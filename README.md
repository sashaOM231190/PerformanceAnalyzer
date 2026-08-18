# PerformanceAnalyzer storage and minifilter diagnostics

PerformanceAnalyzer captures and correlates Windows storage telemetry from
PerfMon, Storport, process/file I/O, Filter Manager callbacks, disk topology,
and optional DiskSpd baseline results.

The minifilter implementation answers four practical questions:

1. Which minifilter consumed the most cumulative callback time?
2. Which files generated the most callback churn?
3. Which process, major function, and callback phase contributed?
4. When did the activity occur relative to the PerfMon and Storport timeline?

Architecture references:

- [Architecture overview](Architecture.md)
- [High-level design](HLD.md)
- [Low-level design](LLD.md)
- [Implementation notes](Implementation-Notes.md)
- [Problem, value, and measured speed](PerformanceAnalyzer-Problem-Value-and-Speed.md)

## Requirements

- Windows PowerShell 5.1
- Administrator privileges for capture
- Windows Performance Recorder (`wpr.exe`)
- Windows Performance Toolkit (`xperf.exe`) for ETL decoding
- `diskspd.exe` in the tool directory when `-SetBaseline` is used

## Files

| File | Purpose |
|---|---|
| `Capture-StorageDiagnostics.ps1` | Starts and stops the capture providers. |
| `PerformanceAnalyzer.exe` | Discovers inputs, runs native parsers, hosts the local dashboard, and opens the browser. |
| `Show-PerfCounterDashboard.ps1` | Embedded data model, cache orchestration, HTTP API, HTML, CSS, and JavaScript. |
| `PerformanceAnalyzer.cs` | Native host and streaming Storport, process-volume, and minifilter aggregators. |
| `PerformanceAnalyzer-Minifilter.wprp` | Bounded memory-mode WPR profile for Filter Manager, file, process, driver, and disk events. |

## Capture command combinations

Run capture commands from an elevated Windows PowerShell prompt.

| Goal | Command | Main output |
|---|---|---|
| Standard storage capture | `.\Capture-StorageDiagnostics.ps1` | BLG, Storport ETL, ProcessVolume ETL, mapping, manifest |
| Store captures under another root | `.\Capture-StorageDiagnostics.ps1 -OutputRoot D:\StorageTraces` | Same as standard capture under the selected root |
| Change the ProcessVolume circular limit | `.\Capture-StorageDiagnostics.ps1 -ProcessIoTraceMaxMB 2048` | Standard capture with a 2-GB ProcessVolume limit |
| Capture minifilter callbacks | `.\Capture-StorageDiagnostics.ps1 -MiniFilter` | BLG, Storport ETL, MiniFilter ETL, filter inventory, mapping, manifest |
| DiskSpd baseline only | `.\Capture-StorageDiagnostics.ps1 -SetBaseline` | BLG, Storport ETL, DiskSpd XML, mapping, manifest |
| DiskSpd baseline plus process-volume trace | `.\Capture-StorageDiagnostics.ps1 -SetBaseline -ProcessETL` | Baseline outputs plus ProcessVolume ETL |
| DiskSpd baseline plus minifilter trace | `.\Capture-StorageDiagnostics.ps1 -SetBaseline -MiniFilter` | Baseline outputs plus MiniFilter ETL and filter inventory |
| Minifilter baseline under another root | `.\Capture-StorageDiagnostics.ps1 -SetBaseline -MiniFilter -OutputRoot D:\StorageTraces` | Combined baseline/minifilter capture under the selected root |

### Switch interaction

- A standard capture already collects `ProcessVolume.etl`; `-ProcessETL` is
  mainly needed with `-SetBaseline`.
- `-MiniFilter` does not start a separate `ProcessVolume.etl`. The
  `MiniFilter.etl` profile already includes the process, file, and disk events
  needed for process-volume attribution.
- `-ProcessETL` is therefore unnecessary when `-MiniFilter` is selected.
- `-ProcessIoTraceMaxMB` applies to `ProcessVolume.etl`, not to the custom WPR
  minifilter profile.

## What `-MiniFilter` captures

The custom WPR profile uses memory logging with 256 buffers of 1 MB each. It
enables:

- `DiskIO`
- `Drivers`
- `FileIO`
- `FileIOInit`
- `FilterIO`
- `FilterIOFailure`
- `FilterIOFastIO`
- `FilterIOInit`
- `Loader`
- `ProcessThread`

The bounded memory design avoids an unbounded ETL and reduces self-observation
from writing a large file-mode trace. At stop time WPR writes `MiniFilter.etl`.
Under sustained high event rates, the oldest buffered events can be replaced.
Always review the lost-event and unmatched-callback metadata.

The minifilter capture folder normally contains:

```text
Storage_*.blg
Storport.etl
MiniFilter.etl
MiniFilterInventory.json
DiskMapping.json
CaptureManifest.json
DiskSpd-baseline.xml        # only with -SetBaseline
```

## Analyzer command combinations

### Recommended folder analysis

```powershell
.\PerformanceAnalyzer.exe C:\PerfLogs\StorageCapture-YYYYMMDD-HHMMSS
```

Equivalent explicit form:

```powershell
.\PerformanceAnalyzer.exe --folder C:\PerfLogs\StorageCapture-YYYYMMDD-HHMMSS
```

Folder mode discovers the BLG, Storport ETL, ProcessVolume or MiniFilter ETL,
mapping, manifest, and optional DiskSpd XML.

### Individual and combined inputs

