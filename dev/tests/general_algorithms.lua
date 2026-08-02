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

----------------------------------------------------------------------
-- BuildShapeGemMap (actions_guitar.lua): chord-quality-aware gem mapping,
-- by pitch class rather than physical note count. When a group has more
-- distinct shapes than available combos, the overflow shapes are assigned
-- by conflict-minimizing search over the ACTUAL event sequence - two
-- shapes that are genuinely back-to-back anywhere in the passage only
-- share a combo when truly unavoidable (marked in the third return
-- value, `shared`), not just because they're pitch-adjacent.
-- S.mc_gtr_allow_14 defaults to true (defaults.lua), so pool2 = POOLS[2].
Test.section('BuildShapeGemMap')

local function ev(s, pitches)
    return { s = s, e = s + 0.1, pitches = pitches }
end

local function dump_gems(gems)
    return '{' .. table.concat(gems, ',') .. '}'
end

local function power_chord(root)
    return { root, root + 7, root + 12 }
end

Test.it('power chord dyad (interval 7) always gets a 1-3 spread', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 52 }) }, 3)
    local gems = shape_gems['45,52']
    Test.expect(gems ~= nil, 'shape assigned a combo')
    Test.expect(gems[2] - gems[1] == 2, '1-3 spread (index gap 2); got gap ' .. tostring(gems[2] - gems[1]))
end)

Test.it('two different power chords (no overflow) each claim a unique combo in pitch order', function()
    local _, shape_gems, shared = BuildShapeGemMap({ ev(0, { 45, 52 }), ev(1, { 40, 47 }) }, 3)
    local a, b = shape_gems['45,52'], shape_gems['40,47']
    -- pool2_by_w[2] = {{0,2},{1,3},{2,4}} (G+Y, R+B, Y+O); N=2 <= 3 combos,
    -- so no overflow - each shape claims a unique slot in ascending-pitch
    -- order: lower (40,47) -> G+Y, higher (45,52) -> R+B.
    Test.expect(b[1] == 0 and b[2] == 2, 'lower shape -> G+Y; got ' .. dump_gems(b))
    Test.expect(a[1] == 1 and a[2] == 3, 'higher shape -> R+B; got ' .. dump_gems(a))
    Test.expect(not shared['45,52'] and not shared['40,47'], 'neither shape is marked shared')
end)

Test.it('reproduces the reported real passage: only the genuine overflow shape wraps', function()
    -- "- - 7 7 5 -" / "3 3 1" / "5 5 3" / "7 7 5" / "3 3 1" / "10 10 8"
    -- horizontal tab, in that exact order (roots 50,46,48,50,46,53). Only
    -- 3 combos exist for a 1-3 spread, but there are 4 distinct shapes;
    -- the expected/confirmed mapping is root46->G+Y, root48->R+B,
    -- root50->Y+O, root53->Y+O (*Wrap) - the highest-pitched shape reuses
    -- the shape it's actually adjacent to at the end of the passage
    -- (root46, already G+Y) is avoided in favor of root50's Y+O, which
    -- root53 is NOT adjacent to anywhere in the sequence.
    local events = {
        ev(0, power_chord(50)), ev(1, power_chord(46)), ev(2, power_chord(48)),
        ev(3, power_chord(50)), ev(4, power_chord(46)), ev(5, power_chord(53)),
    }
    local _, shape_gems, shared = BuildShapeGemMap(events, 3)
    local g46 = shape_gems[table.concat(power_chord(46), ',')]
    local g48 = shape_gems[table.concat(power_chord(48), ',')]
    local g50 = shape_gems[table.concat(power_chord(50), ',')]
    local g53 = shape_gems[table.concat(power_chord(53), ',')]
    Test.expect(g46[1] == 0 and g46[2] == 2, 'root46 -> G+Y; got ' .. dump_gems(g46))
    Test.expect(g48[1] == 1 and g48[2] == 3, 'root48 -> R+B; got ' .. dump_gems(g48))
    Test.expect(g50[1] == 2 and g50[2] == 4, 'root50 -> Y+O; got ' .. dump_gems(g50))
    Test.expect(g53[1] == 2 and g53[2] == 4, 'root53 -> Y+O (reuses root50, not adjacent to it); got ' .. dump_gems(g53))
    local k46, k48, k50, k53 = table.concat(power_chord(46), ','), table.concat(power_chord(48), ','),
        table.concat(power_chord(50), ','), table.concat(power_chord(53), ',')
    Test.expect(not shared[k46] and not shared[k48] and not shared[k50],
        'the 3 shapes that claimed a slot first-come are never marked shared')
    Test.expect(shared[k53], 'only the genuine overflow shape (root53) is marked shared')
end)

