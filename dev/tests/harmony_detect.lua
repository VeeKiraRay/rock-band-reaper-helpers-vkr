-- Unit tests for lib/reaper_harmony_detect.lua - the second voice beside a known lead (the
-- Pitch > Tuner Harmony readout). Pure; synthetic voices, no REAPER objects.

local SR = HARMONY_SR
local N  = HARMONY_FRAME_N

local function Hz(p) return 440 * 2 ^ ((p - 69) / 12) end

-- A sung-like tone: six overtones falling off as 1/k, fixed phases so runs are repeatable.
local function Voice(pitch, amp, phase)
    local f = Hz(pitch)
    local out = {}
    for i = 1, N do
        local t = (i - 1) / SR
        local s = 0
        for k = 1, 6 do s = s + math.sin(2 * math.pi * k * f * t + (phase or 0) * k) / k end
        out[i] = amp * s
    end
    return out
end

local function Mix(...)
    local out = {}
    for i = 1, N do
        local s = 0
        for _, v in ipairs({ ... }) do s = s + v[i] end
        out[i] = s
    end
    return out
end

-- One voted reading from n frames of the same mix (slightly different phases per frame).
local function Reading(lead, harm, scale)
    local v = HarmonyVoteNew()
    for k = 1, 4 do
        local mono = harm and Mix(Voice(lead, 0.3, k), Voice(harm, 0.25, 2 * k)) or Voice(lead, 0.3, k)
        HarmonyVoteAdd(v, HarmonyAnalyseFrame(mono, nil, nil, lead, 0), lead)
    end
    return HarmonyVoteResult(v, lead, scale)
end

Test.section('Harmony detect - frame analysis')

Test.it('finds the lead near its chart note', function()
    local r = HarmonyAnalyseFrame(Voice(60, 0.3), nil, nil, 60, 0)
    Test.expect(r and r.lead_pitch == 60, 'lead C4 heard: ' .. tostring(r and r.lead_pitch))
    Test.expect(r.lead_conf > 0.8, 'clean tone is confident: ' .. tostring(r.lead_conf))
end)

Test.it('a solo lead leaves almost nothing after cancelling', function()
    local r = HarmonyAnalyseFrame(Voice(60, 0.3), nil, nil, 60, 0)
    Test.expect(r.ratio < HARMONY_RATIO, 'ratio ' .. tostring(r.ratio))
    local v = HarmonyVoteNew()
    Test.expect(HarmonyVoteAdd(v, r, 60) == 0, 'no vote from a solo frame')
    Test.expect(HarmonyVoteResult(v, 60) == nil, 'no reading')
end)

Test.it('a second voice leaves a clear residual', function()
    local r = HarmonyAnalyseFrame(Mix(Voice(60, 0.3), Voice(64, 0.25)), nil, nil, 60, 0)
    Test.expect(r.ratio > HARMONY_RATIO, 'ratio ' .. tostring(r.ratio))
end)

Test.it('silence gives no result', function()
    local quiet = {}
    for i = 1, N do quiet[i] = 0 end
    Test.expect(HarmonyAnalyseFrame(quiet, nil, nil, 60, 0) == nil, 'nil for silence')
end)

Test.it('no lead pitch: only the left/right correlation', function()
    local v = Voice(60, 0.3)
    local r = HarmonyAnalyseFrame(v, v, v, nil, 0)
    Test.expect(r and r.ratio == nil and r.p_yin == nil, 'nothing searched without a lead')
    Test.expect(r.corr and r.corr > 0.99, 'identical sides correlate: ' .. tostring(r.corr))
end)

Test.it('left/right correlation drops when the sides differ', function()
    local l, rr = Voice(60, 0.3, 0), Voice(60, 0.3, 1.3)
    local res = HarmonyAnalyseFrame(Mix(l, rr), l, rr, 60, 0)
    Test.expect(res.corr and res.corr < 0.9, 'different sides: ' .. tostring(res.corr))
end)

Test.section('Harmony detect - second voice')

Test.it('a major 3rd above', function()
    local p = Reading(60, 64)
    Test.expect(p == 64, 'E4 over C4: ' .. tostring(p))
end)

Test.it('a 4th below', function()
    local p = Reading(60, 55)
    Test.expect(p == 55, 'G3 under C4: ' .. tostring(p))
end)

Test.it('a minor 6th below', function()
    local p = Reading(64, 56)
    Test.expect(p == 56, 'G#3 under E4: ' .. tostring(p))
end)

Test.it('an octave above is not found (cancelled with the lead)', function()
    local p = Reading(60, 72)
    Test.expect(p ~= 72, 'C5 over C4 cannot be read: ' .. tostring(p))
end)

