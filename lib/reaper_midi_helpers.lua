-- MIDI reading, clearing, and insertion helpers (shared library)
-- Requires globals: r (reaper), RB3_MIN_PITCH, RB3_MAX_PITCH

----------------------------------------------------------------------
function FindMIDIItem(track, range_start, range_end)
    local TOL = 0.001
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
            local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
            if pos <= range_start + TOL and pos + len + TOL >= range_end then
                return item, take
            end
        end
    end
    return nil, nil
end

----------------------------------------------------------------------
-- Find the first MIDI item on a track (no range requirement)
----------------------------------------------------------------------
function FindFirstMIDIItem(midi_track)
    for i = 0, r.CountTrackMediaItems(midi_track) - 1 do
        local item = r.GetTrackMediaItem(midi_track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then return item, take end
    end
    return nil, nil
end

----------------------------------------------------------------------
-- Read all MIDI notes from all MIDI items on a track within a range
----------------------------------------------------------------------
function ReadAllMIDINotesOnTrack(track, range_start, range_end)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local item_pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
            local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local item_end = item_pos + item_len
            if item_pos < range_end and item_end > range_start then
                local _, n = r.MIDI_CountEvts(take)
                for j = 0, n - 1 do
                    local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(take, j)
                    if ok then
                        local s_t = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                        if s_t >= range_start - 1.0 and s_t <= range_end + 1.0 then
                            notes[#notes + 1] = { s = s_t, pitch = p }
                        end
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

----------------------------------------------------------------------
-- Read notes at a specific pitch (for autotune reference)
----------------------------------------------------------------------
function ReadReferenceNotes(midi_take, pitch, range_start, range_end)
    local notes = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p == pitch then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if s_t < range_end and e_t > range_start then
                notes[#notes + 1] = { s = s_t, e = e_t }
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Read all vocal-range notes for auto-tune: pitch-agnostic, deduplicates
-- stacked notes (keeps the lowest pitch when notes share a start time).
function ReadAutoTuneRefNotes(midi_take, range_start, range_end)
    local raw = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if s_t < range_end and e_t > range_start then
                raw[#raw + 1] = { s = s_t, e = e_t, pitch = p }
            end
        end
    end
    -- Sort by start time; within same start time sort lowest pitch first.
    table.sort(raw, function(a, b)
        if math.abs(a.s - b.s) < 0.01 then return a.pitch < b.pitch end
        return a.s < b.s
    end)
    -- Deduplicate: skip any note whose start is within 10 ms of the last kept note.
    local notes = {}
    local last_s = -math.huge
    for _, n in ipairs(raw) do
        if n.s - last_s >= 0.01 then
            notes[#notes + 1] = { s = n.s, e = n.e }
            last_s = n.s
        end
    end
    return notes
end

----------------------------------------------------------------------
-- Delete notes at any of the given pitches that overlap a range
----------------------------------------------------------------------
function ClearNotesAtPitchesInRange(midi_take, pitch_set, range_start, range_end)
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    local removed = 0
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and pitch_set[p] and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if s_t < range_end and e_t > range_start then
                r.MIDI_DeleteNote(midi_take, i)
                removed = removed + 1
            end
        end
    end
    return removed
end

function ClearAllNotesInRange(midi_take, range_start, range_end)
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    local removed = 0
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if s_t < range_end and e_t > range_start then
                r.MIDI_DeleteNote(midi_take, i)
                removed = removed + 1
            end
        end
    end
    return removed
end

----------------------------------------------------------------------
-- Insert notes with per-note pitch
----------------------------------------------------------------------
function InsertNotes(midi_take, notes_with_pitch, vel)
    for _, n in ipairs(notes_with_pitch) do
        local sp = r.MIDI_GetPPQPosFromProjTime(midi_take, n.s)
        local ep = r.MIDI_GetPPQPosFromProjTime(midi_take, n.e)
        r.MIDI_InsertNote(midi_take, false, false, sp, ep, 0, n.pitch, vel, false)
    end
end
