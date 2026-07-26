-- @description Rock Band Venue Events — Tests
-- @author VeeKiraRay
-- @about
--   Tests for the Venue > Events sub-tab: section_events.lua vocabulary vs
--   the full RB3 events list, NextSectionEvent suffix logic, and EVENTS-track
--   insert integration (skipped if the open project already has an EVENTS
--   track). Run from the REAPER Actions list for a fully isolated Lua
--   context, or triggered via the test_rock_band_helpers_vkr launcher.
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
local _gdir = _root .. 'rock_band_general_helper_vkr/'

ctx = nil
_EVENTS_LIST_PATH = _root .. '_external_docs/Text Events List - Events.txt'

r.ClearConsole()
r.ShowConsoleMsg('======  Venue Events — tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- FormatTime (venue_awareness)
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_gdir .. 'helpers.lua')                    -- FindTrackByName
dofile(_gdir .. 'venue_awareness.lua')            -- ReadEventSections (merge test)
dofile(_gdir .. 'venue_lighting.lua')             -- FindNextMeasureStartPpq (final anchor)
dofile(_gdir .. 'venue_generator.lua')            -- ResolveSongEndAndAnchor
dofile(_gdir .. 'section_events.lua')
dofile(_gdir .. 'actions_venue_events.lua')

dofile(_tdir .. 'venue_events.lua')
Test.report()
