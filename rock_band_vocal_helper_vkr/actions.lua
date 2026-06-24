-- Action functions (Preview, Generate, Auto-tune, Apply pitch, Draft Snap)
-- ScanPitchSlidesAction → actions_slides.lua
-- SnapToKeyAction        → actions_snap_key.lua

----------------------------------------------------------------------
-- Track resolution helpers (local - only called within this file)
----------------------------------------------------------------------
local function ResolveTracks()
    local tracks = GetTrackList()
    if #tracks == 0 then return nil, 'No tracks in project.' end
    if S.audio_idx >= #tracks or S.midi_idx >= #tracks then
        return nil, 'Track selection out of range.'
    end
    if S.audio_idx == S.midi_idx then
        return nil, 'Pick different tracks for audio and MIDI.'
    end
    local atr = r.GetTrack(0, tracks[S.audio_idx + 1].idx)
    local mtr = r.GetTrack(0, tracks[S.midi_idx  + 1].idx)
    local rtr
    if S.pitch_mode == MODE_REFERENCE then
        if S.ref_idx >= #tracks then
            return nil, 'Reference MIDI track index out of range.'
        end
        if S.ref_idx == S.audio_idx or S.ref_idx == S.midi_idx then
            return nil, 'Reference MIDI track must be different from audio and destination tracks.'
        end
        rtr = r.GetTrack(0, tracks[S.ref_idx + 1].idx)
    end
    return { audio = atr, midi = mtr, ref = rtr }
end

-- For Apply Pitch Changes: audio track only required when mode is MODE_YIN.
local function ResolveApplyPitchTracks()
    local tracks = GetTrackList()
    if #tracks == 0 then return nil, 'No tracks in project.' end
    if S.midi_idx >= #tracks then
        return nil, 'Destination track index out of range.'
    end
    local mtr = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local rtr, atr
    if S.pitch_mode == MODE_REFERENCE then
        if S.ref_idx >= #tracks then
            return nil, 'Reference MIDI track index out of range.'
        end
        if S.ref_idx == S.midi_idx then
            return nil, 'Reference MIDI track must be different from the destination track.'
        end
        rtr = r.GetTrack(0, tracks[S.ref_idx + 1].idx)
    elseif S.pitch_mode == MODE_YIN then
        if S.audio_idx >= #tracks then
            return nil, 'Audio track index out of range.'
        end
        if S.audio_idx == S.midi_idx then
            return nil, 'Pick different tracks for audio and MIDI.'
        end
        atr = r.GetTrack(0, tracks[S.audio_idx + 1].idx)
    end
    return { midi = mtr, ref = rtr, audio = atr }
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
function Preview()
    local trks, terr = ResolveTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local range_info, rerr = ResolveAnalysisRange(trks.audio)
    if not range_info then
        S.status = 'Error'; S.last_result = rerr; return
    end

    local res, err = RunDetection(range_info)
    if not res then S.status = 'Error'; S.last_result = err; return end

    if S.snap_enabled then
        res.notes = SnapOnsets(res.notes, res.contour_info, S.snap_window_ms)
    end

    local with_pitch, ps_or_err = AssignPitches(res.notes, trks.ref, range_info.item, MODE_SINGLE)
    if not with_pitch then
        S.status = 'Error'; S.last_result = ps_or_err; return
    end

    S.status = 'Preview complete.'
    S.last_result = FormatResult(res, 'Preview', nil, ps_or_err)
end

