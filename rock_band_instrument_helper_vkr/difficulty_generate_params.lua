-- Difficulty > Generate: the parameters and small rules every planner shares - the
-- tuned numbers (GEN5_PARAMS), beat classes, gaps, sustain minimums and release gaps.
--
-- PURE: no r, no S. Loaded first of the Generate modules; difficulty_generate_rhythm.lua
-- and difficulty_generate_5lane.lua bind Gen5MinGapQN, Gen5MinSustainQN,
-- Gen5ReleaseGapQN and the GEN5_* constants at load time.
--
-- Requires (globals, read at call time): DiffReleaseGapQN, DiffSustainTooShort
--   (actions_difficulty_shared.lua).
--
-- What each rule does and why - its source and the measured numbers - is in
-- docs/difficulty_reduction.md, "Guitar, Bass and Keys" and "Pro Keys". Keep the two in step.

-- ONE RHYTHM MODEL FOR EVERY INSTRUMENT. Which onsets a tier keeps depends only on where
-- the onsets are (and the tempo), never on their colors, chords or instrument, and every
-- instrument uses the same numbers - so parts that play the same rhythm on Expert play the
-- same rhythm on every tier. Chords and colors are reduced afterwards and never change which
-- onsets survive. One exception: a busy Hard bar saves its sustains and accent chords for
-- last (ThinBusyBars), so two instruments could lose different notes; Guitar leads there -
-- Bass and Keys take Guitar's choice in a bar of the same rhythm (opts.busy_ref) unless that
-- would remove their own protected note.
GEN5_PARAMS = {
    -- Minimum onset-to-onset gap a tier keeps: the larger of a grid floor (quarter notes)
    -- and a time floor (seconds), so the same chart thins more at fast tempos, never more
    -- than `cap`, the tier's note value (Hard 1/8, Medium 1/4, Easy 1/2) - past it, fast
    -- passages are thinned by bar position (busy_bar_onsets / busy_drop).
    -- TUNED against the official tiers (run_generate_eval_offline.lua tune); change a value
    -- only by re-running that sweep.
    gap = {
        H = { grid = 0.5, sec = 0.15, cap = 0.5 },
        M = { grid = 1.0, sec = 0.30, cap = 1.0 },
        E = { grid = 1.0, sec = 0.70, cap = 2.0 },
    },
    -- How much an onset is worth keeping, by beat position. The thinning keeps the
    -- highest total weight that respects the gap, so these decide WHICH notes go.
    weight = { down = 8, beat = 5, ['8th'] = 3, ['16th'] = 1.5, trip = 2, other = 1 },
    -- An onset holding a sustain (SUSTAIN_QN or longer) is worth this much more - a sustain
    -- on a beat (5 + 3.5) wins over a short note on a bar line (8) when only one fits. On
    -- Medium and Easy it counts only when the note can still be a sustain there: held to the
    -- next upper onset less the tier's release gap, at least min_sustain.
    sustain_bonus = 3.5,
    -- Shortest sustain each tier keeps (above fast_bpm: _fast); shorter ones become plain notes.
    min_sustain      = { H = 0.5, M = 0.75, E = 1.0 },
    min_sustain_fast = { M = 1.0, E = 1.0 },
    -- Hard keeps Expert's sustain lengths, but a Guitar/Bass sustain shorter than qn (at
    -- any tempo) or ms becomes a plain note: Hard's slower highway draws the same tail
    -- shorter. Official Hard drops most of those; Keys keeps them. nil = none for that kind.
    -- Every kind also drops a sustain under 3/16 at 100+ BPM (DiffSustainTooShort).
    -- The ms floor applies only when Hard's next note starts less than ms_room QN after the
    -- tail: with nothing close behind, the tail has time to read (user rule; official Hard
    -- keeps about half of those, against a fifth to two fifths with a note close behind).
    -- ms_grace: a length within this many ms under the floor still passes, so a note on the
    -- line is not judged by which side of a tempo marker its tempo was read on.
    hard_min_sustain = { gb = { qn = 0.75, ms = 300, ms_room = 1.0, ms_grace = 3 } },
    -- A chord next to a single note is worth this much more on Medium: an "and" chord
    -- (3 + 2.5) outweighs a beat single (5) but not a downbeat (8). Bass and Keys follow
    -- Guitar's Medium in bars of the same rhythm (opts.rhythm_ref).
    chord_bonus = { M = 2.5 },
    -- The bar's last note on its last "and", before an empty next downbeat (it ends the
    -- phrase), is worth this much more on Medium and Easy - an "and" (3 + 5) then outweighs
    -- a beat-4 chord (5 + 2.5) - and on Easy needs only phrase_end_gap after the previous
    -- kept note.
    phrase_end_bonus = { M = 5, E = 5 },
    phrase_end_gap = { E = 1.5 },
    -- Medium keeps a note per beat in busy bars (FillBeats).
    fill_beats = { M = true },
    -- A keys lick that starts on an "and" (Gen5AndPhrases): Medium reduces the phrase on
    -- the "and" grid and Easy goes back to Hard's downbeats there. A phrase is a run of
    -- upper-tier onsets with no gap of `rest` or more, at least `min_onsets` long; it
    -- qualifies when its first onset is on an "and" AND its "and" line changes note more
    -- often than its beat line by more than `variety_margin` (changes per step). `kinds`:
    -- the instruments it applies to.
    and_phrase = { kinds = { k5 = true, pk = true }, rest = 2.0, min_onsets = 8, variety_margin = 0.2 },
    -- Most of the upper tier's onsets a tier may keep (nil = no cap). Above it, whole bar
    -- positions are removed across the song (CapKeep), so a sparse chart still gets a
    -- visibly easier tier.
    max_keep = { H = 0.95 },
    -- A bar the gap left completely untouched, with at least this many onsets, still loses
    -- a note (ThinBusyBars) - the song-wide cap misses such bars when the rest of the song
    -- already thinned enough. Hard only; the Medium and Easy gaps always thin 8ths.
    busy_bar_onsets = { H = 6 },
    -- How many notes a bar of straight 8ths loses (opts.busy_drop): 1 (the and of 4) or 2
    -- (also the and of 2). A bar that already leaves 8th slots empty loses that many fewer,
    -- never fewer than one. Left unset it is decided once per song from the tempo at the
    -- first note: 2 above fast_8ths_bpm.
    fast_8ths_bpm = 160,
    -- Hard rewrites runs closer than its gap one grid slower (16ths to 8th triplets, 8th
    -- triplets to 8ths) instead of thinning them in place - difficulty_generate_retime.lua.
    -- The penalty (in 1/24 QN of movement) is what a skip that invents a color move costs.
    retime_color_penalty = 20,
    -- The shortest run a song at or below fast_8ths_bpm rewrites, as a share of its bar
    -- (0.5 = half a bar: 8 consecutive 16ths in 4/4). Shorter groups stay thinned: at these
    -- tempos a 16th pair is usually part of the groove.
    retime_min_run = { slow = 0.5 },
    -- When Hard rewrites fast runs (the Generate sub-tab's "Hard fast runs", opts.fast_runs):
    --   'auto'    - above fast_8ths_bpm only (any run); slower songs are thinned;
    --   'thin'    - never: every run is thinned in place;
    --   'rewrite' - above fast_8ths_bpm any run, at or below it runs of retime_min_run.
    fast_runs_default = 'rewrite',
    -- An onset is ISOLATED when its gaps to both neighbouring upper-tier onsets are more
    -- than this (quarter notes). Spacing only, so it keeps the one-rhythm rule. Hard's cap
    -- and busy-bar rule never remove an isolated onset, and Medium keeps them.
    isolated_qn = 1.0,
    -- When a tier keeps more than this share of the upper tier's onsets, the rhythm barely
    -- changed, so it is made easier by color instead: each bar moves down as a whole until
    -- its top note is color_fallback_top - Hard Blue (O B Y -> B Y R), Medium Yellow.
    -- Colors only; the tiers below inherit it. Medium tries offbeat_fallback_keep first.
    color_fallback_keep = { H = 0.95, M = 0.95 },
    color_fallback_top  = { H = 3, M = 2 },   -- Blue, Yellow
    -- Medium that keeps more than this share of Hard first drops its isolated off-beats
    -- (isolated_qn), and only if it still keeps too much is eased by color.
    offbeat_fallback_keep = { M = 0.95 },
    -- Gap left between a sustain's end and the next note - what each tier aims for.
    -- Hard 1/16 (the RBN standard gap), so it keeps Expert's length; Medium a dotted 8th,
    -- Easy a quarter; above fast_bpm, Medium a quarter and Easy a half note. Medium and Easy
    -- never go below DiffReleaseGapQN, the floor Validate enforces. A sustain that cannot
    -- leave this gap and stay long enough (min_sustain) becomes a 1/32 note, so it clearly
    -- reads as a plain note.
    release      = { H = 0.25, M = 0.75, E = 1.0 },
    release_fast = { M = 1.0, E = 2.0 },
    fast_bpm     = 160,
    -- A rest longer than this (quarter notes) ends a color-shift segment, and a segment is
    -- never longer than segment_max (color_shift = 'segments'). Longer, not "at least": a
    -- Medium line is mostly quarter notes, and splitting at every quarter moved only the
    -- top note of a line (G Y B O became G Y B B, a repeat Hard never had).
    segment_gap = 1.0,
    segment_max = 8.0,
    -- How Guitar/Bass Medium/Easy bring notes under their top lane:
    --   'clamp'    - only the notes above it move down, unless that makes a color repeat
    --                the tier above does not have; then the whole bar moves down
    --                (Gen5ClampOrShiftBars - G O Y B -> G B Y B, and
    --                G Y B O -> G R Y B rather than G Y B B);
    --   'bars'     - every such bar moves down whole (Gen5ShiftBars);
    --   'segments' - each passage moves down whole (Gen5ShiftSegments, segment_gap).
    color_shift = 'clamp',
}

