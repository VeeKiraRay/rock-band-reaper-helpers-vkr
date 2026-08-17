-- Do the OTHER parts of a song carry anything the target chart does not? Run from the
-- repository root:
--   lua dev/calibration/run_cross_instrument_probe_offline.lua
--
-- Every model fitted so far predicts an instrument's rank from that instrument's own
-- chart. README.md's Open threads calls this the cheapest remaining lead: the other
-- instruments' RANKS cannot be used at suggest time (a rank is what the author is asking
-- the tool for), but their MEASURED FACTORS can, because the author has the whole MIDI.
--
-- This is a PROBE, not a round. Nothing here fits a shipped model, declares a candidate,
-- or touches lib/ or corpus_scores.csv. Its output is evidence for deciding whether a
-- round 19 is worth declaring at all - and, if the answer is no, a permanently closed
-- lead, which is worth as much as a win and considerably cheaper than finding out later.
--
-- Writes calibration_cross_instrument_report.txt beside the other reports.
--
----------------------------------------------------------------------
-- WHAT IS DECLARED, AND WHY EACH ONE
----------------------------------------------------------------------
--
--   keys      <- real_keys     0 rows lost   MEASURE ONLY, see below
--   real_keys <- keys          0 rows lost   the shippable direction
--   vocals    <- guitar, drum  ~3 rows lost  STAGE A ONLY, a pre-registered null
--
-- KEYS <- REAL_KEYS IS PRE-COMMITTED AS UNSHIPPABLE, before its number is known, so that
-- a good result cannot argue its way into the product afterwards. The 5-lane keys chart
-- is a lossy reduction of the performance the Pro Keys chart records in full, so this is
-- the direction with the mechanism and probably the direction with the signal. It is also
-- the direction that must not ship: RB3 requires PART KEYS for a Pro Keys chart, but NOT
-- the reverse, so a keys model reading Pro Keys columns would fail for every project that
-- has not authored Pro Keys yet - which is most projects, most of the time.
--
-- If it wins, the honest product expression is a NOTE and not a model input: something of
-- the form "the Pro Keys chart spans 3x the range of this reduction" has no gate to pass,
-- no dependency to design, and does not make a Keys suggestion move when no Keys note
-- changed. Recorded here so the follow-up is obvious and the shortcut is not.
--
-- (Range and movement are the right quantities for such a note; note COUNT and strike
-- RATE are not, because the reduction preserves those exactly - see cross_factors.lua.)
--
-- VOCALS IS A NULL BEING MEASURED, not a candidate being hunted. Other instruments' RANKS
-- predict a vocals rank at only rho +0.219, the lowest of the six (run_label_probes has
-- the number). A rank is Harmonix's own expert reduction of a chart to one difficulty
-- number - a strictly better summary than three of that chart's densities - so three
-- density columns should do worse than +0.219, not better. Prediction 1 says so outright.
--
----------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT DECLARED
----------------------------------------------------------------------
--
-- So a later session reads these as decisions rather than oversights:
--
--   * GUITAR, BASS AND DRUMS AS TARGETS. All three pass the gate. Re-opening a passing
--     instrument to test a mechanism with no product need is the selection inflation the
--     protocol's 1-point-and-70%-of-repeats bar exists to prevent, and a win there would
--     buy a cross-chart dependency for zero gate movement.
--   * KEYS OR PRO KEYS AS A SOURCE FOR VOCALS. Measured: 64 of 328 rows lost, 19.5%.
--     Every vocals figure in this probe would then describe a different row set from
--     every vocals figure already published, and the shift in the interval lower bound
--     would be larger than the effect being measured. A number, not a preference.
--   * VOCALS AS A SOURCE. Its vocabulary shares only playing_s, the tightness percentiles
--     and entropy_h2_rel with the gem sets, so the single-vocabulary rule cannot include
--     it, and inventing a bespoke vocals-to-X column set would be a per-pair search.
--   * THE SOURCE'S FULL FACTOR SET. 96 columns are sitting in the CSV and ridge is
--     tempting. At n=266 it cannot carry them; README.md's deathontwolegs case is what a
--     too-wide fit does with a single extreme row.
--   * DERIVED CROSS TERMS - ratios such as x_real_keys_total_changes / total_changes,
--     i.e. "the reduction dropped 40% of the changes". This is probably the RIGHT
--     parameterisation if the direct columns show anything at all, which is exactly why
--     it is not here: it would make this two hypotheses in one probe. Conditional round
--     20, if and only if the direct columns earn it.
--   * THE OTHER INSTRUMENT'S RANK. Ruled out by what the author is asking for, and
--     already measured by run_label_probes_offline.lua. Restated so it is not re-proposed.
--   * BASS AS A SOURCE FOR THE KEYBOARDS. Zero rows lost, which makes it tempting, and
--     there is no mechanism. Co-presence is not a reason.

