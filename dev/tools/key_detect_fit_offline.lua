-- Fits and evaluates the Metadata > Song key profiles (lib/reaper_key_detect.lua) against
-- the official RB3 DLC charts, whose songs.dta files carry Harmonix's own
-- vocal_tonic_note and song_tonality. Plain Lua 5.4, no REAPER:
--
--   lua dev/tools/key_detect_fit_offline.lua            -- development songs: 5-fold CV
--                                                          report, then writes
--                                                          lib/reaper_key_profiles.lua
--   lua dev/tools/key_detect_fit_offline.lua report     -- the CV report only, no write
--   lua dev/tools/key_detect_fit_offline.lua holdout    -- the hold-out, ONCE (frozen file)
--
-- No other reference set can check it: the other folders under _external_docs/ repeat
-- these songs, and Rock Band Network songs.dta files carry no vocal_tonic_note.
--
-- THE HOLD-OUT is dev/calibration/difficulty_holdout.lua's split (one song in five, by
-- shortname hash), so the same songs stay unseen by every model in this repo. Tune on the
-- development songs; run 'holdout' once, when the sources and weights are final.
--
-- THE LABELS ARE NOT PERFECT. songs.dta values are Harmonix's judgement from the time,
-- and some disagree with published keys (one well-known pop song is stored a fifth away
-- from the key it is usually listed in). They are still the target: they are what the
-- game was shipped with. Expect accuracy to stop well short of 100%.
--
-- The reading here mirrors rock_band_general_helper_vkr/song_key.lua, which does the same
-- from a REAPER project: same pitch ranges, '#' lyrics dropped as unpitched, bracketed text
-- events ignored when matching lyrics.

local _dir  = (arg and arg[0] or ''):match('^(.+[\\/])') or './'
local _root = _dir .. '../../'
local MODE  = arg and arg[1] or 'dev'

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'dev/calibration/difficulty_holdout.lua')
dofile(_root .. 'lib/reaper_key_detect.lua')

local MAIN = _root .. '_external_docs/all_rb3_dlc_reference_songs/'
local PROFILES_OUT = _root .. 'lib/reaper_key_profiles.lua'

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

-- shortname -> { tonic, minor } from every songs.dta under root. Commented lines are
-- skipped: Magma templates carry ";;(song_key ...)" placeholders.
local function ReadTruth(root)
    local truth = {}
    for _, p in ipairs(SmfListFiles(root, 'songs%.dta$')) do
        local f = io.open(p, 'rb')
        local text = f and f:read('a') or ''
        if f then f:close() end
        local cur
        for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
            local sn = line:match('^%(([%w_]+)')
            if sn then
                cur = {}
                truth[sn] = cur
            elseif cur and not line:match('^%s*;') then
                local t = line:match('%(vocal_tonic_note%s+(%d+)%)')
                if t then cur.tonic = tonumber(t) % 12 end
                local m = line:match('%(song_tonality%s+(%d+)%)')
                if m then cur.minor = tonumber(m) == 1 end
            end
        end
    end
    return truth
end

