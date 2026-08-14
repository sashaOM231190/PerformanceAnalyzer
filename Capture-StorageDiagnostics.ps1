<#
.SYNOPSIS
Captures storage diagnostics and can run an interactive DiskSpd baseline.

.DESCRIPTION
Starts one-second PerfMon collection, a circular Microsoft-Windows-StorPort
trace, and a circular Windows kernel process/file/disk I/O trace. Press Enter
after reproducing the issue. The script then stops the collectors and writes
DiskMapping.json for BLG, Storport, process, volume, and disk correlation.
With -SetBaseline, the script prompts for a safe file target and workload
preset, or accepts a custom DiskSpd command. It runs diskspd.exe from the
script directory and stores its XML result in the capture folder.

.EXAMPLE
.\Capture-StorageDiagnostics.ps1

.EXAMPLE
.\Capture-StorageDiagnostics.ps1 -OutputRoot D:\StorageTraces

.EXAMPLE
.\Capture-StorageDiagnostics.ps1 -SetBaseline
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = 'C:\PerfLogs',

    [ValidateRange(256, 8192)]
    [int]$ProcessIoTraceMaxMB = 1024,

    [switch]$SetBaseline
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$principal = New-Object -TypeName Security.Principal.WindowsPrincipal `
    -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$captureDirectory = Join-Path $OutputRoot "StorageCapture-$timestamp"
$perfOutput = Join-Path $captureDirectory 'Storage.blg'
$storportOutput = Join-Path $captureDirectory 'Storport.etl'
$processIoOutput = Join-Path $captureDirectory 'ProcessVolume.etl'
$mappingOutput = Join-Path $captureDirectory 'DiskMapping.json'
$manifestOutput = Join-Path $captureDirectory 'CaptureManifest.json'
$diskSpdOutput = Join-Path $captureDirectory 'DiskSpd-baseline.xml'
$perfCollector = "PerformanceAnalyzerPerf-$PID"
$storportSession = "PerformanceAnalyzerStorport-$PID"
$processIoSession = 'NT Kernel Logger'

New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null

$counterPaths = @(
    '\LogicalDisk(*)\*'
    '\Memory\*'
    '\Network Interface(*)\*'
    '\Paging File(*)\*'
    '\PhysicalDisk(*)\*'
    '\Processor(*)\*'
    '\Process(*)\*'
    '\Redirector\*'
    '\Server\*'
    '\System\*'
)

function Invoke-Logman {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    & logman.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed. Logman exit code: $LASTEXITCODE"
    }
}

if ($null -eq ('PerformanceAnalyzer.CommandLineNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PerformanceAnalyzer
{
    public static class CommandLineNativeMethods
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CommandLineToArgvW(
            string commandLine,
            out int argumentCount);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr LocalFree(IntPtr memory);
    }
}
'@
}

function ConvertFrom-WindowsCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $argumentCount = 0
    $argumentPointer = [PerformanceAnalyzer.CommandLineNativeMethods]::
        CommandLineToArgvW(
            "PerformanceAnalyzerCommand.exe $CommandLine",
            [ref]$argumentCount)
    if ($argumentPointer -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Unable to parse the DiskSpd command. Windows error: $errorCode"
    }

    try {
        $arguments = for ($index = 1; $index -lt $argumentCount; $index++) {
            $itemPointer = [Runtime.InteropServices.Marshal]::ReadIntPtr(
                $argumentPointer,
                $index * [IntPtr]::Size)
            [Runtime.InteropServices.Marshal]::PtrToStringUni($itemPointer)
        }
        @($arguments)
    }
    finally {
        $null = [PerformanceAnalyzer.CommandLineNativeMethods]::LocalFree(
            $argumentPointer)
    }
}

function Format-NativeCommandArgument {
    param([string]$Argument)

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }
    '"' + ($Argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Get-DiskSpdOptionSeconds {
    param(
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Option,
        [Parameter(Mandatory = $true)]
        [int]$DefaultValue
    )

    $value = $DefaultValue
    foreach ($argument in $Arguments) {
        if ($argument -cmatch "^-$Option(\d+)$") {
            $value = [int]$Matches[1]
        }
    }
    $value
}

function Get-CustomDiskSpdConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiskSpdPath
    )

    Write-Host ''
    Write-Host 'Enter the complete DiskSpd command.' -ForegroundColor Cyan
    Write-Host 'Example:'
    Write-Host (
        'diskspd.exe -c10G -d60 -W20 -r8K -w0 -b64K ' +
        '-t4 -o8 -Sh -L C:\Temp\diskspd_test.dat')
    $commandLine = Read-Host 'DiskSpd command'
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        throw 'A custom DiskSpd command is required.'
    }

    $arguments = @(ConvertFrom-WindowsCommandLine -CommandLine $commandLine)
    if ($arguments.Count -eq 0) {
        throw 'The custom DiskSpd command did not contain any arguments.'
    }

    $firstLeaf = Split-Path -Leaf $arguments[0]
    if ($firstLeaf -match '^(?i)diskspd(?:\.exe)?$') {
        $arguments = @($arguments | Select-Object -Skip 1)
    }
    elseif ($arguments[0] -match '(?i)\.exe$') {
        throw (
            "Only diskspd.exe commands are accepted. Received: " +
            $arguments[0])
    }

    if ($arguments.Count -eq 0) {
        throw 'The custom DiskSpd command did not contain workload arguments.'
    }
    if (@($arguments | Where-Object {
                $_ -match '^(?:\||&|&&|;|>|>>|<|2>|2>>|--%)$'
            }).Count -gt 0) {
        throw (
            'Shell operators and output redirection are not accepted. ' +
            'The script writes DiskSpd XML directly into the capture folder.')
    }

    $targetIndexes = @()
    for ($index = 0; $index -lt $arguments.Count; $index++) {
        if ($arguments[$index] -notmatch '^[-/]') {
            $targetIndexes += $index
        }
    }
    if ($targetIndexes.Count -ne 1) {
        throw (
            "Custom baseline mode requires exactly one file target; found " +
            "$($targetIndexes.Count). For a multi-target test, run " +
            ".\Capture-StorageDiagnostics.ps1 without -SetBaseline, run " +
            'DiskSpd separately while the capture is active, and press Enter ' +
            'when the test finishes.')
    }

    $sourceTarget = [Environment]::ExpandEnvironmentVariables(
        $arguments[$targetIndexes[0]].Trim())
    if ($sourceTarget -match '^(#\d+|\\\\\.\\PhysicalDrive\d+)$') {
        throw (
            'Raw disk targets are blocked in baseline mode because a write ' +
            'workload can overwrite disk data. Use a normal capture and run ' +
            'the raw-disk test separately only after validating its safety.')
    }
    if ($sourceTarget -notmatch '^(?<Drive>[A-Za-z]):(?:\\.*)?$') {
        throw (
            'The custom baseline target must be a local drive or file path, ' +
            'such as C:, C:\, or C:\Temp\diskspd_test.dat.')
    }

    $driveRoot = "$($Matches.Drive.ToUpperInvariant()):\"
    if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
        throw "The target drive does not exist: $driveRoot"
    }

    $targetDirectory = if ($sourceTarget -match '^[A-Za-z]:\\?$') {
        $driveRoot
    }
    elseif ($sourceTarget.EndsWith('\')) {
        [IO.Path]::GetFullPath($sourceTarget.TrimEnd('\'))
    }
    else {
        Split-Path -Parent ([IO.Path]::GetFullPath($sourceTarget))
    }
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        throw "The DiskSpd target directory does not exist: $targetDirectory"
    }

    $targetPath = Join-Path $targetDirectory 'DiskSpdBaseline.dat'
    $arguments[$targetIndexes[0]] = $targetPath

    $adjustments = @(
        "Target changed from '$sourceTarget' to '$targetPath'. The supplied " +
        'directory is preserved and only the temporary filename is replaced.'
    )
    if (-not (@($arguments | Where-Object { $_ -ceq '-Rxml' }).Count)) {
        $arguments = @('-Rxml') + $arguments
        $adjustments += (
            '-Rxml added so the result can be saved and analyzed from the ' +
            'capture folder.')
    }
    if (-not (@($arguments | Where-Object { $_ -ceq '-L' }).Count)) {
        $arguments = @('-L') + $arguments
        $adjustments += '-L added so DiskSpd records latency statistics.'
    }

    $targetExisted = Test-Path -LiteralPath $targetPath -PathType Leaf
    $hasCreateOption = @($arguments | Where-Object {
            $_ -cmatch '^-c(?:\d+(?:\.\d+)?[KMG]?)$'
        }).Count -gt 0
    if (-not $targetExisted -and -not $hasCreateOption) {
        throw (
            "The effective target does not exist: $targetPath. Add a DiskSpd " +
            '-c<size> option, for example -c10G, so DiskSpd can create it.')
    }

    $writesToTarget = @($arguments | Where-Object {
            $_ -cmatch '^-w(?:[1-9]\d?|100)$'
        }).Count -gt 0

    $effectiveCommand = @(
        (Format-NativeCommandArgument -Argument $DiskSpdPath)
        $arguments | ForEach-Object {
            Format-NativeCommandArgument -Argument $_
        }
    ) -join ' '

    Write-Host ''
    Write-Host 'Custom command adjustments:' -ForegroundColor Yellow
    foreach ($adjustment in $adjustments) {
        Write-Host "  - $adjustment"
    }
    Write-Host 'Effective command:' -ForegroundColor Cyan
    Write-Host $effectiveCommand
    if ($targetExisted -and ($hasCreateOption -or $writesToTarget)) {
        Write-Warning (
            "The custom workload can modify or resize the existing file: " +
            $targetPath)
    }
    $confirmation = Read-Host 'Run this effective command? [Y/N]'
    if ($confirmation -notmatch '^(?i)y(?:es)?$') {
        throw 'DiskSpd baseline cancelled by the user.'
    }

    [pscustomobject][ordered]@{
        Executable = $DiskSpdPath
        Preset = 'Custom DiskSpd command'
        TargetPath = $targetPath
        TargetExisted = $targetExisted
        CreatedTarget = -not $targetExisted
        OutputPath = $diskSpdOutput
        Arguments = @($arguments)
        MeasurementSeconds = Get-DiskSpdOptionSeconds `
            -Arguments $arguments -Option 'd' -DefaultValue 10
        WarmupSeconds = Get-DiskSpdOptionSeconds `
            -Arguments $arguments -Option 'W' -DefaultValue 5
        CooldownSeconds = Get-DiskSpdOptionSeconds `
            -Arguments $arguments -Option 'C' -DefaultValue 0
        OriginalCommand = $commandLine
        EffectiveCommand = $effectiveCommand
    }
}

