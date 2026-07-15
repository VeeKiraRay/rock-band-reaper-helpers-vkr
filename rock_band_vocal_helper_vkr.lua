-- @description Rock Band Vocal Helper
-- @author VeeKiraRay
-- @version 1.12
-- @about
--   Analyses a vocal audio track and appends MIDI notes to an existing MIDI
--   item on a destination track, one note per detected syllable or phrase.
--   Supports two pitch correction sources: reference MIDI and built-in YIN
--   monophonic pitch detection. Includes Auto-tune to fit detection
--   parameters to manually-placed reference timing notes.
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v1.12
--     - Sliders and combo boxes now use a fixed pixel width
--       (SetNextItemWidth(ctx, 200), matching the general helper's
--       convention) instead of stretching to fill the window on resize.
--       Applied across General, Tuner, Pitch, Pitch slide, Harmonies, and
--       Validation tabs (WIP Note Placement tab intentionally left as-is,
--       to be redone later).
--
--   v1.11
--     - Pitch tab: removed the "Pitch source" selector. Placement is now two
--       sub-tabs, Placement - Built-in and Placement - Reference, each
--       setting the active pitch source while open (mirrors the general
--       helper's Tab Input pattern). Apply pitch changes appears in both.
--     - Harmonies: "Copy phrase markers & overdrive" split into two
--       independent checkboxes/settings - Copy phrase markers (pitch 105)
--       and Copy overdrive (pitch 116, new RB3_OVERDRIVE_PITCH constant).
--     - Lyrics tab: "File: ..." renamed to "Selected: ..." in normal text
--       color (was greyed out), avoiding repeating "File" under its new
--       section header.
--     - Min/max pitch enable checkbox tooltips now say "Uncheck" instead of
--       "Disable".
--
--   v1.10
--     - UI consistency pass matching the general helper's conventions:
--       row labels now sit to the left of their slider/combo/checkbox and
--       align into a shared column (LabelColWidth()) instead of relying on
--       ImGui's native trailing label; radio rows use RadioGroupWidth() for
--       uniform option widths. Applied across General, Tuner, Pitch, Lyrics,
--       Pitch slide, Harmonies, and Validation tabs (WIP Note Placement tab
--       intentionally left as-is, to be redone later).
--     - General tab split into Actions (Refresh tracks) and Settings (WIP
--       tabs, then Save/Load last) sub-tabs, mirroring the general helper.
--     - Pitch tab split into Placement and Snap sub-tabs; the "Pitch range"
--       Min/Max pitch rows now read label -> slider -> enable checkbox
--       (checkbox moved from the slider's left to its right). Pitch tab
--       content moved to a new ui_pitch.lua module (DrawPitchTab).
--     - Lyrics tab buttons grouped under File (Auto-detect, Browse...) and
--       Actions (Clear lyrics, Assign lyrics) section headers.
--
--   v1.9
--     - Related buttons now share a uniform width per group
--       (BtnGroupWidth(), from lib/reaper_imgui_helpers.lua) instead of each
--       sizing to its own label: Save/Load (General tab) and
--       Auto-detect/Browse.../Clear lyrics/Assign lyrics (Lyrics tab).
--
--   v1.8
--     - Internal housekeeping, no behavior changes. Every button in every tab
--       now goes through a shared Btn(label, height) helper (new, in
--       lib/reaper_imgui_helpers.lua) instead of a manual CalcTextSize+Button
--       pair, so each label string appears once instead of twice. Also fixes
--       a pre-existing hardcoded button width (Save/Load, General tab) to
--       compute from its label like every other button.
--
--   Workflow:
--     1. Pick the audio source track and the MIDI destination track.
--        The destination track must contain a MIDI item that covers the range.
--     2. (Optional) Make a time selection to restrict analysis.
--     3. Configure detection settings; pick a Pitch source.
--     4. Dry run to check counts, Auto-tune to fit reference timing notes,
--        Generate to write into the destination MIDI item.
--     5. Or, if you've already tweaked the notes manually and just want to add
--        pitch info, use Apply pitch changes.

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

ctx = r.ImGui_CreateContext('Rock Band Vocal Helper')  -- global

-- Module files live in a subfolder named after this script (without .lua).
-- Renaming the entry point requires renaming the folder too - intentional.
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'

for _, _f in ipairs({
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_dsp.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'tips.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'pipeline.lua',
    _mdir .. 'autotune.lua',
    _mdir .. 'tuner.lua',
    _mdir .. 'actions.lua',
    _mdir .. 'actions_lyrics.lua',
    _mdir .. 'actions_validation.lua',
    _mdir .. 'actions_harmonies.lua',
    _mdir .. 'actions_slides.lua',
    _mdir .. 'actions_snap_key.lua',
    _mdir .. 'ui_slides.lua',
    _mdir .. 'ui_harmonies.lua',
    _mdir .. 'ui.lua',
}) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_dir + 1) ..
            '\n\nPlease reinstall the script.',
            'Missing file', 0)
        return
    end
end

dofile(_dir  .. 'lib/reaper_imgui_helpers.lua')
dofile(_dir  .. 'lib/reaper_dsp.lua')
dofile(_dir  .. 'lib/reaper_midi_helpers.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'tips.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'pipeline.lua')
dofile(_mdir .. 'autotune.lua')
dofile(_mdir .. 'tuner.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'actions_lyrics.lua')
dofile(_mdir .. 'actions_validation.lua')
dofile(_mdir .. 'actions_harmonies.lua')
dofile(_mdir .. 'actions_slides.lua')
dofile(_mdir .. 'actions_snap_key.lua')
dofile(_mdir .. 'ui_slides.lua')
dofile(_mdir .. 'ui_harmonies.lua')
dofile(_mdir .. 'ui_pitch.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTracks()
AutoDetectLyricsFile()
