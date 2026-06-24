-- Shared helpers for fixture-based MIDI tests.
-- Requires: r (reaper global), _FIXTURE_DIR (set by the runner before calling tests)

local function DeselectAllTracks()
    for i = 0, r.CountTracks(0) - 1 do
        r.SetTrackSelected(r.GetTrack(0, i), false)
    end
end

-- Import a MIDI file from _FIXTURE_DIR. Returns (first_abs_idx, n_tracks_added).
-- Deselects all tracks first so REAPER creates new tracks for each MIDI track.
function LoadFixture(filename)
    local path = _FIXTURE_DIR .. filename
    local n_before = r.CountTracks(0)
    DeselectAllTracks()
    r.SetEditCurPos(0, false, false)
    r.InsertMedia(path, 0)
    local n_after = r.CountTracks(0)
    return n_before, n_after - n_before
end

-- Delete all tracks at absolute index >= from_idx.
function CleanupFixture(from_idx)
    local n = r.CountTracks(0)
    for i = n - 1, from_idx, -1 do
        r.DeleteTrack(r.GetTrack(0, i))
    end
end

-- Find a track whose name contains pattern (case-insensitive plain search).
-- Searches from from_idx (default 0). Returns absolute track index or nil.
function FindFixtureTrack(pattern, from_idx)
    local pat = pattern:lower()
    for i = (from_idx or 0), r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        if name:lower():find(pat, 1, true) then return i end
    end
    return nil
end

-- Create an empty named track at the end of the project. Returns absolute index.
function CreateEmptyFixtureTrack(name)
    local n = r.CountTracks(0)
    r.InsertTrackAtIndex(n, true)
    local tr = r.GetTrack(0, n)
    if name then r.GetSetMediaTrackInfo_String(tr, 'P_NAME', name, true) end
    return n
end
