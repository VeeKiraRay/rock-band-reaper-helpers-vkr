-- Scores Events > Metronome (MetronomePlan) against the official charts' practice
-- metronome notes, EVENTS 24 / 25 / 26.
--
--   lua dev/tools/metronome_eval_offline.lua <corpus> [dev|holdout|all] [songs]
--   <corpus> = the folder of official RB3 DLC MIDIs (local data, not in the repo).
--   METRONOME_SET="auto_16th_below_bpm=100" - try parameters without
--   editing the planner.
--   METRONOME_INTRO=chart|steady|audio (default audio, the shipped default: the
--   corpus has no COUNT IN audio, so it falls back to the chart count-in).
--   METRONOME_INTRO_MISSES=1 lists the songs whose intro differs.
--   `songs` lists every song's numbers, worst 26 first.
--
-- Hold-out, declared 2026-11-19 before any tuning here: every 5th song by sorted
-- shortname (index % 5 == 0). Tune on `dev` only; run `holdout` once, when the rules
-- are final. The first survey (which tier each note copies, the 95 BPM pulse rule)
-- looked at every song, so the hold-out checks the tuning, not that survey.
-- SPENT: run once on 2026-11-19 - holdout (114 songs): 24 F1 94.2, 25 F1 94.2, 26 F1 94.2,
-- pulse grid right 101 / 114; dev (470): 92.2 / 93.4 / 90.4, 400 / 470.
-- Tried on dev and dropped: pausing the pulse where no part sounds (26 F1 90.2 at a
-- 1 QN minimum, 90.3 at 2-4 QN, 90.4 never pausing).
-- Added after the hold-out (dev only, so no out-of-sample number): the count-in.
-- Intro (26 before the band) exactly right on dev: steady pulse 76 / 470, count-in
-- on the first note's bar line 213, on the nearest bar line 283, a tie to the later
-- bar 294 (shipped); 26 F1 90.4 -> 90.7.
--
-- Per note: recall (official notes with a generated one within 10 ticks) and
-- precision (generated notes with an official one). Pulse: songs whose generated 26
-- grid (8ths / 16ths) matches the official one.

local _dir = arg[0]:match('^(.+[\\/])') or './'
local _root = _dir .. '../../'
dofile(_dir .. 'smf_reader.lua')
dofile(_dir .. 'smf_chart_events.lua')
r, S = nil, {}
dofile(_root .. 'rock_band_general_helper_vkr/events_metronome.lua')

for kv in (os.getenv('METRONOME_SET') or ''):gmatch('[^,]+') do
    local k, v = kv:match('^%s*([%w_]+)%s*=%s*(%S+)')
    if k then
        if v == 'true' then v = true elseif v == 'false' then v = false else v = tonumber(v) or v end
        METRONOME_PARAMS[k] = v
        print('param ' .. k .. ' = ' .. tostring(v))
    end
end

local USAGE = 'usage: lua dev/tools/metronome_eval_offline.lua <corpus folder> [dev|holdout|all] [songs]'
local corpus = SmfCorpusArg(arg[1], USAGE)
local mode = arg[2] or 'dev'
local list_songs = arg[3] == 'songs'
local TOL_TICKS = 10

