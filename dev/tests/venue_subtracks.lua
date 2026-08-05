-- Tests for actions_venue_subtracks.lua: CategorizeVenueEvent classification, subtrack
-- creation/naming/muting via FindOrCreateSubtrack, item bounds sync via EnsureMatchingItem,
-- position-bridging copy correctness via CopyVenueEvents, the 5 public actions, and
-- RemoveVenueEventsByType's post-refactor behavior (actions_venue_manual.lua).

----------------------------------------------------------------------
Test.section('CategorizeVenueEvent (pure classification)')
----------------------------------------------------------------------

Test.it('classifies every category correctly, special is the catch-all', function()
    Test.expect(CategorizeVenueEvent('[first]') == 'keyframe', 'first')
    Test.expect(CategorizeVenueEvent('[next]') == 'keyframe', 'next')
    Test.expect(CategorizeVenueEvent('[previous]') == 'keyframe', 'previous')
    Test.expect(CategorizeVenueEvent('[coop_all_far]') == 'coop', 'coop')
    Test.expect(CategorizeVenueEvent('[directed_all]') == 'directed', 'directed')
    Test.expect(CategorizeVenueEvent('[lighting (loop_warm)]') == 'lighting', 'lighting')
    Test.expect(CategorizeVenueEvent('[lighting ()]') == 'lighting', 'lighting edge form')
    Test.expect(CategorizeVenueEvent('[ProFilm_a.pp]') == 'postproc', 'postproc')
    Test.expect(CategorizeVenueEvent('[bonusfx]') == 'special', 'bonusfx')
    Test.expect(CategorizeVenueEvent('[bonusfx_optional]') == 'special', 'bonusfx_optional')
    Test.expect(CategorizeVenueEvent('[totally_unknown]') == 'special', 'unknown falls to special')
end)

----------------------------------------------------------------------
Test.section('ResolveBlendSource (pure - Manual gen Blend button)')
----------------------------------------------------------------------

do
    local function E(ppq, msg) return { ppq = ppq, msg = msg } end
    local TOL = 30

    Test.it('two differing events: copies the later one, reports the earlier', function()
        local src, prev = ResolveBlendSource({ E(100, 'stomp'), E(500, 'verse') }, 900, TOL)
        Test.expect(src and src.msg == 'verse', 'expected the most recent event as source')
        Test.expect(prev and prev.msg == 'stomp', 'expected the one before it as prev')
    end)

    Test.it('two identical events: refused, a blend is already in place', function()
        local src, code, a, b =
            ResolveBlendSource({ E(100, 'stomp'), E(500, 'stomp') }, 900, TOL)
        Test.expect(src == nil and code == 'blended', 'expected a blended refusal')
        Test.expect(a and a.ppq == 500 and b and b.ppq == 100,
            'both offending events should come back for the report')
    end)

    Test.it('a single event copies, with no prev to compare against', function()
        local src, prev = ResolveBlendSource({ E(100, 'stomp') }, 900, TOL)
        Test.expect(src and src.msg == 'stomp', 'the only event should still be copied')
        Test.expect(prev == nil, 'there is no earlier event to report')
    end)

    Test.it('nothing before the cursor is refused, not treated as empty-and-fine', function()
        Test.expect(select(2, ResolveBlendSource({}, 900, TOL)) == 'none', 'empty list')
        Test.expect(select(2, ResolveBlendSource({ E(1000, 'a'), E(2000, 'b') }, 900, TOL))
            == 'none', 'every event after the cursor')
    end)

    Test.it('an event on the playhead is refused, and wins over every other outcome', function()
        local src, code, a = ResolveBlendSource({ E(100, 'stomp'), E(900, 'verse') }, 900, TOL)
        Test.expect(src == nil and code == 'occupied' and a.msg == 'verse', 'exact tick')
        Test.expect(select(2, ResolveBlendSource({ E(100, 'x'), E(915, 'y') }, 900, TOL))
            == 'occupied', 'inside the tolerance window')
        Test.expect(ResolveBlendSource({ E(100, 'x'), E(940, 'y') }, 900, TOL) ~= nil,
            'just outside the window should not be treated as occupied')
        -- Would otherwise be 'blended': occupied is checked first.
        Test.expect(select(2, ResolveBlendSource({ E(500, 'a'), E(900, 'a') }, 900, TOL))
            == 'occupied', 'occupied outranks blended')
    end)

    Test.it('events after the cursor are ignored when picking the pair', function()
        local src, prev =
            ResolveBlendSource({ E(100, 'a'), E(500, 'b'), E(2000, 'b') }, 900, TOL)
        Test.expect(src and src.ppq == 500, 'the trailing event must not become the source')
        Test.expect(prev and prev.ppq == 100,
            'nor may it make this look like an existing blend')
    end)
