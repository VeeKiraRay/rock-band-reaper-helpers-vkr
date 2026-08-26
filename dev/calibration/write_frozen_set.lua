-- Regenerate _external_docs/all_rb3_dlc_reference_songs/FROZEN_DEVELOPMENT_SET.txt.
--
--     lua dev/calibration/write_frozen_set.lua
--
-- RUN THIS AFTER ANY RESCORE. That file is not a convenience listing: it DEFINES the
-- reserved test partition by complement - any song in the rb3 root not listed in it has
-- never been walked - and run_calibration_vkr.lua's SPEND_RESERVED_PARTITION guard is
-- written against that definition. A stale copy silently reclassifies rows in whichever
-- direction the corpus moved.
--
-- Lives in the repo rather than in a scratchpad for exactly that reason: the artifact is
-- load-bearing and gitignored, so without a tracked generator it could not be rebuilt.
--
-- It records TWO hashes per song, and the distinction is the point:
--   scored_hash    the bytes the corpus was actually measured from, taken from the
--                  previous frozen record. Historical truth; never recomputed.
--   current_hash   the bytes of the copy that survives consolidation.
-- They differ on exactly three songs, all investigated and all negligible. Overwriting
-- scored_hash with current_hash would erase the only evidence that they ever differed.

-- Repo root, derived from this script rather than hardcoded so the file is portable.
local _self = (arg and arg[0]) or 'dev/calibration/write_frozen_set.lua'
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
    if not f then return nil, 0 end
    local s = f:read('a')
    f:close()
    local h, n, i = FNV_OFFSET, #s, 1
    while i <= n do
        local j = (i + 4095 < n) and (i + 4095) or n
        local b = { string.byte(s, i, j) }
        for k = 1, #b do h = (h ~ b[k]) * FNV_PRIME end
        i = j + 1
    end
    return string.format('%016x', h), n
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

local ROOTS = { 'all_rb3_dlc_reference_songs', 'aux_reference_songs', 'rbn_reference_songs' }
local where = {}
for _, f in ipairs(ROOTS) do
    for base, path in pairs(ListMids(f)) do
        if not where[base] then where[base] = { root = f, path = path } end
    end
end

-- The previous record, for scored_hash.
local prev = {}
do
    local f = io.open(ext .. 'all_rb3_dlc_reference_songs/FROZEN_DEVELOPMENT_SET.txt', 'rb')
    if f then
        local body = false
        for line in f:lines() do
            if line:match('^shortname%s+origin') then body = true
            elseif body then
                local sn, o, h = line:match('^(%S+)%s+(%S+)%s+(%x+)%s+%d+')
                if sn and #h == 16 then prev[sn] = h end
            end
        end
        f:close()
    end
end

