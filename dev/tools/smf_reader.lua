-- Standard MIDI File reader - pure Lua, no REAPER.
--
-- WHY THIS EXISTS. The calibration harness (dev/calibration/) reads charts by
-- importing them into REAPER, which is correct for scoring but far too slow for the
-- census pass that opens every round: "does marker pitch X actually appear, and in how
-- many charts". Those censuses were previously done with a throwaway parser rewritten
-- from scratch each time. This is that parser, once, so a new round writes only the
-- question and not the file format.
--
-- SCOPE. Read-only, metrical SMF (format 0 and 1), which is what every Rock Band MIDI
-- is. It does not write, does not edit, and is deliberately not a REAPER helper - it is
-- loaded from a CLI script, never from a shipped entry point.
--
--   local _dir = arg[0]:match('^(.+[\\/])') or './'
--   dofile(_dir .. 'smf_reader.lua')
--   local song = assert(SmfReadFile(path))
--   local trk  = SmfFindTrack(song, 'PART REAL_KEYS_X')
--
-- Follows the repo convention: exported functions are globals in PascalCase, file
-- private helpers stay local.
--
-- Times are in TICKS everywhere. Tick -> quarter note is `tick / song.tpqn`; tick ->
-- seconds needs the tempo map, so use SmfTickToSec, which is why the tempo map is
-- parsed even though most censuses do not ask for it.

----------------------------------------------------------------------
-- Byte helpers
----------------------------------------------------------------------

-- Big-endian unsigned integer of n bytes at 1-based index i.
local function BE(s, i, n)
    local v = 0
    for k = 0, n - 1 do
        local b = s:byte(i + k)
        if not b then return nil end
        v = v * 256 + b
    end
    return v
end

-- Variable-length quantity. Returns value, next index.
-- SMF caps these at 4 bytes; a longer run means the stream is misaligned, and
-- returning nil here is what turns that into a clean error instead of a hang.
local function VLQ(s, p)
    local v = 0
    for _ = 1, 4 do
        local b = s:byte(p)
        if not b then return nil end
        p = p + 1
        v = v * 128 + (b % 128)
        if b < 128 then return v, p end
    end
    return nil
end

----------------------------------------------------------------------
-- Meta event types we keep
----------------------------------------------------------------------

local META_TEXT       = 0x01
local META_COPYRIGHT  = 0x02
local META_TRACK_NAME = 0x03
local META_LYRIC      = 0x05
local META_MARKER     = 0x06
local META_TEMPO      = 0x51
local META_TIMESIG    = 0x58
local META_END        = 0x2F

-- Text-bearing meta types are collected into `track.texts` with their type, so a caller
-- can tell a lyric (5) from an ordinary text event (1). REAPER's MIDI_GetTextSysexEvt
-- uses the same numbering, which keeps census code and scorer code speaking one
-- vocabulary.
local TEXTISH = {
    [META_TEXT] = true, [META_COPYRIGHT] = true, [META_TRACK_NAME] = true,
    [META_LYRIC] = true, [META_MARKER] = true,
}

----------------------------------------------------------------------
-- Track parsing
----------------------------------------------------------------------

