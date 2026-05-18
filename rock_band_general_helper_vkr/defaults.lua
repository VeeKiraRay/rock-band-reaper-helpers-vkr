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
        '[ProFilm_psychedelic_blue_red.pp]','[sucky_tv.pp]','[space_woosh.pp]',
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
    tm_search_window_ms   = 100,
    tm_drift_threshold_ms = 30,
    tm_bpm_failsafe       = 10.0,
    tm_first_measure      = 3,
    tm_timesig_num        = 0,
    tm_override_failsafe  = false,
    -- Tempo map track indices (not persisted — set by SetDefaultTempoTracks; -1 = none)
    tm_kick_idx           = -1,
    tm_snare_idx          = -1,
    tm_kit_idx            = -1,
    tm_fallback_idx       = -1,
    -- Cached filtered track lists (not persisted — rebuilt by RefreshTrackLists)
    all_track_list        = nil,
    audio_track_list      = nil,
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
                      "COUNT IN is always excluded — use Align count-in for that track.\n\n" ..
                      "Fully undoable.",
    align_count_in  = "Position COUNT IN clips at the standard count-in beat slots.\n\n" ..
                      "Reads the time signature from the project root tempo marker.\n" ..
                      "4/4:  m1 beats 1, 3  →  m2 beats 1, 2, 3, 4  (6 slots)\n" ..
                      "3/4:  m1 beat 1      →  m2 beats 1, 2, 3      (4 slots)\n" ..
                      "Other even time sigs use m1 beat 1 + midpoint, m2 all beats.\n\n" ..
                      "Clips beyond 6 are left untouched and reported.\n" ..
                      "Fully undoable.",
    list_venue  = "Find the VENUE track (by name) and read all its text events.\n\n" ..
                  "Reports: unknown events, consecutive camera repeats, directed cut spacing,\n" ..
                  "and a frequency count of every event used.",

    -- Tempo map — track dropdowns
    kick_track     = "Audio track containing the isolated kick drum stem (KICK AUDIO).\n" ..
                     "Primary source for downbeat detection.",
    snare_track    = "Audio track containing the isolated snare drum stem (SNARE AUDIO).\n" ..
                     "Used per-window when kick has no onset above threshold.",
    kit_track      = "Audio track containing the full drum kit mix (KIT AUDIO).\n" ..
                     "Used per-window when both kick and snare are quiet.",
    fallback_track = "Guitar or keys audio stem used as a last resort.\n" ..
                     "Tried per-window only when all drum sources are quiet.\n" ..
                     "Auto-detects GUITAR AUDIO, then KEYS AUDIO.",

    -- Tempo map — action buttons
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
                  "Read-only — nothing is written to the project.",
    clear_tempo = "Delete REAPER tempo markers except the root marker at index 0.\n\n" ..
                  "With a time selection: deletes only markers within the selection.\n" ..
                  "Without a time selection: deletes all markers except the root.\n\n" ..
                  "Fully undoable.",
    gen_tempo   = "Generate REAPER tempo markers from the drum audio.\n\n" ..
                  "Anchors on the configured first measure, then propagates the beat grid\n" ..
                  "forward, inserting a marker only where the detected downbeat deviates from\n" ..
                  "the expected position by more than the drift threshold.\n\n" ..
                  "Respects time selection if active.",

    -- Tempo map — sliders
    tm_rms_threshold      = "Audio level above which a drum hit onset is detected.\n" ..
                            "Lower = more sensitive; higher = ignore quiet hits.",
    tm_rms_window_ms      = "RMS analysis window in milliseconds.\n" ..
                            "Short (5–15 ms) gives sharp onset times for drums.",
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
    tm_timesig_num        = "Time signature numerator override.\n\n" ..
                            "0 = inherit from the project tempo marker that precedes the\n" ..
                            "analysis range.  Set to 3 for 3/4, 4 for 4/4, etc.",
    tm_override_failsafe  = "Bypass the BPM failsafe check.\n" ..
                            "Enable for songs with intentional large tempo changes.",
}
