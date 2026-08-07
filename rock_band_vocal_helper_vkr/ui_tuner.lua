-- Tuner tab body: YIN detection settings, pitch range, and the live readout.
--
-- Drawn by both the vocal helper's Tuner tab and the standalone
-- rock_band_pitch_tuner_vkr.lua window, so it renders its own body only -
-- no Begin/End, no BeginTabItem. The caller owns the window and the tab item,
-- and is responsible for setting S.tuner_tab_active and calling RunTuner()
-- before any UI rendering.
--
-- Requires globals: r, ctx, S, TIPS, YINPresetCombo, SectionHeader, ResetYIN,
--                   LabelColWidth, SliderTooltip, Tooltip, Btn, RunAction,
--                   StartTuner, StopTuner, PitchName, BTN_H, WIDTH_STD,
--                   RB3_MIN_PITCH, RB3_MAX_PITCH

function DrawTunerTab()
    r.ImGui_Spacing(ctx)
    SectionHeader('YIN Detection', 'Reset##yin_tur', ResetYIN, TIPS.reset_yin)
    local lbl_col_tur = LabelColWidth({
        'Vocal style preset', 'YIN threshold', 'Min frequency (Hz)',
        'Max frequency (Hz)', 'Window (ms)', 'Min confidence',
        'Min RMS level', 'Min pitch', 'Max pitch',
    })
    YINPresetCombo('##tur', lbl_col_tur)
    local _
    r.ImGui_Text(ctx, 'YIN threshold')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_threshold = r.ImGui_SliderDouble(ctx, '##yinthr_tur',
        S.yin_threshold, 0.01, 0.5, '%.3f')
    SliderTooltip(TIPS.yin_threshold)
    r.ImGui_Text(ctx, 'Min frequency (Hz)')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_min_freq = r.ImGui_SliderInt(ctx, '##yinminf_tur',
        S.yin_min_freq, 40, 400)
    SliderTooltip(TIPS.yin_min_freq)
    r.ImGui_Text(ctx, 'Max frequency (Hz)')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_max_freq = r.ImGui_SliderInt(ctx, '##yinmaxf_tur',
        S.yin_max_freq, 200, 2000)
    SliderTooltip(TIPS.yin_max_freq)
    if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
    r.ImGui_Text(ctx, 'Window (ms)')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_window_ms = r.ImGui_SliderInt(ctx, '##yinwin_tur',
        S.yin_window_ms, 10, 100)
    SliderTooltip(TIPS.yin_window_ms)
    r.ImGui_Text(ctx, 'Min confidence')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_min_confidence = r.ImGui_SliderDouble(ctx, '##yinconf_tur',
        S.yin_min_confidence, 0.0, 0.95, '%.2f')
    SliderTooltip(TIPS.yin_min_confidence)
    r.ImGui_Text(ctx, 'Min RMS level')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.tuner_rms_threshold = r.ImGui_SliderDouble(ctx, '##turrms',
        S.tuner_rms_threshold, 0.001, 0.1, '%.4f')
    SliderTooltip(TIPS.tuner_rms_threshold)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Pitch Range')

    r.ImGui_Text(ctx, 'Min pitch')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    if not S.min_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
    local minfmt_tur = ('%%d  (%s)'):format(PitchName(S.min_pitch))
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.min_pitch = r.ImGui_SliderInt(ctx, '##minpitch_tur', S.min_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, minfmt_tur)
    SliderTooltip(TIPS.min_pitch)
    if not S.min_pitch_enabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    local cb_changed_tur
    cb_changed_tur, S.min_pitch_enabled = r.ImGui_Checkbox(ctx, '##minpe_tur', S.min_pitch_enabled)
    Tooltip(TIPS.min_pitch_enabled)

    r.ImGui_Text(ctx, 'Max pitch')
    r.ImGui_SameLine(ctx, lbl_col_tur)
    if not S.max_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
    local maxfmt_tur = ('%%d  (%s)'):format(PitchName(S.max_pitch))
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.max_pitch = r.ImGui_SliderInt(ctx, '##maxpitch_tur', S.max_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, maxfmt_tur)
    SliderTooltip(TIPS.max_pitch)
    if not S.max_pitch_enabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    cb_changed_tur, S.max_pitch_enabled = r.ImGui_Checkbox(ctx, '##maxpe_tur', S.max_pitch_enabled)
    Tooltip(TIPS.max_pitch_enabled)

    if S.min_pitch_enabled and S.max_pitch_enabled and S.min_pitch > S.max_pitch then
        S.max_pitch = S.min_pitch
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Pitch Tuner')

    if S.tuner_active then
        if Btn('Stop Tuner', BTN_H) then RunAction(StopTuner) end
    else
        if Btn('Start Tuner', BTN_H) then RunAction(StartTuner) end
    end
    Tooltip(TIPS.tuner_toggle)

    r.ImGui_Spacing(ctx)
    local state_color = S.tuner_active and 0x88FF88FF or 0x888888FF
    local state_label = S.tuner_active and 'Tuner: Active' or 'Tuner: Stopped'
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), state_color)
    r.ImGui_Text(ctx, state_label)
    r.ImGui_PopStyleColor(ctx)

    r.ImGui_Separator(ctx)

    -- Current pitch display (highlighted)
    local arrow       = ''
    local arrow_color = 0x888888FF
    if S.tuner_pitch and S.tuner_prev_pitch then
        if     S.tuner_pitch > S.tuner_prev_pitch then arrow = '\xe2\x96\xb2'; arrow_color = 0x55FF55FF
        elseif S.tuner_pitch < S.tuner_prev_pitch then arrow = '\xe2\x96\xbc'; arrow_color = 0xFF5555FF
        else                                           arrow = '=';             arrow_color = 0x888888FF
        end
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
    r.ImGui_Text(ctx, S.tuner_pitch_name or '-')
    r.ImGui_PopStyleColor(ctx)
    if arrow ~= '' then
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), arrow_color)
        r.ImGui_Text(ctx, arrow)
        r.ImGui_PopStyleColor(ctx)
    end
    if S.tuner_pitch_hz then
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, ('%.1f Hz'):format(S.tuner_pitch_hz))
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, 'at ' .. r.format_timestr_pos(S.tuner_pitch_ts, '', 0))
    end
    -- Confidence: amber below 0.75 so a shaky reading looks shaky.
    if S.tuner_confidence then
        r.ImGui_SameLine(ctx)
        local conf_col = S.tuner_confidence >= 0.75 and 0xAAAAAAFF or 0xFFC04CFF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), conf_col)
        r.ImGui_Text(ctx, ('(%.0f%% conf)'):format(S.tuner_confidence * 100))
        r.ImGui_PopStyleColor(ctx)
    end

    -- History strip (dimmed, newest on left)
    if #S.tuner_history > 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xAAAAAAFF)
        r.ImGui_Text(ctx, table.concat(S.tuner_history, '  '))
        r.ImGui_PopStyleColor(ctx)
    end

    local quiet_delay = (r.GetPlayState() & 1 ~= 0) and 1.5 or 0.0
    if S.tuner_quiet_since and r.time_precise() - S.tuner_quiet_since > quiet_delay then
        S.status = 'Quiet - no pitch detected'
    elseif S.status == 'Quiet - no pitch detected' then
        S.status = ''
    end
end
