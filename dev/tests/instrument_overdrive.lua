-- Tests for the Overdrive tab (overdrive_*.lua, actions_overdrive*.lua).
--
-- Most of these drive the planners and the validator with HAND-BUILT song models -
-- the same table shape OdBuildModel returns - so the exact bars, spans and phrases are
-- known and no project state is involved. Everything is in quarter notes. The last
-- section builds real tracks and runs GenerateOverdrive / ValidateOverdrive end to end.

----------------------------------------------------------------------
-- Building models
----------------------------------------------------------------------

-- n bars of num/den from quarter note 0.
local function MkBars(n, num, den)
    num, den = num or 4, den or 4
    local bars, q, len = {}, 0, num * 4 / den
    for i = 1, n do
        bars[i] = { qn_s = q, qn_e = q + len, t_s = q * 0.5, num = num, den = den,
                    beats = OdCountedBeats(num, den) }
        q = q + len
    end
    return bars
end

-- A gem on every beat of the chosen bars (`which` is 'all' or a set of bar indexes).
-- pat(b, k) gives the pitches of beat k in bar b.
local function MkEvents(bars, which, pat)
    local evs = {}
    for b, bar in ipairs(bars) do
        if which == 'all' or which[b] then
            local k, q = 0, bar.qn_s
            while q < bar.qn_e - 1e-9 do
                k = k + 1
                evs[#evs + 1] = { qn = q, qn_e = q + 0.25,
                                  pitches = pat and pat(b, k) or { 96 + (b + k) % 3 } }
                q = q + 1
            end
        end
    end
    return evs
end

