-- @description Rock Band Music Theory Helper - Music Notation Unit Tests
-- @author VeeKiraRay
-- @about
--   Algorithm unit tests for lib/reaper_music_notation.lua: the diatonic
--   step model, clef anchors, key signatures and their engraved glyph
--   positions, note spelling, and piano keyboard geometry -- everything the
--   Music Theory helper's Piano tab reads a staff with. Pure; the file
--   loaded below makes no REAPER API calls. Run from the REAPER Actions list
--   or triggered via the test launcher. Results appear in the REAPER console
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
r.ShowConsoleMsg('======  Music Notation - algorithm unit tests  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_music_notation.lua')

dofile(_tdir .. 'music_notation.lua')
Test.report()
