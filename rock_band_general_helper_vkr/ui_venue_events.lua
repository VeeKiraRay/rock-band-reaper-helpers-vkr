-- Venue > Events sub-tab
-- Inserts EVENTS-track section/crowd/global text events at the playhead, one
-- row per event group, with number stepper, letter suffixes, and insert
-- validation. Also hosts the Clear all / Insert bookends quick actions.
-- Requires globals: r, ctx, S, TIPS, Tooltip, SliderTooltip, RunAction,
--                   SECTION_EVENT_GROUPS, SECTION_EVENT_BASE, MakeProjectPoll,
--                   FindEventsTake, ScanEventsTextEvents, NextSectionEvent,
--                   ValidatePlainInsert, InsertEventsEvent, AddSectionEvent,
--                   ClearAllEventsTexts, InsertEventsBookends

-- Cached EVENTS take + scan, refreshed via MakeProjectPoll (at most every
-- 1 s and only when the project changed; 5 s fallback). This tab's own edit
-- buttons set _force_rescan so the -> indicator refreshes next frame instead
-- of waiting out the poll window. The cached take is validated every frame
-- (item deletion / project switch invalidates the pointer between polls).
-- Correctness never depends on this cache - the Add actions always re-scan.
local _poll = MakeProjectPoll(1.0, 5.0)
local _ev_track, _ev_take, _scan
local _force_rescan = false

-- Row for a 'prc' or 'generic' group: combo + number stepper + Add + indicator
local function _draw_prc_row(g, scan, cur_t, cur_ppq, no_take, use_letters, lbl_col)
    local sel = S.venue_ev_sel[g.key] or ''

    r.ImGui_Text(ctx, g.label)
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 170)
    if r.ImGui_BeginCombo(ctx, '##ev_' .. g.key, sel ~= '' and sel or '(select)') then
        if r.ImGui_Selectable(ctx, '(none)', sel == '') then
            S.venue_ev_sel[g.key] = ''
        end
        if sel == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, b in ipairs(g.bases) do
            local b_sel = (sel == b.base)
            if r.ImGui_Selectable(ctx, b.base, b_sel) then
                S.venue_ev_sel[g.key] = b.base
            end
            if b_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(g.tip)

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 90)
    local num = S.venue_ev_num[g.key] or 0
    _, num = r.ImGui_SliderInt(ctx, '##ev_' .. g.key .. '_num', num, 0, 9,
                               num == 0 and 'bare' or '%d')
    S.venue_ev_num[g.key] = num
    SliderTooltip(TIPS.venue_ev_num)

    r.ImGui_SameLine(ctx)
    local dis = no_take or sel == ''
    if dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##ev_' .. g.key, 0) then
        local _b, _n, _l = sel, num, use_letters
        local _c = (SECTION_EVENT_BASE[sel] or {}).caps
        local _g = g.kind == 'generic'
        RunAction(function() AddSectionEvent(_b, _n, _c, _g, _l) end)
        _force_rescan = true
    end
    if dis then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.venue_ev_add)

    if sel ~= '' and scan then
        local text, err = NextSectionEvent(scan, sel, num,
                                           (SECTION_EVENT_BASE[sel] or {}).caps,
                                           g.kind == 'generic', use_letters,
                                           cur_t, cur_ppq)
        r.ImGui_SameLine(ctx)
        if text then
            r.ImGui_TextDisabled(ctx, '-> ' .. text)
            Tooltip(TIPS.venue_ev_next)
        else
            -- full reason on hover and in the result section after Add
            r.ImGui_TextDisabled(ctx, '-> (blocked)')
            Tooltip(err)
        end
    end
end