Test.it('agreement is the winning share of the votes', function()
    local v = HarmonyVoteNew()
    local function frame(p) return { ratio = 1, p_yin = p, c_yin = 0.9, p_short = p, c_short = 0.9 } end
    HarmonyVoteAdd(v, frame(64), 60)
    HarmonyVoteAdd(v, frame(64), 60)
    HarmonyVoteAdd(v, frame(67), 60)
    HarmonyVoteAdd(v, frame(64), 60)
    local p, agree = HarmonyVoteResult(v, 60)
    Test.expect(p == 64, tostring(p))
    Test.expect(math.abs(agree - 0.75) < 1e-9, tostring(agree))
end)

Test.it('weak candidates and the lead pitch do not vote', function()
    local v = HarmonyVoteNew()
    Test.expect(HarmonyVoteAdd(v, { ratio = 1, p_yin = 64, c_yin = HARMONY_FLOOR - 0.01 }, 60) == 0, 'under the floor')
    Test.expect(HarmonyVoteAdd(v, { ratio = 1, p_yin = 60, c_yin = 0.9 }, 60) == 0, 'the lead itself')
    Test.expect(HarmonyVoteAdd(v, { ratio = HARMONY_RATIO, p_yin = 64, c_yin = 0.9 }, 60) == 0, 'ratio not above')
    Test.expect(v.frames == 3 and v.n == 0, 'frames counted, no votes')
end)

Test.section('Harmony detect - key snap')

Test.it('scales', function()
    local cmaj = HarmonyScale(0, false)
    Test.expect(cmaj[0] and cmaj[4] and cmaj[11] and not cmaj[1] and not cmaj[10], 'C major')
    local amin = HarmonyScale(9, true)
    Test.expect(amin[9] and amin[0] and amin[7] and not amin[8], 'A natural minor')
end)

Test.it('outside the key with no vote for either neighbour: unchanged', function()
    -- In a major or minor key both neighbours of an outside note are in the key, so the
    -- snap needs votes to choose; a tie leaves the reading alone (as measured).
    local v = HarmonyVoteNew()
    HarmonyVoteAdd(v, { ratio = 1, p_yin = 63, c_yin = 0.9 }, 60)   -- D#4, outside C major
    Test.expect(HarmonyVoteResult(v, 60, HarmonyScale(0, false)) == 63, 'tie: D#4 kept')
    Test.expect(HarmonyVoteResult(v, 60, nil) == 63, 'no scale: unchanged')
end)

Test.it('the neighbour with more votes wins the snap', function()
    local v = HarmonyVoteNew()
    for _ = 1, 3 do HarmonyVoteAdd(v, { ratio = 1, p_yin = 63, c_yin = 0.9 }, 60) end
    HarmonyVoteAdd(v, { ratio = 1, p_yin = 64, c_yin = 0.9 }, 60)
    Test.expect(HarmonyVoteResult(v, 60, HarmonyScale(0, false)) == 64, 'E4 had a vote, D4 none')
end)

Test.section('Harmony detect - spectral reading')

-- The same sung-like tone over the spectral window's HARMONY_SPEC_N samples.
local function SpecVoice(pitch, amp, phase)
    local f = Hz(pitch)
    local out = {}
    for i = 1, HARMONY_SPEC_N do
        local t = (i - 1) / SR
        local s = 0
        for k = 1, 6 do s = s + math.sin(2 * math.pi * k * f * t + (phase or 0) * k) / k end
        out[i] = amp * s
    end
    return out
end
local function SpecMix(a, b)
    local out = {}
    for i = 1, HARMONY_SPEC_N do out[i] = a[i] + b[i] end
    return out
end

Test.it('a major 3rd above', function()
    local p = HarmonySpectralPitch(SpecMix(SpecVoice(60, 0.3), SpecVoice(64, 0.25, 1)), 60, 0)
    Test.expect(p == 64, 'E4 over C4: ' .. tostring(p))
end)

Test.it('a 4th below', function()
    local p = HarmonySpectralPitch(SpecMix(SpecVoice(60, 0.3), SpecVoice(55, 0.25, 1)), 60, 0)
    Test.expect(p == 55, 'G3 under C4: ' .. tostring(p))
end)

Test.it('silence gives no reading', function()
    local quiet = {}
    for i = 1, HARMONY_SPEC_N do quiet[i] = 0 end
    Test.expect(HarmonySpectralPitch(quiet, 60, 0) == nil, 'nil for silence')
end)

Test.it('spectral votes join the vote; the lead pitch does not', function()
    local v = HarmonyVoteNew()
    Test.expect(HarmonyVoteAddPitch(v, 60, 60) == 0, 'the lead itself')
    Test.expect(HarmonyVoteAddPitch(v, nil, 60) == 0, 'no reading')
    Test.expect(HarmonyVoteAddPitch(v, 64, 60) == 1, 'a second voice')
    HarmonyVoteAdd(v, { ratio = 1, p_yin = 64, c_yin = 0.9 }, 60)
    local p, agree = HarmonyVoteResult(v, 60)
    Test.expect(p == 64 and agree == 1, tostring(p) .. ' ' .. tostring(agree))
    Test.expect(v.frames == 1 and v.n == 2, 'spectral votes are not frames')
end)
