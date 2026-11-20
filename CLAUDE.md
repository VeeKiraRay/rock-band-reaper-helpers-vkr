# Rock Band Authoring Tools — Project Documentation

REAPER ReaScript (Lua) tools for Rock Band audio authoring, sharing a common `lib/` folder.

| Script | Purpose |
|---|---|
| `rock_band_vocal_helper_vkr.lua` | MIDI note generation from vocal audio — syllable detection, pitch assignment, lyrics |
| `rock_band_general_helper_vkr.lua` | Song-wide tools: stem import, audio alignment, tempo map from drum audio, workflow checklist, VENUE/EVENTS, Metadata |
| `rock_band_instrument_helper_vkr.lua` | Instrument parts: difficulty generation and validation, overdrive and drum fills, tab input, MIDI utilities |
| `rock_band_music_theory_helper_vkr.lua` | Read-only drum / guitar / piano reference |

**Read the script-specific file before making changes:**
- Working on `rock_band_vocal_helper_vkr` → read `.claude/CLAUDE_vocal.md`
- Working on `rock_band_general_helper_vkr` → read `.claude/CLAUDE_general.md`
- Working on `rock_band_instrument_helper_vkr` → read `.claude/CLAUDE_instrument.md`
- Working on `rock_band_music_theory_helper_vkr` → read `.claude/CLAUDE_music_theory.md`

This file documents shared runtime, architecture, and conventions only.

---

## Runtime requirements

Every script requires **REAPER 6.x or later** and **ReaImGui 0.7 or later**. Each entry point validates both at startup:

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

**Bumping a helper means checking its standalones.** Four windows ship as their own entry points but own almost no code: `rock_band_preview_vkr.lua` and `rock_band_directed_moves_vkr.lua` draw modules out of `rock_band_general_helper_vkr/`, `rock_band_midi_pattern_vkr.lua` out of `rock_band_instrument_helper_vkr/`, and `rock_band_pitch_tuner_vkr.lua` out of `rock_band_vocal_helper_vkr/`. All four also load shared `lib/` files, so a change to one of those (`lib/reaper_helper_common.lua`, `lib/reaper_helper_ui.lua`, ...) counts too. A fix in one of those shared modules changes what the standalone does **without touching the standalone's own file**, so its `@version` silently stops describing the code it runs.

So whenever you bump a helper's `@version` and write its `@about` entry, finish the job:

1. Check each standalone's load list — the `_files` table in its entry point, also written out in `.claude/CLAUDE_general.md`, `.claude/CLAUDE_instrument.md` and `.claude/CLAUDE_vocal.md` under "Second/Third entry point". This is a lookup, not a judgment call: if a file you changed is in the list, that standalone is affected.
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

**A new entry point needs three registrations, not one.** Adding the `.lua` file is the easy part; each of these fails differently and quietly if skipped:

1. `SCRIPT_LINK_GROUPS` in `lib/reaper_script_links.lua` — otherwise the tool is invisible from every helper's *General > Other tools* tab.
2. The zip list in `.github/workflows/release.yml` — otherwise it is registered but not shipped, and release users get a button greyed out as "Not installed" while everything in a working tree looks correct.
3. `deploy_to_reaper.bat` (local, gitignored path) — otherwise your own REAPER install never sees it.

Items 1 and 2 are covered by `dev/tests/script_links.lua`, which checks the registry against the repo in both directions *and* against the release zip list. Item 3 cannot be tested (the file is local by design).

### Shared lib (`lib/`)

