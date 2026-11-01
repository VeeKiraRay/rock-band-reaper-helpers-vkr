-- Keyframes tab: bulk regeneration of [first]/[next] keyframes for every manual lighting
-- event already on the VENUE track - or, with Target = Subtracks, for every one on
-- "VENUE lighting", writing the keyframes to "VENUE keyevents".
-- Requires: FindVenueTarget, VenueTargetName, VenueTargetUsesSubtracks, VenuePpqBetween
--           (actions_venue_manual.lua), GetTakePPQPerQN, GetTimeSelection,
--           MANUAL_LIGHTING_SET, GenerateKeyframesForSpan, ClearVenueKeyframesInRange,
--           r, S (globals)

function RegenerateVenueKeyframes()
    -- Lighting is read from one take and the keyframes written to another; with Target =
    -- VENUE both are the VENUE take. Every position below is in the lighting take's ticks
    -- until the write, which converts through project time.
    local track, item, take = FindVenueTarget('lighting')
    if not track then return end
    local kf_track, kf_item, kf_take = FindVenueTarget('keyframe')
    if not kf_track then return end

    local ppq = GetTakePPQPerQN(take)

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
    --
    -- Restatements are skipped on both ends: an event repeating the lighting event
    -- immediately before it doesn't change the active preset, so it starts no keyframe
    -- sequence and doesn't end the running one either - the train carries on through it.
    -- That is what a blend-in duplicate is (EmitBlendDuplicates, venue_lighting.lua), and
    -- matching the rule here is what makes generating and regenerating agree. Only the
    -- ADJACENT event is compared, so two sections sharing a preset with a different one
    -- between them are each treated as a real change.
    local spans = {}
    for i, ev in ipairs(lighting_events) do
        local restates = lighting_events[i - 1] and lighting_events[i - 1].msg == ev.msg
        if MANUAL_LIGHTING_SET[ev.msg] and not restates
                and ev.ppq >= range_start_ppq and ev.ppq < range_end_ppq then
            local span_end = range_end_ppq
            for j = i + 1, #lighting_events do
                if lighting_events[j].msg ~= ev.msg then
                    if lighting_events[j].ppq < span_end then
                        span_end = lighting_events[j].ppq
                    end
                    break
                end
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

    -- Generate every span first, from the lighting take, then write: clearing the keyframe
    -- take never changes what a later span reads (in VENUE mode they are one take, and the
    -- clear only removes keyframes, which no span reads).
    local planned = {}
    for _, span in ipairs(spans) do
        planned[#planned + 1] = {
            span   = span,
            events = GenerateKeyframesForSpan(take, span.start_ppq, span.end_ppq, ppq, S.venue_kf_rate),
        }
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(kf_track, kf_item)

    local total = 0
    for _, p in ipairs(planned) do
        ClearVenueKeyframesInRange(kf_take,
            VenuePpqBetween(take, p.span.start_ppq, kf_take),
            VenuePpqBetween(take, p.span.end_ppq, kf_take))
        for _, ev in ipairs(p.events) do
            -- Already placed on its alignment grid (beat/half-beat/quarter-beat, etc.) by
            -- GenerateKeyframesForSpan - no further snapping, or a coarser half-beat re-snap
            -- would collapse finer instrument-aware positions onto the nearest half-beat/beat.
            r.MIDI_InsertTextSysexEvt(kf_take, false, false,
                VenuePpqBetween(take, ev.ppq, kf_take), 1, ev.text)
            total = total + 1
        end
    end

    r.Undo_EndBlock2(0, 'RB Regenerate Venue Keyframes (' .. total .. ' events)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local scope = has_sel and 'time selection' or 'full song'
    local where = VenueTargetUsesSubtracks()
        and (' (%s -> %s)'):format(VenueTargetName('lighting'), VenueTargetName('keyframe'))
        or ''
    S.status = ('Regenerated %d keyframe events across %d manual lighting section(s) (%s)%s.')
        :format(total, #spans, scope, where)
end
