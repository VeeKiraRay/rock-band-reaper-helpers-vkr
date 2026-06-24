-- Keys and Difficulty tab rendering

function DrawKeysTab(ctx)
    local _bp         = 40
    local midi_tracks = S.midi_track_list
    local bw_spl  = r.ImGui_CalcTextSize(ctx, 'Split Hands')            + _bp
    local bw_pk   = r.ImGui_CalcTextSize(ctx, 'Convert to Pro Keys')    + _bp
    local bw_5k   = r.ImGui_CalcTextSize(ctx, 'Convert to 5-Lane Keys') + _bp
    local bw_anim = r.ImGui_CalcTextSize(ctx, 'Generate Animation')     + _bp

    SectionHeader('Hand Split')

    r.ImGui_Text(ctx, 'Source        ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_keys_src_idx = TrackCombo('##mc_keys_src', S.mc_keys_src_idx, midi_tracks)
    Tooltip(TIPS.mc_keys_src)

    r.ImGui_Text(ctx, 'Right hand tgt')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_keys_rh_tgt_idx = TrackCombo('##mc_keys_rh', S.mc_keys_rh_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_keys_rh_tgt)

    r.ImGui_Text(ctx, 'Left hand tgt ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_keys_lh_tgt_idx = TrackCombo('##mc_keys_lh', S.mc_keys_lh_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_keys_lh_tgt)

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Split by:')
    r.ImGui_SameLine(ctx)
    local _t_kspl = TIPS.mc_keys_split
    if r.ImGui_RadioButton(ctx, 'Channel (ch1=RH)', S.mc_keys_split_by_ch) then
        S.mc_keys_split_by_ch = true
    end
    Tooltip(_t_kspl)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Pitch threshold', not S.mc_keys_split_by_ch) then
        S.mc_keys_split_by_ch = false
    end
    Tooltip(_t_kspl)

    local slider_w = 200
    local split_disabled = S.mc_keys_split_by_ch
    if split_disabled then r.ImGui_BeginDisabled(ctx) end
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    _, S.mc_keys_split_pitch = r.ImGui_SliderInt(
        ctx, 'Split pitch', S.mc_keys_split_pitch, 21, 108, '%d')
    SliderTooltip(TIPS.mc_keys_split_pitch)
    r.ImGui_SameLine(ctx)
    r.ImGui_TextDisabled(ctx, PitchName(S.mc_keys_split_pitch))
    if split_disabled then r.ImGui_EndDisabled(ctx) end

    SectionHeader('Convert to Pro Keys')
    r.ImGui_TextDisabled(ctx, 'Source: same as Hand Split above.')

    r.ImGui_Text(ctx, 'Pro Keys target')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_pk_conv_tgt_idx = TrackCombo('##mc_pk_conv_tgt', S.mc_pk_conv_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_pk_conv_tgt)

    _, S.mc_pk_insert_shifts = r.ImGui_Checkbox(ctx, 'Insert lane shift markers', S.mc_pk_insert_shifts)
    Tooltip(TIPS.mc_pk_insert_shifts)

    r.ImGui_Spacing(ctx)
    local no_pk_src = S.mc_keys_src_idx < 0
    local no_pk_tgt = S.mc_pk_conv_tgt_idx < 0
    if no_pk_src or no_pk_tgt then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Convert to Pro Keys', bw_pk, 24) then
        RunAction(ConvertPianoToProKeys)
    end
    if no_pk_src or no_pk_tgt then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.gen_pk_from_piano)

    SectionHeader('Pro Keys Animation')

    r.ImGui_Text(ctx, 'Expert PK src  ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_keys_pk_src_idx = TrackCombo('##mc_keys_pk_src', S.mc_keys_pk_src_idx, midi_tracks)
    Tooltip(TIPS.mc_keys_pk_src)

    r.ImGui_TextDisabled(ctx, 'RH / LH targets: see Hand Split above.')

    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, 'Generate Animation', bw_anim, 24) then
        RunAction(ConvertProKeys)
    end
    Tooltip(TIPS.gen_animation)

    SectionHeader('5-Lane Keys')
    r.ImGui_TextDisabled(ctx, 'Source: same as Hand Split above.')

    r.ImGui_Text(ctx, 'Target track  ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mc_5k_tgt_idx = TrackCombo('##mc_5k_tgt', S.mc_5k_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_5k_tgt)

    local slider_w_5k = 200
    r.ImGui_SetNextItemWidth(ctx, slider_w_5k)
    _, S.mc_5k_phrase_gap_ms = r.ImGui_SliderInt(
        ctx, 'Phrase gap (ms)', S.mc_5k_phrase_gap_ms, 50, 2000)
    SliderTooltip(TIPS.mc_5k_phrase_gap)

    r.ImGui_Text(ctx, 'Max chord:')
    r.ImGui_SameLine(ctx)
    local _t_5kmc = TIPS.mc_5k_max_chord
    if r.ImGui_RadioButton(ctx, '2 notes##5k', S.mc_5k_max_chord == 2) then
        S.mc_5k_max_chord = 2
    end
    Tooltip(_t_5kmc)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, '3 notes##5k', S.mc_5k_max_chord == 3) then
        S.mc_5k_max_chord = 3
    end
    Tooltip(_t_5kmc)

    r.ImGui_Spacing(ctx)
    local no_5k_src = S.mc_keys_src_idx < 0
    local no_5k_tgt = S.mc_5k_tgt_idx < 0
    if no_5k_src or no_5k_tgt then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Convert to 5-Lane Keys', bw_5k, 24) then
        RunAction(ConvertKeys5)
    end
    if no_5k_src or no_5k_tgt then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.gen_5k)

    SectionHeader('Workflow')
    local _t_kpv = TIPS.mc_keys_preview
    if r.ImGui_RadioButton(ctx, 'Auto-insert##key', not S.mc_keys_preview) then
        S.mc_keys_preview = false
    end
    Tooltip(_t_kpv)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Preview only##key', S.mc_keys_preview) then
        S.mc_keys_preview = true
    end
    Tooltip(_t_kpv)

    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, 'Split Hands', bw_spl, 24) then
        RunAction(SplitHands)
    end
