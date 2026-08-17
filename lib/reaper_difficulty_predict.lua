-- Applying a frozen difficulty model to a scored chart.
--
-- PURE: no r.*, no S, no ctx. The models themselves are the generated data table in
-- lib/reaper_difficulty_models.lua; this is the (unchanging) code that reads one. They
-- are separate files on purpose - the data is rewritten by
-- dev/calibration/export_production_models.lua on every refit, and regenerating logic
-- alongside data is how a generator ends up owning behaviour nobody reviews.
--
-- The two names are one letter apart on purpose too: `_models` is what was measured,
-- `_predict` is what to do with it. Nothing else should ever apply a model by hand -
-- the coefficients are in STANDARDIZED units and mean nothing applied to raw factors.
--
-- Requires (globals): nothing. RB_DIFFICULTY_MODELS is passed in, not read from _G, so
-- the parity test can drive a freshly-computed model table that is not the shipped one.

----------------------------------------------------------------------
-- Target scales
--
-- Must match SCALES in dev/calibration/protocol.lua exactly. Kept as a small table here
-- rather than imported, because protocol.lua is dev-only and the product may not load
-- it; the exporter asserts the two agree.
----------------------------------------------------------------------

DIFFICULTY_SCALE_INV = {
    ['rank']      = function(v) return v end,
    ['log(rank)'] = function(v) return math.exp(v) end,
}

-- Ordered factor values for a model, read out of a flat factor table by name.
--
-- Returns values, missing - `missing` names the first factor the chart did not produce,
-- which is a bug in the caller rather than a property of the chart: every key a model
-- names is a column ScoreChart or ScoreVocalChart always emits. Reported rather than
-- defaulted to zero, because a silent zero on a standardized column is not a neutral
-- value - it is whatever (0 - mean)/sd happens to be, often several sd from the centre.
--
-- The origin flags are the exception and are supplied here, always 0: they are
-- training-time indicators (one per auxiliary corpus origin, named is_<origin>), and
-- every product prediction is made on the RB3 scale. Matched by the `is_` prefix rather
-- than by name, so adding an origin to the calibration harness needs no change here.
function DifficultyModelInputs(model, factors)
    local out = {}
    for i, key in ipairs(model.keys) do
        if key:match('^is_') then
            out[i] = 0
        else
            local v = factors[key]
            if type(v) ~= 'number' then return nil, key end
            out[i] = v
        end
    end
    return out
end

-- Predicted rank for one chart.
--
-- Returns rank, clamped, raw_rank:
--   rank      the number to show, clamped to the observed training rank range
--   clamped   true when the clamp actually moved it, so a caller can say so
--   raw_rank  the unclamped value, for tests and diagnostics
-- Or nil, error_key when a factor is missing.
--
-- CLAMPING IS THE LAST STEP AND APPLIES ONLY TO THE RANK. Individual factors are never
-- clamped before the fit: a chart outside the training range is an extrapolation, and
-- squashing its inputs would hide that while still producing a confident-looking number.
-- The rank clamp exists because a log-scale fit exponentiates, so one extreme input does
-- not merely overshoot - it produces a value that is not a rank at all (a bass chart
-- came back at 943 against a corpus spanning 135-488). Report the extrapolation as a
-- warning instead; see the out-of-range check below.
function DifficultyPredictRank(model, factors)
    local xs, missing = DifficultyModelInputs(model, factors)
    if not xs then return nil, missing end

    local y = model.intercept
    for j = 1, #model.coefs do
        y = y + model.coefs[j] * ((xs[j] - model.mean[j]) / model.sd[j])
    end

    local inv = DIFFICULTY_SCALE_INV[model.scale]
    if not inv then return nil, 'scale:' .. tostring(model.scale) end
    local raw = inv(y)

    local rank = raw
    if rank < model.rank_lo then rank = model.rank_lo end
    if rank > model.rank_hi then rank = model.rank_hi end
    return rank, (rank ~= raw), raw
end

-- How unusual each of a model's factors is for this chart, in training standard
-- deviations. Drives the "notable properties" the suggestion explains itself with, so
-- the explanation describes the CHART rather than reciting regression coefficients.
--
-- Returns an array of { key, value, z, mean, sd }, in model factor order, skipping the
-- is_<origin> flags (training indicators, not chart properties).
function DifficultyFactorZ(model, factors)
    local out = {}
    for j, key in ipairs(model.keys) do
        if not key:match('^is_') then
            local v = factors[key]
            if type(v) == 'number' then
                local sd = model.sd[j]
                out[#out + 1] = {
                    key = key, value = v, mean = model.mean[j], sd = sd,
                    z = (sd > 0) and ((v - model.mean[j]) / sd) or 0,
                }
            end
        end
    end
    return out
end

-- Factors sitting outside the range the model was fitted over. The rank clamp hides
-- exactly this case - a clamped prediction looks ordinary - so it has to be reported
-- separately or an author is never told the model is extrapolating.
--
-- Returns an array of { key, value, lo, hi, side }, in model factor order.
function DifficultyOutOfRange(model, factors)
    local out = {}
    for _, key in ipairs(model.keys) do
        local b = not key:match('^is_') and model.bounds and model.bounds[key]
        local v = factors[key]
        if b and type(v) == 'number' then
            if v < b.min then
                out[#out + 1] = { key = key, value = v, lo = b.min, hi = b.max, side = 'below' }
            elseif v > b.max then
                out[#out + 1] = { key = key, value = v, lo = b.min, hi = b.max, side = 'above' }
            end
        end
    end
    return out
end
