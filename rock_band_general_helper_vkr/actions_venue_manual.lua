-- Manual gen actions: single-event insertion at the playhead, playhead advance,
-- keyframe generation, and selective event removal.
-- Requires: FindNamedTrackMIDI, GetTakePPQPerQN, MANUAL_LIGHTING_SET,
--           GenerateKeyframesForSpan, ResolveUserCamInterval,
--           JitteredInterval, CAM_INTERVAL_16THS, CAM_JITTER,
--           DeleteTextEventsInRange, ClearVenueKeyframesInRange, CategorizeVenueEvent,
--           IsBlendAnchor, VENUE_SUBTRACKS (read at call time; loaded later),
--           FindTrackByName, FindFirstMIDIItem, FormatTime, RB3_PHRASE_PITCH,
--           r, S (globals)

-- Reason shown wherever a [first] is refused, in the UI's blocked hover and in the
-- action's own status line, so both read the same.
NO_LIGHTING_AT_PLAYHEAD_MSG =
    '[first] must sit on the same tick as the manual lighting event it drives - ' ..
    'no manual lighting event ([lighting (verse|chorus|manual_cool|manual_warm|' ..
    'dischord|stomp)]) found at the playhead.'

-- Manual gen and the Keyframes tab write to VENUE (S.venue_mg_target 0) or to the Sub
-- VENUE tracks made by Venue > Actions "Copy all to subtracks" (1). In Subtracks mode each
-- event goes to the subtrack of its CategorizeVenueEvent category, the same split those
-- tracks hold. One setting for both views: the subtrack workflow is per project.

function VenueTargetUsesSubtracks()
    return S.venue_mg_target == 1
end

-- Track name Manual gen reads/writes for one category (a VENUE_SUBTRACKS key).
function VenueTargetName(kind)
    if not VenueTargetUsesSubtracks() then return 'VENUE' end
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        if cat.key == kind then return cat.track_name end
    end
    return 'VENUE'
end

local SUBTRACKS_FIRST_HINT =
    'create the subtracks first with Venue > Actions > Copy all to subtracks.'

-- Returns track, item, take for a category, or nil with S.status set.
function FindVenueTarget(kind)
    local name = VenueTargetName(kind)
    local track, item, take = FindNamedTrackMIDI(name)
    if not VenueTargetUsesSubtracks() then
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
    if not track then
        S.status = ('No "%s" track - %s'):format(name, SUBTRACKS_FIRST_HINT)
        return nil, nil, nil
    end
    if not item then
        S.status = ('No MIDI item on "%s" - %s'):format(name, SUBTRACKS_FIRST_HINT)
        return nil, nil, nil
    end
    return track, item, take
end

-- Same project time, expressed in another take's ticks. Subtrack items normally match
-- VENUE's position, but a moved item must not shift the events.
function VenuePpqBetween(src_take, ppq, dst_take)
    if src_take == dst_take then return ppq end
    return r.MIDI_GetPPQPosFromProjTime(dst_take, r.MIDI_GetProjTimeFromPPQPos(src_take, ppq))
end

-- ---------------------------------------------------------------------------

-- "On the playhead" tolerance: a 1/128 note, enough to absorb cursor/grid rounding
-- and far too small to reach a neighbouring event of the same kind (those are
-- seconds apart). Shared so every check in this tab means the same thing by it.
local function _spot_tol(take)
    return math.floor(GetTakePPQPerQN(take) / 32)
end

-- Returns the manual lighting event text at ppq_pos on the take, or nil when there is
-- none. Pure function of (take, ppq_pos) so tests can drive it without a playhead.
function FindManualLightingAtPpq(take, ppq_pos, tol)
    tol = tol or _spot_tol(take)
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, evt_ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and MANUAL_LIGHTING_SET[msg]
                and math.abs(evt_ppq - ppq_pos) <= tol then
            return msg
        end
    end
    return nil
end

-- Replace mode (S.venue_mg_replace 1): the categories an Add clears at the playhead
-- first. Cameras are one family, so a new shot replaces a whole stack on that tick.
local REPLACE_FAMILIES = {
    coop     = { 'coop', 'directed' },
    directed = { 'coop', 'directed' },
    lighting = { 'lighting' },
    postproc = { 'postproc' },
    special  = { 'special' },
    keyframe = { 'keyframe' },
}

-- Deletes the type-1 events within tol of ppq whose CategorizeVenueEvent category is in
-- cats (a set). Returns the removed messages. No UI state, so tests can drive it.
function DeleteVenueEventsAtPpq(take, ppq, tol, cats)
    local removed = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = text_count - 1, 0, -1 do
        local ok, _, _, evt_ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and math.abs(evt_ppq - ppq) <= tol
                and cats[CategorizeVenueEvent(msg)] then
            r.MIDI_DeleteTextSysexEvt(take, i)
            table.insert(removed, 1, msg)
        end
    end
    return removed
