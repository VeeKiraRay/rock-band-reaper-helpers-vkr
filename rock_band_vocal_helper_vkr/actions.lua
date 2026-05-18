-- Action functions (Preview, Generate, Auto-tune, Apply pitch, Slide scan, Snap to Key)

----------------------------------------------------------------------
-- Track resolution helpers (local — only called within this file)
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
                        ('Audio: %s — %s   MIDI item: %s — %s')
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

    local with_pitch, ps_or_err = AssignPitches(res.notes, trks.ref, range_info.item, MODE_SINGLE)
    if not with_pitch then S.status = 'Error'; S.last_result = ps_or_err; return end

    local cleared
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(trks.midi, midi_item)
    if replace then
        cleared = ClearAllNotesInRange(midi_take,
            range_info.range_start, range_info.range_end)
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
        S.last_result = ('Range: %s — %s%s\nNothing to update.'):format(
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
        ('Range: %s — %s  (%.3fs)%s'):format(
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
-- Pitch slide scan
----------------------------------------------------------------------
-- Classify the shape of a pitch trajectory from a list of pitch segments.
-- segs: list of {pc, median_midi, ...}, 2 or more entries, adjacent entries
-- always have different pitch classes (guaranteed by the merge step).
-- Returns one of: 'Slide up', 'Slide down', 'Scoop', 'Bend', 'Complex slide'.
local function ClassifySlide(segs)
    local dirs = {}
    for i = 2, #segs do
        local diff = segs[i].median_midi - segs[i - 1].median_midi
        dirs[#dirs + 1] = diff > 0 and 1 or -1
    end

    local all_up, all_down = true, true
    for _, d in ipairs(dirs) do
        if d < 0 then all_up   = false end
        if d > 0 then all_down = false end
    end
    if all_up   then return 'Slide up'   end
    if all_down then return 'Slide down' end

    local first, last = dirs[1], dirs[#dirs]
    if first < 0 and last > 0 then return 'Scoop' end
    if first > 0 and last < 0 then return 'Bend'  end
    return 'Complex slide'
end

function ScanPitchSlidesAction()
    local tracks = GetTrackList()
    if #tracks == 0 then S.status = 'No tracks in project.'; S.last_result = nil; return end
    if S.audio_idx >= #tracks or S.midi_idx >= #tracks then
        S.status = 'Track selection out of range.'; S.last_result = nil; return
    end

    local audio_track = r.GetTrack(0, tracks[S.audio_idx + 1].idx)
    local midi_track  = r.GetTrack(0, tracks[S.midi_idx  + 1].idx)

    -- Find first audio item on the source track
    local audio_item
    for i = 0, r.CountTrackMediaItems(audio_track) - 1 do
        local item = r.GetTrackMediaItem(audio_track, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then audio_item = item; break end
    end
    if not audio_item then
        S.status = 'Error'
        S.last_result = 'No audio item found on the source track.'
        return
    end

    -- Find MIDI item and establish scan range (respects time selection)
    local sel_start, sel_end = GetTimeSelection()

    if not sel_start then
        local proceed = r.ShowMessageBox(
            'No time selection is active.\n\n' ..
            'Scan pitch slides will process the entire destination MIDI item.\n' ..
            'On a full song this can take 20 seconds or more, and the UI\n' ..
            'will be unresponsive until the scan completes.\n\n' ..
            'Save your project first in case of an unexpected crash.\n\n' ..
            'Press OK to continue, or Cancel to set a time selection first.',
            'Scan pitch slides — no time selection', 1)
        if proceed ~= 1 then return end
    end

    local midi_item, midi_take, range_start, range_end, has_sel

    if sel_start then
        for i = 0, r.CountTrackMediaItems(midi_track) - 1 do
            local item = r.GetTrackMediaItem(midi_track, i)
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
                if pos < sel_end and pos + len > sel_start then
                    midi_item = item; midi_take = take
                    range_start = sel_start; range_end = sel_end
                    has_sel = true; break
                end
            end
        end
    end
    if not midi_item then
        midi_item, midi_take = FindFirstMIDIItem(midi_track)
        if not midi_item then
            S.status = 'Error'
            S.last_result = 'No MIDI item found on the destination track.'
            return
        end
        range_start = r.GetMediaItemInfo_Value(midi_item, 'D_POSITION')
        range_end   = range_start + r.GetMediaItemInfo_Value(midi_item, 'D_LENGTH')
        has_sel = false
    end

    -- Build PPQ -> lyric lookup from type-5 text events
    local lyric_at = {}
    local _, _, _, n_text = r.MIDI_CountEvts(midi_take)
    for i = 0, n_text - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 then lyric_at[ppq] = msg end
    end

    -- Read notes in range (RB3 vocal pitch range only)
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    local notes = {}
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, pitch = r.MIDI_GetNote(midi_take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if s_t >= range_start - 0.001 and s_t < range_end + 0.001
            and pitch >= RB3_MIN_PITCH and pitch <= RB3_MAX_PITCH then
                notes[#notes + 1] = {
                    s = s_t, e = e_t, pitch = pitch, lyric = lyric_at[sppq],
                }
            end
        end
    end

    if #notes == 0 then
        S.status = 'No notes in range.'
        S.last_result = ('Range: %s - %s%s\nNo notes to scan.'):format(
            FormatTime(range_start), FormatTime(range_end),
            has_sel and ' [time selection]' or ' [whole MIDI item]')
        return
    end

    local yctx, yerr = OpenYINContext(audio_item)
    if not yctx then S.status = 'Error'; S.last_result = yerr; return end

    local slide_results = {}
    local n_scanned, n_too_short, n_stable = 0, 0, 0

    for _, note in ipairs(notes) do
        local dur = note.e - note.s
        if dur < S.slide_min_note_ms * 0.001 then
            n_too_short = n_too_short + 1
        else
            n_scanned = n_scanned + 1
            local slide_win_s  = S.slide_win_ms  * 0.001
            local slide_step_s = S.slide_step_ms * 0.001
            local slide_skip_s = S.slide_skip_ms * 0.001

            -- Collect YIN samples every slide_step_s, skipping note edges
            local scan_s = note.s + slide_skip_s
            local scan_e = note.e - slide_skip_s
            local raw = {}
            local t = scan_s
            while t + slide_win_s <= scan_e do
                local p = SampleYINAt(yctx, t, slide_win_s)
                raw[#raw + 1] = {
                    t = t, midi = p, pc = p and (p % 12) or nil,
                }
                t = t + slide_step_s
            end

            -- Group consecutive valid samples by pitch class
            local segs = {}
            local cur
            for _, sp in ipairs(raw) do
                if sp.pc then
                    if not cur or cur.pc ~= sp.pc then
                        cur = {
                            pc = sp.pc, midi_list = { sp.midi },
                            t_start = sp.t, t_end = sp.t + slide_win_s,
                        }
                        segs[#segs + 1] = cur
                    else
                        cur.midi_list[#cur.midi_list + 1] = sp.midi
                        cur.t_end = sp.t + slide_win_s
                    end
                else
                    cur = nil  -- gap resets the current segment
                end
            end

            -- Compute median MIDI note and duration per segment
            for _, seg in ipairs(segs) do
                table.sort(seg.midi_list)
                seg.median_midi = seg.midi_list[math.floor(#seg.midi_list / 2) + 1]
                seg.duration = seg.t_end - seg.t_start
            end

            -- Filter: discard segments shorter than slide_min_seg_s
            local filtered = {}
            for _, seg in ipairs(segs) do
                if seg.duration >= S.slide_min_seg_ms * 0.001 then
                    filtered[#filtered + 1] = seg
                end
            end

            -- Merge adjacent segments that share a pitch class (after gap filtering)
            local merged = {}
            for _, seg in ipairs(filtered) do
                if #merged > 0 and merged[#merged].pc == seg.pc then
                    local last = merged[#merged]
                    for _, v in ipairs(seg.midi_list) do
                        last.midi_list[#last.midi_list + 1] = v
                    end
                    last.t_end    = seg.t_end
                    last.duration = last.t_end - last.t_start
                    table.sort(last.midi_list)
                    last.median_midi =
                        last.midi_list[math.floor(#last.midi_list / 2) + 1]
                else
                    merged[#merged + 1] = {
                        pc         = seg.pc,
                        midi_list  = seg.midi_list,
                        t_start    = seg.t_start,
                        t_end      = seg.t_end,
                        duration   = seg.duration,
                        median_midi = seg.median_midi,
                    }
                end
            end

            if #merged < 2 then
                n_stable = n_stable + 1
            else
                local shape  = ClassifySlide(merged)
                local from_p = merged[1].median_midi
                local to_p   = merged[#merged].median_midi

                -- Show the actual turning point, not just the middle index.
                -- Scoop: deepest dip among inner segments.
                -- Bend:  highest peak among inner segments.
                -- Slide up/down and Complex slide: no mid_p (no single
                -- representative point; Complex label conveys the complexity).
                local mid_p, mid_dur = nil, nil
                if shape == 'Scoop' and #merged >= 3 then
                    local min_midi = math.huge
                    for j = 2, #merged - 1 do
                        if merged[j].median_midi < min_midi then
                            min_midi = merged[j].median_midi
                            mid_dur  = merged[j].duration
                        end
                    end
                    mid_p = min_midi
                elseif shape == 'Bend' and #merged >= 3 then
                    local max_midi = -math.huge
                    for j = 2, #merged - 1 do
                        if merged[j].median_midi > max_midi then
                            max_midi = merged[j].median_midi
                            mid_dur  = merged[j].duration
                        end
                    end
                    mid_p = max_midi
                end

                slide_results[#slide_results + 1] = {
                    time       = note.s,
                    note_dur   = note.e - note.s,
                    note_pitch = note.pitch,
                    lyric      = note.lyric,
                    shape      = shape,
                    from_p     = from_p,
                    from_dur   = merged[1].duration,
                    to_p       = to_p,
                    to_dur     = merged[#merged].duration,
                    mid_p      = mid_p,
                    mid_dur    = mid_dur,
                }
            end
        end
    end

    CloseYINContext(yctx)

    -- Format result lines
    local lines = {
        ('Range: %s - %s%s'):format(
            FormatTime(range_start), FormatTime(range_end),
            has_sel and ' [time selection]' or ' [whole MIDI item]'),
        ('%d notes  |  %d scanned  |  %d too short (<%dms)  |  %d stable')
            :format(#notes, n_scanned, n_too_short, S.slide_min_note_ms, n_stable),
    }

    if #slide_results == 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'No pitch slides detected.'
    else
        lines[#lines + 1] = ('%d slide%s detected:')
            :format(#slide_results, #slide_results == 1 and '' or 's')
        lines[#lines + 1] = ''
        for _, res in ipairs(slide_results) do
            local note_name = PitchName(res.note_pitch)
            local lyric_tag = res.lyric
                and ('(%s "%s") '):format(note_name, res.lyric)
                or  ('(%s) '):format(note_name)
            local nd = res.note_dur
            local function pct(d)
                return math.max(1, math.floor(d / nd * 100 + 0.5))
            end
            local pitch_str
            if res.mid_p then
                pitch_str = ('%s (%d%%) -> %s (%d%%) -> %s (%d%%)'):format(
                    PitchName(res.from_p), pct(res.from_dur),
                    PitchName(res.mid_p),  pct(res.mid_dur),
                    PitchName(res.to_p),   pct(res.to_dur))
            else
                pitch_str = ('%s (%d%%) -> %s (%d%%)'):format(
                    PitchName(res.from_p), pct(res.from_dur),
                    PitchName(res.to_p),   pct(res.to_dur))
            end
            lines[#lines + 1] = ('%-26s  %s%-16s  %s'):format(
                FormatTime(res.time), lyric_tag, res.shape, pitch_str)
        end
    end

    S.status = ('%d pitch slide%s detected'):format(
        #slide_results, #slide_results == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Snap to Key Scale
----------------------------------------------------------------------

-- Returns snapped_pitch (int) and semitone distance (int >= 0).
-- Ties (equidistant up/down) snap downward (lower pitch wins) so that a note
-- "between" two scale degrees consistently rounds to the lower one.
local function NearestScalePitch(pitch, root, quality)
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
        S.last_result = ('Range: %s \xe2\x80\x94 %s%s\nNo vocal notes found.'):format(
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
    ClearAllNotesInRange(midi_take, range_start, range_end)
    ClearLyricsInRange(midi_take, range_start, range_end)
    for _, n in ipairs(snapped) do
        local sppq = r.MIDI_GetPPQPosFromProjTime(midi_take, n.s)
        local eppq = r.MIDI_GetPPQPosFromProjTime(midi_take, n.e)
        r.MIDI_InsertNote(midi_take, n.sel, n.mute, sppq, eppq, n.chan, n.pitch, n.vel, false)
        if n.lyric then
            r.MIDI_InsertTextSysexEvt(midi_take, false, false, sppq, 5, n.lyric)
        end
    end
    r.Undo_EndBlock2(0,
        ('Vocal Helper VKR: Snap to key \xe2\x80\x94 %d note%s moved')
            :format(moved, moved == 1 and '' or 's'), -1)
    r.PreventUIRefresh(-1)

    local key_name = HARM_NOTE_NAMES[root + 1] .. (quality == 1 and ' minor' or ' major')
    local lines = {
        ('Snap to key: %s'):format(key_name),
        ('Range: %s \xe2\x80\x94 %s%s'):format(
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
