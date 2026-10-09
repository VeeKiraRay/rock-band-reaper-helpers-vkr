-- Compare Difficulty > Generate's Hard with a hand-made Hard, bar by bar. Plain Lua 5.4:
--
--   lua dev/tools/generate_compare_hand_offline.lua <source.mid> <hand.mid> [gtr|bass|keys] [from_bar to_bar]
--
-- Plans Hard from <source.mid>'s Expert exactly as the "Hard" button would (Auto options;
-- Bass and Keys follow Guitar's busy bars) and compares it with the Hard tier of
-- <hand.mid> - a copy of the song whose Hard someone reduced by hand to show what the
-- generator should do. Per bar: note counts, how many generated notes sit where the hand
-- put one, and how many of those also have the hand's colors; bars that differ are printed
-- in full. Positions are in 1/24 quarter notes from the bar line (6 = 16th, 8 = 8th
-- triplet, 12 = 8th).
--
-- Without a bar range, every bar where the hand's Hard differs from the generated one is
-- listed. Use it when designing a rule from a hand reduction, and afterwards to check the
-- rule still matches it.

local _self = (arg and arg[0] or ''):gsub('\\', '/')
if not _self:match('^%a:') and not _self:match('^/') then _self = './' .. _self end
local _root = _self:match('^(.*/)dev/tools/[^/]+$') or './'
local M     = _root .. 'rock_band_general_helper_vkr/'

r = {}  -- the rule tables only touch r inside functions this tool never calls

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/tools/smf_chart_events.lua')
dofile(M .. 'actions_difficulty_shared.lua')
dofile(M .. 'actions_difficulty_gtrbass.lua')
dofile(M .. 'actions_difficulty_5k.lua')
dofile(M .. 'difficulty_generate_params.lua')
dofile(M .. 'difficulty_generate_overlaps.lua')
dofile(M .. 'difficulty_generate_retime.lua')
dofile(M .. 'difficulty_generate_colors.lua')
dofile(M .. 'difficulty_generate_rhythm.lua')
dofile(M .. 'difficulty_generate_5lane.lua')
dofile(M .. 'difficulty_generate_prokeys.lua')
dofile(M .. 'difficulty_generate_hopo.lua')

local PARTS = {
    gtr  = { track = 'PART GUITAR', kind = 'gb' },
    bass = { track = 'PART BASS',   kind = 'gb' },
    keys = { track = 'PART KEYS',   kind = 'k5' },
}
local COLORS = { [0] = 'G', 'R', 'Y', 'B', 'O' }

local src_path, hand_path, key = arg[1], arg[2], arg[3] or 'gtr'
local from_bar, to_bar = tonumber(arg[4]), tonumber(arg[5])
if not src_path or not hand_path or not PARTS[key] then
    print('usage: lua dev/tools/generate_compare_hand_offline.lua <source.mid> <hand.mid> [gtr|bass|keys] [from_bar to_bar]')
    return
end
local part = PARTS[key]

local function Load(path)
    local song = assert(SmfReadFile(path), 'could not read ' .. path)
    return song, SmfSongTiming(song)
end
local song, timing = Load(src_path)
local hsong, htiming = Load(hand_path)
local trk, htrk = SmfFindTrack(song, part.track), SmfFindTrack(hsong, part.track)
if not trk or not htrk then print('no ' .. part.track .. ' track in both files'); return end

-- Bass and Keys follow Guitar's busy bars, as the action does.
local busy_ref
local gtr = key ~= 'gtr' and SmfFindTrack(song, 'PART GUITAR')
if gtr then
    local gx = SmfTierEvents(gtr, 96, song.tpqn, timing, { skip_zero = true })
    if #gx > 0 then busy_ref = select(2, Gen5PlanTier('gb', 'H', gx)).busy_bars end
