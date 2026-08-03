-- Algorithm unit tests for vocal helper pure-Lua functions:
-- EditDistance, NearestScalePitch, DiatonicThirdOffset, ResolvePreservedPitches,
-- ScoreNotes.
-- HARM_SCALE and the RB3_* pitch constants must be loaded (from vocal
-- defaults.lua) before running these tests.

----------------------------------------------------------------------
Test.section('EditDistance')

Test.it('identical sequences → 0', function()
    Test.expect(EditDistance({60,62,64}, {60,62,64}) == 0, 'identical → 0')
end)

Test.it('one substitution → 1', function()
    Test.expect(EditDistance({60,62,64}, {60,63,64}) == 1, 'one substitution → 1')
end)

Test.it('one insertion → 1', function()
    Test.expect(EditDistance({60,62}, {60,61,62}) == 1, 'one insertion → 1')
end)

Test.it('empty vs non-empty → length of non-empty', function()
    Test.expect(EditDistance({}, {60,62,64}) == 3,  'empty vs 3 → 3')
    Test.expect(EditDistance({60}, {}) == 1,         '1 vs empty → 1')
end)

Test.it('all-substitution same-length sequences → length', function()
    Test.expect(EditDistance({60,62,64}, {61,63,65}) == 3, 'all different → 3')
end)

----------------------------------------------------------------------
Test.section('NearestScalePitch')

-- root=0 (C), quality=0 (major): HARM_SCALE.major = {0,2,4,5,7,9,11}

Test.it('note already on scale degree: unchanged, dist=0', function()
    local p, d = NearestScalePitch(60, 0, 0)  -- C in C major
    Test.expect(p == 60, 'C on C major stays C')
    Test.expect(d == 0,  'distance 0')
end)

Test.it('D# (63) in C major: tie between D(62) and E(64), lower pitch wins → D', function()
    local p, d = NearestScalePitch(63, 0, 0)
    Test.expect(p == 62 and d == 1, 'D# → D (dist 1)')
end)

Test.it('C# (61) in C major: tie between C(60) and D(62), lower pitch wins → C', function()
    local p, d = NearestScalePitch(61, 0, 0)
    Test.expect(p == 60 and d == 1, 'C# → C (dist 1)')
end)

Test.it('Bb (70) in C minor: on scale degree, dist=0', function()
    -- C minor: {0,2,3,5,7,8,10}; pc=10=Bb is scale degree 7 → dist=0
    local p, d = NearestScalePitch(70, 0, 1)
    Test.expect(d == 0, 'Bb is on C minor scale (dist 0)')
    Test.expect(p == 70, 'pitch unchanged')
end)

Test.it('F# (66) in C major: equidistant from F(65) and G(67), lower wins → F', function()
    local p, d = NearestScalePitch(66, 0, 0)
    Test.expect(p == 65 and d == 1, 'F# → F (dist 1)')
end)

----------------------------------------------------------------------
Test.section('DiatonicThirdOffset')

-- root=0 (C), quality=0 (major): C major = {0,2,4,5,7,9,11}

Test.it('C (60) in C major, 3rd above → +4 semitones (E)', function()
    -- scale deg 1 (C) + 2 = deg 3 (E); E-C = 4 semitones
    local off = DiatonicThirdOffset(60, 0, 0, 1)
    Test.expect(off == 4, 'C→E diatonic 3rd above = +4')
end)

Test.it('E (64) in C major, 3rd below → -4 semitones (C)', function()
    -- scale deg 3 (E) - 2 = deg 1 (C); C-E = -4 semitones
    local off = DiatonicThirdOffset(64, 0, 0, -1)
    Test.expect(off == -4, 'E→C diatonic 3rd below = -4')
end)

Test.it('D (62) in C major, 3rd above → +3 semitones (F)', function()
    -- scale deg 2 (D) + 2 = deg 4 (F); F-D = 3 semitones
    local off = DiatonicThirdOffset(62, 0, 0, 1)
    Test.expect(off == 3, 'D→F diatonic 3rd above = +3')
end)

Test.it('G (67) in C major, 3rd above → +4 semitones (B)', function()
    -- scale deg 5 (G) + 2 = deg 7 (B); B-G = 4 semitones
    local off = DiatonicThirdOffset(67, 0, 0, 1)
    Test.expect(off == 4, 'G→B diatonic 3rd above = +4')
end)

----------------------------------------------------------------------
Test.section('ResolvePreservedPitches')

-- Helpers: a 1-second window on every note unless a test says otherwise.
local function windows_of(new_notes, w)
    local out = {}
    for i = 1, #new_notes do out[i] = w or 1.0 end
    return out
end

local function categories(assigned)
    local out = {}
    for i, a in ipairs(assigned) do out[i] = a.category end
    return table.concat(out, ',')
end

