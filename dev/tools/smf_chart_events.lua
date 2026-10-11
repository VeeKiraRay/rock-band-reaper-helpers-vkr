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
-- Event: { tick, qn, qn_e, offs (gem offsets from lo, ascending), bpm, bar_qn, bar_len, pulse, down }.
-- pulse is the bar's beat (Gen5PulseQN, difficulty_generate_params.lua - load that first).
-- Positions are tick / tpqn, so they are exact - the REAPER action reaches the same values
-- by snapping its seconds-based reads (actions_difficulty_generate.lua, SnapQN).

-- Tempo, bar position and bar number for any tick.
-- Returns { Bpm(tick), BarPos(tick) -> bar_qn, is_downbeat, BarLen(tick) -> QN,
--   Sig(tick) -> num, den, BarNumber(tick) -> 1-based }. Bpm is quarter notes per minute
--   in every time signature, as the file stores it.
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
    function timing.Sig(tick)
        local sig = Seg(sigs, tick)
        return sig.num, sig.den
    end
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

-- One Pro Keys tier track (PART REAL_KEYS_X/H/M/E): playable events with real pitches in
-- offs (48-72, the shape difficulty_generate_prokeys.lua takes), and the lane-shift
-- markers { qn, qn_e, pitch } (pitches 0-9). Returns (events, shifts).
function SmfProKeysEvents(trk, tpqn, timing, opts)
    opts = opts or {}
    local events, tol = {}, tpqn / 96
    local notes = {}
    for _, n in ipairs(SmfNotesInRange(trk, 48, 72)) do
        if not (opts.skip_zero and n.len <= 0) then notes[#notes + 1] = n end
    end
    local i = 1
    while i <= #notes do
        local n0 = notes[i]
        local ev = { tick = n0.tick, qn = n0.tick / tpqn, qn_e = (n0.tick + n0.len) / tpqn, offs = { n0.pitch } }
        local j = i + 1
        while j <= #notes and notes[j].tick - n0.tick <= tol do
            ev.offs[#ev.offs + 1] = notes[j].pitch
            ev.qn_e = math.max(ev.qn_e, (notes[j].tick + notes[j].len) / tpqn)
            j = j + 1
        end
        table.sort(ev.offs)
        ev.bpm = timing.Bpm(n0.tick)
        ev.bar_qn, ev.down = timing.BarPos(n0.tick)
        ev.bar_len = timing.BarLen(n0.tick)
        ev.pulse   = Gen5PulseQN(timing.Sig(n0.tick))
        events[#events + 1] = ev
        i = j
    end
    local shifts, marker = {}, { [0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true }
    for _, n in ipairs(SmfNotesInRange(trk, 0, 9)) do
        if marker[n.pitch] then
            shifts[#shifts + 1] = { qn = n.tick / tpqn, qn_e = (n.tick + n.len) / tpqn, pitch = n.pitch }
        end
    end
    return events, shifts
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
        ev.pulse   = Gen5PulseQN(timing.Sig(n0.tick))
        events[#events + 1] = ev
        i = j
    end
    return events
end

-- The marker context the Drums planner (difficulty_generate_drums.lua, opts.ctx) takes,
-- from a song's PART DRUMS track and its EVENTS track, in quarter notes:
--   fills    { { qn, qn_e }... }  drum fill lanes (120 - all five lanes span the same)
--   rolls    roll (126) and special roll (127) lanes
--   toms     { [2|3|4] = spans }  Pro Drums tom markers 110 / 111 / 112 (Y / B / G)
--   disco    Expert's disco-flip spans: [mix 3 drumsNd] up to the next [mix 3 drumsN]
--            ("dnoflip" is not a flip for the lower tiers)
--   sections { { qn, name }... }  [section x] / [prc_x] text events on EVENTS
function SmfDrumsContext(song, trk)
    local tpqn = song.tpqn
    local function Spans(lo, hi)
        local out = {}
        for _, n in ipairs(SmfNotesInRange(trk, lo, hi)) do
            out[#out + 1] = { qn = n.tick / tpqn, qn_e = (n.tick + n.len) / tpqn }
        end
        return out
    end
    local ctx = { fills = Spans(120, 120), rolls = Spans(126, 127),
                  toms = { [2] = Spans(110, 110), [3] = Spans(111, 111), [4] = Spans(112, 112) },
                  disco = {}, sections = {} }
    local open
    for _, t in ipairs(SmfTexts(trk)) do
        local suffix = t.text:match('^%[mix 3 drums%d(%a*)%]')
        if suffix then
            if suffix == 'd' then
                open = open or t.tick
            elseif open then
                ctx.disco[#ctx.disco + 1] = { qn = open / tpqn, qn_e = t.tick / tpqn }
                open = nil
            end
        end
    end
    if open then ctx.disco[#ctx.disco + 1] = { qn = open / tpqn, qn_e = math.huge } end
    local ev_trk = SmfFindTrack(song, 'EVENTS')
    if ev_trk then
        for _, t in ipairs(SmfTexts(ev_trk)) do
            local name = t.text:match('^%[section (.-)%]') or t.text:match('^%[prc_(.-)%]')
            if name then ctx.sections[#ctx.sections + 1] = { qn = t.tick / tpqn, name = name } end
        end
    end
    return ctx
end
