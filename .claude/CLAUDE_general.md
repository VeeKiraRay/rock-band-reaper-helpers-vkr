# General Helper — Script Documentation

`rock_band_general_helper_vkr.lua` provides Rock Band authoring utilities: tempo map generation from drum audio, audio track alignment, MIDI converter tools (drums, keys, guitar), MIDI alignment, and VENUE event validation.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

Five stable tabs are always visible: **General | Difficulty | Tab Input | MIDI | Venue**

Four WIP tabs appear only when **Show WIPs? = Yes** in the General tab (persisted setting, default No): **Tempo Map | Drums | Keys | Guitar**. These tabs function at a basic level but have known issues and are not ready for general users.

**General tab** — audio alignment and settings persistence.
- **Align all audio** — aligns every audio item on every track to a common reference position.
- **Align count-in** — positions the COUNT IN clip relative to the first measure.
- **Song fade out** — creates a fade-out automation envelope on the master track at the end of the project.
- Save / Load buttons for project-scoped settings.

**Tempo Map tab** — generate a REAPER tempo map from drum audio analysis.
1. Set the four source track dropdowns (KICK, SNARE, KIT, Fallback). Any can be left as "(none)".
2. Use **Show context** to check what the project's tempo marker currently says for the time selection start.
3. Use **Align audio** to align the drum audio tracks before analysis.
4. Use **Estimate initial BPM** to detect BPM and time signature from the audio (read-only).
5. Apply the estimated BPM manually to the project if needed.
6. Use **Generate tempo map** to insert REAPER tempo markers at detected downbeats.
7. Use **Auto-tune threshold** (read-only) to find the RMS threshold that best matches existing reference markers — useful before a full generation run when threshold is uncertain.
8. Use **Clear generated markers** to remove auto-generated markers and start over. Respects time selection: if active, only markers within the selection are cleared; otherwise all markers except the root are cleared.

**Drums tab** — convert GM MIDI drums to Rock Band 5-lane drum notes.
- Source track (GM MIDI) and target track (PART DRUMS) selectors.
- Ghost note threshold: notes at or below the velocity are skipped.
- Crash assignment toggle: Yellow (default) or Green lane.
- Pro Drums checkbox: inserts cymbal marker notes 110/111/112 alongside gem notes.
- Auto-insert or Preview-only workflow.

**Keys tab** — convert piano MIDI to various Rock Band keys formats.
- **Hand Split**: source, right-hand target, left-hand target. Split by MIDI channel (Guitar Pro: ch1=RH, ch2=LH) or pitch threshold.
- **Convert to Pro Keys**: octave-shift all notes into C2–C4 (48–72); optional lane shift marker insertion.
- **Pro Keys Animation**: copy C2–C4 notes from an Expert PK source to animation target tracks.
- **5-Lane Keys**: map piano melody to Expert gem pitches (96–100) using a sliding 5-semitone window.

**Guitar tab** — convert raw guitar MIDI pitches to Rock Band Expert Guitar gems (96–100).
- Source track (raw pitches from Guitar Pro or DAW) and target track (PART GUITAR) selectors.
- Wrap gap slider: rest gap in ms that starts a new phrase from Green (position 0).
- Context window slider: how many measures to look ahead when planning gem scale.
- Max chord: 2 or 3 simultaneous gems per chord event.
- Workflow: Preview (reasoning report only) or Auto-insert (writes gems, fully undoable).
- Validate Guitar: check existing gems on the target track against authoring rules.

**Difficulty tab** — difficulty validation and reduction guidance. Contains two sub-tabs:

*Pro Keys sub-tab* — validates PART REAL_KEYS_X/H/M/E (one track per difficulty).
- **Suggest Hard / Medium / Easy** — analyze Expert, report what changes are needed for each difficulty (read-only).
- **Validate Expert / Hard / Medium / Easy / All** — check against RBN Pro Keys authoring rules: note range, chord count/span, interval jumps, spacing (M/E), lane range markers.
- Track indices auto-detected by name (PART REAL_KEYS_X/H/M/E).

*5-Lane Keys sub-tab* — validates PART KEYS (all four difficulties on one track in separate pitch ranges).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–75 | Easy: 60–62.
- **Suggest Hard / Medium / Easy** — analyze Expert range, report changes needed for lower diffs (read-only).
- **Validate Expert / Hard / Medium / Easy / All** — check chord count, spacing (M/E), note length, sustain gaps.
- Track index auto-detected by name (PART KEYS).
- All actions respect time selection.

**MIDI tab** — align an imported MIDI item to the project grid.
- Source track selector.
- Move only: shifts the item so the first note lands at the time selection start.
- Move + Stretch: also adjusts the take playback rate so the last note lands at the time selection end.
- Set a time selection first, then click **Align MIDI**. Fully undoable.

**Venue tab** — VENUE MIDI track events. Contains five sub-tabs (plus Preview):

*Analysis sub-tab* — inspection tools, plus one generation action.
- **List venue events** — validates the VENUE track against the Rock Band Network spec: track name event, event type checks, unknown events, consecutive camera repeats, directed cut spacing, camera gap statistics, event usage frequency. Read-only.
- **Show event sections** — reads `[prc_*]` markers from the EVENTS track and lists detected song sections with time ranges. Letter-suffix variants (`[prc_verse_1a]`, `[prc_verse_1b]`) are merged into a single section entry. Read-only.
- **Generate sing along** — derives VENUE sing-along notes (pitch 87 guitarist from HARM2, pitch 85 bassist from HARM3) from each harmony track's vocal phrase content: a phrase (bounded by a pitch-105 marker note) qualifies when it has at least one vocal-range note (36-84); qualifying phrases less than a measure apart are merged into one continuous note. Only the pitch of a source track that is present and unmuted is cleared/replaced — a muted or missing source is skipped, leaving its existing notes untouched. If both HARM2 and HARM3 are unavailable, nothing is generated. Always processes the whole song (no time-selection scoping). Fully undoable.

*Themes gen sub-tab* — whole-song generation driven by a `.rbtheme` file.
- **Theme combo** — select a `.rbtheme` file from the `resources/themes/` folder (themes are not shipped with the project; add `.rbtheme` files to enable). Shows `(select a theme)` when none loaded; Generate button is disabled until a theme is chosen. If the `resources/themes/` folder is empty a warning is displayed and all inputs are disabled.
- **Camera pacing** — override the theme's camera cut rate, or keep Theme default.
- **Keyframe align** — global alignment mode for `[first]`/`[next]` keyframe events across all sections.
- **Generate venue events** — generates camera cuts, lighting changes, manual lighting control keyframes, and postproc effects on the VENUE track. Filters camera pools based on which PART instrument tracks are present and unmuted. Respects time selection (partial regeneration). Fully undoable.

