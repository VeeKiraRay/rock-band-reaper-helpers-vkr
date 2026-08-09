-- @description Rock Band Venue Labels - Tests
-- @author VeeKiraRay
-- @about
--   Coverage checks for the venue camera display-label tables: every [coop_*] and
--   [directed_*] event in the pools has a label, no label is orphaned or duplicated,
--   and the dev demo's mirrored pools/labels still match. Pure table checks - no
--   project state is touched, so this is safe to run on an open song. Run from the
--   REAPER Actions list for a fully isolated Lua context, or triggered via the
--   test_rock_band_helpers_vkr launcher.
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
local _tdir     = _root .. 'dev/tests/'
local _gdir     = _root .. 'rock_band_general_helper_vkr/'
local _demo_dir = _root .. 'dev/rock_band_venue_demo_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Venue Labels - tests  ======\n')

dofile(_tdir .. 'framework.lua')

-- venue_sprites.lua resolves VENUE_SPRITE_ROOT at load time from SCRIPT_DIR (falling
-- back to SCRIPT_MDIR, which would error on nil), so this has to be set first.
SCRIPT_DIR = _root

-- Load order matters: the demo defaults define the SAME global names (COOP_POOL,
-- COOP_LABELS, DIRECTED_POOL, DIRECTED_LABELS, LIGHTING_NAMES, POSTPROC_NAMES,
-- VENUE_VALID) as its own mirrored copies, so the helper's tables have to be captured
-- before the demo file overwrites them.
dofile(_root .. 'lib/reaper_imgui_helpers.lua')  -- SortedByLabel (display lists)
dofile(_gdir .. 'defaults.lua')        -- VENUE_VALID
dofile(_gdir .. 'venue_themes.lua')    -- LIGHTING_NAMES, POSTPROC_NAMES, POSTPROC_DISPLAY
dofile(_gdir .. 'venue_camera.lua')    -- COOP_/DIRECTED_ pools, labels, display lists
-- Pure tables/functions; its GetCoopRequiredInstruments use is at call time only,
-- so venue_awareness.lua is not needed for these table-coverage checks.
dofile(_gdir .. 'venue_camera_priority.lua')  -- CAM_PRIORITY, CAM_PRIORITY_TIERS
dofile(_gdir .. 'venue_sprites.lua')   -- RawVenueEventText
dofile(_gdir .. 'venue_lighting.lua')  -- MANUAL_LIGHTING_SET, LIGHTING_DISPLAY_GROUPS
-- The demo mirrors MANUAL_LIGHTING_SET too, keyed by BARE name where the helper keys
-- it by full event text - so every table the tests compare against has to be captured
-- here, not read off the globals once the demo file has loaded.
LBL_MAIN = {
    coop_pool = COOP_POOL, coop = COOP_LABELS,
    dir_pool  = DIRECTED_POOL, dir = DIRECTED_LABELS,
    lighting_names = LIGHTING_NAMES, lighting = LIGHTING_LABELS,
    postproc_names = POSTPROC_NAMES, postproc = POSTPROC_LABELS,
    venue_valid    = VENUE_VALID,
    manual_set     = MANUAL_LIGHTING_SET,
    coop_groups     = COOP_DISPLAY_GROUPS,
    dir_display     = DIRECTED_DISPLAY,
    dir_bre         = DIRECTED_BRE_NAMES,
    lighting_groups = LIGHTING_DISPLAY_GROUPS,
    postproc_display = POSTPROC_DISPLAY,
    priority         = CAM_PRIORITY,
    priority_tiers   = CAM_PRIORITY_TIERS,
    generic_fallback = CAM_GENERIC_FALLBACK,
}

dofile(_demo_dir .. 'defaults.lua')
LBL_DEMO = {
    coop_pool = COOP_POOL, coop = COOP_LABELS,
    dir_pool  = DIRECTED_POOL, dir = DIRECTED_LABELS,
}

dofile(_tdir .. 'venue_labels.lua')
Test.report()
