-- @description Rock Band Venue Blends - Tests
-- @author VeeKiraRay
-- @about
--   Tests for both sides of the blend-anchor rule.
--   venue.lua: IsBlendAnchor, and AnnotateVenueBlends collapsing anchors out of a
--   preset timeline for the Venue Preview (pure - no project state).
--   venue_lighting.lua: GenerateThemedSectionEvents never re-stating a preset that
--   is already running, which would write an accidental anchor. Those cases need a
--   real take for their PPQ conversions and use a temporary VENUE fixture track,
--   cleaned up after each one; they are skipped if the project already has a VENUE
--   track. Run from the REAPER Actions list for a fully isolated Lua context, or
--   via the test_rock_band_helpers_vkr launcher.
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
r.ShowConsoleMsg('======  Venue Blends - tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_tdir .. 'fixture_helpers.lua')            -- CreateEmptyFixtureTrack, CleanupFixture
dofile(_root .. 'lib/reaper_imgui_helpers.lua')   -- SortedByLabel
dofile(_gdir .. 'defaults.lua')                   -- S
dofile(_gdir .. 'helpers.lua')                    -- FindTrackByName, GetTakePPQPerQN
-- Same order the entry point uses: venue_themes defines LIGHTING_LABELS, which
-- venue_lighting reads at load time.
dofile(_gdir .. 'venue.lua')                      -- code under test (read side)
dofile(_gdir .. 'venue_awareness.lua')            -- venue_camera's call-time deps
dofile(_gdir .. 'venue_themes.lua')               -- GetSectionPreset, Build*Pool
dofile(_gdir .. 'venue_camera.lua')               -- PickRandom
dofile(_gdir .. 'venue_lighting.lua')             -- code under test (write side)

EnableFixtureAutoCleanup()  -- one aborted test must not poison the rest

dofile(_tdir .. 'venue_blends.lua')
Test.report()
