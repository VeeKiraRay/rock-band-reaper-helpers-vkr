-- Scores Animation > Drums (DrumAnimPlan) against the official charts' drum
-- animation notes, beside a CAT-like reference (CAT's drums_animations hand
-- rule: strict R L R L through runs up to an 8th apart).
--
--   lua dev/tools/drum_anim_eval_offline.lua [dev|holdout|all] [csv]
--   DRUM_ANIM_BLUE=pick - "Blue cymbal: open hi-hat" on for the songs that play
--   blue as the hi-hat (see below), as their authors would choose.
--
-- Corpus: _external_docs/all_rb3_dlc_reference_songs (local, not in the repo).
-- Hold-out, declared 2026-11-08 BEFORE any tuning: every 5th song by sorted
-- shortname (index % 5 == 0). Tune on `dev` only; run `holdout` once, when the
-- rules are final, and record the number - never tune on it afterwards.
-- SPENT: run once on 2026-11-08 (hand 94.4%; the numbers are in
-- .claude/CLAUDE_general.md, "Feature: Animation > Drums").
--
-- Metrics, per hit time where the official track has hand notes:
--   piece   - single-hand hits: same kit piece (snare, tom 1, crash 2, ...)
--   hand    - single-hand hits: same hand (L / R), by speed
--   two     - two-hand hits: same pieces and hands
--   kick    - kick gem -> kick note present

local _dir = arg[0]:match('^(.+[\\/])') or './'
local _root = _dir .. '../../'
dofile(_dir .. 'smf_reader.lua')
r, S = nil, {}
dofile(_root .. 'rock_band_general_helper_vkr/animation_drums.lua')

-- Try a parameter change without editing the planner:
--   DRUM_ANIM_SET="crash_keep_qn=-1,drum_fast_ms=160" lua dev/tools/drum_anim_eval_offline.lua
for kv in (os.getenv('DRUM_ANIM_SET') or ''):gmatch('[^,]+') do
    local k, v = kv:match('^%s*([%w_]+)%s*=%s*(%S+)')
    if k then DRUM_ANIM_PARAMS[k] = tonumber(v) or v print('param ' .. k .. ' = ' .. v) end
end

