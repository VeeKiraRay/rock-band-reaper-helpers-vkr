-- Tab Input and MIDI tab rendering

function DrawTabInputTab(ctx)
    local _bp    = 40
    local bw_add = r.ImGui_CalcTextSize(ctx, 'Add note')  + _bp
    local bw_run = r.ImGui_CalcTextSize(ctx, 'Run guide') + _bp

    -- Instrument mode selector
    if r.ImGui_RadioButton(ctx, 'Guitar / Bass##tabmode', S.tab_input_mode == 0) then
        S.tab_input_mode = 0
    end
    Tooltip(TIPS.tab_input_mode)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Keys / Pro Keys##tabmode', S.tab_input_mode == 1) then
        S.tab_input_mode = 1
    end
    Tooltip(TIPS.tab_input_mode)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Vocal##tabmode', S.tab_input_mode == 2) then
        S.tab_input_mode = 2
    end
    Tooltip(TIPS.tab_input_mode)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Format selector (shared across all modes)
    if r.ImGui_RadioButton(ctx, 'Horizontal##tabfmt', S.mc_gtr_tab_format == 0) then
        S.mc_gtr_tab_format = 0
    end
    Tooltip(TIPS.mc_gtr_tab_format)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Vertical##tabfmt', S.mc_gtr_tab_format == 1) then
        S.mc_gtr_tab_format = 1
    end
    Tooltip(TIPS.mc_gtr_tab_format)

    r.ImGui_Spacing(ctx)

    -- Mode-specific option (one checkbox per mode, same vertical slot)
    if S.tab_input_mode == 0 then
        _, S.mc_gtr_tab_ordered = r.ImGui_Checkbox(ctx, 'Notes are in play order', S.mc_gtr_tab_ordered)
        Tooltip(TIPS.mc_gtr_tab_ordered)
        r.ImGui_Spacing(ctx)
    elseif S.tab_input_mode == 1 then
        _, S.pk_tab_animation = r.ImGui_Checkbox(
            ctx, 'For animation (full C2\xe2\x80\x93C4, no lane windows)', S.pk_tab_animation)
        Tooltip(TIPS.pk_tab_animation)
        r.ImGui_Spacing(ctx)
    end

    -- Shared textarea
    local line_h  = r.ImGui_GetTextLineHeightWithSpacing(ctx)
    local h_horiz = math.floor(line_h * 10 + 6)
    local h_vert  = math.floor(line_h * 6 + 6)
    if S.mc_gtr_tab_format == 0 then
        local changed, val = r.ImGui_InputTextMultiline(
            ctx, '##tab_input_h', S.mc_gtr_tab_input_h, 0, h_horiz)
        if changed then S.mc_gtr_tab_input_h = val end
    else
        local changed, val = r.ImGui_InputTextMultiline(
            ctx, '##tab_input_v', S.mc_gtr_tab_input_v, 0, h_vert)
        if changed then S.mc_gtr_tab_input_v = val end
    end

    r.ImGui_Spacing(ctx)

    -- Shared Add note button
    if r.ImGui_Button(ctx, 'Add note', bw_add, 24) then
        if S.mc_gtr_tab_format == 0 then
            S.mc_gtr_tab_input_h = S.mc_gtr_tab_input_h .. '- - - - - -\n'
        else
            if S.mc_gtr_tab_input_v:match('^%s*$') then
                S.mc_gtr_tab_input_v = '-\n-\n-\n-\n-\n-'
            else
                S.mc_gtr_tab_input_v = ReformatVerticalTab(S.mc_gtr_tab_input_v, true)
            end
        end
    end
    Tooltip(TIPS.mc_gtr_add_note)
    r.ImGui_SameLine(ctx)

    -- Mode-specific Run guide
    if S.tab_input_mode == 0 then
        if r.ImGui_Button(ctx, 'Run guide', bw_run, 24) then RunAction(GuitarTabGuide) end
        Tooltip(TIPS.mc_gtr_run_guide)
    elseif S.tab_input_mode == 1 then
        if r.ImGui_Button(ctx, 'Run guide', bw_run, 24) then RunAction(ProKeysTabGuide) end
        Tooltip(TIPS.pk_run_guide)
    else
        if r.ImGui_Button(ctx, 'Run guide', bw_run, 24) then RunAction(VocalTabGuide) end
        Tooltip(TIPS.voc_run_guide)
    end
end

