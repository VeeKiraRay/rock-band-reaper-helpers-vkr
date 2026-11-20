-- Keys tab rendering

function DrawKeysTab(ctx)
    local midi_tracks = S.midi_track_list
    local lbl_col_keys = LabelColWidth({ 'Max chord:' })
    local radio_w_keys = RadioGroupWidth({
        '2 notes', '3 notes', 'Auto-insert', 'Preview only',
    })

    TextDimWrapped('Hand animations (PART KEYS_ANIM_RH / _LH) are in the General Helper: ' ..
                   'Animation > Keys.')

    SectionHeader('Source')

    r.ImGui_Text(ctx, 'Source        ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.mc_keys_src_idx = TrackCombo('##mc_keys_src', S.mc_keys_src_idx, midi_tracks)
    Tooltip(TIPS.mc_keys_src)

    SectionHeader('Convert to Pro Keys')
    TextDim('Source: same as above.')

    r.ImGui_Text(ctx, 'Pro Keys target')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.mc_pk_conv_tgt_idx = TrackCombo('##mc_pk_conv_tgt', S.mc_pk_conv_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_pk_conv_tgt)

    _, S.mc_pk_insert_shifts = r.ImGui_Checkbox(ctx, 'Insert lane shift markers', S.mc_pk_insert_shifts)
    Tooltip(TIPS.mc_pk_insert_shifts)

    r.ImGui_Spacing(ctx)
    local no_pk_src = S.mc_keys_src_idx < 0
    local no_pk_tgt = S.mc_pk_conv_tgt_idx < 0
    if no_pk_src or no_pk_tgt then r.ImGui_BeginDisabled(ctx) end
    if Btn('Convert to Pro Keys', BTN_H) then
        RunAction(ConvertPianoToProKeys)
    end
    if no_pk_src or no_pk_tgt then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.gen_pk_from_piano)

    SectionHeader('5-Lane Keys')
    TextDim('Source: same as above.')

    r.ImGui_Text(ctx, 'Target track  ')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.mc_5k_tgt_idx = TrackCombo('##mc_5k_tgt', S.mc_5k_tgt_idx, midi_tracks)
    Tooltip(TIPS.mc_5k_tgt)

    local slider_w_5k = 200
    r.ImGui_SetNextItemWidth(ctx, slider_w_5k)
    _, S.mc_5k_phrase_gap_ms = r.ImGui_SliderInt(
        ctx, 'Phrase gap (ms)', S.mc_5k_phrase_gap_ms, 50, 2000)
    SliderTooltip(TIPS.mc_5k_phrase_gap)

    r.ImGui_Text(ctx, 'Max chord:')
    r.ImGui_SameLine(ctx, lbl_col_keys)
    local _t_5kmc = TIPS.mc_5k_max_chord
    if r.ImGui_RadioButton(ctx, '2 notes##5k', S.mc_5k_max_chord == 2) then
        S.mc_5k_max_chord = 2
    end
    Tooltip(_t_5kmc)
    r.ImGui_SameLine(ctx, lbl_col_keys + radio_w_keys)
    if r.ImGui_RadioButton(ctx, '3 notes##5k', S.mc_5k_max_chord == 3) then
        S.mc_5k_max_chord = 3
    end
    Tooltip(_t_5kmc)

    r.ImGui_Spacing(ctx)
    local no_5k_src = S.mc_keys_src_idx < 0
    local no_5k_tgt = S.mc_5k_tgt_idx < 0
    if no_5k_src or no_5k_tgt then r.ImGui_BeginDisabled(ctx) end
    if Btn('Convert to 5-Lane Keys', BTN_H) then
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
    r.ImGui_SameLine(ctx, radio_w_keys)
    if r.ImGui_RadioButton(ctx, 'Preview only##key', S.mc_keys_preview) then
        S.mc_keys_preview = true
    end
    Tooltip(_t_kpv)
end
