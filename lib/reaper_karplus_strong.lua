-- Karplus-Strong plucked-string synthesis. Pure Lua (math/table only -- no
-- io, no reaper.*) -- fully unit-testable standalone, safe to dofile from a
-- Lua-only context (see dev/tests/run_karplus_strong.lua).
--
-- Physical model: a short delay line seeded with noise (the "pluck"), read
-- and averaged back into itself each sample (a one-zero lowpass inside the
-- feedback loop). That alone naturally produces a decaying, harmonically
-- rich plucked-string tone -- no hand-shaped envelope or explicit harmonics
-- needed, unlike additive (sine + harmonics) synthesis. Verified against an
-- additive-synthesis prototype before adopting this: faster to compute and
-- confirmed to sound meaningfully more like a plucked string.
--
-- Output is a flat table of unnormalized floats (~-1..1, not clipped or
-- quantized) -- lib/reaper_wav_writer.lua turns that into a playable file.

DEFAULT_DAMPING    = 0.996  -- per-step energy-loss coefficient ("brightness" knob);
                             -- see SYNTH_TONES below for the per-instrument values
DEFAULT_STAGGER_S  = 0.013  -- per-note "strum" start offset within a chord
DEFAULT_SAMPLE_RATE = 44100
DEFAULT_RELEASE_S  = 0.15   -- fade-out at the end of a chord buffer; see the
                             -- release note in SynthesizeChordSamples

----------------------------------------------------------------------
-- One struck/plucked string at `freq` Hz, `n_samples` long.
-- opts (all optional):
--   damping:     energy-loss coefficient (default DEFAULT_DAMPING)
--   sample_rate: default DEFAULT_SAMPLE_RATE
--   hammer:      excitation softness, 0..1 (default 1.0 = a flat white-noise
--     burst, i.e. a pluck). Below 1.0 the burst is low-passed before it
--     enters the delay line, modelling a soft hammer striking rather than a
--     fingernail plucking: a hammer puts far more energy into the low
--     partials. Measured on a 220 Hz voice, partials 8-12 sit 10-15 dB lower
--     at hammer = 0.07 than at 1.0. The useful range is narrow and low --
--     0.05..0.3. At 0.3 the difference from white noise is already marginal
--     (~1 dB), which is why the piano presets sit near 0.1.
--   seed:        if given, math.randomseed(seed) right before generating
--     this voice's noise burst -- reproducible output for tests, and the
--     hook a future "let the user control variation" feature would use.
--     If omitted, uses whatever the ambient RNG state currently is, so
--     repeated calls naturally differ (like a real strum) -- callers that
--     want real variation must ensure math.randomseed() was called with
--     real entropy at least once this session (the entry point does this
--     at startup).
-- Returns a table of n_samples floats.
----------------------------------------------------------------------
function KarplusStrongVoice(freq, n_samples, opts)
    opts = opts or {}
    local damping     = opts.damping or DEFAULT_DAMPING
    local sample_rate  = opts.sample_rate or DEFAULT_SAMPLE_RATE
    local hammer       = opts.hammer or 1.0
    if opts.seed then math.randomseed(opts.seed) end

    local N = math.max(2, math.floor(sample_rate / freq + 0.5))
    local buf = {}
    for i = 1, N do buf[i] = math.random() * 2 - 1 end  -- noise burst = the "pluck"

    -- Soft-hammer excitation. Gated rather than always-on with hammer = 1.0
    -- collapsing to a no-op, because the DC-removal pass below would still
    -- shift every sample by the burst's mean -- this way the default path is
    -- byte-identical to what it has always produced.
    if hammer < 1.0 then
        local prev = 0.0
        for i = 1, N do
            prev = hammer * buf[i] + (1.0 - hammer) * prev
            buf[i] = prev
        end
        -- A one-pole low-pass leaves a DC offset behind; left in, it survives
        -- the feedback loop as a slow drift and eats headroom at the WAV
        -- writer's peak normalisation.
        local mean = 0.0
        for i = 1, N do mean = mean + buf[i] end
        mean = mean / N
        for i = 1, N do buf[i] = buf[i] - mean end
    end

    local out = {}
    local pos = 1
    for i = 1, n_samples do
        local nxt = (pos % N) + 1
        local cur = buf[pos]
        out[i] = cur
        buf[pos] = 0.5 * (cur + buf[nxt]) * damping
        pos = nxt
    end
    return out
