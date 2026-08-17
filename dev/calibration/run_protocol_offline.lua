-- Offline driver for run_calibration_protocol_vkr.lua. Run from the repository root:
--   lua dev/calibration/run_protocol_offline.lua
--
-- WHY THIS EXISTS. The protocol is pure statistics over corpus_scores.csv - it touches
-- `reaper` only for path derivation and console output, so REAPER contributes nothing
-- to it but a UI thread to block. At 318 songs the in-REAPER run stopped completing:
-- a ReaScript holds the main thread for the whole computation, so REAPER goes "Not
-- responding" and was killed partway through writing the report. Offline the same work
-- finishes in about two minutes.
--
-- Sleeps or coroutines do not help. The cost is one long synchronous computation, not
-- contention, so there is nothing to yield to; the only in-REAPER fix would be
-- rewriting the candidate/repeat/fold loops as a defer state machine, which is a large
-- change to a dev-only script that would produce identical numbers more slowly.
-- ShowConsoleMsg is itself a real cost here - the report is tens of KB emitted line by
-- line, and REAPER's console is slow.
--
-- THE NUMBERS ARE THE SAME. Fold assignment uses math.random seeded explicitly by
-- ShuffledStratifiedFolds, and REAPER's Lua and the standalone interpreter are both
-- 5.4, whose PRNG is specified - so this is not merely "comparable within a run", it
-- reproduces a REAPER run exactly. Verified against the partial report from the run
-- that crashed: all 59 completed lines byte-identical, the only difference being that
-- run's truncated final line.
--
-- Writes the same calibration_protocol_report.txt the REAPER action does.

local script = (arg and arg[0]) or 'dev/calibration/run_protocol_offline.lua'
local dir    = script:match('^(.+[/\\])') or 'dev/calibration/'
local runner = dir .. 'run_calibration_protocol_vkr.lua'

-- Enough of the API for a script that only reports. get_action_context's second return
-- is the script path, which is how the runner locates the CSV beside itself.
reaper = {
    get_action_context = function() return false, runner, 0, 0, 0, 0 end,
    ClearConsole       = function() end,
    ShowConsoleMsg     = function(s) io.write(s) end,
    ShowMessageBox     = function(s) io.write('MSGBOX: ' .. tostring(s) .. '\n') end,
    time_precise       = os.clock,
    defer              = function() end,
}

dofile(runner)
