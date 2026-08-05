-- MIDI fixture tests for the General Helper.
--
-- Each test imports a real MIDI fixture, points S indices at the loaded tracks,
-- calls one action, asserts on S.status, then deletes the fixture tracks.
-- Actions that have preview mode are run in preview so nothing is written permanently.

local _S0 = {}
for k, v in pairs(S) do _S0[k] = v end

local function reset()
    for k, v in pairs(_S0) do S[k] = v end
    S.status      = 'Ready.'
    S.last_result = nil
end

----------------------------------------------------------------------
-- ConvertDrums - external_drums.mid (standard GM drum notation)
----------------------------------------------------------------------
Test.section('ConvertDrums - GM drums fixture')

Test.it('preview: reads source notes and reports lane counts', function()
    reset()
    local base, n = LoadFixture('external_drums.mid')
    Test.expect(n > 0, 'external_drums.mid created no tracks')
    local tgt = CreateEmptyFixtureTrack('PART DRUMS')
    S.mc_drum_src_idx = base
    S.mc_drum_tgt_idx = tgt
    S.mc_drum_preview = true
    ConvertDrums()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
    Test.expect(S.status:find('%d'), 'expected note count in status')
end)

----------------------------------------------------------------------
-- ConvertGuitar - external_guitar.mid (any pitched MIDI)
----------------------------------------------------------------------
Test.section('ConvertGuitar - external guitar fixture')

Test.it('preview: reads source notes and reports gem assignments', function()
    reset()
    local base, n = LoadFixture('external_guitar.mid')
    Test.expect(n > 0, 'external_guitar.mid created no tracks')
    local tgt = CreateEmptyFixtureTrack('PART GUITAR')
    S.mc_gtr_src_idx  = base
    S.mc_gtr_tgt_idx  = tgt
    S.mc_gtr_workflow = 0  -- 0 = preview
    ConvertGuitar()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
end)

----------------------------------------------------------------------
-- Piano source actions - all share mc_keys_src_idx from external_piano.mid
----------------------------------------------------------------------
Test.section('Piano → Keys - external_piano.mid')

Test.it('SplitHands preview: partitions notes by pitch into RH and LH', function()
    reset()
    local base, n = LoadFixture('external_piano.mid')
    Test.expect(n > 0, 'external_piano.mid created no tracks')
    local rh = CreateEmptyFixtureTrack('KEYS RH')
    S.mc_keys_src_idx    = base
    S.mc_keys_rh_tgt_idx = rh
    S.mc_keys_lh_tgt_idx = -1
    S.mc_keys_preview    = true
    SplitHands()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
end)

Test.it('ConvertPianoToProKeys preview: octave-shifts notes into C2-C4', function()
    reset()
    local base, n = LoadFixture('external_piano.mid')
    Test.expect(n > 0, 'external_piano.mid created no tracks')
    local tgt = CreateEmptyFixtureTrack('PART REAL_KEYS_X')
    S.mc_keys_src_idx    = base
    S.mc_pk_conv_tgt_idx = tgt
    S.mc_keys_preview    = true
    ConvertPianoToProKeys()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
end)

Test.it('ConvertKeys5 preview: assigns 5-lane gem positions (96-100)', function()
    reset()
    local base, n = LoadFixture('external_piano.mid')
    Test.expect(n > 0, 'external_piano.mid created no tracks')
    local tgt = CreateEmptyFixtureTrack('PART KEYS')
    S.mc_keys_src_idx = base
    S.mc_5k_tgt_idx   = tgt
    S.mc_keys_preview = true
    ConvertKeys5()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
end)

----------------------------------------------------------------------
-- ValidateGuitar - rb_guitar.mid (RB gem pitches 96-100 already authored)
----------------------------------------------------------------------
Test.section('ValidateGuitar - RB guitar fixture')

