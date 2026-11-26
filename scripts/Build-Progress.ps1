#Requires -Version 7.0
<#
.SYNOPSIS
Builds the public Loam progress report from a reviewed JSON snapshot and the GFX10 decoder.
.EXAMPLE
pwsh -NoProfile -File scripts/Build-Progress.ps1 -OutputDirectory _site
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [ValidateNotNullOrEmpty()]
    [string]$DataPath = (Join-Path $PSScriptRoot '../site/progress.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$invariantCulture = [Globalization.CultureInfo]::InvariantCulture

function Read-Field {
    param($Object, [string]$Name, [string]$Path, [string]$Type)

    $field = "$Path.$Name"
    if ($Object -isnot [Collections.IDictionary] -or -not $Object.Contains($Name)) {
        throw "Missing required field $field."
    }

    $value = $Object[$Name]
    $valid = switch ($Type) {
        'string' { $value -is [string] -and -not [string]::IsNullOrWhiteSpace($value) }
        'object' { $value -is [Collections.IDictionary] }
        'array' { $value -is [array] -and $value.Count -gt 0 }
        'positive' {
            ($value -is [long] -or $value -is [int] -or $value -is [double]) -and
                [double]::IsFinite($value) -and $value -gt 0
        }
        'count' { ($value -is [long] -or $value -is [int]) -and $value -ge 0 }
    }
    if (-not $valid) {
        throw "Invalid $field. Expected $Type."
    }
    if ($Type -eq 'array') {
        return ,$value
    }
    return $value
}

function Encode-Html([string]$Value) {
    return [Net.WebUtility]::HtmlEncode($Value)
}

function Format-Number([double]$Value, [string]$Pattern = '0.##') {
    return $Value.ToString($Pattern, $invariantCulture)
}

function Read-Link($Project, [string]$Name) {
    $value = Read-Field $Project $Name 'project' string
    $uri = $null
    if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or [string]::IsNullOrEmpty($uri.Host) -or $uri.UserInfo) {
        throw "Project field $Name must be an absolute HTTPS URL."
    }
    return Encode-Html $uri.AbsoluteUri
}

$dataFile = (Get-Item -LiteralPath $DataPath).FullName
$source = [IO.File]::ReadAllText($dataFile)
$data = ConvertFrom-Json -InputObject $source -AsHashtable -Depth 12
if ((Read-Field $data 'schemaVersion' '$' count) -ne 1) {
    throw 'Unsupported progress schema version.'
}

$project = Read-Field $data 'project' '$' object
$projectName = Encode-Html (Read-Field $project 'name' 'project' string)
$repositoryUrl = Read-Link $project 'repositoryUrl'
$changelogUrl = Read-Link $project 'changelogUrl'

$target = Read-Field $data 'target' '$' object
$targetFps = Format-Number (Read-Field $target 'fps' 'target' positive)
$targetMs = Format-Number (Read-Field $target 'frameMs' 'target' positive)

$roadmapStates = [ordered]@{
    Verified = '#237a3b'
    Partial = '#8a5f13'
    Blocked = '#a33642'
    Unverified = '#345986'
    Pending = '#515a69'
}
$roadmapById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$roadmapTracks = @(
    if ($data.Contains('roadmap')) {
        $tracks = Read-Field $data 'roadmap' '$' array
        for ($trackIndex = 0; $trackIndex -lt $tracks.Count; $trackIndex++) {
            $trackData = $tracks[$trackIndex]
            $trackPath = "roadmap[$trackIndex]"
            $trackName = Read-Field $trackData 'label' $trackPath string
            $tileData = Read-Field $trackData 'tiles' $trackPath array
            $tiles = @(
                for ($tileIndex = 0; $tileIndex -lt $tileData.Count; $tileIndex++) {
                    $item = $tileData[$tileIndex]
                    $path = "$trackPath.tiles[$tileIndex]"
                    $id = Read-Field $item 'id' $path string
                    if ($id -cnotmatch '\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z' -or $roadmapById.ContainsKey($id)) {
                        throw "Invalid or duplicate roadmap tile identifier in $path."
                    }
                    $status = Read-Field $item 'status' $path string
                    if ($status -cnotin $roadmapStates.Keys) {
                        throw "Unknown roadmap status in $path."
                    }
                    $checks = @(
                        if ($item.Contains('checks')) {
                            $checkData = Read-Field $item 'checks' $path array
                            for ($checkIndex = 0; $checkIndex -lt $checkData.Count; $checkIndex++) {
                                $checkPath = "$path.checks[$checkIndex]"
                                $check = $checkData[$checkIndex]
                                $checkStatus = Read-Field $check 'status' $checkPath string
                                if ($checkStatus -cnotin $roadmapStates.Keys) {
                                    throw "Unknown roadmap check status in $checkPath."
                                }
                                [pscustomobject]@{
                                    Label = Read-Field $check 'label' $checkPath string
                                    Status = $checkStatus
                                    MapLabel = if ($check.Contains('mapLabel')) {
                                        Read-Field $check 'mapLabel' $checkPath string
                                    }
                                }
                            }
                        }
                    )
                    $tile = [pscustomobject]@{
                        Id = $id
                        Label = Read-Field $item 'label' $path string
                        Status = $status
                        Evidence = Read-Field $item 'evidence' $path string
                        DoneWhen = Read-Field $item 'doneWhen' $path string
                        Checks = $checks
                    }
                    $roadmapById.Add($id, $tile)
                    $tile
                }
            )
            [pscustomobject]@{ Label = $trackName; Tiles = $tiles }
        }
    }
)

