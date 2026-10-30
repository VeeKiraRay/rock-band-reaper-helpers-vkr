-- Drums difficulty checks: the tier reader, the rule thresholds and every Validate check,
-- as categories of DiffIssue records (like CollectK5Checks / CollectGBChecks), so
-- Validate prints them and Generate counts what is left after it writes a tier.
-- Requires: S, r, GetTempoContextBefore, FormatTime, PitchName, DiffIssue (globals)

-- Per-difficulty pitch ranges on PART DRUMS (single track, like PART KEYS).
DRUMS_RANGE = {
    X = { lo = 96, hi = 100 },
    H = { lo = 84, hi = 88  },
    M = { lo = 72, hi = 76  },
    E = { lo = 60, hi = 64  },
}

-- Tempo/density thresholds from external RBN authoring guidance. Global because the
-- Generate planner (difficulty_generate_drums.lua) builds tiers to these same numbers -
-- one table, so the two cannot drift. Each cascades from a higher difficulty down to an
-- easier one that doesn't define its own stricter version - see the per-check comments
-- below for which direction applies.
DRUMS_RULES = {
    roll_hard_16th_bpm     = 140,  -- H: avoid 16th-rate rolls at/above this
    roll_medium_max_qn     = 0.5,  -- M: rolls/fills never faster than 8th-rate (always, any tempo)
    roll_easy_quarter_bpm  = 120,  -- E: rolls/fills reduced to quarter-rate at/above this
    general_hard_8th_bpm   = 170,  -- H: upper limit for constant 8th notes (where Expert is not faster)
    hard_trip_stream_bpm   = 140,  -- H: constant 8th triplets copied from Expert from this tempo
    general_medium_8th_bpm = 140,  -- M: timekeeping reduced from 8th above this (also used by E)
    kick_grid_bpm          = 100,  -- M/E: kicks quarter-grid-only above this
    kick_per_measure_bpm   = 170,  -- M/E: max 1 kick per measure above this
    min_run_len            = 4,    -- min consecutive 8th-note hits to call it a "run"
}
local R = DRUMS_RULES

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

-- Gem order matches LANE_NAMES in actions_drums.lua: offset 0=Kick, 1=Red(snare),
-- 2=Yellow, 3=Blue, 4=Green.
local GEM_NAMES = { 'Kick', 'Red', 'Yellow', 'Blue', 'Green' }

-- Beat duration (seconds) at project time t, using the project tempo map.
local function GetDrumsBeatDur(t)
    local bpm = GetTempoContextBefore(t)
    if not bpm or bpm <= 0 then bpm = 120 end
    return 60.0 / bpm
end

-- Project time -> quarter-note position, exact w.r.t. the tempo map.
-- Beat-fraction rules must be measured this way, not as seconds against a
-- single sampled BPM: with a fluctuating tempo map the seconds-length of a
-- 1/4 note changes inside the gap, so even grid-quantized notes drift a few ms.
local function QNAt(t) return r.TimeMap2_timeToQN(0, t) end

local GRACE  = 0.05  -- forgive gaps/grid positions up to 5% off (hand-placed notes)
local EPS_QN = 0.01  -- epsilon for classification thresholds (~5 ms at 120 BPM)

-- 1-based measure number at project time t.
local function GetMeasureAt(t)
    local s = r.format_timestr_pos(t, '', 1)  -- "M.B.HH" e.g. "5.1.00"
    return tonumber(s:match('^%s*(%d+)'))
end

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

