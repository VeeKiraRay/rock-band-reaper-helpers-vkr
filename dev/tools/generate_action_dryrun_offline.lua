-- Offline dry run of Difficulty > Generate - the real GenerateDifficulties action, not just
-- the planner - under plain Lua 5.4, against MIDI files. No REAPER.
--
--   lua dev/tools/generate_action_dryrun_offline.lua
--       the test fixtures (verbose) + every 6th development song of the RB3 DLC corpus
--       (summary: runs that leave Validate errors)
--   lua dev/tools/generate_action_dryrun_offline.lua <song.mid> [gtr|bass|keys|pk|all] [from_qn to_qn]
--       one song, one part (default gtr): the result text, then X/H/M/E for the range
--       (default: 16 QN from the first Expert note). 'all' runs All instruments (Pro Keys
--       first, then Keys following it) and dumps Pro Keys and Keys.
--
-- A minimal REAPER stand-in: InsertMedia parses the file with dev/tools/smf_reader.lua
-- into in-memory tracks, the project tempo map is the file's own, and notes can be read,
-- inserted and deleted. Like REAPER (observed), inserting a note re-sorts the take and drops
-- its zero-length notes, so Generate's "removed by REAPER" report can be exercised. Every
-- module is loaded as-is, and Validate's own checks run on what Generate writes - the same
-- verification Generate does inside REAPER.
--
-- Use it after a planner change, beside dev/tests/run_generate_golden.lua and
-- dev/calibration/run_generate_eval_offline.lua. It is a stand-in: a result here is strong
-- evidence, not proof - run the REAPER suites before shipping.

local _self = (arg and arg[0] or ''):gsub('\\', '/')
if not _self:match('^%a:') and not _self:match('^/') then _self = './' .. _self end
local _root = _self:match('^(.*/)dev/tools/[^/]+$') or './'
local M     = _root .. 'rock_band_general_helper_vkr/'

dofile(_root .. 'dev/tools/smf_reader.lua')

----------------------------------------------------------------------
-- REAPER stand-in
----------------------------------------------------------------------

local missing = {}
local P = { tracks = {}, markers = {}, timesigs = {} }

