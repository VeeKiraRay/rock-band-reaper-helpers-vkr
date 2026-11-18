-- Animation > Drums: the drummer's hand and foot animation notes on PART DRUMS
-- (and PART DRUMS_2X), generated from the Expert gems.
--
-- The notes (RBN drum doc, "Animations"): kick 24, hi-hat pedal 25 (held: the
-- hat is open while it is held; written only for open hi-hats, see
-- DrumAnimOpenHatSpans - official charts mostly use it for the foot keeping time,
-- which is left to the author), snare L/R 26/27 (soft 28/29), hi-hat L/R
-- 30/31, crash 1 L 34 (soft 35), crash 1 R 36 (soft 37), crash 2 R 38 (soft 39),
-- ride R/L 42/43, crash 2 L 44 (soft 45), tom 1 L/R 46/47, tom 2 L/R 48/49,
-- floor tom L/R 50/51; chokes 40 (crash 2, the right cymbal) / 41 (crash 1, the
-- left) - the RBN doc has them the other way round, the game's code revealed this
-- and an in-game test confirmed it.
--
-- Soft snares, soft crashes and chokes follow the Expert gem's velocity, with the
-- author's own thresholds (options). Official charts do not use velocity for this
-- (447 of 585 RB3 DLC songs use one velocity on every gem; their soft notes were
-- placed by hand), so a chart only gets them where its author set the velocities.
-- A choke replaces the crash hit: one note on the gem's tick, no hand variant (all
-- 518 official chokes are like that).
--
-- Which drum each gem is follows CAT's drums_animations (and the official
-- charts: yellow cymbal = hi-hat 91%, blue cymbal = ride 78%, ...). Which HAND
-- plays it is where this differs from CAT: CAT alternates R L R L through any
-- run up to an 8th apart, which agrees with the official hands 61% of the time.
-- The rules here come from the official RB3 DLC charts (the numbers in
-- DRUM_ANIM_PARAMS and .claude/CLAUDE_general.md):
--   - every piece has a usual hand, following the kit from left to right
--     (hi-hat, crash 1, snare, tom 1, tom 2, floor tom, crash 2, ride): snare and
--     tom 1 left, the rest right - the hi-hat crossed, by the right hand;
--   - hands alternate only when hits come fast: under ~170 ms on drums, ~130 ms
--     on cymbals (and only in longer cymbal runs); slower, one hand repeats;
--   - a fast run takes its phase from the beat: the beat and the 8th "and" by
--     the right hand, the 16th "e" / "a" by the left;
--   - moving to another drum, the hand on that side takes it: moving right
--     (towards the floor tom) the right hand, moving left the left hand;
--   - crash 2 straight into crash 1: crash 1 by the left hand.
--
-- DrumAnimPlan is pure (no r) - dev/tools/drum_anim_eval_offline.lua runs it
-- over the official charts. The REAPER side is GenerateDrumAnimations.
-- Requires globals: r, S, FindTrackByName, FindFirstMIDIItem, ReplaceNotesBulk
-- (lib/reaper_midi_helpers.lua), GetTimeSelection

DRUM_ANIM_PARAMS = {
    window_ms     = 400,  -- hits further apart than this start afresh (usual hand)
    drum_fast_ms  = 170,  -- drums alternate under this (same drum 87-92%, other drum 98%)
    cym_fast_ms   = 130,  -- cymbals alternate under this, from min_cym_hits in a row
    cym_mid_ms    = 170,  -- 130-170 ms: cymbals alternate only in runs of cym_long_run+
    cym_long_run  = 8,    -- (official 130-170 ms: 2-3 hits 18%, 8-15 hits 76%)
    hh16_fast_ms  = 137,  -- hi-hat 16ths alternate under this (16ths at 110 BPM)
    lone_blue_qn  = 1,    -- a blue cymbal with no other blue this close is a crash
    min_cym_hits  = 3,    -- CAT's "Min. cymbals hits" (CAT 4; dev scores 3 best: 92.0 vs 91.8%)
    slow_ms       = 220,  -- a lone snare this far after the last hand hit is "slow"
    context_ms    = 2000, -- what comes right before / after a slow snare
    pause_ms      = 500,  -- a slow snare after this long a gap counts as an accent
    flam_late_qn  = 1 / 32, -- "Flam: left hand slightly after": how far after
    len_qn        = 0.125, -- written note length (animation length has no effect)
    -- Open hi-hat pedal (25), from the official open-hat 25s: start ~a 16th before the
    -- first open hit (11,025 of 15,723), end on the next hi-hat hit (7,387).
    open_lead_qn  = 0.25,  -- the pedal opens this far before the first open hit
    open_next_qn  = 1,     -- the next hi-hat hit closes it when it comes within this
    open_tail_qn  = 1,     -- otherwise held a quarter note after the last open hit
    open_min_qn   = 0.5,   -- shortest pedal note, an 8th (the game opens and closes over time)
}

