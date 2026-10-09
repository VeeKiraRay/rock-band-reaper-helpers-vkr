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

----------------------------------------------------------------------
-- BuildShapeGemMap (actions_guitar.lua): chord-quality-aware gem mapping,
-- by pitch class rather than physical note count. When a group has more
-- distinct shapes than available combos, the overflow shapes are assigned
-- by conflict-minimizing search over the ACTUAL event sequence - two
-- shapes that are genuinely back-to-back anywhere in the passage only
-- share a combo when truly unavoidable (marked in the third return
-- value, `shared`), not just because they're pitch-adjacent.
-- max_chord/allow_14 are explicit arguments, not read from S. These cases
-- drive the Guitar tab converter's configuration (max_chord=3, allow_14=true
-- so pool2 = POOLS[2]); the Tab Input guide's configuration (max_chord=nil,
-- i.e. no compression at all) has its own section further below.
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
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 52 }) }, 3, true)
    local gems = shape_gems['45,52']
    Test.expect(gems ~= nil, 'shape assigned a combo')
    Test.expect(gems[2] - gems[1] == 2, '1-3 spread (index gap 2); got gap ' .. tostring(gems[2] - gems[1]))
end)

Test.it('two different power chords (no overflow) each claim a unique combo in pitch order', function()
    local _, shape_gems, shared = BuildShapeGemMap({ ev(0, { 45, 52 }), ev(1, { 40, 47 }) }, 3, true)
    local a, b = shape_gems['45,52'], shape_gems['40,47']
    -- pool2_by_w[2] = {{0,2},{1,3},{2,4}} (G+Y, R+B, Y+O); N=2 <= 3 combos,
    -- so no overflow - each shape claims a unique slot in ascending-pitch
    -- order: lower (40,47) -> G+Y, higher (45,52) -> R+B.
    Test.expect(b[1] == 0 and b[2] == 2, 'lower shape -> G+Y; got ' .. dump_gems(b))
    Test.expect(a[1] == 1 and a[2] == 3, 'higher shape -> R+B; got ' .. dump_gems(a))
    Test.expect(not shared['45,52'] and not shared['40,47'], 'neither shape is marked shared')
end)

Test.it('reproduces the reported real passage: only the genuine overflow shape wraps', function()
    -- "- 5 7 7 - -" / "1 3 3" / "3 5 5" / "5 7 7" / "1 3 3" / "8 10 10"
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
    local _, shape_gems, shared = BuildShapeGemMap(events, 3, true)
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
    local _, shape_gems, shared = BuildShapeGemMap(events, 3, true)
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
    local _, shape_gems, shared = BuildShapeGemMap(events, 3, true)
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
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 50 }) }, 3, true)
    local gems = shape_gems['45,50']
    Test.expect(gems ~= nil, 'shape assigned a combo')
    local spread = gems[2] - gems[1]
    Test.expect(spread >= 1 and spread <= 3, 'spread within legacy pool2 range; got ' .. tostring(spread))
end)

Test.it('compound interval (> 1 octave) resolves to G+O directly', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 40, 64 }) }, 3, true)
    local gems = shape_gems['40,64']
    Test.expect(gems[1] == 0 and gems[2] == 4, 'G+O for compound interval; got ' ..
        tostring(gems[1]) .. ',' .. tostring(gems[2]))
end)

Test.it('3-physical-note power chord (root+5th+octave, 2 pitch classes) ' ..
         'collapses to a 2-gem 1-3 combo, not a 3-note chord', function()
    -- "5 7 7 - - -" horizontal (G,B,e unplayed; E5=45, A7=52, D7=57) - the
    -- exact shape reported as misclassified: 3 physical notes, but only 2
    -- distinct pitch classes (45 and 52 are a 7th apart, 57 is 45+12).
    -- rock_band_music_theory_helper_vkr's GUITAR_CHORDS table documents
    -- this exact shape's rb_mapping as '1-3', not a 3-note chord.
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 45, 52, 57 }) }, 3, true)
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
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 40, 45, 50 }) }, 3, true)
    local gems = shape_gems['40,45,50']
    Test.expect(#gems == 3, 'true 3-pitch-class chord stays a 3-note chord; got ' .. #gems)
end)

Test.it('single-note shapes are unaffected (unchanged pool cycling)', function()
    local _, shape_gems = BuildShapeGemMap({ ev(0, { 60 }) }, 3, true)
    Test.expect(shape_gems['60'][1] == 0, 'lone single-note shape -> gem 0')
end)

Test.it('BuildShapeGemMap never mutates the caller\'s ev.pitches', function()
    -- CompressChord returns its argument unchanged when the chord already
    -- fits, and is skipped entirely when max_chord is nil - so sorting its
    -- result in place used to reorder the event the caller still owns (and
    -- goes on to print via PitchLabel). SortedChordPitches copies first.
    -- Deliberately descending, i.e. NOT the order tab input produces - the
    -- point is that whatever order the caller hands over survives untouched.
    local events = { ev(0, { 64, 60, 55, 52, 48, 43 }) }
    BuildShapeGemMap(events, nil, true)
    BuildShapeGemMap(events, 3, true)
    Test.expect(table.concat(events[1].pitches, ',') == '64,60,55,52,48,43',
        'ev.pitches keeps its original order; got ' .. table.concat(events[1].pitches, ','))
end)

----------------------------------------------------------------------
-- BuildShapeGemMap: Tab Input guide configuration (max_chord = nil)
----------------------------------------------------------------------
-- The Tab Input tab writes nothing to the project, so nothing needs
-- reducing: it passes max_chord=nil and lets GuitarSuggestRBMapping derive
-- the gem count from distinct PITCH CLASSES on the full shape. These cases
-- are the five tab shapes that exposed the old index-based compression -
-- each one's expected result is what the Music Theory helper's Shape Search
-- reports for the same shape, which is the behaviour the guide must match.
Test.section('BuildShapeGemMap (Tab Input guide, uncompressed)')

local function guide_gems(tab)
    local events = ParseTabHorizontal(tab)
    local all_shapes, shape_gems = BuildShapeGemMap(events, nil, true)
    local sorted = SortedChordPitches(events[1].pitches)
    return shape_gems[table.concat(sorted, ',')], all_shapes, sorted
end

