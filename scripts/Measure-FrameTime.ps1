<#
.SYNOPSIS
Measures individual frame durations from a Victory diagnostic boot log.

.DESCRIPTION
Uses the integer-millisecond samples following "each:" in Victory's frame
reports. A time window includes only complete reports fully inside the window.
Batch start is approximate because Victory rounds the reported batch length.
The 500-draw marker identifies the start of world rendering. Choose an explicit
timestamp for a specific gameplay segment.

.PARAMETER CompareCardRehashPhases
Compares the two logged CARD_REHASH_RUNS=alt settings inside an explicitly
anchored, finite window. Reports crossing a mode change are excluded. Pooled
statistics use all selected individual frames of each mode.

.EXAMPLE
./Measure-VictoryFrameTime.ps1 -LogPath boot.log -AfterFirstWorld -StartSeconds 30 -DurationSeconds 60

.EXAMPLE
./Measure-VictoryFrameTime.ps1 -LogPath boot.log -AnchorTimestamp '2026-11-25T22:30:00Z' -DurationSeconds 120 -CompareCardRehashPhases
#>
[CmdletBinding(DefaultParameterSetName = 'FullLog')]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $LogPath,

    [Parameter(Mandatory, ParameterSetName = 'World')]
    [switch] $AfterFirstWorld,

    [Parameter(Mandatory, ParameterSetName = 'Timestamp')]
    [datetimeoffset] $AnchorTimestamp,

    [Parameter(ParameterSetName = 'World')]
    [Parameter(ParameterSetName = 'Timestamp')]
    [ValidateRange(0.0, 86400.0)]
    [double] $StartSeconds = 0,

    [Parameter(ParameterSetName = 'World')]
    [Parameter(ParameterSetName = 'Timestamp')]
    [ValidateRange(0.001, 86400.0)]
    [double] $DurationSeconds,

    [Parameter(ParameterSetName = 'Timestamp')]
    [switch] $CompareCardRehashPhases
)

$ErrorActionPreference = 'Stop'
if ($CompareCardRehashPhases -and !$PSBoundParameters.ContainsKey('DurationSeconds')) {
    throw 'Comparing rehash phases requires DurationSeconds and a steady gameplay timestamp.'
}
$log = Get-Item -LiteralPath $LogPath
if ($log -isnot [IO.FileInfo]) { throw 'LogPath must name a log file.' }

function Measure-FrameSamples([Collections.Generic.List[double]] $Samples) {
    $count = $Samples.Count
    $stats = [ordered]@{ FrameCount = $count; MeanFps = $null; MeanFrameMs = $null; MedianFrameMs = $null; P95FrameMs = $null }
    if ($count) {
        $totalMs = 0.0
        foreach ($duration in $Samples) { $totalMs += $duration }
        $Samples.Sort()
        $middle = [int][math]::Floor($count / 2)
        $stats.MeanFrameMs = [math]::Round($totalMs / $count, 2)
        if ($totalMs -gt 0) { $stats.MeanFps = [math]::Round(1000 * $count / $totalMs, 2) }
        $stats.MedianFrameMs = if ($count % 2) { $Samples[$middle] } else {
            ($Samples[$middle - 1] + $Samples[$middle]) / 2
        }
        $stats.P95FrameMs = $Samples[[int][math]::Ceiling(0.95 * $count) - 1]
    }
    $stats
}

$culture = [Globalization.CultureInfo]::InvariantCulture
$timestampPattern = '(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))'
$ansi = [regex]'\x1b\[[0-?]*[ -/]*[@-~]'
$worldLine = [regex]("^$timestampPattern\s+\w+\s+victory_gpu::capture:\s+the first frame of 500 draws or more:")
$batchLine = [regex]("^$timestampPattern\s+\w+\s+victory_gpu::framelog:\s+frame times: (?<count>[1-9][0-9]*) frames in (?<span>[0-9]+(?:\.[0-9]+)?) s:(?<report>.*)$")
$sampleLine = [regex]';\s*each:\s*(?<samples>.*)$'
$samplePattern = [regex]'^[0-9]+(?:\s+[0-9]+)*$'
$rehashLabel = 'card rehash passes from now (VICTORY_CARD_REHASH_RUNS=alt):'
$rehashLine = [regex]("^$timestampPattern\s+\w+\s+victory_gpu::host:\s+$([regex]::Escape($rehashLabel))\s+(?<mode>JOINED, one pass a run of touching pieces|one pass a range sent up, as usual)\s*$")

