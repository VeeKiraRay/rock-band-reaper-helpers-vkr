-- MIDI reading, clearing, and insertion helpers (shared library)
-- Requires globals: r (reaper)

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
function ReadAutoTuneRefNotes(midi_take, range_start, range_end, min_pitch, max_pitch)
    local raw = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p >= min_pitch and p <= max_pitch then
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
        if ok and pitch_set[p] then
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

function ClearNotesInRange(midi_take, range_start, range_end, min_pitch, max_pitch)
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    local removed = 0
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p >= min_pitch and p <= max_pitch then
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
-- Read all notes in a PPQ range from a take, optionally restricted to a
-- pitch range (min_pitch/max_pitch default to 0/127 - no filtering).
-- Returns array of {rel_s, rel_e, pitch} sorted by rel_s,
-- where rel_s/rel_e are PPQ offsets from start_ppq.
----------------------------------------------------------------------
function ReadMIDIPatternFromTake(take, start_ppq, end_ppq, min_pitch, max_pitch)
    min_pitch = min_pitch or 0
    max_pitch = max_pitch or 127
    local notes = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and sppq >= start_ppq and sppq < end_ppq and p >= min_pitch and p <= max_pitch then
            notes[#notes + 1] = { rel_s = sppq - start_ppq, rel_e = eppq - start_ppq, pitch = p }
        end
    end
    table.sort(notes, function(a, b) return a.rel_s < b.rel_s end)
    return notes
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

----------------------------------------------------------------------
-- Replace the notes of the pitch ranges ({ { lo, hi }... }) that START in [clear_s,
-- clear_e) (seconds) - or, with clear_s nil, every such note in the take - with `notes`
-- ({ s, e, pitch } in seconds, written on channel 1 at velocity vel), in one
-- MIDI_GetAllEvts / MIDI_SetAllEvts round trip: far faster than per-note deletes and
-- inserts on a busy take. By start, not by overlap (ClearNotesInRange's rule), so a
-- sustain from before the selection is kept rather than deleted and never regenerated.
-- Every other event - other pitches, CCs, text, sysex, the take's end marker - is written
-- back unchanged and in its original order. (Difficulty > Generate's 'batched' /
-- 'per_note' timing modes still clear by overlap.)
-- Buffer format (ReaScript API): per event an int32 offset in ticks from the previous
-- event, a flag byte, an int32 length and the message bytes.
-- Returns false when the take could not be read (the caller falls back to batched).
function ReplaceNotesBulk(take, clear_s, clear_e, ranges, notes, vel)
    local ok, buf = r.MIDI_GetAllEvts(take, '')
    if not ok or type(buf) ~= 'string' then return false end
    local whole = clear_s == nil
    local s_ppq = not whole and r.MIDI_GetPPQPosFromProjTime(take, clear_s) or 0
    local e_ppq = not whole and r.MIDI_GetPPQPosFromProjTime(take, clear_e) or 0
    local owned = {}
    for _, rg in ipairs(ranges) do
        for p = rg[1], rg[2] do owned[p] = true end
    end

    -- Half a tick each way: a note exactly on the selection's start is in, one exactly on
    -- its end is out, whatever the float rounding.
    local function InWindow(at) return whole or (at >= s_ppq - 0.5 and at < e_ppq - 0.5) end

    local evs, open, drop = {}, {}, {}
    -- A zero-length note is stored with its note-off FIRST, at the note-on's own tick, so
    -- first-on-first-off pairing never matched it: the old note stayed, and the new one
    -- written at that position doubled every pitch (rb_pro_keys.mid's last chord, in
    -- REAPER: [E2+E2+G2+G2+B2+B2]). An off with nothing open waits here for an on at the
    -- same tick.
    local early_off = {}
    local pos, ppq, n = 1, 0, #buf
    while pos <= n do
        local off, flag, msg
        off, flag, msg, pos = string.unpack('<i4Bs4', buf, pos)
        ppq = ppq + off
        local k = #evs + 1
        evs[k] = { ppq = ppq, flag = flag, msg = msg, cls = 1, ord = k }
        if #msg >= 3 then
            local st = msg:byte(1)
            local typ, pitch, v = st & 0xF0, msg:byte(2), msg:byte(3)
            if (typ == 0x90 or typ == 0x80) and owned[pitch] then
                local key = (st & 0x0F) * 128 + pitch
                if typ == 0x90 and v > 0 then
                    local eo = early_off[key]
                    if eo and evs[eo].ppq == ppq then
                        -- The zero-length note this early off belongs to.
                        early_off[key] = nil
                        if InWindow(ppq) then drop[eo], drop[k] = true, true end
                    else
                        open[key] = open[key] or {}
                        table.insert(open[key], k)
                    end
                else
                    -- First on, first off - the pairing REAPER's note list uses.
                    local q = open[key]
                    local on = q and table.remove(q, 1)
                    if on then
                        if InWindow(evs[on].ppq) then drop[on], drop[k] = true, true end
                    else
                        early_off[key] = k
                    end
                end
            end
        end
    end
    -- A note-on that never closed, inside the window: nothing may stay behind to pair with
    -- a note-off written below.
    for _, q in pairs(open) do
        for _, k in ipairs(q) do if InWindow(evs[k].ppq) then drop[k] = true end end
    end

    local out = {}
    for k, ev in ipairs(evs) do if not drop[k] then out[#out + 1] = ev end end
    -- New notes: at one tick, a new note-off goes before the old events there and a new
    -- note-on after them, so a new note never swallows an old one's end or start.
    local m = #evs
    for _, nt in ipairs(notes) do
        local sp = math.floor(r.MIDI_GetPPQPosFromProjTime(take, nt.s) + 0.5)
        local ep = math.floor(r.MIDI_GetPPQPosFromProjTime(take, nt.e) + 0.5)
        m = m + 1
        out[#out + 1] = { ppq = sp, flag = 0, msg = string.char(0x90, nt.pitch, vel), cls = 2, ord = m }
        m = m + 1
        out[#out + 1] = { ppq = ep, flag = 0, msg = string.char(0x80, nt.pitch, 0), cls = 0, ord = m }
    end
    table.sort(out, function(a, b)
        if a.ppq ~= b.ppq then return a.ppq < b.ppq end
        if a.cls ~= b.cls then return a.cls < b.cls end
        return a.ord < b.ord
    end)

    local parts, last = {}, 0
    for i, ev in ipairs(out) do
        parts[i] = string.pack('<i4Bs4', ev.ppq - last, ev.flag, ev.msg)
        last = ev.ppq
    end
    r.MIDI_SetAllEvts(take, table.concat(parts))
    return true
end
