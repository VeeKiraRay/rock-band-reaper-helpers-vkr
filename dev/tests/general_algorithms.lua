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
