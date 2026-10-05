-- Difficulty > Generate: the reduction planner for the 5-lane instruments (Guitar,
-- Bass, Keys). Builds one tier from the tier above it.
--
-- PURE: no r, no S. Takes plain event tables and returns plain event tables, so the
-- offline evaluation (dev/calibration/run_generate_eval_offline.lua) runs exactly the
-- code the helper ships. The REAPER side - reading tracks, writing notes, undo - lives
-- in actions_difficulty_generate.lua.
--
-- Input event:  { qn, qn_e, offs = { gem offsets 0-4, ascending }, bpm, down, bar_qn, bar_len }
--   qn / qn_e - onset and end in quarter notes; bpm - tempo at the onset;
--   down      - true when the onset is on a bar line;
--   bar_qn    - quarter notes from the bar line (optional; 4/4 is assumed without it);
--   bar_len   - length of the onset's bar in quarter notes (optional; 4 without it).
-- Output event: { qn, qn_e, offs } with offs relative to the TARGET tier's lowest pitch.
--
-- What it aims for is what official charts do, not merely what Validate requires:
-- Validate's errors barely thin Guitar/Bass Medium and Easy, whose spacing rules are
-- advisories. The targets come from dev/calibration/run_difficulty_probe_vkr.lua over
-- the official RB3 DLC charts - Hard keeps nearly every beat and most 8ths, Medium drops
-- most remaining 8ths, Easy keeps the downbeats and about half the beats - and are
-- tuned against those charts with run_generate_eval_offline.lua.
--
-- Requires (globals, read at call time): GB_MAX_CHORD, GB_MAX_SPAN, GB_RANGE,
--   K5_MAX_CHORD, K5_MIN_SP (actions_difficulty_gtrbass.lua / _5k.lua),
--   DiffReleaseGapQN (actions_difficulty_shared.lua),
--   Gen5RetimeDenseRuns (difficulty_generate_retime.lua), Gen5ReduceChordSize /
--   Gen5NarrowSpan / Gen5ShiftSegments / Gen5ShiftBars (difficulty_generate_colors.lua).

