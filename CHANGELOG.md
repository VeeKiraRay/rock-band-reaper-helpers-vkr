# Changelog

Full version history for each entry-point script. Each script's `@about` block
(in its `.lua` file) keeps only its 5 most recent versions for in-app viewing;
older entries move here, newest first, when a new version pushes the count
over 5. See `CLAUDE.md` → "Changelog / `@about` trimming" for the rule.

## Rock Band General Helper

`rock_band_general_helper_vkr.lua`

**v0.9.15**
- Related buttons (Align all audio/Align count-in, Save/Load, the
  Suggest/Validate rows on the Difficulty tab, Add note/Run guide,
  the Pattern Replace row, Venue > Actions, Venue > Events quick
  actions) now share a uniform width per group (BtnGroupWidth(), new
  in lib/reaper_imgui_helpers.lua) instead of each sizing to its own
  label.
- General tab: "Refresh tracks" moved out of Settings into its own
  "General actions" section at the top (it wasn't really a setting).
- Venue > Events: "Use letter suffix" moved to its own row below the
  quick-action buttons, restyled as a label + checkbox aligned to the
  same column as the section rows below it (was a same-line checkbox
  with an inline label).

**v0.9.14**
- Internal housekeeping, no behavior changes. Every button in every tab
  now goes through a shared Btn(label, height) helper (new, in
  lib/reaper_imgui_helpers.lua) instead of a manual CalcTextSize+Button
  pair, so each label string appears once instead of twice - the old
  pattern let the two copies drift out of sync on a rename (as
  happened this session). Also fixes two pre-existing hardcoded button
  widths (Save/Load, General tab) to compute from their label like
  every other button.

**v0.9.13**
- Fix: [prc_*] section grouping (List event sections, and the
  section-aware generator) failed to merge letter-only suffix variants
  with no number (e.g. [prc_verse_a]/[prc_verse_b]/[prc_verse_c]) -
  each was read as an unrelated standalone section instead of one
  merged section. Numbered-letter variants ([prc_verse_1a]) and bare
  forms ([prc_verse]) were unaffected.
- Venue tab: "Analysis" sub-tab renamed to "Actions". "Show event
  sections" renamed to "List event sections" for consistency with the
  tab's other buttons.
- Venue > Actions: new "List lighting/postproc" action. Lists every
  [lighting*] and *.pp] (postproc) text event on the VENUE track, in
  timeline order of appearance, each with its measure/timestamp.

**v0.9.12**
- Internal housekeeping, no behavior changes. ui_venue.lua split:
  Section gen and Manual gen sub-tabs moved to their own files
  (ui_venue_section_gen.lua, ui_venue_manual.lua); the shared camera
  pacing / keyframe align widgets became globals. Deduplicated
  shared logic (track+MIDI-take lookup, text-event delete loops,
  ticks-per-QN, camera-pacing resolution, instrument letter names)
  and removed dead code (unused preview track_end computation and a
  leftover tooltip).

**v0.9.11**
- Unified throttling for continuous MIDI reads in the Venue tab UI
  (new shared MakeProjectPoll helper: re-read only when the project
  changed, subject to a minimum interval, with a 5 s fallback).
  Events sub-tab no longer re-scans the EVENTS track every frame -
  it polls like the Active players row (1 s + project-change gate)
  and refreshes immediately after its own Add/bookends/Clear buttons.
  Players row: during playback the per-playhead dot lookup now
  updates ~2x/s instead of every frame (stopped-cursor moves still
  react instantly). Preview: the per-frame muted-instruments read
  now rides along with the existing event-cache refresh.

**v0.9.10**
- Venue > Events: with "Use letter suffix" on, Add now only inserts
  lettered forms ([prc_verse_1a] from the very first part - never the
  unlettered [prc_verse_1]), so lettered parts always merge cleanly in
  Section gen. Plain and lettered forms of one event must not be
  mixed: adding either is refused while the other exists. Events with
  no lettered variants (e.g. [prc_bre], entry cues) insert the plain
  form regardless of the checkbox.
