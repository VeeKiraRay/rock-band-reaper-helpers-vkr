-- @description Rock Band Helpers - Score Simulator Unit Tests
-- @author VeeKiraRay
-- @about
--   Unit tests for lib/reaper_score_sim.lua - the base score, star cut-offs and the
--   overdrive simulation behind the General Helper's Metadata > Score and the
--   Instrument Helper's Overdrive > Validate summary. Pure; synthetic charts only.
--   Runs inside REAPER (launcher or Actions list) or offline:
--     lua dev/tests/run_score_sim.lua

local _script
if reaper then
    r = reaper
    _script = ({ reaper.get_action_context() })[2]
else
    r = { ShowConsoleMsg = function(s) io.write(s) end, ClearConsole = function() end }
    _script = arg and arg[0] or ''
    if not _script:match('^%a:') and not _script:match('^[/\\]') then _script = './' .. _script end
end

local _ctx_dir = _script:match('^(.+[\\/])') or './'
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
r.ShowConsoleMsg('======  Score simulator - unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_score_sim.lua')
dofile(_root .. 'lib/reaper_score_read.lua')   -- ScoreMarkUnisons (pure); r only inside functions

dofile(_tdir .. 'score_sim.lua')
Test.report()