Test.it('reads RB guitar gems and reports validation result', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    Test.expect(n > 0, 'rb_guitar.mid created no tracks')
    S.mc_gtr_tgt_idx = base
    ValidateGuitar()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ValidateGuitar did not update S.status')
    Test.expect(not S.status:find('^Error'), 'ValidateGuitar errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Pro Keys - rb_pro_keys.mid (separate tracks per difficulty + animation)
----------------------------------------------------------------------
Test.section('Pro Keys - rb_pro_keys.mid')

Test.it('ConvertProKeys preview: copies Expert C2-C4 notes to animation track', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    Test.expect(n > 0, 'rb_pro_keys.mid created no tracks')
    local x_idx   = FindFixtureTrack('REAL_KEYS_X', base)
    Test.expect(x_idx ~= nil, 'no PART REAL_KEYS_X track found in rb_pro_keys.mid')
    local anim_rh = FindFixtureTrack('ANIM_RH', base) or FindFixtureTrack('ANIM RH', base)
                    or CreateEmptyFixtureTrack('KEYS_ANIM_RH')
    S.mc_keys_pk_src_idx = x_idx
    S.mc_keys_rh_tgt_idx = anim_rh
    S.mc_keys_lh_tgt_idx = -1
    S.mc_keys_preview    = true
    ConvertProKeys()
    CleanupFixture(base)
    Test.expect(S.status:find('preview'), 'expected "preview" in status, got: ' .. S.status)
end)

Test.it('CopyProKeysDiff H: copies Expert notes onto the Hard track', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    Test.expect(n > 0, 'rb_pro_keys.mid created no tracks')
    S.diff_pk_x_idx = FindFixtureTrack('REAL_KEYS_X', base)
    S.diff_pk_h_idx = FindFixtureTrack('REAL_KEYS_H', base)
    Test.expect(S.diff_pk_x_idx ~= nil, 'no PART REAL_KEYS_X track found')
    Test.expect(S.diff_pk_h_idx ~= nil, 'no PART REAL_KEYS_H track found')
    CopyProKeysDiff('H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyProKeysDiff(H) errored: ' .. S.status)
end)

Test.it('ValidateProKeysDiff X: validates Expert against RBN rules', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    local x_idx = FindFixtureTrack('REAL_KEYS_X', base)
    Test.expect(x_idx ~= nil, 'no PART REAL_KEYS_X track found')
    S.diff_pk_x_idx = x_idx
    ValidateProKeysDiff('X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateProKeysDiff(X) errored: ' .. S.status)
end)

Test.it('ValidateProKeysDiff H: runs the cross-difficulty progression check vs Expert', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    Test.expect(n > 0, 'rb_pro_keys.mid created no tracks')
    S.diff_pk_x_idx = FindFixtureTrack('REAL_KEYS_X', base)
    S.diff_pk_h_idx = FindFixtureTrack('REAL_KEYS_H', base)
    ValidateProKeysDiff('H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateProKeysDiff(H) errored: ' .. S.status)
end)

Test.it('ValidateAllProKeys: validates all four difficulty tracks', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    Test.expect(n > 0, 'rb_pro_keys.mid created no tracks')
    S.diff_pk_x_idx = FindFixtureTrack('REAL_KEYS_X', base)
    S.diff_pk_h_idx = FindFixtureTrack('REAL_KEYS_H', base)
    S.diff_pk_m_idx = FindFixtureTrack('REAL_KEYS_M', base)
    S.diff_pk_e_idx = FindFixtureTrack('REAL_KEYS_E', base)
    ValidateAllProKeys()
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateAllProKeys errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- 5-Lane Keys - rb_keys.mid (single track, all difficulties by pitch range)
-- Expert 96-100 | Hard 84-88 | Medium 72-75 | Easy 60-62
----------------------------------------------------------------------
Test.section('5-Lane Keys - rb_keys.mid')

Test.it('CopyKeys5Diff H: copies Expert notes onto the Hard range', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    Test.expect(n > 0, 'rb_keys.mid created no tracks')
    S.diff_5k_idx = base
    CopyKeys5Diff('H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyKeys5Diff(H) errored: ' .. S.status)
end)

Test.it('CopyKeys5Diff M: copies Hard notes onto Medium, exercising color compression', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    Test.expect(n > 0, 'rb_keys.mid created no tracks')
    S.diff_5k_idx = base
    CopyKeys5Diff('M', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyKeys5Diff(M) errored: ' .. S.status)
end)

Test.it('CopyKeys5Diff H: reduces using Pro Keys Hard as a guide', function()
    reset()
    local keys_base, keys_n = LoadFixture('rb_keys.mid')
    Test.expect(keys_n > 0, 'rb_keys.mid created no tracks')
    local pk_base, pk_n = LoadFixture('rb_pro_keys.mid')
    Test.expect(pk_n > 0, 'rb_pro_keys.mid created no tracks')
    local pk_h_idx = FindFixtureTrack('REAL_KEYS_H', pk_base)
    Test.expect(pk_h_idx ~= nil, 'no PART REAL_KEYS_H track found in rb_pro_keys.mid')
    S.diff_5k_idx       = keys_base
    S.diff_pk_h_idx     = pk_h_idx
    S.diff_5k_pk_reduce = true
    CopyKeys5Diff('H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(keys_base)  -- removes both fixtures' tracks (keys_base..end)
    Test.expect(not S.status:find('^Error'), 'CopyKeys5Diff(H) with Pro Keys reduction errored: ' .. S.status)
end)

Test.it('ValidateKeys5Diff X: validates Expert pitch range (96-100)', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    S.diff_5k_idx = base
    ValidateKeys5Diff('X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateKeys5Diff(X) errored: ' .. S.status)
end)

Test.it('ValidateKeys5Diff H: runs the cross-difficulty progression check vs Expert', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    S.diff_5k_idx = base
    ValidateKeys5Diff('H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateKeys5Diff(H) errored: ' .. S.status)
end)

Test.it('ValidateAllKeys5: validates all four difficulty pitch ranges', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    S.diff_5k_idx = base
    ValidateAllKeys5()
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateAllKeys5 errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Guitar/Bass - rb_guitar.mid / rb_bass.mid (single track, all difficulties
-- by pitch range, same shape as rb_keys.mid)
-- Expert 96-100 | Hard 84-88 | Medium 72-75 | Easy 60-62
----------------------------------------------------------------------
Test.section('Guitar/Bass difficulty - rb_guitar.mid / rb_bass.mid')

Test.it('CopyGtrBassDiff gtr H: copies Expert notes onto the Hard range', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    Test.expect(n > 0, 'rb_guitar.mid created no tracks')
    S.diff_gtr_idx = base
    CopyGtrBassDiff('gtr', 'H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyGtrBassDiff(gtr, H) errored: ' .. S.status)
end)

Test.it('ValidateGtrBassDiff gtr X: validates Expert pitch range (96-100)', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    S.diff_gtr_idx = base
    ValidateGtrBassDiff('gtr', 'X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateGtrBassDiff(gtr, X) errored: ' .. S.status)
end)

Test.it('ValidateGtrBassDiff gtr H: runs the cross-difficulty progression check vs Expert', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    S.diff_gtr_idx = base
    ValidateGtrBassDiff('gtr', 'H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateGtrBassDiff(gtr, H) errored: ' .. S.status)
end)

Test.it('ValidateAllGtrBass gtr: validates all four difficulty pitch ranges', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    S.diff_gtr_idx = base
    ValidateAllGtrBass('gtr')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateAllGtrBass(gtr) errored: ' .. S.status)
end)

Test.it('CopyGtrBassDiff bass H: copies Expert notes onto the Hard range', function()
    reset()
    local base, n = LoadFixture('rb_bass.mid')
    Test.expect(n > 0, 'rb_bass.mid created no tracks')
    S.diff_bass_idx = base
    CopyGtrBassDiff('bass', 'H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyGtrBassDiff(bass, H) errored: ' .. S.status)
end)

Test.it('CopyGtrBassDiff gtr M: copies Hard notes onto Medium, exercising color compression', function()
    reset()
    local base, n = LoadFixture('rb_guitar.mid')
    Test.expect(n > 0, 'rb_guitar.mid created no tracks')
    S.diff_gtr_idx = base
    CopyGtrBassDiff('gtr', 'M', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyGtrBassDiff(gtr, M) errored: ' .. S.status)
end)

Test.it('ValidateGtrBassDiff bass X: validates Expert pitch range (96-100)', function()
    reset()
    local base, n = LoadFixture('rb_bass.mid')
    S.diff_bass_idx = base
    ValidateGtrBassDiff('bass', 'X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateGtrBassDiff(bass, X) errored: ' .. S.status)
end)

Test.it('ValidateGtrBassDiff bass H: runs the cross-difficulty progression check vs Expert', function()
    reset()
    local base, n = LoadFixture('rb_bass.mid')
    S.diff_bass_idx = base
    ValidateGtrBassDiff('bass', 'H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateGtrBassDiff(bass, H) errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Drums difficulty - rb_drums.mid (single track, all difficulties by
-- pitch range, same shape as rb_keys.mid)
-- Expert 96-100 | Hard 84-88 | Medium 72-76 | Easy 60-64
----------------------------------------------------------------------
Test.section('Drums difficulty - rb_drums.mid')

Test.it('CopyDrumsDiff H: copies Expert notes onto the Hard range', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    Test.expect(n > 0, 'rb_drums.mid created no tracks')
    S.diff_drums_idx = base
    CopyDrumsDiff('H', true)  -- force: skip the overwrite-confirmation popup for this test
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'CopyDrumsDiff(H) errored: ' .. S.status)
end)

Test.it('ValidateDrumsDiff X: validates Expert pitch range (96-100)', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    S.diff_drums_idx = base
    ValidateDrumsDiff('X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateDrumsDiff(X) errored: ' .. S.status)
end)

Test.it('ValidateDrumsDiff H: runs the cross-difficulty progression check vs Expert (also exercises the roll/trill velocity check)', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    S.diff_drums_idx = base
    ValidateDrumsDiff('H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateDrumsDiff(H) errored: ' .. S.status)
end)

Test.it('ValidateAllDrums: validates all four difficulty pitch ranges', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    S.diff_drums_idx = base
    ValidateAllDrums()
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateAllDrums errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Pattern Replace difficulty filter - GetPatternPitchRange + SetSearchPattern
----------------------------------------------------------------------
Test.section('Pattern Replace difficulty filter')

Test.it('GetPatternPitchRange resolves tiered ranges for PART DRUMS/GUITAR/BASS/KEYS', function()
    reset()
    local expected = {
        [0] = { 60, 100 }, [1] = { 96, 100 }, [2] = { 84, 88 }, [3] = { 72, 76 }, [4] = { 60, 64 },
    }
    for _, tn in ipairs({ 'PART DRUMS', 'PART GUITAR', 'PART BASS', 'PART KEYS' }) do
        for diff_idx, exp in pairs(expected) do
            local lo, hi = GetPatternPitchRange(tn, diff_idx)
            Test.expect(lo == exp[1] and hi == exp[2],
                ('%s diff %d: expected %d-%d, got %d-%d'):format(tn, diff_idx, exp[1], exp[2], lo, hi))
        end
    end
end)

Test.it('GetPatternPitchRange uses a fixed 36-84 range for vocal/harmony tracks regardless of Difficulty', function()
    reset()
    for _, tn in ipairs({ 'PART VOCALS', 'HARM1', 'HARM2', 'HARM3' }) do
        for diff_idx = 0, 4 do
            local lo, hi = GetPatternPitchRange(tn, diff_idx)
            Test.expect(lo == 36 and hi == 84,
                ('%s diff %d: expected 36-84, got %d-%d'):format(tn, diff_idx, lo, hi))
        end
    end
end)

Test.it('GetPatternPitchRange uses a fixed 48-72 range for PART REAL_KEYS*/PART KEYS_ANIM* tracks regardless of Difficulty', function()
    reset()
    for _, tn in ipairs({ 'PART REAL_KEYS_X', 'PART REAL_KEYS_H', 'PART KEYS_ANIM_RH', 'PART KEYS_ANIM_LH' }) do
        for diff_idx = 0, 4 do
            local lo, hi = GetPatternPitchRange(tn, diff_idx)
            Test.expect(lo == 48 and hi == 72,
                ('%s diff %d: expected 48-72, got %d-%d'):format(tn, diff_idx, lo, hi))
        end
    end
end)

Test.it('GetPatternPitchRange has no filtering for unrecognized track names', function()
    reset()
    local lo, hi = GetPatternPitchRange('SOME OTHER TRACK', 2)
    Test.expect(lo == 0 and hi == 127, ('expected 0-127, got %d-%d'):format(lo, hi))
end)

Test.it('SetSearchPattern restricts captured notes to the selected tier on PART DRUMS (Hard)', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    Test.expect(n > 0, 'rb_drums.mid created no tracks')
    local track = r.GetTrack(0, base)
    -- rb_drums.mid carries two SMF track-name events (conductor "rb_drums",
    -- then "PART DRUMS"); REAPER's import collapses them to one track and
    -- keeps the first, so the fixture lands named "rb_drums". Rename to match
    -- the real-world precondition (an already-correctly-named PART DRUMS
    -- track) that GetPatternPitchRange's tier lookup depends on.
    r.GetSetMediaTrackInfo_String(track, 'P_NAME', 'PART DRUMS', true)
    local item = FindFirstMIDIItem(track)
    Test.expect(item ~= nil, 'no MIDI item on rb_drums.mid track')
    local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    r.GetSet_LoopTimeRange(true, false, pos, pos + len, false)
    S.mr_midi_src_idx = base
    S.mr_diff_idx     = 2  -- Hard
    SetSearchPattern()
    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
    CleanupFixture(base)
    Test.expect(S.mr_search_notes ~= nil and #S.mr_search_notes > 0,
        'expected at least one Hard-tier note captured from rb_drums.mid')
    for _, note in ipairs(S.mr_search_notes) do
        Test.expect(note.pitch >= 84 and note.pitch <= 88,
            'note pitch ' .. note.pitch .. ' outside Hard range 84-88')
    end
end)

Test.it('SetSearchPattern with Difficulty=All spans every tier on PART DRUMS', function()
    reset()
    local base, n = LoadFixture('rb_drums.mid')
    Test.expect(n > 0, 'rb_drums.mid created no tracks')
    local track = r.GetTrack(0, base)
    -- See the Hard-tier test above: rename past the conductor-track name
    -- REAPER's import keeps by default.
    r.GetSetMediaTrackInfo_String(track, 'P_NAME', 'PART DRUMS', true)
    local item = FindFirstMIDIItem(track)
    Test.expect(item ~= nil, 'no MIDI item on rb_drums.mid track')
    local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    r.GetSet_LoopTimeRange(true, false, pos, pos + len, false)
    S.mr_midi_src_idx = base
    S.mr_diff_idx     = 0  -- All
    SetSearchPattern()
    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
    CleanupFixture(base)
    Test.expect(S.mr_search_notes ~= nil and #S.mr_search_notes > 0,
        'expected notes captured with Difficulty=All')
    for _, note in ipairs(S.mr_search_notes) do
        Test.expect(note.pitch >= 60 and note.pitch <= 100,
            'note pitch ' .. note.pitch .. ' outside All range 60-100')
    end
end)

----------------------------------------------------------------------
-- Pattern navigation - Go Prev / Go Next / List Search
-- Synthetic track (not a fixture) so match positions are exactly known.
----------------------------------------------------------------------
Test.section('Pattern navigation - Go Prev / Go Next / List Search')

-- Create an empty MIDI-item-bearing track named `name`, `len_s` seconds long
-- from project time 0. Returns (take, item, track_idx).
local function MakeMidiTrack(name, len_s)
    local idx  = CreateEmptyFixtureTrack(name)
    local tr   = r.GetTrack(0, idx)
    local item = r.CreateNewMIDIItemInProj(tr, 0, len_s or 20, false)
    local take = r.GetActiveTake(item)
    return take, item, idx
end

Test.it('ListPatternMatches finds every recurrence; Go Next/Go Prev step between them', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART DRUMS', 12)
    local ppq_per_qn      = GetTakePPQPerQN(take)
    local ppq_per_measure = ppq_per_qn * 4  -- default 4/4

    -- A single Expert-range kick (pitch 96) at the start of measures 1, 3, 5
    -- (0-indexed: 0, 2, 4) - an unambiguous, exactly-known recurrence.
    for _, m in ipairs({ 0, 2, 4 }) do
        local sp = m * ppq_per_measure
        r.MIDI_InsertNote(take, false, false, sp, sp + 1, 0, 96, 100, false)
    end

    S.mr_midi_src_idx = idx
    S.mr_diff_idx     = 1  -- Expert

    -- Capture measure 1's note as the search pattern.
    local m1_time = r.MIDI_GetProjTimeFromPPQPos(take, 0)
    local m2_time = r.MIDI_GetProjTimeFromPPQPos(take, ppq_per_measure)
    r.GetSet_LoopTimeRange(true, false, m1_time, m2_time, false)
    SetSearchPattern()
    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
    Test.expect(S.mr_search_notes ~= nil and #S.mr_search_notes == 1,
        'expected a 1-note search pattern captured')
    Test.expect(not S.mr_search_label:find('\xe2'),
        'search label contains a non-ASCII byte (dash-escape regression): ' .. S.mr_search_label)

    ListPatternMatches()
    Test.expect(S.last_result ~= nil and S.last_result:find('^3 match'),
        'expected 3 matches listed, got status=' .. S.status .. ' result=' .. tostring(S.last_result))
    Test.expect(not S.last_result:find('\xe2'),
        'List Search result contains a non-ASCII byte (dash-escape regression)')

    local m3_time = r.MIDI_GetProjTimeFromPPQPos(take, 2 * ppq_per_measure)
    local m5_time = r.MIDI_GetProjTimeFromPPQPos(take, 4 * ppq_per_measure)

    -- Go Next: measure 1 -> 3 -> 5 -> none left
    r.SetEditCurPos(m1_time + 0.05, false, false)
    GoNextPatternMatch()
    Test.expect(math.abs(r.GetCursorPosition() - m3_time) < 0.01,
        'Go Next: expected cursor at measure 3, got ' .. r.GetCursorPosition())
    GoNextPatternMatch()
    Test.expect(math.abs(r.GetCursorPosition() - m5_time) < 0.01,
        'Go Next: expected cursor at measure 5, got ' .. r.GetCursorPosition())
    GoNextPatternMatch()
    Test.expect(S.status == 'No next instance found.', 'expected no-next status, got: ' .. S.status)

    -- Go Prev: measure 5 -> 3 -> 1 -> none left
    r.SetEditCurPos(m5_time + 0.05, false, false)
    GoPrevPatternMatch()
    Test.expect(math.abs(r.GetCursorPosition() - m3_time) < 0.01,
        'Go Prev: expected cursor at measure 3, got ' .. r.GetCursorPosition())
    GoPrevPatternMatch()
    Test.expect(math.abs(r.GetCursorPosition() - m1_time) < 0.01,
        'Go Prev: expected cursor at measure 1, got ' .. r.GetCursorPosition())
    GoPrevPatternMatch()
    Test.expect(S.status == 'No previous instance found.', 'expected no-previous status, got: ' .. S.status)

    CleanupFixture(idx)
end)

----------------------------------------------------------------------
-- Midi note length adjustment - AdjustMidiNoteLengths
-- Synthetic tracks so exact PPQ-tick results can be asserted.
----------------------------------------------------------------------
Test.section('Midi note length adjustment - AdjustMidiNoteLengths')

Test.it('Non-sustains: unifies every note shorter than 1/8 note to the selected note size', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- Two short (non-sustain) Expert-range (96-100) notes of varying wrong
    -- lengths, plus a third that is already a 1/4-note sustain.
    local sustain_sppq, sustain_eppq = 2 * ppq_per_qn, 3 * ppq_per_qn
    r.MIDI_InsertNote(take, false, false, 0,               100,             0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, ppq_per_qn,       ppq_per_qn + 5,  0, 98, 100, false)
    r.MIDI_InsertNote(take, false, false, sustain_sppq,     sustain_eppq,    0, 100, 100, false)

    S.mn_midi_idx   = idx
    S.mn_diff_idx   = 1  -- Expert
    S.mn_note_type  = 0  -- Non-sustains
    S.mn_note_denom = 32
    AdjustMidiNoteLengths()

    Test.expect(not S.status:find('^Error'), 'AdjustMidiNoteLengths errored: ' .. S.status)
    local _, n = r.MIDI_CountEvts(take)
    Test.expect(n == 3, 'expected 3 notes still present, got ' .. n)
    for i = 0, 1 do
        local ok, _, _, sppq, eppq = r.MIDI_GetNote(take, i)
        Test.expect(ok and (eppq - sppq) == len32,
            ('note %d: expected length %d, got %d'):format(i, len32, eppq - sppq))
    end
    local ok, _, _, sppq3, eppq3 = r.MIDI_GetNote(take, 2)
    Test.expect(ok and sppq3 == sustain_sppq and eppq3 == sustain_eppq,
        'expected the existing 1/4-note sustain to be left completely untouched')
    CleanupFixture(idx)
end)

Test.it('Only sustains: widens a too-small gap to the requested 32nd-note amount', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 1-quarter-note sustain, then the next note only 2x32nds later.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    local next_sppq    = sustain_eppq + 2 * len32
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 96, 100, false)

    S.mn_midi_idx        = idx
    S.mn_diff_idx        = 1  -- Expert
    S.mn_note_type       = 1  -- Only sustains
    S.mn_sustain_32nds   = 4
    AdjustMidiNoteLengths()

    Test.expect(not S.status:find('^Error'), 'AdjustMidiNoteLengths errored: ' .. S.status)
    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_sppq == sustain_sppq, 'sustain start must not move')
    Test.expect(new_eppq == next_sppq - 4 * len32,
        ('expected sustain end at %d, got %d'):format(next_sppq - 4 * len32, new_eppq))
    CleanupFixture(idx)
end)

Test.it('Only sustains: narrows a too-large gap (lengthens the sustain) toward the requested amount', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 1-quarter-note sustain, next note 8x32nds later (well within the
    -- 16x32nd search window); request a smaller 2x32nd gap.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    local next_sppq    = sustain_eppq + 8 * len32
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 96, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 2
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_eppq > sustain_eppq, 'expected the sustain to be lengthened')
    Test.expect(new_eppq == next_sppq - 2 * len32,
        ('expected sustain end at %d, got %d'):format(next_sppq - 2 * len32, new_eppq))
    CleanupFixture(idx)
end)

Test.it('Only sustains: clamps to the 1/32-note floor when the requested gap would shrink it below that', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 1-quarter-note sustain, next note only 1x32nd later; requesting a
    -- large gap (16x32nds) would push the sustain length negative.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    local next_sppq    = sustain_eppq + len32
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 96, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 16
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_eppq == sustain_sppq + len32,
        ('expected sustain clamped to the 1/32-note floor (%d), got %d'):format(sustain_sppq + len32, new_eppq))
    Test.expect(S.last_result ~= nil and S.last_result:find('clamped'),
        'expected the report to mention a clamped sustain: ' .. tostring(S.last_result))
    CleanupFixture(idx)
end)

Test.it('Only sustains: skips a sustain with no next note within the 16x32nd search window', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 1-quarter-note sustain with nothing else on the track at all.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 4
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_sppq == sustain_sppq and new_eppq == sustain_eppq,
        'expected the sustain to be left unchanged (no next note in range)')
    Test.expect(S.last_result ~= nil and S.last_result:find('1 skipped'),
        'expected the report to count 1 skipped sustain: ' .. tostring(S.last_result))
    CleanupFixture(idx)
end)

Test.it('Only sustains: a note shorter than 1/8 note is left untouched', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 16th-note-length note (not a sustain: shorter than 1/8 note), and a
    -- following note close enough that a real sustain would be adjusted.
    local short_sppq = 0
    local short_eppq = math.floor(ppq_per_qn / 4 + 0.5)  -- 1/16 note
    local next_sppq  = short_eppq + len32
    r.MIDI_InsertNote(take, false, false, short_sppq, short_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 96, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 8
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_sppq == short_sppq and new_eppq == short_eppq,
        'expected the non-sustain note to be left completely unchanged')
    CleanupFixture(idx)
end)

Test.it('Only sustains: a chord sustain (same start tick) is counted once, not per pitch', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A Green+Red+Blue chord sustain (3 pitches, same start/end), then the
    -- next chord 2x32nds later.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    local next_sppq    = sustain_eppq + 2 * len32
    for _, pitch in ipairs({ 96, 97, 99 }) do
        r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, pitch, 100, false)
        r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, pitch, 100, false)
    end

    S.mn_midi_idx        = idx
    S.mn_diff_idx        = 1  -- Expert
    S.mn_note_type       = 1  -- Only sustains
    S.mn_sustain_32nds   = 4
    AdjustMidiNoteLengths()

    Test.expect(S.last_result ~= nil and S.last_result:find('^1 sustain'),
        'expected the 3-pitch chord to be reported as 1 sustain, got: ' .. tostring(S.last_result))
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq = r.MIDI_GetNote(take, i)
        if ok and sppq == sustain_sppq then
            Test.expect(eppq == next_sppq - 4 * len32,
                ('chord note at index %d: expected end %d, got %d'):format(i, next_sppq - 4 * len32, eppq))
        end
    end
    CleanupFixture(idx)
end)

Test.it('Non-sustains: a chord (same start tick) is counted once, not per pitch', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A Green+Red+Blue chord of short (wrong-length) notes sharing one start tick.
    for _, pitch in ipairs({ 96, 97, 99 }) do
        r.MIDI_InsertNote(take, false, false, 0, 50, 0, pitch, 100, false)
    end

    S.mn_midi_idx   = idx
    S.mn_diff_idx   = 1  -- Expert
    S.mn_note_type  = 0  -- Non-sustains
    S.mn_note_denom = 32
    AdjustMidiNoteLengths()

    Test.expect(S.status:find('^Adjusted 1 non%-sustain note%.'),
        'expected the 3-pitch chord to be reported as 1 note, got status: ' .. S.status)
    local _, n = r.MIDI_CountEvts(take)
    Test.expect(n == 3, 'expected 3 notes still present, got ' .. n)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq = r.MIDI_GetNote(take, i)
        Test.expect(ok and (eppq - sppq) == len32,
            ('chord note %d: expected length %d, got %d'):format(i, len32, eppq - sppq))
    end
    CleanupFixture(idx)
end)

Test.it('Only sustains: an exactly-1/8-note note counts as a sustain and is adjusted', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- Exactly at the sustain threshold (1/8 note), with a next note 4x32nds on.
    local sustain_sppq = 0
    local sustain_eppq = math.floor(ppq_per_qn / 2 + 0.5)  -- 1/8 note
    local next_sppq    = sustain_eppq + 4 * len32
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 96, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 2
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_eppq == next_sppq - 2 * len32,
        ('expected the 1/8-note sustain adjusted to end at %d, got %d'):format(
            next_sppq - 2 * len32, new_eppq))
    CleanupFixture(idx)
end)

