-- Main UI render loop

local _browse_tooltip_suppressed = false
local _active_proj = r.EnumProjects(-1, '')
local _active_tab  = ''

-- TrackCombo variant that stores and matches by REAPER track index (.idx field)
-- rather than list position, so selections survive filter list rebuilds.
function FilteredTrackCombo(label, reaper_idx, track_list)
    local preview = '<no tracks>'
    for _, t in ipairs(track_list) do
        if t.idx == reaper_idx then preview = t.label; break end
    end
    -- If selection is not in this filtered list, look it up in the full list
    -- so the preview still shows the track name rather than a blank.
    if preview == '<no tracks>' and S.all_track_list then
        for _, t in ipairs(S.all_track_list) do
            if t.idx == reaper_idx then preview = t.label; break end
        end
    end
    local new_idx = reaper_idx
    if r.ImGui_BeginCombo(ctx, label, preview) then
        for _, t in ipairs(track_list) do
            local is_sel = (t.idx == reaper_idx)
            if r.ImGui_Selectable(ctx, t.label, is_sel) then new_idx = t.idx end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    return new_idx
end

-- Soft sanity check for instrument presets: warn when the selected tracks
-- still look vocal-related. Advisory only - never blocks, settings apply
-- regardless. Returns a result-panel string, or nil when nothing looks off.
local function KeysPresetTrackWarnings()
    local lines = {}
    local mtr = r.GetTrack(0, S.midi_idx)
    if mtr then
        local _, name = r.GetTrackName(mtr)
        local u = name:upper()
        if u:find('VOCAL', 1, true) or u:find('HARM', 1, true) then
            lines[#lines + 1] =
                ('Selected preset is piano, but the MIDI destination "%s" looks vocal-related.'):format(name)
        end
    end
    local atr = r.GetTrack(0, S.audio_idx)
    if atr then
        local _, name = r.GetTrackName(atr)
        if name:upper():find('VOCAL', 1, true) then
            lines[#lines + 1] =
                ('Selected preset is piano, but the audio source "%s" contains "vocal".'):format(name)
        end
    end
    if #lines == 0 then return nil end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Did you mean to switch the track selectors? Settings were applied anyway.'
    return table.concat(lines, '\n')
end

-- One-shot preset applier for the YIN sliders + pitch range constraints.
-- Not a stateful selector: sliders remain the source of truth, so the combo
-- always previews 'Apply preset...' and selecting an entry just writes values.
-- col (optional): if given, draws 'Vocal style preset' as its own label at
-- the left, SameLine(col), then a blank-labelled combo - matching the
-- label-column convention used for every other row in the calling tab.
function YINPresetCombo(id_suffix, col)
    if col then
        r.ImGui_Text(ctx, 'Vocal style preset')
        r.ImGui_SameLine(ctx, col)
    end
    local label = col and ('##yinpreset' .. id_suffix) or ('Vocal style preset' .. id_suffix)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, label, 'Apply preset...') then
        for _, preset in ipairs(YIN_PRESETS) do
            if r.ImGui_Selectable(ctx, preset.label, false) then
                ApplyYINPreset(preset)
                S.status = 'Applied preset: ' .. preset.label
                -- Clears any stale result; shows track warnings for instrument presets.
                S.last_result = preset.keys and KeysPresetTrackWarnings() or nil
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.yin_preset)
end

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
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band Vocal Helper', true)
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

        local bw_und = BtnWidth('Undo')

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

                r.ImGui_Spacing(ctx)
                SectionHeader('YIN Detection', 'Reset##yin_tur', ResetYIN, TIPS.reset_yin)
                local lbl_col_tur = LabelColWidth({
                    'Vocal style preset', 'YIN threshold', 'Min frequency (Hz)',
                    'Max frequency (Hz)', 'Window (ms)', 'Min RMS level',
                    'Min pitch', 'Max pitch',
                })
                YINPresetCombo('##tur', lbl_col_tur)
                local _
                r.ImGui_Text(ctx, 'YIN threshold')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.yin_threshold = r.ImGui_SliderDouble(ctx, '##yinthr_tur',
                    S.yin_threshold, 0.01, 0.5, '%.3f')
                SliderTooltip(TIPS.yin_threshold)
                r.ImGui_Text(ctx, 'Min frequency (Hz)')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.yin_min_freq = r.ImGui_SliderInt(ctx, '##yinminf_tur',
                    S.yin_min_freq, 40, 400)
                SliderTooltip(TIPS.yin_min_freq)
                r.ImGui_Text(ctx, 'Max frequency (Hz)')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.yin_max_freq = r.ImGui_SliderInt(ctx, '##yinmaxf_tur',
                    S.yin_max_freq, 200, 2000)
                SliderTooltip(TIPS.yin_max_freq)
                if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
                r.ImGui_Text(ctx, 'Window (ms)')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.yin_window_ms = r.ImGui_SliderInt(ctx, '##yinwin_tur',
                    S.yin_window_ms, 10, 100)
                SliderTooltip(TIPS.yin_window_ms)
                r.ImGui_Text(ctx, 'Min RMS level')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.tuner_rms_threshold = r.ImGui_SliderDouble(ctx, '##turrms',
                    S.tuner_rms_threshold, 0.001, 0.1, '%.4f')
                SliderTooltip(TIPS.tuner_rms_threshold)

                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                SectionHeader('Pitch Range')

                r.ImGui_Text(ctx, 'Min pitch')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                if not S.min_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
                local minfmt_tur = ('%%d  (%s)'):format(PitchName(S.min_pitch))
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.min_pitch = r.ImGui_SliderInt(ctx, '##minpitch_tur', S.min_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, minfmt_tur)
                SliderTooltip(TIPS.min_pitch)
                if not S.min_pitch_enabled then r.ImGui_EndDisabled(ctx) end
                r.ImGui_SameLine(ctx)
                local cb_changed_tur
                cb_changed_tur, S.min_pitch_enabled = r.ImGui_Checkbox(ctx, '##minpe_tur', S.min_pitch_enabled)
                Tooltip(TIPS.min_pitch_enabled)

                r.ImGui_Text(ctx, 'Max pitch')
                r.ImGui_SameLine(ctx, lbl_col_tur)
                if not S.max_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
                local maxfmt_tur = ('%%d  (%s)'):format(PitchName(S.max_pitch))
                r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
                _, S.max_pitch = r.ImGui_SliderInt(ctx, '##maxpitch_tur', S.max_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, maxfmt_tur)
                SliderTooltip(TIPS.max_pitch)
                if not S.max_pitch_enabled then r.ImGui_EndDisabled(ctx) end
                r.ImGui_SameLine(ctx)
                cb_changed_tur, S.max_pitch_enabled = r.ImGui_Checkbox(ctx, '##maxpe_tur', S.max_pitch_enabled)
                Tooltip(TIPS.max_pitch_enabled)

                if S.min_pitch_enabled and S.max_pitch_enabled and S.min_pitch > S.max_pitch then
                    S.max_pitch = S.min_pitch
                end

                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                SectionHeader('Pitch Tuner')

                if S.tuner_active then
                    if Btn('Stop Tuner', BTN_H) then RunAction(StopTuner) end
                else
                    if Btn('Start Tuner', BTN_H) then RunAction(StartTuner) end
                end
                Tooltip(TIPS.tuner_toggle)

                r.ImGui_Spacing(ctx)
                local state_color = S.tuner_active and 0x88FF88FF or 0x888888FF
                local state_label = S.tuner_active and 'Tuner: Active' or 'Tuner: Stopped'
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), state_color)
                r.ImGui_Text(ctx, state_label)
                r.ImGui_PopStyleColor(ctx)

                r.ImGui_Separator(ctx)

                -- Current pitch display (highlighted)
                local arrow       = ''
                local arrow_color = 0x888888FF
                if S.tuner_pitch and S.tuner_prev_pitch then
                    if     S.tuner_pitch > S.tuner_prev_pitch then arrow = '\xe2\x96\xb2'; arrow_color = 0x55FF55FF
                    elseif S.tuner_pitch < S.tuner_prev_pitch then arrow = '\xe2\x96\xbc'; arrow_color = 0xFF5555FF
                    else                                           arrow = '=';             arrow_color = 0x888888FF
                    end
                end
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                r.ImGui_Text(ctx, S.tuner_pitch_name or '\xe2\x80\x94')
                r.ImGui_PopStyleColor(ctx)
                if arrow ~= '' then
                    r.ImGui_SameLine(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), arrow_color)
                    r.ImGui_Text(ctx, arrow)
                    r.ImGui_PopStyleColor(ctx)
                end
                if S.tuner_pitch_hz then
                    r.ImGui_SameLine(ctx)
                    r.ImGui_Text(ctx, ('%.1f Hz'):format(S.tuner_pitch_hz))
                    r.ImGui_SameLine(ctx)
                    r.ImGui_Text(ctx, 'at ' .. r.format_timestr_pos(S.tuner_pitch_ts, '', 0))
                end

                -- History strip (dimmed, newest on left)
                if #S.tuner_history > 0 then
                    r.ImGui_Spacing(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xAAAAAAFF)
                    r.ImGui_Text(ctx, table.concat(S.tuner_history, '  '))
                    r.ImGui_PopStyleColor(ctx)
                end

                local quiet_delay = (r.GetPlayState() & 1 ~= 0) and 1.5 or 0.0
                if S.tuner_quiet_since and r.time_precise() - S.tuner_quiet_since > quiet_delay then
                    S.status = 'Quiet \xe2\x80\x94 no pitch detected'
                elseif S.status == 'Quiet \xe2\x80\x94 no pitch detected' then
                    S.status = ''
                end

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
                local bw_lyrics_actions = BtnGroupWidth({ 'Clear lyrics', 'Assign lyrics' })
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
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, S.status)
        r.ImGui_SameLine(ctx)
        local undo_str = r.Undo_CanUndo2(0) or ''
        local can_undo = undo_str ~= ''
        local avail_x = r.ImGui_GetContentRegionAvail(ctx)
        if avail_x > bw_und + 4 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - bw_und))
        end
        if not can_undo then r.ImGui_BeginDisabled(ctx) end
        if Btn('Undo', BTN_H) then r.Undo_DoUndo2(0) end
        if not can_undo then r.ImGui_EndDisabled(ctx) end
        if can_undo then Tooltip('Undo: ' .. undo_str) end
        if S.last_result then
            r.ImGui_Separator(ctx)
            r.ImGui_PushTextWrapPos(ctx, 0)
            for line in (S.last_result .. '\n'):gmatch('([^\n]*)\n') do
                if line ~= '' then
                    r.ImGui_Text(ctx, line)
                else
                    r.ImGui_Spacing(ctx)
                end
            end
            r.ImGui_PopTextWrapPos(ctx)
        end

        r.ImGui_End(ctx)
    end

    if open then r.defer(Loop) end
end

r.defer(Loop)
