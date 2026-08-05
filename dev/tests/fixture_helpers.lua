-- Shared helpers for fixture-based MIDI tests.
-- Requires: r (reaper global), _FIXTURE_DIR (set by the runner before calling tests)

local function DeselectAllTracks()
    for i = 0, r.CountTracks(0) - 1 do
        r.SetTrackSelected(r.GetTrack(0, i), false)
    end
end

-- InsertMedia can pull a MIDI fixture's embedded tempo/time-sig track into the
-- project's *global* tempo map, and that map is never track-scoped -- deleting
-- the fixture's tracks (all CleanupFixture does) leaves it behind for every
-- later suite's PPQ<->time math. Snapshot/restore it around each fixture load.
local _tempo_snapshot = nil

-- A fresh project has zero explicit tempo markers (REAPER applies an implicit
-- 120bpm/4-4 default instead) -- CountTempoTimeSigMarkers reports 0, so
-- SnapshotTempoMap has nothing to restore to and index 0 is left however the
-- first fixture's import set it. Materialize the implicit default into a real
-- marker before the first snapshot ever happens, so there's always something
-- concrete to restore to. Idempotent: no-op once any marker exists.
local function EnsureDefaultTempoMarker()
    if r.CountTempoTimeSigMarkers(0) == 0 then
        r.AddTempoTimeSigMarker(0, 0, 120, 4, 4, false)
    end
end

local function SnapshotTempoMap()
    local snap = {}
    for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
        local ok, timepos, _, _, bpm, num, denom, linear = r.GetTempoTimeSigMarker(0, i)
        if ok then
            snap[#snap + 1] = { timepos = timepos, bpm = bpm, num = num, denom = denom, linear = linear }
        end
    end
    return snap
end

local function RestoreTempoMap(snap)
    -- Index 0 is the project's always-present root marker; overwrite it
    -- in place rather than deleting it (REAPER refuses to delete the last one).
    for i = r.CountTempoTimeSigMarkers(0) - 1, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, i)
    end
    if snap[1] then
        r.SetTempoTimeSigMarker(0, 0, snap[1].timepos, -1, -1, snap[1].bpm, snap[1].num, snap[1].denom, snap[1].linear)
    end
    for i = 2, #snap do
        local m = snap[i]
        r.AddTempoTimeSigMarker(0, m.timepos, m.bpm, m.num, m.denom, m.linear)
    end
    r.UpdateTimeline()
end

-- Import a MIDI file from _FIXTURE_DIR. Returns (first_abs_idx, n_tracks_added).
-- Deselects all tracks first so REAPER creates new tracks for each MIDI track.
--
-- Fixture caveat: these files are truncated excerpts of real charts, so most of
-- them end with note-ons that have no matching note-off (verifiable with any
-- MIDI parser). REAPER imports each of those as a note whose end sits at ppq 0
-- -- an end *before* its start. Any test that asserts on note lengths, or on
-- what a copy/transform did to a note's end, must skip notes where e <= s.
function LoadFixture(filename)
    local path = _FIXTURE_DIR .. filename
    local n_before = r.CountTracks(0)
    DeselectAllTracks()
    r.SetEditCurPos(0, false, false)
    EnsureDefaultTempoMarker()
    -- Keep the pre-import snapshot across multiple LoadFixture calls sharing
    -- one later CleanupFixture (e.g. two fixtures loaded before one cleanup).
    _tempo_snapshot = _tempo_snapshot or SnapshotTempoMap()
    r.InsertMedia(path, 0)
    local n_after = r.CountTracks(0)
    return n_before, n_after - n_before
end

-- Delete all tracks at absolute index >= from_idx, and restore the tempo map
-- to whatever it was before the most recent LoadFixture (no-op if the tracks
-- being cleaned up came from CreateEmptyFixtureTrack instead).
function CleanupFixture(from_idx)
    local n = r.CountTracks(0)
    for i = n - 1, from_idx, -1 do
        r.DeleteTrack(r.GetTrack(0, i))
    end
    if _tempo_snapshot then
        RestoreTempoMap(_tempo_snapshot)
        _tempo_snapshot = nil
    end
end

-- Install a Test.after hook that returns the project to `baseline` tracks and
-- drops any pending tempo snapshot, so one aborted test cannot poison the rest
-- of the suite.
--
-- Why this is needed: a test that errors never reaches its own CleanupFixture,
-- so its tracks stay in the project. LoadFixture's InsertMedia(path, 0) means
-- "add to current track", and it only creates new tracks when there is no
-- track to add to -- so once leftovers exist, every later LoadFixture silently
-- appends to an existing track and reports 0 tracks created. The result is a
-- single real failure followed by a cascade of misleading
-- "<fixture> created no tracks" errors that hide it.
--
-- After a passing test this is a no-op: the test's own CleanupFixture already
-- brought the count back to baseline.
function EnableFixtureAutoCleanup()
    local baseline = r.CountTracks(0)
    Test.after = function()
        for i = r.CountTracks(0) - 1, baseline, -1 do
            local tr = r.GetTrack(0, i)
            if tr then r.DeleteTrack(tr) end
        end
        if _tempo_snapshot then
            RestoreTempoMap(_tempo_snapshot)
            _tempo_snapshot = nil
        end
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