Test.it('Only sustains: a note buried INSIDE the sustain is the next note, not a later one', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- A 3-quarter-note sustain that already overlaps a short note at 1 QN.
    -- Measuring only from the sustain's tail would step over that note and
    -- size the gap against the one at 3 QN, leaving the overlap in place.
    local sustain_sppq  = 0
    local sustain_eppq  = 3 * ppq_per_qn
    local buried_sppq   = ppq_per_qn
    local later_sppq    = 3 * ppq_per_qn
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, buried_sppq, buried_sppq + len32, 0, 97, 100, false)
    r.MIDI_InsertNote(take, false, false, later_sppq, later_sppq + len32, 0, 98, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 2
    AdjustMidiNoteLengths()

    local ok, _, _, new_sppq, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_sppq == sustain_sppq, 'sustain start must not move')
    Test.expect(new_eppq == buried_sppq - 2 * len32,
        ('expected the sustain sized against the buried note (end %d), got %d'):format(
            buried_sppq - 2 * len32, new_eppq))
    Test.expect(new_eppq < buried_sppq, 'the sustain must no longer overlap the buried note')
    CleanupFixture(idx)
end)

Test.it('Only sustains: a buried note is honored even with no clean next note in the window', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- Buried note at 1 QN; the next clean note is 20 QN away, far outside the
    -- 16x32nd window. The overlap is a defect regardless, so it still wins.
    local sustain_sppq = 0
    local sustain_eppq = 2 * ppq_per_qn
    local buried_sppq  = ppq_per_qn
    local far_sppq     = 20 * ppq_per_qn
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, buried_sppq, buried_sppq + len32, 0, 97, 100, false)
    r.MIDI_InsertNote(take, false, false, far_sppq, far_sppq + len32, 0, 98, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 2
    AdjustMidiNoteLengths()

    local ok, _, _, _, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_eppq == buried_sppq - 2 * len32,
        ('expected end at %d (buried note), got %d'):format(buried_sppq - 2 * len32, new_eppq))
    CleanupFixture(idx)
