-- Algorithm unit tests for GateAndSplit, ApplyMinOffset, SnapOnsets (lib/reaper_dsp.lua).
-- These functions take plain Lua tables and make no REAPER API calls.

local function make_ci(contour, win_samps, sr, time_offset)
    return { contour = contour, win_samps = win_samps, sr = sr,
             time_offset = time_offset or 0.0 }
end

----------------------------------------------------------------------
Test.section('ApplyMinOffset')

Test.it('non-overlapping notes: unchanged', function()
    local notes = { {s=0.0, e=0.5}, {s=1.0, e=1.5} }
    local out, capped, dropped = ApplyMinOffset(notes, 0.1)
    Test.expect(#out == 2,    '2 notes in → 2 notes out')
    Test.expect(capped == 0,  'nothing capped')
    Test.expect(dropped == 0, 'nothing dropped')
    Test.expect(math.abs(out[1].e - 0.5) < 1e-9, 'note 1 end unchanged at 0.5')
end)

Test.it('overlapping note: end capped to maintain min offset', function()
    -- note[1].e=1.05, note[2].s=1.0, min_off=0.1 → cap = 1.0-0.1 = 0.9
    local notes = { {s=0.0, e=1.05}, {s=1.0, e=2.0} }
    local out, capped = ApplyMinOffset(notes, 0.1)
    Test.expect(capped == 1, '1 note capped')
    Test.expect(math.abs(out[1].e - 0.9) < 1e-9, 'note 1 end capped to 0.9')
end)

Test.it('note crushed to zero length after cap: dropped', function()
    -- note[2].s=0.1, min_off=0.5 → cap = 0.1-0.5 = -0.4; note[1].e(1.5) → -0.4 < s(0) → dropped
    local notes = { {s=0.0, e=1.5}, {s=0.1, e=2.0} }
    local _, _, dropped = ApplyMinOffset(notes, 0.5)
    Test.expect(dropped == 1, '1 note dropped after cap reduces it below zero length')
end)

Test.it('last note end is never capped', function()
    -- note[1] overlaps note[2]; note[2] is last and must remain unchanged
    local notes = { {s=0.0, e=0.3}, {s=0.2, e=1.0} }
    local out = ApplyMinOffset(notes, 0.0)
    Test.expect(math.abs(out[#out].e - 1.0) < 1e-9, 'last note end unchanged at 1.0')
end)

----------------------------------------------------------------------
Test.section('GateAndSplit - no-split mode')

Test.it('two distinct loud sections → 2 notes, 2 phrases', function()
    -- win_s=1s; two blobs of 2 windows above threshold, separated by quiet
    local ci = make_ci({0, 0.8, 0.8, 0, 0, 0, 0.8, 0.8, 0}, 100, 100)
    local notes, phrases = GateAndSplit(ci, 0.5, 0, 1.5)
    Test.expect(#notes == 2,  '2 notes detected')
    Test.expect(phrases == 2, '2 phrases')
end)

Test.it('min-duration filter removes events shorter than threshold', function()
    -- each "note" is 1 window = 1s; min_note_s=2s → min_wins=2 → both filtered
    local ci = make_ci({0, 0.8, 0, 0, 0.8, 0}, 100, 100)
    local notes = GateAndSplit(ci, 0.5, 0, 2.0)
    Test.expect(#notes == 0, 'short notes filtered out by min_note_s')
end)

Test.it('note times are shifted by time_offset', function()
    local ci = make_ci({0, 0.8, 0.8, 0}, 100, 100, 10.0)
    local notes = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 1, '1 note')
    Test.expect(notes[1].s >= 10.0, 'start time includes time_offset')
end)

Test.it('empty contour → 0 notes, 0 phrases', function()
    local ci = make_ci({}, 100, 100)
    local notes, phrases = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 0 and phrases == 0, 'empty contour → nothing')
end)

Test.it('all-below-threshold contour → 0 notes', function()
    local ci = make_ci({0.1, 0.2, 0.1, 0.0, 0.1}, 100, 100)
    local notes = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 0, 'all quiet → 0 notes')
end)

----------------------------------------------------------------------
Test.section('GateAndSplit - split mode')

Test.it('single phrase with internal valley → 2 sub-notes, split_extra >= 1', function()
    -- threshold=0.3 (gate). Valley=0.4 is above gate → whole contour is 1 phrase.
    -- peak=0.8, split_ratio=0.7 → cut=0.56; valley=0.4 < cut → 2 sub-notes.
    local ci = make_ci({0, 0.6, 0.8, 0.4, 0.8, 0.6, 0}, 100, 100)
    local notes, phrases, split_extra = GateAndSplit(ci, 0.3, 0.7, 1.0)
    Test.expect(phrases == 1,      '1 phrase before split')
    Test.expect(split_extra >= 1,  'split produced at least 1 extra note')
    Test.expect(#notes >= 2,       'at least 2 sub-notes')
end)

Test.it('flat phrase above cut level → 1 sub-note, split_extra=0', function()
    local ci = make_ci({0, 0.8, 0.8, 0.8, 0.8, 0}, 100, 100)
    local _, _, split_extra = GateAndSplit(ci, 0.5, 0.7, 1.0)
    Test.expect(split_extra == 0, 'no valley → no split')
end)

----------------------------------------------------------------------
Test.section('SnapOnsets')

Test.it('snaps start to nearest positive derivative, end to nearest negative', function()
    -- win_s=1s, t_off=0. Note start at 2.5s (si=3), end at 6.5s (ei=7), window_ms=3000 (half=3).
    -- Sharpest rise: i=4 (0.9-0.0=0.9) → snapped_s = (4-1)*1 = 3.0
    -- Sharpest fall: i=8 (0.0-0.9=-0.9) → snapped_e = (8-1)*1 = 7.0
    local ci = make_ci({0,0,0,0.9,0.9,0.9,0.9,0,0}, 100, 100)
    local out = SnapOnsets({{s=2.5, e=6.5}}, ci, 3000)
    Test.expect(#out == 1, '1 note in → 1 note out')
    Test.expect(math.abs(out[1].s - 3.0) < 1e-9, 'start snapped to t=3.0')
    Test.expect(math.abs(out[1].e - 7.0) < 1e-9, 'end snapped to t=7.0')
end)

Test.it('fallback to original when snapping would produce empty note', function()
    -- Flat contour: all derivatives ~0; best_si and best_ei may coincide → use original
    local ci = make_ci({0.9, 0.9, 0.9, 0.9, 0.9}, 100, 100)
    local note = {s=1.5, e=3.5}
    local out = SnapOnsets({note}, ci, 1000)
    Test.expect(out[1].e > out[1].s, 'output note must not be empty')
end)

Test.it('empty note list returns empty list', function()
    local ci = make_ci({0.5, 0.8, 0.3}, 100, 100)
    local out = SnapOnsets({}, ci, 500)
    Test.expect(#out == 0, 'empty input → empty output')
end)

----------------------------------------------------------------------
-- YIN core: ComputeCMND + SearchYINTau
--
-- Both take plain Lua tables, so a synthetic waveform exercises the real
-- detector with no audio file and no REAPER audio API.
-- Tones are harmonic-rich on purpose: a pure sine has no harmonic structure
-- for the CMND to mistake for the fundamental, so it can never reproduce the
-- octave errors these tests exist to catch.
----------------------------------------------------------------------

local SR       = 48000
local YIN_THR  = 0.15
local MIN_HZ   = 80
local MAX_HZ   = 1000

-- Band-limited sawtooth: sum of n_harm harmonics at 1/k amplitude.
local function make_tone(freq, sr, n_samps, n_harm)
    local mono = {}
    for i = 1, n_samps do
        local t, s = (i - 1) / sr, 0
        for k = 1, n_harm do
            if k * freq < sr * 0.5 then
                s = s + math.sin(2 * math.pi * k * freq * t) / k
            end
        end
        mono[i] = s * 0.5
    end
    return mono
end

local function make_noise(n_samps, seed)
    local mono, x = {}, seed or 12345
    for i = 1, n_samps do
        x = (1103515245 * x + 12345) % 2147483648
        mono[i] = (x / 2147483648) * 2 - 1
    end
    return mono
end

local function make_silence(n_samps)
    local mono = {}
    for i = 1, n_samps do mono[i] = 0 end
    return mono
end

-- Run the full core path for a window of win_ms at the given min freq.
-- Returns (pitch, confidence), matching SearchYINTau.
local function detect(mono_fn, win_ms, min_hz, max_hz, min_conf)
    min_hz, max_hz = min_hz or MIN_HZ, max_hz or MAX_HZ
    local tau_max, n_samps = YINWindowSize(SR, win_ms / 1000, min_hz)
    if not tau_max then return nil end
    local tau_min = math.max(1, math.floor(SR / max_hz))
    if tau_max < tau_min then return nil end
    local d = ComputeCMND(mono_fn(n_samps), tau_max)
    if not d then return nil end
    return SearchYINTau(d, tau_min, tau_max, YIN_THR, SR, min_hz, max_hz, min_conf)
end

Test.section('YIN core - pitch accuracy')

Test.it('220 Hz sawtooth, 30 ms window → A3 (MIDI 57)', function()
    local p = detect(function(n) return make_tone(220, SR, n, 12) end, 30)
    Test.expect(p == 57, 'expected MIDI 57, got ' .. tostring(p))
end)

Test.it('110 Hz sawtooth, 30 ms window → A2 (MIDI 45), not an octave down', function()
    local p = detect(function(n) return make_tone(110, SR, n, 16) end, 30)
    Test.expect(p == 45, 'expected MIDI 45, got ' .. tostring(p))
end)

Test.it('82.4 Hz sawtooth (E2) near min_freq, 30 ms window → MIDI 40', function()
    local p = detect(function(n) return make_tone(82.4, SR, n, 20) end, 30)
    Test.expect(p == 40, 'expected MIDI 40, got ' .. tostring(p))
end)

Test.it('82.4 Hz sawtooth (E2), 60 ms window → MIDI 40', function()
    local p = detect(function(n) return make_tone(82.4, SR, n, 20) end, 60)
    Test.expect(p == 40, 'expected MIDI 40, got ' .. tostring(p))
end)

Test.it('440 Hz sawtooth → A4 (MIDI 69)', function()
    local p = detect(function(n) return make_tone(440, SR, n, 8) end, 30)
    Test.expect(p == 69, 'expected MIDI 69, got ' .. tostring(p))
end)

Test.section('YIN core - rejection')

Test.it('white noise is rejected', function()
    local p = detect(function(n) return make_noise(n) end, 30)
    Test.expect(p == nil, 'expected nil for noise, got ' .. tostring(p))
end)

Test.it('silence is rejected', function()
    local p = detect(function(n) return make_silence(n) end, 30)
    Test.expect(p == nil, 'expected nil for silence, got ' .. tostring(p))
end)

Test.it('tone below min_freq is rejected, not clamped to a boundary tau', function()
    -- 55 Hz with min_freq 80: the true period is longer than tau_max, so the
    -- search must reject rather than settle on the tau_max boundary.
    local p = detect(function(n) return make_tone(55, SR, n, 20) end, 60)
    Test.expect(p == nil, 'expected nil below min_freq, got ' .. tostring(p))
end)

Test.it('tone above max_freq resolves to an in-range sub-period, not garbage', function()
    -- Every signal periodic at f is also periodic at f/2, f/3, ... so a 1500 Hz
    -- tone genuinely repeats at tau=64 (750 Hz). With 1500 Hz outside the search
    -- range, reporting that sub-period is correct - what must not happen is a
    -- result pinned to a scan boundary.
    local p = detect(function(n) return make_tone(1500, SR, n, 4) end, 30)
    Test.expect(p == nil or p == 78,
        'expected nil or the 750 Hz sub-period (78), got ' .. tostring(p))
end)

----------------------------------------------------------------------
-- Boundary rejection, tested directly on SearchYINTau with hand-built CMND
-- tables. A minimum sitting on tau_min or tau_max means the true period most
-- likely lies outside the searched range and the scan just ran out of room;
-- such a result also has no neighbour to interpolate against.
----------------------------------------------------------------------

-- d[] that dips to `dip_value` at `dip_tau` and sits at `floor_value` elsewhere.
local function make_cmnd(tau_max, dip_tau, dip_value, floor_value)
    local d = {}
    d[0] = 0
    for tau = 1, tau_max do d[tau] = floor_value end
    d[dip_tau] = dip_value
    return d
end

Test.section('YIN core - boundary rejection')

Test.it('minimum exactly at tau_min is rejected', function()
    local d = make_cmnd(600, 100, 0.02, 0.9)
    local p = SearchYINTau(d, 100, 600, YIN_THR, SR, MIN_HZ, MAX_HZ)
    Test.expect(p == nil, 'expected nil at tau_min, got ' .. tostring(p))
end)

Test.it('minimum exactly at tau_max is rejected', function()
    local d = make_cmnd(600, 600, 0.02, 0.9)
    local p = SearchYINTau(d, 100, 600, YIN_THR, SR, MIN_HZ, MAX_HZ)
    Test.expect(p == nil, 'expected nil at tau_max, got ' .. tostring(p))
end)

Test.it('minimum one lag inside the lower boundary is accepted', function()
    local d = make_cmnd(600, 101, 0.02, 0.9)
    local p = SearchYINTau(d, 100, 600, YIN_THR, SR, MIN_HZ, MAX_HZ)
    Test.expect(p ~= nil, 'expected a pitch just inside tau_min, got nil')
end)

Test.it('boundary rejection also applies to the global-minimum fallback', function()
    -- No value dips below the threshold, so the search takes the fallback
    -- branch; its minimum still sits on tau_max and must be rejected.
    local d = make_cmnd(600, 600, 0.30, 0.9)
    local p = SearchYINTau(d, 100, 600, YIN_THR, SR, MIN_HZ, MAX_HZ)
    Test.expect(p == nil, 'expected nil, got ' .. tostring(p))
end)

----------------------------------------------------------------------
-- Stress cases. Clean sawtooths are perfectly periodic and noise-free, so
-- they detect correctly even with a biased CMND. Real vocal stems are
-- neither. These reproduce the conditions the bias actually shows up under:
-- a weak fundamental, additive noise, and a short window on a low note.
----------------------------------------------------------------------

-- Sum two signals sample-wise.
local function mix(a, b)
    local out = {}
    for i = 1, #a do out[i] = a[i] + (b[i] or 0) end
    return out
end

local function scale(mono, g)
    local out = {}
    for i = 1, #mono do out[i] = mono[i] * g end
    return out
end

-- Harmonics 2..n_harm only: no energy at the fundamental. The ear (and a
-- correct CMND) still hears freq; a biased search drops an octave.
local function make_missing_fundamental(freq, sr, n_samps, n_harm)
    local mono = {}
    for i = 1, n_samps do
        local t, s = (i - 1) / sr, 0
        for k = 2, n_harm do
            if k * freq < sr * 0.5 then
                s = s + math.sin(2 * math.pi * k * freq * t) / k
            end
        end
        mono[i] = s * 0.5
    end
    return mono
end

-- Sine whose frequency wobbles +/- depth_hz at rate_hz (vibrato).
local function make_vibrato(freq, sr, n_samps, n_harm, depth_hz, rate_hz)
    local mono, phase = {}, 0
    for i = 1, n_samps do
        local t = (i - 1) / sr
        local f = freq + depth_hz * math.sin(2 * math.pi * rate_hz * t)
        phase = phase + 2 * math.pi * f / sr
        local s = 0
        for k = 1, n_harm do
            if k * f < sr * 0.5 then s = s + math.sin(k * phase) / k end
        end
        mono[i] = s * 0.5
    end
    return mono
end

Test.section('YIN core - stress cases')

Test.it('110 Hz with no energy at the fundamental → MIDI 45, not 57', function()
    local p = detect(function(n)
        return make_missing_fundamental(110, SR, n, 16)
    end, 60)
    Test.expect(p == 45, 'expected MIDI 45, got ' .. tostring(p))
end)

Test.it('82.4 Hz (E2) with noise at ~12 dB SNR, 60 ms window → MIDI 40', function()
    local p = detect(function(n)
        return mix(make_tone(82.4, SR, n, 20), scale(make_noise(n, 999), 0.12))
    end, 60)
    Test.expect(p == 40, 'expected MIDI 40, got ' .. tostring(p))
end)

Test.it('220 Hz with noise at ~12 dB SNR → MIDI 57', function()
    local p = detect(function(n)
        return mix(make_tone(220, SR, n, 12), scale(make_noise(n, 4242), 0.12))
    end, 30)
    Test.expect(p == 57, 'expected MIDI 57, got ' .. tostring(p))
end)

Test.it('220 Hz with 6 Hz / 3 Hz vibrato → MIDI 57', function()
    local p = detect(function(n)
        return make_vibrato(220, SR, n, 12, 6, 3)
    end, 30)
    Test.expect(p == 57, 'expected MIDI 57, got ' .. tostring(p))
end)

Test.it('98 Hz (G2) with noise, 30 ms window → MIDI 43', function()
    local p = detect(function(n)
        return mix(make_tone(98, SR, n, 18), scale(make_noise(n, 7331), 0.12))
    end, 30)
    Test.expect(p == 43, 'expected MIDI 43, got ' .. tostring(p))
end)

Test.section('YIN core - confidence')

Test.it('a clean tone reports high confidence', function()
    local _, conf = detect(function(n) return make_tone(220, SR, n, 12) end, 30)
    Test.expect(conf ~= nil, 'confidence must be returned alongside the pitch')
    Test.expect(conf > 0.85, 'expected > 0.85 for a clean tone, got ' .. tostring(conf))
end)

Test.it('confidence falls as noise rises', function()
    local _, clean = detect(function(n) return make_tone(220, SR, n, 12) end, 30)
    local _, noisy = detect(function(n)
        return mix(make_tone(220, SR, n, 12), scale(make_noise(n, 55), 0.5))
    end, 30)
    Test.expect(noisy ~= nil, 'noisy tone should still detect at the default gate')
    Test.expect(noisy < clean, string.format(
        'expected noisy (%.3f) < clean (%.3f)', noisy, clean))
end)

Test.it('raising min_conf rejects a detection that passes at the default', function()
    local sig = function(n)
        return mix(make_tone(220, SR, n, 12), scale(make_noise(n, 55), 0.5))
    end
    local p_default = detect(sig, 30)
    local p_strict  = detect(sig, 30, nil, nil, 0.99)
    Test.expect(p_default ~= nil, 'should detect at the default gate')
    Test.expect(p_strict == nil, 'should reject at min_conf 0.99')
end)

Test.it('min_conf defaults to 0.5 when omitted', function()
    local sig = function(n) return make_tone(220, SR, n, 12) end
    Test.expect(detect(sig, 30) == detect(sig, 30, nil, nil, 0.5),
        'omitting min_conf must behave as 0.5')
end)

Test.it('confidence ignores level, so it cannot gate quiet audio', function()
    -- CMND is amplitude-normalized. This is why DetectPitchYIN needs a
    -- separate RMS gate: quiet instrument bleed in a gap between phrases
    -- scores just as confident as the vocal, and only a level gate rejects it.
    local _, loud  = detect(function(n) return make_tone(220, SR, n, 12) end, 30)
    local _, faint = detect(function(n)
        return scale(make_tone(220, SR, n, 12), 0.0001)
    end, 30)
    Test.expect(faint ~= nil, 'a very quiet tone still detects')
    Test.expect(math.abs(faint - loud) < 0.01, string.format(
        'confidence must be level-invariant: loud %.4f vs faint %.4f', loud, faint))
end)

----------------------------------------------------------------------
-- High-pass before detection. Low-frequency contamination (rumble, plosives,
-- bass bleed) sits below the searched pitch range but still dominates the
-- difference function, so windows fail the confidence gate and silently fall
-- back to the default pitch.
----------------------------------------------------------------------

-- Same 2-pole one-pole cascade ReadMonoWindow applies, for testing the effect
-- on a generated buffer without an audio accessor.
local function highpass(mono, sr, fc)
    local a = (1 / (2 * math.pi * fc)) / ((1 / (2 * math.pi * fc)) + 1 / sr)
    local out = {}
    for i = 1, #mono do out[i] = mono[i] end
    for _ = 1, 2 do
        local prev_x, prev_y = out[1], 0
        for i = 1, #out do
            local x = out[i]
            prev_y = a * (prev_y + x - prev_x)
            prev_x = x
            out[i] = prev_y
        end
    end
    return out
end

local function make_rumble(freq, sr, n_samps, amp)
    local mono = {}
    for i = 1, n_samps do
        local t = (i - 1) / sr
        mono[i] = amp * math.sin(2 * math.pi * freq * t)
                + amp * 0.5 * math.sin(2 * math.pi * freq * 1.5 * t + 0.7)
    end
    return mono
end

Test.section('YIN core - high-pass')

Test.it('high-pass is load-bearing: rumble blocks A2, filtering recovers it', function()
    -- 110 Hz (A2, low male) under 45 Hz rumble. Without filtering the window
    -- fails the confidence gate entirely, so the note would silently take the
    -- default pitch rather than a wrong one.
    local sig = function(n)
        return mix(make_tone(110, SR, n, 16), make_rumble(45, SR, n, 0.5))
    end
    local raw      = detect(sig, 30)
    local filtered = detect(function(n) return highpass(sig(n), SR, MIN_HZ) end, 30)
    Test.expect(raw == nil, 'unfiltered rumble should defeat detection, got ' .. tostring(raw))
    Test.expect(filtered == 45, 'expected MIDI 45 after high-pass, got ' .. tostring(filtered))
end)

Test.it('high-pass does not disturb a clean low note', function()
    -- E2 is only just above the 80 Hz cutoff, the worst case for the filter.
    local p = detect(function(n)
        return highpass(make_tone(82.4, SR, n, 20), SR, MIN_HZ)
    end, 30)
    Test.expect(p == 40, 'expected MIDI 40, got ' .. tostring(p))
end)

Test.it('high-pass does not disturb a clean mid note', function()
    local p = detect(function(n)
        return highpass(make_tone(220, SR, n, 12), SR, MIN_HZ)
    end, 30)
    Test.expect(p == 57, 'expected MIDI 57, got ' .. tostring(p))
end)

----------------------------------------------------------------------
-- MedianVote: the decision half of multi-window sampling. Pure, so it is
-- tested directly; the sampling half needs an audio accessor.
----------------------------------------------------------------------

Test.section('MedianVote')

Test.it('no votes returns nil', function()
    Test.expect(MedianVote({}, {}) == nil, 'empty vote list → nil')
end)

Test.it('a single vote is returned as-is with its confidence', function()
    local p, c = MedianVote({ 57 }, { 0.9 })
    Test.expect(p == 57, 'expected 57, got ' .. tostring(p))
    Test.expect(math.abs(c - 0.9) < 1e-9, 'confidence passed through')
end)

Test.it('one octave-error vote is outvoted by two agreeing votes', function()
    -- The whole point of the median: 45 is an octave below 57.
    Test.expect(MedianVote({ 57, 45, 57 }, { 0.9, 0.8, 0.9 }) == 57,
        'two agreeing votes must beat one outlier')
end)

Test.it('outlier position does not matter', function()
    Test.expect(MedianVote({ 45, 57, 57 }, { 0.8, 0.9, 0.9 }) == 57, 'outlier first')
    Test.expect(MedianVote({ 57, 57, 45 }, { 0.9, 0.9, 0.8 }) == 57, 'outlier last')
end)

Test.it('returns the best confidence among votes matching the median', function()
    -- 0.95 belongs to the outlier and must not be reported as the winner's.
    local p, c = MedianVote({ 57, 45, 57 }, { 0.70, 0.95, 0.88 })
    Test.expect(p == 57, 'median is 57')
    Test.expect(math.abs(c - 0.88) < 1e-9,
        'expected 0.88 (best among the 57s), got ' .. tostring(c))
end)

Test.it('three different votes take the middle one', function()
    Test.expect(MedianVote({ 45, 57, 69 }, { 0.8, 0.8, 0.8 }) == 57,
        'median of three distinct values')
end)

Test.it('an even count rounds up between the two middles', function()
    Test.expect(MedianVote({ 57, 58 }, { 0.8, 0.8 }) == 58,
        'median of 57 and 58 rounds to 58')
end)

Test.it('does not mutate the caller\'s vote list', function()
    local votes = { 69, 45, 57 }
    MedianVote(votes, { 0.8, 0.8, 0.8 })
    Test.expect(votes[1] == 69 and votes[2] == 45 and votes[3] == 57,
        'input order must be preserved for the confidence lookup')
end)
