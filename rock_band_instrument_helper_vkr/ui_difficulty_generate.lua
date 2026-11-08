-- Difficulty > Generate sub-tab: build Hard, Medium and Easy automatically.
-- Requires (globals): S, r, ctx, TIPS, GEN_INSTRUMENTS, GEN_ALL_KEY, GenInstrumentByKey,
--   GEN_STYLES, GEN_STYLE_ROWS, GenStyleValues, GenSetStyle,
--   GenerateDifficulties (actions_difficulty_generate.lua), TrackCombo, Btn,
--   BtnGroupWidth, LabelColWidth, RadioGroupWidth, SectionHeader, Tooltip, RunAction, BTN_H,
--   WIDTH_STD.

local ALL_LABEL = 'All instruments'

function DrawDifficultyGenerateTab(ctx, midi_tracks)
    r.ImGui_TextWrapped(ctx,
        'Builds each difficulty from the one above it: thins the notes the way official '
        .. 'charts do, reduces chords and colors, shortens sustains, then checks the result '
        .. 'with the same rules Validate uses.')

    r.ImGui_Spacing(ctx)
    local col_labels = { 'Instrument', 'Track', '2X track', 'Expert track', 'Medium track', 'Style' }
    for _, row in ipairs(GEN_STYLE_ROWS) do col_labels[#col_labels + 1] = row.label end
    local lbl_col = LabelColWidth(col_labels)

    local cur_key  = S.diff_gen_instrument
    local cur_inst = GenInstrumentByKey(cur_key)
    r.ImGui_Text(ctx, 'Instrument')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##diff_gen_inst', cur_inst and cur_inst.label or ALL_LABEL) then
        for _, inst in ipairs(GEN_INSTRUMENTS) do
            local is_sel = inst.key == cur_key
            if r.ImGui_Selectable(ctx, inst.label, is_sel) then
                S.diff_gen_instrument = inst.key
                S.diff_vc_instrument  = inst.key   -- Validate & copy follows a single instrument
            end
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
        -- Pro Keys: a track per tier, the same selection as Validate & copy.
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

    -- A fact about the song's chart, not a rule choice: editable in every style.
    local drums_rows = S.diff_gen_instrument == 'drums' or S.diff_gen_instrument == GEN_ALL_KEY
    if drums_rows then
        local _, v = r.ImGui_Checkbox(ctx, 'Only 2x bass pedal authored on PART DRUMS##gen_2x_on_1x',
                                      S.diff_gen_drums_2x_on_1x)
        S.diff_gen_drums_2x_on_1x = v
        Tooltip(TIPS.diff_gen_drums_2x_on_1x)
    end

    -- Rule style, then its options. The rows show the values the style runs with
    -- (GenStyleValues); only Custom edits them. All radios share one per-option pitch.
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Rules')
    local rows = {}
    for _, row in ipairs(GEN_STYLE_ROWS) do
        if drums_rows or not row.drums then rows[#rows + 1] = row end
    end
    local all = {}
    for _, st in ipairs(GEN_STYLES) do all[#all + 1] = st.label end
    for _, row in ipairs(rows) do for _, o in ipairs(row.opts) do all[#all + 1] = o[2] end end
    local radio_w = RadioGroupWidth(all)

    r.ImGui_Text(ctx, 'Style')
    for i, st in ipairs(GEN_STYLES) do
        r.ImGui_SameLine(ctx, lbl_col + (i - 1) * radio_w)
        if r.ImGui_RadioButton(ctx, st.label .. '##gen_style', S.diff_gen_style == st.key) then GenSetStyle(st.key) end
        Tooltip(TIPS.diff_gen_style)
    end

    local values = GenStyleValues()
    local locked = S.diff_gen_style ~= 'custom'   -- snapshot: a click below cannot change it
    for _, row in ipairs(rows) do
        r.ImGui_Text(ctx, row.label)
        if locked then r.ImGui_BeginDisabled(ctx) end
        for i, o in ipairs(row.opts) do
            r.ImGui_SameLine(ctx, lbl_col + (i - 1) * radio_w)
            if r.ImGui_RadioButton(ctx, o[2] .. '##' .. row.id, values[row.key] == o[1]) and not locked then
                S[row.field] = o[1]
            end
            -- Tooltip() skips disabled items; the read-only rows keep theirs.
            if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled()) then
                r.ImGui_SetTooltip(ctx, TIPS[row.field])
            end
        end
        if locked then r.ImGui_EndDisabled(ctx) end
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
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
