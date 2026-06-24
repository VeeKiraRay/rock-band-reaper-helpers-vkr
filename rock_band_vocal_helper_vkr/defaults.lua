-- Constants, defaults, live state, and reset functions
-- TIPS table → tips.lua

----------------------------------------------------------------------
-- Pitch source modes
----------------------------------------------------------------------
MODE_SINGLE    = 0
MODE_REFERENCE = 1
MODE_YIN       = 2

-- Rock Band 3 vocal note range. Notes outside this are phrase/overdrive markers.
RB3_MIN_PITCH    = 36   -- C1
RB3_MAX_PITCH    = 84   -- C5
RB3_PHRASE_PITCH = 105  -- phrase/overdrive marker pitch

-- Diatonic harmony support
HARM_SCALE = {
    major = {0, 2, 4, 5, 7, 9, 11},
    minor = {0, 2, 3, 5, 7, 8, 10},
}

HARM_NOTE_NAMES = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}

HARM_MODES = {
    { label = 'Copy as-is',                    diatonic = false, offset =  0 },
    { label = 'Fixed minor 3rd above (+3 st)', diatonic = false, offset =  3 },
    { label = 'Fixed major 3rd above (+4 st)', diatonic = false, offset =  4 },
    { label = 'Fixed minor 3rd below (-3 st)', diatonic = false, offset = -3 },
    { label = 'Fixed major 3rd below (-4 st)', diatonic = false, offset = -4 },
    { label = 'Diatonic 3rd above',            diatonic = true,  dir    =  1 },
    { label = 'Diatonic 3rd below',            diatonic = true,  dir    = -1 },
    { label = 'Fixed 4th above (+5 st)',        diatonic = false, offset =  5 },
    { label = 'Fixed 5th above (+7 st)',        diatonic = false, offset =  7 },
    { label = 'Fixed 4th below (-5 st)',        diatonic = false, offset = -5 },
    { label = 'Fixed 5th below (-7 st)',        diatonic = false, offset = -7 },
}

-- Lyric text events that Clear and Assign both preserve (special game events).
LYRIC_IGNORE = {
    ['[tambourine_start]'] = true, ['[tambourine_end]'] = true,
    ['[cowbell_start]']    = true, ['[cowbell_end]']    = true,
    ['[clap_start]']       = true, ['[clap_end]']       = true,
}

----------------------------------------------------------------------
-- Defaults & state
----------------------------------------------------------------------
DEFAULTS = {
    rms_threshold     = 0.05,
    min_offset_ms     = 100,
    min_note_ms       = 60,
    window_ms         = 25,
    lpf_cutoff_hz     = 0,
    split_ratio       = 0,
    snap_enabled         = false,
    snap_window_ms       = 50,
    draft_snap_window_ms = 100,

    pitch_mode        = MODE_YIN,
    pitch             = 60,
    ref_search_ms     = 500,
    min_pitch_enabled = false,
    min_pitch         = 48,
    max_pitch_enabled = false,
    max_pitch         = 72,

    yin_threshold         = 0.15,
    yin_min_freq          = 80,
    yin_max_freq          = 1000,
    yin_window_ms         = 30,
    tuner_rms_threshold   = 0.005,

    velocity          = 100,

    slide_min_note_ms = 200,
    slide_min_seg_ms  = 50,
    slide_skip_ms     = 20,
    slide_step_ms     = 20,
    slide_win_ms      = 20,
}

