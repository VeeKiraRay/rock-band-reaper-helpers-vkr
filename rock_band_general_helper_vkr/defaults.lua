-- Global state, constants, and tooltip text
-- Requires: nothing (loaded first)

----------------------------------------------------------------------
-- Valid VENUE text events (Rock Band Network specification)
-- The lighting keyframe triggers are [first] / [next] / [prev]: the RBN doc's
-- spelling, the only three the game's keyframe code knows, and what official
-- charts use. [previous] is not a game event (VENUE_KEYFRAME_TYPO).
----------------------------------------------------------------------
VENUE_KEYFRAME_TYPO = '[previous]'
VENUE_VALID = {}
do
    local _list = {
        '[bonusfx]','[bonusfx_optional]',
        '[coop_all_behind]','[coop_all_far]','[coop_all_near]',
        '[coop_front_behind]','[coop_front_near]',
        '[coop_d_behind]','[coop_d_near]',
        '[coop_v_behind]','[coop_v_near]',
        '[coop_b_behind]','[coop_b_near]',
        '[coop_g_behind]','[coop_g_near]',
        '[coop_k_behind]','[coop_k_near]',
        '[coop_d_closeup_hand]','[coop_d_closeup_head]',
        '[coop_v_closeup]',
        '[coop_b_closeup_hand]','[coop_b_closeup_head]',
        '[coop_g_closeup_hand]','[coop_g_closeup_head]',
        '[coop_k_closeup_hand]','[coop_k_closeup_head]',
        '[coop_dv_near]','[coop_bd_near]','[coop_dg_near]',
        '[coop_bv_behind]','[coop_bv_near]',
        '[coop_gv_behind]','[coop_gv_near]',
        '[coop_kv_behind]','[coop_kv_near]',
        '[coop_bg_behind]','[coop_bg_near]',
        '[coop_bk_behind]','[coop_bk_near]',
        '[coop_gk_behind]','[coop_gk_near]',
        '[directed_all]','[directed_all_cam]','[directed_all_lt]','[directed_all_yeah]',
        '[directed_bre]','[directed_brej]','[directed_crowd]',
        '[directed_drums]','[directed_drums_pnt]','[directed_drums_np]',
        '[directed_drums_lt]','[directed_drums_kd]',
        '[directed_vocals]','[directed_vocals_np]','[directed_vocals_cls]',
        '[directed_vocals_cam_pr]','[directed_vocals_cam_pt]',
        '[directed_stagedive]','[directed_crowdsurf]',
        '[directed_bass]','[directed_crowd_b]','[directed_bass_np]',
        '[directed_bass_cam]','[directed_bass_cls]',
        '[directed_guitar]','[directed_crowd_g]','[directed_guitar_np]',
        '[directed_guitar_cls]','[directed_guitar_cam_pr]','[directed_guitar_cam_pt]',
        '[directed_keys]','[directed_keys_cam]','[directed_keys_np]',
        '[directed_duo_drums]','[directed_duo_bass]','[directed_duo_guitar]',
        '[directed_duo_kv]','[directed_duo_gb]','[directed_duo_kb]','[directed_duo_kg]',
        '[bloom.pp]','[bright.pp]','[clean_trails.pp]','[contrast_a.pp]',
        '[desat_blue.pp]','[desat_posterize_trails.pp]',
        '[film_16mm.pp]','[film_b+w.pp]','[film_blue_filter.pp]',
        '[film_contrast.pp]','[film_contrast_blue.pp]','[film_contrast_green.pp]',
        '[film_contrast_red.pp]','[film_sepia_ink.pp]','[film_silvertone.pp]',
        '[flicker_trails.pp]','[horror_movie_special.pp]',
        '[lighting ()]','[first]','[prev]','[next]',
        '[lighting (verse)]','[lighting (chorus)]',
        '[lighting (manual_cool)]','[lighting (manual_warm)]',
        '[lighting (dischord)]','[lighting (stomp)]',
        '[lighting (loop_cool)]','[lighting (loop_warm)]',
        '[lighting (harmony)]','[lighting (frenzy)]',
        '[lighting (silhouettes)]','[lighting (silhouettes_spot)]',
        '[lighting (searchlights)]','[lighting (sweep)]',
        '[lighting (strobe_slow)]','[lighting (strobe_fast)]',
        '[lighting (blackout_slow)]','[lighting (blackout_fast)]',
        '[lighting (flare_slow)]','[lighting (flare_fast)]',
        '[lighting (bre)]', '[lighting (intro)]', '[lighting (blackout_spot)]',
        '[photo_negative.pp]','[photocopy.pp]','[posterize.pp]',
        '[ProFilm_a.pp]','[ProFilm_b.pp]','[ProFilm_mirror_a.pp]',
        '[ProFilm_psychedelic_blue_red.pp]','[shitty_tv.pp]','[space_woosh.pp]',
        '[video_a.pp]','[video_bw.pp]','[video_security.pp]','[video_trails.pp]',
    }
    for _, v in ipairs(_list) do VENUE_VALID[v] = true end
end

-- Directed camera cuts closer than this to the next camera event may be too short.
DIRECTED_GAP_MIN = 2.0