$worldMarker = $null
$windowStart = $null
$windowEnd = $null
if ($PSCmdlet.ParameterSetName -eq 'Timestamp') {
    $windowStart = $AnchorTimestamp.ToUniversalTime().AddSeconds($StartSeconds)
    if ($DurationSeconds) { $windowEnd = $windowStart.AddSeconds($DurationSeconds) }
}

$batches = $complete = $selected = $before = $after = $boundary = $missing = $incomplete = 0
$lastCompleteEnd = $null
$firstSelectedStart = $null
$lastSelectedEnd = $null
$frames = [Collections.Generic.List[double]]::new()
$phases = [Collections.Generic.List[object]]::new()
$phase = $null
$beforePhase = $crossingPhase = 0

# Share write access so the same parser can inspect a live boot log.
$stream = [IO.File]::Open($log.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$reader = [IO.StreamReader]::new($stream)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        $mightChangePhase = $CompareCardRehashPhases -and $line.Contains($rehashLabel)
        if (!$mightChangePhase -and !$line.Contains('frame times:') -and !$line.Contains('first frame of 500 draws')) { continue }
        $line = $ansi.Replace($line, '')
        if ($mightChangePhase) {
            $change = $rehashLine.Match($line)
            if (!$change.Success) { continue }
            $mode = if ($change.Groups['mode'].Value.StartsWith('JOINED')) { 'Joined' } else { 'PerRange' }
            if ($null -ne $phase -and $phase.Mode -eq $mode) { continue }
            $changedAt = [datetimeoffset]::Parse($change.Groups['timestamp'].Value, $culture).ToUniversalTime()
            if ($null -ne $phase) { $phase.EndUtc = $changedAt }
            $phase = [pscustomobject]@{
                Mode = $mode
                StartUtc = $changedAt
                EndUtc = $null
                SelectedBatches = 0
                FirstBatchStartUtc = $null
                LastBatchEndUtc = $null
                Samples = [Collections.Generic.List[double]]::new()
            }
            $phases.Add($phase)
            continue
        }

        $marker = $worldLine.Match($line)
        if ($marker.Success -and $null -eq $worldMarker) {
            $worldMarker = [datetimeoffset]::Parse($marker.Groups['timestamp'].Value, $culture).ToUniversalTime()
            if ($AfterFirstWorld) {
                $windowStart = $worldMarker.AddSeconds($StartSeconds)
                if ($DurationSeconds) { $windowEnd = $windowStart.AddSeconds($DurationSeconds) }
            }
            continue
        }

        $batch = $batchLine.Match($line)
        if (!$batch.Success) { continue }
        $batches++
        $samples = $sampleLine.Match($batch.Groups['report'].Value)
        if (!$samples.Success) {
            $missing++
            continue
        }
        $sampleText = $samples.Groups['samples'].Value.Trim()
        if (!$samplePattern.IsMatch($sampleText)) {
            $incomplete++
            continue
        }
        $values = [regex]::Split($sampleText, '\s+')
        if ($values.Count -ne [int]$batch.Groups['count'].Value) {
            $incomplete++
            continue
        }

        $batchEnd = [datetimeoffset]::Parse($batch.Groups['timestamp'].Value, $culture).ToUniversalTime()
        $batchSpan = [double]::Parse($batch.Groups['span'].Value, $culture)
        $batchStart = $batchEnd.AddSeconds(-$batchSpan)
        $complete++
        $lastCompleteEnd = $batchEnd

        if (($AfterFirstWorld -and $null -eq $worldMarker) -or
            ($null -ne $windowStart -and $batchEnd -le $windowStart)) {
            $before++
            continue
        }
        if ($null -ne $windowEnd -and $batchStart -ge $windowEnd) {
            $after++
            continue
        }
        if (($null -ne $windowStart -and $batchStart -lt $windowStart) -or
            ($null -ne $windowEnd -and $batchEnd -gt $windowEnd)) {
            $boundary++
            continue
        }
        if ($CompareCardRehashPhases) {
            if ($null -eq $phase) {
                $beforePhase++
                continue
            }
            if ($batchStart -lt $phase.StartUtc) {
                $crossingPhase++
                continue
            }
            $phase.SelectedBatches++
            if ($null -eq $phase.FirstBatchStartUtc) { $phase.FirstBatchStartUtc = $batchStart }
            $phase.LastBatchEndUtc = $batchEnd
        }
        $selected++
        if ($null -eq $firstSelectedStart) { $firstSelectedStart = $batchStart }
        $lastSelectedEnd = $batchEnd
        foreach ($value in $values) {
            $milliseconds = [double]::Parse($value, $culture)
            $frames.Add($milliseconds)
            if ($CompareCardRehashPhases) { $phase.Samples.Add($milliseconds) }
        }
    }
} finally {
    $reader.Dispose()
}

