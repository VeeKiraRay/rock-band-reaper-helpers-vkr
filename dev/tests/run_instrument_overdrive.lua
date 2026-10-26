-- @description Rock Band Instrument Helper - Overdrive Tests
-- @author VeeKiraRay
-- @about
--   Tests for the Overdrive tab: counted beats, the per-bar interest score, the
--   vocal, fill and instrument planners (pure, on hand-built song models), the
--   validator, and GenerateOverdrive / ValidateOverdrive end to end against
--   generated tracks - including the replace confirmation, which must write
--   nothing until it is answered.
--
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered
--   via the test_rock_band_helpers_vkr launcher. Results appear in the REAPER
--   console (View > Show REAPER console).

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
local _gdir = _root .. 'rock_band_instrument_helper_vkr/'

ctx = nil                       -- runners set this; the launcher saves/restores it

r.ClearConsole()
r.ShowConsoleMsg('======  Instrument Helper - Overdrive tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')          -- FormatTime
dofile(_root .. 'lib/reaper_difficulty_score.lua')       -- DIFFICULTY_PRIMITIVES, NormalizeSpans
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_gdir .. 'defaults.lua')                          -- S
dofile(_root .. 'lib/reaper_helper_common.lua')          -- GetTempoContextBefore
dofile(_root .. 'lib/reaper_difficulty_read.lua')        -- FindTrackExact, ReadGemEvents
dofile(_gdir .. 'overdrive_read.lua')
dofile(_gdir .. 'overdrive_interest.lua')
dofile(_gdir .. 'actions_overdrive_fills.lua')
dofile(_gdir .. 'actions_overdrive_vocals.lua')
dofile(_gdir .. 'actions_overdrive.lua')
dofile(_gdir .. 'actions_overdrive_validate.lua')

EnableFixtureAutoCleanup()  -- one aborted test must not poison the rest

dofile(_tdir .. 'instrument_overdrive.lua')
Test.report()
