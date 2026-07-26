-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.30
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - audio alignment, count-in positioning, song fade out, settings
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
--   v0.9.29
--     - Venue > Keyframe align: instrument-aware modes (Guitar/Bass/Keys
--       notes, Drum kicks/snare) gain a third Subdivision option, "Every
--       quarter beat" (16th-note grid, max 16 [next] per measure in 4/4),
--       alongside the existing "Every beat" and "Every half beat". Added
--       to all four places the Subdivision radio row appears (Section
--       gen, Manual gen, and the Keyframes sub-tab's own row, plus the
--       shared RenderKeyframeAlignCombo). New shared KeyframeSubdivQN in
--       venue_lighting.lua replaces the inlined half-beat ternary in
--       GenerateKeyframesForSpan/ProcessThemeSection and
--       GenerateManualKeyframes (actions_venue_manual.lua).
--     - Fix: every keyframe insertion site (Keyframes sub-tab regenerate,
--       Manual gen, Section gen, and the full-song Generate) re-snapped
--       every [first]/[next] event to the nearest half-beat after
--       GenerateKeyframesForSpan/GenerateThemedSectionEvents had already
--       placed it - harmless while half-beat was the finest grid, but with
--       quarter-beat now available it silently collapsed 1/4 and 3/4-beat
--       positions onto the nearest half-beat or beat, producing duplicate/
--       merged events and gaps where a real note existed. Keyframe events
--       are now inserted at their already-computed position with no
--       further snapping; camera/lighting/postproc/bonusfx insertion is
--       unaffected. Also incidentally corrects "Section start" mode
--       (align 0), which was being pulled onto the half-beat grid instead
--       of landing exactly on the section marker as documented.
--   v0.9.28
--     - Difficulty > Keys: the "Reduce using Pro Keys (same tier)" reduction
--       (v0.9.27) now also matches sustain length, not just which events
--       survive. A kept event's length is set to the matching Pro Keys
--       event's length (re-anchored at the Keys event's own start), instead
--       of keeping whatever length it had on the copied source tier - Pro
--       Keys is the master chart both are reduced from, and sustain-gap
--       rules require the two charts to agree on note length as well as
--       onset. No change when the checkbox is off or Pro Keys data is
--       unavailable (falls back to the source tier's own length, as
--       before). ReadProKeysEventQNs/HasNearbyQN in actions_difficulty_5k.lua
--       replaced by ReadProKeysEvents/FindNearbyPKEvent (event-based, so
--       length is available alongside timing).
--   v0.9.27
--     - Difficulty > Keys: new "Reduce using Pro Keys (same tier)" checkbox
--       above the Copy row, checked by default. When on, Copy to Hard/
--       Medium/Easy keeps only copied events that land on a note in the
--       matching-tier Pro Keys track (PART REAL_KEYS_H/M/E) - mirrors a
--       rhythm reduction already hand-charted on Pro Keys onto the Keys
--       copy (e.g. Expert has 12 notes, Pro Keys Hard was reduced to 8 -
--       Copy to Hard on Keys now keeps only the 8 matching slots), instead
--       of copying every event from the tier above unfiltered. Match
--       tolerance: 1/32 note in quarter-note space (tightened from an
--       initial 1/16 note, which left too many events kept at faster
--       tempos). Falls back to an unfiltered copy (with a status note
--       explaining why) when the matching Pro Keys track isn't selected,
--       missing, or empty - the button never refuses to run. New
--       persisted S.diff_5k_pk_reduce. Keys-only - Guitar/Bass, Drums,
--       and Pro Keys itself don't have this option.
--   v0.9.26
--     - Difficulty > Drums: "Kick/snare between Yellow/Blue" (Medium) is
--       disabled - as implemented it doesn't match the intended rule (too
--       strong). CheckDrumsYellowBlueInterleave is left defined but no
--       longer wired into RunDrumsChecks, to be revisited once the rule is
--       better understood.
--     - Fix: CompressChordOffsets (actions_difficulty_shared.lua, used by
--       Keys/Guitar-Bass's Copy to Hard/Medium/Easy) only shifted a chord
--       down when it had exactly 2 notes - a lone note above the target
--       tier's color ceiling (e.g. a single Orange note copied to Medium)
--       fell through to the drop branch instead of shifting down (e.g. to
--       Blue), silently losing the note instead of relocating it. Now
--       shifts whenever there are 1 or 2 notes and the shift keeps every
--       note >= offset 0.
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
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
