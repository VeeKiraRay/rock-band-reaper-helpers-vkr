-- Events tab actions: EVENTS-track text event insertion at the playhead with
-- number/letter suffix handling and insert validation (duplicates, bare vs
-- numbered exclusivity, sequence/timeline ordering, same-spot collisions),
-- plus the Clear all / Insert bookends quick actions.
-- Requires: FindNamedTrackMIDI, DeleteTextEventsInRange, FormatTime, r, S (globals)

local function _round_ppq(ppq) return math.floor(ppq + 0.5) end

local function _is_crowd(msg) return msg:find('^%[crowd_') ~= nil end

-- Locate the EVENTS track and its first MIDI item/take. Silent (no S.status)
-- because the UI calls this every frame; actions build their own messages.
-- Returns track, item, take - track may be non-nil while item/take are nil
-- (track exists but has no MIDI item).
function FindEventsTake()
    return FindNamedTrackMIDI('EVENTS')
end

-- Scan of all type-1 (TEXT) events on the take:
--   { events = array of {msg, ppq, t, label} sorted by ppq,
--     by_msg = map msg -> first (earliest) entry }
-- label is a preformatted FormatTime(t) so the validation core needs no
-- REAPER calls. ppq is rounded to an integer for same-spot comparison.
function ScanEventsTextEvents(take)
    local events = {}
    local _, _, _, textcnt = r.MIDI_CountEvts(take)
    for i = 0, textcnt - 1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 then
            local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
            events[#events + 1] = {
                msg = msg, ppq = _round_ppq(ppq), t = t, label = FormatTime(t),
            }
        end
    end
    table.sort(events, function(a, b) return a.ppq < b.ppq end)
    local by_msg = {}
    for _, e in ipairs(events) do
        if not by_msg[e.msg] then by_msg[e.msg] = e end
    end
    return { events = events, by_msg = by_msg }
end

-- ---------------------------------------------------------------------------
-- Validation core (pure - no REAPER/S; unit-testable)
-- ---------------------------------------------------------------------------

-- Event string builders. num 0 = the bare, unnumbered form.
-- non-generic:  [prc_verse] / [prc_verse_a] / [prc_verse_1] / [prc_verse_1a]
-- generic:      [prc_a] / [prc_a3]  (digit appended, no underscore, no letters)
local function _bare_form(base, num, is_generic)
    if num == 0 then return '[prc_' .. base .. ']' end
    if is_generic then return '[prc_' .. base .. num .. ']' end
    return '[prc_' .. base .. '_' .. num .. ']'
end

local function _letter_form(base, num, letter, is_generic)
    if is_generic then return nil end
    if num == 0 then return '[prc_' .. base .. '_' .. letter .. ']' end
    return '[prc_' .. base .. '_' .. num .. letter .. ']'
end

-- Earliest/latest present member of the (base, num) family: the bare form
-- plus every letter a-z (hand-authored letters beyond the cap count too).
-- Returns first_entry, last_entry (by time), or nil when the family is empty.
local function _family_span(scan, base, num, is_generic)
    local first, last
    local function consider(msg)
        local e = msg and scan.by_msg[msg]
        if not e then return end
        if not first or e.t < first.t then first = e end
        if not last  or e.t > last.t  then last  = e end
    end
    consider(_bare_form(base, num, is_generic))
    if not is_generic then
        for c = string.byte('a'), string.byte('z') do
            consider(_letter_form(base, num, string.char(c), is_generic))
        end
    end
    return first, last
end

local function _spot_conflict(scan, ins_ppq)
    for _, e in ipairs(scan.events) do
        if e.ppq == ins_ppq and not _is_crowd(e.msg) then return e end
    end
    return nil
end

