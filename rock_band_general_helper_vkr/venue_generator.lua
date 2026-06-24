-- Venue event generator: main orchestration for GenerateVenueEvents.
-- Requires: venue_camera.lua and venue_lighting.lua loaded first.
-- Requires: GetMutedInstruments, FilterPool, GetCoopRequiredInstruments,
--           GetDirectedRequiredInstruments, FindTrackByName,
--           ReadEventSections, ReadInstrumentPlayStates, GetSectionPreset,
--           GetThemeCameraInterval, r, S (globals)

function ClearVenueTextEventsInRange(take, start_ppq, end_ppq)
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = text_count - 1, 0, -1 do
        local ok, _, _, ppq, evt_type = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq >= start_ppq and ppq < end_ppq then
            r.MIDI_DeleteTextSysexEvt(take, i)
        end
    end
end

-- Clears everything except camera events ([coop_*] / [directed_*]).
-- Use for the blendin zone before a section to preserve previous section's camera shots.
function ClearVenueNonCameraEventsInRange(take, start_ppq, end_ppq)
    local _, _, _, tc = r.MIDI_CountEvts(take)
    for i = tc - 1, 0, -1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq >= start_ppq and ppq < end_ppq then
            if not (msg:find('^%[coop_') or msg:find('^%[directed_')) then
                r.MIDI_DeleteTextSysexEvt(take, i)
            end
        end
    end
end

-- Clears everything except lighting ([lighting *]) and postproc (*.pp]).
-- Use for the section body to preserve adjacent section's blendin LP events.
function ClearVenueExceptLPInRange(take, start_ppq, end_ppq)
    local _, _, _, tc = r.MIDI_CountEvts(take)
    for i = tc - 1, 0, -1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq >= start_ppq and ppq < end_ppq then
            if not (msg:find('^%[lighting') or msg:find('%.pp%]$')) then
                r.MIDI_DeleteTextSysexEvt(take, i)
            end
        end
    end
end

-- ---------------------------------------------------------------------------

