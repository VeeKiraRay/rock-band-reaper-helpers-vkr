-- Main UI render loop

local _browse_tooltip_suppressed = false
local _active_proj = r.EnumProjects(-1, '')
local _active_tab  = ''

-- FilteredTrackCombo, YINPresetCombo and DrawStatusResultPanel now live in
-- ui_common.lua - they are shared with the standalone rock_band_pitch_tuner_vkr.lua.

function Loop()
    -- Detect project switch (tabs). Reinitialize if the active project changed.
    local proj = r.EnumProjects(-1, '')
    if proj ~= _active_proj then
        _active_proj  = proj
        S.audio_idx         = 0
        S.midi_idx          = 0
        S.ref_idx           = 0
        S.lyrics_path       = ''
        S.harm_src_idx      = 0
        S.harm_dst1_idx     = 0
        S.harm_dst2_idx     = 0
        S.harm_dst3_idx     = 0
        S.all_track_list    = nil
        S.midi_track_list   = nil
        S.audio_track_list  = nil
        S.last_result = nil
        if S.tuner_active then StopTuner('Pitch tuner stopped: project switched.') end
        S.tuner_pitch       = nil
        S.tuner_prev_pitch  = nil
        S.tuner_pitch_name  = nil
        S.tuner_pitch_hz    = nil
        S.tuner_confidence  = nil
        S.tuner_pitch_ts    = nil
        S.tuner_quiet_since = nil
        S.tuner_history     = {}
        RefreshTrackLists()
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        SetDefaultTracks()
        AutoDetectLyricsFile()
    end

    -- Run the pitch tuner poll before any UI rendering.
    RunTuner()

    -- Build cached filtered lists on first frame if not yet populated.
    if not S.all_track_list then RefreshTrackLists() end
    local midi_tracks  = S.midi_track_list
    local audio_tracks = S.audio_track_list
    local sel_s, sel_e = GetTimeSelection()

    r.ImGui_SetNextWindowSize(ctx, 580, 1060, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, WINDOW_TITLE, true)
    if visible then
        ----------------------------------------------------------------
        -- Global: track selectors (MIDI first, then audio source)
        ----------------------------------------------------------------
        r.ImGui_Text(ctx, 'MIDI destination track  (must already contain a MIDI item)')
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S.midi_idx = FilteredTrackCombo('##midi', S.midi_idx, midi_tracks)

        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Audio source track')
        r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
        S.audio_idx = FilteredTrackCombo('##audio', S.audio_idx, audio_tracks)

        if sel_s then
            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, ('Time selection: %s - %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
        end

        r.ImGui_Separator(ctx)

        ----------------------------------------------------------------
        -- Tab bar
        ----------------------------------------------------------------
        S.tuner_tab_active = false   -- reset; set true below if Tuner tab is active
        local _new_tab = ''
        if r.ImGui_BeginTabBar(ctx, 'MainTabs') then

            ------------------------------------------------------------
            -- Tab: General
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'General') then
                _new_tab = 'General'

                if r.ImGui_BeginTabBar(ctx, '##general_subtabs') then

                    ------------------------------------------------
                    -- General > Actions sub-tab
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Actions') then
                        SectionHeader('Track lists')
                        if Btn('Refresh tracks', BTN_H) then
                            RefreshTrackLists()
                            S.status = 'Track lists refreshed.'
                        end
                        Tooltip(TIPS.track_refresh)

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
                        if r.ImGui_RadioButton(ctx, 'No##wip', not S.show_wip_tabs) then
                            S.show_wip_tabs = false
                        end
                        Tooltip(TIPS.show_wip_tabs)
                        r.ImGui_SameLine(ctx, lbl_col_gen + radio_w_gen)
                        if r.ImGui_RadioButton(ctx, 'Yes##wip', S.show_wip_tabs) then
                            S.show_wip_tabs = true
                        end
                        Tooltip(TIPS.show_wip_tabs)

                        r.ImGui_Separator(ctx)
                        SectionHeader('Settings')

                        local bw_settings = BtnGroupWidth({ 'Save', 'Load' })
                        if Btn('Save', BTN_H, bw_settings) then
                            SaveSettings()
                            S.status = 'Settings saved to project.'
                        end
                        Tooltip(TIPS.save_settings)
                        r.ImGui_SameLine(ctx)
                        if Btn('Load', BTN_H, bw_settings) then
                            if LoadSettings() then
                                S.status = 'Settings loaded from project.'
                            else
                                S.status = 'No saved settings found in this project.'
                            end
                        end
                        Tooltip(TIPS.load_settings)

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
            -- Tab: Tuner
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Tuner') then
                S.tuner_tab_active = true
                _new_tab = 'Tuner'
                DrawTunerTab()
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Pitch
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Pitch') then
                _new_tab = 'Pitch'
                DrawPitchTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Lyrics
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Lyrics') then
                _new_tab = 'Lyrics'
                r.ImGui_Spacing(ctx)

                SectionHeader('File')
                local lyric_basename = S.lyrics_path ~= ''
                    and (S.lyrics_path:match('[/\\]([^/\\]+)$') or S.lyrics_path)
                    or '(no file selected)'
                r.ImGui_Text(ctx, 'Selected: ' .. lyric_basename)
                if S.lyrics_path ~= '' then Tooltip(S.lyrics_path) end

                local bw_lyrics_file = BtnGroupWidth({ 'Auto-detect', 'Browse...' })
                if Btn('Auto-detect', BTN_H, bw_lyrics_file) then
                    local proj_path = r.GetProjectPath('')
                    if proj_path and proj_path ~= '' then
                        local sep = (proj_path:sub(-1) == '/' or proj_path:sub(-1) == '\\') and '' or '/'
                        local candidate = proj_path .. sep .. 'lyrics.txt'
                        local f = io.open(candidate, 'r')
                        if f then
                            f:close()
                            S.lyrics_path = candidate
                            S.status = 'Lyrics file found: lyrics.txt'
                            S.last_result = nil
                        else
                            S.status = 'No lyrics.txt found in project folder.'
                            S.last_result = nil
                        end
                    else
                        S.status = 'Project has no saved path - save the project first.'
                        S.last_result = nil
                    end
                end
                Tooltip(TIPS.lyrics_auto_detect)

                r.ImGui_SameLine(ctx)
                if Btn('Browse...', BTN_H, bw_lyrics_file) then
                    _browse_tooltip_suppressed = true
                    local proj_path = r.GetProjectPath('')
                    local start = ''
                    if proj_path and proj_path ~= '' then
                        local sep = (proj_path:sub(-1) == '/' or proj_path:sub(-1) == '\\') and '' or '\\'
                        start = proj_path .. sep
                    end
                    local ok, path = r.GetUserFileNameForRead(start, 'Select lyrics file', 'txt')
                    if ok and path and path ~= '' then
                        if not path:match('%.[Tt][Xx][Tt]$') then
                            S.status = 'Invalid file - please select a .txt file.'
                            S.last_result = nil
                        else
                            S.lyrics_path = path
                            S.status = 'Lyrics file: ' .. (path:match('[/\\]([^/\\]+)$') or path)
                            S.last_result = nil
                        end
                    end
                end
                if r.ImGui_IsItemHovered(ctx) and not r.ImGui_IsItemActive(ctx) and not _browse_tooltip_suppressed then
                    r.ImGui_SetTooltip(ctx, TIPS.lyrics_browse)
                elseif not r.ImGui_IsItemHovered(ctx) then
                    _browse_tooltip_suppressed = false
                end

                r.ImGui_Separator(ctx)
                SectionHeader('Actions')
                local bw_lyrics_actions = BtnGroupWidth({ 'Clear lyrics', 'Assign lyrics', 'Create phrases' })
                if Btn('Clear lyrics', BTN_H, bw_lyrics_actions) then
                    RunAction(ClearLyricsAction)
                end
                Tooltip(TIPS.lyrics_clear)

                local assign_disabled = (S.lyrics_path == '')
                r.ImGui_SameLine(ctx)
                if assign_disabled then r.ImGui_BeginDisabled(ctx) end
                if Btn('Assign lyrics', BTN_H, bw_lyrics_actions) then
                    RunAction(AssignLyricsAction)
                end
                if assign_disabled then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.lyrics_assign)

                r.ImGui_SameLine(ctx)
                if assign_disabled then r.ImGui_BeginDisabled(ctx) end
                if Btn('Create phrases', BTN_H, bw_lyrics_actions) then
                    RunAction(CreatePhrasesAction)
                end
                if assign_disabled then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.create_phrases)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Pitch slide
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Pitch slide') then
                _new_tab = 'Pitch slide'
                DrawPitchSlideTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Harmonies
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Harmonies') then
                _new_tab = 'Harmonies'
                DrawHarmoniesTab(ctx)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Validation
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Validation') then
                _new_tab = 'Validation'
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Phrase validation')
                r.ImGui_Spacing(ctx)
                if Btn('Validate phrases', BTN_H) then
                    RunAction(ValidatePhrases)
                end
                Tooltip(TIPS.validate_phrases)
                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Phrase Similarity Check')
                r.ImGui_Spacing(ctx)

                local lbl_col_val = LabelColWidth({
                    'Similarity threshold (%)', 'Same key only (ignore transposition)',
                })

                local _
                r.ImGui_Text(ctx, 'Similarity threshold (%)')
                r.ImGui_SameLine(ctx, lbl_col_val)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.phrase_sim_threshold = r.ImGui_SliderInt(ctx,
                    '##psimthr', S.phrase_sim_threshold, 50, 100)
                SliderTooltip(TIPS.phrase_sim_threshold)

                r.ImGui_Text(ctx, 'Same key only (ignore transposition)')
                r.ImGui_SameLine(ctx, lbl_col_val)
                _, S.phrase_same_key = r.ImGui_Checkbox(ctx, '##psk', S.phrase_same_key)
                Tooltip(TIPS.phrase_same_key)

                r.ImGui_Spacing(ctx)
                if Btn('Check Phrase Similarity', BTN_H) then
                    RunAction(PhraseSimilarityAction)
                end
                Tooltip(TIPS.phrase_sim_check)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- WIP: Note Placement tab
            ------------------------------------------------------------
            if S.show_wip_tabs and r.ImGui_BeginTabItem(ctx, 'Note Placement') then
                _new_tab = 'Note Placement'
                r.ImGui_Spacing(ctx)
                local _
                if r.ImGui_BeginTabBar(ctx, '##placement_subtabs') then

                    ------------------------------------------------
                    -- Sub-tab: Auto Detection
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Auto Detection') then
                        r.ImGui_Spacing(ctx)
                        SectionHeader('MIDI output', 'Reset##midi', ResetMIDIOutput, TIPS.reset_midi)
                        _, S.velocity = r.ImGui_SliderInt(ctx, 'Velocity', S.velocity, 1, 127)
                        SliderTooltip(TIPS.velocity)

                        local pfmt = ('%%d  (%s)'):format(PitchName(S.pitch))
                        _, S.pitch = r.ImGui_SliderInt(ctx, 'Default pitch', S.pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, pfmt)
                        SliderTooltip(TIPS.pitch)

                        r.ImGui_Separator(ctx)
                        SectionHeader('Detection', 'Reset##det', ResetDetection, TIPS.reset_detection)

                        if Btn('Auto-tune from reference', BTN_H) then
                            RunAction(RunAutoTune)
                        end
                        Tooltip(TIPS.autotune)
                        r.ImGui_Spacing(ctx)

                        _, S.rms_threshold = r.ImGui_SliderDouble(ctx, 'RMS threshold',
                            S.rms_threshold, 0.001, 0.5, '%.4f')
                        SliderTooltip(TIPS.rms_threshold)

                        local lpf_fmt = (S.lpf_cutoff_hz > 0) and '%.0f Hz' or 'Off'
                        _, S.lpf_cutoff_hz = r.ImGui_SliderDouble(ctx, 'Low-pass cutoff',
                            S.lpf_cutoff_hz, 0, 8000, lpf_fmt)
                        SliderTooltip(TIPS.lpf_cutoff)

                        local split_fmt = (S.split_ratio > 0) and '%.0f%%' or 'Off'
                        _, S.split_ratio = r.ImGui_SliderDouble(ctx, 'Peak-split ratio',
                            S.split_ratio, 0, 95, split_fmt)
                        SliderTooltip(TIPS.split_ratio)

                        _, S.min_offset_ms = r.ImGui_SliderDouble(ctx, 'Min offset to next note (ms)',
                            S.min_offset_ms, 0, 500, '%.0f')
                        SliderTooltip(TIPS.min_offset_ms)

                        _, S.min_note_ms = r.ImGui_SliderDouble(ctx, 'Min note length (ms)',
                            S.min_note_ms, 10, 500, '%.0f')
                        SliderTooltip(TIPS.min_note_ms)

                        _, S.window_ms = r.ImGui_SliderDouble(ctx, 'RMS window (ms)',
                            S.window_ms, 5, 100, '%.0f')
                        SliderTooltip(TIPS.window_ms)

                        r.ImGui_Separator(ctx)
                        _, S.snap_enabled = r.ImGui_Checkbox(ctx, 'Snap to onsets', S.snap_enabled)
                        Tooltip(TIPS.snap_enabled)
                        if S.snap_enabled then
                            _, S.snap_window_ms = r.ImGui_SliderDouble(ctx, 'Snap window (ms)',
                                S.snap_window_ms, 10, 200, '%.0f')
                            SliderTooltip(TIPS.snap_window_ms)
                        end

                        r.ImGui_Separator(ctx)
                        if Btn('Dry run', BTN_H) then
                            RunAction(Preview)
                        end
                        Tooltip(TIPS.preview)

                        r.ImGui_SameLine(ctx)
                        if Btn('Generate (append)', BTN_H) then
                            RunAction(Generate)
                        end
                        Tooltip(TIPS.generate)

                        r.ImGui_SameLine(ctx)
                        if Btn('Generate (replace)', BTN_H) then
                            RunAction(function() Generate(true) end)
                        end
                        Tooltip(TIPS.generate_replace)

                        r.ImGui_EndTabItem(ctx)
                    end

                    ------------------------------------------------
                    -- Sub-tab: Draft Snap
                    ------------------------------------------------
                    if r.ImGui_BeginTabItem(ctx, 'Draft Snap') then
                        r.ImGui_Spacing(ctx)
                        r.ImGui_TextWrapped(ctx,
                            'Draw rough notes on the MIDI destination track (right count, approximate timing), ' ..
                            'then click Snap draft notes to lock boundaries to the audio.')
                        r.ImGui_Spacing(ctx)

                        _, S.draft_snap_window_ms = r.ImGui_SliderDouble(ctx, 'Snap window (ms)',
                            S.draft_snap_window_ms, 10, 300, '%.0f')
                        SliderTooltip(TIPS.draft_snap_window_ms)

                        r.ImGui_Separator(ctx)
                        if Btn('Snap draft notes', BTN_H) then
                            RunAction(SnapDraft)
                        end
                        Tooltip(TIPS.snap_draft)

                        r.ImGui_EndTabItem(ctx)
                    end

                    r.ImGui_EndTabBar(ctx)
                end

                r.ImGui_EndTabItem(ctx)
            end

            r.ImGui_EndTabBar(ctx)
        end

        if _new_tab ~= _active_tab then
            if _active_tab ~= '' then S.last_result = nil; S.status = '' end
            _active_tab = _new_tab
        end

        ----------------------------------------------------------------
        -- Global: status and result panel
        ----------------------------------------------------------------
        DrawStatusResultPanel(true)

        r.ImGui_End(ctx)
    end

    -- Closing the window ends the defer chain, so stop the tuner here or its
    -- audio accessor stays open (holding the source file) until REAPER exits.
    if not open and S.tuner_active then StopTuner() end

    if open then r.defer(Loop) end
end

r.defer(Loop)