*Section gen sub-tab* — per-section manual configuration.
- **Section selector** — pick a song section (auto-loaded from `[prc_*]` markers). Refresh button re-reads sections from the EVENTS track.
- Per-section config: Lighting preset, Keyframe align (disabled for auto/no lighting), Keyframe rate, Light blendin, Post-process, PP blendin, Directed cut at start, Bonus FX.
- **Camera pacing** — override the camera cut rate for the generated section.
- **Generate section** — generates events for the selected section only. Fully undoable.

*Manual gen sub-tab* — shot-by-shot event insertion at the playhead.
- **Normal camera** — pick any `[coop_*]` shot; **Add** inserts it at the edit cursor.
- **Directed camera** — pick any `[directed_*]` shot including BRE events; **Add** inserts it.
- **Lighting** — pick any lighting preset; **Add** inserts `[lighting (name)]`. When a manual preset is selected, shows Keyframe align + Keyframe rate controls.
- **Post proc** — pick any `[*.pp]` effect; **Add** inserts it.
- **Special** — `[bonusfx]`, `[bonusfx_optional]`, `[first]`, `[next]`, `[previous]`; **Add** inserts the chosen event.
- **Camera pacing** — shared camera pacing override (same state as other gen tabs).
- **Advance camera pacing** — moves the edit cursor forward by one jittered camera interval.
- **Generate keyframes** — generates `[first]`/`[next]` from cursor to the next lighting event / time selection end / VENUE item end. Clears existing keyframe events in the range first. Only available when a manual lighting preset is selected. Fully undoable.
- **Remove** — category dropdown (Camera / Lighting / Post proc / Special) + **Remove** button; removes matching events from time selection (if active) or full song. Fully undoable.

*Keyframes sub-tab* — bulk regeneration of `[first]`/`[next]` keyframes for every manual lighting event already on the VENUE track.
- **Keyframe align** + subdivision (when an instrument-aware mode is selected) — shared global state, same as the other gen tabs.
- **Keyframe rate** — this tab's own value (`S.venue_kf_rate`), independent of Manual gen's rate.
- **Regenerate keyframes** — scans the VENUE track for `[lighting (...)]` events that are manual (`verse`, `chorus`, `manual_cool`, `manual_warm`, `dischord`, `stomp`); for each one inside the processing range, clears and regenerates its `[first]`/`[next]`/`[previous]` events running from that lighting event to the next lighting event of any kind. Camera, lighting, postproc, and bonus FX are never touched. Respects time selection (only lighting events whose own position is inside the selection are regenerated — a section already in progress from before the selection is left untouched); otherwise processes the whole song. Fully undoable.

---

## Module contents