$current = Read-Field $data 'current' '$' object
$revision = Read-Field $current 'revision' 'current' string
if ($revision -cnotmatch '\A[0-9a-f]{7,40}\z') {
    throw 'Current revision must be a lowercase hexadecimal Git identifier.'
}
$hardware = Encode-Html (Read-Field $current 'hardware' 'current' string)
$fps = Format-Number (Read-Field $current 'fps' 'current' positive) '0.00'
$timings = Read-Field $current 'frameMs' 'current' object
$mean = Format-Number (Read-Field $timings 'mean' 'current.frameMs' positive)
$median = Read-Field $timings 'median' 'current.frameMs' positive
$p95 = Read-Field $timings 'p95' 'current.frameMs' positive
if ($p95 -lt $median) {
    throw 'Current p95 must be at least the median.'
}
$median = Format-Number $median
$p95 = Format-Number $p95
$intervals = Read-Field $current 'sampleIntervals' 'current' count
if ($intervals -lt 1) {
    throw 'Current sampleIntervals must be at least one.'
}
$seconds = Format-Number (Read-Field $current 'selectionSeconds' 'current' positive)
$minutes = Format-Number (Read-Field $current 'guardedMinutes' 'current' positive)
$errorCount = Read-Field $current 'nvidiaErrorCount' 'current' count
$headroom = Format-Number (Read-Field $current 'commitHeadroomGiBNearEnd' 'current' positive)

$milestones = Read-Field $data 'milestones' '$' array
$milestoneRows = for ($index = 0; $index -lt $milestones.Count; $index++) {
    $item = $milestones[$index]
    $path = "milestones[$index]"
    $label = Encode-Html (Read-Field $item 'label' $path string)
    $status = Read-Field $item 'status' $path string
    $detail = Encode-Html (Read-Field $item 'detail' $path string)
    if ($status -cnotin @('Verified', 'Partial', 'Unverified', 'Pending')) {
        throw "Unknown status in $path."
    }
    "        <tr><th scope='row'>$label</th><td>$status</td><td>$detail</td></tr>"
}

$earlierRuns = Read-Field $data 'earlierRuns' '$' array
$earlierRows = for ($index = 0; $index -lt $earlierRuns.Count; $index++) {
    $item = $earlierRuns[$index]
    $path = "earlierRuns[$index]"
    $label = Encode-Html (Read-Field $item 'label' $path string)
    $earlierFps = Format-Number (Read-Field $item 'fps' $path positive) '0.00'
    $earlierMedian = Read-Field $item 'medianMs' $path positive
    $earlierP95 = Read-Field $item 'p95Ms' $path positive
    $count = Read-Field $item 'intervals' $path count
    if ($earlierP95 -lt $earlierMedian -or $count -lt 1) {
        throw "Invalid timing sample in $path."
    }
    $earlierMedian = Format-Number $earlierMedian
    $earlierP95 = Format-Number $earlierP95
    $outcome = Encode-Html (Read-Field $item 'outcome' $path string)
    "        <tr><th scope='row'>$label</th><td>$earlierFps</td><td>$earlierMedian</td><td>$earlierP95</td><td>$count</td><td>$outcome</td></tr>"
}

