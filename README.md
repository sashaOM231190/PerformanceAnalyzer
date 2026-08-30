# PerformanceAnalyzer

PerformanceAnalyzer is a portable Windows storage diagnostics package that
captures and correlates PerfMon, Storport, process-volume I/O, Filter Manager
callbacks, disk topology, and optional DiskSpd baseline results.

Version 2.3.0 also includes a local read-only MCP server, a
PerformanceAnalyzer Copilot skill, and an embedded GitHub Copilot CLI terminal.

## Download

Download the latest package from
[GitHub Releases](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/latest).

Version 2.3.0:

- [performanceanalyzer-complete-package-2.3.0.zip](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/download/v2.3.0/performanceanalyzer-complete-package-2.3.0.zip)
- [SHA-256 checksum](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/download/v2.3.0/performanceanalyzer-complete-package-2.3.0.zip.sha256)

Expected SHA-256:

```text
BF66C993C9F8FE898E1A36F837E0B71E7AD3CF9D26DFD5FEBEF6A5337B84B517
```

Verify the download:

```powershell
Get-FileHash `
  .\performanceanalyzer-complete-package-2.3.0.zip `
  -Algorithm SHA256
```

## Requirements

- Windows 10, Windows 11, or Windows Server with ConPTY support
- Windows PowerShell 5.1
- Administrator privileges for data capture
- Windows Performance Recorder (`wpr.exe`)
- Windows Performance Toolkit (`xperf.exe`) for ETL decoding
- GitHub Copilot CLI for Copilot-assisted analysis

## Install

1. Download and extract the ZIP.
2. Open the extracted package directory.
3. Run:

```powershell
.\install.cmd
```

The installer:

- installs the versioned MCP executable for the current user;
- installs the `performance-analyzer` Copilot skill;
- registers the `performance-analyzer` MCP server;
- verifies the configured executable and analyzer endpoint.

The capture and analyzer tools remain portable inside the extracted package.

For a detailed explanation of every manual installation step and how those
steps map to a future one-command PowerShell bootstrap, see
[PowerShell bootstrap installer guide](documentation/PowerShell-Bootstrap-Installer-Guide.md).

## Package layout

```text
install.cmd
readme.txt

analyzer\
  performanceanalyzer.exe
  terminal_assets\

data_capture_tools\
  capture-storagediagnostics.ps1
  diskspd.exe
  performanceanalyzer-minifilter.wprp

copilot_mcp_server\
  performanceanalyzer.mcp.exe

copilot_skill\
  skill.md
  reference\

setup_files\
winget_packaging\
```

## Capture storage diagnostics

Run the capture script from an elevated Windows PowerShell window:

```powershell
.\data_capture_tools\capture-storagediagnostics.ps1
```

Common combinations:

```powershell
# Capture storage, process-volume, and PerfMon data
.\data_capture_tools\capture-storagediagnostics.ps1

# Add Minifilter callback tracing
.\data_capture_tools\capture-storagediagnostics.ps1 -MiniFilter

# Run an interactive DiskSpd baseline
.\data_capture_tools\capture-storagediagnostics.ps1 -SetBaseline

# Combine DiskSpd baseline and Minifilter tracing
.\data_capture_tools\capture-storagediagnostics.ps1 `
  -SetBaseline `
  -MiniFilter
```

Captures are stored under `C:\PerfLogs` by default.

## Analyze a capture

```powershell
.\analyzer\performanceanalyzer.exe `
  C:\PerfLogs\StorageCapture-YYYYMMDD-HHMMSS
```

The analyzer discovers the available BLG, Storport, process-volume,
Minifilter, mapping, manifest, and DiskSpd files in the selected folder.

Useful options:

```text
--no-browser
--port <port>
--version
--help
```

## Copilot integration

The dashboard includes a Copilot button that:

1. verifies Copilot CLI, the MCP registration, installed skill, and terminal
   assets;
2. repairs package-managed MCP and skill setup when required;
3. opens GitHub Copilot CLI in an embedded xterm.js terminal;
4. supplies an initial PerformanceAnalyzer analysis prompt.

Terminal input, output, resize, and status use one persistent WebSocket bound
to loopback. Closing every dashboard page stops the Copilot process after a
short grace period. **End Session** stops both Copilot and
PerformanceAnalyzer.

The AI integration is read-only. It interprets measurements returned by
PerformanceAnalyzer and does not parse raw BLG, ETL, CSV, XML, or cache files.

## Remove Copilot integration

From the extracted package, run:

```powershell
.\setup_files\uninstall.cmd
```

This removes the installed MCP server, skill, and Copilot registration. It
does not delete the portable package or captured diagnostics.

## Measurement boundaries

PerfMon disk latency, Storport request duration, Minifilter callback duration,
DiskSpd latency, and application latency use different measurement boundaries.
They can be correlated by time but must not be added together or subtracted
from one another.

Minifilter cumulative duration can overlap across operations, threads,
processors, filters, and callback phases. It is not equivalent to serialized
application delay.

## Security

- Analyzer and terminal endpoints bind only to `127.0.0.1`.
- Copilot lifecycle and WebSocket routes require a random per-dashboard token.
- The MCP server accepts only loopback HTTP analyzer endpoints.
- MCP tools are read-only and non-destructive.
- The Copilot process tree is owned by a Windows Job Object and is terminated
  when the analyzer session closes.

## Troubleshooting

### Windows reports an unrecognized application

The package is not currently code-signed. Verify the SHA-256 checksum before
running it.

### Copilot button reports a missing component

Run `install.cmd` again from the extracted package and restart
PerformanceAnalyzer.

### The analyzer cannot decode ETL files

Install the Windows Performance Toolkit and confirm `xperf.exe` is available.

### Minifilter capture cannot start

Run PowerShell as administrator, stop any existing WPR recording, and confirm
the supplied WPR profile remains in `data_capture_tools`.

## Release policy

Compiled packages are distributed through GitHub Releases rather than being
committed to the repository history. Each release includes a SHA-256 checksum.
