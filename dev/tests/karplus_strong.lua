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
