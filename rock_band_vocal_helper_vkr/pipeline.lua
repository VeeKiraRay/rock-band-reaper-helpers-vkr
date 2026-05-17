-- Detection pipeline, pitch constraints, and result formatting

----------------------------------------------------------------------
function ResolveAnalysisRange(audio_track)
    local sel_start, sel_end = GetTimeSelection()
    local item

    if sel_start then
        for i = 0, r.CountTrackMediaItems(audio_track) - 1 do
            local it  = r.GetTrackMediaItem(audio_track, i)
            local pos = r.GetMediaItemInfo_Value(it, 'D_POSITION')
            local len = r.GetMediaItemInfo_Value(it, 'D_LENGTH')
            if pos < sel_end and pos + len > sel_start then
                item = it
                break
            end
        end
        if not item then
            return nil, 'No audio item on the source track overlaps the time selection.'
        end
    else
        item = r.GetTrackMediaItem(audio_track, 0)
        if not item then
            return nil, 'No media item on the audio track.'
        end
    end

    local item_pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_end = item_pos + item_len

    local range_start, range_end
    if sel_start then
        range_start = math.max(item_pos, sel_start)
        range_end   = math.min(item_end, sel_end)
    else
        range_start = item_pos
        range_end   = item_end
    end

    if range_end - range_start <= 0 then
        return nil, 'Analysis range is empty.'
    end

    return {
        item          = item,
        range_start   = range_start,
        range_end     = range_end,
        has_selection = sel_start ~= nil,
    }
end

