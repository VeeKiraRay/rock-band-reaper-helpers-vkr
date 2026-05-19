-- Utility functions shared across multiple modules
-- Requires: S, r (globals)

-- Find the first track whose name matches exactly. Returns the track and index, or nil.
function FindTrackByName(name)
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, n = r.GetTrackName(tr)
        if n == name then return tr, i end
    end
    return nil
end

-- Scan track names and pre-select the drum audio tracks.
-- Only sets a field when it is still -1 (not yet assigned).
function SetDefaultTempoTracks()
    local name_to_field = {
        ['KICK AUDIO']   = 'tm_kick_idx',
        ['SNARE AUDIO']  = 'tm_snare_idx',
        ['KIT AUDIO']    = 'tm_kit_idx',
    }
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetTrackName(tr)
        local field = name_to_field[name]
        if field and S[field] == -1 then
            S[field] = i
        end
    end
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

-- Return the project time (seconds) at the start of measure_num (1-based).
function GetMeasureStartTime(measure_num, num, denom)
    local qn_per_measure = num * (4.0 / (denom or 4))
    local qn_pos = (measure_num - 1) * qn_per_measure
    return r.TimeMap2_beatsToTime(0, qn_pos)
end

local function TrackHasAudio(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then return true end
    end
    return false
end

function RefreshTrackLists()
    local n = r.CountTracks(0)
    local all, audio = {}, {}
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        local _, tname = r.GetTrackName(tr)
        if tname == '' then tname = ('Track %d'):format(i + 1) end
        local entry = { idx = i, label = ('%d: %s'):format(i + 1, tname) }
        all[#all + 1] = entry
        if TrackHasAudio(tr) then audio[#audio + 1] = entry end
    end
    S.all_track_list   = all
    S.audio_track_list = audio
end

-- Return a list of audio (non-MIDI) items on a track.
function GetAudioItems(track)
    local result = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
            result[#result + 1] = item
        end
    end
    return result
end
