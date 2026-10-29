$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\Install-PerformanceAnalyzer.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $installer, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw 'Installer has PowerShell syntax errors.' }
$function = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-ApprovedVersion'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

function Invoke-WebRequest {
  param($Uri, [switch]$UseBasicParsing, $Headers)
  if ($Uri -ne $latestVersionUri) { throw 'Unexpected version URL.' }
  $script:requestCount++
  [pscustomobject]@{ Content = $script:responseContent }
}

$latestVersionUri = 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/latest-version.txt'
$Version = ''
$script:requestCount = 0
$currentVersion = (Get-Content (Join-Path $PSScriptRoot '..\latest-version.txt') -Raw).Trim()
foreach ($value in @($currentVersion, '2.4.2', '3.0.0', '3.0.0-preview.1')) {
  $script:responseContent = " $value`r`n"
  if ((Get-ApprovedVersion) -ne $value) { throw "Failed to resolve $value" }
}
foreach ($value in @('', 'v2.5.0-coach.6', '2.5', '2.5.0-', '../2.5.0', '2.5.0;whoami')) {
  $script:responseContent = $value
  $rejected = $false
  try { $null = Get-ApprovedVersion }
  catch { $rejected = $true }
  if (-not $rejected) { throw "Accepted invalid version: $value" }
}
$Version = '2.4.2'
$requestsBeforeOverride = $script:requestCount
if ((Get-ApprovedVersion) -ne $Version) { throw 'Explicit version ignored.' }
if ($script:requestCount -ne $requestsBeforeOverride) {
  throw 'Explicit version should not fetch the default version.'
}
Write-Host 'Installer version resolution passed.'
