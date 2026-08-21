-- Verify the three consolidated corpus roots against the frozen development set.
--
--     lua dev/calibration/verify_corpus_roots.lua
--
-- Run it after moving, adding or deleting anything under _external_docs. It is what said
-- the 2026-08-21 consolidation was safe, and it is the check to repeat before the older
-- reference folders are finally removed.
--
-- Four things have to hold.
--
--   1. Every one of the 394 frozen development songs is findable in the new roots.
--   2. Each moved file is BYTE-IDENTICAL to the copy the corpus was scored from.
--   3. Nothing unique is left in the old folders.
--   4. The rb3 folder's reserved count is UNCHANGED at 258 - the 25 songs added were
--      already-scored development rows, so they must not enlarge the test partition.

-- Repo root, derived from this script rather than hardcoded so the file is portable.
local _self = (arg and arg[0]) or 'dev/calibration/verify_corpus_roots.lua'
-- Two cases: invoked from the repo root (arg[0] carries dev/calibration/), or from this
-- directory (arg[0] is a bare filename). Both script folders sit two levels down.
local _here = _self:match('^(.+[/\\])')
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local root = _here and _up(_up(_here)) or '../../'
if root == '' then root = './' end
if not io.open(root .. 'dev/calibration/corpus_scores.csv', 'r') then
    io.write(('Could not locate the repo root (tried %q).\n'):format(root))
    io.write('Run from the repository root.\n')
    os.exit(1)
end
local ext  = root .. '_external_docs/'