-- Read non-muted notes in pitch range [lo, hi] from all MIDI items on track.
-- Pro Drums tom markers (110-112) never fall in these ranges, so they are
-- naturally excluded rather than requiring an explicit filter. Also reused
-- to read fill markers (120-124) and roll/trill markers (126/127) - both are
-- fixed pitches, not per-difficulty-shifted, so this generic reader works
-- for any marker lane, not just gem ranges.
function ReadDrumsNotes(track, lo, hi, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= lo and pitch <= hi then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = {
                            s     = s,
                            e     = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                            pitch = pitch,
                            vel   = vel,
                        }
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Group notes with the same start time (within 2 ms) into chord/hit events.
function GroupDrumsHits(notes)
    local events = {}
    local i = 1
    while i <= #notes do
        local ev = { s = notes[i].s, e = notes[i].e, pitches = { notes[i].pitch } }
        local j  = i + 1
        while j <= #notes and notes[j].s - ev.s <= 0.002 do
            ev.pitches[#ev.pitches + 1] = notes[j].pitch
            if notes[j].e > ev.e then ev.e = notes[j].e end
            j = j + 1
        end
        table.sort(ev.pitches)
        events[#events + 1] = ev
        i = j
    end
    return events
end

-- One tier's hit events ({ s, e, pitches }) and its note count.
function ReadDrumsTierEvents(track, diff_label, sel_s, sel_e)
    local rng   = DRUMS_RANGE[diff_label]
    local notes = ReadDrumsNotes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
    return GroupDrumsHits(notes), #notes
end

-- Gem name for a pitch: offset from the nearest difficulty's lo (0-4).
function DrumGemName(pitch)
    for _, rng in pairs(DRUMS_RANGE) do
        local offset = pitch - rng.lo
        if offset >= 0 and offset <= 4 then
            return GEM_NAMES[offset + 1]
        end
    end
    return PitchName(pitch)
end

function DrumLabel(pitches)
    if #pitches == 1 then return DrumGemName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = DrumGemName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

local function HasOffset(ev, rng, o)
    for _, p in ipairs(ev.pitches) do
        if p - rng.lo == o then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Check functions - each returns an array of DiffIssue records
----------------------------------------------------------------------

-- Medium (cascades to Easy): max 2 simultaneous notes. Replaces the earlier
-- kick+snare+cymbal-specific "3-limb hit" reading of the RBN doc - the
-- external source is more concrete: no chord may have 3+ notes at all.
local function CheckDrumsMaxChord(events, diff_label)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches >= 3 then
            issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: %s has %d notes (max 2 simultaneous notes on %s)'):format(
                FormatTime(ev.s), DrumLabel(ev.pitches), #ev.pitches, DIFF_NAMES[diff_label]))
        end
    end
    return issues
end

-- Easy: gems must not be paired with kick at all.
local function CheckDrumsKickPairing(events, offset_rng)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches >= 2 and HasOffset(ev, offset_rng, 0) then
            issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: %s pairs a gem with kick (not allowed on Easy)'):format(
                FormatTime(ev.s), DrumLabel(ev.pitches)))
        end
    end
    return issues
end

-- Medium only: a kick or snare note falling between two Yellow/Blue hits
-- (targets fast alternating-hand cymbal/tom patterns with a kick/snare
-- snuck in between). Not wired in: as written it is too strong (official Medium
-- keeps such notes on the beat - see RunDrumsChecks).
local function CheckDrumsYellowBlueInterleave(events, offset_rng)
    local yb_idx = {}
    for i, ev in ipairs(events) do
        if HasOffset(ev, offset_rng, 2) or HasOffset(ev, offset_rng, 3) then yb_idx[#yb_idx + 1] = i end
    end

    local issues = {}
    for k = 1, #yb_idx - 1 do
        local a, b = yb_idx[k], yb_idx[k + 1]
        for i = a + 1, b - 1 do
            local ev = events[i]
            if HasOffset(ev, offset_rng, 0) or HasOffset(ev, offset_rng, 1) then
                issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: %s falls between two Yellow/Blue hits (not allowed on Medium)'):format(
                    FormatTime(ev.s), DrumLabel(ev.pitches)))
            end
        end
    end
    return issues
end

