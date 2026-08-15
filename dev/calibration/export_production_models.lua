-- Freeze the six selected models into lib/reaper_difficulty_models.lua.
--
-- This is the bridge the calibration rounds never built. The protocol SELECTS a candidate
-- shape per instrument; it never fits a final model or writes one down. Until this ran,
-- the shipped suggester had no coefficients to ship.
--
-- Run from the repository root, with a plain Lua interpreter - no REAPER:
--
--     lua dev/calibration/export_production_models.lua
--
-- Reads corpus_scores.csv, refits each selected candidate once on every row it is allowed
-- to train on, and writes the artifact. Read-only apart from that one output file.
--
-- ---------------------------------------------------------------------------
-- WHY THE RIDGE IS CHOSEN DIFFERENTLY HERE THAN IN protocol.lua
--
-- The protocol picks a ridge INSIDE each outer fold and never needs to name one number:
-- it is cross-validating, so a different ridge per fold is fine. A shipped model has to
-- commit to one. Two things then matter that did not before.
--
--   1. REPRODUCIBILITY ACROSS INTERPRETERS. ShuffledStratifiedFolds calls math.random,
--      whose implementation CHANGED between Lua 5.3 and 5.4 (5.4 replaced it with
--      xoshiro256**). REAPER and this offline runner therefore disagree on what
--      SEED = 20260812 means, so a fold-dependent choice made here would not be the one
--      made there. This file carries its own arithmetic LCG instead - no bitwise ops, no
--      library RNG - so the same CSV produces the same artifact on any Lua.
--
--   2. A MODAL VOTE IS KNIFE-EDGE. Guitar's recorded ridge histogram is 0.01 at 36% and
--      0.1 at 31%; ~40 folds separate them out of 1100. Picking the modal winner would
--      let a handful of folds decide a shipped hyperparameter. So every grid value is
--      scored on every inner holdout of every fold of every repeat, and the one with the
--      lowest POOLED error wins, ties going to the smaller ridge. That uses the same
--      nested inner folds and the same error measure as the protocol, over strictly more
--      evidence, and it has no tie to break by luck. The full table is printed so a near
--      tie is visible rather than silent.
--
-- This is the exporter's own reproducibility rule. It does NOT re-run, re-open or
-- second-guess the protocol's SELECTION - the six candidate names below are the
-- protocol's output, copied verbatim, and their factor lists are read out of protocol.lua
-- rather than retyped.
-- ---------------------------------------------------------------------------

local _script = (arg and arg[0]) or 'dev/calibration/export_production_models.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/calibration/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))

local _csv = _dir .. 'corpus_scores.csv'
local _out = _root .. 'lib/reaper_difficulty_models.lua'

-- Schema version of the emitted artifact. Bump when the SHAPE of a model record changes
-- (a new field, a renamed one), not when the numbers move - the consumer checks this and
-- refuses a table it does not understand, which is what stops a stale artifact from being
-- read as a plausible but wrong model.
local SCHEMA = 1

dofile(_dir .. 'difficulty_score.lua')          -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')   -- appends the vocal columns to it
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')
dofile(_root .. 'lib/reaper_difficulty_predict.lua')   -- DIFFICULTY_SCALE_INV, to cross-check

----------------------------------------------------------------------
-- The selection
--
-- The protocol's output, transcribed. Only the NAMES live here; the factor lists come
-- from CandidatesFor(), so a candidate edited in protocol.lua can never silently
-- disagree with what was exported.
----------------------------------------------------------------------

local SELECTIONS = {
    { inst = 'guitar',    candidate = 'full@attacks',                     scale = 'log(rank)' },
    { inst = 'bass',      candidate = 'baseline+ent_rel@attacks',         scale = 'log(rank)' },
    { inst = 'drum',      candidate = 'full_drum',                        scale = 'rank'      },
    { inst = 'keys',      candidate = 'primary+entropy_rel+complex_peak', scale = 'rank'      },
    { inst = 'real_keys', candidate = 'primary+ent_rel@attacks',          scale = 'rank'      },
    { inst = 'vocals',    candidate = 'primary+range+parts',              scale = 'log(rank)' },
}

