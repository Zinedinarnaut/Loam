#Requires -Version 7.0

function ConvertTo-MapLabel([string]$Value) {
    return [Net.WebUtility]::HtmlEncode([Xml.XmlConvert]::VerifyXmlChars($Value))
}

function Get-LoamTreemap([object[]]$Entries, [int]$X, [int]$Y, [int]$W, [int]$H) {
    if ($Entries.Count -eq 0) { return }
    if ($Entries.Count -eq 1) {
        [pscustomobject]@{ Entry = $Entries[0]; X = $X; Y = $Y; W = $W; H = $H }
        return
    }

    # Divide the rectangle in proportion to the entries' weights.
    $weight = ($Entries | Measure-Object -Property LayoutWeight -Sum).Sum
    $splitWeight = 0
    $splitCount = 0
    while ($splitCount -lt ($Entries.Count - 1)) {
        $nextWeight = $splitWeight + $Entries[$splitCount].LayoutWeight
        if ($splitCount -gt 0 -and [Math]::Abs($nextWeight - $weight / 2) -gt
            [Math]::Abs($splitWeight - $weight / 2)) {
            break
        }
        $splitWeight = $nextWeight
        $splitCount++
    }
    $first = $Entries[0..($splitCount - 1)]
    $second = $Entries[$splitCount..($Entries.Count - 1)]
    $fraction = $splitWeight / $weight
    $splitWidth = $W -ge $H
    if ($splitWidth -and $second.Count -eq 1) {
        $labelWidth = 5 + $second[0].Name.Length * 6.6
        $remaining = 1 - $fraction
        $splitWidth = $W * $remaining -ge $labelWidth -or $H * $remaining -lt 16
    }
    if ($splitWidth) {
        $firstWidth = [int][Math]::Clamp([Math]::Round($W * $fraction), 1, $W - 1)
        Get-LoamTreemap $first $X $Y $firstWidth $H
        Get-LoamTreemap $second ($X + $firstWidth) $Y ($W - $firstWidth) $H
    } else {
        $firstHeight = [int][Math]::Clamp([Math]::Round($H * $fraction), 1, $H - 1)
        Get-LoamTreemap $first $X $Y $W $firstHeight
        Get-LoamTreemap $second $X ($Y + $firstHeight) $W ($H - $firstHeight)
    }
}

