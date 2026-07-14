-- @description Rock Band Venue Preview
-- @author VeeKiraRay
-- @version 0.2
-- @about
--   Standalone window for the Venue > Preview sub-tab of the Rock Band
--   General Helper. Shows previous / current / next VENUE events (camera,
--   lighting, post-process) around the playhead with sprite animations.
--
--   The preview remains available as a sub-tab inside the general helper;
--   this entry point offers the same UI in its own window so it can sit
--   next to the generation tabs (e.g. Manual) without tab switching.
--
--   v0.2
--     - Added the "Active players" row below the preview: a colored dot per
--       instrument shows its state at the playhead - active (green), idle
--       (blue), track muted or missing (red), or no play-state events
--       (orange) - matching the general helper's Venue tab.
--   v0.1
--     - Initial release. Reuses the general helper's module files directly
--       (ui_venue_preview.lua and its dependencies) - fixes and features
--       land in both the sub-tab and this window automatically.

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

ctx = r.ImGui_CreateContext('Rock Band Venue Preview')  -- global

-- This entry point has no module folder of its own: it deliberately loads
-- the general helper's modules (rock_band_general_helper_vkr/) so the
-- preview implementation is shared, not duplicated. Exception to the
-- "folder named after the script" rule.
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. 'rock_band_general_helper_vkr/'
SCRIPT_DIR    = _dir   -- global: repo root; venue_sprites.lua needs this at load time
SCRIPT_MDIR   = _mdir  -- global: module folder (general helper's)

local _files = {
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'venue_sprites.lua',
    _mdir .. 'ui_venue_preview.lua',
    _mdir .. 'ui_venue_players.lua',
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

-- Startup initialisation: pick up saved preview settings (scale, animate,
-- players combo, show mode). Saving stays in the general helper's General
-- tab; this window never writes settings.
LoadSettings()

local _active_proj = r.EnumProjects(-1, '')

local function Loop()
    -- Project switch: reload that project's saved settings. Event data
    -- refreshes itself via GetProjectStateChangeCount inside the preview.
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj = proj
        LoadSettings()
    end

    r.ImGui_SetNextWindowSize(ctx, 700, 720, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band Venue Preview', true)
    if visible then
        DrawVenuePreviewTab()
        DrawActivePlayersRow()
        r.ImGui_End(ctx)
    end
    if open then r.defer(Loop) end
end

r.defer(Loop)
