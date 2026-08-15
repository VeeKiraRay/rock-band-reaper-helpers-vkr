-- @description Rock Band General Helper - Difficulty Calibration Unit Tests
-- @author VeeKiraRay
-- @about
--   Unit tests for the difficulty-calibration pilot's two pure modules:
--     dev/calibration/difficulty_score_vocals.lua - the vocal factor set: lyric
--       classification, pitch-CLASS intervals (an octave apart is zero distance),
--       the syllable/note-tube split, and percussion-range subtraction.
--     dev/calibration/difficulty_score.lua - the four scoring factors (average
--       density, peak density, note-change density, change tightness) plus the
--       playing-span fallback used when a track's animation states say the
--       instrument never plays.
--     dev/calibration/songs_dta.lua - songs.dta parsing, covering the shapes in
--       the real corpus files that a naive parser gets wrong (multi-song packs,
--       the (bass 5) channel-vs-rank trap, absent rank keys).
--     dev/calibration/stats.lua - Spearman/Pearson, the weighted ridge-regularized
--       fit, k-fold index generation, seeded stratified shuffles and Wilson bounds.
--     dev/calibration/protocol.lua - the selection rule's per-song residual pass
--       (rank_tiers.lua is loaded for the tier conversion it needs).
--   Both are pure and make no REAPER API calls, so these tests need no project,
--   item, or MIDI editor. Run from the REAPER Actions list or triggered via the
--   test launcher. Results appear in the REAPER console
--   (View > Show REAPER console).

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
r.ShowConsoleMsg('======  Difficulty calibration - unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'dev/calibration/difficulty_score.lua')
dofile(_root .. 'dev/calibration/difficulty_score_vocals.lua')
dofile(_root .. 'dev/calibration/songs_dta.lua')
-- stats/rank_tiers/protocol were missing here for one round, which silently failed 30
-- of the calibration_stats cases on nil globals rather than reporting a load problem.
dofile(_root .. 'dev/calibration/stats.lua')
dofile(_root .. 'dev/calibration/rank_tiers.lua')
dofile(_root .. 'dev/calibration/protocol.lua')

dofile(_tdir .. 'difficulty_score.lua')
dofile(_tdir .. 'songs_dta.lua')
dofile(_tdir .. 'calibration_stats.lua')
dofile(_tdir .. 'difficulty_score_vocals.lua')
Test.report()
