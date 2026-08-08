# Rock Band Vocal Helper — Script Documentation

`rock_band_vocal_helper_vkr.lua` detects syllables/phrases in a vocal audio stem and writes MIDI notes (timing-aligned, optionally pitch-aligned) into an existing MIDI item. Used to author timing data for a karaoke game.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

1. Drop a vocal stem on one track. Add a destination track with a MIDI item covering the timeline area.
2. Pick source and destination tracks in the dropdowns. Smart defaults pre-select tracks named "VOCALS AUDIO" / "DRYVOX1" (audio) and "PART VOCALS" (MIDI).
3. Optionally make a time selection to limit work to one section.
4. Tune detection sliders — RMS threshold, low-pass cutoff, peak-split ratio, min offset, min note length, RMS window.
5. Use **Dry run** to preview note counts without writing anything.
6. Use **Generate (append)** to add notes to the destination MIDI item, or **Generate (replace)** to clear all existing vocal-range notes in the range first — cleaner when you want a fresh result.
7. Iterate. Re-running Generate (append) over the same range clears existing notes at the affected pitches first — no duplicates stack.

**Specialized actions:**

- **Auto-tune from reference.** Manually place a few notes at Default pitch as timing reference → make time selection → Auto-tune. Coordinate descent finds detection parameters that best reproduce those reference notes. Doesn't touch pitch settings or RMS window.
- **Auto-tune YIN from reference.** Generate in YIN mode → manually correct pitches on a few notes → Auto-tune YIN. Sweeps YIN parameter combinations scored against the corrected pitches, applies best values to the sliders. Lives on the Pitch tab's Placement - Built-in sub-tab.
- **Apply pitch changes.** Skips detection entirely. Re-assigns pitches to existing notes using the configured pitch source (YIN or Reference MIDI), preserving position and length. Always enabled.

---

## Pipeline

```
ResolveAnalysisRange(audio_track)
        │   reads time selection, finds the audio item, returns range
        ▼
ComputeRMSContour(item, range, window_s, lpf_cutoff_hz)   [lib/reaper_dsp.lua]
        │   reads samples via take audio accessor
        │   optional 12 dB/oct LPF (two cascaded one-poles), per-channel state
        │   emits per-window RMS values
        ▼
GateAndSplit(contour, threshold, split_ratio, min_note_s)   [lib/reaper_dsp.lua]
        │   pass 1: gate by absolute RMS threshold → phrases
        │   pass 2 (split_ratio > 0): split wherever contour < peak × ratio
        │   filter sub-min_note_s notes
        ▼
ApplyMinOffset(notes, min_off_s)   [lib/reaper_dsp.lua]
        │   cap each note's end at next_note.start − min_off
        │   drop notes squeezed to zero length
        ▼
AssignPitches(notes, ref_track, audio_item)   [pipeline.lua]
        │   per-note: lookup pitch from configured source
        │     Reference → nearest MIDI note on ref track within tolerance
        │     YIN → DetectPitchYIN on audio_item, fallback to Default pitch
        │   apply [min_pitch, max_pitch] via octave-shift, clamp as fallback
        ▼
ClearNotesAtPitchesInRange + InsertNotes   [lib/reaper_midi_helpers.lua]
```

**Auto-tune** wraps this pipeline:

- Caches the RMS contour by `(window_ms, lpf_cutoff_hz)` — most parameter sweeps skip audio I/O.
- Coordinate descent: two coarse passes over each of five tunable parameters, then a fine refinement pass near the best found. Skips `window_ms` (resolution choice, not a fit parameter, and it invalidates the contour cache).

**Apply-pitch** reuses `AssignPitches` only: reads existing notes → deletes → reassigns pitches → reinserts. Uses delete+insert rather than `MIDI_SetNote` because `SetNote` does not register correctly with REAPER's undo system.

---

## Module section order

The logical content order across the vocal modules. Keep additions in their natural section.

```
defaults.lua:
  1.  Mode constants              MODE_REFERENCE / MODE_YIN
                                  RB3_MIN_PITCH, RB3_MAX_PITCH, RB3_PHRASE_PITCH
                                  LYRIC_IGNORE (special game events to preserve)
  2.  DEFAULTS table              single source of truth for defaults
  3.  S table                     live state; S.lyrics_path is session-only (not saved)
  4.  ResetXxx() functions        per-section resets from DEFAULTS

tips.lua:
  5.  TIPS table                  all tooltip text (global, no local)

settings.lua:
  6.  Settings                    SerializeSettings, DeserializeSettings (local)
                                  SaveSettings, LoadSettings (global)

helpers.lua:
  7.  Helpers                     IsOnGrid, GetTakePPQPerQN, SetDefaultTracks, AutoDetectLyricsFile
                                  TrackHasAudio, TrackHasMIDI (local)

pipeline.lua:
  8.  Range/target resolution     ResolveAnalysisRange, FindMIDIItem, FindFirstMIDIItem,
                                  ResolveApplyPitchTarget
  9.  MIDI reading                ReadAllMIDINotesOnTrack, ReadReferenceNotes,
                                  ReadAutoTuneRefNotes, FindNearestRefPitch
  10. Pitch helpers               ApplyPitchRange
  11. Pipeline                    RunDetection, AssignPitches
  12. Result formatting           FormatResult, FormatAutoTuneResult, FormatAutoTuneYINResult

autotune.lua:
  13. Auto-tune                   FineCandidates, EvaluateParams (local), AutoTune,
                                  ApplyAutoTuneResult, ScoreNotes, AutoTuneYIN

actions.lua:
  14. Track resolution (local)    ResolveTracks, ResolveApplyPitchTracks
  15. Actions                     Preview, Generate, RunAutoTune, RunAutoTuneYIN,
                                  ApplyPitchChangesAction, SnapDraft

actions_lyrics.lua:
  16. Lyrics helpers              ReadLyricsFileContent (local); ParseLyricsFile,
                                  ParseLyricsLines (global, promoted for testability)
  17. Lyrics actions              ClearLyricsInRange (global), ClearLyricsAction,
                                  AssignLyricsAction

actions_phrases.lua:
  18. Phrases action              CreatePhrasesAction, NoteLenPPQ (global); SnapDown, SnapUp,
                                  NearestBeatPpq, NearestHalfBeatPpq, NearestQuarterBeatPpq,
                                  NearestMeasurePpq, CollectScopedAndLyrics, FindMismatches,
                                  RunPhase1, GrowEdge, RunPhase2 (local)

actions_validation.lua:
  19. Validation actions          ValidatePhrases, PhraseSimilarityAction

actions_harmonies.lua:
  20. Harmonies actions           DiatonicThirdOffset, ResolvePreservedPitches,
                                  HarmoniesAction

actions_slides.lua:
  21. Slide scan action           ScanPitchSlidesAction; ClassifySlide (local)

actions_snap_key.lua:
  22. Snap to key action          SnapToKeyAction, NearestScalePitch; NextScalePitch (local)

ui_common.lua:
  23. Shared widgets              FilteredTrackCombo, YINPresetCombo,
                                  DrawStatusResultPanel (global);
                                  KeysPresetTrackWarnings (local)

ui_tuner.lua:
  24. Tuner tab                   DrawTunerTab()

ui_slides.lua:
  25. Pitch slide tab             DrawPitchSlideTab(ctx)

ui_harmonies.lua:
  26. Harmonies tab               DrawHarmoniesTab(ctx)

ui_pitch.lua:
  27. Pitch tab                   DrawPitchTab(ctx) — Placement / Snap sub-tabs

ui.lua:
  28. UI                          Loop
  29. r.defer(Loop)               start
```

