-- Spritesheet animation helpers for venue editor combo tooltips.
-- Requires globals: r, ctx, S, SCRIPT_MDIR
-- Degrades silently if spritesheets are not installed.

local SPRITE_COLS       = 8     -- grid convention: all sheets use 8×9
local SPRITE_ROWS       = 9
local SPRITE_FRAME_RATE = 30
local SPRITE_DISPLAY_W  = 213   -- base tooltip render size (1×); 2× doubles this
local SPRITE_DISPLAY_H  = 120

local _repo_root = SCRIPT_DIR or SCRIPT_MDIR:match('^(.+[\\/])[^\\/]+[\\/]$') or SCRIPT_MDIR
-- Self-hosted JPEG sheets under resources/img/spritesheets/{category}/ (large) or
-- resources/img/spritesheets/{category} small/ (small). Large folder is checked first.
VENUE_SPRITE_ROOT = _repo_root .. 'resources/img/spritesheets/'

-- Maps our bare directed-cut names to the filename key used by spritesheets.
DIRECTED_SPRITE_NAMES = {
    directed_all='dall',           directed_all_cam='dallcam',     directed_all_lt='dalllt',
    directed_all_yeah='dallyeah',  directed_crowd='dcrowd',
    directed_drums='ddrums',       directed_drums_pnt='ddrumspoint',
    directed_drums_np='ddrumsnp',  directed_drums_lt='ddrumslt',   directed_drums_kd='ddrumskd',
    directed_vocals='dvocals',     directed_vocals_np='dvoxnp',    directed_vocals_cls='dvoxcls',
    directed_vocals_cam_pr='dvoxcampr', directed_vocals_cam_pt='dvoxcampt',
    directed_stagedive='dstagedive', directed_crowdsurf='dcrowdsurf',
    directed_bass='dbass',         directed_crowd_b='dcrowdbass',
    directed_bass_np='dbassnp',    directed_bass_cam='dbasscam',   directed_bass_cls='dbasscls',
    directed_guitar='dgtr',        directed_crowd_g='dcrowdgtr',
    directed_guitar_np='dgtrnp',   directed_guitar_cls='dgtrcls',
    directed_guitar_cam_pr='dgtrcampr', directed_guitar_cam_pt='dgtrcampt',
    directed_keys='dkeys',         directed_keys_cam='dkeyscam',   directed_keys_np='dkeysnp',
    directed_duo_drums='dduodrums', directed_duo_bass='dduobass',
    directed_duo_guitar='dduogtr', directed_duo_kv='dduokv',
    directed_duo_gb='dduogb',      directed_duo_kb='dduokb',       directed_duo_kg='dduokg',
}

-- Maps our postproc bare names (without .pp) to the spritesheet filename key.
-- Only entries where algorithmic stripping produces the wrong result are listed.
local POSTPROC_SPRITE_NAMES = {
    ['contrast_a']                   = 'contrastbw',
    ['desat_posterize_trails']       = 'desatposterize',
    ['film_16mm']                    = '16mmfilm',
    ['film_b+w']                     = 'filmbw',
    ['film_blue_filter']             = 'bluefilter',
    ['film_sepia_ink']               = 'sepiaink',
    ['film_silvertone']              = 'silvertone',
    ['horror_movie_special']         = 'horrormovie',
    ['ProFilm_b']                    = 'colormuted',
    ['ProFilm_mirror_a']             = 'mirror',
    ['ProFilm_psychedelic_blue_red'] = 'psychbluered',
    ['video_a']                      = 'videograiny',
}

-- Cache: "Category/norm_key" → {image, frame_count, cols, rows} or false (not found)
local _sprite_cache = {}
local _slot_keys  = {}   -- slot_id → last bare_name shown in that slot
local _slot_start = {}   -- slot_id → wall-clock time when slot last changed sprite

local _sprite_dirs_found = nil  -- nil = unchecked; cached on first call

local function NormalizeSpriteKey(category, bare_name)
    if category == 'Lighting' then
        return bare_name:gsub('[_ ]', ''):lower()
    elseif category == 'PostProc' then
        local bare = bare_name:gsub('%.pp$', '')
        return POSTPROC_SPRITE_NAMES[bare] or bare:gsub('[_ ]', ''):lower()
    else  -- Camera (directed cuts)
        return DIRECTED_SPRITE_NAMES[bare_name] or bare_name:gsub('[_ ]', ''):lower()
    end
end

-- Scan dir for the JPEG whose base name (normalized) matches norm_key.
-- File naming convention: {key}_f{framecount}_spritesheet.jpg
local function _try_load_from_dir(dir, norm_key)
    local i = 0
    while true do
        local file = r.EnumerateFiles(dir, i)
        if not file then break end
        local jbase, fc_str = file:match('^(.+)_f(%d+)_spritesheet%.jpg$')
        if jbase and jbase:gsub('[_ ]', ''):lower() == norm_key then
            local ok, img = pcall(r.ImGui_CreateImage, dir .. file)
            if ok and img then
                r.ImGui_Attach(ctx, img)
                local fc = math.max(tonumber(fc_str) or 1, 1)
                local iw, ih = r.ImGui_Image_GetSize(img)
                local tile_w = iw / SPRITE_COLS
                local actual_rows = math.max(1, math.floor(ih / (tile_w * 120 / 213) + 0.5))
                return {
                    image       = img,
                    frame_count = fc,
                    cols        = SPRITE_COLS,
                    rows        = actual_rows,
                }
            end
            break
        end
        i = i + 1
    end
    return nil
