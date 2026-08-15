-- Tests for the shipped difficulty suggester: the frozen model artifact, the predictor
-- that applies it, and the tier arithmetic the UI reports.
--
-- Pure - no project, no MIDI editor. Driven by run_difficulty_suggester.lua.
--
-- THE PARITY SECTION IS THE POINT OF THIS FILE. Everything else here checks arithmetic
-- that would be obvious when wrong. Parity checks the one thing that would NOT be: that
-- lib/reaper_difficulty_models.lua really is the candidate the locked protocol selected,
-- fitted on the rows it was allowed to train on. A factor-order slip, a wrong training
-- partition, or a stale artifact all produce numbers that look entirely plausible.

----------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------

-- Repo root, derived from this file rather than from the runner, so the paths below hold
-- however the suite was launched.
local _self  = debug.getinfo(1, 'S').source:match('^@(.*)$')
local _tdir  = _self and _self:match('^(.+[\\/])') or ''
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root  = _up(_up(_tdir))

local CSV_PATH = _root .. 'dev/calibration/corpus_scores.csv'
local TS_PATH  = _root .. '_external_docs/InstrumentDifficulty.ts'

local function Split(line)
    local out = {}
    for field in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = field end
    return out
end

local function LoadCsv(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local header, header_line, rows = nil, nil, {}
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
    return { header = header, header_line = header_line, rows = rows }
end

local _csv = LoadCsv(CSV_PATH)

-- The corpus CSV is versioned, so it should be here. If it is not - a deployed copy, say -
-- the parity section is SKIPPED LOUDLY rather than silently passing with zero assertions,
-- which is the failure mode that makes a green suite meaningless.
local function RequireCsv()
    Test.expect(_csv ~= nil,
        'corpus_scores.csv not found at ' .. CSV_PATH ..
        ' - parity cannot be checked. Run these tests from the repo checkout.')
end

----------------------------------------------------------------------
-- Tier thresholds against their source
----------------------------------------------------------------------

Test.section('difficulty tiers - transcription')

-- RANK_TIER_THRESHOLDS is a hand transcription of a TypeScript file. Re-derive it from
-- that file rather than trusting the copy: a transposed digit here silently shifts every
-- reported tier, and the drums row has already been wrong once (diff5 read 245, making
-- the Challenging band three rank points wide).
local function ParseThresholdsTs(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local text = f:read('a')
    f:close()
    local out = {}
    for name, body in text:gmatch('const%s+([%u_]+)_DIFFICULTY_THRESHOLDS[^{]*{(.-)}') do
        local t = {}
        for i = 1, 6 do
            t[i] = tonumber(body:match('diff' .. i .. ':%s*(%d+)'))
        end
        out[name] = t
    end
    return out
end

local TS_TO_LUA = {
    GUITAR = 'guitar', BASS = 'bass', DRUMS = 'drum', VOCALS = 'vocals',
    KEYS = 'keys', PRO_KEYS = 'real_keys', PRO_BASS = 'real_bass',
    PRO_GUITAR = 'real_guitar', BAND = 'band',
}

Test.it('every threshold row matches _external_docs/InstrumentDifficulty.ts', function()
    local ts = ParseThresholdsTs(TS_PATH)
    Test.expect(ts ~= nil, 'InstrumentDifficulty.ts not found at ' .. TS_PATH)
    local checked = 0
    for ts_name, lua_key in pairs(TS_TO_LUA) do
        local src = ts[ts_name]
        Test.expect(src ~= nil, 'no ' .. ts_name .. ' block in the .ts source')
        local got = RANK_TIER_THRESHOLDS[lua_key]
        Test.expect(got ~= nil, 'no RANK_TIER_THRESHOLDS entry for ' .. lua_key)
        for i = 1, 6 do
            Test.expect(got[i] == src[i], ('%s diff%d: table says %s, source says %s')
                :format(lua_key, i, tostring(got[i]), tostring(src[i])))
        end
        checked = checked + 1
    end
    Test.expect(checked == 9, 'expected 9 instrument rows, checked ' .. checked)
end)

Test.it('the drums diff5 correction is still 345, not 245', function()
    -- Guarding the specific regression: 245 made Challenging span 242-244 and put zero
    -- corpus charts in it. 345 restores the widening-gap shape every other row has.
    Test.expect(RANK_TIER_THRESHOLDS.drum[5] == 345, 'drums diff5 is not 345')
    local gaps = {}
    for i = 2, 6 do gaps[#gaps + 1] = RANK_TIER_THRESHOLDS.drum[i] - RANK_TIER_THRESHOLDS.drum[i - 1] end
    for i = 2, #gaps do
        Test.expect(gaps[i] >= gaps[i - 1], 'drums tier bands stop widening at band ' .. i)
    end
end)

----------------------------------------------------------------------
-- TierForRank / TierBand / TierPosition
----------------------------------------------------------------------

Test.section('difficulty tiers - lookup and position')

Test.it('rank 0 and absent parts are nil, not tier 0', function()
    Test.expect(TierForRank('guitar', 0) == nil, 'rank 0 should be nil')
    Test.expect(TierForRank('guitar', nil) == nil, 'nil rank should be nil')
    Test.expect(TierForRank('kazoo', 200) == nil, 'unknown instrument should be nil')
    Test.expect(TierPosition('guitar', 0) == nil, 'position of rank 0 should be nil')
    Test.expect(TierName(nil) == 'No Part', 'nil tier should name as No Part')
end)

Test.it('a rank exactly on a threshold belongs to the higher tier', function()
    local t = RANK_TIER_THRESHOLDS.guitar
    for i = 1, 6 do
        Test.expect(TierForRank('guitar', t[i]) == i,
            ('rank %d should be tier %d'):format(t[i], i))
        Test.expect(TierForRank('guitar', t[i] - 1) == i - 1,
            ('rank %d should be tier %d'):format(t[i] - 1, i - 1))
    end
end)

Test.it('position is 0 at the bottom edge of every band', function()
    local t = RANK_TIER_THRESHOLDS.guitar
    for i = 1, 6 do
        local p = TierPosition('guitar', t[i], 605)
        Test.expect(math.abs(p) < 1e-12, ('tier %d bottom edge gave %.6f'):format(i, p))
    end
    -- Tier 0's bottom edge is rank 1: rank 0 means no part, not the easiest chart.
    local lo = select(1, TierBand('guitar', 0))
    Test.expect(lo == 1, 'tier 0 band should start at 1, got ' .. tostring(lo))
end)

Test.it('the product plan worked example reproduces: guitar 271 is 0.06 into tier 4', function()
    Test.expect(TierForRank('guitar', 271) == 4, 'rank 271 should be tier 4')
    local p = TierPosition('guitar', 271, 605)
    Test.expect(math.abs(p - 4 / 66) < 1e-9, ('expected 0.0606, got %.4f'):format(p))
end)

Test.it('tier 6 is closed by the observed maximum, and never overflows', function()
    local lo, hi = TierBand('guitar', 6, 605)
    Test.expect(lo == 409 and hi == 605, ('tier 6 band %s..%s'):format(tostring(lo), tostring(hi)))
    Test.expect(math.abs(TierPosition('guitar', 605, 605) - 1) < 1e-12, 'top of tier 6 should be 1')
    -- A chart harder than anything in the corpus must read 1, not something above it.
    Test.expect(TierPosition('guitar', 900, 605) == 1, 'beyond the observed max should clamp to 1')
end)

Test.it('tier 6 without an observed maximum borrows the width of the band below', function()
    local lo, hi = TierBand('guitar', 6)
    Test.expect(lo == 409, 'tier 6 should start at 409')
    Test.expect(hi == 409 + (409 - 333), ('expected 485, got %s'):format(tostring(hi)))
end)

----------------------------------------------------------------------
-- The predictor
----------------------------------------------------------------------

Test.section('difficulty predictor')

-- A hand-built two-factor model, so the arithmetic is checkable by inspection rather than
-- against another implementation of the same thing.
local function ToyModel(over)
    local m = {
        candidate = 'toy', scale = 'rank', status = 'validated',
        keys = { 'density_peak', 'is_lego' },
        mean = { 10, 0 }, sd = { 2, 1 },
        coefs = { 50, 7 }, intercept = 200,
        ridge = 0.1, rank_lo = 100, rank_hi = 400,
        bounds = { density_peak = { min = 4, max = 16, p90 = 14 } },
        conc = {},
    }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

Test.it('standardizes before applying coefficients', function()
    -- (12 - 10) / 2 = 1 sd, so 200 + 50 = 250.
    local rank = DifficultyPredictRank(ToyModel(), { density_peak = 12 })
    Test.expect(math.abs(rank - 250) < 1e-12, 'expected 250, got ' .. tostring(rank))
end)

Test.it('always supplies is_lego = 0 rather than reading it off the chart', function()
    -- The chart cannot have an is_lego factor; if the predictor read one it would move
    -- the answer. Coefficient 7 on a mean-0 sd-1 column makes that visible immediately.
    local a = DifficultyPredictRank(ToyModel(), { density_peak = 10 })
    local b = DifficultyPredictRank(ToyModel(), { density_peak = 10, is_lego = 1 })
    Test.expect(math.abs(a - 200) < 1e-12, 'expected the intercept, got ' .. tostring(a))
    Test.expect(a == b, 'a chart-supplied is_lego changed the prediction')
end)

Test.it('reports a missing factor instead of defaulting it to zero', function()
    -- Zero is not neutral on a standardized column: here it would read as -5 sd.
    local rank, missing = DifficultyPredictRank(ToyModel(), {})
    Test.expect(rank == nil, 'a missing factor should not produce a rank')
    Test.expect(missing == 'density_peak', 'should name the missing factor')
end)

Test.it('clamps the rank, and says when it did', function()
    local hi, clamped = DifficultyPredictRank(ToyModel(), { density_peak = 100 })
    Test.expect(hi == 400, 'should clamp to rank_hi, got ' .. tostring(hi))
    Test.expect(clamped == true, 'should report that it clamped')
    local lo = DifficultyPredictRank(ToyModel(), { density_peak = -100 })
    Test.expect(lo == 100, 'should clamp to rank_lo, got ' .. tostring(lo))
    local mid, mid_clamped, raw = DifficultyPredictRank(ToyModel(), { density_peak = 12 })
    Test.expect(mid_clamped == false, 'an in-range rank should not report clamping')
    Test.expect(math.abs(raw - 250) < 1e-12, 'raw should be the unclamped value')
end)

Test.it('inverts log(rank) rather than returning the fitted value', function()
    local m = ToyModel({ scale = 'log(rank)', intercept = math.log(250), coefs = { 0, 0 } })
    local rank = DifficultyPredictRank(m, { density_peak = 12 })
    Test.expect(math.abs(rank - 250) < 1e-9, 'expected 250, got ' .. tostring(rank))
end)

Test.it('both target scales the exporter can emit are invertible', function()
    for _, name in ipairs({ 'rank', 'log(rank)' }) do
        Test.expect(type(DIFFICULTY_SCALE_INV[name]) == 'function',
            'no inverse for scale ' .. name)
    end
    Test.expect(math.abs(DIFFICULTY_SCALE_INV['log(rank)'](math.log(317)) - 317) < 1e-9,
        'log inverse is not exp')
end)

Test.it('flags factors outside the fitted range without moving the rank', function()
    local m = ToyModel()
    Test.expect(#DifficultyOutOfRange(m, { density_peak = 10 }) == 0, 'in-range should be quiet')
    local over = DifficultyOutOfRange(m, { density_peak = 20 })
    Test.expect(#over == 1 and over[1].side == 'above', 'should report an above-range factor')
    local under = DifficultyOutOfRange(m, { density_peak = 1 })
    Test.expect(#under == 1 and under[1].side == 'below', 'should report a below-range factor')
    -- The warning is advisory: it must not change what the model predicted.
    Test.expect(DifficultyPredictRank(m, { density_peak = 20 })
             == DifficultyPredictRank(m, { density_peak = 20 }), 'prediction should be stable')
end)

Test.it('reports factor z-scores for the explanation layer, skipping is_lego', function()
    local zs = DifficultyFactorZ(ToyModel(), { density_peak = 14 })
    Test.expect(#zs == 1, 'is_lego should not be offered as a chart property')
    Test.expect(zs[1].key == 'density_peak', 'wrong factor reported')
    Test.expect(math.abs(zs[1].z - 2) < 1e-12, 'expected z = 2, got ' .. tostring(zs[1].z))
end)

----------------------------------------------------------------------
-- The frozen artifact
----------------------------------------------------------------------

Test.section('frozen model artifact')

Test.it('loads, declares a schema this build understands, and covers six instruments', function()
    Test.expect(type(RB_DIFFICULTY_MODELS) == 'table', 'no RB_DIFFICULTY_MODELS table')
    Test.expect(RB_DIFFICULTY_MODELS_SCHEMA == 1,
        'unexpected artifact schema ' .. tostring(RB_DIFFICULTY_MODELS_SCHEMA))
    Test.expect(#RB_DIFFICULTY_MODEL_ORDER == 6,
        'expected 6 models, got ' .. #RB_DIFFICULTY_MODEL_ORDER)
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        Test.expect(RB_DIFFICULTY_MODELS[inst] ~= nil, 'no model for ' .. inst)
        Test.expect(RANK_TIER_THRESHOLDS[inst] ~= nil, 'no tier thresholds for ' .. inst)
    end
end)

Test.it('every model is internally consistent', function()
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m = RB_DIFFICULTY_MODELS[inst]
        local n = #m.keys
        Test.expect(#m.mean == n and #m.sd == n and #m.coefs == n,
            inst .. ': keys/mean/sd/coefs lengths disagree')
        Test.expect(m.keys[n] == 'is_lego', inst .. ': is_lego must be the last factor')
        Test.expect(DIFFICULTY_SCALE_INV[m.scale] ~= nil, inst .. ': unknown scale ' .. m.scale)
        Test.expect(m.rank_lo > 0 and m.rank_hi > m.rank_lo, inst .. ': bad rank clamp')
        for j = 1, n do
            Test.expect(m.sd[j] > 0, inst .. ': non-positive sd on factor ' .. m.keys[j])
        end
        local seen = {}
        for _, k in ipairs(m.keys) do
            Test.expect(not seen[k], inst .. ': factor ' .. k .. ' appears twice')
            seen[k] = true
        end
    end
end)

Test.it('the selected candidate and scale are the ones the protocol chose', function()
    -- Transcribed from calibration_protocol_report.txt. If a future round re-selects, this
    -- test is the thing that says the shipped model changed, out loud.
    local EXPECTED = {
        guitar    = { 'full@attacks',                     'log(rank)', 21 },
        bass      = { 'baseline+ent_rel@attacks',         'log(rank)', 3  },
        drum      = { 'full_drum',                        'rank',      26 },
        keys      = { 'primary+entropy_rel+complex_peak', 'rank',      8  },
        real_keys = { 'primary+ent_rel@attacks',          'rank',      7  },
        vocals    = { 'primary+range+parts',              'log(rank)', 10 },
    }
    for inst, want in pairs(EXPECTED) do
        local m = RB_DIFFICULTY_MODELS[inst]
        Test.expect(m.candidate == want[1],
            ('%s: candidate is %q, expected %q'):format(inst, m.candidate, want[1]))
        Test.expect(m.scale == want[2],
            ('%s: scale is %q, expected %q'):format(inst, m.scale, want[2]))
        -- +1 for the appended is_lego column.
        Test.expect(#m.keys == want[3] + 1,
            ('%s: %d factors, expected %d'):format(inst, #m.keys - 1, want[3]))
    end
end)

Test.it('maturity badges match the product status table', function()
    local EXPECTED = {
        guitar = 'validated', bass = 'validated', drum = 'validated',
        keys = 'beta', real_keys = 'experimental', vocals = 'experimental',
    }
    for inst, want in pairs(EXPECTED) do
        Test.expect(RB_DIFFICULTY_MODELS[inst].status == want,
            ('%s: status is %q, expected %q'):format(inst, RB_DIFFICULTY_MODELS[inst].status, want))
    end
end)

Test.it('was exported from the CSV sitting beside it', function()
    RequireCsv()
    local h = 0
    for i = 1, #_csv.header_line do h = (h * 31 + _csv.header_line:byte(i)) % 4294967296 end
    Test.expect(h == RB_DIFFICULTY_MODELS_CSV_FINGERPRINT,
        'the artifact was exported from a CSV with a different column set - re-run ' ..
        'dev/calibration/export_production_models.lua')
end)

----------------------------------------------------------------------
-- Parity: the artifact IS the fit it claims to be
----------------------------------------------------------------------

Test.section('model parity against the calibration CSV')

-- Rebuild each instrument's training partition from the CSV exactly as the exporter does,
-- refit at the ridge the artifact RECORDS (so this needs no ridge search), and compare.
--
-- Refitting rather than trusting the stored coefficients is what makes this a test. It
-- re-derives the model from the corpus through an independent code path and would catch a
-- wrong row partition, a wrong weight, a reordered factor list, or an artifact left stale
-- by a rescore.
local function Rebuild(inst)
    local m = RB_DIFFICULTY_MODELS[inst]
    local pos = {}
    for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

    local scale_fwd = (m.scale == 'log(rank)')
        and function(v) return math.log(math.max(1, v)) end
        or  function(v) return v end

    local X, ys, ws, rows = {}, {}, {}, {}
    local n_target, n_lego = 0, 0
    local rank_lo, rank_hi = math.huge, -math.huge

    for _, row in ipairs(_csv.rows) do
        local function F(name)
            local i = _csv.header[name]
            return i and row[i] or nil
        end
        if F('instrument') == inst then
            local rank   = tonumber(F('rank'))
            local origin = F('origin')
            local name   = F('shortname')
            local ok     = rank ~= nil
            local vals   = {}
            for _, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(F(k))
                if v == nil then ok = false else vals[k] = v end
            end
            local is_dev  = origin == 'rb3_dlc' and not IsWeirdlyScored(name, inst)
            local is_lego = origin == 'lego'
            if ok and (is_dev or is_lego) then
                local fv = {}
                for j = 1, #m.keys - 1 do fv[j] = vals[m.keys[j]] end
                fv[#m.keys] = is_lego and 1 or 0
                X[#X + 1]  = fv
                ys[#ys + 1] = scale_fwd(rank)
                ws[#ws + 1] = is_lego and PROTOCOL.LEGO_WEIGHT or 1.0
                if is_dev then
                    n_target = n_target + 1
                    if rank < rank_lo then rank_lo = rank end
                    if rank > rank_hi then rank_hi = rank end
                    rows[#rows + 1] = { factors = vals, rank = rank }
                else
                    n_lego = n_lego + 1
                end
            end
        end
    end
    return m, X, ys, ws, rows, n_target, n_lego, rank_lo, rank_hi
end

Test.it('training row counts match the protocol report', function()
    RequireCsv()
    -- From calibration_protocol_report.txt. A drifting count means the partition rule
    -- changed - a different disputed list, or a mis-read origin column.
    local EXPECTED = {
        guitar = { 158, 45 }, bass = { 159, 45 }, drum = { 159, 45 },
        vocals = { 157, 45 }, keys = { 122, 0 },  real_keys = { 122, 0 },
    }
    for inst, want in pairs(EXPECTED) do
        local m, _, _, _, _, n_target, n_lego = Rebuild(inst)
        Test.expect(n_target == want[1],
            ('%s: %d development rows, expected %d'):format(inst, n_target, want[1]))
        Test.expect(n_lego == want[2],
            ('%s: %d lego rows, expected %d'):format(inst, n_lego, want[2]))
        Test.expect(m.n_target == want[1] and m.n_lego == want[2],
            inst .. ': the artifact records different row counts than the CSV holds')
    end
end)

Test.it('the rank clamp is the observed range of the development rows', function()
    RequireCsv()
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m, _, _, _, _, _, _, rank_lo, rank_hi = Rebuild(inst)
        Test.expect(m.rank_lo == rank_lo and m.rank_hi == rank_hi,
            ('%s: clamp %s..%s, CSV says %s..%s'):format(inst,
                tostring(m.rank_lo), tostring(m.rank_hi), tostring(rank_lo), tostring(rank_hi)))
    end
end)

Test.it('refitting the CSV reproduces every stored coefficient', function()
    RequireCsv()
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m, X, ys, ws = Rebuild(inst)
        local fit = MultiFit(X, ys, m.ridge, ws)
        Test.expect(fit ~= nil, inst .. ': refit failed')
        Test.expect(math.abs(fit.intercept - m.intercept) < 1e-9,
            ('%s: intercept %.12g vs stored %.12g'):format(inst, fit.intercept, m.intercept))
        for j = 1, #m.coefs do
            for _, field in ipairs({ 'coefs', 'mean', 'sd' }) do
                local a, b = fit[field][j], m[field][j]
                Test.expect(math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)),
                    ('%s: %s[%d] (%s) %.12g vs stored %.12g')
                        :format(inst, field, j, m.keys[j], a, b))
            end
        end
    end
end)

Test.it('the predictor reproduces the fit on every development row', function()
    RequireCsv()
    -- The acceptance criterion from the product plan: applying the exported artifact to
    -- every eligible row must match a direct fit to well under a rank point.
    local worst, worst_where = 0, ''
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m, X, ys, ws, rows = Rebuild(inst)
        local fit = MultiFit(X, ys, m.ridge, ws)
        local inv = DIFFICULTY_SCALE_INV[m.scale]
        for _, row in ipairs(rows) do
            local fv = {}
            for j = 1, #m.keys - 1 do fv[j] = row.factors[m.keys[j]] end
            fv[#m.keys] = 0
            local want = inv(ApplyFit(fv, fit))
            if want < m.rank_lo then want = m.rank_lo end
            if want > m.rank_hi then want = m.rank_hi end
            local got = DifficultyPredictRank(m, row.factors)
            Test.expect(got ~= nil, inst .. ': predictor returned nil on a CSV row')
            local diff = math.abs(got - want)
            if diff > worst then worst, worst_where = diff, inst end
        end
    end
    Test.expect(worst < 1e-6,
        ('worst prediction difference %.3e rank, on %s (bar is 1e-6)'):format(worst, worst_where))
end)

Test.it('support bounds actually contain the development rows they describe', function()
    RequireCsv()
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m, _, _, _, rows = Rebuild(inst)
        -- Every training chart is inside its own support, so a corpus song can never
        -- trigger the "outside calibration range" warning. Anything that does is genuinely
        -- an extrapolation.
        for _, row in ipairs(rows) do
            local out = DifficultyOutOfRange(m, row.factors)
            Test.expect(#out == 0,
                ('%s: a development row reads as out of range on %s'):format(
                    inst, #out > 0 and out[1].key or '?'))
        end
    end
end)

----------------------------------------------------------------------
-- Explanations and warnings
----------------------------------------------------------------------

Test.section('difficulty explanations')

-- A record shaped like the adapter's, so the explain layer can be driven without REAPER.
local function FakeRec(inst, over)
    local m = RB_DIFFICULTY_MODELS[inst]
    -- Start every factor at its training mean, i.e. a perfectly ordinary chart.
    local factors = {}
    for j, k in ipairs(m.keys) do
        if k ~= 'is_lego' then factors[k] = m.mean[j] end
    end
    local rec = {
        instrument = inst, label = inst, ok = true, status = m.status,
        model = m, factors = factors,
        rank = 250, tier = 3, tier_name = 'Moderate', tier_position = 0.5,
        clamped = false, raw_rank = 250, span_source = 'anim',
    }
    for k, v in pairs(over or {}) do
        if k == 'factors' then
            for fk, fv in pairs(v) do factors[fk] = fv end
        else
            rec[k] = v
        end
    end
    return rec
end

-- Nudge one factor by n training standard deviations.
local function AtZ(inst, key, n)
    local m = RB_DIFFICULTY_MODELS[inst]
    for j, k in ipairs(m.keys) do
        if k == key then return m.mean[j] + n * m.sd[j] end
    end
    error('no factor ' .. key .. ' on ' .. inst)
end

Test.it('every factor of every shipped model has explanation wording', function()
    -- The product plan's acceptance criterion: every explanation maps to an existing
    -- measured factor. Checked in the strong direction - a model factor with no entry
    -- would silently drop out of the panel instead of being explained.
    local missing = {}
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        for _, k in ipairs(RB_DIFFICULTY_MODELS[inst].keys) do
            if k ~= 'is_lego' then
                local info = DIFFICULTY_FACTOR_INFO[k]
                if not (info and info.label and info.high and info.low) then
                    missing[#missing + 1] = inst .. '.' .. k
                end
            end
        end
    end
    Test.expect(#missing == 0, 'factors with no wording: ' .. table.concat(missing, ', '))
end)

Test.it('an ordinary chart gets no explanations and no noisy warnings', function()
    -- Every factor sits exactly at its training mean, so there is nothing notable to say.
    -- Manufacturing three observations here is what trains authors to ignore the panel.
    local rec = FakeRec('guitar')
    DifficultyAnnotate(rec)
    Test.expect(#rec.explanations == 0,
        'expected no explanations, got: ' .. table.concat(rec.explanations, ' | '))
    Test.expect(#rec.warnings == 0,
        'expected no warnings on a mid-tier average guitar chart, got ' .. #rec.warnings)
end)

Test.it('reports at most three properties, most unusual first', function()
    local rec = FakeRec('drum', { factors = {
        kick_density_peak = AtZ('drum', 'kick_density_peak', 3.0),
        density_peak      = AtZ('drum', 'density_peak', 2.0),
        offbeat_frac      = AtZ('drum', 'offbeat_frac', 1.5),
        tom_frac          = AtZ('drum', 'tom_frac', 1.2),
    } })
    DifficultyAnnotate(rec)
    Test.expect(#rec.explanations == 3, 'expected 3 explanations, got ' .. #rec.explanations)
    Test.expect(rec.explanations[1] == DIFFICULTY_FACTOR_INFO.kick_density_peak.high,
        'the most unusual factor should come first, got: ' .. rec.explanations[1])
    -- The full table is still available behind the expander, ordered the same way.
    Test.expect(#rec.factor_rows == #RB_DIFFICULTY_MODELS.drum.keys - 1,
        'factor rows should cover every model factor except is_lego')
    Test.expect(rec.factor_rows[1].key == 'kick_density_peak', 'rows are not sorted by |z|')
end)

Test.it('interval factors read the inverted way round', function()
    -- tight_p10 is a SPACING in quarter notes, so a low value is the hard direction. A
    -- naive high/low mapping would tell the author the chart is roomy when it is dense.
    local rec = FakeRec('guitar', { factors = { tight_p10 = AtZ('guitar', 'tight_p10', -2.5) } })
    DifficultyAnnotate(rec)
    Test.expect(rec.explanations[1] == 'Long stretches of closely spaced changes',
        'low tight_p10 should read as closely spaced, got: ' .. tostring(rec.explanations[1]))
end)

Test.section('difficulty warnings')

Test.it('flags both tier boundaries, and neither past the ends of the ladder', function()
    local near_low = FakeRec('guitar', { tier = 3, tier_position = 0.10 })
    DifficultyAnnotate(near_low)
    local kinds = {}
    for _, w in ipairs(near_low.warnings) do kinds[w.kind] = w.text end
    Test.expect(kinds.boundary and kinds.boundary:find('lower'), 'expected a lower-boundary warning')

    local near_high = FakeRec('guitar', { tier = 3, tier_position = 0.92 })
    DifficultyAnnotate(near_high)
    kinds = {}
    for _, w in ipairs(near_high.warnings) do kinds[w.kind] = w.text end
    Test.expect(kinds.boundary and kinds.boundary:find('upper'), 'expected an upper-boundary warning')

    -- Nothing below Warmup and nothing above Impossible, so those edges are not "close
    -- calls" - there is no tier on the other side of them.
    local floor_rec = FakeRec('guitar', { tier = 0, tier_position = 0.02 })
    DifficultyAnnotate(floor_rec)
    for _, w in ipairs(floor_rec.warnings) do
        Test.expect(w.kind ~= 'boundary', 'tier 0 should not warn about the tier below')
    end
    local ceil_rec = FakeRec('guitar', { tier = 6, tier_position = 0.98 })
    DifficultyAnnotate(ceil_rec)
    for _, w in ipairs(ceil_rec.warnings) do
        Test.expect(w.kind ~= 'boundary', 'tier 6 should not warn about the tier above')
    end
end)

Test.it('concentration fires above the instrument threshold, not below', function()
    local thr = RB_DIFFICULTY_MODELS.guitar.conc.solo_change_ratio
    Test.expect(thr and thr > 1, 'guitar should carry a marked-solo threshold')

    local quiet = FakeRec('guitar', { factors = { solo_change_ratio = thr * 0.9 } })
    DifficultyAnnotate(quiet)
    for _, w in ipairs(quiet.warnings) do
        Test.expect(w.kind ~= 'concentration', 'should not warn below the threshold')
    end

    local loud = FakeRec('guitar', { factors = { solo_change_ratio = thr * 1.5 } })
    DifficultyAnnotate(loud)
    local found = false
    for _, w in ipairs(loud.warnings) do
        if w.kind == 'concentration' then found = true end
    end
    Test.expect(found, 'should warn above the threshold')
end)

Test.it('vocals never gets a concentration note', function()
    -- It has neither a marked solo nor a gem density, so there is no passage to point at.
    -- The exporter must not have left a zero threshold behind that every chart exceeds.
    local c = RB_DIFFICULTY_MODELS.vocals.conc
    Test.expect(not c.density_ratio, 'vocals should carry no density-ratio threshold')
    Test.expect(not c.solo_change_ratio or c.solo_change_ratio <= 1.0,
        'vocals should carry no usable marked-solo threshold')
    local rec = FakeRec('vocals', { factors = { solo_change_ratio = 99, density_peak = 99 } })
    DifficultyAnnotate(rec)
    for _, w in ipairs(rec.warnings) do
        Test.expect(w.kind ~= 'concentration', 'vocals should never warn about concentration')
    end
end)

Test.it('out-of-range is reported and does not move the rank', function()
    local m = RB_DIFFICULTY_MODELS.keys
    local key, bound
    for _, k in ipairs(m.keys) do
        if m.bounds[k] then key, bound = k, m.bounds[k] break end
    end
    local rec = FakeRec('keys', { factors = { [key] = bound.max * 2 + 1 } })
    DifficultyAnnotate(rec)
    local found
    for _, w in ipairs(rec.warnings) do
        if w.kind == 'range' then found = w.text end
    end
    Test.expect(found, 'expected an out-of-range warning for ' .. key)
    Test.expect(found:find('extrapolation'), 'should say the suggestion is an extrapolation')
    -- Advisory only: the same factors must predict the same rank with or without the note.
    local a = DifficultyPredictRank(m, rec.factors)
    local b = DifficultyPredictRank(m, rec.factors)
    Test.expect(a == b, 'the warning must not change the prediction')
end)

Test.it('says when playing time was inferred rather than authored', function()
    local rec = FakeRec('bass', { span_source = 'fallback_no_events' })
    DifficultyAnnotate(rec)
    local found
    for _, w in ipairs(rec.warnings) do if w.kind == 'spans' then found = true end end
    Test.expect(found, 'a fallback span source should be reported')

    local authored = FakeRec('bass', { span_source = 'anim' })
    DifficultyAnnotate(authored)
    for _, w in ipairs(authored.warnings) do
        Test.expect(w.kind ~= 'spans', 'authored playing states should produce no note')
    end
end)

Test.it('carries model maturity as both a badge and a sentence', function()
    local validated = FakeRec('guitar')
    DifficultyAnnotate(validated)
    Test.expect(validated.badge == nil, 'a validated model needs no badge')
    for _, w in ipairs(validated.warnings) do
        Test.expect(w.kind ~= 'maturity', 'a validated model needs no maturity note')
    end

    for inst, badge in pairs({ keys = 'Beta', real_keys = 'Experimental', vocals = 'Experimental' }) do
        local rec = FakeRec(inst)
        DifficultyAnnotate(rec)
        Test.expect(rec.badge == badge,
            ('%s badge is %s, expected %s'):format(inst, tostring(rec.badge), badge))
        local found
        for _, w in ipairs(rec.warnings) do if w.kind == 'maturity' then found = true end end
        Test.expect(found, inst .. ' should carry a maturity sentence')
    end
end)

Test.it('never shows a confidence percentage', function()
    -- The fitted regressions produce no calibrated per-song probability, and tier-band
    -- position is a different quantity that would be read as one.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local rec = FakeRec(inst, { tier_position = 0.05, span_source = 'fallback_no_events' })
        DifficultyAnnotate(rec)
        for _, w in ipairs(rec.warnings) do
            Test.expect(not w.text:lower():find('confiden'),
                inst .. ' warning mentions confidence: ' .. w.text)
            Test.expect(not w.text:find('%d%d%% likely'), inst .. ' warning implies a probability')
        end
    end
end)

Test.it('describes where in the tier band the suggestion sits', function()
    Test.expect(DifficultyPositionText(0.05):find('bottom'), '0.05 should read as near the bottom')
    Test.expect(DifficultyPositionText(0.50):find('middle'), '0.50 should read as the middle')
    Test.expect(DifficultyPositionText(0.95):find('top'),    '0.95 should read as near the top')
    Test.expect(DifficultyPositionText(nil) == nil, 'no position means no text')
end)

Test.section('model artifact - concentration thresholds')

Test.it('concentration thresholds exist where the chart can express concentration', function()
    -- Measured per instrument on purpose. Bass and drums never mark a solo (pitch 103),
    -- so only the density-ratio branch can fire there; vocals has neither column and gets
    -- no concentration note at all.
    for _, inst in ipairs({ 'guitar', 'bass', 'drum', 'keys', 'real_keys' }) do
        local c = RB_DIFFICULTY_MODELS[inst].conc
        Test.expect(c.density_ratio and c.density_ratio > 1,
            inst .. ': no usable peak/average density threshold')
    end
    local g = RB_DIFFICULTY_MODELS.guitar.conc
    Test.expect(g.solo_change_ratio and g.solo_change_ratio > 1.5,
        'guitar should have a marked-solo threshold well above 1')
    -- Bass and drums: the column exists but is constant 1.0, so a threshold of 1 would
    -- fire on every chart. The explanation layer must not use it there.
    for _, inst in ipairs({ 'bass', 'drum' }) do
        local c = RB_DIFFICULTY_MODELS[inst].conc
        Test.expect(not c.solo_change_ratio or c.solo_change_ratio <= 1.0,
            inst .. ' unexpectedly has marked solos - the no-solo assumption changed')
    end
end)
