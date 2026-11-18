-- Smoke tests for every public action in the General Helper.
--
-- Each test calls one action with all track indices set to an out-of-range value
-- (9999) so REAPER's GetTrack returns nil and the action exits via its normal
-- error path. The test passes if:
--   1. No Lua error is thrown (pcall succeeds) - catches "attempt to call nil value"
--      scoping regressions.
--   2. S.status was updated from 'Ready.' - confirms the action ran past reset.

local _S0 = {}
for k, v in pairs(S) do _S0[k] = v end  -- snapshot module-default state

local function reset()
    for k, v in pairs(_S0) do S[k] = v end
    for k in pairs(S) do
        if k:match('_idx$') then S[k] = 9999 end
    end
    S.status           = 'Ready.'
    S.last_result      = nil
    S.mr_search_notes  = nil   -- pattern replace: no cached search pattern
    S.mr_replace_notes = nil   -- pattern replace: no cached replace pattern
    S.venue_sections   = nil   -- venue: no cached sections
    S.venue_themes     = nil   -- venue: no cached themes
end

local function smoke(name, fn)
    Test.it(name, function()
        reset()
        fn()
        Test.expect(
            S.status ~= 'Ready.',
            'S.status was not updated (action may have returned without running)'
        )
    end)
end

Test.section('General')
smoke('AlignAllAudio',     function() AlignAllAudio() end)
smoke('AlignCountIn',      function() AlignCountIn() end)
smoke('CreateSongFadeOut', function() CreateSongFadeOut() end)

Test.section('Song fade out (envelope creation)')

-- The old bug: SONG AUDIO with no Volume envelope -> "Could not create Volume
-- envelope" (the action injected a state-chunk block, which REAPER drops).
-- Skipped when the project already has a SONG AUDIO track (the action would use it).
Test.it('CreateSongFadeOut creates the envelope on a track with an item', function()
    reset()
    if FindTrackByName('SONG AUDIO') then
        Test.expect(true, 'skipped: the project has its own SONG AUDIO track')
        return
    end
    local s0, e0 = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local idx = CreateEmptyFixtureTrack('SONG AUDIO')
    local ok, err = pcall(function()
        local track = r.GetTrack(0, idx)
        local item = r.AddMediaItemToTrack(track)
        r.SetMediaItemInfo_Value(item, 'D_POSITION', 0)
        r.SetMediaItemInfo_Value(item, 'D_LENGTH', 20)
        Test.expect(r.GetTrackEnvelopeByName(track, 'Volume') == nil, 'fixture has no envelope')
        r.GetSet_LoopTimeRange2(0, true, false, 10, 15, false)
        CreateSongFadeOut()
        local env = r.GetTrackEnvelopeByName(track, 'Volume')
        Test.expect(env ~= nil, 'envelope created, status: ' .. tostring(S.status))
        if env then
            Test.expect(r.CountEnvelopePoints(env) == 2,
                        'two fade points, got ' .. r.CountEnvelopePoints(env))
            local _, t1, v1 = r.GetEnvelopePoint(env, 0)
            local _, t2, v2 = r.GetEnvelopePoint(env, 1)
            Test.expect(math.abs(t1 - 10) < 1e-6 and math.abs(t2 - 15) < 1e-6,
                        ('points at 10 / 15 s, got %s / %s'):format(t1, t2))
            Test.expect(v1 > 0 and v2 == 0, ('fades to silence, got %s -> %s'):format(v1, v2))
        end
        Test.expect(r.CountMediaItems(0) > 0 and r.GetTrackNumMediaItems(track) == 1,
                    'the item survived the chunk rewrite')
    end)
    CleanupFixture(idx)
    r.GetSet_LoopTimeRange2(0, true, false, s0, e0, false)
    if not ok then error(err, 0) end
end)

Test.section('Tempo Map')
smoke('ShowTempoContext',           function() ShowTempoContext() end)
smoke('AlignAudioTracks',           function() AlignAudioTracks() end)
smoke('EstimateInitialBPM',         function() EstimateInitialBPM() end)
smoke('GenerateTempoMap',           function() GenerateTempoMap() end)
smoke('ClearGeneratedTempoMarkers', function() ClearGeneratedTempoMarkers() end)
smoke('ConvertTimeSig6to3',         function() ConvertTimeSig6to3() end)

Test.section('Venue')
smoke('ListVenueEvents',    function() ListVenueEvents() end)
smoke('ListLightingPostProcEvents', function() ListLightingPostProcEvents() end)
smoke('ListEventSections',  function() ListEventSections() end)
smoke('LoadVenueSections',  function() LoadVenueSections() end)
smoke('GenerateVenueEvents', function() GenerateVenueEvents() end)
smoke('GenerateSectionEvent', function() GenerateSectionEvent() end)
