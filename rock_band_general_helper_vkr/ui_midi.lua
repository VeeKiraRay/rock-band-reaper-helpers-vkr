-- Tab Input and MIDI tab rendering

-- MIDI > Pattern: Difficulty filter dropdown options (S.mr_diff_idx).
local MR_DIFF_OPTIONS = {
    { idx = 0, label = 'All' },
    { idx = 1, label = 'Expert' },
    { idx = 2, label = 'Hard' },
    { idx = 3, label = 'Medium' },
    { idx = 4, label = 'Easy' },
}

-- Shared body for each Tab Input mode sub-tab: format selector, mode-specific
-- option, textarea, and Add note / Run guide. mode: 0=Guitar/Bass, 1=Keys/Pro
-- Keys, 2=Vocal (mirrors S.tab_input_mode, kept in sync for persistence).
local function _DrawTabInputBody(mode, radio_w_ti)
    S.tab_input_mode = mode

    -- Format selector (shared across all modes)
    if r.ImGui_RadioButton(ctx, 'Horizontal##tabfmt', S.mc_gtr_tab_format == 0) then
        S.mc_gtr_tab_format = 0
    end
    Tooltip(TIPS.mc_gtr_tab_format)
    r.ImGui_SameLine(ctx, radio_w_ti)
    if r.ImGui_RadioButton(ctx, 'Vertical##tabfmt', S.mc_gtr_tab_format == 1) then
        S.mc_gtr_tab_format = 1
    end
    Tooltip(TIPS.mc_gtr_tab_format)

    r.ImGui_Spacing(ctx)

    -- Mode-specific option (one checkbox per mode, same vertical slot)
    if mode == 0 then
        _, S.mc_gtr_tab_ordered = r.ImGui_Checkbox(ctx, 'Notes are in play order', S.mc_gtr_tab_ordered)
        Tooltip(TIPS.mc_gtr_tab_ordered)
        r.ImGui_Spacing(ctx)
    elseif mode == 1 then
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
    local bw_tabinput = BtnGroupWidth({ 'Add note', 'Run guide' })
    if Btn('Add note', BTN_H, bw_tabinput) then
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
    if mode == 0 then
        if Btn('Run guide', BTN_H, bw_tabinput) then RunAction(GuitarTabGuide) end
        Tooltip(TIPS.mc_gtr_run_guide)
    elseif mode == 1 then
        if Btn('Run guide', BTN_H, bw_tabinput) then RunAction(ProKeysTabGuide) end
        Tooltip(TIPS.pk_run_guide)
    else
        if Btn('Run guide', BTN_H, bw_tabinput) then RunAction(VocalTabGuide) end
        Tooltip(TIPS.voc_run_guide)
    end
end

function DrawTabInputTab(ctx)
    local radio_w_ti = RadioGroupWidth({ 'Horizontal', 'Vertical' })

    if r.ImGui_BeginTabBar(ctx, '##tabinput_subtabs') then
        if r.ImGui_BeginTabItem(ctx, 'Guitar / Bass') then
            Tooltip(TIPS.tab_input_mode)
            r.ImGui_Spacing(ctx)
            _DrawTabInputBody(0, radio_w_ti)
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, 'Keys / Pro Keys') then
            Tooltip(TIPS.tab_input_mode)
            r.ImGui_Spacing(ctx)
            _DrawTabInputBody(1, radio_w_ti)
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, 'Vocal') then
            Tooltip(TIPS.tab_input_mode)
            r.ImGui_Spacing(ctx)
            _DrawTabInputBody(2, radio_w_ti)
            r.ImGui_EndTabItem(ctx)
        end
        r.ImGui_EndTabBar(ctx)
    end
end

function DrawMIDITab(ctx)
    local midi_tracks = S.midi_track_list
    local is_busy_mr    = S.busy

    if r.ImGui_BeginTabBar(ctx, '##midi_subtabs') then

        ------------------------------------------------
        -- MIDI > Alignment sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Alignment') then
            r.ImGui_Text(ctx, 'Source track')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
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
            if Btn('Align MIDI', BTN_H) then
                RunAction(AlignMIDI)
            end
            Tooltip(TIPS.ma_align)

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- MIDI > Length sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Length') then
            r.ImGui_Text(ctx, 'Reference track')
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            S.ms_ref_idx = TrackCombo('##ms_ref', S.ms_ref_idx, midi_tracks)
            Tooltip(TIPS.ms_ref)

            r.ImGui_Spacing(ctx)
            if Btn('Resize all MIDI', BTN_H) then
                RunAction(ResizeAllMIDI)
            end
            Tooltip(TIPS.ms_resize)

            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- MIDI > Pattern sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Pattern') then
            local lbl_col_pat = LabelColWidth({ 'Source track', 'Difficulty' })

            r.ImGui_Text(ctx, 'Source track')
            r.ImGui_SameLine(ctx, lbl_col_pat)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
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

            r.ImGui_Text(ctx, 'Difficulty')
            r.ImGui_SameLine(ctx, lbl_col_pat)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
            S.mr_diff_idx = TrackCombo('##mr_diff', S.mr_diff_idx, MR_DIFF_OPTIONS)
            Tooltip(TIPS.mr_diff)
            if S.mr_midi_src_idx >= 0 then
                local _tr = r.GetTrack(0, S.mr_midi_src_idx)
                if _tr then
                    local _, _trname = r.GetTrackName(_tr)
                    local _lo, _hi = GetPatternPitchRange(_trname, S.mr_diff_idx)
                    r.ImGui_TextDisabled(ctx, ('Pitch range: %d\xe2\x80\x93%d'):format(_lo, _hi))
                end
            end

            r.ImGui_Spacing(ctx)
            local bw_pat = BtnGroupWidth({ 'Set Search', 'Set Replace', 'Replace All', 'Fill Range' })
            if is_busy_mr then r.ImGui_BeginDisabled(ctx) end
            if Btn('Set Search', BTN_H, bw_pat) then
                RunAction(SetSearchPattern)
            end
            Tooltip(TIPS.mr_set_search)
            r.ImGui_SameLine(ctx)
            if Btn('Set Replace', BTN_H, bw_pat) then
                RunAction(SetReplacePattern)
            end
            Tooltip(TIPS.mr_set_replace)
            if is_busy_mr then r.ImGui_EndDisabled(ctx) end

            local no_replace = not S.mr_replace_notes
            local no_both    = not S.mr_search_notes or no_replace
            if is_busy_mr or no_both then r.ImGui_BeginDisabled(ctx) end
            if Btn('Replace All', BTN_H, bw_pat) then
                RunAction(DoMIDIPatternReplace)
            end
            Tooltip(TIPS.mr_do_replace)
            if is_busy_mr or no_both then r.ImGui_EndDisabled(ctx) end
            r.ImGui_SameLine(ctx)
            if is_busy_mr or no_replace then r.ImGui_BeginDisabled(ctx) end
            if Btn('Fill Range', BTN_H, bw_pat) then
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

            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end
end
