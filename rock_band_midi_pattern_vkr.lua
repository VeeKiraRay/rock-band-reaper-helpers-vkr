-- @description Rock Band MIDI Pattern
-- @author VeeKiraRay
-- @version 0.2
-- @about
--   Standalone window for the MIDI > Pattern sub-tab of the Rock Band General
--   Helper. Capture a note pattern from a time selection, then find, replace,
--   tile or step through every recurrence of it on a MIDI track.
--
--   The sub-tab remains available inside the general helper; this entry point
--   offers the same UI in its own window so it can sit beside REAPER's MIDI
--   editor without the helper's other tabs coming along.
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   v0.2
--     - The window title now carries the script version - "Rock Band MIDI
--       Pattern v0.2". A bug report that quotes the title says which version
--       it came from, with nothing to look up. The version is read from this
--       file's own header when the script starts, so it can never disagree
--       with the version entries below.
--     - Your window size, position and dock state carry over unchanged, and
--       will survive every future version bump too.
--   v0.1
--     - Initial release. Reuses the general helper's module files directly
--       (ui_midi_pattern.lua and its dependencies) - fixes and features land
--       in both the sub-tab and this window automatically.

r = reaper  -- global so all dofile'd modules can use it

if not r.ImGui_CreateContext then
    r.ShowMessageBox(
        "This script requires the ReaImGui extension.\n\n" ..
        "Install it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and install it.",
        "Missing dependency", 0
    )
    return
end

if not r.ImGui_BeginDisabled then
    r.ShowMessageBox(
        "This script requires ReaImGui 0.7 or later.\n\n" ..
        "Update it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and update.",
        "ReaImGui version too old", 0
    )
    return
end

ctx = r.ImGui_CreateContext('Rock Band MIDI Pattern')  -- global

-- This entry point has no module folder of its own: it deliberately loads
-- the general helper's modules (rock_band_general_helper_vkr/) so the pattern
-- implementation is shared, not duplicated. Exception to the
-- "folder named after the script" rule.
--
-- Note the general helper's ui.lua is NOT in the list and must never be added:
-- its last line is a bare r.defer(Loop), which would spawn the full helper
-- window. Everything this window draws lives in ui_common.lua and
-- ui_midi_pattern.lua instead.
--
-- SCRIPT_DIR / SCRIPT_MDIR are not set: nothing in this subset reads them
-- (venue_sprites.lua is what forces the Venue Preview standalone to set them).
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. 'rock_band_general_helper_vkr/'

local _files = {
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'actions_midi_replace.lua',
    _mdir .. 'ui_common.lua',
    _mdir .. 'ui_midi_pattern.lua',
}

for _, _f in ipairs(_files) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_dir + 1) ..
            '\n\nPlease reinstall the script (this window needs the\n' ..
            'Rock Band General Helper files to be installed too).',
            'Missing file', 0)
        return
    end
end

for _, _f in ipairs(_files) do
    dofile(_f)
end

-- Window title with this script's own @version, read from the header above.
-- The "###" id inside keeps saved window geometry across version bumps.
-- See ScriptWindowTitle.
local _title = ScriptWindowTitle('Rock Band MIDI Pattern', _script)

-- No LoadSettings() / SetDefault*Tracks() here, unlike the other two standalone
-- windows: the Pattern sub-tab has never persisted anything (its S.mr_* fields
-- are marked session-only in defaults.lua, and settings.lua has no key for
-- them), and no SetDefault* function assigns its source track. Nothing to load.

local _active_proj = r.EnumProjects(-1, '')

local function Loop()
    -- Project switch: drop the cached track lists and the captured patterns.
    -- The patterns are take-relative PPQ offsets labelled with the previous
    -- project's measure numbers, so a Replace All after a switch would act on
    -- the wrong material. The general helper resets the same way.
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj      = proj
        S.all_track_list  = nil
        S.midi_track_list = nil
        S.last_result     = nil
        ResetMIDIPatternState()
        RefreshTrackLists()
        S.status = 'Project switched.'
    end

    -- Build the cached filtered lists on first frame if not yet populated.
    if not S.all_track_list then RefreshTrackLists() end

    r.ImGui_SetNextWindowSize(ctx, 560, 540, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, _title, true)
    if visible then
        -- The general helper keeps this button in General > Actions, which this
        -- window has no equivalent of. The source-track dropdown is not
        -- duplicated here - it belongs to DrawMIDIPatternTab.
        if Btn('Refresh tracks', BTN_H) then
            RefreshTrackLists()
            S.status = 'Track lists refreshed.'
        end
        Tooltip(TIPS.track_refresh)

        r.ImGui_Separator(ctx)

        DrawMIDIPatternTab()
        DrawStatusResultPanel(true)   -- true: Replace All / Fill Range write MIDI

        r.ImGui_End(ctx)
    end

    if open then r.defer(Loop) end
end

r.defer(Loop)
