-- The Difficulty > Generate hold-out: which reference songs are never used to shape the
-- generator. Shared by run_difficulty_probe_vkr.lua (inside REAPER) and
-- run_generate_eval_offline.lua (plain Lua), so both exclude exactly the same songs.
--
-- Declared before the first probe run looked at anything. Songs whose shortname hash
-- lands on 0 mod DIFF_HOLDOUT_MOD are held out: one song in five. Never change the hash
-- or the modulus - a different split would quietly put held-out songs into the set the
-- generator was tuned on, and nothing afterwards could tell.
--
-- Unrelated to the rank model's reserved partition in this folder; this one only guards
-- the generator's evaluation.

DIFF_HOLDOUT_MOD = 5

-- FNV-1a over the shortname's bytes. Integer arithmetic only, so the split is the same
-- under REAPER's Lua and the offline interpreter, and on every machine.
function DiffHoldoutHash(s)
    local h = 2166136261
    for i = 1, #s do
        h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff
    end
    return h
end

function DiffIsHeldOut(shortname)
    return DiffHoldoutHash(shortname) % DIFF_HOLDOUT_MOD == 0
end
