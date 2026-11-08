-- Settings save/load (project state)
-- Requires: S (from defaults.lua), r (global)
--
-- Own section key, not the General Helper's 'RBHelperVKR': the two helpers
-- save independently, so saving in one never overwrites the other's settings.
-- These tabs were part of the General Helper before v0.1 of this script; their
-- values saved there are not read back (a deliberate fresh start).

local PROJ_KEY_SECTION = 'RBInstrumentHelperVKR'
local PROJ_KEY_NAME    = 'settings_v1'

local function SerializeSettings()
    return table.concat({
        'v=1',
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
        'tabim='  .. S.tab_input_mode,
        -- Difficulty tab: the instrument dropdowns
        'dgin='   .. S.diff_gen_instrument,
        'dvci='   .. S.diff_vc_instrument,
        -- Difficulty > Generate: rule style, Custom's option values, the 2x pedal checkbox
        'dgst='   .. S.diff_gen_style,
        'dg2x='   .. (S.diff_gen_drums_2x_on_1x and '1' or '0'),
        -- Custom's values only once Custom has some (GenSetStyle): a project that never
        -- used Custom saves none, so Custom later starts from the style shown before it.
        S.diff_gen_custom_set and table.concat({
            'dgbd=' .. tostring(S.diff_gen_busy_drop),
            'dgfr=' .. S.diff_gen_fast_runs,
            'dgdb=' .. S.diff_gen_drums_between,
            'dgde=' .. S.diff_gen_drums_eighths,
            'dgor=' .. S.diff_gen_rules,
        }, ';') or 'dgcs=0',
        -- Difficulty tab: Keys Copy reduced-using-Pro-Keys checkbox
        'd5kpkr=' .. (S.diff_5k_pk_reduce and '1' or '0'),
        -- MIDI alignment
        'mama='  .. S.ma_mode,
        -- MIDI note length/sustain adjustment
        'mndi='  .. S.mn_diff_idx,
        'mnnt='  .. S.mn_note_type,
        'mnnd='  .. S.mn_note_denom,
        'mns32=' .. S.mn_sustain_32nds,
        'mngm='  .. S.mn_gap_mode,
        'swip='   .. (S.show_wip_tabs and '1' or '0'),
        -- Keys > Tuner
        'ctkm='   .. S.ct_key_mode,
        'ctkt='   .. S.ct_key_tonic,
        'ctkn='   .. (S.ct_key_minor and '1' or '0'),
        'ctpl='   .. (S.ct_plain and '1' or '0'),
        'ctrl='   .. (S.ct_read_long and '1' or '0'),
        'ctpa='   .. (S.ct_passage and '1' or '0'),
        -- Overdrive tab
        'odgrp=' .. S.od_group,
        'odiph=' .. (S.od_inc_phrases and '1' or '0'),
        'odifl=' .. (S.od_inc_fills and '1' or '0'),
        'odivo=' .. (S.od_inc_vocals and '1' or '0'),
        'odbpp=' .. S.od_beats_per_phrase,
        'odush=' .. S.od_unison_share,
        'odkod=' .. S.od_keepout_od,
        'odkun=' .. S.od_keepout_unison,
        'odkst=' .. S.od_keepout_start,
        'odtog=' .. (S.od_together and '1' or '0'),
        'odvol=' .. S.od_vocal_overlap,
        'odfpc=' .. S.od_fill_pacing,
        'odfsc=' .. (S.od_fill_sections and '1' or '0'),
        'odfse=' .. (S.od_fill_skip_early and '1' or '0'),
        'odfke=' .. S.od_fill_keepout_end,
        'odvev=' .. S.od_vocal_every,
    }, ';')
end

