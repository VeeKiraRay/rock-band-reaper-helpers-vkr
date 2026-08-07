-- @description Rock Band Music Theory Helper - Guitar Theory Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for lib/reaper_guitar_theory.lua: fret parsing,
--   chord-shape classification, and RB lane-combo suggestion. Also
--   round-trips the Music Theory helper's shipped GUITAR_CHORDS reference
--   table through the classifier, so its shapes and labels are checked
--   against live behaviour rather than trusted. Pure - the two files loaded
--   below make no REAPER API calls. Run from the REAPER Actions list or
--   triggered via the test launcher. Results appear in the REAPER console
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
r.ShowConsoleMsg('======  Guitar Theory - algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_guitar_theory.lua')
-- GUITAR_CHORDS / GUITAR_CHORD_TYPES, round-tripped by the chord section.
-- Defines globals only (S, TIPS, the reference tables) and calls no REAPER
-- API at load time, so it is safe to pull in here; nothing in this suite
-- uses the S/TIPS it also sets.
dofile(_root .. 'rock_band_music_theory_helper_vkr/defaults.lua')

dofile(_tdir .. 'guitar_theory.lua')
Test.report()
