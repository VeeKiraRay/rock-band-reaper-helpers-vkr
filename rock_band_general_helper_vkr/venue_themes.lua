-- Venue theme file parser and preset API.
-- Requires: r, SortedByLabel (globals)

-- Ordered arrays for UI combo lists (section-by-section editor)
POSTPROC_NAMES = {
    'bloom.pp', 'bright.pp', 'clean_trails.pp', 'contrast_a.pp',
    'desat_blue.pp', 'desat_posterize_trails.pp', 'film_16mm.pp',
    'film_b+w.pp', 'film_blue_filter.pp', 'film_contrast.pp',
    'film_contrast_blue.pp', 'film_contrast_green.pp',
    'film_contrast_red.pp', 'film_sepia_ink.pp', 'film_silvertone.pp',
    'flicker_trails.pp', 'horror_movie_special.pp', 'photo_negative.pp',
    'photocopy.pp', 'posterize.pp', 'ProFilm_a.pp', 'ProFilm_b.pp',
    'ProFilm_mirror_a.pp', 'ProFilm_psychedelic_blue_red.pp',
    'shitty_tv.pp', 'space_woosh.pp', 'video_a.pp', 'video_bw.pp',
    'video_security.pp', 'video_trails.pp',
}

LIGHTING_NAMES = {
    'verse', 'chorus', 'manual_cool', 'manual_warm', 'dischord', 'stomp',
    'loop_cool', 'loop_warm', 'harmony', 'frenzy', 'silhouettes', 'silhouettes_spot',
    'searchlights', 'sweep', 'strobe_slow', 'strobe_fast',
    'blackout_slow', 'blackout_fast', 'blackout_spot', 'flare_slow', 'flare_fast', 'bre',
}

-- Display labels for section editor combos (keyed by bare name)
LIGHTING_LABELS = {
    verse='Verse (manual)', chorus='Chorus (manual)', manual_cool='Manual Cool', manual_warm='Manual Warm',
    dischord='Dischord (manual)', stomp='Stomp (manual)', loop_cool='Loop Cool', loop_warm='Loop Warm',
    harmony='Harmony', frenzy='Frenzy', silhouettes='Silhouettes',
    silhouettes_spot='Silhouettes Spot', searchlights='Searchlights', sweep='Sweep',
    strobe_slow='Strobe Slow', strobe_fast='Strobe Fast',
    blackout_slow='Blackout Slow', blackout_fast='Blackout Fast', blackout_spot='Blackout Spot',
    flare_slow='Flare Slow', flare_fast='Flare Fast', bre='BRE',
}

LIGHTING_TIPS = {
    verse            = 'Tends towards soft yet full blends, such as orange and green. Varies between venues.',
    chorus           = 'Tends towards stark, dramatic colors, such as saturated blue and red. Invokes a peak state. Varies between venues.',
    manual_cool      = 'Cool temperature lighting.',
    manual_warm      = 'Warm temperature lighting.',
    dischord         = 'Harsh lighting with a blend of dissonant colors.',
    stomp            = 'All lights are either on or off.',
    loop_cool        = 'A blend of cool temperature colors.',
    loop_warm        = 'A blend of warm temperature colors.',
    harmony          = 'A blend of lights with a harmonious color palette.',
    frenzy           = 'Frenetic, dissonant lighting that alternate quickly.',
    silhouettes      = 'Dark, atmospheric lighting. Shows character silhouettes.',
    silhouettes_spot = 'Dark, atmospheric lighting. Shows illuminated character silhouettes.',
    searchlights     = 'Searchlights that sweep individually.',
    sweep            = 'Lights that sweep together in banks.',
    strobe_slow      = 'Strobe lights that blink on every eighth note..',
    strobe_fast      = 'Strobe lights that blink on every sixteenth note.',
    blackout_slow    = 'Darken the stage slowly to blackout. The fade takes 2 seconds. Does not work if previous light state is too close.',
    blackout_fast    = 'Darken the stage quickly to blackout. The fade takes 0.2 seconds.',
    blackout_spot    = 'A blackout state with added underlighting.', -- was missing
    flare_slow       = 'Bright white flare that fades slowly into the next lighting preset.',
    flare_fast       = 'Bright white flare that fades quickly into the next lighting preset.',
    bre              = 'Frenetic lighting for a Big Rock Ending. Looks like frenzy, only crazier.',
}

