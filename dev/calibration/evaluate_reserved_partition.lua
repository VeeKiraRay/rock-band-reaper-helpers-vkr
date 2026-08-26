-- Grade the SHIPPED models on the reserved test partition. Run from the repo root:
--     lua dev/calibration/evaluate_reserved_partition.lua
--
-- ---------------------------------------------------------------------------
-- WHAT MAKES THIS DIFFERENT FROM EVERY OTHER NUMBER IN THIS PROJECT
--
-- Every figure the calibration produces is development-set repeated CV: the same rows
-- chose the candidate, tuned the ridge and reported the accuracy. Those figures are
-- honest about their own construction and they are still not confirmatory - the bound on
-- a selected model is optimistic by an unmeasured amount.
--
-- These rows are different. They were never walked, never fitted, never inspected as
-- residuals, and never influenced a factor, a scale or a threshold. That is what makes
-- the number below the first confirmatory evidence the project has ever had.
--
-- It is also why this can only be run meaningfully ONCE. Grading, adjusting, and grading
-- again turns a test set into a slow development set - the same selection inflation this
-- whole apparatus exists to avoid, arrived at one honest-looking step at a time.
--
-- SO: READ THE RESULT, WRITE IT DOWN, AND DO NOT TUNE AGAINST IT. If the models are then
-- changed for any reason, the number below describes the OLD models and must be relabelled
-- as such, not quietly carried forward.
--
-- ---------------------------------------------------------------------------
-- WHAT IS APPLIED
--
-- lib/reaper_difficulty_models.lua exactly as shipped, through the shipped predictor.
-- Nothing is refitted here. That matters: the question is not "how well can this factor
-- set do" but "how well does the artifact an author actually gets do on charts nobody
-- looked at".
--
-- Rows come from corpus_scores.csv under origin rb3_dlc_test - written there by
-- run_calibration_vkr.lua with SPEND_RESERVED_PARTITION set. If there are none, the
-- partition has not been spent and this says so rather than inventing an answer.
-- ---------------------------------------------------------------------------

local _script = (arg and arg[0]) or 'dev/calibration/evaluate_reserved_partition.lua'
local _dir = _script:match('^(.+[/\\])')
if not _dir then
    _dir = io.open('protocol.lua', 'r') and './' or 'dev/calibration/'
end
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root = _up(_up(_dir))
if _root == '' then _root = './' end
if not io.open(_root .. 'lib/reaper_difficulty_models.lua', 'r') then
    io.write('Could not locate the repo root. Run from the repository root.\n')
    os.exit(1)
end

r = { ShowConsoleMsg = function(s) io.write(s) end }
reaper = r
ctx = nil

dofile(_dir .. 'difficulty_score.lua')
dofile(_dir .. 'difficulty_score_vocals.lua')
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'protocol.lua')
dofile(_root .. 'lib/reaper_difficulty_predict.lua')
dofile(_root .. 'lib/reaper_difficulty_models.lua')

local TEST_ORIGIN = 'rb3_dlc_test'

----------------------------------------------------------------------
-- CSV
----------------------------------------------------------------------

local function Split(line)
    local out = {}
    for c in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = c end
    return out
end

