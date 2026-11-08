# General Helper — Script Documentation

`rock_band_general_helper_vkr.lua` provides the song-wide Rock Band authoring utilities: stem import and audio track alignment, tempo map generation from drum audio, the workflow checklist, VENUE/EVENTS authoring, and Metadata (genre and difficulty-rank suggestions). The instrument tabs — Difficulty, Overdrive, Tab Input, MIDI and the WIP Drums/Keys/Guitar converters — moved to the Instrument Helper in v0.9.63; see `.claude/CLAUDE_instrument.md`.

Read `CLAUDE.md` first for shared architecture, conventions, and Lua specifics.

---

## How the script is used

Six stable tabs are always visible: **General | Workflow | Animation | Events | Venue | Metadata**

**Metadata tab** has three sub-tabs: Genre, Difficulty and **Song key** (suggests `vocal_tonic_note` / `song_tonality` from the charted notes; see `song_key.lua` and `ui_metadata_key.lua` below, and `dev/tools/key_detect_fit_offline.lua`, which fits the profiles against the official charts and prints their cross-validated agreement with `songs.dta`). Genre and Difficulty, in detail: **Genre** converts a real-world genre into the closest supported major genre and subgenre; it is a pure lookup over two static tables and is listed first because it works with no project open at all. Like Difficulty it states outright that it is advisory - but for a different reason, and the two wordings should not be merged: Difficulty's inputs are measurements of the author's own MIDI, whereas every genre mapping is a hand-made judgment call, so only Genre invites the reader to push back on it. **Difficulty** estimates what rank a finished Expert chart should carry. Both are read-only.

Note the two Difficulty features are different things and are deliberately kept apart. The Instrument Helper's **Difficulty tab** copies, generates and validates authored lower-difficulty charts — it writes MIDI. **Metadata > Difficulty** estimates what rank a finished Expert chart should carry — it is read-only and writes nothing, ever.

One WIP tab appears only when **Show WIPs? = Yes** in the General tab (persisted setting, default No): **Tempo Map**. It functions at a basic level but has known issues and is not ready for general users.

**Window footer** (every tab) — time selection, status, Copy result, Undo; the tabs scroll above it. Track lists refresh on their own (`CLAUDE.md` → "Track lists refresh themselves"). Shared implementation: `CLAUDE.md` → "Window footer".

**General tab** — audio alignment and settings persistence. Contains three sub-tabs:

*Actions sub-tab*
- **Align all audio** — aligns every audio item on every track to a common reference position.
- **Align count-in** — positions the COUNT IN clip relative to the first measure.
- **Song fade out** — creates a fade-out automation envelope on the master track at the end of the project.

*Settings sub-tab*
- Venue preview size/sprite display options, Show WIPs? toggle.
- Save / Load buttons for project-scoped settings (placed last, since they persist the settings above them).

*Other tools sub-tab* — buttons that open the suite's other entry points. Drawn by `DrawGeneralLinksTab` in **`lib/reaper_script_links.lua`**, not by a file in this module folder: the vocal helper's General tab has the identical sub-tab, so the registry and the launcher live in `lib/` to exist exactly once. See `CLAUDE.md` → "Shared lib".
- Two sections from `SCRIPT_LINK_GROUPS`: *Main tools* (General Helper, Vocal Helper, Music Theory Helper) and *Standalone windows* (Venue Preview, Pitch Tuner, MIDI Pattern). One `BtnGroupWidth` spans both sections so they read as a single column.
- The running script's own entry is filtered out by `FilterScriptLinkGroups` (whole-basename, case-insensitive match against `get_action_context()`), so this tab shows five buttons, never six. A group emptied by that filter is dropped rather than left as a header over nothing.
- `LaunchReaScript(path)` = `AddRemoveReaScript(true, 0, path, true)` → `Main_OnCommand`. Registration is idempotent (REAPER de-duplicates by path) and **permanent by design** — it is never removed, since that would delete the user's own registration and any key/toolbar binding with it, and a re-add returns a different command ID. `GetToggleCommandState(cmd) == 1` short-circuits a re-launch so REAPER's modal "ReaScript task control" dialog can't block the frame. Safe to call mid-frame: the launched script runs in its own Lua state and draws its first frame on the next defer tick.
- Missing targets are `BeginDisabled`+`EndDisabled` with the reason drawn *inline* — a disabled widget reports no hover, so its `Tooltip` is unreachable in that state. `file_exists` is re-checked on a 2 s throttle (not per frame, not frozen once — `deploy_to_reaper.bat` gets run with REAPER open).
- **`rock_band_music_theory_helper_vkr` is a link target only** — no reverse link back, because its `ui.lua` has no General tab to host this sub-tab. See `.claude/CLAUDE_music_theory.md`. The three standalone windows are link targets only too, having no tab bar at all by design.
- Tested by `dev/tests/script_links.lua` (pure; no project fixture) — the valuable case checks the registry against the entry points actually present at the install root, in both directions.

**Workflow tab** (`ui_workflow.lua`; a General sub-tab before v0.9.63) — per-project authoring checklist, sourced from a user-editable `.txt` template.
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

