-- @description Rock Band General Helper
-- @author VeeKiraRay
-- @version 0.9.64
-- @about
--   Utility actions for Rock Band authoring in REAPER.
--
--   Tabs:
--     General    - stem import, audio alignment, count-in positioning, song fade out, settings,
--                  buttons that open the other tools in this set
--     Workflow   - per-project authoring workflow checklist
--     Animation  - Beat: write the BEAT track (normal, half or double time);
--                  Character: band member animation states per part;
--                  Drums: the drummer's hand and kick animation notes
--     Events     - list song sections, insert EVENTS track events at the
--                  playhead
--     Venue      - list, validate, and generate VENUE track events
--     Metadata   - genre converter (real-world genre to the supported major genre
--                  and subgenre), suggested difficulty rank and tier per
--                  instrument (Beta) from measurements of the finished Expert
--                  charts, suggested song key (Beta), and each part's score,
--                  star cut-offs and gold-star check. Read-only.
--   Work-in-progress tab (General > Settings > Show WIPs?):
--     Tempo Map  - audio-driven tempo map generation from drum stems
--
--   The instrument tabs (Difficulty, Overdrive, Tab Input, MIDI and the WIP
--   Drums, Keys and Guitar tabs) are in the Rock Band Instrument Helper.
--
--   Built with Claude (Anthropic) - https://claude.ai
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.9.64
--     - New Metadata > Score: for each Expert part (Guitar, Bass,
--       Drums, Keys, Pro Keys, Vocals) the full-combo score without overdrive, the
--       points needed for each star, and the score with overdrive deployed as
--       soon as it can be - with the bar where gold stars are reached, or how
--       far short it falls. Uses the game's own scoring rules; compared with
--       autoplay recordings of a few songs, it lands within a few percent
--       (autoplay deploys overdrive at other moments). Drums show Pro and non-Pro scores,
--       and PART DRUMS_2X gets its own card when the project has it unmuted.
--       A missing or muted part is listed with the reason. A Big Rock Ending
--       counts at up to 500 points a second, what keeping all five lanes going
--       earns (the stars count it at 100), and the card says how much of the
--       total that is. Unisons follow the game's rule: phrases on two different
--       instruments starting less than a beat apart (vocals never).
--       Overdrive is deployed as soon as it is useful - at once, or at the
--       part's next note after a rest, and for vocals just before the singing
--       comes back after a long break - except at the end: when
--       that would leave the last overdrive unusable, an earlier deploy is held
--       so it is used too, and the card says where. Also how much of each part
--       is played in overdrive, warnings where authored overdrive is lost
--       (earned into a full meter), a grey note for a drum fill that cannot
--       appear because it starts less than one highway length - 1.2 s on
--       Expert - after drum overdrive first becomes ready (harmless: a later
--       fill deploys instead), and
--       an amber note when the last overdrive phrase is too close to the end
--       for its overdrive to be spent.
--       Harmonies get their own card when the song has HARM1 and HARM2: scored
--       at HARM1's phrase ends, each extra part singing a phrase adds 10%, and
--       the stars need the same as solo vocals, so gold comes easier.
--       Vocals deploy in the game's freestyle sections (gaps of 0.6 s or more
--       between sung notes, half a second of noise to deploy). Read-only; press
--       Calculate after changing the
--       charts - it is meant to sit beside the Instrument Helper's Overdrive
--       tab.
--     - Venue: the lighting keyframe trigger is now written [prev], not
--       [previous]. [prev] is what the game, the RBN documentation and the
--       official charts use; [previous] is not a game event.
--       Manual gen inserts [prev], and Validate accepts it and lists any
--       [previous] as "not a game event: the keyframe trigger is [prev]" -
--       swap those by hand. Regenerate keyframes and Remove still find the
--       old spelling, so they clean it up.
--     - Animation > Beat no longer writes two downbeats in a row, which the
--       game reports as an error. It could happen at a very short bar: a 1/4
--       or 2/8 bar, or a 2/4, 3/8 or 4/8 bar in half time with the downbeat
--       on every bar. The short bar's downbeat is now written as an upbeat,
--       so the full bar after it keeps its own; in a run of short bars every
--       other one keeps the downbeat.
--     - Beats are now always at least an 8th apart, as the game requires. In
--       a 5/16, 9/16 or 13/16 bar the last beat used to land a 16th before
--       the next bar line; it is now left out, as the official charts do.
--     - Both changes are listed in the result by measure, so you can check
--       the bar - a very short bar may belong with its neighbour. Common
--       time signatures (4/4, 3/4, 6/8, 5/8, 7/8 ...) are unchanged.
--     - The Beat buttons are now "Normal", "Half" and "Double" under a
--       "Generate beats" heading, so the row fits a narrower window.
--     - New "Double": a BEAT note on every 8th. Official
--       charts use it for slow songs whose tempo map runs at half the felt
--       pulse (Snuff, The Only Exception) and for double-time sections
--       (American Pie) - select the section to write only that part. Its
--       downbeat goes every 4 beats in a bar (beats 1 and 3 in 4/4, as the
--       slow songs do; the default) or on every bar.
--     - Good to know, now in the Beat sub-tab: the BEAT track also sets how
--       fast overdrive drains. A full meter lasts 32 BEAT notes, so it lasts
--       twice as long in a half-time part and half as long in a double-time
--       one.
--     - Events > Manual gen: dj_intro now inserts [prc_dj_intro_a] to _d, the
--       names the game knows. With letter suffix off it still adds the
--       letter: the row shows "(letter required)" and the result says why.
--       The reverse case now says so too: names with no lettered form
--       ([prc_bre], [prc_a1], ...) show "(no lettered form)" when letter
--       suffix is on, and the result explains the plain insert.
--       The bare [prc_dj_intro] it offered before (a typo in the community
--       events list) still works as a practice section, but it is not in the
--       game's section names, so it is not translated: every game language
--       shows the event text "prc_dj_intro" instead of its own name for it.
--       Rename any you have.
--     - Animation > Drums: soft hits now follow the velocity of the Expert
--       gems, so the author decides note by note. "Soft snare hits by
--       velocity (ghost strokes)": snares under the Soft below velocity (50
--       by default) get the soft notes - in the game a ghost stroke, the
--       stick hovers and the snare on the kit does not move. "Crash hits by
--       velocity (choke / soft)": crashes under Choke below (20 by default)
--       become chokes (the cymbal grabbed, notes 40 / 41, written instead of
--       the hit), those under Soft below (50) soft crashes (still a hit,
--       lighter), the rest normal hits. Either order works: the lower
--       threshold takes the lowest velocities. Hi-hat and ride are not
--       affected. The Drums options are now grouped under Cymbals, Hi-hat
--       and Snare.
--     - Animation > Drums, open hi-hats (the pedal note 25, held while the
--       hat is open), in a new Hi-hat section. The Blue cymbal choice is now
--       Ride / Hi-hat; new "Open the hat on blue hi-hat hits" (off by
--       default) also holds the pedal under those hits so the hat opens -
--       Harmonix's way (official charts open 83% of blue hi-hat hits), which
--       not every community chart follows. Before, blue as the hi-hat wrote
--       only the hands, so the hat stayed closed, as it still does with the
--       new option off. New "Open hi-hat by velocity": yellow hi-hat gems above Open
--       above (100 by default, so the usual 96 / 100 stay closed) open, for
--       charts that keep blue for the ride. A run of open hits shares one
--       pedal note, from a 16th before the first to the next hi-hat hit, as
--       official charts do. With either on, earlier open-hat pedal notes in
--       range are replaced; the foot-keeping-time 25s stay. Off, note 25 is
--       never touched, as before.
--       The game ignores gem velocity and most charts use one velocity on
--       every gem, so nothing changes until you set some. The result counts
--       the soft snares, soft crashes and chokes written. "Crash riding:
--       alternate soft and hard" works as before. A project saved with the
--       old "Soft snare and crash hits" option or the soft options on keeps
--       every hit soft, as before.
--     - Metadata > Genre has two views: Animation style (new, shown first)
--       and the Genre converter. Animation style lists the four band
--       animation styles - Rocker, Banger, Dramatic, Spazz - and which major
--       genres give each: the genre decides how the whole band moves in game
--       and which directed camera cuts exist. Magma has no other setting for
--       it (community tools such as MiloMod can change it afterwards). The
--       converter's result now names the style of each suggested genre.
--     - Venue: no more [first] on every manual lighting change. In game a
--       lighting preset always starts on its first look, so a [first] there
--       did nothing (the game's own code, read from the RB3 decompilation).
--       Themes gen, Section gen, Keyframes and Manual gen's keyframe Add now
--       write only the [next] train after the lighting event. Regenerate
--       keyframes also removes the old [first]s in the spans it rewrites.
--     - Validate lighting/blends no longer asks for a [first] on each manual
--       change. Instead it lists keyframe events that do nothing in game -
--       under a preset that ignores them (all but verse, chorus, manual_cool,
--       manual_warm, dischord, stomp), before the first lighting event, or a
--       [first] while the preset is still on its first look - as advice, not
--       as issues.
--     - Manual gen: [first] can be inserted anywhere now. Where a keyframe
--       event would do nothing, the row shows "(does nothing here)" and the
--       result says why. [next] is first in the Special list, and the
--       keyframe events have their own tooltips: most manual presets have
--       two looks, so [next] and [prev] land on the same one; verse and
--       chorus have four in arenas, big clubs and festivals. [first] always
--       goes to the first look, whichever look is showing.
--     - New Directed Moves window (its own script, rock_band_directed_moves_vkr.lua):
--       what the game can show for each directed camera cut, read from the
--       game's own venue files (all 44 venues) - a companion to Manual gen
--       and Preview. Open it from General > Other tools or from the new
--       "Standalone windows" section of Venue > Actions, which also opens the
--       Venue Preview window.
--     - Validate camera stacks: a directed cut that a band lineup cannot play
--       is now an issue of its own - directed cuts have no fallback, so the
--       game ignores them and the camera keeps its shot (it used to say a
--       band shot plays). Spots where a normal shot falls back for a lineup
--       are listed as advice, no longer counted as issues.
--     - Venue > Preview: when no stacked camera shot fits the chosen Players
--       lineup, the event's name turns amber with a * and the picture shows
--       what the game plays instead - the remaining member's shot for a duo,
--       All (near) for a one-member shot (one of the band shots it picks at
--       random); hover for which. A directed cut that cannot play is red
--       (ignored, the previous shot stays). Replaces the red "No suitable
--       event" card.
--     - Venue > Preview: Show has a new Current only H option - the current
--       camera, lighting and post-process event side by side on one row.
--       The old Current only is now Current only V.
--     - The Structure row's tooltip notes that numbered verses and choruses
--       get their own background clips in the video venues.
--     - Fixed: opening another project in the same project tab (File > Open,
--       recent projects) was not noticed, so the previous song's Metadata
--       results (Difficulty, Song key, Score), track selections and settings
--       stayed on screen. Only switching project tabs reset the window. Both
--       now do.
--     - Secondary text (hints, empty states, "not set", minor headings) is a
--       lighter grey that is easier to read. The same grey is used everywhere.
--     - One colour per meaning in every window: Venue > Preview's "blending
--       now" line and its fallback camera name use the same amber as every
--       other warning (they were a lighter amber); the Venue Players row's
--       idle blue is a brighter sky blue, the blue used everywhere now.
--     - Copy result (the footer) now also copies results a tab draws itself:
--       Metadata > Difficulty, Song key and Score. It copies what is on
--       screen, in the same order, as plain text - the difficulty dots as
--       "3 of 5 dots", the ruler as its band and position, a key's notes
--       (a tooltip on screen) written out, and Score's findings marked "!"
--       (warning), "?" (advice) or "-" (a note). Difficulty's measured
--       values are included only while they are shown, which replaces the
--       work-in-progress "Copy details" button (removed). A copy no longer
--       includes the status line's "Result copied to the clipboard." when
--       pressed twice.
--     - General > Actions: new "Select song until end" button. It sets the
--       time selection from bar 1 to the [end] event on the EVENTS track, ready
--       for rendering the song audio at the right length. If the EVENTS track
--       is missing, or it has no [end] or more than one, the selection is left
--       alone and the result says why (listing each [end] when there are
--       several).
--     - Fixed: General > Actions "Fade out" stopped with "Could not create
--       Volume envelope" unless the SONG AUDIO track already had a volume
--       envelope. It now creates the envelope itself, and one Undo removes the
--       envelope together with the fade.
--
--   v0.9.63
--     - The instrument tools moved to a new script, the Rock Band Instrument
--       Helper: the Difficulty, Overdrive, Tab Input and MIDI tabs, the
--       work-in-progress Drums, Keys and Guitar tabs, and General > Actions
--       "Remove 2x kicks". Open it from General > Other tools. This helper
--       keeps stem import and audio alignment, the tempo map, the workflow
--       checklist, Venue and Metadata.
--     - Settings saved in a project before this version keep working for the
--       tabs that stayed here. Those of the moved tabs are not carried over
--       to the Instrument Helper; the next Save here drops them.
--     - General > Settings > Show WIPs? now shows only the Tempo Map tab. The
--       Instrument Helper has its own switch for its WIP tabs.
--     - Workflow is its own tab now, no longer a General sub-tab.
--     - New Animation tab, between Workflow and Events. Its Beat sub-tab
--       writes the BEAT track from measure 1 up to the [end] event, or inside
--       the time selection: a downbeat note on each bar's first beat and an
--       upbeat note on every other quarter note, in every time signature (7/8 = four notes, as the
--       official charts do). "Generate half-time beats" puts a note on every
--       other quarter, for animations; its downbeat goes on every other bar
--       (as CAT and most official halved songs do) or on every bar. The beat
--       just before [end] always gets a note, as Magma requires. Needs a
--       BEAT track and an [end] event; existing BEAT notes in the range are
--       replaced. One undo step.
--     - Animation > Character writes the band members' animation states on
--       each part: [play], [mellow] or [intense] (picked per part, or Set all)
--       one beat before the part plays, [idle] one beat after it stops for a
--       long rest (3 bars for instruments, 2 for vocals by default, both
--       adjustable, or never), [idle] at bar 3 when a part starts later, and
--       [idle_realtime] after its last note. Covers PART DRUMS and DRUMS_2X,
--       GUITAR, BASS, KEYS, VOCALS and HARM1, from their Expert notes; muted
--       tracks are skipped. Manual mode inserts any state at the playhead, or
--       replaces the one there, including Idle intense, Play solo (guitar and
--       bass) and the drummer's two ride options, and shows the part's state at the playhead and the bar it
--       started from. Each state's tooltip carries its RBN description.
--     - Animation > Drums writes the drummer's animation notes (which drum or
--       cymbal, which hand, the kick) on PART DRUMS and PART DRUMS_2X from the
--       Expert gems. The hands follow the official charts: they alternate only
--       when hits come fast, in step with the beat, moving around the kit
--       without crossing the arms, disco hi-hat 16ths alternate, a lone blue
--       cymbal is a crash accent, and slow snares vary between hands. Measured
--       against the official charts, the hand is right on 93% of one-hand hits
--       (CAT's rules: 84%). Options as in CAT - default crash, soft hits, the
--       snare + yellow tom flam (now on by default), min cymbal hits - plus
--       Blue cymbal (ride or open hi-hat), slow snare variety, soft / hard
--       crash riding and a late left hand on flams. The hi-hat pedal (note 25)
--       is left to you. Notes are written in one pass, not one by one.
--     - New Events tab for the EVENTS track tools, with two sub-tabs.
--       General holds "List event sections" (moved from Venue > Actions);
--       Manual gen is the former Venue > Events sub-tab.
--     - Events > Manual gen "Insert bookends" now follows the official charts:
--       [crowd_realtime] (the idle crowd) at measure 1 in place of
--       [crowd_normal], [prc_intro] at measure 2 (was 1) with [crowd_noclap]
--       and [crowd_normal] (a placeholder: change it to mellow or intense to
--       suit the song), and [crowd_noclap] on [prc_outro]. A re-run used to
--       delete every [crowd_normal] in the song; crowd events are now removed
--       only on the bookend measures, so crowd changes you placed mid-song stay.
--     - Venue > Manual gen: new Target choice, VENUE (as before) or Subtracks.
--       Subtracks writes each event to its own Sub VENUE track (made by Venue >
--       Actions > Copy all to subtracks): cameras, lighting, post proc, special
--       and keyframes each to their track. Blend, keyframe generation and Remove
--       work on the subtracks too. If a subtrack is missing, you are told to
--       create them first. Run Copy all to main track when done - the game reads
--       only VENUE.
--     - Venue > Keyframes: the same Target choice (one setting, shared with Manual
--       gen). Subtracks reads the manual lighting events on VENUE lighting and
--       writes the regenerated keyframes to VENUE keyevents.
--     - Venue > Manual gen: new Insert choice, Add (as before) or Replace.
--       Replace first removes the events of the same kind at the playhead, then
--       adds the new one: a new lighting preset replaces the old one but leaves a
--       post-process effect on the same spot alone. Cameras count as one kind, so
--       a new shot replaces a whole camera stack there. Works with both targets.
--     - Venue > Actions "Generate sing along": the bassist's notes (from HARM3)
--       now follow HARM2's phrase markers, as the game does. HARM3's own phrase
--       markers are ignored. Before, a HARM3 without phrase markers - the usual
--       way to chart it - gave the bassist no sing-along notes at all.
--     - New footer, always at the bottom of the window: the time selection,
--       the status line, Copy result (the status and result to the clipboard)
--       and Undo. The tabs scroll above it, so on a short window these no
--       longer scroll out of sight. The track dropdowns now update on their
--       own: adding, renaming or deleting a track, or adding an item to one,
--       shows up within about a second. The Refresh tracks button is gone.
--     - General > Actions "Import stems": the lead vocal stem now goes to the
--       VOCALS AUDIO track. It looked for VOCAL AUDIO, which the template does
--       not have, so the vocal stem was always listed as skipped (track not
--       found) instead of imported.
--     - New Metadata > Song key sub-tab (Beta). Suggests the vocal tonic note
--       and whether the song is major or minor - the vocal_tonic_note and
--       song_tonality values in songs.dta - from the charted notes. Four
--       results side by side: PART VOCALS alone, with the harmonies, with Pro
--       Keys, and Pro Keys alone as a second opinion, so you can see what each
--       part says. Each shows the runner-up key and how clear the lead is;
--       hover a key to see its notes. Notes marked unpitched (#) are left out.
--     - Read from: Charted MIDI (default) or Audio stems (experimental), one at
--       a time. Audio stems reads a vocal track and a bass track - each that
--       part on its own (a stem or an AI-separated part, not the full mix) -
--       and gives one result, from both when both have enough notes. Useful
--       before the vocals are charted, and as a second opinion after. Tracks
--       named VOCALS AUDIO and BASS AUDIO are picked automatically. It
--       runs in the background with a progress bar and Cancel, so the window
--       stays usable on slower computers.
--     - Check a key, below the suggestions: pick any key (a suggestion, or one
--       from Tunebat or a chord chart) and see, for PART VOCALS, HARM1-3 and
--       Pro Keys separately, how many notes fall outside it and in which bars -
--       where to look for a note charted a semitone off.
--       A suggestion to verify by ear, not an answer: it is only as accurate as
--       the chart. Read-only.
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
    _dir  .. 'lib/reaper_helper_common.lua',
    _dir  .. 'lib/reaper_helper_ui.lua',
    _dir  .. 'lib/reaper_dsp.lua',
    _dir  .. 'lib/reaper_midi_helpers.lua',
    _dir  .. 'lib/reaper_script_links.lua',
    -- Difficulty suggester. reaper_difficulty_score.lua must precede its vocals
    -- companion (which appends to SCORE_FACTOR_KEYS), and both precede the models.
    _dir  .. 'lib/reaper_difficulty_score.lua',
    _dir  .. 'lib/reaper_difficulty_score_vocals.lua',
    _dir  .. 'lib/reaper_difficulty_tiers.lua',
    _dir  .. 'lib/reaper_difficulty_predict.lua',
    _dir  .. 'lib/reaper_difficulty_models.lua',
    _dir  .. 'lib/reaper_difficulty_read.lua',
    _dir  .. 'lib/reaper_key_detect.lua',
    _dir  .. 'lib/reaper_key_profiles.lua',
    _dir  .. 'lib/reaper_key_audio.lua',
    _dir  .. 'lib/reaper_score_sim.lua',
    _dir  .. 'lib/reaper_score_read.lua',
    _mdir .. 'defaults.lua',
    _mdir .. 'settings.lua',
    _mdir .. 'helpers.lua',
    _mdir .. 'venue.lua',
    _mdir .. 'venue_awareness.lua',
    _mdir .. 'animation_beat.lua',
    _mdir .. 'animation_character.lua',
    _mdir .. 'animation_drums.lua',
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
    _mdir .. 'difficulty_explain.lua',
    _mdir .. 'difficulty_report.lua',
    _mdir .. 'difficulty_suggester.lua',
    _mdir .. 'metadata_genres.lua',
    _mdir .. 'metadata_genres_ext.lua',
    _mdir .. 'metadata_genres_lookup.lua',
    _mdir .. 'song_key.lua',
    _mdir .. 'song_key_audio.lua',
    _mdir .. 'ui_venue.lua',
    _mdir .. 'ui_venue_section_gen.lua',
    _mdir .. 'ui_venue_manual.lua',
    _mdir .. 'ui_venue_events.lua',
    _mdir .. 'ui_venue_preview.lua',
    _mdir .. 'ui_venue_keyframes.lua',
    _mdir .. 'ui_venue_players.lua',
    _mdir .. 'ui_workflow.lua',
    _mdir .. 'ui_animation.lua',
    _mdir .. 'ui_metadata_genre.lua',
    _mdir .. 'ui_metadata_key.lua',
    _mdir .. 'ui_metadata_score.lua',
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
dofile(_dir  .. 'lib/reaper_helper_common.lua')
dofile(_dir  .. 'lib/reaper_helper_ui.lua')
dofile(_dir  .. 'lib/reaper_dsp.lua')
dofile(_dir  .. 'lib/reaper_midi_helpers.lua')
dofile(_dir  .. 'lib/reaper_script_links.lua')
dofile(_dir  .. 'lib/reaper_difficulty_score.lua')
dofile(_dir  .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_dir  .. 'lib/reaper_difficulty_tiers.lua')
dofile(_dir  .. 'lib/reaper_difficulty_predict.lua')
dofile(_dir  .. 'lib/reaper_difficulty_models.lua')
dofile(_dir  .. 'lib/reaper_difficulty_read.lua')
dofile(_dir  .. 'lib/reaper_key_detect.lua')
dofile(_dir  .. 'lib/reaper_key_profiles.lua')   -- generated; read by song_key.lua
dofile(_dir  .. 'lib/reaper_key_audio.lua')      -- uses reaper_dsp.lua's YIN core
dofile(_dir  .. 'lib/reaper_score_sim.lua')      -- Metadata > Score (pure)
dofile(_dir  .. 'lib/reaper_score_read.lua')     -- uses reaper_difficulty_read.lua's readers

-- Window title with this script's own @version, read from the header above.
-- ui.lua passes it to ImGui_Begin; the "###" id inside keeps saved window
-- geometry across version bumps. See ScriptWindowTitle.
WINDOW_TITLE = ScriptWindowTitle('Rock Band General Helper', _script)

dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'settings.lua')
dofile(_mdir .. 'helpers.lua')
dofile(_mdir .. 'venue.lua')
dofile(_mdir .. 'venue_awareness.lua')
dofile(_mdir .. 'animation_beat.lua')       -- uses FindEventTime from venue_awareness.lua
dofile(_mdir .. 'animation_character.lua')
dofile(_mdir .. 'animation_drums.lua')
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
dofile(_mdir .. 'difficulty_explain.lua')
dofile(_mdir .. 'difficulty_report.lua')   -- consumes DifficultyAnnotate's output
dofile(_mdir .. 'difficulty_suggester.lua')
-- Genre converter: vocabulary, then the authored mapping, then the lookup that
-- reads both. metadata_genres_lookup.lua touches them only at call time, but the
-- load order still states the dependency.
dofile(_mdir .. 'metadata_genres.lua')
dofile(_mdir .. 'metadata_genres_ext.lua')
dofile(_mdir .. 'metadata_genres_lookup.lua')
dofile(_mdir .. 'song_key.lua')
dofile(_mdir .. 'song_key_audio.lua')
dofile(_mdir .. 'ui_venue.lua')
dofile(_mdir .. 'ui_venue_section_gen.lua')
dofile(_mdir .. 'ui_venue_manual.lua')
dofile(_mdir .. 'ui_venue_events.lua')
dofile(_mdir .. 'ui_venue_preview.lua')
dofile(_mdir .. 'ui_venue_keyframes.lua')
dofile(_mdir .. 'ui_venue_players.lua')
dofile(_mdir .. 'ui_workflow.lua')
dofile(_mdir .. 'ui_animation.lua')
dofile(_mdir .. 'ui_metadata_genre.lua')
dofile(_mdir .. 'ui_metadata_key.lua')
dofile(_mdir .. 'ui_metadata_score.lua')
dofile(_mdir .. 'ui_metadata.lua')
dofile(_mdir .. 'ui.lua')  -- also calls r.defer(Loop) at end

-- Startup initialisation (runs after all modules are loaded)
local _autoloaded = LoadSettings()
if _autoloaded then S.status = 'Loaded saved settings.' end
SetDefaultTracks()
