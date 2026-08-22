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

----------------------------------------------------------------------
-- Input fingerprints
----------------------------------------------------------------------

-- The hash itself is Fnv1a64Hex, from protocol.lua - one implementation, because the
-- partition rule there and the fingerprints here have to agree about what a hash of a
-- given string is. This file adds only the file-reading half, which protocol.lua stays
-- clear of by design.
--
-- Returns hash, byte count. Read in binary so a CRLF checkout and an LF one are
-- distinguishable rather than silently equal - the files this fingerprints are mixed
-- in this repo, and a line-ending conversion is a real change to the bytes a rerun
-- would read.
local function FnvFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil, nil end
    local s = f:read('a')
    f:close()
    return Fnv1a64Hex(s), #s
end

-- REAPER's ReaScript console is hard-capped at about 16 KB, and this report passed
-- that once the fifth and sixth instruments were added: the earlier instruments scroll
-- off and cannot be recovered, which is exactly the half you need when comparing a new
-- instrument against the locked ones. So every line goes to a FILE as well, and the
-- console keeps its role as the quick look.
--
-- Overwritten each run rather than appended: it is the report for the CSV sitting
-- beside it, and two runs of different data in one file is worse than none.
--
-- WRITTEN ATOMICALLY, and that is not a nicety. This file IS versioned - the README
-- calls it the authority, and the coefficients that ship are justified from it - while
-- the run that produces it holds the interpreter for about three and a half minutes.
-- The first version opened the authority path with mode 'w' up front and wrote
-- incrementally, so a killed or overlapping run left a PLAUSIBLE-LOOKING partial file:
-- correct in its early sections, silently short in its later ones. That is what
-- happened to the round-23a report, which lost four declared drum candidate rows and
-- gained a duplicated block in the keys residuals, and was read as authoritative
-- afterwards because nothing about it looked wrong.
--
-- So: write to a sibling .part and rename onto the authority path only after the
-- completion footer is on disk. A failed run now leaves the previous report intact and
-- the evidence beside it.
local _report = _dir .. 'calibration_protocol_report.txt'
local _part   = _report .. '.part'
local _lock   = _dir .. 'calibration_protocol_report.lock'

-- Two instances writing one target is the other half of the same failure, and the
-- rename does not fix it - each would rename its own .part over the other's finished
-- work. Pure Lua has no lock primitive and no way to stat a file, so the lock carries
-- its own start time and expires on its own rather than needing a manual cleanup after
-- every crash.
--
-- Ten minutes, against a run that takes about four and a half. Long enough that a live
-- run is never mistaken for a dead one on a slow machine, short enough that the common
-- case - kill a run, fix something, start again - waits rather than being stuck. A
-- killed run leaves the lock behind (there is no handler that could remove it), so the
-- refusal below names the file to delete for anyone who does not want to wait.
local LOCK_STALE_S = 600

local function LockAgeOrNil()
    local f = io.open(_lock, 'r')
    if not f then return nil end
    local started = tonumber(f:read('l') or '')
    f:close()
    if not started then return LOCK_STALE_S end   -- unreadable: treat as fresh, i.e. held
    return os.time() - started
end

local function ReleaseLock() os.remove(_lock) end

local _age = LockAgeOrNil()
if _age and _age < LOCK_STALE_S then
    r.ShowConsoleMsg(('A protocol run started %d s ago is still holding %s\n')
        :format(_age, _lock))
    r.ShowConsoleMsg('Wait for it to finish, or delete that file if it died.\n')
    return
end
if _age then
    r.ShowConsoleMsg(('[clearing a stale lock, %d s old]\n'):format(_age))
end
do
    local lf = io.open(_lock, 'w')
    if lf then lf:write(tostring(os.time()), '\n'); lf:close() end
end