-- Shared limits, in quarter notes. Global so every Generate module uses the same values.
GEN5_SUSTAIN_QN = 0.5     -- a note this long or longer counts as sustained (1/8 note)
-- Shortest note written (1/32 note), and so the closest two kept onsets may be. Validate
-- rejects anything under 1/64; upper tiers sometimes carry near-zero lengths and flams
-- a few milliseconds apart, which would otherwise be copied straight through.
GEN5_MIN_LEN_QN = 0.125
GEN5_EPS        = 0.02    -- quarter-note tolerance for "on the grid" and gap tests

local SUSTAIN_QN = GEN5_SUSTAIN_QN
local EPS        = GEN5_EPS

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

-- The beat of a time signature, in quarter notes - an event's `pulse`. Compound meters
-- (6/8, 9/8, 12/8) count in dotted quarters: the strong beats of a 6/8 bar are its 1st and
-- 4th 8ths, 1.5 QN apart. Everything else counts quarter notes from the bar line, odd /8
-- bars (5/8, 7/8) included - they have no even beat to count instead. Counted in quarter
-- notes, a 6/8 Medium would keep three notes against the bar's two beats.
function Gen5PulseQN(num, den)
    if den == 8 and num >= 6 and num % 3 == 0 then return 1.5 end
    return 1
