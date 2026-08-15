-- Unit tests for dev/calibration/stats.lua: Spearman/Pearson, the weighted
-- ridge-regularized MultiFit, and KFoldIndices.
--
-- Pure - plain arrays in, numbers out. The cases here are the properties the
-- calibration analysis relies on, several of which were learned the hard way on
-- the real corpus (near-collinear factors, a differently-scaled group of rows).

local function Approx(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-6)
end

----------------------------------------------------------------------
Test.section('Spearman vs Pearson')

Test.it('Spearman is 1.0 on a monotone but curved relationship, Pearson is not', function()
    -- Exactly why rho is the headline metric: the model only has to ORDER songs
    -- correctly, and a curved score->rank mapping is fine because the fit rescales.
    local x, y = {}, {}
    for i = 1, 10 do x[i] = i; y[i] = i * i end
    Test.expect(Approx(Spearman(x, y), 1.0, 1e-9), 'spearman 1.0')
    local p = Pearson(x, y)
    Test.expect(p < 0.99, 'pearson below 1; got ' .. p)
end)

Test.it('a reversed relationship gives -1.0', function()
    local x, y = {}, {}
    for i = 1, 10 do x[i] = i; y[i] = -i * i end
    Test.expect(Approx(Spearman(x, y), -1.0, 1e-9), 'got ' .. Spearman(x, y))
end)

Test.it('ties are averaged rather than ordered arbitrarily', function()
    -- Official ranks repeat often, so ordinal ranking would bias the result.
    Test.expect(Approx(Spearman({ 1, 2, 2, 3 }, { 10, 20, 20, 30 }), 1.0, 1e-9),
        'tied pairs still perfectly correlated')
end)

Test.it('a constant column has no correlation rather than a divide by zero', function()
    Test.expect(Pearson({ 5, 5, 5, 5 }, { 1, 2, 3, 4 }) == nil, 'nil, not NaN')
end)

----------------------------------------------------------------------
Test.section('MultiFit - exactness and conditioning')

Test.it('recovers an exact linear relationship through standardization', function()
    local X, ys = {}, {}
    for i = 1, 50 do
        local a, b = i * 0.37, (i % 7) * 1.3
        X[i] = { a, b }
        ys[i] = 3.0 * a - 2.0 * b + 5.0
    end
    local fit = MultiFit(X, ys)
    Test.expect(fit ~= nil, 'fit succeeded')
    local worst = 0
    for i = 1, #X do
        worst = math.max(worst, math.abs(ApplyFit(X[i], fit) - ys[i]))
    end
    Test.expect(worst < 1e-3, 'predictions essentially exact; worst ' .. worst)
end)

Test.it('exactly collinear columns still solve, thanks to the ridge term', function()
    -- Not hypothetical: density_peak tracks density_avg and tight_32 is a subset of
    -- tight_16, so the real factor matrix is near-collinear. Without the ridge this
    -- fails outright.
    local X, ys = {}, {}
    for i = 1, 40 do
        local a = i * 0.3
        X[i] = { a, a * 2 }
        ys[i] = 7 * a + 1
    end
    local fit, err = MultiFit(X, ys)
    Test.expect(fit ~= nil, 'solved; got error ' .. tostring(err))
end)

Test.it('a constant feature column does not break the fit', function()
    local X, ys = {}, {}
    for i = 1, 30 do X[i] = { i * 1.0, 5.0 }; ys[i] = 2 * i + 3 end
    Test.expect(MultiFit(X, ys) ~= nil, 'solved')
end)

Test.it('too few rows for the feature count is refused, not fudged', function()
    local X = { { 1, 2, 3 }, { 4, 5, 6 } }
    local fit, err = MultiFit(X, { 1, 2 })
    Test.expect(fit == nil, 'refused')
    Test.expect(type(err) == 'string', 'with a reason')
end)

----------------------------------------------------------------------
Test.section('MultiFit - per-row weights')

