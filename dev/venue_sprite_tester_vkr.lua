-- @description Venue Sprite Tester (VKR)
-- @author VeeKiraRay
-- @about
--   Side-by-side animated preview of venue events.
--   Compares Big (2x, resources/img/spritesheets/) and Small (1x, resources/img/spritesheets/ small)
--   side by side. Each column shows PNG and JPEG rows stacked vertically.
--   Shows the exact filename tried per row so missing files are easy to diagnose.

r = reaper

if not r.ImGui_CreateContext then
    r.ShowMessageBox('ReaImGui not found. Install it via ReaPack.', 'Venue Sprite Tester', 0)
    return
end
if not r.ImGui_BeginDisabled then
    r.ShowMessageBox('ReaImGui 0.7 or later required.', 'Venue Sprite Tester', 0)
    return
end

ctx = r.ImGui_CreateContext('Venue Sprite Tester')

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
SCRIPT_MDIR   = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'

dofile(_dir .. 'rock_band_venue_demo_vkr/defaults.lua')
dofile(_dir .. '../rock_band_general_helper_vkr/venue_sprites.lua')

------------------------------------------------------------------------
-- Local replica of DetectFrameCount (private function in venue_sprites.lua)
-- Used as fallback for PNG files that don't carry frame count in their name.
------------------------------------------------------------------------
local function DetectFrameCountLocal(path, border)
    border = border or 1
    if not r.JS_LICE_LoadPNG then return 72 end
    local ok, bm = pcall(r.JS_LICE_LoadPNG, path)
    if not ok or not bm then return 72 end
    local img_w = r.JS_LICE_GetWidth(bm)
    local img_h = r.JS_LICE_GetHeight(bm)
    local tw    = math.floor(img_w / 8)
    local th    = math.floor(img_h / 9)
    local first = 72
    for frame = 0, 71 do
        local sx  = (frame % 8) * tw
        local sy  = math.floor(frame / 8) * th
        local blk = true
        for y = sy + border, sy + th - 1 - border, 8 do
            for x = sx + border, sx + tw - 1 - border, 8 do
                local c = r.JS_LICE_GetPixel(bm, x, y)
                if ((c >> 16) & 0xFF) > 5
                or ((c >> 8)  & 0xFF) > 5
                or  (c        & 0xFF) > 5 then
                    blk = false; break
                end
            end
            if not blk then break end
        end
        if blk then first = frame; break end
    end
    r.JS_LICE_DestroyBitmap(bm)
    return first > 0 and first or 72
end

------------------------------------------------------------------------
-- FindSheetFile: enumerate a directory to find a matching spritesheet.
--   fmt 'png' → {stem}_spritesheet.png  (exact match)
--   fmt 'jpg' → {stem}_f{N}_spritesheet.jpg  (frame count in name; N captured)
-- Returns (full_path, frame_count_or_nil).  frame_count is only set for jpg.
------------------------------------------------------------------------
local function FindSheetFile(dir, stem, fmt)
    local i = 0
    while true do
        local file = r.EnumerateFiles(dir, i)
        if not file then break end
        if fmt == 'jpg' then
            local fc_str = file:match('^' .. stem .. '_f(%d+)_spritesheet%.jpg$')
            if fc_str then return dir .. file, tonumber(fc_str) end
        else
            if file == stem .. '_spritesheet.png' then return dir .. file, nil end
        end
        i = i + 1
    end
    return nil, nil
end

------------------------------------------------------------------------
-- Image cache: "dir|stem:fmt" → {image, frame_count, border, fname, key} or false
------------------------------------------------------------------------
local _cache = {}

