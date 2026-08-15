-- Compatibility loader. The rank -> tier table now lives in
-- lib/reaper_difficulty_tiers.lua, which also gained TierBand / TierPosition for the
-- suggestion view. See difficulty_score.lua beside this file for why the loaders exist
-- and why debug.getinfo is used to find the repo root.

local _self = debug.getinfo(1, 'S').source:match('^@(.*)$')
local _dir  = _self and _self:match('^(.+[\\/])') or ''
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end

dofile(_up(_up(_dir)) .. 'lib/reaper_difficulty_tiers.lua')
