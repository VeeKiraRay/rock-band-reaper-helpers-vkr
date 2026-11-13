-- VENUE lighting/blend validation rules (actions_venue_validate.lua).
--
-- Drives ValidateVenueLightingBlends and KeyframeNoEffect directly: both are pure
-- over sorted {ppq=, msg=} arrays, so every rule can be stated as a hand-built event
-- list with no project, no VENUE track and no MIDI editor. What that buys is precision
-- - the interesting cases here (a blend anchor that must not restart a preset, a
-- change three events back that must not count as an anchor) are fiddly to build as
-- real MIDI and trivial to state as four table entries.
--
-- Requires globals: Test, ValidateVenueLightingBlends, KeyframeNoEffect,
-- KeyframeNoEffectReason, MANUAL_LIGHTING_SET (set up by run_venue_validate.lua).

local PPQ  = 960                    -- ticks per quarter note
local TOL  = math.floor(PPQ / 32)   -- the 1/128-note "on this tick" tolerance

local STOMP  = '[lighting (stomp)]'
local VERSE  = '[lighting (verse)]'
local CHORUS = '[lighting (chorus)]'
local LOOP   = '[lighting (loop_cool)]'   -- automatic - never keyframed
local PP_A   = '[ProFilm_a.pp]'
local PP_B   = '[ProFilm_b.pp]'

-- Events at beat positions, so a case reads as a timeline.
local function Ev(beat, msg) return { ppq = math.floor(beat * PPQ), msg = msg } end

-- Keyframe events: K(0, '[first]', 4, '[next]') -> two events at beats 0 and 4.
local function K(...)
    local a, out = { ... }, {}
    for i = 1, #a, 2 do out[#out + 1] = Ev(a[i], a[i + 1]) end
    return out
end

local function Run(lighting, postproc, keys)
    return ValidateVenueLightingBlends(lighting or {}, postproc or {}, keys or {}, TOL)
end

