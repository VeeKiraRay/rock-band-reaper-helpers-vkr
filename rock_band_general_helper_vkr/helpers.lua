-- Utility functions shared across multiple modules
-- Requires: S, r (globals); FindTrackByName (lib/reaper_helper_common.lua)

-- Find a track by exact name plus its first MIDI item/take. Returns
-- track, item, take - track is non-nil when the track exists even if it has
-- no MIDI item, so callers can distinguish "no track" from "no MIDI item".
-- Silent: callers own their status/error messages.
-- Self-contained on purpose: the standalone rock_band_preview_vkr.lua loads
-- helpers.lua but not lib/reaper_midi_helpers.lua (FindFirstMIDIItem).
-- It does load lib/reaper_helper_common.lua, for FindTrackByName.
function FindNamedTrackMIDI(name)
    local track = FindTrackByName(name)
    if not track then return nil, nil, nil end
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local it = r.GetTrackMediaItem(track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then return track, it, tk end
    end
    return track, nil, nil
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

-- Return the project time (seconds) at the start of measure_num (1-based).
function GetMeasureStartTime(measure_num, num, denom)
    local qn_per_measure = num * (4.0 / (denom or 4))
    local qn_pos = (measure_num - 1) * qn_per_measure
    return r.TimeMap2_beatsToTime(0, qn_pos)
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
