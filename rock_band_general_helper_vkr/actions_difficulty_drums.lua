-- Drums difficulty validation and copy-to-next-tier tools
-- Requires: S, r, GetTimeSelection, GetTempoContextBefore, FormatTime, PitchName,
--           FindFirstMIDIItem, InsertNotes, ClearNotesInRange (globals)

-- Per-difficulty pitch ranges on PART DRUMS (single track, like PART KEYS)
local DRUMS_RANGE = {
    X = { lo = 96, hi = 100 },
    H = { lo = 84, hi = 88  },
    M = { lo = 72, hi = 76  },
    E = { lo = 60, hi = 64  },
}

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

-- Gem order matches LANE_NAMES in actions_drums.lua: offset 0=Kick, 1=Red(snare),
-- 2=Yellow, 3=Blue, 4=Green.
local GEM_NAMES = { 'Kick', 'Red', 'Yellow', 'Blue', 'Green' }

local DIFF_BY_MIX_IDX = { [0] = 'Easy', [1] = 'Medium', [2] = 'Hard', [3] = 'Expert' }

-- Immediately-higher adjacent tier, for the cross-difficulty progression
-- check (CheckDifficultyProgression in actions_difficulty_shared.lua).
local ADJACENT_HIGHER = { H = 'X', M = 'H', E = 'M' }

