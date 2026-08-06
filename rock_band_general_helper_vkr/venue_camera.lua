-- Camera event generation: pools, weighted picking, coop/directed logic.
-- Requires: GetCoopRequiredInstruments, GetDirectedRequiredInstruments, r, S (globals)
-- Globals exported: COOP_POOL, COOP_LABELS, COOP_DISPLAY_GROUPS, DIRECTED_POOL,
--   DIRECTED_DISPLAY, DIRECTED_BRE_NAMES, PickRandom, JitteredInterval,
--   BuildSuffixPools, CategorizeCoopPool, WeightedPickCoopEvent, FindCompanion,
--   ComputeIdleState, ComputeSingState, GenerateCameraEvents,
--   CAM_INTERVAL_16THS, CAM_JITTER, CAM_START_MIN_16THS, CAM_START_MAX_16THS,
--   CAM_SHORT_START_MIN_16THS, CAM_SHORT_START_MAX_16THS

COOP_POOL = {
    '[coop_all_behind]', '[coop_all_far]', '[coop_all_near]',
    '[coop_front_behind]', '[coop_front_near]',
    '[coop_d_behind]', '[coop_d_near]', '[coop_d_closeup_hand]', '[coop_d_closeup_head]',
    '[coop_v_behind]', '[coop_v_near]', '[coop_v_closeup]',
    '[coop_b_behind]', '[coop_b_near]', '[coop_b_closeup_hand]', '[coop_b_closeup_head]',
    '[coop_g_behind]', '[coop_g_near]', '[coop_g_closeup_hand]', '[coop_g_closeup_head]',
    '[coop_k_behind]', '[coop_k_near]', '[coop_k_closeup_hand]', '[coop_k_closeup_head]',
    '[coop_dv_near]', '[coop_bd_near]', '[coop_dg_near]',
    '[coop_bv_behind]', '[coop_bv_near]',
    '[coop_gv_behind]', '[coop_gv_near]',
    '[coop_kv_behind]', '[coop_kv_near]',
    '[coop_bg_behind]', '[coop_bg_near]',
    '[coop_bk_behind]', '[coop_bk_near]',
    '[coop_gk_behind]', '[coop_gk_near]',
}

-- Display labels for the normal (coop) camera combo in Manual gen (keyed by bare name).
-- "Subject (Variation)": the coop_ prefix carries no information, the one-letter codes are
-- the instrument (d/v/b/g/k), and a two-letter code is a duo shot - named in the same
-- letter order the event uses, matching DIRECTED_LABELS' "Duo Guitar/Bass" style.
-- closeup_hand/closeup_head become (Hands)/(Head): there is no non-close-up hand or head
-- shot, so the word adds nothing. Vocals' plain closeup keeps (Close-up).
COOP_LABELS = {
    coop_all_behind='All (Behind)', coop_all_far='All (Far)', coop_all_near='All (Near)',
    coop_front_behind='Front (Behind)', coop_front_near='Front (Near)',
    coop_d_behind='Drums (Behind)', coop_d_near='Drums (Near)',
    coop_d_closeup_hand='Drums (Hands)', coop_d_closeup_head='Drums (Head)',
    coop_v_behind='Vocals (Behind)', coop_v_near='Vocals (Near)',
    coop_v_closeup='Vocals (Close-up)',
    coop_b_behind='Bass (Behind)', coop_b_near='Bass (Near)',
    coop_b_closeup_hand='Bass (Hands)', coop_b_closeup_head='Bass (Head)',
    coop_g_behind='Guitar (Behind)', coop_g_near='Guitar (Near)',
    coop_g_closeup_hand='Guitar (Hands)', coop_g_closeup_head='Guitar (Head)',
    coop_k_behind='Keys (Behind)', coop_k_near='Keys (Near)',
    coop_k_closeup_hand='Keys (Hands)', coop_k_closeup_head='Keys (Head)',
    coop_dv_near='Duo Drums/Vocals (Near)',
    coop_bd_near='Duo Bass/Drums (Near)',
    coop_dg_near='Duo Drums/Guitar (Near)',
    coop_bv_behind='Duo Bass/Vocals (Behind)', coop_bv_near='Duo Bass/Vocals (Near)',
    coop_gv_behind='Duo Guitar/Vocals (Behind)', coop_gv_near='Duo Guitar/Vocals (Near)',
    coop_kv_behind='Duo Keys/Vocals (Behind)', coop_kv_near='Duo Keys/Vocals (Near)',
    coop_bg_behind='Duo Bass/Guitar (Behind)', coop_bg_near='Duo Bass/Guitar (Near)',
    coop_bk_behind='Duo Bass/Keys (Behind)', coop_bk_near='Duo Bass/Keys (Near)',
    coop_gk_behind='Duo Guitar/Keys (Behind)', coop_gk_near='Duo Guitar/Keys (Near)',
}

