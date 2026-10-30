-- Midi note: bulk non-sustain note-length unification and sustain-gap normalization.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, GetTakePPQPerQN,
-- GetPatternPitchRange (globals)
--
-- All length/gap math works in raw take-relative PPQ ticks (never seconds or
-- QN floats) so results always land exactly on REAPER's own note-length grid
-- - standard note values divide evenly into GetTakePPQPerQN's tick count.

local SUSTAIN_MIN_DENOM = 8    -- 1/8 note: minimum length to be treated as a sustain
local FLOOR_DENOM        = 32   -- 1/32 note: minimum length any note can be shortened to
local SEARCH_WINDOW_32NDS = 16  -- how far ahead (in 32nd notes) to look for "the next note"
                                -- (16x1/32 = a half note, i.e. half a measure in 4/4)
local USUAL_GAP_TOLERANCE = 1.5 -- a sustain is lengthened only when its gap is at most this
                                -- many times the track's most common gap; a longer gap is
                                -- taken as an intentional rest (muted guitar, a break)

-- Standard sustain gap per difficulty tier, in 32nd notes (S.mn_diff_idx:
-- 1=Expert, 2=Hard, 3=Medium, 4=Easy). The UI prefills the gap slider with
-- this when the tier is chosen; the user is free to override it afterwards.
local SUSTAIN_GAP_BY_DIFF = { [1] = 3, [2] = 4, [3] = 8, [4] = 16 }

function SustainGapDefaultForDiff(diff_idx)
    return SUSTAIN_GAP_BY_DIFF[diff_idx]
end

-- Standard note length in take-relative PPQ ticks, rounded to the nearest tick.
local function NoteLenPPQ(ppq_per_qn, denom)
    return math.floor(ppq_per_qn * 4 / denom + 0.5)
end

-- Set every non-sustain note's (length < 1/8 note) end position (in [lo,hi]
-- pitch range, inside the scope) to start + the standard length for `denom`.
-- Existing sustains (>= 1/8 note) are left completely untouched. Single pass:
-- note count and start positions are never touched, so no re-sort/index-shift
-- concerns. Every matching pitch still gets its own MIDI_SetNote call, but a
-- chord (multiple notes sharing one start tick, e.g. a Green+Red+Blue chord)
-- is only counted once, so the report reads as "N notes", not "N pitches".
local function AdjustNonSustainLengths(take, lo, hi, sel_s, sel_e, denom)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len_ppq     = NoteLenPPQ(ppq_per_qn, denom)
    local sustain_min = NoteLenPPQ(ppq_per_qn, SUSTAIN_MIN_DENOM)
    local scope_s = sel_s and r.MIDI_GetPPQPosFromProjTime(take, sel_s) or nil
    local scope_e = sel_e and r.MIDI_GetPPQPosFromProjTime(take, sel_e) or nil

    local _, n = r.MIDI_CountEvts(take)
    local count = 0
    local counted_starts = {}
    for i = 0, n - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(take, i)
        if ok and p >= lo and p <= hi
           and (not scope_s or sppq >= scope_s) and (not scope_e or sppq < scope_e)
           and (eppq - sppq) < sustain_min then
            r.MIDI_SetNote(take, i, sel, mute, sppq, sppq + len_ppq, chan, p, vel, true)
            if not counted_starts[sppq] then
                counted_starts[sppq] = true
                count = count + 1
            end
        end
    end
    return count
end

-- The note `notes[i]` is followed by: the start tick of the EARLIEST note
-- starting strictly after its own start (notes sharing the start tick are
-- chord-mates, not "next"), or nil when that note starts past the search
-- window. A note starting inside the sustain always counts, however far the
-- next clean note is: it's buried under the sustain and must be uncovered.
-- Measuring only from the sustain's tail would step over such a note and
-- stretch the sustain toward a later one, leaving the overlap in place.
-- `notes` must be start-sorted.
local function NextNoteStart(notes, i, search_win)
    local note = notes[i]
    for j = i + 1, #notes do
        if notes[j].sppq > note.sppq then
            if notes[j].sppq < note.eppq
               or notes[j].sppq - note.eppq <= search_win then
                return notes[j].sppq
            end
            return nil
        end
    end
    return nil
end