| File | Contents |
|---|---|
| `lib/reaper_imgui_helpers.lua` | The text colours `COL_TEXT`, `COL_DIM`, `COL_WARN`, `COL_ERROR`, `COL_GOLD`, `COL_OK`, `COL_INFO` (see "Text colours"); `TextDim`, `TextDimWrapped`, `TextColoredWrapped`; `PitchName`, `Tooltip`, `SliderTooltip`, `ScriptWindowTitle`, `Btn`, `BtnWidth`, `BtnGroupWidth`, `LabelColWidth`, `RadioGroupWidth`, `SectionHeader`, `SortedByLabel`, `ComboGroupHeader`, `GetTrackList`, `FormatTime`, `GetTimeSelection`, `BeginScrollBody` (BeginChild for both the 0.9 and the 0.7/0.8 signature) |
| `lib/reaper_helper_common.lua` | `FindTrackByName`, `TrackAtIndex`, `GetTakePPQPerQN`, `GetTempoContextBefore`, `TrackHasAudio`, `TrackHasMIDI`, `RefreshTrackLists`, `RunAction`, `MakeProjectPoll`, `MakeProjectSwitchCheck` — track and action helpers the General, Instrument and Vocal helpers share; `SettingsPairs`, `SettingsDiff`, `SettingsRemoveKey`, `UserDefaultsGet`, `UserDefaultsSet`, `UserDefaultsSetup` — the settings layers (see "Settings save/load"); **load before each `settings.lua`**. Writes the caller's `S` (`*_track_list`, `status`, `last_result`), so each script declares those fields. `RunAction` calls the script's optional global `RunActionErrorCleanup()` after a failed action (the vocal helper closes its open YIN context there) |
| `lib/reaper_helper_ui.lua` | `TrackCombo`, `MidiEditorTrackWarning`, `DrawResultPanel`, `HelperFooterHeight`, `DrawHelperFooter`, `HelperCopyText`, `ResultLineTag`, `SetCopyView`, `DrawSettingsPersistence` — UI every window draws (see "Window footer" below; `DrawSettingsPersistence` is each helper's Settings block: this project / my defaults). `TrackCombo` matches by REAPER track index and offers `(none)` (`-1`): an optional input left unset, or a required one not picked yet — actions resolve indices through `TrackAtIndex` and ask for a track when it returns nil. `DrawResultPanel()` draws the last result (a line with a tab renders as two columns) |
| `lib/reaper_dsp.lua` | `ComputeRMSContour`, `OpenYINContext`, `YINWindowSize`, `ReadMonoWindow`, `QuickRMS`, `ComputeCMND`, `SearchYINTau`, `MedianVote`, `DetectPitchYIN`, `SampleYINAt`, `GateAndSplit`, `ApplyMinOffset` |
| `lib/reaper_midi_helpers.lua` | `FindMIDIItem`, `FindFirstMIDIItem`, `ReadAllMIDINotesOnTrack`, `ClearNotesAtPitchesInRange`, `InsertNotes`, `ReplaceNotesBulk` (one `MIDI_GetAllEvts` / `MIDI_SetAllEvts` round trip: Difficulty > Generate, Animation > Drums), … |
| `lib/reaper_guitar_theory.lua` | `GuitarShapeToPitches`, `GuitarNormalizeIntervals`, `GuitarClassifyChordType`, `GuitarSuggestRBMapping`, `GuitarAnalyzeShape`, `GuitarParseFretInput`, `GuitarAnalyzeShapeAllTunings` — pure, no `r`/`ctx`/`S` |
| `lib/reaper_music_notation.lua` | Staff notation model: `NOTATION_CLEFS`, `KEY_SIGNATURES`, `NotationStepToNatural`, `NotationStepToPitch`, `NotationNoteName`, `NotationKeySigAlteration(s)`, `NotationSoundingStep`, `NotationKeySigSlots`, `RBPitchName`, `PianoKeyLayout` — pure, no `r`/`ctx`/`S` |
| `lib/reaper_script_links.lua` | `SCRIPT_LINK_GROUPS`, `ScriptLinkBasename`, `IsRunningScriptLink`, `FilterScriptLinkGroups`, `LaunchReaScript`, `DrawGeneralLinksTab`, `DrawScriptLinkEntry`, `ScriptLinkEntry` — the General > Other tools sub-tab, shared by the general, instrument and vocal helpers; `DrawScriptLinkEntry` draws one launcher row for other views (the General Helper's Venue > Actions > Standalone windows) |
| `lib/reaper_karplus_strong.lua` | `KarplusStrongVoice`, `SynthesizeChordSamples`, `SYNTH_TONES`, `SYNTH_TONE_ORDER`, `SynthToneOpts`, `SynthTonesInFamily` — struck/plucked-string synthesis and its per-instrument tone presets, for chord audition |
| `lib/reaper_difficulty_score.lua` | `ScoreChart`, `SCORE_FACTOR_KEYS`, `NormalizeSpans`, `EventsInSegments`, `DeriveSpansFromEvents`, `ProRemapEvents`, `Percentile`, `TotalSpanSeconds`, `SpanOverlapSeconds`, `DIFFICULTY_PRIMITIVES` — chart difficulty factors for guitar/bass/drums/keys/Pro Keys. Pure, no `r`/`ctx`/`S`. `DIFFICULTY_PRIMITIVES` exports four per-event building blocks (`PitchSetChanged`, `ShapeKey`, `MotionKey`, `ConditionalEntropy`) for the general helper's Overdrive tab, which scores single bars. Exported rather than copied, so the models stay tied to one implementation |
| `lib/reaper_difficulty_score_vocals.lua` | `ScoreVocalChart`, `NormalizeVocalPhrases`, `VocalClassifyLyric`, `VocalPitchClassDistance`, `VocalNoteIsPitched`, `VocalSubtractPercussion` — the vocal factor set. Pure. **Load after `reaper_difficulty_score.lua`**: it uses that file's span helpers and appends its columns to `SCORE_FACTOR_KEYS` |
| `lib/reaper_difficulty_tiers.lua` | `RANK_TIER_THRESHOLDS`, `TIER_NAMES`, `TierForRank`, `TierName`, `TierBand`, `TierPosition` — rank to displayed tier (0 Warmup … 6 Impossible), from the community `InstrumentDifficulty.ts` tier table. Pure. **Both open-ended bands are closed by the model, not the tier table**: tier 6 by `rank_hi`, tier 0 by `rank_lo`. Measured from rank 1 instead, every floor-clamped Warmup chart computed 0.85–0.97 and read as almost-Apprentice while having fallen off the *bottom* of the scale (drums: 97% of a 1–124 band whose model floor is 120). Both args are optional and omitting them keeps the tier table's own 1-and-infinity |
| `lib/reaper_difficulty_predict.lua` | `DIFFICULTY_SCALE_INV`, `DifficultyModelInputs`, `DifficultyPredictRank`, `DifficultyFactorZ`, `DifficultyOutOfRange` — how to apply a frozen model. Pure. Coefficients are in **standardized** units, so nothing may apply them by hand |
| `lib/reaper_difficulty_models.lua` | **Generated** — `RB_DIFFICULTY_MODELS`, `RB_DIFFICULTY_MODEL_ORDER`, `RB_DIFFICULTY_MODELS_SCHEMA`. The six frozen fitted models. The file states its own format version in `RB_DIFFICULTY_MODELS_SCHEMA`, which is the only place to read it — a copy quoted here drifts the first time the exporter bumps it. Carries coefficients, standardization stats, rank clamp, per-factor `bounds`, concentration thresholds, and `corr` (pairwise factor correlations at \|r\| ≥ 0.70, used to stop the explanation panel restating one observation twice). Rewritten only by `dev/calibration/export_production_models.lua`; never hand-edit |
| `lib/reaper_difficulty_read.lua` | `FindTrackExact`, `ReadGemEvents`, `RB_CHART_SPECS`, `ScoreChartForSpec`, `ReadVocalNotes`, … — the chart readers. Used by the General Helper's Metadata > Difficulty, the Instrument Helper's Generate and Overdrive, and `dev/calibration/`; touches `r` only inside functions |
| `lib/reaper_key_detect.lua` | `KeyFeatures`, `KeyRankSet`, `KeyConfidence`, `KeySetLabel`, `KeyScale`, `KeyScaleText`, `KeyTrackReport`, `KeyFitProfiles`, `KeyName`, `KeyRelation`, `KeyLyricIsUnpitched`, `KEY_RESULT_SETS`, `KEY_SOURCES` — song key suggestion (vocal tonic + major/minor) from charted vocals, harmonies and Pro Keys. Pure. Used by the General Helper's Metadata > Song key, the vocal helper's Pitch > Tuner key snap ("From charted lead"; the standalone Pitch Tuner loads it too) and `dev/tools/key_detect_fit_offline.lua` |
| `lib/reaper_key_profiles.lua` | **Generated** — `RB_KEY_PROFILES`, `RB_KEY_PROFILES_SCHEMA`: per-source pitch-class profiles fitted to the official charts' `songs.dta` keys. Rewritten only by `dev/tools/key_detect_fit_offline.lua`; never hand-edit |
| `lib/reaper_key_audio.lua` | `KeyAudioNotes`, `KeyAudioStart`, `KeyAudioStep`, `KeyAudioProgress`, `KeyAudioFinish`, `KeyAudioPickSet`, `KEY_AUDIO_SR`, `KEY_AUDIO`, `KEY_AUDIO_BASS`, `KEY_AUDIO_SETS` — notes from an isolated vocal or bass recording (YIN per frame at 8 kHz, loudness gate, runs of one pitch) for the song key scorer. Pure; needs `ComputeCMND` / `SearchYINTau` from `lib/reaper_dsp.lua`. Shared by Metadata > Song key's audio result and offline probes |
| `lib/reaper_spectrum.lua` | `SPECTRUM_NFFT`, `SpectrumHann`, `SpectrumMagnitudes` - the radix-2 FFT magnitude spectrum (4096 points) the spectral readers share (`reaper_harmony_detect.lua`, `reaper_chord_detect.lua`). Pure. **Load before both**: they read `SPECTRUM_NFFT` at load time. Its arithmetic is part of what both parity tools check, so change it only with both passing |
| `lib/reaper_harmony_detect.lua` | `HarmonyAnalyseFrame`, `HarmonyVoteNew`, `HarmonyVoteAdd`, `HarmonyVoteResult`, `HarmonyScale`, `HarmonySpectralPitch`, `HarmonyVoteAddPitch`, `HARMONY_SR`, `HARMONY_FRAME_N`, `HARMONY_FRAME_LEAD`, `HARMONY_SPEC_N`, `HARMONY_SPEC_LEAD` — a second voice beside a known lead in one vocal recording: cancel the charted lead's period, search what is left within an octave, vote per lead note, optional key snap; optionally a spectral reading (lead partials masked, harmonic sum) voting alongside. Pure; needs `ComputeCMND` from `lib/reaper_dsp.lua`. Used by the vocal helper's Pitch > Tuner Harmony readout and the standalone Pitch Tuner. **Must stay identical to the method measured offline**: `dev/tools/harmony_detect_parity_offline.lua` compares it with `dev/tools/harmony_audio_core.lua` and `dev/tools/harmony_spectral_core.lua` (the measured implementations) frame by frame - change a constant and the measured accuracy no longer applies |
| `lib/reaper_chord_detect.lua` | `ChordFrameAnalyse`, `ChordFrameChroma`, `ChordPassage`, `ChordSumNew`, `ChordSumAdd`, `ChordRank`, `ChordKeyMask`, `ChordConfidence`, `ChordName`, `ChordNotes`, `ChordNameOverBass`, `ChordUpperTriad`, `ChordTemplateForMask`, `ChordBassPc`, `ChordBassVote`, `CHORD_SR`, `CHORD_FRAME_N`, `CHORD_HOP_S`, `CHORD_ATTACK_S`, `CHORD_SPAN_MAX`, `CHORD_READ_FRAMES`, `CHORD_PLAY_FRAMES`, `CHORD_BASS_N`, `CHORD_BASS_STEP_S`, `CHORD_PASS_HOP_S`, `CHORD_PASS_FRAMES` - chord names from a keys recording: harmonic-sum chroma from C3 up, templates with key / bass priors and "prefer plain chords" (7th and sus4 penalties); plus `ChordPassage`, a single-notes-or-chords verdict over ~4 s found from the audio alone (flux-peak onsets, template score + struck-note ratio against frozen dev statistics). Pure; needs `lib/reaper_spectrum.lua` and `lib/reaper_dsp.lua` loaded first. For the Instrument Helper's Keys > Tuner. **Must stay identical to the measured method**: `dev/tools/chord_detect_parity_offline.lua` compares it with `dev/tools/chord_core.lua` frame by frame (`all` also re-measures the core's accuracy against the chart) |
| `lib/reaper_harmony_style.lua` | `HarmonyPairStats`, `HarmonyClassify`, `HarmonyIntervalName`, `HarmonyBestFixedOffset` — harmony style between a lead line and one harmony line, as three axes: rhythm (homophonic / partial / decorative / counter / alone), spacing (unison / octave / close / open / cluster) and parallel motion (exact or by scale step). Pure. Measured offline over the official HARM1-3 charts; not loaded by a shipped script yet |
| `lib/reaper_score_sim.lua` | `ScoreSimulatePart`, `ScoreSimulateOD`, `ScoreSimulateVocals`, `ScoreBasePart`, `ScoreBaseVocals`, `ScoreStars`, `ScoreStarsReached`, `ScoreBeatAt`, `SCORE_RULES`, `SCORE_POINTS`, `SCORE_STAR_THRESHOLDS`, `SCORE_FILL_GATE_SEC` — RB3 score and overdrive for one part in a full combo (base score, star cut-offs, overdrive deployed as soon as possible). Pure; the game's rules with their sources in the header. Used by the General Helper's Metadata > Score and the Instrument Helper's Overdrive > Validate |
| `lib/reaper_score_read.lua` | `ScoreReadSong`, `ScoreReadBeats`, `ScoreReadBars`, `ScoreBarOf`, `ScoreMarkUnisons`, `ScoreFindings`, `ScoreCoverageText`, `ScoreNum`, `ScoreReportText`, `SCORE_PARTS` — reads the project into the simulator's parts, plus the wording both helpers show. **Load after `reaper_difficulty_read.lua`** (uses its readers at call time) |
| `lib/reaper_wav_writer.lua` | `WriteMonoWAV16` |
| `lib/reaper_venue_shots.lua` | **Generated, frozen** — `RB_VENUE_SHOTS`, `RB_VENUE_SHOTS_SCHEMA`: the directed camera cuts of all 44 RB3 venues as derived information - per cut its moves (our labels, focus member, gender, styles, venue kinds, variants, lead-in, lock where longer than 0.25 s), its length ranges after the event: `length` the range the game's own asset check allows (`world/dircut_limits.dta`), `measured` the real one over all venues and `measured_kind` per venue kind (each shot's camera path with its chained shots, minus its lead-in), its lock range (how long after its event the camera cannot change, 0.25 s floor applied), free-cut flag and lineup remaps; plus `coop_remap` (normal shots: lineup remaps only). Read once from the game's venue files; never hand-edit (see "Probes vs tools": frozen data). Read by the Directed Moves window and by the General Helper's Validate camera stacks (directed-cut move lengths, `venue_camera_timing.lua`) |
| `lib/reaper_venue_shots_query.lua` | `VenueShotEvents`, `VenueShotEvent`, `VenueShotRowMatches`, `VenueShotRemap`, `VenueShotSearch`, `VenueShotKindsText`, `VenueShotRowFilter`, `VenueShotWhoShort`, `VenueShotTimingFacts`, `VENUE_SHOT_KIND_LABELS`, `VENUE_SHOT_LINEUP_LABELS` — queries for the Directed Moves window, following the game's shot filter (style / gender / lineup); `VenueShotTimingFacts` is a directed cut's timing lines, shared by Directed Moves' summary and the General Helper's Manual gen tooltip (which also loads this file). Pure; load after `reaper_venue_shots.lua` |