Test.it('weight 0 on a group matches omitting that group entirely', function()
    -- The property the Lego down-weighting rests on: weighting is a generalisation
    -- of dropping rows, so weight 0 must be indistinguishable from absence.
    local Xa, ya = {}, {}
    for i = 1, 30 do Xa[i] = { i * 0.5, (i % 4) * 1.1 }; ya[i] = 2 * i + 10 end

    local Xb, yb, wb = {}, {}, {}
    for i = 1, #Xa do Xb[i] = Xa[i]; yb[i] = ya[i]; wb[i] = 1.0 end
    -- Append junk rows that must be ignored completely.
    for k = 1, 15 do
        Xb[#Xb + 1] = { -99 * k, 500 + k }
        yb[#yb + 1] = -10000
        wb[#wb + 1] = 0.0
    end

    local fa = MultiFit(Xa, ya)
    local fb = MultiFit(Xb, yb, nil, wb)
    Test.expect(fa and fb, 'both fits succeeded')
    local worst = 0
    for i = 1, #Xa do
        worst = math.max(worst, math.abs(ApplyFit(Xa[i], fa) - ApplyFit(Xa[i], fb)))
    end
    Test.expect(worst < 1e-3, 'identical predictions; worst diff ' .. worst)
end)

Test.it('a down-weighted contradictory group pulls the fit less than an equal one', function()
    local X, ys = {}, {}
    for i = 1, 40 do X[i] = { i * 1.0 }; ys[i] = 5 * i end
    -- A group on a different scale: same features, ranks shifted down by 200.
    local Xc, yc = {}, {}
    for i = 1, #X do Xc[i] = X[i]; yc[i] = ys[i] end
    for i = 1, 20 do Xc[#Xc + 1] = { i * 1.0 }; yc[#yc + 1] = 5 * i - 200 end

    local function IcAt(weight)
        local w = {}
        for i = 1, #Xc do w[i] = (i <= #X) and 1.0 or weight end
        local f = MultiFit(Xc, yc, nil, w)
        return ApplyFit({ 20 }, f)
    end
    local clean = 5 * 20
    local light = IcAt(0.1)
    local heavy = IcAt(1.0)
    Test.expect(math.abs(light - clean) < math.abs(heavy - clean),
        ('light weight stays closer to the clean group; %.1f vs %.1f (clean %.1f)')
            :format(light, heavy, clean))
end)

Test.it('all-zero weights are refused rather than dividing by zero', function()
    local X, ys, w = {}, {}, {}
    for i = 1, 20 do X[i] = { i * 1.0 }; ys[i] = i; w[i] = 0 end
    local fit, err = MultiFit(X, ys, nil, w)
    Test.expect(fit == nil, 'refused')
    Test.expect(type(err) == 'string', 'with a reason')
end)

----------------------------------------------------------------------
Test.section('KFoldIndices')

Test.it('every row appears exactly once across the folds', function()
    local folds = KFoldIndices(23, 5)
    Test.expect(#folds == 5, 'five folds')
    local seen, total = {}, 0
    for _, f in ipairs(folds) do
        for _, i in ipairs(f) do
            Test.expect(not seen[i], 'row ' .. i .. ' appears once')
            seen[i] = true
            total = total + 1
        end
    end
    Test.expect(total == 23, 'all 23 rows covered; got ' .. total)
end)

Test.it('folds are near-equal in size', function()
    local folds = KFoldIndices(100, 5)
    for _, f in ipairs(folds) do
        Test.expect(#f == 20, 'each fold holds 20; got ' .. #f)
    end
end)

Test.it('k is clamped so tiny inputs cannot produce empty folds', function()
    local folds = KFoldIndices(3, 10)
    Test.expect(#folds <= 3, 'at most one fold per row; got ' .. #folds)
    for _, f in ipairs(folds) do Test.expect(#f >= 1, 'no empty fold') end
end)

----------------------------------------------------------------------
Test.section('TierAccuracy')

Test.it('counts exact and within-one agreement, skipping nil sides', function()
    local ex, w1, n = TierAccuracy({ 0, 1, 2, 3 }, { 0, 2, 2, 6 })
    Test.expect(n == 4, 'four compared')
    Test.expect(Approx(ex, 0.50), 'two exact; got ' .. ex)
    Test.expect(Approx(w1, 0.75), 'three within one; got ' .. w1)
end)

Test.it('a nil on either side is skipped, not counted as a miss', function()
    local _, _, n = TierAccuracy({ 1, nil, 3 }, { 1, 2, nil })
    Test.expect(n == 1, 'only the comparable pair counts; got ' .. n)
end)

----------------------------------------------------------------------
Test.section('TierDistance - the product grading scale')

Test.it('buckets predictions by how many tiers off they are', function()
    --                     0     1     2     3      4  -> miss bucket takes 3 and 4
    local pred = { 3,    3,    3,    3,     3 }
    local act  = { 3,    4,    5,    6,     6 }
    -- distances:    0     1     2     3      3
    local d = TierDistance(pred, act)
    Test.expect(d.n == 5, 'five compared; got ' .. d.n)
    Test.expect(d.perfect == 1, 'one exact; got ' .. d.perfect)
    Test.expect(d.good == 1, 'one off by one; got ' .. d.good)
    Test.expect(d.bad == 1, 'one off by two; got ' .. d.bad)
    Test.expect(d.miss == 2, 'two off by three or more; got ' .. d.miss)
end)

Test.it('usable is perfect plus good, the pair worth having', function()
    local d = TierDistance({ 2, 2, 2, 2 }, { 2, 3, 2, 5 })
    Test.expect(d.usable == d.perfect + d.good, 'usable is the sum')
    Test.expect(d.usable == 3, 'three within one tier; got ' .. d.usable)
end)

Test.it('direction does not matter, only distance', function()
    local over  = TierDistance({ 4 }, { 2 })
    local under = TierDistance({ 2 }, { 4 })
    Test.expect(over.bad == 1 and under.bad == 1, 'both two tiers off')
end)

Test.it('nil sides are skipped rather than counted as misses', function()
    local d = TierDistance({ 1, nil, 3 }, { 1, 2, nil })
    Test.expect(d.n == 1, 'one comparable pair; got ' .. d.n)
    Test.expect(d.perfect == 1 and d.miss == 0, 'and it was exact')
end)

Test.it('an empty comparison reports zeros rather than dividing by zero', function()
    local d = TierDistance({}, {})
    Test.expect(d.n == 0 and d.usable == 0, 'zeros')
end)

----------------------------------------------------------------------
Test.section('ShuffledStratifiedFolds - repeated CV needs a seeded shuffle')

local function Strata(n, per_stratum)
    local s = {}
    for i = 1, n do s[i] = 'tier' .. tostring(math.floor((i - 1) / per_stratum)) end
    return s
end

Test.it('every row lands in exactly one fold', function()
    local folds = ShuffledStratifiedFolds(Strata(100, 10), 5, 42)
    local seen, total = {}, 0
    for _, f in ipairs(folds) do
        for _, i in ipairs(f) do
            Test.expect(not seen[i], 'row ' .. i .. ' appears twice')
            seen[i] = true
            total = total + 1
        end
    end
    Test.expect(total == 100, 'all 100 rows placed; got ' .. total)
end)

Test.it('the same seed gives the same folds, a different seed does not', function()
    local function Sig(folds)
        local parts = {}
        for _, f in ipairs(folds) do parts[#parts + 1] = table.concat(f, '.') end
        return table.concat(parts, '|')
    end
    local st = Strata(60, 6)
    Test.expect(Sig(ShuffledStratifiedFolds(st, 5, 7))
             == Sig(ShuffledStratifiedFolds(st, 5, 7)),
        'same seed must reproduce exactly - a reported interval has to be recheckable')
    Test.expect(Sig(ShuffledStratifiedFolds(st, 5, 7))
             ~= Sig(ShuffledStratifiedFolds(st, 5, 8)),
        'a different seed must actually reshuffle, or repeats measure nothing')
end)

Test.it('a thin stratum is spread across folds rather than dumped in one', function()
    -- The case this exists for: bass Impossible holds 2 songs and guitar Warmup 3, so
    -- an unstratified shuffle can leave whole folds with none of a tier.
    local st = {}
    for i = 1, 50 do st[i] = 'common' end
    st[51], st[52], st[53], st[54], st[55] = 'rare', 'rare', 'rare', 'rare', 'rare'
    local folds = ShuffledStratifiedFolds(st, 5, 3)
    local with_rare = 0
    for _, f in ipairs(folds) do
        for _, i in ipairs(f) do
            if st[i] == 'rare' then with_rare = with_rare + 1 break end
        end
    end
    Test.expect(with_rare == 5,
        ('all 5 folds should hold one of the 5 rare rows; got %d'):format(with_rare))
end)

----------------------------------------------------------------------
Test.section('Wilson bounds - the interval the gate reads')

Test.it('reproduces the guitar figure the protocol reports', function()
    -- 94.87% usable on 158 rows -> a one-sided 95% lower bound just over 91%. Pinned
    -- because this single number is what decides pass or fail.
    local lo = WilsonLower(0.9487, 158, 1.645)
    Test.expect(math.abs(lo - 0.9115) < 0.001,
        ('expected ~0.9115, got %.4f'):format(lo))
end)

Test.it('the bound is tighter with more rows, which is the whole point', function()
    local few  = WilsonLower(0.94, 50,  1.645)
    local many = WilsonLower(0.94, 500, 1.645)
    Test.expect(many > few,
        ('more rows must raise the lower bound; %.4f vs %.4f'):format(many, few))
    Test.expect(few < 0.94 and many < 0.94, 'and both stay below the point estimate')
end)

Test.it('stays inside 0..1 at the extremes rather than overshooting', function()
    -- Where the normal approximation misbehaves, which is why Wilson is used.
    Test.expect(WilsonUpper(1.0, 20) <= 1.0, 'upper bound cannot exceed 1')
    Test.expect(WilsonLower(0.0, 20) >= 0.0, 'lower bound cannot go below 0')
    Test.expect(WilsonLower(1.0, 20) < 1.0, 'a perfect run on 20 rows is not certainty')
end)

Test.it('a zero row count is refused rather than dividing by zero', function()
    local lo, hi = WilsonLower(0.9, 0), WilsonUpper(0.9, 0)
    Test.expect(lo == 0 and hi == 1, 'degenerates to the widest interval')
end)

----------------------------------------------------------------------
Test.section('Quantile and MeanOf')

Test.it('quantile interpolates and leaves the caller array alone', function()
    local v = { 5, 1, 3, 2, 4 }
    Test.expect(Quantile(v, 0.5) == 3, 'median of 1..5 is 3')
    Test.expect(Quantile(v, 0) == 1 and Quantile(v, 1) == 5, 'endpoints')
    Test.expect(v[1] == 5, 'the input must not be sorted in place')
end)

Test.it('empty input gives zero rather than an error', function()
    Test.expect(Quantile({}, 0.5) == 0, 'quantile')
    Test.expect(MeanOf({}) == 0, 'mean')
end)

----------------------------------------------------------------------
Test.section('CandidateResiduals - per-song residuals for the selected model')

-- Builds a synthetic instrument where rank is an exact linear function of one factor,
-- so a correct implementation must predict every song back to within rounding. The
-- property under test is the FOLD-ORDER MAPPING: RunOneRepeat emits predictions fold by
-- fold, and CandidateResiduals has to walk the same folds in the same order to know
-- which song each prediction belongs to. A wrong mapping still produces a plausible
-- looking worst-10 list - just attributed to the wrong songs - which is exactly the
-- failure a report cannot reveal on its own.
local function SyntheticSet(n, outlier_at)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    for i = 1, n do
        local x = i
        d.feats[i]   = { x }
        d.ranks[i]   = 130 + 4 * x
        d.origins[i] = 'rb3_dlc'
        d.names[i]   = ('song%02d'):format(i)
    end
    if outlier_at then
        -- Same factor value, wildly different rank: the one row a good fit must miss.
        d.ranks[outlier_at] = 480
    end
    return d
end

local RESID_REC = { keys = { 'density_peak' }, scale_obj = SCALES[1] }
local RESID_POS = { density_peak = 1 }

Test.it('every target row appears exactly once, mapped to its own rank', function()
    local d = SyntheticSet(60)
    local target = {}
    for i = 1, 60 do target[i] = i end
    local out = CandidateResiduals(d, target, {}, 'guitar', RESID_POS, RESID_REC)
    Test.expect(out and #out == 60, 'got ' .. tostring(out and #out))

    local seen = {}
    for _, x in ipairs(out) do
        Test.expect(not seen[x.name], x.name .. ' appears twice')
        seen[x.name] = true
        -- The name carries the row index, so a scrambled mapping is detectable.
        local idx = tonumber(x.name:match('%d+'))
        Test.expect(x.rank == 130 + 4 * idx,
            ('%s should carry rank %d, got %d'):format(x.name, 130 + 4 * idx, x.rank))
    end
end)

Test.it('an exactly linear relationship is predicted back to its own song', function()
    local d = SyntheticSet(60)
    local target = {}
    for i = 1, 60 do target[i] = i end
    local out = CandidateResiduals(d, target, {}, 'guitar', RESID_POS, RESID_REC)
    local worst = 0
    for _, x in ipairs(out) do
        worst = math.max(worst, math.abs(x.pred - x.rank))
    end
    -- A correct mapping leaves only fit error here. A rotated one would misattribute
    -- predictions across the whole rank range and blow well past this.
    Test.expect(worst < 15, ('worst residual %.1f rank points'):format(worst))
    for _, x in ipairs(out) do
        Test.expect(x.dist == 0, x.name .. ' should be an exact tier hit')
    end
end)

Test.it('the list is ordered worst tier distance first', function()
    local d = SyntheticSet(60, 20)   -- song20 is the planted outlier
    local target = {}
    for i = 1, 60 do target[i] = i end
    local out = CandidateResiduals(d, target, {}, 'guitar', RESID_POS, RESID_REC)
    Test.expect(out[1].name == 'song20',
        'the planted outlier should sort first; got ' .. out[1].name)
    for i = 2, #out do
        Test.expect(out[i - 1].dist >= out[i].dist,
            'tier distance must be non-increasing down the list')
    end
end)

Test.it('a candidate record without factor keys returns nil rather than guessing', function()
    local d = SyntheticSet(60)
    local target = {}
    for i = 1, 60 do target[i] = i end
    Test.expect(CandidateResiduals(d, target, {}, 'guitar', RESID_POS, {}) == nil, 'no keys')
    Test.expect(CandidateResiduals(d, target, {}, 'guitar', RESID_POS, nil) == nil, 'no rec')
end)

----------------------------------------------------------------------
Test.section('ClampRank / RankRange - never report a rank nobody labelled')

Test.it('a prediction outside the observed range is pulled to the edge', function()
    -- The case this exists for: dreampolice, bass, actual rank 299, returned 943 from a
    -- log(rank) fit because density_peak sat at z = +6.34.
    Test.expect(ClampRank(943, 135, 488) == 488, 'above range -> max')
    Test.expect(ClampRank(-74, 135, 488) == 135, 'below range -> min')
    Test.expect(ClampRank(299, 135, 488) == 299, 'inside range is untouched')
end)

Test.it('the edges themselves are inside the range', function()
    Test.expect(ClampRank(135, 135, 488) == 135, 'lower edge')
    Test.expect(ClampRank(488, 135, 488) == 488, 'upper edge')
end)

Test.it('a degenerate single-value range collapses to that value', function()
    Test.expect(ClampRank(500, 200, 200) == 200, 'above')
    Test.expect(ClampRank(1, 200, 200) == 200, 'below')
end)

Test.it('RankRange spans every set it is given and ignores absent parts', function()
    local d = { ranks = { 300, 150, 480, 0, 200 } }
    local lo, hi = RankRange(d, { 1, 2 }, { 3 })
    Test.expect(lo == 150 and hi == 480, ('got %s..%s'):format(lo, hi))
    -- rank 0 means "no such part" and must not become the lower bound.
    local lo2, hi2 = RankRange(d, { 4, 5 })
    Test.expect(lo2 == 200 and hi2 == 200, ('got %s..%s'):format(lo2, hi2))
end)

Test.it('an empty set gives an unbounded range rather than an inverted one', function()
    local lo, hi = RankRange({ ranks = {} }, {})
    Test.expect(lo == 1 and hi == math.huge, 'clamping becomes a no-op, not a corruption')
    Test.expect(ClampRank(943, lo, hi) == 943, 'and nothing is clamped')
end)
