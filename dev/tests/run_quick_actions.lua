-- @description Rock Band Quick Actions - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the quick_actions/ hotkey scripts. Each test builds a MIDI item
--   on a temp track, drives the quick action's take-level core directly, and
--   asserts on the resulting notes. No MIDI editor or fixtures needed.
--   Run from the REAPER Actions list for a fully isolated Lua context, or
--   triggered via the test_rock_band_helpers_vkr launcher.
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

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Quick actions - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'quick_actions/lib/vocal_note_snap_core.lua')
dofile(_root .. 'quick_actions/lib/vocal_note_create_core.lua')

EnableFixtureAutoCleanup()  -- one aborted test must not poison the rest

dofile(_tdir .. 'quick_actions.lua')
Test.report()
