#Requires -Version 5.1
<#
.SYNOPSIS
    Slice a Rock Band venue demo capture into named spritesheets.

.DESCRIPTION
    Reads the event order that GenerateDemoVenue() writes to the VENUE track and cuts
    the captured video into 8×N spritesheets (426×240 tiles, 30 fps loop).
    N rows = ceil(played/8); default TileCount 72 → 8×9 (played = TileCount, or
    TileCount - fadeFrames when -FadeSec is used; see -TileCount / -FadeSec).
    Output files are named to drop directly into resources/img/spritesheets/{camera|lighting|postproc}/.

    SYNC POINT
    ----------
    The pre-roll puts [coop_d_closeup_head] at measure 1. The first cycling event
    fires at measure 3. Supply the time of that cut as -FirstEventSec.

    WINDOW SIZES (mirrors GenerateDemoVenue)
    ----------------------------------------
    Camera  : 4 measures per directed cut (variable pre-roll requires more headroom)
    Coop    : 2 measures per coop shot
    Lighting: window size from -WindowSec (default: 2 measures at -Bpm)
    PostProc: window size from -WindowSec (default: 2 measures at -Bpm)

    If -WindowSec is not specified it is computed automatically from -Bpm.
    If -WindowSec IS specified it always takes precedence.

    TIME FORMAT
    -----------
    -FirstEventSec accepts plain seconds (3.875), MM:SS (0:03), MM:SS:mmm (00:03:875),
    MM:SS.mmm (00:03.875), or HH:MM:SS.mmm (0:00:03.875). The colon-before-ms form
    (00:03:875) used by many video players is handled automatically.

    SINGLE-SHOT MODE (-EventName)
    ------------------------------
    Directed cuts have variable pre-roll: the camera system may switch slightly BEFORE
    the text event position, and the "hit" of the animation lands ON the event.
    Because the pre-roll varies per cut (some 0s, some 0.5s, some 1s), sequential
    bulk extraction may not capture each cut cleanly.

    Use -EventName to extract ONE specific event at a time:
        .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:15:200 `
            -Mode camera -EventName directed_bass
    Scrub to where you want the 2.4s animation loop to begin (typically just as the
    cut is established), note that time, and run once per directed cut.
    The output file is named correctly and ready to integrate.

    Lighting and PostProc can also use -EventName for re-extraction of a single event.

.PARAMETER Video
    Path to the captured video file (any format ffmpeg supports).

.PARAMETER FirstEventSec
    Time in the video where the target event's animation should start.
    In batch mode: the moment the first cycling event fires (measure 3 cut).
    In single-shot mode (-EventName): where the 2.4s loop should begin for that cut.
    Accepts: 3.875  |  0:03  |  00:03:875  |  00:03.875  |  0:00:03.875

.PARAMETER Mode
    Which demo mode was recorded: camera, coop, lighting, or postproc.
    Camera and coop both output to resources/img/spritesheets/camera/.

.PARAMETER EventName
    If set, extract only this one event and exit (single-shot mode).
    For camera: bare Lua name (directed_bass) or norm key (dbass) both accepted.
    For lighting: preset name (verse, loop_warm).
    For postproc: bare name without .pp (bloom, ProFilm_a) or norm key (profilma).
    Output file is named correctly for direct integration.

.PARAMETER AltNumber
    Alternative take number for single-shot mode. Default: 0 (canonical).
    When >= 2, the output file gets an _alt{N} suffix: dbass_alt2_spritesheet.png.
    The Lua player picks randomly among the canonical and all alts each session.
    Use 0 for the primary capture; use 2, 3, 4... for each additional recorded take.
    Takes precedence over -AutoAlt when >= 2.

.PARAMETER CamCombo
    Which two non-drummer instruments are present (camera and coop modes only).
    'all' (default): all instruments -- no events are filtered.
    'bg': Bass + Guitar, no Keys -- skips key-specific directed/coop shots.
    'bk': Bass + Keys, no Guitar -- skips guitar-specific shots.
    'gk': Guitar + Keys, no Bass -- skips bass-specific shots.
    Must match the combo used when the demo project was generated.

.PARAMETER AutoAlt
    Probe the output folder before writing; write to the next free alt slot automatically.
    If the canonical file (norm_spritesheet.png) exists, writes _alt2, then _alt3, etc.
    In single-shot mode: takes effect when -AltNumber is 0 (default).
    In batch mode: each event is probed independently.

.PARAMETER TileScale
    Tile resolution to generate: 0=both (default), 1=small only, 2=full only.
    0 (default): generates both sizes; 2x goes to Category/, 1x to "Category small/".
    Scale 2 = 426x240 px tiles -> 3408x2160 sheet (~10 MB).
    Scale 1 = 213x120 px tiles -> 1704x1080 sheet (~2.5 MB), identical display quality.
    The Lua player derives tile size from image dimensions, so both scales load correctly.

.PARAMETER TileCount
    Number of video frames to CAPTURE (the read window). Default: 72.
    Columns are always 8; rows are computed from the played count (see below).
    72 frames = 8×9 sheet (2.4 s loop at 30 fps).
    Values above 72 produce taller sheets; the Lua player reads the row count
    from the image dimensions automatically.
    Examples: 72 = 2.4 s, 90 = 3.0 s, 120 = 4.0 s, 60 = 2.0 s, 48 = 1.6 s.

    With -FadeSec the self-contained crossfade consumes fadeFrames from the capture,
    so the PLAYED count (and filename/grid) is TileCount - fadeFrames. To keep a target
    played length on a clip with spare footage, raise -TileCount by the fade length
    (e.g. -TileCount 126 -FadeSec 0.2 -> 120 played frames). A precise shot with no
    footage to spare simply yields a slightly shorter seamless loop.

.PARAMETER Bpm
    BPM used when generating the demo project. Used to auto-compute WindowSec.
    Default: 120. Ignored if -WindowSec is specified explicitly.

.PARAMETER WindowSec
    Duration of each event window in seconds. Overrides the BPM-derived default.
    Camera mode always uses 4 measures and ignores this parameter.

.PARAMETER OutDir
    Output folder. Defaults to .\resources\img\spritesheets\{camera|lighting|postproc}\ next to this script.

.PARAMETER Jpeg
    Output JPEG instead of PNG.  Embeds the frame count in the filename so the Lua
    player can skip the JS_LICE pixel scan on load.
    Output name: {norm}_f{played}_spritesheet.jpg  (or _alt{N}_f{played}_... for alts),
    where {played} is the played count (= TileCount, or TileCount - fadeFrames with -FadeSec).
    PNG output (default) uses the original naming: {norm}_spritesheet.png.

.PARAMETER Crop
    Optional ffmpeg crop filter (W:H:X:Y) to remove HUD chrome or black bars.
    Example: "1728:972:96:54" trims 96px sides and 54px top/bottom from 1920x1080.

.PARAMETER FadeSec
    Crossfade duration in seconds for loop smoothing. Default: 0 (disabled).
    Self-contained centered seam crossfade: overlaps the clip's OWN last FadeSec frames
    (faded out) onto its own first FadeSec frames, then centers the blend on the loop
    seam. It never reads past the loop point, so no footage from the next shot leaks in.
    The overlap consumes fadeFrames, so the played count is TileCount - fadeFrames (see
    -TileCount). Use 0.1–0.4 s (3–12 frames at 30 fps). Example: -FadeSec 0.2 = 6 frames.

.EXAMPLE
    # Batch: camera mode at 120 BPM (8s windows auto-computed = 4 measures)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera

    # Batch: lighting mode, explicit BPM
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode lighting -Bpm 120

    # Batch: postproc with HUD crop
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode postproc -Crop "1728:972:96:54"

    # Batch: both sizes (default) -- camera/ gets 2x, "camera small/" gets 1x
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera

    # Batch: small only (1704x1080, ~2.5 MB)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera -TileScale 1

    # Batch: camera with a shorter 2.0 s loop (60 frames instead of 72)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera -TileCount 60

    # Single-shot: canonical take
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:15:200 -Mode camera -EventName directed_bass

    # Single-shot: alternative take 2 (produces dbass_alt2_spritesheet.png)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:22:450 -Mode camera -EventName directed_bass -AltNumber 2

    # Single-shot: one lighting preset
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 01:02:450 -Mode lighting -EventName verse

    # Batch: coop mode, all instruments
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode coop

    # Batch: coop mode, Bass+Guitar combo (no Keys -- 7 key-specific shots are skipped)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode coop -CamCombo bg

    # Batch: camera, Bass+Guitar combo (matches a demo project generated with BG combo)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera -CamCombo bg

    # Batch: auto-increment -- second run preserves first run's files as alts
    .\extract_spritesheets.ps1 -Video cap2.mkv -FirstEventSec 00:04:000 -Mode camera -AutoAlt

    # Single-shot: auto-increment (canonical -> _alt2 -> _alt3... probed per output dir)
    .\extract_spritesheets.ps1 -Video cap2.mkv -FirstEventSec 00:22:450 -Mode camera -EventName directed_bass -AutoAlt

    # Batch: JPEG output with frame count in filename (dbass_f72_spritesheet.jpg etc.)
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:04:000 -Mode camera -Jpeg

    # Single-shot: JPEG with 48-frame loop
    .\extract_spritesheets.ps1 -Video cap.mkv -FirstEventSec 00:15:200 -Mode camera -EventName directed_bass -TileCount 48 -Jpeg
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Video,
    [Parameter(Mandatory)][string]$FirstEventSec,
    [Parameter(Mandatory)][ValidateSet('camera','coop','lighting','postproc')][string]$Mode,
    [string]$EventName  = '',
    [int]$AltNumber     = 0,
    [string]$CamCombo   = 'all',
    [switch]$AutoAlt,
    [double]$Bpm        = 120.0,
    [double]$WindowSec  = 0.0,
    [int]$TileCount     = 72,
    [int]$TileScale     = 0,
    [string]$OutDir     = '',
    [string]$Crop       = '',
    [double]$FadeSec    = 0.0,
    [switch]$Jpeg
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Ext            = if ($Jpeg) { '.jpg' } else { '.png' }
$JpegQualityArgs = if ($Jpeg) { @('-q:v', '2') } else { @() }

# ---------------------------------------------------------------------------
# Time format parser
# Accepts: plain seconds, MM:SS, MM:SS:mmm, MM:SS.mmm, HH:MM:SS, HH:MM:SS:mmm, HH:MM:SS.mmm
# ---------------------------------------------------------------------------
function ConvertTo-Seconds([string]$ts) {
    $ts = $ts.Trim()
    # Plain decimal seconds
    if ($ts -match '^\d+(\.\d+)?$') { return [double]$ts }

    # Split on colons
    $cparts = $ts -split ':'
    switch ($cparts.Count) {
        2 {
            # MM:SS or MM:SS.mmm
            $mm   = [int]$cparts[0]
            $sms  = $cparts[1] -split '\.'
            $ss   = [int]$sms[0]
            $frac = if ($sms.Count -gt 1) { [double]('0.' + $sms[1]) } else { 0.0 }
            return $mm * 60 + $ss + $frac
        }
        3 {
            # Distinguish MM:SS:mmm (last part = 1-3 digits, value 0-999)
            # from HH:MM:SS or HH:MM:SS.mmm
            $lastRaw = ($cparts[2] -split '\.')[0]
            if ($lastRaw.Length -le 3 -and [int]$lastRaw -le 999 `
                -and [int]$cparts[0] -lt 60 -and [int]$cparts[1] -lt 60) {
                # MM:SS:mmm
                return [int]$cparts[0] * 60 + [int]$cparts[1] + [int]$lastRaw / 1000.0
            } else {
                # HH:MM:SS or HH:MM:SS.mmm
                $sms  = $cparts[2] -split '\.'
                $frac = if ($sms.Count -gt 1) { [double]('0.' + $sms[1]) } else { 0.0 }
                return [int]$cparts[0] * 3600 + [int]$cparts[1] * 60 + [int]$sms[0] + $frac
            }
        }
        4 {
            # HH:MM:SS:mmm
            return [int]$cparts[0] * 3600 + [int]$cparts[1] * 60 + [int]$cparts[2] + [int]$cparts[3] / 1000.0
        }
        default {
            throw "Unrecognised time format '$ts'. Use: 3.875 | 0:03 | 00:03:875 | 00:03.875 | 0:00:03.875"
        }
    }
}