The `reaper_difficulty_*` scoring modules are shared with the calibration harness in
`dev/calibration/` rather than with a second shipped script — the one case where `lib/`
serves a dev consumer (`reaper_difficulty_read.lua` serves both: the two helpers and the
harness). That is deliberate and load-bearing: the fitted coefficients the
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
TextDim(label)
r.ImGui_SameLine(ctx, row_x + lbl_col)
```
`rock_band_general_helper_vkr/ui_metadata.lua` and Animation > Drums' velocity rows
(`ui_animation.lua`, `VelocityRow`) are currently the only places that combine
`Indent` with a label column — every other tab draws unindented, where the two
forms are identical.

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
sentence, a dimmed empty-state message, an inline warning — should
use `r.ImGui_TextWrapped` / `TextDimWrapped` / `TextColoredWrapped` instead of
`r.ImGui_Text` / `TextDim` / `r.ImGui_TextColored` from the start, so it flows to a new line instead of clipping when the
window is narrow (the same treatment the result panel already gets via
`PushTextWrapPos`/`PopTextWrapPos` in both `ui.lua` files). Reserve plain
`Text`/`TextDim` for short labels (section titles, single words, widget
labels) that aren't at risk of overflowing.

### Text colours
Text is coloured by **meaning**, with the shared constants in
`lib/reaper_imgui_helpers.lua` — never a hex literal, and never a shade close to
one of them ("a slightly lighter amber for this one" is how three ambers and seven
greys built up before):

| Constant | Meaning |
|---|---|
| `COL_TEXT` `0xFFFFFFFF` | white that must stay white (the main value of a live readout) |
| `COL_DIM` `0xAAAAAAFF` | secondary text: hints, empty states, headers of minor groups, less important values |
| `COL_WARN` `0xFFAA00FF` | amber: a warning, an advisory, worth a look |
| `COL_ERROR` `0xFF4444FF` | red: an error, something to fix |
| `COL_GOLD` `0xFFD24AFF` | gold stars reached |
| `COL_OK` `0x44DD44FF` | green: running, active, good |
| `COL_INFO` `0x22BBFFFF` | blue: a neutral highlight, a state worth telling apart |

**One style: saturated, at a similar brightness.** The colours carry little white
(under about 30% in the darkest channel) and sit close together in perceived
lightness on the dark window background: green, blue and amber at L* 72-78, gold a
little brighter (it has to read as gold, not amber), red darker (a red pushed up to
the others' brightness turns pink). A pastel set (more white) and a deeper set were
compared side by side and rejected: pastel weakened the error red, and green and
blue at full brightness stood out from the rest. Amber and gold are only 5 degrees
apart in hue, so they are told apart by brightness - do not move either toward the
other. A new colour, and the drawing colours when they get their own pass, follow
the same style: pick a hue, keep the white mix low, match the band's brightness.

- **Dim text uses `TextDim(text)` / `TextDimWrapped(text)`, never
  `r.ImGui_TextDisabled`.** ImGui's disabled grey (`0x808080` in ReaImGui's default
  style) is too faint to read and has no wrapping variant. A widget that is
  actually disabled is dimmed by `BeginDisabled`, which is independent of this.
- **The result panel** (`DrawResultPanel`) colours a line that starts with a tag:
  `{gold}`, `{error}`, `{warn}`, `{dim}`, `{ok}`, `{info}`. On a two-column line
  (`label\tvalue`) only the value is coloured. The tag is not drawn, and Copy result
  leaves it out (`ResultLineTag`, `HelperCopyText`).
- **A module that builds a colour table at load time** (`ui_venue_players.lua`,
  `ui_keys_tuner.lua`) needs the lib loaded before it — every entry point loads it
  first; a test runner must too.
- **Drawing colours are not text colours.** Plates, gems, piano keys, strip ticks,
  difficulty dots, the pitch arrows' direction green / red and graded scales such as
  the Keys tuner's confidence keep their own local values; they are tuned against
  what they are drawn on. A shared text colour used for a graded step (the Keys
  tuner's `likely` / `maybe` / `clear`) is fine. They have not had a pass of their
  own yet; when they do, they follow the style above.

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
- The window footer (below) — every window draws the one implementation; never a per-script copy.
- Track-selector pre-filtering (audio-only / MIDI-only lists, `RefreshTrackLists`) and the automatic refresh below.
- Any new status-bar widget, keyboard shortcut, or window-level affordance.

If a sync to another script is out of scope for the current task, leave a TODO comment in the code and note it in the PR description — do not silently skip it.

### Window footer

Every window with actions (the three helpers, MIDI Pattern, Pitch Tuner) ends the
same way, from `lib/reaper_helper_ui.lua`:

```lua
local FOOTER = {}   -- file-level; switch parts off per window, e.g. { undo = false }
local visible, open = r.ImGui_Begin(ctx, title, true)
if visible then
    local body_visible = BeginScrollBody('##body', -HelperFooterHeight(FOOTER))
    if body_visible then
        -- tabs / view ...
        DrawResultPanel()
    end
    r.ImGui_EndChild(ctx)          -- always, whatever BeginScrollBody returned
    DrawHelperFooter(FOOTER)
    r.ImGui_End(ctx)
