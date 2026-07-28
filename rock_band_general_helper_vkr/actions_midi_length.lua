-- Midi note: bulk non-sustain note-length unification and sustain-gap normalization.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, GetTakePPQPerQN,
-- GetPatternPitchRange (globals)
--
-- All length/gap math works in raw take-relative PPQ ticks (never seconds or
-- QN floats) so results always land exactly on REAPER's own note-length grid
-- - standard note values divide evenly into GetTakePPQPerQN's tick count.

local SUSTAIN_MIN_DENOM = 4    -- 1/4 note: minimum length to be treated as a sustain
local FLOOR_DENOM        = 32   -- 1/32 note: minimum length any note can be shortened to
local SEARCH_WINDOW_32NDS = 16  -- how far ahead (in 32nd notes) to look for "the next note"

-- Standard note length in take-relative PPQ ticks, rounded to the nearest tick.
local function NoteLenPPQ(ppq_per_qn, denom)
    return math.floor(ppq_per_qn * 4 / denom + 0.5)
end

-- Set every non-sustain note's (length < 1/4 note) end position (in [lo,hi]
-- pitch range, inside the scope) to start + the standard length for `denom`.
-- Existing sustains (>= 1/4 note) are left completely untouched. Single pass:
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

-- For every sustain (length >= 1/4 note) in [lo,hi] pitch range inside the
-- scope, set its end position so the gap to the next in-range note is
-- exactly `gap_32nds` x 1/32 note - widening or narrowing the sustain as
-- needed. A sustain with no next note within SEARCH_WINDOW_32NDS x 1/32 notes
-- of its own end is left unchanged (skipped). If honoring the requested gap
-- would shrink the sustain below the 1/32-note floor, it's clamped to that
-- floor instead (becomes a non-sustain).
--
-- Every matching pitch still gets its own MIDI_SetNote call, but a chord
-- sustain (multiple notes sharing one start tick, e.g. a Green+Red+Blue
-- chord) is only counted once toward adjusted/skipped/clamped, so the report
-- reads as "N sustains", not "N pitches" - the first note processed at a
-- given start tick decides which bucket the whole chord is counted in.
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
    local notes = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(take, i)
        if ok and p >= lo and p <= hi
           and (not scope_s or sppq >= scope_s) and (not scope_e or sppq < scope_e) then
            notes[#notes + 1] = {
                idx = i, sppq = sppq, eppq = eppq, chan = chan, pitch = p, vel = vel,
                sel = sel, mute = mute,
            }
        end
    end
    table.sort(notes, function(a, b) return a.sppq < b.sppq end)

    -- Pass 2: adjust sustains against the (unmodified) start positions above.
    local adjusted, skipped, clamped = 0, 0, 0
    local counted_starts = {}
    for i, note in ipairs(notes) do
        local len = note.eppq - note.sppq
        if len >= sustain_min then
            local next_sppq = nil
            for j = i + 1, #notes do
                if notes[j].sppq >= note.eppq then
                    if notes[j].sppq - note.eppq <= search_win then next_sppq = notes[j].sppq end
                    break
                end
            end
            local first_at_start = not counted_starts[note.sppq]
            counted_starts[note.sppq] = true
            if next_sppq then
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
                skipped = skipped + 1
            end
        end
    end
    return adjusted, skipped, clamped
end

function AdjustMidiNoteLengths()
    if S.mn_midi_idx < 0 then
        S.status = 'Set a MIDI track first.'; return
    end
    local track = r.GetTrack(0, S.mn_midi_idx)
    if not track then
        S.status = 'Selected track no longer exists - refresh tracks.'; return
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
        local adjusted, skipped, clamped = AdjustSustainGaps(take, lo, hi, sel_s, sel_e, S.mn_sustain_32nds)
        r.Undo_EndBlock2(0, ('Adjust notes: sustain gaps (%d adjusted)'):format(adjusted), -1)
        local lines = { ('%d sustain%s adjusted, %d skipped (no next note in range).'):format(
            adjusted, adjusted ~= 1 and 's' or '', skipped) }
        if clamped > 0 then
            lines[#lines + 1] = ('%d clamped to the 1/32-note floor (became non-sustain).'):format(clamped)
        end
        S.status = 'Adjust notes done.'
        S.last_result = table.concat(lines, '\n')
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end
