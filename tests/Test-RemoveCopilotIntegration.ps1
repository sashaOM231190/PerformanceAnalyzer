[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Remove-CopilotIntegration.ps1'
$fixture = Join-Path $env:TEMP ('pa-remove-test-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('LOCALAPPDATA', 'USERPROFILE', 'COPILOT_HOME')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
function Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Write-Fixture {
    param([string]$Path, [string]$Text)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
try {
    $env:USERPROFILE = Join-Path $fixture 'user'
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    $env:COPILOT_HOME = Join-Path $fixture 'custom-copilot-home'
    $configPath = Join-Path $env:COPILOT_HOME 'mcp-config.json'
    $skill = Join-Path $env:COPILOT_HOME 'skills\performance-analyzer\SKILL.md'
    $otherSkill = Join-Path $env:COPILOT_HOME 'skills\unrelated\SKILL.md'
    $defaultSkill = Join-Path $env:USERPROFILE '.copilot\skills\performance-analyzer\SKILL.md'
    $serverRoot = Join-Path $env:LOCALAPPDATA 'PerformanceAnalyzer\Copilot'
    $server1 = Join-Path $serverRoot '2.5.0-coach.7\PerformanceAnalyzer.Mcp.exe'
    $server2 = Join-Path $serverRoot '2.4.2\PerformanceAnalyzer.Mcp.exe'
    $unrelatedFile = Join-Path $serverRoot '2.5.0-coach.7\keep.txt'
    $unversioned = Join-Path $serverRoot 'other\PerformanceAnalyzer.Mcp.exe'
    $capture = Join-Path $fixture 'PerformanceAnalyzerKit\saved-capture\keep.txt'
    $original = '{"customSetting":{"keep":true},"mcpServers":{"performance-analyzer":{"command":"old.exe"},"unrelated":{"type":"http","url":"https://example.invalid/mcp"}}}'
    Write-Fixture $configPath $original
    foreach ($path in @($skill, $otherSkill, $defaultSkill, $server1, $server2, $unrelatedFile, $unversioned, $capture)) {
        Write-Fixture $path 'preserve'
    }
    & $scriptPath -WhatIf
    Check ((Get-Content -LiteralPath $configPath -Raw) -ceq $original) 'WhatIf preserves exact configuration'
    foreach ($path in @($skill, $server1, $server2)) {
        Check (Test-Path -LiteralPath $path) "WhatIf preserves $path"
    }
    & $scriptPath -Confirm:$false
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Check ($null -eq $config.mcpServers.PSObject.Properties['performance-analyzer']) 'Owned registration removed'
    Check ($config.customSetting.keep -and $config.mcpServers.unrelated.url -eq 'https://example.invalid/mcp') 'Unrelated configuration preserved'
    foreach ($path in @((Split-Path -Parent $skill), $server1, $server2)) {
        Check (-not (Test-Path -LiteralPath $path)) "Owned target removed: $path"
    }
    foreach ($path in @($otherSkill, $defaultSkill, $unrelatedFile, $unversioned, $capture)) {
        Check ((Get-Content -LiteralPath $path -Raw) -eq 'preserve') "Unrelated target preserved: $path"
    }
    $after = Get-Content -LiteralPath $configPath -Raw
    & $scriptPath -Confirm:$false
    Check ((Get-Content -LiteralPath $configPath -Raw) -ceq $after) 'Repeated cleanup does not rewrite configuration'

    Write-Fixture $skill 'preserve'
    foreach ($invalid in @('not-json', '[]', '{"mcpServers":null}')) {
        Write-Fixture $configPath $invalid
        $failed = $false
        try { & $scriptPath -Confirm:$false }
        catch { $failed = $true }
        Check $failed 'Invalid configuration fails explicitly'
        Check ((Get-Content -LiteralPath $configPath -Raw) -ceq $invalid) 'Invalid configuration not overwritten'
        Check (Test-Path -LiteralPath $skill) 'Invalid configuration prevents skill deletion'
    }
    Write-Fixture $configPath '{"customSetting":true}'
    & $scriptPath -Confirm:$false
    Check ((Get-Content -LiteralPath $configPath -Raw) -ceq '{"customSetting":true}') 'Configuration without mcpServers is not rewritten'

    Remove-Item Env:\COPILOT_HOME
    & $scriptPath -Confirm:$false
    Check (-not (Test-Path -LiteralPath $defaultSkill)) 'Default Copilot home is supported without config or CLI'
    Check (-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.copilot\mcp-config.json'))) 'Missing configuration is not created'
    Write-Host 'PASS: preview, repeated removal, custom/default homes, invalid config, versioned binaries and unrelated data preservation.'
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
