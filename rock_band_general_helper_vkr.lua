-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.58
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
--   v0.9.58
--     - General > Actions: new "Mark double kicks" button. Charting a double
--       bass pedal means deciding, hit by hit, which kicks in a fast line are
--       the second foot - which is slow, and easy to lose track of halfway
--       through a two-bar blast. Press this and it finds the fast lines on
--       PART DRUMS_2X and moves every second foot from pitch 96 to 95.
--       Kicks up to a 1/8 apart count as one line. Two back-to-back 1/16 kicks
--       are already two feet, so any line that tight qualifies; a straight run
--       of 1/8s needs more than four in a row, since four or fewer is playable
--       with one foot. A kick joined to the line by a wider gap across a bar
--       line is a pickup or a tail, and is left alone.
--       Every other kick in the line becomes the second foot, phased so a kick
--       on a bar downbeat is never taken - which is why a line ending on the
--       downbeat alternates from its first kick instead of its second.
--       Kicks already at 95 count as part of their line, so running it twice
--       changes nothing. A 95 sitting where the rules would not put one is
--       reported and left alone: your own edits are never reverted.
--     - The two buttons are meant to be used in order. Author every kick on
--       both drum tracks, press Mark double kicks, then Remove 2x-marked kicks
--       to take those same hits out of the 1x chart.
--     - General > Actions: new "Remove 2x-marked kicks" button. When a song is
--       charted with a double kick pedal, the extra hits live on PART DRUMS_2X
--       marked with pitch 95, and the 1x chart must not carry a kick at those
--       same ticks. Deleting them by hand across a whole song is slow and easy
--       to get wrong, so this does it in one pass: every kick on PART DRUMS
--       that lines up with a 2x marker is removed, and nothing else on either
--       track is touched.
--     - Matching is by musical position, so a tempo change anywhere in the song
--       does not affect it - which matters on fast songs, where a BPM jump makes
--       a note's position in seconds drift by more than a MIDI tick. Each marker
--       takes the nearest kick, and only when that kick is clearly nearer than
--       the next one along, so on a fast double-kick run it cannot take the
--       neighbouring gem by mistake. A marker whose kick is too far away, or too
--       close to call between two, is reported with the distance rather than
--       guessed at.
--       If PART DRUMS_2X also carries the 1x kicks as pitch 96 - the usual way
--       to author this - the result also says whether the kick counts on the two
--       tracks agree afterwards.
--       The whole track is processed - a time selection does not change the
--       result. Safe to run twice: a run that matches nothing says so and
--       creates no undo point.
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
--
--   v0.9.56
--     - Metadata > Genre: an editorial pass over the mapping after a peer review.
--       Four calls were checked against outside sources rather than settled by taste.
--       Screamo now leads with Emo, since it is an offshoot of emo rather than of
--       metal - the old answer leaned on "screamed vocals", which describes half the
--       list. Viking Metal keeps Black, which is where the style actually came from,
--       and both it and Folk Metal now offer melodic death metal, the branch that was
--       missing and the one Amon Amarth-shaped songs need.
--     - Big Band, Swing and Bebop no longer file as Jazz / Contemporary. Contemporary
--       means modern jazz, so sending historic jazz there quietly misdated it;
--       Jazz / Other is the honest answer and the entries say why.
--     - Suggestions that really meant "you may have picked the wrong genre" are no
--       longer mixed in with the genuine alternatives. Post-Grunge suggested Grunge as
--       though it were another home for post-grunge, when it was telling you to pick a
--       different genre entirely. Those now appear separately, unnumbered, below the
--       suggestions.
--     - Reasons that claimed "Exact match" where the two names do not actually match
--       now say "closest supported category" instead. Teen Pop is not Teen Rock, and
--       Hardcore Techno is not Hardcore Dance.
--     - 19 more genres, covering the ones that previously returned nothing at all:
--       Trap, Drill, Boom Bap, Jazz Rap, Lo-fi Hip-Hop, Electropop, Dance-Pop, Art
--       Pop, Alternative R&B, Post-Metal, Industrial Rock, Melodic Metalcore, Jungle,
--       UK Garage, Glitch, Cumbia, Bachata, Merengue and Mariachi. 227 genres in all.
--     - The tab now says it is advisory, the way Metadata > Difficulty does. Where a
--       style belongs is a judgment call rather than a measurement, so if a suggestion
--       looks plainly wrong it is worth saying so - the mappings are meant to be
--       corrected.
--     - The file now states which dimension wins when a genre could be filed by sound,
--       era, origin or subject matter, so entries like J-Rock and K-Pop stop looking
--       inconsistent, and no longer claims the reference catalogue proves more than it
--       does.
--   v0.9.55
--     - New Metadata > Genre sub-tab: a genre converter. Rock Band accepts 29 major
--       genres and 126 subgenres, and finding the right one is a chore when your song
--       is something the list has no name for. Pick the genre you would actually call
--       the song from a family-narrowed dropdown and it reports the closest supported
--       pair, with a plain-language reason for each.
--       Over 200 genres are offered, deliberately wider than the supported list, so
--       styles with no category of their own - Djent, Easycore, Synthwave, Deathcore,
--       Post-Hardcore, Blackgaze - resolve to something real instead of leaving you
--       guessing.
--     - Some genres map more than one way, and the tab says so rather than pretending
--       otherwise. Where the released-song catalogue genuinely filed a style two ways,
--       both are offered, best first, and each says what would tip the choice. Where
--       the catalogue is consistent, one answer is given.
--     - Names only, never internal metadata strings. Those spellings drift between
--       game eras, and the tool that writes your song metadata has its own picker.
--       Read-only, like Metadata > Difficulty: it never reads or writes the project
--       and creates no undo point.
--   v0.9.54
--     - New Metadata tab, with a Difficulty sub-tab: suggested difficulty (Beta).
--       Press Refresh suggestions and it scores every finished Expert chart in
--       the project - Guitar, Bass, Drums, Keys, Pro Keys and Vocals - and
--       suggests a rank and tier for each, from measurements of the charts
--       themselves. Five difficulty dots as the game shows them, the rank, and
--       a ruler showing where the score landed between the tier it earned and
--       the next one up, so a close call is visible as a close call. Under that,
--       up to three plain-language notes on what makes the chart unusual
--       compared with the reference songs, each explaining its own terminology
--       on hover.
--       Read-only: it never writes a rank, a MIDI event or a project setting,
--       and creates no undo point. The whole chart is scored - a time selection
--       does not change the result.
--     - Advisory, and it says so. The suggestion is an estimate from a model
--       fitted to official Rock Band 3 ranks, not the official rank, and
--       official and player judgments differ from each other too. Where a
--       chart scores past the end of what the tool can measure, it says that
--       rather than showing a number it cannot stand behind. Keys, Pro Keys
--       and Vocals are less certain than Guitar, Bass and Drums.
--     - No confidence percentage anywhere, and no list of which measurement
--       "caused" a rank. The measurements are heavily interrelated, so naming
--       one as the reason would be inventing an explanation; what is shown is
--       what was measured.
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
dofile(_mdir .. 'ui_metadata_genre.lua')
dofile(_mdir .. 'ui_metadata.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTempoTracks()
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
