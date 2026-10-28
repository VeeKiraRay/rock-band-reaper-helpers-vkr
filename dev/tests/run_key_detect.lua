-- @description Rock Band General Helper - Song Key Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for lib/reaper_key_detect.lua, the generated
--   lib/reaper_key_profiles.lua and lib/reaper_key_audio.lua - the Metadata >
--   Song key suggestion: key names and relations, unpitched lyrics, the fitted
--   profiles, ranking, unavailable result sets, confidence, and pitch from
--   synthetic vocal audio. Pure; the files loaded below make no REAPER API
--   calls. Run from the REAPER Actions list or triggered via
--   the test launcher. Results appear in the REAPER console
--   (View > Show REAPER console).

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
r.ShowConsoleMsg('======  Song Key - algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_dsp.lua')          -- ComputeCMND / SearchYINTau
dofile(_root .. 'lib/reaper_key_detect.lua')
dofile(_root .. 'lib/reaper_key_profiles.lua')
dofile(_root .. 'lib/reaper_key_audio.lua')

dofile(_tdir .. 'key_detect.lua')
Test.report()
