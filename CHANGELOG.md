# Changelog

Full version history for each entry-point script. Each script's `@about` block
(in its `.lua` file) keeps only its 5 most recent versions for in-app viewing;
older entries move here, newest first, when a new version pushes the count
over 5. See `CLAUDE.md` → "Changelog / `@about` trimming" for the rule.

## Rock Band General Helper

`rock_band_general_helper_vkr.lua`

**v0.9.37**
- Tab Input's Guitar/Bass guide: removed the "Notes are in play
  order" checkbox and palette mode. Palette mode flattened every
  chord into independent single-note gem events (no chord grouping
  at all), which doesn't reflect real RB charting - the guide now
  always uses the chord-shape-aware assignment the checked state
  already provided, matching how the real Guitar tab converter
  (ConvertGuitar) has always behaved (it never had a palette-mode
  equivalent). S.mc_gtr_tab_ordered and its ExtState key (mcgtor)
  are gone.

**v0.9.36**
- Guitar tab converter and Tab Input's Guitar/Bass guide are now
  chord-quality-aware: a real-guitar interval like a power chord's
  perfect fifth always gets a matching lane spread (1-3: GY/RB/YO)
  instead of whatever pitch-rank pool-cycling happened to land on,
  and the preview/guide report annotates recognized shapes with
  their chord name (e.g. "[Power chord]"). This applies by PITCH
  CLASS, not physical note count: a shape played on 3 strings but
  harmonically just root+5th+octave (e.g. "x x x 7 7 5") is
  recognized as a power chord and correctly collapses to a 2-gem
  1-3 combo, matching real RB charts, instead of being treated as
  an unrelated 3-note chord. Genuine 3-distinct-pitch-class shapes
  (real triads etc.) are unaffected - the library has no narrower
  mapping for those, though the report now names them too when
  recognized (e.g. "[Major triad]"). Consults
  lib/reaper_guitar_theory.lua (already used by the Music Theory
  Helper) via new shared BuildShapeGemMap (actions_guitar.lua),
  which replaces the near-identical shape->gem map building
  previously duplicated in AssignGems and AssignGemsForGuide
  (actions_guitar_guide.lua). actions_guitar_guide.lua's local
  TAB_OPEN tuning table is gone, now reads GUITAR_TAB_OPEN from the
  shared lib.

**v0.9.35**
- Venue > Camera pacing: new "Vocal phrase start" mode - camera cuts land
  exactly on PART VOCALS phrase-marker (pitch 105) note starts instead
  of a fixed interval; "Include jitter" has no effect (and is grayed
  out) in this mode. Themes gen uses every phrase in the song; Section
  gen only phrases starting inside the current section (a phrase
  tailing in from the previous section doesn't count, one that runs
  into the next section does); Manual gen's "Advance camera pacing"
  jumps the playhead straight to the next phrase start (new
  FindNextVocalPhraseStartPpq) and does nothing at or past the last
  phrase. If no phrase markers are found, the recurring camera loop is
  skipped for that generation but forced/bookend camera events still
  happen, and every other event category (lighting, postproc,
  keyframes) generates normally. New CollectVocalPhraseStarts
  (venue_lighting.lua) wraps CollectInstNotePositions for PART VOCALS;
  GenerateCameraEvents gained an optional phrase_positions_16ths param.
  RB3_PHRASE_PITCH is now a shared global (venue_camera.lua) instead of
  a local duplicated in actions_venue_sing_along.lua.

