-- Settings save/load (project state)
-- Requires: S (from defaults.lua), r (global)

local PROJ_KEY_SECTION = 'RBHelperVKR'
local PROJ_KEY_NAME    = 'settings_v1'

local function SerializeSettings()
    return table.concat({
        'v=1',
        'tmrth=' .. S.tm_rms_threshold,
        'tmrwm=' .. S.tm_rms_window_ms,
        'tmswm=' .. S.tm_search_window_ms,
        'tmdtm=' .. S.tm_drift_threshold_ms,
        'tmbpf=' .. S.tm_bpm_failsafe,
        'tmfm='  .. S.tm_first_measure,
        'tmtsn=' .. S.tm_timesig_num,
        'tmofs=' .. (S.tm_override_failsafe and '1' or '0'),
    }, ';')
end

local function DeserializeSettings(str)
    for k, v in str:gmatch('([^=;]+)=([^;]*)') do
        if     k == 'tmrth' then S.tm_rms_threshold      = tonumber(v) or S.tm_rms_threshold
        elseif k == 'tmrwm' then S.tm_rms_window_ms      = tonumber(v) or S.tm_rms_window_ms
        elseif k == 'tmswm' then S.tm_search_window_ms   = tonumber(v) or S.tm_search_window_ms
        elseif k == 'tmdtm' then S.tm_drift_threshold_ms = tonumber(v) or S.tm_drift_threshold_ms
        elseif k == 'tmbpf' then S.tm_bpm_failsafe       = tonumber(v) or S.tm_bpm_failsafe
        elseif k == 'tmfm'  then S.tm_first_measure      = tonumber(v) or S.tm_first_measure
        elseif k == 'tmtsn' then S.tm_timesig_num        = tonumber(v) or S.tm_timesig_num
        elseif k == 'tmofs' then S.tm_override_failsafe  = (v == '1')
        end
    end
end

function SaveSettings()
    r.SetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME, SerializeSettings())
    r.MarkProjectDirty(0)
end

function LoadSettings()
    local _, str = r.GetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME)
    if str and str ~= '' then
        DeserializeSettings(str)
        return true
    end
    return false
end
