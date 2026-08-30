# Building a PowerShell bootstrap installer for PerformanceAnalyzer

This guide explains the complete installation process manually before showing
how the same operations can be combined into a future bootstrap installer.

The objective is to let an end user run one PowerShell command that:

1. discovers a PerformanceAnalyzer GitHub Release;
2. downloads the package and checksum;
3. verifies the package;
4. extracts it into a versioned local directory;
5. installs the MCP server and Copilot skill;
6. verifies the installation;
7. explains what the analyzer and capture script do;
8. prints the exact commands needed to use them.

This document is intentionally a learning guide. The public repository does
not yet include the bootstrap `install.ps1` described here.

## 1. Understand the two installation layers

PerformanceAnalyzer has a portable tool layer and a per-user Copilot layer.

### Portable tool layer

These files can run directly from an extracted package:

```text
analyzer\
  performanceanalyzer.exe
  terminal_assets\

data_capture_tools\
  capture-storagediagnostics.ps1
  diskspd.exe
  performanceanalyzer-minifilter.wprp
```

The analyzer and capture tools do not have to be copied into `Program Files`.
They only need to remain together with their adjacent dependencies.

### Per-user Copilot layer

The package's existing `setup_files\install.ps1` performs these operations:

1. validates the packaged analyzer, capture script, terminal assets, MCP
   executable, skill, and version;
2. copies the MCP executable to:

   ```text
   %LOCALAPPDATA%\PerformanceAnalyzer\Copilot\<version>\
   ```

3. copies the skill to:

   ```text
   %USERPROFILE%\.copilot\skills\performance-analyzer\
   ```

4. removes an older `performance-analyzer` MCP registration when present;
5. registers the versioned MCP executable with GitHub Copilot CLI;
6. verifies the resulting registration.

Running `install.cmd` invokes that PowerShell installer.

The future bootstrap adds a layer before this existing installer: downloading,
verifying, and extracting the portable package.

## 2. Prerequisites

Use Windows PowerShell or PowerShell 7.

Confirm PowerShell can find GitHub Copilot CLI:

```powershell
Get-Command copilot
copilot --version
```

Inspect the existing MCP configuration:

```powershell
copilot mcp list
```

The package installation itself is per-user and should not require
administrator privileges. Administrator privileges are required later when
the storage capture script starts ETW, PerfMon, or WPR providers.

## 3. Define the release and local paths

For a fixed 2.3.0 installation:

```powershell
$owner = 'sashaOM231190'
$repository = 'PerformanceAnalyzer'
$version = '2.3.0'
$tag = "v$version"

$packageName =
    "performanceanalyzer-complete-package-$version.zip"
$checksumName = "$packageName.sha256"

$releaseBase =
    "https://github.com/$owner/$repository/releases/download/$tag"

$downloadRoot = Join-Path $env:TEMP `
    "PerformanceAnalyzer-$version-download"
$installRoot = Join-Path $env:LOCALAPPDATA `
    "PerformanceAnalyzer\$version"

$zipPath = Join-Path $downloadRoot $packageName
$checksumPath = Join-Path $downloadRoot $checksumName
```

Create a clean temporary download directory:

```powershell
if (Test-Path -LiteralPath $downloadRoot) {
    Remove-Item -LiteralPath $downloadRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $downloadRoot -Force |
    Out-Null
```

A production bootstrap should use a unique temporary directory and delete only
that explicitly resolved directory during cleanup.

## 4. Download a fixed release manually

Download the ZIP:

```powershell
Invoke-WebRequest `
    -Uri "$releaseBase/$packageName" `
    -OutFile $zipPath
```

Download the checksum:

```powershell
Invoke-WebRequest `
    -Uri "$releaseBase/$checksumName" `
    -OutFile $checksumPath
```

Confirm both files exist:

```powershell
Get-Item $zipPath, $checksumPath
```

## 5. Discover the latest release automatically

A bootstrap installer should normally ask the GitHub Releases API for the
latest published release:

```powershell
$releaseUri =
    "https://api.github.com/repos/$owner/$repository/releases/latest"

$release = Invoke-RestMethod `
    -Uri $releaseUri `
    -Headers @{ Accept = 'application/vnd.github+json' }

$release.tag_name
$release.name
```

Select the ZIP asset:

```powershell
$zipAsset = $release.assets |
    Where-Object {
        $_.name -match '^performanceanalyzer-complete-package-' -and
        $_.name -like '*.zip'
    } |
    Select-Object -First 1
```

Select its checksum:

```powershell
$checksumAsset = $release.assets |
    Where-Object {
        $_.name -eq "$($zipAsset.name).sha256"
    } |
    Select-Object -First 1
```

Fail explicitly if either asset is missing:

```powershell
if ($null -eq $zipAsset) {
    throw 'The latest release does not contain a package ZIP.'
}

if ($null -eq $checksumAsset) {
    throw 'The latest release does not contain a SHA-256 file.'
}
```

Download using each asset's `browser_download_url`:

```powershell
Invoke-WebRequest `
    -Uri $zipAsset.browser_download_url `
    -OutFile $zipPath

Invoke-WebRequest `
    -Uri $checksumAsset.browser_download_url `
    -OutFile $checksumPath
```

### Fixed version versus latest version

Use a fixed version when:

- reproducing a known environment;
- testing an installer;
- rolling out to a controlled group;
- troubleshooting a specific release.

Use the latest-release API when:

- installing interactively;
- the user explicitly requested the newest stable release;
- the bootstrap clearly prints the selected version before installation.

## 6. Verify SHA-256 before extraction

Read the expected hash:

```powershell
$checksumText = Get-Content `
    -LiteralPath $checksumPath `
    -Raw

$hashMatch = [regex]::Match(
    $checksumText,
    '(?i)\b[a-f0-9]{64}\b')

if (-not $hashMatch.Success) {
    throw 'The checksum file does not contain a valid SHA-256 value.'
}

$expectedHash = $hashMatch.Value.ToUpperInvariant()
```

Calculate the downloaded ZIP hash:

```powershell
$actualHash = (
    Get-FileHash `
        -LiteralPath $zipPath `
        -Algorithm SHA256
).Hash.ToUpperInvariant()
```

Compare the two values:

```powershell
if ($actualHash -ne $expectedHash) {
    throw (
        "Package verification failed.`n" +
        "Expected: $expectedHash`n" +
        "Actual:   $actualHash"
    )
}

Write-Host "SHA-256 verified: $actualHash"
```

Do not extract or execute a package when the checksum does not match.

For PerformanceAnalyzer 2.3.0, the expected ZIP hash is:

```text
BF66C993C9F8FE898E1A36F837E0B71E7AD3CF9D26DFD5FEBEF6A5337B84B517
```

## 7. Extract into a versioned directory

The 2.3.0 ZIP contains the package files directly at its root. It does not add
another enclosing directory.

Example extraction:

```powershell
if (Test-Path -LiteralPath $installRoot) {
    throw (
        "PerformanceAnalyzer $version is already installed at " +
        "'$installRoot'."
    )
}

New-Item -ItemType Directory -Path $installRoot -Force |
    Out-Null

Expand-Archive `
    -LiteralPath $zipPath `
    -DestinationPath $installRoot
```

Confirm the expected package entry points:

```powershell
$requiredPaths = @(
    'install.cmd'
    'setup_files\install.ps1'
    'setup_files\version.txt'
    'analyzer\performanceanalyzer.exe'
    'data_capture_tools\capture-storagediagnostics.ps1'
    'copilot_mcp_server\performanceanalyzer.mcp.exe'
    'copilot_skill\skill.md'
)

foreach ($relativePath in $requiredPaths) {
    $path = Join-Path $installRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "The extracted package is missing '$relativePath'."
    }
}
```

### Safer staging pattern

A production bootstrap should:

1. extract into a temporary staging directory;
2. validate every required file;
3. move the validated staging directory to the final versioned path.

This avoids leaving a partially extracted installation if extraction fails.

## 8. Validate the package without changing Copilot

The packaged installer supports `-ValidateOnly`:

```powershell
$packageInstaller = Join-Path $installRoot `
    'setup_files\install.ps1'

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $packageInstaller `
    -ValidateOnly

if ($LASTEXITCODE -ne 0) {
    throw 'Package validation failed.'
}
```

Validation checks:

- packaged MCP executable;
- skill entry point;
- version file;
- analyzer executable;
- xterm.js and xterm.css;
- Copilot logo;
- capture script;
- availability of GitHub Copilot CLI.

## 9. Install the MCP server and skill

Run the package installer:

```powershell
& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $packageInstaller `
    -Endpoint 'http://127.0.0.1:8765/'

if ($LASTEXITCODE -ne 0) {
    throw 'PerformanceAnalyzer Copilot integration installation failed.'
}
```