end

----------------------------------------------------------------------
-- Tone presets
--
-- Every knob above collected into named instrument voices, so callers ask
-- for a sound rather than assembling six numbers. Expressed as opts rather
-- than new top-level functions deliberately -- KarplusStrongVoice and
-- SynthesizeChordSamples keep their signatures.
--
-- `label` and `family` live on the preset itself rather than in a parallel
-- list in the UI, so a new preset shows up in the right combo automatically
-- and the two cannot drift apart.
--
-- The piano presets vary along ONE axis: hammer softness (plus a little
-- damping to match). Everything else is held equal, which keeps them easy to
-- reason about and cheap to re-tune from "too dull" / "too bright" feedback.
-- The numbers came from spectral measurement, not taste -- see the tuning
-- notes in _future_ideas/music_theory_karplus_strong_extensions.md.
--
-- Not modelled: inharmonicity (the stiff-string partial stretch that is a
-- real part of piano timbre). It was attempted and measured at exactly zero
-- effect; the same doc records what was tried and why it cannot work here.
----------------------------------------------------------------------

SYNTH_TONES = {
    -- Reproduces the original plucked-string sound exactly, apart from the
    -- release fade that every tone now gets.
    guitar = {
        label = 'Guitar', family = 'guitar',
        damping = 0.996, hammer = 1.0,
        strings = 1, detune_cents = 0,
        stagger_s = DEFAULT_STAGGER_S, duration_s = 1.0, release_s = 0.15,
    },
    piano_soft = {
        label = 'Soft', family = 'piano',
        damping = 0.9996, hammer = 0.07,
        strings = 3, detune_cents = 1.5,
        stagger_s = 0, duration_s = 2.5, release_s = 0.25,
    },
    piano_natural = {
        label = 'Natural', family = 'piano',
        damping = 0.9995, hammer = 0.12,
        strings = 3, detune_cents = 1.5,
        stagger_s = 0, duration_s = 2.5, release_s = 0.25,
    },
    piano_bright = {
        label = 'Bright', family = 'piano',
        damping = 0.9993, hammer = 0.35,
        strings = 3, detune_cents = 1.5,
        stagger_s = 0, duration_s = 2.5, release_s = 0.25,
    },
}

-- Presentation order. `pairs()` over SYNTH_TONES has no defined order, so a
-- combo built straight from it would shuffle between sessions.
SYNTH_TONE_ORDER = { 'guitar', 'piano_soft', 'piano_natural', 'piano_bright' }

SYNTH_TONE_DEFAULT = 'guitar'

----------------------------------------------------------------------
-- A fresh opts table for tone `name`, with any keys in `overrides` winning.
-- An unknown or nil name falls back to SYNTH_TONE_DEFAULT rather than
-- erroring, so a stale saved tone name can't break playback.
-- Never returns the stored preset itself -- callers mutate what they get.
----------------------------------------------------------------------
function SynthToneOpts(name, overrides)
    local preset = SYNTH_TONES[name] or SYNTH_TONES[SYNTH_TONE_DEFAULT]
    local out = {}
    for k, v in pairs(preset) do out[k] = v end
    if overrides then
        for k, v in pairs(overrides) do
            if v ~= nil then out[k] = v end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Presets belonging to one family, in SYNTH_TONE_ORDER order.
-- Returns { { name = 'piano_soft', preset = {...} }, ... }.
----------------------------------------------------------------------
function SynthTonesInFamily(family)
    local out = {}
    for _, name in ipairs(SYNTH_TONE_ORDER) do
        local preset = SYNTH_TONES[name]
        if preset and preset.family == family then
            out[#out + 1] = { name = name, preset = preset }
        end
    end
    return out
end

-- Seed spacing between notes of a chord. Each note owns a block of this many
-- consecutive seeds, one per unison string, so adding a string can never
-- collide with the next note's seeds (which would make two voices generate
-- the identical noise burst).
local SEEDS_PER_NOTE = 16

