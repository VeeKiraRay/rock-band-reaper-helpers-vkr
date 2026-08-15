-- Compatibility loader. The gem scorer now lives in lib/reaper_difficulty_score.lua,
-- because the shipped Metadata > Difficulty suggestion and this calibration harness must
-- run the SAME measurement code - the fitted coefficients only mean anything paired with
-- the exact factor implementation they were measured against.
--
-- This file stays so the five run_*.lua entry points here need no edits. Those scripts
-- encode a locked, reproducible experiment; changing their load lists to chase a file
-- move is churn on the one thing that should not move.
--
-- debug.getinfo rather than get_action_context: that returns the ENTRY POINT's path, not
-- this chunk's, and this file is dofile'd from several different directories (REAPER
-- actions, the offline runner, the test runners). The source field is whatever path the
-- caller passed to dofile, so a relative call from the repo root resolves to a relative
-- root, which is correct.

local _self = debug.getinfo(1, 'S').source:match('^@(.*)$')
local _dir  = _self and _self:match('^(.+[\\/])') or ''

-- 'a/b/c/' -> 'a/b/'. No match means there is nothing left to strip, which is the
-- repo root reached as a relative path.
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end

dofile(_up(_up(_dir)) .. 'lib/reaper_difficulty_score.lua')
