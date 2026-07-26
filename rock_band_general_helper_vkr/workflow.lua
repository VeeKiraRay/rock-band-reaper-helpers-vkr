-- Workflow checklist template parser.
-- Requires: r (global)
--
-- Templates live in resources/workflow/*.txt (repo root, sibling to lib/) and
-- use a small line-based markup:
--   [Section Name]        - non-checkable section header
--   Item text              - checkable item
--   Item text {tooltip}    - same-line tooltip, stripped from the label
--   {tooltip}              - on its own line, attaches to the previous item
-- An item that ends up with more than one tooltip source (same-line + a
-- following own-line block, or two same-line groups) drops its tooltip
-- entirely rather than guessing which source wins.

WORKFLOW_MAX_ITEMS = 100

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

-- Returns an array of { s = start_byte, e = end_byte } for every balanced
-- {...} group found in `line`, left to right, non-overlapping.
local function FindBraceGroups(line)
    local groups = {}
    local init = 1
    while true do
        local s, e = line:find('%b{}', init)
        if not s then break end
        groups[#groups + 1] = { s = s, e = e }
        init = e + 1
    end
    return groups
end

-- Removes every {...} group from `line` and returns (label, tip, group_count).
-- `tip` is only meaningful when group_count == 1 (the unambiguous case) - the
-- caller decides what to do with 2+ groups (per the markup's "ignored" rule).
local function StripBraceGroups(line)
    local groups = FindBraceGroups(line)
    if #groups == 0 then
        return line, nil, 0
    end

    local parts = {}
    local pos = 1
    for _, g in ipairs(groups) do
        parts[#parts + 1] = line:sub(pos, g.s - 1)
        pos = g.e + 1
    end
    parts[#parts + 1] = line:sub(pos)
    local label = table.concat(parts):match('^%s*(.-)%s*$')

    if #groups == 1 then
        local g = groups[1]
        return label, line:sub(g.s + 1, g.e - 1), 1
    end
    return label, nil, #groups
end

-- Parses already-read workflow template text into an ordered array of
-- entries plus a list of human-readable validation warnings. Pure function
-- over a string (no REAPER/file-system dependency) so tests can drive it
-- with inline fixtures.
--
-- entries: { kind = 'header', label = ... }
--        | { kind = 'item', section = ..., label = ..., tooltip = ... or nil }
function ParseWorkflowContent(content)
    local entries = {}
    local errors  = {}
    local section   = ''
    local seen      = {}   -- "section\30label" -> true, for duplicate detection
    local last_item = nil  -- most recent item entry, for own-line {tooltip} attach

    for raw_line in (content .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        local line = raw_line:match('^%s*(.-)%s*$')
        if line ~= '' then
            local header = line:match('^%[(.+)%]$')
            if header then
                section = header
                entries[#entries + 1] = { kind = 'header', label = header }
                last_item = nil
            else
                local label, tip, group_count = StripBraceGroups(line)
                if label == '' then
                    -- A line that was entirely {...} group(s): attaches to
                    -- the previous item only (nothing to attach to otherwise).
                    if last_item then
                        last_item._tip_sources = last_item._tip_sources + group_count
                        last_item.tooltip = (last_item._tip_sources == 1) and tip or nil
                    end
                else
                    local key = section .. '\30' .. label
                    if seen[key] then
                        errors[#errors + 1] = ('Duplicate item under [%s]: "%s" (appears more than once)')
                            :format(section ~= '' and section or '(no section)', label)
                    end
                    seen[key] = true
                    local entry = {
                        kind    = 'item',
                        section = section,
                        label   = label,
                        tooltip = (group_count == 1) and tip or nil,
                        _tip_sources = group_count,
                    }
                    entries[#entries + 1] = entry
                    last_item = entry
                end
            end
        end
    end

    for _, e in ipairs(entries) do e._tip_sources = nil end

    -- Bracket-balance sanity check across the whole file: a mismatch usually
    -- means a stray or missing bracket broke the markup somewhere.
    local open_sq, close_sq, open_cu, close_cu = 0, 0, 0, 0
    for c in content:gmatch('.') do
        if     c == '[' then open_sq  = open_sq  + 1
        elseif c == ']' then close_sq = close_sq + 1
        elseif c == '{' then open_cu  = open_cu  + 1
        elseif c == '}' then close_cu = close_cu + 1
        end
    end
    if open_sq ~= close_sq then
        errors[#errors + 1] = ("Uneven [ ] brackets: %d '[' vs %d ']' - check the file for a missing bracket.")
            :format(open_sq, close_sq)
    end
    if open_cu ~= close_cu then
        errors[#errors + 1] = ("Uneven { } brackets: %d '{' vs %d '}' - check the file for a missing bracket.")
            :format(open_cu, close_cu)
    end

    return entries, errors
end

function ParseWorkflowFile(path)
    local f = io.open(path, 'r')
    if not f then return {}, { 'Could not open file: ' .. path } end
    local content = f:read('*all')
    f:close()
    return ParseWorkflowContent(content)
end

function LoadWorkflowFiles(dir)
    -- r.EnumerateFiles requires a path without trailing separator
    local dir_no_slash = dir:gsub('[/\\]$', '')
    local files = {}
    local i     = 0
    while true do
        local filename = r.EnumerateFiles(dir_no_slash, i)
        if not filename then break end
        i = i + 1
        local stem = filename:match('^(.+)%.txt$')
        if stem then
            local path = dir_no_slash .. '/' .. filename
            local entries, errors = ParseWorkflowFile(path)
            files[#files + 1] = { stem = stem, label = stem, entries = entries, errors = errors }
        end
    end
    table.sort(files, function(a, b) return a.label < b.label end)
    return files
end

-- ---------------------------------------------------------------------------
-- Escaping for the delimited on-disk state format (see actions_workflow.lua)
-- ---------------------------------------------------------------------------

-- Workflow section/label text is free-form user content (unlike e.g.
-- venue_sec_configs' auto-generated keys) and could itself contain the
-- delimiter characters used by the workflow_v1 record format - percent-escape
-- them so any label round-trips safely.
function EscapeWF(s)
    s = s:gsub('%%', '%%25')
    s = s:gsub(';', '%%3B')
    s = s:gsub('|', '%%7C')
    s = s:gsub('=', '%%3D')
    return s
end

function UnescapeWF(s)
    s = s:gsub('%%3D', '=')
    s = s:gsub('%%7C', '|')
    s = s:gsub('%%3B', ';')
    s = s:gsub('%%25', '%%')
    return s
end