local SEG
local function Rebuild()
    table.sort(P.markers, function(a, b) return a.timepos < b.timepos end)
    SEG = {}
    if #P.markers == 0 or P.markers[1].timepos > 0 then SEG[1] = { t = 0, qn = 0, bpm = 120 } end
    for _, m in ipairs(P.markers) do
        local prev = SEG[#SEG]
        local qn = prev and (prev.qn + (m.timepos - prev.t) * prev.bpm / 60) or 0
        SEG[#SEG + 1] = { t = m.timepos, qn = qn, bpm = m.bpm }
    end
end
local function SegBy(key, v)
    local lo, hi = 1, #SEG
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if SEG[mid][key] <= v then lo = mid else hi = mid - 1 end
    end
    return SEG[lo]
end
local function TimeToQN(t) local s = SegBy('t', t); return s.qn + (t - s.t) * s.bpm / 60 end
local function QNToTime(qn) local s = SegBy('qn', qn); return s.t + (qn - s.qn) * 60 / s.bpm end
Rebuild()

local function SigAt(qn)
    local ts = { qn = 0, num = 4, denom = 4 }
    for _, x in ipairs(P.timesigs) do if x.qn <= qn + 1e-9 then ts = x end end
    return ts, ts.num * 4 / ts.denom
end

local api = {
    ClearConsole = function() end,
    ShowConsoleMsg = function(s) io.write(s) end,
    PreventUIRefresh = function() end, UpdateArrange = function() end, UpdateTimeline = function() end,
    SetEditCurPos = function() end, SetTrackSelected = function() end,
    Undo_BeginBlock2 = function() end, Undo_EndBlock2 = function() end,
    MarkTrackItemsDirty = function() end,
    CountTracks = function() return #P.tracks end,
    GetTrack = function(_, i) return P.tracks[i + 1] end,
    DeleteTrack = function(tr)
        for i, t in ipairs(P.tracks) do if t == tr then table.remove(P.tracks, i) return end end
    end,
    GetTrackName = function(tr) return true, tr.name end,
    GetSetMediaTrackInfo_String = function(tr) return true, tr.name end,
    GetMediaTrackInfo_Value = function(tr, k) return k == 'B_MUTE' and (tr.mute or 0) or 0 end,
    CountTrackMediaItems = function() return 1 end,
    GetTrackMediaItem = function(tr) return tr end,
    GetActiveTake = function(item) return item end,
    TakeIsMIDI = function() return true end,
    -- The item ends at its last event, as an imported MIDI item does in REAPER: a
    -- zero-length chord at the end of a track sits exactly ON the item's end.
    GetMediaItemInfo_Value = function(item, k)
        if k ~= 'D_LENGTH' then return 0 end
        local last = 0
        for _, n in ipairs(item.notes or {}) do last = math.max(last, n.tick + n.len) end
        return QNToTime(last / (item.tpqn or 480))
    end,
    MIDI_CountEvts = function(take) return true, #take.notes, 0, 0 end,
    MIDI_GetNote = function(take, j)
        local n = take.notes[j + 1]
        return true, false, false, n.tick, n.tick + n.len, n.chan or 0, n.pitch, n.vel
    end,
    MIDI_GetProjTimeFromPPQPos = function(take, ppq) return QNToTime(ppq / take.tpqn) end,
    MIDI_GetPPQPosFromProjTime = function(take, t) return math.floor(TimeToQN(t) * take.tpqn + 0.5) end,
    MIDI_InsertNote = function(take, _, _, sp, ep, chan, pitch, vel)
        take.notes[#take.notes + 1] = { tick = sp, len = ep - sp, pitch = pitch, vel = vel, chan = chan }
        for k = #take.notes, 1, -1 do               -- REAPER drops zero-length notes on re-sort
            if take.notes[k].len <= 0 then table.remove(take.notes, k) end
        end
        return true
    end,
    MIDI_DeleteNote = function(take, i) table.remove(take.notes, i + 1); return true end,
    -- The whole take as REAPER's packed event buffer (int32 tick offset, flag byte, int32
    -- length, message), notes only plus an end-of-take CC 123, and back. Pairs note-ons
    -- with note-offs first on, first off, like REAPER. Lets the action's bulk write
    -- (ReplaceNotesBulk) run here.
    MIDI_GetAllEvts = function(take)
        local evs = {}
        local last_tick = 0
        for i, n in ipairs(take.notes) do
            local ch = n.chan or 0
            evs[#evs + 1] = { t = n.tick, k = 1, i = i, msg = string.char(0x90 | ch, n.pitch, n.vel or 100) }
            evs[#evs + 1] = { t = n.tick + n.len, k = 0, i = i, msg = string.char(0x80 | ch, n.pitch, 0) }
            if n.tick + n.len > last_tick then last_tick = n.tick + n.len end
        end
        table.sort(evs, function(a, b)
            if a.t ~= b.t then return a.t < b.t end
            if a.k ~= b.k then return a.k < b.k end
            return a.i < b.i
        end)
        evs[#evs + 1] = { t = last_tick, msg = string.char(0xB0, 123, 0) }
        local parts, prev = {}, 0
        for i, ev in ipairs(evs) do
            parts[i] = string.pack('<i4Bs4', ev.t - prev, 0, ev.msg)
            prev = ev.t
        end
        return true, table.concat(parts)
    end,
    MIDI_SetAllEvts = function(take, buf)
        local notes, open, pos, tick = {}, {}, 1, 0
        while pos <= #buf do
            local off, _, msg
            off, _, msg, pos = string.unpack('<i4Bs4', buf, pos)
            tick = tick + off
            if #msg >= 3 then
                local st = msg:byte(1)
                local typ, ch, pitch, vel = st & 0xF0, st & 0x0F, msg:byte(2), msg:byte(3)
                local key = ch * 128 + pitch
                if typ == 0x90 and vel > 0 then
                    open[key] = open[key] or {}
                    table.insert(open[key], { tick = tick, pitch = pitch, vel = vel, chan = ch })
                elseif typ == 0x80 or typ == 0x90 then
                    local on = open[key] and table.remove(open[key], 1)
                    if on then
                        on.len = tick - on.tick
                        notes[#notes + 1] = on
                    end
                end
            end
        end
        -- A note-on never closed stays a (zero-length) note, as in REAPER: a stale one left
        -- in the buffer shows up as a duplicate of the note written over it.
        for _, q in pairs(open) do
            for _, on in ipairs(q) do on.len = 0; notes[#notes + 1] = on end
        end
        table.sort(notes, function(a, b) return a.tick < b.tick end)
        take.notes = notes
        return true
    end,
    -- The stand-in sorts on every insert anyway, so batching is a no-op here.
    MIDI_DisableSort = function() end,
    MIDI_Sort = function() end,
    time_precise = function() return os.clock() end,
    TimeMap2_timeToQN = function(_, t) return TimeToQN(t) end,
    TimeMap2_QNToTime = function(_, qn) return QNToTime(qn) end,
    -- As REAPER: the tempo of the time signature's own beat, "2x in /8 signatures". The
    -- planner must not use it (Generate once did, and 6/8 songs read at double tempo);
    -- faithful here so such a read shows up offline too.
    TimeMap_GetDividedBpmAtTime = function(t)
        local ts = SigAt(TimeToQN(t))
        return SegBy('t', t).bpm * ts.denom / 4
    end,
    TimeMap_GetTimeSigAtTime = function(_, t)
        local ts = SigAt(TimeToQN(t))
        return ts.num, ts.denom, SegBy('t', t).bpm
    end,
    Master_GetTempo = function() return SEG[1] and SEG[1].bpm or 120 end,
    TimeMap2_timeToBeats = function(_, t)
        local qn = TimeToQN(t)
        local ts, meas = SigAt(qn)
        local beat = 4 / ts.denom
        return ((qn - ts.qn) % meas) / beat, 0, meas / beat
    end,
    TimeMap_QNToMeasures = function(_, qn)
        local ts, meas = SigAt(qn)
        local k = math.floor((qn - ts.qn) / meas + 1e-9)
        local s = ts.qn + k * meas
        return k, s, s + meas
    end,
    format_timestr_pos = function(t) return ('%d.1.00'):format(math.floor(TimeToQN(t) / 4) + 1) end,
    GetSet_LoopTimeRange = function() return 0, 0 end,
    CountTempoTimeSigMarkers = function() return #P.markers end,
    FindTempoTimeSigMarker = function(_, t)
        local idx = -1
        for i, m in ipairs(P.markers) do if m.timepos <= t then idx = i - 1 end end
        return idx
    end,
    GetTempoTimeSigMarker = function(_, i)
        local m = P.markers[i + 1]
        if not m then return false end
        return true, m.timepos, 0, 0, m.bpm, -1, -1, false
    end,
    ImGui_GetFrameHeight = function() return 20 end,
    InsertMedia = function(path)
        local song = SmfReadFile(path)
        if not song then return 0 end
        P.markers = {}
        for _, m in ipairs(SmfTempoMap(song)) do
            P.markers[#P.markers + 1] = { timepos = m.sec, bpm = 60e6 / m.uspqn }
        end
        Rebuild()
        P.timesigs = {}
        for _, trk in ipairs(song.tracks) do
            for _, x in ipairs(trk.timesigs or {}) do
                P.timesigs[#P.timesigs + 1] = { qn = x.tick / song.tpqn, num = x.num, denom = x.den }
            end
        end
        table.sort(P.timesigs, function(a, b) return a.qn < b.qn end)
        for _, trk in ipairs(song.tracks) do
            P.tracks[#P.tracks + 1] = { name = trk.name or '', notes = trk.notes, tpqn = song.tpqn }
        end
        return 1
    end,
}
reaper = setmetatable(api, { __index = function(_, k)
    missing[k] = true
    return function() return nil end
end })
r = reaper
ctx = nil

----------------------------------------------------------------------
-- The modules, as the entry point loads them
----------------------------------------------------------------------

SCRIPT_MDIR = M
for _, f in ipairs({
    _root .. 'lib/reaper_imgui_helpers.lua', _root .. 'lib/reaper_midi_helpers.lua',
    _root .. 'lib/reaper_guitar_theory.lua', _root .. 'lib/reaper_difficulty_score.lua',
    _root .. 'lib/reaper_difficulty_score_vocals.lua',
    M .. 'defaults.lua', M .. 'helpers.lua', M .. 'actions_guitar.lua', M .. 'actions_guitar_validate.lua',
    M .. 'actions_difficulty_shared.lua', M .. 'actions_difficulty.lua', M .. 'actions_difficulty_5k.lua',
    M .. 'actions_difficulty_gtrbass.lua',
    M .. 'difficulty_generate_params.lua', M .. 'difficulty_generate_overlaps.lua', M .. 'difficulty_generate_retime.lua',
    M .. 'difficulty_generate_colors.lua', M .. 'difficulty_generate_rhythm.lua',
    M .. 'difficulty_generate_5lane.lua', M .. 'difficulty_generate_prokeys.lua',
    M .. 'difficulty_generate_hopo.lua', M .. 'actions_difficulty_generate.lua', M .. 'difficulty_read.lua',
    _root .. 'dev/calibration/difficulty_holdout.lua',
}) do dofile(f) end

local PARTS = {
    gtr  = { field = 'diff_gtr_idx',  track = 'PART GUITAR', read = ReadGBTierEvents, range = GB_RANGE },
    bass = { field = 'diff_bass_idx', track = 'PART BASS',   read = ReadGBTierEvents, range = GB_RANGE },
    keys = { field = 'diff_5k_idx',   track = 'PART KEYS',   read = ReadK5TierEvents, range = K5_RANGE },
    -- A track per tier; the dump reads each tier's own track.
    pk   = { field = 'diff_pk_x_idx', track = 'PART REAL_KEYS_X', pk = true },
}
local PK_FIELDS = { X = 'diff_pk_x_idx', H = 'diff_pk_h_idx', M = 'diff_pk_m_idx', E = 'diff_pk_e_idx' }

-- Load a song and generate one part (or 'all') H>M>E. Returns the part's track (nil if
-- the part is absent).
local function Run(path, key)
    P.tracks = {}
    reaper.InsertMedia(path)
    local part = PARTS[key == 'all' and 'pk' or key]
    S.diff_gtr_idx, S.diff_bass_idx, S.diff_5k_idx = -1, -1, -1
    for _, f in pairs(PK_FIELDS) do S[f] = -1 end
    for i, tr in ipairs(P.tracks) do
        for k, pt in pairs(PARTS) do if tr.name == pt.track then S[pt.field] = i - 1 end end
        for dl, f in pairs(PK_FIELDS) do if tr.name == 'PART REAL_KEYS_' .. dl then S[f] = i - 1 end end
    end
    if S[part.field] < 0 then return nil end
    S.diff_copy_pending = nil
    local ok, err = pcall(GenerateDifficulties, key == 'all' and GEN_ALL_KEY or key, { 'H', 'M', 'E' }, true)
    -- A question after the overwrite one (Pro Keys Hard equal to Expert): take the
    -- second answer, "Keep as Expert", so the run writes what the planner made.
    local pending = S.diff_copy_pending
    if ok and pending and pending.on_alt then
        S.diff_copy_pending = nil
        ok, err = pcall(pending.on_alt)
    end
    if not ok then S.status, S.last_result = 'ERROR ' .. tostring(err), nil end
    return reaper.GetTrack(0, S[part.field])
end

-- Pro Keys: each tier's own track, pitch names, lane shifts as [marker].
local function DumpProKeys(q0, q1)
    for _, dl in ipairs({ 'X', 'H', 'M', 'E' }) do
        local tr = S[PK_FIELDS[dl]] >= 0 and reaper.GetTrack(0, S[PK_FIELDS[dl]])
        local cells = {}
        if tr then
            local shifts, events = ReadPKTierEvents(tr)
            for _, sh in ipairs(shifts) do
                local qn = reaper.TimeMap2_timeToQN(0, sh.s)
                if qn < q1 then cells[#cells + 1] = ('%g:[%d]'):format(qn, sh.pitch) end
            end
            for _, ev in ipairs(events) do
                local qn = reaper.TimeMap2_timeToQN(0, ev.s)
                if qn >= q0 and qn < q1 then
                    local ps = {}
                    for _, p in ipairs(ev.pitches) do ps[#ps + 1] = PitchName(p) end
                    local len = reaper.TimeMap2_timeToQN(0, ev.e) - qn
                    cells[#cells + 1] = ('%g:%s%s'):format(qn, table.concat(ps, '+'), len >= 0.49 and '~' or '')
                end
            end
        end
        print('  ' .. dl, table.concat(cells, ' '))
    end
end

local COLORS = { [0] = 'G', 'R', 'Y', 'B', 'O' }
local function DumpTiers(track, key, q0, q1)
    local part = PARTS[key]
    for _, dl in ipairs({ 'X', 'H', 'M', 'E' }) do
        local lo, cells = part.range[dl].lo, {}
        for _, ev in ipairs(part.read(track, dl)) do
            local qn = reaper.TimeMap2_timeToQN(0, ev.s)
            if qn >= q0 and qn < q1 then
                local cs = {}
                for _, p in ipairs(ev.pitches) do cs[#cs + 1] = COLORS[p - lo] or '?' end
                local len = reaper.TimeMap2_timeToQN(0, ev.e) - qn
                cells[#cells + 1] = ('%g:%s%s'):format(qn, table.concat(cs), len >= 0.49 and '~' or '')
            end
        end
        print('  ' .. dl, table.concat(cells, ' '))
    end
end

if arg[1] then
    local key = arg[2] or 'gtr'
    local track = Run(arg[1], key)
    local part = PARTS[key == 'all' and 'pk' or key]
    if not track then print(('no %s track in %s'):format(part.track, arg[1])); return end
    print(S.status)
    print(S.last_result or '')
    local q0 = tonumber(arg[3])
    if not q0 then
        local x = part.pk and select(2, ReadPKTierEvents(track)) or part.read(track, 'X')
        q0 = x[1] and math.floor(reaper.TimeMap2_timeToQN(0, x[1].s)) or 0
    end
    local q1 = tonumber(arg[4]) or (q0 + 16)
    if part.pk then
        DumpProKeys(q0, q1)
        if key == 'all' and S.diff_5k_idx >= 0 then
            print('  Keys:')
            DumpTiers(reaper.GetTrack(0, S.diff_5k_idx), 'keys', q0, q1)
        end
    else
        DumpTiers(track, key, q0, q1)
    end
else
    for _, f in ipairs({ { 'rb_guitar.mid', 'gtr' }, { 'rb_bass.mid', 'bass' }, { 'rb_keys.mid', 'keys' } }) do
        Run(_root .. 'dev/tests/midi/' .. f[1], f[2])
        print(('%-14s %s'):format(f[1], S.status))
    end
    local files = SmfListFiles(_root .. '_external_docs/all_rb3_dlc_reference_songs/', '%.mid$')
    local n, bad = 0, 0
    for i, path in ipairs(files) do
        local name = SmfShortname(path)
        if i % 6 == 0 and not name:find('%(') and not DiffIsHeldOut(name) then
            for _, key in ipairs({ 'gtr', 'bass', 'keys', 'pk' }) do
                if Run(path, key) then
                    n = n + 1
                    if not S.status:find('no Validate errors', 1, true) then
                        bad = bad + 1
                        print(('%-28s %s'):format(name .. ' ' .. key, S.status))
                    end
                end
            end
        end
    end
    print(('corpus sample: %d runs, %d with Validate errors left'):format(n, bad))
end

local m = {}
for k in pairs(missing) do m[#m + 1] = k end
table.sort(m)
if #m > 0 then print('REAPER calls not in the stand-in (returned nil): ' .. table.concat(m, ', ')) end