| Goal | Command |
|---|---|
| BLG only | `.\PerformanceAnalyzer.exe C:\Path\Storage.blg` |
| Storport ETL only | `.\PerformanceAnalyzer.exe --etl C:\Path\Storport.etl` |
| Process-volume trace | `.\PerformanceAnalyzer.exe --process-etl C:\Path\ProcessVolume.etl --mapping C:\Path\DiskMapping.json` |
| Minifilter trace | `.\PerformanceAnalyzer.exe --minifilter-etl C:\Path\MiniFilter.etl --mapping C:\Path\DiskMapping.json` |
| PerfMon and Storport | `.\PerformanceAnalyzer.exe --blg C:\Path\Storage.blg --etl C:\Path\Storport.etl` |
| PerfMon, Storport, and mapping | `.\PerformanceAnalyzer.exe --blg C:\Path\Storage.blg --etl C:\Path\Storport.etl --mapping C:\Path\DiskMapping.json` |
| Full explicit minifilter set | `.\PerformanceAnalyzer.exe --blg C:\Path\Storage.blg --etl C:\Path\Storport.etl --minifilter-etl C:\Path\MiniFilter.etl --mapping C:\Path\DiskMapping.json` |
| Add a DiskSpd result | Add `--diskspd-xml C:\Path\DiskSpd-baseline.xml` to a supported combination |
| Do not open the browser | Add `--no-browser` |
| Request a specific port | Add `--port 9000` |
| Version | `.\PerformanceAnalyzer.exe --version` |
| Help | `.\PerformanceAnalyzer.exe --help` |

The dashboard binds only to `127.0.0.1`. The default port is `8765`. If that
port is occupied, the analyzer checks the next local ports and prints the
actual URL, for example:

```text
Warning: Port 8765 is already in use. Using port 8766.
Dashboard: http://127.0.0.1:8766/
```

## Minifilter dashboard workflow

Select the **Minifilter** category and choose one of two views.

### Hot files by minifilter

Grouping:

```text
Volume + Minifilter + Absolute file path
```

Use this view first. It combines the selected processes, major functions, and
callback phases to rank files by:

- callback count;
- cumulative callback duration;
- maximum callback duration;
- derived average callback duration.

This view exposes churn. For example, 10,000 callbacks averaging 1 ms produce
10 seconds of cumulative callback time even when no individual callback looks
large.

### Detailed callbacks

Grouping:

```text
Volume + Minifilter + Process/PID + Major function +
Callback phase + Absolute file path
```

Use this view after identifying a hot file or filter. It separates the
contribution by process, operation, and pre/post callback phase.

### Filters and timeline

The view supports:

- volume;
- minifilter;
- process/PID;
- checkbox selection of one or more major functions;
- callback phase;
- partial absolute-file-path search;
- unresolved-path inclusion;
- ordering by total duration, count, maximum, or average.

The major-function picker displays the checked function names. In Hot files
view the selected functions are intentionally combined and listed in the
Major Function Name column. In Detailed callbacks each function has its own
row.

The shared PerfMon Start/End range is sent to the minifilter API. One-second
callback buckets overlapping that range are reaggregated, so the minifilter
table and graphs refer to the same time window.

The local API sorts and returns at most the first 1,000 matching rows. The
summary above the table reports totals across all matching rows, not only the
visible first 1,000.

## How to interpret duration

```text
Callback duration = completion timestamp - initialization timestamp
Average duration  = cumulative duration / completed callback count
```

Important boundaries:

- Minifilter duration measures a Filter Manager callback interval above the
  lower storage stack.
- Storport duration measures a storage-port request interval.
- DiskSpd measures application-visible I/O completion for its workload.
- PerfMon disk latency is a cooked interval-level counter.

These values can be aligned by time, but they must not be added together or
subtracted from one another.

`CREATE`, `CLEANUP`, and `CLOSE` callback counts are activity indicators; they
are not guaranteed to equal unique user-mode open/close calls.

## Cache behavior

The analyzer prints the cache folder and a two-column list of cache files:

```text
%TEMP%\PerformanceAnalyzer
```

Cache layers include:

| Cache | Purpose |
|---|---|
| Decoded ETW CSV | XPerf output reused by process-volume and minifilter parsing |
| Storport processed cache | Native Storport aggregation |
| Process-volume processed cache | Native process/volume aggregation |
| Minifilter processed cache | Summary series and parser metadata |
| Minifilter detail cache | GZip-compressed binary one-second detail buckets |

Cache keys include source identity such as filename, length, last-write ticks,
and mapping signature where mapping affects the result. Schema-version changes
force a one-time rebuild.

Close all analyzer instances before deleting cache files. Deleting the cache
does not delete the original ETL; reopening the trace rebuilds it.

## Troubleshooting

### `Only one usage of each socket address...`

Older builds failed when port `8765` was occupied. The current build
automatically selects the next available loopback port. Use the URL printed in
the console.

### `Failed to fetch`

The browser page has lost its local analyzer server. Close or refresh the stale
page and launch `PerformanceAnalyzer.exe` again.

### Minifilter trace cannot start

- Run PowerShell elevated.
- Confirm `wpr.exe` is available.
- Stop any other active WPR recording.
- Confirm `PerformanceAnalyzer-Minifilter.wprp` is beside the capture script.

### Minifilter analysis cannot start

- Install the Windows Performance Toolkit so `xperf.exe` is available.
- Supply `DiskMapping.json`.
- Confirm the ETL and mapping belong to the same capture.

### Paths are unresolved

Enable **Include unresolved paths** to inspect unmapped values. Missing or
incomplete `DiskMapping.json` prevents NT-device paths from being converted to
drive-letter or volume paths.
