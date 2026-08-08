# Rock Band Music Theory Helper — Script Documentation

Entry point: `rock_band_music_theory_helper_vkr.lua`
Module folder: `rock_band_music_theory_helper_vkr/`

---

## Module table

| File | Role |
|---|---|
| `defaults.lua` | Global data tables: `DRUM_NOTATION`, `DRUM_PATTERNS`, `GUITAR_CHORDS`, `GUITAR_CHORD_TYPES`, `GUITAR_LANE_TERMS`. Also defines the minimal `S` and `TIPS` globals required by shared conventions. |
| `audio_preview.lua` | Playback plumbing shared by every tab: `StopCurrentPreview`, `PlayPreviewPath`, `PlaySynthChord`. Globals, because the tabs live in different files — see "Audio playback" below. |
| `ui_piano.lua` | `DrawPianoTab` — the interactive grand staff, readout and keyboard diagram. Geometry and drawing only; the theory is in `lib/reaper_music_notation.lua`. |
| `ui.lua` | `Loop` function, tab bar, Drums and Guitar render functions. Calls `r.defer(Loop)` to start the script. |
| `lib/reaper_guitar_theory.lua` (shared, not in this module folder) | Pure fret-shape classification: `GuitarParseFretInput`, `GuitarClassifyChordType`, `GuitarSuggestRBMapping`, `GuitarAnalyzeShape`, `GuitarAnalyzeShapeAllTunings`. No `r`/`ctx`/`S` dependency — see "Adding a new instrument tab" below for when logic like this belongs in `lib/` instead of the module folder. |
| `lib/reaper_music_notation.lua` (shared) | Pure staff-notation model: the diatonic step, `NOTATION_CLEFS`, `KEY_SIGNATURES`, `NotationStepToPitch`, `NotationNoteName`, `NotationKeySigSlots`, `PianoKeyLayout`. No `r`/`ctx`/`S` — see "Piano tab" below. |
| `lib/reaper_karplus_strong.lua` (shared) | Pure Karplus-Strong string synthesis and its tone presets: `KarplusStrongVoice`, `SynthesizeChordSamples`, `SYNTH_TONES`, `SynthToneOpts`, `SynthTonesInFamily`. No `r`/`ctx`/`S`, no `io` even — see "Audio playback" below. |
| `lib/reaper_wav_writer.lua` (shared) | Pure, generic mono 16-bit WAV writer: `WriteMonoWAV16`. Takes any float sample buffer — not specific to Karplus-Strong or to guitar. |

Load order in entry point:
```
lib/reaper_imgui_helpers.lua   (SectionHeader, Tooltip, Btn, LabelColWidth)
lib/reaper_guitar_theory.lua   (pure guitar shape/chord classification)
lib/reaper_music_notation.lua  (pure staff notation model)
lib/reaper_karplus_strong.lua  (pure plucked-string synthesis)
lib/reaper_wav_writer.lua      (pure WAV file writer)
rock_band_music_theory_helper_vkr/defaults.lua
rock_band_music_theory_helper_vkr/audio_preview.lua
rock_band_music_theory_helper_vkr/ui_piano.lua
rock_band_music_theory_helper_vkr/ui.lua
```

`defaults.lua` reads `KEY_SIG_NATURAL_IDX` at load time to seed
`S.piano_key_sig_idx`, so `lib/reaper_music_notation.lua` must come before it.
`ui.lua` goes last because it ends with `r.defer(Loop)`.

No `settings.lua`, `helpers.lua`, or `actions.lua` — this is a read-only reference tool.

### Other tools: link target only (deliberate asymmetry)

This script appears as a button in the **General > Other tools** sub-tab of both
the general and vocal helpers (`SCRIPT_LINK_GROUPS` in
`lib/reaper_script_links.lua`), but it offers **no reverse link back** — its tab
bar has only Drums, Guitar and Piano, so there is no General tab to host that
sub-tab.
Adding one means introducing a General tab here first; that is the open TODO,
recorded per `CLAUDE.md` → "UI consistency across scripts". The same asymmetry
applies to `rock_band_preview_vkr.lua` and `rock_band_pitch_tuner_vkr.lua`,
which have no tab bar at all by design.