end
```

- The view scrolls inside the child; the footer is drawn after it and never moves.
- `FOOTER` parts: `status`, `copy`, `undo` (all on unless set `false`).
  `HelperFooterHeight` and `DrawHelperFooter` must get the **same** table, so the
  reserved height matches what is drawn.
- Scroll regions use `BeginScrollBody` (`lib/reaper_imgui_helpers.lua`), never a bare
  `ImGui_BeginChild`: its 5th argument changed type in ReaImGui 0.9.
- **No Always on top.** It was built and removed again: ReaImGui's TopMost flag
  keeps a window above other REAPER windows only, by design on Windows (and per its
  source, macOS), and the fix that worked around it was Windows-specific. It waits
  until it can be verified on macOS and Linux.
- New actions that belong to every window go in the footer, not a General tab.
- **Copy result copies what is on screen**: the view's own results, then the result
  panel. The status line goes in only when the view gives no results of its own (it
  would only say the action ran), and never when it is the footer's own "copied"
  message - a second press would otherwise start with it. A view that draws its results itself (cards, rulers, dots)
  instead of filling `S.last_result` calls `SetCopyView(fn)` while it draws them, where
  `fn` returns them as plain text in the order drawn - Metadata > Difficulty
  (`DifficultyReportText`), Song key (`MidiCopyText` / `AudioCopyText`) and Score
  (`ScoreReportText`) do. The registration lasts one frame and is dropped after the
  footer, so a sub-tab switched away from stops being copied; `fn` runs only when the
  button is pressed. Drawn things get words (the difficulty dots as "3 of 5 dots"), and
  text that is a tooltip on screen may be written out. Where a line is both drawn and
  copied, build it once and feed both (Song key's `TrackCheckLines` / `DrawLines`).

### Track lists refresh themselves

Every window with track dropdowns rebuilds its lists through the shared project-change
poll — no Refresh button:

```lua
local _track_poll = MakeProjectPoll(1.0, 5.0)   -- file level, lib/reaper_helper_common.lua
-- in Loop, after the project-switch check:
local tracks_due = _track_poll()                -- poll first: one build on the first frame
if tracks_due or not S.all_track_list then RefreshTrackLists() end
```

`MakeProjectPoll(min_secs, fallback_secs)` fires when `GetProjectStateChangeCount` moved
and `min_secs` passed (so note drags, which bump the count every frame, cost at most one
rebuild a second), or every `fallback_secs`. The count only moves when an **undo point**
is created — user edits always make one, and so must any helper action that adds tracks
or items (wrap it in an undo block). A project switch still clears `S.all_track_list`
for an immediate rebuild. Use the same poll for any other cached project read in draw
code (the Venue views and the Venue Preview do); never re-scan the project every frame.

### Time selection as scope
Actions respect time selection when active; fall back to whole-item or whole-track defaults otherwise. This is the primary iteration mechanism — work one section at a time.

### Smart default track selection
Each script implements `SetDefaultTracks` (or equivalent): runs at startup and on project switch, matches tracks by name, verifies track content (audio vs MIDI), falls back to index 0 if nothing matches.

### Project-switch detection
Every window's `Loop` asks a shared check, made once at file level:

```lua
local _project_switched = MakeProjectSwitchCheck()   -- lib/reaper_helper_common.lua
-- in Loop:
if _project_switched() then
    -- reset track indices and cached results, LoadSettings, smart defaults, S.status