**Animation tab** (`ui_animation.lua`, `DrawAnimationTab`) — sub-tabs: **Beat** (writes the BEAT track; see "Feature: Animation > Beat" below) **Character** (band member animation states per part; "Feature: Animation > Character") and **Drums** (the drummer's hand and kick animation notes; "Feature: Animation > Drums"). Keys and Guitar are planned, one sub-tab per feature.

**Events tab** (`ui_venue_events.lua`, `DrawEventsTab`) — the EVENTS-track tools, a main tab since v0.9.63 (before that: the List event sections button in Venue > Actions, and Venue > Events). Two sub-tabs:

*General sub-tab* (`DrawEventsGeneralTab`, local)
- **List event sections** — reads `[prc_*]` markers from the EVENTS track and lists detected song sections with time ranges. Letter-suffix variants, including letter-only forms with no number (`[prc_verse_a]`/`[prc_verse_b]`) and numbered forms (`[prc_verse_1a]`/`[prc_verse_1b]`), are merged into a single section entry. Read-only.

*Manual gen sub-tab* (`DrawVenueEventsTab`; the Venue > Events sub-tab before v0.9.63) — EVENTS-track text event insertion at the playhead. One row per event group; vocabulary lives in `section_events.lua`, validated against `_external_docs/Text Events List - Events.txt` by `dev/tests/venue_events.lua`.
- Section groups (Intro, Structure, Solo, Break, Tempo/Energy, Interlude/Jam, Outro/Ending, Misc) — base-name combo + number slider (`bare` or `_1`–`_9`) + **Add**. A read-only `->` indicator shows the exact event the next Add inserts live at the playhead, or `-> (blocked)` when it would be refused (reason on hover; a refused Add also reports the reason in the result section).
- **Insert validation** (`NextSectionEvent` / `ValidatePlainInsert`, pure functions over a positional scan): duplicates refused with the existing event's location; bare and numbered variants of one base must not co-exist; plain and lettered forms of one (base, number) must not be mixed; numbers/letters must be used in sequence (`_2` needs a `_1`-family event) and placed in timeline order between their sequence neighbors; no two text events on one PPQ. `[crowd_*]` events are exempt from all rules and may stack anywhere.
- **Use letter suffix** checkbox (default on) — Add inserts *only lettered forms*, starting at `a` (`[prc_verse_1a]` → `[prc_verse_1b]`; never the unlettered event, so parts always merge in Section gen; hand-deleted letters are re-offered as gaps), capped per base by the valid vocabulary. When off, Add only inserts the plain event and refuses when it exists. Bases with no lettered variants (`.` caps, e.g. `bre`, entry cues) insert the plain form in either mode.
- **Insert bookends** — inserts `[crowd_realtime]` at measure 1, `[prc_intro]` + `[crowd_noclap]` + `[crowd_normal]` (a placeholder mood) at measure 2, `[music_start]` at measure 3, and `[prc_outro]` + `[crowd_noclap]` / `[music_end]` / `[end]` at E−5 / E−2 / E, where E = last measure fully contained in the MIDI item (`TimeMap_GetMeasureInfo` walk); items under 7 full measures skip the end events. Matches the official RB3 charts: the first section sits at bar 3 in most songs, shortly *before* `[music_start]` (our measure 2 keeps the one-event-per-spot rule), and the first EVENTS crowd event is `[crowd_noclap]` on it. Official EVENTS carries only `[crowd_noclap]` / `[crowd_clap]`; the crowd's mood lives on a separate milo crowd track, which opens with `[crowd_realtime]` and changes to a mood on the first section (normal 340, mellow 208, intense 52 of 609 songs). Custom songs have no crowd track, so both go on EVENTS. A re-run first removes every `[prc_intro]` / `[music_start]` / `[prc_outro]` / `[music_end]` / `[end]`, but the crowd events (`[crowd_realtime]`, `[crowd_noclap]`, and the old `[crowd_normal]`) only on this run's crowd spots and where the old `[prc_intro]` / `[prc_outro]` sat, so mid-song crowd events survive. Occupied target spots are skipped and reported.
- **Clear all** — removes every type-1 text event from the EVENTS take (track-name meta untouched).
- Generic group — `[prc_a]`–`[prc_k]`, digits append with no underscore (`[prc_a3]`), no letters.
- Crowd / Global groups — plain full-event combos (`[crowd_*]`, `[music_start]`, `[music_end]`, `[end]`, `[coda]`); Global gets duplicate/same-spot checks, Crowd does not.
- Targets the EVENTS track by name (`FindEventsTake`); an inline hint is shown and all buttons are disabled when the track or its MIDI item is missing. `S.venue_ev_mode` is reserved for a phase-2 target-mode radio (see `SONG_SECTION.md`).
- The take + scan feeding the indicator are cached via `MakeProjectPoll(1.0, 5.0)` (see the polling convention below), force-refreshed by the tab's own edit buttons, and pointer-validated each frame (`ValidatePtr2`); the cursor lookup + row validation over the cached scan are pure Lua and run per frame. The Add actions always re-scan, so the UI cache can never cause a wrong insert.

**Venue tab** — VENUE MIDI track events. Contains five sub-tabs (plus Preview):

*Actions sub-tab* — inspection and validation tools, sing-along generation, and the Sub VENUE tracks copy actions.
- **List venue events** — validates the VENUE track against the Rock Band Network spec: track name event, event type checks, unknown events, consecutive camera repeats, directed cut spacing, camera gap statistics, event usage frequency. Read-only.
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
- **Generate sing along** — derives VENUE sing-along notes (pitch 87 guitarist from HARM2, pitch 85 bassist from HARM3) from each harmony track's vocal phrase content: a phrase (bounded by a pitch-105 marker note; HARM3 reads HARM2's markers and ignores its own, as the game does) qualifies when it has at least one vocal-range note (36-84); qualifying phrases less than a measure apart are merged into one continuous note. Only the pitch of a source track that is present and unmuted is cleared/replaced — a muted or missing source is skipped, leaving its existing notes untouched. If both HARM2 and HARM3 are unavailable, nothing is generated. Always processes the whole song (no time-selection scoping). Fully undoable.
- **Sub VENUE tracks** (`actions_venue_subtracks.lua`) — splits VENUE's events across 6 category tracks for easier authoring once a song has a lot of keyframes, then merges them back. Classification is by `CategorizeVenueEvent`: `coop`/`directed` (camera), `lighting`, `keyframe` (`[first]`/`[next]`/`[previous]`), `postproc` (`*.pp]`), and `special` (bonusfx + anything unrecognized, catch-all). VENUE's own interpretive MIDI notes (e.g. the sing-cue notes at pitches 85-87) are not text events and don't fit this classification — they always travel with `special`, via `CopyVenueNotes` alongside `CopyVenueEvents`, since no other category ever carries notes.
  - **Copy all to subtracks** — creates (if missing) "VENUE normal camera"/"VENUE directed camera"/"VENUE lighting"/"VENUE keyevents"/"VENUE post proc"/"VENUE special", each with a MIDI item matching VENUE's own position/length, inserted directly after VENUE. Newly created tracks start **muted** (an editing-only split with no meaning to the exported song — muting keeps downstream export tooling from flagging them as unrelated/unused MIDI), inherit VENUE's custom MIDI note names (`GetTrackMIDINoteNameEx`/`SetTrackMIDINoteNameEx`, checked across chan -1 and 0-15 for every pitch 0-127), and a newly created item's take gets its `P_NAME` set to the track's own name — REAPER's MIDI-editor tab/take-list label comes from the take's `P_NAME`, not from any embedded MIDI meta-event, so without this every subtrack's take shows as a generic "MIDI take" once more than one MIDI editor tab is open. Re-syncs bounds and re-copies on every run, so it's safe to re-run after editing VENUE directly - none of the creation-only steps (mute, note names, take name) repeat on a later sync (a hand-renamed take is never stomped).
  - **Copy all to main track** — early-exits with a status message if none of the 6 subtracks exist yet (rather than silently clearing VENUE for nothing). Otherwise clears VENUE and replaces it with the combined contents of however many subtracks currently exist (including "VENUE special"'s notes, replacing VENUE's own). Prompts for confirmation first (`S.venue_subtrack_copy_pending`, mirrors the Difficulty tab's overwrite-confirm modal) since it overwrites the track authoring actually reads from.
  - **Subtrack dropdown + Copy to / Copy from** — scoped to one category. **Copy to** clears just that subtrack and copies the matching category from VENUE into it, auto-creating the subtrack if missing. **Copy from** clears only that category's events from VENUE (not everything) before copying the subtrack's contents in — does **not** auto-create the subtrack (no-op status message instead), asymmetric from Copy to on purpose. For Special, both directions also clear+copy VENUE's MIDI notes to/from "VENUE special". Neither prompts for confirmation, matching `RemoveVenueEventsByType`'s existing precedent for category-scoped edits.
  - All 5 actions always process the whole VENUE item — not time-selection scoped, since subtracks always mirror the entire item.

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
- **Target** radio (`S.venue_mg_target`, saved as `vmgt`): **VENUE** (default) or **Subtracks** — the Sub VENUE tracks below. In Subtracks mode every action reads and writes the subtrack of the event's `CategorizeVenueEvent` category (`VenueTargetName(kind)`, `actions_venue_manual.lua`): cameras → normal / directed camera, Lighting Add + Blend → `VENUE lighting`, Post proc Add + Blend → `VENUE post proc`, `[bonusfx*]` → `VENUE special`, `[first]`/`[next]`/`[previous]` and generated keyframes → `VENUE keyevents`. The `[first]` gate and the keyframe span read `VENUE lighting`; keyframe positions move to the keyevents take through project time, so a subtrack item at another position still lands on the right time. Remove clears each covered subtrack (Special = special + keyevents, All = all six). A missing subtrack stops the action before any undo block, with a status pointing to Copy all to subtracks; Remove works on the subtracks that exist and lists the rest. Validators, Preview and the game read only VENUE, so the user merges back with Copy all to main track.
- **Insert** radio (`S.venue_mg_replace`, saved as `vmgr`): **Add** (default, events stack) or **Replace** — the row Add buttons first delete the events of the same family within the 1/128-note spot tolerance of the playhead (`DeleteVenueEventsAtPpq`, pure over one take), then insert, in one undo block. Families (`REPLACE_FAMILIES`): cameras (coop + directed together, so a stack becomes the one new shot), lighting, postproc, special, keyframe. Other families on the tick stay. In Subtracks mode the clear runs on each family category's own subtrack (a camera replace touches both camera tracks). Blend, keyframe generation and Remove ignore the mode.
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
- **Target** radio — the same `S.venue_mg_target` setting as Manual gen's Target (one per project, saved as `vmgt`). **Subtracks** reads the manual lighting events from `VENUE lighting` and writes the keyframes to `VENUE keyevents`, through the shared `FindVenueTarget` / `VenuePpqBetween` (`actions_venue_manual.lua`), so a keyevents item at another position still lands on the right time. A missing subtrack stops the run before any undo block, with the same "Copy all to subtracks" status as Manual gen.
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
| `rock_band_general_helper_vkr/helpers.lua` | `FindNamedTrackMIDI` (track + first MIDI item/take; self-contained for the standalone preview), `SetDefaultTracks`, `GetMeasureStartTime`, `GetAudioItems` |
| `rock_band_general_helper_vkr/venue.lua` | `ListVenueEvents`, `GetVenueEventsForPreview`, `IsBlendAnchor`, `AnnotateVenueBlends` (global); `ReadVenueTextEvents`, `BuildCameraGaps`, `GapStats` (local). Holds the **read** side of the blend rule (`IsBlendAnchor`) because this module is in the standalone Preview's subset and `venue_lighting.lua`, which owns the write side, deliberately is not. |
| `rock_band_general_helper_vkr/venue_awareness.lua` | `GetMutedInstruments`, `GetCoopRequiredInstruments`, `GetDirectedRequiredInstruments`, `FilterPool`, `ReadEventSections`, `ListEventSections`, `FindEventTime` (generic EVENTS-track text-event lookup), `FindMusicStartTime` (thin wrapper over `FindEventTime`), `INST_LETTER_NAMES` (global); `INST_TRACK_NAMES`, `ParsePrcEvent` (local) |
| `rock_band_general_helper_vkr/venue_camera_priority.lua` | `CAM_PRIORITY_TIERS`, `CAM_PRIORITY`, `CAM_GENERIC_FALLBACK`, `CameraShotPriority`, `CameraShotFitsBand`, `PickPriorityCameraEvent` (global); `KEYS_EXCEPTION`, `BareName` (local). Which of several shots stacked on one tick the game plays, transcribed from `_external_docs/RBN2 Camera And Lights - RBN_C3 Documentation.htm`. Pure — no `r`/`ctx`/`S`; its `GetCoopRequiredInstruments`/`GetDirectedRequiredInstruments` use is at call time, so it may load before or after `venue_awareness.lua`. Full write-up in `.claude/CLAUDE_venue_theme_generation.md` ("Camera shot priority"). |
| `rock_band_general_helper_vkr/venue_themes.lua` | `ThemeDisplayLabel`, `LoadVenueThemes`, `GetSectionPreset`, `GetThemeCameraInterval`, `BuildLightingPool`, `BuildPostprocPool` (global); `POSTPROC_VALID_SET`, `LIGHTING_VALID_SET`, `CAMERA_PACING`, `Tokenize`, `ParseSexpr`, `ParseThemeFile`, `InterpretSectionPreset`, `InterpretTheme` (local) |
| `rock_band_general_helper_vkr/venue_camera.lua` | `COOP_POOL`, `COOP_LABELS`, `DIRECTED_POOL`, `DIRECTED_LABELS`, `DIRECTED_TIPS`, `PickRandom`, `JitteredInterval`, `CategorizeCoopPool`, `WeightedPickCoopEvent`, `FindCompanion`, `ComputeIdleState`, `GenerateCameraEvents`, `ResolveUserCamInterval` (global); camera constants (`CAM_INTERVAL_16THS` etc., partially global); `WeightedPickInstrument` (local) |
| `rock_band_general_helper_vkr/venue_sprites.lua` | `LoadVenueSprite`, `DrawVenueTooltipSprite`, `BeginVenueTooltip`, `EndVenueTooltip`, `VenueEventTooltip`, `RawVenueEventText`, `VenueSpriteFoldersFound` (global); `DIRECTED_SPRITE_NAMES`, `VENUE_SPRITE_ROOT` (module-level globals). JPEG-only. Checks `resources/img/spritesheets/{category}/` (large) then `resources/img/spritesheets/{category} small/` (small) — no third-party fallback. Frame count is read from the filename (`{key}_f{N}_spritesheet.jpg`). Display size scales by `S.venue_preview_scale` (1 or 2). Cache stores `{image, frame_count, cols, rows}` per sprite. |
| `rock_band_general_helper_vkr/venue_lighting.lua` | `MANUAL_LIGHTING_SET`, `LIGHTING_OFFSET_16THS`, `INST_KF_MODES`, `KF_ALIGN_LABELS`, `FindNextMeasureStartPpq`, `CollectInstNotePositions`, `GenerateKeyframesForSpan`, `GenerateLightingEvents`, `GenerateThemedSectionEvents`, `SnapPpqToHalfBeat` (global); `MANUAL_LIGHTING_POOL`, `AUTO_LIGHTING_POOL`, lighting constants, `SnapPpqToNearestBeat`, `BlendPpq`, `EmitBlendDuplicates`, `ResolveThemeSection`, `EmitThemeSection` (local) |
| `rock_band_general_helper_vkr/venue_generator.lua` | `GenerateVenueEvents`, `DeleteTextEventsInRange` (predicate-driven deleter backing all clear functions), `ClearVenueTextEventsInRange`, `ClearVenueNonCameraEventsInRange`, `ClearVenueExceptLPInRange`, `ClearVenueKeyframesInRange`, `FindActiveVenuePresetsBefore` (global) |
| `rock_band_general_helper_vkr/animation_beat.lua` | `BeatPlan` (pure), `ReadProjectBars`, `GenerateBeatTrack`, `BEAT_PITCH_DOWN`, `BEAT_PITCH_UP` (global); `Fail` (local) — Animation > Beat |
| `rock_band_general_helper_vkr/animation_drums.lua` | `DRUM_ANIM_PARAMS`, `DRUM_ANIM_PIECES`, `DRUM_ANIM_KICK`, `DRUM_ANIM_TRACKS`, `DrumAnimPlan`, `DrumAnimOnsets`, `DrumAnimDiscoSpans`, `DrumAnimBeatPos` (pure), `DrumAnimOptions`, `GenerateDrumAnimations` (global); `Pieces`, `BeatPos`, `TwoHands`, `ReadDrumsTake`, `IsAnimPitch` (local) — Animation > Drums |
| `rock_band_general_helper_vkr/animation_character.lua` | `CHAR_STATES`, `CHAR_STATE_SET`, `CHAR_RIDE_EVENTS`, `CHAR_RIDE_SET`, `CHAR_ACTIVE_CHOICES`, `CHAR_GROUPS`, `CHAR_PARTS`, `CharStateDesc`, `CharacterPlan` (pure), `CharGroupStatus`, `CharacterStateAt`, `GenerateCharacterAnimations`, `InsertCharacterState` (global); `Trim`, `TrackMuted`, `ReadExpertNotes`, `DeleteStates`, `ActiveFor` (local) — Animation > Character |
| `rock_band_general_helper_vkr/workflow.lua` | `ParseWorkflowContent`, `ParseWorkflowFile`, `LoadWorkflowFiles`, `EscapeWF`, `UnescapeWF` (global); `FindBraceGroups`, `StripBraceGroups` (local) — Workflow sub-tab's `.txt` template parser (pure over string content) + `resources/workflow/` folder scanner |
| `rock_band_general_helper_vkr/actions_workflow.lua` | `CompositeKey`, `PruneToWorkflowEntries`, `SaveWorkflowState`, `LoadWorkflowState`, `SelectWorkflowFile`, `ToggleWorkflowItem`, `ComputeWorkflowStats` (global) — Workflow checklist state, persistence (`workflow_v1` ExtState key), template-switch pruning, and the pure progress-count helper |
| `rock_band_general_helper_vkr/metadata_genres.lua` | `RB3_GENRE_ORDER`, `RB3_GENRES` — the supported genre vocabulary, **29 major genres and 126 subgenres**, transcribed from `_external_docs/Subgenre Descriptions - RBN_C3 Documentation.htm`. Data only, pure. Note that page's own intro prose says "120 subgenre groupings, under 21 major genres" while the page **enumerates 29 and 126**; the enumeration is correct (checked against the tool that does the final selection), so the counts must not be "corrected" back to the prose — `dev/tests/metadata_genres.lua` asserts both numbers. Per-subgenre `blurb`/`elements`/`artists`/`albums` are **optional and mostly absent**: only 33 of the 126 carry any description at all, so every consumer must render correctly from a bare label. **No `.dta` tokens, deliberately** — token spellings drift between game eras (RB1/RB2 `urban` became RB3 `hiphoprap`) and are scoped to their parent (`subgenre_pop` is Pop-Punk under `punk` but Pop under `poprock`), and the packaging tool that writes `songs.dta` has its own picker. |
| `rock_band_general_helper_vkr/metadata_genres_ext.lua` | `GENRE_FAMILY_ORDER`, `GENRE_FAMILIES`, `EXTENDED_GENRES` — the authored half: 208 real-world genres across 10 families, each with 1–3 ranked candidates and a written reason. Data only, pure. Calibrated against 3126 released songs (1375 carrying a subgenre) in `_external_docs/genre_reference_songs/`. **A second candidate is a real fork, not hedging.** A `see_also` entry is a different thing again: it points at another *extended* entry (Post-Grunge -> Grunge) and means "you may have picked the wrong genre", not "here is another supported home" — which is why it is not a candidate and the UI draws it unnumbered below a separator. The header also fixes the **dimension precedence**, which looks arbitrary until stated: an explicit supported category wins first (J-Rock maps by origin only because Rock Band *has* that genre; K-Pop has no equivalent so it maps by sound), then musical style, then scene/origin, then instrumentation or source. Four entries (Viking Metal, Folk Metal, Screamo, Big Band) were settled against web sources rather than taste after `GENRE_REVIEW.md`, and `dev/tests` pins each so a later edit cannot quietly undo them. A multi-filed artist in the catalogue has three distinct explanations that must not be conflated: the band changed style (both filings correct), the cataloguing convention changed between game eras (A Day to Remember is `punk/alternative` on both RB2 songs and `rock/hardrock` on both RB3 ones, from adjacent easycore-era albums), or the boundary genuinely is ambiguous (Five Finger Death Punch has two filings in the *same* era). Only the third justifies a second candidate. |
| `rock_band_general_helper_vkr/metadata_genres_lookup.lua` | `GenresInFamily`, `ExtendedGenreByKey`, `RB3Subgenre`, `ResolveExtendedGenre`, `BuildReverseGenreIndex`, `ExtendedGenresForPair`, `ValidateGenreTables` (global); `PairKey`, `BuildCaches`, the three caches (local) — pure lookup over the two tables above. Caches are built on first use and never invalidated, because neither table changes at runtime. `ResolveExtendedGenre` **skips** a candidate whose pair does not resolve rather than returning a half-built row, so malformed data cannot crash the tab; the test asserts that never actually happens. The reverse index splits each pair's inbound entries into `first` (this pair is that genre's best answer) and `lower` (offered as an alternative) — collapsing them would hide the difference between a style's primary home and somebody's second choice. `ValidateGenreTables` returns a problem list and is used by the tests, not the UI. |
| `rock_band_general_helper_vkr/ui_metadata_genre.lua` | `DrawMetadataGenreTab` (global); `DimWrapped`, `ClampIdx`, `DrawSubgenreDoc`, `DrawForward`, `DrawReverse` (local) — the Genre sub-tab body. **Stricter read-only than Difficulty beside it: it does not even read the project**, so there is no Refresh, nothing to reset on a project switch, and no undo point. **One direction only.** A reverse view (pick a supported genre, see what maps onto it) was built and then cut before release: browsing the supported list is not a task an author has, since they arrive knowing what their song is and needing the other half. Its lookup half survives in `metadata_genres_lookup.lua` (`BuildReverseGenreIndex` / `ExtendedGenresForPair`, no UI caller) because the round-trip test over it is a real integrity check on the mapping - it proves every candidate is reachable from its pair in the right rank bucket - so restoring the view would be a UI-only change. The tab narrows by family first (the vocabulary is past 200 entries, more than one dropdown can be read from) and **changing the family resets `S.genre_ext_idx`**, which addresses the previous family's list. Results are drawn **inline, not into `S.last_result`** — they change as the combo moves, and `ui.lua` wipes the shared panel on any main-tab change. `DimWrapped` exists because ImGui's `TextDisabled` has no wrapping variant. `see_also` pointers render **unnumbered, dimmed and below a separator** — numbering them beside the candidates is exactly the confusion that split exists to remove. |
| `rock_band_general_helper_vkr/ui_metadata.lua` | `DrawMetadataTab` (global); `RefreshSuggestions`, `CopySuggestionDetails`, `DrawCard`, `DrawDifficultyDots`, `DrawTierRuler`, `COL_*`/`DOT_*` (local) — the Metadata tab shell and its Difficulty sub-tab. One card per instrument: name, maturity chip (its meaning is the chip's **tooltip**, not a line on the card — the wording is a property of the model and would otherwise repeat identically on every keys/Pro Keys/vocals result), five difficulty dots, `<tier> (rank N)`, the **tier ruler**, warnings, then the notable properties as **always-visible** bullets. The ruler replaced a `TextDisabled` line ("near the bottom of this tier") that duplicated the amber boundary warning below it while carrying none of the numbers; that wording survives as the ruler's tooltip. It is **drawn, not spelled with dashes** — nothing in this repo loads a font, so ImGui's proportional default cannot hold dash columns aligned between cards; the ASCII form is right only in `dev/tools/verify_suggester_vs_csv.lua`, which prints to a monospace console. Its left label is computed with `LabelColWidth` over **all six** records so the rulers align down the column. A clamped rank pins its marker to that end in `COL_WARN`: a clamped rank is a limit, not a position, and drawing it mid-band would claim the precision the clamp exists to deny. **`Copy details` and `Show measured values` are both gated on `S.show_wip_tabs`**, and so is the `Details` panel itself — not just its checkbox, since ticking it and then turning the WIP flag off would strand an open panel with nothing on screen able to close it. Both answer a calibration question rather than an authoring one, so the first release keeps them one checkbox away in General > Other rather than on the default panel. `S.diff_show_factors` is **session-only and deliberately not persisted** (it had a `dsf=` key; it was removed): a saved value could return in a project where its control is not drawn, so the panel's visibility would have two possible explanations and no way to tell them apart. The raw factor table sits behind a `Details` `CollapsingHeader` shown only when `S.diff_show_factors` is on (off at every startup) — it is a development view, meaningless to an author, and the bullets say the same thing in words. **First use of `CollapsingHeader` / `Indent` in this repo**; the dots follow `ui_venue_players.lua`'s `DrawList` idiom. Scores on demand only — walking every note on six PART tracks is far too much per frame, and a number that changed while being read would be worse than a stale one. Results live in session-only `S.diff_suggestions`, cleared on project switch. There is deliberately **no apply control**: a one-click write would turn an estimate into the answer. `CopySuggestionDetails` is a thin wrapper — the project name (behind a `pcall`, since `GetProjectName`'s signature has moved across REAPER versions) and `ImGui_SetClipboardText`, with the formatting in `difficulty_report.lua` so it tests headlessly. It sets `S.status` on success because a clipboard write is otherwise indistinguishable from a dead button, and is `BeginDisabled` before the first Refresh. |
| | **The dots** reproduce the game's own display: five, filled from the left, red at the top. Seven tiers map onto five because the top two share a filled count (Warmup 0, Solid 2, Nightmare 5, Impossible 5 in red) — that is how the game shows them, not a compression introduced here. An unfilled dot is mid-grey on a near-black plate rather than black on the window background, which is invisible in this theme. |
| `rock_band_general_helper_vkr/difficulty_explain.lua` | `DIFFICULTY_FACTOR_INFO`, `DIFFICULTY_FACTOR_ORDER`, `DIFFICULTY_STATUS_BADGE`, `DIFFICULTY_STATUS_NOTE`, `DifficultyPositionText`, `DifficultyRulerBand`, `DifficultyFactorRows`, `DifficultyExplanations`, `DifficultyWarnings`, `DifficultyAnnotate` (global); `FormatValue` (local) — turns a suggestion into words. Pure, so `dev/tests` drives it with hand-built factor tables. **Never shows regression coefficients**: the factors are near-collinear, so a large coefficient says which of a correlated pair the solver loaded, not what the chart demands. It reports what was *measured* — the ≤3 properties on which this chart is unusual versus the training corpus (|z| ≥ 1.0), which is a claim about the chart and the corpus with no causal content. **A candidate that merely restates a bullet already chosen is skipped** (`COLLINEAR_R = 0.70` against the artifact's `model.corr`), because picking by |z| alone spent two of three slots on one observation on 20% of corpus rows. The loop *continues* rather than breaks, so the slot goes to the next distinct factor; where every remaining notable factor restates one already shown, the card correctly ends up with fewer than three bullets rather than a padded three. `model.corr` is optional and its absence degrades to the old behaviour. `DifficultyFactorRows` is deliberately **not** filtered — the Details table is a complete list, and comparing two charts needs every row. Interval factors (`tight_p10`, `tight_med`) are spacings, so **low is the hard direction** and their wording is inverted. Warning thresholds: tier position ≤ 0.15 / ≥ 0.85, concentration against the model's own per-instrument training p90 (bass and drums never mark a solo, so only the density-ratio branch can fire there; vocals has neither and never warns). **Out-of-range measurements are not a card warning** — they ride on `factor_rows[].out_of` and are shown beside the number in the Details view. Out of range means *unusual*, not *responsible*: a near-empty keys chart carried the corpus's largest average chord size (a sustained two-note pad — unusual and easy for unrelated reasons), and naming it beside a floor-clamped rank read as "it is easy because its chords are large". The clamped note therefore states the bound and stops. Model maturity is **not** a warning — it is a property of the model, not the chart, so it would repeat identically on every card forever; it lives in `DIFFICULTY_STATUS_NOTE` and is shown as the badge's tooltip. Warning wording avoids "calibrated", "extrapolation" and the like: the reader is an author looking at their own MIDI, so the notes say what the number means ("the rank is capped at 488 - the true figure is probably higher") rather than describing the statistics. No confidence percentage anywhere — the regressions produce no calibrated per-song probability. The **Details table is ordered by `DIFFICULTY_FACTOR_ORDER`, not by |z|** — a per-song order put a different factor in every position, so two charts on the same instrument could not be read side by side, which is the only reason that table exists; most-unusual-first still picks the ≤3 bullets, where a ranking is the point. A factor's `tip` is **optional and most do not need one**: it explains the *sentence*, not the measurement, so it earns its place only where the wording uses a term the reader cannot map onto their own MIDI. Requiring one per factor produced tooltips describing the hidden number under a bullet that shows no number, and tooltips explaining game mechanics to the author who wrote the markers. `dev/tests` asserts quality (no tip under 40 chars) rather than coverage, and asserts `DIFFICULTY_FACTOR_ORDER` and `DIFFICULTY_FACTOR_INFO` hold exactly the same keys. `DifficultyRulerBand` supplies the tier ruler's band, its two end labels and a `pinned` flag; the ends with no neighbouring tier are labelled `min <rank_lo>` / `max <rank_hi>` rather than inventing a seventh tier name. **`DifficultyAnnotate` currently forces `rec.badge = nil`** — the maturity chip is switched off for the first release to keep the card plain while authors see it for the first time; the mapping and its tooltip text are still asserted by the tests so the one-line change that restores it stays safe. |
| `rock_band_general_helper_vkr/difficulty_report.lua` | `DifficultyReportText(recs, opts)` (global); `Wrap`, `Pad` (local) — the Copy details button's output. **Pure**, and consumes only what `DifficultyAnnotate` already built (`factor_rows` is pre-formatted and pre-ordered), so it needs none of `difficulty_explain.lua`'s locals and `dev/tests` drives it directly. Split out rather than appended because that file was at 633 lines, in CLAUDE.md's "evaluate splitting before adding more" band. **Aligned plain text, not markdown** — this gets pasted into forum posts, text files and REAPER's console, where a markdown table is pipe-and-dash noise. Column widths are measured across **all** blocks so instruments line up with each other. It **always includes the full factor table**, ignoring `S.diff_show_factors`: producing those numbers for someone else to read is the entire point, and the hand-copied 26-row drum table that prompted the feature had silently lost a row. Each block names its candidate, scale and the artifact schema, because the keys model changed twice in one week and a pasted report has to be identifiable as pre- or post-change. The uncapped score appears only when the clamp actually moved the rank. |
| `rock_band_general_helper_vkr/song_key.lua` | `SuggestProjectSongKey` (global); `BarAt`, `ReadPart` (local) — the read-only Metadata > Song key adapter. Reads PART VOCALS, HARM1-3 (pitches 36-84, dropping notes whose lyric contains `#`, which covers `#$`) and PART REAL_KEYS_X (48-72), then ranks all 24 keys for each of `KEY_RESULT_SETS` (`lib/reaper_key_detect.lua`). **Must read exactly what `dev/tools/key_detect_fit_offline.lua` reads from the reference MIDIs** — the same ranges, the same unpitched rule, bracketed text events skipped when matching lyrics — or the fitted profiles stop meaning what they were fitted to. Each note also carries its bar number from `format_timestr_pos` (which honours the project's measure offset, unlike `TimeMap2_timeToBeats`) for the key check's "outside the key" lists only; bars play no part in scoring. Also returns each track's notes separately (`tracks`: PART VOCALS, HARM1, HARM2, HARM3, Pro Keys — the harmonies set merges HARM1-3, the key check does not) and each set's label from `KeySetLabel`, which names only the parts actually read. Never touches `S`, never writes, no undo point. Whole song; time selection not consulted. |
| `rock_band_general_helper_vkr/song_key_audio.lua` | `SongKeyAudioStart`, `SongKeyAudioStep`, `SongKeyAudioBusy`, `SongKeyAudioCancel`, `SongKeyAudioResult`, `SuggestAudioSongKey` (global); `TrackItems`, `ReadBlock`, `CloseAccessor`, `_job`, `BLOCK_S`, `STEP_UNITS` (local) — the experimental audio-stems result, **run as a job over UI frames**: `SongKeyAudioStep(budget_s)` does at most that much reading (2 s accessor blocks) or analysis (`KeyAudioStep`, 16 frames between clock checks) per call, and `SongKeyTick` (`ui_metadata_key.lua`) calls it once per frame from the window's `Loop` with a 20 ms budget, so the window stays responsive on slow machines and the job continues while another tab is shown. Coroutines were not an option: `GetAudioAccessorSamples` / `new_array` fail inside them. One job at a time; cancelled on Cancel, project switch, `atexit`, and when a take on the picked tracks stops validating (`ValidatePtr2` every block, result `why = 'changed'`); each path destroys the accessor. `SuggestAudioSongKey` runs the same job to the end in one call, for tests and offline checks. Reads every audio item on the picked vocal and bass tracks through a take accessor at `KEY_AUDIO_SR` (REAPER resamples), downmixed to mono in 10 s blocks, then `KeyAudioNotes` (`lib/reaper_key_audio.lua`; `KEY_AUDIO` for the vocal, `KEY_AUDIO_BASS` for the bass) and **one** result from `KeyAudioPickSet`: vocal + bass when both have `KEY_MIN_NOTES`, else whichever does. Bass notes go in as the `keys` part and are scored with the `Kbass` profile (the lowest Pro Keys note of each chord, the nearest charted line to a bass part). Vocal + bass is the strongest combination tried against the reference stems; a full-mix chroma result was tried and dropped as the weakest. Item-relative accessor time, per the audio-accessor rule. About 1 s for the vocal and 4 s for the bass on a fast machine. Bass at 4 kHz (about 2.4x faster overall) and a 50 ms hop were measured and cost a little accuracy each, so neither is used. Reasons when unavailable: `no_track`, `no_items`, `no_notes`, `changed`. **No tempo map needed**: nothing in the key code reads beats since the downbeat source was dropped. Read-only. |
| `rock_band_general_helper_vkr/ui_metadata_key.lua` | `DrawMetadataKeyTab`, `SongKeyTick` (global); `RefreshSongKey`, `RefreshAudioSongKey`, `SetAudioResult`, `DrawVocalsNote`, `KeyRow`, `DrawSuggestion`, `OutsideLine`, `CheckReports`, `DrawTrackCheck`, `DrawKeyCheck`, `DrawMidiMode`, `TrackLine`, `DrawAudioMode`, `DimWrapped`, `WarnWrapped`, `_check` (local) — the Song key sub-tab body. **A "Read from" radio picks one source at a time** (`S.key_mode`: 1 Charted MIDI, the default; 2 Audio stems (experimental)), each with its own button and results, so the author reads one set of answers instead of up to five that may disagree — and the experimental source stays visibly separate. **Audio mode**: Vocal track and Bass track pickers (`TrackCombo` over `S.audio_track_list`; `S.key_audio_idx` / `S.key_bass_idx`, defaulted to `VOCALS AUDIO` / `BASS AUDIO` by `SetDefaultTracks`, reset on project switch) with a line asking for isolated parts, not the full mix; one result (`S.key_audio`) with Suggested / Runner-up / confidence and which tracks were read. While the job runs (`SongKeyAudioBusy`, snapshotted once per frame for the `BeginDisabled` pair) the pickers and button are disabled and a `ProgressBar` with a Cancel button is drawn; `SongKeyTick` (called by `Loop` every frame, whichever tab is showing) stores the result when the job ends. No outside-the-key list for audio, since pitch tracking smears many of a correct recording's notes outside the key; its `Check` buttons switch to MIDI mode with the key loaded (running the MIDI read if none exists yet, keeping that key). **MIDI mode: four charted results, never one blend** — PART VOCALS alone, + harmonies, + Pro Keys, and Pro Keys alone as an independent check — because the author can judge each input (Pro Keys is often not charted; a live vocal take can be off key; a simple harmony a third above the melody can pull the answer to the relative key). A set missing its own input says so rather than falling back to a smaller set. Each shows the suggestion and the runner-up (named by its relation: relative / parallel / a fifth away), each with a `Check` button, and a wording-only confidence from the score lead (`KeyConfidence`). **A key's notes are its tooltip, not a row**, so the runner-up's are available too without repeating the suggestion's. **Check a key**: a tonic combo + Major/Minor (starting on the fullest combined suggestion, or any key the author types in from Tunebat etc.), the key's notes, then per track (PART VOCALS, HARM1, HARM2, HARM3, Pro Keys) the share of notes outside the key (amber from 15%) and those notes with counts and bars, from `KeyTrackReport`; reports are cached in `_check` per result and key. **No "found in key" list**: against the reference charts, how many of the key's notes the parts use barely changed how often a suggestion was right, except when very few (`KEY_FEW_NOTES`), which gets a one-line note instead; the share outside the key is the strong signal. The 15% amber line is where suggestions stop being reliable against the reference charts' own keys (the misses past it are mostly the right tonic in the other mode); a fair share of official vocal charts sit above it, so amber means "worth a look", and the tooltip says so. The README's off-key table comes from the same development-song scan. No `songs.dta` numbers: authors set the key by note name in a packaging app. Notes outside the key are framed as where to look for a note charted a semitone off, **not** as errors — blue notes and the raised 7th of minor are normal. **No accuracy percentage is shown**: the reference values are one charter's judgement from years ago, and a project's result is only as good as its chart — the intro text says to verify by ear. Vocals missing, empty, all-unpitched or too short get their own amber line above the results. Results in session-only `S.key_suggestion`, cleared on project switch; the status line carries the fullest available combined result so the footer's Copy result has it. The checked key is session-only `S.key_check_tonic` / `S.key_check_minor`, also cleared on project switch. |
| `rock_band_general_helper_vkr/difficulty_suggester.lua` | `SuggestProjectDifficulties`, `CountVocalParts`, `HasAnyChartTrack` (global); `Unavailable`, `NoContent`, `SuggestOne` (local) — the read-only Metadata > Difficulty adapter. Returns one record per instrument (`rank`, `tier`, `tier_position`, `factors`, or `ok = false` with a `reason`); never touches `S`, never writes, never creates an undo point. Scores the **whole** chart — a time selection is deliberately not consulted, because the models were calibrated on whole songs. `CountVocalParts` derives `vocal_parts` from HARM2/HARM3 carrying notes, which reproduces the `songs.dta` field on all 203 corpus vocal songs. Reports "absent" and "muted" separately rather than calling `GetMutedInstruments`, which conflates them (see the comment there). |
| `rock_band_general_helper_vkr/tempomap.lua` | `ComputeTempoRMSContour`, `DetectOnsets`, `EstimateBPM`, `GuessTimeSig`, `GetSourcesForRange`, `FitBeatGrid`, `RmsToOnsetFlux`, `FindLocalPeak` |
| `rock_band_general_helper_vkr/actions.lua` | `AlignAudioTracks`, `AlignAllAudio`, `AlignCountIn`, `CreateSongFadeOut`; `CountInBeatSlots` (local) |
| `rock_band_general_helper_vkr/actions_stem_import.lua` | `StemImportPlan`, `ImportStems` (global); `AUDIO_EXTS`, `KIT_EXCLUDE`, `STEM_RULES` (module-level locals); `HasAll`, `HasAny`, `Shortest`, `PickForRule`, `PickStemFolder`, `ListFolderFiles`, `InsertStemItem` (local) — General > Actions' "Import stems". `StemImportPlan(filenames)` is **pure** (no `r`): it maps filenames to template tracks by lowercase substring keyword, running `STEM_RULES` in a fixed order where a file claimed by one rule is no longer a candidate for later ones (so `drums_kick` goes to KICK AUDIO only), with the shortest base name winning ties and alphabetical order breaking equal lengths. KIT AUDIO rejects single-piece stems via `KIT_EXCLUDE`, because names like `drums_hh` are shorter than `drums_kit` and the shortest-name rule alone would pick them. `ImportStems` requires a SONG AUDIO audio item and places every stem at its position. It never touches a track that already holds audio, and it sorts every rule into a bucket before writing, so a run with nothing to import creates no undo point. The folder dialog comes from js_ReaScriptAPI when it is installed; otherwise the native file dialog is used and the picked file's folder is scanned |
| `rock_band_general_helper_vkr/actions_tempomap.lua` | `ShowTempoContext`, `EstimateInitialBPM`, `AutoTuneThreshold`, `ClearGeneratedTempoMarkers`, `GenerateTempoMap`; `BPM_MIN`, `BPM_MAX` (locals) |
| `rock_band_general_helper_vkr/actions_venue_manual.lua` | `InsertVenueEventAtPlayhead`, `AdvanceCameraPacing`, `GenerateManualKeyframes`, `RemoveVenueEventsByType`, `FindManualLightingAtPpq`, `FindNextVocalPhraseStartPpq`, `ResolveBlendSource`, `BlendVenuePresetAtPlayhead`, `NO_LIGHTING_AT_PLAYHEAD_MSG` (global); `_spot_tol` (local) — Manual gen actions |
| `rock_band_general_helper_vkr/section_events.lua` | `SECTION_EVENT_GROUPS`, `SECTION_EVENT_BASE` — EVENTS-track event vocabulary (groups, per-base number/letter caps) for the Events sub-tab; data only, no S/REAPER deps |
| `rock_band_general_helper_vkr/actions_venue_events.lua` | `FindEventsTake`, `ScanEventsTextEvents`, `NextSectionEvent` (pure), `ValidatePlainInsert` (pure), `InsertEventsEvent`, `AddSectionEvent`, `ClearAllEventsTexts`, `InsertEventsBookends` (global) — Events sub-tab actions + validation |
| `rock_band_general_helper_vkr/actions_venue_keyframes.lua` | `RegenerateVenueKeyframes` (global) — Keyframes tab action: bulk-regenerates keyframes for every manual lighting event on the VENUE track |
| `rock_band_general_helper_vkr/actions_venue_validate.lua` | `ValidateVenueLightingBlends` (pure), `ValidateVenueLighting` (global); `NEAR_FIRST_BEATS`, `NearestIndex` (local) — Actions tab's "Validate lighting/blends": `[first]` placement against the preset-change rule, stray-`[first]` classification, and missing blend anchors for lighting and postproc. Read-only |
| `rock_band_general_helper_vkr/actions_venue_validate_camera.lua` | `BuildBandLineups`, `ValidateVenueCameraStacks` (pure), `ValidateVenueCamera` (global); `NEAR_STACK_QN`, `UNCOVERED_LIST_MAX`, `COOP_DUO_SET` (local) — Actions tab's "Validate camera stacks": duplicates, near stacks, shots that win under no lineup, and lineups with no valid camera shot. Read-only. Reads `CAM_PRIORITY_TIERS` at load time, so it must load **after** `venue_camera_priority.lua` |
| `rock_band_general_helper_vkr/actions_venue_sing_along.lua` | `GenerateSingAlong` (global) — Analysis tab action: derives VENUE pitch 85/87 sing-along notes from HARM2/HARM3 vocal phrases; `AvailableHarmTake`, `PhraseSourceTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans` (local) |
| `rock_band_general_helper_vkr/actions_venue_subtracks.lua` | `VENUE_SUBTRACKS`, `CategorizeVenueEvent` (the shared 6-way event classifier, also used by `actions_venue_manual.lua`'s `RemoveVenueEventsByType`), `FindOrCreateSubtrack`, `EnsureMatchingItem`, `CopyVenueEvents` (logic helpers, global for testability), `CopyVenueToSubtracks`, `CopyAllSubtracksToMain`, `CopySelectedSubtrackTo`, `CopySelectedSubtrackFrom` (global) — Actions tab's "Sub VENUE tracks" split/merge feature; `_find_venue_track_and_take` (local) |
| `rock_band_general_helper_vkr/ui_venue.lua` | `DrawVenueTab`, `RenderCamPacingRow`, `RenderKeyframeAlignCombo` (global) — Venue tab bar (Actions, Events, Themes gen, Section gen, Manual gen, Keyframes, Preview; only Actions and Themes gen are drawn inline — every other sub-tab delegates to its own file) plus the camera-pacing / keyframe-align widgets shared by the generation sub-tabs |
| `rock_band_general_helper_vkr/ui_venue_section_gen.lua` | `DrawVenueSectionGenTab` (global) — Section gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_manual.lua` | `DrawVenueManualTab` (global) — Manual gen sub-tab rendering |
| `rock_band_general_helper_vkr/ui_venue_events.lua` | `DrawEventsTab`, `DrawVenueEventsTab` (global); `DrawEventsGeneralTab` (local) — the Events tab: its sub-tab bar, the General sub-tab, and the Manual gen body |
| `rock_band_general_helper_vkr/ui_venue_preview.lua` | `DrawVenuePreviewTab` (global) — Preview sub-tab rendering; caches the VENUE event lists + muted instruments, refreshed on any project state change with a 5 s fallback and a self-pause when one read takes ≥ 0.15 s. Each column is a **PPQ group** (`_group_at`), not one event: camera groups resolve through `PickPriorityCameraEvent`, lighting/post-process take the group's last event. When no shot in a group fits the Players combo the group's last event is drawn in red and `_FALLBACK_NOTE` explains the game's own fallbacks below the row. Lighting/post-process arrive already collapsed by `AnnotateVenueBlends`, so a blend anchor is never a card of its own; `_transition_line` turns its annotations into the line under each timestamp (`blends into next` / `blending now` / `hard cut to next`, blank for camera and for the last event of a kind). That line is drawn even when blank — a column one text line shorter than its neighbours would push its sprite out of alignment. |
| `rock_band_general_helper_vkr/ui_venue_players.lua` | `DrawActivePlayersRow` (global) — Active players dot row shown under every Venue sub-tab and in the standalone preview; PART-track play-state scan cached via `MakeProjectPoll(1.0, 5.0)`, playhead lookup recomputed on playhead change (≥ 0.5 s cadence during playback) |
| `rock_band_general_helper_vkr/ui_venue_keyframes.lua` | `DrawVenueKeyframesTab` (global) — Keyframes sub-tab rendering |
| `rock_band_general_helper_vkr/ui_animation.lua` | `DrawAnimationTab` (global); `DrawAnimationBeatTab`, `DrawAnimationCharacterTab`, `StateCombo`, `RefreshReadout` (local) — the Animation tab: its sub-tab bar, the Beat and Character sub-tabs |
| `rock_band_general_helper_vkr/ui_workflow.lua` | `DrawGeneralWorkflowTab` (global) — Workflow tab rendering (the name predates the tab being promoted from General) |
| `rock_band_general_helper_vkr/ui.lua` | `Loop`, `r.defer(Loop)` |

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
- `actions_venue_sing_along.lua`: `RB3_VOCAL_MIN`, `RB3_VOCAL_MAX`, `RB3_PHRASE_PITCH` (module-level locals), `AvailableHarmTake`, `PhraseSourceTake`, `ReadPhrasesAndVocalNotes`, `MeasureDurationAtTime`, `BuildSpans`
- `actions_venue_events.lua`: `_round_ppq`, `_is_crowd`, `_bare_form`, `_letter_form`, `_family_span`, `_spot_conflict`, `_require_take`, `_insert`, `_refuse`; `BOOKEND_EVENTS` (module-level local)
- `workflow.lua`: `FindBraceGroups`, `StripBraceGroups`
- `ui_venue_events.lua`: `_draw_prc_row`, `_draw_plain_row`
- `metadata_genres_lookup.lua`: `PairKey`, `BuildCaches`, `_family_cache`, `_by_key`, `_reverse`
- `ui_metadata_genre.lua`: `DimWrapped`, `ClampIdx`, `DrawSubgenreDoc`, `DrawForward`, `DrawReverse`
- `actions.lua`: `CountInBeatSlots`
- `actions_stem_import.lua`: `AUDIO_EXTS`, `KIT_EXCLUDE`, `STEM_RULES` (module-level locals), `HasAll`, `HasAny`, `Shortest`, `PickForRule`, `PickStemFolder`, `ListFolderFiles`, `InsertStemItem`
- `actions_tempomap.lua`: `BPM_MIN`, `BPM_MAX` (module-level locals)
- `ui.lua`: `Loop`

**Load order:**
```
lib/reaper_imgui_helpers.lua   → Tooltip, SliderTooltip, SectionHeader, GetTrackList,
                                  FormatTime, GetTimeSelection
lib/reaper_helper_common.lua   → FindTrackByName, TrackAtIndex, GetTakePPQPerQN, GetTempoContextBefore,
                                  RefreshTrackLists, RunAction
lib/reaper_helper_ui.lua       → TrackCombo (REAPER index, (none) = -1), MidiEditorTrackWarning,
                                  DrawResultPanel, DrawHelperFooter
lib/reaper_dsp.lua             → ComputeCMND, SearchYINTau (for lib/reaper_key_audio.lua)
lib/reaper_midi_helpers.lua    → FindFirstMIDIItem, InsertNotes, ClearNotesAtPitchesInRange, …
lib/reaper_script_links.lua    → SCRIPT_LINK_GROUPS, ScriptLinkBasename, IsRunningScriptLink,
                                  FilterScriptLinkGroups, LaunchReaScript, DrawGeneralLinksTab
                                  (General > Other tools sub-tab; shared with the instrument and vocal helpers)
lib/reaper_difficulty_*.lua    → score, tiers, predict, models, read (Metadata > Difficulty)
lib/reaper_key_detect.lua      → KeyFeatures, KeyRankSet, KeyConfidence, KeySetLabel, KeyName,
                                  KeyRelation, KeyScaleText, KeyTrackReport
lib/reaper_key_profiles.lua    → RB_KEY_PROFILES (generated; Metadata > Song key)
lib/reaper_key_audio.lua       → KeyAudioNotes, KeyAudioPickSet, KEY_AUDIO_SR, KEY_AUDIO,
                                  KEY_AUDIO_BASS, KEY_AUDIO_SETS
                                  (uses reaper_dsp.lua's ComputeCMND / SearchYINTau)
defaults.lua                   → S, VENUE_VALID, TIPS, constants
settings.lua                   → SaveSettings, LoadSettings
helpers.lua                    → FindNamedTrackMIDI, SetDefaultTracks,
                                  GetMeasureStartTime, GetAudioItems
venue.lua                      → ListVenueEvents, GetVenueEventsForPreview,
                                  IsBlendAnchor, AnnotateVenueBlends
venue_awareness.lua            → GetMutedInstruments, GetCoopRequiredInstruments,
                                  GetDirectedRequiredInstruments, FilterPool,
                                  ReadEventSections, ListEventSections, FindMusicStartTime,
                                  INST_LETTER_NAMES
animation_beat.lua             → BeatPlan, ReadProjectBars, GenerateBeatTrack
animation_character.lua        → CHAR_* tables, CharacterPlan, GenerateCharacterAnimations,
                                  InsertCharacterState, CharacterStateAt, CharGroupStatus
animation_drums.lua            → DRUM_ANIM_* tables, DrumAnimPlan, DrumAnimOnsets,
                                  DrumAnimDiscoSpans, GenerateDrumAnimations
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
ui_venue.lua                   → DrawVenueTab, RenderCamPacingRow, RenderKeyframeAlignCombo
ui_venue_section_gen.lua       → DrawVenueSectionGenTab
ui_venue_manual.lua            → DrawVenueManualTab
ui_venue_events.lua            → DrawEventsTab, DrawVenueEventsTab
ui_venue_preview.lua           → DrawVenuePreviewTab
ui_venue_players.lua           → DrawActivePlayersRow
ui_venue_keyframes.lua         → DrawVenueKeyframesTab
ui_workflow.lua                → DrawGeneralWorkflowTab
ui_animation.lua               → DrawAnimationTab
song_key.lua                   → SuggestProjectSongKey (loaded after metadata_genres_lookup.lua)
song_key_audio.lua             → SongKeyAudioStart/Step/Busy/Cancel/Result, SuggestAudioSongKey
ui_metadata_key.lua            → DrawMetadataKeyTab (loaded before ui_metadata.lua)
ui.lua                         → Loop (also calls r.defer(Loop))
[entry point startup]          → LoadSettings(), SetDefaultTracks()
```

**`SCRIPT_MDIR` global.** The entry point sets `SCRIPT_MDIR = _mdir` (global) so dofile'd modules can access the module folder path for filesystem operations. The `local _mdir` variable is not accessible from dofile'd modules. **`SCRIPT_DIR` global.** The entry point also sets `SCRIPT_DIR = _dir` (repo root) for accessing shared resources under `resources/` (e.g. `resources/themes/`, `resources/img/spritesheets/`).

**Polling convention for continuous MIDI reads.** UI draw code that reads project MIDI every frame is forbidden — gate the read behind `MakeProjectPoll(min_secs, fallback_secs)` (`lib/reaper_helper_common.lua`): it fires when `GetProjectStateChangeCount` changed (subject to `min_secs`) or `fallback_secs` elapsed (safety net for count collisions across project switches). Heavy multi-track scans use `min_secs = 1.0` (protects against per-frame count churn while dragging notes in a MIDI editor). Only pure-Lua lookups over the cached data may run per frame; lookups that follow the *play* position during playback should recompute at a ~0.5 s cadence, while stopped-cursor moves recompute immediately (the lookup is cheap; a debounce would only add lag). Cached take pointers must be `ValidatePtr2`-checked before use. Note: `GetProjectStateChangeCount` only increments when an **undo point** is registered — bare API edits without an undo block are invisible to the count gate (they are still caught by the `fallback_secs` rescan). All helper edit paths create undo points (the mandatory undo-block pattern), as do user edits in REAPER, so in practice only undo-less test/script edits need care. Current adopters: `ui_venue_players.lua`, `ui_venue_events.lua`; `ui_venue_preview.lua` keeps its own immediate-on-change + self-pause variant; the vocal helper's tuner (audio, 100 ms + playhead gate) is intentionally separate.

**Second entry point: `rock_band_preview_vkr.lua` (repo root).** Standalone Venue Preview window. It has no module folder of its own — it dofiles a subset of this helper's modules: `lib/reaper_imgui_helpers.lua`, `lib/reaper_helper_common.lua`, then `defaults.lua`, `settings.lua`, `helpers.lua`, `venue.lua`, `venue_awareness.lua`, `venue_camera_priority.lua`, `venue_sprites.lua`, `ui_venue_preview.lua`, `ui_venue_players.lua`, and runs its own minimal `Loop` calling `DrawVenuePreviewTab()` + `DrawActivePlayersRow()`. Consequences when editing those files:
- They must keep working without the rest of the general helper loaded — do not add load-time or call-time dependencies (from the preview code path) on modules outside this subset. `settings.lua` guards its `SaveSectionConfigs`/`LoadSectionConfigs` calls (`if X then X() end`) for this reason.
- `venue_camera.lua` is **not** in the subset, so nothing on the preview path may read `COOP_POOL`, `COOP_LABELS`, `DIRECTED_TIPS` or anything else it defines. This is why the shot-priority tables live in their own `venue_camera_priority.lua` rather than beside the pools — the preview needs them and cannot afford to pull in the generator.
- `venue_sprites.lua` reads `SCRIPT_DIR` at dofile time; both entry points set it before loading.
- The standalone calls `LoadSettings()` at startup and on project switch, but never `SaveSettings()` (saving stays in the general helper's General tab).
- **A fix to any file in that subset changes this window too, so it needs its own `@version` bump and its own `@about` entry** in the same task as the general helper's — otherwise its version silently stops describing the code it runs. See `CLAUDE.md` → "Bumping a helper means checking its standalones".


### Save / Load

Section `RBHelperVKR`, key `settings_v1`. Auto-loads on script open.

**Saved:** all tempo map sliders — primary source (`tm_rms_threshold`, `tm_rms_window_ms`, `tm_search_window_ms`, `tm_drift_threshold_ms`, `tm_bpm_failsafe`, `tm_first_measure`, `tm_timesig_num`, `tm_override_failsafe`), fallback source (`tm_fb_rms_threshold`, `tm_fb_rms_window_ms`, `tm_fb_use_flux`), auto-tune (`tm_autotune_density`), the Venue settings, Show WIPs?, and the Workflow sub-tab's selected template name (`workflow_file_name`) and "Show completion timestamp" checkbox (`workflow_show_ts`), Animation > Beat's half-time downbeat style (`beat_half_style`, key `abhs`), and Animation > Character's per-group active states (`char_active`, keys `acsd`/`acsg`/`acsb`/`acsv`/`acsk`), idle gaps (`acgi`, `acgv`) and "Idle in long gaps" (`acig`), and Animation > Drums' options (`adcr`, `adbh`, `admc`, `adfl`, `adsv`, `adso`, `adra`, `adfll`). The Instrument Helper's tabs save under their own key (`.claude/CLAUDE_instrument.md` → Save / Load); a blob saved before the split still carries their fields, which `DeserializeSettings` ignores and the next Save drops.
**Not saved:** track indices — positional, brittle. `SetDefaultTracks` re-detects the tempo map and Song key audio tracks by name. It only assigns fields that are still -1 (do not override saved state).

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


## Feature: Animation > Beat

`animation_beat.lua` writes the BEAT track (note 12 = downbeat on a bar's first beat, 13 = upbeat on its other beats - "upbeat" as the RBN docs, CAT and the community template name it; user-facing text uses the words, not the numbers) - what CAT's "Create BEAT track notes" and "Halve BEAT track notes" do. `BeatPlan(bars, opts)` is pure; `GenerateBeatTrack(half)` reads the measures with `TimeMap_GetMeasureInfo` and writes in quarter notes (`MIDI_GetPPQPosFromProjQN`), so no tick rate is assumed.

Rules, measured over the official RB3 DLC BEAT tracks (591 songs):
- **One note per quarter note, counted from each bar line, in every meter.** 6/8 gets three notes on quarters, not two dotted quarters. A quarter that starts inside the bar gets a note even when the bar ends half a beat later: 7/8 = `D u u u`, 5/8 = `D u u`. CAT and the RBN doc's 7/8 example count only full beats (7/8 = three notes); no official 7/8 bar does that, so the official way was chosen.
- **Measure 1 up to `[end]`, never on it.** 589/591 official tracks start at measure 1; 541 end one quarter before `[end]`, only 5 put a note on it. A time selection narrows the range (start inclusive, end exclusive) and is clipped to `[end]`. Existing BEAT notes starting in the range are replaced; a whole-song run replaces every note in the take.
- **Half time**: a note every two quarters, each bar restarting at its bar line, so odd bars (3/4, 5/4, 6/8) leave the shorter gap before the next bar (CAT; 2 of the 3 official songs with halved odd bars). Bars too short for two notes (2/4, 3/8, 4/8 halved; 1/4, 2/8 normal) are written with the strict spacing and no fallback - a method waits for user data or official evidence.
- **The beat just before `[end]` always gets a note**, half time included. Magma refuses a song without one (verified with Magma: 4/4 with `[end]` on beat 3 fails when beat 2 is empty). Half time steps one beat instead of two when the next step would reach `[end]`, as CAT does, so the last bar can end `D u u` (beats 1, 3, 4).
- **Half-time downbeat** (`S.beat_half_style`): 0 = every other bar (default: CAT and about 12 of 14 halved official songs), 1 = every bar. Parity counts from the bar holding the range start, so a selected halved section starts on a 12.
- Velocity 100 (official); length a 16th (CAT; length has no effect in game).
- Needs a BEAT track and an `[end]` text event on EVENTS. No MIDI item on BEAT -> one is created from measure 1 to `[end]`; an item too short for the range stops the run instead of being resized. One undo block.

**The RBN doc's BEAT rule is wrong or outdated.** The RBN documentation says every measure must have at least one downbeat (12) and one upbeat (13) "for in-game animations", as a Magma compile error, and that a short measure such as 1/4 is best merged with a neighbouring measure. Tested with Magma: all three modes (normal, half time with the downbeat every other bar, half time with it every bar) compile, with bars that have no 12. The only BEAT check Magma enforced was the beat before `[end]` (above). CAT's halving and most halved official songs also leave every second bar without a 12. The doc also describes halving as being for animation purposes.

Tests: `dev/tests/animation_beat.lua` (planner cases also run offline with a stub `r`; the integration cases need a project with no BEAT / EVENTS track whose first bars are 4/4).

## Feature: Animation > Character

`animation_character.lua` writes the character animation state text events (type 1) on each part track. Active states `[play]` `[mellow]` `[intense]` (+ `[play_solo]`, guitar/bass), idle states `[idle]` `[idle_intense]` `[idle_realtime]`. `CHAR_STATES` carries each state's RBN description - the guitar/bass page's wording for instruments, the vocal page's for Vocals/HARM1 - and the UI shows it as the tooltip on every dropdown entry and Manual button (kept with the data rather than in `TIPS`, since it belongs to a state, not to a widget).

**Tracks.** PART DRUMS, PART DRUMS_2X, PART GUITAR, PART BASS, PART KEYS, PART VOCALS, HARM1, each from its own Expert notes (drums 95-100, guitar/bass/keys 96-100, vocals 36-84 so vocal percussion does not count). PART DRUMS_2X is not in the official charts (they never shipped 2x), but Magma turns it into PART DRUMS, so it needs the same events. Not written: HARM2/3 (official almost never) and PART REAL_KEYS_* - none of 427 official Pro Keys songs carries a state event there, PART KEYS does; revisit if Magma or the game turns out to need them. Muted tracks get nothing.

**Generate rules**, measured over the official RB3 DLC charts (591 songs) and matched against CAT's `create_animation_markers`:
- Notes merge into runs (a sustain keeps the part playing). The active state goes 1 QN before a run, `[idle]` 1 QN after a run's end (official: 0.5-1 QN both ways; the RBN vocal doc: "a beat or so" after the last note).
- A gap idles when it is at least the part's threshold, in bars of 4 QN: instruments 3 (CAT; official instruments idle ~50% of 2-3 bar gaps, ~70% of 3-4, ~80% of 4+), vocals 2 (official vocals 29% of 1-2 bar gaps, 71% of 2-3, 93% of 3+; the vocal doc: never idle for less than a measure). Both are sliders.
- "Idle in long gaps" off keeps every part active through rests. A rare official style: of the parts with 2+ rests of 4+ bars, 15/442 never idle in them (guitar 8/55, bass 4/43, vocals 2/215, keys 1/115, drums 0/14), 48 idle in some and 379 in all. Per-rest choice is the commoner variation, which Generate-then-Manual covers. The "high-energy songs" use is the user's idea; the never-idle songs found are not obviously high-energy.
- Start: first note more than 1 QN after bar 3 -> `[idle]` at bar 3, then the active state (CAT; the official charts' usual opening). Otherwise the active state 1 QN before the first note, not before bar 2.
- `[idle_realtime]` 1 QN after the last note (official: ~99% of tracks).
- Active state per group (Drums = PART DRUMS + PART DRUMS_2X, Guitar, Bass, Vocals = PART VOCALS + HARM1, Keys), plus a Set all dropdown. A row is disabled when every track of its group is missing or muted.
- Replaces all seven state texts on the track; with a time selection only those inside it, while the plan is still made from the whole song so the states line up. Events outside the MIDI item are counted and listed, never written.

**UI.** A Mode radio (Generate / Manual, persisted `acmd`) shows one panel at a time, as Venue > Section gen does. Visible options use readable names (`CHAR_STATES[].label`: Play, Mellow, Intense, Play solo, Idle, Idle intense, Idle realtime), as Venue > Manual gen does; results / status keep the event text. Every state tooltip (dropdown entries, a closed dropdown, the At playhead readout) has the Directed camera layout, built from `venue_sprites.lua`'s `BeginVenueTooltip` / `DrawVenueTooltipSprite` / `EndVenueTooltip` (unchanged, so the Venue Preview standalone that loads it is unaffected): sprite, RBN description, separator, the event text greyed. No label line (Directed camera adds one only on the closed dropdown; here it would repeat what the widget shows). Sprites are category `Animation`, folder `resources/img/spritesheets/animation/` (or `animation small/`), file `{key}_f{frames}_spritesheet.jpg`; the key tries `{group}{state}` first (`guitarplay`, `vocalsidlerealtime`; group = a `CHAR_GROUPS` key, so Drums 2X uses drums and HARM1 vocals), then `{state}` for every part (`idle`). No sheets exist yet - without one the tooltip is text only. Descriptions carry no hard line breaks: the tooltip wraps them to the sprite width.

**Ride options (Drums, Manual only).** `CHAR_RIDE_EVENTS`: `[ride_side_true]` ("Ride side swipe", Max Weinberg's side swipe on slow ride hits) and `[ride_side_false]` ("Ride normal"), from the RBN drum doc. No official RB3 DLC chart uses either (0 of 591 songs). They are not states, so they live in their own set (`CHAR_RIDE_SET`): Generate never deletes them, the state readout ignores them, and inserting one replaces only a ride option on that tick (`DeleteStates` / `CharacterStateAt` take the set to use).

**Manual** - Part dropdown, State dropdown (Play solo only for Guitar/Bass; the ride options below a separator for Drums / Drums 2X) and an Insert button that reads Replace when a state already sits on the playhead; it writes at the edit cursor on one track and replaces a state on that tick. Muted tracks are refused. "At playhead" shows the last state at or before the cursor and where it is: "on the playhead" or "from <bar.beat>" (`CharacterStateAt` returns the event's ppq too). Rescanned when the poll fires or the cursor / part changes.

Tests: `dev/tests/animation_character.lua` (planner cases offline with a stub `r`; the integration cases need a project with no part track whose first bars are 4/4).

## Feature: Animation > Drums

`animation_drums.lua` writes the drummer's animation notes on PART DRUMS and PART DRUMS_2X (Magma turns 2X into PART DRUMS) from the Expert gems (95-100, 95 = 2x kick), tom markers (110-112) and disco flip spans. Notes (RBN drum doc "Animations"): kick 24, hi-hat pedal 25, snare L/R 26/27 (soft 28/29), hi-hat L/R 30/31, percussion 32, crash 1 L 34/35 and R 36/37, crash 2 R 38/39, chokes 40/41, ride R/L 42/43, crash 2 L 44/45, tom 1 L/R 46/47, tom 2 L/R 48/49, floor tom L/R 50/51. `DrumAnimPlan` is pure; `dev/tools/drum_anim_eval_offline.lua` scores it against the official charts' own animation notes (every official song has them: 588/588).

**Hold-out.** Declared 2026-11-08 before any tuning: every 5th song by sorted shortname (121 songs). **Run once on 2026-11-08 (SPENT)** with the rules as documented here (118 songs with PART DRUMS): hand on one-hand hits **94.4%** (CAT-like 83.4%, usual hand only 84.0%; fast < 130 ms 91.3% vs CAT 67.8%; 130-220 ms 93.2% vs 80.7%; slower 97.1% vs 93.9%), piece 89.9%, two-hand exact 88.5%, every hand hit exact 85.7%, snare-only hits exact 91.9%, kick 99.9%; with Blue cymbal = Open hi-hat picked for its 10 songs: piece 90.8%, every hand hit 86.4%. In line with dev (93.5% hand), so the rules were not overfitted. Further tuning needs a new declared song set - never tune on the hold-out.

**Pieces** - CAT's mapping, confirmed by the official charts: yellow cymbal hi-hat (91%), blue cymbal ride (78%), green cymbal crash 2 (option crash 1), red snare, tom markers tom 1 / tom 2 / floor tom. Disco flip (`[mix 3 drumsNd]` up to the next Expert mix event; `...dnoflip]` is not a flip): red is the hi-hat, yellow the snare. Crash 1 vs crash 2 is a per-song choice in the official charts (songs spread evenly from <10% to 90%+ crash 1); context rules (crash 1 after hi-hat playing, staying on a crash in a run) measured no better than the plain default, so it is the "Default crash" option. Blue cymbal: some charts put the closed hi-hat on yellow and the open hi-hat on blue - 37 of 338 dev songs with 20+ blue hits play blue as the hi-hat 99% of the time (alone, in runs, under an open or closed pedal); 217 play it as the ride (89%), 84 mix. No gem pattern separates them (blue near yellow: 31 of the 37, but also 19 ride songs), and the official pedal notes would, but community charts often have none - so it is the "Blue cymbal" option (Ride / Open hi-hat; a blue sharing its hit with the hi-hat stays the ride). With Ride, a lone blue (no other blue cymbal within 1 QN, no other cymbal on the hit, no disco flip; 5% of blue hits) is crash 1: official crash 1 32% / crash 2 23% / hi-hat 21% / ride 21%.

**Hands** - the kit left to right: hi-hat, crash 1, snare, tom 1, tom 2, floor tom, crash 2, ride. Official left-hand share per piece follows it (hi-hat 12% - crossed, crash 1 24%, snare 67%, tom 1 57%, tom 2 30%, floor 14%, crash 2 and ride 1%), which gives each piece its usual hand. Then, in order:
- Hands alternate only when hits come fast: drums under 170 ms (same drum 87-92%, drum to drum 98%; slower, one hand repeats - same drum at 220 ms+ switches 15%); cymbals under 130 ms once `min_cym_hits` (3) are in a row, or 130-170 ms in runs of 8+ (official cymbal switching by run length at 130-170 ms: 2-3 hits 18%, 4-7 54%, 8-15 76%, 16+ 90%). CAT's own minimum is 4; 3 scored best on dev. Hi-hat 16ths: a disco beat always alternates (official 98-100%, under 170 ms); plain ones alternate from 110 BPM (`hh16_fast_ms` 137: official 83% at 110-129 BPM, 46% at 95-109, 24% slower - one style per song in between: 54 songs one hand, 27 alternate). 8ths at 170+ BPM, 8th triplets and ride 16ths never alternate at 130-170 ms (0%).
- A fast run takes its phase from the beat, not from the previous hit (official 87-89% of fast hits): beat and 8th "and" right, 16th "e"/"a" left; 32nd and sextuplet runs count steps of their own spacing from the beat (even right). A triplet drum hit straight after a cymbal stays on that hand (shuffles). Alternating from the previous hit instead was the biggest single error source (fast hits 71% -> 90%). Exception: a drum within 170 ms of a one-hand cymbal hit takes the other hand from the cymbal, whatever the beat (official 96-100%; fast hits 91.3% -> 93.1%). The mirror case (a cymbal straight after a drum) measured +0.03 points and keeps the beat phase.
- Moving to another drum at slower speeds: the hand on that side takes it - moving right (towards the floor tom) R 83%, moving left L 80%. A tom straight after a groove hit: R. Crash 2 straight into crash 1: crash 1 by L (89%).
- Slow lone snare ("Slow snare variety", on): official L 50% / R 28% / both 22%. Ghost notes off the 8th grid L (83%); before a cymbal L (80%); in a slow snare-only passage R (40-52%); on the beat after a 0.5 s pause or next to toms both hands (~43%). Off = left hand always. The rules cost ~1 point of exact match (the plural case is weak) and are kept for the varied look the official charts have.
- Two hands on one hit: snare L + the other piece R (groove crossed); hi-hat + crash = crash 1 L + crash 2 R (96%, CAT's table); snare + blue tom = snare L + floor tom R (52% vs tom 2 38%); snare + yellow tom = both hands on the snare ("Flam", on - official 83%; CAT has it off); otherwise the left piece L, the right piece R.

**Options** (CAT's plus the RBN doc tips, each checked): Default crash (crash 2), Blue cymbal (ride), Min cymbal hits (3), Flam (on), Slow snare variety (on), Soft hits (off - official soft ~1 in 9), Crash riding soft / hard (off - official alternates only on 8ths, 6% of runs, 13% when slow; quarters 0%, 16ths 0% but often all soft), Flam left hand late by a 1/32 note (off - official flams are on one tick; true sub-1/16 offsets 61 of ~9600). Not generated: uncrossed hands (LH hi-hat / crash 1 + RH snare: 390 hits in 53 official songs - a deliberate touch, left to the author).

**Scores on dev (470 songs):** hand on one-hand hits 93.5% (CAT-like rule 84.2%, usual hand only 84.1%; fast < 130 ms 93.1% vs CAT 69.7%; 130-220 ms 90.9% vs 81.4%; slower 95.6% vs 92.6%), piece 90.2%, two-hand hits exact 87.6%, every hand hit exact 85.2%, kick 100%. With Blue cymbal = Open hi-hat picked for the 37 songs that play it that way (`DRUM_ANIM_BLUE=pick`): piece 91.2%, two-hand 88.2%, every hand hit 86.1%. Try a change with `DRUM_ANIM_SET="key=value,..."` (overrides `DRUM_ANIM_PARAMS`). Ceiling (dev, measured once): one rule for every song on piece / previous hit / speed / beat position / the official previous hand / direction reaches 95.6% hand; the same chosen per song 99.0% - the rest is per-song style. A few official songs' animations do not follow the gems at all (piece 5-23%).

**Hi-hat pedal (25) - not generated** (song-dependent; left to the author, maybe a Manual mode later). Official use, for reference: in every song; mostly short openings (1/8-1/2 QN) repeating every beat or half beat, 84% starting off the beat; 66% with no hand on a cymbal (left-foot taps), 23% with the ride, 10% with a crash; 23% of hi-hat hand hits fall under an open pedal; the hat is open 30%+ of the song in half the songs. Gem velocity does not mark open hats (96 / 100 either way) and CAT never writes the pedal.

**Action.** Muted tracks skipped (a missing PART DRUMS_2X is normal). Replaces notes 24 and 26-51 that start in the time selection (or the whole take) - never 25. Notes are 1/8 QN long, velocity 100, written in one bulk round trip (`ReplaceNotesBulk`, `lib/reaper_midi_helpers.lua`; per-note inserts took 5-25 s per song), then one `MIDI_Sort`; the result reports the time when a run takes over 2 s. One undo block with `MarkTrackItemsDirty`.

Tests: `dev/tests/animation_drums.lua` (planner cases offline with a stub `r`; integration cases need a project with no drums track).

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
