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
| `allowed_lightpresets` | list of names | Lighting preset names (bare, without `[lighting (...)]` wrapper). One is picked at random per section instance. Valid names listed in `LIGHTING_VALID_SET` in `venue_themes.lua`. |
| `allowed_postprocs` | list of `.pp` filenames | Post-process effect filenames. One picked at random. Valid set: 30 entries in `POSTPROC_VALID_SET`. Emitted as `[ProFilm_a.pp]` — filename wrapped in brackets. |
| `keyframe_rate` | integer (beats) | `[first]`/`[next]` interval for manual lighting presets. Required if `allowed_lightpresets` includes any manual preset (`verse`, `chorus`, `manual_cool`, `manual_warm`, `dischord`, `stomp`). |
| `lightpreset_blendin` | number (beats) | Place the lighting event this many beats BEFORE the section start. If clamped before range start, falls back to range start. |
| `postproc_blendin` | number (beats) | Place the postproc event this many beats BEFORE the section start. Same clamping as `lightpreset_blendin`. When absent, postproc lands at section start. |
| `camera_pacing` | string | Per-section camera pace override, overrides global `camera_pacing` for that section's duration. Same values as global. |
| `dircut_at_start` | string | Bare directed event name (e.g. `directed_all`). Inserts `[directed_all]` as a forced camera cut at the section start. Does NOT insert a random directed cut for that position — forced only. |
| `bonusfx_at_start` | flag | Inserts `[bonusfx]` at section start (half-beat snapped). |

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
2.  Resolve time range (time selection → use_full_item flag)
3.  Detect muted instruments → filter COOP and DIRECTED pools
4.  Build weighted coop opts (CategorizeCoopPool, active_coop_set, keys_failsafe)
5.  ReadInstrumentPlayStates() → per-instrument play/idle timelines (converted to 16ths)
6.  Resolve active theme (S.venue_theme_idx)
7.  If theme: ReadEventSections() → sections[]
8.  Build forced_cuts[] (dircut_at_start per section) and interval_changes[] (camera_pacing overrides)
9.  ClearVenueTextEventsInRange (overwrites range)
10. All subsequent inserts go through insert_text, which snaps to the nearest half-beat (ppq/2).
11. Bookend intro: [lighting (intro)] at tick 0 — only for full-item AND no theme sections
12. Song-start camera bookends (when their absolute positions fall in range):
      Measure 1: forced venue shot ([coop_all_*] / [coop_front_*])
      Measure 3: weighted pick with play-state awareness at that tick
13. Camera:
      cam_dir = theme active → {} (no random directed)
              = no theme     → filtered DIRECTED_POOL
      first cut = one camera interval after last bookend (or default start range)
      GenerateCameraEvents(active_coop, cam_dir, ..., forced_cuts, interval_changes, coop_opts)
        → per-tick play-state cursors advance; idle instruments get weight 5; all-idle shifts groups
14. Lighting + keyframes:
      theme + sections → GenerateThemedSectionEvents (per-section presets)
      theme, no sections → GenerateLightingEvents with default preset pool
      no theme → GenerateLightingEvents (full random MANUAL+AUTO pool)
