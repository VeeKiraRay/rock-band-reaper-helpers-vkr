# General Helper — Script Documentation

`rock_band_general_helper_vkr.lua` provides Rock Band authoring utilities: tempo map generation from drum audio, audio track alignment, MIDI converter tools (drums, keys, guitar), MIDI alignment, and VENUE event validation.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

Five stable tabs are always visible: **General | Difficulty | Tab Input | MIDI | Venue**

Four WIP tabs appear only when **Show WIPs? = Yes** in the General tab (persisted setting, default No): **Tempo Map | Drums | Keys | Guitar**. These tabs function at a basic level but have known issues and are not ready for general users.

**General tab** — audio alignment and settings persistence. Contains three sub-tabs:

*Actions sub-tab*
- **Refresh tracks** — re-scans the project's track list.
- **Align all audio** — aligns every audio item on every track to a common reference position.
- **Align count-in** — positions the COUNT IN clip relative to the first measure.
- **Song fade out** — creates a fade-out automation envelope on the master track at the end of the project.

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
  `x x x 7 7 5`, root+5th+octave) — that collapses to the same 2-gem combo a literal
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

**Difficulty tab** — difficulty validation and copy-to-next-tier tools. Contains four sub-tabs. Each sub-tab has the same two rows: **Copy to Hard / Medium / Easy** actually writes notes (see below), and **Validate Expert / Hard / Medium / Easy / All** checks the actual authored notes in that difficulty's own pitch range (read-only). All actions respect time selection.

**Copy to X** (`Copy*Diff(diff_label, force)` in each module) replaces the tab's former read-only "Suggest" preview — it copies notes from the *immediately higher* adjacent tier (Copy to Hard ← Expert, Copy to Medium ← Hard, Copy to Easy ← Medium — the same `ADJACENT_HIGHER` mapping the progression check below uses) onto the target tier's own track/range, giving the user a real starting point to hand-edit down. Two safeguards: if the source has no notes, it early-exits with a status/report message and writes nothing; if the target already has notes, it sets `S.diff_copy_pending = { message, on_confirm }` instead of writing, which opens a shared confirm-overwrite modal popup (`ConfirmCopyOverwrite`, rendered once at the end of `DrawDifficultyTab` regardless of which sub-tab triggered it — the first modal popup in this codebase) with "Clear and Copy" (re-calls the same function with `force = true`) / "Cancel" buttons. Copies gem/playable notes only — no force-HOPO/trill/roll/fill/disco-mix markers, since those either don't apply to the target tier or are shared fixed-pitch overlays not meant to be duplicated per difficulty. **Pro Keys is the one exception**: since its lane-shift markers (0–9) are essential for the track to make sense at all (not an optional overlay), it copies its entire note set — gems and markers alike — verbatim between tracks (no pitch transform needed either, since its range doesn't shift between tiers). Fully undoable.

