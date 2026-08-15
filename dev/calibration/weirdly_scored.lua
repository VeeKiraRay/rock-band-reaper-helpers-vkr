-- Songs whose official rank is believed to be a BAD LABEL rather than a rating we
-- happen to disagree with.
--
-- PURE: no r.*, no S. Read by run_calibration_analysis_vkr.lua, which excludes these
-- rows from coefficient fitting exactly as it excludes the greenday origin - and
-- which always reports the gate BOTH WITH AND WITHOUT them, so nothing can improve
-- silently.
--
-- Status: calibration pilot, dev-only. THE LIST IS DELIBERATELY EMPTY. The mechanism
-- exists before it is needed so that the criteria below are written down while no
-- specific song is at stake.
--
-- ---------------------------------------------------------------------------
-- Why this is the most dangerous file in the calibration pilot
--
-- Every entry added here makes the reported accuracy go up. That is not a benefit,
-- it is the hazard: a list that grows whenever the model is wrong stops being a
-- record of bad labels and becomes a record of our failures, and the metrics it
-- produces mean nothing. The corpus is the only check on the model; a list that can
-- edit the corpus can defeat the check entirely.
--
-- So the bar is deliberately hard to clear:
--
--   1. CORRUPT, NOT UNFAIR. Only for a label that looks like a mistake - a
--      data-entry error, a rank that contradicts the chart's own content. A rank
--      that is defensible but debated is a MODELLING problem, and excluding it
--      throws away the evidence needed to solve it.
--
--   2. NOT IN THE SAME SESSION IT APPEARED AS A RESIDUAL. If a song is added the
--      moment the model misses it, the justification is unfalsifiable no matter how
--      it is worded. Prior, independent knowledge of a problem is what counts.
--
--   3. AN EXTERNAL, WRITTEN JUSTIFICATION PER ENTRY. Not "the model says otherwise".
--      Something a reader who has never seen our residuals could check.
--
--   4. CAP AT ABOUT 2% OF THE CORPUS (4 songs at 205). Reaching the cap is a signal
--      that the label noise is systematic and should be modelled or accepted, not
--      excised song by song.
--
-- WORKED EXAMPLE OF SOMETHING THAT DOES *NOT* BELONG HERE - webuiltthiscity,
-- guitar, rank 418. It is the corpus's single worst guitar miss, it is a long slow
-- song whose difficulty sits almost entirely in one closing solo, and the community
-- has argued the rating is odd. All true, and it still fails the bar:
--
--   * The rank is not corrupt. Harmonix rated guitar 418 and bass 203 on the same
--     song, and the guitar chart does carry an authored solo (pitch 103) over 11% of
--     its length that the bass chart has no counterpart for. The label is internally
--     consistent with the chart; what is disputed is the PHILOSOPHY of rating a song
--     by its hardest passage. That is a rating we should learn to reproduce or
--     deliberately decline to reproduce, not a typo.
--   * It is the best diagnostic case we have. It is the clearest instance of the
--     concentrated-difficulty pattern that the solo factors were built to capture, so
--     excluding it would remove the evidence for the fix.
--   * Excluding it would take guitar misses from 1 to 0. Any exclusion whose main
--     visible effect is deleting the one failing case has to be assumed suspect.
--
-- Kept as a worked example precisely because it is a *near* miss: the tempting cases
-- will all look like this one.
-- ---------------------------------------------------------------------------

-- Keyed 'shortname\0rank_key', since a song can be mislabelled on one instrument and
-- fine on another. Values are the written justification.
WEIRDLY_SCORED = {
    -- ['someshortname\0guitar'] = 'rank 12 with 1400 expert gems; contradicts the
    --                              chart, likely a dropped digit',
}

-- True when this (song, instrument) pair is excluded from fits.
function IsWeirdlyScored(shortname, rank_key)
    if not shortname or not rank_key then return false end
    return WEIRDLY_SCORED[shortname .. '\0' .. rank_key] ~= nil
end

function WeirdlyScoredReason(shortname, rank_key)
    if not shortname or not rank_key then return nil end
    return WEIRDLY_SCORED[shortname .. '\0' .. rank_key]
end

-- How many entries the list holds, so the analysis can report the cap.
function WeirdlyScoredCount()
    local n = 0
    for _ in pairs(WEIRDLY_SCORED) do n = n + 1 end
    return n
end
