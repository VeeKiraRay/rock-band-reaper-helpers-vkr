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
-- ConvertDrums — external_drums.mid (standard GM drum notation)
----------------------------------------------------------------------
Test.section('ConvertDrums — GM drums fixture')

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
-- ConvertGuitar — external_guitar.mid (any pitched MIDI)
----------------------------------------------------------------------
Test.section('ConvertGuitar — external guitar fixture')

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
-- Piano source actions — all share mc_keys_src_idx from external_piano.mid
----------------------------------------------------------------------
Test.section('Piano → Keys — external_piano.mid')

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
-- ValidateGuitar — rb_guitar.mid (RB gem pitches 96-100 already authored)
----------------------------------------------------------------------
Test.section('ValidateGuitar — RB guitar fixture')

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
-- Pro Keys — rb_pro_keys.mid (separate tracks per difficulty + animation)
----------------------------------------------------------------------
Test.section('Pro Keys — rb_pro_keys.mid')

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

Test.it('SuggestProKeysDiff H: analyzes Expert and lists needed changes', function()
    reset()
    local base, n = LoadFixture('rb_pro_keys.mid')
    Test.expect(n > 0, 'rb_pro_keys.mid created no tracks')
    local x_idx = FindFixtureTrack('REAL_KEYS_X', base)
    Test.expect(x_idx ~= nil, 'no PART REAL_KEYS_X track found')
    S.diff_pk_x_idx = x_idx
    SuggestProKeysDiff('H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'SuggestProKeysDiff(H) errored: ' .. S.status)
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
-- 5-Lane Keys — rb_keys.mid (single track, all difficulties by pitch range)
-- Expert 96-100 | Hard 84-88 | Medium 72-75 | Easy 60-62
----------------------------------------------------------------------
Test.section('5-Lane Keys — rb_keys.mid')

Test.it('SuggestKeys5Diff H: analyzes Expert gems and lists reductions', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    Test.expect(n > 0, 'rb_keys.mid created no tracks')
    S.diff_5k_idx = base
    SuggestKeys5Diff('H')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'SuggestKeys5Diff(H) errored: ' .. S.status)
end)

Test.it('ValidateKeys5Diff X: validates Expert pitch range (96-100)', function()
    reset()
    local base, n = LoadFixture('rb_keys.mid')
    S.diff_5k_idx = base
    ValidateKeys5Diff('X')
    CleanupFixture(base)
    Test.expect(not S.status:find('^Error'), 'ValidateKeys5Diff(X) errored: ' .. S.status)
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
-- Venue — rb_venue_events.mid (EVENTS + VENUE tracks, no instrument awareness data)
-- Venue actions locate tracks by name via FindTrackByName, not S index.
----------------------------------------------------------------------
Test.section('Venue — rb_venue_events.mid (always-playing fallback)')

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
-- Venue with awareness — rb_venue_all_references.mid
-- Contains PART DRUMS/GUITAR/BASS/etc. with [idle] and [play] text events.
-- GenerateVenueEvents uses these to weight camera shot selection per instrument.
----------------------------------------------------------------------
Test.section('Venue — rb_venue_all_references.mid (with idle/play awareness)')

Test.it('GenerateVenueEvents: weights cameras using instrument play states', function()
    reset()
    local base, n = LoadFixture('rb_venue_all_references.mid')
    Test.expect(n > 0, 'rb_venue_all_references.mid created no tracks')
    GenerateVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'GenerateVenueEvents did not update S.status')
    Test.expect(not S.status:find('^Error'), 'GenerateVenueEvents errored: ' .. S.status)
end)