S = {
    audio_idx         = 0,
    midi_idx          = 0,
    ref_idx           = 0,
    lyrics_path       = '',  -- not persisted; auto-detected on open/project switch

    rms_threshold        = DEFAULTS.rms_threshold,
    min_offset_ms        = DEFAULTS.min_offset_ms,
    min_note_ms          = DEFAULTS.min_note_ms,
    window_ms            = DEFAULTS.window_ms,
    lpf_cutoff_hz        = DEFAULTS.lpf_cutoff_hz,
    split_ratio          = DEFAULTS.split_ratio,
    snap_enabled         = DEFAULTS.snap_enabled,
    snap_window_ms       = DEFAULTS.snap_window_ms,
    draft_snap_window_ms = DEFAULTS.draft_snap_window_ms,

    pitch_mode        = DEFAULTS.pitch_mode,
    pitch             = DEFAULTS.pitch,
    ref_search_ms     = DEFAULTS.ref_search_ms,
    min_pitch_enabled = DEFAULTS.min_pitch_enabled,
    min_pitch         = DEFAULTS.min_pitch,
    max_pitch_enabled = DEFAULTS.max_pitch_enabled,
    max_pitch         = DEFAULTS.max_pitch,

    yin_threshold         = DEFAULTS.yin_threshold,
    yin_min_freq          = DEFAULTS.yin_min_freq,
    yin_max_freq          = DEFAULTS.yin_max_freq,
    yin_window_ms         = DEFAULTS.yin_window_ms,
    tuner_rms_threshold   = DEFAULTS.tuner_rms_threshold,

    velocity          = DEFAULTS.velocity,

    slide_min_note_ms = DEFAULTS.slide_min_note_ms,
    slide_min_seg_ms  = DEFAULTS.slide_min_seg_ms,
    slide_skip_ms     = DEFAULTS.slide_skip_ms,
    slide_step_ms     = DEFAULTS.slide_step_ms,
    slide_win_ms      = DEFAULTS.slide_win_ms,

    status            = 'Ready.',
    last_result       = nil,

    -- Harmonies tab - track indices not persisted
    harm_src_idx        = 0,
    harm_dst1_idx       = 0,
    harm_dst2_idx       = 0,
    harm_dst3_idx       = 0,

    -- Persisted
    harm_dst1_enabled   = true,
    harm_dst2_enabled   = false,
    harm_dst3_enabled   = false,
    harm_dst1_mode      = 0,
    harm_dst2_mode      = 0,
    harm_dst3_mode      = 0,
    harm_copy_phrases   = true,
    harm_key_root       = 9,   -- A (common rock key)
    harm_key_quality    = 0,   -- 0 = major, 1 = minor

    -- Persisted - lyric suffix options per destination
    harm_dst1_lyric_unpitched = false,
    harm_dst1_lyric_hidden    = false,
    harm_dst2_lyric_unpitched = false,
    harm_dst2_lyric_hidden    = false,
    harm_dst3_lyric_unpitched = false,
    harm_dst3_lyric_hidden    = false,

    -- Snap to Key - persisted
    snap_key_root        = 9,    -- A (common rock key)
    snap_key_quality     = 0,    -- 0 = major, 1 = minor
    snap_avoid_collision = false,

    -- Phrase similarity - persisted
    phrase_sim_threshold = 80,
    phrase_same_key      = true,

    -- UI visibility (persisted)
    show_wip_tabs        = false,

    -- Cached track lists (session-only; rebuilt by RefreshTrackLists)
    all_track_list   = nil,
    midi_track_list  = nil,
    audio_track_list = nil,

    -- Pitch Tuner (session-only, not persisted)
    tuner_active         = false,
    tuner_tab_active = false,   -- updated each frame inside General BeginTabItem
    action_yctx          = nil,     -- YIN context held by an in-progress action (cleared by RunAction on error)
    tuner_yctx           = nil,     -- YIN context; open while active
    tuner_audio_item     = nil,     -- item the context is currently open on
    tuner_last_t         = 0,       -- r.time_precise() of last detection run
    tuner_last_play_pos  = nil,
    tuner_pos_stable_t   = nil,     -- time when position stopped changing
    tuner_last_detect_t  = 0,       -- time of last successful pitch detection (drives auto-stop)
    tuner_pitch          = nil,     -- last detected MIDI note number
    tuner_pitch_name     = nil,     -- e.g. "A4"
    tuner_pitch_hz       = nil,     -- nominal Hz for the detected note
    tuner_pitch_ts       = nil,     -- project time of last detection
    tuner_history        = {},      -- up to 10 recent note names, [1] = newest
    tuner_prev_pitch     = nil,     -- MIDI note of detection before the current one
    tuner_quiet_since    = nil,     -- r.time_precise() when silence began; nil when pitch is detected
}

function ResetDetection()
    S.rms_threshold  = DEFAULTS.rms_threshold
    S.min_offset_ms  = DEFAULTS.min_offset_ms
    S.min_note_ms    = DEFAULTS.min_note_ms
    S.window_ms      = DEFAULTS.window_ms
    S.lpf_cutoff_hz  = DEFAULTS.lpf_cutoff_hz
    S.split_ratio    = DEFAULTS.split_ratio
    S.snap_enabled   = DEFAULTS.snap_enabled
    S.snap_window_ms = DEFAULTS.snap_window_ms
end

function ResetPitch()
    S.pitch_mode        = DEFAULTS.pitch_mode
    S.pitch             = DEFAULTS.pitch
    S.ref_search_ms     = DEFAULTS.ref_search_ms
    S.min_pitch_enabled = DEFAULTS.min_pitch_enabled
    S.min_pitch         = DEFAULTS.min_pitch
    S.max_pitch_enabled = DEFAULTS.max_pitch_enabled
    S.max_pitch         = DEFAULTS.max_pitch
    S.yin_threshold     = DEFAULTS.yin_threshold
    S.yin_min_freq      = DEFAULTS.yin_min_freq
    S.yin_max_freq      = DEFAULTS.yin_max_freq
    S.yin_window_ms     = DEFAULTS.yin_window_ms
end

function ResetMIDIOutput()
    S.velocity = DEFAULTS.velocity
end

function ResetSlides()
    S.slide_min_note_ms = DEFAULTS.slide_min_note_ms
    S.slide_min_seg_ms  = DEFAULTS.slide_min_seg_ms
    S.slide_skip_ms     = DEFAULTS.slide_skip_ms
    S.slide_step_ms     = DEFAULTS.slide_step_ms
    S.slide_win_ms      = DEFAULTS.slide_win_ms
end

function ResetYIN()
    S.yin_threshold       = DEFAULTS.yin_threshold
    S.yin_min_freq        = DEFAULTS.yin_min_freq
    S.yin_max_freq        = DEFAULTS.yin_max_freq
    S.yin_window_ms       = DEFAULTS.yin_window_ms
    S.tuner_rms_threshold = DEFAULTS.tuner_rms_threshold
end