Equivalent interactive command from the extracted directory:

```powershell
.\install.cmd
```

The installer copies the MCP executable to:

```text
%LOCALAPPDATA%\PerformanceAnalyzer\Copilot\2.3.0\
PerformanceAnalyzer.Mcp.exe
```

It installs the skill under:

```text
%USERPROFILE%\.copilot\skills\performance-analyzer\
```

It then executes the equivalent of:

```powershell
copilot mcp remove performance-analyzer

copilot mcp add performance-analyzer -- `
  "<installed PerformanceAnalyzer.Mcp.exe>" `
  --endpoint http://127.0.0.1:8765/
```

The remove operation is only performed when an existing registration is
present.

## 10. Verify the installation manually

Verify the portable analyzer:

```powershell
$analyzerPath = Join-Path $installRoot `
    'analyzer\performanceanalyzer.exe'

& $analyzerPath --version
```

Verify the capture script:

```powershell
$capturePath = Join-Path $installRoot `
    'data_capture_tools\capture-storagediagnostics.ps1'

Test-Path -LiteralPath $capturePath
```

Verify the installed MCP executable:

```powershell
$installedMcp = Join-Path $env:LOCALAPPDATA `
    'PerformanceAnalyzer\Copilot\2.3.0\PerformanceAnalyzer.Mcp.exe'

Test-Path -LiteralPath $installedMcp
```

Verify the skill:

```powershell
$installedSkill = Join-Path $HOME `
    '.copilot\skills\performance-analyzer\SKILL.md'

Test-Path -LiteralPath $installedSkill
```

Verify Copilot registration:

```powershell
copilot mcp get performance-analyzer
```

Inside a restarted Copilot CLI session, inspect:

```text
/mcp
/skills
```

The `performance-analyzer` MCP server and skill should both be listed.

## 11. Explain what was installed

The future bootstrap should print a concise explanation after successful
verification.

### Analyzer description

Suggested text:

```text
Analyzer:
PerformanceAnalyzer opens an existing Windows storage capture and correlates
PerfMon counters, Storport request timing, process-volume I/O, Minifilter
callbacks, disk topology, capture health, and optional DiskSpd baselines.
It presents the results in a local browser dashboard.
```

Suggested command:

```powershell
& $analyzerPath `
  'C:\PerfLogs\StorageCapture-YYYYMMDD-HHMMSS'
```

### Capture script description

Suggested text:

```text
Capture tool:
Capture-StorageDiagnostics.ps1 collects the files consumed by the analyzer.
A standard capture records PerfMon, Storport, process-volume I/O, disk
mapping, and a manifest. Optional switches add Minifilter tracing or a
DiskSpd baseline.

The capture script must be run from an elevated PowerShell window.
```

Suggested commands:

```powershell
# Standard capture
& $capturePath

# Include Minifilter activity
& $capturePath -MiniFilter

# Collect an interactive DiskSpd baseline
& $capturePath -SetBaseline
```

### Copilot description

Suggested text:

```text
Copilot integration:
The performance-analyzer MCP server and skill are installed for the current
user. Start PerformanceAnalyzer with a capture, select the Copilot button,
and ask Copilot to analyze the loaded capture.
```

## 12. Suggested final success message

```text
PerformanceAnalyzer 2.3.0 is ready to use.

Installed package:
  %LOCALAPPDATA%\PerformanceAnalyzer\2.3.0

Analyzer:
  Opens and correlates existing Windows storage diagnostic captures.

Run:
  <install path>\analyzer\performanceanalyzer.exe <capture folder>

Capture tool:
  Collects PerfMon, Storport, process-volume, Minifilter, disk mapping,
  manifest, and optional DiskSpd baseline data.

Run from an elevated PowerShell window:
  <install path>\data_capture_tools\capture-storagediagnostics.ps1

Copilot integration:
  MCP server registered: performance-analyzer
  Skill installed: performance-analyzer

