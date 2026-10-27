-- @description Rock Band Instrument Helper
-- @author VeeKiraRay
-- @version 0.1
-- @about
--   Instrument part authoring for Rock Band in REAPER: Guitar, Bass, Drums,
--   Keys and Pro Keys.
--
--   Tabs:
--     General    - remove 2x kicks, settings, buttons that
--                  open the other tools in this set
--     Difficulty - copy and validate Pro Keys + Keys + Guitar/Bass + Drums difficulty tiers;
--                  generate Hard/Medium/Easy automatically
--     Overdrive  - generate overdrive phrases, unisons, drum fills and vocal
--                  overdrive; validate what is already authored
--     Tab Input  - guitar/keys/vocal tab entry guide
--     MIDI       - MIDI alignment, length sync, pattern replace
--   Work-in-progress tabs (General > Settings > Show WIPs?):
--     Drums      - convert GM MIDI to Rock Band 5-lane drum notation
--     Keys       - hand split, Pro Keys conversion + animation, 5-Lane Keys conversion
--     Guitar     - convert raw MIDI to Expert Guitar gems, validate
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   These tabs were part of the Rock Band General Helper up to v0.9.62; their
--   earlier history is under that script in CHANGELOG.md in the repo.
--
--   v0.1
--     - First version. The Difficulty, Overdrive, Tab Input and MIDI tabs,
--       the work-in-progress Drums, Keys and Guitar tabs, and "Remove 2x
--       kicks" moved here from the General Helper, which keeps the song-wide
--       tools (audio, tempo map, workflow, venue, metadata). Both helpers can
--       be open at once, and each opens the other from General > Other tools.
--     - Settings are saved separately from the General Helper's. Settings
--       saved in a project before this version are not carried over: these
--       tabs start from their defaults until you save them here.
--     - New footer, always at the bottom of the window: the time selection,
--       the status line, Copy result (the status and result to the clipboard)
--       and Undo. The tabs scroll above it, so on a short window these no
--       longer scroll out of sight. The track dropdowns now update on their
--       own: adding, renaming or deleting a track, or adding an item to one,
--       shows up within about a second. The Refresh tracks button is gone.
--     - The rest of this entry is what changed in these tabs after General
--       Helper v0.9.62.
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
--     - Tab Input, Vocal guide: a passage that already fits C1-C5 keeps its
--       pitch. It used to be moved to the octave nearest C3, as Pro Keys
--       does, so a note on the high e string's 5th fret (A3) came out as A2.
--       Now it shifts only when notes fall outside the range, and then by
--       the smallest octave step.
--     - Tab Input, Pro Keys and Vocal guides: the result lists one row per
--       note or chord, like the Guitar guide - the tab line you typed, its
--       pitches, and on the same row any note out of range or chord wider
--       than an octave - instead of all pitches on one line and the problems
--       in a separate list.
--     - Overdrive, drum fills: Generate no longer places a fill less than 2.5 s
--       after the previous one ends, which Magma refuses to build ("Must be
--       2.5 sec between drum fills"). A fast song could get there through
--       section alignment; across the official RB3 DLC songs the old layout
--       would have hit it in about one song in four. Validate reports it as
--       an error.
--     - The fill pacing is now a minimum: fills never end closer together
--       than it. A section change that comes sooner still gets its fill, and
--       the fill before it is removed instead.
--     - Practice subsections no longer count as a section change: chorus_1a
--       -> chorus_1b, intro_a -> intro_b, or chorus_1 -> chorus_2 back to
--       back. They can still line a fill up at the normal spacing, but never
--       pull one earlier.
--     - Auto fill pacing: fast songs now get one measure every 4, as official
--       charts do at every tempo, instead of 2 measures every 8 from 170 BPM.
--       "2 bars every 8 bars" is still there to pick by hand.
--
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

ctx = r.ImGui_CreateContext('Rock Band Instrument Helper')  -- global

-- Module files live in a subfolder named after this script (without .lua).
-- Renaming the entry point requires renaming the folder too - intentional.
local _script  = ({reaper.get_action_context()})[2]
local _dir     = _script:match('^(.+[\\/])')
local _mdir    = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'
SCRIPT_MDIR    = _mdir  -- global: module files need this for filesystem paths
SCRIPT_DIR     = _dir   -- global: repo root

local _files = {
    _dir  .. 'lib/reaper_imgui_helpers.lua',
    _dir  .. 'lib/reaper_helper_common.lua',
    _dir  .. 'lib/reaper_helper_ui.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _dir  .. 'lib/reaper_guitar_theory.lua',
    _dir  .. 'lib/reaper_script_links.lua',
    -- Chart reading for Generate and Overdrive. reaper_difficulty_score.lua must
    -- precede its vocals companion (which appends to SCORE_FACTOR_KEYS);
    -- reaper_difficulty_read.lua calls both, at call time only.
    _dir  .. 'lib/reaper_difficulty_score.lua',
    _dir  .. 'lib/reaper_difficulty_score_vocals.lua',
    _dir  .. 'lib/reaper_difficulty_tiers.lua',
    _dir  .. 'lib/reaper_difficulty_read.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
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
    -- Difficulty > Generate: the pure planner (its Hard fast-run rewrite first), then the
    -- action that reads and writes tracks. All only touch the rule tables and FindTrackExact
    -- (lib/reaper_difficulty_read.lua) at call time.
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
    -- Overdrive tab: the song model first (it reads through lib/reaper_difficulty_read.lua's
    -- FindTrackExact / ReadGemEvents), then the per-bar interest score, the fill and vocal
    -- planners, the instrument planner and Generate action that calls them, and the
    -- validator. ui_overdrive.lua reads OD_FILL_PACINGS at load time.
    _mdir .. 'overdrive_read.lua',
    _mdir .. 'overdrive_interest.lua',
    _mdir .. 'actions_overdrive_fills.lua',
    _mdir .. 'actions_overdrive_vocals.lua',
    _mdir .. 'actions_overdrive.lua',
    _mdir .. 'actions_overdrive_validate.lua',
    _mdir .. 'ui_keys.lua',
    _mdir .. 'ui_difficulty_generate.lua',
    _mdir .. 'ui_difficulty.lua',
    _mdir .. 'ui_overdrive.lua',
    _mdir .. 'ui_midi_pattern.lua',
    _mdir .. 'ui_midi.lua',
    _mdir .. 'ui.lua',  -- also calls r.defer(Loop) at end
}

for _, _f in ipairs(_files) do
    if not r.file_exists(_f) then
        r.ShowMessageBox(
            'A required file is missing:\n\n  ' .. _f:sub(#_dir + 1) ..
            '\n\nPlease reinstall the script.',
            'Missing file', 0)
        return
    end
end

-- Window title with this script's own @version, read from the header above.
-- ui.lua passes it to ImGui_Begin; the "###" id inside keeps saved window
-- geometry across version bumps. See ScriptWindowTitle. Set once the lib is
-- loaded (it defines ScriptWindowTitle) and before ui.lua, which draws with it.
for _, _f in ipairs(_files) do
    dofile(_f)
    if _f == _dir .. 'lib/reaper_imgui_helpers.lua' then
        WINDOW_TITLE = ScriptWindowTitle('Rock Band Instrument Helper', _script)
    end
end

-- Startup initialisation (runs after all modules are loaded; ui.lua's
-- r.defer(Loop) only queues the first frame, so this still runs before it)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultMIDITracks()
SetDefaultDifficultyTracks()
