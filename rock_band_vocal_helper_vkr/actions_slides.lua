-- Pitch slide scan action

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
            'Scan pitch slides - no time selection', 1)
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

    -- Find audio item that overlaps the scan range
    local audio_item
    for i = 0, r.CountTrackMediaItems(audio_track) - 1 do
        local it   = r.GetTrackMediaItem(audio_track, i)
        local take = r.GetActiveTake(it)
        if take and not r.TakeIsMIDI(take) then
            local pos = r.GetMediaItemInfo_Value(it, 'D_POSITION')
            local len = r.GetMediaItemInfo_Value(it, 'D_LENGTH')
            if pos < range_end and pos + len > range_start then
                audio_item = it; break
            end
        end
    end
    if not audio_item then
        S.status = 'Error'
        S.last_result = 'No audio item on the source track overlaps the scan range.'
        return
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

    local yctx, yerr = OpenYINContext(audio_item, {
        threshold = S.yin_threshold,
        min_freq  = S.yin_min_freq,
        max_freq  = S.yin_max_freq,
        window_ms = S.yin_window_ms,
    })
    if not yctx then S.status = 'Error'; S.last_result = yerr; return end
    S.action_yctx = yctx

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

    S.action_yctx = nil
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