-- ONE RHYTHM MODEL FOR EVERY INSTRUMENT. Which onsets a tier keeps depends only on where
-- the onsets are (and the tempo), never on their colors, chords or instrument, and every
-- instrument uses the same numbers. So Guitar, Bass, Keys (and Pro Keys, when it gets a
-- planner) that play the same rhythm on Expert play the same rhythm on Hard, Medium and
-- Easy. Chords and colors are reduced afterwards and never change which onsets survive.
-- This is a product choice: official Keys Hard keeps more of Expert than Guitar/Bass does,
-- and following that would give the band different rhythms for the same part.
-- One exception, and how it is kept in line: a busy bar on Hard saves its sustains and
-- accent chords for last (ThinBusyBars), so two instruments with the same rhythm could
-- lose different notes. Guitar leads there - Bass and Keys take Guitar's choice in a bar
-- of the same rhythm (opts.busy_ref) unless that would remove their own protected note.
GEN5_PARAMS = {
    -- Minimum onset-to-onset gap a tier keeps: the larger of a grid floor (quarter notes)
    -- and a time floor (seconds), so the same chart thins more at fast tempos.
    --
    -- TUNED, not chosen: the best onset F1 against the official Guitar/Bass tiers over the
    -- development songs (run_generate_eval_offline.lua tune; hold-out excluded). Change a
    -- value only by re-running that sweep.
    --
    -- cap: the gap never exceeds the tier's note value (Hard 1/8, Medium 1/4, Easy 1/2).
    -- Without it the time term crossed the next note value on fast songs and a whole
    -- rhythm level vanished at once - at 210 BPM Hard lost every off-beat 8th, Medium
    -- every other beat, Easy went to whole notes. Official charts do none of that: for a
    -- bar of straight 8ths, Hard drops one or two off-beats at every tempo (dropping all
    -- of them is 2-4%), and Easy keeps beats 1 and 3 at every tempo (93-97%). Past the
    -- cap, fast passages are thinned by bar position (busy_bar_onsets / busy_drop).
    gap = {
        H = { grid = 0.5, sec = 0.15, cap = 0.5 },
        M = { grid = 1.0, sec = 0.30, cap = 1.0 },
        E = { grid = 1.0, sec = 0.70, cap = 2.0 },
    },
    -- How much an onset is worth keeping, by beat position. The thinning keeps the
    -- highest total weight that respects the gap, so these decide WHICH notes go.
    weight = { down = 8, beat = 5, ['8th'] = 3, ['16th'] = 1.5, trip = 2, other = 1 },
    -- An onset holding a sustain (SUSTAIN_QN or longer) is worth this much more. Note
    -- length is part of the rhythm, so this does not break the one-rhythm rule. 3.5 makes
    -- a sustain on a beat (5 + 3.5) win over a short note on a bar line (8) when only one
    -- fits - Easy kept the short downbeat and dropped a long held note at exactly 3.0.
    -- Offline F1 is unchanged or better on every tier against 3.0 (tune sweep).
    sustain_bonus = 3.5,
    -- On Medium and Easy the bonus counts only when the note can still be a sustain there:
    -- held to the next upper onset less the tier's release gap, at least min_sustain.
    -- A note whose tail the tier would cut anyway is just a note (chronosp bar 7: a held
    -- note on 3& won over beat 3 on Medium, and was then cut to a 1/8 tail).
    -- Shortest sustain each tier keeps; shorter ones become plain notes. Measured on the
    -- official RB3 DLC Guitar/Bass (dev songs): Medium sustains above 160 BPM are never
    -- under 0.875 QN (1st percentile 1.0), at <= 160 BPM 1st percentile 0.75; Easy 1.0
    -- both. Hard stays at the 1/8 every tier used before.
    min_sustain      = { H = 0.5, M = 0.75, E = 1.0 },
    min_sustain_fast = { M = 1.0, E = 1.0 },
    -- A chord is worth this much more on Medium: an "and" chord (3 + 2.5) outweighs a beat
    -- single (5) but not a downbeat (8). Official Medium keeps the chord of a beat single
    -- and an 8th-later chord 83% of the time (8748 vs 894), but a downbeat single over the
    -- chord before it 59% (387 vs 221). Chord size is not rhythm, so Bass and Keys follow
    -- Guitar's Medium in bars of the same rhythm (opts.rhythm_ref).
    chord_bonus = { M = 2.5 },
    -- Medium keeps a note per beat in busy bars (FillBeats). A switch so the evaluator can
    -- measure what it costs against official charts.
    fill_beats = { M = true },
    -- Most of the upper tier's onsets a tier may keep (nil = no cap). Above it, whole bar
    -- positions are removed across the song (CapKeep), so a sparse chart still gets a
    -- visibly easier tier: without a cap, an Expert with no 16ths passes the Hard gap
    -- untouched and Validate flags an unchanged copy. A product choice, not tuned.
    max_keep = { H = 0.95 },
    -- A bar the gap left completely untouched, with at least this many onsets, still
    -- loses a note (ThinBusyBars). The song-wide cap above misses such bars when the rest
    -- of the song already thinned enough - a passage of steady 8ths between 16th runs
    -- came through Hard identical to Expert. Hard only; the Medium and Easy gaps always
    -- thin 8ths.
    busy_bar_onsets = { H = 6 },
    -- How many notes a bar of straight 8ths loses: 1 (the and of 4) or 2 (also the and of
    -- 2 - "two groups of three"). A bar that already leaves 8th slots empty loses that
    -- many fewer, never fewer than one. Chosen by the caller (opts.busy_drop); left unset it is decided
    -- once per song from the tempo at the first note: 2 above fast_8ths_bpm. The RBN
    -- Guitar/Bass and Keys docs: "If the song is fast (over 160 bpm), the player shouldn't
    -- be expected to play continuous 8th notes. Thin the chart out by removing every
    -- fourth note per half measure." Official Hard keeps 7 or 6 of 8 straight 8ths about
    -- equally often at every tempo, so the user can override it per song.
    fast_8ths_bpm = 160,
    -- Above fast_8ths_bpm, Hard rewrites runs closer than its gap one grid slower (16ths to
    -- 8th triplets, 8th triplets to 8ths) instead of thinning them in place - see
    -- difficulty_generate_retime.lua. The penalty (in 1/24 QN of movement) is what a skip
    -- that invents a color move costs; 20 matched the chronosp_brutal_decay hand reduction
    -- best of the variants tried (165 of 170 colors).
    retime_color_penalty = 20,
    -- An onset is ISOLATED when its gaps to both neighbouring upper-tier onsets are more
    -- than this (quarter notes). Spacing only, so it keeps the one-rhythm rule.
    -- Hard never removes an isolated onset through the cap or the busy-bar rule: on a
    -- sparse chart (a beginner Keys part of long sustains and a few dotted-quarter notes)
    -- those removals made Hard thinner than official Hard, which keeps a median 92% of
    -- Expert on the easiest Keys songs. Medium keeps them too: it used to drop isolated
    -- OFF-BEAT onsets (the RBN tip "Try to only have playable notes on strong quarter note
    -- beats"), but official Medium keeps 99% of them (935 of 943 above 160 BPM, 4033 of
    -- 4106 at or below; RB3 DLC Guitar/Bass dev songs), and Medium F1 rose on every
    -- instrument without the drop (chronosp bass bar 52 lost its 4& note to it).
    isolated_qn = 1.0,
    -- When a tier keeps more than this share of the upper tier's onsets, the rhythm barely
    -- changed, so it is made easier by color instead: each bar moves down as a whole until
    -- its top note is color_fallback_top - Hard Blue (O B Y -> B Y R), Medium Yellow.
    -- Colors only; the tiers below inherit it. Medium tries offbeat_fallback_keep first.
    color_fallback_keep = { H = 0.95, M = 0.95 },
    color_fallback_top  = { H = 3, M = 2 },   -- Blue, Yellow
    -- Medium that keeps more than this share of Hard first drops its isolated off-beats
    -- (isolated_qn), and only if it still keeps too much is eased by color. A product
    -- choice, not official practice: official Medium on such simple parts keeps them all
    -- (560 of 560 in 58 parts) and changes colors and chord sizes instead. The user prefers
    -- removing a note to recoloring a line (pojat_lemmikkih Keys, where Medium came out
    -- the same as Hard but for sustain lengths).
    offbeat_fallback_keep = { M = 0.95 },
    -- Gap left between a sustain's end and the next note - what each tier aims for.
    -- Hard 1/8, Medium a dotted 8th, Easy a quarter; above fast_bpm, Medium a quarter and
    -- Easy a half note. Medium and Easy never go below DiffReleaseGapQN, the floor Validate
    -- enforces. A sustain that cannot leave this gap and stay 1/8 or longer becomes a 1/32
    -- note, so it clearly reads as a plain note.
    release      = { H = 0.5, M = 0.75, E = 1.0 },
    release_fast = { M = 1.0, E = 2.0 },
    fast_bpm     = 160,
    -- A rest longer than this (quarter notes) ends a color-shift segment, and a segment
    -- is never longer than segment_max: Guitar/Bass Medium/Easy shift a passage down as a
    -- whole, the way official charts move lines down a lane. Longer, not "at least": a
    -- Medium line is mostly quarter notes, and splitting at every quarter moved only the
    -- top note of a line (chronosp bar 10: G Y B O became G Y B B, a repeat Hard never had).
    segment_gap = 1.0,
    segment_max = 8.0,
    -- How Guitar/Bass Medium/Easy bring notes under their top lane:
    --   'clamp'    - only the notes above it move down, unless that makes a color repeat
    --                the tier above does not have; then the whole bar moves down
    --                (Gen5ClampOrShiftBars - pojat bar 3 G O Y B -> G B Y B, chronosp
    --                bar 10 G Y B O -> G R Y B rather than G Y B B);
    --   'bars'     - every such bar moves down whole (Gen5ShiftBars);
    --   'segments' - each passage moves down whole (Gen5ShiftSegments, segment_gap).
    -- Color agreement with official charts (run_generate_eval_offline.lua), Guitar/Bass:
    -- Medium 60.8/69.8% clamp, 58.1/68.6% bars, 56.9/67.7% segments (58.8/67.4% with the
    -- old split at every quarter); Easy 67.1/70.2%, 66.5/69.4%, 66.2/69.3% (66.6/69.4%).
    color_shift = 'clamp',
}

