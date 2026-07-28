-- Manual gen actions: single-event insertion at the playhead, playhead advance,
-- keyframe generation, and selective event removal.
-- Requires: FindNamedTrackMIDI, GetTakePPQPerQN, MANUAL_LIGHTING_SET, INST_KF_MODES,
--           FindNextMeasureStartPpq, CollectInstNotePositions, ResolveUserCamInterval,
--           JitteredInterval, CAM_INTERVAL_16THS, CAM_JITTER, KeyframeSubdivQN,
--           DeleteTextEventsInRange, ClearVenueKeyframesInRange, CategorizeVenueEvent,
--           FindTrackByName, FindFirstMIDIItem, RB3_PHRASE_PITCH, r, S (globals)

local function _find_venue_track_and_take()
    local track, item, take = FindNamedTrackMIDI('VENUE')
    if not track then
        S.status = 'No VENUE track found.'
        return nil, nil, nil
    end
    if not item then
        S.status = 'No MIDI item on VENUE track.'
        return nil, nil, nil
    end
    return track, item, take
end

-- ---------------------------------------------------------------------------

function InsertVenueEventAtPlayhead(text)
    local track, item, take = _find_venue_track_and_take()
    if not track then return end

    local abs_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_InsertTextSysexEvt(take, false, false, abs_ppq, 1, text)
    r.Undo_EndBlock2(0, 'RB Insert VENUE event: ' .. text, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = 'Inserted ' .. text .. ' at playhead (VENUE).'
end

-- ---------------------------------------------------------------------------

-- Returns the PPQ of the next PART VOCALS phrase-marker (pitch 105, RB3_PHRASE_PITCH)
-- note start strictly after cur_ppq on the given take, or nil when none exists. Pure
-- function of (take, cur_ppq) so it can be driven by a test without a MIDI editor.
function FindNextVocalPhraseStartPpq(take, cur_ppq)
    local next_ppq = nil
    local _, note_cnt = r.MIDI_CountEvts(take)
    for i = 0, note_cnt - 1 do
        local ok, _, muted, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
        if ok and not muted and pitch == RB3_PHRASE_PITCH and sppq > cur_ppq then
            if not next_ppq or sppq < next_ppq then next_ppq = sppq end
        end
    end
    return next_ppq
end

function AdvanceCameraPacing()
    if S.venue_cam_pacing == 7 then
        local vt_track = FindTrackByName('PART VOCALS')
        local vt_take
        if vt_track then
            local _vt_item
            _vt_item, vt_take = FindFirstMIDIItem(vt_track)
        end
        if not vt_take then
            S.status = 'No PART VOCALS track/MIDI item found - cannot advance to next vocal phrase.'
            return
        end
        local cur_ppq  = r.MIDI_GetPPQPosFromProjTime(vt_take, r.GetCursorPosition())
        local next_ppq = FindNextVocalPhraseStartPpq(vt_take, cur_ppq)
        if not next_ppq then
            S.status = 'No further vocal phrase found - already at or past the last phrase.'
            return
        end
        r.SetEditCurPos(r.MIDI_GetProjTimeFromPPQPos(vt_take, next_ppq), true, false)
        S.status = 'Advanced playhead to next vocal phrase start.'
        return
    end

    local bpm = r.Master_GetTempo()
    local cam_interval = ResolveUserCamInterval(bpm) or CAM_INTERVAL_16THS

    local actual_16ths = JitteredInterval(cam_interval, S.venue_cam_pacing_jitter and CAM_JITTER or 0)
    local delta_qn     = actual_16ths * 0.25  -- 1 sixteenth = 0.25 quarter notes

    local cur_t  = r.GetCursorPosition()
    local cur_qn = r.TimeMap_timeToQN(cur_t)
    local new_t  = r.TimeMap_QNToTime(cur_qn + delta_qn)
    r.SetEditCurPos(new_t, true, false)

    S.status = ('Advanced playhead by %d sixteenths.'):format(actual_16ths)
end

-- ---------------------------------------------------------------------------

function GenerateManualKeyframes()
    if S.venue_mg_lighting == '' then
        S.status = 'Select a manual lighting preset first (lighting dropdown above).'
        return
    end
    local full_ev = '[lighting (' .. S.venue_mg_lighting .. ')]'
    if not MANUAL_LIGHTING_SET[full_ev] then
        S.status = 'Keyframe gen requires a manual lighting preset: verse, chorus, manual_cool, manual_warm, dischord, or stomp.'
        return
    end

    local track, item, take = _find_venue_track_and_take()
    if not track then return end

    local ppq       = GetTakePPQPerQN(take)
    local half_beat = math.floor(ppq / 2 + 0.5)

    local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local end_ppq        = r.MIDI_GetPPQPosFromProjTime(take, item_end_sec)

    -- Clamp to time selection if active
    local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if sel_e > sel_s then
        local sel_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
        if sel_end_ppq < end_ppq then end_ppq = sel_end_ppq end
    end

    -- Clamp to next lighting event after cursor
    local _, _, _, tc = r.MIDI_CountEvts(take)
    local next_lt_ppq = nil
    for i = 0, tc - 1 do
        local ok, _, _, ppq_pos, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq_pos > start_ppq + half_beat
                and msg:find('^%[lighting') then
            if not next_lt_ppq or ppq_pos < next_lt_ppq then
                next_lt_ppq = ppq_pos
            end
        end
    end
    if next_lt_ppq and next_lt_ppq < end_ppq then end_ppq = next_lt_ppq end

    if end_ppq <= start_ppq then
        S.status = 'No range available for keyframe generation (cursor is at or past end boundary).'
        return
    end

    -- Compute keyframe events
    local ctrl_events = {}
    local align   = S.venue_keyframe_align
    local kf_beats = S.venue_mg_kf_rate
    local kf_ticks = kf_beats * ppq

    if align >= 3 and INST_KF_MODES[align] then
        local inst_info    = INST_KF_MODES[align]
        local inst_pos     = CollectInstNotePositions(
            inst_info.track_name, inst_info.pitch_min, inst_info.pitch_max,
            take, start_ppq, end_ppq)
        local subdiv_qn    = KeyframeSubdivQN(S.venue_kf_inst_subdiv)
        local subdiv_ticks = math.floor(subdiv_qn * ppq)

        ctrl_events[#ctrl_events + 1] = { ppq = start_ppq, text = '[first]' }

        local sec_qn    = r.TimeMap_timeToQN(r.MIDI_GetProjTimeFromPPQPos(take, start_ppq))
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
            -- Anchor [next] to the nearest beat to the playhead so the [next] grid
            -- lands on whole beats even when [first] is not beat-aligned (modes 0 & 1).
            -- beat_anchor + kf_ticks is always > start_ppq since kf_ticks >= 1 beat.
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

    if #ctrl_events == 0 then
        S.status = 'No keyframe positions found in range.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    -- Clear existing keyframe events in range
    ClearVenueKeyframesInRange(take, start_ppq, end_ppq)

    -- Insert new keyframe events at their already-computed alignment grid position (beat,
    -- half-beat, quarter-beat, etc. per S.venue_kf_inst_subdiv for instrument-aware modes) -
    -- no further snapping, or a coarser half-beat re-snap would collapse finer positions.
    for _, ev in ipairs(ctrl_events) do
        r.MIDI_InsertTextSysexEvt(take, false, false, ev.ppq, 1, ev.text)
    end

    r.Undo_EndBlock2(0, 'RB Generate Manual Keyframes (' .. #ctrl_events .. ' events)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Generated %d keyframe events.'):format(#ctrl_events)
end

-- ---------------------------------------------------------------------------

function RemoveVenueEventsByType(remove_type)
    local track, item, take = _find_venue_track_and_take()
    if not track then return end

    local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local has_sel      = sel_e > sel_s

    local item_start_sec  = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec    = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, has_sel and sel_s or item_start_sec)
    local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, has_sel and sel_e or item_end_sec)

    -- Category membership per remove_type, in terms of CategorizeVenueEvent's output
    -- (actions_venue_subtracks.lua) - the single shared classifier also used by the Sub VENUE
    -- tracks split. "Camera" = coop or directed; "Special" = special (bonusfx + anything
    -- unrecognized) or keyframe, matching the previous pattern-based groupings exactly.
    -- "All" is unconditionally true since the classifier's categories are exhaustive.
    local match
    if remove_type == 0 then
        match = function(msg) local c = CategorizeVenueEvent(msg); return c == 'coop' or c == 'directed' end
    elseif remove_type == 1 then
        match = function(msg) return CategorizeVenueEvent(msg) == 'lighting' end
    elseif remove_type == 2 then
        match = function(msg) return CategorizeVenueEvent(msg) == 'postproc' end
    elseif remove_type == 3 then
        match = function(msg) local c = CategorizeVenueEvent(msg); return c == 'special' or c == 'keyframe' end
    else  -- 4 = All
        match = function(msg) return true end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    local count = DeleteTextEventsInRange(take, range_start_ppq, range_end_ppq,
                                          function(msg) return not match(msg) end)

    local type_names = { 'Camera', 'Lighting', 'Post proc', 'Special', 'All' }
    local tname      = type_names[remove_type + 1] or ''
    r.Undo_EndBlock2(0, 'RB Remove VENUE ' .. tname .. ' events (' .. count .. ')', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local scope = has_sel and 'time selection' or 'full song'
    S.status = ('Removed %d %s events (%s).'):format(count, tname, scope)
end
