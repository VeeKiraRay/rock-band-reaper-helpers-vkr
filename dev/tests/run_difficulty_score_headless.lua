-- Headless driver for the pure calibration test sets. Stubs the handful of reaper
-- APIs the framework touches; everything under test here is pure Lua.
-- Repo root, derived from this script rather than hardcoded so the file is portable.
local _self = (arg and arg[0]) or 'dev/tests/run_difficulty_score_headless.lua'
-- Two cases: invoked from the repo root (arg[0] carries dev/tests/), or from this
-- directory (arg[0] is a bare filename). Both script folders sit two levels down, so the
-- second case resolves to ../../ rather than the cwd.
local _here = _self:match('^(.+[/\\])')
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local root = _here and _up(_up(_here)) or '../../'
if root == '' then root = './' end
-- Fail with a sentence rather than a stack trace: a wrong root shows up as a confusing
-- 'no such file' from whichever dofile happens to run first.
if not io.open(root .. 'lib/reaper_difficulty_score.lua', 'r') then
    io.write(('Could not locate the repo root (tried %q).\n'):format(root))
    io.write('Run from the repository root:  lua dev/tests/' ..
             (_self:match('([^/\\]+)$') or '?') .. '\n')
    os.exit(1)
end
reaper = {
    ShowConsoleMsg = function(s) io.write(s) end,
    ClearConsole   = function() end,
    get_action_context = function() return false, root .. 'dev/tests/run_difficulty_score.lua', 0,0,0,0 end,
    time_precise   = os.clock,
    defer          = function() end,
}
r = reaper
ctx = nil
dofile(root .. 'dev/tests/framework.lua')
dofile(root .. 'dev/calibration/difficulty_score.lua')
dofile(root .. 'dev/calibration/difficulty_score_vocals.lua')
dofile(root .. 'dev/calibration/songs_dta.lua')
dofile(root .. 'dev/calibration/stats.lua')
dofile(root .. 'dev/calibration/rank_tiers.lua')
dofile(root .. 'dev/calibration/protocol.lua')
dofile(root .. 'dev/tests/difficulty_score.lua')
dofile(root .. 'dev/tests/songs_dta.lua')
dofile(root .. 'dev/tests/calibration_stats.lua')
dofile(root .. 'dev/tests/difficulty_score_vocals.lua')
Test.report()
