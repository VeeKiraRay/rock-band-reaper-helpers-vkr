-- @description Rock Band Vocal Helper
-- @author VeeKiraRay
-- @version 1.21
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
--   v1.21
--     - The Tuner and Pitch slide tabs are now sub-tabs of the Pitch tab,
--       which reads Tuner, Snap, Slide, Placement - Built-in, Placement -
--       Reference. The sub-tabs work exactly as the tabs did; leaving the
--       Tuner sub-tab still stops a running tuner.
--     - The track dropdowns now have a "(none)" entry, like the other
--       helpers'. An action run with a needed track set to (none), or with
--       a track that was deleted, says which track to pick instead of
--       failing.
--     - The time selection is shown in the status panel at the bottom of the
--       window, as in the other helpers, instead of under the track
--       dropdowns.
--     - The track dropdowns, status panel and error handling now share their
--       code with the General and Instrument helpers, so a fix to one reaches
--       all of them.
--     - New footer, always at the bottom of the window: the time selection,
--       the status line, Copy result (the status and result to the clipboard)
--       and Undo. The tabs scroll above it, so on a short window these no
--       longer scroll out of sight. The track dropdowns now update on their
--       own: adding, renaming or deleting a track, or adding an item to one,
--       shows up within about a second. The Refresh tracks button is gone.
--       General > Actions, which held only that button, is gone.
--     - The MIDI destination / Audio source bar above the tabs is gone. Each
--       view shows only the track it uses - Lyrics, Validation and Pitch >
--       Snap the MIDI track, Pitch > Tuner the audio track, Pitch > Slide and
--       Placement - Built-in both - and a track picked in one view is picked
--       in all of them. Harmonies keeps its own track rows.
--     - Harmonies: the Target track dropdowns list only MIDI tracks, like
--       Source. They listed every track, so an audio track could be picked
--       and the run then stopped with "No MIDI item on destination".
--     - Pitch > Tuner: new Harmony readout (experimental). Tick it and pick
--       the lead chart (HARM1, or PART VOCALS): below the usual readout, HARM1
--       shows the charted lead note and how clearly the audio has it, HARM2
--       the second voice in the same vocal recording. It cancels the charted
--       lead note from the audio and reads what is left. While playing,
--       HARM2 is a vote over the current lead note so far; with playback
--       stopped, the whole note under the cursor is read. Its "% agree" says
--       how many slices voted for it. Optional key snap: off, the key worked
--       out from the lead chart, or a key you pick. Read-only - it never
--       writes notes. Measured on official songs, about a third of harmony
--       notes come out exactly right and half with the right note name;
--       a harmony an octave above the lead and a third voice cannot be read.
--       "Spectral reading too" (off by default) adds a second way of reading
--       the voices - the way a spectrogram shows them - and lets both vote:
--       about 4 points more harmony notes right in the measurements, most
--       of it on harmonies above the lead, some an octave above.
--     - The Piano / keys preset is now called "Piano / keys (clean
--       single-note lines)": it reads an isolated single-note line
--       exactly, but not a stem where other sounds play along.
--   v1.20
--     - The window title now carries the script version - "Rock Band Vocal
--       Helper v1.20". A bug report that quotes the title says which version
--       it came from, with nothing to look up. The version is read from this
--       file's own header when the script starts, so it can never disagree
--       with the version entries below.
--     - Your window size, position and dock state carry over unchanged, and
--       will survive every future version bump too.
--   v1.19
--     - General > Other tools: new MIDI Pattern button, a standalone window
--       carrying the General Helper's MIDI > Pattern sub-tab (capture a note
--       pattern from a time selection, then find, replace, tile or step
--       through every recurrence of it). Nothing in this script changed - the
--       tool list is shared with the General Helper, so the button appears in
--       both. The tab now lists five buttons rather than four.
--   v1.18
--     - New General > Other tools sub-tab: buttons that open the other scripts
--       in this set - General Helper and Music Theory Helper, plus the
--       standalone Venue Preview and Pitch Tuner windows. Each opens in its own
--       window, independently of this one. The tool you are already in is never
--       listed, so this tab shows four buttons rather than five. A tool that is
--       not installed beside this script is greyed out with a note saying so,
--       instead of failing on click; put the .lua entry points back in one
--       folder and it re-enables on its own, no restart.
--       Opening a tool for the first time also registers it in REAPER's Action
--       list, which is what makes it bindable to a key or a toolbar button. It
--       is never un-registered afterwards - removing the action would delete
--       your own registration of that script along with any shortcut bound to
--       it, and re-adding it later produces a different command ID, so the
--       binding could not be restored. Clicking a tool that is already open
--       says so rather than raising REAPER's "ReaScript task control" dialog.
--       New shared lib/reaper_script_links.lua, so this tab and the General
--       Helper's copy of it (its v0.9.48) are drawn from one registry rather
--       than two that could drift. Covered by a new Script Links test set,
--       which checks the registry against the entry points actually present in
--       the install folder - both directions, so a renamed script fails a test
--       instead of shipping a dead button, and a newly added tool fails until
--       it is listed.
--   v1.17
--     - The Tuner tab is now also available as a standalone script,
--       rock_band_pitch_tuner_vkr.lua, so the live readout can stay visible in
--       its own window while you work in another tab or in the MIDI editor.
--       That window adds its own audio source track selector and Refresh
--       tracks button, and never stops on tab navigation (it has no tabs); the
--       60-second idle auto-stop still applies. It reads the same per-project
--       settings but never writes them - saving stays in the General tab. The
--       tab is unchanged; both load the same module files.
--     - Fixed: closing either window with the tuner running left its audio
--       accessor open, holding the source audio file until REAPER exited.
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
    _dir  .. 'lib/reaper_helper_common.lua',
    _dir  .. 'lib/reaper_helper_ui.lua',
    _dir  .. 'lib/reaper_script_links.lua',
    _dir  .. 'lib/reaper_spectrum.lua',
    _dir  .. 'lib/reaper_harmony_detect.lua',
    _dir  .. 'lib/reaper_key_detect.lua',
    _dir  .. 'lib/reaper_key_profiles.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'tips.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'pipeline.lua',
    _mdir .. 'autotune.lua',
    _mdir .. 'tuner.lua',
    _mdir .. 'actions.lua',
    _mdir .. 'actions_lyrics.lua',
    _mdir .. 'actions_phrases.lua',
    _mdir .. 'actions_validation.lua',
    _mdir .. 'actions_harmonies.lua',
    _mdir .. 'actions_slides.lua',
    _mdir .. 'actions_snap_key.lua',
    _mdir .. 'ui_common.lua',
    _mdir .. 'ui_tuner.lua',
    _mdir .. 'ui_slides.lua',
    _mdir .. 'ui_harmonies.lua',
    _mdir .. 'ui_pitch.lua',
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
dofile(_dir  .. 'lib/reaper_helper_common.lua')
dofile(_dir  .. 'lib/reaper_helper_ui.lua')
dofile(_dir  .. 'lib/reaper_script_links.lua')
dofile(_dir  .. 'lib/reaper_spectrum.lua')         -- spectrum for the Harmony readout
dofile(_dir  .. 'lib/reaper_harmony_detect.lua')   -- Pitch > Tuner Harmony readout
dofile(_dir  .. 'lib/reaper_key_detect.lua')       -- ... its key snap "From charted lead"
dofile(_dir  .. 'lib/reaper_key_profiles.lua')

-- Window title with this script's own @version, read from the header above.
-- ui.lua passes it to ImGui_Begin; the "###" id inside keeps saved window
-- geometry across version bumps. See ScriptWindowTitle.
WINDOW_TITLE = ScriptWindowTitle('Rock Band Vocal Helper', _script)

dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'tips.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'pipeline.lua')
dofile(_mdir .. 'autotune.lua')
dofile(_mdir .. 'tuner.lua')
dofile(_mdir .. 'actions.lua')
dofile(_mdir .. 'actions_lyrics.lua')
dofile(_mdir .. 'actions_phrases.lua')
dofile(_mdir .. 'actions_validation.lua')
dofile(_mdir .. 'actions_harmonies.lua')
dofile(_mdir .. 'actions_slides.lua')
dofile(_mdir .. 'actions_snap_key.lua')
dofile(_mdir .. 'ui_common.lua')
dofile(_mdir .. 'ui_tuner.lua')
dofile(_mdir .. 'ui_slides.lua')
dofile(_mdir .. 'ui_harmonies.lua')
dofile(_mdir .. 'ui_pitch.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTracks()
AutoDetectLyricsFile()
