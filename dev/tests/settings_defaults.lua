-- Tests for the settings layers: shipped defaults < my defaults < this project
-- (lib/reaper_helper_common.lua: SettingsPairs / SettingsDiff / SettingsRemoveKey /
-- UserDefaultsSetup) and the General Helper's settings.lua on top of them.
--
-- REAPER's ExtState and project ext-state calls are replaced by an in-memory store for
-- the whole suite and restored at the end, so the tester's own My defaults and the open
-- project are never read or written - and the suite also runs offline.

local real = { GetExtState = r.GetExtState, SetExtState = r.SetExtState,
               DeleteExtState = r.DeleteExtState, GetProjExtState = r.GetProjExtState }
local EXT, PROJ = {}, {}
r.GetExtState = function(sec, key) return EXT[sec .. '/' .. key] or '' end
r.SetExtState = function(sec, key, val) EXT[sec .. '/' .. key] = val end
r.DeleteExtState = function(sec, key) EXT[sec .. '/' .. key] = nil end
r.GetProjExtState = function(_, sec, key)
    local v = PROJ[sec .. '/' .. key]
    return v and 1 or 0, v or ''
end

local function Expect(got, want, label)
    Test.expect(got == want, (label or '') .. ': got "' .. tostring(got) .. '", want "' .. tostring(want) .. '"')
end

----------------------------------------------------------------------
Test.section('Settings strings')
----------------------------------------------------------------------

