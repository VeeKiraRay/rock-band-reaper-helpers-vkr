-- Venue > Preview sub-tab
-- Shows previous / current / next venue events relative to the playhead
-- for each category (Camera, Lighting, Post-Process) with sprite animations.
-- Requires globals: r, ctx, S, GetVenueEventsForPreview, DrawVenueInlineSprite,
--                   VenueSpriteFoldersFound, SectionHeader

local _preview_cache       = nil   -- { camera, lighting, postproc, track_end } or nil
local _preview_error       = nil   -- error string or nil
local _preview_animate     = true  -- false = show middle frame only (no animation)
local _last_state_count    = -1    -- r.GetProjectStateChangeCount() at last refresh
local _last_refresh_time   = 0     -- r.time_precise() at last refresh
local _auto_refresh_paused = false -- true if a read exceeded _SLOW_READ_THRESHOLD
local _AUTO_REFRESH_SECS   = 5.0   -- safety-net re-read interval when state count unchanged
local _SLOW_READ_THRESHOLD = 0.15  -- 150 ms — pause auto-refresh if exceeded

-- Matches SPRITE_DISPLAY_W / SPRITE_DISPLAY_H in venue_sprites.lua
local _SPRITE_W = 213
local _SPRITE_H = 120

-- Players combo constants (mirrors DEMO_CAM_COMBO_* in dev/rock_band_venue_demo_vkr)
local _COMBO_BG      = 0
local _COMBO_BK      = 1
local _COMBO_GK      = 2
local _COMBO_NAMES   = { [0]='Bass \xe2\x80\x93 Guitar', [1]='Bass \xe2\x80\x93 Keys', [2]='Guitar \xe2\x80\x93 Keys' }
local _COMBO_ABSENT  = { [0]='k', [1]='g', [2]='b' }          -- instrument NOT in this combo
local _COMBO_LETTERS = { [0]={'b','g'}, [1]={'b','k'}, [2]={'g','k'} }  -- instruments IN this combo
local _INST_NAMES    = { b='PART BASS', g='PART GUITAR', k='PART KEYS' }

local _SHOW_CURRENT_ONLY = 0
local _SHOW_SURROUNDING  = 1

local function _refresh_preview()
    local t0 = r.time_precise()
    _preview_cache, _preview_error = GetVenueEventsForPreview()
    local elapsed = r.time_precise() - t0
    _last_refresh_time = r.time_precise()
    _last_state_count  = r.GetProjectStateChangeCount()
    if _preview_cache then _preview_error = nil end
    if elapsed >= _SLOW_READ_THRESHOLD then
        _auto_refresh_paused = true
        _preview_error = ('Auto-refresh paused: last read took %.0f ms.\n'
                        .. 'Click "Resume auto-refresh" to try again.'):format(elapsed * 1000)
        _preview_cache = nil
    end
end

-- Format project time as "M34 - 01:21:555"
local function _fmt_event_time(t)
    local mbt     = r.format_timestr_pos(t, '', 1)
    local measure = mbt:match('^(%d+)') or '?'
    local mins    = math.floor(t / 60)
    local secs    = t % 60
    local ms      = math.floor((secs - math.floor(secs)) * 1000)
    return ('M%s - %02d:%02d:%03d'):format(measure, mins, math.floor(secs), ms)
end

-- Extract the bare name used for sprite lookup from an event message.
local function _get_bare_name(ev, category)
    if category == 'Lighting' then
        return ev.msg:match('^%[lighting %((.-)%)%]$') or ev.msg
    else
        return ev.msg:match('^%[(.-)%]$') or ev.msg
    end
end

-- Events are stored in MIDI order (chronological). Return prev/current/next
-- relative to the given playhead time. Groups events at the same PPQ position
-- so that stacked events (same spot) never split across prev/current/next.
local function _find_prev_current_next(events, time)
    if not events or #events == 0 then return nil, nil, nil end
    local curr_idx = nil
    for i, ev in ipairs(events) do
        if ev.t <= time then curr_idx = i else break end
    end
    if not curr_idx then return nil, nil, events[1] end

    local curr_ppq = events[curr_idx].ppq

    -- Walk back to the start of this PPQ group
    local group_start = curr_idx
    while group_start > 1 and events[group_start - 1].ppq == curr_ppq do
        group_start = group_start - 1
    end

    -- Previous: last event strictly before this group
    local prev = group_start > 1 and events[group_start - 1] or nil

    -- Current: last event in the group (alternatives searched by ppq in _resolve_cam_ev)
    local curr = events[curr_idx]

    -- Next: first event after this group
    local after = curr_idx + 1
    while after <= #events and events[after].ppq == curr_ppq do
        after = after + 1
    end
    local next_ev = after <= #events and events[after] or nil

    return prev, curr, next_ev
