-- Score a filled blinded rating worksheet against the official ranks and the model.
--
--     lua dev/calibration/score_human_ratings.lua [instrument]
--
-- Reads <inst>_rating_worksheet.txt (your answers) and <inst>_rating_key.txt (what they
-- were), both written by write_rating_worksheet.lua. Prints to stdout; writes nothing.
--
-- ---------------------------------------------------------------------------
-- THE ANALYSIS, PRE-REGISTERED
--
-- Written before any rating existed, because a study whose read-out is chosen after the
-- answers arrive is the same selection problem the whole protocol exists to prevent - and
-- this one is unusually easy to fool yourself with, since the hypothesis is flattering to
-- the model.
--
-- THE QUESTION. On charts where the model and Harmonix disagree, does a human who knows
-- the game side with the model or with Harmonix?
--
-- THE THREE NUMBERS THAT ANSWER IT, in the order they must be read:
--
--   1. SCALE OFFSET, from the CONTROLS ONLY. Mean signed (human - official) over charts
--      the model got right. This is the rater's personal calibration, and it is measured
--      first because everything else is read relative to it. If the controls come back at
--      -1.0, the rater simply rates a tier low, and a -1.0 on the misses says nothing at
--      all.
--
--   2. EXCESS DISAGREEMENT ON THE MISSES. Mean signed (human - official) over the misses,
--      MINUS the control offset. This is the quantity of interest. Zero means the rater
--      treats missed charts exactly like any other chart, and the official ranks are fine
--      - the model is simply wrong. Strongly negative means the rater declines to call
--      those charts as hard as Harmonix did, in a way not explained by their own scale.
--
--   3. WHOSE SIDE, per chart. On each miss, is the human tier closer to the official tier
--      or to the model's? Reported as a count, with ties named separately. This is the
--      question in its bluntest form and it does not depend on any mean.
--
-- WITHIN-TIER, TOO. The draw puts both groups at official tiers 5 and 6, so 1 and 2 are
-- also computed inside each tier. A whole-sample offset can be a tier effect in disguise
-- when the two groups sit at different tiers, and here they deliberately do not.
--
-- WHAT WOULD COUNT AS SUPPORT FOR THE LABEL HYPOTHESIS, declared now:
--
--   * excess disagreement on the misses of at least ONE FULL TIER, negative, AND
--   * the human siding with the model on a clear majority of misses, AND
--   * the control offset being small enough that the first number is not just scale.
--
-- Anything less is "interesting, not settled". Note the sample is 20 misses: even a clean
-- result here is one rater on one instrument, and the honest ceiling on this study is
-- "worth acting on" rather than "established".
--
-- WHAT HAPPENS NEXT IN EITHER DIRECTION, also declared now, so neither outcome gets
-- reinterpreted into whatever is convenient:
--
--   * SUPPORTED -> the endpoint gate is partly measuring label noise on vocals, and the
--     honest response is to say so in the README and reconsider what the endpoint bar
--     means for this instrument. It is NOT a licence to add these songs to
--     weirdly_scored.lua: that file's bar is "corrupt, not unfair", and a rating we
--     disagree with is exactly what it refuses.
--   * NOT SUPPORTED -> the vocal under-prediction is a modelling failure after all, the
--     label-probe hypothesis in run_label_probes_offline.lua is weakened, and hunting
--     vocal factors is back on.
--
-- WHAT THIS CANNOT DO. The misses are selected ON MODEL ERROR, so no accuracy rate over
-- them means anything, and none is printed. Do not compute one from the per-chart table
-- either; it would be a rate over a sample chosen for being wrong.
-- ---------------------------------------------------------------------------

local _script = (arg and arg[0]) or 'dev/calibration/score_human_ratings.lua'
-- Two invocations to support: from the repo root, where arg[0] carries dev/calibration/,
-- and from this directory, where it is a bare filename and the cwd is already right.
-- Probing for a sibling is what tells the two apart; assuming the repo root silently
-- looked for dev/calibration/dev/calibration/ and reported a missing worksheet.
local _dir = _script:match('^(.+[/\\])')
if not _dir then
    _dir = io.open('protocol.lua', 'r') and './' or 'dev/calibration/'
end
local INST    = arg and arg[1] or 'vocals'

local ws_path  = _dir .. INST .. '_rating_worksheet.txt'
local key_path = _dir .. INST .. '_rating_key.txt'

----------------------------------------------------------------------
-- Read the filled worksheet
----------------------------------------------------------------------

