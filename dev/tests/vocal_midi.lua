-- MIDI fixture tests for the Vocal Helper.
--
-- Each test imports a real MIDI fixture, points S indices at the loaded tracks,
-- calls one action, asserts on S.status, then deletes the fixture tracks.

local _S0 = {}
for k, v in pairs(S) do _S0[k] = v end

local function reset()
    for k, v in pairs(_S0) do S[k] = v end
    S.status      = 'Ready.'
    S.last_result = nil
end

----------------------------------------------------------------------
-- Validation and lyrics - rb_vocal.mid
-- Track has vocal notes (pitch 36-84), phrase markers (pitch 105),
-- and type-5 lyric text events already authored.
----------------------------------------------------------------------
Test.section('Vocal validation - rb_vocal.mid')

Test.it('ValidatePhrases: checks phrase markers contain notes and reports', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    Test.expect(n > 0, 'rb_vocal.mid created no tracks')
    S.midi_idx = base  -- GetTrackList() lists all tracks in order; base == 0-based index
    ValidatePhrases()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ValidatePhrases did not update S.status')
    Test.expect(not S.status:find('^Error'), 'ValidatePhrases errored: ' .. S.status)
end)

Test.it('PhraseSimilarityAction: compares phrase content and reports similarity', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    Test.expect(n > 0, 'rb_vocal.mid created no tracks')
    S.midi_idx = base
    PhraseSimilarityAction()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'PhraseSimilarityAction did not update S.status')
    Test.expect(not S.status:find('^Error'), 'PhraseSimilarityAction errored: ' .. S.status)
end)

