-- Lighting and keyframe event generation: section processing, themed and random modes.
-- Requires: BuildLightingPool, BuildPostprocPool, GetSectionPreset, FindTrackByName,
--           PickRandom, JitteredInterval, r, S (globals from venue_camera.lua and venue_themes.lua)
-- Globals exported: MANUAL_LIGHTING_SET, LIGHTING_OFFSET_16THS, INST_KF_MODES,
--   FindNextMeasureStartPpq, CollectInstNotePositions, GenerateKeyframesForSpan,
--   GenerateLightingEvents, GenerateThemedSectionEvents

local MANUAL_LIGHTING_POOL = {
    '[lighting (verse)]', '[lighting (chorus)]',
    '[lighting (manual_cool)]', '[lighting (manual_warm)]',
    '[lighting (dischord)]', '[lighting (stomp)]',
}

local AUTO_LIGHTING_POOL = {
    '[lighting (loop_cool)]', '[lighting (loop_warm)]',
    '[lighting (harmony)]', '[lighting (frenzy)]',
    '[lighting (silhouettes)]', '[lighting (silhouettes_spot)]',
    '[lighting (searchlights)]', '[lighting (sweep)]',
    '[lighting (strobe_slow)]', '[lighting (strobe_fast)]',
    '[lighting (blackout_slow)]', '[lighting (blackout_fast)]', '[lighting (blackout_spot)]',
    '[lighting (flare_slow)]', '[lighting (flare_fast)]',
    '[lighting (bre)]',
}

MANUAL_LIGHTING_SET = {}
for _, v in ipairs(MANUAL_LIGHTING_POOL) do MANUAL_LIGHTING_SET[v] = true end

-- Instrument track info for keyframe alignment modes 3-7 (S.venue_keyframe_align).
INST_KF_MODES = {
    [3] = { track_name = 'PART GUITAR', pitch_min = 96, pitch_max = 100 },
    [4] = { track_name = 'PART BASS',   pitch_min = 96, pitch_max = 100 },
    [5] = { track_name = 'PART KEYS',   pitch_min = 96, pitch_max = 100 },
    [6] = { track_name = 'PART DRUMS',  pitch_min = 96, pitch_max = 96  },
    [7] = { track_name = 'PART DRUMS',  pitch_min = 97, pitch_max = 97  },
}

local LIGHTING_INTERVAL_16THS = 128   -- ~8 measures between lighting changes
local LIGHTING_JITTER         = 0.25  -- ±25% randomisation
LIGHTING_OFFSET_16THS         = 32    -- lighting starts 2 measures into range
local KEYFRAME_MIN_BEATS      = 1     -- manual lighting [next] min interval (beats)
local KEYFRAME_MAX_BEATS      = 4     -- manual lighting [next] max interval (beats)

-- ---------------------------------------------------------------------------

local function SnapPpqToNearestBeat(ppq_pos, ppq)
    return math.floor(ppq_pos / ppq + 0.5) * ppq
end

-- Returns the PPQ position of the start of the NEXT measure after ppq_pos.
-- Scans forward from an estimate to find the first measure whose end exceeds ppq_pos.
function FindNextMeasureStartPpq(take, ppq_pos, ppq)
    local proj_time = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local qn        = r.TimeMap_timeToQN(proj_time)
    local est       = math.max(0, math.floor(qn / 4) - 1)
    for m = est, est + 30 do
        local _, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, m)
        if not qn_s then break end
        local t_e = r.TimeMap_QNToTime(qn_e)
        if t_e > proj_time + 1e-5 then
            return r.MIDI_GetPPQPosFromProjTime(take, t_e)
        end
    end
    return ppq_pos + 4 * ppq  -- fallback: one bar forward
end

