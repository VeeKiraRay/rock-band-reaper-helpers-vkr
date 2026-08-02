-- @description Rock Band DSP Library - Algorithm Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for GateAndSplit, ApplyMinOffset, and SnapOnsets.
--   These functions take plain Lua tables and make no REAPER API calls.
--   Run from the REAPER Actions list or triggered via the test launcher.
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
r.ShowConsoleMsg('======  DSP Library - algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_dsp.lua')

dofile(_tdir .. 'dsp_algorithms.lua')
Test.report()