| File | Contents |
|---|---|
| `rock_band_general_helper_vkr.lua` | Entry point: ReaImGui check, path derivation, dofile calls, startup |
| `rock_band_general_helper_vkr/defaults.lua` | `VENUE_VALID`, `DIRECTED_GAP_MIN`, `MIDI_META_NAMES`, `S`, `TIPS` |
| `rock_band_general_helper_vkr/settings.lua` | `SaveSettings`, `LoadSettings` (project key: `RBHelperVKR/settings_v1`) |
| `rock_band_general_helper_vkr/helpers.lua` | `FindTrackByName`, `SetDefaultTempoTracks`, `SetDefaultMIDITracks`, `GetTempoContextBefore`, `GetMeasureStartTime`, `GetAudioItems` |
| `rock_band_general_helper_vkr/venue.lua` | `ListVenueEvents` (global); `FindVenueTrack`, `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats` (local) |
| `rock_band_general_helper_vkr/venue_awareness.lua` | `GetMutedInstruments`, `GetCoopRequiredInstruments`, `GetDirectedRequiredInstruments`, `FilterPool`, `ReadEventSections`, `ListEventSections`, `FindMusicStartTime` (global); `INST_TRACK_NAMES`, `ParsePrcEvent` (local) |
| `rock_band_general_helper_vkr/venue_themes.lua` | `ThemeDisplayLabel`, `LoadVenueThemes`, `GetSectionPreset`, `GetThemeCameraInterval`, `BuildLightingPool`, `BuildPostprocPool` (global); `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme` (local) |
| `rock_band_general_helper_vkr/venue_camera.lua` | `COOP_POOL`, `DIRECTED_POOL`, `PickRandom`, `JitteredInterval`, `CategorizeCoopPool`, `WeightedPickCoopEvent`, `FindCompanion`, `ComputeIdleState`, `GenerateCameraEvents` (global); camera constants (`CAM_INTERVAL_16THS` etc., partially global); `WeightedPickInstrument` (local) |
| `rock_band_general_helper_vkr/venue_sprites.lua` | `LoadVenueSprite`, `DrawVenueTooltipSprite`, `BeginVenueTooltip`, `EndVenueTooltip`, `VenueSpriteFoldersFound` (global); `DIRECTED_SPRITE_NAMES`, `VENUE_SPRITE_ROOT` (module-level globals). JPEG-only. Checks `resources/img/spritesheets/{category}/` (large) then `resources/img/spritesheets/{category} small/` (small) — no third-party fallback. Frame count is read from the filename (`{key}_f{N}_spritesheet.jpg`). Display size scales by `S.venue_preview_scale` (1 or 2). Cache stores `{image, frame_count, cols, rows}` per sprite. |
| `rock_band_general_helper_vkr/venue_lighting.lua` | `MANUAL_LIGHTING_SET`, `LIGHTING_OFFSET_16THS`, `INST_KF_MODES`, `FindNextMeasureStartPpq`, `CollectInstNotePositions`, `GenerateKeyframesForSpan`, `GenerateLightingEvents`, `GenerateThemedSectionEvents` (global); `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, lighting constants, `SnapPpqToNearestBeat`, `ProcessThemeSection` (local) |
| `rock_band_general_helper_vkr/venue_generator.lua` | `GenerateVenueEvents`, `ClearVenueTextEventsInRange`, `ClearVenueNonCameraEventsInRange`, `ClearVenueExceptLPInRange`, `ClearVenueKeyframesInRange` (global) |
| `rock_band_general_helper_vkr/tempomap.lua` | `ComputeTempoRMSContour`, `DetectOnsets`, `EstimateBPM`, `GuessTimeSig`, `GetSourcesForRange`, `FitBeatGrid`, `RmsToOnsetFlux`, `FindLocalPeak` |
| `rock_band_general_helper_vkr/actions.lua` | `AlignAudioTracks`, `AlignAllAudio`, `AlignCountIn`, `CreateSongFadeOut`; `CountInBeatSlots` (local) |
| `rock_band_general_helper_vkr/actions_tempomap.lua` | `ShowTempoContext`, `EstimateInitialBPM`, `AutoTuneThreshold`, `ClearGeneratedTempoMarkers`, `GenerateTempoMap`; `BPM_MIN`, `BPM_MAX` (locals) |
| `rock_band_general_helper_vkr/actions_drums.lua` | `ConvertDrums` (global); `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport` (local) |
| `rock_band_general_helper_vkr/actions_keys.lua` | `SplitHands`, `ConvertProKeys`, `ConvertPianoToProKeys`, `ConvertKeys5` (global); `PK_MIN`, `PK_MAX`, `PK_RANGES`, `PK_PREF_LABEL` (module-level globals); `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord` (local) |
| `rock_band_general_helper_vkr/actions_keys_guides.lua` | `ProKeysTabGuide`, `VocalTabGuide` (global); `PkEventLabel`, `ParseTabToRaws` (local) |
| `rock_band_general_helper_vkr/actions_guitar.lua` | `ConvertGuitar`, `ValidateGuitar`, `GetBPMAt`, `CompressChord`, `GemLabel`, `PitchLabel`, `ChordTypeName` (global); `GEM_MIN`, `GEM_MAX`, `GEM_LETTERS`, `CHORD_WINDOW_S`, `POOLS`, `POOLS2_NO14` (module-level globals) — Expert gem generation and authoring rule validation |
| `rock_band_general_helper_vkr/actions_guitar_guide.lua` | `ParseTabHorizontal`, `ParseTabVertical`, `ReformatVerticalTab`, `GuitarTabGuide` (global); `AssignGemsForGuide` (local) — guitar Tab Input guide |
| `rock_band_general_helper_vkr/actions_guitar_validate.lua` | `SustainThresholds`, `ReadRBGuitarNotes`, `RunValidation` (global) — validation helpers called by `ValidateGuitar` |
| `rock_band_general_helper_vkr/actions_midi_align.lua` | `AlignMIDI`, `ResizeAllMIDI` (global) |
| `rock_band_general_helper_vkr/actions_midi_replace.lua` | `SetSearchPattern`, `SetReplacePattern`, `FillRange`, `DoMIDIPatternReplace` (global); `MeasureLabel`, `NoteLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake` (local) |
| `rock_band_general_helper_vkr/actions_difficulty.lua` | `SuggestProKeysDiff`, `ValidateProKeysDiff`, `ValidateAllProKeys` (global) — Pro Keys difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_5k.lua` | `ValidateKeys5Diff`, `ValidateAllKeys5`, `SuggestKeys5Diff` (global) — 5-Lane Keys difficulty rules |
| `rock_band_general_helper_vkr/ui_keys.lua` | `DrawKeysTab`, `DrawDifficultyTab` (global) — Keys and Difficulty tab rendering |
| `rock_band_general_helper_vkr/ui_midi.lua` | `DrawTabInputTab`, `DrawMIDITab` (global) — Tab Input and MIDI tab rendering |
| `rock_band_general_helper_vkr/actions_venue_manual.lua` | `InsertVenueEventAtPlayhead`, `AdvanceCameraPacing`, `GenerateManualKeyframes`, `RemoveVenueEventsByType` (global) — Manual gen actions |
| `rock_band_general_helper_vkr/actions_venue_keyframes.lua` | `RegenerateVenueKeyframes` (global) — Keyframes tab action: bulk-regenerates keyframes for every manual lighting event on the VENUE track |
| `rock_band_general_helper_vkr/actions_venue_sing_along.lua` | `GenerateSingAlong` (global) — Analysis tab action: derives VENUE pitch 85/87 sing-along notes from HARM2/HARM3 vocal phrases; `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans` (local) |
| `rock_band_general_helper_vkr/ui_venue.lua` | `DrawVenueTab` (global) — Venue tab rendering (sub-tab bar: Analysis, Themes gen, Section gen, Manual gen, Keyframes, Preview; Keyframes and Preview delegate to their own files) |
| `rock_band_general_helper_vkr/ui_venue_preview.lua` | `DrawVenuePreviewTab` (global) — Preview sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_keyframes.lua` | `DrawVenueKeyframesTab` (global) — Keyframes sub-tab rendering |
| `rock_band_general_helper_vkr/ui.lua` | `TrackCombo` (global override supporting `sel_idx=-1`), `Loop`, `r.defer(Loop)` |

**Local-only functions:**
- `settings.lua`: `SerializeSettings`, `DeserializeSettings`
- `venue.lua`: `FindVenueTrack`, `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats`
- `venue_awareness.lua`: `INST_TRACK_NAMES`, `ParsePrcEvent`
- `venue_themes.lua`: `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme`
- `venue_camera.lua`: `WeightedPickInstrument`; camera constants `CAM_DIRECTED_COOLDOWN`, `DIRECTED_MIN_COUNT`, `DIRECTED_MAX_COUNT`, `INST_WEIGHTS`, `INST_ORDER`, `IDLE_WEIGHT`
- `venue_sprites.lua`: `_sprite_cache`, `_sprite_dirs_found`, `NormalizeSpriteKey`, `_try_load_from_dir`, `FindAndLoadSprite`, `_CAT_FOLDER`, `POSTPROC_SPRITE_NAMES`; `SPRITE_COLS`, `SPRITE_ROWS`, `SPRITE_FRAME_RATE`, `SPRITE_DISPLAY_W`, `SPRITE_DISPLAY_H`
- `venue_lighting.lua`: `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, `LIGHTING_INTERVAL_16THS`, `LIGHTING_JITTER`, `KEYFRAME_MIN_BEATS`, `KEYFRAME_MAX_BEATS`, `SnapPpqToNearestBeat`, `ProcessThemeSection`
- `actions_venue_sing_along.lua`: `RB3_VOCAL_MIN`, `RB3_VOCAL_MAX`, `RB3_PHRASE_PITCH` (module-level locals), `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans`
- `actions.lua`: `CountInBeatSlots`
- `actions_tempomap.lua`: `BPM_MIN`, `BPM_MAX` (module-level locals)
- `actions_drums.lua`: `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport`
- `actions_keys.lua`: `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord`
- `actions_keys_guides.lua`: `PkEventLabel`, `ParseTabToRaws`
- `actions_guitar.lua`: `ReadGuitarMIDI`, `GroupIntoEvents`, `IsIllegalGO`, `AssignGems`, `BuildPreviewReport`, `BuildOutNotes`, `ClearGuitarGems`
- `actions_guitar_guide.lua`: `AssignGemsForGuide`
- `actions_difficulty.lua`: `EventLabel`, `ReadPKNotes`, `GroupIntoEvents`, `GetBeatDurAt`, `QNAt`, `CheckRange`, `CheckChordCount`, `CheckChordSpan`, `CheckIntervalJumps`, `CheckSpacing`, `CheckLaneShifts`, `CheckNotesAboveExpert`, `BuildReport`, `RunPKValidation`
- `actions_difficulty_5k.lua`: `ReadK5Notes`, `GroupK5Chords`, `GetK5BeatDur`, `QNAt`, `K5Label`, `CheckK5ChordCount`, `CheckK5Spacing`, `CheckK5NoteLength`, `CheckK5SustainGaps`, `BuildK5Report`, `RunK5Checks`

