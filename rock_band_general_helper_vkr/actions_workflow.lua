-- Workflow checklist state: persistence, toggling, and stale-entry purging.
-- Requires: workflow.lua (WORKFLOW_MAX_ITEMS, LoadWorkflowFiles, EscapeWF,
--                         UnescapeWF), r, S (globals)

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

local function CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- Drops any S.workflow_state entry whose (section,label) key doesn't appear
-- as a checkable item in any .txt file currently loaded in S.workflow_files.
-- Only runs when the files list has actually been loaded (i.e. the Workflow
-- tab has been opened this session) - otherwise there is no label universe
-- to compare against, so a save just past the cap this run leaves cleanup
-- for the next one.
function PurgeStaleWorkflowEntries()
    if not S.workflow_files then return end
    local live = {}
    for _, wf in ipairs(S.workflow_files) do
        for _, e in ipairs(wf.entries) do
            if e.kind == 'item' then
                live[CompositeKey(e.section, e.label)] = true
            end
        end
    end
    for key in pairs(S.workflow_state) do
        if not live[key] then S.workflow_state[key] = nil end
    end
end

function SaveWorkflowState()
    if CountTable(S.workflow_state) > WORKFLOW_MAX_ITEMS then
        PurgeStaleWorkflowEntries()
    end
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
