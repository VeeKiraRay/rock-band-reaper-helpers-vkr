-- @description Rock Band Venue Preview
-- @author VeeKiraRay
-- @version 0.8
-- @about
--   Standalone window for the Venue > Preview sub-tab of the Rock Band
--   General Helper. Shows previous / current / next VENUE events (camera,
--   lighting, post-process) around the playhead with sprite animations.
--
--   The preview remains available as a sub-tab inside the general helper;
--   this entry point offers the same UI in its own window so it can sit
--   next to the generation tabs (e.g. Manual) without tab switching.
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.8
--     - Camera row: when no stacked shot fits the chosen Players lineup, the
--       event's name turns amber with a * and the picture shows what the
--       game plays instead - the remaining member's single shot for a duo,
--       All (near) for a one-member shot (one of the band shots it picks at
--       random); hover the name for which. A directed cut that cannot play is
--       red and pictured as All (near): the game drops it and shows a generic
--       band shot, picked at random (checked in game). Replaces the red "No
--       suitable event" card.
--     - The camera row marks what the game does around directed cuts for the
--       chosen lineup (tested in game), each event at its own position: the
--       shot right after a directed cut says "~ plays as soon as the directed
--       ends" (its own position does not matter in game); one the game never
--       shows, because the next event cuts the move first, says "-> never
--       shown" and its directed cut "-> skips the next shot"; and a directed
--       cut right after a directed cut is red, pictured as what plays instead.
--       Hover for the details. The new Camera: Mark directed-cut timing checkbox
--       (on by default, saved from the General Helper's Settings) turns the
--       marks off. (With General Helper v0.9.64.)
--     - Show has a new Current only H option: the current camera, lighting
--       and post-process event side by side on one row. The old Current only
--       is now Current only V; a saved Show choice is kept.
--     - It loads the General Helper's settings files, which gained Animation >
--       Beat's double-time downbeat option in General Helper v0.9.64; this
--       window reads past it and behaves as before.
--     - The shared venue files it loads now spell the lighting keyframe
--       trigger [prev] (General Helper v0.9.64). This window does not show
--       keyframe events, so nothing here looks different.
--     - The same settings files now store Animation > Drums' soft hits as two
--       options, soft crash and soft snare (General Helper v0.9.64). This
--       window has no drum options and saves them as it found them. The
--       defaults file also gained the Metadata > Genre texts and new Venue
--       keyframe, Directed moves and camera validation tooltips, all unused
--       here.
--     - Fixed: opening another project in the same project tab (File > Open,
--       recent projects) kept the previous project's saved preview settings.
--       They now load, as they already did when switching project tabs.
--     - Secondary text (hints, empty states, "not set", minor headings) is a
--       lighter grey that is easier to read. The same grey is used everywhere.
--     - The "blending now" line and a fallback camera's name use the same
--       amber as the General Helper's other warnings (they were a lighter
--       amber). The Players row's idle blue is a brighter sky blue, the blue
--       the General Helper uses everywhere now.
--     - Starts from your My defaults (saved in the General Helper's
--       General > Settings) when the project has no settings of its own -
--       preview size, Animated / Still, Players and Show included. Switching
--       to a project without settings no longer keeps the previous project's.
--       (With General Helper v0.9.64.)
--   v0.7
--     - No change to this window. The General Helper's instrument tabs moved
--       to the new Instrument Helper (General Helper v0.9.63), and the track
--       lookup this window uses moved into the shared lib folder with them;
--       this window now loads it from there.
--     - No change to what this window does: it notices project edits with the
--       same shared check the helpers now use to keep their track lists
--       current, instead of its own copy of it.
--   v0.6
--     - No change to this window. It loads the general helper's settings files,
--       which gained the new Overdrive tab's options in general helper v0.9.60;
--       this window reads past them and behaves exactly as before. Bumped so its
--       version keeps describing the code it runs.
--   v0.5
--     - The window title now carries the script version - "Rock Band Venue
--       Preview v0.5". A bug report that quotes the title says which version
--       it came from, with nothing to look up. The version is read from this
--       file's own header when the script starts, so it can never disagree
--       with the version entries below.
--     - Your window size, position and dock state carry over unchanged, and
--       will survive every future version bump too.
--   v0.4
--     - The preview now understands blends. A blend is authored by writing the
--       running lighting or post proc preset a second time just before the
--       change, so the game fades into it instead of cutting. That second copy
--       is an anchor, not a preset of its own, so it is no longer shown as its
--       own event - before, the same preset filled two columns and every fade
--       looked like a hard cut.
--     - Each lighting and post proc card now says how it hands over to the next
--       one: "blends into next", "blending now" while the playhead is inside
--       the fade, or "hard cut to next" - which is a valid authoring choice,
--       not an error. Camera cards have no such line; a camera cut never fades.
--       Same change as the general helper's Venue > Preview sub-tab (v0.9.53).

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
    _dir  .. 'lib/reaper_helper_common.lua',
    _dir  .. 'lib/reaper_venue_shots.lua',        -- directed-cut move lengths
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'venue_camera_priority.lua',
    _mdir .. 'venue_camera_timing.lua',
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

-- Window title with this script's own @version, read from the header above.
-- The "###" id inside keeps saved window geometry across version bumps.
-- See ScriptWindowTitle.
local _title = ScriptWindowTitle('Rock Band Venue Preview', _script)

-- Startup initialisation: pick up saved preview settings (scale, animate,
-- players combo, show mode). Saving stays in the general helper's General
-- tab; this window never writes settings.
LoadSettings()

local _project_switched = MakeProjectSwitchCheck()   -- pointer + file path

local function Loop()
    -- Project switch: reload that project's saved settings. Event data
    -- refreshes itself via GetProjectStateChangeCount inside the preview.
    if _project_switched() then
        LoadSettings()
    end

    r.ImGui_SetNextWindowSize(ctx, 700, 720, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, _title, true)
    if visible then
        DrawVenuePreviewTab()
        DrawActivePlayersRow()
        r.ImGui_End(ctx)
    end
    if open then r.defer(Loop) end
end

r.defer(Loop)
