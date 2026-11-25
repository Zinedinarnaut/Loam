#Requires -Version 7.0
<#
.SYNOPSIS
Builds the public Loam progress report from a reviewed JSON snapshot.
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
  </style>
</head>
<body>
<main>
  <header>
    <h1>$projectName progress</h1>
    <p>Opening prison sequence on the $hardware, tested at revision <code>$revision</code>.</p>
    <nav aria-label="Project links">
      <a href="$repositoryUrl">Source repository</a>
      <a href="$changelogUrl">Changelog</a>
      <a href="progress.json">Raw JSON</a>
      <a href="fps.svg">FPS badge</a>
    </nav>
  </header>
  <section aria-labelledby="benchmark">
    <h2 id="benchmark">Barred-window benchmark</h2>
    <p><img src="fps.svg" width="150" height="24" alt="$projectName measured $fps FPS"></p>
    <p>$fps FPS from $intervals logged frame intervals within a ${seconds}-second selection. FPS is calculated from the mean measured frame interval.</p>
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
          <tr><th scope="row">Guarded run</th><td>Verified</td><td>Reached the ${minutes}-minute limit. Recorded $errorCount new NVIDIA driver errors and about $headroom GiB of Windows commit headroom near the end.</td></tr>
        </tbody>
      </table>
    </div>
  </section>
  <section aria-labelledby="earlier">
    <h2 id="earlier">Earlier runs</h2>
    <p>Camera views and runtime settings varied across runs, so these measurements cannot isolate the effect of one change.</p>
    <div class="table" role="region" aria-label="Earlier frame timings" tabindex="0">
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

$badgeName = Encode-Html "Measured $fps FPS"
$badge = @"
<svg xmlns="http://www.w3.org/2000/svg" width="150" height="24" viewBox="0 0 150 24" role="img" aria-labelledby="title">
  <title id="title">$badgeName</title>
  <rect width="150" height="24" rx="3" fill="#263b33"/>
  <rect x="77" width="73" height="24" rx="3" fill="#176044"/>
  <g fill="#fff" text-anchor="middle" font-family="system-ui, sans-serif" font-size="11">
    <text x="39" y="16">Measured</text>
    <text x="114" y="16">$fps FPS</text>
  </g>
</svg>
"@

$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if ((Join-Path $outputPath 'progress.json') -eq $dataFile) {
    throw 'Choose an output directory outside the source data directory.'
}
[void][IO.Directory]::CreateDirectory($outputPath)
[IO.File]::WriteAllText((Join-Path $outputPath 'progress.html'), $html)
[IO.File]::WriteAllText((Join-Path $outputPath 'index.html'), $html)
[IO.File]::WriteAllText((Join-Path $outputPath 'progress.json'), $source)
[IO.File]::WriteAllText((Join-Path $outputPath 'fps.svg'), $badge)
