-- Project-specific REAPER utility helpers
-- FormatTime and GetTimeSelection are provided by lib/reaper_imgui_helpers.lua

-- Returns true if project time t falls within tolerance of a 64th-note grid boundary.
-- Coarser grids (32nd, 16th, 8th, quarter) are all subsets of 64th, so this covers them too.
function IsOnGrid(t)
    local _, _, _, fullbeats, _ = r.TimeMap2_timeToBeats(0, t)
    local frac64 = (fullbeats - math.floor(fullbeats)) * 16   -- position in 64th-note units (0-15.99...)
    return math.abs(frac64 - math.floor(frac64 + 0.5)) < 0.05
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
