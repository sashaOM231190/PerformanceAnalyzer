<#
.SYNOPSIS
Captures PerfMon and Storport traces, then records disk correlation data.

.DESCRIPTION
Starts one-second PerfMon collection and a circular Microsoft-Windows-StorPort
ETW trace. Press Enter after reproducing the issue. The script then stops both
collectors and writes DiskMapping.json for later BLG/Storport correlation.

.EXAMPLE
.\Capture-StorageDiagnostics.ps1

.EXAMPLE
.\Capture-StorageDiagnostics.ps1 -OutputRoot D:\StorageTraces
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = 'C:\PerfLogs'
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
$mappingOutput = Join-Path $captureDirectory 'DiskMapping.json'
$manifestOutput = Join-Path $captureDirectory 'CaptureManifest.json'
$perfCollector = "PerformanceAnalyzerPerf-$PID"
$storportSession = "PerformanceAnalyzerStorport-$PID"

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

        $null = $partitionsByDisk[$diskNumber].Add(
            [pscustomobject][ordered]@{
                PartitionNumber = $partition.PartitionNumber
                DriveLetter     = $driveLetter
                AccessPaths     = @($partition.AccessPaths)
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
        Description    = 'DiskNumber and SCSI Port/Bus/Target/LUN mapping captured with BLG and Storport ETL.'
        Disks          = @($diskRecords)
    }
}

$perfCreated = $false
$perfStarted = $false
$storportStarted = $false
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

    Write-Host ''
    Write-Host 'PerfMon and Storport capture are running.' -ForegroundColor Green
    Write-Host 'Reproduce the storage issue now.'
    $null = Read-Host 'Press Enter after the issue has been reproduced'
}
finally {
    Write-Host ''
    Write-Host 'Stopping captures...'

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
}

Write-Host 'Collecting disk correlation information...'
$mapping = Get-DiskMapping
$mapping | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $mappingOutput -Encoding UTF8

$captureStoppedUtc = [DateTimeOffset]::UtcNow
$blgFiles = @(Get-ChildItem -LiteralPath $captureDirectory -Filter '*.blg' -File)
$etlFiles = @(Get-ChildItem -LiteralPath $captureDirectory -Filter '*.etl' -File)
$manifest = [pscustomobject][ordered]@{
    SchemaVersion     = 1
    ComputerName      = $env:COMPUTERNAME
    CaptureStartedUtc = $captureStartedUtc.ToString('o')
    CaptureStoppedUtc = $captureStoppedUtc.ToString('o')
    PerfmonFiles      = @($blgFiles.Name)
    StorportFiles     = @($etlFiles.Name)
    MappingFile       = Split-Path -Leaf $mappingOutput
    PerfmonCollector  = $perfCollector
    StorportSession   = $storportSession
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $manifestOutput -Encoding UTF8

Write-Host ''
Write-Host 'Capture complete.' -ForegroundColor Green
Write-Host "Folder:  $captureDirectory"
Write-Host "BLG:     $($blgFiles.FullName -join ', ')"
Write-Host "ETL:     $($etlFiles.FullName -join ', ')"
Write-Host "Mapping: $mappingOutput"
Write-Host "Manifest:$manifestOutput"
