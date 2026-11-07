-- Chord detect parity - offline, pure Lua (+ ffmpeg unless cached), no REAPER.
--
-- Checks that lib/reaper_chord_detect.lua (what the Instrument Helper's Keys > Tuner runs)
-- gives the same answers as dev/tools/chord_core.lua (the method the 2026-11 chord probe
-- rounds measured), on the keys stems of the decrypted official moggs. The shipped accuracy
-- numbers only apply while this passes.
--
--   lua dev/tools/chord_detect_parity_offline.lua [all | shortname ...]
--
-- Default songs: a few with many charted chords; 'all' = every development song (held-out
-- songs are never read), which also re-measures the core's own accuracy against the chart -
-- it must stay at the frozen method's number (81.4% first, key from charted vocals).
-- Inputs and env: see harmony_audio_core.lua (HAP_CACHE advised; stems cached as
-- <shortname>_keys.s16 / <shortname>_bass.s16).
--
-- Passage check (single notes or chords): every 4 s passage of the song, frame by frame (the
-- per-pitch sums) and per passage (onsets found, value, verdict, struck notes); with 'all',
-- the core's verdict on passages whose chart onsets are all single notes or all 3+ pitch
-- class chords (must stay at the measured ~54% singles found / ~90% chords kept).
--
-- Per charted Pro Keys Expert chord (3+ pitch classes matching a template): every frame's
-- chroma, the bass readings, and the ranking with and without "prefer plain chords".

local _dir  = (arg[0]:match('^(.+[\\/])') or './')
local _root = _dir .. '../../'
dofile(_dir .. 'smf_reader.lua')
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_root .. 'lib/reaper_spectrum.lua')
dofile(_root .. 'lib/reaper_chord_detect.lua')
dofile(_root .. 'lib/reaper_key_detect.lua')
dofile(_root .. 'lib/reaper_key_profiles.lua')
dofile(_root .. 'dev/calibration/difficulty_holdout.lua')
local H = dofile(_dir .. 'harmony_audio_core.lua')
local C = dofile(_dir .. 'chord_core.lua')

local ALL = arg[1] == 'all'
local SONGS = {}
for i = 1, #arg do SONGS[arg[i]] = true end
if #arg == 0 then
    for _, s in ipairs({ 'onlythelonely', 'lightmyfire', 'touchme', 'takeonme', 'bluemonday' }) do SONGS[s] = true end
end

assert(C.SR == CHORD_SR and C.FRAME_N == CHORD_FRAME_N and C.BASS_N == CHORD_BASS_N,
    'the core and the lib must read the same windows')
local SR = C.SR

local function Mono(pcm, s, n)
    local total, x = #pcm // 4, {}
    for i = 1, n do
        local k = s + i - 1
        local a, b = 0, 0
        if k >= 1 and k <= total then a, b = string.unpack('<i2i2', pcm, (k - 1) * 4 + 1) end
        x[i] = (a + b) / 65536
    end
    return x
end

