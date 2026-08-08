-- Unit tests for lib/reaper_music_notation.lua -- the staff-notation model
-- behind the Music Theory helper's Piano tab. Pure; no REAPER objects.

local function midi_of(clef_name, slot, key_n)
    local clef
    for _, c in ipairs(NOTATION_CLEFS) do
        if c.name == clef_name then clef = c end
    end
    Test.expect(clef, 'no such clef: ' .. tostring(clef_name))
    return NotationStepToPitch(clef.bottom_step + slot, key_n or 0, nil, clef.octave_shift)
end

local function name_of(clef_name, slot, key_n)
    local clef
    for _, c in ipairs(NOTATION_CLEFS) do
        if c.name == clef_name then clef = c end
    end
    local step = clef.bottom_step + slot
    local alt  = NotationKeySigAlteration(key_n or 0, step % 7)
    return NotationNoteName(NotationSoundingStep(step, clef.octave_shift), alt)
end

----------------------------------------------------------------------
Test.section('Diatonic steps')

Test.it('middle C is step 28 / MIDI 60', function()
    Test.expect(NOTATION_MIDDLE_C_STEP == 28, 'NOTATION_MIDDLE_C_STEP is ' .. NOTATION_MIDDLE_C_STEP)
    Test.expect(NotationStepToNatural(28) == 60, 'step 28 -> ' .. NotationStepToNatural(28))
end)

Test.it('steps walk the white keys in order', function()
    -- C4 D4 E4 F4 G4 A4 B4 C5
    local want = { 60, 62, 64, 65, 67, 69, 71, 72 }
    for i, midi in ipairs(want) do
        local got = NotationStepToNatural(27 + i)
        Test.expect(got == midi, string.format('step %d -> %d, want %d', 27 + i, got, midi))
    end
end)

Test.it('every octave is exactly 7 steps / 12 semitones', function()
    for step = -14, 56 do
        local lo, hi = NotationStepToNatural(step), NotationStepToNatural(step + 7)
        Test.expect(hi - lo == 12, string.format('step %d: %d -> %d', step, lo, hi))
    end
end)

Test.it('negative steps stay consistent (C0 = 12, C-1 = 0)', function()
    Test.expect(NotationStepToNatural(0) == 12, 'step 0 -> ' .. NotationStepToNatural(0))
    Test.expect(NotationStepToNatural(-7) == 0, 'step -7 -> ' .. NotationStepToNatural(-7))
end)

----------------------------------------------------------------------
Test.section('Clef anchors')

