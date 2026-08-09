-- Venue > Preview sub-tab
-- Shows previous / current / next venue events relative to the playhead
-- for each category (Camera, Lighting, Post-Process) with sprite animations.
-- Requires globals: r, ctx, S, GetVenueEventsForPreview, DrawVenueInlineSprite,
--                   VenueSpriteFoldersFound, SectionHeader, PickPriorityCameraEvent

local _preview_cache       = nil   -- { camera, lighting, postproc } or nil
local _preview_error       = nil   -- error string or nil
local _preview_animate     = true  -- false = show middle frame only (no animation)
local _last_state_count    = -1    -- r.GetProjectStateChangeCount() at last refresh
local _last_refresh_time   = 0     -- r.time_precise() at last refresh
local _auto_refresh_paused = false -- true if a read exceeded _SLOW_READ_THRESHOLD
local _AUTO_REFRESH_SECS   = 5.0   -- safety-net re-read interval when state count unchanged
local _SLOW_READ_THRESHOLD = 0.15  -- 150 ms - pause auto-refresh if exceeded

-- Matches SPRITE_DISPLAY_W / SPRITE_DISPLAY_H in venue_sprites.lua
local _SPRITE_W = 213
local _SPRITE_H = 120

-- Players combo constants (mirrors DEMO_CAM_COMBO_* in dev/rock_band_venue_demo_vkr)
local _COMBO_BG      = 0
local _COMBO_BK      = 1
local _COMBO_GK      = 2
local _COMBO_NAMES   = { [0]='Bass - Guitar', [1]='Bass - Keys', [2]='Guitar - Keys' }
local _COMBO_ABSENT  = { [0]='k', [1]='g', [2]='b' }          -- instrument NOT in this combo
local _COMBO_LETTERS = { [0]={'b','g'}, [1]={'b','k'}, [2]={'g','k'} }  -- instruments IN this combo
local _INST_NAMES    = { b='PART BASS', g='PART GUITAR', k='PART KEYS' }

local _SHOW_CURRENT_ONLY = 0
local _SHOW_SURROUNDING  = 1

-- Amber, for the one transition line that reports live state ("blending now").
-- Deliberately not the 0xFF4444FF red the filtered camera card uses - that red
-- means "nothing here can play", which a blend in progress is the opposite of.
local _BLEND_ACTIVE_COL = 0xFFCC66FF

-- Shown under the Camera row only while a column has no shot that fits the
-- selected lineup. The preview deliberately keeps showing the authored event
-- instead of substituting one of these, so the wording stays on what the
-- GAME does - both fallbacks have more than one possible outcome, and a
-- sprite that is not on the timeline would read as a preview bug.
-- Body text rather than a tooltip, so it lives here and not in TIPS.
local _FALLBACK_NOTE =
    'No stacked camera shot matches the current band. In game, the camera system falls back '
 .. 'to a generic full band camera shot - [coop_all_behind], [coop_all_far] or [coop_all_near]. '
 .. 'A normal (coop) duo shot is converted to a single shot of the remaining band member when '
 .. 'possible by the game. Directed cuts have no documented duo-to-single fallback.'

local _muted_cache = nil  -- GetMutedInstruments() result; mute toggles bump
                          -- the project state count, so refreshes catch them

local function _refresh_preview()
    local t0 = r.time_precise()
    _preview_cache, _preview_error = GetVenueEventsForPreview()
    _muted_cache = GetMutedInstruments()
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

