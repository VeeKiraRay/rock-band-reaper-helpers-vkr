-- Minimal state table - no actions, nothing to persist
S = {
    hovered_drum_idx = nil,   -- set each frame by notation table hover; consumed by image overlay
    preview_src      = nil,   -- active CF_Preview handle; stopped + deleted before next play
    preview_pcm      = nil,   -- PCM_source* backing the active preview; destroyed after CF_Preview_Delete
    burst_files      = nil,   -- {filename, ...} array firing on row click; nil when idle
    burst_idx        = 0,     -- next index into burst_files (1-based)
    burst_next_t     = 0.0,   -- r.time_precise() timestamp for next burst hit
}

TIPS = {}

-- ---------------------------------------------------------------------------
-- Drums: standard notation → Rock Band Pro lane mapping
-- img_idx:   0-based position of this voice in drum.png (left to right)
-- col_w:     column width class for the image hover overlay: 'wide', 'med', or nil (normal)
-- gap_after: extra gap in native px to add after this column in the overlay; nil means none
-- audio_file: filename (no path) in resources/audio/drums/ relative to the entry point.
--             String = single file. Table = burst of samples played 500ms apart.
-- ---------------------------------------------------------------------------
DRUM_NOTATION = {
    { img_idx =  0, col_w = 'med',  name = 'Splash cymbal',    rb_pro = 'Green (cymbal)',        audio_file = 'Splash.ogg',
      notes = 'Default Green but if together with another green use Yellow + Green. If alternating different Greens assign some to Blue.' },
    { img_idx =  1, col_w = 'wide', name = 'China cymbal',     rb_pro = 'Green (cymbal)',        audio_file = 'China.ogg',
      notes = 'Default Green but if together with another green use Yellow + Green. If alternating different Greens assign some to Blue.' },
    { img_idx =  2, col_w = 'med',  name = 'Crash cymbal 2',   rb_pro = 'Green (cymbal)',        audio_file = 'Crsh2.ogg',
      notes = 'Default Green but if together with another green use Yellow + Green. If alternating different Greens assign some to Blue.' },
    { img_idx =  3, col_w = 'med',  name = 'Crash cymbal',     rb_pro = 'Green (cymbal)',        audio_file = 'Crsh1.ogg',
      notes = 'Default Green but if together with another green use Yellow + Green. If alternating different Greens assign some to Blue.' },
    { img_idx =  4, name = 'Open hi-hat',      rb_pro = 'Yellow (cymbal)',       audio_file = 'HhOpen.ogg',
      notes = 'Yellow is the more technically correct but Blue can also be a fun choice if no Ride in the song.' },
    { img_idx =  5, name = 'Closed hi-hat',    rb_pro = 'Yellow (cymbal)',       audio_file = 'HhClosed.ogg',
      notes = 'Most common hi-hat notation. Yellow cymbal in Pro.' },
    { img_idx =  6, name = 'Ride bell',        rb_pro = 'Blue (cymbal)',         audio_file = 'BellRide.ogg',
      notes = 'Diamond notehead indicates the bell of the ride. Blue cymbal in Pro.' },
    { img_idx =  7, name = 'Ride cymbal',      rb_pro = 'Blue (cymbal)',         audio_file = 'Ride1.ogg',
      notes = 'Blue cymbal in Pro.' },
    { img_idx =  8, name = 'High tom',         rb_pro = 'Yellow (tom)',          audio_file = 'HiTom.ogg',
      notes = 'Yellow tom in Pro. Tom marker required for pro drums.' },
    { img_idx =  9, name = 'Cowbell',          rb_pro = '(Cymbal)',              audio_file = 'CowBell.ogg',
      notes = 'Not always charted but can add fun-factor if charted for a rarely used cymbal.' },
    { img_idx = 10, name = 'Tambourine',       rb_pro = '(Cymbal)',              audio_file = 'Tambourine.ogg',
      notes = 'Not always charted but can add fun-factor if charted for a rarely used cymbal.' },
    { img_idx = 11, name = 'Hi-mid tom',       rb_pro = 'Yellow or Blue (tom)', audio_file = 'HiMidTom.ogg',
      notes = 'Yellow if there are multiple lower toms, Blue if a higher tom is present. Tom marker required for pro drums.' },
    { img_idx = 12, name = 'Low-mid tom',      rb_pro = 'Yellow or Blue (tom)', audio_file = 'LoMidTom.ogg',
      notes = 'Yellow if there are multiple lower toms, Blue if a higher tom is present. Tom marker required for pro drums.' },
    { img_idx = 13, name = 'Ride cymbal 2',    rb_pro = 'Blue (cymbal)',         audio_file = 'Ride2.ogg',
      notes = 'Blue cymbal in Pro.' },
    { img_idx = 14, name = 'Snare',            rb_pro = 'Red',                   audio_file = { 'Snare1.ogg', 'Snare2.ogg', 'Snare3.ogg', 'Snare4.ogg' },
      notes = 'Core Red voice in both 4-lane and Pro.' },
    { img_idx = 15, col_w = 'med',  name = 'Snare side stick', rb_pro = 'Red',                   audio_file = 'RimTap.ogg',
      notes = 'Rim click. Still charted as Red. Common for quiet verses.' },
    { img_idx = 16, col_w = 'med', gap_after = 7, name = 'Electric snare',   rb_pro = 'Red',                   audio_file = {'ESnrare1.ogg', 'ESnrare2.ogg'},
      notes = 'Cross-stem notation for electronic snare. Charted as Red.' },
    { img_idx = 17, name = 'Low tom',          rb_pro = 'Blue / Green (tom)',    audio_file = 'LowTom.ogg',
      notes = 'Blue if there is a lower floor tom, Green if there are two higher toms. Tom marker required for pro drums.' },
    { img_idx = 18, name = 'High floor tom',   rb_pro = 'Blue / Green (tom)',    audio_file = 'HiFlrTom.ogg',
      notes = 'Blue if there is a lower floor tom, Green if there are two higher toms. Tom marker required for pro drums.' },
    { img_idx = 19, name = 'Low floor tom',    rb_pro = 'Green (tom)',           audio_file = 'LowFlrTom.ogg',
      notes = 'Green tom in Pro. Tom marker required for pro drums.' },
    { img_idx = 20, name = 'Bass drum 1',      rb_pro = 'Kick pedal',            audio_file = {'Kick1.ogg', 'Kick3.ogg', 'Kick5.ogg', 'Kick7.ogg', 'PKick1.ogg', 'PKick3.ogg'},
      notes = 'Main pedal for 1X drums.' },
    { img_idx = 21, name = 'Bass drum 2',      rb_pro = 'Kick pedal (double)',   audio_file = {'Kick2.ogg', 'Kick4.ogg', 'Kick6.ogg', 'Kick8.ogg', 'PKick2.ogg'},
      notes = 'Double kick. Remember to mark the song as 2X if there is a secondary kick.' },
    { img_idx = 22, name = 'Hi-hat pedal',     rb_pro = '(Yellow)',              audio_file = 'HHPedal.ogg',
      notes = 'Usually not charted but can be added for rhythm purposes if not much else is going on.' },
}

-- ---------------------------------------------------------------------------
-- Common drum patterns
-- ---------------------------------------------------------------------------
DRUM_PATTERNS = {
    { name = 'Basic rock beat',  desc = 'Kick on beats 1 and 3, snare on 2 and 4, hi-hat on every 8th note.'           },
    { name = '4-on-the-floor',   desc = 'Kick on every quarter note (beats 1, 2, 3, 4). Common in pop and dance.'      },
    { name = 'Half-time feel',   desc = 'Snare falls on beat 3 only instead of 2 and 4. Sounds slower and heavier.'    },
    { name = 'Ghost note',       desc = 'Very quiet snare hit, notated with parentheses: (n). Adds texture and groove.' },
    { name = 'Flam',             desc = 'A soft grace note struck just before the main hit, creating a wider sound.'   },
    { name = 'Fill',             desc = 'A short rhythmic figure (usually 1-2 bars) that bridges song sections.'       },
    { name = 'Paradiddle',       desc = 'Sticking pattern: R L R R / L R L L. Fundamental for building stick control.' },
}
