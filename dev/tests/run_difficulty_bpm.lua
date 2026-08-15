-- @description Rock Band General Helper - Difficulty Tempo Tests
-- @author VeeKiraRay
-- @about
--   End-to-end tempo tests for the difficulty-calibration scorer. Unlike
--   run_difficulty_score.lua, these are NOT pure: each test builds a real MIDI take
--   in the current project, reads it back through dev/calibration/corpus.lua's
--   readers, and scores the result - so they cover the tempo path
--   (MIDI_GetPPQPosFromProjQN, TimeMap2_timeToQN, the project tempo map) that the
--   pure tests cannot reach.
--
--   They assert that real-time factors scale with tempo while grid-relative ones do
--   not, and that a tempo CHANGE mid-chart is followed correctly - the case the
--   corpus run's bpm_at_first_note column cannot catch, since it samples one note.
--
--   Modifies the project: creates tracks and rewrites the tempo map, restoring both
--   after each test. Run it in a scratch project, not one you care about.
--
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered
--   via the test_rock_band_helpers_vkr launcher.
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
_FIXTURE_DIR = _tdir .. 'midi/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty calibration - tempo tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
-- songs_dta first: corpus.lua names ParseSongsDta / SongMidiRelPath as requirements,
-- and difficulty_score.lua before it, since ReadMarkerSpans calls NormalizeSpans.
dofile(_root .. 'dev/calibration/difficulty_score.lua')
dofile(_root .. 'dev/calibration/songs_dta.lua')
dofile(_root .. 'dev/calibration/corpus.lua')

dofile(_tdir .. 'difficulty_bpm.lua')
Test.report()
