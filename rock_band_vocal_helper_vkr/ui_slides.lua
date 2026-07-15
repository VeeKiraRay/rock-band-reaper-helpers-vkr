-- Pitch slide tab rendering

function DrawPitchSlideTab(ctx)
    r.ImGui_Spacing(ctx)
    SectionHeader('Slide Scan', 'Reset##slides', ResetSlides, TIPS.reset_slides)

    local lbl_col_sld = LabelColWidth({
        'Min note length (ms)', 'Min segment (ms)', 'Edge skip (ms)',
        'Sample step (ms)', 'Sample window (ms)', 'Vocal style preset',
        'YIN threshold', 'Min frequency (Hz)', 'Max frequency (Hz)',
    })

    r.ImGui_Text(ctx, 'Min note length (ms)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.slide_min_note_ms = r.ImGui_SliderInt(ctx, '##sldminnote', S.slide_min_note_ms, 20, 500)
    S.slide_min_note_ms = math.max(20,  math.floor(S.slide_min_note_ms / 10 + 0.5) * 10)
    SliderTooltip(TIPS.slide_min_note_ms)
    r.ImGui_Text(ctx, 'Min segment (ms)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.slide_min_seg_ms  = r.ImGui_SliderInt(ctx, '##sldminseg', S.slide_min_seg_ms,   5, 100)
    S.slide_min_seg_ms  = math.max(5,   math.floor(S.slide_min_seg_ms  /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_min_seg_ms)
    r.ImGui_Text(ctx, 'Edge skip (ms)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.slide_skip_ms     = r.ImGui_SliderInt(ctx, '##sldskip',       S.slide_skip_ms,      0,  50)
    S.slide_skip_ms     = math.max(0,   math.floor(S.slide_skip_ms     /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_skip_ms)
    r.ImGui_Text(ctx, 'Sample step (ms)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.slide_step_ms     = r.ImGui_SliderInt(ctx, '##sldstep',     S.slide_step_ms,      5,  50)
    S.slide_step_ms     = math.max(5,   math.floor(S.slide_step_ms     /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_step_ms)
    r.ImGui_Text(ctx, 'Sample window (ms)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.slide_win_ms      = r.ImGui_SliderInt(ctx, '##sldwin',   S.slide_win_ms,      10,  50)
    S.slide_win_ms      = math.max(10,  math.floor(S.slide_win_ms      /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_win_ms)
    local min_slidable_ms = S.slide_skip_ms * 2 + S.slide_min_seg_ms * 2
    if min_slidable_ms > S.slide_min_note_ms then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextColored(ctx, 0xFFAA00FF,
            ('! Min segment \xc3\x972 + Edge skip \xc3\x972 = %dms exceeds Min note length (%dms).')
                :format(min_slidable_ms, S.slide_min_note_ms))
        r.ImGui_TextColored(ctx, 0xFFAA00FF,
            '  No slides can be detected with these settings.')
    end
    r.ImGui_Separator(ctx)
    SectionHeader('YIN Detection', 'Reset##yin', ResetYIN, TIPS.reset_yin)
    YINPresetCombo('##sld', lbl_col_sld)
    r.ImGui_Text(ctx, 'YIN threshold')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_threshold = r.ImGui_SliderDouble(ctx, '##yinthr_sld',
        S.yin_threshold, 0.01, 0.5, '%.3f')
    SliderTooltip(TIPS.yin_threshold)
    r.ImGui_Text(ctx, 'Min frequency (Hz)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_min_freq = r.ImGui_SliderInt(ctx, '##yinminf_sld',
        S.yin_min_freq, 40, 400)
    SliderTooltip(TIPS.yin_min_freq)
    r.ImGui_Text(ctx, 'Max frequency (Hz)')
    r.ImGui_SameLine(ctx, lbl_col_sld)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.yin_max_freq = r.ImGui_SliderInt(ctx, '##yinmaxf_sld',
        S.yin_max_freq, 200, 2000)
    SliderTooltip(TIPS.yin_max_freq)
    if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
    r.ImGui_Separator(ctx)
    if Btn('Scan pitch slides', BTN_H) then
        RunAction(ScanPitchSlidesAction)
    end
    Tooltip(TIPS.scan_slides)
end