-- [directed_bre] and [directed_brej] are intentionally excluded.
-- They are for BRE (Big Rock Ending) and must be placed manually.
DIRECTED_POOL = {
    '[directed_all]', '[directed_all_cam]', '[directed_all_lt]', '[directed_all_yeah]',
    '[directed_crowd]',
    '[directed_drums]', '[directed_drums_pnt]', '[directed_drums_np]',
    '[directed_drums_lt]', '[directed_drums_kd]',
    '[directed_vocals]', '[directed_vocals_np]', '[directed_vocals_cls]',
    '[directed_vocals_cam_pr]', '[directed_vocals_cam_pt]',
    '[directed_stagedive]', '[directed_crowdsurf]',
    '[directed_bass]', '[directed_crowd_b]', '[directed_bass_np]',
    '[directed_bass_cam]', '[directed_bass_cls]',
    '[directed_guitar]', '[directed_crowd_g]', '[directed_guitar_np]',
    '[directed_guitar_cls]', '[directed_guitar_cam_pr]', '[directed_guitar_cam_pt]',
    '[directed_keys]', '[directed_keys_cam]', '[directed_keys_np]',
    '[directed_duo_drums]', '[directed_duo_bass]', '[directed_duo_guitar]',
    '[directed_duo_kv]', '[directed_duo_gb]', '[directed_duo_kb]', '[directed_duo_kg]',
}

-- Display labels for the directed cut combo in the section editor (keyed by bare name)
DIRECTED_LABELS = {
    directed_all='All', directed_all_cam='All (Camera)', directed_all_lt='All (Long time)',
    directed_all_yeah='All (Yeah)', directed_crowd='Crowd',
    directed_drums='Drums', directed_drums_pnt='Drums (Point)',
    directed_drums_np='Drums (Not playing)', directed_drums_lt='Drums (Long time)',
    directed_drums_kd='Drums (Kick)',
    directed_vocals='Vocals', directed_vocals_np='Vocals (Not playing)',
    directed_vocals_cls='Vocals (Close-up)', directed_vocals_cam_pr='Vocals (Long pre-roll)',
    directed_vocals_cam_pt='Vocals (Long post-roll)',
    directed_stagedive='Stage Dive', directed_crowdsurf='Crowd Surf',
    directed_bass='Bass', directed_crowd_b='Crowd (Bass)',
    directed_bass_np='Bass (Not playing)', directed_bass_cam='Bass (Camera)',
    directed_bass_cls='Bass (Close-up)',
    directed_guitar='Guitar', directed_crowd_g='Crowd (Guitar)',
    directed_guitar_np='Guitar (Not playing)', directed_guitar_cls='Guitar (Close-up)',
    directed_guitar_cam_pr='Guitar (Long pre-roll)', directed_guitar_cam_pt='Guitar (Long post-roll)',
    directed_keys='Keys', directed_keys_cam='Keys (Camera)',
    directed_keys_np='Keys (Not playing)',
    directed_duo_drums='Duo Drums', directed_duo_bass='Duo Bass',
    directed_duo_guitar='Duo Guitar', directed_duo_kv='Duo Keys/Vocals',
    directed_duo_gb='Duo Guitar/Bass', directed_duo_kb='Duo Keys/Bass',
    directed_duo_kg='Duo Keys/Guitar',
    directed_bre ='Big Rock Ending',
    directed_brej='Big Rock Ending (Jump)',
}