end
-- Marker spans (force-HOPO lo+5, force-strum lo+6) of one tier, in QN.
local function Spans(t, pitch, tpqn)
    local out = {}
    for _, n in ipairs(SmfNotesInRange(t, pitch, pitch)) do
        out[#out + 1] = { qn = n.tick / tpqn, qn_e = (n.tick + n.len) / tpqn }
    end
    return out
end
local x = SmfTierEvents(trk, 96, song.tpqn, timing, { skip_zero = true })
if part.kind == 'gb' then Gen5MarkHopos(x, Spans(trk, 101, song.tpqn), Spans(trk, 102, song.tpqn)) end
local gen = Gen5PlanTier(part.kind, 'H', x, { busy_ref = busy_ref })
local hand = SmfTierEvents(htrk, 84, hsong.tpqn, htiming)

-- bar number -> { start = bar start QN, x = {...}, gen = {...}, hand = {...} }
local bars = {}
local function Bar(qn, tm, tpqn)
    local tick = math.floor(qn * tpqn + 0.5)
    local n = tm.BarNumber(tick)
    bars[n] = bars[n] or { start = qn - tm.BarPos(tick), x = {}, gen = {}, hand = {} }
    return bars[n]
end
for _, ev in ipairs(x)    do table.insert(Bar(ev.qn, timing, song.tpqn).x, ev) end
for _, ev in ipairs(gen)  do table.insert(Bar(ev.qn, timing, song.tpqn).gen, ev) end
for _, ev in ipairs(hand) do table.insert(Bar(ev.qn, htiming, hsong.tpqn).hand, ev) end

local function Shape(ev)
    local s = {}
    for _, o in ipairs(ev.offs) do s[#s + 1] = COLORS[o] or '?' end
    return table.concat(s)
end
local function Pos(ev, b) return math.floor((ev.qn - b.start) * 24 + 0.5) end
local function Row(list, b)
    local cells = {}
    for _, ev in ipairs(list) do cells[#cells + 1] = ('%d:%s'):format(Pos(ev, b), Shape(ev)) end
    return table.concat(cells, ' ')
end

local nums = {}
for n in pairs(bars) do
    if (not from_bar or n >= from_bar) and (not to_bar or n <= to_bar) then nums[#nums + 1] = n end
end
table.sort(nums)

local t_hand, t_gen, t_pos, t_col, shown = 0, 0, 0, 0, 0
for _, n in ipairs(nums) do
    local b = bars[n]
    local g, h = Row(b.gen, b), Row(b.hand, b)
    local at = {}
    for _, ev in ipairs(b.hand) do at[Pos(ev, b)] = Shape(ev) end
    local pos, col = 0, 0
    for _, ev in ipairs(b.gen) do
        local want = at[Pos(ev, b)]
        if want then
            pos = pos + 1
            if want == Shape(ev) then col = col + 1 end
        end
    end
    t_hand, t_gen, t_pos, t_col = t_hand + #b.hand, t_gen + #b.gen, t_pos + pos, t_col + col
    if from_bar or g ~= h then
        shown = shown + 1
        print(('bar %d  X=%d gen=%d hand=%d  same position %d, and colors %d%s'):format(
            n, #b.x, #b.gen, #b.hand, pos, col, g == h and '  SAME' or ''))
        if g ~= h then
            print('   X    ' .. Row(b.x, b))
            print('   gen  ' .. g)
            print('   hand ' .. h)
        end
    end
end
if shown == 0 then print('the generated Hard equals the hand Hard in every bar') end
print(('total: hand %d notes, generated %d; %d at the hand\'s positions, %d with its colors too'):format(
    t_hand, t_gen, t_pos, t_col))

-- Force-HOPO markers on Hard (pitch 89): generated vs the hand's, inside the bar range.
if part.kind == 'gb' then
    local function InRange(qn)
        local n = timing.BarNumber(math.floor(qn * song.tpqn + 0.5))
        return (not from_bar or n >= from_bar) and (not to_bar or n <= to_bar)
    end
    local function Where(qn)
        local tick = math.floor(qn * song.tpqn + 0.5)
        return ('bar %d pos %d'):format(timing.BarNumber(tick), math.floor(timing.BarPos(tick) * 24 + 0.5))
    end
    local function List(spans)
        local out = {}
        for _, sp in ipairs(spans) do
            if InRange(sp.qn) then out[#out + 1] = ('%s -> %s'):format(Where(sp.qn), Where(sp.qn_e)) end
        end
        return out
    end
    local g, h = List(Gen5ForceHopoSpans(gen)), List(Spans(htrk, 89, hsong.tpqn))
    print(('force-HOPO markers on Hard: generated %d, hand %d%s'):format(#g, #h,
        table.concat(g, '|') == table.concat(h, '|') and '  SAME' or ''))
    for _, l in ipairs(g) do print('   gen  ' .. l) end
    for _, l in ipairs(h) do print('   hand ' .. l) end
end