local mode = arg[1] or 'dev'
local files = SmfListFiles(_root .. '_external_docs/all_rb3_dlc_reference_songs')
local names = {}
for _, f in ipairs(files) do names[#names + 1] = { f = f, n = SmfShortname(f) } end
table.sort(names, function(a, b) return a.n < b.n end)

-- official note -> piece, hand
local OFF = {}
for piece, info in pairs(DRUM_ANIM_PIECES) do
    for _, k in ipairs({ 'L', 'R', 'Ls', 'Rs' }) do
        if info[k] then OFF[info[k]] = { piece, k:sub(1, 1) } end
    end
end
OFF[40] = { 'c1', 'R' }   -- chokes: hit with the right hand
OFF[41] = { 'c2', 'R' }
OFF[32] = { 'perc', 'R' }

-- CAT-like hands over the same pieces: runs of single-hand hits up to an 8th
-- apart alternate from the run start (on the 8th grid -> R, else L); cymbals
-- join only from 4 in a row; everything else keeps its usual hand.
local function CatHands(onsets)
    local fill = 0
    for i, o in ipairs(onsets) do
        if #o.pieces == 1 then
            local p = o.pieces[1]
            local info = DRUM_ANIM_PIECES[p]
            local prev, nxt = onsets[i - 1], onsets[i + 1]
            local close_prev = prev and #prev.pieces == 1 and (o.qn - prev.qn) <= 0.5 + 1e-6
            local close_next = nxt and #nxt.pieces == 1 and (nxt.qn - o.qn) <= 0.5 + 1e-6
            local cym_ok = not info.cym or (o.cym_run or 1) >= 4
            local hand = info.hand
            if cym_ok and close_prev and fill > 0 then
                local odd = fill % 2 == 1
                hand = odd and (p == 'sn' and 'R' or 'L') or (p == 'sn' and 'L' or 'R')
                fill = fill + 1
            elseif cym_ok and close_next then
                local bp = DrumAnimBeatPos(o.qn)
                if bp == 'beat' or bp == 'and' then hand = 'R' fill = 1 else hand = 'L' fill = 2 end
            else
                fill = 0
            end
            o.cat = { { p, hand } }
        else
            fill = 0
            o.cat = o.hands
        end
    end
end

local M = {}
local function Add(key, ok) M[key] = M[key] or { 0, 0 } M[key][2] = M[key][2] + 1 if ok then M[key][1] = M[key][1] + 1 end end

local songs = 0
for i, e in ipairs(names) do
    local hold = (i % 5 == 0)
    if mode == 'all' or (mode == 'holdout') == hold then
        local song = SmfReadFile(e.f)
        local t = song and SmfFindTrack(song, 'PART DRUMS')
        if t then
            songs = songs + 1
            local tp, map = song.tpqn, SmfTempoMap(song)
            local gems, toms, texts, off = {}, {}, {}, {}
            for _, n in ipairs(t.notes) do
                local qn = n.tick / tp
                if n.pitch >= 95 and n.pitch <= 100 then
                    gems[#gems + 1] = { qn = qn, sec = SmfTickToSec(map, tp, n.tick), pitch = n.pitch }
                elseif n.pitch >= 110 and n.pitch <= 112 then
                    toms[#toms + 1] = { qn_s = qn, qn_e = (n.tick + math.max(n.len, 1)) / tp, pitch = n.pitch }
                elseif n.pitch >= 24 and n.pitch <= 51 and n.pitch ~= 25 then
                    local k = math.floor(qn * 32 + 0.5)
                    off[k] = off[k] or {}
                    table.insert(off[k], n.pitch)
                end
            end
            for _, x in ipairs(t.texts) do texts[#texts + 1] = { qn = x.tick / tp, text = x.text } end
            local onsets = DrumAnimOnsets(gems, toms, DrumAnimDiscoSpans(texts))
            -- DRUM_ANIM_BLUE=pick: the "Blue cymbal: open hi-hat" option turned on for
            -- the songs whose official chart plays blue as the hi-hat 90%+ (as the
            -- author of that song would pick it).
            local opts = {}
            if os.getenv('DRUM_ANIM_BLUE') == 'pick' then
                local hh, n = 0, 0
                for _, o in ipairs(onsets) do
                    if o.B and not o.Bt and not o.disco and not o.Y and not o.G then
                        local k = math.floor(o.qn * 32 + 0.5)
                        local got = off[k] or off[k - 1] or off[k + 1] or {}
                        for _, p in ipairs(got) do
                            local x = OFF[p]
                            if x and x[1] ~= 'sn' then
                                n = n + 1
                                if x[1] == 'hh' then hh = hh + 1 end
                                break
                            end
                        end
                    end
                end
                if n >= 20 and hh / n >= 0.9 then opts.blue_hh = true blue_songs = (blue_songs or 0) + 1 end
            end
            DrumAnimPlan(onsets, opts)
            CatHands(onsets)
            for _, o in ipairs(onsets) do
                local k = math.floor(o.qn * 32 + 0.5)
                local got = off[k] or off[k - 1] or off[k + 1] or {}
                local hands, kick = {}, false
                for _, p in ipairs(got) do
                    if p == 24 then kick = true elseif OFF[p] then hands[#hands + 1] = OFF[p] end
                end
                if o.K then Add('kick', kick) end
                if #hands > 0 and #o.hands > 0 then
                    local function Key(list)
                        local s = {}
                        for _, h in ipairs(list) do s[#s + 1] = h[1] .. h[2] end
                        table.sort(s)
                        return table.concat(s, ' ')
                    end
                    Add('every hand hit exact', Key(o.hands) == Key(hands))
                    if o.R and not (o.Y or o.B or o.G) then Add('snare-only hits exact', Key(o.hands) == Key(hands)) end
                end
                if #o.hands == 1 and #hands == 1 then
                    local prev = o.prev_sec
                    Add('piece', o.hands[1][1] == hands[1][1])
                    local ok = o.hands[1][2] == hands[1][2]
                    local cok = o.cat[1][2] == hands[1][2]
                    Add('hand (ours)', ok) Add('hand (CAT-like)', cok)
                    Add('hand (usual hand only)', DRUM_ANIM_PIECES[o.hands[1][1]].hand == hands[1][2])
                end
                if #o.hands == 2 and #hands == 2 then
                    local function Key(list)
                        local s = {}
                        for _, h in ipairs(list) do s[#s + 1] = h[1] .. h[2] end
                        table.sort(s)
                        return table.concat(s, ' ')
                    end
                    Add('two-hand exact', Key(o.hands) == Key(hands))
                end
            end
            -- speed buckets for single hands
            local last
            for _, o in ipairs(onsets) do
                if #o.hands > 0 then
                    if #o.hands == 1 and last then
                        local k = math.floor(o.qn * 32 + 0.5)
                        local got = off[k] or off[k - 1] or off[k + 1] or {}
                        local hands = {}
                        for _, p in ipairs(got) do if p ~= 24 and OFF[p] then hands[#hands + 1] = OFF[p] end end
                        if #hands == 1 then
                            local ms = (o.sec - last.sec) * 1000
                            local b = ms < 130 and 'fast <130ms' or ms < 220 and 'mid 130-220' or 'slow 220+'
                            Add('hand ours   ' .. b, o.hands[1][2] == hands[1][2])
                            Add('hand CAT    ' .. b, o.cat[1][2] == hands[1][2])
                        end
                    end
                    last = o
                end
            end
        end
    end
end

print(string.format('Drum animation vs official - %s, %d songs', mode, songs))
if blue_songs then print(string.format('  "Blue cymbal: open hi-hat" picked for %d songs', blue_songs)) end
local keys = {}
for k in pairs(M) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
    local v = M[k]
    print(string.format('  %-28s %7.2f%%  (%d)', k, 100 * v[1] / v[2], v[2]))
end
