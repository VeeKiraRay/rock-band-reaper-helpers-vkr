# Rock Band Authoring Tools — Project Documentation

Two REAPER ReaScript (Lua) tools for Rock Band audio authoring, sharing a common `lib/` folder.

| Script | Purpose |
|---|---|
| `rock_band_vocal_helper_vkr.lua` | MIDI note generation from vocal audio — syllable detection, pitch assignment, lyrics |
| `rock_band_general_helper_vkr.lua` | Tempo map generation from drum audio, audio alignment, VENUE event validation |

**Read the script-specific file before making changes:**
- Working on `rock_band_vocal_helper_vkr` → read `.claude/CLAUDE_vocal.md`
- Working on `rock_band_general_helper_vkr` → read `.claude/CLAUDE_general.md`
- Working on `rock_band_music_theory_helper_vkr` → read `.claude/CLAUDE_music_theory.md`

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

Note: the 0.7 floor is nominal — sprite tooltips and image loading already use v0.8 APIs behind pcall guards, so those features are silently absent on 0.7 rather than breaking the script. Any new use of a post-0.7 API must follow the same pattern until the declared floor is raised.

**Versioning.** Entry point header carries `@version`. Bump it whenever behavior or UI changes meaningfully. Document changes in the `@about` block.

Each window shows that version in its title bar, so a bug report carries it without the user having to look anything up. The entry point builds the title with `ScriptWindowTitle(name, _script)` (`lib/reaper_imgui_helpers.lua`), which reads the `@version` line out of the running script's own header — the version string is never duplicated into code, so it cannot drift from the header. The result is passed to `ImGui_Begin`, either as the global `WINDOW_TITLE` (helpers whose `Begin` lives in a `ui.lua`) or as a file-local `_title` (standalone windows that draw in the entry point).

The returned string ends in `###<name>`, and that suffix is load-bearing rather than cosmetic: ImGui derives a window's identity from its `Begin` label, so without a stable id after `###` every version bump would read as a brand-new window and reset the user's saved size, position and dock state. The id is the bare window name — exactly what the label used to be, so existing windows keep their geometry. **Never change an existing window's `###` id.** `ImGui_CreateContext` labels stay version-free for the same reason: ReaImGui keys per-context saved state off that name.

**Bumping a helper means checking its standalones.** Three windows ship as their own entry points but own almost no code: `rock_band_preview_vkr.lua` and `rock_band_midi_pattern_vkr.lua` draw modules out of `rock_band_general_helper_vkr/`, and `rock_band_pitch_tuner_vkr.lua` draws them out of `rock_band_vocal_helper_vkr/`. A fix in one of those shared modules changes what the standalone does **without touching the standalone's own file**, so its `@version` silently stops describing the code it runs.

So whenever you bump a helper's `@version` and write its `@about` entry, finish the job:

1. Check each standalone's load list — the `_files` table in its entry point, also written out in `.claude/CLAUDE_general.md` and `.claude/CLAUDE_vocal.md` under "Second/Third entry point". This is a lookup, not a judgment call: if a file you changed is in the list, that standalone is affected.
2. Bump that standalone's `@version` too, in the same task.
3. Give it its **own** `@about` entry describing the change from that window's point of view — not a copy of the helper's wording. The helper's entry may say "Venue > Preview sub-tab now ..."; the standalone's says what its window now does. Cross-referencing the helper version it shipped alongside is useful (`rock_band_preview_vkr.lua` v0.4 does this) but is not a substitute for saying what changed.

A change that touches only files outside every standalone's list (a venue generator, a difficulty model, a tab the standalone has no equivalent of) affects none of them, and bumping them anyway would be churn — the entry would have nothing true to say.

**Changelog / `@about` trimming.** Each entry point's `@about` block keeps only its **5 most recent** version entries (newest first, as today). When adding a new version entry pushes the count to 6, move the oldest of the 5 previously-kept entries out to `CHANGELOG.md` at the repo root — don't let `@about` grow unbounded, since it's read in-app (REAPER's script info / ReaPack "about" panel) where a long scroll of old history isn't useful.

