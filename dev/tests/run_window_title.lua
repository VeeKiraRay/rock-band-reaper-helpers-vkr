-- @description Rock Band Window Title - Tests
-- @author VeeKiraRay
-- @about
--   Tests for ScriptWindowTitle in lib/reaper_imgui_helpers.lua, which builds
--   each window's ImGui_Begin label from the running script's own @version
--   header: the version format, the fallbacks when no header can be read, the
--   stable "###" id that keeps saved window geometry across version bumps, and
--   a scan of the six shipped entry points so a header edit that stops parsing
--   fails a test instead of shipping. Run from the REAPER Actions list for a
--   fully isolated Lua context, or via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console.
--
--   Nothing here touches the project, creates tracks, or writes files - only
--   files already in the repo are read. ctx stays nil throughout, which also
--   proves ScriptWindowTitle needs no ImGui context.

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
r.ShowConsoleMsg('======  Window Title - tests  ======\n')

dofile(_tdir .. 'framework.lua')

-- The entry-point scan needs the real install root. ScriptWindowTitle takes the
-- script path as an argument rather than resolving one, so the tests build their
-- paths from this instead of from get_action_context (which here would give this
-- runner's own path).
TITLE_ROOT = _root

dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- code under test

dofile(_tdir .. 'window_title.lua')
Test.report()
