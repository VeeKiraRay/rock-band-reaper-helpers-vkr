-- Minimal state table - no actions, nothing to persist
S = {
    hovered_drum_idx    = nil,   -- set each frame by notation table hover; consumed by image overlay
    preview_src         = nil,   -- active CF_Preview handle; stopped + deleted before next play
    preview_pcm         = nil,   -- PCM_source* backing the active preview; destroyed after CF_Preview_Delete
    burst_files         = nil,   -- {filename, ...} array firing on row click; nil when idle
    burst_idx           = 0,     -- next index into burst_files (1-based)
    burst_next_t        = 0.0,   -- r.time_precise() timestamp for next burst hit
    guitar_search_input  = '',   -- live text in the Guitar tab's shape search box
    guitar_chord_type_idx = 1,   -- selected index into GUITAR_CHORD_TYPES; 1 = Power chord (default)
}

TIPS = {}

TIPS.guitar_play =
    'Plays a short synthesized pluck of this chord (Karplus-Strong string synthesis) ' ..
    'via the same SWS extension the Drums tab uses for its samples -- not a real ' ..
    'guitar recording, just a preview tone. Requires the SWS extension; no MIDI ' ..
    'setup or output device configuration needed.'

TIPS.guitar_search =
    'Paste a fret shape and see its interval classification and suggested RB mapping.\n\n' ..
    'Muted strings at the START or END of the list are optional and can be left out ' ..
    'entirely -- "7 7 5", "x x x 7 7 5", and "- 7 7 5 -" all mean the same shape. ' ..
    'A short list always anchors to the LOWEST strings.\n\n' ..
    'Muted strings BETWEEN played notes are NOT optional -- they mean "skip this ' ..
    'string" and change the shape (e.g. "7 x 5" is an octave; "7 5" is not).\n\n' ..
    'Full form: exactly 6 numbers or "x" (muted), high-to-low, e.g. "x 7 9 9 7 x" -- ' ..
    'the only way to reach strings above the lowest few (e.g. shapes using the B ' ..
    'string). Same convention as the Guitar tab guide\'s tab input in the General Helper.\n\n' ..
    'The shape is also checked against Drop D tuning. If Drop D gives a different ' ..
    'result than Standard, both are shown -- e.g. try "0 0 0" or "2 2 2".'

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

