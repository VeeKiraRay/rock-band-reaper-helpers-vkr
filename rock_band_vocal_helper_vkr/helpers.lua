-- Project-specific REAPER utility helpers
-- FormatTime and GetTimeSelection are provided by lib/reaper_imgui_helpers.lua;
-- GetTakePPQPerQN, TrackHasAudio/TrackHasMIDI, RefreshTrackLists and RunAction
-- by lib/reaper_helper_common.lua.

-- Returns true if project time t falls within tolerance of a 64th-note grid boundary.
-- Coarser grids (32nd, 16th, 8th, quarter) are all subsets of 64th, so this covers them too.
function IsOnGrid(t)
    local _, _, _, fullbeats, _ = r.TimeMap2_timeToBeats(0, t)
    local frac64 = (fullbeats - math.floor(fullbeats)) * 16   -- position in 64th-note units (0-15.99...)
    return math.abs(frac64 - math.floor(frac64 + 0.5)) < 0.05
end

function SetDefaultTracks()
    local n = r.CountTracks(0)
    local audio_found = false
    for _, name in ipairs({ 'VOCALS AUDIO', 'DRYVOX1' }) do
        if not audio_found then
            for i = 0, n - 1 do
                local tr = r.GetTrack(0, i)
                local _, tname = r.GetTrackName(tr)
                if tname == name and TrackHasAudio(tr) then
                    S.audio_idx = i
                    audio_found = true
                    break
                end
            end
        end
    end
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        local _, tname = r.GetTrackName(tr)
        if tname == 'PART VOCALS' and TrackHasMIDI(tr) then
            S.midi_idx = i
            break
        end
    end

    -- Harmony source: prefer 'PART VOCALS', fall back to 'HARM1'
    local harm_src_found = false
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        local _, tname = r.GetTrackName(tr)
        if tname == 'PART VOCALS' and TrackHasMIDI(tr) then
            S.harm_src_idx = i
            harm_src_found = true
            break
        end
    end
    if not harm_src_found then
        for i = 0, n - 1 do
            local tr = r.GetTrack(0, i)
            local _, tname = r.GetTrackName(tr)
            if tname == 'HARM1' and TrackHasMIDI(tr) then
                S.harm_src_idx = i
                break
            end
        end
    end

    -- Tuner Harmony readout: the lead chart it cancels, HARM1 first, else PART VOCALS.
    S.tuner_lead_idx = -1
    for _, name in ipairs({ 'HARM1', 'PART VOCALS' }) do
        if S.tuner_lead_idx < 0 then
            for i = 0, n - 1 do
                local tr = r.GetTrack(0, i)
                local _, tname = r.GetTrackName(tr)
                if tname == name and TrackHasMIDI(tr) then S.tuner_lead_idx = i; break end
            end
        end
    end

    -- Harmony destinations: name-only match (tracks may start empty)
    for _, pair in ipairs({
        { field = 'harm_dst1_idx', name = 'HARM1' },
        { field = 'harm_dst2_idx', name = 'HARM2' },
        { field = 'harm_dst3_idx', name = 'HARM3' },
    }) do
        for i = 0, n - 1 do
            local tr = r.GetTrack(0, i)
            local _, tname = r.GetTrackName(tr)
            if tname == pair.name then S[pair.field] = i; break end
        end
    end
end

-- Called by RunAction (lib/reaper_helper_common.lua) when an action errors:
-- close any YIN context the action left open, so its audio accessor does not
-- hold the source file until REAPER exits.
function RunActionErrorCleanup()
    if S.action_yctx then
        local ctx_to_close = S.action_yctx
        S.action_yctx = nil
        CloseYINContext(ctx_to_close)
    end
end

function AutoDetectLyricsFile()
    local proj_path = r.GetProjectPath('')
    if not proj_path or proj_path == '' then return false end
    local sep = (proj_path:sub(-1) == '/' or proj_path:sub(-1) == '\\') and '' or '/'
    local candidate = proj_path .. sep .. 'lyrics.txt'
    local f = io.open(candidate, 'r')
    if f then
        f:close()
        S.lyrics_path = candidate
        return true
    end
    return false
end
