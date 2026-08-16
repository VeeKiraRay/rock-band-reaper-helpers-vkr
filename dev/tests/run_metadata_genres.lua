-- @description Rock Band Metadata Genres - Tests
-- @author VeeKiraRay
-- @about
--   Tests for the Metadata > Genre converter: the supported vocabulary
--   transcribed from the RBN/C3 Subgenre Descriptions page
--   (metadata_genres.lua), the authored extended vocabulary and its mapping
--   onto that list (metadata_genres_ext.lua), and the lookup over both
--   (metadata_genres_lookup.lua). Run from the REAPER Actions list for a fully
--   isolated Lua context, or via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console.
--
--   Everything here is pure - no project fixture, no tracks, nothing to clean
--   up, and no UI. ctx stays nil throughout, which also proves the three
--   modules do no ImGui work at load time.

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
local _mdir = _root .. 'rock_band_general_helper_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Metadata Genres - tests  ======\n')

dofile(_tdir .. 'framework.lua')

-- Code under test, in the same order the entry point loads it.
dofile(_mdir .. 'metadata_genres.lua')
dofile(_mdir .. 'metadata_genres_ext.lua')
dofile(_mdir .. 'metadata_genres_lookup.lua')

dofile(_tdir .. 'metadata_genres.lua')
Test.report()
