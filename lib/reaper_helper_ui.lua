-- UI pieces shared by every helper (General, Instrument, Vocal) and the
-- standalone windows that draw their modules (MIDI Pattern, Pitch Tuner).
-- Anything more than one entry point draws lives here rather than in a ui.lua,
-- which cannot be dofile'd by another entry point: its last line is a bare
-- r.defer(Loop) that would spawn that helper's whole window.
--
-- Requires globals: r, ctx, S, Btn, BtnWidth, Tooltip, BTN_H, FormatTime,
--                   GetTimeSelection (lib/reaper_imgui_helpers.lua - load first).

-- Track dropdown: stores and matches by REAPER track index (t.idx, from
-- RefreshTrackLists), so a selection survives the filtered lists being rebuilt.
-- reaper_idx = -1 is "(none)": an optional input left unset, or a required one
-- not picked yet (the action then asks for a track - see TrackAtIndex). A
-- selection missing from this filtered list still previews by name from
-- S.all_track_list.
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

------------------------------------------------------------------
-- Result panel + window footer
--
-- Layout every window uses (see CLAUDE.md, "Window footer"):
--
--   if BeginScrollBody('##body', -HelperFooterHeight(opts)) then
--       ... tabs / view ...
--       DrawResultPanel()
--   end
--   r.ImGui_EndChild(ctx)
--   DrawHelperFooter(opts)
--
-- The view scrolls inside the child; the footer is drawn after it and never
-- moves. opts switch each footer part on or off - a part that is off is not
-- drawn and takes no height, so HelperFooterHeight and DrawHelperFooter must be
-- given the same opts:
--   status  - time selection + status line          (reads S.status)
--   copy    - Copy result button                    (reads S.status / S.last_result)
--   undo    - right-aligned Undo button
-- Each part defaults to on; a window passes false for what it does not need.
-- Tooltip strings live here, not in a script's TIPS (CLAUDE.md, Tooltips).
------------------------------------------------------------------

local TIP_COPY    = 'Copy the status line and the result panel to the clipboard.'

-- Pure (no r / ctx / S): the text Copy result puts on the clipboard, or nil
-- when there is nothing beyond the status line worth copying.
function HelperCopyText(status, result)
    if not result or result == '' then return nil end
    if status and status ~= '' then return status .. '\n\n' .. result end
    return result
end

local function On(opts, name)
    return opts == nil or opts[name] ~= false
end

local function HasButtonRow(opts)
    return On(opts, 'copy') or On(opts, 'undo')
end

-- Height to reserve below the scroll body for DrawHelperFooter(opts).
function HelperFooterHeight(opts)
    local item_sp_y = select(2, r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()))
    local h = item_sp_y                                       -- the separator
    if On(opts, 'status') then
        h = h + 2 * r.ImGui_GetTextLineHeightWithSpacing(ctx)
    end
    if HasButtonRow(opts) then
        -- Buttons are BTN_H tall, which can exceed the style's frame height.
        local frame_h = r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx) or BTN_H
        h = h + math.max(BTN_H, frame_h) + item_sp_y
    end
    return h
end

-- The result of the last action (S.last_result), wrapped. A line containing a
-- tab is drawn as two columns (SameLine at 190); several reports use that.
-- Drawn at the end of the scroll body, under the view.
function DrawResultPanel()
    if not S.last_result then return end
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

-- The always-visible footer. See the block comment above for opts.
function DrawHelperFooter(opts)
    r.ImGui_Separator(ctx)

    if On(opts, 'status') then
        local sel_s, sel_e = GetTimeSelection()
        if sel_s then
            r.ImGui_Text(ctx, ('Time selection: %s - %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
        else
            r.ImGui_TextDisabled(ctx, 'No time selection')
        end
        r.ImGui_Text(ctx, S.status or '')
    end

    if not HasButtonRow(opts) then return end
    local first = true
    local function Next()
        if not first then r.ImGui_SameLine(ctx) end
        first = false
    end

    if On(opts, 'copy') then
        Next()
        local text = HelperCopyText(S.status, S.last_result)   -- snapshot: drives the disabled pair
        if not text then r.ImGui_BeginDisabled(ctx) end
        if Btn('Copy result', BTN_H) then
            r.ImGui_SetClipboardText(ctx, text)
            S.status = 'Result copied to the clipboard.'
        end
        if not text then r.ImGui_EndDisabled(ctx) end
        Tooltip(TIP_COPY)
    end

    if On(opts, 'undo') then
        Next()
        local bw_und   = BtnWidth('Undo')
        local undo_str = r.Undo_CanUndo2(0) or ''
        local can_undo = undo_str ~= ''   -- snapshot: drives the disabled pair
        local avail_x  = r.ImGui_GetContentRegionAvail(ctx)
        if avail_x > bw_und + 4 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - bw_und))
        end
        if not can_undo then r.ImGui_BeginDisabled(ctx) end
        if Btn('Undo', BTN_H) then r.Undo_DoUndo2(0) end
        if not can_undo then r.ImGui_EndDisabled(ctx) end
        if can_undo then Tooltip('Undo: ' .. undo_str) end
    end
end

