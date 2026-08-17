-- @description Rock Band Difficulty Calibration - locked protocol / model selection
-- @author VeeKiraRay
-- @about
--   Selects one model per instrument under the LOCKED evaluation protocol in
--   protocol.lua, and grades it against the release gate.
--
--   This is the companion to run_calibration_analysis_vkr.lua, not a replacement.
--   The analysis is the DIAGNOSTIC view - per-factor correlations, coefficients,
--   worst residuals - and is what names the next factor to try. This script is the
--   DECISION view: predeclared candidates, paired repeated cross-validation, ridge
--   tuned inside the training folds, and a gate read from interval lower bounds.
--
--   Why they are separate: the analysis is meant to be read while exploring, and
--   exploring is exactly what inflates a selection estimate. Keeping the decision in
--   its own script with its own fixed rules is what makes its number defensible.
--
--   Read-only. Touches no project state, so it is safe to run in any project - but
--   run it from the same repo checkout as run_calibration_vkr.lua, since it reads the
--   CSV sitting beside it.
--   Results appear in the REAPER console (View > Show REAPER console).

r = reaper

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _csv    = (arg and arg[1]) or (_dir .. 'corpus_scores.csv')

ctx = nil

dofile(_dir .. 'difficulty_score.lua')  -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')  -- appends the vocal columns to it
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')

-- REAPER's ReaScript console is hard-capped at about 16 KB, and this report passed
-- that once the fifth and sixth instruments were added: the earlier instruments scroll
-- off and cannot be recovered, which is exactly the half you need when comparing a new
-- instrument against the locked ones. So every line goes to a FILE as well, and the
-- console keeps its role as the quick look.
--
-- Overwritten each run rather than appended: it is the report for the CSV sitting
-- beside it, and two runs of different data in one file is worse than none. Not
-- versioned - it is derived from the CSV, which is.
local _report = _dir .. 'calibration_protocol_report.txt'
local _rf = io.open(_report, 'w')

local function Msg(s)
    r.ShowConsoleMsg(s)
    if _rf then _rf:write(s) end
end

-- Console-only: for the pointer at the end, which would be noise inside the file.
local function MsgConsole(s) r.ShowConsoleMsg(s) end

local function CloseReport()
    if not _rf then return end
    _rf:close()
    _rf = nil
    MsgConsole(('\n[full report written to %s]\n'):format(_report))
    MsgConsole('The console truncates at ~16 KB; the file does not.\n')
end

----------------------------------------------------------------------
-- CSV load
----------------------------------------------------------------------

local function Split(line)
    local out = {}
    for field in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = field end
    return out
end

local function LoadCsv(path)
    local f = io.open(path, 'r')
    if not f then return nil, 'not found: ' .. path end
    local header, rows = nil, {}
    for line in f:lines() do
        if line ~= '' then
            local fields = Split(line)
            if not header then
                header = {}
                for i, name in ipairs(fields) do header[name] = i end
            else
                rows[#rows + 1] = fields
            end
        end
    end
    f:close()
    if not header then return nil, 'empty file' end
    return { header = header, rows = rows }
end

local function Field(csv, row, name)
    local i = csv.header[name]
    return i and row[i] or nil
end

local function Collect(csv, inst)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    for _, row in ipairs(csv.rows) do
        if Field(csv, row, 'instrument') == inst then
            local rank = tonumber(Field(csv, row, 'rank'))
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(Field(csv, row, k))
                if v == nil then ok = false else fv[j] = v end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]   = fv
                d.ranks[n]   = rank
                d.origins[n] = Field(csv, row, 'origin')
                d.names[n]   = Field(csv, row, 'shortname')
            end
        end
    end
    return d
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------

local function ReportResults(results)
    Msg(('\n  %-26s %-10s %3s  %-16s %-16s %s\n')
        :format('candidate', 'scale', 'k', 'usable (mean)', 'gate lower bound', 'miss    rho'))
    for _, rc in ipairs(results) do
        if not rc.ok then
            Msg(('  %-26s %-10s %3d  (names a factor the CSV does not carry)\n')
                :format(rc.candidate, rc.scale, rc.n_features))
        elseif not rc.usable_mean then
            Msg(('  %-26s %-10s %3d  fit failed in every repeat\n')
                :format(rc.candidate, rc.scale, rc.n_features))
        else
            Msg(('  %-26s %-10s %3d  %6.2f%% [%.1f-%.1f]  %6.2f%%          %5.2f%%  %+.3f\n')
                :format(rc.candidate, rc.scale, rc.n_features,
                        rc.usable_mean * 100,
                        rc.usable_lo_split * 100, rc.usable_hi_split * 100,
                        rc.usable_lower * 100,
                        rc.miss_mean * 100, rc.rho_mean))
        end
    end
    Msg('\n  usable (mean) is the average across repeats; [lo-hi] beside it is the 10th-90th\n')
    Msg('  percentile ACROSS REPEATS, i.e. split noise only. The gate lower bound is the\n')
    Msg('  one-sided 95% Wilson bound on the row count, which is the dominant uncertainty\n')
    Msg('  at this sample size and is what the gate actually reads.\n')
