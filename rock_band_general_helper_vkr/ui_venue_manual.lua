-- Venue > Manual gen sub-tab
-- Shot-by-shot event insertion at the playhead: camera/lighting/postproc/
-- special dropdown rows, playhead advance, keyframe generation, removal.
-- TODO: the five combo+Add rows repeat the same boilerplate - if this file
-- grows, factor a row helper modeled on ui_venue_events.lua's _draw_prc_row.
-- Requires globals: r, ctx, S, TIPS, Tooltip, SliderTooltip, RunAction,
--                   RenderCamPacingRow, MakeProjectPoll, FindNamedTrackMIDI,
--                   InsertVenueEventAtPlayhead, AdvanceCameraPacing,
--                   GenerateManualKeyframes, RemoveVenueEventsByType,
--                   MANUAL_LIGHTING_SET, GetTakePPQPerQN, NO_LIGHTING_AT_PLAYHEAD_MSG,
--                   COOP_POOL, DIRECTED_POOL, DIRECTED_LABELS, DIRECTED_TIPS,
--                   LIGHTING_LABELS, LIGHTING_TIPS, POSTPROC_LABELS, POSTPROC_TIPS,
--                   KF_ALIGN_LABELS, BeginVenueTooltip, DrawVenueTooltipSprite,
--                   EndVenueTooltip

-- Cached VENUE take and the PPQ of every manual lighting event on it, refreshed via
-- MakeProjectPoll (at most every 1 s and only when the project changed; 5 s fallback) -
-- same pattern as ui_venue_events.lua. Backs the "is there a manual lighting event under
-- the playhead?" check that gates [first] insertion and keyframe generation. The
-- positions are cached rather than re-read per frame because the playhead moves
-- constantly while the event list does not, and a finished VENUE track carries thousands
-- of text events. The cached take is validated every frame (item deletion / project
-- switch invalidates the pointer between polls), and this tab's own Add buttons force a
-- rescan so the gate reopens the frame after a lighting event is added. Correctness never
-- depends on this cache - both actions re-check the take for themselves.
local _poll         = MakeProjectPoll(1.0, 5.0)
local _venue_take
local _manual_lt    = nil   -- array of manual lighting PPQ positions
local _lt_tol       = 0     -- match tolerance in ticks (see FindManualLightingAtPpq)
local _force_rescan = false

