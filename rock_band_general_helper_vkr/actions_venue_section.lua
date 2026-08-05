-- Section-by-section venue event generator.
-- Requires: venue_generator.lua (ClearVenueTextEventsInRange, ClearVenueNonCameraEventsInRange,
--                                 ClearVenueExceptLPInRange, FindActiveVenuePresetsBefore),
--           venue_camera.lua (FindCompanion, …),
--           venue_lighting.lua (GenerateThemedSectionEvents, FindNextMeasureStartPpq,
--                               CollectVocalPhraseStarts, SnapPpqToHalfBeat),
--           venue_awareness.lua (ReadEventSections, ReadInstrumentPlayStates),
--           venue_themes.lua (GetSectionPreset, BuildLightingPool, BuildPostprocPool,
--                             GetThemeCameraInterval),
--           helpers.lua (FindTrackByName), r, S, TIPS (globals)

local PROJ_SEC_KEY = 'vsec_v1'

-- ---------------------------------------------------------------------------
-- Data helpers

function SectionKey(sec)
    return sec.name .. '_' .. (sec.num or '')
end

function DefaultConfig()
    return {
        lighting      = '',
        postproc      = '',
        keyframe_rate = 2,
        light_blendin = 0,
        pp_blendin    = 0,
        dircut        = '',
        bonusfx       = false,
    }
end

-- ---------------------------------------------------------------------------
-- Persistence

