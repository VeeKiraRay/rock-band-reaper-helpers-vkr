-- Rock Band chart events from a parsed MIDI file (dev/tools/smf_reader.lua), in the shape
-- the Difficulty > Generate planner (difficulty_generate_5lane.lua) takes. Plain Lua - no
-- REAPER - so the offline evaluation and the golden-chart test read files exactly alike.
--
--   dofile('.../dev/tools/smf_reader.lua')
--   dofile('.../dev/tools/smf_chart_events.lua')
--   local song   = SmfReadFile(path)
--   local timing = SmfSongTiming(song)
--   local events = SmfTierEvents(SmfFindTrack(song, 'PART GUITAR'), 96, song.tpqn, timing)
--
-- Event: { tick, qn, qn_e, offs (gem offsets from lo, ascending), bpm, bar_qn, bar_len, down }.
-- Positions are tick / tpqn, so they are exact - the REAPER action reaches the same values
-- by snapping its seconds-based reads (actions_difficulty_generate.lua, SnapQN).

-- Tempo, bar position and bar number for any tick.
-- Returns { Bpm(tick), BarPos(tick) -> bar_qn, is_downbeat, BarLen(tick) -> QN,
--   BarNumber(tick) -> 1-based }.
function SmfSongTiming(song)
    local tempo = SmfTempoMap(song)
    local sigs = {}
    for _, trk in ipairs(song.tracks) do
        for _, x in ipairs(trk.timesigs or {}) do sigs[#sigs + 1] = x end
    end
    table.sort(sigs, function(a, b) return a.tick < b.tick end)
    if #sigs == 0 or sigs[1].tick > 0 then table.insert(sigs, 1, { tick = 0, num = 4, den = 4 }) end
    local tpqn = song.tpqn

    local function Seg(list, tick)
        local seg = list[1]
        for i = 2, #list do
            if list[i].tick > tick then break end
            seg = list[i]
        end
        return seg
    end
    local function MeasTicks(sig) return sig.num * tpqn * 4 / sig.den end

    local timing = {}
    function timing.Bpm(tick) return 60e6 / Seg(tempo, tick).uspqn end
    function timing.BarPos(tick)
        local sig  = Seg(sigs, tick)
        local meas = MeasTicks(sig)
        local pos  = (tick - sig.tick) % meas
        local tol  = tpqn * 0.02
        return pos / tpqn, pos <= tol or meas - pos <= tol
    end
    function timing.BarLen(tick) return MeasTicks(Seg(sigs, tick)) / tpqn end
    function timing.BarNumber(tick)
        local bars = 0
        for i, sig in ipairs(sigs) do
            local nxt = sigs[i + 1]
            local meas = MeasTicks(sig)
            if nxt and nxt.tick <= tick then
                bars = bars + math.floor((nxt.tick - sig.tick) / meas + 0.5)
            else
                return bars + math.floor((tick - sig.tick) / meas + 1e-9) + 1
            end
        end
        return bars + 1
    end
    return timing
end

-- One tier's gem events: notes in [lo, lo + 4], grouped into chords by shared onset.
-- opts.skip_zero: drop zero-length notes, as the REAPER action does (REAPER deletes them
-- from a take on the next edit, so Generate never builds from them).
function SmfTierEvents(trk, lo, tpqn, timing, opts)
    opts = opts or {}
    local notes = {}
    for _, n in ipairs(SmfNotesInRange(trk, lo, lo + 4)) do
        if not (opts.skip_zero and n.len <= 0) then notes[#notes + 1] = n end
    end
    local events, tol = {}, tpqn / 96
    local i = 1
    while i <= #notes do
        local n0 = notes[i]
        local ev = { tick = n0.tick, qn = n0.tick / tpqn, qn_e = (n0.tick + n0.len) / tpqn,
                     offs = { n0.pitch - lo } }
        local j = i + 1
        while j <= #notes and notes[j].tick - n0.tick <= tol do
            local nj = notes[j]
            ev.offs[#ev.offs + 1] = nj.pitch - lo
            ev.qn_e = math.max(ev.qn_e, (nj.tick + nj.len) / tpqn)
            j = j + 1
        end
        table.sort(ev.offs)
        ev.bpm = timing.Bpm(n0.tick)
        ev.bar_qn, ev.down = timing.BarPos(n0.tick)
        ev.bar_len = timing.BarLen(n0.tick)
        events[#events + 1] = ev
        i = j
    end
    return events
end
