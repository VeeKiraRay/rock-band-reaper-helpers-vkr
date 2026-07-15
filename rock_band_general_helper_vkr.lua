-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.12
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
--   v0.9.12
--     - Internal housekeeping, no behavior changes. ui_venue.lua split:
--       Section gen and Manual gen sub-tabs moved to their own files
--       (ui_venue_section_gen.lua, ui_venue_manual.lua); the shared camera
--       pacing / keyframe align widgets became globals. Deduplicated
--       shared logic (track+MIDI-take lookup, text-event delete loops,
--       ticks-per-QN, camera-pacing resolution, instrument letter names)
--       and removed dead code (unused preview track_end computation and a
--       leftover tooltip).
--   v0.9.11
--     - Unified throttling for continuous MIDI reads in the Venue tab UI
--       (new shared MakeProjectPoll helper: re-read only when the project
--       changed, subject to a minimum interval, with a 5 s fallback).
--       Events sub-tab no longer re-scans the EVENTS track every frame -
--       it polls like the Active players row (1 s + project-change gate)
--       and refreshes immediately after its own Add/bookends/Clear buttons.
--       Players row: during playback the per-playhead dot lookup now
--       updates ~2x/s instead of every frame (stopped-cursor moves still
--       react instantly). Preview: the per-frame muted-instruments read
--       now rides along with the existing event-cache refresh.
--   v0.9.10
--     - Venue > Events: with "Use letter suffix" on, Add now only inserts
--       lettered forms ([prc_verse_1a] from the very first part - never the
--       unlettered [prc_verse_1]), so lettered parts always merge cleanly in
--       Section gen. Plain and lettered forms of one event must not be
--       mixed: adding either is refused while the other exists. Events with
--       no lettered variants (e.g. [prc_bre], entry cues) insert the plain
--       form regardless of the checkbox.
--     - Venue > Events: refusal reasons no longer print next to the row
--       (they took too much horizontal space). The indicator shows a short
--       "-> (blocked)" - hover it for the reason - and a refused Add reports
--       the reason in the result section.
--   v0.9.9
--     - Venue > Events: insert validation. Adds refuse duplicates (with the
--       existing event's location), bare and numbered variants of the same
--       event may not co-exist, numbers/letters must be used in sequence and
--       placed in timeline order (letter gaps are re-offered), and no two
--       text events may share a position - crowd events are exempt and may
--       stack anywhere. The row indicator shows the exact event the Add
--       will insert, or why it would be refused, live at the playhead.
--     - Venue > Events: new quick actions. "Insert bookends" places the
--       minimal per-song event set ([prc_intro] + [crowd_normal] at m1,
--       [music_start] at m3, [prc_outro]/[music_end]/[end] at E-5/E-2/E
--       where E is the last full measure; skipped for items under 7
--       measures), removing prior instances first. "Clear all" removes
--       every text event from the EVENTS track (track name kept).
--     - Venue > Events: "Use letter suffix" is now on by default.
--     - Venue tab: sub-tab description lines use the default text color;
--       Manual gen insert status now names its target track (VENUE).
--   v0.9.8
--     - Venue tab: new Events sub-tab. Inserts EVENTS-track text events at
--       the playhead - [prc_*] section markers grouped by category (intro,
--       structure, solo, break, tempo/energy, interlude, outro, misc,
--       generic a-k), crowd events, and global markers ([music_start],
--       [music_end], [end], [coda]). Each section row has a number stepper
--       (bare or _1.._9) and an opt-in automatic letter suffix mode that
--       reads the EVENTS track and appends the next free letter
--       ([prc_verse_1] -> [prc_verse_1a] -> [prc_verse_1b]), capped to the
--       valid RB3 event vocabulary. A read-only indicator shows the exact
--       event the Add button will insert.
--   v0.9.7
--     - Venue tab: new "Active players" row shown under every sub-tab. A
--       colored dot per instrument shows its state at the playhead - active
--       (green), idle (blue), track muted or missing (red), or no
--       play-state events (orange, treated as always in [play] state) -
--       using the same mute/play-state logic as venue generation. Hover
--       for details.
--       Also shown in the standalone Venue Preview window.
--   v0.9.6
--     - Venue > Preview is now also available as a standalone script,
--       rock_band_preview_vkr.lua, so the preview can sit in its own window
--       next to the generation tabs. The sub-tab is unchanged; both load the
--       same module files.
--   v0.9.5
--     - Venue > Analysis: new "Generate sing along" action. Derives VENUE
--       sing-along notes (pitch 87 guitarist from HARM2, pitch 85 bassist
--       from HARM3) from each harmony track's vocal phrases, merging phrases
--       less than a measure apart into one continuous note. Clears/replaces
--       only the pitch of each unmuted-and-present source track.
--   v0.9.4
--     - Venue tab: new Keyframes sub-tab. Bulk-regenerates [first]/[next]
--       keyframes for every manual lighting event already on the VENUE track
--       (from that lighting event to the next lighting event of any kind),
--       using the shared Keyframe align/subdivision settings and its own
--       Keyframe rate. Only keyframe events are cleared/replaced; camera,
--       lighting, postproc, and bonus FX are untouched. Respects time
--       selection; otherwise processes the whole song.
--   v0.9.3
--     - Venue camera generation (Themes gen and Section gen tabs) now avoids
--       placing the same camera/companion event(s) back-to-back: the full set
--       of event(s) placed at one generated spot (a primary shot plus its
--       companion, if any) is banned for the very next spot only, then clears.
--       The ban chains continuously from the forced tick-0 shot through the
--       music-start anchor pick into the regular per-tick generation loop.
--   v0.9.2
--     - Venue Themes gen: song start now gets a forced, deterministic trio
--       ([coop_all_far] / [lighting (intro)] / [ProFilm_a.pp]) at tick 0
--       instead of a random camera pick, regardless of theme state.
--     - The first generated camera cut is now anchored to the song's actual
--       musical start - an explicit [music_start] EVENTS marker if present,
--       else whichever of measure 3/4 is closer to the 3-second mark - rather
--       than a fixed measure 3.
--     - A theme's first [prc_*] section (e.g. [prc_intro]) placed right at
--       tick 0 is now treated as starting at that same music-start anchor for
--       lighting/postproc/dircut/bonusfx placement, instead of at tick 0.
--     - Fix: the song-start/music-start bookend camera picks (Themes gen and
--       Section gen tabs) now emit the keys/guitar/bass swap companion event
--       when applicable, matching the regular per-tick camera generation loop.
--   v0.9.1
--     - Difficulty validation: gap/spacing/length rules now measured in quarter
--       notes via the tempo map (accurate with fluctuating BPM) with a 5% grace
--       for hand-placed notes.
--   v0.9
--     - Added Drums, Keys, Guitar, Difficulty, Tab Input, MIDI tabs.
--       Refactored into per-feature action files (actions_drums, actions_keys,
--       actions_guitar, actions_midi_align, actions_midi_replace,
--       actions_difficulty, actions_difficulty_5k).
--     - General tab: song fade out action.
--   v0.2
--     - Refactored into multiple module files loaded via dofile.
--       Shares lib/ (ImGui helpers, DSP, MIDI) with rock_band_vocal_helper_vkr.

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