local _script = (arg and arg[0]) or 'dev/calibration/run_cross_instrument_probe_offline.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/calibration/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))
local _csv    = _dir .. 'corpus_scores.csv'
local _report = _dir .. 'calibration_cross_instrument_report.txt'

r = { ShowConsoleMsg = function(s) io.write(s) end }

dofile(_dir .. 'difficulty_score.lua')          -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')   -- appends the vocal columns
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')
dofile(_dir .. 'cross_factors.lua')             -- CROSS_COLUMNS, CrossColsFor, the join
dofile(_root .. 'lib/reaper_difficulty_models.lua')   -- the shipped candidate per instrument

local _rf = io.open(_report, 'w')
local function Msg(s)
    io.write(s)
    if _rf then _rf:write(s) end
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

local csv, err = LoadCsv(_csv)
if not csv then
    Msg(('Cannot read %s (%s)\n'):format(_csv, err))
    if _rf then _rf:close() end
    return
end

local function Field(row, name)
    local i = csv.header[name]
    return i and row[i] or nil
end

local factor_by_song = BuildFactorBySong(csv, Field)

----------------------------------------------------------------------
-- The protocol's own evaluation, reused
--
-- These figures have to be readable against numbers already published in
-- calibration_protocol_report.txt, so this uses the protocol's machinery rather than a
-- simpler fit: the same repeats, the same shared stratified folds, the same nested ridge,
-- the same clamp and the same tier grading. The only thing that varies between columns is
-- WHICH FEATURE KEYS are named.
--
-- Cross columns ride along as additional columns on d.feats with their own entries in
-- `pos`, so RunOneRepeat needs no modification - Slice simply reads feats[i][pos[k]].
--
-- Differs from run_label_probes_offline.lua's Evaluate in one way: no per-row residual is
-- attributed, because nothing here needs one. That drops the fold-order reconstruction,
-- which is the fiddliest part of that function and pure risk when unused.
----------------------------------------------------------------------

-- extra_cols is a list of CrossCol RECORDS, never name strings - see cross_factors.lua on
-- why an x_<src>_<key> name cannot be taken apart again.
local function Collect(inst, extra_cols)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    local pos = {}
    for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end
    local n_base = #SCORE_FACTOR_KEYS
    for j, c in ipairs(extra_cols) do pos[c.name] = n_base + j end

    local dropped_for = {}

    for _, row in ipairs(csv.rows) do
        if Field(row, 'instrument') == inst then
            local rank = tonumber(Field(row, 'rank'))
            local name = Field(row, 'shortname')
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(Field(row, k))
                if v == nil then ok = false else fv[j] = v end
            end
            -- The cross columns. A song missing one of them cannot be used by the
            -- comparison at all, so it is dropped from EVERY column rather than only from
            -- the one that needs it - otherwise the columns would describe different row
            -- sets and could not be read against each other.
            for j, c in ipairs(extra_cols) do
                local v = CrossValue(factor_by_song, name, c)
                if v == nil then
                    ok = false
                    dropped_for[c.src] = (dropped_for[c.src] or 0) + 1
                else
                    fv[n_base + j] = v
                end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]   = fv
                d.ranks[n]   = rank
                d.origins[n] = Field(row, 'origin')
                d.names[n]   = name
            end
        end
    end
    return d, pos, dropped_for
end

