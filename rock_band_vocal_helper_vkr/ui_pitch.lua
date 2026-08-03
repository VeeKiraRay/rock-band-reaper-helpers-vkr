-- Pitch tab rendering (Placement - Built-in / Placement - Reference / Snap sub-tabs)

local function DrawApplyPitchButton()
    r.ImGui_Separator(ctx)
    if Btn('Apply pitch changes', BTN_H) then
        RunAction(ApplyPitchChangesAction)
    end
    Tooltip(TIPS.apply_pitch)
end

function DrawPitchTab(ctx)
    local sel_s, _ = GetTimeSelection()
    local midi_tracks = S.midi_track_list

    if r.ImGui_BeginTabBar(ctx, '##pitch_subtabs') then

        ------------------------------------------------
        -- Sub-tab: Placement - Built-in
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Placement - Built-in') then
            S.pitch_mode = MODE_YIN
            r.ImGui_Spacing(ctx)
            SectionHeader('Pitch', 'Reset##pitch', ResetPitch, TIPS.reset_pitch)

            local lbl_col_bi = LabelColWidth({
                'Vocal style preset', 'YIN threshold', 'Min frequency (Hz)',
                'Max frequency (Hz)', 'YIN window (ms)', 'Min confidence',
                'Min RMS level', 'Samples per note', 'Min pitch', 'Max pitch',
            })
            local radio_w_bi = RadioGroupWidth({ '1', '3', '5' })

            r.ImGui_Text(ctx, 'Built-in detection settings')
            if Btn('Auto-tune YIN from reference', BTN_H) then
                RunAction(RunAutoTuneYIN)
            end
            Tooltip(TIPS.autotune_yin)
            r.ImGui_Spacing(ctx)

            YINPresetCombo('', lbl_col_bi)
            local _
            r.ImGui_Text(ctx, 'YIN threshold')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_threshold = r.ImGui_SliderDouble(ctx, '##yinthr_ph',
                S.yin_threshold, 0.01, 0.5, '%.3f')
            SliderTooltip(TIPS.yin_threshold)
            r.ImGui_Text(ctx, 'Min frequency (Hz)')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_min_freq = r.ImGui_SliderInt(ctx, '##yinminf_ph',
                S.yin_min_freq, 40, 400)
            SliderTooltip(TIPS.yin_min_freq)
            r.ImGui_Text(ctx, 'Max frequency (Hz)')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_max_freq = r.ImGui_SliderInt(ctx, '##yinmaxf_ph',
                S.yin_max_freq, 200, 2000)
            SliderTooltip(TIPS.yin_max_freq)
            if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
            r.ImGui_Text(ctx, 'YIN window (ms)')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_window_ms = r.ImGui_SliderDouble(ctx, '##yinwin_ph',
                S.yin_window_ms, 10, 100, '%.0f')
            SliderTooltip(TIPS.yin_window_ms)
            r.ImGui_Text(ctx, 'Min confidence')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_min_confidence = r.ImGui_SliderDouble(ctx, '##yinconf_ph',
                S.yin_min_confidence, 0.0, 0.95, '%.2f')
            SliderTooltip(TIPS.yin_min_confidence)
            r.ImGui_Text(ctx, 'Min RMS level')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.yin_rms_gate = r.ImGui_SliderDouble(ctx, '##yinrms_ph',
                S.yin_rms_gate, 0.0, 0.1, '%.4f')
            SliderTooltip(TIPS.yin_rms_gate)
            r.ImGui_Text(ctx, 'Samples per note')
            for i, n in ipairs({ 1, 3, 5 }) do
                r.ImGui_SameLine(ctx, lbl_col_bi + (i - 1) * radio_w_bi)
                if r.ImGui_RadioButton(ctx, n .. '##yinvw_ph', S.yin_vote_windows == n) then
                    S.yin_vote_windows = n
                end
                Tooltip(TIPS.yin_vote_windows)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, 'Pitch range constraints')

            r.ImGui_Text(ctx, 'Min pitch')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            if not S.min_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
            local minfmt = ('%%d  (%s)'):format(PitchName(S.min_pitch))
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.min_pitch = r.ImGui_SliderInt(ctx, '##minpitch_ph', S.min_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, minfmt)
            SliderTooltip(TIPS.min_pitch)
            if not S.min_pitch_enabled then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            local cb_changed
            cb_changed, S.min_pitch_enabled = r.ImGui_Checkbox(ctx, '##minpe', S.min_pitch_enabled)
            Tooltip(TIPS.min_pitch_enabled)

            r.ImGui_Text(ctx, 'Max pitch')
            r.ImGui_SameLine(ctx, lbl_col_bi)
            if not S.max_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
            local maxfmt = ('%%d  (%s)'):format(PitchName(S.max_pitch))
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            _, S.max_pitch = r.ImGui_SliderInt(ctx, '##maxpitch_ph', S.max_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, maxfmt)
            SliderTooltip(TIPS.max_pitch)
            if not S.max_pitch_enabled then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            cb_changed, S.max_pitch_enabled = r.ImGui_Checkbox(ctx, '##maxpe', S.max_pitch_enabled)
            Tooltip(TIPS.max_pitch_enabled)

            if S.min_pitch_enabled and S.max_pitch_enabled and S.min_pitch > S.max_pitch then
                S.max_pitch = S.min_pitch
            end

            DrawApplyPitchButton()

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Sub-tab: Placement - Reference
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Placement - Reference') then
            S.pitch_mode = MODE_REFERENCE
            r.ImGui_Spacing(ctx)
            SectionHeader('Reference MIDI')

            local lbl_col_ref = LabelColWidth({ 'Reference MIDI track', 'Search tolerance (ms)' })

            r.ImGui_Text(ctx, 'Reference MIDI track')
            r.ImGui_SameLine(ctx, lbl_col_ref)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            S.ref_idx = FilteredTrackCombo('##refmidi', S.ref_idx, midi_tracks)
            Tooltip(TIPS.ref_track)

            r.ImGui_Text(ctx, 'Search tolerance (ms)')
            r.ImGui_SameLine(ctx, lbl_col_ref)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            local _
            _, S.ref_search_ms = r.ImGui_SliderDouble(ctx, '##refsearch',
                S.ref_search_ms, 50, 2000, '%.0f')
            SliderTooltip(TIPS.ref_search)

            DrawApplyPitchButton()

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Sub-tab: Snap
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Snap') then
            r.ImGui_Spacing(ctx)
            SectionHeader('Snap to Key Scale')

            local lbl_col_key = LabelColWidth({ 'Key' })
            local lbl_col_sac = LabelColWidth({ 'Avoid matching neighbor (within phrase)' })

            r.ImGui_Text(ctx, 'Key')
            Tooltip(TIPS.snap_key_root)
            r.ImGui_SameLine(ctx, lbl_col_key)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
            if r.ImGui_BeginCombo(ctx, '##snap_kr', HARM_NOTE_NAMES[S.snap_key_root + 1]) then
                for i, name in ipairs(HARM_NOTE_NAMES) do
                    local is_sel = (i - 1 == S.snap_key_root)
                    if r.ImGui_Selectable(ctx, name, is_sel) then S.snap_key_root = i - 1 end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end
            Tooltip(TIPS.snap_key_root)
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, 'Major##skq', S.snap_key_quality == 0) then
                S.snap_key_quality = 0
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, 'Minor##skq', S.snap_key_quality == 1) then
                S.snap_key_quality = 1
            end

            r.ImGui_Text(ctx, 'Avoid matching neighbor (within phrase)')
            r.ImGui_SameLine(ctx, lbl_col_sac)
            local _, new_sac = r.ImGui_Checkbox(ctx, '##sac', S.snap_avoid_collision)
            S.snap_avoid_collision = new_sac
            Tooltip(TIPS.snap_avoid_collision)

            r.ImGui_Spacing(ctx)
            local snap_label = sel_s and 'Snap to Key (time sel)' or 'Snap to Key (full item)'
            if Btn(snap_label, 24) then
                if not sel_s then
                    local res = r.ShowMessageBox(
                        'No time selection is active.\n\nAll notes in the full MIDI item will be snapped to the key.\n\nContinue?',
                        'Snap to Key', 1)
                    if res == 1 then RunAction(SnapToKeyAction) end
                else
                    RunAction(SnapToKeyAction)
                end
            end
            Tooltip(TIPS.snap_apply)

            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end
end
