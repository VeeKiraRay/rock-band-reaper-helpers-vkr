-- Algorithm unit tests for general helper pure-Lua functions:
-- EstimateBPM, GuessTimeSig, FitBeatGrid.
-- Tempomap constants (BPM_MIN, BPM_MAX, ONSET_GRACE_S) are module-locals in
-- tempomap.lua, closed over by the functions - no setup required here.

----------------------------------------------------------------------
Test.section('EstimateBPM')

Test.it('empty onsets → nil', function()
    local bpm = EstimateBPM({})
    Test.expect(bpm == nil, 'empty → nil')
end)

Test.it('single onset → nil (need at least 2 for an IOI)', function()
    local bpm = EstimateBPM({1.0})
    Test.expect(bpm == nil, 'single onset → nil')
end)

Test.it('regular onsets: BPM in valid range [60, 250] with positive confidence', function()
    -- 8 onsets at IOI=0.5s (120 BPM equivalent); voting may pick 60 or 120 or 240
    -- but it must be a valid bin and confidence > 0
    local onsets = {}
    for i = 0, 7 do onsets[i+1] = i * 0.5 end
    local bpm, conf = EstimateBPM(onsets)
    Test.expect(bpm ~= nil, 'non-nil BPM from regular onsets')
    Test.expect(bpm >= 60 and bpm <= 250, 'BPM in valid range; got ' .. tostring(bpm))
    Test.expect(conf ~= nil and conf > 0, 'positive confidence')
end)

Test.it('mixed IOI gives 120 more votes than 60 or 240 → returns 120', function()
    -- 3 × IOI=0.25s: votes 240 and 120 (not 60) → hist[120]+=3, hist[240]+=3
    -- 1 × IOI=0.5s:  votes 120, 60, 240           → hist[120]+=1, hist[60]+=1, hist[240]+=1
    -- totals: hist[120]=4, hist[60]=1, hist[240]=4 → 120 wins (scanned low→high, 60 < 120 < 240)
    local onsets = {0, 0.25, 0.5, 0.75, 1.25}
    local bpm = EstimateBPM(onsets)
    Test.expect(bpm == 120, 'mixed IOI → 120; got ' .. tostring(bpm))
end)

----------------------------------------------------------------------
Test.section('GuessTimeSig')

Test.it('downbeats at every 4-beat measure of 4/4 → returns 4', function()
    -- beat_dur=0.5s (120 BPM), measure=2s; onsets only on downbeats
    local onsets = {0, 2, 4, 6, 8}
    local num = GuessTimeSig(onsets, 0.5, 0)
    Test.expect(num == 4, 'regular 4/4 downbeats → 4; got ' .. num)
end)

Test.it('empty onsets → fallback 4', function()
    local num = GuessTimeSig({}, 0.5, 0)
    Test.expect(num == 4, 'empty onsets → default 4')
end)

Test.it('zero beat_dur → guard returns 4', function()
    local num = GuessTimeSig({0, 1, 2, 3}, 0, 0)
    Test.expect(num == 4, 'zero beat_dur → 4')
end)

Test.it('confidence value is in [0, 1]', function()
    local _, conf = GuessTimeSig({0, 2, 4, 6, 8}, 0.5, 0)
    Test.expect(conf >= 0 and conf <= 1, 'confidence in [0,1]; got ' .. tostring(conf))
end)

----------------------------------------------------------------------
Test.section('FitBeatGrid')

local function make_sources(onset_list)
    return {{ onsets = onset_list, name = 'test' }}
end

