-- @description Rock Band Venue Demo Generator
-- @author VeeKiraRay
-- @about
--   Standalone development tool for generating demo VENUE tracks used
--   as the source for venue event preview spritesheets.
--
--   Generates a deterministic VENUE MIDI track with one event per window
--   (camera cuts, lighting presets, or post-process effects) plus a manifest
--   CSV so a capture-and-convert pipeline can slice the video into individual
--   spritesheet images.
--
--   Separate entry point from the main helpers: this is a dev/authoring aid,
--   not a charting tool.

r = reaper  -- global so all dofile'd modules can use it

if not r.ImGui_CreateContext then
    r.ShowMessageBox(
        "This script requires the ReaImGui extension.\n\n" ..
        "Install it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and install it.",
        "Missing dependency", 0)
    return
end

if not r.ImGui_BeginDisabled then
    r.ShowMessageBox(
        "This script requires ReaImGui 0.7 or later.\n\n" ..
        "Update it via Extensions > ReaPack > Browse packages,\n" ..
        "then search for 'ReaImGui' and update.",
        "ReaImGui version too old", 0)
    return
end

ctx = r.ImGui_CreateContext('Rock Band Venue Demo')  -- global

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _root   = _dir .. '../'
local _mdir   = _dir  .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'
SCRIPT_DIR  = _root  -- global: repo root
SCRIPT_MDIR = _mdir  -- global: module folder

for _, _f in ipairs({
    _root .. 'lib/reaper_imgui_helpers.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'actions.lua',
    _mdir .. 'ui.lua',
}) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_root + 1) ..
            '\n\nPlease reinstall the script.',
            'Missing file', 0)
        return
    end
end

dofile(_root .. 'lib/reaper_imgui_helpers.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end
