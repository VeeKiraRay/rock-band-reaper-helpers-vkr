-- @description Rock Band Venue Phrase Pacing — Tests
-- @author VeeKiraRay
-- @about
--   Tests for the "Vocal phrase start" camera pacing mode: GenerateCameraEvents' phrase
--   branch (venue_camera.lua), CollectVocalPhraseStarts note-start-only filtering
--   (venue_lighting.lua), and FindNextVocalPhraseStartPpq (actions_venue_manual.lua).
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered via
--   the test_rock_band_helpers_vkr launcher. Results appear in the REAPER console
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
local _gdir = _root .. 'rock_band_general_helper_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Venue Phrase Pacing — tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_gdir .. 'helpers.lua')                    -- FindTrackByName
dofile(_gdir .. 'venue_camera.lua')               -- GenerateCameraEvents, RB3_PHRASE_PITCH
dofile(_gdir .. 'venue_lighting.lua')             -- CollectInstNotePositions, CollectVocalPhraseStarts
dofile(_gdir .. 'actions_venue_manual.lua')       -- FindNextVocalPhraseStartPpq

dofile(_tdir .. 'venue_phrase_pacing.lua')
Test.report()
