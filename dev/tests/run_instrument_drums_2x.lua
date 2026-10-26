-- @description Rock Band Instrument Helper - Drums 2x Kicks Tests
-- @author VeeKiraRay
-- @about
--   Tests for Remove2XKicks (actions_drums_2x.lua): the General > Actions button
--   that works out which kicks on PART DRUMS_2X are the drummer's second foot and
--   deletes those from PART DRUMS. Also covers DoubleBassPlan, the detection rules
--   as a pure function, and MarkDoubleBassKicks, which is kept but not drawn.
--
--   Includes the tempo-change regression: matching is done in quarter notes, not
--   seconds, so a BPM jump partway through a song does not stop it finding notes.
--   Those tests rewrite the project tempo map and put it back afterwards, and one
--   test asserts the restore actually happened.
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
r.ShowConsoleMsg('======  Instrument Helper - Drums 2x kicks tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_root .. 'lib/reaper_helper_common.lua')   -- FindTrackByName, GetTakePPQPerQN
dofile(_gdir .. 'actions_drums_2x.lua')           -- Remove2XKicks, DoubleBassPlan

EnableFixtureAutoCleanup()  -- one aborted test must not poison the rest

dofile(_tdir .. 'instrument_drums_2x.lua')
Test.report()
