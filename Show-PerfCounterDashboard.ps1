<#
.SYNOPSIS
Starts a local, interactive dashboard for a Windows Performance Monitor BLG file.

.DESCRIPTION
Lists every recorded counter by category and loads counter samples only when a
chart is added. Charts are stacked vertically and share cursor and zoom ranges.
The dashboard binds only to 127.0.0.1 and does not send capture data externally.

.EXAMPLE
.\Show-PerfCounterDashboard.ps1 `
    -InputPath 'E:\StorageIssue\Perf-1Second_000001\Perf-1Second_000001.blg'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,

    [Parameter(Mandatory = $false)]
    [switch]$NoBrowser
)

if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
        throw 'Windows PowerShell 5.1 is required to read BLG counter samples.'
    }

    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $PSCommandPath
        '-InputPath'
        $InputPath
        '-Port'
        $Port.ToString()
    )
    if ($NoBrowser) {
        $arguments += '-NoBrowser'
    }

    & $windowsPowerShell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Dashboard server exited with code $LASTEXITCODE."
    }
    return
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-BlogFile {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        if ($item.Extension -ine '.blg') {
            throw "Input file must have a .blg extension: $Path"
        }
        return $item
    }

    $files = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.blg' |
        Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        throw "No .blg files were found in: $Path"
    }
    return $files[0]
}

function Get-CounterCategory {
    param([string]$CounterSet)

    switch -Regex ($CounterSet) {
        '^(Processor|Processor Information|System)$' { return 'CPU' }
        '^(PhysicalDisk|LogicalDisk|Storage Spaces)' { return 'Disk' }
        '^(Memory|Paging File|Cache)$' { return 'Memory' }
        '^Process' { return 'Process' }
        '^(Network Interface|Network Adapter|TCP|UDP|IPv4|IPv6)' { return 'Network' }
        '^(Server|SMB)' { return 'SMB' }
        default { return 'Other' }
    }
}

function Get-CounterUnit {
    param(
        [string]$CounterSet,
        [string]$Counter
    )

    switch -Regex ($Counter) {
        '(^%|%$|Hits %$)' { return '%' }
        '^Avg\. Disk sec/(?<Operation>Read|Write|Transfer)$' {
            return ('seconds/{0}' -f $Matches.Operation.ToLowerInvariant())
        }
        '^Avg\. Disk Bytes/(?<Operation>Read|Write|Transfer)$' {
            return ('bytes/{0}' -f $Matches.Operation.ToLowerInvariant())
        }
        'Bytes/sec$' { return 'bytes/s' }
        'Current Bandwidth$' { return 'bits/s' }
        '(Available MBytes|Free Megabytes)$' { return 'MiB' }
        'KBytes$' { return 'KiB' }
        '(Bytes( Peak)?|Working Set( - Private| Peak)?)$' { return 'bytes' }
        '^Pool (Nonpaged|Paged)( Peak)?$' { return 'bytes' }
        '(Reads|Writes|Transfers|Operations)/sec$' { return 'operations/s' }
        'Packets/sec$' { return 'packets/s' }
        'Pages/sec$' { return 'pages/s' }
        'Faults/sec$' { return 'faults/s' }
        'Transitions/sec$' { return 'transitions/s' }
        '(Interrupts/sec|DPC Rate|DPCs Queued/sec)$' { return 'events/s' }
        '/sec$' { return 'events/s' }
        'Queue Length$' { return 'requests' }
        '(Elapsed Time|System Up Time)$' { return 'seconds' }
        '(ID Process|Creating Process ID)$' { return 'process ID' }
        'Average Packet Size$' { return 'bytes/packet' }
        '(Dirty Pages|Dirty Page Threshold)$' { return 'pages' }
        'Entries$' { return 'entries' }
        'Allocs$' { return 'allocations' }
        'Connections$' { return 'connections' }
        '(Errors|Discarded|Unknown|Failures|Shortages|Rejected|Searches|Total)$' { return 'count' }
        '^Priority Base$' { return 'priority' }
        '(Thread Count|Threads|Active Threads)$' { return 'threads' }
        '(Handle Count|Handles|Files Open|Processes|Sessions|Current Clients)$' { return 'count' }
        default { return 'value' }
    }
}

function Split-CounterPath {
    param([string]$Path)

    $counterSet = 'Other'
    $instance = ''
    $counter = $Path
    if ($Path -match '^\\\\(?<Computer>[^\\]+)\\(?<CounterSet>[^\\(]+)(?:\((?<Instance>.*)\))?\\(?<Counter>.+)$') {
        $counterSet = $Matches.CounterSet
        if ($Matches.ContainsKey('Instance')) {
            $instance = $Matches.Instance
        }
        $counter = $Matches.Counter
    }

    [pscustomobject][ordered]@{
        Path       = $Path
        Category   = Get-CounterCategory -CounterSet $counterSet
        CounterSet = $counterSet
        Instance   = $instance
        Counter    = $counter
        Unit       = Get-CounterUnit -CounterSet $counterSet -Counter $counter
        Label      = if ([string]::IsNullOrEmpty($instance)) {
            "$counterSet\$counter"
        }
        else {
            "$counterSet($instance)\$counter"
        }
    }
}

function Get-QueryParameters {
    param([string]$Query)

    $parameters = @{}
    if ([string]::IsNullOrEmpty($Query)) {
        return $parameters
    }

    foreach ($pair in $Query.TrimStart('?').Split('&')) {
        if ([string]::IsNullOrEmpty($pair)) {
            continue
        }
        $parts = $pair.Split('=', 2)
        $name = [uri]::UnescapeDataString($parts[0].Replace('+', ' '))
        $value = if ($parts.Count -gt 1) {
            [uri]::UnescapeDataString($parts[1].Replace('+', ' '))
        }
        else {
            ''
        }
        $parameters[$name] = $value
    }

    return $parameters
}

function Send-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    $statusText = switch ($StatusCode) {
        200 { 'OK' }
        400 { 'Bad Request' }
        404 { 'Not Found' }
        500 { 'Internal Server Error' }
        default { 'OK' }
    }
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $header = "HTTP/1.1 $StatusCode $statusText`r`n" +
        "Content-Type: $ContentType`r`n" +
        "Content-Length: $($bodyBytes.Length)`r`n" +
        "Cache-Control: no-store`r`n" +
        "Access-Control-Allow-Origin: http://127.0.0.1`r`n" +
        "Connection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

function Get-CounterData {
    param(
        [string]$BlogPath,
        [string]$CounterPath,
        [string]$Start,
        [string]$End
    )

    $importParameters = @{
        Path        = $BlogPath
        Counter     = $CounterPath
        ErrorAction = 'SilentlyContinue'
    }
    if (-not [string]::IsNullOrWhiteSpace($Start)) {
        $importParameters.StartTime = ([datetimeoffset]::Parse(
            $Start,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)).LocalDateTime
    }
    if (-not [string]::IsNullOrWhiteSpace($End)) {
        $importParameters.EndTime = ([datetimeoffset]::Parse(
            $End,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)).LocalDateTime
    }

    $points = New-Object System.Collections.ArrayList
    $minimum = [double]::PositiveInfinity
    $maximum = [double]::NegativeInfinity
    $sum = [double]0
    $count = [long]0

    Import-Counter @importParameters | ForEach-Object {
        foreach ($sample in $_.CounterSamples) {
            if ($sample.Status -ne 0) {
                continue
            }

            $value = [double]$sample.CookedValue
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) {
                continue
            }

            $milliseconds = [long]([datetimeoffset]$_.Timestamp).ToUnixTimeMilliseconds()
            $null = $points.Add(@($milliseconds, $value))
            if ($value -lt $minimum) { $minimum = $value }
            if ($value -gt $maximum) { $maximum = $value }
            $sum += $value
            $count++
        }
    }

    if ($count -eq 0) {
        throw "No valid samples were returned for counter: $CounterPath"
    }

    [pscustomobject][ordered]@{
        Path    = $CounterPath
        Samples = $count
        Minimum = $minimum
        Maximum = $maximum
        Average = $sum / $count
        Points  = $points
    }
}

function Get-CaptureRange {
    param(
        [string]$BlogPath,
        [string]$CounterPath
    )

    $first = $null
    $last = $null
    Import-Counter -Path $BlogPath -Counter $CounterPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($null -eq $first -or $_.Timestamp -lt $first) {
                $first = $_.Timestamp
            }
            if ($null -eq $last -or $_.Timestamp -gt $last) {
                $last = $_.Timestamp
            }
        }

    if ($null -eq $first -or $null -eq $last) {
        throw 'Unable to determine the BLG capture time range.'
    }

    [pscustomobject]@{
        Start = $first
        End   = $last
    }
}

$html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Performance Counter Dashboard</title>
<style>
:root { font-family: "Segoe UI", Arial, sans-serif; color: #202124; }
* { box-sizing: border-box; }
body { margin: 0; background: #f4f6f8; }
header { position: sticky; top: 0; z-index: 10; background: #17365d; color: white; padding: 12px 18px; }
header h1 { margin: 0 0 4px; font-size: 20px; }
header p { margin: 0; font-size: 13px; color: #dbe7f5; }
.layout { display: grid; grid-template-columns: 350px 1fr; min-height: calc(100vh - 68px); }
aside { position: sticky; top: 68px; height: calc(100vh - 68px); overflow: auto; padding: 14px; background: white; border-right: 1px solid #ccd3da; }
main { min-width: 0; padding: 14px; }
label { display: block; margin-top: 10px; font-size: 12px; font-weight: 600; }
select, input, button { width: 100%; margin-top: 4px; padding: 7px; border: 1px solid #aeb8c2; border-radius: 4px; background: white; }
button { cursor: pointer; background: #1769aa; color: white; border-color: #1769aa; font-weight: 600; }
button.secondary { background: white; color: #17365d; }
button.danger { background: #a12622; border-color: #a12622; }
#counterList { height: 330px; font-family: Consolas, monospace; font-size: 11px; }
.buttonRow { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 10px; }
.timeGrid { display: grid; grid-template-columns: 1fr; gap: 6px; }
.timeField span { display: block; font-size: 10px; color: #5d6975; }
.rangeSlider { position: relative; height: 38px; margin: 8px 2px 2px; }
.rangeBase, .rangeSelection { position: absolute; top: 17px; height: 6px; border-radius: 4px; }
.rangeBase { left: 0; right: 0; background: #cad2db; }
.rangeSelection { background: #1769aa; }
.rangeSlider input[type="range"] {
  position: absolute; left: 0; top: 4px; width: 100%; margin: 0; padding: 0;
  appearance: none; background: transparent; border: 0; pointer-events: none;
}
.rangeSlider input[type="range"]::-webkit-slider-thumb {
  appearance: none; width: 18px; height: 18px; border-radius: 50%;
  background: #1769aa; border: 2px solid white; box-shadow: 0 0 0 1px #17365d;
  pointer-events: auto; cursor: ew-resize;
}
.rangeSlider input[type="range"]::-moz-range-thumb {
  width: 18px; height: 18px; border-radius: 50%; background: #1769aa;
  border: 2px solid white; box-shadow: 0 0 0 1px #17365d;
  pointer-events: auto; cursor: ew-resize;
}
.rangeLabels { display: flex; justify-content: space-between; gap: 8px; font-size: 10px; color: #5d6975; }
.status { margin: 0 0 12px; padding: 10px; background: #fff7d6; border: 1px solid #e6ce72; border-radius: 5px; }
.overview, .analysis { margin: 0 0 12px; padding: 10px; background: white; border: 1px solid #ccd3da; border-radius: 6px; }
.panelHeader { display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-bottom: 7px; }
.panelHeader strong { color: #17365d; }
.panelHint { color: #66727e; font-size: 11px; }
.overviewWrap { position: relative; height: 110px; }
#overviewCanvas { width: 100%; height: 110px; cursor: crosshair; border: 1px solid #d9dfe5; border-radius: 4px; }
.summaryCards { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 8px; margin-bottom: 8px; }
.summaryCard { padding: 8px; border-left: 4px solid #1769aa; background: #f4f7fa; font-size: 11px; overflow-wrap: anywhere; }
.summaryCard strong { display: block; margin-bottom: 3px; color: #17365d; }
.findingsList { margin: 0; padding-left: 22px; max-height: 230px; overflow: auto; }
.findingsList li { margin: 5px 0; padding: 4px 6px; border-radius: 3px; font-size: 11px; }
.finding-critical { background: #ffe0de; border-left: 4px solid #b42318; }
.finding-warning { background: #fff2cc; border-left: 4px solid #c47f00; }
.finding-information { background: #e9f3fb; border-left: 4px solid #1769aa; }
.zoomFinding { width: auto; margin: 0 0 0 8px; padding: 2px 7px; font-size: 10px; }
.readings, .calculator { margin: 0 0 12px; padding: 10px; background: white; border: 1px solid #ccd3da; border-radius: 6px; }
.readingsHeader { display: grid; grid-template-columns: 1fr auto; gap: 10px; align-items: center; margin-bottom: 7px; }
.readingsHeader strong { color: #17365d; }
.copyReadings { width: auto; margin: 0; padding: 5px 12px; }
#readingText { width: 100%; min-height: 86px; resize: vertical; font: 11px Consolas, monospace; white-space: pre; }
.calculatorResults { display: grid; grid-template-columns: repeat(auto-fit, minmax(310px, 1fr)); gap: 8px; }
.calculationCard { position: relative; padding: 9px 34px 9px 10px; background: #f4f7fa; border-left: 4px solid #1769aa; border-radius: 3px; }
.calculationTitle { color: #17365d; font-size: 12px; font-weight: 700; margin-bottom: 5px; }
.calculationDetail { margin: 0; white-space: pre-wrap; font: 11px Consolas, monospace; }
.helpBadge {
  position: absolute; top: 7px; right: 8px; width: 20px; height: 20px;
  border-radius: 50%; background: #1769aa; color: white; text-align: center;
  line-height: 20px; font-weight: 700; cursor: help;
}
.helpBadge:hover::after {
  content: attr(data-help); position: absolute; z-index: 80; top: 25px; right: 0;
  width: 290px; padding: 8px; border-radius: 4px; background: #17202a;
  color: white; text-align: left; line-height: 1.35; font-weight: 400;
  box-shadow: 0 2px 8px #0005;
}
.copySource { position: absolute; left: -10000px; width: 1px; height: 1px; }
.chart { background: white; border: 1px solid #ccd3da; border-radius: 6px; margin-bottom: 12px; box-shadow: 0 1px 2px #00000012; }
.chartHeader { display: grid; grid-template-columns: 1fr auto; gap: 8px; align-items: start; padding: 9px 10px 5px; }
.chartTitle { font-family: Consolas, monospace; font-size: 12px; overflow-wrap: anywhere; }
.chartStats { color: #58636e; font-size: 11px; margin-top: 3px; }
.remove { width: auto; margin: 0; padding: 4px 9px; background: #a12622; border-color: #a12622; }
.canvasWrap { position: relative; width: 100%; height: 240px; }
canvas { display: block; width: 100%; height: 240px; }
.tooltip { position: fixed; display: none; pointer-events: none; z-index: 50; padding: 5px 7px; color: white; background: #111d; border-radius: 4px; font: 11px Consolas, monospace; white-space: pre; }
.empty { padding: 60px 20px; text-align: center; color: #66727e; }
.loading { opacity: .55; }
@media (max-width: 900px) {
  .layout { grid-template-columns: 1fr; }
  aside { position: static; height: auto; border-right: 0; border-bottom: 1px solid #ccd3da; }
}
</style>
</head>
<body>
<header>
  <h1>Performance Counter Dashboard</h1>
  <p>On-demand BLG charts. Source resolution is one sample per second; millisecond timestamps do not provide millisecond measurements.</p>
</header>
<div class="layout">
<aside>
  <label for="category">Category</label>
  <select id="category"></select>

  <label for="search">Filter counters</label>
  <input id="search" type="search" placeholder="Example: 11 F: read bytes">

  <label for="counterList">Counters</label>
  <select id="counterList" multiple></select>

  <div class="buttonRow">
    <button id="add">Add selected</button>
    <button id="clearCategory" class="danger">Remove category</button>
  </div>

  <label>Capture time range</label>
  <div class="timeGrid">
    <div class="timeField">
      <span>Start</span>
      <input id="startTime" type="datetime-local" step="0.001">
    </div>
    <div class="timeField">
      <span>End</span>
      <input id="endTime" type="datetime-local" step="0.001">
    </div>
  </div>
  <div class="rangeSlider" aria-label="Capture time range selector">
    <div class="rangeBase"></div>
    <div class="rangeSelection" id="rangeSelection"></div>
    <input id="startRange" type="range" min="0" max="10000" value="0">
    <input id="endRange" type="range" min="0" max="10000" value="10000">
  </div>
  <div class="rangeLabels">
    <span id="captureStartLabel">Capture start</span>
    <span id="captureEndLabel">Capture end</span>
  </div>

  <div class="buttonRow">
    <button id="refresh">Reload charts</button>
    <button id="resetZoom" class="secondary">Reset zoom</button>
  </div>

  <button id="clearAll" class="danger">Remove all charts</button>
</aside>
<main>
  <div class="status" id="status">Loading counter metadata...</div>
  <section class="overview">
    <div class="panelHeader">
      <strong>Overview navigator</strong>
      <span class="panelHint">Drag across the overview to zoom all graphs. Double-click to reset.</span>
    </div>
    <div class="overviewWrap"><canvas id="overviewCanvas"></canvas></div>
  </section>
  <section class="analysis">
    <div class="panelHeader">
      <strong>Automatic analysis</strong>
      <span class="panelHint">Thresholds and spikes are calculated from loaded one-second samples.</span>
    </div>
    <div id="summaryCards" class="summaryCards"></div>
    <ol id="findingsList" class="findingsList">
      <li class="finding-information">Load counters to generate findings.</li>
    </ol>
  </section>
  <section class="readings">
    <div class="readingsHeader">
      <strong>Cursor readings</strong>
      <button id="copyReadings" class="copyReadings">Copy readings</button>
    </div>
    <textarea id="readingText" readonly>Move the cursor over a graph to capture readings.</textarea>
  </section>
  <section class="calculator">
    <div class="readingsHeader">
      <strong>Counter calculator</strong>
      <button id="copyCalculator" class="copyReadings">Copy calculations</button>
    </div>
    <div id="calculatorResults" class="calculatorResults">
      <div class="calculationCard">Load related counters and select a timestamp to calculate derived values.</div>
    </div>
    <textarea id="calculatorText" class="copySource" readonly aria-hidden="true"></textarea>
  </section>
  <div id="charts"><div class="empty">Select counters to add time-aligned graphs.</div></div>
</main>
</div>
<div id="tooltip" class="tooltip"></div>
<script>
"use strict";

const state = {
  counters: [],
  filtered: [],
  charts: new Map(),
  cursorMs: null,
  captureStart: null,
  captureEnd: null,
  selectedStart: null,
  selectedEnd: null,
  fullStart: null,
  fullEnd: null,
  viewStart: null,
  viewEnd: null,
  overviewDragStart: null,
  overviewDragCurrent: null,
  redrawPending: false
};

const colors = ["#1769aa", "#d1495b", "#2a9d8f", "#7b2cbf", "#e76f51", "#3a86ff"];
const category = document.getElementById("category");
const search = document.getElementById("search");
const counterList = document.getElementById("counterList");
const startTime = document.getElementById("startTime");
const endTime = document.getElementById("endTime");
const startRange = document.getElementById("startRange");
const endRange = document.getElementById("endRange");
const rangeSelection = document.getElementById("rangeSelection");
const charts = document.getElementById("charts");
const overviewCanvas = document.getElementById("overviewCanvas");
const summaryCards = document.getElementById("summaryCards");
const findingsList = document.getElementById("findingsList");
const status = document.getElementById("status");
const tooltip = document.getElementById("tooltip");
const readingText = document.getElementById("readingText");
const calculatorText = document.getElementById("calculatorText");
const calculatorResults = document.getElementById("calculatorResults");

function formatValue(value) {
  if (!Number.isFinite(value)) return "n/a";
  const a = Math.abs(value);
  if (a >= 1e12) return (value / 1e12).toFixed(2) + "T";
  if (a >= 1e9) return (value / 1e9).toFixed(2) + "G";
  if (a >= 1e6) return (value / 1e6).toFixed(2) + "M";
  if (a >= 1e3) return (value / 1e3).toFixed(2) + "K";
  if (a >= 10) return value.toFixed(2);
  return value.toFixed(4);
}

function formatMeasurement(value, unit) {
  if (!Number.isFinite(value)) return "n/a";

  if (unit.startsWith("bytes")) {
    const suffix = unit.slice(5);
    const absolute = Math.abs(value);
    if (absolute >= 1024 ** 4) return (value / 1024 ** 4).toFixed(2) + " TiB" + suffix;
    if (absolute >= 1024 ** 3) return (value / 1024 ** 3).toFixed(2) + " GiB" + suffix;
    if (absolute >= 1024 ** 2) return (value / 1024 ** 2).toFixed(2) + " MiB" + suffix;
    if (absolute >= 1024) return (value / 1024).toFixed(2) + " KiB" + suffix;
    return value.toFixed(2) + " B" + suffix;
  }

  if (unit.startsWith("seconds")) {
    const suffix = unit.slice(7);
    const absolute = Math.abs(value);
    if (absolute > 0 && absolute < 0.001) return (value * 1000000).toFixed(2) + " us" + suffix;
    if (absolute < 1) return (value * 1000).toFixed(2) + " ms" + suffix;
    return value.toFixed(3) + " s" + suffix;
  }

  if (unit === "bits/s") {
    const absolute = Math.abs(value);
    if (absolute >= 1e9) return (value / 1e9).toFixed(2) + " Gbit/s";
    if (absolute >= 1e6) return (value / 1e6).toFixed(2) + " Mbit/s";
    if (absolute >= 1e3) return (value / 1e3).toFixed(2) + " Kbit/s";
    return value.toFixed(2) + " bit/s";
  }

  if (unit === "%") return value.toFixed(4) + "%";
  if (unit === "MiB" || unit === "KiB") return formatValue(value) + " " + unit;
  if (unit === "value") return formatValue(value);
  return formatValue(value) + " " + unit;
}

function formatTime(ms) {
  return new Date(ms).toLocaleString(undefined, {
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    fractionalSecondDigits: 3
  });
}

function getThreshold(counter) {
  const name = counter.Counter.toLowerCase();
  const set = counter.CounterSet.toLowerCase();

  if (name === "avg. disk sec/read" || name === "avg. disk sec/write" ||
      name === "avg. disk sec/transfer") {
    return { direction: "high", warning: 0.020, critical: 0.050 };
  }
  if (name === "% processor time" && set.startsWith("processor")) {
    return { direction: "high", warning: 80, critical: 90 };
  }
  if (name === "% committed bytes in use") {
    return { direction: "high", warning: 85, critical: 95 };
  }
  if (name === "available mbytes") {
    return { direction: "low", warning: 1024, critical: 512 };
  }
  if (name === "% free space") {
    return { direction: "low", warning: 15, critical: 5 };
  }
  if (name.includes("disk queue length")) {
    return { direction: "high", warning: 2, critical: 5 };
  }
  if (name === "output queue length") {
    return { direction: "high", warning: 2, critical: 10 };
  }
  if ((name.includes("errors") || name.includes("discarded") ||
       name.includes("failures") || name.includes("shortages") ||
       name.includes("rejected")) && counter.Unit === "count") {
    return { direction: "high", warning: 0, critical: null };
  }
  return null;
}

function percentile(values, percentileValue) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil(percentileValue * sorted.length) - 1)
  );
  return sorted[index];
}

function getSampleIntervalSeconds(points) {
  if (points.length < 2) return 0;
  const differences = [];
  const limit = Math.min(points.length - 1, 1000);
  for (let index = 0; index < limit; index++) {
    const difference = (points[index + 1][0] - points[index][0]) / 1000;
    if (difference > 0 && difference < 3600) differences.push(difference);
  }
  return percentile(differences, 0.5);
}

function integrateRate(points) {
  const interval = getSampleIntervalSeconds(points);
  if (!interval) return 0;
  return points.reduce((total, point) => total + point[1] * interval, 0);
}

function calculateRangeSummary(points) {
  if (!points.length) {
    return { integrated: 0, activePercent: 0, maximum: 0, average: 0, burstRatio: 0 };
  }

  let sum = 0;
  let maximum = -Infinity;
  let nonzero = 0;
  for (const point of points) {
    const value = point[1];
    sum += value;
    if (value > maximum) maximum = value;
    if (value > 0) nonzero++;
  }
  const average = sum / points.length;
  return {
    integrated: integrateRate(points),
    activePercent: nonzero / points.length * 100,
    maximum,
    average,
    burstRatio: average > 0 ? maximum / average : 0
  };
}

function addFinding(severity, text, timestamp = null) {
  const item = document.createElement("li");
  item.className = `finding-${severity.toLowerCase()}`;
  const description = document.createElement("span");
  description.textContent = text;
  item.appendChild(description);

  if (timestamp !== null) {
    const zoom = document.createElement("button");
    zoom.className = "zoomFinding";
    zoom.textContent = "Zoom";
    zoom.dataset.timestamp = timestamp;
    item.appendChild(zoom);
  }
  findingsList.appendChild(item);
}

function updateAnalysisPanels() {
  summaryCards.innerHTML = "";
  findingsList.innerHTML = "";

  const loadedCharts = [...state.charts.values()].filter(chart => chart.points.length);
  if (!loadedCharts.length) {
    addFinding("Information", "Load counters to generate findings.");
    return;
  }

  let findingCount = 0;
  for (const chart of loadedCharts) {
    const values = chart.points.map(point => point[1]);
    const peak = chart.points.reduce(
      (highest, point) => point[1] > highest[1] ? point : highest,
      chart.points[0]
    );
    const trough = chart.points.reduce(
      (lowest, point) => point[1] < lowest[1] ? point : lowest,
      chart.points[0]
    );
    const p95 = percentile(values, 0.95);
    const threshold = getThreshold(chart.counter);

    if (chart.counter.Unit === "bytes/s") {
      const total = integrateRate(chart.points);
      chart.total = total;
      const card = document.createElement("div");
      card.className = "summaryCard";
      const title = document.createElement("strong");
      title.textContent = chart.counter.Label;
      const value = document.createElement("span");
      value.textContent = `Selected-range total: ${formatMeasurement(total, "bytes")}`;
      card.append(title, value);
      summaryCards.appendChild(card);

      if (total > 0) {
        const interval = getSampleIntervalSeconds(chart.points);
        const peakBytes = peak[1] * interval;
        const share = peakBytes / total * 100;
        addFinding(
          share >= 50 ? "Warning" : "Information",
          `${chart.counter.Label}: ${share.toFixed(1)}% of the total occurred near ` +
          `${formatTime(peak[0])}; selected-range total ${formatMeasurement(total, "bytes")}.`,
          peak[0]
        );
        findingCount++;
      }
    }

    if (threshold) {
      const observed = threshold.direction === "low" ? chart.minimum : chart.maximum;
      const criticalViolation = threshold.critical !== null && (
        threshold.direction === "low"
          ? observed <= threshold.critical
          : observed >= threshold.critical
      );
      const warningViolation = threshold.direction === "low"
        ? observed <= threshold.warning
        : observed > threshold.warning;

      if (criticalViolation || warningViolation) {
        const severity = criticalViolation ? "Critical" : "Warning";
        addFinding(
          severity,
          `${chart.counter.Label}: ${severity.toLowerCase()} threshold reached; ` +
          `observed ${formatMeasurement(observed, chart.counter.Unit)}.`,
          threshold.direction === "low" ? trough[0] : peak[0]
        );
        findingCount++;
      }
    }

    const significantSpike = peak[1] > 0 && (
      (p95 === 0 && peak[1] > chart.average) ||
      (p95 > 0 && peak[1] >= p95 * 2 && peak[1] >= chart.average * 3)
    );
    if (significantSpike) {
      addFinding(
        "Information",
        `${chart.counter.Label}: isolated peak of ` +
        `${formatMeasurement(peak[1], chart.counter.Unit)} at ${formatTime(peak[0])}; ` +
        `sample P95 is ${formatMeasurement(p95, chart.counter.Unit)}.`,
        peak[0]
      );
      findingCount++;
    }
  }

  if (!summaryCards.children.length) {
    const card = document.createElement("div");
    card.className = "summaryCard";
    card.textContent = "Add a bytes/sec counter to calculate cumulative I/O.";
    summaryCards.appendChild(card);
  }
  if (findingCount === 0) {
    addFinding("Information", "No supported threshold violations or significant spikes were detected.");
  }
}

function setStatus(text, error = false) {
  status.textContent = text;
  status.style.background = error ? "#ffe2e0" : "#fff7d6";
  status.style.borderColor = error ? "#d98781" : "#e6ce72";
}

function findLoadedChart(counterSet, instance, counterName) {
  const setName = counterSet.toLowerCase();
  const instanceName = instance.toLowerCase();
  const name = counterName.toLowerCase();
  return [...state.charts.values()].find(chart =>
    chart.counter.CounterSet.toLowerCase() === setName &&
    chart.counter.Instance.toLowerCase() === instanceName &&
    chart.counter.Counter.toLowerCase() === name &&
    chart.points.length
  );
}

function getChartValue(chart, timestamp) {
  if (!chart) return null;
  const point = nearestPoint(chart.points, timestamp);
  return point ? point[1] : null;
}

function formatRawNumber(value) {
  return value.toLocaleString(undefined, { maximumFractionDigits: 6 });
}

function addCalculatorCard(title, detailLines, meaning) {
  const card = document.createElement("div");
  card.className = "calculationCard";
  card.title = meaning;

  const heading = document.createElement("div");
  heading.className = "calculationTitle";
  heading.textContent = title;

  const detail = document.createElement("pre");
  detail.className = "calculationDetail";
  detail.textContent = detailLines.join("\n");

  const help = document.createElement("span");
  help.className = "helpBadge";
  help.textContent = "?";
  help.dataset.help = meaning;

  card.append(heading, detail, help);
  calculatorResults.appendChild(card);
}

function updateCalculatorPanel() {
  calculatorResults.innerHTML = "";
  if (state.cursorMs === null || state.charts.size === 0) {
    const message =
      "Load related counters and select a timestamp to calculate derived values.";
    addCalculatorCard("Calculator ready", [message],
      "The calculator combines related counters from the same disk instance.");
    calculatorText.value = message;
    return;
  }

  const definitions = [
    {
      title: "Read throughput and bytes read in one second",
      left: "Avg. Disk Bytes/Read",
      right: "Disk Reads/sec",
      direct: "Disk Read Bytes/sec",
      resultUnit: "bytes/s",
      meaning:
        "Average read size multiplied by read operations per second gives read throughput. " +
        "For a one-second sample, this is also the estimated amount read during that second."
    },
    {
      title: "Write throughput and bytes written in one second",
      left: "Avg. Disk Bytes/Write",
      right: "Disk Writes/sec",
      direct: "Disk Write Bytes/sec",
      resultUnit: "bytes/s",
      meaning:
        "Average write size multiplied by write operations per second gives write throughput " +
        "and the estimated amount written during one second."
    },
    {
      title: "Read queue length check",
      left: "Avg. Disk sec/Read",
      right: "Disk Reads/sec",
      direct: "Avg. Disk Read Queue Length",
      resultUnit: "requests",
      meaning:
        "Read latency multiplied by read IOPS estimates how many read requests were outstanding. " +
        "Near zero means reads were generally not waiting."
    },
    {
      title: "Write queue length check",
      left: "Avg. Disk sec/Write",
      right: "Disk Writes/sec",
      direct: "Avg. Disk Write Queue Length",
      resultUnit: "requests",
      meaning:
        "Write latency multiplied by write IOPS estimates the average number of outstanding writes."
    },
    {
      title: "Total queue length check",
      left: "Avg. Disk sec/Transfer",
      right: "Disk Transfers/sec",
      direct: "Avg. Disk Queue Length",
      resultUnit: "requests",
      meaning:
        "Overall latency multiplied by total IOPS estimates total outstanding disk requests. " +
        "This is Little's Law applied to storage."
    }
  ];

  const groups = new Map();
  for (const chart of state.charts.values()) {
    if (!["PhysicalDisk", "LogicalDisk"].includes(chart.counter.CounterSet)) continue;
    const key = `${chart.counter.CounterSet}|${chart.counter.Instance}`;
    groups.set(key, {
      counterSet: chart.counter.CounterSet,
      instance: chart.counter.Instance
    });
  }

  const lines = [`Timestamp: ${formatTime(state.cursorMs)}`];
  let calculationCount = 0;

  const appendResult = (title, details, meaning) => {
    calculationCount++;
    addCalculatorCard(title, details, meaning);
    lines.push("");
    lines.push(title);
    lines.push(...details);
    lines.push(`Meaning: ${meaning}`);
  };

  for (const group of groups.values()) {
    const chartFor = counterName =>
      findLoadedChart(group.counterSet, group.instance, counterName);
    const valueFor = counterName =>
      getChartValue(chartFor(counterName), state.cursorMs);
    const groupName = `${group.counterSet}(${group.instance})`;

    const comparisonText = (directName, calculated, resultUnit) => {
      const directChart = chartFor(directName);
      const directValue = getChartValue(directChart, state.cursorMs);
      if (directValue === null) return null;
      const difference = directValue === 0
        ? Math.abs(calculated - directValue)
        : Math.abs(calculated - directValue) / Math.abs(directValue) * 100;
      return `Direct ${directName}: ${formatMeasurement(directValue, directChart.counter.Unit)}; ` +
        `difference ${difference.toFixed(4)}${directValue === 0 ? ` ${resultUnit}` : "%"}`;
    };

    for (const definition of definitions) {
      const leftChart = chartFor(definition.left);
      const rightChart = chartFor(definition.right);
      if (!leftChart || !rightChart) continue;

      const leftValue = getChartValue(leftChart, state.cursorMs);
      const rightValue = getChartValue(rightChart, state.cursorMs);
      if (leftValue === null || rightValue === null) continue;

      const result = leftValue * rightValue;
      const details = [
        `${formatRawNumber(leftValue)} ${leftChart.counter.Unit} x ` +
        `${formatRawNumber(rightValue)} ${rightChart.counter.Unit}`,
        `= ${formatRawNumber(result)} ${definition.resultUnit} ` +
        `(${formatMeasurement(result, definition.resultUnit)})`
      ];

      if (definition.resultUnit === "bytes/s") {
        details.push(
          `Estimated amount in one second = ${formatMeasurement(result, "bytes")}`
        );
      }

      const comparison = comparisonText(
        definition.direct, result, definition.resultUnit);
      if (comparison) details.push(comparison);
      appendResult(
        `${groupName} - ${definition.title}`,
        details,
        definition.meaning
      );
    }

    const reads = valueFor("Disk Reads/sec");
    const writes = valueFor("Disk Writes/sec");
    const transfers = valueFor("Disk Transfers/sec");
    const readBytes = valueFor("Disk Read Bytes/sec");
    const writeBytes = valueFor("Disk Write Bytes/sec");
    const diskBytes = valueFor("Disk Bytes/sec");
    const readLatency = valueFor("Avg. Disk sec/Read");
    const writeLatency = valueFor("Avg. Disk sec/Write");

    if (reads !== null && writes !== null) {
      const totalIops = reads + writes;
      const details = [
        `${formatRawNumber(reads)} read IOPS + ${formatRawNumber(writes)} write IOPS`,
        `= ${formatMeasurement(totalIops, "operations/s")}`
      ];
      const comparison = comparisonText("Disk Transfers/sec", totalIops, "operations/s");
      if (comparison) details.push(comparison);
      appendResult(
        `${groupName} - Total IOPS`,
        details,
        "The total number of read and write operations requested from the disk each second."
      );

      if (totalIops > 0) {
        const readPercent = reads / totalIops * 100;
        const writePercent = writes / totalIops * 100;
        const ratio = writes === 0 ? "read-only" : (reads / writes).toFixed(3) + ":1";
        appendResult(
          `${groupName} - Read/write IOPS mix`,
          [
            `Reads: ${readPercent.toFixed(2)}%`,
            `Writes: ${writePercent.toFixed(2)}%`,
            `Read-to-write ratio: ${ratio}`
          ],
          "Shows whether the workload is mainly reading, mainly writing, or balanced by operation count."
        );
      }
    }

    if (readBytes !== null && writeBytes !== null) {
      const totalThroughput = readBytes + writeBytes;
      const details = [
        `${formatMeasurement(readBytes, "bytes/s")} read + ` +
        `${formatMeasurement(writeBytes, "bytes/s")} write`,
        `= ${formatMeasurement(totalThroughput, "bytes/s")}`
      ];
      const comparison = comparisonText("Disk Bytes/sec", totalThroughput, "bytes/s");
      if (comparison) details.push(comparison);
      appendResult(
        `${groupName} - Total throughput`,
        details,
        "The combined amount of data read from and written to the disk every second."
      );

      if (totalThroughput > 0) {
        const readPercent = readBytes / totalThroughput * 100;
        const writePercent = writeBytes / totalThroughput * 100;
        appendResult(
          `${groupName} - Read/write throughput mix`,
          [
            `Read data: ${readPercent.toFixed(2)}%`,
            `Written data: ${writePercent.toFixed(2)}%`
          ],
          "Shows which direction accounts for most of the transferred bytes, regardless of operation count."
        );
      }

      const totalIops = reads !== null && writes !== null ? reads + writes : transfers;
      if (totalIops !== null && totalIops > 0) {
        const averageTransferSize = totalThroughput / totalIops;
        const details = [
          `${formatMeasurement(totalThroughput, "bytes/s")} / ` +
          `${formatMeasurement(totalIops, "operations/s")}`,
          `= ${formatMeasurement(averageTransferSize, "bytes/transfer")}`
        ];
        const comparison = comparisonText(
          "Avg. Disk Bytes/Transfer", averageTransferSize, "bytes/transfer");
        if (comparison) details.push(comparison);
        appendResult(
          `${groupName} - Average transfer size`,
          details,
          "The typical amount of data in each combined read or write operation. Large values often indicate larger sequential I/O."
        );
      }
    }

    if (readLatency !== null && writeLatency !== null &&
        reads !== null && writes !== null && reads + writes > 0) {
      const weightedLatency =
        (readLatency * reads + writeLatency * writes) / (reads + writes);
      const details = [
        `Weighted by ${formatRawNumber(reads)} read IOPS and ` +
        `${formatRawNumber(writes)} write IOPS`,
        `= ${formatMeasurement(weightedLatency, "seconds/transfer")}`
      ];
      const comparison = comparisonText(
        "Avg. Disk sec/Transfer", weightedLatency, "seconds/transfer");
      if (comparison) details.push(comparison);
      appendResult(
        `${groupName} - Weighted overall latency`,
        details,
        "Combines read and write response times according to how many of each operation occurred."
      );
    }

    const addBusyTime = (queueName, percentName, title, meaning) => {
      const queue = valueFor(queueName);
      if (queue === null) return;
      const calculated = queue * 100;
      const details = [
        `${formatMeasurement(queue, "requests")} x 100`,
        `= ${formatMeasurement(calculated, "%")}`
      ];
      const comparison = comparisonText(percentName, calculated, "%");
      if (comparison) details.push(comparison);
      appendResult(`${groupName} - ${title}`, details, meaning);
    };
    addBusyTime(
      "Avg. Disk Read Queue Length", "% Disk Read Time", "Read busy-time check",
      "Estimates the percentage of the interval occupied by outstanding reads. It may exceed 100% when requests overlap.");
    addBusyTime(
      "Avg. Disk Write Queue Length", "% Disk Write Time", "Write busy-time check",
      "Estimates the percentage of the interval occupied by outstanding writes. Overlapping requests can produce values above 100%.");
    addBusyTime(
      "Avg. Disk Queue Length", "% Disk Time", "Total busy-time check",
      "Converts average outstanding I/O into PerfMon's disk-time percentage. It is not a strict hardware utilization limit.");

    const splitIo = valueFor("Split IO/Sec");
    const totalTransfers = transfers !== null ? transfers :
      (reads !== null && writes !== null ? reads + writes : null);
    if (splitIo !== null && totalTransfers !== null && totalTransfers > 0) {
      const splitPercent = splitIo / totalTransfers * 100;
      appendResult(
        `${groupName} - Split-I/O percentage`,
        [
          `${formatMeasurement(splitIo, "operations/s")} / ` +
          `${formatMeasurement(totalTransfers, "operations/s")} x 100`,
          `= ${splitPercent.toFixed(4)}%`
        ],
        "The share of I/O requests that Windows had to split into multiple operations. A sustained high percentage can indicate fragmentation or alignment issues."
      );
    }

    const transferChart = chartFor("Disk Transfers/sec");
    if (transferChart) {
      const selectedOperations = transferChart.rangeSummary.integrated;
      appendResult(
        `${groupName} - Operations in loaded range`,
        [`Estimated operations: ${formatRawNumber(selectedOperations)}`],
        "Adds the per-second IOPS samples across the loaded time range to estimate how many total I/O operations occurred."
      );
    }

    const throughputChart = chartFor("Disk Bytes/sec");
    if (throughputChart) {
      const rangeSummary = throughputChart.rangeSummary;
      appendResult(
        `${groupName} - Activity and burstiness`,
        [
          `Active samples: ${rangeSummary.activePercent.toFixed(2)}%`,
          `Peak-to-average throughput ratio: ${rangeSummary.burstRatio.toFixed(2)}x`
        ],
        "Active samples show how often the disk transferred data. The burst ratio shows whether activity was steady or concentrated in short spikes."
      );
    }
  }

  if (calculationCount === 0) {
    const message =
      "For read throughput, load Avg. Disk Bytes/Read and Disk Reads/sec " +
      "for the same disk instance.";
    addCalculatorCard(
      "More counters required",
      [message],
      "Derived metrics are shown only when all counters needed by a formula are loaded."
    );
    lines.push("", message);
  }
  calculatorText.value = lines.join("\n");
}

function updateReadingPanel() {
  if (state.cursorMs === null || state.charts.size === 0) {
    readingText.value = "Move the cursor over a graph to capture readings.";
    updateCalculatorPanel();
    return;
  }

  const lines = [`Timestamp: ${formatTime(state.cursorMs)}`];
  for (const chart of state.charts.values()) {
    const point = nearestPoint(chart.points, state.cursorMs);
    if (point) {
      lines.push(
        `${chart.counter.Path} [${chart.counter.Unit}] = ${point[1]} ` +
        `(${formatMeasurement(point[1], chart.counter.Unit)})`
      );
    }
  }
  readingText.value = lines.join("\n");
  updateCalculatorPanel();
}

function updateCounterList() {
  const selectedCategory = category.value;
  const term = search.value.trim().toLowerCase();
  state.filtered = state.counters.filter(c =>
    c.Category === selectedCategory &&
    (!term || c.Label.toLowerCase().includes(term) || c.Path.toLowerCase().includes(term))
  );
  counterList.innerHTML = "";
  for (const counter of state.filtered) {
    const option = document.createElement("option");
    option.value = counter.Path;
    option.textContent = `${counter.Label} [${counter.Unit}]`;
    option.title = counter.Path;
    counterList.appendChild(option);
  }
}

function toIsoInput(value) {
  if (value === null || value === undefined) return "";
  const date = new Date(value);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 23);
}

function inputToMs(input) {
  const parsed = new Date(input.value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function sliderValueToMs(value) {
  const ratio = Number(value) / 10000;
  return state.captureStart + ratio * (state.captureEnd - state.captureStart);
}

function msToSliderValue(value) {
  if (state.captureEnd === state.captureStart) return 0;
  return Math.round((value - state.captureStart) / (state.captureEnd - state.captureStart) * 10000);
}

function updateRangeSelection() {
  const startPercent = Number(startRange.value) / 100;
  const endPercent = Number(endRange.value) / 100;
  rangeSelection.style.left = startPercent + "%";
  rangeSelection.style.right = (100 - endPercent) + "%";
}

function applySelectedRange(start, end, source) {
  if (state.captureStart === null || state.captureEnd === null) return;

  start = clamp(start, state.captureStart, state.captureEnd);
  end = clamp(end, state.captureStart, state.captureEnd);
  const minimumGap = Math.min(1000, state.captureEnd - state.captureStart);

  if (end < start + minimumGap) {
    if (source === "start") {
      start = Math.max(state.captureStart, end - minimumGap);
    } else {
      end = Math.min(state.captureEnd, start + minimumGap);
    }
  }

  state.selectedStart = start;
  state.selectedEnd = end;
  startTime.value = toIsoInput(start);
  endTime.value = toIsoInput(end);
  startRange.value = msToSliderValue(start);
  endRange.value = msToSliderValue(end);
  updateRangeSelection();
}

function initializeTimeRange(start, end) {
  state.captureStart = start;
  state.captureEnd = end;
  const minimum = toIsoInput(start);
  const maximum = toIsoInput(end);
  startTime.min = minimum;
  startTime.max = maximum;
  endTime.min = minimum;
  endTime.max = maximum;
  document.getElementById("captureStartLabel").textContent = formatTime(start);
  document.getElementById("captureEndLabel").textContent = formatTime(end);
  applySelectedRange(start, end, "end");
}

function selectedRangeQuery() {
  const params = new URLSearchParams();
  params.set("start", new Date(state.selectedStart).toISOString());
  params.set("end", new Date(state.selectedEnd).toISOString());
  return params;
}

async function loadCounter(counter, force = false) {
  if (state.charts.has(counter.Path) && !force) return;

  let chart = state.charts.get(counter.Path);
  if (!chart) {
    chart = createChart(counter);
    state.charts.set(counter.Path, chart);
  }
  chart.element.classList.add("loading");
  chart.stats.textContent = "Loading samples...";
  setStatus(`Loading ${counter.Label}`);

  const params = selectedRangeQuery();
  params.set("path", counter.Path);
  try {
    const response = await fetch("/api/data?" + params.toString());
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || response.statusText);

    chart.points = payload.Points;
    chart.minimum = payload.Minimum;
    chart.maximum = payload.Maximum;
    chart.average = payload.Average;
    chart.rangeSummary = calculateRangeSummary(chart.points);
    chart.total = counter.Unit === "bytes/s" ? chart.rangeSummary.integrated : null;
    chart.stats.textContent =
      `Samples ${payload.Samples.toLocaleString()} | ` +
      `Min ${formatMeasurement(payload.Minimum, counter.Unit)} | ` +
      `Max ${formatMeasurement(payload.Maximum, counter.Unit)} | ` +
      `Avg ${formatMeasurement(payload.Average, counter.Unit)}` +
      (chart.total !== null
        ? ` | Selected total ${formatMeasurement(chart.total, "bytes")}`
        : "");

    const first = chart.points[0][0];
    const last = chart.points[chart.points.length - 1][0];
    if (state.fullStart === null || first < state.fullStart) state.fullStart = first;
    if (state.fullEnd === null || last > state.fullEnd) state.fullEnd = last;
    if (state.viewStart === null || state.viewEnd === null) {
      state.viewStart = state.fullStart;
      state.viewEnd = state.fullEnd;
    }
    chart.element.classList.remove("loading");
    updateAnalysisPanels();
    updateReadingPanel();
    redrawAll();
    setStatus(`${state.charts.size} chart(s) loaded. Move across a graph to correlate timestamps; use the mouse wheel to zoom.`);
  } catch (error) {
    chart.element.classList.remove("loading");
    chart.stats.textContent = "Load failed: " + error.message;
    setStatus(error.message, true);
  }
}

function createChart(counter) {
  if (charts.querySelector(".empty")) charts.innerHTML = "";

  const element = document.createElement("section");
  element.className = "chart";
  element.dataset.category = counter.Category;

  const header = document.createElement("div");
  header.className = "chartHeader";
  const titleArea = document.createElement("div");
  const title = document.createElement("div");
  title.className = "chartTitle";
  title.textContent = `${counter.Path} [${counter.Unit}]`;
  const stats = document.createElement("div");
  stats.className = "chartStats";
  titleArea.append(title, stats);
  const remove = document.createElement("button");
  remove.className = "remove";
  remove.textContent = "Remove";
  header.append(titleArea, remove);

  const wrap = document.createElement("div");
  wrap.className = "canvasWrap";
  const canvas = document.createElement("canvas");
  wrap.appendChild(canvas);
  element.append(header, wrap);
  charts.appendChild(element);

  const chart = {
    counter, element, canvas, stats, points: [],
    minimum: 0, maximum: 0, average: 0,
    color: colors[state.charts.size % colors.length]
  };

  remove.addEventListener("click", () => {
    state.charts.delete(counter.Path);
    element.remove();
    if (state.charts.size === 0) {
      charts.innerHTML = '<div class="empty">Select counters to add time-aligned graphs.</div>';
      state.fullStart = state.fullEnd = state.viewStart = state.viewEnd = null;
    } else {
      recomputeBounds();
      redrawAll();
    }
    updateReadingPanel();
    updateAnalysisPanels();
    setStatus(`${state.charts.size} chart(s) loaded.`);
  });

  canvas.addEventListener("mousemove", event => {
    const rect = canvas.getBoundingClientRect();
    const plotLeft = 76;
    const plotRight = rect.width - 14;
    const x = Math.max(plotLeft, Math.min(plotRight, event.clientX - rect.left));
    state.cursorMs = state.viewStart + (x - plotLeft) / (plotRight - plotLeft) * (state.viewEnd - state.viewStart);
    updateReadingPanel();
    redrawAll();

    const point = nearestPoint(chart.points, state.cursorMs);
    if (point) {
      tooltip.style.display = "block";
      tooltip.style.left = Math.min(window.innerWidth - 280, event.clientX + 12) + "px";
      tooltip.style.top = Math.max(8, event.clientY - 42) + "px";
      tooltip.textContent =
        formatTime(point[0]) + "\n" +
        formatMeasurement(point[1], chart.counter.Unit);
    }
  });
  canvas.addEventListener("mouseleave", () => {
    tooltip.style.display = "none";
    redrawAll();
  });
  canvas.addEventListener("wheel", event => {
    event.preventDefault();
    if (state.viewStart === null || state.viewEnd === null) return;
    const rect = canvas.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left - 76) / (rect.width - 90)));
    const center = state.viewStart + ratio * (state.viewEnd - state.viewStart);
    const factor = event.deltaY < 0 ? 0.75 : 1.33;
    let start = center - (center - state.viewStart) * factor;
    let end = center + (state.viewEnd - center) * factor;
    const minimumSpan = 5000;
    if (end - start < minimumSpan) {
      start = center - minimumSpan / 2;
      end = center + minimumSpan / 2;
    }
    state.viewStart = Math.max(state.fullStart, start);
    state.viewEnd = Math.min(state.fullEnd, end);
    redrawAll();
  }, { passive: false });
  canvas.addEventListener("dblclick", resetZoom);

  return chart;
}

function nearestPoint(points, timestamp) {
  if (!points.length) return null;
  let lo = 0, hi = points.length - 1;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (points[mid][0] < timestamp) lo = mid + 1;
    else hi = mid;
  }
  if (lo > 0 && Math.abs(points[lo - 1][0] - timestamp) < Math.abs(points[lo][0] - timestamp)) {
    return points[lo - 1];
  }
  return points[lo];
}

function recomputeBounds() {
  const loaded = [...state.charts.values()].filter(c => c.points.length);
  if (!loaded.length) {
    state.fullStart = state.fullEnd = state.viewStart = state.viewEnd = null;
    return;
  }
  state.fullStart = Math.min(...loaded.map(c => c.points[0][0]));
  state.fullEnd = Math.max(...loaded.map(c => c.points[c.points.length - 1][0]));
  state.viewStart = state.fullStart;
  state.viewEnd = state.fullEnd;
}

function resetZoom() {
  state.viewStart = state.fullStart;
  state.viewEnd = state.fullEnd;
  redrawAll();
}

function overviewXToTime(x, width) {
  const left = 8;
  const right = width - 8;
  const ratio = clamp((x - left) / Math.max(1, right - left), 0, 1);
  return state.fullStart + ratio * (state.fullEnd - state.fullStart);
}

function drawOverview() {
  const rect = overviewCanvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  overviewCanvas.width = Math.max(1, Math.round(rect.width * dpr));
  overviewCanvas.height = Math.max(1, Math.round(rect.height * dpr));
  const ctx = overviewCanvas.getContext("2d");
  ctx.scale(dpr, dpr);
  const width = rect.width;
  const height = rect.height;
  ctx.clearRect(0, 0, width, height);

  const loaded = [...state.charts.values()].filter(chart => chart.points.length);
  if (!loaded.length || state.fullStart === null || state.fullEnd === null) {
    ctx.fillStyle = "#66727e";
    ctx.font = "12px Segoe UI";
    ctx.fillText("Load counters to create the overview.", 12, height / 2);
    return;
  }

  const left = 8, right = width - 8, top = 8, bottom = height - 20;
  const bucketCount = Math.max(1, Math.floor(right - left));
  const buckets = new Float64Array(bucketCount);

  for (const chart of loaded) {
    let minimum = chart.minimum;
    let maximum = chart.maximum;
    const range = maximum - minimum || 1;
    for (const point of chart.points) {
      const ratio = (point[0] - state.fullStart) / (state.fullEnd - state.fullStart);
      const index = Math.max(0, Math.min(bucketCount - 1, Math.floor(ratio * bucketCount)));
      const normalized = (point[1] - minimum) / range;
      buckets[index] = Math.max(buckets[index], normalized);
    }
  }

  ctx.fillStyle = "#dcebf7";
  ctx.beginPath();
  ctx.moveTo(left, bottom);
  for (let index = 0; index < bucketCount; index++) {
    const x = left + index;
    const y = bottom - buckets[index] * (bottom - top);
    ctx.lineTo(x, y);
  }
  ctx.lineTo(right, bottom);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = "#1769aa";
  ctx.lineWidth = 1;
  ctx.stroke();

  const selectionStart = state.overviewDragStart !== null
    ? Math.min(state.overviewDragStart, state.overviewDragCurrent)
    : state.viewStart;
  const selectionEnd = state.overviewDragStart !== null
    ? Math.max(state.overviewDragStart, state.overviewDragCurrent)
    : state.viewEnd;
  const startX = left + (selectionStart - state.fullStart) /
    (state.fullEnd - state.fullStart) * (right - left);
  const endX = left + (selectionEnd - state.fullStart) /
    (state.fullEnd - state.fullStart) * (right - left);

  ctx.fillStyle = "#1769aa22";
  ctx.fillRect(startX, top, Math.max(1, endX - startX), bottom - top);
  ctx.strokeStyle = "#174a7e";
  ctx.lineWidth = 2;
  ctx.strokeRect(startX, top, Math.max(1, endX - startX), bottom - top);
  ctx.fillStyle = "#53606c";
  ctx.font = "10px Segoe UI";
  ctx.fillText(new Date(state.fullStart).toLocaleTimeString(), left, height - 5);
  const endLabel = new Date(state.fullEnd).toLocaleTimeString();
  ctx.fillText(endLabel, right - ctx.measureText(endLabel).width, height - 5);
}

function drawThresholdBands(ctx, chart, yMin, yMax, left, right, top, bottom) {
  const threshold = getThreshold(chart.counter);
  if (!threshold || yMax === yMin) return;

  const valueToY = value =>
    bottom - (value - yMin) / (yMax - yMin) * (bottom - top);
  const drawBand = (from, to, color) => {
    const boundedFrom = clamp(from, yMin, yMax);
    const boundedTo = clamp(to, yMin, yMax);
    if (boundedFrom === boundedTo) return;
    const y1 = valueToY(boundedFrom);
    const y2 = valueToY(boundedTo);
    ctx.fillStyle = color;
    ctx.fillRect(left, Math.min(y1, y2), right - left, Math.abs(y2 - y1));
  };

  if (threshold.direction === "high") {
    if (threshold.critical !== null) {
      drawBand(threshold.warning, threshold.critical, "#f6c34422");
      drawBand(threshold.critical, yMax, "#d6454126");
    } else {
      drawBand(threshold.warning, yMax, "#f6c34422");
    }
  } else {
    if (threshold.critical !== null) {
      drawBand(yMin, threshold.critical, "#d6454126");
      drawBand(threshold.critical, threshold.warning, "#f6c34422");
    } else {
      drawBand(yMin, threshold.warning, "#f6c34422");
    }
  }

  for (const value of [threshold.warning, threshold.critical]) {
    if (value === null || value < yMin || value > yMax) continue;
    const y = valueToY(value);
    ctx.strokeStyle = value === threshold.critical ? "#b42318" : "#c47f00";
    ctx.setLineDash([4, 3]);
    ctx.beginPath();
    ctx.moveTo(left, y);
    ctx.lineTo(right, y);
    ctx.stroke();
    ctx.setLineDash([]);
  }
}

function drawChart(chart) {
  const canvas = chart.canvas;
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.round(rect.width * dpr));
  canvas.height = Math.max(1, Math.round(rect.height * dpr));
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);

  const width = rect.width;
  const height = rect.height;
  const left = 76, right = width - 14, top = 22, bottom = height - 28;
  ctx.clearRect(0, 0, width, height);
  ctx.font = "10px Segoe UI";
  ctx.fillStyle = "#53606c";
  ctx.strokeStyle = "#d9dfe5";
  ctx.lineWidth = 1;
  ctx.fillText(`[${chart.counter.Unit}]`, 4, 11);

  if (!chart.points.length || state.viewStart === null || state.viewEnd === null) return;
  const visible = chart.points.filter(p => p[0] >= state.viewStart && p[0] <= state.viewEnd);
  if (!visible.length) return;

  let yMin = Math.min(...visible.map(p => p[1]));
  let yMax = Math.max(...visible.map(p => p[1]));
  if (yMin === yMax) {
    const padding = Math.abs(yMin) * 0.05 || 1;
    yMin -= padding;
    yMax += padding;
  } else {
    const padding = (yMax - yMin) * 0.06;
    yMin -= padding;
    yMax += padding;
  }

  drawThresholdBands(ctx, chart, yMin, yMax, left, right, top, bottom);

  for (let i = 0; i <= 4; i++) {
    const y = top + (bottom - top) * i / 4;
    ctx.beginPath();
    ctx.moveTo(left, y);
    ctx.lineTo(right, y);
    ctx.stroke();
    const value = yMax - (yMax - yMin) * i / 4;
    ctx.fillText(formatValue(value), 4, y + 3);
  }

  ctx.beginPath();
  ctx.strokeStyle = chart.color;
  ctx.lineWidth = 1.4;
  let started = false;
  for (const point of visible) {
    const x = left + (point[0] - state.viewStart) / (state.viewEnd - state.viewStart) * (right - left);
    const y = bottom - (point[1] - yMin) / (yMax - yMin) * (bottom - top);
    if (!started) {
      ctx.moveTo(x, y);
      started = true;
    } else {
      ctx.lineTo(x, y);
    }
  }
  ctx.stroke();

  ctx.fillStyle = "#53606c";
  ctx.fillText(new Date(state.viewStart).toLocaleTimeString(), left, height - 8);
  const endText = new Date(state.viewEnd).toLocaleTimeString();
  ctx.fillText(endText, right - ctx.measureText(endText).width, height - 8);

  if (state.cursorMs !== null && state.cursorMs >= state.viewStart && state.cursorMs <= state.viewEnd) {
    const x = left + (state.cursorMs - state.viewStart) / (state.viewEnd - state.viewStart) * (right - left);
    ctx.strokeStyle = "#111";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, top);
    ctx.lineTo(x, bottom);
    ctx.stroke();
  }
}

function redrawAll() {
  if (state.redrawPending) return;
  state.redrawPending = true;
  requestAnimationFrame(() => {
    state.redrawPending = false;
    drawOverview();
    for (const chart of state.charts.values()) drawChart(chart);
  });
}

document.getElementById("add").addEventListener("click", async () => {
  const selected = [...counterList.selectedOptions].map(option => option.value);
  for (const path of selected) {
    const counter = state.counters.find(c => c.Path === path);
    if (counter) await loadCounter(counter);
  }
});

document.getElementById("refresh").addEventListener("click", async () => {
  state.fullStart = state.fullEnd = state.viewStart = state.viewEnd = null;
  for (const chart of [...state.charts.values()]) {
    await loadCounter(chart.counter, true);
  }
});

document.getElementById("clearCategory").addEventListener("click", () => {
  const selectedCategory = category.value;
  for (const [path, chart] of [...state.charts.entries()]) {
    if (chart.counter.Category === selectedCategory) {
      state.charts.delete(path);
      chart.element.remove();
    }
  }
  if (state.charts.size === 0) {
    charts.innerHTML = '<div class="empty">Select counters to add time-aligned graphs.</div>';
  }
  recomputeBounds();
  updateReadingPanel();
  updateAnalysisPanels();
  redrawAll();
  setStatus(`${state.charts.size} chart(s) loaded.`);
});

document.getElementById("clearAll").addEventListener("click", () => {
  state.charts.clear();
  charts.innerHTML = '<div class="empty">Select counters to add time-aligned graphs.</div>';
  state.fullStart = state.fullEnd = state.viewStart = state.viewEnd = null;
  state.cursorMs = null;
  updateReadingPanel();
  updateAnalysisPanels();
  setStatus("All charts removed.");
});

document.getElementById("copyReadings").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(readingText.value);
    setStatus("Cursor readings copied to the clipboard.");
  } catch {
    readingText.focus();
    readingText.select();
    document.execCommand("copy");
    setStatus("Cursor readings copied to the clipboard.");
  }
});

document.getElementById("copyCalculator").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(calculatorText.value);
    setStatus("Counter calculations copied to the clipboard.");
  } catch {
    calculatorText.focus();
    calculatorText.select();
    document.execCommand("copy");
    setStatus("Counter calculations copied to the clipboard.");
  }
});

overviewCanvas.addEventListener("pointerdown", event => {
  if (state.fullStart === null || state.fullEnd === null) return;
  const rect = overviewCanvas.getBoundingClientRect();
  const timestamp = overviewXToTime(event.clientX - rect.left, rect.width);
  state.overviewDragStart = timestamp;
  state.overviewDragCurrent = timestamp;
  overviewCanvas.setPointerCapture(event.pointerId);
  drawOverview();
});
overviewCanvas.addEventListener("pointermove", event => {
  if (state.overviewDragStart === null) return;
  const rect = overviewCanvas.getBoundingClientRect();
  state.overviewDragCurrent = overviewXToTime(event.clientX - rect.left, rect.width);
  drawOverview();
});
overviewCanvas.addEventListener("pointerup", event => {
  if (state.overviewDragStart === null) return;
  const start = Math.min(state.overviewDragStart, state.overviewDragCurrent);
  const end = Math.max(state.overviewDragStart, state.overviewDragCurrent);
  state.overviewDragStart = null;
  state.overviewDragCurrent = null;
  if (end - start >= 5000) {
    state.viewStart = clamp(start, state.fullStart, state.fullEnd);
    state.viewEnd = clamp(end, state.fullStart, state.fullEnd);
  }
  overviewCanvas.releasePointerCapture(event.pointerId);
  redrawAll();
});
overviewCanvas.addEventListener("dblclick", resetZoom);

findingsList.addEventListener("click", event => {
  const button = event.target.closest(".zoomFinding");
  if (!button || state.fullStart === null || state.fullEnd === null) return;
  const timestamp = Number(button.dataset.timestamp);
  const radius = Math.max(30000, (state.fullEnd - state.fullStart) * 0.01);
  state.viewStart = Math.max(state.fullStart, timestamp - radius);
  state.viewEnd = Math.min(state.fullEnd, timestamp + radius);
  state.cursorMs = timestamp;
  updateReadingPanel();
  redrawAll();
});

document.getElementById("resetZoom").addEventListener("click", resetZoom);
category.addEventListener("change", updateCounterList);
search.addEventListener("input", updateCounterList);
startRange.addEventListener("input", () => {
  let start = sliderValueToMs(startRange.value);
  const end = state.selectedEnd;
  if (start >= end) {
    start = Math.max(state.captureStart, end - 1000);
  }
  applySelectedRange(start, end, "start");
});
endRange.addEventListener("input", () => {
  const start = state.selectedStart;
  let end = sliderValueToMs(endRange.value);
  if (end <= start) {
    end = Math.min(state.captureEnd, start + 1000);
  }
  applySelectedRange(start, end, "end");
});
startTime.addEventListener("change", () => {
  const value = inputToMs(startTime);
  applySelectedRange(value === null ? state.captureStart : value, state.selectedEnd, "start");
});
endTime.addEventListener("change", () => {
  const value = inputToMs(endTime);
  applySelectedRange(state.selectedStart, value === null ? state.captureEnd : value, "end");
});
window.addEventListener("resize", redrawAll);

fetch("/api/metadata")
  .then(response => response.json())
  .then(payload => {
    state.counters = payload.Counters;
    initializeTimeRange(payload.StartMilliseconds, payload.EndMilliseconds);
    const categories = [...new Set(state.counters.map(c => c.Category))].sort();
    category.innerHTML = categories.map(c => `<option>${c}</option>`).join("");
    if (categories.includes("Disk")) category.value = "Disk";
    updateCounterList();
    setStatus(`${state.counters.length.toLocaleString()} counters available from ${payload.FileName}.`);
  })
  .catch(error => setStatus(error.message, true));
</script>
</body>
</html>
'@

$blgFile = Get-BlogFile -Path $InputPath
Write-Host "Reading counter metadata from $($blgFile.FullName)..."

$counterMap = @{}
$counterSets = @(Import-Counter -Path $blgFile.FullName -ListSet * -ErrorAction Stop)
foreach ($set in $counterSets) {
    $paths = @($set.PathsWithInstances)
    if ($paths.Count -eq 0) {
        $paths = @($set.Paths)
    }
    foreach ($path in $paths) {
        if (-not $counterMap.ContainsKey($path)) {
            $counterMap[$path] = Split-CounterPath -Path $path
        }
    }
}

$counterMetadata = @($counterMap.Values |
    Sort-Object Category, CounterSet, Instance, Counter)
$captureRange = Get-CaptureRange -BlogPath $blgFile.FullName `
    -CounterPath $counterMetadata[0].Path