local SUSTAIN_QN   = 0.5     -- a note this long or longer counts as sustained (1/8 note)
local SHORT_QN     = 0.125   -- length a sustain becomes when cut back (1/32 note)
-- Shortest note written (1/32 note), and so the closest two kept onsets may be. Validate
-- rejects anything under 1/64; upper tiers sometimes carry near-zero lengths and flams
-- a few milliseconds apart, which would otherwise be copied straight through.
local MIN_LEN_QN   = 0.125
local KEYS_GRAY_LO = 0.5     -- Keys X/H gray zone [1/8, 3/16) at >= 100 BPM, see
local KEYS_GRAY_HI = 0.75    --   CheckK5SustainLength
local EPS          = 0.02    -- quarter-note tolerance for "on the grid" and gap tests
local GUIDE_TOL    = 0.125   -- Keys-follows-Pro-Keys onset match (1/32 note)

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

-- Beat position of an onset: down (bar line), beat, 8th, 16th, trip, other.
function Gen5BeatClass(ev)
    if ev.down then return 'down' end
    local qn = ev.qn
    if NearInt(qn, EPS)         then return 'beat' end
    if NearInt(qn * 2, EPS * 2) then return '8th'  end
    if NearInt(qn * 4, EPS * 4) then return '16th' end
    if NearInt(qn * 3, EPS * 3) or NearInt(qn * 6, EPS * 6) then return 'trip' end
    return 'other'
end

local function Copy(offs)
    local out = {}
    for i, o in ipairs(offs) do out[i] = o end
    return out
end


----------------------------------------------------------------------
-- Thinning
----------------------------------------------------------------------

local function MinGapQN(dl, bpm)
    local g = GEN5_PARAMS.gap[dl]
    return math.min(math.max(g.grid, g.sec * (bpm or 120) / 60), g.cap or math.huge)
end

-- Shortest sustain tier dl keeps at this tempo (GEN5_PARAMS.min_sustain).
local function MinSustainQN(dl, bpm)
    local p = GEN5_PARAMS
    if (bpm or 120) > p.fast_bpm and p.min_sustain_fast[dl] then return p.min_sustain_fast[dl] end
    return p.min_sustain[dl] or SUSTAIN_QN
end

-- Beat position and note length (see the one-rhythm note above GEN5_PARAMS). The
-- planner's Weights adds Medium's chord bonus and Medium/Easy's "can it stay a sustain"
-- test on top.
local function Weight(ev)
    local p = GEN5_PARAMS
    local w = p.weight[Gen5BeatClass(ev)] or 1
    if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then w = w + p.sustain_bonus end
    return w
end

-- Keep the highest-weight subset of events in which every onset is at least
-- gap_fn(event, earlier) after the previous kept one (weighted interval scheduling). For a
-- fixed gap this is exact: no other subset that respects the gap keeps more weight,
-- so nothing is removed that the gap did not force out.
-- w: optional per-event weights (default Weight).
-- Returns an array of booleans, keep[i].
local function SelectByGap(events, gap_fn, w)
    local n = #events
    local best, take, prev = { [0] = 0 }, {}, {}
    for i = 1, n do
        local j = i - 1
        while j >= 1 and events[i].qn - events[j].qn < gap_fn(events[i], events[j]) - EPS do j = j - 1 end
        prev[i] = j
        local with = (w and w[i] or Weight(events[i])) + best[j]
        if with > best[i - 1] then
            best[i], take[i] = with, true
        else
            best[i], take[i] = best[i - 1], false
        end
    end
    local keep, i = {}, n
    while i >= 1 do
        if take[i] then keep[i] = true; i = prev[i] else i = i - 1 end
    end
    return keep
end