-- Compute and validate the event the Add button would insert.
-- scan:        result of ScanEventsTextEvents
-- base:        bare base name, e.g. 'verse' or (generic) 'a'
-- num:         0-9; 0 = unnumbered form
-- caps:        caps string from SECTION_EVENT_BASE (nil for generic)
-- is_generic:  [prc_a3]-style base
-- use_letters: letter-suffix mode - targets are lettered forms only
--              ([prc_verse_a], never [prc_verse]); when off, targets are the
--              unlettered form only. Mixing the two within one (base, num)
--              family is refused in both directions. Bases with no lettered
--              variants fall back to the unlettered form in either mode.
-- ins_t/ins_ppq: insert position (project time / rounded take PPQ)
-- Returns the full event string to insert, or nil, reason.
function NextSectionEvent(scan, base, num, caps, is_generic, use_letters, ins_t, ins_ppq)
    -- 1. number validity
    if not is_generic then
        local cap_ch = caps:sub(num + 1, num + 1)
        if cap_ch == '' then
            return nil, '[prc_' .. base .. '] has no _' .. num .. ' variant'
        end
    end

    -- 2. bare vs numbered exclusivity (letters ride along with their number)
    local numbered_first
    for n = 1, 9 do
        local f = _family_span(scan, base, n, is_generic)
        if f then numbered_first = f; break end
    end
    local bare_first = _family_span(scan, base, 0, is_generic)
    if num == 0 and numbered_first then
        return nil, 'Numbered ' .. numbered_first.msg .. ' exists - bare and numbered must not ' ..
                    'co-exist. Use bare for a single section, numbers for repeats.'
    end
    if num >= 1 and bare_first then
        return nil, 'Bare ' .. bare_first.msg .. ' exists - remove it before adding ' ..
                    'numbered variants.'
    end

    -- 3. numbers must be used in order: _N needs an _N-1 family (N >= 2)
    if num >= 2 and not _family_span(scan, base, num - 1, is_generic) then
        return nil, 'Add ' .. _bare_form(base, num - 1, is_generic) ..
                    ' first - numbers must be used in order.'
    end

    -- 4. pick the target slot. Letter mode uses only lettered forms (a..cap,
    --    never the unlettered event); plain mode uses only the unlettered
    --    form. The two must not be mixed within one (base, num) family.
    --    Bases with no lettered variants ('.') fall back to the plain form
    --    even in letter mode.
    local bare = _bare_form(base, num, is_generic)
    local cap_ch = is_generic and '.' or caps:sub(num + 1, num + 1)
    local slots, target_i
    if use_letters and not is_generic and cap_ch ~= '.' then
        local plain = scan.by_msg[bare]
        if plain then
            return nil, bare .. ' exists at ' .. plain.label .. ' - it must not be mixed ' ..
                        'with lettered parts. Remove it, or disable letter suffix.'
        end
        slots = {}
        for c = string.byte('a'), string.byte(cap_ch) do
            slots[#slots + 1] = _letter_form(base, num, string.char(c), is_generic)
        end
        for i, msg in ipairs(slots) do
            if not scan.by_msg[msg] then target_i = i; break end
        end
        if not target_i then
            return nil, 'No more letters available for ' .. bare .. ' (max ' .. cap_ch .. ')'
        end
    else
        if not is_generic and cap_ch ~= '.' then
            for c = string.byte('a'), string.byte(cap_ch) do
                local e = scan.by_msg[_letter_form(base, num, string.char(c), is_generic)]
                if e then
                    return nil, 'Lettered ' .. e.msg .. ' exists - enable letter suffix to ' ..
                                'add more parts, or remove the lettered events.'
                end
            end
        end
        local dup = scan.by_msg[bare]
        if dup then
            return nil, bare .. ' already exists at ' .. dup.label
        end
        slots, target_i = { bare }, 1
    end
    local target = slots[target_i]

    -- 5. timeline ordering: after the previous element in the full sequence,
    --    before the next existing one (within the family, else the nearest
    --    lower/higher numbered family)
    local prev_e
    for i = target_i - 1, 1, -1 do
        prev_e = scan.by_msg[slots[i]]
        if prev_e then break end
    end
    if not prev_e then
        for n = num - 1, 1, -1 do
            local _, last = _family_span(scan, base, n, is_generic)
            if last then prev_e = last; break end
        end
    end
    local next_e
    for i = target_i + 1, #slots do
        next_e = scan.by_msg[slots[i]]
        if next_e then break end
    end
    if not next_e then
        for n = num + 1, 9 do
            local first = _family_span(scan, base, n, is_generic)
            if first then next_e = first; break end
        end
    end
    if prev_e and ins_t <= prev_e.t then
        return nil, target .. ' must be placed after ' .. prev_e.msg ..
                    ' (' .. prev_e.label .. ')'
    end
    if next_e and ins_t >= next_e.t then
        return nil, target .. ' must be placed before ' .. next_e.msg ..
                    ' (' .. next_e.label .. ')'
    end

    -- 6. same-spot: no two text events on one position (crowd events exempt)
    local spot = _spot_conflict(scan, ins_ppq)
    if spot then
        return nil, spot.msg .. ' is already at this position (' .. spot.label .. ')'
    end

    return target
end

-- Validation for the Crowd/Global rows (msg is the full event string).
-- Crowd events bypass all checks; others get duplicate + same-spot checks.
-- Returns true, or nil, reason.
function ValidatePlainInsert(scan, msg, ins_ppq)
    if _is_crowd(msg) then return true end
    local dup = scan.by_msg[msg]
    if dup then
        return nil, msg .. ' already exists at ' .. dup.label
    end
    local spot = _spot_conflict(scan, ins_ppq)
    if spot then
        return nil, spot.msg .. ' is already at this position (' .. spot.label .. ')'
    end
    return true
end

-- ---------------------------------------------------------------------------

local function _require_take()
    local track, item, take = FindEventsTake()
    if not track then
        S.status = 'No EVENTS track found.'
        return nil, nil, nil
    end
    if not take then
        S.status = 'No MIDI item on EVENTS track.'
        return nil, nil, nil
    end
    return track, item, take
end

local function _insert(track, item, take, text)
    local abs_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_InsertTextSysexEvt(take, false, false, abs_ppq, 1, text)
    r.Undo_EndBlock2(0, 'RB Insert EVENTS event: ' .. text, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = 'Inserted ' .. text .. ' at playhead (EVENTS).'
    S.last_result = nil
end

-- Refusal reporting: one-line status plus the full reason in the result
-- section (the inline row indicator only shows a short "(blocked)" marker).
local function _refuse(err)
    S.status = err
    S.last_result = err
end

-- Insert for Crowd/Global rows (text is the full event string).
function InsertEventsEvent(text)
    local track, item, take = _require_take()
    if not track then return end
    local scan = ScanEventsTextEvents(take)
    local ins_ppq = _round_ppq(r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition()))
    local ok, err = ValidatePlainInsert(scan, text, ins_ppq)
    if not ok then
        _refuse(err)
        return
    end
    _insert(track, item, take, text)
end

-- Insert for prc/generic rows: validate + compute the suffixed event, insert.
function AddSectionEvent(base, num, caps, is_generic, use_letters)
    local track, item, take = _require_take()
    if not track then return end
    -- Fresh scan at Add time - never trust a UI frame's cached scan.
    local scan  = ScanEventsTextEvents(take)
    local ins_t = r.GetCursorPosition()
    local ins_ppq = _round_ppq(r.MIDI_GetPPQPosFromProjTime(take, ins_t))
    local text, err = NextSectionEvent(scan, base, num, caps, is_generic,
                                       use_letters, ins_t, ins_ppq)
    if not text then
        _refuse(err)
        return
    end
    _insert(track, item, take, text)
end

-- ---------------------------------------------------------------------------
-- Quick actions
-- ---------------------------------------------------------------------------

-- Remove every type-1 text event on the EVENTS take. The track-name event is
-- a different event type and is left untouched.
function ClearAllEventsTexts()
    local track, item, take = _require_take()
    if not track then return end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    local count = DeleteTextEventsInRange(take, -math.huge, math.huge, nil)
    r.Undo_EndBlock2(0, 'RB Clear EVENTS text events (' .. count .. ')', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Removed %d text events (EVENTS).'):format(count)
    S.last_result = nil
end

local BOOKEND_EVENTS = {
    '[prc_intro]', '[crowd_normal]', '[music_start]',
    '[prc_outro]', '[music_end]', '[end]',
}

-- Insert the minimal event set every song needs: [prc_intro] + [crowd_normal]
-- at measure 1, [music_start] at measure 3, and - when the MIDI item is at
-- least 7 full measures long - [prc_outro] / [music_end] / [end] at measures
-- E-5 / E-2 / E, where E is the last measure fully contained in the item.
-- Existing instances of these six events are removed first, so re-running
-- recalculates their positions. A foreign non-crowd event already sitting on
-- a target spot makes that bookend be skipped (same-spot rule).
function InsertEventsBookends()
    local track, item, take = _require_take()
    if not track then return end

    -- Measure walk via TimeMap_GetMeasureInfo (0-based index; time-signature
    -- safe). E = last measure whose end is within the item.
    local item_end = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                   + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local end_qn = r.TimeMap2_timeToQN(0, item_end)
    local last_full   -- 1-based measure number of E
    local m_time = {} -- 1-based measure number -> project time of its start
    local m = 0
    while m < 100000 do
        local t_start, qn_start, qn_end = r.TimeMap_GetMeasureInfo(0, m)
        if qn_start > end_qn + 1e-9 then break end
        m_time[m + 1] = t_start
        if qn_end <= end_qn + 1e-9 then last_full = m + 1 end
        m = m + 1
    end

    local plan = {
        { measure = 1, msg = '[prc_intro]'   },
        { measure = 1, msg = '[crowd_normal]' },
        { measure = 3, msg = '[music_start]' },
    }
    local end_events_skipped = false
    if last_full and last_full >= 7 then
        plan[#plan + 1] = { measure = last_full - 5, msg = '[prc_outro]' }
        plan[#plan + 1] = { measure = last_full - 2, msg = '[music_end]' }
        plan[#plan + 1] = { measure = last_full,     msg = '[end]'       }
    else
        end_events_skipped = true
    end

    local bookend_set = {}
    for _, msg in ipairs(BOOKEND_EVENTS) do bookend_set[msg] = true end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    -- Remove existing instances of the six bookend events
    local removed = DeleteTextEventsInRange(take, -math.huge, math.huge,
                                            function(msg) return not bookend_set[msg] end)

    -- Insert at the planned spots, skipping occupied ones (crowd events may
    -- stack anywhere and anything may stack on a crowd event). `placed`
    -- tracks this run's own non-crowd inserts, since `scan` predates them
    -- (e.g. a short song can put [prc_outro] on [music_start]'s measure).
    local scan = ScanEventsTextEvents(take)
    local lines, inserted, placed = {}, 0, {}
    for _, p in ipairs(plan) do
        local t = m_time[p.measure]
        if not t then t = ({r.TimeMap_GetMeasureInfo(0, p.measure - 1)})[1] end
        local ppq = r.MIDI_GetPPQPosFromProjTime(take, t)
        local rp  = _round_ppq(ppq)
        local spot_msg
        if not _is_crowd(p.msg) then
            local spot = _spot_conflict(scan, rp)
            spot_msg = (spot and spot.msg) or placed[rp]
        end
        if spot_msg then
            lines[#lines + 1] = ('Skipped %s - %s is already at measure %d.')
                                :format(p.msg, spot_msg, p.measure)
        else
            r.MIDI_InsertTextSysexEvt(take, false, false, ppq, 1, p.msg)
            inserted = inserted + 1
            if not _is_crowd(p.msg) then placed[rp] = p.msg end
            lines[#lines + 1] = ('Inserted %s at measure %d.'):format(p.msg, p.measure)
        end
    end

    r.Undo_EndBlock2(0, 'RB Insert EVENTS bookends (' .. inserted .. ' events)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if removed > 0 then
        table.insert(lines, 1, ('Removed %d previous bookend event(s).'):format(removed))
        table.insert(lines, 2, '')
    end
    if end_events_skipped then
        lines[#lines + 1] = ''
        lines[#lines + 1] = last_full
            and ('End events skipped - item is only %d full measure(s) long (needs 7).')
                :format(last_full)
            or  'End events skipped - item is shorter than one full measure.'
    end
    S.status = ('Inserted %d bookend events (EVENTS).'):format(inserted)
    S.last_result = table.concat(lines, '\n')
end
