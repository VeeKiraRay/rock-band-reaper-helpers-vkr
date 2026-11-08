-- Difficulty tab rendering: the Generate sub-tab (ui_difficulty_generate.lua) and
-- Validate & copy, one sub-tab for every instrument picked from a dropdown.

local TIER_LABEL = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }
local UPPER_TIER = { H = 'X', M = 'H', E = 'M' }

-- Validate & copy per instrument (keys = GEN_INSTRUMENTS keys, in that order).
-- tracks: the track rows ({ label, S field, tip }); tier_field: Pro Keys' track per
-- tier (else every tier lives on the one track); copy / validate / validate_all: the
-- actions; reset: the fields Auto-detect clears before SetDefaultDifficultyTracks.
local VC = {
    gtr = {
        tracks = { { 'PART GUITAR', 'diff_gtr_idx', 'diff_gb_track' } },
        copy_text = 'Copy notes from the tier above onto this one\'s own range:',
        validate_text = 'Check a difficulty range against Guitar/Bass authoring rules:',
        copy = function(t) CopyGtrBassDiff('gtr', t) end,
        validate = function(t) ValidateGtrBassDiff('gtr', t) end,
        validate_all = function() ValidateAllGtrBass('gtr') end,
        tips = { autodetect = 'diff_gb_autodetect', copy = 'diff_gb_copy', validate = 'diff_gb_validate',
                 validate_all = 'diff_gb_validate_all' },
    },
    bass = {
        tracks = { { 'PART BASS', 'diff_bass_idx', 'diff_gb_track' } },
        copy_text = 'Copy notes from the tier above onto this one\'s own range:',
        validate_text = 'Check a difficulty range against Guitar/Bass authoring rules:',
        copy = function(t) CopyGtrBassDiff('bass', t) end,
        validate = function(t) ValidateGtrBassDiff('bass', t) end,
        validate_all = function() ValidateAllGtrBass('bass') end,
        tips = { autodetect = 'diff_gb_autodetect', copy = 'diff_gb_copy', validate = 'diff_gb_validate',
                 validate_all = 'diff_gb_validate_all' },
    },
    pk = {
        tracks = { { 'Expert', 'diff_pk_x_idx', 'diff_pk_x' }, { 'Hard', 'diff_pk_h_idx', 'diff_pk_h' },
                   { 'Medium', 'diff_pk_m_idx', 'diff_pk_m' }, { 'Easy', 'diff_pk_e_idx', 'diff_pk_e' } },
        tier_field = { X = 'diff_pk_x_idx', H = 'diff_pk_h_idx', M = 'diff_pk_m_idx', E = 'diff_pk_e_idx' },
        copy_text = 'Copy notes from the tier above onto this one\'s own track:',
        validate_text = 'Check a difficulty track against RBN authoring rules:',
        copy = function(t) CopyProKeysDiff(t) end,
        validate = function(t) ValidateProKeysDiff(t) end,
        validate_all = function() ValidateAllProKeys() end,
        tips = { autodetect = 'diff_autodetect', copy = 'diff_pk_copy', validate = 'diff_validate',
                 validate_all = 'diff_validate_all' },
    },
    keys = {
        tracks = { { 'PART KEYS', 'diff_5k_idx', 'diff_5k_track' } },
        copy_text = 'Copy notes from the tier above onto this one\'s own range:',
        validate_text = 'Check a difficulty range against Keys authoring rules:',
        copy = function(t) CopyKeys5Diff(t) end,
        validate = function(t) ValidateKeys5Diff(t) end,
        validate_all = function() ValidateAllKeys5() end,
        tips = { autodetect = 'diff_5k_autodetect', copy = 'diff_5k_copy', validate = 'diff_5k_validate',
                 validate_all = 'diff_5k_validate_all' },
        pk_reduce = true,   -- the "Reduce using Pro Keys" checkbox above the Copy buttons
    },
    drums = {
        tracks = { { 'PART DRUMS', 'diff_drums_idx', 'diff_drums_track' } },
        copy_text = 'Copy notes from the tier above onto this one\'s own range:',
        validate_text = 'Check a difficulty range against Drums authoring rules:',
        copy = function(t) CopyDrumsDiff(t) end,
        validate = function(t) ValidateDrumsDiff(t) end,
        validate_all = function() ValidateAllDrums() end,
        tips = { autodetect = 'diff_drums_autodetect', copy = 'diff_drums_copy', validate = 'diff_drums_validate',
                 validate_all = 'diff_drums_validate_all' },
    },
}

-- A tier's track is picked: Pro Keys per tier, the others their one track.
local function HasTier(spec, tier)
    local field = spec.tier_field and spec.tier_field[tier] or spec.tracks[1][2]
    return S[field] >= 0
end