DIRECTED_TIPS = {
    directed_all           = 'Shots where guitar, bass, keys and vocals interact. For example: jumping in the air, kicking towards camera or crowd or dramatically dropping to their knees.',
    directed_all_cam       = 'Like directed_all but typically lasts longer. For example: jumping in the air, kicking towards camera or crowd or dramatically dropping to their knees.',
    directed_all_lt        = 'A long panning shot of the entire band. It is more dynamic than standard (coop) camera shots like "all near" or "all far".',
    directed_all_yeah      = 'A very dramatic cut. For example: Singer points into the air in slow motion, pans to show the rest of the band in slow motion. On bigger venues and with no keys present, the guitarist leaps into the air and slides on their knees.',
    directed_crowd         = 'A dynamic shot that includes the crowd. For example: a wide stage shot or, on bigger venues, an individual shot with a few crowd members.',
    directed_drums         = 'The drummer hits the cymbals on their kit. Sometimes they twirl their sticks first.',
    directed_drums_pnt     = 'The drummer points to the camera with their sticks. Note: the drummer does not always play the drums in this animation.',
    directed_drums_np      = 'The drummer has a range of idle animations. For example: swirl drumsticks, stick tricks or motion to camera.',
    directed_drums_lt      = 'Longer directed drum shot.',
    directed_drums_kd      = "Close-up of the drummer’s kick pedal.",
    directed_vocals        = 'The vocalist has a wide variety of animations like for example: point into the air, point to the crowd, kick into the air or kick the camera.',
    directed_vocals_np     = 'The vocalist has a couple of idle actions: kick into the air or jump.',
    directed_vocals_cls    = 'A dramatic animation that includes: close-up of vocalist holding the mic, holding the mic with both hands, moving head back and forth or falling to the floor or to their knees holding the mic',
    directed_vocals_cam_pr = 'A large range of animations used for exciting vocal moments. For example: interact with crowd or camera or rock the mic. Longer pre-roll and shorter post-roll than [directed_vocals_cam_pt].',
    directed_vocals_cam_pt = 'A large range of animations used for exciting vocal moments. For example: interact with crowd or camera or rock the mic. Shorter pre-roll and longer post-roll than [directed_vocals_cam_pr].',
    directed_stagedive     = 'The vocalist runs off the stage and jumps into the crowd. This shot usually cuts away as soon as the vocalist jumps into the crowd.',
    directed_crowdsurf     = 'Like the stage dive but includes the vocalist crowd-surfing. Sometimes it shows the vocalist crowd-surfing without jumping off the stage.',
    directed_bass          = 'The bassist performs a wide variety of actions. For example: kick into the air, kick over the camera or bump camera with guitar. No knee sliding and less theatrical than guitar.',
    directed_crowd_b       = 'Bassist interacts with the audience, like high-fives, showing off for the crowd, etc. Good for more silent breakdown sections.',
    directed_bass_np       = 'The bassist performs a wide variety of idle actions. For example: kick, kick into the air (not camera).',
    directed_bass_cam      = 'The bassist shows off for the camera. This is usually more relaxed than the guitar player. For example: hit camera with instrument.',
    directed_bass_cls      = "Close-up of the bassist’s fretboard.",
    directed_guitar        = 'The guitarist performs a wide variety of actions. For example: slide on their knees, kick into the air, kick over the camera or bump camera with guitar.',
    directed_crowd_g       = 'Guitarist interacts with the audience, like high-fives, showing off for the crowd, etc. Good for more silent breakdown sections.',
    directed_guitar_np     = 'The guitarist performs a wide variety of idle actions. For example kick, kick into the air (not camera).',
    directed_guitar_cls    = "Close-up of the guitarist’s fretboard.",
    directed_guitar_cam_pr = 'A large range of guitar animations. For example: drop to the floor, show off to camera, show off for crowd. Longer pre-roll and shorter post-roll than [directed_guitar_cam_pt].',
    directed_guitar_cam_pt = 'There are a large range of guitar animations. For example: drop to the floor, show off to camera, show off for crowd. Shorter pre-roll and longer post-roll than [directed_guitar_cam_pr].',
    directed_keys          = 'The keyboard player jumps in the air or slams their hands on the keyboard.',
    directed_keys_cam      = 'The keyboardist rocks out and grooves.',
    directed_keys_np       = 'Very few animations available. The keyboard player rocks back and forth.',
    directed_duo_drums     = 'Drummer turns to the camera or interacts with it. Use only when the drummer is singing. It looks awkward if the drummer is not singing.',
    directed_duo_bass      = 'The bassist and vocalist interact. For example: they are jamming together, leaning into each other or bassist is singing into the mic.',
    directed_duo_guitar    = 'The guitarist and vocalist interact. For example: they are jamming together, leaning into each other or guitarist is singing into the mic.',
    directed_duo_kv        = 'Vocalist and keyboard player rock out together.',
    directed_duo_gb        = 'Guitarist and bassist jam out together.',
    directed_duo_kb        = 'Bassist and keyboard player rock out together.',
    directed_duo_kg        = 'Guitarist and keyboard player rock out together.',
    directed_bre           = 'Big Rock Ending camera cut. Author manually at the BRE section only.',
    directed_brej          = 'Big Rock Ending camera cut (jump variant). Author manually at the BRE section only.',
}

-- Phrase marker note; its own start/end is the vocal phrase's start/end. Shared with
-- actions_venue_sing_along.lua (loaded later) and the "Vocal phrase start" camera pacing mode.
RB3_PHRASE_PITCH = 105

-- Future S-field candidates for UI configuration sliders:
CAM_INTERVAL_16THS        = 24    -- ~1.5 measures between coop cuts (4/4)
CAM_JITTER                = 0.20  -- ±20% randomisation
local CAM_DIRECTED_COOLDOWN   = 2.0   -- multiplier: min wait after a directed cut
CAM_START_MIN_16THS       = 32    -- earliest first cut for full/early-range generation
CAM_START_MAX_16THS       = 48    -- latest first cut for full/early-range generation
CAM_SHORT_START_MIN_16THS = 4     -- earliest first cut when range starts mid-song
CAM_SHORT_START_MAX_16THS = 16    -- latest first cut when range starts mid-song
local DIRECTED_MIN_COUNT      = 1     -- minimum directed cuts per song
local DIRECTED_MAX_COUNT      = 4     -- maximum directed cuts per song

-- Per-instrument selection weights for weighted coop camera picks.
-- These are the base probabilities before normalizing against available instruments.
local INST_WEIGHTS = { v = 40, d = 15, g = 15, b = 15, k = 15 }
local INST_ORDER   = { 'v', 'd', 'g', 'b', 'k' }  -- deterministic iteration order
local IDLE_WEIGHT  = 5  -- effective weight for an instrument currently in idle state

-- View-suffix weights for the secondary roll within the Solo camera group.
-- Vocals has only 3 shot types; all other instruments share the 4-type table.
local SOLO_SUFFIX_WEIGHTS = {
    v = { near = 50, closeup = 30, behind = 20 },
}
local SOLO_SUFFIX_WEIGHTS_DEFAULT = {
    near = 45, closeup_head = 20, closeup_hand = 20, behind = 15,
}
-- Boosted suffix weights when the chosen solo instrument has an active sing note.
-- Vocals ('v') never uses this table (no sing pitch exists for the vocalist).
local SOLO_SUFFIX_WEIGHTS_SING = {
    near = 45, closeup_head = 35, closeup_hand = 10, behind = 10,
}

-- Instrument letters that can carry sing notes (pitches 85/86/87 on the VENUE track).
-- Keys ('k') and vocals ('v') have no dedicated sing pitch and are never in singing_set.
local SING_POOL_LETTERS = { 'b', 'd', 'g' }

math.randomseed(os.time())

-- ---------------------------------------------------------------------------

