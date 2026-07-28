-- Tests for the "Vocal phrase start" camera pacing mode (S.venue_cam_pacing == 7):
-- GenerateCameraEvents' phrase branch (venue_camera.lua, pure - no fixtures needed),
-- CollectVocalPhraseStarts note-start-only filtering (venue_lighting.lua, needs a
-- fixture PART VOCALS track), and FindNextVocalPhraseStartPpq (actions_venue_manual.lua).

local PPQ = 960
local ST  = PPQ / 4  -- sixteenth_ticks

----------------------------------------------------------------------
Test.section('GenerateCameraEvents: phrase mode (pure)')
----------------------------------------------------------------------

Test.it('coop events land exactly on phrase positions, in order, no tail bonus', function()
    local pool   = { '[coop_all_far]' }  -- single entry: deterministic PickRandom
    local events = GenerateCameraEvents(pool, {}, 100, PPQ, nil, nil, nil, nil, nil, nil, nil,
                                        { 10, 50, 90 })
    Test.expect(#events == 3, 'exactly 3 events, got ' .. #events)
    local expected_ticks = { 10 * ST, 50 * ST, 90 * ST }
    for i, ev in ipairs(events) do
        Test.expect(ev.tick == expected_ticks[i],
            ('event %d tick %d != expected %d'):format(i, ev.tick, expected_ticks[i]))
        Test.expect(ev.text == '[coop_all_far]', 'event text')
        Test.expect(not ev.is_directed, 'coop event is not directed')
    end
end)

Test.it('a forced cut still fires with an empty phrase list', function()
    local events = GenerateCameraEvents({ '[coop_all_far]' }, {}, 100, PPQ, nil,
                                        { { pos_16ths = 20, text = '[directed_test]' } },
                                        nil, nil, nil, nil, nil, {})
    Test.expect(#events == 1, 'exactly 1 event, got ' .. #events)
    Test.expect(events[1].text == '[directed_test]', 'forced cut text: ' .. tostring(events[1].text))
    Test.expect(events[1].is_directed, 'forced cut is marked directed')
    Test.expect(events[1].tick == 20 * ST, 'forced cut tick: ' .. tostring(events[1].tick))
end)

Test.it('empty phrase list and no forced cuts yields zero events', function()
    local events = GenerateCameraEvents({ '[coop_all_far]' }, {}, 100, PPQ, nil, nil, nil,
                                        nil, nil, nil, nil, {})
    Test.expect(#events == 0, 'no events, got ' .. #events)
end)

Test.it('start_min filters out phrases before it', function()
    local events = GenerateCameraEvents({ '[coop_all_far]' }, {}, 100, PPQ, nil, nil, nil,
                                        55, nil, nil, nil, { 10, 50, 90 })
    Test.expect(#events == 1, 'only the phrase at/after start_min=55, got ' .. #events)
    Test.expect(events[1].tick == 90 * ST, 'lands on the 90 phrase, not 50: got ' .. tostring(events[1].tick))
end)

----------------------------------------------------------------------
Test.section('CollectVocalPhraseStarts (note-start-only filtering)')
----------------------------------------------------------------------

-- These tests create a track named "PART VOCALS"; never run them against a project
-- that already has one.
if FindTrackByName('PART VOCALS') then
    r.ShowConsoleMsg('  SKIP  CollectVocalPhraseStarts tests (project already has PART VOCALS)\n')
else
    local function WithVocalsFixture(fn, item_len)
        local idx   = CreateEmptyFixtureTrack('PART VOCALS')
        local track = r.GetTrack(0, idx)
        local item  = r.CreateNewMIDIItemInProj(track, 0, item_len or 20, false)
        local take  = r.GetActiveTake(item)
        local ok, err = pcall(fn, take)
        CleanupFixture(idx)
        if not ok then error(err, 2) end
    end

    local function InsertPhrase(take, s, e)
        r.MIDI_InsertNote(take, false, false,
            r.MIDI_GetPPQPosFromProjTime(take, s), r.MIDI_GetPPQPosFromProjTime(take, e),
            0, RB3_PHRASE_PITCH, 100, false)
    end

    Test.it('a phrase starting before the range but overlapping it is excluded', function()
        WithVocalsFixture(function(take)
            InsertPhrase(take, 1, 6)  -- starts before range_start (5s), tails into it
            InsertPhrase(take, 7, 9)  -- fully inside range
            local range_s = r.MIDI_GetPPQPosFromProjTime(take, 5)
            local range_e = r.MIDI_GetPPQPosFromProjTime(take, 10)
            local positions = CollectVocalPhraseStarts(take, range_s, range_e)
            Test.expect(#positions == 1, 'only the phrase starting in-range, got ' .. #positions)
        end)
    end)

    Test.it('a phrase starting inside the range but ending past it is included', function()
        WithVocalsFixture(function(take)
            InsertPhrase(take, 8, 15)  -- starts in range, ends past range_end (10s)
            local range_s = r.MIDI_GetPPQPosFromProjTime(take, 5)
            local range_e = r.MIDI_GetPPQPosFromProjTime(take, 10)
            local positions = CollectVocalPhraseStarts(take, range_s, range_e)
            Test.expect(#positions == 1, 'phrase included despite extending past range_end')
        end)
    end)
end

----------------------------------------------------------------------
Test.section('FindNextVocalPhraseStartPpq (actions_venue_manual.lua)')
----------------------------------------------------------------------

if FindTrackByName('PART VOCALS') then
    r.ShowConsoleMsg('  SKIP  FindNextVocalPhraseStartPpq tests (project already has PART VOCALS)\n')
else
    Test.it('returns the next phrase strictly after cur_ppq, nil at/after the last one', function()
        local idx   = CreateEmptyFixtureTrack('PART VOCALS')
        local track = r.GetTrack(0, idx)
        local item  = r.CreateNewMIDIItemInProj(track, 0, 20, false)
        local take  = r.GetActiveTake(item)
        local ok, err = pcall(function()
            r.MIDI_InsertNote(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, 2), r.MIDI_GetPPQPosFromProjTime(take, 3),
                0, RB3_PHRASE_PITCH, 100, false)
            r.MIDI_InsertNote(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, 6), r.MIDI_GetPPQPosFromProjTime(take, 8),
                0, RB3_PHRASE_PITCH, 100, false)

            -- Read the notes back so comparisons use REAPER's own stored tick positions,
            -- not an independently recomputed time->PPQ conversion (which, at whatever
            -- tempo the open test project happens to use, can land a sub-tick epsilon
            -- off the actual stored integer-tick note position and break exact ==).
            local _, _, _, p2_ppq = r.MIDI_GetNote(take, 0)
            local _, _, _, p6_ppq = r.MIDI_GetNote(take, 1)

            local next1 = FindNextVocalPhraseStartPpq(take, 0)
            Test.expect(next1 == p2_ppq, 'first call from 0 finds the phrase at 2s')

            local next2 = FindNextVocalPhraseStartPpq(take, p2_ppq)
            Test.expect(next2 == p6_ppq, 'strictly after the first phrase finds the second')

            local next3 = FindNextVocalPhraseStartPpq(take, p6_ppq)
            Test.expect(next3 == nil, 'at the last phrase start -> nil')

            local next4 = FindNextVocalPhraseStartPpq(take, p6_ppq + 1000)
            Test.expect(next4 == nil, 'past the last phrase -> nil')
        end)
        CleanupFixture(idx)
        if not ok then error(err, 2) end
    end)
end
