-- Generate a BLINDED human-rating worksheet, and the key that scores it.
--
--     lua dev/calibration/write_rating_worksheet.lua [instrument] [n_miss] [n_control]
--
-- Defaults to vocals, 20 misses, 20 controls.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS STUDY IS FOR
--
-- Three of the six models fail the release gate, and on vocals the failure is
-- concentrated at the top: the model places 1 chart at tier 6 against 20 that officially
-- sit there, and every one of the hardest charts is under-predicted by about 97 rank.
-- run_label_probes_offline.lua already argues why: Rock Band scores vocals by pitch CLASS,
-- so an octave-down performance still scores, and if Harmonix ranked the SONG rather than
-- the CHART then no chart-derived factor can ever close that gap.
--
-- That is a claim about the LABELS, and this is the cheapest honest test of it. A human
-- who knows the game rates the same charts blind. If a careful human also declines to call
-- those charts tier 6, the official ranks are carrying something the chart does not, and
-- the endpoint gate is partly measuring label noise rather than model error. If the human
-- agrees with Harmonix, the model is simply wrong and the hunt for vocal factors continues.
--
-- IT IS NOT AN ACCURACY MEASUREMENT AND CANNOT BE TURNED INTO ONE. The misses are selected
-- ON MODEL ERROR, so any rate computed over them is guaranteed to look bad and means
-- nothing. score_human_ratings.lua refuses to print one.
--
-- ---------------------------------------------------------------------------
-- WHY THERE ARE CONTROLS, AND WHY THEY ARE THE MOST IMPORTANT PART
--
-- Suppose the ratings come back a tier below official across the board. Two explanations
-- fit equally well:
--
--   * the official ranks are inflated at the extremes            <- the hypothesis
--   * the rater's personal scale simply sits lower than Harmonix's   <- boring
--
-- Nothing in a list of misses can separate those. So the worksheet also carries songs the
-- model got RIGHT, shuffled in and indistinguishable, matched as closely as the corpus
-- allows to the misses' official-tier distribution. Those measure the rater's own
-- calibration, and they are what make the misses interpretable at all.
--
-- Perfect matching is impossible by construction and that is itself the finding: at the
-- tiers where the model misses most, there are barely any songs it got right to draw a
-- control from. The achieved match is printed rather than quietly approximated.
--
-- ---------------------------------------------------------------------------
-- BLINDING
--
-- The worksheet carries the shortname and nothing else - no official rank, no official
-- tier, no model prediction, no indication of which rows are misses. Anchoring on a number
-- would make the answers worthless, and a rater cannot un-see one.
--
-- The key goes to a SEPARATE FILE. Discipline is on the human: do not open it until the
-- worksheet is filled in. Both files are tracked, because song shortnames are identifiers
-- rather than content and the study has to be auditable afterwards.
--
-- TWO KINDS OF CONTAMINATION, and the second is the one that bites. The rater is an RB3
-- author and may remember a song's official rating - that is anchoring on a number.
-- Worse, they may recognise a song from THIS PROJECT'S OWN worst-residual reports, which
-- print the official rank, the model's answer, and the fact that it was a miss. That
-- leaks GROUP MEMBERSHIP, which is the one thing blinding exists to protect.
--
-- Both are marked '!' and both are excluded from the blind-only figures. Neither is
-- dropped: a study that discards its inconvenient rows is choosing its own answer.
--
-- Measured on the first pass of the vocals sheet: 6 rows flagged, of which 4 were misses
-- and 2 were controls. So recognition is NOT a reliable indicator of group - wrong a
-- third of the time - and 16 misses against 18 controls survive fully blind, moving the
-- standard error on the miss mean from about 0.22 to 0.25 tiers. The design holds; the
-- leak is recorded rather than waved away.
-- ---------------------------------------------------------------------------