- `CHANGELOG.md` has one `##` section per entry-point script (its display name, e.g. `## Rock Band General Helper`), each section's entries in the same newest-first order as `@about`. The entry being moved out goes at the **top** of its script's section (it's the newest entry in that file, even though it's the oldest one leaving `@about`).
- `@about` gets a one-line pointer right after the intro/`Built with Claude` text and before the version entries: `This @about block keeps only the 5 most recent versions.` / `Full history: CHANGELOG.md in the repo.`
- A script with 5 or fewer versions total (e.g. `rock_band_preview_vkr.lua`, `rock_band_music_theory_helper_vkr.lua` as of this writing) doesn't need the pointer line or a `CHANGELOG.md` section yet — add both the first time it overflows.

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
| `lib/reaper_imgui_helpers.lua` | `PitchName`, `Tooltip`, `SliderTooltip`, `ScriptWindowTitle`, `Btn`, `BtnWidth`, `BtnGroupWidth`, `LabelColWidth`, `RadioGroupWidth`, `SectionHeader`, `SortedByLabel`, `ComboGroupHeader`, `GetTrackList`, `TrackCombo`, `FormatTime`, `GetTimeSelection` |
| `lib/reaper_dsp.lua` | `ComputeRMSContour`, `OpenYINContext`, `YINWindowSize`, `ReadMonoWindow`, `QuickRMS`, `ComputeCMND`, `SearchYINTau`, `MedianVote`, `DetectPitchYIN`, `SampleYINAt`, `GateAndSplit`, `ApplyMinOffset` |
| `lib/reaper_midi_helpers.lua` | `FindMIDIItem`, `FindFirstMIDIItem`, `ReadAllMIDINotesOnTrack`, `ClearNotesAtPitchesInRange`, `InsertNotes`, … |
| `lib/reaper_guitar_theory.lua` | `GuitarShapeToPitches`, `GuitarNormalizeIntervals`, `GuitarClassifyChordType`, `GuitarSuggestRBMapping`, `GuitarAnalyzeShape`, `GuitarParseFretInput`, `GuitarAnalyzeShapeAllTunings` — pure, no `r`/`ctx`/`S` |
| `lib/reaper_music_notation.lua` | Staff notation model: `NOTATION_CLEFS`, `KEY_SIGNATURES`, `NotationStepToNatural`, `NotationStepToPitch`, `NotationNoteName`, `NotationKeySigAlteration(s)`, `NotationSoundingStep`, `NotationKeySigSlots`, `RBPitchName`, `PianoKeyLayout` — pure, no `r`/`ctx`/`S` |
| `lib/reaper_script_links.lua` | `SCRIPT_LINK_GROUPS`, `ScriptLinkBasename`, `IsRunningScriptLink`, `FilterScriptLinkGroups`, `LaunchReaScript`, `DrawGeneralLinksTab` — the General > Other tools sub-tab, shared by both helpers |
| `lib/reaper_karplus_strong.lua` | `KarplusStrongVoice`, `SynthesizeChordSamples`, `SYNTH_TONES`, `SYNTH_TONE_ORDER`, `SynthToneOpts`, `SynthTonesInFamily` — struck/plucked-string synthesis and its per-instrument tone presets, for chord audition |
| `lib/reaper_difficulty_score.lua` | `ScoreChart`, `SCORE_FACTOR_KEYS`, `NormalizeSpans`, `EventsInSegments`, `DeriveSpansFromEvents`, `ProRemapEvents`, `Percentile`, `TotalSpanSeconds`, `SpanOverlapSeconds` — chart difficulty factors for guitar/bass/drums/keys/Pro Keys. Pure, no `r`/`ctx`/`S` |
| `lib/reaper_difficulty_score_vocals.lua` | `ScoreVocalChart`, `NormalizeVocalPhrases`, `VocalClassifyLyric`, `VocalPitchClassDistance`, `VocalNoteIsPitched`, `VocalSubtractPercussion` — the vocal factor set. Pure. **Load after `reaper_difficulty_score.lua`**: it uses that file's span helpers and appends its columns to `SCORE_FACTOR_KEYS` |
| `lib/reaper_difficulty_tiers.lua` | `RANK_TIER_THRESHOLDS`, `TIER_NAMES`, `TierForRank`, `TierName`, `TierBand`, `TierPosition` — rank to displayed tier (0 Warmup … 6 Impossible), from `_external_docs/InstrumentDifficulty.ts`. Pure. **Both open-ended bands are closed by the model, not the tier table**: tier 6 by `rank_hi`, tier 0 by `rank_lo`. Measured from rank 1 instead, every floor-clamped Warmup chart computed 0.85–0.97 and read as almost-Apprentice while having fallen off the *bottom* of the scale (drums: 97% of a 1–124 band whose model floor is 120). Both args are optional and omitting them keeps the tier table's own 1-and-infinity |
| `lib/reaper_difficulty_predict.lua` | `DIFFICULTY_SCALE_INV`, `DifficultyModelInputs`, `DifficultyPredictRank`, `DifficultyFactorZ`, `DifficultyOutOfRange` — how to apply a frozen model. Pure. Coefficients are in **standardized** units, so nothing may apply them by hand |
| `lib/reaper_difficulty_models.lua` | **Generated** — `RB_DIFFICULTY_MODELS`, `RB_DIFFICULTY_MODEL_ORDER`, `RB_DIFFICULTY_MODELS_SCHEMA`. The six frozen fitted models. The file states its own format version in `RB_DIFFICULTY_MODELS_SCHEMA`, which is the only place to read it — a copy quoted here drifts the first time the exporter bumps it. Carries coefficients, standardization stats, rank clamp, per-factor `bounds`, concentration thresholds, and `corr` (pairwise factor correlations at \|r\| ≥ 0.70, used to stop the explanation panel restating one observation twice). Rewritten only by `dev/calibration/export_production_models.lua`; never hand-edit |
| `lib/reaper_wav_writer.lua` | `WriteMonoWAV16` |

