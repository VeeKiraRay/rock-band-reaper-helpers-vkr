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
6. Use **Generate notes (append)** to write notes into the destination MIDI item.
7. Iterate. Re-running Generate over the same range clears existing notes at the affected pitches first — no duplicates stack.

**Specialized actions:**

- **Auto-tune from reference.** Manually place a few notes at Default pitch as timing reference → make time selection → Auto-tune. Coordinate descent finds detection parameters that best reproduce those reference notes. Doesn't touch pitch settings or RMS window.
- **Auto-tune YIN from reference.** Generate in YIN mode → manually correct pitches on a few notes → Auto-tune YIN. Sweeps YIN parameter combinations scored against the corrected pitches, applies best values to the sliders. Enabled only when Pitch source = Built-in detection.
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
  5.  TIPS table                  all tooltip text

settings.lua:
  6.  Settings                    SerializeSettings, DeserializeSettings (local)
                                  SaveSettings, LoadSettings (global)

helpers.lua:
  7.  Helpers                     IsOnGrid, SetDefaultTracks, AutoDetectLyricsFile
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
  13. Auto-tune                   FineCandidates, EvaluateParams, AutoTune,
                                  ApplyAutoTuneResult, ScoreNotes, AutoTuneYIN

actions.lua:
  14. Track resolution (local)    ResolveTracks, ResolveApplyPitchTracks
  15. Actions                     Preview, Generate, RunAutoTune, RunAutoTuneYIN,
                                  ApplyPitchChangesAction, ScanPitchSlidesAction,
                                  SnapToKeyAction

actions_lyrics.lua:
  16. Lyrics helpers (local)      ParseLyricsFile, ClearLyricEvents
  17. Lyrics actions              ClearLyricsInRange (global), ClearLyricsAction,
                                  AssignLyricsAction

actions_validation.lua:
  18. Validation actions          ValidatePhrases, PhraseSimilarityAction

actions_harmonies.lua:
  19. Harmonies actions           HarmoniesAction

ui.lua:
  17. UI                          Loop
  18. r.defer(Loop)               start
```

---

## Module contents

| File                                    | Contents                                                                                                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `rock_band_vocal_helper_vkr.lua`          | Entry point: ReaImGui check, path derivation, dofile calls, startup                                                                                                      |
| `rock_band_vocal_helper_vkr/defaults.lua` | `DEFAULTS`, `S`, `TIPS`, `ResetXxx()`, constants (`MODE_*`, `RB3_*`, `LYRIC_IGNORE`)                                                                                     |
| `rock_band_vocal_helper_vkr/settings.lua` | `SaveSettings`, `LoadSettings`                                                                                                                                           |
| `rock_band_vocal_helper_vkr/helpers.lua`  | `IsOnGrid`, `SetDefaultTracks`, `AutoDetectLyricsFile`; `TrackHasAudio`, `TrackHasMIDI` (local)                                                                          |
| `rock_band_vocal_helper_vkr/pipeline.lua` | `ResolveAnalysisRange`, `ResolveApplyPitchTarget`, `RunDetection`, `AssignPitches`, `ApplyPitchRange`, `FindNearestRefPitch`, `FormatResult`                             |
| `rock_band_vocal_helper_vkr/autotune.lua` | `AutoTune`, `AutoTuneYIN`, `ApplyAutoTuneResult`, format helpers                                                                                                         |
| `rock_band_vocal_helper_vkr/actions.lua`             | `Preview`, `Generate`, `RunAutoTune`, `RunAutoTuneYIN`, `ApplyPitchChangesAction`, `ScanPitchSlidesAction`, `SnapToKeyAction` |
| `rock_band_vocal_helper_vkr/actions_lyrics.lua`      | `ClearLyricsInRange` (global), `ClearLyricsAction`, `AssignLyricsAction`; `ParseLyricsFile`, `ClearLyricEvents` (local)       |
| `rock_band_vocal_helper_vkr/actions_validation.lua`  | `ValidatePhrases`, `PhraseSimilarityAction`; `EditDistance` (local)                                                           |
| `rock_band_vocal_helper_vkr/actions_harmonies.lua`   | `HarmoniesAction`; `ApplyLyricSuffix`, `DiatonicThirdOffset`, `ResolveHarmTracks` (local)                                    |
| `rock_band_vocal_helper_vkr/ui.lua`                  | `Loop`, `r.defer(Loop)`                                                                                                       |

**Local-only functions:**

- `actions.lua`: `ResolveTracks`, `ResolveApplyPitchTracks`, `ClassifySlide`, `NearestScalePitch`, `NextScalePitch`
- `actions_lyrics.lua`: `ParseLyricsFile`, `ClearLyricEvents`
- `actions_validation.lua`: `EditDistance`
- `actions_harmonies.lua`: `ApplyLyricSuffix`, `DiatonicThirdOffset`, `ResolveHarmTracks`
- `helpers.lua`: `TrackHasAudio`, `TrackHasMIDI`
- `settings.lua`: `bool_to_num`, `num_to_bool`, `SerializeSettings`, `DeserializeSettings`
- `autotune.lua`: `ScoreNotes`, `FineCandidates`, `EvaluateParams`

**Load order:**

```
lib/reaper_imgui_helpers.lua   → PitchName, Tooltip, TrackCombo, SectionHeader,
                                  FormatTime, GetTimeSelection
