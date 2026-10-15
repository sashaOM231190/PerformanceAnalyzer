[CmdletBinding()]
param(
    [ValidatePattern('^http://(127\.0\.0\.1|localhost)(:\d+)?/$')]
    [string]$Endpoint = 'http://127.0.0.1:8765/',
    [switch]$InstallCopilot,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$serverSource = Join-Path $PSScriptRoot 'copilot_mcp_server\PerformanceAnalyzer.Mcp.exe'
$skillSource = Join-Path $PSScriptRoot 'copilot_skill'
$versionPath = Join-Path $PSScriptRoot 'version.txt'

foreach ($path in @(
        $serverSource, $versionPath,
        (Join-Path $skillSource 'SKILL.md'),
        (Join-Path $packageRoot 'Analyzer\PerformanceAnalyzer.exe'),
        (Join-Path $packageRoot 'Analyzer\terminal_assets\xterm.js'),
        (Join-Path $packageRoot 'Analyzer\terminal_assets\xterm.css'),
        (Join-Path $packageRoot 'Analyzer\terminal_assets\copilot.svg'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required package file is missing: $path. Extract the entire engineer ZIP before running this script."
    }
}
$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$') {
    throw 'Package version.txt is invalid.'
}

function Find-Copilot {
    Get-Command copilot -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Read-McpConfig {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($null -eq $config -or $config -isnot [pscustomobject]) {
            throw "Unsupported MCP configuration at '$Path'; no integration changes were made."
        }
        if ($null -eq $config.PSObject.Properties['mcpServers']) {
            $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
        }
        elseif ($config.mcpServers -isnot [pscustomobject]) {
            throw "Unsupported mcpServers configuration at '$Path'; no integration changes were made."
        }
        return $config
    }
    return [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
}

$copilot = Find-Copilot
if ($ValidateOnly) {
    Write-Host "Engineer package valid: $version"
    Write-Host "MCP endpoint: $Endpoint"
    if ($null -eq $copilot) {
        Write-Warning 'Copilot CLI is missing. Integration was not installed. Rerun with -InstallCopilot to install it using WinGet.'
    }
    else { Write-Host "Copilot CLI: $($copilot.Source)" }
    return
}
if ($null -eq $copilot) {
    $consent = $InstallCopilot
    if (-not $consent) {
        $answer = Read-Host 'Copilot CLI is missing. Install GitHub.Copilot using WinGet? [y/N]'
        $consent = $answer -match '^(?i:y|yes)$'
    }
    if (-not $consent) {
        throw 'Copilot installation declined. Analyzer remains usable; rerun this script when ready to configure AI integration.'
    }
    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'WinGet is unavailable. Install Microsoft App Installer through your approved software channel, then rerun with -InstallCopilot.'
    }
    & $winget.Source install --id GitHub.Copilot --exact --source winget
    if ($LASTEXITCODE -ne 0) { throw "Copilot installation failed (WinGet exit $LASTEXITCODE)." }
    $env:PATH = @(
        $env:PATH,
        [Environment]::GetEnvironmentVariable('PATH', 'User'),
        [Environment]::GetEnvironmentVariable('PATH', 'Machine'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    ) -join ';'
    $copilot = Find-Copilot
    if ($null -eq $copilot) {
        throw 'WinGet completed but copilot is not discoverable. Open a new PowerShell window and rerun this script.'
    }
}

foreach ($name in @('LOCALAPPDATA', 'USERPROFILE')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "The $name environment variable is required for per-user integration."
    }
}
$copilotRoot = Join-Path $env:LOCALAPPDATA 'PerformanceAnalyzer\Copilot'
$serverDirectory = Join-Path $copilotRoot $version
$serverDestination = Join-Path $serverDirectory 'PerformanceAnalyzer.Mcp.exe'
$copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
    Join-Path $env:USERPROFILE '.copilot'
}
else { $env:COPILOT_HOME }
$skillsRoot = Join-Path $copilotHome 'skills'
$skillDestination = Join-Path $skillsRoot 'performance-analyzer'
$configPath = Join-Path $copilotHome 'mcp-config.json'
$config = Read-McpConfig $configPath
$oldRegistration = $config.mcpServers.PSObject.Properties['performance-analyzer']
$oldValue = if ($null -ne $oldRegistration) { $oldRegistration.Value } else { $null }
$id = [guid]::NewGuid().ToString('N')
$serverBackup = Join-Path $serverDirectory "PerformanceAnalyzer.Mcp.$id.backup"
$skillBackup = Join-Path $skillsRoot ".performance-analyzer-$id.backup"
$serverExisted = Test-Path -LiteralPath $serverDestination -PathType Leaf
$serverChanged = $false
$skillMoved = $false
$skillCreated = $false
$registrationChanged = $false
$cleanupBackups = $false

