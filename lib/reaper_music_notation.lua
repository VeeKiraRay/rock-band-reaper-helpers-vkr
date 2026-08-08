-- Pure staff-notation model: clef + key signature + staff position -> sounding
-- pitch and spelled note name, plus piano-keyboard geometry.
-- No dependency on r/ctx/S -- pure global functions/tables only, safe to
-- dofile from a Lua-only context (see dev/tests/run_music_notation.lua).
--
-- Consumed by rock_band_music_theory_helper_vkr's Piano tab (ui_piano.lua),
-- which draws a grand staff you click to place note heads and reports which
-- keys to press.

----------------------------------------------------------------------
-- The diatonic step
--
-- Everything here hinges on one integer. A STEP indexes letter names in
-- scientific pitch notation:
--
--     step = 7 * octave + degree      degree 0..6 = C D E F G A B
--
-- so middle C (C4, MIDI 60) is step 28, and consecutive steps are
-- consecutive letters regardless of how many semitones apart they sound.
-- That is exactly what a staff position is -- which is why a mouse y
-- coordinate can be turned into one integer and back.
--
-- Note that a step carries no accidental: the accidental comes from the key
-- signature (or, later, an explicit per-note override), applied to the
-- step's DEGREE. Cb4 and C#4 are both step 28.
----------------------------------------------------------------------

NOTATION_DEGREE_SEMITONE = { 0, 2, 4, 5, 7, 9, 11 }               -- 1-based by degree+1
NOTATION_DEGREE_LETTER   = { 'C', 'D', 'E', 'F', 'G', 'A', 'B' }  -- 1-based by degree+1

NOTATION_MIDDLE_C_STEP = 28   -- C4; sounds MIDI 60

-- Suffix per alteration in semitones. Flats are spelled 'b' and sharps '#'
-- rather than the Unicode musical accidentals: the default ImGui font this
-- gets drawn in has no glyphs for the real signs (the same reason
-- ui_venue_players.lua draws its dot with AddCircleFilled instead of a
-- character), and 'Eb4' is what a charter would type anyway.
NOTATION_ACCIDENTAL_SUFFIX = { [-2] = 'bb', [-1] = 'b', [0] = '', [1] = '#', [2] = '##' }

----------------------------------------------------------------------
-- Clefs
--
-- A clef is fully described for our purposes by two numbers: the step
-- sitting on the BOTTOM line of its five-line staff, and how far the
-- written pitch is transposed when sounded.
--
-- Treble bottom line = E4 (step 30). Bass bottom line = G2 (step 18).
--
-- A small 8 printed with the clef transposes what it sounds without moving
-- any note off its line: 8 ABOVE the clef (8va, ottava alta) sounds an
-- octave higher, 8 BELOW it (8vb, ottava bassa) an octave lower. Both
-- directions exist for both clefs, so all four are listed even though
-- treble-8vb (tenor voice, guitar) is by far the one seen most.
--
-- Not modelled: the dashed `8va------` bracket over a passage, which is a
-- temporary shift of those notes only rather than a property of the clef.
-- Reading one of those into this tab means switching the staff to the
-- matching transposing clef for as long as the bracket lasts.
--
-- sig_family selects the conventional key-signature glyph positions below;
-- an octave-transposing clef keeps its parent's positions.
----------------------------------------------------------------------

NOTATION_CLEFS = {
    { name = 'treble',     label = 'Treble',       bottom_step = 30, octave_shift =   0, sig_family = 'treble' },
    { name = 'treble_8va', label = 'Treble (8va)', bottom_step = 30, octave_shift =  12, sig_family = 'treble' },
    { name = 'treble_8vb', label = 'Treble (8vb)', bottom_step = 30, octave_shift = -12, sig_family = 'treble' },
    { name = 'bass',       label = 'Bass',         bottom_step = 18, octave_shift =   0, sig_family = 'bass'   },
    { name = 'bass_8va',   label = 'Bass (8va)',   bottom_step = 18, octave_shift =  12, sig_family = 'bass'   },
    { name = 'bass_8vb',   label = 'Bass (8vb)',   bottom_step = 18, octave_shift = -12, sig_family = 'bass'   },
}