Beat-fraction rules in both difficulty files (spacing, sustain gaps, note length)
are measured in quarter notes via `TimeMap2_timeToQN`, never as seconds against
one sampled BPM — with a fluctuating tempo map the seconds-length of a 1/4 note
varies inside the gap, so even grid-quantized notes fail by a few ms otherwise.
Minimum-gap rules get a 5% grace (`GRACE`) for hand-placed notes; classification
thresholds (is-sustained, sustain gray zone) use a small `EPS_QN` epsilon instead.
- `actions_midi_replace.lua`: `MeasureLabel`, `NoteLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake`
- `ui.lua`: `Loop`

**Load order:**
```
lib/reaper_imgui_helpers.lua   → Tooltip, SliderTooltip, SectionHeader, GetTrackList,
                                  FormatTime, GetTimeSelection  (TrackCombo also loaded
                                  but shadowed locally in ui.lua for -1 support)
lib/reaper_dsp.lua             → (loaded; not currently used by general helper)
lib/reaper_midi_helpers.lua    → FindFirstMIDIItem, InsertNotes, ClearNotesAtPitchesInRange, …
defaults.lua                   → S, VENUE_VALID, TIPS, constants
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → FindTrackByName, SetDefaultTempoTracks, SetDefaultMIDITracks,
                                  SetDefaultDifficultyTracks, GetTempoContextBefore,
                                  GetMeasureStartTime, GetAudioItems
venue.lua                      → ListVenueEvents
venue_awareness.lua            → GetMutedInstruments, GetCoopRequiredInstruments,
                                  GetDirectedRequiredInstruments, FilterPool,
                                  ReadEventSections, ListEventSections, FindMusicStartTime
venue_themes.lua               → ThemeDisplayLabel, LoadVenueThemes, GetSectionPreset,
                                  GetThemeCameraInterval, BuildLightingPool, BuildPostprocPool
venue_camera.lua               → COOP_POOL, DIRECTED_POOL, PickRandom, JitteredInterval,
                                  CategorizeCoopPool, WeightedPickCoopEvent, FindCompanion,
                                  ComputeIdleState, GenerateCameraEvents; camera globals
                                  (CAM_INTERVAL_16THS etc.)
venue_sprites.lua              → LoadVenueSprite, DrawVenueTooltipSprite, BeginVenueTooltip,
                                  EndVenueTooltip; VENUE_SPRITE_ROOT, VENUE_SPRITE_SELF_ROOT,
                                  DIRECTED_SPRITE_NAMES, POSTPROC_SPRITE_NAMES (module globals)
venue_lighting.lua             → MANUAL_LIGHTING_SET, LIGHTING_OFFSET_16THS, INST_KF_MODES,
                                  FindNextMeasureStartPpq, CollectInstNotePositions,
                                  GenerateKeyframesForSpan, GenerateLightingEvents,
                                  GenerateThemedSectionEvents
venue_generator.lua            → GenerateVenueEvents, ClearVenueTextEventsInRange,
                                  ClearVenueNonCameraEventsInRange, ClearVenueExceptLPInRange,
                                  ClearVenueKeyframesInRange
tempomap.lua                   → ComputeTempoRMSContour, DetectOnsets, EstimateBPM,
                                  GuessTimeSig, GetSourcesForRange, FitBeatGrid,
                                  RmsToOnsetFlux, FindLocalPeak
actions.lua                    → AlignAudioTracks, AlignAllAudio, AlignCountIn, CreateSongFadeOut
actions_tempomap.lua           → ShowTempoContext, EstimateInitialBPM, AutoTuneThreshold,
                                  ClearGeneratedTempoMarkers, GenerateTempoMap
actions_drums.lua              → ConvertDrums
actions_keys.lua               → SplitHands, ConvertProKeys, ConvertKeys5
actions_keys_guides.lua        → ProKeysTabGuide, VocalTabGuide
actions_guitar.lua             → ConvertGuitar, ValidateGuitar, GetBPMAt
actions_guitar_guide.lua       → ParseTabHorizontal, ParseTabVertical, ReformatVerticalTab, GuitarTabGuide
actions_guitar_validate.lua    → SustainThresholds, ReadRBGuitarNotes, RunValidation
actions_midi_align.lua         → AlignMIDI, ResizeAllMIDI
actions_midi_replace.lua       → SetSearchPattern, SetReplacePattern, FillRange, DoMIDIPatternReplace
actions_difficulty.lua         → SuggestProKeysDiff, ValidateProKeysDiff, ValidateAllProKeys
actions_difficulty_5k.lua      → ValidateKeys5Diff, ValidateAllKeys5, SuggestKeys5Diff
actions_venue_manual.lua       → InsertVenueEventAtPlayhead, AdvanceCameraPacing,
                                  GenerateManualKeyframes, RemoveVenueEventsByType
actions_venue_keyframes.lua    → RegenerateVenueKeyframes
actions_venue_sing_along.lua   → GenerateSingAlong
ui_keys.lua                    → DrawKeysTab, DrawDifficultyTab
ui_midi.lua                    → DrawTabInputTab, DrawMIDITab
ui_venue.lua                   → DrawVenueTab
ui_venue_preview.lua           → DrawVenuePreviewTab
ui_venue_keyframes.lua         → DrawVenueKeyframesTab
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultTempoTracks(),
                                  SetDefaultMIDITracks(), SetDefaultDifficultyTracks()
```

**`SCRIPT_MDIR` global.** The entry point sets `SCRIPT_MDIR = _mdir` (global) so dofile'd modules can access the module folder path for filesystem operations. The `local _mdir` variable is not accessible from dofile'd modules. **`SCRIPT_DIR` global.** The entry point also sets `SCRIPT_DIR = _dir` (repo root) for accessing shared resources under `resources/` (e.g. `resources/themes/`, `resources/img/spritesheets/`).

