-- Camera shot priority: which stacked shot the game actually plays.
--
-- Source: the RBN2 "Camera And Lights" RBN/C3 documentation, sections
-- "Camera Shot Priority" and "Directed Cuts Priority".
--
-- Because only 4 band members can be on stage at once, and because keys
-- physically replaces a guitarist or bassist, authors stack several camera
-- shots on one tick so at least one of them fits whatever lineup the song
-- ends up with. When the camera system finds multiple shots at one time it
-- evaluates them in a fixed priority order and uses the one that most
-- closely matches the members present. The documented order runs from most
-- generic to most specific, and MORE SPECIFIC WINS: a higher rank in
-- CAM_PRIORITY beats a lower one. Directed cuts are always more specific
-- than any normal (coop) shot, so every directed rank beats every coop rank.
--
-- Good to know - engine fallbacks this module does NOT perform:
--
--   Generic shot fallback. If no stacked shot can be matched, the game
--   picks one of [coop_all_behind], [coop_all_far] or [coop_all_near]
--   (CAM_GENERIC_FALLBACK). A three-character shot ([coop_front_*]) may be
--   selected in such cases as well.
--
--   Duo to single fallback. If a band member is missing when a duo flag is
--   called, and there are no other stacked flags, the game converts the duo
--   cut to a single cut of the remaining member. The documentation states
--   this only for normal (coop) two-character shots - the directed cuts
--   section makes no equivalent claim for [directed_duo_*].
--
-- Both are game-side substitutions with more than one possible outcome, so
-- PickPriorityCameraEvent just returns nil when nothing fits and lets the
-- caller say so. The Venue Preview keeps showing the authored event and
-- explains the fallbacks in an alert rather than inventing a substitute
-- that is not on the timeline.
--
-- Requires: GetCoopRequiredInstruments, GetDirectedRequiredInstruments
--           (venue_awareness.lua) - called at use time, so load order
--           between the two files does not matter.
-- Pure: no r, ctx or S.
-- Globals exported: CAM_PRIORITY_TIERS, CAM_PRIORITY, CAM_GENERIC_FALLBACK,
--   CameraShotPriority, CameraShotFitsBand, PickPriorityCameraEvent

-- Tier grouping and within-tier order are verbatim from the documentation,
-- including its own headings, so this table reads as the reference. The
-- directed tier is one flat list there (no sub-headings), ordered least to
-- most specific. Its order differs from DIRECTED_POOL's in two places
-- (all_yeah/all_lt, duo_guitar/duo_bass) - the pool is authored for
-- spritesheet extraction, not priority, so neither list may be derived
-- from the other.
CAM_PRIORITY_TIERS = {
    {
        key    = 'coop_generic',
        label  = 'Generic four camera shots',
        events = {
            'coop_all_behind', 'coop_all_far', 'coop_all_near',
        },
    },
    {
        key    = 'coop_front',
        label  = 'Three character shots (no drum)',
        events = {
            'coop_front_behind', 'coop_front_near',
        },
    },
    {
        key    = 'coop_single',
        label  = 'One character standard shots',
        events = {
            -- Drums and vocals rank lowest here: they are always present,
            -- which makes their shots the more generic ones.
            'coop_d_behind', 'coop_d_near',
            'coop_v_behind', 'coop_v_near',
            'coop_b_behind', 'coop_b_near',
            'coop_g_behind', 'coop_g_near',
            'coop_k_behind', 'coop_k_near',
        },
    },
    {
        key    = 'coop_closeup',
        label  = 'One character closeups',
        events = {
            'coop_d_closeup_hand', 'coop_d_closeup_head',
            'coop_v_closeup',
            'coop_b_closeup_hand', 'coop_b_closeup_head',
            'coop_g_closeup_hand', 'coop_g_closeup_head',
            'coop_k_closeup_hand', 'coop_k_closeup_head',
        },
    },
    {
        key    = 'coop_duo',
        label  = 'Two character shots',
        events = {
            'coop_dv_near', 'coop_bd_near', 'coop_dg_near',
            'coop_bv_behind', 'coop_bv_near',
            'coop_gv_behind', 'coop_gv_near',
            'coop_kv_behind', 'coop_kv_near',
            'coop_bg_behind', 'coop_bg_near',
            'coop_bk_behind', 'coop_bk_near',
            'coop_gk_behind', 'coop_gk_near',
        },
    },
    {
        key    = 'directed',
        label  = 'Directed cuts',
        events = {
            'directed_all', 'directed_all_cam', 'directed_all_yeah', 'directed_all_lt',
            'directed_bre', 'directed_brej',
            'directed_crowd',
            'directed_drums', 'directed_drums_pnt', 'directed_drums_np',
            'directed_drums_lt', 'directed_drums_kd',
            'directed_vocals', 'directed_vocals_np', 'directed_vocals_cls',
            'directed_vocals_cam_pr', 'directed_vocals_cam_pt',
            'directed_stagedive', 'directed_crowdsurf',
            'directed_bass', 'directed_crowd_b', 'directed_bass_np',
            'directed_bass_cam', 'directed_bass_cls',
            'directed_guitar', 'directed_crowd_g', 'directed_guitar_np',
            'directed_guitar_cls', 'directed_guitar_cam_pr', 'directed_guitar_cam_pt',
            'directed_keys', 'directed_keys_cam', 'directed_keys_np',
            'directed_duo_drums', 'directed_duo_guitar', 'directed_duo_bass',
            'directed_duo_kv', 'directed_duo_gb', 'directed_duo_kb', 'directed_duo_kg',
        },
    },
}