-- The most common gap from a sustain's end to the next note, in whole 32nd
-- notes (each gap rounded to the nearest 32nd). Buried notes and gaps past
-- the search window are not playing gaps and are not counted; a chord counts
-- once. Ties go to the smaller gap. Returns usual, its count, total counted -
-- or nil when there is no gap to count.
local function UsualSustainGap(notes, thirty2_ppq, sustain_min, search_win)
    local counts, total = {}, 0
    local counted_starts = {}
    for i, note in ipairs(notes) do
        if note.eppq - note.sppq >= sustain_min and not counted_starts[note.sppq] then
            counted_starts[note.sppq] = true
            local next_sppq = NextNoteStart(notes, i, search_win)
            if next_sppq and next_sppq >= note.eppq then
                local g = math.floor((next_sppq - note.eppq) / thirty2_ppq + 0.5)
                counts[g] = (counts[g] or 0) + 1
                total = total + 1
            end
        end
    end
    local usual, best = nil, 0
    for g, c in pairs(counts) do
        if c > best or (c == best and g < usual) then usual, best = g, c end
    end
    if not usual then return nil end
    return usual, best, total
end

-- How long a gap (in 32nds) may still be closed up when the usual gap is
-- `usual`: usual x USUAL_GAP_TOLERANCE, rounded down, but always at least one
-- 32nd more than the usual gap (3 -> 4, 2 -> 3, 1 -> 2, 0 -> 1).
local function LengthenLimit32nds(usual)
    return math.max(math.floor(usual * USUAL_GAP_TOLERANCE), usual + 1)
end

