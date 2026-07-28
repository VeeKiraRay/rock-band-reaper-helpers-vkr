# Rock Band Music Theory Helper — Script Documentation

Entry point: `rock_band_music_theory_helper_vkr.lua`
Module folder: `rock_band_music_theory_helper_vkr/`

---

## Module table

| File | Role |
|---|---|
| `defaults.lua` | Global data tables: `DRUM_NOTATION`, `RB_LANE_COLORS`, `PRO_VS_4LANE`, `DRUM_PATTERNS`, `GUITAR_CHORDS`, `GUITAR_CHORD_TYPES`, `GUITAR_LANE_TERMS`. Also defines the minimal `S` and `TIPS` globals required by shared conventions. |
| `ui.lua` | `Loop` function, tab bar, per-instrument render functions. Calls `r.defer(Loop)` to start the script. |
| `lib/reaper_guitar_theory.lua` (shared, not in this module folder) | Pure fret-shape classification: `GuitarParseFretInput`, `GuitarClassifyChordType`, `GuitarSuggestRBMapping`, `GuitarAnalyzeShape`, `GuitarAnalyzeShapeAllTunings`. No `r`/`ctx`/`S` dependency — see "Adding a new instrument tab" below for when logic like this belongs in `lib/` instead of the module folder. |
| `lib/reaper_karplus_strong.lua` (shared) | Pure Karplus-Strong plucked-string synthesis: `KarplusStrongVoice`, `SynthesizeChordSamples`. No `r`/`ctx`/`S`, no `io` even — see "Audio playback" below. |
| `lib/reaper_wav_writer.lua` (shared) | Pure, generic mono 16-bit WAV writer: `WriteMonoWAV16`. Takes any float sample buffer — not specific to Karplus-Strong or to guitar. |

Load order in entry point:
```
lib/reaper_imgui_helpers.lua   (SectionHeader, Tooltip)
lib/reaper_guitar_theory.lua   (pure guitar shape/chord classification)
lib/reaper_karplus_strong.lua  (pure plucked-string synthesis)
lib/reaper_wav_writer.lua      (pure WAV file writer)
rock_band_music_theory_helper_vkr/defaults.lua
rock_band_music_theory_helper_vkr/ui.lua
```

No `settings.lua`, `helpers.lua`, or `actions.lua` — this is a read-only reference tool.

---

## Content data convention

All reference content lives as Lua tables in `defaults.lua`, not inline in `ui.lua`. This keeps rendering logic generic (loop over table, render rows) and makes content edits cheap — no need to touch layout code.

Each instrument section gets its own named table(s). Current tables:

| Table | Description |
|---|---|
| `DRUM_NOTATION` | Rows: `symbol`, `name`, `rb_4lane`, `rb_pro` |
| `RB_LANE_COLORS` | Rows: `color`, `piece` — currently empty; see [`_future_ideas/music_theory_drum_colors.md`](_future_ideas/music_theory_drum_colors.md) |
| `PRO_VS_4LANE` | Array of plain strings (bullet list) — currently empty; see [`_future_ideas/music_theory_pro_vs_4lane.md`](_future_ideas/music_theory_pro_vs_4lane.md) |
| `DRUM_PATTERNS` | Rows: `name`, `desc` |
| `GUITAR_CHORDS` | Rows: `shape`, `type`, `name`, `sound`, `rb_mapping` — see `lib/reaper_guitar_theory.lua`'s header comment for how these were converted/verified from `_future_ideas/GUITAR_THEORY.md` |
| `GUITAR_CHORD_TYPES` | Rows: `name`, `description` — drives the Chord Type Explorer selector; every `GUITAR_CHORDS.type` value appears here exactly once and vice versa |
| `GUITAR_LANE_TERMS` | Rows: `width`, `combos` — RB lane-combo letter names (GR/RY/... ) per spread width |

---

## Adding a new instrument tab

1. Add content tables to `defaults.lua` following the existing naming pattern (e.g., `GUITAR_CHORDS`, `GUITAR_LANE_TERMS`).
2. Add a `local function DrawGuitarTab()` in `ui.lua` that loops over those tables.
3. Add a `BeginTabItem('Guitar')` block inside the `BeginTabBar` in `Loop`, calling `DrawGuitarTab()`.

No other files need changing — **unless** the tab needs reusable classification
logic rather than plain lookup data (Drums is pure lookup; Guitar's shape
search needed real computation: fret parsing, interval math, chord-template
matching). That kind of logic belongs in its own `lib/` file (see
`lib/reaper_guitar_theory.lua`), not the module folder — it keeps the
function pure (no `r`/`ctx`/`S`), testable standalone, and reusable by other
scripts later (the Guitar tab's classifier is intentionally reusable by
`rock_band_general_helper_vkr`'s Guitar-tab converters in a future task).

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

**Playback** — `PlayGuitarChord(pitches)` in `ui.lua`, local: gated on `AUDIO_CF_AVAILABLE` (same SWS check Drums uses). Stops any current preview *before* writing (releases any hold on the scratch path so the overwrite can't race REAPER's own file handle), synthesizes via the two functions above, writes to `GUITAR_PREVIEW_WAV_PATH` (`resources/audio/guitar_preview_scratch.wav`, a single fixed name overwritten every play), then calls `PlayPreviewPath` — the same helper `PlayAudioFile` (drums) now delegates to. No manual note-off scheduling needed: `CF_Preview` plays the generated WAV to completion on its own, and drum/guitar previews share `S.preview_src`/`S.preview_pcm`, so `StopCurrentPreview()` already covers both (clicking a guitar chord mid-drum-sample interrupts it, same as clicking two drum rows in a row already does).

Called from both the Chord Type Explorer table (click a row, parses `row.shape` via `GuitarParseFretInput` at click time — always Standard tuning, since the static table is authored in Standard) and each Shape Search result line (`entry.analysis.pitches`, already tuning-specific — the Drop D result plays back as Drop D).

No new `S` state fields — guitar preview reuses the existing `S.preview_src`/`S.preview_pcm` (see the Drums state-fields table above).

---

## Versioning note

Bump `@version` in the entry point whenever content changes meaningfully (new instrument tab, significant content corrections). The `@about` block should summarize what instruments/sections are covered.
