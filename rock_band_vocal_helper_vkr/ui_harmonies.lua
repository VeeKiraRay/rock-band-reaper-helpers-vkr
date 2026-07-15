-- Harmonies tab rendering

function DrawHarmoniesTab(ctx)
    local sel_s, _ = GetTimeSelection()
    local tracks       = S.all_track_list
    local midi_tracks  = S.midi_track_list

    r.ImGui_Spacing(ctx)

    ---- Source ----
    local lbl_col_src = LabelColWidth({ 'Source' })
    r.ImGui_Text(ctx, 'Source')
    Tooltip(TIPS.harm_src)
    r.ImGui_SameLine(ctx, lbl_col_src)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.harm_src_idx = FilteredTrackCombo('##harm_src', S.harm_src_idx, midi_tracks)
    Tooltip(TIPS.harm_src)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    ---- Destination rows ----
    local dst_rows = {
        { en='harm_dst1_enabled', idx='harm_dst1_idx', mode='harm_dst1_mode',
          en_id='##hd1en', trk_id='##harm_dst1', mode_id='##harm_m1',
          lu='harm_dst1_lyric_unpitched', lh='harm_dst1_lyric_hidden',
          lu_id='##hd1lu', lh_id='##hd1lh',
          label='Destination 1', tip='harm_dst1' },
        { en='harm_dst2_enabled', idx='harm_dst2_idx', mode='harm_dst2_mode',
          en_id='##hd2en', trk_id='##harm_dst2', mode_id='##harm_m2',
          lu='harm_dst2_lyric_unpitched', lh='harm_dst2_lyric_hidden',
          lu_id='##hd2lu', lh_id='##hd2lh',
          label='Destination 2', tip='harm_dst2' },
        { en='harm_dst3_enabled', idx='harm_dst3_idx', mode='harm_dst3_mode',
          en_id='##hd3en', trk_id='##harm_dst3', mode_id='##harm_m3',
          lu='harm_dst3_lyric_unpitched', lh='harm_dst3_lyric_hidden',
          lu_id='##hd3lu', lh_id='##hd3lh',
          label='Destination 3', tip='harm_dst3' },
    }

    local any_diatonic = false
    for _, d in ipairs(dst_rows) do
        if S[d.en] and HARM_MODES[S[d.mode] + 1].diatonic then
            any_diatonic = true
        end
    end

    for _, d in ipairs(dst_rows) do
        r.ImGui_Text(ctx, d.label)
        r.ImGui_SameLine(ctx)
        local _, new_en = r.ImGui_Checkbox(ctx, d.en_id, S[d.en])
        S[d.en] = new_en
        Tooltip(TIPS.harm_dst_enabled)

        local row_off = not S[d.en]
        if row_off then r.ImGui_BeginDisabled(ctx) end
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S[d.idx] = FilteredTrackCombo(d.trk_id, S[d.idx], tracks)
        Tooltip(TIPS[d.tip])
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        if r.ImGui_BeginCombo(ctx, d.mode_id, HARM_MODES[S[d.mode] + 1].label) then
            for mi, m in ipairs(HARM_MODES) do
                local is_sel = (mi - 1 == S[d.mode])
                if r.ImGui_Selectable(ctx, m.label, is_sel) then S[d.mode] = mi - 1 end
                if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        Tooltip(TIPS.harm_dst_mode)
        local _, new_lu = r.ImGui_Checkbox(ctx, 'Unpitched lyrics (#)' .. d.lu_id, S[d.lu])
        S[d.lu] = new_lu
        Tooltip(TIPS.harm_lyric_unpitched)
        r.ImGui_SameLine(ctx)
        local _, new_lh = r.ImGui_Checkbox(ctx, 'Hidden lyrics ($)' .. d.lh_id, S[d.lh])
        S[d.lh] = new_lh
        Tooltip(TIPS.harm_lyric_hidden)
        if row_off then r.ImGui_EndDisabled(ctx) end

        r.ImGui_Spacing(ctx)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    ---- Key section ----
    if not any_diatonic then r.ImGui_BeginDisabled(ctx) end
    local lbl_col_key = LabelColWidth({ 'Key' })
    r.ImGui_Text(ctx, 'Key')
    Tooltip(TIPS.harm_key)
    r.ImGui_SameLine(ctx, lbl_col_key)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
    if r.ImGui_BeginCombo(ctx, '##harm_kr', HARM_NOTE_NAMES[S.harm_key_root + 1]) then
        for i, name in ipairs(HARM_NOTE_NAMES) do
            local is_sel = (i - 1 == S.harm_key_root)
            if r.ImGui_Selectable(ctx, name, is_sel) then S.harm_key_root = i - 1 end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.harm_key)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Major##hkq', S.harm_key_quality == 0) then
        S.harm_key_quality = 0
    end
    Tooltip(TIPS.harm_key_quality)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Minor##hkq', S.harm_key_quality == 1) then
        S.harm_key_quality = 1
    end
    Tooltip(TIPS.harm_key_quality)
    if not any_diatonic then r.ImGui_EndDisabled(ctx) end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    ---- Copy phrase markers / overdrive checkboxes ----
    local _, new_cpm = r.ImGui_Checkbox(ctx, 'Copy phrase markers##harm_cpm', S.harm_copy_phrase_markers)
    S.harm_copy_phrase_markers = new_cpm
    Tooltip(TIPS.harm_copy_phrase_markers)
    r.ImGui_SameLine(ctx)
    local _, new_cod = r.ImGui_Checkbox(ctx, 'Copy overdrive##harm_cod', S.harm_copy_overdrive)
    S.harm_copy_overdrive = new_cod
    Tooltip(TIPS.harm_copy_overdrive)

    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)

    ---- Apply button ----
    if Btn('Apply Harmonies', BTN_H) then
        if not sel_s then
            local res = r.ShowMessageBox(
                'No time selection is active.\n\nAll notes in the full source MIDI item will be processed.\n\nContinue?',
                'Apply Harmonies', 1)
            if res == 1 then RunAction(HarmoniesAction) end
        else
            RunAction(HarmoniesAction)
        end
    end
    Tooltip(TIPS.harm_apply)
end
