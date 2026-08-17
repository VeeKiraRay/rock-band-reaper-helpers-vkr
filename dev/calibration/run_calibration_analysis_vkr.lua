-- @description Rock Band Difficulty Calibration - analysis
-- @author VeeKiraRay
-- @about
--   Reads dev/calibration/corpus_scores.csv (written by run_calibration_vkr.lua)
--   and reports, per instrument:
--     * Spearman rho of each individual factor against the official rank, measured
--       on rb3_dlc rows only - the diagnostic showing which factors carry signal.
--     * A k-fold CROSS-VALIDATED multi-factor fit of score -> rank, with rho, mean
--       absolute rank error, and exact / within-one tier accuracy. Every row is
--       predicted by a model that never saw it.
--     * The same fit with the Lego rows excluded, so their contribution is visible.
--     * Standardized coefficients, for interpreting which factors matter.
--     * Worst cross-validated residuals by song name, which is how the "check the
--       residuals for structure" step actually gets done.
--     * The origin check: an rb3_dlc-only model applied to the Lego songs out of
--       sample, giving the scale offset between the two eras.
--
--   RB3 DLC is the target throughout. Auxiliary origins (Lego, the RB2 disc export)
--   sit on their own rank scales, so each is down-weighted and carries its own
--   is_<origin> column: they add information without steering the model. The origin
--   check below reports each offset overall and per rank band.
--
--   Read-only. Touches no project state, so it is safe to run in any project -
--   but run it from the same repo checkout as run_calibration_vkr.lua, since it
--   reads the CSV sitting beside it.
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
dofile(_dir .. 'protocol.lua')          -- ClampRank / RankRange only; candidates unused here

-- Success thresholds, on the tier-distance grading scale.
--
-- USABLE_GOOD was set before any results were seen: the original criteria said the
-- 70-90% expectation "belongs on +/-1, target 90%+". That is the bar this reads.
-- Exact-tier agreement was expected to land 55-70% and is not a pass condition -
-- Harmonix used playtesters, so exact agreement was never realistic.
local USABLE_GOOD = 0.90   -- perfect + good, i.e. within one tier
local USABLE_OK   = 0.80
local MISS_MAX    = 0.05   -- fraction allowed to be 3+ tiers out

-- Rho is a supporting check on ordering, not the headline. A model could hit a high
-- usable% by predicting near the middle of the range; a healthy rho rules that out.
local RHO_PROMISING = 0.70

local NFOLD = 5

-- Weight on the Lego-era rows. A sweep from 0 to 1.0, measured on held-out rb3_dlc
-- rows, moved rho by at most +/-0.02 on either instrument, so this is not a
-- sensitive knob - it is set low deliberately, to let those songs inform the fit
-- without pulling it toward a different rating scale.
local LEGO_WEIGHT = 0.3

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

local function NumField(csv, row, name)
    return tonumber(Field(csv, row, name))
end

----------------------------------------------------------------------
-- Reporting helpers
----------------------------------------------------------------------

-- REAPER's ReaScript console is hard-capped at about 16 KB, and this report passed
-- that once the fifth and sixth instruments were added: the earlier instruments scroll
-- off and cannot be recovered, which is exactly the half you need when comparing a new
-- instrument against the locked ones. So every line goes to a FILE as well, and the
-- console keeps its role as the quick look.
--
-- Overwritten each run rather than appended: it is the report for the CSV sitting
-- beside it, and two runs of different data in one file is worse than none. Not
-- versioned - it is derived from the CSV, which is.
local _report = _dir .. 'calibration_analysis_report.txt'
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

-- The verdict grades on TIER DISTANCE, not on rho.
--
-- Rho measures whether the model orders songs correctly, which is the right
-- diagnostic while the factors are being chosen. But the product question is "is
-- the suggestion close enough to be worth having", and for that a tier landing one
-- step away is still a good starting point for an author. Harmonix set these ranks
-- with playtesters rather than a formula, and two charts of identical density can
-- genuinely differ in feel, so exact agreement was never the realistic target.
--
-- Rho is still reported alongside, because a high usable% with a poor rho would mean
-- the model is only succeeding by predicting near the middle of the range.
local function Verdict(dist, rho)
    if not dist or dist.n == 0 then return 'n/a' end
    local usable = dist.usable / dist.n
    local miss   = dist.miss / dist.n
    -- Signed, not absolute: a strongly NEGATIVE rho means the model orders songs
    -- backwards, which is a failure, not sound ordering. Unreachable with these
    -- factors, but math.abs here read as deliberate when it was not.
    local ord    = (rho and rho >= RHO_PROMISING)

    if usable >= USABLE_GOOD and miss <= MISS_MAX and ord then
        return ('GOOD - %.0f%% land within one tier; usable as an advisory suggestion')
            :format(usable * 100)
    end
    if usable >= USABLE_GOOD and not ord then
        return ('SUSPECT - %.0f%% usable but weak ordering (rho %.2f); likely predicting near the mean')
            :format(usable * 100, rho or 0)
    end
    if usable >= USABLE_OK then
        return ('FAIR - %.0f%% usable, %.0f%% total misses; worth improving before shipping')
            :format(usable * 100, miss * 100)
    end
    return ('POOR - only %.0f%% land within one tier'):format(usable * 100)