-- Position lookup by name. Callers and S defaults index through this rather
-- than hardcoding a row number, so inserting a clef can't silently repoint
-- them at a different one.
NOTATION_CLEF_IDX = {}
for i, clef in ipairs(NOTATION_CLEFS) do NOTATION_CLEF_IDX[clef.name] = i end

----------------------------------------------------------------------
-- Key signatures
--
-- Sharps are added in the order F C G D A E B, flats in the reverse order
-- B E A D G C F. Stored as DEGREES (0=C .. 6=B) so they index straight into
-- the tables above.
----------------------------------------------------------------------

NOTATION_SHARP_ORDER = { 3, 0, 4, 1, 5, 2, 6 }   -- F C G D A E B
NOTATION_FLAT_ORDER  = { 6, 2, 5, 1, 4, 0, 3 }   -- B E A D G C F

-- n = signed accidental count: negative = that many flats, positive = sharps.
KEY_SIGNATURES = {
    { n = -7, major = 'Cb', minor = 'Ab', label = 'Cb major / Ab minor (7 flats)' },
    { n = -6, major = 'Gb', minor = 'Eb', label = 'Gb major / Eb minor (6 flats)' },
    { n = -5, major = 'Db', minor = 'Bb', label = 'Db major / Bb minor (5 flats)' },
    { n = -4, major = 'Ab', minor = 'F',  label = 'Ab major / F minor (4 flats)'  },
    { n = -3, major = 'Eb', minor = 'C',  label = 'Eb major / C minor (3 flats)'  },
    { n = -2, major = 'Bb', minor = 'G',  label = 'Bb major / G minor (2 flats)'  },
    { n = -1, major = 'F',  minor = 'D',  label = 'F major / D minor (1 flat)'    },
    { n =  0, major = 'C',  minor = 'A',  label = 'C major / A minor (no sharps or flats)' },
    { n =  1, major = 'G',  minor = 'E',  label = 'G major / E minor (1 sharp)'   },
    { n =  2, major = 'D',  minor = 'B',  label = 'D major / B minor (2 sharps)'  },
    { n =  3, major = 'A',  minor = 'F#', label = 'A major / F# minor (3 sharps)' },
    { n =  4, major = 'E',  minor = 'C#', label = 'E major / C# minor (4 sharps)' },
    { n =  5, major = 'B',  minor = 'G#', label = 'B major / G# minor (5 sharps)' },
    { n =  6, major = 'F#', minor = 'D#', label = 'F# major / D# minor (6 sharps)' },
    { n =  7, major = 'C#', minor = 'A#', label = 'C# major / A# minor (7 sharps)' },
}

KEY_SIG_NATURAL_IDX = 8   -- the n = 0 row; the sensible default selection

-- Where each key-signature accidental is drawn, as a staff SLOT (see below),
-- in the same 1..7 order as NOTATION_SHARP_ORDER / NOTATION_FLAT_ORDER.
--
-- These are the conventional engraved positions, not something derivable by
-- formula: a signature accidental is placed to stay inside (or just at the
-- edge of) the staff, so the sequence jumps octaves where a strict "next one
-- down a fourth / up a fifth" rule would run off the top or bottom. The bass
-- positions are the treble ones two slots lower EXCEPT the seventh flat (Fb),
-- which wraps an octave up to the 4th line instead of dropping below the
-- staff.
NOTATION_SIG_SLOTS = {
    -- treble: F5 C5 G5 D5 A4 E5 B4  /  Bb4 Eb5 Ab4 Db5 Gb4 Cb5 Fb4
    treble = { sharp = { 8, 5, 9, 6, 3, 7, 4 }, flat = { 4, 7, 3, 6, 2, 5, 1 } },
    -- bass:   F3 C3 G3 D3 A2 E3 B2  /  Bb2 Eb3 Ab2 Db3 Gb2 Cb3 Fb3
    bass   = { sharp = { 6, 3, 7, 4, 1, 5, 2 }, flat = { 2, 5, 1, 4, 0, 3, 6 } },
}