function Get-DiskSpdBaselineConfiguration {
        $diskSpdPath = Join-Path $PSScriptRoot 'diskspd.exe'
        if (-not (Test-Path -LiteralPath $diskSpdPath -PathType Leaf)) {
            throw "SetBaseline requires diskspd.exe in the script directory: $diskSpdPath"
        }

        Write-Host ''
        Write-Host 'DiskSpd baseline setup' -ForegroundColor Cyan
        Write-Host '  1. Balanced random: 64 KiB, 70% read / 30% write'
        Write-Host '  2. Random read IOPS: 4 KiB, 100% read'
        Write-Host '  3. Sequential read throughput: 1 MiB, 100% read'
        Write-Host '  4. Sequential write throughput: 1 MiB, 100% write'
        Write-Host '  5. Custom DiskSpd command'

        $selection = $null
        while ($selection -notin @('1', '2', '3', '4', '5')) {
            $selection = Read-Host 'Select workload preset [1]'
            if ([string]::IsNullOrWhiteSpace($selection)) {
                $selection = '1'
            }
        }

        if ($selection -eq '5') {
            return Get-CustomDiskSpdConfiguration -DiskSpdPath $diskSpdPath
        }

        $targetPath = Read-Host (
            'Target drive or test file path [C:]')
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            $targetPath = 'C:'
        }
        $targetPath = [Environment]::ExpandEnvironmentVariables(
            $targetPath.Trim().Trim('"'))
        if ($targetPath -match '^[A-Za-z]$') {
            $targetPath = "$targetPath`:"
        }
        if ($targetPath -match '^[A-Za-z]:$') {
            $targetPath = Join-Path "$targetPath\" 'DiskSpdBaseline.dat'
        }
        if ($targetPath -match '^(#\d+|\\\\\.\\PhysicalDrive\d+)$') {
            throw 'Interactive baseline mode accepts only a file target, not a raw disk or volume.'
        }

        $targetPath = [IO.Path]::GetFullPath($targetPath)
        $targetDirectory = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            throw "The DiskSpd target directory does not exist: $targetDirectory"
        }

        $preset = switch ($selection) {
            '1' {
                [pscustomobject]@{
                    Name = 'Balanced random 64 KiB 70/30'
                    Arguments = @('-b64K', '-o8', '-t4', '-r', '-w30')
                }
            }
            '2' {
                [pscustomobject]@{
                    Name = 'Random read IOPS 4 KiB'
                    Arguments = @('-b4K', '-o32', '-t4', '-r', '-w0')
                }
            }
            '3' {
                [pscustomobject]@{
                    Name = 'Sequential read throughput 1 MiB'
                    Arguments = @('-b1M', '-o8', '-t2', '-s', '-w0')
                }
            }
            '4' {
                [pscustomobject]@{
                    Name = 'Sequential write throughput 1 MiB'
                    Arguments = @('-b1M', '-o8', '-t2', '-s', '-w100')
                }
            }
        }

        $targetExisted = Test-Path -LiteralPath $targetPath -PathType Leaf
        if ($targetExisted -and $selection -in @('1', '4')) {
            Write-Warning (
                "The selected workload writes to the existing file and can " +
                "overwrite its contents: $targetPath")
            $confirmation = Read-Host 'Type YES to continue'
            if ($confirmation -cne 'YES') {
                throw 'DiskSpd baseline cancelled before modifying the existing file.'
            }
        }
        $arguments = @()
        if (-not $targetExisted) {
            $arguments += '-c10G'
        }
        $arguments += @(
            $preset.Arguments
            '-Sh'
            '-W0'
            '-d60'
            '-C0'
            '-L'
            '-D1000'
            '-Rxml'
            $targetPath
        )

        [pscustomobject][ordered]@{
            Executable = $diskSpdPath
            Preset = $preset.Name
            TargetPath = $targetPath
            TargetExisted = $targetExisted
            CreatedTarget = -not $targetExisted
            OutputPath = $diskSpdOutput
            Arguments = @($arguments)
            MeasurementSeconds = 60
            WarmupSeconds = 0
            CooldownSeconds = 0
            OriginalCommand = $null
            EffectiveCommand = $null
        }
}

