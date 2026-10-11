-- Offline evaluation of the Difficulty > Generate Drums planner (difficulty_generate_drums.lua)
-- against the official RB3 DLC charts. Plain Lua 5.4, no REAPER:
--
--   lua dev/calibration/run_generate_eval_drums_offline.lua [fast_runs] [holdout]
--
-- fast_runs: rewrite | auto | thin (default GEN5_PARAMS.fast_runs_default). 'thin' is the
-- official-like behaviour (no note ever moves); 'rewrite' moves fill runs, which then
-- never line up with an official onset - expect a lower Hard F1 there.
--
-- For each tier it feeds the OFFICIAL upper tier to the planner (X>H, H>M, M>E) and
-- compares the result with the official lower tier: onset precision / recall / F1, and per
-- lane (Kick, Red, Yellow, Blue, Green) note recall and precision. A "chain" row runs
-- Expert>Hard>Medium>Easy on generated tiers only, which is what the button does. Plain
-- Copy (keep every onset) is the baseline.
--
-- It also counts Validate's errors (CollectDrumsChecks, actions_difficulty_drums_checks.lua)
-- re-implemented here in quarter notes - for the generated tiers (must be 0) and, for
-- reference, the official ones.
--
-- THE HOLD-OUT (difficulty_holdout.lua) is excluded by default; see
-- run_generate_eval_offline.lua for the rule. Writes generate_eval_drums_report.txt beside
-- this script (gitignored). Song shortnames and derived numbers only.

local _dir  = (arg and arg[0] or ''):match('^(.+[\\/])') or './'
local _root = _dir .. '../../'
local FAST, MODE, DIAG = nil, 'dev', false
for _, a in ipairs(arg or {}) do
    if a == 'holdout' then MODE = 'holdout' elseif a == 'diag' then DIAG = true else FAST = a end
end

r = {}
dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/tools/smf_chart_events.lua')
dofile(_dir  .. 'difficulty_holdout.lua')
dofile(_root .. 'rock_band_general_helper_vkr/actions_difficulty_shared.lua')
dofile(_root .. 'rock_band_general_helper_vkr/actions_difficulty_drums_checks.lua')   -- DRUMS_RULES
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_params.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_retime.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_drums.lua')

-- diag: keep rate by lane x beat class, generated vs official, from the same upper tier.
local KEEP, MATCH = {}, 0.05
-- diag: Easy bar types (KS kick+snare, HANDS no kick, MIX both), generated x official.
local BARTYPE = {}
local function BarTypes(evs)
    local bars = {}
    for _, ev in ipairs(evs) do
        local key = ('%.3f'):format(ev.qn - ev.bar_qn)
        local b = bars[key] or { k = false, h = false }
        bars[key] = b
        for _, o in ipairs(ev.offs) do
            if o == 0 then b.k = true elseif o >= 2 then b.h = true end
        end
    end
    local out = {}
    for key, b in pairs(bars) do out[key] = b.k and (b.h and 'MIX' or 'KS') or (b.h and 'HANDS' or 'SNARE') end
    return out
end
local function CompareBarTypes(gen, off)
    local g, o = BarTypes(gen), BarTypes(off)
    for key, t in pairs(o) do
        local k = (g[key] or 'none') .. ' / ' .. t
        BARTYPE[k] = (BARTYPE[k] or 0) + 1
    end
end
local function KeepRates(dl, upper, gen, off)
    local function Set(list)
        local s = {}
        for _, ev in ipairs(list) do
            local key = math.floor(ev.qn / MATCH + 0.5)
            s[key] = ev
        end
        return function(qn)
            local k = math.floor(qn / MATCH + 0.5)
            return s[k] or s[k - 1] or s[k + 1]
        end
    end
    local G, O = Set(gen), Set(off)
    for _, u in ipairs(upper) do
        local c = Gen5BeatClass(u)
        local b = (u.bpm or 120) < 140 and 'slow' or 'fast'
        local g, o = G(u.qn), O(u.qn)
        for _, x in ipairs(u.offs) do
            for _, key in ipairs({ dl .. ' ' .. x .. ' ' .. c, dl .. ' ' .. x .. ' ' .. c .. ' ' .. b }) do
                local t = KEEP[key] or { n = 0, g = 0, o = 0 }
                KEEP[key] = t
                t.n = t.n + 1
                local function HasX(ev) if not ev then return false end for _, y in ipairs(ev.offs) do if y == x then return true end end return false end
                if HasX(g) then t.g = t.g + 1 end
                if HasX(o) then t.o = t.o + 1 end
            end
        end
    end
