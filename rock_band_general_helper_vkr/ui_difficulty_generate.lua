-- Difficulty > Generate sub-tab: build Hard, Medium and Easy automatically.
-- Requires (globals): S, r, ctx, TIPS, GEN_INSTRUMENTS, GEN_ALL_KEY, GenInstrumentByKey,
--   GenerateDifficulties (actions_difficulty_generate.lua), TrackCombo, Btn,
--   BtnGroupWidth, LabelColWidth, SectionHeader, Tooltip, RunAction, BTN_H, WIDTH_STD.

local ALL_LABEL = 'All instruments'

function DrawDifficultyGenerateTab(ctx, midi_tracks)
    r.ImGui_TextWrapped(ctx,
        'Builds each difficulty from the one above it: thins the notes the way official '
        .. 'charts do, reduces chords and colors, shortens sustains, then checks the result '
        .. 'with the same rules Validate uses.')

    SectionHeader('Instrument')
    local lbl_col = LabelColWidth({ 'Instrument', 'Track', 'Hard 8th runs' })

    local cur_key  = S.diff_gen_instrument
    local cur_inst = GenInstrumentByKey(cur_key)
    r.ImGui_Text(ctx, 'Instrument')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##diff_gen_inst', cur_inst and cur_inst.label or ALL_LABEL) then
        for _, inst in ipairs(GEN_INSTRUMENTS) do
            local is_sel = inst.key == cur_key
            if r.ImGui_Selectable(ctx, inst.label, is_sel) then S.diff_gen_instrument = inst.key end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        local all_sel = cur_key == GEN_ALL_KEY
        if r.ImGui_Selectable(ctx, ALL_LABEL, all_sel) then S.diff_gen_instrument = GEN_ALL_KEY end
        if all_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.diff_gen_instrument)

    -- Re-read after the combo: a pick this frame should show its own track row now.
    cur_inst = GenInstrumentByKey(S.diff_gen_instrument)
    local no_track = false
    if cur_inst then
        r.ImGui_Text(ctx, 'Track')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S[cur_inst.idx_field] = TrackCombo('##diff_gen_track', S[cur_inst.idx_field], midi_tracks)
        Tooltip(TIPS.diff_gen_track)
        no_track = S[cur_inst.idx_field] < 0
    else
        r.ImGui_TextWrapped(ctx,
            'Uses each instrument\'s default track (PART GUITAR, PART BASS, PART KEYS) and '
            .. 'skips any that is missing or muted.')
    end

    -- One row of radios, so plain SameLine flow (RadioGroupWidth is for aligning
    -- several radio rows against each other).
    r.ImGui_Text(ctx, 'Hard 8th runs')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Auto##gen_busy', S.diff_gen_busy_drop == 'auto') then
        S.diff_gen_busy_drop = 'auto'
    end
    Tooltip(TIPS.diff_gen_busy_drop)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Drop 1 per bar##gen_busy', S.diff_gen_busy_drop == 1) then
        S.diff_gen_busy_drop = 1
    end
    Tooltip(TIPS.diff_gen_busy_drop)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Drop 2 per bar##gen_busy', S.diff_gen_busy_drop == 2) then
        S.diff_gen_busy_drop = 2
    end
    Tooltip(TIPS.diff_gen_busy_drop)

    SectionHeader('Generate')
    local key = S.diff_gen_instrument
    local labels = { 'Hard', 'Medium', 'Easy', 'Hard > Medium > Easy' }
    local bw = BtnGroupWidth({ 'Hard', 'Medium', 'Easy' })

    if no_track then r.ImGui_BeginDisabled(ctx) end
    if Btn(labels[1] .. '##gen_h', BTN_H, bw) then RunAction(function() GenerateDifficulties(key, { 'H' }) end) end
    Tooltip(TIPS.diff_gen_tier)
    r.ImGui_SameLine(ctx)
    if Btn(labels[2] .. '##gen_m', BTN_H, bw) then RunAction(function() GenerateDifficulties(key, { 'M' }) end) end
    Tooltip(TIPS.diff_gen_tier)
    r.ImGui_SameLine(ctx)
    if Btn(labels[3] .. '##gen_e', BTN_H, bw) then RunAction(function() GenerateDifficulties(key, { 'E' }) end) end
    Tooltip(TIPS.diff_gen_tier)
    r.ImGui_SameLine(ctx)
    if Btn(labels[4] .. '##gen_hme', BTN_H) then
        RunAction(function() GenerateDifficulties(key, { 'H', 'M', 'E' }) end)
    end
    Tooltip(TIPS.diff_gen_chain)
    if no_track then r.ImGui_EndDisabled(ctx) end
end
