# General Helper — Script Documentation

`rock_band_general_helper_vkr.lua` provides Rock Band authoring utilities: tempo map generation from drum audio, audio track alignment, MIDI converter tools (drums, keys, guitar), MIDI alignment, and VENUE event validation.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

Seven stable tabs are always visible: **General | Difficulty | Overdrive | Tab Input | MIDI | Venue | Metadata**

**Overdrive tab** — generates overdrive phrases (116), unisons, drum fills (120-124) and vocal overdrive for the whole song, and validates what is already authored (read-only, with an overview strip). One page: an Instrument dropdown (All / Drums / Bass / Guitar / Keys / Vocals — groups, so tracks that must match are always written together), one settings block per generator with an include checkbox, one **Generate** button, then **Validate**. A time selection is ignored. See "Feature: Overdrive" below.

**Metadata tab** has two sub-tabs. **Genre** converts a real-world genre into the closest supported major genre and subgenre; it is a pure lookup over two static tables and is listed first because it works with no project open at all. Like Difficulty it states outright that it is advisory - but for a different reason, and the two wordings should not be merged: Difficulty's inputs are measurements of the author's own MIDI, whereas every genre mapping is a hand-made judgment call, so only Genre invites the reader to push back on it. **Difficulty** estimates what rank a finished Expert chart should carry. Both are read-only.

Note the two Difficulty features are different things and are deliberately kept apart. The **Difficulty tab** copies and validates authored lower-difficulty charts — it writes MIDI. **Metadata > Difficulty** estimates what rank a finished Expert chart should carry — it is read-only and writes nothing, ever.

Four WIP tabs appear only when **Show WIPs? = Yes** in the General tab (persisted setting, default No): **Tempo Map | Drums | Keys | Guitar**. These tabs function at a basic level but have known issues and are not ready for general users.

**General tab** — audio alignment and settings persistence. Contains four sub-tabs:

*Actions sub-tab*
- **Refresh tracks** — re-scans the project's track list.
- **Align all audio** — aligns every audio item on every track to a common reference position.
- **Align count-in** — positions the COUNT IN clip relative to the first measure.
- **Song fade out** — creates a fade-out automation envelope on the master track at the end of the project.
- **Remove 2x kicks** — works out which kicks on `PART DRUMS_2X` are the drummer's second foot and deletes those from `PART DRUMS`. `PART DRUMS_2X` is the complete chart (every kick at 96) and is never thinned; the only thing that can change there is a leftover pitch-95 note being put back to 96. Matching between the tracks is by musical position, so a tempo change does not affect it. Whole track: a time selection does not narrow it. Safe to re-run — the second run finds nothing to remove and creates no undo point. See "Feature: double-bass detection" below.

*Settings sub-tab*
- Venue preview size/sprite display options, Show WIPs? toggle.
- Save / Load buttons for project-scoped settings (placed last, since they persist the settings above them).

*Workflow sub-tab* — per-project authoring checklist, sourced from a user-editable `.txt` template.
- **Template combo** — select a `.txt` file from `resources/workflow/` (ships with one starter template, `Default.txt`, based on a typical full-band song's steps). Empty folder shows a disabled hint instead of a combo. Any selection change (manual pick, or the startup fallback when no persisted selection matches) goes through `SelectWorkflowFile` — see below.
- Template markup: `[Section Name]` lines are non-checkable headers (rendered via `SectionHeader`); plain lines are checkable items; a trailing `{tooltip text}` on an item line (or a `{...}` line of its own, which attaches to the previous item) becomes that item's hover tooltip. An item that picks up more than one tooltip source (same-line + a following own-line block, or two same-line groups) drops the tooltip entirely rather than guessing which wins.
- Checking an item stamps `os.time()` and immediately autosaves (its own `workflow_v1` project ExtState key, independent of this tab's own Save/Load buttons); unchecking clears the timestamp. A **Show completion timestamp** checkbox (off by default, persisted) controls whether "Completed on dd.MM.yyyy at hh:mm" is displayed under a checked item — the timestamp is always recorded regardless of the checkbox; only its display is optional.
- A **Show only unfinished** checkbox (off by default, persisted) hides checked items during render via a lazy-header-flush loop in `DrawGeneralWorkflowTab`: a header is buffered in `pending_header` and only actually drawn right before the next item that passes the "not (hide_done and checked)" test, so a section whose every item is hidden never gets flushed — no separate per-section pass needed. Reduces to the unfiltered render when the checkbox is off, since every item then passes the test.
- A progress line (`ComputeWorkflowStats(entries, state)`, pure — no `r`/`ctx`/`S` dependency, takes the current file's `entries` and `S.workflow_state` directly) renders `"done / total completed - pct%"` below the checkboxes, always over the *whole* template regardless of the unfinished-only filter.
- **Template switching prunes, not caps.** `SelectWorkflowFile(idx)` (the one place `S.workflow_file_idx`/`S.workflow_file_name` actually change) calls `PruneToWorkflowEntries(S.workflow_files[idx].entries)` — drops any `S.workflow_state` entry not matching that *one* file's items — then `SaveWorkflowState()` immediately. Replaced an earlier design that only pruned once total checked items exceeded a 100-item cap, compared against every loaded template rather than just the selected one; this is simpler and matches the actual use case (bouncing between a couple of templates doesn't need long-lived cross-template history).
- Checked state is keyed by **(section, item label)**, not label alone — the same item text can appear under multiple different `[section]` headers (e.g. "Guitar" under both "Instruments Expert" and "Difficulty reductions" in the starter template) without sharing state.
- Parse-time validation (shown as warnings above the checklist, non-blocking): duplicate `(section, label)` pairs within one file, and unbalanced `[`/`]` or `{`/`}` bracket counts in the file.

*Other tools sub-tab* — buttons that open the suite's other entry points. Drawn by `DrawGeneralLinksTab` in **`lib/reaper_script_links.lua`**, not by a file in this module folder: the vocal helper's General tab has the identical sub-tab, so the registry and the launcher live in `lib/` to exist exactly once. See `CLAUDE.md` → "Shared lib".
- Two sections from `SCRIPT_LINK_GROUPS`: *Main tools* (General Helper, Vocal Helper, Music Theory Helper) and *Standalone windows* (Venue Preview, Pitch Tuner, MIDI Pattern). One `BtnGroupWidth` spans both sections so they read as a single column.
- The running script's own entry is filtered out by `FilterScriptLinkGroups` (whole-basename, case-insensitive match against `get_action_context()`), so this tab shows five buttons, never six. A group emptied by that filter is dropped rather than left as a header over nothing.
- `LaunchReaScript(path)` = `AddRemoveReaScript(true, 0, path, true)` → `Main_OnCommand`. Registration is idempotent (REAPER de-duplicates by path) and **permanent by design** — it is never removed, since that would delete the user's own registration and any key/toolbar binding with it, and a re-add returns a different command ID. `GetToggleCommandState(cmd) == 1` short-circuits a re-launch so REAPER's modal "ReaScript task control" dialog can't block the frame. Safe to call mid-frame: the launched script runs in its own Lua state and draws its first frame on the next defer tick.
- Missing targets are `BeginDisabled`+`EndDisabled` with the reason drawn *inline* — a disabled widget reports no hover, so its `Tooltip` is unreachable in that state. `file_exists` is re-checked on a 2 s throttle (not per frame, not frozen once — `deploy_to_reaper.bat` gets run with REAPER open).
- **`rock_band_music_theory_helper_vkr` is a link target only** — no reverse link back, because its `ui.lua` has no General tab to host this sub-tab. See `.claude/CLAUDE_music_theory.md`. The three standalone windows are link targets only too, having no tab bar at all by design.
- Tested by `dev/tests/script_links.lua` (pure; no project fixture) — the valuable case checks the registry against the entry points actually present at the install root, in both directions.

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
- Every chord shape consults `lib/reaper_guitar_theory.lua`'s chord-quality classifier
  (via `BuildShapeGemMap` in `actions_guitar.lua`), by PITCH CLASS rather than physical
  note count — a real-guitar interval like a power chord's perfect fifth always gets a
  matching lane spread (e.g. 1-3: GY/RB/YO) instead of whatever pitch-rank pool-cycling
  happens to land on, even when voiced with a doubled root across 3 strings (e.g.
  `5 7 7 x x x`, root+5th+octave) — that collapses to the same 2-gem combo a literal
  2-note power chord gets, not a 3-note chord. The preview report annotates recognized
  shapes with their chord name (e.g. `[Power chord]`, `[Major triad]`). When more
  distinct shapes share a width/size group than that group has combo alternatives, the
  first (lowest-pitched) shapes to reach the group each claim a unique combo; any
  further (higher-pitched) shape reuses whichever already-claimed combo minimizes
  conflicts against shapes it's actually adjacent to ANYWHERE in the passage — two
  chords that are genuinely back-to-back only end up looking identical when it's truly
  unavoidable (more distinct shapes than combos), never just because they're
  pitch-neighbors. Reused shapes get `(*Wrap)` appended to their reason string; the
  shape that legitimately claimed the combo first is never flagged. Past
  `MAX_CONFLICT_SHAPES` (200) distinct shapes in one group, skips the conflict search
  and falls back to plain clamp-to-last — real songs stay far below this; it only
  guards against a mis-selected source track (e.g. a drum track) producing a huge,
  near-random shape vocabulary that would otherwise make the search's worst-case
  O(N²) cost visibly freeze REAPER's single-threaded UI.
- Workflow: Preview (reasoning report only) or Auto-insert (writes gems, fully undoable).
- Validate Guitar: check existing gems on the target track against authoring rules.

**Difficulty tab** — difficulty validation, copy-to-next-tier, and automatic generation. Contains five sub-tabs: four per-instrument ones described first, then **Generate** (below the Drums sub-tab). Each sub-tab has the same two rows: **Copy to Hard / Medium / Easy** actually writes notes (see below), and **Validate Expert / Hard / Medium / Easy / All** checks the actual authored notes in that difficulty's own pitch range (read-only). All actions respect time selection.

**Copy to X** (`Copy*Diff(diff_label, force)` in each module) replaces the tab's former read-only "Suggest" preview — it copies notes from the *immediately higher* adjacent tier (Copy to Hard ← Expert, Copy to Medium ← Hard, Copy to Easy ← Medium — the same `ADJACENT_HIGHER` mapping the progression check below uses) onto the target tier's own track/range, giving the user a real starting point to hand-edit down. Two safeguards: if the source has no notes, it early-exits with a status/report message and writes nothing; if the target already has notes, it sets `S.diff_copy_pending = { message, on_confirm }` instead of writing, which opens a shared confirm-overwrite modal popup (`ConfirmCopyOverwrite`, rendered once at the end of `DrawDifficultyTab` regardless of which sub-tab triggered it — the first modal popup in this codebase) with "Clear and Copy" (re-calls the same function with `force = true`) / "Cancel" buttons. Copies gem/playable notes only — no force-HOPO/trill/roll/fill/disco-mix markers, since those either don't apply to the target tier or are shared fixed-pitch overlays not meant to be duplicated per difficulty. **Pro Keys is the one exception**: since its lane-shift markers (0–9) are essential for the track to make sense at all (not an optional overlay), it copies its entire note set — gems and markers alike — verbatim between tracks (no pitch transform needed either, since its range doesn't shift between tiers). Fully undoable.

**Guitar/Bass color compression**: Guitar/Bass *focus* Medium on Green–Blue and Easy on Green–Yellow (RBN convention; all 5 lanes exist at every tier, and official charts do use the upper colors sparingly — see the Guitar/Bass sub-tab). Keys has no such narrowing: official Keys charts use all five lanes on every tier, so its `K5_RANGE` ceiling is `lo+4` everywhere and compression is a no-op. `CompressChordOffsets` (`actions_difficulty_shared.lua`) handles a source chord that uses a color above the target's ceiling: a single note or 2-note chord is shifted down as a whole (preserving its interval) when every note stays ≥ offset 0 — e.g. Hard's Orange+Blue → Medium's Blue+Yellow; otherwise (3+ note chords, or a 2-note chord that would go negative) any note above the ceiling is simply dropped. Drums doesn't need this (every tier has the same 5 lanes, hi-lo=4 always, so the function is a no-op there) but calls it anyway for consistency with Keys/Guitar-Bass's copy functions.

Every Validate action (all four sub-tabs, H/M/E only — never Expert) also runs a shared cross-difficulty progression check (`CheckDifficultyProgression` in `actions_difficulty_shared.lua`) against the immediately higher adjacent tier: flags an unedited copy (identical event count, timing, and normalized pitch shape — i.e. no reduction was actually authored; this is the case right after a fresh "Copy to X" with no further edits, by design), and reports the two tiers' individual note counts, requiring the lower tier to have fewer notes (e.g. `"Expert has 500 notes and Hard has 450 notes: OK"` / `"...: NOT REDUCED"`). Both findings count toward the report's issue total and are prepended right after the header, before the rule-by-rule breakdown. Skipped gracefully when the higher tier's track/range has no notes (nothing to compare against).

*Pro Keys sub-tab* — validates PART REAL_KEYS_X/H/M/E (one track per difficulty).
- **Validate Expert / Hard / Medium / Easy / All** — check against RBN Pro Keys authoring rules: chord count/span, interval jumps, spacing (M/E), lane range markers.
- **Two rules are softer than the RBN doc, from the official RB3 DLC charts** (352 development songs). *Spacing* uses 5-lane Keys' split (`PK_MIN_SP` / `PK_ADV_SP`): an error under a 1/8 note on Medium and a 1/4 on Easy, an advisory under the doc's 1/4 and 1/2 — official Medium has 13.8% of its gaps under a quarter (22% under 100 BPM) and Easy 41.9% under a half, but only 0.8% / 3.0% under half of those. *Interval jumps* are an advisory category: official charts leave 72-89% of the jumps over the doc's limits as they are, and an octave move fixes most of the rest; small whole-shape shifts are under 1%.
- **Unchanged copy / NOT REDUCED are advisories on Pro Keys** (`PK_PROGRESSION`, passed to `CheckDifficultyProgression`): official Hard is sometimes Expert as it is when Expert is simple (3 of 352 RB3 DLC songs exactly, 13 at 95%+ of the notes), and the doc has no rule that Hard must differ.
- `CollectPKChecks(dl, events, lane_shifts, exp_events, sel_s)` returns the checks as categories of `DiffIssue` records (like `CollectK5Checks`), so Generate counts Pro Keys errors the same way; `ReadPKTierEvents(track, sel_s, sel_e)` reads one tier track as `(lane_shifts, events)`.
- Track indices auto-detected by name (PART REAL_KEYS_X/H/M/E).
- Only notes in the playable Pro Keys range (48–72, C2–C4) are read as chord/gem events; reserved marker pitches (overdrive 116, glissando 126, trill 127) and any other out-of-range note are excluded before chord/span/jump/spacing/overlap grouping, so they can never masquerade as huge chords/jumps (`GroupIntoEvents` in `actions_difficulty.lua`). There is no longer a standalone "note range" check — filtering happens before events are built, so nothing outside 48–72 ever reaches a check.

*Keys sub-tab* (formerly "5-Lane Keys") — validates PART KEYS (all four difficulties on one track in separate pitch ranges).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–76 | Easy: 60–64 — all five lanes on every tier.
- **Validate Expert / Hard / Medium / Easy / All** — check chord count, spacing (Medium: error under 1/8, advisory under 1/4; Easy: error under 1/4, advisory under 1/2), note length, sustain gaps (Medium/Easy: the shared `DiffReleaseGapQN` floor, see below).
- Track index auto-detected by name (PART KEYS).
- **Reduce using Pro Keys (same tier)** — checkbox above the Copy row, checked by default, persisted (`S.diff_5k_pk_reduce`). When `Copy to Hard/Medium/Easy` runs with this on, `CopyKeys5Diff` keeps only copied events that land on a note in the matching-tier Pro Keys track (`PART REAL_KEYS_H/M/E`, via `ReadProKeysEvents` + `FindNearbyPKEvent`, tolerance `PK_REDUCE_TOLERANCE_QN` = 1/32 note in quarter-note space — tightened from an initial 1/16 note, which left too many events kept at faster tempos) — mirrors a difficulty reduction already hand-charted on Pro Keys onto the Keys copy, instead of copying every event from the tier above unfiltered. Kept events also get their sustain length matched to the Pro Keys event's length (end minus start, re-anchored at the Keys event's own start via `TimeMap2_QNToTime`) rather than keeping the copied source tier's own length, so both charts agree on note length (not just onset) — Pro Keys is the master chart both are reduced from, and sustain-gap rules require the two to match. Dropped events are simply omitted before `CompressChordOffsets` runs on the survivors. If the matching Pro Keys track isn't selected, missing, or empty, Copy falls back to an unfiltered copy (source length kept as-is) and the status line explains why. Mirrors the user's usual charting order: Pro Keys first (hand-reduce Expert→Hard→Medium→Easy), then Keys, using Pro Keys' already-decided rhythm and note lengths as the reduction guide. Keys-only — Guitar/Bass, Drums, and Pro Keys itself don't have this option.

*Guitar/Bass sub-tab* — validates PART GUITAR or PART BASS (instrument radio switch; Guitar and Bass share one RBN rule set — the doc treats them as one spec with only cosmetic differences — so this sub-tab and `actions_difficulty_gtrbass.lua` are shared between both, parameterized by `instrument` ∈ `'gtr'`/`'bass'`).
- Lanes 96–100 / 84–88 / 72–76 / 60–64 on every tier. `GB_RANGE.hi` is the *focus* ceiling (Medium 75 = up to Blue, Easy 62 = up to Yellow) that Copy compresses to, not a limit.
- **Validate Expert / Hard / Medium / Easy / All** — chord count; chord shape (illegal 3-note Green+Orange on Expert, per-difficulty max span — no Green+Orange on Hard, no Green+Blue on Medium, no chords on Easy; a 2-note Green+Orange chord on Expert is an advisory, not a hard failure); note length (min 1/64, reuses `SustainThresholds` from `actions_guitar_validate.lua`); overlap; sustain gaps (1/32 min on Expert/Hard; Medium/Easy use the shared `DiffReleaseGapQN` floor, see below); an advisory-only note-density grid (quarter-note target on Medium, half-note on Easy — qualitative in the source doc, not chart-breaking); an advisory when a color above the focus ceiling exceeds `GB_UPPER_SHARE_MAX` (5%) of a Medium/Easy tier's notes — single uses are normal and never flagged; an advisory for force-HOPO markers (notes F/F#, offset `lo+5`/`lo+6`) on Medium/Easy; and trill/tremolo marker velocity (pitches 126/127, fixed regardless of difficulty — velocity ≤40 is flagged only when validating Hard, since that's the only tier the doc gives a numeric threshold for: 41–50 required for Hard eligibility, else Magma reports a spacing error).
- Track fields (`diff_gtr_idx`/`diff_bass_idx`) auto-detected by name (PART GUITAR/PART BASS) — independent of the Guitar tab's own conversion target-track field.

**Keys and Guitar/Bass Medium/Easy thresholds are measured, not copied from the docs.** `dev/calibration/run_difficulty_probe_vkr.lua` runs these validators over every official RB3 DLC chart outside its hold-out, and a rule that fires on a large share of Harmonix's own charts is too strict. Four were, and were loosened to fit: the Medium/Easy colour limits (official Guitar/Bass use the upper colors sparingly; Keys use all five lanes on every tier); the Medium/Easy sustain gap (`DiffReleaseGapQN` in `actions_difficulty_shared.lua`: 1/8 note, 1/16 on Medium at ≤100 BPM — Harmonix follows the docs' "pull every sustain back an 8th", not their "try to leave a quarter note"); Keys Medium spacing (1/8 floor, 1/4 advisory); and force-HOPO markers on Medium/Easy (advisory). The rationale and the measured shares sit beside each constant. Re-run the probe before tightening any of them, and keep the docs' wording as the target a reducer *aims* for rather than the floor Validate enforces.

*Drums sub-tab* — validates PART DRUMS (single track, four pitch ranges, same shape as Keys).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–76 | Easy: 60–64. Gem order matches `actions_drums.lua`'s `LANE_NAMES`: offset 0=Kick, 1=Red(snare), 2=Yellow, 3=Blue, 4=Green.
- **Validate Expert / Hard / Medium / Easy / All** — base rules: max 2 simultaneous notes on Medium (cascades to Easy — replaces an earlier, narrower "kick+snare+cymbal 3-limb" reading of the RBN doc with the more concrete external-source rule); no gems paired with kick at all on Easy; roll/trill marker velocity (pitches 126/127 — ≤40 flagged only when validating Hard).
- Layered external-source rules (Hard/Medium/Easy), each a real Check function unless noted as a hint. Cascade direction: a higher tier's rule applies to an easier one too unless that tier defines its own override.
  - **Cascades H→M→E** (no tier-specific override below Hard): no kick starts inside a drum-fill marker (pitch 120–124, fixed like the trill markers); roll/trill markers start on an 8th/quarter-note grid line; a roll covers an even number of gem hits; roll/fill density (Hard: no 16th-rate rolls ≥140 BPM; Medium: never faster than 8th-rate at any tempo — its own blanket rule; Easy: quarter-rate required ≥120 BPM, else inherits Medium's 8th-rate cap below that); general timekeeping density — runs of ≥4 consecutive 8th-note-paced hits (Hard: flagged ≥170 BPM; Medium: ≥140 BPM, its own stricter rule; Easy: inherits Medium's 140 BPM, no own general override); a Green+Yellow/Green+Blue double crash needs a quarter-note gap before it or should reduce to a single Green.
  - **Cascades M→E**: kicks on quarter-grid only above 100 BPM; max 1 kick per measure at ≥170 BPM.
  - **Medium-only** (Easy's existing kick-pairing rule already makes these redundant there): a kick+Green(crash) chord is fine on-beat but not off-beat/syncopated. (A second Medium-only rule, a kick or snare falling between two Yellow/Blue hits, is implemented as `CheckDrumsYellowBlueInterleave` but currently **disabled** — not wired into `RunDrumsChecks` — since the rule as coded doesn't match the intended behavior; the function is left in place pending a clearer definition.)
  - **Hard-only** (tier-specific by nature, not cascaded): Hard should have fewer kicks than Expert; the Hard-tier (`diff_idx==2`) `[mix N drums<config>]` event should use the un-flipped/base config, not the disco (`d`) variant.