local function DeserializeSettings(str)
    for k, v in str:gmatch('([^=;]+)=([^;]*)') do
        -- MIDI converter
        if     k == 'mcgt'  then S.mc_ghost_thresh     = tonumber(v) or S.mc_ghost_thresh
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
        elseif k == 'tabim'  then S.tab_input_mode     = tonumber(v) or 0
        -- Difficulty tab: the instrument dropdowns (an unknown key keeps the current pick)
        elseif k == 'dgin' then
            if v == GEN_ALL_KEY or GenInstrumentByKey(v) then S.diff_gen_instrument = v end
        elseif k == 'dvci' then
            if GenInstrumentByKey(v) then S.diff_vc_instrument = v end
        -- Difficulty > Generate: rule style and Custom's option values
        elseif k == 'dgst' then
            for _, st in ipairs(GEN_STYLES) do if st.key == v then S.diff_gen_style = v end end
        elseif k == 'dgbd' or k == 'dgfr' or k == 'dgdb' or k == 'dgde' or k == 'dgor' then
            local field = ({ dgbd = 'diff_gen_busy_drop', dgfr = 'diff_gen_fast_runs', dgdb = 'diff_gen_drums_between',
                             dgde = 'diff_gen_drums_eighths', dgor = 'diff_gen_rules' })[k]
            for _, row in ipairs(GEN_STYLE_ROWS) do
                if row.field == field then
                    -- Only a value the row offers (busy_drop's 1 and 2 are numbers).
                    for _, o in ipairs(row.opts) do
                        if tostring(o[1]) == v then S[field] = o[1] S.diff_gen_custom_set = true end
                    end
                end
            end
        elseif k == 'dgcs' then S.diff_gen_custom_set = false   -- saved without Custom values
        elseif k == 'dg2x' then S.diff_gen_drums_2x_on_1x = (v == '1')
        -- Difficulty tab: Keys Copy reduced-using-Pro-Keys checkbox
        elseif k == 'd5kpkr' then S.diff_5k_pk_reduce  = (v == '1')
        -- MIDI alignment
        elseif k == 'mama'  then S.ma_mode             = tonumber(v) or 0
        -- MIDI note length/sustain adjustment
        elseif k == 'mndi'  then S.mn_diff_idx         = tonumber(v) or S.mn_diff_idx
        elseif k == 'mnnt'  then S.mn_note_type        = tonumber(v) or S.mn_note_type
        -- Note size: only the values the combo still offers (1/8 was dropped
        -- when 1/8 became the sustain threshold) - an older project's 1/8
        -- would render as a blank selection, so keep the current value instead.
        elseif k == 'mnnd'  then
            local d = tonumber(v)
            if d == 16 or d == 32 or d == 64 or d == 128 then S.mn_note_denom = d end
        elseif k == 'mns32' then S.mn_sustain_32nds    = tonumber(v) or S.mn_sustain_32nds
        elseif k == 'mngm'  then S.mn_gap_mode         = (v == '1') and 1 or 0
        elseif k == 'swip'   then S.show_wip_tabs      = (v == '1')
        -- Keys > Tuner
        elseif k == 'ctkm' then
            for _, m in ipairs(CHORD_KEY_MODES or {}) do if m == v then S.ct_key_mode = v end end
        elseif k == 'ctkt' then
            local t = tonumber(v)
            if t and t >= 0 and t <= 11 then S.ct_key_tonic = math.floor(t) end
        elseif k == 'ctkn' then S.ct_key_minor = (v == '1')
        elseif k == 'ctpl' then S.ct_plain     = (v == '1')
        elseif k == 'ctrl' then S.ct_read_long = (v == '1')
        elseif k == 'ctpa' then S.ct_passage   = (v == '1')
        -- Overdrive tab
        elseif k == 'odgrp' then
            local g = tonumber(v)
            if g and g >= 0 and g < 6 then S.od_group = math.floor(g) end
        elseif k == 'odiph' then S.od_inc_phrases      = (v == '1')
        elseif k == 'odifl' then S.od_inc_fills        = (v == '1')
        elseif k == 'odivo' then S.od_inc_vocals       = (v == '1')
        elseif k == 'odbpp' then S.od_beats_per_phrase = tonumber(v) or S.od_beats_per_phrase
        elseif k == 'odush' then S.od_unison_share     = tonumber(v) or S.od_unison_share
        elseif k == 'odkod' then S.od_keepout_od       = tonumber(v) or S.od_keepout_od
        elseif k == 'odkun' then S.od_keepout_unison   = tonumber(v) or S.od_keepout_unison
        elseif k == 'odkst' then S.od_keepout_start    = tonumber(v) or S.od_keepout_start
        elseif k == 'odtog' then S.od_together         = (v == '1')
        elseif k == 'odvol' then
            local m = tonumber(v)
            if m and m >= 0 and m <= 2 then S.od_vocal_overlap = math.floor(m) end
        elseif k == 'odfpc' then
            local p = tonumber(v)
            if p and p >= 0 and p <= 3 then S.od_fill_pacing = math.floor(p) end
        elseif k == 'odfsc' then S.od_fill_sections    = (v == '1')
        elseif k == 'odfse' then S.od_fill_skip_early  = (v == '1')
        elseif k == 'odfke' then S.od_fill_keepout_end = tonumber(v) or S.od_fill_keepout_end
        elseif k == 'odvev' then S.od_vocal_every      = tonumber(v) or S.od_vocal_every
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
