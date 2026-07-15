-- Venue tab rendering

-- Camera pacing widget shared by all generation sub-tabs.
-- col_offset: if set, use SameLine(col_offset) to align the dropdown with other rows.
-- hide_theme_default: if true, omit the "Theme default" option (used in Manual gen).
function RenderCamPacingRow(col_offset, hide_theme_default)
    local _interval_to_name = {[4]='crazy',[8]='fast',[16]='medium',[24]='slow',[32]='minimal'}
    local _cp_td_suffix = ''
    if S.venue_cam_pacing == 0 and not hide_theme_default then
        local _th  = S.venue_themes and S.venue_theme_idx > 0 and S.venue_themes[S.venue_theme_idx]
        local _cpn = (_th and _th.camera_pacing)
                     or _interval_to_name[CAM_INTERVAL_16THS]
                     or (CAM_INTERVAL_16THS .. ' 16ths')
        _cp_td_suffix = ' (' .. _cpn .. ')'
    end
    local _cp_short  = {'Theme default', 'Minimal', 'Slow', 'Medium', 'Fast', 'Crazy', 'Custom'}
    local _cp_labels = {
        'Theme default' .. _cp_td_suffix,
        'Minimal (32 16ths, ~2 bars @ 120)',
        'Slow (24 16ths)',
        'Medium (16 16ths)',
        'Fast (8 16ths)',
        'Crazy (4 16ths, ~1 beat @ 120)',
        'Custom (' .. S.venue_cam_pacing_custom .. ' 16ths)',
    }
    local _cp_preview
    if hide_theme_default and S.venue_cam_pacing == 0 then
        -- CAM_INTERVAL_16THS = 24 (Slow) is the effective fallback; make it explicit
        local _fn = _interval_to_name[CAM_INTERVAL_16THS] or (CAM_INTERVAL_16THS .. ' 16ths')
        _cp_preview = _fn:sub(1,1):upper() .. _fn:sub(2) .. ' (' .. CAM_INTERVAL_16THS .. ' 16ths)'
    else
        _cp_preview = (_cp_short[S.venue_cam_pacing + 1] or 'Theme default') .. _cp_td_suffix
    end
    r.ImGui_Text(ctx, 'Camera pacing')
    if col_offset then
        r.ImGui_SameLine(ctx, col_offset)
    else
        r.ImGui_SameLine(ctx)
    end
    r.ImGui_SetNextItemWidth(ctx, 160)
    if r.ImGui_BeginCombo(ctx, '##vcpac', _cp_preview) then
        local _ci_start = hide_theme_default and 2 or 1
        for _ci = _ci_start, #_cp_labels do
            local _cl   = _cp_labels[_ci]
            local _csel = (_ci - 1 == S.venue_cam_pacing)
            if r.ImGui_Selectable(ctx, _cl, _csel) then
                S.venue_cam_pacing = _ci - 1
            end
            if _csel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.venue_cam_pacing)
    r.ImGui_SameLine(ctx)
    _, S.venue_cam_pacing_jitter = r.ImGui_Checkbox(ctx, 'Include jitter##vcpacj', S.venue_cam_pacing_jitter)
    Tooltip(TIPS.venue_cam_pacing_jitter)
    if S.venue_cam_pacing == 6 then
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Custom interval')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 160)
        _, S.venue_cam_pacing_custom = r.ImGui_SliderInt(
            ctx, '##vcpac_custom', S.venue_cam_pacing_custom, 2, 128)
        SliderTooltip(TIPS.venue_cam_pacing_custom)
    end
end

function RenderKeyframeAlignCombo()
    local _kfa_labels = {
        'Section start', 'Closest beat', 'Downbeat',
        'Guitar notes', 'Bass notes', 'Keys notes',
        'Drum kicks', 'Drum snare',
    }
    r.ImGui_Text(ctx, 'Keyframe align')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 170)
    local _kfa_preview = _kfa_labels[S.venue_keyframe_align + 1] or 'Section start'
    if r.ImGui_BeginCombo(ctx, '##vkfa', _kfa_preview) then
        for _ki, _kl in ipairs(_kfa_labels) do
            local _ksel = (_ki - 1 == S.venue_keyframe_align)
            if r.ImGui_Selectable(ctx, _kl, _ksel) then
                S.venue_keyframe_align = _ki - 1
            end
            if _ksel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.venue_keyframe_align)
    if S.venue_keyframe_align >= 3 then
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Subdivision    ')
        r.ImGui_SameLine(ctx)
        local _t_kfis = TIPS.venue_kf_inst_subdiv
        if r.ImGui_RadioButton(ctx, 'Every beat##kfis', S.venue_kf_inst_subdiv == 0) then
            S.venue_kf_inst_subdiv = 0
        end
        Tooltip(_t_kfis)
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every half beat##kfis', S.venue_kf_inst_subdiv == 1) then
            S.venue_kf_inst_subdiv = 1
        end
        Tooltip(_t_kfis)
    end
end

