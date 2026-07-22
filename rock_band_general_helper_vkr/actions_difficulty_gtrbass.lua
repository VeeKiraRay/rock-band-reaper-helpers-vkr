-- Guitar/Bass difficulty validation and copy-to-next-tier tools (shared core)
-- Requires: S, r, GetTimeSelection, FormatTime, PitchName,
--           SustainThresholds (from actions_guitar_validate.lua),
--           FindFirstMIDIItem, InsertNotes, ClearNotesInRange (globals)

-- Per-difficulty pitch ranges (single track per instrument, like PART KEYS)
local GB_RANGE = {
    X = { lo = 96, hi = 100 },
    H = { lo = 84, hi = 88  },
    M = { lo = 72, hi = 75  },  -- 4 gems: no Orange
    E = { lo = 60, hi = 62  },  -- 3 gems: Green/Red/Yellow only
}

-- Per-difficulty max simultaneous notes
local GB_MAX_CHORD = { X = 3, H = 2, M = 2, E = 1 }

-- Per-difficulty max chord span (offset steps between lowest/highest gem).
-- Expert's 3-note Green+Orange restriction and the 2-note Green+Orange advisory
-- are handled separately in CheckGBChordSpan since they aren't plain span limits.
local GB_MAX_SPAN = { H = 3, M = 2 }

-- Force-HOPO markers (notes F/F#, offsets lo+5/lo+6) are Expert/Hard-only.
local GB_FORCE_HOPO_ALLOWED = { X = true, H = true, M = false, E = false }

-- Advisory-only note-density grid (qualitative "try to" rules, not chart-breaking)
local GB_ADV_SP = { M = 1.0, E = 2.0 }  -- 1/4 note grid (Medium), 1/2 note grid (Easy)

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }
local GEM_NAMES  = { 'Green', 'Red', 'Yellow', 'Blue', 'Orange' }

-- Immediately-higher adjacent tier, for the cross-difficulty progression
-- check (CheckDifficultyProgression in actions_difficulty_shared.lua).
local ADJACENT_HIGHER = { H = 'X', M = 'H', E = 'M' }