local function _ScanManualLighting(take)
    local out = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, evt_ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and MANUAL_LIGHTING_SET[msg] then
            out[#out + 1] = evt_ppq
        end
    end
    return out, math.floor(GetTakePPQPerQN(take) / 32)
end

function DrawVenueManualTab()
    local _take_valid = _venue_take and r.ValidatePtr2(0, _venue_take, 'MediaItem_Take*')
    if _poll(_force_rescan) or (_venue_take and not _take_valid) then
        _force_rescan = false
        local _, _, _tk = FindNamedTrackMIDI('VENUE')
        _venue_take = _tk
        _take_valid = _venue_take ~= nil
        _manual_lt  = nil
        if _take_valid then _manual_lt, _lt_tol = _ScanManualLighting(_venue_take) end
    end
    -- No VENUE take at all: leave the keyframe controls enabled rather than locking the
    -- tab on a stale/missing cache - the actions report the missing track themselves.
    local _lt_at_playhead = true
    if _take_valid and _manual_lt then
        local _cur_ppq = r.MIDI_GetPPQPosFromProjTime(_venue_take, r.GetCursorPosition())
        _lt_at_playhead = false
        for _, _p in ipairs(_manual_lt) do
            if math.abs(_p - _cur_ppq) <= _lt_tol then _lt_at_playhead = true; break end
        end
    end

    r.ImGui_TextWrapped(ctx, 'Insert individual venue events at the playhead position')
    r.ImGui_Spacing(ctx)

    -- Build directed name list including bre/brej (excluded from auto-gen DIRECTED_POOL)
    local _mg_dir_names = {}
    for _, _dev in ipairs(DIRECTED_POOL) do
        _mg_dir_names[#_mg_dir_names + 1] = _dev:match('^%[(.-)%]$') or _dev
    end
    _mg_dir_names[#_mg_dir_names + 1] = 'directed_bre'
    _mg_dir_names[#_mg_dir_names + 1] = 'directed_brej'

    -- Special events list
    local _special_events = {
        '[bonusfx]', '[bonusfx_optional]', '[first]', '[next]', '[previous]',
    }
    local _special_labels = {
        ['[bonusfx]']          = 'Bonus FX',
        ['[bonusfx_optional]'] = 'Bonus FX (optional)',
        ['[first]']            = '[first] keyframe',
        ['[next]']             = '[next] keyframe',
        ['[previous]']         = '[previous] keyframe',
    }

    local _lbl_col = LabelColWidth({
        'Normal camera', 'Directed camera', 'Lighting', 'Keyframe align',
        'Keyframe rate', 'Post proc', 'Special', 'Camera pacing', 'Remove',
    })

    -- ---- Normal camera ----
    r.ImGui_Text(ctx, 'Normal camera')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_coop_bare = S.venue_mg_coop ~= '' and (S.venue_mg_coop:match('^%[(.-)%]$') or S.venue_mg_coop) or ''
    local _mg_coop_prev = _mg_coop_bare ~= '' and _mg_coop_bare or '(select)'
    if r.ImGui_BeginCombo(ctx, '##mg_coop', _mg_coop_prev) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_mg_coop == '') then
            S.venue_mg_coop = ''
        end
        if S.venue_mg_coop == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, _cev in ipairs(COOP_POOL) do
            local _cbare = _cev:match('^%[(.-)%]$') or _cev
            local _csel  = (S.venue_mg_coop == _cev)
            if r.ImGui_Selectable(ctx, _cbare, _csel) then
                S.venue_mg_coop = _cev
            end
            if _csel then r.ImGui_SetItemDefaultFocus(ctx) end
            if r.ImGui_IsItemHovered(ctx) then
                if BeginVenueTooltip() then
                    DrawVenueTooltipSprite('Camera', _cbare)
                    EndVenueTooltip()
                end
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) and S.venue_mg_coop ~= '' then
        if BeginVenueTooltip() then
            DrawVenueTooltipSprite('Camera', _mg_coop_bare)
            EndVenueTooltip()
        end
    end
    r.ImGui_SameLine(ctx)
    local _mg_coop_dis = S.venue_mg_coop == ''
    if _mg_coop_dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##mg_coop_add', 0) then
        local _ev = S.venue_mg_coop
        RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
    end
    if _mg_coop_dis then r.ImGui_EndDisabled(ctx) end

    -- ---- Directed camera ----
    r.ImGui_Text(ctx, 'Directed camera')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_dir_prev = S.venue_mg_directed ~= ''
        and (DIRECTED_LABELS[S.venue_mg_directed] or S.venue_mg_directed)
        or '(select)'
    if r.ImGui_BeginCombo(ctx, '##mg_dir', _mg_dir_prev) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_mg_directed == '') then
            S.venue_mg_directed = ''
        end
        if S.venue_mg_directed == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, _dn in ipairs(_mg_dir_names) do
            local _dsel = (S.venue_mg_directed == _dn)
            if r.ImGui_Selectable(ctx, DIRECTED_LABELS[_dn] or _dn, _dsel) then
                S.venue_mg_directed = _dn
            end
            if _dsel then r.ImGui_SetItemDefaultFocus(ctx) end
            if r.ImGui_IsItemHovered(ctx) then
                if BeginVenueTooltip() then
                    DrawVenueTooltipSprite('Camera', _dn)
                    if DIRECTED_TIPS[_dn] then
                        r.ImGui_Text(ctx, DIRECTED_TIPS[_dn])
                    end
                    EndVenueTooltip()
                end
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) and S.venue_mg_directed ~= '' then
        if BeginVenueTooltip() then
            DrawVenueTooltipSprite('Camera', S.venue_mg_directed)
            if DIRECTED_TIPS[S.venue_mg_directed] then
                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, (DIRECTED_LABELS[S.venue_mg_directed] or S.venue_mg_directed)
                                 .. ':\n' .. DIRECTED_TIPS[S.venue_mg_directed])
            end
            EndVenueTooltip()
        end
    end
    r.ImGui_SameLine(ctx)
    local _mg_dir_dis = S.venue_mg_directed == ''
    if _mg_dir_dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##mg_dir_add', 0) then
        local _ev = '[' .. S.venue_mg_directed .. ']'
        RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
    end
    if _mg_dir_dis then r.ImGui_EndDisabled(ctx) end

    -- ---- Lighting ----
    r.ImGui_Text(ctx, 'Lighting')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_lt_prev = S.venue_mg_lighting ~= ''
        and (LIGHTING_LABELS[S.venue_mg_lighting] or S.venue_mg_lighting)
        or '(select)'
    if r.ImGui_BeginCombo(ctx, '##mg_lt', _mg_lt_prev) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_mg_lighting == '') then
            S.venue_mg_lighting = ''
        end
        if S.venue_mg_lighting == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, _ltn in ipairs(LIGHTING_NAMES) do
            local _lsel = (S.venue_mg_lighting == _ltn)
            if r.ImGui_Selectable(ctx, LIGHTING_LABELS[_ltn] or _ltn, _lsel) then
                S.venue_mg_lighting = _ltn
            end
            if _lsel then r.ImGui_SetItemDefaultFocus(ctx) end
            if r.ImGui_IsItemHovered(ctx) then
                if BeginVenueTooltip() then
                    DrawVenueTooltipSprite('Lighting', _ltn)
                    if LIGHTING_TIPS[_ltn] then
                        r.ImGui_Text(ctx, LIGHTING_TIPS[_ltn])
                    end
                    EndVenueTooltip()
                end
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) and S.venue_mg_lighting ~= '' then
        if BeginVenueTooltip() then
            DrawVenueTooltipSprite('Lighting', S.venue_mg_lighting)
            if LIGHTING_TIPS[S.venue_mg_lighting] then
                r.ImGui_Text(ctx, (LIGHTING_LABELS[S.venue_mg_lighting] or S.venue_mg_lighting)
                                 .. ':\n' .. LIGHTING_TIPS[S.venue_mg_lighting])
            end
            EndVenueTooltip()
        end
    end
    r.ImGui_SameLine(ctx)
    local _mg_lt_dis = S.venue_mg_lighting == ''
    if _mg_lt_dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##mg_lt_add', 0) then
        local _ev = '[lighting (' .. S.venue_mg_lighting .. ')]'
        RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
        _force_rescan = true
    end
    if _mg_lt_dis then r.ImGui_EndDisabled(ctx) end

    -- Keyframe settings: usable only on a manual lighting event's own tick, since
    -- [first] has to share it. Snapshot once (BeginDisabled balance).
    local _kf_dis = not _lt_at_playhead
    if _kf_dis then r.ImGui_BeginDisabled(ctx) end

    r.ImGui_Text(ctx, 'Keyframe align')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_kfa_labels = KF_ALIGN_LABELS  -- shared with RenderKeyframeAlignCombo
    local _mg_kfa_prev = _mg_kfa_labels[S.venue_keyframe_align + 1] or _mg_kfa_labels[1]
    if r.ImGui_BeginCombo(ctx, '##mg_kfa', _mg_kfa_prev) then
        for _ki, _kl in ipairs(_mg_kfa_labels) do
            local _ksel = (_ki - 1 == S.venue_keyframe_align)
            if r.ImGui_Selectable(ctx, _kl, _ksel) then
                S.venue_keyframe_align = _ki - 1
            end
            if _ksel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.venue_keyframe_align)
    r.ImGui_SameLine(ctx)
    if Btn('Add##mg_kf_btn', 0) then
        RunAction(GenerateManualKeyframes)
        _force_rescan = true
    end
    Tooltip(TIPS.venue_mg_kf_add)
    if _kf_dis then
        -- Step out of the disabled scope just for this label: a disabled widget never
        -- reports hover, so a tooltip drawn inside it could never explain the block.
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, '(blocked)')
        Tooltip(NO_LIGHTING_AT_PLAYHEAD_MSG)
        r.ImGui_BeginDisabled(ctx)
    end

    if S.venue_keyframe_align >= 3 then
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Subdivision    ')
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every beat##mg_kfis', S.venue_kf_inst_subdiv == 0) then
            S.venue_kf_inst_subdiv = 0
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every half beat##mg_kfis', S.venue_kf_inst_subdiv == 1) then
            S.venue_kf_inst_subdiv = 1
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every quarter beat##mg_kfis', S.venue_kf_inst_subdiv == 2) then
            S.venue_kf_inst_subdiv = 2
        end
    end

    r.ImGui_Text(ctx, 'Keyframe rate')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 120)
    _, S.venue_mg_kf_rate = r.ImGui_SliderInt(ctx, '##mg_kf_rate', S.venue_mg_kf_rate, 1, 8)
    SliderTooltip(TIPS.venue_sec_kr)

    if _kf_dis then r.ImGui_EndDisabled(ctx) end

    -- ---- Post proc ----
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Post proc')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_pp_prev = S.venue_mg_postproc ~= ''
        and (POSTPROC_LABELS[S.venue_mg_postproc] or S.venue_mg_postproc)
        or '(select)'
    if r.ImGui_BeginCombo(ctx, '##mg_pp', _mg_pp_prev) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_mg_postproc == '') then
            S.venue_mg_postproc = ''
        end
        if S.venue_mg_postproc == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, _ppn in ipairs(POSTPROC_NAMES) do
            local _psel = (S.venue_mg_postproc == _ppn)
            if r.ImGui_Selectable(ctx, POSTPROC_LABELS[_ppn] or _ppn, _psel) then
                S.venue_mg_postproc = _ppn
            end
            if _psel then r.ImGui_SetItemDefaultFocus(ctx) end
            if r.ImGui_IsItemHovered(ctx) then
                if BeginVenueTooltip() then
                    DrawVenueTooltipSprite('PostProc', _ppn)
                    if POSTPROC_TIPS[_ppn] then
                        r.ImGui_Text(ctx, POSTPROC_TIPS[_ppn])
                    end
                    EndVenueTooltip()
                end
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) and S.venue_mg_postproc ~= '' then
        if BeginVenueTooltip() then
            DrawVenueTooltipSprite('PostProc', S.venue_mg_postproc)
            if POSTPROC_TIPS[S.venue_mg_postproc] then
                r.ImGui_Text(ctx, (POSTPROC_LABELS[S.venue_mg_postproc] or S.venue_mg_postproc)
                                 .. ':\n' .. POSTPROC_TIPS[S.venue_mg_postproc])
            end
            EndVenueTooltip()
        end
    end
    r.ImGui_SameLine(ctx)
    local _mg_pp_dis = S.venue_mg_postproc == ''
    if _mg_pp_dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##mg_pp_add', 0) then
        local _ev = '[' .. S.venue_mg_postproc .. ']'
        RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
    end
    if _mg_pp_dis then r.ImGui_EndDisabled(ctx) end

    -- ---- Special ----
    r.ImGui_Text(ctx, 'Special')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 230)
    local _mg_sp_prev = S.venue_mg_special ~= ''
        and (_special_labels[S.venue_mg_special] or S.venue_mg_special)
        or '(select)'
    if r.ImGui_BeginCombo(ctx, '##mg_sp', _mg_sp_prev) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_mg_special == '') then
            S.venue_mg_special = ''
        end
        if S.venue_mg_special == '' then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, _sev in ipairs(_special_events) do
            local _ssel = (S.venue_mg_special == _sev)
            if r.ImGui_Selectable(ctx, _special_labels[_sev] or _sev, _ssel) then
                S.venue_mg_special = _sev
            end
            if _ssel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    r.ImGui_SameLine(ctx)
    local _mg_sp_dis = S.venue_mg_special == ''
    if _mg_sp_dis then r.ImGui_BeginDisabled(ctx) end
    if Btn('Add##mg_sp_add', 0) then
        local _ev = S.venue_mg_special
        RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
        _force_rescan = true
    end
    if _mg_sp_dis then r.ImGui_EndDisabled(ctx) end
    -- [first] is the only special event tied to a lighting event's position.
    if S.venue_mg_special == '[first]' and not _lt_at_playhead then
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, '(blocked)')
        Tooltip(NO_LIGHTING_AT_PLAYHEAD_MSG)
    end

    -- ---- Camera pacing ----
    r.ImGui_Spacing(ctx)
    RenderCamPacingRow(_lbl_col, true)

    -- ---- Tools ----
    r.ImGui_Spacing(ctx)
    if Btn('Advance camera pacing', 0) then
        RunAction(AdvanceCameraPacing)
    end
    Tooltip('Move the playhead forward by one camera pacing interval.\n\n' ..
            'Uses the Camera pacing setting above. After advancing, manually pick\n' ..
            'and add the camera event you want at the new position.')

    -- ---- Remove events ----
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Remove')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 130)
    local _rm_labels = { 'Camera', 'Lighting', 'Post proc', 'Special', 'All' }
    local _rm_prev   = _rm_labels[S.venue_mg_remove_type + 1] or 'Camera'
    if r.ImGui_BeginCombo(ctx, '##mg_rm_type', _rm_prev) then
        for _ri, _rl in ipairs(_rm_labels) do
            local _rsel = (_ri - 1 == S.venue_mg_remove_type)
            if r.ImGui_Selectable(ctx, _rl, _rsel) then
                S.venue_mg_remove_type = _ri - 1
            end
            if _rsel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    local _rm_tips = {
        'Removes all [coop_*] and [directed_*] camera events.',
        'Removes all [lighting (...)] events.',
        'Removes all post-process [*.pp] events.',
        'Removes [bonusfx], [bonusfx_optional], [first], [next], and [previous] events.',
        'Removes all camera, lighting, post-process, and special events.',
    }
    Tooltip((_rm_tips[S.venue_mg_remove_type + 1] or '') ..
            '\n\nRespects time selection if active. Fully undoable.')
    r.ImGui_SameLine(ctx)
    if Btn('Remove##mg_rm', 0) then
        local _type = S.venue_mg_remove_type
        RunAction(function() RemoveVenueEventsByType(_type) end)
    end

end
