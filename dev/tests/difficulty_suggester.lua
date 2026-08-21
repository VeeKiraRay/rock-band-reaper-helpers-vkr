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
    -- With no model to ask, tier 0's bottom edge is rank 1: rank 0 means no part, not the
    -- easiest chart.
    local lo = select(1, TierBand('guitar', 0))
    Test.expect(lo == 1, 'tier 0 band should start at 1, got ' .. tostring(lo))

    -- Given one, it starts at the lowest rank that model can produce - see below for why.
    Test.expect(select(1, TierBand('guitar', 0, 605, 125)) == 125,
        'tier 0 should start at rank_lo when one is supplied')
    -- A rank_lo that would invert or empty the band is refused rather than trusted.
    Test.expect(select(1, TierBand('guitar', 0, 605, 999)) == 1,
        'a rank_lo above the tier-1 threshold should fall back to 1')
    Test.expect(select(1, TierBand('guitar', 0, 605, 0)) == 1,
        'a zero rank_lo should fall back to 1')
end)

Test.it('a floor-clamped Warmup chart reads as the bottom of the scale, not the top', function()
    -- THE REGRESSION THIS GUARDS. Tier 0's band used to run from rank 1, but no model can
    -- produce a rank below its own rank_lo - so a chart clamped to the floor drew most of
    -- the way up Warmup, one tick short of Apprentice, when what had actually happened was
    -- that it fell off the other END of the scale. When this was found, drums measured
    -- 1..124 against a floor of 120, i.e. 97%.
    --
    -- Asserted as the exact arithmetic rather than "> 0.8": how badly the old band
    -- misreports depends on where each model's floor happens to sit, and the low-end
    -- corpus moved every floor down (guitar 125 -> 75, so 0.97 -> 0.54). A magnitude
    -- threshold measures the corpus, not the fix.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m  = RB_DIFFICULTY_MODELS[inst]
        local t1 = RANK_TIER_THRESHOLDS[inst][1]
        if m.rank_lo < t1 then   -- only instruments whose floor really lands in Warmup
            local before = TierPosition(inst, m.rank_lo, m.rank_hi) or -1
            local after  = TierPosition(inst, m.rank_lo, m.rank_hi, m.rank_lo) or -1
            local unfixed = (m.rank_lo - 1) / (t1 - 1)
            Test.expect(math.abs(before - unfixed) < 1e-9,
                ('%s: the old band should read (rank_lo-1)/(t1-1) = %.4f, got %.4f')
                    :format(inst, unfixed, before))
            Test.expect(unfixed > 0.25,
                ('%s: floor sits only %.2f into Warmup - this test no longer demonstrates '
                 .. 'anything and should be revisited'):format(inst, unfixed))
            Test.expect(after < 1e-9,
                ('%s: a chart at the floor should read 0, got %.4f'):format(inst, after))
        end
    end
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

Test.it('reports factor z-scores for the explanation layer, skipping origin flags', function()
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
    -- 2 added `corr`; 3 allows more than one trailing origin flag. Bumping this
    -- deliberately is the point of the field: a stale artifact should fail loudly here
    -- rather than be read as a plausible but wrong model.
    Test.expect(RB_DIFFICULTY_MODELS_SCHEMA == 3,
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
        -- The origin flags occupy the trailing slots, in AUX_ORIGINS order, and nothing
        -- else may use the is_ prefix - the predictor supplies 0 for anything that does.
        local flags = AuxFlagKeys()
        for fi, flag in ipairs(flags) do
            local at = n - #flags + fi
            Test.expect(m.keys[at] == flag,
                ('%s: expected %s at trailing slot %d, got %s')
                    :format(inst, flag, fi, tostring(m.keys[at])))
        end
        for j = 1, n - #flags do
            Test.expect(not m.keys[j]:match('^is_'),
                inst .. ': ' .. m.keys[j] .. ' uses the reserved is_ prefix')
        end
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
        -- LOW-END CORPUS. Was 'baseline+ent_rel@attacks'; same three factors with the
        -- plain entropy rate instead of the relative one.
        bass      = { 'baseline+entropy',                 'log(rank)', 3  },
        -- TOP-END CORPUS. Was 'full_drum' / rank / 26. Drums re-selects on almost every
        -- rescore because the leader's margin sits just under the predeclared bar, so
        -- treat a failure here as "re-read the protocol report", not as a bug.
        -- ROUND 22. Was 'full_drum'. Same 26 factors, with the three PEAK columns swapped
        -- for their roll-lane twins: a 126/127 lane is leniency, so the old peaks read a
        -- free-play region as the chart's densest passage. makemesmile2 550 -> 362.
        drum      = { 'full_drum@noroll',                 'log(rank)', 26 },
        -- ROUND 16. Was 'primary+entropy_rel+complex_peak' / rank / 8. That model counted
        -- density in gems and needed chord_size_mean to divide chords back out, which
        -- charged ~28 rank per extra note of voicing - the same music as triads landed two
        -- tiers below its single-note version. This one counts attacks and has no chord
        -- factor, so voicing is not an input.
        -- KEYS TOP-UP moved the scale to rank; the factor list is unchanged.
        keys      = { 'primary+ent_rel+complex@attacks-chord', 'rank',      7 },
        real_keys = { 'primary+ent_rel@attacks',          'rank',      7  },
        -- ROUND 20. Was 'parts+tess+move'. Same 12 factors, with the linear vocal_parts
        -- term replaced by parts_3: one part and two measured 0.4 rank apart once the rest
        -- is held, so a linear count over-credited every two-part song. The free two-step
        -- control tied the single step exactly, which is what makes it a finding.
        vocals    = { 'parts+tess+move@parts_step3',      'log(rank)', 12 },
    }
    for inst, want in pairs(EXPECTED) do
        local m = RB_DIFFICULTY_MODELS[inst]
        Test.expect(m.candidate == want[1],
            ('%s: candidate is %q, expected %q'):format(inst, m.candidate, want[1]))
        Test.expect(m.scale == want[2],
            ('%s: scale is %q, expected %q'):format(inst, m.scale, want[2]))
        -- Plus the appended origin flag columns, one per auxiliary origin.
        local n_flags = #AuxFlagKeys()
        Test.expect(#m.keys == want[3] + n_flags,
            ('%s: %d factors, expected %d'):format(inst, #m.keys - n_flags, want[3]))
    end
end)

Test.it('maturity badges match the product status table', function()
    -- No instrument is 'validated', and this test is where that stays true. Guitar,
    -- bass and drum were 'validated' until 2026-08-21 on the strength of passing the
    -- release gate; the peer review that day pointed out the README already says these
    -- are development-set repeated-CV figures and that the reserved test partition has
    -- never been drawn. Nothing may claim 'validated' until one is spent - see the
    -- STATUS table in dev/calibration/export_production_models.lua.
    local EXPECTED = {
        guitar = 'beta', bass = 'beta', drum = 'beta',
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
            local is_dev = origin == 'rb3_dlc' and not IsWeirdlyScored(name, inst)
            local aux_w  = AuxWeight(origin)
            if ok and (is_dev or aux_w) then
                local flags = AuxFlagKeys()
                local fv = {}
                for j = 1, #m.keys - #flags do fv[j] = vals[m.keys[j]] end
                for fi, _ in ipairs(flags) do
                    fv[#m.keys - #flags + fi] =
                        (origin == PROTOCOL.AUX_ORIGINS[fi].origin) and 1 or 0
                end
                X[#X + 1]  = fv
                ys[#ys + 1] = scale_fwd(rank)
                ws[#ws + 1] = aux_w or 1.0
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
    -- 379-song corpus. The second number is every AUXILIARY row pooled (45 lego + 15
    -- rb2), not lego alone; keys and Pro Keys have none, both games predating the part.
    local EXPECTED = {
        guitar = { 327, 60 }, bass = { 330, 60 }, drum = { 328, 60 },
        vocals = { 328, 60 }, keys = { 266, 0 },  real_keys = { 266, 0 },
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
            -- One zero per origin flag, not a single one: the flags occupy the trailing
            -- slots, and a short vector makes ApplyFit read past the end of it.
            local n_flags = #AuxFlagKeys()
            local fv = {}
            for j = 1, #m.keys - n_flags do fv[j] = row.factors[m.keys[j]] end
            for k = #m.keys - n_flags + 1, #m.keys do fv[k] = 0 end
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
        if not k:match('^is_') then factors[k] = m.mean[j] end
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
    -- After the overrides, so a test that sets a fractional rank gets the matching
    -- integer. Mirrors SuggestOne: FLOOR, never round - a rounded integer can name a tier
    -- threshold the tier itself has not reached.
    if rec.rank_shown == nil and rec.rank then rec.rank_shown = math.floor(rec.rank) end
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
            if not k:match('^is_') then
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
        'expected no explanations, got: ' .. #rec.explanations .. ' shown')
    Test.expect(#rec.warnings == 0,
        'expected no warnings on a mid-tier average guitar chart, got ' .. #rec.warnings)
end)

Test.it('reports at most three properties, most unusual first', function()
    local rec = FakeRec('drum', { factors = {
        kick_density_peak = AtZ('drum', 'kick_density_peak', 3.0),
        hand_density_peak_noroll = AtZ('drum', 'hand_density_peak_noroll', 2.0),
        stick_size_mean   = AtZ('drum', 'stick_size_mean', 1.5),
        entropy_h2        = AtZ('drum', 'entropy_h2', 1.2),
    } })
    DifficultyAnnotate(rec)
    Test.expect(#rec.explanations == 3, 'expected 3 explanations, got ' .. #rec.explanations)
    Test.expect(rec.explanations[1].text == DIFFICULTY_FACTOR_INFO.kick_density_peak.high,
        'the most unusual factor should come first, got: ' .. rec.explanations[1].text)
    -- The full table is still available behind the expander - but NOT in this order: see
    -- the canonical-order test below.
    Test.expect(#rec.factor_rows == #RB_DIFFICULTY_MODELS.drum.keys - #AuxFlagKeys(),
        'factor rows should cover every model factor except the origin flags')
end)

Test.it('the details table is in a fixed order, not a per-song one', function()
    -- Sorting the rows by |z| made the table useless for the job it exists to do: two
    -- charts on the same instrument put a different factor in every position, so they
    -- could not be read side by side. The order is now a property of the instrument.
    local a = FakeRec('vocals', { factors = {
        syl_density_avg = AtZ('vocals', 'syl_density_avg', 3.0),
        notated_range   = AtZ('vocals', 'notated_range', 0.2),
    } })
    local b = FakeRec('vocals', { factors = {
        syl_density_avg = AtZ('vocals', 'syl_density_avg', 0.1),
        notated_range   = AtZ('vocals', 'notated_range', 2.8),
    } })
    DifficultyAnnotate(a)
    DifficultyAnnotate(b)

    local ka, kb = {}, {}
    for i, row in ipairs(a.factor_rows) do ka[i] = row.key end
    for i, row in ipairs(b.factor_rows) do kb[i] = row.key end
    Test.expect(table.concat(ka, ',') == table.concat(kb, ','),
        'two songs on one instrument must list the same rows in the same places:\n  '
        .. table.concat(ka, ',') .. '\n  ' .. table.concat(kb, ','))

    -- And that order is DIFFICULTY_FACTOR_ORDER's, not the model's declaration order.
    local last = 0
    local pos  = {}
    for i, k in ipairs(DIFFICULTY_FACTOR_ORDER) do pos[k] = i end
    for _, k in ipairs(ka) do
        Test.expect(pos[k] and pos[k] > last, 'row out of canonical order: ' .. k)
        last = pos[k] or last
    end
end)

Test.it('every factor appears in both the vocabulary and the display order', function()
    -- The two are maintained by hand in one file, and a factor missing from the order list
    -- would silently sort to the end of every details table rather than failing loudly.
    local missing_order, missing_info = {}, {}
    local seen = {}
    for _, k in ipairs(DIFFICULTY_FACTOR_ORDER) do
        seen[k] = true
        if not DIFFICULTY_FACTOR_INFO[k] then missing_info[#missing_info + 1] = k end
    end
    for k in pairs(DIFFICULTY_FACTOR_INFO) do
        if not seen[k] then missing_order[#missing_order + 1] = k end
    end
    table.sort(missing_order)
    Test.expect(#missing_order == 0,
        'in DIFFICULTY_FACTOR_INFO but not DIFFICULTY_FACTOR_ORDER: '
        .. table.concat(missing_order, ', '))
    Test.expect(#missing_info == 0,
        'in DIFFICULTY_FACTOR_ORDER but not DIFFICULTY_FACTOR_INFO: '
        .. table.concat(missing_info, ', '))
end)

Test.section('explanation deduplication')

Test.it('does not spend two slots on one observation', function()
    -- total_changes and playing_s correlate +0.81 on drums: whichever is more unusual,
    -- the other adds nothing. Before this, both took a slot while a genuinely different
    -- property waited behind them. (The pair used to be entropy_h2/entropy_h2_rel, which
    -- the current drum model no longer carries - the point is the mechanism, not the
    -- particular pair.)
    local rec = FakeRec('drum', { factors = {
        total_changes  = AtZ('drum', 'total_changes', 3.0),
        playing_s      = AtZ('drum', 'playing_s', 2.8),
        kick_density_peak = AtZ('drum', 'kick_density_peak', 2.0),
        hand_density_peak_noroll = AtZ('drum', 'hand_density_peak_noroll', 1.5),
    } })
    DifficultyAnnotate(rec)

    local keys = {}
    for _, e in ipairs(rec.explanations) do keys[#keys + 1] = e.key end
    Test.expect(#rec.explanations == 3,
        'the freed slot should be reused, got ' .. #rec.explanations .. ' bullets')

    local n_pair = 0
    for _, k in ipairs(keys) do
        if k == 'total_changes' or k == 'playing_s' then n_pair = n_pair + 1 end
    end
    Test.expect(n_pair == 1,
        'expected one of the correlated pair, got ' .. n_pair .. ': ' .. table.concat(keys, ', '))
    Test.expect(keys[1] == 'total_changes',
        'the more unusual of the pair should be the one kept')

    -- And the slot the suppressed one would have taken goes to the next distinct factor,
    -- rather than being dropped.
    Test.expect(keys[2] == 'kick_density_peak' and keys[3] == 'hand_density_peak_noroll',
        'the freed slot should go to the next distinct factor, got ' .. table.concat(keys, ', '))
end)

Test.it('keeps every factor in the details table, deduplicated or not', function()
    -- The bullets are a summary and may drop a restatement; the table is a complete list
    -- by definition, and a reader comparing two charts needs every row present.
    local rec = FakeRec('drum', { factors = {
        total_changes = AtZ('drum', 'total_changes', 3.0),
        playing_s     = AtZ('drum', 'playing_s', 2.8),
    } })
    DifficultyAnnotate(rec)
    Test.expect(#rec.factor_rows == #RB_DIFFICULTY_MODELS.drum.keys - #AuxFlagKeys(),
        'the details table must still cover every model factor')
end)

Test.it('falls back to the old behaviour when the artifact has no correlations', function()
    -- `corr` is optional: an older artifact must degrade to showing whatever is most
    -- unusual, not error and not silently produce an empty panel.
    local m = RB_DIFFICULTY_MODELS.drum
    local stripped = {}
    for k, v in pairs(m) do stripped[k] = v end
    stripped.corr = nil

    local rec = FakeRec('drum', { model = stripped, factors = {
        total_changes  = AtZ('drum', 'total_changes', 3.0),
        playing_s      = AtZ('drum', 'playing_s', 2.8),
        kick_density_peak = AtZ('drum', 'kick_density_peak', 2.0),
    } })
    DifficultyAnnotate(rec)
    Test.expect(#rec.explanations == 3, 'expected three bullets without corr')
    Test.expect(rec.explanations[1].key == 'total_changes'
            and rec.explanations[2].key == 'playing_s',
        'with no corr the pair should both appear, as before')
end)

Test.it('every shipped correlation is well formed', function()
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m = RB_DIFFICULTY_MODELS[inst]
        Test.expect(type(m.corr) == 'table', inst .. ' has no corr table')
        local named = {}
        for _, k in ipairs(m.keys) do named[k] = true end
        for pair, v in pairs(m.corr) do
            local a, b = pair:match('^(.-)|(.+)$')
            Test.expect(a and b, inst .. ': malformed pair key ' .. pair)
            Test.expect(named[a] and named[b],
                ('%s: %s names a factor this model does not use'):format(inst, pair))
            Test.expect(not a:match('^is_') and not b:match('^is_'),
                inst .. ': an origin flag can never be a bullet')
            Test.expect(type(v) == 'number' and v >= -1 and v <= 1,
                ('%s: %s = %s is not a correlation'):format(inst, pair, tostring(v)))
        end
    end
end)

Test.it('shipped correlations match the corpus they claim to describe', function()
    -- The artifact asserts a fact about corpus_scores.csv. Recomputing it here is what
    -- stops the two drifting - a rescore that moved a column would otherwise leave the
    -- explanation panel deduplicating against numbers that no longer hold.
    RequireCsv()
    if not _csv then return end

    local function Column(inst, key)
        local ci, ii, oi, ri = _csv.header[key], _csv.header['instrument'],
                               _csv.header['origin'], _csv.header['rank']
        local vals = {}
        for _, row in ipairs(_csv.rows) do
            if row[ii] == inst and row[oi] == 'rb3_dlc' and (tonumber(row[ri]) or 0) > 0 then
                vals[#vals + 1] = tonumber(row[ci]) or 0
            end
        end
        return vals
    end
    local function Corr(xs, ys)
        local n = #xs
        local mx, my = 0, 0
        for i = 1, n do mx, my = mx + xs[i], my + ys[i] end
        mx, my = mx / n, my / n
        local sxy, sxx, syy = 0, 0, 0
        for i = 1, n do
            local a, b = xs[i] - mx, ys[i] - my
            sxy, sxx, syy = sxy + a * b, sxx + a * a, syy + b * b
        end
        if sxx <= 0 or syy <= 0 then return 0 end
        return sxy / math.sqrt(sxx * syy)
    end

    local checked = 0
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        for pair, v in pairs(RB_DIFFICULTY_MODELS[inst].corr) do
            local a, b = pair:match('^(.-)|(.+)$')
            local got = Corr(Column(inst, a), Column(inst, b))
            Test.expect(math.abs(got - v) < 1e-9,
                ('%s %s: artifact %.6f, corpus %.6f'):format(inst, pair, v, got))
            Test.expect(math.abs(v) >= 0.70,
                ('%s %s was emitted below the threshold'):format(inst, pair))
            checked = checked + 1
        end
    end
    Test.expect(checked > 0, 'no correlations were checked - the field is missing entirely')
end)

Test.section('the text report')

-- A fully annotated drum record, which is the widest model and so the worst case for both
-- completeness and alignment.
local function ReportRec(over)
    local rec = FakeRec('drum', over)
    DifficultyAnnotate(rec)
    return rec
end

Test.it('a Big Rock Ending is reported once for the song, not once per chart', function()
    -- There is exactly one [coda] per song, so a BRE is a property of the project. The
    -- shares differ per instrument though - childintime is 12.9% on guitar and 0.0% on
    -- drums, because drums is the one part whose animations come from a separate note set
    -- and can legitimately carry an empty BRE.
    local recs = {
        FakeRec('guitar', { label = 'Guitar', bre_gem_frac = 0.129, bre_seconds = 8.2 }),
        FakeRec('bass',   { label = 'Bass',   bre_gem_frac = 0.060, bre_seconds = 8.2 }),
        FakeRec('drum',   { label = 'Drums',  bre_gem_frac = 0.000, bre_seconds = 8.2 }),
    }
    local notes = DifficultySongNotes(recs)
    Test.expect(#notes == 1, 'exactly one song-level note, got ' .. #notes)
    local t = notes[1].text
    Test.expect(t:find('Big Rock Ending', 1, true) ~= nil, 'names the thing')
    Test.expect(t:find('Guitar 13%', 1, true) ~= nil, 'lists the material share')
    Test.expect(t:find('Drums', 1, true) == nil,
        'an instrument below the threshold is left out rather than printed at 0%')

    -- And the per-chart warnings must NOT also carry it - that was the redundancy this
    -- replaced.
    for _, rec in ipairs(recs) do
        DifficultyAnnotate(rec)
        for _, w in ipairs(rec.warnings or {}) do
            Test.expect(w.kind ~= 'bre',
                (rec.instrument .. ': the BRE note should be song-level only'))
        end
    end
end)

Test.it('the BRE note claims nothing about difficulty in either direction', function()
    -- Measured, not stylistic: excluding BRE gems and refitting made the 18 corpus songs
    -- that have one WORSE (4 tier flips toward the official rank, 6 away), so wording that
    -- hinted the rank was inflated would contradict the evidence. It must also imply
    -- nothing about a part with no notes in the BRE.
    local recs = { FakeRec('guitar', { label = 'Guitar',
                                       bre_gem_frac = 0.129, bre_seconds = 8.2 }) }
    local t = DifficultySongNotes(recs)[1].text:lower()
    for _, banned in ipairs({ 'inflat', 'too high', 'too low', 'easier', 'harder',
                              'overrat', 'underrat', 'unfair', 'should be' }) do
        Test.expect(t:find(banned, 1, true) == nil,
            ('the note must not say %q - it makes a difficulty claim'):format(banned))
    end
    Test.expect(t:find('nothing is excluded', 1, true) ~= nil,
        'it should say plainly that the notes are counted')
end)

Test.it('no Big Rock Ending means no note at all', function()
    local recs = { FakeRec('guitar'), FakeRec('drum') }
    Test.expect(#DifficultySongNotes(recs) == 0, 'a song without a coda gets no note')
    Test.expect(#DifficultySongNotes({}) == 0, 'and neither does an empty list')
    -- A BRE whose every share is below the threshold still gets the general statement:
    -- once per song it is information, not noise.
    local small = { FakeRec('guitar', { bre_gem_frac = 0.022, bre_seconds = 4 }) }
    local n = DifficultySongNotes(small)
    Test.expect(#n == 1 and n[1].text:find('Gems inside it', 1, true) == nil,
        'the statement appears without a per-instrument list')
end)

Test.it('the song-level note reaches the pasteable report', function()
    -- It would otherwise be visible on screen and invisible to whoever the author pastes
    -- the report to, which is most of what the report is for.
    local recs = { FakeRec('guitar', { label = 'Guitar',
                                       bre_gem_frac = 0.129, bre_seconds = 8.2 }) }
    for _, rec in ipairs(recs) do DifficultyAnnotate(rec) end
    local text = DifficultyReportText(recs)
    Test.expect(text:find('Big Rock Ending', 1, true) ~= nil,
        'the report should carry the song-level note')
end)

Test.it('the rank it PRINTS never names a tier it did not reach', function()
    -- THE REGRESSION THIS EXISTS FOR. The card and the report each rounded the rank while
    -- the tier came from the unrounded value, so any prediction in [T-0.5, T) printed the
    -- tier below T beside the number T. A vocal chart at 217.6 rendered as
    -- "Solid (rank 218)" with 218 being the Moderate floor. The suite missed it because it
    -- checked tier and rank separately and never that the RENDERED pair agrees.
    --
    -- The invariant: every threshold is an integer, so flooring cannot cross one.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local th = RANK_TIER_THRESHOLDS[inst]
        for _, t in ipairs(th) do
            for _, d in ipairs({ -0.9, -0.5, -0.4, -0.1, 0, 0.1, 0.5 }) do
                local rank = t + d
                local shown = math.floor(rank)
                Test.expect(TierForRank(inst, shown) == TierForRank(inst, rank),
                    ('%s: rank %.1f shows %d, tier %s vs %s'):format(
                        inst, rank, shown,
                        TierName(TierForRank(inst, rank)),
                        TierName(TierForRank(inst, shown))))
            end
        end
    end
end)

Test.it('rounding the rank WOULD have named a tier it did not reach', function()
    -- The counter-test, so the one above cannot pass vacuously if flooring is ever
    -- "tidied" back into rounding. Half a rank below any threshold, rounding crosses it
    -- and the tier does not.
    local crossings = 0
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        for _, t in ipairs(RANK_TIER_THRESHOLDS[inst]) do
            local rank = t - 0.4
            if TierForRank(inst, math.floor(rank + 0.5)) ~= TierForRank(inst, rank) then
                crossings = crossings + 1
            end
        end
    end
    Test.expect(crossings > 0,
        'rounding should cross at least one threshold, or this test proves nothing')
end)

Test.it('the pasteable report prints the floored rank, not a rounded one', function()
    -- Two call sites printed the rank independently and drifted; both now read
    -- rec.rank_shown. This drives the REPORT with the exact value from the bug report -
    -- a vocal chart just under the Moderate floor of 218 - so reverting that site to a
    -- local round() fails here rather than in a screenshot months later. The card is
    -- ImGui and cannot be driven from these tests, but it reads the same field.
    local rec = FakeRec('vocals', { rank = 217.6, tier = 2, tier_name = 'Solid' })
    Test.expect(rec.rank_shown == 217,
        'rank_shown should floor 217.6 to 217, got ' .. tostring(rec.rank_shown))
    DifficultyAnnotate(rec)
    local text = DifficultyReportText({ rec })
    Test.expect(text:find('rank 217', 1, true) ~= nil,
        'the report should print the floored rank')
    Test.expect(text:find('rank 218', 1, true) == nil,
        'the report must not round up to 218, which is the Moderate floor this chart '
        .. 'did not reach')
    -- And the tier it prints beside that number is the one the raw rank actually earns.
    Test.expect(TierForRank('vocals', 217.6) == 2,
        '217.6 is Solid, so "Solid (rank 217)" is the honest pair')
end)

Test.it('lists every factor of every model exactly once', function()
    -- THE REGRESSION THIS EXISTS FOR. The hand-copied drum table that prompted the copy
    -- button was missing anchor_frac, out of 26 rows. A report that silently drops one is
    -- worse than no report, because the reader cannot tell.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local rec = FakeRec(inst)
        DifficultyAnnotate(rec)
        local text = DifficultyReportText({ rec })
        for _, k in ipairs(RB_DIFFICULTY_MODELS[inst].keys) do
            if not k:match('^is_') then
                local label = DIFFICULTY_FACTOR_INFO[k].label
                local n = select(2, text:gsub(label:gsub('%p', '%%%0'), ''))
                Test.expect(n >= 1, ('%s: %s (%s) is missing from the report')
                    :format(inst, k, label))
            end
        end
    end
end)

Test.it('marks a measurement no reference song reached, and only that one', function()
    local m = RB_DIFFICULTY_MODELS.drum
    local key, bound
    for _, k in ipairs(m.keys) do
        if m.bounds[k] then key, bound = k, m.bounds[k] break end
    end
    local rec = ReportRec({ factors = { [key] = bound.max * 2 + 1 } })
    local text = DifficultyReportText({ rec })
    Test.expect(text:find('above any reference song', 1, true) ~= nil,
        'an out-of-range measurement should be marked')
    local n = select(2, text:gsub('any reference song', ''))
    Test.expect(n == 1, 'only the out-of-range row should be marked, got ' .. n)
end)

Test.it('reports the uncapped score only when the rank was pinned', function()
    local m = RB_DIFFICULTY_MODELS.drum
    local pinned = ReportRec({ clamped = true, raw_rank = m.rank_lo - 40, rank = m.rank_lo })
    Test.expect(DifficultyReportText({ pinned }):find('uncapped', 1, true) ~= nil,
        'a pinned rank should report the number the clamp replaced')

    local ordinary = ReportRec({})
    Test.expect(DifficultyReportText({ ordinary }):find('uncapped', 1, true) == nil,
        'an unclamped rank has no uncapped score to report')
end)

Test.it('keeps a block for a part that could not be scored', function()
    local text = DifficultyReportText({
        { instrument = 'keys', label = 'Keys', ok = false, reason = 'PART KEYS is muted' } })
    Test.expect(text:find('Keys', 1, true) ~= nil, 'the instrument should still appear')
    Test.expect(text:find('PART KEYS is muted', 1, true) ~= nil,
        'the reason is usually the whole answer and must survive into the report')
end)

Test.it('names the artifact and the model behind every number', function()
    -- The keys model changed twice in one week. A report pasted into a discussion has to be
    -- identifiable as pre- or post-change without anyone having to remember.
    local rec = ReportRec({})
    local text = DifficultyReportText({ rec })
    Test.expect(text:find('schema ' .. tostring(RB_DIFFICULTY_MODELS_SCHEMA), 1, true) ~= nil,
        'the header should name the artifact schema')
    Test.expect(text:find(RB_DIFFICULTY_MODELS.drum.candidate, 1, true) ~= nil,
        'each block should name the candidate it was scored with')
    Test.expect(text:find(RB_DIFFICULTY_MODELS.drum.scale, 1, true) ~= nil,
        'each block should name the target scale')
end)

Test.it('stays aligned, which is the only thing this format has to do', function()
    -- Two instruments in one report: the columns are measured across ALL blocks, so a
    -- narrow model must not print its table at a different width from a wide one.
    local a = FakeRec('drum');   DifficultyAnnotate(a)
    local b = FakeRec('vocals'); DifficultyAnnotate(b)
    local text = DifficultyReportText({ a, b })

    local sd_col
    for line in text:gmatch('[^\n]+') do
        local at = line:find('%s[-+]%d%.%d sd')
        if at then
            if sd_col then
                Test.expect(at == sd_col,
                    ('the sd column moved from %d to %d on: %s'):format(sd_col, at, line))
            end
            sd_col = at
        end
    end
    Test.expect(sd_col ~= nil, 'no factor rows were produced at all')

    Test.expect(text:find('\t') == nil, 'tabs do not survive being pasted; use spaces')
    for line in text:gmatch('[^\n]+') do
        Test.expect(not line:find('%s$'),
            'trailing whitespace shows as ragged lines when pasted: ' .. line)
    end
end)

Test.it('returns usable text when there is nothing to report', function()
    local text = DifficultyReportText({})
    Test.expect(type(text) == 'string' and #text > 0,
        'an empty list should still produce a header, not nil')
    Test.expect(DifficultyReportText(nil) ~= nil, 'nil should not error either')
end)

Test.section('the tier ruler')

Test.it('labels the band it is in and the one above it', function()
    -- Guitar tier 3 (Moderate) is 221..267, and what an author wants from the right-hand
    -- end is what the next tier costs - so it names the threshold above, not the band it
    -- is already in.
    local rec = FakeRec('guitar', { rank = 240, tier = 3, tier_position = 0.5 })
    DifficultyAnnotate(rec)
    local ru = rec.ruler
    Test.expect(ru ~= nil, 'a scored record should get a ruler')
    Test.expect(ru.lo == 221 and ru.hi == 267,
        ('band %s..%s'):format(tostring(ru.lo), tostring(ru.hi)))
    Test.expect(ru.lo_label == 'Moderate (221)', 'got ' .. ru.lo_label)
    Test.expect(ru.hi_label == 'Challenging (267)', 'got ' .. ru.hi_label)
    Test.expect(ru.pinned == nil, 'an unclamped rank should not be pinned')
end)

Test.it('names the model limit where there is no neighbouring tier', function()
    -- Nothing lies below Warmup or above Impossible, so those ends are labelled with what
    -- the tool can actually produce rather than with a tier that does not exist.
    local m = RB_DIFFICULTY_MODELS.guitar

    local low = FakeRec('guitar', { rank = m.rank_lo, tier = 0, tier_position = 0 })
    DifficultyAnnotate(low)
    Test.expect(low.ruler.lo_label == ('min %d'):format(m.rank_lo),
        'tier 0 left end should be the model floor, got ' .. low.ruler.lo_label)
    Test.expect(low.ruler.hi_label == 'Apprentice (139)', 'got ' .. low.ruler.hi_label)

    local high = FakeRec('guitar', { rank = m.rank_hi, tier = 6, tier_position = 1 })
    DifficultyAnnotate(high)
    Test.expect(high.ruler.lo_label == 'Impossible (409)', 'got ' .. high.ruler.lo_label)
    Test.expect(high.ruler.hi_label == ('max %d'):format(m.rank_hi),
        'tier 6 right end should be the observed maximum, got ' .. high.ruler.hi_label)
end)

Test.it('pins the marker to the end the rank was clamped against', function()
    -- A clamped rank is a limit, not a position, so the UI needs to know WHICH end to draw
    -- it hard against - drawing it somewhere along the band would claim a precision the
    -- clamp exists to deny.
    local m = RB_DIFFICULTY_MODELS.guitar

    local floored = FakeRec('guitar', { rank = m.rank_lo, raw_rank = m.rank_lo - 40,
                                        clamped = true, tier = 0, tier_position = 0 })
    DifficultyAnnotate(floored)
    Test.expect(floored.ruler.pinned == 'lo', 'got ' .. tostring(floored.ruler.pinned))

    local capped = FakeRec('guitar', { rank = m.rank_hi, raw_rank = m.rank_hi + 200,
                                       clamped = true, tier = 6, tier_position = 1 })
    DifficultyAnnotate(capped)
    Test.expect(capped.ruler.pinned == 'hi', 'got ' .. tostring(capped.ruler.pinned))
end)

Test.it('never describes a band the rank falls outside', function()
    -- The marker is drawn at lo + pos * (hi - lo), so a band that does not contain the
    -- rank would put it off the end of its own track.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local m = RB_DIFFICULTY_MODELS[inst]
        local mid = math.floor((m.rank_lo + m.rank_hi) / 2)
        for _, rank in ipairs({ m.rank_lo, mid, m.rank_hi }) do
            local tier = TierForRank(inst, rank)
            local rec  = FakeRec(inst, { rank = rank, tier = tier,
                tier_position = TierPosition(inst, rank, m.rank_hi, m.rank_lo) })
            DifficultyAnnotate(rec)
            local ru = rec.ruler
            Test.expect(ru and rank >= ru.lo and rank <= ru.hi,
                ('%s rank %d fell outside its own band %s..%s'):format(
                    inst, rank, tostring(ru and ru.lo), tostring(ru and ru.hi)))
            Test.expect(ru.pos >= 0 and ru.pos <= 1,
                ('%s rank %d gave position %.3f'):format(inst, rank, ru.pos))
        end
    end
end)

Test.it('has no ruler for a part that could not be scored', function()
    Test.expect(DifficultyRulerBand(nil) == nil, 'nil record')
    Test.expect(DifficultyRulerBand({ ok = false, reason = 'PART KEYS not found' }) == nil,
        'an unscored record should have no ruler to draw')
end)

Test.it('keeps the position wording for the ruler tooltip', function()
    -- It stopped being a line on the card - the ruler shows the same thing with numbers -
    -- but it is still the plain-language version, so it must survive as the tooltip.
    local rec = FakeRec('guitar', { rank = 300, tier = 3, tier_position = 0.5 })
    DifficultyAnnotate(rec)
    Test.expect(rec.position_text == 'around the middle of this tier',
        'got ' .. tostring(rec.position_text))
end)

Test.section('difficulty explanations')

Test.it('interval factors read the inverted way round', function()
    -- tight_p10 is a SPACING in quarter notes, so a low value is the hard direction. A
    -- naive high/low mapping would tell the author the chart is roomy when it is dense.
    local rec = FakeRec('guitar', { factors = { tight_p10 = AtZ('guitar', 'tight_p10', -2.5) } })
    DifficultyAnnotate(rec)
    Test.expect(rec.explanations[1].text == 'Long stretches of closely spaced changes',
        'low tight_p10 should read as closely spaced, got: ' .. tostring(rec.explanations[1].text))
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

Test.it('a pinned rank replaces the boundary note rather than adding to it', function()
    -- The ends of the scale sit near tier lines by coincidence - the drum floor is 120
    -- against a tier-1 threshold of 124 - so a clamped chart would otherwise always collect
    -- "near the upper tier boundary" as well. Both are true; only one is the point.
    local m = RB_DIFFICULTY_MODELS.drum
    local rec = FakeRec('drum', { clamped = true, raw_rank = m.rank_lo - 40,
                                  rank = m.rank_lo, tier = 0, tier_position = 0.97 })
    DifficultyAnnotate(rec)
    local kinds = {}
    for _, w in ipairs(rec.warnings) do kinds[w.kind] = (kinds[w.kind] or 0) + 1 end
    Test.expect(kinds.clamped == 1, 'expected the clamped note')
    Test.expect(kinds.boundary == nil,
        'a clamped rank should not also report a tier boundary')

    -- Unclamped, the same position still warns - the suppression is about the clamp, not
    -- about that position being uninteresting.
    local ordinary = FakeRec('drum', { tier = 3, tier_position = 0.97 })
    DifficultyAnnotate(ordinary)
    local seen = false
    for _, w in ipairs(ordinary.warnings) do
        if w.kind == 'boundary' then seen = true end
    end
    Test.expect(seen, 'an unclamped chart near a boundary should still warn')
end)

Test.it('a tooltip, where one exists, is a real explanation', function()
    -- TIPS ARE DELIBERATELY OPTIONAL. Requiring one per factor produced filler: tooltips
    -- describing the hidden number under a bullet that shows no number, and tooltips
    -- explaining game mechanics to the author who wrote the markers. "Many sustained
    -- notes" needs no gloss. So this checks quality, not coverage - a stub is worse than
    -- an absence, because an absent tooltip does not invite a hover that teaches nothing.
    local stubs = {}
    for k, info in pairs(DIFFICULTY_FACTOR_INFO) do
        if info.tip and #info.tip < 40 then stubs[#stubs + 1] = k end
    end
    table.sort(stubs)
    Test.expect(#stubs == 0, 'tooltips too short to explain anything: '
        .. table.concat(stubs, ', '))

    -- Every factor still needs its two sentences - those are the bullet itself.
    local missing = {}
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        for _, k in ipairs(RB_DIFFICULTY_MODELS[inst].keys) do
            local info = DIFFICULTY_FACTOR_INFO[k]
            if not k:match('^is_') and not (info and info.high and info.low) then
                missing[#missing + 1] = inst .. '.' .. k
            end
        end
    end
    Test.expect(#missing == 0, 'factors with no wording: ' .. table.concat(missing, ', '))

    -- And where there is a tip it has to reach the bullet, not just sit in the table.
    -- hand_density_peak_noroll is one of the factors that keeps one: "the busiest stretch with
    -- the kick taken out" is not recoverable from "Very fast hand passages".
    local rec = FakeRec('drum', { factors = {
        hand_density_peak_noroll = AtZ('drum', 'hand_density_peak_noroll', 3.0) } })
    DifficultyAnnotate(rec)
    Test.expect(rec.explanations[1].tip == DIFFICULTY_FACTOR_INFO.hand_density_peak_noroll.tip,
        'the bullet should carry its factor tip')
    local carried = false
    for _, row in ipairs(rec.factor_rows) do
        if row.key == 'hand_density_peak_noroll' then carried = row.tip ~= nil end
    end
    Test.expect(carried, 'detail rows should carry it too')
end)

Test.it('a pinned rank does not blame an out-of-range measurement for it', function()
    -- The clamp note used to append "most likely from very high average chord size", which
    -- asserts a cause the data does not support: out of range means UNUSUAL, not
    -- responsible. A near-empty keys chart really did carry the corpus's largest average
    -- chord size - a sustained two-note pad, unusual and easy for unrelated reasons - and
    -- the note read as "it is easy because its chords are large".
    local m = RB_DIFFICULTY_MODELS.keys
    local key, bound
    for _, k in ipairs(m.keys) do
        if m.bounds[k] then key, bound = k, m.bounds[k] break end
    end
    local rec = FakeRec('keys', {
        clamped = true, raw_rank = m.rank_lo - 40, rank = m.rank_lo,
        factors = { [key] = bound.max * 2 + 1 },
    })
    DifficultyAnnotate(rec)

    local n_clamped, text = 0, nil
    for _, w in ipairs(rec.warnings) do
        if w.kind == 'clamped' then n_clamped, text = n_clamped + 1, w.text end
        Test.expect(w.kind ~= 'range',
            'out-of-range should no longer be a card warning: ' .. w.text)
    end
    Test.expect(n_clamped == 1, 'expected exactly one clamped note, got ' .. n_clamped)
    Test.expect(not text:find('most likely'),
        'the clamped note must not attribute a cause: ' .. text)
    Test.expect(not text:find(DIFFICULTY_FACTOR_INFO[key].label),
        'the clamped note must not name a factor as the reason: ' .. text)
end)

Test.it('out-of-range shows on the factor row, not as a warning, and moves no rank', function()
    local m = RB_DIFFICULTY_MODELS.keys
    local key, bound
    for _, k in ipairs(m.keys) do
        if m.bounds[k] then key, bound = k, m.bounds[k] break end
    end
    local rec = FakeRec('keys', { factors = { [key] = bound.max * 2 + 1 } })
    DifficultyAnnotate(rec)

    for _, w in ipairs(rec.warnings) do
        Test.expect(w.kind ~= 'range', 'out-of-range should not warn on the card')
    end

    local marked
    for _, row in ipairs(rec.factor_rows) do
        if row.key == key then marked = row.out_of end
        -- Only the offending factor is flagged; the rest are in range.
        if row.key ~= key then
            Test.expect(row.out_of == nil, row.key .. ' should not be flagged')
        end
    end
    Test.expect(marked == 'above',
        ('%s should be flagged as above range, got %s'):format(key, tostring(marked)))

    local under = FakeRec('keys', { factors = { [key] = bound.min - math.abs(bound.min) - 1 } })
    DifficultyAnnotate(under)
    for _, row in ipairs(under.factor_rows) do
        if row.key == key then
            Test.expect(row.out_of == 'below', 'should flag below range, got ' .. tostring(row.out_of))
        end
    end

    -- Advisory only: flagging a row must not change what the model predicted.
    Test.expect(DifficultyPredictRank(m, rec.factors) == DifficultyPredictRank(m, rec.factors),
        'the flag must not change the prediction')
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

Test.it('carries model maturity as a badge, never as a per-chart warning', function()
    -- The maturity wording is a property of the MODEL, so as a warning line it would be
    -- the same sentence under every keys/Pro Keys/vocals result in every project. It rides
    -- on the badge tooltip instead; the warning list stays for things about THIS chart.
    --
    -- THE BADGE IS SWITCHED OFF FOR THE FIRST RELEASE - DifficultyAnnotate sets rec.badge
    -- to nil deliberately, to keep the card as plain as possible while the panel is being
    -- shown to authors for the first time. So this asserts the MAPPING rather than the
    -- annotated record: the wording and the status-to-badge table have to stay correct for
    -- the one-line change that turns it back on to be safe.
    -- Every model is annotated with no badge, because the feature switches them off -
    -- not because any of them is mature enough to need none. That distinction used to
    -- be blurred here by asserting it on guitar under the name `validated`; guitar is
    -- 'beta' now and no shipped model claims otherwise.
    local off = FakeRec('guitar')
    DifficultyAnnotate(off)
    Test.expect(off.badge == nil, 'badges are switched off, so no record may carry one')

    for inst, badge in pairs({
        guitar = 'Beta', bass = 'Beta', drum = 'Beta',
        keys = 'Beta', real_keys = 'Experimental', vocals = 'Experimental',
    }) do
        local status = RB_DIFFICULTY_MODELS[inst].status
        Test.expect(DIFFICULTY_STATUS_BADGE[status] == badge,
            ('%s (%s) maps to %s, expected %s'):format(
                inst, status, tostring(DIFFICULTY_STATUS_BADGE[status]), badge))
        Test.expect(DIFFICULTY_STATUS_NOTE[status] ~= nil,
            inst .. ' badge has no tooltip text to explain it')
    end

    -- No record of any maturity should reach the warning list.
    for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
        local rec = FakeRec(inst)
        DifficultyAnnotate(rec)
        for _, w in ipairs(rec.warnings) do
            Test.expect(w.kind ~= 'maturity',
                inst .. ' put model maturity in the per-chart warnings')
        end
    end
end)

Test.it('the reworded notes avoid jargon and say what the number means', function()
    -- These two were rewritten after review: "calibrated rank range" and "extrapolation"
    -- describe the statistics rather than the chart, and an author reading their own MIDI
    -- could not act on either.
    local m = RB_DIFFICULTY_MODELS.guitar
    local capped = FakeRec('guitar', { clamped = true, raw_rank = m.rank_hi + 200,
                                       rank = m.rank_hi })
    DifficultyAnnotate(capped)
    local text
    for _, w in ipairs(capped.warnings) do if w.kind == 'clamped' then text = w.text end end
    Test.expect(text, 'a clamped rank should be reported')
    Test.expect(text:find('as high as this tool can score'),
        'should say the tool ran out of scale: ' .. text)
    Test.expect(text:find(tostring(math.floor(m.rank_hi))), 'should name the bound value')
    -- Wording is for an author reading their own MIDI, so none of the machinery leaks.
    for _, jargon in ipairs({ 'calibrat', 'reference song', 'model', 'extrapolat' }) do
        Test.expect(not text:lower():find(jargon),
            ('should not say %q: %s'):format(jargon, text))
    end

    -- The floor case has to read the other way round rather than reusing one sentence.
    local floored = FakeRec('guitar', { clamped = true, raw_rank = m.rank_lo - 50,
                                        rank = m.rank_lo })
    DifficultyAnnotate(floored)
    for _, w in ipairs(floored.warnings) do if w.kind == 'clamped' then text = w.text end end
    Test.expect(text:find('as low as this tool can score'),
        'the floor case should read the other way round: ' .. text)
    Test.expect(text:find('judging for yourself'),
        'the floor case should hand the call back to the author: ' .. text)

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
