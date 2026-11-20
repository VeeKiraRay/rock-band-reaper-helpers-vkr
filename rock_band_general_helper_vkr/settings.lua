-- Settings save/load: shipped defaults < my defaults < this project
-- Requires: S (from defaults.lua), r, UserDefaultsSetup (lib/reaper_helper_common.lua,
-- loaded before this file)
--
-- The Instrument Helper saves its tabs' settings under its own key
-- (rock_band_instrument_helper_vkr/settings.lua). Projects saved before the
-- split still carry those tabs' fields in this blob; DeserializeSettings
-- ignores keys it does not know, and the next Save drops them.

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
        -- Venue theme
        'vthn='  .. S.venue_theme_name,
        'vkfa='  .. S.venue_keyframe_align,
        'vkfis=' .. S.venue_kf_inst_subdiv,
        'vcpac='  .. S.venue_cam_pacing,
        'vcpacc=' .. S.venue_cam_pacing_custom,
        'vcpacj=' .. (S.venue_cam_pacing_jitter and '1' or '0'),
        'vsecm='  .. S.venue_sec_mode,
        'vmgt='   .. S.venue_mg_target,
        'vmgr='   .. S.venue_mg_replace,
        'emp='    .. S.metronome_pulse,
        'emi='    .. S.metronome_intro,
        'abhs='   .. S.beat_half_style,
        'abds='   .. S.beat_double_style,
        'acsd='   .. S.char_active.drums,
        'acsg='   .. S.char_active.guitar,
        'acsb='   .. S.char_active.bass,
        'acsv='   .. S.char_active.vocals,
        'acsk='   .. S.char_active.keys,
        'acgi='   .. S.char_gap_inst_bars,
        'acgv='   .. S.char_gap_vox_bars,
        'acig='   .. (S.char_idle_gaps and '1' or '0'),
        'acmd='   .. S.char_mode,
        'adcr='   .. S.drum_anim_crash,
        'adbh='   .. (S.drum_anim_blue_hh and '1' or '0'),
        'admc='   .. S.drum_anim_min_cym,
        'adfl='   .. (S.drum_anim_flam and '1' or '0'),
        'adsv='   .. (S.drum_anim_snare_variety and '1' or '0'),
        'adsc='   .. (S.drum_anim_soft_cym and '1' or '0'),
        'adss='   .. (S.drum_anim_soft_snare and '1' or '0'),
        'adsnb='  .. S.drum_anim_soft_snare_below,
        'adchb='  .. S.drum_anim_choke_below,
        'adcyb='  .. S.drum_anim_soft_cym_below,
        'adoh='   .. (S.drum_anim_open_hat and '1' or '0'),
        'adbo='   .. (S.drum_anim_blue_open and '1' or '0'),
        'adoha='  .. S.drum_anim_open_hat_above,
        'adra='   .. (S.drum_anim_ride_alt and '1' or '0'),
        'adfll='  .. (S.drum_anim_flam_late and '1' or '0'),
        'aklm='   .. S.keys_anim_lh_mode,
        'vsectm=' .. S.venue_sec_tmpl_name,
        'vpscl='   .. S.venue_preview_scale,
        'vpan='    .. (S.venue_preview_animate and '1' or '0'),
        'vpcombo=' .. S.venue_preview_combo,
        'vpshwm=' .. S.venue_preview_show_mode,
        'vpgt='   .. (S.venue_preview_game_timing and '1' or '0'),
        'swip='   .. (S.show_wip_tabs and '1' or '0'),
        -- Workflow checklist
        'wffn=' .. S.workflow_file_name,
        'wfsts=' .. (S.workflow_show_ts and '1' or '0'),
        'wfhd=' .. (S.workflow_hide_done and '1' or '0'),
    }, ';')
end

-- A drum velocity threshold, 0-128 (128 = every hit).
local function Velocity(v, fallback)
    local n = tonumber(v)
    if not n then return fallback end
    return math.max(0, math.min(128, math.floor(n)))
end

