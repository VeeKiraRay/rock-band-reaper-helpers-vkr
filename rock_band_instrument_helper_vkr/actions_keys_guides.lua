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

local TAB_SPAN_MAX = 12  -- widest chord Expert allows, in semitones (one octave)

-- The notes of one event outside lo..hi, each as "C1 below C2" / "D5 above C5".
local function TabOutOfRange(pitches, lo, hi)
    local bad = {}
    for _, p in ipairs(pitches) do
        if p < lo then
            bad[#bad + 1] = PitchName(p) .. ' below ' .. PitchName(lo)
        elseif p > hi then
            bad[#bad + 1] = PitchName(p) .. ' above ' .. PitchName(hi)
        end
    end
    return bad
end

-- "(no shift)" or "-1 oct (-12 semitones)".
local function TabShiftLabel(shift)
    if shift == 0 then return '(no shift)' end
    return ('%+d oct (%+d semitones)'):format(shift / 12, shift)
end

-- First line of both guides: the octave shift and how much was entered.
local function TabGuideHeader(shift, events, total_notes)
    local n_phrases  = events[#events].phrase_idx
    local phrase_str = n_phrases == 1 and '1 phrase' or (n_phrases .. ' phrases')
    local event_str  = #events == 1 and '1 event' or (#events .. ' events')
    local note_str   = total_notes == #events
        and event_str
        or  ('%s, %d notes total'):format(event_str, total_notes)
    return ('Octave shift: %s  (%s, %s)'):format(TabShiftLabel(shift), note_str, phrase_str)
end

-- One row per event, laid out like the guitar guide's: the tab line as typed
-- (or "#n" for vertical input, which has no line per event), the pitches after
-- the shift, and anything wrong with it - notes outside lo..hi, or a chord
-- wider than an octave. Each phrase starts with a "*** Phrase n" line.
-- events: sorted pitches, phrase_idx and (optional) tab_str per event.
-- Returns the lines; the first one is blank.
function TabGuideEventRows(events, lo, hi)
    local lines  = {}
    local phrase = nil
    for i, ev in ipairs(events) do
        if ev.phrase_idx ~= phrase then
            phrase = ev.phrase_idx
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('  *** Phrase %d'):format(phrase)
        end
        local flags = TabOutOfRange(ev.pitches, lo, hi)
        local span  = ev.pitches[#ev.pitches] - ev.pitches[1]
        if span > TAB_SPAN_MAX then
            flags[#flags + 1] = ('spans %d semitones (Expert max %d)'):format(span, TAB_SPAN_MAX)
        end
        local row = ('  %-10s  %s'):format(ev.tab_str or ('#' .. i), PkEventLabel(ev.pitches))
        if #flags > 0 then row = row .. '  <- ' .. table.concat(flags, '; ') end
        lines[#lines + 1] = row
    end
    return lines
end

-- Closing line when any chord is wider than Expert allows (each is marked on its row).
local function AppendSpanSummary(lines, events)
    local n = 0
    for _, ev in ipairs(events) do
        if ev.pitches[#ev.pitches] - ev.pitches[1] > TAB_SPAN_MAX then n = n + 1 end
    end
    if n > 0 then
        lines[#lines + 1] = ('%d chord(s) span more than %d semitones (Expert max) - marked above.'):format(
            n, TAB_SPAN_MAX)
    end
end

local function ParseTabToRaws(status_prefix)
    local text = S.mc_gtr_tab_format == 0 and S.mc_gtr_tab_input_h or S.mc_gtr_tab_input_v
    if not text or text:match('^%s*$') then
        S.status = status_prefix .. ': no input.'
        S.last_result = 'Enter 6-string tab (use - for unplayed).\n' ..
                        'Horizontal: one event per line, low to high (E A D G B e).\n' ..
                        'Vertical: 6 rows top-down (e B G D A E), columns = events.'
        return nil
    end
    local raw_events = S.mc_gtr_tab_format == 0 and ParseTabHorizontal(text) or ParseTabVertical(text)
    if #raw_events == 0 then
        S.status = status_prefix .. ': no notes found.'
        S.last_result = 'No notes found. Use digits for played strings, dashes for unplayed.\n' ..
                        'Example:  - - - 5 6 5'
        return nil
    end
    local events = {}
    for _, rev in ipairs(raw_events) do
        local raws = {}
        for _, p in ipairs(rev.pitches) do raws[#raws + 1] = p end
        table.sort(raws)
        events[#events + 1] = { raws = raws, phrase_idx = rev.phrase_idx, tab_str = rev.tab_str }
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

    local shift_label = TabShiftLabel(best_shift)

    local min_p, max_p = math.huge, -math.huge
    for _, ev in ipairs(events) do
        for _, p in ipairs(ev.pitches) do
            if p < min_p then min_p = p end
            if p > max_p then max_p = p end
        end
    end

    local lines = { TabGuideHeader(best_shift, events, total_notes) }

    if S.pk_tab_animation then
        -- Animation mode: report against full C2-C4 range, skip lane window scoring
        lines[#lines + 1] = 'Animation mode - full C2-C4 range (no lane window).'
        for _, l in ipairs(TabGuideEventRows(events, PK_MIN, PK_MAX)) do lines[#lines + 1] = l end
        lines[#lines + 1] = ''
        if best_out_count == 0 then
            lines[#lines + 1] = 'All notes fit within C2-C4.'
        else
            lines[#lines + 1] = (best_out_count .. ' note(s) fall outside C2-C4 even after best shift - marked above.')
            lines[#lines + 1] = 'Consider re-voicing those notes.'
        end
        AppendSpanSummary(lines, events)

        local status_fit = best_out_count == 0 and 'all fit C2-C4' or
                           (best_out_count .. ' out of C2-C4')
        S.status = ('Pro Keys guide (animation): %s - %s'):format(shift_label, status_fit)
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

        -- Step 6: count the events that fit the suggested lane range
        local in_count = 0
        for _, ev in ipairs(events) do
            if #TabOutOfRange(ev.pitches, best_range.lo, best_range.hi) == 0 then
                in_count = in_count + 1
            end
        end
        local all_fit = in_count == #events

        -- Step 7: suggested range, one row per event (out-of-range notes marked), advice
        local note_center  = (min_p + max_p) / 2
        local range_center = (best_range.lo + best_range.hi) / 2
        local centre_label = math.abs(note_center - range_center) <= 2 and ', best centred' or ''
        local fit_label    = all_fit and 'all fit'
                             or ('%d/%d events fit'):format(in_count, #events)

        lines[#lines + 1] = ('Suggested range: %s  %s  (%s%s)'):format(
            best_range.name, PK_PREF_LABEL[best_range.pref], fit_label, centre_label)
        for _, l in ipairs(TabGuideEventRows(events, best_range.lo, best_range.hi)) do
            lines[#lines + 1] = l
        end
        lines[#lines + 1] = ''

        if all_fit then
            lines[#lines + 1] = ('All %d events fit within %s.'):format(#events, best_range.name)
        else
            lines[#lines + 1] = ('%d event(s) out of range for %s - marked above.'):format(
                #events - in_count, best_range.name)
            if best_out_count > 0 then
                lines[#lines + 1] = 'Note: no octave shift fits all notes in C2-C4.'
                lines[#lines + 1] = 'Consider splitting the passage or re-voicing out-of-range notes.'
            else
                lines[#lines + 1] = 'Consider shifting 1 oct or splitting at a phrase boundary.'
            end
        end
        AppendSpanSummary(lines, events)

        local status_in = all_fit and 'all fit' or (in_count .. '/' .. #events .. ' fit')
        S.status = ('Pro Keys guide: %s - suggested %s (%s)'):format(
            shift_label, best_range.name, status_in)
    end

    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Vocal Tab Input guide
----------------------------------------------------------------------

local VOC_MIN = 36   -- C1
local VOC_MAX = 84   -- C5

-- Octave shift for the vocal guide: the one leaving the fewest notes outside
-- C1-C5; on a tie, the smallest shift (no shift first, then down before up).
-- Unlike Pro Keys, which centres the passage on C3 because its lanes are a
-- range window, a vocal note's pitch is what the singer sings - a passage that
-- already fits must not move.
-- events: { { raws = { pitch, ... } }, ... }. Returns shift, out_count.
function VocalTabBestShift(events)
    local SHIFTS = { 0, -12, 12, -24, 24, -36, -48 }  -- smallest first: ties keep the earlier
    local best_shift, best_out = 0, math.huge
    for _, sh in ipairs(SHIFTS) do
        local out = 0
        for _, ev in ipairs(events) do
            for _, raw in ipairs(ev.raws) do
                local p = raw + sh
                if p < VOC_MIN or p > VOC_MAX then out = out + 1 end
            end
        end
        if out < best_out then best_shift, best_out = sh, out end
    end
    return best_shift, best_out
end

function VocalTabGuide()
    local events = ParseTabToRaws('Vocal guide')
    if not events then return end

    local best_shift, best_out_count = VocalTabBestShift(events)

    -- Apply shift
    local total_notes = 0
    for _, ev in ipairs(events) do
        ev.pitches = {}
        for _, raw in ipairs(ev.raws) do ev.pitches[#ev.pitches + 1] = raw + best_shift end
        table.sort(ev.pitches)
        total_notes = total_notes + #ev.pitches
    end

    local lines = { TabGuideHeader(best_shift, events, total_notes) }
    for _, l in ipairs(TabGuideEventRows(events, VOC_MIN, VOC_MAX)) do lines[#lines + 1] = l end
    lines[#lines + 1] = ''

    if best_out_count == 0 then
        lines[#lines + 1] = 'All notes fit within C1-C5.'
    else
        lines[#lines + 1] = (best_out_count .. ' note(s) fall outside C1-C5 even after best shift - marked above.')
        lines[#lines + 1] = 'Consider re-voicing those notes or splitting the passage.'
    end
    AppendSpanSummary(lines, events)

    local status_fit = best_out_count == 0 and 'all fit C1-C5' or
                       (best_out_count .. ' out of C1-C5')
    S.status = ('Vocal guide: %s - %s'):format(TabShiftLabel(best_shift), status_fit)
    S.last_result = table.concat(lines, '\n')
end
