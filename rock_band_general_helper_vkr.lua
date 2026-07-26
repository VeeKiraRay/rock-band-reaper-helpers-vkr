-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.34
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - audio alignment, count-in positioning, song fade out, settings,
--                  per-project authoring workflow checklist
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
--   v0.9.34
--     - Workflow sub-tab: new "Show only unfinished" checkbox hides checked
--       items (and any section whose items are all checked) so a long
--       checklist doesn't force scrolling past finished work; a "done /
--       total completed - pct%" progress line now sits below the
--       checkboxes, always counted over the whole template regardless of
--       the filter. Simplified how checked history is pruned: switching
--       templates now immediately drops history for items not in the
--       newly-selected file (SelectWorkflowFile), instead of only pruning
--       once the total exceeded a 100-item cap compared against every
--       loaded template - simpler, and matches the actual use case of
--       bouncing between a couple of templates rather than keeping
--       long-lived cross-template history. WORKFLOW_MAX_ITEMS is gone;
--       PurgeStaleWorkflowEntries is replaced by PruneToWorkflowEntries
--       (scoped to one file's entries instead of every loaded one).
--   v0.9.33
--     - Venue subtab intro descriptions (Keyframes, Themes gen, Events,
--       Manual gen, Section gen) now wrap to a new line instead of
--       clipping when the window is narrower than the text - same
--       treatment the result panel already got in v0.9.24, applied to
--       these five r.ImGui_Text calls (now r.ImGui_TextWrapped).
--   v0.9.32
--     - General tab: new "Workflow" sub-tab - a per-project authoring
--       checklist sourced from a user-editable .txt template
--       (resources/workflow/, one starter template "Default" included -
--       selected automatically on first use if present, else the first
--       template alphabetically). [Section] lines group items under a
--       header; plain lines are checkable steps; a trailing {tooltip}
--       (same line, or its own line right after) attaches a hover tooltip -
--       an item with more than one tooltip source drops the tooltip rather
--       than guessing which wins. Checking an item stamps the time and
--       autosaves immediately under its own workflow_v1 project key
--       (independent of this tab's own Save/Load); unchecking clears the
--       timestamp. A "Show completion timestamp" checkbox (off by default,
--       persisted) controls whether "Completed on dd.MM.yyyy at hh:mm" is
--       displayed under checked items - the timestamp is always recorded
--       regardless of the checkbox, only its display is optional. Checked
--       state is keyed by (section, item label), not label alone, so
--       identical item text under two different section headers (e.g.
--       "Guitar" under both "Instruments Expert" and "Difficulty
--       reductions") tracks separately. Switching templates carries over
--       any item whose section+label matches exactly; anything else starts
--       unchecked. Parse-time warnings (shown above the checklist) flag
--       duplicate (section,label) pairs and unbalanced [ ] / { } bracket
--       counts in a template file. Saved state auto-purges entries no
--       longer present in any loaded template once the total exceeds 100
--       items. New workflow.lua (parser) and actions_workflow.lua
--       (persistence) modules.
--   v0.9.31
--     - Venue > Actions: new "Sub VENUE tracks" group splits VENUE's events
--       across 6 category tracks - "VENUE normal camera", "VENUE directed
--       camera", "VENUE lighting", "VENUE keyevents", "VENUE post proc",
--       "VENUE special" - for easier authoring once a song has accumulated
--       a lot of keyframes, then merges them back. "Copy all to subtracks"
--       creates (if missing, muted by default - an editing-only split that
--       shouldn't reach the final export) and re-syncs all 6; new tracks
--       inherit VENUE's custom MIDI note names and get their take named
--       after the track so open MIDI editor tabs are identifiable instead
--       of all showing as "MIDI take". VENUE's own MIDI notes (e.g. the
--       sing-cue notes at pitches 85-87) travel with "VENUE special"
--       alongside its text events. "Copy all to main track" early-exits
--       with a status message if no subtracks exist yet; otherwise clears
--       VENUE and replaces it with their combined contents, notes included
--       (confirmation popup first, mirrors the Difficulty tab's overwrite
--       modal). A Subtrack dropdown plus Copy to/Copy from work on one
--       category at a time
--       (Copy to auto-creates the subtrack, Copy from does not; for
--       Special both directions also carry VENUE's notes). New
--       CategorizeVenueEvent in new actions_venue_subtracks.lua is the
--       first unified 6-way VENUE event classifier - also now backs
--       RemoveVenueEventsByType (actions_venue_manual.lua), replacing its
--       three duplicated pattern checks with one shared classification.
--   v0.9.30
--     - Venue > Themes gen: song end is now resolved from the EVENTS
--       track's [end] marker, not the VENUE MIDI item's own length -
--       nothing is generated at or after it even if the item runs
--       longer (harmless in-game; the result panel suggests trimming
--       the item to [end] when it runs meaningfully past it, purely
--       cosmetic, never required). Falls back to the item's length,
--       with a "Didn't find [end] event, used MIDI length as end."
--       note, when no [end] marker is present. When [music_end] sits
--       within 10 measures of [end], the outro [lighting
--       (blackout_spot)] bookend and the last scripted coop camera
--       cut both target it instead of the literal end - [end]
--       triggers the game's own forced camera cut, so landing our
--       own cut right beside it doubled up as a jump cut. New shared
--       FindEventTime in venue_awareness.lua generalizes the
--       existing [music_start] lookup; FindMusicStartTime is now a
--       thin wrapper over it.
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
    _mdir .. 'actions_difficulty_shared.lua',
    _mdir .. 'actions_difficulty.lua',
    _mdir .. 'actions_difficulty_5k.lua',
    _mdir .. 'actions_difficulty_gtrbass.lua',
    _mdir .. 'actions_difficulty_drums.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_difficulty.lua',
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
dofile(_mdir .. 'actions_venue_subtracks.lua')
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
dofile(_mdir .. 'actions_difficulty_shared.lua')
dofile(_mdir .. 'actions_difficulty.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')
dofile(_mdir .. 'actions_difficulty_drums.lua')
dofile(_mdir .. 'ui_keys.lua')
dofile(_mdir .. 'ui_difficulty.lua')
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