local hdr, rows = {}, {}
do
    local f = io.open(_dir .. 'corpus_scores.csv', 'r')
    if not f then
        io.write('No corpus_scores.csv.\n')
        os.exit(1)
    end
    for i, n in ipairs(Split(f:read('l'))) do hdr[n] = i end
    for line in f:lines() do
        if line ~= '' then rows[#rows + 1] = Split(line) end
    end
    f:close()
end

local n_test_rows = 0
for _, t in ipairs(rows) do
    if t[hdr.origin] == TEST_ORIGIN then n_test_rows = n_test_rows + 1 end
end
if n_test_rows == 0 then
    io.write('No rows with origin ' .. TEST_ORIGIN .. ' in corpus_scores.csv.\n\n')
    io.write('The reserved partition has not been spent. That is the expected state\n')
    io.write('until it is deliberately scored - see SPEND_RESERVED_PARTITION in\n')
    io.write('run_calibration_vkr.lua, and the README before touching it.\n')
    os.exit(0)
end

----------------------------------------------------------------------
-- Grade
----------------------------------------------------------------------

io.write('RESERVED TEST PARTITION - CONFIRMATORY EVALUATION\n')
io.write('================================================\n\n')
io.write('Shipped models, applied unchanged, to rows never used for anything.\n')
io.write(('artifact schema %s, csv fingerprint %s\n\n')
    :format(tostring(RB_DIFFICULTY_MODELS_SCHEMA),
            tostring(RB_DIFFICULTY_MODELS_CSV_FINGERPRINT)))

io.write(('%-10s %5s %9s %9s %9s %9s %8s\n')
    :format('inst', 'n', 'pooled', 'lower', 'miss', 'ends', 'rho'))

local any = false
for _, inst in ipairs(RB_DIFFICULTY_MODEL_ORDER) do
    local model = RB_DIFFICULTY_MODELS[inst]
    local pred, act = {}, {}
    for _, t in ipairs(rows) do
        if t[hdr.origin] == TEST_ORIGIN and t[hdr.instrument] == inst then
            local rank = tonumber(t[hdr.rank])
            if rank and rank > 0 then
                local factors, ok = {}, true
                for _, k in ipairs(model.keys) do
                    -- Trailing origin indicators are not CSV columns; the product passes
                    -- zero for every one of them and so does this.
                    if hdr[k] then
                        local v = tonumber(t[hdr[k]])
                        if v == nil then ok = false else factors[k] = v end
                    end
                end
                if ok then
                    local p = DifficultyPredictRank(model, factors)
                    if p then
                        pred[#pred + 1] = p
                        act[#act + 1]   = rank
                    end
                end
            end
        end
    end

    if #pred == 0 then
        io.write(('%-10s %5d   (no usable rows)\n'):format(inst, 0))
    else
        any = true
        local pt, at = {}, {}
        local ok_n, miss_n, ep_ok, ep_n = 0, 0, 0, 0
        for i = 1, #pred do
            pt[i] = TierForRank(inst, pred[i])
            at[i] = TierForRank(inst, act[i])
            local dist = math.abs(pt[i] - at[i])
            if dist <= 1 then ok_n = ok_n + 1 end
            if dist >= 3 then miss_n = miss_n + 1 end
            if at[i] <= 1 or at[i] >= 5 then
                ep_n = ep_n + 1
                if dist <= 1 then ep_ok = ep_ok + 1 end
            end
        end
        local pooled = ok_n / #pred
        io.write(('%-10s %5d %8.2f%% %8.2f%% %8.2f%% %8s %+8.3f\n')
            :format(inst, #pred, pooled * 100,
                    WilsonLower(pooled, #pred, PROTOCOL.Z) * 100,
                    WilsonUpper(miss_n / #pred, #pred, PROTOCOL.Z) * 100,
                    (ep_n > 0) and ('%.2f%%'):format(ep_ok / ep_n * 100) or '   -',
                    Spearman(pred, act) or 0))
    end
end

if any then
    io.write('\nThese are OUT-OF-SAMPLE. Unlike every other figure in this project they were\n')
    io.write('not produced by the rows that chose the model, so the Wilson bound here is a\n')
    io.write('real confirmatory interval rather than an optimistic one.\n\n')
    io.write('The endpoint column has no bootstrap bound: the pack bootstrap resamples\n')
    io.write('out-of-fold residuals, which do not exist for rows that were never in a fold.\n')
    io.write('It is a point estimate over however many extreme charts the draw contained.\n\n')
    io.write('DO NOT TUNE AGAINST THESE NUMBERS. Grade once, record, stop. If the models\n')
    io.write('change afterwards, this result describes the OLD ones.\n')
end
