-- Track and action helpers shared by the General, Instrument and Vocal helpers
-- (and the standalone windows that draw their modules).
--
-- Requires globals: r, S. S is each script's own state table: RefreshTrackLists
-- writes S.all_track_list / S.audio_track_list / S.midi_track_list, RunAction
-- writes S.status / S.last_result, so every script that loads this file
-- declares those fields in its defaults.lua.

-- Find the first track whose name matches exactly. Returns the track and index, or nil.
function FindTrackByName(name)
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, n = r.GetTrackName(tr)
        if n == name then return tr, i end
    end
    return nil
end

-- The project track at REAPER index idx, or nil when idx is -1 ("(none)" in
-- TrackCombo), not a number, or past the last track (a stale index after
-- tracks were deleted). Actions call this instead of r.GetTrack directly, then
-- report "Pick a ... track" and return when it gives nil.
function TrackAtIndex(idx)
    if type(idx) ~= 'number' or idx < 0 or idx >= r.CountTracks(0) then return nil end
    return r.GetTrack(0, idx)
end

-- MIDI ticks per quarter note for a take (defensive 960 fallback).
function GetTakePPQPerQN(take)
    local qn_start = r.MIDI_GetPPQPosFromProjQN(take, 0)
    local qn_one   = r.MIDI_GetPPQPosFromProjQN(take, 1)
    local ppq      = qn_one - qn_start
    return ppq > 0 and ppq or 960
end

-- Return bpm, timesig_num, timesig_denom, marker_timepos for the tempo marker
-- that is in effect at project time t.  Falls back to the first marker if all
-- markers are after t.
function GetTempoContextBefore(t)
    local count = r.CountTempoTimeSigMarkers(0)
    if count == 0 then return nil, 'No tempo markers in project.' end
    local best_bpm, best_num, best_denom, best_pos
    for i = 0, count - 1 do
        local ok, timepos, _, _, bpm, num, denom = r.GetTempoTimeSigMarker(0, i)
        if ok and timepos <= t then
            best_bpm, best_num, best_denom, best_pos = bpm, num, denom, timepos
        end
    end
    if not best_bpm then
        local ok, timepos, _, _, bpm, num, denom = r.GetTempoTimeSigMarker(0, 0)
        if ok then
            if num  <= 0 then num  = 4 end
            if denom <= 0 then denom = 4 end
            return bpm, num, denom, timepos
        end
        return nil, 'Could not read tempo markers.'
    end
    -- REAPER returns -1 for num/denom when the time sig is implicit on a marker.
    if best_num  <= 0 then best_num  = 4 end
    if best_denom <= 0 then best_denom = 4 end
    return best_bpm, best_num, best_denom, best_pos
end

-- Does the track hold an audio (non-MIDI) item / a MIDI item? Global: the
-- vocal helper's SetDefaultTracks checks track content with them too.
function TrackHasAudio(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then return true end
    end
    return false
end

function TrackHasMIDI(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then return true end
    end
    return false
end

-- Re-scan the project's tracks into S.all_track_list (every track),
-- S.audio_track_list and S.midi_track_list (tracks holding that kind of item),
-- each entry { idx = REAPER track index, label = 'N: name' } for TrackCombo.
function RefreshTrackLists()
    local n = r.CountTracks(0)
    local all, audio, midi = {}, {}, {}
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        local _, tname = r.GetTrackName(tr)
        if tname == '' then tname = ('Track %d'):format(i + 1) end
        local entry = { idx = i, label = ('%d: %s'):format(i + 1, tname) }
        all[#all + 1] = entry
        if TrackHasAudio(tr) then audio[#audio + 1] = entry end
        if TrackHasMIDI(tr)  then midi[#midi + 1]  = entry end
    end
    S.all_track_list   = all
    S.audio_track_list = audio
    S.midi_track_list  = midi
end

-- Wrap an action function in pcall. On error: balance PreventUIRefresh, run
-- the script's optional RunActionErrorCleanup() (the vocal helper closes the
-- YIN context an action left open there), and report via S.status /
-- S.last_result so the script stays alive.
function RunAction(fn)
    local ok, err = pcall(fn)
    if not ok then
        r.PreventUIRefresh(-1)
        if RunActionErrorCleanup then RunActionErrorCleanup() end
        S.status = 'Error'
        S.last_result = tostring(err)
    end
end
