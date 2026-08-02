-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.40
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
--   v0.9.40
--     - MIDI tab > Pattern: fixed "Go Prev" doing nothing useful when the edit
--       cursor sat inside a match. It treated the current match's own start as
--       a valid "previous" target, so pressing it jumped backwards to the start
--       of the instance you were already in rather than reaching the previous
--       one - and from mid-pattern it took two presses to actually move. Go
--       Prev now steps out of the instance under the cursor first. Go Next was
--       never affected. Caught by the MIDI fixture test suite.
--   v0.9.39
--     - MIDI tab > Pattern: new "Go Prev" / "Go Next" buttons move the edit
--       cursor between Search-pattern matches; "List Search" reports every
--       match with its measure/time location (read-only). All three share
--       the Replace All match-scanning walk (new local ScanPatternMatches,
--       actions_midi_replace.lua). Fixed a real bug along the way: the
--       Pattern tab's measure-range label and a few MIDI-tab status
--       messages used UTF-8 en-dash/em-dash byte escapes that ReaImGui's
--       font can't rasterize, rendering as "?" - replaced with plain
--       ASCII dashes in actions_midi_replace.lua, actions_midi_align.lua,
--       and ui_midi.lua.
--     - MIDI tab > Length: new "Midi note" section (above the existing
--       reference-track resize section, now labeled "Midi track") bulk-
--       adjusts note lengths on one track's difficulty tier. "Non-sustains"
--       unifies every note SHORTER than 1/4 note to a selected standard
--       size (1/8 to 1/128, default 1/32) - existing sustains are left
--       untouched; "Only sustains" widens or narrows each sustain's
--       (>= 1/4 note) gap to the next note to an exact 32nd-note amount,
--       searching up to 16x32nd notes ahead - a sustain with nothing that
--       close is left unchanged, and one that would shrink below a
--       1/32-note floor is clamped there instead. All math works in raw
--       take-PPQ ticks (never seconds or QN floats) so results land
--       exactly on REAPER's own note-length grid. New
--       actions_midi_length.lua (AdjustMidiNoteLengths).
--   v0.9.38
--     - Fixed a combo-wrap collision: when a passage has more distinct
--       chord shapes in one lane-spread group than that group has combo
--       alternatives (e.g. 4 different power chords but only 3: G+Y/R+B/
--       Y+O), a same-combo collision was possible between two shapes that
--       are actually back-to-back in the passage (modulo-wrapping could
--       collide the lowest- and highest-pitched shapes; a simpler
--       pitch-rank-only fix could still collide genuinely adjacent
--       chords). BuildShapeGemMap now assigns the first (lowest-pitched)
--       shapes in a group a unique combo each, then gives every
--       additional (higher-pitched) shape whichever already-claimed combo
--       minimizes conflicts against shapes it's actually adjacent to
--       ANYWHERE in the passage - built from a real adjacency table over
--       the event sequence, with a bounded refinement pass - so two
--       genuinely back-to-back chords only ever end up looking identical
--       when it's truly unavoidable (more distinct shapes than combos),
--       never just because they happen to be pitch-neighbors. Reused
--       shapes get "(*Wrap)" appended to their reason string in both the
--       Guitar tab converter's preview and Tab Input's guide report; the
--       shape that legitimately claimed the combo first is never flagged.
--       New AssignByConflict helper (actions_guitar.lua); BuildShapeGemMap
--       gained a third return value (shared: key->true). Safety cap: past
--       200 distinct shapes in one group (MAX_CONFLICT_SHAPES), skips the
--       search and falls back to plain clamp-to-last - real songs stay far
--       below this; it only guards against a mis-selected source track
--       (e.g. a drum track) producing a huge, near-random shape vocabulary
--       that would otherwise make the search's worst case visibly freeze
--       REAPER's single-threaded UI.
--   v0.9.37
--     - Tab Input's Guitar/Bass guide: removed the "Notes are in play
--       order" checkbox and palette mode. Palette mode flattened every
--       chord into independent single-note gem events (no chord grouping
--       at all), which doesn't reflect real RB charting - the guide now
--       always uses the chord-shape-aware assignment the checked state
--       already provided, matching how the real Guitar tab converter
--       (ConvertGuitar) has always behaved (it never had a palette-mode
--       equivalent). S.mc_gtr_tab_ordered and its ExtState key (mcgtor)
--       are gone.
--   v0.9.36
--     - Guitar tab converter and Tab Input's Guitar/Bass guide are now
--       chord-quality-aware: a real-guitar interval like a power chord's
--       perfect fifth always gets a matching lane spread (1-3: GY/RB/YO)
--       instead of whatever pitch-rank pool-cycling happened to land on,
--       and the preview/guide report annotates recognized shapes with
--       their chord name (e.g. "[Power chord]"). This applies by PITCH
--       CLASS, not physical note count: a shape played on 3 strings but
--       harmonically just root+5th+octave (e.g. "x x x 7 7 5") is
--       recognized as a power chord and correctly collapses to a 2-gem
--       1-3 combo, matching real RB charts, instead of being treated as
--       an unrelated 3-note chord. Genuine 3-distinct-pitch-class shapes
--       (real triads etc.) are unaffected - the library has no narrower
--       mapping for those, though the report now names them too when
--       recognized (e.g. "[Major triad]"). Consults
--       lib/reaper_guitar_theory.lua (already used by the Music Theory
--       Helper) via new shared BuildShapeGemMap (actions_guitar.lua),
--       which replaces the near-identical shape->gem map building
--       previously duplicated in AssignGems and AssignGemsForGuide
--       (actions_guitar_guide.lua). actions_guitar_guide.lua's local
--       TAB_OPEN tuning table is gone, now reads GUITAR_TAB_OPEN from the
--       shared lib.
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
    _mdir .. 'actions_midi_length.lua',
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
dofile(_dir  .. 'lib/reaper_guitar_theory.lua')
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
dofile(_mdir .. 'actions_midi_length.lua')
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
