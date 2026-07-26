-- Splits the VENUE track's text events (plus its interpretive MIDI notes, which land on
-- "VENUE special") into 6 category-specific "subtrack" MIDI tracks for easier authoring (a lot
-- of keyframes make the single VENUE track hard to read), then merges them back. Subtracks are
-- a pure editing convenience with no meaning to the exported song.
-- Requires: FindTrackByName, FindNamedTrackMIDI, DeleteTextEventsInRange,
--           ClearVenueTextEventsInRange, r, S (globals)
-- Globals exported: VENUE_SUBTRACKS, CategorizeVenueEvent, FindOrCreateSubtrack,
--   EnsureMatchingItem, CopyVenueEvents, CopyVenueNotes (logic helpers, global per this
--   repo's testability convention - explicit take/item args, no UI/S reads, so tests can
--   drive them directly), CopyVenueToSubtracks, CopyAllSubtracksToMain,
--   CopySelectedSubtrackTo, CopySelectedSubtrackFrom (public actions)

-- Single source of truth for categorization, subtrack creation order/names, and the Actions
-- tab dropdown's option list.
VENUE_SUBTRACKS = {
    { key = 'coop',     label = 'Normal camera',   track_name = 'VENUE normal camera' },
    { key = 'directed', label = 'Directed camera', track_name = 'VENUE directed camera' },
    { key = 'lighting', label = 'Lighting',        track_name = 'VENUE lighting' },
    { key = 'keyframe', label = 'Keyevents',       track_name = 'VENUE keyevents' },
    { key = 'postproc', label = 'Post proc',       track_name = 'VENUE post proc' },
    { key = 'special',  label = 'Special',         track_name = 'VENUE special' },
}

-- Classifies a type-1 VENUE text event string into one of VENUE_SUBTRACKS' keys.
-- 'special' is the catch-all: bonusfx/bonusfx_optional plus anything unrecognized.
function CategorizeVenueEvent(msg)
    if msg == '[first]' or msg == '[next]' or msg == '[previous]' then return 'keyframe' end
    if msg:find('^%[coop_')     then return 'coop'     end
    if msg:find('^%[directed_') then return 'directed' end
    if msg:find('^%[lighting')  then return 'lighting' end
    if msg:find('%.pp%]$')      then return 'postproc' end
    return 'special'
end

-- ---------------------------------------------------------------------------

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

-- Copies every custom MIDI note name set on src_track over to dst_track
-- (GetTrackMIDINoteNameEx/SetTrackMIDINoteNameEx - track-level note-naming data, independent
-- of any actual MIDI content, e.g. a "Bassist sing"/"Drummer sing"/"Guitarist sing" label on
-- pitches 85-87). Checks both the channel-independent default (chan -1) and all 16 channels
-- for every pitch 0-127, since a name can be set at either scope.
local function CopyTrackMIDINoteNames(src_track, dst_track)
    for pitch = 0, 127 do
        for chan = -1, 15 do
            local name = r.GetTrackMIDINoteNameEx(0, src_track, pitch, chan)
            if name and name ~= '' then
                r.SetTrackMIDINoteNameEx(0, dst_track, pitch, chan, name)
            end
        end
    end
end

-- Finds the subtrack for `cat` by exact name; if missing, creates it directly after
-- anchor_track (using IP_TRACKNUMBER, always fresh - a hand-carried index counter would go
-- stale the moment InsertTrackAtIndex shifts everything after it), names it, mutes it, and
-- copies venue_track's MIDI note names onto it (all only on creation - a deliberately
-- unmuted/renamed subtrack is never stomped on a later sync). Returns the track.
function FindOrCreateSubtrack(cat, anchor_track, venue_track)
    local tr = FindTrackByName(cat.track_name)
    if tr then return tr end
    local insert_idx = r.GetMediaTrackInfo_Value(anchor_track, 'IP_TRACKNUMBER')
    r.InsertTrackAtIndex(insert_idx, true)
    tr = r.GetTrack(0, insert_idx)
    r.GetSetMediaTrackInfo_String(tr, 'P_NAME', cat.track_name, true)
    r.SetMediaTrackInfo_Value(tr, 'B_MUTE', 1)
    CopyTrackMIDINoteNames(venue_track, tr)
    return tr
end

