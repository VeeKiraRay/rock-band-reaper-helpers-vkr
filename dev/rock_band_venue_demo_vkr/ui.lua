-- UI and main loop for the Venue Demo generator.
-- Requires: r, ctx, S, TIPS, LIGHTING_NAMES, LIGHTING_LABELS, POSTPROC_NAMES,
--           POSTPROC_LABELS, COOP_POOL, DIRECTED_POOL, GenerateDemoVenue,
--           DirectedRequired, CoopRequired, MutedFromCombo (globals)

local WIN_W = 480
local WIN_H = 520

local function CoopLabel(ev)
    -- Strip brackets and make readable: [coop_all_far] → coop_all_far
    return ev:match('^%[(.-)%]$') or ev
end

local function DrawUI()
    local _bp = 40

    r.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band Venue Demo', true)
    if not visible then return open end

    -- Mode selector
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Camera##dm',   S.demo_mode == DEMO_MODE_CAMERA)   then S.demo_mode = DEMO_MODE_CAMERA   end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Coop##dm',     S.demo_mode == DEMO_MODE_COOP)     then S.demo_mode = DEMO_MODE_COOP     end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Lighting##dm', S.demo_mode == DEMO_MODE_LIGHTING) then S.demo_mode = DEMO_MODE_LIGHTING end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'PostProc##dm', S.demo_mode == DEMO_MODE_POSTPROC) then S.demo_mode = DEMO_MODE_POSTPROC end
    Tooltip(TIPS.demo_mode)

    r.ImGui_Spacing(ctx)

    -- BPM slider
    r.ImGui_Text(ctx, 'BPM         ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 180)
    _, S.demo_bpm = r.ImGui_SliderInt(ctx, '##demo_bpm', S.demo_bpm, 40, 200)
    SliderTooltip(TIPS.demo_bpm)

    -- Window length
    local _bpm_safe = math.max(40, S.demo_bpm)
    if S.demo_mode == DEMO_MODE_CAMERA then
        local cam_win_s = 4.0 * 4.0 * (60.0 / _bpm_safe)
        r.ImGui_TextDisabled(ctx, string.format('Spacing: 4 measures (%.1f s at %d BPM)', cam_win_s, S.demo_bpm))
        Tooltip(TIPS.demo_window_s_camera)
    elseif S.demo_mode == DEMO_MODE_COOP then
        local coop_win_s = 2.0 * 4.0 * (60.0 / _bpm_safe)
        r.ImGui_TextDisabled(ctx, string.format('Spacing: 2 measures (%.1f s at %d BPM)', coop_win_s, S.demo_bpm))
        Tooltip(TIPS.demo_window_s_coop)
    else
        r.ImGui_Text(ctx, 'Window (s)  ')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 180)
        _, S.demo_window_s = r.ImGui_SliderDouble(ctx, '##demo_win', S.demo_window_s, 2.0, 12.0, '%.1f s')
        SliderTooltip(TIPS.demo_window_s)
    end

    -- Players (Camera + Coop modes): filter by which two instruments are present
    if S.demo_mode == DEMO_MODE_CAMERA or S.demo_mode == DEMO_MODE_COOP then
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Players     ')
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Bass + Guitar##combo', S.demo_cam_combo == DEMO_CAM_COMBO_BG) then
            S.demo_cam_combo = DEMO_CAM_COMBO_BG
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Bass + Keys##combo', S.demo_cam_combo == DEMO_CAM_COMBO_BK) then
            S.demo_cam_combo = DEMO_CAM_COMBO_BK
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Guitar + Keys##combo', S.demo_cam_combo == DEMO_CAM_COMBO_GK) then
            S.demo_cam_combo = DEMO_CAM_COMBO_GK
        end
        Tooltip(TIPS.demo_cam_combo)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    local mode = S.demo_mode

    -- Neutral lighting combo (Camera + Coop + PostProc modes)
    if mode == DEMO_MODE_CAMERA or mode == DEMO_MODE_COOP or mode == DEMO_MODE_POSTPROC then
        local lt_preview = LIGHTING_LABELS[LIGHTING_NAMES[S.demo_lt_idx]] or LIGHTING_NAMES[S.demo_lt_idx] or '?'
        r.ImGui_Text(ctx, 'Lighting    ')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 210)
        if r.ImGui_BeginCombo(ctx, '##demo_lt', lt_preview) then
            for i, ltn in ipairs(LIGHTING_NAMES) do
                local sel = (i == S.demo_lt_idx)
                if r.ImGui_Selectable(ctx, LIGHTING_LABELS[ltn] or ltn, sel) then
                    S.demo_lt_idx = i
                end
                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.demo_lt_idx)
    end

    -- Neutral postproc combo (Camera + Coop + Lighting modes)
    if mode == DEMO_MODE_CAMERA or mode == DEMO_MODE_COOP or mode == DEMO_MODE_LIGHTING then
        local pp_preview = POSTPROC_LABELS[POSTPROC_NAMES[S.demo_pp_idx]] or POSTPROC_NAMES[S.demo_pp_idx] or '?'
        r.ImGui_Text(ctx, 'Post-process')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 210)
        if r.ImGui_BeginCombo(ctx, '##demo_pp', pp_preview) then
            for i, ppn in ipairs(POSTPROC_NAMES) do
                local sel = (i == S.demo_pp_idx)
                if r.ImGui_Selectable(ctx, POSTPROC_LABELS[ppn] or ppn, sel) then
                    S.demo_pp_idx = i
                end
                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.demo_pp_idx)
    end

    -- Far camera combo (Lighting + PostProc modes)
    if mode == DEMO_MODE_LIGHTING or mode == DEMO_MODE_POSTPROC then
        local cf_preview = CoopLabel(COOP_POOL[S.demo_cam_far_idx] or '?')
        r.ImGui_Text(ctx, 'Camera far ')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 210)
        if r.ImGui_BeginCombo(ctx, '##demo_cf', cf_preview) then
            for i, cev in ipairs(COOP_POOL) do
                local sel = (i == S.demo_cam_far_idx)
                if r.ImGui_Selectable(ctx, CoopLabel(cev), sel) then
                    S.demo_cam_far_idx = i
                end
                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.demo_cam_far_idx)
    end

    -- Near camera combo (Lighting + PostProc modes)
    if mode == DEMO_MODE_LIGHTING or mode == DEMO_MODE_POSTPROC then
        local cn_preview = CoopLabel(COOP_POOL[S.demo_cam_near_idx] or '?')
        r.ImGui_Text(ctx, 'Camera near')
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 210)
        if r.ImGui_BeginCombo(ctx, '##demo_cn', cn_preview) then
            for i, cev in ipairs(COOP_POOL) do
                local sel = (i == S.demo_cam_near_idx)
                if r.ImGui_Selectable(ctx, CoopLabel(cev), sel) then
                    S.demo_cam_near_idx = i
                end
                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.demo_cam_near_idx)
    end

    r.ImGui_Spacing(ctx)

    -- Estimated duration info
    local beat_s     = 60.0 / math.max(40, S.demo_bpm)
    local measure_s  = 4.0 * beat_s
    local t_offset_s = 2.0 * measure_s  -- 2-measure pre-roll (matches actions.lua)
    local n_windows  = 0
    local est_min    = 0.0
    if mode == DEMO_MODE_CAMERA then
        local muted_ui = MutedFromCombo(S.demo_cam_combo)
        for _, ev in ipairs(DIRECTED_POOL) do
            local req = DirectedRequired(ev)
            local ok = true
            for _, letter in ipairs(req) do
                if muted_ui[letter] then ok = false; break end
            end
            if ok then n_windows = n_windows + 1 end
        end
        est_min = (t_offset_s + n_windows * 4.0 * measure_s) / 60.0
    elseif mode == DEMO_MODE_COOP then
        local muted_ui = MutedFromCombo(S.demo_cam_combo)
        for _, ev in ipairs(COOP_POOL) do
            local req = CoopRequired(ev)
            local ok = true
            for _, letter in ipairs(req) do
                if muted_ui[letter] then ok = false; break end
            end
            if ok then n_windows = n_windows + 1 end
        end
        est_min = (t_offset_s + n_windows * 2.0 * measure_s) / 60.0
    elseif mode == DEMO_MODE_LIGHTING then
        -- 6 manual × 4 sub-windows + 16 auto × 2 sub-windows
        n_windows = 6 * 4 + (#LIGHTING_NAMES - 6) * 2
        est_min   = (t_offset_s + n_windows * S.demo_window_s) / 60.0
    elseif mode == DEMO_MODE_POSTPROC then
        n_windows = #POSTPROC_NAMES * 2   -- far + near window per effect
        est_min   = (t_offset_s + n_windows * S.demo_window_s) / 60.0
    end
    r.ImGui_TextDisabled(ctx, string.format('%d windows  -  estimated %.1f min', n_windows, est_min))

    r.ImGui_Spacing(ctx)

    -- Generate button
    local bw = r.ImGui_CalcTextSize(ctx, 'Generate demo project') + _bp
    if r.ImGui_Button(ctx, 'Generate demo project', bw, 28) then
        GenerateDemoVenue()
    end
    Tooltip(TIPS.demo_generate)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Status line
    r.ImGui_Text(ctx, S.status or '')

    -- Result panel
    if S.last_result then
        r.ImGui_Spacing(ctx)
        local av_w, av_h = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_InputTextMultiline(ctx, '##demo_result', S.last_result,
            av_w, math.max(av_h - 4, 60),
            r.ImGui_InputTextFlags_ReadOnly())
    end

    r.ImGui_End(ctx)
    return open
end

local function Loop()
    local open = DrawUI()
    if open then r.defer(Loop) end
end

r.defer(Loop)