-- Sum of individual notes across all chord events (not chord/event count).
local function CountNotes(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

local INSTRUMENTS = {
    gtr  = { idx_field = 'diff_gtr_idx',  label = 'Guitar', track_name = 'PART GUITAR' },
    bass = { idx_field = 'diff_bass_idx', label = 'Bass',   track_name = 'PART BASS'  },
}

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

-- Read non-muted notes in pitch range [lo, hi] from all MIDI items on track.
local function ReadGBNotes(track, lo, hi, t_s, t_e)
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
local function GroupGBChords(notes)
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

-- Project time -> quarter-note position, exact w.r.t. the tempo map.
local function QNAt(t) return r.TimeMap2_timeToQN(0, t) end

local GRACE  = 0.05  -- forgive gaps up to 5% under the requirement (hand-placed notes)
local EPS_QN = 0.01  -- epsilon for classification thresholds (~5 ms at 120 BPM)

-- Gem color name for a pitch: offset from the nearest difficulty's lo (0-4).
local function GBGemName(pitch)
    for _, rng in pairs(GB_RANGE) do
        local offset = pitch - rng.lo
        if offset >= 0 and offset <= 4 then
            return GEM_NAMES[offset + 1]
        end
    end
    return PitchName(pitch)
end

local function GBLabel(pitches)
    if #pitches == 1 then return GBGemName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = GBGemName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

----------------------------------------------------------------------
-- Check functions - each returns an array of issue strings
----------------------------------------------------------------------

local function CheckGBChordCount(events, max_chord, diff_label)
    local issues = {}
    for _, ev in ipairs(events) do
        if #ev.pitches > max_chord then
            local limit_str = max_chord == 1 and 'no chords' or ('max ' .. max_chord)
            issues[#issues + 1] = ('%s: %s has %d notes (%s for %s)'):format(
                FormatTime(ev.s), GBLabel(ev.pitches), #ev.pitches, limit_str, DIFF_NAMES[diff_label])
        end
    end
    return issues
end

-- Chord shape legality: illegal 3-note Green+Orange (Expert-only hard rule),
-- 2-note Green+Orange advisory (Expert-only, "use sparingly"), and the
-- per-difficulty max-span restriction (Hard: no Green+Orange; Medium: no
-- Green+Blue). Returns (issues, advisories).
local function CheckGBChordSpan(events, diff_label)
    local issues, advisories = {}, {}
    for _, ev in ipairs(events) do
        if #ev.pitches >= 2 then
            local span = ev.pitches[#ev.pitches] - ev.pitches[1]
            if diff_label == 'X' and #ev.pitches == 3 then
                if span == 4 then
                    issues[#issues + 1] = ('%s: %s illegal 3-note chord (Green+Orange combination not allowed)'):format(
                        FormatTime(ev.s), GBLabel(ev.pitches))
                end
            elseif diff_label == 'X' and #ev.pitches == 2 and span == 4 then
                advisories[#advisories + 1] = ('%s: %s (Green+Orange) - use as sparingly as possible'):format(
                    FormatTime(ev.s), GBLabel(ev.pitches))
            elseif GB_MAX_SPAN[diff_label] and span > GB_MAX_SPAN[diff_label] then
                issues[#issues + 1] = ('%s: %s spans %d frets (max %d for %s)'):format(
                    FormatTime(ev.s), GBLabel(ev.pitches), span, GB_MAX_SPAN[diff_label], DIFF_NAMES[diff_label])
            end
        end
    end
    return issues, advisories
end

-- Notes shorter than 1/64 note. Reuses actions_guitar_validate.lua's SustainThresholds.
local function CheckGBNoteLength(events)
    local issues = {}
    for _, ev in ipairs(events) do
        local _, _, note_min_s = SustainThresholds(ev.s)
        local dur = ev.e - ev.s
        if dur < note_min_s - 0.001 then
            issues[#issues + 1] = ('%s: %s is %.1f ms long (min 1/64 note \xe2\x89\x88 %.1f ms)'):format(
                FormatTime(ev.s), GBLabel(ev.pitches), dur * 1000, note_min_s * 1000)
        end
    end
    return issues
end

-- Overlap with previous event (any note starting before the previous ends
-- won't appear on the chart at all).
local function CheckGBOverlap(events)
    local issues = {}
    for i = 2, #events do
        local prev, curr = events[i - 1], events[i]
        if curr.s < prev.e - 0.001 then
            issues[#issues + 1] = ('%s: %s starts %.1f ms before previous event ends'):format(
                FormatTime(curr.s), GBLabel(curr.pitches), (prev.e - curr.s) * 1000)
        end
    end
    return issues
end

-- Gap between end of a sustained note and the next note start.
-- X/H: 1/32 note hard minimum (same as the existing Expert-only validator).
-- M/E: 1/4 note gap required (mirrors Keys' M/E rule).
local function CheckGBSustainGaps(events, diff_label)
    local issues = {}
    for i = 1, #events - 1 do
        local ev, next_ev = events[i], events[i + 1]
        if next_ev.s < ev.e - 0.001 then goto gbsg_next end  -- overlap; handled elsewhere

        if diff_label == 'M' or diff_label == 'E' then
            local qn_e   = QNAt(ev.e)
            local dur_qn = qn_e - QNAt(ev.s)
            if dur_qn < 0.5 - EPS_QN then goto gbsg_next end  -- not sustained (< 1/8 note)
            local gap_qn = QNAt(next_ev.s) - qn_e
            if gap_qn < 1.0 * (1 - GRACE) then
                local gap   = next_ev.s - ev.e
                local min_s = r.TimeMap2_QNToTime(0, qn_e + 1.0) - ev.e
                issues[#issues + 1] = ('%s: %s ends %.0f ms before %s (need 1/4 note gap \xe2\x89\x88 %.0f ms)'):format(
                    FormatTime(next_ev.s), GBLabel(ev.pitches), gap * 1000, GBLabel(next_ev.pitches), min_s * 1000)
            end
        else
            local sustain_thresh, gap_min_s = SustainThresholds(ev.s)
            if (ev.e - ev.s) > sustain_thresh + 0.001 then
                local gap = next_ev.s - ev.e
                if gap < gap_min_s - 0.001 then
                    issues[#issues + 1] = ('%s: %s ends %.1f ms before %s (min 1/32 note \xe2\x89\x88 %.1f ms)'):format(
                        FormatTime(next_ev.s), GBLabel(ev.pitches), gap * 1000, GBLabel(next_ev.pitches), gap_min_s * 1000)
                end
            end
        end
        ::gbsg_next::
    end
    return issues
end

-- Advisory-only note-density grid: Medium targets a quarter-note grid, Easy a
-- half-note grid. Qualitative ("try to") in the source docs, not chart-breaking.
local function CheckGBSpacingAdvisory(events, diff_label)
    local adv_beats = GB_ADV_SP[diff_label]
    if not adv_beats then return {} end
    local issues = {}
    for i = 2, #events do
        local prev, curr = events[i - 1], events[i]
        local qn_prev = QNAt(prev.s)
        local gap_qn  = QNAt(curr.s) - qn_prev
        if gap_qn < adv_beats * (1 - GRACE) then
            local gap      = curr.s - prev.s
            local adv_s    = r.TimeMap2_QNToTime(0, qn_prev + adv_beats) - prev.s
            local frac_str = adv_beats == 1.0 and '1/4 note' or '1/2 note'
            issues[#issues + 1] = ('%s: %s is %.0f ms after previous (advisory: %s grid \xe2\x89\x88 %.0f ms recommended for %s)'):format(
                FormatTime(curr.s), GBLabel(curr.pitches), gap * 1000, frac_str, adv_s * 1000, DIFF_NAMES[diff_label])
        end
    end
    return issues
end

-- Notes with pitches above the valid hi for this difficulty (authoring error).
local function CheckGBOutOfRange(events, rng_hi)
    local issues = {}
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            if p > rng_hi then
                issues[#issues + 1] = ('%s: %s (pitch %d) is outside the valid range for this difficulty'):format(
                    FormatTime(ev.s), GBGemName(p), p)
            end
        end
    end
    return issues
end

-- Force-HOPO markers (notes F/F#, offsets lo+5/lo+6) - disallowed on Medium/Easy.
local function CheckGBForceHopo(track, rng, diff_label, sel_s, sel_e)
    local issues = {}
    local force_lo, force_hi = rng.lo + 5, rng.lo + 6
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, _, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and (pitch == force_lo or pitch == force_hi) then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                        issues[#issues + 1] = ('%s: force-HOPO marker found (not allowed on %s)'):format(
                            FormatTime(s), DIFF_NAMES[diff_label])
                    end
                end
            end
        end
    end
    return issues
end

-- Trill/Tremolo markers (fixed pitches 126/127, not per-difficulty-shifted):
-- velocity <=40 causes a Magma spacing error if the marker needs to reduce to
-- Hard or lower (41-50 required for Hard eligibility).
local function CheckGBTrillVelocity(track, sel_s, sel_e)
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
                            local kind = pitch == 126 and 'Tremolo' or 'Trill'
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

----------------------------------------------------------------------
-- Report builder and validation runner
----------------------------------------------------------------------

local function BuildGBReport(header, cats)
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

local function RunGBChecks(diff_label, events, header, rng, track, sel_s, sel_e)
    local cats = {}

    cats[#cats + 1] = { name = 'Notes outside valid range', issues = CheckGBOutOfRange(events, rng.hi) }

    local max_ch = GB_MAX_CHORD[diff_label]
    local chord_name = diff_label == 'E' and 'Chords (none allowed on Easy)' or ('Max chord (%d notes)'):format(max_ch)
    cats[#cats + 1] = { name = chord_name, issues = CheckGBChordCount(events, max_ch, diff_label) }

    local span_issues, span_adv = CheckGBChordSpan(events, diff_label)
    cats[#cats + 1] = { name = 'Chord shape restrictions', issues = span_issues }
    if #span_adv > 0 then
        cats[#cats + 1] = { name = 'Advisory: Green+Orange chords (use sparingly)', issues = span_adv }
    end

    cats[#cats + 1] = { name = 'Note length (min 1/64)', issues = CheckGBNoteLength(events) }
    cats[#cats + 1] = { name = 'Overlapping notes', issues = CheckGBOverlap(events) }

    local sg_name = (diff_label == 'M' or diff_label == 'E')
        and 'Sustain gaps (min 1/4 note gap to next)'
        or  'Sustain gaps (min 1/32 note)'
    cats[#cats + 1] = { name = sg_name, issues = CheckGBSustainGaps(events, diff_label) }

    if GB_ADV_SP[diff_label] then
        cats[#cats + 1] = { name = 'Advisory: note density grid', issues = CheckGBSpacingAdvisory(events, diff_label) }
    end

    if not GB_FORCE_HOPO_ALLOWED[diff_label] then
        cats[#cats + 1] = {
            name   = 'Force-HOPO markers (not allowed on Medium/Easy)',
            issues = CheckGBForceHopo(track, rng, diff_label, sel_s, sel_e),
        }
    end
    if diff_label == 'H' then
        cats[#cats + 1] = {
            name   = 'Trill/Tremolo velocity (Hard eligibility)',
            issues = CheckGBTrillVelocity(track, sel_s, sel_e),
        }
    end

    return BuildGBReport(header, cats)
end

----------------------------------------------------------------------
-- Global action functions
----------------------------------------------------------------------

-- Validate notes in the diff_label pitch range for the given instrument.
-- instrument: 'gtr' or 'bass'.  diff_label: 'X', 'H', 'M', or 'E'.
function ValidateGtrBassDiff(instrument, diff_label)
    local inst = INSTRUMENTS[instrument]
    local idx  = S[inst.idx_field]
    if idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(inst.track_name)
        S.last_result = ('Select the %s track in the Difficulty \xe2\x86\x92 Guitar/Bass tab.'):format(inst.track_name)
        return
    end
    local track = r.GetTrack(0, idx)
    if not track then
        S.status      = ('Error: %s track no longer exists \xe2\x80\x94 refresh tracks.'):format(inst.track_name)
        S.last_result = nil
        return
    end

    local rng          = GB_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    local notes         = ReadGBNotes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
    local events        = GroupGBChords(notes)

    if #notes == 0 then
        S.status = ('Validate %s %s: no notes in %s\xe2\x80\x93%s (%d\xe2\x80\x93%d).'):format(
            inst.label, diff_label, PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi)
        S.last_result = sel_s
            and ('No %s notes (%s\xe2\x80\x93%s) in the current time selection.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
            or  ('No %s notes (%s\xe2\x80\x93%s) on %s track.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi), inst.track_name)
        return
    end

    local scope  = sel_s and ' [time selection]' or ''
    local header = ('%s %s Validation  [%s\xe2\x80\x93%s, %d\xe2\x80\x93%d]%s'):format(
        inst.label, DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi, scope)
    local report, total = RunGBChecks(diff_label, events, header, rng, track, sel_s, sel_e)

    -- Cross-difficulty progression check (vs the immediately higher tier).
    local higher_dl = ADJACENT_HIGHER[diff_label]
    if higher_dl then
        local higher_rng    = GB_RANGE[higher_dl]
        local higher_notes  = ReadGBNotes(track, higher_rng.lo, higher_rng.lo + 4, sel_s, sel_e)
        local higher_events = GroupGBChords(higher_notes)
        local block, extra = CheckDifficultyProgression(
            DIFF_NAMES[diff_label], DIFF_NAMES[higher_dl],
            events, higher_events, rng.lo, higher_rng.lo,
            CountNotes(events), CountNotes(higher_events))
        report = block .. report
        total  = total + extra
    end

    if total == 0 then
        S.status = ('Validate %s %s: all checks passed%s.'):format(inst.label, diff_label, scope)
    else
        S.status = ('Validate %s %s: %d issue%s found%s.'):format(
            inst.label, diff_label, total, total == 1 and '' or 's', scope)
    end
    S.last_result = report
end

-- Validate all four difficulty ranges for the given instrument in one report.
function ValidateAllGtrBass(instrument)
    local inst = INSTRUMENTS[instrument]
    local idx  = S[inst.idx_field]
    if idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(inst.track_name)
        S.last_result = ('Select the %s track in the Difficulty \xe2\x86\x92 Guitar/Bass tab.'):format(inst.track_name)
        return
    end
    local track = r.GetTrack(0, idx)
    if not track then
        S.status      = ('Error: %s track no longer exists \xe2\x80\x94 refresh tracks.'):format(inst.track_name)
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local scope         = sel_s and ' [time selection]' or ''
    local diff_order    = { 'X', 'H', 'M', 'E' }
    local all_lines     = { ('%s Validate All%s'):format(inst.label, scope), '' }
    local summary       = {}

    -- Carried forward from the previous (higher) tier for the cross-difficulty
    -- progression check - avoids re-reading a range already read this loop.
    local prev_dl, prev_events, prev_count = nil, {}, 0

    for _, dl in ipairs(diff_order) do
        local rng    = GB_RANGE[dl]
        local notes  = ReadGBNotes(track, rng.lo, rng.lo + 4, sel_s, sel_e)
        local events = GroupGBChords(notes)

        if #notes == 0 then
            summary[#summary + 1] = dl .. ':empty'
            all_lines[#all_lines + 1] = ('=== %s ===  (no notes in range %d\xe2\x80\x93%d)'):format(
                DIFF_NAMES[dl], rng.lo, rng.hi)
            all_lines[#all_lines + 1] = ''
            prev_dl, prev_events, prev_count = dl, {}, 0
        else
            local header         = ('=== %s %s  [%d\xe2\x80\x93%d] ==='):format(inst.label, DIFF_NAMES[dl], rng.lo, rng.hi)
            local report, total  = RunGBChecks(dl, events, header, rng, track, sel_s, sel_e)

            if dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] then
                local block, extra = CheckDifficultyProgression(
                    DIFF_NAMES[dl], DIFF_NAMES[prev_dl],
                    events, prev_events, rng.lo, GB_RANGE[prev_dl].lo,
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

    S.status      = ('Validate All %s%s: %s'):format(inst.label, scope, table.concat(summary, ' | '))
    S.last_result = table.concat(all_lines, '\n')
end

-- Copy notes from the immediately higher tier's range onto diff_label's own
-- range, for the given instrument. Colors above the target tier's ceiling
-- are compressed down via CompressChordOffsets (actions_difficulty_shared.lua)
-- rather than dropped outright or left out-of-range.
-- force: skip the "target already has notes" confirmation and overwrite
-- directly (set true when called again from the confirm popup).
function CopyGtrBassDiff(instrument, diff_label, force)
    local inst = INSTRUMENTS[instrument]
    local idx  = S[inst.idx_field]
    if idx < 0 then
        S.status      = ('Error: %s track not selected.'):format(inst.track_name)
        S.last_result = ('Select the %s track in the Difficulty \xe2\x86\x92 Guitar/Bass tab.'):format(inst.track_name)
        return
    end
    local track = r.GetTrack(0, idx)
    if not track then
        S.status      = ('Error: %s track no longer exists \xe2\x80\x94 refresh tracks.'):format(inst.track_name)
        S.last_result = nil
        return
    end

    local src_dl = ADJACENT_HIGHER[diff_label]
    if not src_dl then
        S.status = 'Copy: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local src_rng, tgt_rng = GB_RANGE[src_dl], GB_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    local src_notes  = ReadGBNotes(track, src_rng.lo, src_rng.lo + 4, sel_s, sel_e)
    local src_events = GroupGBChords(src_notes)

    if #src_notes == 0 then
        S.status      = ('Copy %s to %s: no notes on %s to copy.'):format(inst.label, DIFF_NAMES[diff_label], DIFF_NAMES[src_dl])
        S.last_result = ('%s %s range (%d\xe2\x80\x93%d) has no notes%s.'):format(
            inst.label, DIFF_NAMES[src_dl], src_rng.lo, src_rng.hi, sel_s and ' in the current time selection' or '')
        return
    end

    local tgt_notes = ReadGBNotes(track, tgt_rng.lo, tgt_rng.lo + 4, sel_s, sel_e)
    if #tgt_notes > 0 and not force then
        S.diff_copy_pending = {
            message = ('%s %s range already has notes. Clear them and overwrite with a copy of %s?'):format(
                inst.label, DIFF_NAMES[diff_label], DIFF_NAMES[src_dl]),
            on_confirm = function() CopyGtrBassDiff(instrument, diff_label, true) end,
        }
        return
    end

    local item, take = FindFirstMIDIItem(track)
    if not item then
        S.status      = ('Error: %s track has no MIDI item.'):format(inst.track_name)
        S.last_result = ('Create a MIDI item on the %s track first.'):format(inst.track_name)
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
    r.Undo_EndBlock2(0, ('Copy %s %s to %s'):format(inst.label, src_dl, diff_label), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status      = ('Copy %s to %s: copied %d notes from %s.'):format(inst.label, DIFF_NAMES[diff_label], #out_notes, DIFF_NAMES[src_dl])
    S.last_result = nil
end
