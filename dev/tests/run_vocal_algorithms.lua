-- @description Rock Band Vocal Helper — Algorithm Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for ScoreNotes, NearestScalePitch, DiatonicThirdOffset,
--   and EditDistance. These functions operate on plain Lua tables with no REAPER
--   API calls. Run from the REAPER Actions list or triggered via the test launcher.
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
local _mdir       = _root .. 'rock_band_vocal_helper_vkr/'
_FIXTURE_DIR      = _tdir .. 'midi/'   -- global: read by vocal_algorithms.lua's ParseLyricsLines tests

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Vocal Helper — algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_mdir .. 'defaults.lua')           -- S, HARM_SCALE, RB3_* constants
dofile(_mdir .. 'autotune.lua')           -- ScoreNotes
dofile(_mdir .. 'actions_snap_key.lua')   -- NearestScalePitch
dofile(_mdir .. 'actions_harmonies.lua')  -- DiatonicThirdOffset
dofile(_mdir .. 'actions_validation.lua') -- EditDistance
dofile(_mdir .. 'actions_lyrics.lua')     -- ParseLyricsLines, ParseLyricsFile

dofile(_tdir .. 'vocal_algorithms.lua')
Test.report()