function Invoke-DiskSpdBaseline {
    param([object]$Configuration)

        Write-Host ''
        Write-Host "Running DiskSpd baseline: $($Configuration.Preset)" `
            -ForegroundColor Cyan
        Write-Host "Target: $($Configuration.TargetPath)"
        Write-Host (
            "Warmup: $($Configuration.WarmupSeconds) seconds; " +
            "measurement: $($Configuration.MeasurementSeconds) seconds; " +
            "cooldown: $($Configuration.CooldownSeconds) seconds.")

        $standardErrorPath = Join-Path $captureDirectory `
            'DiskSpd-baseline.stderr.txt'
        try {
            & $Configuration.Executable @($Configuration.Arguments) `
                2> $standardErrorPath |
                Set-Content -LiteralPath $Configuration.OutputPath `
                    -Encoding UTF8
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $details = if (Test-Path -LiteralPath $standardErrorPath) {
                    (Get-Content -LiteralPath $standardErrorPath -Raw).Trim()
                }
                else { '' }
                throw (
                    "DiskSpd failed with exit code $exitCode." +
                    $(if ($details) { " $details" } else { '' }))
            }
            if (-not (Test-Path -LiteralPath $Configuration.OutputPath) -or
                (Get-Item -LiteralPath $Configuration.OutputPath).Length -eq 0) {
                throw 'DiskSpd completed without producing an XML result.'
            }
            $firstContent = Get-Content -LiteralPath `
                $Configuration.OutputPath -Raw
            if ($firstContent -notmatch '<Results(?:\s|>)') {
                throw 'DiskSpd output is not a Results XML document.'
            }
        }
        finally {
            if (Test-Path -LiteralPath $standardErrorPath) {
                Remove-Item -LiteralPath $standardErrorPath -Force
            }
        }

        Write-Host "DiskSpd result: $($Configuration.OutputPath)" `
            -ForegroundColor Green
}

