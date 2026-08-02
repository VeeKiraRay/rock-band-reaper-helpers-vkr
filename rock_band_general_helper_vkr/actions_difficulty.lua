-- Pro Keys difficulty validation and copy-to-next-tier tools
-- Requires: S, r, GetTimeSelection, GetTempoContextBefore, FormatTime, PitchName,
--           FindFirstMIDIItem, InsertNotes, ClearNotesInRange (globals)

local PK_MIN = 48  -- C2 (Rock Band convention) = MIDI 48
local PK_MAX = 72  -- C4 (Rock Band convention) = MIDI 72

-- Pitches used as lane range markers (not playable notes)
local PK_LANE_SHIFT_PITCHES = { [0]=true,[2]=true,[4]=true,[5]=true,[7]=true,[9]=true }

-- Per-difficulty rule limits
local PK_MAX_CHORD = { X=4, H=3, M=2, E=1 }
local PK_MAX_SPAN  = { X=12, H=11, M=9 }  -- E has no chords so no span limit
local PK_MAX_JUMP  = { H=11, M=9, E=7 }   -- X has no jump restriction
local PK_MIN_SP    = { M=1.0, E=2.0 }     -- min spacing in beats: 1.0=1/4 note, 2.0=1/2 note
local PK_ALLOW_SH  = { X=true, H=true, M=false, E=false }  -- allow mid-song lane shifts

-- Three primary range positions (easiest to read in-game): C range, F range, A range.
-- Non-primary positions (D=2, E=4, G=7) are technically valid but harder to read.
local PK_PREFERRED_SHIFTS = { [0]=true, [5]=true, [9]=true }
local PK_RANGE_NAMES = {
    [0]='C range (C2-E3)',  [2]='D range (D2-F#3)',
    [4]='E range (E2-G#3)', [5]='F range (F2-A3)',
    [7]='G range (G2-B3)',  [9]='A range (A2-C4)',
}

local DIFF_NAMES = { X='Expert', H='Hard', M='Medium', E='Easy' }

-- Immediately-higher adjacent tier, for the cross-difficulty progression
-- check (CheckDifficultyProgression in actions_difficulty_shared.lua).
local ADJACENT_HIGHER = { H='X', M='H', E='M' }