end

-- A bar in 4/4: the meter the measured position tables (CAP_KEEP_RATE, the RBN "every
-- fourth note per half measure" positions) describe. Events without meter data are 4/4.
function Gen5Is44(ev)
    return math.abs((ev.bar_len or 4) - 4) <= EPS and (ev.pulse or 1) == 1
end

-- Beat position of an onset: down (bar line), beat, 8th, 16th, trip, other. Counted from
-- the bar line (bar_qn), in the bar's own beat (pulse): a 6/8 bar's beats are 0 and 1.5,
-- and a bar after a 7/8 bar starts on an off-beat quarter note.
function Gen5BeatClass(ev)
    if ev.down then return 'down' end
    local qn = ev.bar_qn or ev.qn
    if NearInt(qn / (ev.pulse or 1), EPS) then return 'beat' end
    if NearInt(qn * 2, EPS * 2) then return '8th'  end
    if NearInt(qn * 4, EPS * 4) then return '16th' end
    if NearInt(qn * 3, EPS * 3) or NearInt(qn * 6, EPS * 6) then return 'trip' end
    return 'other'
end

-- Minimum onset-to-onset gap tier dl keeps at this tempo (GEN5_PARAMS.gap). A grid of a
-- beat or more (Medium, Easy) is counted in the bar's beat (pulse): in 6/8 Medium's beat
-- grid is a dotted quarter, so it keeps the two beats rather than three quarter notes
-- across them. Hard's 8th grid is an 8th in every meter.
function Gen5MinGapQN(dl, bpm, pulse)
    local g = GEN5_PARAMS.gap[dl]
    local grid = g.grid >= 1 and g.grid * (pulse or 1) or g.grid
    return math.min(math.max(grid, g.sec * (bpm or 120) / 60), math.max(g.cap or math.huge, grid))
end

-- Shortest sustain tier dl keeps at this tempo (GEN5_PARAMS.min_sustain).
function Gen5MinSustainQN(dl, bpm)
    local p = GEN5_PARAMS
    if (bpm or 120) > p.fast_bpm and p.min_sustain_fast[dl] then return p.min_sustain_fast[dl] end
    return p.min_sustain[dl] or SUSTAIN_QN
end

-- Hard: true when a sustain len_qn long at tempo bpm is played as a plain note - under 3/16
-- at 100+ BPM (DiffSustainTooShort, Validate's Expert/Hard rule), or under the kind's
-- hard_min_sustain (the same 5% grace on qn as Validate, ms_grace on ms). room_qn: from the
-- tail's end to Hard's next onset (nil = none follows); the ms floor needs a note close behind.
function Gen5HardSustainTooShort(kind, len_qn, bpm, room_qn)
    if len_qn < SUSTAIN_QN - EPS then return false end
    if DiffSustainTooShort(len_qn, bpm) then return true end
    local min = GEN5_PARAMS.hard_min_sustain[kind]
    if not min then return false end
    if min.qn and len_qn < min.qn * 0.95 then return true end
    local close = room_qn and (not min.ms_room or room_qn < min.ms_room - EPS)
    return (min.ms and close and len_qn * 60000 / (bpm or 120) < min.ms - (min.ms_grace or 1)) or false
end

-- Gap a sustain must leave before the next note on this tier.
function Gen5ReleaseGapQN(kind, dl, ev)
    local p = GEN5_PARAMS
    local need = p.release[dl] or 0.25
    if (ev.bpm or 120) > p.fast_bpm and p.release_fast[dl] then need = p.release_fast[dl] end
    local floor = DiffReleaseGapQN(dl, ev.bpm)
    if floor and floor > need then need = floor end
    if kind == 'k5' and (dl == 'H' or dl == 'X') and #ev.offs > 1 then
        need = math.max(need, 0.5)   -- Keys X/H: 1/8 after a sustained chord
    end
    return need
end

-- Roll, trill and tremolo lanes (126/127) count on Hard too when the lane marker's velocity
-- is 41-50 (RBN doc: "If you want to use trills and tremolos on Hard difficulty, author your
-- markers with a velocity between 50 and 41"; the drums page says the same of rolls). Hard
-- then plays Expert's notes under such a lane as they are: the game plays them as a lane,
-- and the lane's first note must stay where the marker starts.
-- Pro Keys has a track per tier, so a trill marker on the Hard track is a Hard lane at any
-- velocity (span.hard): the author put it there by hand.
GEN_HARD_LANE_VEL = { lo = 41, hi = 50 }
-- Lane membership: from the lane's start to its end, both included (a roll or trill lane
-- ends at, or just past, the start of its last note). 0.004 QN is 1 ms at 240 BPM.
local LANE_TOL = 0.004

function GenHardLane(span)
    if span.hard then return true end
    return span.vel ~= nil and span.vel >= GEN_HARD_LANE_VEL.lo and span.vel <= GEN_HARD_LANE_VEL.hi
end

-- Hard (out) with every note under a Hard lane replaced by a copy of the upper tier's notes
-- there. A note next to a lane is shortened so it does not run into the lane's notes, nor
-- a lane's last note into the next note. Returns out, and the number of lanes copied.
function GenKeepHardLanes(out, upper, lanes)
    local hard = {}
    for _, sp in ipairs(lanes or {}) do if GenHardLane(sp) then hard[#hard + 1] = sp end end
    if #hard == 0 then return out, 0 end
    local function InLane(qn)
        for _, sp in ipairs(hard) do
            if qn >= sp.qn - LANE_TOL and qn <= sp.qn_e + LANE_TOL then return sp end
        end
        return nil
    end
    local res, copy, used = {}, {}, {}
    for _, ev in ipairs(out) do
        if not InLane(ev.qn) then res[#res + 1] = ev end
    end
    for _, ev in ipairs(upper) do
        local sp = InLane(ev.qn)
        if sp then
            local c = {}
            for k, v in pairs(ev) do c[k] = v end
            c.offs = {}
            for i, o in ipairs(ev.offs) do c.offs[i] = o end
            res[#res + 1] = c
            copy[c], used[sp] = true, true
        end
    end
    table.sort(res, function(a, b) return a.qn < b.qn end)
    for i = 1, #res - 1 do
        local a, b = res[i], res[i + 1]
        if copy[a] ~= copy[b] and a.qn_e > b.qn - EPS / 2 then
            local gap = b.qn - a.qn
            if a.qn_e - a.qn >= SUSTAIN_QN - EPS and gap - 0.25 >= SUSTAIN_QN - EPS then
                a.qn_e = b.qn - 0.25          -- still a sustain, a 1/16 before the lane
            else
                a.qn_e = a.qn + math.min(0.125, gap - EPS / 2)
            end
        end
    end
    local n = 0
    for _ in pairs(used) do n = n + 1 end
    return res, n
end
