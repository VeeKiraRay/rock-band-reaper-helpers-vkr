-- Statistics for the calibration pilot: correlation, least-squares fitting,
-- and accuracy scoring.
--
-- PURE: no r.*, no S. Plain arrays in, numbers out.
--
-- Status: calibration pilot, dev-only.
--
-- Why Spearman is the headline and not a match percentage: rank correlation
-- answers "does the model ORDER songs correctly", which separates the two
-- failure modes a match percentage conflates. High rho with wrong tiers means
-- the mapping needs rescaling (easy). Low rho means a factor is missing or
-- wrong, and no amount of threshold tuning will help.

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

-- Fractional ranks with ties averaged, which is what Spearman requires - using
-- ordinal position instead would silently bias any dataset with repeated values,
-- and official ranks repeat often.
local function RankTransform(xs)
    local n     = #xs
    local order = {}
    for i = 1, n do order[i] = i end
    table.sort(order, function(a, b) return xs[a] < xs[b] end)

    local ranks = {}
    local i = 1
    while i <= n do
        local j = i
        while j < n and xs[order[j + 1]] == xs[order[i]] do j = j + 1 end
        local avg = (i + j) / 2
        for k = i, j do ranks[order[k]] = avg end
        i = j + 1
    end
    return ranks
end

local function Mean(xs)
    if #xs == 0 then return 0 end
    local s = 0
    for _, v in ipairs(xs) do s = s + v end
    return s / #xs
end

----------------------------------------------------------------------
-- Correlation
----------------------------------------------------------------------

function Pearson(xs, ys)
    local n = #xs
    if n < 2 or n ~= #ys then return nil end
    local mx, my = Mean(xs), Mean(ys)
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, n do
        local dx, dy = xs[i] - mx, ys[i] - my
        sxy = sxy + dx * dy
        sxx = sxx + dx * dx
        syy = syy + dy * dy
    end
    if sxx <= 0 or syy <= 0 then return nil end  -- a constant column has no correlation
    return sxy / math.sqrt(sxx * syy)
end

function Spearman(xs, ys)
    if #xs < 2 or #xs ~= #ys then return nil end
    return Pearson(RankTransform(xs), RankTransform(ys))
end

----------------------------------------------------------------------
-- Least squares
----------------------------------------------------------------------

-- Solve A*x = b in place by Gaussian elimination with partial pivoting.
-- A is an n x n array of rows. Returns the solution array, or nil if singular.
local function SolveLinear(A, b, n)
    for col = 1, n do
        local piv, pmax = col, math.abs(A[col][col])
        for row = col + 1, n do
            local v = math.abs(A[row][col])
            if v > pmax then piv, pmax = row, v end
        end
        if pmax < 1e-12 then return nil end
        if piv ~= col then
            A[col], A[piv] = A[piv], A[col]
            b[col], b[piv] = b[piv], b[col]
        end
        local d = A[col][col]
        for row = col + 1, n do
            local f = A[row][col] / d
            if f ~= 0 then
                for k = col, n do A[row][k] = A[row][k] - f * A[col][k] end
                b[row] = b[row] - f * b[col]
            end
        end
    end
    local x = {}
    for row = n, 1, -1 do
        local s = b[row]
        for k = row + 1, n do s = s - A[row][k] * x[k] end
        x[row] = s / A[row][row]
    end
    return x
end