end)

Test.it('Only sustains: a next note starting exactly at the sustain end is seen', function()
    reset()
    local take, item, idx = MakeMidiTrack('PART GUITAR', 20)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len32      = math.floor(ppq_per_qn * 4 / 32 + 0.5)

    -- Sustain end and next note start share a tick (zero gap) - and a third
    -- note further on that must NOT be the one measured against.
    local sustain_sppq = 0
    local sustain_eppq = ppq_per_qn
    local next_sppq    = ppq_per_qn
    local later_sppq   = ppq_per_qn + 8 * len32
    r.MIDI_InsertNote(take, false, false, sustain_sppq, sustain_eppq, 0, 96, 100, false)
    r.MIDI_InsertNote(take, false, false, next_sppq, next_sppq + len32, 0, 97, 100, false)
    r.MIDI_InsertNote(take, false, false, later_sppq, later_sppq + len32, 0, 98, 100, false)

    S.mn_midi_idx      = idx
    S.mn_diff_idx      = 1
    S.mn_note_type     = 1
    S.mn_sustain_32nds = 2
    AdjustMidiNoteLengths()

    local ok, _, _, _, new_eppq = r.MIDI_GetNote(take, 0)
    Test.expect(ok and new_eppq == next_sppq - 2 * len32,
        ('expected end at %d, got %d'):format(next_sppq - 2 * len32, new_eppq))
    CleanupFixture(idx)
end)

