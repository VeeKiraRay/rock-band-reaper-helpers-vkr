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
    Test.expect(#f.fallbacks == 0 and #f.directed_lost == 0, 'no uncovered lineups')
    Test.expect(#f.unreachable == 0, 'nothing unreachable')
    Test.expect(f.spots == 1 and f.stacked == 0, 'one spot, not stacked')
end)

Test.it('primary + companion covers all three lineups', function()
    -- What the generator emits for a keys/guitar/bass swap band.
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'))
    Test.expect(#f.fallbacks == 0 and #f.directed_lost == 0, 'every lineup has a shot')
    Test.expect(#f.unreachable == 0, 'both shots win somewhere')
    Test.expect(f.stacked == 1, 'the spot counts as stacked')
end)

Test.it('an empty track produces no findings', function()
    local f = RunCam({})
    Test.expect(f.events == 0 and f.spots == 0, 'nothing counted')
    Test.expect(#f.fallbacks == 0 and #f.directed_lost == 0 and #f.unreachable == 0, 'nothing reported')
end)

Test.section('Camera stacks - fallbacks and lost directed cuts')

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
    Test.expect(#f.fallbacks == 1, 'one spot; got ' .. #f.fallbacks)
    Test.expect(Blind(f.fallbacks[1]) ==
        'Bass + Keys=duo_single:Bass | Guitar + Keys=duo_single:Guitar',
        'got ' .. Blind(f.fallbacks[1]))
    Test.expect(#f.directed_lost == 0, 'a normal shot is never a lost directed cut')
end)

Test.it('a lone directed cut a lineup cannot play is lost, not a fallback', function()
    -- The game's lineup tables drop a directed cut and a random generic band shot
    -- plays instead - the cut is lost. A keys/bass duo needs BOTH, so only Bass +
    -- Keys plays it.
    local f = RunCam(Cam(4, '[directed_duo_kb]'))
    Test.expect(#f.fallbacks == 0, 'no fallback; got ' .. #f.fallbacks)
    Test.expect(#f.directed_lost == 1, 'one spot; got ' .. #f.directed_lost)
    local names = {}
    for _, lu in ipairs(f.directed_lost[1].lineups) do names[#names + 1] = lu.label end
    Test.expect(table.concat(names, ' | ') == 'Bass + Guitar | Guitar + Keys', 'got ' .. table.concat(names, ' | '))
end)

Test.it('a directed cut stacked with a normal shot falls back, it is not lost', function()
    -- Without keys the directed keys cut cannot play; the stacked keys shot cannot
    -- either, so the normal shot falls back - the camera still cuts.
    local f = RunCam(Cam(4, '[directed_keys]', '[coop_k_near]'))
    Test.expect(#f.directed_lost == 0, 'not lost; got ' .. #f.directed_lost)
    Test.expect(#f.fallbacks == 1 and Blind(f.fallbacks[1]) == 'Bass + Guitar=generic',
        'got ' .. (f.fallbacks[1] and Blind(f.fallbacks[1]) or 'none'))
end)

Test.it('a directed cut with a normal companion every lineup can play is clean', function()
    local f = RunCam(Cam(4, '[directed_keys]', '[coop_all_near]'))
    Test.expect(#f.directed_lost == 0 and #f.fallbacks == 0, 'covered')
end)

Test.it('a stack where nothing fits is generic, not duo-to-single', function()
    -- Two stacked flags, so the "no other stacked flags" condition fails.
    local f = RunCam(Cam(4, '[coop_bk_near]', '[coop_gk_near]'))
    Test.expect(#f.fallbacks == 1, 'one spot; got ' .. #f.fallbacks)
    Test.expect(Blind(f.fallbacks[1]) == 'Bass + Guitar=generic', 'got ' .. Blind(f.fallbacks[1]))
    Test.expect(#f.fallbacks[1].shots == 2, 'the report names both authored shots')
end)

Test.it('a spot every lineup can play produces no entry at all', function()
    local f = RunCam(Cam(4, '[coop_bg_near]', '[coop_k_near]'))
    Test.expect(#f.fallbacks == 0, 'got ' .. #f.fallbacks)
end)

Test.it('a four-piece project needs no companion to be covered', function()
    local f = RunCam(Cam(4, '[coop_bg_near]'), NO_KEYS)
    Test.expect(#f.fallbacks == 0, 'the only lineup can play it')
    Test.expect(#f.unreachable == 0, 'nothing unreachable')
end)

Test.section('CameraFallback (shared with the Venue Preview)')

local NO_GUITAR = { g = true }

Test.it('a stack with a shot that fits has no fallback', function()
    Test.expect(CameraFallback(Cam(4, '[coop_g_near]', '[coop_all_near]'), NO_GUITAR) == nil, 'fits')
end)

Test.it('a lone duo falls back to the partner, a single to a generic band shot', function()
    local d = CameraFallback(Cam(4, '[coop_bg_near]'), NO_GUITAR)
    Test.expect(d.kind == 'duo_single' and d.note == 'Bass' and d.ev.msg == '[coop_bg_near]',
        'duo: ' .. tostring(d.kind) .. ' ' .. tostring(d.note))
    Test.expect(d.play == '[coop_b_near]', 'duo pictures the partner: ' .. tostring(d.play))
    local s = CameraFallback(Cam(4, '[coop_g_near]'), NO_GUITAR)
    Test.expect(s.kind == 'generic' and s.ev.msg == '[coop_g_near]', 'single: ' .. tostring(s.kind))
    Test.expect(s.play == '[coop_all_near]', 'single pictures All (near): ' .. tostring(s.play))
    local b = CameraFallback(Cam(4, '[coop_bg_behind]'), NO_GUITAR)
    Test.expect(b.play == '[coop_b_behind]', 'behind duo stays behind: ' .. tostring(b.play))
    local gb = CameraFallback(Cam(4, '[coop_g_behind]'), NO_GUITAR)
    Test.expect(gb.play == '[coop_all_behind]', 'behind single: ' .. tostring(gb.play))
    local l = CameraFallback(Cam(4, '[directed_guitar]'), NO_GUITAR)
    Test.expect(l.play == '[coop_all_near]',
        'a lost directed cut pictures the generic shot played instead: ' .. tostring(l.play))
end)

Test.it('only directed cuts that cannot play are lost; with a normal shot it falls back', function()
    local l = CameraFallback(Cam(4, '[directed_guitar]'), NO_GUITAR)
    Test.expect(l.kind == 'directed_lost' and l.ev.msg == '[directed_guitar]', 'lost: ' .. tostring(l.kind))
    local m = CameraFallback(Cam(4, '[directed_guitar]', '[coop_g_near]'), NO_GUITAR)
    Test.expect(m.kind == 'generic' and m.ev.msg == '[coop_g_near]',
        'mixed shows the normal shot: ' .. tostring(m.kind) .. ' ' .. tostring(m.ev and m.ev.msg))
end)

Test.section('Camera stacks - shots that never play')

Test.it('a generic shot stacked under an always-valid specific one never plays', function()
    local f = RunCam(Cam(4, '[coop_all_near]', '[coop_gv_near]'), NO_KEYS)
    Test.expect(#f.unreachable == 1, 'expected 1, got ' .. #f.unreachable)
    Test.expect(f.unreachable[1].msg == '[coop_all_near]', 'got ' .. f.unreachable[1].msg)
    Test.expect(f.unreachable[1].fits_any, 'it fits the lineup, it is just outranked')
    local b = f.unreachable[1].beaten_by
    Test.expect(#b == 1 and b[1].msg == '[coop_gv_near]', 'got ' .. tostring(b[1] and b[1].msg))
end)

Test.it('a shot outranked by a different sibling per lineup names all of them', function()
    -- Bass + Guitar plays the guitar shot, Bass + Keys the keys shot (the keys
    -- exception), Guitar + Keys has no bass - so the bass shot never plays, and it
    -- takes removing both siblings to free it.
    local f = RunCam(Cam(4, '[coop_b_near]', '[coop_g_near]', '[coop_k_near]'))
    local u
    for _, it in ipairs(f.unreachable) do if it.msg == '[coop_b_near]' then u = it end end
    Test.expect(u ~= nil, 'coop_b_near is unreachable')
    local got = {}
    for _, b in ipairs(u.beaten_by) do got[#got + 1] = b.msg .. '=' .. table.concat(b.lineups, ',') end
    Test.expect(table.concat(got, ' | ') == '[coop_g_near]=Bass + Guitar | [coop_k_near]=Bass + Keys',
        'got ' .. table.concat(got, ' | '))
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

Test.it('a lone unplayable shot is a fallback spot, not an unreachable shot', function()
    local f = RunCam(Cam(4, '[coop_k_near]'), NO_KEYS)
    Test.expect(#f.unreachable == 0, 'not double-reported; got ' .. Msgs(f.unreachable))
    Test.expect(#f.fallbacks == 1, 'reported once, as a fallback spot')
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

-- ---------------------------------------------------------------------------
-- Directed-cut timing (venue_camera_timing.lua): what plays after a directed cut.
-- Pure over the same camera arrays, plus a ppq -> seconds function (120 BPM here,
-- so a beat is half a second) and, for exact cases, fixed move lengths.

local function SecOf(ppq) return ppq / PPQ * 0.5 end

local LENGTHS = {
    ['[directed_guitar]']   = { 0.5, 2 },
    ['[directed_drums_lt]'] = { 6, 16 },
    ['[directed_vocals]']   = { 0.5, 3 },
}
local function LenOf(msg) return LENGTHS[msg] end

local function RunTiming(camera, lineups)
    return ValidateDirectedCutTiming(camera, lineups or NO_KEYS, SecOf, LenOf)
end

Test.section('Directed-cut timing')

Test.it('the follow-up is never shown when the next event cuts the move first', function()
    -- The bar-86 case: a long move, a follow-up 4 s after it, the next event 5.7 s
    -- after it - the move (6 s or more) is still running, so the follow-up is skipped.
    local f = RunTiming(Cams(Cam(0, '[directed_drums_lt]'),
                             Cam(8, '[coop_d_behind]'),
                             Cam(11.4, '[coop_d_closeup_hand]')))
    Test.expect(#f.follow_skipped == 1, 'expected 1, got ' .. #f.follow_skipped)
    local e = f.follow_skipped[1]
    Test.expect(e.msg == '[coop_d_behind]' and e.next_msg == '[coop_d_closeup_hand]',
        'got ' .. tostring(e.msg) .. ' / ' .. tostring(e.next_msg))
    Test.expect(#f.follow_early == 0, 'a skipped follow-up is not also early')
end)

Test.it('a follow-up right after the cut is not reported when the next event ends the move', function()
    -- The official way to let the next spot end a long move: the follow-up only says
    -- what comes next, it has no time of its own to lose.
    local f = RunTiming(Cams(Cam(0, '[directed_drums_lt]'),
                             Cam(0.2, '[coop_all_far]'),
                             Cam(8, '[coop_d_closeup_hand]')))
    Test.expect(#f.follow_skipped == 0, 'expected none, got ' .. #f.follow_skipped)
end)

Test.it('the follow-up shows early when it sits after even the longest move', function()
    -- directed_guitar runs at most 2 s; the follow-up is 4 s after it.
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(8, '[coop_b_near]'), Cam(16, '[coop_all_far]')))
    Test.expect(#f.follow_early == 1 and f.follow_early[1].msg == '[coop_b_near]',
        'expected the bass shot early; got ' .. #f.follow_early)
    Test.expect(#f.follow_skipped == 0, 'nothing skipped')
end)

Test.it('a follow-up inside the move range is not reported either way', function()
    -- 1.5 s after a 0.5-2 s move: depends on the variant, so no finding.
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(3, '[coop_b_near]'), Cam(16, '[coop_all_far]')))
    Test.expect(#f.follow_early == 0 and #f.follow_skipped == 0, 'uncertain - nothing reported')
end)

Test.it('the usual follow-up right after the cut is clean', function()
    -- Official venues put the next shot ~0.1 s after a directed cut.
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(0.2, '[coop_all_far]'), Cam(8, '[coop_g_near]')))
    Test.expect(#f.follow_early == 0 and #f.follow_skipped == 0 and #f.directed_replaced == 0, 'clean')
end)

Test.it('a directed cut right after a directed cut is replaced', function()
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(8, '[directed_vocals]'), Cam(16, '[coop_all_far]')))
    Test.expect(#f.directed_replaced == 1, 'expected 1, got ' .. #f.directed_replaced)
    local e = f.directed_replaced[1]
    Test.expect(e.msg == '[directed_vocals]' and e.prev_msg == '[directed_guitar]' and e.plays == nil,
        'nothing stacked, so a generic shot; got ' .. tostring(e.plays))
end)

Test.it('a replaced directed cut names the stacked normal shot that plays instead', function()
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(8, '[directed_vocals]', '[coop_v_near]'),
                             Cam(16, '[coop_all_far]')))
    Test.expect(#f.directed_replaced == 1 and f.directed_replaced[1].plays == '[coop_v_near]',
        'got ' .. tostring(f.directed_replaced[1] and f.directed_replaced[1].plays))
end)

Test.it('a replaced directed cut is not timed as a directed cut', function()
    -- The replaced spot plays a normal shot, so the spot after it is an ordinary cut,
    -- and a directed cut after that may play again.
    local f = RunTiming(Cams(Cam(0, '[directed_guitar]'), Cam(8, '[directed_vocals]'),
                             Cam(16, '[directed_guitar]'), Cam(16.2, '[coop_all_far]')))
    Test.expect(#f.directed_replaced == 1, 'only the second cut; got ' .. #f.directed_replaced)
end)

Test.it('a stacked normal shot only matters for a lineup that cannot play the cut', function()
    -- Guitar + Keys has no bass: directed_bass does not play there, the stacked
    -- coop does, so only the two lineups with a bassist time the directed cut.
    local f = RunTiming(Cams(Cam(0, '[directed_bass]', '[coop_all_near]'),
                             Cam(8, '[coop_d_near]'), Cam(16, '[coop_all_far]')), FULL_BAND)
    Test.expect(#f.follow_early == 0, 'no length data for directed_bass here - not timed')
    LENGTHS['[directed_bass]'] = { 0.5, 2 }
    f = RunTiming(Cams(Cam(0, '[directed_bass]', '[coop_all_near]'),
                       Cam(8, '[coop_d_near]'), Cam(16, '[coop_all_far]')), FULL_BAND)
    LENGTHS['[directed_bass]'] = nil
    Test.expect(#f.follow_early == 1, 'one spot; got ' .. #f.follow_early)
    Test.expect(table.concat(f.follow_early[1].lineups, ' | ') == 'Bass + Guitar | Bass + Keys',
        'got ' .. table.concat(f.follow_early[1].lineups, ' | '))
end)

Test.it('move lengths come from the shot data', function()
    local lt = DirectedCutLength('[directed_drums_lt]')
    Test.expect(lt and lt[1] > 6 and lt[2] > lt[1], 'drums_lt runs over 6 s at least')
    Test.expect(DirectedCutLength('[coop_all_far]') == nil, 'normal shots have no length')
    Test.expect(DirectedCutLength('[directed_nonsense]') == nil, 'unknown cut: nil')
end)

Test.it('a shot just after a directed cut is a follow-up, not a botched stack', function()
    local camera = Cams(Cam(4, '[directed_guitar]'),
                        { { ppq = 4 * PPQ + 10, msg = '[coop_all_far]' } })
    local f = RunCam(camera, NO_KEYS)
    Test.expect(#f.near_stacks == 0, 'expected none, got ' .. #f.near_stacks)
end)

-- CameraGameTimeline: the Venue Preview's camera row, one lineup. Events carry t
-- (seconds); 120 BPM again, so beat b is at b / 2 s.
local function TL(...)
    local camera = Cams(...)
    for _, ev in ipairs(camera) do ev.t = SecOf(ev.ppq) end
    return CameraGameTimeline(camera, NO_KEYS[1].muted, LenOf)
end

local function Shown(items)
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = ('%s@%g'):format(it.ev and it.ev.msg or '?', it.t)
    end
    return table.concat(out, ' ')
end

Test.section('Camera timeline (Venue Preview)')

Test.it('a follow-up the next event cuts out stays at its position, marked never shown', function()
    -- README example 1: lt at bar 3, A at bar 4, B at bar 5 (4 s after the cut).
    local items = TL(Cam(8, '[directed_drums_lt]'), Cam(12, '[coop_all_far]'), Cam(16, '[coop_d_near]'))
    Test.expect(Shown(items) == '[directed_drums_lt]@4 [coop_all_far]@6 [coop_d_near]@8', 'got ' .. Shown(items))
    Test.expect(items[2].follow and items[2].follow.skipped, 'A is marked never shown')
    Test.expect(items[1].skips == items[2], 'the cut names what it skips')
end)

Test.it('a follow-up plays as soon as the move ends: marked, at its own position', function()
    -- README example 3: B far away, so A shows when the move ends.
    local items = TL(Cam(8, '[directed_drums_lt]'), Cam(12, '[coop_all_far]'), Cam(80, '[coop_d_near]'))
    Test.expect(Shown(items) == '[directed_drums_lt]@4 [coop_all_far]@6 [coop_d_near]@40', 'got ' .. Shown(items))
    local f = items[2].follow
    Test.expect(f and f.dir.msg == '[directed_drums_lt]' and not f.skipped and not f.maybe_skipped,
        'certain follow-up')
end)

Test.it('a next event inside the move range marks the follow-up as maybe skipped', function()
    local items = TL(Cam(8, '[directed_drums_lt]'), Cam(8.2, '[coop_all_far]'), Cam(28, '[coop_d_near]'))
    -- B is 10 s after the cut: past the 6 s shortest move, before the 16 s longest.
    Test.expect(items[2].follow and items[2].follow.maybe_skipped and not items[2].follow.skipped,
        'maybe skipped')
    Test.expect(math.abs(items[2].t - 4.1) < 0.01, 'at its own position; got ' .. items[2].t)
end)

Test.it('a follow-up of a cut with no length data is still marked', function()
    local items = TL(Cam(0, '[directed_crowd]'), Cam(4, '[coop_all_far]'), Cam(8, '[coop_d_near]'))
    local f = items[2].follow
    Test.expect(f and f.len == nil and not f.skipped, 'marked, nothing guessed')
end)

Test.it('a directed cut right after a directed cut shows as replaced', function()
    local items = TL(Cam(0, '[directed_guitar]'), Cam(8, '[directed_vocals]', '[coop_v_near]'),
                     Cam(16, '[coop_all_far]'))
    local r2 = items[2].replaced
    Test.expect(r2 and r2.by and r2.by.msg == '[coop_v_near]', 'the stacked normal shot plays')
    Test.expect(r2.prev.msg == '[directed_guitar]', 'names the directed cut before it')
end)

Test.it('ordinary normal shots keep their own positions', function()
    local items = TL(Cam(0, '[coop_all_far]'), Cam(4, '[coop_g_near]'), Cam(8, '[coop_d_near]'))
    Test.expect(Shown(items) == '[coop_all_far]@0 [coop_g_near]@2 [coop_d_near]@4', 'got ' .. Shown(items))
end)

Test.it('as written: every spot at its own position, no directed-cut rules', function()
    local camera = Cams(Cam(8, '[directed_drums_lt]'), Cam(12, '[coop_all_far]'), Cam(16, '[coop_d_near]'))
    for _, ev in ipairs(camera) do ev.t = SecOf(ev.ppq) end
    local items = CameraGameTimeline(camera, NO_KEYS[1].muted, LenOf, true)
    Test.expect(Shown(items) == '[directed_drums_lt]@4 [coop_all_far]@6 [coop_d_near]@8', 'got ' .. Shown(items))
    Test.expect(not items[1].skips and not items[2].follow, 'no timing notes')
end)