**Second entry point: `rock_band_preview_vkr.lua` (repo root).** Standalone Venue Preview window. It has no module folder of its own — it dofiles a subset of this helper's modules: `lib/reaper_imgui_helpers.lua`, then `defaults.lua`, `settings.lua`, `helpers.lua`, `venue.lua`, `venue_awareness.lua`, `venue_sprites.lua`, `ui_venue_preview.lua`, and runs its own minimal `Loop` calling `DrawVenuePreviewTab()`. Consequences when editing those files:
- They must keep working without the rest of the general helper loaded — do not add load-time or call-time dependencies (from the preview code path) on modules outside this subset. `settings.lua` guards its `SaveSectionConfigs`/`LoadSectionConfigs` calls (`if X then X() end`) for this reason.
- `venue_sprites.lua` reads `SCRIPT_DIR` at dofile time; both entry points set it before loading.
- The standalone calls `LoadSettings()` at startup and on project switch, but never `SaveSettings()` (saving stays in the general helper's General tab).

**`TrackCombo` override.** The general helper uses `sel_idx = -1` to mean "no track configured" for drum source dropdowns. The lib's `TrackCombo` always expects a non-negative index. `ui.lua` defines `TrackCombo` as a **global** — overriding the lib version for all modules — that adds a `(none)` selectable entry and handles -1. The extracted `ui_keys.lua`, `ui_midi.lua`, and `ui_venue.lua` all call `TrackCombo` and rely on this global override.

### Save / Load

Section `RBHelperVKR`, key `settings_v1`. Auto-loads on script open.

**Saved:** all tempo map sliders — primary source (`tm_rms_threshold`, `tm_rms_window_ms`, `tm_search_window_ms`, `tm_drift_threshold_ms`, `tm_bpm_failsafe`, `tm_first_measure`, `tm_timesig_num`, `tm_override_failsafe`), fallback source (`tm_fb_rms_threshold`, `tm_fb_rms_window_ms`, `tm_fb_use_flux`), and auto-tune (`tm_autotune_density`).
**Not saved:** track indices — positional, brittle. `SetDefaultTempoTracks` re-detects tempo map tracks by name; `SetDefaultMIDITracks` re-detects PART DRUMS and PART GUITAR target tracks by name. Both only assign fields that are still -1 (do not override saved state).

---

## Upcoming features

See [`_future_ideas/`](_future_ideas/) for deferred work:

- [Guitar Allow G+O Checkbox](_future_ideas/general_gtr_allow_go.md) — opt-in to preserve G+O chords without substitution
- [Tempo Map Auto-Scan](_future_ideas/general_tempo_map_auto_scan.md) — auto-find usable analysis window when the first measure has no onsets
- [Beat-Level Markers](_future_ideas/general_beat_level_markers.md) — sub-measure tempo resolution for rubato recordings

---

## Feature: Generate tempo map

### Overview

Two read/write phases:

1. **Estimate initial BPM** (read-only) — detects onsets from the drum audio, estimates BPM via inter-onset interval analysis, and guesses the time signature. Reports results; writes nothing.
2. **Generate tempo map** — inserts REAPER tempo markers. Uses the existing project tempo marker as a phase anchor, propagates a beat grid forward measure-by-measure, and inserts a new marker only where the detected downbeat deviates from the expected position by more than the drift threshold.

### Design decisions

**Anchor-based approach, not blind beat tracking.** The standard workflow aligns the drum audio so that the first true downbeat lands at the configured start measure (default: measure 3). Because REAPER knows where that measure starts (`TimeMap2_beatsToTime`), the phase is given — no phase-detection step needed. The algorithm confirms and tracks the grid forward from that anchor.

**Measure-level markers only.** The community standard is one tempo marker per measure; skip measures where the drums appear on time. Beat-level (four per bar) is a future enhancement.

**Self-correcting grid propagation.** Each detected downbeat becomes the new reference for the next expected downbeat. Slight early/late errors don't accumulate — they're absorbed by the new marker.

**Fallback audio source chain.** Priority: KICK → SNARE → KIT → Fallback. For each analysis window, the highest-priority source with a detected signal is used. Fallbacks exist for sections where kick/snare are absent (intros, transitions, quiet passages).

**Time signature from preceding project marker.** On full-song runs, read the marker at time 0. On time-selection runs, read the last marker at or before `sel_start`. Implemented by iterating all markers and keeping the last one whose `timepos ≤ query time`. User can override the numerator via a slider (0 = inherit).

**Failsafe stops on large BPM drift.** If the instantaneous BPM implied by two consecutive detected downbeats deviates from the initial BPM by more than `bpm_failsafe` (default ±10), generation stops and reports the position and measured BPM. The "Override limit" checkbox bypasses this for intentional large tempo changes.

**Drift threshold controls marker density.** A marker is inserted only when `|detected_time - expected_time| > drift_threshold_ms`. At the 30 ms default, on-time measures produce no marker.

**Remove-then-reinsert within range, not skip-existing.** Before inserting, `GenerateTempoMap` deletes all existing tempo markers where `timepos >= t_s AND timepos < t_e` (iterating in reverse). Re-running is idempotent. Markers before `t_s` (including the root marker at t=0) are never touched.

### REAPER APIs used

| API | Purpose |
|---|---|
| `r.CountTempoTimeSigMarkers(proj)` | Count existing markers |
| `r.GetTempoTimeSigMarker(proj, idx)` | Read a marker: `(ok, timepos, measurepos, beatpos, bpm, num, denom, linear)` |
| `r.AddTempoTimeSigMarker(proj, timepos, bpm, num, denom, linear)` | Insert a tempo marker — **REAPER snaps `timepos` to the nearest beat boundary of the current tempo map**. To place a marker at a specific audio time T, the prior marker must carry a BPM that makes T an exact beat boundary (see two-pass insertion below). |
| `r.DeleteTempoTimeSigMarker(proj, idx)` | Delete a marker (iterate in reverse) |
| `r.TimeMap2_beatsToTime(proj, n)` | Project beats → project time (n = total beats from project start) |
| `r.TimeMap2_timeToBeats(proj, t)` | Project time → beats |
| `r.GetAudioAccessorSamples(...)` | Read PCM samples from audio item |
| `r.CreateTakeAudioAccessor(take)` / `r.DestroyAudioAccessor(aa)` | Audio I/O — always free the accessor |
| `r.new_array(n)` | Sample buffer allocation (1-based, main Lua thread only) |

`TimeMap2_beatsToTime` counts from the project's beat grid. To find the start of measure N in 4/4: `beat_pos = (N - 1) * 4`, then `timepos = r.TimeMap2_beatsToTime(proj, beat_pos)`. For other time sigs, use the numerator in place of 4.

### State fields (`S`)

```lua
-- Persisted (primary source)
S.tm_rms_threshold      = 0.15   -- onset detection threshold (higher than vocal; kick stems are louder/cleaner)
S.tm_rms_window_ms      = 10     -- RMS window in ms (short for drums)
S.tm_search_window_ms   = 100    -- max ms either side of expected beat to search
S.tm_drift_threshold_ms = 30     -- min deviation (ms) before inserting a marker
S.tm_bpm_failsafe       = 10     -- stop if BPM drifts > this from initial
S.tm_first_measure      = 3      -- measure number where the first marker is generated
S.tm_timesig_num        = 0      -- override numerator (0 = inherit from project marker)
S.tm_override_failsafe  = false  -- bypass BPM failsafe

-- Persisted (fallback source — guitar / keys)
S.tm_fb_rms_threshold   = 0.10   -- onset threshold for the fallback track (typically lower than drums)
S.tm_fb_rms_window_ms   = 10     -- RMS window for fallback source
S.tm_fb_use_flux        = false  -- apply onset-flux transform (max(0, rms[i]-rms[i-1])) to fallback

-- Persisted (AutoTuneThreshold)
S.tm_autotune_density   = 0      -- expected onsets/measure density guard (0 = disabled)

-- Not persisted — auto-detected by name on load
S.tm_kick_idx           = -1
S.tm_snare_idx          = -1
S.tm_kit_idx            = -1
S.tm_fallback_idx       = -1
```

### Algorithm detail

#### `ComputeTempoRMSContour`
Simplified variant of the vocal script's `ComputeRMSContour`. No LPF pass (drums are broadband). Channels are averaged. Uses the same audio accessor + `new_array` + sliding window pattern. Returns `{contour, t_start, t_step}` or `nil, error`.

#### `DetectOnsets`
Peak picker over the RMS contour. For each run above threshold: walk forward until the value drops, record the start of the run as the onset (first-crossing heuristic — drum transients rise fast). Enforce `min_gap_s` by discarding detections within the gap of the last accepted onset.

#### `EstimateBPM`
1. Compute adjacent IOIs from the onset list.
2. Convert each IOI to BPM: `bpm = 60 / ioi`.
3. Also vote for `bpm/2` and `bpm×2` (half-time/double-time harmonics).
4. Bin all votes into a 1-BPM-wide histogram from `BPM_MIN` (60) to `BPM_MAX` (250).
5. Return the histogram peak and `consistent_count / (onset_count - 1)` as confidence.

**Project BPM independence.** `EstimateBPM` is purely IOI-based — it only looks at time differences between consecutive onsets. The project's current tempo marker has no effect on the BPM calculation. What *does* affect behavior: when no time selection is active, `EstimateInitialBPM` scans measure-by-measure using `GetMeasureStartTime` (which calls `TimeMap2_beatsToTime`). If the project BPM differs greatly from the song BPM, the scan windows cover wrong time spans. Failure modes at very large deviations (~±80 BPM):
- **Project BPM too low** — wide project measures, many onsets per window, harder stability check.
- **Project BPM too high** — narrow project measures may exhaust the intro before any drum is found.
Workaround: use a time selection over a known drum section, or apply a rough tempo marker first.

#### `GuessTimeSig`
Given `beat_dur` and `onset_times`:
1. Snap the anchor to the nearest onset within 50 ms.
2. For each candidate numerator `{4, 3, 6}`:
   a. Compute `measure_dur = num × beat_dur`.
   b. Count onsets that fall within ±`beat_dur × 0.25` of beat 0.
   c. Score = `count × num / #onsets`.
3. The numerator with the highest score wins.
4. IOI 4-beat override: if the winner is not 4/4, count consecutive-onset pairs spaced `4 × beat_dur` apart (±15%). Two or more such pairs override to 4/4.
5. Minimum evidence threshold: if winner ≠ 4/4 and `best_score < 1.25`, override to 4/4. Genuine 3/4 scores ≥ 1.5; evenly-spaced kicks produce ~1.05 (noise, not real evidence).

#### `FitBeatGrid`
```
t = anchor_t
while next expected downbeat is within analysis range:
    next_exp = t + num × beat_dur
    search onsets in [next_exp − search_window, next_exp + search_window]
    require onset at least beat_dur × (num − 0.5) ahead of t  ← minimum-advance guard
    if found:
        step_dur = (found_t − t) / num
        grid[i] = {expected_t, detected_t, deviation_s, bpm = 60/step_dur, source}
        t = found_t
    else:
        grid[i] = {expected_t, detected_t=nil, deviation_s=nil, bpm=current_bpm, source=nil}
        t = next_exp
```

The minimum-advance guard (`beat_dur × (num - 0.5)`) prevents snapping to beat-4 kicks or subdivisions when the onset list is dense — see the known bug fix below.

#### Time selection boundary rules

**Do not change these without discussion — established from user feedback.**

**Start boundary.** First generated measure:
- If `sel_s` is within 1 ms of a measure downbeat → that measure is the first (inclusive).
- Otherwise → first complete measure boundary *after* `sel_s`.
- Implementation: use `format_timestr_pos(sel_s, '', 1)` for current measure number, compare `sel_s` against `GetMeasureStartTime(current_measure)` with 1 ms tolerance.
- **Do NOT use `TimeMap2_timeToBeats`** — it returns beats within the current measure (0–num), not total beats.

**End boundary.** Last generated measure:
- If `sel_e` is within 1 ms of a measure downbeat → that measure IS included (inclusive end).
- Otherwise → last complete measure whose downbeat falls within the selection.
- `FitBeatGrid` must use `t <= sel_e + 0.001` (not strict `<`).

**No time selection.** Use `S.tm_first_measure` as the anchor. Analysis range = full audio item.

#### `GenerateTempoMap` algorithm
1. Validate: at least one tempo marker exists in the project.
2. Get `bpm0, num, denom` via `GetTempoContextBefore`.
3. Compute `first_gen_measure` from time selection start (boundary rules above), or use `S.tm_first_measure`.
4. Get `measure_start_t` via `GetMeasureStartTime(first_gen_measure, num)`.
5. Detect onsets from all source tracks via `GetSourcesForRange`. If `S.tm_fallback_idx >= 0`, also compute a separate `fb_ci` contour from the fallback track (applying `RmsToOnsetFlux` if `S.tm_fb_use_flux` is set).
6. `grid = FitBeatGrid(...)`.
7. **Fallback peak-fill (optional):** if `fb_ci` is available, walk all grid entries that have no detected onset. For each, call `FindLocalPeak(fb_ci, entry.expected_t, search_window_s)` and accept the result if `peak_v >= S.tm_fb_rms_threshold`. Accepted peaks fill in `detected_t`, `deviation_s`, `bpm`, and mark `source = 'fallback (peak)'`. This fills gaps in sections where kick/snare are absent but guitar or keys are present.
8. **Pass 1 (collect):** iterate grid, apply drift threshold and failsafe check, collect insert positions.
9. **Pass 2 (BPM assignment):** for each insert position, compute span from prior marker to this one, covering N measures. `bpm = N × num × 60 / span`. N estimated as `round(span / measure_dur_est)` — necessary because on-time intermediate measures produce no marker, so naive N=1 gives a BPM N× too low.
10. Delete existing markers in range (reverse order), then insert in forward order.
11. Report: markers inserted, measures scanned, failsafe triggered (if any).

### Known bug (fixed) — FitBeatGrid wrong-onset snapping and REAPER marker snapping

**Symptom.** With a low RMS threshold (detecting beats 1–4, not just downbeats), `GenerateTempoMap` placed markers at wrong positions. High threshold (downbeat-only) worked correctly.

**Root cause 1 — wrong onset snapping.** When every beat is detected, two candidates can fall within `±search_window` at each grid step: the beat-4 kick of the current measure (closer if BPM estimate is slightly off) and the beat-1 kick of the next measure. FitBeatGrid would snap to beat-4, place a marker there, and all subsequent steps inherited the wrong phase.

**Fix:** minimum-advance guard — only accept onsets at least `beat_dur × (num - 0.5)` ahead of the previous anchor.

**Root cause 2 — REAPER marker snapping.** `AddTempoTimeSigMarker` snaps `timepos` to the nearest beat boundary of the *current* tempo map. Even when FitBeatGrid found the correct onset, the marker landed at `expected_t` (the beat boundary) rather than `detected_t` (the actual onset) if the anchor BPM was slightly wrong.

**Fix:** two-pass insertion. Collect all insert positions first, then compute each marker's BPM so that the *next* insert position is an exact beat boundary under that BPM. Insert in forward order.

**Root cause 3 — N-measures BPM error.** When intermediate measures are on-time (below drift threshold), no marker is inserted for them. A span covering N measures with naive `60 × num / span` (assuming N=1) gives a BPM N× too low.

**Fix:** estimate N as `round(span / measure_dur_est)` and use `N × num × 60 / span`.

### Things on the radar

See [Upcoming features](#upcoming-features) and [`_future_ideas/`](_future_ideas/) for deferred tempo map work.

### Known limitations

- Beat-level markers not generated; only measure starts.
- Time signature detection is a heuristic; always verify for unusual signatures.
- Large project BPM mismatch (>~80 BPM off) can cause incorrect or missing results from `EstimateInitialBPM` when no time selection is active. Use a time selection over a known drum section, or apply a rough tempo marker first.
- RMS contour computed synchronously — UI freezes during analysis of long sections (same constraint as vocal auto-tune; see `CLAUDE.md` Lua specifics).
- If no onset is found near an expected downbeat (gap section, quiet intro), the grid extrapolates at current BPM with no marker. User should verify those sections manually.

---

## Feature: VENUE validation

`ListVenueEvents` reads the VENUE MIDI track and reports:

1. **Track name event (type 3).** Must be exactly one, at PPQ 0, with message `"VENUE"`.
2. **Unexpected event types.** All non-track-name events should be type 1 (Text). Any other types are listed with their type name.
3. **Unknown events.** Each text event is checked against `VENUE_VALID` (the full Rock Band Network event table in `defaults.lua`). Unknown events are listed.
4. **Consecutive camera repeats.** Any `[coop...]` or `[directed...]` event that immediately follows an identical event.
5. **Directed cut spacing.** Any `[directed...]` event whose next camera event starts within `DIRECTED_GAP_MIN` (2.0 s). Listed with position, event text, gap duration, and what follows.
6. **Camera gap statistics.** Average, slowest, and fastest cut durations for: coop→any transitions, and directed→coop transitions.
7. **Event usage frequency.** All text events sorted by usage count descending.

### `VENUE_VALID`

A large constant table in `defaults.lua` listing every known valid VENUE text event string. When a text event is not in this table, it's reported as unrecognized. The table is not automatically updated — it must be maintained manually as the Rock Band Network spec evolves.

---

## Feature: VENUE event generator

`GenerateVenueEvents` writes randomised camera cuts and lighting changes to the VENUE MIDI track. It is a direct port and modernisation of `_external_docs/random_venue_gen.lua` (v0.4).

### Instrument track awareness

Five PART tracks are checked. A track is treated as **unavailable** if it is **absent** from the project OR if its mute flag is set:

| Letter | Track name   |
|--------|--------------|
| `d`    | PART DRUMS   |
| `v`    | PART VOCALS  |
| `b`    | PART BASS    |
| `g`    | PART GUITAR  |
| `k`    | PART KEYS    |

Camera events that require an unavailable instrument are removed from the pool before randomising. "Require" is parsed from the event name:
- Coop: the letter code between `[coop_` and the first subsequent `_` (e.g. `[coop_dv_near]` → needs `d` + `v`). `all` and `front` variants have no requirement.
- Directed: full instrument name in the event string (e.g. `[directed_guitar_cls]` → needs `g`). `all`, `crowd`, `stagedive`, `crowdsurf` variants have no requirement. `duo_*` events with a two-letter suffix require both letters; `duo_drums/bass/guitar` require that instrument + vocals.

### Event pools

| Pool constant       | Count | Description |
|---------------------|-------|-------------|
| `COOP_POOL`         | 39    | Cooperative camera shots — single-instrument (`[coop_d_*]`, `[coop_v_*]`, …) and multi-instrument (`[coop_dv_near]`, `[coop_bg_behind]`, …) |
| `DIRECTED_POOL`     | 38    | Director-style cuts. **Intentionally excludes `[directed_bre]` and `[directed_brej]`** — these are BRE (Big Rock Ending) events that must be authored manually |
| `MANUAL_LIGHTING_POOL` | 6  | Lighting modes that require `[first]`/`[next]` keyframe control events: verse, chorus, manual_cool, manual_warm, dischord, stomp |
| `AUTO_LIGHTING_POOL`   | 15 | Self-contained lighting modes that need no control events: loop_cool, loop_warm, harmony, frenzy, silhouettes, silhouettes_spot, searchlights, sweep, strobe_slow, strobe_fast, blackout_slow, blackout_fast, flare_slow, flare_fast, bre |

**Bonus FX remain manual** (`[bonusfx]`, `[bonusfx_optional]`) except via a theme's `dircut_at_start`/`bonusfx_at_start` section presets. Post-process (`[*.pp]`) is otherwise theme-driven only (each section's `allowed_postprocs` preset), **except** for the forced song-start post-process below, which fires unconditionally.

### Generated event types

1. **Forced song-start trio** — `[coop_all_far]`, `[lighting (intro)]`, `[ProFilm_a.pp]`, all placed at tick 0 (the VENUE item's literal start). Fixed, not randomised, and fires **regardless of theme state** — see "Song-start bookends and the music-start anchor" below.
2. **First generated camera cut (coop)** — a weighted pick (not a fixed measure) anchored to the resolved **music-start position**: an explicit `[music_start]` EVENTS-track marker if present, else whichever of measure 3/4 lands closer to the 3-second mark from song start.
3. **Camera cuts (coop)** — placed at jittered intervals from one interval after the music-start anchor onward, up to the blackout position.
4. **Camera cuts (directed)** — 1–4 cuts placed at random positions in the middle 80% of the range, each followed by a 2× cooldown before the next coop cut.
5. **Final coop cut** — placed at the blackout position (32 sixteenths before range end).
6. **Lighting changes** — placed from 32 sixteenths in, at jittered intervals. Each picks from the combined manual + auto pool.
7. **Control keyframes (`[first]`/`[next]`)** — generated only for manual lighting events. `[first]` at the lighting event position, then `[next]` every 1–4 beats until the next lighting change.
8. **Bookend: `[lighting (blackout_spot)]`** — placed 32 sixteenths before range end.

### Song-start bookends and the music-start anchor

The literal start of the VENUE item (tick 0) is not the same as where the song's music
actually begins — songs conventionally have a count-in/silence first. `GenerateVenueEvents`
resolves a single **music-start anchor** (`FindMusicStartTime` in `venue_awareness.lua`, plus
a measure-3/4 fallback computed in `venue_generator.lua`) and uses it in two places:

- **First generated camera cut** — placed at the anchor instead of a fixed measure, so the
  timing adapts to tempo (or to an explicit `[music_start]` marker when the chart has one).
- **First `[prc_*]` section, if placed at tick 0** — when a theme is active and the earliest
  detected section (typically `[prc_intro]`) sits right at the song's literal start,
  `GenerateVenueEvents` re-anchors that section's `t_start` to the music-start position before
  handing sections to `GenerateThemedSectionEvents` — so its lighting/postproc/dircut/bonusfx
  land at the real musical start rather than during the count-in. A section the author already
  placed later is left untouched.

The forced song-start trio (tick 0) is independent of this anchor and always fires — see
"Generated event types" above.

### Timing constants (local in `venue_generator.lua`, future S-field candidates)

| Constant                  | Default | Meaning |
|---------------------------|---------|---------|
| `CAM_INTERVAL_16THS`      | 24      | Base interval between coop cuts (~1.5 measures in 4/4) |
| `CAM_JITTER`              | 0.35    | ±35% interval randomisation |
| `CAM_DIRECTED_COOLDOWN`   | 2.0     | Multiplier: minimum wait after a directed cut |
| `CAM_START_MIN_16THS`     | 32      | Earliest first cut (measure 2) |
| `CAM_START_MAX_16THS`     | 48      | Latest first cut (measure 3) |
| `DIRECTED_MIN_COUNT`      | 1       | Minimum directed cuts per generation range |
| `DIRECTED_MAX_COUNT`      | 4       | Maximum directed cuts per generation range |
| `LIGHTING_INTERVAL_16THS` | 128     | Base interval between lighting changes (~8 measures) |
| `LIGHTING_JITTER`         | 0.25    | ±25% interval randomisation |
| `LIGHTING_OFFSET_16THS`   | 32      | Lighting generation starts this many sixteenths into the range |
| `KEYFRAME_MIN_BEATS`      | 1       | Minimum `[first]`/`[next]` interval (beats) |
| `KEYFRAME_MAX_BEATS`      | 4       | Maximum `[first]`/`[next]` interval (beats) |

These constants are intentionally not in `S` yet — sliders for UI configuration are planned but not implemented.

### Time selection behaviour

- **No selection:** generates across the full VENUE MIDI item. Both bookend events are placed.
- **Selection active:** clamps to the overlap of the selection and the MIDI item. Only events in the selected range are cleared and regenerated; events outside are preserved. Bookend events (`[lighting (intro)]`) are **not** placed — a partial regeneration assumes the surrounding context already has them.

### Undo

Uses `Undo_BeginBlock2(0)` / `Undo_EndBlock2(0, ...)` with `MarkTrackItemsDirty(track, item)` — required for MIDI text event changes to register in REAPER's undo history (see `CLAUDE.md` undo section).

---

## Feature: Event section detection

`ReadEventSections` and `ListEventSections` parse `[prc_*]` text events from the EVENTS MIDI track to split the song into named sections. When a venue theme is active, `GenerateVenueEvents` calls `ReadEventSections` to drive section-aware lighting, postproc, and directed-cut placement.

### Parsing `[prc_*]` event names

Pattern: inner string after `[prc_` is matched against `_(%d+)([a-z]?)$` to detect an optional number+letter suffix.

| Event              | name        | num | letter | Behaviour         |
|--------------------|-------------|-----|--------|-------------------|
| `[prc_verse]`      | `verse`     | nil | nil    | standalone        |
| `[prc_verse_1]`    | `verse`     | 1   | nil    | standalone        |
| `[prc_verse_1a]`   | `verse`     | 1   | `"a"`  | groups with `_1b`, `_1c`, … |
| `[prc_gtr_solo_2b]`| `gtr_solo`  | 2   | `"b"`  | groups with `_2a`, `_2c`, … |

**Name extraction:** `inner:sub(1, #inner - #num_str - #letter - 1)` strips the `_num[letter]` suffix. Names containing underscores (e.g. `gtr_solo`, `build_up`) are handled correctly because the suffix regex is anchored at end-of-string.

### Grouping rule

Walking events sorted by time: if the current event has a letter suffix AND the immediately preceding section record has the same `(name, num)` AND that record is also lettered → extend the existing section (`sub_count++`). Otherwise → new section record.

**Non-consecutive letter events are not grouped.** If `[prc_verse_1a]` appears, then an unrelated section, then `[prc_verse_1b]`, they become two separate sections.

### Section record

```lua
{
  name        = "verse",   -- base name parsed from event
  num         = 1,         -- number suffix (nil if absent)
  is_lettered = true,      -- true when grouped from letter-suffix events
  sub_count   = 3,         -- count of individual prc events in the group
  t_start     = 32.0,      -- project time of first event
  t_end       = 64.0,      -- project time when next section starts; song_end_t for the last
}
```

`song_end_t` passed to `ReadEventSections` defaults to the VENUE item end (from `FindVenueTrack`), falling back to `r.GetProjectLength(0)`.

### Display output (`ListEventSections`)

```
Event sections: 8 total

  1.  intro                   0.000s  ->  32.145s
  2.  verse x1                32.145s  ->  1m 04.290s   (3 parts)
  3.  chorus x1               1m 04.290s  ->  1m 36.435s
  4.  verse x2                1m 36.435s  ->  2m 08.580s   (2 parts)
  ...
```

The `(N parts)` annotation appears only for lettered groups with `sub_count > 1`.

---

## Glossary

- **Onset** — the moment a drum hit begins; specifically where audio energy rises sharply above background. Onset times are the raw input to BPM estimation and beat-grid fitting.
- **IOI (inter-onset interval)** — time between two consecutive onsets. Converting IOIs to BPM (`60 / ioi`) and histogramming them is how `EstimateBPM` finds the dominant tempo without reference to the project's tempo map.
- **Downbeat** — the first beat of a measure (beat 1). `FitBeatGrid` specifically searches for downbeats, not all beats. Markers are placed at downbeat positions.
- **Beat grid** — the expected sequence of downbeat times, computed by stepping forward from an anchor by `num × beat_dur` per measure. When a detected onset is near an expected downbeat, that onset becomes the new anchor.
- **Drift threshold** — the minimum deviation (ms) between a detected downbeat and the expected beat-grid position that triggers a new tempo marker. Below the threshold the measure is considered on-time.
- **Contour** — the sequence of per-window RMS values over an audio item. The onset detector runs over this contour, not raw samples.
- **RMS window** — the length of audio (ms) averaged into one contour value. Shorter = finer time resolution, sharper onset edges; longer = smoother.
- **Tempo marker** — a REAPER project object that sets BPM and time signature from a given project time forward. The root marker at index 0 is always present; `ClearGeneratedTempoMarkers` always preserves it. When a time selection is active, `ClearGeneratedTempoMarkers` only removes markers within the selection; otherwise it removes all markers except the root.
- **VENUE** — a special MIDI track in Rock Band charts carrying camera cut, lighting, and post-processing text events. Events must match the Rock Band Network specification exactly; unknown events cause compile errors.
