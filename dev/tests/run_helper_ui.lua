-- @description Rock Band Helper UI - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the pure half of lib/reaper_helper_ui.lua, the window footer
--   every helper and standalone window draws (the Copy result text), and the
--   MakeProjectPoll timing behind the automatic track-list refresh. Run from
--   the REAPER Actions list for a fully isolated Lua context, or via the
--   test_rock_band_helpers_vkr launcher. Results appear in the REAPER console.
--
--   Nothing here touches the project or draws anything. ctx stays nil, which
--   also proves the module does no ImGui work at load time.

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

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Helper UI - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- BeginScrollBody etc. (loaded first, as in every window)
dofile(_root .. 'lib/reaper_helper_ui.lua')       -- code under test
dofile(_root .. 'lib/reaper_helper_common.lua')   -- MakeProjectPoll (code under test)

dofile(_tdir .. 'helper_ui.lua')
Test.report()