function DrawMIDITab(ctx)
    local _bp         = 40
    local midi_tracks = S.midi_track_list
    local bw_ali        = r.ImGui_CalcTextSize(ctx, 'Align MIDI')      + _bp
    local bw_resize     = r.ImGui_CalcTextSize(ctx, 'Resize all MIDI') + _bp
    local bw_set_search = r.ImGui_CalcTextSize(ctx, 'Set Search')      + _bp
    local bw_set_rep    = r.ImGui_CalcTextSize(ctx, 'Set Replace')     + _bp
    local bw_rep_all    = r.ImGui_CalcTextSize(ctx, 'Replace All')     + _bp
    local bw_fill       = r.ImGui_CalcTextSize(ctx, 'Fill Range')      + _bp
    local is_busy_mr    = S.busy

    SectionHeader('MIDI Alignment')

    r.ImGui_Text(ctx, 'Source track')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.ma_midi_src_idx = TrackCombo('##ma_src', S.ma_midi_src_idx, midi_tracks)
    Tooltip(TIPS.ma_midi_src)

    r.ImGui_Spacing(ctx)
    if r.ImGui_RadioButton(ctx, 'Move first note to time selection start', S.ma_mode == 0) then
        S.ma_mode = 0
    end
    if r.ImGui_RadioButton(ctx, 'Move + Stretch to fit time selection', S.ma_mode == 1) then
        S.ma_mode = 1
    end
    Tooltip(TIPS.ma_mode)

    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, 'Align MIDI', bw_ali, 24) then
        RunAction(AlignMIDI)
    end
    Tooltip(TIPS.ma_align)

    r.ImGui_Separator(ctx)
    SectionHeader('MIDI Length Sync')

    r.ImGui_Text(ctx, 'Reference track')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.ms_ref_idx = TrackCombo('##ms_ref', S.ms_ref_idx, midi_tracks)
    Tooltip(TIPS.ms_ref)

    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, 'Resize all MIDI', bw_resize, 24) then
        RunAction(ResizeAllMIDI)
    end
    Tooltip(TIPS.ms_resize)

    r.ImGui_Separator(ctx)
    SectionHeader('Pattern Replace')

    r.ImGui_Text(ctx, 'Source track')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 200)
    S.mr_midi_src_idx = TrackCombo('##mr_src', S.mr_midi_src_idx, midi_tracks)
    Tooltip(TIPS.mr_midi_src)
    if S.mr_midi_src_idx >= 0 then
        local _ed      = r.MIDIEditor_GetActive()
        local _ed_take = _ed and r.MIDIEditor_GetTake(_ed)
        local _ed_tr   = _ed_take and r.GetMediaItemTake_Track(_ed_take)
        if _ed_tr and _ed_tr ~= r.GetTrack(0, S.mr_midi_src_idx) then
            r.ImGui_TextColored(ctx, 0xFFAA00FF, '! Source track not open in the MIDI editor.')
        end
    end

    r.ImGui_Spacing(ctx)
    if is_busy_mr then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Set Search', bw_set_search, 24) then
        RunAction(SetSearchPattern)
    end
    Tooltip(TIPS.mr_set_search)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Set Replace', bw_set_rep, 24) then
        RunAction(SetReplacePattern)
    end
    Tooltip(TIPS.mr_set_replace)
    if is_busy_mr then r.ImGui_EndDisabled(ctx) end

    local no_replace = not S.mr_replace_notes
    local no_both    = not S.mr_search_notes or no_replace
    if is_busy_mr or no_both then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Replace All', bw_rep_all, 24) then
        RunAction(DoMIDIPatternReplace)
    end
    Tooltip(TIPS.mr_do_replace)
    if is_busy_mr or no_both then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    if is_busy_mr or no_replace then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Fill Range', bw_fill, 24) then
        RunAction(FillRange)
    end
    Tooltip(TIPS.mr_fill_range)
    if is_busy_mr or no_replace then r.ImGui_EndDisabled(ctx) end

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Search: ')
    r.ImGui_SameLine(ctx)
    if S.mr_search_notes then
        r.ImGui_Text(ctx, S.mr_search_label)
    else
        r.ImGui_TextDisabled(ctx, 'not set')
    end
    r.ImGui_Text(ctx, 'Replace:')
    r.ImGui_SameLine(ctx)
    if S.mr_replace_notes then
        r.ImGui_Text(ctx, S.mr_replace_label)
    else
        r.ImGui_TextDisabled(ctx, 'not set')
    end
end