function Generate(replace)
    local trks, terr = ResolveTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local range_info, rerr = ResolveAnalysisRange(trks.audio)
    if not range_info then
        S.status = 'Error'; S.last_result = rerr; return
    end

    local midi_item, midi_take = FindMIDIItem(trks.midi, range_info.range_start, range_info.range_end)
    local clamp_warning = nil

    if not midi_take then
        -- Full coverage not found; accept any overlapping MIDI item and clamp the range.
        for i = 0, r.CountTrackMediaItems(trks.midi) - 1 do
            local it   = r.GetTrackMediaItem(trks.midi, i)
            local take = r.GetActiveTake(it)
            if take and r.TakeIsMIDI(take) then
                local pos  = r.GetMediaItemInfo_Value(it, 'D_POSITION')
                local iend = pos + r.GetMediaItemInfo_Value(it, 'D_LENGTH')
                if pos < range_info.range_end and iend > range_info.range_start then
                    local orig_start = range_info.range_start
                    local orig_end   = range_info.range_end
                    range_info.range_start = math.max(range_info.range_start, pos)
                    range_info.range_end   = math.min(range_info.range_end,   iend)
                    local trimmed_start = range_info.range_start - orig_start
                    local trimmed_end   = orig_end - range_info.range_end
                    local parts = {}
                    if trimmed_end   > 0.001 then parts[#parts+1] = ('%.2fs trimmed from end'):format(trimmed_end) end
                    if trimmed_start > 0.001 then parts[#parts+1] = ('%.2fs trimmed from start'):format(trimmed_start) end
                    clamp_warning = 'Note: audio range clamped to MIDI item bounds (' ..
                        table.concat(parts, ', ') .. ').\n' ..
                        ('Audio: %s - %s   MIDI item: %s - %s')
                            :format(FormatTime(orig_start), FormatTime(orig_end),
                                    FormatTime(pos),        FormatTime(iend))
                    midi_item = it
                    midi_take = take
                    break
                end
            end
        end
    end

    if not midi_take then
        S.status = 'Error'
        S.last_result =
            'No MIDI item on the destination track overlaps the analysis range.\n' ..
            'Create a MIDI item on that track to span the range.'
        return
    end

    local res, err = RunDetection(range_info)
    if not res then S.status = 'Error'; S.last_result = err; return end

    if S.snap_enabled then
        res.notes = SnapOnsets(res.notes, res.contour_info, S.snap_window_ms)
    end

    local with_pitch, ps_or_err = AssignPitches(res.notes, trks.ref, range_info.item, MODE_SINGLE)
    if not with_pitch then S.status = 'Error'; S.last_result = ps_or_err; return end

    local cleared
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(trks.midi, midi_item)
    if replace then
        cleared = ClearNotesInRange(midi_take,
            range_info.range_start, range_info.range_end, RB3_MIN_PITCH, RB3_MAX_PITCH)
    else
        local pitch_set = { [S.pitch] = true }
        for _, n in ipairs(with_pitch) do pitch_set[n.pitch] = true end
        cleared = ClearNotesAtPitchesInRange(midi_take, pitch_set,
            range_info.range_start, range_info.range_end)
    end
    InsertNotes(midi_take, with_pitch, S.velocity)
    local verb = replace and 'replaced' or 'appended'
    r.Undo_EndBlock2(0,
        ('Vocal Helper: cleared %d, %s %d'):format(cleared, verb, #with_pitch), -1)
    r.PreventUIRefresh(-1)

    local action = replace and 'Replaced' or 'Appended'
    S.status = 'Done.'
    S.last_result = FormatResult(res, action, cleared, ps_or_err)
    if clamp_warning then
        S.last_result = S.last_result .. '\n\n' .. clamp_warning
    end
end

function RunAutoTune()
    local trks, terr = ResolveTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    if not GetTimeSelection() then
        S.status = 'Error'
        S.last_result = 'Auto-tune requires a time selection covering the reference notes.'
        return
    end

    local range_info, rerr = ResolveAnalysisRange(trks.audio)
    if not range_info then
        S.status = 'Error'; S.last_result = rerr; return
    end

    local _, midi_take = FindMIDIItem(trks.midi, range_info.range_start, range_info.range_end)
    if not midi_take then
        S.status = 'Error'
        S.last_result =
            'No MIDI item on the destination track covers the analysis range.\n' ..
            'Create or extend a MIDI item on that track and place reference notes inside.'
        return
    end

    S.status = 'Auto-tuning... (UI may freeze briefly)'
    local t0 = r.time_precise()
    local result, err = AutoTune(range_info, midi_take)
    local elapsed = r.time_precise() - t0

    if not result then S.status = 'Error'; S.last_result = err; return end

    ApplyAutoTuneResult(result)
    S.status = ('Auto-tune complete in %.1fs.'):format(elapsed)
    S.last_result = FormatAutoTuneResult(result)
end

function RunAutoTuneYIN()
    if not GetTimeSelection() then
        S.status = 'Error'
        S.last_result = 'YIN auto-tune requires a time selection covering your corrected reference notes.'
        return
    end

    local trks, terr = ResolveApplyPitchTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local target, perr = ResolveApplyPitchTarget(trks.midi)
    if not target then S.status = 'Error'; S.last_result = perr; return end

    local audio_item
    for i = 0, r.CountTrackMediaItems(trks.audio) - 1 do
        local it   = r.GetTrackMediaItem(trks.audio, i)
        local take = r.GetActiveTake(it)
        if take and not r.TakeIsMIDI(take) then
            local pos = r.GetMediaItemInfo_Value(it, 'D_POSITION')
            local len = r.GetMediaItemInfo_Value(it, 'D_LENGTH')
            if pos < target.range_end and pos + len > target.range_start then
                audio_item = it
                break
            end
        end
    end
    if not audio_item then
        S.status = 'Error'
        S.last_result = 'No audio item on the source track overlaps the time selection.'
        return
    end

    local ref_notes = {}
    local _, n_notes = r.MIDI_CountEvts(target.take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(target.take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(target.take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(target.take, eppq)
            if s_t >= target.range_start - 0.001 and s_t < target.range_end + 0.001 then
                ref_notes[#ref_notes + 1] = { s = s_t, e = e_t, pitch = p }
            end
        end
    end

    if #ref_notes == 0 then
        S.status = 'Error'
        S.last_result =
            'No notes in the time selection.\n' ..
            'Place corrected notes on the destination MIDI item first, then run YIN auto-tune.'
        return
    end

    S.status = ('YIN auto-tuning against %d reference notes\xe2\x80\xa6 (UI may freeze briefly)')
        :format(#ref_notes)
    local t0 = r.time_precise()
    local result, err = AutoTuneYIN(audio_item, ref_notes)
    local elapsed = r.time_precise() - t0

    if not result then S.status = 'Error'; S.last_result = err; return end

    S.yin_threshold = result.params.yin_threshold
    S.yin_min_freq  = result.params.yin_min_hz
    S.yin_max_freq  = result.params.yin_max_hz
    S.yin_window_ms = result.params.yin_window_ms

    S.status = ('YIN auto-tune complete in %.1fs.'):format(elapsed)
    S.last_result = FormatAutoTuneYINResult(result)
end

----------------------------------------------------------------------
-- Apply pitch changes: reassign pitches of existing notes without
-- altering their position or length.
----------------------------------------------------------------------
function ApplyPitchChangesAction()
    if S.pitch_mode == MODE_SINGLE then
        S.status = 'Error'
        S.last_result =
            'Apply pitch changes requires Pitch source to be Reference MIDI or Built-in detection.\n' ..
            'In Single pitch mode, this would just set every note to the Default pitch.'
        return
    end

    local trks, terr = ResolveApplyPitchTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local target, perr = ResolveApplyPitchTarget(trks.midi)
    if not target then S.status = 'Error'; S.last_result = perr; return end

    -- For YIN: find an audio item on the source track that overlaps the range.
    local audio_item_for_yin
    if S.pitch_mode == MODE_YIN then
        for i = 0, r.CountTrackMediaItems(trks.audio) - 1 do
            local item = r.GetTrackMediaItem(trks.audio, i)
            local take = r.GetActiveTake(item)
            if take and not r.TakeIsMIDI(take) then
                local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
                if pos < target.range_end and pos + len > target.range_start then
                    audio_item_for_yin = item
                    break
                end
            end
        end
        if not audio_item_for_yin then
            S.status = 'Error'
            S.last_result = 'No audio item on the source track overlaps the target range.'
            return
        end
    end

    -- Read existing notes within range, preserving everything we'll need
    -- to reinsert them with a new pitch.
    local existing = {}
    local _, n_notes = r.MIDI_CountEvts(target.take)
    for i = 0, n_notes - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(target.take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(target.take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(target.take, eppq)
            -- Process notes whose start falls in range. Avoids edge cases
            -- where a long note that just barely overlaps would also get
            -- updated even though the user probably didn't intend it.
            if s_t >= target.range_start - 0.001 and s_t < target.range_end + 0.001
            and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                existing[#existing + 1] = {
                    idx = i, s = s_t, e = e_t,
                    sppq = sppq, eppq = eppq,
                    sel = sel, mute = mute, chan = chan, vel = vel,
                    old_pitch = p,
                }
            end
        end
    end

    if #existing == 0 then
        S.status = 'No notes in range.'
        S.last_result = ('Range: %s - %s%s\nNothing to update.'):format(
            FormatTime(target.range_start), FormatTime(target.range_end),
            target.has_selection and ' [time selection]' or ' [whole MIDI item]')
        return
    end

    -- Reuse AssignPitches by feeding it just the timing fields.
    local input_notes = {}
    for _, n in ipairs(existing) do
        input_notes[#input_notes + 1] = { s = n.s, e = n.e }
    end

    local with_pitch, ps_or_err = AssignPitches(input_notes, trks.ref, audio_item_for_yin)
    if not with_pitch then S.status = 'Error'; S.last_result = ps_or_err; return end

    -- Collect only notes whose pitch actually changes.
    local changes = {}
    for i, n in ipairs(existing) do
        local new_pitch = with_pitch[i].pitch
        if new_pitch ~= n.old_pitch then
            changes[#changes + 1] = { n = n, new_pitch = new_pitch }
        end
    end
    local changed = #changes

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(r.GetMediaItemTake_Track(target.take), r.GetMediaItemTake_Item(target.take))
    if changed > 0 then
        -- Delete in descending index order so earlier indices stay valid.
        table.sort(changes, function(a, b) return a.n.idx > b.n.idx end)
        for _, ch in ipairs(changes) do
            r.MIDI_DeleteNote(target.take, ch.n.idx)
        end
        -- Reinsert with new pitch; PPQ positions are still valid.
        for _, ch in ipairs(changes) do
            r.MIDI_InsertNote(target.take, ch.n.sel, ch.n.mute,
                ch.n.sppq, ch.n.eppq, ch.n.chan, ch.new_pitch, ch.n.vel, false)
        end
    end
    r.Undo_EndBlock2(0,
        ('Vocal Helper: reassigned pitch of %d/%d notes'):format(changed, #existing), -1)
    r.PreventUIRefresh(-1)

    -- Build result panel
    local lines = {
        ('Apply pitch changes: %d notes processed, %d pitches changed')
            :format(#existing, changed),
        ('Range: %s - %s  (%.3fs)%s'):format(
            FormatTime(target.range_start), FormatTime(target.range_end),
            target.range_end - target.range_start,
            target.has_selection and ' [time selection]' or ' [whole MIDI item]'),
    }
    if S.pitch_mode == MODE_REFERENCE then
        lines[#lines + 1] = ('Pitch source: Reference  ->  matched %d, fallback to default %d')
            :format(ps_or_err.ref_used, ps_or_err.ref_fallback)
    elseif S.pitch_mode == MODE_YIN then
        lines[#lines + 1] = ('Pitch source: Built-in  ->  detected %d, fallback to default %d')
            :format(ps_or_err.ref_used, ps_or_err.ref_fallback)
    end
    if ps_or_err.range_adjusted and ps_or_err.range_adjusted > 0 then
        lines[#lines + 1] = ('Pitch range adjusted: %d notes octave-shifted or clamped')
            :format(ps_or_err.range_adjusted)
    end

    S.status = 'Pitches applied.'
    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Draft snap: read existing notes from MIDI destination, snap their
-- boundaries to the nearest energy onset/offset, assign pitches.
----------------------------------------------------------------------
function SnapDraft()
    local trks, terr = ResolveTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local range_info, rerr = ResolveAnalysisRange(trks.audio)
    if not range_info then
        S.status = 'Error'; S.last_result = rerr; return
    end

    local midi_target, merr = ResolveApplyPitchTarget(trks.midi)
    if not midi_target then
        S.status = 'Error'; S.last_result = merr; return
    end

    -- Read draft notes (vocal range only), preserving pitch and velocity
    local draft = {}
    local _, n_notes = r.MIDI_CountEvts(midi_target.take)
    for i = 0, n_notes - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(midi_target.take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_target.take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_target.take, eppq)
            if s_t >= midi_target.range_start - 0.001 and s_t < midi_target.range_end + 0.001 then
                draft[#draft + 1] = {
                    s = s_t, e = e_t,
                    pitch = p, vel = vel, sel = sel, mute = mute, chan = chan,
                }
            end
        end
    end

    if #draft == 0 then
        S.status = 'No notes to snap.'
        S.last_result =
            'No vocal notes found in range on the destination MIDI item.\n' ..
            'Draw rough notes first, then click Snap draft notes.'
        return
    end

    local contour_info, cerr = ComputeRMSContour(
        range_info.item, range_info.range_start, range_info.range_end,
        S.window_ms / 1000, S.lpf_cutoff_hz)
    if not contour_info then
        S.status = 'Error'; S.last_result = cerr; return
    end

    -- Snap boundaries; pitch and velocity come from the draft notes unchanged
    local snapped_boundaries = SnapOnsets(draft, contour_info, S.draft_snap_window_ms)
    local snapped = {}
    for i, n in ipairs(draft) do
        snapped[#snapped + 1] = {
            s     = snapped_boundaries[i].s,
            e     = snapped_boundaries[i].e,
            pitch = n.pitch,
            vel   = n.vel,
            sel   = n.sel,
            mute  = n.mute,
            chan  = n.chan,
        }
    end

    local cleared
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(trks.midi, midi_target.item)
    cleared = ClearNotesInRange(midi_target.take,
        midi_target.range_start, midi_target.range_end, RB3_MIN_PITCH, RB3_MAX_PITCH)
    for _, n in ipairs(snapped) do
        local sppq = r.MIDI_GetPPQPosFromProjTime(midi_target.take, n.s)
        local eppq = r.MIDI_GetPPQPosFromProjTime(midi_target.take, n.e)
        r.MIDI_InsertNote(midi_target.take, n.sel, n.mute, sppq, eppq, n.chan, n.pitch, n.vel, false)
    end
    r.Undo_EndBlock2(0,
        ('Vocal Helper: snap draft notes (%d)'):format(#snapped), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Snap draft: %d notes.'):format(#snapped)
    S.last_result = table.concat({
        ('Snap draft notes: %d in, %d out'):format(#draft, #snapped),
        ('Range: %s \xe2\x80\x94 %s%s'):format(
            FormatTime(midi_target.range_start), FormatTime(midi_target.range_end),
            midi_target.has_selection and ' [time selection]' or ' [whole MIDI item]'),
    }, '\n')
end