POSTPROC_LABELS = {
    ['bloom.pp']='Bloom', ['bright.pp']='Bright', ['clean_trails.pp']='Clean Trails',
    ['contrast_a.pp']='Contrast A', ['desat_blue.pp']='Desaturate Blue',
    ['desat_posterize_trails.pp']='Desaturate Posterize Trails',
    ['film_16mm.pp']='Film 16mm', ['film_b+w.pp']='Film B+W',
    ['film_blue_filter.pp']='Film Blue Filter', ['film_contrast.pp']='Film Contrast',
    ['film_contrast_blue.pp']='Film Contrast Blue',
    ['film_contrast_green.pp']='Film Contrast Green',
    ['film_contrast_red.pp']='Film Contrast Red',
    ['film_sepia_ink.pp']='Film Sepia Ink', ['film_silvertone.pp']='Film Silvertone',
    ['flicker_trails.pp']='Flicker Trails',
    ['horror_movie_special.pp']='Horror Movie Special',
    ['photo_negative.pp']='Photo Negative', ['photocopy.pp']='Photocopy',
    ['posterize.pp']='Posterize',
    ['ProFilm_a.pp']='ProFilm A', ['ProFilm_b.pp']='ProFilm B',
    ['ProFilm_mirror_a.pp']='ProFilm Mirror A',
    ['ProFilm_psychedelic_blue_red.pp']='ProFilm Psychedelic Blue Red',
    ['shitty_tv.pp']='Sucky TV', ['space_woosh.pp']='Space Woosh',
    ['video_a.pp']='Video A', ['video_bw.pp']='Video B+W',
    ['video_security.pp']='Video Security', ['video_trails.pp']='Video Trails',
}

-- Combo display order: alphabetical by LABEL, which is what the user reads.
-- POSTPROC_NAMES itself is alphabetical by raw name and stays that way (the
-- spritesheet extraction tool maps its position to a video window); the two
-- differ only for shitty_tv.pp, labelled "Sucky TV".
POSTPROC_DISPLAY = SortedByLabel(POSTPROC_NAMES, POSTPROC_LABELS)

POSTPROC_TIPS = {
    ['bloom.pp']                        = 'Brightens the picture slightly. Adds a choppy low frame-per-second effect.',
    ['bright.pp']                       = 'Brightens to bloom-esque effect. Lightens dark colors.',
    ['clean_trails.pp']                 = 'Creates a small video feed delay, like a visual “echo”.',
    ['contrast_a.pp']                   = 'A very gritty, somewhat polarized black and white filter.',
    ['desat_blue.pp']                   = 'Slightly gainy image, with a blue tinge.',
    ['desat_posterize_trails.pp']       = 'Creates a long video feed delay and flattens colors.',
    ['film_16mm.pp']                    = 'Grainy video effect.',
    ['film_b+w.pp']                     = 'Reduces colors to a range of grey tones. The range of grey tones is smaller than Silvertone',
    ['film_blue_filter.pp']             = 'Reduces colors to a wide range of blue shades.',
    ['film_contrast.pp']                = 'Makes dark colors darker, and light colors lighter.',
    ['film_contrast_blue.pp']           = 'Makes dark colors darker, and light colors lighter. Adds a slight blue hue.',
    ['film_contrast_green.pp']          = 'Makes dark colors darker, and light colors lighter. Adds slightly green hues.',
    ['film_contrast_red.pp']            = 'Makes dark colors darker, and light colors lighter. Adds slightly red hues.',
    ['film_sepia_ink.pp']               = 'Reduces colors to a wide range of yellowish-grey shades.',
    ['film_silvertone.pp']              = 'Reduces colors to a wide range of grey shades.',
    ['flicker_trails.pp']               = 'Creates a video feed delay. Slightly darkens images and mutes colors.',
    ['horror_movie_special.pp']         = 'Polarizes colors to either red or black.',
    ['photo_negative.pp']               = 'Inverts colors.',
    ['photocopy.pp']                    = 'A choppy, low-frame-per-second effect.',
    ['posterize.pp']                    = 'Flattens colors (most noticable in shadows).',
    ['ProFilm_a.pp']                    = 'The default post process effect. No notable effects.',
    ['ProFilm_b.pp']                    = 'Slightly mutes all colors.',
    ['ProFilm_mirror_a.pp']             = 'The left side of the screen mirrors the right side. Changes colors to a variety of oranges, greens, and yellows.',
    ['ProFilm_psychedelic_blue_red.pp'] = 'Polarizes colors to either red or blue.',
    ['shitty_tv.pp']                     = 'Very grainy video. Dramatically lightens colors.', -- sucky or shitty
    ['space_woosh.pp']                  = 'Lightens colors dramatically. Creates three small video feed delays in red, green, and blue.',
    ['video_a.pp']                      = 'Slightly grainy video.',
    ['video_bw.pp']                     = 'Reduces colors to grey shades. Slightly grity. A smaller range of grey than Silvertone.',
    ['video_security.pp']               = 'Grainy video. Colors are reduced to a wide range of green shades.',
    ['video_trails.pp']                 = 'Creates a video feed delay. A longer delay than Clean Trails.',
}