If a General tab is ever added here, wiring the sub-tab up is three lines:
`lib/reaper_script_links.lua` in the entry point's pre-check + `dofile` lists,
and a `BeginTabItem(ctx, 'Other tools')` → `DrawGeneralLinksTab()` block. The
registry needs no change — `FilterScriptLinkGroups` already hides whichever
script is running.

---

## Content data convention

All reference content lives as Lua tables in `defaults.lua`, not inline in `ui.lua`. This keeps rendering logic generic (loop over table, render rows) and makes content edits cheap — no need to touch layout code.

Each instrument section gets its own named table(s). Current tables:

| Table | Description |
|---|---|
| `DRUM_NOTATION` | Rows: `img_idx` (0-based column in `drum.png`), `name`, `rb_pro`, `notes`, plus the optional layout/playback fields `col_w`, `gap_after`, `audio_file` — see the table's own header comment in `defaults.lua` |
| `DRUM_PATTERNS` | Rows: `name`, `desc` |
| `GUITAR_CHORDS` | Rows: `shape`, `type`, `name`, `sound`, `rb_mapping`. `shape` is standard low-to-high fret notation (`x 3 2 0 1 0` is C major), the same form `_ParseFretPositions` reads — see the table's own header comment in `defaults.lua` for which rows were regenerated rather than copied from `_external_docs/GUITAR_THEORY.md`, and why that doc's fret numbers must not be trusted |
| `GUITAR_CHORD_TYPES` | Rows: `name`, `description` — drives the Chord Type Explorer selector; every `GUITAR_CHORDS.type` value appears here exactly once and vice versa |
| `GUITAR_LANE_TERMS` | Rows: `width`, `combos` — RB lane-combo letter names (GR/RY/... ) per spread width |

The Piano tab is the exception to this convention, and deliberately so: its
content is not a lookup table but a *model* (clefs, key signatures, the
diatonic step), so it lives in `lib/reaper_music_notation.lua` where it can be
unit-tested. `defaults.lua` holds only that tab's `S` fields and `TIPS`.

Two planned Drums sections have no table yet — `RB_LANE_COLORS` (RB lane colour
per drum piece) and `PRO_VS_4LANE`. Earlier revisions of this file listed both
as "currently empty" tables in `defaults.lua`; they were never actually
created. See [`_future_ideas/music_theory_drum_colors.md`](../_future_ideas/music_theory_drum_colors.md)
and [`_future_ideas/music_theory_pro_vs_4lane.md`](../_future_ideas/music_theory_pro_vs_4lane.md),
which make the same stale claim.

---

## Adding a new instrument tab

1. Add content tables to `defaults.lua` following the existing naming pattern (e.g., `GUITAR_CHORDS`, `GUITAR_LANE_TERMS`).
2. Add a `local function DrawGuitarTab()` in `ui.lua` that loops over those tables.
3. Add a `BeginTabItem('Guitar')` block inside the `BeginTabBar` in `Loop`, calling `DrawGuitarTab()`.