15. Bookend outro: [lighting (blackout_spot)] 2 measures before end — full-item only
16. Undo block, UpdateArrange
```

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

`FindKeySwapCompanions` in `venue_generator.lua` returns a **list** of 0, 1, or 2 companion
strings. The inner `try_swap` helper substitutes one letter for another, sorts the result
alphabetically (the pool always uses alphabetical order, e.g. `bg` not `gb`), and checks
`active_coop_set`. Returns nil if the candidate doesn't exist in the pool — drum duos
resolve naturally to only one valid companion because `[coop_dk_*]` is not in the pool.

**Companion count by source code:**

| Source code | Companions emitted |
|---|---|
| `bg` / `bk` / `gk` (pure trio duo) | **2** — both missing variants, all three at the same tick |
| `g` / `b` / `k` (solo) | **1** at random from the two valid alternatives |
| `gv` / `bv` / `kv` / `dg` / `bd` (mixed duo) | **1** at random (or the only valid one for drum duos) |
| `dv`, `d`, `v`, `all`, `front`, … | **0** |

Companion events are flagged `is_companion = true` and counted separately in the result
stats as "Camera (companion)".

### Song-start camera bookends

Two camera events are inserted before the regular generation loop, anchored to the absolute
start of the VENUE item regardless of the current time selection. Each is only inserted
when its position falls within the generation range — both full-item and time-selection runs.

| Position | Event |
|---|---|
| Song measure 1 beat 1 (VENUE item start) | Forced random pick from venue pool (`[coop_all_*]` / `[coop_front_*]`) |
| Song measure 3 beat 1 | `WeightedPickCoopEvent` with play-state awareness at that tick |

The measure 3 shot advances play-state cursors to that exact position: instruments with
`[play]` at or before measure 3 get their full base weight; instruments still idle (or with
no events yet) get weight 5. This makes the very first weighted shot reflect which instruments
actually start the song.

The first regular camera cut from `GenerateCameraEvents` is set to one full camera interval
(with ±jitter, using the same `CAM_INTERVAL_16THS` and `CAM_JITTER` constants as the rest of
the song) after the last inserted bookend — so the measure 3 shot acts as the "first cut"
and subsequent spacing is uniform throughout.

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

## Deferred / not yet implemented

| Feature | Notes |
|---------|-------|
| `extra_sections` | Wildcard/pattern-based section matching from official spec. Not parsed. |
| Per-section directed pools | Themes can't currently restrict which directed cuts fire for a given section. |
| Keyframe rate in 16ths (not beats) | `keyframe_rate` is currently in beats × PPQ. Some themes may benefit from 16th-note resolution. |
| Other time signatures | `FindNextMeasureStartPpq` works for any time sig via `TimeMap_GetMeasureInfo`, but "Downbeat" with `keyframe_rate` not equal to the measure length won't land on all downbeats in non-4/4. |

### Solo shot-type weighting

Currently when the Solo group is selected, any shot from the chosen instrument's sub-pool is
picked with equal probability. The intent is to replace the equal pick with a **weighted
secondary roll** that favours closer angles:

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

These weights apply after the instrument is selected by `WeightedPickInstrument`. The pool is
split by view suffix, one is picked by weight, and then a random event from that suffix's
candidates is picked (there may be multiple `_near` variants, for example).

When **sing notes** (see below) are active for an instrument, the weights for `_near` and
`_closeup_head` (or `_closeup` for vocals) are boosted at the expense of `_behind` and
`_closeup_hand`. The exact boost values are TBD.

**Implementation sketch:**
- Split each instrument's sub-pool by view suffix once per generation (not per tick) into a
  `suffix_pools[letter][suffix]` table.
- Replace the current `PickRandom(sub_pool)` call with a weighted suffix pick, then
  `PickRandom(suffix_pools[letter][suffix])`.
- Pass an optional `sing_boost` flag to apply the boosted weights when a sing note is active.
- Instruments or shots with no `_suffix` in their event name fall through to equal probability
  (the instrument codes like `_all` / `_front` are in the venue group, not solo, so no
  conflict there).

### VENUE MIDI sing notes

The VENUE track carries MIDI notes that signal which instrument players are singing:

| Pitch | Meaning |
|-------|---------|
| 85 | Bassist sing |
| 86 | Drummer sing |
| 87 | Guitarist sing |

Keys has no dedicated sing note — the keys/guitar/bass failsafe already handles which slot
is populated, so a guitarist-sing note on a keys song would carry over via that mechanism.

Sing notes drive two implemented effects and one deferred:

**1. Instrument weight redistribution** (implemented)
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
The duo group pick is unaffected (see effect 2 below).

**2. Duo likelihood boost** (not yet implemented)
Active sing note → increase the probability of duo events pairing that instrument with
the vocalist (e.g. `gv`, `bv`, `dv`). Keys falls back to the failsafe companions (`kv`).

**3. Shot-type suffix boost** (implemented)
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

## Future fine-tuning controls (randomness UI)

The following constants in `venue_generator.lua` are marked "Future S-field candidates"
and are good candidates for UI sliders in the Venue tab:

- **Camera interval** (`CAM_INTERVAL_16THS`): slider 4–64 16ths. Used in no-theme mode.
- **Camera jitter** (`CAM_JITTER`): slider 0–0.5 (0 = perfectly even, 0.5 = very loose).
- **Directed cut count** (`DIRECTED_MIN_COUNT` / `DIRECTED_MAX_COUNT`): two sliders or one range, no-theme mode only.
- **Lighting interval** (`LIGHTING_INTERVAL_16THS`): slider 32–256. No-theme mode.
- **Lighting jitter** (`LIGHTING_JITTER`): slider 0–0.5.
- **Keyframe rate range** (`KEYFRAME_MIN_BEATS` / `KEYFRAME_MAX_BEATS`): used when theme has no `keyframe_rate`. Could be a single slider (fixed rate) or two (range).

Pattern for exposing a constant as `S` field:
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
