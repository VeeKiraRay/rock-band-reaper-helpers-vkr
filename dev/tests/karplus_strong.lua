-- Karplus-Strong algorithm test set. Run via run_karplus_strong.lua.
-- Requires: Test (framework.lua), KarplusStrongVoice/SynthesizeChordSamples
-- (lib/reaper_karplus_strong.lua).

Test.section('KarplusStrongVoice')

Test.it('returns exactly n_samples floats', function()
    local out = KarplusStrongVoice(220, 500, { seed = 1 })
    Test.expect(#out == 500, 'expected 500 samples, got ' .. #out)
end)

Test.it('same seed produces identical output across two calls', function()
    local a = KarplusStrongVoice(220, 200, { seed = 42 })
    local b = KarplusStrongVoice(220, 200, { seed = 42 })
    for i = 1, 200 do
        Test.expect(a[i] == b[i], 'sample ' .. i .. ' differs despite identical seed')
    end
end)

Test.it('different seeds produce different output', function()
    local a = KarplusStrongVoice(220, 200, { seed = 1 })
    local b = KarplusStrongVoice(220, 200, { seed = 2 })
    local differs = false
    for i = 1, 200 do
        if a[i] ~= b[i] then differs = true; break end
    end
    Test.expect(differs, 'expected different seeds to produce different output')
end)

Test.it('omitting seed does not error and still returns n_samples floats', function()
    local out = KarplusStrongVoice(110, 300)
    Test.expect(#out == 300, 'expected 300 samples, got ' .. #out)
end)

Test.it('output values stay within a sane float range (no NaN/inf/blowup)', function()
    local out = KarplusStrongVoice(440, 2000, { seed = 7 })
    for i = 1, 2000 do
        local v = out[i]
        Test.expect(v == v, 'NaN at sample ' .. i)  -- NaN ~= NaN
        Test.expect(v > -10 and v < 10, 'sample ' .. i .. ' out of sane range: ' .. tostring(v))
    end
end)

-- This is the regression guard for the whole soft-hammer change: the Guitar
-- tab must keep the exact sound it has always had. hammer defaults to 1.0,
-- and at 1.0 the excitation filter and its DC-removal pass are skipped
-- entirely rather than collapsing to a near-no-op.
Test.it('hammer = 1.0 is byte-identical to omitting hammer', function()
    local a = KarplusStrongVoice(220, 3000, { seed = 42 })
    local b = KarplusStrongVoice(220, 3000, { seed = 42, hammer = 1.0 })
    for i = 1, 3000 do
        Test.expect(a[i] == b[i], 'sample ' .. i .. ' differs; the guitar path must not move')
    end
end)

Test.it('a soft hammer rolls off the upper partials', function()
    -- Magnitude at one frequency, by direct DFT bin -- no FFT needed for a
    -- handful of probes.
    local function mag(buf, len, f)
        local re, im, w = 0, 0, 2 * math.pi * f / 44100
        for i = 0, len - 1 do
            local v = buf[i + 1]
            re = re + v * math.cos(w * i)
            im = im + v * math.sin(w * i)
        end
        return math.sqrt(re * re + im * im) / len
    end
    -- Ratio of partial 12 to the fundamental, over the attack.
    local function top_ratio(hammer)
        local b = KarplusStrongVoice(220, 1323, { seed = 7, hammer = hammer })
        return mag(b, 1323, 220 * 12) / mag(b, 1323, 220)
    end
    local hard, soft = top_ratio(1.0), top_ratio(0.07)
    local drop_db = 20 * math.log(soft / hard, 10)
    -- Measured at about -15 dB; assert well inside that so ordinary retuning
    -- of the presets doesn't start failing the suite.
    Test.expect(drop_db < -10,
                string.format('expected partial 12 at least 10 dB down, got %.1f dB', drop_db))
end)

Test.it('a soft hammer does not silence the fundamental', function()
    local b = KarplusStrongVoice(220, 4000, { seed = 7, hammer = 0.07 })
    local peak = 0
    for i = 1, 4000 do
        local v = math.abs(b[i])
        if v > peak then peak = v end
    end
    Test.expect(peak > 0.01, 'soft hammer output is essentially silent: peak ' .. peak)
end)

----------------------------------------------------------------------

Test.section('SynthesizeChordSamples')

Test.it('returns n_samples matching sample_rate * duration_s', function()
    local samples, n = SynthesizeChordSamples({ 45, 52, 57 }, 44100, 0.5, { seed = 1 })
    Test.expect(n == 22050, 'expected 22050, got ' .. n)
    Test.expect(#samples == n, 'buffer length should match n_samples')
end)

Test.it('empty pitch list returns a silent (all-zero) buffer, no error', function()
    local samples, n = SynthesizeChordSamples({}, 44100, 0.1, {})
    Test.expect(n == 4410, 'expected 4410, got ' .. n)
    for i = 1, n do
        Test.expect(samples[i] == 0.0, 'expected silence at sample ' .. i)
    end
end)

Test.it('same seed produces identical chord output across two calls', function()
    local a = SynthesizeChordSamples({ 45, 52, 57 }, 44100, 0.2, { seed = 5 })
    local b = SynthesizeChordSamples({ 45, 52, 57 }, 44100, 0.2, { seed = 5 })
    for i = 1, #a do
        Test.expect(a[i] == b[i], 'sample ' .. i .. ' differs despite identical seed')
    end
end)

Test.it('multi-note chord mixing does not error and produces nonzero signal', function()
    local samples, n = SynthesizeChordSamples({ 40, 47, 52, 55 }, 44100, 0.3, { seed = 9 })
    local has_signal = false
    for i = 1, n do
        if samples[i] ~= 0.0 then has_signal = true; break end
    end
    Test.expect(has_signal, 'expected nonzero audio signal for a 4-note chord')
end)

Test.it('unison strings: 1 string with no detune equals omitting both', function()
    local a = SynthesizeChordSamples({ 45, 52 }, 44100, 0.2, { seed = 4 })
    local b = SynthesizeChordSamples({ 45, 52 }, 44100, 0.2, { seed = 4, strings = 1, detune_cents = 0 })
    for i = 1, #a do
        Test.expect(a[i] == b[i], 'sample ' .. i .. ' differs; the default path should be untouched')
    end
end)

Test.it('unison strings: 3 detuned strings differ from 1', function()
    local a = SynthesizeChordSamples({ 57 }, 44100, 0.3, { seed = 4, strings = 1 })
    local b = SynthesizeChordSamples({ 57 }, 44100, 0.3, { seed = 4, strings = 3, detune_cents = 1.5 })
    local differs = false
    for i = 1, #a do
        if a[i] ~= b[i] then differs = true; break end
    end
    Test.expect(differs, 'expected 3 detuned unison strings to change the signal')
end)

Test.it('notes in the same chord are staggered, not all starting at sample 1', function()
    -- Both calls share seed=3, and pitch 45 sorts first (lowest) in both,
    -- so its voice uses the identical seed (opts.seed + 1) in each call.
    -- With staggering, ONLY that voice has started by sample 1 -- so the
    -- 3-note mix's sample 1 should exactly equal the single-note case's
    -- sample 1, not the sum of all 3 voices' sample-1 contributions.
    local samples1 = SynthesizeChordSamples({ 45 }, 44100, 0.05, { seed = 3 })
    local samples3 = SynthesizeChordSamples({ 45, 52, 57 }, 44100, 0.05, { seed = 3 })
    Test.expect(samples3[1] == samples1[1], 'expected only the lowest note to have started by sample 1')
end)

----------------------------------------------------------------------

Test.section('Release fade')

-- Without this, the buffer simply stops while the string is still ringing --
-- a 1 s guitar preview was ending at ~7% of peak, an audible click on every
-- single play. This was the largest single cause of the previews sounding
-- artificial.
Test.it('the buffer ends at effectively zero', function()
    local s, n = SynthesizeChordSamples({ 45, 52, 57 }, 44100, 1.0, { seed = 1 })
    local peak = 0
    for i = 1, n do
        local v = math.abs(s[i])
        if v > peak then peak = v end
    end
    local tail = 0
    for i = n - 200, n do
        local v = math.abs(s[i])
        if v > tail then tail = v end
    end
    Test.expect(peak > 0, 'expected a nonzero signal to fade')
    Test.expect(tail / peak < 0.01,
                string.format('tail is %.3f%% of peak; expected under 1%%', 100 * tail / peak))
    -- Below 16-bit quantisation (1/32768), so it cannot survive the WAV write.
    Test.expect(math.abs(s[n]) < 1 / 32768, 'final sample is audible: ' .. tostring(s[n]))
end)

Test.it('the fade only touches the tail', function()
    local faded = SynthesizeChordSamples({ 45 }, 44100, 1.0, { seed = 2 })
    local raw   = SynthesizeChordSamples({ 45 }, 44100, 1.0, { seed = 2, release_s = 0 })
    local rel   = math.floor(0.15 * 44100)
    for i = 1, #raw - rel do
        Test.expect(faded[i] == raw[i], 'sample ' .. i .. ' changed outside the fade region')
    end
    Test.expect(math.abs(raw[#raw]) > math.abs(faded[#faded]),
                'release_s = 0 should leave the raw ringing tail in place')
end)

Test.it('release_s = 0 disables the fade entirely', function()
    local a = SynthesizeChordSamples({ 45 }, 44100, 0.3, { seed = 2, release_s = 0 })
    local peak, tail = 0, 0
    for i = 1, #a do local v = math.abs(a[i]); if v > peak then peak = v end end
    for i = #a - 50, #a do local v = math.abs(a[i]); if v > tail then tail = v end end
    Test.expect(tail / peak > 0.01, 'expected an un-faded buffer to still be ringing at the end')
end)

Test.it('an over-long release clamps to half the buffer', function()
    local s, n = SynthesizeChordSamples({ 45 }, 44100, 0.1, { seed = 2, release_s = 99 })
    Test.expect(#s == n, 'buffer length changed')
    for i = 1, n do
        Test.expect(s[i] == s[i], 'NaN at sample ' .. i)
    end
    -- The first half is outside the clamped fade, so it must still have signal.
    local head = 0
    for i = 1, math.floor(n / 2) do
        local v = math.abs(s[i])
        if v > head then head = v end
    end
    Test.expect(head > 0, 'clamped fade wiped out the whole buffer')
end)

----------------------------------------------------------------------

Test.section('Tone presets')

Test.it('SYNTH_TONE_ORDER and SYNTH_TONES correspond exactly', function()
    local seen = {}
    for _, name in ipairs(SYNTH_TONE_ORDER) do
        Test.expect(SYNTH_TONES[name], 'SYNTH_TONE_ORDER lists unknown tone ' .. name)
        Test.expect(not seen[name], 'SYNTH_TONE_ORDER repeats ' .. name)
        seen[name] = true
    end
    for name in pairs(SYNTH_TONES) do
        Test.expect(seen[name], name .. ' is missing from SYNTH_TONE_ORDER, so no combo will show it')
    end
end)

Test.it('every preset carries every key a caller reads', function()
    local required = { 'label', 'family', 'damping', 'hammer',
                       'strings', 'detune_cents', 'stagger_s', 'duration_s', 'release_s' }
    for name, preset in pairs(SYNTH_TONES) do
        for _, key in ipairs(required) do
            Test.expect(preset[key] ~= nil, name .. ' is missing ' .. key)
        end
        Test.expect(preset.duration_s > 0, name .. ' has a non-positive duration')
        Test.expect(preset.strings >= 1, name .. ' has fewer than one string')
        Test.expect(preset.hammer > 0 and preset.hammer <= 1.0, name .. ' has hammer outside 0..1')
    end
end)

Test.it('the default tone exists and is the guitar sound', function()
    local preset = SYNTH_TONES[SYNTH_TONE_DEFAULT]
    Test.expect(preset, 'SYNTH_TONE_DEFAULT names no preset')
    Test.expect(preset.hammer == 1.0, 'the default tone must keep the original white-noise pluck')
    Test.expect(preset.strings == 1, 'the default tone must stay single-string')
end)

Test.it('SynthToneOpts falls back to the default for an unknown or nil name', function()
    Test.expect(SynthToneOpts('no such tone').label == SYNTH_TONES[SYNTH_TONE_DEFAULT].label,
                'unknown name did not fall back')
    Test.expect(SynthToneOpts(nil).label == SYNTH_TONES[SYNTH_TONE_DEFAULT].label,
                'nil name did not fall back')
end)

Test.it('SynthToneOpts lets overrides win', function()
    local o = SynthToneOpts('piano_soft', { hammer = 0.99, stagger_s = 0.5 })
    Test.expect(o.hammer == 0.99, 'override ignored: hammer = ' .. tostring(o.hammer))
    Test.expect(o.stagger_s == 0.5, 'override ignored: stagger_s = ' .. tostring(o.stagger_s))
    Test.expect(o.duration_s == SYNTH_TONES.piano_soft.duration_s,
                'un-overridden key should come from the preset')
end)

Test.it('SynthToneOpts never hands back the stored preset', function()
    local before = SYNTH_TONES.piano_soft.hammer
    local o = SynthToneOpts('piano_soft')
    o.hammer = 123
    Test.expect(SYNTH_TONES.piano_soft.hammer == before,
                'mutating the returned table changed the shared preset')
    Test.expect(o ~= SYNTH_TONES.piano_soft, 'returned the preset table itself')
end)

Test.it('SynthTonesInFamily returns the piano tones in order', function()
    local fam = SynthTonesInFamily('piano')
    Test.expect(#fam > 0, 'no piano tones -- the Piano tab combo would be empty')
    for _, entry in ipairs(fam) do
        Test.expect(entry.preset.family == 'piano', entry.name .. ' is not in the piano family')
        Test.expect(SYNTH_TONES[entry.name] == entry.preset, entry.name .. ' preset mismatch')
    end
    -- Order must follow SYNTH_TONE_ORDER, not pairs() iteration order.
    local pos, prev = {}, 0
    for i, name in ipairs(SYNTH_TONE_ORDER) do pos[name] = i end
    for _, entry in ipairs(fam) do
        Test.expect(pos[entry.name] > prev, 'family list is out of SYNTH_TONE_ORDER order')
        prev = pos[entry.name]
    end
end)

Test.it('every preset actually synthesizes a usable buffer', function()
    for name in pairs(SYNTH_TONES) do
        local o = SynthToneOpts(name, { seed = 11 })
        local s, n = SynthesizeChordSamples({ 48, 55, 64 }, 44100, o.duration_s, o)
        Test.expect(n > 0 and #s == n, name .. ' produced no samples')
        local peak = 0
        for i = 1, n do
            local v = s[i]
            Test.expect(v == v, name .. ' produced NaN at sample ' .. i)
            if math.abs(v) > peak then peak = math.abs(v) end
        end
        Test.expect(peak > 0.01, name .. ' is essentially silent (peak ' .. peak .. ')')
        Test.expect(peak < 100, name .. ' blew up (peak ' .. peak .. ')')
    end
end)
