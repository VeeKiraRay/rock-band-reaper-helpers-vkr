-- Does REAPER's audio accessor actually resample when asked for a rate other
-- than the source rate?
--
-- This is the open question blocking item 7 of
-- _future_ideas/vocal_pitch_engine_port.md (analyse at a fixed ~16 kHz, which
-- would make the CMND ~9x cheaper and make item 6's multi-window sampling
-- affordable). If GetAudioAccessorSamples honours its samplerate argument,
-- item 7 is a small diff. If it ignores it and returns source-rate samples,
-- the whole approach needs a hand-rolled decimator instead.
--
-- Cannot be answered outside REAPER, so it lives here rather than in
-- dsp_algorithms.lua.
--
-- Also covers the item-relative accessor rule from CLAUDE.md: the fixture item
-- is deliberately placed at a NON-ZERO project position, so a missing
-- item_pos offset reads silence and fails loudly.

local TEST_FREQ   = 220.0      -- A3
local TEST_MIDI   = 57
local SRC_SR      = 48000
local ANALYSIS_SR = 16000
local ITEM_POS    = 5.0        -- non-zero on purpose
local DUR_S       = 1.0

local function make_saw(freq, sr, n, n_harm)
    local buf = {}
    for i = 1, n do
        local t, s = (i - 1) / sr, 0
        for k = 1, n_harm do
            if k * freq < sr * 0.5 then
                s = s + math.sin(2 * math.pi * k * freq * t) / k
            end
        end
        buf[i] = s * 0.5
    end
    return buf
end

-- Everything this test added to the project, so cleanup works on every exit
-- path. A leaked track would shift indices for any fixture suite run later in
-- the same REAPER session, which is exactly the kind of cross-test flakiness
-- that is miserable to track down.
local fixture = { track_idx = nil, path = nil, sel = nil, cursor = nil }

local function CleanupProbe()
    if fixture.track_idx then
        local tr = r.GetTrack(0, fixture.track_idx)
        if tr then r.DeleteTrack(tr) end
        fixture.track_idx = nil
    end
    if fixture.path then os.remove(fixture.path); fixture.path = nil end
    -- Restore the selection and edit cursor this test disturbed.
    if fixture.sel then
        for i = 0, r.CountTracks(0) - 1 do
            local tr = r.GetTrack(0, i)
            r.SetTrackSelected(tr, fixture.sel[tr] or false)
        end
        fixture.sel = nil
    end
    if fixture.cursor then
        r.SetEditCurPos(fixture.cursor, false, false)
        fixture.cursor = nil
    end
end

-- Build the fixture: a WAV of a known tone on a new track at ITEM_POS.
-- Returns item, or nil, err. On failure the caller must still call
-- CleanupProbe -- partial state is already recorded in `fixture`.
local function BuildToneFixture()
    fixture.cursor = r.GetCursorPosition()
    fixture.sel    = {}
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        fixture.sel[tr] = r.IsTrackSelected(tr)
    end

    local tmp = os.getenv('TEMP') or os.getenv('TMP') or '.'
    fixture.path = tmp .. '/rb_vkr_accessor_probe.wav'

    local samples = make_saw(TEST_FREQ, SRC_SR, math.floor(SRC_SR * DUR_S), 12)
    local ok, werr = WriteMonoWAV16(samples, SRC_SR, fixture.path)
    if not ok then return nil, 'WAV write failed: ' .. tostring(werr) end

    local track_idx = r.CountTracks(0)
    r.InsertTrackAtIndex(track_idx, false)
    fixture.track_idx = track_idx          -- recorded before anything can fail
    local track = r.GetTrack(0, track_idx)
    r.GetSetMediaTrackInfo_String(track, 'P_NAME', 'ACCESSOR PROBE', true)

    -- InsertMedia targets the selected track at the edit cursor.
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(ITEM_POS, false, false)
    r.InsertMedia(fixture.path, 0)

    if r.CountTrackMediaItems(track) == 0 then
        return nil, 'InsertMedia produced no item (path: ' .. fixture.path .. ')'
    end
    local item = r.GetTrackMediaItem(track, 0)
    r.SetMediaItemInfo_Value(item, 'D_POSITION', ITEM_POS)
    return item