-- Product maturity, from the product plan's status table. Carried in the artifact so the
-- UI does not hardcode a second copy that could disagree with what was actually exported.
-- These describe validation against noisy official ranks - they are NOT the probability
-- that a given prediction is right.
local STATUS = {
    guitar = 'validated', bass = 'validated', drum = 'validated',
    keys = 'beta', real_keys = 'experimental', vocals = 'experimental',
}

----------------------------------------------------------------------
-- Failing loudly
----------------------------------------------------------------------

local _errors = 0
local function Fail(fmt, ...)
    io.write('  ERROR: ', (select('#', ...) > 0) and fmt:format(...) or fmt, '\n')
    _errors = _errors + 1
end

----------------------------------------------------------------------
-- CSV
----------------------------------------------------------------------

local function Split(line)
    local out = {}
    for field in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = field end
    return out
end

local function LoadCsv(path)
    local f = io.open(path, 'r')
    if not f then return nil, 'not found: ' .. path end
    local header_line, header, rows = nil, nil, {}
    for line in f:lines() do
        if line ~= '' then
            if not header then
                header_line = line
                header = {}
                for i, name in ipairs(Split(line)) do header[name] = i end
            else
                rows[#rows + 1] = Split(line)
            end
        end
    end
    f:close()
    if not header then return nil, 'empty file' end
    return { header = header, header_line = header_line, rows = rows }
end

-- Detects a header that is not the one this artifact was built from. Deliberately a plain
-- polynomial hash and not a checksum with security properties: the job is to notice an
-- edited or reordered column set, and a consumer comparing fingerprints does not need
-- more than that. Arithmetic only, so it agrees across Lua versions.
local function Fingerprint(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    return h
end

----------------------------------------------------------------------
-- Portable RNG and fold assignment
--
-- Mirrors ShuffledStratifiedFolds in stats.lua exactly - group by stratum in sorted key
-- order, Fisher-Yates inside each stratum, deal round-robin from a rotating start - with
-- the library RNG replaced by the LCG below. Same procedure, reproducible everywhere.
----------------------------------------------------------------------

-- Numerical Recipes' LCG constants. Every intermediate stays under 2^53, so the
-- arithmetic is exact in a double and identical whether Lua has integers or not.
local function NewRng(seed)
    local state = seed % 4294967296
    return function(n)          -- uniform integer in 1..n
        state = (1664525 * state + 1013904223) % 4294967296
        return math.floor(state / 4294967296 * n) + 1
    end
end

local function StratifiedFolds(strata, k, rng)
    local n = #strata
    k = math.max(2, math.min(k or 5, n))

    local by, keys = {}, {}
    for i = 1, n do
        local key = tostring(strata[i])
        if not by[key] then by[key] = {}; keys[#keys + 1] = key end
        local g = by[key]
        g[#g + 1] = i
    end
    table.sort(keys)

    local folds = {}
    for f = 1, k do folds[f] = {} end
    local start = 0
    for _, key in ipairs(keys) do
        local g = by[key]
        for i = #g, 2, -1 do
            local j = rng(i)
            g[i], g[j] = g[j], g[i]
        end
        for i, row in ipairs(g) do
            local f = ((start + i - 1) % k) + 1
            folds[f][#folds[f] + 1] = row
        end
        start = (start + #g) % k
    end
    return folds
end

----------------------------------------------------------------------
-- Collecting one instrument's rows
----------------------------------------------------------------------

local function Collect(csv, inst)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    for _, row in ipairs(csv.rows) do
        local function Field(name)
            local i = csv.header[name]
            return i and row[i] or nil
        end
        if Field('instrument') == inst then
            local rank = tonumber(Field('rank'))
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(Field(k))
                if v == nil then ok = false else fv[j] = v end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]   = fv
                d.ranks[n]   = rank
                d.origins[n] = Field('origin')
                d.names[n]   = Field('shortname')
            end
        end
    end
    return d
end

-- The protocol's training partition: rb3_dlc rows minus any disputed label are the
-- development rows, lego rows are always-training at LEGO_WEIGHT, and the single greenday
-- row is neither (it is scored into the CSV but never fitted).
local function Partition(d, inst)
    local target, extra, weird = {}, {}, {}
    for i, o in ipairs(d.origins) do
        if o == 'rb3_dlc' then
            if IsWeirdlyScored(d.names[i], inst) then weird[#weird + 1] = i
            else target[#target + 1] = i end
        elseif o == 'lego' then
            extra[#extra + 1] = i
        end
    end
    return target, extra, weird
end

----------------------------------------------------------------------
-- Design matrix
----------------------------------------------------------------------

-- Rows in the shape RunOneRepeat builds them: the candidate's factors in declared order,
-- then the is_lego origin flag. Every product prediction passes 0 for that flag.
local function BuildRows(d, idx, keys, pos, scale, is_lego, weight, X, ys, ws)
    for _, i in ipairs(idx) do
        local row = {}
        for j, k in ipairs(keys) do row[j] = d.feats[i][pos[k]] end
        row[#row + 1] = is_lego
        X[#X + 1]  = row
        ys[#ys + 1] = scale.fwd(d.ranks[i])
        ws[#ws + 1] = weight
    end
end

----------------------------------------------------------------------
-- Ridge: pooled inner-fold error over every fold of every repeat
----------------------------------------------------------------------

local function ChooseRidgePooled(d, target, extra, inst, keys, pos, scale)
    local strata = {}
    for n, ti in ipairs(target) do strata[n] = tostring(TierForRank(inst, d.ranks[ti])) end

    local err, cnt = {}, {}
    for _, g in ipairs(PROTOCOL.RIDGE_GRID) do err[g], cnt[g] = 0, 0 end

    for rep = 1, PROTOCOL.N_REPEATS do
        local rng   = NewRng(PROTOCOL.SEED + rep)
        local folds = StratifiedFolds(strata, PROTOCOL.NFOLD, rng)
        for f = 1, #folds do
            -- Training rows for this outer fold, exactly as the protocol builds them.
            local X, ys, ws = {}, {}, {}
            for g = 1, #folds do
                if g ~= f then
                    local rows = {}
                    for _, ti in ipairs(folds[g]) do rows[#rows + 1] = target[ti] end
                    BuildRows(d, rows, keys, pos, scale, 0, 1.0, X, ys, ws)
                end
            end
            BuildRows(d, extra, keys, pos, scale, 1, PROTOCOL.LEGO_WEIGHT, X, ys, ws)

            -- The protocol's own nested search, but scoring every grid value instead of
            -- keeping only the winner. KFoldIndices is deterministic round-robin, so the
            -- inner split needs no RNG and is identical everywhere.
            if #X >= PROTOCOL.INNER_FOLD * 2 then
                local inner = KFoldIndices(#X, PROTOCOL.INNER_FOLD)
                for _, ridge in ipairs(PROTOCOL.RIDGE_GRID) do
                    for a = 1, #inner do
                        local tx, ty, tw = {}, {}, {}
                        for b = 1, #inner do
                            if b ~= a then
                                for _, i in ipairs(inner[b]) do
                                    tx[#tx + 1], ty[#ty + 1], tw[#tw + 1] = X[i], ys[i], ws[i]
                                end
                            end
                        end
                        local fit = MultiFit(tx, ty, ridge, tw)
                        if fit then
                            for _, i in ipairs(inner[a]) do
                                err[ridge] = err[ridge] + math.abs(ApplyFit(X[i], fit) - ys[i])
                                cnt[ridge] = cnt[ridge] + 1
                            end
                        end
                    end
                end
            end
        end
    end

    local best, best_err, table_rows = nil, math.huge, {}
    for _, g in ipairs(PROTOCOL.RIDGE_GRID) do
        local mean = (cnt[g] > 0) and (err[g] / cnt[g]) or nil
        table_rows[#table_rows + 1] = { ridge = g, err = mean, n = cnt[g] }
        -- Strictly less than, walking the grid smallest-first, so a tie keeps the
        -- smaller ridge - the same "simpler wins" spirit as the candidate tie-break.
        if mean and mean < best_err then best, best_err = g, mean end
    end
    return best, table_rows
end

----------------------------------------------------------------------
-- Per-factor support bounds
--
-- Over the TARGET rows only, not target-plus-lego. Two different row sets for two
-- different jobs, and conflating them would be wrong in both directions:
--
--   fit.mean / fit.sd come from MultiFit over every training row INCLUDING the
--   down-weighted lego ones, because that is what standardization was computed against
--   and the coefficients are only valid paired with it.
--
--   min / max / p90 describe the support the SUGGESTION is honest about, and every
--   prediction is made with is_lego = 0, i.e. on the RB3 scale. A chart inside lego's
--   range but outside RB3's is an extrapolation of the thing being predicted.
----------------------------------------------------------------------

local function Percentile90(vals)
    if #vals == 0 then return 0 end
    local t = {}
    for i, v in ipairs(vals) do t[i] = v end
    table.sort(t)
    if #t == 1 then return t[1] end
    local idx = 0.90 * (#t - 1) + 1
    local lo, hi = math.floor(idx), math.ceil(idx)
    if lo == hi then return t[lo] end
    return t[lo] + (t[hi] - t[lo]) * (idx - lo)
end

local function FactorBounds(d, target, keys, pos)
    local bounds = {}
    for _, k in ipairs(keys) do
        local vals = {}
        for _, i in ipairs(target) do vals[#vals + 1] = d.feats[i][pos[k]] end
        local mn, mx = math.huge, -math.huge
        for _, v in ipairs(vals) do
            if v < mn then mn = v end
            if v > mx then mx = v end
        end
        bounds[k] = { min = mn, max = mx, p90 = Percentile90(vals) }
    end
    return bounds
end

-- The concentration warning's threshold, per instrument, from the same target rows.
--
-- Measured rather than assumed, because a single cutoff is provably wrong here: guitar's
-- p90 marked-solo ratio is 2.67 while bass and drums never mark a solo at all (p95 = 1.00),
-- so a shared "3.4x" would fire on nothing for half the instruments. Charts with no marked
-- solo fall back to the peak/average density ratio, whose p90 ranges from 1.58 on drums to
-- 2.74 on keys.
--
-- Both are computed for every instrument that has the columns; vocals has neither and gets
-- no concentration warning.
local function ConcentrationThresholds(d, target, pos)
    local out = {}
    local function P90(key, transform)
        local col = pos[key]
        if not col then return nil end
        local vals = {}
        for _, i in ipairs(target) do
            local v = transform and transform(i) or d.feats[i][col]
            if v then vals[#vals + 1] = v end
        end
        if #vals == 0 then return nil end
        return Percentile90(vals)
    end
    out.solo_change_ratio = P90('solo_change_ratio')
    local avg_col, peak_col = pos['density_avg'], pos['density_peak']
    if avg_col and peak_col then
        out.density_ratio = P90('density_peak', function(i)
            local a = d.feats[i][avg_col]
            if a and a > 0 then return d.feats[i][peak_col] / a end
            return nil
        end)
    end
    return out
end

----------------------------------------------------------------------
-- Emitting Lua
----------------------------------------------------------------------

-- Shortest representation that round-trips exactly. %.17g always does for a double;
-- trying 15 and 16 first keeps the artifact readable without giving up a single bit.
local function Num(v)
    if type(v) ~= 'number' then error('not a number: ' .. tostring(v)) end
    if v ~= v then error('NaN in model output') end
    if v == math.huge or v == -math.huge then error('infinite value in model output') end
    for _, p in ipairs({ '%.15g', '%.16g', '%.17g' }) do
        local s = p:format(v)
        if tonumber(s) == v then return s end
    end
    error('no round-tripping representation for ' .. tostring(v))
end

local function NumList(vals, indent)
    local parts = {}
    for _, v in ipairs(vals) do parts[#parts + 1] = Num(v) end
    -- Wrapped at a fixed width so a 27-coefficient model stays diff-able line by line.
    local lines, cur = {}, indent
    for i, s in ipairs(parts) do
        local piece = s .. (i < #parts and ', ' or '')
        if #cur + #piece > 92 and cur ~= indent then
            lines[#lines + 1] = cur
            cur = indent
        end
        cur = cur .. piece
    end
    if cur ~= indent then lines[#lines + 1] = cur end
    return table.concat(lines, '\n')
end

local function Quote(s) return ('%q'):format(s) end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

io.write('======  Difficulty models - production export  ======\n\n')

local csv, err = LoadCsv(_csv)
if not csv then
    io.write(('Could not read the scores CSV.\n  %s\n\nRun run_calibration_vkr.lua first.\n')
        :format(tostring(err)))
    os.exit(1)
end

local pos = {}
for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

for _, k in ipairs(SCORE_FACTOR_KEYS) do
    if not csv.header[k] then Fail('CSV is missing factor column %s', k) end
end
if _errors > 0 then
    io.write('\nThis CSV predates the current factor set. Rescore before exporting.\n')
    os.exit(1)
end

io.write(('CSV     : %s\n'):format(_csv))
io.write(('rows    : %d   factor columns: %d\n'):format(#csv.rows, #SCORE_FACTOR_KEYS))
io.write(('header  : fingerprint %d\n\n'):format(Fingerprint(csv.header_line)))

local models = {}

for _, sel in ipairs(SELECTIONS) do
    io.write(('==================  %s  ==================\n'):format(sel.inst:upper()))

    -- Resolve the candidate by name out of protocol.lua rather than retyping its factors.
    local cand
    for _, c in ipairs(CandidatesFor(sel.inst)) do
        if c.name == sel.candidate then cand = c break end
    end
    local scale
    for _, s in ipairs(SCALES) do
        if s.name == sel.scale then scale = s break end
    end

    if not cand then
        Fail('protocol.lua declares no candidate named %q for %s', sel.candidate, sel.inst)
    elseif not scale then
        Fail('protocol.lua declares no scale named %q', sel.scale)
    elseif not DIFFICULTY_SCALE_INV[sel.scale] then
        Fail('lib/reaper_difficulty_predict.lua cannot invert scale %q', sel.scale)
    else
        -- Every declared factor must exist exactly once and be numeric everywhere.
        local seen = {}
        for _, k in ipairs(cand.keys) do
            if not pos[k] then Fail('%s: factor %s is not in SCORE_FACTOR_KEYS', sel.inst, k) end
            if seen[k] then Fail('%s: factor %s is declared twice', sel.inst, k) end
            -- Appended by BuildRows, so a candidate declaring it too would fit the origin
            -- flag twice and shift every later coefficient.
            if k == 'is_lego' then Fail('%s: is_lego is appended, not declared', sel.inst) end
            seen[k] = true
        end

        local d = Collect(csv, sel.inst)
        local target, extra, weird = Partition(d, sel.inst)

        io.write(('  candidate        : %s / %s  (%d features)\n')
            :format(cand.name, scale.name, #cand.keys))
        io.write(('  training rows    : %d rb3_dlc + %d lego at weight %.2f  (%d disputed held out)\n')
            :format(#target, #extra, PROTOCOL.LEGO_WEIGHT, #weird))

        if #target == 0 then
            Fail('%s: no development rows', sel.inst)
        else
            local ridge, grid = ChooseRidgePooled(d, target, extra, sel.inst,
                                                  cand.keys, pos, scale)
            io.write('  pooled inner-fold error per ridge (lower is better):\n')
            for _, row in ipairs(grid) do
                io.write(('    %-8g %s%s\n'):format(
                    row.ridge,
                    row.err and ('%.6f'):format(row.err) or '(no fit)',
                    row.ridge == ridge and '   <- selected' or ''))
            end

            -- The final fit: one pass over every allowed training row at that ridge.
            local X, ys, ws = {}, {}, {}
            BuildRows(d, target, cand.keys, pos, scale, 0, 1.0, X, ys, ws)
            BuildRows(d, extra,  cand.keys, pos, scale, 1, PROTOCOL.LEGO_WEIGHT, X, ys, ws)
            local fit, ferr = MultiFit(X, ys, ridge, ws)

            if not fit then
                Fail('%s: final fit failed (%s)', sel.inst, tostring(ferr))
            else
                local rank_lo, rank_hi = RankRange(d, target)
                local keys = {}
                for i, k in ipairs(cand.keys) do keys[i] = k end
                keys[#keys + 1] = 'is_lego'

                models[#models + 1] = {
                    inst      = sel.inst,
                    candidate = cand.name,
                    scale     = scale.name,
                    status    = STATUS[sel.inst] or 'experimental',
                    keys      = keys,
                    mean      = fit.mean,
                    sd        = fit.sd,
                    coefs     = fit.coefs,
                    intercept = fit.intercept,
                    ridge     = ridge,
                    rank_lo   = rank_lo,
                    rank_hi   = rank_hi,
                    bounds    = FactorBounds(d, target, cand.keys, pos),
                    conc      = ConcentrationThresholds(d, target, pos),
                    n_target  = #target,
                    n_lego    = #extra,
                }

                -- Self-check: the artifact, applied through the shipped predictor, must
                -- reproduce this fit on every training row. Catches a factor-order slip
                -- between what was fitted and what was written down, which is otherwise
                -- invisible - the numbers all look plausible.
                local m = models[#models]
                local worst = 0
                for _, i in ipairs(target) do
                    local factors = {}
                    for _, k in ipairs(cand.keys) do factors[k] = d.feats[i][pos[k]] end
                    local got = DifficultyPredictRank(m, factors)
                    local row = {}
                    for j, k in ipairs(cand.keys) do row[j] = d.feats[i][pos[k]] end
                    row[#row + 1] = 0
                    local want = scale.inv(ApplyFit(row, fit))
                    want = math.max(rank_lo, math.min(rank_hi, want))
                    local diff = math.abs(got - want)
                    if diff > worst then worst = diff end
                end
                io.write(('  ridge %-8g  rank clamp %d..%d  self-check max diff %.2e\n')
                    :format(ridge, rank_lo, rank_hi, worst))
                if worst > 1e-9 then
                    Fail('%s: artifact does not reproduce the fit (%.3e)', sel.inst, worst)
                end
            end
        end
    end
    io.write('\n')
end

if _errors > 0 then
    io.write(('Refusing to write the artifact: %d error(s) above.\n'):format(_errors))
    os.exit(1)
end

----------------------------------------------------------------------
-- Write
----------------------------------------------------------------------

local out = {}
local function W(s) out[#out + 1] = s end

W([[
-- GENERATED FILE - DO NOT EDIT BY HAND.
--
-- Written by dev/calibration/export_production_models.lua from
-- dev/calibration/corpus_scores.csv. Re-run the exporter to change anything here; a hand
-- edit would be silently overwritten and, worse, would not be reproducible from the
-- corpus it claims to describe.
--
-- One frozen model per instrument: the candidate the locked protocol selected, refit once
-- on every row it was allowed to train on. Apply with DifficultyPredictRank in
-- lib/reaper_difficulty_predict.lua - the coefficients are in STANDARDIZED units and mean
-- nothing applied to raw factors by hand.
--
-- Field notes:
--   keys        factor order. The LAST entry is always is_lego, a training-time origin
--               flag; product predictions always pass 0 for it.
--   mean / sd   standardization statistics from the fit, over ALL training rows including
--               the down-weighted lego ones. Only valid paired with these coefs.
--   rank_lo/hi  observed rank range of the rb3_dlc training rows. The final rank is
--               clamped to it; individual factors never are.
--   bounds      per-factor min/max/p90 over the rb3_dlc training rows - the support the
--               suggestion is honest about. A DIFFERENT row set from mean/sd, on purpose:
--               every prediction is made on the RB3 scale.
--   conc        concentration thresholds (p90) for the "difficulty is concentrated in a
--               short passage" note. Measured per instrument because a single cutoff is
--               wrong - bass and drums never mark a solo at all.
--   status      model maturity for the UI badge. Describes validation against noisy
--               official ranks, NOT the probability that a prediction is correct.
]])

W(('\nRB_DIFFICULTY_MODELS_SCHEMA = %d\n'):format(SCHEMA))
W(('RB_DIFFICULTY_MODELS_CSV_FINGERPRINT = %d\n'):format(Fingerprint(csv.header_line)))
W('\nRB_DIFFICULTY_MODEL_ORDER = {\n')
for _, m in ipairs(models) do W(('    %s,\n'):format(Quote(m.inst))) end
W('}\n\nRB_DIFFICULTY_MODELS = {\n')

for _, m in ipairs(models) do
    W(('\n[%s] = {\n'):format(Quote(m.inst)))
    W(('    candidate = %s,\n'):format(Quote(m.candidate)))
    W(('    scale     = %s,\n'):format(Quote(m.scale)))
    W(('    status    = %s,\n'):format(Quote(m.status)))
    W(('    ridge     = %s,\n'):format(Num(m.ridge)))
    W(('    rank_lo   = %s,\n'):format(Num(m.rank_lo)))
    W(('    rank_hi   = %s,\n'):format(Num(m.rank_hi)))
    W(('    intercept = %s,\n'):format(Num(m.intercept)))
    W(('    n_target  = %d,\n'):format(m.n_target))
    W(('    n_lego    = %d,\n'):format(m.n_lego))

    W('    keys = {\n')
    for _, k in ipairs(m.keys) do W(('        %s,\n'):format(Quote(k))) end
    W('    },\n')

    for _, field in ipairs({ 'mean', 'sd', 'coefs' }) do
        W(('    %s = {\n%s\n    },\n'):format(field, NumList(m[field], '        ')))
    end

    W('    bounds = {\n')
    for _, k in ipairs(m.keys) do
        local b = m.bounds[k]
        if b then
            W(('        [%s] = { min = %s, max = %s, p90 = %s },\n')
                :format(Quote(k), Num(b.min), Num(b.max), Num(b.p90)))
        end
    end
    W('    },\n')

    W('    conc = {\n')
    for _, k in ipairs({ 'solo_change_ratio', 'density_ratio' }) do
        if m.conc[k] then W(('        %s = %s,\n'):format(k, Num(m.conc[k]))) end
    end
    W('    },\n')

    W('},\n')
end

W('}\n')

local f = io.open(_out, 'w')
if not f then
    io.write(('Could not write %s\n'):format(_out))
    os.exit(1)
end
f:write(table.concat(out))
f:close()

io.write(('Wrote %s\n'):format(_out))
io.write(('%d models, schema %d.\n'):format(#models, SCHEMA))
io.write('\nRe-running on the same CSV must produce a byte-identical file.\n')