-- Parses one MTrk chunk body. Returns a track table.
--
-- Note pairing: a note-on with velocity 0 is a note-off, which Rock Band MIDIs use
-- throughout - treating it as an onset would double every note count and leave every
-- note unterminated. Overlapping same-pitch notes are matched last-in-first-out on a
-- per-(channel, pitch) stack, which is the only unambiguous reading available.
local function ParseTrack(data, p, stop)
    local trk = { name = nil, notes = {}, texts = {}, tempos = {}, timesigs = {} }

    local open    = {}   -- (chan*128 + pitch) -> array of note indices, innermost last
    local running = nil  -- running status: CHANNEL messages only, see below
    local tick    = 0

    while p < stop do
        local dt
        dt, p = VLQ(data, p)
        if not dt then return nil, 'bad delta time' end
        tick = tick + dt

        local b = data:byte(p)
        if not b then return nil, 'truncated track' end

        -- RUNNING STATUS IS SET BY CHANNEL MESSAGES ONLY (0x80-0xEF). A meta event
        -- (0xFF) or sysex (0xF0/0xF7) is a status byte for its own event and nothing
        -- more - it must not become the running status.
        --
        -- This was a real bug and it cost a lot to find. Storing 0xFF here means the
        -- next running-status note event - a note whose 0x9n byte is omitted because
        -- the previous channel message had the same status - gets read as a meta
        -- event: its pitch becomes a meta type, its velocity becomes a length, and the
        -- parser walks off into the middle of the note data and never recovers. The
        -- track does not fail, it TRUNCATES, which is far worse: `lovehermadly` read
        -- 28 notes on PART DRUMS instead of 5996, and 30 on PART REAL_KEYS_X instead
        -- of 903, and reported them as if they were the whole chart. Rock Band MIDIs
        -- interleave text events with notes constantly, so this fires on any file
        -- whose writer relies on running status surviving a meta event.
        local status
        if b >= 0x80 then
            status = b
            p = p + 1
            if b < 0xF0 then running = b end
        elseif running then
            status = running
        else
            return nil, 'running status with no preceding status byte'
        end

        if status == 0xFF then
            local mt = data:byte(p)
            if not mt then return nil, 'truncated meta event' end
            p = p + 1
            local ml
            ml, p = VLQ(data, p)
            if not ml then return nil, 'bad meta length' end
            local payload = data:sub(p, p + ml - 1)
            p = p + ml

            if mt == META_TRACK_NAME and not trk.name then
                trk.name = payload
            end
            if TEXTISH[mt] then
                trk.texts[#trk.texts + 1] = { tick = tick, text = payload, type = mt }
            elseif mt == META_TEMPO and ml == 3 then
                trk.tempos[#trk.tempos + 1] = { tick = tick, uspqn = BE(payload, 1, 3) }
            elseif mt == META_TIMESIG and ml >= 2 then
                trk.timesigs[#trk.timesigs + 1] = {
                    tick = tick, num = payload:byte(1), den = 2 ^ payload:byte(2),
                }
            elseif mt == META_END then
                break
            end

        elseif status == 0xF0 or status == 0xF7 then
            local ml
            ml, p = VLQ(data, p)
            if not ml then return nil, 'bad sysex length' end
            p = p + ml

        else
            local hi   = status - (status % 16)
            local chan = status % 16
            if hi == 0xC0 or hi == 0xD0 then
                p = p + 1                       -- program change / channel pressure
            else
                local d1, d2 = data:byte(p), data:byte(p + 1)
                if not d2 then return nil, 'truncated channel message' end
                p = p + 2

                if hi == 0x90 and d2 > 0 then
                    trk.notes[#trk.notes + 1] = {
                        tick = tick, pitch = d1, vel = d2, chan = chan, len = 0,
                    }
                    local k = chan * 128 + d1
                    local st = open[k]
                    if not st then st = {}; open[k] = st end
                    st[#st + 1] = #trk.notes
                elseif hi == 0x80 or (hi == 0x90 and d2 == 0) then
                    local k  = chan * 128 + d1
                    local st = open[k]
                    if st and #st > 0 then
                        local idx = st[#st]
                        st[#st] = nil
                        trk.notes[idx].len = tick - trk.notes[idx].tick
                    end
                end
            end
        end
    end

    -- A note left open at end-of-track keeps len 0 rather than being dropped: the onset
    -- is real data and a census that counts onsets should still see it.
    return trk
end

----------------------------------------------------------------------
-- File parsing
----------------------------------------------------------------------

-- Parses SMF bytes. Returns song, or nil + error string.
--   song = { format, tpqn, tracks = { track, ... } }
--   track = { name, notes, texts, tempos, timesigs }
--   note  = { tick, pitch, vel, chan, len }
--   text  = { tick, text, type }
function SmfParse(data)
    if type(data) ~= 'string' or #data < 14 then return nil, 'too short to be an SMF' end
    if data:sub(1, 4) ~= 'MThd' then return nil, 'missing MThd header' end

    local hlen   = BE(data, 5, 4)
    local format = BE(data, 9, 2)
    local ntrk   = BE(data, 11, 2)
    local div    = BE(data, 13, 2)

    if format ~= 0 and format ~= 1 then
        return nil, ('unsupported SMF format %d'):format(format)
    end
    -- High bit set means SMPTE frame division. No Rock Band MIDI uses it, and silently
    -- treating the byte pair as a PPQN would scale every tick wrongly.
    if div >= 0x8000 then return nil, 'SMPTE time division is not supported' end
    if div == 0 then return nil, 'zero time division' end

    local song = { format = format, tpqn = div, tracks = {} }
    local pos  = 8 + hlen + 1

    for _ = 1, ntrk do
        if pos + 8 > #data then break end
        if data:sub(pos, pos + 3) ~= 'MTrk' then
            return nil, ('expected MTrk at byte %d'):format(pos)
        end
        local len  = BE(data, pos + 4, 4)
        local trk, err = ParseTrack(data, pos + 8, pos + 8 + len)
        if not trk then
            return nil, ('track %d: %s'):format(#song.tracks + 1, err)
        end
        song.tracks[#song.tracks + 1] = trk
        pos = pos + 8 + len
    end

    return song
end

-- Reads and parses a file. Returns song, or nil + error string.
function SmfReadFile(path)
    local f, err = io.open(path, 'rb')
    if not f then return nil, err or ('cannot open ' .. tostring(path)) end
    local data = f:read('a')
    f:close()
    if not data then return nil, 'empty file: ' .. tostring(path) end
    return SmfParse(data)
end

----------------------------------------------------------------------
-- Lookups
----------------------------------------------------------------------

-- EXACT track-name match, deliberately. A substring match is wrong on this corpus:
-- 'PART KEYS' is a prefix of 'PART KEYS_ANIM_LH' and 'PART REAL_KEYS' a prefix of
-- 'PART REAL_KEYS_H', so a loose search silently scores the wrong track. Mirrors
-- FindTrackExact in dev/calibration/corpus.lua.
function SmfFindTrack(song, name)
    for _, trk in ipairs(song.tracks) do
        if trk.name == name then return trk end
    end
    return nil
end

function SmfTrackNames(song)
    local out = {}
    for _, trk in ipairs(song.tracks) do out[#out + 1] = trk.name or '' end
    return out
end

-- Notes in an inclusive pitch window, in tick order.
function SmfNotesInRange(trk, lo, hi)
    local out = {}
    for _, n in ipairs(trk.notes) do
        if n.pitch >= lo and n.pitch <= hi then out[#out + 1] = n end
    end
    table.sort(out, function(a, b)
        if a.tick ~= b.tick then return a.tick < b.tick end
        return a.pitch < b.pitch
    end)
    return out
end

-- pitch -> count, over one track. The workhorse of a marker census.
function SmfPitchHistogram(trk)
    local h = {}
    for _, n in ipairs(trk.notes) do h[n.pitch] = (h[n.pitch] or 0) + 1 end
    return h
end

-- Text events of one meta type (default 1 = text). Type 5 is lyric.
function SmfTexts(trk, mtype)
    mtype = mtype or META_TEXT
    local out = {}
    for _, t in ipairs(trk.texts) do
        if t.type == mtype then out[#out + 1] = t end
    end
    return out
end

----------------------------------------------------------------------
-- Tempo
----------------------------------------------------------------------

-- Collects tempo changes from every track into one sorted map. Format 1 files put them
-- on track 1 by convention, but the spec does not require it and collecting is cheaper
-- than trusting the convention.
--
-- Returns an array of { tick, uspqn, sec } where `sec` is the wall time of that tick.
-- Always starts at tick 0: an SMF with no tempo event means 120 BPM.
function SmfTempoMap(song)
    local all = {}
    for _, trk in ipairs(song.tracks) do
        for _, tp in ipairs(trk.tempos) do all[#all + 1] = tp end
    end
    table.sort(all, function(a, b) return a.tick < b.tick end)

    local map = {}
    if #all == 0 or all[1].tick > 0 then
        map[1] = { tick = 0, uspqn = 500000, sec = 0 }   -- 120 BPM default
    end
    for _, tp in ipairs(all) do
        local prev = map[#map]
        if prev and prev.tick == tp.tick then
            prev.uspqn = tp.uspqn                        -- last one at a tick wins
        else
            local sec = 0
            if prev then
                sec = prev.sec + (tp.tick - prev.tick) * prev.uspqn / (song.tpqn * 1e6)
            end
            map[#map + 1] = { tick = tp.tick, uspqn = tp.uspqn, sec = sec }
        end
    end
    return map
end

-- Wall-clock seconds for a tick, given a map from SmfTempoMap.
function SmfTickToSec(map, tpqn, tick)
    local seg = map[1]
    for i = 2, #map do
        if map[i].tick > tick then break end
        seg = map[i]
    end
    return seg.sec + (tick - seg.tick) * seg.uspqn / (tpqn * 1e6)
end

----------------------------------------------------------------------
-- Corpus walking (Windows)
----------------------------------------------------------------------

-- Recursive file list under `root` matching `pattern` (a Lua pattern on the full path).
-- Uses `dir /b /s`, so it is Windows-only - which every consumer of this file is. Kept
-- here so a census script is a question and a loop, not a question and a shell pipeline.
function SmfListFiles(root, pattern)
    pattern = pattern or '%.mid$'
    local out = {}
    local cmd = ('dir /b /s "%s" 2>nul'):format(root:gsub('/', '\\'))
    local pipe = io.popen(cmd)
    if not pipe then return out end
    for line in pipe:lines() do
        if line:lower():match(pattern) then out[#out + 1] = line end
    end
    pipe:close()
    table.sort(out)
    return out
end

-- Shortname for a reference-corpus MIDI: the file's own basename, which in this corpus
-- is always the song shortname. Identifiers, not content - safe to print in a report.
function SmfShortname(path)
    return (path:match('([^\\/]+)%.[Mm][Ii][Dd]$')) or path
end
