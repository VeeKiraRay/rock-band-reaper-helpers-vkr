-- Main UI render loop

local _browse_tooltip_suppressed = false
local _active_proj = r.EnumProjects(-1, '')

-- TrackCombo variant that stores and matches by REAPER track index (.idx field)
-- rather than list position, so selections survive filter list rebuilds.
local function FilteredTrackCombo(label, reaper_idx, track_list)
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
        S.harm_confirm_full = false
        S.all_track_list    = nil
        S.midi_track_list   = nil
        S.audio_track_list  = nil
        S.last_result = nil
        RefreshTrackLists()
        local loaded = LoadSettings()
        S.status = loaded and 'Project switched: loaded saved settings.'
                           or 'Project switched.'
        SetDefaultTracks()
        AutoDetectLyricsFile()
    end

    -- Build cached filtered lists on first frame if not yet populated.
    if not S.all_track_list then RefreshTrackLists() end
    local tracks       = S.all_track_list
    local midi_tracks  = S.midi_track_list
    local audio_tracks = S.audio_track_list
    local sel_s, sel_e = GetTimeSelection()
    if sel_s then S.harm_confirm_full = false end

    r.ImGui_SetNextWindowSize(ctx, 580, 1060, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Rock Band Vocal Helper', true)
    if visible then
        ----------------------------------------------------------------
        -- Global: track selectors (MIDI first, then audio source)
        ----------------------------------------------------------------
        r.ImGui_Text(ctx, 'MIDI destination track  (must already contain a MIDI item)')
        S.midi_idx = FilteredTrackCombo('##midi', S.midi_idx, midi_tracks)

        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, 'Audio source track')
        S.audio_idx = FilteredTrackCombo('##audio', S.audio_idx, audio_tracks)

        if sel_s then
            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, ('Time selection: %s — %s'):format(FormatTime(sel_s), FormatTime(sel_e)))
        end

        r.ImGui_Separator(ctx)

        ----------------------------------------------------------------
        -- Button widths — computed once, used across all tabs
        ----------------------------------------------------------------
        local _bp    = 40
        local bw_at  = r.ImGui_CalcTextSize(ctx, 'Auto-tune from reference') + _bp
        local bw_ayt = r.ImGui_CalcTextSize(ctx, 'Auto-tune YIN from reference') + _bp
        local bw_dry = r.ImGui_CalcTextSize(ctx, 'Dry run') + _bp
        local bw_gen = r.ImGui_CalcTextSize(ctx, 'Generate (append)') + _bp
        local bw_grp = r.ImGui_CalcTextSize(ctx, 'Generate (replace)') + _bp
        local bw_app = r.ImGui_CalcTextSize(ctx, 'Apply pitch changes') + _bp
        local bw_und = r.ImGui_CalcTextSize(ctx, 'Undo') + _bp
        local bw_sld = r.ImGui_CalcTextSize(ctx, 'Scan pitch slides') + _bp
        local bw_lad = r.ImGui_CalcTextSize(ctx, 'Auto-detect') + _bp
        local bw_lbr = r.ImGui_CalcTextSize(ctx, 'Browse...') + _bp
        local bw_lcl = r.ImGui_CalcTextSize(ctx, 'Clear lyrics') + _bp
        local bw_las  = r.ImGui_CalcTextSize(ctx, 'Assign lyrics')      + _bp
        local bw_ref  = r.ImGui_CalcTextSize(ctx, 'Refresh tracks')     + _bp
        local bw_harm = r.ImGui_CalcTextSize(ctx, 'Apply Harmonies')    + _bp

        ----------------------------------------------------------------
        -- Tab bar
        ----------------------------------------------------------------
        if r.ImGui_BeginTabBar(ctx, 'MainTabs') then

            ------------------------------------------------------------
            -- Tab: General
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'General') then
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Settings')
                if r.ImGui_Button(ctx, 'Save', 90, 24) then
                    SaveSettings()
                    S.status = 'Settings saved to project.'
                end
                Tooltip(TIPS.save_settings)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Load', 90, 24) then
                    if LoadSettings() then
                        S.status = 'Settings loaded from project.'
                    else
                        S.status = 'No saved settings found in this project.'
                    end
                end
                Tooltip(TIPS.load_settings)

                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Track lists')
                if r.ImGui_Button(ctx, 'Refresh tracks', bw_ref, 24) then
                    RefreshTrackLists()
                    S.status = 'Track lists refreshed.'
                end
                Tooltip(TIPS.track_refresh)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Note Placement
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Note Placement') then
                r.ImGui_Spacing(ctx)
                SectionHeader('Note Placement', 'Reset##det', ResetDetection, TIPS.reset_detection)

                if r.ImGui_Button(ctx, 'Auto-tune from reference', bw_at, 24) then
                    RunAutoTune()
                end
                Tooltip(TIPS.autotune)
                r.ImGui_Spacing(ctx)

                local _
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
                SectionHeader('MIDI output', 'Reset##midi', ResetMIDIOutput, TIPS.reset_midi)
                _, S.velocity = r.ImGui_SliderInt(ctx, 'Velocity', S.velocity, 1, 127)
                SliderTooltip(TIPS.velocity)

                local pfmt = ('%%d  (%s)'):format(PitchName(S.pitch))
                _, S.pitch = r.ImGui_SliderInt(ctx, 'Default pitch', S.pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, pfmt)
                SliderTooltip(TIPS.pitch)

                r.ImGui_Separator(ctx)
                if r.ImGui_Button(ctx, 'Dry run', bw_dry, 24) then
                    Preview()
                end
                Tooltip(TIPS.preview)

                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Generate (append)', bw_gen, 24) then
                    Generate()
                end
                Tooltip(TIPS.generate)

                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Generate (replace)', bw_grp, 24) then
                    Generate(true)
                end
                Tooltip(TIPS.generate_replace)

                local undo_str = r.Undo_CanUndo2(0) or ''
                local can_undo = undo_str ~= ''
                r.ImGui_SameLine(ctx)
                if not can_undo then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Undo', bw_und, 24) then
                    r.Undo_DoUndo2(0)
                end
                if not can_undo then r.ImGui_EndDisabled(ctx) end
                if can_undo then Tooltip('Undo: ' .. undo_str) end

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Pitch
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Pitch') then
                r.ImGui_Spacing(ctx)
                SectionHeader('Pitch', 'Reset##pitch', ResetPitch, TIPS.reset_pitch)

                r.ImGui_Text(ctx, 'Pitch source:')
                if r.ImGui_RadioButton(ctx, 'Built-in detection', S.pitch_mode == MODE_YIN) then
                    S.pitch_mode = MODE_YIN
                end
                Tooltip(TIPS.pitch_mode_yin)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Reference MIDI', S.pitch_mode == MODE_REFERENCE) then
                    S.pitch_mode = MODE_REFERENCE
                end
                Tooltip(TIPS.pitch_mode_reference)

                local yin_disabled = (S.pitch_mode ~= MODE_YIN)
                if yin_disabled then r.ImGui_BeginDisabled(ctx) end

                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Built-in detection settings')
                if r.ImGui_Button(ctx, 'Auto-tune YIN from reference', bw_ayt, 24) then
                    RunAutoTuneYIN()
                end
                Tooltip(TIPS.autotune_yin)
                r.ImGui_Spacing(ctx)

                local _
                _, S.yin_threshold = r.ImGui_SliderDouble(ctx, 'YIN threshold',
                    S.yin_threshold, 0.01, 0.5, '%.3f')
                SliderTooltip(TIPS.yin_threshold)
                _, S.yin_min_freq = r.ImGui_SliderInt(ctx, 'Min frequency (Hz)',
                    S.yin_min_freq, 40, 400)
                SliderTooltip(TIPS.yin_min_freq)
                _, S.yin_max_freq = r.ImGui_SliderInt(ctx, 'Max frequency (Hz)',
                    S.yin_max_freq, 200, 2000)
                SliderTooltip(TIPS.yin_max_freq)
                if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
                _, S.yin_window_ms = r.ImGui_SliderDouble(ctx, 'YIN window (ms)',
                    S.yin_window_ms, 10, 100, '%.0f')
                SliderTooltip(TIPS.yin_window_ms)

                if yin_disabled then r.ImGui_EndDisabled(ctx) end

                local ref_disabled = (S.pitch_mode ~= MODE_REFERENCE)
                if ref_disabled then r.ImGui_BeginDisabled(ctx) end

                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Reference MIDI track')
                S.ref_idx = FilteredTrackCombo('##refmidi', S.ref_idx, midi_tracks)
                Tooltip(TIPS.ref_track)

                _, S.ref_search_ms = r.ImGui_SliderDouble(ctx, 'Search tolerance (ms)',
                    S.ref_search_ms, 50, 2000, '%.0f')
                SliderTooltip(TIPS.ref_search)

                if ref_disabled then r.ImGui_EndDisabled(ctx) end

                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Pitch range constraints')

                local cb_changed
                cb_changed, S.min_pitch_enabled = r.ImGui_Checkbox(ctx, '##minpe', S.min_pitch_enabled)
                Tooltip(TIPS.min_pitch_enabled)
                r.ImGui_SameLine(ctx)
                if not S.min_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
                local minfmt = ('%%d  (%s)'):format(PitchName(S.min_pitch))
                _, S.min_pitch = r.ImGui_SliderInt(ctx, 'Min pitch', S.min_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, minfmt)
                SliderTooltip(TIPS.min_pitch)
                if not S.min_pitch_enabled then r.ImGui_EndDisabled(ctx) end

                cb_changed, S.max_pitch_enabled = r.ImGui_Checkbox(ctx, '##maxpe', S.max_pitch_enabled)
                Tooltip(TIPS.max_pitch_enabled)
                r.ImGui_SameLine(ctx)
                if not S.max_pitch_enabled then r.ImGui_BeginDisabled(ctx) end
                local maxfmt = ('%%d  (%s)'):format(PitchName(S.max_pitch))
                _, S.max_pitch = r.ImGui_SliderInt(ctx, 'Max pitch', S.max_pitch, RB3_MIN_PITCH, RB3_MAX_PITCH, maxfmt)
                SliderTooltip(TIPS.max_pitch)
                if not S.max_pitch_enabled then r.ImGui_EndDisabled(ctx) end

                if S.min_pitch_enabled and S.max_pitch_enabled and S.min_pitch > S.max_pitch then
                    S.max_pitch = S.min_pitch
                end

                r.ImGui_Separator(ctx)
                if r.ImGui_Button(ctx, 'Apply pitch changes', bw_app, 24) then
                    ApplyPitchChangesAction()
                end
                Tooltip(TIPS.apply_pitch)

                local undo_str = r.Undo_CanUndo2(0) or ''
                local can_undo = undo_str ~= ''
                r.ImGui_SameLine(ctx)
                if not can_undo then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Undo', bw_und, 24) then
                    r.Undo_DoUndo2(0)
                end
                if not can_undo then r.ImGui_EndDisabled(ctx) end
                if can_undo then Tooltip('Undo: ' .. undo_str) end

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Lyrics
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Lyrics') then
                r.ImGui_Spacing(ctx)

                local lyric_basename = S.lyrics_path ~= ''
                    and (S.lyrics_path:match('[/\\]([^/\\]+)$') or S.lyrics_path)
                    or '(no file selected)'
                r.ImGui_TextDisabled(ctx, 'File: ' .. lyric_basename)
                if S.lyrics_path ~= '' then Tooltip(S.lyrics_path) end

                if r.ImGui_Button(ctx, 'Auto-detect', bw_lad, 24) then
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
                        S.status = 'Project has no saved path — save the project first.'
                        S.last_result = nil
                    end
                end
                Tooltip(TIPS.lyrics_auto_detect)

                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Browse...', bw_lbr, 24) then
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
                            S.status = 'Invalid file — please select a .txt file.'
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

                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, 'Clear lyrics', bw_lcl, 24) then
                    ClearLyricsAction()
                end
                Tooltip(TIPS.lyrics_clear)

                local assign_disabled = (S.lyrics_path == '')
                r.ImGui_SameLine(ctx)
                if assign_disabled then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Assign lyrics', bw_las, 24) then
                    AssignLyricsAction()
                end
                if assign_disabled then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.lyrics_assign)

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Pitch slide
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Pitch slide') then
                r.ImGui_Spacing(ctx)
                SectionHeader('Slide Scan', 'Reset##slides', ResetSlides, TIPS.reset_slides)
                _, S.slide_min_note_ms = r.ImGui_SliderInt(ctx, 'Min note length (ms)##sld', S.slide_min_note_ms, 20, 500)
                S.slide_min_note_ms = math.max(20,  math.floor(S.slide_min_note_ms / 10 + 0.5) * 10)
                SliderTooltip(TIPS.slide_min_note_ms)
                _, S.slide_min_seg_ms  = r.ImGui_SliderInt(ctx, 'Min segment (ms)##sld',     S.slide_min_seg_ms,   5, 100)
                S.slide_min_seg_ms  = math.max(5,   math.floor(S.slide_min_seg_ms  /  5 + 0.5) *  5)
                SliderTooltip(TIPS.slide_min_seg_ms)
                _, S.slide_skip_ms     = r.ImGui_SliderInt(ctx, 'Edge skip (ms)##sld',       S.slide_skip_ms,      0,  50)
                S.slide_skip_ms     = math.max(0,   math.floor(S.slide_skip_ms     /  5 + 0.5) *  5)
                SliderTooltip(TIPS.slide_skip_ms)
                _, S.slide_step_ms     = r.ImGui_SliderInt(ctx, 'Sample step (ms)##sld',     S.slide_step_ms,      5,  50)
                S.slide_step_ms     = math.max(5,   math.floor(S.slide_step_ms     /  5 + 0.5) *  5)
                SliderTooltip(TIPS.slide_step_ms)
                _, S.slide_win_ms      = r.ImGui_SliderInt(ctx, 'Sample window (ms)##sld',   S.slide_win_ms,      10,  50)
                S.slide_win_ms      = math.max(10,  math.floor(S.slide_win_ms      /  5 + 0.5) *  5)
                SliderTooltip(TIPS.slide_win_ms)
                local min_slidable_ms = S.slide_skip_ms * 2 + S.slide_min_seg_ms * 2
                if min_slidable_ms > S.slide_min_note_ms then
                    r.ImGui_Spacing(ctx)
                    r.ImGui_TextColored(ctx, 0xFFAA00FF,
                        ('! Min segment \xc3\x972 + Edge skip \xc3\x972 = %dms exceeds Min note length (%dms).')
                            :format(min_slidable_ms, S.slide_min_note_ms))
                    r.ImGui_TextColored(ctx, 0xFFAA00FF,
                        '  No slides can be detected with these settings.')
                end
                r.ImGui_Separator(ctx)
                SectionHeader('YIN Detection', 'Reset##yin', ResetYIN, TIPS.reset_yin)
                _, S.yin_threshold = r.ImGui_SliderDouble(ctx, 'YIN threshold',
                    S.yin_threshold, 0.01, 0.5, '%.3f')
                SliderTooltip(TIPS.yin_threshold)
                _, S.yin_min_freq = r.ImGui_SliderInt(ctx, 'Min frequency (Hz)',
                    S.yin_min_freq, 40, 400)
                SliderTooltip(TIPS.yin_min_freq)
                _, S.yin_max_freq = r.ImGui_SliderInt(ctx, 'Max frequency (Hz)',
                    S.yin_max_freq, 200, 2000)
                SliderTooltip(TIPS.yin_max_freq)
                if S.yin_min_freq >= S.yin_max_freq then S.yin_max_freq = S.yin_min_freq + 1 end
                r.ImGui_Separator(ctx)
                if r.ImGui_Button(ctx, 'Scan pitch slides', bw_sld, 24) then
                    ScanPitchSlidesAction()
                end
                Tooltip(TIPS.scan_slides)
                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Harmonies
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Harmonies') then
                r.ImGui_Spacing(ctx)

                ---- Source ----
                r.ImGui_Text(ctx, 'Source')
                Tooltip(TIPS.harm_src)
                S.harm_src_idx = FilteredTrackCombo('##harm_src', S.harm_src_idx, midi_tracks)
                Tooltip(TIPS.harm_src)

                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)

                ---- Destination rows ----
                local dst_rows = {
                    { en='harm_dst1_enabled', idx='harm_dst1_idx', mode='harm_dst1_mode',
                      en_id='##hd1en', trk_id='##harm_dst1', mode_id='##harm_m1',
                      lu='harm_dst1_lyric_unpitched', lh='harm_dst1_lyric_hidden',
                      lu_id='##hd1lu', lh_id='##hd1lh',
                      label='Destination 1', tip='harm_dst1' },
                    { en='harm_dst2_enabled', idx='harm_dst2_idx', mode='harm_dst2_mode',
                      en_id='##hd2en', trk_id='##harm_dst2', mode_id='##harm_m2',
                      lu='harm_dst2_lyric_unpitched', lh='harm_dst2_lyric_hidden',
                      lu_id='##hd2lu', lh_id='##hd2lh',
                      label='Destination 2', tip='harm_dst2' },
                    { en='harm_dst3_enabled', idx='harm_dst3_idx', mode='harm_dst3_mode',
                      en_id='##hd3en', trk_id='##harm_dst3', mode_id='##harm_m3',
                      lu='harm_dst3_lyric_unpitched', lh='harm_dst3_lyric_hidden',
                      lu_id='##hd3lu', lh_id='##hd3lh',
                      label='Destination 3', tip='harm_dst3' },
                }

                local any_diatonic = false
                for _, d in ipairs(dst_rows) do
                    if S[d.en] and HARM_MODES[S[d.mode] + 1].diatonic then
                        any_diatonic = true
                    end
                end

                for _, d in ipairs(dst_rows) do
                    r.ImGui_Text(ctx, d.label)
                    r.ImGui_SameLine(ctx)
                    local _, new_en = r.ImGui_Checkbox(ctx, d.en_id, S[d.en])
                    S[d.en] = new_en
                    Tooltip(TIPS.harm_dst_enabled)

                    local row_off = not S[d.en]
                    if row_off then r.ImGui_BeginDisabled(ctx) end
                    S[d.idx] = FilteredTrackCombo(d.trk_id, S[d.idx], tracks)
                    Tooltip(TIPS[d.tip])
                    if r.ImGui_BeginCombo(ctx, d.mode_id, HARM_MODES[S[d.mode] + 1].label) then
                        for mi, m in ipairs(HARM_MODES) do
                            local is_sel = (mi - 1 == S[d.mode])
                            if r.ImGui_Selectable(ctx, m.label, is_sel) then S[d.mode] = mi - 1 end
                            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                        end
                        r.ImGui_EndCombo(ctx)
                    end
                    Tooltip(TIPS.harm_dst_mode)
                    local _, new_lu = r.ImGui_Checkbox(ctx, 'Unpitched lyrics (#)' .. d.lu_id, S[d.lu])
                    S[d.lu] = new_lu
                    Tooltip(TIPS.harm_lyric_unpitched)
                    r.ImGui_SameLine(ctx)
                    local _, new_lh = r.ImGui_Checkbox(ctx, 'Hidden lyrics ($)' .. d.lh_id, S[d.lh])
                    S[d.lh] = new_lh
                    Tooltip(TIPS.harm_lyric_hidden)
                    if row_off then r.ImGui_EndDisabled(ctx) end

                    r.ImGui_Spacing(ctx)
                end

                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)

                ---- Key section ----
                if not any_diatonic then r.ImGui_BeginDisabled(ctx) end
                r.ImGui_Text(ctx, 'Key')
                Tooltip(TIPS.harm_key)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 80)
                if r.ImGui_BeginCombo(ctx, '##harm_kr', HARM_NOTE_NAMES[S.harm_key_root + 1]) then
                    for i, name in ipairs(HARM_NOTE_NAMES) do
                        local is_sel = (i - 1 == S.harm_key_root)
                        if r.ImGui_Selectable(ctx, name, is_sel) then S.harm_key_root = i - 1 end
                        if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                Tooltip(TIPS.harm_key)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Major##hkq', S.harm_key_quality == 0) then
                    S.harm_key_quality = 0
                end
                Tooltip(TIPS.harm_key_quality)
                r.ImGui_SameLine(ctx)
                if r.ImGui_RadioButton(ctx, 'Minor##hkq', S.harm_key_quality == 1) then
                    S.harm_key_quality = 1
                end
                Tooltip(TIPS.harm_key_quality)
                if not any_diatonic then r.ImGui_EndDisabled(ctx) end

                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)

                ---- Copy phrases checkbox ----
                local _, new_cp = r.ImGui_Checkbox(ctx,
                    'Copy phrase markers & overdrive##harm_cp', S.harm_copy_phrases)
                S.harm_copy_phrases = new_cp
                Tooltip(TIPS.harm_copy_phrases)

                r.ImGui_Spacing(ctx)

                ---- No-time-selection warning ----
                local apply_ok = true
                if not sel_s then
                    r.ImGui_TextColored(ctx, 0xFF8800FF, 'No time selection active.')
                    r.ImGui_TextColored(ctx, 0xFF8800FF, 'The full source MIDI item will be processed.')
                    local _, new_cf = r.ImGui_Checkbox(ctx,
                        'Process full item (no time selection)##harm_cf', S.harm_confirm_full)
                    S.harm_confirm_full = new_cf
                    Tooltip(TIPS.harm_confirm_full)
                    apply_ok = S.harm_confirm_full
                end

                r.ImGui_Spacing(ctx)

                ---- Apply button ----
                if not apply_ok then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Apply Harmonies', bw_harm, 24) then
                    HarmoniesAction()
                end
                if not apply_ok then r.ImGui_EndDisabled(ctx) end
                Tooltip(TIPS.harm_apply)

                local undo_str = r.Undo_CanUndo2(0) or ''
                local can_undo = undo_str ~= ''
                r.ImGui_SameLine(ctx)
                if not can_undo then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, 'Undo', bw_und, 24) then
                    r.Undo_DoUndo2(0)
                end
                if not can_undo then r.ImGui_EndDisabled(ctx) end
                if can_undo then Tooltip('Undo: ' .. undo_str) end

                r.ImGui_EndTabItem(ctx)
            end

            ------------------------------------------------------------
            -- Tab: Validation
            ------------------------------------------------------------
            if r.ImGui_BeginTabItem(ctx, 'Validation') then
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, 'Phrase validation')
                r.ImGui_Spacing(ctx)
                local bw_vp = r.ImGui_CalcTextSize(ctx, 'Validate phrases') + _bp
                if r.ImGui_Button(ctx, 'Validate phrases', bw_vp, 24) then
                    ValidatePhrases()
                end
                Tooltip(TIPS.validate_phrases)
                r.ImGui_EndTabItem(ctx)
            end

            r.ImGui_EndTabBar(ctx)
        end

        ----------------------------------------------------------------
        -- Global: status and result panel
        ----------------------------------------------------------------
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, S.status)
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