- **Authoring hints** — a fixed, non-pass/fail block (`DrumsAuthoringHints`) for rules too qualitative to check deterministically ("try removing kicks from adjacent notes", "remove about half the snare accents", "trim a note or two from a fast roll's start", "reduce hand motion" on Hard; "reduce triplets to quarter notes" on Medium; "favor crash over kick" on Easy). Always shown on H/M/E; never counted as an issue.
- Pro Drums tom markers (110–112) are never read by these checks (they fall outside every difficulty's 5-note pitch window) rather than validated against an unstated per-difficulty rule.
- Every Validate report ends with an informational (non-pass/fail) scan of `[mix N drums<config>]` disco-flip text events, listing which difficulty tiers have one authored — correctness of the flip depends on the surrounding beat pattern, which can't be judged from note data alone (the Hard-only un-flip check above is the one exception that *is* checkable).
- Track field (`diff_drums_idx`) auto-detected by name (PART DRUMS) — independent of the Drums tab's own conversion target-track field.

*Generate sub-tab* — builds Hard, Medium and Easy automatically, each from the tier above it. Guitar, Bass, Pro Keys and Keys today; Drums joins by adding an entry to `GEN_INSTRUMENTS` (`actions_difficulty_generate.lua`) plus a planner. `GEN_INSTRUMENTS` order is also the run order of All instruments, which is why Pro Keys comes before Keys.
- **Pro Keys** (`GenPKPlanTier`, `difficulty_generate_prokeys.lua`): a track per tier (`tier_fields`, the Pro Keys sub-tab's `diff_pk_*_idx`; the sub-tab shows four track rows). Planner events carry real pitches in `offs` (the action reads Pro Keys with a range low of 0). Rhythm is `Gen5SelectOnsets`, the same as every instrument, including the Hard fast-run rewrite and following Guitar - official Pro Keys and Keys onsets agree 89-96% per tier. Measured on the official RB3 DLC Pro Keys (352 dev songs): chords lose notes from the bottom (the top note stays 70-80%); Hard keeps Expert's pitches (78% identical, 18% a subset) and lane shifts (87%), dropping a shift whose notes fit the window already showing; Medium/Easy show one window for the song: Medium keeps Hard's when Hard shows one window all song, preferred or not (`GenPKUpperWindow`; official Medium keeps it in 126 of 136 such songs - the doc prefers C/F/A but accepts another range that fits better), Easy keeps Medium's (the doc), otherwise the best fit (`GenPKBestWindow`: the most notes, then C/F/A, E, D, G). Notes outside fold by the smallest octave move, a whole chord when it fits; notes inside never move, so the same upper note always lands on the same key (choosing the octave nearest the previous note left one D3 an octave above every other D in pojat_lemmikkih's Medium). Easy matches the official window in 96% of songs, Medium in 63%; exact pitches Hard/Medium/Easy 80/74/83%. Sustains leave the RBN gaps (Hard 1/16 simple / 1/8 otherwise, Medium/Easy a quarter); one cut under 3/16 becomes a 1/16 note. Interval jumps are not fixed (see the Pro Keys sub-tab). When Expert has no lane shift, Hard gets a best-fit one before its first note. Writes replace the lane-shift pitches and 48-72 (`ReplaceNotesBulk` takes a list of ranges). In a time selection, a tier with no notes outside it is generated as new - its markers are cleared over the whole item (a template's default C2-E3 marker, inside the selection, had been read as the tier's window) - and a tier with notes elsewhere keeps its first marker's window. Expert's lane shifts are always read from the whole track. Zero-length notes are *used* on Pro Keys: Expert's track is never written, so REAPER does not drop them and Validate still counts them.
- **Time selection = the notes that start in it** (start inclusive, end exclusive), for every instrument: Generate reads to 2 ms before the selection end (`read_e`; the tier readers keep notes up to 1 ms past it, as Validate wants) and `ReplaceNotesBulk` clears by onset. Before, a note on the end downbeat was read and regenerated but not cleared, a duplicate; and a sustain from before the selection was cleared but never regenerated. The `batched` / `per_note` timing modes still clear by overlap (`ClearNotesInRange`).
- **Pro Keys Hard equal to Expert asks a question first.** When the run starts at Hard, Generate plans Pro Keys Hard in memory and, if it equals Expert exactly (`GenPKSameAsUpper`: onsets, pitches, lengths), asks before writing anything (Shorten sustains / Keep as Expert / Cancel), so Medium and Easy are built from the chosen Hard and the run stays one undo step. The answer comes back as `GenerateDifficulties(..., answers)` (`answers.pk_pull_back`), and the result says what was asked, chosen and done. *Shorten* is the planner's `opts.pull_back` (`PullBackSustains`): every sustain 1/16 shorter before a simple transition or at a phrase end, 1/8 otherwise - the commonest official pull-backs - and a tail left under 3/16 becomes a 1/16 note. Official charters do this per song, nearly all or nothing (41 of 275 songs pull back 75%+ of Hard's sustains, 185 under 5%); it is not the doc's jump rule (1% of official shortenings precede a jump over 11). The shared confirm popup (`ui_difficulty.lua`) takes an optional second answer (`alt_label` / `on_alt`) and clears the pending entry before running a callback, so a callback can ask the next question.
- **A keys lick that starts on an "and"** (`Gen5AndPhrases`, `GEN5_PARAMS.and_phrase`; Keys and Pro Keys only). A phrase - upper-tier onsets with no gap of a half note, 8 or more - that enters on an "and" and whose "and" line changes note more often than its beat line (changes per step, margin 0.2) is reduced on Medium on the "and" grid: its onsets weigh as if half a beat earlier (`ShiftedClass`), in `Weights` and `FillBeats`, and a bar touching it does not follow Guitar's Medium. Easy, given Hard as `opts.and_source`, takes Hard's beat notes inside those phrases instead of Medium's - back to the downbeats; guided Keys Easy gets Keys' own Hard notes as extra candidates so it can follow Pro Keys there. From the user's korpiklaani_juo_viinaa hand chart (lick on the and of 4: beats B B C C, "and"s B G C A; Pro Keys Medium matched 238 of 247 hand onsets, 116 before). A PRODUCT RULE: official Medium goes "and"-led in 30% of Keys/Pro Keys phrases that enter on an "and" (7% for beat entries) and note variety barely predicts which; F1 cost under 0.2 points. The action passes Hard (this run's, or read from the track) to Easy; the evaluator, golden suite and dry run do the same.
- **Keys follows the Pro Keys of the same run.** In All instruments, Keys' guide is the Pro Keys output just planned (`ProKeysGuide(..., generated)`), not the track. Keys alone still reads the Pro Keys track, and with no Pro Keys it is planned on its own. `SelectByGuide` matches one Keys onset per Pro Keys onset, the closest: a 32nd grace note before a beat sat inside the 1/32 match window too and kept both.
- **Instrument dropdown** (`S.diff_gen_instrument`, session-only): one instrument, or "All instruments". The track combo binds to the instrument's existing field (`diff_gtr_idx` / `diff_bass_idx` / `diff_5k_idx`), so it is the same selection the instrument's own sub-tab shows. "All instruments" ignores the combos, finds each default track by exact name (`FindTrackExact`), and skips one that is missing, muted (`B_MUTE`) or has an empty source tier.
- **Buttons:** Hard / Medium / Easy (from the tier above *as it is now* — rebuilds the lower tiers after hand-editing one) and Hard > Medium > Easy, where each step reads the tier the previous step just generated (in memory, not re-read from the track). One overwrite popup lists every tier that would be replaced (`S.diff_copy_pending` with `confirm_label`); the whole run is one undo block; time selection limits scope.
- **One rhythm model for every instrument (a product rule).** Which onsets a tier keeps depends only on onset positions, note lengths and tempo — never on colors, chords or instrument — and every instrument uses the same `GEN5_PARAMS`. Guitar, Bass and Keys playing the same Expert rhythm therefore get the same Hard/Medium/Easy rhythm with no coordination between tracks; chords and colors are reduced afterwards and never change which onsets survive. Official Keys reduces less than Guitar/Bass, so this costs some Keys F1 (Easy most, about 2.7 points), accepted deliberately. Do not reintroduce a color- or chord-dependent weight or a per-instrument gap: `dev/tests/general_algorithms.lua` checks that the same rhythm given as guitar, bass and keys produces identical onsets.
- **Planner** (`Gen5PlanTier`, pure): weighted interval scheduling keeps the highest-weight onsets at least a per-tier gap apart (`min(max(grid, sec × bpm / 60), cap)`, grid/sec tuned on Guitar/Bass); weights favor downbeat > beat > 8th > 16th, plus sustains. The **cap** is the tier's note value (Hard 1/8, Medium 1/4, Easy 1/2): without it the time term crossed the next note value on fast songs and a whole rhythm level vanished (at 210 BPM Hard lost every off-beat 8th, Easy went to whole notes — official charts do neither). Past the cap, fast passages are thinned by bar position. **Fast runs one grid slower** (`Gen5RetimeDenseRuns`, `difficulty_generate_retime.lua`, Hard only, not when Keys follows Pro Keys): above `fast_8ths_bpm`, onsets closer than the Hard gap are not thinned in place (a 210 BPM solo kept 5 of 14 notes and lost its motion) but rewritten one step slower on the ladder 32T → 32nd → 16T → 16th → 8T → 8th, so 16ths become 8th triplets (16 → 12) and 8th triplets become 8ths (12 → 8). Alternating straight and triplet keeps each step near 3/4–2/3 of the notes; a same-kind step would halve them. Straight → triplet is deliberate, also for straight 16th riffs: the user preferred the speed it keeps. A bar's grid is its spacings snapped to the ladder, the fastest step that occurs at least twice (one stray tick must not turn a bar of 16ths into 16th triplets). Each half bar is a segment anchored on its beat. Slots stay a grid step from notes that are not dense (those stay put), and a run that *lands* on a beat and then rests keeps that beat as its last slot. A **16th rest inside a run of 16ths whose next note is on the 8th grid is kept**: the run restarts at that note and counts its grid from there (`GR . G G G G G G` → 0, 12, 20, 28, 36 — the pause defines a riff). A rest before a 16th-position note is filled, as the hand-reduced solo did (bars 154–157, 161). A pair after a long gap is not a restart (bar 162 still shifts toward beat 3). Every slot stays a grid step before the next half bar. **A short flourish is thinned, not rewritten**: a run of at most 3 dense notes that starts on a beat and ends off it (bass `G G R | R R`, 16ths into 8ths) loses its in-between 16th to the normal gap, and its notes carry `flourish` so the busy-bar rule still treats the bar as whole and applies Drop 2 (`G R R . | G R R .`). As triplets, its last note had run on into the following 8ths at the same spacing. Runs that end *on* a beat stay rewritten (bar 21's join rule). A note of a run in a bar the rewrite did **not** change (e.g. the downbeat a run of 16ths lands on) loses `retimed` and gets `joined`. Otherwise it kept the busy-bar rule off a following bar of straight 8ths (chronosp bass bar 85, guitar 43/108). `joined` still counts as rewritten for the force-HOPO restore. **Sustain lengths through the chain:** events carry `qn_e_full`, the length before any tier shortened it. When a tier inherits a tail the tier above shortened for a note this tier drops, and the tail is under this tier's minimum, `FixLengths` stretches it back to exactly the minimum, no further (pojat guitar Easy bars 70/74). Restoring the full length instead made Easy sustains longer than the verified ones. **A group that runs straight into the next half bar's beat** (its last note closer than the Hard gap to a note on beat 3 or the next downbeat) and does not start on its own beat is laid out **backward from that beat**. A group cut to one note then keeps the note that hammers into the beat (`36 G 42 G | 48 Y` → `40 G | 48 Y`), not a note an 8th away (chronosp bars 21/23 by hand). A restarted group never starts earlier than its restart note. Bars 20/22/24's first half follows the same rule (`16 24 32 40 | 48`). A DP then maps the notes onto the slots: as many as fit, in order, least movement, +20 (1/24 QN units, `retime_color_penalty`) per skip that creates a color move the source never makes, ties dropping the tail. Positions depend only on the rhythm, so all parts with the same Expert rhythm match. The rule was fitted to a hand reduction of the chronosp_brutal_decay solo and reproduces it (170/170 positions, 165/170 colors). Check it with `dev/tools/generate_compare_hand_offline.lua <song.mid> <hand.mid> [part] [bars]`. Retimed events carry `retimed = true`: the gap does not apply next to them, the cap and busy-bar rules never remove them, and `log.retimed_bars` drives the result's "review by hand" list. The keep cap is a share of the **original** upper count. **Medium** (round 8, from the user's chronosp review; every number measured on official RB3 DLC Guitar/Bass, dev songs). (1) *Shortest sustain per tier* (`min_sustain`): Medium 0.75 QN at ≤ 160 BPM / 1.0 above, Easy 1.0, Hard 0.5. Official fast Medium never has a sustain under 0.875 QN. `FixLengths` cuts anything shorter to a plain note. (2) The *sustain bonus* counts on Medium/Easy only if the note can stay a sustain there (held to the next upper onset less the release gap). (3) *Chord bonus* (`chord_bonus.M = 2.5`), only for a chord with a single note within the gap. Official Medium keeps an 8th-later chord over a beat single 83% of the time but a downbeat single over the chord before it 59%; 3 + 2.5 sits between beat 5 and downbeat 8. On an all-chord passage a per-note bonus only rewarded density. (4) `FillBeats`: a bar whose upper tier has more onsets than beats keeps a note per beat. It adds back removed onsets at least an 8th from kept ones, never between two kept ones closer than a quarter, beats first, then weight, then a held note, then `CAP_KEEP_RATE`. This is the user's choice: official fast Medium keeps both of a beat + 8th-later pair only 5% of the time, so it costs Bass Medium about 1 F1 point. (5) `SnapRewrittenToBeats`: the retime pass marks the rewritten note nearest (within a 16th) to an Expert beat it left empty (`beat_qn`), and Medium/Easy move it back. (6) Colors `color_shift = 'clamp'` (`Gen5ClampOrShiftBars`): only notes/chords above the top lane move (chords whole), unless that creates a same-color repeat with a neighbour in the same bar at most a quarter away which the tier above does not have; then the bar moves down whole. This reproduced every color of the verified pojat golden chart and fixed chronosp bar 10, and it agrees with official colors best (Guitar/Bass Medium 60.8/69.8% vs 58.8/67.4% for the old passage split). (7) Bass/Keys follow Guitar's Medium in bars of the same Hard rhythm (`log.rhythm_bars` → `opts.rhythm_ref`; `GuitarRefs` in the action plans Guitar's chain in memory). **Force-HOPO on Hard** (`difficulty_generate_hopo.lua`, Guitar/Bass): the action marks each Expert note's hammer-on (`ev.hopo` = `'forced'` under an Expert lo+5 marker, `'auto'` when it hammers on by itself and no lo+6 marker forces it off), the planner carries it (with `rewritten` = moved by the retime pass; deliberately not `retimed`, which would lift the next tier's gap), and Hard gets lo+5 markers where it would not hammer on by itself but can. Two cases, each measured on the RB3 DLC charts. **Expert-forced** notes are copied wherever they survive: official Hard keeps 77% of them. **Lost auto hammer-ons** are restored **only on rewritten notes** (8th triplets → 8ths), at most an 8th apart and in runs of 2+, because official Hard turns a lost hammer-on into a strum almost always (4% forced of 14,693) and the RBN doc asks for markers "sparingly". Auto-HOPO = a single note whose color is not in the previous note/chord, within the threshold. The threshold is Magma's per-song setting in ticks at 480 PPQ: 170 by default, or 90/130/250, each just above a note length (16T/16th/8T/8th). REAPER cannot read it, so 170 is assumed; only 9 of 613 official songs set it, all stricter. Spans run from a passage's first onset to its last note's end (the doc: same duration as the note). Generating Hard replaces its lo+5 markers; lo+6 is left alone. Expected cost: official Hard never retimes, so onset F1 against it dropped about 1 point on Guitar Hard. **Busy bars first:** a Hard bar of 6+ onsets the gap left complete loses `busy_drop` notes (1 or 2, per the Generate sub-tab's "Hard 8th runs" choice; Auto = 2 when the first note is over 160 BPM, from the RBN Guitar/Bass and Keys docs: "If the song is fast (over 160 bpm) … remove every fourth note per half measure") **less the 8th slots the bar already leaves empty** — at least one when one or no slot is empty, **none when two or more are** (a bar with rests is already easier; taking two from it gave Hard a hole-ridden line). Bar length comes from `bar_len`, 4 QN without it. Official Hard keeps 7 or 6 of 8 straight 8ths about equally often at every tempo, hence the user override. Removal order: the doc positions (the and of 2, the and of 4) first, least-kept first so Drop 1 still takes the and of 4; then the other off-beats by `CAP_KEEP_RATE`; **protected notes last** — a sustain always, a chord only in a bar that mixes chords and single notes (the accent); in an all-chord or all-single bar they are all alike. **Guitar leads:** Hard records each busy bar it thinned (`log.busy_bars`: onset positions and the positions removed). Bass and Keys get it as `opts.busy_ref`; a bar whose Expert onset positions equal Guitar's loses Guitar's notes, unless one of them is protected on that instrument (its own sustain or accent wins and the bar uses its own order). A different rhythm always uses its own order. The action computes the reference in memory from PART GUITAR's Expert (`GuitarBusyRef`, nothing written) whether or not Guitar is in the run; the golden suite and the offline evaluator do the same. Protection breaks the strict one-rhythm rule (chord size and length now matter in busy bars), which is why the leader exists. It runs before the song-wide cap so the cap cannot take a whole position first and leave the bar rule nothing to do. A Hard keep cap (`max_keep`, 95%) guarantees Hard differs from Expert even on sparse charts. It removes **whole bar positions** across the entire song, least-kept by official Hard first (`CAP_KEEP_RATE`, pooled over all three instruments: "the and of 4" goes first), so a riff reduces the same way every time it comes round. Removing in song order instead thinned only the opening bars of a steady-8ths chart. The song-wide cap misses a busy passage when the rest of the song already thinned enough, which is what the busy-bar rule above (`ThinBusyBars`) catches. **Sparse charts:** an onset is *isolated* when both gaps to its upper-tier neighbours exceed a quarter note (`isolated_qn`). Hard's cap and busy-bar rule never remove an isolated onset (a beginner Keys part lost its few dotted-quarter notes to the song-wide cap; official Hard keeps a median 92% of Expert on the easiest Keys songs). Medium keeps them too, as official Medium does 99% of the time (removing an unconditional drop raised Medium F1 on every instrument, round 9). The exception is a **fallback**: a Medium that would keep more than 95% of Hard (`offbeat_fallback_keep`) drops its isolated off-beats first. If it still keeps over 95%, it is eased by color like Hard (`color_fallback_keep.M`, top lane Yellow). This is a product choice: official Medium on such simple parts keeps every isolated off-beat (560 of 560 in 58 parts) and changes colors and chord sizes instead. The user prefers removing a note to recoloring a line (pojat Keys). Cost: Keys Medium color agreement 81.2 → 78.6%. When Hard still keeps more than 95% of Expert (`color_fallback_keep`), it is eased by color: each **bar** moves down as a whole until its top note is Blue (`ShiftBars`; `O B Y` → `B Y R`), and Medium/Easy inherit it. Bar-aligned on purpose — `ShiftSegments` splits passages on rests, which shifts sparse notes one by one. Easy is never given a note Medium dropped (deferred idea, recorded locally). Planner events carry `bar_qn` and `bar_len` (from `TimeMap_QNToMeasures`), and output events pass them on to the next tier of a chain. Then chords reduce to size/span (Easy keeps the lowest note), Guitar/Bass Medium/Easy bring notes under the focus lanes (`color_shift`, see Medium below), and sustains are shortened to leave the tier's release gap: Hard 1/8, Medium a dotted 8th (a quarter above 160 BPM), Easy a quarter (a half above 160 BPM), never below `DiffReleaseGapQN`. A sustain that cannot keep that gap and stay 1/8 long becomes a 1/32 note, so it clearly reads as a plain note. **Thresholds and float noise:** notes are read in seconds and converted through the tempo map, which leaves tiny errors; identical repeats of a riff once landed either side of the 1/8 boundary (sustain kept in one bar, cut in the next). `ToPlannerEvents` therefore snaps every position and length to 1/960 QN, and every planner threshold compares with `EPS` tolerance — keep both when adding a threshold. Keys follow the same-tier Pro Keys track automatically when it has notes — the Pro Keys sub-tab's selection (`diff_pk_*_idx`, auto-detected at startup), never a name search across the project; only "All instruments" finds `PART REAL_KEYS_*` by name, as it does every track. The output is re-checked with `CollectGBChecks` / `CollectK5Checks` and any remaining error is listed. **Writes are bulk:** each tier (with Hard's force-HOPO markers) is written by `ReplaceNotesBulk`: one `MIDI_GetAllEvts`, the tier's old note on/off pairs dropped and the new ones added in Lua (other events untouched, in order), one `MIDI_SetAllEvts`, one `MIDI_Sort`. Per-note `MIDI_InsertNote` re-sorted the take after every note (about 10 s for chronosp Guitar+Bass H-M-E). Even with sorting disabled, `ClearNotesInRange`'s one-at-a-time deletes took 3.4 of 3.6 s. `WRITE_MODE` keeps `'batched'` / `'per_note'` only for timing comparisons. **Without a time selection a tier is replaced in the whole take**, not from 0 to the item's end: an imported item ends at its last note, and a zero-length chord there sits exactly ON that end, outside [0, end) - it was never cleared, and the new chord doubled every pitch (`rb_pro_keys.mid` bar 11 in REAPER: `[E2+E2+G2+G2+B2+B2]`). A Pro Keys tier generated as new in a time selection is replaced whole too. `ReplaceNotesBulk` also pairs a zero-length note's note-off (stored first, at the note-on's tick) with its note-on, and drops a note-on left unclosed in the window, so nothing stale can pair with a new note-off. The dry-run stand-in ends each item at its last event and keeps an unclosed note-on as a zero-length note, as REAPER does - it reproduced the failure. The result's last line is `Done in x.x s`. A run over `SLOW_RUN_S` (2 s) also lists each phase (read, guitar reference, plan, write, validate, undo); check that first if Generate gets slow again. To see the phases on a fast run, lower `SLOW_RUN_S`. The dry-run stand-in implements both buffer calls, and bulk and batched produced identical takes on the golden songs. **Zero-length notes:** writing a tier into the take makes REAPER drop every zero-length note in that take — Expert gems, untouched tiers, markers such as overdrive (Copy to Difficulty writes the same way). Generate ignores them as input, snapshots them before writing (`ZeroLengthNotes`), and lists in the result the ones REAPER removed outside the regenerated tiers, by position and name — once gone, Validate can no longer find them, so this report is the only trace. The test fixtures `rb_guitar.mid` / `rb_bass.mid` carry a zero-length overdrive marker and `rb_keys.mid` a zero-length Expert chord at bar 11.
- **The aim is official-like, not merely Validate-clean.** Validate's errors barely thin Guitar/Bass Medium/Easy (their spacing rules are advisories), so the gap and weight parameters in `GEN5_PARAMS` are *tuned* — best onset F1 against the official lower tiers over the development songs, with `dev/calibration/run_generate_eval_offline.lua tune` (see the calibration README). Change one only by re-running that sweep. The probe's hold-out (`dev/calibration/difficulty_holdout.lua`) is never used for tuning.
- **Checking a planner change offline**, before the REAPER suites: `lua dev/tests/run_generate_golden.lua` (hand-verified songs regenerate identically), `lua dev/calibration/run_generate_eval_offline.lua` (agreement with official charts, 0 violations), and `lua dev/tools/generate_action_dryrun_offline.lua [song.mid part from_qn to_qn]` (the real action against a REAPER stand-in, Validate's own checks on the output).

**MIDI tab** — MIDI alignment, length sync, note-length adjustment, and pattern replace. Contains three sub-tabs:

*Alignment sub-tab* — align an imported MIDI item to the project grid.
- Source track selector.
- Move only: shifts the item so the first note lands at the time selection start.
- Move + Stretch: also adjusts the take playback rate so the last note lands at the time selection end.
- Set a time selection first, then click **Align MIDI**. Fully undoable.

*Length sub-tab* — two sections, **Midi note** (above) and **Midi track** (below, the sub-tab's original content).
- **Midi note** — bulk note-length/sustain-gap adjustment on one track's difficulty tier. Source track selector (warns when that track isn't the one open in the MIDI editor — shared `MidiEditorTrackWarning`, `ui_midi.lua`, also used by the Pattern sub-tab) + Difficulty selector (Expert/Hard/Medium/Easy — no "All": sustain rules differ per tier so there's no real use case for adjusting all four at once) + Note type radio:
  - A **sustain is any note >= 1/8 note** (`SUSTAIN_MIN_DENOM`, `actions_midi_length.lua`) — the single threshold both modes split on.
  - **Non-sustains** — a Note size combo (1/16, 1/32 default, 1/64, 1/128 — no 1/8: that's the sustain threshold itself); **Adjust notes** sets every note SHORTER than 1/8 note in the selected track/difficulty range to that standard length (start position never moves). Existing sustains are left completely untouched.
  - **Only sustains** — a "32nd note amount" slider (0-32), prefilled with the tier's standard gap whenever Difficulty changes (Expert 3, Hard 4, Medium 8, Easy 16 — `SustainGapDefaultForDiff`; a manual tweak afterwards sticks until the tier changes again). **Adjust notes** finds every sustain and widens or narrows it so the gap to the next note in range is exactly that many 32nd notes. Honoring the requested gap would shrink the sustain below a 1/32-note floor: it's clamped to that floor instead (becomes a non-sustain) rather than skipped.
  - "Next note" is the **earliest** note starting after the sustain's own start tick — notes sharing that tick are chord-mates, not "next". A note starting *inside* the sustain (an existing overlap) counts and always wins, however far the next clean note is; measuring only from the sustain's tail (the pre-v0.9.41 rule) stepped over such a note and sized the sustain against a later one, leaving it overlapped. Only a next note at or past the sustain's end is subject to the search window — more than `SEARCH_WINDOW_32NDS` (16x32nd notes = half a measure in 4/4) past the end and the sustain is left unchanged (skipped).
  - All math works in raw take-PPQ ticks (via `GetTakePPQPerQN`, never seconds or QN floats) so results land exactly on REAPER's own note-length grid. Reuses `GetPatternPitchRange` (below) for the difficulty pitch range, so notes outside the tier (e.g. overdrive) are never touched. Respects time selection (falls back to the whole MIDI item). Fully undoable.
  - A chord (multiple notes sharing one start tick, e.g. a Green+Red+Blue chord) still gets every pitch individually adjusted, but is counted once toward the report/status (`counted_starts` in both `AdjustNonSustainLengths` and `AdjustSustainGaps`, `actions_midi_length.lua`), so the numbers read as "N notes"/"N sustains", not "N pitches".
- **Midi track** — resize every MIDI item on every track to match a reference track's length. Reference track selector, **Resize all MIDI** button.

*Pattern sub-tab* — find, replace, and navigate a note pattern across a MIDI track. Also available as its own window (`rock_band_midi_pattern_vkr.lua`, see "Third entry point" below); the body is `DrawMIDIPatternTab` in `ui_midi_pattern.lua`, drawn by both.
- Source track selector; **Set Search** / **Set Replace** capture the currently-selected notes in the active MIDI editor as the search/replace patterns.
- **Replace All** applies the replace pattern wherever the search pattern is found; **Fill Range** repeats the replace pattern across the time selection.
- **Go Prev** / **Go Next** move the edit cursor to the nearest Search-pattern match before/after the current cursor position; **List Search** reports every match with its measure/time location (read-only, populates the shared result panel). All three share the same match-scanning walk as Replace All (`ScanPatternMatches`) and respect time selection the same way (falls back to the whole MIDI item).

**Venue tab** — VENUE and EVENTS MIDI track events. Contains six sub-tabs (plus Preview):

*Actions sub-tab* — inspection tools, plus a couple of generation actions.
- **List venue events** — validates the VENUE track against the Rock Band Network spec: track name event, event type checks, unknown events, consecutive camera repeats, directed cut spacing, camera gap statistics, event usage frequency. Read-only.
- **List event sections** — reads `[prc_*]` markers from the EVENTS track and lists detected song sections with time ranges. Letter-suffix variants, including letter-only forms with no number (`[prc_verse_a]`/`[prc_verse_b]`) and numbered forms (`[prc_verse_1a]`/`[prc_verse_1b]`), are merged into a single section entry. Read-only.
- **List lighting/postproc** — finds every `[lighting*]` and `*.pp]` (postproc) text event on the VENUE track and lists them in timeline order of appearance, each with its measure/timestamp. Read-only.
- **Validate lighting/blends** (`actions_venue_validate.lua`) — checks the VENUE track's lighting/postproc authoring against the two rules the generators write from, read back off the track. Read-only; never opens an undo block. Four checks, all reported with `FormatTime` positions and a per-finding "what to do about it":
  1. **Missing `[first]`** — every manual lighting event that *changes* the running preset needs a `[first]` on its own tick (the same 1/128-note `_spot_tol` Manual gen's `[first]` gate uses). A restatement (blend anchor) and an automatic preset are both correctly `[first]`-free and are never flagged — see "Keyframe placement rule" below.
  2. **Stray `[first]`** — every `[first]` not on such an event, sub-classified so the fix is unambiguous: `misaligned` (within one beat of a change that *is* missing one → "move it", cross-referenced to that change's own check-1 entry, so acting on check 1 can't leave a duplicate), `on_restatement`, `on_auto`, `duplicate` (second on one tick), `orphan`. The `misaligned` bucket only claims a change that is actually missing its `[first]` — otherwise "move it onto that event" would be wrong advice.
  3 & 4. **Missing blend anchors**, lighting and postproc independently — a preset change is anchored iff the event immediately before it restates the one before *that* (`IsBlendAnchor`). Only *missing* anchors are listed, each with the outgoing preset and where it started; the report says outright that a hard cut is valid, so the list reads as "where a fade would need an anchor", not "where the track is wrong". The first event of a kind is exempt (nothing to blend from).
- Scope: always reads the **whole** track — judging "is this a change?" and "is an anchor present?" needs the events before the selection — then reports only findings whose own position falls inside the time selection. The summary counts are always whole-track and say so. `ValidateVenueLightingBlends` is **pure** over three sorted `{ppq, msg}` arrays (the `ResolveBlendSource` / `NextSectionEvent` precedent), so every rule is testable without a project; `ValidateVenueLighting` is the thin REAPER wrapper that reads, scopes and formats.
- **Validate camera stacks** (`actions_venue_validate_camera.lua`) — replays the game's own shot pick (`PickPriorityCameraEvent`, see "Camera shot priority" in `.claude/CLAUDE_venue_theme_generation.md`) at every camera tick, once per lineup the project can produce, and reports where stacking went wrong. Read-only; never opens an undo block. Four checks:
  1. **Duplicates** — the same shot written twice on one tick. Deduped before anything else, so a copy is reported once here rather than a second time as a shot that never plays.
  2. **Near stacks** — two camera events within a 32nd note but not on the same tick. The game reads those as two cuts, so the second immediately replaces the first; almost always a botched stack.
  3. **Unreachable shots** — a stacked shot that wins under no lineup, either because it needs an instrument no lineup puts on stage (`fits_any = false`) or because a sibling outranks it everywhere it fits (`beaten_by`). Only reported for genuinely stacked ticks: a *lone* unplayable shot is check 4's business, so it isn't double-reported.
  4. **Uncovered spots** — a lineup with no valid camera shot, so the game substitutes: a generic full band shot, or (for a lone coop duo cut, matching the doc's "no other stacked flags" condition) a single shot of the remaining member. One finding **per spot**, carrying the blind lineups — per-lineup findings would triple a report that is already one entry per cut on a track authored without companions. The listing is capped at `UNCOVERED_LIST_MAX` (40) spots; the count is always complete. Like the blend-anchor check, the report says outright that letting the game fall back is valid.
- Lineups come from `BuildBandLineups(GetMutedInstruments())`: only two of bass/guitar/keys fit on stage, so a project charting all three has three lineups and every spot needs a shot for each; a project charting two or fewer has exactly one, and shots for the absent instrument can never play. Drums/vocals mute state carries into every lineup. The report names the lineups it used, so a one-lineup result doesn't read as the check having done nothing.
- Scope: same split as the lighting validator — `ValidateVenueCameraStacks` is **pure** over one sorted `{ppq, msg}` array plus the lineups; `ValidateVenueCamera` is the thin REAPER wrapper that reads the whole track, scopes findings to the time selection and formats.
- **Generate sing along** — derives VENUE sing-along notes (pitch 87 guitarist from HARM2, pitch 85 bassist from HARM3) from each harmony track's vocal phrase content: a phrase (bounded by a pitch-105 marker note) qualifies when it has at least one vocal-range note (36-84); qualifying phrases less than a measure apart are merged into one continuous note. Only the pitch of a source track that is present and unmuted is cleared/replaced — a muted or missing source is skipped, leaving its existing notes untouched. If both HARM2 and HARM3 are unavailable, nothing is generated. Always processes the whole song (no time-selection scoping). Fully undoable.
- **Sub VENUE tracks** (`actions_venue_subtracks.lua`) — splits VENUE's events across 6 category tracks for easier authoring once a song has a lot of keyframes, then merges them back. Classification is by `CategorizeVenueEvent`: `coop`/`directed` (camera), `lighting`, `keyframe` (`[first]`/`[next]`/`[previous]`), `postproc` (`*.pp]`), and `special` (bonusfx + anything unrecognized, catch-all). VENUE's own interpretive MIDI notes (e.g. the sing-cue notes at pitches 85-87) are not text events and don't fit this classification — they always travel with `special`, via `CopyVenueNotes` alongside `CopyVenueEvents`, since no other category ever carries notes.
  - **Copy all to subtracks** — creates (if missing) "VENUE normal camera"/"VENUE directed camera"/"VENUE lighting"/"VENUE keyevents"/"VENUE post proc"/"VENUE special", each with a MIDI item matching VENUE's own position/length, inserted directly after VENUE. Newly created tracks start **muted** (an editing-only split with no meaning to the exported song — muting keeps downstream export tooling from flagging them as unrelated/unused MIDI), inherit VENUE's custom MIDI note names (`GetTrackMIDINoteNameEx`/`SetTrackMIDINoteNameEx`, checked across chan -1 and 0-15 for every pitch 0-127), and a newly created item's take gets its `P_NAME` set to the track's own name — REAPER's MIDI-editor tab/take-list label comes from the take's `P_NAME`, not from any embedded MIDI meta-event, so without this every subtrack's take shows as a generic "MIDI take" once more than one MIDI editor tab is open. Re-syncs bounds and re-copies on every run, so it's safe to re-run after editing VENUE directly - none of the creation-only steps (mute, note names, take name) repeat on a later sync (a hand-renamed take is never stomped).
  - **Copy all to main track** — early-exits with a status message if none of the 6 subtracks exist yet (rather than silently clearing VENUE for nothing). Otherwise clears VENUE and replaces it with the combined contents of however many subtracks currently exist (including "VENUE special"'s notes, replacing VENUE's own). Prompts for confirmation first (`S.venue_subtrack_copy_pending`, mirrors the Difficulty tab's overwrite-confirm modal) since it overwrites the track authoring actually reads from.
  - **Subtrack dropdown + Copy to / Copy from** — scoped to one category. **Copy to** clears just that subtrack and copies the matching category from VENUE into it, auto-creating the subtrack if missing. **Copy from** clears only that category's events from VENUE (not everything) before copying the subtrack's contents in — does **not** auto-create the subtrack (no-op status message instead), asymmetric from Copy to on purpose. For Special, both directions also clear+copy VENUE's MIDI notes to/from "VENUE special". Neither prompts for confirmation, matching `RemoveVenueEventsByType`'s existing precedent for category-scoped edits.
  - All 5 actions always process the whole VENUE item — not time-selection scoped, since subtracks always mirror the entire item.

*Events sub-tab* — EVENTS-track text event insertion at the playhead (the only sub-tab that writes to EVENTS, not VENUE). One row per event group; vocabulary lives in `section_events.lua`, validated against `_external_docs/Text Events List - Events.txt` by `dev/tests/venue_events.lua`.
- Section groups (Intro, Structure, Solo, Break, Tempo/Energy, Interlude/Jam, Outro/Ending, Misc) — base-name combo + number slider (`bare` or `_1`–`_9`) + **Add**. A read-only `->` indicator shows the exact event the next Add inserts live at the playhead, or `-> (blocked)` when it would be refused (reason on hover; a refused Add also reports the reason in the result section).
- **Insert validation** (`NextSectionEvent` / `ValidatePlainInsert`, pure functions over a positional scan): duplicates refused with the existing event's location; bare and numbered variants of one base must not co-exist; plain and lettered forms of one (base, number) must not be mixed; numbers/letters must be used in sequence (`_2` needs a `_1`-family event) and placed in timeline order between their sequence neighbors; no two text events on one PPQ. `[crowd_*]` events are exempt from all rules and may stack anywhere.
- **Use letter suffix** checkbox (default on) — Add inserts *only lettered forms*, starting at `a` (`[prc_verse_1a]` → `[prc_verse_1b]`; never the unlettered event, so parts always merge in Section gen; hand-deleted letters are re-offered as gaps), capped per base by the valid vocabulary. When off, Add only inserts the plain event and refuses when it exists. Bases with no lettered variants (`.` caps, e.g. `bre`, entry cues) insert the plain form in either mode.
- **Insert bookends** — removes prior instances of the six bookend events, then inserts `[prc_intro]` + `[crowd_normal]` at measure 1, `[music_start]` at measure 3, and `[prc_outro]`/`[music_end]`/`[end]` at E−5/E−2/E where E = last measure fully contained in the MIDI item (`TimeMap_GetMeasureInfo` walk); items under 7 full measures skip the end trio. Occupied target spots are skipped and reported.
- **Clear all** — removes every type-1 text event from the EVENTS take (track-name meta untouched).
- Generic group — `[prc_a]`–`[prc_k]`, digits append with no underscore (`[prc_a3]`), no letters.
- Crowd / Global groups — plain full-event combos (`[crowd_*]`, `[music_start]`, `[music_end]`, `[end]`, `[coda]`); Global gets duplicate/same-spot checks, Crowd does not.
- Targets the EVENTS track by name (`FindEventsTake`); an inline hint is shown and all buttons are disabled when the track or its MIDI item is missing. `S.venue_ev_mode` is reserved for a phase-2 target-mode radio (see `SONG_SECTION.md`).
- The take + scan feeding the indicator are cached via `MakeProjectPoll(1.0, 5.0)` (see the polling convention below), force-refreshed by the tab's own edit buttons, and pointer-validated each frame (`ValidatePtr2`); the cursor lookup + row validation over the cached scan are pure Lua and run per frame. The Add actions always re-scan, so the UI cache can never cause a wrong insert.

*Themes gen sub-tab* — whole-song generation driven by a `.rbtheme` file.
- **Theme combo** — select a `.rbtheme` file from the `resources/themes/` folder (themes are not shipped with the project; add `.rbtheme` files to enable). Shows `(select a theme)` when none loaded; Generate button is disabled until a theme is chosen. If the `resources/themes/` folder is empty a warning is displayed and all inputs are disabled.
- **Camera pacing** — override the theme's camera cut rate, or keep Theme default.
- **Keyframe align** — global alignment mode for keyframe events across all sections. See "Keyframe placement rule" below: it decides where the first `[next]` lands, never where `[first]` goes.
- **Generate venue events** — generates camera cuts, lighting changes, manual lighting control keyframes, and postproc effects on the VENUE track. Filters camera pools based on which PART instrument tracks are present and unmuted. Respects time selection (partial regeneration). Fully undoable.

*Section gen sub-tab* — per-section manual configuration.
- **Mode** — Custom (configure the section by hand) or Template (read values from a theme's section preset).
- **Section selector** — pick a song section (auto-loaded from `[prc_*]` markers). Refresh button re-reads sections from the EVENTS track.
- Per-section config: Lighting preset, Keyframe align (disabled for auto/no lighting), Keyframe rate, Light blendin, Post-process, PP blendin, Directed cut at start, Bonus FX. The two blendin values follow the "Blend-in rule" below — this tab reads the outgoing preset off the VENUE track (`FindActiveVenuePresetsBefore`) before clearing anything, and never clears back over those source events.
- **Camera pacing** — override the camera cut rate for the generated section.
- **Generate section** — generates events for the selected section only. Fully undoable.

*Manual gen sub-tab* — shot-by-shot event insertion at the playhead.
- **Normal camera** — pick any `[coop_*]` shot; **Add** inserts it at the edit cursor.
- **Directed camera** — pick any `[directed_*]` shot including BRE events; **Add** inserts it.
- **Lighting** — pick any lighting preset; **Add** inserts `[lighting (name)]`. **Blend** (see below) needs no dropdown selection.
- **Blend** (Lighting and Post proc rows) — copies the preset of that type currently running to the playhead: the same anchor Themes/Section gen place from `lightpreset_blendin` / `postproc_blendin`, for hand-authored transitions. It reads the **VENUE track**, never the dropdown, so it sits outside those rows' `BeginDisabled` guard and works with nothing selected. `ResolveBlendSource` (`actions_venue_manual.lua`) is the pure decision — kept separate from `BlendVenuePresetAtPlayhead` so the rule is testable without a playhead. It refuses, reporting each event it found with its `FormatTime` position, when: an event of that type is already on the playhead (within the shared 1/128-note spot tolerance — an anchor belongs *before* what it blends into), none precedes the playhead, or the two most recent are identical (that pair already **is** an anchor, per the restatement rule below). A single preceding event copies with a note that there was no pair to check. Refusals return before any `Undo_*` call, so they leave no undo point.
- **Keyframe align** (with an **Add** button next to it that generates keyframes) + Subdivision (own row, instrument-aware modes only) + Keyframe rate. The whole row is enabled only when the playhead sits on a manual lighting event — see "`[first]` gating" below.
- **Post proc** — pick any `[*.pp]` effect; **Add** inserts it.
- **Special** — `[bonusfx]`, `[bonusfx_optional]`, `[first]`, `[next]`, `[previous]`; **Add** inserts the chosen event. `[first]` is gated (below); the others are insertable anywhere.
- **Camera pacing** — shared camera pacing override (same state as other gen tabs).
- **Advance camera pacing** — moves the edit cursor forward by one jittered camera interval.
- Keyframe align's **Add** button generates `[first]`/`[next]` from cursor to the next lighting event / time selection end / VENUE item end (delegating to the shared `GenerateKeyframesForSpan`). Clears existing keyframe events in the range first. Fully undoable.
- **`[first]` gating** — a `[first]` only means something on a manual lighting event's own tick, so both the Special row's `[first]` and the entire keyframe row require one at the playhead (`FindManualLightingAtPpq`, tolerance ~1/128 note). Blocked state shows a `(blocked)` marker whose hover carries the shared `NO_LIGHTING_AT_PLAYHEAD_MSG`, the same string the refused action puts in `S.status` — the "(blocked)" affordance the Events tab already used. The gate reads the event **under the playhead**, not the Lighting dropdown, so an existing `[lighting (stomp)]` can be re-keyframed without re-picking it. The UI caches the manual lighting positions behind a `MakeProjectPoll` (as in `ui_venue_events.lua`) and only compares the playhead against that short list per frame — the cursor moves constantly while the event list doesn't, and a finished VENUE track carries thousands of text events. Both actions re-check the take for themselves, and a refusal returns before any `Undo_*` call so it leaves no undo point.
  - Since the keyframe row is disabled in the blocked state and a disabled ImGui widget reports no hover, the `(blocked)` label is drawn in a brief `EndDisabled`/`BeginDisabled` gap so its tooltip is reachable.
- **Remove** — category dropdown (Camera / Lighting / Post proc / Special) + **Remove** button; removes matching events from time selection (if active) or full song. Fully undoable.

*Keyframes sub-tab* — bulk regeneration of `[first]`/`[next]` keyframes for every manual lighting event already on the VENUE track.
- **Keyframe align** + subdivision (when an instrument-aware mode is selected) — shared global state, same as the other gen tabs.
- **Keyframe rate** — this tab's own value (`S.venue_kf_rate`), independent of Manual gen's rate.
- **Regenerate keyframes** — scans the VENUE track for `[lighting (...)]` events that are manual (`verse`, `chorus`, `manual_cool`, `manual_warm`, `dischord`, `stomp`); for each one inside the processing range that *changes* the running preset, clears and regenerates its `[first]`/`[next]`/`[previous]` events running from that lighting event to the next lighting event that changes it again. An event repeating the one immediately before it (a blend duplicate) neither starts a span nor ends one — see the keyframe rule below. Camera, lighting, postproc, and bonus FX are never touched. Respects time selection (only lighting events whose own position is inside the selection are regenerated — a section already in progress from before the selection is left untouched); otherwise processes the whole song. Fully undoable.

**Blend-in rule** (Themes gen and Section gen): `lightpreset_blendin` / `postproc_blendin` do **not** move a section's own lighting/postproc event earlier — those always sit on the section start. The value says how many beats ahead of the boundary the **outgoing** preset is duplicated, as an anchor for the game to blend from. `BlendPpq` / `EmitBlendDuplicates` (`venue_lighting.lua`) own the rule; `.claude/CLAUDE_venue_theme_generation.md` has the worked example and every skip condition.

**No generator ever re-states a running preset** (Themes gen and Section gen). Two identical adjacent events *are* an anchor, so a section that resolved to the preset already playing would forge one, and all four readers above would take it as deliberate. Two layers enforce it, lighting and post proc judged independently:
- `ResolveThemeSection` picks with `PickRandom(pool, prev_text)` — the same repeat-avoidance helper the camera pools and `GenerateLightingEvents` use — so a multi-preset pool re-rolls onto something else. Section gen's Template mode does the same against `FindActiveVenuePresetsBefore`'s result, which is why that lookup now runs *before* the roll.
- `EmitThemeSection` skips the event outright when it still matches (a one-entry pool, Section gen's Custom-mode fixed choice, the song-start bookend). `GenerateThemedSectionEvents` returns a 4th value, `stats = { lt_skipped, pp_skipped }`, and both callers report it.

The section's **keyframes are emitted either way** — only the lighting event is skipped. The previous section's `[next]` train was bounded by *its own* `sec_end_ppq`, so a kept manual preset with no train here would run on with its lights frozen. `[first]` is withheld by the same test, which is the pre-existing restatement rule. Manual gen is deliberately exempt: an author asking for a duplicate there gets one.

**`IsBlendAnchor(a, b)`** (`venue.lua`) is the one home for the *read* side of that rule: two identical **adjacent** events of one kind are an anchor. Four places read it back off a track and must agree — `ResolveBlendSource` (Manual gen's Blend button refusing to add a third copy), `ValidateVenueLightingBlends` (reporting changes with no anchor), the keyframe restatement test (a duplicate carries no `[first]` precisely because it is one), and `AnnotateVenueBlends` (the Preview, below). Any new code deciding "is this a blend?" calls it rather than re-comparing two `msg` fields. It lives in `venue.lua`, not beside the write side in `venue_lighting.lua`, because `venue.lua` is in the standalone Preview's module subset and `venue_lighting.lua` deliberately is not.

**`AnnotateVenueBlends(events)`** (`venue.lua`) is what turns a raw per-kind event list into preset *state* for a reader that wants "what is running", not "what is written". Pure over `{msg, t, ppq}` records. It drops every anchor — a restatement is not a state of its own — and annotates each survivor with `blend_out_t`/`blend_out_ppq` (where the anchor for the **next** change sits, `nil` = hard cut) and `next_t` (when that change lands). Those two together bound the window in which a fade is actually in progress, which is what lets the Preview's Current card say "blending now" without any column knowing which column it is. With three or more identical copies `blend_out_t` is the **last** restatement, matching `IsBlendAnchor`'s adjacency rule. `GetVenueEventsForPreview` runs lighting and post proc through it; **camera is left raw** — a camera cut never fades, and two adjacent identical camera events are a repeat `ListVenueEvents` already reports as a fault. `GenerateThemedSectionEvents` resolves all sections' picks in a first pass before emitting, because emitting a section needs the *previous* section's preset — both to duplicate into the blend zone and to tell whether this section changes anything at all; its optional `incoming` argument supplies the preset state before the first section (Themes gen: the song-start bookend; Section gen: `FindActiveVenuePresetsBefore` off the track). The duplicate carries no keyframes of its own — see the keyframe rule below.

**Keyframe placement rule** (all four generating tabs — Themes gen, Section gen, Keyframes, Manual gen):

- **`[first]` marks a preset CHANGE, and shares that lighting event's tick.** It is the event's own initial keyframe; nothing moves it — not the align mode, not the blend-in. A lighting event that *restates* the preset already running starts no sequence: a blend duplicate, or a section that kept the previous section's preset. The train from the event that did start it carries on through. Enforced in three places from the one rule: `EmitThemeSection` (`venue_lighting.lua`), `RegenerateVenueKeyframes`' span walk (which neither starts nor ends a span on an event repeating the one immediately before it), and `GenerateManualKeyframes`' span-end clamp. Only **adjacent** events are compared, so two sections sharing a preset with a different one between them are each a real change. This is what lets the Keyframes tab round-trip: it sees only track events, never sections or blendin values, so any position-based heuristic would drift from the generators.
- **Align modes decide only where the first `[next]` lands.** Mode 0 `Keyframe rate only` (one rate past the closest beat, nothing at the anchor), 1 `Closest beat`, 2 `Downbeat`, 3–7 instrument-note-driven. Labels live in one shared `KF_ALIGN_LABELS` (`venue_lighting.lua`); mode indices are the persisted `S.venue_keyframe_align` values, so never renumber them.
- **In "Closest beat" mode the snapped beat is a `[next]`, not the `[first]`** — that mode is the only one whose anchor differs from the lighting event's own tick. Skipped when the two coincide, so no duplicate event lands there.
- **Instrument-aware modes (3–7) are the exception**: no `[next]` at the section start, because every `[next]` in those modes must be backed by a real note.
- **Snapping trap:** `venue_generator.lua`'s `insert_text` and `actions_venue_section.lua`'s `insert_snapped` half-beat-snap lighting events but insert keyframes unsnapped (`no_snap = true`, so finer instrument-aware positions survive). A `[first]` meant to share a lighting event's tick must therefore be pre-snapped with the shared `SnapPpqToHalfBeat` (`venue_lighting.lua`) — `EmitThemeSection` and `EmitBlendDuplicates` do this. Emitting it at the raw position lands it a few ticks off the event it belongs to.
- `GenerateManualKeyframes` (Manual gen) calls `GenerateKeyframesForSpan` rather than duplicating it — the two were verbatim copies before v0.9.42. `GenerateKeyframesForSpan` assumes its `start_ppq` **is** a lighting event's tick; both callers guarantee that (the Keyframes tab walks lighting events, Manual gen gates on the playhead).

---

## Module contents

| File | Contents |
|---|---|
| `rock_band_general_helper_vkr.lua` | Entry point: ReaImGui check, path derivation, dofile calls, startup |
| `rock_band_general_helper_vkr/defaults.lua` | `VENUE_VALID`, `DIRECTED_GAP_MIN`, `MIDI_META_NAMES`, `S`, `TIPS` |
| `rock_band_general_helper_vkr/settings.lua` | `SaveSettings`, `LoadSettings` (project key: `RBHelperVKR/settings_v1`) |
| `rock_band_general_helper_vkr/helpers.lua` | `FindTrackByName`, `FindNamedTrackMIDI` (track + first MIDI item/take; self-contained for the standalone preview), `GetTakePPQPerQN`, `SetDefaultTempoTracks`, `SetDefaultMIDITracks`, `GetTempoContextBefore`, `GetMeasureStartTime`, `GetAudioItems`, `MakeProjectPoll` |
| `rock_band_general_helper_vkr/venue.lua` | `ListVenueEvents`, `GetVenueEventsForPreview`, `IsBlendAnchor`, `AnnotateVenueBlends` (global); `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats` (local). Holds the **read** side of the blend rule (`IsBlendAnchor`) because this module is in the standalone Preview's subset and `venue_lighting.lua`, which owns the write side, deliberately is not. |
| `rock_band_general_helper_vkr/venue_awareness.lua` | `GetMutedInstruments`, `GetCoopRequiredInstruments`, `GetDirectedRequiredInstruments`, `FilterPool`, `ReadEventSections`, `ListEventSections`, `FindEventTime` (generic EVENTS-track text-event lookup), `FindMusicStartTime` (thin wrapper over `FindEventTime`), `INST_LETTER_NAMES` (global); `INST_TRACK_NAMES`, `ParsePrcEvent` (local) |
| `rock_band_general_helper_vkr/venue_camera_priority.lua` | `CAM_PRIORITY_TIERS`, `CAM_PRIORITY`, `CAM_GENERIC_FALLBACK`, `CameraShotPriority`, `CameraShotFitsBand`, `PickPriorityCameraEvent` (global); `KEYS_EXCEPTION`, `BareName` (local). Which of several shots stacked on one tick the game plays, transcribed from `_external_docs/RBN2 Camera And Lights - RBN_C3 Documentation.htm`. Pure — no `r`/`ctx`/`S`; its `GetCoopRequiredInstruments`/`GetDirectedRequiredInstruments` use is at call time, so it may load before or after `venue_awareness.lua`. Full write-up in `.claude/CLAUDE_venue_theme_generation.md` ("Camera shot priority"). |
| `rock_band_general_helper_vkr/venue_themes.lua` | `ThemeDisplayLabel`, `LoadVenueThemes`, `GetSectionPreset`, `GetThemeCameraInterval`, `BuildLightingPool`, `BuildPostprocPool` (global); `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme` (local) |
| `rock_band_general_helper_vkr/venue_camera.lua` | `COOP_POOL`, `COOP_LABELS`, `DIRECTED_POOL`, `DIRECTED_LABELS`, `DIRECTED_TIPS`, `PickRandom`, `JitteredInterval`, `CategorizeCoopPool`, `WeightedPickCoopEvent`, `FindCompanion`, `ComputeIdleState`, `GenerateCameraEvents`, `ResolveUserCamInterval` (global); camera constants (`CAM_INTERVAL_16THS` etc., partially global); `WeightedPickInstrument` (local) |
| `rock_band_general_helper_vkr/venue_sprites.lua` | `LoadVenueSprite`, `DrawVenueTooltipSprite`, `BeginVenueTooltip`, `EndVenueTooltip`, `VenueEventTooltip`, `RawVenueEventText`, `VenueSpriteFoldersFound` (global); `DIRECTED_SPRITE_NAMES`, `VENUE_SPRITE_ROOT` (module-level globals). JPEG-only. Checks `resources/img/spritesheets/{category}/` (large) then `resources/img/spritesheets/{category} small/` (small) — no third-party fallback. Frame count is read from the filename (`{key}_f{N}_spritesheet.jpg`). Display size scales by `S.venue_preview_scale` (1 or 2). Cache stores `{image, frame_count, cols, rows}` per sprite. |
| `rock_band_general_helper_vkr/venue_lighting.lua` | `MANUAL_LIGHTING_SET`, `LIGHTING_OFFSET_16THS`, `INST_KF_MODES`, `KF_ALIGN_LABELS`, `FindNextMeasureStartPpq`, `CollectInstNotePositions`, `GenerateKeyframesForSpan`, `GenerateLightingEvents`, `GenerateThemedSectionEvents`, `SnapPpqToHalfBeat` (global); `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, lighting constants, `SnapPpqToNearestBeat`, `BlendPpq`, `EmitBlendDuplicates`, `ResolveThemeSection`, `EmitThemeSection` (local) |
| `rock_band_general_helper_vkr/venue_generator.lua` | `GenerateVenueEvents`, `DeleteTextEventsInRange` (predicate-driven deleter backing all clear functions), `ClearVenueTextEventsInRange`, `ClearVenueNonCameraEventsInRange`, `ClearVenueExceptLPInRange`, `ClearVenueKeyframesInRange`, `FindActiveVenuePresetsBefore` (global) |
| `rock_band_general_helper_vkr/workflow.lua` | `ParseWorkflowContent`, `ParseWorkflowFile`, `LoadWorkflowFiles`, `EscapeWF`, `UnescapeWF` (global); `FindBraceGroups`, `StripBraceGroups` (local) — Workflow sub-tab's `.txt` template parser (pure over string content) + `resources/workflow/` folder scanner |
| `rock_band_general_helper_vkr/actions_workflow.lua` | `CompositeKey`, `PruneToWorkflowEntries`, `SaveWorkflowState`, `LoadWorkflowState`, `SelectWorkflowFile`, `ToggleWorkflowItem`, `ComputeWorkflowStats` (global) — Workflow checklist state, persistence (`workflow_v1` ExtState key), template-switch pruning, and the pure progress-count helper |
| `rock_band_general_helper_vkr/difficulty_read.lua` | `FindTrackExact`, `ReadGemEvents`, `CountStrumOverrides`, `ReadMarkerSpans`, `ReadVocalNotes`, `ReadPhraseSpans`, `ReadPercussionSpans`, `ReadLaneShifts`, `ReadPlayingSpans`, `ANIM_PLAYING`, `ANIM_IDLE`, `VOCAL_LO`, `VOCAL_HI` (global); `TrackEndTime` (local) — reads a chart off REAPER tracks into the plain tables `lib/reaper_difficulty_score*.lua` consume. Uses `r.*` but no `S`/`ctx`, so `dev/calibration/corpus.lua` loads it too. **That sharing is the point:** every row of `dev/calibration/corpus_scores.csv`, and so every fitted coefficient, was produced by these exact readers — any divergence makes the shipped suggestion a different measurement from the one the model was fitted against. `FindTrackExact` is an exact case-insensitive name match, not `FindTrackByName` and not a substring search: these MIDIs carry `PART KEYS_ANIM_LH` beside `PART KEYS`, and `PART REAL_KEYS_E` before `PART REAL_KEYS_X`. |
| `rock_band_general_helper_vkr/metadata_genres.lua` | `RB3_GENRE_ORDER`, `RB3_GENRES` — the supported genre vocabulary, **29 major genres and 126 subgenres**, transcribed from `_external_docs/Subgenre Descriptions - RBN_C3 Documentation.htm`. Data only, pure. Note that page's own intro prose says "120 subgenre groupings, under 21 major genres" while the page **enumerates 29 and 126**; the enumeration is correct (checked against the tool that does the final selection), so the counts must not be "corrected" back to the prose — `dev/tests/metadata_genres.lua` asserts both numbers. Per-subgenre `blurb`/`elements`/`artists`/`albums` are **optional and mostly absent**: only 33 of the 126 carry any description at all, so every consumer must render correctly from a bare label. **No `.dta` tokens, deliberately** — token spellings drift between game eras (RB1/RB2 `urban` became RB3 `hiphoprap`) and are scoped to their parent (`subgenre_pop` is Pop-Punk under `punk` but Pop under `poprock`), and the packaging tool that writes `songs.dta` has its own picker. |
| `rock_band_general_helper_vkr/metadata_genres_ext.lua` | `GENRE_FAMILY_ORDER`, `GENRE_FAMILIES`, `EXTENDED_GENRES` — the authored half: 208 real-world genres across 10 families, each with 1–3 ranked candidates and a written reason. Data only, pure. Calibrated against 3126 released songs (1375 carrying a subgenre) in `_external_docs/genre_reference_songs/`. **A second candidate is a real fork, not hedging.** A `see_also` entry is a different thing again: it points at another *extended* entry (Post-Grunge -> Grunge) and means "you may have picked the wrong genre", not "here is another supported home" — which is why it is not a candidate and the UI draws it unnumbered below a separator. The header also fixes the **dimension precedence**, which looks arbitrary until stated: an explicit supported category wins first (J-Rock maps by origin only because Rock Band *has* that genre; K-Pop has no equivalent so it maps by sound), then musical style, then scene/origin, then instrumentation or source. Four entries (Viking Metal, Folk Metal, Screamo, Big Band) were settled against web sources rather than taste after `GENRE_REVIEW.md`, and `dev/tests` pins each so a later edit cannot quietly undo them. A multi-filed artist in the catalogue has three distinct explanations that must not be conflated: the band changed style (both filings correct), the cataloguing convention changed between game eras (A Day to Remember is `punk/alternative` on both RB2 songs and `rock/hardrock` on both RB3 ones, from adjacent easycore-era albums), or the boundary genuinely is ambiguous (Five Finger Death Punch has two filings in the *same* era). Only the third justifies a second candidate. |
| `rock_band_general_helper_vkr/metadata_genres_lookup.lua` | `GenresInFamily`, `ExtendedGenreByKey`, `RB3Subgenre`, `ResolveExtendedGenre`, `BuildReverseGenreIndex`, `ExtendedGenresForPair`, `ValidateGenreTables` (global); `PairKey`, `BuildCaches`, the three caches (local) — pure lookup over the two tables above. Caches are built on first use and never invalidated, because neither table changes at runtime. `ResolveExtendedGenre` **skips** a candidate whose pair does not resolve rather than returning a half-built row, so malformed data cannot crash the tab; the test asserts that never actually happens. The reverse index splits each pair's inbound entries into `first` (this pair is that genre's best answer) and `lower` (offered as an alternative) — collapsing them would hide the difference between a style's primary home and somebody's second choice. `ValidateGenreTables` returns a problem list and is used by the tests, not the UI. |
| `rock_band_general_helper_vkr/ui_metadata_genre.lua` | `DrawMetadataGenreTab` (global); `DimWrapped`, `ClampIdx`, `DrawSubgenreDoc`, `DrawForward`, `DrawReverse` (local) — the Genre sub-tab body. **Stricter read-only than Difficulty beside it: it does not even read the project**, so there is no Refresh, nothing to reset on a project switch, and no undo point. **One direction only.** A reverse view (pick a supported genre, see what maps onto it) was built and then cut before release: browsing the supported list is not a task an author has, since they arrive knowing what their song is and needing the other half. Its lookup half survives in `metadata_genres_lookup.lua` (`BuildReverseGenreIndex` / `ExtendedGenresForPair`, no UI caller) because the round-trip test over it is a real integrity check on the mapping - it proves every candidate is reachable from its pair in the right rank bucket - so restoring the view would be a UI-only change. The tab narrows by family first (the vocabulary is past 200 entries, more than one dropdown can be read from) and **changing the family resets `S.genre_ext_idx`**, which addresses the previous family's list. Results are drawn **inline, not into `S.last_result`** — they change as the combo moves, and `ui.lua` wipes the shared panel on any main-tab change. `DimWrapped` exists because ImGui's `TextDisabled` has no wrapping variant. `see_also` pointers render **unnumbered, dimmed and below a separator** — numbering them beside the candidates is exactly the confusion that split exists to remove. |
| `rock_band_general_helper_vkr/ui_metadata.lua` | `DrawMetadataTab` (global); `RefreshSuggestions`, `CopySuggestionDetails`, `DrawCard`, `DrawDifficultyDots`, `DrawTierRuler`, `COL_*`/`DOT_*` (local) — the Metadata tab shell and its Difficulty sub-tab. One card per instrument: name, maturity chip (its meaning is the chip's **tooltip**, not a line on the card — the wording is a property of the model and would otherwise repeat identically on every keys/Pro Keys/vocals result), five difficulty dots, `<tier> (rank N)`, the **tier ruler**, warnings, then the notable properties as **always-visible** bullets. The ruler replaced a `TextDisabled` line ("near the bottom of this tier") that duplicated the amber boundary warning below it while carrying none of the numbers; that wording survives as the ruler's tooltip. It is **drawn, not spelled with dashes** — nothing in this repo loads a font, so ImGui's proportional default cannot hold dash columns aligned between cards; the ASCII form is right only in `dev/tools/verify_suggester_vs_csv.lua`, which prints to a monospace console. Its left label is computed with `LabelColWidth` over **all six** records so the rulers align down the column. A clamped rank pins its marker to that end in `COL_WARN`: a clamped rank is a limit, not a position, and drawing it mid-band would claim the precision the clamp exists to deny. **`Copy details` and `Show measured values` are both gated on `S.show_wip_tabs`**, and so is the `Details` panel itself — not just its checkbox, since ticking it and then turning the WIP flag off would strand an open panel with nothing on screen able to close it. Both answer a calibration question rather than an authoring one, so the first release keeps them one checkbox away in General > Other rather than on the default panel. `S.diff_show_factors` is **session-only and deliberately not persisted** (it had a `dsf=` key; it was removed): a saved value could return in a project where its control is not drawn, so the panel's visibility would have two possible explanations and no way to tell them apart. The raw factor table sits behind a `Details` `CollapsingHeader` shown only when `S.diff_show_factors` is on (off at every startup) — it is a development view, meaningless to an author, and the bullets say the same thing in words. **First use of `CollapsingHeader` / `Indent` in this repo**; the dots follow `ui_venue_players.lua`'s `DrawList` idiom. Scores on demand only — walking every note on six PART tracks is far too much per frame, and a number that changed while being read would be worse than a stale one. Results live in session-only `S.diff_suggestions`, cleared on project switch. There is deliberately **no apply control**: a one-click write would turn an estimate into the answer. `CopySuggestionDetails` is a thin wrapper — the project name (behind a `pcall`, since `GetProjectName`'s signature has moved across REAPER versions) and `ImGui_SetClipboardText`, with the formatting in `difficulty_report.lua` so it tests headlessly. It sets `S.status` on success because a clipboard write is otherwise indistinguishable from a dead button, and is `BeginDisabled` before the first Refresh. |
| | **The dots** reproduce the game's own display: five, filled from the left, red at the top. Seven tiers map onto five because the top two share a filled count (Warmup 0, Solid 2, Nightmare 5, Impossible 5 in red) — that is how the game shows them, not a compression introduced here. An unfilled dot is mid-grey on a near-black plate rather than black on the window background, which is invisible in this theme. |
| `rock_band_general_helper_vkr/difficulty_explain.lua` | `DIFFICULTY_FACTOR_INFO`, `DIFFICULTY_FACTOR_ORDER`, `DIFFICULTY_STATUS_BADGE`, `DIFFICULTY_STATUS_NOTE`, `DifficultyPositionText`, `DifficultyRulerBand`, `DifficultyFactorRows`, `DifficultyExplanations`, `DifficultyWarnings`, `DifficultyAnnotate` (global); `FormatValue` (local) — turns a suggestion into words. Pure, so `dev/tests` drives it with hand-built factor tables. **Never shows regression coefficients**: the factors are near-collinear, so a large coefficient says which of a correlated pair the solver loaded, not what the chart demands. It reports what was *measured* — the ≤3 properties on which this chart is unusual versus the training corpus (|z| ≥ 1.0), which is a claim about the chart and the corpus with no causal content. **A candidate that merely restates a bullet already chosen is skipped** (`COLLINEAR_R = 0.70` against the artifact's `model.corr`), because picking by |z| alone spent two of three slots on one observation on 20% of corpus rows. The loop *continues* rather than breaks, so the slot goes to the next distinct factor; where every remaining notable factor restates one already shown, the card correctly ends up with fewer than three bullets rather than a padded three. `model.corr` is optional and its absence degrades to the old behaviour. `DifficultyFactorRows` is deliberately **not** filtered — the Details table is a complete list, and comparing two charts needs every row. Interval factors (`tight_p10`, `tight_med`) are spacings, so **low is the hard direction** and their wording is inverted. Warning thresholds: tier position ≤ 0.15 / ≥ 0.85, concentration against the model's own per-instrument training p90 (bass and drums never mark a solo, so only the density-ratio branch can fire there; vocals has neither and never warns). **Out-of-range measurements are not a card warning** — they ride on `factor_rows[].out_of` and are shown beside the number in the Details view. Out of range means *unusual*, not *responsible*: a near-empty keys chart carried the corpus's largest average chord size (a sustained two-note pad — unusual and easy for unrelated reasons), and naming it beside a floor-clamped rank read as "it is easy because its chords are large". The clamped note therefore states the bound and stops. Model maturity is **not** a warning — it is a property of the model, not the chart, so it would repeat identically on every card forever; it lives in `DIFFICULTY_STATUS_NOTE` and is shown as the badge's tooltip. Warning wording avoids "calibrated", "extrapolation" and the like: the reader is an author looking at their own MIDI, so the notes say what the number means ("the rank is capped at 488 - the true figure is probably higher") rather than describing the statistics. No confidence percentage anywhere — the regressions produce no calibrated per-song probability. The **Details table is ordered by `DIFFICULTY_FACTOR_ORDER`, not by |z|** — a per-song order put a different factor in every position, so two charts on the same instrument could not be read side by side, which is the only reason that table exists; most-unusual-first still picks the ≤3 bullets, where a ranking is the point. A factor's `tip` is **optional and most do not need one**: it explains the *sentence*, not the measurement, so it earns its place only where the wording uses a term the reader cannot map onto their own MIDI. Requiring one per factor produced tooltips describing the hidden number under a bullet that shows no number, and tooltips explaining game mechanics to the author who wrote the markers. `dev/tests` asserts quality (no tip under 40 chars) rather than coverage, and asserts `DIFFICULTY_FACTOR_ORDER` and `DIFFICULTY_FACTOR_INFO` hold exactly the same keys. `DifficultyRulerBand` supplies the tier ruler's band, its two end labels and a `pinned` flag; the ends with no neighbouring tier are labelled `min <rank_lo>` / `max <rank_hi>` rather than inventing a seventh tier name. **`DifficultyAnnotate` currently forces `rec.badge = nil`** — the maturity chip is switched off for the first release to keep the card plain while authors see it for the first time; the mapping and its tooltip text are still asserted by the tests so the one-line change that restores it stays safe. |
| `rock_band_general_helper_vkr/difficulty_report.lua` | `DifficultyReportText(recs, opts)` (global); `Wrap`, `Pad` (local) — the Copy details button's output. **Pure**, and consumes only what `DifficultyAnnotate` already built (`factor_rows` is pre-formatted and pre-ordered), so it needs none of `difficulty_explain.lua`'s locals and `dev/tests` drives it directly. Split out rather than appended because that file was at 633 lines, in CLAUDE.md's "evaluate splitting before adding more" band. **Aligned plain text, not markdown** — this gets pasted into forum posts, text files and REAPER's console, where a markdown table is pipe-and-dash noise. Column widths are measured across **all** blocks so instruments line up with each other. It **always includes the full factor table**, ignoring `S.diff_show_factors`: producing those numbers for someone else to read is the entire point, and the hand-copied 26-row drum table that prompted the feature had silently lost a row. Each block names its candidate, scale and the artifact schema, because the keys model changed twice in one week and a pasted report has to be identifiable as pre- or post-change. The uncapped score appears only when the clamp actually moved the rank. |
| `rock_band_general_helper_vkr/difficulty_suggester.lua` | `SuggestProjectDifficulties`, `CountVocalParts`, `HasAnyChartTrack` (global); `Unavailable`, `NoContent`, `SuggestOne` (local) — the read-only Metadata > Difficulty adapter. Returns one record per instrument (`rank`, `tier`, `tier_position`, `factors`, or `ok = false` with a `reason`); never touches `S`, never writes, never creates an undo point. Scores the **whole** chart — a time selection is deliberately not consulted, because the models were calibrated on whole songs. `CountVocalParts` derives `vocal_parts` from HARM2/HARM3 carrying notes, which reproduces the `songs.dta` field on all 203 corpus vocal songs. Reports "absent" and "muted" separately rather than calling `GetMutedInstruments`, which conflates them (see the comment there). |
| `rock_band_general_helper_vkr/overdrive_read.lua` | `OD_PITCH`, `OD_FILL_LO/HI`, `OD_PHRASE_PITCH`, `OD_SOLO_PITCH`, `OD_QN_EPS`, `OD_INST_GROUPS`, `OD_VOCAL_TRACK`, `OD_HARM_TRACK`, `OD_GROUP_CHOICES`, `OdInstGroup`, span helpers (`OdSpansOverlap`, `OdSameQN`, `OdSameSpan`, `OdAnyOverlap`, `OdSpanListsEqual`), bar helpers (`OdCountedBeats`, `OdReadBars`, `OdBarAt`, `OdBarStartingAt`, `OdBarsOfSpan`, `OdBarActivity`), `OD_TOM_MARKERS`, `OdCrashBars`, `OdTrackTakes`, `OdReadPitchNotes`, `OdBuildModel`, `OdFinishModel`, `OdWhere` (global); `PitchSpans`, `FillSpans`, `ReadEventsTrack` (local) — the Overdrive tab's song model, all in quarter notes. Reads through `difficulty_read.lua`'s `FindTrackExact` / `ReadGemEvents` rather than a second reader |
| `rock_band_general_helper_vkr/overdrive_interest.lua` | `OdBarInterest`, `OdBandTogetherness` (global); `PercentileRanks`, `WindowTerms`, `BarSignature`, weights (local) — per-bar "eventfulness" from `DIFFICULTY_PRIMITIVES`. Pure |
| `rock_band_general_helper_vkr/actions_overdrive_fills.lua` | `OD_FILL_PACINGS`, `OdAutoFillPacing`, `OdPlanFills`, `OdActivationQN`, `OdSplitEarlyFills` (global) — drum fill planner. Pure |
| `rock_band_general_helper_vkr/actions_overdrive_vocals.lua` | `OdPlanVocals` (global) — vocal overdrive planner (cadence + HARM1 match). Pure |
| `rock_band_general_helper_vkr/actions_overdrive.lua` | `OdUnisonGroups`, `OdPlanInstruments` (pure), `OdJobs`, `OdFillAvoidSpans`, `OdVocalNoGo`, `OdDrumPhrasesForActivation`, `GenerateOverdrive` (global); `TakeAtQN`, `InsertQN`, `ClearPitches`, `GroupTracks` (local) — instrument/unison planner and the Generate action (replace confirmation, writing, report) |
| `rock_band_general_helper_vkr/actions_overdrive_validate.lua` | `OdValidateModel` (pure), `OdBuildOverview`, `ValidateOverdrive` (global) — read-only checks and the overview strip's data |
| `rock_band_general_helper_vkr/ui_overdrive.lua` | `DrawOverdriveTab` (global); `DrawOverview` (local) — tab body, overview strip, replace-confirmation modal (`ConfirmOverdriveReplace`) |
| `rock_band_general_helper_vkr/tempomap.lua` | `ComputeTempoRMSContour`, `DetectOnsets`, `EstimateBPM`, `GuessTimeSig`, `GetSourcesForRange`, `FitBeatGrid`, `RmsToOnsetFlux`, `FindLocalPeak` |
| `rock_band_general_helper_vkr/actions.lua` | `AlignAudioTracks`, `AlignAllAudio`, `AlignCountIn`, `CreateSongFadeOut`; `CountInBeatSlots` (local) |
| `rock_band_general_helper_vkr/actions_stem_import.lua` | `StemImportPlan`, `ImportStems` (global); `AUDIO_EXTS`, `KIT_EXCLUDE`, `STEM_RULES` (module-level locals); `HasAll`, `HasAny`, `Shortest`, `PickForRule`, `PickStemFolder`, `ListFolderFiles`, `InsertStemItem` (local) — General > Actions' "Import stems". `StemImportPlan(filenames)` is **pure** (no `r`): it maps filenames to template tracks by lowercase substring keyword, running `STEM_RULES` in a fixed order where a file claimed by one rule is no longer a candidate for later ones (so `drums_kick` goes to KICK AUDIO only), with the shortest base name winning ties and alphabetical order breaking equal lengths. KIT AUDIO rejects single-piece stems via `KIT_EXCLUDE`, because names like `drums_hh` are shorter than `drums_kit` and the shortest-name rule alone would pick them. `ImportStems` requires a SONG AUDIO audio item and places every stem at its position. It never touches a track that already holds audio, and it sorts every rule into a bucket before writing, so a run with nothing to import creates no undo point. The folder dialog comes from js_ReaScriptAPI when it is installed; otherwise the native file dialog is used and the picked file's folder is scanned |
| `rock_band_general_helper_vkr/actions_tempomap.lua` | `ShowTempoContext`, `EstimateInitialBPM`, `AutoTuneThreshold`, `ClearGeneratedTempoMarkers`, `GenerateTempoMap`; `BPM_MIN`, `BPM_MAX` (locals) |
| `rock_band_general_helper_vkr/actions_drums.lua` | `ConvertDrums` (global); `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport` (local) |
| `rock_band_general_helper_vkr/actions_drums_2x.lua` | `DoubleBassPlan`, `Remove2XKicks`, `MarkDoubleBassKicks` (global); `TRACK_2X`, `TRACK_1X`, `MARK_2X`, `KICK`, `MAX_SNAP_QN`, `AMBIGUITY_RATIO`, `UNMATCHED_LIST_MAX`, `SCAN_SPAN`, `SIXTEENTH_QN`, `EIGHTH_QN`, `MAX_EIGHTH_RUN`, `QN_EPS`, `BEAT_EPS`, `REVIEW_LIST_MAX` (module-level locals); `MBTAtQN`, `MIDITakesOn`, `NotesAtPitch`, `DescribeGap`, `MatchMarkers`, `MakeBarDownbeatTest`, `TightestGap`, `TrimRunEdges`, `IsDoubleBassLine`, `GridSlots`, `PickAlternating` — General > Actions' "Remove 2x kicks". **`PART DRUMS_2X` is a complete alternate chart, every kick at 96**; the build swaps the whole track in, and RB3 discards pitch 95, so a kick left at 95 simply never plays. `Remove2XKicks` reads that track's kicks (96 **and** any stale 95), plans the second foot in memory with `DoubleBassPlan`, deletes the matching kicks from `PART DRUMS`, and repairs any 95 back to 96 — all in one undo block across both tracks. Nothing records the plan on disk. Matching is in **project QN** via `MIDI_GetProjQNFromPPQPos`, the same rule as the difficulty validators' beat-fraction checks: bridging two takes through project seconds walks the tempo map twice in opposite directions and is only exact before the first tempo marker. Seconds appear here **only** to render report text. Each planned kick takes the nearest *unclaimed* kick on `PART DRUMS`, within `MAX_SNAP_QN` (a 1/32) **and** at least 4× nearer than the runner-up (`AMBIGUITY_RATIO`) — a relative test, so the window scales with note density; in a 1/32 blast beat any fixed millisecond buffer wide enough to forgive hand-nudging is also wide enough to grab the wrong gem. Both lists are sorted, so a moving insertion point ±`SCAN_SPAN` finds every candidate in O(n+m). Returns before any `Undo_*` call when there is nothing to remove *and* nothing to repair. Planned kicks already missing from `PART DRUMS` are normal on a re-run and are reported as "already absent", not as misses. `MarkDoubleBassKicks` writes pitch 95 and is **deliberately unreachable from the UI** — see `ui.lua`; it is kept and kept tested for a future version supporting games that read 95, and must not be wired up for RB3 |
| `rock_band_general_helper_vkr/actions_keys.lua` | `SplitHands`, `ConvertProKeys`, `ConvertPianoToProKeys`, `ConvertKeys5` (global); `PK_MIN`, `PK_MAX`, `PK_RANGES`, `PK_PREF_LABEL` (module-level globals); `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord` (local) |
| `rock_band_general_helper_vkr/actions_keys_guides.lua` | `ProKeysTabGuide`, `VocalTabGuide` (global); `PkEventLabel`, `ParseTabToRaws` (local) |
| `rock_band_general_helper_vkr/actions_guitar.lua` | `ConvertGuitar`, `ValidateGuitar`, `GetBPMAt`, `CompressChord`, `SortedChordPitches`, `GemLabel`, `PitchLabel`, `ChordTypeName`, `BuildShapeGemMap`, `ChordQualityLabel` (global); `GEM_MIN`, `GEM_MAX`, `GEM_LETTERS`, `CHORD_WINDOW_S`, `POOLS`, `POOLS2_NO14` (module-level globals) — Expert gem generation and authoring rule validation. `BuildShapeGemMap(events, max_chord, allow_14)` (shared with `actions_guitar_guide.lua`) is the global shape→gem-combo map builder; every 2+-note shape consults `GuitarSuggestRBMapping` (`lib/reaper_guitar_theory.lua`) BY PITCH CLASS (not physical note count) so e.g. a power chord — even voiced with a doubled root across 3 strings — always gets a 1-3-spread 2-gem combo. `max_chord`/`allow_14` are **parameters, not reads of `S`** — the two callers aren't governed by the same settings (see `actions_guitar_guide.lua` below); `max_chord = nil` skips compression entirely. Shapes with no principled width and 3+ notes bucket by `min(sz,3)`, since they all draw from `POOLS[3]` and must compete in one `AssignByConflict` group. `SortedChordPitches(pitches, max_chord)` returns an ascending **copy** (optionally compressed first) — `CompressChord` returns its argument unchanged when the chord already fits, so sorting in place used to reorder the caller's own `ev.pitches`. When a group has more distinct shapes than available combos, `AssignByConflict` gives the first (lowest-pitched) shapes a unique combo each, then assigns each overflow shape whichever already-claimed combo minimizes conflicts against shapes it's actually adjacent to anywhere in the passage (an adjacency table built from the real event sequence, restricted to same-group consecutive pairs), tie-broken toward the top of the pool and refined over a few bounded sweeps — returned as a third `shared` map so callers can flag reused combos; `ChordQualityLabel` names the recognized shape (e.g. `[Power chord]`) for the reason string |
| `rock_band_general_helper_vkr/actions_guitar_guide.lua` | `ParseTabHorizontal`, `ParseTabVertical`, `ReformatVerticalTab`, `GuitarTabGuide` (global); `AssignGemsForGuide` (local) — guitar Tab Input guide; `AssignGemsForGuide` delegates its shape→gem map to `BuildShapeGemMap` (`actions_guitar.lua`), calling it as `BuildShapeGemMap(events, nil, true)`. **No compression, and no reads of the Guitar tab's settings.** The Tab Input tab writes nothing to the project, so there is no chart to fit and nothing to reduce — `GuitarSuggestRBMapping` derives the gem count from distinct pitch classes across the whole shape, which is exactly how the Music Theory helper's Shape Search answers, and the two tools must agree (both exist to say how a chord maps to RB). Truncating by array index first made them disagree: it could drop a chord's root and keep a doubled note, turning an open D into a bare sixth dyad, or a G5 into three octaves of G with no suggestable width. `Max chord` / `Allow 1-4` / `Phrase gap` belong to the WIP Guitar tab's converter and are not exposed by this tab (`_DrawTabInputBody`, `ui_midi.lua`) — phrase breaks use the local `TAB_PHRASE_GAP_S` instead of `S.mc_gtr_wrap_gap_ms` |
| `rock_band_general_helper_vkr/actions_guitar_validate.lua` | `SustainThresholds`, `ReadRBGuitarNotes`, `RunValidation` (global) — validation helpers called by `ValidateGuitar` |
| `rock_band_general_helper_vkr/actions_midi_align.lua` | `AlignMIDI`, `ResizeAllMIDI` (global) |
| `rock_band_general_helper_vkr/actions_midi_replace.lua` | `GetPatternPitchRange`, `SetSearchPattern`, `SetReplacePattern`, `FillRange`, `DoMIDIPatternReplace`, `GoPrevPatternMatch`, `GoNextPatternMatch`, `ListPatternMatches` (global); `BuildPatternLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake`, `ResolvePatternScope`, `ScanPatternMatches`, `GoToPatternMatch` (local) |
| `rock_band_general_helper_vkr/actions_midi_length.lua` | `AdjustMidiNoteLengths` (global) — Midi note length/sustain-gap adjustment; `NoteLenPPQ`, `AdjustAllNoteLengths`, `AdjustSustainGaps` (local) |
| `rock_band_general_helper_vkr/actions_difficulty_shared.lua` | `CheckDifficultyProgression`, `CompressChordOffsets`, `DiffIssue`, `BuildDiffCheckReport`, `DiffReleaseGapQN`, `DiffReleaseGapName`, `DiffQNLabel`, `DIFF_RELEASE_GAP_QN` / `DIFF_RELEASE_GAP_SLOW_QN` / `DIFF_SLOW_BPM` (global) — cross-difficulty identical-chart + note-count reduction checks, the color-compression helper used by Keys/Guitar-Bass's Copy functions, the issue record + report builder the Keys and Guitar/Bass checks share, and their shared Medium/Easy sustain-release gap |
| `rock_band_general_helper_vkr/actions_difficulty.lua` | `CopyProKeysDiff`, `ValidateProKeysDiff`, `ValidateAllProKeys`, `CollectPKChecks`, `ReadPKTierEvents`, `PK_MAX_CHORD`, `PK_MAX_SPAN` (global) — Pro Keys difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_5k.lua` | `ValidateKeys5Diff`, `ValidateAllKeys5`, `CopyKeys5Diff`, `ReadK5TierEvents`, `CollectK5Checks`, rule tables `K5_RANGE` / `K5_MAX_CHORD` / `K5_MIN_SP` / `K5_ADV_SP` (global) — Keys (formerly "5-Lane Keys") difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_gtrbass.lua` | `CopyGtrBassDiff`, `ValidateGtrBassDiff`, `ValidateAllGtrBass` (global; take `instrument` = `'gtr'`\|`'bass'` as first param), `ReadGBTierEvents`, `CollectGBChecks`, rule tables `GB_RANGE` / `GB_MAX_CHORD` / `GB_MAX_SPAN` / `GB_FORCE_HOPO_ALLOWED` / `GB_ADV_SP` (global) — shared Guitar/Bass difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_drums.lua` | `CopyDrumsDiff`, `ValidateDrumsDiff`, `ValidateAllDrums` (global) — Drums difficulty rules |
| `rock_band_general_helper_vkr/ui_keys.lua` | `DrawKeysTab` (global) — Keys tab rendering |
| `rock_band_general_helper_vkr/difficulty_generate_retime.lua` | `Gen5RetimeDenseRuns` (global) — Hard's fast-run rewrite: dense runs on fast songs moved one grid slower (16ths → 8th triplets → 8ths) with a color-order-preserving DP. Pure, loaded before the planner; shared with the same offline consumers |
| `rock_band_general_helper_vkr/difficulty_generate_hopo.lua` | `Gen5IsAutoHopo`, `Gen5MarkHopos`, `Gen5ForceHopoSpans` (global) — which notes hammer on, and the force-HOPO markers Guitar/Bass Hard gets to keep Expert's. Pure |
| `rock_band_general_helper_vkr/difficulty_generate_colors.lua` | `Gen5ReduceChordSize`, `Gen5NarrowSpan`, `Gen5ShiftSegments`, `Gen5ShiftBars`, `Gen5ClampOrShiftBars` (global) — chord size/span and moving lines under a tier's top lane. Pure, loaded before the planner |
| `rock_band_general_helper_vkr/difficulty_generate_params.lua` | `GEN5_PARAMS`, `GEN5_SUSTAIN_QN`, `GEN5_MIN_LEN_QN`, `GEN5_EPS`, `Gen5BeatClass`, `Gen5MinGapQN`, `Gen5MinSustainQN`, `Gen5ReleaseGapQN` (global) — the tuned numbers and small shared rules of every Generate planner. Pure; loaded first of the Generate modules, since the rhythm and 5-lane files bind these at load time |
| `rock_band_general_helper_vkr/difficulty_generate_rhythm.lua` | `Gen5SelectOnsets`, `Gen5AndPhrases` (global) — which onsets a tier keeps: gap thinning, the Hard fast-run rewrite call, busy bars, keep cap, Medium's note per beat, following Guitar, Keys following Pro Keys. Shared by every planner, so the one-rhythm rule holds by construction. Pure |
| `rock_band_general_helper_vkr/difficulty_generate_5lane.lua` | `Gen5PlanTier` (global) — Difficulty > Generate's planner for Guitar/Bass/Keys: `Gen5SelectOnsets`, then chords, colors, sustains. No `r`/`S`; shared with `dev/calibration/run_generate_eval_offline.lua` |
| `rock_band_general_helper_vkr/difficulty_generate_prokeys.lua` | `GenPKPlanTier`, `GenPKReduceChord`, `GenPKBestWindow`, `GEN_PK_WINDOWS` (global) — Difficulty > Generate's Pro Keys planner: `Gen5SelectOnsets`, then top-note chord reduction, lane shifts, one Medium/Easy window, sustain gaps. Pure; shared with the offline evaluator |
| `rock_band_general_helper_vkr/actions_difficulty_generate.lua` | `GenerateDifficulties`, `GenInstrumentByKey`, `GEN_INSTRUMENTS`, `GEN_ALL_KEY` (global) — Difficulty > Generate's REAPER side: track resolution, read, plan, write, re-validate, one undo block |
| `rock_band_general_helper_vkr/ui_difficulty_generate.lua` | `DrawDifficultyGenerateTab` (global) — the Generate sub-tab body, called from `DrawDifficultyTab` |
| `rock_band_general_helper_vkr/ui_difficulty.lua` | `DrawDifficultyTab` (global) — Difficulty tab rendering (Pro Keys, Keys, Guitar/Bass, Drums, Generate sub-tabs) and the shared overwrite-confirm popup |
| `rock_band_general_helper_vkr/ui_common.lua` | `TrackCombo`, `MidiEditorTrackWarning`, `DrawStatusResultPanel(show_undo)` (global) — UI pieces shared with the standalone MIDI Pattern window. They live here rather than in `ui.lua` for the same reason the vocal helper's `ui_common.lua` exists: `ui.lua` ends in a bare `r.defer(Loop)` and cannot be dofile'd by a standalone |
| `rock_band_general_helper_vkr/ui_midi_pattern.lua` | `DrawMIDIPatternTab` (body only — no `Begin`/`BeginTabItem`), `ResetMIDIPatternState` (global); `MR_DIFF_OPTIONS` (local) — MIDI > Pattern sub-tab, shared with the standalone window |
| `rock_band_general_helper_vkr/ui_midi.lua` | `DrawTabInputTab`, `DrawMIDITab` (global) — Tab Input and MIDI tab rendering. The Pattern sub-tab's body is in `ui_midi_pattern.lua`; this file only wraps it in a tab item |
| `rock_band_general_helper_vkr/actions_venue_manual.lua` | `InsertVenueEventAtPlayhead`, `AdvanceCameraPacing`, `GenerateManualKeyframes`, `RemoveVenueEventsByType`, `FindManualLightingAtPpq`, `FindNextVocalPhraseStartPpq`, `ResolveBlendSource`, `BlendVenuePresetAtPlayhead`, `NO_LIGHTING_AT_PLAYHEAD_MSG` (global); `_spot_tol` (local) — Manual gen actions |
| `rock_band_general_helper_vkr/section_events.lua` | `SECTION_EVENT_GROUPS`, `SECTION_EVENT_BASE` — EVENTS-track event vocabulary (groups, per-base number/letter caps) for the Events sub-tab; data only, no S/REAPER deps |
| `rock_band_general_helper_vkr/actions_venue_events.lua` | `FindEventsTake`, `ScanEventsTextEvents`, `NextSectionEvent` (pure), `ValidatePlainInsert` (pure), `InsertEventsEvent`, `AddSectionEvent`, `ClearAllEventsTexts`, `InsertEventsBookends` (global) — Events sub-tab actions + validation |
| `rock_band_general_helper_vkr/actions_venue_keyframes.lua` | `RegenerateVenueKeyframes` (global) — Keyframes tab action: bulk-regenerates keyframes for every manual lighting event on the VENUE track |
| `rock_band_general_helper_vkr/actions_venue_validate.lua` | `ValidateVenueLightingBlends` (pure), `ValidateVenueLighting` (global); `NEAR_FIRST_BEATS`, `NearestIndex` (local) — Actions tab's "Validate lighting/blends": `[first]` placement against the preset-change rule, stray-`[first]` classification, and missing blend anchors for lighting and postproc. Read-only |
| `rock_band_general_helper_vkr/actions_venue_validate_camera.lua` | `BuildBandLineups`, `ValidateVenueCameraStacks` (pure), `ValidateVenueCamera` (global); `NEAR_STACK_QN`, `UNCOVERED_LIST_MAX`, `COOP_DUO_SET` (local) — Actions tab's "Validate camera stacks": duplicates, near stacks, shots that win under no lineup, and lineups with no valid camera shot. Read-only. Reads `CAM_PRIORITY_TIERS` at load time, so it must load **after** `venue_camera_priority.lua` |
| `rock_band_general_helper_vkr/actions_venue_sing_along.lua` | `GenerateSingAlong` (global) — Analysis tab action: derives VENUE pitch 85/87 sing-along notes from HARM2/HARM3 vocal phrases; `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans` (local) |
| `rock_band_general_helper_vkr/actions_venue_subtracks.lua` | `VENUE_SUBTRACKS`, `CategorizeVenueEvent` (the shared 6-way event classifier, also used by `actions_venue_manual.lua`'s `RemoveVenueEventsByType`), `FindOrCreateSubtrack`, `EnsureMatchingItem`, `CopyVenueEvents` (logic helpers, global for testability), `CopyVenueToSubtracks`, `CopyAllSubtracksToMain`, `CopySelectedSubtrackTo`, `CopySelectedSubtrackFrom` (global) — Actions tab's "Sub VENUE tracks" split/merge feature; `_find_venue_track_and_take` (local) |
| `rock_band_general_helper_vkr/ui_venue.lua` | `DrawVenueTab`, `RenderCamPacingRow`, `RenderKeyframeAlignCombo` (global) — Venue tab bar (Actions, Events, Themes gen, Section gen, Manual gen, Keyframes, Preview; only Actions and Themes gen are drawn inline — every other sub-tab delegates to its own file) plus the camera-pacing / keyframe-align widgets shared by the generation sub-tabs |
| `rock_band_general_helper_vkr/ui_venue_section_gen.lua` | `DrawVenueSectionGenTab` (global) — Section gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_manual.lua` | `DrawVenueManualTab` (global) — Manual gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_events.lua` | `DrawVenueEventsTab` (global) — Events sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_preview.lua` | `DrawVenuePreviewTab` (global) — Preview sub-tab rendering; caches the VENUE event lists + muted instruments, refreshed on any project state change with a 5 s fallback and a self-pause when one read takes ≥ 0.15 s. Each column is a **PPQ group** (`_group_at`), not one event: camera groups resolve through `PickPriorityCameraEvent`, lighting/post-process take the group's last event. When no shot in a group fits the Players combo the group's last event is drawn in red and `_FALLBACK_NOTE` explains the game's own fallbacks below the row. Lighting/post-process arrive already collapsed by `AnnotateVenueBlends`, so a blend anchor is never a card of its own; `_transition_line` turns its annotations into the line under each timestamp (`blends into next` / `blending now` / `hard cut to next`, blank for camera and for the last event of a kind). That line is drawn even when blank — a column one text line shorter than its neighbours would push its sprite out of alignment. |
| `rock_band_general_helper_vkr/ui_venue_players.lua` | `DrawActivePlayersRow` (global) — Active players dot row shown under every Venue sub-tab and in the standalone preview; PART-track play-state scan cached via `MakeProjectPoll(1.0, 5.0)`, playhead lookup recomputed on playhead change (≥ 0.5 s cadence during playback) |
| `rock_band_general_helper_vkr/ui_venue_keyframes.lua` | `DrawVenueKeyframesTab` (global) — Keyframes sub-tab rendering |
| `rock_band_general_helper_vkr/ui_workflow.lua` | `DrawGeneralWorkflowTab` (global) — General > Workflow sub-tab rendering |
| `rock_band_general_helper_vkr/ui.lua` | `TrackCombo` (global override supporting `sel_idx=-1`), `Loop`, `r.defer(Loop)` |

**Local-only functions:**
- `settings.lua`: `SerializeSettings`, `DeserializeSettings`
- `venue.lua`: `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats`
- `venue_awareness.lua`: `INST_TRACK_NAMES`, `ParsePrcEvent`
- `venue_camera_priority.lua`: `KEYS_EXCEPTION`, `BareName`
- `venue_themes.lua`: `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme`
- `venue_camera.lua`: `WeightedPickInstrument`; camera constants `CAM_DIRECTED_COOLDOWN`, `DIRECTED_MIN_COUNT`, `DIRECTED_MAX_COUNT`, `INST_WEIGHTS`, `INST_ORDER`, `IDLE_WEIGHT`
- `venue_sprites.lua`: `_sprite_cache`, `_sprite_dirs_found`, `NormalizeSpriteKey`, `_try_load_from_dir`, `FindAndLoadSprite`, `_CAT_FOLDER`, `POSTPROC_SPRITE_NAMES`; `SPRITE_COLS`, `SPRITE_ROWS`, `SPRITE_FRAME_RATE`, `SPRITE_DISPLAY_W`, `SPRITE_DISPLAY_H`
- `venue_lighting.lua`: `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, `LIGHTING_INTERVAL_16THS`, `LIGHTING_JITTER`, `KEYFRAME_MIN_BEATS`, `KEYFRAME_MAX_BEATS`, `SnapPpqToNearestBeat`, `BlendPpq`, `EmitBlendDuplicates`, `ResolveThemeSection`, `EmitThemeSection` (`IsBlendAnchor` is global — three files read it)
- `actions_venue_validate.lua`: `NEAR_FIRST_BEATS`, `NearestIndex`
- `actions_venue_validate_camera.lua`: `NEAR_STACK_QN`, `UNCOVERED_LIST_MAX`, `COOP_DUO_SET`
- `actions_venue_sing_along.lua`: `RB3_VOCAL_MIN`, `RB3_VOCAL_MAX`, `RB3_PHRASE_PITCH` (module-level locals), `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans`
- `actions_venue_events.lua`: `_round_ppq`, `_is_crowd`, `_bare_form`, `_letter_form`, `_family_span`, `_spot_conflict`, `_require_take`, `_insert`, `_refuse`; `BOOKEND_EVENTS` (module-level local)
- `workflow.lua`: `FindBraceGroups`, `StripBraceGroups`
- `ui_venue_events.lua`: `_draw_prc_row`, `_draw_plain_row`
- `metadata_genres_lookup.lua`: `PairKey`, `BuildCaches`, `_family_cache`, `_by_key`, `_reverse`
- `ui_metadata_genre.lua`: `DimWrapped`, `ClampIdx`, `DrawSubgenreDoc`, `DrawForward`, `DrawReverse`
- `actions.lua`: `CountInBeatSlots`
- `actions_stem_import.lua`: `AUDIO_EXTS`, `KIT_EXCLUDE`, `STEM_RULES` (module-level locals), `HasAll`, `HasAny`, `Shortest`, `PickForRule`, `PickStemFolder`, `ListFolderFiles`, `InsertStemItem`
- `actions_tempomap.lua`: `BPM_MIN`, `BPM_MAX` (module-level locals)
- `actions_drums.lua`: `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport`
- `actions_drums_2x.lua`: `TRACK_2X`, `TRACK_1X`, `MARK_2X`, `KICK`, `MAX_SNAP_QN`, `AMBIGUITY_RATIO`, `UNMATCHED_LIST_MAX`, `SCAN_SPAN`, `SIXTEENTH_QN`, `EIGHTH_QN`, `MAX_EIGHTH_RUN`, `QN_EPS`, `BEAT_EPS`, `REVIEW_LIST_MAX` (module-level locals); `MBTAtQN`, `MIDITakesOn`, `NotesAtPitch`, `DescribeGap`, `MatchMarkers`, `MakeBarDownbeatTest`, `TightestGap`, `TrimRunEdges`, `IsDoubleBassLine`, `PickAlternating`
- `actions_keys.lua`: `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord`
- `actions_keys_guides.lua`: `PkEventLabel`, `ParseTabToRaws`
- `actions_guitar.lua`: `ReadGuitarMIDI`, `GroupIntoEvents`, `IsIllegalGO`, `AssignGems`, `BuildPreviewReport`, `BuildOutNotes`, `ClearGuitarGems`, `PoolByWidth`, `WIDTH_TO_SPREAD`, `MAX_CONFLICT_SHAPES` (module-level locals), `shape_key`, `sort_by_pitch`, `AssignByConflict`
- `actions_guitar_guide.lua`: `AssignGemsForGuide`
- `actions_difficulty_shared.lua`: `ChartsAreIdentical`
- `actions_difficulty.lua`: `ADJACENT_HIGHER` (module-level local); `EventLabel`, `ReadPKNotes`, `GroupIntoEvents`, `GetBeatDurAt`, `QNAt`, `CountNotes`, `CheckChordCount`, `CheckChordSpan`, `CheckIntervalJumps`, `CheckSpacing`, `CheckLaneShifts`, `CheckNotesAboveExpert`, `BuildReport`, `RunPKValidation`
- `actions_difficulty_5k.lua`: `ADJACENT_HIGHER`, `PK_LANE_SHIFT_PITCHES`, `PK_PLAYABLE_LO`, `PK_PLAYABLE_HI`, `PK_REDUCE_TOLERANCE_QN` (module-level locals); `ReadK5Notes`, `GroupK5Chords`, `GetK5BeatDur`, `QNAt`, `CountNotes`, `K5Label`, `ReadProKeysEvents`, `FindNearbyPKEvent`, `CheckK5ChordCount`, `CheckK5Spacing`, `CheckK5NoteLength`, `CheckK5SustainGaps`, `CheckK5SustainLength`, `RunK5Checks`
- `actions_difficulty_gtrbass.lua`: `DIFF_NAMES`, `GEM_NAMES`, `INSTRUMENTS`, `ADJACENT_HIGHER` (module-level locals); `ReadGBNotes`, `GroupGBChords`, `QNAt`, `CountNotes`, `GBGemName`, `GBLabel`, `CheckGBChordCount`, `CheckGBChordSpan`, `CheckGBNoteLength`, `CheckGBOverlap`, `CheckGBSustainGaps`, `CheckGBSpacingAdvisory`, `CheckGBUpperColors`, `CheckGBForceHopo`, `CheckGBTrillVelocity`, `RunGBChecks`

The Keys and Guitar/Bass checks return `DiffIssue` records (`{ s, pitches, msg, ... }`),
not strings, and `Collect*Checks` returns them as categories `{ name, rule, advisory?,
issues }`. `name` is the heading Validate prints; `rule` is a stable id for counting.
Validate formats them through `BuildDiffCheckReport`, so its text is unchanged. The rule
tables are global so that Validate, the planned Generate planners and
`dev/calibration/run_difficulty_probe_vkr.lua` all read one copy. `CheckDifficultyProgression` (every instrument's Validate) counts a tier that keeps every note but holds some sustains shorter as reduced: it prints "only sustain lengths differ (N sustains shorter)" instead of NOT REDUCED, and counts no issue; `opts.advisory` reports both findings without counting them. Pro Keys' checks still
build strings, which `CollectPKChecks` wraps into records (only its spacing check sets
`rec.advisory` per line); Drums still returns strings.
- `actions_difficulty_drums.lua`: `DRUMS_RANGE`, `DIFF_NAMES`, `GEM_NAMES`, `DIFF_BY_MIX_IDX`, `ADJACENT_HIGHER`, `GRACE`, `EPS_QN`, `ROLL_HARD_16TH_BPM`, `ROLL_MEDIUM_MAX_QN`, `ROLL_EASY_QUARTER_BPM`, `GENERAL_HARD_8TH_BPM`, `GENERAL_MEDIUM_8TH_BPM`, `KICK_GRID_BPM`, `KICK_PER_MEASURE_BPM`, `MIN_RUN_LEN`, `DRUMS_HINTS` (module-level locals); `CountNotes`, `GetDrumsBeatDur`, `QNAt`, `GetMeasureAt`, `ReadDrumsNotes`, `GroupDrumsHits`, `DrumGemName`, `DrumLabel`, `CheckDrumsMaxChord`, `CheckDrumsKickPairing`, `CheckDrumsYellowBlueInterleave`, `CheckDrumsKickGrid`, `CheckDrumsKickPerMeasure`, `CheckDrumsOnBeatCrashKick`, `CheckDrumsDoubleCrash`, `CheckDrumsFillKicks`, `CheckDrumsRollGrid`, `CheckDrumsRollEvenCount`, `RollAvgGapQN`, `CheckDrumsRollDensity`, `CheckDrumsGeneralDensity`, `CheckDrumsOutOfRange`, `CheckDrumsRollVelocity`, `CheckDrumsKickCountVsHigher`, `CheckDrumsDiscoUnflip`, `ScanDiscoFlipStatus`, `DrumsAuthoringHints`, `BuildDrumsReport`, `RunDrumsChecks`

Beat-fraction rules in all three difficulty files (spacing, sustain gaps, note length)
are measured in quarter notes via `TimeMap2_timeToQN`, never as seconds against
one sampled BPM — with a fluctuating tempo map the seconds-length of a 1/4 note
varies inside the gap, so even grid-quantized notes fail by a few ms otherwise.
Minimum-gap rules get a 5% grace (`GRACE`) for hand-placed notes; classification
thresholds (is-sustained, sustain gray zone) use a small `EPS_QN` epsilon instead.
`actions_difficulty_gtrbass.lua` reuses `SustainThresholds` (global, defined in
`actions_guitar_validate.lua`, loaded earlier) for its Expert/Hard note-length
and sustain-gap thresholds instead of re-deriving them.
- `actions_midi_replace.lua`: `BuildPatternLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake`, `ResolvePatternScope`, `ScanPatternMatches`, `GoToPatternMatch`
- `actions_midi_length.lua`: `NoteLenPPQ`, `AdjustAllNoteLengths`, `AdjustSustainGaps`; `SUSTAIN_MIN_DENOM`, `FLOOR_DENOM`, `SEARCH_WINDOW_32NDS` (module-level locals)
- `ui.lua`: `Loop`

**Load order:**
```
lib/reaper_imgui_helpers.lua   → Tooltip, SliderTooltip, SectionHeader, GetTrackList,
                                  FormatTime, GetTimeSelection  (TrackCombo also loaded
                                  but shadowed locally in ui.lua for -1 support)
lib/reaper_dsp.lua             → (loaded; not currently used by general helper)
lib/reaper_midi_helpers.lua    → FindFirstMIDIItem, InsertNotes, ClearNotesAtPitchesInRange, …
lib/reaper_guitar_theory.lua   → GuitarClassifyChordType, GuitarSuggestRBMapping (consulted by
                                  actions_guitar.lua's BuildShapeGemMap, by pitch class, for
                                  chord-quality mapping); GUITAR_TAB_OPEN (tuning table, also used by
                                  actions_guitar_guide.lua's tab parsers)
lib/reaper_script_links.lua    → SCRIPT_LINK_GROUPS, ScriptLinkBasename, IsRunningScriptLink,
                                  FilterScriptLinkGroups, LaunchReaScript, DrawGeneralLinksTab
                                  (General > Other tools sub-tab; shared with the vocal helper)
defaults.lua                   → S, VENUE_VALID, TIPS, constants
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → FindTrackByName, FindNamedTrackMIDI, GetTakePPQPerQN,
                                  SetDefaultTempoTracks, SetDefaultMIDITracks,
                                  SetDefaultDifficultyTracks, GetTempoContextBefore,
                                  GetMeasureStartTime, GetAudioItems, MakeProjectPoll
venue.lua                      → ListVenueEvents, GetVenueEventsForPreview,
                                  IsBlendAnchor, AnnotateVenueBlends
venue_awareness.lua            → GetMutedInstruments, GetCoopRequiredInstruments,
                                  GetDirectedRequiredInstruments, FilterPool,
                                  ReadEventSections, ListEventSections, FindMusicStartTime,
                                  INST_LETTER_NAMES
venue_camera_priority.lua      → CAM_PRIORITY_TIERS, CAM_PRIORITY, CAM_GENERIC_FALLBACK,
                                  CameraShotPriority, CameraShotFitsBand,
                                  PickPriorityCameraEvent
section_events.lua             → SECTION_EVENT_GROUPS, SECTION_EVENT_BASE (data only)
venue_themes.lua               → ThemeDisplayLabel, LoadVenueThemes, GetSectionPreset,
                                  GetThemeCameraInterval, BuildLightingPool, BuildPostprocPool
venue_camera.lua               → COOP_POOL, COOP_LABELS, COOP_DISPLAY_GROUPS,
                                  DIRECTED_POOL, DIRECTED_DISPLAY, DIRECTED_BRE_NAMES,
                                  DIRECTED_LABELS, DIRECTED_TIPS, PickRandom, JitteredInterval,
                                  CategorizeCoopPool, WeightedPickCoopEvent, FindCompanion,
                                  ComputeIdleState, GenerateCameraEvents,
                                  ResolveUserCamInterval; camera globals
                                  (CAM_INTERVAL_16THS etc.)
venue_sprites.lua              → LoadVenueSprite, DrawVenueTooltipSprite, BeginVenueTooltip,
                                  EndVenueTooltip, VenueEventTooltip, RawVenueEventText;
                                  VENUE_SPRITE_ROOT, VENUE_SPRITE_SELF_ROOT,
                                  DIRECTED_SPRITE_NAMES, POSTPROC_SPRITE_NAMES (module globals)
venue_lighting.lua             → MANUAL_LIGHTING_SET, LIGHTING_OFFSET_16THS, INST_KF_MODES,
                                  KF_ALIGN_LABELS, FindNextMeasureStartPpq,
                                  CollectInstNotePositions, SnapPpqToHalfBeat,
                                  GenerateKeyframesForSpan, GenerateLightingEvents,
                                  GenerateThemedSectionEvents
venue_generator.lua            → GenerateVenueEvents, DeleteTextEventsInRange, ClearVenueTextEventsInRange,
                                  ClearVenueNonCameraEventsInRange, ClearVenueExceptLPInRange,
                                  ClearVenueKeyframesInRange, FindActiveVenuePresetsBefore
workflow.lua                   → ParseWorkflowContent, ParseWorkflowFile,
                                  LoadWorkflowFiles, EscapeWF, UnescapeWF
actions_workflow.lua           → CompositeKey, PruneToWorkflowEntries, SaveWorkflowState,
                                  LoadWorkflowState, SelectWorkflowFile, ToggleWorkflowItem,
                                  ComputeWorkflowStats
tempomap.lua                   → ComputeTempoRMSContour, DetectOnsets, EstimateBPM,
                                  GuessTimeSig, GetSourcesForRange, FitBeatGrid,
                                  RmsToOnsetFlux, FindLocalPeak
actions.lua                    → AlignAudioTracks, AlignAllAudio, AlignCountIn, CreateSongFadeOut
actions_stem_import.lua        → StemImportPlan, ImportStems
actions_tempomap.lua           → ShowTempoContext, EstimateInitialBPM, AutoTuneThreshold,
                                  ClearGeneratedTempoMarkers, GenerateTempoMap
actions_drums.lua              → ConvertDrums
actions_drums_2x.lua           → DoubleBassPlan, MarkDoubleBassKicks,
                                  Remove2XKicks
actions_keys.lua               → SplitHands, ConvertProKeys, ConvertKeys5
actions_keys_guides.lua        → ProKeysTabGuide, VocalTabGuide
actions_guitar.lua             → ConvertGuitar, ValidateGuitar, GetBPMAt
actions_guitar_guide.lua       → ParseTabHorizontal, ParseTabVertical, ReformatVerticalTab, GuitarTabGuide
actions_guitar_validate.lua    → SustainThresholds, ReadRBGuitarNotes, RunValidation
actions_midi_align.lua         → AlignMIDI, ResizeAllMIDI
actions_midi_replace.lua       → GetPatternPitchRange, SetSearchPattern, SetReplacePattern,
                                  FillRange, DoMIDIPatternReplace, GoPrevPatternMatch,
                                  GoNextPatternMatch, ListPatternMatches
actions_midi_length.lua        → AdjustMidiNoteLengths
actions_difficulty_shared.lua  → CheckDifficultyProgression, CompressChordOffsets,
                                  DiffIssue, BuildDiffCheckReport, DiffReleaseGapQN,
                                  DiffReleaseGapName, DiffQNLabel, DIFF_RELEASE_GAP_* tables
actions_difficulty.lua         → CopyProKeysDiff, ValidateProKeysDiff, ValidateAllProKeys,
                                  CollectPKChecks, ReadPKTierEvents, PK_MAX_CHORD, PK_MAX_SPAN
actions_difficulty_5k.lua      → ValidateKeys5Diff, ValidateAllKeys5, CopyKeys5Diff,
                                  ReadK5TierEvents, CollectK5Checks, K5_* rule tables
actions_difficulty_gtrbass.lua → CopyGtrBassDiff, ValidateGtrBassDiff, ValidateAllGtrBass,
                                  ReadGBTierEvents, CollectGBChecks, GB_* rule tables
actions_difficulty_drums.lua   → CopyDrumsDiff, ValidateDrumsDiff, ValidateAllDrums
difficulty_generate_params.lua → GEN5_PARAMS, GEN5_* limits, Gen5BeatClass, Gen5MinGapQN,
                                  Gen5MinSustainQN, Gen5ReleaseGapQN (pure; first)
difficulty_generate_retime.lua → Gen5RetimeDenseRuns (pure; Hard's fast-run rewrite,
                                  called by Gen5SelectOnsets - load before it)
difficulty_generate_colors.lua → Gen5ReduceChordSize, Gen5NarrowSpan, Gen5ShiftSegments,
                                  Gen5ShiftBars, Gen5ClampOrShiftBars (pure; before the planner)
difficulty_generate_rhythm.lua → Gen5SelectOnsets, Gen5AndPhrases (pure; which onsets every planner keeps)
difficulty_generate_5lane.lua  → Gen5PlanTier (pure; Guitar/Bass/Keys)
difficulty_generate_prokeys.lua → GenPKPlanTier, GenPKReduceChord, GenPKBestWindow,
                                  GEN_PK_WINDOWS (pure; Pro Keys)
difficulty_generate_hopo.lua   → Gen5IsAutoHopo, Gen5MarkHopos, Gen5ForceHopoSpans,
                                  GEN5_HOPO_THRESHOLD_TICKS (pure; Hard force-HOPO markers)
actions_difficulty_generate.lua → GenerateDifficulties, GenInstrumentByKey,
                                  GEN_INSTRUMENTS, GEN_ALL_KEY
overdrive_read.lua             → OD_* constants, OdBuildModel, Od* span/bar helpers
                                  (needs difficulty_read.lua's FindTrackExact/ReadGemEvents
                                  at call time)
overdrive_interest.lua         → OdBarInterest, OdBandTogetherness
actions_overdrive_fills.lua    → OD_FILL_PACINGS, OdAutoFillPacing, OdPlanFills,
                                  OdActivationQN, OdSplitEarlyFills
actions_overdrive_vocals.lua   → OdPlanVocals
actions_overdrive.lua          → OdUnisonGroups, OdPlanInstruments, OdJobs,
                                  OdFillAvoidSpans, OdVocalNoGo, OdDrumPhrasesForActivation,
                                  GenerateOverdrive
actions_overdrive_validate.lua → OdValidateModel, OdBuildOverview, ValidateOverdrive
actions_venue_manual.lua       → InsertVenueEventAtPlayhead, AdvanceCameraPacing,
                                  GenerateManualKeyframes, RemoveVenueEventsByType,
                                  FindManualLightingAtPpq, FindNextVocalPhraseStartPpq,
                                  ResolveBlendSource, BlendVenuePresetAtPlayhead,
                                  NO_LIGHTING_AT_PLAYHEAD_MSG
actions_venue_events.lua       → FindEventsTake, ScanEventsTextEvents, NextSectionEvent,
                                  ValidatePlainInsert, InsertEventsEvent, AddSectionEvent,
                                  ClearAllEventsTexts, InsertEventsBookends
actions_venue_keyframes.lua    → RegenerateVenueKeyframes
actions_venue_sing_along.lua   → GenerateSingAlong
actions_venue_subtracks.lua    → VENUE_SUBTRACKS, CategorizeVenueEvent, FindOrCreateSubtrack,
                                  EnsureMatchingItem, CopyVenueEvents, CopyVenueToSubtracks,
                                  CopyAllSubtracksToMain, CopySelectedSubtrackTo,
                                  CopySelectedSubtrackFrom
actions_venue_validate.lua     → ValidateVenueLightingBlends, ValidateVenueLighting
actions_venue_validate_camera.lua
                               → BuildBandLineups, ValidateVenueCameraStacks,
                                  ValidateVenueCamera
ui_common.lua                  → TrackCombo, MidiEditorTrackWarning,
                                 DrawStatusResultPanel
ui_keys.lua                    → DrawKeysTab
ui_difficulty_generate.lua     → DrawDifficultyGenerateTab
ui_difficulty.lua              → DrawDifficultyTab
ui_overdrive.lua               → DrawOverdriveTab (reads OD_FILL_PACINGS at load time)
ui_midi_pattern.lua            → DrawMIDIPatternTab, ResetMIDIPatternState
ui_midi.lua                    → DrawTabInputTab, DrawMIDITab
ui_venue.lua                   → DrawVenueTab, RenderCamPacingRow, RenderKeyframeAlignCombo
ui_venue_section_gen.lua       → DrawVenueSectionGenTab
ui_venue_manual.lua            → DrawVenueManualTab
ui_venue_events.lua            → DrawVenueEventsTab
ui_venue_preview.lua           → DrawVenuePreviewTab
ui_venue_players.lua           → DrawActivePlayersRow
ui_venue_keyframes.lua         → DrawVenueKeyframesTab
ui_workflow.lua                → DrawGeneralWorkflowTab
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultTempoTracks(),
                                  SetDefaultMIDITracks(), SetDefaultDifficultyTracks()
```

**`SCRIPT_MDIR` global.** The entry point sets `SCRIPT_MDIR = _mdir` (global) so dofile'd modules can access the module folder path for filesystem operations. The `local _mdir` variable is not accessible from dofile'd modules. **`SCRIPT_DIR` global.** The entry point also sets `SCRIPT_DIR = _dir` (repo root) for accessing shared resources under `resources/` (e.g. `resources/themes/`, `resources/img/spritesheets/`).

**Polling convention for continuous MIDI reads.** UI draw code that reads project MIDI every frame is forbidden — gate the read behind `MakeProjectPoll(min_secs, fallback_secs)` (helpers.lua): it fires when `GetProjectStateChangeCount` changed (subject to `min_secs`) or `fallback_secs` elapsed (safety net for count collisions across project switches). Heavy multi-track scans use `min_secs = 1.0` (protects against per-frame count churn while dragging notes in a MIDI editor). Only pure-Lua lookups over the cached data may run per frame; lookups that follow the *play* position during playback should recompute at a ~0.5 s cadence, while stopped-cursor moves recompute immediately (the lookup is cheap; a debounce would only add lag). Cached take pointers must be `ValidatePtr2`-checked before use. Note: `GetProjectStateChangeCount` only increments when an **undo point** is registered — bare API edits without an undo block are invisible to the count gate (they are still caught by the `fallback_secs` rescan). All helper edit paths create undo points (the mandatory undo-block pattern), as do user edits in REAPER, so in practice only undo-less test/script edits need care. Current adopters: `ui_venue_players.lua`, `ui_venue_events.lua`; `ui_venue_preview.lua` keeps its own immediate-on-change + self-pause variant; the vocal helper's tuner (audio, 100 ms + playhead gate) is intentionally separate.

**Second entry point: `rock_band_preview_vkr.lua` (repo root).** Standalone Venue Preview window. It has no module folder of its own — it dofiles a subset of this helper's modules: `lib/reaper_imgui_helpers.lua`, then `defaults.lua`, `settings.lua`, `helpers.lua`, `venue.lua`, `venue_awareness.lua`, `venue_camera_priority.lua`, `venue_sprites.lua`, `ui_venue_preview.lua`, `ui_venue_players.lua`, and runs its own minimal `Loop` calling `DrawVenuePreviewTab()` + `DrawActivePlayersRow()`. Consequences when editing those files:
- They must keep working without the rest of the general helper loaded — do not add load-time or call-time dependencies (from the preview code path) on modules outside this subset. `settings.lua` guards its `SaveSectionConfigs`/`LoadSectionConfigs` calls (`if X then X() end`) for this reason.
- `venue_camera.lua` is **not** in the subset, so nothing on the preview path may read `COOP_POOL`, `COOP_LABELS`, `DIRECTED_TIPS` or anything else it defines. This is why the shot-priority tables live in their own `venue_camera_priority.lua` rather than beside the pools — the preview needs them and cannot afford to pull in the generator.
- `venue_sprites.lua` reads `SCRIPT_DIR` at dofile time; both entry points set it before loading.
- The standalone calls `LoadSettings()` at startup and on project switch, but never `SaveSettings()` (saving stays in the general helper's General tab).
- **A fix to any file in that subset changes this window too, so it needs its own `@version` bump and its own `@about` entry** in the same task as the general helper's — otherwise its version silently stops describing the code it runs. See `CLAUDE.md` → "Bumping a helper means checking its standalones".

**Third entry point: `rock_band_midi_pattern_vkr.lua` (repo root).** Standalone MIDI Pattern window. No module folder of its own either — it dofiles `lib/reaper_imgui_helpers.lua`, `lib/reaper_midi_helpers.lua`, then `defaults.lua`, `helpers.lua`, `actions_midi_replace.lua`, `ui_common.lua`, `ui_midi_pattern.lua`, and runs its own minimal `Loop`: a **Refresh tracks** button (the general helper keeps that button in General > Actions, which this window has no equivalent of), then `DrawMIDIPatternTab()` + `DrawStatusResultPanel(true)`. Consequences when editing those files:
- The subset must keep working without the rest of the general helper loaded. In particular `ui_midi_pattern.lua` may not grow a dependency on `ui_midi.lua`, `settings.lua` or any venue/difficulty module.
- **`ui.lua` is deliberately not in the list and must never be added**: its last line is a bare `r.defer(Loop)`, which would spawn the full helper window. That is the whole reason `TrackCombo` and the status/result panel were moved out into `ui_common.lua` — the same split the vocal helper made for its standalone tuner.
- It sets neither `SCRIPT_DIR` nor `SCRIPT_MDIR` — nothing in this subset reads them (`venue_sprites.lua` is what forces the preview standalone to set them).
- Unlike the other two standalones it calls **neither `LoadSettings()` nor `SaveSettings()`**: the Pattern sub-tab has never persisted anything (its `S.mr_*` fields are session-only and `settings.lua` has no key for them), and no `SetDefault*Tracks` function assigns `mr_midi_src_idx`. If a Pattern setting is ever made persistent, this window needs `settings.lua` added and `LoadSettings()` called at startup + on project switch.
- Both entry points call `ResetMIDIPatternState()` on project switch. The captured Search/Replace patterns are take-relative PPQ offsets whose labels name the previous project's measures, so carrying them over would silently target the wrong material.
- **A fix to any file in that subset changes this window too, so it needs its own `@version` bump and its own `@about` entry** in the same task as the general helper's — otherwise its version silently stops describing the code it runs. Nearly everything this window draws is shared, so it is the standalone most often affected. See `CLAUDE.md` → "Bumping a helper means checking its standalones".

**`TrackCombo` override.** The general helper uses `sel_idx = -1` to mean "no track configured" for drum source dropdowns. The lib's `TrackCombo` always expects a non-negative index. **`ui_common.lua`** defines `TrackCombo` as a **global** — overriding the lib version for all modules — that adds a `(none)` selectable entry and handles -1. `ui_keys.lua`, `ui_midi.lua`, `ui_midi_pattern.lua` and `ui_venue.lua` all call `TrackCombo` and rely on this global override, so `ui_common.lua` must be dofile'd after `lib/reaper_imgui_helpers.lua` and before any of them. (It lived in `ui.lua` until v0.9.49; it moved because the standalone MIDI Pattern window needs it and cannot load `ui.lua`.)

### Save / Load

Section `RBHelperVKR`, key `settings_v1`. Auto-loads on script open.

**Saved:** all tempo map sliders — primary source (`tm_rms_threshold`, `tm_rms_window_ms`, `tm_search_window_ms`, `tm_drift_threshold_ms`, `tm_bpm_failsafe`, `tm_first_measure`, `tm_timesig_num`, `tm_override_failsafe`), fallback source (`tm_fb_rms_threshold`, `tm_fb_rms_window_ms`, `tm_fb_use_flux`), auto-tune (`tm_autotune_density`), the Difficulty tab's Guitar/Bass instrument radio (`diff_gb_instrument`), the Keys sub-tab's "Reduce using Pro Keys" checkbox (`diff_5k_pk_reduce`), and the Workflow sub-tab's selected template name (`workflow_file_name`) and "Show completion timestamp" checkbox (`workflow_show_ts`), and every Overdrive tab setting (`od_group`, the three include checkboxes, `od_beats_per_phrase`, `od_unison_share`, `od_keepout_start`, `od_together`, `od_vocal_overlap`, `od_keepout_od`, `od_keepout_unison`, `od_fill_pacing`, `od_fill_sections`, `od_fill_skip_early`, `od_fill_keepout_end`, `od_vocal_every`). `od_pending` and `od_overview` are session-only and cleared on project switch.
**Not saved:** track indices — positional, brittle. `SetDefaultTempoTracks` re-detects tempo map tracks by name; `SetDefaultMIDITracks` re-detects PART DRUMS and PART GUITAR target tracks by name; `SetDefaultDifficultyTracks` re-detects all Difficulty-tab tracks (Pro Keys, Keys, Guitar/Bass, Drums) by name. All only assign fields that are still -1 (do not override saved state).

**Own ExtState keys, guarded through `SaveSettings`/`LoadSettings`:** the Section gen sub-tab's per-section configs (`vsec_v1`, `actions_venue_section.lua`) and the Workflow sub-tab's checklist state (`workflow_v1`, `actions_workflow.lua`) each live under their own key rather than the `settings_v1` scalar blob — both hold a variable-length, dynamically-keyed collection rather than a small fixed set of fields.

---

## Difficulty suggester calibration

The Metadata > Difficulty tab ships fitted coefficients, and they came from somewhere: a
calibration harness of real, tracked code in [`dev/calibration/`](../dev/calibration/) —
many rounds of model fitting against a corpus of officially-ranked songs, producing one
selected model per instrument. The round count is deliberately not repeated here; it has
gone stale twice, and `protocol.lua`'s last declared round is the authority.
[`dev/calibration/README.md`](../dev/calibration/README.md)
is the summary: results, file map, how to run it, the locked evaluation protocol, and the
rules a new session must not break. Read it before touching anything in that folder.

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
3. **Camera cuts (coop)** — placed at jittered intervals from one interval after the music-start anchor onward, up to the camera end bound (the **final anchor** when one is resolved, else the range end — see "Song end and the final anchor" below).
4. **Camera cuts (directed)** — 1–4 cuts placed at random positions in the middle 80% of the camera end bound, each followed by a 2× cooldown before the next coop cut.
5. **Final coop cut** — placed 8 sixteenths before the camera end bound.
6. **Lighting changes** — placed from 32 sixteenths in, at jittered intervals, up to the range end. Each picks from the combined manual + auto pool.
7. **Control keyframes (`[first]`/`[next]`)** — generated only for manual lighting events. `[first]` on the lighting event's own tick, then `[next]` every 1–4 beats until the next lighting change (see "Keyframe placement rule" above).
8. **Bookend: `[lighting (blackout_spot)]`** — placed at the final anchor when one is resolved, else 32 sixteenths (2 measures) before the range end.

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

### Song end and the final anchor

The VENUE MIDI item's own length is not authoritative for the song end — the `[end]`
EVENTS-track marker is. `GenerateVenueEvents` clamps `range_end_sec` to `[end]` when it falls
inside the item; nothing is generated at or after it, regardless of how much longer the item
runs. No `[end]` marker (or one outside the item) falls back to the item's own length, exactly
as before this existed, with a `"Didn't find [end] event, used MIDI length as end."` note in
the result panel. When the item runs meaningfully longer than a found `[end]`, the result panel
adds a non-blocking trim suggestion instead (no in-game effect either way).

Additionally, when `[music_end]` sits within 10 measures of `[end]`, it becomes the **final
anchor**: the outro `[lighting (blackout_spot)]` bookend and the last scripted coop camera cut
both target it instead of the literal range end. `[end]` triggers the game's own forced camera
cut, so ending our own generation right on top of it would double up as a jump cut. No
`[music_end]`, or one more than 10 measures before `[end]`, leaves the final anchor unresolved
and every generation step falls back to the literal range end. Full detail (including the
measure-counting method) is in `CLAUDE_venue_theme_generation.md`'s "Song end and the final
anchor" section.

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

`song_end_t` passed to `ReadEventSections` defaults to the VENUE item end (from `FindNamedTrackMIDI('VENUE')`), falling back to `r.GetProjectLength(0)`.

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

## Feature: Overdrive

Generates and validates overdrive for the whole song. Sources: the RBN/C3 "Overdrive and Big Rock Endings" page, plus the drum and vocal authoring pages for fills and vocal phrases. Defaults were checked against reference charts: 581 official RB3 DLC songs and 147 RBN songs, aggregate figures only.

### Notes and tracks

| What | Note | Tracks |
|---|---|---|
| Overdrive / unison phrase | 116 | PART DRUMS, PART DRUMS_2X, PART BASS, PART GUITAR, PART KEYS, PART REAL_KEYS_X, PART VOCALS, HARM1 |
| Drum fill | 120-124, all five lanes, one span | PART DRUMS + PART DRUMS_2X |
| Big Rock Ending lanes | 120-124 from `[coda]` on (Pro Keys: 120 only) | read only — never generated, never cleared |
| Vocal phrase | 105 | PART VOCALS, HARM1 |

The groups in `OD_INST_GROUPS` write their tracks together: PART DRUMS with PART DRUMS_2X, and PART KEYS with PART REAL_KEYS_X. The game needs the keys pair to match, and 2X is the same chart as PART DRUMS. PART VOCALS and HARM1 are written together too: Rock Band 3 has a visual bug in harmonies if the parts differ, so only vocal phrase markers that are identical on both parts are used.

### Rules the generator enforces

- About one phrase per **40 counted beats** of the part's *playing* bars. Counted beats are not quarter notes: 7/8 counts 3 and 6/8 counts 2 (`OdCountedBeats`). A phrase is one measure long.
- Unisons are about **half** the median phrase count. A unison is an identical span on every instrument. A subset without keys is allowed when keys is not playing; never fewer than 3 instruments (or all of them, if there are only 2).
- No two instruments share a bar outside a unison, and phrases never overlap.
- Nothing in the last **8** measures, and no unison in the last **12**. Both count back from `[coda]` when there is one, otherwise from `[end]`. When there is no `[end]` either, the last note is used and Validate says the end checks are approximate.
- **Start keep-out** (`od_keepout_start`, default **5**): no phrase or unison until the band has played that many measures, counted from the first measure *any* present instrument plays. Joining an existing unison ignores it. This is not a doc rule. Official charts put the first instrument phrase a median of 5 measures into the playing (p10 2, p90 9; song-level first OD at median measure 8), and put it in the very first playing measure in only 2% (RB3 DLC) to 14% (RBN) of songs. Without the rule the generator did that in 27%. The singles' spacing is measured from the keep-out, so the part's phrases are spread over the bars they can actually use. Validate reports the lead-in as a summary line, not a warning: at the default, half the official charts would trip it.
- Vocals are never part of a unison. Whether instrument phrases may also sit *under* vocal overdrive is the **Over vocal OD** setting (`od_vocal_overlap`, `OdVocalNoGo`):
  - **Overlap anywhere** (default): what official charts do. 24% of their instrument phrases overlap vocal OD, in 59 of 60 reference songs, and the song build tool accepted it in two deliberate tests. It never makes vocals part of a unison: vocal OD follows the phrase markers, and 0 of 483 official vocal phrases share a unison's span.
  - **Avoid its first measure:** keep the measure the vocal phrase starts in clear; the rest of a long phrase may be overlapped. 96% of vocal OD spans more than one measure, and 62% of official overlaps fall only in the later measures.
  - **Avoid vocal overdrive:** v0.9.60's original behaviour. Every measure a vocal phrase touches is off-limits.
- **Band playing together** (`od_together`, default on, All only), for unisons. Across 60 reference songs, official unisons sit on the **last measure before a section** 5.8× as often as chance (20.6% of unisons vs 3.6% of bars). That's the doc's "pickup, build-up to a chorus". They also sit where guitar and bass share rhythm and contour (`OdBandTogetherness`, lift 1.14; none on guitar-only phrases). The fill grid ends fills on exactly that pre-section measure, and fills are planned first, so the best unison spot was always taken. With the option on:
  - a unison may take the measure before a section when the only thing in the way is the fill leading into it, and that fill gives way (`plan.yielded`, reported);
  - togetherness is added to the unison score, at weight 2 per member.

  Generated unisons on an official unison measure rise from 4.4% to 13.1%, and within one measure from 14.0% to 22.7%. About 1 fill in 10 gives way, which leaves fill counts slightly *below* the official charts rather than above.

  Don't chase much more. Charters aren't consistent with themselves: a chorus with a unison has one in the same spot of the next chorus only 19% of the time. The remaining signals are weak: density rising into a measure (lift 1.21) or dropping (1.35), and section type (riff/interlude 1.44, breakdown/build about 1.7 but rare).
- Drums and unisons stay out of fill bars and never start on a fill's closing crash. A drum phrase in the bar before a fill ends a 32nd short, so it does not touch the fill (the CARV rule).
- A drum solo (a `[prc_drum_solo...]` section or a 103 span on PART DRUMS) holds at most 4 drum phrases, or 2 when a unison leads straight in. It has no fills.
- **Fill end keep-out** (`od_fill_keepout_end`, default **2**): a fill's crash must land at least that many measures before the drums' last measure with a gem. A fill leading into the final hit has nothing left to deploy overdrive for. Official charts put the last fill a median of 4 measures before the drums end. It lands on the final measure in 1% (RB3 DLC) / 0% (RBN) of songs, and within 2 measures in 25% / 6%.
- Vocal OD is an exact copy of a 105 phrase, one per **5** sung phrases. A phrase is only eligible when HARM1 has a 105 with an identical start and end. When the cadence lands on a mismatch it tries one phrase earlier, then one later, and continues from the phrase chosen. When neither works, the slot is reported with measure and time.

### Order: vocals, then fills, then instruments

Each step fences off the next:

1. **Vocals** go first. They are the least flexible, since they are tied to phrase markers and to HARM1. Under the two "avoid" modes of Over vocal OD, their spans also fence off the instruments.
2. **Fills** go second. They are a grid built from the drum part and the sections, which is the order drum authoring happens in anyway.
3. **Instrument phrases** are placed last, around both.

Fills were originally planned last, and every drum phrase then knocked out one or two fill slots: across 60 reference songs that lost 30% of the fills (1256 generated vs 1755 official). Planned first, the count matches the official charts (1790 vs 1755), and the drum phrases still reach their targets.

One fill step runs after the instruments: **dropping early fills** (`od_fill_skip_early`, on by default). A fill before the drummer can have enough overdrive to activate is never usable. Activation takes two single drum phrases, or one unison, which counts double. `OdActivationQN` finds the end of the arming phrase, and `OdSplitEarlyFills` removes every fill that starts before it. This needs the drum phrases, which is why it can't happen during fill planning. The docs never mention a use for early fills. Official RB3 DLC leaves at least one in 56% of songs (6% of all fills); RBN charts do in 26% (1.6%). So it's an option, and Validate only reports early fills in the summary.

### Where fills end (`OdPlanFills`, "End fills at section changes / crashes")

The grid places a fill every N measures. Within reach of each grid slot:
1. A `[prc_*]` section start moves the fill to it.
2. Otherwise a **drum crash** does, nearest the slot first. A crash is a blue or green *cymbal* on a downbeat (`OdCrashBars`). Pro Drums tom markers 111/112 turn those gems into toms, and yellow is left out because it's the hi-hat.
3. Otherwise the fill stays on the grid.

**Sections come first because of measurement, not preference.** Across 60 reference songs:

| Order | Fills ending where the official fill ends |
|---|---|
| Plain grid | 34% |
| Crashes first, sections as fallback | 61% |
| Sections first, crashes as fallback (shipped) | 76% |

Drummers crash in plenty of places that aren't phrase starts, so a crash inside a phrase pulls fills off correct sections. In the spots where a section start had no crash but its neighbour did, the official fill followed the section 32 times and the crash 10 times.

The crash is still used as a **check**. When a fill follows a section start with no crash of its own, but the neighbouring downbeat has one, the Generate report says the section event may be a measure off. That usually means the event was placed by the vocal line rather than the band. Moving the event moves the fill: the case that prompted this was a final chorus marked one measure short, where the section events followed the singer.

### How phrases are placed (`OdPlanInstruments`)

- **Fresh unisons** only happen when every present instrument is being generated (All). A kept track's phrases are not the generator's to line up with. The unison targets are evenly spaced; each is placed on the bar within reach that has the highest summed interest where all core instruments play.
- **Join mode.** When some tracks are kept (a single part is selected, or **Keep existing** was chosen), their identical spans shared by 2 or more parts count as existing unisons. Generated parts join those unisons, and the rest of the kept tracks' bars are simply occupied.
- **Singles** go into the widest remaining gap first. Gaps are measured in the part's own playing-beat space, so a rest never looks like a gap that needs a phrase. A single may move up to a sixth of the gap from its middle, to a more interesting free measure, but pays a spacing penalty of 0.5 × (distance / reach) against its 0–1 interest, so spacing wins most ties. The first version (a quarter of the gap, penalty 0.15) let a section-start bonus pull a phrase 3 measures off target. It left 6.3% of gaps under 0.6× the song's average gap, where official charts have 3.6%. The current values give 4.0%, with the same official-measure hit rate for singles (13.1% vs 13.6%). For single phrases, interest barely predicts official placement, while even spacing is what the doc asks for.
- **Phrase span.** A phrase runs from the barline to the next barline. When the downbeat is empty it starts on the first gem instead, but only if that gem falls within the first beat; a later start would leave a sub-half-measure phrase.

### What the interest score does not do

`OdBarInterest` ranks bars by eventfulness: chord changes, shape variety and motion entropy, reusing the difficulty scorer's primitives. Density has the lowest weight, so a bar of one repeated power chord loses to a bar with palm-muted single notes threaded between the chords.

Measured against the official charts, **none of the note-content terms predicts where official overdrive goes**. Their lift over an average playing bar is 1.01–1.05, and a generator using the score hits an official OD bar about as often as a random pick inside the same spacing window (about 10% exact, about 30% within ±1 bar). Several weightings made no difference. Official placement is explained by:
- spacing;
- keeping drums out of fill bars (lift 0.07);
- one structural cue: the bar just before a section change (lift 1.39 on guitar), i.e. pickups and build-ups.

So the context term carries the most weight, and the bar before a section outranks the section's own first bar. Do not present the tool as reproducing charter judgment. The `@about` entry says so, and so should any future wording.

### Validation severities

**Errors:** only the rules the docs tie to a bug or a chart that does not work:
- overdrive overlapping a fill;
- a fill inside a drum solo;
- a unison sharing a measure with a fill;
- vocal OD that is not exactly a phrase marker;
- HARM1 ≠ PART VOCALS (a visual bug in harmonies);
- a mismatched mirror pair (KEYS vs REAL_KEYS_X, DRUMS vs DRUMS_2X);
- overdrive in the Big Rock Ending.

**Warnings:** everything else. That includes two rules the docs state firmly but official charts, community RBN charts included, break in 3–8% of fills: a drum phrase ending exactly where a fill starts (CARV) and one starting on a fill's crash. As errors they buried the real problems — the first version reported 177 errors across 60 official songs.

**Summary counts:** instrument phrases under vocal overdrive are counted in the summary rather than listed, because official charts do it about 9 times per song.

### Corpus figures behind the defaults

| Measure | RB3 DLC | RBN |
|---|---|---|
| Quarter-note beats per phrase (over the playing span) | median 43 | median 43 |
| Phrase length | median 1.0 bar | 1.0 bar |
| Phrase starts on a barline | 76–87% | 85–88% |
| First gem offset from the phrase start | median 0 | 0 |
| Unisons as a share of phrases | ~1/3 | ~1/2 |
| Measures from last OD to `[end]` | p10 = 11 | p10 = 11 |
| Measures from last unison to `[end]` | p10 = 23 | p10 = 26 |
| KEYS OD == REAL_KEYS_X OD | 97% | 93% |
| Fill length / ends on a barline | median 4 beats / 93% | 4 beats / 93% |
| Measures between fills | median 4 | median 4 |
| Vocal phrases per vocal OD | 4.6 | 4.8 |
| Vocal OD exactly a 105 phrase | 96% | 95% |
| HARM1 phrase markers identical to PART VOCALS' | 20–40% of songs | — |

No reference song carries PART DRUMS_2X, so mirroring it is a design decision rather than a measured one.

### Authoring tips coverage

A set of drum-fill and overdrive authoring tips, checked against the original plan and the v0.9.60 code:

| Tip | In the plan | Implemented |
|---|---|---|
| A fill every 4 measures; very fast: 2 measures every 8; very slow (< 75–80 BPM): half a measure every 2 | Yes | Yes — `OdAutoFillPacing`, with an override combo. Slow switches at ≤ 75 BPM, the bottom of the tip's range. The fast threshold (170) is our own; no source gives one. Tempo is read at the song's midpoint only |
| End a fill at an important transition (a verse with 2 extra bars → the fill ends at the chorus) | Yes | Yes — a `[prc_*]` start within reach replaces the grid slot and the grid re-anchors. Without a section in reach, a drum crash does. A section start with no crash beside a crash is reported. See "Where fills end" |
| If the band pauses before the next section, end the fill at the start of the pause | No | No |
| Avoid a fill right before a long rest | Yes (8+ measures of rest) | Partly — a slot is skipped only when its landing measure has no drum gems. There is no look-ahead for a long rest |
| No fills in drum solos | Yes | Yes — `[prc_drum_solo…]` sections and 103 spans on PART DRUMS. Validate reports a fill in a solo as an error |
| A fill is a good way to end a long drum rest | No | No — the grid ignores rests, and no fill is placed before the drums first come in |
| (Not in the tips) Fills before overdrive can first be activated are unusable | No | Yes — dropped by default ("Skip fills before overdrive can be activated"); Validate reports them in the summary |
| Start OD / unisons with guitar | Implicitly | Yes — guitar is first in `OD_INST_GROUPS`, so it gets first pick of contested bars for singles. Unison bars are chosen on all parts' summed interest, so order does not affect them |
| Unisons where the whole band plays something interesting together (lead line, breakdown, pickup, build-up to a chorus or solo) | Partly | Mostly — with "Prefer measures where the band plays together": the pickup measure before a section (the fill there gives way), and guitar and bass sharing rhythm and contour, with drums on the same beats. Breakdowns aren't detected, and solo-marker starts don't count as section changes |

### Testing

`dev/tests/general_overdrive.lua` (runner `run_general_overdrive.lua`, launcher button "Overdrive Tests"):
- Most of the suite drives the planners and the validator with **hand-built models** in the `OdBuildModel` shape.
- The last section builds real tracks and runs Generate and Validate end to end, including the check that nothing is written while the replace confirmation is pending.
- That section **skips itself** when the project already has a PART or EVENTS track, so it never touches a real song.

---

## Feature: double-bass detection

**The model, first, because an earlier version of this feature got it wrong.**
`PART DRUMS_2X` is a **complete alternate drum chart** — every kick in it,
double-bass hits included, is pitch **96**. The build swaps that whole track in as
the song's 2x version. `PART DRUMS` is the same chart with the drummer's second
foot removed, so one pedal can play it. **Rock Band 3 discards pitch 95**, so a
kick left at that pitch is simply never played.

The first version wrote 95 onto `PART DRUMS_2X` to record which kicks were the
second foot. That was wrong twice over: the marks did nothing in game, and on a
chart where `PART DRUMS` still held every kick it left the "double bass" track
playing *fewer* kicks than the normal one — measured on a real chart, 474 against
577. Do not reintroduce a 95-writing step for RB3.

`Remove2XKicks` (General > Actions, "Remove 2x kicks") therefore plans the second
foot **in memory** and writes nothing to record it: it reads `PART DRUMS_2X`'s
kicks, deletes the matching ones from `PART DRUMS`, and repairs any surviving 95
back to 96. `DoubleBassPlan(qns, is_downbeat)` is the whole rule set as a pure
function — quarter-note positions in, a parallel array of booleans out — so it is
unit-testable with no project at all.

The cost of planning in memory, accepted deliberately: **a hand correction has no
durable home.** The 95s were an editable intermediate, and that is how two rule
bugs were found. Review now happens after the fact — the action reports what it
removed and is a single undo. A read-only preview would restore a before-the-fact
review and is the obvious next addition if this proves annoying.

**The rules**, in order:

1. Kicks no more than a **1/8** apart form one line.
2. **Edge trim.** A kick joined to the line by a gap wider than the line's tightest
   is a pickup into or a tail out of the line rather than part of it, when *either*
   its neighbour inside the line sits on a bar downbeat, *or* the line's tight
   section begins right at that neighbour — which makes the edge kick the only one
   at the wider spacing. Both ends are checked, repeatedly.
   The second test is load-bearing: trimming on the wider gap alone strips every
   one of the leading eighths off a long line that merely *starts* with a stretch
   of 1/8s, one pass at a time (measured: 1009/1080 on the first reference chart).
3. **Is it double bass?** Yes if the tightest gap is a 1/16 or closer — two
   back-to-back 1/16 kicks are already two feet — or if it is a straight run of
   more than `MAX_EIGHTH_RUN` (4) eighths.
4. **Which ones.** Every other kick, phased so that no kick landing on a bar
   downbeat is taken: the 2nd kick is preferred, falling back to the 1st when
   that phase would take a downbeat.
5. **Grid tie-break**, when *neither* phase can spare every downbeat. That happens
   to an even-length line bounded by two downbeats, and a line is usually
   even-length only because it has a **hole** in it. Counting played notes then
   flips the feet relative to the beat for the rest of the line, stranding the
   primaries on offbeats and handing the closing downbeat to the second foot. So
   read the line as a continuous grid instead — `GridSlots` numbers each kick by
   `(qn - qn_first) / tightest gap` — and take one parity of slots, ignoring that
   a slot is empty. The same foot then plays either side of the rest, which is
   what actually happens: the silent slot belonged to the other foot.

Rule 4 is why an even-length line ending on a bar line alternates from its *first*
kick — that is a consequence of the downbeat rule, not a special case.

**Rule 5 is a tie-break and must stay one.** Applied to every line it scores
974/1080 on the first reference chart: a long line mixing 1/8s and 1/16s has a
1/16 grid in which every eighth-spaced kick sits on an even slot, so grid parity
marks none of them. As a tie-break it is provably inert on a line with no hole —
slot number and note index are then the same sequence, so it re-offers the two
sets rule 4 already rejected and falls through to the unchanged default. That is
why adding it moved **zero** notes on the first chart. `GridSlots` returns nil
when any kick misses the grid, so a hand-played line keeps the old behaviour
rather than being rounded to a wrong slot.

**Provenance.** These were derived from, and reproduce exactly, the hand-authored
double bass in two reference songs — 1080/1080 kicks in the first, 577/577 in the
second after its author corrected the output by hand. Two figures are worth
knowing before changing anything:

- `MAX_EIGHTH_RUN` is **not** pinned by that evidence. The reference chart's
  straight-1/8 runs are 2, 3, 13, 61 and 110 kicks long, so any threshold from 3
  to 12 scores identically on it. 4 is the author's stated intent, not a measured
  value.
- Rule 2's *lone-edge* half was added after a second chart disagreed with the
  bar-downbeat-only version — a lone 1/8 leaning on a 1/16 pair, where the pivot
  was a half beat rather than a bar line. That confirmed the original phrasing had
  over-fitted to the incidental fact that both first-chart examples happened to
  pivot on a downbeat. Both halves together now fit two charts exactly (1080/1080
  and 577/577), but each still rests on a handful of examples: treat a
  disagreement with a new chart as evidence about the rule, not about the chart.
- Rule 5 was added the same way: the second chart has two bars (m14, m78) of
  steady 1/16 double bass with one kick missing in the middle, and counting played
  notes put the second foot on the closing downbeat. It changed 16 notes on that
  chart and none on the first.

**Two approaches that look right and are not**, recorded so they are not retried:

| Idea | Score on chart 1 | Why it fails |
|---|---|---|
| Split a line at an interior gap wider than its tightest | 974/1080 | Long mixed lines alternate continuously across 1/8↔1/16 changes and must not be cut there |
| Use grid parity for every line, not just the tie-break | 974/1080 | Eighth-spaced kicks all land on even slots of a 1/16 grid, so none get marked |

**This is a work in progress, and the tooltip says so.** Double-bass charts are
scarce, so the rules are refined as new songs expose new shapes — the lone-edge
half of rule 2 exists because the second chart disagreed with the first version.
The tool is meant to do the bulk of the work on long passages; the author is
expected to check the result rather than accept it. Do not reword the button or
its tooltip to imply the output is authoritative.

**Supporting a second game is open work, and hiding the button is a placeholder.**
`MarkDoubleBassKicks` still exists and still writes 95, for a game that reads it —
it is simply not drawn. The real answer is a game selector that decides which
conventions apply, at which point this and anything else RB3-specific becomes
conditional rather than commented out.

**Bar downbeats are read through `TimeMap2_timeToBeats`**, not `qn % 4`, so a
song that is not in 4/4 or that changes time signature is handled. Everything
else is in quarter notes, for the reason `NotesAtPitch` documents.

**Existing 95s are inputs, not obstacles.** They are read back as kicks so the
alternation comes out right on a part-marked track, which makes the action
idempotent. A 95 sitting where the rules would *not* put one is reported for
review and left untouched — the button never reverts a hand edit.

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
