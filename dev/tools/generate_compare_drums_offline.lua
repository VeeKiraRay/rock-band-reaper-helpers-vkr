-- Compare Difficulty > Generate's Drums with the tiers already in a song, bar by bar.
-- Plain Lua 5.4:
--
--   lua dev/tools/generate_compare_drums_offline.lua <song.mid> [H|M|E|chain] [from_bar to_bar] [rewrite|auto|thin] [beats|hands] [show]
--
-- show: no comparison - print every bar in the range as Generate's chain makes it, one row
-- per tier (Expert, Hard, Medium, Easy), with the file's own tier under it wherever it
-- differs, and the bar's tempo, section and markers (fill, roll, disco flip). The quickest
-- way to answer "why did Generate do this here?". Options as for chain (default fast runs:
-- GEN5_PARAMS.fast_runs_default; "Hard 8th runs" Auto; "Drums Medium" Beats; "Drums fast 8ths"
-- GEN_DRUMS_PARAMS.lower_eighth_hands_default unless beats|hands is given).
--
-- H / M / E: that tier planned from the file's own tier above (what the button does when a
-- run starts at that tier). chain (default): Expert > Hard > Medium > Easy on generated
-- tiers only (the "Hard, Medium, Easy" run). Each generated tier is compared with the
-- file's: per bar the note counts, how many generated hits sit where the file has one, and
-- how many of those have the same gems; bars that differ are printed in full.
--
-- Positions are in 1/24 quarter notes from the bar line (6 = 16th, 8 = 8th triplet,
-- 12 = 8th). Gems: K kick, R snare, Y B G cymbals, y b g toms (under a Pro Drums tom
-- marker).

local _self = (arg and arg[0] or ''):gsub('\\', '/')
if not _self:match('^%a:') and not _self:match('^/') then _self = './' .. _self end
local _root = _self:match('^(.*/)dev/tools/[^/]+$') or './'
local M     = _root .. 'rock_band_general_helper_vkr/'

r = {}  -- the rule tables only touch r inside functions this tool never calls

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/tools/smf_chart_events.lua')
dofile(M .. 'actions_difficulty_shared.lua')
dofile(M .. 'actions_difficulty_drums_checks.lua')
dofile(M .. 'difficulty_generate_params.lua')
dofile(M .. 'difficulty_generate_retime.lua')
dofile(M .. 'difficulty_generate_drums.lua')

local LO    = { X = 96, H = 84, M = 72, E = 60 }
local UPPER = { H = 'X', M = 'H', E = 'M' }
local GEMS  = { [0] = 'K', 'R', 'Y', 'B', 'G' }

local path = arg[1]
local mode, from_bar, to_bar, fast, show, eighth = 'chain', nil, nil, nil, false, nil
for k = 2, #arg do
    local a = arg[k]
    if a == 'show' then show = true
    elseif a == 'H' or a == 'M' or a == 'E' or a == 'chain' then mode = a
    elseif a == 'rewrite' or a == 'auto' or a == 'thin' then fast = a
    elseif a == 'beats' or a == 'hands' then eighth = a
    elseif tonumber(a) then
        if not from_bar then from_bar = tonumber(a) else to_bar = tonumber(a) end
    end
end
if not path then
    print('usage: lua dev/tools/generate_compare_drums_offline.lua <song.mid> [H|M|E|chain] [from_bar to_bar] [rewrite|auto|thin] [beats|hands] [show]')
    return
end

local song   = assert(SmfReadFile(path), 'could not read ' .. path)
local timing = SmfSongTiming(song)
local trk    = SmfFindTrack(song, 'PART DRUMS')
if not trk then print('no PART DRUMS track'); return end
local ctx = SmfDrumsContext(song, trk)
local T = {}
for dl, lo in pairs(LO) do T[dl] = SmfTierEvents(trk, lo, song.tpqn, timing, { skip_zero = true }) end
local opts = { fast_runs = fast, ctx = ctx, eighth_hands = eighth }

-- c: the marker context (the file's, or the one Generate leaves - Hard's rewrite may
-- change the tom markers).
local function InTom(o, qn, c)
    for _, s in ipairs((c or ctx).toms[o] or {}) do
        if qn >= s.qn - 0.02 and qn < s.qn_e - 0.02 then return true end
    end
    return false
