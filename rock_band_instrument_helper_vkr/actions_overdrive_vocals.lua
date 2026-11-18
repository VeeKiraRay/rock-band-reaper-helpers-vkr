-- Overdrive tab: vocal overdrive planning.
--
-- Vocal overdrive is a copy of a phrase marker (105) up to 116, and the two must line
-- up exactly. The doc's rate is one overdrive phrase per 5 vocal phrases (the corpus
-- measures 4.6-4.8), none in the last 8 measures, and vocals are never part of a
-- unison.
--
-- HARM1 CARRIES IDENTICAL OVERDRIVE. The game accepts different phrases on the two
-- parts, but Rock Band 3 has a visual bug in harmonies if the parts differ. HARM1's
-- phrase markers do not always match PART VOCALS' - in the reference corpus they
-- differ somewhere in 60-80% of songs - usually at a few isolated phrases. So a
-- phrase can only carry overdrive when HARM1 has a phrase with exactly the same span;
-- when the cadence lands on one that does not, it moves one phrase earlier or later
-- and continues from there. When neither neighbour works either, the slot is left
-- empty and reported.
--
-- Deliberately no "interest" scoring here: vocals run first, placed by cadence alone,
-- and their spans then fence off the instrument planner.
--
-- Pure over the model from OdBuildModel.
-- Requires (globals): OD_QN_EPS, OdVocalOdProblem (overdrive_read.lua), SCORE_RULES,
--                     ScoreBeatAt (lib/reaper_score_sim.lua, at call time)

-- opts:
--   every       vocal phrases per overdrive phrase (5)
--   keepout_od  measures at the end with no overdrive (8)
--   beats       the BEAT track's beats in QN (ScoreReadBeats), for the room before the
--               vocals' last note
--   break_bars  count every this many full bars with no singing as one sung phrase in
--               the cadence (nil = off, the official charts' way)
--
-- Returns { phrases = { phrase } (model.vocal.phrases entries), unplaced = { phrase },
--           candidates = n }. A phrase entry carries take/sppq/eppq and, when HARM1
-- exists, `harm` - its identical HARM1 phrase.
function OdPlanVocals(model, opts)
    local v = model.vocal
    local plan = { phrases = {}, unplaced = {}, candidates = 0 }
    if not (v and v.present) then return plan end

    local last_b = #model.bars - (opts.keepout_od or 8)
    if last_b < 1 then return plan end
    local limit = model.bars[last_b].qn_e

    -- Only phrases that are sung (an empty phrase marker scores nothing) and end
    -- before the keep-out. The model's bars stop at any [coda], so this also keeps
    -- vocal overdrive out of a Big Rock Ending.
    local cands = {}
    for _, ph in ipairs(v.phrases) do
        if ph.has_notes and ph.e <= limit + OD_QN_EPS then cands[#cands + 1] = ph end
    end
    plan.candidates = #cands

    local K = math.max(2, opts.every or 5)
    -- Room before the vocals' own last note: the 8 beats of overdrive a phrase gives
    -- (0.251 of a meter; SCORE_RULES) must fit before the singing stops, or it can never
    -- be fully spent - Validate's "too close to the end" advice. Vocals often end well
    -- before the song (an instrumental outro), which the keep-out above does not see.
    -- PART VOCALS against its own notes; HARM1 against every harmony part's, since any
    -- singer can deploy. Counted in BEAT-track beats (opts.beats, what drains
    -- overdrive); with no BEAT track, quarter notes (ScoreBeatAt).
    local function Last(list)
        local q
        for _, n in ipairs(list or {}) do if not q or n.qn > q then q = n.qn end end
        return q
    end
    local need = SCORE_RULES.od_phrase * SCORE_RULES.deploy_beats
    local last_solo = Last(v.sung)
    local last_harm = v.harm_present and Last(v.harm_any or v.harm_sung) or nil
    local beats = opts.beats or {}
    local function Left(last, e) return ScoreBeatAt(beats, last) - ScoreBeatAt(beats, e) end
    local function Room(ph)
        if last_solo and Left(last_solo, ph.e) < need - OD_QN_EPS then return false end
        if last_harm and Left(last_harm, ph.e) < need - OD_QN_EPS then return false end
        return true
    end
    -- Out of the candidates altogether, like the keep-out: the cadence then never lands
    -- on one, so no slot is reported unplaced for it.
    local roomy = {}
    for _, ph in ipairs(cands) do if Room(ph) then roomy[#roomy + 1] = ph end end
    cands = roomy
    plan.candidates = #cands
    -- Magma checks each track's overdrive against that track's own notes too
    -- (OdVocalOdProblem): a HARM1 phrase nobody in HARM1-3 sings in would be refused
    -- even with markers matching. Hand-built models without note lists skip it.
    local function Ok(i)
        local ph = cands[i]
        if ph == nil then return false end
        if v.sung and OdVocalOdProblem(ph, v.phrases, v.sung) then return false end
        if v.harm_present then
            if ph.harm == nil then return false end
            if v.harm_sung and OdVocalOdProblem(ph.harm, v.harm_phrases, v.harm_sung, v.harm_any) then
                return false
            end
        end
        return true
    end

    -- Counted position of each candidate: one per sung phrase, plus (opts.break_bars,
    -- "Count long breaks in OD spacing") one per break_bars full bars with no singing
    -- before it - so after a long break the next overdrive comes sooner. Without it the
    -- position is the phrase's index (official charts space by sung phrases only: the
    -- same median distance with or without a long break).
    local pos = {}
    for k, ph in ipairs(cands) do
        local extra = 0
        if opts.break_bars and k > 1 then
            local full = 0
            for _, bar in ipairs(model.bars) do
                if bar.qn_s >= cands[k - 1].e - OD_QN_EPS and bar.qn_e <= ph.s + OD_QN_EPS then
                    full = full + 1
                end
            end
            extra = full // opts.break_bars
        end
        pos[k] = (k > 1 and pos[k - 1] or 0) + 1 + extra
    end
    -- The first candidate at or after counted position `target`, never the one right
    -- after `after` (a sung phrase always lies between two overdrive phrases).
    local function At(target, after)
        for k = (after or 0) + 2, #cands do
            if pos[k] >= target then return k end
        end
        return #cands + 1
    end

    -- Start mid-cycle (the 3rd phrase of 5) so the first and last overdrive sit
    -- about equally far from the ends of the song.
    local i = math.min(math.floor((K + 1) / 2), At(math.floor((K + 1) / 2), -1))
    local last_pick = -1
    while i <= #cands do
        local pick
        if Ok(i) then
            pick = i
        elseif i - 1 > last_pick + 1 and Ok(i - 1) then
            pick = i - 1
        elseif Ok(i + 1) then
            pick = i + 1
        end
        if pick then
            plan.phrases[#plan.phrases + 1] = cands[pick]
            last_pick = pick
            i = At(pos[pick] + K, pick)
        else
            plan.unplaced[#plan.unplaced + 1] = cands[i]
            i = At(pos[i] + K, i)
        end
    end
    return plan
end
