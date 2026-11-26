#Requires -Version 7.0

function New-LoamStatusMap {
    <#
    .SYNOPSIS
    Returns a standalone SVG from measured progress and audited group counts.
    .PARAMETER Groups
    Objects or dictionaries with a name and integer resolver-entry count.
    .PARAMETER ShaderGroups
    Objects or dictionaries with a name and integer opcode catalogue label count.
    .PARAMETER Milestones
    Objects or dictionaries with a label and a status of Verified, Partial,
    Unverified, or Pending.
    .PARAMETER Fps
    Measured FPS as a decimal display string without a unit.
    .PARAMETER TargetFps
    Target FPS as a decimal display string without a unit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Groups,

        [object[]]$ShaderGroups = @(),

        [object[]]$Milestones = @(),

        [Parameter(Mandatory)]
        [ValidatePattern('\A[0-9]{1,4}(?:\.[0-9]{1,3})?\z')]
        [string]$Fps,

        [Parameter(Mandatory)]
        [ValidatePattern('\A[0-9]{1,4}(?:\.[0-9]{1,3})?\z')]
        [string]$TargetFps
    )

    function Get-MapValue([object]$Entry, [string]$Key) {
        if ($Entry -is [Collections.IDictionary]) {
            return $Entry[$Key]
        }
        if ($null -ne $Entry) {
            $property = $Entry.PSObject.Properties[$Key]
            if ($null -ne $property) {
                return $property.Value
            }
        }
    }

    function Get-MapText([object]$Entry, [string]$Key, [int]$MaxLength) {
        $value = Get-MapValue $Entry $Key
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt $MaxLength) {
            throw "Status map $Key must be a nonempty string of at most $MaxLength characters."
        }
        return [Net.WebUtility]::HtmlEncode([Xml.XmlConvert]::VerifyXmlChars($value))
    }

    # The shared grid gives wide labels and large groups more room while
    # keeping every tile the same size.
    $width = 904
    $edge = 24
    $columnCount = 6
    $gap = 8
    $columnWidth = 136
    $stride = $columnWidth + $gap
    $cardInset = 12
    $cellSize = 8
    $cellStride = 11
    $content = [Collections.Generic.List[string]]::new()

    function Add-TileSection(
        [object[]]$Entries,
        [int]$Top,
        [string]$Heading,
        [string]$Detail,
        [string]$CellClass
    ) {
        $cards = @(foreach ($entry in $Entries) {
            $name = Get-MapText $entry 'name' 72
            $count = Get-MapValue $entry 'count'
            if (($count -isnot [int] -and $count -isnot [long]) -or $count -lt 0 -or $count -gt 2048) {
                throw 'Status map count must be an integer from 0 through 2048.'
            }

            $nameWidth = (Get-MapValue $entry 'name').Length * 8
            $countWidth = ([string]$count).Length * 8
            $labelSpan = [Math]::Ceiling(($nameWidth + $countWidth + 38) / $stride)
            $tilesSpan = [Math]::Ceiling(([Math]::Ceiling($count / 2) * $cellStride + 29) / $stride)
            $span = [int][Math]::Min($columnCount, [Math]::Max($labelSpan, $tilesSpan))
            $cardWidth = $span * $stride - $gap
            $tileColumns = [int][Math]::Floor(($cardWidth - 2 * $cardInset + 3) / $cellStride)
            $tileRows = [int][Math]::Ceiling($count / $tileColumns)

            [pscustomobject]@{
                Name = $name
                Count = $count
                Span = $span
                Width = $cardWidth
                TileColumns = $tileColumns
                Height = [Math]::Max(58, 39 + $tileRows * $cellStride)
            }
        })

        $total = ($cards | Measure-Object -Property Count -Sum).Sum
        if ($total -gt 8192) {
            throw 'Status map sections support up to 8192 tiles.'
        }

        $headingY = $Top + 19
        $detailY = $Top + 39
        $trailingX = $width - $edge
        $content.Add("  <text x='$edge' y='$headingY' class='section-title'>$Heading</text>")
        $content.Add("  <text x='$trailingX' y='$headingY' class='group-total' text-anchor='end'>$total across $($Entries.Count) groups</text>")
        $content.Add("  <text x='$edge' y='$detailY' class='muted'>$Detail</text>")

        $rowTop = $Top + 50
        $cardIndex = 0
        while ($cardIndex -lt $cards.Count) {
            $rowStart = $cardIndex
            $usedColumns = 0
            $rowHeight = 0
            while ($cardIndex -lt $cards.Count -and $usedColumns + $cards[$cardIndex].Span -le $columnCount) {
                $usedColumns += $cards[$cardIndex].Span
                $rowHeight = [Math]::Max($rowHeight, $cards[$cardIndex].Height)
                $cardIndex++
            }

            $cardX = $edge
            for ($index = $rowStart; $index -lt $cardIndex; $index++) {
                $card = $cards[$index]
                $nameX = $cardX + $cardInset
                $countX = $cardX + $card.Width - $cardInset
                $labelY = $rowTop + 21
                $tileTop = $rowTop + 31
                $content.Add("  <g><title>$($card.Name), $($card.Count)</title>")
                $content.Add("    <rect x='$cardX' y='$rowTop' width='$($card.Width)' height='$rowHeight' rx='7' class='card'/>")
                $content.Add("    <text x='$nameX' y='$labelY' class='group-name'>$($card.Name)</text>")
                $content.Add("    <text x='$countX' y='$labelY' class='group-count' text-anchor='end'>$($card.Count)</text>")
                for ($tile = 0; $tile -lt $card.Count; $tile++) {
                    $x = $nameX + ($tile % $card.TileColumns) * $cellStride
                    $y = $tileTop + [int][Math]::Floor($tile / $card.TileColumns) * $cellStride
                    $content.Add("    <rect x='$x' y='$y' width='$cellSize' height='$cellSize' rx='1.5' class='$CellClass'/>")
                }
                $content.Add('  </g>')
                $cardX += $card.Width + $gap
            }
            $rowTop += $rowHeight + $gap
        }

        return $rowTop + 14
    }

    $top = Add-TileSection $Groups 103 'Windows resolver registry' 'One green square represents one registered resolver entry.' 'registry-cell'
    if ($ShaderGroups.Count -gt 0) {
        $top = Add-TileSection $ShaderGroups $top 'Shader opcode catalogue' 'One blue square represents one opcode catalogue label.' 'shader-cell'
    }

    if ($Milestones.Count -gt 0) {
        $headingY = $top + 19
        $content.Add("  <text x='$edge' y='$headingY' class='section-title'>Runtime milestones</text>")
        $top += 30
        $usedColumns = 0
        foreach ($milestone in $Milestones) {
            $label = Get-MapText $milestone 'label' 72
            $status = Get-MapValue $milestone 'status'
            if ($status -isnot [string] -or $status -cnotin @('Verified', 'Partial', 'Unverified', 'Pending')) {
                throw 'Status map milestone must use Verified, Partial, Unverified, or Pending.'
            }

            $labelLength = (Get-MapValue $milestone 'label').Length
            $span = [int][Math]::Max(2, [Math]::Ceiling(($labelLength * 8 + 2 * $cardInset) / $stride))
            if ($usedColumns + $span -gt $columnCount) {
                $usedColumns = 0
                $top += 63
            }
            $cardX = $edge + $usedColumns * $stride
            $cardWidth = $span * $stride - $gap
            $labelX = $cardX + $cardInset
            $labelY = $top + 22
            $statusY = $top + 42
            $content.Add("  <g><rect x='$cardX' y='$top' width='$cardWidth' height='55' rx='7' class='card'/>")
            $content.Add("    <text x='$labelX' y='$labelY' class='milestone'>$label</text>")
            $content.Add("    <text x='$labelX' y='$statusY' class='milestone-status state-$status'>$status</text>")
            $content.Add('  </g>')
            $usedColumns += $span
        }
        $top += 55
    }

    $height = $top + $edge
    $backgroundWidth = $width - 1
    $backgroundHeight = $height - 1
    $description = 'Measured opening-scene speed for Loam. Green tiles count registered Windows resolver entries.'
    if ($ShaderGroups.Count -gt 0) {
        $description += ' Blue tiles count shader opcode catalogue labels.'
    }
    if ($Milestones.Count -gt 0) {
        $description += ' Runtime verification is reported by the milestone statuses.'
    }

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img" aria-labelledby="title description">
  <title id="title">Loam status map · $Fps FPS measured, $TargetFps FPS gameplay goal</title>
  <desc id="description">$description</desc>
  <style>
    text { font-family: system-ui, sans-serif; fill: #e9f2ec }
    .title { font-size: 30px; font-weight: 720; letter-spacing: -.65px }
    .muted { font-size: 13px; fill: #b4c5bb }
    .fps { font-size: 23px; font-weight: 700 }
    .section-title { font-size: 18px; font-weight: 680 }
    .group-total, .group-count { font: 12px ui-monospace, monospace; fill: #b4c5bb }
    .group-name { font: 13px ui-monospace, monospace }
    .card { fill: #1a2c24; stroke: #394e43 }
    .registry-cell { fill: #72c492 }
    .shader-cell { fill: #80bfcf }
    .milestone { font-size: 14px; font-weight: 620 }
    .milestone-status { font: 12px ui-monospace, monospace }
    .state-Verified { fill: #94e6ac }
    .state-Partial { fill: #ffd184 }
    .state-Unverified { fill: #bfc9d6 }
    .state-Pending { fill: #d9c5fa }
  </style>
  <rect x=".5" y=".5" width="$backgroundWidth" height="$backgroundHeight" rx="16" fill="#101e18" stroke="#394e43"/>
  <text x="24" y="47" class="title">Loam status map</text>
  <text x="24" y="72" class="muted">Windows compatibility and renderer progress</text>
  <text x="590" y="37" class="muted">Opening scene</text>
  <text x="590" y="69" class="fps">$Fps FPS</text>
  <text x="752" y="37" class="muted">Gameplay goal</text>
  <text x="752" y="69" class="fps">$TargetFps FPS</text>
  <path d="M24 91H880" stroke="#394e43"/>
$($content -join [Environment]::NewLine)
</svg>
"@
}
