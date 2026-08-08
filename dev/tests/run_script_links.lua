-- @description Rock Band Script Links - Tests
-- @author VeeKiraRay
-- @about
--   Tests for lib/reaper_script_links.lua, the shared registry and launcher
--   behind the "General > Other tools" sub-tab: basename parsing, registry
--   shape, the registry checked both ways against the entry points actually
--   present at the install root, and the filter that hides the running
--   script's own button. Run from the REAPER Actions list for a fully
--   isolated Lua context, or via the test_rock_band_helpers_vkr launcher.
--   Results appear in the REAPER console.
--
--   Nothing here touches the project, creates tracks, or launches anything -
--   only the pure half of the module is exercised, and DrawGeneralLinksTab is
--   never called. ctx stays nil throughout, which also proves the module does
--   no ImGui or get_action_context work at load time.

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
r.ShowConsoleMsg('======  Script Links - tests  ======\n')

dofile(_tdir .. 'framework.lua')

-- The repo-scan tests need the real install root. The module resolves its own
-- lazily from get_action_context(), which here would give this runner's path -
-- so the tests are handed the root explicitly rather than reading the module's.
LINKS_ROOT = _root

dofile(_root .. 'lib/reaper_script_links.lua')   -- code under test

dofile(_tdir .. 'script_links.lua')
Test.report()
