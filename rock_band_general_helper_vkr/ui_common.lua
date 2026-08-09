-- UI pieces shared by the main helper window and the standalone MIDI Pattern
-- window (rock_band_midi_pattern_vkr.lua). Anything both entry points draw
-- lives here rather than in ui.lua, which cannot be dofile'd by a standalone:
-- its last line is a bare r.defer(Loop) that would spawn the full helper
-- window. Same reasoning as rock_band_vocal_helper_vkr/ui_common.lua, which
-- exists for the standalone Pitch Tuner.
--
-- Requires globals: r, ctx, S, Btn, BtnWidth, Tooltip, BTN_H, FormatTime,
--                   GetTimeSelection (lib/reaper_imgui_helpers.lua - load first)

-- Local variant of TrackCombo: matches by REAPER track index (t.idx), supports
-- reaper_idx = -1 as "(none)". Shadowing the lib's TrackCombo which uses array
-- indices and has no "(none)" entry.
function TrackCombo(label, reaper_idx, tracks)
    local preview = reaper_idx < 0 and '(none)' or '<no tracks>'
    if reaper_idx >= 0 then
        for _, t in ipairs(tracks) do
            if t.idx == reaper_idx then preview = t.label; break end
        end
        if preview == '<no tracks>' and S.all_track_list then
            for _, t in ipairs(S.all_track_list) do
                if t.idx == reaper_idx then preview = t.label; break end
            end
        end
    end
    local new_idx = reaper_idx
    if r.ImGui_BeginCombo(ctx, label, preview) then
        if r.ImGui_Selectable(ctx, '(none)', reaper_idx < 0) then new_idx = -1 end
        if reaper_idx < 0 then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, t in ipairs(tracks) do
            local is_sel = (t.idx == reaper_idx)
            if r.ImGui_Selectable(ctx, t.label, is_sel) then new_idx = t.idx end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    return new_idx
end

-- Warn when the selected track isn't the one open in the MIDI editor.
-- Silent when no editor is open, or when track_idx is unset.
-- Global rather than a ui_midi.lua local: the Length sub-tab (ui_midi.lua) and
-- the Pattern sub-tab (ui_midi_pattern.lua, also drawn by the standalone) both
-- call it, so it can no longer be private to either file.
function MidiEditorTrackWarning(track_idx)
    if track_idx < 0 then return end
    local ed      = r.MIDIEditor_GetActive()
    local ed_take = ed and r.MIDIEditor_GetTake(ed)
    local ed_tr   = ed_take and r.GetMediaItemTake_Track(ed_take)
    if ed_tr and ed_tr ~= r.GetTrack(0, track_idx) then
        r.ImGui_TextColored(ctx, 0xFFAA00FF, '! Source track not open in the MIDI editor.')
    end
end

-- Bottom-of-window time selection readout, status line, and the wrapped
-- multi-line result panel. Always visible below whatever the caller drew.
-- show_undo: draw the right-aligned Undo button. Both current callers pass
-- true - the main helper and the standalone both make project edits - but the
-- flag is kept so a read-only window can suppress it, as the vocal helper's
-- standalone tuner does.
--
-- A result line containing a tab is rendered as two columns (SameLine at 190);
-- several reports in this script are written that way.
function DrawStatusResultPanel(show_undo)
    local sel_s, sel_e = GetTimeSelection()

    r.ImGui_Separator(ctx)
    if sel_s then
        r.ImGui_Text(ctx, ('Time selection: %s - %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
    else
        r.ImGui_TextDisabled(ctx, 'No time selection')
    end
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
                local left, right = line:match('^([^\t]*)\t(.*)$')
                if left then
                    r.ImGui_Text(ctx, left)
                    r.ImGui_SameLine(ctx, 190)
                    r.ImGui_Text(ctx, right)
                else
                    r.ImGui_Text(ctx, line)
                end
            else
                r.ImGui_Spacing(ctx)
            end
        end
        r.ImGui_PopTextWrapPos(ctx)
    end
end
