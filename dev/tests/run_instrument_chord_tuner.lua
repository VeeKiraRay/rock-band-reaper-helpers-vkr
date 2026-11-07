-- @description Rock Band Instrument Helper - Keys Tuner Tests
-- @author VeeKiraRay
-- @about
--   REAPER tests for the Keys > Tuner controller (chord_tuner.lua): builds a generated keys
--   stem and a charted Pro Keys chord, reads them through real audio accessors, and checks
--   the readings, the passage check, the idle and sub-tab stops and the saved settings.
--   Removes its tracks and file afterwards. Stop playback before running.
--   Run from the REAPER Actions list for a fully isolated Lua context, or
--   triggered via the test_rock_band_helpers_vkr launcher.
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
local _mdir       = _root .. 'rock_band_instrument_helper_vkr/'
SCRIPT_MDIR       = _mdir

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Instrument Helper - Keys Tuner tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')        -- PitchName
dofile(_root .. 'lib/reaper_wav_writer.lua')
dofile(_root .. 'lib/reaper_helper_common.lua')        -- TrackAtIndex, MakeProjectPoll, RefreshTrackLists
dofile(_root .. 'lib/reaper_difficulty_read.lua')      -- FindTrackExact
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_root .. 'lib/reaper_spectrum.lua')
dofile(_root .. 'lib/reaper_chord_detect.lua')
dofile(_root .. 'lib/reaper_key_detect.lua')
dofile(_root .. 'lib/reaper_key_profiles.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'chord_tuner.lua')

dofile(_tdir .. 'instrument_chord_tuner.lua')
Test.report()