The three `reaper_difficulty_*` modules are shared with the calibration harness in
`dev/calibration/` rather than with a second shipped script — the one case where `lib/`
serves a dev consumer. That is deliberate and load-bearing: the fitted coefficients the
suggester ships only mean anything paired with the exact factor implementation they were
measured against, so a second copy would silently invalidate them. `dev/calibration/`
keeps one-line loaders at the old paths so its entry points need no edits. See
[`dev/calibration/README.md`](dev/calibration/README.md).

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

**Exception — shared `lib/` modules keep their own strings.** `TIPS` is
per-script (general helper: `defaults.lua`; vocal helper: `tips.lua`), so a
module in `lib/` that draws UI for *both* cannot read either one's table
without having the same strings copied into both files — which is precisely
the drift the convention exists to prevent. Such a module keeps its tooltip
text beside the data it describes: `lib/reaper_script_links.lua` builds each
tooltip from its own registry entry's `desc`. The same pattern appears inside
a script where a string belongs to a pool rather than to a widget —
`DIRECTED_TIPS` lives in `venue_camera.lua`, not in `TIPS`.

### Result reporting
- Empty lines in `S.last_result` render as `r.ImGui_Spacing` — use for visual breathing room
- New stats: append to a `lines` table, then `table.concat(lines, '\n')`

### Undo blocks

For MIDI edits, `MarkTrackItemsDirty` is **required** inside the block — REAPER's MIDI
functions do not mark the take dirty, so without it the undo entry is silently dropped.
`MarkProjectDirty` and `UpdateArrange` do **not** fix this — they mark the project, not the
take, and the undo system checks the take.

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
Use `Btn(label, height)` (from `lib/reaper_imgui_helpers.lua`) instead of a manual
`CalcTextSize` + `Button` pair — it sizes the button to its own label in one call,
so the label string appears once instead of twice (two copies of the same string
can silently drift out of sync when a label is renamed). Height should be the
shared `BTN_H` constant (`lib/reaper_imgui_helpers.lua`), not a bare `24` —
`BTN_H` is the one place that value lives, so every button stays in lockstep
if it ever changes:
```lua
if Btn('Label', BTN_H) then
    RunAction(SomeAction)
end
```
`Btn` strips any `##id` suffix before measuring, so id-suffixed buttons
(`'Refresh##vsec_refresh'`) still size to their visible text. Never hardcode
pixel values.

If you need the width *before* drawing (e.g. right-aligning a button via
`SetCursorPosX`), use `BtnWidth(label)` to get the same computed width without
drawing, then draw with `Btn` as normal:
```lua
local bw_und = BtnWidth('Undo')
-- ... position math using bw_und ...
if Btn('Undo', BTN_H) then r.Undo_DoUndo2(0) end
```

When several related buttons sit in a row (or block), give them a uniform
width with `BtnGroupWidth(labels)` — the widest label in the group, plus the
same padding `Btn` uses — instead of each button sizing to its own text:
```lua
local bw = BtnGroupWidth({ 'Save', 'Load' })
if Btn('Save', BTN_H, bw) then ... end
if Btn('Load', BTN_H, bw) then ... end
```