-- Every event sharing the PPQ position of events[idx], in MIDI order.
-- Authors stack several camera shots on one tick so at least one fits
-- whatever lineup the song ends up with, so a "spot" is a group, not an
-- event - which of them plays is PickPriorityCameraEvent's call.
local function _group_at(events, idx)
    local ppq = events[idx].ppq
    local first, last = idx, idx
    while first > 1 and events[first - 1].ppq == ppq do first = first - 1 end
    while last < #events and events[last + 1].ppq == ppq do last = last + 1 end
    local group = {}
    for i = first, last do group[#group + 1] = events[i] end
    return group, first, last
end

-- Events are stored in MIDI order (chronological). Return the prev/current/next
-- PPQ groups relative to the given playhead time, so stacked events never split
-- across the three columns.
local function _find_prev_current_next(events, time)
    if not events or #events == 0 then return nil, nil, nil end
    local curr_idx = nil
    for i, ev in ipairs(events) do
        if ev.t <= time then curr_idx = i else break end
    end
    if not curr_idx then return nil, nil, (_group_at(events, 1)) end

    local curr, first, last = _group_at(events, curr_idx)
    local prev = first > 1      and (_group_at(events, first - 1)) or nil
    local next_group = last < #events and (_group_at(events, last + 1)) or nil

    return prev, curr, next_group
end

-- Build the muted table for filtering from the current combo selection.
local function _combo_muted(combo)
    return { [_COMBO_ABSENT[combo]] = true }
end

-- Pick the event to display for one PPQ group.
-- Returns: display_ev, is_filtered
--   is_filtered=false → display_ev is what the game would play here
--   is_filtered=true  → nothing in the group fits the lineup; display_ev is the
--                       group's last event, shown in red with _FALLBACK_NOTE
-- Camera groups resolve by the documented shot priority (venue_camera_priority.lua);
-- lighting and post-process have no priority order, so their last event wins.
local function _resolve_group(group, muted)
    if not group or #group == 0 then return nil, false end
    if not muted then return group[#group], false end
    local chosen = PickPriorityCameraEvent(group, muted)
    if chosen then return chosen, false end
    return group[#group], true
end

-- How the event in a column hands over to whatever follows it, as one line under
-- the timestamp. Returns text, color (nil color = TextDisabled).
--
-- Lighting and post proc arrive from AnnotateVenueBlends (venue.lua) already
-- collapsed - a blend anchor restates a preset that is already running, so it is
-- never a card of its own - and carry the fields read here. Camera events have
-- none of them and always get the blank line: a camera cut never fades.
--
-- The next_t upper bound is what keeps "blending now" out of the Previous column
-- without that column having to know it is the Previous one: past the change, the
-- playhead is no longer inside the fade window.
local function _transition_line(ev, playhead)
    if not ev or not ev.next_t then return ' ' end
    if ev.blend_out_t then
        if playhead >= ev.blend_out_t and playhead < ev.next_t then
            return '-> blending now', _BLEND_ACTIVE_COL
        end
        return '-> blends into next'
    end
    return '-> hard cut to next'
end

-- Draw one labeled column (header + event card or placeholder).
-- NOTE: r.ImGui_Separator inside a BeginGroup expands to full window width,
-- breaking the side-by-side layout - use Spacing instead, and draw the
-- separator once outside all groups (in _draw_category_row).
-- Dummy reserves the sprite footprint so all columns stay the same width
-- even when there is no event or no spritesheet installed.
local function _draw_column(header, ev, category, scale, is_filtered, combo_name, playhead)
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
        -- Always drawn, blank when there is nothing to say: a column one text line
        -- shorter than its neighbours would push its sprite out of alignment.
        local tline, tcol = _transition_line(ev, playhead)
        if tcol then
            r.ImGui_TextColored(ctx, tcol, tline)
        else
            r.ImGui_TextDisabled(ctx, tline)
        end
        if tline ~= ' ' then Tooltip(TIPS.venue_preview_blend) end
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

-- prev/curr/next are PPQ groups (arrays of events), not single events.
local function _draw_category_row(label, prev_grp, curr_grp, next_grp, category, scale,
                                  muted, combo_name, playhead)
    SectionHeader(label)
    r.ImGui_Separator(ctx)  -- full-width separator drawn outside groups (safe here)
    local any_filtered = false
    local function col(header, group)
        local ev, filtered = _resolve_group(group, muted)
        if filtered then any_filtered = true end
        _draw_column(header, ev, category, scale, filtered, combo_name, playhead)
    end
    if S.venue_preview_show_mode == _SHOW_CURRENT_ONLY then
        col('Current', curr_grp)
    else
        col('Previous', prev_grp)
        r.ImGui_SameLine(ctx)
        col('Current',  curr_grp)
        r.ImGui_SameLine(ctx)
        col('Next',     next_grp)
    end
    if any_filtered then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, _FALLBACK_NOTE)
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

    local lbl_col = LabelColWidth({ 'Players', 'Preview size', 'Sprites', 'Show' })
    local radio_w = RadioGroupWidth({
        'Bass + Guitar', 'Bass + Keys', 'Guitar + Keys', '1x', '2x',
        'Animated', 'Still', 'Current only', 'Surrounding events',
    })

    r.ImGui_Text(ctx, 'Players')
    r.ImGui_SameLine(ctx, lbl_col)
    local _t_vpc = TIPS.venue_preview_combo
    if r.ImGui_RadioButton(ctx, 'Bass + Guitar##vpc', S.venue_preview_combo == _COMBO_BG) then
        S.venue_preview_combo = _COMBO_BG
    end
    Tooltip(_t_vpc)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Bass + Keys##vpc', S.venue_preview_combo == _COMBO_BK) then
        S.venue_preview_combo = _COMBO_BK
    end
    Tooltip(_t_vpc)
    r.ImGui_SameLine(ctx, lbl_col + 2 * radio_w)
    if r.ImGui_RadioButton(ctx, 'Guitar + Keys##vpc', S.venue_preview_combo == _COMBO_GK) then
        S.venue_preview_combo = _COMBO_GK
    end
    Tooltip(_t_vpc)
    do
        local muted_real = _muted_cache or GetMutedInstruments()
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
    r.ImGui_SameLine(ctx, lbl_col)
    local _t_vpts = TIPS.venue_preview_scale
    if r.ImGui_RadioButton(ctx, '1x##vpts', S.venue_preview_tab_scale == 1) then
        S.venue_preview_tab_scale = 1
    end
    Tooltip(_t_vpts)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, '2x##vpts', S.venue_preview_tab_scale == 2) then
        S.venue_preview_tab_scale = 2
    end
    Tooltip(_t_vpts)

    r.ImGui_Text(ctx, 'Sprites')
    r.ImGui_SameLine(ctx, lbl_col)
    local _t_vpan = TIPS.venue_preview_animate
    if r.ImGui_RadioButton(ctx, 'Animated##vpan', _preview_animate) then
        _preview_animate = true
    end
    Tooltip(_t_vpan)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Still##vpan', not _preview_animate) then
        _preview_animate = false
    end
    Tooltip(_t_vpan)

    r.ImGui_Text(ctx, 'Show')
    r.ImGui_SameLine(ctx, lbl_col)
    local _t_vpshw = TIPS.venue_preview_show_mode
    if r.ImGui_RadioButton(ctx, 'Current only##vpshw', S.venue_preview_show_mode == _SHOW_CURRENT_ONLY) then
        S.venue_preview_show_mode = _SHOW_CURRENT_ONLY
    end
    Tooltip(_t_vpshw)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Surrounding events##vpshw', S.venue_preview_show_mode == _SHOW_SURROUNDING) then
        S.venue_preview_show_mode = _SHOW_SURROUNDING
    end
    Tooltip(_t_vpshw)

    if not VenueSpriteFoldersFound() then
        r.ImGui_TextDisabled(ctx, '- no spritesheets installed')
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
        r.ImGui_TextDisabled(ctx, 'No data - reading\xe2\x80\xa6')
        return
    end

    local playing  = (r.GetPlayState() & 1) == 1
    local playhead = playing and r.GetPlayPosition() or r.GetCursorPosition()
    local scale    = S.venue_preview_tab_scale

    -- Each of these is a PPQ group (array of stacked events), not one event.
    local cam_p, cam_c, cam_n = _find_prev_current_next(_preview_cache.camera,   playhead)
    local lt_p,  lt_c,  lt_n  = _find_prev_current_next(_preview_cache.lighting, playhead)
    local pp_p,  pp_c,  pp_n  = _find_prev_current_next(_preview_cache.postproc, playhead)

    local muted      = _combo_muted(S.venue_preview_combo)
    local combo_name = _COMBO_NAMES[S.venue_preview_combo]

    _draw_category_row('Camera',       cam_p, cam_c, cam_n, 'Camera',   scale,
                       muted, combo_name, playhead)
    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)
    _draw_category_row('Lighting',     lt_p,  lt_c,  lt_n,  'Lighting', scale,
                       nil, nil, playhead)
    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)
    _draw_category_row('Post-Process', pp_p,  pp_c,  pp_n,  'PostProc', scale,
                       nil, nil, playhead)
end
