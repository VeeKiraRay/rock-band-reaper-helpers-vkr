-- @description Rock Band Instrument Helper - Smoke Tests
-- @author VeeKiraRay
-- @about
--   Smoke-tests every public Instrument Helper action without starting the ImGui loop.
--   Run from the REAPER Actions list for a fully isolated Lua context, or triggered
--   via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console (View > Show REAPER console).

r = reaper

-- Path resolution: works whether this script is run directly (in dev/tests/) or
-- dofile'd from dev/ launcher.
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
SCRIPT_MDIR       = _mdir

ctx = nil  -- actions do not call ImGui directly

r.ClearConsole()
r.ShowConsoleMsg('======  Instrument Helper - smoke tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_imgui_helpers.lua')
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_root .. 'lib/reaper_midi_helpers.lua')
dofile(_root .. 'lib/reaper_guitar_theory.lua')  -- GuitarSuggestRBMapping, used by actions_guitar.lua
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_root .. 'lib/reaper_helper_common.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'actions_drums.lua')
dofile(_mdir .. 'actions_keys.lua')
dofile(_mdir .. 'actions_keys_guides.lua')
dofile(_mdir .. 'actions_guitar.lua')
dofile(_mdir .. 'actions_guitar_guide.lua')
dofile(_mdir .. 'actions_guitar_validate.lua')
dofile(_mdir .. 'actions_midi_align.lua')
dofile(_mdir .. 'actions_midi_replace.lua')
dofile(_mdir .. 'actions_difficulty_shared.lua')
dofile(_mdir .. 'actions_difficulty.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')
dofile(_mdir .. 'actions_difficulty_drums_checks.lua')
dofile(_mdir .. 'actions_difficulty_drums.lua')
dofile(_mdir .. 'difficulty_generate_params.lua')
dofile(_mdir .. 'difficulty_generate_overlaps.lua')
dofile(_mdir .. 'difficulty_generate_retime.lua')
dofile(_mdir .. 'difficulty_generate_colors.lua')
dofile(_mdir .. 'difficulty_generate_rhythm.lua')
dofile(_mdir .. 'difficulty_generate_5lane.lua')
dofile(_mdir .. 'difficulty_generate_prokeys.lua')
dofile(_mdir .. 'difficulty_generate_hopo.lua')
dofile(_mdir .. 'actions_difficulty_generate.lua')
-- ui*.lua intentionally omitted: it calls r.defer(Loop) which starts the ImGui loop

dofile(_tdir .. 'instrument_smoke.lua')
Test.report()