-- project: str comes from a project (old-project rules apply), not from the shipped or
-- my-defaults string (UserDefaultsSetup passes false).
local function DeserializeSettings(str, project)
    -- Saved before the drum velocity thresholds, a soft option meant every hit soft:
    -- such a project gets threshold 128 below, so Generate writes what it did then.
    -- Projects only: a my-defaults string holds just the values that differ, so a
    -- stored soft option without its threshold means the shipped threshold.
    local soft_seen, below_seen = {}, {}
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
        -- Venue theme
        elseif k == 'vthn'  then S.venue_theme_name      = v
        elseif k == 'vkfa'  then S.venue_keyframe_align  = tonumber(v) or 0
        elseif k == 'vkfis' then S.venue_kf_inst_subdiv  = tonumber(v) or 0
        elseif k == 'vcpac'  then S.venue_cam_pacing        = tonumber(v) or 0
        elseif k == 'vcpacc' then S.venue_cam_pacing_custom = tonumber(v) or 16
        elseif k == 'vcpacj' then S.venue_cam_pacing_jitter = (v == '1')
        elseif k == 'vsecm'  then S.venue_sec_mode          = tonumber(v) or 0
        elseif k == 'vmgt'   then S.venue_mg_target         = (v == '1') and 1 or 0
        elseif k == 'vmgr'   then S.venue_mg_replace        = (v == '1') and 1 or 0
        elseif k == 'emi'    then
            local n = tonumber(v)
            if n == 0 or n == 1 or n == 2 then S.metronome_intro = n end
        elseif k == 'emp'    then
            local n = tonumber(v)
            if n == 0 or n == 1 or n == 2 then S.metronome_pulse = n end
        elseif k == 'abhs'   then S.beat_half_style         = (v == '1') and 1 or 0
        elseif k == 'abds'   then S.beat_double_style       = (v == '1') and 1 or 0
        elseif k:match('^acs[dgbvk]$') then
            local group = ({ d = 'drums', g = 'guitar', b = 'bass', v = 'vocals', k = 'keys' })[k:sub(4)]
            local n = tonumber(v)
            if n and n >= 0 and n <= 2 then S.char_active[group] = math.floor(n) end
        elseif k == 'acgi'   then S.char_gap_inst_bars      = math.max(1, math.min(8, tonumber(v) or 3))
        elseif k == 'acgv'   then S.char_gap_vox_bars       = math.max(1, math.min(8, tonumber(v) or 2))
        elseif k == 'acig'   then S.char_idle_gaps          = (v == '1')
        elseif k == 'acmd'   then S.char_mode               = (v == '1') and 1 or 0
        elseif k == 'adcr'   then S.drum_anim_crash         = (v == '1') and 1 or 0
        elseif k == 'adbh'   then S.drum_anim_blue_hh       = (v == '1')
        elseif k == 'admc'   then S.drum_anim_min_cym       = math.max(2, math.min(8, tonumber(v) or 3))
        elseif k == 'adfl'   then S.drum_anim_flam          = (v == '1')
        elseif k == 'adsv'   then S.drum_anim_snare_variety = (v == '1')
        elseif k == 'adsc'   then S.drum_anim_soft_cym      = (v == '1') soft_seen.cym = true
        elseif k == 'adss'   then S.drum_anim_soft_snare    = (v == '1') soft_seen.snare = true
        -- before v0.9.64 one option made snare AND crash hits soft; a project saved
        -- with it keeps both on (the next Save writes adsc / adss instead)
        elseif k == 'adso'   then
            S.drum_anim_soft_cym   = (v == '1')
            S.drum_anim_soft_snare = (v == '1')
            soft_seen.cym, soft_seen.snare = true, true
        elseif k == 'adsnb'  then
            S.drum_anim_soft_snare_below = Velocity(v, S.drum_anim_soft_snare_below)
            below_seen.snare = true
        elseif k == 'adchb'  then
            S.drum_anim_choke_below = Velocity(v, S.drum_anim_choke_below)
            below_seen.cym = true
        elseif k == 'adcyb'  then
            S.drum_anim_soft_cym_below = Velocity(v, S.drum_anim_soft_cym_below)
            below_seen.cym = true
        elseif k == 'adoh'   then S.drum_anim_open_hat      = (v == '1')
        elseif k == 'adbo'   then S.drum_anim_blue_open     = (v == '1')
        elseif k == 'adoha'  then
            S.drum_anim_open_hat_above = math.min(127, Velocity(v, S.drum_anim_open_hat_above))
        elseif k == 'adra'   then S.drum_anim_ride_alt      = (v == '1')
        elseif k == 'adfll'  then S.drum_anim_flam_late     = (v == '1')
        elseif k == 'aklm'   then S.keys_anim_lh_mode       = math.max(0, math.min(2, tonumber(v) or 0))
        elseif k == 'vsectm' then S.venue_sec_tmpl_name     = v
        elseif k == 'vpscl'   then S.venue_preview_scale   = tonumber(v) or 1
        elseif k == 'vpan'    then S.venue_preview_animate = (v == '1')
        elseif k == 'vpcombo' then S.venue_preview_combo     = tonumber(v) or 0
        elseif k == 'vpshwm' then S.venue_preview_show_mode = tonumber(v) or 0
        elseif k == 'vpgt'   then S.venue_preview_game_timing = (v == '1')
        elseif k == 'swip'   then S.show_wip_tabs           = (v == '1')
        -- Workflow checklist
        elseif k == 'wffn'   then S.workflow_file_name      = v
        elseif k == 'wfsts'  then S.workflow_show_ts        = (v == '1')
        elseif k == 'wfhd'   then S.workflow_hide_done      = (v == '1')
        end
    end
    if not project then return end
    if soft_seen.snare and not below_seen.snare and S.drum_anim_soft_snare then
        S.drum_anim_soft_snare_below = 128
    end
    if soft_seen.cym and not below_seen.cym and S.drum_anim_soft_cym then
        S.drum_anim_choke_below, S.drum_anim_soft_cym_below = 0, 128
    end