Test.it('onsets exactly on downbeats: zero deviation and correct BPM', function()
    -- 4/4 at 120 BPM: beat_dur=0.5, measure_qn=4, downbeat every 2s
    local sources = make_sources({2.0, 4.0, 6.0, 8.0})
    local grid = FitBeatGrid(0, 8.0, 0.5, 4, sources, 0.1)
    Test.expect(#grid >= 1, 'at least one grid entry')
    local all_found, all_zero = true, true
    for _, entry in ipairs(grid) do
        if entry.detected_t == nil    then all_found = false end
        if entry.deviation_s == nil or math.abs(entry.deviation_s) > 1e-9 then
            all_zero = false
        end
    end
    Test.expect(all_found, 'all downbeats detected')
    Test.expect(all_zero,  'all deviations are zero')
    Test.expect(math.abs(grid[1].bpm - 120) < 1e-6, 'BPM = 120')
end)

Test.it('no onsets: detected_t nil, BPM falls back to initial beat_dur', function()
    local sources = make_sources({})
    local grid = FitBeatGrid(0, 8.0, 0.5, 4, sources, 0.1)
    Test.expect(#grid >= 1, 'grid entries generated even with no onsets')
    local all_nil = true
    for _, entry in ipairs(grid) do
        if entry.detected_t ~= nil then all_nil = false end
    end
    Test.expect(all_nil, 'all detected_t nil when no onsets')
    Test.expect(math.abs(grid[1].bpm - 120) < 1e-6, 'BPM falls back to 120 from beat_dur=0.5')
end)

Test.it('onset slightly early: detected_t is the actual onset, deviation negative', function()
    -- Expected at 2.0, actual at 1.95 (within search_window=0.1)
    local sources = make_sources({1.95, 3.95, 5.95, 7.95})
    local grid = FitBeatGrid(0, 8.0, 0.5, 4, sources, 0.1)
    local entry = grid[1]
    Test.expect(entry.detected_t ~= nil, 'onset found within window')
    Test.expect(entry.deviation_s ~= nil and entry.deviation_s < 0, 'deviation is negative (early)')
    Test.expect(math.abs(entry.deviation_s - (-0.05)) < 1e-6, 'deviation = -0.05s')
end)

----------------------------------------------------------------------
Test.section('ComputePlayerStatesAt')

-- Hand-built inputs mirroring ReadInstrumentPlayStates() / GetMutedInstruments()
local ps_states = {
    g = {
        { t = 10, is_active = true,  msg = '[play]' },
        { t = 20, is_active = false, msg = '[idle]' },
        { t = 30, is_active = true,  msg = '[intense]' },
    },
}
local ps_no_data = { 'k' }
local ps_muted   = { d = true }

Test.it('muted instrument reports muted regardless of playhead', function()
    local res = ComputePlayerStatesAt(15, ps_states, ps_no_data, ps_muted)
    Test.expect(res.d.state == 'muted', 'd is muted; got ' .. tostring(res.d.state))
end)

Test.it('present track without play-state events reports nodata', function()
    local res = ComputePlayerStatesAt(15, ps_states, ps_no_data, ps_muted)
    Test.expect(res.k.state == 'nodata', 'k is nodata; got ' .. tostring(res.k.state))
end)

Test.it('playhead before first event: active with no msg', function()
    local res = ComputePlayerStatesAt(5, ps_states, ps_no_data, ps_muted)
    Test.expect(res.g.state == 'active', 'g active before first event')
    Test.expect(res.g.msg == nil, 'no msg before first event')
end)

Test.it('playhead between events picks last at-or-before', function()
    local res = ComputePlayerStatesAt(25, ps_states, ps_no_data, ps_muted)
    Test.expect(res.g.state == 'idle', 'g idle at t=25; got ' .. tostring(res.g.state))
    Test.expect(res.g.msg == '[idle]', 'msg is [idle]; got ' .. tostring(res.g.msg))
    Test.expect(res.g.t == 20, 'event time is 20; got ' .. tostring(res.g.t))
end)

Test.it('playhead exactly on an event: that event counts', function()
    local res = ComputePlayerStatesAt(20, ps_states, ps_no_data, ps_muted)
    Test.expect(res.g.state == 'idle', 'g idle exactly at t=20')
end)

Test.it('playhead after last event keeps its state', function()
    local res = ComputePlayerStatesAt(99, ps_states, ps_no_data, ps_muted)
    Test.expect(res.g.state == 'active', 'g active after last event')
    Test.expect(res.g.msg == '[intense]', 'msg is [intense]; got ' .. tostring(res.g.msg))
end)

Test.it('unmuted instrument with no timeline defaults to active', function()
    local res = ComputePlayerStatesAt(15, ps_states, ps_no_data, ps_muted)
    Test.expect(res.b.state == 'active', 'b defaults to active')
    Test.expect(res.v.state == 'active', 'v defaults to active')
end)

Test.it('all five instruments are always present in the result', function()
    local res = ComputePlayerStatesAt(0, {}, {}, {})
    for _, letter in ipairs({ 'b', 'g', 'd', 'k', 'v' }) do
        Test.expect(res[letter] ~= nil, 'missing letter ' .. letter)
        Test.expect(res[letter].state == 'active', letter .. ' defaults to active')
    end
end)

----------------------------------------------------------------------
Test.section('PickPriorityCameraEvent')

-- Groups mirror what ui_venue_preview.lua's _group_at builds: the camera events
-- stacked on one tick, in MIDI order. muted[letter]=true means that instrument
-- is muted or absent (GetMutedInstruments' convention).
local function Grp(...)
    local g = {}
    for _, msg in ipairs({ ... }) do g[#g + 1] = { msg = msg, ppq = 960 } end
    return g
end

Test.it('single event group returns that event', function()
    local got = PickPriorityCameraEvent(Grp('[coop_g_near]'), {})
    Test.expect(got and got.msg == '[coop_g_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('picks highest priority, not last in MIDI order', function()
    -- coop_all_* is the most generic shot; a duo is far more specific. The old
    -- preview took the last event in the group, which would answer coop_all_near.
    local got = PickPriorityCameraEvent(Grp('[coop_gv_near]', '[coop_all_near]'), {})
    Test.expect(got and got.msg == '[coop_gv_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('picks highest priority regardless of position in the group', function()
    local got = PickPriorityCameraEvent(
        Grp('[coop_all_far]', '[coop_bg_near]', '[coop_d_near]'), {})
    Test.expect(got and got.msg == '[coop_bg_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('directed cut beats any coop shot in the group', function()
    local got = PickPriorityCameraEvent(Grp('[directed_all]', '[coop_gk_near]'), {})
    Test.expect(got and got.msg == '[directed_all]', 'got ' .. tostring(got and got.msg))
end)

Test.it('skips a shot needing a muted instrument for a lower-ranked fit', function()
    -- Keys absent: the bass/keys duo cannot play, so the generic shot wins even
    -- though it ranks far below it.
    local got = PickPriorityCameraEvent(Grp('[coop_all_near]', '[coop_bk_near]'), { k = true })
    Test.expect(got and got.msg == '[coop_all_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('companion stacking resolves to the shot that fits the lineup', function()
    -- What the generator emits for a keys/guitar/bass swap band (FindCompanion).
    local group = Grp('[coop_bg_near]', '[coop_k_near]')
    local with_keys = PickPriorityCameraEvent(group, { g = true })
    Test.expect(with_keys and with_keys.msg == '[coop_k_near]',
        'guitar absent -> keys shot; got ' .. tostring(with_keys and with_keys.msg))
    local with_guitar = PickPriorityCameraEvent(group, { k = true })
    Test.expect(with_guitar and with_guitar.msg == '[coop_bg_near]',
        'keys absent -> bass/guitar shot; got ' .. tostring(with_guitar and with_guitar.msg))
end)

Test.it('single keys shot wins over a valid duo shot (documented exception)', function()
    local got = PickPriorityCameraEvent(Grp('[coop_bg_near]', '[coop_k_near]'), {})
    Test.expect(got and got.msg == '[coop_k_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('returns nil when nothing in the group fits', function()
    local got = PickPriorityCameraEvent(Grp('[coop_bk_near]', '[directed_keys]'), { k = true })
    Test.expect(got == nil, 'expected nil; got ' .. tostring(got and got.msg))
end)

Test.it('shots needing nobody are never filtered out', function()
    -- [coop_all_*] / [coop_front_*] / [directed_all*] require no instrument.
    local got = PickPriorityCameraEvent(Grp('[coop_front_near]'),
                                        { b = true, g = true, k = true })
    Test.expect(got and got.msg == '[coop_front_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('unranked event loses to a ranked one but wins when it is the only fit', function()
    local mixed = PickPriorityCameraEvent(Grp('[coop_made_up]', '[coop_d_near]'), {})
    Test.expect(mixed and mixed.msg == '[coop_d_near]',
        'ranked shot should win; got ' .. tostring(mixed and mixed.msg))
    local alone = PickPriorityCameraEvent(Grp('[coop_made_up]'), {})
    Test.expect(alone and alone.msg == '[coop_made_up]',
        'lone unranked shot still shows; got ' .. tostring(alone and alone.msg))
end)

Test.it('nil muted table means every shot fits', function()
    local got = PickPriorityCameraEvent(Grp('[coop_all_near]', '[coop_bk_near]'), nil)
    Test.expect(got and got.msg == '[coop_bk_near]', 'got ' .. tostring(got and got.msg))
end)

Test.it('nil group returns nil', function()
    Test.expect(PickPriorityCameraEvent(nil, {}) == nil, 'expected nil')
end)

----------------------------------------------------------------------
Test.section('KeyframeSubdivQN')

Test.it('mode 0 (every beat) -> 1.0 QN', function()
    Test.expect(KeyframeSubdivQN(0) == 1.0, 'mode 0 -> 1.0')
end)

Test.it('mode 1 (every half beat) -> 0.5 QN', function()
    Test.expect(KeyframeSubdivQN(1) == 0.5, 'mode 1 -> 0.5')
end)

Test.it('mode 2 (every quarter beat) -> 0.25 QN', function()
    Test.expect(KeyframeSubdivQN(2) == 0.25, 'mode 2 -> 0.25')
end)

Test.it('unrecognized mode falls back to 1.0 QN', function()
    Test.expect(KeyframeSubdivQN(99) == 1.0, 'unknown mode -> 1.0')
    Test.expect(KeyframeSubdivQN(nil) == 1.0, 'nil mode -> 1.0')
end)
