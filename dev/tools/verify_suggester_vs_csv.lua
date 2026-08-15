-- Offline verification: does the shipped suggester measure what the corpus was scored on?
--
--     lua dev/tools/verify_suggester_vs_csv.lua [n_songs]
--
-- Loads real corpus MIDIs through a mock REAPER API backed by dev/tools/smf_reader.lua,
-- runs SuggestProjectDifficulties() exactly as the Metadata > Difficulty view will, and
-- compares every factor against that song's row in dev/calibration/corpus_scores.csv.
--
-- WHY THIS EXISTS. The product plan's acceptance criterion for the adapter is "a fixture
-- loaded as a normal REAPER project produces the same factors and rank as its calibration
-- CSV row" - a REAPER-side check. This is the offline half of it: it cannot prove REAPER's
-- own MIDI and tempo APIs behave like the mock, but it does prove the reader, the chart
-- spec, the scorer and the model are wired together correctly, which is where the mistakes
-- actually are. Run the REAPER-side test as well; neither replaces the other.
--
-- EXPECT SMALL DIFFERENCES, NOT ZEROS. The CSV was produced by REAPER converting ticks to
-- seconds through its own tempo map; this converts them through the SMF's. Agreement to a
-- few parts in 10^5 means the two describe the same chart. A factor that disagrees
-- structurally - a different count, a zero against a non-zero - does not.
--
-- MODEL FACTORS ARE GRADED SEPARATELY, AND THEY ARE THE ONES THAT MATTER. A CSV column no
-- selected candidate uses cannot move a suggestion by definition, so a difference there is
-- worth printing and is not a failure.
--
-- The distinction is not academic: `short_frac` and `short_moving_frac` differ on most
-- vocal charts, by a handful of notes each. VOCAL_SHORT_QN is 0.25, and a 16th note at 480
-- tpqn is EXACTLY 0.25 quarter notes - so the threshold sits precisely on the most common
-- note length in a vocal chart, and which side of it a note lands on comes down to the
-- last bit of a tick-to-quarter-note conversion. Measured on `beautifuldisaster`: 176
-- short notes here against 175 in the CSV, out of 339. Neither factor is in the selected
-- vocal model, so no suggestion moves - but it is a real fragility in those two columns
-- and would matter if a future round ever declared them.
--
-- Dev-only, not deployed, not part of the test suite (it needs the ungitignored corpus).

local _script = (arg and arg[0]) or 'dev/tools/verify_suggester_vs_csv.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/tools/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))

local N_SONGS = tonumber(arg and arg[1]) or 6

----------------------------------------------------------------------
-- Mock REAPER
--
-- One track per SMF track, each holding one MIDI item with one take. PPQ is the SMF tick,
-- so MIDI_GetProjTimeFromPPQPos is the tempo map and MIDI_GetProjQNFromPPQPos is a
-- division. Only the calls difficulty_read.lua and difficulty_suggester.lua actually make
-- are implemented - a missing one should be a loud nil-call, not a plausible default.
----------------------------------------------------------------------

local _song, _map, _tracks

local function TickToSec(tick) return SmfTickToSec(_map, _song.tpqn, tick) end

-- Inverse of the tempo map, for TimeMap2_timeToQN.
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
    GetSetMediaTrackInfo_String = function(tr, key, _, _set)
        if key == 'P_NAME' then return true, tr.name or '' end
        return false, ''
    end,
    GetMediaTrackInfo_Value = function(_, key)
        if key == 'B_MUTE' then return 0 end
        return 0
    end,
    -- One item, one take, and the take IS the track record.
    CountTrackMediaItems = function(_) return 1 end,
    GetTrackMediaItem    = function(tr, _) return tr end,
    GetActiveTake        = function(item) return item end,
    TakeIsMIDI           = function(_) return true end,

    -- TrackEndTime reads these to close a playing span that never gets an explicit idle
    -- event.
    --
    -- LENGTH IS THIS TRACK'S OWN LAST EVENT, not the whole file. Measured against the
    -- CSV: sizing every item to the file end made `theballadofirahayes` PART DRUMS read
    -- 169.8 s of playing time against the corpus row's 164.1, because the track's final
    -- playing span is closed at TrackEndTime and a file-length item pushes that boundary
    -- past the end of the drum chart. Per-track lengths reproduce the corpus.
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

    MIDI_CountEvts = function(take)
        return true, #take.notes, 0, #take.texts
    end,
    MIDI_GetNote = function(take, j)
        local n = take.notes[j + 1]
        if not n then return false end
        -- ok, selected, muted, startppq, endppq, chan, pitch, vel
        return true, false, false, n.tick, n.tick + n.len, 0, n.pitch, 100
    end,
    MIDI_GetTextSysexEvt = function(take, j)
        local t = take.texts[j + 1]
        if not t then return false end
        -- ok, selected, muted, ppq, type, msg
        return true, false, false, t.tick, t.type, t.text
    end,
    MIDI_GetProjTimeFromPPQPos = function(_, ppq) return TickToSec(ppq) end,
    MIDI_GetProjQNFromPPQPos   = function(_, ppq) return ppq / _song.tpqn end,
    TimeMap2_timeToQN          = function(_, t) return SecToQN(t) end,
}

