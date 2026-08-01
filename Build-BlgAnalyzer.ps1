<#
.SYNOPSIS
Builds BlgAnalyzer.exe with the dashboard PowerShell script embedded.
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot 'BlgAnalyzer.exe'
}

if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR `
        'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
        throw 'Windows PowerShell 5.1 is required to build BlgAnalyzer.exe.'
    }

    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $PSCommandPath -OutputPath $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE."
    }
    return
}

$sourcePath = Join-Path $PSScriptRoot 'BlgAnalyzerHost.cs'
$scriptPath = Join-Path $PSScriptRoot 'Show-PerfCounterDashboard.ps1'
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compilerPath = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "C# host source was not found: $sourcePath"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Dashboard script was not found: $scriptPath"
}
if (-not $compilerPath) {
    throw '.NET Framework C# compiler was not found.'
}

$automationAssembly = [System.Management.Automation.PSObject].Assembly.Location
$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$arguments = @(
    '/nologo'
    '/target:exe'
    '/platform:anycpu'
    '/optimize+'
    "/out:$resolvedOutputPath"
    "/reference:$automationAssembly"
    "/resource:$scriptPath,BlgDashboardScript"
    $sourcePath
)

& $compilerPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "C# compiler exited with code $LASTEXITCODE."
}

$output = Get-Item -LiteralPath $resolvedOutputPath
Write-Host ("Built {0} ({1:N0} bytes)" -f $output.FullName, $output.Length)
