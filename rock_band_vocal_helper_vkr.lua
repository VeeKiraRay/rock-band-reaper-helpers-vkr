-- @description Rock Band Vocal Helper
-- @author VeeKiraRay
-- @version 1.6
-- @about
--   Analyses a vocal audio track and appends MIDI notes to an existing MIDI
--   item on a destination track, one note per detected syllable or phrase.
--   Supports two pitch correction sources: reference MIDI and built-in YIN
--   monophonic pitch detection. Includes Auto-tune to fit detection
--   parameters to manually-placed reference timing notes.
--
--   Built with Claude (Anthropic) — https://claude.ai
--
--   v1.6
--     - Validation tab: Validate phrases checks all phrase-marker regions for
--       six common authoring issues: lyric capitalization, grid snap (start and
--       end on a 64th-note boundary), gap to the next phrase (>= 4x64th),
--       first note lead (>= 2x64th from phrase start), and last note tail
--       (>= 1x64th before phrase end). Read-only; reports violations grouped
--       by phrase position.
--
--   v1.5
--     - Generate (replace): new button clears all vocal-range notes in the
--       analysis range before inserting, producing a clean result. Phrase
--       markers at other pitches are preserved.
--     - Generate (append) renamed from "Generate notes (append)".
--     - Pitch name display now uses Rock Band octave numbering (C1=36).
--     - Generate and Dry run always assign a fixed pitch (Default pitch
--       slider, now on the Note Placement tab). Pitch tab is now exclusively
--       for Apply pitch changes: only Built-in detection and Reference MIDI
--       remain; Single pitch mode removed; YIN is the new default.
--       Apply pitch changes is always enabled.
--     - Validation tab renamed to Pitch slide. YIN threshold and frequency
--       sliders added alongside Slide Scan controls so the full pitch slide
--       workflow is contained in one tab.
--
--   v1.4
--     - Slide Scan sliders added to the Validation tab: all five scan
--       parameters (min note length, min segment, edge skip, sample step,
--       sample window) are now adjustable and persisted with project settings.
--
--   v1.3
--     - Tab-based UI: reorganised into 5 tabs (General, Note Placement,
--       Pitch, Lyrics, Validation). Track selectors and status/results panel
--       remain global above and below the tab bar.
--     - MIDI destination track selector now appears before Audio source.
--     - "Note Detection" section renamed to "Note Placement".
--
--   v1.2
--     - Added Scan pitch slides: scans existing MIDI notes and reports any
--       where pitch moves significantly during the note (Slide up/down,
--       Scoop, Bend, Complex slide). Read-only; respects time selection.
--       Includes lyric text in the report when present.
--
--   v1.1
--     - Added Auto-tune YIN from reference: sweeps YIN parameters
--       (threshold, frequency range, window) against manually corrected
--       pitches to find the best-fit settings automatically.
--     - Fixed Assign lyrics to always operate on the whole MIDI take,
--       ignoring any time selection (required for correct word-to-note order).
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
-- Renaming the entry point requires renaming the folder too — intentional.
local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'

dofile(_dir  .. 'lib/reaper_imgui_helpers.lua')
dofile(_dir  .. 'lib/reaper_dsp.lua')
dofile(_dir  .. 'lib/reaper_midi_helpers.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'pipeline.lua')
dofile(_mdir .. 'autotune.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTracks()
AutoDetectLyricsFile()