Restart Copilot CLI before the first use.
Installation verified. PerformanceAnalyzer is ready to use.
```

The message should only say "ready to use" after every required validation
succeeds.

## 13. Failure messages

Avoid generic messages such as `Installation failed`.

Report the exact missing or failed component:

```text
GitHub Copilot CLI is not installed or is not available on PATH.
The GitHub Release does not contain the package checksum.
Package SHA-256 verification failed.
The extracted package is missing analyzer\performanceanalyzer.exe.
The packaged skill entry point was not found.
The MCP server was copied but registration verification failed.
The installed PerformanceAnalyzer skill could not be found.
```

Do not continue after checksum, extraction, or registration validation fails.

## 14. Manual removal

Remove only the Copilot integration:

```powershell
$uninstaller = Join-Path $installRoot `
    'setup_files\uninstall.ps1'

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $uninstaller
```

This removes:

- the `performance-analyzer` MCP registration;
- the installed Copilot skill;
- all versioned MCP executables under
  `%LOCALAPPDATA%\PerformanceAnalyzer\Copilot`.

It does not remove:

- the portable package under `$installRoot`;
- storage captures;
- analyzer cache files.

After the uninstaller completes, remove the specific versioned portable
directory if desired:

```powershell
Remove-Item -LiteralPath $installRoot -Recurse -Force
```

Always confirm `$installRoot` contains the expected explicit versioned path
before deleting it.

## 15. Mapping manual steps to bootstrap functions

The future bootstrap can be divided into small functions:

| Function | Responsibility |
|---|---|
| `Get-PerformanceAnalyzerRelease` | Select latest or requested GitHub Release. |
| `Get-ReleaseAsset` | Locate ZIP and checksum assets by exact name. |
| `Save-ReleaseAsset` | Download one asset with clear errors. |
| `Test-PackageHash` | Parse and compare SHA-256 values. |
| `Expand-ValidatedPackage` | Extract to staging and validate required paths. |
| `Install-PortablePackage` | Move staging into the final versioned directory. |
| `Install-CopilotIntegration` | Invoke the packaged installer. |
| `Test-PerformanceAnalyzerInstallation` | Verify analyzer, capture, MCP, skill, and registration. |
| `Write-InstallationSummary` | Explain the tools and print exact commands. |
| `Uninstall-PerformanceAnalyzer` | Invoke packaged removal and remove one selected portable version. |

Keeping these responsibilities separate makes the bootstrap easier to test and
prevents a single large script from hiding partial failures.

## 16. Proposed bootstrap parameters

```powershell
param(
    [string]$Version,

    [string]$InstallDirectory,

    [ValidatePattern(
        '^http://(127\.0\.0\.1|localhost)(:\d+)?/$')]
    [string]$Endpoint = 'http://127.0.0.1:8765/',

    [switch]$Force,

    [switch]$ValidateOnly,

    [switch]$Uninstall
)
```

Recommended meanings:

- `-Version 2.3.0`: install one specific release;
- no `-Version`: install the latest stable release;
- `-InstallDirectory`: override the default portable package location;
- `-Endpoint`: configure the analyzer loopback endpoint;
- `-Force`: replace an existing installation of the same version;
- `-ValidateOnly`: download and validate without installing;
- `-Uninstall`: remove a selected installed version and Copilot integration.

## 17. Recommended end-user command

During development and review, use the safer two-step approach:

```powershell
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/install.ps1 `
  -OutFile .\install-performanceanalyzer.ps1

notepad .\install-performanceanalyzer.ps1

.\install-performanceanalyzer.ps1
```

Only after the bootstrap is reviewed, versioned, and trusted should the README
offer the shorter form:

```powershell
irm https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/install.ps1 |
  iex
```

The pipeline form is convenient but gives the user less opportunity to inspect
the script before executing it.

## 18. Development and release checklist

Before publishing the future bootstrap:

1. Test installation on a machine without PerformanceAnalyzer.
2. Test installation when an older MCP registration exists.
3. Test installation when the same version already exists.
4. Test a wrong checksum.
5. Test a missing ZIP or checksum asset.
6. Test without Copilot CLI on `PATH`.
7. Test a custom loopback port.
8. Test paths containing spaces.
9. Test `-ValidateOnly`.
10. Test uninstall without deleting captures.
11. Confirm the final success message is printed only after verification.
12. Publish the bootstrap change before documenting the one-line command.

