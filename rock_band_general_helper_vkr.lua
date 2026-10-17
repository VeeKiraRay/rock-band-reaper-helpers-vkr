-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.63
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
--     Difficulty - copy and validate Pro Keys + Keys + Guitar/Bass + Drums difficulty tiers;
--                  generate Hard/Medium/Easy automatically for Guitar, Bass and Keys
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
--   v0.9.63
--     - New Difficulty > Generate sub-tab. Builds Hard, Medium and Easy for
--       Guitar, Bass, Pro Keys, Keys or Drums from the difficulty above, in
--       one click. Pick an instrument - or All instruments, which uses PART
--       GUITAR, PART BASS, PART REAL_KEYS_X/H/M/E, PART KEYS and PART DRUMS
--       and skips any that is missing or muted - then generate one difficulty
--       or the whole Hard > Medium > Easy chain. Generate never writes to a
--       muted track: a muted track picked for one instrument stops the run.
--     - It reduces the way official charts do, not just enough to pass
--       Validate. It keeps downbeats and beats first; Medium loses most 8ths
--       and Easy about half the beats. Measured against the official RB3 DLC
--       charts, the notes it keeps match the official choice far more closely
--       than a plain copy does.
--     - One rhythm for the whole band. Which notes stay depends on the rhythm,
--       never on colors or the instrument, so guitar, bass and keys playing the
--       same part get the same easier rhythm on every difficulty. In busy bars
--       on Hard, Bass and Keys follow Guitar: a bar in the same rhythm drops
--       the notes Guitar drops. Chords and colors are reduced afterwards:
--       Guitar/Bass lines move down a lane on Medium and Easy.
--     - Hard always ends up a little easier than Expert. It drops the same
--       off-beat in every bar - first the "and" of 4, the one official Hard
--       drops most - so a riff reduces the same way each time it comes round.
--     - A full bar of 8ths loses one note on Hard (the "and" of 4) or two (also
--       the "and" of 2, leaving two groups of three). Choose it under "Hard 8th
--       runs"; Auto drops two when the song starts above 160 BPM, the RBN docs'
--       "fast". A bar that already rests on one 8th drops one fewer; a bar with
--       two or more 8th rests keeps every note. Sustains - and chords, in a bar
--       that mixes chords with single notes - go last.
--     - Fast runs on fast songs are played one grid slower on Hard instead of
--       being thinned to 8ths: 16ths become 8th triplets (16 notes -> 12),
--       8th triplets become 8ths (12 -> 8), 16th triplets become 16ths. The
--       order of the colors is kept, each half bar starts on its beat, a run
--       that lands on a beat still lands there, a 16th rest before a note on
--       the 8th grid stays (the run restarts after it), and a group that runs
--       into beat 1 or 3 still leads straight into it. A short 16th flourish
--       from a beat into 8ths is thinned to 8ths instead (G G R R R ->
--       G R R .), so it keeps its grouping, and a bar of 8ths right after a
--       run of 16ths still loses its two notes. A 210 BPM solo kept 5 of 14
--       notes before; now it keeps 12 and its motion. The result lists those
--       bars to review by hand.
--     - New "Hard fast runs" choice: Rewrite (the default for now), Auto
--       (rewrite above 160 BPM only) or Thin (never rewrite, as official
--       charts do). With Rewrite, runs of 16ths lasting half a bar or more are
--       rewritten at 160 BPM or slower too (shorter groups are thinned to 8ths
--       as before), so a fast passage in a slower song keeps its motion.
--     - A long run is rewritten on one grid that stays on the beats, between
--       its first and last Expert note, with no break where it crosses beat 3.
--       A run starting on the "and" of 1 no longer begins on the downbeat.
--     - Medium keeps a lone off-beat note with space around it, as official
--       Medium almost always does - unless Medium would otherwise keep more
--       than 95% of Hard: then those notes go first, and only if that is not
--       enough is it eased by color like Hard (top lane Yellow).
--     - Medium: a busy bar keeps a note per beat; a chord wins over the single
--       note next to it, but not over a downbeat; a beat Hard's rewrite moved
--       comes back where Expert plays it; Bass and Keys follow Guitar's Medium
--       in bars of the same rhythm. Sustains shorter than official Medium and
--       Easy ever use become plain notes. Lines move under the top lane note
--       by note, or a whole bar at a time where moving one note would repeat
--       a color the tier above changes.
--     - Guitar/Bass Hard keeps Expert's hammer-ons with force-HOPO markers:
--       wherever Expert forced one and the note survives, and where 8th
--       triplets rewritten as 8ths would otherwise turn a hammer-on run into
--       strums. Assumes Magma's default HOPO threshold (170).
--     - Fast songs no longer lose whole rhythm levels: Hard keeps its 8ths,
--       Medium its quarters and Easy beats 1 and 3, as official charts do. A
--       note with more than a quarter note of space on both sides is never
--       dropped on Hard; Medium drops it when it is off the beat.
--       If Hard still keeps almost all of Expert, as on a sparse beginner part,
--       it is made easier by color instead: each bar moves down until its top
--       note is Blue (Orange-Blue-Yellow becomes Blue-Yellow-Red).
--     - Sustains leave room before the next note: Hard an 8th, Medium a
--       dotted 8th, Easy a quarter (above 160 BPM: Medium a quarter, Easy a
--       half). A sustain too short to keep that gap becomes a short 1/32 note,
--       so it clearly reads as a plain note.
--     - Pro Keys gets the same rhythm as the other instruments, with its own
--       pitch rules, measured on the official charts: chords lose notes from
--       the bottom, so the top (melody) note stays; Hard keeps Expert's notes
--       and the lane shifts it still needs; Medium and Easy show one range for
--       the whole song - Hard's, when Hard keeps one range all song, else
--       the one that fits the most notes. Notes outside
--       it move by an octave; notes inside never move. Sustains leave the RBN
--       gaps (Hard 1/16 or 1/8, Medium and Easy a quarter). Big interval
--       jumps are left as they are, as official charts mostly do. When Expert
--       is so simple that Hard would be an exact copy, Generate asks first:
--       shorten Hard's sustains a little (as some official charters do), or
--       keep Hard as Expert. The result says which was chosen.
--     - Keys and Pro Keys: a lick that starts on an "and" and moves on its
--       "and"s while its beats repeat a note keeps the "and"s on Medium, so
--       the line keeps moving instead of repeating; Easy goes back to Hard's
--       downbeats there. The result lists those bars.
--     - Keys follow the same-difficulty Pro Keys automatically when it has
--       notes, so a Pro Keys reduction you already made carries over. All
--       instruments generates Pro Keys first, and Keys then follows it. One
--       Keys note per Pro Keys note, at exactly the Pro Keys note's position,
--       so both play the same rhythm (a rewritten run included); a Pro Keys
--       note Keys has no note for is listed in the result.
--     - Pro Keys Validate: note spacing on Medium and Easy now works like
--       Keys - an error under an 8th (Medium) or a quarter (Easy), an
--       advisory under the RBN doc's quarter and half. Interval jumps are
--       advisories. Official charts break both doc rules often (Easy: 42% of
--       gaps under a half note), so as errors they flagged nearly every chart.
--       "Unchanged copy" and "NOT REDUCED" are advisories on Pro Keys too.
--     - Validate, every instrument: a difficulty that keeps every note but
--       holds some sustains shorter is no longer "NOT REDUCED"; it reports
--       "only sustain lengths differ".
--     - Songs not in 4/4: the tempo is read in quarter notes, as Validate
--       reads it (a 6/8 song at 105 BPM was treated as 210, so every rule
--       for fast songs fired). In 6/8, 9/8 and 12/8 Easy keeps the bar's
--       dotted-quarter beats and Medium each beat plus the 8th after it, as
--       official charts do, instead of three quarter notes across them.
--       Outside 4/4, a full bar of 8ths on Hard loses the 8th before
--       the next bar line first (in 3/4 the "and" of 3, not the "and" of 2).
--     - Keys and Pro Keys: a note Expert holds while other notes start over
--       it keeps sounding on Hard, within the RBN limits (3 notes at once on
--       Keys, 4 within an octave on Pro Keys). Over the limit, the new
--       chord loses notes first, then the earliest held note ends early; a
--       note that starts is never dropped for it. Medium keeps such a note
--       only when it was held for a bar or more; Easy never. A rolled chord
--       (notes a 1/32 apart, all held) becomes one chord on the beat.
--     - Keys chords lose their lowest notes, keeping the top (melody) note as
--       Pro Keys does and as official Keys charts do most often (Green-Red-
--       Blue becomes Red-Blue). On Easy, a chord repeated for a while stays
--       one note, and a chord change never turns into a repeated note.
--     - Drums are reduced on their own, limb by limb, and never move a note
--       (official charts don't): Hard drops 16ths at 140 BPM and up, keeps a
--       16th tom/snare run only if it lasts two beats or less, puts the
--       hi-hat on 8ths, thins the kicks (under steady 8th hats to beats 1
--       and 3 plus beat 4 where Expert has it, so the bar ends with a faster
--       kick pattern; with quiet hands every beat keeps its kick, under the
--       snare too) and plays Expert's disco-flip sections
--       as a normal beat. A tom the rewrite moves gets one tom marker over
--       its whole run, and the result names those bars to check. Medium
--       plays a two-hand hit with a tom as one gem from 140 BPM, and moves
--       the hi-hat to quarters from 130 BPM -
--       where official charts switch, earlier than the RBN doc's 140 - and on
--       a slower song too when Medium would otherwise keep over 93% of Hard;
--       it keeps kicks on quarter notes (half a bar apart under busy hands),
--       at most two gems at once, and keeps a kick or snare
--       between hi-hat notes only on the beat ("Drums Medium": Beats, None
--       as the RBN doc says, or Keep). Easy plays kick + snare in verses on
--       the hi-hat or ride that have enough kick and snare (a sparse verse
--       keeps its cymbal) and a two-hand beat elsewhere, read from the EVENTS
--       track's sections, never pairs a gem with a kick, and from 140 BPM
--       drops a lone drum on the "and" between two beat hits; from 110 BPM a
--       bar with the snare on the "and"s plays only the "and"s, and from
--       120 BPM a run of 5+ snare 8ths keeps only its beats. Medium and Easy
--       drop a hi-hat sandwiched between snare accents, so the hands don't
--       alternate hat and accent on every 8th. On fast songs (Medium from
--       150 BPM, Easy from 140) no three hand hits come an 8th apart - a
--       pair stays; "Drums fast 8ths" picks which hit goes: Beats (the
--       "and", as official charts do) or Hands (the hit with the least
--       important hands, so two snares can stay together). Every difficulty
--       thins the kicks in fills, plays rolls on its own grid with an even
--       number of hits, and turns a double crash with no room before it into
--       one crash. With "Hard fast runs" on Rewrite or Auto, tom and snare
--       fills are played one grid slower instead of thinned to 8ths;
--       Medium and Easy then reduce such a fill from Expert's notes, so
--       it does not vanish from their 8th grid.
--     - Drums also generates the song's PART DRUMS_2X (double bass pedal),
--       after PART DRUMS: each 2X difficulty plays the kicks of the PART
--       DRUMS difficulty one step up - Hard the single-pedal Expert's,
--       Medium PART DRUMS Hard's, Easy its Medium's - so the 2X Hard stays
--       harder than the normal one. With no PART DRUMS (or a muted one in All
--       instruments), only
--       the 2X track is written, its kicks taken from a single-pedal version
--       made in memory the way "Remove 2x kicks" makes one. The result lists
--       both tracks. "Only 2x bass pedal authored on PART DRUMS" treats
--       PART DRUMS itself as the 2x chart, for a song charted only that way.
--     - General > Actions "Remove 2x kicks": in a 16th double-bass figure the
--       kicks that stay are now chosen by beat position - downbeat, beat,
--       "and", then the 16ths - instead of every second kick counted from the
--       figure's start, so a kick on the beat (often under a crash) is no
--       longer the one removed. Straight 8th runs and triplet figures still
--       alternate as before.
--     - Drums Validate: "kick during a drum fill" is now an advisory, and
--       only when a fill keeps every kick of the difficulty above (official
--       charts thin them, they don't remove them).
--     - Validate: Keys now checks overlapping notes (max 3 on Expert/Hard);
--       Pro Keys allows 4 on Hard, as its doc says, and no longer flags a
--       chord built from a rolled Expert chord.
--     - The result is checked with Validate's own rules and anything left to
--       fix is listed with its time. It asks before replacing notes, one undo
--       reverts the whole run, and a time selection limits it to the notes
--       that start inside it (a note on its first downbeat is replaced, one
--       on the downbeat where it ends is left alone). The result
--       ends with how long the run took (and, for a slow run, where the
--       time went).
--     - It is a starting point, not a finished chart. Official charters make
--       judgement calls no rule captures - play it through and adjust.
--
--   v0.9.62
--     - Difficulty > Keys and Guitar/Bass: Validate now agrees with official
--       charts. Every official RB3 DLC chart was run through it, and four rules
--       flagged Harmonix's own work on most songs. Each now matches what those
--       charts actually do, so what Validate still reports is worth fixing.
--     - Colors on Medium and Easy. Keys: all five colors are valid on every
--       difficulty - official Keys charts use Blue and Orange as much on Easy
--       as on Expert - and Copy no longer pulls them down a color. Guitar/Bass:
--       Medium still focuses on Green to Blue and Easy on Green to Yellow, but
--       the upper colors are allowed, as the RBN docs say. Only heavy use is
--       reported, as an advisory: a color above 5% of the notes, where a
--       typical official chart sits near 1%.
--     - Sustain gaps on Medium and Easy: the next note now needs a 1/8 note gap
--       after a sustain, not a 1/4 (1/16 on Medium at 100 BPM or slower).
--       Official charts pull sustains back by an 8th, as the docs describe.
--     - Keys Medium spacing: notes 1/8 apart are allowed; under a 1/4 is now
--       an advisory rather than an error. Official Medium Keys uses 1/8 gaps
--       routinely at moderate tempos.
--     - Force-HOPO markers on Medium or Easy are an advisory now, not an
--       error. One official guitar Medium chart in five has some.
--     - Expert and Hard checks are unchanged; official charts already pass them.
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
    _mdir .. 'actions_difficulty_drums_checks.lua',
    _mdir .. 'actions_difficulty_drums.lua',
    _mdir .. 'difficulty_generate_params.lua',
    _mdir .. 'difficulty_generate_overlaps.lua',
    _mdir .. 'difficulty_generate_retime.lua',
    _mdir .. 'difficulty_generate_colors.lua',
    _mdir .. 'difficulty_generate_rhythm.lua',
    _mdir .. 'difficulty_generate_5lane.lua',
    _mdir .. 'difficulty_generate_prokeys.lua',
    _mdir .. 'difficulty_generate_hopo.lua',
    _mdir .. 'difficulty_generate_drums.lua',
    _mdir .. 'actions_difficulty_generate.lua',
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
    _mdir .. 'ui_difficulty_generate.lua',
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
dofile(_mdir .. 'actions_difficulty_drums_checks.lua')
dofile(_mdir .. 'actions_difficulty_drums.lua')
-- Difficulty > Generate: the pure planner (its Hard fast-run rewrite first), then the
-- action that reads and writes tracks. All only touch the rule tables and FindTrackExact
-- (difficulty_read.lua) at call time.
dofile(_mdir .. 'difficulty_generate_params.lua')
dofile(_mdir .. 'difficulty_generate_overlaps.lua')
dofile(_mdir .. 'difficulty_generate_retime.lua')
dofile(_mdir .. 'difficulty_generate_colors.lua')
dofile(_mdir .. 'difficulty_generate_rhythm.lua')
dofile(_mdir .. 'difficulty_generate_5lane.lua')
dofile(_mdir .. 'difficulty_generate_prokeys.lua')
dofile(_mdir .. 'difficulty_generate_hopo.lua')
dofile(_mdir .. 'difficulty_generate_drums.lua')
dofile(_mdir .. 'actions_difficulty_generate.lua')
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
dofile(_mdir .. 'ui_difficulty_generate.lua')
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