local function VocalPart(song, name)
    local trk = SmfFindTrack(song, name)
    if not trk then return {} end
    local lyric = {}
    for _, t in ipairs(trk.texts) do
        if (t.type == 1 or t.type == 5) and not t.text:match('^%[') then lyric[t.tick] = t.text end
    end
    local out = {}
    for _, n in ipairs(trk.notes) do
        if n.pitch >= KEY_VOCAL_LO and n.pitch <= KEY_VOCAL_HI
           and not KeyLyricIsUnpitched(lyric[n.tick]) then
            out[#out + 1] = { pitch = n.pitch, qn = n.tick / song.tpqn, len = n.len / song.tpqn }
        end
    end
    return out
end

local function KeysPart(song)
    local trk = SmfFindTrack(song, 'PART REAL_KEYS_X')
    if not trk then return {} end
    local out = {}
    for _, n in ipairs(trk.notes) do
        if n.pitch >= KEY_KEYS_LO and n.pitch <= KEY_KEYS_HI then
            out[#out + 1] = { pitch = n.pitch, qn = n.tick / song.tpqn, len = n.len / song.tpqn }
        end
    end
    return out
end

-- Every song under root with a known tonic: { name, tonic, minor, features }.
local function LoadSongs(root)
    local truth = ReadTruth(root)
    local songs, seen = {}, {}
    for _, path in ipairs(SmfListFiles(root, '%.mid$')) do
        local name = SmfShortname(path)
        local t = truth[name]
        if not name:find('%(') and not seen[name] and t and t.tonic and t.minor ~= nil then
            seen[name] = true
            local song = SmfReadFile(path)
            if song then
                local harm = {}
                for i = 1, 3 do
                    for _, n in ipairs(VocalPart(song, 'HARM' .. i)) do harm[#harm + 1] = n end
                end
                songs[#songs + 1] = {
                    name = name, tonic = t.tonic, minor = t.minor,
                    features = KeyFeatures({
                        vocals = VocalPart(song, 'PART VOCALS'),
                        harm   = harm,
                        keys   = KeysPart(song),
                    }),
                }
            end
        end
    end
    return songs
end

----------------------------------------------------------------------
-- Evaluation
----------------------------------------------------------------------

local function NewTally() return { n = 0, key = 0, tonic = 0, top2 = 0, rel = 0, par = 0, fifth = 0, bands = {} } end

-- Score margin bands: how often the top answer is right when it wins by this much.
local BANDS = { 0.15, 0.08, 0.04, 0 }

local function Tally(t, song, ranked)
    local a, b = ranked[1], ranked[2]
    local ok = a.tonic == song.tonic and a.minor == song.minor
    t.n = t.n + 1
    if ok then t.key = t.key + 1 end
    if a.tonic == song.tonic then t.tonic = t.tonic + 1 end
    if ok or (b.tonic == song.tonic and b.minor == song.minor) then t.top2 = t.top2 + 1 end
    if not ok then
        local rel = KeyRelation(song.tonic, song.minor, a.tonic, a.minor)
        if rel == 'relative' then t.rel = t.rel + 1
        elseif rel == 'parallel' then t.par = t.par + 1
        elseif rel == 'fifth' then t.fifth = t.fifth + 1 end
    end
    local margin = a.score - b.score
    for i, lo in ipairs(BANDS) do
        if margin >= lo then
            local bd = t.bands[i] or { n = 0, ok = 0 }
            t.bands[i] = bd
            bd.n = bd.n + 1
            if ok then bd.ok = bd.ok + 1 end
            break
        end
    end
end

local function Pct(a, n) return n > 0 and 100 * a / n or 0 end

local function PrintTally(label, t)
    if t.n == 0 then
        print(('  %-36s no songs'):format(label))
        return
    end
    print(('  %-36s n=%3d  key %5.1f%%  tonic %5.1f%%  top-2 %5.1f%%'):format(
        label, t.n, Pct(t.key, t.n), Pct(t.tonic, t.n), Pct(t.top2, t.n)))
    print(('  %-36s misses: relative %.1f%%  parallel %.1f%%  a fifth away %.1f%%  other %.1f%%'):format(
        '', Pct(t.rel, t.n), Pct(t.par, t.n), Pct(t.fifth, t.n),
        Pct(t.n - t.key - t.rel - t.par - t.fifth, t.n)))
    local parts = {}
    for i, lo in ipairs(BANDS) do
        local bd = t.bands[i]
        if bd then parts[#parts + 1] = ('margin >= %.2f: %d songs %.0f%%'):format(lo, bd.n, Pct(bd.ok, bd.n)) end
    end
    print(('  %-36s %s'):format('', table.concat(parts, ' | ')))
end

local function Evaluate(songs, ProfilesFor)
    local tallies = {}
    for _, set in ipairs(KEY_RESULT_SETS) do tallies[set.key] = NewTally() end
    for _, s in ipairs(songs) do
        local prof = ProfilesFor(s)
        for _, set in ipairs(KEY_RESULT_SETS) do
            local ranked = KeyRankSet(s.features, set, prof)
            if ranked then Tally(tallies[set.key], s, ranked) end
        end
    end
    for _, set in ipairs(KEY_RESULT_SETS) do PrintTally(set.label, tallies[set.key]) end
end

----------------------------------------------------------------------
-- Writing the profiles
----------------------------------------------------------------------

local function WriteProfiles(profiles, n_songs)
    local L = {
        '-- GENERATED by dev/tools/key_detect_fit_offline.lua - do not hand-edit.',
        '--',
        '-- Song key profiles for lib/reaper_key_detect.lua: per source, the average pitch-class',
        '-- histogram of the official RB3 DLC development songs, rotated so the tonic their',
        '-- songs.dta names is index 1. [0] = major songs, [1] = minor songs. Each sums to 1.',
        '-- Regenerate by running the fitter again; never edit the numbers by hand.',
        '',
        'RB_KEY_PROFILES_SCHEMA = 1',
        '',
        'RB_KEY_PROFILES = {',
        ('    songs = %d,'):format(n_songs),
        '    sources = {',
    }
    for _, name in ipairs(KEY_SOURCES) do
        local p = profiles[name]
        if p then
            L[#L + 1] = ('        %s = {'):format(name)
            for m = 0, 1 do
                local v = {}
                for i = 1, 12 do v[i] = ('%.4f'):format(p[m][i]) end
                L[#L + 1] = ('            [%d] = { %s },'):format(m, table.concat(v, ', '))
            end
            L[#L + 1] = '        },'
        end
    end
    L[#L + 1] = '    },'
    L[#L + 1] = '}'
    local f = assert(io.open(PROFILES_OUT, 'wb'))
    f:write(table.concat(L, '\n') .. '\n')
    f:close()
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

if MODE == 'dev' or MODE == 'report' then
    local all = LoadSongs(MAIN)
    local dev = {}
    for _, s in ipairs(all) do if not DiffIsHeldOut(s.name) then dev[#dev + 1] = s end end

    -- 5-fold CV: each song is scored with profiles fitted on the other four folds.
    local fold_of, by_fold = {}, {}
    for _, s in ipairs(dev) do
        local f = (DiffHoldoutHash(s.name) // DIFF_HOLDOUT_MOD) % 5
        fold_of[s] = f
        by_fold[f] = by_fold[f] or {}
    end
    for f = 0, 4 do
        local train = {}
        for _, s in ipairs(dev) do if fold_of[s] ~= f then train[#train + 1] = s end end
        by_fold[f] = KeyFitProfiles(train)
    end
    print(('Development songs: %d (5-fold cross-validation; hold-out excluded)'):format(#dev))
    Evaluate(dev, function(s) return by_fold[fold_of[s]] end)

    if MODE == 'dev' then
        WriteProfiles(KeyFitProfiles(dev), #dev)
        print('Wrote ' .. PROFILES_OUT)
    end

elseif MODE == 'holdout' then
    dofile(PROFILES_OUT)
    local held = {}
    for _, s in ipairs(LoadSongs(MAIN)) do if DiffIsHeldOut(s.name) then held[#held + 1] = s end end
    print(('HELD-OUT songs: %d - report this once, never tune on it'):format(#held))
    Evaluate(held, function() return RB_KEY_PROFILES.sources end)

else
    error('unknown mode: ' .. tostring(MODE))
end