$registry = Read-Field $data 'registry' '$' object
$registryRevision = Read-Field $registry 'revision' 'registry' string
if ($registryRevision -cnotmatch '\A[0-9a-f]{7,40}\z') {
    throw 'Registry revision must be a lowercase hexadecimal Git identifier.'
}
$groups = Read-Field $registry 'entries' 'registry' array
$groupNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$registryTotal = 0
$registryRows = for ($index = 0; $index -lt $groups.Count; $index++) {
    $item = $groups[$index]
    $path = "registry.entries[$index]"
    $name = Read-Field $item 'name' $path string
    if (-not $groupNames.Add($name)) {
        throw "Duplicate group in $path."
    }
    $count = Read-Field $item 'count' $path count
    $registryTotal += $count
    "        <tr><th scope='row'>$(Encode-Html $name)</th><td>$count</td></tr>"
}

$opcodePath = 'crates/victory-shader/src/gfx10/opcodes.rs'
$decoderPath = 'crates/victory-shader/src/gfx10/mod.rs'
$probePath = 'crates/victory-shader/examples/gfx10-catalogue.rs'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $catalogue = @(cargo run --quiet --locked --package victory-shader --example gfx10-catalogue)
    if ($LASTEXITCODE -ne 0 -or $catalogue.Count -eq 0) {
        throw 'The GFX10 decoder catalogue probe failed.'
    }
} finally {
    Pop-Location
}
$byFamily = [ordered]@{}
foreach ($line in $catalogue) {
    if ($line -cnotmatch '\A(alu|memory)\t([A-Z0-9]+(?: in VOP3)?)\t(0x[0-9a-f]{3})\t([a-z0-9_]+|-)\z') {
        throw "Unexpected GFX10 probe output: $line"
    }
    $panel, $family, $opcode, $name = $Matches[1], $Matches[2], $Matches[3], $Matches[4]
    if (-not $byFamily.Contains($family)) {
        $byFamily[$family] = [ordered]@{
            name = $family
            count = 0
            slotCount = 0
            panel = $panel
            codes = [Collections.Generic.List[int]]::new()
            opcodes = [Collections.Generic.List[object]]::new()
            lastOpcode = ''
        }
    }
    $group = $byFamily[$family]
    if ($group['panel'] -cne $panel -or [string]::CompareOrdinal($opcode, $group['lastOpcode']) -le 0) {
        throw "Unexpected GFX10 opcode order or panel for $family at $opcode."
    }
    if ($name -cne '-') {
        $group['codes'].Add($group['slotCount'])
        $group['opcodes'].Add([ordered]@{ opcode = $opcode; name = $name })
        $group['count']++
    }
    $group['lastOpcode'] = $opcode
    $group['slotCount']++
}
$shaderGroups = @($byFamily.Values)
$shaderTotal = ($shaderGroups | ForEach-Object { $_['count'] } | Measure-Object -Sum).Sum
$shaderSlots = ($shaderGroups | ForEach-Object { $_['slotCount'] } | Measure-Object -Sum).Sum
$shaderPanels = @{}
foreach ($panel in @('alu', 'memory')) {
    $families = @($shaderGroups | Where-Object { $_['panel'] -eq $panel })
    $named = ($families | ForEach-Object { $_['count'] } | Measure-Object -Sum).Sum
    $slots = ($families | ForEach-Object { $_['slotCount'] } | Measure-Object -Sum).Sum
    $shaderPanels[$panel] = "$named/$slots"
}
$data['shaderCatalogue'] = [ordered]@{
    source = $opcodePath
    decoder = $decoderPath
    probe = $probePath
    total = $shaderTotal
    slotCount = $shaderSlots
    families = @($shaderGroups | ForEach-Object {
        [ordered]@{
            name = $_['name']; count = $_['count']; slotCount = $_['slotCount']; panel = $_['panel']
            opcodes = $_['opcodes'].ToArray()
        }
    })
}

$shaderDetails = foreach ($group in $shaderGroups) {
    $family = Encode-Html $group['name']
    $opcodeList = foreach ($opcodeEntry in $group['opcodes']) {
        "            <li><code>$($opcodeEntry['opcode']) $($opcodeEntry['name'])</code></li>"
    }
    @"
      <details>
        <summary>$family · $($group['count'])/$($group['slotCount']) named</summary>
        <ul class="opcode-list">
$($opcodeList -join [Environment]::NewLine)
        </ul>
      </details>
"@
}

