-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.53
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - audio alignment, count-in positioning, song fade out, settings,
--                  per-project authoring workflow checklist, buttons that open
--                  the other tools in this set
--     Tempo Map  - audio-driven tempo map generation from drum stems
--     Drums      - convert GM MIDI to Rock Band 5-lane drum notation
--     Keys       - hand split, Pro Keys conversion + animation, 5-Lane Keys conversion
--     Guitar     - convert raw MIDI to Expert Guitar gems, tab guide, validate
--     Difficulty - copy and validate Pro Keys + Keys + Guitar/Bass + Drums difficulty tiers
--     Tab Input  - guitar/keys/vocal tab entry guide
--     MIDI       - MIDI alignment, length sync, pattern replace
--     Venue      - list, validate, and generate VENUE and EVENTS track events
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.9.53
--     - Venue > Themes gen and Section gen no longer re-state a lighting or post
--       proc preset that is already running. A blend is authored by writing the
--       running preset a second time just before the change, so the game fades
--       into it - which means a section that happened to pick the preset already
--       playing was writing a blend nobody asked for, and the validator, the
--       Keyframes tab and Manual gen's Blend button all read it as deliberate.
--       If a section's theme pool offers alternatives it now picks one of those;
--       if the pool holds only the running preset the section keeps it and writes
--       nothing. Its keyframes are still generated either way, so a manual preset
--       keeps animating across the boundary. The report counts what was kept.
--       Manual gen is unchanged - ask it for a duplicate and you get one.
--     - Venue > Preview now understands blends. The second copy of a preset is an
--       anchor, not a preset of its own, so it is no longer shown as its own
--       event - before, the same preset filled two columns and every fade looked
--       like a hard cut. Each lighting and post proc card instead says how it
--       hands over: "blends into next", "blending now" while the playhead is
--       inside the fade, or "hard cut to next" (a valid choice, not an error).
--       Camera cards have no such line - a camera cut never fades.
--       Same change in the standalone Venue Preview window (its v0.4).
--   v0.9.52
--     - Venue > Actions > Validate: new "Validate camera stacks" button. Only
--       two of bass/guitar/keys fit on stage at once, so a song charting all
--       three can be played by three different bands, and stacked camera shots
--       are how you cover each. This replays the game's shot pick for every
--       lineup your project can produce and reports where that breaks down:
--       shots that win under no lineup (they need an instrument never on
--       stage, or a stacked sibling outranks them everywhere they fit), and
--       spots where a lineup has no valid camera shot so the game picks for
--       you.
--       Read-only, like the lighting validator beside it.
--     - It also catches two mistakes that break stacking outright: the same
--       shot written twice on one tick, and two shots a few ticks apart that
--       were meant to be stacked - the game reads those as two separate cuts,
--       so the second replaces the first before you ever see it.
--     - Letting the game fall back is a valid authoring choice, so those spots
--       are listed as "where the game decides", not as errors - the same way
--       the lighting validator treats a hard cut. Uncovered spots are reported
--       one line per spot rather than per lineup, and the report names which
--       lineups your project can actually produce, so a four-piece song does
--       not read as the check having found nothing to do.
--   v0.9.51
--     - Venue > Preview: when several camera shots are stacked on one tick, the
--       preview now shows the one the GAME would play. Authors stack shots so
--       at least one fits whatever band the song ends up with, and the game
--       ranks them - most specific wins, and a directed cut always beats a
--       normal shot. The preview used to just take the last one in MIDI order,
--       and if that one needed a missing instrument it took the first stacked
--       shot that fit, so a spot could show a shot the game would never pick.
--       Priority order is transcribed from the RBN2 Camera And Lights
--       documentation, including its exception that a single keys shot outranks
--       any duo shot. The Previous and Next columns resolve their own stacks
--       the same way - before, only Current considered alternatives at all.
--     - Venue > Preview: when nothing stacked at a spot fits the selected
--       Players combo, the red "No suitable event" card now comes with a note
--       on what the game does instead: it falls back to a generic full band
--       shot, and it converts a normal duo shot to a single shot of the
--       remaining member when it can. The preview deliberately keeps showing
--       the event you authored rather than drawing one of those substitutes -
--       each has several possible outcomes, and a sprite that is not on your
--       timeline would look like a preview bug.
--     - Same in the standalone Venue Preview window (its v0.3).
--   v0.9.50
--     - Fix: switching projects left the MIDI tab's Length sub-tab pointing at
--       the old project's tracks. Its Source track and Reference track fields
--       kept their positions, so the first Adjust notes or Resize all MIDI
--       after a switch could act on whatever track happened to sit at that
--       index in the new project. They now reset like every other track
--       selector already did. The Pattern sub-tab got the same fix in v0.9.49.
--     - MIDI > Pattern: the Set Search tooltip described something the button
--       has never done - that capturing a Search of a different length clears
--       the Replace pattern. Nothing is ever cleared; the two lengths are
--       checked when Replace All runs, which refuses and says so. The tooltip
--       now says that, so a Replace pattern that looks intact really is.
--     - Internal: removed a disabled-state flag from the Pattern sub-tab that
--       nothing has ever set, so eight of its greyed-out guards could never
--       fire. No visible change - the buttons that genuinely grey out (Replace
--       All and Fill Range without a pattern captured, the three navigation
--       buttons without a Search) are driven by their own conditions and are
--       untouched.
--   v0.9.49
--     - New standalone window: MIDI Pattern (rock_band_midi_pattern_vkr.lua),
--       the MIDI > Pattern sub-tab in a window of its own, so it can sit beside
--       the MIDI editor without the other eight tabs coming with it. Same Set
--       Search / Set Replace / Replace All / Fill Range / Go Prev / Go Next /
--       List Search, the same difficulty pitch-range filter, and the same
--       status and result panel including an Undo button - Replace All and
--       Fill Range write MIDI, so undo matters here. It carries no settings of
--       its own because the Pattern tab has never had any to save; a project
--       switch clears the captured patterns rather than leaving them pointing
--       at the previous project's take. It appears in the General > Other
--       tools sub-tab of both this script and the Vocal Helper, which now list
--       five buttons.
--     - The sub-tab itself is unchanged and still lives in the MIDI tab. Its
--       drawing code moved to a new ui_midi_pattern.lua so both windows draw
--       one implementation rather than two that could drift, and the pieces
--       both entry points need - the track dropdown and the bottom status /
--       result panel - moved to a new ui_common.lua, since ui.lua cannot be
--       loaded by a standalone (its last line opens the full helper window).
--       Same split the Vocal Helper made for its standalone Pitch Tuner.
--     - Fix: switching projects left the captured Search and Replace patterns
--       in place. They are tick offsets into a specific take, labelled with the
--       measure numbers of the project they came from, so a Replace All after
--       a project switch could act on the wrong material. They are now cleared
--       along with the source track, as every other track selector already was.
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
    _dir  .. 'lib/reaper_guitar_theory.lua',
    _dir  .. 'lib/reaper_script_links.lua',
    -- Difficulty suggester. reaper_difficulty_score.lua must precede its vocals
    -- companion (which appends to SCORE_FACTOR_KEYS), and both precede the models.
    _dir  .. 'lib/reaper_difficulty_score.lua',
    _dir  .. 'lib/reaper_difficulty_score_vocals.lua',
    _dir  .. 'lib/reaper_difficulty_tiers.lua',
    _dir  .. 'lib/reaper_difficulty_predict.lua',
    _dir  .. 'lib/reaper_difficulty_models.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'venue_camera_priority.lua',
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
    _mdir .. 'actions_venue_subtracks.lua',
    _mdir .. 'actions_venue_validate.lua',
    _mdir .. 'actions_venue_validate_camera.lua',
    _mdir .. 'workflow.lua',
    _mdir .. 'actions_workflow.lua',
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
    _mdir .. 'actions_midi_length.lua',
    _mdir .. 'actions_difficulty_shared.lua',
    _mdir .. 'actions_difficulty.lua',
    _mdir .. 'actions_difficulty_5k.lua',
    _mdir .. 'actions_difficulty_gtrbass.lua',
    _mdir .. 'actions_difficulty_drums.lua',
    _mdir .. 'difficulty_read.lua',
    _mdir .. 'difficulty_explain.lua',
    _mdir .. 'difficulty_suggester.lua',
    _mdir .. 'ui_common.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_difficulty.lua',
    _mdir .. 'ui_midi_pattern.lua',
    _mdir .. 'ui_midi.lua',
    _mdir .. 'ui_venue.lua',
    _mdir .. 'ui_venue_section_gen.lua',
    _mdir .. 'ui_venue_manual.lua',
    _mdir .. 'ui_venue_events.lua',
    _mdir .. 'ui_venue_preview.lua',
    _mdir .. 'ui_venue_keyframes.lua',
    _mdir .. 'ui_venue_players.lua',
    _mdir .. 'ui_workflow.lua',
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
dofile(_dir  .. 'lib/reaper_guitar_theory.lua')
dofile(_dir  .. 'lib/reaper_script_links.lua')
dofile(_dir  .. 'lib/reaper_difficulty_score.lua')
dofile(_dir  .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_dir  .. 'lib/reaper_difficulty_tiers.lua')
dofile(_dir  .. 'lib/reaper_difficulty_predict.lua')
dofile(_dir  .. 'lib/reaper_difficulty_models.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'venue.lua')
dofile(_mdir .. 'venue_awareness.lua')
dofile(_mdir .. 'venue_camera_priority.lua')
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
dofile(_mdir .. 'actions_venue_subtracks.lua')
dofile(_mdir .. 'actions_venue_validate.lua')
dofile(_mdir .. 'actions_venue_validate_camera.lua')
dofile(_mdir .. 'workflow.lua')
dofile(_mdir .. 'actions_workflow.lua')
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
dofile(_mdir .. 'actions_midi_length.lua')
dofile(_mdir .. 'actions_difficulty_shared.lua')
dofile(_mdir .. 'actions_difficulty.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')
dofile(_mdir .. 'actions_difficulty_drums.lua')
dofile(_mdir .. 'difficulty_read.lua')
dofile(_mdir .. 'difficulty_explain.lua')
dofile(_mdir .. 'difficulty_suggester.lua')
dofile(_mdir .. 'ui_common.lua')
dofile(_mdir .. 'ui_keys.lua')
dofile(_mdir .. 'ui_difficulty.lua')
dofile(_mdir .. 'ui_midi_pattern.lua')
dofile(_mdir .. 'ui_midi.lua')
dofile(_mdir .. 'ui_venue.lua')
dofile(_mdir .. 'ui_venue_section_gen.lua')
dofile(_mdir .. 'ui_venue_manual.lua')
dofile(_mdir .. 'ui_venue_events.lua')
dofile(_mdir .. 'ui_venue_preview.lua')
dofile(_mdir .. 'ui_venue_keyframes.lua')
dofile(_mdir .. 'ui_venue_players.lua')
dofile(_mdir .. 'ui_workflow.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
