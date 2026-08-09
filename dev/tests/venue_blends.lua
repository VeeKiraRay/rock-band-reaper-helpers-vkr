-- Blend-anchor read and write sides.
--
-- Read: AnnotateVenueBlends (venue.lua) collapses anchors out of a preset timeline
-- and annotates what survives, which is what the Venue Preview draws from.
-- Write: GenerateThemedSectionEvents (venue_lighting.lua) must never re-state a
-- preset that is already running - two identical adjacent events ARE an anchor, so
-- an accidental one would be read back as deliberate by the validator, the Keyframes
-- tab and Manual gen's Blend button.

-- ---------------------------------------------------------------------------
-- AnnotateVenueBlends - pure, no project state
-- ---------------------------------------------------------------------------

Test.section('AnnotateVenueBlends')

-- Build a {msg, t, ppq} list from {msg, t} pairs; ppq is t scaled so the two stay
-- distinguishable in assertions.
local function Evs(list)
    local out = {}
    for i, pair in ipairs(list) do
        out[i] = { msg = pair[1], t = pair[2], ppq = pair[2] * 960, evtype = 1 }
    end
    return out
end

Test.it('empty and single-event lists', function()
    local none = AnnotateVenueBlends({})
    Test.expect(#none == 0, 'empty list should stay empty')
    Test.expect(#AnnotateVenueBlends(nil) == 0, 'nil should give an empty list')

    local one = AnnotateVenueBlends(Evs({ { '[lighting (stomp)]', 1 } }))
    Test.expect(#one == 1, 'single event should survive')
    Test.expect(one[1].next_t == nil, 'single event has nothing following it')
    Test.expect(one[1].blend_out_t == nil, 'single event cannot blend into anything')
end)

Test.it('no anchors: every event survives as a hard cut', function()
    local out = AnnotateVenueBlends(Evs({
        { '[lighting (stomp)]', 1 },
        { '[lighting (verse)]', 2 },
        { '[lighting (chorus)]', 3 },
    }))
    Test.expect(#out == 3, 'expected 3 events, got ' .. #out)
    for i = 1, 3 do
        Test.expect(out[i].blend_out_t == nil, 'event ' .. i .. ' should be a hard cut')
    end
    Test.expect(out[1].next_t == 2, 'next_t should point at the following change')
    Test.expect(out[2].next_t == 3, 'next_t should chain')
    Test.expect(out[3].next_t == nil, 'last event has no next')
end)

Test.it('one anchor pair: the duplicate is dropped and annotates its source', function()
    -- stomp at m1, restated at 1.8 as the anchor, verse takes over at 2.
    local out = AnnotateVenueBlends(Evs({
        { '[lighting (stomp)]', 1 },
        { '[lighting (stomp)]', 1.8 },
        { '[lighting (verse)]', 2 },
    }))
    Test.expect(#out == 2, 'the anchor should not survive as an event; got ' .. #out)
    Test.expect(out[1].msg == '[lighting (stomp)]', 'first survivor should be the original')
    Test.expect(out[2].msg == '[lighting (verse)]', 'second survivor should be the change')
    Test.expect(out[1].blend_out_t == 1.8, 'blend_out_t should be the anchor position')
    Test.expect(out[1].blend_out_ppq == 1.8 * 960, 'blend_out_ppq should come along')
    Test.expect(out[1].next_t == 2, 'next_t should be where the change lands')
    Test.expect(out[2].blend_out_t == nil, 'the incoming preset has no anchor of its own')
end)

Test.it('three identical copies: blend_out_t is the LAST restatement', function()
    -- IsBlendAnchor only ever compares adjacent events, so the pair the game reads
    -- is the last copy and the change - not the first copy.
    local out = AnnotateVenueBlends(Evs({
        { '[lighting (stomp)]', 1 },
        { '[lighting (stomp)]', 1.5 },
        { '[lighting (stomp)]', 1.8 },
        { '[lighting (verse)]', 2 },
    }))
    Test.expect(#out == 2, 'both duplicates should be dropped; got ' .. #out)
    Test.expect(out[1].blend_out_t == 1.8, 'expected the last copy, got '
        .. tostring(out[1].blend_out_t))
end)

Test.it('a preset returning after a different one is a fresh change', function()
    -- stomp, verse, stomp: the two stomps are not adjacent, so neither is an anchor
    -- and the second one is a real change needing its own.
    local out = AnnotateVenueBlends(Evs({
        { '[lighting (stomp)]', 1 },
        { '[lighting (verse)]', 2 },
        { '[lighting (stomp)]', 3 },
    }))
    Test.expect(#out == 3, 'nothing should be collapsed; got ' .. #out)
    Test.expect(out[1].blend_out_t == nil, 'stomp -> verse is a hard cut')
    Test.expect(out[2].blend_out_t == nil, 'verse -> stomp is a hard cut')
end)

Test.it('inputs are never modified', function()
    local input = Evs({
        { '[ProFilm_a.pp]', 1 },
        { '[ProFilm_a.pp]', 1.5 },
        { '[ProFilm_b.pp]', 2 },
    })
    AnnotateVenueBlends(input)
    Test.expect(#input == 3, 'the source list should still hold its anchor')
    Test.expect(input[1].blend_out_t == nil, 'the source records should be untouched')
end)

Test.it('IsBlendAnchor handles the ends of a track', function()
    local a = { msg = '[lighting (stomp)]' }
    Test.expect(IsBlendAnchor(a, a), 'two identical events are an anchor')
    Test.expect(not IsBlendAnchor(nil, a), 'nothing before the first event')
    Test.expect(not IsBlendAnchor(a, nil), 'nothing after the last event')
    Test.expect(not IsBlendAnchor(a, { msg = '[lighting (verse)]' }), 'a change is not an anchor')
end)

-- ---------------------------------------------------------------------------
-- GenerateThemedSectionEvents - needs a real take for its PPQ conversions
-- ---------------------------------------------------------------------------

-- These tests create a track named VENUE; never run them against a project that
-- already has one.
if FindTrackByName('VENUE') then
    r.ShowConsoleMsg('\n  SKIP  themed generation tests (this project already has a VENUE track)\n')
else

Test.section('Themed generation - never re-states a running preset')

local ITEM_LEN = 24  -- seconds

-- Run fn with a fixture VENUE track + MIDI item, always cleaning up.
-- fn(take, ppq, range_start_ppq, range_end_ppq).
local function WithVenue(fn)
    local idx   = CreateEmptyFixtureTrack('VENUE')
    local track = r.GetTrack(0, idx)
    local item  = r.CreateNewMIDIItemInProj(track, 0, ITEM_LEN, false)
    local take  = r.GetActiveTake(item)
    local ppq   = GetTakePPQPerQN(take)
    local ok, err = pcall(fn, take, ppq,
        r.MIDI_GetPPQPosFromProjTime(take, 0),
        r.MIDI_GetPPQPosFromProjTime(take, ITEM_LEN))
    CleanupFixture(idx)
    if not ok then error(err, 2) end
end

-- Two adjacent sections covering 2..8s and 8..14s, both falling through to `default`.
local function TwoSections()
    return {
        { name = 'verse',  num = 1, t_start = 2, t_end = 8  },
        { name = 'chorus', num = 1, t_start = 8, t_end = 14 },
    }
end

local function Theme(lightpresets, postprocs, extra)
    local preset = {
        allowed_lightpresets = lightpresets,
        allowed_postprocs    = postprocs,
        keyframe_rate        = 2,
    }
    for k, v in pairs(extra or {}) do preset[k] = v end
    return { section_presets = { default = preset } }
end

local function CountText(events, text)
    local n = 0
    for _, ev in ipairs(events) do
        if ev.text == text then n = n + 1 end
    end
    return n
end

Test.it('a single-entry pool shared by two sections emits one event, not two', function()
    WithVenue(function(take, ppq, rs, re)
        local lt, ctrl, pp, stats = GenerateThemedSectionEvents(
            TwoSections(), Theme({ 'stomp' }, { 'ProFilm_a.pp' }), take, rs, re, ppq)

        Test.expect(#lt == 1, 'expected 1 lighting event, got ' .. #lt)
        Test.expect(lt[1].text == '[lighting (stomp)]', 'wrong preset: ' .. lt[1].text)
        Test.expect(stats.lt_skipped == 1, 'expected 1 skipped lighting, got ' .. stats.lt_skipped)

        Test.expect(#pp == 1, 'expected 1 postproc event, got ' .. #pp)
        Test.expect(stats.pp_skipped == 1, 'expected 1 skipped postproc, got ' .. stats.pp_skipped)

        -- Exactly one [first]: only the section that actually changed the preset.
        Test.expect(CountText(ctrl, '[first]') == 1,
            'expected 1 [first], got ' .. CountText(ctrl, '[first]'))
    end)
end)

Test.it('the kept section still gets its [next] train', function()
    -- The skipped event must not take the keyframes with it: the previous section's
    -- train stopped at ITS own end, so section 2 needs its own or the lights freeze.
    WithVenue(function(take, ppq, rs, re)
        local _, ctrl = GenerateThemedSectionEvents(
            TwoSections(), Theme({ 'stomp' }, nil), take, rs, re, ppq)

        local sec2_ppq  = r.MIDI_GetPPQPosFromProjTime(take, 8) - rs
        local in_sec2   = 0
        for _, ev in ipairs(ctrl) do
            if ev.text == '[next]' and ev.tick >= sec2_ppq then in_sec2 = in_sec2 + 1 end
        end
        Test.expect(in_sec2 > 0, 'section 2 kept the preset but got no [next] events')
    end)
end)

Test.it('a multi-entry pool re-rolls instead of repeating', function()
    -- PickRandom retries up to 10 times, so a 2-entry pool colliding is a ~1/1024
    -- event per run. The bound is loose enough that the fallback can never fail the
    -- suite, and tight enough that a broken re-roll (every run collides) does.
    local both_emitted = 0
    for _ = 1, 20 do
        WithVenue(function(take, ppq, rs, re)
            local lt, _, _, stats = GenerateThemedSectionEvents(
                TwoSections(), Theme({ 'stomp', 'verse' }, nil), take, rs, re, ppq)
            Test.expect(#lt + stats.lt_skipped == 2, 'both sections should be accounted for')
            if #lt == 2 then
                Test.expect(lt[1].text ~= lt[2].text,
                    'emitted two identical adjacent events: ' .. lt[1].text)
                both_emitted = both_emitted + 1
            end
        end)
    end
    Test.expect(both_emitted >= 18,
        'expected the re-roll to avoid a repeat nearly every run, got ' .. both_emitted .. '/20')
end)

Test.it('incoming preset is honoured for the first section', function()
    WithVenue(function(take, ppq, rs, re)
        local lt, ctrl, _, stats = GenerateThemedSectionEvents(
            { { name = 'verse', num = 1, t_start = 2, t_end = 8 } },
            Theme({ 'stomp' }, nil), take, rs, re, ppq,
            { lt_text = '[lighting (stomp)]', sec_ppq = rs })

        Test.expect(#lt == 0, 'the running preset should not be re-stated; got ' .. #lt)
        Test.expect(stats.lt_skipped == 1, 'expected 1 skipped, got ' .. stats.lt_skipped)
        Test.expect(CountText(ctrl, '[first]') == 0, 'a kept preset starts no keyframe run')
    end)
end)

Test.it('lighting and post proc are judged independently', function()
    WithVenue(function(take, ppq, rs, re)
        local lt, _, pp, stats = GenerateThemedSectionEvents(
            { { name = 'verse', num = 1, t_start = 2, t_end = 8 } },
            Theme({ 'stomp' }, { 'ProFilm_b.pp' }), take, rs, re, ppq,
            -- lighting matches, post proc does not
            { lt_text = '[lighting (stomp)]', pp_text = '[ProFilm_a.pp]', sec_ppq = rs })

        Test.expect(#lt == 0, 'matching lighting should be skipped')
        Test.expect(stats.lt_skipped == 1, 'lighting skip should be counted')
        Test.expect(#pp == 1, 'differing post proc should still be written; got ' .. #pp)
        Test.expect(stats.pp_skipped == 0, 'post proc was a real change, nothing to skip')
    end)
end)

end  -- VENUE track guard