lib/reaper_dsp.lua             → audio analysis, YIN
lib/reaper_midi_helpers.lua    → MIDI read/write helpers
defaults.lua                   → S, DEFAULTS, TIPS, constants
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → IsOnGrid, SetDefaultTracks, AutoDetectLyricsFile
pipeline.lua                   → RunDetection, AssignPitches, FormatResult
autotune.lua                   → AutoTune, AutoTuneYIN
actions.lua                    → Preview, Generate, RunAutoTune, RunAutoTuneYIN,
                                  ApplyPitchChangesAction, ScanPitchSlidesAction, SnapToKeyAction
actions_lyrics.lua             → ClearLyricsInRange, ClearLyricsAction, AssignLyricsAction
actions_validation.lua         → ValidatePhrases, PhraseSimilarityAction
actions_harmonies.lua          → HarmoniesAction
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultTracks(), AutoDetectLyricsFile()
```

---

## Public-facing concepts

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

### Pitch sources (Pitch tab — used by Apply pitch changes)

- **Built-in detection (YIN).** Runs YIN on the audio source. Samples a window from ~30% into each note (avoids attack transient, hits steady-state vowel). Falls back to Default pitch when confidence is low. Default mode.
- **Reference MIDI.** For each note, finds the nearest MIDI note on a chosen reference track within the configured Search tolerance (50–2000 ms). Falls back to Default pitch when nothing is in range. Reads from _all_ MIDI items on the reference track that overlap the range.

#### YIN parameters

| Setting                | Range      | Default | What it does                                                                                                                     |
| ---------------------- | ---------- | ------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **YIN threshold**      | 0.01 – 0.5 | 0.15    | Aperiodicity confidence cutoff. Lower = more confident detections, more fallbacks. Higher = more detections, more octave errors. |
| **Min frequency (Hz)** | 40 – 400   | 80 Hz   | Lower bound on detectable pitch; sets the longest lag searched.                                                                  |
| **Max frequency (Hz)** | 200 – 2000 | 1000 Hz | Upper bound on detectable pitch; sets the shortest lag. Must be > Min frequency.                                                 |
| **YIN window (ms)**    | 10 – 100   | 30 ms   | Audio length analysed per note. Capped at 80% of the note length.                                                                |

#### Auto-tune YIN from reference

Enabled only when Pitch source = Built-in detection. Reads existing notes from the MIDI destination at manually-corrected pitches, sweeps YIN parameter combinations, scores against those pitches, applies the best values to the sliders.

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

### Lyrics section

**File selection.** `S.lyrics_path` holds the current path (session-only, not persisted). `AutoDetectLyricsFile` checks for `lyrics.txt` in the project folder on script open and project switch. Browse opens a file picker filtered to `.txt`; non-`.txt` selections are rejected.

**Clear lyrics.** Removes all type-5 (lyric) MIDI text events from the entire destination MIDI take. Preserves entries in `LYRIC_IGNORE`. Always operates on the whole take. Wrapped in an undo block.

**Assign lyrics.** Clears first, then assigns words in order to vocal-range notes on the whole take (ignores time selection — see design decision #8). Reports: syllables added, count-mismatch warning if notes ≠ lyrics, phrase capitalization check.

**Phrase capitalization check.** For each pitch-105 note (phrase marker), finds the first vocal note at or after it, checks that its lyric starts with uppercase. Reports each violation as `mNN  Xm SS.MMMsec  "word"`.

**Lyric file format.** Plain text. `[anything in brackets]` stripped before splitting. Words split on any whitespace.

**`LYRIC_IGNORE`** — special game events that both Clear and Assign preserve:

```lua
local LYRIC_IGNORE = {
    ['[tambourine_start]'] = true, ['[tambourine_end]'] = true,
    ['[cowbell_start]']    = true, ['[cowbell_end]']    = true,
    ['[clap_start]']       = true, ['[clap_end]']       = true,
}
```

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

Assign lyrics ignores time selection and operates on the full MIDI take. If Assign respected a time selection, it would read from the beginning of the lyrics file but write only to notes in the selection — every word after the selection start would land on the wrong note. The RB3 vocal range filter and `LYRIC_IGNORE` table protect all non-lyric content.

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
- [ ] Auto-tune YIN: enabled only when Pitch source = Built-in detection; greys out in other modes.
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
- [ ] Tab bar: 5 tabs; switching doesn't clear `S.status` / `S.last_result`.
- [ ] Scan pitch slides: shows warning when no time selection; result in global panel.
- [ ] YIN threshold changed on Pitch slide tab is visible on Pitch tab (same `S.yin_*` state).
- [ ] Save → modify slide sliders → reload project → values restored.
- [ ] Result summary shows current Min note length value, not a hardcoded string.

---

## Things on the radar

- **Coroutine-based progress bar.** Blocked: `GetAudioAccessorSamples` and `new_array` return nil in coroutines. See "Attempted approaches" for viable paths forward.
- **Multi-item audio support.** Only the first (or overlapping) item is analyzed. Multi-item gluing is the user's responsibility.
- **Reference MIDI auto-alignment.** Cross-correlating detected onsets with reference onsets to find a global offset before per-note matching.
- **Local-peak-aware splitting.** Replace global-peak split with per-syllable local peaks for phrases with very uneven dynamics.
- **Persist track selections.** Use `GetTrackGUID`. Smart defaults partially cover standard project layouts.
- **Lyrics syllable hint (opt-in).** Flag tokens with 3+ vowel groups as likely multi-syllable. Opt-in checkbox (default off). Works best for Spanish/Italian/English; unreliable for French; irrelevant for CJK. Strip trailing silent `e` before counting. Only warn at 3+ groups to reduce false positives.
- **Validation tab.** Future home for read-only advisory checks.

---

## Attempted approaches and what we learned

### Coroutine-based progress bar (attempted in v2.0, reverted)

**Goal.** Live progress bar and Cancel button during slow operations without freezing ImGui.

**What was built.** Actions created `coroutine.create(...)` over their slow body. Loop resumed once per frame, reading `(pct, label)` yield values to update a ProgressBar.

**Why it was reverted.** REAPER's C-extension APIs do not work inside a Lua coroutine:

- `reaper.new_array(n)` returns `nil` in a coroutine.
- `GetAudioAccessorSamples` returns `nil` with a nil buffer.
- Crash: `attempt to compare nil with number` in `ComputeRMSContour`.

Pure Lua computation works fine in coroutines — `GateAndSplit`, `ApplyMinOffset`, non-YIN `AssignPitches` all worked. The restriction is specifically `new_array` / `GetAudioAccessorSamples` called from `OpenYINContext` / `DetectPitchYIN`.

**Secondary bug found.** `ImGui_BeginDisabled`/`ImGui_EndDisabled` must be balanced within a single frame. A button click mid-frame changing `S.busy` broke the paired `EndDisabled`. Fix: snapshot `local is_busy = S.busy` once before any guard. This fix is in v1.9 (see the shared `BeginDisabled` convention in `CLAUDE.md`).

**Viable paths forward:**

1. Pre-compute contour synchronously, then enter a coroutine for GateAndSplit + YIN pitch assignment (pure Lua). No progress bar for audio analysis, but that part is fast.
2. Incremental state machine in Loop — `S.pending_op` advances one step per frame, no coroutines needed.
3. Background thread via external tool — not practical in standard REAPER Lua.

### Automatic key detection for diatonic harmony (attempted, removed)

**Goal.** Detect the song key from the vocal MIDI pitch histogram and/or the vocal audio stem, so diatonic harmony mode could suggest the correct major/minor key without the user having to look it up manually.

**What was built.**
- `DetectKeyFromHistogram(hist)` — Krumhansl-Schmuckler (K-S) algorithm. Computes Pearson correlation of a 12-element pitch-class histogram against 24 key profiles (12 major + 12 minor, each rotated across all 12 roots). Reports the highest-scoring key and the runner-up.
- `DetectKeyMIDIAction()` — builds a duration-weighted pitch-class histogram (weighted by PPQ note length) from all vocal-range notes in the source MIDI item, runs K-S, displays result without auto-setting the key selector.
- `DetectKeyAudioAction()` — samples the audio track with YIN at 100ms intervals across the time selection or the first 20 seconds, builds a pitch-class histogram, runs K-S, displays result.

**Why it was removed.** Tested against Tunebat (Spotify analysis) on 4 songs — only 1 match:

| Song | Tunebat | MIDI detect | Audio detect |
|---|---|---|---|
| Dove Cameron – Too Much | C# major | A# minor | A# major |
| Poets of the Fall – Carnival of Rust | F minor | F minor ✓ | F minor ✓ |
| Jonna Tervomaa – Suljettu Sydän | A minor | G major | G major |
| Indica – Ikuinen virta | B major | D# minor | D# minor |

Songs 1 and 4 are a relative-key confusion (A# minor is the relative minor of C# major; G# minor is the relative minor of B major) — the algorithm found the right pitch cluster but guessed the wrong tonic. Song 3 is a genuine failure, likely because Finnish pop/folk uses Dorian or Phrygian modal harmony that the classical K-S profiles misclassify entirely.

Root cause: K-S profiles were designed for classical music where melodies cover all 7 scale degrees fairly evenly. Vocal melodies in pop/rock concentrate on 3–4 notes, starving the correlation. Relative major/minor pairs share all 7 pitch classes; their only distinguishing signal is emphasis, which is too subtle in a sparse melody.

**Practical recommendation for users.** Look up the key on [Tunebat](https://tunebat.com) (search by song/artist), check a chord chart, or identify the root by ear. Tunebat itself can also make the relative-key mistake on sparse melodies, so verify by ear before applying diatonic harmonies.

**Possible improvements if ever revisited.**
- Present results as a paired label ("B major / G# minor") — relative-key confusion is so common that showing both is more honest than picking one.
- Implement a Temperley–Marvin key-finding algorithm, which weights notes by metrical position rather than raw duration — handles modal melody better than K-S.
- Use chord detection on the full backing mix instead of pitch detection on the vocal stem — backing track harmony is a much stronger key signal than a sparse melody line.
- Neural approaches (Essentia, Librosa) trained on pop/rock rather than classical music would likely outperform K-S here.

---

## Glossary

- **Phrase** — a contiguous region of the RMS contour above the absolute threshold. May be split into multiple notes by peak-split.
