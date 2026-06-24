# Spritesheet Generation Guide

End-to-end process for producing venue event preview spritesheets.
Written so the process can be reproduced months later without re-deriving constants.

---

## Fixed constants (do not change without updating code)

| Constant | Value | Where used |
|---|---|---|
| Grid | 8 columns × 9 rows | `venue_sprites.lua` `SPRITE_COLS/ROWS` |
| Max frames per sheet | 72 (8×9) | at 30 fps = 2.4 s loop; `-TileCount` / `--tile-count` can reduce this |
| Target fps | 30 | `SPRITE_FRAME_RATE` |
| Loop duration | up to 2.4 s | default 72 frames ÷ 30 fps; fewer frames leave remainder black, `DetectFrameCount` auto-detects the boundary |
| Tile size | 426×240 px (2×) or 213×120 px (1×) | use `-TileScale 1` for ~2.5 MB; default 2× is ~10 MB |
| Sheet size | 3408×2160 (2×) or 1704×1080 (1×) | display quality is identical; Lua player renders at 213×120 |
| Border (self-hosted) | 0 px | `SPRITE_BORDER_SELF` in `venue_sprites.lua` |
| Border (FCP) | 1 px | `SPRITE_BORDER_FCP` — legacy only |
| Hard GPU cap | 8192 × 8192 px | ReaImGui `ImGui_CreateImage` limit |
| Spritesheet folder | `Spritesheets/{Lighting|PostProc|Camera}/` | Repo root, loaded before FCP |
| Naming pattern | `{norm_key}_spritesheet.png` | `NormalizeSpriteKey()` in `venue_sprites.lua` |

Normalization rules (same as `NormalizeSpriteKey` in `venue_sprites.lua`):
- **Camera**: use `DIRECTED_SPRITE_NAMES[bare]` if listed, otherwise strip `[_]` and lowercase
- **Lighting**: strip `[_]` and lowercase (`loop_warm` → `loopwarm`)
- **PostProc**: strip `.pp`, apply `POSTPROC_SPRITE_NAMES` exceptions, otherwise strip `[_]` and lowercase

Exceptions table for PostProc (`POSTPROC_SPRITE_NAMES` in both `venue_sprites.lua` and `venue_demo_vkr/defaults.lua`):
```
contrast_a              → contrastbw
desat_posterize_trails  → desatposterize
film_16mm               → 16mmfilm
film_b+w                → filmbw
film_blue_filter        → bluefilter
film_sepia_ink          → sepiaink
film_silvertone         → silvertone
horror_movie_special    → horrormovie
ProFilm_b               → colormuted
ProFilm_mirror_a        → mirror
ProFilm_psychedelic_blue_red → psychbluered
video_a                 → videograiny
```

---

## Step 1 — Generate the demo VENUE project in REAPER

**Tool:** `rock_band_venue_demo_vkr.lua` (run from REAPER Actions menu or ReaPack).

**Recommended settings for the published set:**
| Setting | Camera pass | Lighting pass | PostProc pass |
|---|---|---|---|
| BPM | 120 | 120 | 120 |
| Window | 4 s | 4 s | 4 s |
| Neutral lighting | Loop Warm | — | Loop Warm |
| Neutral post-proc | ProFilm A | ProFilm A | — |
| Camera far | coop_all_far | coop_all_far | coop_all_far |
| Camera near | — | coop_all_near | — |

**What it generates:**
- **Camera mode** (38 windows ≈ 2.5 min): one directed cut per window, constant lighting + postproc throughout.
- **Lighting mode** (68 windows ≈ 4.5 min): each preset × 2 cameras. Manual presets (verse, chorus, manual_cool, manual_warm, dischord, stomp) × 2 keyframe densities (1-beat, 2-beat) = 4 sub-windows per manual preset, 2 sub-windows per auto preset.
- **PostProc mode** (30 windows ≈ 2 min): one .pp effect per window, constant lighting + camera. Re-run with a different neutral lighting to capture combinations.

**Output:**
- VENUE MIDI track written to the current project with a deterministic event layout.
- Project marker "SYNC FLASH" placed at t=0 (orange) — use to align the video capture.
- Manifest CSV written to the project folder: `demo_manifest_{mode}.csv`.

**Workflow:**
1. Open a clean/dedicated REAPER project (not a real chart).
2. Run `rock_band_venue_demo_vkr.lua`.
3. Select mode + settings → click **Generate demo project**.
4. Save the project (`Ctrl+S`) so the manifest CSV is written to the project folder.

---

## Step 2 — Capture video from a modern engine

**Recommended setup:**
- Engine: RB3 Deluxe / YARG / RBHP Onyx / emulator at ≥ 1080p.
- Recorder: OBS Studio at **≥1080p60**, lossless (FFV1/UT) or high-bitrate H.264 (~50 Mbps).
- **One representative venue, fixed framing.** Lighting and postproc effects render differently across venues — document which venue was used and keep it consistent for all passes.
- **Disable HUD / debug overlays** so only the concert stage is visible.

