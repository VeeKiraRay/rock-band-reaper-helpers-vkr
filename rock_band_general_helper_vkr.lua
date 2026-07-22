-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.24
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
--   v0.9.24
--     - Result panel (bottom of every tab): long lines now wrap to the
--       window's current width (ImGui_PushTextWrapPos(ctx, 0)) instead of
--       overflowing and requiring the window to be stretched to read them.
--   v0.9.23
--     - Difficulty tab: replaced the read-only "Suggest Hard/Medium/Easy"
--       preview (all four sub-tabs) with "Copy to Hard/Medium/Easy", which
--       actually copies notes from the immediately higher tier onto the
--       target tier's own track/range - a real starting point to hand-edit
--       down instead of just a report of what would need to change.
--       Two safeguards: if the source tier has no notes, it early-exits and
--       reports that, writing nothing; if the target tier already has
--       notes, a confirmation popup (the first modal in this codebase) asks
--       before clearing and overwriting them.
--       Keys and Guitar/Bass narrow their gem count at Medium/Easy by
--       convention (all 5 colors exist at every tier internally) - copying
--       down now compresses a chord using a color above the target's
--       ceiling instead of leaving it out-of-range or dropping it outright:
--       a single note or 2-note chord shifts down as a whole (e.g. Hard's
--       Orange+Blue -> Medium's Blue+Yellow), otherwise (3+ note chords, or
--       a shift that would go negative) the offending note is simply
--       dropped. New shared CompressChordOffsets in
--       actions_difficulty_shared.lua. Pro Keys copies verbatim (gems and
--       lane-shift markers alike) between tracks, since its range doesn't
--       shift between tiers.
--       SuggestProKeysDiff/SuggestKeys5Diff/SuggestGtrBassDiff/
--       SuggestDrumsDiff and their tooltips are removed, not just hidden.
--   v0.9.22
--     - Difficulty > Drums: layered a batch of concrete external RBN
--       authoring rules on top of the existing base rules, cascading down
--       from a higher difficulty to an easier one that doesn't define its
--       own override:
--       Cascades Hard->Medium->Easy: no kick inside a drum-fill marker
--       (120-124); roll/trill markers start on an 8th/quarter-note grid
--       line; a roll covers an even hit count; roll/fill density (no
--       16th-rate rolls >=140 BPM on Hard, never faster than 8th-rate on
--       Medium, quarter-rate required >=120 BPM on Easy else inherits
--       Medium's cap); general timekeeping density - runs of constant 8th
--       notes flagged >=170 BPM (Hard) / >=140 BPM (Medium, own; Easy
--       inherits); a Green+Yellow/Blue double crash needs a quarter-note
--       gap before it or should reduce to a single Green.
--       Cascades Medium->Easy: kicks on the quarter-grid only above 100
--       BPM; max 1 kick per measure at >=170 BPM. Medium's earlier
--       kick+snare+cymbal-specific "3-limb hit" rule is replaced by a
--       blanket max-2-simultaneous-notes rule (also cascades to Easy).
--       Medium-only: a kick/snare falling between two Yellow/Blue hits;
--       on-beat crash+kick is fine, off-beat/syncopated is not.
--       Hard-only: Hard should have fewer kicks than Expert; the Hard-tier
--       [mix N drums<config>] event should use the un-flipped/base config,
--       not the disco variant.
--       New "Authoring hints" block (non-pass/fail, always shown on H/M/E)
--       covers the rules too qualitative to check deterministically (e.g.
--       "try removing kicks from adjacent notes", "favor crash over kick").
--       Fix: offset-dependent checks (identifying which pitch is the kick/
--       snare/cymbal) used the simulated target tier's range even during
--       Suggest, where the notes being checked are always Expert's raw
--       pitches - so no offset-dependent check ever fired during Suggest.
--       Now resolves against Expert's range whenever validating in Suggest
--       mode.
--   v0.9.21
--     - Difficulty tab: added Guitar/Bass and Drums sub-tabs, matching the
--       existing Pro Keys/Keys suggest-and-validate workflow. "5-Lane Keys"
--       sub-tab renamed to "Keys".
--       Guitar/Bass share one sub-tab (instrument radio switch, since the
--       RBN authoring rules are identical between the two) validating
--       PART GUITAR/PART BASS: chord count/shape (illegal Green+Orange
--       combos, per-difficulty span limits), note length, overlap, sustain
--       gaps, force-HOPO markers (disallowed on Medium/Easy), and
--       trill/tremolo marker velocity (Hard eligibility).
--       Drums gets its own sub-tab validating PART DRUMS: no 3-limb hits on
--       Medium (kick+snare+cymbal/tom together), no gems paired with kick
--       on Easy, roll/trill marker velocity on Hard, and an informational
--       (non-pass/fail) scan of [mix N drums...] disco-flip events.
--       New track fields (diff_gtr_idx, diff_bass_idx, diff_drums_idx) are
--       independent of the Guitar/Drums conversion tabs' own target-track
--       fields and auto-detected by name, same as the existing Pro
--       Keys/Keys difficulty tracks.
--       Every Validate action (all four sub-tabs) now also runs a shared
--       cross-difficulty sanity check against the immediately higher tier
--       (Hard vs Expert, Medium vs Hard, Easy vs Medium): flags an unedited
--       copy (identical timing/shape - no reduction actually authored), and
--       reports individual note counts, requiring the lower tier to have
--       fewer notes than the one above it (e.g. "Expert has 500 notes and
--       Hard has 450 notes: OK"). Both count toward the report's issue
--       total. Not run for Expert (nothing above it) or for Suggest (which
--       only ever reads Expert - there's no second authored track to
--       compare against). Shared logic lives in the new
--       actions_difficulty_shared.lua, reused by all four difficulty
--       modules. Also fixes a latent crash in Drums > Validate Hard/All
--       (roll/trill velocity issues were concatenated as a table instead of
--       formatted into the report).
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
