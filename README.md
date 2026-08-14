# PerformanceAnalyzer

PerformanceAnalyzer is a Windows performance-analysis dashboard for Performance
Monitor `.blg` files. It reads the counters stored in a capture and presents
interactive charts, synchronized cursor readings, zoom controls, findings,
threshold guidance, and derived disk calculations in a local browser.

The dashboard processes captures locally and binds its web server only to
`127.0.0.1`. BLG data is not uploaded by the application.

It can also decode a `Microsoft-Windows-StorPort` ETL and expose synchronized
one-second Storport IOPS, throughput, latency, and error graphs. Every SCSI
opcode present in the trace receives command-specific counters; known opcodes
use names such as READ, WRITE, INQUIRY, REPORT LUNS, UNMAP/TRIM, and
SYNCHRONIZE CACHE, while unknown opcodes retain their hexadecimal value. An
optional `DiskMapping.json` correlates Port/Bus/Target/LUN with PerfMon disk
instances.

## Features

- CPU, physical and logical disk, memory, process, network, SMB, and other
  recorded counter categories
- Searchable counter and instance selection
- Multiple vertically stacked charts with synchronized time and cursor
- Mouse-wheel zoom, selected-time range controls, and overview navigator
- Automatic findings, spike detection, threshold bands, and zoom links
- Human-readable units and copyable cursor readings
- Selected-range cumulative read/write totals
- Disk calculations such as throughput, IOPS, transfer size, queue validation,
  read/write mix, weighted latency, busy-time checks, activity percentage, and
  burst ratio
- Hover help explaining derived values in plain language
- Standalone `PerformanceAnalyzer.exe` with the dashboard script embedded

## Requirements

- Windows
- Windows PowerShell 5.1
- .NET Framework 4.x
- Windows Performance Toolkit (`xperf.exe`) for Storport ETL analysis
- A Performance Monitor `.blg` capture
- A modern web browser

PowerShell 7 can start the script-based version, but BLG processing is
automatically delegated to Windows PowerShell 5.1 because `Import-Counter`
objects do not behave consistently when deserialized across editions.

## Run the standalone EXE

Capture folder auto-discovery:

```powershell
.\PerformanceAnalyzer.exe "E:\Path\StorageCapture-20260808-103655"
```

The folder may contain a BLG, Storport ETL, or both. The analyzer selects the
newest `.blg`, prefers `Storport.etl`, and uses `DiskMapping.json` when present.
It starts in BLG-only, ETL-only, combined, or correlated mode according to the
files that are available.

```powershell
.\PerformanceAnalyzer.exe "E:\Path\Capture.blg"
```

Storport only:

```powershell
.\PerformanceAnalyzer.exe --etl "E:\Path\Storport.etl"
```

Combined without mapping:

```powershell
.\PerformanceAnalyzer.exe `
  --blg "E:\Path\Storage.blg" `
  --etl "E:\Path\Storport.etl"
```

Combined and correlated:

```powershell
.\PerformanceAnalyzer.exe `
  --blg "E:\Path\Storage.blg" `
  --etl "E:\Path\Storport.etl" `
  --mapping "E:\Path\DiskMapping.json"
```

Optional arguments:

```text
--folder <path>       Auto-discover capture files in a directory.
--port <1024-65535>  Use a different local HTTP port.
--no-browser         Do not open the browser automatically.
```

You can also drag a capture folder, `.blg`, or `.etl` file onto
`PerformanceAnalyzer.exe`. The EXE does not need the `.ps1` or `.bat` files beside it
because the dashboard script is embedded.

Press `Ctrl+C` in the console to stop the local dashboard server.

## Run from source

```powershell
.\Show-PerfCounterDashboard.ps1 -InputPath "E:\Path\Capture.blg"
```

For folder auto-discovery:

```powershell
.\Show-PerfCounterDashboard.ps1 -FolderPath "E:\Path\CaptureFolder"
```

Or use the launcher:

```bat
Start-PerformanceDashboard.bat "E:\Path\Capture.blg"
```

The BAT file is only a convenience wrapper for the PowerShell source version.
It is not used by `PerformanceAnalyzer.exe`.

## Build the EXE

Run from the repository directory:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\Build-BlgAnalyzer.ps1
```

