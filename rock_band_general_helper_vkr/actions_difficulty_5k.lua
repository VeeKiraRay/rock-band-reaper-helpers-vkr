-- Keys (5-Lane) difficulty validation and copy-to-next-tier tools
-- Requires: S, r, GetTimeSelection, GetTempoContextBefore, FormatTime, PitchName,
--           FindFirstMIDIItem, InsertNotes, ClearNotesInRange (globals)

-- Per-difficulty pitch ranges on PART KEYS
local K5_RANGE = {
    X = { lo = 96, hi = 100 },
    H = { lo = 84, hi = 88  },
    M = { lo = 72, hi = 75  },
    E = { lo = 60, hi = 62  },
}

-- Per-difficulty chord limits (max simultaneous notes at the same start time)
local K5_MAX_CHORD = { X = 5, H = 3, M = 2, E = 1 }

-- Per-difficulty minimum start-to-start spacing in beats (nil = no rule)
-- M: 1/4 note hard minimum; E: 1/4 note hard minimum + 1/2 note advisory
local K5_MIN_SP = { M = 1.0, E = 1.0 }   -- 1 beat = 1/4 note
local K5_ADV_SP = { E = 2.0 }             -- 2 beats = 1/2 note

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

local GEM_NAMES = { 'Green', 'Red', 'Yellow', 'Blue', 'Orange' }

-- Immediately-higher adjacent tier, for the cross-difficulty progression
-- check (CheckDifficultyProgression in actions_difficulty_shared.lua).
local ADJACENT_HIGHER = { H = 'X', M = 'H', E = 'M' }