end

-- Build the muted table for filtering from the current combo selection.
local function _combo_muted(combo)
    return { [_COMBO_ABSENT[combo]] = true }
end

-- True if event_msg requires an instrument that is in the muted table.
-- Reuses GetCoopRequiredInstruments / GetDirectedRequiredInstruments from venue_awareness.lua.
local function _is_cam_filtered(msg, muted)
    local req
    if msg:find('^%[coop_')         then req = GetCoopRequiredInstruments(msg)
    elseif msg:find('^%[directed_') then req = GetDirectedRequiredInstruments(msg)
    else return false end
    for _, ltr in ipairs(req) do if muted[ltr] then return true end end
    return false
end

-- Given a camera event and the full camera list, find the best event to display.
-- Returns: display_ev, is_filtered
--   is_filtered=false → display_ev is suitable, show normally
--   is_filtered=true  → no suitable alternative found; display_ev is the original (show in red)
local function _resolve_cam_ev(ev, all_cam, muted)
    if not ev then return nil, false end
    if not _is_cam_filtered(ev.msg, muted) then return ev, false end
    for _, other in ipairs(all_cam) do
        if other.ppq == ev.ppq and not _is_cam_filtered(other.msg, muted) then
            return other, false
        end
    end
    return ev, true
end

-- Draw one labeled column (header + event card or placeholder).
-- NOTE: r.ImGui_Separator inside a BeginGroup expands to full window width,
-- breaking the side-by-side layout — use Spacing instead, and draw the
-- separator once outside all groups (in _draw_category_row).
-- Dummy reserves the sprite footprint so all columns stay the same width
-- even when there is no event or no spritesheet installed.
local function _draw_column(header, ev, category, scale, is_filtered, combo_name)
    local sw = _SPRITE_W * scale
    local sh = _SPRITE_H * scale
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, header)
    r.ImGui_Spacing(ctx)
    if not ev then
        r.ImGui_TextDisabled(ctx, 'No event found')
        r.ImGui_Dummy(ctx, sw, sh)
    else
        if is_filtered then
            r.ImGui_TextColored(ctx, 0xFF4444FF, ev.msg)
        else
            r.ImGui_Text(ctx, ev.msg)
        end
        r.ImGui_TextDisabled(ctx, _fmt_event_time(ev.t))
        if is_filtered then
            local cx, cy = r.ImGui_GetCursorPos(ctx)
            r.ImGui_Dummy(ctx, sw, sh)           -- reserve space first (sets group height)
            r.ImGui_SetCursorPos(ctx, cx, cy)    -- step back into that space
            r.ImGui_TextDisabled(ctx, ('No suitable event\nfor %s'):format(combo_name))
        else
            local bare    = _get_bare_name(ev, category)
            local slot_id = category .. '_' .. header
            if not DrawVenueInlineSprite(category, bare, scale, not _preview_animate, slot_id) then
                r.ImGui_TextDisabled(ctx, '(no preview image)')
                r.ImGui_Dummy(ctx, sw, sh)
            end
        end
    end
    r.ImGui_EndGroup(ctx)
end

local function _draw_category_row(label, prev_ev, curr_ev, next_ev, category, scale, muted, combo_name)
    SectionHeader(label)
    r.ImGui_Separator(ctx)  -- full-width separator drawn outside groups (safe here)
    local function col(header, ev)
        if muted then
            local d, f = _resolve_cam_ev(ev, _preview_cache.camera, muted)
            _draw_column(header, d, category, scale, f, combo_name)
        else
            _draw_column(header, ev, category, scale)
        end
    end
    if S.venue_preview_show_mode == _SHOW_CURRENT_ONLY then
        col('Current', curr_ev)
    else
        col('Previous', prev_ev)
        r.ImGui_SameLine(ctx)
        col('Current',  curr_ev)
        r.ImGui_SameLine(ctx)
        col('Next',     next_ev)
    end
end

