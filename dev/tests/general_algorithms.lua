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
    -- 95% cap), then the 160 BPM test song bar: G O G Y R B R in 8ths at 157 BPM.
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
    -- The 160 BPM test song intro: a Green held 5/32 then Orange on beat 2, four times.
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

-- The 160 BPM test song part: a held R, then a bar of three short notes a dotted
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
    -- The 210 BPM test song guitar at 210 BPM (Auto = Drop 2).
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
        { { '.', 'R', 'R', 'R', 'RB', 'RY', 'YB', '.' }, 'fast bar 1' },
        { { 'O', '.', 'B', 'Y', 'R', 'Y', '.', 'Y' },    'fast bar 2' },
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

Test.it('Drop 1 with a rest already in the bar still takes the and of 4', function()
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
-- (difficulty_generate_retime.lua). Cases from the 210 BPM test song solo at 210 BPM,
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
        { 'bar 162: a 16th pair before beat 3 moves onto the triplets, never before its first note',
          '0:R~ 36:B 42:R 48:B 54:R~',
          '0:R 40:R 48:B 56:R' },   -- was 0:R 32:B 40:R 48:B 56:R; user rule 2026-10-10
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

Test.it('force-HOPO: 8th triplets rewritten as 8ths keep their hammer-ons', function()
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
    -- Expert bar 7 of a 210 BPM test song: forced on the notes at 12 and 24 (/24 QN). Two bars of
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
-- Generate: Medium (a 210 BPM test song; a 160 BPM test song)
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
    -- a 210 BPM test song: moving only the O made B B -> the bar moves down whole.
    local out = MediumOf('0:G 12:G 24:Y 48:B 60:G 72:O')
    Test.expect(Hard24(out) == '0:G 24:R 48:Y 72:B', 'bar 10: ' .. Hard24(out))
    -- a 160 BPM test song (157 BPM): moving only the O makes no repeat -> only the O moves.
    out = MediumOf('0:G 24:O 36:G 48:Y 60:R 72:B', 157)
    Test.expect(Hard24(out) == '0:G 24:B 48:Y 72:B', 'G O Y B bar: ' .. Hard24(out))
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
    -- a 160 BPM test song: D3 F3 C3 D3 in C2-E3. F3 is outside and folds to F2; the D3s and the
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

Test.it('Keys following a rewritten Pro Keys run takes its positions', function()
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

-- The 120 BPM test song lick as Hard has it, at 120 BPM: a pickup on the and of 4,
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

Test.it('a long run starting on the "and" of 1 stays on the beat grid, inside its notes, unbroken', function()
    -- 210 BPM: a chord on 1, then 16ths from the "and" of 1 to the end of the bar. The grid
    -- stays aligned to the beats (16, not 12 or 0: never before Expert's first note at 12)
    -- and carries straight across beat 3 - the user's hand reduction of a 210 BPM test song.
    local colors = { 1, 1, 1, 1, 3, 3, 2, 2, 3, 3, 2, 2, 1, 0 }
    local events = { Ev(0, 0.2, { 0, 1 }, 210, 0) }
    for k = 0, 13 do events[#events + 1] = Ev(0.5 + k * 0.25, 0.2, { colors[k + 1] }, 210, 0) end
    events[#events + 1] = Ev(4, 0.2, { 0 }, 210, 4)
    local out = Gen5PlanTier('gb', 'H', events, { busy_drop = 2 })
    local got = Grid24(out, 0)
    Test.expect(got:match('^0 16 24 32 40 48'), 'bar: ' .. got .. ' (expected 0 16 24 32 40 48 ...)')
end)

Test.it('a long run crossing beat 3 has no break (Pro Keys)', function()
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

Test.it('a long run puts no note after its last Expert note', function()
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

Test.it('a short group into beat 3 keeps leading into it', function()
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

Test.it('at or below 160 BPM a run of half a bar or more is rewritten', function()
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
    -- a 120 BPM test song's lick: 16th grace notes inside an 8th line (1, 1.25, 1.5) - no flourish
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

Test.it('6/8: Medium keeps each beat and the 8th after it, Easy the two beats', function()
    -- a 6/8 test song: counted in quarter notes, Medium kept 0, 1 and 2 of
    -- each bar. Official 6/8 Medium's commonest bar of 8ths is 0 0.5 1.5 2; official Easy
    -- keeps 0 and 1.5 (97%, 94%). Never three quarter notes across the bar's two beats.
    local hard = MeterBars(8, 3, 1.5, 105)
    local want = { M = '0 0.5 1.5 2', E = '0 1.5' }
    local medium = Gen5PlanTier('gb', 'M', hard)
    for dl, out in pairs({ M = medium, E = Gen5PlanTier('gb', 'E', medium) }) do
        for b = 0, 7 do
            local got = BarKept(out, b, 3)
            Test.expect(got == want[dl], ('%s bar %d keeps [%s], expected [%s]'):format(dl, b, got, want[dl]))
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

Test.it('Hard keeps a note Expert holds under moving notes', function()
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
    -- a 6/8 test song's last chord at 61 BPM: R and Y a 1/32 apart into a held O on the downbeat.
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

Test.section('Generate planner - Drums')

-- A drum hit: offs 0 Kick, 1 Red, 2 Yellow, 3 Blue, 4 Green; 4/4 bars.
local function DH(qn, offs, bpm)
    local bq = qn % 4
    return { qn = qn, qn_e = qn + 0.1, offs = offs, bpm = bpm or 120, bar_qn = bq, bar_len = 4, pulse = 1,
             down = math.abs(bq) < 1e-9 }
end
local function DHas(ev, o)
    if not ev then return false end
    for _, x in ipairs(ev.offs) do if x == o then return true end end
    return false
end
local function DAt(out, qn) for _, ev in ipairs(out) do if math.abs(ev.qn - qn) < 1e-6 then return ev end end end
local function OnEighths(out)
    for _, ev in ipairs(out) do
        local x = ev.qn * 2
        if math.abs(x - math.floor(x + 0.5)) > 1e-6 then return false, ev.qn end
    end
    return true
end

Test.it('Drums Hard: no 16ths at 140 BPM or faster', function()
    local x = {}
    for k = 0, 15 do
        local q = k * 0.25
        local offs = { 2 }
        if q == 0 or q == 2 then offs = { 0, 2 } elseif q == 1 or q == 3 then offs = { 1, 2 } end
        x[#x + 1] = DH(q, offs, 150)
    end
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    local ok, at = OnEighths(out)
    Test.expect(ok, 'a hit off the 8th grid at ' .. tostring(at))
    Test.expect(#out == 8, ('expected the 8 8ths, got %d'):format(#out))
end)

Test.it('Drums Hard below 140: a hi-hat 16th stream goes to 8ths, a 16th snare run of a beat stays', function()
    local x = {}
    for k = 0, 15 do x[#x + 1] = DH(k * 0.25, { 2 }, 120) end      -- bar 1: 16th hats
    x[#x + 1] = DH(4, { 0, 2 }, 120)
    for k = 0, 3 do x[#x + 1] = DH(6 + k * 0.25, { 1 }, 120) end   -- bar 2 beat 3: a beat of 16th snares
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    local hats = 0
    for _, ev in ipairs(out) do if ev.qn < 4 then hats = hats + 1 end end
    Test.expect(hats == 8, ('bar 1 hats: expected 8, got %d'):format(hats))
    for k = 0, 3 do
        Test.expect(DAt(out, 6 + k * 0.25) ~= nil, ('the short snare run lost %g'):format(6 + k * 0.25))
    end
end)

Test.it('Drums Hard below 140: a pair of 16th snares stays whole, a single one on the "e" goes', function()
    -- a 120 BPM test song: K R R K - the "e" + "and" snare pair is a run (hard_16th_min_run 2);
    -- beat 3: K R K - a single snare on the "e" loses it (RBN "remove about half").
    local x = { DH(0, { 0 }), DH(0.25, { 1 }), DH(0.5, { 1 }), DH(0.75, { 0 }),
                DH(2, { 0, 2 }), DH(2.25, { 1 }), DH(2.5, { 0, 2 }), DH(4, { 0, 4 }) }
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    Test.expect(DHas(DAt(out, 0.25), 1) and DHas(DAt(out, 0.5), 1), 'the snare pair should stay')
    Test.expect(not DHas(DAt(out, 2.25), 1), 'the single snare on the "e" should go')
end)

Test.it('Drums Hard: off-beat 16th kicks keep every other; the next bar\'s busy groove does not clear them', function()
    -- a 120 BPM test song: hats on the 8ths, kicks on every 16th off-beat, RG on beat 4's
    -- "and"; bar 2 starts a KY R KY groove whose busy downbeat kick reaches back.
    local x = {}
    for k = 0, 6 do
        x[#x + 1] = DH(k * 0.5, { 2 }, 120)
        x[#x + 1] = DH(k * 0.5 + 0.25, { 0 }, 120)
    end
    x[#x + 1] = DH(3.5, { 1, 4 }, 120)
    for k = 0, 7 do x[#x + 1] = DH(4 + k * 0.5, k % 2 == 0 and { 0, 2 } or { 1, 2 }, 120) end
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    local kicks = {}
    for _, ev in ipairs(out) do if ev.qn < 4 and DHas(ev, 0) then kicks[#kicks + 1] = ('%g'):format(ev.qn) end end
    Test.expect(#kicks >= 3 and tonumber(kicks[#kicks]) >= 2.5,
        'bar 1 should keep every other kick to its end, got ' .. table.concat(kicks, ','))
    for k = 2, #kicks do
        Test.expect(tonumber(kicks[k]) - tonumber(kicks[k - 1]) >= 0.75 - 1e-6, 'kicks closer than 3/4 QN: ' .. table.concat(kicks, ','))
    end
end)

Test.it('Drums Hard: the end-of-bar kick that comes back takes the 16th kick after it out', function()
    -- a 120 BPM test song: KG RY KY K RY KY RY KY K RY | KY ... - the busy
    -- beat-4 kick returns (EndOfBarKick), the kick on its "e" must go (official: 0-4% keep both).
    local function Bar(b, first)
        return { DH(b, { 0, first }), DH(b + 0.5, { 1, 2 }), DH(b + 1, { 0, 2 }), DH(b + 1.25, { 0 }),
                 DH(b + 1.5, { 1, 2 }), DH(b + 2, { 0, 2 }), DH(b + 2.5, { 1, 2 }), DH(b + 3, { 0, 2 }),
                 DH(b + 3.25, { 0 }), DH(b + 3.5, { 1, 2 }) }
    end
    local x = Bar(0, 4)
    for _, ev in ipairs(Bar(4, 2)) do x[#x + 1] = ev end
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    local prev
    for _, ev in ipairs(out) do
        if DHas(ev, 0) then
            Test.expect(not prev or ev.qn - prev >= 0.5 - 1e-6, ('kicks %g and %g closer than an 8th'):format(prev or 0, ev.qn))
            prev = ev.qn
        end
    end
    Test.expect(DHas(DAt(out, 3), 0), 'beat 4 should keep its kick')
end)

Test.it('Drums Hard: a busy beat kick with a lone kick a 16th after keeps the beat kick', function()
    local x = { DH(0, { 0, 2 }), DH(0.5, { 1, 2 }), DH(1, { 0, 2 }), DH(1.25, { 0 }), DH(1.5, { 1, 2 }),
                DH(2, { 0, 2 }), DH(2.5, { 1, 2 }), DH(3, { 0, 2 }), DH(3.5, { 1, 2 }), DH(4, { 0, 4 }) }
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    Test.expect(DHas(DAt(out, 1), 0), 'beat 2 should keep its kick')
    Test.expect(not DAt(out, 1.25), 'the kick on the "e" of 2 should go')
end)

Test.it('Drums Medium: a kick + cramped double crash keeps the kick and the Green (KYG -> KG)', function()
    local hard = { DH(0, { 0, 2 }), DH(1.5, { 1, 2 }), DH(2, { 0, 2, 4 }), DH(3, { 1, 2 }) }
    local out = GenDrumsPlanTier('M', hard, {})
    local ev = DAt(out, 2)
    Test.expect(ev and DHas(ev, 0) and DHas(ev, 4) and not DHas(ev, 2), 'expected KG, got ' .. (ev and table.concat(ev.offs, ',') or '-'))
end)

Test.it('Drums 170+ BPM, backbeat on the "and"s: Hard hands on the "and"s, kicks on 1 and 3; Medium/Easy follow', function()
    -- a 210 BPM test song: KY RY KY RY KY RY KY RY, two bars. Official Hard keeps the
    -- kicks on beats 1 and 3 in 87% of such bars (2026-10-15).
    local x = {}
    for k = 0, 15 do x[#x + 1] = DH(k * 0.5, k % 2 == 0 and { 0, 2 } or { 1, 2 }, 210) end
    local sections = { { qn = 0, name = 'intro' } }
    local hard = GenDrumsPlanTier('H', x, { fast_runs = 'thin', ctx = { sections = sections } })
    for k = 0, 3 do
        local beat = DAt(hard, k)
        Test.expect(not (beat and DHas(beat, 2)), ('Hard beat %d: no hat'):format(k + 1))
        Test.expect((beat ~= nil and DHas(beat, 0)) == (k % 2 == 0), ('Hard beat %d: a kick only on 1 and 3'):format(k + 1))
        Test.expect(DHas(DAt(hard, k + 0.5), 1) and DHas(DAt(hard, k + 0.5), 2), ('Hard "and" %d: snare + hat'):format(k + 1))
    end
    local med = GenDrumsPlanTier('M', hard, { ctx = { sections = sections } })
    local ands, kicks = 0, 0
    for _, ev in ipairs(med) do
        if ev.qn < 4 then
            if DHas(ev, 1) then ands = ands + 1 end
            if DHas(ev, 0) then kicks = kicks + 1 end
        end
    end
    Test.expect(ands == 4 and kicks == 1, ('Medium bar 1: 4 snares and 1 kick, got %d and %d'):format(ands, kicks))
end)

Test.it('Drums 170+ BPM: a half bar with the snare on both "and"s gets the same treatment', function()
    local x = { DH(0, { 0, 2 }, 210), DH(0.5, { 1, 2 }, 210), DH(1, { 0, 2 }, 210), DH(1.5, { 1 }, 210),
                DH(2, { 1 }, 210), DH(2.5, { 0, 4 }, 210), DH(3.5, { 0, 3 }, 210), DH(4, { 0, 4 }, 210) }
    local hard = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    Test.expect(not DHas(DAt(hard, 0), 2) and not DHas(DAt(hard, 1), 2), 'beats 1-2 lose their hat')
    Test.expect(DHas(DAt(hard, 0.5), 1) and DHas(DAt(hard, 1.5), 1), 'both "and" snares stay')
end)

Test.it('Drums Hard 170+ BPM: an 8th stream stays where Expert is faster, a copied one is broken', function()
    -- Expert 8th triplets (a tom/snare run) -> rewritten to 8ths: Expert is faster, so they stay.
    local x = { DH(0, { 0, 4 }, 210) }
    for k = 0, 8 do x[#x + 1] = DH(1 + k / 3, { 1 }, 210) end
    x[#x + 1] = DH(4, { 0, 4 }, 210)
    local h = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite' })
    local eighths = 0
    for _, ev in ipairs(h) do if ev.qn > 0.9 and ev.qn < 3.9 then eighths = eighths + 1 end end
    Test.expect(eighths >= 6, ('the rewritten 8ths should all stay, got %d'):format(eighths))
    -- Expert 8th hats copied: a run of four 8ths loses a hit.
    local y = {}
    for k = 0, 7 do y[#y + 1] = DH(k * 0.5, k == 0 and { 0, 4 } or { 3 }, 210) end
    y[#y + 1] = DH(4, { 0, 4 }, 210)
    local h2 = GenDrumsPlanTier('H', y, { fast_runs = 'thin' })
    local n = 0
    for _, ev in ipairs(h2) do if ev.qn < 4 then n = n + 1 end end
    Test.expect(n < 8, ('a copied 8th stream should be broken, kept %d'):format(n))
end)

Test.it('Drums Hard: a long 16th snare run is 8ths when thinned, 8th triplets when rewritten', function()
    local x = {}
    for k = 0, 15 do x[#x + 1] = DH(k * 0.25, { 1 }, 120) end
    x[#x + 1] = DH(4, { 0, 4 }, 120)
    local thin = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    Test.expect((OnEighths(thin)), 'thinned: a hit off the 8th grid')
    local re, log = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite' })
    local trip = 0
    for _, ev in ipairs(re) do
        local t3, t2 = ev.qn * 3, ev.qn * 2
        if ev.qn < 4 and math.abs(t3 - math.floor(t3 + 0.5)) < 1e-6 and math.abs(t2 - math.floor(t2 + 0.5)) > 1e-6 then
            trip = trip + 1
        end
    end
    Test.expect(trip > 0 and #log.retimed_bars == 1,
        ('rewritten: %d hits on 8th-triplet off-beats, %d bars'):format(trip, #log.retimed_bars))
end)

Test.it('Drums Hard: a disco-flip section is un-flipped (hat on Yellow, snare on Red with a hat)', function()
    local x = {}
    for k = 0, 15 do
        local q = k * 0.25
        local offs = { 1 }                               -- disco: Red is the hi-hat
        if q == 1 or q == 3 then offs = { 2 } end        -- ... and Yellow the snare
        if q == 0 or q == 2 then offs = { 0, 1 } end
        x[#x + 1] = DH(q, offs, 120)
    end
    local out, log = GenDrumsPlanTier('H', x, { fast_runs = 'thin', ctx = { disco = { { qn = 0, qn_e = 4 } } } })
    Test.expect(log.unflipped > 0, 'nothing un-flipped')
    local snare = DAt(out, 1)
    Test.expect(DHas(snare, 1) and DHas(snare, 2), 'beat 2: snare on Red with a hat on Yellow')
    for _, ev in ipairs(out) do
        Test.expect(not (DHas(ev, 1) and ev.qn ~= 1 and ev.qn ~= 3), ('Red off the backbeat at %g'):format(ev.qn))
    end
    Test.expect((OnEighths(out)), 'hats left on 16ths')
end)

Test.it('Drums Hard: kicks on 1, 3 and 4 under steady 8th hats; on every beat (under the snare too) when the hands are quiet', function()
    -- Steady 8th hats (a 128 BPM test song): official Hard keeps kicks on 1 and 3 in
    -- 49% of such bars, all four in 23%; the end of the bar keeps one more kick - beat 4
    -- when Expert has one (official: beat 4 33%, the "and" 27%, neither 39%).
    local x = { DH(0, { 0, 4 }), DH(0.5, { 2 }), DH(1, { 0, 1 }), DH(1.5, { 2 }), DH(2, { 0, 2 }), DH(2.5, { 2 }),
                DH(3, { 0, 1, 2 }), DH(3.5, { 0, 2 }), DH(4, { 0, 4 }) }
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'thin' })
    Test.expect(DHas(DAt(out, 0), 0) and DHas(DAt(out, 2), 0), 'kicks on 1 and 3 should stay')
    Test.expect(not DHas(DAt(out, 1), 0) and not DHas(DAt(out, 3.5), 0), 'kicks on 2 and the "and" of 4 should go')
    Test.expect(DHas(DAt(out, 3), 0), 'beat 4 should get its kick back (the end of the bar)')
    Test.expect(#out == 9, 'every hat and snare should stay')
    -- Quiet hands: snare on 2 and 4, nothing between - every beat keeps its kick, KR included.
    local q = GenDrumsPlanTier('H', { DH(0, { 0, 4 }), DH(1, { 0, 1 }), DH(2, { 0 }), DH(3, { 0, 1 }) }, { fast_runs = 'thin' })
    for _, b in ipairs({ 0, 1, 2, 3 }) do Test.expect(DHas(DAt(q, b), 0), ('quiet: beat %d lost its kick'):format(b + 1)) end
end)

Test.it('Drums Medium: kicks on quarter notes above 100 BPM, one a bar from 170', function()
    local out = GenDrumsPlanTier('M', { DH(0, { 0, 2 }), DH(0.5, { 0 }), DH(1, { 1, 2 }), DH(1.5, { 0 }),
                                        DH(2, { 0, 2 }), DH(3, { 1, 2 }) })
    for _, ev in ipairs(out) do
        Test.expect(not DHas(ev, 0) or math.abs(ev.qn - math.floor(ev.qn + 0.5)) < 1e-6,
            ('kick off the quarter grid at %g'):format(ev.qn))
    end
    Test.expect(DHas(DAt(out, 0), 0) and DHas(DAt(out, 2), 0), 'the kicks on 1 and 3 should stay')
    local fast = GenDrumsPlanTier('M', { DH(0, { 0, 2 }, 180), DH(1, { 1, 2 }, 180), DH(2, { 0, 2 }, 180),
                                         DH(3, { 1, 2 }, 180) })
    local kicks = 0
    for _, ev in ipairs(fast) do if DHas(ev, 0) then kicks = kicks + 1 end end
    Test.expect(kicks == 1, ('180 BPM: expected one kick in the bar, got %d'):format(kicks))
end)

Test.it('Drums Medium: kicks half a bar apart under busy hands, a quarter apart when the hands are quiet', function()
    -- a 120 BPM test song's oom-pah groove at 120 BPM: official Medium's commonest answer is
    -- KY RY Y RY KY RY Y RY (154 of 370 bars) - the kicks on 2 and 4 go. At 115 BPM here,
    -- under the Medium fallback's tempo floor (this one bar alone would trigger it).
    local busy = {}
    for k = 0, 7 do busy[#busy + 1] = DH(k * 0.5, k % 2 == 0 and { 0, 2 } or { 1, 2 }, 115) end
    local out = GenDrumsPlanTier('M', busy)
    Test.expect(#out == 8, ('all 8 hits stay, got %d'):format(#out))
    Test.expect(DHas(DAt(out, 0), 0) and DHas(DAt(out, 2), 0), 'kicks on 1 and 3 stay')
    Test.expect(not DHas(DAt(out, 1), 0) and not DHas(DAt(out, 3), 0), 'kicks on 2 and 4 go')
    -- Quiet hands (a crash on 1, nothing else on the cymbals): a kick on every beat stays.
    local quiet = { DH(0, { 0, 4 }), DH(1, { 0 }), DH(2, { 0 }), DH(3, { 0 }) }
    local q = GenDrumsPlanTier('M', quiet)
    local kicks = 0
    for _, ev in ipairs(q) do if DHas(ev, 0) then kicks = kicks + 1 end end
    Test.expect(kicks == 4, ('quiet hands: expected 4 kicks, got %d'):format(kicks))
end)

Test.it('Drums Medium: steady 8th hats go to quarters from 130 BPM, or below it when Medium would barely differ from Hard', function()
    -- One bar pattern repeated: hats on every 8th, kick on 1 and 3, snare on 2 and 4.
    local function Bars(bpm, n)
        local out = {}
        for b = 0, n - 1 do
            for k = 0, 7 do
                local q = b * 4 + k * 0.5
                local offs = { 2 }
                if k == 0 or k == 4 then offs = { 0, 2 } elseif k == 2 or k == 6 then offs = { 1, 2 } end
                out[#out + 1] = DH(q, offs, bpm)
            end
        end
        return out
    end
    local function Hats(out) local n = 0 for _, ev in ipairs(out) do if DHas(ev, 2) then n = n + 1 end end return n end
    local fast = GenDrumsPlanTier('M', Bars(132, 4))
    Test.expect(Hats(fast) == 16, ('132 BPM: expected quarter hats (16), got %d'):format(Hats(fast)))
    -- 125 BPM: under 130, but Medium would keep every note of this simple Hard -> fallback.
    local slow, log = GenDrumsPlanTier('M', Bars(125, 4))
    Test.expect(log.fallback ~= nil and Hats(slow) == 16, ('125 BPM: fallback should give quarter hats, got %d'):format(Hats(slow)))
    -- 110 BPM: under the fallback's tempo floor - the 8ths stay.
    local slower = GenDrumsPlanTier('M', Bars(110, 4))
    Test.expect(Hats(slower) == 32, ('110 BPM: 8th hats should stay (32), got %d'):format(Hats(slower)))
end)

Test.it('Drums: a hi-hat between two snare accents goes (Medium with a tom, Easy with any snare); a fill on the "and"s keeps them on Easy', function()
    -- a 128 BPM test song: hat on the beats, snare + blue tom on the "and"s.
    local toms = { [3] = { { qn = 0, qn_e = 4 } } }
    local hard = { DH(0, { 0, 2 }), DH(0.5, { 1, 3 }), DH(1, { 2 }), DH(1.5, { 1, 3 }), DH(2, { 0, 2 }),
                   DH(2.5, { 1, 3 }), DH(3, { 1 }), DH(3.5, { 1 }), DH(4, { 0, 4 }) }
    local med = GenDrumsPlanTier('M', hard, { ctx = { toms = toms } })
    Test.expect(not DAt(med, 1), 'Medium: the hat on beat 2 between the accents should go')
    Test.expect(DAt(med, 2) ~= nil and DHas(DAt(med, 2), 0) and not DHas(DAt(med, 2), 2), 'Medium: beat 3 keeps its kick, loses its hat')
    Test.expect(DHas(DAt(med, 0.5), 3) and DHas(DAt(med, 1.5), 3), 'Medium: the accents keep their tom')
    -- No tom: Medium leaves a snare-only sandwich to the between-hi-hats rule.
    local plain = GenDrumsPlanTier('M', { DH(0, { 2 }), DH(0.5, { 1 }), DH(1, { 2 }), DH(1.5, { 1 }), DH(2, { 2 }) },
                                   { between = 'keep' })
    Test.expect(DHas(DAt(plain, 1), 2), 'Medium, snare only: the hat stays')
    local easy = GenDrumsPlanTier('E', med, { ctx = { toms = toms } })
    for _, q in ipairs({ 0.5, 1.5, 2.5 }) do
        Test.expect(DAt(easy, q) ~= nil, ('Easy should keep the accent on %g'):format(q))
    end
    -- No hands between the accents. The kick on beat 3 stays since 2026-10-14: the half bar's
    -- backbeat is on the "and"s (HardAndBackbeat from easy_and_backbeat_bpm), the beat's hat
    -- goes, the bar has no cymbal left and Easy keeps its kicks (a 128 BPM test song).
    Test.expect(not DAt(easy, 1), 'Easy: nothing on beat 2 between the accents')
    local b3 = DAt(easy, 2)
    Test.expect(not b3 or (#b3.offs == 1 and DHas(b3, 0)), 'Easy: beat 3 at most a kick')
end)

Test.it('Drums: a two-hand "and" (hat + tom) keeps its hat on Medium; Easy takes the hats off only where Easy itself went to quarters', function()
    local toms = { [3] = { { qn = 0, qn_e = 8 } } }
    -- Hard: 8th hats, hat + blue tom on beat 4 and its "and" (a 128 BPM test song's ending), 132 BPM
    -- so Medium's hats go to quarter notes.
    local hard = { DH(0, { 0, 4 }, 132), DH(0.5, { 2 }, 132), DH(1, { 2, 3 }, 132), DH(1.5, { 2 }, 132),
                   DH(2, { 0, 2 }, 132), DH(2.5, { 2 }, 132), DH(3, { 2, 3 }, 132), DH(3.5, { 2, 3 }, 132),
                   DH(4, { 0, 2 }, 132) }   -- a hat, not a crash: no Easy before-crash rule here
    local med = GenDrumsPlanTier('M', hard, { ctx = { toms = toms } })
    Test.expect(not DAt(med, 2.5), 'Medium: the hat-only "and" goes (quarter hats)')
    Test.expect(DHas(DAt(med, 3.5), 2) and DHas(DAt(med, 3.5), 3), 'Medium: the two-hand "and" keeps its hat and tom')
    -- Easy from that Medium (already on quarters): keeps the "and" as Medium has it.
    local easy = GenDrumsPlanTier('E', med, { ctx = { toms = toms } })
    Test.expect(DHas(DAt(easy, 3.5), 2), 'Easy after a quarter-hat Medium: the "and" keeps its hat')
    -- Easy from a Medium still on 8th hats at 135 BPM (a hand-made Medium - a generated one
    -- would already be on quarters): Easy moves to quarters itself, so the two-hand "and"
    -- keeps only its tom and the beat before loses its hat.
    local med8 = { DH(0, { 0, 2 }, 135), DH(0.5, { 2 }, 135), DH(1, { 1, 2 }, 135), DH(1.5, { 2 }, 135),
                   DH(2, { 0, 2 }, 135), DH(2.5, { 2 }, 135), DH(3, { 2, 3 }, 135), DH(3.5, { 2, 3 }, 135),
                   DH(4, { 0, 2 }, 135) }
    local easy8 = GenDrumsPlanTier('E', med8, { ctx = { toms = toms } })
    Test.expect(not DAt(easy8, 2.5), 'Easy: the hat-only "and" goes (quarter hats)')
    Test.expect(not DHas(DAt(easy8, 3.5), 2) and DHas(DAt(easy8, 3.5), 3), 'Easy: the "and" keeps only its tom')
    Test.expect(not DHas(DAt(easy8, 3), 2) and DHas(DAt(easy8, 3), 3), 'Easy: the beat before loses its hat, keeps its tom')
end)

Test.it('Drums: two two-hand hits an 8th apart with a change of drum - the first loses its drum (Medium and Easy)', function()
    -- a 128 BPM test song: Yb RY RY RY -> Y RY RY RY. (A tom marker covers the hits
    -- before its end, so it runs past the tom hit at 1.)
    local toms = { [3] = { { qn = 0, qn_e = 1.25 } } }
    local up = { DH(0, { 0, 2 }), DH(1, { 2, 3 }), DH(1.5, { 1, 2 }), DH(2, { 1, 2 }), DH(2.5, { 1, 2 }), DH(3, { 1 }),
                 DH(4, { 0, 4 }) }
    for _, dl in ipairs({ 'M', 'E' }) do
        local out = GenDrumsPlanTier(dl, up, { ctx = { toms = toms }, between = 'keep' })
        local a = DAt(out, 1)
        Test.expect(a ~= nil and DHas(a, 2) and not DHas(a, 3), dl .. ': the tom before the snare should go, its hat stay')
        Test.expect(DHas(DAt(out, 1.5), 1) and DHas(DAt(out, 1.5), 2), dl .. ': the next hit keeps snare and hat')
        Test.expect(DHas(DAt(out, 2), 1), dl .. ': same drum again - nothing changes')
    end
end)

Test.it('Drums Medium/Easy: a hat + snare an 8th before a crash loses its hat (a cymbal change)', function()
    -- a 128 BPM test song, into the next bar: ... KR RY | G. Easy's own rule (EasyBeforeCrash)
    -- and, since 2026-10-13, the cymbal-change rule on Medium too (CymbalChanges).
    local up = { DH(2, { 0, 2 }), DH(3, { 0, 1 }), DH(3.5, { 1, 2 }), DH(4, { 0, 4 }), DH(5, { 1, 2 }) }
    for _, dl in ipairs({ 'E', 'M' }) do
        local out = GenDrumsPlanTier(dl, up, { between = 'keep' })
        Test.expect(DHas(DAt(out, 3.5), 1) and not DHas(DAt(out, 3.5), 2), dl .. ': the "and" before the crash keeps its snare, loses its hat')
        Test.expect(DHas(DAt(out, 4), 4), dl .. ': the crash stays')
    end
end)

Test.it('Drums Medium: a cymbal change an 8th apart drops the hi-hat/ride; after a double crash (now Green) too', function()
    -- a 120 BPM test song: RY | RG -> R | RG (the crash keeps its snare).
    local a = GenDrumsPlanTier('M', { DH(3, { 1, 2 }), DH(3.5, { 1, 2 }), DH(4, { 1, 4 }), DH(5, { 1 }) }, { between = 'keep' })
    Test.expect(not DHas(DAt(a, 3.5), 2) and DHas(DAt(a, 4), 1) and DHas(DAt(a, 4), 4), 'RY | RG -> R | RG')
    -- a 210 BPM test song: RY then B -> R then B.
    local b = GenDrumsPlanTier('M', { DH(0, { 0, 4 }), DH(1.5, { 1, 2 }), DH(2, { 3 }), DH(3, { 1 }) }, { between = 'keep' })
    Test.expect(not DHas(DAt(b, 1.5), 2) and DHas(DAt(b, 2), 3), 'RY then B -> R then B')
    -- A double crash (B + G, room before it) with a hat + snare an 8th after it: the double
    -- crash is a single Green (DoubleCrashes, every tier since 2026-10-15), and the hit after
    -- it - another cymbal an 8th later - keeps only its snare.
    local c = GenDrumsPlanTier('M', { DH(0, { 1 }), DH(2, { 3, 4 }), DH(2.5, { 1, 2 }), DH(3.5, { 1 }) }, { between = 'keep' })
    Test.expect(not DHas(DAt(c, 2), 3) and DHas(DAt(c, 2), 4), 'the double crash becomes Green')
    Test.expect(DHas(DAt(c, 2.5), 1) and not DHas(DAt(c, 2.5), 2), 'the hit after keeps only its snare')
end)

Test.it('Drums Medium: a snare between a hi-hat and a crash is not "between hi-hats"', function()
    -- a 128 BPM test song: ... RY | R on the "and" of 4 | crash on the downbeat.
    local up = { DH(2, { 0, 2 }), DH(3, { 1, 2 }), DH(3.5, { 1 }), DH(4, { 0, 4 }), DH(5, { 1, 2 }) }
    local med = GenDrumsPlanTier('M', up)
    Test.expect(DHas(DAt(med, 3.5), 1), 'the snare before the crash should stay')
    -- The same snare with a hi-hat after it still goes (an 8th between hats a quarter apart).
    local hats = GenDrumsPlanTier('M', { DH(2, { 0, 2 }), DH(3, { 2 }), DH(3.5, { 1 }), DH(4, { 0, 2 }), DH(5, { 1, 2 }) })
    Test.expect(not DAt(hats, 3.5), 'between two hi-hats the 8th snare still goes')
end)

Test.it('Drums Hard: under busy hands an 8th kick paired with beat 3 stays (before it first), not both', function()
    local function Bar(kicks, bpm)
        local evs = {}
        for k = 0, 7 do
            local q = k * 0.5
            local offs = (k == 2 or k == 6) and { 1, 2 } or { 2 }
            if kicks[k] then table.insert(offs, 1, 0) end
            evs[#evs + 1] = DH(q, offs, bpm)
        end
        evs[#evs + 1] = DH(4, { 0, 4 }, bpm)
        return evs
    end
    local function Kicks(out)
        local t = {}
        for k = 0, 7 do t[#t + 1] = DHas(DAt(out, k * 0.5), 0) and 'K' or '.' end
        return table.concat(t)
    end
    -- a 160 BPM test song: K . . K K . . . at 160 BPM stays (official 93%).
    Test.expect(Kicks(GenDrumsPlanTier('H', Bar({ [0] = 1, [3] = 1, [4] = 1 }, 160), { fast_runs = 'thin' })) == 'K..KK...',
        'K..KK... should stay')
    -- K . . . K K . K -> K . . . K K . . (official 46-62%).
    Test.expect(Kicks(GenDrumsPlanTier('H', Bar({ [0] = 1, [4] = 1, [5] = 1, [7] = 1 }, 160), { fast_runs = 'thin' })) == 'K...KK..',
        'K...KK.K should become K...KK..')
    -- Both sides of beat 3: just 1 and 3 (official 83-100%).
    Test.expect(Kicks(GenDrumsPlanTier('H', Bar({ [0] = 1, [3] = 1, [4] = 1, [5] = 1 }, 160), { fast_runs = 'thin' })) == 'K...K...',
        'K..KKK.. should become K...K...')
end)

-- One 4/4 bar of ride 8ths (Blue, snare on 3) with kicks on the given 8th slots, then the next
-- downbeat; Hard's kicks on the bar's 8th grid as 'K' / '.'.
local function RideBar(kicks, bpm)
    local evs = {}
    for k = 0, 7 do
        local offs = k == 4 and { 1, 3 } or { 3 }
        if kicks[k] then table.insert(offs, 1, 0) end
        evs[#evs + 1] = DH(k * 0.5, offs, bpm)
    end
    evs[#evs + 1] = DH(4, { 0, 4 }, bpm)
    return evs
end
local function HardKicks(out)
    local t = {}
    for k = 0, 7 do t[#t + 1] = DHas(DAt(out, k * 0.5), 0) and 'K' or '.' end
    return table.concat(t)
end

Test.it('Drums Hard: quarter kicks under 8th hands go to 1 and 3, with no end-of-bar kick', function()
    -- Official Hard: 1 and 3 in 424 of 524 such bars at 140-169 BPM; 1, 3 and 4 is not an answer.
    local out = GenDrumsPlanTier('H', RideBar({ [0] = 1, [2] = 1, [4] = 1, [6] = 1 }, 154), { fast_runs = 'thin' })
    Test.expect(HardKicks(out) == 'K...K...', HardKicks(out))
end)

Test.it('Drums Hard: 8th kicks under 8th hands go to a kick on every beat', function()
    -- One step slower than Expert, so a build from quarter kicks to 8th kicks stays audible.
    local all = {}
    for k = 0, 7 do all[k] = 1 end
    for _, bpm in ipairs({ 120, 154, 180 }) do
        local out = GenDrumsPlanTier('H', RideBar(all, bpm), { fast_runs = 'thin' })
        Test.expect(HardKicks(out) == 'K.K.K.K.', ('%d BPM: %s'):format(bpm, HardKicks(out)))
    end
end)

Test.it('Drums Hard: the paired kick reads Expert, not the rewritten fill', function()
    -- 8th kicks on beats 1-2, then 16th snares with kicks on the 8ths from beat 3: the fill
    -- rewrite moves the "and" of 3 off the 8th grid, which once made the "and" of 2 kick
    -- come back next to beat 3. Expert has both "and"s, so neither is paired with beat 3.
    local x = {}
    for k = 0, 3 do x[#x + 1] = DH(k * 0.5, { 0, 3 }, 154) end
    for k = 0, 7 do
        local q = 2 + k * 0.25
        x[#x + 1] = DH(q, k % 2 == 0 and { 0, 1 } or { 1 }, 154)
    end
    x[#x + 1] = DH(4, { 0, 4 }, 154)
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite' })
    Test.expect(not DHas(DAt(out, 1.5), 0), 'the "and" of 2 kick should not come back')
    Test.expect(DHas(DAt(out, 2), 0), 'beat 3 keeps its kick')
end)

Test.it('Drums Hard: a rewritten roll into the downbeat never starts before its first Expert note', function()
    -- a 160 BPM test song (just over 160 BPM): 16th snares from the "a" of 3 into the
    -- downbeat were laid out from the "and" of 3's triplet; now from beat 4.
    local x = { DH(0, { 0, 2 }, 161), DH(1, { 1, 2 }, 161), DH(2, { 0, 2 }, 161) }
    for _, q in ipairs({ 2.75, 3, 3.25, 3.5, 3.75 }) do x[#x + 1] = DH(q, { 1 }, 161) end
    x[#x + 1] = DH(4, { 0, 1, 4 }, 161)
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite' })
    for _, ev in ipairs(out) do
        Test.expect(not (ev.qn > 2 + 1e-6 and ev.qn < 2.75 - 1e-6), ('a rewritten hit at %g, before the roll starts'):format(ev.qn))
    end
    Test.expect(DAt(out, 3) ~= nil, 'the rewrite should start on beat 4')
end)

Test.it('Drums: a fill Medium broke into pieces is one run on Easy; the snare + tom before a crash loses its tom', function()
    -- a 160 BPM test song: Rg (snare + green tom) on 8ths, Medium broke
    -- the runs of four, then a crash.
    local toms = { [4] = { { qn = 0, qn_e = 8 } } }
    local med = { DH(0, { 0 }, 160) }
    for _, q in ipairs({ 0.5, 1, 2, 2.5, 3, 4, 4.5, 5, 6, 6.5, 7 }) do med[#med + 1] = DH(q, { 1, 4 }, 160) end
    med[#med + 1] = DH(8, { 0, 4 }, 160)
    local easy = GenDrumsPlanTier('E', med, { ctx = { toms = toms } })
    Test.expect(not DAt(easy, 0.5), 'Easy: no 8th pair at the start - quarters from the start')
    for _, q in ipairs({ 1, 2, 3, 4, 5, 6 }) do Test.expect(DAt(easy, q) ~= nil, ('Easy: the beat at %g should stay'):format(q)) end
    Test.expect(DHas(DAt(easy, 7), 1) and not DHas(DAt(easy, 7), 4), 'Easy: the last hit before the crash keeps its snare, loses its tom')
    local medium = GenDrumsPlanTier('M', med, { ctx = { toms = toms } })
    local last
    for _, ev in ipairs(medium) do if ev.qn < 8 - 1e-6 then last = ev end end
    Test.expect(last ~= nil and DHas(last, 1) and not DHas(last, 4), 'Medium: the last hit before the crash loses its tom')
end)

Test.it('Drums Hard fallback: a Hard barely easier than Expert drops hat-only "and"s per "Hard 8th runs"', function()
    -- A simple Expert (a 160 BPM test song): steady 8th hats, kick on 1 and 3, snare on 2 and 4.
    -- Bar 1 starts with a crash, bar 2 with a hat.
    local x = {}
    for b = 0, 1 do
        for k = 0, 7 do
            local q = b * 4 + k * 0.5
            local offs = { 2 }
            if k == 0 then offs = b == 0 and { 0, 4 } or { 0, 2 } elseif k == 4 then offs = { 0, 2 }
            elseif k == 2 or k == 6 then offs = { 1, 2 } end
            x[#x + 1] = DH(q, offs, 150)
        end
    end
    x[#x + 1] = DH(8, { 0, 4 }, 150)
    local out, log = GenDrumsPlanTier('H', x, { fast_runs = 'thin', busy_drop = 1 })
    Test.expect(log.hard_fallback ~= nil, 'the fallback should fire (Hard would equal Expert)')
    Test.expect(not DAt(out, 0.5), 'Drop 1, crash on 1: the "and" of 1 goes')
    Test.expect(DAt(out, 3.5) ~= nil, 'Drop 1, crash on 1: the "and" of 4 stays')
    Test.expect(not DAt(out, 7.5) and DAt(out, 4.5) ~= nil, 'Drop 1, no crash: the "and" of 4 goes, the "and" of 1 stays')
    local two = GenDrumsPlanTier('H', x, { fast_runs = 'thin', busy_drop = 2 })
    Test.expect(not DAt(two, 0.5) and not DAt(two, 3.5) and DAt(two, 1.5) ~= nil, 'Drop 2, crash on 1: the "and"s of 1 and 4 go, not of 2')
    Test.expect(not DAt(two, 7.5) and not DAt(two, 5.5), 'Drop 2, no crash: the "and"s of 4 and 2 go')
end)

Test.it('Drums Medium: at most two gems - a three-limb hit loses the kick', function()
    local out = GenDrumsPlanTier('M', { DH(0, { 0, 1, 2 }), DH(1, { 1, 2 }) })
    local ev = DAt(out, 0)
    Test.expect(ev ~= nil and #ev.offs == 2 and not DHas(ev, 0), 'KRY should become RY')
end)

Test.it('Drums Medium: kick/snare between quarter-note hats - Beats keeps the beat ones, Keep all, None none', function()
    local hard = { DH(0, { 0, 2 }), DH(1, { 2 }), DH(1.5, { 1 }), DH(2, { 2 }), DH(2.5, { 0 }), DH(3, { 2 }),
                   DH(4.5, { 2 }), DH(5, { 1 }), DH(5.5, { 2 }) }
    local beats = GenDrumsPlanTier('M', hard, { between = 'beats' })
    Test.expect(not DAt(beats, 1.5) and not DAt(beats, 2.5), 'Beats: the 8th snare/kick between hats should go')
    Test.expect(DAt(beats, 5) ~= nil, 'Beats: the snare on beat 2 between hats should stay')
    local keep = GenDrumsPlanTier('M', hard, { between = 'keep' })
    Test.expect(DAt(keep, 1.5) ~= nil, 'Keep: the 8th snare should stay')
    local none = GenDrumsPlanTier('M', hard, { between = 'none' })
    Test.expect(not DAt(none, 5), 'None: the snare on beat 2 between hats should go too')
end)

Test.it('Drums Easy: kick + snare in a verse on the hi-hat, a two-hand beat in the chorus, never a gem with a kick', function()
    local med = {}
    for bar = 0, 3 do
        local b = bar * 4
        med[#med + 1] = DH(b, { 0, 2 }); med[#med + 1] = DH(b + 1, { 1, 2 })
        med[#med + 1] = DH(b + 2, { 0, 2 }); med[#med + 1] = DH(b + 3, { 1, 2 })
    end
    local sections = { { qn = 0, name = 'verse_1' }, { qn = 8, name = 'chorus_1' } }
    local out, log = GenDrumsPlanTier('E', med, { ctx = { sections = sections } })
    Test.expect(log.easy_types.ks == 1 and log.easy_types.hands == 1, 'one kick+snare and one two-hand section')
    for _, ev in ipairs(out) do
        Test.expect(not (DHas(ev, 0) and #ev.offs > 1), ('a gem paired with a kick at %g'):format(ev.qn))
        if ev.qn < 8 then
            Test.expect(not DHas(ev, 2), ('verse kept a hi-hat at %g'):format(ev.qn))
        else
            Test.expect(not DHas(ev, 0), ('chorus kept a kick at %g'):format(ev.qn))
        end
    end
    Test.expect(DHas(DAt(out, 0), 0), 'the verse should keep its kick on 1')
end)

Test.it('Drums Easy: a verse with sparse kick + snare keeps its 2-hand beat; a ride verse with enough goes kick + snare', function()
    -- Verse 1 (0-12, hi-hat): one kick or snare a bar of 3/4 (a 3/4 test song at 155 BPM `RY Y Y` /
    -- `KY Y Y`), 0.33 per quarter note. Verse 2 (12-20, ride): kick/snare on every beat.
    local med = {}
    for bar = 0, 3 do
        local b = bar * 3
        med[#med + 1] = DH(b, { bar % 2 == 0 and 1 or 0, 2 }, 155)
        med[#med + 1] = DH(b + 1, { 2 }, 155); med[#med + 1] = DH(b + 2, { 2 }, 155)
    end
    for k = 0, 7 do med[#med + 1] = DH(12 + k, { k % 2 == 0 and 0 or 1, 3 }, 120) end
    local sections = { { qn = 0, name = 'verse_1a' }, { qn = 12, name = 'verse_2a' } }
    local out = GenDrumsPlanTier('E', med, { ctx = { sections = sections } })
    local hats, rides = 0, 0
    for _, ev in ipairs(out) do
        if ev.qn < 12 and DHas(ev, 2) then hats = hats + 1 end
        if ev.qn >= 12 and DHas(ev, 3) then rides = rides + 1 end
    end
    Test.expect(hats == 12, ('the sparse hi-hat verse should keep all 12 hats, kept %d'):format(hats))
    Test.expect(rides == 0, ('the busy ride verse should play kick + snare, kept %d rides'):format(rides))
end)

Test.it('Drums 2X: a tier plays the kicks of the PART DRUMS tier one step up, never thinned further', function()
    -- 2X Expert: 8th kicks under 8th hats at 150 BPM. PART DRUMS Expert (single pedal):
    -- kicks on the beats, plus one on the "and" of 4 where 2X has no hit.
    local x2, x1 = {}, {}
    for k = 0, 7 do x2[#x2 + 1] = DH(k * 0.5, { 0, 2 }, 150) end
    for k = 0, 3 do x1[#x1 + 1] = DH(k, { 0, 2 }, 150) end
    x1[#x1 + 1] = DH(3.75, { 0 }, 150)
    local input = GenDrums2xInput(x2, x1)
    local kicks = {}
    for _, ev in ipairs(input) do if DHas(ev, 0) then kicks[#kicks + 1] = ('%g'):format(ev.qn) end end
    Test.expect(table.concat(kicks, ',') == '0,1,2,3,3.75', 'input kicks should be PART DRUMS\'s, got ' .. table.concat(kicks, ','))
    Test.expect(DHas(DAt(input, 0.5), 2) and not DHas(DAt(input, 0.5), 0), 'the 2X hands stay, their kicks go')
    -- Hard keeps all four beat kicks (normal Hard at 150 BPM spaces them half a bar apart
    -- under busy hands); 3.75 is a 16th at 150 BPM, so the 16th rule still takes it.
    local hard = GenDrumsPlanTier('H', input, { fast_runs = 'thin', keep_kicks = true })
    local hk = {}
    for _, ev in ipairs(hard) do if DHas(ev, 0) then hk[#hk + 1] = ('%g'):format(ev.qn) end end
    Test.expect(table.concat(hk, ',') == '0,1,2,3', 'Hard kicks should be 0,1,2,3, got ' .. table.concat(hk, ','))
    local plain = GenDrumsPlanTier('H', input, { fast_runs = 'thin' })
    local pk = 0
    for _, ev in ipairs(plain) do if DHas(ev, 0) then pk = pk + 1 end end
    Test.expect(pk < 4, ('without keep_kicks Hard should thin them, kept %d'):format(pk))
end)

Test.it('Drums 2X with no PART DRUMS: the in-memory single-pedal Expert is what "Remove 2x kicks" leaves', function()
    -- A bar of 16th kicks under quarter hats, then a lone kick on the next downbeat.
    local x2 = {}
    for k = 0, 15 do x2[#x2 + 1] = DH(k * 0.25, k % 4 == 0 and { 0, 2 } or { 0 }, 150) end
    x2[#x2 + 1] = DH(4, { 0, 4 }, 150)
    local single = GenDrumsSinglePedal(x2)
    local qns, kept = {}, {}
    for _, ev in ipairs(x2) do qns[#qns + 1] = ev.qn end
    local marks = DoubleBassPlan(qns, function(qn) return math.abs(qn % 4) < 1e-9 end)
    for i, q in ipairs(qns) do if not marks[i] then kept[#kept + 1] = ('%g'):format(q) end end
    local got = {}
    for _, ev in ipairs(single) do if DHas(ev, 0) then got[#got + 1] = ('%g'):format(ev.qn) end end
    Test.expect(table.concat(got, ',') == table.concat(kept, ','),
        ('kicks %s, DoubleBassPlan keeps %s'):format(table.concat(got, ','), table.concat(kept, ',')))
    Test.expect(#got < #qns, 'some second-foot kicks should go')
    Test.expect(DHas(DAt(single, 1), 2) and DHas(DAt(single, 4), 4), 'the hands stay')
end)

Test.it('Drums Easy two-hand bar: a half bar with no hand hit keeps its kicks', function()
    local med = { DH(0, { 0, 4 }), DH(1, { 0, 3 }), DH(2, { 0 }), DH(3, { 0 }), DH(4, { 0, 4 }), DH(5, { 0, 2 }), DH(6, { 1, 2 }) }
    local out = GenDrumsPlanTier('E', med, { ctx = { sections = { { qn = 0, name = 'intro' } } } })
    Test.expect(DHas(DAt(out, 0), 4) and not DHas(DAt(out, 0), 0), 'beat 1: the crash, no kick')
    Test.expect(DHas(DAt(out, 2), 0) and DHas(DAt(out, 3), 0), 'beats 3 and 4 (no hands) keep their kicks')
    Test.expect(not DHas(DAt(out, 4), 0) and not DHas(DAt(out, 5), 0), 'bar 2 has hands in its first half: no kicks there')
end)

Test.it('Drums Easy at 140+ BPM: a lone drum "and" between two beat hits goes; at 120 it stays', function()
    -- a 3/4 test song at 155 BPM: G, R on the "and", B, then RB.
    local function Bar(bpm) return { DH(0, { 4 }, bpm), DH(0.5, { 1 }, bpm), DH(1, { 3 }, bpm), DH(2, { 1, 3 }, bpm) } end
    local sections = { { qn = 0, name = 'chorus' } }
    -- 'beats': with the default 'hands' the no-three-8ths rule takes the ride on beat 2 instead
    -- (the least important hand gem) and the snare is no longer between two beat hits.
    local fast, log = GenDrumsPlanTier('E', Bar(155), { ctx = { sections = sections }, eighth_hands = 'beats' })
    -- Since 2026-10-14 the no-three-8ths rule (LowerEighthHands, 'beats') takes it first.
    Test.expect(not DAt(fast, 0.5) and (log.lone_ands or 0) + (log.eighth_hands or 0) == 1,
                '155 BPM: the snare on the "and" should go')
    local slow = GenDrumsPlanTier('E', Bar(120), { ctx = { sections = sections } })
    Test.expect(DAt(slow, 0.5) ~= nil, '120 BPM: the snare on the "and" should stay')
end)

Test.it('Drums Medium at 150+ BPM: of three hand hits an 8th apart one goes - Beats: the "and", Hands: the hi-hat', function()
    -- a 160 BPM test song: ... KY | RY on the "and" | RY on beat 4.
    local function Bar(bpm)
        return { DH(0, { 0, 2 }, bpm), DH(1, { 1, 2 }, bpm), DH(2, { 0, 2 }, bpm), DH(2.5, { 1, 2 }, bpm),
                 DH(3, { 1, 2 }, bpm), DH(4, { 0, 2 }, bpm) }
    end
    local beats, log = GenDrumsPlanTier('M', Bar(160), { between = 'keep', eighth_hands = 'beats' })
    Test.expect(not DAt(beats, 2.5) and DHas(DAt(beats, 2), 2) and DHas(DAt(beats, 3), 1), 'Beats: KY . RY')
    Test.expect(log.eighth_hands == 1, ('Beats: expected 1 hit changed, got %s'):format(tostring(log.eighth_hands)))
    local hands = GenDrumsPlanTier('M', Bar(160), { between = 'keep', eighth_hands = 'hands' })
    local b3 = DAt(hands, 2)
    Test.expect(b3 ~= nil and DHas(b3, 0) and not DHas(b3, 2), 'Hands: beat 3 keeps its kick, loses its hi-hat')
    Test.expect(DHas(DAt(hands, 2.5), 1) and DHas(DAt(hands, 3), 1), 'Hands: both snares stay')
    local slow = GenDrumsPlanTier('M', Bar(140), { between = 'keep', eighth_hands = 'beats' })
    Test.expect(DHas(DAt(slow, 2.5), 1) and DHas(DAt(slow, 2), 2), '140 BPM: all three stay on Medium')
end)

Test.it('Drums Medium Hands at 150+ BPM: the hit whose loss leaves over a quarter silent counts one step more', function()
    -- a 3/4 test song at 155 BPM: R on beat 2, b on beat 3, g on its "and", KG on the next
    -- downbeat (here beat 4 of a 4/4 bar - the same 8th after the "and").
    -- The b ranks below the g, but dropping it leaves beat 2 to the "and" of 3 empty: the g goes.
    local up = { DH(0, { 1 }, 155), DH(1, { 1 }, 155), DH(2, { 3 }, 155), DH(2.5, { 4 }, 155), DH(3, { 0, 4 }, 155),
                 DH(4, { 1 }, 155) }
    local toms = { [3] = { { qn = 2, qn_e = 2.1 } }, [4] = { { qn = 2.5, qn_e = 2.6 } } }
    local out = GenDrumsPlanTier('M', up, { between = 'keep', eighth_hands = 'hands', ctx = { toms = toms } })
    Test.expect(DHas(DAt(out, 2), 3) and not DAt(out, 2.5), 'the Blue tom on beat 3 stays, the Green tom on the "and" goes')
    Test.expect(DHas(DAt(out, 3), 4), 'the crash on the downbeat stays')
end)

Test.it('Drums Medium: a fill Hard rewrote to 8th triplets is reduced from Expert\'s notes', function()
    -- a 210 BPM test song / a 120 BPM test song: Medium's 8th grid found
    -- nothing of Hard's triplets but the beats.
    local x, h = {}, {}
    for k = 0, 7 do x[#x + 1] = DH(k * 0.25, { 1 }) end           -- Expert: 16th snares, beats 1-2
    for k = 0, 5 do h[#h + 1] = DH(k / 3, { 1 }) end              -- Hard: the same as 8th triplets
    x[#x + 1] = DH(2, { 0, 4 }); h[#h + 1] = DH(2, { 0, 4 })
    x[#x + 1] = DH(3, { 1 }); h[#h + 1] = DH(3, { 1 })
    local ctx = { fills = { { qn = 0, qn_e = 2 } } }
    local with, log = GenDrumsPlanTier('M', h, { ctx = ctx, expert = x })
    Test.expect(DAt(with, 0.5) ~= nil and DAt(with, 1.5) ~= nil, 'with Expert: the fill keeps its "and"s')
    Test.expect(log.expert_runs == 1, ('expected 1 bar from Expert, got %s'):format(tostring(log.expert_runs)))
    local without = GenDrumsPlanTier('M', h, { ctx = ctx })
    Test.expect(not DAt(without, 0.5), 'without Expert: only the beats (the old behaviour)')
end)

Test.it('Drums Easy from 110 BPM: a bar with the backbeat on the "and"s plays the hands on the "and"s', function()
    -- a 120 BPM test song (chant_1, 120 BPM): G R Y RY Y RY Y RY -> G R . RY . RY . RY.
    local function Bar(bpm)
        return { DH(0, { 4 }, bpm), DH(0.5, { 1 }, bpm), DH(1, { 2 }, bpm), DH(1.5, { 1, 2 }, bpm), DH(2, { 2 }, bpm),
                 DH(2.5, { 1, 2 }, bpm), DH(3, { 2 }, bpm), DH(3.5, { 1, 2 }, bpm), DH(4, { 4 }, bpm) }
    end
    local ctx = { sections = { { qn = 0, name = 'chant_1' } } }
    local out = GenDrumsPlanTier('E', Bar(120), { ctx = ctx })
    Test.expect(not DAt(out, 1) and not DAt(out, 2) and not DAt(out, 3), '120 BPM: the beats\' hi-hats go')
    Test.expect(DHas(DAt(out, 0), 4) and DHas(DAt(out, 1.5), 1) and DHas(DAt(out, 1.5), 2), 'the crash and the "and"s stay')
    local slow = GenDrumsPlanTier('E', Bar(100), { ctx = ctx })
    Test.expect(DHas(DAt(slow, 1), 2), '100 BPM: the beats keep their hi-hats')
end)

Test.it('Drums Easy from 120 BPM: a run of 5+ 8th snare hits keeps only the beats; 4 stay', function()
    -- a 128 BPM test song (128 BPM): Medium RY RY RY RY R R from beat 2.
    local function Run(n, bpm)
        local m = { DH(0, { 0, 2 }, bpm) }
        for k = 0, n - 1 do m[#m + 1] = DH(1 + k * 0.5, { 1, 2 }, bpm) end
        m[#m + 1] = DH(5, { 0, 4 }, bpm)
        return m
    end
    local ctx = { sections = { { qn = 0, name = 'intro' } } }
    local out, log = GenDrumsPlanTier('E', Run(6, 128), { ctx = ctx })
    Test.expect(not DAt(out, 1.5) and not DAt(out, 2.5) and not DAt(out, 3.5), '128 BPM, 6 hits: the "and"s go')
    Test.expect(DHas(DAt(out, 1), 1) and DHas(DAt(out, 2), 1) and DHas(DAt(out, 3), 1), 'the beats keep their snares')
    Test.expect(log.snare_runs == 3, ('expected 3 hits changed, got %s'):format(tostring(log.snare_runs)))
    local four = GenDrumsPlanTier('E', Run(4, 128), { ctx = ctx })
    Test.expect(DAt(four, 1.5) ~= nil, '4 hits: the run stays')
    local slow = GenDrumsPlanTier('E', Run(6, 110), { ctx = ctx })
    Test.expect(DAt(slow, 1.5) ~= nil, '110 BPM: the run stays')
end)

Test.it('Drums Easy: the quarter-note fill switch reads the tempo at bar 1 when it is faster', function()
    -- a 120 BPM test song: 120 at bar 1, the drums start in a bar marked 119.64.
    local med = {}
    for k = 0, 7 do med[#med + 1] = DH(k * 0.5, { 1 }, 119.64) end   -- an 8th snare fill
    med[#med + 1] = DH(4, { 4 }, 119.64)
    local ctx = { fills = { { qn = 0, qn_e = 4 } }, sections = { { qn = 0, name = 'chorus' } } }
    local plain = GenDrumsPlanTier('E', med, { ctx = ctx })
    Test.expect(DAt(plain, 0.5) ~= nil, 'no bar-1 tempo: 119.64 keeps the 8th fill')
    ctx.song_bpm = 120
    local fast = GenDrumsPlanTier('E', med, { ctx = ctx })
    Test.expect(not DAt(fast, 0.5) and DAt(fast, 1) ~= nil, 'bar 1 at 120: the fill goes to quarter notes')
end)

Test.it('Drums Hard: a hit with three hand gems is reported and keeps the kick and two', function()
    -- K R Y G on one hit: unplayable (two hands, one foot), never in an official chart.
    local out, log = GenDrumsPlanTier('H', { DH(0, { 0, 1, 2, 4 }), DH(2, { 1 }) }, { fast_runs = 'thin' })
    local ev = DAt(out, 0)
    local hands = 0
    for _, o in ipairs(ev.offs) do if o ~= 0 then hands = hands + 1 end end
    Test.expect(DHas(ev, 0) and hands == 2 and not DHas(ev, 2), ('K + two hands, the hi-hat gone: %s'):format(table.concat(ev.offs, ',')))
    Test.expect(#log.too_many_gems == 1, 'one hit reported')
end)

Test.it('Drums Medium from 140 BPM: a snare an 8th after a crash goes; at 120 it stays', function()
    -- a 210 BPM test song (209 BPM) / a 3/4 test song at 155 BPM (155): KG, R on the "and" of 1, RY on the "and" of 2.
    local function Bar(bpm) return { DH(0, { 0, 4 }, bpm), DH(0.5, { 1 }, bpm), DH(1.5, { 1, 2 }, bpm), DH(3, { 1 }, bpm) } end
    local fast = GenDrumsPlanTier('M', Bar(155), { between = 'keep' })
    Test.expect(not DAt(fast, 0.5), '155 BPM: the snare after the crash goes')
    Test.expect(DHas(DAt(fast, 0), 4) and DHas(DAt(fast, 1.5), 1), 'the crash and the next snare stay')
    local slow = GenDrumsPlanTier('M', Bar(120), { between = 'keep' })
    Test.expect(DHas(DAt(slow, 0.5), 1), '120 BPM: the snare stays')
end)

Test.it('Drums Easy from 170 BPM: no pair of hand hits an 8th apart; a kick next to one stays', function()
    -- a 210 BPM test song (209 BPM): G, R on the "and" of 1, then "and" snares.
    local ctx = { sections = { { qn = 0, name = 'chorus' } } }
    local m = { DH(0, { 4 }, 209), DH(0.5, { 1 }, 209), DH(1.5, { 1 }, 209), DH(2.5, { 1 }, 209), DH(4, { 0 }, 209),
                DH(4.5, { 1 }, 209), DH(5.5, { 1 }, 209) }
    local out = GenDrumsPlanTier('E', m, { ctx = ctx })
    Test.expect(DHas(DAt(out, 0), 4) and not DAt(out, 0.5), 'the crash stays, the "and" snare after it goes')
    Test.expect(DAt(out, 4.5) ~= nil, 'a kick then a snare an 8th later: both stay')
    -- The intro's tom pair (bars 4-5): equal hits keep the first, the beat.
    local toms = { [2] = { { qn = 0, qn_e = 8 } }, [3] = { { qn = 0, qn_e = 8 } } }
    local pair = GenDrumsPlanTier('E', { DH(0, { 2, 3 }, 210), DH(0.5, { 2, 3 }, 210), DH(6, { 2, 3 }, 210), DH(6.5, { 2, 3 }, 210) },
                                  { ctx = { toms = toms, sections = ctx.sections } })
    Test.expect(DAt(pair, 0) ~= nil and not DAt(pair, 0.5), 'tom pair: the beat stays')
    -- Below 170 the pair stays.
    local slow = GenDrumsPlanTier('E', { DH(0, { 4 }, 150), DH(0.5, { 1 }, 150), DH(2, { 1 }, 150) }, { ctx = ctx })
    Test.expect(DAt(slow, 0.5) ~= nil, '150 BPM: the pair stays')
end)

Test.it('Drums Medium/Easy at fast tempos: a pair of hand hits an 8th apart stays', function()
    -- a 3/4 test song at 155 BPM: KG, B, G an 8th later.
    local up = { DH(0, { 0, 4 }, 155), DH(1, { 3 }, 155), DH(1.5, { 4 }, 155), DH(3, { 1 }, 155) }
    for _, dl in ipairs({ 'M', 'E' }) do
        for _, mode in ipairs({ 'beats', 'hands' }) do
            local out = GenDrumsPlanTier(dl, up, { between = 'keep', eighth_hands = mode,
                                                   ctx = { sections = { { qn = 0, name = 'chorus' } } } })
            Test.expect(DHas(DAt(out, 1), 3) and DHas(DAt(out, 1.5), 4), dl .. ' ' .. mode .. ': the ride and the crash stay')
        end
    end
end)

Test.it('Drums: a roll lane keeps an even number of hits on the tier\'s grid', function()
    local x = {}
    for k = 0, 8 do x[#x + 1] = DH(k * 0.125, { 1 }) end   -- 32nds, 0 .. 1 under the lane
    x[#x + 1] = DH(2, { 0, 4 })
    local ctx = { rolls = { { qn = 0, qn_e = 1 } } }
    for _, dl in ipairs({ 'H', 'M', 'E' }) do
        local out = GenDrumsPlanTier(dl, x, { fast_runs = 'thin', ctx = ctx })
        local hits, prev, min_gap = 0, nil, math.huge
        for _, ev in ipairs(out) do
            if ev.qn <= 1 + 1e-6 then
                hits = hits + #ev.offs
                if prev then min_gap = math.min(min_gap, ev.qn - prev) end
                prev = ev.qn
            end
        end
        local grid = dl == 'H' and 0.25 or dl == 'M' and 0.5 or 1.0
        Test.expect(hits % 2 == 0, ('%s: %d hits in the roll'):format(dl, hits))
        Test.expect(hits == 0 or min_gap >= grid - 1e-6, ('%s: hits %g apart, grid %g'):format(dl, min_gap, grid))
    end
end)

Test.it('Drums: a double crash is a single Green on every tier, with room or not, a kick staying', function()
    local out = GenDrumsPlanTier('H', { DH(0, { 1 }), DH(0.5, { 2, 4 }), DH(2, { 2, 4 }), DH(4, { 0, 2, 4 }) }, { fast_runs = 'thin' })
    local a, b, c = DAt(out, 0.5), DAt(out, 2), DAt(out, 4)
    Test.expect(a ~= nil and #a.offs == 1 and a.offs[1] == 4, 'the cramped double crash should be Green only')
    Test.expect(b ~= nil and #b.offs == 1 and b.offs[1] == 4, 'the one with room too (official Hard: Green only 90-95%)')
    Test.expect(c ~= nil and DHas(c, 0) and DHas(c, 4) and not DHas(c, 2), 'KYG -> KG')
end)

Test.it('Drums: a tom pair or a cymbal + tom is no double crash', function()
    -- Blue and Green toms over the 2nd hit, a Green tom over the 3rd.
    local toms = { [3] = { { qn = 0.5, qn_e = 0.6 } }, [4] = { { qn = 0.5, qn_e = 0.6 }, { qn = 1, qn_e = 1.1 } } }
    local out = GenDrumsPlanTier('H', { DH(0, { 1 }), DH(0.5, { 3, 4 }), DH(1, { 2, 4 }) },
        { fast_runs = 'thin', ctx = { toms = toms } })
    local a, b = DAt(out, 0.5), DAt(out, 1)
    Test.expect(a ~= nil and #a.offs == 2, 'the Blue + Green tom pair should keep both gems')
    Test.expect(b ~= nil and #b.offs == 2, 'the Yellow cymbal + Green tom should keep both gems')
end)

-- A bar of 16ths at 120 BPM: snares, then toms Y B G B on beat 4, each under its own short
-- tom marker exactly on the note (a 3/4 test song at 155 BPM's layout).
local function TomRunBar()
    local x, toms = {}, { [2] = {}, [3] = {}, [4] = {} }
    local tail = { [12] = 2, [13] = 3, [14] = 4, [15] = 3 }
    for k = 0, 15 do
        local q, o = k * 0.25, tail[k] or 1
        x[#x + 1] = DH(q, { o }, 120)
        if o >= 2 then table.insert(toms[o], { qn = q, qn_e = q + 0.05 }) end
    end
    x[#x + 1] = DH(4, { 0, 4 }, 120)
    return x, toms
end
local function UnderSpan(spans, qn)
    for _, s in ipairs(spans or {}) do if qn >= s.qn - 1e-6 and qn < s.qn_e - 1e-6 then return true end end
    return false
end

Test.it('Drums Hard rewrite: a tom moved off its marker gets one marker over the whole run', function()
    local x, toms = TomRunBar()
    local out, log = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite', ctx = { toms = toms } })
    Test.expect(#log.retimed_bars == 1, 'the run should be rewritten')
    Test.expect(#log.tom_markers > 0, 'expected new tom markers')
    for _, ev in ipairs(out) do
        for _, o in ipairs(ev.offs) do
            if o >= 2 and ev.qn < 4 then
                Test.expect(UnderSpan(log.ctx.toms[o], ev.qn), ('Hard gem %d at %g lost its tom marker'):format(o, ev.qn))
            end
        end
    end
    -- Expert's toms stay toms under the new markers.
    for _, ev in ipairs(x) do
        local o = ev.offs[1]
        if o >= 2 and ev.qn < 4 then
            Test.expect(UnderSpan(log.ctx.toms[o], ev.qn), ('Expert gem %d at %g lost its tom marker'):format(o, ev.qn))
        end
    end
    -- One marker per changed color, from the run's first note.
    for _, m in ipairs(log.tom_markers) do
        Test.expect(math.abs(m.qn) < 1e-6 and #log.ctx.toms[m.o] == 1,
            ('color %d: marker from %g, %d markers'):format(m.o, m.qn, #log.ctx.toms[m.o]))
    end
    -- The caller's context is left as it was; the next tier is planned with log.ctx.
    Test.expect(toms ~= log.ctx.toms and #toms[3] == 2, 'the caller\'s context should not be changed in place')
end)

Test.it('Drums Hard rewrite: a moved tom its marker still covers gets the whole-run marker too; a whole-run marker stays', function()
    local x, toms = TomRunBar()
    -- Blue: one long marker over beat 4 (covers wherever the rewrite puts its toms).
    toms[3] = { { qn = 3, qn_e = 4 } }
    local _, log = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite', ctx = { toms = toms } })
    local blue
    for _, m in ipairs(log.tom_markers) do if m.o == 3 then blue = m end end
    Test.expect(blue ~= nil and math.abs(blue.qn) < 1e-6 and math.abs(blue.qn_e - 4) < 1e-6,
        'Blue: expected one marker over the whole run (0-4)')
    -- Run it again on its own result's markers: already exactly the whole run - no change.
    local _, log2 = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite', ctx = log.ctx })
    Test.expect(#log2.tom_markers == 0, ('a second run should change no marker, got %d'):format(#log2.tom_markers))
end)

Test.it('Drums Hard rewrite: a run of 16ths with a 32nd group in it - each group on its own grid', function()
    -- 120 BPM: R 16ths 0-1.75, y 32nds 2 2.125 2.25, b/g 16ths 2.5-3.75, crash on the next bar.
    local x, toms = {}, { [2] = { { qn = 2, qn_e = 2.3 } }, [3] = { { qn = 2.5, qn_e = 3.1 } }, [4] = { { qn = 3.25, qn_e = 3.8 } } }
    for k = 0, 7 do x[#x + 1] = DH(k * 0.25, { 1 }, 120) end
    for _, q in ipairs({ 2, 2.125, 2.25 }) do x[#x + 1] = DH(q, { 2 }, 120) end
    for k = 0, 5 do x[#x + 1] = DH(2.5 + k * 0.25, { k < 3 and 3 or 4 }, 120) end
    x[#x + 1] = DH(4, { 0, 4 }, 120)
    local out = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite', ctx = { toms = toms } })
    local pos = {}
    for _, ev in ipairs(out) do if ev.qn < 4 then pos[#pos + 1] = ('%g'):format(math.floor(ev.qn * 24 + 0.5)) end end
    Test.expect(table.concat(pos, ' ') == '0 8 16 24 32 40 48 54 64 72 80 88',
        'expected R on 8th triplets, two y 16ths, b/g on 8th triplets; got ' .. table.concat(pos, ' '))
end)

Test.it('Drums Hard rewrite: a cymbal of that color under the needed marker - the run is thinned and listed', function()
    local x, toms = TomRunBar()
    -- A Blue cymbal another tier keeps at beat 3.
    local out, log = GenDrumsPlanTier('H', x, { fast_runs = 'rewrite', ctx = { toms = toms },
                                                keep_cymbals = { [3] = { 2 } } })
    Test.expect(#log.tom_conflict_bars == 1 and math.abs(log.tom_conflict_bars[1]) < 1e-6,
        ('expected bar 0 listed, got %d'):format(#log.tom_conflict_bars))
    Test.expect(#log.tom_markers == 0, 'no marker should change')
    Test.expect((OnEighths(out)), 'the thinned run should sit on 8ths')
end)

Test.it('Drums Medium: a two-hand hit with a tom plays one gem at 140+, two toms off the beat at any tempo', function()
    -- All three colors are toms over 0-2 at 150 BPM and 4-6 at 120 BPM; cymbals elsewhere.
    local toms = { [2] = { { qn = 0, qn_e = 2 }, { qn = 4, qn_e = 6 } }, [3] = { { qn = 0, qn_e = 2 }, { qn = 4, qn_e = 6 } },
                   [4] = { { qn = 0, qn_e = 2.6 }, { qn = 4, qn_e = 6.6 } } }
    -- Snares on beat 3 and the "and" of 4 make five hits a bar (a bar with no more hits than
    -- beats keeps its tom pairs - the next test) without three hand hits an 8th apart, which
    -- Medium thins at 150 BPM (LowerEighthHands).
    local up = { DH(0, { 3, 4 }, 150), DH(1, { 2, 3 }, 150), DH(2, { 1 }, 150), DH(2.5, { 2, 4 }, 150), DH(3.5, { 1 }, 150),  -- 150: bg, yb, Y + g
                 DH(4, { 3, 4 }, 120), DH(5, { 1 }, 120), DH(5.5, { 3, 4 }, 120), DH(6.5, { 2, 4 }, 120), DH(7, { 1 }, 120) } -- 120: bg, bg off, Y + g off
    local out = GenDrumsPlanTier('M', up, { ctx = { toms = toms }, between = 'keep' })
    local function Gems(qn)
        local ev = DAt(out, qn)
        return ev and table.concat(ev.offs, ',') or '-'
    end
    Test.expect(Gems(0) == '4', '150 BPM bg: the Green tom stays, got ' .. Gems(0))
    Test.expect(Gems(1) == '3', '150 BPM yb: the Blue tom stays, got ' .. Gems(1))
    Test.expect(Gems(2.5) == '4', '150 BPM Y + g: the tom stays, got ' .. Gems(2.5))
    Test.expect(Gems(4) == '3,4', '120 BPM bg on the beat: both stay, got ' .. Gems(4))
    Test.expect(Gems(5.5) == '4', '120 BPM bg off the beat: the Green tom stays, got ' .. Gems(5.5))
    Test.expect(Gems(6.5) == '2,4', '120 BPM Y + g off the beat: both stay (two-hand "and"), got ' .. Gems(6.5))
end)

Test.it('Drums Medium: a bar with fewer hits than beats keeps its tom pairs', function()
    local toms = { [2] = { { qn = 0, qn_e = 1 } }, [3] = { { qn = 0, qn_e = 1 } } }
    local up = { DH(0, { 0, 2, 3 }, 210), DH(0.5, { 2, 3 }, 210), DH(4, { 0, 4 }, 210) }
    local out = GenDrumsPlanTier('M', up, { ctx = { toms = toms } })
    local ev = DAt(out, 0.5)
    Test.expect(ev and DHas(ev, 2) and DHas(ev, 3), 'the sparse bar should keep both toms')
end)

Test.it('Drums Medium: sparse counts hand notes - bg Rg bg R reduces; repeated tom pairs an 8th apart thin to the beats', function()
    -- a 210 BPM test song (7 hand notes in 4/4): the tom pairs become the higher tom.
    local toms = { [3] = { { qn = 0, qn_e = 8 } }, [4] = { { qn = 0, qn_e = 8 } } }
    local busy = GenDrumsPlanTier('M', { DH(0, { 0, 3, 4 }, 211), DH(1, { 1, 4 }, 211), DH(2, { 0, 3, 4 }, 211),
                                         DH(3, { 1, 4 }, 211), DH(4, { 1 }, 211) }, { ctx = { toms = toms } })
    Test.expect(not DHas(DAt(busy, 0), 3) and DHas(DAt(busy, 0), 4), 'bar 47: bg -> g')
    -- a 210 BPM test song (yb yb . yb yb, 8 notes): the repeats go, the doubles on the beats stay.
    local yt = { [2] = { { qn = 0, qn_e = 8 } }, [3] = { { qn = 0, qn_e = 8 } } }
    local rep = GenDrumsPlanTier('M', { DH(0, { 2, 3 }, 245), DH(0.5, { 2, 3 }, 245), DH(2, { 2, 3 }, 245),
                                        DH(2.5, { 2, 3 }, 245), DH(4, { 1 }, 245) }, { ctx = { toms = yt } })
    Test.expect(not DAt(rep, 0.5) and not DAt(rep, 2.5), 'bar 201: the 8th repeats go')
    Test.expect(DHas(DAt(rep, 0), 2) and DHas(DAt(rep, 0), 3) and DHas(DAt(rep, 2), 2), 'bar 201: the doubles stay')
end)

Test.it('Drums Medium at 150 BPM: no run of four 8ths', function()
    local hard = {}
    for k = 0, 7 do hard[#hard + 1] = DH(k * 0.5, { 1 }, 150) end
    local out = GenDrumsPlanTier('M', hard)
    local run, worst = 1, 1
    for i = 2, #out do
        if math.abs(out[i].qn - out[i - 1].qn - 0.5) < 1e-6 then run = run + 1 else run = 1 end
        worst = math.max(worst, run)
    end
    Test.expect(worst < 4, ('a run of %d 8ths'):format(worst))
end)

Test.it('Drums Easy: no kicks inside a drum fill', function()
    local med = { DH(0, { 0, 2 }), DH(1, { 1, 2 }), DH(2, { 0 }), DH(2.5, { 1 }), DH(3, { 0 }), DH(3.5, { 1 }),
                  DH(4, { 0, 4 }) }
    local out = GenDrumsPlanTier('E', med, { ctx = { fills = { { qn = 2, qn_e = 4 } } } })
    for _, ev in ipairs(out) do
        Test.expect(not (ev.qn >= 2 and ev.qn < 4 and DHas(ev, 0)), ('a kick in the fill at %g'):format(ev.qn))
    end
end)

Test.section('Generate planner - parameters documented')

-- docs/difficulty_reduction.md says why each rule exists; the code says only what it does.
-- Every tunable a planner reads must therefore be named there, in backticks, or its reason
-- is lost the next time someone changes the number.
local function ReadReductionDoc()
    local f = SCRIPT_MDIR and io.open(SCRIPT_MDIR .. '../docs/difficulty_reduction.md', 'rb')
    if not f then return nil end
    local doc = f:read('a')
    f:close()
    return doc
end

local function ExpectKeysDocumented(doc, name, params)
    local missing = {}
    for k in pairs(params) do
        if not doc:find('`' .. k .. '`', 1, true) then missing[#missing + 1] = k end
    end
    table.sort(missing)
    Test.expect(#missing == 0, name .. ' keys missing from docs/difficulty_reduction.md: '
        .. table.concat(missing, ', '))
end

Test.it('every GEN5_PARAMS and GEN_DRUMS_PARAMS key has an entry in the doc', function()
    local doc = ReadReductionDoc()
    Test.expect(doc ~= nil, 'could not read docs/difficulty_reduction.md')
    if not doc then return end
    ExpectKeysDocumented(doc, 'GEN5_PARAMS', GEN5_PARAMS)
    ExpectKeysDocumented(doc, 'GEN_DRUMS_PARAMS', GEN_DRUMS_PARAMS)
end)
