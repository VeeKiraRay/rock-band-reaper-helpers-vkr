-- UI loop
-- Requires: S, TIPS, r, ctx (globals)
-- Requires: all action functions, GetTimeSelection, RefreshTrackLists, Tooltip,
--           SliderTooltip, SectionHeader (globals)
-- Note: r.defer(Loop) is called at the end of this file.

-- Local variant of TrackCombo: matches by REAPER track index (t.idx), supports
-- reaper_idx = -1 as "(none)". Shadowing the lib's TrackCombo which uses array
-- indices and has no "(none)" entry.
local function TrackCombo(label, reaper_idx, tracks)
    local preview = reaper_idx < 0 and '(none)' or '<no tracks>'
    if reaper_idx >= 0 then
        for _, t in ipairs(tracks) do
            if t.idx == reaper_idx then preview = t.label; break end
        end
        if preview == '<no tracks>' and S.all_track_list then
            for _, t in ipairs(S.all_track_list) do
                if t.idx == reaper_idx then preview = t.label; break end
            end
        end
    end
    local new_idx = reaper_idx
    if r.ImGui_BeginCombo(ctx, label, preview) then
        if r.ImGui_Selectable(ctx, '(none)', reaper_idx < 0) then new_idx = -1 end
        if reaper_idx < 0 then r.ImGui_SetItemDefaultFocus(ctx) end
        for _, t in ipairs(tracks) do
            local is_sel = (t.idx == reaper_idx)
            if r.ImGui_Selectable(ctx, t.label, is_sel) then new_idx = t.idx end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    return new_idx
end

local _active_proj = r.EnumProjects(-1, '')

