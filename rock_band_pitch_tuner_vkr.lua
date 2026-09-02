-- @description Rock Band Pitch Tuner
-- @author VeeKiraRay
-- @version 0.2
-- @about
--   Standalone window for the Tuner tab of the Rock Band Vocal Helper. Reads
--   audio from the selected source track at the playhead and shows the
--   detected note, frequency, confidence and a short history strip.
--
--   The tuner remains available as a tab inside the vocal helper; this entry
--   point offers the same UI in its own window so it can stay visible while
--   you work in another tab (Pitch, Lyrics) or another window.
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   v0.2
--     - The window title now carries the script version - "Rock Band Pitch
--       Tuner v0.2". A bug report that quotes the title says which version
--       it came from, with nothing to look up. The version is read from this
--       file's own header when the script starts, so it can never disagree
--       with the version entries below.
--     - Your window size, position and dock state carry over unchanged, and
--       will survive every future version bump too.
--   v0.1
--     - Initial release. Reuses the vocal helper's module files directly
--       (ui_tuner.lua and its dependencies) - fixes and features land in both
--       the tab and this window automatically.

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

ctx = r.ImGui_CreateContext('Rock Band Pitch Tuner')  -- global

-- This entry point has no module folder of its own: it deliberately loads
-- the vocal helper's modules (rock_band_vocal_helper_vkr/) so the tuner
-- implementation is shared, not duplicated. Exception to the
-- "folder named after the script" rule.
--
-- Note the vocal helper's ui.lua is NOT in the list: its last line is a bare
-- r.defer(Loop), which would spawn the full helper window. Everything this
-- window draws lives in ui_common.lua and ui_tuner.lua instead.
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. 'rock_band_vocal_helper_vkr/'

local _files = {
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_dsp.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'tips.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'tuner.lua',
    _mdir .. 'ui_common.lua',
    _mdir .. 'ui_tuner.lua',
}

for _, _f in ipairs(_files) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_dir + 1) ..
            '\n\nPlease reinstall the script (this window needs the\n' ..
            'Rock Band Vocal Helper files to be installed too).',
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
local _title = ScriptWindowTitle('Rock Band Pitch Tuner', _script)

-- Startup initialisation: pick up saved detection settings (YIN threshold,
-- frequency range, window, confidence, RMS gate, pitch range). Saving stays
-- in the vocal helper's General tab; this window never writes settings.
LoadSettings()
SetDefaultTracks()

local _active_proj = r.EnumProjects(-1, '')

local function Loop()
    -- Project switch: reset the track selection and reload that project's
    -- saved settings. The tuner's audio accessor belongs to the old project's
    -- take, so it has to be closed here.
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj       = proj
        S.audio_idx        = 0
        S.all_track_list   = nil
        S.midi_track_list  = nil
        S.audio_track_list = nil
        S.last_result      = nil
        if S.tuner_active then StopTuner('Pitch tuner stopped: project switched.') end
        S.tuner_pitch       = nil
        S.tuner_prev_pitch  = nil
        S.tuner_pitch_name  = nil
        S.tuner_pitch_hz    = nil
        S.tuner_confidence  = nil
        S.tuner_pitch_ts    = nil
        S.tuner_quiet_since = nil
        S.tuner_history     = {}
        RefreshTrackLists()
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        SetDefaultTracks()
    end

    -- No tab bar in this window, so the tuner is always on screen. RunTuner
    -- stops itself when this flag is false (the vocal helper's navigated-away
    -- guard), so it has to be pinned true here every frame.
    S.tuner_tab_active = true

    -- Run the pitch tuner poll before any UI rendering: the readout below
    -- reads S.tuner_quiet_since that RunTuner has just written.
    RunTuner()

    -- Build the cached filtered lists on first frame if not yet populated.
    if not S.all_track_list then RefreshTrackLists() end

    r.ImGui_SetNextWindowSize(ctx, 560, 640, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, _title, true)
    if visible then
        r.ImGui_Text(ctx, 'Audio source track')
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S.audio_idx = FilteredTrackCombo('##audio_tur', S.audio_idx, S.audio_track_list)
        r.ImGui_SameLine(ctx)
        if Btn('Refresh tracks', BTN_H) then
            RefreshTrackLists()
            S.status = 'Track lists refreshed.'
        end
        Tooltip(TIPS.track_refresh)

        r.ImGui_Separator(ctx)

        DrawTunerTab()
        DrawStatusResultPanel(false)

        r.ImGui_End(ctx)
    end

    -- Closing the window ends the defer chain, so stop the tuner here or its
    -- audio accessor stays open (holding the source file) until REAPER exits.
    if not open and S.tuner_active then StopTuner() end

    if open then r.defer(Loop) end
end

r.defer(Loop)