Test.it('open C/G (3 3 2 0 1 0) is a 3-note chord, not a sixth dyad', function()
    -- Old behaviour kept pitches[1], pitches[mid], pitches[#pitches] =
    -- E3+E2+G1: both C's discarded, one pitch class doubled, leaving a
    -- major sixth -> width 1-3. All three pitch classes must survive.
    local gems, _, sorted = guide_gems('3 3 2 0 1 0')
    Test.expect(#sorted == 6, 'shape is not compressed; got ' .. #sorted .. ' pitches')
    Test.expect(#gems == 3, '3 gems for a real triad; got ' .. #gems .. ' ' .. dump_gems(gems))
    Test.expect(GuitarClassifyChordType(sorted) == 'Major triad',
        'classified as a major triad; got ' .. GuitarClassifyChordType(sorted))
end)

Test.it('open D (- 0 0 2 3 2) is a 3-note chord, not a sixth dyad', function()
    -- Old behaviour kept F#3+A2+A1 - every D, the root, discarded.
    local gems, _, sorted = guide_gems('- 0 0 2 3 2')
    Test.expect(#gems == 3, '3 gems for a real triad; got ' .. #gems .. ' ' .. dump_gems(gems))
    Test.expect(GuitarClassifyChordType(sorted) == 'Major triad',
        'classified as a major triad; got ' .. GuitarClassifyChordType(sorted))
end)

Test.it('both G5 voicings resolve to the same 2-gem 1-3 power chord', function()
    -- The regression: "3 x 0 0 3 3" (G,D,G,D,G) used to compress to
    -- G1+G2+G3 - a single pitch class, no suggestable width - and landed in
    -- the 3-note fallback pool, while the identical chord voiced as
    -- "3 x 0 0 - -" was correctly 1-3. Same chord, opposite answers.
    for _, tab in ipairs({ '3 x 0 0 - -', '3 x 0 0 3 3' }) do
        local gems, _, sorted = guide_gems(tab)
        Test.expect(#gems == 2, tab .. ': 2 gems; got ' .. #gems .. ' ' .. dump_gems(gems))
        Test.expect(gems[2] - gems[1] == 2, tab .. ': 1-3 spread; got gap ' .. (gems[2] - gems[1]))
        Test.expect(GuitarClassifyChordType(sorted) == 'Power chord',
            tab .. ': classified as a power chord; got ' .. GuitarClassifyChordType(sorted))
    end
end)

Test.it('all six open strings (0 0 0 0 0 0) stay a 3-note chord', function()
    local gems, all_shapes, sorted = guide_gems('0 0 0 0 0 0')
    Test.expect(#gems == 3, '3 gems; got ' .. #gems .. ' ' .. dump_gems(gems))
    Test.expect(#all_shapes[table.concat(sorted, ',')].pitches == 6,
        'all 6 pitches kept in the shape record')
end)

Test.it('4-note and 6-note fallback shapes share one conflict group', function()
    -- Both draw from POOLS[3], so they must compete in a single
    -- AssignByConflict group - bucketed by min(sz,3), not raw sz. Keyed by
    -- raw sz they were assigned independently and could collide silently.
    -- Two shapes, no overflow (POOLS[3] has 7 combos) -> distinct combos.
    local events = {
        ev(0, { 40, 45, 50, 55 }),          -- 4 notes, 4 pitch classes
        ev(1, { 52, 57, 62, 67, 71, 76 }),  -- 6 notes, 4 pitch classes
    }
    local _, shape_gems, shared = BuildShapeGemMap(events, nil, true)
    local a = shape_gems['40,45,50,55']
    local b = shape_gems['52,57,62,67,71,76']
    Test.expect(a and b, 'both shapes assigned a combo')
    Test.expect(#a == 3 and #b == 3, 'both get 3 gems from POOLS[3]')
    Test.expect(table.concat(a, ',') ~= table.concat(b, ','),
        'the two shapes get different combos; got ' .. dump_gems(a) .. ' and ' .. dump_gems(b))
    Test.expect(not shared['40,45,50,55'] and not shared['52,57,62,67,71,76'],
        'neither is marked shared - there was no overflow')
end)

----------------------------------------------------------------------
-- Difficulty > Generate planner (difficulty_generate_5lane.lua): the Hard keep cap
----------------------------------------------------------------------
Test.section('Generate planner - Hard keep cap')

-- 64 bars of steady 8ths at 80 BPM, two notes per color (G G R R Y Y B B): the Hard
-- gap admits every 8th, so the 95% cap does all the thinning.
local function SteadyEighths(bars)
    local events, colors = {}, { 0, 0, 1, 1, 2, 2, 3, 3 }
    for b = 0, bars - 1 do
        for k = 0, 7 do
            local qn = b * 4 + k * 0.5
            events[#events + 1] = { qn = qn, qn_e = qn + 0.25, offs = { colors[k + 1] },
                                    bpm = 80, down = k == 0, bar_qn = k * 0.5 }
        end
    end
    return events
end

-- bar index -> sorted list of kept bar positions
local function KeptByBar(out)
    local by_bar = {}
    for _, ev in ipairs(out) do
        local b = math.floor(ev.qn / 4 + 1e-6)
        by_bar[b] = by_bar[b] or {}
        table.insert(by_bar[b], ('%.2f'):format(ev.qn - b * 4))
    end
    return by_bar
end

Test.it('the cap thins the same bar positions in every bar, not just the start of the song', function()
    local events = SteadyEighths(64)
    local out = Gen5PlanTier('gb', 'H', events)
    Test.expect(#out < #events, ('Hard kept all %d onsets'):format(#events))
    Test.expect(#out <= math.floor(0.95 * #events), ('Hard kept %d of %d, above the 95%% cap'):format(#out, #events))
    local by_bar = KeptByBar(out)
    local first = table.concat(by_bar[0] or {}, ' ')
    for b = 1, 63 do
        local this = table.concat(by_bar[b] or {}, ' ')
        Test.expect(this == first, ('bar %d keeps [%s] but bar 0 keeps [%s]'):format(b, this, first))
    end
end)

Test.it('the cap removes the and of 4 first - the off-beat official Hard drops most', function()
    local out = Gen5PlanTier('gb', 'H', SteadyEighths(16))
    local kept = ' ' .. table.concat(KeptByBar(out)[0] or {}, ' ') .. ' '
    Test.expect(not kept:find(' 3.50 ', 1, true), 'the and of 4 (3.50) survived: [' .. kept .. ']')
    Test.expect(kept:find(' 0.00 ', 1, true) and kept:find(' 1.00 ', 1, true)
        and kept:find(' 2.00 ', 1, true) and kept:find(' 3.00 ', 1, true), 'a beat was removed: [' .. kept .. ']')
end)

local function Ev(qn, len, offs, bpm, bar_start)
    return { qn = qn, qn_e = qn + len, offs = offs, bpm = bpm,
             down = math.abs(qn - bar_start) < 1e-6, bar_qn = qn - bar_start }
end

Test.it('a busy bar of 8ths the gap left whole loses its and of 4, even when the song-wide cap is met', function()
    -- Four bars of 16ths (the Hard gap thins them, so the song is already far under the
    -- 95% cap), then the pojat_lemmikkih bar: G O G Y R B R in 8ths at 157 BPM.
    local events, bpm = {}, 157
    for b = 0, 3 do
        for k = 0, 15 do events[#events + 1] = Ev(b * 4 + k * 0.25, 0.2, { k % 5 }, bpm, b * 4) end
    end
    local pattern = { { 0, 0 }, { 1, 4 }, { 1.5, 0 }, { 2, 2 }, { 2.5, 1 }, { 3, 3 }, { 3.5, 1 } }
    for _, p in ipairs(pattern) do events[#events + 1] = Ev(16 + p[1], 0.2, { p[2] }, bpm, 16) end
    local kept = ' ' .. table.concat(KeptByBar(Gen5PlanTier('gb', 'H', events))[4] or {}, ' ') .. ' '
    Test.expect(kept == ' 0.00 1.00 1.50 2.00 2.50 3.00 ', 'expected only the and of 4 removed, kept: [' .. kept .. ']')
end)

Test.it('the same rhythm reduces to the same onsets on guitar, bass and keys', function()
    -- Eight bars mixing 16ths, 8ths, quarters and a sustain, given three ways: guitar
    -- single notes, bass on other colors, keys as chords. Only onsets are compared -
    -- chords and colors are reduced separately and may differ.
    local rhythm = {}
    for b = 0, 7 do
        local base = b * 4
        if b % 2 == 0 then
            for k = 0, 7 do rhythm[#rhythm + 1] = { base + k * 0.25, 0.2 } end
            for k = 2, 3 do rhythm[#rhythm + 1] = { base + k, 0.4 } end
        else
            for k = 0, 5 do rhythm[#rhythm + 1] = { base + k * 0.5, 0.4 } end
            rhythm[#rhythm + 1] = { base + 3, 0.9 }
        end
    end
    local function Build(color_fn)
        local evs = {}
        for i, r_ in ipairs(rhythm) do
            evs[i] = Ev(r_[1], r_[2], color_fn(i), 128, math.floor(r_[1] / 4) * 4)
        end
        return evs
    end
    local parts = {
        { 'gb', Build(function(i) return { i % 5 } end) },
        { 'gb', Build(function(i) return { (i * 3) % 5 } end) },
        { 'k5', Build(function(i) return i % 3 == 0 and { 0, 2, 4 } or { i % 4, (i % 4) + 1 } end) },
    }
    local onsets = {}
    for p, part in ipairs(parts) do
        local upper = part[2]
        onsets[p] = {}
        for _, dl in ipairs({ 'H', 'M', 'E' }) do
            upper = Gen5PlanTier(part[1], dl, upper)
            local qs = {}
            for _, ev in ipairs(upper) do qs[#qs + 1] = ('%.3f'):format(ev.qn) end
            onsets[p][dl] = table.concat(qs, ' ')
        end
    end
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        Test.expect(onsets[1][dl] == onsets[2][dl], dl .. ': guitar and bass differ\n' .. onsets[1][dl] .. '\n' .. onsets[2][dl])
        Test.expect(onsets[1][dl] == onsets[3][dl], dl .. ': guitar and keys differ\n' .. onsets[1][dl] .. '\n' .. onsets[3][dl])
    end
end)

Test.it('identical repeats keep identical sustains despite tempo-map rounding', function()
    -- The pojat_lemmikkih intro: a Green held 5/32 then Orange on beat 2, four times.
    -- The Hard gap leaves the Green exactly 1/8 long, on the cut-back boundary. Converting
    -- through a tempo map leaves float noise; a few 1e-9 either side used to decide
    -- whether a bar kept its sustain.
    local events, noise = {}, { -1e-9, 1e-9, -1e-9, 1e-9 }
    for b = 0, 3 do
        local base = b * 4
        events[#events + 1] = Ev(base, 0.625 + noise[b + 1], { 0 }, 157, base)
        events[#events + 1] = Ev(base + 1 + noise[4 - b], 0.125, { 4 }, 157, base)
        events[#events + 1] = Ev(base + 2, 0.125, { 2 }, 157, base)
    end
    local out = Gen5PlanTier('gb', 'H', events)
    local lens = {}
    for _, ev in ipairs(out) do
        if ev.down then lens[#lens + 1] = ('%.3f'):format(ev.qn_e - ev.qn) end
    end
    Test.expect(table.concat(lens, ' ') == '0.500 0.500 0.500 0.500',
        'the four repeats differ: ' .. table.concat(lens, ' '))
end)

Test.it('Easy keeps a held note over a short note when only one fits', function()
    -- Medium: G on bar 1, short Y on the bar line of bar 2, B held from beat 2, G on bar 3,
    -- at 157 BPM. The Easy gap fits only one of Y and B; the held B is kept.
    local events = {
        Ev(0, 0.125, { 0 }, 157, 0),
        Ev(4, 0.125, { 2 }, 157, 4),
        Ev(5, 2.5,   { 3 }, 157, 4),
        Ev(8, 0.125, { 0 }, 157, 8),
    }
    local kept = {}
    for _, ev in ipairs(Gen5PlanTier('gb', 'E', events)) do kept[#kept + 1] = ('%.0f'):format(ev.qn) end
    Test.expect(table.concat(kept, ' ') == '0 5 8', 'expected 0 5 8 (held B kept), got ' .. table.concat(kept, ' '))
end)

-- The pojat_lemmikkih keys part: a held R, then a bar of three short notes a dotted
-- quarter apart (beat 1, the and of 2, beat 4), then held notes again. top_first = true
-- gives O B Y, false gives Y B O.
local function SparseKeys(top_first)
    local c = top_first and { 4, 3, 2 } or { 2, 3, 4 }
    return {
        Ev(0,   3.6,  { 1 },    157, 0),
        Ev(4,   0.25, { c[1] }, 157, 4),
        Ev(5.5, 0.25, { c[2] }, 157, 4),
        Ev(7,   0.25, { c[3] }, 157, 4),
        Ev(8,   3.6,  { 1 },    157, 8),
        Ev(12,  3.6,  { 0 },    157, 12),
    }
end

local function Shape(out)
    local C = { [0] = 'G', 'R', 'Y', 'B', 'O' }
    local parts = {}
    for _, ev in ipairs(out) do
        local cs = {}
        for _, o in ipairs(ev.offs) do cs[#cs + 1] = C[o] end
        parts[#parts + 1] = ('%g:%s'):format(ev.qn, table.concat(cs))
    end
    return table.concat(parts, ' ')
end

Test.it('a sparse bar keeps its isolated off-beat on Hard; a Medium that would copy Hard drops it', function()
    -- Nothing here is closer than Medium's quarter-note gap, so Medium would keep every
    -- onset; above offbeat_fallback_keep it drops its isolated off-beats instead.
    local hard = Gen5PlanTier('k5', 'H', SparseKeys(true))
    local med, mlog = Gen5PlanTier('k5', 'M', hard)
    local h, m = Shape(hard), Shape(med)
    Test.expect(h:find('5.5:', 1, true) ~= nil, 'Hard lost the isolated and of 2: ' .. h)
    Test.expect(#hard == 6, 'Hard should keep all 6 onsets: ' .. h)
    Test.expect(m:find('5.5:', 1, true) == nil, 'Medium kept the isolated and of 2: ' .. m)
    Test.expect(#med == 5 and mlog.offbeats_dropped == 1, 'Medium should drop only that one: ' .. m)
end)

Test.it('a Hard that barely thinned moves each bar down to top out at Blue', function()
    local hard, log = Gen5PlanTier('k5', 'H', SparseKeys(true))
    Test.expect(log.color_fallback, 'the color fallback did not run')
    Test.expect(Shape(hard) == '0:R 4:B 5.5:Y 7:R 8:R 12:G', 'O B Y bar: ' .. Shape(hard))
    local hard2 = Gen5PlanTier('k5', 'H', SparseKeys(false))
    Test.expect(Shape(hard2) == '0:R 4:R 5.5:Y 7:B 8:R 12:G', 'Y B O bar: ' .. Shape(hard2))
    -- Medium inherits the shifted colors.
    Test.expect(Shape(Gen5PlanTier('k5', 'M', hard)) == '0:R 4:B 7:R 8:R 12:G',
        'Medium: ' .. Shape(Gen5PlanTier('k5', 'M', hard)))
end)

-- Bars of eight straight 8ths at a given tempo.
local function Eighths(bars, bpm)
    local events = {}
    for b = 0, bars - 1 do
        for k = 0, 7 do events[#events + 1] = Ev(b * 4 + k * 0.5, 0.25, { k % 5 }, bpm, b * 4) end
    end
    return events
end

-- Every bar's kept positions, checked equal to want (e.g. '0.00 0.50 1.00 ...').
local function ExpectEveryBar(out, bars, want, what)
    local by_bar = KeptByBar(out)
    for b = 0, bars - 1 do
        local got = table.concat(by_bar[b] or {}, ' ')
        Test.expect(got == want, ('%s, bar %d: kept [%s], expected [%s]'):format(what, b, got, want))
    end
end

Test.it('fast song (210 BPM): Hard keeps two groups of three, not just the beats', function()
    -- Before the gap cap, 0.15 s exceeded a 1/8 note above 200 BPM and every off-beat
    -- went (1 . 2 . 3 . 4 .). Official Hard does that to 2-4% of such bars.
    ExpectEveryBar(Gen5PlanTier('gb', 'H', Eighths(8, 210)), 8,
        '0.00 0.50 1.00 2.00 2.50 3.00', 'Hard, Auto at 210 BPM')
    ExpectEveryBar(Gen5PlanTier('gb', 'H', Eighths(8, 210), { busy_drop = 1 }), 8,
        '0.00 0.50 1.00 1.50 2.00 2.50 3.00', 'Hard, Drop 1 at 210 BPM')
    ExpectEveryBar(Gen5PlanTier('gb', 'H', Eighths(8, 120)), 8,
        '0.00 0.50 1.00 1.50 2.00 2.50 3.00', 'Hard, Auto at 120 BPM')
end)

Test.it('Drop 2 takes the fourth note of each half bar, and nothing from a half bar without one', function()
    -- Seven 8ths, no and of 4: only the and of 2 goes (the doc's rule), not the and of 1.
    local events = {}
    for b = 0, 3 do
        for k = 0, 6 do events[#events + 1] = Ev(b * 4 + k * 0.5, 0.25, { k % 5 }, 210, b * 4) end
    end
    ExpectEveryBar(Gen5PlanTier('gb', 'H', events), 4, '0.00 0.50 1.00 2.00 2.50 3.00',
        'Hard, Auto at 210 BPM, bar without the and of 4')
end)

-- One bar from a slot pattern of 8 eighths ('1 1& 2 2& 3 3& 4 4&'): each cell is a color
-- string ('GR'), '.' for a rest, a trailing '~' for a sustain. Repeated `bars` times at
-- `bpm`, so the song-wide cap does not interfere.
local function SlotBars(cells, bars, bpm)
    local L = { G = 0, R = 1, Y = 2, B = 3, O = 4 }
    local events = {}
    for b = 0, bars - 1 do
        for k, cell in ipairs(cells) do
            if cell ~= '.' then
                local offs = {}
                for c in cell:gmatch('[GRYBO]') do offs[#offs + 1] = L[c] end
                local qn = b * 4 + (k - 1) * 0.5
                events[#events + 1] = Ev(qn, cell:find('~', 1, true) and 0.5 or 0.25, offs, bpm, b * 4)
            end
        end
    end
    return events
end

local function Removed(cells, out, bar)
    local names = { '1', '1&', '2', '2&', '3', '3&', '4', '4&' }
    local kept = {}
    -- bar: a number, or anything else (callers pass Gen5PlanTier's log through) for bar 0.
    for _, p in ipairs(KeptByBar(out)[type(bar) == 'number' and bar or 0] or {}) do kept[p] = true end
    local gone = {}
    for k, cell in ipairs(cells) do
        if cell ~= '.' and not kept[('%.2f'):format((k - 1) * 0.5)] then gone[#gone + 1] = names[k] end
    end
    return table.concat(gone, ' ')
end

Test.it('Drop 2: a bar that already rests loses fewer, and keeps an accent chord and a sustain', function()
    -- The chronosp_brutal_decay guitar at 210 BPM (Auto = Drop 2), bars 44, 45 and 52.
    local cases = {
        { { 'GR', '.', 'R', 'R', 'RB', 'RY', 'Y', 'YO' }, '2&',   'bar 44 (rest at 1&, chord on 4&)' },
        { { 'GR', '.', 'G', 'G', 'Y', 'R', 'G', 'O~' },   '2&',   'bar 52 (sustain on 4&)' },
        { { 'G', 'R', 'Y', 'B', 'G', 'R', 'Y', 'RB' },    '1& 2&', 'full bar, chord on 4&' },
        { { 'GR', 'GR', 'RY', 'RY', 'GR', 'GR', 'RY', 'RY' }, '2& 4&', 'all-chord bar' },
    }
    for _, c in ipairs(cases) do
        local got = Removed(c[1], Gen5PlanTier('gb', 'H', SlotBars(c[1], 4, 210)))
        Test.expect(got == c[2], ('%s: removed [%s], expected [%s]'):format(c[3], got, c[2]))
    end
end)

Test.it('a busy bar that already has two 8th rests keeps every note', function()
    -- Four bars of straight 8ths first: they lose two notes each, so the song-wide cap is
    -- already met and only the busy-bar rule decides the last bar.
    local full = { 'G', 'R', 'Y', 'B', 'G', 'R', 'Y', 'B' }
    for _, c in ipairs({
        { { '.', 'R', 'R', 'R', 'RB', 'RY', 'YB', '.' }, 'chronosp bar 45' },
        { { 'O', '.', 'B', 'Y', 'R', 'Y', '.', 'Y' },    'chronosp bar 150' },
    }) do
        local events = SlotBars(full, 4, 210)
        for _, ev in ipairs(SlotBars(c[1], 1, 210)) do
            ev.qn, ev.qn_e = ev.qn + 16, ev.qn_e + 16
            events[#events + 1] = ev
        end
        local got = Removed(c[1], Gen5PlanTier('gb', 'H', events), 4)
        Test.expect(got == '', ('%s: removed [%s], expected nothing'):format(c[2], got))
    end
end)

Test.it('Drop 1 with a rest already in the bar still takes the and of 4 (pojat_lemmikkih bar 3)', function()
    local cells = { 'G', '.', 'O', 'G', 'Y', 'R', 'B', 'R' }
    local got = Removed(cells, Gen5PlanTier('gb', 'H', SlotBars(cells, 4, 157)))
    Test.expect(got == '4&', 'removed [' .. got .. '], expected [4&]')
end)

Test.it('bass follows guitar in a bar of the same rhythm, but keeps its own sustain', function()
    -- Guitar: a full bar with a chord on 4&, so it drops 1& and 2&. Bass plays the same
    -- rhythm as single notes - on its own it would drop 2& and 4&.
    local gtr  = { 'G', 'R', 'Y', 'B', 'G', 'R', 'Y', 'RB' }
    local bass = { 'G', 'G', 'R', 'R', 'Y', 'Y', 'G', 'G' }
    local _, glog = Gen5PlanTier('gb', 'H', SlotBars(gtr, 4, 210))
    local alone = Removed(bass, Gen5PlanTier('gb', 'H', SlotBars(bass, 4, 210)))
    Test.expect(alone == '2& 4&', 'bass alone removed [' .. alone .. '], expected [2& 4&]')
    local out, blog = Gen5PlanTier('gb', 'H', SlotBars(bass, 4, 210), { busy_ref = glog.busy_bars })
    local got = Removed(bass, out)
    Test.expect(got == '1& 2&', 'bass following guitar removed [' .. got .. '], expected [1& 2&]')
    Test.expect(blog.busy_followed == 4, ('followed %s bars, expected 4'):format(tostring(blog.busy_followed)))

    -- Guitar plays straight 8ths and drops 2& and 4&; bass holds a sustain on 4&. Its own
    -- rule wins in that bar: the sustain stays and the and of 1 goes instead.
    local gtr2  = { 'G', 'R', 'Y', 'B', 'G', 'R', 'Y', 'B' }
    local bass2 = { 'G', 'G', 'R', 'R', 'Y', 'Y', 'G', 'G~' }
    local gout2, glog2 = Gen5PlanTier('gb', 'H', SlotBars(gtr2, 4, 210))
    local g2 = Removed(gtr2, gout2)
    Test.expect(g2 == '2& 4&', 'guitar removed [' .. g2 .. '], expected [2& 4&]')
    local out2, blog2 = Gen5PlanTier('gb', 'H', SlotBars(bass2, 4, 210), { busy_ref = glog2.busy_bars })
    local got2 = Removed(bass2, out2)
    Test.expect(got2 == '1& 2&', 'bass removed [' .. got2 .. '], expected [1& 2&]')
    Test.expect(blog2.busy_followed == 0, ('followed %s bars, expected 0'):format(tostring(blog2.busy_followed)))

    -- A different rhythm ignores the reference.
    local bass3 = { 'G', 'G', 'R', 'R', 'Y', 'Y', 'G', '.' }
    local got3 = Removed(bass3, Gen5PlanTier('gb', 'H', SlotBars(bass3, 4, 210), { busy_ref = glog.busy_bars }))
    Test.expect(got3 == '2&', 'bass in another rhythm removed [' .. got3 .. '], expected [2&]')
end)

----------------------------------------------------------------------
-- Generate planner: fast dense runs rewritten one grid slower on Hard
-- (difficulty_generate_retime.lua). Cases from the chronosp_brutal_decay solo at 210 BPM,
-- checked against its hand reduction.
----------------------------------------------------------------------

-- A bar from 'pos:colors' cells, pos in 1/24 QN from the bar line ('0:O 6:O 12:B').
-- A trailing '~' on the colors makes it a sustain. Repeated `bars` times, so every copy
-- reduces alike; Hard of copy 0 is what the tests read.
local function Bar24(cells, bars, bpm)
    local L = { G = 0, R = 1, Y = 2, B = 3, O = 4 }
    local events = {}
    for b = 0, (bars or 1) - 1 do
        for pos, cs in cells:gmatch('(%d+):(%S+)') do
            local offs = {}
            for c in cs:gmatch('[GRYBO]') do offs[#offs + 1] = L[c] end
            local qn = b * 4 + tonumber(pos) / 24
            events[#events + 1] = Ev(qn, cs:find('~', 1, true) and 1.0 or 0.1, offs, bpm or 210, b * 4)
        end
    end
    return events
end

-- Hard's bar 0 as 'pos:colors' in 1/24 QN.
local function Hard24(out)
    local C = { [0] = 'G', 'R', 'Y', 'B', 'O' }
    local cells = {}
    for _, ev in ipairs(out) do
        if ev.qn < 4 - 1e-6 then
            local cs = {}
            for _, o in ipairs(ev.offs) do cs[#cs + 1] = C[o] end
            cells[#cells + 1] = ('%d:%s'):format(math.floor(ev.qn * 24 + 0.5), table.concat(cs))
        end
    end
    return table.concat(cells, ' ')
end

Test.it('fast runs: 16ths become 8th triplets, keeping the color order (hand-reduced bars)', function()
    local cases = {
        { 'bar 158: 16 sixteenths -> 12, the tail of each half goes',
          '0:B 6:B 12:B 18:B 24:B 30:B 36:B 42:B 48:B 54:Y 60:R 66:Y 72:R 78:Y 84:R 90:Y',
          '0:B 8:B 16:B 24:B 32:B 40:B 48:B 56:Y 64:R 72:Y 80:R 88:Y' },
        { 'bar 154: a 16th rest at beat 3&',
          '0:G 6:R 12:Y 18:G 24:R 30:Y 36:B 42:O 48:B 54:Y 66:R 72:O 78:R 84:O 90:R',
          '0:G 8:R 16:Y 24:G 32:R 40:Y 48:B 56:Y 64:R 72:O 80:R 88:O' },
        { 'bar 153: a run that lands on beat 4 keeps landing there, then rests',
          '0:O 6:O 12:B 18:B 24:O 32:B 40:Y 48:O 54:B 60:Y 66:R 72:G',
          '0:O 8:O 16:B 24:O 32:B 40:Y 48:O 56:B 64:Y 72:R' },
        { 'bar 162: a 16th pair before beat 3 moves onto the triplets around it',
          '0:R~ 36:B 42:R 48:B 54:R~',
          '0:R 32:B 40:R 48:B 56:R' },
        { 'bar 20: a 16th rest before a note on the 8th grid stays; the group runs into beat 3',
          '0:GR 12:G 18:G 24:G 30:G 36:G 42:G 48:Y 60:G 66:G 72:G 78:G 84:R',
          '0:GR 16:G 24:G 32:G 40:G 48:Y 60:G 68:G 76:G 84:R' },
        { 'bar 21: a group cut to one note keeps the one that leads into the beat',
          '0:G 6:G 12:G 18:G 24:B 36:G 42:G 48:Y 60:G 66:G 72:R 84:G 90:G',
          '0:G 8:G 16:G 24:B 40:G 48:Y 60:G 68:G 76:R 88:G', 4 },
        -- The long run ends on Expert's O at 60: nothing goes past it (step 1, 2026-10-07 -
        -- the hand reduction had 64:O; the user accepted dropping it).
        { 'bar 165: notes on the 8th grid outside the run stay put; a long run ends where Expert\'s does',
          '0:Y 6:Y 12:R 18:R 24:G 30:G 36:R 42:R 48:Y 54:B 60:O 72:O 84:B',
          '0:Y 8:Y 16:R 24:G 32:G 40:R 48:Y 56:B 72:O 84:B' },
        { 'bar 152: a stray tick (37) does not make the bar read as 16th triplets',
          '0:O 6:O 12:B 18:O 24:B 30:Y 37:R 42:G 48:O 56:B 64:Y 72:B 80:Y 88:R',
          nil },
    }
    for _, c in ipairs(cases) do
        -- One bar, then a note in the next bar: by default far enough away to end the run,
        -- or at c[4] (QN) when the case runs into the next downbeat.
        local events = Bar24(c[2], 1)
        events[#events + 1] = Ev(c[4] or 5, 0.1, { 0 }, 210, 4)
        local out, log = Gen5PlanTier('gb', 'H', events)
        local got = Hard24(out)
        if c[3] then
            Test.expect(got == c[3], ('%s:\n           got  %s\n           want %s'):format(c[1], got, c[3]))
        else
            local _, n = got:gsub('%d+:', '')
            Test.expect(n == 12 and log.retimed_bars[1] and math.abs(log.retimed_bars[1].grid - 1 / 3) < 1e-9,
                ('%s: got %s'):format(c[1], got))
        end
    end
end)

Test.it('fast runs: a short flourish from a beat into 8ths is thinned, not rewritten (bass bar 73)', function()
    -- G G R (16ths from the beat) then R R (8ths): as triplets G G R R ran on evenly. Thinned
    -- it is G R R R per half, and the busy-bar rule (Drop 2 at 210) takes 2& and 4&.
    local x = Bar24('0:G 6:G 12:R 24:R 36:R 48:G 54:G 60:R 72:R 84:R', 1)
    x[#x + 1] = Ev(5, 0.1, { 0 }, 210, 4)
    local got = Hard24(Gen5PlanTier('gb', 'H', x))
    Test.expect(got == '0:G 12:R 24:R 48:G 60:R 72:R', 'bar 73 Hard: ' .. got)
end)

Test.it('fast runs: a bar of 8ths after a 16th run still loses its two notes (bass bar 85)', function()
    -- Bar 0: 16ths running into bar 1's downbeat. Bar 1: straight 8ths. The downbeat ends
    -- bar 0's run, but bar 1 is not rewritten, so the busy-bar rule (Drop 2) applies.
    local x = Bar24('0:O 6:Y 12:O 18:Y 24:O 30:Y 36:O 42:Y 48:O 54:B 60:O 66:B 72:O 78:B 84:O 90:B', 1)
    for _, ev in ipairs(Bar24('0:G 12:G 24:G 36:G 48:Y 60:G 72:G 84:R', 1)) do
        ev.qn, ev.qn_e = ev.qn + 4, ev.qn_e + 4
        x[#x + 1] = ev
    end
    x[#x + 1] = Ev(9, 0.1, { 0 }, 210, 8)
    local hard = Gen5PlanTier('gb', 'H', x)
    local kept = KeptByBar(hard)[1] or {}
    Test.expect(table.concat(kept, ' ') == '0.00 0.50 1.00 2.00 2.50 3.00',
        'bar 1 Hard kept [' .. table.concat(kept, ' ') .. ']')
end)

Test.it('fast runs: 8th triplets become 8ths, 16th triplets 16ths', function()
    local trip8 = '0:O 8:B 16:Y 24:B 32:Y 40:R 48:G 56:Y 64:R 72:Y 80:R 88:G'
    local events = Bar24(trip8, 1)
    events[#events + 1] = Ev(5, 0.1, { 0 }, 210, 4)
    local got = Hard24(Gen5PlanTier('gb', 'H', events))
    Test.expect(got == '0:O 12:B 24:Y 36:R 48:G 60:Y 72:R 84:G', 'bar 172 (8th triplets): ' .. got)

    local cells = {}
    for k = 0, 23 do cells[#cells + 1] = ('%d:%s'):format(k * 4, ({ 'G', 'R', 'Y' })[k % 3 + 1]) end
    events = Bar24(table.concat(cells, ' '), 1)
    events[#events + 1] = Ev(5, 0.1, { 0 }, 210, 4)
    local out = Gen5PlanTier('gb', 'H', events)
    local _, n = Hard24(out):gsub('%d+:', '')
    Test.expect(n == 16, ('24 sixteenth triplets should become 16 sixteenths, got %d: %s'):format(n, Hard24(out)))
end)

Test.it('fast runs: a short run is not rewritten at or below 160 BPM, and the same rhythm lands on the same positions on every part', function()
    -- At 140 BPM only a run of half a bar or more is rewritten (retime_min_run); five 16ths
    -- then 8ths are thinned to 8ths as before.
    local short = '0:B 6:B 12:B 18:B 24:B 36:B 48:Y 60:R 72:Y 84:R'
    local out, log = Gen5PlanTier('gb', 'H', Bar24(short, 1, 140))
    Test.expect(#(log.retimed_bars or {}) == 0, 'retimed at 140 BPM: ' .. Hard24(out))
    local _, n = Hard24(out):gsub('%d+:', '')
    Test.expect(n <= 8, ('at 140 BPM Hard keeps 8ths, got %d notes: %s'):format(n, Hard24(out)))

    local sixteenths = '0:B 6:B 12:B 18:B 24:B 30:B 36:B 42:B 48:B 54:Y 60:R 66:Y 72:R 78:Y 84:R 90:Y'

    local gtr  = Bar24(sixteenths, 1)
    local bass = Bar24('0:G 6:G 12:R 18:R 24:G 30:R 36:Y 42:Y 48:G 54:G 60:G 66:G 72:R 78:R 84:B 90:B', 1)
    local keys = Bar24('0:GY 6:GY 12:RB 18:RB 24:GY 30:RB 36:YO 42:YO 48:GY 54:GY 60:GY 66:GY 72:RB 78:RB 84:BO 90:BO', 1)
    local function Positions(evs)
        local q = {}
        for _, ev in ipairs(Gen5PlanTier(evs == keys and 'k5' or 'gb', 'H', evs)) do q[#q + 1] = ('%.3f'):format(ev.qn) end
        return table.concat(q, ' ')
    end
    local g, b, k = Positions(gtr), Positions(bass), Positions(keys)
    Test.expect(g == b, 'guitar and bass differ:\n' .. g .. '\n' .. b)
    Test.expect(g == k, 'guitar and keys differ:\n' .. g .. '\n' .. k)
end)

----------------------------------------------------------------------
-- Generate: Expert's hammer-ons kept on Hard (difficulty_generate_hopo.lua)
----------------------------------------------------------------------

Test.it('auto-HOPO: a single new color within 170 ticks (an 8th triplet hammers on, an 8th does not)', function()
    local function E(qn, offs) return { qn = qn, qn_e = qn + 0.1, offs = offs } end
    Test.expect(Gen5IsAutoHopo(E(0, { 0 }), E(1 / 3, { 1 })), '8th triplet, new color: hammer-on')
    Test.expect(not Gen5IsAutoHopo(E(0, { 0 }), E(0.5, { 1 })), '8th apart: strummed')
    Test.expect(not Gen5IsAutoHopo(E(0, { 0 }), E(1 / 3, { 0 })), 'same color: strummed')
    Test.expect(not Gen5IsAutoHopo(E(0, { 0 }), E(1 / 3, { 1, 2 })), 'chord: strummed')
    Test.expect(not Gen5IsAutoHopo(E(0, { 0, 1 }), E(1 / 3, { 1 })), 'note out of the previous chord: strummed')
    Test.expect(Gen5IsAutoHopo(E(0, { 0 }), E(0.5, { 1 }), 250), 'Magma threshold 250: an 8th hammers on')
end)

-- 'pos:colors' cells (1/24 QN) of bar 0 at 210 BPM, plus a note at qn `next_qn`.
local function HopoChart(cells, next_qn, next_color)
    local events = Bar24(cells, 1)
    events[#events + 1] = Ev(next_qn, 0.1, { next_color or 1 }, 210, 4)
    return events
end

local function SpanStr(spans)
    local out = {}
    for _, sp in ipairs(spans) do out[#out + 1] = ('%d-%d'):format(math.floor(sp.qn * 24 + 0.5), sp.count) end
    return table.concat(out, ' ')
end

Test.it('force-HOPO: 8th triplets rewritten as 8ths keep their hammer-ons (chronosp bar 172)', function()
    -- Expert hammers on every note after the first (new color each, 160 ticks apart); Hard's
    -- 8ths are 240 apart. One span from the second note through the next bar's downbeat.
    local x = HopoChart('0:O 8:B 16:Y 24:B 32:Y 40:R 48:G 56:Y 64:R 72:Y 80:R 88:G', 4, 1)
    Gen5MarkHopos(x, {}, {})
    local hard = Gen5PlanTier('gb', 'H', x)
    Test.expect(SpanStr(Gen5ForceHopoSpans(hard)) == '12-8', 'spans (start/24-count): ' .. SpanStr(Gen5ForceHopoSpans(hard)))
end)

Test.it('force-HOPO: a run of one color, or a hammer-on lost to ordinary thinning, gets none', function()
    local same = HopoChart('0:O 8:O 16:O 24:O 32:O 40:O 48:O 56:O 64:O 72:O 80:O 88:O', 6, 4)
    Gen5MarkHopos(same, {}, {})
    Test.expect(#Gen5ForceHopoSpans((Gen5PlanTier('gb', 'H', same))) == 0, 'one color: no hammer-ons to keep')
    -- A short group of 8th triplets at 140 BPM: not rewritten (under half a bar at or below
    -- 160 BPM), thinned in place - official Hard strums such notes almost always, so no
    -- markers.
    local slow = Bar24('0:O 8:B 16:Y 24:B 48:G 72:R', 1, 140)
    Gen5MarkHopos(slow, {}, {})
    Test.expect(#Gen5ForceHopoSpans((Gen5PlanTier('gb', 'H', slow))) == 0, '140 BPM thinning: none')
end)

Test.it("force-HOPO: Expert's own forced hammer-ons are copied where the note survives", function()
    -- Expert bar 7 of chronosp: forced on the notes at 12 and 24 (/24 QN). Two bars of
    -- 16ths first, which the Hard gap thins, so the 95% keep cap is met without this bar.
    local x = Bar24('0:G 6:R 12:G 18:R 24:G 30:R 36:G 42:R 48:G 54:R 60:G 66:R 72:G 78:R 84:G 90:R', 2, 120)
    for _, ev in ipairs(Bar24('0:G 12:R 24:Y 48:G', 1, 120)) do
        ev.qn, ev.qn_e = ev.qn + 8, ev.qn_e + 8
        x[#x + 1] = ev
    end
    Gen5MarkHopos(x, { { qn = 8.5, qn_e = 8.625 }, { qn = 9.0, qn_e = 9.125 } }, {})
    local spans = Gen5ForceHopoSpans((Gen5PlanTier('gb', 'H', x)))
    Test.expect(SpanStr(spans) == '204-2', 'spans (start/24-count): ' .. SpanStr(spans))
end)

----------------------------------------------------------------------
-- Generate: Medium (chronosp_brutal_decay bars 7, 10, 11, 18-20; pojat_lemmikkih bar 3)
----------------------------------------------------------------------

-- Hard bar 0 from cells, then a single G on the next downbeat; Medium planned from it.
local function MediumOf(cells, bpm, kind, next_offs)
    local hard = Bar24(cells, 1, bpm or 210)
    hard[#hard + 1] = Ev(4, 0.1, next_offs or { 0 }, bpm or 210, 4)
    return Gen5PlanTier(kind or 'gb', 'M', hard)
end

local function KeptAt(out, qn)
    for _, ev in ipairs(out) do if math.abs(ev.qn - qn) < 1e-6 then return ev end end
end

Test.it('Medium: a busy bar keeps a note per beat - beat 3 and the held 3& note (bar 7)', function()
    local out = MediumOf('0:B 12:O 24:B 36:Y 48:G 60:B~')
    Test.expect(Hard24(out) == '0:B 24:B 48:G 60:B', 'bar 7: ' .. Hard24(out))
    local b = KeptAt(out, 2.5)
    -- Held into the next bar line, Medium's release gap leaves it 1/8 - under Medium's
    -- shortest sustain at 210 BPM (1 QN), so a plain note.
    Test.expect(b and b.qn_e - b.qn < 0.5, '3& note should be plain, length ' .. tostring(b and (b.qn_e - b.qn)))
end)

Test.it('Medium: a 3& chord beats a beat-3 single, a downbeat single beats a 4& chord (bar 11)', function()
    local out = MediumOf('0:B 12:O 24:B 48:G 60:GY 84:GY')
    Test.expect(Hard24(out) == '0:B 24:B 48:G 60:GY', 'bar 11: ' .. Hard24(out))
    Test.expect(KeptAt(out, 4) ~= nil, 'the next downbeat single was dropped for the 4& chord')
end)

Test.it('Medium: an all-chord bar gets no chord bonus, so the next downbeat stays (bars 18-19)', function()
    local out = MediumOf('0:RB 12:RY 36:RY 48:RB 60:RY 84:RY', 210, 'gb', { 2, 3 })
    Test.expect(KeptAt(out, 4) ~= nil, 'next downbeat chord dropped: ' .. Hard24(out))
    Test.expect(not Hard24(out):find('36:RY 48:RB 60:RY', 1, true), 'three 8th chords in a row: ' .. Hard24(out))
end)

Test.it('Medium colors: only notes above Blue move, unless that makes a repeat Hard does not have', function()
    -- chronosp bar 10: moving only the O made B B -> the bar moves down whole.
    local out = MediumOf('0:G 12:G 24:Y 48:B 60:G 72:O')
    Test.expect(Hard24(out) == '0:G 24:R 48:Y 72:B', 'bar 10: ' .. Hard24(out))
    -- pojat bar 3 (157 BPM): moving only the O makes no repeat -> only the O moves.
    out = MediumOf('0:G 24:O 36:G 48:Y 60:R 72:B', 157)
    Test.expect(Hard24(out) == '0:G 24:B 48:Y 72:B', 'pojat bar 3: ' .. Hard24(out))
    -- A chord keeps its shape: Y+O moves down as R+B, not Y+B.
    -- (A busy Hard bar, so Medium thins it and no color fallback applies.)
    out = MediumOf('0:YB 12:YB 24:YB 36:YB 48:YB 60:YB 72:YO', 157, 'gb', { 1, 3 })
    Test.expect(Hard24(out) == '0:YB 24:YB 48:YB 72:RB', 'chord shape: ' .. Hard24(out))
end)

Test.it('Medium: a beat Hard\'s rewrite left empty comes back from Expert (bar 20)', function()
    local x = Bar24('0:GR 12:G 18:G 24:G 30:G 36:G 42:G 48:Y 60:G 66:G 72:G 78:G 84:R', 1)
    x[#x + 1] = Ev(5, 0.1, { 0 }, 210, 4)
    local hard = Gen5PlanTier('gb', 'H', x)
    Test.expect(KeptAt(hard, 3) == nil, 'precondition: Hard has no beat 4: ' .. Hard24(hard))
    local med = Gen5PlanTier('gb', 'M', hard)
    Test.expect(Hard24(med) == '0:GR 24:G 48:Y 72:G', 'bar 20 Medium: ' .. Hard24(med))
end)

Test.it('Medium that keeps nearly all of Hard: off-beats first, then color', function()
    -- Off-beats are enough: Hard B . Y . R (dotted quarters) repeated; Medium drops the
    -- 2& notes and no color fallback follows.
    local hard = {}
    for b = 0, 7 do
        local base = b * 4
        hard[#hard + 1] = Ev(base, 0.25, { 3 }, 157, base)
        hard[#hard + 1] = Ev(base + 1.5, 0.25, { 2 }, 157, base)
        hard[#hard + 1] = Ev(base + 3, 0.25, { 1 }, 157, base)
    end
    local med, log = Gen5PlanTier('k5', 'M', hard)
    Test.expect(log.offbeats_dropped == 8 and not log.color_fallback,
        ('dropped %s, color fallback %s'):format(tostring(log.offbeats_dropped), tostring(log.color_fallback)))
    -- No off-beats to drop: quarter notes topping at Orange; Medium moves each bar down
    -- until it tops out at Yellow.
    hard = {}
    for b = 0, 7 do
        for k = 0, 3 do hard[#hard + 1] = Ev(b * 4 + k, 0.25, { k + 1 }, 157, b * 4) end
    end
    med, log = Gen5PlanTier('k5', 'M', hard)
    -- R Y B O moves down two lanes to top out at Yellow (Green stays Green).
    Test.expect(log.color_fallback and Shape({ med[1], med[2], med[3], med[4] }) == '0:G 1:G 2:R 3:Y',
        'bar 0 Medium: ' .. Shape({ med[1], med[2], med[3], med[4] }))
end)

Test.it('Medium shortest sustain: 1 QN above 160 BPM, a dotted 8th at or below', function()
    -- The held note gets 1.5 QN before the next onset: less Medium's release gap that
    -- leaves 0.5 at 210 BPM (under 1 QN) and 0.75 at 140 (a dotted 8th, kept). The third
    -- note keeps the second from counting as isolated (Medium drops those off-beats).
    for _, c in ipairs({ { 210, false }, { 140, true } }) do
        local hard = { Ev(0, 1.5, { 0 }, c[1], 0), Ev(1.5, 0.1, { 1 }, c[1], 0), Ev(2.5, 0.1, { 2 }, c[1], 0) }
        local out = Gen5PlanTier('gb', 'M', hard)
        local held = out[1] and out[1].qn_e - out[1].qn >= 0.5
        Test.expect(held == c[2], ('%d BPM: sustain %s, length %.3f'):format(c[1],
            c[2] and 'should stay' or 'should become a plain note', out[1] and out[1].qn_e - out[1].qn or -1))
    end
end)

Test.it('Medium: bass follows guitar in a bar of the same Hard rhythm', function()
    local gtr_hard = Bar24('0:B 12:O 24:B 48:G 60:GY 84:GY', 1)
    gtr_hard[#gtr_hard + 1] = Ev(4, 0.1, { 0 }, 210, 4)
    local bass_hard = Bar24('0:G 12:G 24:G 48:G 60:R 84:R', 1)
    bass_hard[#bass_hard + 1] = Ev(4, 0.1, { 0 }, 210, 4)
    local gmed, glog = Gen5PlanTier('gb', 'M', gtr_hard)
    local bmed, blog = Gen5PlanTier('gb', 'M', bass_hard, { rhythm_ref = glog.rhythm_bars })
    local function Pos(out) local p = {} for _, ev in ipairs(out) do p[#p + 1] = ('%.3f'):format(ev.qn) end return table.concat(p, ' ') end
    Test.expect(Pos(bmed) == Pos(gmed), 'bass ' .. Pos(bmed) .. ' / guitar ' .. Pos(gmed))
    Test.expect((blog.rhythm_followed or 0) >= 1, 'no bar followed')
end)

Test.it('fast song (210 BPM): Medium keeps quarters, Easy beats 1 and 3', function()
    local hard = Gen5PlanTier('gb', 'H', Eighths(8, 210))
    local med  = Gen5PlanTier('gb', 'M', hard)
    ExpectEveryBar(med, 8, '0.00 1.00 2.00 3.00', 'Medium at 210 BPM')
    ExpectEveryBar(Gen5PlanTier('gb', 'E', med), 8, '0.00 2.00', 'Easy at 210 BPM')
end)

Test.it('sustain release gaps: Hard 1/8, Medium dotted 8th / 1/4 fast, Easy 1/4 / 1/2 fast', function()
    -- A sustain at 0 held for 3 quarter notes, the next note at 2. Expected sustain end
    -- (quarter notes) per tier and tempo; above 160 BPM is "fast".
    local expect = {
        { 'H', 120, 1.5 },  { 'H', 170, 1.5 },
        { 'M', 120, 1.25 }, { 'M', 170, 1.0 },
        { 'E', 120, 1.0 },  { 'E', 170, 0.125 },  -- a 1/2 gap leaves no sustain: cut to 1/32
    }
    for _, c in ipairs(expect) do
        local dl, bpm, want = c[1], c[2], c[3]
        local events = { Ev(0, 3, { 0 }, bpm, 0), Ev(2, 0.2, { 1 }, bpm, 0) }
        local out = Gen5PlanTier('gb', dl, events)
        Test.expect(#out == 2, ('%s at %d BPM kept %d of 2 notes'):format(dl, bpm, #out))
        local got = out[1].qn_e
        Test.expect(math.abs(got - want) < 1e-6,
            ('%s at %d BPM: sustain ends at %.3f, expected %.3f'):format(dl, bpm, got, want))
    end
end)

----------------------------------------------------------------------
-- Difficulty > Generate: the Pro Keys planner (difficulty_generate_prokeys.lua)
----------------------------------------------------------------------
Test.section('Generate planner - Pro Keys')

local function Pitches(ev) return table.concat(ev.offs, ',') end

Test.it('chords lose notes from the bottom: the top note stays', function()
    local cases = {
        { { 48, 52, 55, 60 }, 'H', '52,55,60' },
        { { 48, 52, 55, 60 }, 'M', '55,60' },
        { { 48, 52, 55, 60 }, 'E', '60' },
        { { 48, 60, 64 },     'H', '60,64' },     -- 48 is 16 below the top: past Hard's 11
        { { 55, 67 },         'M', '67' },        -- an octave is past Medium's 9
    }
    for _, c in ipairs(cases) do
        local got = table.concat(GenPKReduceChord(c[1], c[2]), ',')
        Test.expect(got == c[3], ('%s of %s: got %s, expected %s'):format(c[2], table.concat(c[1], ','), got, c[3]))
    end
end)

Test.it('Pro Keys keeps the same onsets as Keys for the same rhythm', function()
    -- The one-rhythm rule: pitches never decide which onsets survive.
    local pk, k5 = {}, {}
    for b = 0, 3 do
        for k = 0, 15 do
            local qn = b * 4 + k * 0.25
            pk[#pk + 1] = Ev(qn, 0.2, { 48 + (k * 5) % 24 }, 120, b * 4)
            k5[#k5 + 1] = Ev(qn, 0.2, { k % 5 }, 120, b * 4)
        end
    end
    local function Pos(out) local p = {} for _, ev in ipairs(out) do p[#p + 1] = ('%.3f'):format(ev.qn) end return table.concat(p, ' ') end
    local ph, kh = GenPKPlanTier('H', pk), Gen5PlanTier('k5', 'H', k5)
    Test.expect(Pos(ph) == Pos(kh), 'Hard: Pro Keys ' .. Pos(ph) .. ' / Keys ' .. Pos(kh))
    local pm, km = GenPKPlanTier('M', ph), Gen5PlanTier('k5', 'M', kh)
    Test.expect(Pos(pm) == Pos(km), 'Medium: Pro Keys ' .. Pos(pm) .. ' / Keys ' .. Pos(km))
end)

Test.it('Medium shows one window: the best fit, notes outside move by an octave', function()
    -- Half notes C2 E2 G2 C3 E3 G3 C4: C2-E3 (48-64) and E2-G3 (52-67) hold five of the
    -- seven each; C wins the tie. The upper tier shows two windows (A, then F), so none of
    -- its own is simply kept.
    local events = {}
    for k, p in ipairs({ 48, 52, 55, 60, 64, 67, 72 }) do
        local qn = (k - 1) * 2
        events[#events + 1] = Ev(qn, 0.2, { p }, 120, math.floor(qn / 4) * 4)
    end
    local out, log = GenPKPlanTier('M', events, { shifts = { { qn = 0, qn_e = 0.25, pitch = 9 },
                                                             { qn = 4, qn_e = 4.25, pitch = 5 } } })
    Test.expect(log.window == 0, 'window ' .. tostring(log.window) .. ', expected 0 (C2-E3)')
    Test.expect(#log.shifts == 1 and log.shifts[1].pitch == 0 and log.shifts[1].qn == 0,
        'expected one C2-E3 marker at the upper marker position')
    local got = {}
    for _, ev in ipairs(out) do got[#got + 1] = Pitches(ev) end
    -- G3 (67) folds to G2 (55), C4 (72) to C3 (60): the octave that fits, nothing else moves.
    Test.expect(table.concat(got, ' ') == '48 52 55 60 64 55 60', 'got ' .. table.concat(got, ' '))
    Test.expect(log.folded == 2, 'folded ' .. log.folded .. ', expected 2')
end)

Test.it('Medium keeps the upper tier\'s single window, preferred or not', function()
    -- Notes F2 and C3 fit C, D, E and F alike. An upper tier showing A2-C4 all song keeps
    -- it (the C3 fits, the F2 folds up to F3); one showing D2-F3 keeps D2-F3 too.
    local events = { Ev(0, 0.2, { 53 }, 120, 0), Ev(2, 0.2, { 60 }, 120, 0) }
    local out, log = GenPKPlanTier('M', events, { shifts = { { qn = 0, qn_e = 0.25, pitch = 9 } } })
    Test.expect(log.window == 9, 'A upper: window ' .. tostring(log.window) .. ', expected 9')
    Test.expect(Pitches(out[1]) == '65' and Pitches(out[2]) == '60', 'A upper: got ' .. Pitches(out[1]) .. ' ' .. Pitches(out[2]))
    local _, log2 = GenPKPlanTier('M', events, { shifts = { { qn = 0, qn_e = 0.25, pitch = 2 } } })
    Test.expect(log2.window == 2, 'D upper: window ' .. tostring(log2.window) .. ', expected 2')
end)

Test.it('a note that fits the window never moves, so the same note always lands on the same key', function()
    -- pojat_lemmikkih: D3 F3 C3 D3 in C2-E3. F3 is outside and folds to F2; the D3s and the
    -- C3 fit and stay - choosing the octave nearest the previous note moved them down
    -- after F2 but not the first D3.
    local events = {}
    for k, p in ipairs({ 62, 65, 60, 62 }) do
        local qn = (k - 1) * 2
        events[#events + 1] = Ev(qn, 0.2, { p }, 120, math.floor(qn / 4) * 4)
    end
    local out = GenPKPlanTier('M', events, { window = 0 })
    local got = {}
    for _, ev in ipairs(out) do got[#got + 1] = Pitches(ev) end
    Test.expect(table.concat(got, ' ') == '62 53 60 62', 'got ' .. table.concat(got, ' '))
end)

Test.it('Hard keeps the lane shifts it needs and drops the rest', function()
    -- C range from 0, F range at 8 (notes up to A3 = 69 follow), C range again at 16 with
    -- notes inside C2-E3, then a repeat of C at 24.
    local events = {
        Ev(1, 0.2, { 50 }, 120, 0), Ev(9, 0.2, { 69 }, 120, 8), Ev(17, 0.2, { 52 }, 120, 16), Ev(25, 0.2, { 55 }, 120, 24),
    }
    local shifts = { { qn = 0, qn_e = 0.25, pitch = 0 }, { qn = 8, qn_e = 8.25, pitch = 5 },
                     { qn = 16, qn_e = 16.25, pitch = 0 }, { qn = 24, qn_e = 24.25, pitch = 0 } }
    local _, log = GenPKPlanTier('H', events, { shifts = shifts })
    local got = {}
    for _, sh in ipairs(log.shifts) do got[#got + 1] = ('%g:%d'):format(sh.qn, sh.pitch) end
    -- The F shift is needed (A3 = 69 is past E3), and so is the C shift at 16 (E2 = 52 is
    -- under F2 = 53). The repeat of C at 24 shows nothing new and is dropped.
    Test.expect(table.concat(got, ' ') == '0:0 8:5 16:0', 'kept ' .. table.concat(got, ' '))
    Test.expect(log.shifts_dropped == 1, 'dropped ' .. log.shifts_dropped .. ', expected 1')
end)

Test.it('sustains: Medium leaves a quarter, a stub under 3/16 becomes a 1/16 note', function()
    -- Held from 0 for 3 QN, next note at 2: Medium ends it at 1.0. Held from 4, next at 5.5:
    -- the quarter gap leaves 0.5 QN, under 3/16 (0.75), so it becomes 0.25. (The note at
    -- 6.5 keeps 5.5 from being an isolated off-beat, which Medium's fallback would drop.)
    local events = { Ev(0, 3, { 60 }, 120, 0), Ev(2, 0.2, { 62 }, 120, 0),
                     Ev(4, 3, { 60 }, 120, 4), Ev(5.5, 0.2, { 62 }, 120, 4), Ev(6.5, 0.2, { 64 }, 120, 4) }
    local out = GenPKPlanTier('M', events)
    Test.expect(#out == 5, 'kept ' .. #out .. ' of 5')
    Test.expect(math.abs(out[1].qn_e - 1.0) < 1e-6, ('first sustain ends at %.3f, expected 1.000'):format(out[1].qn_e))
    Test.expect(math.abs(out[3].qn_e - 4.25) < 1e-6, ('stub ends at %.3f, expected 4.250'):format(out[3].qn_e))
end)

Test.it('Keys following Pro Keys keeps one onset per Pro Keys onset', function()
    -- A 32nd grace note before each beat on Keys; Pro Keys has only the beats. Both Keys
    -- notes sit within 1/32 of the beat; only the beat itself follows it.
    local keys, guide = {}, {}
    for b = 0, 3 do
        keys[#keys + 1] = Ev(b - 0.125, 0.1, { 0 }, 120, 0)
        keys[#keys + 1] = Ev(b, 0.2, { 1 }, 120, 0)
        guide[#guide + 1] = { qn = b, qn_e = b + 0.2 }
    end
    table.remove(keys, 1)   -- no grace note before the song's first beat
    local out = Gen5PlanTier('k5', 'H', keys, { guide = guide })
    local p = {}
    for _, ev in ipairs(out) do p[#p + 1] = ('%g'):format(ev.qn) end
    Test.expect(table.concat(p, ' ') == '0 1 2 3', 'kept ' .. table.concat(p, ' '))
end)

Test.it('Keys following a rewritten Pro Keys run takes its positions (korpiklaani bar 55)', function()
    -- Keys Expert: 16ths from the "and" of 1 to beat 4. Pro Keys Hard: the same run rewritten
    -- to 8th triplets (16..72/24). Keys plays exactly those onsets - not its nearest 16ths
    -- (18 24 30 42 ..., uneven groups with gaps). A Pro Keys note with no Keys note near it is
    -- reported (guide_missed).
    local keys, guide = {}, {}
    for k = 0, 10 do keys[#keys + 1] = Ev(0.5 + k * 0.25, 0.2, { 1 }, 120, 0) end
    for k = 0, 7 do guide[#guide + 1] = { qn = (16 + k * 8) / 24, qn_e = (16 + k * 8) / 24 + 0.2 } end
    guide[#guide + 1] = { qn = 3.5, qn_e = 3.7 }   -- no Keys note at 84/24
    local out, log = Gen5PlanTier('k5', 'H', keys, { guide = guide })
    local p = {}
    for _, ev in ipairs(out) do p[#p + 1] = ('%d'):format(math.floor(ev.qn * 24 + 0.5)) end
    Test.expect(table.concat(p, ' ') == '16 24 32 40 48 56 64 72', 'kept ' .. table.concat(p, ' '))
    Test.expect(#(log.guide_missed or {}) == 1, 'missed ' .. #(log.guide_missed or {}) .. ', expected 1 (84/24)')
end)

Test.it('Hard that equals Expert is detected, and pull_back shortens every sustain by a 1/16 or a 1/8', function()
    -- Single notes every half note, each held a quarter: Hard keeps them as they are.
    -- Pulled back, each loses a 1/16 (simple single -> single; the last at a phrase end)
    -- and stays a 3/16 sustain. A chord held a quarter before a different chord (complex)
    -- loses a 1/8, and as a 1/8 tail - under 3/16, "stubby" - becomes a 1/16 note.
    local events = {}
    for k = 0, 3 do events[#events + 1] = Ev(k * 2, 1.0, { 60 + k }, 100, math.floor(k / 2) * 4) end
    local out = GenPKPlanTier('H', events)
    Test.expect(GenPKSameAsUpper(out, events), 'Hard should equal Expert')
    local pulled, log = GenPKPlanTier('H', events, { pull_back = true })
    Test.expect(not GenPKSameAsUpper(pulled, events), 'pull_back left Hard equal to Expert')
    Test.expect(log.pulled == 4, 'pulled ' .. tostring(log.pulled) .. ', expected 4')
    for i, ev in ipairs(pulled) do
        Test.expect(math.abs((ev.qn_e - ev.qn) - 0.75) < 1e-6, ('note %d is %.3f QN, expected 0.75'):format(i, ev.qn_e - ev.qn))
    end
    local chords = { Ev(0, 1.0, { 60, 64 }, 100, 0), Ev(2, 0.2, { 62, 65 }, 100, 0) }
    local c, clog = GenPKPlanTier('H', chords, { pull_back = true })
    Test.expect(math.abs((c[1].qn_e - c[1].qn) - 0.25) < 1e-6 and clog.pull_cut == 1,
        ('complex: %.3f QN, cut %s; expected a 1/16 note'):format(c[1].qn_e - c[1].qn, tostring(clog.pull_cut)))
end)

Test.it('progression: same notes with shorter sustains is a reduction; advisory never counts', function()
    local function E(s, e, p) return { s = s, e = e, pitches = { p } } end
    local upper = { E(0, 0.5, 60), E(1, 1.5, 62) }
    local same  = { E(0, 0.5, 60), E(1, 1.5, 62) }
    local short = { E(0, 0.3, 60), E(1, 1.5, 62) }
    local block, extra = CheckDifficultyProgression('Hard', 'Expert', same, upper, 48, 48, 2, 2)
    Test.expect(extra == 2 and block:find('NOT REDUCED', 1, true), 'copy: expected 2 issues, got ' .. extra)
    block, extra = CheckDifficultyProgression('Hard', 'Expert', short, upper, 48, 48, 2, 2)
    Test.expect(extra == 0 and block:find('only sustain lengths differ (1 sustain shorter)', 1, true),
        'shorter sustain: expected no issue, got ' .. extra .. ': ' .. block)
    block, extra = CheckDifficultyProgression('Hard', 'Expert', same, upper, 48, 48, 2, 2, { advisory = true })
    Test.expect(extra == 0 and block:find('Advisory: Hard appears', 1, true), 'advisory: got ' .. extra .. ': ' .. block)
end)

----------------------------------------------------------------------
-- Difficulty > Generate: a keys lick that starts on an "and" (GEN5_PARAMS.and_phrase)
----------------------------------------------------------------------
Test.section('Generate planner - "and" phrases')

-- The korpiklaani_juo_viinaa lick as Hard has it, at 120 BPM: a pickup on the and of 4,
-- then three bars of straight 8ths whose beats repeat a note (B B C C) and whose "and"s
-- move (B G C A). beats / ands: the notes on beats 1-4 and on their "and"s, as offs.
local function Lick(beats, ands)
    local events = { Ev(3.5, 0.2, { ands[4] }, 120, 0) }
    for b = 1, 3 do
        for k = 0, 3 do
            events[#events + 1] = Ev(b * 4 + k, 0.2, { beats[k + 1] }, 120, b * 4)
            events[#events + 1] = Ev(b * 4 + k + 0.5, 0.2, { ands[k + 1] }, 120, b * 4)
        end
    end
    return events
end
local function Positions(out)
    local p = {}
    for _, ev in ipairs(out) do p[#p + 1] = ('%g'):format(ev.qn) end
    return table.concat(p, ' ')
end
local AND_LINE = '3.5 4.5 5.5 6.5 7.5 8.5 9.5 10.5 11.5 12.5 13.5 14.5 15.5'

Test.it('Keys and Pro Keys Medium keep the "and"s of a lick that enters on one and moves there', function()
    local k5 = Gen5PlanTier('k5', 'M', Lick({ 1, 1, 2, 2 }, { 1, 0, 2, 3 }))
    Test.expect(Positions(k5) == AND_LINE, 'Keys: ' .. Positions(k5))
    local pk, log = GenPKPlanTier('M', Lick({ 59, 59, 60, 60 }, { 59, 55, 60, 57 }))
    Test.expect(Positions(pk) == AND_LINE, 'Pro Keys: ' .. Positions(pk))
    Test.expect(#(log.and_phrases or {}) == 1, 'expected one "and" phrase')
end)

Test.it('no shift when the beats move more than the "and"s, on Guitar, or when the lick enters on a beat', function()
    local beats_move = Gen5PlanTier('k5', 'M', Lick({ 1, 0, 2, 3 }, { 1, 1, 2, 2 }))
    Test.expect(not Positions(beats_move):find('4.5', 1, true), 'beats moving: ' .. Positions(beats_move))
    local gtr = Gen5PlanTier('gb', 'M', Lick({ 1, 1, 2, 2 }, { 1, 0, 2, 3 }))
    Test.expect(not Positions(gtr):find('4.5', 1, true), 'Guitar: ' .. Positions(gtr))
    local lick = Lick({ 1, 1, 2, 2 }, { 1, 0, 2, 3 })
    table.remove(lick, 1)   -- no pickup: the phrase enters on the downbeat
    local on_beat = Gen5PlanTier('k5', 'M', lick)
    Test.expect(not Positions(on_beat):find('4.5', 1, true), 'beat entry: ' .. Positions(on_beat))
end)

Test.it('Easy goes back to Hard\'s downbeats inside an "and" phrase', function()
    local hard = Lick({ 59, 59, 60, 60 }, { 59, 55, 60, 57 })
    local med = GenPKPlanTier('M', hard)
    local easy, log = GenPKPlanTier('E', med, { and_source = hard })
    Test.expect((log.easy_from_hard or 0) > 0, 'Easy took no Hard notes')
    -- Beats 1 and 3 from Hard: B on 1, C on 3, in every bar of the lick.
    Test.expect(Positions(easy) == '4 6 8 10 12 14', 'Easy: ' .. Positions(easy))
    Test.expect(Pitches(easy[1]) == '59' and Pitches(easy[2]) == '60', 'Easy pitches: ' .. Pitches(easy[1]) .. ' ' .. Pitches(easy[2]))
end)

----------------------------------------------------------------------
-- Difficulty > Generate: the fast-run rewrite keeps a long run inside Expert's notes
----------------------------------------------------------------------
Test.section('Generate planner - fast-run rewrite bounds')

-- Positions of a bar's Hard notes, in 1/24 QN from the bar line.
local function Grid24(out, bar_start)
    local p = {}
    for _, ev in ipairs(out) do
        if ev.qn >= bar_start - 1e-6 and ev.qn < bar_start + 4 - 1e-6 then
            p[#p + 1] = ('%d'):format(math.floor((ev.qn - bar_start) * 24 + 0.5))
        end
    end
    return table.concat(p, ' ')
end

Test.it('a long run starting on the "and" of 1 stays on the beat grid, inside its notes, unbroken (chronosp bar 60)', function()
    -- 210 BPM: a chord on 1, then 16ths from the "and" of 1 to the end of the bar. The grid
    -- stays aligned to the beats (16, not 12 or 0: never before Expert's first note at 12)
    -- and carries straight across beat 3 - the user's hand reduction of chronosp.
    local colors = { 1, 1, 1, 1, 3, 3, 2, 2, 3, 3, 2, 2, 1, 0 }
    local events = { Ev(0, 0.2, { 0, 1 }, 210, 0) }
    for k = 0, 13 do events[#events + 1] = Ev(0.5 + k * 0.25, 0.2, { colors[k + 1] }, 210, 0) end
    events[#events + 1] = Ev(4, 0.2, { 0 }, 210, 4)
    local out = Gen5PlanTier('gb', 'H', events, { busy_drop = 2 })
    local got = Grid24(out, 0)
    Test.expect(got:match('^0 16 24 32 40 48'), 'bar: ' .. got .. ' (expected 0 16 24 32 40 48 ...)')
end)

Test.it('a long run crossing beat 3 has no break (korpiklaani Pro Keys bar 55)', function()
    -- 120 BPM, Rewrite: 16ths from the "and" of 1 to beat 4, then a note on 4&. Laid out on
    -- one 8th-triplet grid from 16 to 72 - the user's drawing.
    local events = {}
    for k = 0, 10 do events[#events + 1] = Ev(0.5 + k * 0.25, 0.2, { 62 }, 120, 0) end
    events[#events + 1] = Ev(3.5, 0.2, { 60 }, 120, 0)
    local out = GenPKPlanTier('H', events, { fast_runs = 'rewrite' })
    local got = Grid24(out, 0)
    Test.expect(got == '16 24 32 40 48 56 64 72 84', 'bar: ' .. got)
end)

Test.it('Hard fast runs: Thin never rewrites, Auto rewrites above 160 BPM only', function()
    local function Bar(bpm)
        local events = {}
        for k = 0, 15 do events[#events + 1] = Ev(k * 0.25, 0.2, { k % 5 }, bpm, 0) end
        events[#events + 1] = Ev(4, 0.2, { 0 }, bpm, 4)
        return events
    end
    local function Rewritten(bpm, mode)
        local _, log = Gen5PlanTier('gb', 'H', Bar(bpm), { busy_drop = 1, fast_runs = mode })
        return #(log.retimed_bars or {}) > 0
    end
    Test.expect(not Rewritten(210, 'thin'), 'Thin rewrote at 210 BPM')
    Test.expect(Rewritten(210, 'auto'), 'Auto did not rewrite at 210 BPM')
    Test.expect(not Rewritten(128, 'auto'), 'Auto rewrote at 128 BPM')
    Test.expect(Rewritten(128, 'rewrite'), 'Rewrite did not rewrite a whole bar of 16ths at 128 BPM')
end)

Test.it('a long run puts no note after its last Expert note (chronosp bar 165)', function()
    -- 16ths from 0 to 2.5 (beat 3 "and"), then a rest until 3: the second half bar's run
    -- ends on 2.5 (60/24), so no slot at 64/24.
    local events = {}
    for k = 0, 10 do events[#events + 1] = Ev(k * 0.25, 0.2, { k % 5 }, 210, 0) end
    events[#events + 1] = Ev(3, 0.2, { 4 }, 210, 0)
    local out = Gen5PlanTier('gb', 'H', events, { busy_drop = 2 })
    for _, ev in ipairs(out) do
        Test.expect(not (ev.qn > 2.5 + 1e-6 and ev.qn < 3 - 1e-6),
            ('a note at %d/24, after the run\'s last note (60/24)'):format(math.floor(ev.qn * 24 + 0.5)))
    end
end)

Test.it('a short group into beat 3 keeps leading into it (chronosp bars 21/23)', function()
    -- 210 BPM: 16ths 0-1 (a run that lands on beat 2), then G G on 36/24 and 42/24 into Y on
    -- beat 3. The pair is short: it is laid out back from beat 3 - 40 G | 48 Y.
    local events = {}
    for k = 0, 4 do events[#events + 1] = Ev(k * 0.25, 0.2, { 0 }, 210, 0) end
    events[#events + 1] = Ev(1.5, 0.2, { 0 }, 210, 0)
    events[#events + 1] = Ev(1.75, 0.2, { 0 }, 210, 0)
    events[#events + 1] = Ev(2, 0.2, { 2 }, 210, 0)
    events[#events + 1] = Ev(3, 0.2, { 1 }, 210, 0)
    local got = Grid24(Gen5PlanTier('gb', 'H', events, { busy_drop = 2 }), 0)
    Test.expect((' ' .. got .. ' '):find(' 40 48 ', 1, true), 'bar: ' .. got .. ' (expected ... 40 48 ...)')
end)

Test.it('at or below 160 BPM a run of half a bar or more is rewritten (molto opening)', function()
    -- 128 BPM: a bar of 16 moving 16ths becomes 8th triplets, colour order kept.
    local events = {}
    for k = 0, 15 do events[#events + 1] = Ev(k * 0.25, 0.2, { k % 5 }, 128, 0) end
    events[#events + 1] = Ev(4, 0.2, { 0 }, 128, 4)
    local got = Grid24(Gen5PlanTier('gb', 'H', events, { busy_drop = 1 }), 0)
    Test.expect(got == '0 8 16 24 32 40 48 56 64 72 80 88', 'bar: ' .. got)
end)

Test.it('at or below 160 BPM a shorter run is thinned as before, with no busy-bar side effect', function()
    -- 128 BPM: six 16ths (under half a bar), then 8ths - thinned to 8ths, as before the rule.
    local events = {}
    for k = 0, 5 do events[#events + 1] = Ev(k * 0.25, 0.2, { k % 5 }, 128, 0) end
    for k = 3, 7 do events[#events + 1] = Ev(k * 0.5, 0.2, { k % 5 }, 128, 0) end
    local out, log = Gen5PlanTier('gb', 'H', events, { busy_drop = 1 })
    Test.expect(#(log.retimed_bars or {}) == 0, 'a short run was rewritten')
    for _, ev in ipairs(out) do
        Test.expect(math.abs(ev.qn * 2 - math.floor(ev.qn * 2 + 0.5)) < 1e-6, ('a note off the 8th grid at %g'):format(ev.qn))
    end
    -- korpiklaani's lick: 16th grace notes inside an 8th line (1, 1.25, 1.5) - no flourish
    -- marking at this tempo, so the busy-bar rule reads the bar as before (not "whole").
    local lick = {}
    for _, q in ipairs({ 0, 0.5, 1, 1.25, 1.5, 2, 2.5, 3, 3.25, 3.5 }) do lick[#lick + 1] = Ev(q, 0.2, { 1 }, 120, 0) end
    local _, llog = Gen5PlanTier('gb', 'H', lick, { busy_drop = 1 })
    Test.expect(#(llog.retimed_bars or {}) == 0, 'the lick was rewritten')
    for _, ev in ipairs(lick) do Test.expect(not ev.flourish, ('flourish marked at %g at 120 BPM'):format(ev.qn)) end
end)

Test.section('Generate planner - time signatures')

-- `bars` bars of straight 8ths, each bar_len QN long with the given pulse (Gen5PulseQN).
local function MeterBars(bars, bar_len, pulse, bpm)
    local events = {}
    for b = 0, bars - 1 do
        for k = 0, bar_len * 2 - 1 do
            local qn = b * bar_len + k * 0.5
            events[#events + 1] = { qn = qn, qn_e = qn + 0.25, offs = { k % 4 }, bpm = bpm, down = k == 0,
                                    bar_qn = k * 0.5, bar_len = bar_len, pulse = pulse }
        end
    end
    return events
end

-- Bar b's kept positions (QN from its bar line) as text.
local function BarKept(out, b, bar_len)
    local pos = {}
    for _, ev in ipairs(out) do
        local q = ev.qn - b * bar_len
        if q >= -1e-6 and q < bar_len - 1e-6 then pos[#pos + 1] = ('%g'):format(q) end
    end
    return table.concat(pos, ' ')
end

Test.it('the beat of a time signature: a dotted quarter in 6/8, 9/8 and 12/8, else a quarter note', function()
    for _, c in ipairs({ { 4, 4, 1 }, { 3, 4, 1 }, { 6, 4, 1 }, { 2, 2, 1 }, { 6, 8, 1.5 }, { 9, 8, 1.5 },
                         { 12, 8, 1.5 }, { 3, 8, 1 }, { 5, 8, 1 }, { 7, 8, 1 } }) do
        local got = Gen5PulseQN(c[1], c[2])
        Test.expect(got == c[3], ('%d/%d: pulse %s, expected %s'):format(c[1], c[2], tostring(got), tostring(c[3])))
    end
end)

Test.it('beat classes count from the bar line, in the bar\'s own beat', function()
    -- A 7/8 bar is 3.5 QN, so the next bar's beats fall on whole-QN "ands" of the song.
    Test.expect(Gen5BeatClass({ qn = 4.5, bar_qn = 1, bar_len = 4 }) == 'beat', 'beat 2 after a 7/8 bar')
    Test.expect(Gen5BeatClass({ qn = 5, bar_qn = 1.5, bar_len = 4 }) == '8th', 'its "and" of 2')
    -- 6/8: the second beat is 1.5 QN; 1 and 2 QN are 8ths.
    Test.expect(Gen5BeatClass({ qn = 1.5, bar_qn = 1.5, bar_len = 3, pulse = 1.5 }) == 'beat', '6/8 beat 2')
    Test.expect(Gen5BeatClass({ qn = 1, bar_qn = 1, bar_len = 3, pulse = 1.5 }) == '8th', '6/8 third 8th')
end)

Test.it('6/8: Medium and Easy keep the bar\'s two beats, not three quarter notes across them', function()
    -- vm_loiri_sydameeni_joulu_teen: counted in quarter notes, Medium kept 0, 1 and 2 of
    -- each bar. Official 6/8 Medium keeps 0 and 1.5 in 97% of cases.
    local hard = MeterBars(8, 3, 1.5, 105)
    for _, dl in ipairs({ 'M', 'E' }) do
        local out = Gen5PlanTier('gb', dl, hard)
        for b = 0, 7 do
            local got = BarKept(out, b, 3)
            Test.expect(got == '0 1.5', ('%s bar %d keeps [%s], expected [0 1.5]'):format(dl, b, got))
        end
    end
end)

Test.it('6/8 and 3/4: a Hard bar of six 8ths loses the 8th before the bar line first', function()
    -- Drop 1: 6/8 and 3/4 alike lose 2.5. Drop 2: 6/8 also loses the 8th before its second
    -- beat (official 6/8 Hard: 0 0.5 1.5 2 in 77 of 129 such bars); 3/4 the and of 2 (official
    -- slow 3/4 Hard: 0 0.5 1 2 in 15 of 16) - never 4/4's half-bar position by mistake.
    for _, c in ipairs({ { 1.5, 1, '0 0.5 1 1.5 2' }, { 1.5, 2, '0 0.5 1.5 2' },
                         { 1,   1, '0 0.5 1 1.5 2' }, { 1,   2, '0 0.5 1 2' } }) do
        local out = Gen5PlanTier('gb', 'H', MeterBars(8, 3, c[1], 105), { busy_drop = c[2] })
        for b = 0, 7 do
            local got = BarKept(out, b, 3)
            Test.expect(got == c[3], ('%s Drop %d bar %d keeps [%s], expected [%s]')
                :format(c[1] == 1 and '3/4' or '6/8', c[2], b, got, c[3]))
        end
    end
end)

Test.it('6/8: no keys "and" phrase - the 8th after a beat is not an "and" there', function()
    -- A line from the bar's 2nd 8th whose 0.5/1.5/2.5 notes change and whose 0/1/2 notes
    -- repeat: counted in quarter notes it read as a lick on the "and"s, with 1.5 - a 6/8
    -- beat - among them.
    local events = {}
    for b = 0, 3 do
        for k = 0, 5 do
            if b > 0 or k > 0 then
                local q = k * 0.5
                local offs = (k % 2 == 1) and { (b * 3 + k) % 5 } or { 0 }
                events[#events + 1] = { qn = b * 3 + q, qn_e = b * 3 + q + 0.25, offs = offs, bpm = 105,
                                        down = k == 0, bar_qn = q, bar_len = 3, pulse = 1.5 }
            end
        end
    end
    Test.expect(#Gen5AndPhrases(events, 'k5') == 0, 'a 6/8 line was read as an "and" phrase')
    -- The control: the same line in 3/4 IS one, so the test exercises the rule.
    for _, ev in ipairs(events) do ev.pulse = 1 end
    Test.expect(#Gen5AndPhrases(events, 'k5') == 1, 'the 3/4 control is no "and" phrase - the test proves nothing')
end)

Test.section('Generate planner - overlapping gems (Keys, Pro Keys)')

-- 90 BPM: under the Keys 3/16 gray zone (>= 100 BPM), so lengths are only cut by the
-- rules under test.
local OV_BPM = 90

-- The planned event starting at qn, or nil.
local function At(out, qn)
    for _, ev in ipairs(out) do if math.abs(ev.qn - qn) < 1e-6 then return ev end end
end

local function Offs(ev) return ev and table.concat(ev.offs, ',') or 'none' end

Test.it('Hard keeps a note Expert holds under moving notes (Loiri bar 41)', function()
    -- R held for a bar while B/O chords play over it: at most 3 notes sound at once.
    local events = { Ev(0, 5, { 1 }, OV_BPM, 0), Ev(1, 0.125, { 3, 4 }, OV_BPM, 0), Ev(2, 0.125, { 3 }, OV_BPM, 0),
                     Ev(3, 0.125, { 3, 4 }, OV_BPM, 0), Ev(6, 0.125, { 0 }, OV_BPM, 4) }
    local out = Gen5PlanTier('k5', 'H', events)
    local r_ = At(out, 0)
    Test.expect(r_ and math.abs(r_.qn_e - 5) < 1e-6, ('held R ends at %s, expected 5 (Expert)'):format(r_ and r_.qn_e or 'none'))
    -- Size only: a chart this sparse is eased by color (the 95% fallback moves B O down).
    Test.expect(At(out, 1) and #At(out, 1).offs == 2, 'the chord over it lost notes: ' .. Offs(At(out, 1)))
end)

Test.it('an onset under a held note loses chord notes before the held note goes', function()
    -- Held G + R Y B = 4 sounding on 5-lane (max 3): the chord keeps its top two (Keys rule).
    local events = { Ev(0, 4, { 0 }, OV_BPM, 0), Ev(1, 0.125, { 1, 2, 3 }, OV_BPM, 0), Ev(6, 0.125, { 0 }, OV_BPM, 4) }
    local out = Gen5PlanTier('k5', 'H', events)
    Test.expect(Offs(At(out, 1)) == '2,3', 'onset chord: ' .. Offs(At(out, 1)) .. ', expected 2,3')
    Test.expect(math.abs(At(out, 0).qn_e - 4) < 1e-6, ('held G ends at %g, expected 4'):format(At(out, 0).qn_e))
end)

Test.it('stacked sustains: the earliest-started one ends so a new single note fits', function()
    -- G, R, Y held one after another, then a single B: 3 held + 1 is over 5-lane's 3.
    local events = { Ev(0, 8, { 0 }, OV_BPM, 0), Ev(1, 7, { 1 }, OV_BPM, 0), Ev(2, 6, { 2 }, OV_BPM, 0),
                     Ev(3, 0.125, { 3 }, OV_BPM, 0) }
    local out = Gen5PlanTier('k5', 'H', events)
    Test.expect(At(out, 3) ~= nil, 'the single B was dropped')
    Test.expect(At(out, 0).qn_e <= 3 - 0.25 + 1e-6, ('G should end before B with its gap, ends %g'):format(At(out, 0).qn_e))
    Test.expect(math.abs(At(out, 1).qn_e - 8) < 1e-6 and math.abs(At(out, 2).qn_e - 8) < 1e-6,
        ('R and Y should keep holding to 8: %g, %g'):format(At(out, 1).qn_e, At(out, 2).qn_e))
    -- Pro Keys allows 4: the same shape keeps every note held.
    local pk = { Ev(0, 8, { 48 }, OV_BPM, 0), Ev(1, 7, { 52 }, OV_BPM, 0), Ev(2, 6, { 55 }, OV_BPM, 0),
                 Ev(3, 0.125, { 60 }, OV_BPM, 0) }
    local pout = GenPKPlanTier('H', pk, {})
    Test.expect(math.abs(At(pout, 0).qn_e - 8) < 1e-6, ('Pro Keys: 4 sounding is allowed, 48 ends %g'):format(At(pout, 0).qn_e))
end)

Test.it('a held note never sounds into a note on its own lane, nor across more than an octave on Pro Keys', function()
    local out = Gen5PlanTier('k5', 'H', { Ev(0, 4, { 1 }, OV_BPM, 0), Ev(2, 0.125, { 1 }, OV_BPM, 0) })
    Test.expect(At(out, 0).qn_e <= 2 - 0.25 + 1e-6, ('R held into R at 2: ends %g'):format(At(out, 0).qn_e))
    local pout = GenPKPlanTier('H', { Ev(0, 4, { 48 }, OV_BPM, 0), Ev(2, 0.125, { 62 }, OV_BPM, 0) }, {})
    Test.expect(At(pout, 0).qn_e <= 2 - 0.25 + 1e-6, ('48 held under 62 (14 semitones): ends %g'):format(At(pout, 0).qn_e))
end)

Test.it('Medium holds a note only over a note a bar or more later; Easy never', function()
    local long = { Ev(0, 8, { 0 }, OV_BPM, 0), Ev(4, 0.125, { 2 }, OV_BPM, 4) }
    local m = Gen5PlanTier('k5', 'M', long)
    Test.expect(math.abs(At(m, 0).qn_e - 8) < 1e-6, ('Medium: G held a bar before Y should stay, ends %g'):format(At(m, 0).qn_e))
    local short = { Ev(0, 8, { 0 }, OV_BPM, 0), Ev(2, 0.125, { 2 }, OV_BPM, 0) }
    m = Gen5PlanTier('k5', 'M', short)
    Test.expect(At(m, 0).qn_e <= 2 + 1e-6, ('Medium: G held half a bar before Y should end, ends %g'):format(At(m, 0).qn_e))
    local e = Gen5PlanTier('k5', 'E', long)
    Test.expect(At(e, 0).qn_e <= 4 + 1e-6, ('Easy never overlaps: G ends %g'):format(At(e, 0).qn_e))
end)

Test.it('a rolled chord becomes one chord on its strongest beat', function()
    -- Loiri's last chord at 61 BPM: R and Y a 1/32 apart into a held O on the downbeat.
    local roll = { Ev(3.75, 3.75, { 1 }, 61, 0), Ev(3.875, 3.625, { 2 }, 61, 0), Ev(4, 3.5, { 4 }, 61, 4) }
    local out = Gen5PlanTier('k5', 'H', roll)
    Test.expect(#out == 1 and Offs(At(out, 4)) == '1,2,4', ('expected one R Y O chord on 4, got %d events, %s'):format(#out, Offs(At(out, 4))))
    -- A roll that starts on the downbeat stays there (promisesinthedark bar 15).
    local from = { Ev(4, 3.5, { 48, 55 }, 90, 4), Ev(4.25, 3.25, { 57 }, 90, 4) }
    local pout = GenPKPlanTier('H', from, {})
    Test.expect(#pout == 1 and Offs(At(pout, 4)) == '48,55,57', ('expected 48+55+57 on 4, got %d events, %s'):format(#pout, Offs(At(pout, 4))))
end)

Test.it('Keys chords keep their top notes; Guitar keeps the outer pair and the lowest', function()
    -- Official Keys keeps the top note going to one note (Hard>Medium 52% vs 32%); Guitar/Bass
    -- Easy keeps the lowest (69%).
    Test.expect(table.concat(Gen5ReduceChordSizeKeys({ 0, 1, 3 }, 2), ',') == '1,3', 'Keys G R B -> R B')
    Test.expect(table.concat(Gen5ReduceChordSizeKeys({ 1, 3 }, 1), ',') == '3', 'Keys R B -> B')
    Test.expect(table.concat(Gen5ReduceChordSize({ 0, 1, 3 }, 2), ',') == '0,3', 'Guitar G R B -> G B')
    Test.expect(table.concat(Gen5ReduceChordSize({ 1, 3 }, 1), ',') == '1', 'Guitar R B -> R')
    -- Through the planner: a Hard G R B chord becomes R B on Medium, B on Easy. The 8ths
    -- between are there for Medium to drop: a Medium keeping nearly all of Hard is eased by
    -- color instead, which would move the chord.
    local hard = {}
    for b = 0, 3 do
        hard[#hard + 1] = Ev(b * 4, 0.125, { 0, 1, 3 }, OV_BPM, b * 4)
        for k = 1, 7 do hard[#hard + 1] = Ev(b * 4 + k * 0.5, 0.125, { k % 2 == 1 and 1 or 2 }, OV_BPM, b * 4) end
    end
    Test.expect(Offs(At(Gen5PlanTier('k5', 'M', hard), 0)) == '1,3', 'Keys Medium chord: ' .. Offs(At(Gen5PlanTier('k5', 'M', hard), 0)))
    local medium = Gen5PlanTier('k5', 'M', hard)
    Test.expect(Offs(At(Gen5PlanTier('k5', 'E', medium), 0)) == '3', 'Keys Easy note from R B: ' .. Offs(At(Gen5PlanTier('k5', 'E', medium), 0)))
end)

Test.it('Keys Easy keeps its line moving: no new repeats, a repeated chord stays one note', function()
    local function E(...) local o = {} for i, offs in ipairs({ ... }) do o[i] = { offs = { offs[#offs] } } end return o end
    local function Run(chords)
        local out = E(table.unpack(chords))   -- the chord rule's pick: the top note
        Gen5KeysEasyMotion(out, chords)
        local t = {}
        for i, ev in ipairs(out) do t[i] = ev.offs[1] end
        return table.concat(t, ' ')
    end
    -- R Y then G Y: the top Y would repeat while Medium moved -> G. (Lanes: 0 G .. 4 O.)
    Test.expect(Run({ { 1, 2 }, { 0, 2 } }) == '2 0', 'RY GY: ' .. Run({ { 1, 2 }, { 0, 2 } }))
    -- The same chord three times stays one note, also after rule 2 changed its first.
    Test.expect(Run({ { 1, 2 }, { 0, 2 }, { 0, 2 }, { 0, 2 } }) == '2 0 0 0', 'RY GY GY GY: ' .. Run({ { 1, 2 }, { 0, 2 }, { 0, 2 }, { 0, 2 } }))
    -- A single Medium note is never changed, even when it repeats.
    Test.expect(Run({ { 2 }, { 2 } }) == '2 2', 'Y Y: ' .. Run({ { 2 }, { 2 } }))
end)

Test.it('Validate: overlap limits per tier (DiffCheckOverlaps)', function()
    local opts = { max = { X = 3, H = 3 }, label = function(p) return table.concat(p, '+') end,
                   qn_at = function(q) return q end }
    local function N(s, e, p) return { s = s, e = e, pitches = p } end
    local three = { N(0, 4, { 96 }), N(1, 4, { 97 }), N(2, 2.1, { 98 }) }
    local four  = { N(0, 4, { 96 }), N(1, 4, { 97 }), N(2, 2.1, { 98, 99 }) }
    Test.expect(#DiffCheckOverlaps(three, 'H', opts) == 0, '3 sounding on 5-lane Hard is allowed')
    Test.expect(#DiffCheckOverlaps(four, 'H', opts) == 1, '4 sounding on 5-lane Hard is one error')
    Test.expect(#DiffCheckOverlaps({ N(0, 4, { 72 }), N(1, 1.1, { 74 }) }, 'M', opts) == 0, 'Medium: a quarter apart is allowed')
    Test.expect(#DiffCheckOverlaps({ N(0, 4, { 72 }), N(0.5, 0.6, { 74 }) }, 'M', opts) == 1, 'Medium: an 8th apart is an error')
    Test.expect(#DiffCheckOverlaps({ N(0, 4, { 60 }), N(2, 2.1, { 62 }) }, 'E', opts) == 1, 'Easy: any overlap is an error')
end)
