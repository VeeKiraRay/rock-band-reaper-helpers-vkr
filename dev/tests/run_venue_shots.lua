-- @description Rock Band Directed Moves - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the Directed Moves window: the generated camera shot data
--   (lib/reaper_venue_shots.lua) and the queries over it
--   (lib/reaper_venue_shots_query.lua). Pure - no project, no UI.
--   Runs inside REAPER (launcher or Actions list) or offline:
--     lua dev/tests/run_venue_shots.lua

-- Inside REAPER, or plain Lua with a two-function stand-in (the code under test never calls r).
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
r.ShowConsoleMsg('======  Directed Moves - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_venue_shots.lua')
dofile(_root .. 'lib/reaper_venue_shots_query.lua')

dofile(_tdir .. 'venue_shots.lua')
Test.report()
