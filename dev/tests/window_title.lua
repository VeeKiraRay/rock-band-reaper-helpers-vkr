-- Window title coverage (ScriptWindowTitle in lib/reaper_imgui_helpers.lua).
--
-- The function reads the running script's own @version header and builds the
-- ImGui_Begin label from it. Both of its failure modes are silent, which is why
-- they are pinned here:
--
--   1. A header the parser stops matching (reformatted, or pushed past the
--      scanned window) makes the function fall back to the bare name. Nothing
--      errors - the window simply stops reporting its version, and every bug
--      report from then on carries no version either. Section 3 scans the real
--      entry points so a header edit fails a test instead of shipping.
--   2. Losing the "###" id, or changing it, silently resets every user's saved
--      window size, position and dock state. Section 2 pins the id to the bare
--      window name for all six shipped windows.
--
-- Every test here is pure: it reads files that are already in the repo, writes
-- nothing, and creates no tracks or items - nothing to clean up. The set also
-- proves ScriptWindowTitle needs no ImGui context, since the runner leaves
-- ctx = nil.
--
-- Requires globals: Test, TITLE_ROOT (the install root), and ScriptWindowTitle
-- - all set up by run_window_title.lua.

-- Every shipped window, as { window name, entry point }. The window name is the
-- literal each entry point passes to ScriptWindowTitle, and is also the "###" id
-- the saved window geometry is keyed by - so this table is what the id tests
-- compare against. Dev-only windows carry no @version header and are excluded
-- deliberately.
local WINDOWS = {
    { 'Rock Band General Helper', 'rock_band_general_helper_vkr.lua' },
    { 'Rock Band Vocal Helper',   'rock_band_vocal_helper_vkr.lua' },
    { 'RB Music Theory Helper',   'rock_band_music_theory_helper_vkr.lua' },
    { 'Rock Band Venue Preview',  'rock_band_preview_vkr.lua' },
    { 'Rock Band Pitch Tuner',    'rock_band_pitch_tuner_vkr.lua' },
    { 'Rock Band MIDI Pattern',   'rock_band_midi_pattern_vkr.lua' },
}

-- How far into a file ScriptWindowTitle looks for the header. Kept in step by
-- section 3's "within the scanned header window" test, which is what would fail
-- if the two ever drift apart.
local SCANNED_LINES = 12

local function HeaderVersionLine(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local n = 0
    for line in f:lines() do
        n = n + 1
        local ver = line:match('^%-%-%s*@version%s+(%S+)')
        if ver then f:close(); return ver, n end
    end
    f:close()
    return nil
end

------------------------------------------------------------------
Test.section('Window title: format')

Test.it('appends the version with a v prefix', function()
    local t = ScriptWindowTitle('Rock Band General Helper',
                                TITLE_ROOT .. 'rock_band_general_helper_vkr.lua')
    local shown = t:match('^(.-)###')
    Test.expect(shown ~= nil, 'no ### separator in ' .. t)
    Test.expect(shown and shown:match('^Rock Band General Helper v%d') ~= nil,
        'got ' .. tostring(shown))
end)

Test.it('the version shown is the one in the header', function()
    local path = TITLE_ROOT .. 'rock_band_vocal_helper_vkr.lua'
    local ver  = HeaderVersionLine(path)
    Test.expect(ver ~= nil, 'no @version found in rock_band_vocal_helper_vkr.lua')
    local t = ScriptWindowTitle('Rock Band Vocal Helper', path)
    Test.expect(t == 'Rock Band Vocal Helper v' .. tostring(ver) ..
                     '###Rock Band Vocal Helper', 'got ' .. t)
end)

Test.it('falls back to the bare name when the file is missing', function()
    local t = ScriptWindowTitle('Some Window', TITLE_ROOT .. 'no_such_script_vkr.lua')
    Test.expect(t == 'Some Window', 'got ' .. t)
end)

Test.it('falls back to the bare name when there is no @version header', function()
    -- A real repo file with no @version line: the shared lib itself.
    local t = ScriptWindowTitle('Some Window', TITLE_ROOT .. 'lib/reaper_imgui_helpers.lua')
    Test.expect(t == 'Some Window', 'got ' .. t)
end)

Test.it('a bare name carries no ### id, so nothing keys geometry off a stray one', function()
    local t = ScriptWindowTitle('Some Window', TITLE_ROOT .. 'no_such_script_vkr.lua')
    Test.expect(t:find('###', 1, true) == nil, 'got ' .. t)
end)

------------------------------------------------------------------
Test.section('Window title: stable ImGui id')

-- The id after ### is what ImGui keys a window's saved size, position and dock
-- state by. It must stay the bare window name - the literal the label used to
-- be - or every existing user's window jumps back to its default on update.
for _, w in ipairs(WINDOWS) do
    local name, file = w[1], w[2]
    Test.it(('%s keeps its id equal to its name'):format(name), function()
        local t  = ScriptWindowTitle(name, TITLE_ROOT .. file)
        local id = t:match('###(.*)$')
        Test.expect(id == name, 'got id ' .. tostring(id) .. ' from ' .. t)
    end)
end

------------------------------------------------------------------
Test.section('Window title: real entry points')

-- Guards the silent failure: an entry point whose header stops parsing shows no
-- version at all, and nothing else in the repo would notice.
for _, w in ipairs(WINDOWS) do
    local name, file = w[1], w[2]

    Test.it(('%s ships a parseable @version'):format(file), function()
        local ver, line = HeaderVersionLine(TITLE_ROOT .. file)
        Test.expect(ver ~= nil, 'no @version line matched in ' .. file)
        Test.expect(line <= SCANNED_LINES,
            ('@version is on line %d, past the %d lines ScriptWindowTitle scans')
                :format(line, SCANNED_LINES))
    end)

    Test.it(('%s builds a title carrying that version'):format(name), function()
        local ver = HeaderVersionLine(TITLE_ROOT .. file)
        local t   = ScriptWindowTitle(name, TITLE_ROOT .. file)
        Test.expect(t == ('%s v%s###%s'):format(name, tostring(ver), name),
            'got ' .. t)
    end)
end

Test.it('every shipped window has a distinct id', function()
    local seen = {}
    for _, w in ipairs(WINDOWS) do
        Test.expect(not seen[w[1]], 'duplicate window name/id: ' .. w[1])
        seen[w[1]] = true
    end
end)
