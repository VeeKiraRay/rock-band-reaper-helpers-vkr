-- Settings save/load (project state persistence)

local PROJ_KEY_SECTION = 'VocalMIDIGenVKR'
local PROJ_KEY_NAME    = 'settings_v1'

local function bool_to_num(b) return b and 1 or 0 end
local function num_to_bool(n) return (tonumber(n) or 0) ~= 0 end

local function SerializeSettings()
    return ('rms=%.6f;lpf=%.2f;split=%.2f;offset=%.2f;minnote=%.2f;window=%.2f;' ..
            'pmode=%d;pitch=%d;reftol=%.0f;' ..
            'minpe=%d;minp=%d;maxpe=%d;maxp=%d;vel=%d;' ..
            'yt=%.3f;ymn=%.0f;ymx=%.0f;yw=%.0f;' ..
            'sl_mn=%d;sl_ms=%d;sl_sk=%d;sl_st=%d;sl_wn=%d')
        :format(S.rms_threshold, S.lpf_cutoff_hz, S.split_ratio,
                S.min_offset_ms, S.min_note_ms, S.window_ms,
                S.pitch_mode, math.floor(S.pitch + 0.5), S.ref_search_ms,
                bool_to_num(S.min_pitch_enabled),
                math.floor(S.min_pitch + 0.5),
                bool_to_num(S.max_pitch_enabled),
                math.floor(S.max_pitch + 0.5),
                math.floor(S.velocity + 0.5),
                S.yin_threshold, S.yin_min_freq, S.yin_max_freq, S.yin_window_ms,
                S.slide_min_note_ms, S.slide_min_seg_ms, S.slide_skip_ms,
                S.slide_step_ms, S.slide_win_ms)
end

local function DeserializeSettings(str)
    local tmp = {}
    for k, v in str:gmatch('([%w]+)=([^;]+)') do
        tmp[k] = tonumber(v)
    end
    if tmp.rms     then S.rms_threshold     = tmp.rms     end
    if tmp.lpf     then S.lpf_cutoff_hz     = tmp.lpf     end
    if tmp.split   then S.split_ratio       = tmp.split   end
    if tmp.offset  then S.min_offset_ms     = tmp.offset  end
    if tmp.minnote then S.min_note_ms       = tmp.minnote end
    if tmp.window  then S.window_ms         = tmp.window  end
    if tmp.pmode   then S.pitch_mode        = tmp.pmode   end
    if S.pitch_mode == MODE_SINGLE then S.pitch_mode = DEFAULTS.pitch_mode end
    if tmp.pitch   then S.pitch             = math.floor(tmp.pitch + 0.5) end
    if tmp.reftol  then S.ref_search_ms     = tmp.reftol  end
    if tmp.minpe   then S.min_pitch_enabled = num_to_bool(tmp.minpe) end
    if tmp.minp    then S.min_pitch         = math.floor(tmp.minp + 0.5) end
    if tmp.maxpe   then S.max_pitch_enabled = num_to_bool(tmp.maxpe) end
    if tmp.maxp    then S.max_pitch         = math.floor(tmp.maxp + 0.5) end
    if tmp.vel     then S.velocity          = math.floor(tmp.vel + 0.5)  end
    if tmp.yt      then S.yin_threshold     = tmp.yt                     end
    if tmp.ymn     then S.yin_min_freq      = math.floor(tmp.ymn + 0.5) end
    if tmp.ymx     then S.yin_max_freq      = math.floor(tmp.ymx + 0.5) end
    if tmp.yw      then S.yin_window_ms     = tmp.yw                     end
    if tmp.sl_mn   then S.slide_min_note_ms = math.floor(tmp.sl_mn + 0.5) end
    if tmp.sl_ms   then S.slide_min_seg_ms  = math.floor(tmp.sl_ms + 0.5) end
    if tmp.sl_sk   then S.slide_skip_ms     = math.floor(tmp.sl_sk + 0.5) end
    if tmp.sl_st   then S.slide_step_ms     = math.floor(tmp.sl_st + 0.5) end
    if tmp.sl_wn   then S.slide_win_ms      = math.floor(tmp.sl_wn + 0.5) end
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
