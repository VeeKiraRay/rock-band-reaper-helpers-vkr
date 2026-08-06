-- @description Rock Band Venue Validate - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the VENUE lighting/blend validator (actions_venue_validate.lua):
--   [first] keyframe placement against the preset-change rule, stray-[first]
--   classification, and blend-anchor detection for lighting and post proc.
--   All cases drive the pure ValidateVenueLightingBlends, so no project state is
--   touched and no fixture cleanup is needed. Run from the REAPER Actions list for a
--   fully isolated Lua context, or via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console.

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
r.ShowConsoleMsg('======  Venue Validate - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- SortedByLabel, FormatTime
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_gdir .. 'helpers.lua')                    -- FindNamedTrackMIDI, GetTakePPQPerQN
dofile(_gdir .. 'venue_lighting.lua')             -- MANUAL_LIGHTING_SET, IsBlendAnchor
dofile(_gdir .. 'actions_venue_subtracks.lua')    -- CategorizeVenueEvent
dofile(_gdir .. 'actions_venue_validate.lua')     -- code under test

dofile(_tdir .. 'venue_validate.lua')
Test.report()