local files = SmfListFiles(corpus)
local names, seen = {}, {}
for _, f in ipairs(files) do
    local n = SmfShortname(f)
    if not seen[n] then seen[n] = true names[#names + 1] = { f = f, n = n } end
end
table.sort(names, function(a, b) return a.n < b.n end)

-- Expert notes of every part, for the band's first note (count-in).
local BAND = {
    { 'PART GUITAR', 96, 100 }, { 'PART BASS', 96, 100 }, { 'PART DRUMS', 96, 100 },
    { 'PART KEYS', 96, 100 }, { 'PART REAL_KEYS_X', 48, 72 }, { 'PART VOCALS', 36, 84 },
}

local function Near(sorted, t, tol)
    local lo, hi = 1, #sorted
    while lo <= hi do
        local mid = (lo + hi) // 2
        local v = sorted[mid]
        if math.abs(v - t) <= tol then return true end
        if v < t then lo = mid + 1 else hi = mid - 1 end
    end
    return false
end

local function Uniq(list, tol)
    table.sort(list)
    local out = {}
    for _, v in ipairs(list) do if not out[#out] or v - out[#out] > tol then out[#out + 1] = v end end
    return out
end

-- Pulse grid of a 26 list in QN: '16th' when 20%+ sit on odd 16ths, else '8th'.
local function GridOf(qns)
    local odd = 0
    for _, q in ipairs(qns) do
        local f8 = (q * 2) % 1
        local f16 = (q * 4) % 1
        local on8 = f8 < 0.04 or f8 > 0.96
        local on16 = f16 < 0.08 or f16 > 0.92
        if not on8 and on16 then odd = odd + 1 end
    end
    return (#qns > 0 and odd > 0.2 * #qns) and '16th' or '8th'
end

local T = { [24] = { 0, 0, 0, 0 }, [25] = { 0, 0, 0, 0 }, [26] = { 0, 0, 0, 0 } }
local pulse_ok, pulse_n, songs = 0, 0, 0
local intro_ok, intro_n = 0, 0
local rows = {}

for i, e in ipairs(names) do
    local hold = (i % 5 == 0)
    if mode == 'all' or (mode == 'holdout') == hold then
        local song = SmfReadFile(e.f)
        local ev = song and SmfFindTrack(song, 'EVENTS')
        if ev then
            local tp = song.tpqn
            local off = { [24] = {}, [25] = {}, [26] = {} }
            for _, n in ipairs(ev.notes) do
                if off[n.pitch] then table.insert(off[n.pitch], n.tick / tp) end
            end
            local end_qn
            for _, t in ipairs(SmfTexts(ev)) do
                if t.text == '[end]' then end_qn = t.tick / tp end
            end
            if #off[26] > 0 and end_qn then
                songs = songs + 1
                local tol = TOL_TICKS / tp
                for p in pairs(off) do off[p] = Uniq(off[p], tol) end

                local kicks, snares, hits = {}, {}, {}
                local dr = SmfFindTrack(song, 'PART DRUMS')
                if dr then
                    for _, n in ipairs(dr.notes) do
                        if n.pitch >= 72 and n.pitch <= 76 then
                            hits[#hits + 1] = n.tick / tp
                            if n.pitch == 72 then kicks[#kicks + 1] = n.tick / tp end
                            if n.pitch == 73 then snares[#snares + 1] = n.tick / tp end
                        end
                    end
                end
                kicks, snares, hits = Uniq(kicks, tol), Uniq(snares, tol), Uniq(hits, tol)
                local first_tick = math.huge
                for _, b in ipairs(BAND) do
                    local trk = SmfFindTrack(song, b[1])
                    if trk then
                        for _, n in ipairs(trk.notes) do
                            if n.pitch >= b[2] and n.pitch <= b[3] and n.tick < first_tick then first_tick = n.tick end
                        end
                    end
                end
                local first_note_qn, first_bar_qn, next_bar_qn
                if first_tick < math.huge then
                    first_note_qn = first_tick / tp
                    local timing = SmfSongTiming(song)
                    first_bar_qn = first_note_qn - timing.BarPos(first_tick)
                    next_bar_qn = first_bar_qn + timing.BarLen(first_tick)
                end

                -- QN-weighted median tempo over the song (start to [end]).
                local map = SmfTempoMap(song)
                local bpms = {}
                for k, seg in ipairs(map) do
                    local s = seg.tick / tp
                    local nx = map[k + 1] and map[k + 1].tick / tp or end_qn
                    local w = math.floor(math.max(0, math.min(nx, end_qn) - s))
                    for _ = 1, w do bpms[#bpms + 1] = 60e6 / seg.uspqn end
                end
                table.sort(bpms)
                local bpm = bpms[#bpms // 2 + 1] or (60e6 / map[1].uspqn)

                local notes, info = MetronomePlan({
                    start_qn = 0, end_qn = end_qn, median_bpm = bpm,
                    kicks = kicks, snares = snares, hits = hits,
                    first_note_qn = first_note_qn, first_bar_qn = first_bar_qn, next_bar_qn = next_bar_qn,
                }, { pulse = 'auto', intro = os.getenv('METRONOME_INTRO') or 'audio' })
                local gen = { [24] = {}, [25] = {}, [26] = {} }
                for _, n in ipairs(notes) do table.insert(gen[n.pitch], n.qn) end

                local row = { n = e.n, bpm = bpm }
                for _, p in ipairs({ 24, 25, 26 }) do
                    local a, c = 0, 0
                    for _, q in ipairs(off[p]) do if Near(gen[p], q, tol) then a = a + 1 end end
                    for _, q in ipairs(gen[p]) do if Near(off[p], q, tol) then c = c + 1 end end
                    local t = T[p]
                    t[1], t[2], t[3], t[4] = t[1] + a, t[2] + #off[p], t[3] + c, t[4] + #gen[p]
                    local rec = #off[p] > 0 and a / #off[p] or 1
                    local pre = #gen[p] > 0 and c / #gen[p] or 1
                    row[p] = (rec + pre) > 0 and 2 * rec * pre / (rec + pre) or 0
                end
                -- The intro: every 26 before the band's first note, exactly as official.
                if first_note_qn then
                    local a, b = {}, {}
                    for _, q in ipairs(off[26]) do if q < first_note_qn - tol then a[#a + 1] = q end end
                    for _, q in ipairs(gen[26]) do if q < first_note_qn - tol then b[#b + 1] = q end end
                    local same = #a == #b
                    for _, q in ipairs(a) do if not Near(b, q, tol) then same = false end end
                    intro_n = intro_n + 1
                    if same then intro_ok = intro_ok + 1 end
                    if not same and os.getenv('METRONOME_INTRO_MISSES') then
                        local function J(l) local o = {} for k2 = 1, math.min(#l, 10) do o[k2] = ('%g'):format(math.floor(l[k2] * 4 + 0.5) / 4) end return table.concat(o, ' ') .. (#l > 10 and ' ...' or '') end
                        print(('  MISS %-24s first note %g  official [%s]  ours [%s]'):format(e.n, math.floor(first_note_qn * 4 + 0.5) / 4, J(a), J(b)))
                    end
                end
                local og = GridOf(off[26])
                row.grid = og .. (og == info.pulse and '' or ' (generated ' .. info.pulse .. ')')
                pulse_n = pulse_n + 1
                if og == info.pulse then pulse_ok = pulse_ok + 1 end
                rows[#rows + 1] = row
            end
        end
    end
end

print(('%s: %d songs'):format(mode, songs))
for _, p in ipairs({ 24, 25, 26 }) do
    local t = T[p]
    local rec, pre = t[1] / math.max(1, t[2]), t[3] / math.max(1, t[4])
    print(('  %d  recall %5.1f%%  precision %5.1f%%  F1 %5.1f'):format(p, 100 * rec, 100 * pre,
        100 * 2 * rec * pre / math.max(1e-9, rec + pre)))
end
print(('  pulse grid right: %d / %d (%.1f%%)'):format(pulse_ok, pulse_n, 100 * pulse_ok / math.max(1, pulse_n)))
print(('  intro (26 before the band) exactly right: %d / %d (%.1f%%)'):format(intro_ok, intro_n, 100 * intro_ok / math.max(1, intro_n)))

if list_songs then
    table.sort(rows, function(a, b) return a[26] < b[26] end)
    for _, rw in ipairs(rows) do
        print(('  %-28s %5.0f bpm  24 %.2f  25 %.2f  26 %.2f  %s'):format(rw.n, rw.bpm, rw[24], rw[25], rw[26], rw.grid))
    end
end
