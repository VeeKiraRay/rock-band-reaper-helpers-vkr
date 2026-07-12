-- Shared core for the vocal note snap-to-playhead quick actions.
-- Not a bindable action itself — loaded via dofile by the *_vkr.lua wrappers.
-- Requires global: r (reaper), set by the wrapper before dofile.

local RB3_MIN_PITCH = 36  -- C1 (matches rock_band_vocal_helper_vkr/defaults.lua)
local RB3_MAX_PITCH = 84  -- C5
local MAX_DIST      = 1.0 -- s; ignore notes farther than this from the cursor

-- mode: 'auto'  — closer edge decides: start closer → move note, end closer → stretch
--       'start' — always move the note so it starts at the cursor (length preserved)
--       'end'   — always stretch the note so it ends at the cursor
-- Testable core: operates on an explicit take and cursor time (project s).
-- When a note is moved, lyric events (type 5) at its start move with it.
-- Returns 'moved' | 'stretched' | 'selected' (already in place), or nil if
-- no note qualified.
function VocalNoteSnapInTake(take, cursor, mode)
    -- Find the target note: on the cursor wins outright, otherwise nearest
    -- edge within MAX_DIST. Ties keep the lowest index.
    local _, notecnt = r.MIDI_CountEvts(take)
    local best_idx, best_dist
    for i = 0, notecnt - 1 do
        local ok, _, _, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and pitch >= RB3_MIN_PITCH and pitch <= RB3_MAX_PITCH then
            local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
            -- In 'end' mode the note's end must land after its start
            if not (mode == 'end' and s >= cursor) then
                local dist
                if s <= cursor and cursor <= e then
                    dist = 0
                else
                    dist = math.min(math.abs(s - cursor), math.abs(e - cursor))
                end
                if dist <= MAX_DIST and (not best_dist or dist < best_dist) then
                    best_idx, best_dist = i, dist
                    if dist == 0 then break end
                end
            end
        end
    end
    if not best_idx then return end

    local _, _, mute, sppq, eppq, chan, pitch, vel = r.MIDI_GetNote(take, best_idx)
    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)

    local move = (mode == 'start')
        or (mode == 'auto' and math.abs(s - cursor) <= math.abs(e - cursor))
    local new_s, new_e, verb
    if move then
        new_s, new_e, verb = cursor, cursor + (e - s), 'moved'
    else
        new_s, new_e, verb = s, cursor, 'stretched'
    end

    local new_sppq = r.MIDI_GetPPQPosFromProjTime(take, new_s)
    local new_eppq = r.MIDI_GetPPQPosFromProjTime(take, new_e)
    if new_sppq == sppq and new_eppq == eppq then
        -- Already in place: just make it the sole selected note, no undo point
        r.MIDI_SelectAll(take, false)
        r.MIDI_SetNote(take, best_idx, true, nil, nil, nil, nil, nil, nil, false)
        return 'selected'
    end

    local item  = r.GetMediaItemTake_Item(take)
    local track = r.GetMediaItemTake_Track(take)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_SelectAll(take, false)
    if move then
        -- Lyric events (type 5) sit at the note start; drag them along.
        -- Delete in reverse (indices shift), reinsert at the new start.
        local lyrics = {}
        local _, _, _, textcnt = r.MIDI_CountEvts(take)
        for i = textcnt - 1, 0, -1 do
            local ok, tsel, tmute, tppq, ttype, msg = r.MIDI_GetTextSysexEvt(take, i)
            if ok and ttype == 5 and math.abs(tppq - sppq) < 1 then
                lyrics[#lyrics + 1] = { sel = tsel, mute = tmute, msg = msg }
                r.MIDI_DeleteTextSysexEvt(take, i)
            end
        end
        for _, ev in ipairs(lyrics) do
            r.MIDI_InsertTextSysexEvt(take, ev.sel, ev.mute, new_sppq, 5, ev.msg, false)
        end
    end
    r.MIDI_DeleteNote(take, best_idx)
    r.MIDI_InsertNote(take, true, mute, new_sppq, new_eppq, chan, pitch, vel, false)
    r.Undo_EndBlock2(0, ('Snap note to playhead (%s)'):format(verb), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    return verb
end

-- Hotkey entry point: targets the active MIDI editor take at the edit cursor.
function VocalNoteSnap(mode)
    local editor = r.MIDIEditor_GetActive()
    local take   = editor and r.MIDIEditor_GetTake(editor)
    if not take then return end
    return VocalNoteSnapInTake(take, r.GetCursorPosition(), mode)
end
