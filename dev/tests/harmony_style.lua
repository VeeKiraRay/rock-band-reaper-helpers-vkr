-- Unit tests for lib/reaper_harmony_style.lua - harmony style between a lead line and a
-- harmony line. Pure; no REAPER objects.

-- Notes from { pitch, length in QN } pairs played one after another from `start`.
local function Line(seq, start)
    local out, qn = {}, start or 0
    for _, x in ipairs(seq) do
        if x[1] then out[#out + 1] = { pitch = x[1], qn = qn, len = x[2] } end
        qn = qn + x[2]
    end
    return out
end

-- The same rhythm, each pitch moved by f(pitch).
local function Map(notes, f)
    local out = {}
    for i, n in ipairs(notes) do out[i] = { pitch = f(n.pitch), qn = n.qn, len = n.len } end
    return out
end

local C_MAJOR = { [0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true }

-- A diatonic 3rd above in C major: the next scale tone but one.
local function Diatonic3rdUp(p)
    local steps = 0
    local q = p
    while steps < 2 do
        q = q + 1
        if C_MAJOR[q % 12] then steps = steps + 1 end
    end
    return q
end

-- C D E F G A G E, quarter notes.
local LEAD = Line({ { 60, 1 }, { 62, 1 }, { 64, 1 }, { 65, 1 }, { 67, 1 }, { 69, 1 }, { 67, 1 }, { 64, 1 } })

local function Classify(lead, harm) return HarmonyClassify(HarmonyPairStats(lead, harm)) end

Test.section('Harmony style - interval names')

Test.it('names intervals with direction and octaves', function()
    Test.expect(HarmonyIntervalName(0) == 'unison', 'unison')
    Test.expect(HarmonyIntervalName(3) == '3rd above', HarmonyIntervalName(3))
    Test.expect(HarmonyIntervalName(4) == '3rd above', HarmonyIntervalName(4))
    Test.expect(HarmonyIntervalName(-7) == '5th below', HarmonyIntervalName(-7))
    Test.expect(HarmonyIntervalName(12) == 'octave above', HarmonyIntervalName(12))
    Test.expect(HarmonyIntervalName(-24) == '2 octaves below', HarmonyIntervalName(-24))
    Test.expect(HarmonyIntervalName(16) == '3rd + octave above', HarmonyIntervalName(16))
end)

Test.section('Harmony style - spacing and parallel motion')

Test.it('a copy of the lead is homophonic unison', function()
    local c = Classify(LEAD, Map(LEAD, function(p) return p end))
    Test.expect(c.rhythm == 'homophonic', c.rhythm)
    Test.expect(c.spacing == 'unison', c.spacing)
    Test.expect(c.parallel == nil, 'unison is not reported as parallel')
end)

Test.it('an octave below is octave, named below', function()
    local c = Classify(LEAD, Map(LEAD, function(p) return p - 12 end))
    Test.expect(c.spacing == 'octave', c.spacing)
    Test.expect(c.label == 'homophonic, octave below', c.label)
end)

Test.it('a fixed 5th above is parallel exact', function()
    local c = Classify(LEAD, Map(LEAD, function(p) return p + 7 end))
    Test.expect(c.spacing == 'close', c.spacing)
    Test.expect(c.parallel and c.parallel.kind == 'exact', 'exact')
    Test.expect(c.parallel.name == '5th above', c.parallel.name)
end)

Test.it('diatonic 3rds above are parallel by scale step', function()
    local s = HarmonyPairStats(LEAD, Map(LEAD, Diatonic3rdUp))
    local c = HarmonyClassify(s)
    Test.expect(c.parallel and c.parallel.kind == 'scale', c.label)
    Test.expect(c.parallel.name == '3rd above', c.parallel.name)
    Test.expect(s.motion.parallel_scale > 0, 'major/minor 3rd changes counted')
    Test.expect(s.motion.contrary == 0, 'no contrary steps')
end)

Test.it('a 10th above is open spacing', function()
    local c = Classify(LEAD, Map(LEAD, function(p) return p + 16 end))
    Test.expect(c.spacing == 'open', c.spacing)
end)

Test.it('seconds a third of the time is a cluster', function()
    local harm = Map(LEAD, function(p) return p + 4 end)
    harm[1].pitch = LEAD[1].pitch + 2
    harm[2].pitch = LEAD[2].pitch + 1
    harm[3].pitch = LEAD[3].pitch + 2
    local c = Classify(LEAD, harm)
    Test.expect(c.spacing == 'cluster', c.spacing)
end)

Test.section('Harmony style - rhythm')

Test.it('a held note under a moving lead is decorative', function()
    -- Two whole-bar "ooh"s under eight quarter notes.
    local harm = Line({ { 55, 4 }, { 57, 4 } })
    local c = Classify(LEAD, harm)
    Test.expect(c.rhythm == 'decorative', c.rhythm)
end)

Test.it('joining only the last words is partial', function()
    local harm = {}
    for i = 6, 8 do harm[#harm + 1] = { pitch = LEAD[i].pitch + 4, qn = LEAD[i].qn, len = LEAD[i].len } end
    -- The harmony's span is the last three notes, so the lead side matches fully there.
    local s = HarmonyPairStats(LEAD, harm)
    Test.expect(s.l_onset_match == 1, 'lead onsets inside the harmony span all matched')
    Test.expect(HarmonyClassify(s).rhythm == 'homophonic', 'joining at the end reads as homophonic')

    -- Same words, but the harmony skips every other lead word inside its span.
    local skip = { LEAD[1], LEAD[3], LEAD[5], LEAD[7] }
    local c = Classify(LEAD, Map(skip, function(p) return p + 4 end))
    Test.expect(c.rhythm == 'partial', c.rhythm)
end)

Test.it('offset rhythm in contrary motion is counter', function()
    -- Eighth notes on the "and"s, moving down while the lead moves up.
    local harm = Line({ { nil, 0.5 }, { 72, 1 }, { 71, 1 }, { 69, 1 }, { 67, 1 }, { 65, 1 },
                        { 64, 1 }, { 62, 1 } })
    local s = HarmonyPairStats(LEAD, harm)
    local c = HarmonyClassify(s)
    Test.expect(c.rhythm == 'counter', c.rhythm)
    Test.expect(s.motion.contrary > 0, 'contrary steps counted')
end)

Test.it('singing after the lead is alone', function()
    local harm = Line({ { 67, 1 }, { 64, 1 }, { 60, 2 } }, 8)
    local c = Classify(LEAD, harm)
    Test.expect(c.rhythm == 'alone', c.rhythm)
    Test.expect(c.spacing == 'none', c.spacing)
end)

Test.it('onsets within a 1/32 note count as together', function()
    local harm = Map(LEAD, function(p) return p + 4 end)
    for _, n in ipairs(harm) do n.qn = n.qn + 0.1 end
    Test.expect(Classify(LEAD, harm).rhythm == 'homophonic', 'small offsets tolerated')
end)

Test.section('Harmony style - best fixed offset')

Test.it('finds the offset a Fixed Copy style would reproduce', function()
    local harm = Map(LEAD, function(p) return p - 5 end)
    harm[8].pitch = harm[8].pitch - 2
    local off, share = HarmonyBestFixedOffset(HarmonyPairStats(LEAD, harm))
    Test.expect(off == -5, tostring(off))
    Test.expect(math.abs(share - 7 / 8) < 1e-9, tostring(share))
end)

Test.it('no harmony notes gives no stats', function()
    Test.expect(HarmonyPairStats(LEAD, {}) == nil, 'nil stats')
    Test.expect(HarmonyClassify(nil) == nil, 'nil class')
end)
