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

-- Find a track by exact name plus its first MIDI item/take. Returns
-- track, item, take - track is non-nil when the track exists even if it has
-- no MIDI item, so callers can distinguish "no track" from "no MIDI item".
-- Silent: callers own their status/error messages.
-- Self-contained on purpose: the standalone rock_band_preview_vkr.lua loads
-- helpers.lua but not lib/reaper_midi_helpers.lua (FindFirstMIDIItem).
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

-- MIDI ticks per quarter note for a take (defensive 960 fallback).
function GetTakePPQPerQN(take)
    local qn_start = r.MIDI_GetPPQPosFromProjQN(take, 0)
    local qn_one   = r.MIDI_GetPPQPosFromProjQN(take, 1)
    local ppq      = qn_one - qn_start
    return ppq > 0 and ppq or 960
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

-- Scan track names and pre-select MIDI converter target tracks.
-- Only sets a field when it is still -1 (not yet assigned).
function SetDefaultMIDITracks()
    local name_to_field = {
        ['PART DRUMS']  = 'mc_drum_tgt_idx',
        ['PART GUITAR'] = 'mc_gtr_tgt_idx',
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

local function TrackHasMIDI(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then return true end
    end
    return false
end

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

-- Scan track names and pre-select Pro Keys and 5-Lane Keys difficulty tracks.
-- Only sets a field when it is still -1 (not yet assigned).
function SetDefaultDifficultyTracks()
    local name_to_field = {
        ['PART REAL_KEYS_X'] = 'diff_pk_x_idx',
        ['PART REAL_KEYS_H'] = 'diff_pk_h_idx',
        ['PART REAL_KEYS_M'] = 'diff_pk_m_idx',
        ['PART REAL_KEYS_E'] = 'diff_pk_e_idx',
        ['PART KEYS']        = 'diff_5k_idx',
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

-- Wrap an action function in pcall. On error: balance PreventUIRefresh and
-- report via S.status / S.last_result so the script stays alive.
function RunAction(fn)
    local ok, err = pcall(fn)
    if not ok then
        r.PreventUIRefresh(-1)
        S.status = 'Error'
        S.last_result = tostring(err)
    end
end

-- Poll gate for cached project reads in per-frame draw code. Returns a
-- check(force) function -> true when the caller should re-read its project
-- data: on first call, when forced, when fallback_secs elapsed (safety net -
-- covers state-count collisions across project switches), or when min_secs
-- elapsed AND GetProjectStateChangeCount changed (MIDI edits, mute toggles,
-- undo). min_secs > 0 protects heavy scans from per-frame state-count churn
-- (e.g. dragging notes in a MIDI editor bumps the count every frame).
function MakeProjectPoll(min_secs, fallback_secs)
    local last_count, last_time
    return function(force)
        local now = r.time_precise()
        if force or not last_count
            or now - last_time >= fallback_secs
            or (now - last_time >= min_secs
                and r.GetProjectStateChangeCount() ~= last_count) then
            last_count = r.GetProjectStateChangeCount()
            last_time  = now
            return true
        end
        return false
    end
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
