-- Compatibility loader. The vocal scorer now lives in
-- lib/reaper_difficulty_score_vocals.lua. See difficulty_score.lua beside this file for
-- why the loaders exist and why debug.getinfo is used to find the repo root.
--
-- Load order is unchanged and still matters: this must come after difficulty_score.lua
-- (it uses that file's span helpers and appends the vocal columns to SCORE_FACTOR_KEYS)
-- and before anything that reads that list.

local _self = debug.getinfo(1, 'S').source:match('^@(.*)$')
local _dir  = _self and _self:match('^(.+[\\/])') or ''
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end

dofile(_up(_up(_dir)) .. 'lib/reaper_difficulty_score_vocals.lua')
