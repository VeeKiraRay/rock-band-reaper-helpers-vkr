# Rock Band Authoring Tools — Project Documentation

Two REAPER ReaScript (Lua) tools for Rock Band audio authoring, sharing a common `lib/` folder.

| Script | Purpose |
|---|---|
| `rock_band_vocal_helper_vkr.lua` | MIDI note generation from vocal audio — syllable detection, pitch assignment, lyrics |
| `rock_band_general_helper_vkr.lua` | Tempo map generation from drum audio, audio alignment, VENUE event validation |

**Read the script-specific file before making changes:**
- Working on `rock_band_vocal_helper_vkr` → read `CLAUDE_vocal.md`
- Working on `rock_band_general_helper_vkr` → read `CLAUDE_general.md`

This file documents shared runtime, architecture, and conventions only.

---

## Runtime requirements

Both scripts require **REAPER 6.x or later** and **ReaImGui 0.7 or later**. Each entry point validates both at startup:

```lua
if not r.ImGui_CreateContext then   -- extension missing entirely
    r.ShowMessageBox(...); return
end
if not r.ImGui_BeginDisabled then   -- extension pre-0.7
    r.ShowMessageBox(...); return
end
```

The 6.x floor is set by ReaImGui's own requirements. All REAPER core APIs (audio accessor, MIDI events, `new_array`) have been available since REAPER 5.x.

**Versioning.** Entry point header carries `@version`. Bump it whenever behavior or UI changes meaningfully. Document changes in the `@about` block.

---

## Shared architecture

### `dofile` module system

Each entry point loads sibling module files in dependency order. All modules run in one shared global Lua environment — `r`, `ctx`, `S`, `TIPS`, and all cross-file functions are globals. File-private helpers stay `local`.

### Entry point path derivation

```lua
r = reaper  -- global (no local) so all dofile'd modules can use r.*
ctx = r.ImGui_CreateContext('Window Title')  -- global

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'

dofile(_dir  .. 'lib/reaper_imgui_helpers.lua')   -- shared lib
dofile(_dir  .. 'lib/reaper_dsp.lua')
dofile(_dir  .. 'lib/reaper_midi_helpers.lua')
dofile(_mdir .. 'defaults.lua')                   -- script-specific modules
-- ...
```

`_dir` = repo root (shared lib location). `_mdir` = `{repo root}/{script basename}/`. Renaming an entry point requires renaming its subfolder — intentional.

### Shared lib (`lib/`)

| File | Contents |
|---|---|
| `lib/reaper_imgui_helpers.lua` | `PitchName`, `Tooltip`, `SliderTooltip`, `SectionHeader`, `GetTrackList`, `TrackCombo`, `FormatTime`, `GetTimeSelection` |
| `lib/reaper_dsp.lua` | `ComputeRMSContour`, `OpenYINContext`, `DetectPitchYIN`, `SampleYINAt`, `GateAndSplit`, `ApplyMinOffset` |
| `lib/reaper_midi_helpers.lua` | `FindMIDIItem`, `FindFirstMIDIItem`, `ReadAllMIDINotesOnTrack`, `ClearNotesAtPitchesInRange`, `InsertNotes`, … |

### Global vs local function rules

Functions called from another file: define without `local`. Functions used only within their own file: keep `local`. See the script-specific CLAUDE file for the local-only function lists.

---

## Conventions

### Naming
- `r = reaper` set in entry point (no `local`) — all modules use `r.*`, never `reaper.X`
- Functions: `PascalCase` (`Generate`, `AssignPitches`, `SetDefaultTracks`)
- Local variables: `snake_case` (`range_info`, `midi_take`, `ref_notes`)
- Module-level tables and constants: `ALL_CAPS` (`S`, `DEFAULTS`, `TIPS`, `MODE_*`)

### State table (`S`)
- Single source of mutable state per script, defined in `defaults.lua`
- Sliders write directly: `_, S.field = r.ImGui_SliderXxx(...)`
- `S.status` — one-line string shown in the status bar
- `S.last_result` — `\n`-separated multi-line detail, or `nil` to clear

### Tooltips
- All tooltip text in `TIPS` table in `defaults.lua`. UI references `TIPS.foo` — never inline strings.
- Sliders: `SliderTooltip(TIPS.foo)` (appends Ctrl+click hint automatically)
- Buttons: `Tooltip(TIPS.foo)` (no hint)

### Result reporting
- Empty lines in `S.last_result` render as `r.ImGui_Spacing` — use for visual breathing room
- New stats: append to a `lines` table, then `table.concat(lines, '\n')`

### Undo blocks

For MIDI edits, `MarkTrackItemsDirty` is **required** inside the block — REAPER's MIDI
functions do not mark the take dirty, so without it the undo entry is silently dropped.
`MarkProjectDirty` and `UpdateArrange` do **not** fix this. See `CLAUDE_undo_fix.md`.

