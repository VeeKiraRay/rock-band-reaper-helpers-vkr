-- @description Rock Band Animation Character - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the General Helper's Animation > Character sub-tab: the
--   CharacterPlan rules (song start, idle gaps, idle_realtime) and Generate /
--   Manual against fixture part tracks (skipped if the open project already
--   has one). Run from the REAPER Actions list for a fully isolated Lua
--   context, or triggered via the test_rock_band_helpers_vkr launcher.
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
r.ShowConsoleMsg('======  Animation Character - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- GetTimeSelection
dofile(_root .. 'lib/reaper_midi_helpers.lua')    -- FindFirstMIDIItem
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_root .. 'lib/reaper_helper_common.lua')   -- FindTrackByName
dofile(_gdir .. 'animation_character.lua')

EnableFixtureAutoCleanup()  -- one aborted test must not leave tracks behind

dofile(_tdir .. 'animation_character.lua')
Test.report()
