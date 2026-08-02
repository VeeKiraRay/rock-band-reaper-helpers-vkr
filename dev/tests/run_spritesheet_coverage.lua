-- @description Rock Band General Helper - Spritesheet Coverage
-- @author VeeKiraRay
-- @about
--   Checks that every venue event has at least one spritesheet JPEG (large or small folder).
--   Reports missing canonicals as FAIL. Reports unexpected extra files (leftover alts or
--   unrecognised names) as FAIL. Run from the REAPER Actions list or via the
--   test_rock_band_helpers_vkr launcher. Results appear in the REAPER console.

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
local _demo_dir   = _root .. 'dev/rock_band_venue_demo_vkr/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Spritesheet Coverage  ======\n')

dofile(_tdir  .. 'framework.lua')
-- demo defaults is self-contained: defines DIRECTED_POOL, COOP_POOL,
-- DIRECTED_SPRITE_NAMES, LIGHTING_NAMES, POSTPROC_NAMES, POSTPROC_SPRITE_NAMES.
-- No dependency on the main general helper modules.
dofile(_demo_dir .. 'defaults.lua')

local SPRITE_ROOT = _root .. 'resources/img/spritesheets/'

-- -----------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------

-- Scan a directory for *_f{N}_spritesheet.jpg files.
-- Returns table: normalized_jbase -> original_filename
local function scan_dir(dir)
    local found = {}
    local i = 0
    while true do
        local file = r.EnumerateFiles(dir, i)
        if not file then break end
        local jbase = file:match('^(.+)_f%d+_spritesheet%.jpg$')
        if jbase then
            found[jbase:gsub('[_ ]', ''):lower()] = file
        end
        i = i + 1
    end
    return found
end

-- -----------------------------------------------------------------------
-- Expected norm keys per category
-- (Same logic as NormalizeSpriteKey in venue_sprites.lua)
-- -----------------------------------------------------------------------

local camera_keys = {}
for _, ev in ipairs(DIRECTED_POOL) do
    local bare = ev:match('^%[(.-)%]$') or ev
    local norm = DIRECTED_SPRITE_NAMES[bare] or bare:gsub('[_ ]', ''):lower()
    camera_keys[norm] = bare
end
for _, ev in ipairs(COOP_POOL) do
    local bare = ev:match('^%[(.-)%]$') or ev
    camera_keys[bare:gsub('[_ ]', ''):lower()] = bare
end

local lighting_keys = {}
for _, lt in ipairs(LIGHTING_NAMES) do
    lighting_keys[lt:gsub('[_ ]', ''):lower()] = lt
end

local postproc_keys = {}
for _, pp in ipairs(POSTPROC_NAMES) do
    local bare = pp:gsub('%.pp$', '')
    local norm = POSTPROC_SPRITE_NAMES[bare] or bare:gsub('[_ ]', ''):lower()
    postproc_keys[norm] = pp
end

-- -----------------------------------------------------------------------
-- Coverage checker
-- -----------------------------------------------------------------------

local function check_category(title, cat_folder, expected_keys)
    Test.section(title)

    local large_dir = SPRITE_ROOT .. cat_folder .. '/'
    local small_dir = SPRITE_ROOT .. cat_folder .. ' small/'
    local large     = scan_dir(large_dir)
    local small     = scan_dir(small_dir)

    -- Missing canonicals: FAIL if not in large OR small folder.
    local sorted = {}
    for norm in pairs(expected_keys) do sorted[#sorted + 1] = norm end
    table.sort(sorted)

    for _, norm in ipairs(sorted) do
        Test.it('found: ' .. norm, function()
            if not (large[norm] or small[norm]) then
                error('missing from ' .. cat_folder .. '/ and ' .. cat_folder .. ' small/')
            end
        end)
    end

    -- Extra files: FAIL if a file's normalized base is not a known event norm key.
    local function report_extras(files, label)
        local extras = {}
        for norm, fname in pairs(files) do
            if not expected_keys[norm] then extras[#extras + 1] = fname end
        end
        table.sort(extras)
        for _, fname in ipairs(extras) do
            Test.it('no extra file: ' .. fname, function()
                error('unexpected in ' .. label .. ' - leftover alt or unrecognised sprite')
            end)
        end
    end

    report_extras(large, cat_folder .. '/')
    report_extras(small, cat_folder .. ' small/')
end

check_category('Camera spritesheets',  'camera',   camera_keys)
check_category('Lighting spritesheets','lighting',  lighting_keys)
check_category('PostProc spritesheets','postproc',  postproc_keys)

Test.report()