local function DrawValidateCopyTab(ctx, midi_tracks)
    local key  = S.diff_vc_instrument
    local inst = GenInstrumentByKey(key) or GEN_INSTRUMENTS[1]
    local spec = VC[inst.key]

    local col_labels = { 'Instrument' }
    for _, t in ipairs(spec.tracks) do col_labels[#col_labels + 1] = t[1] end
    local lbl_col = LabelColWidth(col_labels)

    r.ImGui_Text(ctx, 'Instrument')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##diff_vc_inst', inst.label) then
        for _, it in ipairs(GEN_INSTRUMENTS) do
            local is_sel = it.key == inst.key
            if r.ImGui_Selectable(ctx, it.label, is_sel) then
                S.diff_vc_instrument  = it.key
                S.diff_gen_instrument = it.key   -- Generate follows the same instrument
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.diff_vc_instrument)

    -- Re-read after the combo: a pick this frame shows its own rows now.
    inst = GenInstrumentByKey(S.diff_vc_instrument) or GEN_INSTRUMENTS[1]
    spec = VC[inst.key]
    for _, t in ipairs(spec.tracks) do
        r.ImGui_Text(ctx, t[1])
        r.ImGui_SameLine(ctx, lbl_col)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S[t[2]] = TrackCombo('##diff_vc_' .. t[2], S[t[2]], midi_tracks)
        Tooltip(TIPS[t[3]])
    end

    r.ImGui_Spacing(ctx)
    if Btn(#spec.tracks > 1 and 'Auto-detect tracks' or 'Auto-detect track', BTN_H) then
        for _, t in ipairs(spec.tracks) do S[t[2]] = -1 end
        SetDefaultDifficultyTracks()
        S.status = inst.label .. (#spec.tracks > 1 and ' tracks' or ' track') .. ' auto-detected.'
    end
    Tooltip(TIPS[spec.tips.autodetect])

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Copy to next difficulty')
    r.ImGui_TextWrapped(ctx, spec.copy_text)
    r.ImGui_Spacing(ctx)
    if spec.pk_reduce then
        _, S.diff_5k_pk_reduce = r.ImGui_Checkbox(ctx, 'Reduce using Pro Keys (same tier)', S.diff_5k_pk_reduce)
        Tooltip(TIPS.diff_5k_pk_reduce)
        r.ImGui_Spacing(ctx)
    end
    local bw_copy = BtnGroupWidth({ 'Copy to Hard', 'Copy to Medium', 'Copy to Easy' })
    for i, t in ipairs({ 'H', 'M', 'E' }) do
        if i > 1 then r.ImGui_SameLine(ctx) end
        local off = not (HasTier(spec, UPPER_TIER[t]) and HasTier(spec, t))
        if off then r.ImGui_BeginDisabled(ctx) end
        if Btn('Copy to ' .. TIER_LABEL[t] .. '##vc_copy', BTN_H, bw_copy) then
            RunAction(function() spec.copy(t) end)
        end
        Tooltip(TIPS[spec.tips.copy])
        if off then r.ImGui_EndDisabled(ctx) end
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Validate')
    r.ImGui_TextWrapped(ctx, spec.validate_text)
    r.ImGui_Spacing(ctx)
    local bw_val = BtnGroupWidth({
        'Validate Expert', 'Validate Hard', 'Validate Medium', 'Validate Easy', 'Validate All',
    })
    -- Expert / Hard / Medium on the first row, Easy / All on the second.
    local any = false
    for i, t in ipairs({ 'X', 'H', 'M', 'E' }) do
        if i == 2 or i == 3 then r.ImGui_SameLine(ctx) end
        local off = not HasTier(spec, t)
        any = any or not off
        if off then r.ImGui_BeginDisabled(ctx) end
        if Btn('Validate ' .. TIER_LABEL[t] .. '##vc_val', BTN_H, bw_val) then
            RunAction(function() spec.validate(t) end)
        end
        Tooltip(TIPS[spec.tips.validate])
        if off then r.ImGui_EndDisabled(ctx) end
    end
    r.ImGui_SameLine(ctx)
    if not any then r.ImGui_BeginDisabled(ctx) end
    if Btn('Validate All##vc_val', BTN_H, bw_val) then RunAction(spec.validate_all) end
    Tooltip(TIPS[spec.tips.validate_all])
    if not any then r.ImGui_EndDisabled(ctx) end
end

function DrawDifficultyTab(ctx)
    local midi_tracks = S.midi_track_list

    if r.ImGui_BeginTabBar(ctx, '##diff_subtabs') then
        if r.ImGui_BeginTabItem(ctx, 'Generate') then
            DrawDifficultyGenerateTab(ctx, midi_tracks)
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, 'Validate & copy') then
            DrawValidateCopyTab(ctx, midi_tracks)
            r.ImGui_EndTabItem(ctx)
        end
        r.ImGui_EndTabBar(ctx)
    end

    -- Shared overwrite confirmation, set by any of the four Copy*Diff functions
    -- or by GenerateDifficulties when the target already has notes. Rendered once
    -- here regardless of which sub-tab triggered it. confirm_label is optional.
    if S.diff_copy_pending then
        r.ImGui_OpenPopup(ctx, 'ConfirmCopyOverwrite')
    end
    if r.ImGui_BeginPopupModal(ctx, 'ConfirmCopyOverwrite', nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        local confirm_label = 'Clear and Copy'
        if S.diff_copy_pending then
            r.ImGui_Text(ctx, S.diff_copy_pending.message)
            confirm_label = S.diff_copy_pending.confirm_label or confirm_label
        end
        r.ImGui_Spacing(ctx)
        -- The pending entry is cleared BEFORE its callback runs: a callback may ask the
        -- next question (Generate: overwrite, then "Hard equals Expert"), and clearing
        -- afterwards would drop it.
        local pending = S.diff_copy_pending
        if Btn(confirm_label .. '##confirm_overwrite', BTN_H) then
            S.diff_copy_pending = nil
            r.ImGui_CloseCurrentPopup(ctx)
            if pending then RunAction(pending.on_confirm) end
        end
        -- Optional second answer (alt_label / on_alt): a question where both answers
        -- go ahead, with Cancel still stopping everything.
        if pending and pending.alt_label then
            r.ImGui_SameLine(ctx)
            if Btn(pending.alt_label .. '##alt_overwrite', BTN_H) then
                S.diff_copy_pending = nil
                r.ImGui_CloseCurrentPopup(ctx)
                RunAction(pending.on_alt)
            end
        end
        r.ImGui_SameLine(ctx)
        if Btn('Cancel', BTN_H) then
            S.diff_copy_pending = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end