end

-- Read a mono window straight from the accessor at an explicit rate, so the
-- rate argument is the only thing under test.
local function ReadAtRate(accessor, item_pos, t_project, rate, n_samps)
    local buf = r.new_array(n_samps)
    buf.clear()
    r.GetAudioAccessorSamples(accessor, rate, 1, t_project - item_pos, n_samps, buf)
    local mono, energy = {}, 0
    for i = 1, n_samps do
        mono[i] = buf[i]
        energy  = energy + buf[i] * buf[i]
    end
    return mono, math.sqrt(energy / n_samps)
end

local function DetectAt(mono, rate)
    local tau_max = math.floor(rate / 80)
    local tau_min = math.max(1, math.floor(rate / 1000))
    local d = ComputeCMND(mono, tau_max)
    if not d then return nil end
    return SearchYINTau(d, tau_min, tau_max, 0.15, rate, 80, 1000)
end

----------------------------------------------------------------------
Test.section('Audio accessor - resampling probe')

local item, build_err = BuildToneFixture()

if not item then
    CleanupProbe()
    Test.it('fixture builds', function()
        Test.expect(false, tostring(build_err))
    end)
else
    local take     = r.GetActiveTake(item)
    local accessor = r.CreateTakeAudioAccessor(take)
    local t_probe  = ITEM_POS + 0.25          -- well inside the tone

    Test.it('control: reading at the source rate detects the known tone', function()
        local n = math.floor(SRC_SR * 0.03) + math.floor(SRC_SR / 80)
        local mono, rms = ReadAtRate(accessor, ITEM_POS, t_probe, SRC_SR, n)
        Test.expect(rms > 0.01, string.format(
            'window is silent (rms %.5f) - item-relative offset is wrong', rms))
        local p = DetectAt(mono, SRC_SR)
        Test.expect(p == TEST_MIDI, string.format(
            'expected MIDI %d at %d Hz, got %s', TEST_MIDI, SRC_SR, tostring(p)))
    end)

    Test.it('THE QUESTION: reading at 16 kHz returns resampled audio', function()
        local n = math.floor(ANALYSIS_SR * 0.03) + math.floor(ANALYSIS_SR / 80)
        local mono, rms = ReadAtRate(accessor, ITEM_POS, t_probe, ANALYSIS_SR, n)
        Test.expect(rms > 0.01, string.format(
            'window is silent at %d Hz (rms %.5f)', ANALYSIS_SR, rms))

        local p = DetectAt(mono, ANALYSIS_SR)
        if p == TEST_MIDI then return end   -- pass: genuine resampling

        -- Diagnose the failure so the result is actionable.
        -- If the accessor ignored the rate and handed back source-rate
        -- samples, interpreting them as 16 kHz makes the tone read 3x low.
        local as_if_ignored = DetectAt(mono, SRC_SR)
        local detail
        if as_if_ignored == TEST_MIDI then
            detail = 'accessor IGNORED the rate argument - samples came back ' ..
                     'at the source rate. Item 7 needs a real decimator.'
        else
            detail = string.format('got MIDI %s (expected %d); reinterpreting ' ..
                     'at the source rate gives %s', tostring(p), TEST_MIDI,
                     tostring(as_if_ignored))
        end
        Test.expect(false, detail)
    end)

    Test.it('resampled and native reads agree on level', function()
        -- A correct resample preserves RMS; truncation or zero-fill would not.
        local n1 = math.floor(SRC_SR * 0.03) + math.floor(SRC_SR / 80)
        local n2 = math.floor(ANALYSIS_SR * 0.03) + math.floor(ANALYSIS_SR / 80)
        local _, rms_native = ReadAtRate(accessor, ITEM_POS, t_probe, SRC_SR, n1)
        local _, rms_down   = ReadAtRate(accessor, ITEM_POS, t_probe, ANALYSIS_SR, n2)
        Test.expect(math.abs(rms_native - rms_down) < 0.05, string.format(
            'rms %.4f (native) vs %.4f (16 kHz)', rms_native, rms_down))
    end)

    r.DestroyAudioAccessor(accessor)
    CleanupProbe()
end
