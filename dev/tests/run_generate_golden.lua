-- @description Rock Band General Helper - Generate Golden-Chart Tests
-- @author VeeKiraRay
-- @about
--   Runs Difficulty > Generate on every MIDI in dev/tests/golden/ and compares the result
--   with the hand-verified Hard, Medium and Easy in the same file (generate_golden.lua).
--   Runs inside REAPER (launcher or Actions list) or offline:
--     lua dev/tests/run_generate_golden.lua
--   The golden folder is gitignored; an empty folder runs zero tests.

-- Inside REAPER, or plain Lua with a two-function stand-in (the planner never calls r).
local _script
if reaper then
    r = reaper
    _script = ({ reaper.get_action_context() })[2]
else
    r = { ShowConsoleMsg = function(s) io.write(s) end, ClearConsole = function() end }
    _script = arg and arg[0] or ''
    -- A relative path from the repo root ("dev/tests/...") needs a leading separator for
    -- the folder detection below.
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
local _mdir = _root .. 'rock_band_general_helper_vkr/'
GOLDEN_DIR  = _tdir .. 'golden/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty > Generate - golden charts  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/tools/smf_chart_events.lua')
dofile(_mdir .. 'actions_difficulty_shared.lua')   -- DiffReleaseGapQN (pure)
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')  -- GB_* rule tables (r only inside functions)
dofile(_mdir .. 'actions_difficulty_5k.lua')       -- K5_* rule tables (r only inside functions)
dofile(_mdir .. 'actions_difficulty.lua')          -- PK_MAX_CHORD / PK_MAX_SPAN (r only inside functions)
dofile(_mdir .. 'difficulty_generate_params.lua')  -- GEN5_PARAMS, shared gaps (pure)
dofile(_mdir .. 'difficulty_generate_overlaps.lua') -- GenMergeRolls, GenPlanOverlaps (pure)
dofile(_mdir .. 'difficulty_generate_retime.lua')  -- Gen5RetimeDenseRuns (pure)
dofile(_mdir .. 'difficulty_generate_colors.lua')  -- chords and colors (pure)
dofile(_mdir .. 'difficulty_generate_rhythm.lua')  -- Gen5SelectOnsets (pure)
dofile(_mdir .. 'difficulty_generate_5lane.lua')   -- Gen5PlanTier (pure)
dofile(_mdir .. 'difficulty_generate_prokeys.lua') -- GenPKPlanTier (pure)
dofile(_mdir .. 'difficulty_generate_hopo.lua')    -- Gen5MarkHopos, Gen5ForceHopoSpans (pure)
dofile(_mdir .. 'actions_difficulty_drums_checks.lua') -- DRUMS_RULES (r only inside functions)
dofile(_mdir .. 'difficulty_generate_drums.lua')   -- GenDrumsPlanTier (pure)

dofile(_tdir .. 'generate_golden.lua')
Test.report()
