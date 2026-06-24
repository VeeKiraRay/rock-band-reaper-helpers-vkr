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
