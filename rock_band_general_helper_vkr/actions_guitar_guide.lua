-- Guitar tab guide actions
----------------------------------------------------------------------
-- Tab Input guide
----------------------------------------------------------------------

local TAB_OPEN    = { 64, 59, 55, 50, 45, 40 }  -- e B G D A E (standard tuning)
local TAB_GAP_BIG = 10  -- seconds; >> wrap_gap_s â†’ triggers phrase break in AssignGems

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
                if f then pitches[#pitches + 1] = TAB_OPEN[si] + f end
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
            if f then pitches[#pitches + 1] = TAB_OPEN[si] + f end
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
local function AssignGemsForGuide(events, wrap_gap_s, max_chord)
    if #events == 0 then return {} end

    local function shape_key(sorted_pitches)
        local t = {}
        for _, p in ipairs(sorted_pitches) do t[#t + 1] = p end
        return table.concat(t, ',')
    end

    -- Build global shapeâ†’gem map across all events
    local all_shapes  = {}
    local size_orders = {}

    for _, ev in ipairs(events) do
        local pitches = CompressChord(ev.pitches, max_chord)
        table.sort(pitches)
        local sz  = #pitches
        local key = shape_key(pitches)
        if not all_shapes[key] then
            local sum = 0
            for _, p in ipairs(pitches) do sum = sum + p end
            all_shapes[key] = { avg = sum / sz, max = pitches[sz], sz = sz, pitches = pitches }
            if not size_orders[sz] then size_orders[sz] = {} end
            size_orders[sz][#size_orders[sz] + 1] = key
        end
    end

    local pool2      = S.mc_gtr_allow_14 and POOLS[2] or POOLS2_NO14
    local shape_gems = {}

    local sizes = {}
    for sz in pairs(size_orders) do sizes[#sizes + 1] = sz end
    table.sort(sizes)

    for _, sz in ipairs(sizes) do
        local order = size_orders[sz]
        table.sort(order, function(a, b)
            local sa, sb = all_shapes[a], all_shapes[b]
            if sa.max ~= sb.max then return sa.max < sb.max end
            return sa.avg < sb.avg
        end)
        local N = #order
        for rank, key in ipairs(order) do
            local combo
            if sz == 1 then
                local gem = N == 1 and 0 or math.min(4, math.floor((rank - 1) * 4 / (N - 1) + 0.5))
                combo = { gem }
            else
                local pool = (sz == 2) and pool2 or (POOLS[math.min(sz, 3)] or POOLS[1])
                combo = pool[((rank - 1) % #pool) + 1]
            end
            shape_gems[key] = combo
        end
    end

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
            local pitches = CompressChord(ev.pitches, max_chord)
            table.sort(pitches)
            local key = shape_key(pitches)
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
            local pitches = CompressChord(ev.pitches, max_chord)
            table.sort(pitches)
            local key  = shape_key(pitches)
            local src  = shape_gems[key]
            local gems = {}
            for _, g in ipairs(src) do gems[#gems + 1] = g end
            local narrowed_14 = false
            if not S.mc_gtr_allow_14 and #gems == 2 and gems[2] - gems[1] >= 3 then
                gems        = { gems[1], gems[1] + 2 }
                narrowed_14 = true
            end
            local n_orig = #ev.pitches
            local reason = string.format('%s  %s \xe2\x86\x92 %s',
                ChordTypeName(gems), PitchLabel(ev.pitches), GemLabel(gems))
            if n_orig > #pitches then
                reason = reason .. string.format('  (compressed %d\xe2\x86\x92%d)', n_orig, #pitches)
            end
            if narrowed_14 then
                reason = reason .. '  (1-4 \xe2\x86\x92 1-3: narrowed per setting)'
            end
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
    local assignments
    if not S.mc_gtr_tab_ordered then
        -- Palette mode: bucket all distinct pitches across gems 0-4.
        -- With N > 5 pitches, multiple pitches intentionally share the same gem.
        local seen, sorted_pitches = {}, {}
        for _, ev in ipairs(events) do
            for _, p in ipairs(ev.pitches) do
                if not seen[p] then seen[p] = true; sorted_pitches[#sorted_pitches + 1] = p end
            end
        end
        table.sort(sorted_pitches)
        local N = #sorted_pitches
        local header_parts = {}
        for i, p in ipairs(sorted_pitches) do
            local gem = N == 1 and 0 or math.min(4, math.floor((i - 1) * 4 / (N - 1) + 0.5))
            header_parts[#header_parts + 1] = PitchName(p) .. '\xe2\x86\x92' .. GEM_LETTERS[gem]
        end
        assignments = { {
            s = 0,
            reason = 'Palette (' .. N .. ' pitch' .. (N == 1 and '' or 'es') .. ')  '
                     .. table.concat(header_parts, '  '),
            is_meta = true,
        } }
        for i, p in ipairs(sorted_pitches) do
            local gem  = N == 1 and 0 or math.min(4, math.floor((i - 1) * 4 / (N - 1) + 0.5))
            local gems = {gem}
            assignments[#assignments + 1] = {
                s = (i - 1) * 0.01, e = (i - 1) * 0.01 + 0.005,
                gems = gems,
                reason = string.format('single  %s \xe2\x86\x92 %s', PitchName(p), GemLabel(gems)),
                is_meta = false,
                tab_str = PitchName(p),
            }
        end
    else
        assignments = AssignGemsForGuide(events, S.mc_gtr_wrap_gap_ms / 1000, S.mc_gtr_max_chord)
    end
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
