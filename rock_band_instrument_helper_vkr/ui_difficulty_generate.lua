-- Difficulty > Generate sub-tab: build Hard, Medium and Easy automatically.
-- Requires (globals): S, r, ctx, TIPS, GEN_INSTRUMENTS, GEN_ALL_KEY, GenInstrumentByKey,
--   GenerateDifficulties (actions_difficulty_generate.lua), TrackCombo, Btn,
--   BtnGroupWidth, LabelColWidth, RadioGroupWidth, SectionHeader, Tooltip, RunAction, BTN_H,
--   WIDTH_STD.

local ALL_LABEL = 'All instruments'

function DrawDifficultyGenerateTab(ctx, midi_tracks)
    r.ImGui_TextWrapped(ctx,
        'Builds each difficulty from the one above it: thins the notes the way official '
        .. 'charts do, reduces chords and colors, shortens sustains, then checks the result '
        .. 'with the same rules Validate uses.')

    SectionHeader('Instrument')
    local lbl_col = LabelColWidth({ 'Instrument', 'Track', '2X track', 'Expert track', 'Medium track', 'Hard 8th runs',
                                    'Hard fast runs', 'Drums Medium' })

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
    if cur_inst and cur_inst.tier_fields then
        -- Pro Keys: a track per tier, the same selection as the Pro Keys sub-tab.
        for _, row in ipairs({ { 'X', 'Expert track' }, { 'H', 'Hard track' },
                               { 'M', 'Medium track' }, { 'E', 'Easy track' } }) do
            local field = cur_inst.tier_fields[row[1]]
            r.ImGui_Text(ctx, row[2])
            r.ImGui_SameLine(ctx, lbl_col)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            S[field] = TrackCombo('##diff_gen_pk_' .. row[1], S[field], midi_tracks)
            Tooltip(TIPS.diff_gen_track)
        end
        no_track = S[cur_inst.tier_fields.X] < 0
    elseif cur_inst then
        r.ImGui_Text(ctx, 'Track')
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S[cur_inst.idx_field] = TrackCombo('##diff_gen_track', S[cur_inst.idx_field], midi_tracks)
        Tooltip(TIPS.diff_gen_track)
        no_track = S[cur_inst.idx_field] < 0
        if cur_inst.x2 then
            -- Drums: the song's PART DRUMS_2X too, generated in the same run ((none): no 2X).
            r.ImGui_Text(ctx, '2X track')
            r.ImGui_SameLine(ctx, lbl_col)
            r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
            S[cur_inst.x2.idx_field] = TrackCombo('##diff_gen_track2x', S[cur_inst.x2.idx_field], midi_tracks)
            Tooltip(TIPS.diff_gen_track2x)
            no_track = no_track and S[cur_inst.x2.idx_field] < 0
        end
    else
        r.ImGui_TextWrapped(ctx,
            'Uses each instrument\'s default track (PART GUITAR, PART BASS, PART REAL_KEYS_X/H/M/E, '
            .. 'PART KEYS, PART DRUMS and PART DRUMS_2X) and skips any that is missing or muted. '
            .. 'Pro Keys runs before Keys, and Keys follows the '
            .. 'Pro Keys it just generated; Drums 2X takes its kicks from the PART DRUMS tiers just made.')
    end

    -- Two rows of radios, aligned on one per-option pitch (RadioGroupWidth).
    local rows = {
        { label = 'Hard 8th runs', field = 'diff_gen_busy_drop', id = 'gen_busy', tip = TIPS.diff_gen_busy_drop,
          opts = { { 'auto', 'Auto' }, { 1, 'Drop 1 per bar' }, { 2, 'Drop 2 per bar' } } },
        { label = 'Hard fast runs', field = 'diff_gen_fast_runs', id = 'gen_fast', tip = TIPS.diff_gen_fast_runs,
          opts = { { 'rewrite', 'Rewrite' }, { 'auto', 'Auto' }, { 'thin', 'Thin' } } },
    }
    -- Drums only (or All instruments): Medium's kick/snare between hi-hat notes.
    local key_now = S.diff_gen_instrument
    if key_now == 'drums' or key_now == GEN_ALL_KEY then
        rows[#rows + 1] = { label = 'Drums Medium', field = 'diff_gen_drums_between', id = 'gen_dbtw',
                            tip = TIPS.diff_gen_drums_between,
                            opts = { { 'beats', 'Beats' }, { 'none', 'None' }, { 'keep', 'Keep' } } }
        rows[#rows + 1] = { label = 'Drums fast 8ths', field = 'diff_gen_drums_eighths', id = 'gen_d8',
                            tip = TIPS.diff_gen_drums_eighths,
                            opts = { { 'hands', 'Hands' }, { 'beats', 'Beats' } } }
    end
    local all = {}
    for _, row in ipairs(rows) do for _, o in ipairs(row.opts) do all[#all + 1] = o[2] end end
    local drums_rows = key_now == 'drums' or key_now == GEN_ALL_KEY
    local radio_w = RadioGroupWidth(all)
    for _, row in ipairs(rows) do
        r.ImGui_Text(ctx, row.label)
        for i, o in ipairs(row.opts) do
            r.ImGui_SameLine(ctx, lbl_col + (i - 1) * radio_w)
            if r.ImGui_RadioButton(ctx, o[2] .. '##' .. row.id, S[row.field] == o[1]) then S[row.field] = o[1] end
            Tooltip(row.tip)
        end
    end
    if drums_rows then
        local _, v = r.ImGui_Checkbox(ctx, 'Only 2x bass pedal authored on PART DRUMS##gen_2x_on_1x',
                                      S.diff_gen_drums_2x_on_1x)
        S.diff_gen_drums_2x_on_1x = v
        Tooltip(TIPS.diff_gen_drums_2x_on_1x)
    end

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
