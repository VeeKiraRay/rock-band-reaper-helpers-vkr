-- Snap to Key Scale action

----------------------------------------------------------------------
-- Snap to Key Scale
----------------------------------------------------------------------

-- Returns snapped_pitch (int) and semitone distance (int >= 0).
-- Ties (equidistant up/down) snap downward (lower pitch wins) so that a note
-- "between" two scale degrees consistently rounds to the lower one.
function NearestScalePitch(pitch, root, quality)
    local scale = quality == 1 and HARM_SCALE.minor or HARM_SCALE.major
    local pc = pitch % 12
    local best_pitch, best_dist = pitch, 999
    for _, interval in ipairs(scale) do
        local spc = (root + interval) % 12
        local up   = (spc - pc + 12) % 12
        local down = (pc - spc + 12) % 12
        local dist, offset = (up < down) and up or down, (up < down) and up or -down
        local candidate = pitch + offset
        if dist < best_dist or (dist == best_dist and candidate < best_pitch) then
            best_dist, best_pitch = dist, candidate
        end
    end
    return best_pitch, best_dist
end

-- Returns the next-best scale pitch, excluding the given pitch class.
-- Used by the collision-avoidance post-pass.
local function NextScalePitch(pitch, root, quality, exclude_pc)
    local scale = quality == 1 and HARM_SCALE.minor or HARM_SCALE.major
    local pc = pitch % 12
    local best_pitch, best_dist = pitch, 999
    for _, interval in ipairs(scale) do
        local spc = (root + interval) % 12
        if spc ~= exclude_pc then
            local up   = (spc - pc + 12) % 12
            local down = (pc - spc + 12) % 12
            local dist, offset = (up < down) and up or down, (up < down) and up or -down
            local candidate = pitch + offset
            if dist < best_dist or (dist == best_dist and candidate < best_pitch) then
                best_dist, best_pitch = dist, candidate
            end
        end
    end
    return best_pitch, best_dist
end

