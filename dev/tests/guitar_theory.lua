-- Guitar Theory algorithm test set. Run via run_guitar_theory.lua.
-- Requires: Test (framework.lua), GuitarParseFretInput/GuitarClassifyChordType/
-- GuitarSuggestRBMapping/GuitarAnalyzeShape (lib/reaper_guitar_theory.lua).

Test.section('GuitarParseFretInput')

Test.it('full 6-token form parses muted + fretted strings', function()
    local pitches, err = GuitarParseFretInput('x 7 9 9 7 x')
    Test.expect(pitches ~= nil, 'expected pitches, got err=' .. tostring(err))
    Test.expect(#pitches == 4, 'expected 4 pitches, got ' .. #pitches)
end)

Test.it('compact form right-anchors to the lowest strings', function()
    local pitches, err = GuitarParseFretInput('10 7 7')
    Test.expect(pitches ~= nil, 'expected pitches, got err=' .. tostring(err))
    Test.expect(#pitches == 3, 'expected 3 pitches, got ' .. #pitches)
    local sorted = { pitches[1], pitches[2], pitches[3] }
    table.sort(sorted)
    Test.expect(sorted[1] == GUITAR_TAB_OPEN[6] + 7, 'string 6 (E) should be open+7')
    Test.expect(sorted[2] == GUITAR_TAB_OPEN[5] + 7, 'string 5 (A) should be open+7')
    Test.expect(sorted[3] == GUITAR_TAB_OPEN[4] + 10, 'string 4 (D) should be open+10')
end)

Test.it('edge mutes (explicit, dash, or omitted) are all equivalent', function()
    local function sorted_pitches(text)
        local p = GuitarParseFretInput(text)
        Test.expect(p ~= nil, text .. ' failed to parse')
        table.sort(p)
        return p
    end
    local a = sorted_pitches('7 7 5')
    local b = sorted_pitches('x x x 7 7 5')
    local c = sorted_pitches('- - - 7 7 5')
    local d = sorted_pitches('- 7 7 5 -')
    for _, other in ipairs({ b, c, d }) do
        Test.expect(#a == #other, 'pitch count mismatch')
        for i = 1, #a do
            Test.expect(a[i] == other[i], 'pitch mismatch at index ' .. i)
        end
    end
end)

Test.it('interior mute is preserved (octave) in compact form', function()
    local full = GuitarParseFretInput('x x x 7 x 5')
    local compact = GuitarParseFretInput('7 x 5')
    table.sort(full)
    table.sort(compact)
    Test.expect(#full == #compact and full[1] == compact[1] and full[2] == compact[2],
        'compact interior-mute form should match the full form')
end)

Test.it('interior mute changes the result vs. no mute', function()
    local with_gap = GuitarParseFretInput('7 x 5')
    local without_gap = GuitarParseFretInput('7 5')
    table.sort(with_gap)
    table.sort(without_gap)
    Test.expect(with_gap[2] - with_gap[1] ~= without_gap[2] - without_gap[1],
        'skipping a string should change the interval')
end)

Test.it('single played note among mutes resolves to the lowest string', function()
    local pitches = GuitarParseFretInput('x 7 x')
    Test.expect(pitches ~= nil and #pitches == 1, 'expected 1 pitch')
    Test.expect(pitches[1] == GUITAR_TAB_OPEN[6] + 7, 'should resolve to low E string fret 7')
end)

Test.it('empty string is rejected', function()
    local pitches, err = GuitarParseFretInput('')
    Test.expect(pitches == nil and err == 'empty', 'expected nil, "empty"')
end)

Test.it('nil input is rejected', function()
    local pitches, err = GuitarParseFretInput(nil)
    Test.expect(pitches == nil and err == 'empty', 'expected nil, "empty"')
end)

Test.it('whitespace-only input is rejected', function()
    local pitches, err = GuitarParseFretInput('   ')
    Test.expect(pitches == nil and err == 'empty', 'expected nil, "empty"')
end)

Test.it('single token parses one pitch, bottom-anchored to low E', function()
    local pitches, err = GuitarParseFretInput('7')
    Test.expect(pitches ~= nil and #pitches == 1, 'expected 1 pitch, got err=' .. tostring(err))
    Test.expect(pitches[1] == GUITAR_TAB_OPEN[6] + 7, 'single token should use string 6 (low E)')
end)

Test.it('more than 6 tokens is rejected', function()
    local pitches, err = GuitarParseFretInput('1 2 3 4 5 6 7')
    Test.expect(pitches == nil and err == 'too many tokens (max 6)', 'expected too-many-tokens error')
end)

Test.it('non-numeric garbage with no frets is rejected', function()
    local pitches, err = GuitarParseFretInput('foo bar')
    Test.expect(pitches == nil and err == 'no frets recognized', 'expected no-frets-recognized error')
end)

----------------------------------------------------------------------

Test.section('GuitarClassifyChordType — dyads')

Test.it('interval 3 -> Minor third', function()
    local t = GuitarClassifyChordType({ 45, 48 })
    Test.expect(t == 'Minor third', 'got ' .. tostring(t))
end)

Test.it('interval 4 -> Major third', function()
    local t = GuitarClassifyChordType({ 45, 49 })
    Test.expect(t == 'Major third', 'got ' .. tostring(t))
end)

Test.it('interval 5 -> Perfect fourth', function()
    local t = GuitarClassifyChordType({ 45, 50 })
    Test.expect(t == 'Perfect fourth', 'got ' .. tostring(t))
end)

Test.it('interval 7 -> Perfect fifth (power chord)', function()
    local t = GuitarClassifyChordType({ 45, 52 })
    Test.expect(t == 'Perfect fifth (power chord)', 'got ' .. tostring(t))
end)

Test.it('interval 12 -> Octave, distinct from unison', function()
    local t = GuitarClassifyChordType({ 45, 57 })
    Test.expect(t == 'Octave', 'got ' .. tostring(t))
end)

Test.it('interval 0 (unison) -> Single note, not Octave', function()
    local t = GuitarClassifyChordType({ 45, 45 })
    Test.expect(t == 'Single note', 'got ' .. tostring(t))
end)

Test.it('single pitch -> Single note', function()
    local t = GuitarClassifyChordType({ 45 })
    Test.expect(t == 'Single note', 'got ' .. tostring(t))
end)

Test.it('empty -> No notes', function()
    local t = GuitarClassifyChordType({})
    Test.expect(t == 'No notes', 'got ' .. tostring(t))
end)

Test.it('unrecognized interval does not crash', function()
    local t = GuitarClassifyChordType({ 45, 46 })  -- interval 1
    Test.expect(t:find('Unrecognized interval'), 'got ' .. tostring(t))
end)

----------------------------------------------------------------------

Test.section('GuitarClassifyChordType — chords (round-trip via GUITAR_CHORDS)')

-- Each row: {shape string in GuitarParseFretInput's 6-token form, expected type}.
-- These are the same verified shapes shipped in
-- rock_band_music_theory_helper_vkr/defaults.lua's GUITAR_CHORDS table.
local CHORD_ROUNDTRIP_CASES = {
    { 'x x x 7 7 5',   'Power chord' },
    { 'x x x 9 9 7',   'Power chord' },
    { 'x x x 5 5 3',   'Power chord' },
    { '1 1 3 x x x',   'Sus2' },
    { '1 4 3 x x x',   'Sus4' },
    { 'x 5 0 x 3 x',   'Major triad' },
    { 'x 0 1 2 x x',   'Major triad' },
    { 'x 4 0 x 3 x',   'Minor triad' },
    { 'x 0 0 2 x x',   'Minor triad' },
    { 'x 5 3 5 3 x',   'Dominant 7' },
    { 'x 4 3 5 3 x',   'Minor 7' },
    { 'x 5 4 5 3 x',   'Major 7' },
    { 'x 4 x 4 3 x',   'Diminished' },
    { 'x 5 1 x 3 x',   'Augmented' },
    { 'x 4 3 4 3 x',   'Half-diminished' },
    { 'x 5 7 5 3 x',   'Add9' },
    { 'x 5 0 3 3 x',   'Add11' },
}

for _, case in ipairs(CHORD_ROUNDTRIP_CASES) do
    local shape_str, expected = case[1], case[2]
    Test.it(shape_str .. ' -> ' .. expected, function()
        local pitches = GuitarParseFretInput(shape_str)
        Test.expect(pitches ~= nil, 'shape failed to parse')
        local t = GuitarClassifyChordType(pitches)
        Test.expect(t == expected, 'expected ' .. expected .. ', got ' .. tostring(t))
    end)
end

Test.it('slash/inversion shape reports Major triad with inversion detail', function()
    local pitches = GuitarParseFretInput('x 0 0 x x 10')  -- bass = 5th, not root
    local t, detail = GuitarClassifyChordType(pitches)
    Test.expect(t == 'Major triad', 'got ' .. tostring(t))
    Test.expect(detail ~= nil and detail:find('slash/inversion'), 'expected inversion detail, got ' .. tostring(detail))
end)

Test.it('dissonant/unrecognized pitch set does not crash', function()
    local t = GuitarClassifyChordType({ 40, 41, 46 })  -- pcs {0,1,6}, no template match
    Test.expect(t:find('Unrecognized chord shape'), 'got ' .. tostring(t))
end)

----------------------------------------------------------------------

Test.section('GuitarSuggestRBMapping')

Test.it('interval-1-spread dyad -> width 1-2, 4 ambiguous options, no combo', function()
    local width, combo, opts = GuitarSuggestRBMapping({ 45, 49 })  -- Major third
    Test.expect(width == '1-2', 'got width=' .. tostring(width))
    Test.expect(combo == nil, 'expected no unambiguous combo')
    Test.expect(opts ~= nil and #opts == 4, 'expected 4 options')
end)

Test.it('octave (interval 12) -> width 1-4, 2 options, no combo', function()
    local width, combo, opts = GuitarSuggestRBMapping({ 45, 57 })
    Test.expect(width == '1-4', 'got width=' .. tostring(width))
    Test.expect(combo == nil, 'expected no unambiguous combo')
    Test.expect(opts ~= nil and #opts == 2, 'expected 2 options')
end)

Test.it('wide/compound interval (>12) -> width 1-5, unambiguous combo GO', function()
    local width, combo, opts = GuitarSuggestRBMapping({ 40, 57 })  -- 17 semitones
    Test.expect(width == '1-5', 'got width=' .. tostring(width))
    Test.expect(combo == 'GO', 'expected unambiguous GO combo, got ' .. tostring(combo))
end)

Test.it('3+ note chord with 3 distinct pitch classes -> width 3-note chord, 7 ambiguous options', function()
    local pitches = GuitarParseFretInput('x 5 0 x 3 x')  -- Major triad: pcs {0,4,7}
    local width, combo, opts = GuitarSuggestRBMapping(pitches)
    Test.expect(width == '3-note chord', 'got width=' .. tostring(width))
    Test.expect(combo == nil, 'expected no unambiguous combo')
    Test.expect(opts ~= nil and #opts == 7, 'expected 7 options')
end)

Test.it('power chord (root+5th+octave-doubled-root) -> width 1-3, not 3-note chord', function()
    -- x x x 7 7 5: 3 physical pitches but only 2 pitch classes (root, 5th) --
    -- must agree with the reference table's "1-3" and with
    -- GuitarClassifyChordType's "Power chord", not fall into the physical-
    -- note-count-based 3-note bucket.
    local pitches = GuitarParseFretInput('x x x 7 7 5')
    local width, combo, opts = GuitarSuggestRBMapping(pitches)
    Test.expect(width == '1-3', 'got width=' .. tostring(width))
    Test.expect(combo == nil, 'expected no unambiguous combo')
    Test.expect(opts ~= nil and #opts == 3, 'expected 3 options (GY/RB/YO)')
end)

Test.it('3+ physical notes all the same pitch class -> no width suggestion', function()
    local width, combo, opts = GuitarSuggestRBMapping({ 40, 52, 64 })  -- E, E+12, E+24
    Test.expect(width == nil and combo == nil and opts == nil, 'expected no suggestion for a doubled single note')
end)

Test.it('perfect fourth (interval 5) reports both widths, not silently picked', function()
    local width, combo, opts = GuitarSuggestRBMapping({ 45, 50 })
    Test.expect(width == '1-2 or 1-3', 'got width=' .. tostring(width))
    Test.expect(combo == nil and opts == nil, 'expected no combo/options for the compound-ambiguous case')
end)

----------------------------------------------------------------------

Test.section('GuitarAnalyzeShape — combined pipeline')

Test.it('bundles classification and mapping into one result table', function()
    local pitches = GuitarParseFretInput('x x x 7 7 5')  -- Power chord
    local result = GuitarAnalyzeShape(pitches)
    Test.expect(result.type_name == 'Power chord', 'got type_name=' .. tostring(result.type_name))
    Test.expect(result.width == '1-3', 'got width=' .. tostring(result.width))
    Test.expect(#result.pitches == 3, 'expected 3 distinct pitches')
end)

----------------------------------------------------------------------

Test.section('GuitarShapeToPitches — tuning parameter')

Test.it('defaults to standard tuning', function()
    local pitches = GuitarShapeToPitches({ { str = 6, fret = 0 } })
    Test.expect(pitches[1] == GUITAR_TAB_OPEN[6], 'got ' .. tostring(pitches[1]))
end)

Test.it('drop D tuning only changes string 6', function()
    for str = 1, 5 do
        local std  = GuitarShapeToPitches({ { str = str, fret = 3 } }, GUITAR_TAB_OPEN)
        local drop = GuitarShapeToPitches({ { str = str, fret = 3 } }, GUITAR_TAB_OPEN_DROP_D)
        Test.expect(std[1] == drop[1], 'string ' .. str .. ' should be unaffected by drop D')
    end
    local std6  = GuitarShapeToPitches({ { str = 6, fret = 0 } }, GUITAR_TAB_OPEN)
    local drop6 = GuitarShapeToPitches({ { str = 6, fret = 0 } }, GUITAR_TAB_OPEN_DROP_D)
    Test.expect(std6[1] - drop6[1] == 2, 'drop D string 6 should be 2 semitones lower')
end)

----------------------------------------------------------------------

Test.section('GuitarAnalyzeShapeAllTunings')

Test.it('7 7 5: Standard Power chord A5, Drop D unrecognized -- 2 distinct entries', function()
    local results = GuitarAnalyzeShapeAllTunings('x x x 7 7 5')
    Test.expect(results ~= nil and #results == 2, 'expected 2 distinct entries')
    Test.expect(results[1].tuning_name == 'Standard', 'first entry should be Standard')
    Test.expect(results[1].analysis.type_name == 'Power chord', 'got ' .. tostring(results[1].analysis.type_name))
    Test.expect(results[2].tuning_name == 'Drop D', 'second entry should be Drop D')
    Test.expect(results[2].analysis.type_name:find('Unrecognized'), 'expected Drop D to be unrecognized here')
end)

Test.it('2 2 2: Standard Sus4 (inversion), Drop D Power chord -- both recognized, both shown', function()
    local results = GuitarAnalyzeShapeAllTunings('2 2 2')
    Test.expect(results ~= nil and #results == 2, 'expected 2 distinct entries')
    Test.expect(results[1].analysis.type_name == 'Sus4', 'got ' .. tostring(results[1].analysis.type_name))
    Test.expect(results[1].analysis.detail ~= nil, 'expected an inversion detail on the Standard result')
    Test.expect(results[2].analysis.type_name == 'Power chord', 'got ' .. tostring(results[2].analysis.type_name))
end)

Test.it('0 0 0: mirrors the open drop-D power chord example', function()
    local results = GuitarAnalyzeShapeAllTunings('0 0 0')
    Test.expect(results ~= nil and #results == 2, 'expected 2 distinct entries')
    Test.expect(results[2].tuning_name == 'Drop D', 'second entry should be Drop D')
    Test.expect(results[2].analysis.type_name == 'Power chord', 'got ' .. tostring(results[2].analysis.type_name))
end)

Test.it('shape not touching string 6 -> tunings agree, deduped to 1 entry', function()
    local results = GuitarAnalyzeShapeAllTunings('7 7 x x x x')  -- Perfect fourth, e/B strings
    Test.expect(results ~= nil and #results == 1, 'expected tunings to be deduplicated to 1 entry')
end)

Test.it('propagates parse errors unchanged', function()
    local results, err = GuitarAnalyzeShapeAllTunings('')
    Test.expect(results == nil and err == 'empty', 'expected nil, "empty"')
end)
