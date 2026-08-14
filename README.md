# PerformanceAnalyzer Storage Diagnostics

PerformanceAnalyzer correlates Windows PerfMon, Storport ETW, process/file I/O
ETW, disk topology, and DiskSpd XML in one local browser dashboard.

This version supports:

- One-second PerfMon analysis.
- Storport request throughput, IOPS, latency, status, and SCSI commands.
- Exact Storport latency bands by Total, Read, Write, Other, and opcode.
- Automatic identification of the SCSI command with maximum request latency.
- Process-to-volume top-five contributor analysis.
- DiskSpd baseline capture, import, target mapping, and comparison.
- LogicalDisk, PhysicalDisk, Storport, CPU average, and CPU peak comparison.
- Processed ETL caching for large captures.

## Contents

- [Prerequisites](#prerequisites)
- [Capture commands](#capture-commands)
- [Analyzer commands](#analyzer-commands)
- [Build commands](#build-commands)
- [DiskSpd baseline behavior](#diskspd-baseline-behavior)
- [Dashboard areas](#dashboard-areas)
- [Comparison calculations](#comparison-calculations)
- [Capture artifacts](#capture-artifacts)
- [Troubleshooting](#troubleshooting)
- [Final release recommendations](#final-release-recommendations)
- [Architecture brief](#architecture-brief)

## Prerequisites

Run capture commands from an elevated Windows PowerShell window.

Required:

- Windows PowerShell 5.1.
- Administrator rights for capture.
- Windows `logman.exe`.
- Windows Performance Toolkit with `xperf.exe` for ETL analysis.
- A modern browser.
- `diskspd.exe` beside `Capture-StorageDiagnostics.ps1` for `-SetBaseline`.

The dashboard listens only on `127.0.0.1`.

## Capture commands

Change to the tool directory:

```powershell
cd E:\tool_development\BlgAnalyzerPrivate\implementing_diskSPD_baseline
```

### Normal diagnostic capture

```powershell
.\Capture-StorageDiagnostics.ps1
```

This collects:

- PerfMon BLG.
- Storport ETL.
- `ProcessVolume.etl`.
- `DiskMapping.json`.
- `CaptureManifest.json`.

Reproduce the issue and press Enter to stop collection.

### Normal capture with a different output root

```powershell
.\Capture-StorageDiagnostics.ps1 `
  -OutputRoot D:\StorageTraces
```

### Normal capture with a different process ETL limit

Valid range: 256-8192 MiB. Default: 1024 MiB.

```powershell
.\Capture-StorageDiagnostics.ps1 `
  -ProcessIoTraceMaxMB 2048
```

### Normal capture with both options

```powershell
.\Capture-StorageDiagnostics.ps1 `
  -OutputRoot D:\StorageTraces `
  -ProcessIoTraceMaxMB 2048
```

### Interactive DiskSpd baseline capture

```powershell
.\Capture-StorageDiagnostics.ps1 -SetBaseline
```

This collects:

- PerfMon BLG.
- Storport ETL.
- DiskSpd XML.
- Disk mapping.
- Capture manifest.

It intentionally skips `ProcessVolume.etl`.

Available presets:

1. Balanced random: 64 KiB, 70% read / 30% write.
2. Random read IOPS: 4 KiB, 100% read.
3. Sequential read throughput: 1 MiB, 100% read.
4. Sequential write throughput: 1 MiB, 100% write.
5. Custom DiskSpd command.

For custom mode, enter a complete command when prompted:

```text
diskspd.exe -c10G -d60 -W20 -r8K -w0 -b64K -t4 -o8 -Sh -L C:\Temp\diskspd_test.dat
```

The script preserves the workload options and supplied target directory, but
controls the temporary target filename. The example target therefore becomes:

```text
C:\Temp\DiskSpdBaseline.dat
```

The effective command and all adjustments are displayed before capture starts.
The user must enter `Y` or `YES` to approve it. The script adds `-Rxml` when
needed so the result is stored as `DiskSpd-baseline.xml` in the capture folder,
and adds `-L` when needed so latency statistics are available. Custom duration,
warmup, and cooldown values are written to the capture manifest.

Custom baseline mode accepts exactly one local file target. Raw-disk and
multi-target commands are rejected. For a multi-target test, start a normal
capture without `-SetBaseline`, run DiskSpd separately, and press Enter after
the test finishes.

Drive input accepts `c`, `C`, or `C:`. A drive input becomes:

```text
C:\DiskSpdBaseline.dat
```

Preset baseline runtime:

```text
Warmup:     0 seconds
Measurement: 60 seconds
Cooldown:   0 seconds
```

New preset test files are 10 GiB and are removed after capture. Existing files
are not removed. Preset write workloads against existing files require an
explicit `YES` confirmation. Custom mode displays any overwrite warning with
the final effective command and requires `Y` or `YES` before execution.

### Baseline capture with a different output root

```powershell
.\Capture-StorageDiagnostics.ps1 `
  -SetBaseline `
  -OutputRoot D:\StorageTraces
```

### Capture script help

```powershell
Get-Help .\Capture-StorageDiagnostics.ps1 -Full
```

## Analyzer commands

### Analyze a capture folder

```powershell
.\PerformanceAnalyzer.exe C:\PerfLogs\StorageCapture-20260814-195749
```

The folder form automatically discovers:

- The BLG file.
- `Storport.etl`.
- `ProcessVolume.etl`.
- `DiskMapping.json`.
- `DiskSpd*.xml`.

When DiskSpd XML is present, automatic process-volume analysis is skipped to
keep baseline startup fast. Provide `--process-etl <path>` to include it.

### Analyze a folder using the explicit option

```powershell
.\PerformanceAnalyzer.exe `
  --folder C:\PerfLogs\StorageCapture-20260814-195749
```

### Analyze a BLG file

```powershell
.\PerformanceAnalyzer.exe C:\Capture\Storage.blg
```

Equivalent explicit command:

```powershell
.\PerformanceAnalyzer.exe --blg C:\Capture\Storage.blg
```

### Analyze a Storport ETL file

```powershell
.\PerformanceAnalyzer.exe --etl C:\Capture\Storport.etl
```

An ETL passed as the first positional path is treated as Storport unless its
name is exactly `ProcessVolume.etl`.

### Analyze process-to-volume I/O

```powershell
.\PerformanceAnalyzer.exe `
  --process-etl C:\Capture\ProcessVolume.etl `
  --mapping C:\Capture\DiskMapping.json
```

`--process-etl` requires a path; it is not a pathless switch.

### Analyze BLG and Storport together

```powershell
.\PerformanceAnalyzer.exe `
  --blg C:\Capture\Storage.blg `
  --etl C:\Capture\Storport.etl
```

### Analyze a fully correlated capture

```powershell
.\PerformanceAnalyzer.exe `
  --blg C:\Capture\Storage.blg `
  --etl C:\Capture\Storport.etl `
  --process-etl C:\Capture\ProcessVolume.etl `
  --mapping C:\Capture\DiskMapping.json
```

### Import a separate DiskSpd XML baseline

```powershell
.\PerformanceAnalyzer.exe `
  --blg C:\Capture\Storage.blg `
  --etl C:\Capture\Storport.etl `
  --mapping C:\Capture\DiskMapping.json `
  --diskspd-xml C:\Baseline\DiskSpd-result.xml
```

The analyzer maps the DiskSpd target through `DiskMapping.json` and compares
only common metrics for the mapped disk or volume.

### Force process-volume analysis for a DiskSpd capture

Use this only when `ProcessVolume.etl` exists:

```powershell
.\PerformanceAnalyzer.exe `
  C:\PerfLogs\StorageCapture-20260814-195749 `
  --process-etl C:\PerfLogs\StorageCapture-20260814-195749\ProcessVolume.etl
```

### Use a different dashboard port

```powershell
.\PerformanceAnalyzer.exe `
  C:\Capture `
  --port 8877
```

Valid ports: 1024-65535. Default: 8765.

### Do not open the browser automatically

```powershell
.\PerformanceAnalyzer.exe `
  C:\Capture `
  --no-browser
```

### Combine port and browser options

```powershell
.\PerformanceAnalyzer.exe `
  C:\Capture `
  --port 8877 `
  --no-browser
```

### Analyzer help

```powershell
.\PerformanceAnalyzer.exe --help
```

Also supported:

```powershell
.\PerformanceAnalyzer.exe -h
.\PerformanceAnalyzer.exe /?
```

### Analyzer version

```powershell
.\PerformanceAnalyzer.exe --version
.\PerformanceAnalyzer.exe -v
```

### Run the dashboard script directly

The executable is recommended, but the embedded script can be run directly:

```powershell
.\Show-PerfCounterDashboard.ps1 `
  -BlgPath C:\Capture\Storage.blg `
  -EtlPath C:\Capture\Storport.etl `
  -ProcessEtlPath C:\Capture\ProcessVolume.etl `
  -MappingPath C:\Capture\DiskMapping.json `
  -DiskSpdXmlPath C:\Capture\DiskSpd-baseline.xml `
  -Port 8765
```

Folder discovery through the script:

```powershell
.\Show-PerfCounterDashboard.ps1 `
  -FolderPath C:\Capture `
  -NoBrowser
```

## Build commands

Build the default executable:

```powershell
.\Build-BlgAnalyzer.ps1
```

Build to another path:

```powershell
.\Build-BlgAnalyzer.ps1 `
  -OutputPath D:\Tools\PerformanceAnalyzer.exe
```

The build uses the .NET Framework C# compiler and embeds
`Show-PerfCounterDashboard.ps1` as a resource in the executable.

## DiskSpd baseline behavior

DiskSpd XML supplies:

- Target path.
- Test duration.
- Block size.
- Random or sequential pattern.
- Read/write ratio.
- Threads and outstanding requests.
- Cache mode.
- Read, write, and total IOPS.
- Read, write, and total throughput.
- Average, P95, and maximum latency.
- IOPS standard deviation.
- Average CPU utilization.

The comparison table includes:

- Storport average I/O size.
- Storport throughput.
- Request-weighted Storport average latency.
- Storport maximum request latency.
- LogicalDisk and PhysicalDisk PerfMon measurements.
- Average and peak PerfMon CPU utilization.

If workload dimensions are incompatible, the tool reports 100% workload
deviation and suppresses misleading performance deviation conclusions.

## Dashboard areas

### Standard PerfMon categories

- CPU
- Disk
- Memory
- Network
- Process
- SMB
- Other

### Storport

- Total, read, write, and other IOPS.
- Total, read, and write throughput.
- Average, P95, and maximum request latency.
- Per-SCSI-command IOPS, throughput, latency, and errors.
- SCSI and SRB failures.

### Disk Latency Bands

Exact per-request Storport ranges:

- Less than 5 ms.
- 5-10 ms.
- 10-20 ms.
- 20-50 ms.
- 50 ms or more.

Each range can be broken down by:

- Total.
- Read.
- Write.
- Other.
- Individual SCSI command and opcode.

The selected-range automatic analysis identifies which SCSI command had the
highest Storport request latency. Every automatic finding also displays the
exact graph title and unit that produced the reading, including findings for
graphs that were analyzed automatically but are not currently loaded.

### Process Volume I/O

Requires `ProcessVolume.etl` and `DiskMapping.json`.

The UI lets the user:

1. Select a drive or volume.
2. Select one of its top five process contributors.
3. Graph the contributor's IOPS, throughput, and request-size metrics.

### SCSI Request Failures

Shows bucketed failures with:

- Opcode and command name.
- SCSI status.
- SRB status and flags.
- NT status.
- Sense key.
- ASC and ASCQ.
- Average and maximum failure latency.

## Comparison calculations

### Signed deviation

Used for throughput and latency:

```text
(captured - baseline) / baseline x 100
```

### Absolute I/O-size deviation

```text
|captured - baseline| / baseline x 100
```

### Storport average latency

Storport has individual request durations. The selected-range average is
request weighted:

```text
sum(one-second average latency x requests in that second)
---------------------------------------------------------
total requests
```

### PerfMon average latency

PerfMon exposes one cooked average-latency sample per interval. The current
selected-range value is the arithmetic mean of those one-second samples.

### CPU average

Arithmetic mean of selected-range:

```text
\Processor(_Total)\% Processor Time
```

Average CPU difference is displayed in percentage points.

### CPU peak

The highest selected-range one-second `_Total` CPU sample. DiskSpd XML does
not provide a peak CPU baseline, so baseline and deviation are `n/a`.

## Capture artifacts

| Artifact | Normal capture | `-SetBaseline` |
|---|---:|---:|
| PerfMon BLG | Yes | Yes |
| `Storport.etl` | Yes | Yes |
| `ProcessVolume.etl` | Yes | No |
| `DiskMapping.json` | Yes | Yes |
| `CaptureManifest.json` | Yes | Yes |
| `DiskSpd-baseline.xml` | No | Yes |

The physical BLG filename may include a timestamp because `logman` uses
timestamped output naming.

Baseline manifest schema version 5 records the original and effective DiskSpd
commands, timing, executable product version, and executable SHA-256 hash.

## Cache behavior

ETL conversion and processed analysis are cached under:

```text
%TEMP%\BlgAnalyzer
```

The cache key includes source filename, length, and last-write time. Cached
and uncached analysis produce the same dashboard data; caching only reduces
startup time.

## Troubleshooting

### `xperf.exe is required`

Install the Windows Performance Toolkit from the Windows ADK.

### `diskspd.exe` was not found

Copy the correct architecture of `diskspd.exe` beside:

```text
Capture-StorageDiagnostics.ps1
```

### Socket address already in use

Use another port:

```powershell
.\PerformanceAnalyzer.exe C:\Capture --port 8877
```

Or close the existing analyzer instance.

### Process-volume analysis is missing

`-SetBaseline` intentionally skips `ProcessVolume.etl`. Run a normal capture:

```powershell
.\Capture-StorageDiagnostics.ps1
```

### Existing NT Kernel Logger session

Normal process-volume capture uses the NT Kernel Logger. Stop the conflicting
kernel trace before starting another normal capture.

### Large ETL startup

The first run converts and aggregates the ETL. Later runs load the processed
cache. Baseline folders skip process-volume analysis unless explicitly
requested.

## Final release recommendations

### Keep in the runtime package

- `PerformanceAnalyzer.exe`
- `Capture-StorageDiagnostics.ps1`
- The matching-architecture `diskspd.exe`
- The DiskSpd vendor EULA or license distributed with that binary
- `README.md`
- `Architecture.md` and `Architecture.pdf`

### Keep only in the developer/source package

- `Show-PerfCounterDashboard.ps1`
- `BlgAnalyzerHost.cs`
- `Build-BlgAnalyzer.ps1`
- DiskSpd source trees, symbols, and architecture-specific binary folders

The current workspace also contains `DiskSpd.ZIP`, `diskspd-master.zip`,
`diskspd-master\`, and the full `DiskSpd\` distribution. They are not used at
runtime. Exclude redundant archives, source trees, and PDB files from the
deployable package, while retaining the applicable DiskSpd license.

### Recommended future additions

1. A read-only preflight command that checks elevation, XPerf, DiskSpd,
   available ports, target-directory access, and estimated free space.
2. Export of the selected range, automatic findings, graph identities, and
   baseline comparison to a portable HTML or JSON report.
3. An optional cache-management command to list or clear
   `%TEMP%\BlgAnalyzer` without deleting capture data.

### Intentionally excluded

- The counter calculator, because it did not contribute to diagnosis.
- PerfMon-derived request latency bands, because interval averages cannot
  reproduce exact per-request distributions.
- Subjective `better` or `worse` comparison labels without workload context.
- Raw-disk and multi-target execution inside integrated baseline mode because
  of destructive risk and ambiguous volume correlation.
- A single composite health score, because it would hide source boundaries
  and workload compatibility.

## Architecture brief

The tool has four main layers:

1. `Capture-StorageDiagnostics.ps1` coordinates PerfMon, Storport, optional
   process-volume ETL, disk mapping, and DiskSpd baseline capture.
2. `PerformanceAnalyzer.exe` discovers capture artifacts, validates command
   inputs, hosts the embedded analysis engine, and opens the local dashboard.
3. The analysis engine parses and correlates BLG, ETL, mapping, and DiskSpd
   XML while preserving each source's measurement boundary.
4. The browser dashboard presents time-aligned graphs, exact Storport latency
   bands, process-volume contributors, automatic findings, and baseline
   comparisons through a loopback-only API.

Large Storport traces use streaming aggregation and processed caching under
`%TEMP%\BlgAnalyzer`. The integrated baseline workflow accepts one controlled
file target and records the effective command, timing, DiskSpd version, and
SHA-256 in the capture manifest.

Detailed diagrams are available in [Architecture.md](Architecture.md) and
[Architecture.pdf](Architecture.pdf).
