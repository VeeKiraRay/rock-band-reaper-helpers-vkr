-- VENUE track parsing and validation
-- Requires: VENUE_VALID, DIRECTED_GAP_MIN, MIDI_META_NAMES, S, FormatTime, r (globals)

local function FindVenueTrack()
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetTrackName(tr)
        if name == 'VENUE' then return tr end
    end
    return nil
end

local function ReadVenueTextEvents(track)
    local take = nil
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local t = r.GetActiveTake(item)
        if t and r.TakeIsMIDI(t) then take = t; break end
    end
    if not take then return nil, 'No MIDI item found on VENUE track.' end

    local events = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evtype >= 1 and evtype <= 15 then
            local t_pos = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
            events[#events + 1] = { msg = msg, t = t_pos, ppq = ppq, evtype = evtype }
        end
    end
    return events
end

-- Returns two lists of {gap, t, from, to} records from a sorted cam_events list.
-- Primary:   gaps where source is [coop...] (to any camera event)
-- Secondary: gaps where source is [directed...] and destination is [coop...]
local function BuildCameraGaps(cam_events)
    local primary   = {}
    local secondary = {}
    for i = 1, #cam_events - 1 do
        local ev      = cam_events[i]
        local next_ev = cam_events[i + 1]
        local gap     = next_ev.t - ev.t
        if ev.msg:match('^%[coop') then
            primary[#primary + 1] = { gap = gap, t = ev.t, from = ev.msg, to = next_ev.msg }
        elseif ev.msg:match('^%[directed') and next_ev.msg:match('^%[coop') then
            secondary[#secondary + 1] = { gap = gap, t = ev.t, from = ev.msg, to = next_ev.msg }
        end
    end
    return primary, secondary
end

local function GapStats(gaps)
    if #gaps == 0 then return nil end
    local total   = 0
    local slowest = gaps[1]
    local fastest = gaps[1]
    for _, g in ipairs(gaps) do
        total = total + g.gap
        if g.gap > slowest.gap then slowest = g end
        if g.gap < fastest.gap then fastest = g end
    end
    return { count = #gaps, avg = total / #gaps, slowest = slowest, fastest = fastest }
end

function ListVenueEvents()
    local track = FindVenueTrack()
    if not track then
        S.status = 'No VENUE track found.'
        S.last_result = 'No VENUE track detected.'
        return
    end

    local all_events, err = ReadVenueTextEvents(track)
    if not all_events then
        S.status = 'Error reading VENUE track.'
        S.last_result = err
        return
    end

    if #all_events == 0 then
        S.status = 'VENUE track has no text events.'
        S.last_result = "VENUE track doesn't have any text events."
        return
    end

    table.sort(all_events, function(a, b) return a.t < b.t end)

    local track_name_events = {}
    local venue_events      = {}
    local unexpected_events = {}
    for _, ev in ipairs(all_events) do
        if ev.evtype == 3 then
            track_name_events[#track_name_events + 1] = ev
        elseif ev.evtype == 1 and ev.msg:sub(1, 1) == '[' then
            venue_events[#venue_events + 1] = ev
        else
            unexpected_events[#unexpected_events + 1] = ev
        end
    end

    local lines = {}

    ---- Track name validation (type 3) ----
    if #track_name_events == 0 then
        lines[#lines + 1] = 'ERROR: Track name event missing — expected Track Name "VENUE" at 1.1.00.'
    elseif #track_name_events > 1 then
        lines[#lines + 1] = ('ERROR: Track name event duplicated (%d found — expected exactly one at 1.1.00):'):format(#track_name_events)
        for _, ev in ipairs(track_name_events) do
            lines[#lines + 1] = ('  %s  "%s"'):format(FormatTime(ev.t), ev.msg)
        end
    else
        local tn = track_name_events[1]
        if tn.ppq ~= 0 then
            lines[#lines + 1] = ('ERROR: Track name "%s" is not at 1.1.00 — found at %s.'):format(tn.msg, FormatTime(tn.t))
        elseif tn.msg ~= 'VENUE' then
            lines[#lines + 1] = ('ERROR: Track name is "%s" — expected "VENUE".'):format(tn.msg)
        else
            lines[#lines + 1] = 'Track name: "VENUE" at 1.1.00.  OK'
        end
    end
    lines[#lines + 1] = ''

    ---- Unexpected event types ----
    if #unexpected_events == 0 then
        lines[#lines + 1] = 'All non-track-name events are type 1 (Text).  OK'
    else
        lines[#lines + 1] = ('Unexpected event types (%d):'):format(#unexpected_events)
        for _, ev in ipairs(unexpected_events) do
            local type_name = MIDI_META_NAMES[ev.evtype] or ('type ' .. ev.evtype)
            lines[#lines + 1] = ('  %s  [%s]  "%s"'):format(FormatTime(ev.t), type_name, ev.msg)
        end
    end
    lines[#lines + 1] = ''

    ---- Unknown event validation ----
    local unknown_seen = {}
    local unknown = {}
    for _, ev in ipairs(venue_events) do
        if not VENUE_VALID[ev.msg] and not unknown_seen[ev.msg] then
            unknown_seen[ev.msg] = true
            unknown[#unknown + 1] = ev.msg
        end
    end
    if #unknown == 0 then
        lines[#lines + 1] = 'All text events are valid.'
    else
        lines[#lines + 1] = ('Unrecognized events (%d unique):'):format(#unknown)
        for _, msg in ipairs(unknown) do
            lines[#lines + 1] = '  ' .. msg
        end
    end
    lines[#lines + 1] = ''

    ---- Camera event checks ----
    local cam_events = {}
    for _, ev in ipairs(venue_events) do
        if ev.msg:match('^%[coop') or ev.msg:match('^%[directed') then
            cam_events[#cam_events + 1] = ev
        end
    end

    local repeats = {}
    for i = 2, #cam_events do
        if cam_events[i].msg == cam_events[i - 1].msg then
            repeats[#repeats + 1] = cam_events[i]
        end
    end
    if #repeats == 0 then
        lines[#lines + 1] = 'No consecutive repeated camera events.'
    else
        lines[#lines + 1] = ('Consecutive repeated camera events (%d):'):format(#repeats)
        for _, ev in ipairs(repeats) do
            lines[#lines + 1] = ('  %s  %s'):format(FormatTime(ev.t), ev.msg)
        end
    end
    lines[#lines + 1] = ''

    local gap_warnings = {}
    for i, ev in ipairs(cam_events) do
        if ev.msg:match('^%[directed') then
            local next_ev = cam_events[i + 1]
            if next_ev then
                local gap = next_ev.t - ev.t
                if gap < DIRECTED_GAP_MIN then
                    gap_warnings[#gap_warnings + 1] = { ev = ev, gap = gap, next_msg = next_ev.msg }
                end
            end
        end
    end
    if #gap_warnings == 0 then
        lines[#lines + 1] = 'No directed cut spacing issues found.'
    else
        lines[#lines + 1] = ('Directed cuts — next camera event within 2s, double-check (%d):'):format(#gap_warnings)
        for _, w in ipairs(gap_warnings) do
            lines[#lines + 1] = ('  %s  %s  →  next in %.2fs  (%s)'):format(
                FormatTime(w.ev.t), w.ev.msg, w.gap, w.next_msg)
        end
    end
    lines[#lines + 1] = ''

    local primary_gaps, secondary_gaps = BuildCameraGaps(cam_events)

    local function AppendGapStats(label, gaps)
        lines[#lines + 1] = label
        local st = GapStats(gaps)
        if not st then
            lines[#lines + 1] = '  No transitions found.'
        else
            lines[#lines + 1] = ('  Count:    %d'):format(st.count)
            lines[#lines + 1] = ('  Average:  %.2fs'):format(st.avg)
            lines[#lines + 1] = ('  Slowest:  %.2fs  —  %s  (%s)'):format(
                st.slowest.gap, FormatTime(st.slowest.t), st.slowest.from)
            lines[#lines + 1] = ('  Fastest:  %.2fs  —  %s  (%s)'):format(
                st.fastest.gap, FormatTime(st.fastest.t), st.fastest.from)
        end
        lines[#lines + 1] = ''
    end

    AppendGapStats('Camera cut speed  (coop → any):', primary_gaps)
    if #secondary_gaps > 0 then
        AppendGapStats('Camera cut speed  (directed → coop):', secondary_gaps)
    end

    local freq = {}
    local freq_keys = {}
    for _, ev in ipairs(venue_events) do
        if not freq[ev.msg] then
            freq[ev.msg] = 0
            freq_keys[#freq_keys + 1] = ev.msg
        end
        freq[ev.msg] = freq[ev.msg] + 1
    end
    table.sort(freq_keys, function(a, b)
        if freq[a] ~= freq[b] then return freq[a] > freq[b] end
        return a < b
    end)
    lines[#lines + 1] = ('Event usage  (%d total, %d unique):'):format(#venue_events, #freq_keys)
    for _, k in ipairs(freq_keys) do
        lines[#lines + 1] = ('  %3d×  %s'):format(freq[k], k)
    end

    S.status = ('VENUE: %d events, %d unique.'):format(#venue_events, #freq_keys)
    S.last_result = table.concat(lines, '\n')
end