-- Scored rows.
local origin, packs = {}, {}
do
    local f = assert(io.open(root .. 'dev/calibration/corpus_scores.csv'))
    local idx, i = {}, 0
    for c in (f:read('l') .. ','):gmatch('([^,]*),') do i = i + 1; idx[c] = i end
    for line in f:lines() do
        local t = {}
        for c in (line .. ','):gmatch('([^,]*),') do t[#t + 1] = c end
        local sn = (t[idx.shortname] or ''):lower()
        -- rb3_dlc_test rows are the SPENT RESERVED PARTITION and must never be listed
        -- here. This file defines the development set, and the reserved partition is
        -- defined by ABSENCE from it - so sweeping in every scored row, which is what
        -- this loop used to do, would quietly promote the test set to training data the
        -- first time the frozen set was regenerated after spending it. The header's own
        -- instruction to "run this after any rescore" is what would have triggered it.
        if sn ~= '' and t[idx.origin] ~= 'rb3_dlc_test' then
            origin[sn] = t[idx.origin]; packs[sn] = t[idx.pack]
        end
    end
    f:close()
end

local names = {}
for sn in pairs(origin) do names[#names + 1] = sn end
table.sort(names)

local out = assert(io.open(ext .. 'all_rb3_dlc_reference_songs/FROZEN_DEVELOPMENT_SET.txt', 'wb'))
local function W(s) out:write(s) end

W('FROZEN DEVELOPMENT SET - the songs every published difficulty figure rests on\n')
W('===========================================================================\n\n')
W('Generated. This is the corpus that produced dev/calibration/corpus_scores.csv, and\n')
W('through it the coefficients in lib/reaper_difficulty_models.lua.\n\n')
W('LAYOUT. The reference corpus is three origin-separated roots under _external_docs:\n')
W('  all_rb3_dlc_reference_songs/   rb3_dlc only\n')
W('  aux_reference_songs/           lego, rb2, greenday - always-training, never predicted\n')
W('  rbn_reference_songs/           RBN ugc_plus - unscored; ranks are tier floors\n\n')
W('THE RESERVED TEST PARTITION IS DEFINED BY COMPLEMENT. Any song in the rb3 root that\n')
W('is NOT listed below has never been walked and is reserved. That is why the non-rb3\n')
W('origins live in their own roots: putting them here would make 148 RBN charts read as\n')
W('reserved rb3_dlc test data. Scoring a reserved song spends it silently and\n')
W('permanently - see PARTITION / PackIsReserved in dev/calibration/protocol.lua, and do\n')
W('not add the rb3 root to _corpora.\n\n')
W('TWO HASHES, AND THE DIFFERENCE MATTERS.\n')
W('  scored    the bytes the corpus was actually measured from. Historical truth, carried\n')
W('            forward from the pre-consolidation record and never recomputed.\n')
W('  current   the bytes of the copy that survives in the roots above.\n')
W('They differ on exactly three songs, each investigated and each negligible:\n')
W('  wanteddeadoralive2  8 EVENTS notes, a track the scorer does not read\n')
W('  badmedicine         one Pro Keys lane-shift marker moved tick 0 -> 3840\n')
W('  waitandbleed        an ending ritardando in the last four beats; +0.28% on playing_s\n')
W('A shortname alone does not identify a chart, which is the whole reason for hashing.\n\n')
W('Hash is FNV-1a 64 over the whole .mid, the same function protocol.lua uses.\n\n')

local counts, drift, missing = {}, {}, {}
local rows = {}
for _, sn in ipairs(names) do
    local o = origin[sn]
    counts[o] = (counts[o] or 0) + 1
    local w = where[sn]
    if not w then
        missing[#missing + 1] = sn
    else
        local cur, bytes = Hash(w.path)
        local scored = prev[sn] or cur
        if scored ~= cur then drift[#drift + 1] = sn end
        rows[#rows + 1] = ('%-34s %-9s %s %s %9d  %s\n')
            :format(sn, o, scored, (scored == cur) and '       =        ' or cur,
                    bytes, w.root:gsub('_reference_songs', ''))
    end
end

W('SUMMARY\n-------\n')
local ord = {}
for o in pairs(counts) do ord[#ord + 1] = o end
table.sort(ord)
local total = 0
for _, o in ipairs(ord) do
    W(('  %-10s %4d\n'):format(o, counts[o]))
    total = total + counts[o]
end
W(('  %-10s %4d  frozen development songs\n'):format('TOTAL', total))

local rb3 = ListMids('all_rb3_dlc_reference_songs')
local reserved = 0
for base in pairs(rb3) do if not origin[base] then reserved = reserved + 1 end end
W(('\n  %4d songs in the rb3 root are NOT listed below.\n'):format(reserved))
W('       Those are the RESERVED TEST PARTITION. Do not score them.\n')

if #drift > 0 then
    W(('\n  %d song(s) whose surviving copy differs from the scored bytes:\n'):format(#drift))
    for _, sn in ipairs(drift) do W('       ' .. sn .. '\n') end
end
if #missing > 0 then
    W(('\n  %d scored song(s) NOT FOUND in any root - investigate before deleting anything:\n')
        :format(#missing))
    for _, sn in ipairs(missing) do W('       ' .. sn .. '\n') end
end

W('\n\nTHE FROZEN SET\n--------------\n')
W(('%-34s %-9s %-16s %-16s %9s  %s\n')
    :format('shortname', 'origin', 'scored', 'current', 'bytes', 'root'))
for _, r in ipairs(rows) do W(r) end
out:close()

io.write(('wrote FROZEN_DEVELOPMENT_SET.txt: %d songs, %d reserved, %d byte-drift, %d missing\n')
    :format(total, reserved, #drift, #missing))
