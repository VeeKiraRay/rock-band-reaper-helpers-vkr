-- Settings save/load (project state)
-- Requires: S (from defaults.lua), r (global)

local PROJ_KEY_SECTION = 'RBHelperVKR'
local PROJ_KEY_NAME    = 'settings_v1'

local function SerializeSettings()
    return table.concat({
        'v=1',
        'tmrth='   .. S.tm_rms_threshold,
        'tmrwm='   .. S.tm_rms_window_ms,
        'tmfbthr=' .. S.tm_fb_rms_threshold,
        'tmfbrwm=' .. S.tm_fb_rms_window_ms,
        'tmswm='   .. S.tm_search_window_ms,
        'tmdtm=' .. S.tm_drift_threshold_ms,
        'tmbpf=' .. S.tm_bpm_failsafe,
        'tmfm='  .. S.tm_first_measure,
        'tmtsn=' .. S.tm_timesig_num,
        'tmtsd=' .. S.tm_timesig_denom,
        'tmofs='   .. (S.tm_override_failsafe and '1' or '0'),
        'tmatd='   .. S.tm_autotune_density,
        'tmfbflx=' .. (S.tm_fb_use_flux and '1' or '0'),
        -- MIDI converter
        'mcgt='  .. S.mc_ghost_thresh,
        'mcc2g=' .. (S.mc_crash_to_green and '1' or '0'),
        'mcpd='  .. (S.mc_pro_drums and '1' or '0'),
        'mcdpv=' .. (S.mc_drum_preview and '1' or '0'),
        'mcksc=' .. (S.mc_keys_split_by_ch and '1' or '0'),
        'mcksp=' .. S.mc_keys_split_pitch,
        'mckpv=' .. (S.mc_keys_preview and '1' or '0'),
        'mcpkis=' .. (S.mc_pk_insert_shifts and '1' or '0'),
        'mc5kpg=' .. S.mc_5k_phrase_gap_ms,
        'mc5kmc=' .. S.mc_5k_max_chord,
        -- MIDI converter: guitar
        'mcgwg=' .. S.mc_gtr_wrap_gap_ms,
        'mcgmc=' .. S.mc_gtr_max_chord,
        'mcga14=' .. (S.mc_gtr_allow_14 and '1' or '0'),
        'mcgwf='  .. S.mc_gtr_workflow,
        -- Tab Input guide
        'mcgtf='  .. S.mc_gtr_tab_format,
        'mcgtor=' .. (S.mc_gtr_tab_ordered and '1' or '0'),
        'tabim='  .. S.tab_input_mode,
        -- MIDI alignment
        'mama='  .. S.ma_mode,
        -- Venue theme
        'vthn='  .. S.venue_theme_name,
        'vkfa='  .. S.venue_keyframe_align,
        'vkfis=' .. S.venue_kf_inst_subdiv,
        'vcpac='  .. S.venue_cam_pacing,
        'vcpacc=' .. S.venue_cam_pacing_custom,
        'vcpacj=' .. (S.venue_cam_pacing_jitter and '1' or '0'),
        'vsecm='  .. S.venue_sec_mode,
        'vsectm=' .. S.venue_sec_tmpl_name,
        'vpscl='   .. S.venue_preview_scale,
        'vpan='    .. (S.venue_preview_animate and '1' or '0'),
        'vpcombo=' .. S.venue_preview_combo,
        'vpshwm=' .. S.venue_preview_show_mode,
        'swip='   .. (S.show_wip_tabs and '1' or '0'),
    }, ';')
end

