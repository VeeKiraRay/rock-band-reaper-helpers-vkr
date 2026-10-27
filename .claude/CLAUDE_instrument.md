# Instrument Helper — Script Documentation

`rock_band_instrument_helper_vkr.lua` covers the instrument parts: Guitar, Bass, Drums, Keys and Pro Keys — difficulty generation and validation, overdrive and drum fills, tab input, MIDI utilities, and the WIP converter tabs. These tabs were part of the General Helper until it was split (General Helper v0.9.63 / Instrument Helper v0.1); `.claude/CLAUDE_general.md` documents the song-wide half.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

Five stable tabs are always visible: **General | Difficulty | Overdrive | Tab Input | MIDI**

**Overdrive tab** — generates overdrive phrases (116), unisons, drum fills (120-124) and vocal overdrive for the whole song, and validates what is already authored (read-only, with an overview strip). One page: an Instrument dropdown (All / Drums / Bass / Guitar / Keys / Vocals — groups, so tracks that must match are always written together), one settings block per generator with an include checkbox, one **Generate** button, then **Validate**. A time selection is ignored. See "Feature: Overdrive" below.

Three WIP tabs appear only when **Show WIPs? = Yes** in the General tab (persisted setting, default No): **Drums | Keys | Guitar**. These tabs function at a basic level but have known issues and are not ready for general users.

**Window footer** (every tab) — time selection, status, Copy result, Undo; the tabs scroll above it. Track lists refresh on their own (`CLAUDE.md` → "Track lists refresh themselves"). Shared implementation: `CLAUDE.md` → "Window footer".

**General tab** — three sub-tabs:

*Actions sub-tab*
- **Remove 2x kicks** — works out which kicks on `PART DRUMS_2X` are the drummer's second foot and deletes those from `PART DRUMS`. `PART DRUMS_2X` is the complete chart (every kick at 96) and is never thinned; the only thing that can change there is a leftover pitch-95 note being put back to 96. Matching between the tracks is by musical position, so a tempo change does not affect it. Whole track: a time selection does not narrow it. Safe to re-run — the second run finds nothing to remove and creates no undo point. See "Feature: double-bass detection" below.

*Settings sub-tab*
- Show WIPs? toggle.
- Save / Load buttons for project-scoped settings (placed last, since they persist the settings above them).