-- The one place effective ranking diverges from the tier table above.
-- Documentation, "Two character shots", Note 1: "As an exception to the
-- rule, a single keys shot will prioritize over any combo shot." So these
-- are lifted out of their documented tiers to sit just above coop_duo -
-- above every two-character coop shot, still below every directed cut.
-- The note says "a single keys shot" without settling whether the closeups
-- count; they are included here, since a closeup is already the more
-- specific of the two single-keys tiers.
local KEYS_EXCEPTION = {
    'coop_k_behind', 'coop_k_near',
    'coop_k_closeup_hand', 'coop_k_closeup_head',
}

-- CAM_PRIORITY[bare_name] = integer rank, higher wins. This is the
-- EFFECTIVE order (keys exception applied); CAM_PRIORITY_TIERS stays the
-- documented grouping.
CAM_PRIORITY = {}

do
    local deferred = {}
    for _, n in ipairs(KEYS_EXCEPTION) do deferred[n] = true end

    local order = {}
    for _, tier in ipairs(CAM_PRIORITY_TIERS) do
        for _, name in ipairs(tier.events) do
            if not deferred[name] then order[#order + 1] = name end
        end
        -- Insert the held-back keys shots right after the last coop tier,
        -- keeping their relative order from the tiers above.
        if tier.key == 'coop_duo' then
            for _, name in ipairs(KEYS_EXCEPTION) do order[#order + 1] = name end
        end
    end

    for rank, name in ipairs(order) do CAM_PRIORITY[name] = rank end
end

-- What the game falls back to when nothing stacked at a tick can be matched.
CAM_GENERIC_FALLBACK = {
    '[coop_all_behind]', '[coop_all_far]', '[coop_all_near]',
}

local function BareName(msg)
    return msg:match('^%[(.-)%]$') or msg
end

-- Rank for a camera event, or nil if it is not a known camera shot.
-- Accepts either full event text ('[coop_g_near]') or a bare name.
function CameraShotPriority(msg)
    if not msg then return nil end
    return CAM_PRIORITY[BareName(msg)]
end

-- True if the shot can play with the current lineup, i.e. none of the
-- instruments it needs is in `muted` (muted[letter] = true covers both
-- muted and absent PART tracks - see GetMutedInstruments).
-- Non-camera events are never filtered out.
function CameraShotFitsBand(msg, muted)
    if not muted then return true end
    local req
    if msg:find('^%[coop_')         then req = GetCoopRequiredInstruments(msg)
    elseif msg:find('^%[directed_') then req = GetDirectedRequiredInstruments(msg)
    else return true end
    for _, ltr in ipairs(req) do
        if muted[ltr] then return false end
    end
    return true
end

-- Given the camera events stacked on one tick (array of { msg = ... }, in
-- MIDI order) and the current lineup, return the event the game would use:
-- the highest-priority shot that fits the band. Returns nil when none fits,
-- which is the caller's cue to report the engine fallbacks rather than
-- guess at them.
--
-- Ties and unranked events (a hand-typed shot outside the pools) keep the
-- pre-priority behaviour of later-in-MIDI-order winning, so a tick this
-- table says nothing about never resolves arbitrarily.
function PickPriorityCameraEvent(group, muted)
    if not group then return nil end
    local best, best_rank
    for _, ev in ipairs(group) do
        if CameraShotFitsBand(ev.msg, muted) then
            local rank = CameraShotPriority(ev.msg) or 0
            if not best or rank >= best_rank then
                best, best_rank = ev, rank
            end
        end
    end
    return best
end
