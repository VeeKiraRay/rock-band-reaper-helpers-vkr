-- Demo venue generator action.
-- Requires: r, S, DIRECTED_POOL, COOP_POOL, LIGHTING_NAMES, POSTPROC_NAMES,
--           MANUAL_LIGHTING_SET, DIRECTED_SPRITE_NAMES, POSTPROC_SPRITE_NAMES (globals)

-- Returns the instrument letters required by a coop camera event.
-- Mirrors GetCoopRequiredInstruments() in venue_awareness.lua.
-- Global so ui.lua can call it for the filtered duration estimate.
function CoopRequired(ev)
    local inner = ev:match('^%[coop_(.+)%]$')
    if not inner then return {} end
    if inner:match('^all') or inner:match('^front') then return {} end
    local code = inner:match('^(%a+)_')
    if not code then return {} end
    local valid = {d=true, v=true, b=true, g=true, k=true}
    local req = {}
    for i = 1, #code do
        local ch = code:sub(i, i)
        if valid[ch] then req[#req + 1] = ch end
    end
    return req
end

-- Returns the instrument letters required by a directed cut event.
-- Mirrors GetDirectedRequiredInstruments() in venue_awareness.lua.
-- Global so ui.lua can call it for the filtered duration estimate.
function DirectedRequired(ev)
    local inner = ev:match('^%[directed_(.+)%]$')
    if not inner then return {} end
    if inner:match('^all') or inner == 'stagedive' or inner == 'crowdsurf'
        or inner == 'crowd' then return {} end
    if inner == 'crowd_b' then return {'b'} end
    if inner == 'crowd_g' then return {'g'} end
    if inner:match('^duo_') then
        local part = inner:match('^duo_(.+)$')
        if part == 'drums'  then return {'d', 'v'} end
        if part == 'bass'   then return {'b', 'v'} end
        if part == 'guitar' then return {'g', 'v'} end
        if #part == 2 then
            local valid = {d=true, v=true, b=true, g=true, k=true}
            local req = {}
            for i = 1, 2 do
                local ch = part:sub(i, i)
                if valid[ch] then req[#req + 1] = ch end
            end
            return req
        end
        return {}
    end
    if inner:match('^drums')  then return {'d'} end
    if inner:match('^vocals') then return {'v'} end
    if inner:match('^bass')   then return {'b'} end
    if inner:match('^guitar') then return {'g'} end
    if inner:match('^keys')   then return {'k'} end
    return {}
end

-- Returns a muted-letter table for the given combo constant.
-- Global so ui.lua can reuse it for the filtered window count.
function MutedFromCombo(combo)
    if combo == DEMO_CAM_COMBO_BG then return {k = true}  -- no Keys
    elseif combo == DEMO_CAM_COMBO_BK then return {g = true}  -- no Guitar
    elseif combo == DEMO_CAM_COMBO_GK then return {b = true}  -- no Bass
    end
    return {}
end

-- Normalize a bare event name to the expected spritesheet filename key.
-- Mirrors NormalizeSpriteKey() in venue_sprites.lua.
local function SpriteNormKey(category, bare_name)
    if category == 'Camera' then
        return DIRECTED_SPRITE_NAMES[bare_name]
            or bare_name:gsub('[_ ]', ''):lower()
    elseif category == 'Lighting' then
        return bare_name:gsub('[_ ]', ''):lower()
    else  -- PostProc
        local bare = bare_name:gsub('%.pp$', '')
        return POSTPROC_SPRITE_NAMES[bare]
            or bare:gsub('[_ ]', ''):lower()
    end
end

local function FindVenueTrack()
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetTrackName(t)
        if name == 'VENUE' then return t end
    end
    return nil
end

local function FindOrCreateEventsTrack()
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetTrackName(t)
        if name == 'EVENTS' then return t end
    end
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    local t = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(t, 'P_NAME', 'EVENTS', true)
    return t
end

local function FindOrCreateVenueTrack()
    local t = FindVenueTrack()
    if t then return t end
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    t = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(t, 'P_NAME', 'VENUE', true)
    return t
end

-- Find first MIDI item at or near t=0 on track, or nil.
local function FindMIDIItemAtStart(track)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local it = r.GetTrackMediaItem(track, i)
        if r.GetMediaItemInfo_Value(it, 'D_POSITION') < 0.001 then
            local tk = r.GetActiveTake(it)
            if tk and r.TakeIsMIDI(tk) then return it, tk end
        end
    end
    return nil, nil
end

local function InsertText(take, t_proj, msg)
    local ppq = r.MIDI_GetPPQPosFromProjTime(take, t_proj)
    r.MIDI_InsertTextSysexEvt(take, false, false, ppq, 1, msg, false)
end

local function ClearAllTextEvents(take)
    local _, _, _, tc = r.MIDI_CountEvts(take)
    for i = tc - 1, 0, -1 do
        local ok, _, _, _, evt_type = r.MIDI_GetTextSysexEvt(take, i)
        if ok and (evt_type == 1 or evt_type == 3) then
            r.MIDI_DeleteTextSysexEvt(take, i)
        end
    end
end

function GenerateDemoVenue()
    local bpm      = math.max(40, math.min(300, S.demo_bpm))
    local win_s    = math.max(2.0, math.min(30.0, S.demo_window_s))
    local mode     = S.demo_mode
    local beat_s    = 60.0 / bpm
    local measure_s = 4.0 * beat_s
    -- 2-measure pre-roll at 4/4: [coop_d_closeup_head] fires here so the
    -- capture has a visible sync cue; first cycling event starts at measure 3.
    local t_offset  = 2.0 * measure_s

    -- Resolve neutral layers from S indices
    local lt_name  = LIGHTING_NAMES[S.demo_lt_idx]  or 'loop_warm'
    local pp_name  = POSTPROC_NAMES[S.demo_pp_idx]  or 'ProFilm_a.pp'
    local cam_far  = COOP_POOL[S.demo_cam_far_idx]  or '[coop_all_far]'
    local cam_near = COOP_POOL[S.demo_cam_near_idx] or '[coop_all_near]'

    local lt_event = '[lighting (' .. lt_name .. ')]'
    local pp_event = '[' .. pp_name .. ']'

    -- Accumulate events and manifest entries
    local evts     = {}  -- {t, msg}
    local manifest = {}  -- {key, t_start, t_end, category, bare}

    local function E(t, msg) evts[#evts + 1] = {t = t, msg = msg} end
    local function M(key, ts, te, cat, bare)
        manifest[#manifest + 1] = {key = key, t_start = ts, t_end = te,
                                    cat = cat, bare = bare}
    end

    local total_dur = 0

    -- Sync cue at measure 1 (t=0): visible in the capture as a drummer-head
    -- closeup. When this cuts away to the first cycling event at measure 3
    -- the author knows where to start slicing the video.
    E(0, '[coop_d_closeup_head]')

    if mode == DEMO_MODE_CAMERA then
        -- Neutral lighting + pp at measure 1; directed cuts start at measure 3.
        -- Directed cuts need 4 measures each: they have variable pre-roll and
        -- some shots take longer to complete before yielding to the next event.
        -- Layout per window: directed cut at beat 0, reset [coop_d_closeup_head]
        -- at beat 13 (3m+1b), giving 3 beats of reset before the next cut fires.
        local cam_win_s    = 4.0 * measure_s
        local reset_offs_s = 3.0 * measure_s + beat_s  -- 3m+1b into the window
        E(0, lt_event)
        E(0, pp_event)
        -- Filter pool to the selected instrument combo (absent instrument excluded)
        local muted   = MutedFromCombo(S.demo_cam_combo)
        local slot    = 0
        for _, ev in ipairs(DIRECTED_POOL) do
            local req     = DirectedRequired(ev)
            local blocked = false
            for _, letter in ipairs(req) do
                if muted[letter] then blocked = true; break end
            end
            if not blocked then
                local t    = t_offset + slot * cam_win_s
                local bare = ev:match('^%[(.-)%]$') or ev
                E(t, ev)
                E(t + reset_offs_s, '[coop_d_closeup_head]')
                M(bare, t, t + cam_win_s, 'Camera', bare)
                slot = slot + 1
            end
        end
        total_dur = t_offset + slot * cam_win_s

    elseif mode == DEMO_MODE_COOP then
        -- Neutral lighting + pp at measure 1; coop shots start at measure 3.
        -- Coop shots are instant cuts with no variable pre-roll — 2 measures each.
        local coop_win_s = 2.0 * measure_s
        E(0, lt_event)
        E(0, pp_event)
        local muted = MutedFromCombo(S.demo_cam_combo)
        local slot  = 0
        for _, ev in ipairs(COOP_POOL) do
            local req     = CoopRequired(ev)
            local blocked = false
            for _, letter in ipairs(req) do
                if muted[letter] then blocked = true; break end
            end
            if not blocked then
                local t    = t_offset + slot * coop_win_s
                local bare = ev:match('^%[(.-)%]$') or ev
                E(t, ev)
                M(bare, t, t + coop_win_s, 'Camera', bare)
                slot = slot + 1
            end
        end
        total_dur = t_offset + slot * coop_win_s

    elseif mode == DEMO_MODE_LIGHTING then
        -- Neutral pp at measure 1; lighting presets start at measure 3.
        E(0, pp_event)
        local slot = 0
        for _, lt_i in ipairs(LIGHTING_NAMES) do
            local is_manual = MANUAL_LIGHTING_SET[lt_i]
            local lt_ev_i   = '[lighting (' .. lt_i .. ')]'

            -- kf_variants: nil = no keyframes; otherwise {interval_s, label_suffix}
            local kf_variants = is_manual
                and {{beat_s, '1beat'}, {beat_s * 2, '2beat'}}
                or  {{nil, ''}}

            for _, kfv in ipairs(kf_variants) do
                for _, cam_info in ipairs({{cam_far, 'far'}, {cam_near, 'near'}}) do
                    local t = t_offset + slot * win_s
                    E(t, lt_ev_i)
                    E(t, cam_info[1])
                    if kfv[1] then
                        -- [first] at window start, then [next] every kf_interval_s
                        E(t, '[first]')
                        local tf = t + kfv[1]
                        while tf < t + win_s - 0.05 do
                            E(tf, '[next]')
                            tf = tf + kfv[1]
                        end
                    end
                    local key_suffix = kfv[2] ~= '' and ('_' .. cam_info[2] .. '_' .. kfv[2])
                                                     or ('_' .. cam_info[2])
                    M(lt_i .. key_suffix, t, t + win_s, 'Lighting', lt_i)
                    slot = slot + 1
                end
            end
        end
        total_dur = t_offset + slot * win_s

    elseif mode == DEMO_MODE_POSTPROC then
        -- Neutral lighting at measure 1; each pp effect gets two consecutive windows:
        -- first with cam_far, then cam_near.  Camera alternates every window so no
        -- character drifts out of frame over a long static shot.
        E(0, lt_event)
        local slot = 0
        for _, pp_i in ipairs(POSTPROC_NAMES) do
            local bare  = pp_i:gsub('%.pp$', '')
            local pp_ev = '[' .. pp_i .. ']'
            for _, cam_info in ipairs({{cam_far, 'far'}, {cam_near, 'near'}}) do
                local t = t_offset + slot * win_s
                E(t, cam_info[1])
                E(t, pp_ev)
                M(bare .. '_' .. cam_info[2], t, t + win_s, 'PostProc', pp_i)
                slot = slot + 1
            end
        end
        total_dur = t_offset + slot * win_s
    end

    if total_dur == 0 or #evts == 0 then
        S.status = 'Demo: nothing to generate.'
        return
    end

    -- Warn (don't block) if total exceeds the recommended 20-minute ceiling
    local over_limit = total_dur > 1200

    -- Update project BPM at root tempo marker index 0
    if r.CountTempoTimeSigMarkers(0) > 0 then
        r.SetTempoTimeSigMarker(0, 0, 0, -1, -1, bpm, 4, 4, false)
    end

    local venue_track      = FindOrCreateVenueTrack()
    local events_track     = FindOrCreateEventsTrack()
    local item_dur         = total_dur + win_s  -- one extra window as tail buffer
    -- [end] 5 s after last VENUE window; EVENTS item covers through [end] + 1 s buffer
    local end_event_t      = total_dur + 5.0
    local events_item_dur  = end_event_t + 1.0

    local item,        take        = FindMIDIItemAtStart(venue_track)
    local events_item, events_take = FindMIDIItemAtStart(events_track)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    -- VENUE track
    if item then
        r.SetMediaItemLength(item, item_dur, true)
        ClearAllTextEvents(take)
    else
        item = r.CreateNewMIDIItemInProj(venue_track, 0, item_dur, false)
        take = r.GetActiveTake(item)
    end
    r.MIDI_InsertTextSysexEvt(take, false, false, 0, 3, 'VENUE', false)
    for _, ev in ipairs(evts) do
        InsertText(take, ev.t, ev.msg)
    end
    r.MarkTrackItemsDirty(venue_track, item)

    -- EVENTS track: clear everything, then write the three required events
    if events_item then
        r.SetMediaItemLength(events_item, events_item_dur, true)
        ClearAllTextEvents(events_take)
    else
        events_item = r.CreateNewMIDIItemInProj(events_track, 0, events_item_dur, false)
        events_take = r.GetActiveTake(events_item)
    end
    r.MIDI_InsertTextSysexEvt(events_take, false, false, 0, 3, 'EVENTS', false)
    InsertText(events_take, 0,                        '[prc_intro]')
    InsertText(events_take, 0,                        '[crowd_normal]')
    InsertText(events_take, t_offset,                 '[music_start]')
    InsertText(events_take, end_event_t - measure_s,  '[music_end]')
    InsertText(events_take, end_event_t,              '[end]')
    r.MarkTrackItemsDirty(events_track, events_item)

    r.Undo_EndBlock2(0, 'Generate demo venue project', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    -- Write manifest CSV to project folder
    local proj_path = r.GetProjectPath(0)
    local csv_written = false
    if proj_path and proj_path ~= '' then
        local mode_tag = (mode == DEMO_MODE_CAMERA   and 'camera')
                      or (mode == DEMO_MODE_COOP      and 'coop')
                      or (mode == DEMO_MODE_LIGHTING  and 'lighting')
                      or ('postproc_' .. lt_name:gsub('[_ ]', ''))
        local csv_path = proj_path .. '/' .. 'demo_manifest_' .. mode_tag .. '.csv'
        local f = io.open(csv_path, 'w')
        if f then
            f:write('event_key,window_start_s,window_end_s,sprite_norm_key,sprite_filename\n')
            for _, m in ipairs(manifest) do
                local norm = SpriteNormKey(m.cat, m.bare)
                f:write(string.format('%s,%.3f,%.3f,%s,%s_spritesheet.png\n',
                    m.key, m.t_start, m.t_end, norm, norm))
            end
            f:close()
            csv_written = true
            S.status = string.format('Done: %d windows, %.1f min.  Manifest: %s',
                #manifest, total_dur / 60, csv_path:match('[^\\/]+$'))
        end
    end
    if not csv_written then
        S.status = string.format('Done: %d windows, %.1f min.  Save project to write manifest.',
            #manifest, total_dur / 60)
    end

    local lines = {
        string.format('%d event windows generated across %.1f minutes.',
            #manifest, total_dur / 60),
        string.format('Pre-roll: [coop_d_closeup_head] at m1; events start at m3 (%.1f s).',
            t_offset),
        '',
        'Mode    : ' .. (mode == DEMO_MODE_CAMERA   and 'Camera'
                      or mode == DEMO_MODE_COOP      and 'Coop'
                      or mode == DEMO_MODE_LIGHTING  and 'Lighting'
                      or 'PostProc'),
        'BPM     : ' .. bpm .. '   Window: ' ..
            (mode == DEMO_MODE_CAMERA  and string.format('%.1f s (4 measures)', 4.0 * measure_s)
          or mode == DEMO_MODE_COOP    and string.format('%.1f s (2 measures)', 2.0 * measure_s)
          or (win_s .. ' s')),
        'Neutral : ' .. lt_name .. '  /  ' .. pp_name,
    }
    if mode == DEMO_MODE_LIGHTING or mode == DEMO_MODE_POSTPROC then
        lines[#lines + 1] = 'Cameras : far=' .. cam_far .. '  near=' .. cam_near
    end
    if over_limit then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'WARNING: total duration exceeds recommended 20-min limit.'
    end
    if csv_written then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Manifest CSV written to project folder.'
    else
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Save the project to a folder first to write the manifest CSV.'
    end
    S.last_result = table.concat(lines, '\n')
end