local function LoadSheet(dir, stem, fmt, border)
    local key = dir .. '|' .. stem .. ':' .. fmt
    local cached = _cache[key]
    if cached ~= nil then return cached end

    local path, fc_from_name = FindSheetFile(dir, stem, fmt)
    if not path then
        _cache[key] = false
        return false
    end

    local ok, img = pcall(r.ImGui_CreateImage, path)
    if ok and img then
        r.ImGui_Attach(ctx, img)
        local iw, ih = r.ImGui_Image_GetSize(img)
        local tile_w  = iw / 8
        local actual_rows = math.max(1, math.floor(ih / (tile_w * 120 / 213) + 0.5))
        local fc = fc_from_name or DetectFrameCountLocal(path, border)
        _cache[key] = {
            image       = img,
            frame_count = math.max(fc, 1),
            rows        = actual_rows,
            border      = border,
            fname       = path:match('[^\\/]+$'),
            key         = key,
        }
    else
        _cache[key] = false
    end
    return _cache[key]
end

------------------------------------------------------------------------
-- Build event list from the loaded pools/labels
------------------------------------------------------------------------
local EVENTS = {}   -- {label, norm, category}
local GROUPS  = {}  -- {name, first}  (first = 1-based index into EVENTS)

local function add_group(name)
    GROUPS[#GROUPS + 1] = { name=name, first=#EVENTS + 1 }
end

add_group('Directed Cuts')
for _, ev in ipairs(DIRECTED_POOL) do
    local bare = ev:match('^%[(.-)%]$') or ev
    EVENTS[#EVENTS + 1] = {
        label    = DIRECTED_LABELS[bare] or bare,
        norm     = DIRECTED_SPRITE_NAMES[bare] or bare:gsub('[_ ]', ''):lower(),
        category = 'Camera',
    }
end

add_group('Coop Shots')
for _, ev in ipairs(COOP_POOL) do
    local bare = ev:match('^%[(.-)%]$') or ev
    EVENTS[#EVENTS + 1] = { label=bare, norm=bare:gsub('[_ ]', ''):lower(), category='Camera' }
end

add_group('Lighting')
for _, lt in ipairs(LIGHTING_NAMES) do
    EVENTS[#EVENTS + 1] = {
        label    = LIGHTING_LABELS[lt] or lt,
        norm     = lt:gsub('[_ ]', ''):lower(),
        category = 'Lighting',
    }
end

add_group('PostProc')
for _, pp in ipairs(POSTPROC_NAMES) do
    local bare = pp:gsub('%.pp$', '')
    EVENTS[#EVENTS + 1] = {
        label    = POSTPROC_LABELS[pp] or pp,
        norm     = POSTPROC_SPRITE_NAMES[bare] or bare:gsub('[_ ]', ''):lower(),
        category = 'PostProc',
    }
end

------------------------------------------------------------------------
-- Panel config
-- has_jpeg: whether to show a JPEG row below the PNG row.
-- FCP is always PNG-only so its has_jpeg = false.
------------------------------------------------------------------------
local IMG_ROOT = _dir .. '../resources/img/spritesheets/'

local PANELS = {
    { title='Big (2x)',   dir=IMG_ROOT, suffix='',       border=0, has_jpeg=true },
    { title='Small (1x)', dir=IMG_ROOT, suffix=' small', border=0, has_jpeg=true },
}

------------------------------------------------------------------------
-- UI state
------------------------------------------------------------------------
local S = { sel=1, alt=1, scale=2 }   -- default 2x display

------------------------------------------------------------------------
-- DrawSheetRow: draw one format row (PNG or JPEG) within a panel column.
------------------------------------------------------------------------
local COL_OK      = 0x88FF88FF
local COL_MISSING = 0xFF5555FF
local COL_BOX_BG  = 0x1A1A1AFF
local COL_BOX_BD  = 0x555555FF

local function DrawSheetRow(dir, stem, fmt, border, dw, dh)
    local data = LoadSheet(dir, stem, fmt, border)

    if data and not r.ImGui_ValidatePtr(data.image, 'ImGui_Image*') then
        _cache[data.key] = false; data = false
    end

    r.ImGui_TextDisabled(ctx, fmt:upper())
    r.ImGui_Spacing(ctx)

    if data then
        local frame    = math.floor(r.time_precise() * 30) % data.frame_count
        local img_w, img_h = r.ImGui_Image_GetSize(data.image)
        local tw   = img_w / 8
        local th   = img_h / data.rows
        local brd  = data.border
        local col  = frame % 8
        local row  = math.floor(frame / 8)
        r.ImGui_Image(ctx, data.image, dw, dh,
            (col * tw + brd)       / img_w, (row * th + brd)       / img_h,
            ((col + 1) * tw - brd) / img_w, ((row + 1) * th - brd) / img_h)
    else
        local dl     = r.ImGui_GetWindowDrawList(ctx)
        local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_DrawList_AddRectFilled(dl, ox, oy, ox + dw, oy + dh, COL_BOX_BG)
        r.ImGui_DrawList_AddRect(dl, ox, oy, ox + dw, oy + dh, COL_BOX_BD)
        r.ImGui_Dummy(ctx, dw, dh)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_TextDisabled(ctx, data and data.fname or ('(missing)'))
    if data then
        r.ImGui_TextColored(ctx, COL_OK, 'OK  ' .. data.frame_count .. ' frames')
    else
        r.ImGui_TextColored(ctx, COL_MISSING, 'MISSING')
    end
end

------------------------------------------------------------------------
-- DrawPanel: draws one table column — title, PNG row, and optional JPEG row.
------------------------------------------------------------------------
local function DrawPanel(p, ev, dw, dh)
    local stem = S.alt <= 1
        and ev.norm
        or  (ev.norm .. '_alt' .. S.alt)
    local dir = p.dir .. ev.category:lower() .. p.suffix .. '/'

    r.ImGui_Text(ctx, p.title)
    r.ImGui_Spacing(ctx)

    DrawSheetRow(dir, stem, 'png', p.border, dw, dh)

    if p.has_jpeg then
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        DrawSheetRow(dir, stem, 'jpg', p.border, dw, dh)
    end
end

------------------------------------------------------------------------
-- Main UI
------------------------------------------------------------------------
local WIN_W, WIN_H = 1440, 900

local function DrawUI()
    r.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Venue Sprite Tester', true)
    if not visible then return open end

    local dw = S.scale == 2 and 426 or 213
    local dh = S.scale == 2 and 240 or 120

    -- Controls row
    local ev = EVENTS[S.sel]
    r.ImGui_Text(ctx, 'Event')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 320)
    if r.ImGui_BeginCombo(ctx, '##ev', ev and ev.label or '?') then
        local gi = 1
        for i, e in ipairs(EVENTS) do
            if gi <= #GROUPS and GROUPS[gi].first == i then
                if i > 1 then r.ImGui_Separator(ctx) end
                r.ImGui_TextDisabled(ctx, GROUPS[gi].name)
                gi = gi + 1
            end
            local sel = (i == S.sel)
            if r.ImGui_Selectable(ctx, e.label .. '##e' .. i, sel) then
                S.sel = i
            end
            if sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, '1x##sc', S.scale == 1) then S.scale = 1 end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, '2x##sc', S.scale == 2) then S.scale = 2 end

    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, '  Alt')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 48)
    local _, new_alt = r.ImGui_InputInt(ctx, '##alt', S.alt)
    S.alt = math.max(1, new_alt)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Three-panel table
    if ev and r.ImGui_BeginTable(ctx, 'panels', 2, r.ImGui_TableFlags_BordersInnerV()) then
        r.ImGui_TableNextRow(ctx)
        for _, p in ipairs(PANELS) do
            r.ImGui_TableNextColumn(ctx)
            DrawPanel(p, ev, dw, dh)
        end
        r.ImGui_EndTable(ctx)
    end

    r.ImGui_End(ctx)
    return open
end

local function Loop()
    local open = DrawUI()
    if open then r.defer(Loop) end
end

r.defer(Loop)