-- parts: { guitar = 'all' | set, ... }; parts left out are absent from the song.
local function MkModel(n_bars, parts, extra)
    local bars = MkBars(n_bars)
    local model = { bars = bars, inst = {}, sections = {}, fills = {}, rolls = {},
                    drum_solos = {}, end_qn = bars[#bars].qn_e, has_end_event = true }
    for _, g in ipairs(OD_INST_GROUPS) do
        local which = parts[g.key]
        model.inst[g.key] = { key = g.key, label = g.label, group = g,
                              present = which ~= nil,
                              events = which and MkEvents(bars, which) or {}, od = {} }
    end
    for k, v in pairs(extra or {}) do model[k] = v end
    OdFinishModel(model)
    return model
end

local function Range(a, z)
    local set = {}
    for b = a, z do set[b] = true end
    return set
end

local ALL4 = { guitar = 'all', bass = 'all', drums = 'all', keys = 'all' }
local STD = { beats_per_phrase = 40, unison_share = 0.5, keepout_od = 8, keepout_unison = 12 }

local function PlanAll(model, nogo, fills)
    return OdPlanInstruments(model, {
        gen = { guitar = true, bass = true, drums = true, keys = true },
        beats_per_phrase = 40, unison_share = 0.5, keepout_od = 8, keepout_unison = 12,
        nogo = nogo or {}, fills = fills or {} })
end

----------------------------------------------------------------------
Test.section('Counted beats')
----------------------------------------------------------------------

Test.it('counts the doc\'s beats, not quarter notes', function()
    Test.expect(OdCountedBeats(4, 4) == 4, '4/4')
    Test.expect(OdCountedBeats(3, 4) == 3, '3/4')
    Test.expect(OdCountedBeats(7, 8) == 3, '7/8 is counted 1-2, 1-2, 1-2-3')
    Test.expect(OdCountedBeats(6, 8) == 2, '6/8 counts its dotted pulse')
    Test.expect(OdCountedBeats(12, 8) == 4, '12/8')
    Test.expect(OdCountedBeats(5, 8) == 2, '5/8')
end)

----------------------------------------------------------------------
Test.section('Bar interest')
----------------------------------------------------------------------

Test.it('a bar of changing shapes beats a bar of one repeated chord', function()
    local bars = MkBars(2)
    local evs = {}
    for i = 0, 7 do   -- bar 1: the same power chord on every eighth
        evs[#evs + 1] = { qn = i * 0.5, qn_e = i * 0.5 + 0.25, pitches = { 96, 98 } }
    end
    for i = 0, 7 do   -- bar 2: the chord with single palm-muted notes threaded between
        local p = (i % 2 == 0) and { 96, 98 } or { 96 + (i % 3) }
        evs[#evs + 1] = { qn = 4 + i * 0.5, qn_e = 4 + i * 0.5 + 0.25, pitches = p }
    end
    local score = OdBarInterest(bars, evs, {})
    Test.expect(score[2] > score[1], ('changing %.3f vs repeated %.3f'):format(score[2], score[1]))
end)

Test.it('a bar with no gems gets no score', function()
    local bars = MkBars(3)
    local score = OdBarInterest(bars, MkEvents(bars, { [1] = true, [3] = true }), {})
    Test.expect(score[2] == nil, 'resting bar scored')
end)

----------------------------------------------------------------------
Test.section('Vocal planner')
----------------------------------------------------------------------

-- 24 two-bar phrases in 60 bars; phrase i covers bars 2i-1..2i (short of the barline).
-- All of them end by bar 48, before the 8-bar keep-out starts at bar 53.
local function VocalModel(harm_mismatch)
    local model = MkModel(60, {})
    local phrases = {}
    for i = 1, 24 do
        local s, e = model.bars[2 * i - 1].qn_s, model.bars[2 * i].qn_e - 0.5
        local ph = { s = s, e = e, has_notes = true }
        if not (harm_mismatch and harm_mismatch[i]) then ph.harm = { s = s, e = e } end
        phrases[i] = ph
    end
    model.vocal = { present = true, harm_present = true, phrases = phrases, od = {},
                    harm_od = {}, harm_phrases = {} }
    return model, phrases
end

local function Index(phrases, list)
    local out = {}
    for _, ph in ipairs(list) do
        for i, p in ipairs(phrases) do if p == ph then out[#out + 1] = i end end
    end
    return table.concat(out, ',')
end

Test.it('picks every 5th sung phrase, starting mid-cycle', function()
    local model, phrases = VocalModel()
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(Index(phrases, plan.phrases) == '3,8,13,18,23', Index(phrases, plan.phrases))
    Test.expect(#plan.unplaced == 0, 'nothing unplaced')
end)

Test.it('leaves room for the overdrive before the vocals\' own last note', function()
    -- The last note is phrase 24's first, half a beat after phrase 23 ends: phrase 23
    -- has no room for its 8 beats, so the cadence ends at 18 - not on 23, and with
    -- nothing reported unplaced. No BEAT track: quarter notes.
    local model, phrases = VocalModel()
    local sung = {}
    for i = 1, 24 do sung[#sung + 1] = { qn = phrases[i].s, qn_e = phrases[i].s + 1 } end
    model.vocal.sung = sung
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8, beats = {} })
    Test.expect(Index(phrases, plan.phrases) == '3,8,13,18', Index(phrases, plan.phrases))
    Test.expect(#plan.unplaced == 0, #plan.unplaced .. ' unplaced')
end)

Test.it('"Count long breaks": 10 bars without singing count as one phrase', function()
    -- Phrases 1-8 in bars 1-16, a 20-bar break, phrases 9-24 from bar 37.
    local model = MkModel(90, {})
    local phrases = {}
    for i = 1, 24 do
        local b = (i <= 8) and (2 * i - 1) or (2 * i - 1 + 20)
        local s, e = model.bars[b].qn_s, model.bars[b + 1].qn_e - 0.5
        phrases[i] = { s = s, e = e, has_notes = true, harm = { s = s, e = e } }
    end
    model.vocal = { present = true, harm_present = true, phrases = phrases, od = {},
                    harm_od = {}, harm_phrases = {} }
    local off = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(Index(phrases, off.phrases) == '3,8,13,18,23', 'off: ' .. Index(phrases, off.phrases))
    -- On: the break counts 2, so after phrase 8 the next is 3 sung phrases later.
    local on = OdPlanVocals(model, { every = 5, keepout_od = 8, break_bars = 10 })
    Test.expect(Index(phrases, on.phrases) == '3,8,11,16,21', 'on: ' .. Index(phrases, on.phrases))
    -- A 40-bar break counts 4: the next would be the very next phrase - one is kept between.
    local on4 = OdPlanVocals(model, { every = 5, keepout_od = 8, break_bars = 5 })
    for k = 2, #on4.phrases do
        local a, b
        for i, p in ipairs(phrases) do
            if p == on4.phrases[k - 1] then a = i end
            if p == on4.phrases[k] then b = i end
        end
        Test.expect(b - a >= 2, ('adjacent overdrive phrases %d and %d'):format(a, b))
    end
end)

Test.it('moves one phrase earlier when HARM1 differs there', function()
    local model, phrases = VocalModel({ [8] = true })
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(Index(phrases, plan.phrases) == '3,7,12,17,22', Index(phrases, plan.phrases))
end)

Test.it('moves one phrase later when the earlier one differs too', function()
    local model, phrases = VocalModel({ [7] = true, [8] = true })
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(Index(phrases, plan.phrases) == '3,9,14,19,24', Index(phrases, plan.phrases))
end)

Test.it('reports the slot when neither neighbour matches HARM1', function()
    local model, phrases = VocalModel({ [7] = true, [8] = true, [9] = true })
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(#plan.unplaced == 1 and plan.unplaced[1] == phrases[8], 'phrase 8 reported')
    Test.expect(Index(phrases, plan.phrases) == '3,13,18,23', Index(phrases, plan.phrases))
end)

Test.it('without HARM1 every phrase is eligible', function()
    local model, phrases = VocalModel({ [8] = true })
    model.vocal.harm_present = false
    local plan = OdPlanVocals(model, { every = 5, keepout_od = 8 })
    Test.expect(Index(phrases, plan.phrases) == '3,8,13,18,23', Index(phrases, plan.phrases))
end)

----------------------------------------------------------------------
Test.section('Fill planner')
----------------------------------------------------------------------

Test.it('one bar every 4, ending on barlines', function()
    local model = MkModel(40, { drums = 'all' })
    local plan = OdPlanFills(model, { pacing = 2, align = false, drum_od = {} })
    Test.expect(#plan.fills == 9, 'count ' .. #plan.fills)   -- ends at bars 5, 9, ... 37
    for _, f in ipairs(plan.fills) do
        Test.expect(OdBarStartingAt(model.bars, f.e) ~= nil, 'fill end off the barline')
        Test.expect(math.abs((f.e - f.s) - 4) < 1e-6, 'fill is not one bar')
    end
    Test.expect(plan.fills[1].bar == 5, 'first fill should land on bar 5')
end)

-- The doc's example: a verse with two extra bars gets its fill into the chorus
-- rather than keeping to the grid, so the fill that would have ended at bar 9
-- ends at the section start on bar 11 instead, and the grid continues from there.
Test.it('ends a fill at a nearby section change', function()
    local model = MkModel(40, { drums = 'all' },
        { sections = { { name = 'chorus_1', s = MkBars(40)[11].qn_s, bar = 11 } } })
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends = {}
    for _, f in ipairs(plan.fills) do ends[#ends + 1] = f.bar end
    Test.expect(table.concat(ends, ','):find('^5,11,15,19,') ~= nil, table.concat(ends, ','))
end)

-- Drums with a green crash on the downbeat of the chosen bars and hi-hat elsewhere.
local function CrashModel(n, crash_at, extra)
    local model = MkModel(n, { drums = 'all' }, extra)
    model.inst.drums.events = MkEvents(model.bars, 'all', function(b, k)
        if k == 1 and crash_at[b] then return { 96, 100 } end
        return { 98 }
    end)
    OdFinishModel(model)
    return model
end

-- Phrases start with a crash every 4 bars from bar 5.
local function EveryFourth()
    local crash = {}
    for b = 5, 57, 4 do crash[b] = true end
    return crash
end

Test.it('a section start wins over a crash, and a crash beside it is reported', function()
    -- The section event sits at 12, a measure before the crash at 13 - the case where
    -- the section event followed the vocals. Sections come first (they match official
    -- fill positions far more often), but the mismatch is flagged in the report.
    local bars = MkBars(60)
    local model = CrashModel(60, EveryFourth(),
        { sections = { { name = 'outro_chorus_a', s = bars[12].qn_s, bar = 12 } } })
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends, flagged = {}, nil
    for _, f in ipairs(plan.fills) do
        ends[#ends + 1] = f.bar
        if f.crash_near then flagged = f end
    end
    local list = table.concat(ends, ',')
    -- Bar 12 is only 3 bars after the fill into bar 9, so that fill gives way. The next
    -- one moves to the crash at 17, the nearest at least 4 bars on.
    Test.expect(list:find('^5,12,17,') ~= nil, list)
    Test.expect(flagged and flagged.bar == 12 and flagged.crash_near == 13, 'crash at 13 not reported')
end)

Test.it('section family drops a trailing number, number + letter, or letter', function()
    local cases = {
        chorus_1 = 'chorus', chorus_1a = 'chorus', chorus_12b = 'chorus', intro_a = 'intro',
        gtr_solo_2a = 'gtr_solo', gtr_solo = 'gtr_solo', gtr_break = 'gtr_break',
        outro_chorus_a = 'outro_chorus', bre = 'bre', ['1a'] = '1a', main_riff = 'main_riff',
    }
    for name, want in pairs(cases) do
        local got = OdSectionFamily(name)
        Test.expect(got == want, ('%s -> %s, want %s'):format(name, got, want))
    end
end)

Test.it('a practice subsection does not pull a fill', function()
    local bars = MkBars(40)
    local model = MkModel(40, { drums = 'all' }, { sections = {
        { name = 'verse_1',   s = bars[3].qn_s,  bar = 3 },
        { name = 'chorus_1a', s = bars[11].qn_s, bar = 11 },
        { name = 'chorus_1b', s = bars[15].qn_s, bar = 15 },
        { name = 'chorus_2',  s = bars[18].qn_s, bar = 18 },   -- same section, renumbered
    } })
    Test.expect(model.section_bars[15] and not model.section_change_bars[15], 'subsection read as a change')
    Test.expect(not model.section_change_bars[18], 'chorus_1b -> chorus_2 read as a change')
    local ends = {}
    for _, f in ipairs(OdPlanFills(model, { pacing = 2, align = true, drum_od = {} }).fills) do
        ends[#ends + 1] = f.bar
    end
    -- 3 (section), 7, 11 (section), 15, 19 ... - not pulled to 18.
    local list = table.concat(ends, ',')
    Test.expect(list:find('^3,7,11,15,19,') ~= nil, list)
end)

Test.it('a subsection lines a fill up at the full pacing, never earlier', function()
    local bars = MkBars(40)
    local model = MkModel(40, { drums = 'all' }, { sections = {
        { name = 'verse_1a', s = bars[1].qn_s,  bar = 1 },
        { name = 'verse_1b', s = bars[8].qn_s,  bar = 8 },    -- 3 bars after the fill at 5: ignored
        { name = 'verse_1c', s = bars[14].qn_s, bar = 14 },   -- 5 bars after the fill at 9: used
    } })
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends = {}
    for _, f in ipairs(plan.fills) do ends[#ends + 1] = f.bar end
    local list = table.concat(ends, ',')
    Test.expect(list:find('^5,9,14,18,') ~= nil, list)
    Test.expect((plan.skipped['gave way to a fill into a section change'] or 0) == 0, 'a subsection replaced a fill')
end)

Test.it('a section right after a section fill gets none; the pacing is a minimum', function()
    local bars = MkBars(40)
    local model = MkModel(40, { drums = 'all' }, { sections = {
        { name = 'prechorus_1', s = bars[9].qn_s,  bar = 9 },
        { name = 'chorus_1',    s = bars[11].qn_s, bar = 11 },
    } })
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends = {}
    for _, f in ipairs(plan.fills) do ends[#ends + 1] = f.bar end
    local list = table.concat(ends, ',')
    Test.expect(list:find('^5,9,13,') ~= nil, list)
    for i = 2, #plan.fills do
        Test.expect(plan.fills[i].bar - plan.fills[i - 1].bar >= 4, 'fills closer than 4 bars: ' .. list)
    end
end)

Test.it('the replaced fill is counted, and the fill before it stays', function()
    local bars = MkBars(40)
    local model = MkModel(40, { drums = 'all' },
        { sections = { { name = 'chorus_1', s = bars[16].qn_s, bar = 16 } } })
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends = {}
    for _, f in ipairs(plan.fills) do ends[#ends + 1] = f.bar end
    -- Grid 5, 9, 13; the chorus at 16 replaces 13 (3 bars before it): 9 -> 16 is 7 bars.
    local list = table.concat(ends, ',')
    Test.expect(list:find('^5,9,16,20,') ~= nil, list)
    Test.expect((plan.skipped['gave way to a fill into a section change'] or 0) == 1, 'replacement not counted')
end)

-- Bars at a fixed tempo: MkBars' start times are 120 BPM.
local function AtBpm(model, bpm)
    for _, b in ipairs(model.bars) do b.t_s = b.qn_s * 60 / bpm end
    return model
end

Test.it('no fill starts under 2.5 s after the previous one ends (Magma)', function()
    -- Half a bar every 2 at 193 BPM leaves 6 QN = 1.87 s between fills.
    local model = AtBpm(MkModel(40, { drums = 'all' }), 193)
    local plan = OdPlanFills(model, { pacing = 1, align = false, drum_od = {} })
    Test.expect(#plan.fills > 0, 'no fills at all')
    for i = 2, #plan.fills do
        local gap = OdQNToSec(model.bars, plan.fills[i].s) - OdQNToSec(model.bars, plan.fills[i - 1].e)
        Test.expect(gap >= OD_FILL_MIN_GAP_SEC - 1e-3, ('gap %.2f s before bar %d'):format(gap, plan.fills[i].bar))
    end
    Test.expect((plan.skipped['under 2.5 s after the previous fill'] or 0) > 0, 'skip not counted')
end)

Test.it('Auto pacing: one bar every 4 at fast tempos, half a bar only when very slow', function()
    Test.expect(OdAutoFillPacing(193) == 2, 'fast song')
    Test.expect(OdAutoFillPacing(120) == 2, 'mid tempo')
    Test.expect(OdAutoFillPacing(70) == 1, 'slow song')
end)

Test.it('with no section in reach, a fill moves to a nearby crash', function()
    -- Crashes every 4 bars from 5, but one phrase runs 5 bars: crash at 14, not 13.
    local crash = EveryFourth()
    crash[13] = nil
    crash[14] = true
    local model = CrashModel(60, crash)
    local plan = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} })
    local ends = {}
    for _, f in ipairs(plan.fills) do ends[#ends + 1] = f.bar end
    Test.expect(table.concat(ends, ','):find('^5,9,14,') ~= nil, table.concat(ends, ','))
end)

Test.it('a section start the drums mark is not reported', function()
    local bars = MkBars(60)
    local model = CrashModel(60, EveryFourth(),
        { sections = { { name = 'chorus_1', s = bars[13].qn_s, bar = 13 } } })
    for _, f in ipairs(OdPlanFills(model, { pacing = 2, align = true, drum_od = {} }).fills) do
        Test.expect(not f.crash_near, 'reported a section the drums confirm, at ' .. f.bar)
    end
end)

Test.it('a green gem under a tom marker is not a crash', function()
    local bars = MkBars(20)
    local model = CrashModel(20, { [13] = true },
        { tom_markers = { [100] = { { s = bars[13].qn_s, e = bars[13].qn_e } } } })
    Test.expect(not model.crash_bars[13], 'tom read as a crash')
    local model2 = CrashModel(20, { [13] = true })
    Test.expect(model2.crash_bars[13], 'crash not found')
end)

Test.it('activation needs two drum phrases, or one unison', function()
    local one  = { s = 10, e = 14 }
    local two  = { s = 30, e = 34 }
    Test.expect(OdActivationQN({ one, two }) == 34, 'two singles arm at the second')
    Test.expect(OdActivationQN({ { s = 10, e = 14, unison = true }, two }) == 14, 'a unison arms alone')
    Test.expect(OdActivationQN({ one }) == nil, 'one single never arms')
end)

Test.it('fills before activation are split off', function()
    local fills = { { s = 20, e = 24 }, { s = 36, e = 40 }, { s = 52, e = 56 } }
    local kept, early = OdSplitEarlyFills(fills, 34)
    Test.expect(#kept == 2 and #early == 1 and early[1].s == 20, ('%d kept, %d early'):format(#kept, #early))
    local k2, e2 = OdSplitEarlyFills(fills, nil)
    Test.expect(#k2 == 0 and #e2 == 3, 'no activation means every fill is early')
end)

Test.it('a fill too soon after the first activation is split off (Hard highway)', function()
    -- 120 BPM: 1 QN = 0.5 s. Activation at QN 34 (17.0 s).
    local function Sec(qn) return qn * 0.5 end
    local fills = { { s = 20, e = 24 },     -- before activation: early
                    { s = 37, e = 40 },     -- 1.5 s after: too soon on Hard
                    { s = 52, e = 56 } }    -- 9.0 s after: kept
    local kept, early, soon = OdSplitEarlyFills(fills, 34, OD_FILL_GATE_SEC, Sec)
    Test.expect(#kept == 1 and kept[1].s == 52, #kept .. ' kept')
    Test.expect(#early == 1 and early[1].s == 20, #early .. ' early')
    Test.expect(#soon == 1 and soon[1].s == 37, #soon .. ' too soon')
    Test.expect(OD_FILL_GATE_SEC == 1.6, 'gate ' .. OD_FILL_GATE_SEC)
    -- 1.7 s after is fine; without a gate nothing is too soon.
    local k2, _, s2 = OdSplitEarlyFills({ { s = 37.4, e = 40 } }, 34, OD_FILL_GATE_SEC, Sec)
    Test.expect(#k2 == 1 and #s2 == 0, '1.7 s after was dropped')
    local k3, _, s3 = OdSplitEarlyFills(fills, 34)
    Test.expect(#k3 == 2 and #s3 == 0, 'no gate: the old split')
end)

Test.it('skips drum solos and slots next to kept overdrive', function()
    local bars = MkBars(40)
    local model = MkModel(40, { drums = 'all' },
        { drum_solos = { { s = bars[16].qn_s, e = bars[21].qn_e } } })
    local kept = { { s = bars[25].qn_s, e = bars[25].qn_e } }   -- starts on the bar-25 crash
    local plan = OdPlanFills(model, { pacing = 2, align = false, drum_od = kept })
    for _, f in ipairs(plan.fills) do
        Test.expect(not OdSpansOverlap(f.s, f.e, bars[16].qn_s, bars[21].qn_e), 'fill in drum solo')
        Test.expect(f.bar ~= 25, 'fill ends on a kept phrase\'s start')
    end
    Test.expect((plan.skipped['in a drum solo'] or 0) >= 1, 'solo skip counted')
end)

Test.it('end keep-out: no fill leading into the drums\' last measures', function()
    -- Drums play to bar 37; grid fills would end at 5, 9, ... 33, 37.
    local model = MkModel(40, { drums = Range(1, 37) })
    local last = function(keep)
        local plan = OdPlanFills(model, { pacing = 2, align = false, drum_od = {}, keepout_end = keep })
        return plan.fills[#plan.fills].bar, plan
    end
    Test.expect(last(0) == 37, 'keep-out 0 allows a fill into the final measure')
    local b, plan = last(2)
    Test.expect(b == 33, 'keep-out 2: last fill lands at ' .. b)
    Test.expect((plan.skipped['too close to the last drum note'] or 0) == 1, 'skip not counted')
end)

Test.it('never fills into a bar where the drums rest', function()
    local model = MkModel(40, { drums = Range(1, 20) })
    local plan = OdPlanFills(model, { pacing = 2, align = false, drum_od = {} })
    for _, f in ipairs(plan.fills) do Test.expect(f.bar <= 20, 'fill into a rest at ' .. f.bar) end
end)

----------------------------------------------------------------------
Test.section('Instrument planner')
----------------------------------------------------------------------

-- Every bar index where a phrase of `key` starts.
local function BarsOf(plan, key)
    local set = {}
    for _, sp in ipairs(plan.phrases[key] or {}) do set[sp.bar] = sp end
    return set
end

Test.it('hits the frequency target and keeps out of the end', function()
    local model = MkModel(80, ALL4)
    local plan = PlanAll(model)
    for key in pairs(ALL4) do
        -- 72 eligible bars x 4 beats / 40 = 7.2
        Test.expect(plan.targets[key] == 7, key .. ' target ' .. tostring(plan.targets[key]))
        Test.expect(#plan.phrases[key] == 7, key .. ' placed ' .. #plan.phrases[key])
        for _, sp in ipairs(plan.phrases[key]) do
            Test.expect(sp.bar <= 72, key .. ' phrase in the last 8 bars')
            if sp.unison then Test.expect(sp.bar <= 68, 'unison in the last 12 bars') end
        end
    end
end)

Test.it('unisons are identical spans; nothing else shares a bar', function()
    local model = MkModel(80, ALL4)
    local plan = PlanAll(model)
    local by_bar = {}
    for key, list in pairs(plan.phrases) do
        for _, sp in ipairs(list) do
            by_bar[sp.bar] = by_bar[sp.bar] or {}
            by_bar[sp.bar][#by_bar[sp.bar] + 1] = sp
        end
    end
    local unisons = 0
    for b, list in pairs(by_bar) do
        if #list > 1 then
            unisons = unisons + 1
            Test.expect(#list >= 3, ('bar %d shared by %d parts'):format(b, #list))
            for _, sp in ipairs(list) do
                Test.expect(sp.unison and OdSameSpan(sp, list[1]), 'unison spans differ at bar ' .. b)
            end
        end
    end
    Test.expect(unisons == #plan.unison_bars and unisons >= 3, 'unison count ' .. unisons)
end)

Test.it('no instrument phrase touches vocal overdrive', function()
    local model = MkModel(80, ALL4)
    local nogo = {}
    for b = 1, 72, 9 do nogo[#nogo + 1] = { s = model.bars[b].qn_s + 1, e = model.bars[b + 1].qn_e - 1 } end
    local plan = PlanAll(model, nogo)
    for key, list in pairs(plan.phrases) do
        for _, sp in ipairs(list) do
            Test.expect(not OdAnyOverlap(nogo, sp.s, sp.e), key .. ' phrase on vocal overdrive')
            local bar = model.bars[sp.bar]
            Test.expect(not OdAnyOverlap(nogo, bar.qn_s, bar.qn_e), key .. ' phrase in a vocal OD bar')
        end
    end
end)

Test.it('drums and unisons keep out of fill bars and off fill crashes', function()
    local model = MkModel(80, ALL4)
    local fills = OdPlanFills(model, { pacing = 2, align = false, drum_od = {} }).fills
    local plan = PlanAll(model, {}, fills)
    for key, list in pairs(plan.phrases) do
        for _, sp in ipairs(list) do
            if key == 'drums' or sp.unison then
                for _, f in ipairs(fills) do
                    local bar = model.bars[sp.bar]
                    Test.expect(not OdSpansOverlap(f.s, f.e, bar.qn_s, bar.qn_e), key .. ' in a fill bar')
                    Test.expect(not OdSameQN(sp.s, f.e), key .. ' starts on a fill crash')
                    Test.expect(not OdSameQN(sp.e, f.s), key .. ' ends where a fill starts')
                end
            end
        end
    end
end)

Test.it('a unison may leave out keys where keys is resting', function()
    local model = MkModel(80, { guitar = 'all', bass = 'all', drums = 'all', keys = Range(1, 10) })
    local plan = PlanAll(model)
    local keys_bars = BarsOf(plan, 'keys')
    local subset = 0
    for _, b in ipairs(plan.unison_bars) do
        Test.expect(BarsOf(plan, 'guitar')[b] and BarsOf(plan, 'bass')[b] and BarsOf(plan, 'drums')[b],
                    'core instrument missing from unison at bar ' .. b)
        if not keys_bars[b] then subset = subset + 1 end
    end
    Test.expect(subset > 0, 'expected unisons without keys')
end)

Test.it('a single part joins existing unisons and avoids lone phrases', function()
    local model = MkModel(80, ALL4)
    local un = { s = model.bars[30].qn_s, e = model.bars[30].qn_e }
    local lone = { s = model.bars[40].qn_s, e = model.bars[40].qn_e }
    model.inst.guitar.od = { un, lone }
    model.inst.bass.od = { { s = un.s, e = un.e } }
    model.inst.drums.od = { { s = un.s, e = un.e } }
    local plan = OdPlanInstruments(model, {
        gen = { keys = true }, beats_per_phrase = 40, unison_share = 0.5,
        keepout_od = 8, keepout_unison = 12, nogo = {}, fills = {} })
    local kb = BarsOf(plan, 'keys')
    Test.expect(kb[30] and OdSameSpan(kb[30], un), 'keys did not join the unison')
    Test.expect(not kb[40], 'keys paired with a lone guitar phrase')
    Test.expect(plan.unison_mode == 'joined', 'mode ' .. tostring(plan.unison_mode))
end)

Test.it('start keep-out: nothing before the band has played N measures', function()
    -- The band comes in at bar 3 (bars 1-2 are silent count-in), as songs usually do.
    local model = MkModel(80, { guitar = Range(3, 80), bass = Range(3, 80),
                                drums = Range(3, 80), keys = Range(3, 80) })
    local plan = OdPlanInstruments(model, {
        gen = { guitar = true, bass = true, drums = true, keys = true },
        beats_per_phrase = 40, unison_share = 0.5, keepout_od = 8, keepout_unison = 12,
        keepout_start = 5, nogo = {}, fills = {} })
    Test.expect(plan.first_ok == 8, 'first allowed bar ' .. tostring(plan.first_ok))
    local earliest = math.huge
    for key, list in pairs(plan.phrases) do
        Test.expect(#list == plan.targets[key], key .. ' still reaches its target')
        for _, sp in ipairs(list) do earliest = math.min(earliest, sp.bar) end
    end
    Test.expect(earliest >= 8, 'phrase at bar ' .. earliest)
end)

Test.it('start keep-out of 0 allows the first playing measure', function()
    local model = MkModel(80, ALL4)
    local plan = OdPlanInstruments(model, {
        gen = { guitar = true }, beats_per_phrase = 40, unison_share = 0.5,
        keepout_od = 8, keepout_unison = 12, keepout_start = 0, nogo = {}, fills = {} })
    Test.expect(plan.first_ok == 1, 'first allowed bar ' .. tostring(plan.first_ok))
end)

Test.it('vocal overlap modes: avoid, first measure only, anywhere', function()
    local bars = MkBars(20)
    local v = { { s = bars[5].qn_s + 1, e = bars[7].qn_e - 1 } }   -- 3-measure vocal phrase
    local avoid = OdVocalNoGo(bars, v, 0)
    Test.expect(#avoid == 1 and avoid[1] == v[1], 'avoid keeps the whole phrase')
    local first = OdVocalNoGo(bars, v, 1)
    Test.expect(#first == 1 and OdSameQN(first[1].s, bars[5].qn_s) and OdSameQN(first[1].e, bars[5].qn_e),
                'first-measure mode blocks only measure 5')
    Test.expect(#OdVocalNoGo(bars, v, 2) == 0, 'overlap-anywhere blocks nothing')
end)

Test.it('togetherness: guitar and bass moving together outscore unrelated parts', function()
    local bars = MkBars(2)
    local gtr, bass = {}, {}
    for i = 0, 7 do   -- bar 1: GR RY YB BO climbing against G R Y B, on the same eighths
        local k = i % 4
        gtr[#gtr + 1]  = { qn = i * 0.5, qn_e = i * 0.5 + 0.25, pitches = { 96 + k, 97 + k } }
        bass[#bass + 1] = { qn = i * 0.5, qn_e = i * 0.5 + 0.25, pitches = { 96 + k } }
    end
    for i = 0, 7 do   -- bar 2: guitar climbs on eighths, bass falls on the off-beats
        local k = i % 4
        gtr[#gtr + 1]  = { qn = 4 + i * 0.5, qn_e = 4 + i * 0.5 + 0.25, pitches = { 96 + k } }
        bass[#bass + 1] = { qn = 4 + i * 0.5 + 0.25, qn_e = 4 + i * 0.5 + 0.5, pitches = { 99 - k } }
    end
    local t = OdBandTogetherness(bars, gtr, bass, {})
    Test.expect(t[1] and t[2] and t[1] > t[2], ('together %.2f vs apart %.2f'):format(t[1] or -1, t[2] or -1))
end)

Test.it('together: a unison takes the measure before a section; that fill gives way', function()
    local bars = MkBars(80)
    local secs = {}
    for i, b in ipairs({ 21, 41, 61 }) do
        secs[#secs + 1] = { name = ({ 'chorus_1', 'bridge', 'chorus_2' })[i], s = bars[b].qn_s, bar = b }
    end
    local model = MkModel(80, ALL4, { sections = secs })
    local fills = OdPlanFills(model, { pacing = 2, align = true, drum_od = {} }).fills
    local base = { gen = { guitar = true, bass = true, drums = true, keys = true },
                   beats_per_phrase = 40, unison_share = 0.5, keepout_od = 8,
                   keepout_unison = 12, nogo = {}, fills = fills }
    local off = OdPlanInstruments(model, base)
    Test.expect(#off.yielded == 0, 'without together no fill gives way')
    base.together = true
    local on = OdPlanInstruments(model, base)
    Test.expect(#on.yielded >= 1, 'no fill gave way')
    local un = {}
    for _, b in ipairs(on.unison_bars) do un[b] = true end
    for _, f in ipairs(on.yielded) do
        local landing = OdBarStartingAt(model.bars, f.e)
        Test.expect(landing and model.section_change_bars[landing] and un[landing - 1],
                    'yielded fill is not the one before a section with a unison')
    end
    Test.expect(#fills == #OdPlanFills(model, { pacing = 2, align = true, drum_od = {} }).fills,
                'the caller\'s fill list was modified')
end)

Test.it('rests are not counted toward the target', function()
    local model = MkModel(80, { guitar = Range(1, 36) })
    local plan = OdPlanInstruments(model, { gen = { guitar = true }, beats_per_phrase = 40,
        unison_share = 0.5, keepout_od = 8, keepout_unison = 12, nogo = {}, fills = {} })
    Test.expect(plan.targets.guitar == 4, 'target ' .. plan.targets.guitar)   -- 36 x 4 / 40
    for _, sp in ipairs(plan.phrases.guitar) do Test.expect(sp.bar <= 36, 'phrase in a rest') end
end)

Test.it('a part that stops early keeps its overdrive room before its own last note', function()
    -- Keys stop at bars 20-40 while the band plays to bar 80. For every stop point, keys'
    -- last phrase ends at least 8 beats (16 for a unison) before keys' last note.
    local bad, phrases = {}, 0
    for stop = 20, 40, 2 do
        local model = MkModel(80, { guitar = 'all', bass = 'all', drums = 'all', keys = Range(1, stop) })
        local plan = PlanAll(model)
        local last = 0
        for _, ev in ipairs(model.inst.keys.events) do last = math.max(last, ev.qn) end
        local list = plan.phrases.keys
        phrases = phrases + #list
        for _, sp in ipairs(list) do
            local need = 0.251 * 32 * (sp.unison and 2 or 1)
            if last - sp.e < need - 1e-6 then bad[#bad + 1] = ('stop %d: phrase at %.0f'):format(stop, sp.s) end
        end
    end
    Test.expect(phrases > 0, 'setup: keys got no phrases')
    Test.expect(#bad == 0, table.concat(bad, '; '))
end)

Test.it('"Count rests": a rest bar inside the part counts 1 beat toward the spacing', function()
    -- Guitar plays bars 1-20 and 61-100 (240 beats), resting 40 bars in between.
    local function Plan(rest)
        local bars_played = Range(1, 20)
        for b = 61, 100 do bars_played[b] = true end
        local model = MkModel(110, { guitar = bars_played })
        return OdPlanInstruments(model, { gen = { guitar = true }, beats_per_phrase = 40,
            unison_share = 0.5, keepout_od = 8, keepout_unison = 12, nogo = {}, fills = {},
            rest_beats = rest })
    end
    local off, on = Plan(nil), Plan(1)
    Test.expect(off.targets.guitar == 6, 'off target ' .. off.targets.guitar)
    Test.expect(on.targets.guitar == 7, 'on target ' .. on.targets.guitar .. ' (280 beats / 40)')
    Test.expect(#on.phrases.guitar == 7, #on.phrases.guitar .. ' phrases placed')
    for _, sp in ipairs(on.phrases.guitar) do
        Test.expect(sp.bar <= 20 or sp.bar >= 61, 'a phrase in the rest, bar ' .. sp.bar)
    end
end)

Test.it('drum solos hold at most 4 phrases', function()
    local bars = MkBars(200)
    local model = MkModel(200, { drums = 'all' },
        { drum_solos = { { s = bars[20].qn_s, e = bars[120].qn_e } } })
    local plan = OdPlanInstruments(model, { gen = { drums = true }, beats_per_phrase = 40,
        unison_share = 0.5, keepout_od = 8, keepout_unison = 12, nogo = {}, fills = {} })
    local inside = 0
    for _, sp in ipairs(plan.phrases.drums) do
        if OdSpansOverlap(sp.s, sp.e, bars[20].qn_s, bars[120].qn_e) then inside = inside + 1 end
    end
    Test.expect(inside <= 4, inside .. ' phrases in the solo')
    Test.expect(plan.solo_trimmed > 0, 'expected trimming')
end)

Test.it('never two phrases on one part without a gem between (Magma), even when crowded', function()
    -- One phrase per 4 beats asks for a phrase in every bar; a rest in the middle.
    local model = MkModel(60, { guitar = Range(1, 25), bass = 'all', drums = 'all', keys = Range(30, 60) })
    local plan = OdPlanInstruments(model, {
        gen = { guitar = true, bass = true, drums = true, keys = true },
        beats_per_phrase = 4, unison_share = 0.5, keepout_od = 8, keepout_unison = 12,
        nogo = {}, fills = {} })
    local placed = 0
    for key, list in pairs(plan.phrases) do
        placed = placed + #list
        local issues = OdPhraseGemIssues(list, model.inst[key].events)
        Test.expect(#issues.adjacent == 0, ('%s: %d pairs with no gem between'):format(key, #issues.adjacent))
        Test.expect(#issues.empty == 0, key .. ': an empty phrase')
    end
    Test.expect(placed > 20, 'the planner still placed phrases (' .. placed .. ')')
end)

Test.it('a lower difficulty without a gem between also blocks a phrase', function()
    -- Expert plays every beat; Hard only bar 1-10 and 21+, so Hard has nothing between
    -- a phrase in bar 10 and one in bar 21.
    local model = MkModel(40, { guitar = 'all' })
    local g = model.inst.guitar
    local hard = {}
    for _, ev in ipairs(g.events) do
        local b = OdBarAt(model.bars, ev.qn)
        if b <= 10 or b >= 21 then hard[#hard + 1] = ev end
    end
    g.tiers = { { name = 'Expert', events = g.events }, { name = 'Hard', events = hard } }
    local ten = model.bars[10]
    g.od = { { s = ten.qn_s, e = ten.qn_e } }
    local plan = OdPlanInstruments(model, { gen = { bass = true }, beats_per_phrase = 40,
        unison_share = 0.5, keepout_od = 8, keepout_unison = 12, nogo = {}, fills = {} })
    -- Guitar is kept here (not generated); the check itself is the validator's.
    g.od[2] = { s = model.bars[21].qn_s, e = model.bars[21].qn_e }
    local errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('Guitar Hard: no notes between', 1, true) ~= nil, 'Hard not flagged:\n' .. errs)
    Test.expect(errs:find('Guitar Expert: no notes between', 1, true) == nil, 'Expert has gems between')
    Test.expect(plan ~= nil)
end)

----------------------------------------------------------------------
Test.section('Phrase gem checks')
----------------------------------------------------------------------

Test.it('OdHasGem: start inclusive, end exclusive', function()
    local ev = { { qn = 1 }, { qn = 3 }, { qn = 5 } }
    Test.expect(OdHasGem(ev, 3, 4), 'gem on the start')
    Test.expect(not OdHasGem(ev, 3.5, 5), 'gem on the end is outside')
    Test.expect(not OdHasGem(ev, 6, 8), 'after every gem')
    Test.expect(OdHasGem(ev, 0, 1.5) and not OdHasGem({}, 0, 9), 'first gem / no gems')
end)

Test.it('OdPhraseGemIssues: empty phrases and pairs with nothing between', function()
    local ev = { { qn = 0 }, { qn = 4 }, { qn = 12 } }
    local od = { { s = 0, e = 2 }, { s = 4, e = 6 }, { s = 8, e = 10 }, { s = 12, e = 14 } }
    local i = OdPhraseGemIssues(od, ev)
    Test.expect(#i.empty == 1 and i.empty[1].s == 8, 'phrase at 8 has no gem')
    -- 0-2 -> 4-6: nothing in [2, 4) (the gem at 4 is inside the next phrase); 4-6 -> 8-10
    -- and 8-10 -> 12-14 likewise.
    Test.expect(#i.adjacent == 3, 'pairs ' .. #i.adjacent)
    local ok = OdPhraseGemIssues({ { s = 0, e = 2 }, { s = 4, e = 6 } }, { { qn = 0 }, { qn = 3 }, { qn = 4 } })
    Test.expect(#ok.adjacent == 0 and #ok.empty == 0, 'a gem at 3 separates them')
end)

----------------------------------------------------------------------
Test.section('Validator')
----------------------------------------------------------------------

-- Plan a whole model and write the plan into it, as Generate would.
local function GeneratedModel()
    local model = MkModel(80, ALL4)
    local fills = OdPlanFills(model, { pacing = 2, align = false, drum_od = {} }).fills
    local plan = PlanAll(model, {}, fills)
    for key, list in pairs(plan.phrases) do model.inst[key].od = list end
    model.fills = fills
    for _, f in ipairs(fills) do f.lanes = 5 end
    return model
end

Test.it('a generated song validates with no errors', function()
    local rep = OdValidateModel(GeneratedModel(), STD)
    Test.expect(rep.n_errors == 0, table.concat(rep.errors, ' / '))
end)

Test.it('flags a drum phrase overlapping a fill', function()
    local model = GeneratedModel()
    local f = model.fills[3]
    model.inst.drums.od[#model.inst.drums.od + 1] = { s = f.s, e = f.e }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.errors, '\n'):find('overlaps a fill', 1, true) ~= nil, 'not flagged')
end)

Test.it('flags fills under 2.5 s apart (Magma)', function()
    local model = AtBpm(GeneratedModel(), 193)
    local f = model.fills[3]
    -- A second 2-bar fill ending 4 bars after it: 2 bars (2.49 s at 193 BPM) between.
    local b = OdBarStartingAt(model.bars, f.e)
    table.insert(model.fills, 4, { s = model.bars[b + 2].qn_s, e = model.bars[b + 4].qn_s, lanes = 5 })
    local errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('Magma needs 2.5 s', 1, true) ~= nil, 'not flagged')
    Test.expect(OdValidateModel(GeneratedModel(), STD).n_errors == 0, 'flagged a clean song')
end)

Test.it('flags PART KEYS and PART REAL_KEYS_X that differ', function()
    local model = GeneratedModel()
    model.inst.keys.track, model.inst.keys.mirror_track = true, true
    model.inst.keys.mirror_od = { model.inst.keys.od[1] }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.errors, '\n'):find('PART REAL_KEYS_X', 1, true) ~= nil, 'not flagged')
end)

Test.it('HARM1 overdrive that differs from PART VOCALS is a warning (Magma accepts it)', function()
    local model = GeneratedModel()
    local s, e = model.bars[10].qn_s, model.bars[11].qn_e
    local s2, e2 = model.bars[20].qn_s, model.bars[21].qn_e
    model.vocal = { present = true, harm_present = true,
                    phrases = { { s = s, e = e, has_notes = true }, { s = s2, e = e2, has_notes = true } },
                    od = { { s = s, e = e } }, harm_od = { { s = s2, e = e2 } },
                    harm_phrases = { { s = s, e = e }, { s = s2, e = e2 } } }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.warnings, '\n'):find('PART VOCALS and HARM1 overdrive differ', 1, true) ~= nil,
                'not warned')
    Test.expect(table.concat(rep.errors, '\n'):find('HARM1', 1, true) == nil, 'still an error')
end)

Test.it('HARM1 with no overdrive at all is fine: harmonies use PART VOCALS\'', function()
    -- Verified in game: harmonies earn overdrive on PART VOCALS' phrases then.
    local model = GeneratedModel()
    local s, e = model.bars[10].qn_s, model.bars[11].qn_e
    model.vocal = { present = true, harm_present = true,
                    phrases = { { s = s, e = e, has_notes = true } },
                    od = { { s = s, e = e } }, harm_od = {}, harm_phrases = { { s = s, e = e } } }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.warnings, '\n'):find('overdrive differ', 1, true) == nil, 'warned')
    Test.expect(table.concat(rep.summary, '\n'):find('HARM1 has none', 1, true) ~= nil, 'no Markers note')
end)

Test.it('HARM1 overdrive where PART VOCALS has no phrase is not a mismatch', function()
    -- A part only the harmonies sing: PART VOCALS can have no overdrive there.
    local model = GeneratedModel()
    local s, e = model.bars[10].qn_s, model.bars[11].qn_e
    local s2, e2 = model.bars[20].qn_s, model.bars[21].qn_e
    model.vocal = { present = true, harm_present = true,
                    phrases = { { s = s, e = e, has_notes = true } },
                    od = { { s = s, e = e } }, harm_od = { { s = s, e = e }, { s = s2, e = e2 } },
                    harm_phrases = { { s = s, e = e }, { s = s2, e = e2 } } }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.warnings, '\n'):find('overdrive differ', 1, true) == nil, 'warned')
    Test.expect(table.concat(rep.summary, '\n'):find('HARM1 adds 1 where PART VOCALS has no phrase', 1, true) ~= nil,
                'no Markers note')
end)

Test.it('HARM1 overdrive missing one of PART VOCALS\' phrases is still a mismatch', function()
    -- The extra HARM1 phrase is exempt, but PART VOCALS' second one is not on HARM1.
    local model = GeneratedModel()
    local s, e = model.bars[10].qn_s, model.bars[11].qn_e
    local s2, e2 = model.bars[20].qn_s, model.bars[21].qn_e
    local s3, e3 = model.bars[30].qn_s, model.bars[31].qn_e
    model.vocal = { present = true, harm_present = true,
                    phrases = { { s = s, e = e, has_notes = true }, { s = s3, e = e3, has_notes = true } },
                    od = { { s = s, e = e }, { s = s3, e = e3 } }, harm_od = { { s = s, e = e }, { s = s2, e = e2 } },
                    harm_phrases = { { s = s, e = e }, { s = s2, e = e2 }, { s = s3, e = e3 } } }
    local rep = OdValidateModel(model, STD)
    Test.expect(table.concat(rep.warnings, '\n'):find('overdrive differ', 1, true) ~= nil, 'not warned')
end)

-- A song with harmonies: PART VOCALS has phrases 10-11 and 12-13, HARM1 one phrase 10-13.
local function HarmModel(vocal_od, harm_od, harm_sung)
    local model = GeneratedModel()
    local b = model.bars
    local a = { s = b[10].qn_s, e = b[11].qn_e }
    local c = { s = b[12].qn_s, e = b[13].qn_e }
    model.vocal = { present = true, harm_present = true,
                    phrases = { { s = a.s, e = a.e, has_notes = true }, { s = c.s, e = c.e, has_notes = true } },
                    harm_phrases = { { s = a.s, e = c.e } },
                    od = vocal_od(a, c), harm_od = harm_od(a, c),
                    sung = { { qn = a.s }, { qn = c.s } }, harm_sung = harm_sung or { { qn = a.s }, { qn = c.s } } }
    return model
end

Test.it('HARM1 overdrive off a HARM1 marker is an error, with the reason when PART VOCALS fits', function()
    local model = HarmModel(function(a) return { a } end, function(a) return { { s = a.s, e = a.e } } end)
    local errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('HARM1: overdrive at', 1, true) ~= nil, 'not flagged:\n' .. errs)
    Test.expect(errs:find('It is fine on PART VOCALS', 1, true) ~= nil, 'no look-ahead hint:\n' .. errs)
    -- Fitting HARM1's own marker: no HARM1 error (the mismatch with PART VOCALS is a warning).
    local fit = HarmModel(function(a) return { a } end, function(a, c) return { { s = a.s, e = c.e } } end)
    local rep = OdValidateModel(fit, STD)
    Test.expect(table.concat(rep.errors, '\n'):find('HARM1:', 1, true) == nil, 'fitting overdrive flagged')
    Test.expect(table.concat(rep.warnings, '\n'):find('overdrive differ', 1, true) ~= nil, 'mismatch not warned')
end)

Test.it('HARM1 overdrive on a HARM1 phrase with no HARM1 notes is a Magma error', function()
    -- Fits HARM1's marker exactly, but HARM1 sings only later in the song (Magma:
    -- "ends prematurely", verified on a test song).
    local od = function(a, c) return { { s = a.s, e = c.e } } end
    local model = HarmModel(function(a) return { a } end, od, nil)
    local b40 = model.bars[40]
    model.vocal.harm_phrases[2] = { s = b40.qn_s, e = b40.qn_e }
    model.vocal.harm_sung = { { qn = b40.qn_s, qn_e = b40.qn_s + 1 } }
    local errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('phrase with no HARM1 notes', 1, true) ~= nil, 'not flagged:\n' .. errs)
    Test.expect(errs:find('Magma reports it as "ends prematurely"', 1, true) ~= nil, 'no Magma text')
    -- HARM2 sings there (HARM1-3 together): accepted, as in Magma-built RBN songs.
    model.vocal.harm_any = { { qn = model.bars[10].qn_s, qn_e = model.bars[10].qn_s + 1 },
                             { qn = b40.qn_s, qn_e = b40.qn_s + 1 } }
    errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('HARM1:', 1, true) == nil, 'flagged though HARM2 sings:\n' .. errs)
    -- With a HARM1 note inside: clean.
    model.vocal.harm_any = nil
    model.vocal.harm_sung = { { qn = model.bars[10].qn_s, qn_e = model.bars[13].qn_s } }
    errs = table.concat(OdValidateModel(model, STD).errors, '\n')
    Test.expect(errs:find('HARM1:', 1, true) == nil, 'flagged with a HARM1 note:\n' .. errs)
end)

Test.it('OdVocalOdProblem: judged by notes, each case Magma reports', function()
    -- Phrases 10-20 and 30-40; notes 11-12, 14-16, 31-32.
    local ph = { { s = 10, e = 20 }, { s = 30, e = 40 } }
    local n = { { qn = 11, qn_e = 12 }, { qn = 14, qn_e = 16 }, { qn = 31, qn_e = 32 } }
    local function K(s, e) return (OdVocalOdProblem({ s = s, e = e }, ph, n)) end
    Test.expect(K(10, 20) == nil, 'exact fit')
    Test.expect(K(9, 25) == nil, 'off the markers but covering the notes: Magma accepts it')
    Test.expect(K(10, 15) == nil, 'the last note rings past the end: still covered')
    Test.expect(K(15, 20) == 'during_note', 'starts inside the 14-16 note')
    Test.expect(K(12.5, 20) == 'mid_phrase', 'starts after the phrase\'s first note')
    Test.expect(K(10, 13) == 'short', 'ends before the last note starts')
    Test.expect(K(10, 31.5) == 'long', 'reaches the next phrase\'s first note')
    Test.expect(K(8, 13) == 'short', 'early start ending short: judged by the next note\'s phrase')
    Test.expect(K(45, 50) == 'after_all', 'after every note')
    Test.expect(OdVocalOdProblem({ s = 10, e = 20 }, ph, { { qn = 31, qn_e = 32 } }) == 'no_notes',
                'a phrase with no note of this track')
    Test.expect(OdVocalOdProblem({ s = 10, e = 20 }, ph, { { qn = 50, qn_e = 51 } }) == 'off',
                'the next note is outside every phrase')
    -- HARM1: a phrase only HARM2 sings in is fine.
    Test.expect(OdVocalOdProblem({ s = 10, e = 20 }, ph, { { qn = 31, qn_e = 32 } },
                { { qn = 12, qn_e = 13 }, { qn = 31, qn_e = 32 } }) == nil, 'another voice sings there')
end)

Test.it('an instrument phrase with no gems is warned, two with none between are a Magma error', function()
    local model = GeneratedModel()
    -- Guitar rests in bars 60-62: a phrase there is empty; one at 59 and one at 63
    -- (bars 60-62 empty) have no gem between them.
    local g = model.inst.guitar
    local keep = {}
    for _, ev in ipairs(g.events) do
        local b = OdBarAt(model.bars, ev.qn)
        if b < 60 or b > 62 then keep[#keep + 1] = ev end
    end
    g.events = keep
    g.tiers = { { name = 'Expert', events = keep } }
    local b = model.bars
    g.od = { { s = b[59].qn_s, e = b[59].qn_e }, { s = b[61].qn_s, e = b[61].qn_e },
             { s = b[63].qn_s, e = b[63].qn_e } }
    local rep = OdValidateModel(model, STD)
    local errs, w = table.concat(rep.errors, '\n'), table.concat(rep.warnings, '\n')
    Test.expect(w:find('Guitar Expert: overdrive phrase at', 1, true) ~= nil, 'empty phrase not warned:\n' .. w)
    Test.expect(errs:find('Guitar Expert: no notes between', 1, true) ~= nil, 'no-gems-between not flagged:\n' .. errs)
end)

Test.it('warns about a two-instrument pair and a late phrase', function()
    local model = GeneratedModel()
    local b = model.bars[76]
    model.inst.guitar.od[#model.inst.guitar.od + 1] = { s = b.qn_s, e = b.qn_e }
    model.inst.bass.od[#model.inst.bass.od + 1] = { s = b.qn_s, e = b.qn_e }
    local w = table.concat(OdValidateModel(model, STD).warnings, '\n')
    Test.expect(w:find('share a phrase', 1, true) ~= nil, 'pair not flagged')
    Test.expect(w:find('last 8 measures', 1, true) ~= nil, 'late phrase not flagged')
end)

----------------------------------------------------------------------
Test.section('Generate and Validate on real tracks')
----------------------------------------------------------------------

local TRACK_NAMES = { 'EVENTS', 'PART GUITAR', 'PART BASS', 'PART DRUMS', 'PART DRUMS_2X',
                      'PART VOCALS', 'HARM1' }
local clash = false
for _, n in ipairs(TRACK_NAMES) do if FindTrackExact(n) then clash = true end end

if clash then
    r.ShowConsoleMsg('  SKIP  end-to-end tests (project already has a PART or EVENTS track)\n')
else

local N_MEAS = 48

-- Quarter-note start of measure m (1-based), from the project's own measure map.
local function MeasQN(m) return ({ r.TimeMap_GetMeasureInfo(0, m - 1) })[2] end

local function MkTrack(name, notes, texts)
    local idx  = CreateEmptyFixtureTrack(name)
    local tr   = r.GetTrack(0, idx)
    local item = r.CreateNewMIDIItemInProj(tr, 0, r.TimeMap2_QNToTime(0, MeasQN(N_MEAS + 1)), false)
    local take = r.GetActiveTake(item)
    for _, n in ipairs(notes or {}) do
        local sp = r.MIDI_GetPPQPosFromProjQN(take, n[1])
        local ep = r.MIDI_GetPPQPosFromProjQN(take, n[2])
        r.MIDI_InsertNote(take, false, false, sp, ep, 0, n[3], 100, true)
    end
    for _, x in ipairs(texts or {}) do
        r.MIDI_InsertTextSysexEvt(take, false, false, r.MIDI_GetPPQPosFromProjQN(take, x[1]), 1, x[2])
    end
    r.MIDI_Sort(take)
    return tr
end

-- A gem on every beat of measures 1..last.
local function Beats(last)
    local out = {}
    for m = 1, last do
        local q, qe = MeasQN(m), MeasQN(m + 1)
        local k = 0
        while q < qe - 1e-9 do
            k = k + 1
            out[#out + 1] = { q, q + 0.25, 96 + (m + k) % 3 }
            q = q + 1
        end
    end
    return out
end

local function Count(name, pitch)
    local tr = FindTrackExact(name)
    local n = 0
    for _, tk in ipairs(OdTrackTakes(tr)) do
        local _, cnt = r.MIDI_CountEvts(tk.take)
        for i = 0, cnt - 1 do
            local _, _, _, _, _, _, p = r.MIDI_GetNote(tk.take, i)
            if p == pitch then n = n + 1 end
        end
    end
    return n
end

local function Build()
    MkTrack('EVENTS', {}, { { MeasQN(N_MEAS), '[end]' } })
    MkTrack('PART GUITAR', Beats(N_MEAS - 1))
    MkTrack('PART BASS', Beats(N_MEAS - 1))
    MkTrack('PART DRUMS', Beats(N_MEAS - 1))
    MkTrack('PART DRUMS_2X', Beats(N_MEAS - 1))
    -- 20 two-measure phrases; HARM1 carries identical markers except phrase 8.
    local vox, harm = {}, {}
    for i = 1, 20 do
        local s, e = MeasQN(2 * i - 1), MeasQN(2 * i + 1) - 0.5
        vox[#vox + 1] = { s, e, 105 }
        vox[#vox + 1] = { s, s + 1, 60 }
        harm[#harm + 1] = { s, (i == 8) and (e - 0.25) or e, 105 }
        harm[#harm + 1] = { s, s + 1, 64 }
    end
    MkTrack('PART VOCALS', vox)
    MkTrack('HARM1', harm)
end

local function DefaultSettings()
    S.od_group, S.od_inc_phrases, S.od_inc_fills, S.od_inc_vocals = 0, true, true, true
    S.od_beats_per_phrase, S.od_unison_share = 40, 50
    S.od_keepout_od, S.od_keepout_unison = 8, 12
    S.od_fill_pacing, S.od_fill_sections, S.od_vocal_every = 2, false, 5
    S.od_keepout_start, S.od_fill_skip_early = 5, true
    S.od_vocal_harm1 = true
end

Test.it('writes every part, mirrors 2X, and validates clean', function()
    local base = r.CountTracks(0)
    Build()
    DefaultSettings()
    GenerateOverdrive()
    Test.expect(S.od_pending == nil, 'empty tracks should not ask: ' .. tostring(S.status))
    Test.expect(Count('PART GUITAR', 116) > 0, 'no guitar overdrive')
    Test.expect(Count('PART DRUMS', 116) == Count('PART DRUMS_2X', 116), '2X OD differs')
    Test.expect(Count('PART DRUMS', 120) > 0 and Count('PART DRUMS', 120) == Count('PART DRUMS_2X', 124),
                'fills missing or not mirrored')
    Test.expect(Count('PART VOCALS', 116) == Count('HARM1', 116), 'HARM1 OD count differs')
    ValidateOverdrive()
    Test.expect(S.status:find('^Overdrive check: 0 errors') or S.status:find('no issues', 1, true),
                'validation: ' .. tostring(S.status) .. '\n' .. tostring(S.last_result))
    CleanupFixture(base)
end)

Test.it('asks before replacing and writes nothing until answered', function()
    local base = r.CountTracks(0)
    Build()
    DefaultSettings()
    GenerateOverdrive()
    local before = Count('PART GUITAR', 116)
    S.od_group = 3   -- Guitar only
    GenerateOverdrive()
    Test.expect(S.od_pending ~= nil, 'no confirmation asked')
    Test.expect(Count('PART GUITAR', 116) == before, 'wrote before confirmation')
    S.od_pending.on_replace()
    Test.expect(S.od_pending == nil and Count('PART GUITAR', 116) > 0, 'replace did not write')
    CleanupFixture(base)
end)

Test.it('Generate OD for HARM1 off: HARM1 cleared, PART VOCALS written, no mismatch warning', function()
    local base = r.CountTracks(0)
    Build()
    DefaultSettings()
    GenerateOverdrive()   -- first with HARM1, so the second run has HARM1 overdrive to remove
    Test.expect(Count('HARM1', 116) > 0, 'setup: no HARM1 overdrive')
    S.od_vocal_harm1 = false
    GenerateOverdrive()
    Test.expect(S.od_pending ~= nil, 'no replace question asked')
    Test.expect(not S.od_pending.message:find('HARM1', 1, true), 'replace question lists HARM1')
    S.od_pending.on_replace()
    Test.expect(S.od_pending ~= nil and S.od_pending.replace_label == 'Remove', 'no HARM1 question asked')
    S.od_pending.on_replace()   -- Remove
    Test.expect(S.od_pending == nil, 'still asking')
    Test.expect(Count('PART VOCALS', 116) > 0, 'no PART VOCALS overdrive')
    Test.expect(Count('HARM1', 116) == 0, 'HARM1 still has overdrive')
    Test.expect(tostring(S.last_result):find('HARM1 left without', 1, true) ~= nil, 'no Written to note')
    ValidateOverdrive()
    Test.expect(tostring(S.last_result):find('overdrive differ', 1, true) == nil, 'mismatch warned')
    CleanupFixture(base)
    S.od_vocal_harm1 = true
end)

Test.it('Generate OD for HARM1 off: Keep leaves HARM1 overdrive untouched', function()
    local base = r.CountTracks(0)
    Build()
    DefaultSettings()
    GenerateOverdrive()
    local before = Count('HARM1', 116)
    S.od_vocal_harm1 = false
    GenerateOverdrive()
    S.od_pending.on_replace()   -- replace the other tracks
    Test.expect(S.od_pending ~= nil and S.od_pending.keep_label == 'Keep', 'no HARM1 question asked')
    S.od_pending.on_keep()
    Test.expect(S.od_pending == nil, 'still asking')
    Test.expect(Count('HARM1', 116) == before, 'HARM1 overdrive changed')
    Test.expect(tostring(S.last_result):find('own overdrive kept', 1, true) ~= nil, 'no Written to note')
    CleanupFixture(base)
    S.od_vocal_harm1 = true
end)

end