local FNV_OFFSET, FNV_PRIME = 0xcbf29ce484222325, 0x100000001b3
local function Hash(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    local h, n, i = FNV_OFFSET, #s, 1
    while i <= n do
        local j = (i + 4095 < n) and (i + 4095) or n
        local b = { string.byte(s, i, j) }
        for k = 1, #b do h = (h ~ b[k]) * FNV_PRIME end
        i = j + 1
    end
    return string.format('%016x', h)
end

local function ListMids(folder)
    local out = {}
    local p = io.popen(('cmd /c dir /b /s "%s\\*.mid" 2>nul'):format(
        (ext .. folder):gsub('/', '\\')))
    if not p then return out end
    for line in p:lines() do
        local base = line:match('([^\\/]+)%.[Mm][Ii][Dd]$')
        if base then
            base = base:lower()
            out[base] = out[base] or line
        end
    end
    p:close()
    return out
end

local NEW_ROOTS = { 'all_rb3_dlc_reference_songs', 'aux_reference_songs', 'rbn_reference_songs' }
local OLD_ROOTS = { 'reference_songs', 'new_reference_songs', 'hard_reference_songs' }

local newsets, union = {}, {}
for _, f in ipairs(NEW_ROOTS) do
    newsets[f] = ListMids(f)
    local n = 0
    for b, p in pairs(newsets[f]) do
        n = n + 1
        union[b] = union[b] or { root = f, path = p }
    end
    io.write(('%-32s %4d songs\n'):format(f, n))
end
local nunion = 0
for _ in pairs(union) do nunion = nunion + 1 end
io.write(('%-32s %4d distinct songs across the three roots\n\n'):format('UNION', nunion))

-- Frozen set with the hash each song was scored from.
local frozen = {}
do
    local f = assert(io.open(ext .. 'all_rb3_dlc_reference_songs/FROZEN_DEVELOPMENT_SET.txt', 'rb'))
    local body = false
    for line in f:lines() do
        if line:match('^shortname%s+origin') then body = true
        elseif body then
            -- Row shape is: shortname origin scored current bytes root, where `current`
            -- is either a second 16-hex hash or a bare '=' when it matches `scored`.
            --
            -- Two parser bugs have already happened here and both failed the same silent
            -- way - an empty frozen set makes every check below pass or report everything
            -- as reserved, rather than erroring. So the count is asserted at the end.
            -- (First was '%x16', which is not Lua pattern syntax at all; second was this
            -- pattern written for the single-hash format it replaced.)
            local sn, o, scored, cur = line:match('^(%S+)%s+(%S+)%s+(%x+)%s+(%S+)%s+%d+')
            if sn and #scored == 16 then
                frozen[sn] = { origin = o, hash = scored,
                               current = (cur == '=') and scored or cur }
            end
        end
    end
    f:close()
end
local nf = 0
for _ in pairs(frozen) do nf = nf + 1 end
io.write(('frozen development set: %d songs\n\n'):format(nf))
-- Refuse to report on an empty or implausible parse. Every check below is a membership
-- test against this set, so a parse failure would otherwise read as a clean bill of
-- health or as "everything is reserved" - both of which have already happened.
if nf < 300 then
    io.write('REFUSING TO CONTINUE: the frozen set parsed as ' .. nf .. ' songs.\n')
    io.write('That is a parser failure, not a corpus finding - the file holds 394.\n')
    os.exit(1)
end

------------------------------------------------------------------
io.write('1. FROZEN SONGS FINDABLE IN THE NEW ROOTS\n')
local missing, wrong_root = {}, {}
local EXPECT_ROOT = {
    rb3_dlc = 'all_rb3_dlc_reference_songs',
    lego = 'aux_reference_songs', rb2 = 'aux_reference_songs',
    greenday = 'aux_reference_songs',
}
for sn, rec in pairs(frozen) do
    local u = union[sn]
    if not u then
        missing[#missing + 1] = sn .. ' (' .. rec.origin .. ')'
    elseif EXPECT_ROOT[rec.origin] and u.root ~= EXPECT_ROOT[rec.origin] then
        wrong_root[#wrong_root + 1] = ('%s: %s is in %s, expected %s')
            :format(sn, rec.origin, u.root, EXPECT_ROOT[rec.origin])
    end
end
io.write(('   missing: %d   in the wrong root: %d\n'):format(#missing, #wrong_root))
for i = 1, math.min(#missing, 10) do io.write('     MISSING ' .. missing[i] .. '\n') end
for i = 1, math.min(#wrong_root, 10) do io.write('     ' .. wrong_root[i] .. '\n') end

------------------------------------------------------------------
io.write('\n2. BYTES MATCH WHAT THE CORPUS WAS SCORED FROM\n')
local mismatch, unchecked = {}, 0
for sn, rec in pairs(frozen) do
    local u = union[sn]
    if u and rec.hash then
        local h = Hash(u.path)
        if h ~= rec.hash then
            mismatch[#mismatch + 1] = ('%s  frozen %s  now %s'):format(sn, rec.hash, tostring(h))
        end
    else
        unchecked = unchecked + 1
    end
end
io.write(('   mismatches: %d   unchecked: %d\n'):format(#mismatch, unchecked))
for i = 1, math.min(#mismatch, 12) do io.write('     ' .. mismatch[i] .. '\n') end
io.write('   (the three known same-name-different-bytes charts are expected here:\n')
io.write('    the rb3 folder holds its own copy of badmedicine / waitandbleed /\n')
io.write('    wanteddeadoralive2, and the frozen hash names the reference_songs one)\n')

------------------------------------------------------------------
io.write('\n3. ANYTHING LEFT UNIQUE IN THE OLD FOLDERS\n')
local left = {}
for _, f in ipairs(OLD_ROOTS) do
    for base in pairs(ListMids(f)) do
        if not union[base] then left[#left + 1] = base .. '  (' .. f .. ')' end
    end
end
table.sort(left)
io.write(('   %d basenames exist only in the old folders\n'):format(#left))
for i = 1, math.min(#left, 12) do io.write('     ' .. left[i] .. '\n') end

------------------------------------------------------------------
io.write('\n4. RESERVED PARTITION UNCHANGED\n')
local rb3 = newsets['all_rb3_dlc_reference_songs']
local dev, reserved = 0, 0
for base in pairs(rb3) do
    if frozen[base] then dev = dev + 1 else reserved = reserved + 1 end
end
io.write(('   rb3 root: %d development, %d reserved\n'):format(dev, reserved))
io.write(('   reserved was 258 before the move; %s\n')
    :format(reserved == 258 and 'UNCHANGED - correct' or '*** CHANGED - investigate ***'))
