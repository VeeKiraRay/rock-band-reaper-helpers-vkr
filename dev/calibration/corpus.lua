-- Corpus side of the calibration harness: walking the reference corpus, importing a
-- song's MIDI, and restoring the tempo map afterwards.
--
-- The chart READERS that used to live here now sit in
-- rock_band_general_helper_vkr/difficulty_read.lua, because the shipped Metadata >
-- Difficulty suggestion has to read charts exactly the way the corpus was scored - see
-- that file's header. What is left here is everything the product must never do: corpus
-- discovery, MIDI import, track cleanup, songs.dta walking.
--
-- This file loads them itself rather than leaving it to run_calibration_vkr.lua. That
-- deviates from the entry-point-owns-every-dofile convention on purpose and in one
-- direction only: the calibration entry points encode a locked experiment, and a file
-- move is not a reason to edit them. Same reasoning, and the same debug.getinfo
-- mechanism, as the loaders left at difficulty_score.lua and rank_tiers.lua.
--
-- Requires (globals): ParseSongsDta, SongMidiRelPath (songs_dta.lua),
--                     NormalizeSpans (lib/reaper_difficulty_score.lua),
--                     NormalizeVocalPhrases (lib/reaper_difficulty_score_vocals.lua)
--
-- Status: calibration harness, dev-only.

local _self = debug.getinfo(1, 'S').source:match('^@(.*)$')
local _dir  = _self and _self:match('^(.+[\\/])') or ''
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end

dofile(_up(_up(_dir)) .. 'rock_band_general_helper_vkr/difficulty_read.lua')

----------------------------------------------------------------------
-- Import / cleanup
----------------------------------------------------------------------

-- Same job as fixture_helpers.LoadFixture, but takes an absolute path (that
-- helper hardcodes _FIXTURE_DIR) and snapshots the tempo map per call.
--
-- The tempo snapshot is load-bearing, not hygiene: song MIDIs carry full tempo
-- maps, every density factor is measured in real time, and factor 4 converts
-- through the map. Restoring afterwards keeps song N+1 from inheriting song N's
-- tempo.
local _tempo_snapshot = nil

-- Snapshot/restore logic follows dev/tests/fixture_helpers.lua:22-53, whose
-- tempo functions are file-locals and so cannot be reused directly. Two details
-- there are non-obvious and both are load-bearing:
--
--   * A fresh project has ZERO explicit tempo markers (REAPER applies an
--     implicit 120/4-4 instead), so a snapshot taken then has nothing to restore
--     and index 0 keeps whatever the first import set. Materialize the default
--     into a real marker before the first snapshot.
--   * REAPER refuses to delete the LAST tempo marker, so index 0 must be
--     overwritten in place rather than deleted.
local function EnsureDefaultTempoMarker()
    if r.CountTempoTimeSigMarkers(0) == 0 then
        r.AddTempoTimeSigMarker(0, 0, 120, 4, 4, false)
    end
end

local function SnapshotTempo()
    local snap = {}
    for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
        local ok, timepos, _, _, bpm, num, denom, linear = r.GetTempoTimeSigMarker(0, i)
        if ok then
            snap[#snap + 1] = { timepos = timepos, bpm = bpm,
                                num = num, denom = denom, linear = linear }
        end
    end
    return snap
end

local function RestoreTempo(snap)
    for i = r.CountTempoTimeSigMarkers(0) - 1, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, i)
    end
    if snap[1] then
        r.SetTempoTimeSigMarker(0, 0, snap[1].timepos, -1, -1,
            snap[1].bpm, snap[1].num, snap[1].denom, snap[1].linear)
    end
    for i = 2, #snap do
        local m = snap[i]
        r.AddTempoTimeSigMarker(0, m.timepos, m.bpm, m.num, m.denom, m.linear)
    end
    r.UpdateTimeline()
end