```lua
r.PreventUIRefresh(1)
r.Undo_BeginBlock2(0)
r.MarkTrackItemsDirty(track, item)   -- REQUIRED for any MIDI_* edit
--   local item  = r.GetMediaItemTake_Item(take)
--   local track = r.GetMediaItemTake_Track(take)
-- ... MIDI_InsertNote / MIDI_DeleteNote / MIDI_InsertTextSysexEvt / etc. ...
-- Use noSort=false on inserts; no MIDI_Sort needed.
r.Undo_EndBlock2(0, 'Descriptive label (N items)', -1)
r.PreventUIRefresh(-1)
```

For non-MIDI edits (track state, markers, tempo map) `MarkTrackItemsDirty` is not needed.

### Error handling
- Functions that can fail: `return nil, error_string`
- Errors surface via `S.status` and `S.last_result`. Never call `error()` or `ShowMessageBox` from action functions.

### Button widths
```lua
local _bp  = 40   -- ~20 px padding each side
local bw_x = r.ImGui_CalcTextSize(ctx, 'Label') + _bp
```
Compute all widths together near the top of `if visible then`. Never hardcode pixel values.

### `BeginDisabled` / `EndDisabled` balance
Snapshot any state flag that drives a `BeginDisabled` guard once before widget calls — a button click mid-frame can change `S.busy`, breaking the paired `EndDisabled`:
```lua
local is_busy = S.busy   -- snapshot once
if is_busy then r.ImGui_BeginDisabled(ctx) end
-- ... widgets ...
if is_busy then r.ImGui_EndDisabled(ctx) end
```

### Time selection as scope
Actions respect time selection when active; fall back to whole-item or whole-track defaults otherwise. This is the primary iteration mechanism — work one section at a time.

### Smart default track selection
Each script implements `SetDefaultTracks` (or equivalent): runs at startup and on project switch, matches tracks by name, verifies track content (audio vs MIDI), falls back to index 0 if nothing matches.

### Project-switch detection
`Loop` caches the current project pointer and checks `r.EnumProjects(-1, '')` each frame. On mismatch: reset track indices, call `LoadSettings`, re-run smart defaults, update `S.status`. Ensures no state from the previous project leaks.

### Settings save/load
`SetProjExtState` / `GetProjExtState` under a script-specific section key. Format: semicolon-separated `key=value`. `DeserializeSettings` parses each field independently — missing fields keep their current value. Track indices are **not** saved (positional, brittle across sessions).

---

## Lua specifics (REAPER)

- `reaper.new_array(n)` for sample buffers. 1-based indexing. Does **not** work inside Lua coroutines — REAPER restriction.
- `GetAudioAccessorSamples` also fails in coroutines for the same reason. Both must run on the main Lua thread.
- `MIDI_GetNote` returns `(ok, sel, mute, sppq, eppq, chan, pitch, vel)`. Use named locals.
- `MIDI_CountEvts(take)` returns `(retval, notecnt, ccevtcnt, textsyxevtcnt)` — **fourth** value is text/sysex count (third is CC count, a common mistake).
- `MIDI_GetTextSysexEvt(take, i)` returns `(ok, sel, mute, ppq, type, msg)`. Type 5 = lyric.
- After `MIDI_DeleteNote` / `MIDI_DeleteTextSysexEvt`: indices of remaining events shift — **iterate in reverse** when deleting.
- Use `noSort=false` on `MIDI_InsertNote` / `MIDI_InsertTextSysexEvt` — no `MIDI_Sort` needed and it avoids breaking undo detection.
- `format_timestr_pos(tpos, '', 1)` → measures/beats string e.g. `"90.1.00"`. Parse leading integer for the measure number.
- Audio accessor: always free with `DestroyAudioAccessor`. Leaking holds file handles open indefinitely.

---

## File layout

```
[repo root]/
  lib/                                       ← shared by both scripts
    reaper_imgui_helpers.lua
    reaper_dsp.lua
    reaper_midi_helpers.lua

  rock_band_vocal_helper_vkr.lua             ← entry point (only file users run)
  rock_band_vocal_helper_vkr/
    defaults.lua     helpers.lua     pipeline.lua
    settings.lua     autotune.lua    actions.lua    ui.lua

  rock_band_general_helper_vkr.lua           ← entry point (only file users run)
  rock_band_general_helper_vkr/
    defaults.lua     helpers.lua     venue.lua
    settings.lua     tempomap.lua    actions.lua    ui.lua

  CLAUDE.md           ← this file (shared conventions)
  CLAUDE_vocal.md     ← vocal helper details
  CLAUDE_general.md   ← general helper details
```

Module file contents and load orders are in the script-specific CLAUDE files.

---

## Glossary

- **Stem** — isolated audio track from a mix (vocal stem, kick stem, etc.)
- **RMS** — root mean square of signal in a window; perceived loudness proxy
- **PPQ** — REAPER's MIDI tick unit. Convert: `MIDI_GetPPQPosFromProjTime` / `MIDI_GetProjTimeFromPPQPos`
- **Take** — recording or MIDI clip inside a media item. Use the active take for note operations.
- **Audio accessor** — REAPER API for reading PCM samples. Create: `CreateTakeAudioAccessor`. Always free: `DestroyAudioAccessor`.
- **YIN** — monophonic pitch detection algorithm based on the cumulative mean normalized difference function (CMND). Finds the fundamental frequency by searching for the period (lag) that minimizes the difference function, with parabolic interpolation for sub-sample precision.