end

local function Subset(list, idxs)
    local out = {}
    for _, i in ipairs(idxs) do out[#out + 1] = list[i] end
    return out
end

-- Feature vector plus one indicator per auxiliary origin, appended in
-- PROTOCOL.AUX_ORIGINS order (see WithOrigin in protocol.lua, which this mirrors).
--
-- Each indicator is a nuisance parameter, not a difficulty factor: it lets the fit
-- account for "this row came from a differently-calibrated game" so the real
-- coefficients are estimated cleanly. Predictions for a new song pass 0 for all of
-- them, i.e. the RB3 scale, which is the scale a custom should be rated on.
--
-- Takes the row's ORIGIN rather than a prepared flag, so a caller cannot write one
-- origin's 1 into another's column once a second indicator exists.
local function WithOrigin(fv, origin)
    local out = {}
    for j = 1, #fv do out[j] = fv[j] end
    for _, aux in ipairs(PROTOCOL.AUX_ORIGINS) do
        out[#out + 1] = (origin == aux.origin) and 1 or 0
    end
    return out
end

----------------------------------------------------------------------
-- Per-instrument analysis
----------------------------------------------------------------------

local function Collect(csv, inst)
    local d = { feats = {}, ranks = {}, origins = {}, names = {}, span_src = {},
                packs = {}, tight_ok = {} }
    for _, row in ipairs(csv.rows) do
        if Field(csv, row, 'instrument') == inst then
            local rank = NumField(csv, row, 'rank')
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = NumField(csv, row, k)
                if v == nil then ok = false else fv[j] = v end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]    = fv
                d.ranks[n]    = rank
                d.origins[n]  = Field(csv, row, 'origin')
                d.names[n]    = Field(csv, row, 'shortname')
                d.span_src[n] = Field(csv, row, 'span_source')
                -- Optional columns: absent in runs written before they existed, and
                -- neither is needed for the fit, so a nil must not reject the row.
                d.packs[n]    = Field(csv, row, 'pack')
                d.tight_ok[n] = Field(csv, row, 'tight_measured')
            end
        end
    end
    return d
end

-- Cross-validated predictions for the rows in `target` (indices into d).
--
-- Every fold trains on the other folds' target rows plus all of `extra` (the
-- down-weighted other-origin rows, which are never predicted and never held out).
-- Returns pred, act, order - order maps each prediction back to its row index.
--
-- CV rather than one split, because with n around 110 a single 36-row holdout swung
-- guitar rho between 0.62 and 0.79 depending on which rows landed in it. One number
-- from one split was mostly noise; here every row is predicted exactly once by a
-- model that never saw it.
local function CrossValidate(d, target, extra, extra_weight)
    local folds = KFoldIndices(#target, NFOLD)
    local pred, act, order = {}, {}, {}
    -- Clamped to the observed label range, same as the protocol - see ClampRank. Only
    -- the printed MAE moves; tier grades and rho do not.
    local rank_lo, rank_hi = RankRange(d, target)

    for f = 1, #folds do
        local X, ys, ws = {}, {}, {}
        for g = 1, #folds do
            if g ~= f then
                for _, ti in ipairs(folds[g]) do
                    local i = target[ti]
                    X[#X + 1]   = WithOrigin(d.feats[i], nil)
                    ys[#ys + 1] = d.ranks[i]
                    ws[#ws + 1] = 1.0
                end
            end
        end
        for _, i in ipairs(extra) do
            X[#X + 1]   = WithOrigin(d.feats[i], d.origins[i])
            ys[#ys + 1] = d.ranks[i]
            -- Per origin, so two auxiliary sets can carry different weights. The
            -- extra_weight argument is the fallback for callers that pass a hand-built
            -- set (the leaner-factor sweeps below).
            ws[#ws + 1] = AuxWeight(d.origins[i]) or extra_weight
        end
        local fit = MultiFit(X, ys, nil, ws)
        if not fit then return nil end
        for _, ti in ipairs(folds[f]) do
            local i = target[ti]
            local n = #pred + 1
            pred[n]  = ClampRank(ApplyFit(WithOrigin(d.feats[i], nil), fit), rank_lo, rank_hi)
            act[n]   = d.ranks[i]
            order[n] = i
        end
    end
    return pred, act, order
end

local function TiersFor(inst, pred, act)
    local pt, at = {}, {}
    for i = 1, #pred do
        -- A fit can predict a negative rank; clamp to 1 so it lands in Warmup rather
        -- than reading as "no part". inst is already the songs.dta rank key, which
        -- is what RANK_TIER_THRESHOLDS is keyed by.
        pt[i] = TierForRank(inst, math.max(1, pred[i]))
        at[i] = TierForRank(inst, act[i])
    end
    return pt, at
end

local function ReportMetrics(label, inst, pred, act)
    if not pred then
        Msg(('    %-22s fit failed\n'):format(label))
        return nil
    end
    local rho = Spearman(pred, act)
    local pt, at = TiersFor(inst, pred, act)
    local d = TierDistance(pt, at)
    Msg(('    %-22s usable %5.1f%%   rho %s   MAE %5.1f   (n=%d)\n')
        :format(label, d.usable / d.n * 100,
                rho and ('%+.3f'):format(rho) or ' n/a ',
                MeanAbsError(pred, act), d.n))
    return rho, d
end

-- The grading scale, spelled out. This is the product metric: how often the
-- suggestion is close enough to be worth having.
local function ReportGrades(d)
    if not d or d.n == 0 then return end
    local function line(name, count, note)
        Msg(('      %-8s %-14s %3d   %5.1f%%%s\n')
            :format(name, note, count, count / d.n * 100, ''))
    end
    Msg('\n    grade distribution (rhythm-game style):\n')
    line('PERFECT', d.perfect, 'exact tier')
    line('GOOD',    d.good,    '1 tier off')
    line('BAD',     d.bad,     '2 tiers off')
    line('MISS',    d.miss,    '3+ tiers off')
    Msg(('      %-8s %-14s %3d   %5.1f%%\n')
        :format('->', 'usable', d.usable, d.usable / d.n * 100))
end

local function AnalyseInstrument(csv, inst)
    local d = Collect(csv, inst)

    local rb_all, other_idx = PartitionIndices(d.origins, function(o) return o == 'rb3_dlc' end)
    -- Every auxiliary origin, pooled. Still called lego_idx below for continuity with
    -- the rest of this file; it is no longer Lego-only.
    local lego_idx = AuxIndices(d.origins)

    -- Disputed labels, held out of the fit. The list is normally empty; when it is
    -- not, BOTH gates are reported below so an exclusion cannot flatter the result
    -- without being visible. See the long note in weirdly_scored.lua.
    local rb_idx, weird_idx = {}, {}
    for _, i in ipairs(rb_all) do
        if IsWeirdlyScored(d.names[i], inst) then weird_idx[#weird_idx + 1] = i
        else rb_idx[#rb_idx + 1] = i end
    end

    -- n is the FITTED row count, not every row in the CSV. The excluded origins
    -- (greenday) reach no fit, so counting them here would report a sample size
    -- larger than any number below it was measured on.
    local n_fit = #rb_idx + #lego_idx
    Msg(('\n==============  %s  (n=%d fitted)  ==============\n'):format(inst:upper(), n_fit))
    if n_fit < 10 then
        Msg(('  too few rows to analyse (%d in the CSV, %d fitted)\n'):format(#d.feats, n_fit))
        return
    end

    local aux_parts = {}
    for _, a in ipairs(PROTOCOL.AUX_ORIGINS) do
        local n = 0
        for _, i in ipairs(lego_idx) do if d.origins[i] == a.origin then n = n + 1 end end
        if n > 0 then
            aux_parts[#aux_parts + 1] = ('%d %s (weight %.2f)'):format(n, a.origin, a.weight)
        end
    end
    Msg(('  rows: %d rb3_dlc (the target), %s, %d excluded from all fits\n')
        :format(#rb_idx,
                #aux_parts > 0 and table.concat(aux_parts, ', ') or 'no auxiliary origins',
                #other_idx - #lego_idx))

    -- Always printed, even at zero, so the mechanism is visibly working before it
    -- ever holds anything - and so a future run where it is non-zero looks different
    -- rather than merely unremarked.
    Msg(('  disputed labels held out: %d of %d on the list (cap ~2%% of the corpus)\n')
        :format(#weird_idx, WeirdlyScoredCount()))
    for _, i in ipairs(weird_idx) do
        Msg(('    %-24s rank %-4d  %s\n')
            :format(d.names[i], d.ranks[i],
                    WeirdlyScoredReason(d.names[i], inst) or '(no reason given!)'))
    end

    local n_fb = 0
    for _, s in ipairs(d.span_src) do
        if s ~= 'anim' then n_fb = n_fb + 1 end
    end
    Msg(('  playing spans: %d from animation events, %d from the fallback\n')
        :format(#d.feats - n_fb, n_fb))

    -- Charts with no within-segment gem change have no measurable change interval,
    -- so tight_p10/tight_med sit at 0 - which for an interval factor reads to the
    -- fit as maximally tight. Expected to be 0 rows; reported because a nonzero
    -- count would mean two factors are lying on those rows.
    local n_untight = 0
    for _, v in ipairs(d.tight_ok) do
        if v == 'false' then n_untight = n_untight + 1 end
    end
    if n_untight > 0 then
        Msg(('  WARNING: %d rows have no measured change interval; their tight_* factors\n')
            :format(n_untight))
        Msg('           read as maximally tight rather than as unmeasured.\n')
    end

    -- Pack concentration. Rows from one pack are related songs, so random row folds
    -- over a corpus dominated by a few packs report better than a genuinely unseen
    -- song would score. This does not correct the numbers below - it says how much
    -- to trust them until a grouped leave-one-pack-out check is run.
    if d.packs[1] then
        local by_pack, n_packs, biggest_n = {}, 0, 0
        for _, i in ipairs(rb_idx) do
            local p = d.packs[i] or '?'
            if not by_pack[p] then n_packs = n_packs + 1 end
            by_pack[p] = (by_pack[p] or 0) + 1
            if by_pack[p] > biggest_n then biggest_n = by_pack[p] end
        end
        Msg(('  packs: %d distinct across the rb3_dlc rows; largest holds %d (%.0f%%)\n')
            :format(n_packs, biggest_n, biggest_n / math.max(1, #rb_idx) * 100))
        if biggest_n / math.max(1, #rb_idx) > 0.15 then
            Msg('           -> one pack carries enough rows that random folds are\n')
            Msg('              optimistic; treat the CV figures as an upper bound.\n')
        end
    end

    if #rb_idx < 20 then
        Msg('  too few rb3_dlc rows to fit against\n')
        return
    end

    -- 1. Per-factor rho on rb3_dlc only, so the Lego scale shift cannot distort it.
    Msg('\n  -- individual factors vs rank, rb3_dlc only (Spearman) --\n')
    local rb_ranks = Subset(d.ranks, rb_idx)
    local best_k, best_rho = nil, 0
    for j, k in ipairs(SCORE_FACTOR_KEYS) do
        local col = {}
        for n, i in ipairs(rb_idx) do col[n] = d.feats[i][j] end
        local rho = Spearman(col, rb_ranks)
        Msg(('    %-14s rho = %s\n'):format(k, rho and ('%+.3f'):format(rho) or 'n/a'))
        if rho and math.abs(rho) > math.abs(best_rho) then best_k, best_rho = k, rho end
    end
    if best_k then
        Msg(('    strongest single factor: %s (rho %+.3f)\n'):format(best_k, best_rho))
    end

    -- 2. Cross-validated fit. The headline, and what the verdict reads from.
    Msg(('\n  -- %d-fold cross-validated fit, evaluated on rb3_dlc --\n'):format(NFOLD))
    local pred, act, order = CrossValidate(d, rb_idx, lego_idx, LEGO_WEIGHT)
    local rho_cv, dist = ReportMetrics('with lego (weighted)', inst, pred, act)
    -- The same thing without Lego, so its contribution is visible rather than assumed.
    local pred0, act0 = CrossValidate(d, rb_idx, {}, 0)
    ReportMetrics('rb3_dlc alone', inst, pred0, act0)
    -- The gate WITH the disputed rows folded back in. They were never in a training
    -- fold, so predicting them from the full fit is genuinely out of sample and their
    -- tier distances can join the CV pool directly.
    --
    -- This is the guard that makes the exclusion honest: any entry on the disputed
    -- list moves these two numbers apart, and the difference is the exact amount the
    -- headline owes to having removed songs.
    if pred and act and #weird_idx > 0 then
        local Xw, yw, ww = {}, {}, {}
        for _, i in ipairs(rb_idx) do
            Xw[#Xw + 1], yw[#yw + 1], ww[#ww + 1] = WithOrigin(d.feats[i], nil), d.ranks[i], 1.0
        end
        for _, i in ipairs(lego_idx) do
            Xw[#Xw + 1], yw[#yw + 1], ww[#ww + 1] = WithOrigin(d.feats[i], d.origins[i]), d.ranks[i], AuxWeight(d.origins[i]) or LEGO_WEIGHT
        end
        local fit_w = MultiFit(Xw, yw, nil, ww)
        if fit_w then
            local p2, a2 = {}, {}
            for n = 1, #pred do p2[n], a2[n] = pred[n], act[n] end
            for _, i in ipairs(weird_idx) do
                p2[#p2 + 1] = ApplyFit(WithOrigin(d.feats[i], nil), fit_w)
                a2[#a2 + 1] = d.ranks[i]
            end
            ReportMetrics('incl. disputed rows', inst, p2, a2)
            Msg('      ^ the gate WITHOUT the exclusions. The gap between these two\n')
            Msg('        lines is what the headline owes to removing songs.\n')
        end
    end

    ReportGrades(dist)
    if dist then
        Msg(('\n    VERDICT: %s\n'):format(Verdict(dist, rho_cv)))
    end

    -- 2b. Lean subsets, cross-validated the same way. Keeps "is the full set
    -- earning its keep" in front of every run rather than being assumed: on the
    -- previous factor set two factors outscored all thirteen on bass, because the
    -- extra columns were adding variance rather than information.
    if SCORE_LEAN_SETS and #SCORE_LEAN_SETS > 0 then
        Msg('\n  -- leaner factor sets, same cross-validation --\n')
        -- Index of each factor key, so a subset can be sliced out of the full vector.
        local pos = {}
        for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end
        -- `set`, not `S`: repo-wide, S is the per-script state table.
        for _, set in ipairs(SCORE_LEAN_SETS) do
            local ok = true
            for _, k in ipairs(set.keys) do
                if not pos[k] then ok = false end
            end
            if ok then
                local sub = { feats = {}, ranks = d.ranks, origins = d.origins }
                for i = 1, #d.feats do
                    local v = {}
                    for _, k in ipairs(set.keys) do v[#v + 1] = d.feats[i][pos[k]] end
                    sub.feats[i] = v
                end
                local p, a = CrossValidate(sub, rb_idx, lego_idx, LEGO_WEIGHT)
                ReportMetrics(set.name, inst, p, a)
            else
                Msg(('    %-22s skipped (unknown factor key)\n'):format(set.name))
            end
        end
    end

    -- 3. Coefficients from a full fit, for interpretation only - never for the
    -- headline, since a fit reports optimistically on its own training rows.
    local Xall, yall, wall = {}, {}, {}
    for _, i in ipairs(rb_idx) do
        Xall[#Xall + 1] = WithOrigin(d.feats[i], nil)
        yall[#yall + 1] = d.ranks[i]
        wall[#wall + 1] = 1.0
    end
    for _, i in ipairs(lego_idx) do
        Xall[#Xall + 1] = WithOrigin(d.feats[i], d.origins[i])
        yall[#yall + 1] = d.ranks[i]
        wall[#wall + 1] = AuxWeight(d.origins[i]) or LEGO_WEIGHT
    end
    local full = MultiFit(Xall, yall, nil, wall)
    if full then
        Msg('\n  -- coefficients (standardized; full fit, interpretation only) --\n')
        for j, k in ipairs(SCORE_FACTOR_KEYS) do
            Msg(('    %-14s %+8.2f\n'):format(k, full.coefs[j]))
        end
        -- The indicators occupy the trailing coefficients, in AUX_ORIGINS order.
        local base = #full.coefs - #PROTOCOL.AUX_ORIGINS
        for ai, a in ipairs(PROTOCOL.AUX_ORIGINS) do
            local n = 0
            for _, i in ipairs(lego_idx) do if d.origins[i] == a.origin then n = n + 1 end end
            if n > 0 then
                Msg(('    %-14s %+8.2f  <- scale shift, not a difficulty factor\n')
                    :format(a.flag, full.coefs[base + ai]))
            else
                -- No rows of this origin for this instrument (Lego Rock Band and the RB2
                -- export both predate keys, so PART KEYS has none of either). The column
                -- is then constant, MultiFit neutralises it by clamping its sd, and
                -- whatever coefficient comes back describes nothing.
                Msg(('    %-14s      n/a  <- no %s rows exist for this instrument\n')
                    :format(a.flag, a.origin))
            end
        end
        Msg(('    %-14s %+8.2f\n'):format('(intercept)', full.intercept))
    end

    -- 4. Worst residuals, from the cross-validated predictions so they are genuine
    -- misses rather than fit artefacts. A recurring kind of song here names the next
    -- factor to add - this listing is what produced the totals and repetition ones.
    -- Sorted by TIER distance, not by rank error, because the tier is what the grade
    -- counts. The two disagree more than you would expect: on one bass run the single
    -- worst rank error (-206, a predicted rank of -74 against an actual 132) was an
    -- EXACT tier match, since both fell in Warmup - while the songs that actually
    -- missed by two tiers had rank errors of only +62 and +70. Sorting by rank error
    -- listed two perfect matches and omitted the real failures.
    if pred and act and order then
        local resid = {}
        local pt, at = TiersFor(inst, pred, act)
        for n = 1, #pred do
            local i = order[n]
            resid[#resid + 1] = {
                name = d.names[i], origin = d.origins[i], rank = act[n],
                rank_err = pred[n] - act[n],
                pt = pt[n], at = at[n],
                td = (pt[n] and at[n]) and math.abs(pt[n] - at[n]) or 0,
            }
        end
        table.sort(resid, function(a, b)
            if a.td ~= b.td then return a.td > b.td end
            return math.abs(a.rank_err) > math.abs(b.rank_err)
        end)
        Msg('\n  -- worst 10 by tier distance, cross-validated --\n')
        for n = 1, math.min(10, #resid) do
            local e = resid[n]
            Msg(('    %-24s %-8s rank %-4d  said tier %s, actual %s  (%d off, rank %+.0f)\n')
                :format(e.name, e.origin, e.rank,
                        tostring(e.pt), tostring(e.at), e.td, e.rank_err))
        end
    end

    -- 5. Origin check: an rb3_dlc-only model applied to each auxiliary origin OUT OF
    -- SAMPLE. A least-squares fit is unbiased on its own training data, so the rb3
    -- baseline is 0 by construction and each origin's mean IS its offset. (An earlier
    -- version restricted both to a shared rank band, which broke that property and
    -- left two numbers that only meant something once differenced.)
    --
    -- Reported PER TIER BAND as well as overall, which tests a specific claim: a disc's
    -- setlist is picked to span the difficulty range, so its ranks may be pushed apart
    -- to fill the scale rather than measured independently - in which case the offset
    -- would be small at the extremes and large in the middle, rather than a constant
    -- shift the indicator column can absorb. A single mean cannot tell those apart.
    if #lego_idx >= 10 then
        local rb_fit = MultiFit(Subset(d.feats, rb_idx), rb_ranks)
        if rb_fit then
            local s_rb = 0
            for _, i in ipairs(rb_idx) do
                s_rb = s_rb + (ApplyFit(d.feats[i], rb_fit) - d.ranks[i])
            end
            Msg('\n  -- origin check: rb3_dlc-only model applied to each origin out of sample --\n')
            Msg(('    mean (pred - actual) on rb3_dlc itself : %+.1f   <- ~0 by construction\n')
                :format(s_rb / #rb_idx))

            for _, a in ipairs(PROTOCOL.AUX_ORIGINS) do
                local rows = {}
                for _, i in ipairs(lego_idx) do
                    if d.origins[i] == a.origin then rows[#rows + 1] = i end
                end
                if #rows == 0 then
                    Msg(('    %-10s no rows for this instrument\n'):format(a.origin))
                else
                    local sum = 0
                    for _, i in ipairs(rows) do
                        sum = sum + (ApplyFit(d.feats[i], rb_fit) - d.ranks[i])
                    end
                    local off = sum / #rows
                    Msg(('    mean (pred - actual) on %-8s : %+.1f  (n=%d)   <- the scale offset\n')
                        :format(a.origin, off, #rows))
                    if math.abs(off) < 15 then
                        Msg(('    -> %s sits on the rb3_dlc scale\n'):format(a.origin))
                    else
                        Msg(('    -> %s rates the same chart about %.0f rank points %s than RB3.\n')
                            :format(a.origin, math.abs(off), off > 0 and 'LOWER' or 'HIGHER'))
                        Msg(('       Absorbed by the %s column; a new song predicts with it at 0,\n')
                            :format(a.flag))
                        Msg('       i.e. on the RB3 scale.\n')
                    end
                    -- Per tier band. A constant shift stays flat here; a setlist spread
                    -- to fill the scale bows in the middle.
                    if #rows >= 12 then
                        local bands = { { 1, 200 }, { 200, 300 }, { 300, 1000 } }
                        local parts = {}
                        for _, b in ipairs(bands) do
                            local s, n = 0, 0
                            for _, i in ipairs(rows) do
                                if d.ranks[i] >= b[1] and d.ranks[i] < b[2] then
                                    s = s + (ApplyFit(d.feats[i], rb_fit) - d.ranks[i])
                                    n = n + 1
                                end
                            end
                            parts[#parts + 1] = n > 0
                                and ('%d-%s: %+.0f (n=%d)'):format(b[1],
                                    b[2] == 1000 and 'up' or tostring(b[2]), s / n, n)
                                or ('%d-%s: -'):format(b[1],
                                    b[2] == 1000 and 'up' or tostring(b[2]))
                        end
                        Msg(('       by rank band: %s\n'):format(table.concat(parts, ',  ')))
                    end
                end
            end
        end
    end

    -- Handed back so Main can run the controlled patterns through it. Those live
    -- outside this function because they are about the MODEL rather than about the
    -- corpus. The rank range travels with the fit so a synthetic pattern landing
    -- outside the training data can be flagged as extrapolation rather than reported
    -- as a prediction.
    local lo, hi = math.huge, -math.huge
    for _, i in ipairs(rb_idx) do
        if d.ranks[i] < lo then lo = d.ranks[i] end
        if d.ranks[i] > hi then hi = d.ranks[i] end
    end
    return full, lo, hi
end

----------------------------------------------------------------------
-- Controlled patterns: what would a synthetic chart actually be rated?
----------------------------------------------------------------------

-- Every number above is a correlation or an aggregate. This block converts the
-- fitted model back into the units the product will use - a rank and a tier - by
-- feeding it charts whose difficulty is known by construction.
--
-- It answers "does tempo actually change the rating, and by how much" directly,
-- and then keeps answering it: if a 240 bpm sixteenth-note chart ever predicts a
-- lower tier than the same pattern at 60, that is visible on every run instead of
-- being discovered later. The scorer's own unit tests assert that density doubles
-- with tempo; they cannot say whether that survives the fit.
--
-- Pure Lua tables, no REAPER - the same builders the unit tests use.
local function BuildRun(n, qn_step, bpm, pitches_fn, qn0, len_qn)
    local ev  = {}
    local qn  = qn0 or 0
    local spq = 60.0 / bpm
    local len = len_qn or 0.1
    for i = 1, n do
        local t = qn * spq
        ev[#ev + 1] = {
            s = t, e = t + len * spq, qn = qn, qn_e = qn + len,
            pitches = pitches_fn and pitches_fn(i) or { 96 },
        }
        qn = qn + qn_step
    end
    return ev
end
local function Alt(i) return { 96 + (i % 2) } end

local function ReportControlledPatterns(inst, fit, rank_lo, rank_hi)
    if not fit then return end
    -- These are GEM charts - note runs at pitches 96/97 with no lyrics - so running them
    -- through a vocal fit would rate a guitar riff with a singing model and print a
    -- number that means nothing. Vocals needs its own pattern builder (a syllable run at
    -- a known density, an octave-leap melody, a talkie passage) before it can have this
    -- section; until then, say so rather than print nonsense.
    if inst == 'vocals' then
        Msg('\n  -- controlled patterns: skipped for vocals --\n')
        Msg('    The synthetic charts here are gem runs with no lyrics and no phrases,\n')
        Msg('    so every vocal factor would read 0 and the rating would be arithmetic\n')
        Msg('    on an empty chart. Vocals needs its own pattern builder.\n')
        return
    end
    Msg('\n  -- controlled patterns through the fitted model --\n')
    Msg('    (synthetic charts, difficulty known by construction; origin flags = 0)\n')

    local function Rate(label, events, opts)
        local spans = { { s = events[1].s, e = events[#events].e } }
        local sc = ScoreChart(events, spans, opts)
        local fv = {}
        -- `or 0` since round 11: SCORE_FACTOR_KEYS spans the gem AND vocal factor sets,
        -- and ScoreChart produces only the gem half. A nil here leaves a HOLE in the
        -- vector rather than a zero, so ApplyFit walks off the end of it and dies in
        -- stats.lua with "arithmetic on a nil value". The CSV writer has the same guard.
        for j, k in ipairs(SCORE_FACTOR_KEYS) do fv[j] = sc[k] or 0 end
        -- One zero per auxiliary origin, matching what WithOrigin appends: rate on the
        -- RB3 scale. Driven off AUX_ORIGINS rather than a literal, because appending a
        -- fixed number here is the same hole the comment above describes - the vector
        -- would come up short the moment a second origin was declared.
        for _ = 1, #PROTOCOL.AUX_ORIGINS do fv[#fv + 1] = 0 end
        local rank = ApplyFit(fv, fit)
        local tier = TierForRank(inst, math.max(1, rank))
        -- A linear fit extrapolates without complaint, and a synthetic pattern can
        -- easily be more extreme than anything in the corpus - a 32nd-note wall has
        -- no counterpart among real charts. Outside the observed rank range the
        -- number is arithmetic, not a prediction, and must not read as one.
        local flag = ''
        if rank_lo and rank_hi and (rank < rank_lo or rank > rank_hi) then
            flag = ('   <-- EXTRAPOLATED (corpus %d-%d)'):format(rank_lo, rank_hi)
        end
        Msg(('    %-34s rank %6.0f   tier %s  (%s)%s\n')
            :format(label, rank, tostring(tier), TierName(tier), flag))
        return rank
    end

    -- The BPM ladder: identical 16th-note pattern, four tempos. Note count is held
    -- constant, so anything that moves is tempo doing the work.
    local prev = nil
    for _, bpm in ipairs({ 60, 120, 180, 240 }) do
        local ev = BuildRun(240, 0.25, bpm, Alt)
        local rank = Rate(('240x 16ths @ %d bpm'):format(bpm), ev)
        if prev and rank < prev then
            Msg('      <-- WARNING: faster chart rated LOWER than the slower one.\n')
            Msg('          Tempo handling or the fit is wrong; investigate before\n')
            Msg('          trusting anything above.\n')
        end
        prev = rank
    end

    -- Same note count, same tempo, difficulty concentrated vs spread. Tests the
    -- round-4 hypothesis in product units rather than in coefficients.
    local uniform = BuildRun(240, 0.5, 120, Alt)
    Rate('240 notes, even 8ths', uniform)
    local burst = {}
    for _, e in ipairs(BuildRun(120, 1.0,  120, Alt))      do burst[#burst + 1] = e end
    for _, e in ipairs(BuildRun(120, 0.125, 120, Alt, 130)) do burst[#burst + 1] = e end
    local solo = { { s = burst[121].s, e = burst[#burst].e } }
    Rate('240 notes, half slow + 32nd burst', burst)
    Rate('  the same, burst marked as solo', burst, { marked_solo_spans = solo })
    Msg('      the last two differ only in whether the hard part is MARKED, which is\n')
    Msg('      what solo_change_ratio is supposed to notice.\n')
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty calibration - analysis  ======\n')

local csv, err = LoadCsv(_csv)
if not csv then
    Msg(('\nCould not read the scores CSV.\n  %s\n\nRun run_calibration_vkr.lua first.\n')
        :format(tostring(err)))
    return
end

Msg(('\nRows: %d\n'):format(#csv.rows))

-- Fail loudly on a CSV written before the current factor set. Without this the
-- per-row gather silently rejects every row for a missing column and the report
-- reads "too few rows to analyse", which says nothing about why.
local missing = {}
for _, k in ipairs(SCORE_FACTOR_KEYS) do
    if not csv.header[k] then missing[#missing + 1] = k end
end
if #missing > 0 then
    Msg('\nThis CSV predates the current factor set - missing columns:\n')
    Msg('  ' .. table.concat(missing, ', ') .. '\n\n')
    Msg('Delete corpus_scores.csv and re-run run_calibration_vkr.lua to rescore.\n')
    Msg('(The scoring run is resumable, but only for songs whose rows already match\n')
    Msg(' the current columns - a factor set change means a full rescore.)\n')
    return
end

local seen, order = {}, {}
for _, row in ipairs(csv.rows) do
    local inst = Field(csv, row, 'instrument')
    if inst and not seen[inst] then
        seen[inst] = true
        order[#order + 1] = inst
    end
end

for _, inst in ipairs(order) do
    local fit, rank_lo, rank_hi = AnalyseInstrument(csv, inst)
    ReportControlledPatterns(inst, fit, rank_lo, rank_hi)
end

Msg('\n')
Msg('Grading scale (all figures cross-validated on rb3_dlc):\n')
Msg('  PERFECT  exact tier      the suggestion is spot on\n')
Msg('  GOOD     1 tier off      still a useful starting point for an author\n')
Msg('  BAD      2 tiers off     misleading\n')
Msg('  MISS     3+ tiers off    worthless\n')
Msg('\n')
Msg(('Pass condition: usable (perfect+good) >= %.0f%%, misses <= %.0f%%, and rho >= %.2f\n')
    :format(USABLE_GOOD * 100, MISS_MAX * 100, RHO_PROMISING))
Msg('The rho condition exists only to rule out hitting the usable% by predicting near\n')
Msg('the middle of the range. Exact-tier agreement is NOT a pass condition: Harmonix\n')
Msg('set these ranks with playtesters, and two charts of identical density can differ\n')
Msg('in how hard they feel, so exact agreement was never the realistic target.\n')
Msg('\nAlso check the residuals above for structure: misses clustering on one kind of\n')
Msg('song name the missing factor, which is more actionable than a slightly higher rho.\n')

CloseReport()