The build script uses the .NET Framework C# compiler and embeds
`Show-PerfCounterDashboard.ps1` as the `BlgDashboardScript` resource in
`PerformanceAnalyzer.exe`.

Any dashboard source change requires rebuilding the EXE.

## Source layout

| File | Purpose |
| --- | --- |
| `Show-PerfCounterDashboard.ps1` | BLG reader, local HTTP server, HTML, CSS, JavaScript, charts, findings, and calculations |
| `BlgAnalyzerHost.cs` | Console host that validates arguments and runs the embedded dashboard through the Windows PowerShell engine |
| `Build-BlgAnalyzer.ps1` | Reproducibly compiles the C# host and embeds the dashboard script |
| `Start-PerformanceDashboard.bat` | Optional launcher for the external PowerShell script |
| `PerformanceAnalyzer.exe` | Built standalone executable |

## Example disk calculation

If a capture contains:

```text
Avg. Disk Bytes/Read = 1,044,480 bytes/read
Disk Reads/sec       = 7.021 reads/second
```

The estimated read throughput is:

```text
1,044,480 × 7.021 = 7,333,326 bytes/second = 6.99 MiB/second
```

The dashboard compares calculated values with direct PerfMon counters when the
required counters for the same disk instance are loaded.

## Limitations

- Results are limited to counters and sample intervals recorded in the BLG.
- A one-second capture cannot reconstruct millisecond-level I/O distributions,
  file paths, or stack traces.
- Standard Process and PhysicalDisk counters cannot reliably attribute a
  process to a particular physical disk. Use ETW/WPR for exact
  process-to-file-to-disk tracing.
- Thresholds are diagnostic guidance rather than universal hardware limits.
- The executable is a C# host for embedded PowerShell logic, not a native
  rewrite of the analyzer.

## Privacy and security

- The server listens only on the IPv4 loopback address.
- Captures remain on the computer running the analyzer.
- No telemetry or external web service is used.
- Review `Show-PerfCounterDashboard.ps1` and `BlgAnalyzerHost.cs` for the full
  implementation.

## Sample captures

BLG captures are intentionally excluded from Git because they can be very
large and may contain machine, process, and workload information. Supply your
own capture when running the analyzer.

## Architecture documentation

The `docs` directory contains:

- `01-HLD.md` - high-level design
- `02-LLD.md` - low-level design
- `03-Code-Walkthrough.md` - function-by-function implementation guide
- `BLG-Analyzer-Architecture-Guide.pdf` - combined learning guide

To rebuild the HTML and PDF:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\Build-Documentation.ps1
```

The documentation build uses Node.js and the locally installed Microsoft Edge.
It does not download an additional browser or npm package.

## Collect synchronized BLG and Storport traces

Run the following script from an elevated Windows PowerShell window:

```powershell
.\Capture-StorageDiagnostics.ps1
```

It starts one-second PerfMon and circular Storport collectors, waits while the
issue is reproduced, then stops both collectors and creates:

- One or more `.blg` files
- `Storport.etl`
- `DiskMapping.json`
- `CaptureManifest.json`

The mapping records Windows disk number, matching PerfMon instances, SCSI
Port/Bus/Target/LUN, stable disk identifiers, and partitions.

The combined analyzer supports:

- BLG-only analysis
- Storport-only analysis
- Side-by-side BLG and Storport analysis without mapping
- Correlation immediately when `DiskMapping.json` is supplied
- Attaching the mapping file later without recollecting the BLG or ETL

Under the **Storport** category, counters are grouped by disk or Storport port.
Select command-specific counters such as `READ(16) [0x88] P95 Latency`,
`WRITE(16) [0x8A] Maximum Latency`, or
`UNMAP/TRIM [0x42] Average Latency` to identify which SCSI operation was slow.
Discovery-only addresses are consolidated by port so commands such as REPORT
LUNS remain visible without producing hundreds of nearly empty device groups.

