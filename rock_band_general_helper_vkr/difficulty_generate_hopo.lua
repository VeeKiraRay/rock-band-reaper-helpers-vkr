-- Difficulty > Generate: keep Expert's hammer-ons on Hard.
--
-- PURE: no r, no S. Shared by the action (actions_difficulty_generate.lua) and the offline
-- tools, like the planner.
--
-- Hard reduction can pull notes apart: 8th triplets rewritten as 8ths
-- (difficulty_generate_retime.lua) are 240 ticks apart instead of 160, past the HOPO
-- threshold, so a hammer-on run on Expert becomes strummed on Hard - harder than Expert
-- in feel. Each Hard note whose Expert note was a HOPO but which no longer is one gets a
-- force-HOPO marker (F above the tier, lo + 5). From the user's hand reduction of a
-- 210 BPM guitar solo, which this reproduces.
-- Hard only: the RBN docs say "Hopos should not be forced on Medium or Easy".

-- The HOPO threshold is set per song in Magma, in ticks at 480 PPQ: 170 by default, or 90,
-- 130 or 250. Each sits just above a note length - 90 a 16th triplet (80), 130 a 16th
-- (120), 170 an 8th triplet (160), 250 an 8th (240) - so it decides which spacing hammers
-- on. The RBN Guitar/Bass doc's "within 1/16th note" undersells the default. REAPER cannot
-- see the Magma setting, so callers pass it (threshold_ticks); 170 when they do not.
GEN5_HOPO_THRESHOLD_TICKS = 170
local function ThresholdQN(ticks) return (ticks or GEN5_HOPO_THRESHOLD_TICKS) / 480 end

local EPS = 0.005   -- QN

-- Does `ev` hammer on from `prev` without a marker? A single note, a color not in the
-- previous note or chord, starting within the threshold of it.
function Gen5IsAutoHopo(prev, ev, threshold_ticks)
    if not prev or #ev.offs ~= 1 then return false end
    if ev.qn - prev.qn > ThresholdQN(threshold_ticks) + EPS then return false end
    for _, o in ipairs(prev.offs) do
        if o == ev.offs[1] then return false end
    end
    return true
end

local function Covered(spans, qn)
    for _, sp in ipairs(spans or {}) do
        if qn >= sp.qn - EPS and qn < sp.qn_e - EPS then return true end
    end
    return false
end

-- Mark how each event of a tier plays there: ev.hopo = 'forced' under a force-HOPO marker,
-- 'auto' when it hammers on by itself and is not forced off, else nil. force_on /
-- force_off: { { qn, qn_e }... }, the tier's lo+5 / lo+6 markers. The planner carries the
-- flag to the tiers it builds.
function Gen5MarkHopos(events, force_on, force_off, threshold_ticks)
    for i, ev in ipairs(events) do
        if Covered(force_on, ev.qn) then
            ev.hopo = 'forced'
        elseif Gen5IsAutoHopo(events[i - 1], ev, threshold_ticks) and not Covered(force_off, ev.qn) then
            ev.hopo = 'auto'
        else
            ev.hopo = nil
        end
    end
    return events
end

-- Hard events (Expert's ev.hopo carried through, ev.rewritten on notes the fast-run
-- rewrite moved) -> force-HOPO spans { { qn, qn_e, count }... }, one per run of
-- consecutive notes that need one, from the first onset to the last note's end.
-- A note needs one when Hard would not hammer it on by itself but can (a single note, a
-- color the previous note does not have) and either
--   * Expert FORCED it - copied wherever the note survives; or
--   * Expert hammered it on by itself and Generate's rewrite pulled it apart (8th
--     triplets to 8ths), at most an 8th after the previous note, in a run of 2 or more.
--     Only rewritten notes: elsewhere a lost hammer-on becomes a strum, and markers are
--     used sparingly.
function Gen5ForceHopoSpans(events, threshold_ticks)
    local spans, cur = {}, nil
    for i, ev in ipairs(events) do
        local prev = events[i - 1]
        local need = prev and ev.hopo and #ev.offs == 1
                     and not Gen5IsAutoHopo(prev, ev, threshold_ticks)
                     and (ev.hopo == 'forced'
                          or (ev.rewritten and ev.qn - prev.qn <= 0.5 + EPS))
        if need then
            for _, o in ipairs(prev.offs) do
                if o == ev.offs[1] then need = false end
            end
        end
        if need then
            if cur then
                cur.qn_e, cur.count = ev.qn_e, cur.count + 1
            else
                cur = { qn = ev.qn, qn_e = ev.qn_e, count = 1, forced = false }
                spans[#spans + 1] = cur
            end
            if ev.hopo == 'forced' then cur.forced = true end
        else
            cur = nil
        end
    end
    -- A restored passage, not a lone note: one restored note between strums (a hammer-on
    -- across a bar line into a run of one color) is left to the author. Expert's forced
    -- notes are kept even alone - its author placed them.
    local out = {}
    for _, sp in ipairs(spans) do
        if sp.forced or sp.count >= 2 then out[#out + 1] = sp end
    end
    return out
end
