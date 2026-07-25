-- Difficulty tab rendering

function DrawDifficultyTab(ctx)
    local midi_tracks = S.midi_track_list

    if r.ImGui_BeginTabBar(ctx, '##diff_subtabs') then

        ------------------------------------------------
        -- Difficulty > Pro Keys sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Pro Keys') then
            SectionHeader('Pro Keys Tracks')

            local lbl_col_pk = LabelColWidth({ 'Expert', 'Hard', 'Medium', 'Easy' })

            r.ImGui_Text(ctx, 'Expert')
            r.ImGui_SameLine(ctx, lbl_col_pk)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_x_idx = TrackCombo('##diff_pk_x', S.diff_pk_x_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_x)

            r.ImGui_Text(ctx, 'Hard')
            r.ImGui_SameLine(ctx, lbl_col_pk)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_h_idx = TrackCombo('##diff_pk_h', S.diff_pk_h_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_h)

            r.ImGui_Text(ctx, 'Medium')
            r.ImGui_SameLine(ctx, lbl_col_pk)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_m_idx = TrackCombo('##diff_pk_m', S.diff_pk_m_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_m)

            r.ImGui_Text(ctx, 'Easy')
            r.ImGui_SameLine(ctx, lbl_col_pk)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_e_idx = TrackCombo('##diff_pk_e', S.diff_pk_e_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_e)

            r.ImGui_Spacing(ctx)
            if Btn('Auto-detect tracks', BTN_H) then
                S.diff_pk_x_idx = -1; S.diff_pk_h_idx = -1
                S.diff_pk_m_idx = -1; S.diff_pk_e_idx = -1
                SetDefaultDifficultyTracks()
                S.status = 'Pro Keys tracks auto-detected.'
            end
            Tooltip(TIPS.diff_autodetect)

            local no_x   = S.diff_pk_x_idx < 0
            local no_h   = S.diff_pk_h_idx < 0
            local no_m   = S.diff_pk_m_idx < 0
            local no_e   = S.diff_pk_e_idx < 0
            local no_any = no_x and no_h and no_m and no_e

            SectionHeader('Copy to next difficulty')
            r.ImGui_TextDisabled(ctx, 'Copy notes from the tier above onto this one\'s own track:')
            r.ImGui_Spacing(ctx)

            local bw_copy_pk = BtnGroupWidth({ 'Copy to Hard', 'Copy to Medium', 'Copy to Easy' })
            if no_x or no_h then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Hard',   BTN_H, bw_copy_pk) then RunAction(function() CopyProKeysDiff('H') end) end
            Tooltip(TIPS.diff_pk_copy)
            if no_x or no_h then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_h or no_m then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Medium', BTN_H, bw_copy_pk) then RunAction(function() CopyProKeysDiff('M') end) end
            Tooltip(TIPS.diff_pk_copy)
            if no_h or no_m then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_m or no_e then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Easy',   BTN_H, bw_copy_pk) then RunAction(function() CopyProKeysDiff('E') end) end
            Tooltip(TIPS.diff_pk_copy)
            if no_m or no_e then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty track against RBN authoring rules:')
            r.ImGui_Spacing(ctx)

            local bw_val = BtnGroupWidth({
                'Validate Expert', 'Validate Hard', 'Validate Medium', 'Validate Easy', 'Validate All',
            })
            if no_x then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Expert', BTN_H, bw_val) then RunAction(function() ValidateProKeysDiff('X') end) end
            Tooltip(TIPS.diff_validate)
            if no_x then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_h then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Hard',   BTN_H, bw_val) then RunAction(function() ValidateProKeysDiff('H') end) end
            Tooltip(TIPS.diff_validate)
            if no_h then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_m then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Medium', BTN_H, bw_val) then RunAction(function() ValidateProKeysDiff('M') end) end
            Tooltip(TIPS.diff_validate)
            if no_m then r.ImGui_EndDisabled(ctx) end

            if no_e then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Easy',   BTN_H, bw_val) then RunAction(function() ValidateProKeysDiff('E') end) end
            Tooltip(TIPS.diff_validate)
            if no_e then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_any then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate All', BTN_H, bw_val) then RunAction(ValidateAllProKeys) end
            Tooltip(TIPS.diff_validate_all)
            if no_any then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Difficulty > Keys sub-tab (formerly "5-Lane Keys")
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Keys') then
            SectionHeader('Keys Track')

            r.ImGui_Text(ctx, 'PART KEYS')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_5k_idx = TrackCombo('##diff_5k', S.diff_5k_idx, midi_tracks)
            Tooltip(TIPS.diff_5k_track)

            r.ImGui_Spacing(ctx)
            if Btn('Auto-detect track', BTN_H) then
                S.diff_5k_idx = -1
                SetDefaultDifficultyTracks()
                S.status = 'Keys track auto-detected.'
            end
            Tooltip(TIPS.diff_5k_autodetect)

            local no_5k = S.diff_5k_idx < 0

            SectionHeader('Copy to next difficulty')
            r.ImGui_TextDisabled(ctx, 'Copy notes from the tier above onto this one\'s own range:')
            r.ImGui_Spacing(ctx)

            _, S.diff_5k_pk_reduce = r.ImGui_Checkbox(ctx, 'Reduce using Pro Keys (same tier)', S.diff_5k_pk_reduce)
            Tooltip(TIPS.diff_5k_pk_reduce)
            r.ImGui_Spacing(ctx)

            local bw_5k_copy = BtnGroupWidth({ 'Copy to Hard', 'Copy to Medium', 'Copy to Easy' })
            if no_5k then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Hard',   BTN_H, bw_5k_copy) then RunAction(function() CopyKeys5Diff('H') end) end
            Tooltip(TIPS.diff_5k_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Medium', BTN_H, bw_5k_copy) then RunAction(function() CopyKeys5Diff('M') end) end
            Tooltip(TIPS.diff_5k_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Easy',   BTN_H, bw_5k_copy) then RunAction(function() CopyKeys5Diff('E') end) end
            Tooltip(TIPS.diff_5k_copy)
            if no_5k then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty range against Keys authoring rules:')
            r.ImGui_Spacing(ctx)

            local bw_5k_val = BtnGroupWidth({
                'Validate Expert', 'Validate Hard', 'Validate Medium', 'Validate Easy', 'Validate All',
            })
            if no_5k then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Expert', BTN_H, bw_5k_val) then RunAction(function() ValidateKeys5Diff('X') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Hard',   BTN_H, bw_5k_val) then RunAction(function() ValidateKeys5Diff('H') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Medium', BTN_H, bw_5k_val) then RunAction(function() ValidateKeys5Diff('M') end) end
            Tooltip(TIPS.diff_5k_validate)
            if no_5k then r.ImGui_EndDisabled(ctx) end

            if no_5k then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Easy',   BTN_H, bw_5k_val) then RunAction(function() ValidateKeys5Diff('E') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate All', BTN_H, bw_5k_val) then RunAction(ValidateAllKeys5) end
            Tooltip(TIPS.diff_5k_validate_all)
            if no_5k then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Difficulty > Guitar/Bass sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Guitar/Bass') then
            local radio_w_gb = RadioGroupWidth({ 'Guitar', 'Bass' })

            SectionHeader('Instrument')
            if r.ImGui_RadioButton(ctx, 'Guitar##diff_gb_inst', S.diff_gb_instrument == 'gtr') then
                S.diff_gb_instrument = 'gtr'
            end
            Tooltip(TIPS.diff_gb_instrument)
            r.ImGui_SameLine(ctx, radio_w_gb)
            if r.ImGui_RadioButton(ctx, 'Bass##diff_gb_inst', S.diff_gb_instrument == 'bass') then
                S.diff_gb_instrument = 'bass'
            end
            Tooltip(TIPS.diff_gb_instrument)

            local inst        = S.diff_gb_instrument
            local track_name  = inst == 'bass' and 'PART BASS' or 'PART GUITAR'
            local idx_field    = inst == 'bass' and 'diff_bass_idx' or 'diff_gtr_idx'

            SectionHeader(track_name .. ' Track')
            r.ImGui_Text(ctx, track_name)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S[idx_field] = TrackCombo('##diff_gb_track', S[idx_field], midi_tracks)
            Tooltip(TIPS.diff_gb_track)

            r.ImGui_Spacing(ctx)
            if Btn('Auto-detect tracks', BTN_H) then
                S.diff_gtr_idx  = -1
                S.diff_bass_idx = -1
                SetDefaultDifficultyTracks()
                S.status = 'Guitar/Bass tracks auto-detected.'
            end
            Tooltip(TIPS.diff_gb_autodetect)

            local no_gb = S[idx_field] < 0

            SectionHeader('Copy to next difficulty')
            r.ImGui_TextDisabled(ctx, 'Copy notes from the tier above onto this one\'s own range:')
            r.ImGui_Spacing(ctx)

            local bw_gb_copy = BtnGroupWidth({ 'Copy to Hard', 'Copy to Medium', 'Copy to Easy' })
            if no_gb then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Hard',   BTN_H, bw_gb_copy) then RunAction(function() CopyGtrBassDiff(inst, 'H') end) end
            Tooltip(TIPS.diff_gb_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Medium', BTN_H, bw_gb_copy) then RunAction(function() CopyGtrBassDiff(inst, 'M') end) end
            Tooltip(TIPS.diff_gb_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Easy',   BTN_H, bw_gb_copy) then RunAction(function() CopyGtrBassDiff(inst, 'E') end) end
            Tooltip(TIPS.diff_gb_copy)
            if no_gb then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty range against Guitar/Bass authoring rules:')
            r.ImGui_Spacing(ctx)

            local bw_gb_val = BtnGroupWidth({
                'Validate Expert', 'Validate Hard', 'Validate Medium', 'Validate Easy', 'Validate All',
            })
            if no_gb then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Expert', BTN_H, bw_gb_val) then RunAction(function() ValidateGtrBassDiff(inst, 'X') end) end
            Tooltip(TIPS.diff_gb_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Hard',   BTN_H, bw_gb_val) then RunAction(function() ValidateGtrBassDiff(inst, 'H') end) end
            Tooltip(TIPS.diff_gb_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Medium', BTN_H, bw_gb_val) then RunAction(function() ValidateGtrBassDiff(inst, 'M') end) end
            Tooltip(TIPS.diff_gb_validate)
            if no_gb then r.ImGui_EndDisabled(ctx) end

            if no_gb then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Easy',   BTN_H, bw_gb_val) then RunAction(function() ValidateGtrBassDiff(inst, 'E') end) end
            Tooltip(TIPS.diff_gb_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate All', BTN_H, bw_gb_val) then RunAction(function() ValidateAllGtrBass(inst) end) end
            Tooltip(TIPS.diff_gb_validate_all)
            if no_gb then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Difficulty > Drums sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Drums') then
            SectionHeader('Drums Track')

            r.ImGui_Text(ctx, 'PART DRUMS')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_drums_idx = TrackCombo('##diff_drums', S.diff_drums_idx, midi_tracks)
            Tooltip(TIPS.diff_drums_track)

            r.ImGui_Spacing(ctx)
            if Btn('Auto-detect track', BTN_H) then
                S.diff_drums_idx = -1
                SetDefaultDifficultyTracks()
                S.status = 'Drums track auto-detected.'
            end
            Tooltip(TIPS.diff_drums_autodetect)

            local no_drums = S.diff_drums_idx < 0

            SectionHeader('Copy to next difficulty')
            r.ImGui_TextDisabled(ctx, 'Copy notes from the tier above onto this one\'s own range:')
            r.ImGui_Spacing(ctx)

            local bw_dr_copy = BtnGroupWidth({ 'Copy to Hard', 'Copy to Medium', 'Copy to Easy' })
            if no_drums then r.ImGui_BeginDisabled(ctx) end
            if Btn('Copy to Hard',   BTN_H, bw_dr_copy) then RunAction(function() CopyDrumsDiff('H') end) end
            Tooltip(TIPS.diff_drums_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Medium', BTN_H, bw_dr_copy) then RunAction(function() CopyDrumsDiff('M') end) end
            Tooltip(TIPS.diff_drums_copy)
            r.ImGui_SameLine(ctx)
            if Btn('Copy to Easy',   BTN_H, bw_dr_copy) then RunAction(function() CopyDrumsDiff('E') end) end
            Tooltip(TIPS.diff_drums_copy)
            if no_drums then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty range against Drums authoring rules:')
            r.ImGui_Spacing(ctx)

            local bw_dr_val = BtnGroupWidth({
                'Validate Expert', 'Validate Hard', 'Validate Medium', 'Validate Easy', 'Validate All',
            })
            if no_drums then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Expert', BTN_H, bw_dr_val) then RunAction(function() ValidateDrumsDiff('X') end) end
            Tooltip(TIPS.diff_drums_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Hard',   BTN_H, bw_dr_val) then RunAction(function() ValidateDrumsDiff('H') end) end
            Tooltip(TIPS.diff_drums_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate Medium', BTN_H, bw_dr_val) then RunAction(function() ValidateDrumsDiff('M') end) end
            Tooltip(TIPS.diff_drums_validate)
            if no_drums then r.ImGui_EndDisabled(ctx) end

            if no_drums then r.ImGui_BeginDisabled(ctx) end
            if Btn('Validate Easy',   BTN_H, bw_dr_val) then RunAction(function() ValidateDrumsDiff('E') end) end
            Tooltip(TIPS.diff_drums_validate)
            r.ImGui_SameLine(ctx)
            if Btn('Validate All', BTN_H, bw_dr_val) then RunAction(ValidateAllDrums) end
            Tooltip(TIPS.diff_drums_validate_all)
            if no_drums then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end

    -- Shared "Copy to X" overwrite confirmation, set by any of the four
    -- Copy*Diff functions when the target already has notes. Rendered once
    -- here regardless of which sub-tab triggered it.
    if S.diff_copy_pending then
        r.ImGui_OpenPopup(ctx, 'ConfirmCopyOverwrite')
    end
    if r.ImGui_BeginPopupModal(ctx, 'ConfirmCopyOverwrite', nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        if S.diff_copy_pending then
            r.ImGui_Text(ctx, S.diff_copy_pending.message)
        end
        r.ImGui_Spacing(ctx)
        if Btn('Clear and Copy', BTN_H) then
            if S.diff_copy_pending then RunAction(S.diff_copy_pending.on_confirm) end
            S.diff_copy_pending = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if Btn('Cancel', BTN_H) then
            S.diff_copy_pending = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end