-- Kit pieces left to right (the RBN visual template) and their notes.
DRUM_ANIM_PIECES = {
    hh   = { pos = 1, hand = 'R', L = 30, R = 31,                     cym = true },
    c1   = { pos = 2, hand = 'R', L = 34, R = 36, Ls = 35, Rs = 37,   cym = true, choke = 41 },
    sn   = { pos = 3, hand = 'L', L = 26, R = 27, Ls = 28, Rs = 29 },
    t1   = { pos = 4, hand = 'L', L = 46, R = 47 },
    t2   = { pos = 5, hand = 'R', L = 48, R = 49 },
    ft   = { pos = 6, hand = 'R', L = 50, R = 51 },
    c2   = { pos = 7, hand = 'R', L = 44, R = 38, Ls = 45, Rs = 39,   cym = true, choke = 40 },
    ride = { pos = 8, hand = 'R', L = 43, R = 42,                     cym = true },
}
DRUM_ANIM_KICK = 24
-- Velocity of a gem that carries none (synthetic onsets): a normal hit.
DRUM_ANIM_VEL_DEFAULT = 100

local EPS = 1e-6
local function Other(h) return h == 'L' and 'R' or 'L' end

-- The kit pieces an onset's gems hit, before hands. Disco flip: the red gem is
-- the hi-hat and the yellow cymbal the snare (CAT; the RBN mix events).
-- Blue cymbal: the ride, or (option) the open hi-hat - some songs chart the
-- closed hi-hat yellow and the open one blue (official: 37 of 338 songs with
-- blue cymbals play it as the hi-hat 99% of the time; no gem pattern tells them
-- apart, so it is the author's choice). A blue already sharing its hit with the
-- hi-hat stays the ride. A lone blue (o.lone_blue) is a crash accent: crash 1.
-- Also records o.pvel[piece]: the velocity of the gem that made the piece (the
-- velocity options read it; DrumAnimPieceVel).
local function Pieces(o, opts)
    local p, vel = {}, o.vel or {}
    o.pvel = {}
    o.hh_lane = nil
    local function Add(piece, lane)
        p[#p + 1] = piece
        o.pvel[piece] = math.max(o.pvel[piece] or 0, vel[lane] or DRUM_ANIM_VEL_DEFAULT)
        if piece == 'hh' then o.hh_lane = lane end   -- open hi-hat: which gem made it
    end
    if o.R then Add(o.disco and 'hh' or 'sn', 'R') end
    if o.Y then Add(o.Yt and 't1' or (o.disco and 'sn' or 'hh'), 'Y') end
    if o.B then
        local hh_taken = (o.R and o.disco) or (o.Y and not o.Yt and not o.disco)
        if o.Bt then Add('t2', 'B')
        elseif opts.blue_hh and not hh_taken then Add('hh', 'B')
        elseif o.lone_blue and not opts.blue_hh then Add('c1', 'B')
        else Add('ride', 'B') end
    end
    if o.G then Add(o.Gt and 'ft' or (opts.crash1 and 'c1' or 'c2'), 'G') end
    return p
end

-- Velocity of a planned hand's piece. Two-hand rules can turn a piece into another
-- (hi-hat + crash -> both crashes): such a piece takes the loudest gem of the hit.
local function PieceVel(o, piece)
    local v = o.pvel and o.pvel[piece]
    if v then return v end
    local best
    for _, x in pairs(o.pvel or {}) do best = math.max(best or 0, x) end
    return best or DRUM_ANIM_VEL_DEFAULT
end
DrumAnimPieceVel = PieceVel

-- Beat position of a hit: 'beat' / 'and' (8th grid) / 'e' (16th off the 8th
-- grid) / 'trip' / 'other'.
local function BeatPos(qn)
    local fr = qn - math.floor(qn + EPS)
    if fr < 0.02 or fr > 0.98 then return 'beat' end
    if math.abs(fr - 0.5) < 0.02 then return 'and' end
    if math.abs(fr - 0.25) < 0.02 or math.abs(fr - 0.75) < 0.02 then return 'e' end
    if math.abs(fr - 1 / 3) < 0.02 or math.abs(fr - 2 / 3) < 0.02 then return 'trip' end
    return 'other'
end
DrumAnimBeatPos = BeatPos

-- Two hands on one onset: the snare goes to the left hand and the other piece
-- to the right (the groove: hi-hat crossed over); otherwise the piece further
-- left takes the left hand. More than two pieces: the snare and the loudest
-- cymbal (crash > ride > hi-hat), or the two outermost.
local CYM_RANK = { c2 = 4, c1 = 3, ride = 2, hh = 1 }
local function TwoHands(pieces)
    local list = {}
    for _, p in ipairs(pieces) do list[#list + 1] = p end
    if #list > 2 then
        local has_sn, best
        for _, p in ipairs(list) do
            if p == 'sn' then has_sn = true
            elseif CYM_RANK[p] and (not best or CYM_RANK[p] > CYM_RANK[best]) then best = p end
        end
        if has_sn and best then list = { 'sn', best }
        else
            table.sort(list, function(a, b) return DRUM_ANIM_PIECES[a].pos < DRUM_ANIM_PIECES[b].pos end)
            list = { list[1], list[#list] }
        end
    end
    local a, b = list[1], list[2]
    -- hi-hat + crash: both crashes, crash 1 left (official 96%, CAT's table)
    if (a == 'hh' and (b == 'c2' or b == 'c1')) or (b == 'hh' and (a == 'c2' or a == 'c1')) then
        return { { 'c1', 'L' }, { 'c2', 'R' } }
    end
    -- snare + tom 2: the right hand reaches the floor tom (official 52% vs tom 2 38%)
    if (a == 'sn' and b == 't2') or (b == 'sn' and a == 't2') then
        return { { 'sn', 'L' }, { 'ft', 'R' } }
    end
    if a == 'sn' then return { { a, 'L' }, { b, 'R' } } end
    if b == 'sn' then return { { b, 'L' }, { a, 'R' } } end
    if DRUM_ANIM_PIECES[a].pos > DRUM_ANIM_PIECES[b].pos then a, b = b, a end
    return { { a, 'L' }, { b, 'R' } }
end

-- Plans the animation notes.
--   onsets: { { qn, sec, K, R, Y, B, G (gems hit), Yt, Bt, Gt (under a tom marker),
--               disco }, ... } sorted by qn, one per hit time
--   opts:   crash1 (bool) - green cymbal on crash 1 instead of crash 2
--           soft_snare_below - snare gems under this velocity are soft (ghost strokes:
--                           the kit snare does not move); nil = off, 128 = every snare
--           choke_below    - crash gems under this velocity are chokes (40 / 41,
--                           replacing the hit); nil or 0 = none
--           soft_cym_below - crash gems under this velocity are soft (still a hit,
--                           lighter); nil = off, 128 = every crash. With both set, the
--                           lower of the two takes the lowest velocities (choke 20 /
--                           soft 50: 0-19 choke, 20-49 soft; soft 20 / choke 50: 0-19
--                           soft, 20-49 choke)
--           (gem velocity: onset.vel = { R=, Y=, B=, G= }, missing = DRUM_ANIM_VEL_DEFAULT)
--           flam (bool)   - snare + yellow tom = both hands on the snare (default on)
--           min_cym_hits  - cymbal hits in a row before fast cymbals alternate
--           snare_variety (bool) - slow lone snares by the right hand in snare-only
--                           passages and by both hands on accents (default on)
--           crash_ride_alt (bool) - riding a crash in 8ths alternates soft / hard
--           flam_late (bool) - the left hand of a flam a 1/32 note late
--           blue_hh (bool) - the blue cymbal is the open hi-hat, not the ride
-- Returns notes { { qn, pitch }, ... } and, per onset, o.hands = { { piece, hand } }.
function DrumAnimPlan(onsets, opts)
    opts = opts or {}
    local P = DRUM_ANIM_PARAMS
    local min_cym = opts.min_cym_hits or P.min_cym_hits
    local variety = opts.snare_variety ~= false
    local notes = {}

    -- Pieces per onset; single-hand onsets get their hand in the pass below.
    -- The green cymbal is always the default crash (option): which crash official
    -- charts use is a per-song choice (crash 1 anywhere from <10% to 90%+ of a
    -- song's crashes), and context rules (crash 1 after hi-hat playing, a crash run
    -- staying on its crash) measured no better than the plain default.
    -- A lone blue cymbal (no other blue cymbal within lone_blue_qn, no other
    -- cymbal on the hit, not in a disco flip): official plays it as a crash 55%
    -- (crash 1 32%, crash 2 23%), the ride only 21%.
    local blues = {}
    for _, o in ipairs(onsets) do
        o.lone_blue = nil
        if o.B and not o.Bt and not o.disco then blues[#blues + 1] = o end
    end
    for k, o in ipairs(blues) do
        local near = (blues[k - 1] and o.qn - blues[k - 1].qn <= P.lone_blue_qn + EPS)
                  or (blues[k + 1] and blues[k + 1].qn - o.qn <= P.lone_blue_qn + EPS)
        if not near and not (o.Y and not o.Yt) and not (o.G and not o.Gt) then o.lone_blue = true end
    end

    for _, o in ipairs(onsets) do
        o.pieces = Pieces(o, opts)
        -- snare + yellow tom = both hands on the snare (official 83%); on unless turned off
        if opts.flam ~= false and o.R and o.Yt and #o.pieces == 2 then o.flam = true end
    end

    -- Length of each run of fast single-hand cymbal hits (for min_cym_hits).
    local i = 1
    while i <= #onsets do
        local o = onsets[i]
        if #o.pieces == 1 and DRUM_ANIM_PIECES[o.pieces[1]].cym then
            local j = i
            while onsets[j + 1] and #onsets[j + 1].pieces == 1
                  and DRUM_ANIM_PIECES[onsets[j + 1].pieces[1]].cym
                  and (onsets[j + 1].sec - onsets[j].sec) * 1000 < P.cym_mid_ms do
                j = j + 1
            end
            for k = i, j do onsets[k].cym_run = j - i + 1 end
            i = j + 1
        else
            i = i + 1
        end
    end

    local prev       -- the previous onset with a hand hit
    for idx, o in ipairs(onsets) do
        local n = #o.pieces
        if o.flam then
            o.hands = { { 'sn', 'L' }, { 'sn', 'R' } }
        elseif n >= 2 then
            o.hands = TwoHands(o.pieces)
        elseif n == 1 then
            local p = o.pieces[1]
            local info = DRUM_ANIM_PIECES[p]
            local hand = info.hand
            local ms = prev and (o.sec - prev.sec) * 1000 or math.huge
            local single_prev = prev and #prev.hands == 1
            local pp = single_prev and prev.hands[1][1]
            local ph = single_prev and prev.hands[1][2]
            -- the next hand hit, to know whether a fast run starts here
            local nxt
            for k = idx + 1, #onsets do if #onsets[k].pieces > 0 then nxt = onsets[k] break end end
            local next_ms = nxt and (nxt.sec - o.sec) * 1000 or math.huge

            -- In a fast run the hand follows the beat (official: 87-89% of fast hits):
            -- the beat and the 8th "and" right, the 16th "e" / "a" left; triplets and
            -- finer grids alternate from the previous hit.
            local bp = BeatPos(o.qn)
            local phase = (bp == 'beat' or bp == 'and') and 'R' or (bp == 'e') and 'L' or nil
            -- Finer grids (32nds, triplets): count steps of the run's own spacing from
            -- the beat - even steps right, odd steps left.
            local gap_qn = math.min(prev and (o.qn - prev.qn) or math.huge,
                                    nxt and (nxt.qn - o.qn) or math.huge)
            local function FastHand()
                for _, unit in ipairs({ 1 / 8, 1 / 6, 1 / 12 }) do
                    if math.abs(gap_qn - unit) < 0.01 then
                        local steps = math.floor((o.qn - math.floor(o.qn + EPS)) / unit + 0.5)
                        return steps % 2 == 0 and 'R' or 'L'
                    end
                end
                if phase then return phase end
                -- a triplet drum hit right after a cymbal stays on that hand (shuffles)
                if bp == 'trip' and pp and DRUM_ANIM_PIECES[pp].cym and not info.cym then return ph end
                if ph then return Other(ph) end
                return (bp == 'trip') and 'R' or 'L'
            end
            if info.cym then
                -- Hi-hat 16ths: a disco beat always alternates (official 98-100%);
                -- plain ones from about 110 BPM (83%; 95-109 BPM 46%, slower 24%).
                local hh16 = p == 'hh' and pp == 'hh' and prev and math.abs(o.qn - prev.qn - 0.25) < 0.01
                local fast = single_prev and DRUM_ANIM_PIECES[pp].cym
                    and ((ms < P.cym_fast_ms and o.cym_run >= min_cym)
                      or (ms < P.cym_mid_ms and o.cym_run >= P.cym_long_run)
                      or (hh16 and o.disco and ms < P.cym_mid_ms)
                      or (hh16 and ms < P.hh16_fast_ms and o.cym_run >= min_cym))
                if fast then
                    hand = FastHand()
                elseif single_prev and not DRUM_ANIM_PIECES[pp].cym and ms < P.cym_mid_ms then
                    hand = FastHand()   -- a cymbal inside a fast drum run
                elseif p == 'c1' and pp == 'c2' and ph == 'R' and ms < P.window_ms then
                    hand = 'L'
                end
            else
                if single_prev and ms < P.drum_fast_ms and DRUM_ANIM_PIECES[pp].cym then
                    -- a drum straight after a cymbal: the other hand (official 96-100%)
                    hand = Other(ph)
                elseif single_prev and ms < P.drum_fast_ms then
                    hand = FastHand()
                elseif next_ms < P.drum_fast_ms and #nxt.pieces == 1
                       and not DRUM_ANIM_PIECES[nxt.pieces[1]].cym then
                    -- A fast run starts here: phase from the beat.
                    hand = phase or ((bp == 'trip') and 'R' or 'L')
                elseif single_prev and ms < P.window_ms and not DRUM_ANIM_PIECES[pp].cym then
                    if pp == p then
                        hand = ph
                    else
                        hand = info.pos > DRUM_ANIM_PIECES[pp].pos and 'R' or 'L'
                    end
                elseif prev and #prev.hands >= 2 and ms < P.window_ms and p ~= 'sn' then
                    hand = 'R'   -- first tom after a groove hit
                end
            end
            o.hands = { { p, hand } }

            -- A slow lone snare (official: L 50%, R 28%, both hands 22%):
            if p == 'sn' and ms >= P.slow_ms and next_ms >= P.drum_fast_ms then
                local near_next = nxt and next_ms < P.context_ms
                local np = near_next and nxt.pieces or {}
                local next_cym, next_tom, next_sn = false, false, false
                for _, q in ipairs(np) do
                    if DRUM_ANIM_PIECES[q].cym then next_cym = true
                    elseif q == 'sn' then next_sn = true else next_tom = true end
                end
                -- what was hit before, by gems (a both-hands snare is still "a snare")
                local pq = prev and #prev.pieces == 1 and prev.pieces[1]
                local prev_sn = pq == 'sn' and ms < P.context_ms
                local prev_tom = pq and pq ~= 'sn' and not DRUM_ANIM_PIECES[pq].cym and ms < P.context_ms
                local alone = not prev or ms >= P.pause_ms
                if bp ~= 'beat' and bp ~= 'and' then
                    o.hands = { { 'sn', 'L' } }                 -- ghost note (L 83%)
                elseif next_cym then
                    o.hands = { { 'sn', 'L' } }                 -- R gets ready for the cymbal (L 80%)
                elseif variety and prev_sn and next_sn and #np == 1 then
                    o.hands = { { 'sn', 'R' } }                 -- slow snare-only passage (R 40-52%)
                elseif variety and bp == 'beat' and (alone or prev_tom or next_tom) then
                    o.hands = { { 'sn', 'L' }, { 'sn', 'R' } }  -- an accent: both hands (~43%)
                end
            end
        else
            o.hands = {}
        end

        if #o.hands > 0 then prev = o end
    end

    -- Option: riding a crash in 8ths alternates soft and hard (RBN doc tip;
    -- official: only on 8ths, 6% of runs, 13% of slow ones - so off by default).
    if opts.crash_ride_alt then
        local run_piece, last_qn, k = nil, nil, 0
        for _, o in ipairs(onsets) do
            if #o.hands == 1 and (o.hands[1][1] == 'c1' or o.hands[1][1] == 'c2') then
                local p = o.hands[1][1]
                if run_piece == p and last_qn and math.abs(o.qn - last_qn - 0.5) < 0.02 then
                    k = k + 1
                else
                    k = 0
                end
                o.soft_hit = (k % 2 == 1)
                run_piece, last_qn = p, o.qn
            elseif #o.hands > 0 then
                run_piece, last_qn = nil, nil
            end
        end
    end

    for _, o in ipairs(onsets) do
        if o.K then notes[#notes + 1] = { qn = o.qn, pitch = DRUM_ANIM_KICK } end
        local choked = {}
        for _, ph in ipairs(o.hands) do
            local info = DRUM_ANIM_PIECES[ph[1]]
            local key = ph[2]
            local vel = PieceVel(o, ph[1])
            -- A crash's bands work in either order: the lower threshold takes the
            -- lowest velocities, the higher one the band between the two.
            local cut_ch, cut_soft = opts.choke_below, opts.soft_cym_below
            local is_choke = info.choke and cut_ch and vel < cut_ch
                             and not (cut_soft and cut_soft < cut_ch and vel < cut_soft)
            -- A choke replaces the hit: one note per cymbal, whichever hand (or both).
            if is_choke then
                if not choked[ph[1]] then
                    choked[ph[1]] = true
                    notes[#notes + 1] = { qn = o.qn, pitch = info.choke }
                end
            else
                -- Soft snare notes are ghost strokes in game (the kit snare does not
                -- move); soft cymbals still hit - hence separate thresholds.
                local below = (ph[1] == 'sn' and opts.soft_snare_below)
                           or (info.Ls and info.cym and opts.soft_cym_below)
                local soft = below and vel < below or false
                -- crash riding flips every other hit of the run against the velocity
                if o.soft_hit ~= nil and info.cym then soft = (soft ~= o.soft_hit) end
                if soft and info[key .. 's'] then key = key .. 's' end
                local qn = o.qn
                -- Option: in a flam the left hand lands slightly after the right (RBN
                -- doc tip; official flams are almost all on one tick - off by default).
                if opts.flam_late and o.flam and ph[2] == 'L' then qn = qn + P.flam_late_qn end
                notes[#notes + 1] = { qn = qn, pitch = info[key] }
            end
        end
    end
    return notes
end

-- Open hi-hat pedal notes (25) from planned onsets (after DrumAnimPlan).
--   opts.blue_open      - a hi-hat hit from a blue gem is open (Blue cymbal = Hi-hat plus
--                         "Open the hat on blue hi-hat hits" - Harmonix's way, not all
--                         community charts agree)
--   opts.open_hat_above - a hi-hat hit from a yellow gem (red in a disco flip) with a
--                         velocity above this is open; nil = off
-- Consecutive open hits (no closed hi-hat hit between) share one 25: from open_lead_qn
-- before the first (not back to the previous hi-hat hit) to the next hi-hat hit, or
-- open_tail_qn after the last when none comes within open_next_qn; at least
-- open_min_qn long unless the next hi-hat hit comes sooner.
-- Returns { { qn_s, qn_e, hits }, ... } sorted.
function DrumAnimOpenHatSpans(onsets, opts)
    opts = opts or {}
    local P = DRUM_ANIM_PARAMS
    if not opts.blue_open and not opts.open_hat_above then return {} end
    local hats = {}
    for _, o in ipairs(onsets) do
        for _, ph in ipairs(o.hands or {}) do
            if ph[1] == 'hh' then
                local lane = o.hh_lane
                local open = (lane == 'B' and opts.blue_open)
                    or (opts.open_hat_above and lane ~= 'B'
                        and PieceVel(o, 'hh') > opts.open_hat_above)
                hats[#hats + 1] = { qn = o.qn, open = open and true or false }
                break
            end
        end
    end
    local spans = {}
    local i = 1
    while i <= #hats do
        if hats[i].open then
            local j = i
            while hats[j + 1] and hats[j + 1].open do j = j + 1 end
            local first, last = hats[i].qn, hats[j].qn
            local prev, nxt = hats[i - 1], hats[j + 1]
            local s = first - P.open_lead_qn
            if prev and s <= prev.qn + EPS then s = (prev.qn + first) / 2 end
            local e
            if nxt and nxt.qn - last <= P.open_next_qn + EPS then e = nxt.qn
            else e = last + P.open_tail_qn end
            if e - s < P.open_min_qn then
                e = s + P.open_min_qn
                if nxt and e > nxt.qn then e = nxt.qn end
            end
            spans[#spans + 1] = { qn_s = s, qn_e = e, hits = j - i + 1 }
            i = j + 1
        else
            i = i + 1
        end
    end
    return spans
end

-- Onsets from Expert gems.
--   gems:  { { qn, sec, pitch, vel } } with pitch 95-100 (95 = 2x kick); vel optional
--   toms:  { { qn_s, qn_e, pitch } } tom markers 110-112
--   disco: { { qn_s, qn_e } } disco flip spans
function DrumAnimOnsets(gems, toms, disco)
    local by, order = {}, {}
    for _, g in ipairs(gems) do
        local key = math.floor(g.qn * 960 + 0.5)
        local o = by[key]
        if not o then
            o = { qn = g.qn, sec = g.sec }
            by[key] = o
            order[#order + 1] = o
        end
        local lane = ({ [95] = 'K', [96] = 'K', [97] = 'R', [98] = 'Y', [99] = 'B', [100] = 'G' })[g.pitch]
        if lane then
            o[lane] = true
            if g.vel and lane ~= 'K' then
                o.vel = o.vel or {}
                o.vel[lane] = math.max(o.vel[lane] or 0, g.vel)
            end
        end
    end
    table.sort(order, function(a, b) return a.qn < b.qn end)
    local function Under(spans, qn, pitch)
        for _, s in ipairs(spans) do
            if (not pitch or s.pitch == pitch) and qn >= s.qn_s - EPS and qn < s.qn_e - EPS then return true end
        end
        return false
    end
    for _, o in ipairs(order) do
        if o.Y then o.Yt = Under(toms, o.qn, 110) end
        if o.B then o.Bt = Under(toms, o.qn, 111) end
        if o.G then o.Gt = Under(toms, o.qn, 112) end
        o.disco = Under(disco or {}, o.qn)
    end
    return order
end

-- Disco flip spans from PART DRUMS text events ({ { qn, text } }): Expert's
-- "[mix 3 drums<N>d]" opens one, the next other Expert mix event closes it
-- ("[mix 3 drums<N>]", "...dnoflip]" - a disco beat that is not flipped, ...).
function DrumAnimDiscoSpans(texts, end_qn)
    local spans, open = {}, nil
    table.sort(texts, function(a, b) return a.qn < b.qn end)
    for _, t in ipairs(texts) do
        local is_mix = t.text:match('^%[mix 3 drums%d') ~= nil
        local is_disco = t.text:match('^%[mix 3 drums%dd%]') ~= nil
        if is_disco then
            open = open or t.qn
        elseif is_mix and open then
            spans[#spans + 1] = { qn_s = open, qn_e = t.qn }
            open = nil
        end
    end
    if open then spans[#spans + 1] = { qn_s = open, qn_e = end_qn or math.huge } end
    return spans
end

----------------------------------------------------------------------
-- REAPER side
----------------------------------------------------------------------

DRUM_ANIM_TRACKS = { 'PART DRUMS', 'PART DRUMS_2X' }

-- The options from S (Animation > Drums).
function DrumAnimOptions()
    return {
        crash1         = S.drum_anim_crash == 1,
        blue_hh        = S.drum_anim_blue_hh,
        blue_open      = S.drum_anim_blue_hh and S.drum_anim_blue_open,   -- Harmonix: a blue hi-hat is open
        open_hat_above = S.drum_anim_open_hat and S.drum_anim_open_hat_above or nil,
        soft_snare_below = S.drum_anim_soft_snare and S.drum_anim_soft_snare_below or nil,
        choke_below      = S.drum_anim_soft_cym and S.drum_anim_choke_below or nil,
        soft_cym_below   = S.drum_anim_soft_cym and S.drum_anim_soft_cym_below or nil,
        flam           = S.drum_anim_flam,
        min_cym_hits   = S.drum_anim_min_cym,
        snare_variety  = S.drum_anim_snare_variety,
        crash_ride_alt = S.drum_anim_ride_alt,
        flam_late      = S.drum_anim_flam_late,
    }
end

-- Read a drums take: Expert gems, tom markers and disco spans -> onsets.
local function ReadDrumsTake(take)
    local gems, toms, texts = {}, {}, {}
    local _, n_notes, _, n_txt = r.MIDI_CountEvts(take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, pitch, vel = r.MIDI_GetNote(take, i)
        if ok then
            if pitch >= 95 and pitch <= 100 then
                gems[#gems + 1] = { qn = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                                    sec = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                                    pitch = pitch, vel = vel }
            elseif pitch >= 110 and pitch <= 112 then
                toms[#toms + 1] = { qn_s = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                                    qn_e = r.MIDI_GetProjQNFromPPQPos(take, math.max(eppq, sppq + 1)),
                                    pitch = pitch }
            end
        end
    end
    for i = 0, n_txt - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and typ == 1 then texts[#texts + 1] = { qn = r.MIDI_GetProjQNFromPPQPos(take, ppq), text = msg } end
    end
    return DrumAnimOnsets(gems, toms, DrumAnimDiscoSpans(texts))
end

local function IsAnimPitch(p) return p >= 24 and p <= 51 and p ~= 25 end
local ANIM_RANGES = { { 24, 24 }, { 26, 51 } }   -- what the bulk write replaces (25 apart)
local PEDAL = 25

-- The open hi-hat pedal notes, only while an open-hat option is on. Of the 25s that
-- start in range, those with a hi-hat hit under them (open-hat 25s from an earlier run
-- or placed by hand) and those a new one would overlap are replaced; the rest - the
-- foot keeping time, 87% of official 25s - stay. Per note: a song has few.
-- in_range(qn), item_s / item_e in QN. Returns written, replaced.
local function WriteOpenHatPedal(take, onsets, spans, in_range, item_s, item_e)
    local hats = {}
    for _, o in ipairs(onsets) do
        for _, ph in ipairs(o.hands or {}) do
            if ph[1] == 'hh' then hats[#hats + 1] = o.qn break end
        end
    end
    local new = {}
    for _, sp in ipairs(spans) do
        if in_range(sp.qn_s) and sp.qn_s >= item_s - EPS and sp.qn_e <= item_e + EPS then
            new[#new + 1] = sp
        end
    end
    local function Covers(s, e, list)
        for _, q in ipairs(list) do if q >= s - EPS and q < e - EPS then return true end end
        return false
    end
    local function Overlaps(s, e)
        for _, sp in ipairs(new) do if s < sp.qn_e - EPS and e > sp.qn_s + EPS then return true end end
        return false
    end
    local replaced = 0
    local _, n_notes = r.MIDI_CountEvts(take)
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and pitch == PEDAL then
            local s = r.MIDI_GetProjQNFromPPQPos(take, sppq)
            local e = r.MIDI_GetProjQNFromPPQPos(take, math.max(eppq, sppq + 1))
            if in_range(s) and (Covers(s, e, hats) or Overlaps(s, e)) then
                r.MIDI_DeleteNote(take, i)
                replaced = replaced + 1
            end
        end
    end
    for _, sp in ipairs(new) do
        r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjQN(take, sp.qn_s),
                          r.MIDI_GetPPQPosFromProjQN(take, sp.qn_e), 0, PEDAL, 100, false)
    end
    return #new, replaced
end

-- The Generate button: PART DRUMS and PART DRUMS_2X, whole song or the notes
-- that start in the time selection. The hi-hat pedal (25) is touched only by the
-- open hi-hat options (WriteOpenHatPedal).
function GenerateDrumAnimations()
    local t0 = r.time_precise()
    local opts = DrumAnimOptions()
    local sel_s, sel_e = GetTimeSelection()
    local sel_s_qn = sel_s and r.TimeMap2_timeToQN(0, sel_s)
    local sel_e_qn = sel_e and r.TimeMap2_timeToQN(0, sel_e)

    local jobs, skipped = {}, {}
    for i, name in ipairs(DRUM_ANIM_TRACKS) do
        local track = FindTrackByName(name)
        if not track then
            if i == 1 then skipped[#skipped + 1] = name .. ': no track' end
        elseif r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then
            skipped[#skipped + 1] = name .. ': muted'
        else
            local item, take = FindFirstMIDIItem(track)
            local onsets = take and ReadDrumsTake(take) or {}
            if #onsets == 0 then
                skipped[#skipped + 1] = name .. ': no Expert notes'
            else
                local notes = DrumAnimPlan(onsets, opts)
                jobs[#jobs + 1] = { name = name, track = track, item = item, take = take,
                                    notes = notes, onsets = onsets }
            end
        end
    end
    if #jobs == 0 then
        S.status = 'Drum animations: nothing to write.'
        S.last_result = #skipped > 0 and table.concat(skipped, '\n') or nil
        return
    end

    local lines = {}
    if sel_s then lines[#lines + 1] = 'Range: the time selection (planned from the whole song).' end
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local total = 0
    for _, j in ipairs(jobs) do
        r.MarkTrackItemsDirty(j.track, j.item)
        local take = j.take
        local function InRange(qn)
            return not sel_s or (qn >= sel_s_qn - EPS and qn < sel_e_qn - EPS)
        end
        -- the old animation notes (not the hi-hat pedal) that start in range
        local _, n_notes = r.MIDI_CountEvts(take)
        local removed = 0
        for i = 0, n_notes - 1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok and IsAnimPitch(pitch) and InRange(r.MIDI_GetProjQNFromPPQPos(take, sppq)) then
                removed = removed + 1
            end
        end
        local pos = r.GetMediaItemInfo_Value(j.item, 'D_POSITION')
        local i_s = r.TimeMap2_timeToQN(0, pos)
        local i_e = r.TimeMap2_timeToQN(0, pos + r.GetMediaItemInfo_Value(j.item, 'D_LENGTH'))
        local new, outside = {}, 0
        for _, n in ipairs(j.notes) do
            if InRange(n.qn) then
                if n.qn >= i_s - EPS and n.qn + DRUM_ANIM_PARAMS.len_qn <= i_e + EPS then
                    new[#new + 1] = { s = r.TimeMap2_QNToTime(0, n.qn),
                                      e = r.TimeMap2_QNToTime(0, n.qn + DRUM_ANIM_PARAMS.len_qn),
                                      pitch = n.pitch }
                else
                    outside = outside + 1
                end
            end
        end
        -- One read and one write of the take (per-note inserts took 5-25 s on a song).
        if not ReplaceNotesBulk(take, sel_s, sel_e, ANIM_RANGES, new, 100) then
            for i = n_notes - 1, 0, -1 do
                local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
                if ok and IsAnimPitch(pitch) and InRange(r.MIDI_GetProjQNFromPPQPos(take, sppq)) then
                    r.MIDI_DeleteNote(take, i)
                end
            end
            for _, n in ipairs(new) do
                r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, n.s),
                    r.MIDI_GetPPQPosFromProjTime(take, n.e), 0, n.pitch, 100, false)
            end
        end
        r.MIDI_Sort(take)   -- as Difficulty > Generate does after its bulk write
        local pedal_n, pedal_old, pedal_hits = 0, 0, 0
        if opts.blue_open or opts.open_hat_above then
            local spans = DrumAnimOpenHatSpans(j.onsets, opts)
            for _, sp in ipairs(spans) do if InRange(sp.qn_s) then pedal_hits = pedal_hits + sp.hits end end
            pedal_n, pedal_old = WriteOpenHatPedal(take, j.onsets, spans, InRange, i_s, i_e)
        end
        local written = #new
        total = total + written
        -- what the hands did
        local left, right, two, flams = 0, 0, 0, 0
        for _, o in ipairs(j.onsets) do
            if InRange(o.qn) then
                if o.flam then flams = flams + 1 elseif #o.hands >= 2 then two = two + 1 end
                if #o.hands == 1 then
                    if o.hands[1][2] == 'L' then left = left + 1 else right = right + 1 end
                end
            end
        end
        if #lines > 0 then lines[#lines + 1] = '' end
        lines[#lines + 1] = j.name
        lines[#lines + 1] = string.format('- Total %d notes%s', written,
                                          removed > 0 and string.format(' (replaced %d notes)', removed) or '')
        local kicks = 0
        for _, n in ipairs(new) do if n.pitch == DRUM_ANIM_KICK then kicks = kicks + 1 end end
        -- Total = kicks + one hand hits + two notes per two hand hit and per flam.
        lines[#lines + 1] = string.format('- Kicks: %d', kicks)
        lines[#lines + 1] = string.format('- One hand hits: %d (%d right / %d left)', right + left, right, left)
        lines[#lines + 1] = string.format('- Two hand hits: %d (%d notes)', two, 2 * two)
        lines[#lines + 1] = string.format('- Flams: %d (%d notes)', flams, 2 * flams)
        if opts.soft_snare_below or opts.soft_cym_below or opts.choke_below then
            local SOFT_SN = { [28] = true, [29] = true }
            local SOFT_CY = { [35] = true, [37] = true, [39] = true, [45] = true }
            local n_sn, n_cy, n_ch = 0, 0, 0
            for _, n in ipairs(new) do
                if SOFT_SN[n.pitch] then n_sn = n_sn + 1
                elseif SOFT_CY[n.pitch] then n_cy = n_cy + 1
                elseif n.pitch == 40 or n.pitch == 41 then n_ch = n_ch + 1 end
            end
            lines[#lines + 1] = string.format('- By velocity: %d soft snares, %d soft crashes, %d chokes',
                                              n_sn, n_cy, n_ch)
        end
        if opts.blue_open or opts.open_hat_above then
            lines[#lines + 1] = string.format('- Open hi-hat: %d pedal notes (25) over %d open hits%s',
                pedal_n, pedal_hits,
                pedal_old > 0 and string.format(', %d old open-hat 25s replaced', pedal_old) or '')
        end
        if outside > 0 then
            lines[#lines + 1] = string.format('- %d notes outside the MIDI item - extend the item and run again', outside)
        end
    end
    r.Undo_EndBlock2(0, string.format('Generate drum animations (%d notes)', total), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local o = opts
    local function OnOff(v) return v and 'on' or 'off' end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Options'
    lines[#lines + 1] = '- Default crash: ' .. (o.crash1 and 'crash 1' or 'crash 2')
    lines[#lines + 1] = '- Blue cymbal: ' .. (o.blue_hh and 'hi-hat' or 'ride')
    if o.blue_hh then lines[#lines + 1] = '- Open the hat on blue hi-hat hits: ' .. OnOff(o.blue_open) end
    lines[#lines + 1] = '- Min cymbal hits: ' .. (o.min_cym_hits or DRUM_ANIM_PARAMS.min_cym_hits)
    lines[#lines + 1] = '- Open hi-hat by velocity: ' .. (o.open_hat_above
        and ('above velocity ' .. o.open_hat_above) or 'off')
    lines[#lines + 1] = '- Snare + yellow tom as a flam: ' .. OnOff(o.flam)
    lines[#lines + 1] = '- Slow snare variety: ' .. OnOff(o.snare_variety)
    lines[#lines + 1] = '- Soft snare hits (ghost strokes): ' .. (o.soft_snare_below
        and ('below velocity ' .. o.soft_snare_below) or 'off')
    lines[#lines + 1] = '- Crash hits by velocity: ' .. (o.soft_cym_below
        and ('choke below ' .. o.choke_below .. ', soft below ' .. o.soft_cym_below) or 'off')
    lines[#lines + 1] = '- Crash riding soft / hard: ' .. OnOff(o.crash_ride_alt)
    lines[#lines + 1] = '- Flam left hand late: ' .. OnOff(o.flam_late)
    lines[#lines + 1] = ''
    if o.blue_open or o.open_hat_above then
        lines[#lines + 1] = 'Hi-hat pedal (25): open-hat notes written; the other 25s (the foot ' ..
                            'keeping time) were left as they were.'
    else
        lines[#lines + 1] = 'The hi-hat pedal notes were left as they were.'
    end
    local dt = r.time_precise() - t0
    if dt > 2 then lines[#lines + 1] = string.format('Took %.1f s.', dt) end
    if #skipped > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Skipped:'
        for _, s in ipairs(skipped) do lines[#lines + 1] = '  ' .. s end
    end
    S.status = string.format('Drum animations: %d notes on %d track%s.', total, #jobs, #jobs == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end