end
```

On a switch: reset track indices, clear results that describe the old song, call `LoadSettings`, re-run smart defaults, update `S.status`. Ensures no state from the previous project leaks.

**The project pointer alone is not enough**, so never compare `r.EnumProjects(-1, '')` by hand: opening another project in the *same* project tab (File > Open, recent projects) keeps REAPER's pointer, and a pointer check left the previous song's results and settings on screen. The check compares the project file path too. A path appearing where there was none (the first save of a new project) is not a switch; Save As to a new name is, which only reloads the same settings.

### Settings save/load
Three layers, lowest first: **shipped** (`defaults.lua`) < **my defaults** (REAPER global ExtState, persisted in `reaper-extstate.ini`: every project reads it and updates never touch it) < **this project** (`SetProjExtState` / `GetProjExtState` under a script-specific section key). Format of all three: semicolon-separated `key=value`. `DeserializeSettings` parses each field independently — missing fields keep their current value. Track indices are **not** saved (positional, brittle across sessions).

- **My defaults store only differences** from the shipped string (`SettingsDiff`), so a value the user never changed follows a later release's new default, and one they changed survives it. Re-saving keeps every value that still differs.
- **`LoadSettings` starts with `ApplyDefaults()`** (shipped, then my defaults), then the project string. So every startup and project switch starts from the defaults, and a project without settings never keeps the previous project's. A project string holds every key, so it wins outright.
- **The shared machinery is `UserDefaultsSetup{ section, serialize, deserialize, labels }`** (`lib/reaper_helper_common.lua`), called once at the **end** of each helper's `settings.lua`, while `S` still holds the shipped values: it captures the shipped string and defines `ApplyDefaults`, `SaveUserDefaults`, `ClearUserDefaults`, `ResetUserDefault`, `UserDefaultRows`. So `reaper_helper_common.lua` loads **before** `settings.lua` (entry points and test runners). The Settings tab draws `DrawSettingsPersistence()` (`lib/reaper_helper_ui.lua`). `labels` names each key for the My defaults list (`{ name, bool = true }` shows On / Off). A new persisted key needs its label too, or the list shows the raw key.
- **`DeserializeSettings(str, project)`: old-project rules run only when `project` is true.** A my-defaults string holds only differences, so a stored option without its companion value means the shipped one. General's soft-option "128" rule would otherwise fire on it. A plain sanity check (the vocal helper's `pitch_mode`) may run on every string.
- **Save as my defaults asks before leaving a project behind.** When the open project has saved settings that differ from the current values (`ProjectSettingsDiffer`), the project would keep using them next time. So the shared block asks: save to the project too / only my defaults / cancel. A project with no settings, or with these exact values, is saved without asking.
- **Song-specific values never become my defaults**: `project_only(key, value)` in each `UserDefaultsSetup` call. The current lists:
  - General: tempo map first measure, time signature and failsafe override, character states, venue theme.
  - Instrument: the Keys Tuner's picked key.
  - Vocal: harmonies / snap keys, a Tuner key snap set to a key note, the pitch range and fixed pitch.

  The test checks the value, so a mixed setting's preference part (Tuner key snap Off / From charted lead) can still be a default. It runs on save and on load, so a value an older version stored is ignored. **A new persisted setting that belongs to one song goes on that list.**
- Project data that is not a preference (venue section configs, the workflow checklist state) keeps its own project keys and is not part of my defaults.

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

**Register the launcher from the repo checkout** (Actions > Load ReaScript),
not from a copy deployed into REAPER's Scripts folder. Suites read files a
deployed copy does not carry — `dev/calibration/` (the difficulty suites load
the scorer and stats from there), `.github/workflows/release.yml` (the Script
Links suite checks the release zip list), and `dev/dev_defaults.lua` with your local
`dev/dev_defaults.local.lua` for the suites that check against local reference files —
and fail to load or fail spuriously without them. Running
from the repo also tests the current code with no deploy step in between.

Structure: `framework.lua` provides `Test.section` / `Test.it` / `Test.expect`
/ `Test.report`; `fixture_helpers.lua` provides fixture loading and temp-track
helpers; each suite is a `<name>.lua` test set plus a `run_<name>.lua` runner
that dofiles the code under test and the set.

**Golden charts for Difficulty > Generate** (`run_generate_golden.lua`, also runnable
offline: `lua dev/tests/run_generate_golden.lua`): every MIDI in the gitignored
`dev/tests/golden/` holds hand-verified Hard/Medium/Easy. The suite regenerates each
Guitar/Bass/Keys/Pro Keys/Drums part (and PART DRUMS_2X, with its kicks from PART DRUMS one
tier up) from its Expert and fails on any rhythm, color/pitch/gem or length
difference, listed by bar, and on any difference in Guitar/Bass Hard's force-HOPO markers or
Pro Keys' lane-shift markers. Run it after every planner change: a failure means a rule change altered
an approved chart — either regenerate and re-verify the song, or rework the rule. The
synthetic tests in `instrument_algorithms.lua` pin individual rules; the golden charts are
what catch a change's effect on real songs. See `dev/tests/golden/README.md`.

**A runner must dofile everything its modules need at load time** — including
`lib/` files a module calls while loading (e.g. `venue_camera.lua` and
`venue_lighting.lua` call `SortedByLabel` from `lib/reaper_imgui_helpers.lua`). The
launcher runs each suite in its own fresh environment (`NewTestEnv`), exactly as
if run alone from the Actions list, so a missing dofile fails immediately instead
of passing because an earlier suite in the session happened to load the file.
Before that isolation, two runners went unnoticed missing a library for months.

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
- **Never assume a MIDI tick rate.** Rock Band projects use **480** ticks per quarter note (PPQ); REAPER's own default for new items is 960, and imported files carry their own. Read the real value from the take with `GetTakePPQPerQN(take)` (each helper's `helpers.lua`), or work in quarter notes (`TimeMap2_timeToQN`, `MIDI_GetProjQNFromPPQPos`) and never touch ticks. A hardcoded 960 is only acceptable as a defensive fallback, as a synthetic test value, or as a rounding grid finer than any real tick rate (Difficulty > Generate snaps to 1/960 QN: every tick at 480 or 960 PPQ lies exactly on that grid).
- **Thresholds on converted times need tolerance.** Seconds → quarter notes through the tempo map leaves float noise around 1e-9. A test like `len < 0.5` (exactly 1/8) then splits identical notes either way. Compare with an epsilon, or snap to a note grid first (both are used in `difficulty_generate_5lane.lua` / `actions_difficulty_generate.lua`).
- Audio accessor: always free with `DestroyAudioAccessor`. Leaking holds file handles open indefinitely.
- `CreateTakeAudioAccessor` returns an **item-relative** accessor. `GetAudioAccessorSamples` on such an accessor expects time in seconds from the **start of the take's source media**, not project time. Always convert: `t_off = project_time - item_pos` (where `item_pos = GetMediaItemInfo_Value(item, 'D_POSITION')`). Every function in `lib/reaper_dsp.lua` that reads a take accessor already does this (`DetectPitchYIN`, `SampleYINAt`, `ComputeRMSContour`). Any new audio analysis function must do the same — omitting this reads zeros for items not placed at project time 0, which is always the case for stems (they start at measure 3+). MIDI items are unaffected (their `item_pos` is always 0).

---

## File layout

```
[repo root]/
  lib/                                       ← shared by the scripts
    reaper_imgui_helpers.lua
    reaper_helper_common.lua                 ← track/action helpers: general, instrument, vocal
    reaper_helper_ui.lua                     ← TrackCombo, result panel, window footer: every window
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
    reaper_difficulty_read.lua               ← chart readers (both helpers + calibration)
    reaper_key_detect.lua                    ← song key suggestion (Metadata > Song key)
    reaper_key_profiles.lua                  ← GENERATED by dev/tools/key_detect_fit_offline.lua
    reaper_key_audio.lua                     ← notes from a vocal recording (song key)
    reaper_spectrum.lua                      ← FFT magnitude spectrum (spectral readers)
    reaper_harmony_detect.lua                ← second voice beside the lead (Tuner Harmony readout)
    reaper_harmony_style.lua                 ← harmony style vs the lead (dev probe for now)
    reaper_chord_detect.lua                  ← chord names from a keys recording (Keys > Tuner)
    reaper_score_sim.lua                     ← score + overdrive simulator (Metadata > Score,
    reaper_score_read.lua                      Overdrive > Validate's "in play" lines)
    reaper_wav_writer.lua
    reaper_venue_shots.lua                   ← GENERATED once, frozen (camera shots of the venues)
    reaper_venue_shots_query.lua             ← queries for the Directed Moves window

  rock_band_vocal_helper_vkr.lua             ← entry point (only file users run)
  rock_band_vocal_helper_vkr/
    defaults.lua     helpers.lua     pipeline.lua
    settings.lua     autotune.lua    actions.lua    ui.lua

  rock_band_general_helper_vkr.lua           ← entry point (only file users run)
  rock_band_general_helper_vkr/
    defaults.lua     helpers.lua     venue.lua
    settings.lua     tempomap.lua    actions.lua    ui.lua
    difficulty_explain.lua                   ← Metadata > Difficulty: wording, the
    difficulty_report.lua                      pasteable text report, the read-only
    difficulty_suggester.lua                   adapter (readers: lib/reaper_difficulty_read.lua)
    metadata_genres.lua                      ← Metadata > Genre: supported vocabulary
    metadata_genres_ext.lua                    (transcribed), the authored extended
    metadata_genres_lookup.lua                 vocabulary + mapping, and the lookup
    ui_metadata_genre.lua                    ← Metadata > Genre tab body
    song_key.lua     song_key_audio.lua      ← Metadata > Song key: chart and audio
    ui_metadata_key.lua                        readers, tab body
    ui_metadata_score.lua                    ← Metadata > Score tab body
    ui_metadata.lua                          ← Metadata tab shell (Genre, Difficulty, Song key, Score)
    animation_beat.lua                       ← Animation > Beat (BEAT track),
    animation_character.lua                    > Character (animation states) and
    animation_drums.lua                        > Drums (drummer notes): planners and
    ui_animation.lua                           actions, the Animation tab body

  rock_band_instrument_helper_vkr.lua        ← entry point (only file users run)
  rock_band_instrument_helper_vkr/
    defaults.lua     settings.lua    helpers.lua    ui.lua
    ui_midi_pattern.lua                      ← shared with the standalone MIDI Pattern window
    difficulty_generate_params.lua           ← Difficulty > Generate: shared parameters,
    difficulty_generate_retime.lua             Hard's fast-run rewrite, chords and
    difficulty_generate_colors.lua             colors, which onsets every planner keeps,
    difficulty_generate_rhythm.lua             the pure 5-lane and Pro Keys planners
    difficulty_generate_5lane.lua              (shared with dev/calibration/),
    difficulty_generate_prokeys.lua
    difficulty_generate_hopo.lua               Hard's force-HOPO markers, the Drums
    difficulty_generate_drums.lua              planner (limb by limb, independent of
    actions_difficulty_generate.lua            the band), the REAPER action, and the
    ui_difficulty_generate.lua                 sub-tab body
    overdrive_read.lua                       ← Overdrive tab: song model (QN), per-bar
    overdrive_interest.lua                     interest score, the fill / vocal /
    actions_overdrive_fills.lua                instrument planners (pure) with the
    actions_overdrive_vocals.lua               Generate action, the validator, and
    actions_overdrive.lua                      the tab body
    actions_overdrive_validate.lua
    ui_overdrive.lua
    chord_tuner.lua                          ← Keys > Tuner: the readings (chords from
    ui_keys_tuner.lua                          the keys stem) and the sub-tab body

  rock_band_music_theory_helper_vkr.lua      ← entry point (only file users run)
  rock_band_music_theory_helper_vkr/
    defaults.lua     audio_preview.lua
    ui_piano.lua     ui.lua                  ← ui.lua = tab bar + Drums + Guitar

  rock_band_preview_vkr.lua                  ← standalone Venue Preview window
                                               (no module folder of its own —
                                               reuses rock_band_general_helper_vkr/
                                               modules; documented exception to
                                               the folder-naming rule)

  rock_band_directed_moves_vkr.lua           ← standalone Directed Moves window
                                               (same exception — reuses
                                               rock_band_general_helper_vkr/
                                               ui_venue_camera_shots.lua + the
                                               lib/reaper_venue_shots*.lua data)

  rock_band_pitch_tuner_vkr.lua              ← standalone Pitch Tuner window
                                               (same exception — reuses
                                               rock_band_vocal_helper_vkr/
                                               ui_common.lua + ui_tuner.lua and
                                               their dependencies; never ui.lua)

  rock_band_midi_pattern_vkr.lua             ← standalone MIDI Pattern window
                                               (same exception — reuses
                                               rock_band_instrument_helper_vkr/
                                               ui_midi_pattern.lua + lib/
                                               reaper_helper_ui.lua and their
                                               dependencies; never ui.lua)

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
    CLAUDE_instrument.md          ← instrument helper details
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

**No committed file says where local data lives.** The corpora and reference files are
gathered for one question and the tools outlive them, so code never builds a path to them:
- `dev/tools/` command-line scripts take the corpus folder as an argument on every run
  (`SmfCorpusArg` in `dev/tools/smf_reader.lua` prints the usage and exits without one).
- Scripts REAPER runs, the calibration harness and the test suites ask
  `DevPath('<key>')` (`dev/dev_defaults.lua`, committed with a placeholder per key and a
  line saying what each is). Each machine sets its values in `dev/dev_defaults.local.lua`,
  which is gitignored; a relative value is taken from the repo root. A key left unset
  returns nil and a message naming it, so a fresh clone still loads every script: a
  calibration runner stops, a test skips. A new dataset gets a new key there.
- A probe in `dev/probes/` (gitignored) may hard-code its path.

**No absolute path in any committed file** - not in code, docs, test fixtures, or anything
a script writes into the repo (manifests, reports, CSVs). A machine's path names the person
and their folders, is wrong on every other checkout, and stays in git history after it is
removed. Write the dataset's key, a repo-relative path, or a description instead. A
generator that records where it read from writes the key name (`run_calibration_vkr.lua`'s
manifest does).

### Probes (`dev/probes/`, gitignored) vs tools (`dev/tools/`)

A **probe** is a one-off measurement over a local corpus (official charts, decrypted
multitracks, a venue-merged MIDI set): it answers a question, its numbers go into the
notes, and a clone could not run it anyway. Probes live in `dev/probes/`, which is
gitignored, and load what they share from `dev/tools/` through `_root .. 'dev/tools/'`.

What outlives the question goes in `dev/tools/` and is committed: shared readers
(`smf_reader.lua`), fitters that write a generated `lib/` file, and the **measured method
cores** (`harmony_audio_core.lua`, `harmony_spectral_core.lua`) with the parity tool that
checks a shipped `lib/` port against them. When a probe's method ships, move the method
into a core the probe loads - a committed tool may never `dofile` a probe. Committed files
name `dev/tools/` files freely and never a probe; describe the measurement instead
("measured over the official HARM1-3 charts").

**Frozen data is the exception.** A generated `lib/` file whose inputs can never ship
(files extracted from the game itself) and whose input set is complete (the game's venues)
is written once by a probe, not by a committed fitter: a committed fitter would not run on
a clone either, and there is nothing new to fit. Its header says so - "generated once from
..., frozen, never hand-edit" - and describes the source without naming the probe.
`lib/reaper_venue_shots.lua` is the one case so far.

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
