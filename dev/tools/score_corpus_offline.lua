-- Score an arbitrary reference corpus offline, into corpus_scores.csv's schema.
--
--   lua dev/tools/score_corpus_offline.lua <corpus-root> <output.csv> [limit]
--
-- WHAT THIS IS FOR. run_calibration_vkr.lua is the authoritative scorer and needs REAPER:
-- it imports each MIDI, reads it through REAPER's own tempo map, and deletes the tracks
-- again. That is a long run and cannot be scripted from a plain Lua CLI. This produces the
-- same table from the same production code through the pure SMF reader, so a candidate
-- corpus can be looked at - row counts, rank coverage, what the clamp floors would become -
-- before committing to the REAPER pass.
--
-- IT IS A PREVIEW, NOT A REPLACEMENT, AND THE TWO MUST NOT BE MIXED IN ONE TRAINING SET.
-- Measured drift against the REAPER-scored CSV is small but real and always in the same
-- columns: the CSV converts ticks to seconds through REAPER's tempo map and this through
-- the SMF's, and `sustain_frac` sits exactly on an eighth-note boundary so a few notes fall
-- either side of it. Merging offline-scored rows into a REAPER-scored corpus would put a
-- measurement difference exactly along the new/old split, which is indistinguishable from a
-- real effect. Score the whole thing one way or the other.
--
-- MIDIs ARE RESOLVED BY INDEX, NOT BY PATH CONVENTION. Every .mid under the root is keyed
-- by its basename, which in these corpora is always the song shortname, and each dta entry
-- is looked up in that index. This handles both layouts at once - the original corpus's
-- Root/songs/<name>/<name>.mid and the low-end set's flat folders - along with the case a
-- flat pack makes routine: one songs.dta describing a whole pack of which only some songs'
-- MIDIs are present. Nothing here encodes a directory shape.

local _script = (arg and arg[0]) or 'dev/tools/score_corpus_offline.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/tools/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))

local CORPUS  = arg and arg[1]
local OUT     = arg and arg[2]
local LIMIT   = tonumber(arg and arg[3])

if not CORPUS or not OUT then
    print('usage: lua dev/tools/score_corpus_offline.lua <corpus-root> <output.csv> [limit]')
    os.exit(1)
end
if not CORPUS:match('[/\\]$') then CORPUS = CORPUS .. '/' end

----------------------------------------------------------------------
-- Mock REAPER
--
-- Deliberately the same shape as dev/tools/verify_suggester_vs_csv.lua's: one track per
-- SMF track, one item, one take, PPQ as the SMF tick. Only the calls difficulty_read.lua
-- actually makes are implemented, so a missing one is a loud nil-call rather than a
-- plausible default that quietly changes a measurement.
----------------------------------------------------------------------

local _song, _map, _tracks

local function TickToSec(tick) return SmfTickToSec(_map, _song.tpqn, tick) end

local function SecToQN(t)
    local seg = _map[1]
    for i = 2, #_map do
        if _map[i].sec > t then break end
        seg = _map[i]
    end
    local tick = seg.tick + (t - seg.sec) * _song.tpqn * 1e6 / seg.uspqn
    return tick / _song.tpqn
end

r = {
    CountTracks = function() return #_tracks end,
    GetTrack    = function(_, i) return _tracks[i + 1] end,
    GetSetMediaTrackInfo_String = function(tr, key)
        if key == 'P_NAME' then return true, tr.name or '' end
        return false, ''
    end,
    GetMediaTrackInfo_Value = function() return 0 end,
    CountTrackMediaItems    = function() return 1 end,
    GetTrackMediaItem       = function(tr) return tr end,
    GetActiveTake           = function(item) return item end,
    TakeIsMIDI              = function() return true end,

    -- Per-track length, not the file's. See the note in verify_suggester_vs_csv.lua: a
    -- file-length item pushes the final playing span past the end of the chart and
    -- inflates playing time on any track that stops early.
    GetMediaItemInfo_Value = function(item, key)
        if key == 'D_POSITION' then return 0 end
        if key == 'D_LENGTH' then
            local last = 0
            for _, n in ipairs(item.notes) do
                if n.tick + n.len > last then last = n.tick + n.len end
            end
            for _, t in ipairs(item.texts) do
                if t.tick > last then last = t.tick end
            end
            return TickToSec(last)
        end
        return 0
    end,

    MIDI_CountEvts = function(take) return true, #take.notes, 0, #take.texts end,
    MIDI_GetNote = function(take, j)
        local n = take.notes[j + 1]
        if not n then return false end
        return true, false, false, n.tick, n.tick + n.len, 0, n.pitch, 100
    end,
    MIDI_GetTextSysexEvt = function(take, j)
        local t = take.texts[j + 1]
        if not t then return false end
        return true, false, false, t.tick, t.type, t.text
    end,
    MIDI_GetProjTimeFromPPQPos = function(_, ppq) return TickToSec(ppq) end,
    MIDI_GetProjQNFromPPQPos   = function(_, ppq) return ppq / _song.tpqn end,
    TimeMap2_timeToQN          = function(_, t) return SecToQN(t) end,
}