-- Multiple linear regression of ys on the feature vectors in X.
--
-- X: array of rows, each an array of m feature values (same m for every row).
-- Returns a fit table { coefs, intercept, mean, sd, ridge } for ApplyFit, or
-- nil, err.
--
-- Fitting over the factor VECTOR rather than a hand-weighted single score is
-- deliberate: the weights are exactly what calibration is supposed to discover,
-- so guessing them first would be measuring the guess.
--
-- Two numerical safeguards, both of which matter here rather than being generic
-- caution. The difficulty factors are near-collinear by construction - peak
-- density tracks average density, and tight_32 is a subset of tight_16 - and raw
-- normal equations on near-collinear columns produce coefficients that blow up
-- and flip sign, which would make the per-factor weights unreadable even when
-- the predictions look fine:
--
--   * Standardize each column to zero mean / unit sd before solving. This
--     conditions the matrix properly and makes the returned coefficients
--     directly comparable to each other as effect sizes.
--   * Add a small ridge term to the diagonal. Negligible when the columns are
--     independent, and it keeps an exactly-collinear pair (or a constant column)
--     solvable instead of failing outright.
--
-- Coefficients are returned in STANDARDIZED units, so ApplyFit must be used
-- rather than applying them by hand to raw features.
--
-- ws (optional): per-row weights, defaulting to 1. Used to let a
-- differently-calibrated group of rows contribute to the fit without steering it:
-- the Lego-era songs sit on a rank scale about 45 points below RB3 DLC's, and the
-- goal is to match RB3. Weight 0 for a group is equivalent to omitting it.
function MultiFit(X, ys, ridge, ws)
    local n = #X
    if n == 0 then return nil, 'no rows' end
    local m = #X[1]
    if n < m + 1 then return nil, 'not enough rows for ' .. m .. ' features' end
    ridge = ridge or 1e-6

    -- Total weight replaces n throughout, so every mean/sd/ridge term stays on the
    -- same scale whether or not weights are in play.
    local W = 0
    if ws then
        for i = 1, n do W = W + ws[i] end
        if W <= 0 then return nil, 'all weights are zero' end
    else
        W = n
    end
    local function Wt(i) return ws and ws[i] or 1 end

    -- Weighted column means and standard deviations.
    local mean, sd = {}, {}
    for j = 1, m do
        local s = 0
        for i = 1, n do s = s + Wt(i) * X[i][j] end
        mean[j] = s / W
        local v = 0
        for i = 1, n do
            local d = X[i][j] - mean[j]
            v = v + Wt(i) * d * d
        end
        sd[j] = math.sqrt(v / W)
        -- A constant column carries no information; sd 1 makes it a harmless zero
        -- after centering rather than a division by zero.
        if sd[j] < 1e-12 then sd[j] = 1 end
    end

    -- Normal equations over the standardized design matrix, intercept first.
    local dim = m + 1
    local A, b = {}, {}
    for i = 1, dim do
        A[i] = {}
        for j = 1, dim do A[i][j] = 0 end
        b[i] = 0
    end
    for row = 1, n do
        local w  = Wt(row)
        local xr = { 1 }
        for j = 1, m do xr[j + 1] = (X[row][j] - mean[j]) / sd[j] end
        for i = 1, dim do
            for j = 1, dim do A[i][j] = A[i][j] + w * xr[i] * xr[j] end
            b[i] = b[i] + w * xr[i] * ys[row]
        end
    end
    -- Ridge on the feature diagonal only, never on the intercept.
    for i = 2, dim do A[i][i] = A[i][i] + ridge * W end

    local sol = SolveLinear(A, b, dim)
    if not sol then return nil, 'singular even with ridge' end

    local coefs = {}
    for j = 1, m do coefs[j] = sol[j + 1] end
    return { coefs = coefs, intercept = sol[1], mean = mean, sd = sd, ridge = ridge }
end

-- Predict from raw (unstandardized) features using a fit from MultiFit.
function ApplyFit(features, fit)
    local y = fit.intercept
    for j = 1, #fit.coefs do
        y = y + fit.coefs[j] * ((features[j] - fit.mean[j]) / fit.sd[j])
    end
    return y
end

----------------------------------------------------------------------
-- Error and accuracy
----------------------------------------------------------------------

function MeanAbsError(pred, actual)
    local n = #pred
    if n == 0 then return 0 end
    local s = 0
    for i = 1, n do s = s + math.abs(pred[i] - actual[i]) end
    return s / n
end

-- Exact and within-one-tier agreement between two tier arrays.
-- Returns exact_fraction, within1_fraction, n_compared. Entries where either
-- side is nil (no part) are skipped rather than counted as misses.
function TierAccuracy(pred_tiers, actual_tiers)
    local exact, within1, n = 0, 0, 0
    for i = 1, #pred_tiers do
        local p, a = pred_tiers[i], actual_tiers[i]
        if p ~= nil and a ~= nil then
            n = n + 1
            local d = math.abs(p - a)
            if d == 0 then exact = exact + 1 end
            if d <= 1 then within1 = within1 + 1 end
        end
    end
    if n == 0 then return 0, 0, 0 end
    return exact / n, within1 / n, n
