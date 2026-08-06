-- Venue > Section gen sub-tab
-- Per-section venue event generation: pick a [prc_*] section, configure its
-- lighting/postproc/dircut/bonusfx (or use a template theme), and generate.
-- Requires globals: r, ctx, S, TIPS, Tooltip, SliderTooltip, RunAction,
--                   RenderCamPacingRow, RenderKeyframeAlignCombo,
--                   LoadVenueSections, GenerateSectionEvent, SectionKey,
--                   DefaultConfig, DIRECTED_DISPLAY, DIRECTED_LABELS, DIRECTED_TIPS,
--                   LIGHTING_DISPLAY_GROUPS, LIGHTING_LABELS, LIGHTING_TIPS,
--                   POSTPROC_DISPLAY, POSTPROC_LABELS, POSTPROC_TIPS,
--                   VenueEventTooltip, ComboGroupHeader

function DrawVenueSectionGenTab()
    local lbl_col = LabelColWidth({
        'Mode', 'Section', 'Theme', 'Lighting', 'Keyframe align', 'Keyframe rate',
        'Light blendin', 'Post-process', 'PP blendin', 'Directed cut',
        'Bonus FX', 'Camera pacing',
    })

    r.ImGui_TextWrapped(ctx, 'Generate venue events for a single section by defining the style or using a theme')
    r.ImGui_Spacing(ctx)

    -- Helper: section display label with measure range
    local function _sec_lbl(s)
        local cn = s.name:sub(1,1):upper() .. s.name:sub(2)
        local nm = s.num and (cn .. ' ' .. s.num) or cn
        local ms = r.format_timestr_pos(s.t_start, '', 1):match('^(%d+)') or '?'
        local me = r.format_timestr_pos(s.t_end,   '', 1):match('^(%d+)') or '?'
        return nm .. ' (m' .. ms .. '-m' .. me .. ')'
    end

    -- Section selector row
    r.ImGui_Text(ctx, 'Section')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 260)
    local _vsec_secs  = S.venue_sections
    local _vsec_count = _vsec_secs and #_vsec_secs or 0
    local _vsec_prev  = _vsec_count > 0
        and _sec_lbl(_vsec_secs[S.venue_sec_idx])
        or '(no sections loaded)'
    if r.ImGui_BeginCombo(ctx, '##vsec', _vsec_prev) then
        for _si, _ss in ipairs(_vsec_secs or {}) do
            local _ssel = (_si == S.venue_sec_idx)
            if r.ImGui_Selectable(ctx, _sec_lbl(_ss), _ssel) then
                S.venue_sec_idx = _si
            end
            if _ssel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    r.ImGui_SameLine(ctx)
    if Btn('Refresh##vsec_refresh', 0) then
        LoadVenueSections()
    end
    Tooltip(TIPS.venue_sec_section)

    local _sg_no_sections = not S.venue_sections or #S.venue_sections == 0
    if _sg_no_sections then
        r.ImGui_TextDisabled(ctx, 'No [prc_*] sections found - add markers to the EVENTS track')
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Custom', S.venue_sec_mode == 0) then
        S.venue_sec_mode = 0
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Template', S.venue_sec_mode == 1) then
        S.venue_sec_mode = 1
    end

    -- Custom mode panel
    if S.venue_sec_mode == 0 then
    if _vsec_count > 0 and S.venue_sec_idx >= 1 and S.venue_sec_idx <= _vsec_count then
        local _sec = _vsec_secs[S.venue_sec_idx]
        local _key = SectionKey(_sec)
        if not S.venue_sec_configs[_key] then
            S.venue_sec_configs[_key] = DefaultConfig()
        end
        local _cfg = S.venue_sec_configs[_key]

        r.ImGui_Spacing(ctx)
        SectionHeader(_sec_lbl(_sec))

        -- Manual lighting flag (drives keyframe and blendin visibility)
        local _is_manual = _cfg.lighting ~= '' and
            MANUAL_LIGHTING_SET['[lighting (' .. _cfg.lighting .. ')]']

        -- Lighting combo
        r.ImGui_Text(ctx, 'Lighting')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        local _lt_prev = _cfg.lighting ~= ''
            and (LIGHTING_LABELS[_cfg.lighting] or _cfg.lighting)
            or '(none)'
        if r.ImGui_BeginCombo(ctx, '##vsec_lt', _lt_prev) then
            if r.ImGui_Selectable(ctx, '(none)', _cfg.lighting == '') then
                _cfg.lighting = ''
            end
            if _cfg.lighting == '' then r.ImGui_SetItemDefaultFocus(ctx) end
            for _, _ltgrp in ipairs(LIGHTING_DISPLAY_GROUPS) do
                ComboGroupHeader(_ltgrp.name)
                for _, _ltn in ipairs(_ltgrp.names) do
                    local _lsel = (_cfg.lighting == _ltn)
                    if r.ImGui_Selectable(ctx, LIGHTING_LABELS[_ltn] or _ltn, _lsel) then
                        _cfg.lighting = _ltn
                    end
                    if _lsel then r.ImGui_SetItemDefaultFocus(ctx) end
                    if r.ImGui_IsItemHovered(ctx) then
                        VenueEventTooltip('Lighting', _ltn, LIGHTING_TIPS[_ltn])
                    end
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then
            VenueEventTooltip('Lighting', _cfg.lighting, LIGHTING_TIPS[_cfg.lighting],
                              { intro = TIPS.venue_sec_lighting,
                                label = LIGHTING_LABELS[_cfg.lighting] or _cfg.lighting })
        end

        -- Keyframe align (per-section; disabled for auto/no lighting)
        local _kfa_labels = KF_ALIGN_LABELS  -- shared with the other gen tabs (venue_lighting.lua)
        local _kf_dis = not _is_manual
        if _kf_dis then r.ImGui_BeginDisabled(ctx) end
        r.ImGui_Text(ctx, 'Keyframe align')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        local _kfa_preview = _kfa_labels[S.venue_keyframe_align + 1] or _kfa_labels[1]
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
            if r.ImGui_RadioButton(ctx, 'Every beat##kfis', S.venue_kf_inst_subdiv == 0) then
                S.venue_kf_inst_subdiv = 0
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, 'Every half beat##kfis', S.venue_kf_inst_subdiv == 1) then
                S.venue_kf_inst_subdiv = 1
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, 'Every quarter beat##kfis', S.venue_kf_inst_subdiv == 2) then
                S.venue_kf_inst_subdiv = 2
            end
            Tooltip(TIPS.venue_kf_inst_subdiv)
        end
        if _kf_dis then r.ImGui_EndDisabled(ctx) end

        -- Keyframe rate (only for manual lighting presets)
        if _is_manual then
            r.ImGui_Text(ctx, 'Keyframe rate')
            r.ImGui_SameLine(ctx, lbl_col)
            r.ImGui_SetNextItemWidth(ctx, 120)
            _, _cfg.keyframe_rate = r.ImGui_SliderInt(
                ctx, '##vsec_kr', _cfg.keyframe_rate, 1, 8)
            SliderTooltip(TIPS.venue_sec_kr)
        end

        -- Light blendin
        r.ImGui_Text(ctx, 'Light blendin')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, 120)
        _, _cfg.light_blendin = r.ImGui_SliderInt(
            ctx, '##vsec_ltb', _cfg.light_blendin, 0, 8)
        SliderTooltip(TIPS.venue_sec_lt_blend)

        -- Postproc combo
        r.ImGui_Text(ctx, 'Post-process')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, 240)
        local _pp_prev = _cfg.postproc ~= ''
            and (POSTPROC_LABELS[_cfg.postproc] or _cfg.postproc)
            or '(none)'
        if r.ImGui_BeginCombo(ctx, '##vsec_pp', _pp_prev) then
            if r.ImGui_Selectable(ctx, '(none)', _cfg.postproc == '') then
                _cfg.postproc = ''
            end
            if _cfg.postproc == '' then r.ImGui_SetItemDefaultFocus(ctx) end
            for _, _ppn in ipairs(POSTPROC_DISPLAY) do
                local _psel = (_cfg.postproc == _ppn)
                if r.ImGui_Selectable(ctx, POSTPROC_LABELS[_ppn] or _ppn, _psel) then
                    _cfg.postproc = _ppn
                end
                if _psel then r.ImGui_SetItemDefaultFocus(ctx) end
                if r.ImGui_IsItemHovered(ctx) then
                    VenueEventTooltip('PostProc', _ppn, POSTPROC_TIPS[_ppn])
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then
            VenueEventTooltip('PostProc', _cfg.postproc, POSTPROC_TIPS[_cfg.postproc],
                              { intro = TIPS.venue_sec_postproc,
                                label = POSTPROC_LABELS[_cfg.postproc] or _cfg.postproc })
        end

        -- PP blendin
        r.ImGui_Text(ctx, 'PP blendin')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, 120)
        _, _cfg.pp_blendin = r.ImGui_SliderInt(
            ctx, '##vsec_ppb', _cfg.pp_blendin, 0, 8)
        SliderTooltip(TIPS.venue_sec_pp_blend)

        -- Dircut combo
        r.ImGui_Text(ctx, 'Directed cut')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, 220)
        local _dc_prev = _cfg.dircut ~= ''
            and (DIRECTED_LABELS[_cfg.dircut] or _cfg.dircut)
            or '(none)'
        if r.ImGui_BeginCombo(ctx, '##vsec_dc', _dc_prev) then
            if r.ImGui_Selectable(ctx, '(none)', _cfg.dircut == '') then
                _cfg.dircut = ''
            end
            if _cfg.dircut == '' then r.ImGui_SetItemDefaultFocus(ctx) end
            for _, _dcn in ipairs(DIRECTED_DISPLAY) do
                local _dcsel = (_cfg.dircut == _dcn)
                if r.ImGui_Selectable(ctx, DIRECTED_LABELS[_dcn] or _dcn, _dcsel) then
                    _cfg.dircut = _dcn
                end
                if _dcsel then r.ImGui_SetItemDefaultFocus(ctx) end
                if r.ImGui_IsItemHovered(ctx) then
                    VenueEventTooltip('Camera', _dcn, DIRECTED_TIPS[_dcn])
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then
            VenueEventTooltip('Camera', _cfg.dircut, DIRECTED_TIPS[_cfg.dircut],
                              { intro = TIPS.venue_sec_dircut,
                                label = DIRECTED_LABELS[_cfg.dircut] or _cfg.dircut })
        end

        -- BonusFX checkbox
        r.ImGui_Text(ctx, 'Bonus FX')
        r.ImGui_SameLine(ctx, lbl_col)
        _, _cfg.bonusfx = r.ImGui_Checkbox(ctx, '##vsec_bfx', _cfg.bonusfx)
        Tooltip(TIPS.venue_sec_bonusfx)
    end
    end -- S.venue_sec_mode == 0

    -- Template mode panel
    if S.venue_sec_mode == 1 then
        r.ImGui_Spacing(ctx)
        local _tmpl_no_themes = #S.venue_themes == 0
        if _tmpl_no_themes then
            r.ImGui_TextDisabled(ctx, 'No themes found - add .rbtheme files to the resources/themes/ folder')
            r.ImGui_BeginDisabled(ctx)
        end
        r.ImGui_Text(ctx, 'Theme')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, 240)
        local _tmpl_prev = S.venue_sec_tmpl_idx > 0
            and S.venue_themes[S.venue_sec_tmpl_idx].label
            or '...'
        if r.ImGui_BeginCombo(ctx, '##vsec_tmpl', _tmpl_prev) then
            for i, t in ipairs(S.venue_themes) do
                local is_sel = (i == S.venue_sec_tmpl_idx)
                if r.ImGui_Selectable(ctx, t.label, is_sel) then
                    S.venue_sec_tmpl_idx  = i
                    S.venue_sec_tmpl_name = t.stem
                end
                if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.venue_theme)
        if _vsec_count > 0 and S.venue_sec_idx >= 1 and S.venue_sec_idx <= _vsec_count
            and S.venue_sec_tmpl_idx > 0 then
            local _tmpl_sec = _vsec_secs[S.venue_sec_idx]
            local _th       = S.venue_themes[S.venue_sec_tmpl_idx]
            local _preset   = _th.section_presets and
                (_th.section_presets[_tmpl_sec.name] or _th.section_presets['default'])
            r.ImGui_Spacing(ctx)
            if _preset then
                local _lt_val = _preset.allowed_lightpresets and
                    table.concat(_preset.allowed_lightpresets, ', ') or '-'
                local _pp_val = _preset.allowed_postprocs and
                    table.concat(_preset.allowed_postprocs, ', ') or '-'
                r.ImGui_Text(ctx, 'Lighting')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _lt_val)
                r.ImGui_Text(ctx, 'Post-process')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _pp_val)
                r.ImGui_Text(ctx, 'Keyframe rate')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _preset.keyframe_rate and tostring(_preset.keyframe_rate) or '-')
                r.ImGui_Text(ctx, 'Light blendin')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _preset.lightpreset_blendin and tostring(_preset.lightpreset_blendin) or '-')
                r.ImGui_Text(ctx, 'PP blendin')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _preset.postproc_blendin and tostring(_preset.postproc_blendin) or '-')
                r.ImGui_Text(ctx, 'Directed cut')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _preset.dircut_at_start or '-')
                r.ImGui_Text(ctx, 'Bonus FX')
                r.ImGui_SameLine(ctx, lbl_col)
                r.ImGui_TextDisabled(ctx, _preset.bonusfx_at_start and 'yes' or 'no')
            else
                r.ImGui_TextDisabled(ctx, 'No preset for this section type in the selected theme')
            end
        end
        if _tmpl_no_themes then r.ImGui_EndDisabled(ctx) end
        r.ImGui_Spacing(ctx)
        RenderKeyframeAlignCombo(lbl_col)
    end -- S.venue_sec_mode == 1

    r.ImGui_Spacing(ctx)
    RenderCamPacingRow(lbl_col)

    r.ImGui_Spacing(ctx)
    local _gen_disabled = _sg_no_sections
        or (S.venue_sec_mode == 1 and S.venue_sec_tmpl_idx == 0)
    if _gen_disabled then r.ImGui_BeginDisabled(ctx) end
    if Btn('Generate section', BTN_H) then
        RunAction(GenerateSectionEvent)
    end
    if _gen_disabled then r.ImGui_EndDisabled(ctx) end

end
