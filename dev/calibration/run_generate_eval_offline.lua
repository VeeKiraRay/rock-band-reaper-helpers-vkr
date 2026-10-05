-- Offline evaluation of the Difficulty > Generate planner (difficulty_generate_5lane.lua)
-- against the official RB3 DLC charts. Plain Lua 5.4, no REAPER:
--
--   lua dev/calibration/run_generate_eval_offline.lua            -- development songs
--   lua dev/calibration/run_generate_eval_offline.lua holdout    -- the hold-out, ONCE
--
-- For Guitar, Bass and Keys it feeds each OFFICIAL upper tier to the planner (X>H, H>M,
-- M>E) and compares the result with the official lower tier: precision and recall of
-- onsets, F1, how often a matched onset got the same colors, and the planner's keep rate by
-- beat position beside the official one. A "chain" row runs Expert>Hard>Medium>Easy on
-- generated tiers only, which is what the button does. Plain Copy (keep every onset) is
-- printed as the baseline the planner has to beat.
--
-- It also counts violations of the rules Validate enforces as errors, re-implemented here
-- in quarter notes (the REAPER-side checks need a project). Those must be 0.
--
-- THE HOLD-OUT (difficulty_holdout.lua) is excluded by default. Tune on the development
-- songs only; run 'holdout' once, when the parameters are final, and report that number.
-- Running it again after changing parameters turns it into a development set.
--
-- Writes generate_eval_report.txt beside this script (gitignored). Song shortnames and
-- derived numbers only.

local _dir  = (arg and arg[0] or ''):match('^(.+[\\/])') or './'
local _root = _dir .. '../../'
local MODE  = arg and arg[1] or 'dev'

r = {}  -- the difficulty modules only touch r inside functions this script never calls

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/tools/smf_chart_events.lua')
dofile(_dir  .. 'difficulty_holdout.lua')
dofile(_root .. 'rock_band_general_helper_vkr/actions_difficulty_shared.lua')
dofile(_root .. 'rock_band_general_helper_vkr/actions_difficulty_gtrbass.lua')
dofile(_root .. 'rock_band_general_helper_vkr/actions_difficulty_5k.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_retime.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_colors.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_generate_5lane.lua')

local CORPUS = _root .. '_external_docs/all_rb3_dlc_reference_songs/'
local OUT    = _dir .. 'generate_eval_report.txt'

local INSTRUMENTS = {
    { key = 'guitar', track = 'PART GUITAR', kind = 'gb', label = 'Guitar' },
    { key = 'bass',   track = 'PART BASS',   kind = 'gb', label = 'Bass'   },
    { key = 'keys',   track = 'PART KEYS',   kind = 'k5', label = 'Keys'   },
}
local LO    = { X = 96, H = 84, M = 72, E = 60 }
local UPPER = { H = 'X', M = 'H', E = 'M' }
local MATCH = 0.05
local CLASSES = { 'down', 'beat', '8th', '16th', 'trip', 'other' }

-- Reading a song: dev/tools/smf_chart_events.lua (SmfSongTiming, SmfTierEvents), shared
-- with the golden-chart test so both read files exactly alike.

----------------------------------------------------------------------
-- Comparison
----------------------------------------------------------------------

-- One-to-one onset matching. Returns matched pairs { gen_index, off_index }.
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