-- Finds track's existing MIDI item (creating one matching ref_item's bounds if none), syncs
-- both D_POSITION and D_LENGTH to ref_item's current values, then clears every existing
-- type-1 event on the take unconditionally - a full-take clear, not scoped to the item's
-- current visible range, since resizing an item only clips what's visible; it doesn't delete
-- events sitting outside the new bounds, so a range-scoped clear would leave stale events
-- that resurface on a later resize. A newly created item also gets its take's P_NAME set to
-- the track's own name (only on creation - a later re-sync never touches it, so a
-- hand-renamed take isn't stomped). REAPER's own MIDI-editor tab/take-list labels come from
-- the take's P_NAME, not from any embedded MIDI meta-event - without this, every subtrack's
-- take shows as a generic "MIDI take", indistinguishable from one another once more than one
-- is open. Returns item, take.
function EnsureMatchingItem(track, ref_item)
    local ref_start = r.GetMediaItemInfo_Value(ref_item, 'D_POSITION')
    local ref_len   = r.GetMediaItemInfo_Value(ref_item, 'D_LENGTH')
    local item
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local it = r.GetTrackMediaItem(track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then item = it; break end
    end
    local is_new = not item
    if item then
        r.SetMediaItemInfo_Value(item, 'D_POSITION', ref_start)
        r.SetMediaItemInfo_Value(item, 'D_LENGTH', ref_len)
    else
        item = r.CreateNewMIDIItemInProj(track, ref_start, ref_start + ref_len, false)
    end
    local take = r.GetActiveTake(item)
    DeleteTextEventsInRange(take, -math.huge, math.huge, nil)
    if is_new then
        local _, track_name = r.GetTrackName(track)
        r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', track_name, true)
    end
    return item, take
end

-- Copies type-1 text events from src_take to dst_take, optionally filtered by
-- filter_fn(msg) -> bool. Bridges each position via project time (never copies raw ppq ticks
-- directly - a freshly-created item's PPQ-per-QN resolution isn't guaranteed to match the
-- source). Events whose bridged position falls outside dst_item's own
-- [D_POSITION, D_POSITION+D_LENGTH) are skipped rather than inserted out-of-bounds (can
-- happen if a subtrack item was independently moved/resized).
-- Returns inserted_count, skipped_count.
function CopyVenueEvents(src_take, dst_take, dst_item, filter_fn)
    local dst_start_sec = r.GetMediaItemInfo_Value(dst_item, 'D_POSITION')
    local dst_end_sec   = dst_start_sec + r.GetMediaItemInfo_Value(dst_item, 'D_LENGTH')
    local dst_start_ppq = r.MIDI_GetPPQPosFromProjTime(dst_take, dst_start_sec)
    local dst_end_ppq   = r.MIDI_GetPPQPosFromProjTime(dst_take, dst_end_sec)

    local inserted, skipped = 0, 0
    local _, _, _, text_count = r.MIDI_CountEvts(src_take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(src_take, i)
        if ok and evtype == 1 and (not filter_fn or filter_fn(msg)) then
            local t_pos   = r.MIDI_GetProjTimeFromPPQPos(src_take, ppq)
            local dst_ppq = r.MIDI_GetPPQPosFromProjTime(dst_take, t_pos)
            if dst_ppq >= dst_start_ppq and dst_ppq < dst_end_ppq then
                r.MIDI_InsertTextSysexEvt(dst_take, false, false, dst_ppq, 1, msg, false)
                inserted = inserted + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return inserted, skipped
end

-- Deletes every MIDI note on take. Iterates in reverse since indices shift after each delete.
local function ClearAllNotes(take)
    local _, note_count = r.MIDI_CountEvts(take)
    for i = note_count - 1, 0, -1 do
        r.MIDI_DeleteNote(take, i)
    end
end

-- Copies MIDI notes from src_take to dst_take, bridging positions via project time (same
-- rationale as CopyVenueEvents). Only ever used between VENUE and "VENUE special" - VENUE is
-- the only VENUE-family track that carries interpretive MIDI notes (e.g. pitches 85-87 for
-- bassist/drummer/guitarist sing cues), so "special" is where they belong alongside its
-- bonusfx/catch-all text events. Skips a note if either bridged endpoint falls outside
-- dst_item's own [D_POSITION, D_POSITION+D_LENGTH). Returns inserted_count, skipped_count.
function CopyVenueNotes(src_take, dst_take, dst_item)
    local dst_start_sec = r.GetMediaItemInfo_Value(dst_item, 'D_POSITION')
    local dst_end_sec   = dst_start_sec + r.GetMediaItemInfo_Value(dst_item, 'D_LENGTH')
    local dst_start_ppq = r.MIDI_GetPPQPosFromProjTime(dst_take, dst_start_sec)
    local dst_end_ppq   = r.MIDI_GetPPQPosFromProjTime(dst_take, dst_end_sec)

    local inserted, skipped = 0, 0
    local _, note_count = r.MIDI_CountEvts(src_take)
    for i = 0, note_count - 1 do
        local ok, sel, mute, sppq, eppq, chan, pitch, vel = r.MIDI_GetNote(src_take, i)
        if ok then
            local s_ppq = r.MIDI_GetPPQPosFromProjTime(dst_take, r.MIDI_GetProjTimeFromPPQPos(src_take, sppq))
            local e_ppq = r.MIDI_GetPPQPosFromProjTime(dst_take, r.MIDI_GetProjTimeFromPPQPos(src_take, eppq))
            if s_ppq >= dst_start_ppq and e_ppq <= dst_end_ppq then
                r.MIDI_InsertNote(dst_take, sel, mute, s_ppq, e_ppq, chan, pitch, vel, false)
                inserted = inserted + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return inserted, skipped
end

-- ---------------------------------------------------------------------------

-- "Copy all to subtracks": creates (if missing) and re-syncs all 6 subtracks, filtering VENUE's
-- events into each by category. Always processes the whole VENUE item - not time-selection
-- scoped, since subtracks always mirror the entire item.
function CopyVenueToSubtracks()
    local venue_track, venue_item, venue_take = _find_venue_track_and_take()
    if not venue_track then return end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local anchor = venue_track
    local counts, skipped_total = {}, 0
    local note_total, note_skipped_total = 0, 0
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        local tr = FindOrCreateSubtrack(cat, anchor, venue_track)
        anchor = tr
        local item, take = EnsureMatchingItem(tr, venue_item)
        r.MarkTrackItemsDirty(tr, item)
        local n, skipped = CopyVenueEvents(venue_take, take, item, function(msg)
            return CategorizeVenueEvent(msg) == cat.key
        end)
        counts[cat.key] = n
        skipped_total   = skipped_total + skipped

        -- VENUE's own interpretive MIDI notes (e.g. pitches 85-87 sing cues) land on
        -- "VENUE special" alongside its other catch-all events - no other category ever
        -- carries notes.
        if cat.key == 'special' then
            ClearAllNotes(take)
            local note_n, note_skipped = CopyVenueNotes(venue_take, take, item)
            note_total         = note_total + note_n
            note_skipped_total = note_skipped_total + note_skipped
        end
    end

    r.Undo_EndBlock2(0, 'RB Copy VENUE to subtracks', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = { 'Copied VENUE events to 6 subtracks:', '' }
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        lines[#lines + 1] = ('  %-16s %d'):format(cat.label, counts[cat.key])
    end
    if note_total > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Notes copied to Special: %d'):format(note_total)
    end
    if skipped_total + note_skipped_total > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('%d event(s) / %d note(s) skipped (would have landed outside a subtrack item).')
                            :format(skipped_total, note_skipped_total)
    end
    S.status      = 'Copied VENUE events to subtracks.'
    S.last_result = table.concat(lines, '\n')
end

-- "Copy all to main track": clears VENUE and replaces it with the combined contents of every
-- existing subtrack (no category filter - a literal merge). force=true skips the
-- already-has-events confirmation gate (used by the popup's "Clear and Copy" and by tests).
function CopyAllSubtracksToMain(force)
    local venue_track, venue_item, venue_take = _find_venue_track_and_take()
    if not venue_track then return end

    local any_exist = false
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        if FindTrackByName(cat.track_name) then any_exist = true; break end
    end
    if not any_exist then
        S.status      = 'No VENUE subtracks found.'
        S.last_result = 'None of the "VENUE ..." subtracks exist yet.\n\n' ..
                        'Run "Copy all to subtracks" (or "Copy to" for a single category) first.'
        return
    end

    if not force then
        local _, _, _, text_count = r.MIDI_CountEvts(venue_take)
        local has_events = false
        for i = 0, text_count - 1 do
            local ok, _, _, _, evtype = r.MIDI_GetTextSysexEvt(venue_take, i)
            if ok and evtype == 1 then has_events = true; break end
        end
        if has_events then
            S.venue_subtrack_copy_pending = {
                message = 'The VENUE track already has events. Clear them and replace with ' ..
                          'the combined contents of the subtracks?',
                on_confirm = function() CopyAllSubtracksToMain(true) end,
            }
            return
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(venue_track, venue_item)

    DeleteTextEventsInRange(venue_take, -math.huge, math.huge, nil)
    ClearAllNotes(venue_take)

    local total, skipped_total, missing = 0, 0, {}
    local note_total, note_skipped_total = 0, 0
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        local _, _, sub_take = FindNamedTrackMIDI(cat.track_name)
        if sub_take then
            local n, skipped = CopyVenueEvents(sub_take, venue_take, venue_item, nil)
            total         = total + n
            skipped_total = skipped_total + skipped
            if cat.key == 'special' then
                local note_n, note_skipped = CopyVenueNotes(sub_take, venue_take, venue_item)
                note_total         = note_total + note_n
                note_skipped_total = note_skipped_total + note_skipped
            end
        else
            missing[#missing + 1] = cat.label
        end
    end

    r.Undo_EndBlock2(0, 'RB Copy VENUE subtracks to main', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = { ('Copied %d event(s) from subtracks into VENUE.'):format(total) }
    if note_total > 0 then
        lines[#lines + 1] = ('Copied %d note(s) from Special into VENUE.'):format(note_total)
    end
    if skipped_total > 0 then
        lines[#lines + 1] = ('%d event(s) skipped (outside VENUE item bounds).'):format(skipped_total)
    end
    if note_skipped_total > 0 then
        lines[#lines + 1] = ('%d note(s) skipped (outside VENUE item bounds).'):format(note_skipped_total)
    end
    if #missing > 0 then
        lines[#lines + 1] = 'Missing subtracks (skipped): ' .. table.concat(missing, ', ')
    end
    S.status      = ('Copied %d events from subtracks into VENUE.'):format(total)
    S.last_result = table.concat(lines, '\n')
end

-- "Copy to" (single, selected subtrack): auto-creates the subtrack if missing.
function CopySelectedSubtrackTo()
    local cat = VENUE_SUBTRACKS[S.venue_subtrack_idx + 1]
    local venue_track, venue_item, venue_take = _find_venue_track_and_take()
    if not venue_track then return end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local tr          = FindOrCreateSubtrack(cat, venue_track, venue_track)
    local item, take  = EnsureMatchingItem(tr, venue_item)
    r.MarkTrackItemsDirty(tr, item)

    local count, skipped = CopyVenueEvents(venue_take, take, item, function(msg)
        return CategorizeVenueEvent(msg) == cat.key
    end)

    local note_count, note_skipped = 0, 0
    if cat.key == 'special' then
        ClearAllNotes(take)
        note_count, note_skipped = CopyVenueNotes(venue_take, take, item)
    end

    r.Undo_EndBlock2(0, 'RB Copy VENUE ' .. cat.label .. ' to subtrack', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local parts = { ('%d %s event(s)'):format(count, cat.label) }
    if note_count > 0 then parts[#parts + 1] = ('%d note(s)'):format(note_count) end
    local msg = ('Copied %s to "%s".'):format(table.concat(parts, ' + '), cat.track_name)
    local total_skipped = skipped + note_skipped
    if total_skipped > 0 then
        msg = msg .. (' (%d skipped)'):format(total_skipped)
    end
    S.status = msg
end

-- "Copy from" (single, selected subtrack): does NOT auto-create - reports a no-op status
-- instead, asymmetric from "Copy to" on purpose. Clears only that category's events from
-- VENUE (not everything) before copying the subtrack's contents in.
function CopySelectedSubtrackFrom()
    local cat = VENUE_SUBTRACKS[S.venue_subtrack_idx + 1]
    local venue_track, venue_item, venue_take = _find_venue_track_and_take()
    if not venue_track then return end

    local _, _, sub_take = FindNamedTrackMIDI(cat.track_name)
    if not sub_take then
        S.status = ('No "%s" subtrack found - use Copy to first.'):format(cat.track_name)
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(venue_track, venue_item)

    local item_start_sec  = r.GetMediaItemInfo_Value(venue_item, 'D_POSITION')
    local item_end_sec    = item_start_sec + r.GetMediaItemInfo_Value(venue_item, 'D_LENGTH')
    local range_start_ppq = r.MIDI_GetPPQPosFromProjTime(venue_take, item_start_sec)
    local range_end_ppq   = r.MIDI_GetPPQPosFromProjTime(venue_take, item_end_sec)
    DeleteTextEventsInRange(venue_take, range_start_ppq, range_end_ppq, function(msg)
        return CategorizeVenueEvent(msg) ~= cat.key   -- keep = not this category
    end)

    local count, skipped = CopyVenueEvents(sub_take, venue_take, venue_item, nil)

    local note_count, note_skipped = 0, 0
    if cat.key == 'special' then
        ClearAllNotes(venue_take)
        note_count, note_skipped = CopyVenueNotes(sub_take, venue_take, venue_item)
    end

    r.Undo_EndBlock2(0, 'RB Copy VENUE subtrack ' .. cat.label .. ' to main', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local parts = { ('%d %s event(s)'):format(count, cat.label) }
    if note_count > 0 then parts[#parts + 1] = ('%d note(s)'):format(note_count) end
    local msg = ('Copied %s from "%s" into VENUE.'):format(table.concat(parts, ' + '), cat.track_name)
    local total_skipped = skipped + note_skipped
    if total_skipped > 0 then
        msg = msg .. (' (%d skipped)'):format(total_skipped)
    end
    S.status = msg
end