- Venue > Events: refusal reasons no longer print next to the row
  (they took too much horizontal space). The indicator shows a short
  "-> (blocked)" - hover it for the reason - and a refused Add reports
  the reason in the result section.

**v0.9.9**
- Venue > Events: insert validation. Adds refuse duplicates (with the
  existing event's location), bare and numbered variants of the same
  event may not co-exist, numbers/letters must be used in sequence and
  placed in timeline order (letter gaps are re-offered), and no two
  text events may share a position - crowd events are exempt and may
  stack anywhere. The row indicator shows the exact event the Add
  will insert, or why it would be refused, live at the playhead.
- Venue > Events: new quick actions. "Insert bookends" places the
  minimal per-song event set ([prc_intro] + [crowd_normal] at m1,
  [music_start] at m3, [prc_outro]/[music_end]/[end] at E-5/E-2/E
  where E is the last full measure; skipped for items under 7
  measures), removing prior instances first. "Clear all" removes
  every text event from the EVENTS track (track name kept).
- Venue > Events: "Use letter suffix" is now on by default.
- Venue tab: sub-tab description lines use the default text color;
  Manual gen insert status now names its target track (VENUE).

**v0.9.8**
- Venue tab: new Events sub-tab. Inserts EVENTS-track text events at
  the playhead - [prc_*] section markers grouped by category (intro,
  structure, solo, break, tempo/energy, interlude, outro, misc,
  generic a-k), crowd events, and global markers ([music_start],
  [music_end], [end], [coda]). Each section row has a number stepper
  (bare or _1.._9) and an opt-in automatic letter suffix mode that
  reads the EVENTS track and appends the next free letter
  ([prc_verse_1] -> [prc_verse_1a] -> [prc_verse_1b]), capped to the
  valid RB3 event vocabulary. A read-only indicator shows the exact
  event the Add button will insert.

**v0.9.7**
- Venue tab: new "Active players" row shown under every sub-tab. A
  colored dot per instrument shows its state at the playhead - active
  (green), idle (blue), track muted or missing (red), or no
  play-state events (orange, treated as always in [play] state) -
  using the same mute/play-state logic as venue generation. Hover
  for details.
  Also shown in the standalone Venue Preview window.

**v0.9.6**
- Venue > Preview is now also available as a standalone script,
  rock_band_preview_vkr.lua, so the preview can sit in its own window
  next to the generation tabs. The sub-tab is unchanged; both load the
  same module files.

**v0.9.5**
- Venue > Analysis: new "Generate sing along" action. Derives VENUE
  sing-along notes (pitch 87 guitarist from HARM2, pitch 85 bassist
  from HARM3) from each harmony track's vocal phrases, merging phrases
  less than a measure apart into one continuous note. Clears/replaces
  only the pitch of each unmuted-and-present source track.

**v0.9.4**
- Venue tab: new Keyframes sub-tab. Bulk-regenerates [first]/[next]
  keyframes for every manual lighting event already on the VENUE track
  (from that lighting event to the next lighting event of any kind),
  using the shared Keyframe align/subdivision settings and its own
  Keyframe rate. Only keyframe events are cleared/replaced; camera,
  lighting, postproc, and bonus FX are untouched. Respects time
  selection; otherwise processes the whole song.

**v0.9.3**
- Venue camera generation (Themes gen and Section gen tabs) now avoids
  placing the same camera/companion event(s) back-to-back: the full set
  of event(s) placed at one generated spot (a primary shot plus its
  companion, if any) is banned for the very next spot only, then clears.
  The ban chains continuously from the forced tick-0 shot through the
  music-start anchor pick into the regular per-tick generation loop.

**v0.9.2**
- Venue Themes gen: song start now gets a forced, deterministic trio
  ([coop_all_far] / [lighting (intro)] / [ProFilm_a.pp]) at tick 0
  instead of a random camera pick, regardless of theme state.
- The first generated camera cut is now anchored to the song's actual
  musical start - an explicit [music_start] EVENTS marker if present,
  else whichever of measure 3/4 is closer to the 3-second mark - rather
  than a fixed measure 3.
- A theme's first [prc_*] section (e.g. [prc_intro]) placed right at
  tick 0 is now treated as starting at that same music-start anchor for
  lighting/postproc/dircut/bonusfx placement, instead of at tick 0.
- Fix: the song-start/music-start bookend camera picks (Themes gen and
  Section gen tabs) now emit the keys/guitar/bass swap companion event
  when applicable, matching the regular per-tick camera generation loop.

**v0.9.1**
- Difficulty validation: gap/spacing/length rules now measured in quarter
  notes via the tempo map (accurate with fluctuating BPM) with a 5% grace
  for hand-placed notes.

**v0.9**
- Added Drums, Keys, Guitar, Difficulty, Tab Input, MIDI tabs.
  Refactored into per-feature action files (actions_drums, actions_keys,
  actions_guitar, actions_midi_align, actions_midi_replace,
  actions_difficulty, actions_difficulty_5k).
- General tab: song fade out action.

**v0.2**
- Refactored into multiple module files loaded via dofile.
  Shares lib/ (ImGui helpers, DSP, MIDI) with rock_band_vocal_helper_vkr.

## Rock Band Vocal Helper

`rock_band_vocal_helper_vkr.lua`

**v1.7**
- Vocal style presets: one-click combo on the Pitch, Tuner and Pitch
  slide tabs applies YIN settings derived from standard voice ranges
  (low male, tenor, high male, alto, soprano) plus style-only variants
  (breathy/raspy, clean). Voice-range presets also enable matching
  Min/Max pitch constraints to octave-snap detection errors. A
  Piano / keys preset tunes YIN and the tuner's Min RMS level for
  quiet single-note piano stems.

**v1.6**
- Validation tab: Validate phrases checks all phrase-marker regions for
  six common authoring issues: lyric capitalization, grid snap (start and
  end on a 64th-note boundary), gap to the next phrase (>= 4x64th),
  first note lead (>= 2x64th from phrase start), and last note tail
  (>= 1x64th before phrase end). Read-only; reports violations grouped
  by phrase position.

**v1.5**
- Generate (replace): new button clears all vocal-range notes in the
  analysis range before inserting, producing a clean result. Phrase
  markers at other pitches are preserved.
- Generate (append) renamed from "Generate notes (append)".
- Pitch name display now uses Rock Band octave numbering (C1=36).
- Generate and Dry run always assign a fixed pitch (Default pitch
  slider, now on the Note Placement tab). Pitch tab is now exclusively
  for Apply pitch changes: only Built-in detection and Reference MIDI
  remain; Single pitch mode removed; YIN is the new default.
  Apply pitch changes is always enabled.
- Validation tab renamed to Pitch slide. YIN threshold and frequency
  sliders added alongside Slide Scan controls so the full pitch slide
  workflow is contained in one tab.

**v1.4**
- Slide Scan sliders added to the Validation tab: all five scan
  parameters (min note length, min segment, edge skip, sample step,
  sample window) are now adjustable and persisted with project settings.

**v1.3**
- Tab-based UI: reorganised into 5 tabs (General, Note Placement,
  Pitch, Lyrics, Validation). Track selectors and status/results panel
  remain global above and below the tab bar.
- MIDI destination track selector now appears before Audio source.
- "Note Detection" section renamed to "Note Placement".

**v1.2**
- Added Scan pitch slides: scans existing MIDI notes and reports any
  where pitch moves significantly during the note (Slide up/down,
  Scoop, Bend, Complex slide). Read-only; respects time selection.
  Includes lyric text in the report when present.

**v1.1**
- Added Auto-tune YIN from reference: sweeps YIN parameters
  (threshold, frequency range, window) against manually corrected
  pitches to find the best-fit settings automatically.
- Fixed Assign lyrics to always operate on the whole MIDI take,
  ignoring any time selection (required for correct word-to-note order).