**Keys and Guitar/Bass color compression**: both narrow their gem count at Medium/Easy by RBN convention (all 5 colors exist at every tier internally; Medium/Easy just don't use the upper ones). `CompressChordOffsets` (`actions_difficulty_shared.lua`) handles a source chord that uses a color above the target's ceiling: a single note or 2-note chord is shifted down as a whole (preserving its interval) when every note stays ≥ offset 0 — e.g. Hard's Orange+Blue → Medium's Blue+Yellow; otherwise (3+ note chords, or a 2-note chord that would go negative) any note above the ceiling is simply dropped. Drums doesn't need this (every tier has the same 5 lanes, hi-lo=4 always, so the function is a no-op there) but calls it anyway for consistency with Keys/Guitar-Bass's copy functions.

Every Validate action (all four sub-tabs, H/M/E only — never Expert) also runs a shared cross-difficulty progression check (`CheckDifficultyProgression` in `actions_difficulty_shared.lua`) against the immediately higher adjacent tier: flags an unedited copy (identical event count, timing, and normalized pitch shape — i.e. no reduction was actually authored; this is the case right after a fresh "Copy to X" with no further edits, by design), and reports the two tiers' individual note counts, requiring the lower tier to have fewer notes (e.g. `"Expert has 500 notes and Hard has 450 notes: OK"` / `"...: NOT REDUCED"`). Both findings count toward the report's issue total and are prepended right after the header, before the rule-by-rule breakdown. Skipped gracefully when the higher tier's track/range has no notes (nothing to compare against).

*Pro Keys sub-tab* — validates PART REAL_KEYS_X/H/M/E (one track per difficulty).
- **Validate Expert / Hard / Medium / Easy / All** — check against RBN Pro Keys authoring rules: chord count/span, interval jumps, spacing (M/E), lane range markers.
- Track indices auto-detected by name (PART REAL_KEYS_X/H/M/E).
- Only notes in the playable Pro Keys range (48–72, C2–C4) are read as chord/gem events; reserved marker pitches (overdrive 116, glissando 126, trill 127) and any other out-of-range note are excluded before chord/span/jump/spacing/overlap grouping, so they can never masquerade as huge chords/jumps (`GroupIntoEvents` in `actions_difficulty.lua`). There is no longer a standalone "note range" check — filtering happens before events are built, so nothing outside 48–72 ever reaches a check.

*Keys sub-tab* (formerly "5-Lane Keys") — validates PART KEYS (all four difficulties on one track in separate pitch ranges).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–75 | Easy: 60–62.
- **Validate Expert / Hard / Medium / Easy / All** — check chord count, spacing (M/E), note length, sustain gaps.
- Track index auto-detected by name (PART KEYS).
- **Reduce using Pro Keys (same tier)** — checkbox above the Copy row, checked by default, persisted (`S.diff_5k_pk_reduce`). When `Copy to Hard/Medium/Easy` runs with this on, `CopyKeys5Diff` keeps only copied events that land on a note in the matching-tier Pro Keys track (`PART REAL_KEYS_H/M/E`, via `ReadProKeysEvents` + `FindNearbyPKEvent`, tolerance `PK_REDUCE_TOLERANCE_QN` = 1/32 note in quarter-note space — tightened from an initial 1/16 note, which left too many events kept at faster tempos) — mirrors a difficulty reduction already hand-charted on Pro Keys onto the Keys copy, instead of copying every event from the tier above unfiltered. Kept events also get their sustain length matched to the Pro Keys event's length (end minus start, re-anchored at the Keys event's own start via `TimeMap2_QNToTime`) rather than keeping the copied source tier's own length, so both charts agree on note length (not just onset) — Pro Keys is the master chart both are reduced from, and sustain-gap rules require the two to match. Dropped events are simply omitted before `CompressChordOffsets` runs on the survivors. If the matching Pro Keys track isn't selected, missing, or empty, Copy falls back to an unfiltered copy (source length kept as-is) and the status line explains why. Mirrors the user's usual charting order: Pro Keys first (hand-reduce Expert→Hard→Medium→Easy), then Keys, using Pro Keys' already-decided rhythm and note lengths as the reduction guide. Keys-only — Guitar/Bass, Drums, and Pro Keys itself don't have this option.

