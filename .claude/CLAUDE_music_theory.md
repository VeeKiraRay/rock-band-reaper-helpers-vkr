# Rock Band Music Theory Helper — Script Documentation

Entry point: `rock_band_music_theory_helper_vkr.lua`
Module folder: `rock_band_music_theory_helper_vkr/`

---

## Module table

| File | Role |
|---|---|
| `defaults.lua` | Global data tables: `DRUM_NOTATION`, `RB_LANE_COLORS`, `PRO_VS_4LANE`, `DRUM_PATTERNS`, `GUITAR_CHORDS`, `GUITAR_LANE_TERMS`. Also defines the minimal `S` and `TIPS` globals required by shared conventions. |
| `ui.lua` | `Loop` function, tab bar, per-instrument render functions. Calls `r.defer(Loop)` to start the script. |
| `lib/reaper_guitar_theory.lua` (shared, not in this module folder) | Pure fret-shape classification: `GuitarParseFretInput`, `GuitarClassifyChordType`, `GuitarSuggestRBMapping`, `GuitarAnalyzeShape`. No `r`/`ctx`/`S` dependency — see "Adding a new instrument tab" below for when logic like this belongs in `lib/` instead of the module folder. |

Load order in entry point:
```
lib/reaper_imgui_helpers.lua   (SectionHeader, Tooltip)
lib/reaper_guitar_theory.lua   (pure guitar shape/chord classification)
rock_band_music_theory_helper_vkr/defaults.lua
rock_band_music_theory_helper_vkr/ui.lua
```

No `settings.lua`, `helpers.lua`, or `actions.lua` — this is a read-only reference tool.

---

## Content data convention

All reference content lives as Lua tables in `defaults.lua`, not inline in `ui.lua`. This keeps rendering logic generic (loop over table, render rows) and makes content edits cheap — no need to touch layout code.

Each instrument section gets its own named table(s). Current tables:

| Table | Description |
|---|---|
| `DRUM_NOTATION` | Rows: `symbol`, `name`, `rb_4lane`, `rb_pro` |
| `RB_LANE_COLORS` | Rows: `color`, `piece` — currently empty; see [`_future_ideas/music_theory_drum_colors.md`](_future_ideas/music_theory_drum_colors.md) |
| `PRO_VS_4LANE` | Array of plain strings (bullet list) — currently empty; see [`_future_ideas/music_theory_pro_vs_4lane.md`](_future_ideas/music_theory_pro_vs_4lane.md) |
| `DRUM_PATTERNS` | Rows: `name`, `desc` |
| `GUITAR_CHORDS` | Rows: `shape`, `type`, `sound`, `rb_mapping` — see `lib/reaper_guitar_theory.lua`'s header comment for how these were converted/verified from `_future_ideas/GUITAR_THEORY.md` |
| `GUITAR_LANE_TERMS` | Rows: `width`, `combos` — RB lane-combo letter names (GR/RY/... ) per spread width |

---

## Adding a new instrument tab

1. Add content tables to `defaults.lua` following the existing naming pattern (e.g., `GUITAR_CHORDS`, `GUITAR_LANE_TERMS`).
2. Add a `local function DrawGuitarTab()` in `ui.lua` that loops over those tables.
3. Add a `BeginTabItem('Guitar')` block inside the `BeginTabBar` in `Loop`, calling `DrawGuitarTab()`.

No other files need changing — **unless** the tab needs reusable classification
logic rather than plain lookup data (Drums is pure lookup; Guitar's shape
search needed real computation: fret parsing, interval math, chord-template
matching). That kind of logic belongs in its own `lib/` file (see
`lib/reaper_guitar_theory.lua`), not the module folder — it keeps the
function pure (no `r`/`ctx`/`S`), testable standalone, and reusable by other
scripts later (the Guitar tab's classifier is intentionally reusable by
`rock_band_general_helper_vkr`'s Guitar-tab converters in a future task).

---

## Audio playback (implemented)

Audio playback is implemented via the SWS extension's `CF_CreatePreview` API. No VSTi or plugin required beyond SWS.

### How it works

`PlayDrumWAV(img_idx_or_row)` in `ui.lua` — global, called when the user hovers+clicks a row in the drum notation table. Stops any current preview, then starts a new one for the sample file corresponding to that row.

`PlayAudioFile(filename)` — local helper. Creates a `CF_CreatePreview` handle and starts it:
```lua
local src    = r.PCM_Source_CreateFromFile(path)
local handle = r.CF_CreatePreview(src)
r.CF_Preview_SetValue(handle, 'B_LOOP', 0)
r.CF_Preview_Play(handle)
S.preview_src = handle
S.preview_pcm = src
```

`StopCurrentPreview()` — local helper. Stops and frees the handle before starting a new one.

**Burst playback** (`S.burst_files`, `S.burst_idx`, `S.burst_next_t`) — for multi-sample patterns (e.g. a drum roll), `PlayDrumWAV` fills `burst_files` with a list of sample filenames and sets a timer. `Loop` fires successive samples by checking `r.time_precise()` against `burst_next_t`.

### State fields

| Field | Type | What it holds |
|---|---|---|
| `S.hovered_drum_idx` | int or nil | 0-based image column index; set each frame by hover detection |
| `S.preview_src` | handle | Active `CF_Preview` handle; nil when idle |
| `S.preview_pcm` | handle | Backing `PCM_Source*` for the current preview |
| `S.burst_files` | table or nil | `{filename, …}` array for multi-sample burst playback |
| `S.burst_idx` | int | Next index into `burst_files` (1-based) |
| `S.burst_next_t` | float | `r.time_precise()` timestamp for the next burst hit |

### Audio pack location

Sample files are expected in the `audio/` subfolder next to the entry point. The script checks at startup whether `audio/` exists and gracefully disables playback if it does not (no error, just no audio feedback). This keeps the base install usable without the optional audio pack.

### Option A (not used): MIDI via system synth

Documented here for reference in case SWS is unavailable:

```lua
-- Drum hit on MIDI channel 10 (0x99), GM pitch 38 = snare
reaper.StuffMIDIMessage(0, 0x99, 38, 100)
```

Routes through whatever MIDI output device is active (typically Microsoft GS Wavetable Synth). Zero dependencies, lower sample quality.

---

## Versioning note

Bump `@version` in the entry point whenever content changes meaningfully (new instrument tab, significant content corrections). The `@about` block should summarize what instruments/sections are covered.