-- Medium (cascades to Easy): kicks must land on the quarter-note grid once
-- the song is faster than kick_grid_bpm.
local function CheckDrumsKickGrid(events, offset_rng)
    local issues = {}
    for _, ev in ipairs(events) do
        if HasOffset(ev, offset_rng, 0) then
            local bpm = 60.0 / GetDrumsBeatDur(ev.s)
            if bpm > R.kick_grid_bpm then
                local frac = QNAt(ev.s) % 1.0
                local off  = math.min(frac, 1.0 - frac)
                if off > GRACE then
                    issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: kick at %.0f BPM is not on the quarter-note grid (kicks on quarter notes only above %d BPM)'):format(
                        FormatTime(ev.s), bpm, R.kick_grid_bpm))
                end
            end
        end
    end
    return issues
end

-- Medium (cascades to Easy): at or above kick_per_measure_bpm, no more than
-- one kick per measure.
local function CheckDrumsKickPerMeasure(events, offset_rng)
    local counts, first_t = {}, {}
    for _, ev in ipairs(events) do
        if HasOffset(ev, offset_rng, 0) then
            local m = GetMeasureAt(ev.s)
            if m then
                counts[m] = (counts[m] or 0) + 1
                if not first_t[m] then first_t[m] = ev.s end
            end
        end
    end

    local measures = {}
    for m in pairs(counts) do measures[#measures + 1] = m end
    table.sort(measures)

    local issues = {}
    for _, m in ipairs(measures) do
        if counts[m] > 1 then
            local bpm = 60.0 / GetDrumsBeatDur(first_t[m])
            if bpm >= R.kick_per_measure_bpm then
                issues[#issues + 1] = DiffIssue(first_t[m], {}, ('Measure %d has %d kicks at %.0f BPM (max 1 per measure at >=%d BPM)'):format(
                    m, counts[m], bpm, R.kick_per_measure_bpm))
            end
        end
    end
    return issues
end

-- A Yellow/Blue/Green gem (offset 2-4) at time t under its Pro Drums tom marker
-- (110-112) - a tom, not a cymbal. toms: ReadDrumsNotes(track, 110, 112).
local function UnderTom(toms, o, t)
    for _, m in ipairs(toms or {}) do
        if m.pitch == 108 + o and t >= m.s - 0.001 and t < m.e - 0.001 then return true end
    end
    return false
end

-- Medium only: a kick+crash(Green) chord is fine on-beat, but not off-beat/
-- syncopated. A Green tom is no crash.
local function CheckDrumsOnBeatCrashKick(events, offset_rng, toms)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches == 2 then
            local o1, o2 = ev.pitches[1] - offset_rng.lo, ev.pitches[2] - offset_rng.lo
            if o1 == 0 and o2 == 4 and not UnderTom(toms, 4, ev.s) then  -- kick + Green, pitches are sorted ascending
                local frac = QNAt(ev.s) % 1.0
                local off  = math.min(frac, 1.0 - frac)
                if off > GRACE then
                    issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: off-beat/syncopated crash+kick not allowed on Medium (on-beat only)'):format(
                        FormatTime(ev.s)))
                end
            end
        end
    end
    return issues
end

-- Cascades H -> M -> E: a Green+Yellow or Green+Blue double crash needs a
-- quarter-note gap before it to prepare, otherwise it should be reduced to a
-- single Green. Cymbals only: a gem under its tom marker makes it a tom pair or a
-- cymbal + tom, which official Hard keeps as is about half the time.
local function CheckDrumsDoubleCrash(events, offset_rng, toms)
    local issues = {}
    for i = 1, #events do
        local ev = events[i]
        if #ev.pitches == 2 then
            local o1, o2 = ev.pitches[1] - offset_rng.lo, ev.pitches[2] - offset_rng.lo
            if o2 == 4 and (o1 == 2 or o1 == 3)  -- double crash, sorted ascending
               and not UnderTom(toms, o1, ev.s) and not UnderTom(toms, o2, ev.s) then
                local ok_space = false
                if i > 1 then
                    local gap_qn = QNAt(ev.s) - QNAt(events[i - 1].s)
                    ok_space = gap_qn >= 1.0 * (1 - GRACE)
                end
                if not ok_space then
                    issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: %s double crash needs a quarter-note gap before it to prepare, or should be reduced to a single Green'):format(
                        FormatTime(ev.s), DrumLabel(ev.pitches)))
                end
            end
        end
    end
    return issues
