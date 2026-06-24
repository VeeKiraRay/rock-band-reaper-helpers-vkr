-- DSP and audio analysis functions (shared library)
-- Requires globals: r (reaper)

----------------------------------------------------------------------
function ComputeRMSContour(audio_item, range_start, range_end, window_s, lpf_cutoff_hz)
    local take = r.GetActiveTake(audio_item)
    if not take or r.TakeIsMIDI(take) then
        return nil, 'Active take on the audio track is not audio.'
    end

    local src = r.GetMediaItemTake_Source(take)
    local sr  = r.GetMediaSourceSampleRate(src)
    local nch = r.GetMediaSourceNumChannels(src)
    if sr == 0 then return nil, 'Could not read source sample rate.' end

    local item_pos  = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION')
    local rel_start = range_start - item_pos
    local rel_len   = range_end   - range_start

    local accessor   = r.CreateTakeAudioAccessor(take)
    local win_samps  = math.max(1, math.floor(window_s * sr))
    local total_wins = math.floor(rel_len / window_s)
    local chunk_wins = 256
    local buf_samps  = win_samps * chunk_wins
    local buffer     = r.new_array(buf_samps * nch)

    local lpf_alpha
    if lpf_cutoff_hz > 0 and lpf_cutoff_hz < sr * 0.5 then
        lpf_alpha = 1 - math.exp(-2 * math.pi * lpf_cutoff_hz / sr)
    end
    local lpf_y1, lpf_y2 = {}, {}
    for c = 0, nch - 1 do lpf_y1[c] = 0; lpf_y2[c] = 0 end

    local contour   = {}
    local truncated = false
    local w = 0
    while w < total_wins do
        local this_wins  = math.min(chunk_wins, total_wins - w)
        local this_samps = this_wins * win_samps
        local t_start    = rel_start + (w * win_samps) / sr

        buffer.clear()
        local ret = r.GetAudioAccessorSamples(accessor, sr, nch, t_start, this_samps, buffer)
        if ret < 0 then truncated = true; break end

        for k = 0, this_wins - 1 do
            local sum  = 0
            local base = k * win_samps * nch + 1
            local last = base + win_samps * nch - 1
            if lpf_alpha then
                for i = base, last do
                    local ch  = (i - base) % nch
                    local raw = buffer[i]
                    local y1  = lpf_y1[ch] + lpf_alpha * (raw - lpf_y1[ch])
                    local y2  = lpf_y2[ch] + lpf_alpha * (y1  - lpf_y2[ch])
                    lpf_y1[ch] = y1
                    lpf_y2[ch] = y2
                    sum = sum + y2 * y2
                end
            else
                for i = base, last do
                    local s = buffer[i]
                    sum = sum + s * s
                end
            end
            contour[#contour + 1] = math.sqrt(sum / (win_samps * nch))
        end
        w = w + this_wins
    end

    r.DestroyAudioAccessor(accessor)

    return {
        contour     = contour,
        win_samps   = win_samps,
        sr          = sr,
        time_offset = range_start,
        truncated   = truncated or nil,
    }
end

----------------------------------------------------------------------
-- YIN monophonic pitch detection
----------------------------------------------------------------------
-- params: { threshold, min_freq, max_freq, window_ms }
function OpenYINContext(audio_item, params)
    local take = r.GetActiveTake(audio_item)
    if not take or r.TakeIsMIDI(take) then
        return nil, 'Audio item has no valid audio take.'
    end
    local src = r.GetMediaItemTake_Source(take)
    local sr  = r.GetMediaSourceSampleRate(src)
    local nch = r.GetMediaSourceNumChannels(src)
    if sr == 0 then return nil, 'Could not read source sample rate.' end
    return {
        accessor = r.CreateTakeAudioAccessor(take),
        sr       = sr,
        nch      = nch,
        item_pos = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION'),
        params   = params,
    }
end

function CloseYINContext(ctx)
    if ctx then r.DestroyAudioAccessor(ctx.accessor) end
end

----------------------------------------------------------------------
-- YIN core helpers (shared by DetectPitchYIN, SampleYINAt, AutoTuneYIN)
----------------------------------------------------------------------

-- Compute the cumulative mean normalized difference function (CMND / YIN step 2)
-- from a mono sample array. Returns table d[] where d[0]=0 and d[1..tau_max]
-- hold the normalized differences.
function ComputeCMND(mono, tau_max)
    local d = {}
    d[0] = 0
    local running_sum = 0
    for tau = 1, tau_max do
        local sq = 0
        for j = 1, #mono - tau do
            local diff = mono[j] - mono[j + tau]
            sq = sq + diff * diff
        end
        running_sum = running_sum + sq
        d[tau] = (running_sum > 0) and (sq * tau / running_sum) or 1
    end
    return d
end

-- Search a CMND table for the best period estimate and convert to a MIDI pitch.
-- First dip below threshold sliding to a local minimum; fallback to global
-- minimum; parabolic interpolation for sub-sample precision.
-- Returns MIDI pitch integer, or nil if no confident estimate.
function SearchYINTau(d, tau_min, tau_max, threshold, sr, min_freq, max_freq)
    local tau_est
    for tau = tau_min, tau_max - 1 do
        if d[tau] < threshold then
            while tau < tau_max and d[tau + 1] < d[tau] do tau = tau + 1 end
            tau_est = tau
            break
        end
    end
    if not tau_est then
        local min_d, min_tau = math.huge, tau_min
        for tau = tau_min, tau_max do
            if d[tau] < min_d then min_d = d[tau]; min_tau = tau end
        end
        if min_d > 0.5 then return nil end
        tau_est = min_tau
    end
    if tau_est > tau_min and tau_est < tau_max then
        local s0, s1, s2 = d[tau_est - 1], d[tau_est], d[tau_est + 1]
        local denom = 2 * s1 - s0 - s2
        if math.abs(denom) > 1e-10 then
            tau_est = tau_est + (s0 - s2) / (2 * denom)
        end
    end
    local freq = sr / tau_est
    if freq < min_freq or freq > max_freq then return nil end
    return math.floor(69 + 12 * math.log(freq / 440) / math.log(2) + 0.5)
end

----------------------------------------------------------------------
-- YIN pitch detection — public API
----------------------------------------------------------------------

-- Sample at an explicit project time. win_s controls the analysis window.
-- Reads threshold/freq bounds from yctx.params.
function SampleYINAt(yctx, t_sample, win_s)
    local sr, nch = yctx.sr, yctx.nch
    local p       = yctx.params
    if win_s < 0.01 then return nil end

    local n_samps = math.max(2, math.floor(win_s * sr))
    local tau_min = math.max(1, math.floor(sr / p.max_freq))
    local tau_max = math.min(
        math.floor(sr / p.min_freq),
        math.floor(n_samps / 2) - 1)
    if tau_max < tau_min then return nil end

    local t_off = t_sample - yctx.item_pos
    if t_off < 0 then t_off = 0 end

    local buf = r.new_array(n_samps * nch)
    buf.clear()
    r.GetAudioAccessorSamples(yctx.accessor, sr, nch, t_off, n_samps, buf)

    local mono = {}
    for i = 1, n_samps do
        local s = 0
        for c = 0, nch - 1 do s = s + buf[(i - 1) * nch + c + 1] end
        mono[i] = nch > 1 and s / nch or s
    end

    local d = ComputeCMND(mono, tau_max)
    return SearchYINTau(d, tau_min, tau_max, p.threshold, sr, p.min_freq, p.max_freq)
end

-- Detect pitch for a note span. Samples at 30% into the note to hit
-- steady-state vowel and avoid the attack transient. Reads all params
-- (window_ms, threshold, freq bounds) from ctx.params.
function DetectPitchYIN(ctx, note_s, note_e)
    local note_len = note_e - note_s
    local p        = ctx.params
    local win_s    = math.min(p.window_ms / 1000, note_len * 0.8)
    return SampleYINAt(ctx, note_s + note_len * 0.3, win_s)
end

----------------------------------------------------------------------
-- Gate + optional peak-relative split
----------------------------------------------------------------------
function GateAndSplit(contour_info, threshold, split_ratio, min_note_s)
    local contour   = contour_info.contour
    local win_samps = contour_info.win_samps
    local sr        = contour_info.sr
    local t_off     = contour_info.time_offset
    local win_s     = win_samps / sr
    local min_wins  = math.max(1, math.floor(min_note_s / win_s))

    local phrases = {}
    local in_phr, p_s, p_e = false, 0, 0
    for i = 1, #contour do
        if contour[i] >= threshold then
            if not in_phr then in_phr = true; p_s = i end
            p_e = i + 1
        elseif in_phr then
            phrases[#phrases + 1] = { s = p_s, e = p_e }
            in_phr = false
        end
    end
    if in_phr then phrases[#phrases + 1] = { s = p_s, e = p_e } end

    local notes_idx = {}
    local split_extra = 0

    for _, phr in ipairs(phrases) do
        if split_ratio <= 0 then
            if (phr.e - phr.s) >= min_wins then
                notes_idx[#notes_idx + 1] = { s = phr.s, e = phr.e }
            end
        else
            local peak = 0
            for i = phr.s, phr.e - 1 do
                if contour[i] > peak then peak = contour[i] end
            end
            local cut = peak * split_ratio
            if cut < threshold then cut = threshold end

            local sub_count = 0
            local in_sub, s_idx, e_idx = false, 0, 0
            for i = phr.s, phr.e - 1 do
                if contour[i] >= cut then
                    if not in_sub then in_sub = true; s_idx = i end
                    e_idx = i + 1
                elseif in_sub then
                    if (e_idx - s_idx) >= min_wins then
                        notes_idx[#notes_idx + 1] = { s = s_idx, e = e_idx }
                        sub_count = sub_count + 1
                    end
                    in_sub = false
                end
            end
            if in_sub and (e_idx - s_idx) >= min_wins then
                notes_idx[#notes_idx + 1] = { s = s_idx, e = e_idx }
                sub_count = sub_count + 1
            end
            if sub_count > 1 then split_extra = split_extra + (sub_count - 1) end
        end
    end

    local notes = {}
    for _, n in ipairs(notes_idx) do
        notes[#notes + 1] = {
            s = t_off + (n.s - 1) * win_s,
            e = t_off + (n.e - 1) * win_s,
        }
    end

    return notes, #phrases, split_extra
end

----------------------------------------------------------------------
-- Snap note boundaries to the nearest peak energy transition
----------------------------------------------------------------------
function SnapOnsets(notes, contour_info, window_ms)
    local contour = contour_info.contour
    local win_s   = contour_info.win_samps / contour_info.sr
    local t_off   = contour_info.time_offset
    local half    = math.max(1, math.floor((window_ms / 1000) / win_s))
    local n_total = #contour

    local out = {}
    for _, n in ipairs(notes) do
        local si = math.max(1, math.floor((n.s - t_off) / win_s) + 1)
        local ei = math.max(1, math.floor((n.e - t_off) / win_s) + 1)

        -- Snap start: find peak positive derivative near si
        local best_si, best_sd = si, -math.huge
        for i = math.max(2, si - half), math.min(n_total, si + half) do
            local d = contour[i] - contour[i - 1]
            if d > best_sd then best_sd = d; best_si = i end
        end

        -- Snap end: find peak negative derivative near ei
        local best_ei, best_ed = ei, math.huge
        for i = math.max(2, ei - half), math.min(n_total, ei + half) do
            local d = contour[i] - contour[i - 1]
            if d < best_ed then best_ed = d; best_ei = i end
        end

        local snapped_s = t_off + (best_si - 1) * win_s
        local snapped_e = t_off + (best_ei - 1) * win_s
        if snapped_e > snapped_s then
            out[#out + 1] = { s = snapped_s, e = snapped_e }
        else
            out[#out + 1] = { s = n.s, e = n.e }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Apply min-offset cap
----------------------------------------------------------------------
function ApplyMinOffset(notes, min_off_s)
    local capped = 0
    for i = 1, #notes - 1 do
        local cap = notes[i + 1].s - min_off_s
        if notes[i].e > cap then
            notes[i].e = cap
            capped = capped + 1
        end
    end
    local out, dropped = {}, 0
    for _, n in ipairs(notes) do
        if n.e > n.s then
            out[#out + 1] = n
        else
            dropped = dropped + 1
        end
    end
    return out, capped, dropped
end
