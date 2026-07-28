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

DEFAULT_DAMPING    = 0.996  -- per-step energy-loss coefficient ("brightness" knob;
                             -- duller/warmer tone presets would lower this, brighter
                             -- ones would raise it -- see the Guitar tone variants
                             -- note in the plan for future presets, not implemented here)
DEFAULT_STAGGER_S  = 0.013  -- per-note "strum" start offset within a chord
DEFAULT_SAMPLE_RATE = 44100

----------------------------------------------------------------------
-- One plucked string at `freq` Hz, `n_samples` long.
-- opts (all optional):
--   damping:     energy-loss coefficient (default DEFAULT_DAMPING)
--   sample_rate: default DEFAULT_SAMPLE_RATE
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
    if opts.seed then math.randomseed(opts.seed) end

    local N = math.max(2, math.floor(sample_rate / freq + 0.5))
    local buf = {}
    for i = 1, N do buf[i] = math.random() * 2 - 1 end  -- noise burst = the "pluck"

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
-- Chord-level composition: one KarplusStrongVoice per pitch, staggered by
-- opts.stagger_s * (index-1) seconds (notes sorted ascending) so a
-- multi-note chord sounds strummed rather than a synchronized block hit.
--
-- pitches[]: MIDI note numbers, any order; duplicates just produce two
--   independent voices at the same pitch (harmless, if unusual input).
-- opts (all optional): damping, stagger_s (default DEFAULT_STAGGER_S),
--   seed (if given, each voice gets seed + its note index, so notes in the
--   same chord don't all pluck with identical noise -- still fully
--   deterministic overall for a given seed).
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
    for note_idx, p in ipairs(sorted) do
        local freq = 440.0 * 2.0 ^ ((p - 69) / 12.0)
        local offset_n = math.floor((note_idx - 1) * stagger_s * sample_rate)
        local voice_len = n_samples - offset_n
        if voice_len > 0 then
            local voice_seed = opts.seed and (opts.seed + note_idx) or nil
            local voice = KarplusStrongVoice(freq, voice_len, {
                damping = opts.damping, sample_rate = sample_rate, seed = voice_seed,
            })
            for i = 1, voice_len do
                mix[offset_n + i] = mix[offset_n + i] + voice[i]
            end
        end
    end
    return mix, n_samples
end
