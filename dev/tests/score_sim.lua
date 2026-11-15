-- Unit tests for lib/reaper_score_sim.lua. Synthetic charts at 120 BPM (0.5 s per
-- quarter note), BEAT notes on every quarter note unless a test says otherwise.

local function Near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- n gems from `from` QN, `step` QN apart, each `len` QN long with `notes` notes.
local function Gems(n, step, len, notes, from)
    local out = {}
    for i = 0, n - 1 do
        local qn = (from or 0) + i * step
        out[#out + 1] = { qn = qn, qn_e = qn + (len or 0.1), sec = qn * 0.5, n = notes or 1 }
    end
    return out
end

local function Beats(from, to, step)
    local out = {}
    for q = from, to, step or 1 do out[#out + 1] = q end
    return out
end

local function Part(kind, gems, extra)
    local p = { kind = kind, gems = gems, od = {}, solos = {}, fills = {},
                beats = Beats(0, 400) }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

Test.section('Base score')

Test.it('25 per note, x2 from the 10th gem', function()
    local s9  = ScoreBasePart(Part('guitar', Gems(9, 1)))
    local s10 = ScoreBasePart(Part('guitar', Gems(10, 1)))
    Test.expect(s9 == 225, 'nine gems: ' .. s9)
    Test.expect(s10 == 275, 'ten gems: ' .. s10)
end)

Test.it('a chord is 25 per note', function()
    Test.expect(ScoreBasePart(Part('guitar', Gems(1, 1, 0.1, 3))) == 75)
end)

Test.it('tail only above 1/3 QN, 12 per quarter note per note', function()
    local short = ScoreBasePart(Part('guitar', Gems(1, 1, 1 / 3, 2)))
    local long  = ScoreBasePart(Part('guitar', Gems(1, 1, 0.5, 2)))
    Test.expect(short == 50, 'no tail at 1/3 QN: ' .. short)
    Test.expect(Near(long, 50 + 12 * 0.5 * 2), 'tail: ' .. long)
end)

Test.it('drums never score a tail', function()
    Test.expect(ScoreBasePart(Part('drums', Gems(1, 1, 2))) == 25)
end)

Test.it('bass multiplier reaches x6, guitar stops at x4', function()
    local bass = ScoreBasePart(Part('bass', Gems(60, 1)))
    local gtr  = ScoreBasePart(Part('guitar', Gems(60, 1)))
    Test.expect(bass == 25 * (9 + 20 + 30 + 40 + 50 + 60 + 6), 'bass ' .. bass)
    Test.expect(gtr == 25 * (9 + 20 + 30 + 4 * 31), 'guitar ' .. gtr)
end)

Test.it('solo bonus 100 per gem in the solo', function()
    local p = Part('guitar', Gems(10, 1), { solos = { { s = 2, e = 7 } } })
    local _, bonus, solo = ScoreBasePart(p)
    Test.expect(solo == 500 and bonus == 500, 'solo ' .. solo)
end)

Test.it('Big Rock Ending gems are left out, it pays 100 per second', function()
    local p = Part('guitar', Gems(20, 1), { bre = { s = 10, e = 18, sec = 4 } })
    local streak, bonus = ScoreBasePart(p)
    -- Gems 0-9 and the final hits at 18 and 19 after the lanes; 10-17 are left out.
    Test.expect(streak == 25 * 9 + 50 * 3, 'BRE gems left out: ' .. streak)
    Test.expect(bonus == 400, 'coda bonus ' .. bonus)
end)

Test.it('Pro drums: base 30 per note, a tom earns 25 in play', function()
    local g = Gems(2, 1)
    g[2].toms = 1
    local p = Part('drums', g)
    Test.expect(ScoreBasePart(p, { pro = true }) == 60)
    local res = ScoreSimulateOD(p, { pro = true })
    Test.expect(res.score == 55, 'played ' .. res.score)
    Test.expect(ScoreSimulateOD(p, { pro = false }).score == 50)
end)

Test.it('Pro Keys: 60 per note, tail 30 per quarter note, x4 at most', function()
    Test.expect(ScoreBasePart(Part('prokeys', Gems(1, 1, 0.1, 3))) == 180, 'chord of 3')
    local tail = ScoreBasePart(Part('prokeys', Gems(1, 1, 0.5, 2)))
    Test.expect(Near(tail, 120 + 30 * 0.5 * 2), 'tail ' .. tail)
    local s40 = ScoreBasePart(Part('prokeys', Gems(40, 1)))
    Test.expect(s40 == 60 * (9 + 20 + 30 + 4 * 11), 'x4 cap: ' .. s40)
    local st = ScoreStars('prokeys', 1000, 0)
    Test.expect(st[6] == 1150, 'stars as keys')
end)

Test.it('Big Rock Ending in play: up to 500 per second, the base counts 100', function()
    local p = Part('guitar', Gems(20, 1), { bre = { s = 10, e = 18, sec = 4 } })
    local res = ScoreSimulateOD(p)
    Test.expect(res.base_bonus == 400, 'base ' .. res.base_bonus)
    Test.expect(res.bre_points == 2000 and res.bonus == 2000, 'played ' .. res.bonus)
end)

Test.section('Unisons (ScoreMarkUnisons)')

local function OdParts(spec)
    local parts = {}
    for key, starts in pairs(spec) do
        local od = {}
        for _, s in ipairs(starts) do od[#od + 1] = { s = s, e = s + 4 } end
        parts[key] = { od = od }
    end
    ScoreMarkUnisons(parts)
    return parts
end

Test.it('starts under a quarter note apart on two instruments: a unison', function()
    local p = OdParts({ guitar = { 10 }, bass = { 10.75 } })
    Test.expect(p.guitar.od[1].unison and p.bass.od[1].unison)
end)

Test.it('a quarter note or more apart: not a unison, whatever the ends', function()
    local p = OdParts({ guitar = { 10 }, bass = { 11 } })
    Test.expect(not p.guitar.od[1].unison and not p.bass.od[1].unison)
end)

Test.it('Keys with Pro Keys, or Drums with Drums 2X, is one instrument', function()
    local p = OdParts({ keys = { 10 }, prokeys = { 10 }, drums = { 20 }, drums2x = { 20 } })
    Test.expect(not p.keys.od[1].unison and not p.prokeys.od[1].unison, 'keys')
    Test.expect(not p.drums.od[1].unison and not p.drums2x.od[1].unison, 'drums')
    local q = OdParts({ keys = { 10 }, prokeys = { 10 }, guitar = { 10 } })
    Test.expect(q.keys.od[1].unison and q.prokeys.od[1].unison, 'with guitar it is')
end)

Test.it('vocals never join a unison', function()
    local p = OdParts({ guitar = { 10 }, vocals = { 10 } })
    Test.expect(not p.guitar.od[1].unison and not p.vocals.od[1].unison)
end)

Test.section('Stars')

Test.it('cut-offs from the game thresholds', function()
    local st = ScoreStars('guitar', 1000, 0)
    Test.expect(st[5] == 780 and st[6] == 1150, 'guitar ' .. st[5] .. ' ' .. st[6])
    local dr = ScoreStars('drums', 1000, 100)
    Test.expect(dr[6] == math.floor(1090 + 95), 'drums gold with bonus ' .. dr[6])
    Test.expect(ScoreStarsReached(st, 1149) == 5 and ScoreStarsReached(st, 1150) == 6)
end)

Test.section('Beats')

Test.it('beat count and its inverse', function()
    local b = { 0, 2, 4, 6 }
    Test.expect(Near(ScoreBeatAt(b, 3), 1.5))
    Test.expect(Near(ScoreBeatAt(b, 8), 4))
    Test.expect(Near(ScoreQNAtBeat(b, 1.5), 3))
    Test.expect(Near(ScoreQNAtBeat(b, 4), 8))
    Test.expect(Near(ScoreBeatAt({}, 5), 5), 'no BEAT track: one per quarter note')
end)

Test.section('Overdrive')

Test.it('two phrases make it ready; it drains 1/32 per beat', function()
    local p = Part('guitar', Gems(80, 1), { od = { { s = 0, e = 1 }, { s = 4, e = 5 } } })
    local res = ScoreSimulateOD(p)
    Test.expect(#res.deploys == 1, 'one deploy: ' .. #res.deploys)
    local d = res.deploys[1]
    Test.expect(Near(d.s, 4), 'starts at the second phrase: ' .. d.s)
    Test.expect(Near(d.e - d.s, 0.502 * 32, 1e-3), 'lasts 16.064 beats: ' .. (d.e - d.s))
end)

Test.it('half-time BEAT track: the same meter lasts twice as long', function()
    local p = Part('guitar', Gems(80, 1), { od = { { s = 0, e = 1 }, { s = 4, e = 5 } },
                                            beats = Beats(0, 400, 2) })
    local d = ScoreSimulateOD(p).deploys[1]
    Test.expect(Near(d.e - d.s, 0.502 * 64, 1e-3), 'half time: ' .. (d.e - d.s))
end)

Test.it('a unison phrase alone fills half the meter', function()
    local p = Part('bass', Gems(40, 1), { od = { { s = 0, e = 1, unison = true } } })
    local res = ScoreSimulateOD(p)
    Test.expect(#res.deploys == 1 and Near(res.deploys[1].s, 0))
end)

Test.it('notes in overdrive score x2', function()
    local plain = ScoreSimulateOD(Part('guitar', Gems(40, 1)))
    local od = ScoreSimulateOD(Part('guitar', Gems(40, 1),
                               { od = { { s = 0, e = 1, unison = true } } }))
    Test.expect(od.score > plain.score, 'more with overdrive')
    Test.expect(plain.score == ScoreBasePart(Part('guitar', Gems(40, 1))),
                'no overdrive = the base')
    Test.expect(od.od_gems == 16, 'gems 2-17 doubled: ' .. od.od_gems)
end)

Test.it('whammy on an overdrive sustain fills the meter', function()
    local g = Gems(1, 1, 4)
    for _, x in ipairs(Gems(30, 1, 0.1, 1, 10)) do g[#g + 1] = x end
    local p = Part('guitar', g, { od = { { s = 0, e = 1 } } })
    local on = ScoreSimulateOD(p, { whammy = true })
    local off = ScoreSimulateOD(p, { whammy = false })
    Test.expect(#off.deploys == 0 and Near(off.waste[1].amount, 0.251), 'without whammy')
    Test.expect(Near(on.waste[1].amount, 0.251 + 0.034 * 4, 1e-6), 'with whammy '
                .. tostring(on.waste[1] and on.waste[1].amount))
end)

Test.it('drums: a full meter wastes the next phrase; unspent when no fill comes', function()
    local od = {}
    for i = 0, 4 do od[#od + 1] = { s = i * 8, e = i * 8 + 1 } end
    local res = ScoreSimulateOD(Part('drums', Gems(48, 1), { od = od }))
    local full, unspent = 0, nil
    for _, w in ipairs(res.waste) do
        if w.kind == 'full' then full = full + w.amount
        elseif w.kind == 'unspent' then unspent = w end
    end
    -- 0.004 over the top on the fourth phrase, all 0.251 of the fifth.
    Test.expect(Near(full, 0.255, 1e-6), 'lost to a full meter: ' .. full)
    Test.expect(unspent and unspent.ready and Near(unspent.amount, 1), 'never deployed')
end)

Test.it('drums: a fill too soon after ready is lost, the next one deploys', function()
    local fills = { { s = 11, e = 12, s_sec = 5.5 }, { s = 20, e = 22, s_sec = 10 } }
    local p = Part('drums', Gems(60, 1),
                   { od = { { s = 0, e = 1 }, { s = 10, e = 11 } }, fills = fills })
    local res = ScoreSimulateOD(p)
    Test.expect(#res.lost_fills == 1 and Near(res.lost_fills[1].qn, 11), 'lost fill')
    Test.expect(Near(res.lost_fills[1].gap_sec, 0.5), 'gap ' .. res.lost_fills[1].gap_sec)
    Test.expect(#res.deploys == 1 and Near(res.deploys[1].s, 22), 'deploys at the crash')
    Test.expect(res.fill_points_lost > 0, 'the fill gems score nothing')
    Test.expect(res.gems == 60 - 3, 'gems 20, 21, 22 left out: ' .. res.gems)
end)

Test.it('drums deploy_anywhere (autoplay): deploys when ready, no fill gems lost', function()
    local fills = { { s = 20, e = 22, s_sec = 10 } }
    local p = Part('drums', Gems(60, 1),
                   { od = { { s = 0, e = 1 }, { s = 10, e = 11 } }, fills = fills })
    local res = ScoreSimulateOD(p, { deploy_anywhere = true })
    Test.expect(#res.deploys == 1 and Near(res.deploys[1].s, 10), 'deploys at ready')
    Test.expect(res.fill_points_lost == 0 and res.gems == 60, 'every gem scores')
    -- (Not "scores more": deploying later at the fill can cover more x4 gems.)
    Test.expect(ScoreSimulateOD(p).fill_points_lost > 0, 'the fill run loses its gems')
end)

Test.it('guitar: a deploy running past the last note is clipped there', function()
    local p = Part('guitar', Gems(10, 1), { od = { { s = 0, e = 1, unison = true } } })
    local res = ScoreSimulateOD(p)
    Test.expect(Near(res.deploys[1].e, 9), 'clipped: ' .. res.deploys[1].e)
    Test.expect(#res.waste == 0, 'running out at the end is not waste')
end)

Test.it('gold: the bar where it is reached, or how far short', function()
    local od = {}
    for i = 0, 9 do od[#od + 1] = { s = i * 20, e = i * 20 + 1, unison = true } end
    local rich = ScoreSimulateOD(Part('guitar', Gems(200, 1), { od = od }))
    Test.expect(rich.stars_reached == 6 and rich.gold_qn, 'gold reached')
    local poor = ScoreSimulateOD(Part('guitar', Gems(200, 1)))
    Test.expect(poor.stars_reached == 5 and not poor.gold_qn and poor.gold_short > 0,
                'no overdrive: 5 stars')
end)

Test.section('End of song: holding for the last overdrive')

-- Two phrases make the meter ready at 8 QN (deploy 8..24), then one lone phrase at 40:
-- deploy-asap leaves its 0.251 unused. Holding the first deploy until the lone phrase
-- adds to it uses everything.
local function EndPart()
    return Part('guitar', Gems(60, 1), { od = { { s = 0, e = 1 }, { s = 8, e = 9 },
                                                { s = 40, e = 41 } } })
end

Test.it('deploy-asap leaves the last overdrive unused', function()
    local res = ScoreSimulatePart(EndPart(), { search = 'off' })
    local unspent = false
    for _, w in ipairs(res.waste) do if w.kind == 'unspent' then unspent = true end end
    Test.expect(unspent and not res.held, 'unspent, no hold')
end)

Test.it('the search holds an earlier deploy so the last one is used', function()
    local res = ScoreSimulatePart(EndPart())
    local unspent = false
    for _, w in ipairs(res.waste) do if w.kind == 'unspent' then unspent = true end end
    Test.expect(not unspent, 'nothing left unused')
    Test.expect(res.held and Near(res.held[1].qn, 8), 'held at 8')
    Test.expect(res.held[1].deploy and res.held[1].deploy > 24, 'deployed later: '
                .. tostring(res.held[1].deploy))
    Test.expect(res.total > res.asap_total, 'scores more than deploy-asap')
end)

Test.it('a held deploy starts as early as it can and still meets the next phrase', function()
    -- Held at 8 with 0.502 (16.06 beats); the next phrase is collected at 40. Earliest
    -- start that is still running then: 40 - 16.06 + 0.25 margin = 24.19 -> the next
    -- breakpoint, 25. The phrase at 40 then extends the same deploy - one deploy only.
    local res = ScoreSimulatePart(EndPart())
    Test.expect(#res.deploys == 1, 'one deploy, extended: ' .. #res.deploys)
    local d = res.deploys[1]
    Test.expect(d.s > 24 and d.s <= 25 + 1e-6, 'starts early: ' .. d.s)
    Test.expect(d.e > 41, 'runs past the phrase at 40: ' .. d.e)
end)

Test.it('no unused overdrive at the end: the plain path, no search', function()
    local p = Part('guitar', Gems(60, 1), { od = { { s = 0, e = 1, unison = true } } })
    local res = ScoreSimulatePart(p)
    Test.expect(not res.held and res.total == res.asap_total)
end)

Test.it('advice: the last phrase too close to the end to spend its overdrive', function()
    -- Last phrase completes at 56; the part ends at 59: 3 beats left for 8 beats.
    local p = Part('guitar', Gems(60, 1), { od = { { s = 56, e = 57 } } })
    local res = ScoreSimulatePart(p)
    Test.expect(res.last_od and res.last_od.too_late, 'too late')
    Test.expect(Near(res.last_od.beats_left, 3) and Near(res.last_od.beats_needed, 0.251 * 32))
    local levels = {}
    for _, f in ipairs(ScoreFindings(res, nil, 'guitar')) do levels[f.level] = true end
    Test.expect(levels.advice and not levels.warn, 'advice, not a warning')
end)

Test.section('Vocals')

-- Phrases of 4 QN with a sung note filling 0..3 QN of each, 1 QN gap (0.5 s).
local function VocalPart(n, od_at, gap_qn)
    local phrases, notes = {}, {}
    local len = 4 + (gap_qn or 0)
    for i = 0, n - 1 do
        local s = i * len
        phrases[#phrases + 1] = { s = s, e = s + 4, e_sec = (s + 4) * 0.5, sung = true,
                                  perc = 0, od = od_at and od_at[i + 1] or false }
        notes[#notes + 1] = { qn = s, qn_e = s + 3, s = s * 0.5, e = (s + 3) * 0.5 }
    end
    return { kind = 'vocals', phrases = phrases, notes = notes, beats = Beats(0, 400) }
end

Test.it('base: 1000 per phrase with the phrase streak', function()
    Test.expect(ScoreBaseVocals(VocalPart(2)) == 3000)
    Test.expect(ScoreBaseVocals(VocalPart(5)) == 14000)
end)

Test.it('percussion phrases pay bonus only', function()
    local p = VocalPart(3)
    p.phrases[2].perc = 4
    local streak, bonus = ScoreBaseVocals(p)
    Test.expect(streak == 3000 and bonus == 400, streak .. ' ' .. bonus)
end)

Test.it('deploy in a 0.6 s gap doubles the phrases sung while deployed', function()
    -- 1 QN gap after each note = 0.5 s from the note end to the marker end plus the
    -- extra gap: 2 QN = 1 s between notes.
    local p = VocalPart(8, { true, true }, 1)
    local res = ScoreSimulateVocals(p)
    Test.expect(#res.deploys >= 1, 'deployed')
    -- Ready at the end of phrase 2 (marker end 9 QN = 4.5 s). Its gap runs 4.0..5.0 s,
    -- a freestyle section 4.1..4.9 s: 500 ms of noise from 4.5 s does not fit, so the
    -- deploy waits for the next section (6.6..7.4 s) and lands 500 ms into it, at
    -- 7.1 s = 14.2 QN.
    Test.expect(Near(res.deploys[1].s, 14.2, 1e-6), 'deploy start ' .. res.deploys[1].s)
    -- Phrase 3 ended its note at 13: none of it is doubled.
    -- Deploy 14.2..30.26: phrases 4, 5 and 6 (sung 15-18, 20-23, 25-28) in full, plus
    -- the first 132 ms of phrase 7's note (30..33 QN = 1.5 s): inside its 150 ms ramp, so
    -- only (2/3 x 132^1.5 / sqrt 150) / (100 + 1350) = 0.057 of it.
    local ramp = (2 / 3) * 132 ^ 1.5 / math.sqrt(150) / (100 + 1350)
    Test.expect(Near(res.od_gems, 3 + ramp, 1e-3), 'phrases doubled: ' .. res.od_gems)
    Test.expect(res.score > ScoreBaseVocals(p), 'more than the base')
end)

Test.it('harmonies: extra parts add 10% each, the star base stays solo', function()
    local p = VocalPart(5)
    for _, ph in ipairs(p.phrases) do
        local n = { qn = ph.s, qn_e = ph.s + 3, s = ph.s * 0.5, e = (ph.s + 3) * 0.5 }
        ph.voices = { { n }, { n }, { n } }     -- HARM1, HARM2, HARM3 all singing
    end
    local res = ScoreSimulateVocals(p)
    Test.expect(res.base_streak == 14000, 'base as solo: ' .. res.base_streak)
    Test.expect(Near(res.score, 14000 * 1.2), 'three parts = 1.2x: ' .. res.score)
    Test.expect(res.stars[6] == ScoreStars('vocals', 14000, 0)[6], 'same gold cut-off')
end)

Test.it('harmonies: a phrase only HARM2 sings is worth the full value', function()
    local p = VocalPart(2)
    local n = { qn = 0, qn_e = 3, s = 0, e = 1.5 }
    p.phrases[1].voices = { { n } }             -- one voice (HARM2) = the best-sung part
    p.phrases[2].voices = { { n }, { n } }
    local res = ScoreSimulateVocals(p)
    Test.expect(Near(res.score, 1000 * 1 + 1000 * 2 * 1.1), 'got ' .. res.score)
end)

Test.it('harmonies: any part\'s own freestyle section can deploy', function()
    local p = VocalPart(6, { true, true }, 0)   -- HARM1: only 0.5 s between notes
    -- HARM2 sings 6-9 QN, then nothing until 20: a section 4.6..9.9 s.
    p.lines = { p.notes, {
        { qn = 6, qn_e = 9, s = 3, e = 4.5 },
        { qn = 20, qn_e = 22, s = 10, e = 11 },
    } }
    local res = ScoreSimulateVocals(p)
    Test.expect(#res.deploys == 1, 'deployed in HARM2\'s section')
    -- Ready at 9 QN (4.5 s); the section starts at 4.6 s; 500 ms later = 5.1 s = 10.2 QN.
    Test.expect(Near(res.deploys[1].s, 10.2, 1e-6), 'at ' .. res.deploys[1].s)
end)

Test.it('freestyle sections: trimmed ends, none in a mid-word gap', function()
    local secs = ScoreFreestyleSections({
        { qn = 2, qn_e = 3, s = 1, e = 1.5, lyric = 'hel-' },
        { qn = 6, qn_e = 7, s = 3, e = 3.5, lyric = 'lo' },     -- 1.5 s gap, mid-word
        { qn = 9, qn_e = 10, s = 4.2, e = 4.7, lyric = 'you' }, -- 0.7 s gap: 50 ms trim
    })
    Test.expect(#secs == 3, 'start, one gap, after the end: ' .. #secs)
    Test.expect(Near(secs[1].s_sec, 0.1) and Near(secs[1].e_sec, 0.9), 'before the first note')
    Test.expect(Near(secs[2].s_sec, 3.55) and Near(secs[2].e_sec, 4.15), '600-800 ms gap')
    Test.expect(secs[3].e_sec == math.huge and Near(secs[3].s_sec, 4.8), 'after the last')
end)

Test.it('vocal weights: a note\'s first 150 ms ramp up', function()
    -- A 0.6 s note (1.2 QN): weight 2/3 x 150 + 450 = 550; its second half (300 ms,
    -- past the ramp) weighs 300, so a deploy from its middle doubles 300 / 550 of it.
    local n = { qn = 0, qn_e = 1.2, s = 0, e = 0.6 }
    Test.expect(Near(ScoreVocalSliceWeight(n, 0, 1.2), 550, 1e-6), 'whole note')
    Test.expect(Near(ScoreVocalSliceWeight(n, 0.6, 1.2), 300, 1e-6), 'second half')
    -- A piece clipped from a longer note keeps the whole note's ramp start.
    local piece = { qn = 0.6, qn_e = 1.2, oq = 0, oq_e = 1.2, s = 0, e = 0.6 }
    Test.expect(Near(ScoreVocalSliceWeight(piece, 0.6, 1.2), 300, 1e-6), 'clipped piece')
end)

Test.it('no gap long enough: overdrive is never spent', function()
    local p = VocalPart(6, { true, true }, 0)   -- 1 QN = 0.5 s between notes
    local res = ScoreSimulateVocals(p)
    Test.expect(#res.deploys == 0, 'no deploy')
    Test.expect(res.waste[1] and res.waste[1].kind == 'unspent' and res.waste[1].ready)
end)

------------------------------------------------------------------
Test.section('Copy result text (ScoreReportText)')

Test.it('numbers get thousands separators', function()
    Test.expect(ScoreNum(1234567) == '1,234,567' and ScoreNum(999) == '999' and ScoreNum(1000.4) == '1,000',
        ScoreNum(1234567) .. ' / ' .. ScoreNum(999) .. ' / ' .. ScoreNum(1000.4))
end)

Test.it('a card reads in the tab\'s order, with finding marks', function()
    local res = { stars = { 1, 2, 3, 4, 5, 1500 }, base_streak = 1000, base_bonus = 200,
                  total = 1400, stars_reached = 5, gold_short = 100, deploys = {},
                  bre_points = 0 }
    local text = ScoreReportText({ bars = {}, no_beat = true, cards = {
        { label = 'Guitar', kind = 'guitar', runs = { res },
          findings = { { level = 'warn', text = 'Lost.' }, { level = 'advice', text = 'Late.' },
                       { level = 'info', text = 'Held.' } } },
        { label = 'Keys', kind = 'keys', reason = 'PART KEYS is muted' } } })
    local want = {
        'No BEAT track', 'Guitar', 'Stars: 1* 1  2* 2  3* 3  4* 4  5* 5  Gold 1,500',
        'FC without OD: 1,200 (200 of it bonus)', 'FC with OD: 1,400 (5*) - short of gold by 100',
        'Never in OD.', '! Lost.', '? Late.', '- Held.', 'Keys', 'PART KEYS is muted' }
    local at = 0
    for _, w in ipairs(want) do
        local i = text:find(w, at + 1, true)
        Test.expect(i ~= nil, ('"%s" missing or out of order in:\n%s'):format(w, text))
        if not i then return end
        at = i
    end
end)
