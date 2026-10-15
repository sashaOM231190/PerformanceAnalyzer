[CmdletBinding()]
param(
  [ValidatePattern(
    '^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$')]
  [string]$Version,

  [switch]$ValidateOnly,
  [switch]$InstallCopilot,
  [switch]$SkipCopilotIntegration
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
  if ($InstallCopilot) { $arguments += '-InstallCopilot' }
  if ($SkipCopilotIntegration) { $arguments += '-SkipCopilotIntegration' }

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

function Find-TraceTool {
  param([ValidateSet('wpr.exe', 'xperf.exe')][string]$Name)
  $candidates = @(
    (Join-Path $env:WINDIR "Sysnative\$Name"),
    (Join-Path $env:WINDIR "System32\$Name")
  )
  $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
  if ($null -ne $command) { $candidates += $command.Source }
  foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not [string]::IsNullOrWhiteSpace($base)) {
      $candidates += Join-Path $base "Windows Kits\10\Windows Performance Toolkit\$Name"
    }
  }
  $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}

function Show-Prerequisites {
  foreach ($name in @('wpr.exe', 'xperf.exe')) {
    $path = Find-TraceTool $name
    if ($path) { Write-Host "$name found: $path" }
    else {
      $purpose = if ($name -eq 'wpr.exe') { '-MiniFilter capture' } else { 'ETL analysis' }
      Write-Warning "$name MISSING: required for $purpose. Install the Windows Performance Toolkit from the Windows ADK: https://learn.microsoft.com/windows-hardware/get-started/adk-install"
    }
  }
}

function Get-EngineerLayout {
  param([string]$Root)
  $modern = Test-Path -LiteralPath (Join-Path $Root 'Ai Integration') -PathType Container
  if ($modern) {
    $installer = 'Ai Integration\Integrate-Copilot.ps1'
    $versionFile = 'Ai Integration\version.txt'
    $required = @(
      'readme.txt', 'Analyzer\PerformanceAnalyzer.exe',
      'Analyzer\terminal_assets\xterm.js', 'Analyzer\terminal_assets\xterm.css',
      'Analyzer\terminal_assets\copilot.svg', $installer, $versionFile,
      'Ai Integration\copilot_mcp_server\PerformanceAnalyzer.Mcp.exe',
      'Ai Integration\copilot_skill\SKILL.md',
      'CaptureKit\readme.txt', 'CaptureKit\capture_tools\Capture-StorageDiagnostics.ps1',
      'CaptureKit\capture_tools\diskspd.exe',
      'CaptureKit\capture_tools\PerformanceAnalyzer-Minifilter.wprp'
    )
  }
  else {
    $installer = 'setup_files\install.ps1'
    $versionFile = 'setup_files\version.txt'
    $required = @(
      'readme.txt', 'install.cmd', 'analyzer\PerformanceAnalyzer.exe',
      'copilot_mcp_server\PerformanceAnalyzer.Mcp.exe', 'copilot_skill\SKILL.md',
      $installer, $versionFile
    )
  }
  Assert-PackageFiles -Root $Root -PackageName 'Engineer package' -RelativePaths $required
  [pscustomobject]@{
    Modern = $modern
    Installer = $installer
    VersionFile = $versionFile
    Analyzer = 'Analyzer\PerformanceAnalyzer.exe'
  }
}

function Install-EngineerFiles {
  param([string]$Source, [string]$Destination)
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
  Write-Host "Engineer files installed/refreshed: $Destination"
}

if (-not $ValidateOnly -and -not (Test-Administrator)) {
  Write-Host 'Administrator access is required. Opening an elevated window...'
  Invoke-ElevatedBootstrap
}

$approvedVersion = Get-ApprovedVersion
$tag = "v$approvedVersion"
$releaseBase = `
  "https://github.com/$owner/$repository/releases/download/$tag"

$engineerPackageName = `
  "performanceanalyzer-engineer-analysis-kit-$approvedVersion.zip"

$engineerChecksumName = "$engineerPackageName.sha256"

$workRoot = Join-Path $env:TEMP (
  'PerformanceAnalyzer-{0}-{1}' -f `
    $approvedVersion,
    [guid]::NewGuid().ToString('N')
)

$downloadRoot = Join-Path $workRoot 'downloads'
$engineerExtractRoot = Join-Path $workRoot 'engineer'

$engineerZip = Join-Path $downloadRoot $engineerPackageName
$engineerChecksum = Join-Path $downloadRoot $engineerChecksumName

Show-Prerequisites

try {
  New-Item -ItemType Directory -Path $downloadRoot | Out-Null
  New-Item -ItemType Directory -Path $engineerExtractRoot | Out-Null

  Get-ReleaseFile `
    -Uri "$releaseBase/$engineerPackageName" `
    -Destination $engineerZip

  Get-ReleaseFile `
    -Uri "$releaseBase/$engineerChecksumName" `
    -Destination $engineerChecksum

  Test-PackageChecksum `
    -PackagePath $engineerZip `
    -ChecksumPath $engineerChecksum

  Expand-Archive `
    -LiteralPath $engineerZip `
    -DestinationPath $engineerExtractRoot

  $engineerRoot = Join-Path $engineerExtractRoot `
    "PerformanceAnalyzer\$approvedVersion"

  $layout = Get-EngineerLayout -Root $engineerRoot

  $packageVersion = (
    Get-Content (Join-Path $engineerRoot $layout.VersionFile) -Raw
  ).Trim()

  if ($packageVersion -ne $approvedVersion) {
    throw "Engineer package version is $packageVersion; expected $approvedVersion."
  }

  if ($ValidateOnly) {
    & (Join-Path $engineerRoot $layout.Analyzer) --version
    if ($LASTEXITCODE -ne 0) { throw 'Packaged analyzer validation failed.' }
    if ($layout.Modern) {
      & (Join-Path $engineerRoot $layout.Installer) -ValidateOnly
    }
    Write-Host "PerformanceAnalyzer $approvedVersion engineer package is valid."
    return
  }

  $applicationRoot = 'C:\PerformanceAnalyzer'
  $installRoot = Join-Path $applicationRoot $approvedVersion
  New-Item `
    -ItemType Directory `
    -Path $applicationRoot `
    -Force |
    Out-Null

  Install-EngineerFiles -Source $engineerRoot -Destination $installRoot

  if (-not $SkipCopilotIntegration) {
    $packageInstaller = Join-Path $installRoot $layout.Installer
    $integrationArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $packageInstaller)
    if ($layout.Modern -and $InstallCopilot) { $integrationArguments += '-InstallCopilot' }
    & powershell.exe @integrationArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Copilot integration failed (exit $LASTEXITCODE). Engineer files are installed at '$installRoot'; rerun '$packageInstaller' to repair integration."
    }
  }
  else { Write-Warning 'AI integration was skipped; only the engineer files were installed.' }

  $analyzerPath = Join-Path $installRoot `
    $layout.Analyzer

  & $analyzerPath --version
  if ($LASTEXITCODE -ne 0) {
    throw 'Installed analyzer version check failed.'
  }

  Write-Host ''
  Write-Host 'PerformanceAnalyzer installation completed.'
  Write-Host "Engineer tools: $installRoot"
  Write-Host "Customer-only ZIP/checksum (download separately when needed): https://github.com/$owner/$repository/releases/tag/$tag"
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
