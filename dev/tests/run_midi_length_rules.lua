-- @description Rock Band Instrument Helper - MIDI > Length Rules Tests
-- @author VeeKiraRay
-- @about
--   Pure tests for MIDI > Length's sustain rules (midi_length_rules.lua): the gap and
--   plain-note rules it takes from Difficulty > Generate and Validate.
--   Runs inside REAPER (launcher or Actions list) or offline:
--     lua dev/tests/run_midi_length_rules.lua

-- Inside REAPER, or plain Lua with a two-function stand-in (the rules never call r).
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
local _mdir = _root .. 'rock_band_instrument_helper_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  MIDI > Length - sustain rules  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_mdir .. 'actions_difficulty_shared.lua')   -- DiffSustainTooShort, DiffReleaseGapQN (pure)
dofile(_mdir .. 'difficulty_generate_params.lua')  -- GEN5_PARAMS, Gen5ReleaseGapQN, ... (pure)
dofile(_mdir .. 'difficulty_generate_prokeys.lua') -- GenPKReleaseGapQN, GEN_PK_* (pure)
dofile(_mdir .. 'midi_length_rules.lua')

dofile(_tdir .. 'midi_length_rules.lua')
Test.report()