-- Returns first_track_idx, n_tracks_added.
function ImportSongMidi(abs_path)
    local n_before = r.CountTracks(0)
    -- Deselect everything: InsertMedia(path, 0) means "add to current track" and
    -- only creates tracks when there is nothing selected to add to.
    for i = 0, n_before - 1 do
        r.SetTrackSelected(r.GetTrack(0, i), false)
    end
    r.SetEditCurPos(0, false, false)
    EnsureDefaultTempoMarker()
    _tempo_snapshot = _tempo_snapshot or SnapshotTempo()
    r.InsertMedia(abs_path, 0)
    return n_before, r.CountTracks(0) - n_before
end

-- Delete every track from from_idx up, and restore the pre-import tempo map.
--
-- Must be robust: leftover tracks poison every later import (see the comment on
-- EnableFixtureAutoCleanup in dev/tests/fixture_helpers.lua - one failure
-- cascades into a run of misleading "created no tracks" results).
function CleanupImport(from_idx)
    for i = r.CountTracks(0) - 1, from_idx, -1 do
        local tr = r.GetTrack(0, i)
        if tr then r.DeleteTrack(tr) end
    end
    if _tempo_snapshot then
        RestoreTempo(_tempo_snapshot)
        _tempo_snapshot = nil
    end
end

----------------------------------------------------------------------
-- Corpus walk
----------------------------------------------------------------------

local function ReadFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local text = f:read('a')
    f:close()
    return text
end

local function FileExists(path)
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

-- Recursively collect every 'songs.dta' under root, at any depth (the corpus has
-- single-song packs at the top level and multi-song packs one folder deeper).
--
-- Matches the filename EXACTLY: folder 3A6A6D27... also contains a duplicate
-- 'songs(0).dta', and reading both would process that song twice.
local function CollectDtaPaths(root, out, depth)
    out   = out or {}
    depth = depth or 0
    if depth > 4 then return out end

    -- Two layouts. The original corpus nests a pack under Root/songs/; the low-end set
    -- added later is flat, with songs.dta and every MIDI in one folder. Probing both is
    -- additive - a folder can only match one of them - so the original walk is unchanged.
    for _, rel in ipairs({ 'Root/songs/songs.dta', 'songs.dta' }) do
        local candidate = root .. rel
        if FileExists(candidate) then out[#out + 1] = candidate end
    end

    local i = 0
    while true do
        local sub = r.EnumerateSubdirectories(root, i)
        if not sub then break end
        CollectDtaPaths(root .. sub .. '/', out, depth + 1)
        i = i + 1
    end
    return out
end

-- Every song in the corpus, as a flat list of
--   { shortname, origin, ranks, genre, vocal_parts, midi_path }
-- Songs whose MIDI is missing are returned with midi_path = nil so the caller
-- can report them rather than silently skipping.
function WalkCorpus(root)
    local songs = {}
    for _, dta in ipairs(CollectDtaPaths(root)) do
        -- Strip whichever layout's dta path this is, leaving the pack root.
        local pack = dta:gsub('Root/songs/songs%.dta$', ''):gsub('songs%.dta$', '')
        local text = ReadFile(dta)
        if text then
            for _, e in ipairs(ParseSongsDta(text)) do
                -- Nested first, then flat. A pack matches one or the other; trying both
                -- costs a stat call and keeps the caller free of layout knowledge.
                local mid = pack .. SongMidiRelPath(e.shortname)
                if not FileExists(mid) then
                    mid = pack .. SongMidiRelPathFlat(e.shortname)
                end
                songs[#songs + 1] = {
                    shortname   = e.shortname,
                    origin      = e.origin,
                    genre       = e.genre,
                    vocal_parts = e.vocal_parts,
                    ranks       = e.ranks,
                    midi_path   = FileExists(mid) and mid or nil,
                    pack        = pack,
                }
            end
        end
    end
    table.sort(songs, function(a, b) return a.shortname < b.shortname end)
    return songs
end
