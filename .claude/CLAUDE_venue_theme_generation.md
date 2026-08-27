# Venue Theme Generation — Implementation Notes

Reference document for the themed VENUE event generator in `rock_band_general_helper_vkr`.
Read this before touching any venue-related file. Complements `CLAUDE_general.md`.

---

## What was built

A section-aware VENUE event generator driven by `.rbtheme` preset files. The generator
reads `[prc_*]` section markers from the EVENTS track and uses per-section lighting,
camera, and postproc presets defined in the selected theme.

When no theme is selected the generator falls back to the original fully-random mode.

---

## New and modified files

| File | Role |
|------|------|
| `rock_band_general_helper_vkr/venue_themes.lua` | `.rbtheme` parser + public preset API |
| `rock_band_general_helper_vkr/venue_awareness.lua` | `[prc_*]` section detection (pre-existing, no change) |
| `rock_band_general_helper_vkr/venue_camera.lua` | Camera pools, weighted picking, `GenerateCameraEvents` |
| `rock_band_general_helper_vkr/venue_lighting.lua` | Lighting generation, section processing, `GenerateThemedSectionEvents` |
| `rock_band_general_helper_vkr/venue_generator.lua` | `GenerateVenueEvents` orchestration only |
| `rock_band_general_helper_vkr/themes/*.rbtheme` | 10 bundled theme files |
| `rock_band_general_helper_vkr/defaults.lua` | Added `S.venue_theme_idx`, `S.venue_theme_name`, `S.venue_themes`, `TIPS.venue_theme`, `TIPS.venue_keyframe_align` |
| `rock_band_general_helper_vkr/settings.lua` | Serialize/deserialize `venue_theme_name` (key `vthn`) and `venue_keyframe_align` (key `vkfa`) |
| `rock_band_general_helper_vkr/ui.lua` | Venue tab: lazy-load themes, theme combo, keyframe align radios |

Load order in entry point:
```lua
dofile(_mdir .. 'venue_awareness.lua')
dofile(_mdir .. 'venue_themes.lua')      -- before camera/lighting/generator
dofile(_mdir .. 'venue_camera.lua')      -- pools, weighted picking, camera generation
dofile(_mdir .. 'venue_lighting.lua')    -- lighting, section processing, keyframe logic
dofile(_mdir .. 'venue_generator.lua')   -- GenerateVenueEvents orchestration only
```

---

## `.rbtheme` file format

S-expression format (Lisp-like). Lines starting with `;` are comments. The file is
parsed by `venue_themes.lua` using a hand-written recursive descent S-expression parser.

```lisp
(camera_pacing medium)          ; global camera pace: crazy|fast|medium|slow|minimal

(section_presets

  (default                       ; fallback for any section not listed below
    (allowed_lightpresets loop_warm loop_cool)
    (allowed_postprocs ProFilm_a.pp)
    (lightpreset_blendin 2)
  )

  (intro
    (allowed_lightpresets silhouettes_spot loop_warm)
    (allowed_postprocs  ProFilm_a.pp)
    (lightpreset_blendin 4)
  )

  (verse1                        ; matches [prc_verse_1]; verse2..N loop back
    (allowed_lightpresets manual_cool)
    (allowed_postprocs ProFilm_a.pp)
    (lightpreset_blendin 2)
    (keyframe_rate 2)
  )

  (chorus1
    (allowed_lightpresets chorus)
    (keyframe_rate 1)
    (dircut_at_start directed_all)
    (lightpreset_blendin 1)
    (bonusfx_at_start)
  )

)
```

### Section key matching

The EVENTS track marker `[prc_verse_3]` is parsed as `{name="verse", num=3}`.

Lookup order in `GetSectionPreset`:
1. Collect all numbered variants for the name: `verse1`, `verse2`, `verse3`, …
2. Loop-back: `idx = ((num - 1) % count) + 1` — `[prc_verse_4]` with only `verse1/2/3` defined → uses `verse1`
3. If no numbered variants found, try the bare name (e.g. `bridge` without a number)
4. Fall through to `default`

Sections without a number (e.g. `[prc_intro]`) match the bare key `intro`.

### Preset fields

| Field | Type | Description |
|-------|------|-------------|
| `allowed_lightpresets` | list of names | Lighting preset names (bare, without `[lighting (...)]` wrapper). One is picked per section instance, avoiding the preset already running (see "Never re-states a running preset" below). Valid names listed in `LIGHTING_VALID_SET` in `venue_themes.lua`. |
| `allowed_postprocs` | list of `.pp` filenames | Post-process effect filenames. One picked per section instance, same avoidance. Valid set: 30 entries in `POSTPROC_VALID_SET`. Emitted as `[ProFilm_a.pp]` — filename wrapped in brackets. |
| `keyframe_rate` | integer (beats) | `[first]`/`[next]` interval for manual lighting presets. Required if `allowed_lightpresets` includes any manual preset (`verse`, `chorus`, `manual_cool`, `manual_warm`, `dischord`, `stomp`). |
| `lightpreset_blendin` | number (beats) | Blend into this section's lighting instead of cutting to it: re-state the **previously active** lighting preset this many beats before the section start. This section's own event never moves off the section start. Absent/0 = hard cut. See "Blend-in" below. |
| `postproc_blendin` | number (beats) | Same for post-process, with its own independent offset. |
| `camera_pacing` | string | Per-section camera pace override, overrides global `camera_pacing` for that section's duration. Same values as global. |
| `dircut_at_start` | string | Bare directed event name (e.g. `directed_all`). Inserts `[directed_all]` as a forced camera cut at the section start. Does NOT insert a random directed cut for that position — forced only. |
| `bonusfx_at_start` | flag | Inserts `[bonusfx]` at section start (half-beat snapped). |