-- avoid: either a single string to exclude, or a set (table with string keys = true) of
-- multiple strings to exclude - lets callers ban every event from the previous "spot"
-- (a primary shot plus its companion, if any) rather than just the last single pick.
function PickRandom(pool, avoid)
    if #pool == 0 then return nil end
    if #pool == 1 then return pool[1] end
    for _ = 1, 10 do
        local choice = pool[math.random(#pool)]
        local banned = (type(avoid) == 'table') and avoid[choice] or (choice == avoid)
        if not banned then return choice end
    end
    return pool[math.random(#pool)]
end

function JitteredInterval(base_16ths, jitter_frac)
    local lo      = base_16ths * (1.0 - jitter_frac)
    local hi      = base_16ths * (1.0 + jitter_frac)
    local snapped = math.floor(lo + math.random() * (hi - lo) + 0.5)
    return snapped < 1 and 1 or snapped
end

-- Splits each instrument's solo shot pool by view suffix, called once before generation.
-- Returns suffix_pools[letter][view] = {shots}; unrecognized views go into ['__other'].
-- Pass the result as coop_opts.suffix_pools for use in WeightedPickCoopEvent.
function BuildSuffixPools(solo_pools)
    local out = {}
    for letter, shots in pairs(solo_pools) do
        local weight_table = SOLO_SUFFIX_WEIGHTS[letter] or SOLO_SUFFIX_WEIGHTS_DEFAULT
        local by_view      = {}
        for _, shot in ipairs(shots) do
            local view = shot:match('^%[coop_%a_(.+)%]$')
            if view and weight_table[view] then
                if not by_view[view] then by_view[view] = {} end
                by_view[view][#by_view[view] + 1] = shot
            else
                if not by_view['__other'] then by_view['__other'] = {} end
                by_view['__other'][#by_view['__other'] + 1] = shot
            end
        end
        out[letter] = by_view
    end
    return out
end

local function WeightedPickSoloShot(letter, suffix_by_view, avoid, singing_set)
    local weight_table
    if singing_set and singing_set[letter] and letter ~= 'v' then
        weight_table = SOLO_SUFFIX_WEIGHTS_SING
    else
        weight_table = SOLO_SUFFIX_WEIGHTS[letter] or SOLO_SUFFIX_WEIGHTS_DEFAULT
    end
    local choices = {}
    local total   = 0
    for view, w in pairs(weight_table) do
        local shots = suffix_by_view[view]
        if shots and #shots > 0 then
            total = total + w
            choices[#choices + 1] = { shots = shots, w = w }
        end
    end
    if #choices == 0 then
        local other = suffix_by_view['__other']
        return other and PickRandom(other, avoid) or nil
    end
    local cum  = 0
    local roll = math.random() * total
    for _, c in ipairs(choices) do
        cum = cum + c.w
        if roll < cum then return PickRandom(c.shots, avoid) end
    end
    return PickRandom(choices[#choices].shots, avoid)
end

-- Splits an active_coop array into three categorised sub-pools:
--   venue  = shots with "all" or "front" codes   ([coop_all_*], [coop_front_*])
--   solo   = table[letter] = shots for single-instrument codes  ([coop_g_*], …)
--   duo    = table[code2]  = shots for two-instrument codes     ([coop_gv_*], …)
function CategorizeCoopPool(pool)
    local venue = {}
    local solo  = {}
    local duo   = {}
    for _, ev in ipairs(pool) do
        local inner = ev:match('^%[coop_(.+)%]$')
        if inner then
            local code = inner:match('^(%a+)_')
            if code then
                if code == 'all' or code == 'front' then
                    venue[#venue + 1] = ev
                elseif #code == 1 then
                    if not solo[code] then solo[code] = {} end
                    solo[code][#solo[code] + 1] = ev
                elseif #code == 2 then
                    if not duo[code] then duo[code] = {} end
                    duo[code][#duo[code] + 1] = ev
                else
                    venue[#venue + 1] = ev
                end
            end
        end
    end
    return venue, solo, duo
end

-- Picks one instrument letter from available_set using INST_WEIGHTS.
-- available_set is a table where available_set[letter] = true.
-- idle_set (optional): letters currently idle receive IDLE_WEIGHT instead of base weight.
-- singing_set (optional): applies sing-note weight redistribution when some (not all) of
--   {b,d,g} are singing. Non-singing {b,d,g} and keys drop to IDLE_WEIGHT; their
--   "missing" weight (base - IDLE_WEIGHT) redistributes equally to available singers.
--   When all three sing or none sing, base weights apply unchanged.
local function WeightedPickInstrument(available_set, idle_set, singing_set)
    local effective = {}
    if singing_set then
        local singers = {}
        local n_sing  = 0
        for _, l in ipairs(SING_POOL_LETTERS) do
            if singing_set[l] then singers[l] = true; n_sing = n_sing + 1 end
        end
        if n_sing > 0 and n_sing < #SING_POOL_LETTERS then
            local missing = 0
            for _, l in ipairs(SING_POOL_LETTERS) do
                if not singers[l] then
                    effective[l] = IDLE_WEIGHT
                    if available_set[l] then
                        missing = missing + ((INST_WEIGHTS[l] or 0) - IDLE_WEIGHT)
                    end
                end
            end
            effective['k'] = IDLE_WEIGHT
            if available_set['k'] then
                missing = missing + ((INST_WEIGHTS['k'] or 0) - IDLE_WEIGHT)
            end
            local avail_sing = {}
            for l in pairs(singers) do
                if available_set[l] then avail_sing[#avail_sing + 1] = l end
            end
            if #avail_sing > 0 then
                local bonus = missing / #avail_sing
                for _, l in ipairs(avail_sing) do
                    effective[l] = (INST_WEIGHTS[l] or 0) + bonus
                end
            end
        end
    end

    local total = 0
    local items = {}
    for _, letter in ipairs(INST_ORDER) do
        if available_set[letter] then
            local w
            if effective[letter] then
                w = effective[letter]
            elseif idle_set and idle_set[letter] then
                w = IDLE_WEIGHT
            else
                w = INST_WEIGHTS[letter] or 0
            end
            if w > 0 then
                total = total + w
                items[#items + 1] = { letter = letter, cum = total }
            end
        end
    end
    if total == 0 or #items == 0 then return nil end
    local roll = math.random() * total
    for _, item in ipairs(items) do
        if roll < item.cum then return item.letter end
    end
    return items[#items].letter
end

-- Keys / guitar / bass swap failsafe: when all three of {bass, guitar, keys} are
-- present in the project, the in-game band can only have two of them at once.
-- Emitting a companion event at the same tick gives the game an alternative to pick
-- from based on which two instruments are actually populated in the band setup.
--
-- Companion pick for keys/guitar/bass failsafe.
-- Uses the same weighted randomness as a normal camera pick, filtered to exclude
-- any instrument letter already present in the primary shot's code.
-- avoid_set: optional set of event strings to exclude (the previous spot's banned events) -
-- see PickRandom for the set format.
-- Returns one companion string or nil (never more than one).
function FindCompanion(event_text, coop_opts, idle_set, singing_set, avoid_set)
    local code = event_text:match('^%[coop_(%a+)_')
    if not code then return nil end
    if code == 'all' or code == 'front' then return nil end

    local has_gbk = code:find('g', 1, true) or code:find('b', 1, true) or code:find('k', 1, true)
    if not has_gbk then return nil end

    -- Build exclude set from primary instrument letters
    local exclude = {}
    for i = 1, #code do exclude[code:sub(i, i)] = true end

    -- Filter solo_pools: drop excluded instruments
    local fsolo = {}
    for letter, shots in pairs(coop_opts.solo_pools) do
        if not exclude[letter] and #shots > 0 then
            fsolo[letter] = shots
        end
    end

    -- Filter duo_pools: drop any duo code that contains an excluded instrument
    local fduo = {}
    for dcode, shots in pairs(coop_opts.duo_pools) do
        local ok = true
        for i = 1, #dcode do
            if exclude[dcode:sub(i, i)] then ok = false; break end
        end
        if ok and #shots > 0 then fduo[dcode] = shots end
    end

    return WeightedPickCoopEvent(coop_opts.venue_pool, fsolo, fduo, avoid_set,
                                 idle_set, nil, coop_opts.suffix_pools, singing_set)
end

-- Three-stage weighted coop pick:
--   1. Choose group:      solo 60% / duo 20% / venue 20%  (weights scale to available groups)
--   2. Choose instrument: v=30 d=20 g=20 b=15 k=15        (normalized over available instruments)
--   3. Pick random event from that instrument's sub-pool, avoiding last_pick where possible.
-- idle_set (optional): instruments in idle state receive IDLE_WEIGHT at stage 2.
-- group_weights (optional): override {solo, duo, venue} percentages (e.g. all-idle shift).
function WeightedPickCoopEvent(venue_pool, solo_pools, duo_pools, avoid,
                               idle_set, group_weights, suffix_pools, singing_set)
    local gw        = group_weights or { solo = 60, duo = 20, venue = 20 }
    local has_venue = #venue_pool > 0
    local has_solo  = next(solo_pools) ~= nil
    local has_duo   = next(duo_pools)  ~= nil

    local groups = {}
    if has_solo  then groups[#groups + 1] = { name = 'solo',  w = gw.solo  } end
    if has_duo   then groups[#groups + 1] = { name = 'duo',   w = gw.duo   } end
    if has_venue then groups[#groups + 1] = { name = 'venue', w = gw.venue } end
    if #groups == 0 then return nil end

    local total = 0
    for _, g in ipairs(groups) do total = total + g.w end
    local chosen = groups[#groups].name
    local cum    = 0
    local roll   = math.random() * total
    for _, g in ipairs(groups) do
        cum = cum + g.w
        if roll < cum then chosen = g.name; break end
    end

    if chosen == 'venue' then
        return PickRandom(venue_pool, avoid)

    elseif chosen == 'solo' then
        local avail = {}
        for letter, shots in pairs(solo_pools) do
            if #shots > 0 then avail[letter] = true end
        end
        local letter = WeightedPickInstrument(avail, idle_set, singing_set)
        if letter and solo_pools[letter] then
            if suffix_pools and suffix_pools[letter] then
                return WeightedPickSoloShot(letter, suffix_pools[letter], avoid, singing_set)
            end
            return PickRandom(solo_pools[letter], avoid)
        end
        local all_solo = {}
        for _, shots in pairs(solo_pools) do
            for _, s in ipairs(shots) do all_solo[#all_solo + 1] = s end
        end
        return PickRandom(all_solo, avoid)

    else  -- duo
        -- Build available instrument letters across all non-empty duo sub-pools
        local avail = {}
        for code2, shots in pairs(duo_pools) do
            if #shots > 0 then
                for i = 1, #code2 do avail[code2:sub(i, i)] = true end
            end
        end
        local letter = WeightedPickInstrument(avail, idle_set)
        -- Collect all duo events that feature the selected instrument
        local matching = {}
        for code2, shots in pairs(duo_pools) do
            if #shots > 0 and letter and code2:find(letter, 1, true) then
                for _, s in ipairs(shots) do matching[#matching + 1] = s end
            end
        end
        if #matching > 0 then return PickRandom(matching, avoid) end
        local all_duo = {}
        for _, shots in pairs(duo_pools) do
            for _, s in ipairs(shots) do all_duo[#all_duo + 1] = s end
        end
        return PickRandom(all_duo, avoid)
    end
end

-- Advances per-instrument play-state cursors to pos_16ths and returns:
--   idle_set   table[letter]=true for instruments currently in idle state
--   all_idle   true when every instrument that has events in the coop pools is idle
-- Cursors advance monotonically - safe to call with increasing pos_16ths values.
function ComputeIdleState(coop_opts, play_cursors, pos_16ths)
    if not coop_opts or not coop_opts.play_states then
        return {}, false
    end
    local idle_set = {}
    for letter, timeline in pairs(coop_opts.play_states) do
        if timeline then
            while play_cursors[letter] <= #timeline
                  and timeline[play_cursors[letter]].pos_16ths <= pos_16ths do
                play_cursors[letter] = play_cursors[letter] + 1
            end
            local ci        = play_cursors[letter] - 1
            local is_active = ci >= 1 and timeline[ci].is_active or false
            if not is_active then idle_set[letter] = true end
        end
        -- nil timeline = no play-state events = always active = not added to idle_set
    end
    -- all_idle: every instrument with events in solo or duo pools is idle
    local all_idle = true
    for letter, shots in pairs(coop_opts.solo_pools) do
        if #shots > 0 and (not coop_opts.play_states[letter] or not idle_set[letter]) then
            all_idle = false; break
        end
    end
    if all_idle then
        for code2, shots in pairs(coop_opts.duo_pools) do
            if #shots > 0 then
                for i = 1, #code2 do
                    local l = code2:sub(i, i)
                    if not coop_opts.play_states[l] or not idle_set[l] then
                        all_idle = false; break
                    end
                end
            end
            if not all_idle then break end
        end
    end
    return idle_set, all_idle
end

-- Returns singing_set[letter]=true for instruments with an active sing note at pos_16ths.
-- Cursors advance monotonically - same pattern as ComputeIdleState.
function ComputeSingState(coop_opts, sing_cursors, pos_16ths)
    if not coop_opts or not coop_opts.sing_states then return {} end
    local singing_set = {}
    for letter, timeline in pairs(coop_opts.sing_states) do
        while sing_cursors[letter] <= #timeline
              and timeline[sing_cursors[letter]].pos_16ths <= pos_16ths do
            sing_cursors[letter] = sing_cursors[letter] + 1
        end
        local ci = sing_cursors[letter] - 1
        if ci >= 1 and timeline[ci].is_singing then
            singing_set[letter] = true
        end
    end
    return singing_set
end

-- cam_interval: override base camera spacing in 16ths (nil = use constant)
-- forced_cuts:  sorted array of {pos_16ths, text} for dircut_at_start events
-- interval_changes: sorted array of {pos_16ths, interval} for per-section pacing
-- coop_opts:    optional weighted-pick config:
--   { venue_pool, solo_pools, duo_pools, active_coop_set, keys_failsafe, play_states }
--   When present, uses WeightedPickCoopEvent instead of PickRandom.
-- initial_avoid_set: optional set of event strings banned for the very first pick (e.g. the
--   text(s) placed at a caller's bookend spot immediately before this call) - see PickRandom.
-- phrase_positions_16ths: "Vocal phrase start" pacing mode. nil = not active (normal
--   interval-based pacing). Otherwise a sorted array (may be empty) of phrase-start
--   positions in 16ths - the recurring loop visits exactly these positions (plus any
--   forced_cuts targets) instead of stepping by cam_interval/JitteredInterval; jitter
--   and the tail bonus shot are not used in this mode.
function GenerateCameraEvents(active_coop, active_directed, total_16ths, ppq,
                              cam_interval, forced_cuts, interval_changes,
                              start_min, start_max, coop_opts, initial_avoid_set,
                              phrase_positions_16ths)
    local base_interval   = cam_interval or CAM_INTERVAL_16THS
    local sixteenth_ticks = ppq / 4
    local events          = {}
    local use_phrase      = phrase_positions_16ths ~= nil

    local fc_sorted = {}
    if forced_cuts then
        for _, fc in ipairs(forced_cuts) do fc_sorted[#fc_sorted + 1] = fc end
        table.sort(fc_sorted, function(a, b) return a.pos_16ths < b.pos_16ths end)
    end

    if #active_coop == 0 and #active_directed == 0 and #fc_sorted == 0 then
        return events
    end

    local fc_idx     = 1
    local phrase_idx = 1

    -- Returns the smaller of "next remaining phrase position" / "next pending forced
    -- cut's pos_16ths", or nil when neither remains. Phrase-mode only - this is what
    -- lets a forced cut keep firing at its own position even when no phrases are left
    -- (or none exist at all).
    local function next_phrase_or_fc()
        local ph = phrase_positions_16ths and phrase_positions_16ths[phrase_idx]
        local fc = fc_sorted[fc_idx] and fc_sorted[fc_idx].pos_16ths
        if ph and fc then return math.min(ph, fc) end
        return ph or fc
    end

    local start_16ths
    if use_phrase then
        local lo = start_min or 0
        while phrase_idx <= #phrase_positions_16ths
              and phrase_positions_16ths[phrase_idx] < lo do
            phrase_idx = phrase_idx + 1
        end
        start_16ths = next_phrase_or_fc()
        if not start_16ths then return events end
    else
        start_16ths = math.random(
            start_min or CAM_START_MIN_16THS,
            start_max or CAM_START_MAX_16THS)
    end

    local num_directed = 0
    if #active_directed > 0 then
        num_directed = math.random(DIRECTED_MIN_COUNT, DIRECTED_MAX_COUNT)
    end

    local directed_positions = {}
    for _ = 1, num_directed do
        local zone_s = math.max(math.floor(total_16ths * 0.10), start_16ths)
        local zone_e = math.floor(total_16ths * 0.90)
        if zone_e > zone_s then
            directed_positions[#directed_positions + 1] = math.random(zone_s, zone_e)
        end
    end
    table.sort(directed_positions)

    local blackout_16ths = total_16ths - 8
    if blackout_16ths < start_16ths then blackout_16ths = total_16ths end

    local pos_16ths        = start_16ths
    -- Set of event strings banned for the current pick - the previous spot's placed event(s)
    -- (primary + companion, if any). Replaced wholesale each spot, never merged across spots,
    -- so a shot is only off-limits for one spot ahead.
    local last_spot        = initial_avoid_set or {}
    local last_event_16ths = start_16ths
    local directed_idx     = 1
    local cur_interval     = base_interval
    local ic_idx           = 1

    local play_cursors = {}
    if coop_opts and coop_opts.play_states then
        for letter, _ in pairs(coop_opts.play_states) do
            play_cursors[letter] = 1
        end
    end
    local sing_cursors = {}
    if coop_opts and coop_opts.sing_states then
        for letter in pairs(coop_opts.sing_states) do sing_cursors[letter] = 1 end
    end

    while pos_16ths < blackout_16ths do
        -- Advance per-section interval changes
        if interval_changes then
            while ic_idx <= #interval_changes
                and pos_16ths >= interval_changes[ic_idx].pos_16ths do
                cur_interval = interval_changes[ic_idx].interval
                ic_idx = ic_idx + 1
            end
        end

        local is_directed = false

        -- Forced directed cuts (from dircut_at_start)
        if fc_idx <= #fc_sorted then
            local fc = fc_sorted[fc_idx]
            if pos_16ths >= fc.pos_16ths - cur_interval / 2 then
                events[#events + 1] = {
                    tick        = math.floor(fc.pos_16ths * sixteenth_ticks + 0.5),
                    text        = fc.text,
                    is_directed = true,
                }
                last_spot          = { [fc.text] = true }
                last_event_16ths   = fc.pos_16ths
                is_directed        = true
                fc_idx             = fc_idx + 1
            end
        end

        -- Random directed cuts
        if not is_directed and directed_idx <= #directed_positions and #active_directed > 0 then
            if pos_16ths >= directed_positions[directed_idx] - cur_interval / 2 then
                local text = PickRandom(active_directed, last_spot)
                if text then
                    last_spot          = { [text] = true }
                    last_event_16ths   = pos_16ths
                    events[#events + 1] = {
                        tick        = math.floor(pos_16ths * sixteenth_ticks + 0.5),
                        text        = text,
                        is_directed = true,
                    }
                    is_directed = true
                end
                directed_idx = directed_idx + 1
            end
        end

        if not is_directed and #active_coop > 0 then
            local text
            if coop_opts then
                local idle_set, all_idle = ComputeIdleState(coop_opts, play_cursors, pos_16ths)
                local singing_set        = ComputeSingState(coop_opts, sing_cursors, pos_16ths)
                local gw = all_idle and { solo = 30, duo = 10, venue = 60 } or nil
                text = WeightedPickCoopEvent(
                    coop_opts.venue_pool, coop_opts.solo_pools,
                    coop_opts.duo_pools, last_spot, idle_set, gw,
                    coop_opts.suffix_pools, singing_set)
            else
                text = PickRandom(active_coop, last_spot)
            end
            if text then
                local prev_spot    = last_spot
                last_spot          = { [text] = true }
                last_event_16ths   = pos_16ths
                local tick         = math.floor(pos_16ths * sixteenth_ticks + 0.5)
                events[#events + 1] = {
                    tick = tick, text = text, is_directed = false,
                }
                if coop_opts and coop_opts.keys_failsafe then
                    local companion = FindCompanion(text, coop_opts, idle_set, singing_set, prev_spot)
                    if companion then
                        last_spot[companion] = true
                        events[#events + 1] = {
                            tick         = tick,
                            text         = companion,
                            is_directed  = false,
                            is_companion = true,
                        }
                    end
                end
            end
        end

        if use_phrase then
            -- Advance past whatever position was just processed (whether it produced a
            -- coop pick, a forced cut, or nothing) so it's never revisited.
            while phrase_idx <= #phrase_positions_16ths
                  and phrase_positions_16ths[phrase_idx] <= pos_16ths do
                phrase_idx = phrase_idx + 1
            end
            pos_16ths = next_phrase_or_fc() or blackout_16ths
        else
            local interval = JitteredInterval(cur_interval, S.venue_cam_pacing_jitter and CAM_JITTER or 0)
            if is_directed then
                local min_cd = math.floor(cur_interval * CAM_DIRECTED_COOLDOWN)
                if interval < min_cd then interval = min_cd end
            end
            pos_16ths = pos_16ths + interval
        end
    end

    -- Tail bonus shot: not used in phrase mode - camera events are wanted exactly on
    -- phrase notes, not on a synthetic extra position near the end of the range.
    local min_tail_gap = math.floor(base_interval * (1 - (S.venue_cam_pacing_jitter and CAM_JITTER or 0)))
    if not use_phrase and #active_coop > 0 and blackout_16ths > start_16ths
        and blackout_16ths - last_event_16ths >= min_tail_gap then
        local text
        if coop_opts then
            local idle_set, all_idle = ComputeIdleState(coop_opts, play_cursors, blackout_16ths)
            local singing_set        = ComputeSingState(coop_opts, sing_cursors, blackout_16ths)
            local gw = all_idle and { solo = 30, duo = 10, venue = 60 } or nil
            text = WeightedPickCoopEvent(
                coop_opts.venue_pool, coop_opts.solo_pools,
                coop_opts.duo_pools, last_spot, idle_set, gw,
                coop_opts.suffix_pools, singing_set)
        else
            text = PickRandom(active_coop, last_spot)
        end
        if text then
            local tick = math.floor(blackout_16ths * sixteenth_ticks + 0.5)
            events[#events + 1] = {
                tick = tick, text = text, is_directed = false,
            }
            if coop_opts and coop_opts.keys_failsafe then
                local companion = FindCompanion(text, coop_opts, idle_set, singing_set, last_spot)
                if companion then
                    events[#events + 1] = {
                        tick         = tick,
                        text         = companion,
                        is_directed  = false,
                        is_companion = true,
                    }
                end
            end
        end
    end

    return events
end

-- Resolve the user camera-pacing override (S.venue_cam_pacing) to an
-- interval in 16ths. Returns interval|nil, is_named_preset:
--   0 (theme default) -> nil, false
--   1-5 (named preset) -> GetThemeCameraInterval(name, bpm), true
--   6 (custom 16ths)   -> S.venue_cam_pacing_custom (x1.5 at >=150 bpm), false
-- is_named_preset matters to the generator: only named presets suppress
-- per-section theme pacing overrides (custom pacing does not).
function ResolveUserCamInterval(bpm)
    local names = {nil, 'minimal', 'slow', 'medium', 'fast', 'crazy'}
    local name  = names[S.venue_cam_pacing + 1]
    if name then
        return GetThemeCameraInterval(name, bpm), true
    elseif S.venue_cam_pacing == 6 then
        local base = S.venue_cam_pacing_custom
        return (bpm >= 150) and math.floor(base * 1.5 + 0.5) or base, false
    end
    return nil, false
end

-- ---------------------------------------------------------------------------
-- Display order for the camera combos. Built once at load, alphabetically by
-- label. The pools at the top of this file keep their authored order - other
-- things depend on it (dev/tools/assets/extract_spritesheets.ps1 maps pool
-- position to a window in the captured demo video, and the dev demo stores
-- literal positions), and generation picks at random, never by position.
-- Built here, at the end of the file, because CategorizeCoopPool has to exist
-- before this runs.
-- ---------------------------------------------------------------------------

local function BareOf(ev) return ev:match('^%[(.-)%]$') or ev end

-- Normal camera, grouped the way the generator itself buckets these shots, each
-- group alphabetical. Holds FULL event strings - that is what the combo assigns
-- to S.venue_mg_coop. The buckets come from CategorizeCoopPool rather than a
-- second hand-written split, so the headers can't claim a grouping the generator
-- doesn't actually use.
COOP_DISPLAY_GROUPS = {}
do
    local _venue, _solo, _duo = CategorizeCoopPool(COOP_POOL)
    -- solo/duo arrive keyed by instrument code, and pairs() order is undefined -
    -- flatten first; the label sort is what gives the result a stable order.
    local function Flatten(by_code)
        local out = {}
        for _, shots in pairs(by_code) do
            for _, ev in ipairs(shots) do out[#out + 1] = ev end
        end
        return out
    end
    COOP_DISPLAY_GROUPS = {
        { name = 'Venue', events = SortedByLabel(_venue,         COOP_LABELS, BareOf) },
        { name = 'Solo',  events = SortedByLabel(Flatten(_solo), COOP_LABELS, BareOf) },
        { name = 'Duo',   events = SortedByLabel(Flatten(_duo),  COOP_LABELS, BareOf) },
    }
end

-- Directed camera: bare names, alphabetical. The BRE cuts are not in here - Manual
-- gen pins them after this list (they are for the Big Rock Ending only) and Section
-- gen doesn't offer them at all.
DIRECTED_DISPLAY = {}
do
    local _bare = {}
    for _, ev in ipairs(DIRECTED_POOL) do _bare[#_bare + 1] = BareOf(ev) end
    DIRECTED_DISPLAY = SortedByLabel(_bare, DIRECTED_LABELS)
end

DIRECTED_BRE_NAMES = { 'directed_bre', 'directed_brej' }