end

local function ReportRidges(results)
    -- If the search always lands on the smallest grid value, the grid is not doing
    -- anything and that should be visible rather than assumed.
    local counts, total = {}, 0
    for _, rc in ipairs(results) do
        for _, g in ipairs(rc.ridges or {}) do
            counts[g] = (counts[g] or 0) + 1
            total = total + 1
        end
    end
    if total == 0 then return end
    Msg('\n  ridge chosen inside training folds: ')
    local parts = {}
    for _, g in ipairs(PROTOCOL.RIDGE_GRID) do
        if counts[g] then
            parts[#parts + 1] = ('%g x%d (%.0f%%)')
                :format(g, counts[g], counts[g] / total * 100)
        end
    end
    Msg(table.concat(parts, ', ') .. '\n')
end

local function AnalyseInstrument(csv, inst)
    local d = Collect(csv, inst)

    local rb_all = {}
    for i, o in ipairs(d.origins) do
        if o == 'rb3_dlc' then rb_all[#rb_all + 1] = i end
    end
    -- Every auxiliary origin, pooled: always training, never predicted, each carrying
    -- its own indicator column and its own weight.
    local aux = AuxIndices(d.origins)
    -- Disputed labels never train and never grade. Normally empty.
    local target, weird = {}, {}
    for _, i in ipairs(rb_all) do
        if IsWeirdlyScored(d.names[i], inst) then weird[#weird + 1] = i
        else target[#target + 1] = i end
    end

    Msg(('\n==================  %s  ==================\n'):format(inst:upper()))
    Msg(('  development rows : %d rb3_dlc\n'):format(#target))
    if #aux > 0 then
        -- Per origin, not just a total: two origins at the same weight are not
        -- interchangeable, and a run where one of them is empty for this instrument
        -- should look different rather than merely smaller.
        local parts = {}
        for _, a in ipairs(PROTOCOL.AUX_ORIGINS) do
            local n = 0
            for _, i in ipairs(aux) do if d.origins[i] == a.origin then n = n + 1 end end
            if n > 0 then
                parts[#parts + 1] = ('%d %s at weight %.2f'):format(n, a.origin, a.weight)
            end
        end
        Msg(('  always-training   : %s\n'):format(table.concat(parts, ', ')))
    else
        -- Lego Rock Band and the RB2 export both predate the keyboard part, so PART KEYS
        -- has no auxiliary rows at all. Their indicator columns are then constant and
        -- contribute nothing (MultiFit clamps a zero-variance column's sd), but the row
        -- count is smaller for it, and that is what makes the gate harder to clear.
        Msg('  always-training   : none - no auxiliary-origin rows for this instrument\n')
    end
    Msg(('  disputed held out : %d\n'):format(#weird))
    Msg(('  reserved test set : NOT DRAWN - this phase validates the approach, not a release\n'))
    if #target < 40 then
        Msg('  too few development rows for this protocol\n')
        return
    end

    local pos = {}
    for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

    local results = RunProtocol(d, target, aux, inst, pos)
    ReportResults(results)
    ReportRidges(results)

    local sel, leader, gain, win_share = SelectCandidate(results, inst)
    if not sel then
        Msg('\n  no candidate produced a result\n')
        return
    end

    Msg('\n  -- selection --\n')
    Msg(('    best mean usable  : %s / %s at %.2f%%\n')
        :format(leader.candidate, leader.scale, leader.usable_mean * 100))
    Msg(('    SELECTED          : %s / %s  (%d features)\n')
        :format(sel.candidate, sel.scale, sel.n_features))
    if sel ~= leader then
        Msg(('    the leader beats it by %+.2f points and wins %.0f%% of paired repeats,\n')
            :format(gain * 100, win_share * 100))
        Msg(('    which does not clear the predeclared bar (>%.0f points AND >%.0f%% of repeats),\n')
            :format(SELECT_MIN_GAIN * 100, SELECT_WIN_SHARE * 100))
        Msg('    so the simpler candidate is selected.\n')
    else
        Msg('    no simpler candidate came within the predeclared margin.\n')
    end

    -- Every candidate against the selected one, so the margins are visible rather
    -- than summarised into a single choice.
    Msg('\n  -- paired differences against the selected candidate --\n')
    Msg(('    %-26s %-10s %10s %10s\n'):format('candidate', 'scale', 'mean diff', 'wins'))
    for _, rc in ipairs(results) do
        if rc.usable_mean and rc ~= sel then
            local g, w = PairedDiff(rc, sel)
            Msg(('    %-26s %-10s %+9.2f%% %9.0f%%\n')
                :format(rc.candidate, rc.scale, g * 100, w * 100))
        end
    end

    -- Worst residuals OF THE SELECTED MODEL. The analysis script has its own worst-10,
    -- but it comes from the all-factor unridged fit on the raw rank scale, which is not
    -- the model chosen here and can disagree by a hundred rank points on one song.
    --
    -- MEASURED, round 10, and it is worse than "a hundred rank points": the analysis
    -- put `shadowsofthenight` (real_keys, actual 348) at 138 - a FOUR-TIER miss - while
    -- every one of the twelve declared candidates predicts it out-of-fold at 255-347,
    -- and the two simplest get its tier exactly right. An unridged fit over ~31 columns
    -- extrapolates wildly for a chart that sits off the collinear ridge those columns
    -- lie on, and that song is #3 of 122 on peak gem/attack ratio. If the two lists
    -- disagree, THIS one is the answer. See the design doc, "the analysis view's
    -- worst-10 is not a bug report".
    local resid = CandidateResiduals(d, target, aux, inst, pos, sel)
    if resid then
        Msg('\n  -- worst 10 by tier distance, SELECTED model, averaged over repeats --\n')
        for i = 1, math.min(10, #resid) do
            local x = resid[i]
            Msg(('    %-24s rank %3d  predicted %4.0f  said tier %d, actual %d  (%d off)\n')
                :format(x.name, x.rank, x.pred, x.tier_pred, x.tier_act, x.dist))
        end
    end

    -- When the mean leader is rejected by the stability guard, show its residuals
    -- too. This makes a deliberately rejected experiment auditable: a small average
    -- gain may still be concentrated at (or absent from) the hard end that motivated
    -- the candidate.
    if leader ~= sel then
        local leader_resid = CandidateResiduals(d, target, aux, inst, pos, leader)
        if leader_resid then
            Msg('\n  -- worst 10 by tier distance, MEAN LEADER, averaged over repeats --\n')
            for i = 1, math.min(10, #leader_resid) do
                local x = leader_resid[i]
                Msg(('    %-24s rank %3d  predicted %4.0f  said tier %d, actual %d  (%d off)\n')
                    :format(x.name, x.rank, x.pred, x.tier_pred, x.tier_act, x.dist))
            end
        end
    end

    local passed, reasons = GateVerdict(sel)
    Msg('\n  -- release gate, read from the pessimistic end of each interval --\n')
    Msg(('    usable lower bound : %6.2f%%   (floor %.0f%%)\n')
        :format(sel.usable_lower * 100, PROTOCOL.USABLE_FLOOR * 100))
    Msg(('    miss upper bound   : %6.2f%%   (ceiling %.0f%%)\n')
        :format(sel.miss_upper * 100, PROTOCOL.MISS_CEILING * 100))
    Msg(('    rho (mean)         : %+6.3f   (floor %.2f)\n')
        :format(sel.rho_mean, PROTOCOL.RHO_FLOOR))
    if passed then
        Msg('    -> PASSES the gate on the development set.\n')
    else
        Msg('    -> DOES NOT PASS:\n')
        for _, why in ipairs(reasons) do Msg('       - ' .. why .. '\n') end
    end
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

r.ClearConsole()
Msg('======  Difficulty calibration - LOCKED PROTOCOL  ======\n')

local csv, err = LoadCsv(_csv)
if not csv then
    Msg(('\nCould not read the scores CSV.\n  %s\n\nRun run_calibration_vkr.lua first.\n')
        :format(tostring(err)))
    return
end

local missing = {}
for _, k in ipairs(SCORE_FACTOR_KEYS) do
    if not csv.header[k] then missing[#missing + 1] = k end
end
if #missing > 0 then
    Msg('\nThis CSV predates the current factor set - missing columns:\n')
    Msg('  ' .. table.concat(missing, ', ') .. '\n\n')
    Msg('Delete corpus_scores.csv and re-run run_calibration_vkr.lua to rescore.\n')
    return
end

Msg(('\nrows %d   repeats %d   folds %d   seed %d\n')
    :format(#csv.rows, PROTOCOL.N_REPEATS, PROTOCOL.NFOLD, PROTOCOL.SEED))
Msg('candidates and thresholds are fixed in protocol.lua and were set before this ran.\n')
Msg('Changing any of them is a new experiment, not a re-run - say so if you do.\n')

local seen, order = {}, {}
for _, row in ipairs(csv.rows) do
    local inst = Field(csv, row, 'instrument')
    if inst and not seen[inst] then
        seen[inst] = true
        order[#order + 1] = inst
    end
end

for _, inst in ipairs(order) do AnalyseInstrument(csv, inst) end

Msg('\n')
Msg('Reading this report:\n')
Msg('  * The SELECTED line is the model this protocol chooses. It is not necessarily\n')
Msg('    the highest mean - a bigger model has to beat a simpler one across repeats,\n')
Msg('    not just on average once.\n')
Msg('  * The gate reads interval LOWER bounds, so a pass here is harder than the\n')
Msg('    point estimates the earlier rounds reported. A point estimate above 90% with\n')
Msg('    a lower bound below it means the corpus is too small to prove the claim yet,\n')
Msg('    not that the model got worse.\n')
Msg('  * MAE is deliberately absent: it is not comparable between the rank and\n')
Msg('    log(rank) scales, and comparing it across them would pick the wrong model.\n')

CloseReport()