local function Partition(d, inst)
    local target = {}
    for i, o in ipairs(d.origins) do
        if o == 'rb3_dlc' and not IsWeirdlyScored(d.names[i], inst) then
            target[#target + 1] = i
        end
    end
    return target, AuxIndices(d.origins)
end

-- One candidate's worth of the protocol: N_REPEATS of shared-fold CV, aggregated the same
-- way RunProtocol aggregates. The usable LOWER bound is what the gate actually reads, so
-- it is reported beside the mean rather than left to be recomputed by hand.
local function Evaluate(d, target, aux, inst, keys, pos, scale)
    local strata = {}
    for n, ti in ipairs(target) do strata[n] = tostring(TierForRank(inst, d.ranks[ti])) end
    local rank_lo, rank_hi = RankRange(d, target)

    local usable, miss, rho = {}, {}, {}
    local n_rows = 0

    for rep = 1, PROTOCOL.N_REPEATS do
        local folds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
        local pred, act = RunOneRepeat(d, target, aux, folds, keys, pos, scale)
        if pred then
            local pt, at = {}, {}
            for i = 1, #pred do
                pred[i] = ClampRank(pred[i], rank_lo, rank_hi)
                pt[i] = TierForRank(inst, pred[i])
                at[i] = TierForRank(inst, act[i])
            end
            local dist = TierDistance(pt, at)
            usable[#usable + 1] = dist.usable / dist.n
            miss[#miss + 1]     = dist.miss / dist.n
            rho[#rho + 1]       = Spearman(pred, act) or 0
            n_rows = dist.n
        end
    end
    if #usable == 0 then return nil end

    local usable_mean = MeanOf(usable)
    return {
        usable = usable_mean,
        usable_lo = WilsonLower(usable_mean, n_rows, PROTOCOL.Z),
        miss = MeanOf(miss),
        miss_hi = WilsonUpper(MeanOf(miss), n_rows, PROTOCOL.Z),
        rho = MeanOf(rho), n_rows = n_rows,
        -- Per-repeat, so a challenger can be compared to the incumbent REPEAT BY REPEAT.
        -- Both columns saw the same folds in the same order (same SEED + rep), so the
        -- pairing is exact and the difference of the means is not the whole story - the
        -- protocol's second criterion is how OFTEN the challenger wins, not by how much.
        per_repeat = usable,
    }
end

-- The protocol's own selection bar, applied here rather than eyeballed: a challenger must
-- beat the incumbent by GAIN_POINTS *and* win at least WIN_SHARE of the paired repeats.
-- Reported for the probe's own columns so the decision "is this worth declaring as a
-- round" is answered with the rule the round itself would be judged by.
local function PairedWinShare(challenger, incumbent)
    if not (challenger and incumbent and challenger.per_repeat and incumbent.per_repeat) then
        return nil
    end
    local n, wins = math.min(#challenger.per_repeat, #incumbent.per_repeat), 0
    if n == 0 then return nil end
    for i = 1, n do
        if challenger.per_repeat[i] > incumbent.per_repeat[i] then wins = wins + 1 end
    end
    return wins / n, n
end

local function ScaleNamed(name)
    for _, s in ipairs(SCALES) do
        if s.name == name then return s end
    end
    return SCALES[1]
end

----------------------------------------------------------------------
-- The declared pairs
----------------------------------------------------------------------

-- `cols` nil means CROSS_COLUMNS. The @geom pairs use CROSS_COLUMNS_GEOMETRY and exist
-- because the first vocabulary turned out to be near-duplicate on the keyboard pair - see
-- cross_factors.lua for the measured ratios that forced the addendum.
local PAIRS = {
    { target = 'keys',      sources = { 'real_keys' },
      note = 'MEASURE ONLY - dependency runs the wrong way, see header' },
    { target = 'real_keys', sources = { 'keys' },
      note = 'the shippable direction' },
    { target = 'vocals',    sources = { 'guitar', 'drum' },
      note = 'stage A only - pre-registered as a null' },

    { target = 'keys',      sources = { 'real_keys' }, cols = CROSS_COLUMNS_GEOMETRY,
      tag = '@geom', note = 'ADDENDUM - the columns the reduction does NOT preserve' },
    { target = 'real_keys', sources = { 'keys' },      cols = CROSS_COLUMNS_GEOMETRY,
      tag = '@geom', note = 'ADDENDUM - same, shippable direction' },
}

Msg('======  Cross-instrument chart factors  ======\n\n')
Msg(('CSV : %s   (%d rows)\n'):format(_csv, #csv.rows))
Msg(('Cross columns, one vocabulary for every pair: %s\n\n')
    :format(table.concat(CROSS_COLUMNS, ', ')))

Msg([[
Three predictors of the same rank, scored by the LOCKED protocol (10 repeats, shared
stratified folds, nested ridge, same clamp and tier grading):

  chart        the shipped candidate's factors - today's model
  chart+cross  the same, plus the other part's three columns
  cross only   ONLY the other part's columns; no evidence from the chart being ranked

`cross only` exists to size the ceiling, and is a diagnostic that must never become a
candidate: the protocol's tie-break prefers the simpler model, so a 3-column cross-only
entry landing within a point of a 7-column incumbent would WIN SELECTION and ship a keys
model made entirely of Pro Keys columns. It is measured here, where nothing is selected,
and deliberately not declared in protocol.lua.

]])

local results = {}

Msg(('  %-11s %-12s %-9s %-9s %-9s %-7s %s\n')
    :format('target', 'predictor', 'usable', 'lower', 'rho', 'n', 'note'))
Msg('  ' .. string.rep('-', 82) .. '\n')

for _, pair in ipairs(PAIRS) do
    local inst  = pair.target
    local model = RB_DIFFICULTY_MODELS[inst]
    -- An instrument appears more than once (first vocabulary, then @geom), so results are
    -- keyed by the pair rather than by the instrument. The bare instrument key stays the
    -- FIRST vocabulary's result, which is what the pre-registered predictions named.
    pair.slot = inst .. (pair.tag or '')
    if model then
        local scale = ScaleNamed(model.scale)
        -- The shipped model's own factor list, minus the appended origin flags.
        local chart_keys = {}
        for _, k in ipairs(model.keys) do
            if not k:match('^is_') then chart_keys[#chart_keys + 1] = k end
        end

        local cross = {}
        for _, src in ipairs(pair.sources) do
            for _, c in ipairs(CrossColsFor(src, pair.cols)) do cross[#cross + 1] = c end
        end
        local cross_names = {}
        for _, c in ipairs(cross) do cross_names[#cross_names + 1] = c.name end

        -- FIDELITY GATE. The chart column over EVERY target row must reproduce the number
        -- already published in calibration_protocol_report.txt. If it does not, this
        -- harness is not running the protocol and its novel columns mean nothing.
        local d0, pos0 = Collect(inst, {})
        local t0, aux0 = Partition(d0, inst)
        local fid = Evaluate(d0, t0, aux0, inst, chart_keys, pos0, scale)

        -- The comparison itself, on the subset where every cross source exists, so all
        -- three columns describe the same rows.
        local d1, pos1, dropped = Collect(inst, cross)
        local t1, aux1 = Partition(d1, inst)

        local both = {}
        for _, k in ipairs(chart_keys)  do both[#both + 1] = k end
        for _, k in ipairs(cross_names) do both[#both + 1] = k end

        local res = {
            chart = Evaluate(d1, t1, aux1, inst, chart_keys,   pos1, scale),
            both  = Evaluate(d1, t1, aux1, inst, both,         pos1, scale),
            cross = Evaluate(d1, t1, aux1, inst, cross_names,  pos1, scale),
        }
        results[pair.slot] = {
            res = res, fid = fid, lost = #t0 - #t1, dropped = dropped,
            sources = pair.sources,
        }

        local label = { chart = 'chart', both = 'chart+cross', cross = 'cross only' }
        for _, which in ipairs({ 'chart', 'both', 'cross' }) do
            local e = res[which]
            if e then
                Msg(('  %-11s %-12s %7.2f%%  %7.2f%%  %+7.3f  %-7d %s\n')
                    :format(which == 'chart' and pair.slot or '', label[which],
                            e.usable * 100, e.usable_lo * 100, e.rho, e.n_rows,
                            which == 'chart'
                                and ('<- ' .. table.concat(pair.sources, ' + ')
                                     .. ' [' .. table.concat(pair.cols or CROSS_COLUMNS, ', ')
                                     .. ']') or ''))
            end
        end
        if fid then
            Msg(('  %-11s %-12s %7.2f%%  %7.2f%%  %+7.3f  %-7d %s\n')
                :format('', 'chart, all', fid.usable * 100, fid.usable_lo * 100,
                        fid.rho, fid.n_rows, '<- must match the protocol report'))
        end
        Msg(('  %-11s %s\n\n'):format('', pair.note))
    end
end

----------------------------------------------------------------------
-- Row-loss gate
--
-- Not a footnote. A pair that loses rows is not measuring what the published figures
-- measured, and the keyboard pair losing any at all would mean the join is wrong rather
-- than that the corpus changed.
----------------------------------------------------------------------

Msg('ROW LOSS - rows dropped because the song lacks the source part\n')
Msg(string.rep('-', 76) .. '\n')
for _, pair in ipairs(PAIRS) do
    local rec = results[pair.slot]
    if rec then
        local parts = {}
        for _, src in ipairs(pair.sources) do
            parts[#parts + 1] = ('%s %d'):format(src, rec.dropped[src] or 0)
        end
        local pct = rec.fid and rec.fid.n_rows > 0
            and (rec.lost / rec.fid.n_rows * 100) or 0
        local flag = ''
        if pair.target == 'keys' or pair.target == 'real_keys' then
            flag = (rec.lost == 0) and '  as declared' or '  <<<< EXPECTED ZERO'
        elseif rec.lost > 10 then
            flag = '  <<<< material, figures are not comparable'
        end
        Msg(('  %-11s %d of %d target rows (%.1f%%)   [%s]%s\n')
            :format(pair.slot, rec.lost, rec.fid and rec.fid.n_rows or 0, pct,
                    table.concat(parts, ', '), flag))
    end
end

----------------------------------------------------------------------
-- Predictions, marked
----------------------------------------------------------------------

----------------------------------------------------------------------
-- The selection bar, and the gate, applied rather than eyeballed
--
-- A usable mean that rises is not a result. The protocol selects a challenger only when
-- it beats the incumbent by SELECT_MIN_GAIN *and* wins SELECT_WIN_SHARE of the paired
-- repeats, and it passes the gate only on all three of usable-lower, miss-upper and rho.
-- Both rules are printed here so a promising-looking number cannot be mistaken for a
-- round that would actually land.
----------------------------------------------------------------------

Msg('\n\nWOULD THE PROTOCOL SELECT IT, AND WOULD IT PASS THE GATE?\n')
Msg(string.rep('-', 92) .. '\n')
Msg(('  bar: gain > %.2f points AND wins > %.0f%% of paired repeats.'
    .. '   gate: usable_lo >= %.0f%%, miss_hi <= %.0f%%, rho >= %.2f\n\n')
    :format(SELECT_MIN_GAIN * 100, SELECT_WIN_SHARE * 100,
            PROTOCOL.USABLE_FLOOR * 100, PROTOCOL.MISS_CEILING * 100,
            PROTOCOL.RHO_FLOOR))

Msg(('  %-11s %-8s %-9s %-11s %-9s %-9s %-8s %s\n')
    :format('target', 'gain', 'win share', 'selected?', 'usable_lo', 'miss_hi', 'rho',
            'gate'))
Msg('  ' .. string.rep('-', 90) .. '\n')

for _, pair in ipairs(PAIRS) do
    local rec = results[pair.slot]
    if rec and rec.res.chart and rec.res.both then
        local ch, bo = rec.res.chart, rec.res.both
        local gain = bo.usable - ch.usable
        local share = PairedWinShare(bo, ch) or 0
        local selected = (gain > SELECT_MIN_GAIN) and (share > SELECT_WIN_SHARE)
        local gate_ok = (bo.usable_lo >= PROTOCOL.USABLE_FLOOR)
            and (bo.miss_hi <= PROTOCOL.MISS_CEILING)
            and (bo.rho >= PROTOCOL.RHO_FLOOR)
        Msg(('  %-11s %+7.2f  %8.0f%%  %-11s %8.2f%%  %8.2f%%  %+7.3f  %s\n')
            :format(pair.slot, gain * 100, share * 100,
                    selected and 'YES' or 'no', bo.usable_lo * 100, bo.miss_hi * 100,
                    bo.rho, gate_ok and 'PASSES' or 'fails'))
    end
end

Msg('\n\nPREDICTIONS RECORDED BEFORE RUNNING\n')
Msg(string.rep('-', 76) .. '\n')

local function Gain(rec)
    if not (rec and rec.res.chart and rec.res.both) then return nil end
    return (rec.res.both.usable - rec.res.chart.usable) * 100
end

do
    local v = results.vocals
    local g = Gain(v)
    if g then
        Msg(('  1. Vocals gains under 1 usable point from guitar and drum columns. A RANK\n'
            .. '     is a better summary of a chart than three of its densities, and other\n'
            .. '     instruments\' ranks already reach only rho +0.219 on vocals.\n'
            .. '     -> gain %+.2f points, rho %+.3f -> %+.3f.  %s\n')
            :format(g, v.res.chart.rho, v.res.both.rho, (g < 1.0) and 'HIT' or 'MISSED'))
    end
end

do
    local k, rk = Gain(results.keys), Gain(results.real_keys)
    if k and rk then
        Msg(('  2. keys <- real_keys gains more than real_keys <- keys. The reduction is\n'
            .. '     lossy in one direction only.\n'
            .. '     -> keys %+.2f, Pro Keys %+.2f.  %s\n')
            :format(k, rk, (k > rk) and 'HIT' or 'MISSED'))
    end
end

do
    local k = results.keys
    if k and k.res.cross then
        local rho = k.res.cross.rho
        Msg(('  3. `cross only` on keys reaches rho >= +0.70 - Pro Keys factors ALONE\n'
            .. '     nearly reproduce the keys rank. If true this is a statement about the\n'
            .. '     label, not a model.\n'
            .. '     -> rho %+.3f.  %s\n')
            :format(rho, (rho >= 0.70) and 'HIT' or 'MISSED'))
    end
end

do
    local k, rk = results.keys, results.real_keys
    if k and rk and k.res.both and rk.res.both then
        local kb, rb = k.res.both.usable_lo * 100, rk.res.both.usable_lo * 100
        local both_under = (kb < 90.0) and (rb < 90.0)
        local gain = (k.res.both.usable - k.res.chart.usable) * 100
        local share = (PairedWinShare(k.res.both, k.res.chart) or 0) * 100
        Msg(('  4. Neither keyboard candidate clears the 90%% usable LOWER bound. Keys\' gap\n'
            .. '     is an accuracy ceiling, not a specification gap, and three correlated\n'
            .. '     columns do not lift a ceiling.\n'
            .. '     -> keys %.2f%%, Pro Keys %.2f%%.  %s\n')
            :format(kb, rb, both_under and 'HIT' or 'MISSED'))
        -- WRONG ON THE LETTER, RIGHT ON THE SUBSTANCE, and a bare MISSED would hide that.
        -- The bound did cross 90%, so the prediction as written failed. But it crossed by
        -- +0.45 points on a bar that requires 1.00, winning exactly 70% of paired repeats
        -- against a rule that needs MORE than 70% - so the protocol declines it on both
        -- criteria at once. "Does not lift the ceiling" was the right claim about the
        -- effect; "stays under 90%" was the wrong way to have measured it, because a
        -- threshold 0.06 away can be crossed by noise the selection bar is built to reject.
        Msg(('     NOTE: the bound crossed, the SELECTION did not - gain %+.2f against a\n'
            .. '     %.2f-point bar, winning %.0f%% of paired repeats against a >%.0f%% rule.\n'
            .. '     The prediction failed as written and holds as stated: the ceiling is\n'
            .. '     intact and the crossing is inside the noise band the bar exists to reject.\n')
            :format(gain, SELECT_MIN_GAIN * 100, share, SELECT_WIN_SHARE * 100))
    end
end

do
    local k, rk, v = results.keys, results.real_keys, results.vocals
    if k and rk and v then
        local kb_zero = (k.lost == 0) and (rk.lost == 0)
        Msg(('  5. Zero rows lost on the keyboard pair in both directions; a handful on\n'
            .. '     vocals <- guitar + drum.\n'
            .. '     -> keys %d, Pro Keys %d, vocals %d.  %s\n')
            :format(k.lost, rk.lost, v.lost, kb_zero and 'HIT' or 'MISSED'))
    end
end

-- Registered before the @geom pairs were run, after the first vocabulary had been run and
-- the redundancy measured. Stated that way rather than backdated: prediction 6 had
-- evidence 1-5 did not, and pretending otherwise would misrepresent how it was formed.
do
    local kg, rg = Gain(results['keys@geom']), Gain(results['real_keys@geom'])
    local k = Gain(results.keys)
    if kg and rg and k then
        Msg(('  6. [registered after 1-5, before the @geom run] The geometry columns beat\n'
            .. '     the rhythm columns on keys <- Pro Keys, because the rhythm columns are\n'
            .. '     the SAME NUMBER on both charts (ratio 1.00) while span and movement\n'
            .. '     differ 2.5-3.2x. Both still fail the 1-point selection bar: the keys\n'
            .. '     ceiling is not a missing-column problem.\n'
            .. '     -> geometry %+.2f vs rhythm %+.2f on keys; Pro Keys geometry %+.2f.\n'
            .. '        geometry beat rhythm: %s   both still under the bar: %s\n')
            :format(kg, k, rg,
                    (kg > k) and 'YES' or 'no',
                    (kg <= 1.0 and rg <= 1.0) and 'YES' or 'NO - one cleared it'))
    end
end

Msg('\nNothing here fits a shipped model. lib/ and corpus_scores.csv are untouched.\n')

if _rf then
    _rf:close()
    io.write(('\n[report written to %s]\n'):format(_report))
end
