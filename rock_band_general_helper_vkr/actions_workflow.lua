-- Workflow checklist state: persistence, toggling, and template-switch pruning.
-- Requires: workflow.lua (LoadWorkflowFiles, EscapeWF, UnescapeWF), r, S (globals)

local PROJ_WORKFLOW_KEY = 'workflow_v1'

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------

-- Composite key so identical item text under different [section] headers
-- (e.g. "Guitar" under both "Instruments Expert" and "Difficulty reductions")
-- is tracked independently instead of sharing one checked state.
function CompositeKey(section, label)
    return (section or '') .. '\30' .. label
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- Drops any S.workflow_state entry whose (section,label) key isn't a
-- checkable item in `entries` (one template file's parsed entries, not all
-- loaded templates) - keeps persisted state scoped to whichever template is
-- currently selected instead of accumulating history across every template
-- ever picked.
function PruneToWorkflowEntries(entries)
    local live = {}
    for _, e in ipairs(entries) do
        if e.kind == 'item' then
            live[CompositeKey(e.section, e.label)] = true
        end
    end
    for key in pairs(S.workflow_state) do
        if not live[key] then S.workflow_state[key] = nil end
    end
end

function SaveWorkflowState()
    local parts = {}
    for _, entry in pairs(S.workflow_state) do
        parts[#parts + 1] = EscapeWF(entry.section) .. '|' .. EscapeWF(entry.label) .. '|' ..
            (entry.checked and '1' or '0') .. '|' .. (entry.ts or '')
    end
    r.SetProjExtState(0, 'RBHelperVKR', PROJ_WORKFLOW_KEY, table.concat(parts, ';'))
end

function LoadWorkflowState()
    S.workflow_state = {}
    local _, str = r.GetProjExtState(0, 'RBHelperVKR', PROJ_WORKFLOW_KEY)
    if not str or str == '' then return end
    for record in str:gmatch('[^;]+') do
        local section_e, label_e, checked_s, ts_s = record:match('^(.-)|(.-)|([01])|(%d*)$')
        if section_e then
            local section, label = UnescapeWF(section_e), UnescapeWF(label_e)
            S.workflow_state[CompositeKey(section, label)] = {
                section = section,
                label   = label,
                checked = checked_s == '1',
                ts      = (ts_s ~= '' and tonumber(ts_s)) or nil,
            }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Template selection
-- ---------------------------------------------------------------------------

-- The one place a workflow template selection actually changes (combo pick,
-- or the startup fallback to Default/first-alphabetical). Prunes checked
-- state down to the newly-selected file's own items and saves immediately,
-- so switching templates never leaves a stale mix of two templates' history
-- sitting in the project.
function SelectWorkflowFile(idx)
    local wf = S.workflow_files[idx]
    S.workflow_file_idx  = idx
    S.workflow_file_name = wf.stem
    PruneToWorkflowEntries(wf.entries)
    SaveWorkflowState()
end

-- ---------------------------------------------------------------------------
-- Toggling
-- ---------------------------------------------------------------------------

-- Checking/unchecking a workflow item autosaves immediately (its own project
-- ExtState key, independent of the General tab's explicit Save/Load buttons)
-- so progress from a session is never lost if the user forgets to hit Save.
function ToggleWorkflowItem(section, label, new_checked)
    S.workflow_state[CompositeKey(section, label)] = {
        section = section,
        label   = label,
        checked = new_checked,
        ts      = new_checked and os.time() or nil,
    }
    SaveWorkflowState()
end

-- ---------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------

-- Pure function over one template's entries + the checked-state table (no
-- REAPER/UI dependency) so it can be unit tested directly. Returns
-- (done, total) counting only checkable items - headers aren't counted.
function ComputeWorkflowStats(entries, state)
    local total, done = 0, 0
    for _, e in ipairs(entries) do
        if e.kind == 'item' then
            total = total + 1
            local st = state[CompositeKey(e.section, e.label)]
            if st and st.checked then done = done + 1 end
        end
    end
    return done, total
end
