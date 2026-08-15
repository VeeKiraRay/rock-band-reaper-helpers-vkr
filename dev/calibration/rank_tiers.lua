-- Rock Band rank -> difficulty tier conversion.
--
-- PURE: no r.*, no S. Ported from _external_docs/InstrumentDifficulty.ts, which
-- is the authoritative copy for this repo. Keys match songs.dta's own rank key
-- names (see DTA_RANK_KEYS in songs_dta.lua) so a rank can be converted without
-- a translation step.
--
-- Status: calibration pilot, dev-only. Moves into lib/ if the pilot succeeds and
-- the tab gets built - at which point it needs a test asserting these numbers
-- against the source file rather than trusting this transcription.
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