-- ---------------------------------------------------------------------------
-- Guitar: real-guitar chord shapes -> Rock Band 5-lane mapping
-- shape: display string, high-to-low (e B G D A E), 'x' = muted/unplayed --
-- same convention as GUITAR_TAB_OPEN in lib/reaper_guitar_theory.lua.
-- name: the concrete chord name for THIS example (root + quality, e.g.
--   'A5', 'Cm7', 'G/D'), computed the same way GuitarClassifyChordType
--   derives a root (rotate candidate root pitch classes, first template
--   match wins) -- verified with a standalone script before authoring.
--   '-' marks pure 2-note intervals (Minor/Major third, Perfect fourth,
--   Sixth dyad, Octave) that aren't conventionally written as a chord
--   symbol; inventing one would be more confusing than a dash.
--
-- Converted from _future_ideas/GUITAR_THEORY.md, which was written
-- low-to-high (E A D G B e). Two kinds of conversion happened here, NOT a
-- uniform token reversal:
--   - Power chord / octave / fully-specified triad-and-up rows: the doc's
--     numbers are internally consistent (they really do produce their
--     labeled interval), so these are a straight positional relabel into
--     high-to-low order.
--   - The 2-string third/fourth/sixth "dyad" rows and the Add9/Add11/Slash
--     rows: independent verification found the doc's literal fret numbers
--     do NOT reproduce their own labeled interval/type under any consistent
--     string-pair reading (e.g. "7 8 x" labeled Major third computes to a
--     tritone) -- the doc's numbers read as written-by-feel, not
--     calculated. These rows were regenerated from clean interval/pitch-
--     class math instead (verified against lib/reaper_guitar_theory.lua's
--     classifier -- see dev/tests/guitar_theory.lua's round-trip cases),
--     keeping the doc's original Type/Sound/RB Mapping labels, which are
--     the actually meaningful content.
--
-- The former 4th power-chord row (2-note, no octave: 'x x x x 5 3') was
-- originally its own type, 'Perfect fifth (power chord)'. Per the Wikipedia
-- definition of a power chord ("the root note and the fifth, as well as
-- POSSIBLY octaves of those notes") the octave is optional to the concept,
-- so it's grouped under plain 'Power chord' here -- one teaching category,
-- not two. This only relabels this static table's display field;
-- GUITAR_DYAD_INTERVALS[7].name in lib/reaper_guitar_theory.lua (the live
-- classifier's own output string for a bare interval-7 dyad) is untouched.
-- ---------------------------------------------------------------------------
GUITAR_CHORDS = {
    -- Power chords (root + 5th [+ octave]), verified shape reversal
    { shape = 'x x x 7 7 5', type = 'Power chord', name = 'A5', sound = 'Strong, stable', rb_mapping = '1-3' },
    { shape = 'x x x 9 9 7', type = 'Power chord', name = 'B5', sound = 'Strong',         rb_mapping = '1-3' },
    { shape = 'x x x 5 5 3', type = 'Power chord', name = 'G5', sound = 'Strong',         rb_mapping = '1-3' },
    { shape = 'x x x x 5 3', type = 'Power chord', name = 'G5', sound = 'Strong',         rb_mapping = '1-3' },

    -- 2-string dyads/intervals (regenerated, see file header)
    { shape = 'x 2 3 x x x', type = 'Minor third',    name = '-', sound = 'Warm',   rb_mapping = '1-2' },
    { shape = 'x 5 5 x x x', type = 'Major third',    name = '-', sound = 'Sweet',  rb_mapping = '1-2' },
    { shape = '7 7 x x x x', type = 'Perfect fourth', name = '-', sound = 'Open',   rb_mapping = '1-2 or 1-3' },
    { shape = 'x x x x 6 2', type = 'Sixth dyad',     name = '-', sound = 'Bright', rb_mapping = '1-3' },

    -- Octave (skip-string) shapes, root + skip + octave; verified shape reversal
    { shape = 'x x x 7 x 5', type = 'Octave', name = '-', sound = 'Strong',       rb_mapping = '1-4' },
    { shape = 'x x 5 x 3 x', type = 'Octave', name = '-', sound = 'Strong, wide', rb_mapping = '1-4' },
    { shape = 'x 5 x 2 x x', type = 'Octave', name = '-', sound = 'Strong',       rb_mapping = '1-4' },

    -- Suspended chords (regenerated, see file header)
    { shape = '1 1 3 x x x', type = 'Sus2', name = 'A#sus2', sound = 'Open, airy', rb_mapping = '1-4' },
    { shape = '1 4 3 x x x', type = 'Sus4', name = 'A#sus4', sound = 'Tense',      rb_mapping = '1-4' },

    -- Triads, verified shape reversal
    { shape = 'x 5 0 x 3 x', type = 'Major triad', name = 'C',  sound = 'Full, rich',   rb_mapping = '3-note' },
    { shape = 'x 0 1 2 x x', type = 'Major triad', name = 'E',  sound = 'Full, bright', rb_mapping = '3-note' },
    { shape = 'x 4 0 x 3 x', type = 'Minor triad', name = 'Cm', sound = 'Dark',         rb_mapping = '3-note' },
    { shape = 'x 0 0 2 x x', type = 'Minor triad', name = 'Em', sound = 'Dark',         rb_mapping = '3-note' },

    -- 7th chords, verified shape reversal
    { shape = 'x 5 3 5 3 x', type = 'Dominant 7', name = 'C7',    sound = 'Bluesy', rb_mapping = '3-note' },
    { shape = 'x 4 3 5 3 x', type = 'Minor 7',    name = 'Cm7',   sound = 'Smooth', rb_mapping = '3-note' },
    { shape = 'x 5 4 5 3 x', type = 'Major 7',    name = 'Cmaj7', sound = 'Dreamy', rb_mapping = '3-note' },

    -- Diminished / Augmented / Half-diminished, verified shape reversal
    { shape = 'x 4 x 4 3 x', type = 'Diminished',      name = 'Cdim',   sound = 'Very tense',       rb_mapping = '3-note' },
    { shape = 'x 5 1 x 3 x', type = 'Augmented',       name = 'Caug',   sound = 'Bright, unstable', rb_mapping = '3-note' },
    { shape = 'x 4 3 4 3 x', type = 'Half-diminished', name = 'Cm7b5', sound = 'Dark',             rb_mapping = '3-note' },

    -- Add9 / Add11 (regenerated, see file header)
    { shape = 'x 5 7 5 3 x', type = 'Add9',  name = 'Cadd9',  sound = 'Bright', rb_mapping = '3-note' },
    { shape = 'x 5 0 3 3 x', type = 'Add11', name = 'Cadd11', sound = 'Open',   rb_mapping = '3-note' },

    -- Slash chord (regenerated): triad with the 5th, not the root, in the bass
    { shape = 'x 0 0 x x 10', type = 'Slash chord', name = 'G/D', sound = 'Bright', rb_mapping = '3-note' },
}

-- ---------------------------------------------------------------------------
-- Guitar chord types: drives the Chord Type Explorer selector in the Guitar
-- tab. Pedagogical order (simple to complex), NOT alphabetical. Every
-- GUITAR_CHORDS.type value must appear here exactly once, and vice versa.
--
-- Descriptions are original wording, not copied from any external source
-- (in particular, not the Wikipedia text this content was originally
-- discussed against -- CC-licensed text isn't pulled into the repo
-- verbatim). Power chord / Major triad / Minor triad are the three
-- "flagship" types with a fuller two-part description; everything else is
-- one-to-three sentences.
-- ---------------------------------------------------------------------------
GUITAR_CHORD_TYPES = {
    { name = 'Power chord', description =
        'A power chord (also written with a "5", e.g. A5) is a root note plus the ' ..
        'perfect fifth above it, often with the root doubled an octave higher for ' ..
        'extra weight. It leaves out the major or minor third, so it is neither ' ..
        'major nor minor -- it works equally well under either, which is why it is ' ..
        'the backbone of rock and metal rhythm guitar.\n\n' ..
        'The shape is movable: the four lowest strings in standard tuning are each ' ..
        'a perfect fourth apart, so the same two-fret finger shape (root on one ' ..
        'string, fifth two frets higher on the next string down in pitch) slides up ' ..
        'and down the neck to root the chord on any note, with the octave (if used) ' ..
        'two frets further up the string after that.\n\n' ..
        'In drop D tuning (the low E string tuned down a whole step to D), a power ' ..
        'chord rooted on that string can be barred with a single finger across ' ..
        'three strings instead of the usual two-finger shape, and a D power chord ' ..
        'can be played on three open strings -- try the Shape Search above with ' ..
        '"0 0 0" to see both tunings\' interpretation of that exact shape.' },
    { name = 'Minor third', description =
        'Two notes a minor third (3 semitones) apart -- a plain interval rather ' ..
        'than a full chord, with a darker color than a major third.' },
    { name = 'Major third', description =
        'Two notes a major third (4 semitones) apart -- a plain interval, ' ..
        'brighter-sounding than a minor third.' },
    { name = 'Perfect fourth', description =
        'Two notes a perfect fourth (5 semitones) apart -- an open, ' ..
        'ambiguous-sounding interval common in rock riffs.' },
    { name = 'Sixth dyad', description =
        'Two notes a major sixth (9 semitones) apart -- a bright, wide-sounding interval.' },
    { name = 'Octave', description =
        'The same note twice, 12 semitones apart, played by skipping a string in ' ..
        'between -- adds thickness without changing the harmony.' },
    { name = 'Sus2', description =
        'A "suspended" triad that replaces the third with a major second (2 ' ..
        'semitones up) -- open and unresolved-sounding, neither major nor minor.' },
    { name = 'Sus4', description =
        'A "suspended" triad that replaces the third with a perfect fourth (5 ' ..
        'semitones up) -- tense-sounding, often resolving back to a major or minor chord.' },
    { name = 'Major triad', description =
        'A major triad stacks a root, a major third (4 semitones up), and a ' ..
        'perfect fifth (7 semitones up) -- the most basic "happy"-sounding chord in ' ..
        'Western music, and the default meaning of a bare chord letter (a plain ' ..
        '"C" means C major).\n\n' ..
        'On guitar it is usually voiced across 3-6 strings with some notes doubled, ' ..
        'not just the three bare pitches -- the reference rows below show a couple ' ..
        'of common voicings, not the only ones.' },
    { name = 'Minor triad', description =
        'A minor triad swaps the major triad\'s major third for a minor third (3 ' ..
        'semitones up), keeping the same perfect fifth -- the classic "sad" or ' ..
        'darker-sounding counterpart to a major chord. Written with a lowercase ' ..
        '"m" after the root (e.g. Am).' },
    { name = 'Dominant 7', description =
        'A major triad plus a minor seventh (10 semitones up) -- the bluesy, ' ..
        'unresolved-sounding chord that wants to resolve down a fifth (e.g. G7 -> C).' },
    { name = 'Minor 7', description =
        'A minor triad plus a minor seventh -- smoother and jazzier-sounding than a ' ..
        'plain minor triad.' },
    { name = 'Major 7', description =
        'A major triad plus a major seventh (11 semitones up) -- a dreamy, ' ..
        'lush-sounding chord common in jazz and soul.' },
    { name = 'Diminished', description =
        'A root, minor third, and diminished fifth (a tritone, 6 semitones up) -- a ' ..
        'tense, unstable-sounding chord that wants to resolve.' },
    { name = 'Augmented', description =
        'A root, major third, and augmented fifth (8 semitones up) -- an unsettled, ' ..
        'dreamlike-sounding chord.' },
    { name = 'Half-diminished', description =
        'A diminished triad plus a minor seventh -- softer than a fully diminished ' ..
        'chord, common as the ii chord in a minor-key ii-V-i progression.' },
    { name = 'Add9', description =
        'A major triad plus a major ninth (the same pitch class as a 2nd, an ' ..
        'octave up) -- adds color without the tension a 7th would add.' },
    { name = 'Add11', description =
        'A major triad plus a perfect 11th (the same pitch class as a 4th, an ' ..
        'octave up) -- adds an open, spacious color.' },
    { name = 'Slash chord', description =
        'Written as "X/Y": chord X, but with note Y (not X\'s own root) as the ' ..
        'lowest note -- common when a bass line walks between chords, or when a ' ..
        'triad is played in an inversion. The example row below is a major triad ' ..
        'with its 5th, not its root, in the bass.' },
}

-- ---------------------------------------------------------------------------
-- RB lane-combo terminology: letter names (G/R/Y/B/O, matching GEM_LETTERS in
-- rock_band_general_helper_vkr/actions_guitar.lua) for each spread width.
-- ---------------------------------------------------------------------------
GUITAR_LANE_TERMS = {
    { width = '1-2',    combos = 'GR, RY, YB, BO' },
    { width = '1-3',    combos = 'GY, RB, YO' },
    { width = '1-4',    combos = 'GB, RO' },
    { width = '1-5',    combos = 'GO' },
    { width = '3-note', combos = 'GRY, GRB, GYB, RYB, RYO, RBO, YBO' },
}
