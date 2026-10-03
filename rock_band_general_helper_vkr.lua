-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.61
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - stem import, audio alignment, count-in positioning, song fade out, settings,
--                  per-project authoring workflow checklist, buttons that open
--                  the other tools in this set
--     Tempo Map  - audio-driven tempo map generation from drum stems
--     Drums      - convert GM MIDI to Rock Band 5-lane drum notation
--     Keys       - hand split, Pro Keys conversion + animation, 5-Lane Keys conversion
--     Guitar     - convert raw MIDI to Expert Guitar gems, tab guide, validate
--     Difficulty - copy and validate Pro Keys + Keys + Guitar/Bass + Drums difficulty tiers
--     Overdrive  - generate overdrive phrases, unisons, drum fills and vocal
--                  overdrive; validate what is already authored
--     Tab Input  - guitar/keys/vocal tab entry guide
--     MIDI       - MIDI alignment, length sync, pattern replace
--     Venue      - list, validate, and generate VENUE and EVENTS track events
--     Metadata   - genre converter (real-world genre to the supported major genre
--                  and subgenre), and suggested difficulty rank and tier per
--                  instrument (Beta) from measurements of the finished Expert
--                  charts. Read-only.
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.9.61
--     - General > Actions: new "Import stems" button. Pick a folder of stems and
--       each one lands on its template track, lined up with the SONG AUDIO item.
--       Files are matched by keyword in the filename, ignoring case: kick, snare,
--       bass, guitar, drum (KIT AUDIO), vocal (VOCAL AUDIO, a "lead" file
--       preferred), vocal + back (DRYVOX2), and piano, keys or accordion (KEYS
--       AUDIO, in that order). When several files fit, the shortest name wins,
--       and each file goes to one track only.
--     - KIT AUDIO skips single-piece files such as drums_hh, drums_toms or
--       drums_cymbals, and BASS AUDIO skips bassdrum, so a kit piece is never
--       mistaken for the full kit or the bass.
--     - A track that already holds audio is left alone. The result lists what was
--       imported, what was skipped and why, and any audio file that matched no
--       track. One undo removes the whole import.
--     - With the js_ReaScriptAPI extension a folder dialog opens; without it, pick
--       any file inside the stem folder and that folder is used.
--
--   v0.9.60
--     - New Overdrive tab. Generates overdrive phrases, unisons, drum fills and
--       vocal overdrive for the whole song, following the RBN authoring rules:
--       about one one-measure phrase per 40 counted beats of each part's playing
--       time, about half as many unisons, even spacing, nothing in the last 8
--       measures and no unison in the last 12. The first phrase waits until the
--       band has played 5 measures (adjustable) - official charts put it a median
--       of 5 measures in. Pick All or a single part. Tracks
--       that must match are always written together: PART DRUMS + PART DRUMS_2X,
--       PART KEYS + PART REAL_KEYS_X, PART VOCALS + HARM1.
--     - The order matters. Vocal overdrive comes first, copied exactly from the
--       phrase markers, and only where HARM1 has an identical phrase. Rock Band 3
--       has a visual bug in harmonies if the parts differ. To avoid this we avoid
--       vocal phrase markers that are different between PART VOCALS and HARM1:
--       where they differ, it moves one phrase earlier or later, or tells you
--       where it could not. Then drum fills,
--       one measure every 4 by default, ending at section changes - or on a drum
--       crash where no section is near. Then the instrument phrases, which keep
--       clear of fill measures and of a fill's closing crash.
--     - Unisons go where the band plays together, as official charts do: on the
--       measure just before a new section (the fill there gives way to it), and
--       where guitar and bass play the same rhythm and move the same way. Checked
--       against official charts, this puts about 2.5x as many unisons where the
--       charter put one. Untick "Prefer measures where the band plays together"
--       if a song comes out worse.
--     - "Over vocal OD" sets whether instrument phrases may sit under vocal
--       overdrive: anywhere (the default, as official charts do), everywhere but
--       the measure a vocal phrase starts in, or not at all. Vocals are never
--       part of a unison either way.
--     - Fills before the drummer can first activate overdrive (two drum phrases,
--       or one unison) are left out, since they can never be used. Untick "Skip
--       fills before overdrive can be activated" to keep them. Likewise no fill
--       leads into the drums' last 2 measures (adjustable) - there is nothing left
--       to deploy overdrive for at the final hit.
--     - If a fill ends on a section start that the drums do not mark with a crash,
--       while the measure beside it has one, the result says so: that section
--       event is probably a measure off. Move it and generate again.
--     - A single part joins the unisons the other parts already have. If a track
--       already has overdrive or fills you are asked before anything is replaced,
--       and can keep it instead. One undo step reverts a whole run. A time
--       selection is ignored, and a Big Rock Ending is never written into.
--     - Validate checks what is already authored: counts and spacing, unisons,
--       fill collisions, matching tracks and the end-of-song keep-outs, reports
--       how far into the song the first phrase comes, and draws an overview strip
--       of the whole song. Read-only.
--     - Which of several nearby measures gets a phrase is a suggestion, not a copy
--       of what an official charter would pick. Official charters are not
--       consistent with themselves either, so treat the result as a starting
--       point to adjust.
--
--   v0.9.59
--     - The window title now carries the script version - "Rock Band General
--       Helper v0.9.59". A bug report that quotes the title says which version
--       it came from, with nothing to look up. The version is read from this
--       file's own header when the script starts, so it can never disagree
--       with the version entries below.
--     - Your window size, position and dock state carry over unchanged, and
--       will survive every future version bump too.
--
--   v0.9.58
--     - General > Actions: new "Remove 2x kicks" button. When a song is charted
--       with a double bass pedal, PART DRUMS_2X holds the complete drum chart -
--       every kick, the double hits included - and PART DRUMS has to be the same
--       chart with the second foot taken out, so one pedal can still play it.
--       Working out by hand which kicks those are is slow and easy to lose track
--       of halfway through a two-bar blast. Author every kick on both tracks and
--       press this instead.
--     - Only PART DRUMS loses notes. PART DRUMS_2X is never thinned, so it stays
--       the complete chart the game expects.
--     - How it decides. Kicks up to a 1/8 apart count as one line. Two back-to-
--       back 1/16 kicks are already two feet, so any line that tight qualifies;
--       a straight run of 1/8s needs more than four in a row, since four or fewer
--       is playable with one foot. A kick hanging off the line by a wider gap - a
--       lone 1/8 leaning against a burst of 1/16s, or one across a bar line from
--       the rest - is a separate hit and is left alone.
--       Every other kick in the line is the second foot, phased so a kick on a
--       bar downbeat is never taken - which is why a line ending on the downbeat
--       alternates from its first kick instead of its second. A line with a gap
--       in it is read as one continuous grid rather than by counting the kicks
--       that are there, so the feet stay on the same subdivisions across the gap
--       and the downbeats either side stay primary.
--     - Matching between the two tracks is by musical position, so a tempo change
--       anywhere in the song does not affect it - which matters on fast songs,
--       where a BPM jump makes a note's position in seconds drift by more than a
--       MIDI tick. On a fast run it will not take a neighbouring gem by mistake.
--       The result says whether the two tracks are left holding consistent kicks.
--     - The whole track is processed - a time selection does not change the
--       result. Safe to run twice: the second run finds nothing left to remove,
--       says so, and creates no undo point. One undo puts both tracks back.
--     - Charts are checked, not trusted. The rules come from a small number of
--       hand-charted songs, so an unusual passage can still come out wrong - most
--       often where a line has a gap in it. It is meant to do the bulk of the work
--       on the long passages, not to be the last word.
--
--   v0.9.57
--     - Metadata > Difficulty: new suggestion models for drums, keys and vocals,
--       refitted against a reference corpus that grew from 205 songs to 394. The
--       earlier corpus was thin at both ends of the scale, which flattered every
--       figure: a model that hedges toward the middle looks good when most of the
--       songs measured against it sit there. Easy and hard songs were added at
--       both ends, so the accuracy numbers went DOWN while becoming honest.
--       Guitar, bass and Pro Keys suggestions are unchanged.
--     - Vocals: the model now measures how long a part stays high, not only how
--       high it reaches. A chart that sits above G4 for much of its singing time
--       reads harder than one that touches the same note once, which is what the
--       official ranks reward. It also counts how often the melody changes note.
--       Vocals remains the weakest instrument and keeps its Experimental badge -
--       it still under-rates the hardest charts, the operatic and wide-ranging
--       ones most of all.
--     - Drums: back to the fuller model, which now wins clearly rather than by a
--       hair. It is the most reliable of the six.
--     - Keys: unchanged factors, fitted on a straight rank scale rather than a
--       log one. Keys sits fractionally under the accuracy bar the other three
--       cleared, so it keeps its Beta badge; adding easy and hard keys charts
--       twice failed to close that gap, which suggests the limit is the model
--       rather than the number of songs behind it.
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
    _mdir .. 'actions_stem_import.lua',
    _mdir .. 'actions_tempomap.lua',
    _mdir .. 'actions_drums.lua',
    _mdir .. 'actions_drums_2x.lua',
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
    _mdir .. 'difficulty_report.lua',
    _mdir .. 'difficulty_suggester.lua',
    _mdir .. 'metadata_genres.lua',
    _mdir .. 'metadata_genres_ext.lua',
    _mdir .. 'metadata_genres_lookup.lua',
    _mdir .. 'overdrive_read.lua',
    _mdir .. 'overdrive_interest.lua',
    _mdir .. 'actions_overdrive_fills.lua',
    _mdir .. 'actions_overdrive_vocals.lua',
    _mdir .. 'actions_overdrive.lua',
    _mdir .. 'actions_overdrive_validate.lua',
    _mdir .. 'ui_common.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_difficulty.lua',
    _mdir .. 'ui_overdrive.lua',
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
    _mdir .. 'ui_metadata_genre.lua',
    _mdir .. 'ui_metadata.lua',
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