end

function InsertVenueEventAtPlayhead(text)
    local kind = CategorizeVenueEvent(text)
    local track, item, take = FindVenueTarget(kind)
    if not track then return end
    local replace = S.venue_mg_replace == 1

    local cursor  = r.GetCursorPosition()
    local abs_ppq = r.MIDI_GetPPQPosFromProjTime(take, cursor)

    -- Re-validate here, never trusting the UI frame's cached check (same discipline as
    -- InsertEventsEvent). Returns before any Undo_* call, so a refusal leaves no undo point.
    -- In Subtracks mode the lighting event lives on another track than the [first].
    if text == '[first]' then
        local _, _, lt_take = FindVenueTarget('lighting')
        if not lt_take then return end
        local lt_ppq = r.MIDI_GetPPQPosFromProjTime(lt_take, cursor)
        if not FindManualLightingAtPpq(lt_take, lt_ppq) then
            S.status = NO_LIGHTING_AT_PLAYHEAD_MSG
            return
        end
    end

    -- Replace: the takes holding the family, grouped so one take is cleared once (in
    -- VENUE mode every category is the VENUE take). A missing subtrack on the clearing
    -- side has nothing to clear and is skipped.
    local clears = {}
    if replace then
        local by_take = {}
        for _, cat in ipairs(REPLACE_FAMILIES[kind] or { kind }) do
            local c_track, c_item, c_take
            if cat == kind then
                c_track, c_item, c_take = track, item, take
            else
                c_track, c_item, c_take = FindNamedTrackMIDI(VenueTargetName(cat))
            end
            if c_item then
                local entry = by_take[c_take]
                if not entry then
                    entry = { track = c_track, item = c_item, take = c_take, cats = {} }
                    by_take[c_take] = entry
                    clears[#clears + 1] = entry
                end
                entry.cats[cat] = true
            end
        end
    end

    local name = VenueTargetName(kind)
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local removed = {}
    for _, c in ipairs(clears) do
        r.MarkTrackItemsDirty(c.track, c.item)
        local c_ppq = r.MIDI_GetPPQPosFromProjTime(c.take, cursor)
        for _, msg in ipairs(DeleteVenueEventsAtPpq(c.take, c_ppq, _spot_tol(c.take), c.cats)) do
            removed[#removed + 1] = msg
        end
    end
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_InsertTextSysexEvt(take, false, false, abs_ppq, 1, text)
    local verb = #removed > 0 and 'Replace' or 'Insert'
    r.Undo_EndBlock2(0, 'RB ' .. verb .. ' VENUE event: ' .. text, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if #removed > 0 then
        S.status = ('Replaced %s with %s at playhead (%s).'):format(
            table.concat(removed, ' + '), text, name)
    else
        S.status = ('Inserted %s at playhead (%s).'):format(text, name)
    end
end

-- ---------------------------------------------------------------------------
-- Blend: re-state the currently-active lighting/postproc preset at the playhead, so
-- RB3 fades into the next one instead of cutting to it. Same anchor Themes gen and
-- Section gen place automatically from lightpreset_blendin / postproc_blendin.

-- Decides what a Blend click should do. `events` is every text event of ONE kind
-- ({ppq=, msg=}), sorted by ppq. Pure, so tests can drive it without a take.
-- Returns either
--   src, prev        - copy src.msg to cur_ppq (prev is nil when src is the only
--                      candidate; it is only ever returned for the report)
--   nil, code, a, b  - refused; code is 'occupied' | 'none' | 'blended'
function ResolveBlendSource(events, cur_ppq, tol)
    tol = tol or 0

    -- An anchor belongs BEFORE the event it blends into; stacking two of a kind on
    -- one tick is never wanted. Checked first, so it wins over the outcomes below.
    for _, ev in ipairs(events) do
        if math.abs(ev.ppq - cur_ppq) <= tol then return nil, 'occupied', ev end
    end

    local last, second_last
    for _, ev in ipairs(events) do
        if ev.ppq < cur_ppq then second_last = last; last = ev end
    end

    if not last then return nil, 'none' end
    -- Two identical adjacent events of a kind ARE a blend anchor (IsBlendAnchor,
    -- venue.lua - the shared rule EmitBlendDuplicates writes and the validator,
    -- keyframes and Preview read back), so a third copy would change nothing.
    if IsBlendAnchor(second_last, last) then
        return nil, 'blended', last, second_last
    end
    return last, second_last
end

-- kind: 'lighting' or 'postproc' (CategorizeVenueEvent's own names).
function BlendVenuePresetAtPlayhead(kind)
    local track, item, take = FindVenueTarget(kind)
    if not track then return end

    local cur_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())
    local label   = (kind == 'postproc') and 'post-process' or 'lighting'

    -- Classify with the shared CategorizeVenueEvent rather than re-deriving the
    -- [lighting / .pp] patterns here (actions_venue_subtracks.lua).
    local events = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, evt_ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and CategorizeVenueEvent(msg) == kind then
            events[#events + 1] = { ppq = evt_ppq, msg = msg }
        end
    end
    table.sort(events, function(a, b) return a.ppq < b.ppq end)

    local function at(ev)
        return FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, ev.ppq))
    end

    local src, prev_or_code, a, b = ResolveBlendSource(events, cur_ppq, _spot_tol(take))

    -- Every refusal returns before any Undo_* call, so it leaves no undo point.
    if not src then
        local lines
        if prev_or_code == 'occupied' then
            S.status = ('%s is already at the playhead - nothing to blend.'):format(a.msg)
            lines = {
                ('Refused: %s already sits at the playhead (%s).'):format(a.msg, at(a)),
                '',
                'A blend anchor goes BEFORE the event it blends into - move the cursor',
                'back a beat or two and try again.',
            }
        elseif prev_or_code == 'none' then
            S.status = ('No %s event before the playhead - nothing to blend from.'):format(label)
            lines = {
                ('Refused: no %s event exists before the playhead.'):format(label),
                '',
                ('Add the %s preset that should be running first, then blend into the'):format(label),
                'one that follows it.',
            }
        else  -- 'blended'
            S.status = ('Already blended - the last two %s events are the same.'):format(label)
            lines = {
                ('Refused: the two most recent %s events before the playhead are'):format(label),
                'identical, which is exactly what a blend anchor looks like. Adding a',
                'third copy would change nothing.',
                '',
                ('  %s   %s   (most recent)'):format(a.msg, at(a)),
                ('  %s   %s'):format(b.msg, at(b)),
            }
        end
        S.last_result = table.concat(lines, '\n')
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    r.MIDI_InsertTextSysexEvt(take, false, false, cur_ppq, 1, src.msg)
    r.Undo_EndBlock2(0, 'RB Blend VENUE ' .. label .. ': ' .. src.msg, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local placed_t = FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, cur_ppq))
    local lines = {
        ('Copied the active %s preset to the playhead as a blend anchor (%s).'):format(
            label, VenueTargetName(kind)),
        '',
        ('  Source:  %s   %s'):format(src.msg, at(src)),
        ('  Placed:  %s   %s'):format(src.msg, placed_t),
        '',
    }
    local prev = prev_or_code
    if prev then
        lines[#lines + 1] = ('The %s before it was %s (%s), so this is a real change'):format(
            label, prev.msg, at(prev))
        lines[#lines + 1] = 'and not an anchor that already exists.'
    else
        lines[#lines + 1] = ('It is the only %s event before the playhead, so there was no'):format(label)
        lines[#lines + 1] = 'existing blend to detect.'
    end
    S.status      = ('Blended: copied %s to the playhead.'):format(src.msg)
    S.last_result = table.concat(lines, '\n')
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
    -- Lighting is read from one take and the keyframes written to another; in VENUE mode
    -- both are the VENUE take. Every position below is in the lighting take's ticks
    -- until the write, which converts through project time.
    local track, item, take = FindVenueTarget('lighting')
    if not track then return end
    local kf_track, kf_item, kf_take = FindVenueTarget('keyframe')
    if not kf_track then return end

    local ppq       = GetTakePPQPerQN(take)
    local half_beat = math.floor(ppq / 2 + 0.5)

    local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())

    -- The keyframe train belongs to the lighting event under the playhead - that event,
    -- not the lighting dropdown, decides whether generation is allowed, so an existing
    -- [lighting (...)] can be re-keyframed without re-picking it above.
    local cur_lt_text = FindManualLightingAtPpq(take, start_ppq)
    if not cur_lt_text then
        S.status = NO_LIGHTING_AT_PLAYHEAD_MSG
        return
    end

    local item_start_sec = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local end_ppq        = r.MIDI_GetPPQPosFromProjTime(take, item_end_sec)

    -- Clamp to time selection if active
    local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if sel_e > sel_s then
        local sel_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
        if sel_end_ppq < end_ppq then end_ppq = sel_end_ppq end
    end

    -- Clamp to next lighting event after cursor. An event restating the preset being
    -- keyframed - a blend-in duplicate ahead of the next section - changes nothing and
    -- must not cut the train short; only a real preset change ends the span.
    local _, _, _, tc = r.MIDI_CountEvts(take)
    local next_lt_ppq = nil
    for i = 0, tc - 1 do
        local ok, _, _, ppq_pos, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and ppq_pos > start_ppq + half_beat
                and msg:find('^%[lighting') and msg ~= cur_lt_text then
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

    -- Same span algorithm the Keyframes tab runs per manual lighting event; the playhead
    -- check above guarantees start_ppq is a lighting event's own tick, which is what
    -- GenerateKeyframesForSpan assumes when it anchors [first] there.
    local ctrl_events = GenerateKeyframesForSpan(take, start_ppq, end_ppq, ppq, S.venue_mg_kf_rate)

    if #ctrl_events == 0 then
        S.status = 'No keyframe positions found in range.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(kf_track, kf_item)

    -- Clear existing keyframe events in range
    ClearVenueKeyframesInRange(kf_take,
        VenuePpqBetween(take, start_ppq, kf_take), VenuePpqBetween(take, end_ppq, kf_take))

    -- Insert new keyframe events at their already-computed alignment grid position (beat,
    -- half-beat, quarter-beat, etc. per S.venue_kf_inst_subdiv for instrument-aware modes) -
    -- no further snapping, or a coarser half-beat re-snap would collapse finer positions.
    for _, ev in ipairs(ctrl_events) do
        r.MIDI_InsertTextSysexEvt(kf_take, false, false,
            VenuePpqBetween(take, ev.ppq, kf_take), 1, ev.text)
    end

    r.Undo_EndBlock2(0, 'RB Generate Manual Keyframes (' .. #ctrl_events .. ' events)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if VenueTargetUsesSubtracks() then
        S.status = ('Generated %d keyframe events (%s).'):format(
            #ctrl_events, VenueTargetName('keyframe'))
    else
        S.status = ('Generated %d keyframe events.'):format(#ctrl_events)
    end
end

-- ---------------------------------------------------------------------------

-- Categories (CategorizeVenueEvent keys) each Remove type covers. "Camera" = coop or
-- directed; "Special" = special (bonusfx + anything unrecognized) or keyframe. "All"
-- lists every category, since the classifier's categories are exhaustive.
local REMOVE_CATEGORIES = {
    [0] = { coop = true, directed = true },
    [1] = { lighting = true },
    [2] = { postproc = true },
    [3] = { special = true, keyframe = true },
    [4] = { coop = true, directed = true, lighting = true, keyframe = true,
            postproc = true, special = true },
}

function RemoveVenueEventsByType(remove_type)
    local cats = REMOVE_CATEGORIES[remove_type] or REMOVE_CATEGORIES[4]

    -- The takes to clear: VENUE alone, or each existing subtrack of a covered category.
    local targets, missing = {}, {}
    if VenueTargetUsesSubtracks() then
        for _, cat in ipairs(VENUE_SUBTRACKS) do
            if cats[cat.key] then
                local track, item, take = FindNamedTrackMIDI(cat.track_name)
                if item then
                    targets[#targets + 1] = { track = track, item = item, take = take }
                else
                    missing[#missing + 1] = cat.track_name
                end
            end
        end
        if #targets == 0 then
            S.status = ('No subtrack found (%s) - %s'):format(
                        table.concat(missing, ', '), SUBTRACKS_FIRST_HINT)
            return
        end
    else
        local track, item, take = FindVenueTarget('special')
        if not track then return end
        targets[1] = { track = track, item = item, take = take }
    end

    local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local has_sel      = sel_e > sel_s

    local function keep(msg) return not cats[CategorizeVenueEvent(msg)] end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local count = 0
    for _, t in ipairs(targets) do
        r.MarkTrackItemsDirty(t.track, t.item)
        local item_start_sec  = r.GetMediaItemInfo_Value(t.item, 'D_POSITION')
        local item_end_sec    = item_start_sec + r.GetMediaItemInfo_Value(t.item, 'D_LENGTH')
        local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(t.take, has_sel and sel_s or item_start_sec)
        local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(t.take, has_sel and sel_e or item_end_sec)
        count = count + DeleteTextEventsInRange(t.take, range_start_ppq, range_end_ppq, keep)
    end

    local type_names = { 'Camera', 'Lighting', 'Post proc', 'Special', 'All' }
    local tname      = type_names[remove_type + 1] or ''
    r.Undo_EndBlock2(0, 'RB Remove VENUE ' .. tname .. ' events (' .. count .. ')', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local scope = has_sel and 'time selection' or 'full song'
    if VenueTargetUsesSubtracks() then
        S.status = ('Removed %d %s events (%s, subtracks).'):format(count, tname, scope)
        if #missing > 0 then
            S.last_result = 'Not found, skipped: ' .. table.concat(missing, ', ')
        end
    else
        S.status = ('Removed %d %s events (%s).'):format(count, tname, scope)
    end
end