if ($null -eq ('PerformanceAnalyzer.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PerformanceAnalyzer
{
    public static class NativeMethods
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint QueryDosDevice(
            string deviceName,
            StringBuilder targetPath,
            int maximumLength);
    }
}
'@
}

function Get-NtDevicePath {
    param(
        [string]$DriveLetter,
        [string]$VolumePath
    )

    $deviceName = if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) {
        $DriveLetter
    }
    elseif ($VolumePath -match '^\\\\\?\\(?<Name>Volume\{[^}]+\})\\?$') {
        $Matches.Name
    }
    else {
        $null
    }
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        return $null
    }

    $buffer = New-Object Text.StringBuilder -ArgumentList 32768
    $length = [PerformanceAnalyzer.NativeMethods]::QueryDosDevice(
        $deviceName,
        $buffer,
        $buffer.Capacity)
    if ($length -eq 0) {
        Write-Warning "Unable to resolve the NT device path for $deviceName."
        return $null
    }
    return $buffer.ToString().Split([char]0)[0]
}

function Get-PerfmonDiskInstances {
    $instances = @()
    try {
        $set = Get-Counter -ListSet PhysicalDisk -ErrorAction Stop
        $instances = @($set.PathsWithInstances |
            ForEach-Object {
                if ($_ -match '\\PhysicalDisk\((?<Instance>.+)\)\\') {
                    $Matches.Instance
                }
            } |
            Sort-Object -Unique)
    }
    catch {
        Write-Warning "Unable to enumerate PhysicalDisk instances: $($_.Exception.Message)"
    }
    return $instances
}