Test.it('overflow shape avoids reusing the combo of the shape it is actually adjacent to', function()
    -- 4 power chords played in strict ascending order A,B,C,D - naive
    -- "clamp to the last slot" would give D the SAME combo as C (its
    -- immediate predecessor), a real back-to-back collision. Conflict
    -- minimization must pick a different, non-adjacent slot for D.
    local events = {
        ev(0, power_chord(40)), ev(1, power_chord(42)),
        ev(2, power_chord(44)), ev(3, power_chord(46)),
    }
    local _, shape_gems, shared = BuildShapeGemMap(events, 3)
    local kC, kD = table.concat(power_chord(44), ','), table.concat(power_chord(46), ',')
    local gC, gD = shape_gems[kC], shape_gems[kD]
    Test.expect(not (gC[1] == gD[1] and gC[2] == gD[2]),
        'D does not collide with its actual neighbor C; C=' .. dump_gems(gC) .. ' D=' .. dump_gems(gD))
    Test.expect(shared[kD], 'D (the overflow shape) is marked shared')
end)

Test.it('past MAX_CONFLICT_SHAPES distinct shapes, falls back to plain clamp-to-last (safety cap)', function()
    -- 250 distinct power chords (> the 200-shape cap), one semitone apart,
    -- played in ascending sequence - a pathological case (e.g. the wrong
    -- source track selected) that must stay fast and bounded rather than
    -- running the O(N^2)-ish conflict search.
    local events = {}
    for i = 1, 250 do
        events[i] = ev(i, power_chord(20 + i))
    end
    local _, shape_gems, shared = BuildShapeGemMap(events, 3)
    local all_clamped = true
    for i = 4, 250 do  -- ranks 1-3 claim unique slots; 4+ are overflow
        local key = table.concat(power_chord(20 + i), ',')
        local gems = shape_gems[key]
        if not (gems[1] == 2 and gems[2] == 4 and shared[key]) then
            all_clamped = false
        end
    end
    Test.expect(all_clamped, 'every overflow shape clamps to the last slot (Y+O) and is marked shared')
end)

Test.it('perfect fourth (interval 5, ambiguous width) falls back to legacy pool cycling', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 50 }) }, 3)
    local gems = shape_gems['45,50']
    Test.expect(gems ~= nil, 'shape assigned a combo')
    local spread = gems[2] - gems[1]
    Test.expect(spread >= 1 and spread <= 3, 'spread within legacy pool2 range; got ' .. tostring(spread))
end)

Test.it('compound interval (> 1 octave) resolves to G+O directly', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 40, 64 }) }, 3)
    local gems = shape_gems['40,64']
    Test.expect(gems[1] == 0 and gems[2] == 4, 'G+O for compound interval; got ' ..
        tostring(gems[1]) .. ',' .. tostring(gems[2]))
end)

Test.it('3-physical-note power chord (root+5th+octave, 2 pitch classes) ' ..
         'collapses to a 2-gem 1-3 combo, not a 3-note chord', function()
    -- "- - - 7 7 5" horizontal (e,B,G unplayed; D7=57, A7=52, E5=45) - the
    -- exact shape reported as misclassified: 3 physical notes, but only 2
    -- distinct pitch classes (45 and 52 are a 7th apart, 57 is 45+12).
    -- rock_band_music_theory_helper_vkr's GUITAR_CHORDS table documents
    -- this exact shape's rb_mapping as '1-3', not a 3-note chord.
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 52, 57 }) }, 3)
    local gems = shape_gems['45,52,57']
    Test.expect(gems ~= nil, 'shape assigned a combo')
    Test.expect(#gems == 2, 'collapses to 2 gems, not 3; got ' .. #gems)
    Test.expect(gems[2] - gems[1] == 2, '1-3 spread (index gap 2); got gap ' .. tostring(gems[2] - gems[1]))
end)

Test.it('ChordQualityLabel recognizes the same 3-physical-note power chord', function()
    local label = ChordQualityLabel({ 45, 52, 57 })
    Test.expect(label:match('Power chord') ~= nil, 'labels it a power chord; got ' .. label)
end)

Test.it('a genuine 3-distinct-pitch-class shape (real triad) still gets a 3-note chord', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 40, 45, 50 }) }, 3)
    local gems = shape_gems['40,45,50']
    Test.expect(#gems == 3, 'true 3-pitch-class chord stays a 3-note chord; got ' .. #gems)
end)

Test.it('single-note shapes are unaffected (unchanged pool cycling)', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 60 }) }, 3)
    Test.expect(shape_gems['60'][1] == 0, 'lone single-note shape -> gem 0')
end)
