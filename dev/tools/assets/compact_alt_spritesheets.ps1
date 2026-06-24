<#
.SYNOPSIS
    Compact gaps in spritesheet alt-variant filenames.
.DESCRIPTION
    Walks a directory tree looking for *_spritesheet.png and *_spritesheet.jpg files.
    For each base name, collects the base file and up to MaxAlt alt variants,
    then renames them to fill any gaps from the bottom up.
    The _f{N} frame-count token and file extension are preserved during renaming.

    Example (PNG):
      coopallbehind_alt2_spritesheet.png  (no base)
      coopallbehind_alt3_spritesheet.png
    becomes:
      coopallbehind_spritesheet.png
      coopallbehind_alt2_spritesheet.png

    Example (JPEG with frame count):
      dalllt_alt2_f48_spritesheet.jpg  (no base)
      dalllt_alt3_f48_spritesheet.jpg
    becomes:
      dalllt_f48_spritesheet.jpg
      dalllt_alt2_f48_spritesheet.jpg

.PARAMETER Path
    Root directory to scan recursively.  Defaults to .\resources\img\Spritesheets
.PARAMETER MaxAlt
    Highest alt number to look for.  Defaults to 5.
.PARAMETER WhatIf
    Preview only — show what would be renamed without changing anything.

.EXAMPLE
    .\compact_alt_spritesheets.ps1 -WhatIf
    .\compact_alt_spritesheets.ps1
    .\compact_alt_spritesheets.ps1 -Path '.\resources\img\spritesheets\camera'
#>
param(
    [string]$Path   = (Join-Path $PSScriptRoot '..\..\..\resources\img\spritesheets'),
    [int]   $MaxAlt = 5,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Collect all spritesheet files grouped by (directory, base name).
# Handles both PNG ({norm}[_alt{N}]_spritesheet.png)
# and JPEG ({norm}[_alt{N}]_f{count}_spritesheet.jpg).
# Slot 1 = base file (no _altN suffix), slot N = _altN file.
# Each slot entry stores: Path, Ext, FcToken (e.g. "_f48" or "").
# ---------------------------------------------------------------------------

$groups = @{}

Get-ChildItem -Path $Path -Recurse -Filter '*_spritesheet.*' |
    Where-Object { $_.Extension -in @('.png', '.jpg') } |
    ForEach-Object {
        $stem = $_.BaseName   # without extension, e.g. "dalllt_alt2_f48_spritesheet"
        $dir  = $_.DirectoryName
        $ext  = $_.Extension  # '.png' or '.jpg'
        $base = $null
        $slot = $null
        $fcToken = ''

        # JPEG alt with frame count: {norm}_alt{N}_f{count}_spritesheet
        if ($stem -match '^(.+)_alt(\d+)_f(\d+)_spritesheet$') {
            $base    = $Matches[1]
            $slot    = [int]$Matches[2]
            $fcToken = "_f$($Matches[3])"
        }
        # PNG alt (no frame count): {norm}_alt{N}_spritesheet
        elseif ($stem -match '^(.+)_alt(\d+)_spritesheet$') {
            $base = $Matches[1]
            $slot = [int]$Matches[2]
        }
        # JPEG base with frame count: {norm}_f{count}_spritesheet
        elseif ($stem -match '^(.+)_f(\d+)_spritesheet$') {
            $base    = $Matches[1]
            $slot    = 1
            $fcToken = "_f$($Matches[2])"
        }
        # PNG base (no frame count): {norm}_spritesheet
        elseif ($stem -match '^(.+)_spritesheet$') {
            $base = $Matches[1]
            $slot = 1
        }
        else {
            return   # skip unexpected names
        }

        $key = "$dir`|$base|$ext"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [PSCustomObject]@{ Dir = $dir; Base = $base; Ext = $ext; Slots = @{} }
        }
        $groups[$key].Slots[$slot] = [PSCustomObject]@{
            Path    = $_.FullName
            FcToken = $fcToken
        }
    }

# ---------------------------------------------------------------------------
# For each group, build a compact rename plan and execute (or preview) it.
# Processing targets from lowest slot upward keeps source paths valid,
# since we only ever move files down to a slot that was already freed.
# ---------------------------------------------------------------------------

$totalRenames = 0
$resolvedRoot = (Resolve-Path $Path).Path

foreach ($key in ($groups.Keys | Sort-Object)) {
    $g = $groups[$key]

    # Collect occupied slots in ascending order.
    $occupied = @(1..$MaxAlt | Where-Object { $g.Slots.ContainsKey($_) })
    if ($occupied.Count -eq 0) { continue }

    # Pair each occupied slot with its compacted target slot.
    $renames = [System.Collections.Generic.List[PSCustomObject]]::new()
    $targetSlot = 1
    foreach ($srcSlot in $occupied) {
        if ($srcSlot -ne $targetSlot) {
            $entry   = $g.Slots[$srcSlot]
            $dstName = if ($targetSlot -eq 1) {
                "$($g.Base)$($entry.FcToken)_spritesheet$($g.Ext)"
            } else {
                "$($g.Base)_alt${targetSlot}$($entry.FcToken)_spritesheet$($g.Ext)"
            }
            $renames.Add([PSCustomObject]@{
                Src     = $entry.Path
                DstName = $dstName
                DstPath = Join-Path $g.Dir $dstName
            })
        }
        $targetSlot++
    }

    if ($renames.Count -eq 0) { continue }

    $relDir = $g.Dir.Replace($resolvedRoot, '').TrimStart('\/')
    if ($relDir -eq '') { $relDir = '.' }
    Write-Host "[$relDir]" -ForegroundColor Cyan

    foreach ($item in $renames) {
        $srcLeaf = Split-Path $item.Src -Leaf
        if ($WhatIf) {
            Write-Host ("  {0,-65}  ->  {1}" -f $srcLeaf, $item.DstName)
        } else {
            Rename-Item -Path $item.Src -NewName $item.DstName
            Write-Host ("  {0,-65}  ->  {1}" -f $srcLeaf, $item.DstName)
        }
        $totalRenames++
    }
}

Write-Host ''
if ($totalRenames -eq 0) {
    Write-Host 'No gaps found — all alt sequences are already compact.' -ForegroundColor Green
} elseif ($WhatIf) {
    Write-Host "$totalRenames rename(s) would be performed.  Re-run without -WhatIf to apply." -ForegroundColor Yellow
} else {
    Write-Host "$totalRenames rename(s) performed." -ForegroundColor Green
}