function Get-DiskMapping {
    $perfmonInstances = @(Get-PerfmonDiskInstances)
    $storageDisks = @{}
    foreach ($disk in @(Get-Disk -ErrorAction SilentlyContinue)) {
        $storageDisks[[uint32]$disk.Number] = $disk
    }

    $partitionsByDisk = @{}
    foreach ($partition in @(Get-Partition -ErrorAction SilentlyContinue)) {
        $diskNumber = [uint32]$partition.DiskNumber
        if (-not $partitionsByDisk.ContainsKey($diskNumber)) {
            $partitionsByDisk[$diskNumber] =
                New-Object System.Collections.ArrayList
        }

        $driveLetterText = [string]$partition.DriveLetter
        $driveLetter = if (
            -not [string]::IsNullOrWhiteSpace($driveLetterText) -and
            [int][char]$driveLetterText[0] -ne 0) {
            "$driveLetterText`:"
        }
        else {
            $null
        }
        $volume = @(Get-Volume -Partition $partition -ErrorAction SilentlyContinue |
            Select-Object -First 1)
        $volumePath = if ($volume.Count -gt 0) {
            [string]$volume[0].Path
        }
        else {
            $null
        }
        $ntDevicePath = Get-NtDevicePath -DriveLetter $driveLetter `
            -VolumePath $volumePath

        $null = $partitionsByDisk[$diskNumber].Add(
            [pscustomobject][ordered]@{
                PartitionNumber = $partition.PartitionNumber
                DriveLetter     = $driveLetter
                AccessPaths     = @($partition.AccessPaths)
                VolumePath      = $volumePath
                NtDevicePath    = $ntDevicePath
                FileSystemLabel = if ($volume.Count -gt 0) {
                    $volume[0].FileSystemLabel
                }
                else { $null }
                FileSystemType  = if ($volume.Count -gt 0) {
                    $volume[0].FileSystemType
                }
                else { $null }
                SizeBytes       = [uint64]$partition.Size
                Type            = $partition.Type
            })
    }

    $diskRecords = foreach ($wmiDisk in @(
            Get-CimInstance Win32_DiskDrive |
                Sort-Object Index)) {
        $diskNumber = [uint32]$wmiDisk.Index
        $storageDisk = $storageDisks[$diskNumber]
        $partitions = if ($partitionsByDisk.ContainsKey($diskNumber)) {
            @($partitionsByDisk[$diskNumber])
        }
        else {
            @()
        }

        $physicalInstances = @($perfmonInstances |
            Where-Object {
                $_ -eq "$diskNumber" -or
                $_ -like "$diskNumber *"
            })
        $logicalInstances = @($partitions |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.DriveLetter) } |
            ForEach-Object { $_.DriveLetter } |
            Sort-Object -Unique)

        [pscustomobject][ordered]@{
            DiskNumber               = $diskNumber
            PerfmonPhysicalInstances = $physicalInstances
            PerfmonLogicalInstances  = $logicalInstances
            ScsiPort                 = $wmiDisk.SCSIPort
            ScsiBus                  = $wmiDisk.SCSIBus
            ScsiTargetId             = $wmiDisk.SCSITargetId
            ScsiLogicalUnit          = $wmiDisk.SCSILogicalUnit
            DeviceId                 = $wmiDisk.DeviceID
            PnpDeviceId              = $wmiDisk.PNPDeviceID
            Model                    = $wmiDisk.Model
            SerialNumber             = if ($storageDisk) {
                $storageDisk.SerialNumber
            }
            else {
                $wmiDisk.SerialNumber
            }
            UniqueId                 = if ($storageDisk) {
                $storageDisk.UniqueId
            }
            else {
                $null
            }
            FriendlyName             = if ($storageDisk) {
                $storageDisk.FriendlyName
            }
            else {
                $wmiDisk.Caption
            }
            BusType                  = if ($storageDisk) {
                $storageDisk.BusType.ToString()
            }
            else {
                $wmiDisk.InterfaceType
            }
            Location                 = if ($storageDisk) {
                $storageDisk.Location
            }
            else {
                $null
            }
            Path                     = if ($storageDisk) {
                $storageDisk.Path
            }
            else {
                $null
            }
            SizeBytes                = [uint64]$wmiDisk.Size
            Partitions               = $partitions
        }
    }

    [pscustomobject][ordered]@{
        SchemaVersion  = 1
        ComputerName   = $env:COMPUTERNAME
        CollectedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        Description    = 'Disk, volume, NT device path, and SCSI mapping captured with BLG, Storport, and process I/O ETL.'
        Disks          = @($diskRecords)
    }
}

$perfCreated = $false
$perfStarted = $false
$storportStarted = $false
$processIoStarted = $false
$diskSpdConfiguration = if ($SetBaseline) {
    Get-DiskSpdBaselineConfiguration
}
else {
    $null
}
$captureStartedUtc = [DateTimeOffset]::UtcNow

try {
    Write-Host "Capture directory: $captureDirectory"
    Write-Host 'Creating one-second PerfMon collector...'

    $perfCreateArguments = @(
        'create'
        'counter'
        $perfCollector
        '-o'
        $perfOutput
        '-f'
        'bincirc'
        '-v'
        'mmddhhmm'
        '-max'
        '300'
        '-si'
        '00:00:01'
        '-c'
    ) + $counterPaths
    Invoke-Logman -Arguments $perfCreateArguments `
        -Operation 'Creating the PerfMon collector'
    $perfCreated = $true

    Invoke-Logman -Arguments @('start', $perfCollector) `
        -Operation 'Starting the PerfMon collector'
    $perfStarted = $true

    Write-Host 'Starting circular Storport ETW trace...'
    Invoke-Logman -Arguments @(
        'create'
        'trace'
        $storportSession
        '-ow'
        '-o'
        $storportOutput
        '-p'
        'Microsoft-Windows-StorPort'
        '0xffffffffffffffff'
        '0xff'
        '-nb'
        '16'
        '16'
        '-bs'
        '1024'
        '-mode'
        'Circular'
        '-f'
        'bincirc'
        '-max'
        '1024'
        '-ets'
    ) -Operation 'Starting the Storport trace'
    $storportStarted = $true

    if (-not $SetBaseline) {
        & logman.exe query $processIoSession -ets *> $null
        if ($LASTEXITCODE -eq 0) {
            throw "The '$processIoSession' session is already running. Stop the existing kernel trace before starting this capture."
        }

        Write-Host 'Starting circular process, file, and disk I/O trace...'
        Invoke-Logman -Arguments @(
            'create'
            'trace'
            $processIoSession
            '-ow'
            '-o'
            $processIoOutput
            '-p'
            'Windows Kernel Trace'
            '0x06000707'
            '0x5'
            '-nb'
            '16'
            '256'
            '-bs'
            '1024'
            '-mode'
            'Circular'
            '-f'
            'bincirc'
            '-max'
            $ProcessIoTraceMaxMB.ToString()
            '-ets'
        ) -Operation 'Starting the process and volume I/O trace'
        $processIoStarted = $true
    }

    Write-Host ''
    $captureDescription = if ($SetBaseline) {
        'PerfMon and Storport baseline captures are running.'
    }
    else {
        'PerfMon, Storport, and process-volume captures are running.'
    }
    Write-Host $captureDescription -ForegroundColor Green
    if ($SetBaseline) {
        Invoke-DiskSpdBaseline -Configuration $diskSpdConfiguration
    }
    else {
        Write-Host 'Reproduce the storage issue now.'
        $null = Read-Host 'Press Enter after the issue has been reproduced'
    }
}
finally {
    Write-Host ''
    Write-Host 'Stopping captures...'

    if ($processIoStarted) {
        & logman.exe stop $processIoSession -ets
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Stopping process-volume tracing failed with exit code $LASTEXITCODE."
        }
    }

    if ($storportStarted) {
        & logman.exe stop $storportSession -ets
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Stopping Storport failed with exit code $LASTEXITCODE."
        }
    }

    if ($perfStarted) {
        & logman.exe stop $perfCollector
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Stopping PerfMon failed with exit code $LASTEXITCODE."
        }
    }

    if ($perfCreated) {
        & logman.exe delete $perfCollector
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Deleting the PerfMon collector failed with exit code $LASTEXITCODE."
        }
    }

    if ($null -ne $diskSpdConfiguration -and
        $diskSpdConfiguration.CreatedTarget -and
        (Test-Path -LiteralPath $diskSpdConfiguration.TargetPath `
            -PathType Leaf)) {
        Write-Host (
            "Removing temporary DiskSpd test file: " +
            $diskSpdConfiguration.TargetPath)
        try {
            Remove-Item -LiteralPath `
                $diskSpdConfiguration.TargetPath -Force
        }
        catch {
            Write-Warning (
                "Temporary DiskSpd test file could not be removed: " +
                $_.Exception.Message)
        }
    }
}

Write-Host 'Collecting disk correlation information...'
$mapping = Get-DiskMapping
$mapping | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $mappingOutput -Encoding UTF8

$captureStoppedUtc = [DateTimeOffset]::UtcNow
$blgFiles = @(Get-ChildItem -LiteralPath $captureDirectory -Filter '*.blg' -File)
$etlFiles = @(Get-ChildItem -LiteralPath $captureDirectory -Filter '*.etl' -File)
$storportFiles = @($etlFiles | Where-Object { $_.Name -ieq 'Storport.etl' })
$processIoFiles = @($etlFiles | Where-Object { $_.Name -ieq 'ProcessVolume.etl' })
$diskSpdExecutableInfo = if ($null -ne $diskSpdConfiguration) {
    Get-Item -LiteralPath $diskSpdConfiguration.Executable
}
else { $null }
$diskSpdExecutableHash = if ($null -ne $diskSpdExecutableInfo) {
    (Get-FileHash -LiteralPath $diskSpdExecutableInfo.FullName `
        -Algorithm SHA256).Hash
}
else { $null }
$manifest = [pscustomobject][ordered]@{
    SchemaVersion     = 5
    ComputerName      = $env:COMPUTERNAME
    CaptureStartedUtc = $captureStartedUtc.ToString('o')
    CaptureStoppedUtc = $captureStoppedUtc.ToString('o')
    PerfmonFiles      = @($blgFiles |
        ForEach-Object { $_.Name })
    StorportFiles     = @($storportFiles |
        ForEach-Object { $_.Name })
    ProcessIoFiles    = @($processIoFiles |
        ForEach-Object { $_.Name })
    DiskSpdBaselineFile = if (
        Test-Path -LiteralPath $diskSpdOutput -PathType Leaf) {
        Split-Path -Leaf $diskSpdOutput
    }
    else { $null }
    DiskSpdPreset     = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.Preset
    }
    else { $null }
    DiskSpdTarget     = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.TargetPath
    }
    else { $null }
    DiskSpdMeasurementSeconds = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.MeasurementSeconds
    }
    else { $null }
    DiskSpdWarmupSeconds = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.WarmupSeconds
    }
    else { $null }
    DiskSpdCooldownSeconds = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.CooldownSeconds
    }
    else { $null }
    DiskSpdOriginalCommand = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.OriginalCommand
    }
    else { $null }
    DiskSpdEffectiveCommand = if ($null -ne $diskSpdConfiguration) {
        $diskSpdConfiguration.EffectiveCommand
    }
    else { $null }
    DiskSpdExecutableVersion = if ($null -ne $diskSpdExecutableInfo) {
        $diskSpdExecutableInfo.VersionInfo.ProductVersion
    }
    else { $null }
    DiskSpdExecutableSha256 = $diskSpdExecutableHash
    MappingFile       = Split-Path -Leaf $mappingOutput
    PerfmonCollector  = $perfCollector
    StorportSession   = $storportSession
    ProcessIoSession  = if ($processIoStarted) {
        $processIoSession
    }
    else { $null }
    ProcessIoKeywords = if ($processIoStarted) {
        '0x06000707'
    }
    else { $null }
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $manifestOutput -Encoding UTF8

Write-Host ''
Write-Host 'Capture complete.' -ForegroundColor Green
Write-Host "Folder:  $captureDirectory"
Write-Host "BLG:     $(
    @($blgFiles | ForEach-Object { $_.FullName }) -join ', ')"
Write-Host "Storport:$(
    @($storportFiles | ForEach-Object { $_.FullName }) -join ', ')"
$processIoDisplay = if ($processIoFiles.Count -gt 0) {
    @($processIoFiles | ForEach-Object { $_.FullName }) -join ', '
}
elseif ($SetBaseline) {
    'Not collected (baseline mode)'
}
else {
    'No process-volume ETL was produced'
}
Write-Host "Process: $processIoDisplay"
Write-Host "Mapping: $mappingOutput"
Write-Host "Manifest:$manifestOutput"
if (Test-Path -LiteralPath $diskSpdOutput -PathType Leaf) {
    Write-Host "DiskSpd: $diskSpdOutput"
}
