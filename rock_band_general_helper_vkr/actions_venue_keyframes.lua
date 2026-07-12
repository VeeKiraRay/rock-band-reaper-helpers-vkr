-- Keyframes tab: bulk regeneration of [first]/[next] keyframes for every manual lighting
-- event already on the VENUE track.
-- Requires: FindTrackByName, GetTimeSelection, MANUAL_LIGHTING_SET, GenerateKeyframesForSpan,
--           ClearVenueKeyframesInRange, r, S (globals)

function RegenerateVenueKeyframes()
    local track = FindTrackByName('VENUE')
    if not track then
        S.status = 'No VENUE track found.'
        return
    end
    local item, take
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local it = r.GetTrackMediaItem(track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then item, take = it, tk; break end
    end
    if not item then
        S.status = 'No MIDI item on VENUE track.'
        return
    end

    local qn_start = r.MIDI_GetPPQPosFromProjQN(take, 0)
    local qn_one   = r.MIDI_GetPPQPosFromProjQN(take, 1)
    local ppq      = qn_one - qn_start
    if ppq <= 0 then ppq = 960 end
    local half_beat = math.floor(ppq / 2 + 0.5)

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')

    local sel_s, sel_e = GetTimeSelection()
    local has_sel       = sel_s ~= nil
    local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, has_sel and sel_s or item_start_sec)
    local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, has_sel and sel_e or item_end_sec)

    -- Read every [lighting (...)] event on the whole take (not range-limited) so a manual
    -- event near the range's end can still find its true next-lighting boundary even when
    -- that boundary sits outside the range - the span itself is then clamped to range end.
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    local lighting_events = {}
    for i = 0, text_count - 1 do
        local ok, _, _, ppq_pos, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and msg:find('^%[lighting') then
            lighting_events[#lighting_events + 1] = { ppq = ppq_pos, msg = msg }
        end
    end
    table.sort(lighting_events, function(a, b) return a.ppq < b.ppq end)

    -- Build spans: for each manual lighting event whose trigger falls inside the processing
    -- range, from its ppq to the next lighting event's ppq (any kind), clamped to range end.
    -- A trigger outside the range never starts a span - its keyframes are left untouched even
    -- if part of its train would otherwise fall inside the range.
    local spans = {}
    for i, ev in ipairs(lighting_events) do
        if MANUAL_LIGHTING_SET[ev.msg]
                and ev.ppq >= range_start_ppq and ev.ppq < range_end_ppq then
            local span_end = range_end_ppq
            if lighting_events[i + 1] and lighting_events[i + 1].ppq < span_end then
                span_end = lighting_events[i + 1].ppq
            end
            if span_end > ev.ppq then
                spans[#spans + 1] = { start_ppq = ev.ppq, end_ppq = span_end }
            end
        end
    end

    if #spans == 0 then
        S.status = 'No manual lighting events found in range - nothing to regenerate.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    local total = 0
    for _, span in ipairs(spans) do
        ClearVenueKeyframesInRange(take, span.start_ppq, span.end_ppq)

        local ctrl_events = GenerateKeyframesForSpan(take, span.start_ppq, span.end_ppq, ppq, S.venue_kf_rate)
        for _, ev in ipairs(ctrl_events) do
            local snapped = math.max(ev.ppq, math.floor(ev.ppq / half_beat + 0.5) * half_beat)
            r.MIDI_InsertTextSysexEvt(take, false, false, snapped, 1, ev.text)
            total = total + 1
        end
    end

    r.Undo_EndBlock2(0, 'RB Regenerate Venue Keyframes (' .. total .. ' events)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local scope = has_sel and 'time selection' or 'full song'
    S.status = ('Regenerated %d keyframe events across %d manual lighting section(s) (%s).')
        :format(total, #spans, scope)
end