**v0.9.34**
- Workflow sub-tab: new "Show only unfinished" checkbox hides checked
  items (and any section whose items are all checked) so a long
  checklist doesn't force scrolling past finished work; a "done /
  total completed - pct%" progress line now sits below the
  checkboxes, always counted over the whole template regardless of
  the filter. Simplified how checked history is pruned: switching
  templates now immediately drops history for items not in the
  newly-selected file (SelectWorkflowFile), instead of only pruning
  once the total exceeded a 100-item cap compared against every
  loaded template - simpler, and matches the actual use case of
  bouncing between a couple of templates rather than keeping
  long-lived cross-template history. WORKFLOW_MAX_ITEMS is gone;
  PurgeStaleWorkflowEntries is replaced by PruneToWorkflowEntries
  (scoped to one file's entries instead of every loaded one).

**v0.9.33**
- Venue subtab intro descriptions (Keyframes, Themes gen, Events,
  Manual gen, Section gen) now wrap to a new line instead of
  clipping when the window is narrower than the text - same
  treatment the result panel already got in v0.9.24, applied to
  these five r.ImGui_Text calls (now r.ImGui_TextWrapped).

**v0.9.32**
- General tab: new "Workflow" sub-tab - a per-project authoring
  checklist sourced from a user-editable .txt template
  (resources/workflow/, one starter template "Default" included -
  selected automatically on first use if present, else the first
  template alphabetically). [Section] lines group items under a
  header; plain lines are checkable steps; a trailing {tooltip}
  (same line, or its own line right after) attaches a hover tooltip -
  an item with more than one tooltip source drops the tooltip rather
  than guessing which wins. Checking an item stamps the time and
  autosaves immediately under its own workflow_v1 project key
  (independent of this tab's own Save/Load); unchecking clears the
  timestamp. A "Show completion timestamp" checkbox (off by default,
  persisted) controls whether "Completed on dd.MM.yyyy at hh:mm" is
  displayed under checked items - the timestamp is always recorded
  regardless of the checkbox, only its display is optional. Checked
  state is keyed by (section, item label), not label alone, so
  identical item text under two different section headers (e.g.
  "Guitar" under both "Instruments Expert" and "Difficulty
  reductions") tracks separately. Switching templates carries over
  any item whose section+label matches exactly; anything else starts
  unchecked. Parse-time warnings (shown above the checklist) flag
  duplicate (section,label) pairs and unbalanced [ ] / { } bracket
  counts in a template file. Saved state auto-purges entries no
  longer present in any loaded template once the total exceeds 100
  items. New workflow.lua (parser) and actions_workflow.lua
  (persistence) modules.

**v0.9.31**
- Venue > Actions: new "Sub VENUE tracks" group splits VENUE's events
  across 6 category tracks - "VENUE normal camera", "VENUE directed
  camera", "VENUE lighting", "VENUE keyevents", "VENUE post proc",
  "VENUE special" - for easier authoring once a song has accumulated
  a lot of keyframes, then merges them back. "Copy all to subtracks"
  creates (if missing, muted by default - an editing-only split that
  shouldn't reach the final export) and re-syncs all 6; new tracks
  inherit VENUE's custom MIDI note names and get their take named
  after the track so open MIDI editor tabs are identifiable instead
  of all showing as "MIDI take". VENUE's own MIDI notes (e.g. the
  sing-cue notes at pitches 85-87) travel with "VENUE special"
  alongside its text events. "Copy all to main track" early-exits
  with a status message if no subtracks exist yet; otherwise clears
  VENUE and replaces it with their combined contents, notes included
  (confirmation popup first, mirrors the Difficulty tab's overwrite
  modal). A Subtrack dropdown plus Copy to/Copy from work on one
  category at a time
  (Copy to auto-creates the subtrack, Copy from does not; for
  Special both directions also carry VENUE's notes). New
  CategorizeVenueEvent in new actions_venue_subtracks.lua is the
  first unified 6-way VENUE event classifier - also now backs
  RemoveVenueEventsByType (actions_venue_manual.lua), replacing its
  three duplicated pattern checks with one shared classification.

**v0.9.30**
- Venue > Themes gen: song end is now resolved from the EVENTS
  track's [end] marker, not the VENUE MIDI item's own length -
  nothing is generated at or after it even if the item runs
  longer (harmless in-game; the result panel suggests trimming
  the item to [end] when it runs meaningfully past it, purely
  cosmetic, never required). Falls back to the item's length,
  with a "Didn't find [end] event, used MIDI length as end."
  note, when no [end] marker is present. When [music_end] sits
  within 10 measures of [end], the outro [lighting
  (blackout_spot)] bookend and the last scripted coop camera
  cut both target it instead of the literal end - [end]
  triggers the game's own forced camera cut, so landing our
  own cut right beside it doubled up as a jump cut. New shared
  FindEventTime in venue_awareness.lua generalizes the
  existing [music_start] lookup; FindMusicStartTime is now a
  thin wrapper over it.

**v0.9.29**
- Venue > Keyframe align: instrument-aware modes (Guitar/Bass/Keys
  notes, Drum kicks/snare) gain a third Subdivision option, "Every
  quarter beat" (16th-note grid, max 16 [next] per measure in 4/4),
  alongside the existing "Every beat" and "Every half beat". Added
  to all four places the Subdivision radio row appears (Section
  gen, Manual gen, and the Keyframes sub-tab's own row, plus the
  shared RenderKeyframeAlignCombo). New shared KeyframeSubdivQN in
  venue_lighting.lua replaces the inlined half-beat ternary in
  GenerateKeyframesForSpan/ProcessThemeSection and
  GenerateManualKeyframes (actions_venue_manual.lua).
- Fix: every keyframe insertion site (Keyframes sub-tab regenerate,
  Manual gen, Section gen, and the full-song Generate) re-snapped
  every [first]/[next] event to the nearest half-beat after
  GenerateKeyframesForSpan/GenerateThemedSectionEvents had already
  placed it - harmless while half-beat was the finest grid, but with
  quarter-beat now available it silently collapsed 1/4 and 3/4-beat
  positions onto the nearest half-beat or beat, producing duplicate/
  merged events and gaps where a real note existed. Keyframe events
  are now inserted at their already-computed position with no
  further snapping; camera/lighting/postproc/bonusfx insertion is
  unaffected. Also incidentally corrects "Section start" mode
  (align 0), which was being pulled onto the half-beat grid instead
  of landing exactly on the section marker as documented.

**v0.9.28**
- Difficulty > Keys: the "Reduce using Pro Keys (same tier)" reduction
  (v0.9.27) now also matches sustain length, not just which events
  survive. A kept event's length is set to the matching Pro Keys
  event's length (re-anchored at the Keys event's own start), instead
  of keeping whatever length it had on the copied source tier - Pro
  Keys is the master chart both are reduced from, and sustain-gap
  rules require the two charts to agree on note length as well as
  onset. No change when the checkbox is off or Pro Keys data is
  unavailable (falls back to the source tier's own length, as
  before). ReadProKeysEventQNs/HasNearbyQN in actions_difficulty_5k.lua
  replaced by ReadProKeysEvents/FindNearbyPKEvent (event-based, so
  length is available alongside timing).

**v0.9.27**
- Difficulty > Keys: new "Reduce using Pro Keys (same tier)" checkbox
  above the Copy row, checked by default. When on, Copy to Hard/
  Medium/Easy keeps only copied events that land on a note in the
  matching-tier Pro Keys track (PART REAL_KEYS_H/M/E) - mirrors a
  rhythm reduction already hand-charted on Pro Keys onto the Keys
  copy (e.g. Expert has 12 notes, Pro Keys Hard was reduced to 8 -
  Copy to Hard on Keys now keeps only the 8 matching slots), instead
  of copying every event from the tier above unfiltered. Match
  tolerance: 1/32 note in quarter-note space (tightened from an
  initial 1/16 note, which left too many events kept at faster
  tempos). Falls back to an unfiltered copy (with a status note
  explaining why) when the matching Pro Keys track isn't selected,
  missing, or empty - the button never refuses to run. New
  persisted S.diff_5k_pk_reduce. Keys-only - Guitar/Bass, Drums,
  and Pro Keys itself don't have this option.

**v0.9.26**
- Difficulty > Drums: "Kick/snare between Yellow/Blue" (Medium) is
  disabled - as implemented it doesn't match the intended rule (too
  strong). CheckDrumsYellowBlueInterleave is left defined but no
  longer wired into RunDrumsChecks, to be revisited once the rule is
  better understood.
- Fix: CompressChordOffsets (actions_difficulty_shared.lua, used by
  Keys/Guitar-Bass's Copy to Hard/Medium/Easy) only shifted a chord
  down when it had exactly 2 notes - a lone note above the target
  tier's color ceiling (e.g. a single Orange note copied to Medium)
  fell through to the drop branch instead of shifting down (e.g. to
  Blue), silently losing the note instead of relocating it. Now
  shifts whenever there are 1 or 2 notes and the shift keeps every
  note >= offset 0.

**v0.9.25**
- MIDI > Pattern: new Difficulty dropdown (All/Expert/Hard/Medium/Easy,
  default All) scopes Set Search/Set Replace/Replace All/Fill Range to
  one difficulty tier's pitch range on PART DRUMS/GUITAR/BASS/KEYS
  (Expert 96-100, Hard 84-88, Medium 72-76, Easy 60-64; All = 60-100)
  instead of touching every tier packed into the same track/time
  window. PART VOCALS/HARM1-3 (36-84) and PART REAL_KEYS*/PART
  KEYS_ANIM* (48-72) always use their own fixed range regardless of
  the dropdown; any other track keeps the previous unfiltered (0-127)
  behavior. A disabled-style "Pitch range: lo-hi" readout under the
  dropdown shows the range currently in effect. New global
  GetPatternPitchRange in actions_midi_replace.lua; ReadMIDIPatternFromTake
  (lib/reaper_midi_helpers.lua) and the local ClearPatternWindow gained
  optional min/max pitch params.

**v0.9.24**
- Result panel (bottom of every tab): long lines now wrap to the
  window's current width (ImGui_PushTextWrapPos(ctx, 0)) instead of
  overflowing and requiring the window to be stretched to read them.

**v0.9.23**
- Difficulty tab: replaced the read-only "Suggest Hard/Medium/Easy"
  preview (all four sub-tabs) with "Copy to Hard/Medium/Easy", which
  actually copies notes from the immediately higher tier onto the
  target tier's own track/range - a real starting point to hand-edit
  down instead of just a report of what would need to change.
  Two safeguards: if the source tier has no notes, it early-exits and
  reports that, writing nothing; if the target tier already has
  notes, a confirmation popup (the first modal in this codebase) asks
  before clearing and overwriting them.
  Keys and Guitar/Bass narrow their gem count at Medium/Easy by
  convention (all 5 colors exist at every tier internally) - copying
  down now compresses a chord using a color above the target's
  ceiling instead of leaving it out-of-range or dropping it outright:
  a single note or 2-note chord shifts down as a whole (e.g. Hard's
  Orange+Blue -> Medium's Blue+Yellow), otherwise (3+ note chords, or
  a shift that would go negative) the offending note is simply
  dropped. New shared CompressChordOffsets in
  actions_difficulty_shared.lua. Pro Keys copies verbatim (gems and
  lane-shift markers alike) between tracks, since its range doesn't
  shift between tiers.
  SuggestProKeysDiff/SuggestKeys5Diff/SuggestGtrBassDiff/
  SuggestDrumsDiff and their tooltips are removed, not just hidden.

**v0.9.22**
- Difficulty > Drums: layered a batch of concrete external RBN
  authoring rules on top of the existing base rules, cascading down
  from a higher difficulty to an easier one that doesn't define its
  own override:
  Cascades Hard->Medium->Easy: no kick inside a drum-fill marker
  (120-124); roll/trill markers start on an 8th/quarter-note grid
  line; a roll covers an even hit count; roll/fill density (no
  16th-rate rolls >=140 BPM on Hard, never faster than 8th-rate on
  Medium, quarter-rate required >=120 BPM on Easy else inherits
  Medium's cap); general timekeeping density - runs of constant 8th
  notes flagged >=170 BPM (Hard) / >=140 BPM (Medium, own; Easy
  inherits); a Green+Yellow/Blue double crash needs a quarter-note
  gap before it or should reduce to a single Green.
  Cascades Medium->Easy: kicks on the quarter-grid only above 100
  BPM; max 1 kick per measure at >=170 BPM. Medium's earlier
  kick+snare+cymbal-specific "3-limb hit" rule is replaced by a
  blanket max-2-simultaneous-notes rule (also cascades to Easy).
  Medium-only: a kick/snare falling between two Yellow/Blue hits;
  on-beat crash+kick is fine, off-beat/syncopated is not.
  Hard-only: Hard should have fewer kicks than Expert; the Hard-tier
  [mix N drums<config>] event should use the un-flipped/base config,
  not the disco variant.
  New "Authoring hints" block (non-pass/fail, always shown on H/M/E)
  covers the rules too qualitative to check deterministically (e.g.
  "try removing kicks from adjacent notes", "favor crash over kick").
  Fix: offset-dependent checks (identifying which pitch is the kick/
  snare/cymbal) used the simulated target tier's range even during
  Suggest, where the notes being checked are always Expert's raw
  pitches - so no offset-dependent check ever fired during Suggest.
  Now resolves against Expert's range whenever validating in Suggest
  mode.

**v0.9.21**
- Difficulty tab: added Guitar/Bass and Drums sub-tabs, matching the
  existing Pro Keys/Keys suggest-and-validate workflow. "5-Lane Keys"
  sub-tab renamed to "Keys".
  Guitar/Bass share one sub-tab (instrument radio switch, since the
  RBN authoring rules are identical between the two) validating
  PART GUITAR/PART BASS: chord count/shape (illegal Green+Orange
  combos, per-difficulty span limits), note length, overlap, sustain
  gaps, force-HOPO markers (disallowed on Medium/Easy), and
  trill/tremolo marker velocity (Hard eligibility).
  Drums gets its own sub-tab validating PART DRUMS: no 3-limb hits on
  Medium (kick+snare+cymbal/tom together), no gems paired with kick
  on Easy, roll/trill marker velocity on Hard, and an informational
  (non-pass/fail) scan of [mix N drums...] disco-flip events.
  New track fields (diff_gtr_idx, diff_bass_idx, diff_drums_idx) are
  independent of the Guitar/Drums conversion tabs' own target-track
  fields and auto-detected by name, same as the existing Pro
  Keys/Keys difficulty tracks.
  Every Validate action (all four sub-tabs) now also runs a shared
  cross-difficulty sanity check against the immediately higher tier
  (Hard vs Expert, Medium vs Hard, Easy vs Medium): flags an unedited
  copy (identical timing/shape - no reduction actually authored), and
  reports individual note counts, requiring the lower tier to have
  fewer notes than the one above it (e.g. "Expert has 500 notes and
  Hard has 450 notes: OK"). Both count toward the report's issue
  total. Not run for Expert (nothing above it) or for Suggest (which
  only ever reads Expert - there's no second authored track to
  compare against). Shared logic lives in the new
  actions_difficulty_shared.lua, reused by all four difficulty
  modules. Also fixes a latent crash in Drums > Validate Hard/All
  (roll/trill velocity issues were concatenated as a table instead of
  formatted into the report).

**v0.9.20**
- Fix: Difficulty > Pro Keys validation (Suggest/Validate) misclassified
  reserved marker pitches - overdrive (116), glissando (126), trill
  (127) - as playable notes, so they could be merged into a chord with
  a real note or fed into interval-jump/spacing/overlap checks,
  producing false-positive issues (e.g. a huge chord span or jump
  measured against an overdrive marker). Only notes in the playable
  C2-C4 range (48-72) are now treated as chord/gem events. The
  standalone "note range" check is removed since it can no longer
  trigger - filtering now happens before events are built.

**v0.9.19**
- Fix: RadioGroupWidth()'s per-option padding was a fixed pixel guess
  that could undershoot the real rendered width of a radio button at
  larger REAPER UI scales, causing the second option to overlap the
  first's label when the group's labels were short (surfaced by the
  Tab Input tab's Horizontal/Vertical row after its width group
  shrank from 5 labels to 2). Now derives padding from
  ImGui_GetFrameHeight() + the real ItemSpacing style value (tracks
  font size / UI scale) plus a fixed cushion, instead of a flat guess;
  falls back to the old fixed constant if GetFrameHeight isn't
  available. (First pass still left Horizontal/Vertical visibly tight
  - the flat "+10" buffer wasn't enough headroom on the group's widest
  label; this revision widens it.)
- General tab: "Song fade out" moved back to the Actions sub-tab
  (it's an action, not a setting).
- Venue > Actions: "List venue events"/"List event sections"/"List
  lighting/postproc" grouped under an "Analyze" label; "Generate sing
  along" under its own "Quick actions" label - same pattern as the
  General tab's "General actions"/"Audio alignment" split.
- Venue > Section gen and Manual gen: the Keyframe align dropdown is
  now the same width as the Lighting dropdown in the same sub-tab
  (was narrower than Lighting in both).

**v0.9.18**
- General tab: split into Actions (General actions, Audio alignment)
  and Settings (Song fade out, Venue preview, WIP tabs, Settings)
  sub-tabs. Save/Load moved to the end of Settings, after the values
  they persist.
- Difficulty tab: Validate row now wraps at 3 buttons per row (Expert/
  Hard/Medium, then Easy/All) instead of 4+1, since the button text is
  long. Applies to both Pro Keys and 5-Lane Keys sub-tabs.
- Tab Input tab: the Guitar/Bass, Keys/Pro Keys, and Vocal instrument
  modes are now sub-tabs instead of radio buttons. The Horizontal/
  Vertical format selector's column width no longer factors in the
  old mode-selector labels.
- MIDI tab: MIDI Alignment, MIDI Length Sync, and Pattern Replace are
  now sub-tabs (Alignment / Length / Pattern) instead of stacked
  sections.
- Venue > Section gen: the Custom/Template selector now has a "Mode"
  label, aligned with the rest of the tab's inputs.
- Venue > Manual gen: the Keyframes button moved next to the Keyframe
  align dropdown and renamed to "Add" (was on the Lighting row).
  Subdivision (Every beat/Every half beat) moved to its own labeled
  row, matching Section gen and Themes gen's style, instead of sitting
  inline after the Keyframe align dropdown.
- Venue > Keyframes: Subdivision moved to its own labeled row, same
  change as Manual gen.

**v0.9.17**
- Radio button options now align into columns within each tab view via
  a new RadioGroupWidth() helper (in lib/reaper_imgui_helpers.lua,
  same idea as BtnGroupWidth()/LabelColWidth() but for radio option
  spacing): General tab (Preview size/Sprites/Show WIPs?), Guitar WIP
  tab (Max chord/Workflow - also gained its first row-label column),
  Tab Input tab (instrument mode/format selector), Keys tab (Split
  by/Max chord/Workflow - also gained a row-label column), and Venue >
  Preview (Players/Preview size/Sprites/Show).

**v0.9.16**
- Row labels (the text before a dropdown/slider/radio group) now align
  within each tab or sub-tab via a new LabelColWidth() helper (in
  lib/reaper_imgui_helpers.lua), same idea as BtnGroupWidth() but for
  label columns instead of button widths: General tab (Preview size/
  Sprites/Show WIPs?), Difficulty > Pro Keys (Expert/Hard/Medium/
  Easy), MIDI tab (Source track/Reference track), Venue > Themes gen,
  Section gen, and Manual gen (Remove folded into the existing
  column), Venue > Preview (Players/Preview size/Sprites/Show).
  RenderKeyframeAlignCombo() gained an optional col_offset param
  (matching RenderCamPacingRow()) so it can join a tab's column.
  Also replaced two remaining hardcoded-longest-label guesses (Venue
  > Events, Venue > Keyframes) with the same helper for consistency.

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

**v1.11**
- Pitch tab: removed the "Pitch source" selector. Placement is now two
  sub-tabs, Placement - Built-in and Placement - Reference, each
  setting the active pitch source while open (mirrors the general
  helper's Tab Input pattern). Apply pitch changes appears in both.
- Harmonies: "Copy phrase markers & overdrive" split into two
  independent checkboxes/settings - Copy phrase markers (pitch 105)
  and Copy overdrive (pitch 116, new RB3_OVERDRIVE_PITCH constant).
- Lyrics tab: "File: ..." renamed to "Selected: ..." in normal text
  color (was greyed out), avoiding repeating "File" under its new
  section header.
- Min/max pitch enable checkbox tooltips now say "Uncheck" instead of
  "Disable".

**v1.10**
- UI consistency pass matching the general helper's conventions:
  row labels now sit to the left of their slider/combo/checkbox and
  align into a shared column (LabelColWidth()) instead of relying on
  ImGui's native trailing label; radio rows use RadioGroupWidth() for
  uniform option widths. Applied across General, Tuner, Pitch, Lyrics,
  Pitch slide, Harmonies, and Validation tabs (WIP Note Placement tab
  intentionally left as-is, to be redone later).
- General tab split into Actions (Refresh tracks) and Settings (WIP
  tabs, then Save/Load last) sub-tabs, mirroring the general helper.
- Pitch tab split into Placement and Snap sub-tabs; the "Pitch range"
  Min/Max pitch rows now read label -> slider -> enable checkbox
  (checkbox moved from the slider's left to its right). Pitch tab
  content moved to a new ui_pitch.lua module (DrawPitchTab).
- Lyrics tab buttons grouped under File (Auto-detect, Browse...) and
  Actions (Clear lyrics, Assign lyrics) section headers.

**v1.9**
- Related buttons now share a uniform width per group (BtnGroupWidth(),
  from lib/reaper_imgui_helpers.lua) instead of each sizing to its own
  label: Save/Load (General tab) and Auto-detect/Browse.../Clear
  lyrics/Assign lyrics (Lyrics tab).

**v1.8**
- Internal housekeeping, no behavior changes. Every button in every tab
  now goes through a shared Btn(label, height) helper (new, in
  lib/reaper_imgui_helpers.lua) instead of a manual CalcTextSize+Button
  pair, so each label string appears once instead of twice. Also fixes
  a pre-existing hardcoded button width (Save/Load, General tab) to
  compute from its label like every other button.

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