local function SameOffs(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Rule violations Validate reports as errors, in quarter notes.
local function CountViolations(kind, dl, gen)
    local v = 0
    local max_n = kind == 'gb' and GB_MAX_CHORD[dl] or K5_MAX_CHORD[dl]
    for i, ev in ipairs(gen) do
        if #ev.offs > max_n then v = v + 1 end
        if kind == 'gb' and GB_MAX_SPAN[dl] and #ev.offs >= 2
           and ev.offs[#ev.offs] - ev.offs[1] > GB_MAX_SPAN[dl] then v = v + 1 end
        local nx = gen[i + 1]
        if nx then
            if nx.qn < ev.qn_e - 0.005 then v = v + 1 end                    -- overlap
            if kind == 'k5' and K5_MIN_SP[dl] and nx.qn - ev.qn < K5_MIN_SP[dl] * 0.95 then
                v = v + 1                                                     -- spacing
            end
            local floor = DiffReleaseGapQN(dl, ev.bpm)
            if floor and ev.qn_e - ev.qn >= 0.49 and nx.qn >= ev.qn_e
               and nx.qn - ev.qn_e < floor * 0.95 then v = v + 1 end         -- release gap
        end
    end
    return v
end

----------------------------------------------------------------------
-- Aggregation
----------------------------------------------------------------------

AGG = {}
local function Acc(inst, dl)
    AGG[inst] = AGG[inst] or {}
    local a = AGG[inst][dl]
    if not a then
        a = { songs = 0, gen = 0, off = 0, hit = 0, color = 0, viol = 0,
              copy_gen = 0, copy_hit = 0, chain_gen = 0, chain_off = 0, chain_hit = 0,
              cls_n = {}, cls_gen = {}, cls_off = {} }
        AGG[inst][dl] = a
    end
    return a
end

local function KeptByClass(a, upper, gen, off)
    local g = MatchOnsets(upper, gen)
    local o = MatchOnsets(upper, off)
    local gk, ok = {}, {}
    for _, p in ipairs(g) do gk[p[1]] = true end
    for _, p in ipairs(o) do ok[p[1]] = true end
    for i, ev in ipairs(upper) do
        local c = Gen5BeatClass(ev)
        a.cls_n[c]   = (a.cls_n[c] or 0) + 1
        if gk[i] then a.cls_gen[c] = (a.cls_gen[c] or 0) + 1 end
        if ok[i] then a.cls_off[c] = (a.cls_off[c] or 0) + 1 end
    end
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

-- Load every song once: DATA = { { inst, tiers = { X, H, M, E }, song }... }.
-- GTR_X / GTR_H[song]: that song's guitar Expert and official Hard, which Bass and Keys
-- follow (busy_ref on Hard, rhythm_ref on Medium).
local DATA, GTR_X, GTR_H = {}, {}, {}
local files, seen = SmfListFiles(CORPUS, '%.mid$'), {}
local n_songs = 0
for _, path in ipairs(files) do
    local name = SmfShortname(path)
    if not name:find('%(') and not seen[name] then
        seen[name] = true
        if (MODE == 'holdout') == DiffIsHeldOut(name) then
            local song = SmfReadFile(path)
            if song then
                n_songs = n_songs + 1
                local timing = SmfSongTiming(song)
                for _, inst in ipairs(INSTRUMENTS) do
                    local trk = SmfFindTrack(song, inst.track)
                    if trk then
                        local tiers = {}
                        for dl in pairs(LO) do tiers[dl] = SmfTierEvents(trk, LO[dl], song.tpqn, timing) end
                        DATA[#DATA + 1] = { inst = inst, tiers = tiers, song = n_songs }
                        if inst.key == 'guitar' then GTR_X[n_songs], GTR_H[n_songs] = tiers.X, tiers.H end
                    end
                end
            end
        end
    end
end

local function F1(p, rcl) return (p + rcl) > 0 and 2 * p * rcl / (p + rcl) or 0 end

-- Run the planner over DATA with the current GEN5_PARAMS and fill AGG.
-- with_chain: also run the Expert>Hard>Medium>Easy chain (slower; skipped while tuning).
local function Evaluate(with_chain, only_kind, only_dl)
    AGG = {}
    -- Guitar leads Bass and Keys, as in the action: its Hard plan from its Expert (busy
    -- bars) and its Medium (rhythm) - from the official Hard for the per-tier rows, from its
    -- own generated Hard for the chain. Redone each run: the parameters may have changed.
    local refs = {}
    for song, x in pairs(GTR_X) do
        if #x > 0 then
            local gh, hlog = Gen5PlanTier('gb', 'H', x)
            refs[song] = { H = hlog.busy_bars,
                           M_chain = select(2, Gen5PlanTier('gb', 'M', gh)).rhythm_bars,
                           M = GTR_H[song] and #GTR_H[song] > 0
                               and select(2, Gen5PlanTier('gb', 'M', GTR_H[song])).rhythm_bars or nil }
        end
    end
    for _, d in ipairs(DATA) do
        local inst, tiers = d.inst, d.tiers
        local ref = inst.key ~= 'guitar' and refs[d.song] or {}
        local function Opts(dl, chain)
            return { busy_ref = dl == 'H' and ref.H or nil,
                     rhythm_ref = dl == 'M' and (chain and ref.M_chain or ref.M) or nil }
        end
        if not only_kind or inst.kind == only_kind then
            local chain = tiers.X
            for _, dl in ipairs({ 'H', 'M', 'E' }) do
                local upper, off = tiers[UPPER[dl]], tiers[dl]
                if #upper > 0 and #off > 0 and (not only_dl or dl == only_dl) then
                    local a = Acc(inst.key, dl)
                    local gen = Gen5PlanTier(inst.kind, dl, upper, Opts(dl, false))
                    local m = MatchOnsets(gen, off)
                    a.songs = a.songs + 1
                    a.gen, a.off, a.hit = a.gen + #gen, a.off + #off, a.hit + #m
                    for _, p in ipairs(m) do
                        if SameOffs(gen[p[1]].offs, off[p[2]].offs) then a.color = a.color + 1 end
                    end
                    a.viol = a.viol + CountViolations(inst.kind, dl, gen)
                    local cm = MatchOnsets(upper, off)
                    a.copy_gen, a.copy_hit = a.copy_gen + #upper, a.copy_hit + #cm
                    KeptByClass(a, upper, gen, off)
                    if with_chain and chain and #chain > 0 then
                        chain = Gen5PlanTier(inst.kind, dl, chain, Opts(dl, true))
                        local chm = MatchOnsets(chain, off)
                        a.chain_gen = a.chain_gen + #chain
                        a.chain_off = a.chain_off + #off
                        a.chain_hit = a.chain_hit + #chm
                        a.viol = a.viol + CountViolations(inst.kind, dl, chain)
                    end
                elseif #upper == 0 or #off == 0 then
                    chain = nil
                end
            end
        end
    end
end

-- Micro F1 for one (kind, tier) over the current AGG.
local function KindF1(kind, dl)
    local hit, gen, off = 0, 0, 0
    for _, inst in ipairs(INSTRUMENTS) do
        local a = inst.kind == kind and AGG[inst.key] and AGG[inst.key][dl]
        if a then hit, gen, off = hit + a.hit, gen + a.gen, off + a.off end
    end
    return F1(hit / math.max(1, gen), hit / math.max(1, off)), gen / math.max(1, off)
end

-- 'tune': sweep the thinning gap per tier, print the F1 surface, and leave the best
-- setting in GEN5_PARAMS for the report below. Development songs only.
--
-- ONE rhythm model for every instrument (see GEN5_PARAMS), so there is one gap per tier.
-- It is scored against the official Guitar/Bass tiers, which the shipped values were
-- tuned on; Keys is printed beside it so the cost of sharing the model stays visible.
if MODE == 'tune' then
    local GRIDS = { H = { 0.25, 0.5 }, M = { 0.5, 1.0 }, E = { 1.0, 2.0 } }
    local SECS  = { 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.20 }
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        local best
        for _, grid in ipairs(GRIDS[dl]) do
            local cells = {}
            for _, sec in ipairs(SECS) do
                GEN5_PARAMS.gap[dl] = { grid = grid, sec = sec }
                Evaluate(false, nil, dl)
                local f1, ratio = KindF1('gb', dl)
                local kf1 = KindF1('k5', dl)
                cells[#cells + 1] = ('%.2f:%4.1f/%.2f k%4.1f'):format(sec, 100 * f1, ratio, 100 * kf1)
                if not best or f1 > best.f1 then best = { f1 = f1, grid = grid, sec = sec } end
            end
            io.write(('%s grid %.2f  %s\n'):format(dl, grid, table.concat(cells, ' ')))
        end
        GEN5_PARAMS.gap[dl] = { grid = best.grid, sec = best.sec }
        io.write(('  BEST %s: grid %.2f sec %.2f  Guitar/Bass F1 %.1f%%\n'):format(
            dl, best.grid, best.sec, 100 * best.f1))
    end

    -- Then the sustain bonus (the one weight term left - colors and chords no longer
    -- count), scored by mean Guitar/Bass F1 over the three tiers.
    local function MeanF1()
        Evaluate(false)
        local s = 0
        for _, dl in ipairs({ 'H', 'M', 'E' }) do s = s + KindF1('gb', dl) end
        return s / 3
    end
    local best_v, best_f
    local cells = {}
    for _, v in ipairs({ 0, 0.5, 1, 2, 3, 5 }) do
        GEN5_PARAMS.sustain_bonus = v
        local f = MeanF1()
        cells[#cells + 1] = ('%.1f:%.2f'):format(v, 100 * f)
        if not best_f or f > best_f then best_v, best_f = v, f end
    end
    GEN5_PARAMS.sustain_bonus = best_v
    io.write(('sustain_bonus  %s  BEST %.1f\n'):format(table.concat(cells, ' '), best_v))
end

-- 'tune_cap': sweep the Hard keep cap with everything else as configured, and print what
-- it does to each instrument kind. The cap is a product choice, so this reports and does
-- not pick: GEN5_PARAMS keeps its configured value for the report below.
if MODE == 'tune' or MODE == 'tune_cap' then
    local configured = GEN5_PARAMS.max_keep.H
    local cells = { gb = {}, k5 = {} }
    for _, v in ipairs({ false, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70 }) do
        GEN5_PARAMS.max_keep.H = v or nil
        Evaluate(false, nil, 'H')
        for _, kind in ipairs({ 'gb', 'k5' }) do
            local f1, ratio = KindF1(kind, 'H')
            table.insert(cells[kind], ('%s:%4.1f/%.2f'):format(v and ('%.2f'):format(v) or 'none', 100 * f1, ratio))
        end
    end
    GEN5_PARAMS.max_keep.H = configured
    for _, kind in ipairs({ 'gb', 'k5' }) do
        io.write(('max_keep H %s  %s\n'):format(kind, table.concat(cells[kind], ' ')))
    end
end

Evaluate(true)

local lines = {}
local function L(s) lines[#lines + 1] = s or '' end

L(('Generate evaluation - %s songs (%d), %s'):format(
    MODE == 'holdout' and 'HELD-OUT' or 'development', n_songs,
    MODE == 'holdout' and 'report this once' or 'tune on these'))
L('P/R/F1: onsets generated from the OFFICIAL upper tier vs the official tier.')
L('copy F1: the same for plain Copy (keep everything). chain F1: Expert>Hard>Medium>Easy')
L('on generated tiers only. color: matched onsets with exactly the official colors.')
L('viol: rule violations Validate would report as errors (must be 0).')
L()
L(('%-7s %s %5s  %6s %6s %6s  %7s  %8s  %6s  %5s'):format(
    'inst', 'tier', 'songs', 'P', 'R', 'F1', 'copyF1', 'chainF1', 'color', 'viol'))
for _, inst in ipairs(INSTRUMENTS) do
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        local a = AGG[inst.key] and AGG[inst.key][dl]
        if a then
            local p, rc = a.hit / math.max(1, a.gen), a.hit / math.max(1, a.off)
            local cp, cr = a.copy_hit / math.max(1, a.copy_gen), a.copy_hit / math.max(1, a.off)
            local hp, hr = a.chain_hit / math.max(1, a.chain_gen), a.chain_hit / math.max(1, a.chain_off)
            L(('%-7s  %s   %5d  %5.1f%% %5.1f%% %5.1f%%  %6.1f%%  %7.1f%%  %5.1f%%  %5d'):format(
                inst.label, dl, a.songs, 100 * p, 100 * rc, 100 * F1(p, rc), 100 * F1(cp, cr),
                100 * F1(hp, hr), 100 * a.color / math.max(1, a.hit), a.viol))
        end
    end
end
L()
L('Keep rate by beat position of the upper tier: generated / official')
for _, inst in ipairs(INSTRUMENTS) do
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        local a = AGG[inst.key] and AGG[inst.key][dl]
        if a then
            local cells = {}
            for _, c in ipairs(CLASSES) do
                local n = a.cls_n[c] or 0
                if n > 0 then
                    cells[#cells + 1] = ('%s %3.0f/%3.0f'):format(c,
                        100 * (a.cls_gen[c] or 0) / n, 100 * (a.cls_off[c] or 0) / n)
                end
            end
            L(('  %-6s %s>%s  %s'):format(inst.label, UPPER[dl], dl, table.concat(cells, '  ')))
        end
    end
end

local report = table.concat(lines, '\n') .. '\n'
io.write(report)
local f = io.open(OUT, 'w')
if f then f:write(report); f:close() end