----------------------------------------------------------------------
-- Chord-level composition: one or more KarplusStrongVoices per pitch,
-- staggered by opts.stagger_s * (index-1) seconds (notes sorted ascending)
-- so a multi-note chord sounds strummed rather than a synchronized block
-- hit -- pass stagger_s = 0 for a struck instrument, where both hands land
-- together.
--
-- pitches[]: MIDI note numbers, any order; duplicates just produce two
--   independent voices at the same pitch (harmless, if unusual input).
-- opts (all optional):
--   damping, hammer:  passed through to each KarplusStrongVoice
--   stagger_s:        default DEFAULT_STAGGER_S
--   strings:          unison strings per note (default 1). A piano has two
--     or three strings to a note, tuned a hair apart; the slow beating that
--     produces is a large part of what reads as "piano" rather than "synth".
--   detune_cents:     total spread across those strings (default 0), applied
--     symmetrically about the true pitch. Keep it small -- at 1.5 cents a
--     440 Hz note beats at 0.38 Hz, about one cycle per 2.5 s preview, which
--     is a slow swell; past ~5 cents it stops sounding like one note.
--   release_s:        fade-out at the end (default DEFAULT_RELEASE_S),
--     clamped to half the buffer. Without it the buffer just stops, and a
--     string is nowhere near silent by then -- a 1 s guitar preview ends at
--     ~7% of peak, which is an audible click on every play. Pass 0 to
--     disable (tests that need to see the raw tail do).
--   seed:             if given, every voice is derived from it, so the whole
--     chord is reproducible while no two voices share a burst.
-- Returns samples[] (flat float buffer, length n_samples), n_samples.
----------------------------------------------------------------------
function SynthesizeChordSamples(pitches, sample_rate, duration_s, opts)
    opts = opts or {}
    local n_samples = math.floor(sample_rate * duration_s)
    local mix = {}
    for i = 1, n_samples do mix[i] = 0.0 end
    if not pitches or #pitches == 0 then return mix, n_samples end

    local sorted = {}
    for _, p in ipairs(pitches) do sorted[#sorted + 1] = p end
    table.sort(sorted)

    local stagger_s = opts.stagger_s or DEFAULT_STAGGER_S
    local strings   = math.max(1, math.floor(opts.strings or 1))
    local detune    = opts.detune_cents or 0

    for note_idx, p in ipairs(sorted) do
        local f0 = 440.0 * 2.0 ^ ((p - 69) / 12.0)
        local offset_n = math.floor((note_idx - 1) * stagger_s * sample_rate)
        local voice_len = n_samples - offset_n
        if voice_len > 0 then
            for s = 1, strings do
                -- Spread symmetrically about f0: a single string lands exactly
                -- on pitch, two straddle it, three put one dead centre.
                local cents = (strings > 1) and ((s - (strings + 1) / 2) * detune) or 0
                local freq  = (cents ~= 0) and (f0 * 2.0 ^ (cents / 1200.0)) or f0
                local voice_seed = opts.seed and (opts.seed + note_idx * SEEDS_PER_NOTE + s) or nil
                local voice = KarplusStrongVoice(freq, voice_len, {
                    damping = opts.damping, hammer = opts.hammer,
                    sample_rate = sample_rate, seed = voice_seed,
                })
                for i = 1, voice_len do
                    mix[offset_n + i] = mix[offset_n + i] + voice[i]
                end
            end
        end
    end

    -- Raised-cosine release, so the file can never end on a step discontinuity.
    local release_s = opts.release_s or DEFAULT_RELEASE_S
    local rel = math.min(math.floor(release_s * sample_rate), math.floor(n_samples / 2))
    if rel > 0 then
        local first = n_samples - rel + 1
        for i = 0, rel - 1 do
            local g = 0.5 * (1.0 + math.cos(math.pi * i / rel))
            mix[first + i] = mix[first + i] * g
        end
    end

    return mix, n_samples
end
