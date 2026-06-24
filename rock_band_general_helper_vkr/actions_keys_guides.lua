-- Pro Keys and Vocal tab guide actions
----------------------------------------------------------------------
-- Pro Keys Tab Input guide
----------------------------------------------------------------------

-- PK_MIN, PK_MAX, PK_RANGES, PK_PREF_LABEL defined at module level above.

-- Format a single event's pitches for display.
-- Single note: "C3". Chord: "[A2+C3+E3]".
local function PkEventLabel(pitches)
    if #pitches == 1 then return PitchName(pitches[1]) end
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = PitchName(p) end
    return '[' .. table.concat(parts, '+') .. ']'
end

local function ParseTabToRaws(status_prefix)
    local text = S.mc_gtr_tab_format == 0 and S.mc_gtr_tab_input_h or S.mc_gtr_tab_input_v
    if not text or text:match('^%s*$') then
        S.status = status_prefix .. ': no input.'
        S.last_result = 'Enter 6-string tab (e B G D A E, use - for unplayed).\n' ..
                        'Horizontal: one event per line.  Vertical: 6 rows, columns = events.'
        return nil
    end
    local raw_events = S.mc_gtr_tab_format == 0 and ParseTabHorizontal(text) or ParseTabVertical(text)
    if #raw_events == 0 then
        S.status = status_prefix .. ': no notes found.'
        S.last_result = 'No notes found. Use digits for played strings, dashes for unplayed.\n' ..
                        'Example:  5 6 5 - - -'
        return nil
    end
    local events = {}
    for _, rev in ipairs(raw_events) do
        local raws = {}
        for _, p in ipairs(rev.pitches) do raws[#raws + 1] = p end
        table.sort(raws)
        events[#events + 1] = { raws = raws, phrase_idx = rev.phrase_idx }
    end
    return events
end

function ProKeysTabGuide()
    local events = ParseTabToRaws('Pro Keys guide')
    if not events then return end

    -- Step 3: find best octave shift (counts individual pitches out of range)
    local SHIFTS = { -48, -36, -24, -12, 0, 12, 24 }
    local best_shift       = 0
    local best_out_count   = math.huge
    local best_median_dist = math.huge

    local function median_dist(shift)
        local pitches = {}
        for _, ev in ipairs(events) do
            for _, raw in ipairs(ev.raws) do pitches[#pitches + 1] = raw + shift end
        end
        table.sort(pitches)
        local mid = pitches[math.ceil(#pitches / 2)]
        return math.abs(mid - 60)  -- 60 = C3 = midpoint of 48-72
    end

    for _, sh in ipairs(SHIFTS) do
        local out = 0
        for _, ev in ipairs(events) do
            for _, raw in ipairs(ev.raws) do
                local p = raw + sh
                if p < PK_MIN or p > PK_MAX then out = out + 1 end
            end
        end
        local md = median_dist(sh)
        if out < best_out_count or (out == best_out_count and md < best_median_dist) then
            best_shift       = sh
            best_out_count   = out
            best_median_dist = md
        end
    end

    -- Step 4: apply shift; compute per-event pitches (sorted)
    local total_notes = 0
    for _, ev in ipairs(events) do
        ev.pitches = {}
        for _, raw in ipairs(ev.raws) do ev.pitches[#ev.pitches + 1] = raw + best_shift end
        table.sort(ev.pitches)
        total_notes = total_notes + #ev.pitches
    end

    -- Steps 5-7: branch on animation vs. standard mode

    -- Shared: build event labels and note span
    local shift_label
    if best_shift == 0 then
        shift_label = '(no shift)'
    else
        local oct = best_shift / 12
        shift_label = ('%+d oct (%+d semitones)'):format(oct, best_shift)
    end

    local ev_labels = {}
    for _, ev in ipairs(events) do ev_labels[#ev_labels + 1] = PkEventLabel(ev.pitches) end

    local min_p, max_p = math.huge, -math.huge
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            if p < min_p then min_p = p end
            if p > max_p then max_p = p end
        end
    end

    -- Chord span warnings (> 12 semitones = exceeds octave rule); shared by both modes
    local span_warns = {}
    for i, ev in ipairs(events) do
        if #ev.pitches > 1 then
            local span = ev.pitches[#ev.pitches] - ev.pitches[1]
            if span > 12 then
                span_warns[#span_warns + 1] = ('  Event %d: %s spans %d semitones (max 12 for Expert)'):format(
                    i, PkEventLabel(ev.pitches), span)
            end
        end
    end

    local n_phrases = events[#events].phrase_idx
    local phrase_str = n_phrases == 1 and '1 phrase' or (n_phrases .. ' phrases')
    local note_str   = total_notes == #events
        and ('%d events'):format(#events)
        or  ('%d events, %d notes total'):format(#events, total_notes)

    local lines = {}
    lines[#lines + 1] = ('Events after shift %s:'):format(shift_label)
    lines[#lines + 1] = table.concat(ev_labels, '  ')
    lines[#lines + 1] = ('(%s, %s)'):format(note_str, phrase_str)
    lines[#lines + 1] = ''

    if S.pk_tab_animation then
        -- Animation mode: report against full C2-C4 range, skip lane window scoring
        lines[#lines + 1] = 'Animation mode \xe2\x80\x94 full C2\xe2\x80\x93C4 range (no lane window).'
        lines[#lines + 1] = ''
        if best_out_count == 0 then
            lines[#lines + 1] = 'All notes fit within C2\xe2\x80\x93C4.'
        else
            lines[#lines + 1] = (best_out_count .. ' note(s) fall outside C2\xe2\x80\x93C4 even after best shift.')
            lines[#lines + 1] = 'Consider re-voicing those notes.'
            -- List out-of-range events
            lines[#lines + 1] = ''
            for i, ev in ipairs(events) do
                local bad = {}
                for _, p in ipairs(ev.pitches) do
                    if p < PK_MIN or p > PK_MAX then
                        local dir = p < PK_MIN and ('below ' .. PitchName(PK_MIN))
                                                or ('above ' .. PitchName(PK_MAX))
                        bad[#bad + 1] = PitchName(p) .. ' ' .. dir
                    end
                end
                if #bad > 0 then
                    lines[#lines + 1] = ('  Event %d (phrase %d): %s \xe2\x80\x94 %s'):format(
                        i, ev.phrase_idx, PkEventLabel(ev.pitches), table.concat(bad, '; '))
                end
            end
        end

        if #span_warns > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = 'Chord span warnings (Expert max: 12 semitones):'
            for _, s in ipairs(span_warns) do lines[#lines + 1] = s end
        end

        local status_fit = best_out_count == 0 and 'all fit C2\xe2\x80\x93C4' or
                           (best_out_count .. ' out of C2\xe2\x80\x93C4')
        S.status = ('Pro Keys guide (animation): %s \xe2\x80\x94 %s'):format(shift_label, status_fit)
    else
        -- Standard mode: score lane windows and suggest best range

        -- Step 5: score lane ranges - an event is "in" only if ALL its pitches fit
        local best_range = nil
        local best_score = -math.huge
        for _, rng in ipairs(PK_RANGES) do
            local in_count = 0
            local rng_min_p, rng_max_p = math.huge, -math.huge
            for _, ev in ipairs(events) do
                local all_in = true
                for _, p in ipairs(ev.pitches) do
                    if p < rng.lo or p > rng.hi then all_in = false end
                    if p < rng_min_p then rng_min_p = p end
                    if p > rng_max_p then rng_max_p = p end
                end
                if all_in then in_count = in_count + 1 end
            end
            local note_center  = in_count > 0 and (rng_min_p + rng_max_p) / 2 or 0
            local range_center = (rng.lo + rng.hi) / 2
            local score = in_count * 10000
                        - math.abs(note_center - range_center) * 10
                        - rng.pref
            if score > best_score then
                best_score = score
                best_range = rng
            end
        end

        -- Step 6: collect out-of-range events for the suggested lane range
        local oor      = {}
        local in_count = 0
        for i, ev in ipairs(events) do
            local bad = {}
            for _, p in ipairs(ev.pitches) do
                if p < best_range.lo or p > best_range.hi then
                    local dir = p < best_range.lo
                        and 'below ' .. PitchName(best_range.lo)
                        or  'above ' .. PitchName(best_range.hi)
                    bad[#bad + 1] = PitchName(p) .. ' ' .. dir
                end
            end
            if #bad > 0 then
                oor[#oor + 1] = ('  Event %d (phrase %d): %s \xe2\x80\x94 %s'):format(
                    i, ev.phrase_idx, PkEventLabel(ev.pitches), table.concat(bad, '; '))
            else
                in_count = in_count + 1
            end
        end

        -- Step 7: build lane-range report lines
        local note_center  = (min_p + max_p) / 2
        local range_center = (best_range.lo + best_range.hi) / 2
        local centre_label = math.abs(note_center - range_center) <= 2 and ', best centred' or ''

        if #oor == 0 then
            lines[#lines + 1] = ('Suggested range: %s  %s  (all fit%s)'):format(
                best_range.name, PK_PREF_LABEL[best_range.pref], centre_label)
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('All %d events fit within %s.'):format(#events, best_range.name)
        else
            lines[#lines + 1] = ('Suggested range: %s  %s  (%d/%d events fit%s)'):format(
                best_range.name, PK_PREF_LABEL[best_range.pref], in_count, #events, centre_label)
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('Out of range for %s:'):format(best_range.name)
            for _, s in ipairs(oor) do lines[#lines + 1] = s end
            lines[#lines + 1] = ''
            if best_out_count > 0 then
                lines[#lines + 1] = 'Note: no octave shift fits all notes in C2\xe2\x80\x93C4.'
                lines[#lines + 1] = 'Consider splitting the passage or re-voicing out-of-range notes.'
            else
                lines[#lines + 1] = 'Consider shifting 1 oct or splitting at a phrase boundary.'
            end
        end

        if #span_warns > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = 'Chord span warnings (Expert max: 12 semitones):'
            for _, s in ipairs(span_warns) do lines[#lines + 1] = s end
        end

        local status_in = #oor == 0 and 'all fit' or (in_count .. '/' .. #events .. ' fit')
        S.status = ('Pro Keys guide: %s \xe2\x80\x94 suggested %s (%s)'):format(
            shift_label, best_range.name, status_in)
    end

    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Vocal Tab Input guide
----------------------------------------------------------------------

local VOC_MIN = 36   -- C1
local VOC_MAX = 84   -- C5

function VocalTabGuide()
    local events = ParseTabToRaws('Vocal guide')
    if not events then return end

    -- Find best octave shift (minimize notes outside C1-C5)
    local SHIFTS = { -48, -36, -24, -12, 0, 12, 24 }
    local best_shift       = 0
    local best_out_count   = math.huge
    local best_median_dist = math.huge

    local function median_dist_voc(shift)
        local pitches = {}
        for _, ev in ipairs(events) do
            for _, raw in ipairs(ev.raws) do pitches[#pitches + 1] = raw + shift end
        end
        table.sort(pitches)
        local mid = pitches[math.ceil(#pitches / 2)]
        return math.abs(mid - 60)  -- 60 = C3 = midpoint of C1-C5 range
    end

    for _, sh in ipairs(SHIFTS) do
        local out = 0
        for _, ev in ipairs(events) do
            for _, raw in ipairs(ev.raws) do
                local p = raw + sh
                if p < VOC_MIN or p > VOC_MAX then out = out + 1 end
            end
        end
        local md = median_dist_voc(sh)
        if out < best_out_count or (out == best_out_count and md < best_median_dist) then
            best_shift       = sh
            best_out_count   = out
            best_median_dist = md
        end
    end

    -- Apply shift
    local total_notes = 0
    for _, ev in ipairs(events) do
        ev.pitches = {}
        for _, raw in ipairs(ev.raws) do ev.pitches[#ev.pitches + 1] = raw + best_shift end
        table.sort(ev.pitches)
        total_notes = total_notes + #ev.pitches
    end

    local shift_label
    if best_shift == 0 then
        shift_label = '(no shift)'
    else
        local oct = best_shift / 12
        shift_label = ('%+d oct (%+d semitones)'):format(oct, best_shift)
    end

    local ev_labels = {}
    for _, ev in ipairs(events) do ev_labels[#ev_labels + 1] = PkEventLabel(ev.pitches) end

    local span_warns = {}
    for i, ev in ipairs(events) do
        if #ev.pitches > 1 then
            local span = ev.pitches[#ev.pitches] - ev.pitches[1]
            if span > 12 then
                span_warns[#span_warns + 1] = ('  Event %d: %s spans %d semitones (max 12 for Expert)'):format(
                    i, PkEventLabel(ev.pitches), span)
            end
        end
    end

    local n_phrases = events[#events].phrase_idx
    local phrase_str = n_phrases == 1 and '1 phrase' or (n_phrases .. ' phrases')
    local note_str   = total_notes == #events
        and ('%d events'):format(#events)
        or  ('%d events, %d notes total'):format(#events, total_notes)

    local lines = {}
    lines[#lines + 1] = ('Events after shift %s:'):format(shift_label)
    lines[#lines + 1] = table.concat(ev_labels, '  ')
    lines[#lines + 1] = ('(%s, %s)'):format(note_str, phrase_str)
    lines[#lines + 1] = ''

    if best_out_count == 0 then
        lines[#lines + 1] = 'All notes fit within C1\xe2\x80\x93C5.'
    else
        lines[#lines + 1] = (best_out_count .. ' note(s) fall outside C1\xe2\x80\x93C5 even after best shift.')
        lines[#lines + 1] = 'Consider re-voicing those notes or splitting the passage.'
        lines[#lines + 1] = ''
        for i, ev in ipairs(events) do
            local bad = {}
            for _, p in ipairs(ev.pitches) do
                if p < VOC_MIN or p > VOC_MAX then
                    local dir = p < VOC_MIN and ('below ' .. PitchName(VOC_MIN))
                                             or ('above ' .. PitchName(VOC_MAX))
                    bad[#bad + 1] = PitchName(p) .. ' ' .. dir
                end
            end
            if #bad > 0 then
                lines[#lines + 1] = ('  Event %d (phrase %d): %s \xe2\x80\x94 %s'):format(
                    i, ev.phrase_idx, PkEventLabel(ev.pitches), table.concat(bad, '; '))
            end
        end
    end

    if #span_warns > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Chord span warnings (Expert max: 12 semitones):'
        for _, s in ipairs(span_warns) do lines[#lines + 1] = s end
    end

    local status_fit = best_out_count == 0 and 'all fit C1\xe2\x80\x93C5' or
                       (best_out_count .. ' out of C1\xe2\x80\x93C5')
    S.status = ('Vocal guide: %s \xe2\x80\x94 %s'):format(shift_label, status_fit)
    S.last_result = table.concat(lines, '\n')
end