. (Join-Path $PSScriptRoot 'StatusMap.ps1')
$mapTasks = @{ VOP3 = 'shader-translation'; SMEM = 'smem'; pipelines = 'd3d12-pipelines' }
$mapWork = @{}
foreach ($key in $mapTasks.Keys) {
    $tile = $null
    if ($roadmapById.TryGetValue($mapTasks[$key], [ref]$tile)) {
        $mapChecks = @($tile.Checks | Where-Object { $_.MapLabel -and ($key -ceq 'pipelines' -or $_.Status -cne 'Verified') })
        if ($mapChecks.Count) {
            $mapWork[$key] = [pscustomobject]@{
                Label = $tile.Label
                Anchor = "task-$($tile.Id)"
                Checks = $mapChecks
            }
        }
    }
}
$sourceMap = New-LoamStatusMap -Groups $groups -ShaderGroups $shaderGroups
$statusMap = $sourceMap
$statusAlt = "Loam status map with $registryTotal resolver entries and $shaderTotal named GFX10 opcode slots out of $shaderSlots"
if ($mapWork.Count) {
    $statusMap = New-LoamStatusMap -Groups $groups -ShaderGroups $shaderGroups -WorkItems $mapWork
    $statusAlt += '. Selected tiles show translation checks and RTX pipeline status, with details below.'
}
$roadmapHtml = ''
if ($roadmapTracks.Count) {
    $sections = foreach ($track in $roadmapTracks) {
        $cards = foreach ($tile in $track.Tiles) {
            $checkDetails = if ($tile.Checks.Count) {
                $items = foreach ($check in $tile.Checks) {
                    "              <li>$(Encode-Html $check.Label) <span class='task-state'>($($check.Status))</span></li>"
                }
                @"
          <details>
            <summary>Checks</summary>
            <ul>
$($items -join [Environment]::NewLine)
            </ul>
          </details>
"@
            }
            @"
        <article id="task-$($tile.Id)" class="task">
          <h4>$(Encode-Html $tile.Label)</h4>
          <p class="task-state">$($tile.Status)</p>
          <p>$(Encode-Html $tile.Evidence)</p>
          <p><strong>Completion check.</strong> $(Encode-Html $tile.DoneWhen)</p>
$checkDetails
        </article>
"@
        }
        @"
      <h3>$(Encode-Html $track.Label)</h3>
      <div class="task-grid">
$($cards -join [Environment]::NewLine)
      </div>
"@
    }
    $roadmapHtml = @"
  <section aria-labelledby="roadmap-details">
    <h2 id="roadmap-details">Playability details</h2>
    <p>The target is sustained offline play at $targetFps FPS ($targetMs ms per frame) on the $hardware.</p>
$($sections -join [Environment]::NewLine)
  </section>
"@
}

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$projectName progress</title>
  <style>
    :root {
      color-scheme: light dark;
      --paper: #f6f7f3;
      --surface: #fff;
      --ink: #23312d;
      --muted: #52635b;
      --line: #d9e2d9;
      --accent: #176044;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --paper: #191e1b;
        --surface: #202723;
        --ink: #ebf2ec;
        --muted: #b0bfb5;
        --line: #41534a;
        --accent: #90dbb5;
      }
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--paper); color: var(--ink); font: 1rem/1.55 system-ui, sans-serif; }
    main { max-width: 62rem; margin: auto; padding: 3rem clamp(1rem, 4vw, 2.5rem); }
    h1, h2 { line-height: 1.15; letter-spacing: -.025em; }
    h1 { margin: 0; font-size: clamp(2.25rem, 7vw, 3.5rem); }
    h2 { margin: 0 0 .75rem; font-size: 1.45rem; }
    p { margin: 0 0 1rem; }
    header { padding-bottom: 1.25rem; border-bottom: 1px solid var(--line); }
    header p { margin-top: .65rem; color: var(--muted); }
    a { color: var(--accent); text-underline-offset: .18em; }
    nav { display: flex; flex-wrap: wrap; gap: .35rem 1.1rem; }
    section { margin-top: 2rem; }
    .table { overflow-x: auto; background: var(--surface); border: 1px solid var(--line); }
    table { width: 100%; min-width: 34rem; border-collapse: collapse; }
    th, td { padding: .65rem .85rem; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    thead { color: var(--muted); font-size: .87rem; }
    tbody tr:last-child > * { border-bottom: 0; }
    td { font-variant-numeric: tabular-nums; }
    code { font-size: .95em; }
    .status-map { display: block; width: 100%; height: auto; }
    .task-grid { display: grid; grid-template-columns: repeat(auto-fit,minmax(min(100%,21rem),1fr)); gap: .7rem; }
    .task { padding: .8rem 1rem; background: var(--surface); border: 1px solid var(--line); }
    .task:target { outline: 2px solid var(--accent); }
    .task h4 { margin: 0; }
    .task-state { color: var(--muted); font-size: .87rem; font-weight: 600; }
    .task p:last-child { margin-bottom: 0; }
    details { border-bottom: 1px solid var(--line); }
    summary { cursor: pointer; padding: .45rem 0; }
    .opcode-list { columns: 18rem; list-style: none; margin: 0 0 .75rem; padding: 0; }
    .opcode-list li { break-inside: avoid; overflow-wrap: anywhere; }
  </style>
</head>
<body>
<main>
  <header>
    <h1>$projectName progress</h1>
    <p>Opening prison sequence on the $hardware.</p>
    <nav aria-label="Project links">
      <a href="#status-map">Status</a>
      <a href="#shader-opcodes">Shader reference</a>
      <a href="$repositoryUrl">Source repository</a>
      <a href="$changelogUrl">Changelog</a>
      <a href="progress.json">Raw JSON</a>
      <a href="fps.svg">FPS badge</a>
    </nav>
  </header>
  <section aria-labelledby="status-map">
    <h2 id="status-map">Source status map</h2>
    <p><a href="status-map.svg"><img class="status-map" src="status-map.svg" alt="$statusAlt"></a></p>
  </section>
$roadmapHtml

  <section aria-labelledby="shader-opcodes">
    <h2 id="shader-opcodes">GFX10 shader opcodes</h2>
    <p>Green cells mark opcodes with names returned by Loam's decoder. Gray cells include reserved values. The VOP3 groups include the 64-bit encodings of VOPC, VOP2, and VOP1.</p>
    <p>Separate DXIL output tests cover <a href="$repositoryUrl/blob/main/crates/victory-shader/src/emit/valu_tests.rs"><code>v_lerp_u8</code></a> and <a href="$repositoryUrl/blob/main/crates/victory-shader/src/emit/mod.rs">representative SMEM scalar buffer loads</a>. The map measures instruction recognition.</p>
$($shaderDetails -join [Environment]::NewLine)
  </section>

  <section aria-labelledby="benchmark">
    <h2 id="benchmark">Barred-window reference benchmark</h2>
    <p><img src="fps.svg" alt="$projectName measured $fps FPS"></p>
    <p>$fps FPS from $intervals logged frame intervals within a ${seconds}-second selection at revision <code>$revision</code>. FPS is calculated from the mean measured frame interval.</p>
    <div class="table" role="region" aria-label="Barred-window results" tabindex="0">
      <table>
        <thead><tr><th scope="col">Mean frame time</th><th scope="col">Median</th><th scope="col">95th percentile</th><th scope="col">Target</th></tr></thead>
        <tbody><tr><td>$mean ms</td><td>$median ms</td><td>$p95 ms</td><td>$targetFps FPS ($targetMs ms)</td></tr></tbody>
      </table>
    </div>
  </section>
  <section aria-labelledby="milestones">
    <h2 id="milestones">Milestones</h2>
    <div class="table" role="region" aria-label="Milestones" tabindex="0">
      <table>
        <thead><tr><th scope="col">Milestone</th><th scope="col">Status</th><th scope="col">Observed behavior</th></tr></thead>
        <tbody>
$($milestoneRows -join [Environment]::NewLine)
          <tr><th scope="row">$fps FPS benchmark run</th><td>Verified</td><td>Reached the ${minutes}-minute limit. Recorded $errorCount new NVIDIA driver errors and about $headroom GiB of Windows commit headroom near the end.</td></tr>
        </tbody>
      </table>
    </div>
  </section>
  <section aria-labelledby="earlier">
    <h2 id="earlier">Other runs</h2>
    <p>Camera views and runtime settings varied across runs, so these measurements cannot isolate the effect of one change.</p>
    <div class="table" role="region" aria-label="Other frame timings" tabindex="0">
      <table>
        <thead><tr><th scope="col">Run</th><th scope="col">FPS</th><th scope="col">Median (ms)</th><th scope="col">P95 (ms)</th><th scope="col">Intervals</th><th scope="col">Observation</th></tr></thead>
        <tbody>
$($earlierRows -join [Environment]::NewLine)
        </tbody>
      </table>
    </div>
  </section>
  <section aria-labelledby="registry">
    <h2 id="registry">Windows resolver registry</h2>
    <p>$registryTotal registered entries across $($groups.Count) groups at source revision <code>$registryRevision</code>. A registration records that Loam can resolve an import by name or ordinal. Behavior is verified separately.</p>
    <div class="table" role="region" aria-label="Resolver registry counts" tabindex="0">
      <table>
        <thead><tr><th scope="col">Group</th><th scope="col">Registered entries</th></tr></thead>
        <tbody>
$($registryRows -join [Environment]::NewLine)
        </tbody>
      </table>
    </div>
  </section>
</main>
</body>
</html>
"@

function New-ProgressBadge([string]$Label, [string]$Value, [int]$LabelWidth, [int]$ValueWidth, [string]$Color) {
    $width = $LabelWidth + $ValueWidth
    $title = Encode-Html "$Label $Value"
    $badgeLabel = Encode-Html $Label
    $badgeValue = Encode-Html $Value
    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="20" viewBox="0 0 $width 20" role="img" aria-labelledby="title">
  <title id="title">$title</title>
  <rect width="$LabelWidth" height="20" fill="#555"/>
  <rect x="$LabelWidth" width="$ValueWidth" height="20" fill="$Color"/>
  <g fill="#fff" text-anchor="middle" font-family="Verdana, DejaVu Sans, sans-serif" font-size="11" font-weight="600">
    <text x="$([int]($LabelWidth / 2))" y="14">$badgeLabel</text>
    <text x="$([int]($LabelWidth + $ValueWidth / 2))" y="14">$badgeValue</text>
  </g>
</svg>
"@
}

$badge = New-ProgressBadge 'opening scene benchmark' "$fps FPS" 165 74 '#2f81f7'
$registryBadge = New-ProgressBadge 'libraries*' "$registryTotal entries" 75 75 '#dfb317'
$shaderBadge = New-ProgressBadge 'GFX10 opcode names' "$shaderTotal/$shaderSlots" 131 76 '#4c1'
$aluBadge = New-ProgressBadge 'GFX10 ALU slots' $shaderPanels['alu'] 112 70 '#4c1'
$memoryBadge = New-ProgressBadge 'GFX10 memory and export' $shaderPanels['memory'] 165 70 '#4c1'
$targetBadge = New-ProgressBadge 'gameplay target' "$targetFps FPS" 108 58 '#345986'

$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if ((Join-Path $outputPath 'progress.json') -eq $dataFile) {
    throw 'Choose an output directory outside the source data directory.'
}
[void][IO.Directory]::CreateDirectory($outputPath)
[IO.File]::WriteAllText((Join-Path $outputPath 'progress.html'), $html)
[IO.File]::WriteAllText((Join-Path $outputPath 'index.html'), $html)
[IO.File]::WriteAllText((Join-Path $outputPath 'progress.json'), (ConvertTo-Json -InputObject $data -Depth 12) + [Environment]::NewLine)
[IO.File]::WriteAllText((Join-Path $outputPath 'fps.svg'), $badge)
[IO.File]::WriteAllText((Join-Path $outputPath 'registry.svg'), $registryBadge)
[IO.File]::WriteAllText((Join-Path $outputPath 'gfx10.svg'), $shaderBadge)
[IO.File]::WriteAllText((Join-Path $outputPath 'gfx10-alu.svg'), $aluBadge)
[IO.File]::WriteAllText((Join-Path $outputPath 'gfx10-memory.svg'), $memoryBadge)
[IO.File]::WriteAllText((Join-Path $outputPath 'status-map.svg'), $statusMap)
[IO.File]::WriteAllText((Join-Path $outputPath 'source-map.svg'), $sourceMap)
[IO.File]::WriteAllText((Join-Path $outputPath 'fps-target.svg'), $targetBadge)
foreach ($id in @('mission-completion', 'windows-memory')) {
    $tile = $null
    $trackBadge = if ($roadmapById.TryGetValue($id, [ref]$tile)) {
        New-ProgressBadge $tile.Label $tile.Status 137 74 $roadmapStates[$tile.Status]
    } else {
        $label = if ($id -eq 'mission-completion') { 'Complete the mission' } else { 'Windows memory' }
        New-ProgressBadge $label 'No status' 137 74 $roadmapStates.Pending
    }
    [IO.File]::WriteAllText((Join-Path $outputPath "$id.svg"), $trackBadge)
}