Test.it('AssignLyricsAction: reads lyrics.txt and attaches words to notes', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    Test.expect(n > 0, 'rb_vocal.mid created no tracks')
    S.midi_idx    = base
    S.lyrics_path = _FIXTURE_DIR .. 'lyrics.txt'
    AssignLyricsAction()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'AssignLyricsAction did not update S.status')
    Test.expect(not S.status:find('^Error'), 'AssignLyricsAction errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Phrases - rb_vocal.mid
----------------------------------------------------------------------
Test.section('Phrases - rb_vocal.mid')

local function CountPhraseMarkers(track_idx)
    local track = r.GetTrack(0, track_idx)
    local item, take = FindFirstMIDIItem(track)
    if not take then return 0 end
    local _, n = r.MIDI_CountEvts(take)
    local count = 0
    for i = 0, n - 1 do
        local ok, _, _, _, _, _, p = r.MIDI_GetNote(take, i)
        if ok and p == RB3_PHRASE_PITCH then count = count + 1 end
    end
    return count
end

-- Returns { {s, e}, ... } for every pitch-105 note on the track's take, plus
-- the take's own 1/32-note grid unit (NoteLenPPQ/GetTakePPQPerQN, both
-- global) - used to assert every phrase marker's start/end lands exactly on
-- the grid (the invariant a fractional-ppq version of the growth math broke).
local function CollectPhraseMarkerEdges(track_idx)
    local track = r.GetTrack(0, track_idx)
    local item, take = FindFirstMIDIItem(track)
    if not take then return {}, nil end
    local edges = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p == RB3_PHRASE_PITCH then
            edges[#edges + 1] = { s = sppq, e = eppq }
        end
    end
    local thirty2_ppq = NoteLenPPQ(GetTakePPQPerQN(take), 32)
    return edges, thirty2_ppq
end

-- Distance in ticks from ppq to the nearest multiple of grid (handles the
-- floating-point-modulo-near-grid wraparound case: e.g. -1e-9 % grid ==
-- grid - 1e-9, which is "on grid" too, not "a full grid unit off").
local function DistanceToGrid(ppq, grid)
    local rem = ppq % grid
    return math.min(rem, grid - rem)
end

Test.it('CreatePhrasesAction: happy path creates phrase markers after Assign lyrics', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    Test.expect(n > 0, 'rb_vocal.mid created no tracks')
    S.midi_idx    = base
    S.lyrics_path = _FIXTURE_DIR .. 'lyrics.txt'
    AssignLyricsAction()
    Test.expect(not S.status:find('^Error'), 'AssignLyricsAction errored: ' .. S.status)

    local lines = ParseLyricsLines(S.lyrics_path)
    CreatePhrasesAction()
    local phrase_count = CountPhraseMarkers(base)
    local edges, thirty2_ppq = CollectPhraseMarkerEdges(base)
    CleanupFixture(base)

    Test.expect(S.status ~= 'Ready.', 'CreatePhrasesAction did not update S.status')
    Test.expect(not S.status:find('^Error'), 'CreatePhrasesAction errored: ' .. S.status)
    Test.expect(phrase_count > 0, 'expected at least one phrase marker created')
    Test.expect(phrase_count <= #lines, 'phrase count should not exceed non-blank line count')

    local off_grid = 0
    for _, e in ipairs(edges) do
        if DistanceToGrid(e.s, thirty2_ppq) > 0.5 then off_grid = off_grid + 1 end
        if DistanceToGrid(e.e, thirty2_ppq) > 0.5 then off_grid = off_grid + 1 end
    end
    Test.expect(off_grid == 0, ('%d phrase-marker edge(s) not on the 1/32-note grid'):format(off_grid))
end)

Test.it('CreatePhrasesAction: aborts with zero notes written when lyrics.txt drifts', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    S.midi_idx    = base
    S.lyrics_path = _FIXTURE_DIR .. 'lyrics.txt'
    AssignLyricsAction()
    local before = CountPhraseMarkers(base)

    -- Different lyrics file - guaranteed to mismatch on word 1 against the
    -- lyric text AssignLyricsAction just wrote from the real lyrics.txt.
    S.lyrics_path = _FIXTURE_DIR .. 'lyrics_phrases_mismatch.txt'
    CreatePhrasesAction()
    local after = CountPhraseMarkers(base)
    CleanupFixture(base)

    Test.expect(S.status:find('^Error'), 'expected Error status on mismatch, got: ' .. S.status)
    Test.expect(after == before, 'phrase marker count must be unchanged on abort')
end)

Test.it('CreatePhrasesAction: reports no lyrics file selected, same as Assign lyrics', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    S.midi_idx    = base
    S.lyrics_path = ''
    CreatePhrasesAction()
    CleanupFixture(base)
    Test.expect(S.status == 'No lyrics file selected.', 'unexpected status: ' .. S.status)
end)

Test.it('CreatePhrasesAction: reports unprocessed lines when fewer notes than lyrics', function()
    reset()
    local base, n = LoadFixture('rb_vocal.mid')
    S.midi_idx    = base
    S.lyrics_path = _FIXTURE_DIR .. 'lyrics.txt'
    AssignLyricsAction()
    Test.expect(not S.status:find('^Error'), 'AssignLyricsAction errored: ' .. S.status)

    -- Delete the back half of the vocal-range notes so lyrics.txt has more
    -- lines than there are remaining notes to bracket - exercises the
    -- "excess lyrics" notice path without needing a dedicated fixture.
    local track = r.GetTrack(0, base)
    local item, take = FindFirstMIDIItem(track)
    local starts = {}
    local _, n_notes = r.MIDI_CountEvts(take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            starts[#starts + 1] = sppq
        end
    end
    table.sort(starts)
    local cutoff_ppq = starts[math.ceil(#starts / 2)]
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH and sppq >= cutoff_ppq then
            r.MIDI_DeleteNote(take, i)
        end
    end

    CreatePhrasesAction()
    CleanupFixture(base)

    Test.expect(not S.status:find('^Error'), 'CreatePhrasesAction errored: ' .. S.status)
    Test.expect(S.last_result and S.last_result:find('not processed'),
        'expected excess-lyrics notice in result')
end)

----------------------------------------------------------------------
-- Harmonies - rb_vocal_and_harm.mid
-- Contains PART VOCALS source and HARM1/HARM2/HARM3 destination tracks,
-- each with a MIDI item ready to receive generated harmony notes.
----------------------------------------------------------------------
Test.section('Harmonies - rb_vocal_and_harm.mid')

Test.it('HarmoniesAction: copies PART VOCALS to HARM1 in unison (mode 0)', function()
    reset()
    local base, n = LoadFixture('rb_vocal_and_harm.mid')
    Test.expect(n > 0, 'rb_vocal_and_harm.mid created no tracks')

    local src_idx  = FindFixtureTrack('PART VOCALS', base) or FindFixtureTrack('VOCALS', base)
    local dst1_idx = FindFixtureTrack('HARM1', base)
    Test.expect(src_idx  ~= nil, 'no PART VOCALS track found in rb_vocal_and_harm.mid')
    Test.expect(dst1_idx ~= nil, 'no HARM1 track found in rb_vocal_and_harm.mid')

    S.harm_src_idx      = src_idx
    S.harm_dst1_idx     = dst1_idx
    S.harm_dst1_enabled = true
    S.harm_dst1_mode    = 0  -- "Copy as-is": duplicates notes at same pitch
    S.harm_dst2_enabled = false
    S.harm_dst3_enabled = false

    HarmoniesAction()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'HarmoniesAction did not update S.status')
    Test.expect(not S.status:find('^Error'), 'HarmoniesAction errored: ' .. S.status)
end)

-- Vocal-range notes on a track's first MIDI item, as { s, e, pitch } sorted by s.
local function ReadVocalNotes(track_idx)
    local _, take = FindFirstMIDIItem(r.GetTrack(0, track_idx))
    if not take then return nil end
    local out = {}
    local _, nc = r.MIDI_CountEvts(take)
    for i = 0, nc - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            out[#out + 1] = {
                s     = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                e     = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                pitch = p,
            }
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out, take
end

local function PreserveModeIndex()
    for i, m in ipairs(HARM_MODES) do
        if m.preserve then return i - 1 end
    end
    return nil
end

Test.it('HarmoniesAction: preserve mode keeps destination pitches, takes source timing', function()
    reset()
    local base, n = LoadFixture('rb_vocal_and_harm.mid')
    Test.expect(n > 0, 'rb_vocal_and_harm.mid created no tracks')

    local src_idx  = FindFixtureTrack('PART VOCALS', base) or FindFixtureTrack('VOCALS', base)
    local dst1_idx = FindFixtureTrack('HARM1', base)
    Test.expect(src_idx  ~= nil, 'no PART VOCALS track found in rb_vocal_and_harm.mid')
    Test.expect(dst1_idx ~= nil, 'no HARM1 track found in rb_vocal_and_harm.mid')

    local preserve_mode = PreserveModeIndex()
    Test.expect(preserve_mode ~= nil, 'no preserve entry in HARM_MODES')

    local src_notes = ReadVocalNotes(src_idx)
    Test.expect(src_notes and #src_notes > 0, 'PART VOCALS has no vocal notes')

    -- Seed HARM1 with a distinctive pitch pattern at the source's own timings,
    -- so preserve mode has an unambiguous donor for every note.
    local _, dst_take = ReadVocalNotes(dst1_idx)
    Test.expect(dst_take ~= nil, 'no MIDI take on HARM1')
    local dnc = select(2, r.MIDI_CountEvts(dst_take))
    for i = dnc - 1, 0, -1 do r.MIDI_DeleteNote(dst_take, i) end

    local seeded, expected = {}, {}
    for i, sn in ipairs(src_notes) do
        expected[i] = 60 + (i % 5)   -- unrelated to the source pitches
        seeded[i]   = { s = sn.s, e = sn.e, pitch = expected[i] }
    end
    InsertNotes(dst_take, seeded, S.velocity)

    S.harm_src_idx      = src_idx
    S.harm_dst1_idx     = dst1_idx
    S.harm_dst1_enabled = true
    S.harm_dst1_mode    = preserve_mode
    S.harm_dst2_enabled = false
    S.harm_dst3_enabled = false

    HarmoniesAction()

    local got = ReadVocalNotes(dst1_idx)
    CleanupFixture(base)

    -- ResolvePreservedPitches bails with 'Range error on Destination N.', which
    -- does not start with 'Error' - check both, or an early bail-out shows up
    -- as a confusing pitch/timing failure instead of the abort it really is.
    Test.expect(not (S.status:find('^Error') or S.status:find('error')),
        'HarmoniesAction errored: ' .. S.status .. ' / ' .. tostring(S.last_result))
    Test.expect(got and #got == #src_notes,
        ('HARM1 should have %d notes, has %s'):format(#src_notes, got and #got or 'nil'))

    -- Report the first offender with its numbers - a bare true/false here says
    -- nothing about whether a failure is tick quantisation or a real shift.
    --
    -- Note ends are compared only where the source note has one. The fixtures
    -- are truncated excerpts of real charts, so their last few note-ons have no
    -- matching note-off (rb_vocal_and_harm.mid: pitch 105 at tick 22680 and the
    -- final vocal note at 22864, on every track; most other fixtures are the
    -- same). REAPER imports such a note with its end at ppq 0 - i.e. an end
    -- *before* its start - and MIDI_InsertNote clamps that to a minimum-length
    -- note on the way out, so the copy legitimately does not reproduce a
    -- nonsense end. Starts are still checked for every note.
    local pitch_bad, time_bad, max_dt, ends_checked = nil, nil, 0, 0
    for i = 1, #src_notes do
        local g, sn = got[i], src_notes[i]
        if not g then
            pitch_bad = pitch_bad or ('note %d missing'):format(i)
            break
        end
        if not pitch_bad and g.pitch ~= expected[i] then
            pitch_bad = ('note %d: got pitch %d, expected %d'):format(i, g.pitch, expected[i])
        end
        local ds  = g.s - sn.s
        local de  = sn.e > sn.s and (g.e - sn.e) or 0
        if sn.e > sn.s then ends_checked = ends_checked + 1 end
        max_dt = math.max(max_dt, math.abs(ds), math.abs(de))
        if not time_bad and (math.abs(ds) > 0.002 or math.abs(de) > 0.002) then
            time_bad = ('note %d: start %+.4fs / end %+.4fs off source '
                .. '(got %.4f-%.4f, source %.4f-%.4f)')
                :format(i, ds, de, g.s, g.e, sn.s, sn.e)
        end
    end
    Test.expect(not pitch_bad, 'HARM1 kept its own pitches - ' .. tostring(pitch_bad))
    Test.expect(not time_bad,
        ('HARM1 note starts/ends match the source - %s (max delta %.4fs over %d notes)')
        :format(tostring(time_bad), max_dt, #src_notes))
    Test.expect(ends_checked >= #src_notes - 1,
        ('only %d of %d source notes had a usable end - fixture more truncated than expected')
        :format(ends_checked, #src_notes))
    Test.expect(S.last_result and S.last_result:find('Existing pitches applied', 1, true),
        'result panel reports the preserve breakdown')
end)