*Other tools sub-tab* — the same `DrawGeneralLinksTab` (`lib/reaper_script_links.lua`) the General Helper and the vocal helper draw; see `.claude/CLAUDE_general.md` → "Other tools sub-tab".

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
- **Validate Expert / Hard / Medium / Easy / All** — check against RBN Pro Keys authoring rules: chord count/span, interval jumps, spacing (M/E), lane range markers, overlapping gems (`DiffCheckOverlaps`: up to 4 notes sounding on Expert and Hard within an octave, none on Medium unless a quarter note apart, none on Easy — the doc's "Up to 4 notes in Pro Keys Expert / Hard"; Hard was once limited to 3). The "more notes than nearest Expert chord" check counts the Expert notes *sounding* there — the nearest onset, notes still held into it, and notes rolled in within 1/8 while it sounds — so a rolled chord merged into one chord (`GenMergeRolls`) is not flagged.
- **Two rules are softer than the RBN doc, from the official RB3 DLC charts** (352 development songs). *Spacing* uses 5-lane Keys' split (`PK_MIN_SP` / `PK_ADV_SP`): an error under a 1/8 note on Medium and a 1/4 on Easy, an advisory under the doc's 1/4 and 1/2 — official Medium has 13.8% of its gaps under a quarter (22% under 100 BPM) and Easy 41.9% under a half, but only 0.8% / 3.0% under half of those. *Interval jumps* are an advisory category: official charts leave 72-89% of the jumps over the doc's limits as they are, and an octave move fixes most of the rest; small whole-shape shifts are under 1%.
- **Unchanged copy / NOT REDUCED are advisories on Pro Keys** (`PK_PROGRESSION`, passed to `CheckDifficultyProgression`): official Hard is sometimes Expert as it is when Expert is simple (3 of 352 RB3 DLC songs exactly, 13 at 95%+ of the notes), and the doc has no rule that Hard must differ.
- `CollectPKChecks(dl, events, lane_shifts, exp_events, sel_s)` returns the checks as categories of `DiffIssue` records (like `CollectK5Checks`), so Generate counts Pro Keys errors the same way; `ReadPKTierEvents(track, sel_s, sel_e)` reads one tier track as `(lane_shifts, events)`.
- Track indices auto-detected by name (PART REAL_KEYS_X/H/M/E).
- Only notes in the playable Pro Keys range (48–72, C2–C4) are read as chord/gem events; reserved marker pitches (overdrive 116, glissando 126, trill 127) and any other out-of-range note are excluded before chord/span/jump/spacing/overlap grouping, so they can never masquerade as huge chords/jumps (`GroupIntoEvents` in `actions_difficulty.lua`). There is no longer a standalone "note range" check — filtering happens before events are built, so nothing outside 48–72 ever reaches a check.

*Keys sub-tab* (formerly "5-Lane Keys") — validates PART KEYS (all four difficulties on one track in separate pitch ranges).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–76 | Easy: 60–64 — all five lanes on every tier.
- **Validate Expert / Hard / Medium / Easy / All** — check chord count, spacing (Medium: error under 1/8, advisory under 1/4; Easy: error under 1/4, advisory under 1/2), note length, sustain gaps (Medium/Easy: the shared `DiffReleaseGapQN` floor, see below), overlapping gems (`DiffCheckOverlaps`, shared with Pro Keys: at most 3 notes sounding on Expert and Hard, the 5-lane doc's limit; Medium/Easy as Pro Keys).
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
  - **Cascades H→M→E** (no tier-specific override below Hard): an advisory "Kicks in drum fills" flags a fill lane (pitch 120) that keeps 2+ kicks and every kick of the tier above - it assumes a lane is a fill, and official charts trip it on 15-30% of lanes (H 29.8%, M 25.5%, E 15.1%); roll/trill markers start on an 8th/quarter-note grid line; a roll covers an even number of gem hits; roll/fill density (Hard: no 16th-rate rolls ≥140 BPM; Medium: never faster than 8th-rate at any tempo — its own blanket rule; Easy: quarter-rate required ≥120 BPM, else inherits Medium's 8th-rate cap below that); general timekeeping density — runs of ≥4 consecutive 8th-note-paced hits (Hard: flagged ≥170 BPM; Medium: ≥140 BPM, its own stricter rule; Easy: inherits Medium's 140 BPM, no own general override); a Green+Yellow/Green+Blue double crash needs a quarter-note gap before it or should reduce to a single Green.
  - **Cascades M→E**: kicks on quarter-grid only above 100 BPM; max 1 kick per measure at ≥170 BPM.
  - **Medium-only** (Easy's existing kick-pairing rule already makes these redundant there): a kick+Green(crash) chord is fine on-beat but not off-beat/syncopated. (A second Medium-only rule, a kick or snare falling between two Yellow/Blue hits, is implemented as `CheckDrumsYellowBlueInterleave` but currently **disabled** — not wired into `RunDrumsChecks` — since the rule as coded doesn't match the intended behavior; the function is left in place pending a clearer definition.)
  - **Hard-only** (tier-specific by nature, not cascaded): Hard should have fewer kicks than Expert; the Hard-tier (`diff_idx==2`) `[mix N drums<config>]` event should use the un-flipped/base config, not the disco (`d`) variant.
- **Authoring hints** — a fixed, non-pass/fail block (`DrumsAuthoringHints`) for rules too qualitative to check deterministically ("try removing kicks from adjacent notes", "remove about half the snare accents", "trim a note or two from a fast roll's start", "reduce hand motion" on Hard; "reduce triplets to quarter notes" on Medium; "favor crash over kick" on Easy). Always shown on H/M/E; never counted as an issue.
- Pro Drums tom markers (110–112) are not validated themselves (they fall outside every difficulty's 5-note pitch window, and no per-difficulty rule is stated). Two checks read them: a gem under its tom marker is a tom, so it is no crash for *double crash prep space* or Medium's *on-beat crash+kick* (`UnderTom`).
- Every Validate report ends with an informational (non-pass/fail) scan of `[mix N drums<config>]` disco-flip text events, listing which difficulty tiers have one authored — correctness of the flip depends on the surrounding beat pattern, which can't be judged from note data alone (the Hard-only un-flip check above is the one exception that *is* checkable).
- Track field (`diff_drums_idx`) auto-detected by name (PART DRUMS) — independent of the Drums tab's own conversion target-track field.

*Generate sub-tab* — builds Hard, Medium and Easy automatically, each from the tier above it, for Guitar, Bass, Pro Keys, Keys and Drums (with the song's PART DRUMS_2X). **Every reduction rule - what it does, its source (RBN doc, official charts, or a user rule) and its measured numbers - is in [`docs/difficulty_reduction.md`](../docs/difficulty_reduction.md)**, per instrument and difficulty, with the settings table. Code comments say only what a rule does; change a rule and its doc entry together. `dev/tests/instrument_algorithms.lua` fails when a `GEN5_PARAMS` or `GEN_DRUMS_PARAMS` key is not named in the doc. This paragraph covers the wiring.
- **Instruments:** `GEN_INSTRUMENTS` (`actions_difficulty_generate.lua`); another instrument joins with an entry there plus a planner. Its order is the run order of All instruments, which is why Pro Keys comes before Keys. Planners are pure (no `r`, no `S`): `Gen5PlanTier` (Guitar/Bass/Keys, `difficulty_generate_5lane.lua`), `GenPKPlanTier` (Pro Keys), `GenDrumsPlanTier` (Drums). The 5-lane and Pro Keys planners share `Gen5SelectOnsets` (`difficulty_generate_rhythm.lua`), which decides the onsets each tier keeps; Drums has its own limb-by-limb planner, independent of the band.
- **Instrument dropdown** (`S.diff_gen_instrument`, session-only): one instrument, or "All instruments". The track combo binds to the instrument's existing field (`diff_gtr_idx` / `diff_bass_idx` / `diff_5k_idx` / `diff_drums_idx`; Pro Keys uses the Pro Keys sub-tab's `diff_pk_*_idx`, one track per tier), so it is the same selection the instrument's own sub-tab shows. "All instruments" ignores the combos and finds each default track by exact name (`FindTrackExact`).
- **Generate never writes to a muted track.** A muted track picked for a single-instrument run stops the run before anything is read or written (`MutedError` in `ResolveTargets`); All instruments skips a muted, missing or empty track - PART DRUMS_2X and the Pro Keys tier tracks too - and lists it.
- **Buttons:** Hard / Medium / Easy (from the tier above *as it is now* — rebuilds the lower tiers after hand-editing one) and Hard > Medium > Easy, where each step plans from the tier the previous step just generated (in memory, not re-read from the track). One overwrite popup lists every tier that would be replaced (`S.diff_copy_pending` with `confirm_label`); the whole run is one undo block.
- **Time selection = the notes that start in it** (start inclusive, end exclusive), for every instrument: Generate reads to 2 ms before the selection end (`read_e`; the tier readers keep notes up to 1 ms past it, as Validate wants) and `ReplaceNotesBulk` clears by onset. **Without a time selection a tier is replaced in the whole take**, not from 0 to the item's end: an imported item ends at its last note, and a zero-length chord sitting exactly on that end was never cleared and got doubled. A Pro Keys tier with no notes outside the selection is generated as new and replaced whole (its lane-shift markers too); Expert's lane shifts are always read from the whole track.
- **Planner events** (`GenToPlannerEvents`): positions and lengths in quarter notes, snapped to 1/960 QN, plus `bar_qn` / `bar_len` (`TimeMap_QNToMeasures`), `pulse` (`Gen5PulseQN`: 1.5 in compound meters) and `bpm`. Output events carry them on to the next tier of a chain. **`bpm` is quarter notes per minute in every meter** - the tempo marker in effect (`GetBPMAt`), what Validate and the offline tools read; never `TimeMap_GetDividedBpmAtTime`, which doubles it in /8 signatures. Reading in seconds leaves float noise, so every planner threshold compares with `GEN5_EPS` - keep both the snap and the tolerance when adding a threshold. `qn_e_full` is a note's length before any tier shortened it.
- **One rhythm model for 5-lane and Pro Keys (a product rule).** Which onsets a tier keeps depends only on onset positions, note lengths and tempo — never on colors, chords or instrument — and every instrument uses the same `GEN5_PARAMS`, so parts playing the same Expert rhythm get the same lower-tier rhythm with no coordination. `instrument_algorithms.lua` checks that the same rhythm given as guitar, bass and keys produces identical onsets; do not add a color- or chord-dependent weight or a per-instrument gap. The one coordinated exception is **Guitar leading**: the action plans Guitar's chain in memory (`GuitarRefs`, nothing written, whether or not Guitar is in the run) and passes Hard's busy-bar choices (`log.busy_bars` → `opts.busy_ref`) and Medium's rhythm (`log.rhythm_bars` → `opts.rhythm_ref`) to Bass, Keys and Pro Keys; the golden suite and the offline evaluator do the same.
- **Keys follows Pro Keys.** Keys follows the same-tier Pro Keys when it has notes (`SelectByGuide`, one Keys onset per Pro Keys onset, a matched note taking the Pro Keys position): in All instruments the Pro Keys output just planned (`ProKeysGuide(..., generated)`), alone the Pro Keys sub-tab's tracks - never a name search outside All instruments. A Pro Keys note with no Keys note within a 32nd is listed (`log.guide_missed`).
- **Tuned numbers:** `GEN5_PARAMS`' gaps and weights are tuned for onset F1 against the official lower tiers over the development songs (`dev/calibration/run_generate_eval_offline.lua tune`, see the calibration README). Change one only by re-running that sweep; the hold-out (`dev/calibration/difficulty_holdout.lua`) is never used for tuning.
- **Questions before writing:** a run starting at Hard plans Pro Keys Hard in memory and, if it equals Expert exactly (`GenPKSameAsUpper`), asks first (Shorten sustains / Keep as Expert / Cancel), so Medium and Easy are built from the chosen Hard and the run stays one undo step. The answer comes back as `GenerateDifficulties(..., answers)` (`answers.pk_pull_back` → the planner's `opts.pull_back`). The shared confirm popup (`ui_difficulty.lua`) takes an optional second answer (`alt_label` / `on_alt`) and clears the pending entry before running a callback, so a callback can ask the next question.
- **Settings reach the planners as `opts`:** "Hard fast runs" `S.diff_gen_fast_runs` → `opts.fast_runs` (also used for the Guitar reference and the Pro Keys pre-plan; default `GEN5_PARAMS.fast_runs_default`), "Hard 8th runs" → `opts.busy_drop`, "Drums Medium" `S.diff_gen_drums_between`, "Drums fast 8ths" `S.diff_gen_drums_eighths` → `opts.eighth_hands`. All session-only.
- **Hard fast-run rewrite** (`Gen5RetimeDenseRuns`, `difficulty_generate_retime.lua`) is the one place notes move. Moved events carry `retimed` (the gap does not apply next to them, the cap and busy-bar rules never remove them, `log.retimed_bars` drives the result's "review by hand" list) or `joined` (a run's note in a bar the rewrite did not change); `rewritten` marks a moved note for the force-HOPO restore without lifting the next tier's gap. Drums pass `group_grid = 'own'` and `min_grid`. Compare a rewrite with a hand reduction: `dev/tools/generate_compare_hand_offline.lua <song.mid> <hand.mid> [part] [bars]`.
- **Force-HOPO on Hard** (`difficulty_generate_hopo.lua`, Guitar/Bass): the action marks each Expert note's hammer-on (`ev.hopo` = `'forced'` / `'auto'`), the planner carries it, and generating Hard replaces its lo+5 markers (lo+6 is left alone). Magma's HOPO threshold cannot be read from REAPER, so 170 ticks at 480 PPQ is assumed.
- **Drums planner** (`GenDrumsPlanTier`, `difficulty_generate_drums.lua`): one step function per rule, run in a fixed order inside the local `PlanTier` - **the order matters** (three-limb kicks before kick spacing, the tom-before-crash rule after the 8th-run breaker, roll evening last). RBN tempo thresholds come from Validate's own `DRUMS_RULES` (`actions_difficulty_drums_checks.lua`), so the two cannot drift. *Context* (`opts.ctx`, read by `DrumsContext` from the whole take): fill lanes 120, roll lanes 126/127, Pro Drums tom markers 110-112, Expert's disco-flip spans, the EVENTS track's section names, and `song_bpm` (the tempo at bar 1). Medium also gets Expert (`opts.expert`) to reduce fills Hard rewrote. The planner reports what it did in `log` (one key per rule; the action turns each into a result line) and returns `log.ctx`, the context after its changes, which the tiers below are planned with.
- **Tom markers follow the Drums rewrite:** tom markers are shared by every tier, so when Hard's rewrite moves a tom the planner returns `log.tom_markers` (one marker over the whole run) and `log.tom_conflict_bars` (runs thinned instead, because a cymbal would fall under the new marker - in the tier above or in notes the run does not write, `opts.keep_cymbals` from `DrumsKeptCymbals`). The action writes the markers in the same undo block.
- **Drums 2X** (`PART DRUMS_2X`) is part of the Drums selection, not an instrument: the `drums` entry of `GEN_INSTRUMENTS` carries it as `x2` (`S.diff_drums2x_idx`, the "2X track" row), and `ResolveTargets` / `AddTargets` expand Drums into a PART DRUMS target and a 2X target after it. Each 2X tier takes the kicks of the PART DRUMS tier one step up (`GenDrums2xInput`, `opts.keep_kicks`); the PART DRUMS tier is read when the 2X tier is planned, so a run uses the tiers it has just written. With PART DRUMS missing, `(none)` or muted, a single-pedal version is made in memory (`SinglePedalTiers`, `GenDrumsSinglePedal` → `DoubleBassPlan` unchanged, exactly what General > Actions > "Remove 2x kicks" would leave). "Only 2x bass pedal authored on PART DRUMS" (`S.diff_gen_drums_2x_on_1x`, `TwoXOnOneTarget`) generates PART DRUMS that way, and stops the run when the song also has a PART DRUMS_2X or `DoubleBassPlan` finds no second-foot kick.
- **Writes are bulk:** each tier (with Hard's force-HOPO markers, Pro Keys' lane shifts) is written by `ReplaceNotesBulk`: one `MIDI_GetAllEvts`, the tier's old note on/off pairs dropped and the new ones added in Lua (other events untouched, in order), one `MIDI_SetAllEvts`, one `MIDI_Sort`. Per-note inserts took about 10 s for a fast song's Guitar + Bass; `WRITE_MODE` keeps `'batched'` / `'per_note'` only for timing comparisons (they still clear by overlap, `ClearNotesInRange`). `ReplaceNotesBulk` pairs a zero-length note's note-off (stored first, at the note-on's tick) with its note-on, and drops a note-on left unclosed in the window. The result's last line is `Done in x.x s`; a run over `SLOW_RUN_S` (2 s) lists each phase - check it first if Generate gets slow.
- **Zero-length notes:** writing a tier makes REAPER drop every zero-length note in that take — Expert gems, untouched tiers, markers such as overdrive (Copy to Difficulty writes the same way). Generate ignores them as input, snapshots them before writing (`ZeroLengthNotes`) and lists the ones REAPER removed outside the regenerated tiers - once gone, Validate cannot find them. Pro Keys uses them as input: Expert's track is never written. The fixtures `rb_guitar.mid` / `rb_bass.mid` carry a zero-length overdrive marker and `rb_keys.mid` a zero-length Expert chord at bar 11.
- **Result:** per tier, onsets and notes kept (`kept 829 of 833 onsets (99%), 1373 of 1569 notes (88%)`; a chord losing a note keeps the onset), from `KeptPercent`, which never rounds to 100 when something was dropped or to 0 when something was kept. The output is re-checked with Validate's own collectors (`CollectGBChecks` / `CollectK5Checks` / `CollectPKChecks` / the drums checks) and any remaining error is listed; Drums' roll-marker checks (`marker = true` categories) are about Expert's markers, so they are noted once instead of counted against the tier.
- **The aim is official-like, not merely Validate-clean.** Validate's errors barely thin Guitar/Bass Medium/Easy (their spacing rules are advisories), which is why the numbers are tuned against official charts.
- **Checking a planner change offline**, before the REAPER suites: `lua dev/tests/run_generate_golden.lua` (hand-verified songs regenerate identically, every part including PART DRUMS_2X), `lua dev/calibration/run_generate_eval_offline.lua` and `lua dev/calibration/run_generate_eval_drums_offline.lua [rewrite|auto|thin] [beats|hands|off] [diag]` (agreement with official charts, 0 violations), and `lua dev/tools/generate_action_dryrun_offline.lua [song.mid part from_qn to_qn]` (the real action against a REAPER stand-in, Validate's own checks on the output; Drums modes `drums|drums-1x-muted|drums-muted|drums-2x-on-1x|drums-2x-as-1x`). To answer "why did Generate do this here?" for drums: `lua dev/tools/generate_compare_drums_offline.lua <song.mid> [H|M|E|chain] [bars] [beats|hands] show` prints every tier of the range per bar, the file's tier under it where it differs, tempo, section, markers and which rules fired.

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

## Module contents

| File | Contents |
|---|---|
| `rock_band_instrument_helper_vkr.lua` | Entry point: ReaImGui check, path derivation, dofile calls, startup |
| `rock_band_instrument_helper_vkr/defaults.lua` | `S`, `TIPS` |
| `rock_band_instrument_helper_vkr/settings.lua` | `SaveSettings`, `LoadSettings` (project key: `RBInstrumentHelperVKR/settings_v1`) |
| `rock_band_instrument_helper_vkr/helpers.lua` | `SetDefaultMIDITracks`, `SetDefaultDifficultyTracks` — smart default track selection. The track and action helpers both helpers need (`FindTrackByName`, `GetTakePPQPerQN`, `GetTempoContextBefore`, `RefreshTrackLists`, `RunAction`) are in `lib/reaper_helper_common.lua` |
| `rock_band_instrument_helper_vkr/overdrive_read.lua` | `OD_PITCH`, `OD_FILL_LO/HI`, `OD_PHRASE_PITCH`, `OD_SOLO_PITCH`, `OD_QN_EPS`, `OD_INST_GROUPS`, `OD_VOCAL_TRACK`, `OD_HARM_TRACK`, `OD_GROUP_CHOICES`, `OdInstGroup`, span helpers (`OdSpansOverlap`, `OdSameQN`, `OdSameSpan`, `OdAnyOverlap`, `OdSpanListsEqual`), bar helpers (`OdCountedBeats`, `OdReadBars`, `OdBarAt`, `OdBarStartingAt`, `OdBarsOfSpan`, `OdBarActivity`, `OdQNToSec`), `OdSectionFamily`, `OD_TOM_MARKERS`, `OdCrashBars`, `OdTrackTakes`, `OdReadPitchNotes`, `OdBuildModel`, `OdFinishModel`, `OdWhere` (global); `PitchSpans`, `FillSpans`, `ReadEventsTrack` (local) — the Overdrive tab's song model, all in quarter notes. Reads through `difficulty_read.lua`'s `FindTrackExact` / `ReadGemEvents` rather than a second reader |
| `rock_band_instrument_helper_vkr/overdrive_interest.lua` | `OdBarInterest`, `OdBandTogetherness` (global); `PercentileRanks`, `WindowTerms`, `BarSignature`, weights (local) — per-bar "eventfulness" from `DIFFICULTY_PRIMITIVES`. Pure |
| `rock_band_instrument_helper_vkr/actions_overdrive_fills.lua` | `OD_FILL_PACINGS`, `OD_FILL_MIN_GAP_SEC`, `OdAutoFillPacing`, `OdPlanFills`, `OdActivationQN`, `OdSplitEarlyFills` (global) — drum fill planner. Pure |
| `rock_band_instrument_helper_vkr/actions_overdrive_vocals.lua` | `OdPlanVocals` (global) — vocal overdrive planner (cadence + HARM1 match). Pure |
| `rock_band_instrument_helper_vkr/actions_overdrive.lua` | `OdUnisonGroups`, `OdPlanInstruments` (pure), `OdJobs`, `OdFillAvoidSpans`, `OdVocalNoGo`, `OdDrumPhrasesForActivation`, `GenerateOverdrive` (global); `TakeAtQN`, `InsertQN`, `ClearPitches`, `GroupTracks` (local) — instrument/unison planner and the Generate action (replace confirmation, writing, report) |
| `rock_band_instrument_helper_vkr/actions_overdrive_validate.lua` | `OdValidateModel` (pure), `OdBuildOverview`, `ValidateOverdrive` (global) — read-only checks and the overview strip's data |
| `rock_band_instrument_helper_vkr/ui_overdrive.lua` | `DrawOverdriveTab` (global); `DrawOverview` (local) — tab body, overview strip, replace-confirmation modal (`ConfirmOverdriveReplace`) |
| `rock_band_instrument_helper_vkr/actions_drums.lua` | `ConvertDrums` (global); `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport` (local) |
| `rock_band_instrument_helper_vkr/actions_drums_2x.lua` | `DoubleBassPlan`, `Remove2XKicks`, `MarkDoubleBassKicks` (global); `TRACK_2X`, `TRACK_1X`, `MARK_2X`, `KICK`, `MAX_SNAP_QN`, `AMBIGUITY_RATIO`, `UNMATCHED_LIST_MAX`, `SCAN_SPAN`, `SIXTEENTH_QN`, `EIGHTH_QN`, `MAX_EIGHTH_RUN`, `QN_EPS`, `BEAT_EPS`, `REVIEW_LIST_MAX`, `POS_EPS`, `PRIORITY_W` (module-level locals); `MBTAtQN`, `MIDITakesOn`, `NotesAtPitch`, `DescribeGap`, `MatchMarkers`, `MakeBarDownbeatTest`, `MakeBarPosition`, `TightestGap`, `TrimRunEdges`, `IsDoubleBassLine`, `GridSlots`, `PickAlternating`, `OnStep`, `PriorityPicks` — General > Actions' "Remove 2x kicks". **`PART DRUMS_2X` is a complete alternate chart, every kick at 96**; the build swaps the whole track in, and RB3 discards pitch 95, so a kick left at 95 simply never plays. `Remove2XKicks` reads that track's kicks (96 **and** any stale 95), plans the second foot in memory with `DoubleBassPlan`, deletes the matching kicks from `PART DRUMS`, and repairs any 95 back to 96 — all in one undo block across both tracks. Nothing records the plan on disk. Matching is in **project QN** via `MIDI_GetProjQNFromPPQPos`, the same rule as the difficulty validators' beat-fraction checks: bridging two takes through project seconds walks the tempo map twice in opposite directions and is only exact before the first tempo marker. Seconds appear here **only** to render report text. Each planned kick takes the nearest *unclaimed* kick on `PART DRUMS`, within `MAX_SNAP_QN` (a 1/32) **and** at least 4× nearer than the runner-up (`AMBIGUITY_RATIO`) — a relative test, so the window scales with note density; in a 1/32 blast beat any fixed millisecond buffer wide enough to forgive hand-nudging is also wide enough to grab the wrong gem. Both lists are sorted, so a moving insertion point ±`SCAN_SPAN` finds every candidate in O(n+m). Returns before any `Undo_*` call when there is nothing to remove *and* nothing to repair. Planned kicks already missing from `PART DRUMS` are normal on a re-run and are reported as "already absent", not as misses. `MarkDoubleBassKicks` writes pitch 95 and is **deliberately unreachable from the UI** — see `ui.lua`; it is kept and kept tested for a future version supporting games that read 95, and must not be wired up for RB3 |
| `rock_band_instrument_helper_vkr/actions_keys.lua` | `SplitHands`, `ConvertProKeys`, `ConvertPianoToProKeys`, `ConvertKeys5` (global); `PK_MIN`, `PK_MAX`, `PK_RANGES`, `PK_PREF_LABEL` (module-level globals); `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord` (local) |
| `rock_band_instrument_helper_vkr/actions_keys_guides.lua` | `ProKeysTabGuide`, `VocalTabGuide`, `VocalTabBestShift`, `TabGuideEventRows` (global); `PkEventLabel`, `ParseTabToRaws`, `TabOutOfRange`, `TabShiftLabel`, `TabGuideHeader`, `AppendSpanSummary` (local). Both guides print one row per event, laid out like the guitar guide's (`TabGuideEventRows`: the typed tab line, the pitches after the shift, out-of-range notes and over-wide chords flagged on the row). The two guides pick their octave shift differently: Pro Keys centres the passage on C3 (its lanes are a range window, so only the shape matters), while vocals keep the written pitch and shift only when notes fall outside C1-C5 (`VocalTabBestShift`: fewest out of range, then the smallest shift) |
| `rock_band_instrument_helper_vkr/actions_guitar.lua` | `ConvertGuitar`, `ValidateGuitar`, `GetBPMAt`, `CompressChord`, `SortedChordPitches`, `GemLabel`, `PitchLabel`, `ChordTypeName`, `BuildShapeGemMap`, `ChordQualityLabel` (global); `GEM_MIN`, `GEM_MAX`, `GEM_LETTERS`, `CHORD_WINDOW_S`, `POOLS`, `POOLS2_NO14` (module-level globals) — Expert gem generation and authoring rule validation. `BuildShapeGemMap(events, max_chord, allow_14)` (shared with `actions_guitar_guide.lua`) is the global shape→gem-combo map builder; every 2+-note shape consults `GuitarSuggestRBMapping` (`lib/reaper_guitar_theory.lua`) BY PITCH CLASS (not physical note count) so e.g. a power chord — even voiced with a doubled root across 3 strings — always gets a 1-3-spread 2-gem combo. `max_chord`/`allow_14` are **parameters, not reads of `S`** — the two callers aren't governed by the same settings (see `actions_guitar_guide.lua` below); `max_chord = nil` skips compression entirely. Shapes with no principled width and 3+ notes bucket by `min(sz,3)`, since they all draw from `POOLS[3]` and must compete in one `AssignByConflict` group. `SortedChordPitches(pitches, max_chord)` returns an ascending **copy** (optionally compressed first) — `CompressChord` returns its argument unchanged when the chord already fits, so sorting in place used to reorder the caller's own `ev.pitches`. When a group has more distinct shapes than available combos, `AssignByConflict` gives the first (lowest-pitched) shapes a unique combo each, then assigns each overflow shape whichever already-claimed combo minimizes conflicts against shapes it's actually adjacent to anywhere in the passage (an adjacency table built from the real event sequence, restricted to same-group consecutive pairs), tie-broken toward the top of the pool and refined over a few bounded sweeps — returned as a third `shared` map so callers can flag reused combos; `ChordQualityLabel` names the recognized shape (e.g. `[Power chord]`) for the reason string |
| `rock_band_instrument_helper_vkr/actions_guitar_guide.lua` | `ParseTabHorizontal`, `ParseTabVertical`, `ReformatVerticalTab`, `GuitarTabGuide` (global); `AssignGemsForGuide` (local) — guitar Tab Input guide; `AssignGemsForGuide` delegates its shape→gem map to `BuildShapeGemMap` (`actions_guitar.lua`), calling it as `BuildShapeGemMap(events, nil, true)`. **No compression, and no reads of the Guitar tab's settings.** The Tab Input tab writes nothing to the project, so there is no chart to fit and nothing to reduce — `GuitarSuggestRBMapping` derives the gem count from distinct pitch classes across the whole shape, which is exactly how the Music Theory helper's Shape Search answers, and the two tools must agree (both exist to say how a chord maps to RB). Truncating by array index first made them disagree: it could drop a chord's root and keep a doubled note, turning an open D into a bare sixth dyad, or a G5 into three octaves of G with no suggestable width. `Max chord` / `Allow 1-4` / `Phrase gap` belong to the WIP Guitar tab's converter and are not exposed by this tab (`_DrawTabInputBody`, `ui_midi.lua`) — phrase breaks use the local `TAB_PHRASE_GAP_S` instead of `S.mc_gtr_wrap_gap_ms` |
| `rock_band_instrument_helper_vkr/actions_guitar_validate.lua` | `SustainThresholds`, `ReadRBGuitarNotes`, `RunValidation` (global) — validation helpers called by `ValidateGuitar` |
| `rock_band_instrument_helper_vkr/actions_midi_align.lua` | `AlignMIDI`, `ResizeAllMIDI` (global) |
| `rock_band_instrument_helper_vkr/actions_midi_replace.lua` | `GetPatternPitchRange`, `SetSearchPattern`, `SetReplacePattern`, `FillRange`, `DoMIDIPatternReplace`, `GoPrevPatternMatch`, `GoNextPatternMatch`, `ListPatternMatches` (global); `BuildPatternLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake`, `ResolvePatternScope`, `ScanPatternMatches`, `GoToPatternMatch` (local) |
| `rock_band_instrument_helper_vkr/actions_midi_length.lua` | `AdjustMidiNoteLengths` (global) — Midi note length/sustain-gap adjustment; `NoteLenPPQ`, `AdjustAllNoteLengths`, `AdjustSustainGaps` (local) |
| `rock_band_instrument_helper_vkr/actions_difficulty_shared.lua` | `CheckDifficultyProgression`, `CompressChordOffsets`, `DiffIssue`, `DiffCheckOverlaps`, `BuildDiffCheckReport`, `DiffReleaseGapQN`, `DiffReleaseGapName`, `DiffQNLabel`, `DIFF_RELEASE_GAP_QN` / `DIFF_RELEASE_GAP_SLOW_QN` / `DIFF_SLOW_BPM` (global) — cross-difficulty identical-chart + note-count reduction checks, the color-compression helper used by Keys/Guitar-Bass's Copy functions, the issue record + report builder the Keys and Guitar/Bass checks share, and their shared Medium/Easy sustain-release gap |
| `rock_band_instrument_helper_vkr/actions_difficulty.lua` | `CopyProKeysDiff`, `ValidateProKeysDiff`, `ValidateAllProKeys`, `CollectPKChecks`, `ReadPKTierEvents`, `PK_MAX_CHORD`, `PK_MAX_SPAN` (global) — Pro Keys difficulty rules |
| `rock_band_instrument_helper_vkr/actions_difficulty_5k.lua` | `ValidateKeys5Diff`, `ValidateAllKeys5`, `CopyKeys5Diff`, `ReadK5TierEvents`, `CollectK5Checks`, rule tables `K5_RANGE` / `K5_MAX_CHORD` / `K5_MIN_SP` / `K5_ADV_SP` (global) — Keys (formerly "5-Lane Keys") difficulty rules |
| `rock_band_instrument_helper_vkr/actions_difficulty_gtrbass.lua` | `CopyGtrBassDiff`, `ValidateGtrBassDiff`, `ValidateAllGtrBass` (global; take `instrument` = `'gtr'`\|`'bass'` as first param), `ReadGBTierEvents`, `CollectGBChecks`, rule tables `GB_RANGE` / `GB_MAX_CHORD` / `GB_MAX_SPAN` / `GB_FORCE_HOPO_ALLOWED` / `GB_ADV_SP` (global) — shared Guitar/Bass difficulty rules |
| `rock_band_instrument_helper_vkr/actions_difficulty_drums_checks.lua` | `DRUMS_RANGE`, `DRUMS_RULES`, `ReadDrumsNotes`, `GroupDrumsHits`, `ReadDrumsTierEvents`, `DrumGemName`, `DrumLabel`, `CollectDrumsChecks` (global) — the Drums tier reader, the RBN tempo thresholds (shared with the Generate planner) and every Validate check as `DiffIssue` categories |
| `rock_band_instrument_helper_vkr/actions_difficulty_drums.lua` | `CopyDrumsDiff`, `ValidateDrumsDiff`, `ValidateAllDrums` (global) — Drums Validate report and Copy to Difficulty, plus the two cross-tier checks (kick count vs Expert, Hard disco mix event) |
| `rock_band_instrument_helper_vkr/difficulty_generate_drums.lua` | `GenDrumsPlanTier`, `GEN_DRUMS_PARAMS`, `GenDrumsIsVerse`, `GenDrums2xInput`, `GenDrumsSinglePedal` (global) — the Drums Generate planner (limb by limb). Pure; reads `DRUMS_RULES` and `Gen5RetimeDenseRuns` at call time |
| `rock_band_instrument_helper_vkr/ui_keys.lua` | `DrawKeysTab` (global) — Keys tab rendering |
| `rock_band_instrument_helper_vkr/difficulty_generate_retime.lua` | `Gen5RetimeDenseRuns` (global) — Hard's fast-run rewrite: dense runs on fast songs moved one grid slower (16ths → 8th triplets → 8ths) with a color-order-preserving DP. Pure, loaded before the planner; shared with the same offline consumers |
| `rock_band_instrument_helper_vkr/difficulty_generate_hopo.lua` | `Gen5IsAutoHopo`, `Gen5MarkHopos`, `Gen5ForceHopoSpans` (global) — which notes hammer on, and the force-HOPO markers Guitar/Bass Hard gets to keep Expert's. Pure |
| `rock_band_instrument_helper_vkr/difficulty_generate_colors.lua` | `Gen5ReduceChordSize`, `Gen5ReduceChordSizeKeys`, `Gen5KeysEasyMotion`, `Gen5NarrowSpan`, `Gen5ShiftSegments`, `Gen5ShiftBars`, `Gen5ClampOrShiftBars` (global) — chord size/span and moving lines under a tier's top lane. Pure, loaded before the planner |
| `rock_band_instrument_helper_vkr/difficulty_generate_params.lua` | `GEN5_PARAMS`, `GEN5_SUSTAIN_QN`, `GEN5_MIN_LEN_QN`, `GEN5_EPS`, `Gen5PulseQN`, `Gen5Is44`, `Gen5BeatClass`, `Gen5MinGapQN`, `Gen5MinSustainQN`, `Gen5ReleaseGapQN` (global) — the tuned numbers and small shared rules of every Generate planner. Pure; loaded first of the Generate modules, since the rhythm and 5-lane files bind these at load time |
| `rock_band_instrument_helper_vkr/difficulty_generate_overlaps.lua` | `GEN_OVERLAP_MAX`, `GEN_OVERLAP_SPAN`, `GenMergeRolls`, `GenPlanOverlaps`, `GenNextAfterHold` (global) — Keys and Pro Keys overlapping gems (a note held while later notes start) and rolled chords. Pure; loaded right after the params file |
| `rock_band_instrument_helper_vkr/difficulty_generate_rhythm.lua` | `Gen5SelectOnsets`, `Gen5AndPhrases` (global) — which onsets a tier keeps: gap thinning, the Hard fast-run rewrite call, busy bars, keep cap, Medium's note per beat, following Guitar, Keys following Pro Keys. Shared by every planner, so the one-rhythm rule holds by construction. Pure |
| `rock_band_instrument_helper_vkr/difficulty_generate_5lane.lua` | `Gen5PlanTier` (global) — Difficulty > Generate's planner for Guitar/Bass/Keys: `Gen5SelectOnsets`, then chords, colors, sustains. No `r`/`S`; shared with `dev/calibration/run_generate_eval_offline.lua` |
| `rock_band_instrument_helper_vkr/difficulty_generate_prokeys.lua` | `GenPKPlanTier`, `GenPKReduceChord`, `GenPKBestWindow`, `GEN_PK_WINDOWS` (global) — Difficulty > Generate's Pro Keys planner: `Gen5SelectOnsets`, then top-note chord reduction, lane shifts, one Medium/Easy window, sustain gaps. Pure; shared with the offline evaluator |
| `rock_band_instrument_helper_vkr/actions_difficulty_generate.lua` | `GenerateDifficulties`, `GenInstrumentByKey`, `GenToPlannerEvents`, `GEN_INSTRUMENTS`, `GEN_ALL_KEY` (global) — Difficulty > Generate's REAPER side: track resolution, read, plan, write, re-validate, one undo block |
| `rock_band_instrument_helper_vkr/ui_difficulty_generate.lua` | `DrawDifficultyGenerateTab` (global) — the Generate sub-tab body, called from `DrawDifficultyTab` |
| `rock_band_instrument_helper_vkr/ui_difficulty.lua` | `DrawDifficultyTab` (global) — Difficulty tab rendering (Pro Keys, Keys, Guitar/Bass, Drums, Generate sub-tabs) and the shared overwrite-confirm popup |
| `rock_band_instrument_helper_vkr/ui_midi_pattern.lua` | `DrawMIDIPatternTab` (body only — no `Begin`/`BeginTabItem`), `ResetMIDIPatternState` (global); `MR_DIFF_OPTIONS` (local) — MIDI > Pattern sub-tab, shared with the standalone window |
| `rock_band_instrument_helper_vkr/ui_midi.lua` | `DrawTabInputTab`, `DrawMIDITab` (global) — Tab Input and MIDI tab rendering. The Pattern sub-tab's body is in `ui_midi_pattern.lua`; this file only wraps it in a tab item |
| `rock_band_instrument_helper_vkr/ui.lua` | `Loop` — the tab bar, the General tab, the WIP tabs' bodies, project-switch handling |

**Local-only functions:**
- `settings.lua`: `SerializeSettings`, `DeserializeSettings`
- `helpers.lua`: `SetDefaultsByName`
- `actions_drums.lua`: `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport`
- `actions_drums_2x.lua`: `TRACK_2X`, `TRACK_1X`, `MARK_2X`, `KICK`, `MAX_SNAP_QN`, `AMBIGUITY_RATIO`, `UNMATCHED_LIST_MAX`, `SCAN_SPAN`, `SIXTEENTH_QN`, `EIGHTH_QN`, `MAX_EIGHTH_RUN`, `QN_EPS`, `BEAT_EPS`, `REVIEW_LIST_MAX`, `POS_EPS`, `PRIORITY_W` (module-level locals); `MBTAtQN`, `MIDITakesOn`, `NotesAtPitch`, `DescribeGap`, `MatchMarkers`, `MakeBarDownbeatTest`, `MakeBarPosition`, `TightestGap`, `TrimRunEdges`, `IsDoubleBassLine`, `GridSlots`, `PickAlternating`, `OnStep`, `PriorityPicks`
- `actions_keys.lua`: `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord`
- `actions_keys_guides.lua`: `PkEventLabel`, `ParseTabToRaws`, `TabOutOfRange`, `TabShiftLabel`, `TabGuideHeader`, `AppendSpanSummary`
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
- `actions_difficulty_drums_checks.lua`: `DIFF_NAMES`, `GEM_NAMES`, `GRACE`, `EPS_QN`, `R` (module-level locals); `GetDrumsBeatDur`, `QNAt`, `GetMeasureAt`, `HasOffset`, `CheckDrumsMaxChord`, `CheckDrumsKickPairing`, `CheckDrumsYellowBlueInterleave` (not wired in), `CheckDrumsKickGrid`, `CheckDrumsKickPerMeasure`, `CheckDrumsOnBeatCrashKick`, `CheckDrumsDoubleCrash`, `CheckDrumsFillKicks`, `CheckDrumsRollGrid`, `CheckDrumsRollEvenCount`, `RollAvgGapQN`, `CheckDrumsRollDensity`, `CheckDrumsGeneralDensity`, `CheckDrumsOutOfRange`, `CheckDrumsRollVelocity`
- `actions_difficulty_drums.lua`: `DIFF_NAMES`, `DIFF_BY_MIX_IDX`, `ADJACENT_HIGHER`, `DRUMS_HINTS` (module-level locals); `CountNotes`, `CheckDrumsKickCountVsHigher`, `CheckDrumsDiscoUnflip`, `ScanDiscoFlipStatus`, `DrumsAuthoringHints`, `RunDrumsChecks`
- `difficulty_generate_drums.lua`: `EPS`, `ROLL_TOL`, `KICK`..`GRN`, `CLASS_W`, `TOM_MARKER_TAIL`, `EVERY_8TH`, `EVERY_BEAT`, `PlanTier` (module-level locals); `NearInt`, `OnGrid`, `OnBeat`, `In`, `Has`, `Drop`, `Add`, `IsCymbal`, `IsTom`, `HasCymbal`, `FillLike`, `Copy`, `Compact`, `Mark`, `ExpertForRewrittenRuns`, `SongTempo`, `Annotate`, `KeepByGap`, `Unflip`, `RollGrid`, `Rolls`, `FillRuns`, `RunTomMarkers`, `TomMarkerConflict`, `ApplyTomMarkers`, `RetimeFills`, `GridFillRuns`, `CymbalStream`, `DropStreamCymbals`, `HardSixteenths`, `TwoHand`, `EasyTwoHandAnds`, `LowerHands`, `KickWeight`, `HardAndBackbeat`, `HardKickFigures`, `BusyHands`, `ThinKicks`, `HardHatDrops`, `UpperEighths`, `AllSlots`, `QuarterKickBar`, `HardEighthKicks`, `PairedKick`, `EndOfBarKick`, `LowerKicks`, `OneKickPerBar`, `KickUnderSnare`, `TimeCymbal`, `Between`, `SandwichedHats`, `DrumChanges`, `EasyBeforeCrash`, `MediumTomPairs`, `EasyLoneAnds`, `GemRank`, `CymbalChanges`, `TomBeforeCrash`, `AfterCrash`, `MaxGems`, `SectionTypes`, `EasyBeats`, `DoubleCrashes`, `OnsetValue`, `BreakEighthRuns`, `LowerEighthHands`, `EasySnareRuns`, `EvenRolls`

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
lib/reaper_imgui_helpers.lua   → Tooltip, SliderTooltip, SectionHeader, Btn*, FormatTime, GetTimeSelection
lib/reaper_helper_common.lua   → FindTrackByName, GetTakePPQPerQN, GetTempoContextBefore,
                                  RefreshTrackLists, RunAction
lib/reaper_helper_ui.lua       → TrackCombo (REAPER index, (none) = -1), MidiEditorTrackWarning,
                                  DrawResultPanel, DrawHelperFooter
lib/reaper_midi_helpers.lua    → FindFirstMIDIItem, InsertNotes, ClearNotesAtPitchesInRange, …
lib/reaper_guitar_theory.lua   → GuitarClassifyChordType, GuitarSuggestRBMapping (consulted by
                                  actions_guitar.lua's BuildShapeGemMap); GUITAR_TAB_OPEN (also used by
                                  actions_guitar_guide.lua's tab parsers)
lib/reaper_script_links.lua    → DrawGeneralLinksTab (General > Other tools)
lib/reaper_difficulty_score.lua, lib/reaper_difficulty_score_vocals.lua, lib/reaper_difficulty_tiers.lua
                               → DIFFICULTY_PRIMITIVES (Overdrive interest score), TIER_NAMES;
                                  the score modules are also what reaper_difficulty_read.lua calls
lib/reaper_difficulty_read.lua → FindTrackExact, ReadGemEvents, … (chart readers, shared with the
                                  General Helper's Metadata > Difficulty and dev/calibration/)
defaults.lua                   → S, TIPS
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → SetDefaultMIDITracks, SetDefaultDifficultyTracks
actions_drums.lua              → ConvertDrums
actions_drums_2x.lua           → DoubleBassPlan, MarkDoubleBassKicks,
                                  Remove2XKicks
actions_keys.lua               → SplitHands, ConvertProKeys, ConvertKeys5
actions_keys_guides.lua        → ProKeysTabGuide, VocalTabGuide, VocalTabBestShift, TabGuideEventRows
actions_guitar.lua             → ConvertGuitar, ValidateGuitar, GetBPMAt
actions_guitar_guide.lua       → ParseTabHorizontal, ParseTabVertical, ReformatVerticalTab, GuitarTabGuide
actions_guitar_validate.lua    → SustainThresholds, ReadRBGuitarNotes, RunValidation
actions_midi_align.lua         → AlignMIDI, ResizeAllMIDI
actions_midi_replace.lua       → GetPatternPitchRange, SetSearchPattern, SetReplacePattern,
                                  FillRange, DoMIDIPatternReplace, GoPrevPatternMatch,
                                  GoNextPatternMatch, ListPatternMatches
actions_midi_length.lua        → AdjustMidiNoteLengths
actions_difficulty_shared.lua  → CheckDifficultyProgression, CompressChordOffsets,
                                  DiffIssue, DiffCheckOverlaps, BuildDiffCheckReport, DiffReleaseGapQN,
                                  DiffReleaseGapName, DiffQNLabel, DIFF_RELEASE_GAP_* tables
actions_difficulty.lua         → CopyProKeysDiff, ValidateProKeysDiff, ValidateAllProKeys,
                                  CollectPKChecks, ReadPKTierEvents, PK_MAX_CHORD, PK_MAX_SPAN
actions_difficulty_5k.lua      → ValidateKeys5Diff, ValidateAllKeys5, CopyKeys5Diff,
                                  ReadK5TierEvents, CollectK5Checks, K5_* rule tables
actions_difficulty_gtrbass.lua → CopyGtrBassDiff, ValidateGtrBassDiff, ValidateAllGtrBass,
                                  ReadGBTierEvents, CollectGBChecks, GB_* rule tables
actions_difficulty_drums_checks.lua → DRUMS_RANGE, DRUMS_RULES, ReadDrumsTierEvents, CollectDrumsChecks
actions_difficulty_drums.lua   → CopyDrumsDiff, ValidateDrumsDiff, ValidateAllDrums
difficulty_generate_params.lua → GEN5_PARAMS, GEN5_* limits, Gen5PulseQN, Gen5Is44, Gen5BeatClass, Gen5MinGapQN,
                                  Gen5MinSustainQN, Gen5ReleaseGapQN (pure; first)
difficulty_generate_overlaps.lua → GEN_OVERLAP_MAX, GEN_OVERLAP_SPAN, GenMergeRolls, GenPlanOverlaps,
                                  GenNextAfterHold (pure; Keys/Pro Keys overlapping gems and rolled chords)
difficulty_generate_retime.lua → Gen5RetimeDenseRuns (pure; Hard's fast-run rewrite,
                                  called by Gen5SelectOnsets - load before it)
difficulty_generate_colors.lua → Gen5ReduceChordSize(Keys), Gen5KeysEasyMotion, Gen5NarrowSpan, Gen5ShiftSegments,
                                  Gen5ShiftBars, Gen5ClampOrShiftBars (pure; before the planner)
difficulty_generate_rhythm.lua → Gen5SelectOnsets, Gen5AndPhrases (pure; which onsets every planner keeps)
difficulty_generate_5lane.lua  → Gen5PlanTier (pure; Guitar/Bass/Keys)
difficulty_generate_prokeys.lua → GenPKPlanTier, GenPKReduceChord, GenPKBestWindow,
                                  GEN_PK_WINDOWS (pure; Pro Keys)
difficulty_generate_hopo.lua   → Gen5IsAutoHopo, Gen5MarkHopos, Gen5ForceHopoSpans,
                                  GEN5_HOPO_THRESHOLD_TICKS (pure; Hard force-HOPO markers)
difficulty_generate_drums.lua  → GenDrumsPlanTier, GenDrums2xInput, GenDrumsSinglePedal, GEN_DRUMS_PARAMS (pure; Drums - needs DRUMS_RULES,
                                  DoubleBassPlan
                                  and Gen5RetimeDenseRuns at call time)
actions_difficulty_generate.lua → GenerateDifficulties, GenInstrumentByKey,
                                  GenToPlannerEvents, GEN_INSTRUMENTS, GEN_ALL_KEY
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
ui_keys.lua                    → DrawKeysTab
ui_difficulty_generate.lua     → DrawDifficultyGenerateTab
ui_difficulty.lua              → DrawDifficultyTab
ui_overdrive.lua               → DrawOverdriveTab (reads OD_FILL_PACINGS at load time)
ui_midi_pattern.lua            → DrawMIDIPatternTab, ResetMIDIPatternState
ui_midi.lua                    → DrawTabInputTab, DrawMIDITab
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultMIDITracks(), SetDefaultDifficultyTracks()
```

The entry point sets `WINDOW_TITLE` right after `lib/reaper_imgui_helpers.lua` loads (it defines `ScriptWindowTitle`) and before `ui.lua`.

**`SCRIPT_MDIR` global.** The entry point sets `SCRIPT_MDIR = _mdir` (global) so dofile'd modules can access the module folder path for filesystem operations. The `local _mdir` variable is not accessible from dofile'd modules. **`SCRIPT_DIR` global.** The entry point also sets `SCRIPT_DIR = _dir` (repo root) for accessing shared resources under `resources/` (e.g. `resources/themes/`, `resources/img/spritesheets/`).

**Second entry point: `rock_band_midi_pattern_vkr.lua` (repo root).** Standalone MIDI Pattern window. No module folder of its own either — it dofiles `lib/reaper_imgui_helpers.lua`, `lib/reaper_helper_common.lua`, `lib/reaper_helper_ui.lua`, `lib/reaper_midi_helpers.lua`, then this helper's `defaults.lua`, `actions_midi_replace.lua`, `ui_midi_pattern.lua`, and runs its own minimal `Loop`: `DrawMIDIPatternTab()` + `DrawResultPanel()` in a scroll body, then the shared footer (`DrawHelperFooter({})` - Copy result, Undo; its track list refreshes through `MakeProjectPoll` like the helpers'). Consequences when editing those files:
- The subset must keep working without the rest of the instrument helper loaded. In particular `ui_midi_pattern.lua` may not grow a dependency on `ui_midi.lua`, `settings.lua` or any venue/difficulty module.
- **`ui.lua` is deliberately not in the list and must never be added**: its last line is a bare `r.defer(Loop)`, which would spawn the full helper window. That is the whole reason `TrackCombo` and the status/result panel were moved out into `lib/reaper_helper_ui.lua` (first `lib/reaper_helper_ui.lua`) — the same split the vocal helper made for its standalone tuner.
- It sets neither `SCRIPT_DIR` nor `SCRIPT_MDIR` — nothing in this subset reads them .
- Unlike the other standalones it calls **neither `LoadSettings()` nor `SaveSettings()`**: the Pattern sub-tab has never persisted anything (its `S.mr_*` fields are session-only and `settings.lua` has no key for them), and no `SetDefault*Tracks` function assigns `mr_midi_src_idx`. If a Pattern setting is ever made persistent, this window needs `settings.lua` added and `LoadSettings()` called at startup + on project switch.
- Both entry points call `ResetMIDIPatternState()` on project switch. The captured Search/Replace patterns are take-relative PPQ offsets whose labels name the previous project's measures, so carrying them over would silently target the wrong material.
- **A fix to any file in that subset changes this window too, so it needs its own `@version` bump and its own `@about` entry** in the same task as the instrument helper's — otherwise its version silently stops describing the code it runs. Nearly everything this window draws is shared, so it is the standalone most often affected. See `CLAUDE.md` → "Bumping a helper means checking its standalones".

### Save / Load

Section `RBInstrumentHelperVKR`, key `settings_v1` — its own key, so saving in one helper never overwrites the other's settings. Auto-loads on script open and on project switch. Values these tabs saved under the General Helper's `RBHelperVKR` key before the split are deliberately not read back (a fresh start, the user's choice); the General Helper's next Save drops them from its blob.

**Saved:** the MIDI converter options (`mc_*`, except track indices), the Tab Input format and mode (`mc_gtr_tab_format`, `tab_input_mode`), the Difficulty tab's Guitar/Bass instrument radio (`diff_gb_instrument`) and the Keys sub-tab's "Reduce using Pro Keys" checkbox (`diff_5k_pk_reduce`), MIDI Alignment and Length (`ma_mode`, `mn_*`), `show_wip_tabs`, and every Overdrive tab setting (`od_group`, the three include checkboxes, `od_beats_per_phrase`, `od_unison_share`, `od_keepout_start`, `od_together`, `od_vocal_overlap`, `od_keepout_od`, `od_keepout_unison`, `od_fill_pacing`, `od_fill_sections`, `od_fill_skip_early`, `od_fill_keepout_end`, `od_vocal_every`). `od_pending` and `od_overview` are session-only and cleared on project switch; so are Difficulty > Generate's choices (`diff_gen_*`).
**Not saved:** track indices — positional, brittle. `SetDefaultMIDITracks` re-detects PART DRUMS and PART GUITAR target tracks by name; `SetDefaultDifficultyTracks` re-detects all Difficulty-tab tracks (Pro Keys, Keys, Guitar/Bass, Drums, PART DRUMS_2X) by name. Both only assign fields that are still -1.

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
1. A `[prc_*]` section **change** moves the fill to it.
2. Otherwise a **drum crash** does, nearest the slot first. A crash is a blue or green *cymbal* on a downbeat (`OdCrashBars`). Pro Drums tom markers 111/112 turn those gems into toms, and yellow is left out because it's the hi-hat.
3. Otherwise the fill stays on the grid.

**The pacing is a minimum** (user rule). Two kept fills never end closer than N measures apart. A section change closer than that still gets its fill, and the previous fill is removed instead (reported as "gave way to a fill into a section change"). A gap of 6 or 7 measures to the fill before is fine. A previous fill that itself leads into a section change is kept, and the closer section gets none. Crashes and the grid only move a fill to N measures or later. The old rule let alignment end a fill half the pacing after the previous one. With 2-bar fills at 193 BPM that left 2.49 s between them, and over the RB3 DLC (hold-out excluded) it produced a sub-2.5 s gap in 119 of 483 songs.

**Magma's 2.5 s rule** (`OD_FILL_MIN_GAP_SEC`): Magma refuses to build a song when a fill starts less than 2.5 s after the previous fill ends. The planner skips such a slot ("under 2.5 s after the previous fill"), and Validate reports it as an error. Seconds come from the bars' start times (`OdQNToSec`), so the planner stays pure.

**Section change vs subsection** (`model.section_change_bars`, `OdSectionFamily`). Charters split sections into practice subsections (`chorus_1a` → `chorus_1b`, `intro_a` → `intro_b`), and official charts do so often. `OdSectionFamily` drops a last word that is a number, a number plus one letter, or a single letter. A start counts as a change only when that family differs from the previous section's, so a back-to-back `chorus_1` → `chorus_2` is not a change either. A subsection still lines a fill up, but only at the full pacing or later, and it never replaces a fill. Matching official fill ends over the RB3 DLC: subsections ignored entirely 76.0%, this rule 77.2%, subsections treated as changes 78.2%. The user chose the middle option. `model.section_bars` (every start) still feeds the bar-interest score. The unison-before-a-section rule (`YieldableFill`) reads `section_change_bars`, so it agrees with the fills.

**Auto pacing** (`OdAutoFillPacing`): half a bar every 2 at 75 BPM or slower, otherwise 1 bar every 4. The RBN doc's "2 bars every 8 when very fast" is not what official charts do. At 170+ BPM, RB3 DLC fills are one bar long 91–98% of the time and 2 bars ~0%, and 69–82% come every 4 bars, the same as at 120–170 BPM. The 2-bar pacing stays as a manual choice.

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
- a fill starting less than 2.5 s after the previous fill ends (Magma refuses to build the song);
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

`dev/tests/instrument_overdrive.lua` (runner `run_instrument_overdrive.lua`, launcher button "Overdrive Tests"):
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
back to 96. `DoubleBassPlan(qns, is_downbeat, bar_pos)` is the whole rule set as a pure
function (`bar_pos(qn)`, quarter notes from the bar line, is optional: without it
rule 6 is skipped) — quarter-note positions in, a parallel array of booleans out — so it is
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

6. **Bar-position ranking**, for a line on the straight 1/16 grid that rules 4-5
   take kicks from. Counting means where the count starts decides which kicks
   stay: a lone 1/8 set aside by rule 2 flips the phase, and a mixed figure such
   as `e a | 3 e &` (beat 3 under a crash) loses beat 3 and its "and" and keeps
   the 16ths. So the kept kicks are re-chosen by weight - downbeat 8, beat 5,
   "and" 3, 1/16 1.5 (`PRIORITY_W`, the Generate drums planner's ranking) - the
   highest total with kept kicks at least twice the line's tightest gap apart,
   so a 1/16 stream still halves to 1/8s on the beat side; a tie keeps more
   kicks (`PriorityPicks`, weighted interval scheduling over the untrimmed line).
   **Not used** on a line with any kick off the 1/16 grid - on a triplet grid the
   beat comes every third note, so ranking by position cannot alternate evenly
   (applied there it cost 283 and 338 kicks of agreement on two triplet-feel
   songs) - or with a straight run of more than `MAX_EIGHTH_RUN` 1/8s, which keep
   rule 4's alternation. A downbeat is never taken (guarded: the rule declines).

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
- Rule 6 was fitted on community "(2x Bass Pedal)" RBN releases against their own
  one-pedal versions (31 songs, 43,206 2x kicks): agreement with the authors'
  one-pedal kicks 38,036 -> 38,989. Those authors follow no shared guideline and a
  few of them chart many of the songs, so it is a direction, not a target. Both
  reference charts are unchanged (1080/1080 and 577/577). The same comparison showed
  three differences that were **not** adopted (author preference, not a rule):
  long straight-1/8 runs kept whole on one pedal, slow 1/16 runs kept whole (both
  about the foot's speed - below about 7 kicks a second), and two kicks a 1/16
  apart both kept.

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
