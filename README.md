# PerformanceAnalyzer Coach

Capture and correlate Windows storage performance, Storport latency, PerfMon,
and minifilter activity. Coach guides disk/volume-specific analysis.

## Download / install

[Coach 2.5.0-coach.7 packages](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.5.0-coach.7)

| Package | Recipient |
| --- | --- |
| `performanceanalyzer-engineer-analysis-kit-2.5.0-coach.7.zip` | Engineer: analyzer, customer capture tools, MCP and skill |
| `performanceanalyzer-customer-capture-kit-2.5.0-coach.7.zip` | **Share this ZIP and its `.sha256` with the customer**; no analyzer or AI components |

**coach.7 was repackaged:** folder layout and ZIP checksums changed. Download
the new ZIP **and matching checksum** together. The old `start-capture.cmd`
was removed; use the explicit capture commands below.
For manual upgrades, extract into a clean directory: ZIP extraction does not
remove old launchers left by an earlier kit.

Install/refresh the engineer kit and cache the customer ZIP under
`C:\PerformanceAnalyzer\Packages\2.5.0-coach.7`:

```powershell
$path = Join-Path $env:TEMP 'Install-PerformanceAnalyzer.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/Install-PerformanceAnalyzer.ps1' -OutFile $path -UseBasicParsing; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.7
```

The bootstrap reports `wpr.exe` and `xperf.exe` locations or missing-tool
warnings. It checks System32/Sysnative, PATH and standard Windows Performance
Toolkit folders; Xperf does **not** have to be in System32. Missing WPR
prevents minifilter capture; missing Xperf prevents ETL decoding, not BLG-only
analysis. Install missing tools through the
[Windows ADK / Windows Performance Toolkit](https://learn.microsoft.com/windows-hardware/get-started/adk-install).

If Copilot CLI is missing, integration asks before installing
`GitHub.Copilot` through WinGet. Installation/authentication may be restricted
by organizational policy. Bootstrap options:

```powershell
# Explicit consent to install missing Copilot CLI through WinGet.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.7 -InstallCopilot
# Validate downloads/package files only; do not install or change integration.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.7 -ValidateOnly
# Install files without configuring AI integration.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.7 -SkipCopilotIntegration
```

## Installed directories

```text
C:\PerformanceAnalyzer\2.5.0-coach.7\
  readme.txt
  Analyzer\
    PerformanceAnalyzer.exe
    terminal_assets\
  CaptureKit\
    readme.txt
    capture_tools\
  Ai Integration\
    Integrate-Copilot.ps1
    version.txt
    copilot_mcp_server\
    copilot_skill\
```

Older installations may retain their old setup folders; the bootstrap refreshes
the new files without deleting unrelated files or saved captures.

## Capture: run as Administrator

Customer ZIP: extract to `C:\`; tools are directly under
`C:\PerformanceAnalyzer\2.5.0-coach.7\capture_tools`.
Engineer ZIP: tools are under `CaptureKit\capture_tools` instead.

```powershell
# Customer machine: capture the existing problem WITH minifilter callbacks.
Set-Location 'C:\PerformanceAnalyzer\2.5.0-coach.7\capture_tools'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Capture-StorageDiagnostics.ps1 -MiniFilter

# Engineer machine: use the capture tools included in the combined kit.
Set-Location 'C:\PerformanceAnalyzer\2.5.0-coach.7\CaptureKit\capture_tools'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Capture-StorageDiagnostics.ps1 -MiniFilter

# Different output location; minifilter callbacks still included.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Capture-StorageDiagnostics.ps1 -MiniFilter -OutputRoot 'D:\StorageTraces'

# Optional active DiskSpd baseline: obtain workload/write approval first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Capture-StorageDiagnostics.ps1 -SetBaseline -MiniFilter
```

Reproduce after collectors start, press **Enter** to stop normal capture, and
wait for **Capture complete**. Baseline capture stops when DiskSpd finishes.
For minifilter capture, confirm nonempty `MiniFilter.etl` in the printed output
folder. Without `-MiniFilter`, missing minifilter data is expected.

Default output: `C:\PerfLogs\StorageCapture-*`. Archive the **entire stopped
capture folder**, including BLG, ETLs, mapping and manifest; transfer through
the approved support channel. Do not stop somebody else's WPR/kernel trace.
Captures can contain machine/process names and file paths.

[All capture parameters, mode combinations, DiskSpd flags and troubleshooting](documentation/Capture-Reference.md).
Cloning this repository does not include the capture tools; download a ZIP.

## Analyze

```powershell
& 'C:\PerformanceAnalyzer\2.5.0-coach.7\Analyzer\PerformanceAnalyzer.exe' 'C:\path\to\StorageCapture-folder'
& 'C:\PerformanceAnalyzer\2.5.0-coach.7\Analyzer\PerformanceAnalyzer.exe' /?
```

Coach starts with disk number and volume, then operation and interval.
Minifilter callback duration and Storport latency measure different boundaries;
do not subtract one from the other. Reorder graphs with the header Move handle
or Up/Down buttons.

## Install / repair AI integration

Run for the Windows account that will use Copilot; close running analyzer/Coach
sessions before replacing files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\PerformanceAnalyzer\2.5.0-coach.7\Ai Integration\Integrate-Copilot.ps1'
# Explicit WinGet consent if Copilot CLI is missing:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\PerformanceAnalyzer\2.5.0-coach.7\Ai Integration\Integrate-Copilot.ps1' -InstallCopilot
# Optional custom analyzer port:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\PerformanceAnalyzer\2.5.0-coach.7\Ai Integration\Integrate-Copilot.ps1' -Endpoint 'http://127.0.0.1:9000/'
copilot mcp get performance-analyzer
```

Restart Copilot CLI; sign in with `/login` if needed and verify `/mcp` and
`/skills`. The script refreshes only the PerformanceAnalyzer MCP registration
and skill. MCP binary: `%LOCALAPPDATA%\PerformanceAnalyzer\Copilot\2.5.0-coach.7`.
Skill: `%USERPROFILE%\.copilot\skills\performance-analyzer`.
If `COPILOT_HOME` is set, configuration and skills use that directory instead.

## Verify a ZIP

```powershell
$zip = 'C:\path\to\downloaded-package.zip'
$expected = [regex]::Match((Get-Content "$zip.sha256" -Raw), '(?i)\b[a-f0-9]{64}\b').Value
if (-not $expected -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected) { throw 'Checksum mismatch' }
```

Anonymous usage telemetry is enabled by default, not capture-content upload.
To disable it:

```powershell
& 'C:\PerformanceAnalyzer\2.5.0-coach.7\Analyzer\PerformanceAnalyzer.exe' --disable-telemetry
```

Restart the analyzer afterward. Packages remain public until a restricted
distribution location is established; removing links alone is not access control.