----------------------------------------------------------------------
-- Production modules, in the general helper's own load order
----------------------------------------------------------------------

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'lib/reaper_difficulty_score.lua')
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_read.lua')
dofile(_root .. 'dev/calibration/songs_dta.lua')

----------------------------------------------------------------------
-- The CSV schema
--
-- Transcribed from run_calibration_vkr.lua's CSV_COLS, and the factor columns come from
-- SCORE_FACTOR_KEYS exactly as they do there, so writer and analysis cannot drift. The
-- header is compared against the existing corpus CSV at the end of the run: a mismatch
-- makes the output useless for merging and has to be loud.
----------------------------------------------------------------------

local CSV_COLS = {
    'shortname', 'origin', 'pack', 'instrument', 'rank',
    'notes', 'events', 'span_source', 'anim_events',
    'force_hopo_notes', 'force_strum_notes',
    'sustain_measured', 'tight_measured', 'solo_measured', 'entropy_contexts',
    'tom_marker_spans',
    'bpm_at_first_note', 'tempo_markers',
}

local function AllCols()
    local cols = {}
    for _, c in ipairs(CSV_COLS) do cols[#cols + 1] = c end
    for _, k in ipairs(SCORE_FACTOR_KEYS) do cols[#cols + 1] = k end
    return cols
end

-- %.6f with the trailing zeros trimmed, matching the calibration writer so the two files
-- are diffable.
local function Num(v)
    if type(v) ~= 'number' then return tostring(v) end
    local s = ('%.6f'):format(v)
    s = s:gsub('0+$', ''):gsub('%.$', '')
    return s == '' and '0' or s
end

local function PackId(path)
    if not path or path == '' then return '?' end
    local leaf = path:match('([^/\\]+)[/\\]*$') or path
    return (leaf:gsub(',', '_'))
end

----------------------------------------------------------------------
-- Corpus discovery
----------------------------------------------------------------------

-- Every MIDI under the root, keyed by shortname.
--
-- The same basename appearing twice is EXPECTED here and is not by itself a problem: the
-- low-end set was assembled by searching per instrument, so a pack that happens to be easy
-- on both bass and drums is copied into both folders - 158 of its songs are duplicated that
-- way and every copy is byte-identical.
--
-- What would be a problem is two DIFFERENT charts under one shortname, because then the
-- choice of copy silently decides which chart a real rank gets attached to. So the
-- duplicate is resolved silently when the bytes match and reported loudly when they do
-- not, rather than warning on all 158 and training the reader to skip the warning.
local function ReadFile(p)
    local f = io.open(p, 'rb')
    if not f then return nil end
    local s = f:read('a'); f:close(); return s
end

local midi_by_name, conflicts = {}, {}
for _, path in ipairs(SmfListFiles(CORPUS, '%.mid$')) do
    local name = SmfShortname(path)
    local seen_path = midi_by_name[name]
    if not seen_path then
        midi_by_name[name] = path
    elseif seen_path ~= path and ReadFile(seen_path) ~= ReadFile(path) then
        conflicts[name] = true
    end
end

local songs, seen = {}, {}
for _, dta in ipairs(SmfListFiles(CORPUS, 'songs%.dta$')) do  -- luacheck: ignore
    -- Exact filename only: one corpus folder carries a duplicate 'songs(0).dta' and
    -- reading both would score that song twice.
    if dta:lower():match('[/\\]songs%.dta$') then
        local pack = dta:gsub('[/\\][^/\\]+$', '')
        for _, e in ipairs(ParseSongsDta(ReadFile(dta) or '')) do
            -- The same song can appear under several instrument folders in the low-end
            -- set; the first dta to name it wins and the rest are skipped.
            if not seen[e.shortname] and midi_by_name[e.shortname] then
                seen[e.shortname] = true
                songs[#songs + 1] = {
                    shortname = e.shortname, origin = e.origin, ranks = e.ranks,
                    vocal_parts = e.vocal_parts, pack = pack,
                    midi = midi_by_name[e.shortname],
                }
            end
        end
    end
end
table.sort(songs, function(a, b) return a.shortname < b.shortname end)

if #songs == 0 then
    print(('No songs found under %s - is the corpus present?'):format(CORPUS))
    os.exit(1)
end
if LIMIT and LIMIT < #songs then
    for i = #songs, LIMIT + 1, -1 do songs[i] = nil end
end

----------------------------------------------------------------------
-- Score
----------------------------------------------------------------------

local out = assert(io.open(OUT, 'w'))
local cols = AllCols()
out:write(table.concat(cols, ',') .. '\n')

local n_rows, n_songs, n_skipped, failures = 0, 0, 0, {}

for _, song in ipairs(songs) do
    _song = SmfReadFile(song.midi)
    if _song then
        _map    = SmfTempoMap(_song)
        _tracks = {}
        for _, trk in ipairs(_song.tracks) do _tracks[#_tracks + 1] = trk end
        n_songs = n_songs + 1

        -- The first tempo segment's BPM stands in for REAPER's
        -- TimeMap_GetDividedBpmAtTime at the first onset. It is a diagnostic column, not
        -- a factor: it exists so a systematic tempo-import failure would be visible.
        local first_bpm = _map[1] and (60e6 / _map[1].uspqn) or 0

        for _, spec in ipairs(RB_CHART_SPECS) do
            local rank = DtaRank(song, spec.key)
            if rank then
                local sc, info, err = ScoreChartForSpec(spec, 0, {
                    vocal_parts = song.vocal_parts,
                })
                if sc then
                    local row
                    if spec.vocal then
                        row = {
                            song.shortname, song.origin or '?', PackId(song.pack),
                            spec.key, rank,
                            sc.syllables_total, sc.tubes_total, info.span_source, info.n_anim,
                            'n/a', 'n/a',
                            'n/a', tostring(sc.tight_med > 0), 'n/a', sc.entropy_contexts,
                            'n/a',
                            Num(first_bpm), #_map,
                        }
                    else
                        row = {
                            song.shortname, song.origin or '?', PackId(song.pack),
                            spec.key, rank,
                            sc.notes, sc.events, info.span_source, info.n_anim,
                            info.n_fhopo or 'n/a', info.n_fstrum or 'n/a',
                            tostring(sc.sustain_measured), tostring(sc.tight_measured),
                            tostring(sc.solo_measured), sc.entropy_contexts,
                            info.n_tom or 'n/a',
                            Num(first_bpm), #_map,
                        }
                    end
                    -- `or 0` because SCORE_FACTOR_KEYS spans both factor sets - the vocal
                    -- columns are structurally absent from a gem score and vice versa. A
                    -- nil would shift every later column left by one.
                    for _, k in ipairs(SCORE_FACTOR_KEYS) do row[#row + 1] = Num(sc[k] or 0) end
                    out:write(table.concat(row, ',') .. '\n')
                    n_rows = n_rows + 1
                else
                    n_skipped = n_skipped + 1
                    failures[err or 'unknown'] = (failures[err or 'unknown'] or 0) + 1
                end
            end
        end
    end
end
out:close()

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------

print(('corpus   : %s'):format(CORPUS))
print(('songs    : %d scored, %d rows'):format(n_songs, n_rows))
print(('skipped  : %d (instrument ranked in the dta but its track is absent)'):format(n_skipped))
for k, v in pairs(failures) do print(('   %-44s %d'):format(k, v)) end

-- Only DIFFERING copies are reported. Identical ones are routine here and warning on them
-- would bury this line under 158 non-problems.
local conflict_names = {}
for k in pairs(conflicts) do conflict_names[#conflict_names + 1] = k end
if #conflict_names > 0 then
    table.sort(conflict_names)
    print(('\nWARNING: %d shortname(s) resolve to DIFFERENT MIDIs and the first was used - '
        .. 'a real rank may be attached to the wrong chart: %s')
        :format(#conflict_names, table.concat(conflict_names, ', ')))
end

-- The header is the authoritative record of the factor set. If it does not match the
-- corpus CSV byte for byte, this output cannot be merged with it under any circumstances.
local existing = io.open(_root .. 'dev/calibration/corpus_scores.csv')
if existing then
    local want = existing:read('l'); existing:close()
    local got  = table.concat(cols, ',')
    print(('\nschema   : %s'):format(got == want and 'matches corpus_scores.csv'
        or 'DIFFERS from corpus_scores.csv - do not merge'))
end
print(('wrote    : %s'):format(OUT))