Test.it('bottom lines sound at the conventional pitches', function()
    local want = {
        treble = 64, treble_8va = 76, treble_8vb = 52,
        bass   = 43, bass_8va   = 55, bass_8vb   = 31,
    }
    local n = 0
    for clef_name, midi in pairs(want) do
        local got = midi_of(clef_name, 0)
        Test.expect(got == midi, string.format('%s bottom line -> %d, want %d', clef_name, got, midi))
        n = n + 1
    end
    Test.expect(n == #NOTATION_CLEFS,
                string.format('%d clefs defined but %d checked -- add the new one here', #NOTATION_CLEFS, n))
end)

Test.it('NOTATION_CLEF_IDX points at the clef it names', function()
    local n = 0
    for name, i in pairs(NOTATION_CLEF_IDX) do
        Test.expect(NOTATION_CLEFS[i] and NOTATION_CLEFS[i].name == name,
                    string.format('NOTATION_CLEF_IDX.%s = %d, which is %s', name, i,
                                  NOTATION_CLEFS[i] and NOTATION_CLEFS[i].name or 'nil'))
        n = n + 1
    end
    Test.expect(n == #NOTATION_CLEFS, 'index map has ' .. n .. ' entries for ' .. #NOTATION_CLEFS .. ' clefs')
    -- The two the Piano tab opens on must exist under these exact names.
    Test.expect(NOTATION_CLEF_IDX.treble, 'no clef named treble')
    Test.expect(NOTATION_CLEF_IDX.bass,   'no clef named bass')
end)

Test.it('8va sounds up an octave, 8vb down, from the same lines', function()
    local pairs_ = { { 'treble', 'treble_8va', 12 }, { 'treble', 'treble_8vb', -12 },
                     { 'bass',   'bass_8va',   12 }, { 'bass',   'bass_8vb',   -12 } }
    for _, p in ipairs(pairs_) do
        local plain, shifted, delta = p[1], p[2], p[3]
        for slot = -6, 14 do
            Test.expect(midi_of(shifted, slot) == midi_of(plain, slot) + delta,
                        string.format('%s slot %d', shifted, slot))
        end
        -- The lines themselves must not move -- only what they sound.
        local a, b = nil, nil
        for _, c in ipairs(NOTATION_CLEFS) do
            if c.name == plain then a = c elseif c.name == shifted then b = c end
        end
        Test.expect(a and b, 'missing clef: ' .. plain .. ' or ' .. shifted)
        Test.expect(a.bottom_step == b.bottom_step,
                    shifted .. ' moved its bottom line; it should only transpose')
    end
end)

Test.it('treble top line is F5, bass top line is A3', function()
    Test.expect(midi_of('treble', 8) == 77, 'treble slot 8 -> ' .. midi_of('treble', 8))
    Test.expect(midi_of('bass',   8) == 57, 'bass slot 8 -> '   .. midi_of('bass', 8))
end)

Test.it('middle C is one ledger line below treble and above bass', function()
    Test.expect(midi_of('treble', -2) == 60, 'treble slot -2 -> ' .. midi_of('treble', -2))
    Test.expect(midi_of('bass',   10) == 60, 'bass slot 10 -> '   .. midi_of('bass', 10))
end)

Test.it('every clef declares a sig_family that has slot data', function()
    for _, clef in ipairs(NOTATION_CLEFS) do
        Test.expect(NOTATION_SIG_SLOTS[clef.sig_family],
                    clef.name .. ' has unknown sig_family ' .. tostring(clef.sig_family))
    end
end)

----------------------------------------------------------------------
Test.section('Key signatures')

Test.it('there are 15 signatures, -7 flats through 7 sharps, in order', function()
    Test.expect(#KEY_SIGNATURES == 15, '#KEY_SIGNATURES = ' .. #KEY_SIGNATURES)
    for i, row in ipairs(KEY_SIGNATURES) do
        Test.expect(row.n == i - 8, string.format('row %d has n = %d', i, row.n))
    end
end)

Test.it('KEY_SIG_NATURAL_IDX points at n = 0', function()
    Test.expect(KEY_SIGNATURES[KEY_SIG_NATURAL_IDX].n == 0,
                'KEY_SIG_NATURAL_IDX row n = ' .. KEY_SIGNATURES[KEY_SIG_NATURAL_IDX].n)
end)

Test.it('each label states its own accidental count', function()
    for _, row in ipairs(KEY_SIGNATURES) do
        local count, word = row.label:match('%((%d+) (%a+)%)')
        if row.n == 0 then
            Test.expect(count == nil, 'n = 0 label should not state a count: ' .. row.label)
        else
            Test.expect(tonumber(count) == math.abs(row.n),
                        string.format('label "%s" states %s, n = %d', row.label, tostring(count), row.n))
            local stem = (word or ''):gsub('s$', '')   -- '3 flats' / '1 flat'
            local want = row.n > 0 and 'sharp' or 'flat'
            Test.expect(stem == want, string.format('label "%s" says %s, want %s', row.label, tostring(word), want))
        end
    end
end)

Test.it('C major alters nothing', function()
    local alt = NotationKeySigAlterations(0)
    for deg = 0, 6 do Test.expect(alt[deg] == 0, 'degree ' .. deg .. ' altered in C major') end
end)

Test.it('3 flats alters exactly B, E, A', function()
    local alt   = NotationKeySigAlterations(-3)
    local want  = { [6] = -1, [2] = -1, [5] = -1 }   -- B E A
    for deg = 0, 6 do
        Test.expect(alt[deg] == (want[deg] or 0),
                    string.format('degree %d -> %d in 3 flats', deg, alt[deg]))
    end
end)

Test.it('4 sharps alters exactly F, C, G, D', function()
    local alt  = NotationKeySigAlterations(4)
    local want = { [3] = 1, [0] = 1, [4] = 1, [1] = 1 }   -- F C G D
    for deg = 0, 6 do
        Test.expect(alt[deg] == (want[deg] or 0),
                    string.format('degree %d -> %d in 4 sharps', deg, alt[deg]))
    end
end)

Test.it('7 accidentals alter all seven letters', function()
    for _, n in ipairs({ -7, 7 }) do
        local alt = NotationKeySigAlterations(n)
        for deg = 0, 6 do
            Test.expect(alt[deg] == (n > 0 and 1 or -1),
                        string.format('degree %d unaltered with n = %d', deg, n))
        end
    end
end)

Test.it('sharp and flat orders are the same seven degrees, reversed', function()
    for i = 1, 7 do
        Test.expect(NOTATION_SHARP_ORDER[i] == NOTATION_FLAT_ORDER[8 - i],
                    'orders disagree at position ' .. i)
    end
end)

Test.it('an explicit accidental overrides the key signature', function()
    -- Treble bottom line in 3 flats is Eb; forcing a natural gives E back.
    Test.expect(NotationStepToPitch(30, -3, nil, 0) == 63, 'Eb4 expected')
    Test.expect(NotationStepToPitch(30, -3, 0,   0) == 64, 'forced natural should be E4')
    Test.expect(NotationStepToPitch(30, -3, 1,   0) == 65, 'forced sharp should be E#4')
end)

----------------------------------------------------------------------
Test.section('Key signature glyph placement')

Test.it('n = 0 places no glyphs; |n| places that many', function()
    for _, clef in ipairs(NOTATION_CLEFS) do
        Test.expect(#NotationKeySigSlots(0, clef) == 0, clef.name .. ' drew glyphs for C major')
        for n = -7, 7 do
            Test.expect(#NotationKeySigSlots(n, clef) == math.abs(n),
                        string.format('%s n = %d drew %d glyphs', clef.name, n, #NotationKeySigSlots(n, clef)))
        end
    end
end)

Test.it('glyphs sit on the letters the signature actually alters', function()
    for n = -7, 7 do
        if n ~= 0 then
            for _, clef in ipairs(NOTATION_CLEFS) do
                for _, glyph in ipairs(NotationKeySigSlots(n, clef)) do
                    local degree = (clef.bottom_step + glyph.slot) % 7
                    local alt    = NotationKeySigAlteration(n, degree)
                    Test.expect(alt == (n > 0 and 1 or -1),
                                string.format('%s n = %d: glyph at slot %d is degree %d, which the signature does not alter',
                                              clef.name, n, glyph.slot, degree))
                    Test.expect(glyph.sign == (n > 0 and '#' or 'b'), 'wrong sign for n = ' .. n)
                end
            end
        end
    end
end)

Test.it('glyphs stay on or beside the staff', function()
    for n = -7, 7 do
        for _, clef in ipairs(NOTATION_CLEFS) do
            for _, glyph in ipairs(NotationKeySigSlots(n, clef)) do
                Test.expect(glyph.slot >= 0 and glyph.slot <= 9,
                            string.format('%s n = %d has a glyph at slot %d, off the staff',
                                          clef.name, n, glyph.slot))
            end
        end
    end
end)

Test.it('no two glyphs of one signature share a slot', function()
    for n = -7, 7 do
        for _, clef in ipairs(NOTATION_CLEFS) do
            local seen = {}
            for _, glyph in ipairs(NotationKeySigSlots(n, clef)) do
                Test.expect(not seen[glyph.slot],
                            string.format('%s n = %d repeats slot %d', clef.name, n, glyph.slot))
                seen[glyph.slot] = true
            end
        end
    end
end)

----------------------------------------------------------------------
Test.section('Note spelling')

Test.it('naturals are spelled with no accidental', function()
    Test.expect(NotationNoteName(28, 0) == 'C4', NotationNoteName(28, 0))
    Test.expect(NotationNoteName(34, 0) == 'B4', NotationNoteName(34, 0))
end)

Test.it('a flat key spells flats, not sharps', function()
    -- The trap PitchName would fall into: MIDI 63 in Eb major is Eb4, not D#3.
    Test.expect(name_of('treble', 0, -3) == 'Eb4', name_of('treble', 0, -3))
    Test.expect(midi_of('treble', 0, -3) == 63,    'MIDI ' .. midi_of('treble', 0, -3))
end)

Test.it('a sharp key spells sharps', function()
    -- Treble 2nd line is G4; in 4 sharps that is G#4.
    Test.expect(name_of('treble', 2, 4) == 'G#4', name_of('treble', 2, 4))
    Test.expect(midi_of('treble', 2, 4) == 68,    'MIDI ' .. midi_of('treble', 2, 4))
end)

Test.it('the octave number follows the letter, not the sound', function()
    -- Cb4 sounds as B3 but is still written in octave 4; B#3 sounds as C4.
    Test.expect(NotationNoteName(28, -1) == 'Cb4', NotationNoteName(28, -1))
    Test.expect(NotationStepToNatural(28) - 1 == 59, 'Cb4 should sound MIDI 59')
    Test.expect(NotationNoteName(27, 1) == 'B#3', NotationNoteName(27, 1))
end)

Test.it('an 8vb clef names the sounding octave', function()
    Test.expect(name_of('treble_8vb', 0, -3) == 'Eb3', name_of('treble_8vb', 0, -3))
    Test.expect(midi_of('treble_8vb', 0, -3) == 51,    'MIDI ' .. midi_of('treble_8vb', 0, -3))
end)

Test.it('spelled name and MIDI number always agree', function()
    local pc = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
    for n = -7, 7 do
        for _, clef in ipairs(NOTATION_CLEFS) do
            for slot = -6, 14 do
                local step   = clef.bottom_step + slot
                local alt    = NotationKeySigAlteration(n, step % 7)
                local name   = NotationNoteName(NotationSoundingStep(step, clef.octave_shift), alt)
                local midi   = NotationStepToPitch(step, n, nil, clef.octave_shift)
                local letter, acc, oct = name:match('^(%a)(#*b*)(-?%d+)$')
                Test.expect(letter, 'unparseable name: ' .. name)
                local from_name = 12 * (tonumber(oct) + 1) + pc[letter]
                                  + (acc == '#' and 1 or acc == 'b' and -1 or 0)
                Test.expect(from_name == midi,
                            string.format('%s says MIDI %d, model says %d', name, from_name, midi))
            end
        end
    end
end)

----------------------------------------------------------------------
Test.section('REAPER piano-roll naming')

Test.it('the name table is REAPER\'s twelve, in chromatic order', function()
    local want = { 'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B' }
    Test.expect(#RB_NOTE_NAMES == 12, '#RB_NOTE_NAMES = ' .. #RB_NOTE_NAMES)
    for i, name in ipairs(want) do
        Test.expect(RB_NOTE_NAMES[i] == name,
                    string.format('index %d is %s, want %s', i, RB_NOTE_NAMES[i], name))
    end
end)

Test.it('octaves follow the Rock Band convention (C1 = 36)', function()
    local want = { [0] = 'C-2', [12] = 'C-1', [24] = 'C0', [36] = 'C1',
                   [48] = 'C2', [60] = 'C3', [72] = 'C4', [84] = 'C5' }
    for midi, name in pairs(want) do
        Test.expect(RBPitchName(midi) == name,
                    string.format('MIDI %d -> %s, want %s', midi, RBPitchName(midi), name))
    end
end)

Test.it('the two flat spellings are flats, not sharps', function()
    Test.expect(RBPitchName(63) == 'Eb3', RBPitchName(63))
    Test.expect(RBPitchName(70) == 'Bb3', RBPitchName(70))
end)

Test.it('the other three accidentals are sharps', function()
    Test.expect(RBPitchName(61) == 'C#3', RBPitchName(61))
    Test.expect(RBPitchName(66) == 'F#3', RBPitchName(66))
    Test.expect(RBPitchName(68) == 'G#3', RBPitchName(68))
end)

Test.it('out-of-range input is clamped, not errored', function()
    Test.expect(RBPitchName(-20) == RBPitchName(0),   'negative should clamp to 0')
    Test.expect(RBPitchName(999) == RBPitchName(127), 'too high should clamp to 127')
end)

Test.it('names round-trip back to their MIDI number', function()
    local pc = {}
    for i, name in ipairs(RB_NOTE_NAMES) do pc[name] = i - 1 end
    for midi = 0, 127 do
        local name = RBPitchName(midi)
        local stem, oct = name:match('^(%a[#b]?)(-?%d+)$')
        Test.expect(stem and pc[stem], 'unparseable name: ' .. name)
        local back = 12 * (tonumber(oct) - RB_OCTAVE_OFFSET) + pc[stem]
        Test.expect(back == midi, string.format('%s -> %d, want %d', name, back, midi))
    end
end)

Test.it('it names the same key as the staff model, spelling aside', function()
    -- The point of the toggle: two different names, never two different keys.
    -- Db in Ab major is the trap -- the staff says Db, the piano roll says C#.
    local pc = {}
    for i, name in ipairs(RB_NOTE_NAMES) do pc[name] = i - 1 end
    for n = -7, 7 do
        for _, clef in ipairs(NOTATION_CLEFS) do
            for slot = -6, 14 do
                local midi = NotationStepToPitch(clef.bottom_step + slot, n, nil, clef.octave_shift)
                local stem = RBPitchName(midi):match('^(%a[#b]?)')
                Test.expect(pc[stem] == midi % 12,
                            string.format('MIDI %d named %s (pc %d, want %d)',
                                          midi, RBPitchName(midi), pc[stem], midi % 12))
            end
        end
    end
end)

Test.it('Ab major: the staff spells Db, the piano roll spells C#', function()
    -- Ab major is 4 flats (B E A D). Treble 2nd space is A4 -> Ab4; the space
    -- below the bottom line is D4 -> Db4. Same keys, different names.
    Test.expect(name_of('treble',  3, -4) == 'Ab4', name_of('treble', 3, -4))
    Test.expect(RBPitchName(midi_of('treble',  3, -4)) == 'G#3',
                RBPitchName(midi_of('treble', 3, -4)))
    Test.expect(name_of('treble', -1, -4) == 'Db4', name_of('treble', -1, -4))
    Test.expect(RBPitchName(midi_of('treble', -1, -4)) == 'C#3',
                RBPitchName(midi_of('treble', -1, -4)))
end)

Test.it('Ab major: E natural needs an accidental, Eb does not', function()
    -- The 4th space is an E; with 4 flats it reads Eb, and both namings agree
    -- on the spelling there (Eb is one of REAPER's twelve).
    Test.expect(name_of('treble', 7, -4) == 'Eb5', name_of('treble', 7, -4))
    Test.expect(RBPitchName(midi_of('treble', 7, -4)) == 'Eb4',
                RBPitchName(midi_of('treble', 7, -4)))
    -- Forcing a natural is a semitone up, and that is a different key.
    Test.expect(NotationStepToPitch(37, -4, 0, 0) == midi_of('treble', 7, -4) + 1,
                'E natural should be one semitone above Eb')
end)

----------------------------------------------------------------------
Test.section('Piano keyboard layout')

Test.it('C2-C6 has every MIDI note exactly once, in order', function()
    local keys = PianoKeyLayout(36, 84)
    Test.expect(#keys == 49, '#keys = ' .. #keys)
    for i, key in ipairs(keys) do
        Test.expect(key.midi == 35 + i, string.format('key %d is MIDI %d', i, key.midi))
    end
end)

Test.it('black/white classification matches pitch class', function()
    local black = { [1] = true, [3] = true, [6] = true, [8] = true, [10] = true }
    for _, key in ipairs(PianoKeyLayout(36, 84)) do
        Test.expect(key.is_black == (black[key.midi % 12] or false),
                    'MIDI ' .. key.midi .. ' misclassified')
    end
end)

Test.it('an octave has 7 white and 5 black keys', function()
    local keys, whites = PianoKeyLayout(60, 71)
    Test.expect(whites == 7, 'whites = ' .. whites)
    Test.expect(#keys - whites == 5, 'blacks = ' .. (#keys - whites))
end)

Test.it('white keys tile left to right with no gap or overlap', function()
    local keys = PianoKeyLayout(36, 84)
    local next_x = 0
    for _, key in ipairs(keys) do
        if not key.is_black then
            Test.expect(math.abs(key.x - next_x) < 1e-9,
                        string.format('white MIDI %d starts at %.3f, want %.3f', key.midi, key.x, next_x))
            next_x = next_x + key.w
        end
    end
end)

Test.it('black keys overlap the boundary between their neighbours', function()
    for _, key in ipairs(PianoKeyLayout(36, 84)) do
        if key.is_black then
            local lo, hi = key.x, key.x + key.w
            -- The boundary is the left edge of the white key above it, which
            -- for every black key is a whole number of white widths.
            local boundary = math.floor(lo) + 1
            Test.expect(lo < boundary and hi > boundary,
                        string.format('black MIDI %d spans %.3f..%.3f, missing boundary %d',
                                      key.midi, lo, hi, boundary))
        end
    end
end)

Test.it('total width equals the white key count', function()
    for _, span in ipairs({ { 36, 84 }, { 48, 72 }, { 60, 60 }, { 21, 108 } }) do
        local keys, whites = PianoKeyLayout(span[1], span[2])
        local right = 0
        for _, key in ipairs(keys) do
            if not key.is_black then right = math.max(right, key.x + key.w) end
        end
        Test.expect(right == whites,
                    string.format('span %d-%d: right edge %.3f, whites %d', span[1], span[2], right, whites))
    end
end)

----------------------------------------------------------------------
Test.section('Reference case: the Eb major grand staff')

-- The screenshot this feature was built from: 3 flats, an octave-down treble
-- over a bass clef. The upper chord sits on the bottom line, second line and
-- third line -- E, G and B, which the signature turns into Eb, G and Bb.
Test.it('upper staff (Treble 8vb) reads Eb3 G3 Bb3', function()
    local want_name = { 'Eb3', 'G3', 'Bb3' }
    local want_midi = { 51, 55, 58 }
    for i, slot in ipairs({ 0, 2, 4 }) do
        Test.expect(name_of('treble_8vb', slot, -3) == want_name[i],
                    string.format('slot %d -> %s, want %s', slot, name_of('treble_8vb', slot, -3), want_name[i]))
        Test.expect(midi_of('treble_8vb', slot, -3) == want_midi[i],
                    string.format('slot %d -> MIDI %d, want %d', slot, midi_of('treble_8vb', slot, -3), want_midi[i]))
    end
end)

Test.it('lower staff (Bass) reads the same letters an octave down', function()
    -- Bass slot -2 is Eb2, slot 0 is G2, slot 2 is Bb2.
    Test.expect(name_of('bass', -2, -3) == 'Eb2', name_of('bass', -2, -3))
    Test.expect(name_of('bass',  0, -3) == 'G2',  name_of('bass',  0, -3))
    Test.expect(name_of('bass',  2, -3) == 'Bb2', name_of('bass',  2, -3))
end)

Test.it('the same positions read differently in C major', function()
    -- The whole point of setting a key signature: identical note heads, and
    -- with no flats these are E, G and B naturals instead.
    for i, slot in ipairs({ 0, 2, 4 }) do
        local want = ({ 'E3', 'G3', 'B3' })[i]
        Test.expect(name_of('treble_8vb', slot, 0) == want,
                    string.format('slot %d -> %s, want %s', slot, name_of('treble_8vb', slot, 0), want))
    end
end)
