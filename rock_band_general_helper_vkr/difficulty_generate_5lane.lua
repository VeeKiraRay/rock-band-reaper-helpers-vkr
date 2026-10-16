-- Difficulty > Generate: the reduction planner for the 5-lane instruments (Guitar,
-- Bass, Keys). Builds one tier from the tier above it.
--
-- PURE: no r, no S. Takes plain event tables and returns plain event tables, so the
-- offline evaluation (dev/calibration/run_generate_eval_offline.lua) runs exactly the
-- code the helper ships. The REAPER side - reading tracks, writing notes, undo - lives
-- in actions_difficulty_generate.lua.
--
-- Input event:  { qn, qn_e, offs = { gem offsets 0-4, ascending }, bpm, down, bar_qn, bar_len, pulse }
--   qn / qn_e - onset and end in quarter notes; bpm - tempo at the onset, in quarter
--               notes per minute whatever the time signature;
--   down      - true when the onset is on a bar line;
--   bar_qn    - quarter notes from the bar line (optional; 4/4 is assumed without it);
--   bar_len   - length of the onset's bar in quarter notes (optional; 4 without it);
--   pulse     - the bar's beat in quarter notes, Gen5PulseQN (optional; 1 without it,
--               1.5 in 6/8, 9/8 and 12/8).
-- Output event: { qn, qn_e, offs } with offs relative to the TARGET tier's lowest pitch.
--
-- What it aims for is what official charts do, not merely what Validate requires
-- (Validate's Guitar/Bass Medium/Easy spacing rules are advisories); the numbers are tuned
-- with run_generate_eval_offline.lua. Each rule's source: docs/difficulty_reduction.md.
--
-- Which onsets survive is decided by Gen5SelectOnsets (difficulty_generate_rhythm.lua),
-- shared with Pro Keys; the parameters live in difficulty_generate_params.lua. This
-- file reduces chords and colors and fixes sustain lengths. Load after both.
--
-- Requires (globals, read at call time): GB_MAX_CHORD, GB_MAX_SPAN, GB_RANGE,
--   K5_MAX_CHORD (actions_difficulty_gtrbass.lua / _5k.lua), Gen5ReduceChordSize(Keys) / Gen5KeysEasyMotion /
--   Gen5NarrowSpan / Gen5ShiftSegments / Gen5ShiftBars (difficulty_generate_colors.lua),
--   GenPlanOverlaps / GenNextAfterHold (difficulty_generate_overlaps.lua).

local SUSTAIN_QN   = GEN5_SUSTAIN_QN
local SHORT_QN     = 0.125   -- length a sustain becomes when cut back (1/32 note)
local MIN_LEN_QN   = GEN5_MIN_LEN_QN
local KEYS_GRAY_LO = 0.5     -- Keys X/H gray zone [1/8, 3/16) at >= 100 BPM, see
local KEYS_GRAY_HI = 0.75    --   CheckK5SustainLength
local EPS          = GEN5_EPS
local MinSustainQN, ReleaseGapQN = Gen5MinSustainQN, Gen5ReleaseGapQN

local function Copy(offs)
    local out = {}
    for i, o in ipairs(offs) do out[i] = o end
    return out
end

----------------------------------------------------------------------
-- Sustains
----------------------------------------------------------------------

-- Shorten sustains to leave the tier's release gap, cut a sustain that would end up
-- shorter than the tier keeps (MinSustainQN) back to a plain note, and keep every note
-- clear of the next onset. A note GenPlanOverlaps holds over later onsets (hold) is
-- measured against the first onset after it ends instead; if it ends up too short to
-- sustain, it is a plain note clear of the very next onset like any other.
-- Returns (shortened, cut).
local function FixLengths(kind, dl, out)
    local shortened, cut = 0, 0
    for i, ev in ipairs(out) do
        local first = out[i + 1]
        local nx = GenNextAfterHold(out, i)
        local len = ev.qn_e - ev.qn
        if len >= SUSTAIN_QN - EPS then
            -- A held note pulled back can end at or just after a note it was held over:
            -- then that note is the one after its end, and the gap is measured again.
            while nx do
                local limit = nx.qn - ReleaseGapQN(kind, dl, ev)
                if ev.qn_e <= limit + EPS then break end
                ev.qn_e = limit
                shortened = shortened + 1
                local again = GenNextAfterHold(out, i)
                if again == nx then break end
                nx = again
            end
            -- A tail the tier above shortened for a note this tier drops comes back up to
            -- this tier's minimum when the original note was that long and there is room:
            -- Easy inherited a 3/4 tail from Medium and lost the sustain.
            local min_len = MinSustainQN(dl, ev.bpm)
            if ev.qn_e - ev.qn < min_len - EPS and (ev.qn_e_full or ev.qn_e) - ev.qn >= min_len - EPS
               and (not nx or nx.qn - ReleaseGapQN(kind, dl, ev) >= ev.qn + min_len - EPS) then
                ev.qn_e = ev.qn + min_len
            end
            -- With EPS: a sustain left exactly at the minimum stays a sustain. Without it,
            -- tempo-map rounding made identical repeats land either side of 1/8.
            if ev.qn_e - ev.qn < min_len - EPS then
                ev.qn_e = ev.qn + math.min(SHORT_QN, first and (first.qn - ev.qn - EPS) or SHORT_QN)
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
        -- next note in game) - unless it is a sustain GenPlanOverlaps holds over it. Kept
        -- onsets are at least MIN_LEN_QN apart, so both hold.
        if ev.qn_e - ev.qn < MIN_LEN_QN then ev.qn_e = ev.qn + MIN_LEN_QN end
        -- A held sustain stops only for the first onset after its end (nil: none follows).
        local stop = first
        if ev.hold and ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then stop = nx end
        if stop and ev.qn_e > stop.qn - EPS / 2 then
            ev.qn_e = math.max(ev.qn + MIN_LEN_QN * 0.6, stop.qn - EPS / 2)
        end
    end
    return shortened, cut
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


    local keep, guide_len
    events, keep, guide_len = Gen5SelectOnsets(kind, dl, events, opts, log)

    local max_n   = kind == 'gb' and GB_MAX_CHORD[dl] or K5_MAX_CHORD[dl]
    -- Keys keeps a chord's top notes; Guitar/Bass the outer pair and the lowest note
    -- (Gen5ReduceChordSizeKeys says why).
    local reduce  = kind == 'k5' and Gen5ReduceChordSizeKeys or Gen5ReduceChordSize
    local upper_offs = {}   -- Keys Easy: each kept event's Medium offs (Gen5KeysEasyMotion)
    local out = {}
    for i, ev in ipairs(events) do
        if keep[i] then
            local offs = reduce(Copy(ev.offs), max_n)
            upper_offs[#out + 1] = ev.offs
            if #offs ~= #ev.offs then log.chords_reduced = log.chords_reduced + 1 end
            -- qn_e_full: the note's length before any tier shortened it (FixLengths).
            local full = ev.qn_e_full or ev.qn_e
            local qn_e = ev.qn_e
            if guide_len and guide_len[i] then qn_e, full = ev.qn + guide_len[i], ev.qn + guide_len[i] end
            -- bar_qn carried through: the next tier in a chain is built from this one.
            out[#out + 1] = { qn = ev.qn, qn_e = qn_e, qn_e_full = full, offs = offs, bpm = ev.bpm, down = ev.down,
                              bar_qn = ev.bar_qn, bar_len = ev.bar_len, pulse = ev.pulse,
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

    -- Keys Easy: a chord reduced to one note keeps the line moving (no new repeats, a
    -- repeated chord stays one note).
    if kind == 'k5' and dl == 'E' then log.easy_motion = Gen5KeysEasyMotion(out, upper_offs) end

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

    -- Keys: notes Expert holds while later notes start keep sounding within the docs'
    -- limits (GenPlanOverlaps, difficulty_generate_overlaps.lua); after the colors, so a
    -- shifted line is what the lane and count checks see.
    if kind == 'k5' then
        log.overlaps = GenPlanOverlaps(kind, dl, out, reduce,
            function(h) return ReleaseGapQN(kind, dl, h) end)
    end
    log.shortened, log.cut = FixLengths(kind, dl, out)
    return out, log
end
