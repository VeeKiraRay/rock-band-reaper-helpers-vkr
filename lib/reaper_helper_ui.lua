-- UI pieces shared by every helper (General, Instrument, Vocal) and the
-- standalone windows that draw their modules (MIDI Pattern, Pitch Tuner).
-- Anything more than one entry point draws lives here rather than in a ui.lua,
-- which cannot be dofile'd by another entry point: its last line is a bare
-- r.defer(Loop) that would spawn that helper's whole window.
--
-- Requires globals: r, ctx, S, Btn, BtnWidth, Tooltip, BTN_H, FormatTime,
--                   GetTimeSelection, TextDim, COL_* (lib/reaper_imgui_helpers.lua -
--                   load first).

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
        r.ImGui_TextColored(ctx, COL_WARN, '! Source track not open in the MIDI editor.')
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
--   copy    - Copy result button                    (reads S.status / S.last_result,
--                                                     and the view's SetCopyView text)
--   undo    - right-aligned Undo button
-- Each part defaults to on; a window passes false for what it does not need.
-- Tooltip strings live here, not in a script's TIPS (CLAUDE.md, Tooltips).
------------------------------------------------------------------

local TIP_COPY    = 'Copy the results to the clipboard: the ones shown in this view, or the ' ..
                    'status line and the result panel.'

-- A view that draws its own results (cards, rulers, dots) instead of the result
-- panel calls SetCopyView(fn) while it draws them; fn returns those results as
-- plain text. Copy result then includes it. Registered every frame by whichever
-- view is on screen and dropped after the footer, so the copy always follows
-- what is visible - a sub-tab switched away from stops being copied at once.
-- fn runs only when the button is pressed, never per frame.
local _copy_view = nil

function SetCopyView(fn)
    _copy_view = fn
end

-- Result line colour tags. A line in S.last_result may start with one of these,
-- e.g. '{gold}Guitar OD boost\t+52,476 ... reached': the panel draws the line in
-- that shared colour (for a two-column line, only the value after the tab) and
-- does not show the tag; Copy result leaves it out. Names, not colours, so this
-- table needs nothing loaded; the colours are read at draw time.
local RESULT_TAGS = { gold = 'COL_GOLD', error = 'COL_ERROR', warn = 'COL_WARN',
                      dim = 'COL_DIM', ok = 'COL_OK', info = 'COL_INFO' }

-- Pure: a result line -> its tag name (or nil) and the line without the tag.
-- An unknown {word} is left in the text, so a line that happens to start with
-- braces is never eaten.
function ResultLineTag(line)
    local tag, rest = line:match('^{(%a+)}(.*)$')
    if tag and RESULT_TAGS[tag] then return tag, rest end
    return nil, line
end

-- What the footer puts on the status line after a copy. Never copied itself: a second
-- press would otherwise start the clipboard text with it.
local COPIED_STATUS = 'Result copied to the clipboard.'

-- Pure (no r / ctx / S): the text Copy result puts on the clipboard, in screen order,
-- or nil when there is nothing beyond the status line worth copying. Colour tags are
-- dropped.
--   status - the status line. Left out when a view gives its own results (view): those
--            are self-describing, and the status there only says the action ran - or,
--            after a copy, that it was copied. Left out too when it is the footer's own
--            "copied" message.
--   view   - the view's own results (SetCopyView), before the result panel.
--   result - the result panel (S.last_result).
function HelperCopyText(status, result, view)
    local parts = {}
    local has_view = view and view ~= ''
    if status and status ~= '' and status ~= COPIED_STATUS and not has_view then
        parts[#parts + 1] = status
    end
    local body = false
    if has_view then parts[#parts + 1] = view; body = true end
    if result and result ~= '' then
        local lines = {}
        for line in (result .. '\n'):gmatch('([^\n]*)\n') do
            local _, text = ResultLineTag(line)
            lines[#lines + 1] = text
        end
        parts[#parts + 1] = table.concat(lines, '\n')
        body = true
    end
    if not body then return nil end
    return table.concat(parts, '\n\n')
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
            local tag
            tag, line = ResultLineTag(line)
            local col = tag and _G[RESULT_TAGS[tag]]
            local function Draw(text)
                if col then r.ImGui_TextColored(ctx, col, text) else r.ImGui_Text(ctx, text) end
            end
            local left, right = line:match('^([^\t]*)\t(.*)$')
            if left then
                r.ImGui_Text(ctx, left)
                r.ImGui_SameLine(ctx, 190)
                Draw(right)
            else
                Draw(line)
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
            TextDim('No time selection')
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
        -- Snapshot: drives the disabled pair. The view's text is built only on a press.
        local view_fn = _copy_view
        local has = view_fn ~= nil or HelperCopyText(S.status, S.last_result) ~= nil
        if not has then r.ImGui_BeginDisabled(ctx) end
        if Btn('Copy result', BTN_H) then
            local text = HelperCopyText(S.status, S.last_result, view_fn and view_fn())
            if text then
                r.ImGui_SetClipboardText(ctx, text)
                S.status = COPIED_STATUS
            end
        end
        if not has then r.ImGui_EndDisabled(ctx) end
        Tooltip(TIP_COPY)
    end
    _copy_view = nil   -- the next frame's view registers again

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

