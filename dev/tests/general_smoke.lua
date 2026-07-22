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
smoke('CopyProKeysDiff H',     function() CopyProKeysDiff('H') end)
smoke('CopyProKeysDiff M',     function() CopyProKeysDiff('M') end)
smoke('CopyProKeysDiff E',     function() CopyProKeysDiff('E') end)
smoke('ValidateProKeysDiff X', function() ValidateProKeysDiff('X') end)
smoke('ValidateProKeysDiff H', function() ValidateProKeysDiff('H') end)
smoke('ValidateProKeysDiff M', function() ValidateProKeysDiff('M') end)
smoke('ValidateProKeysDiff E', function() ValidateProKeysDiff('E') end)
smoke('ValidateAllProKeys',    function() ValidateAllProKeys() end)

Test.section('Difficulty — 5-Lane Keys')
smoke('CopyKeys5Diff H',     function() CopyKeys5Diff('H') end)
smoke('CopyKeys5Diff M',     function() CopyKeys5Diff('M') end)
smoke('CopyKeys5Diff E',     function() CopyKeys5Diff('E') end)
smoke('ValidateKeys5Diff X', function() ValidateKeys5Diff('X') end)
smoke('ValidateKeys5Diff H', function() ValidateKeys5Diff('H') end)
smoke('ValidateKeys5Diff M', function() ValidateKeys5Diff('M') end)
smoke('ValidateKeys5Diff E', function() ValidateKeys5Diff('E') end)
smoke('ValidateAllKeys5',    function() ValidateAllKeys5() end)

Test.section('Difficulty — Guitar/Bass')
smoke('CopyGtrBassDiff gtr H',      function() CopyGtrBassDiff('gtr', 'H') end)
smoke('CopyGtrBassDiff gtr M',      function() CopyGtrBassDiff('gtr', 'M') end)
smoke('CopyGtrBassDiff gtr E',      function() CopyGtrBassDiff('gtr', 'E') end)
smoke('ValidateGtrBassDiff gtr X',  function() ValidateGtrBassDiff('gtr', 'X') end)
smoke('ValidateGtrBassDiff gtr H',  function() ValidateGtrBassDiff('gtr', 'H') end)
smoke('ValidateGtrBassDiff gtr M',  function() ValidateGtrBassDiff('gtr', 'M') end)
smoke('ValidateGtrBassDiff gtr E',  function() ValidateGtrBassDiff('gtr', 'E') end)
smoke('ValidateAllGtrBass gtr',     function() ValidateAllGtrBass('gtr') end)
smoke('CopyGtrBassDiff bass H',     function() CopyGtrBassDiff('bass', 'H') end)
smoke('ValidateGtrBassDiff bass X', function() ValidateGtrBassDiff('bass', 'X') end)
smoke('ValidateAllGtrBass bass',    function() ValidateAllGtrBass('bass') end)

Test.section('Difficulty — Drums')
smoke('CopyDrumsDiff H',     function() CopyDrumsDiff('H') end)
smoke('CopyDrumsDiff M',     function() CopyDrumsDiff('M') end)
smoke('CopyDrumsDiff E',     function() CopyDrumsDiff('E') end)
smoke('ValidateDrumsDiff X', function() ValidateDrumsDiff('X') end)
smoke('ValidateDrumsDiff H', function() ValidateDrumsDiff('H') end)
smoke('ValidateDrumsDiff M', function() ValidateDrumsDiff('M') end)
smoke('ValidateDrumsDiff E', function() ValidateDrumsDiff('E') end)
smoke('ValidateAllDrums',    function() ValidateAllDrums() end)

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
