# PerformanceAnalyzer: complete capture and command reference

[Quick installation and capture commands](../README.md).

PerformanceAnalyzer is distributed as two role-specific Windows packages:

| Package | Audience | Purpose |
| --- | --- | --- |
| Customer capture kit | External customers | Collect storage diagnostics for support |
| Engineer analysis kit | Support engineers | Analyze captures with the desktop analyzer and Copilot integration |

The packages are intentionally separate. Customers do not receive the analyzer,
MCP server, Copilot skill, or embedded terminal.

## Download

[Download PerformanceAnalyzer Coach 2.5.0-coach.7](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.5.0-coach.7)

Use the Coach release for engineer analysis. This is a prerelease; the
download and installation instructions below select it explicitly.

Release assets:

- `performanceanalyzer-customer-capture-kit-2.5.0-coach.7.zip`
- `performanceanalyzer-customer-capture-kit-2.5.0-coach.7.zip.sha256`
- `performanceanalyzer-engineer-analysis-kit-2.5.0-coach.7.zip`
- `performanceanalyzer-engineer-analysis-kit-2.5.0-coach.7.zip.sha256`

Verify each ZIP against its matching SHA-256 file before extraction.

### Coach features

PerformanceAnalyzer `2.5.0-coach.7` fixes Storport average-latency graph loading,
sparse/single-sample plots, and stale readings after failed range requests.
It also fixes native command labels such as `READ(10) [0x28]` and captured
minifilter disk-partition identity matching, and supports larger bounded
minifilter duration groups. Upgrade both the analyzer and MCP/skill package;
run the new kit's `Ai Integration\Integrate-Copilot.ps1` and restart Copilot CLI rather than retaining
an older MCP executable.

Validated against a real capture: all **15,458 available graphs** passed
full-range data and canvas checks, with selected-range checks including an
explicit unavailable-latency message for one idle Storport interval.
All **36 MCP tools** and the seven-step Coach foundation passed live
stdio, HTTP, and dashboard integration checks.

Coach starts with the captured disk number and
volume identity, validates their mapping, and classifies the investigation as
storage performance/latency. Coach introduces Storport average and maximum
latency for the selected operation/opcode, then matching PerfMon latency,
average queue length, current queue length, throughput, and minifilter callback
activity. It explains sampling intervals and distinct measurement boundaries;
minifilter duration is not latency minus Storport.

Beginner, Guided, and Expert change explanation depth. The initial foundation
preserves observation, correlation, hypothesis and verification gates.
Unavailable sources/counters require explicit acknowledgement instead of
substituting another disk or operation. Verified completion unlocks the wider
read-only analysis for the same capture; a different capture resets the
foundation. PerfMon-counter and educational questions remain available at
every stage. Progress, hints, graph revisiting, context correction and reusable
investigation summaries remain available. Coach can be unembedded into a
separate resizable window.