$captureStartOffset = [datetimeoffset]$captureRange.Start
$captureEndOffset = [datetimeoffset]$captureRange.End
$metadataJson = [pscustomobject][ordered]@{
    FileName          = $blgFile.Name
    FilePath          = $blgFile.FullName
    StartTime         = $captureRange.Start.ToString('o')
    EndTime           = $captureRange.End.ToString('o')
    StartMilliseconds = $captureStartOffset.ToUnixTimeMilliseconds()
    EndMilliseconds   = $captureEndOffset.ToUnixTimeMilliseconds()
    Counters          = $counterMetadata
} | ConvertTo-Json -Depth 4 -Compress

$listener = New-Object System.Net.Sockets.TcpListener -ArgumentList @(
    [System.Net.IPAddress]::Loopback,
    $Port)
$listener.Start()
$actualPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$url = "http://127.0.0.1:$actualPort/"

Write-Host ''
Write-Host "Dashboard: $url"
Write-Host "BLG: $($blgFile.FullName)"
Write-Host "Counters available: $($counterMetadata.Count)"
Write-Host 'Press Ctrl+C to stop the dashboard.'

if (-not $NoBrowser) {
    Start-Process $url
}

try {
    while ($true) {
        if (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 100
            continue
        }

        $client = $listener.AcceptTcpClient()
        $stream = $null
        $reader = $null
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader -ArgumentList @(
                $stream,
                [Text.Encoding]::ASCII,
                $false,
                4096,
                $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }

            while (-not [string]::IsNullOrEmpty($reader.ReadLine())) {
            }

            $requestParts = $requestLine.Split(' ')
            if ($requestParts.Count -lt 2 -or $requestParts[0] -ne 'GET') {
                Send-HttpResponse -Stream $stream -StatusCode 400 `
                    -ContentType 'application/json; charset=utf-8' `
                    -Body '{"error":"Only GET requests are supported."}'
                continue
            }

            $requestUri = [uri]("http://127.0.0.1$($requestParts[1])")
            switch ($requestUri.AbsolutePath) {
                '/' {
                    Send-HttpResponse -Stream $stream -StatusCode 200 `
                        -ContentType 'text/html; charset=utf-8' -Body $html
                }
                '/api/metadata' {
                    Send-HttpResponse -Stream $stream -StatusCode 200 `
                        -ContentType 'application/json; charset=utf-8' -Body $metadataJson
                }
                '/api/data' {
                    try {
                        $query = Get-QueryParameters -Query $requestUri.Query
                        if (-not $query.ContainsKey('path') -or
                            -not $counterMap.ContainsKey($query.path)) {
                            throw 'The requested counter path is missing or is not present in the BLG.'
                        }

                        $startOffset = $captureStartOffset
                        $endOffset = $captureEndOffset
                        if ($query.ContainsKey('start')) {
                            $startOffset = [datetimeoffset]::Parse(
                                $query.start,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::RoundtripKind)
                        }
                        if ($query.ContainsKey('end')) {
                            $endOffset = [datetimeoffset]::Parse(
                                $query.end,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::RoundtripKind)
                        }
                        if ($startOffset -lt $captureStartOffset) {
                            $startOffset = $captureStartOffset
                        }
                        if ($endOffset -gt $captureEndOffset) {
                            $endOffset = $captureEndOffset
                        }
                        if ($startOffset -gt $endOffset) {
                            throw 'Start time must be earlier than end time.'
                        }

                        $data = Get-CounterData -BlogPath $blgFile.FullName `
                            -CounterPath $query.path `
                            -Start $startOffset.ToString('o') `
                            -End $endOffset.ToString('o')
                        $body = $data | ConvertTo-Json -Depth 5 -Compress
                        Send-HttpResponse -Stream $stream -StatusCode 200 `
                            -ContentType 'application/json; charset=utf-8' -Body $body
                    }
                    catch {
                        $errorBody = [pscustomobject]@{ error = $_.Exception.Message } |
                            ConvertTo-Json -Compress
                        Send-HttpResponse -Stream $stream -StatusCode 400 `
                            -ContentType 'application/json; charset=utf-8' -Body $errorBody
                    }
                }
                default {
                    Send-HttpResponse -Stream $stream -StatusCode 404 `
                        -ContentType 'application/json; charset=utf-8' `
                        -Body '{"error":"Not found."}'
                }
            }
        }
        catch {
            if ($null -ne $stream -and $stream.CanWrite) {
                $errorBody = [pscustomobject]@{ error = $_.Exception.Message } |
                    ConvertTo-Json -Compress
                Send-HttpResponse -Stream $stream -StatusCode 500 `
                    -ContentType 'application/json; charset=utf-8' -Body $errorBody
            }
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