-- Returns a sorted array of VENUE-take PPQ positions for notes in [pitch_min, pitch_max]
-- on the named instrument track that fall within [range_start_ppq, range_end_ppq).
-- Returns {} when the track or its MIDI item cannot be found.
function CollectInstNotePositions(track_name, pitch_min, pitch_max, venue_take,
                                        range_start_ppq, range_end_ppq)
    local inst_track = FindTrackByName(track_name)
    if not inst_track then return {} end
    local inst_take
    for i = 0, r.CountTrackMediaItems(inst_track) - 1 do
        local it = r.GetTrackMediaItem(inst_track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then inst_take = tk; break end
    end
    if not inst_take then return {} end

    local start_t    = r.MIDI_GetProjTimeFromPPQPos(venue_take, range_start_ppq)
    local end_t      = r.MIDI_GetProjTimeFromPPQPos(venue_take, range_end_ppq)
    local inst_s_ppq = r.MIDI_GetPPQPosFromProjTime(inst_take, start_t)
    local inst_e_ppq = r.MIDI_GetPPQPosFromProjTime(inst_take, end_t)

    local positions   = {}
    local _, note_cnt = r.MIDI_CountEvts(inst_take)
    for i = 0, note_cnt - 1 do
        local ok, _, muted, sppq, _, _, pitch = r.MIDI_GetNote(inst_take, i)
        if ok and not muted and pitch >= pitch_min and pitch <= pitch_max
                and sppq >= inst_s_ppq and sppq < inst_e_ppq then
            local proj_t    = r.MIDI_GetProjTimeFromPPQPos(inst_take, sppq)
            local venue_ppq = r.MIDI_GetPPQPosFromProjTime(venue_take, proj_t)
            positions[#positions + 1] = venue_ppq
        end
    end
    table.sort(positions)
    return positions
end

-- Returns an array of {ppq, text} keyframe events ('[first]'/'[next]') for one manual-lighting
-- span [start_ppq, end_ppq), using the shared S.venue_keyframe_align / S.venue_kf_inst_subdiv
-- settings and the given rate in beats. Same algorithm as GenerateManualKeyframes's body
-- (actions_venue_manual.lua), parameterized so it can be reused per-span by other callers.
function GenerateKeyframesForSpan(take, start_ppq, end_ppq, ppq, kf_rate_beats)
    local ctrl_events = {}
    local align    = S.venue_keyframe_align
    local kf_ticks = kf_rate_beats * ppq

    if align >= 3 and INST_KF_MODES[align] then
        local inst_info    = INST_KF_MODES[align]
        local inst_pos     = CollectInstNotePositions(
            inst_info.track_name, inst_info.pitch_min, inst_info.pitch_max,
            take, start_ppq, end_ppq)
        local subdiv_ticks = math.floor(S.venue_kf_inst_subdiv == 1 and ppq / 2 or ppq)

        ctrl_events[#ctrl_events + 1] = { ppq = start_ppq, text = '[first]' }

        local sec_qn    = r.TimeMap_timeToQN(r.MIDI_GetProjTimeFromPPQPos(take, start_ppq))
        local subdiv_qn = S.venue_kf_inst_subdiv == 1 and 0.5 or 1.0
        local grid_qn   = math.ceil(sec_qn / subdiv_qn + 1e-6) * subdiv_qn
        local pos_ppq   = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap_QNToTime(grid_qn))
        local tolerance = math.floor(ppq / 32)
        local ni        = 1
        while pos_ppq < end_ppq do
            while ni <= #inst_pos and inst_pos[ni] < pos_ppq - tolerance do
                ni = ni + 1
            end
            if ni <= #inst_pos and inst_pos[ni] <= pos_ppq + tolerance then
                ctrl_events[#ctrl_events + 1] = { ppq = pos_ppq, text = '[next]' }
            end
            pos_ppq = pos_ppq + subdiv_ticks
        end
    else
        -- Standard modes 0-2
        local first_ppq
        if align == 1 then
            first_ppq = math.max(start_ppq, math.floor(start_ppq / ppq + 0.5) * ppq)
        else
            first_ppq = start_ppq
        end

        local next_ppq
        if align == 2 then
            local nms = FindNextMeasureStartPpq(take, start_ppq, ppq)
            next_ppq  = nms < end_ppq and nms or nil
        else
            -- Anchor [next] to the nearest beat to the span start so the [next] grid lands on
            -- whole beats even when [first] is not beat-aligned (modes 0 & 1).
            local beat_anchor = math.floor(start_ppq / ppq + 0.5) * ppq
            next_ppq = beat_anchor + kf_ticks
        end

        if first_ppq < end_ppq then
            ctrl_events[#ctrl_events + 1] = { ppq = first_ppq, text = '[first]' }
        end
        if next_ppq then
            local pos_ppq = next_ppq
            while pos_ppq < end_ppq do
                ctrl_events[#ctrl_events + 1] = { ppq = pos_ppq, text = '[next]' }
                pos_ppq = pos_ppq + kf_ticks
            end
        end
    end

    return ctrl_events
end

-- pool_override: use a specific pool instead of the combined MANUAL+AUTO default
function GenerateLightingEvents(range_16ths, ppq, pool_override)
    local sixteenth_ticks = ppq / 4
    local combined_pool
    if pool_override then
        combined_pool = pool_override
    else
        combined_pool = {}
        for _, v in ipairs(MANUAL_LIGHTING_POOL) do combined_pool[#combined_pool + 1] = v end
        for _, v in ipairs(AUTO_LIGHTING_POOL)   do combined_pool[#combined_pool + 1] = v end
    end

    local lt_events = {}
    local pos_16ths = 0
    local last_pick = nil

    while pos_16ths < range_16ths do
        local text = PickRandom(combined_pool, last_pick)
        last_pick = text
        lt_events[#lt_events + 1] = {
            tick      = math.floor(pos_16ths * sixteenth_ticks + 0.5),
            text      = text,
            pos_16ths = pos_16ths,
        }
        pos_16ths = pos_16ths + JitteredInterval(LIGHTING_INTERVAL_16THS, LIGHTING_JITTER)
    end

    local ctrl_events = {}
    for i, ev in ipairs(lt_events) do
        if MANUAL_LIGHTING_SET[ev.text] then
            local keyframe_16ths = math.random(KEYFRAME_MIN_BEATS, KEYFRAME_MAX_BEATS) * 4
            local end_16ths      = range_16ths
            if i < #lt_events then end_16ths = lt_events[i + 1].pos_16ths end

            local ctrl_pos = ev.pos_16ths
            local first    = true
            while ctrl_pos < end_16ths do
                ctrl_events[#ctrl_events + 1] = {
                    tick = math.floor(ctrl_pos * sixteenth_ticks + 0.5),
                    text = first and '[first]' or '[next]',
                }
                first    = false
                ctrl_pos = ctrl_pos + keyframe_16ths
            end
        end
    end

    return lt_events, ctrl_events
end

-- Generates lighting, keyframe control, and postproc events for each detected
-- [prc_*] section using the active theme. Tick offsets are from range_start_ppq.
local function ProcessThemeSection(sec, theme, take, range_start_ppq, range_end_ppq, ppq,
                                   lt_events, ctrl_events, pp_events, inst_note_positions)
    local sec_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
    local sec_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, sec.t_end)
    if sec_start_ppq >= range_end_ppq or sec_end_ppq <= range_start_ppq then return end

    local preset = GetSectionPreset(theme, sec.name, sec.num)
    if not preset then return end

    local lt_pool = BuildLightingPool(preset)
    local pp_pool = BuildPostprocPool(preset)

    local blendin_ticks  = (preset.lightpreset_blendin or 0) * ppq
    local lt_ppq_abs     = math.max(range_start_ppq, sec_start_ppq - blendin_ticks)
    local lt_tick_offset = math.floor(lt_ppq_abs - range_start_ppq + 0.5)

    if lt_pool and #lt_pool > 0 then
        local lt_text = lt_pool[math.random(#lt_pool)]
        lt_events[#lt_events + 1] = { tick = lt_tick_offset, text = lt_text }

        if MANUAL_LIGHTING_SET[lt_text] then
            local sec_ppq = math.max(range_start_ppq, sec_start_ppq)
            local kf_end  = math.min(range_end_ppq, sec_end_ppq)
            local align   = S.venue_keyframe_align

            if align >= 3 and inst_note_positions then
                -- Instrument-aware mode: [first] at section start; [next] only at
                -- beat or half-beat grid positions that have at least one qualifying note.
                local subdiv_ticks = math.floor(
                    S.venue_kf_inst_subdiv == 1 and ppq / 2 or ppq)
                if sec_ppq < kf_end then
                    ctrl_events[#ctrl_events + 1] = {
                        tick = math.floor(sec_ppq - range_start_ppq + 0.5),
                        text = '[first]',
                    }
                end
                -- Find the first beat/half-beat grid line strictly after sec_ppq.
                -- Uses the tempo map so sparse marker projects and off-beat section
                -- starts are all handled correctly (same pattern as FindNextMeasureStartPpq).
                local sec_proj_t = r.MIDI_GetProjTimeFromPPQPos(take, sec_ppq)
                local sec_qn     = r.TimeMap_timeToQN(sec_proj_t)
                local subdiv_qn  = S.venue_kf_inst_subdiv == 1 and 0.5 or 1.0
                local grid_qn    = math.ceil(sec_qn / subdiv_qn + 1e-6) * subdiv_qn
                local grid_t     = r.TimeMap_QNToTime(grid_qn)
                local pos_ppq    = r.MIDI_GetPPQPosFromProjTime(take, grid_t)
                local tolerance  = math.floor(ppq / 32)  -- ~30 ticks at ppq 960
                local ni         = 1
                while pos_ppq < kf_end do
                    -- Exact match: note must be within tolerance of the grid line,
                    -- not just anywhere in the subdivision interval.
                    while ni <= #inst_note_positions
                          and inst_note_positions[ni] < pos_ppq - tolerance do
                        ni = ni + 1
                    end
                    if ni <= #inst_note_positions
                          and inst_note_positions[ni] <= pos_ppq + tolerance then
                        ctrl_events[#ctrl_events + 1] = {
                            tick = math.floor(pos_ppq - range_start_ppq + 0.5),
                            text = '[next]',
                        }
                    end
                    pos_ppq = pos_ppq + subdiv_ticks
                end
            else
                -- Standard modes 0-2: use theme keyframe_rate (or random) for [next] spacing
                local kf_beats = preset.keyframe_rate
                    or math.random(KEYFRAME_MIN_BEATS, KEYFRAME_MAX_BEATS)
                local kf_ticks = kf_beats * ppq

                -- [first] position: section start, or snapped to nearest beat (mode 1)
                local first_ppq
                if align == 1 then
                    first_ppq = math.max(sec_ppq, SnapPpqToNearestBeat(sec_ppq, ppq))
                else
                    first_ppq = sec_ppq
                end

                -- [next] start: downbeat mode begins from next measure boundary (mode 2)
                local next_ppq
                if align == 2 then
                    local nms = FindNextMeasureStartPpq(take, sec_ppq, ppq)
                    next_ppq  = nms < kf_end and nms or nil
                else
                    next_ppq = first_ppq + kf_ticks
                end

                if first_ppq < kf_end then
                    ctrl_events[#ctrl_events + 1] = {
                        tick = math.floor(first_ppq - range_start_ppq + 0.5),
                        text = '[first]',
                    }
                end
                if next_ppq then
                    local pos_ppq = next_ppq
                    while pos_ppq < kf_end do
                        ctrl_events[#ctrl_events + 1] = {
                            tick = math.floor(pos_ppq - range_start_ppq + 0.5),
                            text = '[next]',
                        }
                        pos_ppq = pos_ppq + kf_ticks
                    end
                end
            end
        end
    end

    if pp_pool and #pp_pool > 0 then
        local pp_blendin_ticks = (preset.postproc_blendin or 0) * ppq
        local pp_ppq_abs       = math.max(range_start_ppq, sec_start_ppq - pp_blendin_ticks)
        local pp_tick_offset   = math.floor(pp_ppq_abs - range_start_ppq + 0.5)
        local pp_text          = pp_pool[math.random(#pp_pool)]
        pp_events[#pp_events + 1] = { tick = pp_tick_offset, text = pp_text }
    end
end

function GenerateThemedSectionEvents(sections, theme, take,
                                     range_start_ppq, range_end_ppq, ppq)
    local lt_events   = {}
    local ctrl_events = {}
    local pp_events   = {}

    -- Pre-compute instrument note positions once for instrument-aware modes (3-7)
    local inst_note_positions = nil
    local inst_info = INST_KF_MODES[S.venue_keyframe_align]
    if inst_info then
        inst_note_positions = CollectInstNotePositions(
            inst_info.track_name, inst_info.pitch_min, inst_info.pitch_max,
            take, range_start_ppq, range_end_ppq)
    end

    for _, sec in ipairs(sections) do
        ProcessThemeSection(sec, theme, take, range_start_ppq, range_end_ppq, ppq,
                            lt_events, ctrl_events, pp_events, inst_note_positions)
    end
    return lt_events, ctrl_events, pp_events
end