function New-LoamRoadmap {
    param([object[]]$Tracks, [System.Collections.IDictionary]$States)

    $content = [Collections.Generic.List[string]]::new()
    function Add-Track($Track, [int]$X, [int]$Y, [int]$W, [int]$H) {
        $heading = ConvertTo-MapLabel $Track.Label
        $content.Add("  <text x='$X' y='$($Y + 15)' class='section-label'>$heading</text>")
        $entries = @(foreach ($tile in $Track.Tiles) {
            [pscustomobject]@{ Name = $tile.Label; LayoutWeight = [Math]::Max(1, $tile.Checks.Count); Tile = $tile }
        })
        foreach ($slot in (Get-LoamTreemap $entries $X ($Y + 21) $W $H)) {
            $tile = $slot.Entry.Tile
            $name = ConvertTo-MapLabel $tile.Label
            $status = $tile.Status
            $state = $States[$status]
            $color = if ($tile.Checks.Count) { $state.Surface } else { $state.Badge }
            $x0 = $slot.X
            $y0 = $slot.Y
            $w0 = $slot.W
            $h0 = $slot.H
            $content.Add("  <a href='progress.html#task-$($tile.Id)' aria-label='$name ($status)'>")
            $content.Add("    <title>$name ($status)</title>")
            $content.Add("    <rect x='$x0' y='$y0' width='$w0' height='$h0' fill='$color' class='tile'/>")
            if ($tile.Checks.Count -and $h0 -gt 25) {
                $checks = @(foreach ($check in $tile.Checks) {
                    [pscustomobject]@{ Name = ''; LayoutWeight = 1; Check = $check }
                })
                foreach ($cell in (Get-LoamTreemap $checks ($x0 + 2) ($y0 + 20) ($w0 - 4) ($h0 - 22))) {
                    $check = $cell.Entry.Check
                    $checkLabel = ConvertTo-MapLabel $check.Label
                    $checkColor = $States[$check.Status].Badge
                    $content.Add("    <rect x='$($cell.X)' y='$($cell.Y)' width='$($cell.W)' height='$($cell.H)' fill='$checkColor' class='check'><title>$checkLabel ($($check.Status))</title></rect>")
                }
            }
            $font = [int][Math]::Min(15, [Math]::Floor(($w0 - 10) / ($tile.Label.Length * 0.64)))
            $content.Add("    <text x='$($x0 + 5)' y='$($y0 + 15)' class='tile-label' font-size='$font'>$name</text>")
            $content.Add('  </a>')
        }
    }

    $top = 6
    for ($index = 0; $index -lt $Tracks.Count; $index++) {
        $track = $Tracks[$index]
        if (!$track.Wide -and $index + 1 -lt $Tracks.Count -and !$Tracks[$index + 1].Wide) {
            Add-Track $track 4 $top 490 166
            Add-Track $Tracks[$index + 1] 505 $top 491 166
            $index++
            $top += 203
        } else {
            Add-Track $track 4 $top 992 79
            $top += 116
        }
    }

    $legendX = 4
    foreach ($status in $States.Keys) {
        $content.Add("  <rect x='$legendX' y='$top' width='11' height='11' fill='$($States[$status].Badge)'/>")
        $content.Add("  <text x='$($legendX + 16)' y='$($top + 10)' class='legend'>$status</text>")
        $legendX += 96
    }
    $height = $top + 20

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="$height" viewBox="0 0 1000 $height" role="img" aria-labelledby="title description">
  <title id="title">Loam playability status grid</title>
  <desc id="description">Work tiles and individual checks for Loam, colored by status. Tile links lead to evidence and completion checks.</desc>
  <style>
    text { font-family: Arial, sans-serif; fill: #f0f6fc; }
    .section-label { font-size: 16px; }
    .tile-label { stroke: #0d1117; stroke-width: 2; stroke-linejoin: round; paint-order: stroke; }
    .legend { font-size: 12px; }
    .tile, .check { stroke: #0d1117; stroke-width: 1.5; }
    a:hover .tile, a:focus .tile { stroke: #f0f6fc; }
  </style>
  <rect width="1000" height="$height" fill="#0d1117"/>
$($content -join [Environment]::NewLine)
</svg>
"@
}

function New-LoamReferenceMap {
    <#
    .SYNOPSIS
    Renders resolver registrations and named opcode slots as two-color treemaps.
    .PARAMETER Groups
    Resolver dictionary entries with name and count.
    .PARAMETER ShaderGroups
    Opcode dictionaries with name, count, slotCount, a panel (alu or memory),
    and the zero-based codes of named slots within that family.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Groups,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$ShaderGroups
    )

    $content = [Collections.Generic.List[string]]::new()

    $libraries = @(foreach ($entry in $Groups) {
        $name = $entry['name']
        $count = $entry['count']
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or
            ($count -isnot [int] -and $count -isnot [long]) -or $count -lt 0) {
            throw 'A library map entry needs a name and a nonnegative integer count.'
        }
        if ($count -gt 0) {
            [pscustomobject]@{
                Name = $name
                Count = $count
                Weight = $count
                LayoutWeight = $count
                CellClass = 'registry-cell'
            }
        }
    })

    $opcodes = @(foreach ($entry in $ShaderGroups) {
        $name = $entry['name']
        $count = $entry['count']
        $slots = $entry['slotCount']
        $panel = $entry['panel']
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or
            ($count -isnot [int] -and $count -isnot [long]) -or
            ($slots -isnot [int] -and $slots -isnot [long]) -or $slots -le 0 -or $count -lt 0 -or
            $count -gt $slots -or $panel -cnotin @('alu', 'memory')) {
            throw "Invalid shader map entry '$name'."
        }

        $named = [Collections.Generic.HashSet[int]]::new()
        foreach ($code in $entry['codes']) {
            if (($code -isnot [ValueType]) -or
                $code -lt 0 -or $code -ge $slots -or $code -ne [int]$code -or -not $named.Add([int]$code)) {
                throw "Invalid or duplicate named slot in opcode family $name."
            }
        }
        if ($named.Count -ne $count) {
            throw "The names in opcode family $name do not match its published count."
        }
        [pscustomobject]@{
            Name = $name
            Count = $count
            Weight = $slots
            # Very small families need enough area for the label.
            LayoutWeight = [Math]::Max(28, $slots)
            Named = $named
            Panel = $panel
            CellClass = 'shader-cell'
        }
    })

    function Add-MapGroup([object]$Entry, [int]$X, [int]$Y, [int]$W, [int]$H) {
        $isShader = $Entry.CellClass -eq 'shader-cell'
        # Fit the largest usable square pitch within the weighted rectangle.
        $bestPitch = 0
        $columns = 1
        for ($candidate = 1; $candidate -le [Math]::Min($Entry.Weight, $W); $candidate++) {
            $rows = [Math]::Ceiling($Entry.Weight / $candidate)
            $pitch = [Math]::Min([double]$W / $candidate, [double]$H / $rows)
            if ($pitch -gt $bestPitch) {
                $bestPitch = $pitch
                $columns = $candidate
            }
        }
        if ($bestPitch -le 0) {
            throw "The status map has no space for $($Entry.Name)."
        }
        $name = ConvertTo-MapLabel $Entry.Name
        $summary = if ($isShader) { "$($Entry.Count)/$($Entry.Weight) named opcode slots" } else { "$($Entry.Count) registrations" }
        $content.Add("  <g><title>$name ($summary)</title>")
        $content.Add("    <rect x='$X' y='$Y' width='$W' height='$H' class='group'/>")
        $cellBorder = [Math]::Min(0.7, $bestPitch / 5)
        $side = ($bestPitch - $cellBorder).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
        for ($index = 0; $index -lt $Entry.Weight; $index++) {
            $cellX = ($X + ($index % $columns) * $bestPitch).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
            $cellY = ($Y + [Math]::Floor($index / $columns) * $bestPitch).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
            $class = $Entry.CellClass
            if ($isShader) {
                $class += if ($Entry.Named.Contains($index)) { ' named' } else { ' unnamed' }
            }
            $content.Add("    <rect x='$cellX' y='$cellY' width='$side' height='$side' class='$class'/>")
        }

        $maxLabelLength = [int][Math]::Floor(($W - 5) / 6.6)
        if ($maxLabelLength -ge 2 -and $H -ge 13) {
            $label = $Entry.Name
            if ($label.Length -gt $maxLabelLength) {
                $label = $label.Substring(0, $maxLabelLength - 1) + [char]0x2026
            }
            $content.Add("    <text x='$($X + 3)' y='$($Y + 13)' class='group-label'>$(ConvertTo-MapLabel $label)</text>")
        }
        $content.Add("    <rect x='$X' y='$Y' width='$W' height='$H' class='group-border'/>")
        $content.Add('  </g>')
    }

    function Add-Treemap([object[]]$Entries, [int]$X, [int]$Y, [int]$W, [int]$H) {
        foreach ($slot in (Get-LoamTreemap $Entries $X $Y $W $H)) {
            Add-MapGroup $slot.Entry $slot.X $slot.Y $slot.W $slot.H
        }
    }

    function Add-LibrarySection([object[]]$Entries, [string]$Heading, [int]$X, [int]$Top, [int]$W, [int]$H) {
        $total = ($Entries | Measure-Object -Property Count -Sum).Sum
        $content.Add("  <text x='$X' y='$Top' class='section-label'>$($Heading): $([int]$total)</text>")
        Add-Treemap @($Entries | Sort-Object -Property LayoutWeight -Descending -Stable) $X ($Top + 9) $W $H
    }

    function Add-ShaderSection([object[]]$Entries, [string]$Heading, [int]$X, [int]$Top, [int]$W, [int]$H) {
        $totals = @($Entries | Measure-Object -Property Count, Weight -Sum)
        $content.Add("  <text x='$X' y='$Top' class='section-label'>$($Heading): $($totals[0].Sum)/$($totals[1].Sum) named</text>")
        Add-Treemap @($Entries | Sort-Object -Property LayoutWeight -Descending -Stable) $X ($Top + 9) $W $H
    }

    $registrations = ($libraries | Measure-Object -Property Count -Sum).Sum
    $content.Add("  <text x='4' y='17' class='section-label'>System libraries*: $registrations registrations</text>")
    Add-LibrarySection @($libraries | Where-Object Count -GE 20) 'Large system libraries' 4 46 490 195
    Add-LibrarySection @($libraries | Where-Object { $_.Count -ge 5 -and $_.Count -lt 20 }) 'Medium system libraries' 509 46 487 195
    Add-LibrarySection @($libraries | Where-Object Count -LT 5) 'Small system libraries' 4 280 992 106

    Add-ShaderSection @($opcodes | Where-Object Panel -EQ 'alu') 'GFX10 ALU opcodes' 4 426 490 279
    Add-ShaderSection @($opcodes | Where-Object Panel -EQ 'memory') 'GFX10 memory and export opcodes' 509 426 487 279

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="748" viewBox="0 0 1000 748" role="img" aria-labelledby="title description">
  <title id="title">Loam system libraries and GFX10 opcodes</title>
  <desc id="description">Library tiles show resolver registrations. Shader tiles show decoder recognition by encoding family, including the VOP3 forms of VOPC, VOP2, and VOP1.</desc>
  <style>
    text { font-family: Arial, sans-serif; fill: white; stroke: #0d1117; stroke-width: 3; stroke-linejoin: round; paint-order: stroke; }
    .section-label { font-size: 16px; }
    .group-label { font-size: 12px; }
    .legend { font-size: 12px; }
    .group { fill: #161b22; }
    .group-border { fill: none; stroke: #0d1117; stroke-width: 1.5; }
    .registry-cell, .named { fill: #2ea043; }
    .unnamed { fill: #6e7681; }
  </style>
  <rect width="1000" height="748" fill="#0d1117"/>
$($content -join [Environment]::NewLine)
  <rect x="4" y="728" width="11" height="11" class="named"/>
  <text x="20" y="738" class="legend">Named opcode slot</text>
  <rect x="147" y="728" width="11" height="11" class="unnamed"/>
  <text x="163" y="738" class="legend">Unnamed opcode slot, including reserved encodings</text>
</svg>
"@
}
