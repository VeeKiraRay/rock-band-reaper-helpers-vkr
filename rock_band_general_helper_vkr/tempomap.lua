-- Tempo map audio analysis: RMS contour, onset detection, BPM estimation, grid fitting
-- Requires: S, r (globals)

local BPM_MIN, BPM_MAX = 60, 250
local ONSET_GRACE_S = 0.05

-- Compute a per-window RMS contour from an audio item over [t_s, t_e].
-- Adapted from the vocal script's ComputeRMSContour; LPF pass removed
-- (not needed for broadband drum signals). Channels are averaged.
-- Returns {contour, t_start, t_step} on success, or nil + error string.
function ComputeTempoRMSContour(audio_item, t_s, t_e, window_s)
    local take = r.GetActiveTake(audio_item)
    if not take or r.TakeIsMIDI(take) then
        return nil, 'Active take on the drum track is not audio.'
    end

    local src = r.GetMediaItemTake_Source(take)
    local sr  = r.GetMediaSourceSampleRate(src)
    local nch = r.GetMediaSourceNumChannels(src)
    if sr == 0 then return nil, 'Could not read source sample rate.' end

    local item_pos   = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION')
    local rel_start  = t_s - item_pos
    local rel_len    = t_e - t_s
    local win_samps  = math.max(1, math.floor(window_s * sr))
    local total_wins = math.floor(rel_len / window_s)

    if total_wins < 1 then return nil, 'Analysis range is shorter than one RMS window.' end

    local accessor  = r.CreateTakeAudioAccessor(take)
    local chunk_wins = 256
    local buf_samps  = win_samps * chunk_wins
    local buffer     = r.new_array(buf_samps * nch)
    local contour    = {}
    local w = 0

    while w < total_wins do
        local this_wins  = math.min(chunk_wins, total_wins - w)
        local this_samps = this_wins * win_samps
        local t_chunk    = rel_start + (w * win_samps) / sr

        buffer.clear()
        local ret = r.GetAudioAccessorSamples(accessor, sr, nch, t_chunk, this_samps, buffer)
        if ret < 0 then break end

        for k = 0, this_wins - 1 do
            local sum  = 0
            local base = k * win_samps * nch + 1
            for i = base, base + win_samps * nch - 1 do
                local s = buffer[i]
                sum = sum + s * s
            end
            contour[#contour + 1] = math.sqrt(sum / (win_samps * nch))
        end
        w = w + this_wins
    end

    r.DestroyAudioAccessor(accessor)

    return { contour = contour, t_start = t_s, t_step = window_s }
end

-- Peak picker over an RMS contour. Records the first-crossing window of each
-- run above threshold as the onset (sharp drum transient rises fast). min_gap_s
-- enforces a minimum distance between accepted onsets.
function DetectOnsets(ci, threshold, min_gap_s)
    local contour       = ci.contour
    local t_start       = ci.t_start
    local t_step        = ci.t_step
    local min_gap_wins  = math.max(1, math.floor(min_gap_s / t_step))
    local onsets        = {}
    local last_peak_win = -min_gap_wins
    local i = 1

    while i <= #contour do
        if contour[i] >= threshold then
            local start_i = i
            local peak_i  = i
            local peak_v  = contour[i]
            while i <= #contour and contour[i] >= threshold do
                if contour[i] > peak_v then peak_i = i; peak_v = contour[i] end
                i = i + 1
            end
            if peak_i - last_peak_win >= min_gap_wins then
                onsets[#onsets + 1] = t_start + (start_i - 1) * t_step
                last_peak_win = peak_i
            end
        else
            i = i + 1
        end
    end

    return onsets
end

-- IOI histogram BPM estimator. Votes for bpm, bpm/2, and bpm×2 so kick patterns
-- spaced over 1, 2, or half a beat all converge on the same peak bin.
function EstimateBPM(onsets)
    if #onsets < 2 then return nil, 0 end
    local hist = {}
    for i = 2, #onsets do
        local ioi = onsets[i] - onsets[i-1]
        if ioi > 1e-6 then
            for _, bpm in ipairs({ 60/ioi, 30/ioi, 120/ioi }) do
                local bi = math.floor(bpm + 0.5)
                if bi >= BPM_MIN and bi <= BPM_MAX then
                    hist[bi] = (hist[bi] or 0) + 1
                end
            end
        end
    end
    local peak_bpm, peak_count = BPM_MIN, 0
    for b = BPM_MIN, BPM_MAX do
        local c = hist[b] or 0
        if c > peak_count then peak_bpm = b; peak_count = c end
    end
    if peak_count == 0 then return nil, 0 end
    local consistent = 0
    for i = 2, #onsets do
        local ioi = onsets[i] - onsets[i-1]
        if ioi > 1e-6 then
            for _, bpm in ipairs({ 60/ioi, 30/ioi, 120/ioi }) do
                if math.floor(bpm + 0.5) == peak_bpm then
                    consistent = consistent + 1
                    break
                end
            end
        end
    end
    return peak_bpm, consistent / math.max(1, #onsets - 1)
end

-- Phase-alignment vote for time signature numerator {3, 4, 6}.
-- Normalised score (count × num / #onsets) removes cycle-length bias.
function GuessTimeSig(onsets, beat_dur, anchor_t)
    if #onsets < 2 or beat_dur <= 0 then return 4, 0 end
    local snap_dist = ONSET_GRACE_S
    for _, t in ipairs(onsets) do
        local d = math.abs(t - anchor_t)
        if d < snap_dist then snap_dist = d; anchor_t = t end
    end
    local tolerance = beat_dur * 0.25
    local best_num, best_score, best_count = 4, 0, 0
    for _, num in ipairs({4, 3, 6}) do
        local measure_dur = num * beat_dur
        local count = 0
        for _, t in ipairs(onsets) do
            local phase = (t - anchor_t) % measure_dur
            if phase <= tolerance or phase >= measure_dur - tolerance then
                count = count + 1
            end
        end
        local score = count * num / #onsets
        if score > best_score then
            best_num   = num
            best_score = score
            best_count = count
        end
    end

    if best_num ~= 4 then
        local ioi_tol  = beat_dur * 0.15
        local ioi_4cnt = 0
        for i = 2, #onsets do
            if math.abs(onsets[i] - onsets[i-1] - 4 * beat_dur) < ioi_tol then
                ioi_4cnt = ioi_4cnt + 1
            end
        end
        if ioi_4cnt >= 2 then best_num = 4 end
    end

    if best_num ~= 4 and best_score < 1.25 then best_num = 4 end

    return best_num, best_count / #onsets
end

-- Build an ordered list of {onsets, name} for every configured source track
-- that has an audio item overlapping [t_s, t_e]. Priority: kick → snare → kit → fallback.
function GetSourcesForRange(t_s, t_e, window_s)
    local priority = {
        'tm_kick_idx', 'tm_snare_idx', 'tm_kit_idx', 'tm_fallback_idx',
    }
    local sources = {}
    for _, field in ipairs(priority) do
        local idx = S[field]
        if idx >= 0 then
            local tr = r.GetTrack(0, idx)
            if tr then
                local _, name = r.GetTrackName(tr)
                local item
                for j = 0, r.CountTrackMediaItems(tr) - 1 do
                    local it  = r.GetTrackMediaItem(tr, j)
                    local ip  = r.GetMediaItemInfo_Value(it, 'D_POSITION')
                    local ie  = ip + r.GetMediaItemInfo_Value(it, 'D_LENGTH')
                    if ip <= t_e and ie >= t_s then item = it; break end
                end
                if item then
                    local ci = ComputeTempoRMSContour(item, t_s, t_e, window_s)
                    if ci then
                        local onsets = DetectOnsets(ci, S.tm_rms_threshold, 0.05)
                        if #onsets > 0 then
                            sources[#sources + 1] = {onsets = onsets, name = name}
                        end
                    end
                end
            end
        end
    end
    return sources
end

-- Walk forward from anchor_t in measure-sized steps, searching for the nearest onset
-- within search_window_s of each expected downbeat. Returns an array of entries with
-- {expected_t, detected_t, deviation_s, bpm, source}.
function FitBeatGrid(anchor_t, t_end, beat_dur, num, sources, search_window_s)
    local grid = {}
    local t = anchor_t
    local min_advance = beat_dur * (num - 0.5)
    while true do
        local next_exp = t + num * beat_dur
        if next_exp > t_end + search_window_s then break end
        local best_t, best_src = nil, nil
        for _, src in ipairs(sources) do
            local found_d = search_window_s
            for _, ot in ipairs(src.onsets) do
                if ot < next_exp - search_window_s then
                    -- before window; keep scanning
                elseif ot > next_exp + search_window_s then
                    break
                elseif ot >= t + min_advance then
                    local d = math.abs(ot - next_exp)
                    if d < found_d then found_d = d; best_t = ot; best_src = src.name end
                end
            end
            if best_t then break end
        end
        local step_dur = ((best_t or next_exp) - t) / num
        grid[#grid + 1] = {
            expected_t  = next_exp,
            detected_t  = best_t,
            deviation_s = best_t and (best_t - next_exp) or nil,
            bpm         = 60.0 / step_dur,
            source      = best_src,
        }
        t = best_t or next_exp
    end
    return grid
end