$T0 = ConvertTo-Seconds $FirstEventSec

# ---------------------------------------------------------------------------
# Auto-compute WindowSec from BPM when not specified explicitly
# Camera uses 4 measures; lighting/postproc use 2 measures
# ---------------------------------------------------------------------------
$BeatSec    = 60.0 / [math]::Max(40.0, $Bpm)
$MeasureSec = 4.0 * $BeatSec

if ($WindowSec -eq 0.0) {
    $WindowSec = switch ($Mode) {
        'camera'   { 4.0 * $MeasureSec }   # 4 measures -- directed cuts need headroom
        'coop'     { 2.0 * $MeasureSec }
        'lighting' { 2.0 * $MeasureSec }
        'postproc' { 2.0 * $MeasureSec }
    }
}

# Camera and coop modes always force their window size regardless of -WindowSec
if ($Mode -eq 'camera') { $WindowSec = 4.0 * $MeasureSec }
if ($Mode -eq 'coop')   { $WindowSec = 2.0 * $MeasureSec }

# ---------------------------------------------------------------------------
# Grid / tile constants -- cols fixed at 8; rows computed from OutCount (played frames)
# ---------------------------------------------------------------------------
$COLS = 8
$FPS  = 30
if ($TileCount -lt 1) {
    Write-Warning "-TileCount $TileCount is below minimum (1) -- clamped."
    $TileCount = 1
}
$LoopSec = [double]$TileCount / $FPS
$ReadSec = $LoopSec   # read exactly the captured window; the crossfade is self-contained
if ($TileScale -notin @(0, 1, 2)) {
    Write-Warning "-TileScale $TileScale must be 0, 1, or 2 -- defaulting to 0 (both)."
    $TileScale = 0
}
if ($FadeSec -lt 0.0) { $FadeSec = 0.0 }
if ($FadeSec -gt 0.0 -and $FadeSec -ge $LoopSec) {
    $cap = [math]::Round($LoopSec * 0.25, 3)
    Write-Warning "-FadeSec $FadeSec s >= loop duration ($LoopSec s). Capped to $cap s."
    $FadeSec = $cap
}
# Self-contained crossfade consumes the fade length from the captured frames:
# TileCount = frames captured; OutCount = playable frames (filename/grid) after the overlap.
$FadeFrames = if ($FadeSec -gt 0.0) { [int][math]::Round($FadeSec * $FPS) } else { 0 }
$OutCount   = [math]::Max(1, $TileCount - $FadeFrames)
$ROWS       = [math]::Ceiling($OutCount / $COLS)   # matches math.ceil(fc/SPRITE_COLS) in venue_sprites.lua
# 0 = both scales; TILE_W/TILE_H are computed per-scale during extraction
$ScalesToRun = if ($TileScale -eq 0) { @(2, 1) } else { @($TileScale) }
if ($CamCombo -notin @('all','bg','bk','gk')) {
    Write-Warning "-CamCombo '$CamCombo' is not valid. Use: all, bg, bk, gk. Defaulting to 'all'."
    $CamCombo = 'all'
}

