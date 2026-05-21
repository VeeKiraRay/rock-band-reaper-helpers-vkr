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
            'sl_mn=%d;sl_ms=%d;sl_sk=%d;sl_st=%d;sl_wn=%d;' ..
            'hd1e=%d;hd2e=%d;hd3e=%d;hd1m=%d;hd2m=%d;hd3m=%d;hcp=%d;hkr=%d;hkq=%d;' ..
            'hd1lu=%d;hd2lu=%d;hd3lu=%d;hd1lh=%d;hd2lh=%d;hd3lh=%d;' ..
            'skr=%d;skq=%d;sac=%d;pst=%d;psk=%d;' ..
            'trms=%.4f')
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
                S.slide_step_ms, S.slide_win_ms,
                bool_to_num(S.harm_dst1_enabled),
                bool_to_num(S.harm_dst2_enabled),
                bool_to_num(S.harm_dst3_enabled),
                math.floor(S.harm_dst1_mode),
                math.floor(S.harm_dst2_mode),
                math.floor(S.harm_dst3_mode),
                bool_to_num(S.harm_copy_phrases),
                math.floor(S.harm_key_root),
                math.floor(S.harm_key_quality),
                bool_to_num(S.harm_dst1_lyric_unpitched),
                bool_to_num(S.harm_dst2_lyric_unpitched),
                bool_to_num(S.harm_dst3_lyric_unpitched),
                bool_to_num(S.harm_dst1_lyric_hidden),
                bool_to_num(S.harm_dst2_lyric_hidden),
                bool_to_num(S.harm_dst3_lyric_hidden),
                math.floor(S.snap_key_root),
                math.floor(S.snap_key_quality),
                bool_to_num(S.snap_avoid_collision),
                math.floor(S.phrase_sim_threshold),
                bool_to_num(S.phrase_same_key),
                S.tuner_rms_threshold)
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
    if tmp.sl_mn   then S.slide_min_note_ms  = math.floor(tmp.sl_mn + 0.5) end
    if tmp.sl_ms   then S.slide_min_seg_ms   = math.floor(tmp.sl_ms + 0.5) end
    if tmp.sl_sk   then S.slide_skip_ms      = math.floor(tmp.sl_sk + 0.5) end
    if tmp.sl_st   then S.slide_step_ms      = math.floor(tmp.sl_st + 0.5) end
    if tmp.sl_wn   then S.slide_win_ms       = math.floor(tmp.sl_wn + 0.5) end
    if tmp.hd1e    then S.harm_dst1_enabled  = num_to_bool(tmp.hd1e)        end
    if tmp.hd2e    then S.harm_dst2_enabled  = num_to_bool(tmp.hd2e)        end
    if tmp.hd3e    then S.harm_dst3_enabled  = num_to_bool(tmp.hd3e)        end
    if tmp.hd1m    then S.harm_dst1_mode     = math.floor(tmp.hd1m + 0.5)  end
    if tmp.hd2m    then S.harm_dst2_mode     = math.floor(tmp.hd2m + 0.5)  end
    if tmp.hd3m    then S.harm_dst3_mode     = math.floor(tmp.hd3m + 0.5)  end
    if tmp.hcp     then S.harm_copy_phrases  = num_to_bool(tmp.hcp)         end
    if tmp.hkr     then S.harm_key_root      = math.floor(tmp.hkr  + 0.5)  end
    if tmp.hkq     then S.harm_key_quality   = math.floor(tmp.hkq  + 0.5)  end
    if tmp.hd1lu   then S.harm_dst1_lyric_unpitched = num_to_bool(tmp.hd1lu) end
    if tmp.hd2lu   then S.harm_dst2_lyric_unpitched = num_to_bool(tmp.hd2lu) end
    if tmp.hd3lu   then S.harm_dst3_lyric_unpitched = num_to_bool(tmp.hd3lu) end
    if tmp.hd1lh   then S.harm_dst1_lyric_hidden    = num_to_bool(tmp.hd1lh) end
    if tmp.hd2lh   then S.harm_dst2_lyric_hidden    = num_to_bool(tmp.hd2lh) end
    if tmp.hd3lh   then S.harm_dst3_lyric_hidden    = num_to_bool(tmp.hd3lh) end
    if tmp.skr     then S.snap_key_root            = math.floor(tmp.skr + 0.5) end
    if tmp.skq     then S.snap_key_quality         = math.floor(tmp.skq + 0.5) end
    if tmp.sac     then S.snap_avoid_collision     = num_to_bool(tmp.sac)       end
    if tmp.pst     then S.phrase_sim_threshold     = math.floor(tmp.pst + 0.5) end
    if tmp.psk     then S.phrase_same_key          = num_to_bool(tmp.psk)       end
    if tmp.trms    then S.tuner_rms_threshold      = tmp.trms                   end
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