try {
    New-Item -ItemType Directory -Path $serverDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
    if ($serverExisted) {
        Copy-Item -LiteralPath $serverDestination -Destination $serverBackup
    }
    $serverChanged = $true
    Copy-Item -LiteralPath $serverSource -Destination $serverDestination -Force
    if (Test-Path -LiteralPath $skillDestination) {
        Move-Item -LiteralPath $skillDestination -Destination $skillBackup
        $skillMoved = $true
    }
    New-Item -ItemType Directory -Path $skillDestination | Out-Null
    $skillCreated = $true
    Get-ChildItem -LiteralPath $skillSource -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $skillDestination -Recurse
    }

    $registrationChanged = $true
    if ($null -ne $oldRegistration) {
        & $copilot.Source mcp remove performance-analyzer
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove the existing PerformanceAnalyzer MCP registration.' }
    }
    & $copilot.Source mcp add performance-analyzer `
        --env "PERFORMANCEANALYZER_ENDPOINT=$Endpoint" -- $serverDestination --endpoint $Endpoint
    if ($LASTEXITCODE -ne 0) { throw 'Could not register the PerformanceAnalyzer MCP server.' }
    & $copilot.Source mcp get performance-analyzer
    if ($LASTEXITCODE -ne 0) { throw 'The MCP registration could not be verified.' }
    $installed = Read-McpConfig $configPath
    $entry = $installed.mcpServers.PSObject.Properties['performance-analyzer']
    if ($null -eq $entry -or
        $entry.Value.command -ne $serverDestination -or
        @($entry.Value.args).Count -ne 2 -or
        $entry.Value.args[0] -ne '--endpoint' -or
        $entry.Value.args[1] -ne $Endpoint -or
        $entry.Value.env.PERFORMANCEANALYZER_ENDPOINT -ne $Endpoint) {
        throw 'The registered MCP command or endpoint does not match this installation.'
    }
    $cleanupBackups = $true
}
catch {
    $failure = $_
    try {
        if ($registrationChanged) {
            $current = Read-McpConfig $configPath
            $current.mcpServers.PSObject.Properties.Remove('performance-analyzer')
            if ($null -ne $oldRegistration) {
                $current.mcpServers | Add-Member -NotePropertyName 'performance-analyzer' -NotePropertyValue $oldValue
            }
            $json = $current | ConvertTo-Json -Depth 100
            [IO.File]::WriteAllText($configPath, $json, [Text.UTF8Encoding]::new($false))
        }
        if ($skillCreated) { Remove-Item -LiteralPath $skillDestination -Recurse -Force }
        if ($skillMoved) { Move-Item -LiteralPath $skillBackup -Destination $skillDestination }
        if ($serverChanged) {
            if ($serverExisted) {
                Copy-Item -LiteralPath $serverBackup -Destination $serverDestination -Force
            }
            elseif (Test-Path -LiteralPath $serverDestination) {
                Remove-Item -LiteralPath $serverDestination
            }
        }
        $cleanupBackups = $true
    }
    catch {
        Write-Error "Integration rollback failed: $($_.Exception.Message). Preserve backups at '$serverBackup' and '$skillBackup'." -ErrorAction Continue
    }
    throw "AI integration failed: $($failure.Exception.Message). Close running analyzer/Copilot sessions before retrying."
}
finally {
    if ($cleanupBackups) {
        if (Test-Path -LiteralPath $serverBackup) { Remove-Item -LiteralPath $serverBackup }
        if (Test-Path -LiteralPath $skillBackup) { Remove-Item -LiteralPath $skillBackup -Recurse -Force }
    }
}
Write-Host "AI integration installed/repaired for the current user ($version)."
Write-Host "MCP server: $serverDestination"
Write-Host "Skill: $skillDestination"
Write-Host 'Restart Copilot CLI. Sign in with /login if needed; verify with /mcp and /skills.'
