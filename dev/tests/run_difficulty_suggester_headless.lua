-- Repo root, derived from this script rather than hardcoded so the file is portable.
local _self = (arg and arg[0]) or 'dev/tests/run_difficulty_suggester_headless.lua'
-- Two cases: invoked from the repo root (arg[0] carries dev/tests/), or from this
-- directory (arg[0] is a bare filename). Both script folders sit two levels down.
local _here = _self:match('^(.+[/\\])')
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local root = _here and _up(_up(_here)) or '../../'
if root == '' then root = './' end
if not io.open(root .. 'lib/reaper_difficulty_score.lua', 'r') then
    io.write(('Could not locate the repo root (tried %q).\n'):format(root))
    io.write('Run from the repository root.\n')
    os.exit(1)
end
reaper = {
    ShowConsoleMsg = function(s) io.write(s) end,
    ClearConsole   = function() end,
    get_action_context = function() return false, root .. 'dev/tests/run_difficulty_suggester.lua', 0,0,0,0 end,
    time_precise = os.clock, defer = function() end,
}
r = reaper
ctx = nil
dofile(root .. 'dev/tests/framework.lua')
dofile(root .. 'lib/reaper_difficulty_score.lua')
dofile(root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(root .. 'lib/reaper_difficulty_tiers.lua')
dofile(root .. 'lib/reaper_difficulty_predict.lua')
dofile(root .. 'lib/reaper_difficulty_models.lua')
dofile(root .. 'rock_band_general_helper_vkr/difficulty_explain.lua')
dofile(root .. 'rock_band_general_helper_vkr/difficulty_report.lua')
dofile(root .. 'dev/calibration/stats.lua')
dofile(root .. 'dev/calibration/weirdly_scored.lua')
dofile(root .. 'dev/calibration/protocol.lua')
dofile(root .. 'dev/tests/difficulty_suggester.lua')
Test.report()