---

## Module contents

| File                                                | Contents                                                                                                                                     |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `rock_band_vocal_helper_vkr.lua`                    | Entry point: ReaImGui check, path derivation, dofile calls, startup                                                                          |
| `rock_band_vocal_helper_vkr/defaults.lua`           | `DEFAULTS`, `S`, `ResetXxx()`, constants (`MODE_*`, `RB3_*`, `LYRIC_IGNORE`)                                                                |
| `rock_band_vocal_helper_vkr/tips.lua`               | `TIPS` (global) — all tooltip strings                                                                                                        |
| `rock_band_vocal_helper_vkr/settings.lua`           | `SaveSettings`, `LoadSettings`                                                                                                               |
| `rock_band_vocal_helper_vkr/helpers.lua`            | `IsOnGrid`, `GetTakePPQPerQN`, `SetDefaultTracks`, `AutoDetectLyricsFile`; `TrackHasAudio`, `TrackHasMIDI` (local)                            |
| `rock_band_vocal_helper_vkr/pipeline.lua`           | `ResolveAnalysisRange`, `ResolveApplyPitchTarget`, `RunDetection`, `AssignPitches`, `ApplyPitchRange`, `FindNearestRefPitch`, `FormatResult` |
| `rock_band_vocal_helper_vkr/autotune.lua`           | `AutoTune`, `AutoTuneYIN`, `ApplyAutoTuneResult`, format helpers                                                                             |
| `rock_band_vocal_helper_vkr/tuner.lua`              | `StartTuner`, `StopTuner`, `RunTuner`; `FindItemAtPos`, `OpenContextForItem` (local)                                                         |
| `rock_band_vocal_helper_vkr/actions.lua`            | `Preview`, `Generate`, `RunAutoTune`, `RunAutoTuneYIN`, `ApplyPitchChangesAction`, `SnapDraft`; `ResolveTracks`, `ResolveApplyPitchTracks` (local) |
| `rock_band_vocal_helper_vkr/actions_lyrics.lua`     | `ParseLyricsFile`, `ParseLyricsLines`, `ClearLyricsInRange`, `ClearLyricsAction`, `AssignLyricsAction`; `ReadLyricsFileContent`, `ClearLyricEvents` (local) |
| `rock_band_vocal_helper_vkr/actions_phrases.lua`    | `CreatePhrasesAction`, `NoteLenPPQ`; `SnapDown`, `SnapUp`, `NearestBeatPpq`, `NearestHalfBeatPpq`, `NearestQuarterBeatPpq`, `NearestMeasurePpq`, `CollectScopedAndLyrics`, `FindMismatches`, `RunPhase1`, `GrowEdge`, `RunPhase2` (local) |
| `rock_band_vocal_helper_vkr/actions_validation.lua` | `ValidatePhrases`, `PhraseSimilarityAction`, `EditDistance`; `(no local helpers)`                                                            |
| `rock_band_vocal_helper_vkr/actions_harmonies.lua`  | `HarmoniesAction`, `DiatonicThirdOffset`, `ResolvePreservedPitches`; `ApplyLyricSuffix`, `ResolveHarmTracks`, `MeasureLengthAt`, `ReadTargetNotesInRange` (local) |
| `rock_band_vocal_helper_vkr/actions_slides.lua`     | `ScanPitchSlidesAction`; `ClassifySlide` (local)                                                                                             |
| `rock_band_vocal_helper_vkr/actions_snap_key.lua`   | `SnapToKeyAction`, `NearestScalePitch`; `NextScalePitch` (local)                                                                             |
| `rock_band_vocal_helper_vkr/ui_common.lua`          | `FilteredTrackCombo`, `YINPresetCombo`, `DrawStatusResultPanel(show_undo)` (global); `KeysPresetTrackWarnings` (local) — shared with the standalone tuner |
| `rock_band_vocal_helper_vkr/ui_tuner.lua`           | `DrawTunerTab()` — body only (no `Begin`/`BeginTabItem`), shared with the standalone tuner                                                    |
| `rock_band_vocal_helper_vkr/ui_slides.lua`          | `DrawPitchSlideTab(ctx)`                                                                                                                     |
| `rock_band_vocal_helper_vkr/ui_harmonies.lua`       | `DrawHarmoniesTab(ctx)`                                                                                                                      |
| `rock_band_vocal_helper_vkr/ui_pitch.lua`           | `DrawPitchTab(ctx)` — Placement - Built-in (detection/range/apply), Placement - Reference (reference track/apply), and Snap (Snap to Key Scale) sub-tabs |
| `rock_band_vocal_helper_vkr/ui.lua`                 | `Loop`, `r.defer(Loop)` — tab bar and everything not shared with the standalone tuner                                                        |

**Local-only functions:**

- `actions.lua`: `ResolveTracks`, `ResolveApplyPitchTracks`
- `actions_lyrics.lua`: `ReadLyricsFileContent`, `ClearLyricEvents`
- `actions_phrases.lua`: `SnapDown`, `SnapUp`, `NearestBeatPpq`, `NearestHalfBeatPpq`, `NearestQuarterBeatPpq`, `NearestMeasurePpq`, `CollectScopedAndLyrics`, `FindMismatches`, `RunPhase1`, `GrowEdge`, `RunPhase2`
- `actions_validation.lua`: (none — `EditDistance` promoted to global for testability)
- `actions_harmonies.lua`: `ApplyLyricSuffix`, `ResolveHarmTracks`, `MeasureLengthAt`, `ReadTargetNotesInRange`
- `actions_slides.lua`: `ClassifySlide`
- `actions_snap_key.lua`: `NextScalePitch`
- `helpers.lua`: `TrackHasAudio`, `TrackHasMIDI`
- `settings.lua`: `bool_to_num`, `num_to_bool`, `SerializeSettings`, `DeserializeSettings`
- `autotune.lua`: `FineCandidates`, `EvaluateParams`
- `tuner.lua`: `FindItemAtPos`, `OpenContextForItem`
- `ui_common.lua`: `KeysPresetTrackWarnings`

**Load order:**

