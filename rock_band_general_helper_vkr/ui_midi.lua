-- Tab Input and MIDI tab rendering.
--
-- The MIDI > Pattern sub-tab's body lives in ui_midi_pattern.lua, because the
-- standalone rock_band_midi_pattern_vkr.lua window draws it too; this file only
-- wraps it in a tab item. MidiEditorTrackWarning moved to ui_common.lua for the
-- same reason (Pattern and Length both call it).

-- MIDI > Length > Midi note: Difficulty dropdown options (S.mn_diff_idx).
-- No "All" entry - sustain/gap rules differ per tier.
local MN_DIFF_OPTIONS = {
    { idx = 1, label = 'Expert' },
    { idx = 2, label = 'Hard' },
    { idx = 3, label = 'Medium' },
    { idx = 4, label = 'Easy' },
}

-- MIDI > Length > Midi note: Note size dropdown options (S.mn_note_denom).
-- No 1/8 entry: 1/8 is the sustain threshold, so a "non-sustain" target can
-- never land on it.
local MN_NOTE_SIZE_OPTIONS = {
    { idx = 16,  label = '1/16' },
    { idx = 32,  label = '1/32' },
    { idx = 64,  label = '1/64' },
    { idx = 128, label = '1/128' },
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
    if mode == 1 then
        _, S.pk_tab_animation = r.ImGui_Checkbox(
            ctx, 'For animation (full C2-C4, no lane windows)', S.pk_tab_animation)
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
            SectionHeader('Midi note')

            local lbl_col_mn = LabelColWidth({ 'Source track', 'Difficulty', 'Note type', 'Note size' })

            r.ImGui_Text(ctx, 'Source track')
            r.ImGui_SameLine(ctx, lbl_col_mn)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            S.mn_midi_idx = TrackCombo('##mn_track', S.mn_midi_idx, midi_tracks)
            Tooltip(TIPS.mn_midi_track)
            MidiEditorTrackWarning(S.mn_midi_idx)

            -- Picking a tier prefills the standard gap for it; a manual slider
            -- tweak afterwards sticks (only a CHANGE of tier overwrites it).
            r.ImGui_Text(ctx, 'Difficulty')
            r.ImGui_SameLine(ctx, lbl_col_mn)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
            local prev_diff_mn = S.mn_diff_idx
            S.mn_diff_idx = TrackCombo('##mn_diff', S.mn_diff_idx, MN_DIFF_OPTIONS)
            Tooltip(TIPS.mn_diff)
            if S.mn_diff_idx ~= prev_diff_mn then
                S.mn_sustain_32nds = SustainGapDefaultForDiff(S.mn_diff_idx) or S.mn_sustain_32nds
            end

            r.ImGui_Spacing(ctx)
            local radio_w_mn = RadioGroupWidth({ 'Non-sustains', 'Only sustains' })
            r.ImGui_Text(ctx, 'Note type')
            r.ImGui_SameLine(ctx, lbl_col_mn)
            if r.ImGui_RadioButton(ctx, 'Non-sustains##mn_type', S.mn_note_type == 0) then
                S.mn_note_type = 0
            end
            Tooltip(TIPS.mn_note_type)
            r.ImGui_SameLine(ctx, lbl_col_mn + radio_w_mn)
            if r.ImGui_RadioButton(ctx, 'Only sustains##mn_type', S.mn_note_type == 1) then
                S.mn_note_type = 1
            end
            Tooltip(TIPS.mn_note_type)

            if S.mn_note_type == 0 then
                r.ImGui_Text(ctx, 'Note size')
                r.ImGui_SameLine(ctx, lbl_col_mn)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
                S.mn_note_denom = TrackCombo('##mn_denom', S.mn_note_denom, MN_NOTE_SIZE_OPTIONS)
                Tooltip(TIPS.mn_note_denom)
            else
                r.ImGui_Text(ctx, '32nd note amount')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
                _, S.mn_sustain_32nds = r.ImGui_SliderInt(ctx, '##mn_gap32', S.mn_sustain_32nds, 0, 32)
                Tooltip(TIPS.mn_sustain_32nds)
            end

            r.ImGui_Spacing(ctx)
            if Btn('Adjust notes', BTN_H) then
                RunAction(AdjustMidiNoteLengths)
            end
            Tooltip(TIPS.mn_adjust)

            r.ImGui_Separator(ctx)
            SectionHeader('Midi track')

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
            DrawMIDIPatternTab()   -- ui_midi_pattern.lua (shared with the standalone)
            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end
end