----------------------------------------------------------------------
-- Staff slots
--
-- A SLOT is a vertical position on one five-line staff, counting half
-- spaces upward from the bottom line: 0 = bottom line, 1 = the space above
-- it, 2 = second line, ... 8 = top line. Slots below 0 or above 8 are
-- outside the staff and need ledger lines (at even slots only -- odd slots
-- are spaces).
--
--     step = clef.bottom_step + slot
----------------------------------------------------------------------

-- MIDI note of a step with no accidental applied.
function NotationStepToNatural(step)
    local oct = math.floor(step / 7)
    local deg = step - oct * 7
    return 12 * (oct + 1) + NOTATION_DEGREE_SEMITONE[deg + 1]
end

-- Alteration in semitones (-1, 0 or +1) that key signature `n` applies to
-- one degree. Allocation-free -- called per note head per frame.
function NotationKeySigAlteration(n, degree)
    n = n or 0
    if n > 0 then
        for i = 1, math.min(n, 7) do
            if NOTATION_SHARP_ORDER[i] == degree then return 1 end
        end
    elseif n < 0 then
        for i = 1, math.min(-n, 7) do
            if NOTATION_FLAT_ORDER[i] == degree then return -1 end
        end
    end
    return 0
end

-- The same thing for all seven degrees at once: alt[degree] = -1 | 0 | 1.
function NotationKeySigAlterations(n)
    local alt = {}
    for deg = 0, 6 do alt[deg] = NotationKeySigAlteration(n, deg) end
    return alt
end

-- The step a WRITTEN step actually sounds at, under an octave-transposing
-- clef. octave_shift is a whole number of octaves in semitones, so this is
-- always a whole number of diatonic octaves (7 steps) -- which means the
-- degree, and therefore the key-signature alteration, is unchanged.
function NotationSoundingStep(step, octave_shift)
    return step + 7 * math.floor((octave_shift or 0) / 12)
end

-- Sounding MIDI note for a written step.
--   key_n        signed key-signature accidental count (see KEY_SIGNATURES)
--   accidental   nil = follow the key signature; a number (-2..2) = an
--                explicit per-note override, ignoring the signature
--   octave_shift the clef's transposition in semitones
function NotationStepToPitch(step, key_n, accidental, octave_shift)
    local alt = accidental
    if alt == nil then alt = NotationKeySigAlteration(key_n, step % 7) end
    return NotationStepToNatural(step) + alt + (octave_shift or 0)
end

-- Spelled name for a step, e.g. 'Eb4', 'F#3', 'B4'. Pass the SOUNDING step
-- (see NotationSoundingStep) to name what the player actually plays.
--
-- This deliberately does not go through PitchName (lib/reaper_imgui_helpers.lua):
-- that one is sharps-only and uses the Rock Band octave convention (C3 = 60),
-- so it would call this Eb4 'D#3'. On a staff the spelling is the whole
-- point, and the octave numbers here are scientific pitch notation (C4 = 60).
function NotationNoteName(step, alteration)
    local oct = math.floor(step / 7)
    local deg = step - oct * 7
    return NOTATION_DEGREE_LETTER[deg + 1]
        .. (NOTATION_ACCIDENTAL_SUFFIX[alteration or 0] or '')
        .. tostring(oct)
end

