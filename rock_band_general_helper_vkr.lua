-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.20
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - audio alignment, count-in positioning, song fade out, settings
--     Tempo Map  - audio-driven tempo map generation from drum stems
--     Drums      - convert GM MIDI to Rock Band 5-lane drum notation
--     Keys       - hand split, Pro Keys conversion + animation, 5-Lane Keys conversion
--     Guitar     - convert raw MIDI to Expert Guitar gems, tab guide, validate
--     Difficulty - suggest and validate Pro Keys + 5-Lane Keys difficulty tiers
--     Tab Input  - guitar/keys/vocal tab entry guide
--     MIDI       - MIDI alignment, length sync, pattern replace
--     Venue      - list, validate, and generate VENUE and EVENTS track events
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.9.20
--     - Fix: Difficulty > Pro Keys validation (Suggest/Validate) misclassified
--       reserved marker pitches - overdrive (116), glissando (126), trill
--       (127) - as playable notes, so they could be merged into a chord with
--       a real note or fed into interval-jump/spacing/overlap checks,
--       producing false-positive issues (e.g. a huge chord span or jump
--       measured against an overdrive marker). Only notes in the playable
--       C2-C4 range (48-72) are now treated as chord/gem events. The
--       standalone "note range" check is removed since it can no longer
--       trigger - filtering now happens before events are built.
--   v0.9.19
--     - Fix: RadioGroupWidth()'s per-option padding was a fixed pixel guess
--       that could undershoot the real rendered width of a radio button at
--       larger REAPER UI scales, causing the second option to overlap the
--       first's label when the group's labels were short (surfaced by the
--       Tab Input tab's Horizontal/Vertical row after its width group
--       shrank from 5 labels to 2). Now derives padding from
--       ImGui_GetFrameHeight() + the real ItemSpacing style value (tracks
--       font size / UI scale) plus a fixed cushion, instead of a flat guess;
--       falls back to the old fixed constant if GetFrameHeight isn't
--       available. (First pass still left Horizontal/Vertical visibly tight
--       - the flat "+10" buffer wasn't enough headroom on the group's widest
--       label; this revision widens it.)
--     - General tab: "Song fade out" moved back to the Actions sub-tab
--       (it's an action, not a setting).
--     - Venue > Actions: "List venue events"/"List event sections"/"List
--       lighting/postproc" grouped under an "Analyze" label; "Generate sing
--       along" under its own "Quick actions" label - same pattern as the
--       General tab's "General actions"/"Audio alignment" split.
--     - Venue > Section gen and Manual gen: the Keyframe align dropdown is
--       now the same width as the Lighting dropdown in the same sub-tab
--       (was narrower than Lighting in both).
--   v0.9.18
--     - General tab: split into Actions (General actions, Audio alignment)
--       and Settings (Song fade out, Venue preview, WIP tabs, Settings)
--       sub-tabs. Save/Load moved to the end of Settings, after the values
--       they persist.
--     - Difficulty tab: Validate row now wraps at 3 buttons per row (Expert/
--       Hard/Medium, then Easy/All) instead of 4+1, since the button text is
--       long. Applies to both Pro Keys and 5-Lane Keys sub-tabs.
--     - Tab Input tab: the Guitar/Bass, Keys/Pro Keys, and Vocal instrument
--       modes are now sub-tabs instead of radio buttons. The Horizontal/
--       Vertical format selector's column width no longer factors in the
--       old mode-selector labels.
--     - MIDI tab: MIDI Alignment, MIDI Length Sync, and Pattern Replace are
--       now sub-tabs (Alignment / Length / Pattern) instead of stacked
--       sections.
--     - Venue > Section gen: the Custom/Template selector now has a "Mode"
--       label, aligned with the rest of the tab's inputs.
--     - Venue > Manual gen: the Keyframes button moved next to the Keyframe
--       align dropdown and renamed to "Add" (was on the Lighting row).
--       Subdivision (Every beat/Every half beat) moved to its own labeled
--       row, matching Section gen and Themes gen's style, instead of sitting
--       inline after the Keyframe align dropdown.
--     - Venue > Keyframes: Subdivision moved to its own labeled row, same
--       change as Manual gen.
--   v0.9.17
--     - Radio button options now align into columns within each tab view via
--       a new RadioGroupWidth() helper (in lib/reaper_imgui_helpers.lua,
--       same idea as BtnGroupWidth()/LabelColWidth() but for radio option
--       spacing): General tab (Preview size/Sprites/Show WIPs?), Guitar WIP
--       tab (Max chord/Workflow - also gained its first row-label column),
--       Tab Input tab (instrument mode/format selector), Keys tab (Split
--       by/Max chord/Workflow - also gained a row-label column), and Venue >
--       Preview (Players/Preview size/Sprites/Show).
--   v0.9.16
--     - Row labels (the text before a dropdown/slider/radio group) now align
--       within each tab or sub-tab via a new LabelColWidth() helper (in
--       lib/reaper_imgui_helpers.lua), same idea as BtnGroupWidth() but for
--       label columns instead of button widths: General tab (Preview size/
--       Sprites/Show WIPs?), Difficulty > Pro Keys (Expert/Hard/Medium/
--       Easy), MIDI tab (Source track/Reference track), Venue > Themes gen,
--       Section gen, and Manual gen (Remove folded into the existing
--       column), Venue > Preview (Players/Preview size/Sprites/Show).
--       RenderKeyframeAlignCombo() gained an optional col_offset param
--       (matching RenderCamPacingRow()) so it can join a tab's column.
--       Also replaced two remaining hardcoded-longest-label guesses (Venue
--       > Events, Venue > Keyframes) with the same helper for consistency.

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

ctx = r.ImGui_CreateContext('Rock Band General Helper')  -- global

-- Module files live in a subfolder named after this script (without .lua).
-- Renaming the entry point requires renaming the folder too - intentional.
local _script  = ({reaper.get_action_context()})[2]
local _dir     = _script:match('^(.+[\\/])')
local _mdir    = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'
SCRIPT_MDIR    = _mdir  -- global: module files need this for filesystem paths
SCRIPT_DIR     = _dir   -- global: repo root; used for resources/ paths (e.g. themes, spritesheets)

for _, _f in ipairs({
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_dsp.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'section_events.lua',
    _mdir .. 'venue_themes.lua',
    _mdir .. 'venue_camera.lua',
    _mdir .. 'venue_sprites.lua',
    _mdir .. 'venue_lighting.lua',
    _mdir .. 'venue_generator.lua',
    _mdir .. 'actions_venue_section.lua',
    _mdir .. 'actions_venue_manual.lua',
    _mdir .. 'actions_venue_events.lua',
    _mdir .. 'actions_venue_keyframes.lua',
    _mdir .. 'actions_venue_sing_along.lua',
    _mdir .. 'tempomap.lua',
    _mdir .. 'actions.lua',
    _mdir .. 'actions_tempomap.lua',
    _mdir .. 'actions_drums.lua',
    _mdir .. 'actions_keys.lua',
    _mdir .. 'actions_keys_guides.lua',
    _mdir .. 'actions_guitar.lua',
    _mdir .. 'actions_guitar_guide.lua',
    _mdir .. 'actions_guitar_validate.lua',
    _mdir .. 'actions_midi_align.lua',
    _mdir .. 'actions_midi_replace.lua',
    _mdir .. 'actions_difficulty.lua',
    _mdir .. 'actions_difficulty_5k.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_midi.lua',
    _mdir .. 'ui_venue.lua',
    _mdir .. 'ui_venue_section_gen.lua',
    _mdir .. 'ui_venue_manual.lua',
    _mdir .. 'ui_venue_events.lua',
    _mdir .. 'ui_venue_preview.lua',
    _mdir .. 'ui_venue_keyframes.lua',
    _mdir .. 'ui_venue_players.lua',
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
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'venue.lua')
dofile(_mdir .. 'venue_awareness.lua')
dofile(_mdir .. 'section_events.lua')
dofile(_mdir .. 'venue_themes.lua')
dofile(_mdir .. 'venue_camera.lua')
dofile(_mdir .. 'venue_sprites.lua')
dofile(_mdir .. 'venue_lighting.lua')
dofile(_mdir .. 'venue_generator.lua')
dofile(_mdir .. 'actions_venue_section.lua')
dofile(_mdir .. 'actions_venue_manual.lua')
dofile(_mdir .. 'actions_venue_events.lua')
dofile(_mdir .. 'actions_venue_keyframes.lua')
dofile(_mdir .. 'actions_venue_sing_along.lua')
dofile(_mdir .. 'tempomap.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'actions_tempomap.lua')
dofile(_mdir .. 'actions_drums.lua')
dofile(_mdir .. 'actions_keys.lua')
dofile(_mdir .. 'actions_keys_guides.lua')
dofile(_mdir .. 'actions_guitar.lua')
dofile(_mdir .. 'actions_guitar_guide.lua')
dofile(_mdir .. 'actions_guitar_validate.lua')
dofile(_mdir .. 'actions_midi_align.lua')
dofile(_mdir .. 'actions_midi_replace.lua')
dofile(_mdir .. 'actions_difficulty.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'ui_keys.lua')
dofile(_mdir .. 'ui_midi.lua')
dofile(_mdir .. 'ui_venue.lua')
dofile(_mdir .. 'ui_venue_section_gen.lua')
dofile(_mdir .. 'ui_venue_manual.lua')
dofile(_mdir .. 'ui_venue_events.lua')
dofile(_mdir .. 'ui_venue_preview.lua')
dofile(_mdir .. 'ui_venue_keyframes.lua')
dofile(_mdir .. 'ui_venue_players.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
