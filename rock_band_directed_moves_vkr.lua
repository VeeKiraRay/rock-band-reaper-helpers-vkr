-- @description Rock Band Directed Moves
-- @author VeeKiraRay
-- @version 0.1
-- @about
--   Standalone reference window: what the game can show for each directed
--   camera cut, read from the game's own venue files (all 44 RB3 venues).
--   A companion to the Rock Band General Helper's Venue > Manual gen and
--   Venue > Preview: keep it open beside them while picking directed cuts.
--   Read-only - it never touches the project.
--
--   v0.1
--     - First version. Search by camera event or by keyword ("kiss", "jump",
--       "mic stand"); each event lists its moves - who moves, for which song
--       style and gender, in which kinds of venue, how many variants, its
--       lead-in (how early the move starts) - plus how long its versions run,
--       measured from the venue files (per venue kind when a Venue is
--       picked), and amber notes for a cut whose versions can hold the camera
--       longer than usual, one missing from some venues, or one the band
--       lineup changes (a dropped cut gets a random generic band shot).
--       Filters for song style, focus member, venue and band dim the moves
--       that would not play; clicking a move shows its
--       event with the filters it needs, so the moves left undimmed are the
--       ones competing with it.
--     - Open it from the Actions list, from General > Other tools in any of
--       the helpers, or from the General Helper's Venue > Actions. It was a
--       Venue sub-tab while General Helper v0.9.64 was in development.

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

ctx = r.ImGui_CreateContext('Rock Band Directed Moves')  -- global

-- This entry point has no module folder of its own: it loads the general
-- helper's modules (rock_band_general_helper_vkr/) and the shared shot data in
-- lib/, so the view is not duplicated. Exception to the "folder named after the
-- script" rule, like rock_band_preview_vkr.lua.
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. 'rock_band_general_helper_vkr/'
SCRIPT_DIR    = _dir   -- global: repo root; venue_sprites.lua needs this at load time
SCRIPT_MDIR   = _mdir  -- global: module folder (general helper's)

local _files = {
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_venue_shots.lua',        -- generated (frozen) shot data
    _dir  .. 'lib/reaper_venue_shots_query.lua',
    _mdir .. 'defaults.lua',                      -- S (session-only state), TIPS
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'venue_themes.lua',
    _mdir .. 'venue_camera.lua',                  -- DIRECTED_LABELS / DIRECTED_TIPS / COOP_LABELS
    _mdir .. 'venue_sprites.lua',                 -- VenueEventTooltip
    _mdir .. 'ui_venue_camera_shots.lua',         -- DrawVenueCameraShotsTab
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
local _title = ScriptWindowTitle('Rock Band Directed Moves', _script)

-- No settings: the search and filters are session-only, and nothing here reads
-- the project, so there is no project-switch handling either.
local function Loop()
    r.ImGui_SetNextWindowSize(ctx, 820, 640, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, _title, true)
    if visible then
        DrawVenueCameraShotsTab()
        r.ImGui_End(ctx)
    end
    if open then r.defer(Loop) end
end

r.defer(Loop)
