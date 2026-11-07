-- REAPER tests for the Instrument Helper's Keys > Tuner controller (chord_tuner.lua): real
-- audio accessors on a generated keys stem, a charted Pro Keys chord, and the poll loop.
-- Requires: Test (framework.lua), fixture helpers, WriteMonoWAV16 (lib/reaper_wav_writer.lua),
--           and the modules run_instrument_chord_tuner.lua loads.
--
-- Fixture (all at 120 BPM, project time):
--   KEYS AUDIO        a WAV item at ITEM_POS: struck C major chords every 0.5 s for 5 s,
--                     then a C major melody of single notes every 0.25 s for 5 s
--   PART REAL_KEYS_X  one charted chord, C E G, at CHART_S .. CHART_S + 0.5
-- Playback must be stopped while the suite runs (the tuner reads the edit cursor).

local ITEM_POS   = 2.0
local CHORDS_S   = 5.0            -- chords for this long from ITEM_POS, then the melody
local MELODY_S   = 5.0
local CHART_S    = ITEM_POS + 1.0 -- the charted chord
local SR_WAV     = 44100
local MELODY     = { 60, 64, 67, 65, 62, 60, 71, 72 }
local SETTINGS_SECTION, SETTINGS_KEY = 'RBInstrumentHelperVKR', 'settings_v1'   -- settings.lua's (file-local there)

local function Hz(p) return 440 * 2 ^ ((p - 69) / 12) end

