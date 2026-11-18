-- @description Rock Band Settings Defaults - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the settings layers every helper uses: shipped defaults < my defaults
--   (REAPER global ExtState) < this project. The string tools and UserDefaultsSetup
--   from lib/reaper_helper_common.lua, then the General Helper's settings.lua on top.
--   REAPER's ExtState calls are replaced by an in-memory store while it runs, so your
--   own defaults and the open project are left alone.
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered
--   via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console (View > Show REAPER console).

r = reaper

local _ctx_script = ({reaper.get_action_context()})[2]
local _ctx_dir    = _ctx_script:match('^(.+[\\/])')
local _in_dev_tests = _ctx_dir:lower():find('[/\\]dev[/\\]tests[/\\]$')
local _in_dev       = _ctx_dir:lower():find('[/\\]dev[/\\]$')
local function _strip(d)
    return (d:match('^(.+)[/\\]+$') or d):match('^(.+[/\\])') or d
end
local _root = _in_dev_tests and _strip(_strip(_ctx_dir))
           or _in_dev       and _strip(_ctx_dir)
           or _ctx_dir
local _tdir = _root .. 'dev/tests/'
local _gdir = _root .. 'rock_band_general_helper_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Settings defaults - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')
dofile(_root .. 'lib/reaper_helper_common.lua')   -- SettingsDiff, UserDefaultsSetup
dofile(_gdir .. 'defaults.lua')                   -- S
GENERAL_SETTINGS_FILE = _gdir .. 'settings.lua'   -- loaded by the test set itself

dofile(_tdir .. 'settings_defaults.lua')
Test.report()