Test.it('SustainGapDefaultForDiff returns the standard gap per tier', function()
    local want = { [1] = 3, [2] = 4, [3] = 8, [4] = 16 }
    for diff, gap in pairs(want) do
        local got = SustainGapDefaultForDiff(diff)
        Test.expect(got == gap,
            ('diff %d: expected gap %d, got %s'):format(diff, gap, tostring(got)))
    end
    Test.expect(SustainGapDefaultForDiff(0) == nil, 'expected nil for a non-tier index')
    Test.expect(SustainGapDefaultForDiff(5) == nil, 'expected nil for a non-tier index')
end)

----------------------------------------------------------------------
-- Venue - rb_venue_events.mid (EVENTS + VENUE tracks, no instrument awareness data)
-- Venue actions locate tracks by name via FindTrackByName, not S index.
----------------------------------------------------------------------
Test.section('Venue - rb_venue_events.mid (always-playing fallback)')

Test.it('ListVenueEvents: reads VENUE track and reports events', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    Test.expect(n > 0, 'rb_venue_events.mid created no tracks')
    ListVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ListVenueEvents did not update S.status')
end)

Test.it('ListEventSections: reads [prc_*] markers from EVENTS track', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    ListEventSections()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ListEventSections did not update S.status')
end)

Test.it('GenerateVenueEvents: generates events; instruments default to always-playing', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    GenerateVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'GenerateVenueEvents did not update S.status')
    Test.expect(not S.status:find('^Error'), 'GenerateVenueEvents errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Venue with awareness - rb_venue_all_references.mid
-- Contains PART DRUMS/GUITAR/BASS/etc. with [idle] and [play] text events.
-- GenerateVenueEvents uses these to weight camera shot selection per instrument.
----------------------------------------------------------------------
Test.section('Venue - rb_venue_all_references.mid (with idle/play awareness)')

Test.it('GenerateVenueEvents: weights cameras using instrument play states', function()
    reset()
    local base, n = LoadFixture('rb_venue_all_references.mid')
    Test.expect(n > 0, 'rb_venue_all_references.mid created no tracks')
    GenerateVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'GenerateVenueEvents did not update S.status')
    Test.expect(not S.status:find('^Error'), 'GenerateVenueEvents errored: ' .. S.status)
end)