function SaveSectionConfigs()
    local parts = {}
    for key, cfg in pairs(S.venue_sec_configs) do
        local bonusfx_int = cfg.bonusfx and 1 or 0
        parts[#parts + 1] = key .. '=' ..
            (cfg.lighting or '')      .. '|' ..
            (cfg.postproc or '')      .. '|' ..
            (cfg.keyframe_rate or 2)  .. '|' ..
            (cfg.light_blendin or 0)  .. '|' ..
            (cfg.pp_blendin or 0)     .. '|' ..
            (cfg.dircut or '')        .. '|' ..
            bonusfx_int
    end
    r.SetProjExtState(0, 'RBHelperVKR', PROJ_SEC_KEY, table.concat(parts, ';'))
end

function LoadSectionConfigs()
    S.venue_sec_configs = {}
    local _, str = r.GetProjExtState(0, 'RBHelperVKR', PROJ_SEC_KEY)
    if not str or str == '' then return end
    for entry in str:gmatch('[^;]+') do
        local key, val = entry:match('^([^=]+)=(.+)$')
        if key and val then
            local fields = {}
            for f in val:gmatch('[^|]*') do fields[#fields + 1] = f end
            if #fields >= 7 then
                S.venue_sec_configs[key] = {
                    lighting      = fields[1],
                    postproc      = fields[2],
                    keyframe_rate = tonumber(fields[3]) or 2,
                    light_blendin = tonumber(fields[4]) or 0,
                    pp_blendin    = tonumber(fields[5]) or 0,
                    dircut        = fields[6],
                    bonusfx       = fields[7] == '1',
                }
            end
        end
    end
end

-- ---------------------------------------------------------------------------

function LoadVenueSections()
    local track, item = FindNamedTrackMIDI('VENUE')
    if not track then
        S.status = 'No VENUE track found - cannot read sections.'
        return
    end
    local item_end = r.GetProjectLength(0)
    if item then
        item_end = r.GetMediaItemInfo_Value(item, 'D_POSITION') +
                   r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    end
    local secs = ReadEventSections(item_end)
    if not secs or #secs == 0 then
        S.venue_sections = {}
        S.status = 'No [prc_*] sections found on EVENTS track.'
        return
    end
    S.venue_sections = secs
    S.venue_sec_idx  = 1
    LoadSectionConfigs()
    S.status = ('Loaded %d sections.'):format(#secs)
end

-- ---------------------------------------------------------------------------

function GenerateSectionEvent()
    if not S.venue_sections or #S.venue_sections == 0 then
        S.status     = 'No sections loaded - click Refresh first.'
        S.last_result = nil
        return
    end
    if S.venue_sec_idx < 1 or S.venue_sec_idx > #S.venue_sections then
        S.status     = 'Invalid section selection.'
        S.last_result = nil
        return
    end

    local track, item, take = FindNamedTrackMIDI('VENUE')
    if not track then
        S.status     = 'No VENUE track found.'
        S.last_result = nil
        return
    end
    if not item then
        S.status     = 'No MIDI item on VENUE track.'
        S.last_result = nil
        return
    end

    local sec = S.venue_sections[S.venue_sec_idx]
    local cfg
    if S.venue_sec_mode == 1 then
        local _th    = S.venue_themes and S.venue_themes[S.venue_sec_tmpl_idx]
        local _pr    = _th and _th.section_presets and
            (_th.section_presets[sec.name] or _th.section_presets['default'])
        if _pr then
            local lp = _pr.allowed_lightpresets
            local pp = _pr.allowed_postprocs
            cfg = {
                lighting      = lp and lp[math.random(#lp)] or '',
                postproc      = pp and pp[math.random(#pp)] or '',
                keyframe_rate = _pr.keyframe_rate       or 2,
                light_blendin = _pr.lightpreset_blendin or 0,
                pp_blendin    = _pr.postproc_blendin    or 0,
                dircut        = _pr.dircut_at_start     or '',
                bonusfx       = _pr.bonusfx_at_start    or false,
            }
        else
            cfg = DefaultConfig()
        end
    else
        cfg = S.venue_sec_configs[SectionKey(sec)] or DefaultConfig()
    end

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')

    local ppq = GetTakePPQPerQN(take)
    local sixteenth_ticks = ppq / 4

    local sec_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
    local sec_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, sec.t_end)
    local item_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, item_start_sec)

    -- Preset state going into this section, read BEFORE anything is cleared (the clear
    -- below reaches into the blend zone and would remove the very events being looked
    -- up). Feeds GenerateThemedSectionEvents' `incoming` so the blend duplicates
    -- re-state whatever was actually playing - Themes gen gets this from its own
    -- section walk, but Section gen only ever sees one section.
    local in_lt_text, in_lt_ppq, in_pp_text, in_pp_ppq =
        FindActiveVenuePresetsBefore(take, sec_start_ppq)

    local max_blendin    = math.max(cfg.light_blendin, cfg.pp_blendin)
    local clear_start_ppq = math.max(item_start_ppq, sec_start_ppq - max_blendin * ppq)
    -- Never clear back over the incoming preset's own events: a previous section
    -- shorter than this section's blendin would otherwise lose its lighting/postproc
    -- outright, since EmitBlendDuplicates refuses to place a duplicate at or before
    -- the event it copies.
    if in_lt_ppq and clear_start_ppq <= in_lt_ppq then clear_start_ppq = in_lt_ppq + 1 end
    if in_pp_ppq and clear_start_ppq <= in_pp_ppq then clear_start_ppq = in_pp_ppq + 1 end

    -- Camera setup
    local muted       = GetMutedInstruments()
    local active_coop = FilterPool(COOP_POOL, muted, GetCoopRequiredInstruments)

    local coop_venue_pool, coop_solo_pools, coop_duo_pools = CategorizeCoopPool(active_coop)
    local active_coop_set = {}
    for _, ev in ipairs(active_coop) do active_coop_set[ev] = true end
    local coop_opts = {
        venue_pool      = coop_venue_pool,
        solo_pools      = coop_solo_pools,
        duo_pools       = coop_duo_pools,
        active_coop_set = active_coop_set,
        keys_failsafe   = not muted.k and not muted.g and not muted.b,
        suffix_pools    = BuildSuffixPools(coop_solo_pools),
    }

    -- Convert play-state timelines to range-relative 16ths (range = sec_start_ppq)
    local play_states_raw, no_data_letters = ReadInstrumentPlayStates()
    local play_states_16ths = {}
    for letter, timeline in pairs(play_states_raw) do
        if timeline then
            local converted = {}
            for _, ev in ipairs(timeline) do
                local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, ev.t)
                local p16 = (ppq_pos - sec_start_ppq) / sixteenth_ticks
                converted[#converted + 1] = { pos_16ths = p16, is_active = ev.is_active }
            end
            play_states_16ths[letter] = converted
        end
    end
    coop_opts.play_states = play_states_16ths

    -- Convert sing-note timelines (VENUE-PPQ to range-relative 16ths)
    local sing_notes_raw    = ReadSingNoteTimelines(take)
    local sing_states_16ths = {}
    for letter, notes in pairs(sing_notes_raw) do
        local events = {}
        for _, note in ipairs(notes) do
            local s16 = (note.sppq - sec_start_ppq) / sixteenth_ticks
            local e16 = (note.eppq - sec_start_ppq) / sixteenth_ticks
            events[#events + 1] = { pos_16ths = s16, is_singing = true  }
            events[#events + 1] = { pos_16ths = e16, is_singing = false }
        end
        table.sort(events, function(a, b) return a.pos_16ths < b.pos_16ths end)
        sing_states_16ths[letter] = events
    end
    coop_opts.sing_states = sing_states_16ths

    -- Vocal phrase start pacing mode (S.venue_cam_pacing == 7): camera cadence follows
    -- PART VOCALS phrase-marker (pitch 105) note starts inside this section instead of a
    -- fixed interval - see GenerateCameraEvents' phrase_positions_16ths param.
    local phrase_mode = (S.venue_cam_pacing == 7)

    -- Camera interval: user override, else (template mode) the template theme's pacing.
    -- Suppressed in phrase mode - it has no interval concept.
    local bpm = r.Master_GetTempo()
    local cam_interval = ResolveUserCamInterval(bpm)
    if not cam_interval and S.venue_sec_mode == 1 and not phrase_mode then
        local _tmpl_th = S.venue_themes and S.venue_themes[S.venue_sec_tmpl_idx]
        if _tmpl_th and _tmpl_th.camera_pacing then
            cam_interval = GetThemeCameraInterval(_tmpl_th.camera_pacing, bpm)
        end
    end

    -- Phrase positions, section-relative in 16ths - possibly empty (phrase mode active
    -- but no phrase markers found in this section), never nil once phrase_mode is true.
    local phrase_positions_16ths = nil
    if phrase_mode then
        local raw_positions = CollectVocalPhraseStarts(take, sec_start_ppq, sec_end_ppq)
        phrase_positions_16ths = {}
        for _, p in ipairs(raw_positions) do
            phrase_positions_16ths[#phrase_positions_16ths + 1] =
                (p - sec_start_ppq) / sixteenth_ticks
        end
    end

    -- Forced dircut at section start (pos_16ths = 0 = sec_start)
    local forced_cuts = nil
    if cfg.dircut ~= '' then
        forced_cuts = { { pos_16ths = 0, text = '[' .. cfg.dircut .. ']' } }
    end

    -- Synthetic theme for GenerateThemedSectionEvents
    local syn_theme = nil
    if cfg.lighting ~= '' or cfg.postproc ~= '' then
        syn_theme = {
            section_presets = {
                default = {
                    allowed_lightpresets = cfg.lighting ~= '' and { cfg.lighting } or nil,
                    allowed_postprocs    = cfg.postproc ~= '' and { cfg.postproc } or nil,
                    lightpreset_blendin  = cfg.light_blendin,
                    postproc_blendin     = cfg.pp_blendin,
                    keyframe_rate        = cfg.keyframe_rate > 0 and cfg.keyframe_rate or nil,
                }
            }
        }
    end

    -- half-beat snap helper. no_snap: skip snapping - keyframe ctrl_events are already
    -- placed on their own alignment grid (possibly finer than half-beat, e.g. quarter-beat
    -- instrument-aware modes) by GenerateThemedSectionEvents; re-snapping to half-beat would
    -- collapse those finer positions onto the nearest half-beat/beat. A [first] carrying a
    -- lighting event's tick is pre-snapped by SnapPpqToHalfBeat there so it still lands on
    -- that event exactly.
    local function insert_snapped(abs_ppq, text, no_snap)
        local snapped = no_snap and abs_ppq or SnapPpqToHalfBeat(abs_ppq, ppq)
        r.MIDI_InsertTextSysexEvt(take, false, false, snapped, 1, text)
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    -- Blendin zone + section start: clear LP/keyframe/bonusfx, preserve previous section's camera
    ClearVenueNonCameraEventsInRange(take, clear_start_ppq, sec_start_ppq + 1)
    -- Section body: clear camera/keyframe/bonusfx, preserve LP (may be next section's blendin)
    ClearVenueExceptLPInRange(take, sec_start_ppq, sec_end_ppq)

    local total_inserted = 0

    -- Song-start bookends (same as GenerateVenueEvents; only fire if inside section range)
    local last_bookend_16ths     = nil
    local bookend_companion_count = 0
    -- Set of event strings banned for the next pick (see PickRandom) - chains through the
    -- bookends into GenerateCameraEvents so the regular loop's first cut doesn't immediately
    -- repeat whatever the bookends just placed.
    local last_spot = {}
    if #coop_venue_pool > 0 then
        local song_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, item_start_sec)
        local bk_m2_ppq      = FindNextMeasureStartPpq(take, song_start_ppq, ppq)
        local bk_m3_ppq      = FindNextMeasureStartPpq(take, bk_m2_ppq, ppq)

        if song_start_ppq >= sec_start_ppq and song_start_ppq < sec_end_ppq then
            local tick    = math.floor(song_start_ppq - sec_start_ppq + 0.5)
            local m1_text = PickRandom(coop_venue_pool, nil)
            insert_snapped(sec_start_ppq + tick, m1_text)
            total_inserted = total_inserted + 1
            last_bookend_16ths = tick / sixteenth_ticks
            last_spot           = { [m1_text] = true }
        end

        if bk_m3_ppq >= sec_start_ppq and bk_m3_ppq < sec_end_ppq then
            local m3_tick = math.floor(bk_m3_ppq - sec_start_ppq + 0.5)
            local m3_16ths = m3_tick / sixteenth_ticks
            local m3_cursors = {}
            for letter, _ in pairs(coop_opts.play_states) do m3_cursors[letter] = 1 end
            local m3_sing_cursors = {}
            for letter in pairs(coop_opts.sing_states) do m3_sing_cursors[letter] = 1 end
            local m3_idle, m3_all_idle = ComputeIdleState(coop_opts, m3_cursors, m3_16ths)
            local m3_singing           = ComputeSingState(coop_opts, m3_sing_cursors, m3_16ths)
            local m3_gw   = m3_all_idle and { solo = 30, duo = 10, venue = 60 } or nil
            local m3_text = WeightedPickCoopEvent(
                coop_opts.venue_pool, coop_opts.solo_pools,
                coop_opts.duo_pools, last_spot, m3_idle, m3_gw,
                coop_opts.suffix_pools, m3_singing)
            if m3_text then
                local prev_spot = last_spot
                insert_snapped(sec_start_ppq + m3_tick, m3_text)
                total_inserted = total_inserted + 1
                last_bookend_16ths = m3_16ths
                last_spot           = { [m3_text] = true }

                if coop_opts.keys_failsafe then
                    local m3_companion = FindCompanion(m3_text, coop_opts, m3_idle, m3_singing, prev_spot)
                    if m3_companion then
                        insert_snapped(sec_start_ppq + m3_tick, m3_companion)
                        total_inserted         = total_inserted + 1
                        bookend_companion_count = bookend_companion_count + 1
                        last_spot[m3_companion] = true
                    end
                end
            end
        end
    end

    -- Inherit pacing from last camera event of the previous section when no song-start bookend.
    -- Not applicable in phrase mode - it has no interval to inherit.
    if not phrase_mode and last_bookend_16ths == nil then
        local ref_interval = cam_interval or CAM_INTERVAL_16THS
        local lookback_ppq = math.floor(3 * ref_interval * sixteenth_ticks)
        local search_start = math.max(item_start_ppq, sec_start_ppq - lookback_ppq)
        local _, _, _, tc  = r.MIDI_CountEvts(take)
        local prev_cam_ppq = nil
        for i = 0, tc - 1 do
            local ok, _, _, ev_ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
            if ok and evt_type == 1 and ev_ppq >= search_start and ev_ppq < sec_start_ppq then
                if msg:find('^%[coop_') or msg:find('^%[directed_') then
                    if not prev_cam_ppq or ev_ppq > prev_cam_ppq then
                        prev_cam_ppq = ev_ppq
                    end
                end
            end
        end
        if prev_cam_ppq then
            last_bookend_16ths = (prev_cam_ppq - sec_start_ppq) / sixteenth_ticks
        end
    end

    -- Camera events scoped to the section. In phrase mode, start_min/max are left nil -
    -- phrase mode simply uses every phrase start inside [sec_start_ppq, sec_end_ppq),
    -- no bookend-avoidance window needed.
    local cam_start_min, cam_start_max
    if not phrase_mode then
        local range_offset_16ths = math.floor((sec_start_ppq - item_start_ppq) / sixteenth_ticks)
        cam_start_min = range_offset_16ths >= CAM_START_MIN_16THS and CAM_SHORT_START_MIN_16THS or nil
        cam_start_max = range_offset_16ths >= CAM_START_MIN_16THS and CAM_SHORT_START_MAX_16THS or nil
        if last_bookend_16ths then
            local ref = cam_interval or CAM_INTERVAL_16THS
            local _cj = S.venue_cam_pacing_jitter and CAM_JITTER or 0
            local lo  = math.floor(last_bookend_16ths + ref * (1 - _cj))
            local hi  = math.floor(last_bookend_16ths + ref * (1 + _cj))
            lo = math.max(lo, 0)
            hi = math.max(hi, math.max(lo, 1))
            cam_start_min = cam_start_min and math.max(cam_start_min, lo) or lo
            cam_start_max = cam_start_max and math.max(cam_start_max, hi) or hi
        end
    end

    local total_16ths = math.floor((sec_end_ppq - sec_start_ppq) / sixteenth_ticks)
    local cam_events  = GenerateCameraEvents(active_coop, {}, total_16ths, ppq,
                                             cam_interval, forced_cuts, nil,
                                             cam_start_min, cam_start_max, coop_opts, last_spot,
                                             phrase_positions_16ths)
    local cam_coop_count     = 0
    local cam_directed_count = 0
    local cam_companion_count = 0
    for _, ev in ipairs(cam_events) do
        insert_snapped(sec_start_ppq + ev.tick, ev.text)
        total_inserted = total_inserted + 1
        if ev.is_directed  then cam_directed_count  = cam_directed_count  + 1 end
        if ev.is_companion then cam_companion_count  = cam_companion_count + 1 end
        if not ev.is_directed and not ev.is_companion then cam_coop_count = cam_coop_count + 1 end
    end
    cam_companion_count = cam_companion_count + bookend_companion_count

    -- Lighting / postproc / keyframes via GenerateThemedSectionEvents
    local lt_count   = 0
    local ctrl_count = 0
    local pp_count   = 0
    if syn_theme then
        local lt_events, ctrl_events, pp_events = GenerateThemedSectionEvents(
            { sec }, syn_theme, take, clear_start_ppq, sec_end_ppq, ppq,
            (in_lt_text or in_pp_text) and {
                lt_text  = in_lt_text, lt_ppq = in_lt_ppq,
                pp_text  = in_pp_text, pp_ppq = in_pp_ppq,
                -- The outgoing section's own rate isn't recoverable from the track,
                -- so the duplicate's keyframes use this section's - it only governs
                -- the handful of beats inside the blend zone.
                kf_beats = cfg.keyframe_rate > 0 and cfg.keyframe_rate or nil,
            } or nil)
        for _, ev in ipairs(lt_events)   do
            insert_snapped(clear_start_ppq + ev.tick, ev.text)
            total_inserted = total_inserted + 1
            lt_count = lt_count + 1
        end
        for _, ev in ipairs(ctrl_events) do
            insert_snapped(clear_start_ppq + ev.tick, ev.text, true)
            total_inserted = total_inserted + 1
            ctrl_count = ctrl_count + 1
        end
        for _, ev in ipairs(pp_events) do
            insert_snapped(clear_start_ppq + ev.tick, ev.text)
            total_inserted = total_inserted + 1
            pp_count = pp_count + 1
        end
    end

    -- BonusFX at section start
    if cfg.bonusfx then
        insert_snapped(sec_start_ppq, '[bonusfx]')
        total_inserted = total_inserted + 1
    end

    r.Undo_EndBlock2(0, 'RB Generate Section: ' .. sec.name, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    -- Build section display name for status (matches venue_awareness.lua formatting)
    local _cap     = sec.name:sub(1,1):upper() .. sec.name:sub(2)
    local sec_label = sec.num and (_cap .. ' ' .. sec.num) or _cap

    S.status = ('Generated %d events for %s.'):format(total_inserted, sec_label)

    local lines = {}
    lines[#lines + 1] = ('Generated %d total events for section: %s'):format(total_inserted, sec_label)
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('Camera (coop):      %d'):format(cam_coop_count)
    if cam_directed_count > 0 then
        lines[#lines + 1] = ('Camera (directed):  %d'):format(cam_directed_count)
    end
    if cam_companion_count > 0 then
        lines[#lines + 1] = ('Camera (companion): %d'):format(cam_companion_count)
    end
    if phrase_mode and #phrase_positions_16ths == 0 then
        lines[#lines + 1] = 'No PART VOCALS phrase markers found in this section - the ' ..
                            'recurring camera loop was skipped (bookend/forced-cut events, ' ..
                            'if any, were still placed).'
    end
    if lt_count > 0 then
        lines[#lines + 1] = ('Lighting:           %d'):format(lt_count)
    end
    if ctrl_count > 0 then
        lines[#lines + 1] = ('Control [first]/[next]: %d'):format(ctrl_count)
    end
    if pp_count > 0 then
        lines[#lines + 1] = ('Post-process:       %d'):format(pp_count)
    end
    if cfg.bonusfx then
        lines[#lines + 1] = 'Bonus FX:           1'
    end
    if last_bookend_16ths then
        lines[#lines + 1] = 'Song-start bookend: included'
    end
    lines[#lines + 1] = ''

    local warn_no_data = {}
    for _, l in ipairs(no_data_letters) do
        if not muted[l] then warn_no_data[#warn_no_data + 1] = INST_LETTER_NAMES[l] or l end
    end
    table.sort(warn_no_data)
    if #warn_no_data > 0 then
        lines[#lines + 1] = 'Note: ' .. table.concat(warn_no_data, ', ') ..
                            ' have no play-state events - treated as always active.'
    end

    local muted_names = {}
    for letter in pairs(muted) do muted_names[#muted_names + 1] = INST_LETTER_NAMES[letter] or letter end
    table.sort(muted_names)
    if #muted_names > 0 then
        lines[#lines + 1] = 'Muted/absent: ' .. table.concat(muted_names, ', ')
    end

    S.last_result = table.concat(lines, '\n')
end