function DrawVenueTab(ctx)
    local _bp = 40

    -- Lazy-load themes on first Venue tab open
    if S.venue_themes == nil then
        S.venue_themes = LoadVenueThemes(SCRIPT_DIR .. 'resources/themes/')
        if S.venue_theme_name ~= '' then
            for i, t in ipairs(S.venue_themes) do
                if t.stem == S.venue_theme_name then
                    S.venue_theme_idx = i
                    break
                end
            end
        end
        if S.venue_sec_tmpl_name ~= '' then
            for i, t in ipairs(S.venue_themes) do
                if t.stem == S.venue_sec_tmpl_name then
                    S.venue_sec_tmpl_idx = i
                    break
                end
            end
        end
        if S.venue_theme_idx == 0 and #S.venue_themes > 0 then
            S.venue_theme_idx  = 1
            S.venue_theme_name = S.venue_themes[1].stem
        end
        if S.venue_sec_tmpl_idx == 0 and #S.venue_themes > 0 then
            S.venue_sec_tmpl_idx  = 1
            S.venue_sec_tmpl_name = S.venue_themes[1].stem
        end
        LoadVenueSections()
    end


    if r.ImGui_BeginTabBar(ctx, '##venue_subtabs') then

        ------------------------------------------------
        -- Venue > Actions sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Actions') then
            local bw_lv = r.ImGui_CalcTextSize(ctx, 'List venue events')       + _bp
            local bw_es = r.ImGui_CalcTextSize(ctx, 'List event sections')    + _bp
            local bw_lp = r.ImGui_CalcTextSize(ctx, 'List lighting/postproc') + _bp
            local bw_sa = r.ImGui_CalcTextSize(ctx, 'Generate sing along')    + _bp

            if r.ImGui_Button(ctx, 'List venue events', bw_lv, 24) then
                RunAction(ListVenueEvents)
            end
            Tooltip(TIPS.list_venue)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'List event sections', bw_es, 24) then
                RunAction(ListEventSections)
            end
            Tooltip(TIPS.venue_sections)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'List lighting/postproc', bw_lp, 24) then
                RunAction(ListLightingPostProcEvents)
            end
            Tooltip(TIPS.venue_lighting_postproc)
            if r.ImGui_Button(ctx, 'Generate sing along', bw_sa, 24) then
                RunAction(GenerateSingAlong)
            end
            Tooltip(TIPS.venue_sing_along)

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Events sub-tab (ui_venue_events.lua)
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Events') then
            DrawVenueEventsTab()
            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Themes gen sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Themes gen') then
            r.ImGui_Text(ctx, 'Generate venue events using a .rbtheme for the whole song')
            r.ImGui_Spacing(ctx)

            local _no_themes = #S.venue_themes == 0
            if _no_themes then
                r.ImGui_TextDisabled(ctx, 'No themes found \xe2\x80\x94 add .rbtheme files to the resources/themes/ folder')
                r.ImGui_BeginDisabled(ctx)
            end
            local _no_sections = not S.venue_sections or #S.venue_sections == 0
            if _no_sections then
                r.ImGui_TextDisabled(ctx, 'Add [prc_*] markers to the EVENTS track for section-based generation')
                r.ImGui_Spacing(ctx)
            end

            -- Theme combo
            local _tg_preview = S.venue_theme_idx > 0
                and S.venue_themes[S.venue_theme_idx].label
                or '(select a theme)'
            r.ImGui_Text(ctx, 'Theme')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 240)
            if r.ImGui_BeginCombo(ctx, '##venue_theme', _tg_preview) then
                for i, t in ipairs(S.venue_themes) do
                    local is_sel = (i == S.venue_theme_idx)
                    if r.ImGui_Selectable(ctx, t.label, is_sel) then
                        S.venue_theme_idx  = i
                        S.venue_theme_name = t.stem
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end
            Tooltip(TIPS.venue_theme)

            r.ImGui_Spacing(ctx)
            RenderCamPacingRow()

            -- Keyframe align (global, applies to all sections in the theme)
            r.ImGui_Spacing(ctx)
            RenderKeyframeAlignCombo()

            r.ImGui_Spacing(ctx)
            local _tg_no_sel = S.venue_theme_idx == 0
            if _tg_no_sel then r.ImGui_BeginDisabled(ctx) end
            local bw_gv = r.ImGui_CalcTextSize(ctx, 'Generate venue events') + _bp
            if r.ImGui_Button(ctx, 'Generate venue events', bw_gv, 24) then
                RunAction(GenerateVenueEvents)
            end
            Tooltip(TIPS.venue_generate)
            if _tg_no_sel then r.ImGui_EndDisabled(ctx) end

            if _no_themes then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Section gen sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Section gen') then
            DrawVenueSectionGenTab()
            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Manual gen sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Manual gen') then
            DrawVenueManualTab()
            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Keyframes sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Keyframes') then
            DrawVenueKeyframesTab()
            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Preview sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Preview') then
            DrawVenuePreviewTab()
            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
        DrawActivePlayersRow()
    end
end