```
lib/reaper_imgui_helpers.lua   → PitchName, Tooltip, TrackCombo, SectionHeader,
                                  FormatTime, GetTimeSelection
lib/reaper_dsp.lua             → audio analysis, YIN
lib/reaper_midi_helpers.lua    → MIDI read/write helpers
lib/reaper_script_links.lua    → SCRIPT_LINK_GROUPS, ScriptLinkBasename, IsRunningScriptLink,
                                  FilterScriptLinkGroups, LaunchReaScript, DrawGeneralLinksTab
                                  (General > Other tools sub-tab; shared with the general
                                  helper, which documents the behaviour in CLAUDE_general.md)
defaults.lua                   → S, DEFAULTS, constants
tips.lua                       → TIPS
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → IsOnGrid, GetTakePPQPerQN, SetDefaultTracks, AutoDetectLyricsFile
pipeline.lua                   → RunDetection, AssignPitches, FormatResult
autotune.lua                   → AutoTune, AutoTuneYIN
tuner.lua                      → StartTuner, StopTuner, RunTuner
actions.lua                    → Preview, Generate, RunAutoTune, RunAutoTuneYIN,
                                  ApplyPitchChangesAction, SnapDraft
actions_lyrics.lua             → ParseLyricsFile, ParseLyricsLines, ClearLyricsInRange,
                                  ClearLyricsAction, AssignLyricsAction
actions_phrases.lua            → CreatePhrasesAction, NoteLenPPQ
actions_validation.lua         → ValidatePhrases, PhraseSimilarityAction
actions_harmonies.lua          → HarmoniesAction
actions_slides.lua             → ScanPitchSlidesAction
actions_snap_key.lua           → SnapToKeyAction
ui_common.lua                  → FilteredTrackCombo, YINPresetCombo, DrawStatusResultPanel
ui_tuner.lua                   → DrawTunerTab
ui_slides.lua                  → DrawPitchSlideTab
ui_harmonies.lua               → DrawHarmoniesTab
ui_pitch.lua                   → DrawPitchTab
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultTracks(), AutoDetectLyricsFile()
```

**Second entry point: `rock_band_pitch_tuner_vkr.lua` (repo root).** Standalone Pitch
Tuner window. It has no module folder of its own — it dofiles a subset of this
helper's modules: `lib/reaper_imgui_helpers.lua`, `lib/reaper_dsp.lua`, then
`defaults.lua`, `tips.lua`, `settings.lua`, `helpers.lua`, `tuner.lua`,
`ui_common.lua`, `ui_tuner.lua`, and runs its own minimal `Loop` calling
`DrawTunerTab()` + `DrawStatusResultPanel(false)` under its own audio-source
track combo. Consequences when editing those files:

- They must keep working without the rest of the vocal helper loaded — do not add
  load-time or call-time dependencies (from the tuner code path) on modules
  outside this subset. If you add a call into `pipeline.lua`, `actions*.lua` or
  `autotune.lua` from any of them, guard it (`if X then X() end`) the way the
  general helper's `settings.lua` guards `SaveSectionConfigs`.
- **`ui.lua` is deliberately not in the list** and must never be added: its last
  line is a bare `r.defer(Loop)`, which would spawn the full helper window. That
  is the whole reason `FilteredTrackCombo`, `YINPresetCombo` and the status/result
  panel were moved out into `ui_common.lua`.