### Blend-in

`lightpreset_blendin` / `postproc_blendin` do **not** move the section's own
events earlier. RB3 switches preset "when this section begins" either way; the
blendin value says how far ahead of that boundary the **outgoing** preset is
duplicated, giving the game an anchor to interpolate from instead of snapping.

`[lighting (stomp)]` + `[ProFilm_a.pp]` at m3, next section at m10 picking
`[lighting (verse)]` + `[ProFilm_b.pp]` with `lightpreset_blendin 1` and
`postproc_blendin 2`:

```
m3     [lighting (stomp)]  [ProFilm_a.pp]  [first]   <- section 1, untouched
m9 b3  [ProFilm_a.pp]                         <- duplicate, postproc_blendin 2
m9 b4  [lighting (stomp)]                     <- duplicate, lightpreset_blendin 1
m10 b1 [lighting (verse)]  [ProFilm_b.pp]  [first]
```

The blendin values belong to the **incoming** section (the doc's "how many
beats BEFORE *this* section"); the duplicated content is the outgoing preset.
Details, all in `BlendPpq` / `EmitBlendDuplicates` (`venue_lighting.lua`):

- The duplicate is a **bare lighting event** — no `[first]`, no `[next]`. It
  restates a preset that is already running, and only a preset *change* starts
  a keyframe sequence, so section 1's train just carries on through it to the
  boundary. (See "Keyframe placement rule" in `CLAUDE_general.md`; the
  Keyframes tab re-derives the same rule from the track, which is what makes
  regenerating reproduce what was generated.)
- Skipped when the preset isn't changing (lighting and postproc judged
  independently), or when the blend point would land at or before the event it
  copies — a section shorter than the next one's blendin, or a first section
  sitting on the song-start bookend.
- Themes gen carries the outgoing preset forward through its own section walk
  and seeds the first section from the song-start bookend; Section gen only
  ever sees one section, so it reads the outgoing preset off the VENUE track
  via `FindActiveVenuePresetsBefore` (`venue_generator.lua`) and passes it in
  as `GenerateThemedSectionEvents`' `incoming` argument.

#### Reading a blend back off the track

A blendin value exists only inside a theme; the VENUE track keeps no record of
it. What survives is the shape: **two identical adjacent events of one kind
are a blend anchor.** That is the whole rule, and `IsBlendAnchor(a, b)`
(`venue.lua`) is the one place it lives, because four unrelated features have
to agree on it:

| Reader | Uses it to decide |
|---|---|
| `ResolveBlendSource` (Manual gen's **Blend** button) | refuse to add a third copy — the pair already *is* an anchor |
| `ValidateVenueLightingBlends` (Actions ▸ **Validate lighting/blends**) | which preset changes have no anchor before them |
| keyframe restatement test | a duplicate gets no `[first]` — it starts no train |
| `AnnotateVenueBlends` (Venue **Preview**) | which events are preset *state* and which are just anchors to collapse |

It sits in `venue.lua` rather than beside the write side because the standalone
Venue Preview window loads that module and deliberately does not load
`venue_lighting.lua`.

**`AnnotateVenueBlends(events)`** is the Preview's reader. Pure over one kind's
`{msg, t, ppq}` list: it drops every anchor and annotates each survivor with
`blend_out_t`/`blend_out_ppq` (where the anchor for the *next* change sits;
`nil` = hard cut) and `next_t` (when that change lands). The pair bounds the
window in which a fade is actually running, which is what the Preview's
"blending now" line tests against the playhead. With three or more identical
copies `blend_out_t` is the **last** restatement — the pair `IsBlendAnchor`
would match. Camera is never annotated: a camera cut does not fade.

Lighting and post proc are judged independently, exactly as
`EmitBlendDuplicates` decides them. Only **adjacent** events are compared, so
a preset returning after a different one in between is a fresh change needing
its own anchor, not one already covered by its earlier run.

Hand authoring produces the same shape: Manual gen's **Blend** button copies
the currently-running preset to the playhead, which is the identical duplicate
`EmitBlendDuplicates` would have written. Park the playhead a beat or two
before the boundary, click Blend, then add the new preset at the boundary
itself. A change with no anchor is a **hard cut** — legitimate, and what
blendin 0 / absent produces — so the validator lists them as "where a fade
would need an anchor", never as errors.

### Never re-states a running preset

A section that resolved to the preset already playing would write two identical
adjacent events at its boundary — which *is* the anchor shape above, so all four
readers would take it as a deliberate blend. Both generating tabs prevent it, lighting
and post proc judged independently:

1. **Re-roll at pick time.** `ResolveThemeSection` takes the incoming preset state as
   `prev` and picks with `PickRandom(pool, prev_text)` — the same helper the camera
   pools and `GenerateLightingEvents`' `last_pick` use. `GenerateThemedSectionEvents`'
   pass 1 already runs in section order, so each pick sees the one before it (`incoming`
   seeds the first). Section gen's Template mode does the same against
   `FindActiveVenuePresetsBefore`, which is why that lookup runs before its roll.
2. **Skip at emit time.** `EmitThemeSection` drops the event when it still matches —
   a one-entry pool, Section gen's Custom-mode fixed choice, or `PickRandom`'s
   fallback after 10 tries. `GenerateThemedSectionEvents` returns a 4th value,
   `stats = { lt_skipped, pp_skipped }`; `GenerateVenueEvents` reports the totals and
   `GenerateSectionEvent` names the preset it kept.

**Keyframes are emitted either way** — the skip covers only the `lt_events` append. The
previous section's `[next]` train was bounded by *its own* `sec_end_ppq`, so a kept
manual preset with no train of its own here would run through the section with its
lights frozen. `[first]` is withheld by the same test, which is the existing
"only a change starts a train" rule and is what keeps the Keyframes tab's round trip
working (it already treats a duplicate as neither starting nor ending a span, so
removing the duplicate leaves its span continuous).

Manual gen is exempt by design: an author who wants a duplicate there gets one.

### Valid lighting preset names (bare)
`verse`, `chorus`, `manual_cool`, `manual_warm`, `dischord`, `stomp` (manual — require `[first]`/`[next]`)
`loop_cool`, `loop_warm`, `harmony`, `frenzy`, `silhouettes`, `silhouettes_spot`,
`searchlights`, `sweep`, `strobe_slow`, `strobe_fast`, `blackout_slow`, `blackout_fast`,
`flare_slow`, `flare_fast`, `bre` (auto — no keyframes needed)

### Camera pacing table

| pacing  | < 150 BPM | ≥ 150 BPM (×1.5) | @ 120 BPM                     |
|---------|-----------|------------------|-------------------------------|
| crazy   | 4 16ths   | 6 16ths          | ~0.5 s — every beat           |
| fast    | 8 16ths   | 12 16ths         | ~1 s — every 2 beats          |
| medium  | 16 16ths  | 24 16ths         | ~2 s — every bar              |
| slow    | 24 16ths  | 36 16ths         | ~3 s — every 1.5 bars         |
| minimal | 32 16ths  | 48 16ths         | ~4 s — every 2 bars           |

At ≥ 150 BPM all intervals are scaled by ×1.5 (rounded) — `crazy` at 160 BPM fires every ~0.6 s,
`minimal` at 160 BPM fires every ~4.5 s. BPM is read from `r.Master_GetTempo()` at generation time.

---

## Generation pipeline (`GenerateVenueEvents`)

```
1.  Find VENUE track + MIDI item
2.  ResolveSongEndAndAnchor(take, ppq, item_start_sec, item_end_sec) → range_end_sec,
    end_in_range, trailing_slack_sec, final_anchor_ppq (extracted, pure — see below)
      range_end_sec: [end] EVENTS-track marker when one falls inside the item, else the
        item's own length (fallback — flagged in the result panel as used_end_fallback,
        with a "Didn't find [end] event, used MIDI length as end" note)
      final_anchor_ppq: the [music_end] EVENTS-track marker, but only when it is within
        10 measures of [end] (counted via repeated FindNextMeasureStartPpq calls) —
        otherwise nil, meaning "use the literal range end" everywhere below
3.  Detect muted instruments → filter COOP and DIRECTED pools
4.  Build weighted coop opts (CategorizeCoopPool, active_coop_set, keys_failsafe)
5.  ReadInstrumentPlayStates() → per-instrument play/idle timelines (converted to 16ths)
6.  Resolve active theme (S.venue_theme_idx)
7.  If theme: ReadEventSections(range_end_sec) → sections[]
8.  Resolve the music-start anchor (FindMusicStartTime, else measure-3/4-nearest-3s fallback);
    if sections[1] sits at the song's literal start, re-anchor its t_start to this position
9.  Build forced_cuts[] (dircut_at_start per section) and interval_changes[] (camera_pacing overrides)
10. ClearVenueTextEventsInRange (overwrites range)
11. All subsequent inserts go through insert_text, which snaps to the nearest half-beat (ppq/2).
12. Forced song-start trio at tick 0 (unconditional on theme state):
      [coop_all_far], [lighting (intro)], [ProFilm_a.pp]
13. First generated camera cut: weighted pick with play-state awareness at the music-start anchor
14. Camera:
      cam_dir = theme active → {} (no random directed)
              = no theme     → filtered DIRECTED_POOL
      first cut = one camera interval after last bookend (or default start range)
      cam_total_16ths = final anchor's 16ths position if resolved, else the full range
      GenerateCameraEvents(active_coop, cam_dir, cam_total_16ths, ..., forced_cuts, interval_changes, coop_opts)
        → per-tick play-state cursors advance; idle instruments get weight 5; all-idle shifts groups
        → last scripted coop cut lands 8 sixteenths before cam_total_16ths (see venue_camera.lua)
15. Lighting + keyframes:
      theme + sections → GenerateThemedSectionEvents (per-section presets)
      theme, no sections → GenerateLightingEvents with default preset pool
      no theme → GenerateLightingEvents (full random MANUAL+AUTO pool)
16. Bookend outro: [lighting (blackout_spot)] at the final anchor if resolved, else 2 measures
    (32 sixteenths) before the range end
17. Undo block, UpdateArrange
```

### Song end and the final anchor

The VENUE MIDI item's own length is not authoritative for where the song ends — authors
routinely leave trailing slack after the last real event, and that's harmless in-game. The
`[end]` text event on the EVENTS track is the actual song end: nothing is generated at or
after it, regardless of how much longer the item runs.

- **`[end]` present and inside the item** (`end_in_range`): `range_end_sec` is clamped to it.
  If the item runs meaningfully longer than `[end]` (`trailing_slack_sec > 1.0`), the result
  panel adds a non-blocking note suggesting the item be trimmed to `[end]` — purely cosmetic,
  never required.
- **`[end]` missing (or outside the item)**: falls back to the item's own length, exactly as
  before this feature existed, plus a `"Didn't find [end] event, used MIDI length as end."`
  note in the result panel.

The **final anchor** (`final_anchor_ppq` / `final_anchor_16ths` in `venue_generator.lua`)
additionally resolves the `[music_end]` marker when it sits within 10 measures of `[end]`.
`[end]` triggers the game's own forced camera cut, so a scripted cut or the outro lighting
bookend landing right on top of it doubles up as a jump cut — anchoring both to `[music_end]`
instead keeps them clear of it. When `[music_end]` is absent, or more than 10 measures before
`[end]` (e.g. a long instrumental/crowd-noise outro that still wants normal generation for its
whole length), the final anchor is nil and every step below falls back to the literal range end
— identical to pre-`[music_end]` behavior.

### `GenerateCameraEvents` — randomness constants

These are `local` constants at the top of `venue_generator.lua`, marked as
**"Future S-field candidates"**. They currently have no UI controls.

| Constant | Default | Meaning |
|----------|---------|---------|
| `CAM_INTERVAL_16THS` | 24 | Base spacing between coop camera cuts (~1.5 bars in 4/4). Used in no-theme mode only; theme mode uses `GetThemeCameraInterval`. |
| `CAM_JITTER` | 0.35 | ±35% random variation on each camera interval. Applied in both modes. |
| `CAM_DIRECTED_COOLDOWN` | 2.0 | Multiplier: minimum gap after a directed cut = `interval × 2.0`. |
| `CAM_START_MIN_16THS` | 32 | Earliest first camera cut (2 bars). |
| `CAM_START_MAX_16THS` | 48 | Latest first camera cut (3 bars). |
| `DIRECTED_MIN_COUNT` | 1 | Min random directed cuts — only in no-theme mode (theme uses forced_cuts). |
| `DIRECTED_MAX_COUNT` | 4 | Max random directed cuts — only in no-theme mode. |

### No-repeat avoidance (`last_spot`)

`GenerateCameraEvents` tracks a `last_spot` **set** (not a single value) of every event string
placed at the immediately preceding "spot" — a primary coop/directed pick plus its companion
event, if one fired. This set is passed as the `avoid` argument to `PickRandom` /
`WeightedPickCoopEvent` for the next pick, and to `FindCompanion` for that pick's companion, so
neither the primary nor the companion can repeat anything from the previous spot.

`last_spot` is **replaced wholesale** at every spot, never merged across spots — a shot banned
at spot N is fully available again at spot N+2. This applies uniformly to forced directed cuts,
random directed cuts, and coop cuts (directed and coop share the same `last_spot`, matching the
existing structure — pools never overlap between the two categories in practice).

`PickRandom(pool, avoid)` accepts either a single string (legacy scalar equality) or a set
(`{ [text] = true, ... }`, checked via table membership) — `type(avoid) == 'table'` selects
which check runs. `WeightedPickCoopEvent` and `WeightedPickSoloShot` forward `avoid` opaquely,
so they work with either form unchanged.

`GenerateCameraEvents` accepts an optional trailing `initial_avoid_set` parameter so a caller's
own bookend picks (see "Song-start bookends and the music-start anchor" below) can seed the ban
before the regular loop's very first pick — `GenerateVenueEvents` and `GenerateSectionEvent`
both thread their own bookend `last_spot` through to this parameter, so the ban chains
continuously from the forced tick-0 shot through every generated cut in the song, with no seam
at the bookend/regular-loop boundary.

### Weighted coop camera selection

Coop shots are split into three groups based on the instrument code in the event name:

| Group | Rule | Examples |
|-------|------|---------|
| Solo | Single instrument letter (`#code == 1`) | `[coop_g_*]`, `[coop_v_*]`, `[coop_d_*]` |
| Duo | Two instrument letters (`#code == 2`) | `[coop_gv_*]`, `[coop_bg_*]`, `[coop_bk_*]` |
| Venue | `all` or `front` code | `[coop_all_*]`, `[coop_front_*]` |

**Group selection weights** (after filtering to groups that have available shots):

| Group | Weight |
|-------|--------|
| Solo | 60% |
| Duo | 20% |
| Venue | 20% |

**Per-instrument weights** (used for Solo and Duo groups):

| Instrument | Letter | Base weight | Idle weight |
|------------|--------|-------------|-------------|
| Vocals | v | 40% | 5% |
| Drums | d | 15% | 5% |
| Guitar | g | 15% | 5% |
| Bass | b | 15% | 5% |
| Keys | k | 15% | 5% |

For **Solo**: an instrument is picked by weight → random shot from that instrument's sub-pool.

For **Duo**: an instrument is picked by weight from all letters appearing in available duo codes → random shot from all duo events that contain that letter.

For **Venue**: equal probability for each event.

All weights are normalized (redistributed) over the instruments actually present (non-muted). Missing instruments are excluded entirely — their weight is divided proportionally among the remainder.

### Play-state awareness

Each PART track may contain `[play]`, `[mellow]`, `[intense]`, `[idle]`, and `[idle_realtime]`
text events signalling whether the instrument is actively performing or on a break. These are
read once before generation by `ReadInstrumentPlayStates` in `venue_awareness.lua` and stored
as sorted per-instrument timelines.

At each camera cut tick a cursor per instrument advances monotonically through its timeline
(last event before the tick wins; **default = idle** if no event has occurred yet). Idle
instruments receive **weight 5** instead of their base weight. The result is renormalized over
all available instruments — no re-roll needed.

**All-idle group shift:** when every instrument with events in the coop pool is idle at the
current tick, group weights shift to favour venue shots:

| Group | Normal | All-idle |
|-------|--------|----------|
| Solo  | 60%    | 30%      |
| Duo   | 20%    | 10%      |
| Venue | 20%    | 60%      |

**Fallback:** if a PART track is present but has no play/idle events at all, that instrument
is treated as always active. The result output lists which instruments fell back to this mode.

### Keys / guitar / bass swap failsafe

In Rock Band, the keys slot physically replaces a guitar or bass player — you cannot have
guitar + bass + keys all active simultaneously. When **all three** are charted in the
project the generator emits **companion events** at the same tick so the game can pick
whichever two instruments are actually populated in the band setup.

Condition: `keys_failsafe = not muted.k and not muted.g and not muted.b`
(Does **not** activate when only two of the three are present.)

`FindCompanion(event_text, coop_opts, idle_set, singing_set, avoid_set)` (global,
`venue_camera.lua`) always returns **one** companion string or `nil` for a given primary pick —
it does one filtered `WeightedPickCoopEvent` call, never more. It excludes every instrument
letter already present in the primary shot's code from the solo/duo pools before picking, then
weight-picks from whatever remains, passing `avoid_set` through so the companion also can't
repeat the previous spot's event(s) (see "No-repeat avoidance" above). Returns nil if nothing
valid remains (e.g. the primary shot already used every non-excluded instrument, or the
candidate duo doesn't exist in the pool — drum duos resolve naturally to no companion because
`[coop_dk_*]` is not in the pool).

**Companion emitted by source code:**

| Source code | Companion |
|---|---|
| `bg` / `bk` / `gk` (duo between two of bass/guitar/keys) | **1** — the remaining third instrument's solo or duo shot |
| `g` / `b` / `k` (solo) | **1** at random from the remaining valid alternatives |
| `gv` / `bv` / `kv` / `dg` / `bd` (mixed duo) | **1** at random (or none for drum duos) |
| `dv`, `d`, `v`, `all`, `front`, … | **0** (no b/g/k in the code) |

Companion events are flagged `is_companion = true` and counted separately in the result
stats as "Camera (companion)".

**`FindCompanion` must be called at every insertion point that can pick a solo/duo coop
event, not just the main per-tick loop.** It was originally only wired into
`GenerateCameraEvents`'s regular loop (`venue_camera.lua`); the song-start/music-start bookend
picks (`GenerateVenueEvents` in `venue_generator.lua`, and the equivalent bookend block in
`actions_venue_section.lua`'s `GenerateSectionEvent`) call `WeightedPickCoopEvent` directly and
were missing the `FindCompanion` follow-up, so a keys/guitar/bass swap band would silently lose
the alternate shot whenever the bookend picked a `g`/`b`/`k`/duo event. `FindCompanion` had to
be changed from `local` to a global function in `venue_camera.lua` so these other files could
call it (see `CLAUDE.md`'s global-vs-local function rule). Both bookend call sites now check
`coop_opts.keys_failsafe` and call `FindCompanion` the same way the main loop does.

### Camera shot priority (`venue_camera_priority.lua`)

Stacking only works because the game **ranks** the shots it finds on one tick. Source:
`_external_docs/RBN2 Camera And Lights - RBN_C3 Documentation.htm`, sections "Camera Shot
Priority" and "Directed Cuts Priority". The engine evaluates every shot at that tick in a
fixed order and plays the one that most closely matches the members actually on stage. The
documented order runs most generic → most specific, and **more specific wins**.

`CAM_PRIORITY_TIERS` keeps the documentation's own grouping and within-tier order:

| Rank | Tier | Count | Notes |
|---|---|---|---|
| lowest | Generic four camera shots | 3 | `[coop_all_behind/far/near]` |
| ↓ | Three character shots (no drum) | 2 | `[coop_front_behind/near]` |
| ↓ | One character standard shots | 10 | drums and vocals rank below b/g/k — they are always present, so their shots are the more generic ones |
| ↓ | One character closeups | 9 | |
| ↓ | Two character shots | 15 | |
| highest | Directed cuts | 40 | always more specific than any coop shot; 38 pool entries + `[directed_bre]` / `[directed_brej]` |

`CAM_PRIORITY[bare_name]` is the flattened **effective** rank (higher wins). It diverges from
the tier table in exactly one documented place: doc Note 1, "a single keys shot will prioritize
over any combo shot", so `coop_k_behind/near/closeup_hand/closeup_head` are lifted to just
above the two-character tier — still below every directed cut. The note does not settle whether
the closeups count; the module includes them and says so.

`PickPriorityCameraEvent(group, muted)` is the resolver: drop the shots needing an instrument in
`muted`, return the highest-ranked survivor, return `nil` if none survives. `dev/tests/venue_labels.lua`
guards the table (coverage, unique ranks, tier sizes, the two ordering promises) and
`dev/tests/general_algorithms.lua` the resolver.

Two things read it. The **Venue Preview** resolves each PPQ group through it, so a stacked spot
shows the shot the game would play. **Venue > Actions > Validate camera stacks**
(`actions_venue_validate_camera.lua`) replays it once per possible lineup across the whole track
and reports stacks that went wrong — shots that win under no lineup, and lineups left with no
valid camera shot. See "Feature: VENUE validation" in `.claude/CLAUDE_general.md`.

**Two engine fallbacks nothing in this repo performs.** Both are game-side substitutions with
more than one possible outcome, so the generator does not emit them and the Venue Preview does
not draw them — it keeps showing the authored event and explains these in an alert instead:

- **Generic shot fallback.** If no stacked shot can be matched, the game uses one of
  `[coop_all_behind]`, `[coop_all_far]` or `[coop_all_near]` (`CAM_GENERIC_FALLBACK`). A
  three-character `[coop_front_*]` shot may be selected in such cases as well.
- **Duo to single fallback.** If a member is missing when a duo flag is called *and there are no
  other stacked flags*, the duo cut becomes a single cut of the remaining member. This is the
  direct reason companion stacking above is worth doing: without a companion you get the game's
  guess, with one you get the shot you chose. The documentation states this only for normal
  (coop) two-character shots — the directed cuts section makes no equivalent claim for
  `[directed_duo_*]`.

### Song-start bookends and the music-start anchor

Two events are inserted before the regular generation loop, anchored to the absolute start of
the VENUE item regardless of the current time selection. Each is only inserted when its
position falls within the generation range — both full-item and time-selection runs.

| Position | Event |
|---|---|
| Song measure 1 beat 1 (VENUE item start, tick 0) | **Forced, not randomised:** `[coop_all_far]` + `[lighting (intro)]` + `[ProFilm_a.pp]`, fired regardless of theme state |
| Music-start anchor (see below) | `WeightedPickCoopEvent` with play-state awareness at that tick |

**Resolving the music-start anchor.** The literal song start (tick 0) is not the same as
where the music actually begins — songs conventionally have a count-in/silence first.
`GenerateVenueEvents` resolves one anchor position and reuses it in two places:

1. An explicit `[music_start]` text event on the EVENTS track (`FindMusicStartTime` in
   `venue_awareness.lua`), if present — authoritative, no guessing needed.
2. Otherwise, whichever of measure 3 or measure 4 (via `FindNextMeasureStartPpq`) has a
   real project time closer to `item_start_sec + 3.0` — adapts to tempo instead of a fixed
   measure count.

The weighted second bookend fires at this anchor and advances play-state cursors to that exact
position: instruments with `[play]` at or before the anchor get their full base weight;
instruments still idle (or with no events yet) get weight 5. This makes the very first weighted
shot reflect which instruments actually start the song.

**First `[prc_*]` section re-anchoring.** When a theme is active and the earliest detected
section (`sections[1]`, typically `[prc_intro]`) was placed right at the song's literal start
(`t_start` within ~1ms of `item_start_sec`), `GenerateVenueEvents` rewrites `sections[1].t_start`
to the same music-start anchor before building `forced_cuts`/`interval_changes`/`bonusfx_events`
and before calling `GenerateThemedSectionEvents` — so that section's lighting, postproc, forced
directed cut, and bonus FX all land at the real musical start instead of during the count-in.
A section the author already placed later (not at tick 0) is left untouched.

The first regular camera cut from `GenerateCameraEvents` is set to one full camera interval
(with ±jitter, using the same `CAM_INTERVAL_16THS` and `CAM_JITTER` constants as the rest of
the song) after the last inserted bookend — so the music-start anchor shot acts as the
"first cut" and subsequent spacing is uniform throughout.

**No-repeat chaining across the bookend boundary.** Both `venue_generator.lua` and
`actions_venue_section.lua` build their own local `last_spot` set (see "No-repeat avoidance"
above) as they insert each bookend: the forced `[coop_all_far]` seeds it, the anchor/measure-3
pick's `WeightedPickCoopEvent` call is given the current `last_spot` as its avoid set (so it
won't repeat the forced shot), `FindCompanion` is given the pre-update `last_spot` for the same
reason, and the result (primary + companion) replaces `last_spot` for the next step. The final
`last_spot` is passed as `GenerateCameraEvents`'s `initial_avoid_set` argument, so the regular
loop's very first pick also can't repeat whatever the bookends just placed.

### Half-beat snapping

All text events (camera, lighting, keyframes, post-process) are snapped to the nearest
half-beat (`ppq / 2` ticks) in absolute project PPQ space. Snapping happens in the
`insert_text` closure in `GenerateVenueEvents` and applies to every event type uniformly.

### `GenerateLightingEvents` — randomness constants (no-theme mode)

| Constant | Default | Meaning |
|----------|---------|---------|
| `LIGHTING_INTERVAL_16THS` | 128 | Base spacing between lighting changes (~8 bars). |
| `LIGHTING_JITTER` | 0.25 | ±25% random variation on each lighting interval. |
| `LIGHTING_OFFSET_16THS` | 32 | Lighting changes start 2 bars into the range (gives camera a head start). |
| `KEYFRAME_MIN_BEATS` | 1 | Min `[first]`/`[next]` interval when theme has no `keyframe_rate`. |
| `KEYFRAME_MAX_BEATS` | 4 | Max `[first]`/`[next]` interval when theme has no `keyframe_rate`. |

---

## Keyframe alignment (`S.venue_keyframe_align`)

Controls where `[first]` and `[next]` events land relative to the section start.
Saved to project state as `vkfa` (integer 0–7).

This same setting (and `S.venue_kf_inst_subdiv`) is shared by every keyframe generator in the
codebase: `ProcessThemeSection` (this file's themed pipeline), `GenerateManualKeyframes`
(Manual gen sub-tab, one span from the playhead), and `GenerateKeyframesForSpan` (extracted in
`venue_lighting.lua`, used by the Keyframes sub-tab's `RegenerateVenueKeyframes` to bulk-refresh
every manual lighting event already on the VENUE track — see `CLAUDE_general.md`'s Venue tab
description). All three implement the same modes 0-7 algorithm independently rather than
sharing one function, to avoid touching already-working generation paths.

### Modes 0–2 (standard)

| Mode | Value | `[first]` position | `[next]` sequence starts from |
|------|-------|--------------------|-------------------------------|
| Section start | 0 | Section start | Section start + `kf_ticks` |
| Closest beat  | 1 | Nearest beat to section start | `[first]` + `kf_ticks` |
| Downbeat      | 2 | Section start | First measure boundary AFTER section start, then at `kf_ticks` intervals |

**Downbeat implementation** (`FindNextMeasureStartPpq` in `venue_lighting.lua`):
- Estimates the measure index from `TimeMap_timeToQN` ÷ 4
- Scans forward measure-by-measure using `TimeMap_GetMeasureInfo`
- Returns the `t_e` (end) of the measure containing the section start = start of the next measure
- Fallback if API fails: advance by 4 beats (`ppq_pos + 4 * ppq`)

Note: "Downbeat" with `keyframe_rate=4` in 4/4 lands every `[next]` on a bar downbeat.
With `keyframe_rate=2` they land on beats 1 and 3 (on-beat but not always bar-downbeats).

### Modes 3–7 (instrument-aware)

These modes **ignore** the theme's `keyframe_rate`. Instead, the generator scans the named
instrument's Expert MIDI track and emits `[next]` only at beat or half-beat grid positions
that have at least one qualifying note.

| Mode | Value | Track | Pitches |
|------|-------|-------|---------|
| Guitar notes | 3 | PART GUITAR | 96–100 |
| Bass notes   | 4 | PART BASS   | 96–100 |
| Keys notes   | 5 | PART KEYS   | 96–100 |
| Drum kicks   | 6 | PART DRUMS  | 96 only |
| Drum snare   | 7 | PART DRUMS  | 97 only |

`[first]` is placed at the section start (no beat-snapping).  
`[next]` events are placed at each beat/half-beat grid position within the section where at
least one qualifying note starts. Grid positions with no notes are silently skipped.

**Subdivision** (`S.venue_kf_inst_subdiv`, persisted as `vkfis`):

| Setting | Value | Grid interval | Max `[next]` per measure (4/4) |
|---------|-------|---------------|-------------------------------|
| Every beat      | 0 | `ppq` (quarter note) | 4 |
| Every half beat | 1 | `ppq / 2` (8th note) | 8 |

**Implementation** (`CollectInstNotePositions` in `venue_lighting.lua`):
- Finds the instrument track by name via `FindTrackByName`
- Reads the first MIDI item on that track
- Converts the section range from VENUE PPQ → project time → instrument PPQ
- Collects all non-muted notes in pitch range, converts positions back to VENUE PPQ
- Returns a sorted array; used as the note lookup for all sections in `GenerateThemedSectionEvents`
- Note positions are pre-computed once per generation (not once per section)

---

## State fields added to `S`

| Field | Default | Persisted | Description |
|-------|---------|-----------|-------------|
| `venue_theme_idx` | 0 | No | Index into `S.venue_themes`; 0 = no theme |
| `venue_theme_name` | `''` | Yes (`vthn`) | Stem filename of selected theme; used to restore `idx` on load |
| `venue_themes` | `nil` | No | Array of parsed theme tables; lazy-loaded on first Venue tab render |
| `venue_keyframe_align` | 0 | Yes (`vkfa`) | 0–7 — keyframe alignment mode (0/1/2 = standard; 3–7 = instrument-aware) |
| `venue_kf_inst_subdiv` | 0 | Yes (`vkfis`) | 0 = every beat, 1 = every half beat — subdivision for instrument-aware modes |
| `venue_cam_pacing` | 0 | Yes (`vcpac`) | 0–6 — camera cut pacing override (0 = theme default; 1–5 = minimal→crazy; 6 = custom) |
| `venue_cam_pacing_custom` | 16 | Yes (`vcpacc`) | Custom camera interval in 16ths; only used when `venue_cam_pacing == 6` |

`S.venue_themes` is `nil` until the Venue tab is first rendered. The UI lazy-loads via
`LoadVenueThemes(_mdir .. 'themes/')` and re-resolves `venue_theme_name → venue_theme_idx`.

---

## Solo shot-type weighting

When the Solo group is selected, the shot is not picked from the instrument's sub-pool with
equal probability. A **weighted secondary roll** favours closer angles, applied after the
instrument is chosen by `WeightedPickInstrument`:

**Vocals** (3 variants):

| Shot suffix | Weight |
|------------|--------|
| `_near` | 50% |
| `_closeup` | 30% |
| `_behind` | 20% |

**All other instruments** (4 variants):

| Shot suffix | Weight |
|------------|--------|
| `_near` | 45% |
| `_closeup_head` | 20% |
| `_closeup_hand` | 20% |
| `_behind` | 15% |

The weight tables live in `venue_camera.lua` as `SOLO_SUFFIX_WEIGHTS` (per instrument) and
`SOLO_SUFFIX_WEIGHTS_DEFAULT`. The mechanism is two functions:

- **`BuildSuffixPools(solo_pools)`** splits each instrument's sub-pool by view suffix
  **once per generation**, not per tick, returning `suffix_pools[letter][view] = {shots}`.
  Callers pass the result as `coop_opts.suffix_pools`.
- **`WeightedPickSoloShot(letter, suffix_by_view, avoid, singing_set)`** rolls against the
  weight table, then picks a random event from that suffix's candidates — there may be
  several `_near` variants, for example.

Shots whose event name carries no recognised suffix go into an `'__other'` pool and are
picked with equal probability, which is also the fallback when no weighted view has any
candidates. The instrument codes like `_all` / `_front` belong to the venue group rather
than solo, so they never collide with a view suffix.

When **sing notes** (see below) are active for an instrument, `SOLO_SUFFIX_WEIGHTS_SING`
replaces the normal table — see effect 2 for the values. Vocals (`'v'`) is excluded by an
explicit `letter ~= 'v'` guard: its weights are never shifted.

## VENUE MIDI sing notes

The VENUE track carries MIDI notes that signal which instrument players are singing:

| Pitch | Meaning |
|-------|---------|
| 85 | Bassist sing |
| 86 | Drummer sing |
| 87 | Guitarist sing |

Keys has no dedicated sing note — the keys/guitar/bass failsafe already handles which slot
is populated, so a guitarist-sing note on a keys song would carry over via that mechanism.

Sing notes drive two effects:

**1. Instrument weight redistribution**
When some (not all) of {b,d,g} have active sing notes, non-singing {b,d,g} and keys drop
to idle weight (5). Their "missing" weight (base−5 each, across available instruments)
redistributes equally to the active singers. When all three sing or none sing, base weights
apply unchanged. Vocals ('v') is always unchanged (no sing pitch exists for vocalists).

| Scenario | v | g (sings) | b | d | k |
|----------|---|-----------|---|---|---|
| only g sings | 40 | 45 | 5 | 5 | 5 |
| g + b sing | 40 | 25 | 25 | 5 | 5 |
| all 3 sing | 40 | 15 | 15 | 15 | 15 (no change) |

Redistribution applies only in `WeightedPickInstrument` for the **solo** group pick.
The duo group pick is unaffected.

**2. Shot-type suffix boost**
When the chosen solo instrument has an active sing note, `_closeup_head` is favoured at
the expense of `_closeup_hand` and `_behind`. Vocals ('v') weights are never shifted.

| Suffix | Normal | Singing |
|--------|--------|---------|
| `_near` | 45% | 45% |
| `_closeup_head` | 20% | 35% |
| `_closeup_hand` | 20% | 10% |
| `_behind` | 15% | 10% |

**Implementation:**
- `ReadSingNoteTimelines(take)` in `venue_awareness.lua` reads pitches 85/86/87 from the
  VENUE take as MIDI notes (they survive `ClearVenueTextEventsInRange`).
- `GenerateVenueEvents` converts to range-relative 16ths timeline and stores in `coop_opts.sing_states`.
- `ComputeSingState(coop_opts, sing_cursors, pos_16ths)` in `venue_camera.lua` advances
  cursors and returns `singing_set[letter]=true` — same monotonic cursor pattern as
  `ComputeIdleState`.
- `singing_set` is passed to `WeightedPickCoopEvent` (8th param) → solo branch only.
  `WeightedPickInstrument` applies the redistribution; `WeightedPickSoloShot` picks the
  suffix weight table based on whether the chosen letter is in `singing_set`.

---

## Known limitations

| Area | Limitation |
|------|------------|
| `extra_sections` | The official spec's wildcard/pattern-based section matching is not parsed. |
| Non-4/4 time signatures | `FindNextMeasureStartPpq` works for any time signature via `TimeMap_GetMeasureInfo`, but "Downbeat" alignment with a `keyframe_rate` that is not the measure length won't land on every downbeat outside 4/4. |
| `keyframe_rate` resolution | Expressed in beats × PPQ, so it cannot express a 16th-note rate. |

## Exposing a generator constant as an `S` field

Several constants in `venue_generator.lua` are marked "Future S-field candidates" —
`CAM_INTERVAL_16THS`, `CAM_JITTER`, `DIRECTED_MIN_COUNT` / `DIRECTED_MAX_COUNT`,
`LIGHTING_INTERVAL_16THS`, `LIGHTING_JITTER`, and `KEYFRAME_MIN_BEATS` /
`KEYFRAME_MAX_BEATS`. Promoting one to a user control is a four-step change:
1. Add to `S` in `defaults.lua` with the same default value
2. Add serialize/deserialize in `settings.lua`
3. Replace the local constant reference in `venue_generator.lua` with `S.field`
4. Add a slider in the Venue tab in `ui.lua` with a `SliderTooltip(TIPS.field)`

---

## Bundled themes

10 `.rbtheme` files in `rock_band_general_helper_vkr/themes/`:
`AggressiveMetal`, `ArenaRock`, `DarkHeavyRock`, `DustyVintage`, `EdgyProgRock`,
`FeelGoodPopRock`, `GaragePunkRock`, `PsychJamRock`, `SlowJam`, `SynthPop`

Users can add custom themes by dropping additional `.rbtheme` files into the `themes/` folder.
The theme list is re-scanned each time the Venue tab is first rendered in a session.
