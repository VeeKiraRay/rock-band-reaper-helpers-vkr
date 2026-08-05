-- Global state, constants, and tooltip text
-- Requires: nothing (loaded first)

----------------------------------------------------------------------
-- Valid VENUE text events (Rock Band Network specification)
----------------------------------------------------------------------
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
        '[lighting ()]','[first]','[previous]','[next]',
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
    -- Tempo map track indices (not persisted - set by SetDefaultTempoTracks; -1 = none)
    tm_kick_idx           = -1,
    tm_snare_idx          = -1,
    tm_kit_idx            = -1,
    tm_fallback_idx       = -1,
    -- MIDI converter: drums (persisted except track indices)
    mc_drum_src_idx       = -1,
    mc_drum_tgt_idx       = -1,
    mc_ghost_thresh       = 20,    -- velocity <= this = ghost note, skip
    mc_crash_to_green     = true,  -- false=crash→yellow(98), true=crash→green(100)
    mc_pro_drums          = true,  -- insert cymbal marker notes (110-112)
    mc_drum_preview       = false, -- true=preview only, false=auto-insert
    -- MIDI converter: keys (persisted except track indices)
    mc_keys_src_idx       = -1,
    mc_keys_rh_tgt_idx    = -1,
    mc_keys_lh_tgt_idx    = -1,
    mc_keys_mode          = 0,     -- 0=hand split, 1=pro keys, 2=5-key (stub)
    mc_keys_pk_src_idx    = -1,    -- Expert Pro Keys source for animation copy
    mc_keys_split_by_ch   = true,  -- true=channel-based (ch1=RH), false=pitch threshold
    mc_keys_split_pitch   = 60,    -- pitch threshold for hand split (default C4/middle C)
    mc_keys_preview       = false,
    -- MIDI converter: piano→Pro Keys range (persisted except track index)
    mc_pk_conv_tgt_idx    = -1,     -- Piano→PK target track
    mc_pk_insert_shifts   = false,  -- auto-insert lane shift markers
    -- MIDI converter: piano→5-Lane Keys (persisted except track index)
    mc_5k_tgt_idx         = -1,     -- 5-Lane Keys target track
    mc_5k_phrase_gap_ms   = 200,    -- silence gap (ms) that resets window root
    mc_5k_max_chord       = 3,      -- max simultaneous gems per chord (2 or 3)
    -- MIDI converter: guitar (persisted except track indices)
    mc_gtr_src_idx        = -1,
    mc_gtr_tgt_idx        = -1,
    mc_gtr_wrap_gap_ms    = 200,  -- rest gap (ms) shown as phrase boundary in report
    mc_gtr_max_chord      = 3,    -- max simultaneous gems per chord (2 or 3)
    mc_gtr_allow_14       = true, -- allow 1-4 chord stretches (spread >= 3)
    mc_gtr_workflow       = 0,    -- 0 = Preview, 1 = Auto-insert
    -- Tab Input guide (format/mode persisted; input buffers are ephemeral)
    mc_gtr_tab_format     = 0,    -- 0 = horizontal, 1 = vertical
    mc_gtr_tab_input_h    = '',   -- horizontal textarea content
    mc_gtr_tab_input_v    = '',   -- vertical textarea content
    tab_input_mode        = 0,    -- 0 = Guitar/Bass, 1 = Keys/Pro Keys, 2 = Vocal
    pk_tab_animation      = false, -- true = full C2-C4 range, skip lane window scoring
    -- MIDI alignment (persisted except track index)
    ma_midi_src_idx       = -1,
    ma_mode               = 0,  -- 0 = move only, 1 = move + stretch
    -- MIDI length sync (not persisted - track index only)
    ms_ref_idx            = -1,
    -- MIDI note length/sustain adjustment (persisted except track index)
    mn_midi_idx           = -1,
    mn_diff_idx           = 1,     -- 1=Expert, 2=Hard, 3=Medium, 4=Easy (no "All")
    mn_note_type          = 0,     -- 0 = All notes, 1 = Only sustains
    mn_note_denom         = 32,    -- All notes: note size denominator (16/32/64/128)
    mn_sustain_32nds      = 3,     -- Only sustains: gap size in 32nd notes (0-32);
                                   -- matches SustainGapDefaultForDiff(1) (Expert),
                                   -- which prefills it when the tier is changed
    -- Pattern Replace (session-only - not persisted)
    mr_midi_src_idx       = -1,
    mr_diff_idx           = 0,     -- 0=All, 1=Expert, 2=Hard, 3=Medium, 4=Easy
    mr_search_notes       = nil,   -- array of {rel_s, rel_e, pitch} or nil
    mr_search_label       = '',
    mr_search_dur_ppq     = 0,
    mr_search_step_ppq    = 0,     -- 1 measure in PPQ; scan stride for DoMIDIPatternReplace
    mr_replace_notes      = nil,
    mr_replace_label      = '',
    mr_replace_dur_ppq    = 0,
    -- Pro Keys difficulty (not persisted - auto-detected by name)
    diff_pk_x_idx         = -1,
    diff_pk_h_idx         = -1,
    diff_pk_m_idx         = -1,
    diff_pk_e_idx         = -1,
    -- 5-Lane Keys difficulty (not persisted - auto-detected by name)
    diff_5k_idx           = -1,
    diff_5k_pk_reduce     = true,  -- Copy to X: keep only events matching a same-tier Pro Keys note (persisted)
    -- Guitar/Bass difficulty (not persisted - auto-detected by name)
    diff_gtr_idx          = -1,
    diff_bass_idx         = -1,
    diff_gb_instrument    = 'gtr',  -- 'gtr' or 'bass' (persisted)
    -- Drums difficulty (not persisted - auto-detected by name)
    diff_drums_idx        = -1,
    -- Difficulty tab: pending "Copy to X" overwrite confirmation (not persisted,
    -- transient UI state). nil = no popup. Otherwise: { message = string,
    -- on_confirm = function() ... end } - set by a Copy*Diff call when the
    -- target already has notes; consumed by the confirm popup in ui_difficulty.lua.
    diff_copy_pending     = nil,
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
    venue_preview_show_mode = 0,    -- 0=current only, 1=surrounding events
    -- Manual gen (not persisted - session state only)
    venue_mg_coop        = '',   -- full event e.g. '[coop_all_behind]'
    venue_mg_directed    = '',   -- bare name e.g. 'directed_all'
    venue_mg_lighting    = '',   -- bare name e.g. 'loop_warm'
    venue_mg_postproc    = '',   -- name with ext e.g. 'bloom.pp'
    venue_mg_special     = '',   -- full event e.g. '[bonusfx]'
    venue_mg_kf_rate     = 2,    -- keyframe rate in beats (1-8)
    venue_mg_remove_type = 0,    -- 0=Camera 1=Lighting 2=PostProc 3=Special 4=All
    -- Keyframes tab (not persisted - session state only)
    venue_kf_rate        = 2,    -- keyframe rate in beats (1-8), independent of venue_mg_kf_rate
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
    -- UI visibility (persisted)
    show_wip_tabs           = false, -- show Tempo Map, Drums, Keys, Guitar tabs
    -- Workflow checklist (General > Workflow)
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
    save          = "Save current settings to this project.",
    load          = "Load previously saved settings from this project.",
    track_refresh = "Refresh the track lists to include any newly added or renamed tracks.",

    -- General tab
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
    venue_sections  = "Read [prc_*] section markers from the EVENTS track and list the\n" ..
                      "detected song sections with their time ranges.\n\n" ..
                      "Letter-suffix events ([prc_verse_1a], [prc_verse_1b], ...) are grouped\n" ..
                      "into a single section. Plain-number ([prc_verse_1]) and bare\n" ..
                      "([prc_verse]) events are each their own standalone section.",
    venue_sing_along = "Derive VENUE sing-along notes from the HARM2/HARM3 harmony tracks:\n" ..
                      "pitch 87 (guitarist) from HARM2, pitch 85 (bassist) from HARM3.\n\n" ..
                      "For each vocal phrase (bounded by a pitch-105 marker) where the harmony\n" ..
                      "track actually sings a note, draws a note spanning that phrase. Phrases\n" ..
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
    venue_keyframe_align = "Where the [first]/[next] keyframe sequence for manual lighting begins.\n\n" ..
                           "Section start: exactly at the [prc_*] section event (default).\n" ..
                           "Closest beat:  snapped to the nearest beat boundary.\n" ..
                           "Downbeat:      [first] at section start; [next] from the next measure boundary.\n\n" ..
                           "Instrument modes ignore the theme's keyframe_rate and emit [next]\n" ..
                           "only at subdivision grid points (beat/half-beat/quarter-beat) where notes actually exist:\n" ..
                           "  Guitar notes - reads PART GUITAR (pitches 96-100)\n" ..
                           "  Bass notes   - reads PART BASS   (pitches 96-100)\n" ..
                           "  Keys notes   - reads PART KEYS   (pitches 96-100)\n" ..
                           "  Drum kicks   - reads PART DRUMS  (pitch 96 only)\n" ..
                           "  Drum snare   - reads PART DRUMS  (pitch 97 only)",

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
                         "stomp) require [first]/[next] keyframe events - set Keyframe rate\n" ..
                         "to control the spacing.\n\n" ..
                         "Auto presets (loop_*, harmony, frenzy, silhouettes, etc.) need no\n" ..
                         "keyframes. Leave blank to skip lighting for this section.",
    venue_sec_postproc = "Post-process effect (.pp file) for this section.\n\n" ..
                         "Leave blank to skip.",
    venue_sec_kr       = "Keyframe rate in beats: how often [first]/[next] events are placed.\n\n" ..
                         "Only used when the chosen lighting preset is a manual type\n" ..
                         "(verse, chorus, manual_cool, manual_warm, dischord, stomp).\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_lt_blend = "Place the lighting event this many beats BEFORE the section start.\n\n" ..
                         "Useful for smooth lighting transitions into the section.\n" ..
                         "Clamped to the item start if it would reach before the beginning.\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_pp_blend = "Place the post-process event this many beats BEFORE the section start.\n\n" ..
                         "Clamped to the item start if it would reach before the beginning.\n\n" ..
                         "Ctrl+click to type an exact value.",
    venue_sec_dircut   = "Insert a forced directed camera cut at the section start.\n\n" ..
                         "Select a directed event name, or leave blank for no forced cut.\n" ..
                         "Random directed cuts are suppressed in section generation mode.",
    venue_sec_bonusfx  = "Insert a [bonusfx] event at the section start.",

    -- Keyframes tab
    venue_kf_regenerate = "Find every manual lighting event ([lighting (verse)], (chorus),\n" ..
                          "(manual_cool), (manual_warm), (dischord), (stomp)) already on the\n" ..
                          "VENUE track and regenerate its [first]/[next] keyframes, running from\n" ..
                          "that lighting event to the next lighting event of any kind.\n\n" ..
                          "Only [first]/[next]/[previous] events are cleared and replaced -\n" ..
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
                       "always insert the plain form.",
    venue_ev_next    = "The exact event the Add button will insert at the current playhead\n" ..
                       "position, based on the selection, number, letter mode, and the\n" ..
                       "events already on the EVENTS track.\n\n" ..
                       "Shows '(blocked)' when the Add would be refused (duplicate, mixed\n" ..
                       "plain/lettered or bare/numbered forms, wrong order, or another\n" ..
                       "event on the same spot; crowd events are exempt) - hover it for\n" ..
                       "the reason, which is also reported in the result on Add.",
    venue_ev_add     = "Insert the shown event at the exact playhead position on the\n" ..
                       "EVENTS track.\n\nFully undoable.",
    venue_ev_bookends = "Insert the minimal event set every song needs:\n" ..
                        "  measure 1:  [prc_intro] + [crowd_normal]\n" ..
                        "  measure 3:  [music_start]\n" ..
                        "  measure E-5 / E-2 / E:  [prc_outro] / [music_end] / [end]\n" ..
                        "where E is the last measure fully contained in the MIDI item.\n" ..
                        "Items shorter than 7 full measures skip the three end events.\n\n" ..
                        "Existing instances of these six events are removed first, so\n" ..
                        "re-running recalculates their positions. A different event\n" ..
                        "already sitting on a target measure makes that bookend be\n" ..
                        "skipped (reported in the result).\n\nFully undoable.",
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

    -- MIDI converter - Drums tab
    mc_drum_src    = "MIDI track containing the source drum notation.\n" ..
                     "Typically a Guitar Pro or DAW MIDI export.\n" ..
                     "Should use General MIDI drum pitch numbers (channel 10 convention).",
    mc_drum_tgt    = "Target MIDI track where Rock Band drum notes will be written.\n" ..
                     "Must have an existing MIDI item (e.g. the PART DRUMS track).",
    mc_ghost_thresh = "Notes at or below this velocity are treated as ghost notes and skipped.\n" ..
                      "0 = keep all notes.  Typical ghost threshold: 20-40.",
    mc_crash_color = "Choose which lane crash cymbal notes map to.\n\n" ..
                     "Green (default): crash → note 100. No tom marker added - green notes\n" ..
                     "display as cymbal in Pro Drums by default.\n" ..
                     "Yellow: crash → note 98. Use when you need crash on the same lane as hi-hat,\n" ..
                     "e.g. for double-crash hits or sections where green is occupied by toms.\n\n" ..
                     "Ride cymbals always map to Blue (99).",
    mc_pro_drums   = "Insert tom marker notes (110=Yellow, 111=Blue, 112=Green).\n\n" ..
                     "Required for Rock Band 3 Pro Drums mode. In-game, yellow/blue/green gem\n" ..
                     "notes display as cymbals by default. Adding a same-length tom marker note\n" ..
                     "alongside a gem switches its display to a tom pad.\n" ..
                     "Disable if you are authoring standard (non-pro) drums only.",
    mc_drum_preview = "Preview: show lane counts without writing to the project.\n" ..
                      "Auto-insert: analyse and insert notes in one step (fully undoable).",

    -- MIDI converter - Keys tab
    mc_keys_src     = "MIDI track containing the source piano notation.\n" ..
                      "Guitar Pro exports typically use channel 1 for right hand and\n" ..
                      "channel 2 for left hand.",
    mc_keys_rh_tgt  = "Target track that will receive right-hand notes after the split.\n" ..
                      "Set to (none) to skip writing the right hand.",
    mc_keys_lh_tgt  = "Target track that will receive left-hand notes after the split.\n" ..
                      "Set to (none) to skip writing the left hand.",
    mc_keys_split   = "How to determine which notes belong to each hand.\n\n" ..
                      "Channel-based: right hand = MIDI channel 1, left hand = channel 2.\n" ..
                      "  Guitar Pro and most notation software exports use this convention.\n\n" ..
                      "Pitch threshold: notes at or above the threshold pitch = right hand;\n" ..
                      "  notes below = left hand.  Use when channels are not separated.",
    mc_keys_split_pitch = "Pitch boundary for the pitch-threshold hand split.\n" ..
                          "Notes at or above this pitch are treated as right hand.\n" ..
                          "Default C4 (middle C, pitch 60) works for most piano pieces.",
    mc_keys_preview = "Preview: show note counts without writing to the project.\n" ..
                      "Auto-insert: split and insert notes in one step (fully undoable).",

    -- MIDI converter - Guitar tab
    mc_gtr_src       = 'Source MIDI track with raw guitar pitches (Guitar Pro import, DAW export, etc.).\n' ..
                       'Pitches can be any range - the tool maps them to 5 RB gem positions.',
    mc_gtr_tgt       = 'Target MIDI track to write Rock Band Expert Guitar gems (96-100).\n' ..
                       'Must already have a MIDI item (e.g. the PART GUITAR track).',
    mc_gtr_wrap_gap  = 'Rest gap in milliseconds that marks a phrase boundary in the preview report.\n' ..
                       'Gem assignments are NOT reset at phrase boundaries - the same pitch always\n' ..
                       'maps to the same gem across the whole track. Wrapping (reusing a gem for\n' ..
                       'a new pitch) only occurs when all 5 gem slots are already taken.',
    mc_gtr_max_chord = 'Maximum simultaneous gems per chord. 3-note chords are reserved for augmented,\n' ..
                       'diminished, or seventh-type chords. Set to 2 to keep all chords as 2-finger.',
    mc_gtr_allow_14  = 'When unchecked, any 1-4 chord (gem spread ≥ 3, e.g. Green+Blue or Red+Orange)\n' ..
                       'is narrowed to a 1-3 chord by moving the upper gem one step closer.',
    mc_gtr_workflow  = 'Preview: show gem assignments and reasoning in the result panel below.\n' ..
                       'Auto-insert: write gems directly to the target track (fully undoable).',
    mc_gtr_convert   = 'Map source MIDI pitches to Expert Guitar gems on the target track.\n\n' ..
                       'Respects time selection if active.',
    mc_gtr_validate  = 'Check existing Expert Guitar gems on the target track against RB authoring rules:\n' ..
                       '  • Max 3 notes per chord\n' ..
                       '  • No Green+Orange in 3-note chords\n' ..
                       '  • No overlapping notes\n' ..
                       '  • Sustain gap requirements\n' ..
                       '  • Minimum note length (1/64th)\n\n' ..
                       'Respects time selection if active.',

    -- Tab Input guide
    mc_gtr_tab_format  = 'Horizontal: one event per line - 6 space-separated tokens, left = highest string (e),\n' ..
                         'right = lowest string (E). Use a fret number or dash for unplayed.\n' ..
                         'Supports multi-digit frets (10, 12, etc.). Blank line = phrase break.\n\n' ..
                         'Vertical: standard guitar tab layout - 6 rows (e/B/G/D/A/E),\n' ..
                         'each row is space-separated tokens, columns = events. All-dash column = phrase break.',
    mc_gtr_add_note    = 'Append a new empty note slot to the input.\n\n' ..
                         'Horizontal: appends a new all-dash line (- - - - - -).\n' ..
                         'Vertical: pads all rows to equal length and appends a new all-dash column.',
    mc_gtr_run_guide   = 'Convert the tab input to Rock Band gem colors and display the result.\n\n' ..
                         'Nothing is written to the project - this is a reference guide only.\n' ..
                         'Uses the same Wrap gap and Max chord settings as the Guitar converter.',
    tab_input_mode     = 'Switch the Tab Input mode.\n\n' ..
                         'Guitar/Bass: standard guitar tab format (horizontal or vertical).\n' ..
                         'Keys/Pro Keys: enter fret numbers relative to guitar string pitches,\n' ..
                         'shifted into the C2-C4 Pro Keys range.\n' ..
                         'Vocal: same tab format, shifted into the wider C1-C5 vocal range.',
    pk_run_guide       = 'Convert frets to pitches, shift into the C2-C4 Pro Keys range\n' ..
                         '(MIDI 48-72), and suggest the best lane range.\n\n' ..
                         'Nothing is written to the project - reference guide only.\n\n' ..
                         'When \xe2\x80\x9cFor animation\xe2\x80\x9d is checked: skips lane window scoring\n' ..
                         'and reports against the full C2-C4 range instead.',
    pk_tab_animation   = 'Animation mode: score against the full C2-C4 range instead of a\n' ..
                         '10th (17-key lane window). Use when planning notes for\n' ..
                         'PART KEYS_ANIM_RH or PART KEYS_ANIM_LH.\n\n' ..
                         'Lane range suggestions are hidden; only out-of-C2-C4 notes are flagged.',
    voc_run_guide      = 'Convert frets to pitches, find the best octave shift to fit C1-C5\n' ..
                         '(MIDI 36-84), and report any out-of-range notes.\n\n' ..
                         'Nothing is written to the project - reference guide only.\n' ..
                         'Blank lines separate phrases.',

    -- MIDI converter - Keys tab (Pro Keys animation)
    mc_keys_pk_src     = 'Expert Pro Keys source track (PART REAL_KEYS_X or similar).\n' ..
                         'Notes in C2-C4 (MIDI 48-72) are copied to the animation track.\n' ..
                         'Lane shift markers (MIDI 0-9) are automatically excluded.',
    gen_animation      = 'Copy Expert Pro Keys notes (C2-C4) to the animation target track(s).\n\n' ..
                         'Lane shift markers and any notes outside C2-C4 are stripped.\n' ..
                         'RH/LH targets are shared with the Hand Split section above.\n\n' ..
                         'Respects time selection if active. Fully undoable.',

    -- MIDI converter - Keys tab (piano→Pro Keys range)
    mc_pk_conv_tgt      = 'Target Pro Keys track (typically PART REAL_KEYS_X).\n' ..
                          'Notes will be octave-shifted into C2-C4 (MIDI 48-72).',
    mc_pk_insert_shifts = 'Auto-insert lane shift marker notes when the melody moves outside\n' ..
                          'the current 10th-window range.\n\n' ..
                          'Markers are MIDI notes 0-9 (C-A in the lowest octave), placed\n' ..
                          'approximately one measure before the range transition.\n' ..
                          'They can be moved or deleted after insertion.',
    gen_pk_from_piano   = 'Convert piano MIDI to Pro Keys range by octave-shifting all notes\n' ..
                          'into C2-C4 (MIDI 48-72).\n\n' ..
                          'Each note is shifted up or down by whole octaves until it lands in range.\n' ..
                          'Uses the source track from Hand Split above.\n\n' ..
                          'Respects time selection if active. Fully undoable.',

    -- MIDI converter - Keys tab (piano→5-Lane Keys)
    mc_5k_tgt          = 'Target 5-Lane Keys track (PART KEYS).\n' ..
                         'Output notes will be Expert gems (pitches 96-100).',
    mc_5k_phrase_gap   = 'Rest gap in milliseconds that resets the gem window to Green (position 0).\n' ..
                         'After a silence of at least this length, the next note starts a new phrase\n' ..
                         'and anchors the window to its pitch.',
    mc_5k_max_chord    = 'Maximum simultaneous gems per chord.\n' ..
                         '3-note chords keep the lowest, one middle, and highest note.\n' ..
                         '2-note chords keep only the lowest and highest.',
    gen_5k             = 'Map piano MIDI to 5-lane Expert Keys gems (96-100).\n\n' ..
                         'A 5-semitone window tracks the melody: the window root maps to Green,\n' ..
                         'and the window shifts when the melody moves outside it.\n' ..
                         'After a rest of the configured phrase gap length, the window resets.\n\n' ..
                         'Uses the source track from Hand Split above.\n\n' ..
                         'Respects time selection if active. Fully undoable.',

    -- MIDI alignment
    ma_midi_src = "MIDI track whose first item will be moved and/or stretched to align\n" ..
                  "with the time selection.\n\n" ..
                  "Only the first MIDI item on the track is affected.",
    ma_mode     = "Move only: shifts the item so the first note lands at the time selection start.\n" ..
                  "Move + Stretch: also adjusts the playback rate so the last note lands at the\n" ..
                  "time selection end.\n\n" ..
                  "The result does not need to be exact - snap/quantize finishes alignment.",
    ma_align    = "Move (and optionally stretch) the MIDI item to align with the time selection.\n\n" ..
                  "Set a time selection first. Move + Stretch adjusts the playback rate so the\n" ..
                  "last note lands at the time selection end.\n\n" ..
                  "Fully undoable.",

    -- MIDI tab - Length Sync
    ms_ref    = "The MIDI track whose item length will be used as the target.\n\n" ..
                "Pick the track that is already sized to the full song length.",
    ms_resize = "Set the item length of every MIDI item that starts at project position 0\n" ..
                "to match the reference track - identical to dragging the right edge of\n" ..
                "each item. Notes are not moved or deleted.\n\n" ..
                "MIDI items that do NOT start at position 0 are skipped; those are\n" ..
                "reference clips managed by the MIDI Alignment section above.\n\n" ..
                "If shrinking: check that no notes exist beyond the new item end.",

    -- MIDI tab - Midi note (length/sustain adjustment)
    mn_midi_track  = "MIDI track to adjust note lengths on.\n\n" ..
                     "A warning appears below if this is not the track currently open in\n" ..
                     "the MIDI editor.",
    mn_diff        = "Restricts the adjustment to one difficulty tier's pitch range.\n\n" ..
                     "PART DRUMS/GUITAR/BASS/KEYS: Expert 96-100, Hard 84-88,\n" ..
                     "Medium 72-76, Easy 60-64.\n\n" ..
                     "PART VOCALS/HARM1-3 and PART REAL_KEYS*/PART KEYS_ANIM* always use\n" ..
                     "their own fixed range regardless of this selector.\n\n" ..
                     "No notes outside the selected range are touched.\n\n" ..
                     "Changing the tier prefills the 32nd note amount with that tier's\n" ..
                     "standard gap (Expert 3, Hard 4, Medium 8, Easy 16). Adjust it\n" ..
                     "afterwards and your value sticks.",
    mn_note_type   = "Non-sustains: unify every note SHORTER than 1/8 note to the selected\n" ..
                     "Note size. Existing sustains (>= 1/8 note) are left untouched.\n\n" ..
                     "Only sustains: leave note starts and short notes untouched; instead\n" ..
                     "adjust the gap between each sustain (>= 1/8 note) and the next note.",
    mn_note_denom  = "Standard note length every non-sustain note in range is set to (start\n" ..
                     "position unchanged, only the end position moves). Default: 1/32.\n\n" ..
                     "1/8 is not offered: that is the sustain threshold.",
    mn_sustain_32nds = "Target gap, in 32nd notes, between a sustain's end and the next note.\n\n" ..
                     "Widens or shortens the sustain as needed to hit this gap exactly.\n" ..
                     "Prefilled per difficulty tier (Expert 3, Hard 4, Medium 8, Easy 16).\n\n" ..
                     "Only looks up to a half note (16x32nd notes) ahead for a next note -\n" ..
                     "sustains with nothing that close are left unchanged. A note starting\n" ..
                     "INSIDE the sustain always counts as the next note, however far the\n" ..
                     "following one is, so an overlap is never left behind.",
    mn_adjust      = "Apply the note-length/sustain-gap adjustment to the selected track\n" ..
                     "and difficulty range.\n\n" ..
                     "With a time selection: only adjusts notes starting inside it.\n" ..
                     "Without: adjusts the whole MIDI item.\n\n" ..
                     "Fully undoable.",

    -- MIDI tab - Pattern Replace
    mr_midi_src    = "MIDI track to search and replace patterns within.\n\n" ..
                     "All four actions (Set Search, Set Replace, Replace All, Fill Range)\n" ..
                     "read from and write to this track.",
    mr_diff        = "Restricts Pattern actions to one difficulty tier's pitch range.\n\n" ..
                     "PART DRUMS/GUITAR/BASS/KEYS: All=60-100, or the single tier's band\n" ..
                     "(Expert 96-100, Hard 84-88, Medium 72-76, Easy 60-64).\n\n" ..
                     "PART VOCALS/HARM1-3 and PART REAL_KEYS*/PART KEYS_ANIM* always use\n" ..
                     "their own fixed range regardless of this selector.\n\n" ..
                     "Any other track: no filtering, full MIDI note range.",
    mr_set_search  = "Capture the current time selection as the pattern to search for.\n\n" ..
                     "Both patterns must cover exactly the same duration.\n" ..
                     "Setting a new Search pattern with a different length clears the Replace pattern.",
    mr_set_replace = "Capture the current time selection as the replacement pattern.\n\n" ..
                     "Must cover the same duration as the Search pattern (if one is already set).\n" ..
                     "Also used as the source for Fill Range.",
    mr_do_replace  = "Scan the MIDI track for every window matching the Search pattern\n" ..
                     "and replace it with the Replace pattern.\n\n" ..
                     "With a time selection: only scans within that range.\n" ..
                     "Without: scans the full MIDI item.\n\n" ..
                     "Fully undoable.",
    mr_fill_range  = "Tile the Replace pattern across the active time selection.\n\n" ..
                     "Clears each destination window first, then inserts the Replace notes.\n" ..
                     "Requires an active time selection.\n\n" ..
                     "Fully undoable.",
    mr_go_prev     = "Move the edit cursor to the nearest Search-pattern match before the\n" ..
                     "current cursor position.\n\n" ..
                     "With a time selection: only searches within that range.\n" ..
                     "Without: searches the full MIDI item.",
    mr_go_next     = "Move the edit cursor to the nearest Search-pattern match after the\n" ..
                     "current cursor position.\n\n" ..
                     "With a time selection: only searches within that range.\n" ..
                     "Without: searches the full MIDI item.",
    mr_list_search = "List every Search-pattern match with its measure and time location.\n\n" ..
                     "With a time selection: only searches within that range.\n" ..
                     "Without: searches the full MIDI item.\n\n" ..
                     "Read-only.",

    -- General tab - Song fade out
    song_fade_out = "Create a volume fade out on the SONG AUDIO track within the time selection.\n\n" ..
                    "Volume starts at the track's current fader level and reaches silence at\n" ..
                    "the end of the selection. Existing envelope points inside the selection\n" ..
                    "are replaced; points outside are untouched.\n\n" ..
                    "Select a range that starts at a musically meaningful point (e.g. end of\n" ..
                    "the last vocal phrase) for the most natural-sounding cutoff.",

    -- Difficulty tab - Pro Keys
    diff_pk_x       = "Expert Pro Keys track (PART REAL_KEYS_X).\n" ..
                      "Source for Copy to Hard and cross-difficulty validation.",
    diff_pk_h       = "Hard Pro Keys track (PART REAL_KEYS_H).\n" ..
                      "Validated against Hard authoring rules and compared to Expert.",
    diff_pk_m       = "Medium Pro Keys track (PART REAL_KEYS_M).\n" ..
                      "Validated against Medium authoring rules and compared to Expert.",
    diff_pk_e       = "Easy Pro Keys track (PART REAL_KEYS_E).\n" ..
                      "Validated against Easy authoring rules and compared to Expert.",
    diff_autodetect = "Search for PART REAL_KEYS_X/H/M/E tracks by exact name and assign them.\n" ..
                      "Resets existing selections before scanning.",
    diff_pk_copy    = "Copy notes from the tier above (Expert\xe2\x86\x92Hard, Hard\xe2\x86\x92Medium,\n" ..
                      "Medium\xe2\x86\x92Easy) onto this difficulty's own track, verbatim -\n" ..
                      "including lane-shift markers. A starting point to hand-edit down,\n" ..
                      "not an automatic reduction.\n\n" ..
                      "If the source track has no notes, nothing is copied and the result\n" ..
                      "panel reports it. If the target track already has notes, a\n" ..
                      "confirmation popup asks before clearing and overwriting them.\n\n" ..
                      "Fully undoable. Respects time selection if active.",
    diff_validate   = "Validate this difficulty track against RBN Pro Keys authoring rules:\n" ..
                      "chord count/span, interval jumps, spacing, lane range markers,\n" ..
                      "and whether any notes exceed what is in Expert.\n\n" ..
                      "Only notes in the playable C2-C4 range are validated; overdrive,\n" ..
                      "glissando, and trill markers are ignored.\n\n" ..
                      "Read-only - no project changes are made.\n" ..
                      "Respects time selection if active.",
    diff_validate_all = "Validate all four Pro Keys difficulty tracks in one combined report.\n" ..
                        "Skips any difficulty whose track is set to (none).\n\n" ..
                        "Read-only - no project changes are made.\n" ..
                        "Respects time selection if active.",

    -- Difficulty tab - 5-Lane Keys
    diff_5k_track     = "5-Lane Keys track (PART KEYS).\n" ..
                        "All four difficulties live on this single track in separate pitch ranges:\n" ..
                        "Expert 96-100 | Hard 84-88 | Medium 72-75 | Easy 60-62",
    diff_5k_autodetect = "Search for a track named PART KEYS and assign it.\n" ..
                         "Resets the current selection before scanning.",
    diff_5k_copy      = "Copy notes from the tier above (Expert\xe2\x86\x92Hard, Hard\xe2\x86\x92Medium,\n" ..
                        "Medium\xe2\x86\x92Easy) onto this difficulty's own pitch range. Colors\n" ..
                        "above this tier's ceiling (e.g. Orange copied down to Medium) are\n" ..
                        "pulled down a color instead of dropped.\n\n" ..
                        "See \"Reduce using Pro Keys\" below for optional rhythm reduction\n" ..
                        "guided by the same-tier Pro Keys track; with it off, this is a\n" ..
                        "starting point to hand-edit down, not an automatic reduction.\n\n" ..
                        "If the source range has no notes, nothing is copied and the result\n" ..
                        "panel reports it. If the target range already has notes, a\n" ..
                        "confirmation popup asks before clearing and overwriting them.\n\n" ..
                        "Fully undoable. Respects time selection if active.",
    diff_5k_pk_reduce = "When copying to Hard/Medium/Easy, keep only events that land on a\n" ..
                        "note in the matching-tier Pro Keys track (PART REAL_KEYS_H/M/E) -\n" ..
                        "mirrors whatever rhythm reduction was already hand-charted on Pro\n" ..
                        "Keys onto the Keys copy, instead of copying every event from the\n" ..
                        "tier above unfiltered. Match tolerance: 1/32 note. Kept events also\n" ..
                        "have their sustain length matched to the Pro Keys note's length, so\n" ..
                        "both charts agree on note length (not just onset) - Pro Keys is the\n" ..
                        "master chart both are reduced from.\n\n" ..
                        "If the matching Pro Keys track isn't selected, missing, or empty,\n" ..
                        "Copy falls back to an unfiltered copy and says so in the result.",
    diff_5k_validate  = "Validate the notes in this difficulty's pitch range against\n" ..
                        "5-Lane Keys authoring rules: chord count, note spacing, note\n" ..
                        "length, and sustain gaps.\n\n" ..
                        "Read-only - no project changes are made.\n" ..
                        "Respects time selection if active.",
    diff_5k_validate_all = "Validate all four 5-Lane Keys difficulty ranges in one combined report.\n\n" ..
                           "Read-only - no project changes are made.\n" ..
                           "Respects time selection if active.",

    -- Difficulty tab - Guitar/Bass
    diff_gb_instrument = "Switch which instrument's track and difficulty ranges are shown below.\n\n" ..
                         "Guitar and Bass share identical RBN authoring rules (ranges, chord\n" ..
                         "legality, sustain/HOPO rules) - only the track differs.",
    diff_gb_track      = "Guitar/Bass difficulty track (PART GUITAR or PART BASS, matching the\n" ..
                         "instrument selected above).\n" ..
                         "All four difficulties live on this single track in separate pitch ranges:\n" ..
                         "Expert 96-100 | Hard 84-88 | Medium 72-75 | Easy 60-62",
    diff_gb_autodetect = "Search for tracks named PART GUITAR and PART BASS by exact name and\n" ..
                         "assign them. Resets both selections before scanning.",
    diff_gb_copy       = "Copy notes from the tier above (Expert\xe2\x86\x92Hard, Hard\xe2\x86\x92Medium,\n" ..
                         "Medium\xe2\x86\x92Easy) onto this difficulty's own pitch range, for the\n" ..
                         "instrument selected above. Colors above this tier's ceiling (e.g.\n" ..
                         "Orange copied down to Medium) are pulled down a color instead of\n" ..
                         "dropped - a starting point to hand-edit down, not an automatic\n" ..
                         "reduction.\n\n" ..
                         "If the source range has no notes, nothing is copied and the result\n" ..
                         "panel reports it. If the target range already has notes, a\n" ..
                         "confirmation popup asks before clearing and overwriting them.\n\n" ..
                         "Fully undoable. Respects time selection if active.",
    diff_gb_validate   = "Validate the notes in this difficulty's pitch range against RBN\n" ..
                         "Guitar/Bass authoring rules: chord count, chord shape (illegal\n" ..
                         "Green+Orange combinations, span limits), note length, overlap,\n" ..
                         "sustain gaps, force-HOPO markers (not allowed on Medium/Easy), and\n" ..
                         "trill/tremolo marker velocity (Hard eligibility).\n\n" ..
                         "Read-only - no project changes are made.\n" ..
                         "Respects time selection if active.",
    diff_gb_validate_all = "Validate all four Guitar/Bass difficulty ranges in one combined report.\n\n" ..
                           "Read-only - no project changes are made.\n" ..
                           "Respects time selection if active.",

    -- Difficulty tab - Drums
    diff_drums_track      = "Drums difficulty track (PART DRUMS).\n" ..
                            "All four difficulties live on this single track in separate pitch ranges:\n" ..
                            "Expert 96-100 | Hard 84-88 | Medium 72-76 | Easy 60-64",
    diff_drums_autodetect = "Search for a track named PART DRUMS and assign it.\n" ..
                            "Resets the current selection before scanning.",
    diff_drums_copy       = "Copy notes from the tier above (Expert\xe2\x86\x92Hard, Hard\xe2\x86\x92Medium,\n" ..
                            "Medium\xe2\x86\x92Easy) onto this difficulty's own pitch range - a\n" ..
                            "starting point to hand-edit down, not an automatic reduction.\n\n" ..
                            "If the source range has no notes, nothing is copied and the result\n" ..
                            "panel reports it. If the target range already has notes, a\n" ..
                            "confirmation popup asks before clearing and overwriting them.\n\n" ..
                            "Fully undoable. Respects time selection if active.",
    diff_drums_validate   = "Validate the notes in this difficulty's pitch range against RBN\n" ..
                            "Drums authoring rules: no 3-limb hits on Medium (kick+snare+cymbal/tom\n" ..
                            "together), no gems paired with kick on Easy, and roll/trill marker\n" ..
                            "velocity on Hard (41-50 required for Hard eligibility).\n\n" ..
                            "Also reports [mix N drums...] disco-flip event status as an\n" ..
                            "informational note - not a pass/fail check, since correctness\n" ..
                            "depends on the surrounding beat pattern.\n\n" ..
                            "Read-only - no project changes are made.\n" ..
                            "Respects time selection if active.",
    diff_drums_validate_all = "Validate all four Drums difficulty ranges in one combined report.\n\n" ..
                              "Read-only - no project changes are made.\n" ..
                              "Respects time selection if active.",

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
                           "Camera events that require the absent instrument are replaced by an\n" ..
                           "alternative event at the same position, if one exists. Only the Camera\n" ..
                           "row is affected; Lighting and Post-Process are unchanged.",
    venue_preview_show_mode = "How many events to display per category.\n\n" ..
                           "Current only       -  one column showing the active event (started at or\n" ..
                           "                      before the playhead and not yet superseded).\n" ..
                           "Surrounding events -  three columns: the previous, current, and next event.",
    venue_preview_refresh_resume = "Auto-refresh was paused because the last VENUE MIDI read\n" ..
                           "took 150 ms or longer.\n\n" ..
                           "Click to re-enable automatic updates. If it pauses again,\n" ..
                           "the VENUE track may be too large to read in real time.",
    show_wip_tabs        = "Show work-in-progress tabs (Tempo Map, Drums, Keys, Guitar).\n\n" ..
                           "These tabs work at a basic level but have known issues and are\n" ..
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
