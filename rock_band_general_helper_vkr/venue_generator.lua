-- Venue event generator: main orchestration for GenerateVenueEvents.
-- Requires: venue_camera.lua and venue_lighting.lua loaded first.
-- Requires: GetMutedInstruments, FilterPool, GetCoopRequiredInstruments,
--           GetDirectedRequiredInstruments, FindTrackByName, FindCompanion,
--           ReadEventSections, ReadInstrumentPlayStates, GetSectionPreset,
--           GetThemeCameraInterval, FindEventTime, FindMusicStartTime,
--           FindNextMeasureStartPpq, r, S (globals)

-- Delete type-1 text events in [start_ppq, end_ppq). keep_fn(msg) -> true
-- preserves an event; nil keep_fn deletes every text event in range.
-- Returns the number of deleted events. Backs every venue clear function
-- (and the Events tab's Clear all / Remove by type).
function DeleteTextEventsInRange(take, start_ppq, end_ppq, keep_fn)
    local count = 0
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = text_count - 1, 0, -1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq >= start_ppq and ppq < end_ppq
            and not (keep_fn and keep_fn(msg)) then
            r.MIDI_DeleteTextSysexEvt(take, i)
            count = count + 1
        end
    end
    return count
end

function ClearVenueTextEventsInRange(take, start_ppq, end_ppq)
    DeleteTextEventsInRange(take, start_ppq, end_ppq, nil)
end

-- Clears everything except camera events ([coop_*] / [directed_*]).
-- Use for the blendin zone before a section to preserve previous section's camera shots.
function ClearVenueNonCameraEventsInRange(take, start_ppq, end_ppq)
    DeleteTextEventsInRange(take, start_ppq, end_ppq, function(msg)
        return msg:find('^%[coop_') or msg:find('^%[directed_')
    end)
end

-- Clears everything except lighting ([lighting *]) and postproc (*.pp]).
-- Use for the section body to preserve adjacent section's blendin LP events.
function ClearVenueExceptLPInRange(take, start_ppq, end_ppq)
    DeleteTextEventsInRange(take, start_ppq, end_ppq, function(msg)
        return msg:find('^%[lighting') or msg:find('%.pp%]$')
    end)
end

-- Deletes only [first]/[next]/[previous] text events in range. Leaves camera, lighting,
-- postproc, and bonusfx untouched.
function ClearVenueKeyframesInRange(take, start_ppq, end_ppq)
    DeleteTextEventsInRange(take, start_ppq, end_ppq, function(msg)
        return msg ~= '[first]' and msg ~= '[next]' and msg ~= '[previous]'
    end)
end

-- Resolves the generation range end from EVENTS-track markers, plus the "final anchor"
-- position used to keep the outro lighting bookend and the last scripted camera cut clear
-- of the game's own forced camera cut at [end]. Pure function of the EVENTS track + the
-- VENUE item's own bounds - see CLAUDE_venue_theme_generation.md's "Song end and the final
-- anchor" for the full rationale.
-- Returns:
--   range_end_sec      - [end] marker time when one falls inside the item, else item_end_sec
--   end_in_range       - true when a valid [end] marker was used for range_end_sec
--   trailing_slack_sec - item_end_sec - range_end_sec (0 when end_in_range is false)
--   final_anchor_ppq   - take-PPQ position of [music_end] when it is within 10 measures of
--                         [end] (measured via FindNextMeasureStartPpq), else nil
function ResolveSongEndAndAnchor(take, ppq, item_start_sec, item_end_sec)
    local end_marker_t = FindEventTime('[end]')
    local end_in_range = end_marker_t ~= nil
                       and end_marker_t > item_start_sec
                       and end_marker_t <= item_end_sec
    local range_end_sec      = end_in_range and end_marker_t or item_end_sec
    local trailing_slack_sec = end_in_range and (item_end_sec - end_marker_t) or 0

    local final_anchor_ppq = nil
    if end_in_range then
        local music_end_t = FindEventTime('[music_end]')
        if music_end_t and music_end_t > item_start_sec and music_end_t < range_end_sec then
            local range_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, range_end_sec)
            local music_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, music_end_t)
            local pos, measures = music_end_ppq, 0
            while pos < range_end_ppq and measures < 999 do
                pos = FindNextMeasureStartPpq(take, pos, ppq)
                measures = measures + 1
            end
            if measures <= 10 then
                final_anchor_ppq = music_end_ppq
            end
        end
    end

    return range_end_sec, end_in_range, trailing_slack_sec, final_anchor_ppq
end

-- ---------------------------------------------------------------------------