-- Slots and signs for drawing key signature `n` under `clef`, left to right.
-- Returns { { slot = int, sign = '#' | 'b' }, ... } -- empty for n = 0.
function NotationKeySigSlots(n, clef)
    n = n or 0
    local out = {}
    if n == 0 then return out end
    local fam   = NOTATION_SIG_SLOTS[(clef and clef.sig_family) or 'treble']
    local slots = n > 0 and fam.sharp or fam.flat
    local sign  = n > 0 and '#' or 'b'
    for i = 1, math.min(math.abs(n), 7) do
        out[#out + 1] = { slot = slots[i], sign = sign }
    end
    return out
end

----------------------------------------------------------------------
-- REAPER piano-roll naming
--
-- What REAPER's MIDI editor prints down the side of the piano roll, which is
-- what a charter is actually looking at while working. It mixes accidentals
-- rather than picking one: sharps for C#/F#/G#, flats for Eb/Bb. Two pitch
-- classes therefore disagree with PitchName (lib/reaper_imgui_helpers.lua),
-- whose table is all sharps -- D#/Eb and A#/Bb name the same key.
--
-- This is a fixed 12-name table, NOT staff spelling: it has no key signature
-- and no concept of a letter, so Db and C# are the same string here even
-- though they are different notes on a page. That is the trade -- it matches
-- the piano roll exactly, which is the point.
----------------------------------------------------------------------

RB_NOTE_NAMES = { 'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B' }

-- Rock Band octave convention: C1 = 36 (the kick drum), so middle C reads C3
-- -- one lower than the scientific C4 the staff model above uses. Charters
-- read pitches this way because the RB MIDI templates are numbered in it.
-- Kept in step with PitchName in lib/reaper_imgui_helpers.lua, which applies
-- the same offset; the two live in different libs because that one is loaded
-- by every script and this one only where notation is needed.
RB_OCTAVE_OFFSET = -2

-- MIDI note -> the string REAPER's piano roll shows for it, e.g. 63 -> 'Eb3'.
function RBPitchName(p)
    p = math.floor(p + 0.5)
    if p < 0 then p = 0 elseif p > 127 then p = 127 end
    return ('%s%d'):format(RB_NOTE_NAMES[(p % 12) + 1],
                           math.floor(p / 12) + RB_OCTAVE_OFFSET)
end

----------------------------------------------------------------------
-- Piano keyboard geometry
----------------------------------------------------------------------

NOTATION_BLACK_PC = { [1] = true, [3] = true, [6] = true, [8] = true, [10] = true }

-- Black key width, in white-key widths.
NOTATION_BLACK_W = 0.62

-- A black key nominally sits on the boundary between its two neighbouring
-- white keys, but on a real keyboard the three-key and two-key groups are
-- nudged outward so the white keys behind them stay playable. Fractions of a
-- white-key width; tune visually.
NOTATION_BLACK_NUDGE = { [1] = -0.10, [3] = 0.10, [6] = -0.13, [8] = 0.0, [10] = 0.13 }

-- Key rectangles for the MIDI range [lo_midi, hi_midi], in NORMALIZED units
-- where one white key is 1.0 wide and x = 0 is the left edge of the first
-- white key -- the caller scales to pixels.
--
-- Returns keys[], white_count. keys[] is in ascending MIDI order, so drawing
-- it in order paints white keys before the black keys that overlap them
-- only if the caller makes two passes: do whites first, then blacks, or the
-- blacks get covered.
--
-- lo_midi should be a white (natural) pitch -- a range starting on a black
-- key puts that key's left edge at a negative x, since there is no white key
-- to its left to sit against.
function PianoKeyLayout(lo_midi, hi_midi)
    local keys, white_i = {}, 0
    for m = lo_midi, hi_midi do
        local pc = m % 12
        if NOTATION_BLACK_PC[pc] then
            local cx = white_i + (NOTATION_BLACK_NUDGE[pc] or 0)
            keys[#keys + 1] = {
                midi = m, is_black = true,
                x = cx - NOTATION_BLACK_W / 2, w = NOTATION_BLACK_W,
            }
        else
            keys[#keys + 1] = { midi = m, is_black = false, x = white_i, w = 1 }
            white_i = white_i + 1
        end
    end
    return keys, white_i
end