-- Sum of individual notes across all chord events (not chord/event count).
local function CountNotes(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

local function EventLabel(pitches)
    if #pitches == 1 then return PitchName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = PitchName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

-- Read all non-muted notes from all MIDI items on track within [t_s, t_e].
-- Pass nil for t_s/t_e to read entire track.
-- Returns array sorted by start time: { s, e, pitch, vel }
local function ReadPKNotes(track, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted then
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

-- Split notes into lane-shift markers and playable events.
-- Playable events group notes within 2ms of each other into chords.
-- Returns: lane_shifts[], events[]
-- Each event: { s, e, pitches[] } sorted by time; pitches sorted low-to-high.
local function GroupIntoEvents(notes)
    local lane_shifts = {}
    local playable    = {}
    for _, n in ipairs(notes) do
        if PK_LANE_SHIFT_PITCHES[n.pitch] then
            lane_shifts[#lane_shifts + 1] = n
        elseif n.pitch >= PK_MIN and n.pitch <= PK_MAX then
            playable[#playable + 1] = n
        end
        -- Anything else (overdrive 116, glissando 126, trill 127, or other stray
        -- pitches) is not a playable Pro Keys note - excluded from chord/span/
        -- jump/spacing/overlap checks so it can't produce false positives there.
    end

    local events = {}
    local i = 1
    while i <= #playable do
        local ev = { s = playable[i].s, e = playable[i].e, pitches = { playable[i].pitch } }
        local j = i + 1
        while j <= #playable and playable[j].s - ev.s <= 0.002 do
            ev.pitches[#ev.pitches + 1] = playable[j].pitch
            if playable[j].e > ev.e then ev.e = playable[j].e end
            j = j + 1
        end
        table.sort(ev.pitches)
        events[#events + 1] = ev
        i = j
    end
    return lane_shifts, events
end

-- Beat duration (seconds) at project time t, using the project tempo map.
local function GetBeatDurAt(t)
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

-- 1-based measure number at project time t.
local function GetMeasureAt(t)
    local s = r.format_timestr_pos(t, '', 1)  -- "M.B.HH" e.g. "5.1.00"
    return tonumber(s:match('^%s*(%d+)'))
end

-- Returns "→ suggest X" or "→ suggest [X+Y] or [A+B]" for a chord that needs reducing.
-- Tries to find max_notes notes within max_span semitones; falls back to single-note.
-- Shows two options when "keep highest" and "keep lowest" produce different results.
local function SuggestChordReduction(pitches, max_notes, max_span)
    if max_notes <= 1 or #pitches <= 1 then
        local h = PitchName(pitches[#pitches])
        local l = PitchName(pitches[1])
        if h == l then
            return '\xe2\x86\x92 suggest ' .. h
        end
        return '\xe2\x86\x92 suggest ' .. h .. ' (highest) or ' .. l .. ' (lowest)'
    end

    local keep_high, keep_low
    for i = 1, #pitches - 1 do
        for j = i + 1, #pitches do
            local span = pitches[j] - pitches[i]
            if not max_span or span <= max_span then
                if pitches[j] == pitches[#pitches] and not keep_high then
                    keep_high = { pitches[i], pitches[j] }
                end
                if pitches[i] == pitches[1] and not keep_low then
                    keep_low = { pitches[i], pitches[j] }
                end
            end
        end
    end

    if not keep_high and not keep_low then
        local h = PitchName(pitches[#pitches])
        local l = PitchName(pitches[1])
        if h == l then return '\xe2\x86\x92 suggest ' .. h end
        return '\xe2\x86\x92 suggest ' .. h .. ' (highest) or ' .. l .. ' (lowest)'
    end

    local opts = {}
    if keep_high then opts[#opts + 1] = EventLabel(keep_high) end
    if keep_low then
        local same = keep_high
            and keep_high[1] == keep_low[1]
            and keep_high[2] == keep_low[2]
        if not same then opts[#opts + 1] = EventLabel(keep_low) end
    end
    return '\xe2\x86\x92 suggest ' .. table.concat(opts, ' or ')
end

-- Returns a hint for fixing an interval jump violation.
-- Single-note events: picks the best direction using two priority rules:
--   1. Change the note that appears fewer times in the chart (fewer edits overall).
--   2. Tie-break: prefer the fix whose target pitch has fewer existing occurrences
--      (avoids creating a long run of the same note).
--   3. Still tied: show both options.
-- Chord events: shows semitone overshoot only.
-- pitch_freq: table mapping MIDI pitch → occurrence count across all events.
local function SuggestJumpFix(prev_pitches, curr_pitches, min_int, max_jump, pitch_freq)
    local overshoot = min_int - max_jump
    if #prev_pitches == 1 and #curr_pitches == 1 then
        local pa, pb = prev_pitches[1], curr_pitches[1]
        local fix_prev, fix_curr
        if pb > pa then
            fix_curr = pb - overshoot
            fix_prev = pa + overshoot
        else
            fix_curr = pb + overshoot
            fix_prev = pa - overshoot
        end

        local cnt_pa = pitch_freq[pa] or 0
        local cnt_pb = pitch_freq[pb] or 0
        local want_prev = cnt_pa <= cnt_pb
        local want_curr = cnt_pb <= cnt_pa

        if want_prev and want_curr then
            local after_prev = (pitch_freq[fix_prev] or 0) + 1
            local after_curr = (pitch_freq[fix_curr] or 0) + 1
            if after_prev < after_curr then
                want_curr = false
            elseif after_curr < after_prev then
                want_prev = false
            end
        end

        local function verb(orig, tgt) return tgt > orig and 'raise' or 'lower' end
        if want_prev and not want_curr then
            return ('\xe2\x86\x92 %s %s to %s'):format(verb(pa, fix_prev), PitchName(pa), PitchName(fix_prev))
        elseif want_curr and not want_prev then
            return ('\xe2\x86\x92 %s %s to %s'):format(verb(pb, fix_curr), PitchName(pb), PitchName(fix_curr))
        else
            return ('\xe2\x86\x92 %s %s to %s, or %s %s to %s'):format(
                verb(pb, fix_curr), PitchName(pb), PitchName(fix_curr),
                verb(pa, fix_prev), PitchName(pa), PitchName(fix_prev))
        end
    end
    return ('\xe2\x86\x92 bring events %d semitone%s closer'):format(overshoot, overshoot == 1 and '' or 's')
end

----------------------------------------------------------------------
-- Check functions - each returns an array of issue strings
----------------------------------------------------------------------

local function CheckChordCount(events, max_notes, max_span)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches > max_notes then
            local limit_str = max_notes == 1 and 'single notes only' or ('max ' .. max_notes)
            local hint = SuggestChordReduction(ev.pitches, max_notes, max_span)
            issues[#issues + 1] = ('%s: %s has %d notes (%s) %s'):format(
                FormatTime(ev.s), EventLabel(ev.pitches), #ev.pitches, limit_str, hint)
        end
    end
    return issues
end

local function CheckChordSpan(events, max_span)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches > 1 then
            local span = ev.pitches[#ev.pitches] - ev.pitches[1]
            if span > max_span then
                local hint = SuggestChordReduction(ev.pitches, #ev.pitches - 1, max_span)
                issues[#issues + 1] = ('%s: %s spans %d semitones (max %d) %s'):format(
                    FormatTime(ev.s), EventLabel(ev.pitches), span, max_span, hint)
            end
        end
    end
    return issues
end

-- Jump = minimum abs interval between any note in event A and any note in event B.
local function CheckIntervalJumps(events, max_jump)
    local pitch_freq = {}
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            pitch_freq[p] = (pitch_freq[p] or 0) + 1
        end
    end

    local issues = {}
    for i = 2, #events do
        local prev, curr = events[i-1], events[i]
        local min_int = math.huge
        for _, pa in ipairs(prev.pitches) do
            for _, pb in ipairs(curr.pitches) do
                local d = math.abs(pb - pa)
                if d < min_int then min_int = d end
            end
        end
        if min_int > max_jump then
            local hint = SuggestJumpFix(prev.pitches, curr.pitches, min_int, max_jump, pitch_freq)
            issues[#issues + 1] = ('%s: jump of %d semitones from %s to %s (max %d) %s'):format(
                FormatTime(curr.s), min_int,
                EventLabel(prev.pitches), EventLabel(curr.pitches), max_jump, hint)
        end
    end
    return issues
end

-- Spacing check: start-to-start gap between consecutive events must be >= min_beat_frac beats.
local function CheckSpacing(events, min_beat_frac)
    local issues = {}
    for i = 2, #events do
        local prev, curr = events[i-1], events[i]
        local qn_prev = QNAt(prev.s)
        local gap_qn  = QNAt(curr.s) - qn_prev
        if gap_qn < min_beat_frac * (1 - GRACE) then
            local gap   = curr.s - prev.s
            local min_s = r.TimeMap2_QNToTime(0, qn_prev + min_beat_frac) - prev.s
            local frac_str = min_beat_frac == 1.0 and '1/4 note' or '1/2 note'
            issues[#issues + 1] = ('%s: %s is %.0f ms after previous note (min %s = %.0f ms)'):format(
                FormatTime(curr.s), EventLabel(curr.pitches),
                gap * 1000, frac_str, min_s * 1000)
        end
    end
    return issues
end

-- Lane range marker checks.
-- allow_extra = false on M/E (no mid-song shifts allowed).
-- sel_s: when a time selection is active, skip the "initial marker required" check
--   because the initial marker may precede the selection.
local function CheckLaneShifts(lane_shifts, events, allow_extra, sel_s)
    local issues = {}
    local first_note_t = events[1] and events[1].s or nil

    if not sel_s then
        local has_initial = false
        for _, ls in ipairs(lane_shifts) do
            if not first_note_t or ls.s <= first_note_t + 0.001 then
                has_initial = true; break
            end
        end
        if not has_initial and first_note_t then
            issues[#issues + 1] = 'No initial range marker before first note (required on all difficulties)'
        end
    end

    if not allow_extra and first_note_t then
        for _, ls in ipairs(lane_shifts) do
            if ls.s > first_note_t + 0.001 then
                issues[#issues + 1] = ('%s: lane range shift not allowed on Medium or Easy'):format(
                    FormatTime(ls.s))
            end
        end
    end

    return issues
end

-- Advisory: flag lane shift markers that are not one of the three primary ranges.
-- Primary: C (pitch 0, C2-E3), F (pitch 5, F2-A3), A (pitch 9, A2-C4).
local function CheckPreferredRanges(lane_shifts)
    local issues = {}
    for _, ls in ipairs(lane_shifts) do
        if not PK_PREFERRED_SHIFTS[ls.pitch] then
            local rname = PK_RANGE_NAMES[ls.pitch] or ('pitch ' .. ls.pitch)
            issues[#issues + 1] = ('%s: %s - prefer C range (C2-E3), F range (F2-A3), or A range (A2-C4)'):format(
                FormatTime(ls.s), rname)
        end
    end
    return issues
end

-- Check for notes that start while earlier notes are still playing (broken chords / arpeggios).
-- X: max 4 simultaneously active; H: max 3. M: none unless ≥ quarter note apart. E: none.
-- Also flags overlapping span > octave (12 semitones) for X/H.
local function CheckOverlappingGems(events, diff_label)
    local max_ov = { X=4, H=3 }
    local issues = {}

    for i = 2, #events do
        local curr = events[i]

        -- Collect pitches from all events that started earlier but are still sounding at curr.s
        local active_pitches = {}
        for j = 1, i - 1 do
            local prev = events[j]
            if prev.e > curr.s + 0.002 then
                for _, p in ipairs(prev.pitches) do
                    active_pitches[#active_pitches + 1] = p
                end
            end
        end

        if #active_pitches == 0 then goto ov_next end

        -- Medium exception: OK when the overlapping event started ≥ quarter note ago
        if diff_label == 'M' then
            local last_start = 0
            for j = 1, i - 1 do
                local prev = events[j]
                if prev.e > curr.s + 0.002 and prev.s > last_start then
                    last_start = prev.s
                end
            end
            if QNAt(curr.s) - QNAt(last_start) >= 1.0 - EPS_QN then goto ov_next end
        end

        do
            table.sort(active_pitches)
            local all_p = {}
            for _, p in ipairs(active_pitches) do all_p[#all_p + 1] = p end
            for _, p in ipairs(curr.pitches)   do all_p[#all_p + 1] = p end
            table.sort(all_p)
            local span  = all_p[#all_p] - all_p[1]
            local count = #all_p

            if diff_label == 'E' then
                issues[#issues + 1] = ('%s: %s starts while %s still playing (no overlapping on Easy)'):format(
                    FormatTime(curr.s), EventLabel(curr.pitches), EventLabel(active_pitches))
            elseif diff_label == 'M' then
                issues[#issues + 1] = ('%s: %s overlaps previous note (no overlapping on Medium unless \xe2\x89\xa5 quarter note apart)'):format(
                    FormatTime(curr.s), EventLabel(curr.pitches))
            elseif count > max_ov[diff_label] then
                issues[#issues + 1] = ('%s: %d notes active simultaneously (max %d overlapping for %s)'):format(
                    FormatTime(curr.s), count, max_ov[diff_label], DIFF_NAMES[diff_label])
            end

            -- Span check: applies to X/H (for M/E the overlap itself is already flagged)
            if (diff_label == 'X' or diff_label == 'H') and span > 12 then
                issues[#issues + 1] = ('%s: overlapping notes span %d semitones (max 12 = octave)'):format(
                    FormatTime(curr.s), span)
            end
        end

        ::ov_next::
    end
    return issues
end

-- Check gap between the end of a sustained note and the start of the next note.
-- Only fires on notes longer than 1/8 note. Gaps from overlapping notes are skipped
-- (those are reported by CheckOverlappingGems instead).
-- Expert/Hard: 16th note for simple transitions; 8th note for complex.
--   Simple = single→single, or one side is single and its pitch is in the chord.
--   chord→chord is ALWAYS complex regardless of shared notes (different voicing = different transition).
-- Medium/Easy: quarter note always.
local function CheckSustainGaps(events, diff_label)
    local issues = {}

    for i = 1, #events - 1 do
        local ev      = events[i]
        local next_ev = events[i + 1]
        local qn_e    = QNAt(ev.e)
        local dur_qn  = qn_e - QNAt(ev.s)

        if dur_qn < 0.5 - EPS_QN then goto sg_next end  -- not sustained (< 1/8 note)

        local gap_qn = QNAt(next_ev.s) - qn_e
        if gap_qn < 0 then goto sg_next end  -- overlap: handled by CheckOverlappingGems

        local is_chord   = #ev.pitches > 1
        local next_chord = #next_ev.pitches > 1

        -- "Simple": single→single, single↔chord where the single note is inside the chord,
        -- or chord→same chord (re-articulation, not a harmonic transition).
        -- chord→different chord is always complex even when some pitches are shared.
        -- Pitches are sorted by GroupIntoEvents so index comparison is valid.
        local simple = false
        if not is_chord and not next_chord then
            simple = true
        elseif not is_chord and next_chord then
            for _, q in ipairs(next_ev.pitches) do
                if q == ev.pitches[1] then simple = true; break end
            end
        elseif is_chord and not next_chord then
            for _, p in ipairs(ev.pitches) do
                if p == next_ev.pitches[1] then simple = true; break end
            end
        elseif #ev.pitches == #next_ev.pitches then
            simple = true
            for k = 1, #ev.pitches do
                if ev.pitches[k] ~= next_ev.pitches[k] then simple = false; break end
            end
        end  -- chord→different chord: simple stays false

        local min_qn, min_label, ttype
        if diff_label == 'M' or diff_label == 'E' then
            min_qn, min_label, ttype = 1.0, '1/4 note', ''
        elseif simple then
            min_qn, min_label, ttype = 0.25, '1/16 note', 'simple transition: '
        elseif is_chord and next_chord then
            min_qn, min_label, ttype = 0.5, '1/8 note', 'chord \xe2\x86\x92 chord: '
        elseif is_chord then
            min_qn, min_label, ttype = 0.5, '1/8 note', 'chord \xe2\x86\x92 unrelated note: '
        else
            min_qn, min_label, ttype = 0.5, '1/8 note', 'note \xe2\x86\x92 unrelated chord: '
        end

        if gap_qn < min_qn * (1 - GRACE) then
            local gap   = next_ev.s - ev.e
            local min_s = r.TimeMap2_QNToTime(0, qn_e + min_qn) - ev.e
            issues[#issues + 1] = ('%s: %s ends %.0f ms before %s (%sneed %s gap = %.0f ms)'):format(
                FormatTime(next_ev.s), EventLabel(ev.pitches), gap * 1000,
                EventLabel(next_ev.pitches), ttype, min_label, min_s * 1000)
        end

        ::sg_next::
    end
    return issues
end

-- For each measure where Expert has notes, check that the lower diff also has notes.
-- Groups consecutive missing measures into ranges: "Measures 5-10 have Expert notes but none here."
local function CheckMissingMeasures(exp_events, lower_events)
    local exp_meas, low_meas = {}, {}
    for _, ev in ipairs(exp_events) do
        local m = GetMeasureAt(ev.s)
        if m then exp_meas[m] = true end
    end
    for _, ev in ipairs(lower_events) do
        local m = GetMeasureAt(ev.s)
        if m then low_meas[m] = true end
    end

    local missing = {}
    for m in pairs(exp_meas) do
        if not low_meas[m] then missing[#missing + 1] = m end
    end
    if #missing == 0 then return {} end
    table.sort(missing)

    local issues = {}
    local i = 1
    while i <= #missing do
        local s_m, e_m = missing[i], missing[i]
        while i + 1 <= #missing and missing[i + 1] == e_m + 1 do
            i = i + 1; e_m = missing[i]
        end
        if s_m == e_m then
            issues[#issues + 1] = ('Measure %d has Expert notes but none here'):format(s_m)
        else
            issues[#issues + 1] = ('Measures %d-%d have Expert notes but none here'):format(s_m, e_m)
        end
        i = i + 1
    end
    return issues
end

-- Check whether any lower-diff note has no Expert counterpart within 1/8 note.
local function CheckNotesAboveExpert(exp_events, lower_events)
    local issues = {}
    for _, ev in ipairs(lower_events) do
        local tolerance = GetBeatDurAt(ev.s) * 0.5  -- 1/8 note
        local nearest_ev, nearest_dt = nil, math.huge
        for _, xev in ipairs(exp_events) do
            local dt = math.abs(xev.s - ev.s)
            if dt < nearest_dt then nearest_dt = dt; nearest_ev = xev end
        end
        if not nearest_ev or nearest_dt > tolerance then
            issues[#issues + 1] = ('%s: %s has no Expert note within 1/8 note'):format(
                FormatTime(ev.s), EventLabel(ev.pitches))
        elseif #ev.pitches > #nearest_ev.pitches then
            issues[#issues + 1] = ('%s: %s has more notes than nearest Expert chord %s'):format(
                FormatTime(ev.s), EventLabel(ev.pitches), EventLabel(nearest_ev.pitches))
        end
    end
    return issues
end

----------------------------------------------------------------------
-- Report builder
----------------------------------------------------------------------

-- Returns (report_text, total_issue_count)
local function BuildReport(header, categories)
    local lines  = { header, '' }
    local total  = 0
    for _, cat in ipairs(categories) do
        local n = #cat.issues
        total   = total + n
        if n == 0 then
            lines[#lines + 1] = cat.name .. ':  OK'
        else
            lines[#lines + 1] = ('%s:  %d issue%s'):format(cat.name, n, n == 1 and '' or 's')
            for _, issue in ipairs(cat.issues) do
                lines[#lines + 1] = '  \xe2\x80\xa2 ' .. issue
            end
        end
        lines[#lines + 1] = ''
    end
    return table.concat(lines, '\n'), total
end

----------------------------------------------------------------------
-- Shared validation kernel - used by both Suggest and Validate
----------------------------------------------------------------------

-- Run all rule checks for diff_label against events/lane_shifts.
-- exp_events: Expert events for cross-diff check (nil = skip that check).
-- sel_s: time selection start, or nil (controls lane-shift initial-marker check).
-- header: first line of the report.
-- Returns (report_text, total_issue_count)
local function RunPKValidation(diff_label, events, lane_shifts, exp_events, sel_s, header)
    local cats = {}

    local clabel = diff_label == 'E' and 'Chord count (single notes only)'
                or ('Chord count (max ' .. PK_MAX_CHORD[diff_label] .. ')')
    cats[#cats + 1] = { name = clabel, issues = CheckChordCount(events, PK_MAX_CHORD[diff_label], PK_MAX_SPAN[diff_label]) }

    if PK_MAX_SPAN[diff_label] then
        cats[#cats + 1] = {
            name    = ('Chord span (max %d semitones)'):format(PK_MAX_SPAN[diff_label]),
            issues  = CheckChordSpan(events, PK_MAX_SPAN[diff_label]),
        }
    end

    if PK_MAX_JUMP[diff_label] then
        cats[#cats + 1] = {
            name    = ('Interval jumps (max %d semitones)'):format(PK_MAX_JUMP[diff_label]),
            issues  = CheckIntervalJumps(events, PK_MAX_JUMP[diff_label]),
        }
    end

    if PK_MIN_SP[diff_label] then
        local slabel = PK_MIN_SP[diff_label] == 1.0
            and 'Note spacing (min 1/4 note start-to-start)'
            or  'Note spacing (min 1/2 note start-to-start)'
        cats[#cats + 1] = { name = slabel, issues = CheckSpacing(events, PK_MIN_SP[diff_label]) }
    end

    cats[#cats + 1] = {
        name   = 'Lane range markers',
        issues = CheckLaneShifts(lane_shifts, events, PK_ALLOW_SH[diff_label], sel_s),
    }

    -- Advisory: preferred ranges (C/F/A) only relevant when lane shifts are allowed
    if PK_ALLOW_SH[diff_label] and #lane_shifts > 0 then
        cats[#cats + 1] = {
            name   = 'Lane shift ranges (prefer C, F, A)',
            issues = CheckPreferredRanges(lane_shifts),
        }
    end

    cats[#cats + 1] = { name = 'Overlapping gems', issues = CheckOverlappingGems(events, diff_label) }
    cats[#cats + 1] = { name = 'Sustain gaps',     issues = CheckSustainGaps(events, diff_label) }

    if diff_label ~= 'X' and exp_events and #exp_events > 0 then
        cats[#cats + 1] = { name = 'Notes not in Expert', issues = CheckNotesAboveExpert(exp_events, events) }
        cats[#cats + 1] = { name = 'Missing measures',    issues = CheckMissingMeasures(exp_events, events) }
    end

    return BuildReport(header, cats)
end

----------------------------------------------------------------------
-- Global action functions
----------------------------------------------------------------------

-- Copy notes from the immediately higher Pro Keys tier onto diff_label's own
-- track. A literal duplicate - Pro Keys' playable range (C2-C4) doesn't
-- shift between tiers, so no pitch transform is needed - and copies
-- everything (playable gems AND lane-shift markers), since the markers are
-- essential for the track to make sense, not an optional overlay.
-- force: skip the "target already has notes" confirmation and overwrite
-- directly (set true when called again from the confirm popup).
function CopyProKeysDiff(diff_label, force)
    local idx_fields = { X='diff_pk_x_idx', H='diff_pk_h_idx', M='diff_pk_m_idx', E='diff_pk_e_idx' }
    local src_dl = ADJACENT_HIGHER[diff_label]
    if not src_dl then
        S.status = 'Copy: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local src_idx, tgt_idx = S[idx_fields[src_dl]], S[idx_fields[diff_label]]
    if src_idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(DIFF_NAMES[src_dl])
        S.last_result = ('Select the PART REAL_KEYS_%s track in the Difficulty tab.'):format(src_dl)
        return
    end
    if tgt_idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(DIFF_NAMES[diff_label])
        S.last_result = ('Select the PART REAL_KEYS_%s track in the Difficulty tab.'):format(diff_label)
        return
    end
    local src_tr, tgt_tr = r.GetTrack(0, src_idx), r.GetTrack(0, tgt_idx)
    if not src_tr or not tgt_tr then
        S.status      = 'Error: a selected track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes = ReadPKNotes(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status      = ('Copy to %s: no notes on %s to copy.'):format(DIFF_NAMES[diff_label], DIFF_NAMES[src_dl])
        S.last_result = ('%s track has no notes%s.'):format(
            DIFF_NAMES[src_dl], sel_s and ' in the current time selection' or '')
        return
    end

    local tgt_notes = ReadPKNotes(tgt_tr, sel_s, sel_e)
    if #tgt_notes > 0 and not force then
        S.diff_copy_pending = {
            message = ('PART REAL_KEYS_%s already has notes. Clear them and overwrite with a copy of PART REAL_KEYS_%s?'):format(
                diff_label, src_dl),
            on_confirm = function() CopyProKeysDiff(diff_label, true) end,
        }
        return
    end

    local tgt_item, tgt_take = FindFirstMIDIItem(tgt_tr)
    if not tgt_item then
        S.status      = ('Error: %s track has no MIDI item.'):format(DIFF_NAMES[diff_label])
        S.last_result = ('Create a MIDI item on the PART REAL_KEYS_%s track first.'):format(diff_label)
        return
    end

    local clear_s = sel_s or 0
    local clear_e = sel_e or (r.GetMediaItemInfo_Value(tgt_item, 'D_POSITION') + r.GetMediaItemInfo_Value(tgt_item, 'D_LENGTH'))

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(tgt_tr, tgt_item)
    ClearNotesInRange(tgt_take, clear_s, clear_e, 0, 9)
    ClearNotesInRange(tgt_take, clear_s, clear_e, PK_MIN, PK_MAX)
    local out_notes = {}
    for _, n in ipairs(src_notes) do
        out_notes[#out_notes + 1] = { s = n.s, e = n.e, pitch = n.pitch }
    end
    InsertNotes(tgt_take, out_notes, 100)
    r.Undo_EndBlock2(0, ('Copy Pro Keys %s to %s'):format(src_dl, diff_label), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status      = ('Copy to %s: copied %d notes from %s.'):format(DIFF_NAMES[diff_label], #src_notes, DIFF_NAMES[src_dl])
    S.last_result = nil
end

-- Validate PART REAL_KEYS_{diff_label} against RBN authoring rules.
-- diff_label: 'X', 'H', 'M', or 'E'
function ValidateProKeysDiff(diff_label)
    local idx_fields = { X='diff_pk_x_idx', H='diff_pk_h_idx', M='diff_pk_m_idx', E='diff_pk_e_idx' }
    local field      = idx_fields[diff_label]
    if not field then
        S.status = 'Validate: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local tgt_idx = S[field]
    if tgt_idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(DIFF_NAMES[diff_label])
        S.last_result = ('Select the PART REAL_KEYS_%s track in the Difficulty tab.'):format(diff_label)
        return
    end
    local tgt_tr = r.GetTrack(0, tgt_idx)
    if not tgt_tr then
        S.status      = ('Error: %s track no longer exists - refresh tracks.'):format(DIFF_NAMES[diff_label])
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local all_notes    = ReadPKNotes(tgt_tr, sel_s, sel_e)
    local lane_shifts, events = GroupIntoEvents(all_notes)

    -- Only bail when the track is completely empty (no lane markers either).
    -- A track with lane markers but no playable notes falls through to RunPKValidation,
    -- where CheckMissingMeasures will flag the missing measures.
    if #all_notes == 0 then
        S.status = ('Validate %s: track is empty.'):format(diff_label)
        S.last_result = sel_s
            and ('No notes on %s track in the current time selection.'):format(DIFF_NAMES[diff_label])
            or  ('%s track is empty.'):format(DIFF_NAMES[diff_label])
        return
    end

    -- Load Expert events for cross-diff check (H/M/E only)
    local exp_events = nil
    if diff_label ~= 'X' and S.diff_pk_x_idx >= 0 then
        local exp_tr = r.GetTrack(0, S.diff_pk_x_idx)
        if exp_tr then
            local exp_notes = ReadPKNotes(exp_tr, sel_s, sel_e)
            local _, evs    = GroupIntoEvents(exp_notes)
            if #evs > 0 then exp_events = evs end
        end
    end

    local scope  = sel_s and ' [time selection]' or ''
    local header = ('Pro Keys %s Validation%s'):format(DIFF_NAMES[diff_label], scope)
    local report, total = RunPKValidation(diff_label, events, lane_shifts, exp_events, sel_s, header)

    -- Cross-difficulty progression check (vs the immediately higher tier,
    -- not always Expert - separate concern from exp_events above).
    local higher_dl = ADJACENT_HIGHER[diff_label]
    if higher_dl then
        local higher_events, higher_count = {}, 0
        local higher_idx = S[idx_fields[higher_dl]]
        if higher_idx >= 0 then
            local higher_tr = r.GetTrack(0, higher_idx)
            if higher_tr then
                local higher_notes = ReadPKNotes(higher_tr, sel_s, sel_e)
                local _, hevs = GroupIntoEvents(higher_notes)
                higher_events, higher_count = hevs, CountNotes(hevs)
            end
        end
        local block, extra = CheckDifficultyProgression(
            DIFF_NAMES[diff_label], DIFF_NAMES[higher_dl],
            events, higher_events, PK_MIN, PK_MIN,
            CountNotes(events), higher_count)
        report = block .. report
        total  = total + extra
    end

    if total == 0 then
        S.status = ('Validate %s: all checks passed%s.'):format(diff_label, scope)
    else
        S.status = ('Validate %s: %d issue%s found%s.'):format(
            diff_label, total, total == 1 and '' or 's', scope)
    end
    S.last_result = report
end

-- Validate all four Pro Keys difficulties and produce a combined report.
function ValidateAllProKeys()
    local sel_s, sel_e = GetTimeSelection()
    local scope        = sel_s and ' [time selection]' or ''

    -- Load Expert events once for cross-diff checks
    local exp_events = nil
    if S.diff_pk_x_idx >= 0 then
        local exp_tr = r.GetTrack(0, S.diff_pk_x_idx)
        if exp_tr then
            local enotes = ReadPKNotes(exp_tr, sel_s, sel_e)
            local _, evs = GroupIntoEvents(enotes)
            if #evs > 0 then exp_events = evs end
        end
    end

    local all_lines    = { ('Pro Keys Validate All%s'):format(scope), '' }
    local summary      = {}
    local diff_order   = { 'X', 'H', 'M', 'E' }
    local idx_fields   = { X='diff_pk_x_idx', H='diff_pk_h_idx', M='diff_pk_m_idx', E='diff_pk_e_idx' }

    -- Carried forward from the previous (higher) tier for the cross-difficulty
    -- progression check - avoids re-reading a track already read this loop.
    local prev_dl, prev_events, prev_count = nil, {}, 0

    for _, dl in ipairs(diff_order) do
        local tgt_idx = S[idx_fields[dl]]
        if tgt_idx < 0 then
            summary[#summary + 1] = dl .. ':(none)'
            prev_dl, prev_events, prev_count = dl, {}, 0
        else
            local tgt_tr = r.GetTrack(0, tgt_idx)
            if not tgt_tr then
                summary[#summary + 1] = dl .. ':missing'
                prev_dl, prev_events, prev_count = dl, {}, 0
            else
                local notes            = ReadPKNotes(tgt_tr, sel_s, sel_e)
                local lane_shifts, evs = GroupIntoEvents(notes)

                if #notes == 0 then
                    summary[#summary + 1] = dl .. ':empty'
                    all_lines[#all_lines + 1] = ('=== %s ===  (track is empty)'):format(DIFF_NAMES[dl])
                    all_lines[#all_lines + 1] = ''
                    prev_dl, prev_events, prev_count = dl, {}, 0
                else
                    local use_exp = (dl ~= 'X') and exp_events or nil
                    local header  = ('=== Pro Keys %s ==='):format(DIFF_NAMES[dl])
                    local report, total = RunPKValidation(dl, evs, lane_shifts, use_exp, sel_s, header)

                    if dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] then
                        local block, extra = CheckDifficultyProgression(
                            DIFF_NAMES[dl], DIFF_NAMES[prev_dl],
                            evs, prev_events, PK_MIN, PK_MIN,
                            CountNotes(evs), prev_count)
                        report = block .. report
                        total  = total + extra
                    end

                    if total == 0 then
                        summary[#summary + 1] = dl .. ':OK'
                    else
                        summary[#summary + 1] = ('%s:%d'):format(dl, total)
                    end
                    -- Append report lines (skip the leading blank we already added)
                    for line in (report .. '\n'):gmatch('([^\n]*)\n') do
                        all_lines[#all_lines + 1] = line
                    end
                    prev_dl, prev_events, prev_count = dl, evs, CountNotes(evs)
                end
            end
        end
    end

    S.status      = ('Validate All Pro Keys%s: %s'):format(scope, table.concat(summary, ' | '))
    S.last_result = table.concat(all_lines, '\n')
end