end

----------------------------------------------------------------------
-- These tests create a track named VENUE (plus subtracks); never run them against a
-- project that already has one.
if FindTrackByName('VENUE') then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has a VENUE track)\n')
else

    -- Run fn with a fixture VENUE track + MIDI item, always cleaning up. item_len defaults to
    -- 10 seconds starting at start_sec (default 0).
    local function WithVenueFixture(fn, item_len, len_is_qn, start_sec)
        local idx   = CreateEmptyFixtureTrack('VENUE')
        local track = r.GetTrack(0, idx)
        local s     = start_sec or 0
        local item  = r.CreateNewMIDIItemInProj(track, s, s + (item_len or 10), len_is_qn or false)
        local take  = r.GetActiveTake(item)
        local ok, err = pcall(fn, track, item, take)
        CleanupFixture(idx)
        if not ok then error(err, 2) end
    end

    local function InsertEvt(take, t, msg)
        r.MIDI_InsertTextSysexEvt(take, false, false,
            r.MIDI_GetPPQPosFromProjTime(take, t), 1, msg, false)
    end

    local function CountTextEvts(take)
        local _, _, _, n = r.MIDI_CountEvts(take)
        return n
    end

    -- All type-1 event strings on a take, in event-index order (not time-sorted).
    local function ReadMsgs(take)
        local out = {}
        local n = CountTextEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, _, evtype, msg = r.MIDI_GetTextSysexEvt(take, i)
            if ok and evtype == 1 then out[#out + 1] = msg end
        end
        return out
    end

    ------------------------------------------------------------------
    Test.section('CopyVenueToSubtracks (bulk create + split)')
    ------------------------------------------------------------------

    Test.it('creates 6 correctly-named, muted, contiguous tracks; idempotent on re-run', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            local venue_idx = select(2, FindTrackByName('VENUE'))
            InsertEvt(venue_take, 1, '[coop_all_far]')
            InsertEvt(venue_take, 2, '[directed_all]')
            InsertEvt(venue_take, 3, '[lighting (loop_warm)]')
            InsertEvt(venue_take, 4, '[first]')
            InsertEvt(venue_take, 5, '[ProFilm_a.pp]')
            InsertEvt(venue_take, 6, '[bonusfx]')

            CopyVenueToSubtracks()

            for i, cat in ipairs(VENUE_SUBTRACKS) do
                local tr, idx = FindTrackByName(cat.track_name)
                Test.expect(tr, cat.track_name .. ' exists')
                Test.expect(idx == venue_idx + i, cat.track_name .. ' at expected contiguous index')
                Test.expect(r.GetMediaTrackInfo_Value(tr, 'B_MUTE') == 1, cat.track_name .. ' muted')
            end

            local total_tracks = r.CountTracks(0)
            CopyVenueToSubtracks()
            Test.expect(r.CountTracks(0) == total_tracks, 'no duplicate tracks on re-run')

            local _, _, coop_take = FindNamedTrackMIDI('VENUE normal camera')
            Test.expect(CountTextEvts(coop_take) == 1, 'no accumulated duplicate events on re-run')
        end, 10)
    end)

    Test.it('splits each category into its own subtrack', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 1, '[coop_all_far]')
            InsertEvt(venue_take, 2, '[directed_all]')
            InsertEvt(venue_take, 3, '[lighting (loop_warm)]')
            InsertEvt(venue_take, 4, '[first]')
            InsertEvt(venue_take, 5, '[ProFilm_a.pp]')
            InsertEvt(venue_take, 6, '[bonusfx]')

            CopyVenueToSubtracks()

            local expect_msg = {
                coop = '[coop_all_far]', directed = '[directed_all]',
                lighting = '[lighting (loop_warm)]', keyframe = '[first]',
                postproc = '[ProFilm_a.pp]', special = '[bonusfx]',
            }
            for _, cat in ipairs(VENUE_SUBTRACKS) do
                local _, _, take = FindNamedTrackMIDI(cat.track_name)
                local msgs = ReadMsgs(take)
                Test.expect(#msgs == 1 and msgs[1] == expect_msg[cat.key],
                            cat.track_name .. ' got ' .. table.concat(msgs, ','))
            end
        end, 10)
    end)

    Test.it('FindOrCreateSubtrack copies VENUE MIDI note names onto a newly created subtrack', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            r.SetTrackMIDINoteNameEx(0, venue_track, 85, -1, 'Bassist sing')
            r.SetTrackMIDINoteNameEx(0, venue_track, 86, -1, 'Drummer sing')

            local sub_track = FindOrCreateSubtrack(VENUE_SUBTRACKS[1], venue_track, venue_track)

            Test.expect(r.GetTrackMIDINoteNameEx(0, sub_track, 85, -1) == 'Bassist sing',
                        'pitch 85 name copied')
            Test.expect(r.GetTrackMIDINoteNameEx(0, sub_track, 86, -1) == 'Drummer sing',
                        'pitch 86 name copied')
        end, 10)
    end)

    ------------------------------------------------------------------
    Test.section('EnsureMatchingItem / CopyVenueEvents (position-bridging logic helpers)')
    ------------------------------------------------------------------

    Test.it('EnsureMatchingItem names a newly created take after the track (REAPER take label, not a MIDI event)', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            local sub_track = FindOrCreateSubtrack(VENUE_SUBTRACKS[1], venue_track, venue_track)
            local _, sub_take = EnsureMatchingItem(sub_track, venue_item)

            local _, take_name = r.GetSetMediaItemTakeInfo_String(sub_take, 'P_NAME', '', false)
            Test.expect(take_name == VENUE_SUBTRACKS[1].track_name,
                        'take P_NAME matches the track name, got ' .. tostring(take_name))

            -- Hand-rename the take, then re-sync (item already exists) - must not be stomped
            r.GetSetMediaItemTakeInfo_String(sub_take, 'P_NAME', 'custom name', true)
            EnsureMatchingItem(sub_track, venue_item)
            local _, renamed = r.GetSetMediaItemTakeInfo_String(sub_take, 'P_NAME', '', false)
            Test.expect(renamed == 'custom name', 'hand-renamed take not overwritten on re-sync')
        end, 10)
    end)

    Test.it('CopyVenueEvents bridges positions via project time (nonzero item position)', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 6.5, '[coop_all_far]')  -- 1.5s into a 5s-start, 10s-long item

            local sub_track      = FindOrCreateSubtrack(VENUE_SUBTRACKS[1], venue_track, venue_track)
            local sub_item, sub_take = EnsureMatchingItem(sub_track, venue_item)
            CopyVenueEvents(venue_take, sub_take, sub_item, function(msg)
                return CategorizeVenueEvent(msg) == 'coop'
            end)

            local n = CountTextEvts(sub_take)
            local found_t
            for i = 0, n - 1 do
                local ok, _, _, ppq, evtype = r.MIDI_GetTextSysexEvt(sub_take, i)
                if ok and evtype == 1 then found_t = r.MIDI_GetProjTimeFromPPQPos(sub_take, ppq) end
            end
            Test.expect(n == 1, 'exactly one event copied')
            Test.expect(found_t and math.abs(found_t - 6.5) < 0.01,
                        'project time preserved through the bridge, got ' .. tostring(found_t))
        end, 10, false, 5)
    end)

    Test.it('EnsureMatchingItem re-syncs both position and length on later calls', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            local sub_track = FindOrCreateSubtrack(VENUE_SUBTRACKS[1], venue_track, venue_track)
            EnsureMatchingItem(sub_track, venue_item)

            r.SetMediaItemInfo_Value(venue_item, 'D_POSITION', 3)
            r.SetMediaItemInfo_Value(venue_item, 'D_LENGTH', 20)

            local sub_item = EnsureMatchingItem(sub_track, venue_item)
            Test.expect(math.abs(r.GetMediaItemInfo_Value(sub_item, 'D_POSITION') - 3) < 1e-6,
                        'subtrack item position re-synced')
            Test.expect(math.abs(r.GetMediaItemInfo_Value(sub_item, 'D_LENGTH') - 20) < 1e-6,
                        'subtrack item length re-synced')
        end, 10)
    end)

    Test.it('EnsureMatchingItem clears events regardless of a prior resize (full-take clear)', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            local sub_track = FindOrCreateSubtrack(VENUE_SUBTRACKS[1], venue_track, venue_track)
            local sub_item, sub_take = EnsureMatchingItem(sub_track, venue_item)
            InsertEvt(sub_take, 8, '[coop_all_far]')  -- near the end of a 10s item

            -- Shrink then grow back - a range-scoped clear keyed off "current" bounds could
            -- miss this event while the item was shrunk.
            r.SetMediaItemInfo_Value(sub_item, 'D_LENGTH', 2)
            r.SetMediaItemInfo_Value(sub_item, 'D_LENGTH', 10)

            EnsureMatchingItem(sub_track, venue_item)
            Test.expect(CountTextEvts(sub_take) == 0,
                        'stray event cleared despite the resize round-trip')
        end, 10)
    end)

    ------------------------------------------------------------------
    Test.section('CopyAllSubtracksToMain (bulk merge)')
    ------------------------------------------------------------------

    Test.it('combines all subtracks into VENUE, preserves the track-name event', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            r.MIDI_InsertTextSysexEvt(venue_take, false, false, 0, 3, 'VENUE', false)
            InsertEvt(venue_take, 1, '[coop_all_far]')
            InsertEvt(venue_take, 2, '[directed_all]')
            InsertEvt(venue_take, 3, '[lighting (loop_warm)]')
            InsertEvt(venue_take, 4, '[first]')
            InsertEvt(venue_take, 5, '[ProFilm_a.pp]')
            InsertEvt(venue_take, 6, '[bonusfx]')

            CopyVenueToSubtracks()
            CopyAllSubtracksToMain(true)

            local n = CountTextEvts(venue_take)
            local name_ok = false
            for i = 0, n - 1 do
                local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(venue_take, i)
                if ok and evtype == 3 and msg == 'VENUE' and ppq == 0 then name_ok = true end
            end
            Test.expect(name_ok, 'track-name (type 3) event survives the clear+merge')

            local msgs = ReadMsgs(venue_take)
            table.sort(msgs)
            local expect = { '[ProFilm_a.pp]', '[bonusfx]', '[coop_all_far]',
                              '[directed_all]', '[first]', '[lighting (loop_warm)]' }
            table.sort(expect)
            Test.expect(#msgs == #expect, ('got %d events, want %d'):format(#msgs, #expect))
            for i = 1, #expect do
                Test.expect(msgs[i] == expect[i], 'event ' .. i .. ': got ' .. tostring(msgs[i]))
            end
        end, 10)
    end)

    Test.it('uses only the subtracks that exist, reports the rest as missing', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 1, '[coop_all_far]')
            CopyVenueToSubtracks()

            for i = 4, 6 do
                local tr = FindTrackByName(VENUE_SUBTRACKS[i].track_name)
                r.DeleteTrack(tr)
            end

            CopyAllSubtracksToMain(true)
            Test.expect(S.last_result:find('Missing subtracks', 1, true),
                        'reports missing subtracks: ' .. tostring(S.last_result))
            local msgs = ReadMsgs(venue_take)
            Test.expect(#msgs == 1 and msgs[1] == '[coop_all_far]',
                        'only the surviving subtrack merged in')
        end, 10)
    end)

    Test.it('early-exits with a status message when no subtracks exist at all', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 1, '[coop_all_far]')  -- must survive untouched

            for _, cat in ipairs(VENUE_SUBTRACKS) do
                Test.expect(not FindTrackByName(cat.track_name), cat.track_name .. ' absent before test')
            end

            S.status = ''
            CopyAllSubtracksToMain(false)
            Test.expect(S.status == 'No VENUE subtracks found.', 'status: ' .. tostring(S.status))
            Test.expect(S.last_result:find('Copy all to subtracks', 1, true),
                        'result points at Copy all to subtracks: ' .. tostring(S.last_result))
            local msgs = ReadMsgs(venue_take)
            Test.expect(#msgs == 1 and msgs[1] == '[coop_all_far]', 'VENUE left untouched')
        end, 10)
    end)

    Test.it('MIDI notes round-trip through VENUE special (bulk split + merge)', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            r.MIDI_InsertNote(venue_take, false, false,
                r.MIDI_GetPPQPosFromProjTime(venue_take, 2),
                r.MIDI_GetPPQPosFromProjTime(venue_take, 3), 0, 85, 100, false)

            CopyVenueToSubtracks()
            local _, _, special_take = FindNamedTrackMIDI('VENUE special')
            local _, note_n = r.MIDI_CountEvts(special_take)
            Test.expect(note_n == 1, 'note copied to VENUE special, got ' .. tostring(note_n))
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(special_take, 0)
            Test.expect(ok and pitch == 85, 'copied note is pitch 85')
            Test.expect(math.abs(r.MIDI_GetProjTimeFromPPQPos(special_take, sppq) - 2) < 0.01,
                        'copied note start time preserved')

            -- Change the note on the subtrack, then merge back - VENUE's own copy must be
            -- replaced, not duplicated alongside it.
            r.MIDI_DeleteNote(special_take, 0)
            r.MIDI_InsertNote(special_take, false, false,
                r.MIDI_GetPPQPosFromProjTime(special_take, 4),
                r.MIDI_GetPPQPosFromProjTime(special_take, 5), 0, 86, 100, false)

            CopyAllSubtracksToMain(true)
            local _, venue_note_n = r.MIDI_CountEvts(venue_take)
            Test.expect(venue_note_n == 1, 'exactly one note on VENUE after merge, got ' .. tostring(venue_note_n))
            local ok2, _, _, sppq2, _, _, pitch2 = r.MIDI_GetNote(venue_take, 0)
            Test.expect(ok2 and pitch2 == 86, 'VENUE note replaced with the edited one (pitch 86)')
            Test.expect(math.abs(r.MIDI_GetProjTimeFromPPQPos(venue_take, sppq2) - 4) < 0.01,
                        'merged note start time preserved')
        end, 10)
    end)

    ------------------------------------------------------------------
    Test.section('CopySelectedSubtrackTo / CopySelectedSubtrackFrom (single subtrack)')
    ------------------------------------------------------------------

    Test.it('Copy to auto-creates a missing subtrack; Copy from does not', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 1, '[coop_all_far]')

            S.venue_subtrack_idx = 0  -- Normal camera (coop)
            Test.expect(not FindTrackByName('VENUE normal camera'), 'subtrack absent before test')
            CopySelectedSubtrackTo()
            Test.expect(FindTrackByName('VENUE normal camera'), 'Copy to auto-created the subtrack')

            S.venue_subtrack_idx = 1  -- Directed camera - still missing
            S.status = ''
            CopySelectedSubtrackFrom()
            Test.expect(not FindTrackByName('VENUE directed camera'),
                        'Copy from did not auto-create the missing subtrack')
            Test.expect(S.status:find('No "VENUE directed camera" subtrack found', 1, true),
                        'status: ' .. tostring(S.status))
        end, 10)
    end)

    Test.it('Copy from clears only its own category on VENUE, leaves other categories alone', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            InsertEvt(venue_take, 1, '[coop_all_far]')            -- stale coop event
            InsertEvt(venue_take, 2, '[lighting (loop_warm)]')    -- unrelated, must survive

            S.venue_subtrack_idx = 0  -- Normal camera (coop)
            CopySelectedSubtrackTo()  -- subtrack now has [coop_all_far]

            local _, _, coop_take = FindNamedTrackMIDI('VENUE normal camera')
            local _, _, _, n = r.MIDI_CountEvts(coop_take)
            for i = n - 1, 0, -1 do r.MIDI_DeleteTextSysexEvt(coop_take, i) end
            InsertEvt(coop_take, 1, '[coop_all_near]')  -- swap in a different coop event

            CopySelectedSubtrackFrom()

            local msgs = ReadMsgs(venue_take)
            local has_new_coop, has_lighting, has_old_coop = false, false, false
            for _, m in ipairs(msgs) do
                if m == '[coop_all_near]'        then has_new_coop  = true end
                if m == '[lighting (loop_warm)]' then has_lighting  = true end
                if m == '[coop_all_far]'         then has_old_coop  = true end
            end
            Test.expect(#msgs == 2, ('got %d events'):format(#msgs))
            Test.expect(has_new_coop, 'new coop event copied in')
            Test.expect(has_lighting, 'unrelated lighting event untouched')
            Test.expect(not has_old_coop, 'old coop event replaced, not left behind')
        end, 10)
    end)

    Test.it('MIDI notes round-trip through VENUE special (single Copy to / Copy from)', function()
        WithVenueFixture(function(venue_track, venue_item, venue_take)
            r.MIDI_InsertNote(venue_take, false, false,
                r.MIDI_GetPPQPosFromProjTime(venue_take, 2),
                r.MIDI_GetPPQPosFromProjTime(venue_take, 3), 0, 87, 100, false)

            S.venue_subtrack_idx = 5  -- Special
            CopySelectedSubtrackTo()

            local _, _, special_take = FindNamedTrackMIDI('VENUE special')
            local _, note_n = r.MIDI_CountEvts(special_take)
            Test.expect(note_n == 1, 'note copied to VENUE special via single Copy to')

            r.MIDI_DeleteNote(special_take, 0)
            r.MIDI_InsertNote(special_take, false, false,
                r.MIDI_GetPPQPosFromProjTime(special_take, 6),
                r.MIDI_GetPPQPosFromProjTime(special_take, 7), 0, 85, 100, false)

            CopySelectedSubtrackFrom()

            local _, venue_note_n = r.MIDI_CountEvts(venue_take)
            Test.expect(venue_note_n == 1, 'exactly one note on VENUE after Copy from, got '
                        .. tostring(venue_note_n))
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(venue_take, 0)
            Test.expect(ok and pitch == 85, 'VENUE note replaced with the edited one (pitch 85)')
            Test.expect(math.abs(r.MIDI_GetProjTimeFromPPQPos(venue_take, sppq) - 6) < 0.01,
                        'merged note start time preserved')
        end, 10)
    end)

    ------------------------------------------------------------------
    Test.section('Missing VENUE track/item guards')
    ------------------------------------------------------------------

    Test.it('all 4 public actions set a status message and do nothing without a VENUE track', function()
        Test.expect(not FindTrackByName('VENUE'), 'no VENUE track before test')

        S.status = ''; CopyVenueToSubtracks()
        Test.expect(S.status == 'No VENUE track found.', 'CopyVenueToSubtracks: ' .. tostring(S.status))

        S.status = ''; CopyAllSubtracksToMain(false)
        Test.expect(S.status == 'No VENUE track found.', 'CopyAllSubtracksToMain: ' .. tostring(S.status))

        S.venue_subtrack_idx = 0
        S.status = ''; CopySelectedSubtrackTo()
        Test.expect(S.status == 'No VENUE track found.', 'CopySelectedSubtrackTo: ' .. tostring(S.status))

        S.status = ''; CopySelectedSubtrackFrom()
        Test.expect(S.status == 'No VENUE track found.', 'CopySelectedSubtrackFrom: ' .. tostring(S.status))
    end)

    ------------------------------------------------------------------
    Test.section('RemoveVenueEventsByType (post-refactor regression, actions_venue_manual.lua)')
    ------------------------------------------------------------------

    Test.it('removes exactly the expected category per remove_type; All removes everything', function()
        -- Guard against an active time selection in the host project affecting the range.
        local sel_s0, sel_e0 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        r.GetSet_LoopTimeRange(true, false, 0, 0, false)

        local function seed(take)
            InsertEvt(take, 1, '[coop_all_far]')
            InsertEvt(take, 2, '[directed_all]')
            InsertEvt(take, 3, '[lighting (loop_warm)]')
            InsertEvt(take, 4, '[ProFilm_a.pp]')
            InsertEvt(take, 5, '[bonusfx]')
            InsertEvt(take, 6, '[first]')
            InsertEvt(take, 7, '[totally_unknown]')
        end

        local ok, err = pcall(function()
            WithVenueFixture(function(_, _, venue_take)
                seed(venue_take)
                RemoveVenueEventsByType(0)  -- Camera: coop + directed
                Test.expect(#ReadMsgs(venue_take) == 5, 'Camera')
            end, 10)

            WithVenueFixture(function(_, _, venue_take)
                seed(venue_take)
                RemoveVenueEventsByType(1)  -- Lighting
                Test.expect(#ReadMsgs(venue_take) == 6, 'Lighting')
            end, 10)

            WithVenueFixture(function(_, _, venue_take)
                seed(venue_take)
                RemoveVenueEventsByType(2)  -- Post proc
                Test.expect(#ReadMsgs(venue_take) == 6, 'Post proc')
            end, 10)

            WithVenueFixture(function(_, _, venue_take)
                seed(venue_take)
                RemoveVenueEventsByType(3)  -- Special: bonusfx + keyframe + unrecognized
                Test.expect(#ReadMsgs(venue_take) == 4, 'Special')
            end, 10)

            WithVenueFixture(function(_, _, venue_take)
                seed(venue_take)
                RemoveVenueEventsByType(4)  -- All
                Test.expect(#ReadMsgs(venue_take) == 0, 'All')
            end, 10)
        end)

        r.GetSet_LoopTimeRange(true, false, sel_s0, sel_e0, false)
        if not ok then error(err, 2) end
    end)

    ------------------------------------------------------------------
    Test.section('FindManualLightingAtPpq / [first] gating (actions_venue_manual.lua)')
    ------------------------------------------------------------------

    Test.it('matches only a MANUAL lighting event, on or within tolerance of the tick', function()
        WithVenueFixture(function(_, _, take)
            local ppq = GetTakePPQPerQN(take)
            InsertEvt(take, 1, '[lighting (stomp)]')       -- manual
            InsertEvt(take, 3, '[lighting (loop_warm)]')   -- auto: needs no keyframes
            InsertEvt(take, 5, '[coop_all_far]')
            local p = function(t) return r.MIDI_GetPPQPosFromProjTime(take, t) end

            Test.expect(FindManualLightingAtPpq(take, p(1)) == '[lighting (stomp)]',
                'exact tick should match the manual lighting event')
            Test.expect(FindManualLightingAtPpq(take, p(1) + math.floor(ppq / 64)) ~= nil,
                'a tick inside the tolerance window should still match')
            Test.expect(FindManualLightingAtPpq(take, p(1) + ppq) == nil,
                'a whole beat away is outside the tolerance window')
            Test.expect(FindManualLightingAtPpq(take, p(3)) == nil,
                'an auto lighting preset drives no keyframes and must not match')
            Test.expect(FindManualLightingAtPpq(take, p(5)) == nil, 'camera event must not match')
            Test.expect(FindManualLightingAtPpq(take, p(8)) == nil, 'empty spot must not match')
        end, 10)
    end)

    Test.it('RegenerateVenueKeyframes: a restatement starts no span and ends none', function()
        -- Guard against an active time selection in the host project affecting the range.
        local sel_s0, sel_e0 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        r.GetSet_LoopTimeRange(true, false, 0, 0, false)

        local ok, err = pcall(function()
            WithVenueFixture(function(_, _, take)
                local ppq = GetTakePPQPerQN(take)
                local qn  = function(n)
                    return r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap_QNToTime(n))
                end
                local function InsertAtQN(n, msg)
                    r.MIDI_InsertTextSysexEvt(take, false, false, qn(n), 1, msg, false)
                end
                -- stomp at QN 4, its blend-in restatement a beat before the real change
                -- to verse at QN 20.
                InsertAtQN(4,  '[lighting (stomp)]')
                InsertAtQN(19, '[lighting (stomp)]')
                InsertAtQN(20, '[lighting (verse)]')

                local align0, rate0 = S.venue_keyframe_align, S.venue_kf_rate
                S.venue_keyframe_align = 0
                S.venue_kf_rate        = 4
                RegenerateVenueKeyframes()
                S.venue_keyframe_align, S.venue_kf_rate = align0, rate0
                Test.expect(S.status:find('Regenerated'),
                    'expected a regenerated report, got: ' .. S.status)

                -- Collect the regenerated keyframes by position.
                local firsts, nexts = {}, {}
                local _, _, _, n = r.MIDI_CountEvts(take)
                for i = 0, n - 1 do
                    local o, _, _, p, ty, msg = r.MIDI_GetTextSysexEvt(take, i)
                    if o and ty == 1 then
                        if msg == '[first]' then firsts[p] = true
                        elseif msg == '[next]' then nexts[p] = true end
                    end
                end

                Test.expect(firsts[qn(4)], 'the stomp that changed the preset needs a [first]')
                Test.expect(not firsts[qn(19)],
                    'the restatement must not start a second sequence')
                Test.expect(firsts[qn(20)], 'the change to verse needs a [first]')
                -- The first span runs through its own restatement to the real change,
                -- so at rate 4 it puts a [next] on QN 8/12/16 - past QN 19 would be
                -- QN 20, which is the span end.
                Test.expect(nexts[qn(16)],
                    "the first span's train should run past its restatement")
            end, 30)
        end)

        r.GetSet_LoopTimeRange(true, false, sel_s0, sel_e0, false)
        if not ok then error(err, 2) end
    end)

    Test.it('BlendVenuePresetAtPlayhead copies the active preset, then refuses a second time', function()
        WithVenueFixture(function(_, _, take)
            local cur0 = r.GetCursorPosition()
            local ok, err = pcall(function()
                InsertEvt(take, 1, '[lighting (stomp)]')
                InsertEvt(take, 3, '[lighting (verse)]')
                InsertEvt(take, 2, '[ProFilm_a.pp]')

                r.SetEditCurPos(6, false, false)
                BlendVenuePresetAtPlayhead('lighting')

                Test.expect(#ReadMsgs(take) == 4, 'expected one event inserted')
                Test.expect(S.last_result and S.last_result:find('%[lighting %(verse%)%]'),
                    'the report should name the copied event: ' .. tostring(S.last_result))
                local at_cur = 0
                local p = r.MIDI_GetPPQPosFromProjTime(take, 6)
                local _, _, _, n = r.MIDI_CountEvts(take)
                for i = 0, n - 1 do
                    local o, _, _, evp, ty, msg = r.MIDI_GetTextSysexEvt(take, i)
                    if o and ty == 1 and msg == '[lighting (verse)]'
                            and math.abs(evp - p) < 2 then
                        at_cur = at_cur + 1
                    end
                end
                Test.expect(at_cur == 1, 'the copy should sit on the playhead')

                -- The last two lighting events now match: a blend is already in place.
                r.SetEditCurPos(8, false, false)
                BlendVenuePresetAtPlayhead('lighting')
                Test.expect(#ReadMsgs(take) == 4, 'a refusal must insert nothing')
                Test.expect(S.status:find('Already blended'),
                    'expected the blended refusal, got: ' .. S.status)
            end)
            r.SetEditCurPos(cur0, false, false)
            if not ok then error(err, 2) end
        end, 10)
    end)

    Test.it('Blend keeps lighting and post-process separate', function()
        WithVenueFixture(function(_, _, take)
            local cur0 = r.GetCursorPosition()
            local ok, err = pcall(function()
                InsertEvt(take, 1, '[lighting (stomp)]')
                InsertEvt(take, 2, '[ProFilm_a.pp]')
                InsertEvt(take, 3, '[ProFilm_b.pp]')

                r.SetEditCurPos(6, false, false)
                BlendVenuePresetAtPlayhead('postproc')
                Test.expect(S.last_result and S.last_result:find('ProFilm_b%.pp'),
                    'postproc blend must copy the .pp event, got: ' .. tostring(S.last_result))

                -- Only one lighting event exists - copied, with nothing to compare.
                r.SetEditCurPos(7, false, false)
                BlendVenuePresetAtPlayhead('lighting')
                Test.expect(S.last_result:find('%[lighting %(stomp%)%]'),
                    'lighting blend must ignore the .pp events: ' .. tostring(S.last_result))
                Test.expect(S.last_result:find('only'),
                    'expected the single-event note in the report')
            end)
            r.SetEditCurPos(cur0, false, false)
            if not ok then error(err, 2) end
        end, 10)
    end)

    Test.it('Blend refuses on an occupied spot and with nothing before the playhead', function()
        WithVenueFixture(function(_, _, take)
            local cur0 = r.GetCursorPosition()
            local ok, err = pcall(function()
                InsertEvt(take, 5, '[lighting (stomp)]')

                r.SetEditCurPos(5, false, false)          -- right on the event
                BlendVenuePresetAtPlayhead('lighting')
                Test.expect(#ReadMsgs(take) == 1, 'occupied refusal must insert nothing')
                Test.expect(S.status:find('already at the playhead'),
                    'expected the occupied refusal, got: ' .. S.status)

                r.SetEditCurPos(2, false, false)          -- before every lighting event
                BlendVenuePresetAtPlayhead('lighting')
                Test.expect(#ReadMsgs(take) == 1, 'empty refusal must insert nothing')
                Test.expect(S.status:find('nothing to blend from'),
                    'expected the none refusal, got: ' .. S.status)
            end)
            r.SetEditCurPos(cur0, false, false)
            if not ok then error(err, 2) end
        end, 10)
    end)

    Test.it('FindActiveVenuePresetsBefore returns the nearest preceding lighting + postproc', function()
        WithVenueFixture(function(_, _, take)
            InsertEvt(take, 1, '[lighting (stomp)]')
            InsertEvt(take, 2, '[ProFilm_a.pp]')
            InsertEvt(take, 3, '[lighting (verse)]')
            InsertEvt(take, 4, '[coop_all_far]')     -- must be ignored
            local p = function(t) return r.MIDI_GetPPQPosFromProjTime(take, t) end

            local lt, lt_ppq, pp, pp_ppq = FindActiveVenuePresetsBefore(take, p(5))
            Test.expect(lt == '[lighting (verse)]', 'expected the LAST lighting, got ' .. tostring(lt))
            Test.expect(lt_ppq == p(3), 'wrong lighting position')
            Test.expect(pp == '[ProFilm_a.pp]', 'expected the postproc, got ' .. tostring(pp))
            Test.expect(pp_ppq == p(2), 'wrong postproc position')

            -- Strictly before: an event exactly at the query point does not count.
            lt = FindActiveVenuePresetsBefore(take, p(3))
            Test.expect(lt == '[lighting (stomp)]',
                'expected the earlier lighting, got ' .. tostring(lt))

            local n_lt, _, n_pp = FindActiveVenuePresetsBefore(take, p(0.5))
            Test.expect(n_lt == nil and n_pp == nil, 'nothing precedes the start')
        end, 10)
    end)

    Test.it('InsertVenueEventAtPlayhead refuses a [first] with no lighting event under it', function()
        WithVenueFixture(function(_, _, take)
            local cur0 = r.GetCursorPosition()
            local ok, err = pcall(function()
                InsertEvt(take, 1, '[lighting (stomp)]')

                r.SetEditCurPos(8, false, false)          -- bare spot
                S.status = 'Ready.'
                InsertVenueEventAtPlayhead('[first]')
                Test.expect(#ReadMsgs(take) == 1, 'nothing should have been inserted')
                Test.expect(S.status == NO_LIGHTING_AT_PLAYHEAD_MSG,
                    'expected the shared refusal message, got: ' .. tostring(S.status))

                r.SetEditCurPos(1, false, false)          -- on the lighting event
                InsertVenueEventAtPlayhead('[first]')
                Test.expect(#ReadMsgs(take) == 2, '[first] should be allowed on the lighting tick')

                -- Other special events are never gated by this rule.
                r.SetEditCurPos(8, false, false)
                InsertVenueEventAtPlayhead('[next]')
                Test.expect(#ReadMsgs(take) == 3, '[next] must remain insertable anywhere')
            end)
            r.SetEditCurPos(cur0, false, false)
            if not ok then error(err, 2) end
        end, 10)
    end)

end
