-- Freeze the six selected models into lib/reaper_difficulty_models.lua.
--
-- This is the bridge the calibration rounds never built. The protocol SELECTS a candidate
-- shape per instrument; it never fits a final model or writes one down. Until this ran,
-- the shipped suggester had no coefficients to ship.
--
-- Run from the repository root, with a plain Lua interpreter - no REAPER:
--
--     lua dev/calibration/export_production_models.lua
--
-- Reads corpus_scores.csv, refits each selected candidate once on every row it is allowed
-- to train on, and writes the artifact. Read-only apart from that one output file.
--
-- ---------------------------------------------------------------------------
-- WHY THE RIDGE IS CHOSEN DIFFERENTLY HERE THAN IN protocol.lua
--
-- The protocol picks a ridge INSIDE each outer fold and never needs to name one number:
-- it is cross-validating, so a different ridge per fold is fine. A shipped model has to
-- commit to one. Two things then matter that did not before.
--
--   1. REPRODUCIBILITY ACROSS INTERPRETERS. ShuffledStratifiedFolds calls math.random,
--      whose implementation CHANGED between Lua 5.3 and 5.4 (5.4 replaced it with
--      xoshiro256**). REAPER and this offline runner therefore disagree on what
--      SEED = 20260812 means, so a fold-dependent choice made here would not be the one
--      made there. This file carries its own arithmetic LCG instead - no bitwise ops, no
--      library RNG - so the same CSV produces the same CONTENT on any Lua.
--
--      Content, not bytes: the artifact is written in text mode, so its line endings
--      follow the platform (CRLF as committed, from Windows). That is fine while nothing
--      diffs it mechanically. If it ever joins the report and the manifest in the CI
--      check, switch this writer to 'wb' as they use - and expect a one-time whole-file
--      diff when the endings normalise.
--
--   2. A MODAL VOTE IS KNIFE-EDGE. Guitar's recorded ridge histogram is 0.01 at 36% and
--      0.1 at 31%; ~40 folds separate them out of 1100. Picking the modal winner would
--      let a handful of folds decide a shipped hyperparameter. So every grid value is
--      scored on every inner holdout of every fold of every repeat, and the one with the
--      lowest POOLED error wins, ties going to the smaller ridge. That uses the same
--      nested inner folds and the same error measure as the protocol, over strictly more
--      evidence, and it has no tie to break by luck. The full table is printed so a near
--      tie is visible rather than silent.
--
-- This is the exporter's own reproducibility rule. It does NOT re-run, re-open or
-- second-guess the protocol's SELECTION - the six candidate names below are the
-- protocol's output, and their factor lists are read out of protocol.lua rather than
-- retyped.
--
-- Since 2026-08-21 those names are no longer merely "copied verbatim" and trusted: the
-- protocol writes calibration_decision_manifest.lua, this reads it, and a disagreement
-- with the table below is a hard failure. See the manifest block further down for why
-- copying-and-trusting was not safe.
-- ---------------------------------------------------------------------------

local _script = (arg and arg[0]) or 'dev/calibration/export_production_models.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/calibration/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))

local _csv = _dir .. 'corpus_scores.csv'
local _out = _root .. 'lib/reaper_difficulty_models.lua'

-- Schema version of the emitted artifact. Bump when the SHAPE of a model record changes
-- (a new field, a renamed one), not when the numbers move - the consumer checks this and
-- refuses a table it does not understand, which is what stops a stale artifact from being
-- read as a plausible but wrong model.
-- 2: added `corr`, per-model factor correlations for explanation deduplication.
-- 3: more than one trailing origin flag. `keys` used to end with exactly is_lego; it now
--    ends with one is_<origin> per PROTOCOL.AUX_ORIGINS entry (is_lego, is_rb2), so a
--    consumer counting back from the end must not assume a single flag.
-- 4: `n_lego` renamed to `n_aux`. It stopped meaning "Lego rows" when the RB2 disc export
--    was added as a second auxiliary origin - it has counted Lego PLUS RB2 since schema 3
--    while still being named for one of them, which the 2026-08-21 peer review flagged as
--    a provenance field that misreports its own contents. Renamed rather than split
--    because no consumer needs the breakdown; the report and manifest carry it per origin.
-- 5: added `reliability` - per-tier counts in the PREDICTED-tier conditional, carried from
--    the manifest rather than computed here (it comes from out-of-fold predictions and
--    this file refits on every row). Feeds the product's per-tier reliability note, the
--    first thing that tells an author WHERE the model is weak instead of how mature it is.
local SCHEMA = 5

dofile(_dir .. 'difficulty_score.lua')          -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')   -- appends the vocal columns to it
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')
dofile(_root .. 'lib/reaper_difficulty_predict.lua')   -- DIFFICULTY_SCALE_INV, to cross-check

----------------------------------------------------------------------
-- The selection
--
-- The protocol's output, transcribed. Only the NAMES live here; the factor lists come
-- from CandidatesFor(), so a candidate edited in protocol.lua can never silently
-- disagree with what was exported.
----------------------------------------------------------------------