No other files need changing — **unless** the tab needs reusable classification
logic rather than plain lookup data (Drums is pure lookup; Guitar's shape
search needed real computation: fret parsing, interval math, chord-template
matching; Piano needed a whole notation model). That kind of logic belongs in
its own `lib/` file (see `lib/reaper_guitar_theory.lua`,
`lib/reaper_music_notation.lua`), not the module folder — it keeps the
function pure (no `r`/`ctx`/`S`), testable standalone, and reusable by other
scripts later (the Guitar tab's classifier is intentionally reusable by
`rock_band_general_helper_vkr`'s Guitar-tab converters in a future task).

**And unless the tab is big enough to want its own file.** Piano got
`ui_piano.lua` rather than a fourth render function in `ui.lua`: the tab was
self-contained and `ui.lua` was already around 430 lines, in the "consider
whether a new feature fits elsewhere" band of the size guidelines in the root
`CLAUDE.md`. If a tab moves out like this, anything in `ui.lua` it needs has
to stop being a file-local — that is why `audio_preview.lua` exists.

**Reference-table data is tested, not trusted.** `dev/tests/run_guitar_theory.lua`
loads this folder's `defaults.lua` and round-trips **every** `GUITAR_CHORDS` row
through the live classifier — each shape must parse, classify as its own `type`,
and have an `rb_mapping` matching `GuitarSuggestRBMapping`; `GUITAR_CHORDS.type`
and `GUITAR_CHORD_TYPES` must correspond exactly in both directions. Two rows
deliberately diverge on `type` (the bare fifth, and the slash chord) and carry a
documented exemption in `dev/tests/guitar_theory.lua`, itself guarded against
going stale. Add a chord row and it is checked automatically — no test edit
needed. Hand-authored teaching data has no other safety net, so if you add a new
lookup table of this kind, give it the same treatment.

---

## Audio playback (implemented)

Two independent playback mechanisms, one per instrument tab.

### Drums: recorded samples (SWS `CF_CreatePreview`)

Implemented via the SWS extension's `CF_CreatePreview` API. No VSTi or plugin required beyond SWS.

### How it works

`PlayDrumWAV(img_idx_or_row)` in `ui.lua` — global, called when the user hovers+clicks a row in the drum notation table. Stops any current preview, then starts a new one for the sample file corresponding to that row.

`PlayAudioFile(filename)` — local helper. Creates a `CF_CreatePreview` handle and starts it:
```lua
local src    = r.PCM_Source_CreateFromFile(path)
local handle = r.CF_CreatePreview(src)
r.CF_Preview_SetValue(handle, 'B_LOOP', 0)
r.CF_Preview_Play(handle)
S.preview_src = handle
S.preview_pcm = src
```

`StopCurrentPreview()` — local helper. Stops and frees the handle before starting a new one.

**Burst playback** (`S.burst_files`, `S.burst_idx`, `S.burst_next_t`) — for multi-sample patterns (e.g. a drum roll), `PlayDrumWAV` fills `burst_files` with a list of sample filenames and sets a timer. `Loop` fires successive samples by checking `r.time_precise()` against `burst_next_t`.

### State fields (Drums)

| Field | Type | What it holds |
|---|---|---|
| `S.hovered_drum_idx` | int or nil | 0-based image column index; set each frame by hover detection |
| `S.preview_src` | handle | Active `CF_Preview` handle; nil when idle |
| `S.preview_pcm` | handle | Backing `PCM_Source*` for the current preview |
| `S.burst_files` | table or nil | `{filename, …}` array for multi-sample burst playback |
| `S.burst_idx` | int | Next index into `burst_files` (1-based) |
| `S.burst_next_t` | float | `r.time_precise()` timestamp for the next burst hit |

### Audio pack location

Sample files are expected in the `audio/` subfolder next to the entry point. The script checks at startup whether `audio/` exists and gracefully disables playback if it does not (no error, just no audio feedback). This keeps the base install usable without the optional audio pack.

### Guitar: synthesized preview tone (Karplus-Strong, shared `CF_CreatePreview` path)

Real recorded samples aren't practical for the Guitar tab: Shape Search takes arbitrary user-typed shapes (any root, any tuning), which a fixed sample library can never cover, and CC0 clips at these exact voicings would be hard to source pre-made anyway. A MIDI-synth route (`reaper.StuffMIDIMessage`) was tried first and doesn't work: its Lua-reachable modes have no path to a software synth without a **track** in the current project (armed, MIDI-input-monitoring enabled, with a synth loaded) — building that at runtime would mutate the user's actual project (undo entries, a track saved into their `.rpp`), which conflicts with this tool's read-only design.

Instead: synthesize the chord as a short WAV waveform ourselves, and preview it through the *same* `CF_CreatePreview` mechanism Drums already uses — zero project mutation, same SWS dependency Drums already has (not a new one), and full control over the tone instead of depending on whatever MIDI synth may or may not be configured on a given machine. Trade-off: it's a synthesized pluck, not a realistic guitar recording.

**Synthesis** — `lib/reaper_karplus_strong.lua`, pure Lua, no `reaper.*`:
- `KarplusStrongVoice(freq, n_samples, opts)` — one plucked string. Physical modeling: a short delay line (`round(sample_rate / freq)` samples) seeded with noise (the "pluck"), then each output sample is emitted and the delay line is fed back `damping * 0.5 * (current + next)` (a one-zero lowpass in the loop) — this alone produces a decaying, harmonically rich tone with no hand-shaped envelope needed. `opts.damping` is the brightness/energy-loss knob (future tone presets would tune this — see [`_future_ideas/music_theory_karplus_strong_extensions.md`](_future_ideas/music_theory_karplus_strong_extensions.md) for guitar tone variants and other-instrument reuse, not yet implemented); `opts.seed`, if given, seeds the RNG right before that voice's noise burst for reproducible output (tests, and the hook a future "user-controlled variation" feature would use) — if omitted, relies on the ambient RNG state (seeded once with `math.randomseed(os.time())` at entry-point startup) so repeated plays of the same chord sound slightly different, like a real strum.
- `SynthesizeChordSamples(pitches, sample_rate, duration_s, opts)` — one voice per pitch, each staggered `opts.stagger_s` (default ~13ms) after the previous (sorted ascending) so a chord sounds strummed rather than a synchronized block hit. Mixes all voices into one flat float buffer.

**Writing** — `lib/reaper_wav_writer.lua`, pure Lua, `io`/`string` only, generic to any float buffer (not Karplus-Strong-specific): `WriteMonoWAV16(samples, sample_rate, path)` peak-normalizes (loudest sample at ~90% of full scale, so multi-note chords never clip) and writes a mono 16-bit RIFF/WAVE/fmt/data file, byte-packed manually via `string.char` (not `string.pack`, to avoid any assumption about the Lua version REAPER embeds on a given machine).

**Playback** — `PlaySynthChord(pitches, opts)` in `audio_preview.lua`, global: gated on `AUDIO_CF_AVAILABLE` (same SWS check Drums uses). Stops any current preview *before* writing (releases any hold on the scratch path so the overwrite can't race REAPER's own file handle), synthesizes via the two functions above, writes to `SYNTH_PREVIEW_WAV_PATH` (`resources/audio/synth_preview_scratch.wav`, a single fixed name overwritten every play), then calls `PlayPreviewPath` — the same helper `PlayAudioFile` (drums) delegates to. No manual note-off scheduling needed: `CF_Preview` plays the generated WAV to completion on its own, and all previews share `S.preview_src`/`S.preview_pcm`, so `StopCurrentPreview()` already covers every tab (clicking a chord mid-drum-sample interrupts it, same as clicking two drum rows in a row already does).

### Tone presets

`opts.tone` names a row in `SYNTH_TONES` (`lib/reaper_karplus_strong.lua`), which carries every synthesis knob for one instrument voice — `damping`, `hammer`, `strings`, `detune_cents`, `stagger_s`, `duration_s`, `release_s` — plus `label`/`family` for the UI. `SynthToneOpts(name, overrides)` resolves one into a fresh table (never the stored preset; callers mutate what they get) and any other key in `opts` overrides it for that call. An unknown or nil name falls back to `guitar`, so a stale saved tone can't break playback.

- **Guitar** passes no `opts` at all and therefore lands on `guitar`, which reproduces the original sound exactly. A test asserts `hammer = 1.0` is byte-identical to omitting it — that is the regression guard for the whole preset change, and it should survive any future work here.
- **Piano** passes `{ tone = S.piano_tone }`, one of `piano_soft` / `piano_natural` / `piano_bright`, chosen from a **Tone** combo. Duration comes from the preset too (2.5 s vs the guitar's 1.0 s): a struck string needs far longer to decay, and cutting it short is audible.

Two things worth not re-deriving, both measured (full numbers in [`_future_ideas/music_theory_karplus_strong_extensions.md`](../_future_ideas/music_theory_karplus_strong_extensions.md)):

- **`release_s` is a defect fix, not a tone.** The buffer used to just stop while the string was still ringing — a 1 s guitar preview ended at 6.9% of peak, an audible click on *every* play, and the single biggest reason the previews sounded synthetic. The raised-cosine fade takes that to 0.015%. It lives in shared chord-assembly code, so both tabs get it with no per-instrument code.
- **`hammer` only does something below ~0.15.** At 0.3 the difference from a flat white-noise burst is about 1 dB. `piano_bright` sits at 0.35 precisely because "bright" here means "close to the original pluck".

Deliberately **not** modelled: inharmonicity, the stiff-string partial stretch that is a real part of piano timbre. It was attempted with allpass dispersion (one filter and cascades of up to eight, coefficients 0.28–0.7) and measured at *exactly zero* relative stretch every time — the delay line forces partials to be harmonic, and a first-order allpass shifts them all uniformly, which is a detune rather than a stretch. The future-ideas doc records the full table and why, so nobody repeats the experiment.

The piano presets vary along one axis (hammer softness, plus a little damping), holding everything else equal. That is on purpose: it keeps them cheap to re-tune from "too dull" / "too bright" feedback, which matters because the values came from spectral measurement rather than from listening.

Called from the Chord Type Explorer table (click a row, parses `row.shape` via `GuitarParseFretInput` at click time — always Standard tuning, since the static table is authored in Standard), each Shape Search result line (`entry.analysis.pitches`, already tuning-specific — the Drop D result plays back as Drop D), and the Piano tab's Play button.

No new `S` state fields for playback — every tab reuses the existing `S.preview_src`/`S.preview_pcm` (see the Drums state-fields table above).

### Why `audio_preview.lua` exists

`StopCurrentPreview` / `PlayPreviewPath` / `PlaySynthChord` were file-locals in `ui.lua` while Drums and Guitar were the only tabs. The Piano tab lives in its own file (`ui.lua` was already ~430 lines, and the tab is self-contained), so the three genuinely shared helpers moved out as globals. `PlayAudioFile` and `PlayDrumWAV` stayed local in `ui.lua` — they are drums-only and nothing else needs them.

---

## Piano tab

Reads written staff notation and reports which keys to press. Set a clef per staff and a key signature, click the staff wherever a note head is printed, and the tab gives back spelled note names, MIDI numbers, a highlighted keyboard, and block-chord playback.

Read-only like the rest of the script — it does not write MIDI. Project-mutating keyboard work belongs in the general helper's Keys tab (`actions_keys.lua`).

### The model lives in `lib/`, not `defaults.lua`

`lib/reaper_music_notation.lua` is pure (no `r`/`ctx`/`S`), so the theory is unit-testable standalone — `dev/tests/run_music_notation.lua` covers it with no REAPER objects at all. Everything hinges on the **diatonic step**:

```
step = 7 * octave + degree        degree 0..6 = C D E F G A B
```

so middle C (C4, MIDI 60) is step 28 and consecutive steps are consecutive letters. That is exactly what a staff position is, which is why a mouse y coordinate can become one integer and back. A step carries no accidental — the accidental comes from the key signature, applied to the step's *degree*.

A **clef** is two numbers: the step on its bottom line, and how far written pitch is transposed when sounded. A small 8 printed with the clef transposes what it sounds without moving any note off its line — 8 *above* (8va) sounds an octave higher, 8 *below* (8vb) an octave lower — so `NOTATION_CLEFS` carries all four transposing variants alongside plain treble and bass, six rows in total. A **slot** is a vertical position on one staff, 0 = bottom line, 8 = top line, counting half spaces; `step = clef.bottom_step + slot`.

Either staff can take any clef, so a two-treble score (two parts, not a piano grand staff) works as well as treble-over-bass. Index the table through `NOTATION_CLEF_IDX` by name — `defaults.lua` seeds `S.piano_clef_upper_idx`/`_lower_idx` that way, and `ui_piano.lua`'s nil-guards use it too, so inserting a clef row cannot silently repoint them. The test suite asserts the map matches the table in both directions and fails if a newly added clef has no pitch check.

Not modelled: the dashed `8va------` bracket over a passage. That is a temporary shift of those notes only, not a property of the clef; reading one means switching the staff to the matching transposing clef for as long as the bracket lasts.

### Two naming schemes, and why neither is `PitchName`

The readout can name a pitch two ways, toggled by `S.piano_rb_names` (**default on**):

| | Function | Spelling | Octaves | MIDI 61 |
|---|---|---|---|---|
| **REAPER piano roll** (default) | `RBPitchName` | fixed 12 names, no key signature | RB (C1 = 36) | `C#3` |
| Sheet music | `NotationNoteName` | follows the key signature | scientific (C4 = 60) | `Db4` |

Both name the same key — only the string differs, and the test suite asserts that across every key signature, clef and slot.

`RBPitchName` reproduces what REAPER's MIDI editor prints down the side of the piano roll, so a charter can read a value straight across into the editor. Its table mixes accidentals rather than picking one: **C C# D Eb E F F# G G# A Bb B**. It is not staff spelling and cannot be — it has no key signature and no concept of a letter, so Db and C# are the same string.

`NotationNoteName` deliberately does **not** go through `PitchName` (`lib/reaper_imgui_helpers.lua`) either. That one is all-sharps, so it would call Eb "D#" — on a staff the spelling is the whole point. `PitchName` and `RBPitchName` share the RB octave offset but differ at two pitch classes (D#/Eb, A#/Bb); each carries a comment pointing at the other, since they live in different libs (`PitchName` is loaded by every script, `RBPitchName` only where notation is needed).

Anything that displays an octave has to follow the toggle, not just the note list — the keyboard diagram's per-C labels do, because a keyboard reading "C2" under a note the list calls "C1" is worse than no label. Two hint lines under the readout state which scheme is showing.

`NOTATION_SIG_SLOTS` (where each key-signature accidental is drawn) is hand-authored per clef family rather than computed: engraved signature positions jump octaves to stay on the staff, and no simple rule reproduces them (the seventh flat, Fb, wraps *up* an octave in bass clef instead of dropping below the staff). The test suite checks every signature against the model — each glyph must sit on a letter that signature actually alters, stay within slots 0–9, and not collide with another.

### The canvas

`ui_piano.lua` is geometry and drawing only. It is the first place in the codebase with a genuinely interactive custom canvas:

```lua
local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
r.ImGui_InvisibleButton(ctx, '##piano_staff', canvas_w, canvas_h)   -- reserves layout AND hit-tests
local dl = r.ImGui_GetWindowDrawList(ctx)
```

Same `GetCursorScreenPos` → `GetWindowDrawList` → `DrawList_Add*` idiom as `ui_venue_players.lua`'s dot and the Drums tab's hover highlight; `InvisibleButton` replaces `Dummy` because the region must be clickable. No ReaImGui version-floor bump was needed — `InvisibleButton`, `GetMousePos`, `AddLine`, `AddCircleFilled` and `AddText` are all long-standing bindings.

Points worth not re-deriving:

- **Band splitting.** The two staves share one `InvisibleButton`. A mouse y is routed to a staff by splitting down the middle of the *gap between the bands*, not between the two bottom lines — splitting between bottom lines puts the lower staff's topmost ledger positions on the upper staff's side, where they resolve to no valid slot and become unclickable.
- **Clefs and accidentals are text labels.** The default ImGui font has no music glyphs (same reason `ui_venue_players.lua` draws its dot with `AddCircleFilled` rather than a character), so the canvas prints `Treble`, `Bass`, `#`, `b`. Bundling a music font would fix this and is noted in the future-ideas doc.
- **Note heads on adjacent slots offset horizontally**, the standard engraving of a second. Without it a close voicing draws as one blob.
- **No tooltip on the canvas.** A hover tooltip covering the thing you are trying to click is worse than useless; those instructions are printed above the staff instead. `defaults.lua` carries a comment saying so, in place of the `TIPS` entry someone would otherwise add back.

### State fields (Piano)

| Field | Type | What it holds |
|---|---|---|
| `S.piano_clef_upper_idx` | int | Index into `NOTATION_CLEFS`; default 1 (Treble) |
| `S.piano_clef_lower_idx` | int | Index into `NOTATION_CLEFS`; default 3 (Bass) |
| `S.piano_show_lower` | bool | false = single staff |
| `S.piano_rb_names` | bool | true (default) = `RBPitchName`; false = staff spelling. See "Two naming schemes" above |
| `S.piano_tone` | string | Preset **name** from `SYNTH_TONES`, not an index; default `'piano_natural'`. See "Tone presets" above |
| `S.piano_key_sig_idx` | int | Index into `KEY_SIGNATURES`; seeded from `KEY_SIG_NATURAL_IDX` |
| `S.piano_notes_upper` | table | Set of placed written steps: `[step] = true` |
| `S.piano_notes_lower` | table | Same, for the lower staff |

Note heads are stored **per staff**, not once for the grand staff: the same slot means a different sounding pitch on each (different clef, possibly a different octave transposition).

### Deferred

Chord-name identification, Pro Keys range checking, a clickable keyboard, and per-note accidental overrides were scoped with the tab and deliberately left out. [`_future_ideas/music_theory_piano_tab_extensions.md`](../_future_ideas/music_theory_piano_tab_extensions.md) has the design for each, including the two that need a `lib/` move first. The `accidental` parameter on `NotationStepToPitch` is already the hook for the fourth.

---

## Versioning note

Bump `@version` in the entry point whenever content changes meaningfully (new instrument tab, significant content corrections). The `@about` block should summarize what instruments/sections are covered.
