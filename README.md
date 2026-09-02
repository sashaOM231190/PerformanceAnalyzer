# PerformanceAnalyzer

PerformanceAnalyzer is distributed as two role-specific Windows packages:

| Package | Audience | Purpose |
| --- | --- | --- |
| Customer capture kit | External customers | Collect storage diagnostics for support |
| Engineer analysis kit | Support engineers | Analyze captures with the desktop analyzer and Copilot integration |

The packages are intentionally separate. Customers do not receive the analyzer,
MCP server, Copilot skill, or embedded terminal.

## Download

[Download PerformanceAnalyzer 2.4.1](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.4.1)

Release assets:

- `performanceanalyzer-customer-capture-kit-2.4.1.zip`
- `performanceanalyzer-customer-capture-kit-2.4.1.zip.sha256`
- `performanceanalyzer-engineer-analysis-kit-2.4.1.zip`
- `performanceanalyzer-engineer-analysis-kit-2.4.1.zip.sha256`

Verify each ZIP against its matching SHA-256 file before extraction.

### Coach prerelease

PerformanceAnalyzer `2.5.0-coach.2` introduces an educational Coach workflow.
On launch it offers a consent-based tour of every graph category available in
the capture. Before arranging an investigation, Coach asks what the engineer
is looking for. Capture-specific evidence remains locked until the engineer
records an observation, correlation, and hypothesis. There is no urgency
bypass.

[Download Coach 2.5.0-coach.2](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.5.0-coach.2)

Install this prerelease explicitly:

```powershell
$path = Join-Path $env:TEMP 'Install-PerformanceAnalyzer.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/Install-PerformanceAnalyzer.ps1' -OutFile $path -UseBasicParsing; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.2
```

The automatic installation channel remains on stable version `2.4.1`. To
rollback, run the same command with `-Version 2.4.1`.

## Automated engineer installation

Run this command from Windows PowerShell:

```powershell
$path = Join-Path $env:TEMP 'Install-PerformanceAnalyzer.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/Install-PerformanceAnalyzer.ps1' -OutFile $path -UseBasicParsing; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path
```

The bootstrap automatically requests administrator access, reads the approved
version from `latest-version.txt`, downloads and verifies both packages,
installs the engineer tools, configures the Copilot integration, and retains
the customer ZIP under:

```text
C:\PerformanceAnalyzer\Packages\<version>
```

The command does not change between releases. Publishing a new approved
version requires updating `latest-version.txt` after its release assets are
available.

## Requirements

- Windows PowerShell 5.1
- Administrator privileges for data capture
- Windows Performance Recorder (`wpr.exe`)
- Windows Performance Toolkit (`xperf.exe`) for ETL decoding
- GitHub Copilot CLI for Copilot-assisted engineer analysis

## Customer capture workflow

1. Download the customer capture kit and matching checksum.
2. Verify the ZIP's SHA-256 hash.
3. Extract the ZIP to `C:\`.
4. Run `C:\PerformanceAnalyzer\2.4.1\start-capture.cmd`.
5. Approve the administrator prompt and follow the capture instructions.
6. Compress the complete `C:\PerfLogs\StorageCapture-*` directory.
7. Transfer the archive through the approved support channel.

The capture kit contains the PowerShell capture script, DiskSpd, its license,
and the Minifilter WPR profile. It does not install software or Copilot
components.

## Engineer analysis workflow

1. Download the engineer analysis kit and matching checksum.
2. Verify the ZIP's SHA-256 hash.
3. Extract the ZIP to `C:\`.
4. Run `C:\PerformanceAnalyzer\2.4.1\install.cmd`.
5. Restart GitHub Copilot CLI after the installer registers the MCP server and
   installs the skill.
6. Open a received capture with:

```powershell
& 'C:\PerformanceAnalyzer\2.4.1\analyzer\PerformanceAnalyzer.exe' `
  'C:\path\to\StorageCapture-folder'
```

The MCP server is installed per user under
`%LOCALAPPDATA%\PerformanceAnalyzer\Copilot\2.4.1`, and the skill is installed
under `%USERPROFILE%\.copilot\skills\performance-analyzer`.

## Verify a download

```powershell
$zipPath = 'C:\path\to\downloaded-package.zip'
$checksumPath = "$zipPath.sha256"
$expected = [regex]::Match(
  (Get-Content $checksumPath -Raw),
  '(?i)\b[a-f0-9]{64}\b'
).Value.ToUpperInvariant()
$actual = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()

if ($actual -ne $expected) {
  throw 'Package checksum verification failed.'
}

Write-Host 'Package checksum verified.'
```

## Package boundaries

Customer capture kit:

```text
PerformanceAnalyzer\2.4.1\
  readme.txt
  start-capture.cmd
  capture_tools\
```

Engineer analysis kit:

```text
PerformanceAnalyzer\2.4.1\
  readme.txt
  install.cmd
  analyzer\
  copilot_mcp_server\
  copilot_skill\
  setup_files\
```

## Security and measurement boundaries

- Analyzer and terminal endpoints bind only to `127.0.0.1`.
- The MCP server is read-only and accepts only loopback analyzer endpoints.
- The Copilot skill interprets data returned by PerformanceAnalyzer; it does
  not parse raw BLG, ETL, CSV, XML, or cache files.
- Anonymous usage telemetry records random installation/session identifiers,
  application version, launches, capture opens, Copilot outcomes, crashes,
  timestamps, and sanitized error codes. It does not collect capture data,
  paths, usernames, machine names, prompts, or Copilot conversations.
- Telemetry can be disabled with
  `PerformanceAnalyzer.exe --disable-telemetry`.
- PerfMon, Storport, Minifilter, DiskSpd, and application latency use different
  measurement boundaries and must not be added together.

## Release policy

Compiled packages are distributed through GitHub Releases rather than being
committed to repository history. The analyzer and MCP server are maintained in
separate private source repositories.
