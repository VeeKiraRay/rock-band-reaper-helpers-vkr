-- Venue tab rendering

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

    -- Camera pacing widget shared by all generation sub-tabs.
    -- col_offset: if set, use SameLine(col_offset) to align the dropdown with other rows.
    -- hide_theme_default: if true, omit the "Theme default" option (used in Manual gen).
    local function _render_cam_pacing(col_offset, hide_theme_default)
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

    local function _render_kfa_combo()
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

    if r.ImGui_BeginTabBar(ctx, '##venue_subtabs') then

        ------------------------------------------------
        -- Venue > Analysis sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Analysis') then
            local bw_lv = r.ImGui_CalcTextSize(ctx, 'List venue events')   + _bp
            local bw_es = r.ImGui_CalcTextSize(ctx, 'Show event sections') + _bp

            if r.ImGui_Button(ctx, 'List venue events', bw_lv, 24) then
                RunAction(ListVenueEvents)
            end
            Tooltip(TIPS.list_venue)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Show event sections', bw_es, 24) then
                RunAction(ListEventSections)
            end
            Tooltip(TIPS.venue_sections)

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Themes gen sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Themes gen') then
            r.ImGui_TextDisabled(ctx, 'Generate venue events using a .rbtheme for the whole song')
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
            _render_cam_pacing()

            -- Keyframe align (global, applies to all sections in the theme)
            r.ImGui_Spacing(ctx)
            _render_kfa_combo()

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
            r.ImGui_TextDisabled(ctx, 'Generate venue events for a single section by defining the style or using a theme')
            r.ImGui_Spacing(ctx)

            -- Helper: section display label with measure range
            local function _sec_lbl(s)
                local cn = s.name:sub(1,1):upper() .. s.name:sub(2)
                local nm = s.num and (cn .. ' ' .. s.num) or cn
                local ms = r.format_timestr_pos(s.t_start, '', 1):match('^(%d+)') or '?'
                local me = r.format_timestr_pos(s.t_end,   '', 1):match('^(%d+)') or '?'
                return nm .. ' (m' .. ms .. '\xe2\x80\x93m' .. me .. ')'
            end

            -- Build directed name list once per frame (bare names, no brackets)
            local _dir_names = {}
            for _, _dev in ipairs(DIRECTED_POOL) do
                _dir_names[#_dir_names + 1] = _dev:match('^%[(.-)%]$') or _dev
            end

            -- Section selector row
            r.ImGui_Text(ctx, 'Section      ')
            r.ImGui_SameLine(ctx)
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
            local _bw_ref = r.ImGui_CalcTextSize(ctx, 'Refresh') + _bp
            if r.ImGui_Button(ctx, 'Refresh##vsec_refresh', _bw_ref, 0) then
                LoadVenueSections()
            end
            Tooltip(TIPS.venue_sec_section)

            local _sg_no_sections = not S.venue_sections or #S.venue_sections == 0
            if _sg_no_sections then
                r.ImGui_TextDisabled(ctx, 'No [prc_*] sections found \xe2\x80\x94 add markers to the EVENTS track')
            end

            r.ImGui_Spacing(ctx)
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
                r.ImGui_Text(ctx, 'Lighting     ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                local _lt_prev = _cfg.lighting ~= ''
                    and (LIGHTING_LABELS[_cfg.lighting] or _cfg.lighting)
                    or '(none)'
                if r.ImGui_BeginCombo(ctx, '##vsec_lt', _lt_prev) then
                    if r.ImGui_Selectable(ctx, '(none)', _cfg.lighting == '') then
                        _cfg.lighting = ''
                    end
                    if _cfg.lighting == '' then r.ImGui_SetItemDefaultFocus(ctx) end
                    for _, _ltn in ipairs(LIGHTING_NAMES) do
                        local _lsel = (_cfg.lighting == _ltn)
                        if r.ImGui_Selectable(ctx, LIGHTING_LABELS[_ltn] or _ltn, _lsel) then
                            _cfg.lighting = _ltn
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
                if r.ImGui_IsItemHovered(ctx) then
                    if BeginVenueTooltip() then
                        if _cfg.lighting ~= '' then
                            DrawVenueTooltipSprite('Lighting', _cfg.lighting)
                        end
                        r.ImGui_Text(ctx, TIPS.venue_sec_lighting)
                        if _cfg.lighting ~= '' and LIGHTING_TIPS[_cfg.lighting] then
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, (LIGHTING_LABELS[_cfg.lighting] or _cfg.lighting)
                                             .. ':\n' .. LIGHTING_TIPS[_cfg.lighting])
                        end
                        EndVenueTooltip()
                    end
                end

                -- Keyframe align (per-section; disabled for auto/no lighting)
                local _kfa_labels = {
                    'Section start', 'Closest beat', 'Downbeat',
                    'Guitar notes', 'Bass notes', 'Keys notes',
                    'Drum kicks', 'Drum snare',
                }
                local _kf_dis = not _is_manual
                if _kf_dis then r.ImGui_BeginDisabled(ctx) end
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
                    if r.ImGui_RadioButton(ctx, 'Every beat##kfis', S.venue_kf_inst_subdiv == 0) then
                        S.venue_kf_inst_subdiv = 0
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, 'Every half beat##kfis', S.venue_kf_inst_subdiv == 1) then
                        S.venue_kf_inst_subdiv = 1
                    end
                    Tooltip(TIPS.venue_kf_inst_subdiv)
                end
                if _kf_dis then r.ImGui_EndDisabled(ctx) end

                -- Keyframe rate (only for manual lighting presets)
                if _is_manual then
                    r.ImGui_Text(ctx, 'Keyframe rate')
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 120)
                    _, _cfg.keyframe_rate = r.ImGui_SliderInt(
                        ctx, '##vsec_kr', _cfg.keyframe_rate, 1, 8)
                    SliderTooltip(TIPS.venue_sec_kr)
                end

                -- Light blendin
                r.ImGui_Text(ctx, 'Light blendin')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 120)
                _, _cfg.light_blendin = r.ImGui_SliderInt(
                    ctx, '##vsec_ltb', _cfg.light_blendin, 0, 8)
                SliderTooltip(TIPS.venue_sec_lt_blend)

                -- Postproc combo
                r.ImGui_Text(ctx, 'Post-process ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 240)
                local _pp_prev = _cfg.postproc ~= ''
                    and (POSTPROC_LABELS[_cfg.postproc] or _cfg.postproc)
                    or '(none)'
                if r.ImGui_BeginCombo(ctx, '##vsec_pp', _pp_prev) then
                    if r.ImGui_Selectable(ctx, '(none)', _cfg.postproc == '') then
                        _cfg.postproc = ''
                    end
                    if _cfg.postproc == '' then r.ImGui_SetItemDefaultFocus(ctx) end
                    for _, _ppn in ipairs(POSTPROC_NAMES) do
                        local _psel = (_cfg.postproc == _ppn)
                        if r.ImGui_Selectable(ctx, POSTPROC_LABELS[_ppn] or _ppn, _psel) then
                            _cfg.postproc = _ppn
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
                if r.ImGui_IsItemHovered(ctx) then
                    if BeginVenueTooltip() then
                        if _cfg.postproc ~= '' then
                            DrawVenueTooltipSprite('PostProc', _cfg.postproc)
                        end
                        r.ImGui_Text(ctx, TIPS.venue_sec_postproc)
                        if _cfg.postproc ~= '' and POSTPROC_TIPS[_cfg.postproc] then
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, (POSTPROC_LABELS[_cfg.postproc] or _cfg.postproc)
                                             .. ':\n' .. POSTPROC_TIPS[_cfg.postproc])
                        end
                        EndVenueTooltip()
                    end
                end

                -- PP blendin
                r.ImGui_Text(ctx, 'PP blendin   ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 120)
                _, _cfg.pp_blendin = r.ImGui_SliderInt(
                    ctx, '##vsec_ppb', _cfg.pp_blendin, 0, 8)
                SliderTooltip(TIPS.venue_sec_pp_blend)

                -- Dircut combo
                r.ImGui_Text(ctx, 'Directed cut ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 220)
                local _dc_prev = _cfg.dircut ~= ''
                    and (DIRECTED_LABELS[_cfg.dircut] or _cfg.dircut)
                    or '(none)'
                if r.ImGui_BeginCombo(ctx, '##vsec_dc', _dc_prev) then
                    if r.ImGui_Selectable(ctx, '(none)', _cfg.dircut == '') then
                        _cfg.dircut = ''
                    end
                    if _cfg.dircut == '' then r.ImGui_SetItemDefaultFocus(ctx) end
                    for _, _dcn in ipairs(_dir_names) do
                        local _dcsel = (_cfg.dircut == _dcn)
                        if r.ImGui_Selectable(ctx, DIRECTED_LABELS[_dcn] or _dcn, _dcsel) then
                            _cfg.dircut = _dcn
                        end
                        if _dcsel then r.ImGui_SetItemDefaultFocus(ctx) end
                        if r.ImGui_IsItemHovered(ctx) then
                            if BeginVenueTooltip() then
                                DrawVenueTooltipSprite('Camera', _dcn)
                                if DIRECTED_TIPS[_dcn] then
                                    r.ImGui_Text(ctx, DIRECTED_TIPS[_dcn])
                                end
                                EndVenueTooltip()
                            end
                        end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                if r.ImGui_IsItemHovered(ctx) then
                    if BeginVenueTooltip() then
                        if _cfg.dircut ~= '' then
                            DrawVenueTooltipSprite('Camera', _cfg.dircut)
                        end
                        r.ImGui_Text(ctx, TIPS.venue_sec_dircut)
                        if _cfg.dircut ~= '' and DIRECTED_TIPS[_cfg.dircut] then
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, (DIRECTED_LABELS[_cfg.dircut] or _cfg.dircut)
                                             .. ':\n' .. DIRECTED_TIPS[_cfg.dircut])
                        end
                        EndVenueTooltip()
                    end
                end

                -- BonusFX checkbox
                r.ImGui_Text(ctx, 'Bonus FX     ')
                r.ImGui_SameLine(ctx)
                _, _cfg.bonusfx = r.ImGui_Checkbox(ctx, '##vsec_bfx', _cfg.bonusfx)
                Tooltip(TIPS.venue_sec_bonusfx)
            end
            end -- S.venue_sec_mode == 0

            -- Template mode panel
            if S.venue_sec_mode == 1 then
                r.ImGui_Spacing(ctx)
                local _tmpl_no_themes = #S.venue_themes == 0
                if _tmpl_no_themes then
                    r.ImGui_TextDisabled(ctx, 'No themes found \xe2\x80\x94 add .rbtheme files to the resources/themes/ folder')
                    r.ImGui_BeginDisabled(ctx)
                end
                r.ImGui_Text(ctx, 'Theme')
                r.ImGui_SameLine(ctx)
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
                            table.concat(_preset.allowed_lightpresets, ', ') or '\xe2\x80\x94'
                        local _pp_val = _preset.allowed_postprocs and
                            table.concat(_preset.allowed_postprocs, ', ') or '\xe2\x80\x94'
                        r.ImGui_Text(ctx, 'Lighting     ')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _lt_val)
                        r.ImGui_Text(ctx, 'Post-process ')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _pp_val)
                        r.ImGui_Text(ctx, 'Keyframe rate')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _preset.keyframe_rate and tostring(_preset.keyframe_rate) or '\xe2\x80\x94')
                        r.ImGui_Text(ctx, 'Light blendin')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _preset.lightpreset_blendin and tostring(_preset.lightpreset_blendin) or '\xe2\x80\x94')
                        r.ImGui_Text(ctx, 'PP blendin   ')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _preset.postproc_blendin and tostring(_preset.postproc_blendin) or '\xe2\x80\x94')
                        r.ImGui_Text(ctx, 'Directed cut ')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _preset.dircut_at_start or '\xe2\x80\x94')
                        r.ImGui_Text(ctx, 'Bonus FX     ')
                        r.ImGui_SameLine(ctx)
                        r.ImGui_TextDisabled(ctx, _preset.bonusfx_at_start and 'yes' or 'no')
                    else
                        r.ImGui_TextDisabled(ctx, 'No preset for this section type in the selected theme')
                    end
                end
                if _tmpl_no_themes then r.ImGui_EndDisabled(ctx) end
                r.ImGui_Spacing(ctx)
                _render_kfa_combo()
            end -- S.venue_sec_mode == 1

            r.ImGui_Spacing(ctx)
            _render_cam_pacing()

            r.ImGui_Spacing(ctx)
            local _gen_disabled = _sg_no_sections
                or (S.venue_sec_mode == 1 and S.venue_sec_tmpl_idx == 0)
            if _gen_disabled then r.ImGui_BeginDisabled(ctx) end
            local bw_gs = r.ImGui_CalcTextSize(ctx, 'Generate section') + _bp
            if r.ImGui_Button(ctx, 'Generate section', bw_gs, 24) then
                RunAction(GenerateSectionEvent)
            end
            if _gen_disabled then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Venue > Manual gen sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Manual gen') then
            r.ImGui_TextDisabled(ctx, 'Insert individual venue events at the playhead position')
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

            local _bp_add  = r.ImGui_CalcTextSize(ctx, 'Add') + _bp
            local _lbl_col = r.ImGui_CalcTextSize(ctx, 'Directed camera') + 16

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
            if r.ImGui_Button(ctx, 'Add##mg_coop_add', _bp_add, 0) then
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
            if r.ImGui_Button(ctx, 'Add##mg_dir_add', _bp_add, 0) then
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
            if r.ImGui_Button(ctx, 'Add##mg_lt_add', _bp_add, 0) then
                local _ev = '[lighting (' .. S.venue_mg_lighting .. ')]'
                RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
            end
            if _mg_lt_dis then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            local _mg_is_manual = S.venue_mg_lighting ~= '' and
                MANUAL_LIGHTING_SET['[lighting (' .. S.venue_mg_lighting .. ')]']
            local _gkf_dis = not _mg_is_manual
            if _gkf_dis then r.ImGui_BeginDisabled(ctx) end
            local _bw_kf = r.ImGui_CalcTextSize(ctx, 'Keyframes') + _bp
            if r.ImGui_Button(ctx, 'Keyframes##mg_kf_btn', _bw_kf, 0) then
                RunAction(GenerateManualKeyframes)
            end
            Tooltip('Generate [first]/[next] keyframe events from the playhead to the next\n' ..
                    'lighting event, the time selection end (if active), or the VENUE item end.\n\n' ..
                    'Clears any existing [first]/[next]/[previous] events in that range first.\n' ..
                    'Only available when a manual lighting preset is selected above.\n' ..
                    'Fully undoable.')
            if _gkf_dis then r.ImGui_EndDisabled(ctx) end

            -- Keyframe settings (shown only when a manual lighting preset is selected)
            local _kf_dis = not _mg_is_manual
            if _kf_dis then r.ImGui_BeginDisabled(ctx) end

            r.ImGui_Text(ctx, 'Keyframe align')
            r.ImGui_SameLine(ctx, _lbl_col)
            r.ImGui_SetNextItemWidth(ctx, 170)
            local _mg_kfa_labels = {
                'Playhead', 'Closest beat', 'Downbeat',
                'Guitar notes', 'Bass notes', 'Keys notes',
                'Drum kicks', 'Drum snare',
            }
            local _mg_kfa_prev = _mg_kfa_labels[S.venue_keyframe_align + 1] or 'Playhead'
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
            Tooltip('Where the [first]/[next] keyframe sequence begins.\n\n' ..
                    'Playhead:      [first] at the current edit cursor position.\n' ..
                    'Closest beat:  snapped to the nearest beat boundary.\n' ..
                    'Downbeat:      [first] at cursor; [next] from the next measure start.\n\n' ..
                    'Instrument modes emit [next] only at beats (or half-beats) where\n' ..
                    'qualifying notes actually exist on the named track:\n' ..
                    '  Guitar notes \xe2\x80\x93 PART GUITAR (pitches 96\xe2\x80\x93100)\n' ..
                    '  Bass notes   \xe2\x80\x93 PART BASS   (pitches 96\xe2\x80\x93100)\n' ..
                    '  Keys notes   \xe2\x80\x93 PART KEYS   (pitches 96\xe2\x80\x93100)\n' ..
                    '  Drum kicks   \xe2\x80\x93 PART DRUMS  (pitch 96)\n' ..
                    '  Drum snare   \xe2\x80\x93 PART DRUMS  (pitch 97)')
            if S.venue_keyframe_align >= 3 then
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Every beat##mg_kfis', S.venue_kf_inst_subdiv == 0) then
                    S.venue_kf_inst_subdiv = 0
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Every half beat##mg_kfis', S.venue_kf_inst_subdiv == 1) then
                    S.venue_kf_inst_subdiv = 1
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
            if r.ImGui_Button(ctx, 'Add##mg_pp_add', _bp_add, 0) then
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
            if r.ImGui_Button(ctx, 'Add##mg_sp_add', _bp_add, 0) then
                local _ev = S.venue_mg_special
                RunAction(function() InsertVenueEventAtPlayhead(_ev) end)
            end
            if _mg_sp_dis then r.ImGui_EndDisabled(ctx) end

            -- ---- Camera pacing ----
            r.ImGui_Spacing(ctx)
            _render_cam_pacing(_lbl_col, true)

            -- ---- Tools ----
            r.ImGui_Spacing(ctx)
            local bw_adv = r.ImGui_CalcTextSize(ctx, 'Advance camera pacing') + _bp
            if r.ImGui_Button(ctx, 'Advance camera pacing', bw_adv, 0) then
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
            r.ImGui_SameLine(ctx)
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
            local bw_rm = r.ImGui_CalcTextSize(ctx, 'Remove') + _bp
            if r.ImGui_Button(ctx, 'Remove##mg_rm', bw_rm, 0) then
                local _type = S.venue_mg_remove_type
                RunAction(function() RemoveVenueEventsByType(_type) end)
            end

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
    end
end