# Suppress ffmpeg banner/progress in normal mode; full output in -Verbose mode.
# Do NOT use 2>&1 -- PS 5.1 wraps stderr in ErrorRecord objects which trigger
# $ErrorActionPreference = 'Stop' even when ffmpeg exits 0.
$FfQuiet = if ($VerbosePreference -eq 'SilentlyContinue') { @('-hide_banner','-loglevel','error') } else { @() }

# ---------------------------------------------------------------------------
# Resolve output directory
# ---------------------------------------------------------------------------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Category   = switch ($Mode) { 'camera' {'camera'} 'coop' {'camera'} 'lighting' {'lighting'} 'postproc' {'postproc'} }
# Output dirs are resolved per scale in the extraction sections below.

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found in PATH.`nInstall from https://ffmpeg.org/ and add to PATH."
    exit 1
}
if (-not (Test-Path $Video)) {
    Write-Error "Video not found: $Video"
    exit 1
}

# ---------------------------------------------------------------------------
# Normalization -- mirrors NormalizeSpriteKey() in venue_sprites.lua
# ---------------------------------------------------------------------------
$DirectedSprite = @{
    directed_all='dall';           directed_all_cam='dallcam';      directed_all_lt='dalllt'
    directed_all_yeah='dallyeah'; directed_crowd='dcrowd'
    directed_drums='ddrums';      directed_drums_pnt='ddrumspoint'
    directed_drums_np='ddrumsnp'; directed_drums_lt='ddrumslt';    directed_drums_kd='ddrumskd'
    directed_vocals='dvocals';    directed_vocals_np='dvoxnp';     directed_vocals_cls='dvoxcls'
    directed_vocals_cam_pr='dvoxcampr'; directed_vocals_cam_pt='dvoxcampt'
    directed_stagedive='dstagedive'; directed_crowdsurf='dcrowdsurf'
    directed_bass='dbass';        directed_crowd_b='dcrowdbass'
    directed_bass_np='dbassnp';   directed_bass_cam='dbasscam';    directed_bass_cls='dbasscls'
    directed_guitar='dgtr';       directed_crowd_g='dcrowdgtr'
    directed_guitar_np='dgtrnp';  directed_guitar_cls='dgtrcls'
    directed_guitar_cam_pr='dgtrcampr'; directed_guitar_cam_pt='dgtrcampt'
    directed_keys='dkeys';        directed_keys_cam='dkeyscam';    directed_keys_np='dkeysnp'
    directed_duo_drums='dduodrums'; directed_duo_bass='dduobass'
    directed_duo_guitar='dduogtr'; directed_duo_kv='dduokv'
    directed_duo_gb='dduogb';     directed_duo_kb='dduokb';        directed_duo_kg='dduokg'
}
# Reverse map: norm key -> norm key (identity, for when user passes norm key directly)
$DirectedNormSet = @{}
foreach ($v in $DirectedSprite.Values) { $DirectedNormSet[$v] = $v }

$PostprocSprite = @{}
$PostprocSprite['contrast_a']                  = 'contrastbw'
$PostprocSprite['desat_posterize_trails']       = 'desatposterize'
$PostprocSprite['film_16mm']                   = '16mmfilm'
$PostprocSprite['film_b+w']                    = 'filmbw'
$PostprocSprite['film_blue_filter']            = 'bluefilter'
$PostprocSprite['film_sepia_ink']              = 'sepiaink'
$PostprocSprite['film_silvertone']             = 'silvertone'
$PostprocSprite['horror_movie_special']        = 'horrormovie'
$PostprocSprite['ProFilm_b']                   = 'colormuted'
$PostprocSprite['ProFilm_mirror_a']            = 'mirror'
$PostprocSprite['ProFilm_psychedelic_blue_red']= 'psychbluered'
$PostprocSprite['video_a']                     = 'videograiny'
$PostprocNormSet = @{}
foreach ($v in $PostprocSprite.Values) { $PostprocNormSet[$v] = $v }

function Get-NormCamera([string]$name) {
    if ($DirectedSprite.ContainsKey($name))  { return $DirectedSprite[$name] }
    if ($DirectedNormSet.ContainsKey($name)) { return $name }  # already a norm key
    return ($name -replace '[_ ]','').ToLower()
}
function Get-NormLighting([string]$name) { return ($name -replace '[_ ]','').ToLower() }
function Get-NormPostProc([string]$name) {
    $bare = $name -replace '\.pp$',''
    if ($PostprocSprite.ContainsKey($bare))  { return $PostprocSprite[$bare] }
    if ($PostprocNormSet.ContainsKey($bare)) { return $bare }  # already a norm key
    return ($bare -replace '[_ ]','').ToLower()
}

# ---------------------------------------------------------------------------
# Instrument combo filtering -- mirrors DirectedRequired, CoopRequired,
# and MutedFromCombo in rock_band_venue_demo_vkr/actions.lua
# $ev is a bare name without brackets: 'directed_bass', 'coop_bd_near', etc.
# Returns an array of required instrument letters ('d','v','b','g','k').
# ---------------------------------------------------------------------------
function Get-DirectedRequired([string]$ev) {
    if ($ev -notmatch '^directed_(.+)$') { return @() }
    $inner = $Matches[1]
    if ($inner -match '^all' -or $inner -in @('stagedive','crowdsurf','crowd')) { return @() }
    if ($inner -eq 'crowd_b') { return @('b') }
    if ($inner -eq 'crowd_g') { return @('g') }
    if ($inner -match '^duo_(.+)$') {
        $part = $Matches[1]
        if ($part -eq 'drums')  { return @('d','v') }
        if ($part -eq 'bass')   { return @('b','v') }
        if ($part -eq 'guitar') { return @('g','v') }
        if ($part.Length -eq 2) {
            $valid = @{d=1;v=1;b=1;g=1;k=1}
            return @($part.ToCharArray() | Where-Object { $valid.ContainsKey([string]$_) } | ForEach-Object { [string]$_ })
        }
        return @()
    }
    if ($inner -match '^drums')  { return @('d') }
    if ($inner -match '^vocals') { return @('v') }
    if ($inner -match '^bass')   { return @('b') }
    if ($inner -match '^guitar') { return @('g') }
    if ($inner -match '^keys')   { return @('k') }
    return @()
}
function Get-CoopRequired([string]$ev) {
    if ($ev -notmatch '^coop_(.+)$') { return @() }
    $inner = $Matches[1]
    if ($inner -match '^all' -or $inner -match '^front') { return @() }
    # Code is the instrument letters before the first underscore: 'bd' in 'bd_near'
    if ($inner -notmatch '^([a-z]+)_') { return @() }
    $code  = $Matches[1]
    $valid = @{d=1;v=1;b=1;g=1;k=1}
    return @($code.ToCharArray() | Where-Object { $valid.ContainsKey([string]$_) } | ForEach-Object { [string]$_ })
}
function Get-MutedFromCombo([string]$combo) {
    switch ($combo) {
        'bg' { return @{k = $true} }   # Bass + Guitar, no Keys
        'bk' { return @{g = $true} }   # Bass + Keys, no Guitar
        'gk' { return @{b = $true} }   # Guitar + Keys, no Bass
    }
    return @{}
}

# ---------------------------------------------------------------------------
# Build ordered window list -- mirrors the slot order in GenerateDemoVenue()
# ---------------------------------------------------------------------------
$Windows = [System.Collections.Generic.List[PSCustomObject]]::new()

$DirectedPool = @(
    'directed_all','directed_all_cam','directed_all_lt','directed_all_yeah',
    'directed_crowd',
    'directed_drums','directed_drums_pnt','directed_drums_np',
    'directed_drums_lt','directed_drums_kd',
    'directed_vocals','directed_vocals_np','directed_vocals_cls',
    'directed_vocals_cam_pr','directed_vocals_cam_pt',
    'directed_stagedive','directed_crowdsurf',
    'directed_bass','directed_crowd_b','directed_bass_np',
    'directed_bass_cam','directed_bass_cls',
    'directed_guitar','directed_crowd_g','directed_guitar_np',
    'directed_guitar_cls','directed_guitar_cam_pr','directed_guitar_cam_pt',
    'directed_keys','directed_keys_cam','directed_keys_np',
    'directed_duo_drums','directed_duo_bass','directed_duo_guitar',
    'directed_duo_kv','directed_duo_gb','directed_duo_kb','directed_duo_kg'
)
$CoopPool = @(
    'coop_all_behind','coop_all_far','coop_all_near',
    'coop_front_behind','coop_front_near',
    'coop_d_behind','coop_d_near','coop_d_closeup_hand','coop_d_closeup_head',
    'coop_v_behind','coop_v_near','coop_v_closeup',
    'coop_b_behind','coop_b_near','coop_b_closeup_hand','coop_b_closeup_head',
    'coop_g_behind','coop_g_near','coop_g_closeup_hand','coop_g_closeup_head',
    'coop_k_behind','coop_k_near','coop_k_closeup_hand','coop_k_closeup_head',
    'coop_dv_near','coop_bd_near','coop_dg_near',
    'coop_bv_behind','coop_bv_near',
    'coop_gv_behind','coop_gv_near',
    'coop_kv_behind','coop_kv_near',
    'coop_bg_behind','coop_bg_near',
    'coop_bk_behind','coop_bk_near',
    'coop_gk_behind','coop_gk_near'
)
$LightingNames = @(
    'verse','chorus','manual_cool','manual_warm','dischord','stomp',
    'loop_cool','loop_warm','harmony','frenzy','silhouettes','silhouettes_spot',
    'searchlights','sweep','strobe_slow','strobe_fast',
    'blackout_slow','blackout_fast','blackout_spot','flare_slow','flare_fast','bre'
)
$ManualSet = @{verse=1;chorus=1;manual_cool=1;manual_warm=1;dischord=1;stomp=1}
$PostprocNames = @(
    'bloom.pp','bright.pp','clean_trails.pp','contrast_a.pp',
    'desat_blue.pp','desat_posterize_trails.pp','film_16mm.pp',
    'film_b+w.pp','film_blue_filter.pp','film_contrast.pp',
    'film_contrast_blue.pp','film_contrast_green.pp',
    'film_contrast_red.pp','film_sepia_ink.pp','film_silvertone.pp',
    'flicker_trails.pp','horror_movie_special.pp','photo_negative.pp',
    'photocopy.pp','posterize.pp','ProFilm_a.pp','ProFilm_b.pp',
    'ProFilm_mirror_a.pp','ProFilm_psychedelic_blue_red.pp',
    'shitty_tv.pp','space_woosh.pp','video_a.pp','video_bw.pp',
    'video_security.pp','video_trails.pp'
)

switch ($Mode) {
    'camera' {
        $muted = Get-MutedFromCombo $CamCombo
        $slot  = 0
        foreach ($ev in $DirectedPool) {
            $req     = Get-DirectedRequired $ev
            $blocked = @($req | Where-Object { $muted.ContainsKey($_) }).Count -gt 0
            if (-not $blocked) {
                $norm = Get-NormCamera $ev
                $Windows.Add([PSCustomObject]@{ Slot=$slot; OutBase=$norm; Integration=$norm; IsCanonical=$true })
                $slot++
            }
        }
    }
    'coop' {
        $muted = Get-MutedFromCombo $CamCombo
        $slot  = 0
        foreach ($ev in $CoopPool) {
            $req     = Get-CoopRequired $ev
            $blocked = @($req | Where-Object { $muted.ContainsKey($_) }).Count -gt 0
            if (-not $blocked) {
                $norm = Get-NormCamera $ev
                $Windows.Add([PSCustomObject]@{ Slot=$slot; OutBase=$norm; Integration=$norm; IsCanonical=$true })
                $slot++
            }
        }
    }
    'lighting' {
        $slot = 0
        foreach ($lt in $LightingNames) {
            $isManual   = $ManualSet.ContainsKey($lt)
            $norm       = Get-NormLighting $lt
            $kfVariants = if ($isManual) { @('1beat','2beat') } else { @('') }
            foreach ($kf in $kfVariants) {
                foreach ($cam in @('far','near')) {
                    $suffix  = if ($kf) { "${cam}_${kf}" } else { $cam }
                    $outBase = "${lt}_${suffix}"
                    $isCanon = ($cam -eq 'far') -and ($kf -eq '' -or $kf -eq '1beat')
                    $Windows.Add([PSCustomObject]@{ Slot=$slot; OutBase=$outBase; Integration=$norm; IsCanonical=$isCanon })
                    $slot++
                }
            }
        }
    }
    'postproc' {
        $slot = 0
        foreach ($pp in $PostprocNames) {
            $norm = Get-NormPostProc $pp
            foreach ($cam in @('far','near')) {
                $isCanon = ($cam -eq 'far')
                $Windows.Add([PSCustomObject]@{ Slot=$slot; OutBase="${norm}_${cam}"; Integration=$norm; IsCanonical=$isCanon })
                $slot++
            }
        }
    }
}

# Resolve output dir for a given scale.  When both scales run, append " small" for 1x.
function Resolve-OutDir([int]$scale) {
    $suffix = if ($scale -eq 1) { ' small' } else { '' }
    if ($OutDir) {
        if ($TileScale -eq 0) { return "$OutDir$suffix" } else { return $OutDir }
    }
    return Join-Path $ScriptRoot "..\..\..\resources\img\spritesheets\$Category$suffix"
}

# Auto-alt: find the next unoccupied output file slot for a given norm key.
# Returns the canonical path if it does not exist; otherwise _alt2, _alt3, etc.
# Reads $Jpeg, $OutCount, and $Ext from script scope.
function Get-NextOutputFile([string]$outDir, [string]$normKey) {
    if ($Jpeg) {
        $canonical = Join-Path $outDir "${normKey}_f${OutCount}_spritesheet.jpg"
        if (-not (Test-Path $canonical)) { return $canonical }
        $n = 2
        while ($true) {
            $f = Join-Path $outDir "${normKey}_alt${n}_f${OutCount}_spritesheet.jpg"
            if (-not (Test-Path $f)) { return $f }
            $n++
        }
    } else {
        $canonical = Join-Path $outDir "${normKey}_spritesheet.png"
        if (-not (Test-Path $canonical)) { return $canonical }
        $n = 2
        while ($true) {
            $f = Join-Path $outDir "${normKey}_alt${n}_spritesheet.png"
            if (-not (Test-Path $f)) { return $f }
            $n++
        }
    }
}

# Returns @('-vf', chain) or @('-filter_complex', graph) ready to splice into ffArgs.
# Uses $FPS, $COLS, $ROWS, $FadeSec, $FadeFrames, $TileCount, $OutCount from script scope.
function Get-FilterArgs([string]$crop, [int]$tileW, [int]$tileH) {
    $baseFilters = if ($crop) { "crop=$crop,fps=$FPS,scale=${tileW}:${tileH}" } `
                   else        { "fps=$FPS,scale=${tileW}:${tileH}" }
    $tileFilter  = "tile=${COLS}x${ROWS}:padding=0:color=black"
    if ($FadeSec -le 0.0) {
        return @('-vf', "${baseFilters},${tileFilter}")
    }
    $D    = $FadeSec.ToString('F3')
    $half = [int][math]::Floor($FadeFrames / 2)   # rotate amount (frames) to center the blend
    # Self-contained centered loop crossfade: overlap the clip's own last D frames (faded out) onto
    # its own first D frames -> OutCount = TileCount - D playable frames (seamless, never reads past
    # the loop point), then rotate by D/2 so the dissolve straddles the seam.
    $loop = "[0:v]${baseFilters}[v];[v]split[body][tail];" +
            "[tail]trim=start_frame=${OutCount},setpts=PTS-STARTPTS,format=yuva420p,fade=out:st=0:d=${D}:alpha=1[t];" +
            "[body][t]overlay=eof_action=pass,trim=end_frame=${OutCount},setpts=PTS-STARTPTS,format=yuv420p[loop]"
    if ($half -ge 1) {
        $fc = "${loop};[loop]split[p1][p2];" +
              "[p1]trim=start_frame=${half},setpts=PTS-STARTPTS[a];" +
              "[p2]trim=end_frame=${half},setpts=PTS-STARTPTS[b];" +
              "[a][b]concat=n=2:v=1,${tileFilter}"
    } else {
        $fc = "${loop};[loop]${tileFilter}"
    }
    return @('-filter_complex', $fc)
}

