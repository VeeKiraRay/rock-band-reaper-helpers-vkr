-- Round-14 offline corpus scorer.
--
-- Re-scores only keys, Pro Keys and vocals through the pure SMF reader, then writes a
-- separate CSV. Rows for the locked passing instruments are schema-extended from the
-- round-13 CSV with zeros in the new columns, so their old measurements stay untouched.
-- Run from the repository root:
--   lua dev/calibration/run_round14_offline.lua

local script = (arg and arg[0]) or 'dev/calibration/run_round14_offline.lua'
local dir = script:match('^(.+[/\\])') or 'dev/calibration/'
local root = dir:gsub('dev[/\\]calibration[/\\]$', '')

dofile(dir .. 'difficulty_score.lua')
dofile(dir .. 'difficulty_score_vocals.lua')
dofile(dir .. 'songs_dta.lua')
dofile(root .. 'dev/tools/smf_reader.lua')

local source_csv = dir .. 'corpus_scores.csv'
local output_csv = dir .. 'corpus_scores_round14.csv'
local corpus_root = root .. '_external_docs/reference_songs/'

local function Split(line)
    local out = {}
    for v in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = v end
    return out
end

local function ReadCsv(path)
    local f = assert(io.open(path, 'r'))
    local names = Split(assert(f:read('*l')))
    local rows = {}
    for line in f:lines() do
        local vals, row = Split(line), {}
        for i, name in ipairs(names) do row[name] = vals[i] end
        rows[#rows + 1] = row
    end
    f:close()
    return names, rows
end

local function ReadFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a'); f:close(); return s
end

local function ListDta(root_path)
    local out = {}
    local pipe = assert(io.popen(('dir /b /s "%s" 2>nul'):format(root_path:gsub('/', '\\'))))
    for path in pipe:lines() do
        if path:lower():match('[/\\]songs%.dta$') then out[#out + 1] = path end
    end
    pipe:close()
    return out
end

local songs = {}
for _, path in ipairs(ListDta(corpus_root)) do
    local text = ReadFile(path)
    local pack = path:gsub('[/\\]Root[/\\]songs[/\\]songs%.dta$', '')
    local pack_id = pack:match('([^/\\]+)$') or pack
    for _, e in ipairs(ParseSongsDta(text or '')) do
        local mid = pack .. '/Root/songs/' .. e.shortname .. '/' .. e.shortname .. '.mid'
        songs[pack_id .. '\0' .. e.shortname] = { dta = e, midi = mid }
    end
end

local function Sec(song, map, tick) return SmfTickToSec(map, song.tpqn, tick) end
local function TrackEndTick(track)
    local t = 0
    for _, n in ipairs(track.notes) do if n.tick + n.len > t then t = n.tick + n.len end end
    for _, e in ipairs(track.texts) do if e.tick > t then t = e.tick end end
    return t
end

local function GemEvents(song, map, track, lo, hi)
    local raw = SmfNotesInRange(track, lo, hi)
    local events, i = {}, 1
    while i <= #raw do
        local tick, pitches, stop = raw[i].tick, {}, raw[i].tick + raw[i].len
        local j = i
        while j <= #raw and raw[j].tick == tick do
            pitches[#pitches + 1] = raw[j].pitch
            if raw[j].tick + raw[j].len > stop then stop = raw[j].tick + raw[j].len end
            j = j + 1
        end
        table.sort(pitches)
        local held, struck = {}, {}
        for _, p in ipairs(pitches) do struck[p] = true end
        local seen = {}
        for k = 1, i - 1 do
            local n = raw[k]
            if n.tick < tick and n.tick + n.len > tick and not struck[n.pitch] then seen[n.pitch] = true end
        end
        for p in pairs(seen) do held[#held + 1] = p end
        table.sort(held)
        events[#events + 1] = {
            s = Sec(song, map, tick), e = Sec(song, map, stop),
            qn = tick / song.tpqn, qn_e = stop / song.tpqn,
            pitches = pitches, held = held,
        }
        i = j
    end
    return events
end

local PLAY = { ['[play]']=true, ['[intense]']=true, ['[mellow]']=true, ['[play_solo]']=true }
local IDLE = { ['[idle]']=true, ['[idle_realtime]']=true, ['[idle_intense]']=true }
local function PlayingSpans(song, map, track)
    local states = {}
    for _, e in ipairs(track.texts) do
        local m = e.text:lower()
        if e.type == 1 and (PLAY[m] or IDLE[m]) then
            states[#states + 1] = { t = Sec(song, map, e.tick), play = PLAY[m] or false,
                                    solo = m == '[play_solo]' }
        end
    end
    table.sort(states, function(a, b) return a.t < b.t end)
    local spans, solos, open, solo = {}, {}, nil, nil
    for _, e in ipairs(states) do
        if e.play then
            open = open or e.t
            if e.solo then solo = solo or e.t elseif solo then
                if e.t > solo then solos[#solos + 1] = { s = solo, e = e.t } end
                solo = nil
            end
        else
            if open and e.t > open then spans[#spans + 1] = { s = open, e = e.t } end
            if solo and e.t > solo then solos[#solos + 1] = { s = solo, e = e.t } end
            open, solo = nil, nil
        end
    end
    local finish = Sec(song, map, TrackEndTick(track))
    if open and finish > open then spans[#spans + 1] = { s = open, e = finish } end
    if solo and finish > solo then solos[#solos + 1] = { s = solo, e = finish } end
    return NormalizeSpans(spans), #states, NormalizeSpans(solos)
end

local function MarkerSpans(song, map, track, pitch, vocal)
    local spans = {}
    for _, n in ipairs(track.notes) do
        if n.pitch == pitch and n.len > 0 then
            spans[#spans + 1] = { s = Sec(song, map, n.tick), e = Sec(song, map, n.tick + n.len) }
        end
    end
    return vocal and NormalizeVocalPhrases(spans) or NormalizeSpans(spans)
end

local function VocalNotes(song, map, track)
    local lyrics = {}
    for _, e in ipairs(track.texts) do
        if (e.type == 1 or e.type == 5) and lyrics[e.tick] == nil then lyrics[e.tick] = e.text end
    end
    local out = {}
    for _, n in ipairs(SmfNotesInRange(track, 36, 84)) do
        out[#out + 1] = { s = Sec(song, map, n.tick), e = Sec(song, map, n.tick + n.len),
            qn = n.tick / song.tpqn, qn_e = (n.tick + n.len) / song.tpqn,
            pitch = n.pitch, lyric = lyrics[n.tick] }
    end
    return out
end

local function PercussionSpans(song, map, track)
    local marks = {}
    for _, e in ipairs(track.texts) do
        local what, kind = e.text:match('^%[(%a+)_(start)%]$')
        if not what then what, kind = e.text:match('^%[(%a+)_(end)%]$') end
        if what == 'tambourine' or what == 'cowbell' or what == 'clap' then
            marks[#marks + 1] = { t = Sec(song, map, e.tick), kind = kind }
        end
    end
    table.sort(marks, function(a, b) return a.t < b.t end)
    local out, open = {}, nil
    for _, m in ipairs(marks) do
        if m.kind == 'start' then open = open or m.t elseif open then
            if m.t > open then out[#out + 1] = { s = open, e = m.t } end
            open = nil
        end
    end
    if open then out[#out + 1] = { s = open, e = Sec(song, map, TrackEndTick(track)) } end
    return NormalizeSpans(out)
end

local SHIFT = { [0]=48, [2]=50, [4]=52, [5]=53, [7]=55, [9]=57 }
local function LaneShifts(song, map, track)
    local out = {}
    for _, n in ipairs(track.notes) do
        if SHIFT[n.pitch] then out[#out + 1] = { s = Sec(song, map, n.tick), base = SHIFT[n.pitch] } end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

local function ScoreTarget(row)
    local sn, inst = row.shortname, row.instrument
    local rec = assert(songs[row.pack .. '\0' .. sn], 'missing dta entry: ' .. row.pack .. '/' .. sn)
    local song = assert(SmfReadFile(rec.midi))
    local map = SmfTempoMap(song)
    if inst == 'vocals' then
        local track = assert(SmfFindTrack(song, 'PART VOCALS'))
        local notes = VocalNotes(song, map, track)
        local phrases = {}
        for _, p in ipairs({105, 106}) do
            for _, sp in ipairs(MarkerSpans(song, map, track, p, true)) do phrases[#phrases + 1] = sp end
        end
        phrases = NormalizeVocalPhrases(phrases)
        -- A handful of legacy MIDIs use overlapping same-pitch phrase markers that the
        -- census reader cannot pair (their marker length is zero). Detect that from the
        -- already-recorded round-13 playing time and use note-derived segmentation for
        -- new factors. Old columns are preserved below, so this fallback cannot move a
        -- previous result.
        local phrase_s = TotalSpanSeconds(phrases)
        local recorded_s = tonumber(row.playing_s) or 0
        if recorded_s > 0 and phrase_s < recorded_s * 0.5 then phrases = {} end
        if #phrases == 0 then phrases = select(1, PlayingSpans(song, map, track)) end
        if #phrases == 0 then phrases = DeriveSpansFromEvents(notes) end
        return ScoreVocalChart(notes, phrases, {
            perc_spans = PercussionSpans(song, map, track),
            vocal_parts = rec.dta.vocal_parts or 1,
        })
    end

    local is_pro = inst == 'real_keys'
    local track = assert(SmfFindTrack(song, is_pro and 'PART REAL_KEYS_X' or 'PART KEYS'))
    local events = GemEvents(song, map, track, is_pro and 48 or 96, is_pro and 72 or 100)
    local span_track = is_pro and (SmfFindTrack(song, 'PART KEYS') or track) or track
    local spans, _, solos = PlayingSpans(song, map, span_track)
    if #spans == 0 then spans = DeriveSpansFromEvents(events) end
    return ScoreChart(events, spans, {
        solo_spans = solos,
        marked_solo_spans = MarkerSpans(song, map, track, is_pro and 115 or 103),
        trill_spans = MarkerSpans(song, map, track, 127),
        gliss_spans = is_pro and MarkerSpans(song, map, track, 126) or nil,
        lane_shifts = is_pro and LaneShifts(song, map, track) or nil,
        pro_keys = is_pro, offbeat = true,
    })
end

local old_names, rows = ReadCsv(source_csv)
local meta = {}
local factor = {}
for _, k in ipairs(SCORE_FACTOR_KEYS) do factor[k] = true end
for _, name in ipairs(old_names) do if not factor[name] then meta[#meta + 1] = name end end
local names = {}
for _, name in ipairs(meta) do names[#names + 1] = name end
for _, name in ipairs(SCORE_FACTOR_KEYS) do names[#names + 1] = name end

local target = { keys = true, real_keys = true, vocals = true }
local new_factors = {
    complex_peak = true,
    finger_reassign_mean = true, finger_reassign_p90 = true,
    finger_reassign_peak = true, held_independence_peak = true,
    high_hold_time_70 = true, high_longest_note_70 = true,
    high_reentry_rate_70 = true, pitch_p98_time = true,
    phrase_density_p90 = true, phrase_complex_p90 = true, vocal_parts = true,
}
for n, row in ipairs(rows) do
    if target[row.instrument] then
        local score = ScoreTarget(row)
        -- Only append round-14 measurements. The offline adapter is independently
        -- checked against the old columns, but preserving them exactly is stronger:
        -- every prior candidate must reproduce to the digit by construction.
        for k in pairs(new_factors) do row[k] = score[k] or 0 end
        if n % 50 == 0 then io.write(('.%d'):format(n)) end
    else
        for _, k in ipairs(SCORE_FACTOR_KEYS) do if row[k] == nil then row[k] = 0 end end
    end
end

local function Num(v)
    if type(v) ~= 'number' then return tostring(v or '') end
    local s = ('%.6f'):format(v):gsub('0+$', ''):gsub('%.$', '')
    return s
end
local out = assert(io.open(output_csv, 'w'))
out:write(table.concat(names, ','), '\n')
for _, row in ipairs(rows) do
    local vals = {}
    for _, name in ipairs(names) do vals[#vals + 1] = Num(row[name]) end
    out:write(table.concat(vals, ','), '\n')
end
out:close()
io.write(('wrote %s (%d rows, %d factors)\n'):format(output_csv, #rows, #SCORE_FACTOR_KEYS))