local function Loop()
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj = proj
        S.last_result      = nil
        S.all_track_list   = nil
        S.audio_track_list = nil
        S.tm_kick_idx     = -1
        S.tm_snare_idx    = -1
        S.tm_kit_idx      = -1
        S.tm_fallback_idx = -1
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        SetDefaultTempoTracks()
    end

    local sel_s, sel_e = GetTimeSelection()
    if not S.all_track_list then RefreshTrackLists() end
    local audio_tracks = S.audio_track_list

    r.ImGui_SetNextWindowSize(ctx, 540, 620, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band General Helper', true)
    if visible then
        local _bp  = 40
        local bw_und = r.ImGui_CalcTextSize(ctx, 'Undo') + _bp

        if r.ImGui_BeginTabBar(ctx, '##tabs') then

            ------------------------------------------------------------
            -- General tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'General') then
                local bw_aall = r.ImGui_CalcTextSize(ctx, 'Align all audio') + _bp
                local bw_acin = r.ImGui_CalcTextSize(ctx, 'Align count-in')  + _bp

                SectionHeader('Audio alignment')

                if r.ImGui_Button(ctx, 'Align all audio', bw_aall, 24) then
                    AlignAllAudio()
                end
                Tooltip(TIPS.align_all_audio)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Align count-in', bw_acin, 24) then
                    AlignCountIn()
                end
                Tooltip(TIPS.align_count_in)

                r.ImGui_Separator(ctx)
                SectionHeader('Settings')

                if r.ImGui_Button(ctx, 'Save', 90, 24) then
                    SaveSettings()
                    S.status = 'Settings saved to project.'
                end
                Tooltip(TIPS.save)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Load', 90, 24) then
                    if LoadSettings() then
                        S.status = 'Settings loaded from project.'
                    else
                        S.status = 'No saved settings found in this project.'
                    end
                end
                Tooltip(TIPS.load)
                r.ImGui_SameLine(ctx)
                local bw_ref = r.ImGui_CalcTextSize(ctx, 'Refresh tracks') + _bp
                if r.ImGui_Button(ctx, 'Refresh tracks', bw_ref, 24) then
                    RefreshTrackLists()
                    S.status = 'Track lists refreshed.'
                end
                Tooltip(TIPS.track_refresh)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tempo Map tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Tempo Map') then
                local bw_ctx   = r.ImGui_CalcTextSize(ctx, 'Show context')           + _bp
                local bw_ali   = r.ImGui_CalcTextSize(ctx, 'Align audio')             + _bp
                local bw_ebpm  = r.ImGui_CalcTextSize(ctx, 'Estimate initial BPM')    + _bp
                local bw_gen   = r.ImGui_CalcTextSize(ctx, 'Generate tempo map')      + _bp
                local bw_clrtm = r.ImGui_CalcTextSize(ctx, 'Clear generated markers') + _bp

                r.ImGui_Text(ctx, 'KICK track ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.tm_kick_idx = TrackCombo('##tm_kick', S.tm_kick_idx, audio_tracks)
                Tooltip(TIPS.kick_track)

                r.ImGui_Text(ctx, 'SNARE track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.tm_snare_idx = TrackCombo('##tm_snare', S.tm_snare_idx, audio_tracks)
                Tooltip(TIPS.snare_track)

                r.ImGui_Text(ctx, 'KIT track  ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.tm_kit_idx = TrackCombo('##tm_kit', S.tm_kit_idx, audio_tracks)
                Tooltip(TIPS.kit_track)

                r.ImGui_Text(ctx, 'Fallback   ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.tm_fallback_idx = TrackCombo('##tm_fallback', S.tm_fallback_idx, audio_tracks)
                Tooltip(TIPS.fallback_track)

                r.ImGui_Spacing(ctx)

                if r.ImGui_Button(ctx, 'Show context', bw_ctx, 24) then
                    ShowTempoContext()
                end
                Tooltip(TIPS.show_ctx)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Align audio', bw_ali, 24) then
                    AlignAudioTracks()
                end
                Tooltip(TIPS.align_audio)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Estimate initial BPM', bw_ebpm, 24) then
                    EstimateInitialBPM()
                end
                Tooltip(TIPS.est_bpm)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Generate tempo map', bw_gen, 24) then
                    GenerateTempoMap()
                end
                Tooltip(TIPS.gen_tempo)

                if r.ImGui_Button(ctx, 'Clear generated markers', bw_clrtm, 24) then
                    ClearGeneratedTempoMarkers()
                end
                Tooltip(TIPS.clear_tempo)

                r.ImGui_Spacing(ctx)

                local slider_w = 200
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_rms_threshold = r.ImGui_SliderDouble(
                    ctx, 'RMS threshold', S.tm_rms_threshold, 0.001, 0.5, '%.3f')
                SliderTooltip(TIPS.tm_rms_threshold)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_rms_window_ms = r.ImGui_SliderInt(
                    ctx, 'RMS window (ms)', S.tm_rms_window_ms, 5, 30)
                SliderTooltip(TIPS.tm_rms_window_ms)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_search_window_ms = r.ImGui_SliderInt(
                    ctx, 'Search window (ms)', S.tm_search_window_ms, 20, 300)
                SliderTooltip(TIPS.tm_search_window_ms)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_drift_threshold_ms = r.ImGui_SliderInt(
                    ctx, 'Drift threshold (ms)', S.tm_drift_threshold_ms, 5, 100)
                SliderTooltip(TIPS.tm_drift_threshold_ms)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_bpm_failsafe = r.ImGui_SliderDouble(
                    ctx, 'BPM failsafe', S.tm_bpm_failsafe, 2.0, 30.0, '%.1f')
                SliderTooltip(TIPS.tm_bpm_failsafe)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_first_measure = r.ImGui_SliderInt(
                    ctx, 'First measure', S.tm_first_measure, 1, 8)
                SliderTooltip(TIPS.tm_first_measure)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_timesig_num = r.ImGui_SliderInt(
                    ctx, 'Time sig num (0=inherit)', S.tm_timesig_num, 0, 12)
                SliderTooltip(TIPS.tm_timesig_num)

                _, S.tm_override_failsafe = r.ImGui_Checkbox(
                    ctx, 'Override BPM limit', S.tm_override_failsafe)
                Tooltip(TIPS.tm_override_failsafe)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Venue tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Venue') then
                local bw_lv = r.ImGui_CalcTextSize(ctx, 'List venue events') + _bp

                if r.ImGui_Button(ctx, 'List venue events', bw_lv, 24) then
                    ListVenueEvents()
                end
                Tooltip(TIPS.list_venue)

                r.ImGui_EndTabItem(ctx)
            end

            r.ImGui_EndTabBar(ctx)
        end

        ----------------------------------------------------------------
        -- Time selection info + status panel (always visible below tabs)
        ----------------------------------------------------------------
        r.ImGui_Separator(ctx)
        if sel_s then
            r.ImGui_Text(ctx, ('Time selection: %s — %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
        else
            r.ImGui_TextDisabled(ctx, 'No time selection')
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, S.status)
        r.ImGui_SameLine(ctx)
        local undo_str = r.Undo_CanUndo2(0) or ''
        local can_undo = undo_str ~= ''
        local avail_x  = r.ImGui_GetContentRegionAvail(ctx)
        if avail_x > bw_und + 4 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - bw_und))
        end
        if not can_undo then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, 'Undo', bw_und, 24) then r.Undo_DoUndo2(0) end
        if not can_undo then r.ImGui_EndDisabled(ctx) end
        if can_undo then Tooltip('Undo: ' .. undo_str) end
        if S.last_result then
            r.ImGui_Separator(ctx)
            for line in S.last_result:gmatch('([^\n]*)\n?') do
                if line ~= '' then
                    r.ImGui_Text(ctx, line)
                else
                    r.ImGui_Spacing(ctx)
                end
            end
        end

        r.ImGui_End(ctx)
    end

    if open then r.defer(Loop) end
end

r.defer(Loop)
