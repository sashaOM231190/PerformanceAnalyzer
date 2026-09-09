# PerformanceAnalyzer

PerformanceAnalyzer is distributed as two role-specific Windows packages:

| Package | Audience | Purpose |
| --- | --- | --- |
| Customer capture kit | External customers | Collect storage diagnostics for support |
| Engineer analysis kit | Support engineers | Analyze captures with the desktop analyzer and Copilot integration |

The packages are intentionally separate. Customers do not receive the analyzer,
MCP server, Copilot skill, or embedded terminal.

## Download

[Download PerformanceAnalyzer 2.4.2](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.4.2)

Release assets:

- `performanceanalyzer-customer-capture-kit-2.4.2.zip`
- `performanceanalyzer-customer-capture-kit-2.4.2.zip.sha256`
- `performanceanalyzer-engineer-analysis-kit-2.4.2.zip`
- `performanceanalyzer-engineer-analysis-kit-2.4.2.zip.sha256`

Verify each ZIP against its matching SHA-256 file before extraction.

### Coach prerelease

PerformanceAnalyzer `2.5.0-coach.4` provides context-first educational
onboarding. Coach asks what the engineer is investigating, loads one relevant
graph, explains its purpose and UI path, and requests consent before adding
each next graph. Capture-specific evidence remains locked until the engineer
records an observation, correlation, and hypothesis. Coach can also be
unembedded into a separate resizable window. There is no urgency bypass. The
dashboard also reports the current anonymous telemetry state and provides the
opt-out command when telemetry is enabled.

[Download Coach 2.5.0-coach.4](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.5.0-coach.4)

Install this prerelease explicitly:

```powershell
$path = Join-Path $env:TEMP 'Install-PerformanceAnalyzer.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/Install-PerformanceAnalyzer.ps1' -OutFile $path -UseBasicParsing; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.4
```

The automatic installation channel uses stable version `2.4.2`. To
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
4. Run `C:\PerformanceAnalyzer\2.4.2\start-capture.cmd`.
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
4. Run `C:\PerformanceAnalyzer\2.4.2\install.cmd`.
5. Restart GitHub Copilot CLI after the installer registers the MCP server and
   installs the skill.
6. Open a received capture with:

```powershell
& 'C:\PerformanceAnalyzer\2.4.2\analyzer\PerformanceAnalyzer.exe' `
  'C:\path\to\StorageCapture-folder'
```

The MCP server is installed per user under
`%LOCALAPPDATA%\PerformanceAnalyzer\Copilot\2.4.2`, and the skill is installed
under `%USERPROFILE%\.copilot\skills\performance-analyzer`.

## Command reference

Display the built-in command reference:

```powershell
.\PerformanceAnalyzer.exe /?
```

Usage:

```text
PerformanceAnalyzer.exe "E:\Path\CaptureFolder"
PerformanceAnalyzer.exe --folder "E:\Path\CaptureFolder"
PerformanceAnalyzer.exe "E:\Path\Capture.blg"
PerformanceAnalyzer.exe --etl "E:\Path\Storport.etl"
PerformanceAnalyzer.exe --process-etl "E:\Path\ProcessVolume.etl" --mapping "E:\Path\DiskMapping.json"
PerformanceAnalyzer.exe --minifilter-etl "E:\Path\MiniFilter.etl" --mapping "E:\Path\DiskMapping.json"
PerformanceAnalyzer.exe --blg "E:\Path\Capture.blg" --etl "E:\Path\Storport.etl"
PerformanceAnalyzer.exe --blg "E:\Path\Capture.blg" --etl "E:\Path\Storport.etl" --mapping "E:\Path\DiskMapping.json" --diskspd-xml "E:\Path\DiskSpd-result.xml"
```

Options:

| Option | Description |
| --- | --- |
| `--folder <path>` | Auto-discover capture files. |
| `--blg <path>` | PerfMon BLG input. |
| `--etl <path>` | Storport ETL input. |
| `--process-etl <path>` | Process-volume ETL input. |
| `--minifilter-etl <path>` | Minifilter callback ETL input. |
| `--mapping <path>` | Optional disk-correlation JSON. |
| `--diskspd-xml <path>` | Optional DiskSpd `-Rxml` result. |
| `--port <1024-65535>` | Use a different local HTTP port. |
| `--no-browser` | Do not open the browser automatically. |
| `--version`, `-v` | Display the analyzer version. |
| `--telemetry-status` | Display anonymous telemetry status. |
| `--enable-telemetry` | Enable anonymous usage telemetry. |
| `--disable-telemetry` | Disable anonymous usage telemetry. Restart the analyzer afterward. |

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
PerformanceAnalyzer\2.4.2\
  readme.txt
  start-capture.cmd
  capture_tools\
```

Engineer analysis kit:

```text
PerformanceAnalyzer\2.4.2\
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