*Guitar/Bass sub-tab* — validates PART GUITAR or PART BASS (instrument radio switch; Guitar and Bass share one RBN rule set — the doc treats them as one spec with only cosmetic differences — so this sub-tab and `actions_difficulty_gtrbass.lua` are shared between both, parameterized by `instrument` ∈ `'gtr'`/`'bass'`).
- Expert: 96–100 | Hard: 84–88 | Medium: 72–75 (no Orange) | Easy: 60–62 (Green/Red/Yellow only).
- **Validate Expert / Hard / Medium / Easy / All** — chord count; chord shape (illegal 3-note Green+Orange on Expert, per-difficulty max span — no Green+Orange on Hard, no Green+Blue on Medium, no chords on Easy; a 2-note Green+Orange chord on Expert is an advisory, not a hard failure); note length (min 1/64, reuses `SustainThresholds` from `actions_guitar_validate.lua`); overlap; sustain gaps (1/32 min on Expert/Hard, 1/4 note on Medium/Easy); an advisory-only note-density grid (quarter-note target on Medium, half-note on Easy — qualitative in the source doc, not chart-breaking); force-HOPO markers (notes F/F#, offset `lo+5`/`lo+6` — disallowed on Medium/Easy); and trill/tremolo marker velocity (pitches 126/127, fixed regardless of difficulty — velocity ≤40 is flagged only when validating Hard, since that's the only tier the doc gives a numeric threshold for: 41–50 required for Hard eligibility, else Magma reports a spacing error).
- Track fields (`diff_gtr_idx`/`diff_bass_idx`) auto-detected by name (PART GUITAR/PART BASS) — independent of the Guitar tab's own conversion target-track field.

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

*Pattern sub-tab* — find, replace, and navigate a note pattern across a MIDI track.
- Source track selector; **Set Search** / **Set Replace** capture the currently-selected notes in the active MIDI editor as the search/replace patterns.
- **Replace All** applies the replace pattern wherever the search pattern is found; **Fill Range** repeats the replace pattern across the time selection.
- **Go Prev** / **Go Next** move the edit cursor to the nearest Search-pattern match before/after the current cursor position; **List Search** reports every match with its measure/time location (read-only, populates the shared result panel). All three share the same match-scanning walk as Replace All (`ScanPatternMatches`) and respect time selection the same way (falls back to the whole MIDI item).

**Venue tab** — VENUE and EVENTS MIDI track events. Contains six sub-tabs (plus Preview):

*Actions sub-tab* — inspection tools, plus a couple of generation actions.
- **List venue events** — validates the VENUE track against the Rock Band Network spec: track name event, event type checks, unknown events, consecutive camera repeats, directed cut spacing, camera gap statistics, event usage frequency. Read-only.
- **List event sections** — reads `[prc_*]` markers from the EVENTS track and lists detected song sections with time ranges. Letter-suffix variants, including letter-only forms with no number (`[prc_verse_a]`/`[prc_verse_b]`) and numbered forms (`[prc_verse_1a]`/`[prc_verse_1b]`), are merged into a single section entry. Read-only.
- **List lighting/postproc** — finds every `[lighting*]` and `*.pp]` (postproc) text event on the VENUE track and lists them in timeline order of appearance, each with its measure/timestamp. Read-only.
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

**Blend-in rule** (Themes gen and Section gen): `lightpreset_blendin` / `postproc_blendin` do **not** move a section's own lighting/postproc event earlier — those always sit on the section start. The value says how many beats ahead of the boundary the **outgoing** preset is duplicated, as an anchor for the game to blend from. `BlendPpq` / `EmitBlendDuplicates` (`venue_lighting.lua`) own the rule; `.claude/CLAUDE_venue_theme_generation.md` has the worked example and every skip condition. `GenerateThemedSectionEvents` resolves all sections' picks in a first pass before emitting, because emitting a section needs the *previous* section's preset — both to duplicate into the blend zone and to tell whether this section changes anything at all; its optional `incoming` argument supplies the preset state before the first section (Themes gen: the song-start bookend; Section gen: `FindActiveVenuePresetsBefore` off the track). The duplicate carries no keyframes of its own — see the keyframe rule below.

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
| `rock_band_general_helper_vkr/venue.lua` | `ListVenueEvents`, `GetVenueEventsForPreview` (global); `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats` (local) |
| `rock_band_general_helper_vkr/venue_awareness.lua` | `GetMutedInstruments`, `GetCoopRequiredInstruments`, `GetDirectedRequiredInstruments`, `FilterPool`, `ReadEventSections`, `ListEventSections`, `FindEventTime` (generic EVENTS-track text-event lookup), `FindMusicStartTime` (thin wrapper over `FindEventTime`), `INST_LETTER_NAMES` (global); `INST_TRACK_NAMES`, `ParsePrcEvent` (local) |
| `rock_band_general_helper_vkr/venue_themes.lua` | `ThemeDisplayLabel`, `LoadVenueThemes`, `GetSectionPreset`, `GetThemeCameraInterval`, `BuildLightingPool`, `BuildPostprocPool` (global); `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme` (local) |
| `rock_band_general_helper_vkr/venue_camera.lua` | `COOP_POOL`, `DIRECTED_POOL`, `PickRandom`, `JitteredInterval`, `CategorizeCoopPool`, `WeightedPickCoopEvent`, `FindCompanion`, `ComputeIdleState`, `GenerateCameraEvents`, `ResolveUserCamInterval` (global); camera constants (`CAM_INTERVAL_16THS` etc., partially global); `WeightedPickInstrument` (local) |
| `rock_band_general_helper_vkr/venue_sprites.lua` | `LoadVenueSprite`, `DrawVenueTooltipSprite`, `BeginVenueTooltip`, `EndVenueTooltip`, `VenueSpriteFoldersFound` (global); `DIRECTED_SPRITE_NAMES`, `VENUE_SPRITE_ROOT` (module-level globals). JPEG-only. Checks `resources/img/spritesheets/{category}/` (large) then `resources/img/spritesheets/{category} small/` (small) — no third-party fallback. Frame count is read from the filename (`{key}_f{N}_spritesheet.jpg`). Display size scales by `S.venue_preview_scale` (1 or 2). Cache stores `{image, frame_count, cols, rows}` per sprite. |
| `rock_band_general_helper_vkr/venue_lighting.lua` | `MANUAL_LIGHTING_SET`, `LIGHTING_OFFSET_16THS`, `INST_KF_MODES`, `KF_ALIGN_LABELS`, `FindNextMeasureStartPpq`, `CollectInstNotePositions`, `GenerateKeyframesForSpan`, `GenerateLightingEvents`, `GenerateThemedSectionEvents`, `SnapPpqToHalfBeat` (global); `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, lighting constants, `SnapPpqToNearestBeat`, `BlendPpq`, `EmitBlendDuplicates`, `ResolveThemeSection`, `EmitThemeSection` (local) |
| `rock_band_general_helper_vkr/venue_generator.lua` | `GenerateVenueEvents`, `DeleteTextEventsInRange` (predicate-driven deleter backing all clear functions), `ClearVenueTextEventsInRange`, `ClearVenueNonCameraEventsInRange`, `ClearVenueExceptLPInRange`, `ClearVenueKeyframesInRange`, `FindActiveVenuePresetsBefore` (global) |
| `rock_band_general_helper_vkr/workflow.lua` | `ParseWorkflowContent`, `ParseWorkflowFile`, `LoadWorkflowFiles`, `EscapeWF`, `UnescapeWF` (global); `FindBraceGroups`, `StripBraceGroups` (local) — Workflow sub-tab's `.txt` template parser (pure over string content) + `resources/workflow/` folder scanner |
| `rock_band_general_helper_vkr/actions_workflow.lua` | `CompositeKey`, `PruneToWorkflowEntries`, `SaveWorkflowState`, `LoadWorkflowState`, `SelectWorkflowFile`, `ToggleWorkflowItem`, `ComputeWorkflowStats` (global) — Workflow checklist state, persistence (`workflow_v1` ExtState key), template-switch pruning, and the pure progress-count helper |
| `rock_band_general_helper_vkr/tempomap.lua` | `ComputeTempoRMSContour`, `DetectOnsets`, `EstimateBPM`, `GuessTimeSig`, `GetSourcesForRange`, `FitBeatGrid`, `RmsToOnsetFlux`, `FindLocalPeak` |
| `rock_band_general_helper_vkr/actions.lua` | `AlignAudioTracks`, `AlignAllAudio`, `AlignCountIn`, `CreateSongFadeOut`; `CountInBeatSlots` (local) |
| `rock_band_general_helper_vkr/actions_tempomap.lua` | `ShowTempoContext`, `EstimateInitialBPM`, `AutoTuneThreshold`, `ClearGeneratedTempoMarkers`, `GenerateTempoMap`; `BPM_MIN`, `BPM_MAX` (locals) |
| `rock_band_general_helper_vkr/actions_drums.lua` | `ConvertDrums` (global); `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport` (local) |
| `rock_band_general_helper_vkr/actions_keys.lua` | `SplitHands`, `ConvertProKeys`, `ConvertPianoToProKeys`, `ConvertKeys5` (global); `PK_MIN`, `PK_MAX`, `PK_RANGES`, `PK_PREF_LABEL` (module-level globals); `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord` (local) |
| `rock_band_general_helper_vkr/actions_keys_guides.lua` | `ProKeysTabGuide`, `VocalTabGuide` (global); `PkEventLabel`, `ParseTabToRaws` (local) |
| `rock_band_general_helper_vkr/actions_guitar.lua` | `ConvertGuitar`, `ValidateGuitar`, `GetBPMAt`, `CompressChord`, `GemLabel`, `PitchLabel`, `ChordTypeName`, `BuildShapeGemMap`, `ChordQualityLabel` (global); `GEM_MIN`, `GEM_MAX`, `GEM_LETTERS`, `CHORD_WINDOW_S`, `POOLS`, `POOLS2_NO14` (module-level globals) — Expert gem generation and authoring rule validation. `BuildShapeGemMap` (shared with `actions_guitar_guide.lua`) is the global shape→gem-combo map builder; every 2+-note shape consults `GuitarSuggestRBMapping` (`lib/reaper_guitar_theory.lua`) BY PITCH CLASS (not physical note count) so e.g. a power chord — even voiced with a doubled root across 3 strings — always gets a 1-3-spread 2-gem combo. When a group has more distinct shapes than available combos, `AssignByConflict` gives the first (lowest-pitched) shapes a unique combo each, then assigns each overflow shape whichever already-claimed combo minimizes conflicts against shapes it's actually adjacent to anywhere in the passage (an adjacency table built from the real event sequence, restricted to same-group consecutive pairs), tie-broken toward the top of the pool and refined over a few bounded sweeps — returned as a third `shared` map so callers can flag reused combos; `ChordQualityLabel` names the recognized shape (e.g. `[Power chord]`) for the reason string |
| `rock_band_general_helper_vkr/actions_guitar_guide.lua` | `ParseTabHorizontal`, `ParseTabVertical`, `ReformatVerticalTab`, `GuitarTabGuide` (global); `AssignGemsForGuide` (local) — guitar Tab Input guide; `AssignGemsForGuide` delegates its shape→gem map to `BuildShapeGemMap` (`actions_guitar.lua`) |
| `rock_band_general_helper_vkr/actions_guitar_validate.lua` | `SustainThresholds`, `ReadRBGuitarNotes`, `RunValidation` (global) — validation helpers called by `ValidateGuitar` |
| `rock_band_general_helper_vkr/actions_midi_align.lua` | `AlignMIDI`, `ResizeAllMIDI` (global) |
| `rock_band_general_helper_vkr/actions_midi_replace.lua` | `GetPatternPitchRange`, `SetSearchPattern`, `SetReplacePattern`, `FillRange`, `DoMIDIPatternReplace`, `GoPrevPatternMatch`, `GoNextPatternMatch`, `ListPatternMatches` (global); `BuildPatternLabel`, `PatternsMatch`, `ClearPatternWindow`, `GetTrackAndTake`, `ResolvePatternScope`, `ScanPatternMatches`, `GoToPatternMatch` (local) |
| `rock_band_general_helper_vkr/actions_midi_length.lua` | `AdjustMidiNoteLengths` (global) — Midi note length/sustain-gap adjustment; `NoteLenPPQ`, `AdjustAllNoteLengths`, `AdjustSustainGaps` (local) |
| `rock_band_general_helper_vkr/actions_difficulty_shared.lua` | `CheckDifficultyProgression`, `CompressChordOffsets` (global) — cross-difficulty identical-chart + note-count reduction checks, and the color-compression helper used by Keys/Guitar-Bass's Copy functions, shared by all four difficulty modules below |
| `rock_band_general_helper_vkr/actions_difficulty.lua` | `CopyProKeysDiff`, `ValidateProKeysDiff`, `ValidateAllProKeys` (global) — Pro Keys difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_5k.lua` | `ValidateKeys5Diff`, `ValidateAllKeys5`, `CopyKeys5Diff` (global) — Keys (formerly "5-Lane Keys") difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_gtrbass.lua` | `CopyGtrBassDiff`, `ValidateGtrBassDiff`, `ValidateAllGtrBass` (global; take `instrument` = `'gtr'`\|`'bass'` as first param) — shared Guitar/Bass difficulty rules |
| `rock_band_general_helper_vkr/actions_difficulty_drums.lua` | `CopyDrumsDiff`, `ValidateDrumsDiff`, `ValidateAllDrums` (global) — Drums difficulty rules |
| `rock_band_general_helper_vkr/ui_keys.lua` | `DrawKeysTab` (global) — Keys tab rendering |
| `rock_band_general_helper_vkr/ui_difficulty.lua` | `DrawDifficultyTab` (global) — Difficulty tab rendering (Pro Keys, Keys, Guitar/Bass, Drums sub-tabs) |
| `rock_band_general_helper_vkr/ui_midi.lua` | `DrawTabInputTab`, `DrawMIDITab` (global) — Tab Input and MIDI tab rendering |
| `rock_band_general_helper_vkr/actions_venue_manual.lua` | `InsertVenueEventAtPlayhead`, `AdvanceCameraPacing`, `GenerateManualKeyframes`, `RemoveVenueEventsByType`, `FindManualLightingAtPpq`, `FindNextVocalPhraseStartPpq`, `ResolveBlendSource`, `BlendVenuePresetAtPlayhead`, `NO_LIGHTING_AT_PLAYHEAD_MSG` (global); `_spot_tol` (local) — Manual gen actions |
| `rock_band_general_helper_vkr/section_events.lua` | `SECTION_EVENT_GROUPS`, `SECTION_EVENT_BASE` — EVENTS-track event vocabulary (groups, per-base number/letter caps) for the Events sub-tab; data only, no S/REAPER deps |
| `rock_band_general_helper_vkr/actions_venue_events.lua` | `FindEventsTake`, `ScanEventsTextEvents`, `NextSectionEvent` (pure), `ValidatePlainInsert` (pure), `InsertEventsEvent`, `AddSectionEvent`, `ClearAllEventsTexts`, `InsertEventsBookends` (global) — Events sub-tab actions + validation |
| `rock_band_general_helper_vkr/actions_venue_keyframes.lua` | `RegenerateVenueKeyframes` (global) — Keyframes tab action: bulk-regenerates keyframes for every manual lighting event on the VENUE track |
| `rock_band_general_helper_vkr/actions_venue_sing_along.lua` | `GenerateSingAlong` (global) — Analysis tab action: derives VENUE pitch 85/87 sing-along notes from HARM2/HARM3 vocal phrases; `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans` (local) |
| `rock_band_general_helper_vkr/actions_venue_subtracks.lua` | `VENUE_SUBTRACKS`, `CategorizeVenueEvent` (the shared 6-way event classifier, also used by `actions_venue_manual.lua`'s `RemoveVenueEventsByType`), `FindOrCreateSubtrack`, `EnsureMatchingItem`, `CopyVenueEvents` (logic helpers, global for testability), `CopyVenueToSubtracks`, `CopyAllSubtracksToMain`, `CopySelectedSubtrackTo`, `CopySelectedSubtrackFrom` (global) — Actions tab's "Sub VENUE tracks" split/merge feature; `_find_venue_track_and_take` (local) |
| `rock_band_general_helper_vkr/ui_venue.lua` | `DrawVenueTab`, `RenderCamPacingRow`, `RenderKeyframeAlignCombo` (global) — Venue tab bar (Actions, Events, Themes gen, Section gen, Manual gen, Keyframes, Preview; only Actions and Themes gen are drawn inline — every other sub-tab delegates to its own file) plus the camera-pacing / keyframe-align widgets shared by the generation sub-tabs |
| `rock_band_general_helper_vkr/ui_venue_section_gen.lua` | `DrawVenueSectionGenTab` (global) — Section gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_manual.lua` | `DrawVenueManualTab` (global) — Manual gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_events.lua` | `DrawVenueEventsTab` (global) — Events sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_preview.lua` | `DrawVenuePreviewTab` (global) — Preview sub-tab rendering; caches the VENUE event lists + muted instruments, refreshed on any project state change with a 5 s fallback and a self-pause when one read takes ≥ 0.15 s |
| `rock_band_general_helper_vkr/ui_venue_players.lua` | `DrawActivePlayersRow` (global) — Active players dot row shown under every Venue sub-tab and in the standalone preview; PART-track play-state scan cached via `MakeProjectPoll(1.0, 5.0)`, playhead lookup recomputed on playhead change (≥ 0.5 s cadence during playback) |
| `rock_band_general_helper_vkr/ui_venue_keyframes.lua` | `DrawVenueKeyframesTab` (global) — Keyframes sub-tab rendering |
| `rock_band_general_helper_vkr/ui_workflow.lua` | `DrawGeneralWorkflowTab` (global) — General > Workflow sub-tab rendering |
| `rock_band_general_helper_vkr/ui.lua` | `TrackCombo` (global override supporting `sel_idx=-1`), `Loop`, `r.defer(Loop)` |

**Local-only functions:**
- `settings.lua`: `SerializeSettings`, `DeserializeSettings`
- `venue.lua`: `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats`
- `venue_awareness.lua`: `INST_TRACK_NAMES`, `ParsePrcEvent`
- `venue_themes.lua`: `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme`
- `venue_camera.lua`: `WeightedPickInstrument`; camera constants `CAM_DIRECTED_COOLDOWN`, `DIRECTED_MIN_COUNT`, `DIRECTED_MAX_COUNT`, `INST_WEIGHTS`, `INST_ORDER`, `IDLE_WEIGHT`
- `venue_sprites.lua`: `_sprite_cache`, `_sprite_dirs_found`, `NormalizeSpriteKey`, `_try_load_from_dir`, `FindAndLoadSprite`, `_CAT_FOLDER`, `POSTPROC_SPRITE_NAMES`; `SPRITE_COLS`, `SPRITE_ROWS`, `SPRITE_FRAME_RATE`, `SPRITE_DISPLAY_W`, `SPRITE_DISPLAY_H`
- `venue_lighting.lua`: `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, `LIGHTING_INTERVAL_16THS`, `LIGHTING_JITTER`, `KEYFRAME_MIN_BEATS`, `KEYFRAME_MAX_BEATS`, `SnapPpqToNearestBeat`, `BlendPpq`, `EmitBlendDuplicates`, `ResolveThemeSection`, `EmitThemeSection`
- `actions_venue_sing_along.lua`: `RB3_VOCAL_MIN`, `RB3_VOCAL_MAX`, `RB3_PHRASE_PITCH` (module-level locals), `AvailableHarmTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans`
- `actions_venue_events.lua`: `_round_ppq`, `_is_crowd`, `_bare_form`, `_letter_form`, `_family_span`, `_spot_conflict`, `_require_take`, `_insert`, `_refuse`; `BOOKEND_EVENTS` (module-level local)
- `workflow.lua`: `FindBraceGroups`, `StripBraceGroups`
- `ui_venue_events.lua`: `_draw_prc_row`, `_draw_plain_row`
- `actions.lua`: `CountInBeatSlots`
- `actions_tempomap.lua`: `BPM_MIN`, `BPM_MAX` (module-level locals)
- `actions_drums.lua`: `BuildMap`, `ReadMIDINotes`, `ClearDrumNotes`, `BuildDrumOutput`, `BuildReport`
- `actions_keys.lua`: `ReadMIDINotesWithChannel`, `IsRightHand`, `ClearAllNotesInTimeRange`, `WriteNotesToTrack`, `CompressChord`
- `actions_keys_guides.lua`: `PkEventLabel`, `ParseTabToRaws`
- `actions_guitar.lua`: `ReadGuitarMIDI`, `GroupIntoEvents`, `IsIllegalGO`, `AssignGems`, `BuildPreviewReport`, `BuildOutNotes`, `ClearGuitarGems`, `PoolByWidth`, `WIDTH_TO_SPREAD`, `MAX_CONFLICT_SHAPES` (module-level locals), `shape_key`, `sort_by_pitch`, `AssignByConflict`
- `actions_guitar_guide.lua`: `AssignGemsForGuide`
- `actions_difficulty_shared.lua`: `ChartsAreIdentical`
- `actions_difficulty.lua`: `ADJACENT_HIGHER` (module-level local); `EventLabel`, `ReadPKNotes`, `GroupIntoEvents`, `GetBeatDurAt`, `QNAt`, `CountNotes`, `CheckChordCount`, `CheckChordSpan`, `CheckIntervalJumps`, `CheckSpacing`, `CheckLaneShifts`, `CheckNotesAboveExpert`, `BuildReport`, `RunPKValidation`
- `actions_difficulty_5k.lua`: `ADJACENT_HIGHER`, `PK_LANE_SHIFT_PITCHES`, `PK_PLAYABLE_LO`, `PK_PLAYABLE_HI`, `PK_REDUCE_TOLERANCE_QN` (module-level locals); `ReadK5Notes`, `GroupK5Chords`, `GetK5BeatDur`, `QNAt`, `CountNotes`, `K5Label`, `ReadProKeysEvents`, `FindNearbyPKEvent`, `CheckK5ChordCount`, `CheckK5Spacing`, `CheckK5NoteLength`, `CheckK5SustainGaps`, `BuildK5Report`, `RunK5Checks`
- `actions_difficulty_gtrbass.lua`: `GB_RANGE`, `GB_MAX_CHORD`, `GB_MAX_SPAN`, `GB_FORCE_HOPO_ALLOWED`, `GB_ADV_SP`, `DIFF_NAMES`, `GEM_NAMES`, `INSTRUMENTS`, `ADJACENT_HIGHER` (module-level locals); `ReadGBNotes`, `GroupGBChords`, `QNAt`, `CountNotes`, `GBGemName`, `GBLabel`, `CheckGBChordCount`, `CheckGBChordSpan`, `CheckGBNoteLength`, `CheckGBOverlap`, `CheckGBSustainGaps`, `CheckGBSpacingAdvisory`, `CheckGBOutOfRange`, `CheckGBForceHopo`, `CheckGBTrillVelocity`, `BuildGBReport`, `RunGBChecks`
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
defaults.lua                   → S, VENUE_VALID, TIPS, constants
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → FindTrackByName, FindNamedTrackMIDI, GetTakePPQPerQN,
                                  SetDefaultTempoTracks, SetDefaultMIDITracks,
                                  SetDefaultDifficultyTracks, GetTempoContextBefore,
                                  GetMeasureStartTime, GetAudioItems, MakeProjectPoll
venue.lua                      → ListVenueEvents, GetVenueEventsForPreview
venue_awareness.lua            → GetMutedInstruments, GetCoopRequiredInstruments,
                                  GetDirectedRequiredInstruments, FilterPool,
                                  ReadEventSections, ListEventSections, FindMusicStartTime,
                                  INST_LETTER_NAMES
section_events.lua             → SECTION_EVENT_GROUPS, SECTION_EVENT_BASE (data only)
venue_themes.lua               → ThemeDisplayLabel, LoadVenueThemes, GetSectionPreset,
                                  GetThemeCameraInterval, BuildLightingPool, BuildPostprocPool
venue_camera.lua               → COOP_POOL, DIRECTED_POOL, PickRandom, JitteredInterval,
                                  CategorizeCoopPool, WeightedPickCoopEvent, FindCompanion,
                                  ComputeIdleState, GenerateCameraEvents,
                                  ResolveUserCamInterval; camera globals
                                  (CAM_INTERVAL_16THS etc.)
venue_sprites.lua              → LoadVenueSprite, DrawVenueTooltipSprite, BeginVenueTooltip,
                                  EndVenueTooltip; VENUE_SPRITE_ROOT, VENUE_SPRITE_SELF_ROOT,
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
actions_tempomap.lua           → ShowTempoContext, EstimateInitialBPM, AutoTuneThreshold,
                                  ClearGeneratedTempoMarkers, GenerateTempoMap
actions_drums.lua              → ConvertDrums
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
actions_difficulty_shared.lua  → CheckDifficultyProgression
actions_difficulty.lua         → CopyProKeysDiff, ValidateProKeysDiff, ValidateAllProKeys
actions_difficulty_5k.lua      → ValidateKeys5Diff, ValidateAllKeys5, CopyKeys5Diff
actions_difficulty_gtrbass.lua → CopyGtrBassDiff, ValidateGtrBassDiff, ValidateAllGtrBass
actions_difficulty_drums.lua   → CopyDrumsDiff, ValidateDrumsDiff, ValidateAllDrums
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
ui_keys.lua                    → DrawKeysTab
ui_difficulty.lua              → DrawDifficultyTab
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

**Second entry point: `rock_band_preview_vkr.lua` (repo root).** Standalone Venue Preview window. It has no module folder of its own — it dofiles a subset of this helper's modules: `lib/reaper_imgui_helpers.lua`, then `defaults.lua`, `settings.lua`, `helpers.lua`, `venue.lua`, `venue_awareness.lua`, `venue_sprites.lua`, `ui_venue_preview.lua`, `ui_venue_players.lua`, and runs its own minimal `Loop` calling `DrawVenuePreviewTab()` + `DrawActivePlayersRow()`. Consequences when editing those files:
- They must keep working without the rest of the general helper loaded — do not add load-time or call-time dependencies (from the preview code path) on modules outside this subset. `settings.lua` guards its `SaveSectionConfigs`/`LoadSectionConfigs` calls (`if X then X() end`) for this reason.
- `venue_sprites.lua` reads `SCRIPT_DIR` at dofile time; both entry points set it before loading.
- The standalone calls `LoadSettings()` at startup and on project switch, but never `SaveSettings()` (saving stays in the general helper's General tab).

**`TrackCombo` override.** The general helper uses `sel_idx = -1` to mean "no track configured" for drum source dropdowns. The lib's `TrackCombo` always expects a non-negative index. `ui.lua` defines `TrackCombo` as a **global** — overriding the lib version for all modules — that adds a `(none)` selectable entry and handles -1. The extracted `ui_keys.lua`, `ui_midi.lua`, and `ui_venue.lua` all call `TrackCombo` and rely on this global override.

### Save / Load

Section `RBHelperVKR`, key `settings_v1`. Auto-loads on script open.

**Saved:** all tempo map sliders — primary source (`tm_rms_threshold`, `tm_rms_window_ms`, `tm_search_window_ms`, `tm_drift_threshold_ms`, `tm_bpm_failsafe`, `tm_first_measure`, `tm_timesig_num`, `tm_override_failsafe`), fallback source (`tm_fb_rms_threshold`, `tm_fb_rms_window_ms`, `tm_fb_use_flux`), auto-tune (`tm_autotune_density`), the Difficulty tab's Guitar/Bass instrument radio (`diff_gb_instrument`), the Keys sub-tab's "Reduce using Pro Keys" checkbox (`diff_5k_pk_reduce`), and the Workflow sub-tab's selected template name (`workflow_file_name`) and "Show completion timestamp" checkbox (`workflow_show_ts`).
**Not saved:** track indices — positional, brittle. `SetDefaultTempoTracks` re-detects tempo map tracks by name; `SetDefaultMIDITracks` re-detects PART DRUMS and PART GUITAR target tracks by name; `SetDefaultDifficultyTracks` re-detects all Difficulty-tab tracks (Pro Keys, Keys, Guitar/Bass, Drums) by name. All only assign fields that are still -1 (do not override saved state).

**Own ExtState keys, guarded through `SaveSettings`/`LoadSettings`:** the Section gen sub-tab's per-section configs (`vsec_v1`, `actions_venue_section.lua`) and the Workflow sub-tab's checklist state (`workflow_v1`, `actions_workflow.lua`) each live under their own key rather than the `settings_v1` scalar blob — both hold a variable-length, dynamically-keyed collection rather than a small fixed set of fields.

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
