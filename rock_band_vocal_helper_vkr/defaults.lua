-- Constants, defaults, live state, tips, and reset functions

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

    pitch_mode        = MODE_YIN,
    pitch             = 60,
    ref_search_ms     = 500,
    min_pitch_enabled = false,
    min_pitch         = 48,
    max_pitch_enabled = false,
    max_pitch         = 72,

    yin_threshold     = 0.15,
    yin_min_freq      = 80,
    yin_max_freq      = 1000,
    yin_window_ms     = 30,

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

    rms_threshold     = DEFAULTS.rms_threshold,
    min_offset_ms     = DEFAULTS.min_offset_ms,
    min_note_ms       = DEFAULTS.min_note_ms,
    window_ms         = DEFAULTS.window_ms,
    lpf_cutoff_hz     = DEFAULTS.lpf_cutoff_hz,
    split_ratio       = DEFAULTS.split_ratio,

    pitch_mode        = DEFAULTS.pitch_mode,
    pitch             = DEFAULTS.pitch,
    ref_search_ms     = DEFAULTS.ref_search_ms,
    min_pitch_enabled = DEFAULTS.min_pitch_enabled,
    min_pitch         = DEFAULTS.min_pitch,
    max_pitch_enabled = DEFAULTS.max_pitch_enabled,
    max_pitch         = DEFAULTS.max_pitch,

    yin_threshold     = DEFAULTS.yin_threshold,
    yin_min_freq      = DEFAULTS.yin_min_freq,
    yin_max_freq      = DEFAULTS.yin_max_freq,
    yin_window_ms     = DEFAULTS.yin_window_ms,

    velocity          = DEFAULTS.velocity,

    slide_min_note_ms = DEFAULTS.slide_min_note_ms,
    slide_min_seg_ms  = DEFAULTS.slide_min_seg_ms,
    slide_skip_ms     = DEFAULTS.slide_skip_ms,
    slide_step_ms     = DEFAULTS.slide_step_ms,
    slide_win_ms      = DEFAULTS.slide_win_ms,

    status            = 'Ready.',
    last_result       = nil,

    -- Harmonies tab — track indices not persisted
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

    -- Persisted — lyric suffix options per destination
    harm_dst1_lyric_unpitched = false,
    harm_dst1_lyric_hidden    = false,
    harm_dst2_lyric_unpitched = false,
    harm_dst2_lyric_hidden    = false,
    harm_dst3_lyric_unpitched = false,
    harm_dst3_lyric_hidden    = false,

    -- Snap to Key — persisted
    snap_key_root        = 9,    -- A (common rock key)
    snap_key_quality     = 0,    -- 0 = major, 1 = minor
    snap_avoid_collision = false,

    -- Transient — not persisted
    harm_confirm_full   = false,

    -- Cached track lists (session-only; rebuilt by RefreshTrackLists)
    all_track_list   = nil,
    midi_track_list  = nil,
    audio_track_list = nil,
}

function ResetDetection()
    S.rms_threshold = DEFAULTS.rms_threshold
    S.min_offset_ms = DEFAULTS.min_offset_ms
    S.min_note_ms   = DEFAULTS.min_note_ms
    S.window_ms     = DEFAULTS.window_ms
    S.lpf_cutoff_hz = DEFAULTS.lpf_cutoff_hz
    S.split_ratio   = DEFAULTS.split_ratio
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
    S.yin_threshold = DEFAULTS.yin_threshold
    S.yin_min_freq  = DEFAULTS.yin_min_freq
    S.yin_max_freq  = DEFAULTS.yin_max_freq
    S.yin_window_ms = DEFAULTS.yin_window_ms
end

