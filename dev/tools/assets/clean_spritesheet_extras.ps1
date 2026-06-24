<#
.SYNOPSIS
    Remove spritesheet JPEG files that are not recognised venue event names.
.DESCRIPTION
    Scans the six resources/img/spritesheets/ category folders (camera, lighting, postproc
    and their corresponding small variants) for files matching the JPEG spritesheet
    naming convention:

        {norm_key}_f{N}_spritesheet.jpg

    Any file whose norm key (jbase with underscores/spaces stripped and lowercased)
    is not in the canonical event list for that category is considered unexpected.
    These are exactly the files the Spritesheet Coverage test in
    test_rock_band_helpers_vkr.lua reports as FAIL.

    Typical candidates: leftover alt variants (_alt2_, _near_), renamed copies,
    or files with typos that were never cleaned up after compaction.

    Run with -WhatIf (default) to preview.  Re-run without it to delete.

.PARAMETER Root
    Root of the spritesheet tree.  Defaults to .\resources\img\spritesheets
.PARAMETER WhatIf
    Preview only — list what would be removed without deleting anything.

.EXAMPLE
    .\clean_spritesheet_extras.ps1 -WhatIf
    .\clean_spritesheet_extras.ps1
    .\clean_spritesheet_extras.ps1 -Root '.\resources\img\spritesheets\camera'
#>
param(
    [string]$Root   = (Join-Path $PSScriptRoot '..\..\..\resources\img\spritesheets'),
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Canonical norm keys per category.
# Mirror the expected-key computation in tests/run_spritesheet_coverage.lua.
# Norm key = jbase (filename before _f{N}_spritesheet) with [_ ] stripped, lowercased.
# Update these if DIRECTED_SPRITE_NAMES, COOP_POOL, LIGHTING_NAMES, POSTPROC_NAMES,
# or POSTPROC_SPRITE_NAMES change in rock_band_venue_demo_vkr/defaults.lua.
# ---------------------------------------------------------------------------

$CameraKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($k in @(
    # Directed cuts — mapped via DIRECTED_SPRITE_NAMES
    'dall','dallcam','dalllt','dallyeah','dcrowd',
    'ddrums','ddrumspoint','ddrumsnp','ddrumslt','ddrumskd',
    'dvocals','dvoxnp','dvoxcls','dvoxcampr','dvoxcampt',
    'dstagedive','dcrowdsurf',
    'dbass','dcrowdbass','dbassnp','dbasscam','dbasscls',
    'dgtr','dcrowdgtr','dgtrnp','dgtrcls','dgtrcampr','dgtrcampt',
    'dkeys','dkeyscam','dkeysnp',
    'dduodrums','dduobass','dduogtr','dduokv','dduogb','dduokb','dduokg',
    # Coop shots — bare name from COOP_POOL with [_ ] stripped and lowercased
    'coopallbehind','coopallfar','coopallnear',
    'coopfrontbehind','coopfrontnear',
    'coopdbehind','coopdnear','coopdcloseuphand','coopdcloseuphead',
    'coopvbehind','coopvnear','coopvcloseup',
    'coopbbehind','coopbnear','coopbcloseuphand','coopbcloseuphead',
    'coopgbehind','coopgnear','coopgcloseuphand','coopgcloseuphead',
    'coopkbehind','coopknear','coopkcloseuphand','coopkcloseuphead',
    'coopdvnear','coopbdnear','coopdgnear',
    'coopbvbehind','coopbvnear',
    'coopgvbehind','coopgvnear',
    'coopkvbehind','coopkvnear',
    'coopbgbehind','coopbgnear',
    'coopbkbehind','coopbknear',
    'coopgkbehind','coopgknear'
)) { [void]$CameraKeys.Add($k) }

$LightingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($k in @(
    # LIGHTING_NAMES with [_ ] stripped and lowercased
    'verse','chorus','manualcool','manualwarm','dischord','stomp',
    'loopcool','loopwarm','harmony','frenzy',
    'silhouettes','silhouettesspot','searchlights','sweep',
    'strobeslow','strobefast','blackoutslow','blackoutfast','blackoutspot',
    'flareslow','flarefast','bre'
)) { [void]$LightingKeys.Add($k) }

$PostprocKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($k in @(
    # Exception entries from POSTPROC_SPRITE_NAMES (override the algorithmic norm)
    'contrastbw',       # contrast_a
    'desatposterize',   # desat_posterize_trails
    '16mmfilm',         # film_16mm
    'filmbw',           # film_b+w
    'bluefilter',       # film_blue_filter
    'sepiaink',         # film_sepia_ink
    'silvertone',       # film_silvertone
    'horrormovie',      # horror_movie_special
    'colormuted',       # ProFilm_b
    'mirror',           # ProFilm_mirror_a
    'psychbluered',     # ProFilm_psychedelic_blue_red
    'videograiny',      # video_a
    # Remaining POSTPROC_NAMES — bare name (without .pp) with [_ ] stripped and lowercased
    'bloom','bright','cleantrails','desatblue',
    'filmcontrast','filmcontrastblue','filmcontrastgreen','filmcontrastred',
    'flickertrails','photonegative','photocopy','posterize',
    'profilma',         # ProFilm_a  (P, F, a stripped of underscores → ProFilma → profilma)
    'shittytv','spacewoosh','videobw','videosecurity','videotrails'
)) { [void]$PostprocKeys.Add($k) }

# ---------------------------------------------------------------------------
# Category folder → expected key set
# ---------------------------------------------------------------------------
$categoryMap = [ordered]@{
    'camera'         = $CameraKeys
    'camera small'   = $CameraKeys
    'lighting'       = $LightingKeys
    'lighting small' = $LightingKeys
    'postproc'       = $PostprocKeys
    'postproc small' = $PostprocKeys
}

# ---------------------------------------------------------------------------
# Scan and collect unexpected files
# ---------------------------------------------------------------------------
$resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)

$toRemove = [System.Collections.Generic.List[string]]::new()

foreach ($catFolder in $categoryMap.Keys) {
    $dir      = Join-Path $resolvedRoot $catFolder
    $expected = $categoryMap[$catFolder]

    if (-not (Test-Path $dir)) { continue }

    foreach ($file in (Get-ChildItem -Path $dir -File)) {
        # Only examine files that follow the JPEG spritesheet naming convention.
        if ($file.Name -notmatch '^(.+)_f\d+_spritesheet\.jpg$') { continue }
        $jbase = $Matches[1]
        $norm  = ($jbase -replace '[_ ]', '').ToLower()

        if (-not $expected.Contains($norm)) {
            $toRemove.Add($file.FullName)
        }
    }
}

# ---------------------------------------------------------------------------
# Report / delete
# ---------------------------------------------------------------------------
if ($toRemove.Count -eq 0) {
    Write-Host 'No unexpected spritesheet files found.' -ForegroundColor Green
    exit 0
}

foreach ($path in ($toRemove | Sort-Object)) {
    $rel = $path.Substring($resolvedRoot.Length).TrimStart('\/')
    Write-Host "  $rel"
}

Write-Host ''
if ($WhatIf) {
    Write-Host "$($toRemove.Count) file(s) would be removed  (re-run without -WhatIf to apply)." -ForegroundColor Yellow
} else {
    foreach ($path in $toRemove) {
        Remove-Item -Path $path -Force
    }
    Write-Host "$($toRemove.Count) file(s) removed." -ForegroundColor Green
}
