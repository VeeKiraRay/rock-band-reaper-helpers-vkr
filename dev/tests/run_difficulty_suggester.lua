-- @description Rock Band General Helper - Difficulty Suggester Tests
-- @author VeeKiraRay
-- @about
--   Tests for the shipped difficulty suggester:
--     lib/reaper_difficulty_tiers.lua    - rank to tier, tier bands, position in band,
--       re-asserted against _external_docs/InstrumentDifficulty.ts rather than trusting
--       the transcription.
--     lib/reaper_difficulty_predict.lua  - standardization, scale inversion, rank
--       clamping, out-of-range detection, factor z-scores.
--     lib/reaper_difficulty_models.lua   - the frozen artifact: schema, shape, and the
--       candidate each instrument actually selected.
--   Plus PARITY: each model is refit from dev/calibration/corpus_scores.csv at its own
--   recorded ridge and compared coefficient by coefficient, then applied to every
--   development row. That is what establishes the number shown to an author is really
--   the model the locked protocol selected.
--
--   Pure - no project, item, or MIDI editor. Run from the REAPER Actions list or the
--   test launcher. Results appear in the REAPER console (View > Show REAPER console).
--
--   Run from the repo checkout: the parity section reads the calibration CSV, which is
--   not deployed. It fails loudly rather than silently skipping if the CSV is absent.

r = reaper

local _ctx_script = ({reaper.get_action_context()})[2]
local _ctx_dir    = _ctx_script:match('^(.+[\\/])')
local _in_dev_tests = _ctx_dir:lower():find('[/\\]dev[/\\]tests[/\\]$')
local _in_dev       = _ctx_dir:lower():find('[/\\]dev[/\\]$')
local function _strip(d)
    return (d:match('^(.+)[/\\]+$') or d):match('^(.+[/\\])') or d
end
local _root = _in_dev_tests and _strip(_strip(_ctx_dir))
           or _in_dev       and _strip(_ctx_dir)
           or _ctx_dir
local _tdir = _root .. 'dev/tests/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty suggester - unit tests  ======\n')

dofile(_tdir .. 'framework.lua')

-- Production modules under test.
dofile(_root .. 'lib/reaper_difficulty_score.lua')          -- SCORE_FACTOR_KEYS
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')   -- appends the vocal columns
dofile(_root .. 'lib/reaper_difficulty_tiers.lua')
dofile(_root .. 'lib/reaper_difficulty_predict.lua')
dofile(_root .. 'lib/reaper_difficulty_models.lua')
-- Pure (no r/S/ctx), so they load here without the rest of the helper's chain.
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_explain.lua')
dofile(_root .. 'rock_band_general_helper_vkr/difficulty_report.lua')

-- Calibration-side pieces the parity section needs: the ridge fit it refits with, the
-- disputed-label rule that defines the training partition, and PROTOCOL.LEGO_WEIGHT.
dofile(_root .. 'dev/calibration/stats.lua')
dofile(_root .. 'dev/calibration/weirdly_scored.lua')
dofile(_root .. 'dev/calibration/protocol.lua')

dofile(_tdir .. 'difficulty_suggester.lua')
Test.report()