local _script = (arg and arg[0]) or 'dev/calibration/write_rating_worksheet.lua'
-- Two invocations to support: from the repo root, where arg[0] carries dev/calibration/,
-- and from this directory, where it is a bare filename and the cwd is already right.
-- Probing for a sibling is what tells the two apart.
local _dir = _script:match('^(.+[/\\])')
if not _dir then
    _dir = io.open('protocol.lua', 'r') and './' or 'dev/calibration/'
end
local _csv = _dir .. 'corpus_scores.csv'

if not io.open(_csv, 'r') then
    io.write(('Could not find %s. Run from the repository root.\n'):format(_csv))
    os.exit(1)
end

r = { ShowConsoleMsg = function(s) io.write(s) end }
reaper = r
ctx = nil

dofile(_dir .. 'difficulty_score.lua')
dofile(_dir .. 'difficulty_score_vocals.lua')
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')

local INST      = arg and arg[1] or 'vocals'
local N_MISS    = tonumber(arg and arg[2]) or 20
local N_CONTROL = tonumber(arg and arg[3]) or 20
-- Fixed so a regenerated worksheet is the same worksheet. Changing it after seeing a
-- draft would be choosing which songs to be tested on.
local SEED = 20260823

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
    local f = assert(io.open(_csv, 'r'))
    for i, n in ipairs(Split(f:read('l'))) do hdr[n] = i end
    for line in f:lines() do
        if line ~= '' then rows[#rows + 1] = Split(line) end
    end
    f:close()
end

local d = { feats = {}, ranks = {}, origins = {}, names = {}, packs = {} }
for _, t in ipairs(rows) do
    if t[hdr.instrument] == INST then
        local rank = tonumber(t[hdr.rank])
        local fv, ok = {}, rank ~= nil
        for j, k in ipairs(SCORE_FACTOR_KEYS) do
            local v = tonumber(t[hdr[k]])
            if v == nil then ok = false else fv[j] = v end
        end
        if ok then
            local n = #d.feats + 1
            d.feats[n], d.ranks[n] = fv, rank
            d.origins[n] = t[hdr.origin]
            d.names[n]   = t[hdr.shortname]
            d.packs[n]   = t[hdr.pack]
        end
    end
end

local pos = {}
for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

local target, aux = {}, {}
for i, o in ipairs(d.origins) do
    if o == 'rb3_dlc' then
        if not (WeirdlyScored and WeirdlyScored(d.names[i], INST)) then
            target[#target + 1] = i
        end
    elseif AuxWeight(o) then
        aux[#aux + 1] = i
    end
end
if #target < 40 then
    io.write(('Only %d rows for %s - not enough for a study.\n'):format(#target, INST))
    os.exit(1)
end

----------------------------------------------------------------------
-- The selected model's out-of-fold residuals
----------------------------------------------------------------------

-- Whichever candidate the protocol picks, taken from a live run rather than transcribed:
-- a worksheet built against a model that is no longer selected would be testing nothing.
local results = RunProtocol(d, target, aux, INST, pos)
local sel = SelectCandidate(results, INST)
if not sel then
    io.write('No candidate produced a result.\n')
    os.exit(1)
end
local resid = CandidateResiduals(d, target, aux, INST, pos, sel)
if not resid then
    io.write('No residuals.\n')
    os.exit(1)
end

----------------------------------------------------------------------
-- Pick misses and tier-matched controls
----------------------------------------------------------------------

-- resid arrives sorted worst-first, so the misses are simply the head of it.
local misses, pool = {}, {}
for _, x in ipairs(resid) do
    if #misses < N_MISS and x.dist >= 2 then
        misses[#misses + 1] = x
    elseif x.dist <= 1 then
        pool[#pool + 1] = x
    end
end
if #misses == 0 then
    io.write('No misses of two tiers or more - nothing to study.\n')
    os.exit(1)
end

-- Histogram of the misses' OFFICIAL tiers: what the controls should look like.
local want = {}
for _, x in ipairs(misses) do want[x.tier_act] = (want[x.tier_act] or 0) + 1 end

local by_tier = {}
for _, x in ipairs(pool) do
    by_tier[x.tier_act] = by_tier[x.tier_act] or {}
    table.insert(by_tier[x.tier_act], x)
end
-- Sorted then seeded-shuffled, so the choice depends on the seed alone and not on table
-- order, which Lua does not guarantee between runs.
math.randomseed(SEED)
for _, list in pairs(by_tier) do
    table.sort(list, function(a, b) return a.name < b.name end)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local controls, taken, shortfall = {}, {}, {}
local scale = N_CONTROL / #misses
for t = 0, 6 do
    local need = math.floor((want[t] or 0) * scale + 0.5)
    local have = by_tier[t] or {}
    local got  = 0
    for i = 1, math.min(need, #have) do
        controls[#controls + 1] = have[i]
        taken[have[i].name] = true
        got = got + 1
    end
    if got < need then shortfall[t] = need - got end
end
-- Top up where the matched draw ran dry, NEAREST TIER FIRST to the tier that fell short.
-- This matters more than it looks: the shortfall is always at the extreme the model
-- misses, and filling it from the middle of the scale would hand the study a control
-- group that is systematically easier than the misses - so any offset between the two
-- groups would be a tier effect wearing the hypothesis's clothes.
if #controls < N_CONTROL then
    local short_tiers = {}
    for t = 0, 6 do
        if shortfall[t] then short_tiers[#short_tiers + 1] = t end
    end
    local function Distance(x)
        local best = 99
        for _, t in ipairs(short_tiers) do
            best = math.min(best, math.abs(x.tier_act - t))
        end
        return best
    end
    local rest = {}
    for _, x in ipairs(pool) do
        if not taken[x.name] then rest[#rest + 1] = x end
    end
    table.sort(rest, function(a, b)
        local da, db = Distance(a), Distance(b)
        if da ~= db then return da < db end
        return a.name < b.name          -- total order, so the seed alone decides below
    end)
    -- Shuffle only WITHIN each distance band, so nearness is respected and the choice
    -- inside a band is still the seed's.
    local i = 1
    while i <= #rest do
        local j = i
        while j < #rest and Distance(rest[j + 1]) == Distance(rest[i]) do j = j + 1 end
        for k = j, i + 1, -1 do
            local m = i + math.random(k - i + 1) - 1
            rest[k], rest[m] = rest[m], rest[k]
        end
        i = j + 1
    end
    for _, x in ipairs(rest) do
        if #controls >= N_CONTROL then break end
        controls[#controls + 1] = x
        taken[x.name] = true
    end
end

----------------------------------------------------------------------
-- Shuffle together and write
----------------------------------------------------------------------

local items = {}
for _, x in ipairs(misses)   do items[#items + 1] = { rec = x, group = 'miss' } end
for _, x in ipairs(controls) do items[#items + 1] = { rec = x, group = 'control' } end
table.sort(items, function(a, b) return a.rec.name < b.rec.name end)
for i = #items, 2, -1 do
    local j = math.random(i)
    items[i], items[j] = items[j], items[i]
end

local prefix = INST:sub(1, 1):upper()
for i, it in ipairs(items) do it.id = ('%s%02d'):format(prefix, i) end

local ws_path  = _dir .. INST .. '_rating_worksheet.txt'
local key_path = _dir .. INST .. '_rating_key.txt'

do
    local f = assert(io.open(ws_path, 'wb'))
    local function W(s) f:write(s) end
    W(('BLINDED RATING WORKSHEET - %s\n'):format(INST:upper()))
    W('=======================================\n\n')
    W('Rate each chart on the Rock Band 3 tier scale, from what the CHART asks of a\n')
    W('player. Write the number in the brackets, first thing. Leave a row blank if you\n')
    W('cannot judge it; a blank is far more useful than a guess.\n\n')
    W('Torn between two ADJACENT tiers? Write both - "3 or 4" - and it is scored as 3.5.\n')
    W('That is better than a coin flip, which just adds half a tier of noise. Torn across\n')
    W('three tiers means you cannot judge it: leave it blank. Notes after the number are\n')
    W('fine, but avoid stray digits in them - "many 4-note runs" reads as a rating.\n\n')
    W('  0 Warmup   1 Apprentice   2 Solid   3 Moderate\n')
    W('  4 Challenging   5 Nightmare   6 Impossible\n\n')
    W('The official rank, the tool prediction, and which rows are which are all in\n')
    W('a separate key file. DO NOT OPEN IT until every row below is filled in - a\n')
    W('number you have already seen cannot be un-seen, and the study is worthless if\n')
    W('the answers are anchored to it.\n\n')
    W('Half these songs are ones the tool got right. You cannot tell which from this\n')
    W('sheet, and that is deliberate - they measure YOUR scale against the official\n')
    W('one, which is what makes the rest interpretable.\n\n')
    W('Put a ! on any row you are not judging cold. Either kind counts: remembering the\n')
    W('official rating, OR recognising the song from our own worst-residual reports.\n')
    W('The second is the worse leak - those reports show the official rank, the model\'s\n')
    W('answer, and the fact that it was a miss - so flag it whenever it happens.\n\n')
    W('Flagged rows are reported separately, never dropped, and the figures are also\n')
    W('computed over the blind rows alone.\n\n')
    W('A ! on its own is NOT a rating. Recognising a song is not judging it, so still\n')
    W('write your own number beside the mark.\n\n')
    W('----------------------------------------------------------------------\n\n')
    for _, it in ipairs(items) do
        W(('  %s  %-34s  tier [   ]\n\n'):format(it.id, it.rec.name))
    end
    W('----------------------------------------------------------------------\n')
    W(('%d charts. Score with:\n'):format(#items))
    W(('  lua dev/calibration/score_human_ratings.lua %s\n'):format(INST))
    f:close()
end

do
    local f = assert(io.open(key_path, 'wb'))
    local function W(s) f:write(s) end
    W(('RATING KEY - %s.  DO NOT READ THIS UNTIL THE WORKSHEET IS FILLED IN.\n')
        :format(INST:upper()))
    W('=====================================================================\n\n')
    W('Generated alongside ' .. INST .. '_rating_worksheet.txt. Reading it first anchors\n')
    W('every answer and there is no way to undo that.\n\n')
    W(('model: %s / %s\n\n'):format(sel.candidate, sel.scale))
    W(('%-5s %-34s %-8s %6s %6s %6s %6s\n')
        :format('id', 'shortname', 'group', 'off_t', 'off_r', 'mdl_t', 'mdl_r'))
    for _, it in ipairs(items) do
        W(('%-5s %-34s %-8s %6d %6d %6d %6.0f\n')
            :format(it.id, it.rec.name, it.group, it.rec.tier_act, it.rec.rank,
                    it.rec.tier_pred, it.rec.pred))
    end
    f:close()
end

----------------------------------------------------------------------
-- What the draw achieved
----------------------------------------------------------------------

io.write(('wrote %s  (%d charts: %d misses, %d controls)\n')
    :format(ws_path, #items, #misses, #controls))
io.write(('wrote %s  - do not read it yet\n\n'):format(key_path))

io.write('official-tier match between misses and controls:\n')
io.write('  tier   misses   controls\n')
local cw = {}
for _, x in ipairs(controls) do cw[x.tier_act] = (cw[x.tier_act] or 0) + 1 end
for t = 0, 6 do
    if (want[t] or 0) > 0 or (cw[t] or 0) > 0 then
        io.write(('   %d     %5d    %6d%s\n'):format(t, want[t] or 0, cw[t] or 0,
            shortfall[t] and ('   (%d short - too few correct charts at this tier)')
                :format(shortfall[t]) or ''))
    end
end
io.write('\nA shortfall is not a defect in the draw. At the tiers where the model misses\n')
io.write('most there are barely any charts it got right, which is the finding restated.\n')
