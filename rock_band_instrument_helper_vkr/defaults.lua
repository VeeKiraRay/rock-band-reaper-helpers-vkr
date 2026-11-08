-- Global state and tooltip text for the Instrument Helper
-- Requires: nothing (loaded first)

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
S = {
    status                = 'Ready.',
    last_result           = nil,
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
    mn_gap_mode           = 0,     -- Only sustains: 0 = Default (Generate's rules), 1 = Custom
    mn_sustain_32nds      = 2,     -- Only sustains, Custom: gap size in 32nd notes (0-32);
                                   -- prefilled with MidiLengthDefaultGap32 when the track
                                   -- or tier changes (2 = Expert's 1/16)
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
    -- Drums difficulty (not persisted - auto-detected by name)
    diff_drums_idx        = -1,
    diff_drums2x_idx      = -1,   -- PART DRUMS_2X (double bass pedal), Generate only
    diff_gen_drums_2x_on_1x = false,  -- Generate: PART DRUMS holds the 2x bass pedal chart (opt-in, persisted)
    -- Difficulty > Generate: instrument dropdown, a GEN_INSTRUMENTS key or 'all' (persisted)
    diff_gen_instrument   = 'gtr',
    -- Difficulty > Validate & copy: instrument dropdown, a GEN_INSTRUMENTS key (persisted).
    -- Follows Generate's pick whenever that is one instrument, and the other way round.
    diff_vc_instrument    = 'gtr',
    -- Difficulty > Generate: rule style - 'vkr' | 'official' | 'custom' (persisted). VKR and
    -- Official run their GEN_STYLES preset; the fields below are Custom's own values
    -- (persisted; GenStyleValues, actions_difficulty_generate.lua).
    diff_gen_style        = 'vkr',
    -- Custom has values of its own (loaded from the project's settings, or Custom was
    -- picked this session): switching to Custom keeps them instead of copying the preset.
    diff_gen_custom_set   = false,
    -- Notes a full bar of 8ths loses on Hard - 'auto', 1 or 2 (Auto decides from the
    -- song's tempo, see GEN5_PARAMS.fast_8ths_bpm)
    diff_gen_busy_drop    = 'auto',
    -- 'auto' | 'thin' | 'rewrite' - see GEN5_PARAMS.fast_runs_default
    diff_gen_fast_runs    = 'rewrite',
    -- Drums Medium: a kick/snare between hi-hat notes - 'beats' (keep those on a beat, as
    -- official charts do) | 'none' (the RBN doc) | 'keep'. See difficulty_generate_drums.lua
    -- (opts.between).
    diff_gen_drums_between = 'beats',
    -- Drums Medium/Easy at fast tempos: which of three hand hits an 8th apart goes -
    -- 'hands' (the least important hand gems; VKR) | 'beats' (the "and"s, as official charts
    -- do). See difficulty_generate_drums.lua (opts.eighth_hands).
    diff_gen_drums_eighths = 'hands',
    -- Every rule without its own option row: 'vkr' | 'official' (GEN_STYLE_ROWS).
    diff_gen_rules        = 'vkr',
    -- Difficulty tab: pending overwrite confirmation (not persisted, transient UI
    -- state). nil = no popup. Otherwise: { message = string, on_confirm = function()
    -- ... end, confirm_label = string? } - set by a Copy*Diff call or by
    -- GenerateDifficulties when the target already has notes; consumed by the
    -- confirm popup in ui_difficulty.lua.
    diff_copy_pending     = nil,
    -- Cached filtered track lists (not persisted - rebuilt by RefreshTrackLists)
    all_track_list        = nil,
    audio_track_list      = nil,
    midi_track_list       = nil,
    -- UI visibility (persisted)
    show_wip_tabs           = false, -- show the Drums and Guitar tabs and Keys > WIP
    -- Keys > Tuner (persisted unless noted; track indices are not, as everywhere)
    ct_keys_idx         = -1,     -- keys audio (KEYS AUDIO by default)
    ct_bass_idx         = -1,     -- bass audio, optional (BASS AUDIO by default)
    ct_key_mode         = 'off',  -- one of CHORD_KEY_MODES: off / vocals / prokeys / manual
    ct_key_tonic        = 0,      -- manual key: tonic pitch class (0 = C)
    ct_key_minor        = false,  -- manual key: minor
    ct_plain            = true,   -- prefer plain chords (7th / sus4 penalties)
    ct_read_long        = false,  -- stopped, nothing charted: read 0.45 s instead of 0.2 s
    ct_passage          = true,   -- passage check: single notes or chords over ~4 s
    -- Keys > Tuner, session only
    ct_active           = false,
    ct_tab_active       = false,  -- set while the Tuner sub-tab is drawn
    ct_last_t           = 0,
    ct_last_pos         = nil,
    ct_last_playing     = nil,
    ct_last_move_t      = nil,    -- when the cursor last moved (or playback ran): idle stop
    ct_job              = nil,    -- a stopped reading in progress
    ct_result           = nil,    -- the last reading, for the readout
    ct_history          = {},     -- chord readings, oldest first
    ct_note_history     = {},     -- single-note readings, oldest first
    ct_audio            = {},     -- open accessors: { keys = {item, ctx}, bass = ... }
    ct_chart            = nil,    -- charted Pro Keys chords (timing for stopped readings)
    ct_key              = nil,    -- the key in use: { tonic, minor, name, mask } or nil
    ct_key_why          = nil,    -- why a chosen key source gave no key
    ct_pass_frames      = {},     -- passage check: per-pitch sums by grid frame
    ct_pass_job         = nil,    -- passage check: a stopped read in progress
    ct_pass             = nil,    -- passage check: the last verdict, for the readout
    -- Overdrive tab (persisted unless noted)
    od_group            = 0,     -- index into OD_GROUP_CHOICES, 0-based: 0 = All
    od_inc_phrases      = true,
    od_inc_fills        = true,
    od_inc_vocals       = true,
    od_beats_per_phrase = 40,    -- the doc's rate: one phrase per 40 counted beats
    od_unison_share     = 50,    -- percent of the median phrase count; the doc says about half
    od_keepout_od       = 8,     -- measures at the end with no overdrive
    od_keepout_unison   = 12,    -- measures at the end with no unison
    od_keepout_start    = 5,     -- measures the band plays before the first phrase (official median 5)
    od_together         = true,  -- unisons prefer the pre-section measure and the band playing together
    od_vocal_overlap    = 2,     -- instrument OD vs vocal OD: 0 avoid, 1 avoid its first measure, 2 overlap anywhere
    od_fill_pacing      = 0,     -- 0 = Auto from tempo, else an OD_FILL_PACINGS index
    od_fill_sections    = true,  -- end a fill on a nearby section start, else a nearby drum crash
    od_fill_skip_early  = true,  -- leave out fills before drum overdrive can first be activated
    od_fill_keepout_end = 2,     -- a fill's crash lands at least this many measures before the drums' last measure
    od_vocal_every      = 5,     -- vocal phrases per vocal overdrive phrase
    -- Session only: { message, can_keep, on_replace, on_keep } while the replace
    -- confirmation is open; the overview strip's data from the last Generate/Validate.
    -- Both describe the current project and are cleared on a project switch.
    od_pending          = nil,
    od_overview         = nil,
}

----------------------------------------------------------------------
-- Tooltip text
----------------------------------------------------------------------
TIPS = {
    save          = "Save current settings to this project.",
    load          = "Load previously saved settings from this project.",

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
    mc_gtr_tab_format  = 'Horizontal: one event per line - 6 space-separated tokens, left = lowest string (E),\n' ..
                         'right = highest string (e). Standard chord notation: "x 3 2 0 1 0" is C major.\n' ..
                         'Use a fret number, or a dash/x for unplayed.\n' ..
                         'Supports multi-digit frets (10, 12, etc.). Blank line = phrase break.\n\n' ..
                         'Vertical: standard guitar tab layout - 6 rows (e/B/G/D/A/E),\n' ..
                         'each row is space-separated tokens, columns = events. All-dash column = phrase break.\n\n' ..
                         'The two run in opposite directions on purpose - that is how each notation is\n' ..
                         'really written. A one-line fret shape starts at the low E; ASCII tab puts the\n' ..
                         'high e on the top row.',
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
                     "Only sustains: picks the tier's gap and shortest-sustain rules.\n" ..
                     "PART REAL_KEYS_X/H/M/E take the tier from the track name instead.",
    mn_note_type   = "Non-sustains: unify every note SHORTER than 1/8 note to the selected\n" ..
                     "Note size. Existing sustains (>= 1/8 note) are left untouched.\n\n" ..
                     "Only sustains: leave note starts and short notes untouched; instead\n" ..
                     "adjust the gap between each sustain (>= 1/8 note) and the next note.",
    mn_note_denom  = "Standard note length every non-sustain note in range is set to (start\n" ..
                     "position unchanged, only the end position moves). Default: 1/32.\n\n" ..
                     "1/8 is not offered: that is the sustain threshold.",
    mn_gap_mode    = "Default: the gap Difficulty > Generate leaves after a sustain, worked out\n" ..
                     "per sustain for this instrument and tier (Keys: a 1/8 after a chord on\n" ..
                     "Expert/Hard; Pro Keys Hard: a 1/16 before a simple change, else a 1/8).\n" ..
                     "Fast songs (over 160 BPM) are told by the song's first tempo. Expert\n" ..
                     "uses Hard's gaps. The rules are shown below.\n\n" ..
                     "Custom: one gap, in 32nd notes, for every sustain.\n\n" ..
                     "Both: a sustain too short for the tier becomes a plain note, as\n" ..
                     "Generate makes it, and is listed in the result.",
    mn_sustain_32nds = "Target gap, in 32nd notes, between a sustain's end and the next note.\n\n" ..
                     "Widens or shortens the sustain as needed to hit this gap exactly.\n" ..
                     "Prefilled with the Default gap (single note to single note) when the\n" ..
                     "track or difficulty changes.",
    mn_adjust      = "Apply the note-length/sustain-gap adjustment to the selected track\n" ..
                     "and difficulty range.\n\n" ..
                     "Only sustains: looks up to a half note (16x32nd notes) ahead for a\n" ..
                     "next note - sustains with nothing that close keep their gap. A note\n" ..
                     "starting INSIDE the sustain always counts as the next note, so an\n" ..
                     "overlap is never left behind.\n\n" ..
                     "Intentional rests are kept: the track's most common gap is measured\n" ..
                     "(whole track, this difficulty), and a sustain is only lengthened when\n" ..
                     "its gap is at most 1.5x that (usual 3 -> up to 4). Longer gaps are left\n" ..
                     "alone and listed in the result to check by hand. A gap tighter than\n" ..
                     "the target is always fixed. Then a sustain too short for the tier\n" ..
                     "becomes a plain note (listed too).\n\n" ..
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
                     "Both patterns must cover exactly the same duration. Neither button\n" ..
                     "clears the other - if the two lengths disagree, Replace All refuses\n" ..
                     "to run and says so, and you re-capture whichever one is wrong.",
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

    -- General tab - Drums 2x kicks
    -- Not currently drawn: MarkDoubleBassKicks writes pitch 95, which Rock
    -- Band 3 discards. Kept for a future version supporting games that do
    -- read it. See ui.lua, General > Actions > Drums 2x kicks.
    drums_2x_mark_double =
        "Find the double-bass lines on PART DRUMS_2X and move every second foot\n" ..
        "from pitch 96 to pitch 95.\n\n" ..
        "NOT for Rock Band 3, which discards pitch 95 - so this button is not drawn\n" ..
        "in the UI. Kept for a future version supporting games that do read it.\n\n" ..
        "What counts as a double-bass line:\n" ..
        "  Kicks up to a 1/8 apart form one line.\n" ..
        "  Two back-to-back 1/16 kicks are already two feet, so any line with a\n" ..
        "  1/16 or tighter gap qualifies.\n" ..
        "  A straight run of 1/8s needs more than 4 in a row - four or fewer is\n" ..
        "  playable with one foot.\n" ..
        "  A kick hanging off the line by a wider gap - a lone 1/8 leaning against\n" ..
        "  a burst of 1/16s, or one across a bar line from the rest - is a separate\n" ..
        "  hit, not part of the line, and is left alone.\n\n" ..
        "Every other kick in the line becomes the second foot, phased so a kick on\n" ..
        "a bar downbeat is never taken - so a line ending on the downbeat starts\n" ..
        "its alternation on the first kick instead of the second.\n\n" ..
        "A line with a gap in it is read as one continuous grid rather than by\n" ..
        "counting the kicks that are actually there, so the feet stay on the same\n" ..
        "subdivisions across the gap and the downbeats either side stay primary.\n" ..
        "The same foot plays on both sides of the rest, which is what happens when\n" ..
        "the silent slot was the other foot's.\n\n" ..
        "Kicks already at pitch 95 count as part of the line, so re-running is\n" ..
        "safe. Any 95 sitting where these rules would not put one is reported and\n" ..
        "left untouched - your own edits are never reverted.\n\n" ..
        "The whole track is processed. A time selection does not change the result.\n\n" ..
        "Check the result rather than trusting it. The rules come from a small number\n" ..
        "of hand-charted songs, so an unusual passage can come out wrong - most often\n" ..
        "where a line has a gap in it, or starts and ends on a downbeat. It is meant\n" ..
        "to do the bulk of the work on the long passages, not to be the last word.\n\n" ..
        "Fully undoable.",
    drums_2x_remove_kicks =
        "Work out which kicks on PART DRUMS_2X are the drummer's second foot, and\n" ..
        "remove those from PART DRUMS.\n\n" ..
        "PART DRUMS_2X is the complete drum chart - every kick, double-bass hits\n" ..
        "included, all at pitch 96. The build swaps that whole track in as the song's\n" ..
        "2x version. PART DRUMS is the same chart with the second foot taken out, so\n" ..
        "it stays playable with one pedal. Author every kick on both tracks, then\n" ..
        "press this.\n\n" ..
        "Only PART DRUMS loses notes. PART DRUMS_2X is never thinned - the one thing\n" ..
        "that can change there is a leftover pitch-95 note being put back to 96.\n" ..
        "Rock Band 3 ignores 95, so a kick left at that pitch would simply not play.\n\n" ..
        "What counts as a double-bass line:\n" ..
        "  Kicks up to a 1/8 apart form one line.\n" ..
        "  Two back-to-back 1/16 kicks are already two feet, so any line with a\n" ..
        "  1/16 or tighter gap qualifies.\n" ..
        "  A straight run of 1/8s needs more than 4 in a row - four or fewer is\n" ..
        "  playable with one foot.\n" ..
        "  A kick hanging off the line by a wider gap - a lone 1/8 leaning against\n" ..
        "  a burst of 1/16s, or one across a bar line from the rest - is a separate\n" ..
        "  hit, not part of the line, and is left alone.\n\n" ..
        "Every other kick in the line is the second foot, phased so a kick on a bar\n" ..
        "downbeat is never taken - so a line ending on the downbeat starts its\n" ..
        "alternation on the first kick instead of the second. A line with a gap in\n" ..
        "it is read as one continuous grid rather than by counting the kicks that\n" ..
        "are there, so the feet stay on the same subdivisions across the gap.\n\n" ..
        "Matching against PART DRUMS is by musical position, so a tempo change\n" ..
        "anywhere in the song does not affect it, and on a fast run it will not take\n" ..
        "a neighbouring gem by mistake.\n\n" ..
        "The whole track is processed. A time selection does not change the result.\n\n" ..
        "Safe to run twice: the second run finds nothing left to remove, says so,\n" ..
        "and adds no undo point.\n\n" ..
        "Check the result rather than trusting it. The rules come from a small number\n" ..
        "of hand-charted songs, so an unusual passage can come out wrong - most often\n" ..
        "where a line has a gap in it, or starts and ends on a downbeat. It is meant\n" ..
        "to do the bulk of the work on the long passages, not to be the last word.\n\n" ..
        "Fully undoable - one step puts both tracks back.",

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
                        "Expert 96-100 | Hard 84-88 | Medium 72-76 | Easy 60-64\n" ..
                        "(all five colors on every difficulty, as official Keys charts use them)",
    diff_5k_autodetect = "Search for a track named PART KEYS and assign it.\n" ..
                         "Resets the current selection before scanning.",
    diff_5k_copy      = "Copy notes from the tier above (Expert\xe2\x86\x92Hard, Hard\xe2\x86\x92Medium,\n" ..
                        "Medium\xe2\x86\x92Easy) onto this difficulty's own pitch range. Colors\n" ..
                        "copy across unchanged - every Keys difficulty uses all five.\n\n" ..
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
                        "Medium/Easy limits follow what official charts actually do: Medium\n" ..
                        "notes may be 1/8 apart (1/4 is advised), and a sustain needs a 1/8\n" ..
                        "note gap before the next note (1/16 on Medium at 100 BPM or slower).\n\n" ..
                        "Read-only - no project changes are made.\n" ..
                        "Respects time selection if active.",
    diff_5k_validate_all = "Validate all four 5-Lane Keys difficulty ranges in one combined report.\n\n" ..
                           "Read-only - no project changes are made.\n" ..
                           "Respects time selection if active.",

    -- Difficulty tab - Guitar/Bass
    diff_gb_track      = "Guitar/Bass difficulty track (PART GUITAR or PART BASS, matching the\n" ..
                         "instrument selected above).\n" ..
                         "All four difficulties live on this single track in separate pitch ranges:\n" ..
                         "Expert 96-100 | Hard 84-88 | Medium 72-76 | Easy 60-64\n" ..
                         "Medium focuses on Green-Blue and Easy on Green-Yellow; the upper\n" ..
                         "colors are allowed but used sparingly.",
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
                         "sustain gaps, and trill/tremolo marker velocity (Hard eligibility).\n\n" ..
                         "Medium/Easy limits follow what official charts actually do: a\n" ..
                         "sustain needs a 1/8 note gap before the next note (1/16 on Medium\n" ..
                         "at 100 BPM or slower). Advisories, not errors: Orange on Medium or\n" ..
                         "Blue/Orange on Easy above 5% of the notes, and force-HOPO markers\n" ..
                         "on Medium/Easy.\n\n" ..
                         "Read-only - no project changes are made.\n" ..
                         "Respects time selection if active.",
    diff_gb_validate_all = "Validate all four Guitar/Bass difficulty ranges in one combined report.\n\n" ..
                           "Read-only - no project changes are made.\n" ..
                           "Respects time selection if active.",

    -- Difficulty tab - Generate
    diff_gen_instrument = "Which instrument to generate difficulties for.\n\n" ..
                          "All instruments uses each instrument's default track (PART GUITAR,\n" ..
                          "PART BASS, PART REAL_KEYS_X/H/M/E, PART KEYS, PART DRUMS,\n" ..
                          "PART DRUMS_2X) and skips any that is missing or muted.\n" ..
                          "Generate never writes to a muted track: a single instrument whose\n" ..
                          "track is muted stops with a message to unmute it first.\n\n" ..
                          "Pro Keys runs before Keys, and Keys\n" ..
                          "follows the Pro Keys it just generated. Drums are reduced on their\n" ..
                          "own: they neither follow nor lead the other instruments.\n\n" ..
                          "Drums covers PART DRUMS_2X (double bass pedal) too: it runs\n" ..
                          "after PART DRUMS, and each 2X difficulty plays the kicks of the\n" ..
                          "PART DRUMS difficulty one step up. The result lists both tracks.",
    diff_gen_track      = "The instrument's track. Shared with Validate & copy -\n" ..
                          "changing it here changes it there too.",
    diff_vc_instrument  = "Which instrument to copy or validate. Follows the instrument\n" ..
                          "picked in Generate (and the other way round), except when\n" ..
                          "Generate is on All instruments.\n\n" ..
                          "Guitar and Bass share the same RBN authoring rules (ranges, chord\n" ..
                          "legality, sustain/HOPO rules) - only the track differs.",
    diff_gen_style      = "Which set of rules Generate follows.\n\n" ..
                          "VKR: the tool author's own rules - mostly what official charts\n" ..
                          "do, with choices of their own where a chart played better\n" ..
                          "another way (for example Hard fast runs rewritten one grid\n" ..
                          "slower instead of thinned).\n" ..
                          "Official: what official charts do, wherever the two differ.\n" ..
                          "Custom: pick each option yourself. Keeps its own values once\n" ..
                          "you have used it (and saved settings bring them back); the\n" ..
                          "first time it starts from the style shown before it.\n\n" ..
                          "With VKR and Official the options below show the values used\n" ..
                          "and cannot be changed. Saved with the project's settings.",
    diff_gen_rules      = "Every rule that has no option row of its own.\n\n" ..
                          "VKR: the tool author's choices where they differ from official\n" ..
                          "charts.\n" ..
                          "Official: most of those choices turned off, so the result is\n" ..
                          "closer to official charts. Not the same as them: a few rules\n" ..
                          "have no official version yet.",
    diff_gen_drums_2x_on_1x = "For a song charted only in its double bass pedal version, on\n" ..
                          "PART DRUMS (no PART DRUMS_2X). PART DRUMS is then generated the\n" ..
                          "way a PART DRUMS_2X would be: its Expert stays, and each lower\n" ..
                          "difficulty plays the kicks of a single-pedal version made in\n" ..
                          "memory (what \"Remove 2x kicks\" would leave), one difficulty up.\n\n" ..
                          "Stops without writing anything when the song also has a\n" ..
                          "PART DRUMS_2X, or when PART DRUMS Expert has no double-bass\n" ..
                          "kicks to remove (a single-pedal chart).",
    diff_gen_track2x    = "The song's PART DRUMS_2X (double bass pedal) track, if it has one.\n" ..
                          "Generated in the same run, after PART DRUMS: each 2X difficulty\n" ..
                          "plays the kicks of the PART DRUMS difficulty one step up (Hard\n" ..
                          "the single-pedal Expert's, Medium PART DRUMS Hard's, Easy its\n" ..
                          "Medium's); the hands are reduced as usual.\n\n" ..
                          "With no PART DRUMS ((none) in the Track row), only the 2X track\n" ..
                          "is written:\n" ..
                          "a single-pedal version is made in memory from the 2X Expert\n" ..
                          "(fast kick runs thinned) and its kicks are used.\n\n" ..
                          "(none): the song has no 2X track.",
    diff_gen_tier       ="Generate this difficulty from the one above it as it is now\n" ..
                          "(Hard from Expert, Medium from Hard, Easy from Medium). Useful\n" ..
                          "after hand-editing a tier, to rebuild only the ones below it.\n\n" ..
                          "Thins notes the way official charts do - downbeats and beats\n" ..
                          "first - then reduces chords and colors and shortens sustains.\n" ..
                          "Which notes are kept depends only on the rhythm, so guitar,\n" ..
                          "bass and keys playing the same part get the same easier\n" ..
                          "rhythm (in busy bars Bass and Keys follow Guitar's Hard).\n" ..
                          "Keys follow the same-difficulty Pro Keys track when it\n" ..
                          "has notes.\n\n" ..
                          "On a sparse part, Hard keeps notes that have more than a\n" ..
                          "quarter note of space around them (Medium drops them when off\n" ..
                          "the beat); a Hard that keeps almost all of Expert is eased by\n" ..
                          "moving each bar down a lane so it tops out at Blue.\n\n" ..
                          "Hard plays fast runs one grid slower instead of thinning them\n" ..
                          "(\"Hard fast runs\"): 16ths become 8th triplets, 8th triplets\n" ..
                          "become 8ths, keeping the order of the colors. A long run stays\n" ..
                          "on the beat grid between its first and last Expert note, with no\n" ..
                          "break in the middle. Those bars are listed in the result to\n" ..
                          "review by hand.\n\n" ..
                          "Medium keeps a note per beat in busy bars, prefers a chord to a\n" ..
                          "single note next to it (but not to a downbeat), and puts a beat\n" ..
                          "Hard's rewrite moved back where Expert plays it. Bass and Keys\n" ..
                          "follow Guitar's Medium in bars of the same rhythm. Medium and\n" ..
                          "Easy keep only sustains of a quarter note or more above 160 BPM\n" ..
                          "(Medium a dotted 8th at or below), as official charts do.\n\n" ..
                          "Guitar/Bass Hard gets force-HOPO markers where Expert forced\n" ..
                          "a hammer-on, and where that rewrite pulled Expert's hammer-ons\n" ..
                          "apart (assumes Magma's default HOPO threshold, 170).\n\n" ..
                          "Sustains leave a gap before the next note: Hard 1/8, Medium a\n" ..
                          "dotted 8th, Easy a quarter (above 160 BPM: Medium a quarter,\n" ..
                          "Easy a half). One that would end up shorter than 1/8 becomes a\n" ..
                          "short 1/32 note.\n\n" ..
                          "Pro Keys keeps the same rhythm. Chords lose notes from the\n" ..
                          "bottom, so the top (melody) note stays. Hard keeps Expert's\n" ..
                          "lane shifts it still needs. Medium and Easy show one range for\n" ..
                          "the whole song: Hard's, when Hard shows one range all song,\n" ..
                          "else the one that fits the most notes. Notes outside it move\n" ..
                          "by an octave; notes inside never move, so the same note\n" ..
                          "always lands on the same key. Sustains\n" ..
                          "leave the RBN gaps (Hard 1/16 or 1/8, Medium and Easy a\n" ..
                          "quarter); one cut under 3/16 becomes a 1/16 note. If Expert is so\n" ..
                          "simple that Hard would be an exact copy, it asks first whether to\n" ..
                          "shorten Hard's sustains a little or keep Hard as Expert.\n\n" ..
                          "Drums are reduced limb by limb, never moving a note (except\n" ..
                          "fills with \"Hard fast runs\" on Rewrite/Auto). Hard: no 16ths at\n" ..
                          "140 BPM or faster, a tom/snare run of 16ths only if it lasts two\n" ..
                          "beats or less, hi-hat/ride on 8ths, fewer kicks (under steady 8th\n" ..
                          "hats kicks on 1, 3 and 4), Expert's disco-flip sections played as a\n" ..
                          "normal beat. Medium: the hi-hat on quarter notes from 130 BPM -\n" ..
                          "or slower too when Medium would otherwise keep over 93% of Hard -\n" ..
                          "kicks on quarter notes above 100 BPM (half a bar apart under busy\n" ..
                          "hands) and one a bar from 170 BPM, at most two gems at once.\n" ..
                          "Easy: a kick + snare\n" ..
                          "beat in verses kept on the hi-hat, a two-hand beat elsewhere\n" ..
                          "(from the EVENTS track's sections), never a gem with a kick. Fill\n" ..
                          "kicks are thinned, rolls under a roll lane keep an even count.\n\n" ..
                          "Keys and Pro Keys: a lick that starts on an \"and\" and moves\n" ..
                          "on its \"and\"s (while its beats repeat a note) keeps the\n" ..
                          "\"and\"s on Medium, so the line keeps moving; Easy goes back to\n" ..
                          "Hard's downbeats there.\n\n" ..
                          "The result is checked with Validate's rules and anything left\n" ..
                          "to fix is listed. Asks before replacing existing notes. One\n" ..
                          "undo reverts it. Respects time selection if active.",
    diff_gen_fast_runs  = "How Hard handles runs of 16ths (or faster). Drums: tom and\n" ..
                          "snare runs (fills) only, never a groove with cymbals.\n\n" ..
                          "Rewrite: played one grid slower - 16ths become 8th triplets, 8th\n" ..
                          "triplets become 8ths - keeping the order of the notes. Above 160\n" ..
                          "BPM any run; at or below it runs of half a bar or more.\n" ..
                          "Auto: rewrite above 160 BPM only, thin slower songs.\n" ..
                          "Thin: never rewrite - the notes are thinned to the Hard grid, as\n" ..
                          "official charts do.\n\n" ..
                          "Rewriting is not what official charts do: it keeps a fast\n" ..
                          "passage moving instead of turning it into plain 8ths. Rewritten\n" ..
                          "bars are listed in the result to review by hand.",
    diff_gen_drums_between = "Drums Medium: a kick or snare between two hi-hat/ride notes.\n\n" ..
                          "Beats: keep it when it is on a beat, drop it on an 8th or 16th -\n" ..
                          "what official Medium charts do (they keep 83-94% of those on a\n" ..
                          "beat, 22% on an 8th).\n" ..
                          "None: drop them all - the RBN doc's rule (\"No kicks or snares in\n" ..
                          "between hihat/ride gems\").\n" ..
                          "Keep: keep them all.",
    diff_gen_drums_eighths = "Drums Medium (from 150 BPM) and Easy (from 140 BPM): no three\n" ..
                          "hand hits in a row an 8th apart - official charts at these\n" ..
                          "tempos almost never ask for them. A pair stays; of three, one\n" ..
                          "loses its hands (a kick under it stays).\n\n" ..
                          "Beats: the hit on the \"and\" goes - what official charts do\n" ..
                          "(beat, \"and\", beat keeps the two beats 89-100% of the time).\n" ..
                          "Hands: the hit with the least important hands goes (crash,\n" ..
                          "snare, toms, then ride and hi-hat; a beat wins a tie) - a hi-hat\n" ..
                          "on the beat can go so two snares stay together. Not what\n" ..
                          "official charts do; keeps more of the groove's movement.",
    diff_gen_busy_drop  = "How many notes a full bar of 8ths loses on Hard.\n" ..
                          "Drums: only when Hard would barely differ from Expert (over 95%\n" ..
                          "of its notes) - a bar of steady 8th hi-hats loses that many\n" ..
                          "hat-only \"and\"s (after a crash on 1 the \"and\" of 1 first).\n\n" ..
                          "Drop 1: the and of 4 (1 & 2 & 3 & 4).\n" ..
                          "Drop 2: also the and of 2 - two groups of three\n" ..
                          "(1 & 2 . 3 & 4 .).\n\n" ..
                          "Auto drops 2 when the song starts above 160 BPM, else 1. The\n" ..
                          "RBN docs: \"If the song is fast (over 160 bpm), the player\n" ..
                          "shouldn't be expected to play continuous 8th notes. Thin the\n" ..
                          "chart out by removing every fourth note per half measure.\"\n\n" ..
                          "A bar that already rests on one 8th drops one fewer (at least\n" ..
                          "one); a bar with two or more 8th rests keeps every note.\n" ..
                          "Sustains, and chords in a bar that mixes chords with single\n" ..
                          "notes, go last.\n\n" ..
                          "Bass and Keys follow Guitar: a bar in the same rhythm as\n" ..
                          "PART GUITAR's Expert drops the notes Guitar's Hard drops.\n\n" ..
                          "Official charts use both about equally often, so pick what keeps\n" ..
                          "the song's feel - keep 1 if its strong beats are the upbeats.",
    diff_gen_chain      = "Generate Hard from Expert, then Medium from that Hard, then\n" ..
                          "Easy from that Medium - all three in one go, as one undo step.\n\n" ..
                          "Asks before replacing existing notes. Respects time selection.",

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
    show_wip_tabs        = "Show work-in-progress tabs (Drums, Guitar, and Keys > WIP).\n\n" ..
                           "They work at a basic level but have known issues and are\n" ..
                           "not ready for general use. Set to No to hide them from the tab bar.",
    -- Keys > Tuner
    ct_keys_track        = "The keys audio stem to read. A track named KEYS AUDIO is\n" ..
                           "picked automatically.",
    ct_bass_track        = "Optional: the bass audio stem. Its note nudges the chord's\n" ..
                           "root (measured: a few more chords right). A track named\n" ..
                           "BASS AUDIO is picked automatically.",
    ct_key_mode          = "The song key nudges the names toward chords that fit it.\n" ..
                           "A correct key improves the result; a wrong one can hurt.\n\n" ..
                           "Off: no key.\n" ..
                           "From charted vocals: the key Metadata > Song key reads\n" ..
                           "from PART VOCALS.\n" ..
                           "From charted Pro Keys: the key read from PART REAL_KEYS_X.\n" ..
                           "Manual: pick it.",
    ct_plain             = "Prefer plain chords: a chord's notes have overtones that look\n" ..
                           "like a 7th or a sus4 (an E's overtone is a B, so C can read as\n" ..
                           "Cmaj7). On by default - measured clearly better on the\n" ..
                           "official songs.\n\n" ..
                           "Turn it off for songs built mostly on 7th chords (funk, soul,\n" ..
                           "jazz). The other reading is shown in brackets either way when\n" ..
                           "the two disagree.",
    ct_read_length       = "How much audio a stopped reading takes when no Pro Keys chord\n" ..
                           "is charted under the cursor.\n\n" ..
                           "Short (0.2 s): best for most songs - chords often change\n" ..
                           "within half a second.\n" ..
                           "Long (0.45 s): for slow, held chords (ballads, pads).\n\n" ..
                           "With a charted chord under the cursor the Tuner reads that\n" ..
                           "chord's own length instead (most accurate).",
    ct_toggle            = "Start / stop reading chords from the keys stem.\n\n" ..
                           "Stopped: park the edit cursor on a chord's start.\n" ..
                           "Playing: shows the chord of the last 0.2 s.\n" ..
                           "It stops on its own when the cursor has not moved for 60 s.\n\n" ..
                           "Expect roughly 6 in 10 chords right first and 8 in 10 in the\n" ..
                           "top three on a new song - much better on some songs, worse\n" ..
                           "on others. Treat it as a suggestion and trust your ears.",
    ct_confidence        = "How far the best chord leads the second, and how often a\n" ..
                           "lead like that was right on the official songs:\n\n" ..
                           "clear  ~95%\nlikely ~80%\nmaybe  ~60%\nunsure ~40% - check the top three.",
    ct_passage           = "Passage check: over about 4 seconds of the keys stem, does the\n" ..
                           "part play single notes (a melody, broken chords) or chords?\n" ..
                           "Pro Keys is often single notes, and naming every key press as a\n" ..
                           "chord would mislead. With playback stopped it reads 4 s from\n" ..
                           "the cursor (not while playing: 4 s cannot keep up), then dims\n" ..
                           "the Single or the Chord line, whichever it does not favour.\n\n" ..
                           "Measured on official songs: about half of the single-note\n" ..
                           "passages are recognised, and chord passages are rarely called\n" ..
                           "single notes. A clean melody does much better.",
    ct_passage_line      = "Single notes or chords over the next 4 s from the cursor\n" ..
                           "(see Passage check).",
    ct_single            = "The reading as one note: its strongest pitch class, right\n" ..
                           "about 6 in 10 times on official songs and more on a clean\n" ..
                           "melody. The octave is a guess - place the note in the Pro Keys\n" ..
                           "range yourself.",
    ct_hint_nochart      = "No charted chord here: reading %s from the cursor. Charting the " ..
                           "chord's start (PART REAL_KEYS_X) lets the Tuner read the whole " ..
                           "chord; place the cursor on the chord's start.",
    -- Overdrive tab
    od_group             = "Which part to generate for.\n\n" ..
                           "All generates every part, including unisons across the band.\n" ..
                           "A single part is generated on its own: it joins unisons the\n" ..
                           "other parts already have and keeps out of their phrases.\n\n" ..
                           "Tracks that must match are always written together:\n" ..
                           "Drums = PART DRUMS + PART DRUMS_2X, Keys = PART KEYS +\n" ..
                           "PART REAL_KEYS_X, Vocals = PART VOCALS + HARM1.",
    od_inc_phrases       = "Generate overdrive phrases (note 116) on the instrument parts.\n\n" ..
                           "Each phrase is one measure, spaced evenly over the bars the part\n" ..
                           "is actually playing. Among nearby bars it prefers the one just\n" ..
                           "before a section change, then the most eventful one - chord\n" ..
                           "changes and varied shapes rather than one repeated chord.\n\n" ..
                           "Never in the first or last measures (the keep-outs below),\n" ..
                           "and on drums never in a fill's measure or on a fill's\n" ..
                           "crash. Whether phrases may sit under vocal overdrive is set\n" ..
                           "below.",
    od_together          = "Place unisons where the band plays together, as official\n" ..
                           "charts do:\n\n" ..
                           "- on the last measure before a new section (a pickup or\n" ..
                           "  build-up into it). The drum fill leading into that section\n" ..
                           "  gives way to the unison.\n" ..
                           "- where guitar and bass hit the same notes and move the same\n" ..
                           "  way - GR RY YB BO on guitar against G R Y B on bass counts,\n" ..
                           "  as does the whole band hitting the same beats.\n\n" ..
                           "Measured on official charts, this puts about 2.5x as many\n" ..
                           "unisons where the charter put one, at the cost of about 1 fill\n" ..
                           "in 10. Only used with All; untick it if a song comes out worse.",
    od_vocal_overlap     = "May instrument overdrive sit under vocal overdrive?\n\n" ..
                           "Overlap anywhere      -  yes, as official charts do. Vocals are\n" ..
                           "                         still never part of a unison.\n" ..
                           "Avoid its first measure -  keep the measure where a vocal phrase\n" ..
                           "                         starts clear; the rest of a long phrase\n" ..
                           "                         may be overlapped.\n" ..
                           "Avoid vocal overdrive  -  keep every measure a vocal phrase\n" ..
                           "                         touches clear.",
    od_beats_per_phrase  = "How much playing time each overdrive phrase covers, in counted\n" ..
                           "beats. The RBN guideline is one phrase per 40 beats: about 10\n" ..
                           "measures in 4/4.\n\n" ..
                           "Beats are counted, not quarter notes: 7/8 counts 3 and 6/8\n" ..
                           "counts 2, as the doc's time-signature table does. Bars where\n" ..
                           "the part rests are not counted.",
    od_unison_share      = "How many unisons to make, as a share of the phrase count.\n" ..
                           "The doc asks for about half.\n\n" ..
                           "A unison is the same phrase on every instrument at once. Keys\n" ..
                           "may be left out of one where it is not playing.\n\n" ..
                           "Only used with All: a single part joins the unisons the other\n" ..
                           "parts already have instead.",
    od_keepout_od        = "No overdrive in this many measures at the end of the song.\n" ..
                           "The doc says roughly 8. Counted back from [end], or from\n" ..
                           "[coda] when the song has a Big Rock Ending.",
    od_keepout_unison    = "No unison in this many measures at the end of the song.\n" ..
                           "The doc says roughly 12.",
    od_keepout_start     = "How many measures the band plays before the first overdrive\n" ..
                           "phrase or unison, counted from the first measure any\n" ..
                           "instrument plays.\n\n" ..
                           "Official charts put their first phrase a median of 5 measures\n" ..
                           "in (most between 2 and 9). With the band starting at measure 3\n" ..
                           "and the default of 5, the first phrase lands at measure 8 or\n" ..
                           "later. Vocal overdrive is not affected.",
    od_inc_fills         = "Generate drum fills (notes 120-124, all five lanes) on PART\n" ..
                           "DRUMS and PART DRUMS_2X. A fill is where the drummer can\n" ..
                           "deploy overdrive.\n\n" ..
                           "Fills are laid out before the instrument phrases, so drum\n" ..
                           "phrases and unisons keep clear of them. None in a drum solo,\n" ..
                           "over a drum roll, before a rest, or in a Big Rock Ending - its\n" ..
                           "lanes after [coda] are never touched.",
    od_fill_pacing       = "How often fills come and how long they are.\n\n" ..
                           "Auto: half a measure every 2 for very slow songs (75 BPM or\n" ..
                           "less), one measure every 4 otherwise. The RBN drum doc suggests\n" ..
                           "2 measures every 8 for very fast songs, but official charts keep\n" ..
                           "one measure every 4 there too - pick it by hand if you want it.\n\n" ..
                           "The spacing is a minimum: fills never end closer together,\n" ..
                           "and never start less than 2.5 s after the previous fill ends\n" ..
                           "(Magma refuses to build the song otherwise).",
    od_fill_sections     = "Line fills up with the song instead of keeping strictly to the\n" ..
                           "grid - e.g. a verse with two extra measures gets its fill\n" ..
                           "into the chorus.\n\n" ..
                           "A fill ends on a [prc_*] section change (EVENTS track) within\n" ..
                           "reach of the grid slot. Where there is none, it ends on a drum\n" ..
                           "crash (a blue or green cymbal on a downbeat) instead.\n\n" ..
                           "Practice subsections are not a change: chorus_1a -> chorus_1b,\n" ..
                           "intro_a -> intro_b, or chorus_1 -> chorus_2 back to back (the\n" ..
                           "number or letter at the end is ignored). A section change that comes too soon\n" ..
                           "after the previous fill takes its place - that fill is removed.\n\n" ..
                           "If a section start has no crash but the next or previous\n" ..
                           "measure does, the result points it out: the section event may\n" ..
                           "be a measure off, and moving it moves the fill with it.",
    od_fill_keepout_end  = "No fill in the last measures of the drum part: a fill's crash\n" ..
                           "must land at least this many measures before the drums' last\n" ..
                           "measure. A fill leading straight into the final hit has no\n" ..
                           "overdrive left to be useful for.\n\n" ..
                           "Official charts put their last fill a median of 4 measures\n" ..
                           "before the drums end, and almost never on the final measure.",
    od_fill_skip_early   = "Leave out fills that come before the drummer can have enough\n" ..
                           "overdrive to activate - two drum phrases, or one unison. The\n" ..
                           "drummer can never use them.\n\n" ..
                           "Untick to keep the full grid from the start of the song, as\n" ..
                           "many official charts do.",
    od_inc_vocals        = "Generate vocal overdrive (note 116) on PART VOCALS and HARM1.\n\n" ..
                           "Each one copies a phrase marker (105) exactly. Only phrases\n" ..
                           "with an identical phrase marker on HARM1 are used: Rock Band 3\n" ..
                           "has a visual bug in harmonies if the parts differ. If the cadence\n" ..
                           "lands on a phrase that differs, it moves one phrase earlier or\n" ..
                           "later; if neither works, the result says where.\n\n" ..
                           "Generated first; whether instrument phrases may sit under it\n" ..
                           "is the \"Over vocal OD\" setting above.",
    od_vocal_every       = "Vocal phrases per overdrive phrase. The doc recommends one\n" ..
                           "overdrive for every 5 phrases.",
    od_generate          = "Generate for the whole song. A time selection is ignored.\n\n" ..
                           "If a target already has overdrive or fill notes you are asked\n" ..
                           "first. Everything is one undo step.",
    od_validate          = "Check the overdrive already in the song against the RBN rules:\n" ..
                           "phrase counts and spacing, unisons, fill collisions, matching\n" ..
                           "tracks (Keys/Pro Keys, Drums/Drums 2x, Vocals/HARM1) and the\n" ..
                           "end-of-song keep-outs. Read-only.",
    od_replace           = "Delete the existing notes on the listed tracks and generate\n" ..
                           "new ones. One undo step puts everything back.",
    od_keep              = "Leave the listed tracks as they are and generate only the\n" ..
                           "rest. Kept overdrive is worked around: new phrases join its\n" ..
                           "unisons and stay out of its bars.",
}
