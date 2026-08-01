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
-- Validation and lyrics — rb_vocal.mid
-- Track has vocal notes (pitch 36-84), phrase markers (pitch 105),
-- and type-5 lyric text events already authored.
----------------------------------------------------------------------
Test.section('Vocal validation — rb_vocal.mid')

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
-- Phrases — rb_vocal.mid
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
-- Harmonies — rb_vocal_and_harm.mid
-- Contains PART VOCALS source and HARM1/HARM2/HARM3 destination tracks,
-- each with a MIDI item ready to receive generated harmony notes.
----------------------------------------------------------------------
Test.section('Harmonies — rb_vocal_and_harm.mid')

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
