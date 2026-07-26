-- @description Rock Band Workflow Checklist — Tests
-- @author VeeKiraRay
-- @about
--   Tests for the Workflow checklist feature: template parsing (workflow.lua),
--   including [section]/{tooltip} markup and duplicate/bracket-balance
--   validation, plus state persistence, template-switch pruning, and the
--   progress-count helper (actions_workflow.lua). Run from the REAPER
--   Actions list for a fully isolated Lua context, or via the
--   test_rock_band_helpers_vkr launcher. Results appear in the REAPER
--   console.
--
--   The persistence tests read/write this project's real "RBHelperVKR" /
--   "workflow_v1" ExtState key - they snapshot the original value first and
--   restore it afterward, so running this suite never loses real checklist
--   progress in whatever project it's run from.

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
r.ShowConsoleMsg('======  Workflow Checklist — tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_gdir .. 'defaults.lua')            -- S
dofile(_gdir .. 'workflow.lua')            -- code under test: parser
dofile(_gdir .. 'actions_workflow.lua')    -- code under test: persistence

dofile(_tdir .. 'workflow.lua')
Test.report()