**Alignment:**
- Load the generated chart in the engine.
- Start OBS recording, then start playback from t=0.
- The "SYNC FLASH" marker at t=0 corresponds to the very start of playback. The orange REAPER marker is your reference — frame 0 of the recording = t=0.
- If the engine has a pre-roll delay, add that offset when cutting windows (or note it in the manifest).

**One capture file per pass** (Camera, Lighting, each PostProc-with-lighting variant).

---

## Step 3 — Convert video to spritesheets

**Prerequisites:** `ffmpeg` in PATH (the `tile` video filter is used in a single-pass extraction).
Install from https://ffmpeg.org/ or via `winget install ffmpeg`.

### 3a — Run the extraction script

`extract_spritesheets.ps1` (in this folder) automates the full process.
It knows the event order for each mode internally, so no manifest CSV is required.

```powershell
# Camera mode
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 4.12 -Mode camera

# Lighting mode
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 4.12 -Mode lighting

# PostProc mode
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 4.12 -Mode postproc

# With HUD crop (W:H:X:Y) -- trim 96px left/right and 54px top/bottom from 1920x1080
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 4.12 -Mode camera -Crop "1728:972:96:54"

# Non-default window size (must match what was set in the demo tool)
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 6.03 -Mode postproc -WindowSec 6.0
```

**`-FirstEventSec`:** the time in the video (in seconds) when the camera cuts away from the
`[coop_d_closeup_head]` pre-roll to the first cycling event. Scrub the video in VLC/mpv
and note the timestamp of that cut. This is the sync anchor; all subsequent windows are
derived automatically as `FirstEventSec + slot × WindowSec`.

**Output location:** `img/spritesheets/{camera|lighting|postproc}/` at the repo root
(three levels up from this script). Override with `-OutDir path`.

**Lighting mode variants:** each preset produces multiple sub-windows (far/near, 1beat/2beat
for manual presets). All variants are extracted with descriptive names
(e.g. `verse_far_1beat_spritesheet.png`). The script also automatically copies the
`far + 1beat` variant (or `far` for auto presets) to the canonical integration name
(e.g. `verse_spritesheet.png`). To use a different variant, copy the preferred file
over the integration-name file.

### 3b — How the single-pass extraction works

The script runs one `ffmpeg` call per event window:

```
ffmpeg -ss {t_start} -t 2.4 -i capture.mkv
       -vf "fps=30, scale=426:240, tile=8x9:padding=0:color=black"
       -frames:v 1  output_spritesheet.png
```

- `-ss` before `-i`: fast input-side seek to the window start (accurate enough for fixed-BPM sources).
- `fps=30`: re-samples to exactly 30fps so the tile always has the right frame density.
- `scale=426:240`: scales each frame to the 2× tile size.
- `tile=8x9`: collects 72 frames (2.4 s × 30 fps) and assembles them into the 3408×2160 sheet in one pass.
- Black padding fills any unused cells at the end. `DetectFrameCount` in `venue_sprites.lua` auto-detects the first all-black cell and caps the animation loop accordingly.

### 3c — Loop crossfade (`-FadeSec`)

Optional loop smoothing, off by default (`-FadeSec 0`). When set, it is a **self-contained** centered
seam crossfade: the clip's own last `D` frames are overlapped (faded out) onto its own first `D`
frames, and the blend is then centered on the loop seam. It **never reads past the loop point**, so a
precise shot that cuts to a different camera right after its window never has that next shot leak in.

```powershell
# 6-frame (0.2 s at 30 fps) self-contained centered seam dissolve
.\extract_spritesheets.ps1 -Video capture.mkv -FirstEventSec 4.12 -Mode camera -FadeSec 0.2
```

**Frame accounting (important).** The overlap *consumes* the fade length, so `-TileCount` is the
number of frames **captured** and the **played** count (filename `f{n}`, grid rows) is
`TileCount − fadeFrames`:

- To keep a target played length on a clip that has spare footage, raise `-TileCount` by the fade
  length: `-TileCount 126 -FadeSec 0.2` → **120** played frames (the same result as a plain
  `-TileCount 120` with no fade, but now seamless).
- A precise shot with no spare footage just yields a slightly shorter loop:
  `-TileCount 36 -FadeSec 0.2` → **30** played frames (`ddrums_f30_…`). The grid pads the unused
  cells black as usual.

How it works (the filter switches from `-vf` to `-filter_complex`):
- Reads exactly `-TileCount` frames (no extra footage).
- **Overlay**: the clip's own tail (`trim=start_frame=OutCount`, last `D` frames, faded out) is
  composited onto its own head; the body is trimmed to `OutCount = TileCount − fadeFrames`.
