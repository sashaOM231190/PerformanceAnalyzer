# PerformanceAnalyzer

PerformanceAnalyzer is a local Windows tool for analyzing:

- Performance Monitor binary log (`.blg`) captures
- Microsoft-Windows-StorPort ETL (`.etl`) traces
- Optional `DiskMapping.json` files that correlate PerfMon disks with Storport
  Port/Bus/Target/LUN addresses

The dashboard runs in a local browser and listens only on `127.0.0.1`. Capture
data is processed on the computer where the tool is running and is not uploaded
to an external service.

## Included files

| File | Purpose |
| --- | --- |
| `PerformanceAnalyzer.exe` | Current standalone analyzer |
| `Capture-StorageDiagnostics.ps1` | Collects synchronized BLG, Storport ETL, mapping, and manifest files |
| `BlgAnalyzer.exe` | Previous BLG-only release retained for compatibility |

## Requirements

- Windows
- Windows PowerShell 5.1
- .NET Framework 4.x
- A modern web browser
- Windows Performance Toolkit (`xperf.exe`) when analyzing Storport ETL files
- Administrator PowerShell session when running the capture script

BLG-only analysis does not require `xperf.exe`.

## How the analyzer works

### BLG processing

The analyzer discovers the counters actually recorded in the BLG and loads
selected counters on demand. It supports CPU, physical and logical disk,
memory, process, network, SMB, and other recorded counter sets.

The dashboard provides:

- Searchable counter selection
- Multiple synchronized graphs
- Shared cursor readings and tooltips
- Mouse-wheel zoom and selected-time controls
- Warning and critical threshold bands
- Spike detection and automatic findings
- Cumulative throughput and disk calculations
- Resizable counter selection panel

### Storport processing

The analyzer converts the ETL through `xperf.exe`, reads Storport request
events, and creates one-second graphs for:

- Total, read, and write IOPS
- Total, read, and write throughput
- Average, P95, and maximum request latency
- SCSI and SRB errors
- Command-specific IOPS, throughput, latency, and errors

Every SCSI opcode observed in the trace remains visible. Known commands are
named, for example:

```text
READ(10) [0x28]
WRITE(10) [0x2A]
SYNCHRONIZE CACHE(10) [0x35]
UNMAP/TRIM [0x42]
READ(16) [0x88]
WRITE(16) [0x8A]
REPORT LUNS [0xA0]
```

Unknown commands are displayed as `UNKNOWN SCSI COMMAND [0xNN]`.

### Disk correlation

PerfMon identifies a disk with an instance such as:

```text
PhysicalDisk(0 C: D: E:)
```

Storport identifies the same device with:

```text
Port 0 / Bus 0 / Target 0 / LUN 0
```

`DiskMapping.json` connects these identities through the Windows disk number
and SCSI address. Mapping can be supplied at startup or attached later from the
browser without recollecting the BLG or ETL.

### Timeline alignment

BLG timestamps can be returned as local-time fields or UTC fields depending on
the capture. When BLG and ETL files are supplied together, the analyzer selects
the BLG interpretation that aligns with the Storport trace.

## Session modes

| Mode | Available files | Behavior |
| --- | --- | --- |
| BLG only | BLG | PerfMon analysis |
| ETL only | ETL | Storport analysis |
| Combined uncorrelated | BLG + ETL | Both sources share a timeline, but disks are not mapped |
| Correlated | BLG + ETL + mapping | Storport addresses are mapped to Windows/PerfMon disks |

## Command-line syntax

```text
PerformanceAnalyzer.exe [input] [options]
```

### Positional input

The first positional argument can be a capture folder, BLG file, or ETL file:

```powershell
.\PerformanceAnalyzer.exe "C:\PerfLogs\StorageCapture-20260808-103655"
.\PerformanceAnalyzer.exe "C:\PerfLogs\Storage.blg"
.\PerformanceAnalyzer.exe "C:\PerfLogs\Storport.etl"
```

### Command variables

| Variable | Value | Description |
| --- | --- | --- |
| `--folder` | Directory path | Auto-discovers the available BLG, ETL, and mapping files |
| `--blg` | `.blg` path | Supplies a specific Performance Monitor capture |
| `--etl` | `.etl` path | Supplies a specific Storport trace |
| `--mapping` | `.json` path | Supplies an optional disk-correlation file |
| `--port` | `1024`-`65535` | Changes the local HTTP port; default is `8765` |
| `--no-browser` | No value | Starts the server without opening a browser automatically |
| `--help` | No value | Displays executable usage |

`-h` and `/?` also display help.

### Folder auto-discovery

```powershell
.\PerformanceAnalyzer.exe --folder "C:\PerfLogs\StorageCapture-20260808-103655"
```

Folder selection follows these rules:

1. Select the newest `.blg`.
2. Prefer `Storport.etl`; otherwise select the newest `.etl`.
3. Prefer `DiskMapping.json`; otherwise select the newest matching mapping JSON.
4. Start in the mode supported by the files that were found.

The folder can also be dragged onto `PerformanceAnalyzer.exe`.

### BLG-only analysis

```powershell
.\PerformanceAnalyzer.exe --blg "C:\PerfLogs\Storage.blg"
```

### Storport-only analysis

```powershell
.\PerformanceAnalyzer.exe --etl "C:\PerfLogs\Storport.etl"
```

### Combined analysis without mapping

```powershell
.\PerformanceAnalyzer.exe `
  --blg "C:\PerfLogs\Storage.blg" `
  --etl "C:\PerfLogs\Storport.etl"
```

### Combined and correlated analysis

```powershell
.\PerformanceAnalyzer.exe `
  --blg "C:\PerfLogs\Storage.blg" `
  --etl "C:\PerfLogs\Storport.etl" `
  --mapping "C:\PerfLogs\DiskMapping.json"
```

### Custom local port

```powershell
.\PerformanceAnalyzer.exe `
  --folder "C:\PerfLogs\StorageCapture-20260808-103655" `
  --port 9000
```

The dashboard is then available at:

```text
http://127.0.0.1:9000/
```

### Start without opening a browser

```powershell
.\PerformanceAnalyzer.exe `
  --folder "C:\PerfLogs\StorageCapture-20260808-103655" `
  --no-browser
```

Press `Ctrl+C` in the console to stop the dashboard server.

## Collect synchronized diagnostic data

Run Windows PowerShell as Administrator:

```powershell
Set-Location "E:\Path\BlgAnalyzer"
.\Capture-StorageDiagnostics.ps1
```

To use a different output root:

```powershell
.\Capture-StorageDiagnostics.ps1 -OutputRoot "D:\StorageTraces"
```

### Capture script variable

| Variable | Default | Description |
| --- | --- | --- |
| `-OutputRoot` | `C:\PerfLogs` | Parent directory where a timestamped capture folder is created |

The script creates a directory such as:

```text
C:\PerfLogs\StorageCapture-20260810-125400
```

It then:

1. Creates a circular PerfMon collector with a one-second sample interval.
2. Starts a circular Microsoft-Windows-StorPort ETW trace.
3. Waits while the storage issue is reproduced.
4. Stops both collectors when Enter is pressed.
5. Collects disk, partition, PerfMon-instance, and Port/Bus/Target/LUN mapping.
6. Writes a capture manifest.

### PerfMon counters collected

```text
\LogicalDisk(*)\*
\Memory\*
\Network Interface(*)\*
\Paging File(*)\*
\PhysicalDisk(*)\*
\Processor(*)\*
\Process(*)\*
\Redirector\*
\Server\*
\System\*
```

The BLG collector uses:

- One-second sampling
- Binary circular format
- Maximum size of 300 MB

The Storport collector uses:

- Provider: `Microsoft-Windows-StorPort`
- Circular ETL format
- Maximum size of 1024 MB
- 1024 KB buffers

### Generated files

| File | Description |
| --- | --- |
| `Storage_*.blg` | One-second PerfMon capture |
| `Storport.etl` | Storport request trace |
| `DiskMapping.json` | Disk number, PerfMon instance, volume, identity, and SCSI address mapping |
| `CaptureManifest.json` | Capture times, computer name, collector names, and generated filenames |

Analyze the complete output folder directly:

```powershell
.\PerformanceAnalyzer.exe "C:\PerfLogs\StorageCapture-20260810-125400"
```

## Reading Storport results

Under the **Storport** category:

- Select device-level metrics for overall storage behavior.
- Select command-specific metrics to determine whether READ, WRITE, TRIM,
  cache flush, or another command experienced latency.
- Use P95 latency to understand sustained high-latency behavior.
- Use maximum latency to find the worst one-second interval.
- Compare Storport latency with PerfMon disk latency on the shared timeline.

Sparse commands might have only one request in the selected range. These are
shown as point markers instead of line segments.

## Limitations

- BLG detail is limited to the counters and sample interval collected.
- One-second BLG samples cannot reconstruct individual I/O requests.
- Storport ETL is required for request-level command latency.
- Mapping correlates a Storport device to a Windows physical disk, but does not
  identify the application or exact file responsible for each request.
- Thresholds are diagnostic guidance and are not universal hardware limits.
- ETL conversion can require additional time for large traces.

## Privacy and security

- The HTTP listener binds only to `127.0.0.1`.
- Capture files remain local.
- The tool has no telemetry or upload functionality.
- BLG, ETL, and mapping files can expose machine names, process names, storage
  identities, and workload behavior; handle them as diagnostic data.