end
local function Shape(ev, c)
    local s = {}
    for _, o in ipairs(ev.offs) do
        local g = GEMS[o] or '?'
        if o >= 2 and InTom(o, ev.qn, c) then g = g:lower() end
        s[#s + 1] = g
    end
    return table.concat(s)
end

-- The tiers to compare: { dl, upper events, generated events, log }.
local runs = {}
if mode == 'chain' then
    local up = T.X
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        opts.expert = dl == 'M' and T.X or nil   -- Medium: fills Hard rewrote, from Expert
        local out, log = GenDrumsPlanTier(dl, up, opts)
        runs[#runs + 1] = { dl = dl, upper = up, gen = out, log = log }
        up = out
        opts.ctx = log.ctx
    end
else
    opts.expert = mode == 'M' and T.X or nil
    local out, log = GenDrumsPlanTier(mode, T[UPPER[mode]], opts)
    runs[1] = { dl = mode, upper = T[UPPER[mode]], gen = out, log = log }
end

if show then
    -- Every tier of the chain, bar by bar.
    local tiers = { { 'X', T.X } }
    for _, run in ipairs(runs) do tiers[#tiers + 1] = { run.dl, run.gen } end
    local bars = {}
    local function Bar(qn)
        local tick = math.floor(qn * song.tpqn + 0.5)
        local n = timing.BarNumber(tick)
        bars[n] = bars[n] or { start = qn - timing.BarPos(tick), rows = {}, file = {} }
        return bars[n]
    end
    for _, t in ipairs(tiers) do
        for _, ev in ipairs(t[2]) do
            local b = Bar(ev.qn)
            b.rows[t[1]] = b.rows[t[1]] or {}
            table.insert(b.rows[t[1]], ev)
            b.bpm = b.bpm or ev.bpm
        end
    end
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        for _, ev in ipairs(T[dl]) do
            local b = Bar(ev.qn)
            b.file[dl] = b.file[dl] or {}
            table.insert(b.file[dl], ev)
        end
    end
    local gen_ctx = runs[#runs].log.ctx
    local function Row(list, b, c)
        local cells = {}
        for _, ev in ipairs(list or {}) do
            cells[#cells + 1] = ('%d:%s'):format(math.floor((ev.qn - b.start) * 24 + 0.5), Shape(ev, c))
        end
        return table.concat(cells, ' ')
    end
    local function Section(qn)
        local name
        for _, sec in ipairs(ctx.sections) do if sec.qn <= qn + 0.02 then name = sec.name else break end end
        return name
    end
    local function Marks(b)
        local m = {}
        local function Over(spans, label)
            for _, sp in ipairs(spans) do
                if sp.qn < b.start + 4 - 0.02 and sp.qn_e > b.start + 0.02 then m[#m + 1] = label; return end
            end
        end
        Over(ctx.fills, 'fill lane'); Over(ctx.rolls, 'roll lane'); Over(ctx.disco, 'disco flip')
        return #m > 0 and ('  [' .. table.concat(m, ', ') .. ']') or ''
    end
    local nums = {}
    for n in pairs(bars) do
        if (not from_bar or n >= from_bar) and (not to_bar or n <= to_bar) then nums[#nums + 1] = n end
    end
    table.sort(nums)
    for _, n in ipairs(nums) do
        local b = bars[n]
        print(('bar %d  %.0f BPM%s%s'):format(n, b.bpm or 0, Section(b.start) and ('  section ' .. Section(b.start)) or '', Marks(b)))
        for _, t in ipairs(tiers) do
            local dl = t[1]
            local g = Row(b.rows[dl], b, gen_ctx)
            print(('  %-6s %s'):format(({ X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' })[dl], g))
            if dl ~= 'X' and b.file[dl] and Row(b.file[dl], b) ~= g then
                print(('  %-6s %s'):format('  file', Row(b.file[dl], b)))
            end
        end
    end
    for _, run in ipairs(runs) do
        local l = run.log
        local extra = {}
        for _, k in ipairs({ 'unflipped', 'rolls', 'runs_broken', 'sandwiched', 'drum_changes', 'two_hand_ands',
                             'before_crash', 'tom_before_crash', 'hat_drops', 'tom_pairs', 'lone_ands', 'eighth_hands', 'expert_runs' }) do
            if (l[k] or 0) > 0 then extra[#extra + 1] = ('%s %d'):format(k, l[k]) end
        end
        if #l.retimed_bars > 0 then extra[#extra + 1] = ('retimed bars %d'):format(#l.retimed_bars) end
        for _, m in ipairs(l.tom_markers or {}) do
            local bars = {}
            for _, bq in ipairs(m.bars) do
                bars[#bars + 1] = tostring(timing.BarNumber(math.floor(bq * song.tpqn + 0.5)))
            end
            extra[#extra + 1] = ('%s tom marker %.3f-%.3f QN (bar %s, replaces %d)'):format(
                GEMS[m.o], m.qn, m.qn_e, table.concat(bars, '/'), #m.replaces)
        end
        for _, bq in ipairs(l.tom_conflict_bars or {}) do
            extra[#extra + 1] = ('bar %d run thinned (a cymbal under the tom marker it needs)'):format(
                timing.BarNumber(math.floor(bq * song.tpqn + 0.5)))
        end
        if l.hard_fallback then extra[#extra + 1] = 'Hard fallback fired' end
        if l.fallback then extra[#extra + 1] = 'Medium fallback fired' end
        print(('%s: kept %d of %d onsets, %d of %d notes%s'):format(run.dl, l.kept, l.upper, l.notes, l.upper_notes,
            #extra > 0 and ('; ' .. table.concat(extra, ', ')) or ''))
    end
    return
end

for _, run in ipairs(runs) do
    local file = T[run.dl]
    print(('==== %s (%s from %s%s) ===='):format(run.dl, mode == 'chain' and 'chain' or 'file',
        UPPER[run.dl], mode == 'chain' and run.dl ~= 'H' and ' as generated' or ''))
    local bars = {}
    local function Bar(qn)
        local tick = math.floor(qn * song.tpqn + 0.5)
        local n = timing.BarNumber(tick)
        bars[n] = bars[n] or { start = qn - timing.BarPos(tick), up = {}, gen = {}, file = {} }
        return bars[n]
    end
    for _, ev in ipairs(run.upper) do table.insert(Bar(ev.qn).up, ev) end
    for _, ev in ipairs(run.gen)   do table.insert(Bar(ev.qn).gen, ev) end
    for _, ev in ipairs(file)      do table.insert(Bar(ev.qn).file, ev) end
    local function Pos(ev, b) return math.floor((ev.qn - b.start) * 24 + 0.5) end
    local function Row(list, b, c)
        local cells = {}
        for _, ev in ipairs(list) do cells[#cells + 1] = ('%d:%s'):format(Pos(ev, b), Shape(ev, c)) end
        return table.concat(cells, ' ')
    end
    local nums = {}
    for n in pairs(bars) do
        if (not from_bar or n >= from_bar) and (not to_bar or n <= to_bar) then nums[#nums + 1] = n end
    end
    table.sort(nums)
    local t_file, t_gen, t_pos, t_same, differ = 0, 0, 0, 0, 0
    for _, n in ipairs(nums) do
        local b = bars[n]
        local g, f = Row(b.gen, b, run.log.ctx), Row(b.file, b)
        local at = {}
        for _, ev in ipairs(b.file) do at[Pos(ev, b)] = Shape(ev) end
        local pos, same = 0, 0
        for _, ev in ipairs(b.gen) do
            local want = at[Pos(ev, b)]
            if want then
                pos = pos + 1
                if want == Shape(ev, run.log.ctx) then same = same + 1 end
            end
        end
        t_file, t_gen, t_pos, t_same = t_file + #b.file, t_gen + #b.gen, t_pos + pos, t_same + same
        if g ~= f then
            differ = differ + 1
            print(('bar %d  %s=%d gen=%d file=%d  same position %d, same gems %d'):format(
                n, UPPER[run.dl], #b.up, #b.gen, #b.file, pos, same))
            print('   ' .. UPPER[run.dl] .. '    ' .. Row(b.up, b))
            print('   gen  ' .. g)
            print('   file ' .. f)
        end
    end
    print(('%s: %d of %d bars differ; file %d hits, generated %d; %d at the file\'s positions, %d with its gems too'):format(
        run.dl, differ, #nums, t_file, t_gen, t_pos, t_same))
    local l = run.log
    print(('   log: kept %d of %d onsets, %d of %d notes; unflipped %d, rolls %d, rewritten bars %d, 8th runs broken %d, Easy sections kick+snare %d / 2-hand %d'):format(
        l.kept, l.upper, l.notes, l.upper_notes, l.unflipped, l.rolls, #l.retimed_bars, l.runs_broken,
        l.easy_types.ks, l.easy_types.hands))
    print('')
end
