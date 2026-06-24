-- UI loop
-- Requires: S, TIPS, r, ctx (globals)
-- Requires: all action functions, GetTimeSelection, RefreshTrackLists, Tooltip,
--           SliderTooltip, SectionHeader (globals)
-- Note: r.defer(Loop) is called at the end of this file.

-- Local variant of TrackCombo: matches by REAPER track index (t.idx), supports
-- reaper_idx = -1 as "(none)". Shadowing the lib's TrackCombo which uses array
-- indices and has no "(none)" entry.
function TrackCombo(label, reaper_idx, tracks)
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
local _active_tab  = ''

local function Loop()
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj = proj
        S.last_result      = nil
        S.all_track_list   = nil
        S.audio_track_list = nil
        S.midi_track_list  = nil
        S.tm_kick_idx        = -1
        S.tm_snare_idx       = -1
        S.tm_kit_idx         = -1
        S.tm_fallback_idx    = -1
        S.mc_drum_src_idx    = -1
        S.mc_drum_tgt_idx    = -1
        S.mc_keys_src_idx    = -1
        S.mc_keys_rh_tgt_idx = -1
        S.mc_keys_lh_tgt_idx = -1
        S.mc_pk_conv_tgt_idx = -1
        S.mc_5k_tgt_idx      = -1
        S.mc_gtr_src_idx      = -1
        S.mc_gtr_tgt_idx      = -1
        S.ma_midi_src_idx    = -1
        S.diff_pk_x_idx      = -1
        S.diff_pk_h_idx      = -1
        S.diff_pk_m_idx      = -1
        S.diff_pk_e_idx      = -1
        S.diff_5k_idx        = -1
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        -- Re-resolve theme index from persisted name (themes list is already loaded)
        S.venue_theme_idx = 0
        if S.venue_themes then
            for i, t in ipairs(S.venue_themes) do
                if t.stem == S.venue_theme_name then
                    S.venue_theme_idx = i
                    break
                end
            end
        end
        SetDefaultTempoTracks()
        SetDefaultMIDITracks()
        SetDefaultDifficultyTracks()
    end

    local sel_s, sel_e = GetTimeSelection()
    if not S.all_track_list then RefreshTrackLists() end
    local audio_tracks = S.audio_track_list
    local midi_tracks  = S.midi_track_list

    r.ImGui_SetNextWindowSize(ctx, 560, 660, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band General Helper', true)
    if visible then
        local _bp  = 40
        local bw_und = r.ImGui_CalcTextSize(ctx, 'Undo') + _bp
        local _new_tab = ''

        if r.ImGui_BeginTabBar(ctx, '##tabs') then

            ------------------------------------------------------------
            -- General tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'General') then
                _new_tab = 'General'
                local bw_aall = r.ImGui_CalcTextSize(ctx, 'Align all audio') + _bp
                local bw_acin = r.ImGui_CalcTextSize(ctx, 'Align count-in')  + _bp
                local bw_fade = r.ImGui_CalcTextSize(ctx, 'Fade out')         + _bp

                SectionHeader('Audio alignment')

                if r.ImGui_Button(ctx, 'Align all audio', bw_aall, 24) then
                    RunAction(AlignAllAudio)
                end
                Tooltip(TIPS.align_all_audio)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Align count-in', bw_acin, 24) then
                    RunAction(AlignCountIn)
                end
                Tooltip(TIPS.align_count_in)

                r.ImGui_Separator(ctx)
                SectionHeader('Song fade out')
                if r.ImGui_Button(ctx, 'Fade out', bw_fade, 24) then
                    RunAction(CreateSongFadeOut)
                end
                Tooltip(TIPS.song_fade_out)

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

                r.ImGui_Separator(ctx)
                SectionHeader('Venue preview')
                r.ImGui_Text(ctx, 'Preview size')
                r.ImGui_SameLine(ctx)
                local _t_vpscl = TIPS.venue_preview_scale
                if r.ImGui_RadioButton(ctx, '1x##vpscl', S.venue_preview_scale == 1) then
                    S.venue_preview_scale = 1
                end
                Tooltip(_t_vpscl)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, '2x##vpscl', S.venue_preview_scale == 2) then
                    S.venue_preview_scale = 2
                end
                Tooltip(_t_vpscl)
                r.ImGui_Text(ctx, 'Sprites')
                r.ImGui_SameLine(ctx)
                local _t_vpan = TIPS.venue_preview_animate
                if r.ImGui_RadioButton(ctx, 'Animated##vpan_g', S.venue_preview_animate) then
                    S.venue_preview_animate = true
                end
                Tooltip(_t_vpan)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Still##vpan_g', not S.venue_preview_animate) then
                    S.venue_preview_animate = false
                end
                Tooltip(_t_vpan)
                if not VenueSpriteFoldersFound() then
                    r.ImGui_Spacing(ctx)
                    r.ImGui_TextDisabled(ctx,
                        'Venue spritesheets not found - check readme for installation instructions')
                end

                r.ImGui_Separator(ctx)
                SectionHeader('WIP tabs')
                r.ImGui_Text(ctx, 'Show WIPs?')
                r.ImGui_SameLine(ctx)
                local _t_wip = TIPS.show_wip_tabs
                if r.ImGui_RadioButton(ctx, 'No##wip', not S.show_wip_tabs) then
                    S.show_wip_tabs = false
                end
                Tooltip(_t_wip)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Yes##wip', S.show_wip_tabs) then
                    S.show_wip_tabs = true
                end
                Tooltip(_t_wip)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Difficulty tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Difficulty') then
                _new_tab = 'Difficulty'
                DrawDifficultyTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end


            ------------------------------------------------------------
            -- Tab Input guide
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Tab Input') then
                _new_tab = 'Tab Input'
                DrawTabInputTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- MIDI tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'MIDI') then
                _new_tab = 'MIDI'
                DrawMIDITab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Venue tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Venue') then
                _new_tab = 'Venue'
                DrawVenueTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Tempo Map tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Tempo Map') then
                _new_tab = 'Tempo Map'
                local bw_ctx   = r.ImGui_CalcTextSize(ctx, 'Show context')              + _bp
                local bw_ali   = r.ImGui_CalcTextSize(ctx, 'Align audio')                + _bp
                local bw_ebpm  = r.ImGui_CalcTextSize(ctx, 'Estimate initial BPM')       + _bp
                local bw_gen   = r.ImGui_CalcTextSize(ctx, 'Generate tempo map')         + _bp
                local bw_clrtm = r.ImGui_CalcTextSize(ctx, 'Clear markers')              + _bp
                local bw_c643  = r.ImGui_CalcTextSize(ctx, 'Convert 6/4 \xe2\x86\x92 3/4') + _bp

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

                r.ImGui_Text(ctx, 'FULL KIT   ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.tm_kit_idx = TrackCombo('##tm_kit', S.tm_kit_idx, audio_tracks)
                Tooltip(TIPS.kit_track)

                local slider_w = 200

                SectionHeader('Drum sources')
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_rms_threshold = r.ImGui_SliderDouble(
                    ctx, 'RMS threshold', S.tm_rms_threshold, 0.001, 0.5, '%.3f')
                SliderTooltip(TIPS.tm_rms_threshold)

                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.tm_rms_window_ms = r.ImGui_SliderInt(
                    ctx, 'RMS window (ms)', S.tm_rms_window_ms, 5, 30)
                SliderTooltip(TIPS.tm_rms_window_ms)

                SectionHeader('Analysis')
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
                local ts_ch, ts_new = r.ImGui_InputText(ctx, 'Time sig (empty=inherit)', S.tm_timesig_text)
                Tooltip(TIPS.tm_timesig_num)
                if ts_ch then
                    S.tm_timesig_text = ts_new
                    local text = ts_new:match('^%s*(.-)%s*$')
                    if text == '' then
                        S.tm_timesig_num   = 0
                        S.tm_timesig_denom = 4
                    else
                        local n, d = text:match('^(%d+)%s*/%s*(%d+)$')
                        if n then
                            S.tm_timesig_num   = tonumber(n) or 0
                            S.tm_timesig_denom = tonumber(d) or 4
                        else
                            local n_only = text:match('^(%d+)$')
                            if n_only then
                                S.tm_timesig_num   = tonumber(n_only) or 0
                                S.tm_timesig_denom = 4
                            end
                        end
                    end
                end

                _, S.tm_override_failsafe = r.ImGui_Checkbox(
                    ctx, 'Override BPM limit', S.tm_override_failsafe)
                Tooltip(TIPS.tm_override_failsafe)

                r.ImGui_Spacing(ctx)

                if r.ImGui_Button(ctx, 'Show context', bw_ctx, 24) then
                    RunAction(ShowTempoContext)
                end
                Tooltip(TIPS.show_ctx)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Align audio', bw_ali, 24) then
                    RunAction(AlignAudioTracks)
                end
                Tooltip(TIPS.align_audio)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Estimate initial BPM', bw_ebpm, 24) then
                    RunAction(EstimateInitialBPM)
                end
                Tooltip(TIPS.est_bpm)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Generate tempo map', bw_gen, 24) then
                    RunAction(GenerateTempoMap)
                end
                Tooltip(TIPS.gen_tempo)

                if r.ImGui_Button(ctx, 'Clear markers', bw_clrtm, 24) then
                    RunAction(ClearGeneratedTempoMarkers)
                end
                Tooltip(TIPS.clear_tempo)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Convert 6/4 \xe2\x86\x92 3/4', bw_c643, 24) then
                    RunAction(ConvertTimeSig6to3)
                end
                Tooltip(TIPS.convert_6_4_to_3_4)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Drums tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Drums') then
                _new_tab = 'Drums'
                local bw_cvt = r.ImGui_CalcTextSize(ctx, 'Convert Drums') + _bp

                r.ImGui_Text(ctx, 'Source track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.mc_drum_src_idx = TrackCombo('##mc_drum_src', S.mc_drum_src_idx, midi_tracks)
                Tooltip(TIPS.mc_drum_src)

                r.ImGui_Text(ctx, 'Target track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.mc_drum_tgt_idx = TrackCombo('##mc_drum_tgt', S.mc_drum_tgt_idx, midi_tracks)
                Tooltip(TIPS.mc_drum_tgt)

                local slider_w = 200

                SectionHeader('Options')
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.mc_ghost_thresh = r.ImGui_SliderInt(
                    ctx, 'Ghost threshold (vel)', S.mc_ghost_thresh, 0, 40)
                SliderTooltip(TIPS.mc_ghost_thresh)

                local crash_label = S.mc_crash_to_green and 'Crashes \xe2\x86\x92 Green' or 'Crashes \xe2\x86\x92 Yellow'
                if r.ImGui_Button(ctx, crash_label, 160, 22) then
                    S.mc_crash_to_green = not S.mc_crash_to_green
                end
                Tooltip(TIPS.mc_crash_color)

                r.ImGui_SameLine(ctx)
                _, S.mc_pro_drums = r.ImGui_Checkbox(ctx, 'Pro Drums', S.mc_pro_drums)
                Tooltip(TIPS.mc_pro_drums)

                SectionHeader('Workflow')
                local _t_dru = TIPS.mc_drum_preview
                if r.ImGui_RadioButton(ctx, 'Auto-insert##dru', not S.mc_drum_preview) then
                    S.mc_drum_preview = false
                end
                Tooltip(_t_dru)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Preview only##dru', S.mc_drum_preview) then
                    S.mc_drum_preview = true
                end
                Tooltip(_t_dru)

                r.ImGui_Spacing(ctx)
                if r.ImGui_Button(ctx, 'Convert Drums', bw_cvt, 24) then
                    RunAction(ConvertDrums)
                end

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Keys tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Keys') then
                _new_tab = 'Keys'
                DrawKeysTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Guitar tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Guitar') then
                _new_tab = 'Guitar'
                local bw_cvt = r.ImGui_CalcTextSize(ctx, 'Convert Guitar') + _bp
                local bw_val = r.ImGui_CalcTextSize(ctx, 'Validate Guitar') + _bp

                SectionHeader('Source / Target')

                r.ImGui_Text(ctx, 'Source track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.mc_gtr_src_idx = TrackCombo('##mc_gtr_src', S.mc_gtr_src_idx, midi_tracks)
                Tooltip(TIPS.mc_gtr_src)

                r.ImGui_Text(ctx, 'Target track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                S.mc_gtr_tgt_idx = TrackCombo('##mc_gtr_tgt', S.mc_gtr_tgt_idx, midi_tracks)
                Tooltip(TIPS.mc_gtr_tgt)

                local slider_w = 200

                SectionHeader('Conversion Options')
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.mc_gtr_wrap_gap_ms = r.ImGui_SliderInt(
                    ctx, 'Phrase gap (ms)', S.mc_gtr_wrap_gap_ms, 50, 1000)
                SliderTooltip(TIPS.mc_gtr_wrap_gap)

                r.ImGui_Text(ctx, 'Max chord:')
                r.ImGui_SameLine(ctx)
                local _t_gmc = TIPS.mc_gtr_max_chord
                if r.ImGui_RadioButton(ctx, '2 notes##gtr', S.mc_gtr_max_chord == 2) then
                    S.mc_gtr_max_chord = 2
                end
                Tooltip(_t_gmc)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, '3 notes##gtr', S.mc_gtr_max_chord == 3) then
                    S.mc_gtr_max_chord = 3
                end
                Tooltip(_t_gmc)

                _, S.mc_gtr_allow_14 = r.ImGui_Checkbox(ctx, 'Allow 1-4 chords##gtr', S.mc_gtr_allow_14)
                Tooltip(TIPS.mc_gtr_allow_14)

                SectionHeader('Workflow')
                local _t_gwf = TIPS.mc_gtr_workflow
                if r.ImGui_RadioButton(ctx, 'Preview##gtr', S.mc_gtr_workflow == 0) then
                    S.mc_gtr_workflow = 0
                end
                Tooltip(_t_gwf)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Auto-insert##gtr', S.mc_gtr_workflow == 1) then
                    S.mc_gtr_workflow = 1
                end
                Tooltip(_t_gwf)

                r.ImGui_Spacing(ctx)
                local no_src = S.mc_gtr_src_idx < 0
                local no_tgt = S.mc_gtr_tgt_idx < 0
                if no_src or no_tgt then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Convert Guitar', bw_cvt, 24) then
                    RunAction(ConvertGuitar)
                end
                if no_src or no_tgt then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.mc_gtr_convert)

                r.ImGui_SameLine(ctx)
                if no_tgt then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Validate Guitar', bw_val, 24) then
                    RunAction(ValidateGuitar)
                end
                if no_tgt then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.mc_gtr_validate)

                r.ImGui_EndTabItem(ctx)
            end

            r.ImGui_EndTabBar(ctx)
        end

        if _new_tab ~= _active_tab then
            if _active_tab ~= '' then S.last_result = nil; S.status = '' end
            _active_tab = _new_tab
        end

        ----------------------------------------------------------------
        -- Time selection info + status panel (always visible below tabs)
        ----------------------------------------------------------------
        r.ImGui_Separator(ctx)
        if sel_s then
            r.ImGui_Text(ctx, ('Time selection: %s - %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
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
            for line in (S.last_result .. '\n'):gmatch('([^\n]*)\n') do
                if line ~= '' then
                    local left, right = line:match('^([^\t]*)\t(.*)$')
                    if left then
                        r.ImGui_Text(ctx, left)
                        r.ImGui_SameLine(ctx, 190)
                        r.ImGui_Text(ctx, right)
                    else
                        r.ImGui_Text(ctx, line)
                    end
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