# ---------------------------------------------------------------------------
# Single-shot mode: extract one named event at T0 and exit
# ---------------------------------------------------------------------------
if ($EventName) {
    $norm = switch ($Mode) {
        'camera'   { Get-NormCamera   $EventName }
        'coop'     { Get-NormCamera   $EventName }
        'lighting' { Get-NormLighting $EventName }
        'postproc' { Get-NormPostProc $EventName }
    }
    Write-Host ""
    Write-Host "Single-shot  : $EventName  ->  $norm"
    Write-Host "Start time   : $FirstEventSec  ($T0 s)"
    Write-Host ""
    foreach ($runScale in $ScalesToRun) {
        $runTileW  = 213 * $runScale
        $runTileH  = 120 * $runScale
        $runOutDir = Resolve-OutDir $runScale
        New-Item -ItemType Directory -Force -Path $runOutDir | Out-Null
        if ($AltNumber -ge 2) {
            $outFile = Join-Path $runOutDir "${norm}_alt${AltNumber}_f${OutCount}_spritesheet${Ext}"
            if (-not $Jpeg) { $outFile = Join-Path $runOutDir "${norm}_alt${AltNumber}_spritesheet.png" }
        } elseif ($AutoAlt) {
            $outFile = Get-NextOutputFile $runOutDir $norm
        } else {
            $outFile = if ($Jpeg) { Join-Path $runOutDir "${norm}_f${OutCount}_spritesheet.jpg" } `
                       else        { Join-Path $runOutDir "${norm}_spritesheet.png" }
        }
        $outLabel   = [System.IO.Path]::GetFileName($outFile)
        $filterArgs = Get-FilterArgs $Crop $runTileW $runTileH
        Write-Host "Output (${runScale}x) : $outFile"
        $ffArgs = @('-ss', $T0.ToString('F3'), '-t', $ReadSec.ToString('F3'),
                    '-i', $Video) + $filterArgs + @('-frames:v', '1') + $JpegQualityArgs + @('-y', $outFile)
        & ffmpeg @FfQuiet @ffArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ffmpeg failed (exit $LASTEXITCODE). Re-run with -Verbose for full ffmpeg output."
            exit 1
        }
        Write-Host "Done.  $outLabel written." -ForegroundColor Green
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Batch mode: extract all windows in slot order
# ---------------------------------------------------------------------------
$Total       = $Windows.Count
$TotalErrors = 0
$Timer       = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host ""
Write-Host "Mode     : $Mode  ($Total windows)"
Write-Host "Video    : $Video"
Write-Host "Sync     : first event at $FirstEventSec ($T0 s)"
Write-Host "BPM      : $Bpm  |  Window: $([math]::Round($WindowSec,2)) s"
Write-Host "Frames   : $TileCount captured -> $OutCount played  ($([math]::Round($OutCount / $FPS, 2)) s loop)  |  ${COLS}x${ROWS} grid  ${FPS}fps"
if ($FadeSec -gt 0.0) { Write-Host "Crossfade: $FadeSec s ($FadeFrames frames, self-contained -> $OutCount played)" }
$scaleLabel = if ($TileScale -eq 0) { '1x + 2x (both)' } else { "${TileScale}x" }
Write-Host "Scale    : $scaleLabel"
if ($Mode -in @('camera','coop')) {
    $comboLabel = switch ($CamCombo) {
        'bg' {'Bass+Guitar (no Keys)'} 'bk' {'Bass+Keys (no Guitar)'} 'gk' {'Guitar+Keys (no Bass)'}
        default {'All instruments'}
    }
    Write-Host "Combo    : $comboLabel"
}
if ($Crop) { Write-Host "Crop     : $Crop" }

foreach ($runScale in $ScalesToRun) {
    $runTileW  = 213 * $runScale
    $runTileH  = 120 * $runScale
    $runOutDir = Resolve-OutDir $runScale
    New-Item -ItemType Directory -Force -Path $runOutDir | Out-Null
    $runFilterArgs = Get-FilterArgs $Crop $runTileW $runTileH
    $Errors = 0

    Write-Host ""
    Write-Host "--- ${runScale}x  ${runTileW}x${runTileH}  ->  $runOutDir ---"
    Write-Host ""

    foreach ($w in $Windows) {
        $tStart = $T0 + $w.Slot * $WindowSec
        if ($AutoAlt) {
            $outFile = Get-NextOutputFile $runOutDir $w.OutBase
        } else {
            $outFile = if ($Jpeg) { Join-Path $runOutDir "$($w.OutBase)_f${OutCount}_spritesheet.jpg" } `
                       else        { Join-Path $runOutDir "$($w.OutBase)_spritesheet.png" }
        }

        Write-Host ("  [{0,3}/{1}]  {2,-45}  t={3,7:F2}s" -f ($w.Slot + 1), $Total, $w.OutBase, $tStart) -NoNewline

        $ffArgs = @('-ss', $tStart.ToString('F3'), '-t', $ReadSec.ToString('F3'),
                    '-i', $Video) + $runFilterArgs + @('-frames:v', '1') + $JpegQualityArgs + @('-y', $outFile)
        & ffmpeg @FfQuiet @ffArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  FAILED' -ForegroundColor Red
            $Errors++
        } else {
            Write-Host '  ok' -ForegroundColor Green
        }
    }

    # Lighting + PostProc: copy canonical (far) variants to integration-ready filenames
    if ($Mode -eq 'lighting' -or $Mode -eq 'postproc') {
        Write-Host ""
        Write-Host "Copying canonical variants to integration names..."
        $Windows | Where-Object { $_.IsCanonical } | ForEach-Object {
            $srcLeaf = if ($Jpeg) { "$($_.OutBase)_f${OutCount}_spritesheet.jpg" } else { "$($_.OutBase)_spritesheet.png" }
            $dstLeaf = if ($Jpeg) { "$($_.Integration)_f${OutCount}_spritesheet.jpg" } else { "$($_.Integration)_spritesheet.png" }
            $src = Join-Path $runOutDir $srcLeaf
            $dst = Join-Path $runOutDir $dstLeaf
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination $dst -Force
                Write-Host ("    {0,-55} -> {1}" -f $srcLeaf, $dstLeaf)
            }
        }
        Write-Host ""
        Write-Host "  Default canonical = far view + 1-beat keyframes (manual) / far view (auto)."
        Write-Host "  To use a different variant: copy the preferred file over the integration name."
    }

    $TotalErrors += $Errors
}

$Timer.Stop()
$elapsed_m = [math]::Floor($Timer.Elapsed.TotalMinutes)
$elapsed_s = $Timer.Elapsed.Seconds
$runCount  = $ScalesToRun.Count
Write-Host ""
$doneColor = if ($TotalErrors -eq 0) { 'Green' } else { 'Yellow' }
Write-Host ("Done in {0}m {1}s.  {2}/{3} succeeded." -f $elapsed_m, $elapsed_s, ($Total * $runCount - $TotalErrors), ($Total * $runCount)) `
    -ForegroundColor $doneColor
if ($TotalErrors -gt 0) { exit 1 }
