-- @description Rock Band Venue Subtracks - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the VENUE sub-track split/merge feature (actions_venue_subtracks.lua):
--   CategorizeVenueEvent classification, subtrack creation/naming/muting, position-bridging
--   copy correctness, and the 5 public actions - plus a regression check on
--   RemoveVenueEventsByType (actions_venue_manual.lua) after its refactor to share
--   CategorizeVenueEvent. Run from the REAPER Actions list for a fully isolated Lua context,
--   or via the test_rock_band_helpers_vkr launcher. Results appear in the REAPER console.

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
r.ShowConsoleMsg('======  Venue Subtracks - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_gdir .. 'helpers.lua')                    -- FindTrackByName, FindNamedTrackMIDI, GetTakePPQPerQN
dofile(_gdir .. 'venue_generator.lua')            -- DeleteTextEventsInRange, ClearVenueTextEventsInRange
dofile(_gdir .. 'actions_venue_subtracks.lua')    -- code under test
dofile(_gdir .. 'actions_venue_manual.lua')       -- RemoveVenueEventsByType regression

EnableFixtureAutoCleanup()  -- one aborted test must not poison the rest

dofile(_tdir .. 'venue_subtracks.lua')
Test.report()
