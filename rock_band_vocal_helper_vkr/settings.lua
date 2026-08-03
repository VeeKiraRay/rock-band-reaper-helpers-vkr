-- Settings save/load (project state persistence)

local PROJ_KEY_SECTION = 'VocalMIDIGenVKR'
local PROJ_KEY_NAME    = 'settings_v1'

local function bool_to_num(b) return b and 1 or 0 end
local function num_to_bool(n) return (tonumber(n) or 0) ~= 0 end

-- Table-driven settings spec. Adding a new slider requires one entry here only.
-- kind: 'float' (stored as-is; fmt is a printf format string),
--       'int'   (math.floor(v+0.5) on read),
--       'bool'  (num_to_bool on read).
local SETTINGS = {
    { key='rms',    field='rms_threshold',             fmt='%.6f', kind='float' },
    { key='lpf',    field='lpf_cutoff_hz',             fmt='%.2f', kind='float' },
    { key='split',  field='split_ratio',               fmt='%.2f', kind='float' },
    { key='offset', field='min_offset_ms',             fmt='%.2f', kind='float' },
    { key='minnote',field='min_note_ms',               fmt='%.2f', kind='float' },
    { key='window', field='window_ms',                 fmt='%.2f', kind='float' },
    { key='pmode',  field='pitch_mode',                             kind='int'  },
    { key='pitch',  field='pitch',                                  kind='int'  },
    { key='reftol', field='ref_search_ms',             fmt='%.0f', kind='float' },
    { key='minpe',  field='min_pitch_enabled',                      kind='bool' },
    { key='minp',   field='min_pitch',                              kind='int'  },
    { key='maxpe',  field='max_pitch_enabled',                      kind='bool' },
    { key='maxp',   field='max_pitch',                              kind='int'  },
    { key='vel',    field='velocity',                               kind='int'  },
    { key='yt',     field='yin_threshold',             fmt='%.3f', kind='float' },
    { key='ymn',    field='yin_min_freq',                           kind='int'  },
    { key='ymx',    field='yin_max_freq',                           kind='int'  },
    { key='yw',     field='yin_window_ms',             fmt='%.0f', kind='float' },
    { key='ycf',    field='yin_min_confidence',        fmt='%.2f', kind='float' },
    { key='yrms',   field='yin_rms_gate',              fmt='%.4f', kind='float' },
    { key='yvw',    field='yin_vote_windows',                      kind='int'  },
    { key='sl_mn',  field='slide_min_note_ms',                      kind='int'  },
    { key='sl_ms',  field='slide_min_seg_ms',                       kind='int'  },
    { key='sl_sk',  field='slide_skip_ms',                          kind='int'  },
    { key='sl_st',  field='slide_step_ms',                          kind='int'  },
    { key='sl_wn',  field='slide_win_ms',                           kind='int'  },
    { key='hd1e',   field='harm_dst1_enabled',                      kind='bool' },
    { key='hd2e',   field='harm_dst2_enabled',                      kind='bool' },
    { key='hd3e',   field='harm_dst3_enabled',                      kind='bool' },
    { key='hd1m',   field='harm_dst1_mode',                         kind='int'  },
    { key='hd2m',   field='harm_dst2_mode',                         kind='int'  },
    { key='hd3m',   field='harm_dst3_mode',                         kind='int'  },
    { key='hcpm',   field='harm_copy_phrase_markers',               kind='bool' },
    { key='hcod',   field='harm_copy_overdrive',                    kind='bool' },
    { key='hkr',    field='harm_key_root',                          kind='int'  },
    { key='hkq',    field='harm_key_quality',                       kind='int'  },
    { key='hd1lu',  field='harm_dst1_lyric_unpitched',              kind='bool' },
    { key='hd2lu',  field='harm_dst2_lyric_unpitched',              kind='bool' },
    { key='hd3lu',  field='harm_dst3_lyric_unpitched',              kind='bool' },
    { key='hd1lh',  field='harm_dst1_lyric_hidden',                 kind='bool' },
    { key='hd2lh',  field='harm_dst2_lyric_hidden',                 kind='bool' },
    { key='hd3lh',  field='harm_dst3_lyric_hidden',                 kind='bool' },
    { key='skr',    field='snap_key_root',                          kind='int'  },
    { key='skq',    field='snap_key_quality',                       kind='int'  },
    { key='sac',    field='snap_avoid_collision',                   kind='bool' },
    { key='pst',    field='phrase_sim_threshold',                   kind='int'  },
    { key='psk',    field='phrase_same_key',                        kind='bool' },
    { key='trms',   field='tuner_rms_threshold',       fmt='%.4f', kind='float' },
    { key='swip',   field='show_wip_tabs',                        kind='bool'  },
}

local function SerializeSettings()
    local parts = {}
    for _, s in ipairs(SETTINGS) do
        local v = S[s.field]
        local val
        if s.kind == 'bool' then
            val = v and '1' or '0'
        elseif s.kind == 'int' then
            val = ('%d'):format(math.floor(v + 0.5))
        else
            val = s.fmt:format(v)
        end
        parts[#parts + 1] = s.key .. '=' .. val
    end
    return table.concat(parts, ';')
end

local function DeserializeSettings(str)
    local tmp = {}
    for k, v in str:gmatch('([%w_]+)=([^;]+)') do
        tmp[k] = tonumber(v)
    end
    for _, s in ipairs(SETTINGS) do
        if tmp[s.key] ~= nil then
            if s.kind == 'bool' then
                S[s.field] = num_to_bool(tmp[s.key])
            elseif s.kind == 'int' then
                S[s.field] = math.floor(tmp[s.key] + 0.5)
            else
                S[s.field] = tmp[s.key]
            end
        end
    end
    if S.pitch_mode == MODE_SINGLE then S.pitch_mode = DEFAULTS.pitch_mode end
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
