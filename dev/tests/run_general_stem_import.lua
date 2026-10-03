-- @description Rock Band General Helper - Stem Import Tests
-- @author VeeKiraRay
-- @about
--   Tests for General > Actions' "Import stems" filename matching
--   (StemImportPlan). Pure - creates nothing in the project.
--
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered
--   via the test_rock_band_helpers_vkr launcher. Results appear in the REAPER
--   console (View > Show REAPER console).

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

ctx = nil                       -- runners set this; the launcher saves/restores it

r.ClearConsole()
r.ShowConsoleMsg('======  General Helper - Stem import tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_gdir .. 'actions_stem_import.lua')

dofile(_tdir .. 'general_stem_import.lua')
Test.report()