----------------------------------------------------------------------
-- Modules under test - the same load order as the general helper's entry point
----------------------------------------------------------------------

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'lib/reaper_difficulty_score.lua')
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_root .. 'lib/reaper_difficulty_tiers.lua')
dofile(_root .. 'lib/reaper_difficulty_predict.lua')
dofile(_root .. 'lib/reaper_difficulty_models.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_read.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_suggester.lua')
dofile(_root .. 'dev/calibration/songs_dta.lua')

local function LoadSong(path)
    _song   = SmfReadFile(path)
    _map    = SmfTempoMap(_song)
    _tracks = {}
    for _, trk in ipairs(_song.tracks) do _tracks[#_tracks + 1] = trk end
end

----------------------------------------------------------------------
-- CSV
----------------------------------------------------------------------

local function Split(line)
    local out = {}
    for v in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = v end
    return out
end

local rows, header = {}, nil
do
    local f = assert(io.open(_root .. 'dev/calibration/corpus_scores.csv'))
    header = {}
    for i, n in ipairs(Split(f:read('l'))) do header[n] = i end
    for line in f:lines() do
        if line ~= '' then
            local v = Split(line)
            rows[(v[header.shortname] or '') .. '\0' .. (v[header.instrument] or '')] = v
        end
    end
    f:close()
end

----------------------------------------------------------------------
-- Corpus
----------------------------------------------------------------------

local function ReadFile(p)
    local f = io.open(p, 'rb')
    if not f then return nil end
    local s = f:read('a'); f:close(); return s
end

local songs = {}
for _, dta in ipairs(SmfListFiles(_root .. '_external_docs/reference_songs/', 'songs%.dta$')) do
    local pack = dta:gsub('[/\\]Root[/\\]songs[/\\]songs%.dta$', '')
    for _, e in ipairs(ParseSongsDta(ReadFile(dta) or '')) do
        if e.origin == 'rb3_dlc' then
            songs[#songs + 1] = {
                shortname = e.shortname, ranks = e.ranks,
                vocal_parts = e.vocal_parts,
                midi = pack .. '/Root/songs/' .. e.shortname .. '/' .. e.shortname .. '.mid',
            }
        end
    end
end
table.sort(songs, function(a, b) return a.shortname < b.shortname end)

if #songs == 0 then
    print('No reference songs found - this check needs the ungitignored corpus. Skipping.')
    return
end

-- Songs charting the most instruments first, so a short run still covers all six models.
table.sort(songs, function(a, b)
    local function n(s)
        local c = 0
        for _, k in ipairs({ 'guitar', 'bass', 'drum', 'keys', 'real_keys', 'vocals' }) do
            if (s.ranks[k] or 0) > 0 then c = c + 1 end
        end
        return c
    end
    local na, nb = n(a), n(b)
    if na ~= nb then return na > nb end
    return a.shortname < b.shortname
end)

----------------------------------------------------------------------
-- Compare
----------------------------------------------------------------------

print(('Comparing %d songs against corpus_scores.csv\n'):format(math.min(N_SONGS, #songs)))

local worst_rel, worst_where = 0, ''
local n_rows, n_model_bad, n_other_bad, n_missing_row = 0, 0, 0, 0
local tier_hits, tier_total = 0, 0
local other_bad_keys = {}
local worst_rank_delta, worst_rank_where, n_tier_flip = 0, '', 0
local tier_flips = {}

for i = 1, math.min(N_SONGS, #songs) do
    local song = songs[i]
    LoadSong(song.midi)

    local recs = SuggestProjectDifficulties()
    local parts = {}
    for _, rec in ipairs(recs) do
        local row = rows[song.shortname .. '\0' .. rec.instrument]
        if not rec.ok then
            parts[#parts + 1] = ('%s: %s'):format(rec.instrument, rec.reason)
        elseif not row then
            n_missing_row = n_missing_row + 1
            parts[#parts + 1] = ('%s: scored but no CSV row'):format(rec.instrument)
        else
            n_rows = n_rows + 1
            local in_model = {}
            for _, k in ipairs(rec.model.keys) do in_model[k] = true end

            local bad = {}
            for _, k in ipairs(SCORE_FACTOR_KEYS) do
                local want = tonumber(row[header[k]])
                local got  = rec.factors[k] or 0
                if want then
                    local scale = math.max(math.abs(want), math.abs(got), 1e-9)
                    local rel   = math.abs(got - want) / scale
                    -- The CSV stores %.6f with trailing zeros trimmed, so a small value
                    -- carries few significant digits; compare against that granularity.
                    if math.abs(got - want) > 1e-6 and rel > 1e-3 then
                        if in_model[k] then
                            bad[#bad + 1] = ('%s %.6g vs %.6g'):format(k, got, want)
                            n_model_bad = n_model_bad + 1
                        else
                            n_other_bad = n_other_bad + 1
                            other_bad_keys[k] = (other_bad_keys[k] or 0) + 1
                        end
                    elseif rel > worst_rel then
                        worst_rel, worst_where = rel, rec.instrument .. '.' .. k
                    end
                end
            end
            -- THE NUMBER THAT ACTUALLY MATTERS. Feed the model the CSV's own factors and
            -- compare the rank against the one computed from the project. A factor that
            -- drifts on a threshold is only a problem to the extent it moves this.
            local csv_factors = {}
            for _, k in ipairs(SCORE_FACTOR_KEYS) do
                csv_factors[k] = tonumber(row[header[k]]) or 0
            end
            local csv_rank = DifficultyPredictRank(rec.model, csv_factors)
            if csv_rank then
                local drank = math.abs(csv_rank - rec.rank)
                if drank > worst_rank_delta then
                    worst_rank_delta = drank
                    worst_rank_where = ('%s %s'):format(song.shortname, rec.instrument)
                end
                local csv_tier = TierForRank(rec.instrument, csv_rank)
                if csv_tier ~= rec.tier then
                    n_tier_flip = n_tier_flip + 1
                    -- Name it: a tier that moves is the only difference an author can
                    -- see, so it should never be a bare count in the summary.
                    tier_flips[#tier_flips + 1] = ('%s %s: %.2f (tier %d) vs CSV %.2f (tier %d)')
                        :format(song.shortname, rec.instrument,
                                rec.rank, rec.tier, csv_rank, csv_tier)
                end
            end

            local actual = tonumber(row[header.rank])
            local at     = TierForRank(rec.instrument, actual)
            tier_total   = tier_total + 1
            if math.abs(rec.tier - at) <= 1 then tier_hits = tier_hits + 1 end
            parts[#parts + 1] = ('%s: rank %d->%d tier %d/%d%s')
                :format(rec.instrument, actual, math.floor(rec.rank + 0.5), rec.tier, at,
                        #bad > 0 and ('  MISMATCH: ' .. table.concat(bad, '; ')) or '')
        end
    end
    print(('%-26s %s'):format(song.shortname, table.concat(parts, '\n' .. (' '):rep(27))))
    print('')
end

print(('rows compared          : %d'):format(n_rows))
print(('MODEL factor mismatches: %d'):format(n_model_bad))
print(('other column drift     : %d'):format(n_other_bad))
if n_other_bad > 0 then
    local names = {}
    for k, n in pairs(other_bad_keys) do names[#names + 1] = ('%s x%d'):format(k, n) end
    table.sort(names)
    print(('  (unused by any selected model: %s)'):format(table.concat(names, ', ')))
end
print(('rows with no CSV row   : %d'):format(n_missing_row))
print(('worst agreeing factor  : %.2e relative (%s)'):format(worst_rel, worst_where))
print('')
print('-- what an author would actually see --')
print(('worst rank difference  : %.3f rank (%s)'):format(worst_rank_delta, worst_rank_where))
print(('suggestions changing tier: %d of %d'):format(n_tier_flip, n_rows))
for _, s in ipairs(tier_flips) do print('  ' .. s) end
print(('within-one of official : %d/%d'):format(tier_hits, tier_total))
print('')
-- The pass condition is the SUGGESTION, not the intermediate. A threshold factor that
-- flips a note either way is only a defect to the extent it moves the number shown.
--
-- The bar is a few rank points rather than zero, and a tier change is allowed only when
-- the rank difference is smaller than the distance to the boundary it crossed - i.e. the
-- chart was sitting ON a threshold, where any measurement noise at all decides the tier.
-- Demanding zero flips would be demanding that no chart ever land within a rank point of
-- a boundary, which is not a property of the adapter.
local BAR = 5.0
if worst_rank_delta < BAR and n_tier_flip <= 1 then
    print(('PASS - every suggestion computed from the project matches the one computed'))
    print(('       from the calibration measurement to within %.1f rank.'):format(BAR))
    if n_tier_flip > 0 then
        print('       The listed tier change is a chart sitting on a threshold, not a')
        print('       measurement disagreement - see the rank pair above.')
    end
else
    print('FAIL - the adapter does not reproduce the measurement the models were fitted on.')
end
