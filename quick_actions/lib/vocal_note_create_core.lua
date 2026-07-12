-- Shared core for the vocal note create-at-playhead quick action.
-- Not a bindable action itself — loaded via dofile by the *_vkr.lua wrapper.
-- Requires global: r (reaper), set by the wrapper before dofile.

local RB3_MIN_PITCH = 36  -- C1 (matches rock_band_vocal_helper_vkr/defaults.lua)
local RB3_MAX_PITCH = 84  -- C5
local DEFAULT_PITCH = 60  -- C3 in RB octave numbering; used when take has no vocal notes
local VEL           = 96

-- Testable core: operates on an explicit take and cursor time (project s).
-- Creates a one-grid-unit note at the cursor, pitch copied from the nearest
-- vocal-range note (DEFAULT_PITCH if none), clamped so it never overlaps the
-- next note. Returns 'created', or nil if the cursor is inside an existing
-- note or there is no room.
function VocalNoteCreateInTake(take, cursor)
    local _, notecnt = r.MIDI_CountEvts(take)
    local pitch, best_dist = DEFAULT_PITCH, nil
    local next_sppq  -- start PPQ of the first note at/after the cursor
    for i = 0, notecnt - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
            if s <= cursor and cursor < e then return end  -- would overlap
            local dist = math.min(math.abs(s - cursor), math.abs(e - cursor))
            if not best_dist or dist < best_dist then
                pitch, best_dist = p, dist
            end
            if s >= cursor and (not next_sppq or sppq < next_sppq) then
                next_sppq = sppq
            end
        end
    end

    -- One grid unit long, via QN so it is tempo- and PPQ-resolution-safe
    local sppq    = r.MIDI_GetPPQPosFromProjTime(take, cursor)
    local grid_qn = r.MIDI_GetGrid(take)
    local eppq    = r.MIDI_GetPPQPosFromProjQN(take,
                        r.MIDI_GetProjQNFromPPQPos(take, sppq) + grid_qn)
    if next_sppq and next_sppq < eppq then eppq = next_sppq end
    if eppq <= sppq then return end  -- next note starts at the cursor

    local item  = r.GetMediaItemTake_Item(take)
    local track = r.GetMediaItemTake_Track(take)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_SelectAll(take, false)
    r.MIDI_InsertNote(take, true, false, sppq, eppq, 0, pitch, VEL, false)
    r.Undo_EndBlock2(0, 'Create note at playhead', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    return 'created'
end

-- Hotkey entry point: targets the active MIDI editor take at the edit cursor.
function VocalNoteCreate()
    local editor = r.MIDIEditor_GetActive()
    local take   = editor and r.MIDIEditor_GetTake(editor)
    if not take then return end
    return VocalNoteCreateInTake(take, r.GetCursorPosition())
end