MIDI_META_NAMES = {
    [1] = 'Text', [2] = 'Copyright', [3] = 'Track Name',
    [4] = 'Instrument Name', [5] = 'Lyric', [6] = 'Marker', [7] = 'Cue Point',
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
S = {
    status                = 'Ready.',
    last_result           = nil,
    -- Tempo map settings (persisted)
    tm_rms_threshold      = 0.15,
    tm_rms_window_ms      = 10,
    tm_fb_rms_threshold   = 0.10,
    tm_fb_rms_window_ms   = 10,
    tm_fb_use_flux        = false,  -- apply onset-flux transform to fallback source
    tm_search_window_ms   = 100,
    tm_drift_threshold_ms = 30,
    tm_bpm_failsafe       = 10.0,
    tm_first_measure      = 3,
    tm_timesig_num        = 0,
    tm_timesig_denom      = 4,
    tm_timesig_text       = '',   -- UI buffer; '' = inherit
    tm_override_failsafe  = false,
    tm_autotune_density   = 0,    -- expected onsets/measure for auto-tune density guard (0 = disabled)
    -- Tempo map track indices (not persisted - set by SetDefaultTracks; -1 = none)
    tm_kick_idx           = -1,
    tm_snare_idx          = -1,
    tm_kit_idx            = -1,
    tm_fallback_idx       = -1,
    -- Metadata > Difficulty: the last set of suggestion records from
    -- SuggestProjectDifficulties(). SESSION-ONLY and deliberately never persisted - a
    -- prediction is derived from the charts as they are right now, and a saved one would
    -- go stale the moment the author edits a note while still looking authoritative.
    -- Cleared on project switch alongside the track indices; nil = not scanned yet.
    diff_suggestions      = nil,
    -- Show the raw factor measurements behind each suggestion. "peak attack rate 4.51,
    -- +1.8 sd" is a debugging view, meaningful to someone comparing against the
    -- calibration corpus and noise to everyone else; the plain-language bullets above it
    -- say the same thing in words.
    --
    -- SESSION ONLY, DELIBERATELY NOT PERSISTED. Its control lives behind
    -- S.show_wip_tabs, so a saved value could come back in a project where the checkbox
    -- is not on screen - leaving a Details panel open with nothing visible to close it,
    -- and no way to tell which of the two flags put it there. Starting from off every
    -- session means the panel's visibility always has exactly one explanation.
    diff_show_factors     = false,
    -- Metadata > Score: the last ScoreProjectParts() result (nil = not calculated).
    -- Session-only and cleared on project switch, like diff_suggestions above and for
    -- the same reason.
    score_result          = nil,
    -- Metadata > Song key: the last SuggestProjectSongKey() result. Session-only and
    -- cleared on project switch, like diff_suggestions above and for the same reason.
    key_suggestion        = nil,
    -- Metadata > Song key > Check a key: the key being checked (tonic 0-11, minor).
    -- Session-only; set to the best suggestion on each run, cleared on project switch.
    key_check_tonic       = nil,
    key_check_minor       = false,
    -- Metadata > Song key, audio mode: the vocal and bass tracks (REAPER indices, -1 =
    -- none). Not persisted, like every track index; SetDefaultTracks picks VOCALS
    -- AUDIO and BASS AUDIO. key_audio is the last SuggestAudioSongKey() result.
    key_audio_idx         = -1,
    key_bass_idx          = -1,
    key_audio             = nil,
    -- Which source the tab reads: 1 = charted MIDI (default), 2 = audio stems. Session-only.
    key_mode              = 1,
    -- Metadata > Genre: the two combo positions. SESSION ONLY, DELIBERATELY NOT
    -- PERSISTED - this sub-tab is a lookup over two static tables and says nothing about
    -- the project, so a saved position would restore one project's answer into another
    -- and mean nothing in either.
    -- genre_ext_idx addresses the CURRENT family's list, so changing genre_family_idx
    -- must reset it (see DrawForward in ui_metadata_genre.lua).
    genre_family_idx      = 1,
    genre_ext_idx         = 1,
    genre_mode            = 1,    -- 1 = Animation style, 2 = Genre converter (session only too)
    -- Cached filtered track lists (not persisted - rebuilt by RefreshTrackLists)
    all_track_list        = nil,
    audio_track_list      = nil,
    midi_track_list       = nil,
    -- Venue themes (venue_themes persisted by name only; idx/table re-resolved at Venue tab open)
    venue_theme_idx       = 0,    -- 0 = no theme; 1..n indexes venue_themes
    venue_themes          = nil,  -- lazy-loaded from resources/themes/ folder; NOT persisted
    venue_theme_name      = '',   -- persisted: empty = no theme, else stem filename
    venue_keyframe_align  = 0,    -- 0=section start, 1=closest beat, 2=downbeat; 3-7=instrument-aware
    venue_kf_inst_subdiv  = 0,    -- 0=every beat, 1=every half beat, 2=every quarter beat (instrument modes 3-7 only)
    venue_cam_pacing        = 0,    -- 0=theme default, 1=minimal, 2=slow, 3=medium, 4=fast, 5=crazy, 6=custom
    venue_cam_pacing_custom = 16,   -- custom camera interval in 16ths; only used when venue_cam_pacing==6
    venue_cam_pacing_jitter = true,  -- include ±20% randomisation in camera cut intervals
    -- Section gen mode
    venue_sections          = nil,  -- array from ReadEventSections; NOT persisted (refreshed on demand)
    venue_sec_idx           = 1,    -- selected section index (1-based); NOT persisted
    venue_sec_configs       = {},   -- per-section configs keyed by SectionKey; persisted via vsec_v1
    venue_sec_mode          = 0,    -- 0 = Custom, 1 = Template
    venue_sec_tmpl_idx      = 0,    -- 1-based index into S.venue_themes; 0 = none
    venue_sec_tmpl_name     = '',   -- persisted theme stem name (mirrors venue_theme_name pattern)
    venue_preview_scale     = 1,    -- tooltip sprite display scale: 1 = 213×120 px, 2 = 426×240 px
    venue_preview_animate   = true, -- tooltip sprite animation: false = show middle frame only
    venue_preview_tab_scale = 1,    -- Preview sub-tab inline sprite scale (independent of tooltip scale)
    venue_preview_combo     = 0,    -- 0=Bass+Guitar, 1=Bass+Keys, 2=Guitar+Keys
    venue_preview_show_mode = 0,    -- 0=current only V, 1=surrounding events, 2=current only H
    -- Manual gen (not persisted - session state only)
    venue_mg_coop        = '',   -- full event e.g. '[coop_all_behind]'
    venue_mg_directed    = '',   -- bare name e.g. 'directed_all'
    venue_mg_lighting    = '',   -- bare name e.g. 'loop_warm'
    venue_mg_postproc    = '',   -- name with ext e.g. 'bloom.pp'
    venue_mg_special     = '',   -- full event e.g. '[bonusfx]'
    venue_mg_kf_rate     = 2,    -- keyframe rate in beats (1-8)
    venue_mg_remove_type = 0,    -- 0=Camera 1=Lighting 2=PostProc 3=Special 4=All
    venue_mg_target      = 0,    -- 0=VENUE 1=Sub VENUE tracks (persisted: 'vmgt')
    venue_mg_replace     = 0,    -- 0=Add 1=Replace same family at the playhead (persisted: 'vmgr')
    -- Keyframes tab (not persisted - session state only)
    venue_kf_rate        = 2,    -- keyframe rate in beats (1-8), independent of venue_mg_kf_rate
    -- Directed Moves window (not persisted - session state only)
    venue_cs_mode        = 1,    -- 1 = search by camera event, 2 = by keyword
    venue_cs_event       = '',   -- bare camera event, e.g. 'directed_guitar'
    venue_cs_text        = '',   -- keyword search text
    venue_cs_style       = '',   -- '' any, or 'R' / 'D' / 'B' / 'S'
    venue_cs_gender      = '',   -- '' any, or 'M' / 'F'
    venue_cs_kind        = '',   -- '' any venue, or a venue kind ('arena', ...)
    venue_cs_lineup      = '',   -- '' all five, or 'no_keys' / 'no_guitar' / 'no_bass'
    -- Events tab (not persisted - session state only)
    venue_ev_sel         = {},   -- per-group selected base/event ('' = none), keyed by group key
    venue_ev_num         = {},   -- per-group number 0-9 (0 = bare form), keyed by group key
    venue_ev_letters     = true, -- 'Use letter suffix' checkbox
    venue_ev_mode        = 0,    -- reserved: 0 = EVENTS target (phase-2 mode radio)
    -- Sub VENUE tracks (not persisted - session state only)
    venue_subtrack_idx     = 0,    -- 0-based index into VENUE_SUBTRACKS (Actions tab dropdown)
    -- { message=.., on_confirm=function() ... end } - set by CopyAllSubtracksToMain when
    -- VENUE already has events; consumed by the confirm popup in ui_venue.lua.
    venue_subtrack_copy_pending = nil,
    -- Events > Metronome
    metronome_pulse      = 0,    -- hi-hat pulse: 0=Auto (by tempo) 1=8ths 2=16ths (persisted: 'emp')
    metronome_intro      = 0,    -- intro: 0=From COUNT IN 1=Count in from chart 2=Steady pulse (persisted: 'emi')
    -- Animation > Beat
    beat_half_style      = 0,    -- half-time downbeat: 0=every other bar 1=every bar (persisted: 'abhs')
    beat_double_style    = 0,    -- double-time downbeat: 0=every 4 beats 1=every bar (persisted: 'abds')
    -- Animation > Character
    char_active = { drums = 0, guitar = 0, bass = 0, vocals = 0, keys = 0 },
                                 -- per group: 0=[play] 1=[mellow] 2=[intense] (persisted: 'acsd' 'acsg' 'acsb' 'acsv' 'acsk')
    char_gap_inst_bars   = 3,    -- instruments idle in gaps of this many bars (4 QN) or more (persisted: 'acgi')
    char_gap_vox_bars    = 2,    -- vocals / HARM1, likewise (persisted: 'acgv')
    char_idle_gaps       = true, -- false = stay active through every gap (persisted: 'acig')
    char_mode            = 0,    -- 0=Generate 1=Manual (persisted: 'acmd')
    char_manual_part     = 1,    -- Manual part, index into CHAR_PARTS (not persisted)
    char_manual_state    = '[play]', -- Manual state, an event text from CHAR_STATES (not persisted)
    -- Animation > Drums (all persisted: 'adcr' 'admc' 'adfl' 'adsv' 'adsc' 'adss' 'adra' 'adfll',
    -- thresholds 'adsnb' 'adchb' 'adcyb', open hi-hat 'adoh' 'adoha' 'adbo'; the old combined 'adso' is still read: 1 = both soft
    -- options on. A project saved before the thresholds with a soft option on loads that
    -- option's soft threshold as 128 - every hit soft, as the option did then)
    drum_anim_crash         = 0,     -- default crash: 0 = crash 2, 1 = crash 1
    drum_anim_blue_hh       = false, -- blue cymbal = hi-hat (false = ride)
    drum_anim_blue_open     = false, -- blue hi-hat hits are open (pedal 25 held; Harmonix's way)
    drum_anim_min_cym       = 3,     -- fast cymbal hits in a row before the hands alternate
    drum_anim_open_hat      = false, -- open hi-hat by velocity (yellow hi-hat gems)
    drum_anim_open_hat_above = 100,  -- yellow hi-hat gems above this velocity: open (pedal 25 held)
    drum_anim_flam          = true,  -- snare + yellow tom = both hands on the snare
    drum_anim_snare_variety = true,  -- slow lone snares: right hand / both hands by context
    drum_anim_soft_cym      = false, -- crash hits by velocity: chokes and soft crash notes
    drum_anim_choke_below   = 20,    -- crash gems under this velocity: chokes (0 = none)
    drum_anim_soft_cym_below = 50,   -- other crash gems under this velocity: soft (still hit, lighter)
    drum_anim_soft_snare    = false, -- soft snare notes by velocity (ghost strokes: the kit snare does not move)
    drum_anim_soft_snare_below = 50, -- snare gems under this velocity: soft
    drum_anim_ride_alt      = false, -- riding a crash in 8ths alternates soft and hard
    drum_anim_flam_late     = false, -- a flam's left hand a 1/32 note late
    -- UI visibility (persisted)
    show_wip_tabs           = false, -- show the Tempo Map tab
    -- Workflow checklist (Workflow tab)
    workflow_files      = nil,  -- lazy-loaded from resources/workflow/ folder; NOT persisted
    workflow_file_idx   = 0,    -- 0 = none selected; 1..n indexes workflow_files; NOT persisted
    workflow_file_name  = '',   -- persisted (scalar blob): selected template's stem filename
    workflow_state      = {},   -- persisted via workflow_v1; keyed by CompositeKey(section, label)
    workflow_show_ts    = false, -- persisted (scalar blob): show "Completed on ..." under checked items
    workflow_hide_done  = false, -- persisted (scalar blob): hide checked items (and fully-checked sections)
}

----------------------------------------------------------------------
-- Tooltip text
----------------------------------------------------------------------
TIPS = {

    -- Metadata > Genre
    genre_mode_style =
        "Which band animation style each supported major genre gives in game.",
    genre_mode_converter =
        "Convert the genre you would call the song into the closest supported\n" ..
        "major genre and subgenre.",
    genre_family =
        "Narrows the genre list below.\n\n" ..
        "The full list runs past 200 entries, which is more than a\n" ..
        "single dropdown can be read from. Pick the broad family\n" ..
        "first and the second list holds only that family's genres.\n\n" ..
        "Changing the family resets the genre below it.",
    genre_pick =
        "The genre you would actually call this song.\n\n" ..
        "This list is deliberately wider than what Rock Band supports - it holds\n" ..
        "styles like Djent, Easycore and Synthwave that have no supported category\n" ..
        "of their own, which is the whole reason the conversion is needed.\n\n" ..
        "If your genre is missing, pick the nearest one in the same family, or use\n" ..
        "the other direction to browse what the supported list actually offers.",
    genre_candidates =
        "Some genres have more than one defensible home in the supported list.\n\n" ..
        "The reference catalogue of released songs mostly agrees with itself,\n" ..
        "so a single suggestion means the call is settled. Where two or three\n" ..
        "are shown, real songs in that style were genuinely filed both ways.\n\n" ..
        "The first is the usual pick. Each one says what\n" ..
        "would tip the choice toward it.",
    genre_see_also =
        "A pointer to a different genre in this list, not another Rock Band category.\n\n" ..
        "Some styles are named for what came after something else, so the\n" ..
        "genre you picked may not be the one you want. Post-Grunge suggests\n" ..
        "Grunge for a song that really belongs to the early 90s wave.\n\n" ..
        "Shown separately from the numbered suggestions because it answers a different\n" ..
        "question: those are where your genre goes, this is whether you picked it.",

    -- Metadata > Score
    score_calculate =
        "Work out each Expert part's full-combo score: without overdrive (what the\n" ..
        "stars are measured against), the star cut-offs, and with overdrive deployed\n" ..
        "as soon as it is useful - and so whether gold stars can be reached.\n\n" ..
        "Read-only, nothing is written. Results are not kept up to date: press again\n" ..
        "after changing the charts (for example the overdrive in the Instrument Helper).",
    score_stars =
        "Points needed for each star (1* to 5*, then gold), from the game's own tables:\n" ..
        "5 stars is below the full combo without overdrive; gold is above it and needs\n" ..
        "overdrive. Bonus points (solos, Big Rock Ending) count towards the stars at\n" ..
        "their own rate.",
    score_od =
        "A full combo with overdrive deployed as soon as it is useful: guitar, bass,\n" ..
        "keys and Pro Keys the moment the meter is half full - or, before a rest, at\n" ..
        "the next note - drums at the first fill the game shows, vocals in the first\n" ..
        "freestyle section, just before the singing comes back (a long instrumental\n" ..
        "break does not drain it). Whammy on every overdrive sustain.\n\n" ..
        "One exception, at the end: when that would leave the last overdrive unusable,\n" ..
        "one of the last three deploys is held - started later, just early enough to\n" ..
        "still be running when the next phrase comes in - so the last one is used too.\n" ..
        "The card says where.\n\n" ..
        "Not the best possible run - saving overdrive for a busier part can score\n" ..
        "more - so 'short of gold' means 'short with this simple plan'.",
    score_coverage =
        "How much of the part is played in overdrive with the plan above: the total\n" ..
        "length in bars, and the share of the part from its first note to its last.",
    score_pro =
        "Pro drums: kick, snare and cymbals earn 5 more per note, toms do not. The stars\n" ..
        "are measured as if every note earned it, so toms make gold a little harder.",
    score_vocals =
        "Vocals deploy in a freestyle section: a gap of more than 0.6 s between sung\n" ..
        "notes (not in the middle of a word), less a short margin at each end. Deploying\n" ..
        "takes half a second of unbroken noise into the mic (0.4 s in a short section),\n" ..
        "so a section has to be long enough for that after overdrive is ready.\n\n" ..
        "A phrase's points build up as its notes are sung, by sung time (each note's\n" ..
        "first 150 ms count a little less); overdrive doubles what is sung while it is on.\n\n" ..
        "Harmonies score at HARM1's phrase ends: the best-sung part gets the full\n" ..
        "phrase value, each other part singing in it 10% more. Only HARM1's overdrive\n" ..
        "counts, and any part's own freestyle section can deploy it. The stars are\n" ..
        "measured on HARM1's phrases like solo vocals, so the extra parts are pure\n" ..
        "gain - gold comes easier.",
    score_bre =
        "The Big Rock Ending pays for how you play it: every hit on a lane earns points\n" ..
        "for the time since that lane's last hit (up to 1.5 s), about 500 a second at\n" ..
        "most with all five lanes kept going. Paid at the end, only if you hit the final\n" ..
        "note, and never doubled by overdrive. The total here assumes that most.\n\n" ..
        "The star cut-offs count the BRE at only 100 a second, so a well-played BRE\n" ..
        "brings gold closer.",

    -- Metadata > Difficulty
    diff_suggest_refresh =
        "Score every Expert chart in this project and suggest a rank and tier for each.\n\n" ..
        "Read-only: nothing is written to the project, and no undo point\n" ..
        "is created. Results are not saved - re-run after editing a chart.\n\n" ..
        "The whole chart is scored. A time selection does not change the result.",
    diff_dots =
        "Rock Band shows an instrument's difficulty as five dots.\n\n" ..
        "Filled dots are how far up the scale the part sits: none for Warmup,\n" ..
        "two for Solid, five for Nightmare. Impossible fills all five in red.\n\n" ..
        "Two tiers share five filled dots because that is how the game displays them.",
    diff_ruler =
        "Where this chart landed between the tier it earned and the next one up.\n\n" ..
        "A tier is a threshold, so a chart sitting near either end could reasonably\n" ..
        "be called either tier - the marker shows how much room there was.\n\n" ..
        "An amber marker pinned to one end means the score ran past the end of\n" ..
        "the scale, so its real position is further out than the ruler can show.",
    -- Metadata > Song key
    key_analyze =
        "Read the charted vocals, harmonies and Pro Keys and suggest the\n" ..
        "vocal tonic note and whether the song is major or minor.\n\n" ..
        "Notes whose lyric is marked unpitched (#) are left out.\n\n" ..
        "Read-only: nothing is written to the project, and no undo point\n" ..
        "is created. Results are not saved - re-run after editing a chart.\n\n" ..
        "The whole song is read. A time selection does not change the result.",
    key_suggested =
        "The key whose scale and home note fit the charted notes best.\n\n" ..
        "A suggestion, not a measurement: verify it by ear or against a\n" ..
        "chord chart before entering it.",
    key_keys_only =
        "Pro Keys on its own, as a second opinion beside the vocals.",
    key_mode_midi =
        "Suggest the key from the charted notes: PART VOCALS, HARM1-3 and Pro Keys.",
    key_mode_audio =
        "Suggest the key from vocal and bass audio stems instead of the chart.\n\n" ..
        "Useful before the vocals are charted, and as a second\n" ..
        "opinion after.",
    key_audio_track =
        "A track with the lead vocal on its own. Avoid using the full mix - the\n" ..
        "pitch detected there would be whatever is loudest, which usually is not\n" ..
        "the vocals. Choose (none) to try what the bass stem alone produces.\n\n" ..
        "A track named VOCALS AUDIO is picked automatically.",
    key_bass_track =
        "A track with the bass guitar on its own. The bass keeps returning to the\n" ..
        "home note, so with the vocal it gives the best audio result. Leave it at\n" ..
        "(none) to use the vocal alone.\n\n" ..
        "A track named BASS AUDIO is picked automatically.",
    key_analyze_audio =
        "Read the picked vocal and bass tracks and suggest the vocal tonic note\n" ..
        "and whether the song is major or minor. Uses both when both give\n" ..
        "enough notes, otherwise whichever does.\n\n" ..
        "Read-only: nothing is written to the project, and no undo point\n" ..
        "is created. Takes a few seconds for a whole song.",
    key_check_button_audio =
        "Switch to Charted MIDI and show this key in Check a key, track by\n" ..
        "track - which charted notes fall outside it.",
    key_check_button =
        "Show this key in Check a key below, track by track.",
    key_check_pick =
        "The key to check. Starts on the best suggestion; set it to any\n" ..
        "key you want to compare, such as one from Tunebat or a chord chart.",
    key_scale =
        "The seven notes of the checked key, starting from its home note.\n\n" ..
        "Minor keys are listed as the natural minor scale.",
    key_share_out =
        "How many of this track's notes are not in the checked key. The\n" ..
        "notes are listed below with the bars they are in.\n\n" ..
        "Songs use such notes on purpose all the time - a blue note, or the\n" ..
        "raised 7th of a minor key (G# in A minor) - so they are not mistakes\n" ..
        "in themselves, and a chart should keep the pitch actually sung. They\n" ..
        "are where to look if a note may be charted a semitone off: a note\n" ..
        "that appears once or twice is worth a listen, one that repeats in\n" ..
        "the same places is almost always meant.\n\n" ..
        "In the official vocal charts, half the songs have under 3% of their\n" ..
        "notes outside the key their songs.dta lists, and about 1 in 5 has 15%\n" ..
        "or more - so the amber from 15% means worth a look, not wrong. Such\n" ..
        "songs often sit between major and minor; try the other one.",

    -- Metadata > Difficulty (continued)
    diff_show_factors =
        "Show the raw measurements behind each suggestion.\n\n" ..
        "This is a development view - useful for comparing a chart\n" ..
        "against the reference songs, and not needed to read the result.\n" ..
        "The bullet points above each card say the same thing in words.\n\n" ..
        "While shown, Copy result copies them too, with the model behind\n" ..
        "each number.\n\n" ..
        "Not saved: it starts off again next time the script is opened.",
    diff_suggest_why =
        "The chart properties on which this part is unusual,\n" ..
        "compared with the songs the model was fitted on.\n\n" ..
        "These are measurements, not causes: they describe what is distinctive\n" ..
        "about the chart rather than claiming which property produced the rank.\n\n" ..
        "The value column is the measurement; the last column is how\n" ..
        "many standard deviations it sits from the average charted song.",

    -- General tab
    import_stems    = "Pick a folder of stems and place each one on its template track,\n" ..
                      "at the same position as the SONG AUDIO item.\n\n" ..
                      "Only the folder itself is scanned, not folders inside it. Filenames are\n" ..
                      "matched by keyword, ignoring case (wav, mp3, ogg, flac, aif, m4a, wma, opus):\n" ..
                      "  vocal + back            -> DRYVOX2\n" ..
                      "  kick                    -> KICK AUDIO\n" ..
                      "  snare                   -> SNARE AUDIO\n" ..
                      "  piano, else keys, else accordion -> KEYS AUDIO\n" ..
                      "  bass (not drum)         -> BASS AUDIO\n" ..
                      "  guitar                  -> GUITAR AUDIO\n" ..
                      "  vocal (lead preferred)  -> VOCALS AUDIO\n" ..
                      "  drum                    -> KIT AUDIO\n" ..
                      "KIT AUDIO ignores single-piece files that also name crash, cymbal, hh,\n" ..
                      "kick, ride, snare, toms or bass. When several files fit, the shortest\n" ..
                      "name wins. Each file goes to one track only.\n\n" ..
                      "A track that already holds audio is skipped. Missing tracks, tracks with\n" ..
                      "no matching file, and files that matched nothing are listed in the result.\n\n" ..
                      "With the js_ReaScriptAPI extension a folder dialog opens; without it, pick\n" ..
                      "any file inside the stem folder. Requires SONG AUDIO. Fully undoable.",
    align_all_audio = "Align every single-item audio track in the project to the SONG AUDIO start position.\n\n" ..
                      "Tracks with zero audio items (MIDI tracks, empty tracks) are silently skipped.\n" ..
                      "Tracks with multiple audio items are skipped and listed in the result.\n" ..
                      "COUNT IN is always excluded - use Align count-in for that track.\n\n" ..
                      "Fully undoable.",
    align_count_in  = "Position COUNT IN clips at the standard count-in beat slots.\n\n" ..
                      "Reads the time signature from the project root tempo marker.\n" ..
                      "4/4:  m1 beats 1, 3  →  m2 beats 1, 2, 3, 4  (6 slots)\n" ..
                      "3/4:  m1 beat 1      →  m2 beats 1, 2, 3      (4 slots)\n" ..
                      "Other even time sigs use m1 beat 1 + midpoint, m2 all beats.\n\n" ..
                      "Clips beyond 6 are left untouched and reported.\n" ..
                      "Fully undoable.",
    list_venue      = "Find the VENUE track (by name) and read all its text events.\n\n" ..
                      "Reports: unknown events, consecutive camera repeats, directed cut spacing,\n" ..
                      "and a frequency count of every event used.",
    venue_lighting_postproc = "Find the VENUE track and list every [lighting*] and *.pp] (postproc)\n" ..
                      "text event, in timeline order, each with its measure/timestamp.",
    venue_validate_lighting =
                      "Check the VENUE track's lighting and post proc authoring. Read-only.\n\n" ..
                      "Keyframe events with no effect (listed as advice, not issues):\n" ..
                      "  - [first] / [next] / [prev] under a preset that ignores them (all\n" ..
                      "    but verse, chorus, manual_cool, manual_warm, dischord, stomp)\n" ..
                      "  - a [first] before any [next] / [prev] in its preset - a preset\n" ..
                      "    always starts on its first look, so it does nothing (this is\n" ..
                      "    the [first] older versions wrote on every lighting change)\n" ..
                      "  - keyframe events before the first lighting event\n\n" ..
                      "Blends:\n" ..
                      "  - a preset change fades only when the OUTGOING preset is restated\n" ..
                      "    shortly before it. Changes with no such anchor are listed, for\n" ..
                      "    lighting and post proc independently. A hard cut is valid, so\n" ..
                      "    these are only issues where you wanted a fade.\n\n" ..
                      "Always reads the whole track (judging a change needs the events before\n" ..
                      "it); with a time selection active, only issues inside it are reported.",
    venue_validate_camera =
                      "Check which of your stacked camera shots can actually play.\n" ..
                      "Read-only.\n\n" ..
                      "Only 4 members fit on stage and keys replaces a guitarist or\n" ..
                      "bassist, so a song charting guitar, bass AND keys has three\n" ..
                      "possible lineups. This replays the game's shot pick for every\n" ..
                      "lineup your project can produce, and reports:\n" ..
                      "  - shots that win under no lineup: they need an instrument that\n" ..
                      "    is never on stage, or a stacked sibling outranks them\n" ..
                      "    everywhere they would fit\n" ..
                      "  - directed cuts a lineup cannot play: directed cuts have no\n" ..
                      "    fallback, so the game ignores them and the camera keeps the\n" ..
                      "    shot it is on\n" ..
                      "  - the same shot written twice on one tick\n" ..
                      "  - shots a few ticks apart that were meant to be stacked: the\n" ..
                      "    game reads those as two cuts, so the second replaces the first\n\n" ..
                      "Also listed, but not counted as issues: fallback spots, where a\n" ..
                      "lineup has no valid normal shot and the game picks one for you (a\n" ..
                      "generic full band shot, or a single shot of the remaining member\n" ..
                      "for a lone duo cut). Letting the game fall back is fine.\n\n" ..
                      "Always reads the whole track; with a time selection active, only\n" ..
                      "issues inside it are reported.",
    venue_sections  = "Read [prc_*] section markers from the EVENTS track and list the\n" ..
                      "detected song sections with their time ranges.\n\n" ..
                      "Letter-suffix events ([prc_verse_1a], [prc_verse_1b], ...) are grouped\n" ..
                      "into a single section. Plain-number ([prc_verse_1]) and bare\n" ..
                      "([prc_verse]) events are each their own standalone section.",
    metronome_pulse = "How often the hi-hat click (26) ticks between the drum hits.\n\n" ..
                      "Auto: 16ths when the song's median tempo is under 95 BPM, else 8ths -\n" ..
                      "what the official charts do in about 6 songs of 7. Pick 8ths or 16ths\n" ..
                      "when Auto guesses wrong for the song; select a section first to change\n" ..
                      "only that part.\n\n" ..
                      "The pulse keeps its grid whatever the music plays: official charts keep\n" ..
                      "it at 8ths or 16ths through drum rests and quarter-note bars alike.",
    metronome_intro = "What the hi-hat click (26) plays before the band comes in.\n\n" ..
                      "Most official songs open with a drummer's count-in instead of the pulse:\n" ..
                      "\"one . two . one two three four\", then the pulse starts with the band.\n" ..
                      "The count-in is in the song audio, not the chart, so:\n\n" ..
                      "From COUNT IN: a click where each COUNT IN clip starts (the template's\n" ..
                      "count-in track, one hi-hat sample per clip), snapped to the nearest 8th.\n" ..
                      "Without COUNT IN clips it counts in from the chart instead.\n" ..
                      "Count in from chart: the official pattern in the two bars before the bar\n" ..
                      "line nearest the band's first note (a pickup counts in to the bar after\n" ..
                      "it) - the same as 63% of the official intros.\n" ..
                      "Steady pulse: the pulse from measure 1, as about 1 official song in 6 does.",
    metronome_generate = "Write the practice metronome on the EVENTS track, from measure 1 up\n" ..
                         "to [end], or inside the time selection:\n" ..
                         "  24 (kick) on each PART DRUMS Medium kick,\n" ..
                         "  25 (snare) on each Medium snare,\n" ..
                         "  26 (hi-hat) on every pulse step and every Medium hit, with the\n" ..
                         "  Intro choice before the band comes in.\n" ..
                         "This is how the official RB3 charts build them. Without Medium drums\n" ..
                         "only the hi-hat pulse is written.\n\n" ..
                         "The game plays these sounds only in practice mode, when the player\n" ..
                         "practises any part except drums - a drum-kit click to follow the beat.\n" ..
                         "Earlier 24 / 25 / 26 notes in the range are replaced; other EVENTS\n" ..
                         "notes and text events stay. One undo step.",
    venue_sing_along = "Derive VENUE sing-along notes from the HARM2/HARM3 harmony tracks:\n" ..
                      "pitch 87 (guitarist) from HARM2, pitch 85 (bassist) from HARM3.\n\n" ..
                      "For each vocal phrase (bounded by a pitch-105 marker) where the harmony\n" ..
                      "track actually sings a note, draws a note spanning that phrase. HARM3\n" ..
                      "uses HARM2's phrase markers, as the game does - its own are ignored.\n" ..
                      "Phrases\n" ..
                      "back to back (gap of one measure or less) are merged into one continuous\n" ..
                      "note instead of one per phrase.\n\n" ..
                      "If only one of HARM2/HARM3 is muted or missing, that instrument is\n" ..
                      "skipped - its existing notes are left untouched. If both are muted or\n" ..
                      "missing, nothing is generated. Pitch 86 (drummer) is never touched.\n\n" ..
                      "Always processes the whole song. Fully undoable.",
    venue_subtrack_copy_to_all = "Create (if missing) 6 tracks - \"VENUE normal camera\",\n" ..
                      "\"VENUE directed camera\", \"VENUE lighting\", \"VENUE keyevents\",\n" ..
                      "\"VENUE post proc\", \"VENUE special\" - each with a MIDI item matching\n" ..
                      "the VENUE item's position/length. Newly created tracks start muted (this\n" ..
                      "editing-only split shouldn't reach the final export), inherit VENUE's\n" ..
                      "custom MIDI note names, and get their take named after the track so open\n" ..
                      "MIDI editor tabs are identifiable instead of all showing as \"MIDI take\".\n\n" ..
                      "Clears each subtrack and re-copies the matching category of events from\n" ..
                      "VENUE - safe to re-run any time to re-sync after editing VENUE directly.\n" ..
                      "VENUE's own MIDI notes (e.g. the sing-cue notes at pitches 85-87) are\n" ..
                      "copied to \"VENUE special\" alongside its text events - the only category\n" ..
                      "that ever carries notes.\n\n" ..
                      "Always processes the whole song. Fully undoable.",
    venue_subtrack_copy_from_all = "Clear the VENUE track and replace its events with the\n" ..
                      "combined contents of all 6 subtracks (however many currently exist).\n" ..
                      "Does nothing (with a status message) if none of the subtracks exist yet -\n" ..
                      "run \"Copy all to subtracks\" first.\n\n" ..
                      "Prompts for confirmation first, since this overwrites the VENUE track\n" ..
                      "that authoring actually reads from.\n\n" ..
                      "Always processes the whole song. Fully undoable.",
    venue_subtrack_select = "Which of the 6 subtrack categories the Copy to/from buttons act on.",
    venue_subtrack_copy_to_one = "Clear just the selected subtrack and copy that category's\n" ..
                      "events from VENUE into it. Creates the subtrack (muted) if it doesn't\n" ..
                      "exist yet.\n\n" ..
                      "Always processes the whole song. Fully undoable.",
    venue_subtrack_copy_from_one = "Clear only the selected category's events from VENUE, then\n" ..
                      "copy everything from that one subtrack into VENUE. For Special, this\n" ..
                      "also clears and replaces VENUE's own MIDI notes with whatever notes are\n" ..
                      "on \"VENUE special\".\n\n" ..
                      "Unlike \"Copy to\", this does not create the subtrack if it's missing -\n" ..
                      "run \"Copy all to subtracks\" or \"Copy to\" at least once first.\n\n" ..
                      "Assumes the subtrack only contains its own category's events -\n" ..
                      "hand-edited off-category events won't be swept out of VENUE by this.\n\n" ..
                      "Always processes the whole song. Fully undoable.",
    venue_generate  = "Generate random camera and lighting events on the VENUE track.\n\n" ..
                      "Camera events are filtered by instrument availability: if a PART track is\n" ..
                      "absent from the project or muted, camera shots featuring that instrument\n" ..
                      "are removed from the pool before randomising.\n\n" ..
                      "Replaces all existing text events in the generation range.\n\n" ..
                      "Respects time selection: if a range is selected, only that range is\n" ..
                      "regenerated and events outside it are preserved.",
    venue_keyframe_align = "Where the FIRST [next] of a manual lighting keyframe sequence lands.\n\n" ..
                           "No keyframe goes on the lighting event itself: a preset always starts\n" ..
                           "on its first look.\n\n" ..
                           "Keyframe rate only: first [next] one keyframe rate after the closest beat\n" ..
                           "                    (no extra keyframe at the section start).\n" ..
                           "Closest beat:       first [next] on the beat closest to the section start,\n" ..
                           "                    then every keyframe rate.\n" ..
                           "Downbeat:           first [next] on the next measure boundary,\n" ..
                           "                    then every keyframe rate.\n\n" ..
                           "Instrument modes ignore the theme's keyframe_rate and emit [next]\n" ..
                           "only at subdivision grid points (beat/half-beat/quarter-beat) where notes actually exist:\n" ..
                           "  Guitar notes - reads PART GUITAR (pitches 96-100)\n" ..
                           "  Bass notes   - reads PART BASS   (pitches 96-100)\n" ..
                           "  Keys notes   - reads PART KEYS   (pitches 96-100)\n" ..
                           "  Drum kicks   - reads PART DRUMS  (pitch 96 only)\n" ..
                           "  Drum snare   - reads PART DRUMS  (pitch 97 only)",

    venue_mg_blend_lt = "Copy the lighting preset that is currently running to the playhead, so\n" ..
                        "the game BLENDS into the next lighting event instead of cutting to it.\n\n" ..
                        "Place the anchor a beat or two BEFORE where the new preset goes, then\n" ..
                        "add that preset at the boundary. Same thing Themes gen and Section gen\n" ..
                        "write automatically from a section's lightpreset_blendin.\n\n" ..
                        "Reads the VENUE track, not the dropdown above - it copies whatever is\n" ..
                        "actually playing. Refused, with a report naming what it found, when the\n" ..
                        "last two lighting events already match (a blend is in place), when a\n" ..
                        "lighting event is already on the playhead, or when none precedes it.\n\n" ..
                        "The copy carries no keyframes: restating the running preset does not\n" ..
                        "restart it, so its [next] train runs on. Fully undoable.",
    venue_mg_blend_pp = "Copy the post-process effect that is currently running to the playhead,\n" ..
                        "so the game BLENDS into the next one instead of cutting to it.\n\n" ..
                        "Place the anchor a beat or two BEFORE where the new effect goes, then\n" ..
                        "add that effect at the boundary. Same thing Themes gen and Section gen\n" ..
                        "write automatically from a section's postproc_blendin.\n\n" ..
                        "Reads the VENUE track, not the dropdown above - it copies whatever is\n" ..
                        "actually playing. Refused, with a report naming what it found, when the\n" ..
                        "last two post-process events already match (a blend is in place), when\n" ..
                        "one is already on the playhead, or when none precedes it.\n\n" ..
                        "Fully undoable.",
    venue_mg_kf_add = "Generate [next] keyframe events from the playhead to the next\n" ..
                      "lighting event, the time selection end (if active), or the VENUE item end.\n\n" ..
                      "The playhead must be on a manual lighting event\n" ..
                      "([lighting (verse|chorus|manual_cool|manual_warm|dischord|stomp)]) - the\n" ..
                      "[next] train belongs to it. The whole row is blocked anywhere else.\n" ..
                      "No keyframe goes on the event itself: a preset always starts on its\n" ..
                      "first look.\n\n" ..
                      "Clears any existing [first]/[next]/[prev] events in that range first.\n" ..
                      "Fully undoable.",
    venue_kf_next = "Step a manual lighting preset to its next look (looping round).\n\n" ..
                    "Only the manual presets use keyframe events: verse, chorus,\n" ..
                    "manual_cool, manual_warm, dischord and stomp. Every other preset\n" ..
                    "ignores them.\n\n" ..
                    "A preset change always starts on the first look. Most manual presets\n" ..
                    "have two looks, so [next] toggles between them. The official charts\n" ..
                    "use only [next], often one per beat.\n\n" ..
                    "Looks per venue (all 44 venues read from the game files; every venue\n" ..
                    "of a kind has the same presets):\n" ..
                    "  verse, chorus: 4 in arenas, big clubs and festivals;\n" ..
                    "                 2 in small clubs and video venues\n" ..
                    "  stomp, dischord, manual_cool, manual_warm: 2 everywhere\n" ..
                    "  (on PS3 the arenas run manual_cool / manual_warm on their own,\n" ..
                    "  so [next] does nothing there)",
    venue_kf_first = "Go to the manual lighting preset's first look.\n\n" ..
                     "Unlike [next] and [prev], the result does not depend on which look\n" ..
                     "is showing, so use it where a part must start from the first look.\n" ..
                     "Right after a lighting change it does nothing: a preset always\n" ..
                     "starts on its first look.\n\n" ..
                     "Only verse, chorus, manual_cool, manual_warm, dischord and stomp\n" ..
                     "react to it.",
    venue_kf_prev = "Step a manual lighting preset back one look (looping round).\n\n" ..
                    "With two looks it lands on the same look as [next]. Where verse and\n" ..
                    "chorus have four looks (arenas, big clubs, festivals) it steps\n" ..
                    "through them backwards - mix it with [next] to make your own\n" ..
                    "sequence of looks there.\n\n" ..
                    "Only verse, chorus, manual_cool, manual_warm, dischord and stomp\n" ..
                    "react to it.",
    venue_cs_mode_event = "Pick one camera event and see every move it has.",
    venue_cs_mode_keyword = "Type words to find moves by name (e.g. kiss, jump, mic stand) or camera\n" ..
                            "events by name (e.g. guitar). Every word must match. Shows up to 10\n" ..
                            "camera events, each with the moves that matched.",
    venue_cs_style = "The song's animation style, set by its genre (Metadata > Genre >\n" ..
                     "Animation style). Most directed cuts have moves for only some styles.",
    venue_cs_gender = "The gender of the band member the cut focuses on. Some moves exist for\n" ..
                      "only one gender. The player's characters decide this, not the song.",
    venue_cs_kind = "The kind of venue. The player's venue decides this, not the song.\n" ..
                    "Each venue has its own set of camera shots.",
    venue_cs_lineup = "Which band members are on stage. With guitar, bass and keys all charted,\n" ..
                      "only two of the three fit on stage, so one is left out. The game then\n" ..
                      "drops or replaces the cuts of the member who is left out.",
    venue_cs_partial = "Only some venues of this kind have this move.",    venue_cs_col_1 = "What the shot shows: the move, the moves of several members, the part\n" ..
                     "of the crowd it frames, or band close-ups. A long name ends in ...\n" ..
                     "when the window is narrow: hover it to read it whole.\n" ..
                     "Click a move to see what competes with it.",
    venue_cs_row_click = "Click: show this camera event with the filters this move needs.\n" ..
                         "The moves left undimmed are the ones competing with it.",
    venue_cs_col_2 = "Who moves: a band member, several members, the crowd, or the band in\n" ..
                     "close-up. Several members by letter: V+G+B = vocals, guitar, bass\n" ..
                     "(D drums, K keys); hover one to read it whole.",
    venue_cs_col_3 = "The song styles this move is for. Any = every style.",
    venue_cs_col_4 = "The focus member's gender this move is for. Both = either.",
    venue_cs_col_5 = "The venue kinds that have this move. All = every venue; * = only some venues of that kind.",
    venue_cs_col_6 = "How many shots of this move one venue has. The game rotates through them:\n" ..
                     "each use of the event takes the next one.",
    venue_cs_col_7 = "How early the move starts before its event (the event marks the moment\n" ..
                     "the move lands).",
    venue_mg_target = "Where this tab reads and writes events.\n\n" ..
                      "VENUE: the VENUE track.\n" ..
                      "Subtracks: the Sub VENUE tracks made by Venue > Actions > Copy all to\n" ..
                      "subtracks. Each event goes to its own track - cameras to VENUE normal\n" ..
                      "camera / VENUE directed camera, lighting to VENUE lighting, [first] /\n" ..
                      "[next] / [prev] and generated keyframes to VENUE keyevents, and so on.\n" ..
                      "Blend and the keyframe checks read VENUE lighting / VENUE post proc.\n\n" ..
                      "The game, the Venue validators and Preview read only VENUE: run\n" ..
                      "Copy all to main track when you are done.\n\n" ..
                      "The Keyframes tab shares this setting.",
    venue_kf_target = "Where Regenerate keyframes reads lighting and writes keyframes.\n\n" ..
                      "VENUE: both on the VENUE track.\n" ..
                      "Subtracks: reads the manual lighting events on VENUE lighting and\n" ..
                      "writes the [next] keyframes to VENUE keyevents (Sub VENUE tracks, made by\n" ..
                      "Venue > Actions > Copy all to subtracks).\n\n" ..
                      "Shared with Manual gen's Target. The game, the Venue validators and\n" ..
                      "Preview read only VENUE: run Copy all to main track when you are done.",
    anim_beat_full = "Write a BEAT note on every quarter note, from measure 1 up to [end]\n" ..
                     "(or inside the time selection, never past [end]).\n\n" ..
                     "A downbeat note (12) on each bar's first beat, an upbeat note (13)\n" ..
                     "on the others. Every time signature counts in quarter notes from\n" ..
                     "the bar line, as the official charts do: 6/8 gets three notes,\n" ..
                     "7/8 four.\n\n" ..
                     "Needs a BEAT track and an [end] event on EVENTS. Existing BEAT notes\n" ..
                     "in the range are replaced. One undo step.\n\n" ..
                     "Overdrive drains per BEAT note: a full meter lasts 32 of them\n" ..
                     "(8 bars of 4/4 here).",
    anim_beat_half = "Half-speed BEAT track, for animations: a note on every other quarter\n" ..
                     "note (beats 1 and 3 in 4/4). Each bar starts again on its first beat,\n" ..
                     "so in 3/4 or 6/8 the shorter gap comes before the next bar.\n" ..
                     "The beat just before [end] always gets a note (Magma needs it).\n\n" ..
                     "Select a section first to halve only that part.\n" ..
                     "Range, checks and undo as Normal.\n\n" ..
                     "Overdrive lasts twice as long in a halved part (it drains per BEAT\n" ..
                     "note: a full meter lasts 32 of them).",
    anim_beat_double = "Double-speed BEAT track: a note on every 8th note, counted from\n" ..
                       "each bar line.\n\n" ..
                       "Official charts use it in about 2% of songs, two ways:\n" ..
                       "  - slow songs whose tempo map runs at half the felt pulse, so the\n" ..
                       "    beat follows what you hear: Snuff, Happy Xmas (War Is Over),\n" ..
                       "    The Only Exception, Spoonman, Free Bird, King George;\n" ..
                       "  - double-time sections inside a normal song: American Pie,\n" ..
                       "    Phantom of the Opera, Voodoo Child (live). Select the section\n" ..
                       "    first to write only that part.\n\n" ..
                       "Overdrive drains twice as fast in a double-time part (it drains per\n" ..
                       "BEAT note: a full meter lasts 32 of them).\n" ..
                       "Range, checks and undo as Normal.",
    anim_beat_double_style = "Where double-time beats put the downbeat note.\n\n" ..
                             "Every 4 beats: on the bar line and every 4 notes after it, while\n" ..
                             "4 or more are left in the bar - twice in a 4/4 bar, once in 3/4.\n" ..
                             "The slow songs do this (Snuff, Happy Xmas, Spoonman): the BEAT\n" ..
                             "track reads like the song at double tempo.\n" ..
                             "Every bar: only on the bar line, 8 notes in a 4/4 bar. Official\n" ..
                             "double-time sections do this (American Pie), and The Red in 6/8\n" ..
                             "(6 notes a bar).",
    drum_anim_crash = "Which crash a green cymbal gem plays: crash 2 on the drummer's right\n" ..
                      "(next to the ride) or crash 1 on the left (next to the hi-hat).\n\n" ..
                      "Official charts choose per song: some use crash 1 for nearly every\n" ..
                      "crash, others almost never. Crash 2 is the commoner overall. Pick what\n" ..
                      "the recording sounds like; edit single crashes by hand after.",
    drum_anim_blue = "What a blue cymbal gem plays.\n\n" ..
                     "Ride: the ride cymbal. A lone blue hit (no other blue within a beat)\n" ..
                     "is played as a crash 1 accent.\n" ..
                     "Hi-hat: every blue hit is played on the hi-hat. To also open the hat\n" ..
                     "on those hits, tick \"Open the hat on blue hi-hat hits\" (Hi-hat).\n\n" ..
                     "Official charts: most play blue as the ride; ~10% of songs play it as\n" ..
                     "the hi-hat nearly every time, open on 83% of those hits.",
    drum_anim_blue_open = "Needs Blue cymbal = Hi-hat (Cymbals).\n\n" ..
                          "The hat is open on every blue hi-hat hit: the\n" ..
                          "pedal note (25) is held under it. A run of open hits shares one\n" ..
                          "pedal note, from a 16th before the first to the next hi-hat hit.\n\n" ..
                          "Harmonix charted open hi-hats on blue (official charts open 83% of\n" ..
                          "blue hi-hat hits), but not every community chart follows that, so it\n" ..
                          "is off by default.",
    drum_anim_open_hat = "Open the hi-hat on loud yellow hi-hat gems: those with a velocity\n" ..
                         "above Open above get the pedal note (25) held under them. A run of\n" ..
                         "open hits shares one pedal note, from a 16th before the first to the\n" ..
                         "next hi-hat hit, which closes it - as official charts do.\n\n" ..
                         "For charts that keep blue for the ride. The game ignores gem velocity,\n" ..
                         "so raise it on the hats you want open: most charts have one velocity\n" ..
                         "on every gem (often 96 or 100), and then nothing opens. Official\n" ..
                         "charts keep 78% of yellow hi-hat hits closed.\n\n" ..
                         "Other pedal notes - the foot keeping time while the hands play the\n" ..
                         "ride or crashes, most of the 25s in official charts - are left as\n" ..
                         "they are.",
    drum_anim_open_hat_above = "Yellow hi-hat gems with a velocity above this are open. 100 opens\n" ..
                               "only gems louder than the usual 96 / 100; 0 opens every one.",
    drum_anim_min_cym = "Fast hi-hat / cymbal hits (under ~130 ms apart, e.g. 16ths at 120 BPM\n" ..
                        "or 8ths at 240 BPM) switch to alternating hands only after this many\n" ..
                        "in a row; until then the right hand plays them. Hi-hat 16ths also\n" ..
                        "alternate from 110 BPM, and always in a disco beat. Slower cymbals\n" ..
                        "stay on the right hand.\n\n" ..
                        "3 matches the official charts best. CAT uses 4.",
    drum_anim_flam = "Snare and yellow tom together: both hands on the snare instead of\n" ..
                     "snare + tom 1. Official charts do this 83% of the time.",
    drum_anim_snare_variety = "Lone snare hits with nothing fast around them:\n" ..
                              "  - in a slow snare-only passage, the right hand plays them;\n" ..
                              "  - on the beat after a pause or next to toms, both hands (an accent).\n" ..
                              "Off: the left hand plays them all. Official charts play these\n" ..
                              "~50% left, ~30% right, ~20% both hands.",
    drum_anim_soft_cym = "Choose how each crash is played from the velocity of its Expert gem:\n" ..
                         "  - under Choke below: a choke - the drummer grabs the cymbal to stop\n" ..
                         "    it (notes 40 / 41, written instead of the hit);\n" ..
                         "  - under Soft below: a soft crash - still a hit, lighter;\n" ..
                         "  - the rest: a normal hit.\n" ..
                         "The lower of the two thresholds takes the lowest velocities, so\n" ..
                         "either order works.\n" ..
                         "Hi-hat and ride have no soft or choke notes and are not affected.\n\n" ..
                         "The game ignores gem velocity, so set it on the gems you want: most\n" ..
                         "charts have one velocity on every gem (often 96 or 100), and then\n" ..
                         "nothing changes. Official charts choke a crash before a stop, and\n" ..
                         "even then only about one time in ten.",
    drum_anim_choke_below = "Crash gems with a velocity under this become chokes (the cymbal is\n" ..
                            "grabbed, not hit). 0 = no chokes.\n\n" ..
                            "Either order works: the lower of Choke below and Soft below takes\n" ..
                            "the lowest velocities. Choke 20 / Soft 50: 0-19 choke, 20-49 soft.\n" ..
                            "Choke 50 / Soft 20: 0-19 soft, 20-49 choke.",
    drum_anim_soft_cym_below = "Crash gems with a velocity under this become soft crashes, except\n" ..
                               "where Choke below claims them (see its tooltip). 0 = no soft crashes.",
    drum_anim_soft_snare = "Snare gems on Expert with a low velocity use the soft snare notes\n" ..
                           "(28 / 29). In the game these are ghost strokes: the stick hovers over\n" ..
                           "the snare and the snare on the kit does not move - meant for quiet\n" ..
                           "ghost notes.\n\n" ..
                           "The game ignores gem velocity, so lower it on the ghost notes you\n" ..
                           "want: most charts have one velocity on every gem (often 96 or 100),\n" ..
                           "and then nothing changes. Official charts use soft snare notes for a\n" ..
                           "few ghost notes in about half of the songs, never for every hit.",
    drum_anim_soft_snare_below = "Snare gems with a velocity under this become ghost strokes.\n" ..
                                 "128 = every snare hit (no snare in the song then moves).",
    drum_anim_ride_alt = "When the drummer rides a crash in 8th notes, alternate soft and hard\n" ..
                         "hits so it looks less robotic (an RBN doc tip). Rare in official\n" ..
                         "charts (6% of 8th-note crash riding, 13% when slow); quarters and\n" ..
                         "16ths are never alternated.",
    drum_anim_flam_late = "The left hand of a flam lands a 1/32 note after the right (an RBN\n" ..
                          "doc tip for a more realistic flam). Official charts put both hands\n" ..
                          "on the same tick.",
    drum_anim_generate = "Write the animation notes on PART DRUMS and PART DRUMS_2X from their\n" ..
                         "Expert gems. Existing animation notes are replaced - on the whole\n" ..
                         "track, or only inside the time selection. Hi-hat pedal notes (25)\n" ..
                         "are touched only for open hi-hats (Open the hat on blue hi-hat hits,\n" ..
                         "or Open hi-hat by velocity): those are replaced, the rest stay. Muted\n" ..
                         "tracks are skipped. One undo step.",
    char_set_all ="Set every part's active state at once. The rows below can then be\n" ..
                   "changed one by one.",
    char_gap_inst = "Drums, guitar, bass and keys go [idle] when they rest at least this\n" ..
                    "long (from the end of a note to the next note), and come back 1 beat\n" ..
                    "before they play again. 1 bar = 4 quarter notes.\n\n" ..
                    "Default 3 bars, as CAT. Official charts idle about half of the\n" ..
                    "2-3 bar rests and most of the longer ones.",
    char_gap_vox = "Vocals and HARM1 go [idle] (microphone down) when they rest at least\n" ..
                   "this long. 1 bar = 4 quarter notes.\n\n" ..
                   "Default 2 bars: official charts idle about 70% of the 2-3 bar vocal\n" ..
                   "rests. The RBN vocal doc advises against idling for less than a bar.",
    char_idle_gaps = "Off: parts stay in their active state through every rest. The song\n" ..
                     "start ([idle] at bar 3 before a late first note) and [idle_realtime]\n" ..
                     "after the last note are written either way.\n\n" ..
                     "Rare in official charts: about 3% of parts with several long rests\n" ..
                     "never idle. Charters more often skip the idle in a rest or two -\n" ..
                     "generate with this on, then change single rests in Manual mode.",
    char_generate = "Write the animation states on PART DRUMS, PART DRUMS_2X, PART GUITAR,\n" ..
                    "PART BASS, PART KEYS, PART VOCALS and HARM1, from their Expert notes:\n" ..
                    "  - the active state 1 beat before the part plays,\n" ..
                    "  - [idle] 1 beat after it stops for a long rest (the gaps above),\n" ..
                    "  - [idle] at bar 3 when the part starts later,\n" ..
                    "  - [idle_realtime] 1 beat after its last note.\n\n" ..
                    "Muted tracks and tracks with no Expert notes are skipped. Existing\n" ..
                    "animation states are replaced - on the whole track, or only inside\n" ..
                    "the time selection. One undo step.",
    char_mode = "Generate: write the states for the whole song (or the time selection).\n" ..
                "Manual: put one state at the playhead on one part.",
    char_manual_part = "The track Manual writes to.",
    char_manual_btn = "Inserts the state at the edit cursor on the part's track. When a\n" ..
                      "state already sits on that spot the button reads Replace and swaps\n" ..
                      "it. One undo step.\n\n" ..
                      "The ride options (Drums) are not states: they replace only another\n" ..
                      "ride option on that spot, and Generate leaves them alone.",
    char_readout = "The part's state at the playhead: the last state event at or before\n" ..
                   "it, and where that event is - on the playhead itself, or the bar.beat\n" ..
                   "it started from.",
    anim_beat_half_style = "Where half-time beats put the downbeat note.\n\n" ..
                           "Every other bar: the first bar of the range gets a downbeat, the\n" ..
                           "next bar starts with an upbeat, and so on. This is how CAT and most\n" ..
                           "official halved songs do it.\n" ..
                           "Every bar: a downbeat on every bar's first beat.",
    venue_mg_replace = "What the Add buttons do with events already at the playhead.\n\n" ..
                       "Add: insert next to them (stacks build up).\n" ..
                       "Replace: first remove the events of the same family on that spot,\n" ..
                       "then insert. Other families there stay.\n\n" ..
                       "Families: cameras (normal and directed together, so a camera stack\n" ..
                       "becomes the one new shot), lighting, post proc, bonus FX, and\n" ..
                       "keyframes ([first] / [next] / [prev]).\n\n" ..
                       "Blend and keyframe generation are not affected. One undo step.",

    venue_kf_inst_subdiv = "Subdivision grid for instrument-aware keyframe alignment.\n\n" ..
                           "Every beat:         check each beat boundary (max 4 [next] per measure in 4/4).\n" ..
                           "Every half beat:    check each 8th-note boundary (max 8 [next] per measure in 4/4).\n" ..
                           "Every quarter beat: check each 16th-note boundary (max 16 [next] per measure in 4/4).\n\n" ..
                           "Grid positions with no qualifying notes are skipped; no [next] is emitted.",

    venue_theme     = "Select a venue theme to guide lighting and camera generation.\n\n" ..
                      "Themes define per-section lighting presets, postproc effects,\n" ..
                      "and camera pacing. Lighting and postproc events are randomly picked\n" ..
                      "from each section's allowed pool; directed cuts fire at section\n" ..
                      "starts when specified.\n\n" ..
                      "Requires [prc_*] section markers on the EVENTS track.\n" ..
                      "Falls back to the theme's default preset if no sections are detected.\n\n" ..
                      "Drop .rbtheme files into the resources/themes/ folder to add custom themes.",

    venue_cam_pacing = "Override the camera cut pacing for the entire song.\n\n" ..
                       "Theme default: use the pacing defined in the selected theme\n" ..
                       "(falls back to Slow - 24 16ths - when no theme is selected).\n\n" ..
                       "Any other value overrides both the theme's global camera_pacing\n" ..
                       "and any per-section camera_pacing overrides defined in the theme.\n\n" ..
                       "At or above 150 BPM all intervals scale by \xc3\x971.5 to avoid\n" ..
                       "camera cuts becoming too rapid at fast tempos.\n\n" ..
                       "4/4 reference: 16 \xc3\x9716ths = 1 measure (Medium), 24 = 1.5 measures\n" ..
                       "(Slow), 32 = 2 measures (Minimal).\n\n" ..
                       "Vocal phrase start: not interval-based - reads PART VOCALS phrase-\n" ..
                       "marker (pitch 105) note starts and places a camera event exactly on\n" ..
                       "each one; \"Include jitter\" has no effect in this mode.\n\n" ..
                       "Themes gen uses every phrase in the song. Section gen only phrases\n" ..
                       "that start inside the current section (one tailing in from the\n" ..
                       "previous section doesn't count, one that runs into the next section\n" ..
                       "does). Manual gen's \"Advance camera pacing\" jumps straight to the\n" ..
                       "next phrase start instead of stepping by an interval, and does\n" ..
                       "nothing when there is no further phrase.\n\n" ..
                       "If no phrase markers exist at all, the recurring camera loop is\n" ..
                       "skipped (forced/bookend camera events, if any, still happen).",

    venue_cam_pacing_jitter = "When checked, camera cut intervals are randomised within \xc2\xb120% of\n" ..
                              "the selected pacing value, giving a more natural feel.\n\n" ..
                              "When unchecked, all camera cuts land at the exact interval with\n" ..
                              "no randomisation - use this for metrically precise authoring.",

    venue_cam_pacing_custom = "Custom camera cut interval in 16th notes (2-128).\n\n" ..
                              "At or above 150 BPM this value is scaled by \xc3\x971.5,\n" ..
                              "same as the named presets.\n\n" ..
                              "Ctrl+click to type an exact value.",

    -- Section-by-section editor
    venue_sec_section  = "Select a detected [prc_*] section to configure.\n\n" ..
                         "Click Refresh to re-read sections from the EVENTS track.",
    venue_sec_lighting = "Lighting preset for this section.\n\n" ..
                         "Manual presets (verse, chorus, manual_cool, manual_warm, dischord,\n" ..
                         "stomp) step between their looks on [next] keyframe events - set\n" ..
                         "Keyframe rate to control the spacing.\n\n" ..
                         "Auto presets (loop_*, harmony, frenzy, silhouettes, etc.) need no\n" ..
                         "keyframes. Leave blank to skip lighting for this section.",
    venue_sec_postproc = "Post-process effect (.pp file) for this section.\n\n" ..
                         "Leave blank to skip.",
    venue_sec_kr       = "Keyframe rate in beats: how often [next] events are placed.\n\n" ..
                         "Keyframe align decides where the first [next] lands.\n\n" ..
                         "Only used when the chosen lighting preset is a manual type\n" ..
                         "(verse, chorus, manual_cool, manual_warm, dischord, stomp).\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_lt_blend = "Blend into this section's lighting instead of cutting to it.\n\n" ..
                         "This section's own lighting event always sits ON the section start.\n" ..
                         "This many beats before it, the PREVIOUSLY active lighting preset is\n" ..
                         "re-stated as a blend anchor, which is what makes the game fade rather\n" ..
                         "than snap. 0 = hard cut at the section start.\n\n" ..
                         "The duplicate carries no keyframes: it restates a preset that is\n" ..
                         "already running, which does not restart it - the [next] train from\n" ..
                         "the original event runs on through it.\n\n" ..
                         "Skipped when the preset is not changing, or when the blend point\n" ..
                         "would fall at or before the event it copies.\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_pp_blend = "Blend into this section's post-process instead of cutting to it.\n\n" ..
                         "This section's own post-process event always sits ON the section start.\n" ..
                         "This many beats before it, the PREVIOUSLY active effect is re-stated as\n" ..
                         "a blend anchor. 0 = hard cut at the section start.\n\n" ..
                         "Skipped when the effect is not changing, or when the blend point would\n" ..
                         "fall at or before the event it copies.\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_dircut   = "Insert a forced directed camera cut at the section start.\n\n" ..
                         "Select a directed event name, or leave blank for no forced cut.\n" ..
                         "Random directed cuts are suppressed in section generation mode.",
    venue_sec_bonusfx  = "Insert a [bonusfx] event at the section start.",

    -- Keyframes tab
    venue_kf_regenerate = "Find every manual lighting event ([lighting (verse)], (chorus),\n" ..
                          "(manual_cool), (manual_warm), (dischord), (stomp)) already on the\n" ..
                          "VENUE track (Target = Subtracks: on VENUE lighting, keyframes go to\n" ..
                          "VENUE keyevents) and regenerate its [next] keyframes, running from\n" ..
                          "that lighting event to the next lighting event of any kind.\n\n" ..
                          "Keyframe align decides where the first [next] lands. No keyframe\n" ..
                          "goes on the lighting event itself: a preset always starts on its\n" ..
                          "first look (an old [first] there is removed).\n\n" ..
                          "Only [first]/[next]/[prev] events are cleared and replaced -\n" ..
                          "camera, lighting, post-process, and bonus FX are untouched.\n\n" ..
                          "Respects an active time selection (only lighting events inside the\n" ..
                          "selection are regenerated); otherwise processes the whole song.\n\n" ..
                          "Fully undoable.",

    -- Events tab
    venue_ev_num     = "Section number: 'bare' inserts the unnumbered event ([prc_verse]),\n" ..
                       "1-9 insert numbered variants ([prc_verse_1]).\n\n" ..
                       "Use 'bare' when a section type occurs only once (e.g. a single\n" ..
                       "guitar solo) and numbers when it repeats - bare and numbered\n" ..
                       "variants of the same event must not co-exist, and numbers must\n" ..
                       "be used in order ([prc_verse_2] needs [prc_verse_1] before it).\n\n" ..
                       "Ctrl+click to type an exact value.",
    venue_ev_letters = "Insert lettered part events - [prc_verse_1a], [prc_verse_1b], ...\n" ..
                       "- used to split a long section into parts (they merge back into\n" ..
                       "one section in Section gen). The next free letter is picked\n" ..
                       "automatically; a letter deleted by hand is offered again, placed\n" ..
                       "between its neighbors.\n\n" ..
                       "On: Add only inserts lettered forms, never the plain event.\n" ..
                       "Off: Add only inserts the plain event, and refuses when it\n" ..
                       "already exists. Plain and lettered forms of the same event must\n" ..
                       "not be mixed. Events with no lettered variants (e.g. [prc_bre])\n" ..
                       "always insert the plain form, and events with only lettered\n" ..
                       "variants ([prc_dj_intro_a]..) always insert a lettered one - the\n" ..
                       "row then says so next to the event.",
    venue_ev_next    = "The exact event the Add button will insert at the current playhead\n" ..
                       "position, based on the selection, number, letter mode, and the\n" ..
                       "events already on the EVENTS track.\n\n" ..
                       "Shows '(blocked)' when the Add would be refused (duplicate, mixed\n" ..
                       "plain/lettered or bare/numbered forms, wrong order, or another\n" ..
                       "event on the same spot; crowd events are exempt) - hover it for\n" ..
                       "the reason, which is also reported in the result on Add.",
    venue_ev_letters_only = "The game's section names list this one only with a letter\n" ..
                       "(_a, _b, ...), so Add inserts the lettered event even with\n" ..
                       "letter suffix off.\n\n" ..
                       "A listed name is shown translated in each game language; an\n" ..
                       "unlisted one is shown as the event text itself, the same in\n" ..
                       "every language.",
    venue_ev_no_letters = "The game's section names have no lettered form of this one,\n" ..
                       "so Add inserts the plain event even with letter suffix on.\n\n" ..
                       "A listed name is shown translated in each game language; an\n" ..
                       "unlisted one is shown as the event text itself, the same in\n" ..
                       "every language.",
    venue_ev_add     = "Insert the shown event at the exact playhead position on the\n" ..
                       "EVENTS track.\n\nFully undoable.",
    venue_ev_bookends = "Insert the minimal event set every song needs:\n" ..
                        "  measure 1:  [crowd_realtime] (idle crowd)\n" ..
                        "  measure 2:  [prc_intro] + [crowd_noclap] + [crowd_normal]\n" ..
                        "              (change [crowd_normal] to mellow or intense\n" ..
                        "              to suit the song)\n" ..
                        "  measure 3:  [music_start]\n" ..
                        "  measure E-5:  [prc_outro] + [crowd_noclap]\n" ..
                        "  measure E-2 / E:  [music_end] / [end]\n" ..
                        "where E is the last measure fully contained in the MIDI item.\n" ..
                        "Items shorter than 7 full measures skip the end events.\n\n" ..
                        "Existing bookend events are removed first, so re-running\n" ..
                        "recalculates their positions. Crowd events are removed only\n" ..
                        "on the bookend measures - ones you placed elsewhere stay.\n" ..
                        "A different event already sitting on a target measure makes\n" ..
                        "that bookend be skipped (reported in the result).\n\nFully undoable.",
    venue_ev_clear   = "Remove every text event from the EVENTS track.\n" ..
                       "The track name event is left as is.\n\nFully undoable.",

    -- Active players row (bottom of the Venue tab and standalone preview window).
    -- venue_player_* entries are string.format templates filled in by
    -- ui_venue_players.lua (%s = PART track name / play-state event / time).
    venue_players_row = "Instrument availability at the playhead, as venue generation sees it:\n\n" ..
                        "green   active ([play]/[mellow]/[intense])\n" ..
                        "blue    idle ([idle]/[idle_realtime])\n" ..
                        "red     track muted or missing\n" ..
                        "orange  no play-state events (treated as always in [play] state)\n\n" ..
                        "Follows the play cursor during playback, the edit cursor otherwise.\n" ..
                        "Hover an instrument for details.",
    venue_player_muted   = "%s is muted - excluded from venue generation.",
    venue_player_missing = "%s track is missing - excluded from venue generation.",
    venue_player_nodata  = "%s has no [play]/[idle] play-state events -\n" ..
                           "venue generation treats it as always in [play] state.",
    venue_player_state   = "%s - %s since %s.",
    venue_player_default_active = "%s - active (before the first play-state event).",

    -- Tempo map - track dropdowns
    kick_track     = "Audio track containing the isolated kick drum stem (KICK AUDIO).\n" ..
                     "Primary source for downbeat detection.",
    snare_track    = "Audio track containing the isolated snare drum stem (SNARE AUDIO).\n" ..
                     "Used per-window when kick has no onset above threshold.",
    kit_track      = "Audio track containing the full drum kit mix (KIT AUDIO).\n" ..
                     "Used per-window when both kick and snare are quiet.",
    fallback_track = "Guitar or keys audio stem used as a last resort.\n" ..
                     "Tried per-window only when all drum sources are quiet.\n" ..
                     "Auto-detects GUITAR AUDIO, then KEYS AUDIO.",

    -- Tempo map - action buttons
    show_ctx    = "Read the tempo marker that applies at the time-selection start (or project\n" ..
                  "start if no selection) and show the BPM, time signature, and calculated\n" ..
                  "start time of the first generated measure.\n\n" ..
                  "Use this to verify the project is set up correctly before generating.",
    align_audio = "Move the audio item on each selected drum track so it starts at the same\n" ..
                  "position as the item on the SONG AUDIO track.\n\n" ..
                  "Tracks with multiple items are skipped with an error.\n" ..
                  "Tracks that are already aligned are reported without changes.",
    est_bpm     = "Detect onsets from the kick/snare audio and estimate the average BPM\n" ..
                  "and likely time signature.\n\n" ..
                  "Read-only - nothing is written to the project.",
    clear_tempo = "Delete REAPER tempo markers except the root marker at index 0.\n\n" ..
                  "With a time selection: deletes only markers within the selection.\n" ..
                  "Without a time selection: deletes all markers except the root.\n\n" ..
                  "Fully undoable.",
    gen_tempo   = "Generate REAPER tempo markers from the drum audio.\n\n" ..
                  "Anchors on the configured first measure, then propagates the beat grid\n" ..
                  "forward, inserting a marker only where the detected downbeat deviates from\n" ..
                  "the expected position by more than the drift threshold.\n\n" ..
                  "Respects time selection if active.",
    autotune_threshold = "Find the highest RMS threshold that still detects onsets near\n" ..
                         "the tempo markers currently placed in the project.\n\n" ..
                         "Place at least 2 markers manually at downbeat positions first.\n" ..
                         "With a time selection: only markers in that range are used.\n" ..
                         "Without: all markers in the audio item span are used.\n\n" ..
                         "Updates the Drum or Fallback threshold automatically based on\n" ..
                         "which source has signal in the selected range.\n" ..
                         "Read-only - no project changes are made.",
    convert_6_4_to_3_4 = "Convert all 6/4 tempo markers to 3/4. BPMs are unchanged;\n" ..
                          "MIDI note positions are unaffected (PPQ is independent of time signature).\n\n" ..
                          "With a time selection: only markers within the selection are converted.\n" ..
                          "Without a time selection: converts all 6/4 markers in the project.\n\n" ..
                          "Fully undoable.",

    -- Tempo map - sliders
    tm_rms_threshold      = "Audio level above which a drum hit onset is detected.\n" ..
                            "Lower = more sensitive; higher = ignore quiet hits.",
    tm_rms_window_ms      = "RMS analysis window in milliseconds.\n" ..
                            "Short (5-15 ms) gives sharp onset times for drums.",
    tm_fb_rms_threshold   = "RMS onset threshold for the fallback source (guitar / keys).\n" ..
                            "Guitar sustain is uneven - usually needs a lower value than drums.\n" ..
                            "Lower = more sensitive; higher = ignore quiet hits.",
    tm_fb_rms_window_ms   = "RMS analysis window in milliseconds for the fallback source.\n" ..
                            "Short (5-15 ms) gives sharp onset times.",
    tm_fb_use_flux        = "Apply onset-flux mode to the Fallback source (guitar / keys).\n\n" ..
                            "Replaces raw RMS with the positive energy-rise per window.\n" ..
                            "Sustained notes produce 0 (no false onsets); only true attacks spike.\n\n" ..
                            "Also applies to the local-peak search used during tempo map generation.\n" ..
                            "When enabled, the RMS threshold below is the minimum energy-rise, not amplitude.",
    tm_search_window_ms   = "How far either side of the expected downbeat position to search\n" ..
                            "for an onset (in ms).\n" ..
                            "Wider = more tolerant of tempo drift; narrower = stricter.",
    tm_drift_threshold_ms = "Minimum deviation (ms) from the expected beat position before\n" ..
                            "a new tempo marker is inserted.\n" ..
                            "Higher = fewer, sparser markers; lower = more corrections.",
    tm_bpm_failsafe       = "Generation stops if the instantaneous BPM implied by two\n" ..
                            "consecutive detected downbeats drifts more than this amount\n" ..
                            "from the initial BPM.\n\n" ..
                            "Override with the checkbox below for songs with large BPM changes.",
    tm_first_measure      = "Project measure number where the first tempo marker will be\n" ..
                            "generated (and where the beat grid anchor is placed).\n\n" ..
                            "Align your drum audio so the first true downbeat lands on this\n" ..
                            "measure before running Generate.",
    tm_timesig_num        = "Time signature override.\n\n" ..
                            "Empty  =  inherit from the project tempo marker.\n" ..
                            "One number (e.g. 3)  =  override numerator only; denominator stays 4.\n" ..
                            "Two numbers (e.g. 6/8 or 4 / 4)  =  override both.",
    tm_override_failsafe  = "Bypass the BPM failsafe check.\n" ..
                            "Enable for songs with intentional large tempo changes.",
    tm_autotune_density   = "Expected number of detectable onsets per measure in the analysis range.\n\n" ..
                            "Set to the approximate count of note hits per measure in your audio.\n" ..
                            "Example: 4 for one note per beat in 4/4; 8 for eighth notes.\n\n" ..
                            "At 0: no density check.\n" ..
                            "When set: thresholds producing more than 2x this count are excluded,\n" ..
                            "preventing auto-tune from landing on an excessively noisy threshold.",

    -- General tab - Song fade out
    song_fade_out = "Create a volume fade out on the SONG AUDIO track within the time selection.\n\n" ..
                    "Volume starts at the track's current fader level and reaches silence at\n" ..
                    "the end of the selection. Existing envelope points inside the selection\n" ..
                    "are replaced; points outside are untouched.\n\n" ..
                    "Select a range that starts at a musically meaningful point (e.g. end of\n" ..
                    "the last vocal phrase) for the most natural-sounding cutoff.",
    select_song_until_end = "Set the time selection from bar 1 to the [end] event on the EVENTS track,\n" ..
                    "so a render with bounds set to Time selection comes out at the song's length.\n\n" ..
                    "The selection is left unchanged, and the reason reported, when the EVENTS\n" ..
                    "track is missing or has no [end] event or more than one.",

    venue_preview_scale  = "Scale for venue event sprite previews shown in tooltips.\n\n" ..
                           "1\xc3\x97 - smaller display (213\xc3\x97120 px).\n" ..
                           "2\xc3\x97 - larger display (426\xc3\x97240 px).\n\n" ..
                           "The scale affects display size only. Which source folder is loaded\n" ..
                           "(large or small) depends on what is installed.\n\n" ..
                           "The Preview tab has its own independent size setting.",
    venue_preview_animate = "Controls animation for venue sprite previews shown in tooltips.\n\n" ..
                           "Animated - sprite plays through all frames continuously.\n" ..
                           "Still - shows a single frame from the middle of the sheet.\n\n" ..
                           "The Preview tab has its own independent Animated/Still toggle.",
    venue_preview_combo   = "Which two instruments are in the player's band lineup.\n\n" ..
                           "Bass + Guitar  -  no Keys player; Keys camera shots are filtered.\n" ..
                           "Bass + Keys    -  no Guitar player; Guitar camera shots are filtered.\n" ..
                           "Guitar + Keys  -  no Bass player; Bass camera shots are filtered.\n\n" ..
                           "A camera event that requires the absent instrument gives way to a shot\n" ..
                           "stacked at the same position that fits. If none fits, the event stays\n" ..
                           "with a * - hover it for what the game does instead. Only the Camera row\n" ..
                           "is affected; Lighting and Post-Process are unchanged.",
    venue_preview_fb_generic = "No stacked camera shot fits the %s band.\n" ..
                           "In game this falls back to a generic full band shot, picked at random.\n" ..
                           "The picture shows one of them, %s.",
    venue_preview_fb_duo  = "No stacked camera shot fits the %s band.\n" ..
                           "In game this duo shot becomes a single shot of %s.\n" ..
                           "The picture shows that shot, %s.",
    venue_preview_fb_directed = "This directed cut cannot play with the %s band.\n" ..
                           "Directed cuts have no fallback: the game ignores it and the camera\n" ..
                           "keeps the previous shot. Stack a normal shot here to choose one.",
    venue_preview_show_mode = "Which events to display, and how.\n\n" ..
                           "Current only V     -  the active event of each category (started at or\n" ..
                           "                      before the playhead and not yet superseded), one\n" ..
                           "                      category per row.\n" ..
                           "Current only H     -  the same active events side by side on one row:\n" ..
                           "                      camera, lighting, then post-process.\n" ..
                           "Surrounding events -  three columns per category: the previous, current,\n" ..
                           "                      and next event.",
    venue_preview_blend  = "How this lighting / post proc preset hands over to the next one.\n\n" ..
                           "A blend is authored by re-stating the running preset a beat or two\n" ..
                           "before the change, so the game fades between them instead of cutting.\n" ..
                           "That re-stated copy is not a preset of its own, so the preview never\n" ..
                           "shows it as an event - it shows up here instead:\n\n" ..
                           "blends into next  -  an anchor is present, the game will fade.\n" ..
                           "blending now      -  the playhead is inside that fade right now.\n" ..
                           "hard cut to next  -  no anchor, the game switches instantly. This is\n" ..
                           "                     a valid authoring choice, not an error.\n\n" ..
                           "Camera events never show a line here - a camera cut never fades.",
    venue_preview_refresh_resume = "Auto-refresh was paused because the last VENUE MIDI read\n" ..
                           "took 150 ms or longer.\n\n" ..
                           "Click to re-enable automatic updates. If it pauses again,\n" ..
                           "the VENUE track may be too large to read in real time.",
    show_wip_tabs        = "Show work-in-progress tabs (Tempo Map).\n\n" ..
                           "They work at a basic level but have known issues and are\n" ..
                           "not ready for general use. Set to No to hide them from the tab bar.",
    workflow_file        = "Pick a workflow checklist template from resources/workflow/.\n\n" ..
                           "Add or edit .txt files there to tailor the checklist to your\n" ..
                           "own process - each file can use a different set of steps\n" ..
                           "(e.g. a shorter list for instrumental songs).\n\n" ..
                           "Switching templates drops checked history for any item not\n" ..
                           "in the newly-selected template - it isn't kept around for\n" ..
                           "when you switch back.",
    workflow_show_ts     = "Show the completion date/time under each checked item.\n\n" ..
                           "The timestamp is always recorded when you check an item -\n" ..
                           "this only controls whether it's displayed.",
    workflow_hide_done   = "Hide checked items so you can focus on what's left.\n\n" ..
                           "A section whose every item is checked is hidden entirely.\n" ..
                           "Nothing is lost - unchecking this shows everything again.",
}