end

-- Distribution of how far off each prediction is, in tiers.
--
-- This is the metric that matters for the actual product, graded the way a rhythm
-- game grades a note: exact is perfect, one tier off is still a useful suggestion,
-- two is bad, three or more is a total miss. Harmonix set these ranks with
-- playtesters, not a formula, and two charts with identical density can genuinely
-- differ in how hard they feel - so exact agreement was never the realistic target.
-- What matters is that the suggestion lands close enough to be a good starting point.
--
-- Returns { perfect, good, bad, miss, n, usable } where usable = perfect + good.
-- Entries where either side is nil (no part) are skipped.
function TierDistance(pred_tiers, actual_tiers)
    local out = { perfect = 0, good = 0, bad = 0, miss = 0, n = 0, usable = 0 }
    for i = 1, #pred_tiers do
        local p, a = pred_tiers[i], actual_tiers[i]
        if p ~= nil and a ~= nil then
            out.n = out.n + 1
            local d = math.abs(p - a)
            if     d == 0 then out.perfect = out.perfect + 1
            elseif d == 1 then out.good    = out.good + 1
            elseif d == 2 then out.bad     = out.bad + 1
            else               out.miss    = out.miss + 1 end
        end
    end
    out.usable = out.perfect + out.good
    return out
end

-- Two-way split by a predicate, for the origin validation: fit on one subset,
-- measure the other. Returns in_set, out_set (arrays of indices).
function PartitionIndices(items, pred)
    local yes, no = {}, {}
    for i, it in ipairs(items) do
        if pred(it) then yes[#yes + 1] = i else no[#no + 1] = i end
    end
    return yes, no
end

----------------------------------------------------------------------
-- Cross-validation
----------------------------------------------------------------------

-- Fold assignment for k-fold CV: returns folds, an array of k index arrays.
--
-- Deterministic (round-robin by position) rather than random, for two reasons:
-- runs stay comparable to each other, and a positional split cannot accidentally
-- concentrate the hard songs in one fold the way a rank-ordered split would.
--
-- CV rather than a single holdout is not fussiness here: one 36-row test split of
-- this corpus produced a guitar rho of 0.62 against a 5-fold value of 0.79. At this
-- sample size a single split is mostly noise, and every row gets tested exactly once
-- under CV.
function KFoldIndices(n, k)
    k = math.max(2, math.min(k or 5, n))
    local folds = {}
    for f = 1, k do folds[f] = {} end
    for i = 1, n do
        local f = ((i - 1) % k) + 1
        folds[f][#folds[f] + 1] = i
    end
    return folds
end

-- Shuffled, stratified fold assignment for REPEATED cross-validation.
--
-- KFoldIndices above is deliberately deterministic, which is right for a single
-- comparable run and useless for repeated CV: repeating a deterministic split gives
-- the same answer every time and so produces no spread to measure.
--
--   strata  parallel array of stratum keys (any comparable value; nil allowed).
--           Rows are dealt out within each stratum, so every fold gets roughly the
--           same tier mix - which matters here because whole tiers hold 2-3 songs
--           and a random split can empty one.
--   seed    RECORDED so a reported interval is reproducible. Callers must pass one
--           rather than relying on os.time(), or the numbers cannot be rechecked.
--
-- Returns folds, an array of k index arrays.
function ShuffledStratifiedFolds(strata, k, seed)
    local n = #strata
    k = math.max(2, math.min(k or 5, n))
    math.randomseed(seed or 1)

    -- Group row indices by stratum, keeping a stable key order so the shuffle is a
    -- function of the seed alone and not of table iteration order (which Lua does
    -- not guarantee between runs).
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
    -- Deal each stratum round-robin from a rotating start, so small strata do not all
    -- land in fold 1.
    local start = 0
    for _, key in ipairs(keys) do
        local g = by[key]
        -- Fisher-Yates, so the shuffle is uniform rather than sort-comparator noise.
        for i = #g, 2, -1 do
            local j = math.random(i)
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

-- Shuffled fold assignment that keeps whole GROUPS together while still balancing
-- strata - "stratified group k-fold".
--
-- WHY. ShuffledStratifiedFolds above deals individual rows, so two songs from the same
-- DLC pack can land one in training and one in validation. Songs in a pack share an
-- authoring team, an era and often a difficulty intent, so such a split lets the model
-- see a near-sibling of the row it is being graded on. Whatever accuracy that buys is
-- not accuracy on an unseen song, and the corpus grows one pack at a time, so it is the
-- realistic unit of "new data" as well.
--
-- The two goals genuinely conflict - whole packs cannot always be dealt so that every
-- tier stays even - so this is a greedy balance, not an exact one:
--
--   1. Group rows by group key, and note each group's per-stratum counts.
--   2. Order groups largest first (a big group placed late has nowhere good to go),
--      breaking ties with a seeded random key so repeats differ.
--   3. Place each group in whichever fold leaves the per-stratum counts most even,
--      measured as the summed spread of each stratum's counts across folds.
--
--   strata  parallel array of stratum keys, as above.
--   groups  parallel array of group keys. nil or '' means "no group", and such a row
--           becomes its own singleton group rather than joining one big nil bucket -
--           silently merging every unlabelled row would be the opposite of the intent.
--   seed    RECORDED, same contract as ShuffledStratifiedFolds.
--
-- WHAT IT CANNOT DO. A stratum spread over fewer than k groups cannot reach k folds -
-- bass Impossible is 3 songs in 3 packs, vocals Warmup is 2 songs in 2 packs. Grouping
-- therefore makes the sparsest tiers' per-tier rates NOISIER, not cleaner, and any
-- per-tier reading of a grouped run has to say so. Callers can see this coming from
-- the returned second value.
--
-- Returns folds, plus a diagnostics table { n_groups, largest_group, thin_strata },
-- where thin_strata maps stratum -> group count for any stratum held by fewer than k
-- groups.
function StratifiedGroupFolds(strata, groups, k, seed)
    local n = #strata
    k = math.max(2, math.min(k or 5, n))
    math.randomseed(seed or 1)

    -- Stable key order first, so the shuffle is a function of the seed alone and not of
    -- Lua's table iteration order.
    local by, keys = {}, {}
    for i = 1, n do
        local g = groups and groups[i]
        if g == nil or g == '' then g = '\0row' .. i end
        g = tostring(g)
        if not by[g] then by[g] = { rows = {}, counts = {} }; keys[#keys + 1] = g end
        local rec = by[g]
        rec.rows[#rec.rows + 1] = i
        local s = tostring(strata[i])
        rec.counts[s] = (rec.counts[s] or 0) + 1
    end
    table.sort(keys)

    -- Every stratum present, in a fixed order, so the cost below is deterministic.
    local slist, seen = {}, {}
    for i = 1, n do
        local s = tostring(strata[i])
        if not seen[s] then seen[s] = true; slist[#slist + 1] = s end
    end
    table.sort(slist)

    -- Draw tie-break keys in sorted-key order, then sort largest-first. The comparator
    -- is a total order (size, then key, then name), so table.sort's instability cannot
    -- make the result depend on anything but the seed.
    local tie = {}
    for _, g in ipairs(keys) do tie[g] = math.random() end
    local order = {}
    for i, g in ipairs(keys) do order[i] = g end
    table.sort(order, function(a, b)
        local na, nb = #by[a].rows, #by[b].rows
        if na ~= nb then return na > nb end
        if tie[a] ~= tie[b] then return tie[a] < tie[b] end
        return a < b
    end)

    local folds, fill = {}, {}
    local per = {}                       -- per[stratum][fold] = count so far
    for f = 1, k do folds[f] = {}; fill[f] = 0 end
    for _, s in ipairs(slist) do
        per[s] = {}
        for f = 1, k do per[s][f] = 0 end
    end

    for _, g in ipairs(order) do
        local rec = by[g]
        local best, best_cost, best_fill
        for f = 1, k do
            -- Summed spread of each stratum's per-fold counts, if this group went here.
            -- Standard deviation rather than range: range ignores everything between the
            -- two extremes, and with 7 tiers most of the imbalance lives there.
            local cost = 0
            for _, s in ipairs(slist) do
                local add, row = rec.counts[s] or 0, per[s]
                local mean = 0
                for x = 1, k do mean = mean + row[x] end
                mean = (mean + add) / k
                local var = 0
                for x = 1, k do
                    local c = row[x] + ((x == f) and add or 0)
                    var = var + (c - mean) * (c - mean)
                end
                cost = cost + math.sqrt(var / k)
            end
            -- Ties on the stratum cost are common (most groups are one song), so break
            -- them on total fold size to keep the folds themselves near-equal.
            if not best or cost < best_cost - 1e-12
               or (cost < best_cost + 1e-12 and fill[f] < best_fill) then
                best, best_cost, best_fill = f, cost, fill[f]
            end
        end
        for _, i in ipairs(rec.rows) do
            folds[best][#folds[best] + 1] = i
        end
        fill[best] = fill[best] + #rec.rows
        for _, s in ipairs(slist) do
            per[s][best] = per[s][best] + (rec.counts[s] or 0)
        end
    end

    -- Diagnostics the caller is expected to report rather than discard.
    local groups_per_stratum = {}
    for _, g in ipairs(keys) do
        for s in pairs(by[g].counts) do
            groups_per_stratum[s] = (groups_per_stratum[s] or 0) + 1
        end
    end
    local thin = {}
    for _, s in ipairs(slist) do
        if groups_per_stratum[s] < k then thin[s] = groups_per_stratum[s] end
    end
    local largest = 0
    for _, g in ipairs(keys) do
        if #by[g].rows > largest then largest = #by[g].rows end
    end
    return folds, { n_groups = #keys, largest_group = largest, thin_strata = thin }
end

-- One-sided Wilson score bounds for a proportion.
--
-- WHY THESE AND NOT THE SPREAD ACROSS CV REPEATS. Repeat-to-repeat spread measures
-- how much the answer moves when the SPLIT changes - split noise. It says nothing
-- about how much the answer would move on a different sample of songs, and it is far
-- smaller, so using it as the uncertainty would badly overstate confidence. The
-- binomial bound below is about the sample size, which is the dominant term here:
-- at 94% usable on 158 rows the lower bound is near 90%, while repeat spread is
-- typically under a point.
--
-- Wilson rather than the normal approximation because p is close to 1, where the
-- normal interval misbehaves (it can exceed 1, and it is anticonservative).
--
--   p  observed proportion, 0..1
--   n  number of observations
--   z  1.645 for a one-sided 95% bound (the default), 1.96 for 97.5%
local function WilsonBounds(p, n, z)
    if not n or n <= 0 then return 0, 1 end
    z = z or 1.645
    local z2     = z * z
    local denom  = 1 + z2 / n
    local centre = (p + z2 / (2 * n)) / denom
    local half   = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / denom
    local lo, hi = centre - half, centre + half
    if lo < 0 then lo = 0 end
    if hi > 1 then hi = 1 end
    return lo, hi
end

function WilsonLower(p, n, z) local lo = WilsonBounds(p, n, z) return lo end
function WilsonUpper(p, n, z) local _, hi = WilsonBounds(p, n, z) return hi end

-- Linear-interpolated quantile of an UNSORTED array (sorted internally, so the
-- caller's array is left alone). Used to summarise the spread across CV repeats.
function Quantile(values, q)
    local t = {}
    for i, v in ipairs(values) do t[i] = v end
    if #t == 0 then return 0 end
    table.sort(t)
    if #t == 1 then return t[1] end
    local idx = q * (#t - 1) + 1
    local lo, hi = math.floor(idx), math.ceil(idx)
    if lo == hi then return t[lo] end
    return t[lo] + (t[hi] - t[lo]) * (idx - lo)
end

function MeanOf(values)
    if #values == 0 then return 0 end
    local s = 0
    for _, v in ipairs(values) do s = s + v end
    return s / #values
end

-- Sample standard deviation (n-1). Zero for fewer than two values rather than nil, so
-- a caller formatting a report never has to branch: with one repeat there is no spread
-- to report, and 0 says that as honestly as nil would.
function SampleSd(values)
    local n = #values
    if n < 2 then return 0 end
    local m, v = MeanOf(values), 0
    for _, x in ipairs(values) do v = v + (x - m) * (x - m) end
    return math.sqrt(v / (n - 1))
end