### Label column alignment
When a block of rows each pair a text label with an input (`Text` + `SameLine`
+ combo/slider/radio/checkbox), align the inputs with `LabelColWidth(labels)`
— the widest label in the group, plus padding — passed as the `col` arg to
`SameLine`, instead of hardcoding whichever label is presumed longest (that
assumption silently breaks alignment the day a longer label is added):
```lua
local lbl_col = LabelColWidth({ 'Source track', 'Reference track' })
r.ImGui_Text(ctx, 'Source track')
r.ImGui_SameLine(ctx, lbl_col)
-- ... combo ...
```
Shared row-drawing functions used by more than one tab (`RenderCamPacingRow`,
`RenderKeyframeAlignCombo`) take an optional `col_offset` param for this —
pass the caller's `lbl_col` through so the row joins that tab's alignment.

**Inside an `Indent`, add the row's own start.** `SameLine(ctx, x)` is measured
from the window's content edge and does **not** include `ImGui_Indent`, so a
bare `SameLine(ctx, lbl_col)` in an indented block leaves the label only
`lbl_col - indent` of room and the next widget overlaps the longest one. Read
the cursor before drawing the label and offset from there, which also survives
the block gaining or losing an indent level:
```lua
local row_x = r.ImGui_GetCursorPosX(ctx)   -- includes the current indent
r.ImGui_TextDisabled(ctx, label)
r.ImGui_SameLine(ctx, row_x + lbl_col)
```
`rock_band_general_helper_vkr/ui_metadata.lua` is currently the only file that
combines `Indent` with a label column — every other tab draws unindented, where
the two forms are identical.

