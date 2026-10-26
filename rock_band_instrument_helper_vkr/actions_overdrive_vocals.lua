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
-- Requires (globals): OD_QN_EPS (overdrive_read.lua)

-- opts:
--   every       vocal phrases per overdrive phrase (5)
--   keepout_od  measures at the end with no overdrive (8)
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
    local function Ok(i)
        local ph = cands[i]
        return ph ~= nil and (not v.harm_present or ph.harm ~= nil)
    end

    -- Start mid-cycle (the 3rd phrase of 5) so the first and last overdrive sit
    -- about equally far from the ends of the song.
    local i = math.floor((K + 1) / 2)
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
            i = pick + K
        else
            plan.unplaced[#plan.unplaced + 1] = cands[i]
            i = i + K
        end
    end
    return plan
end
