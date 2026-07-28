-- @description Rock Band General Helper — Algorithm Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for EstimateBPM, GuessTimeSig, FitBeatGrid,
--   ComputePlayerStatesAt, KeyframeSubdivQN, and BuildShapeGemMap.
--   These functions operate on plain Lua tables with no REAPER API calls.
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
local _mdir       = _root .. 'rock_band_general_helper_vkr/'
SCRIPT_MDIR       = _mdir  -- tempomap.lua does not use this, but set for consistency

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  General Helper — algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_root .. 'lib/reaper_guitar_theory.lua')  -- GuitarSuggestRBMapping, GuitarClassifyChordType
dofile(_mdir .. 'defaults.lua')        -- S and constants
dofile(_mdir .. 'tempomap.lua')        -- EstimateBPM, GuessTimeSig, FitBeatGrid
dofile(_mdir .. 'venue_awareness.lua') -- ComputePlayerStatesAt (pure; REAPER-facing
                                       -- functions in this file are not exercised)
dofile(_mdir .. 'venue_lighting.lua')  -- KeyframeSubdivQN (pure; other functions in
                                       -- this file are not exercised)
dofile(_mdir .. 'actions_guitar.lua')  -- BuildShapeGemMap (pure; other functions in
                                       -- this file are not exercised)

dofile(_tdir .. 'general_algorithms.lua')
Test.report()