function GenerateVenueEvents()
    local track = FindTrackByName('VENUE')
    if not track then
        S.status     = 'No VENUE track found.'
        S.last_result = 'Could not find a track named "VENUE".\n\n' ..
                        'Make sure your Rock Band project has a VENUE track.'
        return
    end

    local item, take = nil, nil
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local it = r.GetTrackMediaItem(track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then item, take = it, tk; break end
    end
    if not item then
        S.status     = 'No MIDI item on VENUE track.'
        S.last_result = 'Found the VENUE track but it has no MIDI items.\n\n' ..
                        'Add a MIDI item to the VENUE track first.'
        return
    end

    local muted       = GetMutedInstruments()
    local active_coop = FilterPool(COOP_POOL, muted, GetCoopRequiredInstruments)

    -- Build weighted coop selection config.
    -- keys_failsafe: emit a companion guitar/bass event alongside any keys event (and vice
    -- versa) so the game can pick the slot that is actually populated in this band setup.
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

    local play_states_raw, no_data_letters = ReadInstrumentPlayStates()

    if #active_coop == 0 then
        local letter_names = {d='Drums', v='Vocals', b='Bass', g='Guitar', k='Keys'}
        local names        = {}
        for letter in pairs(muted) do names[#names + 1] = letter_names[letter] or letter end
        table.sort(names)
        S.status      = 'All instrument tracks muted - no camera events available.'
        S.last_result = 'Muted/absent: ' .. table.concat(names, ', ') ..
                        '\n\nUnmute at least one instrument track and try again.'
        return
    end

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')

    local qn_start = r.MIDI_GetPPQPosFromProjQN(take, 0)
    local qn_one   = r.MIDI_GetPPQPosFromProjQN(take, 1)
    local ppq      = qn_one - qn_start
    if ppq <= 0 then ppq = 960 end
    local sixteenth_ticks = ppq / 4

    local range_start_sec = item_start_sec
    local range_end_sec   = item_end_sec

    local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, range_start_sec)
    local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, range_end_sec)
    local range_ticks     = range_end_ppq - range_start_ppq
    local total_16ths     = math.floor(range_ticks / sixteenth_ticks)

    -- Resolve active theme
    local theme = nil
    if S.venue_theme_idx and S.venue_theme_idx > 0 and S.venue_themes then
        theme = S.venue_themes[S.venue_theme_idx]
    end

    local bpm = r.Master_GetTempo()

    -- Load sections when theme is active
    local sections = {}
    if theme then
        local s = ReadEventSections(range_end_sec)
        if s then sections = s end
    end

    -- Camera: theme-level interval and per-section overrides
    local cam_interval     = theme and GetThemeCameraInterval(theme.camera_pacing, bpm) or nil

    -- User camera pacing override (0=theme default, 1-5=named presets, 6=custom 16ths)
    local _user_cp_names = {nil, 'minimal', 'slow', 'medium', 'fast', 'crazy'}
    local user_cam_pacing = _user_cp_names[S.venue_cam_pacing + 1]
    if user_cam_pacing then
        cam_interval = GetThemeCameraInterval(user_cam_pacing, bpm)
    elseif S.venue_cam_pacing == 6 then
        local base = S.venue_cam_pacing_custom
        cam_interval = (bpm >= 150) and math.floor(base * 1.5 + 0.5) or base
    end

    local forced_cuts      = nil
    local interval_changes = nil
    local bonusfx_events   = nil

    if theme and #sections > 0 then
        local fc_list  = {}
        local ic_list  = {}
        local bfx_list = {}
        for _, sec in ipairs(sections) do
            local preset = GetSectionPreset(theme, sec.name, sec.num)
            if preset then
                if preset.dircut_at_start then
                    local sec_ppq    = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
                    local pos_16ths  = math.floor(((sec_ppq - range_start_ppq) / sixteenth_ticks) / 4 + 0.5) * 4
                    if pos_16ths >= 0 and pos_16ths < total_16ths then
                        fc_list[#fc_list + 1] = {
                            pos_16ths = pos_16ths,
                            text      = '[' .. preset.dircut_at_start .. ']',
                        }
                    end
                end
                if preset.camera_pacing and not user_cam_pacing then
                    local sec_ppq   = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
                    local pos_16ths = math.floor((sec_ppq - range_start_ppq) / sixteenth_ticks)
                    if pos_16ths >= 0 then
                        ic_list[#ic_list + 1] = {
                            pos_16ths = pos_16ths,
                            interval  = GetThemeCameraInterval(preset.camera_pacing, bpm),
                        }
                    end
                end
                if preset.bonusfx_at_start then
                    local sec_ppq  = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
                    local tick_off = sec_ppq - range_start_ppq
                    if tick_off >= 0 and tick_off < range_ticks then
                        bfx_list[#bfx_list + 1] = tick_off
                    end
                end
            end
        end
        if #fc_list  > 0 then forced_cuts      = fc_list  end
        if #ic_list  > 0 then interval_changes = ic_list  end
        if #bfx_list > 0 then bonusfx_events   = bfx_list end
    end

    -- Convert play-state timelines from project time to 16ths within the generation range.
    local play_states_16ths = {}
    for letter, timeline in pairs(play_states_raw) do
        if timeline then
            local converted = {}
            for _, ev in ipairs(timeline) do
                local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, ev.t)
                local p16     = (ppq_pos - range_start_ppq) / sixteenth_ticks
                converted[#converted + 1] = { pos_16ths = p16, is_active = ev.is_active }
            end
            play_states_16ths[letter] = converted
        end
        -- nil stays nil = always active
    end
    coop_opts.play_states = play_states_16ths

    -- Convert sing-note timelines from VENUE-PPQ to range-relative 16ths.
    -- Note: ReadSingNoteTimelines reads from the same take before ClearVenueTextEventsInRange,
    -- which is safe because that call only deletes text/sysex events, not MIDI notes.
    local sing_notes_raw    = ReadSingNoteTimelines(take)
    local sing_states_16ths = {}
    for letter, notes in pairs(sing_notes_raw) do
        local events = {}
        for _, note in ipairs(notes) do
            local s16 = (note.sppq - range_start_ppq) / sixteenth_ticks
            local e16 = (note.eppq - range_start_ppq) / sixteenth_ticks
            events[#events + 1] = { pos_16ths = s16, is_singing = true  }
            events[#events + 1] = { pos_16ths = e16, is_singing = false }
        end
        table.sort(events, function(a, b) return a.pos_16ths < b.pos_16ths end)
        sing_states_16ths[letter] = events
    end
    coop_opts.sing_states = sing_states_16ths

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    ClearVenueTextEventsInRange(take, range_start_ppq, range_end_ppq)

    local count     = 0
    local half_beat = math.floor(ppq / 2 + 0.5)  -- ticks per half-beat (snap grid)
    local function insert_text(tick_offset, text)
        local abs_ppq = range_start_ppq + tick_offset
        local snapped = math.floor(abs_ppq / half_beat + 0.5) * half_beat
        r.MIDI_InsertTextSysexEvt(take, false, false, snapped, 1, text)
        count = count + 1
    end

    -- Intro bookend: only when not using themed sections (theme handles intro section)
    if not (theme and #sections > 0) then
        insert_text(0, '[lighting (intro)]')
    end

    -- Song-start camera bookends anchored to VENUE item start.
    --   Measure 1: forced venue shot  ([coop_all_*] / [coop_front_*])
    --   Measure 3: weighted pick with play-state awareness at that exact tick
    local cam_bookend_count  = 0
    local last_bookend_16ths = nil  -- 16ths position of last inserted bookend shot
    if #coop_opts.venue_pool > 0 then
        local song_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, item_start_sec)
        local bk_m2_ppq      = FindNextMeasureStartPpq(take, song_start_ppq, ppq)
        local bk_m3_ppq      = FindNextMeasureStartPpq(take, bk_m2_ppq, ppq)

        if song_start_ppq >= range_start_ppq and song_start_ppq < range_end_ppq then
            local tick = math.floor(song_start_ppq - range_start_ppq + 0.5)
            insert_text(tick, PickRandom(coop_opts.venue_pool, nil))
            cam_bookend_count  = cam_bookend_count + 1
            last_bookend_16ths = tick / sixteenth_ticks
        end

        if bk_m3_ppq >= range_start_ppq and bk_m3_ppq < range_end_ppq then
            local m3_tick    = math.floor(bk_m3_ppq - range_start_ppq + 0.5)
            local m3_16ths   = m3_tick / sixteenth_ticks
            local m3_cursors = {}
            for letter, _ in pairs(coop_opts.play_states) do
                m3_cursors[letter] = 1
            end
            local m3_sing_cursors = {}
            for letter in pairs(coop_opts.sing_states) do m3_sing_cursors[letter] = 1 end
            local m3_idle, m3_all_idle = ComputeIdleState(coop_opts, m3_cursors, m3_16ths)
            local m3_singing           = ComputeSingState(coop_opts, m3_sing_cursors, m3_16ths)
            local m3_gw   = m3_all_idle and { solo = 30, duo = 10, venue = 60 } or nil
            local m3_text = WeightedPickCoopEvent(
                coop_opts.venue_pool, coop_opts.solo_pools,
                coop_opts.duo_pools, nil, m3_idle, m3_gw,
                coop_opts.suffix_pools, m3_singing)
            if m3_text then
                insert_text(m3_tick, m3_text)
                cam_bookend_count  = cam_bookend_count + 1
                last_bookend_16ths = m3_16ths
            end
        end
    end

    -- Treat the last bookend shot as the first cut: next event is one normal interval later.
    local cam_start_min, cam_start_max
    if last_bookend_16ths then
        local _cj = S.venue_cam_pacing_jitter and CAM_JITTER or 0
        cam_start_min = math.floor(last_bookend_16ths + CAM_INTERVAL_16THS * (1 - _cj))
        cam_start_max = math.floor(last_bookend_16ths + CAM_INTERVAL_16THS * (1 + _cj))
    end

    local cam_dir        = {}
    local cam_events     = GenerateCameraEvents(active_coop, cam_dir, total_16ths, ppq,
                                                cam_interval, forced_cuts, interval_changes,
                                                cam_start_min, cam_start_max, coop_opts)
    local directed_count  = 0
    local companion_count = 0
    for _, ev in ipairs(cam_events) do
        insert_text(ev.tick, ev.text)
        if ev.is_directed  then directed_count  = directed_count  + 1 end
        if ev.is_companion then companion_count = companion_count + 1 end
    end

    local bonusfx_count = 0
    if bonusfx_events then
        for _, tick_off in ipairs(bonusfx_events) do
            insert_text(tick_off, '[bonusfx]')
            bonusfx_count = bonusfx_count + 1
        end
    end

    local lt_offset_ticks = math.floor(LIGHTING_OFFSET_16THS * sixteenth_ticks + 0.5)
    local lt_range_16ths  = total_16ths - LIGHTING_OFFSET_16THS
    local lt_events, ctrl_events, pp_events

    if theme and #sections > 0 then
        lt_events, ctrl_events, pp_events = GenerateThemedSectionEvents(
            sections, theme, take, range_start_ppq, range_end_ppq, ppq)
        for _, ev in ipairs(lt_events)   do insert_text(ev.tick, ev.text) end
        for _, ev in ipairs(ctrl_events) do insert_text(ev.tick, ev.text) end
        for _, ev in ipairs(pp_events)   do insert_text(ev.tick, ev.text) end
    else
        local def  = theme and theme.section_presets and theme.section_presets['default']
        local pool = def and BuildLightingPool(def) or nil
        lt_events, ctrl_events = GenerateLightingEvents(lt_range_16ths, ppq, pool)
        pp_events = {}
        for _, ev in ipairs(lt_events)   do insert_text(lt_offset_ticks + ev.tick, ev.text) end
        for _, ev in ipairs(ctrl_events) do insert_text(lt_offset_ticks + ev.tick, ev.text) end
    end

    local blackout_offset = range_ticks - math.floor(32 * sixteenth_ticks)
    if blackout_offset > 0 then
        insert_text(blackout_offset, '[lighting (blackout_spot)]')
    end

    r.Undo_EndBlock2(0, 'RB Generate Venue Events', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local letter_names = {d='Drums', v='Vocals', b='Bass', g='Guitar', k='Keys'}
    local muted_names  = {}
    for letter in pairs(muted) do muted_names[#muted_names + 1] = letter_names[letter] or letter end
    table.sort(muted_names)
    local muted_str = #muted_names > 0 and table.concat(muted_names, ', ') or 'None'

    local manual_count = 0
    for _, ev in ipairs(lt_events) do
        if MANUAL_LIGHTING_SET[ev.text] then manual_count = manual_count + 1 end
    end

    local lines = {}
    lines[#lines + 1] = ('Generated %d total events on VENUE track.'):format(count)
    lines[#lines + 1] = ''
    if theme then
        lines[#lines + 1] = 'Theme:              ' .. theme.label
        lines[#lines + 1] = ('Sections matched:   %d'):format(#sections)
        lines[#lines + 1] = ''
    end
    lines[#lines + 1] = 'Muted/absent:       ' .. muted_str
    lines[#lines + 1] = ('Available coop:     %d/%d'):format(#active_coop, #COOP_POOL)
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('Camera (coop):      %d'):format(#cam_events - directed_count - companion_count)
    lines[#lines + 1] = ('Camera (directed):  %d'):format(directed_count)
    if companion_count > 0 then
        lines[#lines + 1] = ('Camera (companion): %d'):format(companion_count)
    end
    lines[#lines + 1] = ('Lighting (auto):    %d'):format(#lt_events - manual_count)
    lines[#lines + 1] = ('Lighting (manual):  %d'):format(manual_count)
    lines[#lines + 1] = ('Control [first]/[next]: %d'):format(#ctrl_events)
    if #pp_events > 0 then
        lines[#lines + 1] = ('Post-process:       %d'):format(#pp_events)
    end
    if bonusfx_count > 0 then
        lines[#lines + 1] = ('Bonus FX:           %d'):format(bonusfx_count)
    end
    local bookend_count = 1 + cam_bookend_count  -- blackout_spot + camera venue bookends
    if not (theme and #sections > 0) then bookend_count = bookend_count + 1 end  -- intro
    lines[#lines + 1] = ('Bookend events:     %d'):format(bookend_count)
    lines[#lines + 1] = ''
    local warn_no_data = {}
    local nd_names_map = { d='Drums', v='Vocals', b='Bass', g='Guitar', k='Keys' }
    for _, l in ipairs(no_data_letters) do
        if not muted[l] then warn_no_data[#warn_no_data + 1] = nd_names_map[l] or l end
    end
    table.sort(warn_no_data)
    if #warn_no_data > 0 then
        lines[#lines + 1] = 'Note: ' .. table.concat(warn_no_data, ', ') ..
                            ' have no play-state events - treated as always active.'
        lines[#lines + 1] = ''
    end
    local sing_letter_names = { b='Bass', d='Drums', g='Guitar' }
    local sing_active = {}
    for _, l in ipairs({ 'b', 'd', 'g' }) do
        if coop_opts.sing_states[l] then
            sing_active[#sing_active + 1] = sing_letter_names[l]
        end
    end
    if #sing_active > 0 then
        lines[#lines + 1] = 'Sing notes:         ' .. table.concat(sing_active, ', ')
    end
    lines[#lines + 1] = ('PPQ: %d  |  Range 16ths: %d'):format(ppq, total_16ths)

    S.status      = ('Generated %d VENUE events.'):format(count)
    S.last_result = table.concat(lines, '\n')
end