Graphs in the middle pane can be reordered with the header's **Move** drag
handle, **Up**/**Down** buttons, or **Alt+Up/Down** on the handle. Escape cancels
a drag. Reordering preserves data, colours, time range and aligned readings
without reloading samples. New graphs append, range changes preserve order,
and **Undo Coach arrangement** restores the previous layout. Order is
session-only.

## Automated engineer installation

Run this command from Windows PowerShell:

```powershell
$path = Join-Path $env:TEMP 'Install-PerformanceAnalyzer.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/sashaOM231190/PerformanceAnalyzer/main/Install-PerformanceAnalyzer.ps1' -OutFile $path -UseBasicParsing; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Version 2.5.0-coach.7
```

The bootstrap automatically requests administrator access, downloads and
verifies the engineer package for the explicitly selected Coach version,
installs the engineer tools and configures the Copilot integration.
It does not download/cache the customer ZIP or create a `Packages` folder.
Download the customer-only ZIP and matching checksum from the release page
when needed for handoff. An existing `C:\PerformanceAnalyzer\Packages` cache
is unused; check its contents before manually deleting it.

Keep `-Version 2.5.0-coach.7` in this command to select Coach. Omitting
`-Version` uses the separate default channel in `latest-version.txt`, which
has not been switched to Coach. For a newer recommended Coach release,
update the explicit version only after its release assets are available.

## Requirements

- Windows PowerShell 5.1
- Administrator privileges for data capture
- Windows Performance Recorder (`wpr.exe`) for `-MiniFilter` capture only
- Windows Performance Toolkit (`xperf.exe`) on the engineer's machine for ETL decoding
- GitHub Copilot CLI on the engineer's machine for Copilot-assisted analysis

## Customer capture workflow

1. Download the customer capture kit and matching checksum.
2. Verify the ZIP's SHA-256 hash.
3. Extract the ZIP to `C:\`.
4. Open Windows PowerShell as Administrator and run:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PerformanceAnalyzer\2.5.0-coach.7\capture_tools\Capture-StorageDiagnostics.ps1" -MiniFilter`.
5. Follow the capture instructions.
6. Compress the complete `C:\PerfLogs\StorageCapture-*` directory.
7. Transfer the archive through the approved support channel.

The capture kit contains the PowerShell capture script, DiskSpd, its license,
and the Minifilter WPR profile. It does not install software or Copilot
components.

### Where to get the capture script

**Cloning this repository does not provide the capture script.** Capture tools
are distributed in the customer ZIP on the [Coach release page](https://github.com/sashaOM231190/PerformanceAnalyzer/releases/tag/v2.5.0-coach.7),
not as tracked source files. Local `PerformanceAnalyzer-Packaging` staging
directories and ZIPs are ignored by Git and are not part of a fresh clone.
`Install-PerformanceAnalyzer.ps1` installs engineer tools; it is not the data
capture script.

Download `performanceanalyzer-customer-capture-kit-2.5.0-coach.7.zip` and its matching
`.sha256`, verify them using [Verify a download](#verify-a-download), and extract
the ZIP to `C:\`. Keep these files together:

```text
C:\PerformanceAnalyzer\2.5.0-coach.7\
  readme.txt
  capture_tools\
    Capture-StorageDiagnostics.ps1
    diskspd.exe
    PerformanceAnalyzer-Minifilter.wprp
```

This capture reference describes the **2.5.0-coach.7 customer kit**. For another
release, substitute its version in the paths and check that release's script
parameters and bundled DiskSpd help.

### Before capturing

Use an elevated **Windows PowerShell 5.1** window on the affected machine.
The script checks administrator membership and fails if it is not elevated.
It uses Windows `logman.exe`, the Windows storage/CIM cmdlets, and, for
minifilter inventory, `fltmc.exe`. WPR is required only for `-MiniFilter`;
DiskSpd is required only for `-SetBaseline`.

Choose an output drive with enough free space and, where practical, separate
from the storage being investigated: writing traces also generates I/O.
Allow for a 300 MB circular BLG, a 1,024 MB circular Storport ETL, the selected
process ETL size, and any minifilter ETL written at stop. A new preset baseline
also creates a **10 GiB test file** on the workload target drive.

Coordinate with anyone running WPR or other kernel tracing. Normal process
capture uses `NT Kernel Logger` and refuses to start if that session already
exists. `-MiniFilter` refuses to start if it detects another WPR recording.
Do not stop another person's diagnostic session just to make this capture run.

**Standard capture observes the existing workload. `-SetBaseline` actively
generates storage load and can write data.** Obtain approval before running a
baseline on a production system, and use a dedicated disposable test file.
Capture data can contain machine names, process names, file paths, volume
labels, disk serial numbers and other identifiers; it is not anonymized.

### Quick start: reproduce an existing problem

The repackaged kit has no `start-capture.cmd`. Run the PowerShell script
directly from an elevated window. Include `-MiniFilter` when filter callbacks
are required; it is not enabled by default:

```powershell
Set-Location 'C:\PerformanceAnalyzer\2.5.0-coach.7\capture_tools'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  '.\Capture-StorageDiagnostics.ps1' -MiniFilter
```

Wait until the collectors are running and the script says to reproduce the
issue. Reproduce it, then press **Enter in the capture window** promptly after
the symptom. Wait for stopping, mapping collection, and the final
`Capture complete.` message before compressing the folder. Do not close the
window or copy active ETLs instead of stopping normally.

There is no capture-duration parameter: normal capture waits for Enter.
Circular traces retain the most recent data, not necessarily the complete
time since startup. Keep the reproduction short enough to retain the event of
interest, and record the symptom's time and time zone for the engineer.

In this command, `-NoProfile`, `-ExecutionPolicy Bypass`, and `-File` are
**powershell.exe options**, not capture parameters. They respectively avoid
loading PowerShell profiles, set execution policy for this child process,
and execute the named script. `Bypass` does not permanently change machine
policy or override organizational policy.

### Complete capture parameter reference

All five script-defined parameters are optional:

| Parameter | Type / default | Allowed values and behavior |
| --- | --- | --- |
| `-OutputRoot <path>` | String; `C:\PerfLogs` | Non-null, non-empty output root. Creates `StorageCapture-yyyyMMdd-HHmmss` underneath it, creating directories as needed. Use a writable path and quote paths containing spaces. This selects trace output, **not** the DiskSpd workload target. |
| `-ProcessIoTraceMaxMB <number>` | Integer; `1024` | Inclusive range **256-8192 MB**. Caps the circular `ProcessVolume.etl` only. Does not change BLG, Storport, or minifilter limits. Has no effect when process ETL is not enabled or `-MiniFilter` is used. |
| `-SetBaseline` | Switch; off | Prompts for a DiskSpd preset or custom command, starts the selected collectors, runs DiskSpd, and stops automatically when DiskSpd finishes. Produces `DiskSpd-baseline.xml`. By default, baseline mode collects BLG and Storport only. |
| `-ProcessETL` | Switch; off | Adds `ProcessVolume.etl` **during baseline mode**. Standard capture already includes it, so this switch is redundant without `-SetBaseline`. `-MiniFilter` takes precedence and supplies process/file/disk events in its own ETL. |
| `-MiniFilter` | Switch; off | Uses the adjacent `PerformanceAnalyzer-Minifilter.wprp` with WPR profile `PerformanceAnalyzerMiniFilter.Light`. Records filter callbacks plus process, image, file and disk events in `MiniFilter.etl`; attempts to write `MiniFilterInventory.json`. Can be combined with `-SetBaseline`. Does not create a separate `ProcessVolume.etl`. |

Switches take no following value; omit them to use the default behavior.
PowerShell also supports explicit switch syntax such as `-MiniFilter:$false`.
Parameter names are case-insensitive. DiskSpd option letters, by contrast,
are case-sensitive.

Because the script uses `[CmdletBinding()]`, PowerShell's common parameters
are also accepted: `-Verbose`, `-Debug`, `-ErrorAction`, `-WarningAction`,
`-InformationAction`, `-ErrorVariable`, `-WarningVariable`,
`-InformationVariable`, `-OutVariable`, `-OutBuffer`, and `-PipelineVariable`.
They control PowerShell streams/preferences; they are not additional
collectors, durations, or size controls. The script explicitly sets
`$ErrorActionPreference = 'Stop'` and checks native collector exit codes, so
do not rely on `-ErrorAction` to turn a failed capture into a successful one.
There is **no `-WhatIf`, `-Confirm`, `-Duration`, or script-defined `-Help`**
parameter.

Read the script's built-in help without starting a capture:

```powershell
Get-Help '.\Capture-StorageDiagnostics.ps1' -Full
Get-Command '.\Capture-StorageDiagnostics.ps1' -Syntax
```

### Which flags collect which data?

PerfMon BLG, Storport ETL, disk mapping and the manifest are common to all
successful modes:

| Capture flags | Process/file/disk source | Filter callbacks / inventory | DiskSpd XML | How capture ends |
| --- | --- | --- | --- | --- |
| None, or `-ProcessETL` alone | `ProcessVolume.etl` | No | No | Press Enter after reproduction |
| `-MiniFilter` (with or without `-ProcessETL`) | `MiniFilter.etl` | Yes | No | Press Enter after reproduction |
| `-SetBaseline` | Not collected | No | Yes | DiskSpd finishes |
| `-SetBaseline -ProcessETL` | `ProcessVolume.etl` | No | Yes | DiskSpd finishes |
| `-SetBaseline -MiniFilter` (with or without `-ProcessETL`) | `MiniFilter.etl` | Yes | Yes | DiskSpd finishes |

In minifilter mode the manifest deliberately lists `MiniFilter.etl` as the
process I/O source. The absence of `ProcessVolume.etl` is expected, not a
missing collector.

### Capture examples

Run these from the extracted `capture_tools` directory in elevated Windows
PowerShell. Each example is a separate capture; do not run them concurrently.

```powershell
# Existing application problem; custom output and 2,048 MB process trace.
& '.\Capture-StorageDiagnostics.ps1' `
  -OutputRoot 'D:\Storage Traces' -ProcessIoTraceMaxMB 2048

# Existing problem with minifilter callback tracing.
& '.\Capture-StorageDiagnostics.ps1' `
  -MiniFilter -OutputRoot 'D:\StorageTraces'

# Interactive baseline with BLG and Storport only.
& '.\Capture-StorageDiagnostics.ps1' -SetBaseline

# Baseline with a separate process-volume trace.
& '.\Capture-StorageDiagnostics.ps1' `
  -SetBaseline -ProcessETL -ProcessIoTraceMaxMB 2048

# Baseline with minifilter and process/file/disk events in MiniFilter.etl.
& '.\Capture-StorageDiagnostics.ps1' `
  -SetBaseline -MiniFilter -OutputRoot 'D:\StorageTraces'
```

### DiskSpd baseline: prompts, presets and safety

With `-SetBaseline`, configure the workload **before** collectors start:

1. Choose preset `1`-`4`, or `5` for a custom command. Enter alone selects `1`.
2. For a preset, enter a drive letter or test file path. The default `C:`
   becomes `C:\DiskSpdBaseline.dat`; a drive such as `D:` becomes
   `D:\DiskSpdBaseline.dat`. A supplied file path is used as entered after
   normalization. Its parent directory must already exist.
3. Review any existing-file warning. Write presets `1` and `4` require the
   exact confirmation `YES` when the target file already exists.
4. The collectors start, DiskSpd runs, and the collectors stop automatically.
   Do not press Enter to stop a baseline as you would a normal capture.

| Preset | Workload-specific flags | Workload |
| --- | --- | --- |
| `1` (default) | `-b64K -o8 -t4 -r -w30` | Random 64 KiB, 70% reads / 30% writes; up to 32 outstanding requests across 4 threads |
| `2` | `-b4K -o32 -t4 -r -w0` | Random 4 KiB, read-only; up to 128 outstanding requests across 4 threads |
| `3` | `-b1M -o8 -t2 -s -w0` | Sequential 1 MiB, read-only; up to 16 outstanding requests across 2 threads |
| `4` | `-b1M -o8 -t2 -s -w100` | Sequential 1 MiB, write-only; up to 16 outstanding requests across 2 threads |
| `5` | User-supplied command, adjusted as below | Custom workload |

All four built-in presets append
`-Sh -W0 -d60 -C0 -L -D1000 -Rxml`. If the target file does not exist,
the script also adds `-c10G`. They measure for **60 seconds with no warmup or
cooldown**; file creation and collector startup/stop add time outside that
measurement. Even a read-only preset creates/writes a new file if necessary.

| Shared flag | Meaning |
| --- | --- |
| `-c10G` | Create a 10 GiB test file when the target does not already exist. |
| `-Sh` | Disable software caching and request write-through (`-Su -Sw` behavior). This is an I/O mode, not proof that all storage-system caches are disabled. |
| `-W0` | Zero seconds of warmup before measurement. |
| `-d60` | Measure the workload for 60 seconds. |
| `-C0` | Zero seconds of cooldown after measurement. |
| `-L` | Collect latency statistics. |
| `-D1000` | Collect per-thread/per-target IOPS statistics at 1,000 ms intervals; XML includes the time series. |
| `-Rxml` | Emit XML for the analyzer rather than text. |

Use only a disposable test file, never an application database or valuable
existing file. Raw physical-disk targets are blocked by the baseline
workflow. Existing target files are retained and may have been modified;
only a target that the script considered newly created is removed during
cleanup. If removal fails, the script warns and the file remains.

#### Custom baseline command (menu choice 5)

At the prompt, enter one DiskSpd command, for example:

```text
diskspd.exe -c10G -d60 -W20 -C0 -r8K -w0 -b64K -t4 -o8 -Sh -L -D1000 -Rxml D:\PerfTest\disposable.dat
```

`D:\PerfTest` must already exist and have enough free space. The script:

- Always invokes **its adjacent `diskspd.exe`**, not an arbitrary executable
  supplied in the command.
- Requires exactly one target and a local drive/file path. Raw disk targets
  and shell operators/redirection are rejected; this is not a shell command
  runner.
- Replaces the target filename with **`DiskSpdBaseline.dat` in the supplied
  directory**. In the example, the effective target is
  `D:\PerfTest\DiskSpdBaseline.dat`, not `disposable.dat`.
- Adds `-Rxml` and `-L` if absent. Supply `-Rxml` explicitly and do not include
  competing result formats or profile-only `-Rp...` modes.
- Requires `-c<size>` if the effective file does not exist. An existing
  `DiskSpdBaseline.dat` can be modified or resized by the custom workload.
- Displays adjustments and the effective command, then requires `Y` or
  `Yes` confirmation. Records the original and effective commands in the
  capture manifest.

For custom commands, DiskSpd defaults are 10 seconds of measurement,
5 seconds of warmup and zero cooldown unless `-d`, `-W` and `-C` override
them. Choose explicit timing flags for reproducible tests.

The custom parser is intended for a **single-file command-line workload**.
Do not use XML profiles (`-X`), synchronization-only commands (`-ye`), or
DiskSpd-owned kernel ETW (`-e...`) through it: XML targets are not covered by
the filename rewrite, synchronization-only commands do not produce a
baseline result, and kernel ETW can conflict with the capture's own session.
For a separately approved workload that does not fit the custom parser, run
a normal capture, run DiskSpd separately, then press Enter after the workload
finishes. Separately generated results are not automatically recorded as an
integrated baseline in the manifest; retain their XML and command details
with the capture.

### Bundled DiskSpd option reference

The 2.5.0-coach.7 kit bundles DiskSpd **2.2.0**. The following covers its help-listed
flags, including advanced flags not used by the presets. They are
**DiskSpd options**, not parameters to `Capture-StorageDiagnostics.ps1`.
Availability in DiskSpd does not imply compatibility with the custom
baseline parser; follow the restrictions above.

Read the executable's authoritative help without generating load:

```powershell
& '.\diskspd.exe' '-?'
```

Sizes are integer bytes, optionally suffixed with `K`, `M`, `G`, `T`
(KiB/MiB/GiB/TiB) or `b` (blocks of the size selected by `-b`).

| Flag | Meaning / default |
| --- | --- |
| `-?` | Show usage; does not run a workload. |
| `-:<flags>` | Experimental bitmask; bit `1` permits throughput-limit sleeps longer than 1 ms. |
| `-ag` | Default group affinity: assign threads round-robin to CPUs, filling processor groups in order. |
| `-a[g#,]#[,#,...]` | Explicit CPU/group affinity, e.g. `-a0,1` or `-ag0,0,1,g1,0,1`. |
| `-n` | Disable default CPU affinity. |
| `-b<size>` | I/O block size; default `64K`. Also defines size units for suffix `b`. |
| `-B<base>[:length]` | Limit I/O to a base offset and optional length; default is the whole target. |
| `-c<size>` | Create file targets of this size; incompatible with non-file targets. Can modify an existing file. |
| `-d<seconds>` | Measurement duration; default `10`. |
| `-W<seconds>` | Warmup duration before measurement; default `5`. |
| `-C<seconds>` | Cooldown duration after measurement; default `0`. |
| `-D<milliseconds>` | IOPS statistics interval; default `1000`. XML includes per-thread/per-target series. |
| `-f<size>` | Maximum target offset, exclusive; equivalent to bounds specified with `-B`. |
| `-f<rst>` | File access hints: `r` random access, `s` sequential scan, `t` temporary; combinable. |
| `-F<count>` | Total thread count; conflicts with `-t`. |
| `-t<count>` | Threads per target; conflicts with `-F`. Presets set this explicitly. |
| `-o<count>` | Outstanding requests per target per thread; default `2`. |
| `-O<count>` | Outstanding requests per thread when using `-F`. |
| `-g<value>[i]` | Per-thread/per-target throughput limit in bytes/ms, or IOPS with suffix `i`; incompatible with `-x`. Default: unlimited. |
| `-i<count>` | I/Os per burst; used with `-j`. Default: inactive. |
| `-j<milliseconds>` | Interval between bursts; used with `-i`. Default: inactive. |
| `-I<priority>` | I/O priority: `1` very low, `2` low, `3` normal (default). |
| `-l` | Use large pages for I/O buffers. |
| `-L` | Collect latency statistics. |
| `-p` | Parallel sequential I/O starting at the same offset; useful with `-o2` or greater, ignored with `-r`. |
| `-P<count>` | Progress dot after this many completed I/Os per thread; default count `65536` when enabled. |
| `-r[align]` | Random I/O; optional offset alignment, default block size. Overrides `-s`. |
| `-rd<dist>[params]` | Nonuniform random distribution: `pct` uses I/O%/target% ranges; `abs` uses I/O%/target-size ranges. Default random distribution is uniform. |
| `-rs<percentage>` | Percentage of requests issued randomly; remaining requests form sequential runs. |
| `-s[i][align]` | Sequential stride/alignment; default block size, independent offsets per thread. `-si` shares an interlocked offset; conflicts with `-p`, `-rs`, `-T`. Ignored with `-r`. |
| `-T<offs>` | Starting separation between sequential threads on one target; default `0`. Conflicts with `-r` and `-si`. |
| `-R[p]<text|xml>` | Output format; default text. Optional `p` validates/re-emits a profile without running load. Use `-Rxml` for analyzer results. |
| `-S[bhmruw]` | Caching controls; combine nonconflicting letters. Default: caching enabled, no write-through. |
| `-S`, `-Su` | Disable software caching (`FILE_FLAG_NO_BUFFERING`). |
| `-Sb` | Explicitly enable caching (default). |
| `-Sh` | Equivalent to `-Suw`: unbuffered plus write-through. |
| `-Sm` | Memory-mapped I/O. |
| `-Sr` | Disable local caching while retaining remote software caching; remote filesystems only. |
| `-Sw` | Write-through (`FILE_FLAG_WRITE_THROUGH`), or non-temporal writes with memory-mapped I/O. |
| `-h` | Deprecated alias; use `-Sh`. |
| `-N<vni>` | Memory-mapped flush mode: `v` uses `FlushViewOfFile`, `n` uses `RtlFlushNonVolatileMemory`, `i` uses that API without waiting for drain. Default: none. |
| `-v[s]` | Verbose output; `-vs` adds summary statistics only. |
| `-w<percentage>` | Write percentage; absent, `-w`, or `-w0` means reads only. **Write tests can destroy existing target data.** |
| `-x` | Completion routines instead of I/O completion ports. |
| `-X<filepath>` | XML workload profile, optionally with command-line target substitutions. Not supported by the integrated custom baseline workflow. |
| `-z[seed]` | Random seed; absent uses `0`, bare `-z` seeds from system runtime. |
| `-Z` | Zero-filled write buffers. |
| `-Zr` | Generate random data per I/O; adds runtime overhead. |
| `-Z<size>` | Random-data source buffer of this size for writes. |
| `-Z<size>,<file>` | Write source buffer populated from a file. Default without `-Z...`: repeating byte pattern `0`-`255`. |
| `-ys<eventname>` | Signal a named event before the measured run, after warmup. |
| `-yf<eventname>` | Signal a named event after the measured run, before cooldown. |
| `-yr<eventname>` | Wait on a named event before the run, including warmup. |
| `-yp<eventname>` | Stop when a named event is signaled; Ctrl+C is bound to it. |
| `-ye<eventname>` | Signal a named event and exit; no baseline workload/result. |
| `-e<q|c|s>` | ETW timer: performance counter (default `q`), cycle count (`c`), system timer (`s`). Avoid DiskSpd-owned ETW during this capture. |
| `-ep` | Paged memory for `NT Kernel Logger`; default nonpaged. |
| `-ePROCESS` | ETW process start/end. |
| `-eTHREAD` | ETW thread start/end. |
| `-eIMAGE_LOAD` | ETW image loads. |
| `-eDISK_IO` | ETW physical disk I/O. |
| `-eMEMORY_PAGE_FAULTS` | ETW all page faults. |
| `-eMEMORY_HARD_FAULTS` | ETW hard page faults only. |
| `-eNETWORK` | ETW TCP/IP and UDP/IP sends/receives. |
| `-eREGISTRY` | ETW registry activity. |

DiskSpd itself supports file, physical-drive and volume targets, but the
integrated baseline restricts targets as described above. Do not interpret
this reference as approval to run destructive raw-device tests.

### Collection settings and output files

These collector settings are fixed in the 2.5.0-coach.7 script unless a parameter
above explicitly changes them:

| Collector | Settings / scope |
| --- | --- |
| PerfMon | One-second sampling; circular binary log capped at 300 MB. All counters in `LogicalDisk(*)`, `Memory`, `Network Interface(*)`, `Paging File(*)`, `PhysicalDisk(*)`, `Processor(*)`, `Process(*)`, `Redirector`, `Server`, and `System`. |
| Storport | `Microsoft-Windows-StorPort`, keyword mask `0xffffffffffffffff`, level `0xff`; circular ETL capped at 1,024 MB; 16 buffers of 1,024 KB. |
| Process-volume | `Windows Kernel Trace`, keyword mask `0x06000707`, level `0x5`; circular ETL capped by `-ProcessIoTraceMaxMB`; 16-256 buffers of 1,024 KB; session `NT Kernel Logger`. |
| Minifilter | WPR memory-mode `PerformanceAnalyzerMiniFilter.Light`; 256 buffers of 1,024 KB (256 MiB configured buffer capacity), flushed to ETL at stop. Includes `DiskIO`, `Drivers`, `FileIO`, `FileIOInit`, `FilterIO`, `FilterIOFailure`, `FilterIOFastIO`, `FilterIOInit`, `Loader`, and `ProcessThread`. |

Minifilter's buffer capacity is **not an ETL file-size cap**.
`-ProcessIoTraceMaxMB` does not resize these WPR buffers. All circular or
memory-buffer captures have finite retention; older events may be overwritten
and events can be lost under load.

| Output | When produced / purpose |
| --- | --- |
| `Storage*.blg` | Every successful mode; PerfMon samples. The script requests `Storage.blg`, but Logman applies a date/time filename suffix. Use the actual filename or the manifest's `PerfmonFiles`. |
| `Storport.etl` | Every successful mode; Storport request activity. |
| `ProcessVolume.etl` | Normal capture, or baseline with `-ProcessETL`, when not using `-MiniFilter`. |
| `MiniFilter.etl` | With `-MiniFilter`; filter callbacks and process/file/disk correlation in one ETL. |
| `MiniFilterInventory.json` | With `-MiniFilter`, if inventory collection succeeds; loaded filter names, instance counts, altitudes and frames. |
| `DiskMapping.json` | After collectors stop; disk numbers, PerfMon instances, SCSI addressing, disk identity, partitions, drive letters, volume and NT device paths. |
| `CaptureManifest.json` | After mapping; schema version 6, UTC start/stop, filenames, collector/source information and baseline settings. Integrated baselines include DiskSpd version/hash and custom original/effective commands. |
| `DiskSpd-baseline.xml` | With `-SetBaseline`; validated nonempty DiskSpd Results XML. |

Mapping and filter inventory are snapshots taken **after** recording stops.
Manifest start/stop timestamps bracket setup and post-processing as well as
the recording; do not assume every collector or DiskSpd measured for that
entire interval.

### Completion, troubleshooting and handoff

A valid handoff is the **whole stopped capture directory**, not just one ETL.
Confirm the final folder path, check that files appropriate to the selected
mode exist and are nonempty, and inspect any warnings before sharing.
Include a short description of the symptom, reproduction steps, affected
volume, symptom time/time zone, selected capture flags and baseline choices.
Compress the complete folder and transfer it through the approved support
channel. Use an approved archive tool capable of handling large files;
Windows PowerShell `Compress-Archive` has a 2 GB per-file limitation.

| Symptom | Action |
| --- | --- |
| Script missing after clone | Download/extract the customer release ZIP. The installer script is not a substitute for it. |
| Script says to run elevated / access denied | Open Windows PowerShell as Administrator; ensure the output location is writable. |
| Execution policy blocks the script | Use the child-process launch shown above if organizational policy permits; do not change machine-wide policy. |
| PerfMon collector creation fails | Check the printed Logman error and local counter availability. The script uses English counter paths, which may not resolve on localized Windows installations. |
| `NT Kernel Logger` already running | Coordinate with the owner of the existing trace; finish it through its own tool before retrying. |
| Another WPR recording is active | Coordinate with its owner. Do not indiscriminately cancel WPR recordings. |
| `wpr.exe` or minifilter profile missing | Ensure WPR is available and the profile remains beside the script, or use a capture without `-MiniFilter` if callback tracing is not needed. |
| `diskspd.exe` missing / target directory missing | Keep the bundled executable beside the script and create a dedicated test directory before choosing a baseline target. |
| DiskSpd fails or output is not Results XML | Review the displayed error/effective command, remove incompatible result/profile options and retry with a supported single-file workload. The script's temporary stderr file is removed after invocation. |
| No `ProcessVolume.etl` | Expected for baseline without `-ProcessETL`, and for all minifilter modes; use the mode table before treating it as a failure. |
| Stop or inventory warning | Preserve the warning text and tell the engineer. A stop failure can leave a trace incomplete; inventory is best-effort. |
| No mapping/manifest or no completion message | Treat the capture as incomplete. Collector cleanup runs in `finally` once collector setup begins, but a terminating error can prevent the later mapping/manifest steps. Preserve the error and partial output; do not label it a successful capture. |
| Issue missing from a long capture | Circular retention may have overwritten it. Repeat a shorter reproduction and stop promptly; increase the process cap only if that is the affected source. |

Do not force-close the capture window, kill unrelated trace processes, or
assume an interrupted session was cleaned up. If recording remains active,
identify the exact session and coordinate its stop with the engineer.

## Engineer analysis workflow

1. Download the engineer analysis kit and matching checksum.
2. Verify the ZIP's SHA-256 hash.
3. Extract the ZIP to `C:\`.
4. Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PerformanceAnalyzer\2.5.0-coach.7\Ai Integration\Integrate-Copilot.ps1"`.
5. Restart GitHub Copilot CLI after the installer registers the MCP server and
   installs the skill.
6. Open a received capture with:

```powershell
& 'C:\PerformanceAnalyzer\2.5.0-coach.7\analyzer\PerformanceAnalyzer.exe' `
  'C:\path\to\StorageCapture-folder'
```

The MCP server is installed per user under
`%LOCALAPPDATA%\PerformanceAnalyzer\Copilot\2.5.0-coach.7`, and the skill is installed
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
PerformanceAnalyzer\2.5.0-coach.7\
  readme.txt
  capture_tools\
```

Engineer analysis kit:

```text
PerformanceAnalyzer\2.5.0-coach.7\
  readme.txt
  Analyzer\
  CaptureKit\
    readme.txt
    capture_tools\
  Ai Integration\
    Integrate-Copilot.ps1
    Remove-CopilotIntegration.ps1
    copilot_mcp_server\
    copilot_skill\
    version.txt
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