-- Sum of individual notes across all chord events (not chord/event count).
local function CountNotes(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

-- Read non-muted notes in pitch range [lo, hi] from all MIDI items on track.
-- t_s / t_e: restrict to time selection (pass nil for full track).
-- Returns array sorted by start time: { s, e, pitch, vel }
local function ReadK5Notes(track, lo, hi, t_s, t_e)
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

-- Group notes with the same start time (within 2 ms) into chord events.
-- Returns array of events sorted by time: { s, e, pitches[] }
local function GroupK5Chords(notes)
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

-- Beat duration (seconds) at project time t.
local function GetK5BeatDur(t)
    local bpm = GetTempoContextBefore(t)
    if not bpm or bpm <= 0 then bpm = 120 end
    return 60.0 / bpm
end

-- Project time → quarter-note position, exact w.r.t. the tempo map.
-- Beat-fraction rules must be measured this way, not as seconds against a
-- single sampled BPM: with a fluctuating tempo map the seconds-length of a
-- 1/4 note changes inside the gap, so even grid-quantized notes drift a few ms.
local function QNAt(t) return r.TimeMap2_timeToQN(0, t) end

local GRACE  = 0.05  -- forgive gaps up to 5% under the requirement (hand-placed notes)
local EPS_QN = 0.01  -- epsilon for classification thresholds (~5 ms at 120 BPM)

-- Returns the gem lane color name for a pitch.
-- Uses offset from the nearest difficulty's lo, checking all 5 gem slots (0-4),
-- so OOR notes (e.g. Blue/Orange on Easy) still get a color name.
local function K5GemName(pitch)
    for _, rng in pairs(K5_RANGE) do
        local offset = pitch - rng.lo
        if offset >= 0 and offset <= 4 then
            return GEM_NAMES[offset + 1]
        end
    end
    return PitchName(pitch)
end

-- Format pitches for display using gem color names: single → "Green", chord → "[Green+Yellow]".
local function K5Label(pitches)
    if #pitches == 1 then return K5GemName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = K5GemName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

----------------------------------------------------------------------
-- Check functions - each returns an array of issue strings
----------------------------------------------------------------------

-- Chords exceeding max simultaneous notes for this difficulty.
local function CheckK5ChordCount(events, max_chord, diff_label)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches > max_chord then
            local limit_str = max_chord == 1 and 'no chords' or ('max ' .. max_chord)
            issues[#issues + 1] = ('%s: %s has %d notes (%s for %s)'):format(
                FormatTime(ev.s), K5Label(ev.pitches), #ev.pitches, limit_str, DIFF_NAMES[diff_label])
        end
    end
    return issues
end

-- Start-to-start spacing below minimum.
-- min_beats: hard minimum (beats). advisory_beats: softer advisory limit, or nil.
local function CheckK5Spacing(events, min_beats, advisory_beats)
    local issues = {}
    for i = 2, #events do
        local prev, curr = events[i-1], events[i]
        local qn_prev = QNAt(prev.s)
        local gap_qn  = QNAt(curr.s) - qn_prev
        local gap     = curr.s - prev.s
        if gap_qn < min_beats * (1 - GRACE) then
            local min_s = r.TimeMap2_QNToTime(0, qn_prev + min_beats) - prev.s
            local frac_str = min_beats == 1.0 and '1/4 note' or '1/2 note'
            issues[#issues + 1] = ('%s: %s is %.0f ms after previous (min %s = %.0f ms)'):format(
                FormatTime(curr.s), K5Label(curr.pitches), gap * 1000, frac_str, min_s * 1000)
        elseif advisory_beats and gap_qn < advisory_beats * (1 - GRACE) then
            local adv_s = r.TimeMap2_QNToTime(0, qn_prev + advisory_beats) - prev.s
            local adv_str = advisory_beats == 2.0 and '1/2 note' or '1/4 note'
            issues[#issues + 1] = ('%s: %s is %.0f ms after previous (advisory: %s = %.0f ms recommended for Easy)'):format(
                FormatTime(curr.s), K5Label(curr.pitches), gap * 1000, adv_str, adv_s * 1000)
        end
    end
    return issues
end

-- Notes shorter than 1/64 note.
local function CheckK5NoteLength(events)
    local issues = {}
    for _, ev in ipairs(events) do
        local qn_s   = QNAt(ev.s)
        local dur_qn = QNAt(ev.e) - qn_s
        if dur_qn < 0.0625 * (1 - GRACE) then  -- 1/64 note = 1/16 of a beat
            local dur   = ev.e - ev.s
            local min_s = r.TimeMap2_QNToTime(0, qn_s + 0.0625) - ev.s
            issues[#issues + 1] = ('%s: %s is %.1f ms long (min 1/64 note = %.1f ms)'):format(
                FormatTime(ev.s), K5Label(ev.pitches), dur * 1000, min_s * 1000)
        end
    end
    return issues
end

-- Gap between end of a sustained note and the next note start.
-- Only fires on notes at least 1/8 note long. Overlap is skipped (gap < 0).
-- M/E: 1/4 note gap required for all notes. X/H: 1/16 note (single) or 1/8 note (chord).
local function CheckK5SustainGaps(events, diff_label)
    local issues = {}
    for i = 1, #events - 1 do
        local ev      = events[i]
        local next_ev = events[i + 1]
        local qn_e    = QNAt(ev.e)
        local dur_qn  = qn_e - QNAt(ev.s)

        if dur_qn < 0.5 - EPS_QN then goto k5sg_next end  -- not sustained (< 1/8 note)

        local gap_qn = QNAt(next_ev.s) - qn_e
        if gap_qn < 0 then goto k5sg_next end  -- overlap; handled elsewhere

        local min_qn, min_label
        if diff_label == 'M' or diff_label == 'E' then
            min_qn, min_label = 1.0,  '1/4 note'
        elseif #ev.pitches > 1 then
            min_qn, min_label = 0.5,  '1/8 note'
        else
            min_qn, min_label = 0.25, '1/16 note'
        end

        if gap_qn < min_qn * (1 - GRACE) then
            local gap   = next_ev.s - ev.e
            local min_s = r.TimeMap2_QNToTime(0, qn_e + min_qn) - ev.e
            issues[#issues + 1] = ('%s: %s ends %.0f ms before %s (need %s gap = %.0f ms)'):format(
                FormatTime(next_ev.s), K5Label(ev.pitches), gap * 1000,
                K5Label(next_ev.pitches), min_label, min_s * 1000)
        end

        ::k5sg_next::
    end
    return issues
end

-- Expert/Hard: notes in the gray zone [1/8, 3/16) at >= 100 BPM are too long to be a hit
-- but too short for a valid sustain display. Flag them to extend or shorten.
local function CheckK5SustainLength(events)
    local issues = {}
    for _, ev in ipairs(events) do
        local bpm = 60.0 / GetK5BeatDur(ev.s)
        if bpm < 100 then goto k5sl_next end
        local qn_s   = QNAt(ev.s)
        local dur_qn = QNAt(ev.e) - qn_s
        -- Gray zone: >= 1/8 note (too long for a hit) but < 3/16 note (too short to sustain)
        if dur_qn >= 0.5 - EPS_QN and dur_qn < 0.75 * (1 - GRACE) then
            local dur   = ev.e - ev.s
            local min_s = r.TimeMap2_QNToTime(0, qn_s + 0.75) - ev.s
            issues[#issues + 1] = ('%s: %s is %.0f ms (need >= 3/16 note = %.0f ms at %.0f BPM, or shorten to hit)'):format(
                FormatTime(ev.s), K5Label(ev.pitches), dur * 1000, min_s * 1000, bpm)
        end
        ::k5sl_next::
    end
    return issues
end

-- Notes with pitches above the valid hi for this difficulty (authoring error).
-- rng_hi: K5_RANGE[diff].hi - the highest valid pitch for the diff being validated.
local function CheckK5OutOfRange(events, rng_hi)
    local issues = {}
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            if p > rng_hi then
                issues[#issues + 1] = ('%s: %s (pitch %d) is outside the valid range for this difficulty'):format(
                    FormatTime(ev.s), K5GemName(p), p)
            end
        end
    end
    return issues
end

----------------------------------------------------------------------
-- Report builder and validation runner
----------------------------------------------------------------------

local function BuildK5Report(header, cats)
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

local function RunK5Checks(diff_label, events, header, rng_hi)
    local max_ch = K5_MAX_CHORD[diff_label]
    local min_sp = K5_MIN_SP[diff_label]
    local cats   = {}

    cats[#cats + 1] = { name = 'Notes outside valid range', issues = CheckK5OutOfRange(events, rng_hi) }

    local chord_name
    if diff_label == 'E' then
        chord_name = 'Chords (none allowed on Easy)'
    else
        chord_name = ('Max chord (%d notes)'):format(max_ch)
    end
    cats[#cats + 1] = { name = chord_name, issues = CheckK5ChordCount(events, max_ch, diff_label) }

    if min_sp then
        local adv = K5_ADV_SP[diff_label]
        local sp_name = diff_label == 'E'
            and 'Note spacing (min 1/4 note, advisory 1/2 note)'
            or  'Note spacing (min 1/4 note)'
        cats[#cats + 1] = { name = sp_name, issues = CheckK5Spacing(events, min_sp, adv) }
    end

    cats[#cats + 1] = { name = 'Note length (min 1/64)', issues = CheckK5NoteLength(events) }

    if diff_label == 'X' or diff_label == 'H' then
        cats[#cats + 1] = { name = 'Sustain length (min 3/16 at >=100 BPM)', issues = CheckK5SustainLength(events) }
    end

    local sg_name = (diff_label == 'M' or diff_label == 'E')
        and 'Sustain gaps (min 1/4 note gap to next)'
        or  'Sustain gaps (min 1/16 single / 1/8 chord)'
    cats[#cats + 1] = { name = sg_name, issues = CheckK5SustainGaps(events, diff_label) }

    return BuildK5Report(header, cats)
end

----------------------------------------------------------------------
-- Global action functions
----------------------------------------------------------------------

-- Validate notes in the diff_label pitch range on PART KEYS.
-- diff_label: 'X', 'H', 'M', or 'E'
function ValidateKeys5Diff(diff_label)
    if S.diff_5k_idx < 0 then
        S.status      = 'Error: PART KEYS track not selected.'
        S.last_result = 'Select the PART KEYS track in the Difficulty \xe2\x86\x92 5-Lane Keys tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_5k_idx)
    if not track then
        S.status      = 'Error: PART KEYS track no longer exists \xe2\x80\x94 refresh tracks.'
        S.last_result = nil
        return
    end

    local rng          = K5_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    -- Read up to lo+4 (all 5 gem slots) so OOR notes are included and flagged.
    local notes        = ReadK5Notes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
    local events       = GroupK5Chords(notes)

    if #notes == 0 then
        S.status = ('Validate 5-Key %s: no notes in %s\xe2\x80\x93%s (%d\xe2\x80\x93%d).'):format(
            diff_label, PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi)
        S.last_result = sel_s
            and ('No %s notes (%s\xe2\x80\x93%s) in the current time selection.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
            or  ('No %s notes (%s\xe2\x80\x93%s) on PART KEYS track.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
        return
    end

    local scope  = sel_s and ' [time selection]' or ''
    local header = ('5-Lane Keys %s Validation  [%s\xe2\x80\x93%s, %d\xe2\x80\x93%d]%s'):format(
        DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi, scope)
    local report, total = RunK5Checks(diff_label, events, header, rng.hi)

    -- Cross-difficulty progression check (vs the immediately higher tier).
    local higher_dl = ADJACENT_HIGHER[diff_label]
    if higher_dl then
        local higher_rng    = K5_RANGE[higher_dl]
        local higher_notes  = ReadK5Notes(track, higher_rng.lo, higher_rng.lo + 4, sel_s, sel_e)
        local higher_events = GroupK5Chords(higher_notes)
        local block, extra = CheckDifficultyProgression(
            DIFF_NAMES[diff_label], DIFF_NAMES[higher_dl],
            events, higher_events, rng.lo, higher_rng.lo,
            CountNotes(events), CountNotes(higher_events))
        report = block .. report
        total  = total + extra
    end

    if total == 0 then
        S.status = ('Validate 5-Key %s: all checks passed%s.'):format(diff_label, scope)
    else
        S.status = ('Validate 5-Key %s: %d issue%s found%s.'):format(
            diff_label, total, total == 1 and '' or 's', scope)
    end
    S.last_result = report
end

-- Validate all four difficulty ranges on PART KEYS in a combined report.
function ValidateAllKeys5()
    if S.diff_5k_idx < 0 then
        S.status      = 'Error: PART KEYS track not selected.'
        S.last_result = 'Select the PART KEYS track in the Difficulty \xe2\x86\x92 5-Lane Keys tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_5k_idx)
    if not track then
        S.status      = 'Error: PART KEYS track no longer exists \xe2\x80\x94 refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local scope        = sel_s and ' [time selection]' or ''
    local diff_order   = { 'X', 'H', 'M', 'E' }
    local all_lines    = { ('5-Lane Keys Validate All%s'):format(scope), '' }
    local summary      = {}

    -- Carried forward from the previous (higher) tier for the cross-difficulty
    -- progression check - avoids re-reading a range already read this loop.
    local prev_dl, prev_events, prev_count = nil, {}, 0

    for _, dl in ipairs(diff_order) do
        local rng    = K5_RANGE[dl]
        local notes  = ReadK5Notes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
        local events = GroupK5Chords(notes)

        if #notes == 0 then
            summary[#summary + 1] = dl .. ':empty'
            all_lines[#all_lines + 1] = ('=== %s ===  (no notes in range %d\xe2\x80\x93%d)'):format(
                DIFF_NAMES[dl], rng.lo, rng.hi)
            all_lines[#all_lines + 1] = ''
            prev_dl, prev_events, prev_count = dl, {}, 0
        else
            local header        = ('=== 5-Lane Keys %s  [%d\xe2\x80\x93%d] ==='):format(DIFF_NAMES[dl], rng.lo, rng.hi)
            local report, total = RunK5Checks(dl, events, header, rng.hi)

            if dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] then
                local block, extra = CheckDifficultyProgression(
                    DIFF_NAMES[dl], DIFF_NAMES[prev_dl],
                    events, prev_events, rng.lo, K5_RANGE[prev_dl].lo,
                    CountNotes(events), prev_count)
                report = block .. report
                total  = total + extra
            end

            summary[#summary + 1] = total == 0 and (dl .. ':OK') or ('%s:%d'):format(dl, total)
            for line in (report .. '\n'):gmatch('([^\n]*)\n') do
                all_lines[#all_lines + 1] = line
            end
            prev_dl, prev_events, prev_count = dl, events, CountNotes(events)
        end
    end

    S.status      = ('Validate All 5-Lane Keys%s: %s'):format(scope, table.concat(summary, ' | '))
    S.last_result = table.concat(all_lines, '\n')
end

-- Copy notes from the immediately higher tier's range onto diff_label's own
-- range on PART KEYS. Colors above the target tier's ceiling are compressed
-- down via CompressChordOffsets (actions_difficulty_shared.lua) rather than
-- dropped outright or left out-of-range.
-- force: skip the "target already has notes" confirmation and overwrite
-- directly (set true when called again from the confirm popup).
function CopyKeys5Diff(diff_label, force)
    if S.diff_5k_idx < 0 then
        S.status      = 'Error: PART KEYS track not selected.'
        S.last_result = 'Select the PART KEYS track in the Difficulty \xe2\x86\x92 Keys tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_5k_idx)
    if not track then
        S.status      = 'Error: PART KEYS track no longer exists \xe2\x80\x94 refresh tracks.'
        S.last_result = nil
        return
    end

    local src_dl = ADJACENT_HIGHER[diff_label]
    if not src_dl then
        S.status = 'Copy: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local src_rng, tgt_rng = K5_RANGE[src_dl], K5_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    local src_notes  = ReadK5Notes(track, src_rng.lo, src_rng.lo + 4, sel_s, sel_e)
    local src_events = GroupK5Chords(src_notes)

    if #src_notes == 0 then
        S.status      = ('Copy to %s: no notes on %s to copy.'):format(DIFF_NAMES[diff_label], DIFF_NAMES[src_dl])
        S.last_result = ('%s range (%d\xe2\x80\x93%d) has no notes%s.'):format(
            DIFF_NAMES[src_dl], src_rng.lo, src_rng.hi, sel_s and ' in the current time selection' or '')
        return
    end

    local tgt_notes = ReadK5Notes(track, tgt_rng.lo, tgt_rng.lo + 4, sel_s, sel_e)
    if #tgt_notes > 0 and not force then
        S.diff_copy_pending = {
            message = ('%s range already has notes. Clear them and overwrite with a copy of %s?'):format(
                DIFF_NAMES[diff_label], DIFF_NAMES[src_dl]),
            on_confirm = function() CopyKeys5Diff(diff_label, true) end,
        }
        return
    end

    local item, take = FindFirstMIDIItem(track)
    if not item then
        S.status      = 'Error: PART KEYS track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART KEYS track first.'
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
    r.Undo_EndBlock2(0, ('Copy Keys %s to %s'):format(src_dl, diff_label), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status      = ('Copy to %s: copied %d notes from %s.'):format(DIFF_NAMES[diff_label], #out_notes, DIFF_NAMES[src_dl])
    S.last_result = nil
end