end

local CORPUS = _root .. '_external_docs/all_rb3_dlc_reference_songs/'
local OUT    = _dir .. 'generate_eval_drums_report.txt'
local LO     = { X = 96, H = 84, M = 72, E = 60 }
local UPPER  = { H = 'X', M = 'H', E = 'M' }
local LANES  = { [0] = 'K', 'R', 'Y', 'B', 'G' }

local R      = DRUMS_RULES

local function MatchOnsets(gen, off)
    local pairs_, j = {}, 1
    for i, g in ipairs(gen) do
        while j <= #off and off[j].qn < g.qn - MATCH do j = j + 1 end
        if j <= #off and math.abs(off[j].qn - g.qn) <= MATCH then
            pairs_[#pairs_ + 1] = { i, j }
            j = j + 1
        end
    end
    return pairs_
end

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end
local function Has(ev, o) for _, x in ipairs(ev.offs) do if x == o then return true end end return false end

-- Validate's error rules in quarter notes (the advisory fill-kick check is left out).
-- Returns { rule = count }.
local function Violations(dl, evs, ctx)
    local v = {}
    local function Inc(k) v[k] = (v[k] or 0) + 1 end
    local low = dl == 'M' or dl == 'E'
    local kicks_bar = {}
    for i, ev in ipairs(evs) do
        if low and #ev.offs >= 3 then Inc('chord_size') end
        if low and Has(ev, 0) then
            if (ev.bpm or 120) > R.kick_grid_bpm and not NearInt(ev.qn, 0.05) then Inc('kick_grid') end
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            local b = kicks_bar[key] or { n = 0, bpm = ev.bpm }
            kicks_bar[key] = b
            b.n = b.n + 1
        end
        if dl == 'M' and #ev.offs == 2 and ev.offs[1] == 0 and ev.offs[2] == 4 and not NearInt(ev.qn, 0.05) then
            Inc('crash_kick')
        end
        if dl == 'E' and #ev.offs >= 2 and Has(ev, 0) then Inc('kick_pairing') end
        if dl ~= 'X' and #ev.offs == 2 and ev.offs[2] == 4 and (ev.offs[1] == 2 or ev.offs[1] == 3) then
            local pv = evs[i - 1]
            if not pv or ev.qn - pv.qn < 0.95 then Inc('double_crash') end
        end
    end
    for _, b in pairs(kicks_bar) do
        if b.n > 1 and (b.bpm or 120) >= R.kick_per_measure_bpm then Inc('kick_per_measure') end
    end
    if dl ~= 'X' then
        local lim = dl == 'H' and R.general_hard_8th_bpm or R.general_medium_8th_bpm
        local i = 1
        while i < #evs do
            local j = i
            while j < #evs and math.abs(evs[j + 1].qn - evs[j].qn - 0.5) <= 0.025 do j = j + 1 end
            if j - i + 1 >= R.min_run_len then
                if (evs[i].bpm or 120) >= lim then Inc('density') end
                i = j + 1
            else
                i = i + 1
            end
        end
        for _, roll in ipairs(ctx.rolls) do
            local gems, first, last, n = 0, nil, nil, 0
            for _, ev in ipairs(evs) do
                if ev.qn >= roll.qn - 0.004 and ev.qn <= roll.qn_e + 0.004 then
                    gems = gems + #ev.offs; n = n + 1
                    first = first or ev; last = ev
                end
            end
            if gems > 0 and gems % 2 == 1 then Inc('roll_even') end
            if n >= 2 then
                local avg, bpm = (last.qn - first.qn) / (n - 1), first.bpm or 120
                if (dl == 'H' and bpm >= R.roll_hard_16th_bpm and avg < 0.375)
                   or (dl == 'M' and avg < R.roll_medium_max_qn - 0.01)
                   or (dl == 'E' and ((bpm >= R.roll_easy_quarter_bpm and avg < 0.99) or avg < R.roll_medium_max_qn - 0.01)) then
                    Inc('roll_density')
                end
            end
        end
    end
    return v
end

local function NewStats() return { tp = 0, gen = 0, off = 0, lane = {}, viol = {}, viol_off = {}, notes_gen = 0, notes_off = 0 } end
local function Accumulate(st, dl, gen, off, ctx, count_official)
    local pr = MatchOnsets(gen, off)
    st.tp, st.gen, st.off = st.tp + #pr, st.gen + #gen, st.off + #off
    for o = 0, 4 do st.lane[o] = st.lane[o] or { tp = 0, gen = 0, off = 0 } end
    for _, ev in ipairs(gen) do
        for _, o in ipairs(ev.offs) do st.lane[o].gen = st.lane[o].gen + 1 end
        st.notes_gen = st.notes_gen + #ev.offs
    end
    for _, ev in ipairs(off) do
        for _, o in ipairs(ev.offs) do st.lane[o].off = st.lane[o].off + 1 end
        st.notes_off = st.notes_off + #ev.offs
    end
    for _, p in ipairs(pr) do
        local g, o = gen[p[1]], off[p[2]]
        for _, x in ipairs(g.offs) do if Has(o, x) then st.lane[x].tp = st.lane[x].tp + 1 end end
    end
    for k, n in pairs(Violations(dl, gen, ctx)) do st.viol[k] = (st.viol[k] or 0) + n end
    if count_official then
        for k, n in pairs(Violations(dl, off, ctx)) do st.viol_off[k] = (st.viol_off[k] or 0) + n end
    end
end

local stats = { H = NewStats(), M = NewStats(), E = NewStats(),
                chainH = NewStats(), chainM = NewStats(), chainE = NewStats(),
                copyH = NewStats(), copyM = NewStats(), copyE = NewStats() }
local songs = 0
local per_song = {}

local files, seen = SmfListFiles(CORPUS, '%.mid$'), {}
for _, path in ipairs(files) do
    local name = SmfShortname(path)
    if not name:find('%(') and not seen[name] then
        seen[name] = true
        if (MODE == 'holdout') == DiffIsHeldOut(name) then
            local song = SmfReadFile(path)
            local trk = song and SmfFindTrack(song, 'PART DRUMS')
            if trk then
                local timing = SmfSongTiming(song)
                local T, ok = {}, true
                for dl, lo in pairs(LO) do
                    T[dl] = SmfTierEvents(trk, lo, song.tpqn, timing, { skip_zero = true })
                    if #T[dl] == 0 then ok = false end
                end
                if ok then
                    songs = songs + 1
                    local ctx = SmfDrumsContext(song, trk)
                    local opts = { fast_runs = FAST, ctx = ctx }
                    local viol_song = 0
                    for _, dl in ipairs({ 'H', 'M', 'E' }) do
                        local out = GenDrumsPlanTier(dl, T[UPPER[dl]], opts)
                        Accumulate(stats[dl], dl, out, T[dl], ctx, true)
                        if DIAG then
                            KeepRates(dl, T[UPPER[dl]], out, T[dl])
                            if dl == 'E' then CompareBarTypes(out, T.E) end
                        end
                        Accumulate(stats['copy' .. dl], dl, T[UPPER[dl]], T[dl], ctx, false)
                        for _, n in pairs(Violations(dl, out, ctx)) do viol_song = viol_song + n end
                    end
                    local up = T.X
                    for _, dl in ipairs({ 'H', 'M', 'E' }) do
                        local out = GenDrumsPlanTier(dl, up, opts)
                        Accumulate(stats['chain' .. dl], dl, out, T[dl], ctx, false)
                        up = out
                    end
                    if viol_song > 0 then per_song[#per_song + 1] = { name, viol_song } end
                end
            end
        end
    end
end

local out = {}
local function P(f, ...) out[#out + 1] = select('#', ...) == 0 and f or string.format(f, ...) end
local function F1(st)
    local p = st.tp / math.max(1, st.gen)
    local r_ = st.tp / math.max(1, st.off)
    return 100 * p, 100 * r_, p + r_ > 0 and 200 * p * r_ / (p + r_) or 0
end
P('Drums Generate evaluation - %d %s songs, fast runs: %s', songs, MODE, FAST or GEN5_PARAMS.fast_runs_default)
P('')
P('%-8s %7s %7s %7s  %8s   %s', 'tier', 'prec', 'recall', 'F1', 'notes', 'per lane recall / precision (K R Y B G)')
for _, row in ipairs({ { 'H', 'H' }, { 'M', 'M' }, { 'E', 'E' }, { 'chain H', 'chainH' }, { 'chain M', 'chainM' },
                       { 'chain E', 'chainE' }, { 'copy H', 'copyH' }, { 'copy M', 'copyM' }, { 'copy E', 'copyE' } }) do
    local st = stats[row[2]]
    local p, rc, f = F1(st)
    local lanes = {}
    for o = 0, 4 do
        local l = st.lane[o]
        lanes[#lanes + 1] = ('%s %2.0f/%2.0f'):format(LANES[o], 100 * l.tp / math.max(1, l.off), 100 * l.tp / math.max(1, l.gen))
    end
    P('%-8s %6.1f%% %6.1f%% %6.1f%%  %7.0f%%   %s', row[1], p, rc, f, 100 * st.notes_gen / math.max(1, st.notes_off),
        table.concat(lanes, '  '))
end
P('')
P('Validate errors (generated / official):')
for _, dl in ipairs({ 'H', 'M', 'E' }) do
    local keys, seenk = {}, {}
    for k in pairs(stats[dl].viol) do keys[#keys + 1] = k; seenk[k] = true end
    for k in pairs(stats[dl].viol_off) do if not seenk[k] then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = ('%s %d/%d'):format(k, stats[dl].viol[k] or 0, stats[dl].viol_off[k] or 0) end
    local chain = 0
    for _, n in pairs(stats['chain' .. dl].viol) do chain = chain + n end
    P('  %s: %s   (chain: %d)', dl, #parts > 0 and table.concat(parts, ', ') or 'none', chain)
end
if #per_song > 0 then
    table.sort(per_song, function(a, b) return a[2] > b[2] end)
    local l = {}
    for i = 1, math.min(10, #per_song) do l[#l + 1] = ('%s %d'):format(per_song[i][1], per_song[i][2]) end
    P('  most: %s', table.concat(l, ', '))
end

if DIAG then
    P('')
    P('Keep rate from the upper tier, generated / official, by lane and beat class (n >= 200):')
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        for o = 0, 4 do
            local parts = {}
            for _, c in ipairs({ 'down', 'beat', '8th', '16th', 'trip', 'other' }) do
                for _, b in ipairs({ 'slow', 'fast' }) do
                    local t = KEEP[dl .. ' ' .. o .. ' ' .. c .. ' ' .. b]
                    if t and t.n >= 200 then
                        parts[#parts + 1] = ('%s/%s %2.0f/%2.0f'):format(c, b, 100 * t.g / t.n, 100 * t.o / t.n)
                    end
                end
            end
            P('  %s %s  %s', dl, LANES[o], table.concat(parts, '  '))
        end
    end
    P('')
    P('Easy bar types, generated / official (from the official Medium):')
    local keys = {}
    for k, n in pairs(BARTYPE) do keys[#keys + 1] = { k, n } end
    table.sort(keys, function(a, b) return a[2] > b[2] end)
    for _, x in ipairs(keys) do P('  %-20s %d', x[1], x[2]) end
end

local text = table.concat(out, '\n')
print(text)
local f = io.open(OUT, 'w')
if f then f:write(text, '\n'); f:close() end
