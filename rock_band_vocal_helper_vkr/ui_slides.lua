-- Pitch slide tab rendering

function DrawPitchSlideTab(ctx)
    local _bp    = 40
    local bw_sld = r.ImGui_CalcTextSize(ctx, 'Scan pitch slides') + _bp

    r.ImGui_Spacing(ctx)
    SectionHeader('Slide Scan', 'Reset##slides', ResetSlides, TIPS.reset_slides)
    _, S.slide_min_note_ms = r.ImGui_SliderInt(ctx, 'Min note length (ms)##sld', S.slide_min_note_ms, 20, 500)
    S.slide_min_note_ms = math.max(20,  math.floor(S.slide_min_note_ms / 10 + 0.5) * 10)
    SliderTooltip(TIPS.slide_min_note_ms)
    _, S.slide_min_seg_ms  = r.ImGui_SliderInt(ctx, 'Min segment (ms)##sld',     S.slide_min_seg_ms,   5, 100)
    S.slide_min_seg_ms  = math.max(5,   math.floor(S.slide_min_seg_ms  /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_min_seg_ms)
    _, S.slide_skip_ms     = r.ImGui_SliderInt(ctx, 'Edge skip (ms)##sld',       S.slide_skip_ms,      0,  50)
    S.slide_skip_ms     = math.max(0,   math.floor(S.slide_skip_ms     /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_skip_ms)
    _, S.slide_step_ms     = r.ImGui_SliderInt(ctx, 'Sample step (ms)##sld',     S.slide_step_ms,      5,  50)
    S.slide_step_ms     = math.max(5,   math.floor(S.slide_step_ms     /  5 + 0.5) *  5)
    SliderTooltip(TIPS.slide_step_ms)
    _, S.slide_win_ms      = r.ImGui_SliderInt(ctx, 'Sample window (ms)##sld',   S.slide_win_ms,      10,  50)
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
    _, S.yin_threshold = r.ImGui_SliderDouble(ctx, 'YIN threshold',
        S.yin_threshold, 0.01, 0.5, '%.3f')
    SliderTooltip(TIPS.yin_threshold)
    _, S.yin_min_freq = r.ImGui_SliderInt(ctx, 'Min frequency (Hz)',
        S.yin_min_freq, 40, 400)
    SliderTooltip(TIPS.yin_min_freq)
    _, S.yin_max_freq = r.ImGui_SliderInt(ctx, 'Max frequency (Hz)',
        S.yin_max_freq, 200, 2000)
    SliderTooltip(TIPS.yin_max_freq)
    if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, 'Scan pitch slides', bw_sld, 24) then
        RunAction(ScanPitchSlidesAction)
    end
    Tooltip(TIPS.scan_slides)
end