$report = [ordered]@{
    LogPath = $log.FullName
    Status = if ($AfterFirstWorld -and $null -eq $worldMarker) { 'WorldMarkerMissing' }
        elseif (!$complete) { 'NoCompleteFrameLists' }
        elseif (!$selected) { 'NoCompleteBatchesInWindow' }
        else { 'Measured' }
    WorldMarkerUtc = $worldMarker
    WindowStartUtc = $windowStart
    WindowEndUtc = $windowEnd
    FirstSelectedBatchStartUtc = $firstSelectedStart
    LastSelectedBatchEndUtc = $lastSelectedEnd
    LastCompleteBatchEndUtc = $lastCompleteEnd
    HasReportThroughWindowEnd = if ($null -ne $windowEnd) {
        $null -ne $lastCompleteEnd -and $lastCompleteEnd -ge $windowEnd
    }
    ReportedBatches = $batches
    CompleteBatches = $complete
    MissingFrameLists = $missing
    IncompleteFrameLists = $incomplete
    BatchesBeforeWindow = $before
    BatchesAfterWindow = $after
    BatchesCrossingWindow = $boundary
    SelectedBatches = $selected
}
$report += Measure-FrameSamples $frames

if ($CompareCardRehashPhases) {
    $measuredPhases = @($phases | Where-Object SelectedBatches -gt 0)
    $pooled = foreach ($mode in 'PerRange', 'Joined') {
        $modePhases = @($measuredPhases | Where-Object Mode -eq $mode)
        $samples = [Collections.Generic.List[double]]::new()
        $modeBatches = 0
        foreach ($item in $modePhases) {
            $samples.AddRange($item.Samples)
            $modeBatches += $item.SelectedBatches
        }
        [pscustomobject]([ordered]@{
            Mode = $mode
            PhaseCount = $modePhases.Count
            SelectedBatches = $modeBatches
        } + (Measure-FrameSamples $samples))
    }
    if (!$phases.Count) { $report.Status = 'NoLoggedCardRehashPhases' }
    elseif ($report.Status -eq 'Measured' -and ($pooled | Where-Object FrameCount -eq 0)) {
        $report.Status = 'NoComparableCardRehashPhases'
    }
    $report.BatchesBeforeFirstPhaseMarker = $beforePhase
    $report.BatchesCrossingPhaseMarker = $crossingPhase
    $report.RehashPooledByMode = @($pooled)
    $report.RehashPhases = @(foreach ($item in $measuredPhases) {
        [pscustomobject]([ordered]@{
            Mode = $item.Mode
            PhaseStartUtc = $item.StartUtc
            PhaseEndUtc = $item.EndUtc
            FirstSelectedBatchStartUtc = $item.FirstBatchStartUtc
            LastSelectedBatchEndUtc = $item.LastBatchEndUtc
            SelectedBatches = $item.SelectedBatches
        } + (Measure-FrameSamples $item.Samples))
    })
}

[pscustomobject]$report
