[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('LOCALAPPDATA', 'USERPROFILE')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "The $name environment variable is required for per-user cleanup."
    }
}
$copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
    Join-Path $env:USERPROFILE '.copilot'
}
else { $env:COPILOT_HOME }
$configPath = Join-Path $copilotHome 'mcp-config.json'
$skillPath = Join-Path $copilotHome 'skills\performance-analyzer'
$serverRoot = Join-Path $env:LOCALAPPDATA 'PerformanceAnalyzer\Copilot'

function Assert-NoReparsePoint {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing cleanup through a link or reparse point: $($item.FullName)"
        }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
}

# Validate every target before changing configuration or removing files.
$config = $null
$registration = $null
if (Test-Path -LiteralPath $configPath) {
    Assert-NoReparsePoint $configPath
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($null -eq $config -or $config -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Unsupported MCP configuration at '$configPath'; no changes were made."
    }
    $servers = $config.PSObject.Properties['mcpServers']
    if ($null -ne $servers) {
        if ($servers.Value -isnot [System.Management.Automation.PSCustomObject]) {
            throw "Unsupported mcpServers configuration at '$configPath'; no changes were made."
        }
        $registration = $servers.Value.PSObject.Properties['performance-analyzer']
    }
}
if (Test-Path -LiteralPath $skillPath) {
    Assert-NoReparsePoint $skillPath
    foreach ($item in Get-ChildItem -LiteralPath $skillPath -Force -Recurse) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing cleanup of a skill containing a link or reparse point: $($item.FullName)"
        }
    }
}
$serverPaths = @(
    if (Test-Path -LiteralPath $serverRoot) {
        Assert-NoReparsePoint $serverRoot
        foreach ($directory in Get-ChildItem -LiteralPath $serverRoot -Directory -Force) {
            if ($directory.Name -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$') { continue }
            Assert-NoReparsePoint $directory.FullName
            $path = Join-Path $directory.FullName 'PerformanceAnalyzer.Mcp.exe'
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Assert-NoReparsePoint $path
                $path
            }
        }
    }
)

Write-Host 'Close analyzer/Coach and Copilot sessions before cleanup; restart Copilot afterward.'
if ($null -ne $registration -and $PSCmdlet.ShouldProcess($configPath, 'Remove only the performance-analyzer MCP registration')) {
    $config.mcpServers.PSObject.Properties.Remove('performance-analyzer')
    $temporaryPath = Join-Path $copilotHome ("mcp-config.$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllText($temporaryPath, ($config | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($temporaryPath, $configPath, [System.Management.Automation.Language.NullString]::Value)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}
if ((Test-Path -LiteralPath $skillPath) -and $PSCmdlet.ShouldProcess($skillPath, 'Remove the PerformanceAnalyzer skill')) {
    Remove-Item -LiteralPath $skillPath -Recurse -Force
}
foreach ($path in $serverPaths) {
    if ($PSCmdlet.ShouldProcess($path, 'Remove the installed PerformanceAnalyzer MCP binary')) {
        Remove-Item -LiteralPath $path -Force
    }
}
if (-not $WhatIfPreference) {
    Write-Host 'Cleanup finished. Already absent items required no action; any declined actions were left unchanged.'
}
Write-Host 'Copilot CLI, unrelated integrations, package folders and saved captures were not removed.'
Write-Host 'Optional: after saving any captures, manually delete C:\PerformanceAnalyzerKit if that is your extracted kit.'
Write-Host 'The bootstrap uses C:\PerformanceAnalyzer by default. Check your actual installation location before deleting any folder.'