-- Sum of individual notes across all chord events (not chord/event count).
local function CountNotes(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

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

-- Tempo/density thresholds from external RBN authoring guidance (layered on
-- top of the base rules above). Each cascades from a higher difficulty down
-- to an easier one that doesn't define its own stricter version - see the
-- per-check comments below for which direction applies.
local ROLL_HARD_16TH_BPM     = 140  -- H: avoid 16th-rate rolls at/above this
local ROLL_MEDIUM_MAX_QN     = 0.5  -- M: rolls/fills never faster than 8th-rate (always, any tempo)
local ROLL_EASY_QUARTER_BPM  = 120  -- E: rolls/fills reduced to quarter-rate at/above this
local GENERAL_HARD_8TH_BPM   = 170  -- H: upper limit for constant 8th notes
local GENERAL_MEDIUM_8TH_BPM = 140  -- M: timekeeping reduced from 8th above this (also used by E)
local KICK_GRID_BPM          = 100  -- M/E: kicks quarter-grid-only above this
local KICK_PER_MEASURE_BPM   = 170  -- M/E: max 1 kick per measure above this
local MIN_RUN_LEN            = 4    -- min consecutive 8th-note hits to call it a "run"

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

-- Read non-muted notes in pitch range [lo, hi] from all MIDI items on track.
-- Pro Drums tom markers (110-112) never fall in these ranges, so they are
-- naturally excluded rather than requiring an explicit filter. Also reused
-- to read fill markers (120-124) and roll/trill markers (126/127) - both are
-- fixed pitches, not per-difficulty-shifted, so this generic reader works
-- for any marker lane, not just gem ranges.
local function ReadDrumsNotes(track, lo, hi, t_s, t_e)
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
local function GroupDrumsHits(notes)
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

-- Gem name for a pitch: offset from the nearest difficulty's lo (0-4).
local function DrumGemName(pitch)
    for _, rng in pairs(DRUMS_RANGE) do
        local offset = pitch - rng.lo
        if offset >= 0 and offset <= 4 then
            return GEM_NAMES[offset + 1]
        end
    end
    return PitchName(pitch)
end

local function DrumLabel(pitches)
    if #pitches == 1 then return DrumGemName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = DrumGemName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

----------------------------------------------------------------------
-- Check functions - each returns an array of issue strings
----------------------------------------------------------------------

-- Medium (cascades to Easy): max 2 simultaneous notes. Replaces the earlier
-- kick+snare+cymbal-specific "3-limb hit" reading of the RBN doc - the
-- external source is more concrete: no chord may have 3+ notes at all.
local function CheckDrumsMaxChord(events, diff_label)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches >= 3 then
            issues[#issues + 1] = ('%s: %s has %d notes (max 2 simultaneous notes on %s)'):format(
                FormatTime(ev.s), DrumLabel(ev.pitches), #ev.pitches, DIFF_NAMES[diff_label])
        end
    end
    return issues
end

-- Easy: gems must not be paired with kick at all.
local function CheckDrumsKickPairing(events, offset_rng)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches >= 2 then
            for _, p in ipairs(ev.pitches) do
                if p - offset_rng.lo == 0 then
                    issues[#issues + 1] = ('%s: %s pairs a gem with kick (not allowed on Easy)'):format(
                        FormatTime(ev.s), DrumLabel(ev.pitches))
                    break
                end
            end
        end
    end
    return issues
end

-- Medium only: a kick or snare note falling between two Yellow/Blue hits
-- (targets fast alternating-hand cymbal/tom patterns with a kick/snare
-- snuck in between).
local function CheckDrumsYellowBlueInterleave(events, offset_rng)
    local yb_idx = {}
    for i, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            local o = p - offset_rng.lo
            if o == 2 or o == 3 then yb_idx[#yb_idx + 1] = i; break end
        end
    end

    local issues = {}
    for k = 1, #yb_idx - 1 do
        local a, b = yb_idx[k], yb_idx[k + 1]
        for i = a + 1, b - 1 do
            local ev = events[i]
            local has_ks = false
            for _, p in ipairs(ev.pitches) do
                local o = p - offset_rng.lo
                if o == 0 or o == 1 then has_ks = true; break end
            end
            if has_ks then
                issues[#issues + 1] = ('%s: %s falls between two Yellow/Blue hits (not allowed on Medium)'):format(
                    FormatTime(ev.s), DrumLabel(ev.pitches))
            end
        end
    end
    return issues
end

-- Medium (cascades to Easy): kicks must land on the quarter-note grid once
-- the song is faster than KICK_GRID_BPM.
local function CheckDrumsKickGrid(events, offset_rng)
    local issues = {}
    for _, ev in ipairs(events) do
        local has_kick = false
        for _, p in ipairs(ev.pitches) do
            if p - offset_rng.lo == 0 then has_kick = true; break end
        end
        if has_kick then
            local bpm = 60.0 / GetDrumsBeatDur(ev.s)
            if bpm > KICK_GRID_BPM then
                local frac = QNAt(ev.s) % 1.0
                local off  = math.min(frac, 1.0 - frac)
                if off > GRACE then
                    issues[#issues + 1] = ('%s: kick at %.0f BPM is not on the quarter-note grid (kicks on quarter notes only above %d BPM)'):format(
                        FormatTime(ev.s), bpm, KICK_GRID_BPM)
                end
            end
        end
    end
    return issues
end

-- Medium (cascades to Easy): at or above KICK_PER_MEASURE_BPM, no more than
-- one kick per measure.
local function CheckDrumsKickPerMeasure(events, offset_rng)
    local counts, first_t = {}, {}
    for _, ev in ipairs(events) do
        local has_kick = false
        for _, p in ipairs(ev.pitches) do
            if p - offset_rng.lo == 0 then has_kick = true; break end
        end
        if has_kick then
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
            if bpm >= KICK_PER_MEASURE_BPM then
                issues[#issues + 1] = ('Measure %d has %d kicks at %.0f BPM (max 1 per measure at >=%d BPM)'):format(
                    m, counts[m], bpm, KICK_PER_MEASURE_BPM)
            end
        end
    end
    return issues
end

-- Medium only: a kick+crash(Green) chord is fine on-beat, but not off-beat/
-- syncopated.
local function CheckDrumsOnBeatCrashKick(events, offset_rng)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches == 2 then
            local o1, o2 = ev.pitches[1] - offset_rng.lo, ev.pitches[2] - offset_rng.lo
            if o1 == 0 and o2 == 4 then  -- kick + Green, pitches are sorted ascending
                local frac = QNAt(ev.s) % 1.0
                local off  = math.min(frac, 1.0 - frac)
                if off > GRACE then
                    issues[#issues + 1] = ('%s: off-beat/syncopated crash+kick not allowed on Medium (on-beat only)'):format(
                        FormatTime(ev.s))
                end
            end
        end
    end
    return issues
end

-- Cascades H -> M -> E: a Green+Yellow or Green+Blue double crash needs a
-- quarter-note gap before it to prepare, otherwise it should be reduced to a
-- single Green.
local function CheckDrumsDoubleCrash(events, offset_rng)
    local issues = {}
    for i = 1, #events do
        local ev = events[i]
        if #ev.pitches == 2 then
            local o1, o2 = ev.pitches[1] - offset_rng.lo, ev.pitches[2] - offset_rng.lo
            if o2 == 4 and (o1 == 2 or o1 == 3) then  -- double crash, sorted ascending
                local ok_space = false
                if i > 1 then
                    local gap_qn = QNAt(ev.s) - QNAt(events[i - 1].s)
                    ok_space = gap_qn >= 1.0 * (1 - GRACE)
                end
                if not ok_space then
                    issues[#issues + 1] = ('%s: %s double crash needs a quarter-note gap before it to prepare, or should be reduced to a single Green'):format(
                        FormatTime(ev.s), DrumLabel(ev.pitches))
                end
            end
        end
    end
    return issues
end

-- Cascades H -> M -> E: no kick may start inside a drum fill (pitch 120-124
-- markers, fixed - not per-difficulty-shifted).
local function CheckDrumsFillKicks(events, fills, offset_rng)
    if #fills == 0 then return {} end
    local issues = {}
    for _, ev in ipairs(events) do
        local has_kick = false
        for _, p in ipairs(ev.pitches) do
            if p - offset_rng.lo == 0 then has_kick = true; break end
        end
        if has_kick then
            for _, fill in ipairs(fills) do
                if ev.s >= fill.s - 0.001 and ev.s < fill.e + 0.001 then
                    issues[#issues + 1] = ('%s: kick during a drum fill (remove kicks from fills)'):format(FormatTime(ev.s))
                    break
                end
            end
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
            issues[#issues + 1] = ('%s: roll does not start on an 8th/quarter-note grid line'):format(FormatTime(roll.s))
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
            issues[#issues + 1] = ('%s: roll has %d hits (should be an even number)'):format(FormatTime(roll.s), count)
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
--   Hard:   16th-rate rolls flagged only at/above ROLL_HARD_16TH_BPM.
--   Medium: never faster than 8th-rate, at any tempo (own blanket rule).
--   Easy:   quarter-rate required at/above ROLL_EASY_QUARTER_BPM; below that,
--           inherits Medium's 8th-rate cap (Easy has no own override there).
local function CheckDrumsRollDensity(rolls, events, diff_label)
    local issues = {}
    for _, roll in ipairs(rolls) do
        local avg_gap = RollAvgGapQN(roll, events)
        if avg_gap then
            local bpm = 60.0 / GetDrumsBeatDur(roll.s)
            if diff_label == 'H' then
                if bpm >= ROLL_HARD_16TH_BPM and avg_gap < 0.375 then
                    issues[#issues + 1] = ('%s: roll at %.0f BPM is authored at 16th-note rate (avoid 16ths at >=%d BPM on Hard)'):format(
                        FormatTime(roll.s), bpm, ROLL_HARD_16TH_BPM)
                end
            elseif diff_label == 'M' then
                if avg_gap < ROLL_MEDIUM_MAX_QN - EPS_QN then
                    issues[#issues + 1] = ('%s: roll is faster than 8th-note rate (Medium never plays rolls/fills at 16th-note rate)'):format(
                        FormatTime(roll.s))
                end
            elseif diff_label == 'E' then
                if bpm >= ROLL_EASY_QUARTER_BPM then
                    if avg_gap < 1.0 - EPS_QN then
                        issues[#issues + 1] = ('%s: roll at %.0f BPM is faster than quarter-note rate (reduce fills to quarter notes at >=%d BPM on Easy)'):format(
                            FormatTime(roll.s), bpm, ROLL_EASY_QUARTER_BPM)
                    end
                elseif avg_gap < ROLL_MEDIUM_MAX_QN - EPS_QN then
                    issues[#issues + 1] = ('%s: roll is faster than 8th-note rate (inherited from Medium - no Easy override below %d BPM)'):format(
                        FormatTime(roll.s), ROLL_EASY_QUARTER_BPM)
                end
            end
        end
    end
    return issues
end

-- General timekeeping density (whole event stream, not roll-scoped): flags
-- maximal runs of >= MIN_RUN_LEN consecutive events spaced at a constant
-- 8th-note interval, gated by the tier's BPM threshold.
--   Hard:   ~170 BPM upper limit (own).
--   Medium: >=140 BPM (own, stricter than Hard - no inheritance needed).
--   Easy:   inherits Medium's 140 BPM (no own general-density override).
local function CheckDrumsGeneralDensity(events, diff_label)
    local bpm_threshold
    if diff_label == 'H' then bpm_threshold = GENERAL_HARD_8TH_BPM
    elseif diff_label == 'M' or diff_label == 'E' then bpm_threshold = GENERAL_MEDIUM_8TH_BPM
    else return {} end

    local issues = {}
    local i = 1
    while i < #events do
        local run_start = i
        local j = i
        while j < #events do
            local gap_qn = QNAt(events[j + 1].s) - QNAt(events[j].s)
            if math.abs(gap_qn - 0.5) > 0.5 * GRACE then break end
            j = j + 1
        end
        local run_len = j - run_start + 1
        if run_len >= MIN_RUN_LEN then
            local bpm = 60.0 / GetDrumsBeatDur(events[run_start].s)
            if bpm >= bpm_threshold then
                issues[#issues + 1] = ('%s-%s: %d consecutive 8th notes at %.0f BPM (reduce timekeeping density above %d BPM on %s)'):format(
                    FormatTime(events[run_start].s), FormatTime(events[j].s), run_len, bpm, bpm_threshold, DIFF_NAMES[diff_label])
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
                issues[#issues + 1] = ('%s: %s (pitch %d) is outside the valid range for this difficulty'):format(
                    FormatTime(ev.s), DrumGemName(p), p)
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
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, _, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted and (pitch == 126 or pitch == 127) then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                        if vel <= 40 then
                            local kind = pitch == 127 and 'Special/cymbal-swell roll' or 'Roll'
                            issues[#issues + 1] = ('%s: %s marker velocity %d (need 41-50 for Hard eligibility - Magma will report a spacing error)'):format(
                                FormatTime(s), kind, vel)
                        end
                    end
                end
            end
        end
    end
    return issues
end

-- Hard only: Hard should have fewer kicks than Expert (Medium/Easy already
-- have their own distinct/stronger kick rules, so this isn't cascaded).
local function CheckDrumsKickCountVsHigher(events, higher_events, offset_rng, higher_offset_rng)
    local function KickCount(evs, rng)
        local n = 0
        for _, ev in ipairs(evs) do
            for _, p in ipairs(ev.pitches) do
                if p - rng.lo == 0 then n = n + 1 end
            end
        end
        return n
    end
    local higher_kicks = KickCount(higher_events, higher_offset_rng)
    if higher_kicks == 0 then return {} end
    local lower_kicks = KickCount(events, offset_rng)
    if lower_kicks < higher_kicks then return {} end
    return {
        ('Hard has %d kicks and Expert has %d kicks - Hard should have fewer kicks than Expert'):format(
            lower_kicks, higher_kicks),
    }
end

-- Hard only: the Hard-tier (diff_idx==2) [mix N drums<config>] event should
-- use the un-flipped/base config, not the disco ("d") variant - on Hard,
-- disco beats are charted as a normal 8-beat.
local function CheckDrumsDiscoUnflip(track, sel_s, sel_e)
    local issues = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textsyxevtcnt = r.MIDI_CountEvts(take)
            for j = 0, textsyxevtcnt - 1 do
                local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and evtype == 1 then
                    local mix_idx, cfg, suffix = msg:match('%[mix (%d+) drums(%d)(%a*)%]')
                    if mix_idx and tonumber(mix_idx) == 2 then
                        local s = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
                        if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                            if suffix == 'd' then
                                issues[#issues + 1] = ('%s: Hard mix event uses the disco variant (drums%sd) - Hard should use the un-flipped/base config (drums%s or drums%snoflip)'):format(
                                    FormatTime(s), cfg, cfg, cfg)
                            end
                        end
                    end
                end
            end
        end
    end
    return issues
end

-- Informational scan of [mix <difficulty 0-3> drums<config>] text/sysex events.
-- Not a pass/fail check: whether a given disco-flip configuration is correct
-- depends on the surrounding beat pattern, which can't be judged from note
-- data alone. Reports which difficulty tiers have a mix event authored.
local function ScanDiscoFlipStatus(track, sel_s, sel_e)
    local found = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textsyxevtcnt = r.MIDI_CountEvts(take)
            for j = 0, textsyxevtcnt - 1 do
                local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and evtype == 1 then
                    local mix_idx, cfg, suffix = msg:match('%[mix (%d+) drums(%d)(%a*)%]')
                    if mix_idx then
                        local s = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
                        if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                            found[#found + 1] = {
                                s = s, diff_idx = tonumber(mix_idx), cfg = cfg, suffix = suffix,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.s < b.s end)

    if #found == 0 then
        return 'Disco flip: no [mix N drums...] events found on this track.'
    end
    local lines = { 'Disco flip status (informational only - not pass/fail):' }
    for _, f in ipairs(found) do
        local diff_name = DIFF_BY_MIX_IDX[f.diff_idx] or ('idx ' .. f.diff_idx)
        lines[#lines + 1] = ('  %s: mix %d drums%s%s (%s)'):format(
            FormatTime(f.s), f.diff_idx, f.cfg, f.suffix, diff_name)
    end
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Authoring hints - qualitative/subjective source rules that can't become a
-- deterministic pass/fail check. Always shown, never counted as an issue.
----------------------------------------------------------------------

local DRUMS_HINTS = {
    H = {
        'Try removing kicks from adjacent 8th or 16th notes.',
        'In a section filled with little snare accents, remove about half of them.',
        'Trim a note or two from the start of a fast roll.',
        'Reduce hand motion: if a crash happens right after a snare flam (Red+Yellow), consider making the flam a one-handed snare hit instead.',
    },
    M = {
        'It is usually best to reduce triplets to quarter notes.',
    },
    E = {
        'Favor crash (Green) over kick when simplifying a beat.',
    },
}

local function DrumsAuthoringHints(diff_label)
    local hints = DRUMS_HINTS[diff_label]
    if not hints or #hints == 0 then return '' end
    local lines = { 'Authoring hints (suggestions, not hard rules):' }
    for _, h in ipairs(hints) do
        lines[#lines + 1] = '  \xe2\x80\xa2 ' .. h
    end
    return table.concat(lines, '\n') .. '\n\n'
end

----------------------------------------------------------------------
-- Report builder and validation runner
----------------------------------------------------------------------

local function BuildDrumsReport(header, cats)
    local lines = { header, '' }
    local total = 0
    local ok_cats = {}
    for _, cat in ipairs(cats) do
        if #cat.issues > 0 then
            lines[#lines + 1] = cat.name .. ':'
            for _, issue in ipairs(cat.issues) do
                lines[#lines + 1] = '  ' .. issue
                total = total + 1
            end
            lines[#lines + 1] = ''
        else
            ok_cats[#ok_cats + 1] = cat.name
        end
    end
    if total == 0 then
        lines[#lines + 1] = 'No issues found.'
        lines[#lines + 1] = ''
    elseif #ok_cats > 0 then
        lines[#lines + 1] = 'Passed: ' .. table.concat(ok_cats, ', ')
        lines[#lines + 1] = ''
    end
    return table.concat(lines, '\n'), total
end

-- rng: the target tier's range - also used as offset_rng to compute "is this
-- pitch the kick" etc. track/sel_s/sel_e: needed to read fill (120-124) and
-- roll/trill (126/127) markers for the marker-based checks.
local function RunDrumsChecks(diff_label, events, header, rng, track, sel_s, sel_e)
    local cats = {}
    local offset_rng = rng

    cats[#cats + 1] = { name = 'Notes outside valid range', issues = CheckDrumsOutOfRange(events, rng.hi) }

    if diff_label == 'M' or diff_label == 'E' then
        cats[#cats + 1] = { name = 'Max chord size (2 notes)', issues = CheckDrumsMaxChord(events, diff_label) }
        cats[#cats + 1] = { name = 'Kicks on quarter-note grid', issues = CheckDrumsKickGrid(events, offset_rng) }
        cats[#cats + 1] = { name = 'Kicks per measure', issues = CheckDrumsKickPerMeasure(events, offset_rng) }
    end

    if diff_label == 'M' then
        -- CheckDrumsYellowBlueInterleave is disabled for now: as currently
        -- written it doesn't match the intended rule (too strong). Left
        -- defined above, just not wired in, so it can be tuned once the
        -- rule is better understood without touching the rest of the module.
        cats[#cats + 1] = { name = 'On-beat crash+kick only', issues = CheckDrumsOnBeatCrashKick(events, offset_rng) }
    elseif diff_label == 'E' then
        cats[#cats + 1] = { name = 'No gems paired with kick (Easy)', issues = CheckDrumsKickPairing(events, offset_rng) }
    end

    if diff_label ~= 'X' then
        cats[#cats + 1] = { name = 'Timekeeping density', issues = CheckDrumsGeneralDensity(events, diff_label) }
        cats[#cats + 1] = { name = 'Double crash prep space', issues = CheckDrumsDoubleCrash(events, offset_rng) }

        local fills = ReadDrumsNotes(track, 120, 124, sel_s, sel_e)
        local rolls = ReadDrumsNotes(track, 126, 127, sel_s, sel_e)
        cats[#cats + 1] = { name = 'No kicks in drum fills', issues = CheckDrumsFillKicks(events, fills, offset_rng) }
        cats[#cats + 1] = { name = 'Roll starts on grid',     issues = CheckDrumsRollGrid(rolls) }
        cats[#cats + 1] = { name = 'Even roll hit count',     issues = CheckDrumsRollEvenCount(rolls, events) }
        cats[#cats + 1] = { name = 'Roll/fill density',       issues = CheckDrumsRollDensity(rolls, events, diff_label) }
    end

    if diff_label == 'H' then
        cats[#cats + 1] = {
            name   = 'Roll/Trill velocity (Hard eligibility)',
            issues = CheckDrumsRollVelocity(track, sel_s, sel_e),
        }
    end

    return BuildDrumsReport(header, cats)
end

----------------------------------------------------------------------
-- Global action functions
----------------------------------------------------------------------

-- Validate notes in the diff_label pitch range on PART DRUMS.
function ValidateDrumsDiff(diff_label)
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local rng           = DRUMS_RANGE[diff_label]
    local sel_s, sel_e   = GetTimeSelection()
    local notes          = ReadDrumsNotes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
    local events         = GroupDrumsHits(notes)

    if #notes == 0 then
        S.status = ('Validate Drums %s: no notes in %s-%s (%d-%d).'):format(
            diff_label, PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi)
        S.last_result = sel_s
            and ('No %s notes (%s-%s) in the current time selection.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
            or  ('No %s notes (%s-%s) on PART DRUMS track.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
        return
    end

    local scope  = sel_s and ' [time selection]' or ''
    local header = ('Drums %s Validation  [%s-%s, %d-%d]%s'):format(
        DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi, scope)
    local report, total = RunDrumsChecks(diff_label, events, header, rng, track, sel_s, sel_e)

    -- Cross-difficulty progression check (vs the immediately higher tier),
    -- plus the Hard-only kick-count and disco-unflip checks that reuse the
    -- same higher-tier data.
    local higher_dl = ADJACENT_HIGHER[diff_label]
    if higher_dl then
        local higher_rng    = DRUMS_RANGE[higher_dl]
        local higher_notes  = ReadDrumsNotes(track, higher_rng.lo, higher_rng.lo + 4, sel_s, sel_e)
        local higher_events = GroupDrumsHits(higher_notes)
        local block, extra = CheckDifficultyProgression(
            DIFF_NAMES[diff_label], DIFF_NAMES[higher_dl],
            events, higher_events, rng.lo, higher_rng.lo,
            CountNotes(events), CountNotes(higher_events))
        report = block .. report
        total  = total + extra

        if diff_label == 'H' then
            local kick_issues = CheckDrumsKickCountVsHigher(events, higher_events, rng, higher_rng)
            if #kick_issues > 0 then
                report = report .. table.concat(kick_issues, '\n') .. '\n\n'
                total  = total + #kick_issues
            end
            local unflip_issues = CheckDrumsDiscoUnflip(track, sel_s, sel_e)
            if #unflip_issues > 0 then
                report = report .. table.concat(unflip_issues, '\n') .. '\n\n'
                total  = total + #unflip_issues
            end
        end
    end

    report = report .. DrumsAuthoringHints(diff_label)
    report = report .. ScanDiscoFlipStatus(track, sel_s, sel_e)

    if total == 0 then
        S.status = ('Validate Drums %s: all checks passed%s.'):format(diff_label, scope)
    else
        S.status = ('Validate Drums %s: %d issue%s found%s.'):format(
            diff_label, total, total == 1 and '' or 's', scope)
    end
    S.last_result = report
end

-- Validate all four difficulty ranges on PART DRUMS in a combined report.
function ValidateAllDrums()
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local scope         = sel_s and ' [time selection]' or ''
    local diff_order    = { 'X', 'H', 'M', 'E' }
    local all_lines     = { ('Drums Validate All%s'):format(scope), '' }
    local summary       = {}

    -- Carried forward from the previous (higher) tier for the cross-difficulty
    -- progression check - avoids re-reading a range already read this loop.
    local prev_dl, prev_events, prev_count = nil, {}, 0

    for _, dl in ipairs(diff_order) do
        local rng    = DRUMS_RANGE[dl]
        local notes  = ReadDrumsNotes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
        local events = GroupDrumsHits(notes)

        if #notes == 0 then
            summary[#summary + 1] = dl .. ':empty'
            all_lines[#all_lines + 1] = ('=== %s ===  (no notes in range %d-%d)'):format(
                DIFF_NAMES[dl], rng.lo, rng.hi)
            all_lines[#all_lines + 1] = ''
            prev_dl, prev_events, prev_count = dl, {}, 0
        else
            local header        = ('=== Drums %s  [%d-%d] ==='):format(DIFF_NAMES[dl], rng.lo, rng.hi)
            local report, total = RunDrumsChecks(dl, events, header, rng, track, sel_s, sel_e)

            if dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] then
                local block, extra = CheckDifficultyProgression(
                    DIFF_NAMES[dl], DIFF_NAMES[prev_dl],
                    events, prev_events, rng.lo, DRUMS_RANGE[prev_dl].lo,
                    CountNotes(events), prev_count)
                report = block .. report
                total  = total + extra

                if dl == 'H' then
                    local kick_issues = CheckDrumsKickCountVsHigher(events, prev_events, rng, DRUMS_RANGE[prev_dl])
                    if #kick_issues > 0 then
                        report = report .. table.concat(kick_issues, '\n') .. '\n\n'
                        total  = total + #kick_issues
                    end
                    local unflip_issues = CheckDrumsDiscoUnflip(track, sel_s, sel_e)
                    if #unflip_issues > 0 then
                        report = report .. table.concat(unflip_issues, '\n') .. '\n\n'
                        total  = total + #unflip_issues
                    end
                end
            end

            report = report .. DrumsAuthoringHints(dl)

            summary[#summary + 1] = total == 0 and (dl .. ':OK') or ('%s:%d'):format(dl, total)
            for line in (report .. '\n'):gmatch('([^\n]*)\n') do
                all_lines[#all_lines + 1] = line
            end
            prev_dl, prev_events, prev_count = dl, events, CountNotes(events)
        end
    end

    all_lines[#all_lines + 1] = ScanDiscoFlipStatus(track, sel_s, sel_e)

    S.status      = ('Validate All Drums%s: %s'):format(scope, table.concat(summary, ' | '))
    S.last_result = table.concat(all_lines, '\n')
end

-- Copy notes from the immediately higher tier's range onto diff_label's own
-- range on PART DRUMS. Every Drums tier has the same 5 lanes (hi-lo=4
-- always), so CompressChordOffsets is a no-op here - included anyway for
-- consistency with Keys/Guitar-Bass's copy functions.
-- force: skip the "target already has notes" confirmation and overwrite
-- directly (set true when called again from the confirm popup).
function CopyDrumsDiff(diff_label, force)
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local src_dl = ADJACENT_HIGHER[diff_label]
    if not src_dl then
        S.status = 'Copy: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local src_rng, tgt_rng = DRUMS_RANGE[src_dl], DRUMS_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    local src_notes  = ReadDrumsNotes(track, src_rng.lo, src_rng.lo + 4, sel_s, sel_e)
    local src_events = GroupDrumsHits(src_notes)

    if #src_notes == 0 then
        S.status      = ('Copy to %s: no notes on %s to copy.'):format(DIFF_NAMES[diff_label], DIFF_NAMES[src_dl])
        S.last_result = ('%s range (%d-%d) has no notes%s.'):format(
            DIFF_NAMES[src_dl], src_rng.lo, src_rng.hi, sel_s and ' in the current time selection' or '')
        return
    end

    local tgt_notes = ReadDrumsNotes(track, tgt_rng.lo, tgt_rng.lo + 4, sel_s, sel_e)
    if #tgt_notes > 0 and not force then
        S.diff_copy_pending = {
            message = ('%s range already has notes. Clear them and overwrite with a copy of %s?'):format(
                DIFF_NAMES[diff_label], DIFF_NAMES[src_dl]),
            on_confirm = function() CopyDrumsDiff(diff_label, true) end,
        }
        return
    end

    local item, take = FindFirstMIDIItem(track)
    if not item then
        S.status      = 'Error: PART DRUMS track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART DRUMS track first.'
        return
    end

    local clear_s = sel_s or 0
    local clear_e = sel_e or (r.GetMediaItemInfo_Value(item, 'D_POSITION') + r.GetMediaItemInfo_Value(item, 'D_LENGTH'))

    local target_max_offset = tgt_rng.hi - tgt_rng.lo
    local out_notes = {}
    for _, ev in ipairs(src_events) do
        local offsets = {}
        for _, p in ipairs(ev.pitches) do offsets[#offsets + 1] = p - src_rng.lo end
        local new_offsets = CompressChordOffsets(offsets, target_max_offset)
        for _, o in ipairs(new_offsets) do
            out_notes[#out_notes + 1] = { s = ev.s, e = ev.e, pitch = tgt_rng.lo + o }
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    ClearNotesInRange(take, clear_s, clear_e, tgt_rng.lo, tgt_rng.lo + 4)
    InsertNotes(take, out_notes, 100)
    r.Undo_EndBlock2(0, ('Copy Drums %s to %s'):format(src_dl, diff_label), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status      = ('Copy to %s: copied %d notes from %s.'):format(DIFF_NAMES[diff_label], #out_notes, DIFF_NAMES[src_dl])
    S.last_result = nil
end