local function DeserializeSettings(str)
    for k, v in str:gmatch('([^=;]+)=([^;]*)') do
        if     k == 'tmrth'   then S.tm_rms_threshold      = tonumber(v) or S.tm_rms_threshold
        elseif k == 'tmrwm'   then S.tm_rms_window_ms      = tonumber(v) or S.tm_rms_window_ms
        elseif k == 'tmfbthr' then S.tm_fb_rms_threshold   = tonumber(v) or S.tm_fb_rms_threshold
        elseif k == 'tmfbrwm' then S.tm_fb_rms_window_ms   = tonumber(v) or S.tm_fb_rms_window_ms
        elseif k == 'tmswm'   then S.tm_search_window_ms   = tonumber(v) or S.tm_search_window_ms
        elseif k == 'tmdtm' then S.tm_drift_threshold_ms = tonumber(v) or S.tm_drift_threshold_ms
        elseif k == 'tmbpf' then S.tm_bpm_failsafe       = tonumber(v) or S.tm_bpm_failsafe
        elseif k == 'tmfm'  then S.tm_first_measure      = tonumber(v) or S.tm_first_measure
        elseif k == 'tmtsn' then S.tm_timesig_num        = tonumber(v) or S.tm_timesig_num
        elseif k == 'tmtsd' then S.tm_timesig_denom      = tonumber(v) or S.tm_timesig_denom
        elseif k == 'tmofs' then S.tm_override_failsafe  = (v == '1')
        elseif k == 'tmatd'   then S.tm_autotune_density   = tonumber(v) or 0
        elseif k == 'tmfbflx' then S.tm_fb_use_flux        = (v == '1')
        -- MIDI converter
        elseif k == 'mcgt'  then S.mc_ghost_thresh     = tonumber(v) or S.mc_ghost_thresh
        elseif k == 'mcc2g' then S.mc_crash_to_green   = (v == '1')
        elseif k == 'mcpd'  then S.mc_pro_drums        = (v == '1')
        elseif k == 'mcdpv' then S.mc_drum_preview     = (v == '1')
        elseif k == 'mcksc' then S.mc_keys_split_by_ch  = (v == '1')
        elseif k == 'mcksp' then S.mc_keys_split_pitch  = tonumber(v) or S.mc_keys_split_pitch
        elseif k == 'mckpv' then S.mc_keys_preview      = (v == '1')
        elseif k == 'mcpkis' then S.mc_pk_insert_shifts = (v == '1')
        elseif k == 'mc5kpg' then S.mc_5k_phrase_gap_ms = tonumber(v) or S.mc_5k_phrase_gap_ms
        elseif k == 'mc5kmc' then S.mc_5k_max_chord     = tonumber(v) or S.mc_5k_max_chord
        -- MIDI converter: guitar
        elseif k == 'mcgwg' then S.mc_gtr_wrap_gap_ms  = tonumber(v) or S.mc_gtr_wrap_gap_ms
        elseif k == 'mcgmc' then S.mc_gtr_max_chord    = tonumber(v) or S.mc_gtr_max_chord
        elseif k == 'mcga14' then S.mc_gtr_allow_14   = (v == '1')
        elseif k == 'mcgwf'  then S.mc_gtr_workflow    = tonumber(v) or 0
        -- Tab Input guide
        elseif k == 'mcgtf'  then S.mc_gtr_tab_format  = tonumber(v) or 0
        elseif k == 'mcgtor' then S.mc_gtr_tab_ordered = (v == '1')
        elseif k == 'tabim'  then S.tab_input_mode     = tonumber(v) or 0
        -- MIDI alignment
        elseif k == 'mama'  then S.ma_mode             = tonumber(v) or 0
        -- Venue theme
        elseif k == 'vthn'  then S.venue_theme_name      = v
        elseif k == 'vkfa'  then S.venue_keyframe_align  = tonumber(v) or 0
        elseif k == 'vkfis' then S.venue_kf_inst_subdiv  = tonumber(v) or 0
        elseif k == 'vcpac'  then S.venue_cam_pacing        = tonumber(v) or 0
        elseif k == 'vcpacc' then S.venue_cam_pacing_custom = tonumber(v) or 16
        elseif k == 'vcpacj' then S.venue_cam_pacing_jitter = (v == '1')
        elseif k == 'vsecm'  then S.venue_sec_mode          = tonumber(v) or 0
        elseif k == 'vsectm' then S.venue_sec_tmpl_name     = v
        elseif k == 'vpscl'   then S.venue_preview_scale   = tonumber(v) or 1
        elseif k == 'vpan'    then S.venue_preview_animate = (v == '1')
        elseif k == 'vpcombo' then S.venue_preview_combo     = tonumber(v) or 0
        elseif k == 'vpshwm' then S.venue_preview_show_mode = tonumber(v) or 0
        elseif k == 'swip'   then S.show_wip_tabs           = (v == '1')
        end
    end
end

-- Save/LoadSectionConfigs live in actions_venue_section.lua, which the slim
-- standalone preview entry point (rock_band_preview_vkr.lua) does not load —
-- guard the calls so this file works in both entry points.
function SaveSettings()
    r.SetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME, SerializeSettings())
    if SaveSectionConfigs then SaveSectionConfigs() end
    r.MarkProjectDirty(0)
end

function LoadSettings()
    local _, str = r.GetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME)
    if str and str ~= '' then
        DeserializeSettings(str)
        if S.tm_timesig_num == 0 then
            S.tm_timesig_text = ''
        else
            S.tm_timesig_text = S.tm_timesig_num .. '/' .. S.tm_timesig_denom
        end
        if LoadSectionConfigs then LoadSectionConfigs() end
        return true
    end
    if LoadSectionConfigs then LoadSectionConfigs() end
    return false
end
