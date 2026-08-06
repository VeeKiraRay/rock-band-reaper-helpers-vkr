-- VENUE lighting/blend validation rules (actions_venue_validate.lua).
--
-- Drives ValidateVenueLightingBlends directly: it is pure over three sorted
-- {ppq=, msg=} arrays, so every rule can be stated as a hand-built event list with
-- no project, no VENUE track and no MIDI editor. What that buys is precision - the
-- interesting cases here (a blend anchor that must NOT carry a [first], a change
-- three events back that must not count as an anchor) are fiddly to build as real
-- MIDI and trivial to state as four table entries.
--
-- Requires globals: Test, ValidateVenueLightingBlends, MANUAL_LIGHTING_SET
-- (set up by run_venue_validate.lua).

local PPQ  = 960                    -- ticks per quarter note
local TOL  = math.floor(PPQ / 32)   -- the 1/128-note "on this tick" tolerance
local NEAR = PPQ                    -- one beat: the misplaced-[first] window

local STOMP  = '[lighting (stomp)]'
local VERSE  = '[lighting (verse)]'
local CHORUS = '[lighting (chorus)]'
local LOOP   = '[lighting (loop_cool)]'   -- automatic - never keyframed
local PP_A   = '[ProFilm_a.pp]'
local PP_B   = '[ProFilm_b.pp]'

-- Events at beat positions, so a case reads as a timeline.
local function Ev(beat, msg) return { ppq = math.floor(beat * PPQ), msg = msg } end