end

-- Kicks in drum fills (pitch 120 markers, fixed - not per-difficulty-shifted). Official
-- charts thin a fill's kicks rather than removing them (RB3 DLC: a fill with 4-6 Expert
-- kicks keeps 3.2 on Hard, 2.1 on Medium; Hard/Medium leave under 5% of fills without
-- any), so this is advisory, and only flags a fill that keeps 2+ kicks and every kick of
-- the tier above. upper_events/upper_rng: the tier above (nil on Expert - not checked).
local function CheckDrumsFillKicks(events, fills, offset_rng, upper_events, upper_rng)
    if #fills == 0 or not upper_events then return {} end
    local function Kicks(evs, rng, fill)
        local n, first = 0, nil
        for _, ev in ipairs(evs) do
            if ev.s >= fill.s - 0.001 and ev.s < fill.e + 0.001 and HasOffset(ev, rng, 0) then
                n = n + 1
                first = first or ev
            end
        end
        return n, first
    end
    local issues = {}
    for _, fill in ipairs(fills) do
        local n, first = Kicks(events, offset_rng, fill)
        local up = Kicks(upper_events, upper_rng, fill)
        if n >= 2 and n >= up then
            issues[#issues + 1] = DiffIssue(first.s, first.pitches, ('%s: drum fill keeps all %d kicks of the tier above - thin them'):format(
                FormatTime(fill.s), n))
        end
    end
    return issues
end

