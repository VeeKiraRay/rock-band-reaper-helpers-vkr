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

Test.section('Tempo Map')
smoke('ShowTempoContext',           function() ShowTempoContext() end)
smoke('AlignAudioTracks',           function() AlignAudioTracks() end)
smoke('EstimateInitialBPM',         function() EstimateInitialBPM() end)
smoke('GenerateTempoMap',           function() GenerateTempoMap() end)
smoke('ClearGeneratedTempoMarkers', function() ClearGeneratedTempoMarkers() end)
smoke('ConvertTimeSig6to3',         function() ConvertTimeSig6to3() end)

Test.section('Drums')
smoke('ConvertDrums', function() ConvertDrums() end)

Test.section('Keys')
smoke('SplitHands',           function() SplitHands() end)
smoke('ConvertPianoToProKeys', function() ConvertPianoToProKeys() end)
smoke('ConvertProKeys',        function() ConvertProKeys() end)
smoke('ConvertKeys5',          function() ConvertKeys5() end)

Test.section('Guitar')
smoke('ConvertGuitar',  function() ConvertGuitar() end)
smoke('GuitarTabGuide', function() GuitarTabGuide() end)
smoke('ValidateGuitar', function() ValidateGuitar() end)

Test.section('Difficulty — Pro Keys')
smoke('SuggestProKeysDiff H',  function() SuggestProKeysDiff('H') end)
smoke('SuggestProKeysDiff M',  function() SuggestProKeysDiff('M') end)
smoke('SuggestProKeysDiff E',  function() SuggestProKeysDiff('E') end)
smoke('ValidateProKeysDiff X', function() ValidateProKeysDiff('X') end)
smoke('ValidateProKeysDiff H', function() ValidateProKeysDiff('H') end)
smoke('ValidateProKeysDiff M', function() ValidateProKeysDiff('M') end)
smoke('ValidateProKeysDiff E', function() ValidateProKeysDiff('E') end)
smoke('ValidateAllProKeys',    function() ValidateAllProKeys() end)

Test.section('Difficulty — 5-Lane Keys')
smoke('SuggestKeys5Diff H',  function() SuggestKeys5Diff('H') end)
smoke('SuggestKeys5Diff M',  function() SuggestKeys5Diff('M') end)
smoke('SuggestKeys5Diff E',  function() SuggestKeys5Diff('E') end)
smoke('ValidateKeys5Diff X', function() ValidateKeys5Diff('X') end)
smoke('ValidateKeys5Diff H', function() ValidateKeys5Diff('H') end)
smoke('ValidateKeys5Diff M', function() ValidateKeys5Diff('M') end)
smoke('ValidateKeys5Diff E', function() ValidateKeys5Diff('E') end)
smoke('ValidateAllKeys5',    function() ValidateAllKeys5() end)

Test.section('MIDI')
smoke('AlignMIDI',           function() AlignMIDI() end)
smoke('ResizeAllMIDI',       function() ResizeAllMIDI() end)
smoke('SetSearchPattern',    function() SetSearchPattern() end)
smoke('SetReplacePattern',   function() SetReplacePattern() end)
smoke('DoMIDIPatternReplace', function() DoMIDIPatternReplace() end)
smoke('FillRange',           function() FillRange() end)

Test.section('Venue')
smoke('ListVenueEvents',    function() ListVenueEvents() end)
smoke('ListLightingPostProcEvents', function() ListLightingPostProcEvents() end)
smoke('ListEventSections',  function() ListEventSections() end)
smoke('LoadVenueSections',  function() LoadVenueSections() end)
smoke('GenerateVenueEvents', function() GenerateVenueEvents() end)
smoke('GenerateSectionEvent', function() GenerateSectionEvent() end)