- The standalone calls `LoadSettings()` at startup and on project switch, but
  never `SaveSettings()` (saving stays in the vocal helper's General tab).
- It pins `S.tuner_tab_active = true` every frame — see the Tab-navigation stop
  note below.

---

## Public-facing concepts

### Pitch Tuner (Tuner tab)

Read-only — never modifies the project. Polls `SampleYINAt` at the current playhead position every 100 ms and displays the detected pitch.

**Display:**

- **Current pitch** — note name (`A4`) + direction indicator (green `▲` / red `▼` / grey `=`, relative to `S.tuner_prev_pitch`), nominal Hz, project timestamp. Arrow only shown when a previous pitch exists. Shows `—` before any detection.
- **History strip** — last 10 detected note names, newest on the left, dimmed. Updates only when a new pitch is added; silent/gap samples are not added to history.
- **Quiet indicator** — "Quiet — no pitch detected" written to `S.status` (same field as auto-stop messages). Grace period: 1.5 s when playing (`GetPlayState() & 1 ~= 0`); instant when stopped/scrubbing. Cleared from `S.status` when quiet_since becomes nil (pitch detected), but only if nothing else has since overwritten it. Controlled by `S.tuner_quiet_since`.
- **State indicator** — "Tuner: Active" (green) / "Tuner: Stopped" (grey) shown inline below the Start/Stop button. Tuner writes `S.status` for quiet state and auto-stop/error messages; active/stopped state is inline only and never touches `S.status`.

**Position handling:**

- When playing: reads `GetPlayPosition2()`.
- When stopped/scrubbing: reads `GetCursorPosition()` so manual playhead drags are detected.
- When position hasn't changed since last scan: skip detection silently (no status message written).

**Silence and gap detection (before YIN):**

- `FindItemAtPos` returns nil → `S.tuner_quiet_since` set — suppresses false readings in gaps between items.
- `QuickRMS(yctx, play_pos, win_s)` < `S.tuner_rms_threshold` → `S.tuner_quiet_since` set — suppresses spurious low-frequency YIN results on near-silence. `QuickRMS` converts `play_pos` to item-relative time (`math.max(0, play_pos - yctx.item_pos)`) before calling `GetAudioAccessorSamples`.

**Min RMS level slider:** `S.tuner_rms_threshold` (default 0.005, range 0.001–0.1). Exposed in the YIN Detection section. Persisted via settings.

**Auto-stop:** Timer (`tuner_last_detect_t`) resets on every successful pitch detection. If 60 s pass without any new pitch while the playhead is stationary, `StopTuner` is called automatically with a reason written to `S.status`.

**Tab-navigation stop:** `S.tuner_tab_active` is set `false` before the tab bar each frame and `true` inside the Tuner `BeginTabItem` block. `RunTuner()` checks the previous frame's value at the top of `Loop` — one frame after the user leaves the tab, the tuner stops. The standalone `rock_band_pitch_tuner_vkr.lua` has no tab bar, so it pins the flag `true` every frame before calling `RunTuner()`; without that the tuner would stop itself on the first frame after starting.

**Window-close stop:** closing either window ends its defer chain, so both call `StopTuner()` when `ImGui_Begin`'s `open` is false. Without it the `CreateTakeAudioAccessor` handle in `S.tuner_yctx` is never destroyed and holds the source audio file open until REAPER exits.

**Standalone window:** the Tuner tab body lives in `ui_tuner.lua` as `DrawTunerTab()` and is drawn by both the tab and `rock_band_pitch_tuner_vkr.lua`. The standalone adds its own audio-source combo + "Refresh tracks" button above it (the main window's live above the tab bar) and a status/result panel below it without the Undo button — it makes no project edits.

**YIN and pitch range settings** — shared with the Pitch and Pitch slide tabs (`S.yin_*`, `S.min_pitch`, `S.max_pitch`). Changes on the Tuner tab are immediately reflected elsewhere and vice versa.

**State fields:** `S.tuner_pitch`, `S.tuner_prev_pitch`, `S.tuner_pitch_name`, `S.tuner_pitch_hz`, `S.tuner_pitch_ts`, `S.tuner_quiet_since`, `S.tuner_history` — session-only, not saved. `S.tuner_rms_threshold` — persisted.

### Note Placement parameters

| Setting                     | Range             | Default | What it does                                                                                                                |
| --------------------------- | ----------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| **RMS threshold**           | 0.001 – 0.5       | 0.05    | Audio level above which a note starts. Lower = more sensitive.                                                              |
| **Low-pass cutoff**         | 0 – 8000 Hz       | 0 (Off) | Filters audio before energy detection. Cuts sibilants so note starts snap to vowels. 1500–2500 Hz is the vocal sweet spot.  |
| **Peak-split ratio**        | 0 – 95 %          | 0 (Off) | Splits a phrase wherever RMS dips below `peak × ratio`. Separates fast syllables that don't fall below absolute threshold.  |
| **Min offset to next note** | 0 – 500 ms        | 100 ms  | Forces a minimum gap before the next note. End times get capped.                                                            |
| **Min note length**         | 10 – 500 ms       | 60 ms   | Discards sub-threshold notes.                                                                                               |
| **RMS window**              | 5 – 100 ms        | 25 ms   | Analysis resolution. Trade-off between precision and speed. **Not modified by Auto-tune.**                                  |
| **Default pitch**           | RB3_MIN – RB3_MAX | 60 (C4) | Pitch assigned by Generate and Dry run. Also the fallback for Reference MIDI and Built-in detection when no pitch is found. |

### Draft Snap (Note Placement tab → Draft Snap sub-tab)

An alternative workflow when you already have roughly-placed notes with the right count but imprecise boundaries. Instead of running detection from audio, you draw notes by hand at approximately the right positions, then click **Snap draft** to lock each boundary to the nearest energy onset in the audio.

- Setting: `draft_snap_window_ms` (default 100 ms, persisted as `dsw`). How far from each note boundary to search for a sharper energy transition.
- Action: `SnapDraft()` in `actions.lua`. Reads existing notes from the MIDI destination, moves each start/end to the nearest energy onset within the window, then runs `AssignPitches` using the configured pitch source.
- Scope: active time selection, or full MIDI item if no selection.
- Complement to the automatic onset-snap in Auto Detection (which fires immediately after `GateAndSplit`). Draft Snap is for manual workflows; Auto Detection snap is automatic after RMS detection.

### Pitch sources (Pitch tab → Placement - Built-in / Placement - Reference sub-tabs — used by Apply pitch changes)

`S.pitch_mode` (`MODE_YIN` / `MODE_REFERENCE`) is no longer chosen via an explicit selector — each sub-tab sets it as a side effect while it's the active sub-tab (`DrawPitchTab` in `ui_pitch.lua`, mirrors the general helper's Tab Input pattern of a per-sub-tab body setting its own mode). `Apply pitch changes` appears in both sub-tabs so applying works from whichever source is currently active.

- **Built-in detection (YIN)** (Placement - Built-in sub-tab). Runs YIN on the audio source. Samples a window from ~30% into each note (avoids attack transient, hits steady-state vowel). Falls back to Default pitch when confidence is low. Default mode.
- **Reference MIDI** (Placement - Reference sub-tab). For each note, finds the nearest MIDI note on a chosen reference track within the configured Search tolerance (50–2000 ms). Falls back to Default pitch when nothing is in range. Reads from _all_ MIDI items on the reference track that overlap the range.

#### YIN parameters

| Setting                | Range      | Default | What it does                                                                                                                     |
| ---------------------- | ---------- | ------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **YIN threshold**      | 0.01 – 0.5 | 0.15    | Aperiodicity confidence cutoff. Lower = more confident detections, more fallbacks. Higher = more detections, more octave errors. |
| **Min frequency (Hz)** | 40 – 400   | 80 Hz   | Lower bound on detectable pitch; sets the longest lag searched.                                                                  |
| **Max frequency (Hz)** | 200 – 2000 | 1000 Hz | Upper bound on detectable pitch; sets the shortest lag. Must be > Min frequency.                                                 |
| **YIN window (ms)**    | 10 – 100   | 30 ms   | Audio length analysed per note. Capped at 80% of the note length.                                                                |

#### YIN vocal-style presets

One-shot preset combo shown above the YIN sliders on the **Pitch → Placement**, **Tuner**, and **Pitch slide** tabs/sub-tabs. Preset data: `YIN_PRESETS` in `defaults.lua`; applier: `ApplyYINPreset(preset)` in `defaults.lua`; combo widget: `YINPresetCombo(id_suffix, col)` (global, `ui.lua`) — `col` is optional and, when given, draws the "Vocal style preset" label to the left via `LabelColWidth`-style alignment instead of ImGui's native trailing label.

- Voice-range presets (low male → soprano) set all four YIN sliders **and** set + enable the Min/Max pitch constraints. Frequency bounds follow standard voice-classification ranges; raising min freq above the subharmonic range is the primary fix for octave-down errors.
- Style-only presets (breathy/raspy, clean) set only threshold and window — `nil` fields in a preset entry are left unchanged.
- Instrument preset "Piano / keys" (tuner-focused): strict threshold 0.10, 45–2000 Hz, 50 ms window, and lowers `S.tuner_rms_threshold` to 0.002 via the optional `tuner_rms` preset field. Deliberately no pitch range: RB3 keys only cover C2–C4 (48–72), but the tuner should report the true sounding pitch so the author decides how to wrap the part into the playable range. Monophonic only — chords confuse YIN.
- The combo is a command, not state: preview text is always `Apply preset...`, nothing new is persisted (applied values land in the already-persisted `S.yin_*` / pitch fields), and sliders remain the source of truth afterwards. Applying any preset clears `S.last_result`.
- Presets with `keys = true` run `KeysPresetTrackWarnings` (local, `ui.lua`): a soft sanity check that writes to `S.last_result` if the MIDI destination name contains `VOCAL`/`HARM` or the audio source name contains `VOCAL` (case-insensitive). Advisory only — both warnings can co-exist, nothing is blocked, settings apply regardless.

#### Auto-tune YIN from reference

Lives on the Placement - Built-in sub-tab. Reads existing notes from the MIDI destination at manually-corrected pitches, sweeps YIN parameter combinations, scores against those pitches, applies the best values to the sliders.

- **Fixed timings.** Note positions from the MIDI take are ground truth; only `AssignPitches` is re-run per candidate set. Much lighter than detection auto-tune.
- **CMND cache.** Pre-computes CMND arrays per `window_ms` candidate. All threshold/frequency sweeps scan the cache with no audio I/O; a different `window_ms` forces a full recompute.
- **Scoring.** Octave-insensitive pitch-class distance: `min(|ref - yin| mod 12, 12 - (|ref - yin| mod 12))`, 0–6 per note. Fallback penalty = 6. Lower = better. Ignoring octave separates pitch-class accuracy (what these parameters control) from octave correctness (what pitch range constraints fix).
- **Octave mismatch advisory.** Reports count and suggests pitch range values derived from the reference span: e.g. `"3 octave mismatches — reference spans C3–G4. Consider: min 48, max 67."` Does not auto-apply.
- **Parameters swept.** `yin_threshold`, `yin_min_hz`, `yin_max_hz`, `yin_window_ms`. Pitch range constraints excluded — they address octave correction, not pitch-class accuracy.
- **`FineCandidates`** — module-level function shared by both `AutoTune` and `AutoTuneYIN`.

### Slide Scan parameters (Pitch slide tab)

| Setting                  | Range    | Default | What it does                                                                      |
| ------------------------ | -------- | ------- | --------------------------------------------------------------------------------- |
| **Min note length (ms)** | 20 – 300 | 80 ms   | Notes shorter than this are skipped entirely.                                     |
| **Min segment (ms)**     | 5 – 100  | 20 ms   | A detected pitch run shorter than this is discarded.                              |
| **Edge skip (ms)**       | 0 – 50   | 20 ms   | Skip note start and end before sampling. Hides consonant artifacts at boundaries. |
| **Sample step (ms)**     | 5 – 50   | 10 ms   | Pitch sampling interval along the note.                                           |
| **Sample window (ms)**   | 10 – 50  | 20 ms   | YIN analysis window per sample point.                                             |

Uses current YIN threshold and frequency range from the Pitch tab.

### Pitch range constraints

Two checkbox+slider pairs (min/max). Out-of-range pitches are octave-shifted toward the range first (±12 at a time, up to 16 attempts). Clamp to the nearer endpoint only when the range is narrower than 12 semitones. The `range_adjusted` count appears in the result panel when non-zero.

### Snap to Key Scale (Pitch tab → Snap sub-tab)

Shifts each vocal note to the nearest pitch in a chosen major or minor scale. Phrase markers (pitch 105) are preserved unchanged; lyrics survive because only pitch is changed (not position or length).

| Setting             | Default | What it does                                                                                                                                                                                                                        |
| ------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Key root**        | A       | Root note of the target scale (`snap_key_root`, persisted as `skr`)                                                                                                                                                                 |
| **Quality**         | Major   | `snap_key_quality`: 0 = major, 1 = minor (persisted as `skq`)                                                                                                                                                                       |
| **Avoid collision** | Off     | `snap_avoid_collision`: after snapping, if a note lands on the same pitch as its neighbour within the same phrase, try the next closest scale degree instead. Notes across phrase boundaries are not compared. (Persisted as `sac`) |

Action: `SnapToKeyAction()` in `actions.lua`. Local helpers `NearestScalePitch` and `NextScalePitch` do the lookup. Uses `HARM_SCALE` from `defaults.lua` for the scale degree table.

Scope: active time selection, or full MIDI item after confirmation.

### Lyrics section

**File selection.** `S.lyrics_path` holds the current path (session-only, not persisted). `AutoDetectLyricsFile` checks for `lyrics.txt` in the project folder on script open and project switch. Browse opens a file picker filtered to `.txt`; non-`.txt` selections are rejected.

**Clear lyrics.** Removes all type-5 (lyric) MIDI text events from the entire destination MIDI take. Preserves entries in `LYRIC_IGNORE`. Always operates on the whole take. Wrapped in an undo block.

**Assign lyrics.** Clears first, then assigns words in order to vocal-range notes on the whole take (ignores time selection — see design decision #8). Reports: syllables added, count-mismatch warning if notes ≠ lyrics, phrase capitalization check.

**Phrase capitalization check.** For each pitch-105 note (phrase marker), finds the first vocal note at or after it, checks that its lyric starts with uppercase. Reports each violation as `mNN  Xm SS.MMMsec  "word"`.

**Create phrases.** `CreatePhrasesAction()` in `actions_phrases.lua`. Writes pitch-105 phrase-marker notes, one per lyrics.txt "line" — a newline-delimited group of words, distinct from `ParseLyricsFile`'s flat whitespace-only parse. `ParseLyricsLines` (in `actions_lyrics.lua`, sharing `ReadLyricsFileContent`'s bracket-strip with `ParseLyricsFile` so the two word lists always agree) returns each line's `start_idx`/`end_idx` into that same flat word array. Because Assign Lyrics only ever guarantees word *i* ↔ the *i*-th vocal-range note (whole take, by start time), a line's first-word index doubles as the index of its first note — no independent search is needed to find "where a line starts."

That reuse only holds if lyrics.txt still matches what's actually on the take, so before writing anything, Create Phrases cross-checks every word against the take's existing type-5 lyric text (same range Assign Lyrics would have written). Any mismatch aborts with zero notes written, listing every offending line/word/position and suggesting Assign lyrics be re-run first. Lines beyond the last note available (`lyrics.txt` longer than the take has notes for) are reported as an "unprocessed" notice, not an abort.

Placement is two passes. Pass 1 snaps each phrase's start down to the nearest 1/32-note at or before its first pitch note, and its end up to the nearest 1/32-note at or after its last pitch note, inserting phrases in line order; if a phrase's pass-1 start would leave less than a 1/32-note gap from the previous phrase's pass-1 end, Create Phrases stops there — phrases already inserted for earlier lines are kept, later lines are not attempted, and the colliding pair is reported. Pass 2 (only over phrases actually inserted) grows each phrase's lead-in/tail and the gap between neighbors in strict priority order, highest first: (1) the 1/32-note absolute gap floor, guaranteed by pass 1; (2) a guaranteed minimum of 1/32 note of individual lead-in/tail growth for *each* side; (3) growing the gap the rest of the way toward its own 1/8-note ideal; (4) any further leftover split 60/40 between lead-in/tail (lead-in prioritized), each capped at its own 1/8-note ideal, preferring to land on a measure boundary, then a beat, then a half-beat, then a quarter-beat (each tier tried in that priority order; measure only loses to beat when beat is clearly closer to the ideal target). In a tight spot this means every note gets at least a sliver of breathing room and the gap between phrases grows before either side maxes out its own spacing — not the other way around. First and last phrases have no neighbor on their outer side and grow freely toward the ideal.

All of pass 2's growth arithmetic (the ideal cap, the 60/40 split, the growth amount itself) is expressed as an integer count of 1/32-note grid units rather than fractional ppq — since a pass-1 edge is already an exact grid multiple, `pass1_edge_ppq + direction * units * thirty2_ppq` is always grid-aligned by construction, for both the start and end of every phrase. This is deliberate: an earlier fractional-ppq version could produce an off-grid edge whenever a side's allotted budget fell short of the full ideal (common — the tail side's 40% share reaches the cap less often than lead-in's 60%), which isn't just a tight-spot problem since it happened even with generous room available.

Existing pitch-105 notes on the whole take are cleared first. Scope: whole take, same as Assign Lyrics.

**Lyric file format.** Plain text. `[anything in brackets]` stripped before splitting. Words split on any whitespace.

**`LYRIC_IGNORE`** — special game events that both Clear and Assign preserve:

```lua
local LYRIC_IGNORE = {
    ['[tambourine_start]'] = true, ['[tambourine_end]'] = true,
    ['[cowbell_start]']    = true, ['[cowbell_end]']    = true,
    ['[clap_start]']       = true, ['[clap_end]']       = true,
}
```

### Harmonies tab

Copies vocal notes from a source MIDI track to up to three destination tracks, applying a pitch interval to each. Existing vocal-range notes (C1–C5) in each destination are cleared before inserting.

**Destinations.** Three rows (`harm_dst1/2/3`), each with:

- Enable checkbox (`harm_dst1/2/3_enabled`, persisted as `hd1e/hd2e/hd3e`)
- **Target track** dropdown (`harm_dst1/2/3_idx`, session-only)
- **Copy style** dropdown (`harm_dst1/2/3_mode`, persisted as `hd1m/hd2m/hd3m`)
- Lyric suffix: **Unpitched** appends `#` (`harm_dst1/2/3_lyric_unpitched`, persisted), **Hidden** appends `$` (`harm_dst1/2/3_lyric_hidden`, persisted). Both can be active — `#` is inserted before `$`. Duplicates not added if the source lyric already ends with the suffix.

**Copy styles** (indices into `HARM_MODES` in `defaults.lua`):

| Index | Label                 | Description                            |
| ----- | --------------------- | -------------------------------------- |
| 0     | Copy as-is            | No pitch change                        |
| 1     | Fixed minor 3rd above | +3 st                                  |
| 2     | Fixed major 3rd above | +4 st                                  |
| 3     | Fixed minor 3rd below | −3 st                                  |
| 4     | Fixed major 3rd below | −4 st                                  |
| 5     | Diatonic 3rd above    | +3 or +4 st per note, respecting scale |
| 6     | Diatonic 3rd below    | −3 or −4 st per note, respecting scale |
| 7     | Fixed 4th above       | +5 st                                  |
| 8     | Fixed 5th above       | +7 st                                  |
| 9     | Fixed 4th below       | −5 st                                  |
| 10    | Fixed 5th below       | −7 st                                  |
| 11    | Preserve target pitches | Pitch taken from the destination track, not the source |

New styles must be **appended** — the index is what gets persisted, so inserting
mid-table silently changes every saved project's selection.

**Preserve target pitches** is a timing-only re-sync: positions, lengths, splits
and lyrics come from the source, pitches come from whatever was already on the
destination. Its purpose is the point after a harmony part has been authored by
hand, when its pitches no longer follow any preset and only the lead's timing has
changed.

Pitch assignment is `ResolvePreservedPitches(new_notes, old_notes, windows)` in
`actions_harmonies.lua` — deliberately free of REAPER calls (hence the
precomputed `windows`) so `dev/tests/vocal_algorithms.lua` can unit test it. Each
copied note falls into exactly one of four categories, counted and reported as
indented lines under that destination's result line:

| Category   | Rule                                                        | Result line |
| ---------- | ----------------------------------------------------------- | ----------- |
| `existing` | Overlaps a destination note (largest overlap wins)           | `Existing pitches applied` |
| `closest`  | No overlap; nearest destination note start within the window | `Matching closest pitch applied` |
| `carried`  | Shares a donor with the previous note — a note split for a slide. Pitch is `donor + (source interval since the run's first note)` | `Slide interval carried` |
| `source`   | Nothing within the window; source pitch copied unchanged     | `No matching close pitch source applied` |

The window is one measure at the note's own position
(`HARM_PRESERVE_SEARCH_MEASURES` in `defaults.lua`, applied via the local
`MeasureLengthAt`), so it follows the tempo rather than being a fixed number of
seconds. A `carried` pitch landing outside C1–C5 aborts the whole action before
anything is written, matching how the interval styles' range check behaves.

**Diatonic modes** require the key settings: `harm_key_root` (0–11, default A=9, persisted as `hkr`) and `harm_key_quality` (0=major, 1=minor, persisted as `hkq`). Implemented by `DiatonicThirdOffset(note, root, quality, dir)` in `actions_harmonies.lua` using `HARM_SCALE`.

**Copy phrase markers / overdrive** — two independent flags: `harm_copy_phrase_markers` (persisted as `hcpm`) copies pitch-105 phrase-marker notes; `harm_copy_overdrive` (persisted as `hcod`) copies pitch-116 overdrive notes (`RB3_PHRASE_PITCH` / `RB3_OVERDRIVE_PITCH` in `defaults.lua`). Each destination's matching notes are cleared first, independently.

**Scope:** active time selection, or full source item after confirmation.

**Action:** `HarmoniesAction()` in `actions_harmonies.lua`. It resolves every destination's final note list *before* opening the undo block, so an out-of-range pitch on destination 3 leaves 1 and 2 untouched. Globals: `DiatonicThirdOffset`, `ResolvePreservedPitches`. Local helpers: `ResolveHarmTracks` (finds source/destination MIDI items), `ApplyLyricSuffix` (adds `#`/`$` to copied lyrics), `MeasureLengthAt`, `ReadTargetNotesInRange`.

**Track indices** (`harm_src_idx`, `harm_dst1/2/3_idx`) are session-only — not persisted.

### Validation tab

Two read-only advisory checks. Neither modifies the project; both write results to `S.last_result`.

#### Validate phrases

`ValidatePhrases()` in `actions_validation.lua`. Checks every phrase-marker region (pairs of pitch-105 notes) for six common authoring issues:

| #   | Check                | Rule                                                                   |
| --- | -------------------- | ---------------------------------------------------------------------- |
| 1   | Lyric capitalization | First vocal note after the phrase marker must have an uppercase lyric  |
| 2   | Phrase start on grid | Phrase marker start must land on a 64th-note (or coarser) boundary     |
| 3   | Phrase end on grid   | Phrase marker end must land on a 64th-note boundary                    |
| 4   | Gap to next phrase   | Gap between this phrase end and the next phrase start must be ≥ 4×64th |
| 5   | First note lead      | First vocal note must start ≥ 2×64th notes after the phrase start      |
| 6   | Last note tail       | Last vocal note must end ≥ 1×64th note before the phrase end           |

Violations are grouped by phrase position. Operates on the whole take regardless of time selection.

#### Phrase Similarity Check

`PhraseSimilarityAction()` in `actions_validation.lua`. Groups phrases by melodic similarity and flags notes that differ from the group consensus — useful for spotting copy mistakes in repeated sections.

| Setting                  | Default | What it does                                                                                                                                               |
| ------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Similarity threshold** | 80 %    | `phrase_sim_threshold` (persisted as `pst`). Minimum similarity to group two phrases together.                                                             |
| **Same key**             | On      | `phrase_same_key` (persisted as `psk`). When on, compares actual pitches; when off, compares melodic contour (interval shape) — transposition-insensitive. |

Local helper: `EditDistance` (Wagner–Fischer algorithm on pitch sequences or interval sequences depending on `phrase_same_key`).

### Save / Load

Section `VocalMIDIGenVKR`, key `settings_v1`. Auto-loads on script open.

**Saved:** all detection sliders + pitch settings (YIN params, reference tolerance) + velocity + slide scan params.
**Not saved:** track selections (`audio_idx`, `midi_idx`, `ref_idx`) — positional, brittle across sessions. Use `GetTrackGUID` if persistence is ever needed.

---

## Key design decisions

### 1. Append into an existing MIDI item

Generate writes into a user-created MIDI item, never creates items. Creating items per run produced overlap and duplication issues.

### 2. Clear before append, scoped by pitch

On Generate, deletes existing notes at every pitch the run will produce (plus Default pitch as safety) within the analysis range only. Notes at other pitches survive — reference pitches placed by hand aren't destroyed. Re-running Generate is idempotent for that pitch set.

### 3. Pitch range = octave-snap, not clamp-only

Octave artifacts from AI stem separation preserve the note name (`C5` showing up as `C2`). Octave-shifting recovers the intended pitch. Clamp is only the fallback when the range is narrower than 12 semitones.

### 4. Auto-tune scoring weights

`score = 1000 × (misses + extras) + 1000 × mean_start_diff_s + 100 × mean_length_diff_s`

Note count dominates (1 missed note ≈ 1 second of cumulative start error). Start time matters ~10× as much as length for tie-breaking.

### 5. Auto-tune skips `window_ms`

`window_ms` is a quality/speed trade-off, not a fit-to-reference parameter. It invalidates the contour cache — letting auto-tune vary it would make detection slower without improving accuracy.

### 6. `Apply pitch changes` is opt-in, not automatic

Separate button, separate flow. `ResolveApplyPitchTarget` allows partially-overlapping MIDI items; `FindMIDIItem` requires full coverage. Always enabled — both YIN and Reference MIDI are meaningful for re-pitching.

### 7. Lyrics path is session-only

`S.lyrics_path` is not written to `SerializeSettings`. File paths are machine-specific and stale paths cause confusing "file not found" errors more often than persistence saves a click. Auto-detect plus Browse cover both workflows.

### 8. Lyric functions always operate on the whole take

### 9. MODE_SINGLE is dead code — keep but don't expose

`MODE_SINGLE = 0` is defined in `defaults.lua` and handled in `settings.lua` deserialization (legacy load path downgrades it to `MODE_YIN`). The UI only exposes Built-in detection (YIN) and Reference MIDI — there is no radio button for single-pitch mode. Do not remove the constant (would break old save files) and do not expose it in new UI.

Assign lyrics ignores time selection and operates on the full MIDI take. If Assign respected a time selection, it would read from the beginning of the lyrics file but write only to notes in the selection — every word after the selection start would land on the wrong note. The RB3 vocal range filter and `LYRIC_IGNORE` table protect all non-lyric content.

### 10. Create Phrases reuses Assign Lyrics' positional indexing

Assign Lyrics only ever guarantees word *i* ↔ the *i*-th vocal-range note — never word-per-syllable alignment beyond that. A line-preserving parse over the exact same bracket-strip-then-split content (`ParseLyricsLines`, sharing `ReadLyricsFileContent` with `ParseLyricsFile`) gets "which notes belong to which line" for free, without a live search through notes for a line's first word. This is exactly why the pre-flight mismatch check exists: the whole scheme is only valid for as long as lyrics.txt and the take's actual lyric text events agree, so Create Phrases verifies that before writing anything and aborts (zero mutation) otherwise.

---

## Known limitations

1. **Auto-tune freezes the UI.** Single-threaded Lua; coroutines are not viable (see "Attempted approaches"). Freeze is acceptable for infrequent use.
2. **Apply pitch changes matches on note-start time only.** Shifted notes may pull the wrong reference pitch if the reference note "belongs" to a different syllable.
3. **Peak-split uses a global per-phrase peak.** A quiet syllable in a phrase with one loud hit may be lost if split ratio is above `quiet_rms / loud_rms`.
4. **Single audio item per track.** Without a time selection, only the first item is analyzed. With a time selection, the script picks the overlapping item. Multi-item gluing is the user's responsibility.
5. **Reference MIDI alignment is the user's job.** No auto-alignment. If Basic Pitch output is consistently early/late, nudge the MIDI item or increase search tolerance.
6. **Track selections not persisted.** Positional indices are brittle across sessions. Smart defaults partially mitigate for standard project layouts.
7. **YIN samples at 30% into the note.** Heuristic — avoids attack, stays in vowel. May land on a consonant for very fast syllables.

---

## Common change patterns

### Adding a new Note Placement slider

1. Add field to `DEFAULTS` and `S`.
2. Add to `ResetDetection`.
3. Add a TIPS entry.
4. Add to `SerializeSettings` / `DeserializeSettings` (new short key — don't reuse).
5. Add slider in the Note Placement tab with `SliderTooltip(TIPS.foo)`.
6. Thread through `RunDetection` / `GateAndSplit` / wherever it applies.
7. If auto-tune should vary it: add to `CANDIDATES_COARSE`, the `best` table, `SweepParam` calls in both passes, and a `FineCandidates` call. Only `window_ms` and `lpf_cutoff_hz` should be in the contour cache key.

### Adding a new pitch source

1. Add a `MODE_*` constant.
2. Add a radio button in the Pitch section.
3. Add a TIPS entry.
4. Add a branch in `AssignPitches`. Follow the YIN pattern: open context before the loop, close in the finally position, return nil on error, fall back to Default pitch.
5. If it needs additional inputs (track, slider): use `BeginDisabled`/`EndDisabled` so they grey out when not selected.
6. Update Apply pitch changes enable/disable logic.
7. Update settings save/load if the mode has persistent inputs.

### Adding a new action button

1. Write the action: resolve tracks → resolve range → run pipeline → update `S.status` and `S.last_result`.
2. Add a TIPS entry.
3. Add button in the UI with `Tooltip(TIPS.foo)` after.
4. Set width with `r.ImGui_CalcTextSize(ctx, label) + _bp`.
5. Wrap project modifications in `Undo_BeginBlock` / `Undo_EndBlock`.

---

## Testing checklist

- [ ] Script loads without errors when ReaImGui is missing (shows message, returns cleanly).
- [ ] Sliders move; values reflect in detection.
- [ ] Generate works with no time selection (whole audio item).
- [ ] Generate works with a time selection (limited to selection).
- [ ] Re-running Generate over the same range doesn't stack duplicates.
- [ ] Generate respects the Min offset rule (visible as gaps in MIDI editor).
- [ ] Auto-tune produces reasonable values for a section with hand-placed reference notes; result panel shows accuracy stats.
- [ ] Apply pitch changes preserves note positions and lengths but updates pitches.
- [ ] Apply pitch changes is always enabled; works for Built-in detection and Reference MIDI.
- [ ] YIN mode: Generate assigns non-default pitches for pitched vocal audio.
- [ ] YIN mode: ambiguous pitches fall back to Default without error.
- [ ] Auto-tune YIN: available on the Placement - Built-in sub-tab.
- [ ] Auto-tune YIN: runs without error, updates four YIN sliders, reports octave mismatch advisory.
- [ ] Auto-tune YIN: with no time selection, operates on all notes in the MIDI item.
- [ ] Save → modify sliders (including YIN params) → Load → all values restored.
- [ ] Reset Note Placement / Reset Pitch / Reset MIDI output return respective sections to defaults.
- [ ] Pitch range: octave-shifts out-of-range notes back; clamps when range < 12 semitones.
- [ ] Reference MIDI mode reports matched and fallback-to-default counts.
- [ ] Smart defaults: "VOCALS AUDIO" + "PART VOCALS" pre-selected on a matching project.
- [ ] Project switch: clears track selections, loads new project's settings, re-runs smart defaults.
- [ ] Undo button: disabled when nothing to undo; shows operation label in tooltip; actually undoes.
- [ ] Lyrics — Auto-detect finds `lyrics.txt` in project folder on open.
- [ ] Lyrics — Browse opens in project folder; rejects non-.txt files.
- [ ] Lyrics — Clear removes type-5 events except LYRIC_IGNORE; correct undo entry.
- [ ] Lyrics — Assign assigns to all vocal-range notes on whole take, ignoring time selection.
- [ ] Lyrics — Re-running Assign doesn't stack duplicates.
- [ ] Lyrics — Count mismatch warning appears when notes ≠ lyrics.
- [ ] Lyrics — Phrase capitalization check reports violations with timestamps.
- [ ] Lyrics — Assign is greyed out when no file selected; active after auto-detect or browse.
- [ ] Lyrics — Create phrases: whole-take scope; existing phrase markers cleared first.
- [ ] Lyrics — Create phrases: aborts with zero notes written and reports every mismatch when lyrics.txt drifts from the take's lyric text.
- [ ] Lyrics — Create phrases: lines beyond the last available note are reported as an "unprocessed" notice, not an abort.
- [ ] Lyrics — Create phrases: pass-1 phrase markers bracket each line's notes, snapped to the 1/32-note grid.
- [ ] Lyrics — Create phrases: pass-2 grows lead-in/tail spacing toward the 1/8-note ideal, preferring measure > beat > half-beat > quarter-beat boundaries; every resulting phrase-marker start and end lands exactly on the 1/32-note grid; a too-tight neighbor pair stops the run and keeps phrases already inserted.
- [ ] Lyrics — Create phrases: in a tight spot, both phrases keep at least a 1/32-note sliver of individual lead-in/tail before the gap between them grows toward its own 1/8-note ideal (not maximized individual spacing at the gap's expense).
- [ ] Lyrics — Create phrases: first/last phrase grows freely on its outer (no-neighbor) side.
- [ ] Lyrics — Create phrases is greyed out when no lyrics file selected, same as Assign lyrics.
- [ ] Tab bar: 8 tabs (General, Tuner, Note Placement, Pitch, Lyrics, Pitch slide, Harmonies, Validation); switching doesn't clear `S.status` / `S.last_result`. General has Actions/Settings/Other tools sub-tabs (Other tools shows four buttons — never the Vocal Helper itself); Pitch has Placement - Built-in/Placement - Reference/Snap sub-tabs; Note Placement (WIP) has Auto Detection/Draft Snap sub-tabs.
- [ ] Generate (replace): clears all existing vocal-range notes in the range, then inserts fresh detections; result panel says "Replaced".
- [ ] Draft Snap: rough hand-drawn notes snap to audio onsets; pitches assigned from configured pitch source.
- [ ] Snap to Key Scale: notes shift to nearest scale degree; phrase markers preserved; avoid-collision pushes duplicates to next scale degree.
- [ ] Harmonies: Apply copies notes to enabled destinations with correct pitch interval; diatonic mode respects key selection; lyric suffixes appended; phrase markers copied when checked. Target track / Copy style labels align with Source and Key, and grey out with a disabled row.
- [ ] Harmonies, Copy style = Preserve target pitches: destination pitches survive; note starts, ends, splits and lyrics match the source; a source note split for a slide gives the second half `first half + source interval`; a note with nothing within a measure keeps the source pitch; the four counts in the result panel sum to the vocal note count.
- [ ] Validate phrases: runs without error; flags violations grouped by phrase position; no project modification.
- [ ] Phrase Similarity: groups similar phrases; flags differing notes; same-key vs contour mode both work.
- [ ] Scan pitch slides: shows warning when no time selection; result in global panel.
- [ ] YIN threshold changed on Pitch slide tab is visible on Pitch tab (same `S.yin_*` state).
- [ ] YIN presets: combo appears on Pitch, Tuner, and Pitch slide tabs; a voice-range preset sets all four YIN sliders and enables Min/Max pitch; a style-only preset changes only threshold and window; status bar reports the preset label.
- [ ] Piano preset: with "PART VOCALS" MIDI destination and/or a "VOCALS"-named audio source selected, applying it shows the vocal-track warning(s) in the result panel (both when both match); with keys-named tracks, no warning; settings apply in every case.
- [ ] Save → modify slide sliders → reload project → values restored.
- [ ] Result summary shows current Min note length value, not a hardcoded string.

---

## Things on the radar

See [`_future_ideas/`](_future_ideas/) for deferred work:

- [Coroutine-based progress bar](_future_ideas/vocal_coroutine_progress.md) — live progress during slow operations; blocked by REAPER coroutine restrictions on `new_array` / `GetAudioAccessorSamples`
- [Multi-item audio support](_future_ideas/vocal_multi_item_audio.md) — analyze tracks with multiple audio items
- [Reference MIDI auto-alignment](_future_ideas/vocal_midi_auto_alignment.md) — cross-correlate onsets to find a global MIDI offset
- [Local-peak-aware splitting](_future_ideas/vocal_local_peak_splitting.md) — per-syllable peaks for phrases with uneven dynamics
- [Persist track selections](_future_ideas/vocal_persist_tracks.md) — use `GetTrackGUID` for stable cross-session track refs
- [Lyrics syllable hint](_future_ideas/vocal_lyrics_syllable_hint.md) — opt-in warning for likely multi-syllable tokens

---

## Attempted approaches and what we learned

See [`_future_ideas/`](_future_ideas/) for full context:

- [Coroutine-based progress bar](_future_ideas/vocal_coroutine_progress.md) — attempted in v2.0, reverted; `new_array` / `GetAudioAccessorSamples` return nil in coroutines (REAPER restriction)
- [Automatic key detection](_future_ideas/vocal_key_detection.md) — K-S algorithm built and removed; only 1/4 accuracy on test songs; possible improvements documented

---

## Glossary

- **Phrase** — a contiguous region of the RMS contour above the absolute threshold. May be split into multiple notes by peak-split.
