-- Script Links coverage (lib/reaper_script_links.lua).
-- Backs the "General > Other tools" sub-tab, whose two failure modes are both
-- silent: a registry entry naming a file that no longer exists ships a button
-- that can never work, and a new entry point nobody adds to the registry is
-- simply invisible. Sections 3a and 3b guard each direction against the real
-- repo, so a rename or an addition fails a test instead of shipping.
--
-- The self-hide filter is the other thing worth pinning down: it is what keeps
-- the General Helper from offering to open the General Helper, and a
-- substring-based version of it would misfire on neighbouring filenames.
--
-- Every test here is pure - no project fixture, no tracks, nothing to clean up.
-- The set also proves the module's load-time purity implicitly: the runner sets
-- ctx = nil before dofile'ing it, so any ImGui or get_action_context call at
-- load time would blow up before the first test runs.
--
-- Requires globals: Test, LINKS_ROOT (the install root), and the module's own
-- SCRIPT_LINK_GROUPS / ScriptLinkBasename / IsRunningScriptLink /
-- FilterScriptLinkGroups - all set up by run_script_links.lua.

local function AllEntries(groups)
    local out = {}
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.entries) do out[#out + 1] = e end
    end
    return out
end

local function Join(list)
    table.sort(list)
    return table.concat(list, ', ')
end

------------------------------------------------------------------
Test.section('Script Links: basename parsing')

Test.it('splits a Windows path', function()
    Test.expect(ScriptLinkBasename('C:\\a\\b\\x.lua') == 'x.lua', 'got ' ..
        tostring(ScriptLinkBasename('C:\\a\\b\\x.lua')))
end)

Test.it('splits a POSIX path', function()
    Test.expect(ScriptLinkBasename('/a/b/x.lua') == 'x.lua')
end)

Test.it('passes a bare filename through', function()
    Test.expect(ScriptLinkBasename('x.lua') == 'x.lua')
end)

Test.it('handles mixed separators', function()
    Test.expect(ScriptLinkBasename('C:/a\\b/c\\x.lua') == 'x.lua')
end)

Test.it('returns nil for nil, empty and a bare separator', function()
    Test.expect(ScriptLinkBasename(nil) == nil, 'nil')
    Test.expect(ScriptLinkBasename('') == nil, 'empty string')
    Test.expect(ScriptLinkBasename('C:\\a\\b\\') == nil, 'trailing separator')
end)

------------------------------------------------------------------
Test.section('Script Links: registry shape')

Test.it('has the two expected groups, 3 + 2 entries', function()
    Test.expect(#SCRIPT_LINK_GROUPS == 2, 'expected 2 groups, got ' .. #SCRIPT_LINK_GROUPS)
    Test.expect(#SCRIPT_LINK_GROUPS[1].entries == 3,
        'group 1 has ' .. #SCRIPT_LINK_GROUPS[1].entries .. ' entries')
    Test.expect(#SCRIPT_LINK_GROUPS[2].entries == 2,
        'group 2 has ' .. #SCRIPT_LINK_GROUPS[2].entries .. ' entries')
end)

Test.it('every group has a non-empty title', function()
    for i, g in ipairs(SCRIPT_LINK_GROUPS) do
        Test.expect(type(g.title) == 'string' and g.title ~= '', 'group ' .. i)
    end
end)

Test.it('every entry has a file, label, short and desc', function()
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        local what = tostring(e.file)
        Test.expect(type(e.file) == 'string' and e.file ~= '', 'file: ' .. what)
        Test.expect(type(e.label) == 'string' and e.label ~= '', 'label: ' .. what)
        Test.expect(type(e.short) == 'string' and e.short ~= '', 'short: ' .. what)
        Test.expect(type(e.desc) == 'string' and e.desc ~= '', 'desc: ' .. what)
    end
end)

-- `short` shares the button's line, so it has to fit beside the widest button
-- at the default window width. One line, and short enough not to clip.
Test.it('every short is a single line and stays brief', function()
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        Test.expect(not e.short:find('\n'), e.file .. ': short must be one line')
        Test.expect(#e.short <= 40,
            e.file .. ': short is ' .. #e.short .. ' chars, over the 40 that fit')
    end
end)

-- This tab advertises the other tools, so it must not name a tab that is
-- hidden behind "Show WIPs?" - a user who follows the pointer finds nothing.
-- Only unambiguous phrases are listed: bare words like "drums" or "guitar"
-- appear legitimately in the Music Theory entry, so matching those would be a
-- false positive rather than a guard.
-- Matched case-insensitively: the string this guard was written for read
-- "Tempo map generation from drum stems", which a case-sensitive list of
-- "Tempo Map" / "tempo map" would have sailed straight past.
Test.it('no short or desc advertises a WIP-only feature', function()
    local forbidden = { 'tempo map', 'note placement', 'syllable' }
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        local short_l, desc_l = e.short:lower(), e.desc:lower()
        for _, phrase in ipairs(forbidden) do
            Test.expect(not short_l:find(phrase, 1, true),
                e.file .. ": short names the WIP-only '" .. phrase .. "'")
            Test.expect(not desc_l:find(phrase, 1, true),
                e.file .. ": desc names the WIP-only '" .. phrase .. "'")
        end
    end
end)

Test.it('every file is a rock_band_*_vkr.lua basename', function()
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        Test.expect(e.file:match('^rock_band_.+_vkr%.lua$') ~= nil, e.file)
        Test.expect(not e.file:find('[/\\]'), e.file .. ' must be a bare basename')
    end
end)

Test.it('no duplicate file or label', function()
    local seen_file, seen_label = {}, {}
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        Test.expect(not seen_file[e.file], 'duplicate file: ' .. e.file)
        Test.expect(not seen_label[e.label], 'duplicate label: ' .. e.label)
        seen_file[e.file], seen_label[e.label] = true, true
    end
end)

------------------------------------------------------------------
Test.section('Script Links: registry matches the repo')

-- Guards a rename: an entry point renamed without updating the registry would
-- otherwise ship a button that is permanently greyed out.
Test.it('every registry file exists at the install root', function()
    local missing = {}
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        if not r.file_exists(LINKS_ROOT .. e.file) then missing[#missing + 1] = e.file end
    end
    Test.expect(#missing == 0, 'not found in ' .. LINKS_ROOT .. ': ' .. Join(missing))
end)

-- The reverse guard: a sixth entry point added at the root fails this until it
-- is listed, so a new tool cannot be invisible from the Other tools tab.
Test.it('every rock_band_*_vkr.lua at the root is in the registry', function()
    -- r.EnumerateFiles requires a path without trailing separator
    local dir_no_slash = LINKS_ROOT:gsub('[/\\]$', '')
    local listed = {}
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do listed[e.file] = true end

    local unlisted, i = {}, 0
    while true do
        local filename = r.EnumerateFiles(dir_no_slash, i)
        if not filename then break end
        i = i + 1
        if filename:match('^rock_band_.+_vkr%.lua$') and not listed[filename] then
            unlisted[#unlisted + 1] = filename
        end
    end
    Test.expect(#unlisted == 0,
        'entry point(s) at the root missing from SCRIPT_LINK_GROUPS: ' .. Join(unlisted))
end)

------------------------------------------------------------------
Test.section('Script Links: self-hide filter')

Test.it('running script is dropped, the other four remain', function()
    for _, e in ipairs(AllEntries(SCRIPT_LINK_GROUPS)) do
        local kept = AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, 'C:\\x\\' .. e.file))
        Test.expect(#kept == 4, e.file .. ': expected 4 entries, got ' .. #kept)
        for _, k in ipairs(kept) do
            Test.expect(k.file ~= e.file, e.file .. ' was not dropped')
        end
    end
end)

Test.it('matches case-insensitively (Windows paths)', function()
    local path = 'C:\\X\\ROCK_BAND_GENERAL_HELPER_VKR.LUA'
    local kept = AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, path))
    Test.expect(#kept == 4, 'expected 4, got ' .. #kept)
end)

Test.it('matches a bare basename with no directory', function()
    local kept = AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS,
        'rock_band_pitch_tuner_vkr.lua'))
    Test.expect(#kept == 4, 'expected 4, got ' .. #kept)
end)

-- Whole-basename equality, not a substring search: these three all contain a
-- registry name or are contained by one, and none of them may hide anything.
Test.it('a neighbouring filename hides nothing', function()
    local cases = {
        'C:\\x\\dev\\test_rock_band_helpers_vkr.lua',
        'C:\\x\\rock_band_general_helper_vkr.lua.bak',
        'C:\\x\\my_rock_band_vocal_helper_vkr.lua',
    }
    for _, path in ipairs(cases) do
        local kept = AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, path))
        Test.expect(#kept == 5, path .. ': expected 5, got ' .. #kept)
    end
end)

Test.it('nil and empty paths hide nothing', function()
    Test.expect(#AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, nil)) == 5, 'nil')
    Test.expect(#AllEntries(FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, '')) == 5, 'empty')
end)

Test.it('leaves the source registry untouched', function()
    FilterScriptLinkGroups(SCRIPT_LINK_GROUPS, 'C:\\x\\rock_band_pitch_tuner_vkr.lua')
    Test.expect(#SCRIPT_LINK_GROUPS == 2, 'group count changed')
    Test.expect(#AllEntries(SCRIPT_LINK_GROUPS) == 5, 'entry count changed')
end)

------------------------------------------------------------------
Test.section('Script Links: empty group collapse')

-- Synthetic: the real registry can never empty a group (no group is a single
-- entry), but the draw loop would put a bare SectionHeader over nothing if the
-- filter ever left one behind.
Test.it('a group emptied by the filter is dropped, not left headerless', function()
    local groups = {
        { title = 'A', entries = { { file = 'a.lua', label = 'A', desc = 'a' } } },
        { title = 'B', entries = { { file = 'b.lua', label = 'B', desc = 'b' } } },
    }
    local out = FilterScriptLinkGroups(groups, 'C:\\x\\b.lua')
    Test.expect(#out == 1, 'expected 1 group, got ' .. #out)
    Test.expect(out[1].title == 'A', 'wrong group survived: ' .. tostring(out[1].title))
end)

Test.it('filtering out everything yields no groups at all', function()
    local groups = { { title = 'A', entries = { { file = 'a.lua', label = 'A', desc = 'a' } } } }
    Test.expect(#FilterScriptLinkGroups(groups, 'a.lua') == 0, 'expected 0 groups')
end)
