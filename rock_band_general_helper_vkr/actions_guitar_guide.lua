-- Guitar tab guide actions
----------------------------------------------------------------------
-- Tab Input guide
----------------------------------------------------------------------

-- Tuning table: GUITAR_TAB_OPEN, from lib/reaper_guitar_theory.lua (e B G D
-- A E, standard tuning) -- also the pure fret-shape -> chord-quality
-- classifier AssignGemsForGuide's dyad handling consults (see
-- BuildShapeGemMap in actions_guitar.lua).
local TAB_GAP_BIG = 10  -- seconds; >> TAB_PHRASE_GAP_S -> triggers phrase break in AssignGems

-- Phrase-break threshold for the synthetic timeline GuitarTabGuide builds:
-- events sit 0.01 s apart and a blank tab line inserts TAB_GAP_BIG, so any
-- value strictly between the two behaves identically. Fixed here rather
-- than read from S.mc_gtr_wrap_gap_ms, whose slider lives in the WIP Guitar
-- tab (ui.lua) - phrase breaks in this tab come from blank lines in the
-- input, and a converter setting the Tab Input tab doesn't expose must not
-- be able to change that.
local TAB_PHRASE_GAP_S = 1.0

-- Horizontal: one event per line, 6 space-separated tokens (digit=fret, else=unplayed).
-- Blank line = phrase break. Supports multi-digit frets (10, 12, etc.).
-- Returns { pitches, phrase_idx, tab_str } per event.
function ParseTabHorizontal(text)
    local events     = {}
    local phrase_idx = 1
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed == '' then
            if #events > 0 then phrase_idx = phrase_idx + 1 end
        else
            local pitches = {}
            local si = 0
            for tok in trimmed:gmatch('%S+') do
                si = si + 1
                if si > 6 then break end
                local f = tonumber(tok)
                if f then pitches[#pitches + 1] = GUITAR_TAB_OPEN[si] + f end
            end
            if #pitches > 0 then
                events[#events + 1] = { pitches = pitches, phrase_idx = phrase_idx, tab_str = trimmed }
            end
        end
    end
    return events
end

-- Vertical: 6 rows of space-separated tokens (digit=fret, else=unplayed); columns = events.
-- All-non-digit column = phrase break. Supports multi-digit frets.
-- Returns { pitches, phrase_idx } per event.
function ParseTabVertical(text)
    local rows = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed ~= '' and #rows < 6 then
            local toks = {}
            for tok in trimmed:gmatch('%S+') do toks[#toks + 1] = tok end
            rows[#rows + 1] = toks
        end
    end
    local n_cols = 0
    for i = 1, #rows do n_cols = math.max(n_cols, #rows[i]) end
    local events     = {}
    local phrase_idx = 1
    for col = 1, n_cols do
        local pitches = {}
        for si = 1, #rows do
            local f = tonumber((rows[si] or {})[col])
            if f then pitches[#pitches + 1] = GUITAR_TAB_OPEN[si] + f end
        end
        if #pitches > 0 then
            events[#events + 1] = { pitches = pitches, phrase_idx = phrase_idx }
        else
            if #events > 0 then phrase_idx = phrase_idx + 1 end
        end
    end
    return events
end

-- Called from ui.lua "Add note" button in vertical mode.
-- 6 plain lines of space-separated tokens. Pads rows to equal length,
-- appends a new all-dash column when add_column=true.
function ReformatVerticalTab(text, add_column)
    local rows = {}
    for i = 1, 6 do rows[i] = {} end
    local row_n = 0
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed ~= '' then
            row_n = row_n + 1
            if row_n <= 6 then
                for tok in trimmed:gmatch('%S+') do rows[row_n][#rows[row_n] + 1] = tok end
            end
        end
    end
    local n = 0
    for i = 1, 6 do n = math.max(n, #rows[i]) end
    for i = 1, 6 do
        while #rows[i] < n do rows[i][#rows[i] + 1] = '-' end
        if add_column then rows[i][#rows[i] + 1] = '-' end
    end
    local lines = {}
    for i = 1, 6 do lines[i] = table.concat(rows[i], ' ') end
    return table.concat(lines, '\n')
end

-- Assign gems for the tab guide: global chord-shape ranking by pitch, pool wrap only on overflow.
-- Distinct shapes across ALL events are sorted by pitch and assigned combos from the pool once.
-- Gaps > wrap_gap_s are annotated as phrase boundaries in the report but do not reset assignments.
-- Called only from GuitarTabGuide (ordered mode). Uses shared POOLS / POOLS2_NO14 at file scope.
--
-- Chords are NOT compressed here (max_chord=nil to BuildShapeGemMap). The
-- Tab Input tab is a reference guide that writes nothing to the project, so
-- there is no chart to fit and nothing to reduce; GuitarSuggestRBMapping
-- already derives the gem count from distinct PITCH CLASSES on the full
-- shape (2 for any dyad width, 3 for a real triad). That's exactly how the
-- Music Theory helper's Shape Search reaches its answer, and the two tools
-- must agree - both exist to say how a given chord maps to RB.
-- Truncating by array index beforehand made them disagree: it could drop a
-- chord's root and leave a doubled note behind, turning e.g. an open D
-- major into a bare sixth dyad, or a G5 into three octaves of G with no
-- suggestable width at all.
-- allow_14=true for the same reason: an octave dyad should report 1-4, as
-- Shape Search does. Max chord / Allow 1-4 belong to the WIP Guitar tab's
-- converter and are not exposed by this tab (see _DrawTabInputBody in
-- ui_midi.lua) - they must not reach it.
local function AssignGemsForGuide(events, wrap_gap_s)
    if #events == 0 then return {} end

    local function shape_key(sorted_pitches)
        local t = {}
        for _, p in ipairs(sorted_pitches) do t[#t + 1] = p end
        return table.concat(t, ',')
    end

    -- Global shape->gem map across all events - see BuildShapeGemMap's own
    -- doc comment (actions_guitar.lua) for the dyad chord-quality logic.
    local all_shapes, shape_gems, shared = BuildShapeGemMap(events, nil, true)

    -- Split into phrases for report annotations only
    local phrases = {}
    local cur = { events[1] }
    for i = 2, #events do
        if (events[i].s - events[i-1].e) > wrap_gap_s then
            phrases[#phrases + 1] = cur
            cur = { events[i] }
        else
            cur[#cur + 1] = events[i]
        end
    end
    phrases[#phrases + 1] = cur

    local assignments = {}
    local prev_end    = -1

    for _, phrase_evs in ipairs(phrases) do
        -- Build header for this phrase using globally-assigned gems
        local seen       = {}
        local seen_order = {}
        for _, ev in ipairs(phrase_evs) do
            local key = shape_key(SortedChordPitches(ev.pitches))
            if not seen[key] then
                seen[key] = true
                seen_order[#seen_order + 1] = key
            end
        end
        table.sort(seen_order, function(a, b)
            local sa, sb = all_shapes[a], all_shapes[b]
            if sa.max ~= sb.max then return sa.max < sb.max end
            return sa.avg < sb.avg
        end)
        local header_parts = {}
        for _, key in ipairs(seen_order) do
            local pitch_parts = {}
            for _, p in ipairs(all_shapes[key].pitches) do
                pitch_parts[#pitch_parts + 1] = PitchName(p)
            end
            header_parts[#header_parts + 1] =
                table.concat(pitch_parts, '+') .. '\xe2\x86\x92' .. GemLabel(shape_gems[key])
        end

        local gap_s = prev_end >= 0 and (phrase_evs[1].s - prev_end) or 0
        local meta_reason
        if prev_end >= 0 and gap_s > wrap_gap_s then
            meta_reason = string.format('Phrase  gap=%.0f ms  ', gap_s * 1000)
                .. table.concat(header_parts, '  ')
        else
            meta_reason = 'Phrase start  ' .. table.concat(header_parts, '  ')
        end
        assignments[#assignments + 1] = { s = phrase_evs[1].s, reason = meta_reason, is_meta = true }

        for _, ev in ipairs(phrase_evs) do
            local pitches = SortedChordPitches(ev.pitches)
            local key  = shape_key(pitches)
            local src  = shape_gems[key]
            local gems = {}
            for _, g in ipairs(src) do gems[#gems + 1] = g end
            local reason = string.format('%s  %s \xe2\x86\x92 %s',
                ChordTypeName(gems), PitchLabel(ev.pitches), GemLabel(gems))
            reason = reason .. ChordQualityLabel(pitches)
            if shared[key] then reason = reason .. '  (*Wrap)' end
            assignments[#assignments + 1] = {
                s = ev.s, e = ev.e, gems = gems, reason = reason, is_meta = false,
                tab_str = ev.tab_str,
            }
            prev_end = ev.e
        end
    end

    return assignments
end

function GuitarTabGuide()
    local text = S.mc_gtr_tab_format == 0 and S.mc_gtr_tab_input_h or S.mc_gtr_tab_input_v
    if not text or text:match('^%s*$') then
        S.status = 'Tab input is empty'
        return
    end
    local raw_events = S.mc_gtr_tab_format == 0 and ParseTabHorizontal(text) or ParseTabVertical(text)
    -- Convert phrase_idx to time-based events for AssignGemsForGuide
    local events = {}
    if #raw_events > 0 then
        local t = 0
        local prev_phrase = raw_events[1].phrase_idx
        for _, rev in ipairs(raw_events) do
            if rev.phrase_idx ~= prev_phrase then
                t = t + TAB_GAP_BIG
                prev_phrase = rev.phrase_idx
            end
            events[#events + 1] = { s = t, e = t + 0.005, pitches = rev.pitches, tab_str = rev.tab_str }
            t = t + 0.01
        end
    end
    if #events == 0 then
        S.status = 'No valid notes found in tab input'
        return
    end
    local assignments = AssignGemsForGuide(events, TAB_PHRASE_GAP_S)
    local lines = {}
    for _, a in ipairs(assignments) do
        if a.is_meta then
            lines[#lines + 1] = ''
            lines[#lines + 1] = '  *** ' .. a.reason
        else
            local first = a.tab_str or GemLabel(a.gems)
            lines[#lines + 1] = string.format('  %-10s  %s', first, a.reason)
        end
    end
    S.last_result = table.concat(lines, '\n')
    S.status      = string.format('Tab guide: %d note(s)', #events)
end