function GenerateVenueEvents()
    local track, item, take = FindNamedTrackMIDI('VENUE')
    if not track then
        S.status     = 'No VENUE track found.'
        S.last_result = 'Could not find a track named "VENUE".\n\n' ..
                        'Make sure your Rock Band project has a VENUE track.'
        return
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
        local names = {}
        for letter in pairs(muted) do names[#names + 1] = INST_LETTER_NAMES[letter] or letter end
        table.sort(names)
        S.status      = 'All instrument tracks muted - no camera events available.'
        S.last_result = 'Muted/absent: ' .. table.concat(names, ', ') ..
                        '\n\nUnmute at least one instrument track and try again.'
        return
    end

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')

    local ppq             = GetTakePPQPerQN(take)
    local sixteenth_ticks = ppq / 4

    -- [end] on the EVENTS track is the absolute song end - the VENUE MIDI item is free to
    -- run past it (harmless in-game) but nothing should be generated at or after that point.
    -- Falls back to the item's own length (with a result-panel warning) when no [end] marker
    -- is present. final_anchor_ppq additionally resolves [music_end] when it's close enough
    -- to [end] to anchor the outro bookend and last camera cut there instead - see
    -- ResolveSongEndAndAnchor above.
    local range_start_sec = item_start_sec
    local range_end_sec, end_in_range, trailing_slack_sec, final_anchor_ppq =
        ResolveSongEndAndAnchor(take, ppq, item_start_sec, item_end_sec)
    local used_end_fallback = not end_in_range

    local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, range_start_sec)
    local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, range_end_sec)
    local range_ticks     = range_end_ppq - range_start_ppq
    local total_16ths     = math.floor(range_ticks / sixteenth_ticks)

    local final_anchor_16ths = final_anchor_ppq
        and (final_anchor_ppq - range_start_ppq) / sixteenth_ticks or nil

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

    -- "Actual music start": an explicit [music_start] marker on the EVENTS track if present,
    -- else whichever of measure 3/4 lands closer to the 3-second mark (adapts to tempo).
    -- Used to anchor the first generated camera cut, and to re-anchor a [prc_*] section
    -- that was placed right at the song's literal start (see below).
    local song_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, item_start_sec)
    local music_start_ppq
    local music_start_t = FindMusicStartTime()
    if music_start_t then
        music_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, music_start_t)
    else
        local bk_m2_ppq = FindNextMeasureStartPpq(take, song_start_ppq, ppq)
        local bk_m3_ppq = FindNextMeasureStartPpq(take, bk_m2_ppq, ppq)
        local bk_m4_ppq = FindNextMeasureStartPpq(take, bk_m3_ppq, ppq)
        local t_target   = item_start_sec + 3.0
        local t3         = r.MIDI_GetProjTimeFromPPQPos(take, bk_m3_ppq)
        local t4         = r.MIDI_GetProjTimeFromPPQPos(take, bk_m4_ppq)
        music_start_ppq  = (math.abs(t4 - t_target) < math.abs(t3 - t_target)) and bk_m4_ppq or bk_m3_ppq
    end

    -- If the first [prc_*] section was placed right at the song's literal start (e.g. a
    -- [prc_intro] marker at measure 1), treat it as if it actually starts at the resolved
    -- music-start anchor instead - its lighting/postproc (and any dircut/bonusfx) then land
    -- at the real musical start rather than during the count-in/silence.
    if theme and sections[1] and sections[1].t_start <= item_start_sec + 0.001 then
        sections[1].t_start = r.MIDI_GetProjTimeFromPPQPos(take, music_start_ppq)
    end

    -- Vocal phrase start pacing mode (S.venue_cam_pacing == 7): camera cadence follows
    -- PART VOCALS phrase-marker (pitch 105) note starts instead of a fixed interval - see
    -- GenerateCameraEvents' phrase_positions_16ths param and CollectVocalPhraseStarts.
    local phrase_mode = (S.venue_cam_pacing == 7)

    -- Camera: theme-level interval and per-section overrides (suppressed in phrase mode -
    -- it has no interval concept)
    local cam_interval = (not phrase_mode) and theme
        and GetThemeCameraInterval(theme.camera_pacing, bpm) or nil

    -- User camera pacing override (0=theme default, 1-5=named presets, 6=custom 16ths,
    -- 7=vocal phrase start)
    local user_ci, user_cam_pacing = ResolveUserCamInterval(bpm)
    if user_ci then cam_interval = user_ci end

    -- Phrase positions, range-relative in 16ths - possibly empty (phrase mode active but
    -- no phrase markers found), never nil once phrase_mode is true.
    local phrase_positions_16ths = nil
    if phrase_mode then
        local raw_positions = CollectVocalPhraseStarts(take, range_start_ppq, range_end_ppq)
        phrase_positions_16ths = {}
        for _, p in ipairs(raw_positions) do
            phrase_positions_16ths[#phrase_positions_16ths + 1] =
                (p - range_start_ppq) / sixteenth_ticks
        end
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
                if preset.camera_pacing and not user_cam_pacing and not phrase_mode then
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
    -- no_snap: skip snapping - keyframe ctrl_events from GenerateThemedSectionEvents are
    -- already placed on their own alignment grid (possibly finer than half-beat, e.g.
    -- quarter-beat instrument-aware modes); re-snapping would collapse those positions
    -- onto the nearest half-beat/beat. A [first] carrying a lighting event's tick is
    -- pre-snapped by SnapPpqToHalfBeat there so it still lands on that event exactly.
    local function insert_text(tick_offset, text, no_snap)
        local abs_ppq = range_start_ppq + tick_offset
        local snapped = no_snap and abs_ppq or SnapPpqToHalfBeat(abs_ppq, ppq)
        r.MIDI_InsertTextSysexEvt(take, false, false, snapped, 1, text)
        count = count + 1
    end

    -- Forced song-start trio: not randomised, fires regardless of theme, so every song
    -- opens the same way. A themed [prc_*] section covering song start still gets its own
    -- lighting/postproc pick independently (see the section-shift above and ProcessThemeSection).
    local cam_bookend_count      = 0
    local forced_pp_count        = 0
    local bookend_companion_count = 0
    local last_bookend_16ths    = nil  -- 16ths position of last inserted bookend shot
    -- Set of event strings banned for the next pick (see PickRandom) - chains through the
    -- bookends into GenerateCameraEvents so the regular loop's first cut doesn't immediately
    -- repeat whatever the bookends just placed.
    local last_spot              = {}
    if song_start_ppq >= range_start_ppq and song_start_ppq < range_end_ppq then
        local tick = math.floor(song_start_ppq - range_start_ppq + 0.5)
        insert_text(tick, '[coop_all_far]')
        insert_text(tick, '[lighting (intro)]')
        insert_text(tick, '[ProFilm_a.pp]')
        cam_bookend_count  = 1
        forced_pp_count    = 1
        last_bookend_16ths = tick / sixteenth_ticks
        last_spot           = { ['[coop_all_far]'] = true }
    end

    -- First randomly-generated camera cut: weighted pick with play-state awareness,
    -- anchored to the resolved music-start position (not a fixed measure).
    if #coop_opts.venue_pool > 0
        and music_start_ppq >= range_start_ppq and music_start_ppq < range_end_ppq then
        local anchor_tick    = math.floor(music_start_ppq - range_start_ppq + 0.5)
        local anchor_16ths   = anchor_tick / sixteenth_ticks
        local anchor_cursors = {}
        for letter, _ in pairs(coop_opts.play_states) do
            anchor_cursors[letter] = 1
        end
        local anchor_sing_cursors = {}
        for letter in pairs(coop_opts.sing_states) do anchor_sing_cursors[letter] = 1 end
        local anchor_idle, anchor_all_idle = ComputeIdleState(coop_opts, anchor_cursors, anchor_16ths)
        local anchor_singing               = ComputeSingState(coop_opts, anchor_sing_cursors, anchor_16ths)
        local anchor_gw   = anchor_all_idle and { solo = 30, duo = 10, venue = 60 } or nil
        local anchor_text = WeightedPickCoopEvent(
            coop_opts.venue_pool, coop_opts.solo_pools,
            coop_opts.duo_pools, last_spot, anchor_idle, anchor_gw,
            coop_opts.suffix_pools, anchor_singing)
        if anchor_text then
            local prev_spot    = last_spot
            insert_text(anchor_tick, anchor_text)
            cam_bookend_count  = cam_bookend_count + 1
            last_bookend_16ths = anchor_16ths
            last_spot           = { [anchor_text] = true }

            if coop_opts.keys_failsafe then
                local anchor_companion = FindCompanion(anchor_text, coop_opts, anchor_idle, anchor_singing, prev_spot)
                if anchor_companion then
                    insert_text(anchor_tick, anchor_companion)
                    cam_bookend_count      = cam_bookend_count + 1
                    bookend_companion_count = bookend_companion_count + 1
                    last_spot[anchor_companion] = true
                end
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

    local cam_dir         = {}
    -- The last scripted camera cut lands 8 sixteenths before whichever end this call is
    -- given - anchoring to final_anchor_16ths (the [music_end] position) when set keeps that
    -- last cut away from [end]'s own forced in-game camera cut instead of landing right next
    -- to it. See "Final anchor" above.
    local cam_total_16ths = final_anchor_16ths or total_16ths
    local cam_events      = GenerateCameraEvents(active_coop, cam_dir, cam_total_16ths, ppq,
                                                cam_interval, forced_cuts, interval_changes,
                                                cam_start_min, cam_start_max, coop_opts, last_spot,
                                                phrase_positions_16ths)
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
        for _, ev in ipairs(ctrl_events) do insert_text(ev.tick, ev.text, true) end
        for _, ev in ipairs(pp_events)   do insert_text(ev.tick, ev.text) end
    else
        local def  = theme and theme.section_presets and theme.section_presets['default']
        local pool = def and BuildLightingPool(def) or nil
        lt_events, ctrl_events = GenerateLightingEvents(lt_range_16ths, ppq, pool)
        pp_events = {}
        for _, ev in ipairs(lt_events)   do insert_text(lt_offset_ticks + ev.tick, ev.text) end
        for _, ev in ipairs(ctrl_events) do insert_text(lt_offset_ticks + ev.tick, ev.text) end
    end

    -- Outro bookend: at the final anchor ([music_end]) when one was resolved above,
    -- otherwise 2 measures (32 sixteenths) before the song end (see "Final anchor" above).
    local blackout_offset = final_anchor_ppq
        and (final_anchor_ppq - range_start_ppq)
        or (range_ticks - math.floor(32 * sixteenth_ticks))
    if blackout_offset > 0 then
        insert_text(blackout_offset, '[lighting (blackout_spot)]')
    end

    r.Undo_EndBlock2(0, 'RB Generate Venue Events', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local muted_names = {}
    for letter in pairs(muted) do muted_names[#muted_names + 1] = INST_LETTER_NAMES[letter] or letter end
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
    if companion_count + bookend_companion_count > 0 then
        lines[#lines + 1] = ('Camera (companion): %d'):format(companion_count + bookend_companion_count)
    end
    if phrase_mode and #phrase_positions_16ths == 0 then
        lines[#lines + 1] = 'No PART VOCALS phrase markers found - the recurring camera loop ' ..
                            'was skipped (bookend/forced-cut events, if any, were still placed).'
    end
    lines[#lines + 1] = ('Lighting (auto):    %d'):format(#lt_events - manual_count)
    lines[#lines + 1] = ('Lighting (manual):  %d'):format(manual_count)
    lines[#lines + 1] = ('Control [first]/[next]: %d'):format(#ctrl_events)
    if #pp_events + forced_pp_count > 0 then
        lines[#lines + 1] = ('Post-process:       %d'):format(#pp_events + forced_pp_count)
    end
    if bonusfx_count > 0 then
        lines[#lines + 1] = ('Bonus FX:           %d'):format(bonusfx_count)
    end
    -- intro lighting + blackout_spot + camera bookends (forced measure-1 shot + music-start weighted pick)
    local bookend_count = 2 + cam_bookend_count
    lines[#lines + 1] = ('Bookend events:     %d'):format(bookend_count)
    lines[#lines + 1] = ('Music start anchor: %s'):format(
        music_start_t and 'explicit [music_start] marker' or '~3s fallback (measure 3/4)')
    lines[#lines + 1] = ('Song end:           %s'):format(
        end_in_range and 'explicit [end] marker' or 'MIDI item length (fallback)')
    if final_anchor_ppq then
        lines[#lines + 1] = 'Final anchor:       [music_end] marker (outro bookend + last camera cut)'
    end
    lines[#lines + 1] = ''
    if used_end_fallback then
        lines[#lines + 1] = "Didn't find [end] event, used MIDI length as end."
        lines[#lines + 1] = ''
    elseif trailing_slack_sec > 1.0 then
        lines[#lines + 1] = ('Note: VENUE item runs %.1fs past [end] - trimming it to [end] is safe ' ..
                             '(no in-game effect) and keeps the item tidy.'):format(trailing_slack_sec)
        lines[#lines + 1] = ''
    end
    local warn_no_data = {}
    for _, l in ipairs(no_data_letters) do
        if not muted[l] then warn_no_data[#warn_no_data + 1] = INST_LETTER_NAMES[l] or l end
    end
    table.sort(warn_no_data)
    if #warn_no_data > 0 then
        lines[#lines + 1] = 'Note: ' .. table.concat(warn_no_data, ', ') ..
                            ' have no play-state events - treated as always active.'
        lines[#lines + 1] = ''
    end
    local sing_active = {}
    for _, l in ipairs({ 'b', 'd', 'g' }) do
        if coop_opts.sing_states[l] then
            sing_active[#sing_active + 1] = INST_LETTER_NAMES[l]
        end
    end
    if #sing_active > 0 then
        lines[#lines + 1] = 'Sing notes:         ' .. table.concat(sing_active, ', ')
    end
    lines[#lines + 1] = ('PPQ: %d  |  Range 16ths: %d'):format(ppq, total_16ths)

    S.status      = ('Generated %d VENUE events.'):format(count)
    S.last_result = table.concat(lines, '\n')
end
