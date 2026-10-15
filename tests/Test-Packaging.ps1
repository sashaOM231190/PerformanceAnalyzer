[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$ReleaseRoot,
    [Parameter(Mandatory)][string]$LegacyReleaseRoot,
    [string]$RealCopilot,
    [string]$AnalyzerSource
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $repository 'Install-PerformanceAnalyzer.ps1'
$integration = Join-Path $PackageRoot 'Ai Integration\Integrate-Copilot.ps1'
$version = (Get-Content -LiteralPath (Join-Path $PackageRoot 'Ai Integration\version.txt') -Raw).Trim()
if (-not $AnalyzerSource) {
    $AnalyzerSource = Join-Path $repository 'PerformanceAnalyzer-Packaging\worktrees\coach6-analyzer\source\Show-PerfCounterDashboard.ps1'
}
$fixture = Join-Path $env:TEMP ('pa-packaging-test-' + [guid]::NewGuid().ToString('N'))
$node = (Get-Command node -ErrorAction Stop).Source
$saved = @{}
foreach ($name in @('PATH', 'USERPROFILE', 'LOCALAPPDATA', 'WINDIR', 'ProgramFiles', 'ProgramFiles(x86)', 'COPILOT_HOME')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
function Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Must-Fail {
    param([scriptblock]$Action, [string]$Pattern)
    $failed = $false
    try { & $Action | Out-Null }
    catch {
        $failed = $true
        Check ($_.Exception.Message -match $Pattern) "Expected '$Pattern'; got '$($_.Exception.Message)'"
    }
    Check $failed "Expected failure matching $Pattern"
}
function Write-Fixture {
    param([string]$Path, [string]$Text = '')
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Import-Functions {
    param([string]$Path, [string[]]$Names)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    Check ($errors.Count -eq 0) "PowerShell parses: $Path"
    foreach ($name in $Names) {
        $definition = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $name
        })
        Check ($definition.Count -eq 1) "Top-level function $name exists"
        . ([scriptblock]::Create($definition[0].Extent.Text.Replace("function $name {", "function script:$name {")))
    }
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Import-Functions $bootstrap @('Find-TraceTool', 'Show-Prerequisites', 'Assert-PackageFiles', 'Get-EngineerLayout', 'Install-EngineerFiles', 'Test-PackageChecksum')
    Import-Functions $integration @()
    $layout = Get-EngineerLayout $PackageRoot
    Check $layout.Modern 'Combined layout is recognized'
    $undo = Join-Path $PackageRoot 'Ai Integration\Remove-CopilotIntegration.ps1'
    Check (Test-Path -LiteralPath $undo -PathType Leaf) 'Engineer kit includes the undo script'
    Check ((Get-FileHash $undo).Hash -eq (Get-FileHash (Join-Path $repository 'scripts\Remove-CopilotIntegration.ps1')).Hash) 'Packaged undo script matches repository source'
    $legacy = Join-Path $LegacyReleaseRoot 'engineer-kit-staging\PerformanceAnalyzer\2.5.0-coach.7'
    Check (-not (Get-EngineerLayout $legacy).Modern) 'Legacy layout remains recognized'
    $broken = Join-Path $fixture 'broken'
    New-Item -ItemType Directory -Path (Join-Path $broken 'Ai Integration') -Force | Out-Null
    Must-Fail { Get-EngineerLayout $broken } 'missing'
    $source = Join-Path $fixture 'source'
    $destination = Join-Path $fixture 'existing'
    Write-Fixture (Join-Path $source 'Ai Integration\Integrate-Copilot.ps1') 'new'
    Write-Fixture (Join-Path $destination 'Ai Integration\Integrate-Copilot.ps1') 'old'
    Write-Fixture (Join-Path $destination 'saved-capture\keep.txt') 'preserve'
    Install-EngineerFiles $source $destination
    Check ((Get-Content (Join-Path $destination 'Ai Integration\Integrate-Copilot.ps1') -Raw) -eq 'new') 'Same-version installation refreshes files'
    Check ((Get-Content (Join-Path $destination 'saved-capture\keep.txt') -Raw) -eq 'preserve') 'Saved captures remain untouched'
    $checksumFile = Join-Path $fixture 'sample.zip'
    Write-Fixture $checksumFile 'sample'
    Write-Fixture "$checksumFile.sha256" ((Get-FileHash $checksumFile).Hash + '  sample.zip')
    Test-PackageChecksum $checksumFile "$checksumFile.sha256"
    Write-Fixture "$checksumFile.sha256" ('0' * 64)
    Must-Fail { Test-PackageChecksum $checksumFile "$checksumFile.sha256" } 'verification failed'

    $env:WINDIR = Join-Path $fixture 'windows'
    $env:ProgramFiles = Join-Path $fixture 'programs'
    ${env:ProgramFiles(x86)} = Join-Path $fixture 'programs-x86'
    function Get-Command { param($Name, $CommandType, $ErrorAction) return $null }
    Check ($null -eq (Find-TraceTool wpr.exe)) 'Missing WPR is recognized'
    Write-Fixture (Join-Path $env:WINDIR 'System32\wpr.exe')
    Check ((Find-TraceTool wpr.exe) -eq (Join-Path $env:WINDIR 'System32\wpr.exe')) 'System32 WPR is recognized'
    $sdkXperf = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Windows Performance Toolkit\xperf.exe'
    Write-Fixture $sdkXperf
    Check ((Find-TraceTool xperf.exe) -eq $sdkXperf) 'SDK Xperf is found without PATH'
    Import-Functions $AnalyzerSource @('Get-XperfCommand')
    Check ((Get-XperfCommand).Source -eq $sdkXperf) 'Analyzer also resolves SDK Xperf without PATH'
    Remove-Item Function:\Get-Command
    foreach ($name in @('WINDIR', 'ProgramFiles', 'ProgramFiles(x86)')) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name])
    }

    $env:USERPROFILE = Join-Path $fixture 'user'
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    $env:COPILOT_HOME = Join-Path $env:USERPROFILE '.copilot'
    $env:PA_PACKAGE_TEST_ROOT = $fixture
    $bin = Join-Path $fixture 'bin'
    New-Item -ItemType Directory -Path $bin | Out-Null
    $env:PATH = "$bin;$($saved.WINDIR)\System32;$($saved.WINDIR)\System32\WindowsPowerShell\v1.0"
    $fakeScript = Join-Path $PSScriptRoot 'fake-copilot.cjs'
    $template = "@echo off`r`n`"$node`" `"$fakeScript`" %*`r`n"
    Write-Fixture (Join-Path $fixture 'copilot-template.cmd') $template
    & $integration -ValidateOnly -InstallCopilot
    Check (-not (Test-Path (Join-Path $fixture 'calls.jsonl'))) 'ValidateOnly neither installs CLI nor calls MCP'
    function Read-Host { param($Prompt) return 'n' }
    Must-Fail { & $integration } 'declined'
    Remove-Item Function:\Read-Host
    Must-Fail { & $integration -InstallCopilot } 'WinGet is unavailable'
    Write-Fixture (Join-Path $bin 'winget.cmd') "@echo off`r`n`"$node`" `"$fakeScript`" winget %*`r`n"
    $env:PA_PACKAGE_TEST_WINGET_FAIL = '1'
    Must-Fail { & $integration -InstallCopilot } 'WinGet exit 5'
    Remove-Item Env:\PA_PACKAGE_TEST_WINGET_FAIL
    $configPath = Join-Path $env:USERPROFILE '.copilot\mcp-config.json'
    Write-Fixture $configPath '{"customSetting":true,"mcpServers":{"performance-analyzer":{"type":"local","command":"old.exe","args":[],"env":{"PERFORMANCEANALYZER_ENDPOINT":"http://127.0.0.1:9000/"}},"unrelated":{"type":"http","url":"https://example.invalid/mcp","tools":["*"]}}}'
    $otherSkill = Join-Path $env:USERPROFILE '.copilot\skills\unrelated\SKILL.md'
    Write-Fixture $otherSkill 'unrelated skill'
    function Read-Host { param($Prompt) return 'y' }
    & $integration -Endpoint 'http://127.0.0.1:9000/'
    Remove-Item Function:\Read-Host
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Check ($config.mcpServers.'performance-analyzer'.env.PERFORMANCEANALYZER_ENDPOINT -eq 'http://127.0.0.1:9000/') 'Exact endpoint registered'
    Check (($config.mcpServers.'performance-analyzer'.args -join ' ') -eq '--endpoint http://127.0.0.1:9000/') 'Endpoint is passed as MCP command arguments, not just an ignored environment variable'
    Check ($config.mcpServers.unrelated.url -eq 'https://example.invalid/mcp' -and $config.customSetting) 'Unrelated configuration preserved'
    $skillPath = Join-Path $env:USERPROFILE '.copilot\skills\performance-analyzer'
    Write-Fixture (Join-Path $skillPath 'stale.txt') 'stale'
    & $integration
    Check (-not (Test-Path (Join-Path $skillPath 'stale.txt'))) 'Repair replaces stale owned skill files'
    Check ((Get-Content $otherSkill -Raw) -eq 'unrelated skill') 'Repair preserves unrelated skills'
    $before = Get-Content $configPath -Raw | ConvertFrom-Json
    $beforeOwn = $before.mcpServers.'performance-analyzer' | ConvertTo-Json -Depth 20 -Compress
    $serverPath = Join-Path $env:LOCALAPPDATA "PerformanceAnalyzer\Copilot\$version\PerformanceAnalyzer.Mcp.exe"
    $serverHash = (Get-FileHash $serverPath).Hash
    $env:PA_PACKAGE_TEST_ADD_FAIL = '1'
    Must-Fail { & $integration -Endpoint 'http://127.0.0.1:9010/' } 'Could not register'
    Remove-Item Env:\PA_PACKAGE_TEST_ADD_FAIL
    $after = Get-Content $configPath -Raw | ConvertFrom-Json
    Check (($after.mcpServers.'performance-analyzer' | ConvertTo-Json -Depth 20 -Compress) -eq $beforeOwn) 'Failed repair rolls back only the owned registration'
    Check ($after.mcpServers.unrelated.url -eq 'https://example.invalid/mcp') 'Failed repair preserves unrelated registration'
    Check ((Get-FileHash $serverPath).Hash -eq $serverHash) 'Failed repair restores server binary'
    Check (Test-Path (Join-Path $skillPath 'SKILL.md')) 'Failed repair restores skill'
    $calls = @(Get-Content (Join-Path $fixture 'calls.jsonl') | ForEach-Object { ,(ConvertFrom-Json $_) })
    Check (@($calls | Where-Object { $_[0] -eq 'winget' }).Count -eq 2) 'WinGet runs only with explicit consent while CLI is absent'
    $validConfig = Get-Content $configPath -Raw
    Write-Fixture $configPath 'not-json'
    Must-Fail { & $integration } 'Invalid JSON|Invalid object|unexpected|Invalid JSON primitive'
    Check ((Get-Content $configPath -Raw) -eq 'not-json') 'Malformed configuration is not overwritten'
    Write-Fixture $configPath $validConfig
    Write-Fixture $configPath '{"customSetting":true}'
    & $integration
    $emptyConfig = Get-Content $configPath -Raw | ConvertFrom-Json
    Check ($emptyConfig.customSetting -and $null -ne $emptyConfig.mcpServers.PSObject.Properties['performance-analyzer']) 'An existing config without mcpServers is supported'
    Write-Fixture $configPath $validConfig

    if ($RealCopilot) {
        $env:COPILOT_HOME = Join-Path $fixture 'real-cli-home'
        New-Item -ItemType Directory -Path $env:COPILOT_HOME | Out-Null
        & $RealCopilot --no-auto-update mcp add unrelated --transport http 'https://example.invalid/mcp'
        Check ($LASTEXITCODE -eq 0) 'Real CLI can seed an isolated unrelated registration'
        Write-Fixture (Join-Path $bin 'copilot.cmd') "@echo off`r`n`"$RealCopilot`" --no-auto-update %*`r`n"
        & $integration
        & $integration -Endpoint 'http://127.0.0.1:9001/'
        $realConfig = Get-Content (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Raw | ConvertFrom-Json
        Check ($realConfig.mcpServers.'performance-analyzer'.env.PERFORMANCEANALYZER_ENDPOINT -eq 'http://127.0.0.1:9001/') 'Real CLI repairs the exact endpoint in custom COPILOT_HOME'
        Check (($realConfig.mcpServers.'performance-analyzer'.args -join ' ') -eq '--endpoint http://127.0.0.1:9001/') 'Real CLI persists executable endpoint arguments'
        Check ($null -ne $realConfig.mcpServers.PSObject.Properties['unrelated']) 'Real CLI preserves unrelated registration'
        Check (Test-Path (Join-Path $env:COPILOT_HOME 'skills\performance-analyzer\SKILL.md')) 'Custom COPILOT_HOME receives the skill'
        $env:COPILOT_HOME = Join-Path $env:USERPROFILE '.copilot'
        Write-Fixture (Join-Path $bin 'copilot.cmd') $template
        Write-Host 'PASS real Copilot CLI: isolated install/repair, endpoint correction and unrelated registration preservation.'
    }

    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing, $Headers)
        if (-not $OutFile) { throw 'Fixture expects explicit version and file downloads only.' }
        if ($Uri -notmatch '/performanceanalyzer-engineer-analysis-kit-[^/]+\.zip(\.sha256)?$') {
            throw "Bootstrap must download only the engineer ZIP/checksum, not a customer package: $Uri"
        }
        Copy-Item -LiteralPath (Join-Path $env:PA_PACKAGE_DOWNLOAD_FIXTURE ([IO.Path]::GetFileName($Uri))) -Destination $OutFile
    }
    $env:PA_PACKAGE_DOWNLOAD_FIXTURE = $ReleaseRoot
    & $bootstrap -Version $version -ValidateOnly
    $isolatedInstall = Join-Path $fixture 'installed'
    $bootstrapText = Get-Content -LiteralPath $bootstrap -Raw
    $rootAssignment = '$applicationRoot = ''C:\PerformanceAnalyzer'''
    $elevationGuard = 'if (-not $ValidateOnly -and -not (Test-Administrator)) {'
    Check ($bootstrapText.Contains($rootAssignment) -and $bootstrapText.Contains($elevationGuard)) 'Isolated installation overrides match the bootstrap'
    $isolatedBootstrap = $bootstrapText.Replace(
        $rootAssignment, ('$applicationRoot = ''' + $isolatedInstall.Replace("'", "''") + '''')
    ).Replace($elevationGuard, 'if ($false) {')
    Write-Fixture (Join-Path $isolatedInstall "$version\saved-capture\keep.txt") 'preserve'
    & ([scriptblock]::Create($isolatedBootstrap)) -Version $version -SkipCopilotIntegration
    Check (-not (Test-Path -LiteralPath (Join-Path $isolatedInstall 'Packages'))) 'Installation does not create a Packages cache'
    Check (Test-Path -LiteralPath (Join-Path $isolatedInstall "$version\Ai Integration\Remove-CopilotIntegration.ps1")) 'Installation includes the undo script'
    Check ((Get-Content -LiteralPath (Join-Path $isolatedInstall "$version\saved-capture\keep.txt") -Raw) -eq 'preserve') 'Bootstrap preserves existing captures'
    $env:PA_PACKAGE_DOWNLOAD_FIXTURE = $LegacyReleaseRoot
    & $bootstrap -Version '2.5.0-coach.7' -ValidateOnly
    Remove-Item Function:\Invoke-WebRequest
    Write-Host 'PASS packaging: new/legacy bootstrap, same-version refresh, checksums, System32/SDK discovery, CLI consent, missing/failed WinGet, repair, rollback and unrelated settings/skills.'
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    foreach ($name in @('PA_PACKAGE_TEST_ROOT', 'PA_PACKAGE_TEST_WINGET_FAIL', 'PA_PACKAGE_TEST_ADD_FAIL', 'PA_PACKAGE_DOWNLOAD_FIXTURE')) {
        Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
    }
    foreach ($name in @('Get-Command', 'Read-Host', 'Invoke-WebRequest')) {
        Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