-- Cascades H -> M -> E: a roll/trill marker (126/127) should start on an
-- 8th-note grid line (a quarter-note position is a subset of the 8th grid,
-- so one check covers both).
local function CheckDrumsRollGrid(rolls)
    local issues = {}
    for _, roll in ipairs(rolls) do
        local frac = QNAt(roll.s) % 0.5
        local off  = math.min(frac, 0.5 - frac)
        if off > 0.5 * GRACE then
            issues[#issues + 1] = DiffIssue(roll.s, {}, ('%s: roll does not start on an 8th/quarter-note grid line'):format(FormatTime(roll.s)))
        end
    end
    return issues
end

-- Cascades H -> M -> E: a roll/trill marker should cover an even number of
-- gem hits.
local function CheckDrumsRollEvenCount(rolls, events)
    local issues = {}
    for _, roll in ipairs(rolls) do
        local count = 0
        for _, ev in ipairs(events) do
            if ev.s >= roll.s - 0.001 and ev.s < roll.e + 0.001 then
                count = count + #ev.pitches
            end
        end
        if count > 0 and count % 2 == 1 then
            issues[#issues + 1] = DiffIssue(roll.s, {}, ('%s: roll has %d hits (should be an even number)'):format(FormatTime(roll.s), count))
        end
    end
    return issues
end

-- Average start-to-start gap (in quarter notes) between gem hits covered by
-- a roll's [s, e] span, or nil if fewer than 2 hits fall inside it.
local function RollAvgGapQN(roll, events)
    local times = {}
    for _, ev in ipairs(events) do
        if ev.s >= roll.s - 0.001 and ev.s < roll.e + 0.001 then
            times[#times + 1] = ev.s
        end
    end
    if #times < 2 then return nil end
    table.sort(times)
    return (QNAt(times[#times]) - QNAt(times[1])) / (#times - 1)
end

-- Roll/fill density vs. the tier's threshold:
--   Hard:   16th-rate rolls flagged only at/above roll_hard_16th_bpm.
--   Medium: never faster than 8th-rate, at any tempo (own blanket rule).
--   Easy:   quarter-rate required at/above roll_easy_quarter_bpm; below that,
--           inherits Medium's 8th-rate cap (Easy has no own override there).
local function CheckDrumsRollDensity(rolls, events, diff_label)
    local issues = {}
    for _, roll in ipairs(rolls) do
        local avg_gap = RollAvgGapQN(roll, events)
        if avg_gap then
            local bpm = 60.0 / GetDrumsBeatDur(roll.s)
            local msg
            if diff_label == 'H' then
                if bpm >= R.roll_hard_16th_bpm and avg_gap < 0.375 then
                    msg = ('%s: roll at %.0f BPM is authored at 16th-note rate (avoid 16ths at >=%d BPM on Hard)'):format(
                        FormatTime(roll.s), bpm, R.roll_hard_16th_bpm)
                end
            elseif diff_label == 'M' then
                if avg_gap < R.roll_medium_max_qn - EPS_QN then
                    msg = ('%s: roll is faster than 8th-note rate (Medium never plays rolls/fills at 16th-note rate)'):format(
                        FormatTime(roll.s))
                end
            elseif diff_label == 'E' then
                if bpm >= R.roll_easy_quarter_bpm then
                    if avg_gap < 1.0 - EPS_QN then
                        msg = ('%s: roll at %.0f BPM is faster than quarter-note rate (reduce fills to quarter notes at >=%d BPM on Easy)'):format(
                            FormatTime(roll.s), bpm, R.roll_easy_quarter_bpm)
                    end
                elseif avg_gap < R.roll_medium_max_qn - EPS_QN then
                    msg = ('%s: roll is faster than 8th-note rate (inherited from Medium - no Easy override below %d BPM)'):format(
                        FormatTime(roll.s), R.roll_easy_quarter_bpm)
                end
            end
            if msg then issues[#issues + 1] = DiffIssue(roll.s, {}, msg) end
        end
    end
    return issues
end

-- General timekeeping density (whole event stream, not roll-scoped): flags
-- maximal runs of >= min_run_len consecutive events spaced at a constant
-- 8th-note interval, gated by the tier's BPM threshold.
--   Hard:   ~170 BPM upper limit (own).
--   Medium: >=140 BPM (own, stricter than Hard - no inheritance needed).
--   Easy:   inherits Medium's 140 BPM (no own general-density override).
local function CheckDrumsGeneralDensity(events, diff_label, expert)
    local medium = diff_label == 'M' or diff_label == 'E'
    if diff_label ~= 'H' and not medium then return {} end
    -- Medium/Easy: every hit, constant 8ths from general_medium_8th_bpm (absolute).
    -- Hard, RELATIVE TO EXPERT (2026-10-14): hand notes only (a kick-only hit is no part of
    -- the hands' "constant stream"), and a run of min_run_len hand hits at one spacing is a
    -- problem only where Expert does not play faster over the same stretch - 8ths from
    -- general_hard_8th_bpm, 8th triplets from hard_trip_stream_bpm. A reduction (Expert's 8th
    -- triplets or 16ths played as 8ths) passes, a copy of Expert's own stream does not. The
    -- Generate planner's BreakEighthRuns counts the same way. `expert`: Expert's hit events
    -- (Hard only; without them every run counts, as before).
    local spacings = medium and { { 0.5, R.general_medium_8th_bpm, '8th notes' } }
                     or { { 0.5, R.general_hard_8th_bpm, '8th notes' }, { 1 / 3, R.hard_trip_stream_bpm, '8th triplets' } }
    -- Hit events with a hand gem: anything but the kick (every tier's kick pitch - 60, 72,
    -- 84, 96 - is a multiple of 12, so one test serves Hard and Expert alike).
    local function Hands(list)
        local out = {}
        for _, ev in ipairs(list or {}) do
            for _, p in ipairs(ev.pitches) do
                if p % 12 ~= DRUMS_RANGE.X.lo % 12 then out[#out + 1] = ev; break end
            end
        end
        return out
    end
    if not medium then events = Hands(events) end
    local xq = {}
    if not medium and expert then
        for _, ev in ipairs(Hands(expert)) do xq[#xq + 1] = QNAt(ev.s) end
    end
    local function ExpertFaster(a, b, sp)
        if medium or not expert then return false end
        local q0, q1 = QNAt(events[a].s), QNAt(events[b].s)
        local cnt, prev, closest = 0, nil, math.huge
        for _, q in ipairs(xq) do
            if q >= q0 - 0.01 and q <= q1 + 0.01 then
                cnt = cnt + 1
                if prev then closest = math.min(closest, q - prev) end
                prev = q
            end
        end
        return cnt > b - a + 1 or closest < sp - 0.01
    end
    local issues = {}
    local i = 1
    while i < #events do
        local gap = QNAt(events[i + 1].s) - QNAt(events[i].s)
        local sp
        for _, c in ipairs(spacings) do if math.abs(gap - c[1]) <= c[1] * GRACE then sp = c end end
        local j = i
        if sp then
            while j < #events do
                local g = QNAt(events[j + 1].s) - QNAt(events[j].s)
                if math.abs(g - sp[1]) > sp[1] * GRACE then break end
                j = j + 1
            end
        end
        local run_len = j - i + 1
        if sp and run_len >= R.min_run_len then
            local bpm = 60.0 / GetDrumsBeatDur(events[i].s)
            if bpm >= sp[2] then
                -- The first stretch of min_run_len hits Expert does not play faster.
                local bad
                for a = i, j - R.min_run_len + 1 do
                    if not ExpertFaster(a, a + R.min_run_len - 1, sp[1]) then bad = a; break end
                end
                if bad then
                    issues[#issues + 1] = DiffIssue(events[i].s, events[i].pitches,
                        ('%s-%s: %d consecutive %s at %.0f BPM%s (reduce timekeeping density above %d BPM on %s)'):format(
                        FormatTime(events[i].s), FormatTime(events[j].s), run_len, sp[3], bpm,
                        medium and '' or ' where Expert plays them too', sp[2], DIFF_NAMES[diff_label]))
                end
            end
            i = j + 1
        else
            i = i + 1
        end
    end
    return issues
end

-- Notes with pitches above the valid hi for this difficulty (authoring error).
local function CheckDrumsOutOfRange(events, rng_hi)
    local issues = {}
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            if p > rng_hi then
                issues[#issues + 1] = DiffIssue(ev.s, ev.pitches, ('%s: %s (pitch %d) is outside the valid range for this difficulty'):format(
                    FormatTime(ev.s), DrumGemName(p), p))
            end
        end
    end
    return issues
end

-- Roll/Trill markers (fixed pitches 126/127, not per-difficulty-shifted):
-- velocity <=40 causes a Magma spacing error if the roll needs to reduce to
-- Hard or lower (41-50 required for Hard eligibility).
local function CheckDrumsRollVelocity(track, sel_s, sel_e)
    local issues = {}
    for _, n in ipairs(ReadDrumsNotes(track, 126, 127, sel_s, sel_e)) do
        if n.vel <= 40 then
            local kind = n.pitch == 127 and 'Special/cymbal-swell roll' or 'Roll'
            issues[#issues + 1] = DiffIssue(n.s, {}, ('%s: %s marker velocity %d (need 41-50 for Hard eligibility - Magma will report a spacing error)'):format(
                FormatTime(n.s), kind, n.vel))
        end
    end
    return issues
end

-- Every check for one tier, as categories { name, rule, issues, advisory? }, in report
-- order. upper_events: the tier above, as hit events (nil for Expert or when unknown) -
-- the fill-kick advisory compares against it.
-- track/sel_s/sel_e: needed to read fill (120) and roll/trill (126/127) markers.
function CollectDrumsChecks(diff_label, events, track, sel_s, sel_e, upper_events)
    local rng  = DRUMS_RANGE[diff_label]
    local cats = {}
    -- Pro Drums tom markers, read whole: one that starts before the selection still covers
    -- the gems in it.
    local toms = ReadDrumsNotes(track, 110, 112)

    cats[#cats + 1] = { name = 'Notes outside valid range', rule = 'range', issues = CheckDrumsOutOfRange(events, rng.hi) }

    if diff_label == 'M' or diff_label == 'E' then
        cats[#cats + 1] = { name = 'Max chord size (2 notes)', rule = 'chord_size', issues = CheckDrumsMaxChord(events, diff_label) }
        cats[#cats + 1] = { name = 'Kicks on quarter-note grid', rule = 'kick_grid', issues = CheckDrumsKickGrid(events, rng) }
        cats[#cats + 1] = { name = 'Kicks per measure', rule = 'kick_per_measure', issues = CheckDrumsKickPerMeasure(events, rng) }
    end

    if diff_label == 'M' then
        -- CheckDrumsYellowBlueInterleave is not wired in: as written it doesn't match
        -- the intended rule (too strong) - official Medium keeps a kick or snare between
        -- hi-hat notes when it falls on the beat (RB3 DLC: 83-94% of those survive).
        cats[#cats + 1] = { name = 'On-beat crash+kick only', rule = 'crash_kick', issues = CheckDrumsOnBeatCrashKick(events, rng, toms) }
    elseif diff_label == 'E' then
        cats[#cats + 1] = { name = 'No gems paired with kick (Easy)', rule = 'kick_pairing', issues = CheckDrumsKickPairing(events, rng) }
    end

    -- Hard: a roll lane whose marker velocity is 41-50 is a lane on Hard too, played as
    -- Expert's notes (RBN doc) - its notes are not held to Hard's roll and density limits.
    local all_rolls = (diff_label ~= 'X') and ReadDrumsNotes(track, 126, 127, sel_s, sel_e) or {}
    local rolls, hard_lanes = {}, {}
    for _, n in ipairs(all_rolls) do
        if diff_label == 'H' and n.vel >= 41 and n.vel <= 50 then hard_lanes[#hard_lanes + 1] = n
        else rolls[#rolls + 1] = n end
    end
    local timed = events
    if #hard_lanes > 0 then
        timed = {}
        for _, ev in ipairs(events) do
            local under = false
            for _, l in ipairs(hard_lanes) do
                if ev.s >= l.s - 0.001 and ev.s < l.e + 0.001 then under = true; break end
            end
            if not under then timed[#timed + 1] = ev end
        end
    end

    if diff_label ~= 'X' then
        cats[#cats + 1] = { name = 'Timekeeping density', rule = 'density', issues = CheckDrumsGeneralDensity(timed, diff_label,
            diff_label == 'H' and (ReadDrumsTierEvents(track, 'X', sel_s, sel_e)) or nil) }
        cats[#cats + 1] = { name = 'Double crash prep space', rule = 'double_crash', issues = CheckDrumsDoubleCrash(events, rng, toms) }

        local fills = ReadDrumsNotes(track, 120, 120, sel_s, sel_e)
        local up_dl = ({ H = 'X', M = 'H', E = 'M' })[diff_label]
        cats[#cats + 1] = { name = 'Kicks in drum fills (advisory: thin them)', rule = 'fill_kicks', advisory = true,
                            issues = CheckDrumsFillKicks(events, fills, rng, upper_events, DRUMS_RANGE[up_dl]) }
        -- marker = true: the check is about the roll lane marker (shared by every tier), not
        -- the tier's notes - Generate does not count it against the tier it wrote.
        cats[#cats + 1] = { name = 'Roll starts on grid',     rule = 'roll_grid',    marker = true,
                            issues = CheckDrumsRollGrid(all_rolls) }
        cats[#cats + 1] = { name = 'Even roll hit count',     rule = 'roll_even',    issues = CheckDrumsRollEvenCount(rolls, events) }
        cats[#cats + 1] = { name = 'Roll/fill density',       rule = 'roll_density', issues = CheckDrumsRollDensity(rolls, events, diff_label) }
    end

    if diff_label == 'H' then
        cats[#cats + 1] = { name = 'Roll/Trill velocity (Hard eligibility)', rule = 'roll_velocity', marker = true,
                            issues = CheckDrumsRollVelocity(track, sel_s, sel_e) }
    end

    return cats
end