-- How often official Hard keeps an off-beat onset of Expert, by bar position (quarter
-- notes from the bar line, on a 1/12 grid). Pooled over Guitar, Bass and Keys - one
-- rhythm model - over the development songs (official X>H, positions with 800+ onsets;
-- run_generate_eval_offline.lua's reader, hold-out excluded). The least-kept position
-- goes first. The 8th off-beats are the telling rows: official Hard drops "the and of 4"
-- (3.5, kept 49%) far more readily than the and of 2 (73%), of 1 (84%) or of 3 (85%).
local CAP_KEEP_RATE = {
    ['0.167'] = 0.03, ['1.167'] = 0.04, ['3.167'] = 0.06, ['3.917'] = 0.06, ['2.167'] = 0.06,
    ['3.750'] = 0.11, ['3.833'] = 0.19, ['0.250'] = 0.20, ['2.750'] = 0.25, ['2.833'] = 0.26,
    ['0.333'] = 0.26, ['1.833'] = 0.26, ['3.250'] = 0.27, ['1.750'] = 0.30, ['1.250'] = 0.30,
    ['3.667'] = 0.33, ['2.250'] = 0.35, ['3.333'] = 0.37, ['2.333'] = 0.38, ['0.750'] = 0.39,
    ['1.667'] = 0.42, ['1.333'] = 0.42, ['0.667'] = 0.43, ['2.667'] = 0.45, ['0.833'] = 0.46,
    ['3.500'] = 0.49, ['1.500'] = 0.73, ['0.500'] = 0.84, ['2.500'] = 0.85,
}
-- For a position the table does not list (an odd meter, a rare position): the beat
-- class's typical official keep rate, so it still sorts sensibly.
local CAP_CLASS_RATE = { ['8th'] = 0.6, ['16th'] = 0.25, trip = 0.4, other = 0.15 }

-- An onset's bar position, as CAP_KEEP_RATE keys it. bar_qn is optional (4/4 assumed).
local function BarPosKey(ev)
    return ('%.3f'):format(math.floor((ev.bar_qn or ev.qn % 4) * 12 + 0.5) / 12)
end

local function PosRate(ev)
    return CAP_KEEP_RATE[BarPosKey(ev)] or CAP_CLASS_RATE[Gen5BeatClass(ev)] or 0.5
end

-- Retimed notes (Gen5RetimeDenseRuns) are already the reduction: never removed again.
local function IsCandidate(ev)
    if ev.retimed then return false end
    local c = Gen5BeatClass(ev)
    return c ~= 'down' and c ~= 'beat'
end

-- Both gaps to the neighbouring onsets (in events) more than GEN5_PARAMS.isolated_qn.
-- The first and last onsets count their missing side as infinitely far.
local function IsIsolated(events, i)
    local lim = GEN5_PARAMS.isolated_qn + EPS
    local ev, pv, nx = events[i], events[i - 1], events[i + 1]
    return (not pv or ev.qn - pv.qn > lim) and (not nx or nx.qn - ev.qn > lim)
end

-- Medium's fallback: drop every kept off-beat onset that is isolated in the upper tier.
-- Returns how many were dropped.
local function DropIsolatedOffbeats(events, keep)
    local n = 0
    for i, ev in ipairs(events) do
        if keep[i] and IsCandidate(ev) and IsIsolated(events, i) then keep[i] = nil; n = n + 1 end
    end
    return n
end

-- Drop kept onsets until at most cap * #events remain. Removes WHOLE bar positions
-- across the whole song at once, least-kept first (CAP_KEEP_RATE), never a downbeat or
-- beat. So the same riff reduces the same way every time it comes round, rather than
-- the start of the song absorbing the whole cut. It can overshoot the cap by up to one
-- position. Removing an onset only widens gaps, so SelectByGap's gap still holds.
-- n_upper: the upper tier's onset count the cap is a share of - more than #events when
-- the Hard fast-run rewrite already took notes out.
local function CapKeep(events, keep, cap, protect_isolated, n_upper)
    if not cap then return end
    local kept, groups = 0, {}
    for i, ev in ipairs(events) do
        if keep[i] then
            kept = kept + 1
            if IsCandidate(ev) and not (protect_isolated and IsIsolated(events, i)) then
                local key = BarPosKey(ev)
                local g = groups[key]
                if not g then
                    g = { key = key, members = {}, rate = PosRate(ev) }
                    groups[key] = g
                end
                g.members[#g.members + 1] = i
            end
        end
    end
    local limit = math.floor(cap * (n_upper or #events))
    if kept <= limit then return end
    local order = {}
    for _, g in pairs(groups) do order[#order + 1] = g end
    table.sort(order, function(a, b)
        if a.rate ~= b.rate then return a.rate < b.rate end
        return a.key < b.key
    end)
    for _, g in ipairs(order) do
        if kept <= limit then break end
        for _, i in ipairs(g.members) do keep[i] = nil end
        kept = kept - #g.members
    end
end

-- An onset's position in its bar, as the busy-bar reference (busy_ref) records it.
local function PosStr(ev)
    return ('%.3f'):format(ev.bar_qn or ev.qn % 4)
end

-- Empty 8th-note slots in a bar: its length in 8ths minus the 8th-grid slots holding an
-- onset. A bar that already rests somewhere is easier than a full one, so it loses less.
local function EmptyEighths(events, idx)
    local slots, n = {}, 0
    local bar_len = events[idx[1]].bar_len or 4
    for _, i in ipairs(idx) do
        local x = (events[i].bar_qn or events[i].qn % 4) * 2
        if NearInt(x, EPS * 2) then
            local s = math.floor(x + 0.5)
            if not slots[s] then slots[s] = true; n = n + 1 end
        end
    end
    return math.max(0, math.floor(bar_len * 2 + 0.5) - n)
end

-- The notes in a bar that go last. A sustain always (it holds the line); a chord only in
-- a bar that mixes chords and single notes, where it is the accent. In a bar of all
-- chords or all single notes they are all alike and the usual "and" notes go.
local function ProtectedSet(events, idx)
    local chords, singles = 0, 0
    for _, i in ipairs(idx) do
        if #events[i].offs >= 2 then chords = chords + 1 else singles = singles + 1 end
    end
    local mixed, prot = chords > 0 and singles > 0, {}
    for _, i in ipairs(idx) do
        local ev = events[i]
        if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS or (mixed and #ev.offs >= 2) then prot[i] = true end
    end
    return prot
end

-- Every bar the selection left complete - all of its upper onsets kept, none retimed -
-- with at least min_onsets onsets is thinned. It loses n_drop notes less the 8th slots it
-- already leaves empty, at least one - unless two or more slots are empty already, then
-- none: Drop 2 on a bar of straight 8ths takes two, on a bar with one rest one, on a bar
-- with two rests nothing. Which notes go:
--   1. the RBN doc positions first - "remove every fourth note per half measure", the and
--      of 2 and the and of 4 (with Drop 1 the and of 4 wins: official Hard drops it most);
--   2. then the other off-beats, least-kept bar position first (CAP_KEEP_RATE), the later
--      one on a tie;
--   3. protected notes (ProtectedSet) last, whatever their position.
-- Rhythm, length and chord size only - never colors.
--
-- ref (optional): the leading instrument's busy bars, { [bar start] = { sig, removed } }.
-- A bar whose onset positions equal the leader's (sig) loses the leader's notes, so the
-- band drops the same notes - unless one of them is protected HERE (this instrument's own
-- sustain or accent wins); then the bar uses its own order above.
-- Returns { [bar start] = { sig, removed } } for the bars it thinned, and how many of
-- them followed ref.
local function ThinBusyBars(events, keep, min_onsets, protect_isolated, n_drop, ref)
    local record, followed = {}, 0
    if not min_onsets then return record, followed end
    local bars, order = {}, {}
    for i, ev in ipairs(events) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        local b = bars[key]
        if not b then
            b = { key = key, idx = {} }
            bars[key] = b
            order[#order + 1] = b
        end
        b.idx[#b.idx + 1] = i
    end
    for _, b in ipairs(order) do
        if #b.idx >= min_onsets then
            local complete = true
            for _, i in ipairs(b.idx) do
                -- A flourish note the gap dropped (Gen5RetimeDenseRuns) does not count: the
                -- bar left is still a full bar of 8ths.
                if (not keep[i] and not events[i].flourish) or events[i].retimed then complete = false; break end
            end
            -- Two or more 8th rests already: the bar is thin enough as it is.
            local empty = complete and EmptyEighths(events, b.idx) or 0
            if complete and empty < 2 then
                local pos, at = {}, {}
                for k, i in ipairs(b.idx) do
                    pos[k] = PosStr(events[i])
                    at[pos[k]] = i
                end
                local sig  = table.concat(pos, ' ')
                local prot = ProtectedSet(events, b.idx)
                local drop
                local lead = ref and ref[b.key]
                if lead and lead.sig == sig then
                    drop = {}
                    for _, p in ipairs(lead.removed) do
                        local i = at[p]
                        if not i or prot[i] or (protect_isolated and IsIsolated(events, i)) then
                            drop = nil
                            break
                        end
                        drop[#drop + 1] = i
                    end
                    if drop then followed = followed + 1 end
                end
                if not drop then
                    local cands = {}
                    for _, i in ipairs(b.idx) do
                        if keep[i] and IsCandidate(events[i]) and not (protect_isolated and IsIsolated(events, i)) then
                            local key = BarPosKey(events[i])
                            cands[#cands + 1] = { i = i, r = PosRate(events[i]), p = prot[i] and 1 or 0,
                                                  doc = (key == '1.500' or key == '3.500') and 0 or 1 }
                        end
                    end
                    table.sort(cands, function(a, c)
                        if a.p ~= c.p then return a.p < c.p end
                        if a.doc ~= c.doc then return a.doc < c.doc end
                        if a.r ~= c.r then return a.r < c.r end
                        return a.i > c.i
                    end)
                    local n = math.max(1, (n_drop or 1) - empty)
                    drop = {}
                    for k = 1, math.min(n, #cands) do drop[k] = cands[k].i end
                end
                local removed = {}
                for _, i in ipairs(drop) do
                    keep[i] = nil
                    removed[#removed + 1] = PosStr(events[i])
                end
                table.sort(removed)
                record[b.key] = { sig = sig, removed = removed }
            end
        end
    end
    return record, followed
end

-- Keys following the same-tier Pro Keys chart: keep the events that land on a Pro
-- Keys onset, with that note's length. guide = sorted { { qn, qn_e }... }.
local function SelectByGuide(events, guide)
    local keep, lens, j = {}, {}, 1
    for i, ev in ipairs(events) do
        while j <= #guide and guide[j].qn < ev.qn - GUIDE_TOL do j = j + 1 end
        local best
        for k = j, math.min(#guide, j + 1) do
            if math.abs(guide[k].qn - ev.qn) <= GUIDE_TOL
               and (not best or math.abs(guide[k].qn - ev.qn) < math.abs(guide[best].qn - ev.qn)) then
                best = k
            end
        end
        if best then
            keep[i] = true
            lens[i] = guide[best].qn_e - guide[best].qn
        end
    end
    return keep, lens
end

----------------------------------------------------------------------
-- Sustains
----------------------------------------------------------------------

-- Gap a sustain must leave before the next note on this tier.
local function ReleaseGapQN(kind, dl, ev)
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

-- Shorten sustains to leave the tier's release gap, cut a sustain that would end up
-- shorter than the tier keeps (MinSustainQN) back to a plain note, and keep every note
-- clear of the next onset. Returns (shortened, cut).
local function FixLengths(kind, dl, out)
    local shortened, cut = 0, 0
    for i, ev in ipairs(out) do
        local nx = out[i + 1]
        local len = ev.qn_e - ev.qn
        if len >= SUSTAIN_QN - EPS then
            if nx then
                local limit = nx.qn - ReleaseGapQN(kind, dl, ev)
                if ev.qn_e > limit + EPS then
                    ev.qn_e = limit
                    shortened = shortened + 1
                end
            end
            -- A tail the tier above shortened for a note this tier drops comes back up to
            -- this tier's minimum when the original note was that long and there is room:
            -- Easy inherited a 3/4 tail from Medium and lost the sustain (pojat bars 70/74).
            local min_len = MinSustainQN(dl, ev.bpm)
            if ev.qn_e - ev.qn < min_len - EPS and (ev.qn_e_full or ev.qn_e) - ev.qn >= min_len - EPS
               and (not nx or nx.qn - ReleaseGapQN(kind, dl, ev) >= ev.qn + min_len - EPS) then
                ev.qn_e = ev.qn + min_len
            end
            -- With EPS: a sustain left exactly at the minimum stays a sustain. Without it,
            -- tempo-map rounding made identical repeats land either side of 1/8.
            if ev.qn_e - ev.qn < min_len - EPS then
                ev.qn_e = ev.qn + math.min(SHORT_QN, nx and (nx.qn - ev.qn - EPS) or SHORT_QN)
                cut = cut + 1
            end
        end
        len = ev.qn_e - ev.qn
        -- Keys Expert/Hard gray zone: too long for a hit, too short for a tail.
        -- Same bounds as CheckK5SustainLength, so a length on either edge is judged alike.
        if kind == 'k5' and (dl == 'H' or dl == 'X') and (ev.bpm or 120) >= 100
           and len >= KEYS_GRAY_LO - EPS and len < KEYS_GRAY_HI * 0.95 then
            ev.qn_e = ev.qn + SHORT_QN
            cut = cut + 1
        end
        -- At least MIN_LEN_QN long, but never into the next onset (an overlap hides the
        -- next note in game). Kept onsets are at least MIN_LEN_QN apart, so both hold.
        if ev.qn_e - ev.qn < MIN_LEN_QN then ev.qn_e = ev.qn + MIN_LEN_QN end
        if nx and ev.qn_e > nx.qn - EPS / 2 then
            ev.qn_e = math.max(ev.qn + MIN_LEN_QN * 0.6, nx.qn - EPS / 2)
        end
    end
    return shortened, cut
end

----------------------------------------------------------------------
-- Medium: weights, a note per beat, and following Guitar
----------------------------------------------------------------------

-- Per-event weights for tier dl. Hard: Weight as it always was. Medium/Easy: the sustain
-- bonus only for a note that can stay a sustain on this tier (held at most to the next
-- upper onset less the release gap, at least MinSustainQN); Medium adds chord_bonus.
local function Weights(kind, dl, events)
    local p, w = GEN5_PARAMS, {}
    for i, ev in ipairs(events) do
        if dl == 'H' then
            w[i] = Weight(ev)
        else
            w[i] = p.weight[Gen5BeatClass(ev)] or 1
            local len, nx = ev.qn_e - ev.qn, events[i + 1]
            if nx then len = math.min(len, nx.qn - ev.qn - ReleaseGapQN(kind, dl, ev)) end
            if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS and len >= MinSustainQN(dl, ev.bpm) - EPS then
                w[i] = w[i] + p.sustain_bonus
            end
            if #ev.offs >= 2 and p.chord_bonus[dl] then
                -- Only against a single note it competes with (within the tier's gap): a
                -- bonus on every chord of an all-chord passage only rewarded keeping more
                -- of them, off-beats over the downbeat (chronosp bars 18-19).
                local gap = MinGapQN(dl, ev.bpm)
                for j = i - 1, i + 1, 2 do
                    local o = events[j]
                    if o and #o.offs == 1 and math.abs(o.qn - ev.qn) < gap - EPS then
                        w[i] = w[i] + p.chord_bonus[dl]
                        break
                    end
                end
            end
        end
    end
    return w
end

-- The bar each event is in: list of { key, start, len, idx = { event indices } }.
local function Bars(events)
    local bars, order = {}, {}
    for i, ev in ipairs(events) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        local b = bars[key]
        if not b then
            b = { key = key, start = start, len = ev.bar_len or 4, idx = {} }
            bars[key] = b
            order[#order + 1] = b
        end
        b.idx[#b.idx + 1] = i
    end
    return order
end

-- Medium keeps a note per beat in a busy bar. In a bar where the upper tier has more
-- onsets than the bar has beats and Medium kept fewer than its beats, removed upper
-- onsets come back until it has as many as beats: at least an 8th from every kept
-- onset, beats and downbeats first, then by weight, then a held note, then the earlier.
-- From the user's review of chronosp_brutal_decay: bar 7 keeps beat 3 AND the held note on
-- 3& (B . B . G B), bar 11 beat 3 AND the 3& chord (B . B . G GY). Official fast Medium
-- keeps both of such a pair only 5% of the time; the user preferred the bar's pulse.
-- Returns the number of onsets added.
local function FillBeats(events, keep, w)
    local added, kept_qn = 0, {}
    for i, ev in ipairs(events) do if keep[i] then kept_qn[#kept_qn + 1] = ev.qn end end
    -- At least an 8th from every kept onset, and not closer than a quarter on BOTH sides:
    -- filling the middle of 36 . 60 (chronosp bar 18) made three 8th chords in a row.
    local function Clear(qn)
        local near_l, near_r = false, false
        for _, k in ipairs(kept_qn) do
            local d = k - qn
            if math.abs(d) < 0.5 - EPS then return false end
            if d < 0 and -d < 1 - EPS then near_l = true end
            if d > 0 and d < 1 - EPS then near_r = true end
        end
        return not (near_l and near_r)
    end
    for _, b in ipairs(Bars(events)) do
        local beats = math.floor(b.len + EPS)
        local n = 0
        for _, i in ipairs(b.idx) do if keep[i] then n = n + 1 end end
        if #b.idx > beats and n < beats then
            local cands = {}
            for _, i in ipairs(b.idx) do
                if not keep[i] then
                    local c = Gen5BeatClass(events[i])
                    local ev = events[i]
                    cands[#cands + 1] = { i = i, beat = (c == 'down' or c == 'beat') and 1 or 0, w = w[i],
                                          held = ev.qn_e - ev.qn >= SUSTAIN_QN - EPS and 1 or 0,
                                          rate = PosRate(ev) }
                end
            end
            -- Last tie-break: the bar position official charts keep most (CAP_KEEP_RATE), so
            -- an all-chord syncopated bar (chronosp bar 18) gets 0 12 | 48 60, Hard's own
            -- pairs, rather than three 8ths in a row.
            table.sort(cands, function(a, c)
                if a.beat ~= c.beat then return a.beat > c.beat end
                if a.w ~= c.w then return a.w > c.w end
                if a.held ~= c.held then return a.held > c.held end
                if a.rate ~= c.rate then return a.rate > c.rate end
                return a.i < c.i
            end)
            for _, c in ipairs(cands) do
                if n >= beats then break end
                if Clear(events[c.i].qn) then
                    keep[c.i] = true
                    kept_qn[#kept_qn + 1] = events[c.i].qn
                    n, added = n + 1, added + 1
                end
            end
        end
    end
    return added
end

-- A rewritten Hard note that stands for a beat Expert plays (beat_qn, set by
-- Gen5RetimeDenseRuns) goes back to that beat for Medium and Easy, so the beat is not left
-- empty below Hard: chronosp bar 20's beat 4 sat at 76/24 on Hard. Returns a new list.
local function SnapRewrittenToBeats(events)
    local out, moved = {}, false
    for i, ev in ipairs(events) do
        local src = ev.beat_qn
        if src and math.abs(src - ev.qn) > EPS and ev.bar_qn then
            local pv, nx = events[i - 1], events[i + 1]
            if (not pv or src - pv.qn > MIN_LEN_QN) and (not nx or nx.qn - src > MIN_LEN_QN) then
                local d = src - ev.qn
                local bar_qn = ev.bar_qn + d
                ev = { qn = src, qn_e = ev.qn_e + d, qn_e_full = (ev.qn_e_full or ev.qn_e) + d,
                       offs = ev.offs, bpm = ev.bpm, bar_qn = bar_qn,
                       bar_len = ev.bar_len, down = math.abs(bar_qn) <= EPS, hopo = ev.hopo, src_qn = src }
                moved = true
            end
        end
        out[#out + 1] = ev
    end
    if moved then table.sort(out, function(a, c) return a.qn < c.qn end) end
    return out
end

-- Bars of the same rhythm keep the same Medium onsets on every instrument: the leader's
-- record { [bar start] = { sig = upper onset positions, kept = kept positions } }.
local function RhythmRecord(events, keep)
    local rec = {}
    for _, b in ipairs(Bars(events)) do
        local sig, kept = {}, {}
        for _, i in ipairs(b.idx) do
            local pos = ('%.3f'):format(events[i].bar_qn or events[i].qn % 4)
            sig[#sig + 1] = pos
            if keep[i] then kept[pos] = true end
        end
        rec[b.key] = { sig = table.concat(sig, ' '), kept = kept }
    end
    return rec
end

-- Follow the leader's Medium in bars whose upper rhythm matches. Returns bars followed.
local function FollowRhythm(events, keep, ref)
    if not ref then return 0 end
    local followed = 0
    local mine = RhythmRecord(events, keep)
    for _, b in ipairs(Bars(events)) do
        local lead = ref[b.key]
        if lead and mine[b.key] and lead.sig == mine[b.key].sig then
            for _, i in ipairs(b.idx) do
                keep[i] = lead.kept[('%.3f'):format(events[i].bar_qn or events[i].qn % 4)] or nil
            end
            followed = followed + 1
        end
    end
    return followed
end

----------------------------------------------------------------------
-- Planner
----------------------------------------------------------------------

-- Build tier dl ('H', 'M' or 'E') from the events of the tier above it.
--   kind   - 'gb' (Guitar/Bass) or 'k5' (Keys)
--   events - the upper tier, as described at the top of this file, sorted by qn
--   opts   - optional { guide = { { qn, qn_e }... }, busy_drop = 1 | 2, busy_ref = {...} }
--            guide: Keys only, the same-tier Pro Keys chart to follow instead of
--            thinning by beat position. busy_drop: notes a complete busy bar loses on
--            Hard; nil = Auto (2 when the first note is over fast_8ths_bpm).
--            busy_ref: the leading instrument's log.busy_bars from its own Hard (Guitar
--            leads Bass and Keys), so a bar with the same rhythm loses the same notes.
--            rhythm_ref: the leader's log.rhythm_bars from its own Medium, so a bar with
--            the same Hard rhythm keeps the same Medium onsets.
-- kind affects chords, colors and sustain rules only - which onsets are kept depends on it
-- only through Medium's chord bonus, where Bass and Keys follow Guitar (rhythm_ref).
-- Returns (out_events, log) where log counts what was done:
--   { upper, kept, removed, chords_reduced, recolored, shortened, cut, guided,
--     color_fallback (true when Hard was eased by color because it barely thinned),
--     busy_drop, busy_auto, first_bpm (what the busy-bar rule used, and why),
--     busy_bars ({ [bar start] = { sig, removed } }, the reference for followers),
--     busy_followed (bars that took busy_ref's notes),
--     retimed_bars (Hard: { { start = bar start QN, grid }... }, bars whose fast runs were
--     rewritten one grid slower - see difficulty_generate_retime.lua),
--     filled (Medium: onsets FillBeats added), rhythm_bars (Medium: the reference for
--     followers), rhythm_followed (Medium: bars that took rhythm_ref's onsets) }
function Gen5PlanTier(kind, dl, events, opts)
    opts = opts or {}
    local log = { upper = #events, kept = 0, removed = 0, chords_reduced = 0,
                  recolored = 0, shortened = 0, cut = 0, guided = false, color_fallback = false }

    local keep, guide_len, weights
    if kind == 'k5' and opts.guide and #opts.guide > 0 then
        keep, guide_len = SelectByGuide(events, opts.guide)
        log.guided = true
        -- The guide is a chart someone reduced by hand; still hold Validate's floor, and
        -- never keep two onsets closer than the shortest note that can be written.
        local floor = math.max(K5_MIN_SP[dl] or 0, MIN_LEN_QN)
        do
            local sub = {}
            for i, ev in ipairs(events) do if keep[i] then sub[#sub + 1] = ev end end
            local sub_keep = SelectByGap(sub, function() return floor end)
            local k = 0
            for i in ipairs(events) do
                if keep[i] then
                    k = k + 1
                    if not sub_keep[k] then keep[i] = nil end
                end
            end
        end
    else
        -- Hard on a fast song: dense runs are rewritten one grid slower first. Those notes
        -- are already the reduction, so the gap does not apply between them and their
        -- neighbours (the rewrite keeps them a grid step apart).
        if dl == 'H' then
            events, log.retimed_bars = Gen5RetimeDenseRuns(events, {
                gap = function(ev) return MinGapQN('H', ev.bpm) end, eps = EPS })
            -- A note of a run in a bar the rewrite did not change (it neither moved nor
            -- dropped anything there) is an ordinary note again: chronosp bass bar 85's
            -- downbeat ends bar 84's 16ths, and as `retimed` it kept the busy-bar rule off
            -- a bar of straight 8ths.
            local changed = {}
            for _, rb in ipairs(log.retimed_bars) do changed[('%.3f'):format(rb.start)] = true end
            for _, ev in ipairs(events) do
                if ev.retimed then
                    local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
                    -- Still part of the rewritten passage for the force-HOPO markers
                    -- (`rewritten` below): a run's landing note keeps Expert's hammer-on.
                    if not changed[('%.3f'):format(start)] then ev.retimed, ev.joined = nil, true end
                end
            end
        else
            events = SnapRewrittenToBeats(events)
        end
        weights = Weights(kind, dl, events)
        keep = SelectByGap(events, function(ev, earlier)
            if ev.retimed or earlier.retimed then return MIN_LEN_QN end
            return MinGapQN(dl, ev.bpm)
        end, weights)
    end

    -- Busy bars: how many notes each loses (busy_drop). Unset = once per song, from the
    -- tempo at the first note (fast_8ths_bpm).
    local n_drop = opts.busy_drop
    log.first_bpm = events[1] and events[1].bpm or nil
    if not n_drop then
        n_drop = (log.first_bpm or 0) > GEN5_PARAMS.fast_8ths_bpm and 2 or 1
        log.busy_auto = true
    end
    log.busy_drop = n_drop

    -- Busy bars first, in both paths (so Keys following Pro Keys keeps the rule): a bar
    -- gets the per-bar treatment before the song-wide cap could take a whole position
    -- from every bar and leave nothing for it. Hard never takes an isolated onset (see
    -- isolated_qn).
    log.busy_bars, log.busy_followed = ThinBusyBars(events, keep, GEN5_PARAMS.busy_bar_onsets[dl],
        dl == 'H', n_drop, opts.busy_ref)
    if not log.guided then
        CapKeep(events, keep, GEN5_PARAMS.max_keep[dl], dl == 'H', log.upper)
        -- Not when following Pro Keys: Keys and Pro Keys keep the same density.
        if dl == 'M' then
            log.filled = GEN5_PARAMS.fill_beats[dl] and FillBeats(events, keep, weights) or 0
            -- Barely thinner than Hard: drop the isolated off-beats (offbeat_fallback_keep).
            local fb = GEN5_PARAMS.offbeat_fallback_keep[dl]
            if fb and log.upper > 0 then
                local n = 0
                for i in ipairs(events) do if keep[i] then n = n + 1 end end
                if n / log.upper > fb then log.offbeats_dropped = DropIsolatedOffbeats(events, keep) end
            end
            log.rhythm_followed = FollowRhythm(events, keep, opts.rhythm_ref)
            log.rhythm_bars = RhythmRecord(events, keep)
        end
    end

    local max_n   = kind == 'gb' and GB_MAX_CHORD[dl] or K5_MAX_CHORD[dl]
    local out = {}
    for i, ev in ipairs(events) do
        if keep[i] then
            local offs = Gen5ReduceChordSize(Copy(ev.offs), max_n)
            if #offs ~= #ev.offs then log.chords_reduced = log.chords_reduced + 1 end
            -- qn_e_full: the note's length before any tier shortened it (FixLengths).
            local full = ev.qn_e_full or ev.qn_e
            local qn_e = ev.qn_e
            if guide_len and guide_len[i] then qn_e, full = ev.qn + guide_len[i], ev.qn + guide_len[i] end
            -- bar_qn carried through: the next tier in a chain is built from this one.
            out[#out + 1] = { qn = ev.qn, qn_e = qn_e, qn_e_full = full, offs = offs, bpm = ev.bpm, down = ev.down,
                              bar_qn = ev.bar_qn, bar_len = ev.bar_len,
                              -- Expert's hammer-on, and whether the fast-run rewrite
                              -- moved the note, for the force-HOPO markers on Hard
                              -- (difficulty_generate_hopo.lua). Not `retimed` itself:
                              -- that would lift the gap for the next tier down.
                              hopo = ev.hopo, rewritten = ev.retimed or ev.joined,
                              -- the Expert beat a rewritten note stands for
                              -- (SnapRewrittenToBeats)
                              beat_qn = ev.beat_qn }
        end
    end
    log.kept    = #out
    log.removed = log.upper - #out

    -- Hard that barely thinned is made easier by color instead (color_fallback_keep).
    local fb = GEN5_PARAMS.color_fallback_keep[dl]
    if fb and log.upper > 0 and #out / log.upper > fb then
        local n = Gen5ShiftBars(out, GEN5_PARAMS.color_fallback_top[dl])
        log.recolored = log.recolored + n
        log.color_fallback = n > 0
    end

    if kind == 'gb' then
        local rng = GB_RANGE[dl]
        local ceiling = rng.hi - rng.lo
        if ceiling < 4 then
            local mode = GEN5_PARAMS.color_shift
            log.recolored = mode == 'clamp' and Gen5ClampOrShiftBars(out, ceiling)
                            or mode == 'bars' and Gen5ShiftBars(out, ceiling)
                            or Gen5ShiftSegments(out, ceiling)
        end
        for _, ev in ipairs(out) do
            local before = #ev.offs
            ev.offs = Gen5NarrowSpan(ev.offs, GB_MAX_SPAN[dl])
            if #ev.offs ~= before then log.chords_reduced = log.chords_reduced + 1 end
        end
    end

    log.shortened, log.cut = FixLengths(kind, dl, out)
    return out, log
end
