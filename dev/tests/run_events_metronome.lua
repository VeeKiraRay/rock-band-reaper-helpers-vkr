-- @description Rock Band Events Metronome - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the General Helper's Events > Metronome sub-tab: the MetronomePlan
--   rules (pulse, drums, time selection) and GenerateMetronome against fixture
--   EVENTS / PART DRUMS tracks (skipped if the open project already has either).
--   Runs inside REAPER (launcher or Actions list) or offline, planner only:
--     lua dev/tests/run_events_metronome.lua
--   Results appear in the REAPER console (View > Show REAPER console).

local _script
if reaper then
    r = reaper
    _script = ({ reaper.get_action_context() })[2]
else
    r = { ShowConsoleMsg = function(s) io.write(s) end, ClearConsole = function() end }
    _script = arg and arg[0] or ''
    if not _script:match('^%a:') and not _script:match('^[/\\]') then _script = './' .. _script end
end

local _ctx_dir = _script:match('^(.+[\\/])') or './'
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
r.ShowConsoleMsg('======  Events Metronome - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')    -- GetTimeSelection, FormatTime
dofile(_root .. 'lib/reaper_midi_helpers.lua')     -- ReplaceNotesBulk
dofile(_gdir .. 'defaults.lua')                    -- S
dofile(_root .. 'lib/reaper_helper_common.lua')    -- FindTrackByName
dofile(_root .. 'lib/reaper_difficulty_read.lua')  -- FindTrackExact, ReadGemEvents
dofile(_gdir .. 'helpers.lua')                     -- FindNamedTrackMIDI
dofile(_gdir .. 'venue_awareness.lua')             -- FindEventTime
dofile(_gdir .. 'events_metronome.lua')
if r.CountTracks then EnableFixtureAutoCleanup() end  -- one aborted test must not leave tracks behind

dofile(_tdir .. 'events_metronome.lua')
Test.report()