-- "kind@beat" per no-effect finding, in order.
local function Kinds(f)
    local out = {}
    for _, k in ipairs(f.no_effect) do out[#out + 1] = ('%s@%g'):format(k.kind, k.ppq / PPQ) end
    return table.concat(out, ',')
end

-- ---------------------------------------------------------------------------

Test.section('Keyframe events with no effect')

Test.it('a [next] train under a manual preset is clean', function()
    local f = Run({ Ev(0, STOMP) }, nil, K(1, '[next]', 2, '[next]', 3, '[next]'))
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

Test.it('a manual change with no keyframe on its tick is clean (no [first] needed)', function()
    local f = Run({ Ev(0, STOMP), Ev(40, VERSE) }, nil, {})
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

-- The old generators' shape: a [first] on every manual change's own tick.
Test.it('a [first] on the change tick does nothing (still on the first look)', function()
    local f = Run({ Ev(0, STOMP), Ev(40, VERSE) }, nil, K(0, '[first]', 1, '[next]', 40, '[first]'))
    Test.expect(Kinds(f) == 'first_look@0,first_look@40', 'got ' .. Kinds(f))
end)

Test.it('a [first] within the tolerance of the tick is the same', function()
    local f = Run({ Ev(0, STOMP) }, nil, { { ppq = TOL, msg = '[first]' } })
    Test.expect(Kinds(f) == 'first_look@' .. TOL / PPQ, 'got ' .. Kinds(f))
end)

Test.it('a [first] after a [next] in the same preset has an effect', function()
    local f = Run({ Ev(0, STOMP) }, nil, K(2, '[next]', 4, '[first]'))
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

Test.it('a [first] after a [prev] has an effect too', function()
    local f = Run({ Ev(0, VERSE) }, nil, K(2, '[prev]', 4, '[first]'))
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

-- A [next] on the change tick may count in game (the preset starts when the fade into
-- it starts), so it may have moved the look: a later [first] is not flagged.
Test.it('a [next] on the change tick counts before a later [first]', function()
    local f = Run({ Ev(0, STOMP) }, nil, K(0, '[next]', 4, '[first]'))
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

-- A [next] in the previous preset does not count: the new preset starts on look 0.
Test.it('a [next] before the preset change does not count for its [first]', function()
    local f = Run({ Ev(0, STOMP), Ev(8, VERSE) }, nil, K(4, '[next]', 10, '[first]'))
    Test.expect(Kinds(f) == 'first_look@10', 'got ' .. Kinds(f))
end)

-- Restating the running preset (a blend anchor) does not restart it.
Test.it('a restatement does not restart the preset: [next] before it still counts', function()
    local f = Run({ Ev(0, STOMP), Ev(36, STOMP), Ev(40, VERSE) }, nil, K(4, '[next]', 37, '[first]'))
    Test.expect(#f.no_effect == 0, 'got ' .. Kinds(f))
end)

Test.it('keyframe events under an automatic preset are ignored', function()
    local f = Run({ Ev(0, LOOP) }, nil, K(0, '[first]', 2, '[next]', 4, '[prev]'))
    Test.expect(Kinds(f) == 'ignored@0,ignored@2,ignored@4', 'got ' .. Kinds(f))
    Test.expect(f.no_effect[1].lt.msg == LOOP, 'the running preset is reported')
end)

Test.it('keyframe events before the first lighting event do nothing', function()
    local f = Run({ Ev(8, STOMP) }, nil, K(2, '[next]', 9, '[next]'))
    Test.expect(Kinds(f) == 'no_preset@2', 'got ' .. Kinds(f))
end)

Test.it('keyframe events with no lighting at all do nothing', function()
    local f = Run({}, nil, K(0, '[first]', 4, '[next]'))
    Test.expect(Kinds(f) == 'no_preset@0,no_preset@4', 'got ' .. Kinds(f))
end)

Test.it('the reason text names the preset', function()
    local kind, lt = KeyframeNoEffect('[next]', 4 * PPQ, { Ev(0, LOOP) }, {}, TOL)
    Test.expect(kind == 'ignored', 'got ' .. tostring(kind))
    Test.expect(KeyframeNoEffectReason(kind, '[next]', lt):find(LOOP, 1, true), 'preset named')
    kind, lt = KeyframeNoEffect('[first]', 0, { Ev(0, STOMP) }, {}, TOL)
    Test.expect(KeyframeNoEffectReason(kind, '[first]', lt):find('first look', 1, true), 'first look')
end)

Test.it('MANUAL_LIGHTING_SET drives the manual/automatic split', function()
    -- Guards against the validator growing its own copy of the preset vocabulary:
    -- every preset it treats as manual must come from that one set.
    local n = 0
    for msg in pairs(MANUAL_LIGHTING_SET) do
        n = n + 1
        local f = Run({ Ev(0, msg) }, nil, K(2, '[next]'))
        Test.expect(#f.no_effect == 0, msg .. ' should take keyframes')
    end
    Test.expect(n == 6, 'expected 6 manual presets, got ' .. n)
    local f = Run({ Ev(0, LOOP) }, nil, {})
    Test.expect(f.manual_changes == 0, 'loop_cool should not count as a manual change')
end)

Test.section('Blend anchors - lighting')

Test.it('a change preceded by a restatement is anchored', function()
    local f = Run({ Ev(0, STOMP), Ev(36, STOMP), Ev(40, VERSE) })
    Test.expect(#f.blend.lt.missing == 0, 'expected the change to be anchored')
    Test.expect(f.blend.lt.anchored == 1 and f.blend.lt.changes == 1, 'wrong blend counts')
end)

Test.it('a hard cut is reported with both presets and where the old one started', function()
    local f = Run({ Ev(0, STOMP), Ev(40, VERSE) })
    Test.expect(#f.blend.lt.missing == 1, 'expected 1 unanchored change')
    local b = f.blend.lt.missing[1]
    Test.expect(b.from_msg == STOMP and b.msg == VERSE, 'wrong from/to')
    Test.expect(b.from_ppq == 0 and b.ppq == 40 * PPQ, 'wrong positions')
end)

Test.it('the first lighting event of the song is exempt', function()
    local f = Run({ Ev(0, STOMP) })
    Test.expect(f.blend.lt.changes == 0, 'nothing precedes it to blend from')
    Test.expect(#f.blend.lt.missing == 0, 'and so it cannot be reported')
end)

Test.it('several restatements still anchor the change', function()
    local f = Run({ Ev(0, STOMP), Ev(20, STOMP), Ev(36, STOMP), Ev(40, VERSE) })
    Test.expect(#f.blend.lt.missing == 0, 'expected anchored, got ' .. #f.blend.lt.missing)
end)

-- Only ADJACENT events are compared: a preset returning later is a real change again,
-- and the earlier run of it is not an anchor for it.
Test.it('a preset returning after another one is a fresh unanchored change', function()
    local f = Run({ Ev(0, VERSE), Ev(20, STOMP), Ev(40, VERSE) })
    Test.expect(f.blend.lt.changes == 2, 'both should count as changes')
    Test.expect(#f.blend.lt.missing == 2, 'neither is anchored')
end)

Test.it('a fully blended three-section run is clean', function()
    local lighting = {
        Ev(0, STOMP),  Ev(38, STOMP),           -- section 1 + its outgoing anchor
        Ev(40, VERSE), Ev(78, VERSE),           -- section 2 + its outgoing anchor
        Ev(80, CHORUS),
    }
    local f = Run(lighting, nil, K(1, '[next]', 41, '[next]', 81, '[next]'))
    Test.expect(#f.no_effect == 0, 'no keyframe findings: ' .. Kinds(f))
    Test.expect(#f.blend.lt.missing == 0, 'no missing blends')
    Test.expect(f.changes == 3 and f.manual_changes == 3, 'wrong change counts')
end)

Test.section('Blend anchors - post proc')

Test.it('post proc is judged independently of lighting', function()
    local lighting = { Ev(0, STOMP), Ev(38, STOMP), Ev(40, VERSE) }
    local pp       = { Ev(0, PP_A), Ev(40, PP_B) }
    local f = Run(lighting, pp)
    Test.expect(#f.blend.lt.missing == 0, 'lighting is anchored')
    Test.expect(#f.blend.pp.missing == 1, 'post proc is not')
    Test.expect(f.blend.pp.missing[1].msg == PP_B, 'wrong post proc change reported')
end)

Test.it('an anchored post proc change is clean', function()
    local f = Run({}, { Ev(0, PP_A), Ev(38, PP_A), Ev(40, PP_B) }, {})
    Test.expect(#f.blend.pp.missing == 0, 'expected anchored')
    Test.expect(f.blend.pp.anchored == 1, 'wrong anchored count')
end)

Test.section('Edge cases')

Test.it('an empty track produces no findings', function()
    local f = Run({}, {}, {})
    Test.expect(#f.no_effect == 0, 'nothing to report')
    Test.expect(#f.blend.lt.missing == 0 and #f.blend.pp.missing == 0, 'nothing to report')
    Test.expect(f.changes == 0 and f.manual_changes == 0, 'counts should be zero')
end)

-- ---------------------------------------------------------------------------
-- Camera stack validation (actions_venue_validate_camera.lua). Same discipline:
-- ValidateVenueCameraStacks is pure over one sorted {ppq=, msg=} array plus the
-- lineups, so each case is a hand-built stack rather than a VENUE track.

local CAM_NEAR = math.floor(PPQ / 8)   -- the 32nd-note "meant to be stacked" window

-- Camera events at beat positions; several at one beat = a stack.
local function Cam(beat, ...)
    local out = {}
    for _, msg in ipairs({ ... }) do
        out[#out + 1] = { ppq = math.floor(beat * PPQ), msg = msg }
    end
    return out
end

local function Cams(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, ev in ipairs(list) do out[#out + 1] = ev end
    end
    return out
end

local FULL_BAND = BuildBandLineups({})              -- b, g and k all charted
local NO_KEYS   = BuildBandLineups({ k = true })    -- the ordinary four-piece

local function RunCam(camera, lineups)
    return ValidateVenueCameraStacks(camera, lineups or FULL_BAND, CAM_NEAR)
end

local function Msgs(list)
    local out = {}
    for _, it in ipairs(list) do out[#out + 1] = it.msg end
    table.sort(out)
    return table.concat(out, ',')
end

Test.section('BuildBandLineups')

Test.it('all of bass/guitar/keys charted gives the three swap lineups', function()
    Test.expect(#FULL_BAND == 3, 'expected 3 lineups, got ' .. #FULL_BAND)
    local labels = {}
    for _, lu in ipairs(FULL_BAND) do labels[#labels + 1] = lu.label end
    Test.expect(table.concat(labels, ' | ') == 'Bass + Guitar | Bass + Keys | Guitar + Keys',
        'got ' .. table.concat(labels, ' | '))
end)

Test.it('each swap lineup mutes the instrument it leaves off stage', function()
    Test.expect(FULL_BAND[1].muted.k, 'Bass + Guitar should mute keys')
    Test.expect(FULL_BAND[2].muted.g, 'Bass + Keys should mute guitar')
    Test.expect(FULL_BAND[3].muted.b, 'Guitar + Keys should mute bass')
    Test.expect(not FULL_BAND[1].muted.b and not FULL_BAND[1].muted.g,
        'Bass + Guitar should keep both of its own instruments')
end)

Test.it('fewer than three of the trio charted gives exactly one lineup', function()
    Test.expect(#NO_KEYS == 1, 'expected 1 lineup, got ' .. #NO_KEYS)
    Test.expect(NO_KEYS[1].label == 'Bass + Guitar', 'got ' .. NO_KEYS[1].label)
    Test.expect(NO_KEYS[1].muted.k, 'keys stays muted')
end)

Test.it('drums/vocals mute state carries into every lineup', function()
    local lineups = BuildBandLineups({ v = true })
    Test.expect(#lineups == 3, 'the trio is untouched, so still 3 lineups')
    for _, lu in ipairs(lineups) do
        Test.expect(lu.muted.v, lu.label .. ' should keep vocals muted')
    end
end)

Test.section('Camera stacks - clean tracks')

Test.it('a shot needing nobody is fine for every lineup', function()
    local f = RunCam(Cam(4, '[coop_all_near]'))
    Test.expect(#f.uncovered == 0, 'no uncovered lineups')
    Test.expect(#f.unreachable == 0, 'nothing unreachable')
    Test.expect(f.spots == 1 and f.stacked == 0, 'one spot, not stacked')
end)

Test.it('primary + companion covers all three lineups', function()
    -- What the generator emits for a keys/guitar/bass swap band.
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'))
    Test.expect(#f.uncovered == 0, 'every lineup has a shot')
    Test.expect(#f.unreachable == 0, 'both shots win somewhere')
    Test.expect(f.stacked == 1, 'the spot counts as stacked')
end)

Test.it('an empty track produces no findings', function()
    local f = RunCam({})
    Test.expect(f.events == 0 and f.spots == 0, 'nothing counted')
    Test.expect(#f.uncovered == 0 and #f.unreachable == 0, 'nothing reported')
end)

Test.section('Camera stacks - uncovered lineups')

-- Findings are one per SPOT, carrying the lineups that spot leaves blind.
local function Blind(c)
    local out = {}
    for _, lu in ipairs(c.lineups) do
        out[#out + 1] = ('%s=%s%s'):format(lu.label, lu.kind, lu.note and (':' .. lu.note) or '')
    end
    return table.concat(out, ' | ')
end

Test.it('a lone coop duo cut reports the duo-to-single fallback', function()
    -- Documented Note 2: a duo flag with no other stacked flags degrades to a
    -- single shot of whoever is left, so this is named, not called generic.
    local f = RunCam(Cam(4, '[coop_bg_near]'))
    Test.expect(#f.uncovered == 1, 'one spot; got ' .. #f.uncovered)
    Test.expect(Blind(f.uncovered[1]) ==
        'Bass + Keys=duo_single:Bass | Guitar + Keys=duo_single:Guitar',
        'got ' .. Blind(f.uncovered[1]))
end)

Test.it('a lone directed duo cut falls back to a generic shot', function()
    -- The directed cuts section documents no duo-to-single equivalent, so this
    -- degrades to a generic shot where a coop duo would name the remaining member.
    -- A keys/bass duo needs BOTH, so only Bass + Keys can play it.
    local f = RunCam(Cam(4, '[directed_duo_kb]'))
    Test.expect(#f.uncovered == 1, 'one spot; got ' .. #f.uncovered)
    Test.expect(Blind(f.uncovered[1]) == 'Bass + Guitar=generic | Guitar + Keys=generic',
        'got ' .. Blind(f.uncovered[1]))
end)

Test.it('a stack where nothing fits is generic, not duo-to-single', function()
    -- Two stacked flags, so the "no other stacked flags" condition fails.
    local f = RunCam(Cam(4, '[coop_bk_near]', '[coop_gk_near]'))
    Test.expect(#f.uncovered == 1, 'one spot; got ' .. #f.uncovered)
    Test.expect(Blind(f.uncovered[1]) == 'Bass + Guitar=generic', 'got ' .. Blind(f.uncovered[1]))
    Test.expect(#f.uncovered[1].shots == 2, 'the report names both authored shots')
end)

Test.it('a spot every lineup can play produces no entry at all', function()
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'))
    Test.expect(#f.uncovered == 0, 'got ' .. #f.uncovered)
end)

Test.it('a four-piece project needs no companion to be covered', function()
    local f = RunCam(Cam(4, '[coop_bg_near]'), NO_KEYS)
    Test.expect(#f.uncovered == 0, 'the only lineup can play it')
    Test.expect(#f.unreachable == 0, 'nothing unreachable')
end)

Test.section('Camera stacks - shots that never play')

Test.it('a generic shot stacked under an always-valid specific one never plays', function()
    local f = RunCam(Cam(4, '[coop_all_near]', '[coop_gv_near]'), NO_KEYS)
    Test.expect(#f.unreachable == 1, 'expected 1, got ' .. #f.unreachable)
    Test.expect(f.unreachable[1].msg == '[coop_all_near]', 'got ' .. f.unreachable[1].msg)
    Test.expect(f.unreachable[1].fits_any, 'it fits the lineup, it is just outranked')
    Test.expect(f.unreachable[1].beaten_by == '[coop_gv_near]',
        'got ' .. tostring(f.unreachable[1].beaten_by))
end)

Test.it('a shot needing an uncharted instrument never plays', function()
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'), NO_KEYS)
    Test.expect(#f.unreachable == 1, 'expected 1, got ' .. #f.unreachable)
    Test.expect(f.unreachable[1].msg == '[coop_k_near]', 'got ' .. f.unreachable[1].msg)
    Test.expect(not f.unreachable[1].fits_any, 'no lineup puts keys on stage')
end)

Test.it('a shot that wins under one lineup is not reported', function()
    -- coop_k_near loses to coop_bg_near on Bass + Guitar but wins the other two.
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'))
    Test.expect(#f.unreachable == 0, 'got ' .. Msgs(f.unreachable))
end)

Test.it('a lone unplayable shot is an uncovered spot, not an unreachable shot', function()
    local f = RunCam(Cam(4, '[coop_k_near]'), NO_KEYS)
    Test.expect(#f.unreachable == 0, 'not double-reported; got ' .. Msgs(f.unreachable))
    Test.expect(#f.uncovered == 1, 'reported once, as an uncovered spot')
end)

Test.section('Camera stacks - mechanical mistakes')

Test.it('the same shot twice on one tick is one duplicate finding', function()
    local f = RunCam(Cam(4, '[coop_all_near]', '[coop_all_near]'))
    Test.expect(#f.duplicates == 1, 'expected 1, got ' .. #f.duplicates)
    Test.expect(f.duplicates[1].count == 2, 'count 2; got ' .. f.duplicates[1].count)
    Test.expect(#f.unreachable == 0, 'the copy is not also called unreachable')
    Test.expect(f.stacked == 0, 'one distinct shot is not a stack')
end)

Test.it('shots a few ticks apart are flagged as a botched stack', function()
    local camera = Cams(Cam(4, '[coop_bg_near]'),
                        { { ppq = 4 * PPQ + 10, msg = '[coop_k_near]' } })
    local f = RunCam(camera)
    Test.expect(#f.near_stacks == 1, 'expected 1, got ' .. #f.near_stacks)
    Test.expect(f.near_stacks[1].delta == 10, 'got ' .. f.near_stacks[1].delta)
    Test.expect(f.near_stacks[1].prev_msg == '[coop_bg_near]', 'got ' .. f.near_stacks[1].prev_msg)
end)

Test.it('shots a full beat apart are two ordinary cuts', function()
    local f = RunCam(Cams(Cam(4, '[coop_all_near]'), Cam(5, '[coop_all_far]')))
    Test.expect(#f.near_stacks == 0, 'expected none, got ' .. #f.near_stacks)
    Test.expect(f.spots == 2, 'two spots')
end)

Test.it('counts describe the whole track', function()
    local f = RunCam(Cams(Cam(4, '[coop_bg_near]', '[coop_k_near]'),
                          Cam(8, '[coop_all_near]'),
                          Cam(12, '[coop_bv_near]', '[coop_kv_near]')))
    Test.expect(f.events == 5, 'five events; got ' .. f.events)
    Test.expect(f.spots == 3, 'three spots; got ' .. f.spots)
    Test.expect(f.stacked == 2, 'two of them stacked; got ' .. f.stacked)
end)