local POSTPROC_VALID_SET = {}
do
    for _, v in ipairs(POSTPROC_NAMES) do POSTPROC_VALID_SET[v] = true end
end

local LIGHTING_VALID_SET = {
    verse=true, chorus=true, manual_cool=true, manual_warm=true,
    dischord=true, stomp=true, loop_cool=true, loop_warm=true,
    harmony=true, frenzy=true, silhouettes=true, silhouettes_spot=true,
    searchlights=true, sweep=true, strobe_slow=true, strobe_fast=true,
    blackout_slow=true, blackout_fast=true, blackout_spot=true, flare_slow=true, flare_fast=true,
    bre=true,
}

local CAMERA_PACING = {
    crazy = 4, fast = 8, medium = 16, slow = 24, minimal = 32,
}

-- ---------------------------------------------------------------------------
-- S-expression parser
-- ---------------------------------------------------------------------------

local function Tokenize(s)
    s = s:gsub(';[^\n]*', '')
    s = s:gsub('%(', ' ( '):gsub('%)', ' ) ')
    local t = {}
    for tok in s:gmatch('%S+') do t[#t + 1] = tok end
    return t
end

local function ParseSexpr(tokens, pos)
    if pos > #tokens then return nil, pos end
    local tok = tokens[pos]
    if tok == '(' then
        pos = pos + 1
        local list = {}
        while pos <= #tokens and tokens[pos] ~= ')' do
            local elem, next_pos = ParseSexpr(tokens, pos)
            list[#list + 1] = elem
            pos = next_pos
        end
        return list, pos + 1
    else
        return tok, pos + 1
    end
end

local function ParseThemeFile(s)
    local tokens = Tokenize(s)
    local nodes  = {}
    local pos    = 1
    while pos <= #tokens do
        local node, next_pos = ParseSexpr(tokens, pos)
        if node then nodes[#nodes + 1] = node end
        pos = next_pos
    end
    return nodes
end

-- ---------------------------------------------------------------------------
-- Theme interpreter
-- ---------------------------------------------------------------------------

local function InterpretSectionPreset(children)
    local preset = {}
    for _, child in ipairs(children) do
        if type(child) == 'table' and #child >= 1 then
            local key = child[1]
            if key == 'allowed_lightpresets' then
                preset.allowed_lightpresets = {}
                for i = 2, #child do
                    local name = child[i]
                    if type(name) == 'string' and LIGHTING_VALID_SET[name] then
                        preset.allowed_lightpresets[#preset.allowed_lightpresets + 1] = name
                    end
                end
            elseif key == 'allowed_postprocs' then
                preset.allowed_postprocs = {}
                for i = 2, #child do
                    local name = child[i]
                    if type(name) == 'string' and POSTPROC_VALID_SET[name] then
                        preset.allowed_postprocs[#preset.allowed_postprocs + 1] = name
                    end
                end
            elseif key == 'keyframe_rate' then
                preset.keyframe_rate = tonumber(child[2])
            elseif key == 'lightpreset_blendin' then
                preset.lightpreset_blendin = tonumber(child[2])
            elseif key == 'postproc_blendin' then
                preset.postproc_blendin = tonumber(child[2])
            elseif key == 'camera_pacing' and type(child[2]) == 'string' then
                preset.camera_pacing = child[2]
            elseif key == 'dircut_at_start' and type(child[2]) == 'string' then
                preset.dircut_at_start = child[2]
            elseif key == 'bonusfx_at_start' then
                preset.bonusfx_at_start = true
            end
        end
    end
    return preset
end

local function InterpretTheme(nodes)
    local theme = { camera_pacing = 'medium', section_presets = {} }
    for _, node in ipairs(nodes) do
        if type(node) == 'table' and #node >= 1 then
            local key = node[1]
            if key == 'camera_pacing' and type(node[2]) == 'string' then
                theme.camera_pacing = node[2]
            elseif key == 'section_presets' then
                for i = 2, #node do
                    local sec = node[i]
                    if type(sec) == 'table' and type(sec[1]) == 'string' then
                        local children = {}
                        for j = 2, #sec do children[#children + 1] = sec[j] end
                        theme.section_presets[sec[1]] = InterpretSectionPreset(children)
                    end
                end
            end
        end
    end
    return theme
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ThemeDisplayLabel(stem)
    local result = stem:sub(1, 1)
    for i = 2, #stem do
        local c = stem:sub(i, i)
        result = result .. (c:match('%u') and (' ' .. c) or c)
    end
    return result
end

function LoadVenueThemes(themes_dir)
    -- r.EnumerateFiles requires a path without trailing separator
    local dir_no_slash = themes_dir:gsub('[/\\]$', '')
    local themes = {}
    local i      = 0
    while true do
        local filename = r.EnumerateFiles(dir_no_slash, i)
        if not filename then break end
        i = i + 1
        local stem = filename:match('^(.+)%.rbtheme$')
        if stem then
            local path = dir_no_slash .. '/' .. filename
            local f    = io.open(path, 'r')
            if f then
                local content = f:read('*all')
                f:close()
                local ok, result = pcall(function()
                    local nodes = ParseThemeFile(content)
                    local theme = InterpretTheme(nodes)
                    theme.label = ThemeDisplayLabel(stem)
                    theme.stem  = stem
                    return theme
                end)
                if ok then themes[#themes + 1] = result end
            end
        end
    end
    table.sort(themes, function(a, b) return a.label < b.label end)
    return themes
end

function GetSectionPreset(theme, section_name, section_num)
    local presets = theme.section_presets
    if not presets then return nil end

    if section_num then
        -- Collect consecutively numbered variants: name1, name2, name3, ...
        local variants = {}
        local n = 1
        while true do
            local key = section_name .. n
            if presets[key] then
                variants[#variants + 1] = presets[key]
                n = n + 1
            else
                break
            end
        end
        if #variants > 0 then
            local idx = ((section_num - 1) % #variants) + 1
            return variants[idx]
        end
        -- No numbered variants - try bare name
        if presets[section_name] then return presets[section_name] end
    else
        if presets[section_name] then return presets[section_name] end
    end

    return presets['default']
end

function GetThemeCameraInterval(camera_pacing, bpm)
    local base = CAMERA_PACING[camera_pacing] or CAMERA_PACING.medium
    return (bpm >= 150) and math.floor(base * 1.5 + 0.5) or base
end

function BuildLightingPool(preset)
    if not preset or not preset.allowed_lightpresets then return nil end
    local pool = {}
    for _, name in ipairs(preset.allowed_lightpresets) do
        if LIGHTING_VALID_SET[name] then
            pool[#pool + 1] = '[lighting (' .. name .. ')]'
        end
    end
    return #pool > 0 and pool or nil
end

function BuildPostprocPool(preset)
    if not preset or not preset.allowed_postprocs then return nil end
    local pool = {}
    for _, name in ipairs(preset.allowed_postprocs) do
        if POSTPROC_VALID_SET[name] then
            pool[#pool + 1] = '[' .. name .. ']'
        end
    end
    return #pool > 0 and pool or nil
end