end

local _CAT_FOLDER = {Camera='camera', Lighting='lighting', PostProc='postproc'}

local function FindAndLoadSprite(category, norm_key)
    local folder = _CAT_FOLDER[category] or category:lower()
    local result = _try_load_from_dir(VENUE_SPRITE_ROOT .. folder .. '/', norm_key)
    if result then return result end
    return _try_load_from_dir(VENUE_SPRITE_ROOT .. folder .. ' small/', norm_key)
end

-- Load and cache a spritesheet. Returns {image, frame_count, cols, rows} or false.
function LoadVenueSprite(category, bare_name)
    local norm = NormalizeSpriteKey(category, bare_name)
    local key  = category .. '/' .. norm
    local cached = _sprite_cache[key]
    if cached ~= nil then return cached end
    local result = FindAndLoadSprite(category, norm)
    _sprite_cache[key] = result
    return result
end

-- Returns true if at least one spritesheet category folder has files. Result cached.
function VenueSpriteFoldersFound()
    if _sprite_dirs_found ~= nil then return _sprite_dirs_found end
    local cats = {'camera', 'lighting', 'postproc'}
    for _, cat in ipairs(cats) do
        if r.EnumerateFiles(VENUE_SPRITE_ROOT .. cat .. '/', 0) ~= nil then
            _sprite_dirs_found = true; return true
        end
        if r.EnumerateFiles(VENUE_SPRITE_ROOT .. cat .. ' small/', 0) ~= nil then
            _sprite_dirs_found = true; return true
        end
    end
    _sprite_dirs_found = false
    return false
end

-- Render one animated frame inside the currently-open BeginTooltip window.
-- Animation loops continuously based on r.time_precise() - no start-time tracking needed.
-- Returns true if image was drawn, false if no spritesheet found (caller shows text only).
function DrawVenueTooltipSprite(category, bare_name)
    local data = LoadVenueSprite(category, bare_name)
    if not data then return false end
    if not r.ImGui_ValidatePtr(data.image, 'ImGui_Image*') then
        local norm = NormalizeSpriteKey(category, bare_name)
        _sprite_cache[category .. '/' .. norm] = false
        return false
    end
    local freeze     = not (S.venue_preview_animate)
    local frame      = freeze
        and math.floor(data.frame_count / 2)
        or  math.floor(r.time_precise() * SPRITE_FRAME_RATE) % data.frame_count
    local img_w, img_h = r.ImGui_Image_GetSize(data.image)
    local src_tile_w = img_w / data.cols
    local src_tile_h = img_h / data.rows
    local col        = frame % data.cols
    local row        = math.floor(frame / data.cols)
    local scale      = S.venue_preview_scale or 1
    r.ImGui_Image(ctx, data.image, SPRITE_DISPLAY_W * scale, SPRITE_DISPLAY_H * scale,
        (col * src_tile_w)           / img_w,
        (row * src_tile_h)           / img_h,
        ((col + 1) * src_tile_w)     / img_w,
        ((row + 1) * src_tile_h)     / img_h)
    return true
end

-- Open a venue tooltip window with text wrap pinned to the sprite width.
-- Always call EndVenueTooltip when this returns true.
-- Draw one animated sprite frame inline at the current cursor position (not inside a tooltip).
-- Takes explicit scale so the Preview sub-tab can use its own scale setting.
-- Returns true if the image was drawn, false if no spritesheet was found.
function DrawVenueInlineSprite(category, bare_name, scale, freeze, slot_id)
    local data = LoadVenueSprite(category, bare_name)
    if not data then return false end
    if not r.ImGui_ValidatePtr(data.image, 'ImGui_Image*') then
        local norm = NormalizeSpriteKey(category, bare_name)
        _sprite_cache[category .. '/' .. norm] = false
        return false
    end
    local frame
    if freeze then
        frame = math.floor(data.frame_count / 2)
    elseif slot_id then
        local now = r.time_precise()
        if _slot_keys[slot_id] ~= bare_name then
            _slot_keys[slot_id]  = bare_name
            _slot_start[slot_id] = now
        end
        frame = math.floor((now - _slot_start[slot_id]) * SPRITE_FRAME_RATE) % data.frame_count
    else
        frame = math.floor(r.time_precise() * SPRITE_FRAME_RATE) % data.frame_count
    end
    local img_w, img_h = r.ImGui_Image_GetSize(data.image)
    local src_tile_w = img_w / data.cols
    local src_tile_h = img_h / data.rows
    local col        = frame % data.cols
    local row        = math.floor(frame / data.cols)
    r.ImGui_Image(ctx, data.image, SPRITE_DISPLAY_W * scale, SPRITE_DISPLAY_H * scale,
        (col * src_tile_w)       / img_w, (row * src_tile_h)       / img_h,
        ((col + 1) * src_tile_w) / img_w, ((row + 1) * src_tile_h) / img_h)
    return true
end

function BeginVenueTooltip()
    if not r.ImGui_BeginTooltip(ctx) then return false end
    r.ImGui_PushTextWrapPos(ctx, SPRITE_DISPLAY_W * (S.venue_preview_scale or 1))
    return true
end

function EndVenueTooltip()
    r.ImGui_PopTextWrapPos(ctx)
    r.ImGui_EndTooltip(ctx)
end