### Radio button columns
`RadioButton` has no width parameter, so when a tab has multiple rows of
side-by-side radio options (e.g. "Preview size: 1x / 2x" and "Sprites:
Animated / Still"), the options don't line up unless each is explicitly
positioned. Use `RadioGroupWidth(labels)` — the widest option label in the
tab's group, plus padding — as a uniform per-option pitch, and position
option *i* (i ≥ 2) at `base + (i-1) * radio_w`, where `base` is that row's
own start (`0`, or its `lbl_col` if it has a row label):
```lua
local radio_w = RadioGroupWidth({ '1x', '2x', 'Animated', 'Still' })
r.ImGui_Text(ctx, 'Preview size')
r.ImGui_SameLine(ctx, lbl_col)
if r.ImGui_RadioButton(ctx, '1x##vpscl', ...) then ... end
r.ImGui_SameLine(ctx, lbl_col + radio_w)          -- option 2
if r.ImGui_RadioButton(ctx, '2x##vpscl', ...) then ... end
```
Only build a group where 2+ radio rows exist to align against each other in
the same tab view — a single isolated row has nothing to align. `SameLine(ctx,
x)` sets an *absolute* cursor position, so every option in the group
(including option 1) needs an explicit offset — leaving option 1 on a bare
`SameLine(ctx)` (natural flow after label text) while positioning option 2
with `SameLine(ctx, radio_w)` will misplace or overlap it, since `radio_w`
has no relationship to where the label pushed option 1.

### Fixed-width sliders and combos
Sliders and combo boxes should get an explicit
`r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)` (the standard width, `200`, defined
in `lib/reaper_imgui_helpers.lua`; the narrower `WIDTH_SHORT`, `80`, is used
for short selectors such as a note-name combo) immediately before the widget
call. Without it, ReaImGui defaults to filling the remaining line width, so
the control visibly stretches or shrinks as the user resizes the window —
inconsistent with every other sized element (`Btn`, `LabelColWidth`,
`RadioGroupWidth` all compute a fixed pixel width). Apply this to every
slider/combo, including ones that are the only widget on their line:
```lua
r.ImGui_Text(ctx, 'YIN threshold')
r.ImGui_SameLine(ctx, lbl_col)
r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
_, S.yin_threshold = r.ImGui_SliderDouble(ctx, '##yinthr', S.yin_threshold, 0.01, 0.5, '%.3f')
```
A row where a widget must share the line with something after it (e.g. a
slider followed by an enable checkbox) still uses `WIDTH_STD` — the fixed
width is what leaves room for the trailing widget in the first place. Use a
bare pixel literal only for a genuinely one-off, context-specific width (e.g.
a camera-pacing column) that isn't the shared convention.

### Wrapped text for descriptions and alerts
Any newly-added description, warning, or status text long enough to
plausibly exceed one line at a normal window width — a tab/section intro
sentence, a `TextDisabled` empty-state message, an inline warning — should
use `r.ImGui_TextWrapped` instead of `r.ImGui_Text` / `r.ImGui_TextDisabled`
from the start, so it flows to a new line instead of clipping when the
window is narrow (the same treatment the result panel already gets via
`PushTextWrapPos`/`PopTextWrapPos` in both `ui.lua` files). Reserve plain
`Text`/`TextDisabled` for short labels (section titles, single words, widget
labels) that aren't at risk of overflowing.

### `BeginDisabled` / `EndDisabled` balance
Snapshot any state flag that drives a `BeginDisabled` guard once before widget calls — a button click mid-frame can change `S.busy`, breaking the paired `EndDisabled`:
```lua
local is_busy = S.busy   -- snapshot once
if is_busy then r.ImGui_BeginDisabled(ctx) end
-- ... widgets ...
if is_busy then r.ImGui_EndDisabled(ctx) end
```

### UI consistency across scripts

When a UI change is generic — a shared widget pattern, a status-bar affordance, a track-selector behaviour — it must be applied to **every script and every tab** that is affected, not just the one where it was first added.

Before closing work on a UI change, ask:
- Does this pattern appear in the other helper(s)? If so, port it there too in the same task.
- Does it apply to all tabs within a script, or only the one currently being edited?

**Examples of changes that must be kept in sync across all helpers:**
- Bottom-panel undo button (added to vocal helper → must also appear in general helper, and any future helper).
- Track-selector pre-filtering (audio-only / MIDI-only lists, `RefreshTrackLists`, "Refresh tracks" button).
- Any new status-bar widget, keyboard shortcut, or window-level affordance.

If a sync to another script is out of scope for the current task, leave a TODO comment in the code and note it in the PR description — do not silently skip it.

### Time selection as scope
Actions respect time selection when active; fall back to whole-item or whole-track defaults otherwise. This is the primary iteration mechanism — work one section at a time.

### Smart default track selection
Each script implements `SetDefaultTracks` (or equivalent): runs at startup and on project switch, matches tracks by name, verifies track content (audio vs MIDI), falls back to index 0 if nothing matches.

### Project-switch detection
`Loop` caches the current project pointer and checks `r.EnumProjects(-1, '')` each frame. On mismatch: reset track indices, call `LoadSettings`, re-run smart defaults, update `S.status`. Ensures no state from the previous project leaks.

### Settings save/load
`SetProjExtState` / `GetProjExtState` under a script-specific section key. Format: semicolon-separated `key=value`. `DeserializeSettings` parses each field independently — missing fields keep their current value. Track indices are **not** saved (positional, brittle across sessions).

### File size and feature placement

Before appending a new feature to an existing file, ask:

- **Does it fit the file's existing scope?** `actions.lua` holds the detection pipeline and pitch logic. A lyrics utility doesn't belong there just because it's "also an action".
- **Is it self-contained?** A feature whose helpers, local functions, and public actions are only used with each other is a good candidate for its own file.
- **Good split candidates:** a complete tab's worth of actions, a self-contained algorithm, a new domain (harmonies, validation, lyrics) with no dependency on detection internals.

**Size guidelines:**

| File length      | Signal                                               |
|------------------|------------------------------------------------------|
| up to ~400 lines | Fine — no action needed                              |
| ~400–600 lines   | Consider: would a new feature fit better elsewhere?  |
| ~600–800 lines   | Actively evaluate splitting before adding more code  |
| 800+ lines       | Split is overdue; do it before the next feature      |

These are guidelines, not hard stops. Tightly coupled code that must share local helpers is better kept together even if it crosses 600 lines. But a file that is long *because it accumulated unrelated features* should be split — the coupling was coincidental, not structural.

**Why this matters:** reading a 1000-line file to make a 5-line edit loads unnecessary context and makes targeted changes expensive. Smaller, focused files are cheaper to reason about, cheaper to read, and cheaper to modify.

**After splitting:** update the script-specific CLAUDE file (module table, section order, load order) and add the new `dofile` line to the entry point.

---

## Testing

Tests live in `dev/tests/` and run **inside REAPER** (manually, with full access
to all REAPER APIs) — there is no headless runner. Launch them via the
`dev/test_rock_band_helpers_vkr.lua` button window, or run an individual
`dev/tests/run_*.lua` directly from the Actions list for an isolated Lua
context. Results print to the REAPER console.

Structure: `framework.lua` provides `Test.section` / `Test.it` / `Test.expect`
/ `Test.report`; `fixture_helpers.lua` provides fixture loading and temp-track
helpers; each suite is a `<name>.lua` test set plus a `run_<name>.lua` runner
that dofiles the code under test and the set.

**When adding a new feature, plan quick tests for it in the same task:**
- Add cases to the matching existing test set when one covers that area.
- Otherwise create a new set + `run_*.lua` runner (copy an existing runner's
  path-derivation preamble) and add a button for it in
  `dev/test_rock_band_helpers_vkr.lua`.
- Design for testability: keep UI/editor acquisition (active MIDI editor,
  edit cursor, `S` indices) in a thin wrapper and put the logic in a function
  taking explicit arguments (e.g. `VocalNoteSnapInTake(take, cursor, mode)`),
  so tests can drive it against a generated MIDI item without a MIDI editor.
- Tests must clean up any tracks/items they create (`CleanupFixture`).

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
- `CreateTakeAudioAccessor` returns an **item-relative** accessor. `GetAudioAccessorSamples` on such an accessor expects time in seconds from the **start of the take's source media**, not project time. Always convert: `t_off = project_time - item_pos` (where `item_pos = GetMediaItemInfo_Value(item, 'D_POSITION')`). Every function in `lib/reaper_dsp.lua` that reads a take accessor already does this (`DetectPitchYIN`, `SampleYINAt`, `ComputeRMSContour`). Any new audio analysis function must do the same — omitting this reads zeros for items not placed at project time 0, which is always the case for stems (they start at measure 3+). MIDI items are unaffected (their `item_pos` is always 0).

---

## File layout

```
[repo root]/
  lib/                                       ← shared by both scripts
    reaper_imgui_helpers.lua
    reaper_dsp.lua
    reaper_midi_helpers.lua
    reaper_guitar_theory.lua
    reaper_music_notation.lua                ← staff/clef/key-signature model
    reaper_script_links.lua                  ← General > Other tools sub-tab
    reaper_karplus_strong.lua
    reaper_difficulty_score.lua              ← chart difficulty factors; shared with
    reaper_difficulty_score_vocals.lua         dev/calibration/ so the shipped model and
    reaper_difficulty_tiers.lua                the fitted coefficients cannot drift apart
    reaper_difficulty_predict.lua            ← applies a frozen model
    reaper_difficulty_models.lua             ← GENERATED by the calibration exporter
    reaper_wav_writer.lua

  rock_band_vocal_helper_vkr.lua             ← entry point (only file users run)
  rock_band_vocal_helper_vkr/
    defaults.lua     helpers.lua     pipeline.lua
    settings.lua     autotune.lua    actions.lua    ui.lua

  rock_band_general_helper_vkr.lua           ← entry point (only file users run)
  rock_band_general_helper_vkr/
    defaults.lua     helpers.lua     venue.lua
    settings.lua     tempomap.lua    actions.lua    ui.lua
    ui_common.lua                            ← pieces shared with the standalone
    ui_midi_pattern.lua                        MIDI Pattern window (see below)
    difficulty_read.lua                      ← Metadata > Difficulty: chart readers
    difficulty_explain.lua                     (shared with dev/calibration/), wording,
    difficulty_report.lua                      the pasteable text report, the read-only
    difficulty_suggester.lua                   adapter, and the tab body
    metadata_genres.lua                      ← Metadata > Genre: supported vocabulary
    metadata_genres_ext.lua                    (transcribed), the authored extended
    metadata_genres_lookup.lua                 vocabulary + mapping, and the lookup
    ui_metadata_genre.lua                    ← Metadata > Genre tab body
    ui_metadata.lua                          ← Metadata tab shell (Genre + Difficulty)

  rock_band_music_theory_helper_vkr.lua      ← entry point (only file users run)
  rock_band_music_theory_helper_vkr/
    defaults.lua     audio_preview.lua
    ui_piano.lua     ui.lua                  ← ui.lua = tab bar + Drums + Guitar

  rock_band_preview_vkr.lua                  ← standalone Venue Preview window
                                               (no module folder of its own —
                                               reuses rock_band_general_helper_vkr/
                                               modules; documented exception to
                                               the folder-naming rule)

  rock_band_pitch_tuner_vkr.lua              ← standalone Pitch Tuner window
                                               (same exception — reuses
                                               rock_band_vocal_helper_vkr/
                                               ui_common.lua + ui_tuner.lua and
                                               their dependencies; never ui.lua)

  rock_band_midi_pattern_vkr.lua             ← standalone MIDI Pattern window
                                               (same exception — reuses
                                               rock_band_general_helper_vkr/
                                               ui_common.lua + ui_midi_pattern.lua
                                               and their dependencies; never ui.lua)

  quick_actions/                             ← single-file, no-UI hotkey scripts
    lib/
      vocal_note_snap_core.lua               ← shared cores (not bindable)
      vocal_note_create_core.lua
    vocal_note_snap_to_playhead_vkr.lua      ← bindable wrapper (auto)
    vocal_note_snap_start_to_playhead_vkr.lua
    vocal_note_snap_end_to_playhead_vkr.lua
    vocal_note_create_at_playhead_vkr.lua

  CLAUDE.md           ← this file (shared conventions)
  .claude/
    CLAUDE_vocal.md               ← vocal helper details
    CLAUDE_general.md             ← general helper details
    CLAUDE_music_theory.md        ← music theory helper details
    CLAUDE_venue_theme_generation.md  ← venue theme authoring guide
```

Module file contents and load orders are in the script-specific CLAUDE files.

### What belongs in a committed CLAUDE file

`CLAUDE.md` and everything in `.claude/` carry **stable project knowledge only** —
architecture, conventions, how to build and deploy, and lessons that stay true. The test
before adding anything: *would this still be true in three months, and does a developer
who just cloned this repo need it?*

Roadmaps, active tasks, WIP notes and local environment details go in `CLAUDE.local.md`
at the repo root, which is gitignored.

### Never cite an unversioned document from a versioned file

`_future_ideas/`, `_old_stuff/`, `_external_docs/` and `_raw_assets/` are all gitignored,
so **no committed file — Lua source and code comments included, not just markdown — may
point a reader at a document inside them.** A fresh clone cannot open it, so the citation
is a dead end that also implies something is missing when nothing is.

Where the fact is worth keeping, **state the fact and drop the path.** A comment saying
"transcribed from the RBN/C3 Subgenre Descriptions documentation" is provenance a reader
can act on; the same sentence prefixed with `_external_docs/` only looks like a broken
repo path. Where a planning document holds a durable lesson, write the lesson into the
committed file and leave the document out of it.

**A path the code actually loads is not a citation and stays.** `dev/calibration/` and
`dev/tests/` build real filesystem paths under `_external_docs/` because that is where
the corpus and reference files have to be placed; those, and the prose explaining that the
folder is unversioned and must be supplied, are operating instructions rather than
pointers to reading material.

### Quick actions (`quick_actions/`)

Small no-UI scripts meant to be bound to a hotkey and fired once (no ImGui, no
defer loop). Conventions:

- `*_vkr.lua` files at the folder root are the bindable entry points; shared
  cores live in `quick_actions/lib/` (loaded via `dofile`, never bound
  directly), keeping the root listing bindable-only.
- Exit silently when preconditions fail (no MIDI editor, no target note) —
  never `ShowMessageBox`. A no-op run must not create an undo point: return
  before any `Undo_*` call.
- Self-contained: hardcode constants (e.g. pitch range 36–84) rather than
  loading a helper's `defaults.lua`.
- Cores expose a take-level function (explicit take/cursor args) alongside the
  hotkey entry point, so `dev/tests/quick_actions.lua` can test them without
  an open MIDI editor.
- New scripts need a line in `deploy_to_reaper.bat` (the `quick_actions`
  robocopy already mirrors the whole folder).

---

## Glossary

- **Stem** — isolated audio track from a mix (vocal stem, kick stem, etc.)
- **RMS** — root mean square of signal in a window; perceived loudness proxy
- **PPQ** — REAPER's MIDI tick unit. Convert: `MIDI_GetPPQPosFromProjTime` / `MIDI_GetProjTimeFromPPQPos`
- **Take** — recording or MIDI clip inside a media item. Use the active take for note operations.
- **Audio accessor** — REAPER API for reading PCM samples. Create: `CreateTakeAudioAccessor`. Always free: `DestroyAudioAccessor`.
- **YIN** — monophonic pitch detection algorithm based on the cumulative mean normalized difference function (CMND). Finds the fundamental frequency by searching for the period (lag) that minimizes the difference function, with parabolic interpolation for sub-sample precision.
