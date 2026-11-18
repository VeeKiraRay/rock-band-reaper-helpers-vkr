-- Track and action helpers shared by the General, Instrument and Vocal helpers
-- (and the standalone windows that draw their modules), and the settings layers
-- (shipped < my defaults < project, UserDefaultsSetup).
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

-- Poll gate for cached project reads in per-frame draw code (track lists in
-- every window, the Venue views and the Venue Preview). Returns a
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

-- Project-switch check for every window's Loop. Returns a function that is true on
-- the first frame after the active project changed.
--
-- THE POINTER ALONE IS NOT ENOUGH. Opening another project in the same project tab
-- (File > Open, recent projects) keeps REAPER's project pointer, so a pointer check
-- left the previous song's results, track indices and settings on screen. The
-- project file path is compared too. A path appearing where there was none is the
-- first save of a new project, not a switch, so it does not count.
function MakeProjectSwitchCheck()
    local proj, path = r.EnumProjects(-1, '')
    path = path or ''
    return function()
        local p, f = r.EnumProjects(-1, '')
        f = f or ''
        local switched = p ~= proj or (f ~= path and path ~= '')
        proj, path = p, f
        return switched
    end
end

----------------------------------------------------------------------
-- Settings: shipped defaults < my defaults < this project
----------------------------------------------------------------------
-- Each helper's settings.lua turns S into a 'k=v;k=v' string (SerializeSettings) and
-- back (DeserializeSettings). Three layers, lowest first:
--   shipped     - defaults.lua, captured as a string when settings.lua loads;
--   my defaults - REAPER's global ExtState (reaper-extstate.ini: every project reads
--                 it, updates never touch it), holding ONLY the values that differ
--                 from the shipped ones, so a later release's new default still
--                 reaches every value the user never changed;
--   the project - project ext-state, as before (every key, so it wins outright).

-- Ordered { { k, v } } of a settings string; the 'v' format key is skipped. Pure.
function SettingsPairs(str)
    local out = {}
    for k, v in (str or ''):gmatch('([^=;]+)=([^;]*)') do
        if k ~= 'v' then out[#out + 1] = { k, v } end
    end
    return out
end

local function JoinPairs(pairs_list)
    local parts = {}
    for _, p in ipairs(pairs_list) do parts[#parts + 1] = p[1] .. '=' .. p[2] end
    return table.concat(parts, ';')
end

-- The pairs of `current` whose value differs from `shipped` (or that shipped lacks),
-- in current's order, as a settings string. Pure.
function SettingsDiff(shipped, current)
    local base = {}
    for _, p in ipairs(SettingsPairs(shipped)) do base[p[1]] = p[2] end
    local out = {}
    for _, p in ipairs(SettingsPairs(current)) do
        if base[p[1]] ~= p[2] then out[#out + 1] = p end
    end
    return JoinPairs(out)
end

-- `str` without the pairs for which drop(key, value) is true. Pure.
function SettingsFilter(str, drop)
    local out = {}
    for _, p in ipairs(SettingsPairs(str)) do
        if not drop(p[1], p[2]) then out[#out + 1] = p end
    end
    return JoinPairs(out)
end

-- `str` without `key`. Pure.
function SettingsRemoveKey(str, key)
    local out = {}
    for _, p in ipairs(SettingsPairs(str)) do
        if p[1] ~= key then out[#out + 1] = p end
    end
    return JoinPairs(out)
end

local USER_DEFAULTS_KEY = 'settings_v1'

-- My defaults of a helper, stored under '<section>_defaults' (persisted). '' = none.
function UserDefaultsGet(section)
    local s = r.GetExtState(section .. '_defaults', USER_DEFAULTS_KEY)
    return s or ''
end

function UserDefaultsSet(section, str)
    if str == nil or str == '' then
        r.DeleteExtState(section .. '_defaults', USER_DEFAULTS_KEY, true)
    else
        r.SetExtState(section .. '_defaults', USER_DEFAULTS_KEY, str, true)
    end
end

-- Called once at the end of each helper's settings.lua, while S still holds the
-- shipped defaults (defaults.lua loads first in every entry point):
--   section     - the helper's project ext-state section ('RBHelperVKR', ...)
--   serialize   - SerializeSettings
--   deserialize - DeserializeSettings(str, project): project = false for the shipped
--                 and my-defaults strings, so rules for old PROJECTS (migrations) do
--                 not fire on a string that holds only differences
--   labels      - key -> 'Tab > Setting' or { 'Tab > Setting', bool = true }
--   project_key - the key the project's settings are saved under ('settings_v1')
--   project_only(key, value) - true for a value that belongs to one song (a tempo map's
--                 first measure, a picked song key, ...): never one of my defaults,
--                 only saved with a project. Checked on save AND on load, so a value
--                 an earlier version stored is ignored too.
-- Defines the globals the shared Settings block (DrawSettingsPersistence) calls:
--   ProjectSettingsDiffer()  true when this project has saved settings of its own that
--                            are not the current values - they would win over saved
--                            defaults the next time the project is opened
--   ApplyDefaults()          S back to shipped, then my defaults on top
--   SaveUserDefaults()       store the current values that differ; returns how many
--   ClearUserDefaults()      drop them all (S unchanged)
--   ResetUserDefault(key)    drop one, and set that value back to the shipped one
--   UserDefaultRows()        { { key, label, value, shipped } } for the list
function UserDefaultsSetup(spec)
    local shipped = spec.serialize()
    local shipped_v = {}
    for _, p in ipairs(SettingsPairs(shipped)) do shipped_v[p[1]] = p[2] end
    local labels = spec.labels or {}
    local project_only = spec.project_only or function() return false end
    -- My defaults as stored, without anything that belongs to one song.
    local function Mine()
        return SettingsFilter(UserDefaultsGet(spec.section), project_only)
    end

    function ProjectSettingsDiffer()
        local _, str = r.GetProjExtState(0, spec.section, spec.project_key or USER_DEFAULTS_KEY)
        return str ~= nil and str ~= '' and str ~= spec.serialize()
    end

    function ApplyDefaults()
        spec.deserialize(shipped, false)
        local mine = Mine()
        if mine ~= '' then spec.deserialize(mine, false) end
    end

    function SaveUserDefaults()
        local diff = SettingsFilter(SettingsDiff(shipped, spec.serialize()), project_only)
        UserDefaultsSet(spec.section, diff)
        return #SettingsPairs(diff)
    end

    function ClearUserDefaults()
        UserDefaultsSet(spec.section, '')
    end

    function ResetUserDefault(key)
        UserDefaultsSet(spec.section, SettingsRemoveKey(UserDefaultsGet(spec.section), key))
        if shipped_v[key] then spec.deserialize(key .. '=' .. shipped_v[key], false) end
    end

    local function Show(v, bool)
        if v == nil then return '-' end
        if bool then return v == '1' and 'On' or 'Off' end
        return v ~= '' and v or '(empty)'
    end

    function UserDefaultRows()
        local rows = {}
        for _, p in ipairs(SettingsPairs(Mine())) do
            local l = labels[p[1]]
            local name = type(l) == 'table' and l[1] or l or p[1]
            local bool = type(l) == 'table' and l.bool
            rows[#rows + 1] = { key = p[1], label = name, value = Show(p[2], bool),
                                shipped = Show(shipped_v[p[1]], bool) }
        end
        return rows
    end
end
