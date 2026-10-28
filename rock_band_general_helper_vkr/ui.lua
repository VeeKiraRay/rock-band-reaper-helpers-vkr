-- UI loop
-- Requires: S, TIPS, r, ctx (globals)
-- Requires: all action functions, RefreshTrackLists, Tooltip, SliderTooltip,
--           SectionHeader, DrawGeneralLinksTab (globals)
-- Requires: TrackCombo, DrawResultPanel, DrawHelperFooter (lib/reaper_helper_ui.lua, shared
--           with the Instrument Helper).
-- Note: r.defer(Loop) is called at the end of this file.

local _active_proj = r.EnumProjects(-1, '')
local _active_tab  = ''

-- Track lists rebuild themselves after a project edit (at most once a second,
-- 5 s safety re-read) - lib/reaper_helper_common.lua, MakeProjectPoll.
local _track_poll = MakeProjectPoll(1.0, 5.0)

-- Footer parts this window shows (lib/reaper_helper_ui.lua, DrawHelperFooter).
local FOOTER = {}

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
        S.key_audio_idx      = -1   -- Metadata > Song key audio tracks; re-defaulted below
        S.key_bass_idx       = -1
        -- Metadata > Difficulty results describe the PREVIOUS project's charts. Leaving
        -- them on screen after a switch would attribute one song's ranks to another.
        S.diff_suggestions   = nil
        S.key_suggestion     = nil   -- Metadata > Song key, same reason
        S.key_audio          = nil
        SongKeyAudioCancel()          -- a running audio read belongs to the old project
        S.key_check_tonic    = nil
        S.key_check_minor    = false
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
        -- Workflow templates are project-independent, but re-scan the folder
        -- fresh and re-resolve the selected index from the new project's
        -- persisted name (workflow_state itself is repopulated by LoadSettings above)
        S.workflow_files    = nil
        S.workflow_file_idx = 0
        SetDefaultTracks()
    end

    -- Poll first, so the first frame builds the lists once, not twice.
    local tracks_due = _track_poll()
    if tracks_due or not S.all_track_list then RefreshTrackLists() end

    -- Metadata > Song key's audio job: a ~20 ms slice per frame, whichever tab is showing.
    SongKeyTick()
    local audio_tracks = S.audio_track_list

    r.ImGui_SetNextWindowSize(ctx, 560, 660, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, WINDOW_TITLE, true)
    if visible then
        local _new_tab = ''

        -- The view scrolls inside this child; the footer below it never moves.
        local body_visible = BeginScrollBody('##body', -HelperFooterHeight(FOOTER))
        if body_visible and r.ImGui_BeginTabBar(ctx, '##tabs') then

            ------------------------------------------------------------
            -- General tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'General') then
                _new_tab = 'General'

                if r.ImGui_BeginTabBar(ctx, '##general_subtabs') then

                    ------------------------------------------------
                    -- General > Actions sub-tab
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Actions') then
                        SectionHeader('Audio alignment')

                        local bw_align = BtnGroupWidth({ 'Import stems', 'Align all audio', 'Align count-in' })
                        if Btn('Import stems', BTN_H, bw_align) then
                            RunAction(ImportStems)
                        end
                        Tooltip(TIPS.import_stems)
                        r.ImGui_SameLine(ctx)
                        if Btn('Align all audio', BTN_H, bw_align) then
                            RunAction(AlignAllAudio)
                        end
                        Tooltip(TIPS.align_all_audio)
                        r.ImGui_SameLine(ctx)
                        if Btn('Align count-in', BTN_H, bw_align) then
                            RunAction(AlignCountIn)
                        end
                        Tooltip(TIPS.align_count_in)

                        r.ImGui_Separator(ctx)
                        SectionHeader('Song fade out')
                        if Btn('Fade out', BTN_H) then
                            RunAction(CreateSongFadeOut)
                        end
                        Tooltip(TIPS.song_fade_out)


                        r.ImGui_EndTabItem(ctx)
                    end

                    ------------------------------------------------
                    -- General > Settings sub-tab
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Settings') then
                        local lbl_col_gen = LabelColWidth({ 'Preview size', 'Sprites', 'Show WIPs?' })
                        local radio_w_gen = RadioGroupWidth({ '1x', '2x', 'Animated', 'Still', 'No', 'Yes' })

                        SectionHeader('Venue preview')
                        r.ImGui_Text(ctx, 'Preview size')
                        r.ImGui_SameLine(ctx, lbl_col_gen)
                        local _t_vpscl = TIPS.venue_preview_scale
                        if r.ImGui_RadioButton(ctx, '1x##vpscl', S.venue_preview_scale == 1) then
                            S.venue_preview_scale = 1
                        end
                        Tooltip(_t_vpscl)
                        r.ImGui_SameLine(ctx, lbl_col_gen + radio_w_gen)
                        if r.ImGui_RadioButton(ctx, '2x##vpscl', S.venue_preview_scale == 2) then
                            S.venue_preview_scale = 2
                        end
                        Tooltip(_t_vpscl)
                        r.ImGui_Text(ctx, 'Sprites')
                        r.ImGui_SameLine(ctx, lbl_col_gen)
                        local _t_vpan = TIPS.venue_preview_animate
                        if r.ImGui_RadioButton(ctx, 'Animated##vpan_g', S.venue_preview_animate) then
                            S.venue_preview_animate = true
                        end
                        Tooltip(_t_vpan)
                        r.ImGui_SameLine(ctx, lbl_col_gen + radio_w_gen)
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
                        r.ImGui_SameLine(ctx, lbl_col_gen)
                        local _t_wip = TIPS.show_wip_tabs
                        if r.ImGui_RadioButton(ctx, 'No##wip', not S.show_wip_tabs) then
                            S.show_wip_tabs = false
                        end
                        Tooltip(_t_wip)
                        r.ImGui_SameLine(ctx, lbl_col_gen + radio_w_gen)
                        if r.ImGui_RadioButton(ctx, 'Yes##wip', S.show_wip_tabs) then
                            S.show_wip_tabs = true
                        end
                        Tooltip(_t_wip)

                        r.ImGui_Separator(ctx)
                        SectionHeader('Settings')

                        local bw_settings = BtnGroupWidth({ 'Save', 'Load' })
                        if Btn('Save', BTN_H, bw_settings) then
                            SaveSettings()
                            S.status = 'Settings saved to project.'
                        end
                        Tooltip(TIPS.save)
                        r.ImGui_SameLine(ctx)
                        if Btn('Load', BTN_H, bw_settings) then
                            if LoadSettings() then
                                S.status = 'Settings loaded from project.'
                            else
                                S.status = 'No saved settings found in this project.'
                            end
                        end
                        Tooltip(TIPS.load)

                        r.ImGui_EndTabItem(ctx)
                    end

                    ------------------------------------------------
                    -- General > Other tools sub-tab
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Other tools') then
                        DrawGeneralLinksTab()
                        r.ImGui_EndTabItem(ctx)
                    end

                    r.ImGui_EndTabBar(ctx)
                end

                r.ImGui_EndTabItem(ctx)
            end


            ------------------------------------------------------------
            -- Workflow tab (ui_workflow.lua)
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Workflow') then
                _new_tab = 'Workflow'
                DrawGeneralWorkflowTab()
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Events tab (ui_venue_events.lua): General + Manual gen
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Events') then
                _new_tab = 'Events'
                DrawEventsTab()
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
            -- Metadata tab
            --
            -- Last of the stable tabs, immediately before the WIP ones, so the
            -- stable/WIP split stays visually intact.
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Metadata') then
                _new_tab = 'Metadata'
                DrawMetadataTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Tempo Map tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Tempo Map') then
                _new_tab = 'Tempo Map'

                r.ImGui_Text(ctx, 'KICK track ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.tm_kick_idx = TrackCombo('##tm_kick', S.tm_kick_idx, audio_tracks)
                Tooltip(TIPS.kick_track)

                r.ImGui_Text(ctx, 'SNARE track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.tm_snare_idx = TrackCombo('##tm_snare', S.tm_snare_idx, audio_tracks)
                Tooltip(TIPS.snare_track)

                r.ImGui_Text(ctx, 'FULL KIT   ')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
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

                if Btn('Show context', BTN_H) then
                    RunAction(ShowTempoContext)
                end
                Tooltip(TIPS.show_ctx)
                r.ImGui_SameLine(ctx)
                if Btn('Align audio', BTN_H) then
                    RunAction(AlignAudioTracks)
                end
                Tooltip(TIPS.align_audio)
                r.ImGui_SameLine(ctx)
                if Btn('Estimate initial BPM', BTN_H) then
                    RunAction(EstimateInitialBPM)
                end
                Tooltip(TIPS.est_bpm)
                r.ImGui_SameLine(ctx)
                if Btn('Generate tempo map', BTN_H) then
                    RunAction(GenerateTempoMap)
                end
                Tooltip(TIPS.gen_tempo)

                if Btn('Clear markers', BTN_H) then
                    RunAction(ClearGeneratedTempoMarkers)
                end
                Tooltip(TIPS.clear_tempo)
                r.ImGui_SameLine(ctx)
                if Btn('Convert 6/4 \xe2\x86\x92 3/4', BTN_H) then
                    RunAction(ConvertTimeSig6to3)
                end
                Tooltip(TIPS.convert_6_4_to_3_4)

                r.ImGui_EndTabItem(ctx)
            end


            r.ImGui_EndTabBar(ctx)
        end

        if _new_tab ~= _active_tab then
            if _active_tab ~= '' then S.last_result = nil; S.status = '' end
            _active_tab = _new_tab
        end

        if body_visible then DrawResultPanel() end
        r.ImGui_EndChild(ctx)   -- always paired with BeginScrollBody

        ----------------------------------------------------------------
        -- Footer: time selection, status, Refresh / Copy / Undo
        ----------------------------------------------------------------
        DrawHelperFooter(FOOTER)   -- lib/reaper_helper_ui.lua

        r.ImGui_End(ctx)
    end

    if open then r.defer(Loop) end
end

r.defer(Loop)
