-- UI pieces shared by the main helper window and the standalone Pitch Tuner
-- (rock_band_pitch_tuner_vkr.lua). Anything both entry points draw lives here
-- rather than in ui.lua, which cannot be dofile'd by the standalone: its last
-- line is a bare r.defer(Loop) that would spawn the full helper window.
--
-- Requires globals: r, ctx, S, TIPS, YIN_PRESETS, ApplyYINPreset,
--                   Btn, BtnWidth, Tooltip, BTN_H, WIDTH_STD

-- TrackCombo variant that stores and matches by REAPER track index (.idx field)
-- rather than list position, so selections survive filter list rebuilds.
function FilteredTrackCombo(label, reaper_idx, track_list)
    local preview = '<no tracks>'
    for _, t in ipairs(track_list) do
        if t.idx == reaper_idx then preview = t.label; break end
    end
    -- If selection is not in this filtered list, look it up in the full list
    -- so the preview still shows the track name rather than a blank.
    if preview == '<no tracks>' and S.all_track_list then
        for _, t in ipairs(S.all_track_list) do
            if t.idx == reaper_idx then preview = t.label; break end
        end
    end
    local new_idx = reaper_idx
    if r.ImGui_BeginCombo(ctx, label, preview) then
        for _, t in ipairs(track_list) do
            local is_sel = (t.idx == reaper_idx)
            if r.ImGui_Selectable(ctx, t.label, is_sel) then new_idx = t.idx end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    return new_idx
end

-- Soft sanity check for instrument presets: warn when the selected tracks
-- still look vocal-related. Advisory only - never blocks, settings apply
-- regardless. Returns a result-panel string, or nil when nothing looks off.
local function KeysPresetTrackWarnings()
    local lines = {}
    local mtr = r.GetTrack(0, S.midi_idx)
    if mtr then
        local _, name = r.GetTrackName(mtr)
        local u = name:upper()
        if u:find('VOCAL', 1, true) or u:find('HARM', 1, true) then
            lines[#lines + 1] =
                ('Selected preset is piano, but the MIDI destination "%s" looks vocal-related.'):format(name)
        end
    end
    local atr = r.GetTrack(0, S.audio_idx)
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

-- Bottom-of-window status line plus the wrapped multi-line result panel.
-- show_undo: draw the right-aligned Undo button (main helper window). The
-- standalone tuner passes false - it makes no project edits, so there is
-- never anything of its own to undo.
function DrawStatusResultPanel(show_undo)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, S.status)
    if show_undo then
        r.ImGui_SameLine(ctx)
        local bw_und   = BtnWidth('Undo')
        local undo_str = r.Undo_CanUndo2(0) or ''
        local can_undo = undo_str ~= ''
        local avail_x  = r.ImGui_GetContentRegionAvail(ctx)
        if avail_x > bw_und + 4 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - bw_und))
        end
        if not can_undo then r.ImGui_BeginDisabled(ctx) end
        if Btn('Undo', BTN_H) then r.Undo_DoUndo2(0) end
        if not can_undo then r.ImGui_EndDisabled(ctx) end
        if can_undo then Tooltip('Undo: ' .. undo_str) end
    end
    if S.last_result then
        r.ImGui_Separator(ctx)
        r.ImGui_PushTextWrapPos(ctx, 0)
        for line in (S.last_result .. '\n'):gmatch('([^\n]*)\n') do
            if line ~= '' then
                r.ImGui_Text(ctx, line)
            else
                r.ImGui_Spacing(ctx)
            end
        end
        r.ImGui_PopTextWrapPos(ctx)
    end
end
