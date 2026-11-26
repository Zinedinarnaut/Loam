#Requires -Version 7.0

function New-LoamStatusMap {
    <#
    .SYNOPSIS
    Renders resolver registrations and named opcode slots as two-color treemaps.
    .PARAMETER Groups
    Resolver dictionary entries with name and count.
    .PARAMETER ShaderGroups
    Opcode dictionaries with name, count, slotCount, a panel (alu or memory),
    and the zero-based codes of named slots within that family.
    .PARAMETER WorkItems
    Optional captions for shader tile names and the missing pipelines group.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Groups,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$ShaderGroups,

        [Collections.IDictionary]$WorkItems = @{}
    )

    $content = [Collections.Generic.List[string]]::new()

    function ConvertTo-MapLabel([string]$Value) {
        return [Net.WebUtility]::HtmlEncode([Xml.XmlConvert]::VerifyXmlChars($Value))
    }

    function Add-ShaderWork($Work, [int]$X, [int]$Y, [int]$W, [int]$H) {
        $step = 14
        $height = 18 + $step * $Work.Lines.Count
        $top = $Y + $H - $height - 3
        $left = $X + 7
        $anchor = ConvertTo-MapLabel $Work.Anchor
        $content.Add("    <a href='progress.html#$anchor' class='shader-work'>")
        $content.Add("      <rect x='$($X + 3)' y='$top' width='$($W - 6)' height='$height' class='group' fill-opacity='.92'/>")
        $content.Add("      <text x='$left' y='$($top + 13)' class='group-label'>Mission DXIL checks</text>")
        for ($index = 0; $index -lt $Work.Lines.Count; $index++) {
            $label = ConvertTo-MapLabel $Work.Lines[$index]
            $baseline = $top + 13 + ($index + 1) * $step
            $content.Add("      <text x='$left' y='$baseline' class='group-label'>$label</text>")
        }
        $content.Add('    </a>')
    }

    function Add-PipelineWork($Work, [int]$Top) {
        $name = ConvertTo-MapLabel $Work.Label
        $anchor = ConvertTo-MapLabel $Work.Anchor
        $content.Add("  <text x='4' y='$($Top + 14)' class='section-label'>$name</text>")
        $content.Add("  <a href='progress.html#$anchor' class='pipeline-work'>")
        for ($index = 0; $index -lt $Work.Lines.Count; $index++) {
            $left = 4 + [int][Math]::Floor(992 * $index / $Work.Lines.Count)
            $right = 4 + [int][Math]::Floor(992 * ($index + 1) / $Work.Lines.Count)
            $label = ConvertTo-MapLabel $Work.Lines[$index]
            $content.Add("    <rect x='$left' y='$($Top + 20)' width='$($right - $left)' height='32' class='group'/>")
            $content.Add("    <rect x='$($left + 6)' y='$($Top + 30)' width='11' height='11' fill='#6e7681'/>")
            $content.Add("    <text x='$($left + 23)' y='$($Top + 40)' class='group-label'>$label</text>")
            $content.Add("    <rect x='$left' y='$($Top + 20)' width='$($right - $left)' height='32' class='group-border'/>")
        }
        $content.Add('  </a>')
    }

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
        if ($isShader -and $WorkItems.Contains($Entry.Name)) {
            Add-ShaderWork $WorkItems[$Entry.Name] $X $Y $W $H
        }
        $content.Add("    <rect x='$X' y='$Y' width='$W' height='$H' class='group-border'/>")
        $content.Add('  </g>')
    }

    function Add-Treemap([object[]]$Entries, [int]$X, [int]$Y, [int]$W, [int]$H) {
        if ($Entries.Count -eq 1) {
            Add-MapGroup $Entries[0] $X $Y $W $H
            return
        }
        if ($Entries.Count -eq 0) {
            return
        }

        # Divide the rectangle in proportion to the groups' weights.
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
            # A narrow strip can hide the last label. Try the other axis
            # when it has room for a full line of text.
            $labelWidth = 5 + $second[0].Name.Length * 6.6
            $remaining = 1 - $fraction
            $splitWidth = $W * $remaining -ge $labelWidth -or $H * $remaining -lt 16
        }
        if ($splitWidth) {
            $firstWidth = [int][Math]::Clamp([Math]::Round($W * $fraction), 1, $W - 1)
            Add-Treemap $first $X $Y $firstWidth $H
            Add-Treemap $second ($X + $firstWidth) $Y ($W - $firstWidth) $H
        } else {
            $firstHeight = [int][Math]::Clamp([Math]::Round($H * $fraction), 1, $H - 1)
            Add-Treemap $first $X $Y $W $firstHeight
            Add-Treemap $second $X ($Y + $firstHeight) $W ($H - $firstHeight)
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

    $legendY = 728
    $description = 'Library tiles show resolver registrations. Shader tiles show decoder recognition by encoding family, including the VOP3 forms of VOPC, VOP2, and VOP1.'
    if ($WorkItems.Contains('pipelines')) {
        Add-PipelineWork $WorkItems['pipelines'] 721
        $legendY = 785
    }
    if ($WorkItems.Count) {
        $description += ' Selected tiles show remaining translation and pipeline work.'
    }
    $height = $legendY + 20

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="$height" viewBox="0 0 1000 $height" role="img" aria-labelledby="title description">
  <title id="title">Loam system libraries and GFX10 opcodes</title>
  <desc id="description">$description</desc>
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
  <rect width="1000" height="$height" fill="#0d1117"/>
$($content -join [Environment]::NewLine)
  <rect x="4" y="$legendY" width="11" height="11" class="named"/>
  <text x="20" y="$($legendY + 10)" class="legend">Named opcode slot</text>
  <rect x="147" y="$legendY" width="11" height="11" class="unnamed"/>
  <text x="163" y="$($legendY + 10)" class="legend">Unnamed opcode slot, including reserved encodings</text>
</svg>
"@
}
