-- Smoke tests for every public action in the Vocal Helper.
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
    S.lyrics_path = ''
    S.status      = 'Ready.'
    S.last_result = nil
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

Test.section('Detection')
smoke('Preview',                 function() Preview() end)
smoke('Generate (append)',       function() Generate() end)
smoke('Generate (replace)',      function() Generate(true) end)
smoke('RunAutoTune',             function() RunAutoTune() end)
smoke('RunAutoTuneYIN',          function() RunAutoTuneYIN() end)
smoke('ApplyPitchChangesAction', function() ApplyPitchChangesAction() end)
smoke('SnapDraft',               function() SnapDraft() end)

Test.section('Pitch Slide / Snap')
smoke('ScanPitchSlidesAction', function() ScanPitchSlidesAction() end)
smoke('SnapToKeyAction',       function() SnapToKeyAction() end)

Test.section('Lyrics')
smoke('ClearLyricsAction',  function() ClearLyricsAction() end)
smoke('AssignLyricsAction', function() AssignLyricsAction() end)

Test.section('Harmonies')
smoke('HarmoniesAction', function() HarmoniesAction() end)

Test.section('Validation')
smoke('ValidatePhrases',        function() ValidatePhrases() end)
smoke('PhraseSimilarityAction', function() PhraseSimilarityAction() end)
