-- @description Rock Band Vocal Helper
-- @author VeeKiraRay
-- @version 1.16
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
--   v1.16
--     - Harmonies: each destination's two dropdowns are now labelled Target
--       track and Copy style, aligned into the same column as Source and Key.
--     - Harmonies: new Copy style, "Preserve target pitches". It copies the
--       source's positions, lengths, splits and lyrics as usual but takes each
--       note's pitch from the note already on the destination track, so a
--       harmony part that was authored by hand can be re-synced after the lead's
--       timing changes without losing its pitches. Where a copied note overlaps
--       a destination note, that note's pitch is used; where it doesn't, the
--       nearest destination note within one measure donates its pitch; a note
--       split in two for a slide keeps the destination pitch on the first half
--       and carries the source's own interval onto the rest; and where nothing
--       is close enough, the source pitch is copied unchanged. The result panel
--       counts all four cases separately.
--   v1.15
--     Pitch detection overhaul. Every figure below is from the synthetic test
--     harness in dev/tests/dsp_algorithms.lua; see dev/PITCH_DETECTION_FINDINGS.md
--     for the measurements behind each change.
--     - The difference function now compares every candidate period over the
--       same fixed width, instead of a width that shrank as the period grew -
--       that shrinkage biased the search toward long periods, i.e. octave-down
--       errors. Over 420 cases, octave errors fall ~40% (27 to 16 with a full
--       harmonic series, 56 to 34 when the fundamental is weak). A short window
--       no longer silently narrows the frequency range the detector claims to
--       search, so Min frequency is now honoured exactly.
--     - Detections whose best match sits on the edge of the searched period
--       range are now rejected. These are cases where the true pitch most
--       likely lies outside the Min/Max frequency bounds and the search simply
--       ran out of room; they previously produced confident-looking wrong
--       pitches. Leave a little room above your highest note when setting Max
--       frequency - a note landing right on the bound can be rejected.
--     - Each note is now sampled at several points and the median taken,
--       instead of trusting one sample 30% in. A consonant or breath landing
--       on that instant used to decide the whole note: with a mid-note
--       consonant, correct detections go from 20% to 100%, and with vibrato
--       from 72% to 85%. New "Samples per note" setting (1 / 3 / 5, default 3);
--       when the first two agree the third is skipped, so most notes cost two
--       windows rather than three. Set it to 1 for the old behaviour.
--     - Audio is high-passed below Min frequency before detection. Rumble,
--       plosives and low-end bleed sit under the searched range but still
--       dominated the analysis, causing notes to silently fall back to the
--       Default pitch. Against 45-60 Hz contamination, correct detections go
--       from 122/162 to 159/162 at moderate level and 35/162 to 130/162 at
--       heavy level, with no loss on clean audio.
--     - New "Min confidence" setting (Pitch and Tuner tabs): detections report
--       how periodic they are, and readings below the threshold are treated as
--       no detection, so notes fall back to the Default pitch rather than
--       getting a wrong one. This rejects breath and unvoiced consonants
--       ("sss", "shh"), which pass a level gate but carry no pitch. Default
--       0.50 matches how earlier versions behaved. The Tuner readout now shows
--       the confidence percentage, amber below 75%.
--     - New "Min RMS level" setting (Pitch tab): notes whose audio is too quiet
--       fall back to the Default pitch instead of taking a pitch from bleed in
--       the gaps. Min confidence cannot do this - the periodicity measure
--       ignores level entirely, so quiet bleed scores just as confident as the
--       vocal itself.
--     - Detection now analyses at a reduced sample rate (24 kHz for typical
--       vocal settings), which is roughly 3x faster and was measured to give
--       identical pitches to full rate across the vocal range. A high Max
--       frequency keeps the rate up, so the Piano/keys preset is unaffected.
--     - Live tuner and pitch-slide detection share all of the above.
--   v1.14
--     - Lyrics tab: new "Create phrases" action writes phrase-marker
--       (pitch 105) notes, one per line in the lyrics file, bracketing that
--       line's sung notes with lead-in/tail spacing snapped to the grid and
--       to nearby beat/measure boundaries. Reuses Assign Lyrics' word<->note
--       positional indexing (whole take), and validates lyrics.txt against
--       the take's existing lyric text before writing anything - aborts
--       with no changes if they've drifted out of sync.
--   v1.13
--     - Result panel (bottom of every tab): long lines now wrap to the
--       window's current width (ImGui_PushTextWrapPos(ctx, 0)) instead of
--       overflowing and requiring the window to be stretched to read them.
--   v1.12
--     - Sliders and combo boxes now use a fixed pixel width
--       (SetNextItemWidth(ctx, 200), matching the general helper's
--       convention) instead of stretching to fill the window on resize.
--       Applied across General, Tuner, Pitch, Pitch slide, Harmonies, and
--       Validation tabs (WIP Note Placement tab intentionally left as-is,
--       to be redone later).
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
    _mdir .. 'actions_phrases.lua',
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
dofile(_mdir .. 'actions_phrases.lua')
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