end

local function TimesigText()
    if S.tm_timesig_num == 0 then
        S.tm_timesig_text = ''
    else
        S.tm_timesig_text = S.tm_timesig_num .. '/' .. S.tm_timesig_denom
    end
end

-- Save/LoadSectionConfigs (actions_venue_section.lua) and Save/LoadWorkflowState
-- (actions_workflow.lua) aren't loaded by the slim standalone preview entry
-- point (rock_band_preview_vkr.lua) - guard the calls so this file works in
-- both entry points.
function SaveSettings()
    r.SetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME, SerializeSettings())
    if SaveSectionConfigs then SaveSectionConfigs() end
    if SaveWorkflowState then SaveWorkflowState() end
    r.MarkProjectDirty(0)
end

-- Shipped defaults, then my defaults, then the project's own settings when it has
-- some (lib/reaper_helper_common.lua, "Settings"). Starting from the defaults every
-- time also means a project without settings never keeps the previous project's.
-- Returns true when the project had settings.
function LoadSettings()
    ApplyDefaults()
    local _, str = r.GetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME)
    local loaded = str and str ~= '' or false
    if loaded then DeserializeSettings(str, true) end
    TimesigText()
    if LoadSectionConfigs then LoadSectionConfigs() end
    if LoadWorkflowState then LoadWorkflowState() end
    return loaded
end

