-- UI loop
-- Requires: S, TIPS, r, ctx (globals)
-- Requires: all action functions, RefreshTrackLists, Tooltip, SliderTooltip,
--           SectionHeader, DrawGeneralLinksTab (globals)
-- Requires: TrackCombo, DrawResultPanel, DrawHelperFooter (lib/reaper_helper_ui.lua) - they
--           live there because the General Helper and the standalone
--           rock_band_midi_pattern_vkr.lua draw them too, and neither can
--           dofile this file (its last line is a bare r.defer(Loop)).
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
        S.mn_midi_idx        = -1
        S.ms_ref_idx         = -1
        -- Pattern sub-tab: the captured patterns are take-relative PPQ offsets
        -- labelled with the old project's measure numbers, so they cannot carry
        -- over. Shared with the standalone window, which resets the same way.
        ResetMIDIPatternState()
        S.diff_pk_x_idx      = -1
        S.diff_pk_h_idx      = -1
        S.diff_pk_m_idx      = -1
        S.diff_pk_e_idx      = -1
        S.diff_5k_idx        = -1
        S.diff_gtr_idx       = -1
        S.diff_bass_idx      = -1
        S.diff_drums_idx     = -1
        S.diff_drums2x_idx   = -1
        -- Overdrive: a pending replace confirmation and the overview strip both
        -- describe the previous project's tracks.
        S.od_pending         = nil
        S.od_overview        = nil
        -- Keys > Tuner: its accessors, chart and key belong to the old project.
        StopChordTuner()
        S.ct_keys_idx, S.ct_bass_idx = -1, -1
        S.ct_result, S.ct_chart, S.ct_key, S.ct_history, S.ct_note_history = nil, nil, nil, {}, {}
        S.ct_pass, S.ct_pass_job, S.ct_pass_frames = nil, nil, {}
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        SetDefaultMIDITracks()
        SetDefaultDifficultyTracks()
        SetDefaultChordTunerTracks()
    end

    -- Poll first, so the first frame builds the lists once, not twice.
    local tracks_due = _track_poll()
    if tracks_due or not S.all_track_list then RefreshTrackLists() end
    local midi_tracks  = S.midi_track_list

    S.ct_tab_active = false   -- the Keys > Tuner sub-tab sets it while drawn
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
                        SectionHeader('Drums 2x kicks')
                        -- MarkDoubleBassKicks is deliberately NOT drawn here.
                        -- It writes pitch 95, which Rock Band 3 discards, so on an
                        -- RB3 chart it turns real kicks in the 2x track into notes
                        -- the game never plays. The function and its tests are kept
                        -- for a future version that supports games which do read 95;
                        -- it comes back with that multi-game UI, not before.
                        if Btn('Remove 2x kicks', BTN_H) then
                            RunAction(Remove2XKicks)
                        end
                        Tooltip(TIPS.drums_2x_remove_kicks)
                        r.ImGui_EndTabItem(ctx)
                    end

                    ------------------------------------------------
                    -- General > Settings sub-tab
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Settings') then
                        local lbl_col_gen = LabelColWidth({ 'Show WIPs?' })
                        local radio_w_gen = RadioGroupWidth({ 'No', 'Yes' })

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
            -- Difficulty tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Difficulty') then
                _new_tab = 'Difficulty'
                DrawDifficultyTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Overdrive tab
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Overdrive') then
                _new_tab = 'Overdrive'
                DrawOverdriveTab(ctx)
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
            -- Keys tab: Tuner (always), WIP (the MIDI converters, Show WIPs = Yes)
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Keys') then
                _new_tab = 'Keys'
                if r.ImGui_BeginTabBar(ctx, '##keys_subtabs') then
                    if r.ImGui_BeginTabItem(ctx, 'Tuner') then
                        S.ct_tab_active = true
                        DrawKeysTunerTab()
                        r.ImGui_EndTabItem(ctx)
                    end
                    if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'WIP') then
                        DrawKeysTab(ctx)
                        r.ImGui_EndTabItem(ctx)
                    end
                    r.ImGui_EndTabBar(ctx)
                end
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Drums tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Drums') then
                _new_tab = 'Drums'

                r.ImGui_Text(ctx, 'Source track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.mc_drum_src_idx = TrackCombo('##mc_drum_src', S.mc_drum_src_idx, midi_tracks)
                Tooltip(TIPS.mc_drum_src)

                r.ImGui_Text(ctx, 'Target track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.mc_drum_tgt_idx = TrackCombo('##mc_drum_tgt', S.mc_drum_tgt_idx, midi_tracks)
                Tooltip(TIPS.mc_drum_tgt)

                local slider_w = 200

                SectionHeader('Options')
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.mc_ghost_thresh = r.ImGui_SliderInt(
                    ctx, 'Ghost threshold (vel)', S.mc_ghost_thresh, 0, 40)
                SliderTooltip(TIPS.mc_ghost_thresh)

                local crash_label = S.mc_crash_to_green and 'Crashes \xe2\x86\x92 Green' or 'Crashes \xe2\x86\x92 Yellow'
                if Btn(crash_label, 22) then
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
                if Btn('Convert Drums', BTN_H) then
                    RunAction(ConvertDrums)
                end

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Guitar tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Guitar') then
                _new_tab = 'Guitar'

                SectionHeader('Source / Target')

                r.ImGui_Text(ctx, 'Source track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.mc_gtr_src_idx = TrackCombo('##mc_gtr_src', S.mc_gtr_src_idx, midi_tracks)
                Tooltip(TIPS.mc_gtr_src)

                r.ImGui_Text(ctx, 'Target track')
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                S.mc_gtr_tgt_idx = TrackCombo('##mc_gtr_tgt', S.mc_gtr_tgt_idx, midi_tracks)
                Tooltip(TIPS.mc_gtr_tgt)

                local slider_w = 200

                SectionHeader('Conversion Options')
                r.ImGui_SetNextItemWidth(ctx, slider_w)
                _, S.mc_gtr_wrap_gap_ms = r.ImGui_SliderInt(
                    ctx, 'Phrase gap (ms)', S.mc_gtr_wrap_gap_ms, 50, 1000)
                SliderTooltip(TIPS.mc_gtr_wrap_gap)

                local lbl_col_gtr = LabelColWidth({ 'Max chord:' })
                local radio_w_gtr = RadioGroupWidth({
                    '2 notes', '3 notes', 'Preview', 'Auto-insert',
                })

                r.ImGui_Text(ctx, 'Max chord:')
                r.ImGui_SameLine(ctx, lbl_col_gtr)
                local _t_gmc = TIPS.mc_gtr_max_chord
                if r.ImGui_RadioButton(ctx, '2 notes##gtr', S.mc_gtr_max_chord == 2) then
                    S.mc_gtr_max_chord = 2
                end
                Tooltip(_t_gmc)
                r.ImGui_SameLine(ctx, lbl_col_gtr + radio_w_gtr)
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
                r.ImGui_SameLine(ctx, radio_w_gtr)
                if r.ImGui_RadioButton(ctx, 'Auto-insert##gtr', S.mc_gtr_workflow == 1) then
                    S.mc_gtr_workflow = 1
                end
                Tooltip(_t_gwf)

                r.ImGui_Spacing(ctx)
                local no_src = S.mc_gtr_src_idx < 0
                local no_tgt = S.mc_gtr_tgt_idx < 0
                if no_src or no_tgt then r.ImGui_BeginDisabled(ctx) end
                if Btn('Convert Guitar', BTN_H) then
                    RunAction(ConvertGuitar)
                end
                if no_src or no_tgt then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.mc_gtr_convert)

                r.ImGui_SameLine(ctx)
                if no_tgt then r.ImGui_BeginDisabled(ctx) end
                if Btn('Validate Guitar', BTN_H) then
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

        if body_visible then DrawResultPanel() end
        r.ImGui_EndChild(ctx)   -- always paired with BeginScrollBody

        ----------------------------------------------------------------
        -- Footer: time selection, status, Refresh / Copy / Undo
        ----------------------------------------------------------------
        DrawHelperFooter(FOOTER)   -- lib/reaper_helper_ui.lua

        r.ImGui_End(ctx)
    end

    ChordTunerTick()   -- Keys > Tuner: stops itself when its sub-tab was not drawn
    if open then r.defer(Loop) else StopChordTuner() end
end

r.defer(Loop)