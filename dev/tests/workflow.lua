-- Tests for workflow.lua (ParseWorkflowContent markup parsing, EscapeWF/UnescapeWF)
-- and actions_workflow.lua (SaveWorkflowState/LoadWorkflowState round-trip, the
-- WORKFLOW_MAX_ITEMS purge trigger).

----------------------------------------------------------------------
Test.section('ParseWorkflowContent - headers, items, tooltips')
----------------------------------------------------------------------

local function ItemsOnly(entries)
    local out = {}
    for _, e in ipairs(entries) do
        if e.kind == 'item' then out[#out + 1] = e end
    end
    return out
end

Test.it('parses headers and plain items with no tooltip', function()
    local entries, errors = ParseWorkflowContent([[
[Getting started]
Get initial BPM
Check time signature
]])
    Test.expect(#errors == 0, 'no warnings for a well-formed file')
    Test.expect(#entries == 3, 'header + 2 items')
    Test.expect(entries[1].kind == 'header' and entries[1].label == 'Getting started', 'header parsed')
    Test.expect(entries[2].kind == 'item' and entries[2].label == 'Get initial BPM', 'item 1 parsed')
    Test.expect(entries[2].section == 'Getting started', 'item 1 section tracked')
    Test.expect(entries[2].tooltip == nil, 'item 1 has no tooltip')
    Test.expect(entries[3].label == 'Check time signature', 'item 2 parsed')
end)

Test.it('same-line trailing {tooltip} is stripped from the label', function()
    local entries = ParseWorkflowContent([[
[Section]
Align stems {watch for sample rate mismatches}
]])
    local items = ItemsOnly(entries)
    Test.expect(items[1].label == 'Align stems', 'label has brace group stripped')
    Test.expect(items[1].tooltip == 'watch for sample rate mismatches', 'tooltip captured')
end)

Test.it('own-line {tooltip} attaches to the previous item', function()
    local entries = ParseWorkflowContent([[
[Section]
Align stems
{watch for sample rate mismatches}
]])
    local items = ItemsOnly(entries)
    Test.expect(items[1].tooltip == 'watch for sample rate mismatches', 'own-line tooltip attached')
end)

Test.it('a same-line tooltip plus a following own-line tooltip is dropped (ambiguous)', function()
    local entries = ParseWorkflowContent([[
[Section]
Align stems {first tip}
{second tip}
]])
    local items = ItemsOnly(entries)
    Test.expect(items[1].label == 'Align stems', 'label still stripped of its own brace group')
    Test.expect(items[1].tooltip == nil, 'tooltip dropped once a second source appears')
end)

Test.it('two same-line brace groups on one item drop the tooltip', function()
    local entries = ParseWorkflowContent([[
[Section]
Align stems {tip one} {tip two}
]])
    local items = ItemsOnly(entries)
    Test.expect(items[1].label == 'Align stems', 'both brace groups removed from label')
    Test.expect(items[1].tooltip == nil, 'ambiguous multi-brace tooltip dropped')
end)

Test.it('an own-line tooltip with nothing preceding it is silently ignored', function()
    local entries, errors = ParseWorkflowContent([[
{orphan tooltip}
[Section]
Item one
]])
    Test.expect(#errors == 0, 'orphan tooltip is not an error')
    local items = ItemsOnly(entries)
    Test.expect(items[1].tooltip == nil, 'orphan tooltip attaches to nothing')
end)

----------------------------------------------------------------------
Test.section('ParseWorkflowContent - duplicate + bracket-balance warnings')
----------------------------------------------------------------------

Test.it('flags a duplicate (section,label) pair within one file', function()
    local _, errors = ParseWorkflowContent([[
[Instruments Expert]
Guitar
Bass
Guitar
]])
    Test.expect(#errors == 1, 'exactly one duplicate warning')
    Test.expect(errors[1]:find('Instruments Expert') ~= nil, 'warning names the section')
    Test.expect(errors[1]:find('Guitar') ~= nil, 'warning names the label')
end)

Test.it('does not flag identical labels under different sections', function()
    local _, errors = ParseWorkflowContent([[
[Instruments Expert]
Guitar
[Difficulty reductions]
Guitar
]])
    Test.expect(#errors == 0, 'same label under different sections is not a duplicate')
end)

Test.it('flags uneven [ ] bracket counts', function()
    local _, errors = ParseWorkflowContent([[
[Unclosed section
Item one
]])
    local found = false
    for _, msg in ipairs(errors) do
        if msg:find('%[ %]') then found = true end
    end
    Test.expect(found, 'reports the [ ] mismatch')
end)

Test.it('flags uneven { } bracket counts', function()
    local _, errors = ParseWorkflowContent([[
[Section]
Item one {unterminated tooltip
]])
    local found = false
    for _, msg in ipairs(errors) do
        if msg:find('%{ %}') then found = true end
    end
    Test.expect(found, 'reports the { } mismatch')
end)

Test.it('a well-formed file reports no bracket warnings', function()
    local _, errors = ParseWorkflowContent([[
[Section]
Item one {tip}
Item two
]])
    Test.expect(#errors == 0, 'balanced brackets, no duplicates -> no warnings')
end)

----------------------------------------------------------------------
Test.section('EscapeWF / UnescapeWF round-trip')
----------------------------------------------------------------------

Test.it('round-trips text containing every delimiter character', function()
    local raw = 'a;b|c=d%e'
    Test.expect(UnescapeWF(EscapeWF(raw)) == raw, 'escape then unescape returns the original text')
end)

Test.it('escaped text contains none of the raw delimiter characters', function()
    local escaped = EscapeWF('a;b|c=d')
    Test.expect(not escaped:find(';', 1, true), 'no literal ; survives escaping')
    Test.expect(not escaped:find('|', 1, true), 'no literal | survives escaping')
    Test.expect(not escaped:find('=', 1, true), 'no literal = survives escaping')
end)

----------------------------------------------------------------------
-- Persistence: these read/write the real project's "RBHelperVKR"/"workflow_v1"
-- ExtState key. Snapshot the original value and S state, restore both after -
-- running this suite must never lose real checklist progress.
----------------------------------------------------------------------
Test.section('SaveWorkflowState / LoadWorkflowState (project ExtState round-trip)')

do
    local _, _orig_ext   = r.GetProjExtState(0, 'RBHelperVKR', 'workflow_v1')
    local _orig_S_state  = S.workflow_state
    local _orig_S_files  = S.workflow_files

    local function CountKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    Test.it('round-trips checked state and timestamp', function()
        S.workflow_state = {}
        S.workflow_files = nil  -- no purge trigger for this test
        ToggleWorkflowItem('Getting started', 'Check time signature', true)
        local key = CompositeKey('Getting started', 'Check time signature')
        local ts  = S.workflow_state[key].ts
        Test.expect(ts ~= nil, 'timestamp set on check')

        LoadWorkflowState()
        local loaded = S.workflow_state[key]
        Test.expect(loaded ~= nil, 'entry present after reload')
        Test.expect(loaded.checked == true, 'checked survives reload')
        Test.expect(loaded.ts == ts, 'timestamp survives reload')
    end)

    Test.it('unchecking clears the timestamp', function()
        S.workflow_state = {}
        S.workflow_files = nil
        ToggleWorkflowItem('Sec', 'Item', true)
        ToggleWorkflowItem('Sec', 'Item', false)
        LoadWorkflowState()
        local loaded = S.workflow_state[CompositeKey('Sec', 'Item')]
        Test.expect(loaded.checked == false, 'unchecked survives reload')
        Test.expect(loaded.ts == nil, 'timestamp cleared on uncheck')
    end)

    Test.it('purges stale entries once past WORKFLOW_MAX_ITEMS', function()
        S.workflow_state = {}
        S.workflow_files = {
            { stem = 'fixture', label = 'fixture', errors = {}, entries = {
                { kind = 'item', section = 'Sec', label = 'Live Item' },
            } },
        }
        ToggleWorkflowItem('Sec', 'Live Item', true)
        for i = 1, WORKFLOW_MAX_ITEMS do
            local k = CompositeKey('Stale', 'Item ' .. i)
            S.workflow_state[k] = { section = 'Stale', label = 'Item ' .. i, checked = true, ts = os.time() }
        end
        Test.expect(CountKeys(S.workflow_state) > WORKFLOW_MAX_ITEMS, 'seeded past the cap')

        SaveWorkflowState()  -- should purge stale entries before writing

        Test.expect(S.workflow_state[CompositeKey('Sec', 'Live Item')] ~= nil, 'live entry kept in memory')
        Test.expect(S.workflow_state[CompositeKey('Stale', 'Item 1')] == nil, 'stale entry purged in memory')

        LoadWorkflowState()
        Test.expect(S.workflow_state[CompositeKey('Sec', 'Live Item')] ~= nil, 'live entry survives reload')
        Test.expect(S.workflow_state[CompositeKey('Stale', 'Item 1')] == nil, 'stale entry stays purged after reload')
    end)

    -- Always restore the real project's original workflow_v1 value and S
    -- state, regardless of pass/fail above.
    r.SetProjExtState(0, 'RBHelperVKR', 'workflow_v1', _orig_ext or '')
    S.workflow_state = _orig_S_state
    S.workflow_files = _orig_S_files
end
