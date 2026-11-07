-- @description Rock Band Vocal Helper - Harmony Detect Tests
-- @author VeeKiraRay
-- @about
--   Pure tests for lib/reaper_harmony_detect.lua (the Pitch > Tuner Harmony readout):
--   lead cancellation, the second voice on synthetic voices, voting and the key snap.
--   Runs inside REAPER (launcher or Actions list) or offline:
--     lua dev/tests/run_harmony_detect.lua

-- Inside REAPER, or plain Lua with a two-function stand-in (the module never calls r).
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
r.ShowConsoleMsg('======  Harmony detect - unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_dsp.lua')              -- ComputeCMND
dofile(_root .. 'lib/reaper_spectrum.lua')
dofile(_root .. 'lib/reaper_harmony_detect.lua')

dofile(_tdir .. 'harmony_detect.lua')
Test.report()
