[CmdletBinding()]
param(
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,

  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.SecurityProtocolType]::Tls12

$owner = 'sashaOM231190'
$repository = 'PerformanceAnalyzer'
$repositoryRoot = "https://raw.githubusercontent.com/$owner/$repository/main"
$latestVersionUri = "$repositoryRoot/latest-version.txt"

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)

  return $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )
}

function Invoke-ElevatedBootstrap {
  $arguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    "`"$PSCommandPath`""
  )

  if ($Version) {
    $arguments += @('-Version', $Version)
  }

  $process = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList $arguments `
    -Verb RunAs `
    -Wait `
    -PassThru

  exit $process.ExitCode
}

function Get-ApprovedVersion {
  if ($Version) {
    return $Version
  }

  Write-Host 'Discovering the latest approved version...'

  $response = Invoke-WebRequest `
    -Uri $latestVersionUri `
    -UseBasicParsing `
    -Headers @{
      'User-Agent' = 'PerformanceAnalyzer-Installer'
    }

  $approvedVersion = $response.Content.Trim()

  if ($approvedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version returned by $latestVersionUri"
  }

  return $approvedVersion
}

function Get-ReleaseFile {
  param(
    [Parameter(Mandatory)]
    [string]$Uri,

    [Parameter(Mandatory)]
    [string]$Destination
  )

  Write-Host "Downloading: $([IO.Path]::GetFileName($Destination))"

  Invoke-WebRequest `
    -Uri $Uri `
    -OutFile $Destination `
    -UseBasicParsing `
    -Headers @{
      'User-Agent' = 'PerformanceAnalyzer-Installer'
    }
}

function Test-PackageChecksum {
  param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [Parameter(Mandatory)]
    [string]$ChecksumPath
  )

  $checksumText = Get-Content $ChecksumPath -Raw
  $hashMatch = [regex]::Match(
    $checksumText,
    '(?i)\b[a-f0-9]{64}\b'
  )

  if (-not $hashMatch.Success) {
    throw "Invalid checksum file: $ChecksumPath"
  }

  $expectedHash = $hashMatch.Value.ToUpperInvariant()
  $actualHash = (
    Get-FileHash $PackagePath -Algorithm SHA256
  ).Hash.ToUpperInvariant()

  if ($actualHash -ne $expectedHash) {
    throw "Checksum verification failed: $PackagePath"
  }

  Write-Host "Checksum verified: $([IO.Path]::GetFileName($PackagePath))"
}

function Assert-PackageFiles {
  param(
    [Parameter(Mandatory)]
    [string]$Root,

    [Parameter(Mandatory)]
    [string[]]$RelativePaths,

    [Parameter(Mandatory)]
    [string]$PackageName
  )

  foreach ($relativePath in $RelativePaths) {
    $path = Join-Path $Root $relativePath

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "$PackageName file is missing: $relativePath"
    }
  }
}

if (-not $ValidateOnly -and -not (Test-Administrator)) {
  Write-Host 'Administrator access is required. Opening an elevated window...'
  Invoke-ElevatedBootstrap
}

$approvedVersion = Get-ApprovedVersion
$tag = "v$approvedVersion"
$releaseBase = `
  "https://github.com/$owner/$repository/releases/download/$tag"

$customerPackageName = `
  "performanceanalyzer-customer-capture-kit-$approvedVersion.zip"

$engineerPackageName = `
  "performanceanalyzer-engineer-analysis-kit-$approvedVersion.zip"

$customerChecksumName = "$customerPackageName.sha256"
$engineerChecksumName = "$engineerPackageName.sha256"

$workRoot = Join-Path $env:TEMP (
  'PerformanceAnalyzer-{0}-{1}' -f `
    $approvedVersion,
    [guid]::NewGuid().ToString('N')
)

$downloadRoot = Join-Path $workRoot 'downloads'
$customerExtractRoot = Join-Path $workRoot 'customer'
$engineerExtractRoot = Join-Path $workRoot 'engineer'

$customerZip = Join-Path $downloadRoot $customerPackageName
$customerChecksum = Join-Path $downloadRoot $customerChecksumName
$engineerZip = Join-Path $downloadRoot $engineerPackageName
$engineerChecksum = Join-Path $downloadRoot $engineerChecksumName

try {
  New-Item -ItemType Directory -Path $downloadRoot | Out-Null
  New-Item -ItemType Directory -Path $customerExtractRoot | Out-Null
  New-Item -ItemType Directory -Path $engineerExtractRoot | Out-Null

  Get-ReleaseFile `
    -Uri "$releaseBase/$customerPackageName" `
    -Destination $customerZip

  Get-ReleaseFile `
    -Uri "$releaseBase/$customerChecksumName" `
    -Destination $customerChecksum

  Get-ReleaseFile `
    -Uri "$releaseBase/$engineerPackageName" `
    -Destination $engineerZip

  Get-ReleaseFile `
    -Uri "$releaseBase/$engineerChecksumName" `
    -Destination $engineerChecksum

  Test-PackageChecksum `
    -PackagePath $customerZip `
    -ChecksumPath $customerChecksum

  Test-PackageChecksum `
    -PackagePath $engineerZip `
    -ChecksumPath $engineerChecksum

  Expand-Archive `
    -LiteralPath $customerZip `
    -DestinationPath $customerExtractRoot

  Expand-Archive `
    -LiteralPath $engineerZip `
    -DestinationPath $engineerExtractRoot

  $customerRoot = Join-Path $customerExtractRoot `
    "PerformanceAnalyzer\$approvedVersion"

  $engineerRoot = Join-Path $engineerExtractRoot `
    "PerformanceAnalyzer\$approvedVersion"

  Assert-PackageFiles `
    -Root $customerRoot `
    -PackageName 'Customer package' `
    -RelativePaths @(
      'readme.txt'
      'start-capture.cmd'
      'capture_tools\Capture-StorageDiagnostics.ps1'
      'capture_tools\diskspd.exe'
      'capture_tools\PerformanceAnalyzer-Minifilter.wprp'
    )

  Assert-PackageFiles `
    -Root $engineerRoot `
    -PackageName 'Engineer package' `
    -RelativePaths @(
      'readme.txt'
      'install.cmd'
      'analyzer\PerformanceAnalyzer.exe'
      'copilot_mcp_server\PerformanceAnalyzer.Mcp.exe'
      'copilot_skill\SKILL.md'
      'setup_files\install.ps1'
      'setup_files\version.txt'
    )

  $packageVersion = (
    Get-Content (Join-Path $engineerRoot 'setup_files\version.txt') -Raw
  ).Trim()

  if ($packageVersion -ne $approvedVersion) {
    throw "Engineer package version is $packageVersion; expected $approvedVersion."
  }

  if ($ValidateOnly) {
    & (Join-Path $engineerRoot 'analyzer\PerformanceAnalyzer.exe') --version
    Write-Host "PerformanceAnalyzer $approvedVersion packages are valid."
    return
  }

  $applicationRoot = 'C:\PerformanceAnalyzer'
  $installRoot = Join-Path $applicationRoot $approvedVersion
  $customerPackageRoot = Join-Path $applicationRoot `
    "Packages\$approvedVersion"

  New-Item `
    -ItemType Directory `
    -Path $applicationRoot `
    -Force |
    Out-Null

  New-Item `
    -ItemType Directory `
    -Path $customerPackageRoot `
    -Force |
    Out-Null

  if (-not (Test-Path -LiteralPath $installRoot)) {
    Move-Item `
      -LiteralPath $engineerRoot `
      -Destination $installRoot
  }
  else {
    Assert-PackageFiles `
      -Root $installRoot `
      -PackageName 'Existing engineer installation' `
      -RelativePaths @(
        'analyzer\PerformanceAnalyzer.exe'
        'copilot_mcp_server\PerformanceAnalyzer.Mcp.exe'
        'copilot_skill\SKILL.md'
        'setup_files\install.ps1'
        'setup_files\version.txt'
      )

    Write-Host "Using existing engineer installation: $installRoot"
  }

  Copy-Item `
    -LiteralPath $customerZip `
    -Destination $customerPackageRoot `
    -Force

  Copy-Item `
    -LiteralPath $customerChecksum `
    -Destination $customerPackageRoot `
    -Force

  $packageInstaller = Join-Path $installRoot 'setup_files\install.ps1'

  & powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $packageInstaller

  if ($LASTEXITCODE -ne 0) {
    throw "Copilot integration installation failed with exit code $LASTEXITCODE."
  }

  $analyzerPath = Join-Path $installRoot `
    'analyzer\PerformanceAnalyzer.exe'

  & $analyzerPath --version

  copilot mcp get performance-analyzer

  if ($LASTEXITCODE -ne 0) {
    throw 'The MCP registration could not be verified.'
  }

  Write-Host ''
  Write-Host 'PerformanceAnalyzer installation completed.'
  Write-Host "Engineer tools: $installRoot"
  Write-Host (
    "Customer kit:   $customerPackageRoot\$customerPackageName"
  )
  Write-Host ''
  Write-Host 'Restart GitHub Copilot CLI before using the integration.'
}
finally {
  if (Test-Path -LiteralPath $workRoot) {
    Remove-Item `
      -LiteralPath $workRoot `
      -Recurse `
      -Force
  }
}