Test.it('SettingsPairs: in order, the v= format key skipped, empty values kept', function()
    local p = SettingsPairs('v=1;a=1;b=;c=x y')
    Expect(#p, 3, 'count')
    Expect(p[1][1] .. '=' .. p[1][2] .. ' ' .. p[2][1] .. '=' .. p[2][2] .. ' ' .. p[3][2], 'a=1 b= x y')
    Expect(#SettingsPairs(''), 0, 'empty string')
    Expect(#SettingsPairs(nil), 0, 'nil')
end)

Test.it('SettingsDiff: only values that differ or the shipped string lacks', function()
    Expect(SettingsDiff('v=1;a=1;b=2;c=3', 'v=1;a=1;b=5;c=3;d=7'), 'b=5;d=7')
    Expect(SettingsDiff('v=1;a=1', 'v=1;a=1'), '', 'nothing changed')
    Expect(SettingsDiff('a=1;b=2', 'b=9;a=0'), 'b=9;a=0', "current's order")
end)

Test.it('SettingsRemoveKey', function()
    Expect(SettingsRemoveKey('a=1;b=2;c=3', 'b'), 'a=1;c=3')
    Expect(SettingsRemoveKey('a=1', 'x'), 'a=1', 'absent key')
end)

----------------------------------------------------------------------
Test.section('UserDefaultsSetup - layers')
----------------------------------------------------------------------

-- A small helper: three settings, its deserialize logging the project flag.
local FS = { a = 1, b = true, c = 'x' }
local flags = {}
local function FSerialize()
    return table.concat({ 'v=1', 'a=' .. FS.a, 'b=' .. (FS.b and '1' or '0'), 'c=' .. FS.c }, ';')
end
local function FDeserialize(str, project)
    flags[#flags + 1] = project and 'P' or 'd'
    for k, v in str:gmatch('([^=;]+)=([^;]*)') do
        if k == 'a' then FS.a = tonumber(v) or FS.a
        elseif k == 'b' then FS.b = (v == '1')
        elseif k == 'c' then FS.c = v end
    end
end
local function Setup()
    UserDefaultsSetup({ section = 'TestHelper', project_key = 'settings_v1',
                        serialize = FSerialize, deserialize = FDeserialize,
                        labels = { a = 'Tab: A', b = { 'Tab: B', bool = true } } })
end
local function State() return FS.a .. '/' .. tostring(FS.b) .. '/' .. FS.c end

Test.it('Save as my defaults stores only what differs from shipped', function()
    EXT = {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    Setup()                                   -- shipped: 1 / true / x
    FS.a, FS.c = 5, 'y'
    Expect(SaveUserDefaults(), 2, 'count')
    Expect(UserDefaultsGet('TestHelper'), 'a=5;c=y', 'stored')
    FS.a, FS.c = 1, 'x'
    Expect(SaveUserDefaults(), 0, 'all at shipped again')
    Expect(UserDefaultsGet('TestHelper'), '', 'nothing stored')
end)

Test.it('ApplyDefaults: back to shipped, then my defaults; never as a project string', function()
    EXT = {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    Setup()
    UserDefaultsSet('TestHelper', 'a=7')
    FS.a, FS.b, FS.c = 99, false, 'zzz'       -- whatever the last project had
    flags = {}
    ApplyDefaults()
    Expect(State(), '7/true/x', 'shipped b and c, my a')
    Expect(table.concat(flags), 'dd', 'deserialize called with project = false, twice')
end)

Test.it('a later release: a new shipped default reaches what the user never changed', function()
    EXT = {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    Setup()                                   -- "September": shipped a=1, c=x
    FS.a = 5
    SaveUserDefaults()                        -- the user prefers a=5
    FS.a, FS.b, FS.c = 1, true, 'new'
    Setup()                                   -- "November": shipped c changed to 'new'
    ApplyDefaults()
    Expect(State(), '5/true/new', 'my a kept, the new shipped c arrives')
    SaveUserDefaults()                        -- saving again keeps a
    Expect(UserDefaultsGet('TestHelper'), 'a=5', 're-saved')
end)

Test.it('Reset one, Clear all, and the list', function()
    EXT = {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    Setup()
    FS.a, FS.b = 4, false
    SaveUserDefaults()
    local rows = UserDefaultRows()
    Expect(#rows, 2, 'rows')
    Expect(rows[1].label .. ' ' .. rows[1].value .. ' (' .. rows[1].shipped .. ')', 'Tab: A 4 (1)', 'number row')
    Expect(rows[2].label .. ' ' .. rows[2].value .. ' (' .. rows[2].shipped .. ')', 'Tab: B Off (On)', 'bool row')
    ResetUserDefault('a')
    Expect(UserDefaultsGet('TestHelper'), 'b=0', 'a dropped from storage')
    Expect(FS.a, 1, 'a back to shipped now')
    ClearUserDefaults()
    Expect(UserDefaultsGet('TestHelper'), '', 'cleared')
    Expect(#UserDefaultRows(), 0, 'no rows')
    Expect(FS.b, false, 'Clear leaves the shown settings alone')
end)

Test.it('project-only values are never stored, and ignored if an older save stored them', function()
    EXT = {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    -- c is song-specific; a only when it is 9 (like a mode whose one value picks a key)
    UserDefaultsSetup({ section = 'TestHelper', serialize = FSerialize, deserialize = FDeserialize,
                        project_only = function(k, v) return k == 'c' or (k == 'a' and v == '9') end })
    FS.a, FS.c = 5, 'song'
    Expect(SaveUserDefaults(), 1, 'only a stored')
    Expect(UserDefaultsGet('TestHelper'), 'a=5', 'c left out')
    FS.a = 9
    SaveUserDefaults()
    Expect(UserDefaultsGet('TestHelper'), '', 'a=9 is project-only too')
    UserDefaultsSet('TestHelper', 'a=5;c=old')   -- as an earlier version could have stored
    FS.a, FS.c = 0, 'zzz'
    ApplyDefaults()
    Expect(State(), '5/true/x', 'stored c ignored: shipped x')
    Expect(#UserDefaultRows(), 1, 'list shows only a')
    Setup()   -- back to the plain test helper
end)

Test.it('ProjectSettingsDiffer: only a project with other saved settings asks', function()
    EXT, PROJ = {}, {}
    FS.a, FS.b, FS.c = 1, true, 'x'
    Setup()
    Expect(ProjectSettingsDiffer(), false, 'no project settings')
    PROJ['TestHelper/settings_v1'] = FSerialize()
    Expect(ProjectSettingsDiffer(), false, 'project saved exactly these values')
    FS.a = 9
    Expect(ProjectSettingsDiffer(), true, 'project saved other values')
    PROJ = {}
end)

----------------------------------------------------------------------
Test.section('General Helper settings.lua on the layers')
----------------------------------------------------------------------

-- settings.lua defines its own UserDefaultsSetup globals when it loads, replacing the
-- test helper's above.
if not GENERAL_SETTINGS_FILE then
    -- the runner did not load the General Helper's files
else
    dofile(GENERAL_SETTINGS_FILE)
    local G = 'RBHelperVKR'

    Test.it('a project without settings gets shipped + mine, not the previous project\'s', function()
        EXT, PROJ = {}, {}
        S.drum_anim_min_cym, S.drum_anim_flam = 3, true
        S.drum_anim_min_cym = 6
        SaveUserDefaults()                    -- mine: min cymbal hits 6
        S.drum_anim_flam = false              -- the previous project turned the flam off
        Expect(LoadSettings(), false, 'no project settings')
        Expect(S.drum_anim_min_cym, 6, 'my default')
        Expect(S.drum_anim_flam, true, 'shipped, not the previous project\'s')
    end)

    Test.it('song-specific General settings stay out of my defaults', function()
        EXT, PROJ = {}, {}
        LoadSettings()                        -- shipped
        S.tm_first_measure, S.char_active.drums, S.venue_theme_name = 5, 2, 'some_theme'
        S.drum_anim_min_cym = 6
        Expect(SaveUserDefaults(), 1, 'only min cymbal hits stored')
        Expect(UserDefaultsGet(G), 'admc=6', 'stored')
        EXT, PROJ = {}, {}
        LoadSettings()
    end)

    Test.it('project settings win over mine', function()
        EXT, PROJ = {}, {}
        UserDefaultsSet(G, 'admc=6')
        PROJ[G .. '/settings_v1'] = 'v=1;admc=4'
        Expect(LoadSettings(), true, 'project had settings')
        Expect(S.drum_anim_min_cym, 4, 'the project\'s value')
    end)

    Test.it('the old-project soft-option rule does not fire on my defaults', function()
        EXT, PROJ = {}, {}
        UserDefaultsSet(G, 'adss=1')         -- mine: soft snare on, shipped threshold
        LoadSettings()
        Expect(S.drum_anim_soft_snare, true, 'option on')
        Expect(S.drum_anim_soft_snare_below, 50, 'shipped threshold, not the old-project 128')
        PROJ[G .. '/settings_v1'] = 'v=1;adss=1'   -- an old project: still 128
        LoadSettings()
        Expect(S.drum_anim_soft_snare_below, 128, 'old project keeps every hit soft')
        EXT, PROJ = {}, {}
        LoadSettings()                        -- leave S at shipped
    end)
end

for k, f in pairs(real) do r[k] = f end