end

function DrawDifficultyTab(ctx)
    local _bp         = 40
    local midi_tracks = S.midi_track_list

    if r.ImGui_BeginTabBar(ctx, '##diff_subtabs') then

        ------------------------------------------------
        -- Difficulty > Pro Keys sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Pro Keys') then
            local bw_auto = r.ImGui_CalcTextSize(ctx, 'Auto-detect tracks') + _bp
            local bw_sgh  = r.ImGui_CalcTextSize(ctx, 'Suggest Hard')       + _bp
            local bw_sgm  = r.ImGui_CalcTextSize(ctx, 'Suggest Medium')     + _bp
            local bw_sge  = r.ImGui_CalcTextSize(ctx, 'Suggest Easy')       + _bp
            local bw_vax  = r.ImGui_CalcTextSize(ctx, 'Validate Expert')    + _bp
            local bw_vah  = r.ImGui_CalcTextSize(ctx, 'Validate Hard')      + _bp
            local bw_vam  = r.ImGui_CalcTextSize(ctx, 'Validate Medium')    + _bp
            local bw_vae  = r.ImGui_CalcTextSize(ctx, 'Validate Easy')      + _bp
            local bw_val  = r.ImGui_CalcTextSize(ctx, 'Validate All')       + _bp

            SectionHeader('Pro Keys Tracks')

            r.ImGui_Text(ctx, 'Expert')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_x_idx = TrackCombo('##diff_pk_x', S.diff_pk_x_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_x)

            r.ImGui_Text(ctx, 'Hard  ')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_h_idx = TrackCombo('##diff_pk_h', S.diff_pk_h_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_h)

            r.ImGui_Text(ctx, 'Medium')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_m_idx = TrackCombo('##diff_pk_m', S.diff_pk_m_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_m)

            r.ImGui_Text(ctx, 'Easy  ')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_pk_e_idx = TrackCombo('##diff_pk_e', S.diff_pk_e_idx, midi_tracks)
            Tooltip(TIPS.diff_pk_e)

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, 'Auto-detect tracks', bw_auto, 24) then
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

            SectionHeader('Suggest reduction')
            r.ImGui_TextDisabled(ctx, 'Analyze Expert and list changes needed for each difficulty:')
            r.ImGui_Spacing(ctx)

            if no_x then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Suggest Hard',   bw_sgh, 24) then RunAction(function() SuggestProKeysDiff('H') end) end
            Tooltip(TIPS.diff_suggest)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Suggest Medium', bw_sgm, 24) then RunAction(function() SuggestProKeysDiff('M') end) end
            Tooltip(TIPS.diff_suggest)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Suggest Easy',   bw_sge, 24) then RunAction(function() SuggestProKeysDiff('E') end) end
            Tooltip(TIPS.diff_suggest)
            if no_x then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty track against RBN authoring rules:')
            r.ImGui_Spacing(ctx)

            if no_x then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate Expert', bw_vax, 24) then RunAction(function() ValidateProKeysDiff('X') end) end
            Tooltip(TIPS.diff_validate)
            if no_x then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_h then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate Hard',   bw_vah, 24) then RunAction(function() ValidateProKeysDiff('H') end) end
            Tooltip(TIPS.diff_validate)
            if no_h then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_m then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate Medium', bw_vam, 24) then RunAction(function() ValidateProKeysDiff('M') end) end
            Tooltip(TIPS.diff_validate)
            if no_m then r.ImGui_EndDisabled(ctx) end

            r.ImGui_SameLine(ctx)
            if no_e then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate Easy',   bw_vae, 24) then RunAction(function() ValidateProKeysDiff('E') end) end
            Tooltip(TIPS.diff_validate)
            if no_e then r.ImGui_EndDisabled(ctx) end

            r.ImGui_Spacing(ctx)
            if no_any then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate All', bw_val, 24) then RunAction(ValidateAllProKeys) end
            Tooltip(TIPS.diff_validate_all)
            if no_any then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Difficulty > 5-Lane Keys sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, '5-Lane Keys') then
            local bw_5k_auto = r.ImGui_CalcTextSize(ctx, 'Auto-detect track') + _bp
            local bw_5k_sgh  = r.ImGui_CalcTextSize(ctx, 'Suggest Hard')      + _bp
            local bw_5k_sgm  = r.ImGui_CalcTextSize(ctx, 'Suggest Medium')    + _bp
            local bw_5k_sge  = r.ImGui_CalcTextSize(ctx, 'Suggest Easy')      + _bp
            local bw_5k_vax  = r.ImGui_CalcTextSize(ctx, 'Validate Expert')   + _bp
            local bw_5k_vah  = r.ImGui_CalcTextSize(ctx, 'Validate Hard')     + _bp
            local bw_5k_vam  = r.ImGui_CalcTextSize(ctx, 'Validate Medium')   + _bp
            local bw_5k_vae  = r.ImGui_CalcTextSize(ctx, 'Validate Easy')     + _bp
            local bw_5k_val  = r.ImGui_CalcTextSize(ctx, 'Validate All')      + _bp

            SectionHeader('5-Lane Keys Track')

            r.ImGui_Text(ctx, 'PART KEYS')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            S.diff_5k_idx = TrackCombo('##diff_5k', S.diff_5k_idx, midi_tracks)
            Tooltip(TIPS.diff_5k_track)

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, 'Auto-detect track', bw_5k_auto, 24) then
                S.diff_5k_idx = -1
                SetDefaultDifficultyTracks()
                S.status = '5-Lane Keys track auto-detected.'
            end
            Tooltip(TIPS.diff_5k_autodetect)

            local no_5k = S.diff_5k_idx < 0

            SectionHeader('Suggest reduction')
            r.ImGui_TextDisabled(ctx, 'Analyze Expert (96\xe2\x80\x93100) and list changes needed for each difficulty:')
            r.ImGui_Spacing(ctx)

            local is_busy_5k = no_5k
            if is_busy_5k then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Suggest Hard',   bw_5k_sgh, 24) then RunAction(function() SuggestKeys5Diff('H') end) end
            Tooltip(TIPS.diff_5k_suggest)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Suggest Medium', bw_5k_sgm, 24) then RunAction(function() SuggestKeys5Diff('M') end) end
            Tooltip(TIPS.diff_5k_suggest)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Suggest Easy',   bw_5k_sge, 24) then RunAction(function() SuggestKeys5Diff('E') end) end
            Tooltip(TIPS.diff_5k_suggest)
            if is_busy_5k then r.ImGui_EndDisabled(ctx) end

            SectionHeader('Validate')
            r.ImGui_TextDisabled(ctx, 'Check a difficulty range against 5-Lane Keys authoring rules:')
            r.ImGui_Spacing(ctx)

            if no_5k then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate Expert', bw_5k_vax, 24) then RunAction(function() ValidateKeys5Diff('X') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Validate Hard',   bw_5k_vah, 24) then RunAction(function() ValidateKeys5Diff('H') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Validate Medium', bw_5k_vam, 24) then RunAction(function() ValidateKeys5Diff('M') end) end
            Tooltip(TIPS.diff_5k_validate)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Validate Easy',   bw_5k_vae, 24) then RunAction(function() ValidateKeys5Diff('E') end) end
            Tooltip(TIPS.diff_5k_validate)
            if no_5k then r.ImGui_EndDisabled(ctx) end

            r.ImGui_Spacing(ctx)
            if no_5k then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, 'Validate All', bw_5k_val, 24) then RunAction(ValidateAllKeys5) end
            Tooltip(TIPS.diff_5k_validate_all)
            if no_5k then r.ImGui_EndDisabled(ctx) end

            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end
end
