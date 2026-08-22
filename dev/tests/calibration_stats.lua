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
Test.section('StratifiedGroupFolds - whole packs, or the score is leakage')

local function FoldSig(folds)
    local parts = {}
    for _, f in ipairs(folds) do
        local t = {}
        for _, i in ipairs(f) do t[#t + 1] = i end
        table.sort(t)
        parts[#parts + 1] = table.concat(t, '.')
    end
    return table.concat(parts, '|')
end

-- 60 rows, 20 packs of 3, 4 tiers dealt across them.
local function GroupedFixture(n, per_pack, ntier)
    local st, gp = {}, {}
    for i = 1, n do
        st[i] = 'tier' .. tostring(i % ntier)
        gp[i] = 'pack' .. tostring(math.floor((i - 1) / per_pack))
    end
    return st, gp
end

Test.it('no group is ever split across two folds', function()
    -- This is the whole point of the function: a split group is exactly the leakage the
    -- row-level scheme has, and it must be structurally impossible here.
    local st, gp = GroupedFixture(60, 3, 4)
    local folds = StratifiedGroupFolds(st, gp, 5, 11)
    local fold_of = {}
    for fi, f in ipairs(folds) do
        for _, i in ipairs(f) do
            Test.expect(fold_of[gp[i]] == nil or fold_of[gp[i]] == fi,
                ('%s spans folds %s and %d'):format(gp[i], tostring(fold_of[gp[i]]), fi))
            fold_of[gp[i]] = fi
        end
    end
end)

Test.it('every row lands in exactly one fold', function()
    local st, gp = GroupedFixture(60, 3, 4)
    local folds = StratifiedGroupFolds(st, gp, 5, 11)
    local seen, total = {}, 0
    for _, f in ipairs(folds) do
        for _, i in ipairs(f) do
            Test.expect(not seen[i], 'row ' .. i .. ' appears twice')
            seen[i] = true
            total = total + 1
        end
    end
    Test.expect(total == 60, 'all 60 rows placed; got ' .. total)
end)

Test.it('the same seed reproduces, a different seed reshuffles', function()
    local st, gp = GroupedFixture(60, 3, 4)
    Test.expect(FoldSig(StratifiedGroupFolds(st, gp, 5, 7))
             == FoldSig(StratifiedGroupFolds(st, gp, 5, 7)),
        'same seed must reproduce - a reported delta has to be recheckable')
    Test.expect(FoldSig(StratifiedGroupFolds(st, gp, 5, 7))
             ~= FoldSig(StratifiedGroupFolds(st, gp, 5, 8)),
        'a different seed must move whole packs, or the repeats measure nothing')
end)

Test.it('folds stay near-equal in size despite grouping', function()
    -- Grouping is allowed to cost some balance; it is not allowed to produce a fold
    -- holding half the corpus, which would make the per-fold rate meaningless.
    local st, gp = GroupedFixture(60, 3, 4)
    local folds = StratifiedGroupFolds(st, gp, 5, 11)
    local lo, hi = math.huge, 0
    for _, f in ipairs(folds) do
        lo = math.min(lo, #f)
        hi = math.max(hi, #f)
    end
    Test.expect(hi - lo <= 3, ('fold sizes spread %d..%d, too uneven'):format(lo, hi))
end)

Test.it('an unlabelled row becomes its own group, not one shared bucket', function()
    -- Merging every pack-less row would be the opposite of the intent: it would force
    -- rows with nothing in common to share a fold and call that leakage-free.
    local st, gp = {}, {}
    for i = 1, 30 do st[i] = 'tier' .. tostring(i % 3); gp[i] = '' end
    local folds = StratifiedGroupFolds(st, gp, 5, 5)
    local sizes = 0
    for _, f in ipairs(folds) do
        Test.expect(#f > 0, 'a fold came out empty with 30 singleton groups')
        sizes = sizes + #f
    end
    Test.expect(sizes == 30, 'all rows placed; got ' .. sizes)
end)

Test.it('reports thin strata rather than hiding them', function()
    -- bass Impossible is 3 songs in 3 packs against 5 folds. Grouping CANNOT reach every
    -- fold there, and the caller has to be told so it can say so in the report.
    local st, gp = {}, {}
    for i = 1, 50 do st[i] = 'common'; gp[i] = 'pack' .. math.floor((i - 1) / 5) end
    for i = 51, 53 do st[i] = 'rare'; gp[i] = 'rare_pack' .. i end
    local _, diag = StratifiedGroupFolds(st, gp, 5, 3)
    Test.expect(diag.thin_strata['rare'] == 3,
        'rare sits in 3 packs and must be flagged as thin')
    Test.expect(diag.thin_strata['common'] == nil,
        'common sits in 10 packs and must not be flagged')
    Test.expect(diag.n_groups == 13, 'expected 13 groups, got ' .. tostring(diag.n_groups))
    Test.expect(diag.largest_group == 5, 'largest pack is 5 rows')
end)

Test.it('PackLeakageRate is zero for grouped folds and positive for row-level', function()
    -- The number the report quotes. If this ever reads non-zero on grouped folds, the
    -- grouping is broken and every delta beside it is meaningless.
    local st, gp = GroupedFixture(60, 3, 4)
    local grouped = StratifiedGroupFolds(st, gp, 5, 11)
    local rowlevel = ShuffledStratifiedFolds(st, 5, 11)
    Test.expect(PackLeakageRate(grouped, gp) == 0,
        'grouped folds must leak nothing by construction')
    Test.expect(PackLeakageRate(rowlevel, gp) > 0.5,
        'with 20 packs of 3 over 5 folds, most rows should have a sibling in training')
end)

----------------------------------------------------------------------
Test.section('PackBootstrap - the interval Wilson cannot produce')

-- Residual rows as CandidateResiduals emits them: pack, pred, rank, and the two tiers.
local function BootRows(spec)
    local out = {}
    for _, s in ipairs(spec) do
        for i = 1, s.n do
            out[#out + 1] = {
                name = s.pack .. '_' .. i, pack = s.pack,
                rank = s.rank + i, pred = s.rank + i + (s.err or 0),
                tier_act = s.tier, tier_pred = s.tier + (s.off or 0),
                dist = math.abs(s.off or 0),
            }
        end
    end
    return out
end

Test.it('the point estimate matches a hand count', function()
    -- 8 rows, 2 of them two tiers out, so pooled usable is 6/8.
    local rows = BootRows({
        { pack = 'a', n = 3, rank = 100, tier = 3, off = 0 },
        { pack = 'b', n = 3, rank = 200, tier = 4, off = 1 },
        { pack = 'c', n = 2, rank = 300, tier = 5, off = 2 },
    })
    local b = PackBootstrap(rows)
    Test.expect(b ~= nil, 'bootstrap returned nil')
    Test.expect(math.abs(b.stat.pooled.point - 6 / 8) < 1e-9,
        'pooled point should be 0.75, got ' .. tostring(b.stat.pooled.point))
    Test.expect(b.n == 8 and b.n_packs == 3,
        ('expected 8 rows in 3 packs, got %d in %d'):format(b.n, b.n_packs))
end)

Test.it('is reproducible - a quoted bound has to be recheckable', function()
    local rows = BootRows({
        { pack = 'a', n = 4, rank = 100, tier = 2, off = 0 },
        { pack = 'b', n = 4, rank = 200, tier = 3, off = 1 },
        { pack = 'c', n = 4, rank = 300, tier = 4, off = 0 },
        { pack = 'd', n = 4, rank = 400, tier = 5, off = 2 },
    })
    local a, b = PackBootstrap(rows), PackBootstrap(rows)
    Test.expect(a.stat.pooled.lo == b.stat.pooled.lo
            and a.stat.macro.lo == b.stat.macro.lo,
        'two runs on the same rows must give the same bounds')
end)

Test.it('the lower bound sits below the point estimate and inside [0,1]', function()
    local rows = BootRows({
        { pack = 'a', n = 6, rank = 100, tier = 2, off = 0 },
        { pack = 'b', n = 6, rank = 200, tier = 3, off = 0 },
        { pack = 'c', n = 6, rank = 300, tier = 4, off = 1 },
        { pack = 'd', n = 6, rank = 400, tier = 5, off = 2 },
    })
    local b = PackBootstrap(rows)
    for _, k in ipairs({ 'pooled', 'macro' }) do
        local s = b.stat[k]
        Test.expect(s.lo <= s.point + 1e-9,
            k .. ' lower bound must not exceed the point estimate')
        Test.expect(s.lo >= 0 and s.p95 <= 1,
            k .. ' bounds must stay inside [0,1]')
    end
end)

Test.it('clustering widens the interval - the whole reason for resampling packs', function()
    -- Same 40 rows and the same pooled rate twice. In `clustered` a whole pack of 20 is
    -- wrong together, so a resample either draws it or does not and the rate swings; in
    -- `spread` the same 20 failures sit in 20 separate packs and average out. If the
    -- bootstrap did not respect packs these two would come out the same.
    local clustered = BootRows({
        { pack = 'good', n = 20, rank = 100, tier = 3, off = 0 },
        { pack = 'bad',  n = 20, rank = 200, tier = 3, off = 2 },
    })
    local spec = {}
    for i = 1, 20 do
        spec[#spec + 1] = { pack = 'g' .. i, n = 1, rank = 100 + i, tier = 3, off = 0 }
        spec[#spec + 1] = { pack = 'b' .. i, n = 1, rank = 200 + i, tier = 3, off = 2 }
    end
    local spread = BootRows(spec)
    local bc, bs = PackBootstrap(clustered), PackBootstrap(spread)
    Test.expect(math.abs(bc.stat.pooled.point - bs.stat.pooled.point) < 1e-9,
        'the two fixtures must share a point estimate, or the comparison means nothing')
    Test.expect(bc.stat.pooled.sd > bs.stat.pooled.sd * 2,
        ('clustered sd %.4f should dwarf spread sd %.4f')
            :format(bc.stat.pooled.sd, bs.stat.pooled.sd))
end)

Test.it('reports the design effect against the binomial sd', function()
    local clustered = BootRows({
        { pack = 'good', n = 20, rank = 100, tier = 3, off = 0 },
        { pack = 'bad',  n = 20, rank = 200, tier = 3, off = 2 },
    })
    local b = PackBootstrap(clustered)
    Test.expect(b.stat.pooled.design and b.stat.pooled.design > 1,
        'two packs of 20 must show a design effect above 1')
    Test.expect(b.stat.pooled.n_eff and b.stat.pooled.n_eff < b.n,
        'effective n must fall below the row count when rows are clustered')
end)

Test.it('a row without a pack is its own group, not one shared bucket', function()
    -- Pooling every unlabelled row would invent clustering that is not there and
    -- silently widen the interval.
    local rows = BootRows({ { pack = 'x', n = 12, rank = 100, tier = 3, off = 0 } })
    for _, x in ipairs(rows) do x.pack = nil end
    local b = PackBootstrap(rows)
    Test.expect(b.n_packs == 12, 'expected 12 singleton groups, got ' .. tostring(b.n_packs))
end)

Test.it('counts resamples that lose a tier instead of hiding them', function()
    -- One tier held by a single pack: some resamples miss it, and macro then averages
    -- over fewer bands - a different estimand, so the rate has to be visible.
    local rows = BootRows({
        { pack = 'a', n = 20, rank = 100, tier = 2, off = 0 },
        { pack = 'b', n = 20, rank = 200, tier = 3, off = 0 },
        { pack = 'rare', n = 1, rank = 400, tier = 6, off = 0 },
    })
    local b = PackBootstrap(rows)
    Test.expect(b.macro_short_frac > 0.1,
        'a 1-pack tier out of 3 packs should vanish often; got '
        .. tostring(b.macro_short_frac))
end)

Test.it('returns nil rather than dividing by nothing', function()
    Test.expect(PackBootstrap({}) == nil, 'empty input')
    Test.expect(PackBootstrap(nil) == nil, 'nil input')
end)

----------------------------------------------------------------------
Test.section('SampleSd')

Test.it('matches a hand-computed n-1 standard deviation', function()
    local sd = SampleSd({ 2, 4, 4, 4, 5, 5, 7, 9 })
    Test.expect(math.abs(sd - 2.13809) < 1e-4, 'got ' .. tostring(sd))
end)

Test.it('returns 0 rather than nil below two values', function()
    Test.expect(SampleSd({}) == 0, 'empty')
    Test.expect(SampleSd({ 3 }) == 0, 'single value has no spread')
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

Test.section('Fnv1a64 - the one hash both the fingerprints and the partition use')

Test.it('matches the published FNV-1a 64 test vectors', function()
    -- These are the canonical vectors. They are asserted rather than assumed because
    -- everything downstream - the report's provenance header, the reserved partition -
    -- is only meaningful if this function is the standard one and stays it.
    Test.expect(Fnv1a64Hex('') == 'cbf29ce484222325', 'empty string')
    Test.expect(Fnv1a64Hex('a') == 'af63dc4c8601ec8c', 'single byte')
    Test.expect(Fnv1a64Hex('hello world') == '779a65e7023cd2e7', 'multi-byte')
end)

Test.it('crosses the 4096-byte block boundary correctly', function()
    -- Fnv1a64 reads in 4096-value blocks for speed, so the block seam is the one place
    -- an off-by-one would hide: short strings would all still pass.
    local a = string.rep('x', 4095) .. 'y'
    local b = string.rep('x', 4096) .. 'y'
    Test.expect(Fnv1a64Hex(a) ~= Fnv1a64Hex(b), 'a byte either side of the seam differs')
    -- Same content, so the seam must not change the answer: build 5000 bytes two ways.
    local long = string.rep('abcde', 1000)
    Test.expect(#long == 5000 and Fnv1a64Hex(long) == Fnv1a64Hex(long .. ''), 'stable past one block')
end)

Test.section('PackIsReserved - the test partition, committed before the data exists')

Test.it('a pack already in the corpus is never reserved', function()
    -- Rule 1, and the one that actually matters: a walked pack has informed factor
    -- design and residual inspection, so it can never be held-out evidence again. This
    -- must beat the hash, whatever the hash says.
    local seen = {}
    local hashed_reserved
    for i = 1, 500 do
        local p = 'pack' .. i
        if PackIsReserved(p, {}) then hashed_reserved = p break end
    end
    Test.expect(hashed_reserved ~= nil, 'found a pack the hash reserves')
    seen[hashed_reserved] = true
    Test.expect(PackIsReserved(hashed_reserved, seen) == false,
        'a seen pack stays development even though its hash says reserved')
end)

Test.it('is deterministic and depends only on the pack id', function()
    Test.expect(PackIsReserved('somepack', {}) == PackIsReserved('somepack', {}),
        'same answer every call - a partition that moved would be no partition')
end)

Test.it('reserves the declared share', function()
    local n, res = 2000, 0
    for i = 1, n do
        if PackIsReserved('synthetic_pack_' .. i, {}) then res = res + 1 end
    end
    local pct = res / n * 100
    -- Tolerance is one-sided at 100: an exact share is only expected in the degenerate
    -- case. Below 100 this asserts the hash is not lopsided; at 100 it asserts every
    -- unwalked pack is held out, which is the current epoch's whole policy.
    if PARTITION.RESERVED_PCT >= 100 then
        Test.expect(res == n,
            ('%d of %d reserved, expected all of them'):format(res, n))
    else
        Test.expect(math.abs(pct - PARTITION.RESERVED_PCT) < 5,
            ('%.1f%% reserved, declared %d%%'):format(pct, PARTITION.RESERVED_PCT))
    end
end)

Test.it('the walked-already rule still beats a 100% reserve', function()
    -- At RESERVED_PCT = 100 the hash reserves everything, so rule 1 is the only thing
    -- keeping the 330 development songs out of the test partition. If it ever stopped
    -- winning, every already-spent row would be reported as held-out evidence - the
    -- single worst failure this file can have.
    Test.expect(PackIsReserved('somepack', { somepack = true }) == false,
        'a walked pack is development even when the share is 100%')
end)

Test.it('a row with no pack id is development, not silently held out', function()
    -- The CSV has rows whose pack could not be determined. Treating those as reserved
    -- would quietly move real training data out of reach, so the safe default is the
    -- one that keeps them visible.
    Test.expect(PackIsReserved(nil, {}) == false, 'nil pack')
    Test.expect(PackIsReserved('', {}) == false, 'empty pack')
end)

Test.section('TierDiagnostics - the per-tier slicing the pooled figure hides')

-- Minimal residual rows: TierDiagnostics only reads tier_act, tier_pred and dist.
local function Resid(spec)
    local out = {}
    for _, s in ipairs(spec) do
        for _ = 1, s[3] do
            out[#out + 1] = { tier_act = s[1], tier_pred = s[2],
                              dist = math.abs(s[2] - s[1]) }
        end
    end
    return out
end

Test.it('pooled and macro diverge exactly when tier sizes differ', function()
    -- 90 rows in tier 3, all correct. 10 rows in tier 6, all two tiers out.
    -- Pooled = 90/100. Macro = mean(1.00, 0.00) = 0.50.
    local d = TierDiagnostics(Resid({ { 3, 3, 90 }, { 6, 4, 10 } }))
    Test.expect(math.abs(d.pooled - 0.90) < 1e-9, ('pooled %.4f'):format(d.pooled))
    Test.expect(math.abs(d.macro - 0.50) < 1e-9, ('macro %.4f'):format(d.macro))
end)

Test.it('they agree when every occupied tier is the same size', function()
    -- With equal n per tier, equal weighting IS the pooled weighting.
    local d = TierDiagnostics(Resid({ { 1, 1, 20 }, { 2, 2, 20 }, { 3, 4, 20 } }))
    Test.expect(math.abs(d.pooled - d.macro) < 1e-9,
        ('pooled %.4f vs macro %.4f'):format(d.pooled, d.macro))
end)

Test.it('a one-tier miss still counts as usable, two does not', function()
    local d = TierDiagnostics(Resid({ { 3, 4, 5 }, { 3, 5, 5 } }))
    Test.expect(math.abs(d.pooled - 0.50) < 1e-9,
        'within-one is usable, within-two is not')
end)

Test.it('signed bias keeps its direction rather than being absolute', function()
    -- The whole point of reporting bias separately from distance: over- and
    -- under-prediction cancel in the mean, and that cancellation is what made the
    -- overall bias look like absence of bias.
    local d = TierDiagnostics(Resid({ { 1, 2, 10 }, { 5, 4, 10 } }))
    local by = {}
    for _, t in ipairs(d.tiers) do by[t.tier] = t.bias end
    Test.expect(math.abs(by[1] - 1.0) < 1e-9, ('low tier bias %.2f, expected +1'):format(by[1]))
    Test.expect(math.abs(by[5] + 1.0) < 1e-9, ('high tier bias %.2f, expected -1'):format(by[5]))
end)

Test.it('the endpoint band pools tiers 0-1 and 5-6 and skips the middle', function()
    -- 10 rows at tier 0 all correct, 10 at tier 6 all wrong, 100 in the middle correct.
    local d = TierDiagnostics(Resid({ { 0, 0, 10 }, { 6, 3, 10 }, { 3, 3, 100 } }))
    Test.expect(d.ep_n == 20, ('endpoint n %d, expected 20'):format(d.ep_n))
    Test.expect(math.abs(d.endpoint - 0.50) < 1e-9,
        ('endpoint %.4f, expected 0.50'):format(d.endpoint))
    Test.expect(d.n == 120, 'total still counts every row')
end)

Test.it('the confusion matrix counts every row exactly once', function()
    local d = TierDiagnostics(Resid({ { 2, 2, 7 }, { 2, 3, 3 }, { 5, 4, 4 } }))
    local total = 0
    for _, row in pairs(d.matrix) do
        for _, c in pairs(row) do total = total + c end
    end
    Test.expect(total == 14, ('matrix holds %d rows, expected 14'):format(total))
    Test.expect(d.matrix[2][2] == 7 and d.matrix[2][3] == 3, 'cells land where expected')
end)

Test.it('predicted counts expose compression toward the middle', function()
    -- Ten charts are officially tier 6; the model puts one there. That asymmetry is
    -- invisible in usable% and is the reason n_pred is reported at all.
    local d = TierDiagnostics(Resid({ { 6, 6, 1 }, { 6, 5, 9 }, { 3, 3, 20 } }))
    local by = {}
    for _, t in ipairs(d.tiers) do by[t.tier] = t end
    Test.expect(by[6].n == 10, 'ten official tier-6 rows')
    Test.expect(by[6].n_pred == 1, ('predicted tier 6 %d times, expected 1'):format(by[6].n_pred))
end)

Test.it('an empty or absent residual list returns nil rather than dividing by zero', function()
    Test.expect(TierDiagnostics(nil) == nil, 'nil in, nil out')
    Test.expect(TierDiagnostics({}) == nil, 'empty in, nil out')
end)