-- Charted Pro Keys Expert chords: notes 48-72 sounding just after each onset.
local function Chords(song, map)
    local trk = SmfFindTrack(song, 'PART REAL_KEYS_X')
    if not trk then return nil end
    local notes = {}
    for _, n in ipairs(trk.notes) do
        if n.pitch >= 48 and n.pitch <= 72 and n.len > 0 then
            notes[#notes + 1] = { pitch = n.pitch, tick = n.tick,
                s = SmfTickToSec(map, song.tpqn, n.tick), e = SmfTickToSec(map, song.tpqn, n.tick + n.len) }
        end
    end
    table.sort(notes, function(a, b) return a.tick < b.tick end)
    local ons = {}
    for _, n in ipairs(notes) do
        if not ons[#ons] or ons[#ons].tick ~= n.tick then ons[#ons + 1] = { tick = n.tick, s = n.s } end
    end
    local out, first = {}, 1
    for i, o in ipairs(ons) do
        o.next = ons[i + 1] and ons[i + 1].s or o.s + 1.0
        local mask, npc = 0, 0
        while notes[first] and notes[first].e < o.s do first = first + 1 end
        for j = first, #notes do
            local n = notes[j]
            if n.s > o.s then break end
            if n.tick == o.tick or n.e > o.s + 0.030 then
                local bit = 1 << (n.pitch % 12)
                if mask & bit == 0 then mask, npc = mask | bit, npc + 1 end
            end
        end
        if npc >= 3 and C.LABEL[mask] then o.mask = mask; out[#out + 1] = o end
    end
    return out
end

local function VocalKeyMask(song, map)
    local notes = H.PitchedNotes(song, map, SmfFindTrack(song, 'PART VOCALS'))
    if #notes == 0 then return nil end
    local kn = {}
    for _, n in ipairs(notes) do kn[#kn + 1] = { pitch = n.pitch, qn = n.s, len = n.e - n.s } end
    local ranked = KeyRankSet(KeyFeatures({ vocals = kn }), KEY_RESULT_SETS[1], RB_KEY_PROFILES.sources)
    if not (ranked and ranked[1]) then return nil end
    local a, b = C.KeyMask(ranked[1].tonic, ranked[1].minor), ChordKeyMask(ranked[1].tonic, ranked[1].minor)
    assert(a == b, 'key masks differ')
    return a
end

local frames, chords, right = 0, 0, 0
local passages, pure_s, pure_c, found_s, kept_c = 0, 0, 0, 0, 0

-- Per 4 s passage: chart onsets starting single notes / 3+ pitch classes.
local function ChartPassages(song, map)
    local trk = SmfFindTrack(song, 'PART REAL_KEYS_X')
    local by = {}
    for _, n in ipairs(trk and trk.notes or {}) do
        if n.pitch >= 48 and n.pitch <= 72 and n.len > 0 then
            by[n.tick] = (by[n.tick] or 0) | (1 << (n.pitch % 12))
        end
    end
    local win = {}
    for tick, mask in pairs(by) do
        local k = math.floor(SmfTickToSec(map, song.tpqn, tick) / 4.0)
        local w = win[k] or { n = 0, single = 0, chord = 0 }
        win[k] = w
        local npc = 0
        for pc = 0, 11 do if mask & (1 << pc) ~= 0 then npc = npc + 1 end end
        w.n = w.n + 1
        if npc == 1 then w.single = w.single + 1 elseif npc >= 3 then w.chord = w.chord + 1 end
    end
    return win
end
local mism = {}
local function Bad(what, sn, t, a, b)
    mism[what] = (mism[what] or 0) + 1
    if mism[what] <= 3 then
        print(('  MISMATCH %-8s %s at %.3f s: core %s, lib %s'):format(what, sn, t, tostring(a), tostring(b)))
    end
end

for _, mogg in ipairs(SmfListFiles(_root .. H.FOLDER_REL, 'decrypted[\\/][^\\/]+%.mogg$')) do
    local sn = mogg:match('([^\\/]+)%.[Mm][Oo][Gg][Gg]$')
    if (ALL or SONGS[sn]) and not DiffIsHeldOut(sn) then
        local song_dir = mogg:match('^(.*[\\/])decrypted[\\/]')
        local dta = H.read_all(song_dir:match('^(.*[\\/])[^\\/]+[\\/]$') .. 'songs.dta')
        local song = SmfReadFile(song_dir .. sn .. '.mid')
        local info = dta and H.DtaInfo(dta, sn, 'keys')
        local map = song and SmfTempoMap(song)
        local list = song and Chords(song, map)
        local pcm = info and list and H.Decode(mogg, info, sn)
        if type(pcm) ~= 'string' then
            if not ALL then print('skipped ' .. sn) end
        else
            local binfo = H.DtaInfo(dta, sn, 'bass')
            local bpcm = binfo and H.Decode(mogg, binfo, sn)
            if type(bpcm) ~= 'string' then bpcm = nil end
            local km = VocalKeyMask(song, map)
            local cents = info.cents
            for _, o in ipairs(list) do
                -- frames: onset + 30 ms, then every 64 ms while the next onset is a frame away
                local core_sum, lib_sum = {}, ChordSumNew()
                for i = 0, 11 do core_sum[i] = 0 end
                local any = false
                for k = 0, C.SPAN_MAX - 1 do
                    local st = o.s + C.ATTACK_S + k * C.HOP_S
                    if k > 0 and st + 0.064 > o.next then break end
                    local mono = Mono(pcm, math.floor(st * SR) + 1, C.FRAME_N)
                    local a, b = C.FrameChroma(mono, cents), ChordFrameChroma(mono, cents)
                    frames = frames + 1
                    if (a == nil) ~= (b == nil) then
                        Bad('silence', sn, st, a ~= nil, b ~= nil)
                    elseif a then
                        any = true
                        for i = 0, 11 do
                            if a[i] ~= b[i] then Bad('chroma', sn, st, a[i], b[i]); break end
                        end
                        for i = 0, 11 do core_sum[i] = core_sum[i] + a[i] end
                        ChordSumAdd(lib_sum, b)
                    end
                end
                -- bass: readings from onset + 60 ms every 60 ms, at most 4, inside the chord
                local core_pcs, lib_pcs = {}, {}
                if bpcm then
                    for k = 0, 3 do
                        local t = o.s + 0.060 + k * C.BASS_STEP_S
                        if k > 0 and t + C.BASS_WIN_S > o.next then break end
                        local mono = Mono(bpcm, math.floor(t * SR) + 1, C.BASS_N)
                        local a, b = C.BassPc(mono, cents), ChordBassPc(mono, cents)
                        if a ~= b then Bad('bass', sn, t, a, b) end
                        if a then core_pcs[#core_pcs + 1] = a end
                        if b then lib_pcs[#lib_pcs + 1] = b end
                    end
                end
                local cb, lb = C.BassVote(core_pcs), ChordBassVote(lib_pcs)
                if cb ~= lb then Bad('bassvote', sn, o.s, cb, lb) end
                chords = chords + 1
                if any then
                    for _, plain in ipairs({ true, false }) do
                        local ct, cm = C.Rank(core_sum, { key_mask = km, bass = cb, plain = plain })
                        local lt, lm = ChordRank(lib_sum, { key_mask = km, bass = lb, plain = plain })
                        for i = 1, 3 do
                            if ct[i].mask ~= lt[i].mask then Bad('rank', sn, o.s, ct[i].mask, lt[i].mask); break end
                        end
                        if math.abs(cm - lm) > 1e-12 then Bad('margin', sn, o.s, cm, lm) end
                        if plain and ct[1].mask == o.mask then right = right + 1 end
                    end
                end
            end
            -- passage check
            local cache = {}
            local function Pair(g)
                local v = cache[g]
                if v == nil then
                    local mono = Mono(pcm, math.floor(g * C.PASS_HOP_S * SR) + 1, C.FRAME_N)
                    local a = C.FramePitches(mono, cents)
                    local _, b = ChordFrameAnalyse(mono, cents)
                    frames = frames + 1
                    if (a == nil) ~= (b == nil) then Bad('pitches', sn, g * C.PASS_HOP_S, a ~= nil, b ~= nil)
                    elseif a then
                        for p = C.PASS_LO, C.TOP_PITCH do
                            if a[p] ~= b[p] then Bad('pitches', sn, g * C.PASS_HOP_S, a[p], b[p]); break end
                        end
                    end
                    v = { a or false, b or false }
                    cache[g] = v
                end
                return v
            end
            local truth = ChartPassages(song, map)
            local dur = #pcm / 4 / SR
            for k = 0, math.floor(dur / 4.0) - 1 do
                local w = truth[k]
                local pure = w and w.n >= 3 and (w.single == w.n or w.chord == w.n)
                if ALL and not pure then goto next_passage end
                do
                    local g0, g1 = math.ceil(k * 4.0 / C.PASS_HOP_S), math.floor((k + 1) * 4.0 / C.PASS_HOP_S) - 1
                    local fa, fb = {}, {}
                    for g = g0 - 3, g1 + 1 do
                        local v = Pair(g)
                        fa[#fa + 1], fb[#fb + 1] = v[1], v[2]
                    end
                    local a, b = C.Passage(fa), ChordPassage(fb)
                    passages = passages + 1
                    if #a.onsets ~= #b.onsets then Bad('onsets', sn, k * 4.0, #a.onsets, #b.onsets)
                    else
                        for i, oa in ipairs(a.onsets) do
                            local ob = b.onsets[i]
                            if oa.i ~= ob.i or oa.note ~= ob.note or oa.tmpl ~= ob.tmpl or oa.st ~= ob.st then
                                Bad('onset', sn, k * 4.0, oa.note, ob.note); break
                            end
                        end
                        if a.value ~= b.value or a.single ~= b.single then Bad('verdict', sn, k * 4.0, a.value, b.value) end
                    end
                    if pure and a.value then
                        if w.single == w.n then
                            pure_s = pure_s + 1
                            if a.single then found_s = found_s + 1 end
                        else
                            pure_c = pure_c + 1
                            if not a.single then kept_c = kept_c + 1 end
                        end
                    end
                end
                ::next_passage::
            end
            print(('%-26s %5d chords'):format(sn, #list))
        end
    end
end

local total = 0
for _, c in pairs(mism) do total = total + c end
print(('Passages %d; pure passages: singles %d (called single %.1f%%), chords %d (kept as chords %.1f%%)'):format(
    passages, pure_s, pure_s > 0 and 100 * found_s / pure_s or 0, pure_c, pure_c > 0 and 100 * kept_c / pure_c or 0))
print(('Chords %d, frames %d, mismatches %d; the core names %.1f%% of the chords right first'):format(
    chords, frames, total, chords > 0 and 100 * right / chords or 0))
for k, c in pairs(mism) do print(('  %-8s %d'):format(k, c)) end
print(total == 0 and 'PARITY OK' or 'PARITY FAILED')