-- Names for the My defaults list (General > Settings); { name, bool = true } shows
-- On / Off.
local LABELS = {
    tmrth   = 'Tempo Map: RMS threshold',
    tmrwm   = 'Tempo Map: RMS window (ms)',
    tmfbthr = 'Tempo Map: fallback RMS threshold',
    tmfbrwm = 'Tempo Map: fallback RMS window (ms)',
    tmswm   = 'Tempo Map: search window (ms)',
    tmdtm   = 'Tempo Map: drift threshold (ms)',
    tmbpf   = 'Tempo Map: BPM failsafe',
    tmfm    = 'Tempo Map: first measure',
    tmtsn   = 'Tempo Map: time signature, top',
    tmtsd   = 'Tempo Map: time signature, bottom',
    tmofs   = { 'Tempo Map: override failsafe', bool = true },
    tmatd   = 'Tempo Map: auto-tune density',
    tmfbflx = { 'Tempo Map: fallback uses spectral flux', bool = true },
    vthn    = 'Venue: theme',
    vkfa    = 'Venue > Keyframes: alignment',
    vkfis   = 'Venue > Keyframes: instrument subdivision',
    vcpac   = 'Venue: camera pacing',
    vcpacc  = 'Venue: camera pacing, custom (16ths)',
    vcpacj  = { 'Venue: camera pacing jitter', bool = true },
    vsecm   = 'Venue > Section gen: mode',
    vsectm  = 'Venue > Section gen: template',
    vmgt    = 'Venue: target (0 VENUE, 1 Subtracks)',
    vmgr    = 'Venue > Manual gen: insert (0 Add, 1 Replace)',
    vpscl   = 'Venue preview: size',
    vpan    = { 'Venue preview: animated', bool = true },
    vpcombo = 'Venue preview: players',
    vpshwm  = 'Venue > Preview: show',
    vpgt    = { 'Venue > Preview: mark directed-cut timing', bool = true },
    emp     = 'Events > Metronome: pulse (0 Auto, 1 8ths, 2 16ths)',
    emi     = 'Events > Metronome: intro (0 From COUNT IN, 1 Count in from chart, 2 Steady)',
    abhs    = 'Animation > Beat: half-time downbeat',
    abds    = 'Animation > Beat: double-time downbeat',
    acsd    = 'Animation > Character: drums state',
    acsg    = 'Animation > Character: guitar state',
    acsb    = 'Animation > Character: bass state',
    acsv    = 'Animation > Character: vocals state',
    acsk    = 'Animation > Character: keys state',
    acgi    = 'Animation > Character: instrument rest (bars)',
    acgv    = 'Animation > Character: vocal rest (bars)',
    acig    = { 'Animation > Character: idle in rests', bool = true },
    acmd    = 'Animation > Character: mode (0 Generate, 1 Manual)',
    adcr    = 'Animation > Drums: default crash (0 crash 2, 1 crash 1)',
    adbh    = { 'Animation > Drums: blue cymbal as the hi-hat', bool = true },
    admc    = 'Animation > Drums: min cymbal hits',
    adfl    = { 'Animation > Drums: snare + yellow tom as a flam', bool = true },
    adsv    = { 'Animation > Drums: slow snare variety', bool = true },
    adsc    = { 'Animation > Drums: crash hits by velocity', bool = true },
    adss    = { 'Animation > Drums: soft snare hits by velocity', bool = true },
    adsnb   = 'Animation > Drums: soft snare below velocity',
    adchb   = 'Animation > Drums: choke below velocity',
    adcyb   = 'Animation > Drums: soft crash below velocity',
    adoh    = { 'Animation > Drums: open hi-hat by velocity', bool = true },
    adbo    = { 'Animation > Drums: open the hat on blue hi-hat hits', bool = true },
    adoha   = 'Animation > Drums: open hi-hat above velocity',
    adra    = { 'Animation > Drums: crash riding soft / hard', bool = true },
    adfll   = { 'Animation > Drums: flam left hand late', bool = true },
    aklm    = 'Animation > Keys: left-hand notes (0 whole track, 1 channel 2, 2 not on Expert)',
    swip    = { 'General > Settings: show WIPs', bool = true },
    wffn    = 'Workflow: checklist',
    wfsts   = { 'Workflow: show timestamps', bool = true },
    wfhd    = { 'Workflow: hide done', bool = true },
}

-- Values that belong to one song: saved with a project, never one of my defaults.
local PROJECT_ONLY = {
    tmfm = true, tmtsn = true, tmtsd = true,   -- Tempo Map: first measure, time signature
    tmofs = true,                              -- Tempo Map: failsafe bypassed for one song
    acsd = true, acsg = true, acsb = true, acsv = true, acsk = true,   -- character states (mood)
    vthn = true,                               -- venue theme
}

-- Last, while S still holds the shipped defaults: defaults.lua loads first.
UserDefaultsSetup({ section = PROJ_KEY_SECTION, project_key = PROJ_KEY_NAME,
                    serialize = SerializeSettings, deserialize = DeserializeSettings,
                    labels = LABELS,
                    project_only = function(k, v)
                        -- A picked metronome pulse (8ths / 16ths) fits one song; Auto is a preference.
                        if k == 'emp' then return v ~= '0' end
                        return PROJECT_ONLY[k] == true
                    end })
