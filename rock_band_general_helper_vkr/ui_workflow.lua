-- General > Workflow sub-tab rendering.
-- Requires: workflow.lua (LoadWorkflowFiles), actions_workflow.lua
--           (ToggleWorkflowItem, CompositeKey), lib/reaper_imgui_helpers.lua
--           (Tooltip, SectionHeader, WIDTH_STD), r, ctx, S, TIPS (globals)

local COL_WARNING = 0xFFAA00FF  -- warning amber, matches ui_midi.lua / ui_venue_players.lua

function DrawGeneralWorkflowTab()
    if S.workflow_files == nil then
        S.workflow_files = LoadWorkflowFiles(SCRIPT_DIR .. 'resources/workflow/')
        S.workflow_file_idx = 0
        for i, wf in ipairs(S.workflow_files) do
            if wf.stem == S.workflow_file_name then
                S.workflow_file_idx = i
                break
            end
        end
        -- No persisted selection matched (first run, or its file was removed):
        -- prefer a template named "Default", else fall back to the first one
        -- alphabetically (S.workflow_files is already sorted by label).
        if S.workflow_file_idx == 0 and #S.workflow_files > 0 then
            for i, wf in ipairs(S.workflow_files) do
                if wf.stem == 'Default' then
                    S.workflow_file_idx = i
                    break
                end
            end
            if S.workflow_file_idx == 0 then S.workflow_file_idx = 1 end
            S.workflow_file_name = S.workflow_files[S.workflow_file_idx].stem
        end
    end

    if #S.workflow_files == 0 then
        r.ImGui_TextDisabled(ctx, 'No workflow templates found - add .txt files to the resources/workflow/ folder')
        return
    end

    local _wf_preview = S.workflow_file_idx > 0
        and S.workflow_files[S.workflow_file_idx].label
        or '(select a workflow)'
    r.ImGui_Text(ctx, 'Workflow')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##workflow_file', _wf_preview) then
        for i, wf in ipairs(S.workflow_files) do
            local is_sel = (i == S.workflow_file_idx)
            if r.ImGui_Selectable(ctx, wf.label, is_sel) then
                S.workflow_file_idx  = i
                S.workflow_file_name = wf.stem
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.workflow_file)

    _, S.workflow_show_ts = r.ImGui_Checkbox(ctx, 'Show completion timestamp', S.workflow_show_ts)
    Tooltip(TIPS.workflow_show_ts)

    if S.workflow_file_idx == 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextDisabled(ctx, 'Select a workflow template above.')
        return
    end

    local wf = S.workflow_files[S.workflow_file_idx]

    if #wf.errors > 0 then
        r.ImGui_Spacing(ctx)
        for _, msg in ipairs(wf.errors) do
            r.ImGui_TextColored(ctx, COL_WARNING, '! ' .. msg)
        end
    end

    r.ImGui_Separator(ctx)

    local first_header = true
    for i, e in ipairs(wf.entries) do
        if e.kind == 'header' then
            if not first_header then
                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
            end
            first_header = false
            SectionHeader(e.label)
        else
            local key     = CompositeKey(e.section, e.label)
            local st      = S.workflow_state[key]
            local checked = st ~= nil and st.checked or false

            local changed, new_checked = r.ImGui_Checkbox(ctx, '##wf_item_' .. i, checked)
            if e.tooltip then Tooltip(e.tooltip) end
            r.ImGui_SameLine(ctx)
            r.ImGui_PushTextWrapPos(ctx, 0)
            r.ImGui_TextWrapped(ctx, e.label)
            r.ImGui_PopTextWrapPos(ctx)
            if r.ImGui_IsItemClicked(ctx) then
                changed, new_checked = true, not checked
            end
            if e.tooltip then Tooltip(e.tooltip) end

            if S.workflow_show_ts and checked and st and st.ts then
                r.ImGui_TextDisabled(ctx, '    Completed on ' .. os.date('%d.%m.%Y at %H:%M', st.ts))
            end

            if changed then
                ToggleWorkflowItem(e.section, e.label, new_checked)
            end
        end
    end
end