local function KeysSample(t)
    local function Hit(pitches, dt)
        local s, env = 0, math.exp(-4 * dt)
        for _, p in ipairs(pitches) do
            local f = Hz(p)
            for k = 1, 6 do s = s + env * math.sin(2 * math.pi * k * f * dt + 0.7 * k) / k end
        end
        return s
    end
    if t < CHORDS_S then
        local k = math.floor(t / 0.5)
        local v = Hit({ 60, 64, 67 }, t - k * 0.5)
        if k > 0 then v = v + Hit({ 60, 64, 67 }, t - (k - 1) * 0.5) end
        return v
    end
    local m = t - CHORDS_S
    local k = math.floor(m / 0.25)
    local v = Hit({ MELODY[k % #MELODY + 1] }, m - k * 0.25)
    if k > 0 then v = v + Hit({ MELODY[(k - 1) % #MELODY + 1] }, m - (k - 1) * 0.25) end
    return v
end

local fixture = {}

local function BuildFixture()
    fixture.baseline = r.CountTracks(0)
    fixture.cursor = r.GetCursorPosition()
    EnsureDefaultTempoMarker()
    local samples = {}
    for i = 1, math.floor((CHORDS_S + MELODY_S) * SR_WAV) do samples[i] = KeysSample((i - 1) / SR_WAV) end
    local tmp = os.getenv('TEMP') or os.getenv('TMP') or '.'
    fixture.path = tmp .. '/rb_vkr_chord_tuner_test.wav'
    local ok, err = WriteMonoWAV16(samples, SR_WAV, fixture.path)
    if not ok then return nil, 'WAV write failed: ' .. tostring(err) end

    local ki = CreateEmptyFixtureTrack('KEYS AUDIO')
    local ktr = r.GetTrack(0, ki)
    r.SetOnlyTrackSelected(ktr)
    r.SetEditCurPos(ITEM_POS, false, false)
    r.InsertMedia(fixture.path, 0)
    if r.CountTrackMediaItems(ktr) == 0 then return nil, 'InsertMedia produced no item' end
    r.SetMediaItemInfo_Value(r.GetTrackMediaItem(ktr, 0), 'D_POSITION', ITEM_POS)

    local pi = CreateEmptyFixtureTrack('PART REAL_KEYS_X')
    local ptr = r.GetTrack(0, pi)
    local item = r.CreateNewMIDIItemInProj(ptr, 0, ITEM_POS + CHORDS_S + MELODY_S, false)
    local take = r.GetActiveTake(item)
    local s = r.MIDI_GetPPQPosFromProjTime(take, CHART_S)
    local e = r.MIDI_GetPPQPosFromProjTime(take, CHART_S + 0.5)
    for _, p in ipairs({ 60, 64, 67 }) do r.MIDI_InsertNote(take, false, false, s, e, 0, p, 100, false) end
    fixture.keys_idx = ki
    return true
end

local function CleanupFixtureAll()
    StopChordTuner()
    CleanupFixture(fixture.baseline)
    if fixture.path then os.remove(fixture.path) end
    if fixture.cursor then r.SetEditCurPos(fixture.cursor, false, false) end
end

-- Run the tuner's poll until nothing is left to read (or `polls` run out).
local function Settle(polls)
    for _ = 1, polls or 80 do
        S.ct_tab_active = true
        S.ct_last_t = 0                 -- the poll is rate-limited to 100 ms; the test is not
        ChordTunerTick()
        if not S.ct_job and not S.ct_pass_job then return true end
    end
    return false
end

local function ReadAt(t)
    r.SetEditCurPos(t, false, false)
    return Settle()
end

Test.section('Keys > Tuner controller (REAPER)')

if r.GetPlayState() & 1 ~= 0 then
    Test.it('playback must be stopped', function() Test.expect(false, 'stop playback and run again') end)
    return
end

local built, build_err = BuildFixture()
if not built then
    Test.it('fixture', function() Test.expect(false, tostring(build_err)) end)
    CleanupFixtureAll()
    return
end

Test.it('picks KEYS AUDIO by default', function()
    S.ct_keys_idx, S.ct_bass_idx = -1, -1
    RefreshTrackLists()
    SetDefaultChordTunerTracks()
    Test.expect(S.ct_keys_idx == fixture.keys_idx, ('ct_keys_idx %d, want %d'):format(S.ct_keys_idx, fixture.keys_idx))
end)

Test.it('stopped on a charted chord: reads its span, C major, with the charted notes', function()
    S.ct_key_mode, S.ct_plain, S.ct_passage, S.ct_read_long = 'off', true, true, false
    StartChordTuner()
    Test.expect(S.ct_active, 'started: ' .. tostring(S.status))
    Test.expect(ReadAt(CHART_S + 0.1), 'reading finished')
    local res = S.ct_result
    Test.expect(res and res.kind == 'chart', 'kind ' .. tostring(res and res.kind))
    Test.expect(res and res.top and ChordName(res.top[1]) == 'C', 'chord ' .. tostring(res and res.top and ChordName(res.top[1])))
    Test.expect(res and res.chart and res.chart.mask == ((1 << 0) | (1 << 4) | (1 << 7)), 'charted C E G')
    Test.expect(res and res.single and res.single % 12 ~= nil, 'a Single reading')
end)

Test.it('stopped off the chart, in the chords: fixed window C, passage looks like chords', function()
    -- 0.5 s in: the 4 s passage stays inside the chords and off the charted chord (1.0 s in)
    Test.expect(ReadAt(ITEM_POS + 0.5), 'reading finished')
    local res, p = S.ct_result, S.ct_pass
    Test.expect(res and res.kind == 'fixed' and ChordName(res.top[1]) == 'C', 'fixed C: ' .. tostring(res and res.kind))
    Test.expect(p and not p.busy and p.single == false, 'passage chords, value ' .. tostring(p and p.value))
end)

Test.it('stopped in the melody: passage looks like single notes, Single names the note', function()
    -- melody note k = 4 starts at CHORDS_S + 1.0 into the item: MELODY[5] = D
    Test.expect(ReadAt(ITEM_POS + CHORDS_S + 1.0), 'reading finished')
    local res, p = S.ct_result, S.ct_pass
    Test.expect(p and not p.busy and p.single == true, 'passage single notes, value ' .. tostring(p and p.value))
    Test.expect(res and res.single and res.single % 12 == MELODY[5] % 12,
        'Single ' .. tostring(res and res.single and PitchName(res.single)))
end)

Test.it('nudging the cursor re-uses the passage frames', function()
    local before = 0
    for _ in pairs(S.ct_pass_frames) do before = before + 1 end
    Test.expect(ReadAt(ITEM_POS + CHORDS_S + 1.3), 'reading finished')
    local after = 0
    for _ in pairs(S.ct_pass_frames) do after = after + 1 end
    Test.expect(after - before <= 8, ('%d new frames for a 0.3 s nudge'):format(after - before))
end)

Test.it('stops itself after 60 s with the cursor still, closing its accessors', function()
    S.ct_last_move_t = r.time_precise() - 61
    Settle(2)
    Test.expect(not S.ct_active, 'stopped: ' .. tostring(S.status))
    Test.expect(next(S.ct_audio) == nil, 'accessors closed')
end)

Test.it('stops when its sub-tab is not drawn', function()
    StartChordTuner()
    ReadAt(CHART_S + 0.1)
    S.ct_tab_active = false
    ChordTunerTick()
    Test.expect(not S.ct_active and next(S.ct_audio) == nil, 'stopped, accessors closed')
end)

Test.it('settings round trip (the project\'s own saved settings are restored afterwards)', function()
    local _, saved = r.GetProjExtState(0, SETTINGS_SECTION, SETTINGS_KEY)
    S.ct_key_mode, S.ct_key_tonic, S.ct_key_minor, S.ct_plain, S.ct_read_long, S.ct_passage =
        'manual', 9, true, false, true, false
    SaveSettings()
    S.ct_key_mode, S.ct_key_tonic, S.ct_key_minor, S.ct_plain, S.ct_read_long, S.ct_passage =
        'off', 0, false, true, false, true
    LoadSettings()
    Test.expect(S.ct_key_mode == 'manual' and S.ct_key_tonic == 9 and S.ct_key_minor
        and not S.ct_plain and S.ct_read_long and not S.ct_passage, 'all six restored')
    r.SetProjExtState(0, SETTINGS_SECTION, SETTINGS_KEY, saved or '')
end)

CleanupFixtureAll()