-- PARSING WHAT A HUMAN ACTUALLY WRITES IN A BOX.
--
-- The first version of this took the first digit it found, which is the worst possible
-- behaviour: "3 or close 4" scored as 3, "! I think this was Impossible tier" vanished
-- without a word, and both looked like clean data afterwards. A rating study that
-- misreads its own answers is worse than no study, because the error is invisible.
--
-- So: collect every tier-sized number in the box and decide from the set.
--   one number            that is the rating
--   two ADJACENT numbers  the midpoint - "3 or 4" is 3.5, and a genuine between-two
--                         answer carries more information than a forced coin flip
--   anything else         REFUSED and printed, never guessed at
--
-- Free text alongside the number is fine and expected. The risk is a stray digit inside
-- a comment, which cannot be fully solved by pattern matching - so every row that was
-- read as anything other than a bare single number is echoed back for eyeballing.
local answers, known, hedged, refused, flagged_blank = {}, {}, {}, {}, {}
do
    local f = io.open(ws_path, 'r')
    if not f then
        io.write(('No worksheet at %s.\n'):format(ws_path))
        io.write('Generate one:  lua dev/calibration/write_rating_worksheet.lua '
                 .. INST .. '\n')
        os.exit(1)
    end
    for line in f:lines() do
        local id, body = line:match('^%s*(%u%d%d)%s+%S+%s+tier%s*%[(.-)%]')
        if id then
            local knew = body:find('!', 1, true) ~= nil
            if knew then known[id] = true end

            local nums = {}
            for tok in body:gmatch('%d+%.?%d*') do
                local v = tonumber(tok)
                -- Only tier-sized values are candidates; a "12" in a comment is not a
                -- tier and dropping it is right. A "5" in a comment is indistinguishable
                -- from a rating, which is why the echo below exists.
                if v and v >= 0 and v <= 6 then nums[#nums + 1] = v end
            end

            if #nums == 1 then
                answers[id] = nums[1]
                if nums[1] % 1 ~= 0 or body:match('^%s*%d%s*$') == nil then
                    -- Not a bare single digit: worth showing back.
                    if body:match('^%s*%d%s*$') == nil then
                        hedged[#hedged + 1] = { id = id, raw = body, as = nums[1] }
                    end
                end
            elseif #nums == 2 and math.abs(nums[1] - nums[2]) == 1 then
                answers[id] = (nums[1] + nums[2]) / 2
                hedged[#hedged + 1] = { id = id, raw = body, as = answers[id] }
            elseif #nums == 0 then
                if knew then flagged_blank[#flagged_blank + 1] = id end
            else
                refused[#refused + 1] = { id = id, raw = body }
            end
        end
    end
    f:close()
end

local n_ans = 0
for _ in pairs(answers) do n_ans = n_ans + 1 end
if n_ans == 0 then
    io.write('No ratings found in the worksheet - nothing to score.\n')
    io.write('Write a tier number inside each [   ] and run this again.\n')
    os.exit(1)
end

----------------------------------------------------------------------
-- Read the key
----------------------------------------------------------------------

local key, order = {}, {}
do
    local f = io.open(key_path, 'r')
    if not f then
        io.write(('No key at %s.\n'):format(key_path))
        os.exit(1)
    end
    for line in f:lines() do
        local id, name, group, ot, orank, mt, mr =
            line:match('^(%u%d%d)%s+(%S+)%s+(%a+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)')
        if id then
            key[id] = { name = name, group = group,
                        off_t = tonumber(ot), off_r = tonumber(orank),
                        mdl_t = tonumber(mt), mdl_r = tonumber(mr) }
            order[#order + 1] = id
        end
    end
    f:close()
end
if #order == 0 then
    io.write('Could not parse the key.\n')
    os.exit(1)
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------

local function Mean(t)
    if #t == 0 then return nil end
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    return s / #t
end

io.write(('HUMAN RATING STUDY - %s\n'):format(INST:upper()))
io.write('=====================================\n\n')
io.write(('%d of %d charts rated'):format(n_ans, #order))
local n_known = 0
for id in pairs(known) do if answers[id] then n_known = n_known + 1 end end
if n_known > 0 then
    io.write((', %d marked as already known'):format(n_known))
end
io.write('.\n\n')

-- Everything the parser had to interpret, before any analysis. If a comment's stray digit
-- was read as a rating, this is where it becomes visible - and it is printed first
-- deliberately, so it is seen before the numbers that depend on it.
if #hedged > 0 then
    io.write(('HOW %d NON-OBVIOUS ENTRIES WERE READ - check these before trusting the rest\n')
        :format(#hedged))
    for _, h in ipairs(hedged) do
        io.write(('   %s  "%s"  ->  %.1f\n'):format(h.id, (h.raw:gsub('^%s+', '')
            :gsub('%s+$', '')), h.as))
    end
    io.write('\n')
end
if #refused > 0 then
    io.write(('%d ENTRIES COULD NOT BE READ and are excluded. Fix or blank them:\n')
        :format(#refused))
    for _, x in ipairs(refused) do
        io.write(('   %s  "%s"\n'):format(x.id, (x.raw:gsub('^%s+', ''):gsub('%s+$', ''))))
    end
    io.write('   (a rating must be one tier, or two adjacent ones like "3 or 4")\n\n')
end
if #flagged_blank > 0 then
    io.write(('%d rows carry a "!" note but no rating of your own: %s\n')
        :format(#flagged_blank, table.concat(flagged_blank, ' ')))
    io.write('   Recognising a song is not judging it - neither remembering the official\n')
    io.write('   rank nor spotting it in our own residual reports is a rating.\n')
    io.write('   These count as unrated until a number is written in.\n\n')
end

-- Gather, splitting the remembered ones out: they are not blind and are reported apart
-- rather than dropped, so the effect of excluding them is visible instead of assumed.
local groups = { miss = {}, control = {} }
local blind  = { miss = {}, control = {} }
local by_tier = {}
for _, id in ipairs(order) do
    local k, a = key[id], answers[id]
    if k and a then
        local diff = a - k.off_t
        table.insert(groups[k.group], { id = id, k = k, a = a, diff = diff })
        if not known[id] then table.insert(blind[k.group], diff) end
        by_tier[k.off_t] = by_tier[k.off_t] or { miss = {}, control = {} }
        table.insert(by_tier[k.off_t][k.group], diff)
    end
end

local function Diffs(list)
    local out = {}
    for _, x in ipairs(list) do out[#out + 1] = x.diff end
    return out
end

io.write('1. YOUR SCALE, from the CONTROLS - charts the model got right\n')
local c_all   = Mean(Diffs(groups.control))
local c_blind = Mean(blind.control)
if c_all then
    io.write(('   mean (you - official) over %d controls: %+.2f tiers\n')
        :format(#groups.control, c_all))
    if c_blind and #blind.control ~= #groups.control then
        io.write(('   blind only (%d): %+.2f\n'):format(#blind.control, c_blind))
    end
    io.write('   Everything below is read RELATIVE to this. A large value here means you\n')
    io.write('   and Harmonix use the scale differently, which is not a finding about the\n')
    io.write('   misses.\n')
else
    io.write('   no controls rated - the rest of this report cannot be interpreted\n')
end

io.write('\n2. THE MISSES\n')
local m_all = Mean(Diffs(groups.miss))
if m_all and c_all then
    io.write(('   mean (you - official) over %d misses: %+.2f tiers\n')
        :format(#groups.miss, m_all))
    io.write(('   EXCESS over your control offset:      %+.2f tiers\n'):format(m_all - c_all))
    local m_blind = Mean(blind.miss)
    if m_blind and c_blind and #blind.miss ~= #groups.miss then
        io.write(('   blind only: %+.2f excess\n'):format(m_blind - c_blind))
    end
else
    io.write('   not enough rated to compare\n')
end

io.write('\n3. WHOSE SIDE, per miss\n')
local with_model, with_official, tie = 0, 0, 0
for _, x in ipairs(groups.miss) do
    local dm = math.abs(x.a - x.k.mdl_t)
    local do_ = math.abs(x.a - x.k.off_t)
    if dm < do_ then with_model = with_model + 1
    elseif do_ < dm then with_official = with_official + 1
    else tie = tie + 1 end
end
io.write(('   closer to the MODEL: %d    closer to OFFICIAL: %d    equidistant: %d\n')
    :format(with_model, with_official, tie))

io.write('\n4. WITHIN OFFICIAL TIER - a whole-sample offset can be a tier effect\n')
io.write('   tier   n miss   mean       n ctrl   mean      excess\n')
for t = 0, 6 do
    local bt = by_tier[t]
    if bt and (#bt.miss > 0 or #bt.control > 0) then
        local mm, mc = Mean(bt.miss), Mean(bt.control)
        io.write(('    %d      %5d   %s      %5d   %s     %s\n'):format(t,
            #bt.miss,    mm and ('%+.2f'):format(mm) or '  -  ',
            #bt.control, mc and ('%+.2f'):format(mc) or '  -  ',
            (mm and mc) and ('%+.2f'):format(mm - mc) or '  -  '))
    end
end

io.write('\n5. PER CHART\n')
io.write(('   %-5s %-30s %-8s %5s %5s %5s\n')
    :format('id', 'shortname', 'group', 'you', 'off', 'model'))
local rows = {}
for _, g in ipairs({ 'miss', 'control' }) do
    for _, x in ipairs(groups[g]) do rows[#rows + 1] = x end
end
table.sort(rows, function(a, b) return a.diff < b.diff end)
for _, x in ipairs(rows) do
    -- "you" is %.1f because a between-two answer is a real half-tier, not a rounding
    -- artefact - and rounding it here would hide the hedge the parser reported above.
    io.write(('   %-5s %-30s %-8s %5.1f %5d %5d%s\n')
        :format(x.id, x.k.name, x.k.group, x.a, x.k.off_t, x.k.mdl_t,
                known[x.id] and '  (knew it)' or ''))
end

io.write('\nREAD 1 BEFORE 2. And note what is NOT here: no accuracy rate over these charts,\n')
io.write('because they were selected on model error and any such rate is meaningless. See\n')
io.write('the pre-registered analysis at the top of this file for what counts as support.\n')