-- BINARY MODE, and the CI check depends on it. Lua's text mode translates '\n' to the
-- platform's line ending, so the same run writes CRLF under REAPER on Windows and LF on
-- a Linux runner. The tracked report would then differ from a regenerated one on every
-- CI run, for a reason that has nothing to do with the calibration. 'wb' makes the file
-- byte-identical everywhere, which is the property the whole check rests on.
local _rf = io.open(_part, 'wb')

local function Msg(s)
    r.ShowConsoleMsg(s)
    if _rf then _rf:write(s) end
end

-- Console-only: for the pointer at the end, which would be noise inside the file.
local function MsgConsole(s) r.ShowConsoleMsg(s) end

-- Give up without touching the authority file. Every early return below goes through
-- this, so a run that cannot read its inputs leaves the previous report in place.
local function AbortReport()
    if _rf then _rf:close(); _rf = nil end
    os.remove(_part)
    ReleaseLock()
end

local function CloseReport()
    if not _rf then return end
    -- The footer is the whole point of the .part dance: its presence is what says the
    -- file is complete, and a reader (or CI) can check for it without rerunning.
    _rf:write('\n[report complete]\n')
    _rf:close()
    _rf = nil
    os.remove(_report)                       -- Windows os.rename will not overwrite
    local ok, why = os.rename(_part, _report)
    ReleaseLock()
    if not ok then
        MsgConsole(('\n[could not replace %s: %s]\n'):format(_report, tostring(why)))
        MsgConsole(('[the finished report is at %s]\n'):format(_part))
        return
    end
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
    -- packs is read for the grouped-fold probe. It is CSV column 3 and went unread until
    -- 2026-08-21, which is finding 7 of the peer review: the fold assignment could not
    -- know two rows came from the same DLC pack.
    local d = { feats = {}, ranks = {}, origins = {}, names = {}, packs = {} }
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
                d.packs[n]   = Field(csv, row, 'pack')
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
        :format('candidate', 'scale', 'k', 'usable (mean)', 'gate lower bound',
                'miss    rho     macro'))
    -- Track whichever candidate leads on each quantity, so the two can be compared
    -- without reading forty rows by eye. This is the answer to "would a different model
    -- win if the gate moved to macro?".
    local best_p, best_m
    for _, rc in ipairs(results) do
        if not rc.ok then
            Msg(('  %-26s %-10s %3d  (names a factor the CSV does not carry)\n')
                :format(rc.candidate, rc.scale, rc.n_features))
        elseif not rc.usable_mean then
            Msg(('  %-26s %-10s %3d  fit failed in every repeat\n')
                :format(rc.candidate, rc.scale, rc.n_features))
        else
            Msg(('  %-26s %-10s %3d  %6.2f%% [%.1f-%.1f]  %6.2f%%          %5.2f%%  %+.3f  %6.2f%%\n')
                :format(rc.candidate, rc.scale, rc.n_features,
                        rc.usable_mean * 100,
                        rc.usable_lo_split * 100, rc.usable_hi_split * 100,
                        rc.usable_lower * 100,
                        rc.miss_mean * 100, rc.rho_mean,
                        (rc.macro_mean or 0) * 100))
            if not best_p or rc.usable_mean > best_p.usable_mean then best_p = rc end
            if not best_m or (rc.macro_mean or 0) > (best_m.macro_mean or 0) then best_m = rc end
        end
    end
    Msg('\n  usable (mean) is the average across repeats; [lo-hi] beside it is the 10th-90th\n')
    Msg('  percentile ACROSS REPEATS, i.e. split noise only. The gate lower bound is the\n')
    Msg('  one-sided 95% Wilson bound on the row count, which is the dominant uncertainty\n')
    Msg('  at this sample size and is what the gate actually reads.\n')

    -- macro is REPORTED ONLY. SelectCandidate ranks by pooled usable%, and continues to
    -- until the gate is actually moved - see MacroUsable in protocol.lua for why this is
    -- measured now and why adopting macro because of what it favours would be the wrong
    -- reason.
    if best_p and best_m then
        Msg('\n  macro weights every occupied tier equally instead of every row. It is\n')
        Msg('  measured for every candidate but NOT selected on - the selection rule still\n')
        Msg('  reads pooled usable%.\n')
        if best_p == best_m then
            Msg(('    the same candidate leads on both: %s / %s\n')
                :format(best_p.candidate, best_p.scale))
        else
            Msg(('    pooled leader : %s / %s  (%.2f%% pooled, %.2f%% macro)\n')
                :format(best_p.candidate, best_p.scale,
                        best_p.usable_mean * 100, (best_p.macro_mean or 0) * 100))
            Msg(('    macro leader  : %s / %s  (%.2f%% pooled, %.2f%% macro)\n')
                :format(best_m.candidate, best_m.scale,
                        best_m.usable_mean * 100, (best_m.macro_mean or 0) * 100))
            Msg('    THEY DISAGREE - moving the gate to macro would reopen this selection.\n')
        end
    end
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
        return nil
    end

    local pos = {}
    for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

    local results = RunProtocol(d, target, aux, inst, pos)
    ReportResults(results)
    ReportRidges(results)

    local sel, leader, gain, win_share = SelectCandidate(results, inst)
    if not sel then
        Msg('\n  no candidate produced a result\n')
        return nil
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

    -- Per-tier view of the SAME predictions the headline figures come from. Added
    -- 2026-08-21 after the peer review pointed out that a pooled percentage over a
    -- deliberately enriched corpus has no stable meaning, and that the pooled figure
    -- hides a uniform compression toward the middle. See TierDiagnostics in protocol.lua
    -- for the declared estimand and the pre-registered intent to move the gate to macro.
    local diag = resid and TierDiagnostics(resid)
    if diag then
        Msg('\n  -- per tier, SELECTED model, same cross-validated predictions --\n')
        Msg('    tier     n    share   usable   signed bias   predicted n\n')
        for _, t in ipairs(diag.tiers) do
            Msg(('     %d    %4d   %5.1f%%  %6.1f%%       %+5.2f          %4d\n')
                :format(t.tier, t.n, t.share * 100, t.usable * 100, t.bias, t.n_pred))
        end
        Msg(('    pooled   %6.2f%%   what the gate reads - an adversarially curated mix\n')
            :format(diag.pooled * 100))
        if diag.macro then
            Msg(('    macro    %6.2f%%   equal weight per occupied tier (%+.2f vs pooled)\n')
                :format(diag.macro * 100, (diag.macro - diag.pooled) * 100))
        end
        if diag.endpoint then
            Msg(('    ends     %6.2f%%   tiers 0-1 and 5-6 pooled, %d rows (%.0f%% of corpus)\n')
                :format(diag.endpoint * 100, diag.ep_n, diag.ep_n / diag.n * 100))
        end

        -- The confusion matrix the pooled figure summarises away. Rows are the official
        -- tier, columns the predicted one, so the diagonal is exact agreement and the
        -- two neighbouring diagonals are the rest of "usable".
        Msg('\n    confusion (row = official tier, col = predicted)\n')
        Msg('           0    1    2    3    4    5    6\n')
        for _, t in ipairs(diag.tiers) do
            local cells = {}
            for p = 0, 6 do
                local c = (diag.matrix[t.tier] or {})[p] or 0
                cells[#cells + 1] = (c > 0) and ('%4d'):format(c) or '   .'
            end
            Msg(('      %d %s\n'):format(t.tier, table.concat(cells, ' ')))
        end
    end

    -- What constant guessing scores on the same folds. Without this, "94% within one
    -- tier" cannot be read as good or bad.
    local base = NaiveBaselines(d, target, inst)
    if base and base.modal_tier and base.median_rank then
        Msg('\n  -- naive baselines, same folds and seeds, fitted out of fold --\n')
        Msg(('    modal tier    pooled %6.2f%%   macro %6.2f%%\n')
            :format(base.modal_tier.pooled * 100,
                    (base.modal_tier.macro or 0) * 100))
        Msg(('    median rank   pooled %6.2f%%   macro %6.2f%%\n')
            :format(base.median_rank.pooled * 100,
                    (base.median_rank.macro or 0) * 100))
        if diag then
            Msg(('    SELECTED over the better baseline: %+.2f pooled, %+.2f macro\n')
                :format((diag.pooled - math.max(base.modal_tier.pooled,
                                                base.median_rank.pooled)) * 100,
                        ((diag.macro or 0) - math.max(base.modal_tier.macro or 0,
                                                      base.median_rank.macro or 0)) * 100))
        end
    end

    -- An interval for the quantities Wilson cannot reach - macro, rho - and a direct test
    -- of whether Wilson is optimistic on the ones it can. Resamples PACKS, not rows.
    -- Bounds the averaged-prediction figures printed in the per-tier block just above,
    -- which are NOT the per-repeat means the gate quotes; see PackBootstrap.
    local boot = resid and PackBootstrap(resid)
    if boot then
        Msg(('\n  -- pack bootstrap, %d resamples of %d packs --\n')
            :format(boot.B, boot.n_packs))
        Msg(('    %-10s %8s %8s %10s %10s\n')
            :format('metric', 'point', 'sd', 'p05 (lo)', 'p95'))
        local function Row(key, label, scale, fmt)
            local s = boot.stat[key]
            if not s then return end
            Msg(('    %-10s ' .. fmt .. ' ' .. fmt .. ' ' .. fmt .. ' ' .. fmt .. '\n')
                :format(label, s.point * scale, s.sd * scale,
                        s.lo * scale, s.p95 * scale))
        end
        Row('pooled',   'pooled',   100, '%8.2f')
        Row('macro',    'macro',    100, '%8.2f')
        Row('endpoint', 'ends',     100, '%8.2f')
        Row('rho',      'rho',        1, '%8.3f')

        -- The design effect is the point of the exercise: it says in one number whether
        -- the gate's Wilson bound is defensible on clustered rows.
        Msg('\n    clustering cost, against the binomial sd Wilson assumes:\n')
        for _, key in ipairs({ 'pooled', 'endpoint' }) do
            local s = boot.stat[key]
            if s and s.design then
                -- ref_n is that metric's OWN denominator: all rows for pooled, endpoint
                -- rows for the endpoint band. See PackBootstrap.
                Msg(('      %-8s bootstrap sd %.4f vs binomial %.4f over %d rows  ->  '
                     .. 'design %.2f, effective n %.0f\n')
                    :format(key, s.sd, s.binom_sd, s.ref_n, s.design, s.n_eff))
            end
        end
        if boot.macro_short_frac > 0 then
            Msg(('    NOTE: %.1f%% of resamples miss a tier entirely, so their macro is a\n')
                :format(boot.macro_short_frac * 100))
            Msg('    mean over fewer bands - that widens the macro interval beyond pack\n')
            Msg('    sampling alone. See PackBootstrap.\n')
        end
    end

    -- How much of the score survives when whole DLC PACKS are held out instead of
    -- individual songs. Peer review finding 7: `pack` is CSV column 3 and the fold
    -- assignment never read it, so a song could be graded while a pack sibling sat in
    -- training. Reported, NOT gated on - see the GROUPED FOLDS block in protocol.lua for
    -- the pre-registered prediction and why moving the gate is a separate decision.
    local groups = {}
    for n, ti in ipairs(target) do groups[n] = d.packs and d.packs[ti] end
    local probe = GroupedFoldProbe(d, target, aux, inst, pos,
                                   sel.keys, sel.scale_obj, groups)
    if probe then
        Msg('\n  -- pack-grouped folds, SELECTED model, matched seeds --\n')
        Msg(('    %d packs over %d rows, largest %d rows (%.1f%% of the corpus)\n')
            :format(probe.diag.n_groups, probe.n_rows or #target,
                    probe.diag.largest_group,
                    probe.diag.largest_group / math.max(1, probe.n_rows or #target) * 100))
        Msg(('    row-level folds leak a pack sibling into training for %.1f%% of rows\n')
            :format(probe.leak_row * 100))
        Msg(('    %-10s %10s %10s %12s\n')
            :format('metric', 'row-level', 'grouped', 'difference'))
        Msg(('    %-10s %9.2f%% %9.2f%% %+8.2f (sd %.2f)\n')
            :format('pooled', probe.usable_row * 100, probe.usable_grouped * 100,
                    probe.usable_delta * 100, probe.usable_delta_sd * 100))
        Msg(('    %-10s %9.2f%% %9.2f%% %+8.2f (sd %.2f)\n')
            :format('macro', probe.macro_row * 100, probe.macro_grouped * 100,
                    probe.macro_delta * 100, probe.macro_delta_sd * 100))
        Msg(('    %-10s %10.3f %10.3f %+8.3f (sd %.3f)\n')
            :format('rho', probe.rho_row, probe.rho_grouped,
                    probe.rho_delta, probe.rho_delta_sd))
        local thin = {}
        for s, c in pairs(probe.diag.thin_strata) do
            thin[#thin + 1] = ('tier %s in %d packs'):format(s, c)
        end
        table.sort(thin)
        if #thin > 0 then
            Msg(('    NOTE: %s - fewer packs than folds, so that tier cannot reach every\n')
                :format(table.concat(thin, ', ')))
            Msg('    fold and its per-tier rate is NOISIER under grouping, not cleaner.\n')
        end
    end

    local passed, reasons = GateVerdict(sel, boot)
    Msg('\n  -- release gate --\n')
    Msg(('    usable lower bound : %6.2f%%   (floor %.0f%%, one-sided 95%% Wilson)\n')
        :format(sel.usable_lower * 100, PROTOCOL.USABLE_FLOOR * 100))
    Msg(('    miss upper bound   : %6.2f%%   (ceiling %.0f%%, one-sided 95%% Wilson)\n')
        :format(sel.miss_upper * 100, PROTOCOL.MISS_CEILING * 100))
    -- rho is read from its pessimistic end too, as of 2026-08-22. The mean is printed
    -- beside the bound because the two answer different questions and the mean is what
    -- every figure before that date was gated on.
    local rho_boot = boot and boot.stat and boot.stat.rho
    if rho_boot then
        Msg(('    rho lower bound    : %+.3f   (floor %.2f, pack bootstrap p05)\n')
            :format(rho_boot.lo, PROTOCOL.RHO_FLOOR))
        Msg(('       mean %+.3f, split range [%+.3f, %+.3f] - split noise, not uncertainty\n')
            :format(sel.rho_mean, sel.rho_lo_split or sel.rho_mean,
                    sel.rho_hi_split or sel.rho_mean))
    else
        Msg(('    rho (MEAN - no bootstrap): %+.3f   (floor %.2f)  split range [%+.3f, %+.3f]\n')
            :format(sel.rho_mean, PROTOCOL.RHO_FLOOR,
                    sel.rho_lo_split or sel.rho_mean, sel.rho_hi_split or sel.rho_mean))
    end
    -- The extremes bar. Bootstrap p05, never Wilson - see the ENDPOINT FLOOR block in
    -- protocol.lua for why this band in particular cannot use a binomial interval.
    local ep_boot = boot and boot.stat and boot.stat.endpoint
    if ep_boot then
        Msg(('    endpoint band      : %6.2f%%   (floor %.0f%%, pack bootstrap p05, tiers 0-1 + 5-6)\n')
            :format(ep_boot.lo * 100, PROTOCOL.ENDPOINT_FLOOR * 100))
        Msg(('       point %.2f%% over %d rows; design effect %.2f, so a binomial bound\n')
            :format(ep_boot.point * 100, boot.ep_n or 0, ep_boot.design or 1))
        Msg('       would land in much the same place - the bootstrap is preferred for\n')
        Msg('       assuming nothing, not because Wilson fails on this band.\n')
    end
    if passed then
        Msg('    -> PASSES the gate on the development set.\n')
    else
        Msg('    -> DOES NOT PASS:\n')
    end
    for _, why in ipairs(reasons) do Msg('       - ' .. why .. '\n') end

    -- The decision, as data. Everything the exporter needs in order to stop taking this
    -- script's word for it via a hand-copied table - see the manifest block in Main.
    return {
        inst         = inst,
        candidate    = sel.candidate,
        scale        = sel.scale,
        n_features   = sel.n_features,
        n_target     = #target,
        n_aux        = #aux,
        n_weird      = #weird,
        n_rows       = sel.n_rows,
        usable_mean  = sel.usable_mean,
        usable_lower = sel.usable_lower,
        miss_upper   = sel.miss_upper,
        rho_mean     = sel.rho_mean,
        rho_lo_split = sel.rho_lo_split,
        rho_hi_split = sel.rho_hi_split,
        -- What the gate ACTUALLY read for rho as of 2026-08-22. Recorded separately from
        -- rho_mean because a manifest that only carried the mean would no longer describe
        -- the decision it is supposed to be the record of. nil if no bootstrap ran, which
        -- is also the signal that the mean was used instead.
        rho_lower    = rho_boot and rho_boot.lo or nil,
        -- The extremes bar's input, schema 3. Recorded for the same reason as rho_lower:
        -- a manifest that does not carry every quantity the gate read is not a record of
        -- the decision.
        endpoint_lower = ep_boot and ep_boot.lo or nil,
        endpoint_n     = boot and boot.ep_n or nil,
        gate_passed  = passed,
    }
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
    AbortReport()
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
    AbortReport()
    return
end

-- Provenance. A report that cannot say which inputs produced it cannot be checked
-- against a rerun, and this one is the authority for coefficients that ship. Whole
-- files, not a header line or a row count: a reordered CSV, an edited candidate table
-- and a changed factor implementation all have to show up here, and only the first of
-- those changes the row count.
--
-- NO WALL-CLOCK TIME, on purpose. Fold assignment is explicitly seeded and both
-- interpreters are Lua 5.4, so two runs over unchanged inputs produce a byte-identical
-- file - which is what lets CI diff the tracked report against a fresh run and fail on
-- any difference. A timestamp would make every run differ and spend that for nothing;
-- git already dates the file. For the same reason the RUNTIME (REAPER or the offline
-- driver) is printed to the console only: the two are meant to agree byte for byte,
-- and writing which one ran would guarantee they never do.
-- Held in locals rather than inlined: the decision manifest at the end of this run
-- records the same three values, and computing them twice is how the report and the
-- manifest would eventually come to describe different inputs.
local _csv_hash, _csv_bytes = FnvFile(_csv)
local _protocol_hash        = FnvFile(_dir .. 'protocol.lua')
local _factors_hash         = Fnv1a64Hex(table.concat(SCORE_FACTOR_KEYS, ','))

Msg(('\ncorpus_scores.csv  %s  %d bytes, %d rows\n')
    :format(_csv_hash or '(unreadable)', _csv_bytes or -1, #csv.rows))
Msg(('protocol.lua       %s\n'):format(_protocol_hash or '(unreadable)'))
Msg(('factor set         %s  %d columns\n')
    :format(_factors_hash, #SCORE_FACTOR_KEYS))
Msg(('interpreter        %s\n'):format(_VERSION))
MsgConsole(('runtime            %s\n'):format(r.GetAppVersion and 'REAPER' or 'offline driver'))

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

local decisions = {}
for _, inst in ipairs(order) do
    local dec = AnalyseInstrument(csv, inst)
    if dec then decisions[#decisions + 1] = dec end
end

Msg('\n')
Msg('Reading this report:\n')
Msg('  * The SELECTED line is the model this protocol chooses. It is not necessarily\n')
Msg('    the highest mean - a bigger model has to beat a simpler one across repeats,\n')
Msg('    not just on average once.\n')
Msg('  * The usable and miss gates read interval bounds at the pessimistic end, so a\n')
Msg('    pass on them is harder than the point estimates the earlier rounds reported.\n')
Msg('    A point estimate above 90% with a lower bound below it means the corpus is too\n')
Msg('    small to prove the claim yet, not that the model got worse.\n')
Msg('  * RHO IS GATED ON ITS PACK-BOOTSTRAP LOWER BOUND as of 2026-08-22, so every\n')
Msg('    figure the gate reads is now the pessimistic end. It was gated on the MEAN\n')
Msg('    until then, because ten correlated reruns over the same songs have no honest\n')
Msg('    interval. The split range printed beside it is still repeat-to-repeat spread\n')
Msg('    and still is NOT a confidence interval - read the bound, not the range.\n')
Msg('  * These are DEVELOPMENT-SET figures and the Wilson bounds are not confirmatory\n')
Msg('    intervals. The same repeated-CV results both choose the candidate and report\n')
Msg('    its quality, so the bound on the selected model is optimistic by an unmeasured\n')
Msg('    amount. No reserved test partition has been drawn, and none can be drawn from\n')
Msg('    these rows - see PackIsReserved in protocol.lua.\n')
Msg('  * MAE is deliberately absent: it is not comparable between the rank and\n')
Msg('    log(rank) scales, and comparing it across them would pick the wrong model.\n')

----------------------------------------------------------------------
-- The decision manifest
----------------------------------------------------------------------

-- Machine-readable output of everything this run DECIDED, plus fingerprints of what it
-- decided it from.
--
-- WHY IT EXISTS. export_production_models.lua turns a selection into the coefficients
-- that ship, and until now it learned that selection from a table typed by hand into its
-- own source. That table cannot be wrong in a way anything detects: the unit tests refit
-- the model the exporter names and compare coefficients, so they pass whenever the
-- exporter is self-consistent - including when the protocol has since selected something
-- else. The 2026-08-21 peer review named this exactly: "tests can pass while the protocol
-- report has reselected a different model."
--
-- So the protocol now writes down what it chose, and the exporter reads it and refuses to
-- run against inputs that have moved. The exporter still carries its documented
-- expectation of each selection - the rounds and reasoning are worth keeping in the file
-- that acts on them - but that table is now an ASSERTION checked against this manifest
-- rather than the source of truth.
--
-- Written last, and only on a completed run, so a killed run cannot leave a manifest
-- describing selections it never finished making. Same reasoning as the report's .part.
--
-- A Lua table rather than a text format: the only consumer is a Lua script, dofile is the
-- whole parser, and it stays diff-readable in review.
local _manifest = _dir .. 'calibration_decision_manifest.lua'
do
    -- 'wb' for the same reason as the report - see the _rf comment.
    local mf, mferr = io.open(_manifest, 'wb')
    if not mf then
        MsgConsole(('\n[could not write %s: %s]\n'):format(_manifest, tostring(mferr)))
    else
        local function Q(s) return ('%q'):format(s) end
        mf:write('-- GENERATED by run_calibration_protocol_vkr.lua. Do not hand-edit.\n')
        mf:write('--\n')
        mf:write("-- The protocol's decisions, and fingerprints of the inputs they were made\n")
        mf:write('-- from. export_production_models.lua reads this and refuses to export if any\n')
        mf:write('-- fingerprint no longer matches the file it describes.\n')
        mf:write('--\n')
        mf:write('-- Regenerate with:  lua dev/calibration/run_protocol_offline.lua\n\n')
        mf:write('CALIBRATION_MANIFEST = {\n')
        -- SCHEMA 3 as of 2026-08-22. Bumped twice in one day, both times because what the
        -- manifest MEANS changed rather than merely what it carries:
        --   2  rho_lower added; the gate reads it instead of rho_mean.
        --   3  endpoint_lower added; the gate gained a fourth input, so a schema 2 file
        --      records a verdict reached WITHOUT the extremes bar.
        mf:write('    schema   = 3,\n')
        -- Only reached after every instrument has been analysed, so this flag being true
        -- is a statement about the whole file and not just its header.
        mf:write('    complete = true,\n')
        mf:write('    inputs = {\n')
        mf:write(('        csv_hash      = %s,\n'):format(Q(_csv_hash or '')))
        mf:write(('        csv_bytes     = %d,\n'):format(_csv_bytes or -1))
        mf:write(('        csv_rows      = %d,\n'):format(#csv.rows))
        mf:write(('        protocol_hash = %s,\n'):format(Q(_protocol_hash or '')))
        mf:write(('        factors_hash  = %s,\n'):format(Q(_factors_hash or '')))
        mf:write(('        factors_n     = %d,\n'):format(#SCORE_FACTOR_KEYS))
        mf:write(('        lua           = %s,\n'):format(Q(_VERSION)))
        mf:write('    },\n')
        -- The thresholds in force when these verdicts were reached. A gate edited after
        -- the fact would otherwise leave the verdicts below looking as though they had
        -- been graded against the new numbers.
        mf:write('    protocol = {\n')
        mf:write(('        n_repeats     = %d,\n'):format(PROTOCOL.N_REPEATS))
        mf:write(('        nfold         = %d,\n'):format(PROTOCOL.NFOLD))
        mf:write(('        inner_fold    = %d,\n'):format(PROTOCOL.INNER_FOLD))
        mf:write(('        seed          = %d,\n'):format(PROTOCOL.SEED))
        mf:write(('        usable_floor  = %.4f,\n'):format(PROTOCOL.USABLE_FLOOR))
        mf:write(('        miss_ceiling  = %.4f,\n'):format(PROTOCOL.MISS_CEILING))
        mf:write(('        rho_floor     = %.4f,\n'):format(PROTOCOL.RHO_FLOOR))
        mf:write(('        endpoint_floor = %.4f,\n'):format(PROTOCOL.ENDPOINT_FLOOR))
        mf:write('    },\n')
        mf:write('    selections = {\n')
        for _, dc in ipairs(decisions) do
            mf:write('        {\n')
            mf:write(('            inst = %s, candidate = %s, scale = %s,\n')
                :format(Q(dc.inst), Q(dc.candidate), Q(dc.scale)))
            mf:write(('            n_features = %d, n_target = %d, n_aux = %d, n_weird = %d,\n')
                :format(dc.n_features, dc.n_target, dc.n_aux, dc.n_weird))
            mf:write(('            usable_mean = %.6f, usable_lower = %.6f, miss_upper = %.6f,\n')
                :format(dc.usable_mean, dc.usable_lower, dc.miss_upper))
            mf:write(('            rho_mean = %.6f, rho_lo_split = %.6f, rho_hi_split = %.6f,\n')
                :format(dc.rho_mean, dc.rho_lo_split or dc.rho_mean,
                        dc.rho_hi_split or dc.rho_mean))
            -- The gate's actual rho input. Written as nil when no bootstrap ran, which
            -- is the signal that rho_mean was used instead.
            mf:write(('            rho_lower = %s,\n')
                :format(dc.rho_lower and ('%.6f'):format(dc.rho_lower) or 'nil'))
            mf:write(('            endpoint_lower = %s, endpoint_n = %s,\n')
                :format(dc.endpoint_lower and ('%.6f'):format(dc.endpoint_lower) or 'nil',
                        dc.endpoint_n and ('%d'):format(dc.endpoint_n) or 'nil'))
            mf:write(('            gate_passed = %s,\n'):format(tostring(dc.gate_passed)))
            mf:write('        },\n')
        end
        mf:write('    },\n')
        mf:write('}\n')
        mf:close()
        MsgConsole(('\n[decision manifest written to %s]\n'):format(_manifest))
    end
end

CloseReport()