function DrawVenuePreviewTab()
    if not _auto_refresh_paused then
        local state = r.GetProjectStateChangeCount()
        local now   = r.time_precise()
        if state ~= _last_state_count or now - _last_refresh_time >= _AUTO_REFRESH_SECS then
            _refresh_preview()
        end
    end

    r.ImGui_Text(ctx, 'Players')
    r.ImGui_SameLine(ctx)
    local _t_vpc = TIPS.venue_preview_combo
    if r.ImGui_RadioButton(ctx, 'Bass + Guitar##vpc', S.venue_preview_combo == _COMBO_BG) then
        S.venue_preview_combo = _COMBO_BG
    end
    Tooltip(_t_vpc)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Bass + Keys##vpc', S.venue_preview_combo == _COMBO_BK) then
        S.venue_preview_combo = _COMBO_BK
    end
    Tooltip(_t_vpc)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Guitar + Keys##vpc', S.venue_preview_combo == _COMBO_GK) then
        S.venue_preview_combo = _COMBO_GK
    end
    Tooltip(_t_vpc)
    do
        local muted_real = GetMutedInstruments()
        local warn = {}
        for _, ltr in ipairs(_COMBO_LETTERS[S.venue_preview_combo]) do
            if muted_real[ltr] then warn[#warn + 1] = _INST_NAMES[ltr] end
        end
        if #warn == 2 then
            r.ImGui_TextDisabled(ctx, 'Both instruments are muted')
        elseif #warn == 1 then
            r.ImGui_TextDisabled(ctx, warn[1] .. ' muted')
        end
    end

    r.ImGui_Text(ctx, 'Preview size')
    r.ImGui_SameLine(ctx)
    local _t_vpts = TIPS.venue_preview_scale
    if r.ImGui_RadioButton(ctx, '1x##vpts', S.venue_preview_tab_scale == 1) then
        S.venue_preview_tab_scale = 1
    end
    Tooltip(_t_vpts)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, '2x##vpts', S.venue_preview_tab_scale == 2) then
        S.venue_preview_tab_scale = 2
    end
    Tooltip(_t_vpts)

    r.ImGui_Text(ctx, 'Sprites')
    r.ImGui_SameLine(ctx)
    local _t_vpan = TIPS.venue_preview_animate
    if r.ImGui_RadioButton(ctx, 'Animated##vpan', _preview_animate) then
        _preview_animate = true
    end
    Tooltip(_t_vpan)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Still##vpan', not _preview_animate) then
        _preview_animate = false
    end
    Tooltip(_t_vpan)

    r.ImGui_Text(ctx, 'Show')
    r.ImGui_SameLine(ctx)
    local _t_vpshw = TIPS.venue_preview_show_mode
    if r.ImGui_RadioButton(ctx, 'Current only##vpshw', S.venue_preview_show_mode == _SHOW_CURRENT_ONLY) then
        S.venue_preview_show_mode = _SHOW_CURRENT_ONLY
    end
    Tooltip(_t_vpshw)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Surrounding events##vpshw', S.venue_preview_show_mode == _SHOW_SURROUNDING) then
        S.venue_preview_show_mode = _SHOW_SURROUNDING
    end
    Tooltip(_t_vpshw)

    if not VenueSpriteFoldersFound() then
        r.ImGui_TextDisabled(ctx, '\xe2\x80\x94 no spritesheets installed')
    end

    if _auto_refresh_paused then
        if r.ImGui_Button(ctx, 'Resume auto-refresh##vpr') then
            _auto_refresh_paused = false
            _refresh_preview()
        end
        Tooltip(TIPS.venue_preview_refresh_resume)
    end

    r.ImGui_Spacing(ctx)

    if _preview_error then
        r.ImGui_TextDisabled(ctx, _preview_error)
        return
    end
    if not _preview_cache then
        r.ImGui_TextDisabled(ctx, 'No data \xe2\x80\x94 reading\xe2\x80\xa6')
        return
    end

    local playing  = (r.GetPlayState() & 1) == 1
    local playhead = playing and r.GetPlayPosition() or r.GetCursorPosition()
    local scale    = S.venue_preview_tab_scale

    local cam_p, cam_c, cam_n = _find_prev_current_next(_preview_cache.camera,   playhead)
    local lt_p,  lt_c,  lt_n  = _find_prev_current_next(_preview_cache.lighting, playhead)
    local pp_p,  pp_c,  pp_n  = _find_prev_current_next(_preview_cache.postproc, playhead)

    local muted      = _combo_muted(S.venue_preview_combo)
    local combo_name = _COMBO_NAMES[S.venue_preview_combo]

    _draw_category_row('Camera',       cam_p, cam_c, cam_n, 'Camera',   scale, muted, combo_name)
    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)
    _draw_category_row('Lighting',     lt_p,  lt_c,  lt_n,  'Lighting', scale)
    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)
    _draw_category_row('Post-Process', pp_p,  pp_c,  pp_n,  'PostProc', scale)
end