-- Row for a 'plain' group (Crowd/Global): combo of full event strings + Add.
-- The combo is widened to span the stepper column so Add buttons line up.
local function _draw_plain_row(g, scan, cur_ppq, no_take, lbl_col, combo_w)
    local sel = S.venue_ev_sel[g.key] or ''

    r.ImGui_Text(ctx, g.label)
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, combo_w)
    if r.ImGui_BeginCombo(ctx, '##ev_' .. g.key, sel ~= '' and sel or '(select)') then
        if r.ImGui_Selectable(ctx, '(none)', sel == '') then
            S.venue_ev_sel[g.key] = ''
        end
        if sel == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, ev in ipairs(g.events) do
            local e_sel = (sel == ev)
            if r.ImGui_Selectable(ctx, ev, e_sel) then
                S.venue_ev_sel[g.key] = ev
            end
            if e_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(g.tip)

    r.ImGui_SameLine(ctx)
    local dis = no_take or sel == ''
    if dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##ev_' .. g.key, 0) then
        local _ev = sel
        RunAction(function() InsertEventsEvent(_ev) end)
        _force_rescan = true
    end
    if dis then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.venue_ev_add)

    if sel ~= '' and scan then
        local ok, err = ValidatePlainInsert(scan, sel, cur_ppq)
        if not ok then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, '(blocked)')
            Tooltip(err)
        end
    end
end

function DrawVenueEventsTab()
    local _group_labels = { 'Use letter suffix' }
    for _, g in ipairs(SECTION_EVENT_GROUPS) do _group_labels[#_group_labels + 1] = g.label end
    local lbl_col = LabelColWidth(_group_labels)
    local item_sp = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())

    r.ImGui_Text(ctx,
        'Insert section, crowd, and global events on the EVENTS track at the playhead')
    r.ImGui_Spacing(ctx)

    -- Refresh the cached take + scan when the poll fires, this tab's own
    -- buttons forced it, or the cached take pointer went stale
    local take_valid = _ev_take and r.ValidatePtr2(0, _ev_take, 'MediaItem_Take*')
    if _poll(_force_rescan) or (_ev_take and not take_valid) then
        _force_rescan = false
        _ev_track, _, _ev_take = FindEventsTake()
        _scan = _ev_take and ScanEventsTextEvents(_ev_take) or nil
        take_valid = _ev_take ~= nil
    end
    local ev_track, ev_take = _ev_track, take_valid and _ev_take or nil
    local no_take = not ev_take              -- snapshot once (BeginDisabled balance)

    -- Quick actions row
    local bw_qa = BtnGroupWidth({ 'Insert bookends', 'Clear all' })
    if no_take then r.ImGui_BeginDisabled(ctx) end
    if Btn('Insert bookends', BTN_H, bw_qa) then
        RunAction(InsertEventsBookends)
        _force_rescan = true
    end
    if not no_take then Tooltip(TIPS.venue_ev_bookends) end
    r.ImGui_SameLine(ctx)
    if Btn('Clear all', BTN_H, bw_qa) then
        RunAction(ClearAllEventsTexts)
        _force_rescan = true
    end
    if not no_take then Tooltip(TIPS.venue_ev_clear) end
    if no_take then r.ImGui_EndDisabled(ctx) end

    local scan, cur_t, cur_ppq
    if ev_take then
        scan  = _scan
        cur_t = r.GetCursorPosition()
        cur_ppq = math.floor(r.MIDI_GetPPQPosFromProjTime(ev_take, cur_t) + 0.5)
    end

    if no_take then
        r.ImGui_TextDisabled(ctx, ev_track
            and 'No MIDI item on EVENTS track - add one to enable Add'
            or  'No EVENTS track found - create it to enable Add')
    end

    -- Phase 2 adds a target-mode radio row here (EVENTS / other MIDI track);
    -- S.venue_ev_mode is already reserved for it.
    r.ImGui_Text(ctx, 'Use letter suffix')
    r.ImGui_SameLine(ctx, lbl_col)
    _, S.venue_ev_letters = r.ImGui_Checkbox(ctx, '##venue_ev_letters', S.venue_ev_letters)
    Tooltip(TIPS.venue_ev_letters)
    local use_letters = S.venue_ev_letters  -- snapshot once per frame
    r.ImGui_Spacing(ctx)

    for _, g in ipairs(SECTION_EVENT_GROUPS) do
        if g.kind == 'plain' then
            _draw_plain_row(g, scan, cur_ppq, no_take, lbl_col,
                            170 + item_sp + 90)
        else
            _draw_prc_row(g, scan, cur_t, cur_ppq, no_take, use_letters, lbl_col)
        end
    end
end