-- Calls ResolvePreservedPitches and fails the test if it errored, so the cases
-- below can index the result directly.
local function resolve_ok(new_notes, old_notes, w)
    local a, c = ResolvePreservedPitches(new_notes, old_notes, w)
    Test.expect(a ~= nil, 'unexpected error: ' .. tostring(c))
    return a or {}, c or { existing = -1, closest = -1, carried = -1, source = -1 }
end

Test.it('overlapping destination note donates its pitch', function()
    local new_notes = { { s = 0.0, e = 1.0, src_pitch = 60 } }
    local old_notes = { { s = 0.0, e = 1.0, pitch = 67 } }
    local a, c = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a[1].pitch == 67, 'kept destination pitch 67, got ' .. tostring(a[1].pitch))
    Test.expect(a[1].category == 'existing', 'category existing, got ' .. a[1].category)
    Test.expect(c.existing == 1, 'existing count 1')
end)

Test.it('largest overlap wins when two destination notes overlap', function()
    local new_notes = { { s = 0.9, e = 2.0, src_pitch = 60 } }
    local old_notes = { { s = 0.0, e = 1.0, pitch = 62 },   -- 0.1 s overlap
                        { s = 1.0, e = 2.0, pitch = 71 } }  -- 1.0 s overlap
    local a = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a[1].pitch == 71, 'largest overlap donates, got ' .. tostring(a[1].pitch))
end)

Test.it('note nudged clear of its donor takes the nearest pitch in window', function()
    local new_notes = { { s = 2.0, e = 2.4, src_pitch = 60 } }
    local old_notes = { { s = 1.5, e = 1.9, pitch = 65 } }   -- 0.5 s away, no overlap
    local a, c = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a[1].pitch == 65, 'nearest pitch 65, got ' .. tostring(a[1].pitch))
    Test.expect(a[1].category == 'closest', 'category closest, got ' .. a[1].category)
    Test.expect(c.closest == 1, 'closest count 1')
end)

Test.it('no destination note inside the window falls back to the source pitch', function()
    local new_notes = { { s = 10.0, e = 10.4, src_pitch = 60 } }
    local old_notes = { { s = 1.5, e = 1.9, pitch = 65 } }
    local a, c = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a[1].pitch == 60, 'source pitch 60 copied as-is, got ' .. tostring(a[1].pitch))
    Test.expect(a[1].category == 'source', 'category source, got ' .. a[1].category)
    Test.expect(c.source == 1, 'source count 1')
end)

Test.it('empty destination puts every note in the source category', function()
    local new_notes = { { s = 0.0, e = 0.5, src_pitch = 60 },
                        { s = 1.0, e = 1.5, src_pitch = 62 } }
    local a, c = resolve_ok(new_notes, {}, windows_of(new_notes))
    Test.expect(c.source == 2, 'both notes fall back, got ' .. c.source)
    Test.expect(a[1].pitch == 60 and a[2].pitch == 62, 'source pitches copied unchanged')
end)

Test.it('note split for a slide carries the source interval onto the second half', function()
    -- Destination held one note; the source has since been split, rising +3.
    local new_notes = { { s = 0.0, e = 0.5, src_pitch = 57 },
                        { s = 0.5, e = 1.0, src_pitch = 60 } }
    local old_notes = { { s = 0.0, e = 1.0, pitch = 64 } }
    local a, c = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a[1].pitch == 64, 'first half keeps 64, got ' .. tostring(a[1].pitch))
    Test.expect(a[2].pitch == 67, 'second half = 64 + 3, got ' .. tostring(a[2].pitch))
    Test.expect(categories(a) == 'existing,carried',
        'categories existing,carried - got ' .. categories(a))
    Test.expect(c.existing == 1 and c.carried == 1, 'one existing, one carried')
end)