function SnapToKeyAction()
    local tracks = GetTrackList()
    if #tracks == 0 or S.midi_idx >= #tracks then
        S.status = 'Error'; S.last_result = 'Invalid MIDI destination track.'; return
    end
    local midi_track = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local midi_item, midi_take = FindFirstMIDIItem(midi_track)
    if not midi_take then
        S.status = 'Error'
        S.last_result = 'No MIDI item found on the destination track.'
        return
    end

    local ts, te = GetTimeSelection()
    local range_start, range_end, has_sel
    if ts then
        range_start, range_end, has_sel = ts, te, true
    else
        range_start = r.GetMediaItemInfo_Value(midi_item, 'D_POSITION')
        range_end   = range_start + r.GetMediaItemInfo_Value(midi_item, 'D_LENGTH')
        has_sel = false
    end

    local root    = S.snap_key_root
    local quality = S.snap_key_quality

    local _, n_notes, _, n_text = r.MIDI_CountEvts(midi_take)

    local lyric_at = {}
    for i = 0, n_text - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 and not LYRIC_IGNORE[msg] then lyric_at[ppq] = msg end
    end

    -- Read phrase marker times (whole take) for collision-avoidance boundary check
    local marker_times = {}
    local notes = {}
    for i = 0, n_notes - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(midi_take, i)
        if ok then
            if p == RB3_PHRASE_PITCH then
                marker_times[#marker_times + 1] = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            elseif p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
                if s_t >= range_start - 0.001 and s_t < range_end + 0.001 then
                    notes[#notes + 1] = {
                        s = s_t, e = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq),
                        pitch = p, vel = vel, sel = sel, mute = mute, chan = chan,
                        lyric = lyric_at[sppq],
                    }
                end
            end
        end
    end
    table.sort(marker_times)

    if #notes == 0 then
        S.status = 'No notes in range.'
        S.last_result = ('Range: %s - %s%s\nNo vocal notes found.'):format(
            FormatTime(range_start), FormatTime(range_end),
            has_sel and ' [time selection]' or ' [whole MIDI item]')
        return
    end

    local snapped = {}
    local moved, max_move = 0, 0
    for _, n in ipairs(notes) do
        local new_pitch, dist = NearestScalePitch(n.pitch, root, quality)
        while new_pitch < RB3_MIN_PITCH do new_pitch = new_pitch + 12 end
        while new_pitch > RB3_MAX_PITCH do new_pitch = new_pitch - 12 end
        if new_pitch ~= n.pitch then moved = moved + 1 end
        if dist > max_move then max_move = dist end
        snapped[#snapped + 1] = {
            s = n.s, e = n.e, pitch = new_pitch,
            vel = n.vel, sel = n.sel, mute = n.mute, chan = n.chan,
            lyric = n.lyric,
        }
    end

    -- Phrase-aware collision avoidance: if two adjacent same-phrase notes snap to
    -- the same pitch but were originally different, redirect whichever note moved
    -- more to the next closest scale degree (adjusting the note that caused the
    -- collision rather than always blindly adjusting the later one).
    local collisions_fixed = 0
    if S.snap_avoid_collision then
        local displacements = {}
        for i = 1, #snapped do
            displacements[i] = math.abs(snapped[i].pitch - notes[i].pitch)
        end
        local function cross_phrase_boundary(i)
            local t_a, t_b = notes[i - 1].s, notes[i].s
            for _, mt in ipairs(marker_times) do
                if mt > t_a and mt <= t_b then return true end
            end
            return false
        end
        for i = 2, #snapped do
            if not cross_phrase_boundary(i)
            and snapped[i].pitch == snapped[i - 1].pitch
            and notes[i].pitch   ~= notes[i - 1].pitch then
                -- Adjust whichever note moved more; use i on a tie.
                local adj = (displacements[i] >= displacements[i - 1]) and i or (i - 1)
                local alt = NextScalePitch(notes[adj].pitch, root, quality, snapped[adj].pitch % 12)
                while alt < RB3_MIN_PITCH do alt = alt + 12 end
                while alt > RB3_MAX_PITCH do alt = alt - 12 end
                if alt ~= snapped[adj].pitch then
                    snapped[adj].pitch = alt
                    displacements[adj] = math.abs(alt - notes[adj].pitch)
                    collisions_fixed = collisions_fixed + 1
                end
            end
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(midi_track, midi_item)
    ClearNotesInRange(midi_take, range_start, range_end, RB3_MIN_PITCH, RB3_MAX_PITCH)
    -- Only remove lyric events that are attached to notes being reinserted.
    -- Orphaned lyrics (no corresponding note at that PPQ) are left untouched.
    local note_ppqs = {}
    for _, n in ipairs(snapped) do
        note_ppqs[r.MIDI_GetPPQPosFromProjTime(midi_take, n.s)] = true
    end
    local _, _, _, n_text = r.MIDI_CountEvts(midi_take)
    for i = n_text - 1, 0, -1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 and not LYRIC_IGNORE[msg] and note_ppqs[ppq] then
            r.MIDI_DeleteTextSysexEvt(midi_take, i)
        end
    end
    for _, n in ipairs(snapped) do
        local sppq = r.MIDI_GetPPQPosFromProjTime(midi_take, n.s)
        local eppq = r.MIDI_GetPPQPosFromProjTime(midi_take, n.e)
        r.MIDI_InsertNote(midi_take, n.sel, n.mute, sppq, eppq, n.chan, n.pitch, n.vel, false)
        if n.lyric then
            r.MIDI_InsertTextSysexEvt(midi_take, false, false, sppq, 5, n.lyric)
        end
    end
    r.Undo_EndBlock2(0,
        ('Vocal Helper VKR: Snap to key - %d note%s moved')
            :format(moved, moved == 1 and '' or 's'), -1)
    r.PreventUIRefresh(-1)

    local key_name = HARM_NOTE_NAMES[root + 1] .. (quality == 1 and ' minor' or ' major')
    local lines = {
        ('Snap to key: %s'):format(key_name),
        ('Range: %s - %s%s'):format(
            FormatTime(range_start), FormatTime(range_end),
            has_sel and ' [time selection]' or ' [whole MIDI item]'),
        ('Notes: %d total, %d snapped, %d already in key')
            :format(#notes, moved, #notes - moved),
        ('Max move: %d semitone%s'):format(max_move, max_move == 1 and '' or 's'),
    }
    if S.snap_avoid_collision and collisions_fixed > 0 then
        lines[#lines + 1] = ('Collision avoidance: %d note%s redirected to next scale degree')
            :format(collisions_fixed, collisions_fixed == 1 and '' or 's')
    end
    S.status = ('Snap to key: %d note%s snapped.'):format(moved, moved == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end