----------------------------------------------------------------------
-- Help text (all tooltip strings)
----------------------------------------------------------------------
TIPS = {
    rms_threshold =
        "Audio level (0..1) above which a note starts.\n\n" ..
        "LOWER -> more sensitive, picks up quiet phrases. Too low triggers " ..
        "on breath, room noise, and bleed -> way too many notes.\n\n" ..
        "HIGHER -> ignores quiet material. Too high misses real phrases.\n\n" ..
        "Start around 0.05 for clean stems; try 0.01-0.03 for quieter sources.\n\n" ..
        "Note: enabling Low-pass cutoff lowers the overall RMS values, so you " ..
        "may need to lower this threshold to compensate.",

    lpf_cutoff =
        "Low-pass filter applied to the audio before energy detection.\n\n" ..
        "Cuts high frequencies so sibilants ('s', 'sh', 'f', 'th') become " ..
        "nearly invisible to the detector — note starts snap to the vowel " ..
        "instead of the leading consonant.\n\n" ..
        "LOWER cutoff (~800 Hz) -> stronger sibilant rejection but may also " ..
        "smooth other transients and slightly delay note starts.\n\n" ..
        "HIGHER cutoff (~4000 Hz) -> mild rejection, less impact on timing.\n\n" ..
        "0 = Off (no filtering). 1500-2500 Hz is a good range for vocals.\n\n" ..
        "Filtering reduces the audio's overall RMS, so re-tune the threshold " ..
        "after enabling.",

    split_ratio =
        "Peak-relative threshold for splitting a single detection into " ..
        "multiple notes.\n\n" ..
        "After a phrase is detected, its loudest point is found. If the " ..
        "RMS contour inside the phrase dips below this percentage of that " ..
        "peak, the phrase is split there. Useful for fast syllables sung " ..
        "together that don't drop below the absolute threshold.\n\n" ..
        "0%% = Off (use absolute threshold only).\n" ..
        "~50%% = moderate splitting.\n" ..
        "HIGHER -> more aggressive splitting; risk of over-splitting steady " ..
        "vowels into many small notes.",

    min_offset_ms =
        "Forces a minimum gap before the next detected note.\n\n" ..
        "If a note's natural end would land closer than this to the next " ..
        "note, it is cut short to enforce the gap.\n\n" ..
        "HIGHER -> cleaner separation but shortens many notes; very short " ..
        "notes can disappear (see 'Dropped' count in the result).\n\n" ..
        "LOWER -> notes can run right up to the next one (no enforced gap).",

    min_note_ms =
        "Notes shorter than this are discarded after detection.\n\n" ..
        "Filters out clicks, lip noise, and brief transients that aren't " ..
        "real syllables.\n\n" ..
        "TOO LOW -> junk gets through.\n" ..
        "TOO HIGH -> real short syllables get dropped.",

    window_ms =
        "Analysis resolution: how often RMS is measured.\n\n" ..
        "SMALLER -> more precise note start/end times, but slower analysis.\n\n" ..
        "LARGER -> smoother, faster, less precise edges.\n\n" ..
        "20-30ms is a sweet spot for vocals.\n\n" ..
        "Note: this is NOT changed by Auto-tune.",

    pitch_mode_single =
        "Every generated note gets the same pitch (the Default pitch slider " ..
        "below). Pick a pitch that doesn't already have notes in the " ..
        "destination MIDI item, so reference notes at other pitches are " ..
        "preserved when you regenerate.",

    pitch_mode_reference =
        "For each generated note, look at a separate MIDI track and copy " ..
        "the pitch of the nearest reference note (by start time) within " ..
        "the configured Search tolerance. If nothing is in range, use the " ..
        "Default pitch.\n\n" ..
        "It's up to you to align the reference MIDI item to the song. " ..
        "Generate it externally with Basic Pitch / Melodyne / etc., import, " ..
        "and shift/stretch as needed.",

    pitch_mode_yin =
        "Built-in monophonic pitch detection using the YIN algorithm.\n\n" ..
        "Analyses the audio from the source track directly to estimate the " ..
        "fundamental frequency of each note — no external MIDI reference needed.\n\n" ..
        "Adjust the YIN threshold and frequency range to suit the source. " ..
        "Notes where pitch cannot be reliably detected fall back to the Default pitch.\n\n" ..
        "Works best on clean, dry vocal stems.",

    yin_threshold =
        "Confidence threshold for YIN pitch detection (0.01 - 0.5).\n\n" ..
        "YIN measures aperiodicity: 0 = perfectly periodic, 1 = no periodicity.\n\n" ..
        "LOWER -> stricter; only confident detections accepted. More notes " ..
        "fall back to Default pitch in noisy or consonant-heavy regions.\n" ..
        "HIGHER -> more permissive; detects more notes but may pick wrong " ..
        "pitches on breaths or fricatives.\n\n" ..
        "0.10 - 0.20 works well for clean vocal stems.",

    yin_min_freq =
        "Lowest pitch frequency to detect (Hz).\n\n" ..
        "Set near the lowest note expected in the vocal part.\n" ..
        "Typical male bass: ~80 Hz (E2). Typical tenor: ~130 Hz (C3).\n\n" ..
        "Must be lower than Max frequency. Wider range = slightly slower analysis.",

    yin_max_freq =
        "Highest pitch frequency to detect (Hz).\n\n" ..
        "Set near the highest note expected in the vocal part.\n" ..
        "Typical soprano: ~1000 Hz (B5). Most pop vocals stay under 800 Hz.\n\n" ..
        "Must be higher than Min frequency.",

    yin_window_ms =
        "Length of the audio window analysed per note for pitch detection (ms).\n\n" ..
        "YIN reads this many milliseconds from around 30%% into each note " ..
        "to find the steady-state vowel region.\n\n" ..
        "LONGER -> more stable estimate; requires a note at least this long.\n" ..
        "SHORTER -> works on short notes but may be noisier.\n\n" ..
        "30 ms is a good default for most vocals.",

    pitch =
        "Pitch assigned to all notes by Generate and Dry run.\n\n" ..
        "Also used as the fallback when Reference MIDI or Built-in detection " ..
        "cannot find a pitch for a note.\n\n" ..
        "Set this on the Note Placement tab.",

    ref_track =
        "MIDI track containing reference notes whose pitches will be copied " ..
        "into the generated notes. The track may contain one or more MIDI " ..
        "items; all notes inside the analysis range are considered.\n\n" ..
        "Only used when Pitch source is set to 'Reference MIDI'.",

    ref_search =
        "How far (in either direction from a note's start) to search for the " ..
        "nearest reference note. If nothing is found inside this window, the " ..
        "note gets the Default pitch instead.\n\n" ..
        "HIGHER -> more permissive; reference timing can be sloppy.\n" ..
        "LOWER -> stricter; missing reference notes default more often.\n\n" ..
        "500 ms is a reasonable starting point.",

    min_pitch_enabled =
        "Constrain notes to be at or above this pitch.\n\n" ..
        "Useful for fixing octave-error artifacts from stem separation: " ..
        "weird low octaves get shifted up by 12 semitones until they're " ..
        "in range.\n\n" ..
        "Disable if you don't want any minimum.",

    max_pitch_enabled =
        "Constrain notes to be at or below this pitch.\n\n" ..
        "Useful for fixing octave-error artifacts: weird high octaves " ..
        "get shifted down by 12 semitones until they're in range.\n\n" ..
        "Disable if you don't want any maximum.",

    min_pitch =
        "Lowest allowed pitch.\n\n" ..
        "Notes below this are octave-shifted up until they fit. If the " ..
        "range is narrower than an octave, they clamp to this value.",

    max_pitch =
        "Highest allowed pitch.\n\n" ..
        "Notes above this are octave-shifted down until they fit. If the " ..
        "range is narrower than an octave, they clamp to this value.",

    velocity =
        "MIDI velocity (1..127) for every generated note. Affects how loud " ..
        "notes play in your sampler / synth. Has no effect on detection.",

    reset_detection = "Reset all Note Placement sliders to factory defaults.",
    reset_pitch     = "Reset all Pitch settings to factory defaults.",
    reset_midi      = "Reset MIDI output sliders to factory defaults.",

    save_settings =
        "Save the current Detection, Pitch, and Velocity values into the " ..
        "project file. They'll be auto-loaded next time the script is " ..
        "opened in this project.\n\n" ..
        "Track selections (audio / MIDI dest / reference MIDI) are NOT saved.",

    load_settings =
        "Reload the most recently saved values from the project file.",

    preview =
        "Run detection only and show stats, without writing any notes.",

    generate =
        "Run detection and append the resulting notes to the existing MIDI " ..
        "item on the destination track. First clears existing notes at every " ..
        "pitch the new run will produce (plus the Default pitch), so re-running " ..
        "over the same range does not stack duplicates.",

    generate_replace =
        "Run detection and replace all existing notes in the analysis range " ..
        "(vocal pitch range only — phrase markers at other pitches are preserved). " ..
        "Produces a clean result with no leftover notes from previous runs.",

    autotune =
        "Find detection settings that best match reference notes you've " ..
        "manually placed.\n\n" ..
        "Prerequisites:\n" ..
        " - Make a time selection covering a section of the song.\n" ..
        " - Place reference notes at the Default pitch in that range.\n\n" ..
        "Tunes RMS threshold, low-pass, split ratio, min offset, and min " ..
        "note. Does NOT change Pitch settings or RMS window.\n\n" ..
        "Use 'Save' first if you want to be able to return to your " ..
        "current values via 'Load'.",

    apply_pitch =
        "Reassign pitches of existing notes on the destination MIDI item " ..
        "without changing their position or length.\n\n" ..
        "Use this when you've already done timing work (manual placement, " ..
        "splitting, length tweaks) and just want to apply pitch information.\n\n" ..
        "Scope:\n" ..
        " - With time selection: processes notes within the selection.\n" ..
        " - Without time selection: processes all notes on the destination " ..
        "MIDI item.\n\n" ..
        "Each existing note gets a new pitch via the configured Pitch source. " ..
        "Pitch range constraints are applied. Velocity, position, and length " ..
        "are preserved.",

    apply_pitch_disabled =
        "Apply pitch changes is only available when Pitch source is set to " ..
        "'Reference MIDI' or 'Built-in detection'. In Single " ..
        "pitch mode, this would overwrite every note with the same pitch.",

    autotune_yin =
        "Find YIN settings that best match notes whose pitches you have\n" ..
        "already corrected manually.\n\n" ..
        "Prerequisites:\n" ..
        " - Make a time selection covering the corrected notes.\n" ..
        " - Ensure notes on the destination MIDI item have the correct pitches\n" ..
        "   in that range (e.g. from manual editing or Apply pitch changes).\n\n" ..
        "Sweeps YIN threshold, frequency range, and window length. Scoring is\n" ..
        "octave-insensitive — pitch-class accuracy is the goal; use pitch range\n" ..
        "constraints to fix any octave errors afterward.\n\n" ..
        "Only available when Pitch source is Built-in detection.\n\n" ..
        "Use 'Save' first to preserve your current values.",

    scan_slides =
        "Scan existing notes on the destination MIDI item and report any\n" ..
        "where pitch moves significantly during the note.\n\n" ..
        "Uses the audio source track to sample pitch at multiple points\n" ..
        "inside each note (via YIN), then classifies the trajectory:\n" ..
        "  Slide up    — pitch rises through the note\n" ..
        "  Slide down  — pitch falls through the note\n" ..
        "  Scoop       — dips then rises (e.g. start mid, drop, go high)\n" ..
        "  Bend        — rises then falls\n" ..
        "  Complex slide — three or more direction changes\n\n" ..
        "Stable notes are not reported. Notes below Min note length are skipped.\n" ..
        "Requires at least two pitch segments each meeting Min segment duration\n" ..
        "inside the note to count as a slide.\n" ..
        "Octave detection errors (C3 vs C5) are ignored — only pitch-class\n" ..
        "changes trigger a slide report.\n\n" ..
        "Uses the YIN threshold and frequency settings in the section above.\n\n" ..
        "Scope:\n" ..
        " - With time selection: scans notes within the selection.\n" ..
        " - Without time selection: scans all notes on the MIDI item.\n\n" ..
        "Read-only — does not modify the project.",

    reset_slides =
        "Reset all Slide Scan sliders to factory defaults.",
    reset_yin =
        "Reset YIN detection settings to factory defaults.",
    slide_min_note_ms =
        "Notes shorter than this duration are skipped entirely.\n" ..
        "Increase to ignore short notes; decrease to scan more aggressively.\n\n",
    slide_min_seg_ms =
        "A detected pitch run shorter than this is discarded.\n" ..
        "Increase to suppress flickery false positives;\n" ..
        "decrease to catch very short slides.\n\n",
    slide_skip_ms =
        "Skip the start and end of each note before sampling.\n" ..
        "Hides consonant artifacts at note boundaries.\n" ..
        "Set to 0 for clean audio with no edge artifacts.\n\n",
    slide_step_ms =
        "How often pitch is sampled along the note.\n" ..
        "Smaller = more resolution and better coverage, but slower scan.\n\n",
    slide_win_ms =
        "YIN analysis window per sample point.\n" ..
        "Longer = more stable detection;\n" ..
        "shorter = catches faster pitch changes.\n\n",

    lyrics_auto_detect =
        "Look for 'lyrics.txt' in the current project folder and select it " ..
        "automatically. Nothing happens if the file is not found.",

    lyrics_browse =
        "Open a file browser to select a lyrics file.\n\n" ..
        "Format: plain text, words separated by any whitespace. " ..
        "Content inside [square brackets] is stripped before splitting, " ..
        "so section headers like '[verse]' are ignored.",

    lyrics_clear =
        "Remove all lyric text events from the entire destination MIDI item.\n\n" ..
        "Special game events ([tambourine_start], [cowbell_start], etc.) are preserved.",

    lyrics_assign =
        "Assign lyrics from the file to notes on the destination MIDI item.\n\n" ..
        "Words are assigned in order to notes in the RB3 vocal pitch range (C1–C5), " ..
        "sorted by start time.\n\n" ..
        "Scope:\n" ..
        " - With time selection: only notes within the selection receive lyrics.\n" ..
        " - Without time selection: all notes on the MIDI item.\n\n" ..
        "Existing lyric events are cleared first (special game events preserved).\n\n" ..
        "After assigning, the result panel shows count-mismatch warnings and a " ..
        "phrase capitalization check (first word after each phrase marker should " ..
        "start with an uppercase letter).",

    validate_phrases =
        "Check all phrases (pitch-105 marker regions) for common authoring issues.\n\n" ..
        "Checks per phrase:\n" ..
        "  1. First vocal note has a capitalized lyric\n" ..
        "  2. Phrase marker start is on a 64th-note (or coarser) grid boundary\n" ..
        "  3. Phrase marker end is on a 64th-note (or coarser) grid boundary\n" ..
        "  4. Gap to the next phrase is at least 4 x 64th note\n" ..
        "  5. First vocal note starts at least 2 x 64th notes after phrase start\n" ..
        "  6. Last vocal note ends at least 1 x 64th note before phrase end\n\n" ..
        "Violations are grouped by phrase position.\n\n" ..
        "Operates on the whole take regardless of time selection.\n" ..
        "Read-only — does not modify the project.",

    harm_src =
        "MIDI source track to copy vocal notes from.\n\n" ..
        "The first MIDI item on this track is used. Typically 'PART VOCALS'.",

    harm_dst1 = "First destination track for the harmony copy.",
    harm_dst2 = "Second destination track for the harmony copy.",
    harm_dst3 = "Third destination track for the harmony copy.",

    harm_dst_enabled =
        "Enable or disable this destination row.\n\n" ..
        "At least one destination must be enabled to apply harmonies.",

    harm_dst_mode =
        "Pitch interval applied when copying notes to this destination.\n\n" ..
        "Diatonic modes use the key set in the Key section and apply the\n" ..
        "correct interval for each individual note (e.g. +3 or +4 st depending\n" ..
        "on the scale degree). Fixed modes add the same semitone offset to every note.\n\n" ..
        "The 4th and 5th are included but will not fit most songs.",

    harm_key =
        "Song key used for 'Diatonic 3rd' modes.\n\n" ..
        "Only relevant when at least one destination is set to a diatonic mode.\n" ..
        "Look up the key on Tunebat (tunebat.com) or check a chord chart,\n" ..
        "then verify by ear before applying.",

    harm_key_quality =
        "Major or natural minor quality for the key.",

    harm_copy_phrases =
        "Also copy phrase marker and overdrive notes (outside the C1-C5 vocal range)\n" ..
        "from the source to each enabled destination.\n\n" ..
        "Existing out-of-range notes in the destination are cleared before copying.",

    harm_confirm_full =
        "No time selection is active. Check this box to confirm processing the entire\n" ..
        "source MIDI item. Make a time selection to limit scope.",

    track_refresh =
        "Re-scan all tracks and rebuild the filtered track dropdowns.\n\n" ..
        "Audio source shows only tracks with audio items.\n" ..
        "MIDI destination, Reference MIDI, and Harmony source show only\n" ..
        "tracks with MIDI items.\n\n" ..
        "Click after adding audio or MIDI items to a track that wasn't\n" ..
        "previously visible in a dropdown. Refresh also runs automatically\n" ..
        "on startup and project switch.",

    harm_lyric_unpitched =
        "Add '#' to the end of each copied lyric on this destination.\n\n" ..
        "In Rock Band, '#' marks the syllable as unpitched — the game accepts\n" ..
        "any pitch for that note. Use this for screamed or growled harmonies\n" ..
        "where exact pitch is not expected from the singer.\n\n" ..
        "If the source lyric already ends with '#', it is not duplicated.\n" ..
        "When both options are checked, '#' is added before '$'.",

    harm_lyric_hidden =
        "Add '$' to the end of each copied lyric on this destination.\n\n" ..
        "In Rock Band, '$' makes the lyric invisible on screen. The game\n" ..
        "displays two distinct lyric lines at a time. If one harmony track\n" ..
        "sings the same words as the lead and another sings different words,\n" ..
        "hide the duplicate track's lyrics so the second display slot is free\n" ..
        "for the track with distinct lyrics.\n\n" ..
        "If the source lyric already ends with '$', it is not duplicated.\n" ..
        "When both options are checked, '#' is added before '$'.",

    harm_apply =
        "Copy vocal notes from the source track to all enabled destinations,\n" ..
        "applying the chosen pitch interval to each.\n\n" ..
        "Destination notes in the vocal range (C1-C5) are cleared before inserting.\n" ..
        "If 'Copy phrase markers' is on, out-of-range notes are also replaced.\n\n" ..
        "Scope: active time selection, or full source item if confirmed.",

    snap_key_root =
        "Root note of the key to snap notes to.",

    snap_key_quality =
        "Major or minor scale for the snap operation.",

    snap_avoid_collision =
        "After snapping, if a note lands on the same pitch as its neighbor\n" ..
        "within the same phrase, try the next closest scale degree instead.\n" ..
        "Notes across phrase boundaries are not compared.",

    snap_apply =
        "Snap vocal notes to the nearest pitch in the selected key scale.\n\n" ..
        "Each note shifts by the fewest semitones to land on a scale degree.\n" ..
        "Phrase markers (pitch 105) are preserved unchanged.\n" ..
        "Lyrics are also preserved.\n\n" ..
        "Scope:\n" ..
        " - With time selection: only notes within the selection are snapped.\n" ..
        " - Without time selection: all notes on the MIDI item (requires confirmation).",
}
