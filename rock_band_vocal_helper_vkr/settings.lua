-- Settings save/load: shipped defaults < my defaults < this project
-- Requires: S, DEFAULTS, MODE_SINGLE (defaults.lua), r, UserDefaultsSetup
-- (lib/reaper_helper_common.lua, loaded before this file)

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
    { key='thm',    field='tuner_harmony',                          kind='bool' },
    { key='tkm',    field='tuner_key_mode',                         kind='int'  },
    { key='tkq',    field='tuner_key_minor',                        kind='bool' },
    { key='tsp',    field='tuner_spectral',                         kind='bool' },
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

-- _project: str comes from a project, not the shipped / my-defaults string
-- (UserDefaultsSetup passes false). The pitch_mode fix below is a sanity check, not an
-- old-project rule, so it runs on every string.
local function DeserializeSettings(str, _project)
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

-- Shipped defaults, then my defaults, then the project's own settings when it has
-- some (lib/reaper_helper_common.lua, "Settings"). Returns true when it had some.
function LoadSettings()
    ApplyDefaults()
    local _, str = r.GetProjExtState(0, PROJ_KEY_SECTION, PROJ_KEY_NAME)
    if str and str ~= '' then
        DeserializeSettings(str, true)
        return true
    end
    return false
end

-- Names for the My defaults list (General > Settings); booleans show On / Off.
local NAMES = {
    rms = 'Detect: RMS threshold', lpf = 'Detect: low-pass cutoff (Hz)',
    split = 'Detect: split ratio', offset = 'Detect: min offset to next note (ms)',
    minnote = 'Detect: min note length (ms)', window = 'Detect: RMS window (ms)',
    pmode = 'Pitch > Placement: mode', pitch = 'Pitch > Placement: fixed pitch',
    reftol = 'Pitch > Placement - Reference: search window (ms)',
    minpe = 'Pitch: min pitch on', minp = 'Pitch: min pitch',
    maxpe = 'Pitch: max pitch on', maxp = 'Pitch: max pitch',
    vel = 'MIDI output: velocity',
    yt = 'Pitch > YIN: threshold', ymn = 'Pitch > YIN: min frequency (Hz)',
    ymx = 'Pitch > YIN: max frequency (Hz)', yw = 'Pitch > YIN: window (ms)',
    ycf = 'Pitch > YIN: min confidence', yrms = 'Pitch > YIN: min RMS level',
    yvw = 'Pitch > YIN: samples per note',
    sl_mn = 'Pitch > Slide: min note length (ms)', sl_ms = 'Pitch > Slide: min segment (ms)',
    sl_sk = 'Pitch > Slide: edge skip (ms)', sl_st = 'Pitch > Slide: sample step (ms)',
    sl_wn = 'Pitch > Slide: sample window (ms)',
    hd1e = 'Harmonies: target 1 on', hd2e = 'Harmonies: target 2 on', hd3e = 'Harmonies: target 3 on',
    hd1m = 'Harmonies: target 1 mode', hd2m = 'Harmonies: target 2 mode', hd3m = 'Harmonies: target 3 mode',
    hcpm = 'Harmonies: copy phrase markers', hcod = 'Harmonies: copy overdrive',
    hkr = 'Harmonies: key root', hkq = 'Harmonies: key quality',
    hd1lu = 'Harmonies: target 1 lyrics unpitched', hd2lu = 'Harmonies: target 2 lyrics unpitched',
    hd3lu = 'Harmonies: target 3 lyrics unpitched',
    hd1lh = 'Harmonies: target 1 lyrics hidden', hd2lh = 'Harmonies: target 2 lyrics hidden',
    hd3lh = 'Harmonies: target 3 lyrics hidden',
    skr = 'Pitch > Snap: key root', skq = 'Pitch > Snap: key quality',
    sac = 'Pitch > Snap: avoid matching neighbor',
    pst = 'Phrases: similarity threshold (%)', psk = 'Phrases: same key only',
    trms = 'Pitch > Tuner: min RMS level', thm = 'Pitch > Tuner: harmony readout',
    tkm = 'Pitch > Tuner: key snap', tkq = 'Pitch > Tuner: minor',
    tsp = 'Pitch > Tuner: spectral reading too',
    swip = 'General > Settings: show WIPs',
}
local LABELS = {}
for _, s in ipairs(SETTINGS) do
    local name = NAMES[s.key] or s.key
    LABELS[s.key] = s.kind == 'bool' and { name, bool = true } or name
end

-- Values that belong to one song: saved with a project, never one of my defaults.
-- The song keys (Harmonies, Snap, a Tuner key snap set to a key note - Off and From
-- charted lead are preferences) and the singer's range (min / max pitch, fixed pitch).
local PROJECT_ONLY = {
    hkr = true, hkq = true, skr = true, skq = true, tkq = true,
    minpe = true, minp = true, maxpe = true, maxp = true, pitch = true,
}
local function ProjectOnly(k, v)
    if k == 'tkm' then return (tonumber(v) or 0) > TUNER_KEY_LEAD end
    return PROJECT_ONLY[k] == true
end

-- Last, while S still holds the shipped defaults: defaults.lua loads first.
UserDefaultsSetup({ section = PROJ_KEY_SECTION, project_key = PROJ_KEY_NAME,
                    serialize = SerializeSettings, deserialize = DeserializeSettings,
                    labels = LABELS, project_only = ProjectOnly })
