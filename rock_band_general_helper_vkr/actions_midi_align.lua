-- MIDI item alignment: move and optionally stretch a MIDI item to fit a time selection.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem (globals)

function AlignMIDI()
    if S.ma_midi_src_idx < 0 then
        S.status = 'Error: no MIDI source track selected.'
        S.last_result = 'Select the MIDI track to align in the MIDI tab.'
        return
    end
    local src_tr = r.GetTrack(0, S.ma_midi_src_idx)
    if not src_tr then
        S.status = 'Error: selected track no longer exists \xe2\x80\x94 refresh tracks.'
        S.last_result = nil
        return
    end

    local item, take = FindFirstMIDIItem(src_tr)
    if not item then
        S.status = 'Error: no MIDI item found on selected track.'
        S.last_result = 'Create or import a MIDI item on the source track first.'
        return
    end

    local _, notecnt = r.MIDI_CountEvts(take)
    if notecnt == 0 then
        S.status = 'Error: MIDI item has no notes.'
        S.last_result = 'The selected track\'s first MIDI item contains no notes.'
        return
    end

    local first_t, last_t
    for j = 0, notecnt - 1 do
        local ok, _, muted, sppq = r.MIDI_GetNote(take, j)
        if ok and not muted then
            local t = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            if not first_t or t < first_t then first_t = t end
            if not last_t  or t > last_t  then last_t  = t end
        end
    end
    if not first_t then
        S.status = 'No unmuted notes found.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    if not sel_s then
        S.status = 'Error: no time selection.'
        S.last_result = 'Set a time selection to define the target position.\n\n' ..
            'Place the start where the first note should land.\n' ..
            'For Move + Stretch, the end sets where the last note should land.'
        return
    end

    local old_ip   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local old_len  = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local old_rate = r.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')

    local new_ip, new_len, new_rate, mode_str
    local current_span = last_t - first_t
    local target_span  = sel_e - sel_s

    if S.ma_mode == 1 and current_span >= 0.001 and target_span >= 0.001 then
        new_rate = old_rate * current_span / target_span
        new_ip   = sel_s - (first_t - old_ip) * (old_rate / new_rate)
        new_len  = old_len * (old_rate / new_rate)
        mode_str = 'Move + Stretch'
    else
        new_rate = old_rate
        new_ip   = sel_s - (first_t - old_ip)
        new_len  = old_len
        if S.ma_mode == 1 then
            mode_str = 'Move only (span too small to stretch)'
        else
            mode_str = 'Move only'
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', new_rate)
    r.SetMediaItemInfo_Value(item, 'D_POSITION', new_ip)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', new_len)
    r.UpdateItemInProject(item)
    r.Undo_EndBlock2(0, 'Align MIDI', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local delta_ms = (new_ip - old_ip) * 1000
    local lines = {
        ('Mode: %s'):format(mode_str),
        ('Item moved: %+.1f ms'):format(delta_ms),
    }
    if new_rate ~= old_rate then
        lines[#lines + 1] = ('Playback rate: %.4f \xe2\x86\x92 %.4f'):format(old_rate, new_rate)
    end
    S.status = ('MIDI aligned: moved %+.1f ms.'):format(delta_ms)
    S.last_result = table.concat(lines, '\n')
end

-- Set D_LENGTH on every MIDI-at-position-0 item to match the reference item length.
-- Equivalent to dragging the right edge of each item. Notes are not moved.
function ResizeAllMIDI()
    if S.ms_ref_idx < 0 then
        S.status = 'Error: no reference MIDI track selected.'
        S.last_result = 'Select the reference track in the MIDI Length Sync section.'
        return
    end
    local ref_tr = r.GetTrack(0, S.ms_ref_idx)
    if not ref_tr then
        S.status = 'Error: reference track no longer exists \xe2\x80\x94 refresh tracks.'
        S.last_result = nil
        return
    end
    local ref_item = FindFirstMIDIItem(ref_tr)
    if not ref_item then
        S.status = 'Error: reference track has no MIDI item.'
        S.last_result = nil
        return
    end
    local ref_len = r.GetMediaItemInfo_Value(ref_item, 'D_LENGTH')
    local _, ref_name = r.GetTrackName(ref_tr)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local lines   = {}
    local skipped = {}
    local changed = 0
    local shrunk  = 0
    lines[1] = ('Reference: %s  (%.3f s)'):format(ref_name, ref_len)
    lines[2] = ''

    for i = 0, r.CountTracks(0) - 1 do
        if i ~= S.ms_ref_idx then
            local tr = r.GetTrack(0, i)
            local _, name = r.GetTrackName(tr)
            local item, take = FindFirstMIDIItem(tr)
            if item then
                local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                if pos < 0.0001 then
                    local old_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
                    if math.abs(old_len - ref_len) < 0.001 then
                        lines[#lines + 1] = ('  %-30s already matches'):format(name)
                    else
                        -- SetMediaItemInfo_Value('D_LENGTH') leaves the MIDI source at its
                        -- old length, causing the "beyond source" triangles and blocking note
                        -- drawing in the extended area.  Insert a 1-tick dummy note at the new
                        -- end PPQ to force REAPER to extend the source, then immediately delete
                        -- it.  REAPER does not shrink source length on note deletion.
                        if ref_len > old_len then
                            local new_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, pos + ref_len)
                            local dummy_sppq  = math.floor(new_end_ppq) - 1
                            local _, nc_before = r.MIDI_CountEvts(take)
                            r.MIDI_InsertNote(take, false, true, dummy_sppq, dummy_sppq + 1,
                                0, 0, 1, false)
                            local _, nc_after = r.MIDI_CountEvts(take)
                            if nc_after > nc_before then
                                -- Find and delete by exact PPQ rather than relying on sort order,
                                -- so we never accidentally delete a real note.
                                for j = nc_after - 1, 0, -1 do
                                    local ok, _, _, sppq = r.MIDI_GetNote(take, j)
                                    if ok and math.floor(sppq) == dummy_sppq then
                                        r.MIDI_DeleteNote(take, j)
                                        break
                                    end
                                end
                            end
                            r.MarkTrackItemsDirty(tr, item)
                        end
                        r.SetMediaItemInfo_Value(item, 'D_LENGTH', ref_len)
                        r.UpdateItemInProject(item)
                        local dir = ref_len > old_len and 'extended' or 'shrunk'
                        lines[#lines + 1] = ('  %-30s %.3f s \xe2\x86\x92 %.3f s  (%s)'):format(
                            name, old_len, ref_len, dir)
                        changed = changed + 1
                        if ref_len < old_len then shrunk = shrunk + 1 end
                    end
                else
                    skipped[#skipped + 1] = name
                end
            end
        end
    end

    r.Undo_EndBlock2(0, ('Resize all MIDI to reference (%d changed)'):format(changed), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if #skipped > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Skipped \xe2\x80\x94 not at position 0 (%d):'):format(#skipped)
        for _, n in ipairs(skipped) do
            lines[#lines + 1] = '  ' .. n
        end
    end
    if shrunk > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Warning: %d item%s shrunk \xe2\x80\x94 verify no notes are cut off.'):format(
            shrunk, shrunk == 1 and ' was' or 's were')
    end

    S.status = changed > 0
        and ('Resized %d MIDI track%s to %.3f s.'):format(
            changed, changed == 1 and '' or 's', ref_len)
        or  'All MIDI tracks already match reference length.'
    S.last_result = table.concat(lines, '\n')
end