local SELECTIONS = {
    { inst = 'guitar',    candidate = 'full@attacks',                     scale = 'log(rank)' },
    -- LOW-END CORPUS (205 -> 318 songs). Replaced 'baseline+ent_rel@attacks'. Same three
    -- factors and the same shape, with the plain entropy rate in place of the relative
    -- one; the leader (primary+entropy@attacks) is +0.34 points and wins only 50% of
    -- paired repeats, nowhere near the bar, so the tie goes to the simpler model.
    { inst = 'bass',      candidate = 'baseline+entropy',                 scale = 'log(rank)' },
    -- KEYS TOP-UP (379 -> 394 songs). Back to 'full_drum', now on log(rank), after one
    -- revision on primary+limbs+ent+offbeat and one on primary+entropy. This time it wins
    -- outright - no simpler candidate came within the predeclared margin - and it is the
    -- best drums has ever measured: usable lower bound 93.38%, rho +0.888.
    --
    -- DRUMS RE-SELECTS ON ALMOST EVERY RESCORE. Four corpus revisions, four different
    -- answers (full_drum/rank, primary+entropy/rank, primary+limbs+ent+offbeat/log,
    -- full_drum/log), because for three of them the leader's margin sat just under the bar
    -- (+0.90, +0.79, +0.64) and tiny data changes reordered the field. Re-read the protocol
    -- report after ANY rescore rather than assuming this entry still matches; dev/tests
    -- checks exactly that.
    --
    -- full_drum does NOT carry the duplicate-by-construction pro_ pairs. An earlier version
    -- of this comment said it did; that was wrong. The pairs
    -- (total_changes/pro_total_changes, change_rate/pro_change_rate, and tight_p10/tight_med
    -- against their pro_ twins) are bit-identical on drum rows and blow up into +903/-906,
    -- but only in the ANALYSIS report's unridged fit over every column. No declared drum
    -- candidate contains both halves of any of them.
    -- ROUND 22 swapped the three PEAK columns for their roll-lane twins. The factor list
    -- is otherwise unchanged. A 126/127 roll lane is a leniency device - the player is not
    -- required to hit the notes under it - so the peaks were reading a free-play region as
    -- the densest passage in the song. `makemesmile2` was the worst over-prediction on
    -- record at 550 against an official 292 and now reads 362, a 188-rank move that takes
    -- it from two tiers out to one. Corpus: 93.38% -> 94.37% lower bound, rho +0.888 ->
    -- +0.894, and 3 charts fixed against 2 broken.
    --
    -- THE TWO IT BREAKS ARE NOT A MEASUREMENT ERROR, and the mechanism is worth keeping.
    -- `dreamonlive` and `wearethechampions2` have IDENTICAL values on the twins and their
    -- originals - neither has a lane under its peak window. What moved is the column's
    -- SCALE: dropping the leniency passages cut attack_density_peak's corpus sd by 17.7%
    -- and hand_density_peak's by 16.5%, because the excluded values were the extreme
    -- outliers. Standardization is global, so every chart's z rose on those columns
    -- (`dreamonlive`'s attack z went +0.44 -> +0.62 with its chart untouched). Excluding
    -- outliers from a standardized column never stays local to the outliers.
    { inst = 'drum',      candidate = 'full_drum@noroll',                 scale = 'log(rank)' },
    -- ROUND 16 chose these factors. Replaced 'primary+entropy_rel+complex_peak' / rank:
    -- that model measured density in GEMS and carried chord_size_mean at -12.86 to divide
    -- chords back out of the count - which charged a real chart ~28 rank per extra note in
    -- its voicing, so the same music voiced as triads scored two tiers below the single-note
    -- version. This one counts ATTACKS and drops the chord factor entirely, so voicing is
    -- not an input at all. See dev/calibration/README.md, "a coefficient's sign is only
    -- interpretable relative to the units of the factors beside it".
    --
    -- KEYS TOP-UP moved the SCALE from log(rank) to rank; the factor list is unchanged.
    { inst = 'keys',      candidate = 'primary+ent_rel+complex@attacks-chord',
                                                                     scale = 'rank'      },
    { inst = 'real_keys', candidate = 'primary+ent_rel@attacks',          scale = 'rank'      },
    -- ROUND 18. Replaced 'primary+range+parts'. Vocals under-rates its hardest charts by
    -- ~117 rank, three times worse than any other instrument's top-end shrinkage, and two
    -- explanations were eliminated before a factor was added: it is not a song-level label
    -- (other instruments' ranks predict a vocals rank at only rho +0.219, the lowest of the
    -- six), and it is not the "high AND held" interaction (super-linear forms of sustained
    -- high time moved the top-end bias by under 1 rank, two of them the wrong way).
    --
    -- What was missing had never been declared: high_time_70, the fraction of sung time
    -- above G4, is the largest single discriminator of the charts ranked 400+ at +1.28 sd,
    -- and the tessitura family had only ever appeared in candidates that DROP vocal_parts.
    -- With pc_change_rate beside it - the demand is high AND MOVING, not high and held -
    -- vocals gains rho +0.617 -> +0.668 over the incumbent on the same rows.
    --
    -- STILL FAILS THE GATE, at a lower bound of 85.12% against the 90% floor and rho short
    -- of 0.70. Shipped anyway, per the decision to get author feedback on the weak
    -- instruments; the artifact's `experimental` badge is what says so in the UI.
    -- ROUND 20 replaced the linear vocal_parts term with parts_3, a step. Same factor
    -- count, same everything else. Entering the harmony count as a NUMBER asserted that one
    -- singer to two costs what two to three costs; with the other eleven factors held the
    -- corpus says one part and two sit 0.4 rank apart and the entire effect is the move to
    -- three, so the linear term was over-crediting all 87 two-part songs by ~12 rank.
    --
    -- THE CONTROL IS WHAT MAKES IT A FINDING. `@parts_free` - one free coefficient per step,
    -- told nothing about how the levels relate - ties `@parts_step3` at 88.63%, identically.
    -- Given permission to price the two steps differently the fit does not use it.
    --
    -- IT ARRIVES BY THE EQUAL-COMPLEXITY TIE-BREAK, not by clearing the gain bar: +0.27
    -- points at 40% of paired repeats is noise, and SelectCandidate prefers the better mean
    -- among candidates of the same size. That door is safe here precisely because vocals
    -- fails its gate either way - only the model's CLAIM changes. See the README finding on
    -- why the same door must not be trusted on keys, which sits 0.06 points from its floor.
    --
    -- WHAT ROUND 21 MEASURED AND DID NOT WIN. `parts+tess+move+breath@mean50` posts 89.02%,
    -- the highest vocal figure this project has recorded, and was refused at +0.40 points /
    -- 80% of repeats against a bar of >1.00 and >70%. The refusal is substantively right and
    -- not merely conservative: on the ten worst-predicted charts the breath columns move
    -- nothing (antsmarching 192 -> 192, phantomoftheopera 240 -> 240) and push three of the
    -- hardest DOWN (somebodytolove2 320 -> 315, dontstopmenow 292 -> 280). Its whole gain
    -- comes from middling charts. Three mechanisms - phrase geometry, harmony shape, breath
    -- grouping - now all measure null on the same ten charts.
    --
    -- STILL FAILS THE GATE, 85.42% against the 90% floor and rho +0.674 against 0.70.
    -- Shipped anyway, per the decision to get author feedback on the weak instruments; the
    -- artifact's `experimental` badge is what says so in the UI.
    { inst = 'vocals',    candidate = 'parts+tess+move@parts_step3',      scale = 'log(rank)' },
}

-- Product maturity, from the product plan's status table. Carried in the artifact so the
-- UI does not hardcode a second copy that could disagree with what was actually exported.
-- These describe validation against noisy official ranks - they are NOT the probability
-- that a given prediction is right.
--
-- NOTHING HERE IS 'validated', AND NOTHING MAY BE UNTIL A TEST SET IS SPENT. Guitar,
-- bass and drum carried 'validated' until 2026-08-21, on the strength of passing the
-- release gate. The peer review that day named the contradiction: dev/calibration's own
-- README says in as many words that these are development-set repeated-CV figures and
-- must be called "development-gate passes", not validated, because the reserved test
-- partition has deliberately never been drawn. Every RB3 row has already informed
-- factor design, residual inspection and candidate selection across 23 rounds, so no
-- current row can supply confirmatory evidence later, whatever it is renamed to.
--
-- They are 'beta' instead - the same word keys carries, which is the honest reading:
-- the model passed the gate the project can currently evaluate, and that gate is
-- narrower than the release gate the implementation plan describes. Restoring
-- 'validated' needs genuinely new pack-held-out data evaluated once, not a better
-- number on these rows.
--
-- 'beta' rather than a new 'development_gate_pass': DIFFICULTY_STATUS_BADGE and
-- DIFFICULTY_STATUS_NOTE in difficulty_explain.lua know three statuses, and inventing a
-- fourth is a UI wording decision that belongs with the wider gate, not with this fix.
local STATUS = {
    guitar = 'beta', bass = 'beta', drum = 'beta',
    keys = 'beta', real_keys = 'experimental', vocals = 'experimental',
}

----------------------------------------------------------------------
-- Failing loudly
----------------------------------------------------------------------

local _errors = 0
local function Fail(fmt, ...)
    io.write('  ERROR: ', (select('#', ...) > 0) and fmt:format(...) or fmt, '\n')
    _errors = _errors + 1
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
    local header_line, header, rows = nil, nil, {}
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
    if not header then return nil, 'empty file' end
    return { header = header, header_line = header_line, rows = rows }
end

-- Detects a header that is not the one this artifact was built from. Deliberately a plain
-- polynomial hash and not a checksum with security properties: the job is to notice an
-- edited or reordered column set, and a consumer comparing fingerprints does not need
-- more than that. Arithmetic only, so it agrees across Lua versions.
local function Fingerprint(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    return h
end

----------------------------------------------------------------------
-- Portable RNG and fold assignment
--
-- Mirrors ShuffledStratifiedFolds in stats.lua exactly - group by stratum in sorted key
-- order, Fisher-Yates inside each stratum, deal round-robin from a rotating start - with
-- the library RNG replaced by the LCG below. Same procedure, reproducible everywhere.
----------------------------------------------------------------------

-- Numerical Recipes' LCG constants. Every intermediate stays under 2^53, so the
-- arithmetic is exact in a double and identical whether Lua has integers or not.
local function NewRng(seed)
    local state = seed % 4294967296
    return function(n)          -- uniform integer in 1..n
        state = (1664525 * state + 1013904223) % 4294967296
        return math.floor(state / 4294967296 * n) + 1
    end
end

local function StratifiedFolds(strata, k, rng)
    local n = #strata
    k = math.max(2, math.min(k or 5, n))

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
    local start = 0
    for _, key in ipairs(keys) do
        local g = by[key]
        for i = #g, 2, -1 do
            local j = rng(i)
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

----------------------------------------------------------------------
-- Collecting one instrument's rows
----------------------------------------------------------------------

local function Collect(csv, inst)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    for _, row in ipairs(csv.rows) do
        local function Field(name)
            local i = csv.header[name]
            return i and row[i] or nil
        end
        if Field('instrument') == inst then
            local rank = tonumber(Field('rank'))
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(Field(k))
                if v == nil then ok = false else fv[j] = v end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]   = fv
                d.ranks[n]   = rank
                d.origins[n] = Field('origin')
                d.names[n]   = Field('shortname')
            end
        end
    end
    return d
end

-- The protocol's training partition: rb3_dlc rows minus any disputed label are the
-- development rows, every auxiliary origin (see PROTOCOL.AUX_ORIGINS) is always-training
-- at its own weight, and any other origin is neither - scored into the CSV but never
-- fitted, which is where the lone greenday row goes.
local function Partition(d, inst)
    local target, extra, weird = {}, {}, {}
    for i, o in ipairs(d.origins) do
        if o == 'rb3_dlc' then
            if IsWeirdlyScored(d.names[i], inst) then weird[#weird + 1] = i
            else target[#target + 1] = i end
        elseif AuxWeight(o) then
            extra[#extra + 1] = i
        end
    end
    return target, extra, weird
end

----------------------------------------------------------------------
-- Design matrix
----------------------------------------------------------------------

-- Rows in the shape RunOneRepeat builds them: the candidate's factors in declared order,
-- then one origin flag per PROTOCOL.AUX_ORIGINS entry, in that order. Every product
-- prediction passes 0 for all of them.
--
-- The row's ORIGIN drives the flags rather than a caller-supplied value, and the weight
-- comes from the same table, so the design matrix here cannot disagree with the one the
-- protocol measured - which is the whole reason the exported coefficients mean anything.
-- `aux` is optional and parallel to X: true where the row came from an auxiliary origin.
-- ChooseRidgePooled needs it to apply PROTOCOL.RIDGE_VALIDATION, which must match the
-- protocol's policy exactly - the two searches disagreeing is peer review finding 6.
local function BuildRows(d, idx, keys, pos, scale, X, ys, ws, aux)
    for _, i in ipairs(idx) do
        local row = {}
        for j, k in ipairs(keys) do row[j] = d.feats[i][pos[k]] end
        for _, a in ipairs(PROTOCOL.AUX_ORIGINS) do
            row[#row + 1] = (d.origins[i] == a.origin) and 1 or 0
        end
        X[#X + 1]  = row
        ys[#ys + 1] = scale.fwd(d.ranks[i])
        ws[#ws + 1] = AuxWeight(d.origins[i]) or 1.0
        if aux then aux[#aux + 1] = (AuxWeight(d.origins[i]) ~= nil) end
    end
end

----------------------------------------------------------------------
-- Ridge: pooled inner-fold error over every fold of every repeat
----------------------------------------------------------------------

local function ChooseRidgePooled(d, target, extra, inst, keys, pos, scale)
    local strata = {}
    for n, ti in ipairs(target) do strata[n] = tostring(TierForRank(inst, d.ranks[ti])) end

    local err, cnt = {}, {}
    for _, g in ipairs(PROTOCOL.RIDGE_GRID) do err[g], cnt[g] = 0, 0 end

    for rep = 1, PROTOCOL.N_REPEATS do
        local rng   = NewRng(PROTOCOL.SEED + rep)
        local folds = StratifiedFolds(strata, PROTOCOL.NFOLD, rng)
        for f = 1, #folds do
            -- Training rows for this outer fold, exactly as the protocol builds them.
            local X, ys, ws, aux = {}, {}, {}, {}
            for g = 1, #folds do
                if g ~= f then
                    local rows = {}
                    for _, ti in ipairs(folds[g]) do rows[#rows + 1] = target[ti] end
                    BuildRows(d, rows, keys, pos, scale, X, ys, ws, aux)
                end
            end
            BuildRows(d, extra, keys, pos, scale, X, ys, ws, aux)

            -- The protocol's own nested search, but scoring every grid value instead of
            -- keeping only the winner. KFoldIndices is deterministic round-robin, so the
            -- inner split needs no RNG and is identical everywhere.
            if #X >= PROTOCOL.INNER_FOLD * 2 then
                local inner = KFoldIndices(#X, PROTOCOL.INNER_FOLD)
                for _, ridge in ipairs(PROTOCOL.RIDGE_GRID) do
                    for a = 1, #inner do
                        local tx, ty, tw = {}, {}, {}
                        for b = 1, #inner do
                            if b ~= a then
                                for _, i in ipairs(inner[b]) do
                                    tx[#tx + 1], ty[#ty + 1], tw[#tw + 1] = X[i], ys[i], ws[i]
                                end
                            end
                        end
                        local fit = MultiFit(tx, ty, ridge, tw)
                        if fit then
                            for _, i in ipairs(inner[a]) do
                                -- Same scoring policy as the protocol's ChooseRidge. The
                                -- two drifting apart is exactly finding 6.
                                local sw = InnerScoreWeight(aux[i], ws[i])
                                if sw > 0 then
                                    err[ridge] = err[ridge]
                                        + sw * math.abs(ApplyFit(X[i], fit) - ys[i])
                                    cnt[ridge] = cnt[ridge] + sw
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local best, best_err, table_rows = nil, math.huge, {}
    for _, g in ipairs(PROTOCOL.RIDGE_GRID) do
        local mean = (cnt[g] > 0) and (err[g] / cnt[g]) or nil
        table_rows[#table_rows + 1] = { ridge = g, err = mean, n = cnt[g] }
        -- Strictly less than, walking the grid smallest-first, so a tie keeps the
        -- smaller ridge - the same "simpler wins" spirit as the candidate tie-break.
        if mean and mean < best_err then best, best_err = g, mean end
    end
    return best, table_rows
end

----------------------------------------------------------------------
-- Per-factor support bounds
--
-- Over the TARGET rows only, not target-plus-lego. Two different row sets for two
-- different jobs, and conflating them would be wrong in both directions:
--
--   fit.mean / fit.sd come from MultiFit over every training row INCLUDING the
--   down-weighted lego ones, because that is what standardization was computed against
--   and the coefficients are only valid paired with it.
--
--   min / max / p90 describe the support the SUGGESTION is honest about, and every
--   prediction is made with is_lego = 0, i.e. on the RB3 scale. A chart inside lego's
--   range but outside RB3's is an extrapolation of the thing being predicted.
----------------------------------------------------------------------

local function Percentile90(vals)
    if #vals == 0 then return 0 end
    local t = {}
    for i, v in ipairs(vals) do t[i] = v end
    table.sort(t)
    if #t == 1 then return t[1] end
    local idx = 0.90 * (#t - 1) + 1
    local lo, hi = math.floor(idx), math.ceil(idx)
    if lo == hi then return t[lo] end
    return t[lo] + (t[hi] - t[lo]) * (idx - lo)
end

local function FactorBounds(d, target, keys, pos)
    local bounds = {}
    for _, k in ipairs(keys) do
        local vals = {}
        for _, i in ipairs(target) do vals[#vals + 1] = d.feats[i][pos[k]] end
        local mn, mx = math.huge, -math.huge
        for _, v in ipairs(vals) do
            if v < mn then mn = v end
            if v > mx then mx = v end
        end
        bounds[k] = { min = mn, max = mx, p90 = Percentile90(vals) }
    end
    return bounds
end

----------------------------------------------------------------------
-- Pairwise correlation between a model's own factors
--
-- Consumed by DifficultyExplanations, which shows at most three "notable properties" and
-- picks them by how far each measurement sits from the corpus mean. That rule has no idea
-- whether a factor says anything NEW: on 20% of corpus rows two of the three slots went to
-- a correlated pair, i.e. one observation stated twice, while a genuinely different
-- property waited behind it.
--
-- MEASURED AND SHIPPED RATHER THAN HAND-GROUPED, because which factors duplicate is a
-- property of the instrument, not of the vocabulary. entropy_h2 and entropy_h2_rel
-- correlate +0.96 on drums; notes_total and total_changes +0.94 on drums but +0.80 on
-- guitar; complex_peak and density_peak +0.88 on keys alone; tight_p10 and tight_med range
-- from +0.45 on drums to +0.75 on vocals. A single hand-written grouping would either miss
-- the drum pairs or suppress the spacing pair where it genuinely carries two facts.
--
-- Target rows only, matching FactorBounds and for the same reason: every prediction is
-- made on the RB3 scale, so the correlations the product reasons about are RB3's.
--
-- Only pairs at or above the threshold are emitted - the artifact carries what it needs to
-- suppress a restatement, not a full matrix. The origin flags are excluded: they are
-- training-time indicators and can never be a bullet.
----------------------------------------------------------------------

-- Below this two factors are treated as saying different things. Must not be raised above
-- the consumer's own COLLINEAR_R in difficulty_explain.lua, or a pair that file wants to
-- suppress would simply be missing from the artifact.
local CORR_EMIT_MIN = 0.70

local function Correlation(xs, ys)
    local n = #xs
    if n < 2 then return 0 end
    local mx, my = 0, 0
    for i = 1, n do mx, my = mx + xs[i], my + ys[i] end
    mx, my = mx / n, my / n
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, n do
        local a, b = xs[i] - mx, ys[i] - my
        sxy, sxx, syy = sxy + a * b, sxx + a * a, syy + b * b
    end
    -- A constant column correlates with nothing; report 0 rather than dividing by zero.
    if sxx <= 0 or syy <= 0 then return 0 end
    return sxy / math.sqrt(sxx * syy)
end

local function FactorCorrelations(d, target, keys, pos)
    local cols = {}
    for _, k in ipairs(keys) do
        if not k:match('^is_') then
            local vals = {}
            for _, i in ipairs(target) do vals[#vals + 1] = d.feats[i][pos[k]] end
            cols[k] = vals
        end
    end
    local out, n = {}, 0
    for a = 1, #keys do
        for b = a + 1, #keys do
            local ka, kb = keys[a], keys[b]
            if cols[ka] and cols[kb] then
                local rr = Correlation(cols[ka], cols[kb])
                if math.abs(rr) >= CORR_EMIT_MIN then
                    -- Joined in the model's own key order. The reader tries both
                    -- orderings, so this needs no sorting convention.
                    out[ka .. '|' .. kb] = rr
                    n = n + 1
                end
            end
        end
    end
    return out, n
end

-- The concentration warning's threshold, per instrument, from the same target rows.
--
-- Measured rather than assumed, because a single cutoff is provably wrong here: guitar's
-- p90 marked-solo ratio is 2.67 while bass and drums never mark a solo at all (p95 = 1.00),
-- so a shared "3.4x" would fire on nothing for half the instruments. Charts with no marked
-- solo fall back to the peak/average density ratio, whose p90 ranges from 1.58 on drums to
-- 2.74 on keys.
--
-- Both are computed for every instrument that has the columns; vocals has neither and gets
-- no concentration warning.
local function ConcentrationThresholds(d, target, pos)
    local out = {}
    local function P90(key, transform)
        local col = pos[key]
        if not col then return nil end
        local vals = {}
        for _, i in ipairs(target) do
            -- NOT `transform and transform(i) or d.feats[i][col]`. A transform returning
            -- nil - which is how it says "this row cannot express a ratio" - would fall
            -- through to the raw column and contribute a value it deliberately declined
            -- to produce. On vocals, where density_avg is structurally 0, that silently
            -- turned "no threshold" into a threshold of 0, which every chart exceeds.
            local v
            if transform then v = transform(i) else v = d.feats[i][col] end
            if v then vals[#vals + 1] = v end
        end
        if #vals == 0 then return nil end
        return Percentile90(vals)
    end
    out.solo_change_ratio = P90('solo_change_ratio')
    local avg_col, peak_col = pos['density_avg'], pos['density_peak']
    if avg_col and peak_col then
        out.density_ratio = P90('density_peak', function(i)
            local a = d.feats[i][avg_col]
            if a and a > 0 then return d.feats[i][peak_col] / a end
            return nil
        end)
    end
    return out
end

----------------------------------------------------------------------
-- Emitting Lua
----------------------------------------------------------------------

-- Shortest representation that round-trips exactly. %.17g always does for a double;
-- trying 15 and 16 first keeps the artifact readable without giving up a single bit.
local function Num(v)
    if type(v) ~= 'number' then error('not a number: ' .. tostring(v)) end
    if v ~= v then error('NaN in model output') end
    if v == math.huge or v == -math.huge then error('infinite value in model output') end
    for _, p in ipairs({ '%.15g', '%.16g', '%.17g' }) do
        local s = p:format(v)
        if tonumber(s) == v then return s end
    end
    error('no round-tripping representation for ' .. tostring(v))
end

local function NumList(vals, indent)
    local parts = {}
    for _, v in ipairs(vals) do parts[#parts + 1] = Num(v) end
    -- Wrapped at a fixed width so a 27-coefficient model stays diff-able line by line.
    local lines, cur = {}, indent
    for i, s in ipairs(parts) do
        local piece = s .. (i < #parts and ', ' or '')
        if #cur + #piece > 92 and cur ~= indent then
            lines[#lines + 1] = cur
            cur = indent
        end
        cur = cur .. piece
    end
    if cur ~= indent then lines[#lines + 1] = cur end
    return table.concat(lines, '\n')
end

local function Quote(s) return ('%q'):format(s) end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

io.write('======  Difficulty models - production export  ======\n\n')

local csv, err = LoadCsv(_csv)
if not csv then
    io.write(('Could not read the scores CSV.\n  %s\n\nRun run_calibration_vkr.lua first.\n')
        :format(tostring(err)))
    os.exit(1)
end

local pos = {}
for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end

for _, k in ipairs(SCORE_FACTOR_KEYS) do
    if not csv.header[k] then Fail('CSV is missing factor column %s', k) end
end
if _errors > 0 then
    io.write('\nThis CSV predates the current factor set. Rescore before exporting.\n')
    os.exit(1)
end

io.write(('CSV     : %s\n'):format(_csv))
io.write(('rows    : %d   factor columns: %d\n'):format(#csv.rows, #SCORE_FACTOR_KEYS))
io.write(('header  : fingerprint %d\n'):format(Fingerprint(csv.header_line)))

----------------------------------------------------------------------
-- The decision manifest, and why this file no longer decides anything
----------------------------------------------------------------------

-- Until 2026-08-21 the SELECTIONS table above WAS the decision: whatever it named got
-- refitted and shipped. Nothing could detect it being wrong. The unit tests refit the
-- model this file names and compare coefficients, so they pass whenever this file is
-- self-consistent - including when the protocol has since selected something else
-- entirely. The peer review put it plainly: "tests can pass while the protocol report
-- has reselected a different model." Drums makes that concrete rather than theoretical -
-- it has re-selected on four of the last four rescores, three of them on margins just
-- under the bar.
--
-- The protocol now emits calibration_decision_manifest.lua, and that is the authority.
-- SELECTIONS stays because the rounds and reasoning documented against each entry are
-- worth keeping in the file that acts on them - but it is now an ASSERTION. If it and
-- the manifest disagree, this exits rather than picking one, because either could be the
-- stale half and guessing is how a wrong model ships quietly.
--
-- The manifest also carries fingerprints of the inputs the protocol read. If any no
-- longer matches, the selection was made against data that has since moved and this
-- refuses to export. That is a stricter check than the header fingerprint above, which
-- only ever noticed a changed COLUMN SET - a rescore that kept the columns and changed
-- every value passed it cleanly.
local _manifest_path = _dir .. 'calibration_decision_manifest.lua'

-- Per-instrument reliability tables lifted from the manifest, keyed by instrument. Global
-- because the model-building loop below is a long way from the validation block that
-- fills it, and threading one table through would obscure that it is carried rather than
-- computed - which is the point worth being obvious.
MANIFEST_RELIABILITY = {}

local function ReadAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

do
    local chunk = loadfile(_manifest_path)
    if not chunk then
        io.write(('\nNo decision manifest at %s\n'):format(_manifest_path))
        io.write('Run the protocol first:  lua dev/calibration/run_protocol_offline.lua\n')
        os.exit(1)
    end
    chunk()

    local M = CALIBRATION_MANIFEST
    -- Schema 3 since 2026-08-22 (rho_lower at 2, endpoint_lower at 3 - the gate gained an
    -- extremes bar, so a schema 2 file records verdicts reached without it). Pinned
    -- exactly rather than accepted as ">= 1": this file's job is to refuse inputs it does
    -- not understand, and a schema it has never seen is exactly that.
    if type(M) ~= 'table' or M.schema ~= 4 then
        Fail('manifest schema is %s, expected 4', tostring(M and M.schema))
    elseif not M.complete then
        -- A manifest is only written after every instrument is analysed, so this should
        -- be unreachable - but an incomplete one describes selections that were never
        -- finished being made, and exporting from it would be worse than not exporting.
        Fail('manifest says the protocol run did not complete')
    else
        -- Inputs. Recomputed here rather than trusted, which is the entire point.
        local csv_now  = Fnv1a64Hex(ReadAll(_csv) or '')
        local prot_now = Fnv1a64Hex(ReadAll(_dir .. 'protocol.lua') or '')
        local fact_now = Fnv1a64Hex(table.concat(SCORE_FACTOR_KEYS, ','))
        if M.inputs.csv_hash ~= csv_now then
            Fail('corpus_scores.csv has changed since the protocol ran (%s -> %s)',
                M.inputs.csv_hash, csv_now)
        end
        if M.inputs.protocol_hash ~= prot_now then
            Fail('protocol.lua has changed since the protocol ran (%s -> %s)',
                M.inputs.protocol_hash, prot_now)
        end
        if M.inputs.factors_hash ~= fact_now then
            Fail('the factor set has changed since the protocol ran (%s -> %s)',
                M.inputs.factors_hash, fact_now)
        end

        -- Selections, both directions: a manifest entry this file does not expect is as
        -- much a disagreement as an expectation the manifest does not carry.
        local expect = {}
        for _, s in ipairs(SELECTIONS) do expect[s.inst] = s end
        local seen = {}
        for _, s in ipairs(M.selections) do
            seen[s.inst] = true
            local e = expect[s.inst]
            if not e then
                Fail('manifest selects %s, which SELECTIONS does not mention', s.inst)
            elseif e.candidate ~= s.candidate or e.scale ~= s.scale then
                Fail('%s: SELECTIONS says %s / %s, the protocol selected %s / %s'
                    .. ' - update SELECTIONS (and its reasoning) or rerun the protocol',
                    s.inst, e.candidate, e.scale, s.candidate, s.scale)
            end
        end
        for _, s in ipairs(SELECTIONS) do
            if not seen[s.inst] then
                Fail('SELECTIONS expects %s, which the manifest does not select', s.inst)
            end
        end

        -- STATUS is a PRODUCT judgment and deliberately not derived from gate_passed: all
        -- six ship, including three that fail, to get author feedback on the weak ones. So
        -- this reports the pairing rather than enforcing it - but an instrument with no
        -- status at all is a real omission.
        for _, s in ipairs(M.selections) do
            if not STATUS[s.inst] then Fail('%s has no entry in STATUS', s.inst) end
        end

        -- Per-tier reliability travels from the protocol to the artifact untouched. It is
        -- computed from OUT-OF-FOLD predictions, and this script refits on every row, so
        -- there is no honest way to recompute it here - carrying it is the only correct
        -- option. Missing entries are fatal rather than skipped: the product's reliability
        -- note is the one place an author is told where the model is weak, and shipping a
        -- model with that silently absent is worse than not shipping.
        for _, s in ipairs(M.selections) do
            if type(s.reliability) ~= 'table' then
                Fail('%s carries no reliability table - rerun the protocol', s.inst)
            else
                MANIFEST_RELIABILITY[s.inst] = s.reliability
            end
        end

        if _errors > 0 then
            io.write('\nRefusing to export. See dev/calibration/README.md.\n')
            os.exit(1)
        end

        io.write(('manifest: %d selections, inputs verified\n'):format(#M.selections))
        for _, s in ipairs(M.selections) do
            io.write(('          %-10s %-40s %-10s gate %s / status %s\n'):format(
                s.inst, s.candidate, s.scale,
                s.gate_passed and 'PASS' or 'fail', STATUS[s.inst]))
        end
    end
end

io.write('\n')

local models = {}

for _, sel in ipairs(SELECTIONS) do
    io.write(('==================  %s  ==================\n'):format(sel.inst:upper()))

    -- Resolve the candidate by name out of protocol.lua rather than retyping its factors.
    local cand
    for _, c in ipairs(CandidatesFor(sel.inst)) do
        if c.name == sel.candidate then cand = c break end
    end
    local scale
    for _, s in ipairs(SCALES) do
        if s.name == sel.scale then scale = s break end
    end

    if not cand then
        Fail('protocol.lua declares no candidate named %q for %s', sel.candidate, sel.inst)
    elseif not scale then
        Fail('protocol.lua declares no scale named %q', sel.scale)
    elseif not DIFFICULTY_SCALE_INV[sel.scale] then
        Fail('lib/reaper_difficulty_predict.lua cannot invert scale %q', sel.scale)
    else
        -- Every declared factor must exist exactly once and be numeric everywhere.
        local seen = {}
        for _, k in ipairs(cand.keys) do
            if not pos[k] then Fail('%s: factor %s is not in SCORE_FACTOR_KEYS', sel.inst, k) end
            if seen[k] then Fail('%s: factor %s is declared twice', sel.inst, k) end
            -- Appended by BuildRows, so a candidate declaring one too would fit that
            -- origin flag twice and shift every later coefficient.
            if k:match('^is_') then
                Fail('%s: %s is appended, not declared', sel.inst, k)
            end
            seen[k] = true
        end

        local d = Collect(csv, sel.inst)
        local target, extra, weird = Partition(d, sel.inst)

        io.write(('  candidate        : %s / %s  (%d features)\n')
            :format(cand.name, scale.name, #cand.keys))
        -- Per origin. "+ 60 lego" would be a lie now that extra pools two origins, and a
        -- wrong provenance line in the export log is exactly the kind of thing nobody
        -- rechecks once it looks plausible.
        local aux_parts = {}
        for _, a in ipairs(PROTOCOL.AUX_ORIGINS) do
            local n = 0
            for _, ix in ipairs(extra) do if d.origins[ix] == a.origin then n = n + 1 end end
            if n > 0 then
                aux_parts[#aux_parts + 1] = ('%d %s at weight %.2f'):format(n, a.origin, a.weight)
            end
        end
        io.write(('  training rows    : %d rb3_dlc + %s  (%d disputed held out)\n')
            :format(#target,
                    #aux_parts > 0 and table.concat(aux_parts, ' + ') or 'no auxiliary rows',
                    #weird))

        if #target == 0 then
            Fail('%s: no development rows', sel.inst)
        else
            local ridge, grid = ChooseRidgePooled(d, target, extra, sel.inst,
                                                  cand.keys, pos, scale)
            io.write('  pooled inner-fold error per ridge (lower is better):\n')
            for _, row in ipairs(grid) do
                io.write(('    %-8g %s%s\n'):format(
                    row.ridge,
                    row.err and ('%.6f'):format(row.err) or '(no fit)',
                    row.ridge == ridge and '   <- selected' or ''))
            end

            -- The final fit: one pass over every allowed training row at that ridge.
            local X, ys, ws = {}, {}, {}
            BuildRows(d, target, cand.keys, pos, scale, X, ys, ws)
            BuildRows(d, extra,  cand.keys, pos, scale, X, ys, ws)
            local fit, ferr = MultiFit(X, ys, ridge, ws)

            if not fit then
                Fail('%s: final fit failed (%s)', sel.inst, tostring(ferr))
            else
                local rank_lo, rank_hi = RankRange(d, target)
                local keys = {}
                for i, k in ipairs(cand.keys) do keys[i] = k end
                for _, flag in ipairs(AuxFlagKeys()) do keys[#keys + 1] = flag end

                models[#models + 1] = {
                    inst      = sel.inst,
                    candidate = cand.name,
                    scale     = scale.name,
                    status    = STATUS[sel.inst] or 'experimental',
                    keys      = keys,
                    mean      = fit.mean,
                    sd        = fit.sd,
                    coefs     = fit.coefs,
                    intercept = fit.intercept,
                    ridge     = ridge,
                    rank_lo   = rank_lo,
                    rank_hi   = rank_hi,
                    bounds    = FactorBounds(d, target, cand.keys, pos),
                    conc      = ConcentrationThresholds(d, target, pos),
                    corr      = FactorCorrelations(d, target, cand.keys, pos),
                    n_target  = #target,
                    n_aux     = #extra,
                    -- Straight from the manifest, never recomputed here: it comes from the
                    -- protocol's out-of-fold predictions, and this file refits on ALL rows
                    -- and so has no honest way to produce it. The protocol decides; the
                    -- exporter obeys.
                    reliability = MANIFEST_RELIABILITY[sel.inst],
                }

                -- Self-check: the artifact, applied through the shipped predictor, must
                -- reproduce this fit on every training row. Catches a factor-order slip
                -- between what was fitted and what was written down, which is otherwise
                -- invisible - the numbers all look plausible.
                local m = models[#models]
                local worst = 0
                for _, i in ipairs(target) do
                    local factors = {}
                    for _, k in ipairs(cand.keys) do factors[k] = d.feats[i][pos[k]] end
                    local got = DifficultyPredictRank(m, factors)
                    local row = {}
                    for j, k in ipairs(cand.keys) do row[j] = d.feats[i][pos[k]] end
                    -- One zero per auxiliary origin, matching BuildRows. Derived rather
                    -- than a literal: a fixed count silently shortens the vector the
                    -- moment another origin is declared, and ApplyFit then reads past
                    -- the end of it.
                    for _ = 1, #PROTOCOL.AUX_ORIGINS do row[#row + 1] = 0 end
                    local want = scale.inv(ApplyFit(row, fit))
                    want = math.max(rank_lo, math.min(rank_hi, want))
                    local diff = math.abs(got - want)
                    if diff > worst then worst = diff end
                end
                io.write(('  ridge %-8g  rank clamp %d..%d  self-check max diff %.2e\n')
                    :format(ridge, rank_lo, rank_hi, worst))
                if worst > 1e-9 then
                    Fail('%s: artifact does not reproduce the fit (%.3e)', sel.inst, worst)
                end
            end
        end
    end
    io.write('\n')
end

if _errors > 0 then
    io.write(('Refusing to write the artifact: %d error(s) above.\n'):format(_errors))
    os.exit(1)
end

----------------------------------------------------------------------
-- Write
----------------------------------------------------------------------

local out = {}
local function W(s) out[#out + 1] = s end

W([[
-- GENERATED FILE - DO NOT EDIT BY HAND.
--
-- Written by dev/calibration/export_production_models.lua from
-- dev/calibration/corpus_scores.csv. Re-run the exporter to change anything here; a hand
-- edit would be silently overwritten and, worse, would not be reproducible from the
-- corpus it claims to describe.
--
-- One frozen model per instrument: the candidate the locked protocol selected, refit once
-- on every row it was allowed to train on. Apply with DifficultyPredictRank in
-- lib/reaper_difficulty_predict.lua - the coefficients are in STANDARDIZED units and mean
-- nothing applied to raw factors by hand.
--
-- Field notes:
--   keys        factor order. The TRAILING entries are the training-time origin flags,
--               one per PROTOCOL.AUX_ORIGINS entry and named is_<origin>; product
--               predictions always pass 0 for every one of them.
--   mean / sd   standardization statistics from the fit, over ALL training rows including
--               the down-weighted lego ones. Only valid paired with these coefs.
--   rank_lo/hi  observed rank range of the rb3_dlc training rows. The final rank is
--               clamped to it; individual factors never are.
--   bounds      per-factor min/max/p90 over the rb3_dlc training rows - the support the
--               suggestion is honest about. A DIFFERENT row set from mean/sd, on purpose:
--               every prediction is made on the RB3 scale.
--   conc        concentration thresholds (p90) for the "difficulty is concentrated in a
--               short passage" note. Measured per instrument because a single cutoff is
--               wrong - bass and drums never mark a solo at all.
--   corr        pairwise correlation between this model's own factors, over the same
--               rb3_dlc rows as bounds, emitted only for pairs at |r| >= 0.70. Lets the
--               explanation panel drop a "notable property" that merely restates one it
--               has already shown - which factors duplicate is per-instrument, so it is
--               measured rather than hand-grouped. Key is the two factor names joined by
--               '|'; readers must try both orderings.
--   status      model maturity for the UI badge. Describes validation against noisy
--               official ranks, NOT the probability that a prediction is correct.
--   n_target    rb3_dlc rows this model was fitted on - the development set.
--   n_aux       auxiliary-origin rows (Lego plus the RB2 disc export) that always train
--               at their declared weight and are never predicted. Called n_lego before
--               schema 4, by which point it had counted two origins for a while.
--   reliability per-tier accuracy in the PREDICTED-tier conditional, from the protocol's
--               OUT-OF-FOLD predictions - keyed by the tier the model produced, not the
--               tier a chart officially holds. n_pred/ok_pred answer "how far out is a
--               prediction of this tier?"; `actual` holds the full distribution of
--               official tiers behind those predictions; n_act is how many charts really
--               sit at this tier, which against n_pred is how far the model reaches.
--               The report's per-tier table is the OPPOSITE conditional and reads much
--               worse at the extremes - see TierReliability in protocol.lua for why a
--               product note built on that one would mislead.
]])

W(('\nRB_DIFFICULTY_MODELS_SCHEMA = %d\n'):format(SCHEMA))
W(('RB_DIFFICULTY_MODELS_CSV_FINGERPRINT = %d\n'):format(Fingerprint(csv.header_line)))
W('\nRB_DIFFICULTY_MODEL_ORDER = {\n')
for _, m in ipairs(models) do W(('    %s,\n'):format(Quote(m.inst))) end
W('}\n\nRB_DIFFICULTY_MODELS = {\n')

for _, m in ipairs(models) do
    W(('\n[%s] = {\n'):format(Quote(m.inst)))
    W(('    candidate = %s,\n'):format(Quote(m.candidate)))
    W(('    scale     = %s,\n'):format(Quote(m.scale)))
    W(('    status    = %s,\n'):format(Quote(m.status)))
    W(('    ridge     = %s,\n'):format(Num(m.ridge)))
    W(('    rank_lo   = %s,\n'):format(Num(m.rank_lo)))
    W(('    rank_hi   = %s,\n'):format(Num(m.rank_hi)))
    W(('    intercept = %s,\n'):format(Num(m.intercept)))
    W(('    n_target  = %d,\n'):format(m.n_target))
    W(('    n_aux     = %d,\n'):format(m.n_aux))

    W('    keys = {\n')
    for _, k in ipairs(m.keys) do W(('        %s,\n'):format(Quote(k))) end
    W('    },\n')

    for _, field in ipairs({ 'mean', 'sd', 'coefs' }) do
        W(('    %s = {\n%s\n    },\n'):format(field, NumList(m[field], '        ')))
    end

    W('    bounds = {\n')
    for _, k in ipairs(m.keys) do
        local b = m.bounds[k]
        if b then
            W(('        [%s] = { min = %s, max = %s, p90 = %s },\n')
                :format(Quote(k), Num(b.min), Num(b.max), Num(b.p90)))
        end
    end
    W('    },\n')

    W('    conc = {\n')
    for _, k in ipairs({ 'solo_change_ratio', 'density_ratio' }) do
        if m.conc[k] then W(('        %s = %s,\n'):format(k, Num(m.conc[k]))) end
    end
    W('    },\n')

    -- SORTED, because pairs() order is not deterministic in Lua and this file has to be
    -- byte-identical across runs - that reproducibility is what makes a regenerated
    -- artifact reviewable as a diff.
    local pair_keys = {}
    for k in pairs(m.corr) do pair_keys[#pair_keys + 1] = k end
    table.sort(pair_keys)
    W('    corr = {\n')
    for _, k in ipairs(pair_keys) do
        W(('        [%s] = %s,\n'):format(Quote(k), Num(m.corr[k])))
    end
    W('    },\n')

    -- Integer keys 0..6 in ascending order, so this stays byte-stable like everything
    -- else here. Emitted last because it is the largest per-model block after the
    -- coefficients and reads better below them.
    W('    reliability = {\n')
    for t = 0, 6 do
        local rt = m.reliability and m.reliability[t]
        if rt then
            local acts = {}
            for a = 0, 6 do
                local c = rt.actual and rt.actual[a]
                if c then acts[#acts + 1] = ('[%d]=%d'):format(a, c) end
            end
            W(('        [%d] = { n_act = %d, n_pred = %d, ok_pred = %d, actual = { %s } },\n')
                :format(t, rt.n_act, rt.n_pred, rt.ok_pred, table.concat(acts, ', ')))
        end
    end
    W('    },\n')

    W('},\n')
end

W('}\n')

local f = io.open(_out, 'w')
if not f then
    io.write(('Could not write %s\n'):format(_out))
    os.exit(1)
end
f:write(table.concat(out))
f:close()

io.write(('Wrote %s\n'):format(_out))
io.write(('%d models, schema %d.\n'):format(#models, SCHEMA))
io.write('\nRe-running on the same CSV must produce a byte-identical file.\n')