- **Rotate**: that loop is split and re-concatenated shifted by `D/2` frames so the blend straddles
  the seam (centered) rather than sitting at the start. Rotating a loop's phase is harmless since it
  plays continuously. A very small `-FadeSec` (under ~2 frames) skips the rotation.
- Recommended range: 0.1–0.4 s (3–12 frames). Longer than ~0.33 s starts to read as a deliberate
  effect rather than seam smoothing.

Honest caveat: each clip is a slice of continuous gameplay, not a purpose-built loop, so its start
and end genuinely differ. The crossfade minimizes the seam — it cannot make the two ends identical.

---

## Step 4 — Install and verify

1. Place all generated `*_spritesheet.png` files into the repo under:
   ```
   Spritesheets/
     Camera/
       dall_spritesheet.png
       dallcam_spritesheet.png
       ...
     Lighting/
       loopwarm_spritesheet.png
       verse_spritesheet.png
       ...
     PostProc/
       profilma_spritesheet.png
       bloom_spritesheet.png
       ...
   ```
2. Launch `rock_band_general_helper_vkr.lua` in REAPER.
3. Open the **Venue** tab → **Section gen** sub-tab.
4. Hover each lighting, post-proc, and directed-cut combo entry — confirm animated previews appear, loop correctly at 30 fps, and match the expected event visually.
5. Confirm back-compat: with the `Spritesheets/` folder absent but FCP installed, legacy 213×120 FCP sheets still render (the loader falls back to FCP automatically). With neither present, tooltips show text-only with no errors.

---

## Helper scripts (this folder)

All scripts default their paths relative to their own location so they can be
run from any working directory without `-Path` / `-Root` arguments.

### `extract_spritesheets.ps1`
The main extraction tool. Slices a captured video into named spritesheet PNGs/JPEGs
using `ffmpeg`. Knows the full event order for camera, coop, lighting, and postproc
modes internally — no manifest CSV required. Supports batch mode (all events in one
run) and single-shot mode (`-EventName`) for re-extracting one event at a specific
timestamp. See the `.SYNOPSIS` block inside the script for the full parameter reference.

### `run_spritesheet_batch.ps1`
Reads a plain-text command file (one `extract_spritesheets.ps1` invocation per line,
`#`-prefixed lines ignored) and runs them sequentially, printing per-command timing
and a pass/fail summary. Sets the working directory to the command file's folder so
relative video paths in the command file resolve correctly.

```powershell
.\run_spritesheet_batch.ps1 -CommandFile commands.txt
.\run_spritesheet_batch.ps1 -CommandFile commands.txt -StopOnError
```

### `compact_alt_spritesheets.ps1`
Fixes gaps in alt-variant numbering after deleting a take. Walks the spritesheet tree
and renames files so alt slots are contiguous from 2 upward with no holes. Supports
PNG (`{norm}_alt{N}_spritesheet.png`) and JPEG (`{norm}_alt{N}_f{count}_spritesheet.jpg`).

```powershell
.\compact_alt_spritesheets.ps1 -WhatIf          # preview
.\compact_alt_spritesheets.ps1                   # apply
.\compact_alt_spritesheets.ps1 -Path '..\..\img\spritesheets\camera'
```

### `archive_alt_spritesheets.ps1`
Moves all `_alt{N}` and `_near` variant spritesheets out of the integration folder
(`img/spritesheets/`) into a sibling archive folder (`img/spritesheets alts/`),
preserving the sub-directory structure. Useful for keeping the integration folder
clean while retaining alternate takes for future use.

```powershell
.\archive_alt_spritesheets.ps1 -WhatIf          # preview
.\archive_alt_spritesheets.ps1                   # apply
```

### `clean_spritesheet_extras.ps1`
Removes JPEG spritesheet files whose normalised key is not in the canonical event
list for their category folder. These are the exact files the **Spritesheet Coverage**
test (`tests/run_spritesheet_coverage.lua`) reports as `FAIL` — leftover alts,
renamed copies, or files with typos that survived compaction.

```powershell
.\clean_spritesheet_extras.ps1 -WhatIf          # preview (default-safe)
.\clean_spritesheet_extras.ps1                   # delete
```

---

## PostProc × Lighting combinations

To capture every .pp effect under multiple lighting presets:
1. In the demo tool, select **PostProc** mode.
2. Set **Lighting** to the desired neutral lighting preset (e.g. Frenzy).
3. Generate → capture → convert. Manifest file is named `demo_manifest_postproc_frenzy.csv`.
4. Repeat for each lighting preset of interest.

Each combination set produces its own spritesheet folder or can be filed under a sub-folder (e.g. `PostProc/frenzy/`). The loader currently searches only `PostProc/`; if you want selectable variant sets, a future UI addition is needed.
