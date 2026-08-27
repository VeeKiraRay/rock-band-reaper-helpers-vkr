-- Rock Band rank -> difficulty tier conversion.
--
-- PURE: no r.*, no S. Ported from the community InstrumentDifficulty.ts, which
-- is the authoritative source for these thresholds. dev/tests re-asserts every
-- row against a local copy of it and FAILS if that copy is absent, so the
-- suggester suite needs one. Keys match songs.dta's own rank key
-- names (see DTA_RANK_KEYS in dev/calibration/songs_dta.lua) so a rank can be
-- converted without a translation step.
--
-- Shared by the calibration harness and the general helper's Metadata >
-- Difficulty view. dev/calibration/rank_tiers.lua is a one-line loader kept so
-- the calibration entry points need no edits.
--
-- The numbers below are a hand transcription and are re-asserted against the
-- source file by dev/tests/difficulty_suggester.lua.
--
-- ---------------------------------------------------------------------------
-- Tier numbering
--
-- Two conventions exist and they differ by one. This module uses the DISPLAYED
-- one, matching how the game shows difficulty and how the design doc is written:
--
--   0 Warmup   1 Apprentice   2 Solid   3 Moderate
--   4 Challenging   5 Nightmare   6 Impossible
--
-- "No part" is not a tier here - it is nil, because a song without the
-- instrument has no difficulty rather than the lowest one. (The .ts file's own
-- doc comment numbers things 0..7 with 0 = No Part, which is the same
-- information shifted by one. Never mix the two.)
--
-- diffN is the rank at which tier N begins, so a rank above 0 but below diff1
-- is Warmup / tier 0.
--
-- The drums row's diff5 is 345. The source file briefly carried 245, which made
-- the Challenging band 3 rank points wide (242-244): on the 155-song corpus that
-- put 0 charts in Challenging and 26 in Nightmare. 345 restores the
-- increasing-gap shape every other instrument has (27 27 64 103 103) and was
-- confirmed by the source's author.
-- ---------------------------------------------------------------------------

RANK_TIER_THRESHOLDS = {
    guitar      = { 139, 176, 221, 267, 333, 409 },
    bass        = { 135, 181, 228, 293, 364, 436 },
    drum        = { 124, 151, 178, 242, 345, 448 },
    vocals      = { 132, 175, 218, 279, 353, 427 },
    keys        = { 153, 211, 269, 327, 385, 443 },
    real_keys   = { 153, 211, 269, 327, 385, 443 },
    real_guitar = { 150, 208, 267, 325, 384, 442 },
    real_bass   = { 150, 208, 267, 325, 384, 442 },
    band        = { 165, 215, 243, 267, 292, 345 },
}

-- Indexed 0-6 to match the tier numbers themselves.
TIER_NAMES = {
    [0] = 'Warmup', [1] = 'Apprentice', [2] = 'Solid', [3] = 'Moderate',
    [4] = 'Challenging', [5] = 'Nightmare', [6] = 'Impossible',
}

-- Returns the 0-6 tier, or nil when the song has no such part (rank 0 or
-- absent) or the instrument is unknown.
function TierForRank(inst, rank)
    local t = RANK_TIER_THRESHOLDS[inst]
    if not t or not rank or rank <= 0 then return nil end
    local tier = 0
    for i = 1, 6 do
        if rank >= t[i] then tier = i end
    end
    return tier
end

function TierName(tier)
    if tier == nil then return 'No Part' end
    return TIER_NAMES[tier] or ('?' .. tostring(tier))
end

----------------------------------------------------------------------
-- Where inside its tier a rank sits
--
-- The suggestion view needs this because the tier alone hides how close a call
-- was: a guitar chart at 267 and one at 332 are both Challenging, and only one
-- of them would change tier if the model were a few points out.
--
-- BOTH END BANDS ARE OPEN and have to be closed by hand, in different ways:
--
--   Tier 0 runs from `rank_lo` - the lowest rank the model can produce - for
--   exactly the reason tier 6 stops at the observed maximum. A position inside
--   an open band is only meaningful relative to what the tool can actually
--   say. Measured from 1 instead, every floor-clamped Warmup chart computes
--   0.85-0.97 and reads as almost-Apprentice when it in fact fell off the
--   BOTTOM of the scale: the drum floor is 120 against a tier-1 threshold of
--   124, so 97% of a band the model can only reach the last 4% of. That was
--   also the true cause of a false "near the upper tier boundary" on clamped
--   drum charts, which DifficultyWarnings had to suppress by hand.
--
--   With no rank_lo the band still starts at 1, which is the honest answer
--   when the caller has no model to ask. Rank 0 is never the bottom of tier 0:
--   it means the song has no such part, which TierForRank reports as nil.
--
--   Tier 6 has no upper threshold at all. `rank_hi` closes it, and the honest
--   value is the highest rank the model was fitted against - the exported
--   observed maximum - because a position inside Impossible is only meaningful
--   relative to the hardest chart anyone has actually labelled. With no
--   rank_hi, the band is assumed as wide as the one below it, which is the
--   least-surprising extrapolation for a ladder whose gaps otherwise only
--   widen (27 27 64 103 103). Say so in the UI rather than implying precision
--   the threshold table does not carry.
----------------------------------------------------------------------

-- Returns lo, hi for a tier's rank band: lo inclusive, hi exclusive except on
-- tier 6, where it is inclusive because nothing lies above it. nil for an
-- unknown instrument or a tier outside 0-6.
function TierBand(inst, tier, rank_hi, rank_lo)
    local t = RANK_TIER_THRESHOLDS[inst]
    if not t or not tier or tier < 0 or tier > 6 then return nil end
    -- Never return a band the rank cannot reach: a rank_lo at or above the tier-1
    -- threshold would invert the band, so fall back to 1 rather than trust it.
    local lo = t[tier]
    if tier == 0 then
        lo = (rank_lo and rank_lo > 0 and rank_lo < t[1]) and rank_lo or 1
    end
    if tier < 6 then return lo, t[tier + 1] end
    -- Never return a band the rank itself falls outside: an observed maximum
    -- from a corpus that happens to exclude this chart would otherwise produce
    -- a position above 1.
    local hi = rank_hi
    if not hi or hi <= lo then hi = lo + (t[6] - t[5]) end
    return lo, hi
end

-- Position of a rank inside its own tier, 0 at the bottom edge and 1 at the
-- top. nil whenever TierForRank is nil, so callers test one thing.
function TierPosition(inst, rank, rank_hi, rank_lo)
    local tier = TierForRank(inst, rank)
    if not tier then return nil end
    -- math.min on the floor for the same reason math.max guards the ceiling: a
    -- chart below the model's own observed minimum must read 0, not below it.
    local lo, hi = TierBand(inst, tier, math.max(rank_hi or 0, rank),
                            rank_lo and math.min(rank_lo, rank) or nil)
    if not lo or hi <= lo then return 0 end
    local p = (rank - lo) / (hi - lo)
    if p < 0 then return 0 end
    if p > 1 then return 1 end
    return p
end