----------------------------------------------------------------------
-- Resolve target for "Apply pitch changes": find a MIDI item to operate on,
-- and the time range within which to process notes.
--
-- With time selection: find a MIDI item that OVERLAPS the selection
-- (doesn't need to fully cover it; we just process notes within both).
-- Without time selection: use the first MIDI item on the track and its
-- full bounds.
----------------------------------------------------------------------
function ResolveApplyPitchTarget(midi_track)
    local sel_start, sel_end = GetTimeSelection()

    if sel_start then
        for i = 0, r.CountTrackMediaItems(midi_track) - 1 do
            local item = r.GetTrackMediaItem(midi_track, i)
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
                local item_end = pos + len
                if pos < sel_end and item_end > sel_start then
                    return {
                        item = item, take = take,
                        range_start = math.max(pos, sel_start),
                        range_end   = math.min(item_end, sel_end),
                        has_selection = true,
                    }
                end
            end
        end
        return nil, 'No MIDI item on the destination track overlaps the time selection.'
    end

    for i = 0, r.CountTrackMediaItems(midi_track) - 1 do
        local item = r.GetTrackMediaItem(midi_track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
            local len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
            return {
                item = item, take = take,
                range_start = pos, range_end = pos + len,
                has_selection = false,
            }
        end
    end
    return nil, 'No MIDI item found on the destination track.'
end

----------------------------------------------------------------------
-- Find the nearest reference pitch to a given time, within tolerance
----------------------------------------------------------------------
function FindNearestRefPitch(ref_notes, time, tolerance_s)
    local best_pitch, best_dist = nil, tolerance_s + 1
    for _, ref in ipairs(ref_notes) do
        if ref.s > time + tolerance_s then break end
        if ref.s >= time - tolerance_s then
            local dist = math.abs(ref.s - time)
            if dist < best_dist then
                best_dist = dist
                best_pitch = ref.pitch
            end
        end
    end
    return best_pitch
end

----------------------------------------------------------------------
-- Snap a pitch into [min, max] by trying octave shifts
----------------------------------------------------------------------
function ApplyPitchRange(pitch, min_p, max_p)
    if not min_p and not max_p then return pitch end
    local p = pitch
    local guard = 16
    while min_p and p < min_p and guard > 0 do
        p = p + 12
        guard = guard - 1
    end
    guard = 16
    while max_p and p > max_p and guard > 0 do
        p = p - 12
        guard = guard - 1
    end
    if min_p and p < min_p then p = min_p end
    if max_p and p > max_p then p = max_p end
    if p < RB3_MIN_PITCH then p = RB3_MIN_PITCH elseif p > RB3_MAX_PITCH then p = RB3_MAX_PITCH end
    return p
end

----------------------------------------------------------------------
-- Run the full detection pipeline
----------------------------------------------------------------------
function RunDetection(range_info)
    local contour_info, cerr = ComputeRMSContour(
        range_info.item, range_info.range_start, range_info.range_end,
        S.window_ms / 1000, S.lpf_cutoff_hz)
    if not contour_info then return nil, cerr end

    local raw, n_phrases, n_splits = GateAndSplit(
        contour_info,
        S.rms_threshold,
        S.split_ratio / 100,
        S.min_note_ms / 1000)

    local notes, capped, dropped = ApplyMinOffset(raw, S.min_offset_ms / 1000)

    return {
        notes         = notes,
        raw_count     = #raw,
        phrases       = n_phrases,
        splits        = n_splits,
        capped        = capped,
        dropped       = dropped,
        range_start   = range_info.range_start,
        range_end     = range_info.range_end,
        has_selection = range_info.has_selection,
    }
end

----------------------------------------------------------------------
-- Assign pitches based on the configured Pitch source
----------------------------------------------------------------------
function AssignPitches(notes, ref_track, audio_item, force_mode)
    local mode = force_mode ~= nil and force_mode or S.pitch_mode
    local default = S.pitch
    local min_p = S.min_pitch_enabled and S.min_pitch or nil
    local max_p = S.max_pitch_enabled and S.max_pitch or nil

    local ref_notes
    local ref_used, ref_fallback = 0, 0

    if mode == MODE_REFERENCE then
        if not ref_track then
            return nil, 'Reference MIDI track is not selected.'
        end
        local pad = (S.ref_search_ms / 1000) + 0.1
        local r_start = (notes[1] and notes[1].s or 0) - pad
        local r_end   = (notes[#notes] and notes[#notes].e or 0) + pad
        ref_notes = ReadAllMIDINotesOnTrack(ref_track, r_start, r_end)
    end

    local yin_ctx
    if mode == MODE_YIN then
        if not audio_item then
            return nil, 'Audio source item is required for built-in pitch detection.'
        end
        local err
        yin_ctx, err = OpenYINContext(audio_item)
        if not yin_ctx then return nil, err end
    end

    local out = {}
    for _, n in ipairs(notes) do
        local pitch
        if mode == MODE_REFERENCE then
            local found = FindNearestRefPitch(ref_notes, n.s, S.ref_search_ms / 1000)
            if found then
                pitch = found
                ref_used = ref_used + 1
            else
                pitch = default
                ref_fallback = ref_fallback + 1
            end
        elseif mode == MODE_YIN then
            local detected = DetectPitchYIN(yin_ctx, n.s, n.e)
            if detected then
                pitch = detected
                ref_used = ref_used + 1
            else
                pitch = default
                ref_fallback = ref_fallback + 1
            end
        else
            pitch = default
        end

        local raw_pitch = pitch
        pitch = ApplyPitchRange(pitch, min_p, max_p)
        out[#out + 1] = {
            s = n.s, e = n.e,
            pitch = pitch,
            shifted = (pitch ~= raw_pitch),
        }
    end

    if yin_ctx then CloseYINContext(yin_ctx) end

    local stats = { ref_used = ref_used, ref_fallback = ref_fallback }
    local shifted = 0
    for _, n in ipairs(out) do if n.shifted then shifted = shifted + 1 end end
    stats.range_adjusted = shifted

    return out, stats
end

----------------------------------------------------------------------
-- Result formatting (Preview / Generate)
----------------------------------------------------------------------
function FormatResult(res, action, cleared, pitch_stats)
    local lines = {
        ('%s: %d notes'):format(action, #res.notes),
        ('Range: %s — %s  (%.3fs)%s'):format(
            FormatTime(res.range_start), FormatTime(res.range_end),
            res.range_end - res.range_start,
            res.has_selection and ' [time selection]' or ' [whole item]'),
    }
    if res.splits > 0 then
        lines[#lines + 1] = ('Phrases: %d  ->  split into %d extra notes')
            :format(res.phrases, res.splits)
    else
        lines[#lines + 1] = ('Phrases: %d'):format(res.phrases)
    end
    lines[#lines + 1] = ('Length-capped by min offset: %d'):format(res.capped)
    lines[#lines + 1] = ('Dropped (too short): %d'):format(res.dropped)

    if pitch_stats then
        if S.pitch_mode == MODE_REFERENCE then
            lines[#lines + 1] = ('Pitch source: Reference  ->  matched %d, fallback to default %d')
                :format(pitch_stats.ref_used, pitch_stats.ref_fallback)
        elseif S.pitch_mode == MODE_YIN then
            lines[#lines + 1] = ('Pitch source: Built-in  ->  detected %d, fallback to default %d')
                :format(pitch_stats.ref_used, pitch_stats.ref_fallback)
        end
        if pitch_stats.range_adjusted and pitch_stats.range_adjusted > 0 then
            lines[#lines + 1] = ('Pitch range adjusted: %d notes octave-shifted or clamped')
                :format(pitch_stats.range_adjusted)
        end
    end

    if cleared then
        lines[#lines + 1] = ('Cleared existing notes in range: %d'):format(cleared)
    end
    return table.concat(lines, '\n')
end