-- Window title with this script's own @version, read from the header above.
-- ui.lua passes it to ImGui_Begin; the "###" id inside keeps saved window
-- geometry across version bumps. See ScriptWindowTitle.
WINDOW_TITLE = ScriptWindowTitle('Rock Band General Helper', _script)

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
dofile(_mdir .. 'actions_stem_import.lua')
dofile(_mdir .. 'actions_tempomap.lua')
dofile(_mdir .. 'actions_drums.lua')
dofile(_mdir .. 'actions_drums_2x.lua')
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
dofile(_mdir .. 'difficulty_report.lua')   -- consumes DifficultyAnnotate's output
dofile(_mdir .. 'difficulty_suggester.lua')
-- Genre converter: vocabulary, then the authored mapping, then the lookup that
-- reads both. metadata_genres_lookup.lua touches them only at call time, but the
-- load order still states the dependency.
dofile(_mdir .. 'metadata_genres.lua')
dofile(_mdir .. 'metadata_genres_ext.lua')
dofile(_mdir .. 'metadata_genres_lookup.lua')
-- Overdrive tab: the song model first (it reads through difficulty_read.lua's
-- FindTrackExact / ReadGemEvents), then the per-bar interest score, the fill and vocal
-- planners, the instrument planner and Generate action that calls them, and the
-- validator. ui_overdrive.lua reads OD_FILL_PACINGS at load time.
dofile(_mdir .. 'overdrive_read.lua')
dofile(_mdir .. 'overdrive_interest.lua')
dofile(_mdir .. 'actions_overdrive_fills.lua')
dofile(_mdir .. 'actions_overdrive_vocals.lua')
dofile(_mdir .. 'actions_overdrive.lua')
dofile(_mdir .. 'actions_overdrive_validate.lua')
dofile(_mdir .. 'ui_common.lua')
dofile(_mdir .. 'ui_keys.lua')
dofile(_mdir .. 'ui_difficulty.lua')
dofile(_mdir .. 'ui_overdrive.lua')
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
dofile(_mdir .. 'ui_metadata_genre.lua')
dofile(_mdir .. 'ui_metadata.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
