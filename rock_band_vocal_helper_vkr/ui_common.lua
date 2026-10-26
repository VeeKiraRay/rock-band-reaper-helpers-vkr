-- Vocal UI pieces shared by the main helper window and the standalone Pitch
-- Tuner (rock_band_pitch_tuner_vkr.lua). Anything both entry points draw lives
-- here rather than in ui.lua, which cannot be dofile'd by the standalone: its
-- last line is a bare r.defer(Loop) that would spawn the full helper window.
-- The track dropdown and the status/result panel are not vocal-specific and
-- live in lib/reaper_helper_ui.lua (TrackCombo, DrawStatusResultPanel).
--
-- Requires globals: r, ctx, S, TIPS, YIN_PRESETS, ApplyYINPreset,
--                   Btn, BtnWidth, Tooltip, BTN_H, WIDTH_STD

-- Soft sanity check for instrument presets: warn when the selected tracks
-- still look vocal-related. Advisory only - never blocks, settings apply
-- regardless. Returns a result-panel string, or nil when nothing looks off.
local function KeysPresetTrackWarnings()
    local lines = {}
    local mtr = TrackAtIndex(S.midi_idx)
    if mtr then
        local _, name = r.GetTrackName(mtr)
        local u = name:upper()
        if u:find('VOCAL', 1, true) or u:find('HARM', 1, true) then
            lines[#lines + 1] =
                ('Selected preset is piano, but the MIDI destination "%s" looks vocal-related.'):format(name)
        end
    end
    local atr = TrackAtIndex(S.audio_idx)
    if atr then
        local _, name = r.GetTrackName(atr)
        if name:upper():find('VOCAL', 1, true) then
            lines[#lines + 1] =
                ('Selected preset is piano, but the audio source "%s" contains "vocal".'):format(name)
        end
    end
    if #lines == 0 then return nil end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Did you mean to switch the track selectors? Settings were applied anyway.'
    return table.concat(lines, '\n')
end

-- One-shot preset applier for the YIN sliders + pitch range constraints.
-- Not a stateful selector: sliders remain the source of truth, so the combo
-- always previews 'Apply preset...' and selecting an entry just writes values.
-- col (optional): if given, draws 'Vocal style preset' as its own label at
-- the left, SameLine(col), then a blank-labelled combo - matching the
-- label-column convention used for every other row in the calling tab.
function YINPresetCombo(id_suffix, col)
    if col then
        r.ImGui_Text(ctx, 'Vocal style preset')
        r.ImGui_SameLine(ctx, col)
    end
    local label = col and ('##yinpreset' .. id_suffix) or ('Vocal style preset' .. id_suffix)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, label, 'Apply preset...') then
        for _, preset in ipairs(YIN_PRESETS) do
            if r.ImGui_Selectable(ctx, preset.label, false) then
                ApplyYINPreset(preset)
                S.status = 'Applied preset: ' .. preset.label
                -- Clears any stale result; shows track warnings for instrument presets.
                S.last_result = preset.keys and KeysPresetTrackWarnings() or nil
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.yin_preset)
end