-- For every sustain (length >= 1/8 note) in [lo,hi] pitch range inside the
-- scope, set its end position so the gap to the next in-range note is
-- exactly `gap_32nds` x 1/32 note - widening or narrowing the sustain as
-- needed. A sustain with no next note within SEARCH_WINDOW_32NDS x 1/32 notes
-- of its own end is left unchanged (skipped). If honoring the requested gap
-- would shrink the sustain below the 1/32-note floor, it's clamped to that
-- floor instead (becomes a non-sustain). See NextNoteStart for "next note".
--
-- Lengthening is limited: the track's most common gap is measured over the
-- WHOLE take in the pitch range (not just the scope, so a section-by-section
-- run sees the song's value), and a sustain whose gap is longer than
-- LengthenLimit32nds of it is left alone - an author who ends a sustain much
-- earlier than usual means a rest. A gap tighter than the target is always
-- fixed, whatever its size: shortening a sustain never fills a rest.
--
-- Every matching pitch still gets its own MIDI_SetNote call, but a chord
-- sustain (multiple notes sharing one start tick, e.g. a Green+Red+Blue
-- chord) is only counted once toward adjusted/skipped/clamped/left, so the
-- report reads as "N sustains", not "N pitches" - the first note processed at
-- a given start tick decides which bucket the whole chord is counted in.
--
-- Returns adjusted, skipped, clamped, left (list of { sppq, gap_32nds }),
-- usual ({ gap_32nds, count, total, limit_32nds } or nil).
local function AdjustSustainGaps(take, lo, hi, sel_s, sel_e, gap_32nds)
    local ppq_per_qn  = GetTakePPQPerQN(take)
    local thirty2_ppq = NoteLenPPQ(ppq_per_qn, FLOOR_DENOM)
    local sustain_min = NoteLenPPQ(ppq_per_qn, SUSTAIN_MIN_DENOM)
    local search_win  = SEARCH_WINDOW_32NDS * thirty2_ppq
    local gap_target  = gap_32nds * thirty2_ppq
    local scope_s = sel_s and r.MIDI_GetPPQPosFromProjTime(take, sel_s) or nil
    local scope_e = sel_e and r.MIDI_GetPPQPosFromProjTime(take, sel_e) or nil

    -- Pass 1: collect every in-range note's original start/end, sorted by
    -- start - "next note" lookups must see original, unmodified positions.
    -- `all` ignores the scope (for the usual gap); `notes` is the scope.
    local all = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(take, i)
        if ok and p >= lo and p <= hi then
            all[#all + 1] = {
                idx = i, sppq = sppq, eppq = eppq, chan = chan, pitch = p, vel = vel,
                sel = sel, mute = mute,
            }
        end
    end
    table.sort(all, function(a, b) return a.sppq < b.sppq end)
    local notes = {}
    for _, note in ipairs(all) do
        if (not scope_s or note.sppq >= scope_s) and (not scope_e or note.sppq < scope_e) then
            notes[#notes + 1] = note
        end
    end

    local usual_g, usual_n, usual_total = UsualSustainGap(all, thirty2_ppq, sustain_min, search_win)
    local usual, limit_32nds = nil, nil
    if usual_g then
        limit_32nds = LengthenLimit32nds(usual_g)
        usual = { gap_32nds = usual_g, count = usual_n, total = usual_total,
                  limit_32nds = limit_32nds }
    end

    -- Pass 2: adjust sustains against the (unmodified) start positions above.
    local adjusted, skipped, clamped = 0, 0, 0
    local left = {}
    local counted_starts = {}
    for i, note in ipairs(notes) do
        local len = note.eppq - note.sppq
        if len >= sustain_min then
            local next_sppq = NextNoteStart(notes, i, search_win)
            local first_at_start = not counted_starts[note.sppq]
            counted_starts[note.sppq] = true
            local leave_gap = nil   -- set (in 32nds) when this is a rest to leave alone
            if next_sppq and next_sppq >= note.eppq then
                local gap = next_sppq - note.eppq
                local gap_r = math.floor(gap / thirty2_ppq + 0.5)
                if gap > gap_target and limit_32nds and gap_r > limit_32nds then
                    leave_gap = gap_r
                end
            end
            if next_sppq and not leave_gap then
                local new_eppq = next_sppq - gap_target
                local floor_eppq = note.sppq + thirty2_ppq
                local was_clamped = false
                if new_eppq < floor_eppq then
                    new_eppq = floor_eppq
                    was_clamped = true
                end
                r.MIDI_SetNote(take, note.idx, note.sel, note.mute, note.sppq, new_eppq,
                    note.chan, note.pitch, note.vel, true)
                if first_at_start then
                    adjusted = adjusted + 1
                    if was_clamped then clamped = clamped + 1 end
                end
            elseif first_at_start then
                if leave_gap then
                    left[#left + 1] = { sppq = note.sppq, gap_32nds = leave_gap }
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return adjusted, skipped, clamped, left, usual
end

function AdjustMidiNoteLengths()
    if S.mn_midi_idx < 0 then
        S.status = 'Set a MIDI track first.'; return
    end
    local track = r.GetTrack(0, S.mn_midi_idx)
    if not track then
        S.status = 'Selected track no longer exists - pick the track again.'; return
    end
    local item, take = FindFirstMIDIItem(track)
    if not take then
        S.status = 'No MIDI item on selected track.'; return
    end
    if S.mn_note_type == 0 and S.mn_note_denom <= 0 then
        S.status = 'Set a Note size first.'; return
    end

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mn_diff_idx)
    local sel_s, sel_e = GetTimeSelection()

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    if S.mn_note_type == 0 then
        local count = AdjustNonSustainLengths(take, lo, hi, sel_s, sel_e, S.mn_note_denom)
        r.Undo_EndBlock2(0, ('Adjust notes: unify %d non-sustain note%s to 1/%d'):format(
            count, count ~= 1 and 's' or '', S.mn_note_denom), -1)
        S.status = ('Adjusted %d non-sustain note%s.'):format(count, count ~= 1 and 's' or '')
        S.last_result = nil
    else
        local adjusted, skipped, clamped, left, usual =
            AdjustSustainGaps(take, lo, hi, sel_s, sel_e, S.mn_sustain_32nds)
        r.Undo_EndBlock2(0, ('Adjust notes: sustain gaps (%d adjusted)'):format(adjusted), -1)
        local lines = {}
        if usual then
            lines[#lines + 1] = ('Most common gap: %d/32 (%d of %d sustains). Lengthened only where the gap was %d/32 or less.'):format(
                usual.gap_32nds, usual.count, usual.total, usual.limit_32nds)
        else
            lines[#lines + 1] = 'No gaps to measure a most common gap from.'
        end
        lines[#lines + 1] = ('%d sustain%s adjusted, %d skipped (no next note within a half note).'):format(
            adjusted, adjusted ~= 1 and 's' or '', skipped)
        if clamped > 0 then
            lines[#lines + 1] = ('%d clamped to the 1/32-note floor (became non-sustain).'):format(clamped)
        end
        if #left > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('%d left alone - gap longer than %d/32 (check by hand):'):format(
                #left, usual.limit_32nds)
            for _, l in ipairs(left) do
                local t = r.MIDI_GetProjTimeFromPPQPos(take, l.sppq)
                lines[#lines + 1] = ('%s\tgap %d/32'):format(r.format_timestr_pos(t, '', 1), l.gap_32nds)
            end
            S.status = ('Adjust notes done - %d long gap%s left alone.'):format(
                #left, #left ~= 1 and 's' or '')
        else
            S.status = 'Adjust notes done.'
        end
        S.last_result = table.concat(lines, '\n')
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end