Test.it('a carried pitch outside the vocal range is an error, not a clamp', function()
    local new_notes = { { s = 0.0, e = 0.5, src_pitch = 60 },
                        { s = 0.5, e = 1.0, src_pitch = 72 } }   -- +12
    local old_notes = { { s = 0.0, e = 1.0, pitch = RB3_MAX_PITCH } }
    local a, err = ResolvePreservedPitches(new_notes, old_notes, windows_of(new_notes))
    Test.expect(a == nil, 'expected nil on out-of-range carried pitch')
    Test.expect(type(err) == 'string' and #err > 0, 'expected an error string')
end)

Test.it('a note with no donor breaks the run, so the next note is not carried', function()
    local new_notes = { { s = 0.0, e = 0.5, src_pitch = 57 },   -- donor
                        { s = 5.0, e = 5.5, src_pitch = 60 },   -- nothing near
                        { s = 0.5, e = 1.0, src_pitch = 62 } }  -- same donor as #1
    -- Tight windows so note 2 finds nothing.
    local old_notes = { { s = 0.0, e = 1.0, pitch = 64 } }
    local a = resolve_ok(new_notes, old_notes, windows_of(new_notes, 0.2))
    Test.expect(categories(a) == 'existing,source,existing',
        'run broken by the orphan note - got ' .. categories(a))
    Test.expect(a[3].pitch == 64, 'note 3 starts a fresh run at 64, got ' .. tostring(a[3].pitch))
end)

Test.it('the four category counts sum to the number of notes', function()
    local new_notes = { { s = 0.0, e = 0.5, src_pitch = 57 },
                        { s = 0.5, e = 1.0, src_pitch = 59 },
                        { s = 2.2, e = 2.6, src_pitch = 60 },
                        { s = 9.0, e = 9.5, src_pitch = 62 } }
    local old_notes = { { s = 0.0, e = 1.0, pitch = 64 },
                        { s = 1.5, e = 2.0, pitch = 66 } }
    local a, c = resolve_ok(new_notes, old_notes, windows_of(new_notes))
    local total = c.existing + c.closest + c.carried + c.source
    Test.expect(total == #new_notes,
        ('counts sum to %d, expected %d'):format(total, #new_notes))
    Test.expect(#a == #new_notes, 'one assignment per note')
end)

----------------------------------------------------------------------
Test.section('ScoreNotes')

Test.it('identical detection and reference → score 0', function()
    local ref = { {s=0.0,e=0.5}, {s=1.0,e=1.5} }
    local det = { {s=0.0,e=0.5}, {s=1.0,e=1.5} }
    Test.expect(ScoreNotes(det, ref).score == 0, 'perfect match → score 0')
end)

Test.it('empty detection (all misses) → penalty >= 1000 per miss', function()
    local ref = { {s=0.0,e=0.5} }
    Test.expect(ScoreNotes({}, ref).score >= 1000, '1 miss → score >= 1000')
end)

Test.it('empty reference (all extras) → penalty >= 1000 per extra', function()
    local det = { {s=0.0,e=0.5} }
    Test.expect(ScoreNotes(det, {}).score >= 1000, '1 extra → score >= 1000')
end)

----------------------------------------------------------------------
-- lyrics_phrases.txt:
--   [Verse]
--   Hello world
--   Second line here
--
--   [Chorus]
--   One more
-- -> flat words: Hello(1) world(2) Second(3) line(4) here(5) One(6) more(7)
Test.section('ParseLyricsLines')

Test.it('bracket-only and blank lines are dropped; 3 non-blank lines remain', function()
    local lines, flat = ParseLyricsLines(_FIXTURE_DIR .. 'lyrics_phrases.txt')
    Test.expect(lines ~= nil, 'parses without error')
    Test.expect(#lines == 3, ('expected 3 lines, got %d'):format(#lines))
    Test.expect(#flat == 7, ('expected 7 words, got %d'):format(#flat))
end)

Test.it('start_idx/end_idx match hand-counted word positions', function()
    local lines = ParseLyricsLines(_FIXTURE_DIR .. 'lyrics_phrases.txt')
    Test.expect(lines[1].start_idx == 1 and lines[1].end_idx == 2, 'line 1 = words 1-2')
    Test.expect(lines[2].start_idx == 3 and lines[2].end_idx == 5, 'line 2 = words 3-5')
    Test.expect(lines[3].start_idx == 6 and lines[3].end_idx == 7, 'line 3 = words 6-7')
end)

Test.it('flat word list matches ParseLyricsFile exactly (load-bearing invariant)', function()
    local _, flat = ParseLyricsLines(_FIXTURE_DIR .. 'lyrics_phrases.txt')
    local words = ParseLyricsFile(_FIXTURE_DIR .. 'lyrics_phrases.txt')
    Test.expect(#flat == #words, 'same word count')
    local same = true
    for i = 1, #flat do
        if flat[i] ~= words[i] then same = false end
    end
    Test.expect(same, 'same word order/content, index for index')
end)

Test.it('file with only bracket markers → nil, error', function()
    local lines, err = ParseLyricsLines(_FIXTURE_DIR .. 'lyrics_phrases_empty.txt')
    Test.expect(lines == nil, 'no lines returned')
    Test.expect(type(err) == 'string' and #err > 0, 'error message returned')
end)

Test.it('detection outside 0.25s tolerance: treated as miss + extra', function()
    -- ref onset at 0.0; det onset at 0.3s offset > MATCH_TOLERANCE_S=0.25 → no match
    local ref = { {s=0.0, e=0.5} }
    local det = { {s=0.3, e=0.8} }
    Test.expect(ScoreNotes(det, ref).score >= 2000, '1 miss + 1 extra = penalty >= 2000')
end)

Test.it('detection within 0.25s tolerance: matched, score < 1000', function()
    local ref = { {s=0.0, e=0.5} }
    local det = { {s=0.1, e=0.6} }  -- 0.1s offset < 0.25 tolerance
    Test.expect(ScoreNotes(det, ref).score < 1000, 'matched onset → score < 1000')
end)
