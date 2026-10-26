-- @description Rock Band Instrument Helper - Algorithm Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for BuildShapeGemMap (both the Guitar converter's
--   and the Tab Input guide's configuration), the Tab Input guides, and the
--   Difficulty > Generate planner.
--   These functions operate on plain Lua tables with no REAPER API calls.
--   Run from the REAPER Actions list or triggered via the test launcher.
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
SCRIPT_MDIR       = _mdir  -- nothing under test uses this, but set for consistency

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Instrument Helper - algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')  -- PitchName, FormatTime
dofile(_root .. 'lib/reaper_guitar_theory.lua')  -- GuitarSuggestRBMapping, GuitarClassifyChordType
dofile(_mdir .. 'defaults.lua')        -- S and constants
dofile(_mdir .. 'actions_guitar.lua')  -- BuildShapeGemMap, SortedChordPitches (pure;
                                       -- other functions in this file are not exercised)
dofile(_mdir .. 'actions_guitar_guide.lua')  -- ParseTabHorizontal (pure; GuitarTabGuide
                                             -- itself is not exercised)

dofile(_mdir .. 'actions_keys_guides.lua')  -- VocalTabBestShift (pure; the guides
                                            -- themselves read S and are not called)
dofile(_mdir .. 'actions_difficulty_shared.lua')    -- DiffReleaseGapQN (pure)
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')   -- GB_* rule tables (r only inside functions)
dofile(_mdir .. 'actions_difficulty_5k.lua')        -- K5_* rule tables (r only inside functions)
dofile(_mdir .. 'actions_difficulty.lua')           -- PK_MAX_CHORD / PK_MAX_SPAN (r only inside functions)
dofile(_mdir .. 'difficulty_generate_params.lua')   -- GEN5_PARAMS, shared gaps (pure)
dofile(_mdir .. 'difficulty_generate_overlaps.lua') -- GenMergeRolls, GenPlanOverlaps (pure)
dofile(_mdir .. 'difficulty_generate_retime.lua')   -- Gen5RetimeDenseRuns (pure)
dofile(_mdir .. 'difficulty_generate_colors.lua')   -- Gen5ReduceChordSize, Gen5Shift* (pure)
dofile(_mdir .. 'difficulty_generate_rhythm.lua')   -- Gen5SelectOnsets (pure)
dofile(_mdir .. 'difficulty_generate_5lane.lua')    -- Gen5PlanTier (pure)
dofile(_mdir .. 'difficulty_generate_prokeys.lua')   -- GenPKPlanTier (pure)
dofile(_mdir .. 'difficulty_generate_hopo.lua')     -- Gen5MarkHopos, Gen5ForceHopoSpans (pure)
dofile(_mdir .. 'actions_difficulty_drums_checks.lua') -- DRUMS_RULES (r only inside functions)
dofile(_mdir .. 'actions_drums_2x.lua')             -- DoubleBassPlan (pure; GenDrumsSinglePedal uses it)
dofile(_mdir .. 'difficulty_generate_drums.lua')    -- GenDrumsPlanTier (pure)
dofile(_tdir .. 'instrument_algorithms.lua')
Test.report()