local function At(...)
    local out = {}
    for _, b in ipairs({ ... }) do out[#out + 1] = { ppq = math.floor(b * PPQ) } end
    return out
end

local function Run(lighting, postproc, firsts)
    return ValidateVenueLightingBlends(lighting or {}, postproc or {}, firsts or {}, TOL, NEAR)
end

local function Kinds(f)
    local out = {}
    for _, s in ipairs(f.stray_first) do out[#out + 1] = s.kind end
    return table.concat(out, ',')
end

-- ---------------------------------------------------------------------------

Test.section('Missing [first] on a lighting change')

Test.it('a manual change with a [first] on its tick is clean', function()
    local f = Run({ Ev(0, STOMP) }, nil, At(0))
    Test.expect(#f.missing_first == 0, 'expected no missing [first]')
    Test.expect(#f.stray_first == 0, 'expected no stray [first], got ' .. Kinds(f))
end)

Test.it('a manual change with no [first] is reported', function()
    local f = Run({ Ev(0, STOMP) }, nil, {})
    Test.expect(#f.missing_first == 1, 'expected 1 missing, got ' .. #f.missing_first)
    Test.expect(f.missing_first[1].msg == STOMP, 'wrong event reported')
end)

-- The headline rule: a blend anchor restates the preset already running, so it starts
-- no keyframe train and must not be flagged for lacking a [first]. Reading the user's
-- brief literally ("every manual lighting event needs one") would fail here.
Test.it('a restatement (blend anchor) is NOT flagged as missing', function()
    local f = Run({ Ev(0, STOMP), Ev(36, STOMP), Ev(40, VERSE) }, nil, At(0, 40))
    Test.expect(#f.missing_first == 0, 'blend anchor should not want a [first]')
    Test.expect(#f.stray_first == 0, 'expected no stray, got ' .. Kinds(f))
end)

Test.it('an automatic preset never wants a [first]', function()
    local f = Run({ Ev(0, LOOP) }, nil, {})
    Test.expect(#f.missing_first == 0, 'automatic presets take no keyframes')
    Test.expect(f.manual_changes == 0, 'loop_cool should not count as a manual change')
end)

Test.it('a [first] inside the tolerance still counts as on-tick', function()
    local f = Run({ Ev(0, STOMP) }, nil, { { ppq = TOL } })
    Test.expect(#f.missing_first == 0, 'TOL ticks off should still pair')
    Test.expect(#f.stray_first == 0, 'and should not read as stray: ' .. Kinds(f))
end)

Test.it('a [first] just past the tolerance is missing + misaligned, cross-linked', function()
    local f = Run({ Ev(0, STOMP) }, nil, { { ppq = TOL + 1 } })
    Test.expect(#f.missing_first == 1, 'expected the change to want a [first]')
    Test.expect(Kinds(f) == 'misaligned', 'expected misaligned, got ' .. Kinds(f))
    Test.expect(f.missing_first[1].near_delta == TOL + 1,
        'missing entry should carry the nearby [first] delta for the report')
end)

Test.section('Stray [first] classification')

Test.it('[first] on a blend anchor reads as on_restatement', function()
    local f = Run({ Ev(0, STOMP), Ev(36, STOMP), Ev(40, VERSE) }, nil, At(0, 36, 40))
    Test.expect(Kinds(f) == 'on_restatement', 'got ' .. Kinds(f))
end)

Test.it('[first] on an automatic preset reads as on_auto', function()
    local f = Run({ Ev(0, LOOP) }, nil, At(0))
    Test.expect(Kinds(f) == 'on_auto', 'got ' .. Kinds(f))
end)

Test.it('[first] nowhere near a lighting event reads as orphan', function()
    local f = Run({ Ev(0, STOMP) }, nil, At(0, 20))
    Test.expect(Kinds(f) == 'orphan', 'got ' .. Kinds(f))
end)

Test.it('two [first] on one tick: the second is a duplicate', function()
    local f = Run({ Ev(0, STOMP) }, nil, At(0, 0))
    Test.expect(Kinds(f) == 'duplicate', 'got ' .. Kinds(f))
end)

-- Only a change that is actually MISSING its [first] can claim a nearby one; otherwise
-- "move it onto that event" would be wrong advice - the event already has one.
Test.it('a near [first] beside an already-paired change is an orphan, not misaligned', function()
    local f = Run({ Ev(0, STOMP) }, nil, { { ppq = 0 }, { ppq = 100 } })
    Test.expect(Kinds(f) == 'orphan', 'got ' .. Kinds(f))
end)

Test.it('[first] events with no lighting at all are orphans', function()
    local f = Run({}, nil, At(0, 4))
    Test.expect(Kinds(f) == 'orphan,orphan', 'got ' .. Kinds(f))
end)

Test.section('Blend anchors - lighting')

Test.it('a change preceded by a restatement is anchored', function()
    local f = Run({ Ev(0, STOMP), Ev(36, STOMP), Ev(40, VERSE) }, nil, At(0, 40))
    Test.expect(#f.blend.lt.missing == 0, 'expected the change to be anchored')
    Test.expect(f.blend.lt.anchored == 1 and f.blend.lt.changes == 1, 'wrong blend counts')
end)

Test.it('a hard cut is reported with both presets and where the old one started', function()
    local f = Run({ Ev(0, STOMP), Ev(40, VERSE) }, nil, At(0, 40))
    Test.expect(#f.blend.lt.missing == 1, 'expected 1 unanchored change')
    local b = f.blend.lt.missing[1]
    Test.expect(b.from_msg == STOMP and b.msg == VERSE, 'wrong from/to')
    Test.expect(b.from_ppq == 0 and b.ppq == 40 * PPQ, 'wrong positions')
end)

Test.it('the first lighting event of the song is exempt', function()
    local f = Run({ Ev(0, STOMP) }, nil, At(0))
    Test.expect(f.blend.lt.changes == 0, 'nothing precedes it to blend from')
    Test.expect(#f.blend.lt.missing == 0, 'and so it cannot be reported')
end)

Test.it('several restatements still anchor the change', function()
    local f = Run({ Ev(0, STOMP), Ev(20, STOMP), Ev(36, STOMP), Ev(40, VERSE) }, nil, At(0, 40))
    Test.expect(#f.blend.lt.missing == 0, 'expected anchored, got ' .. #f.blend.lt.missing)
end)

-- Only ADJACENT events are compared: a preset returning later is a real change again,
-- and the earlier run of it is not an anchor for it.
Test.it('a preset returning after another one is a fresh unanchored change', function()
    local f = Run({ Ev(0, VERSE), Ev(20, STOMP), Ev(40, VERSE) }, nil, At(0, 20, 40))
    Test.expect(f.blend.lt.changes == 2, 'both should count as changes')
    Test.expect(#f.blend.lt.missing == 2, 'neither is anchored')
    Test.expect(#f.missing_first == 0, 'all three carry their own [first]')
end)

Test.it('a fully blended three-section run is clean', function()
    local lighting = {
        Ev(0, STOMP),  Ev(38, STOMP),           -- section 1 + its outgoing anchor
        Ev(40, VERSE), Ev(78, VERSE),           -- section 2 + its outgoing anchor
        Ev(80, CHORUS),
    }
    local f = Run(lighting, nil, At(0, 40, 80))
    Test.expect(#f.missing_first == 0, 'no missing [first]')
    Test.expect(#f.stray_first == 0, 'no stray [first]: ' .. Kinds(f))
    Test.expect(#f.blend.lt.missing == 0, 'no missing blends')
    Test.expect(f.changes == 3 and f.manual_changes == 3, 'wrong change counts')
end)

Test.section('Blend anchors - post proc')

Test.it('post proc is judged independently of lighting', function()
    local lighting = { Ev(0, STOMP), Ev(38, STOMP), Ev(40, VERSE) }
    local pp       = { Ev(0, PP_A), Ev(40, PP_B) }
    local f = Run(lighting, pp, At(0, 40))
    Test.expect(#f.blend.lt.missing == 0, 'lighting is anchored')
    Test.expect(#f.blend.pp.missing == 1, 'post proc is not')
    Test.expect(f.blend.pp.missing[1].msg == PP_B, 'wrong post proc change reported')
end)

Test.it('post proc events never want a [first]', function()
    local f = Run({}, { Ev(0, PP_A), Ev(40, PP_B) }, {})
    Test.expect(#f.missing_first == 0, 'keyframes belong to lighting only')
end)

Test.it('an anchored post proc change is clean', function()
    local f = Run({}, { Ev(0, PP_A), Ev(38, PP_A), Ev(40, PP_B) }, {})
    Test.expect(#f.blend.pp.missing == 0, 'expected anchored')
    Test.expect(f.blend.pp.anchored == 1, 'wrong anchored count')
end)

Test.section('Edge cases')

Test.it('an empty track produces no findings', function()
    local f = Run({}, {}, {})
    Test.expect(#f.missing_first == 0 and #f.stray_first == 0, 'nothing to report')
    Test.expect(#f.blend.lt.missing == 0 and #f.blend.pp.missing == 0, 'nothing to report')
    Test.expect(f.changes == 0 and f.manual_changes == 0, 'counts should be zero')
end)

Test.it('MANUAL_LIGHTING_SET drives the manual/automatic split', function()
    -- Guards against the validator growing its own copy of the preset vocabulary:
    -- every preset it treats as manual must come from that one set.
    local n = 0
    for msg in pairs(MANUAL_LIGHTING_SET) do
        n = n + 1
        local f = Run({ Ev(0, msg) }, nil, {})
        Test.expect(#f.missing_first == 1, msg .. ' should want a [first]')
    end
    Test.expect(n == 6, 'expected 6 manual presets, got ' .. n)
end)
