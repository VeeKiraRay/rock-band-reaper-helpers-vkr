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
-- params: { threshold, min_freq, max_freq, window_ms, min_conf, rms_gate,
--           vote_windows }
--
-- sr is the source rate; analysis_sr is the rate windows are actually read and
-- analysed at (see YINAnalysisRate). Callers that sweep max_freq should pass
-- the widest value they will try, so one context stays valid for all of them.
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
        accessor    = r.CreateTakeAudioAccessor(take),
        sr          = sr,
        analysis_sr = YINAnalysisRate(sr, params and params.max_freq),
        nch         = nch,
        item_pos    = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION'),
        params      = params,
    }
end

function CloseYINContext(ctx)
    if ctx then r.DestroyAudioAccessor(ctx.accessor) end
end

----------------------------------------------------------------------
-- YIN core helpers (shared by DetectPitchYIN, SampleYINAt, AutoTuneYIN)
----------------------------------------------------------------------

-- Analysis geometry for one YIN window.
--   tau_max  longest lag searched, set by min_freq alone
--   n_samps  samples to read: W + tau_max, so mono[j + tau] stays in range for
--            every j in 1..W and every tau up to tau_max
-- win_s is the correlation width W - the number of terms every tau sums over -
-- not the total read length. Sizing the read to W + tau_max is what lets
-- ComputeCMND use one fixed width for all tau (see there for why that matters).
--
-- W is deliberately not required to reach tau_max. Correctness only needs
-- n_samps >= W + tau_max, which holds by construction, and measurement shows
-- accuracy is flat down to W/tau_max ~ 0.4 - so short windows (the pitch-slide
-- case) stay usable. Note this makes tau_max depend on min_freq alone: unlike
-- the old geometry, a short window no longer silently narrows the frequency
-- range it claims to search.
function YINWindowSize(sr, win_s, min_freq)
    local w_samps = math.max(2, math.floor(win_s * sr))
    local tau_max = math.floor(sr / min_freq)
    if tau_max < 1 then return nil end
    return tau_max, w_samps + tau_max
end

-- Sample rate to analyse at, which need not be the source rate. The accessor
-- resamples on request (see dev/tests/run_accessor_resampling.lua), and CMND
-- cost falls with the square of the ratio - both W and tau_max shrink - so a
-- 48 kHz source analysed at 24 kHz is ~4x fewer inner iterations, measured at
-- 3.2x faster wall clock.
--
-- The 24 kHz floor is measured, not chosen for neatness. Over 396 cases (real
-- equal-tempered pitches MIDI 40-83, three noise levels, three seeds), 24 kHz
-- and 32 kHz both scored 396/396 with 0.00 cents mean deviation from 48 kHz,
-- while 16 kHz scored 378/396 with genuine semitone errors (MIDI 78 read as
-- 77, 79 as 80). 16 kHz is not safe for vocals despite being the obvious
-- "fundamentals are all below 1.1 kHz" choice.
--
-- The 24x max_freq term keeps enough lag resolution at the top of the searched
-- range: it is what makes a Piano/keys setting (max_freq 2000) resolve to the
-- full rate rather than downsampling into the one configuration where 24 kHz
-- measured worse.
function YINAnalysisRate(source_sr, max_freq)
    local wanted = math.max(24000, math.ceil((max_freq or 1000) * 24))
    return math.min(source_sr, wanted)
end

-- One-pole high-pass, applied in place, cascaded `poles` times for a steeper
-- slope. Seeding prev_x from the first sample avoids a step transient at the
-- buffer start, which would otherwise land inside the correlation width.
local function HighPassInPlace(mono, sr, fc, poles)
    local rc = 1 / (2 * math.pi * fc)
    local a  = rc / (rc + 1 / sr)
    for _ = 1, poles do
        local prev_x, prev_y = mono[1], 0
        for i = 1, #mono do
            local x = mono[i]
            prev_y  = a * (prev_y + x - prev_x)
            prev_x  = x
            mono[i] = prev_y
        end
    end
end

-- Read n_samps frames at project time t_sample from a YIN context accessor,
-- downmixed to a 1-based mono table.
-- The accessor is take-relative, so project time must be offset by item_pos.
--
-- hp_hz (optional) high-passes the window at that cutoff before returning.
-- Callers pass their min_freq: energy below the lowest pitch being searched
-- for can only hurt, and rumble, plosives and low-end instrument bleed drag
-- YIN toward a subharmonic. Measured against 45-60 Hz contamination with the
-- default 80 Hz min_freq, correct detections go 122 -> 159 at moderate level
-- and 35 -> 130 at heavy level, with no loss on clean audio (155 -> 154).
-- The failure mode it fixes is mostly *missed* detections - contaminated
-- windows fail the confidence gate and silently fall back to the default
-- pitch - not wrong ones.
function ReadMonoWindow(yctx, t_sample, n_samps, hp_hz)
    -- n_samps is counted at the analysis rate, so the accessor must be asked
    -- for that rate too. It resamples on request; the probe test asserts this.
    local sr, nch = yctx.analysis_sr or yctx.sr, yctx.nch
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
    if hp_hz and hp_hz > 0 and hp_hz < sr * 0.5 then
        HighPassInPlace(mono, sr, hp_hz, 2)
    end
    return mono
end

-- RMS level of a window, read straight from a YIN context accessor as mono.
-- Cheap enough to run as a pre-gate before the O(W x tau_max) CMND.
function QuickRMS(yctx, t_sample, win_s)
    -- Read at the analysis rate: resampling preserves RMS (asserted by the
    -- accessor probe test), and fewer samples means a cheaper gate.
    local sr    = yctx.analysis_sr or yctx.sr
    local samps = math.max(1, math.floor(sr * win_s))
    local buf   = r.new_array(samps)
    local t_off = math.max(0, t_sample - yctx.item_pos)
    buf.clear()
    r.GetAudioAccessorSamples(yctx.accessor, sr, 1, t_off, samps, buf)
    local sum_sq = 0
    for i = 1, samps do sum_sq = sum_sq + buf[i] * buf[i] end
    return math.sqrt(sum_sq / samps)
end

-- Compute the cumulative mean normalized difference function (CMND / YIN step 2)
-- from a mono sample array. Returns table d[] where d[0]=0 and d[1..tau_max]
-- hold the normalized differences, or nil if the array is too short.
--
-- The summation width is fixed at W = #mono - tau_max for every tau, as in
-- classical YIN. Letting the width shrink with tau (summing to #mono - tau)
-- makes raw d(tau) drift downward at long lags purely from summing fewer
-- terms, which biases the search toward large tau - i.e. octave-down.
-- Measured over 420 synthetic cases (frequency x window x SNR): octave errors
-- drop from 27 to 16 with a full harmonic series, and from 56 to 34 when the
-- fundamental is missing.
function ComputeCMND(mono, tau_max)
    local W = #mono - tau_max
    if W < 1 then return nil end
    local d = {}
    d[0] = 0
    local running_sum = 0
    for tau = 1, tau_max do
        local sq = 0
        for j = 1, W do
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
--
-- Returns (pitch, confidence), or nil when no estimate survives the guards.
-- Confidence is 1 - d'(tau), YIN's periodicity measure: ~1 for a strongly
-- periodic window, near 0 for noise. min_conf defaults to 0.5, which
-- reproduces the previous hardcoded fallback guard.
function SearchYINTau(d, tau_min, tau_max, threshold, sr, min_freq, max_freq, min_conf)
    min_conf = min_conf or 0.5
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
        tau_est = min_tau
    end

    -- A minimum sitting on a scan boundary is not a real dip - the true period
    -- most likely lies outside [tau_min, tau_max] and the search merely ran out
    -- of room. Such a result also skips interpolation below, so it is doubly
    -- untrustworthy. Reject rather than report confident-looking garbage.
    if tau_est <= tau_min or tau_est >= tau_max then return nil end

    -- Read confidence while tau_est is still an integer index into d.
    local conf = 1 - d[tau_est]
    if conf < min_conf then return nil end

    -- Boundary rejection above guarantees both neighbours exist.
    local s0, s1, s2 = d[tau_est - 1], d[tau_est], d[tau_est + 1]
    local denom = 2 * s1 - s0 - s2
    if math.abs(denom) > 1e-10 then
        tau_est = tau_est + (s0 - s2) / (2 * denom)
    end

    local freq = sr / tau_est
    if freq < min_freq or freq > max_freq then return nil end
    return math.floor(69 + 12 * math.log(freq / 440) / math.log(2) + 0.5), conf
end

----------------------------------------------------------------------
-- YIN pitch detection - public API
----------------------------------------------------------------------

-- Sample at an explicit project time. win_s controls the analysis window.
-- Reads threshold/freq bounds/min_conf from yctx.params.
-- Returns (pitch, confidence) - see SearchYINTau.
function SampleYINAt(yctx, t_sample, win_s)
    local sr = yctx.analysis_sr or yctx.sr
    local p  = yctx.params
    if win_s < 0.01 then return nil end

    local tau_max, n_samps = YINWindowSize(sr, win_s, p.min_freq)
    if not tau_max then return nil end
    local tau_min = math.max(1, math.floor(sr / p.max_freq))
    if tau_max < tau_min then return nil end

    local mono = ReadMonoWindow(yctx, t_sample, n_samps, p.min_freq)
    local d    = ComputeCMND(mono, tau_max)
    if not d then return nil end
    return SearchYINTau(d, tau_min, tau_max, p.threshold, sr,
                        p.min_freq, p.max_freq, p.min_conf)
end

-- Where across a note to take vote samples, by vote count.
local VOTE_FRACTIONS = {
    [1] = { 0.30 },
    [3] = { 0.25, 0.45, 0.65 },
    [5] = { 0.20, 0.325, 0.45, 0.575, 0.70 },
}

-- Median of a list of integers, rounding up on an even count.
-- Returns the median and the highest confidence among the votes that agreed
-- with it, so the caller learns how sure the winning reading was.
function MedianVote(votes, confs)
    if #votes == 0 then return nil end
    local sorted = {}
    for i, v in ipairs(votes) do sorted[i] = v end
    table.sort(sorted)
    local n   = #sorted
    local med = (n % 2 == 1) and sorted[(n + 1) / 2]
                or math.floor((sorted[n / 2] + sorted[n / 2 + 1]) / 2 + 0.5)
    local best
    for i, v in ipairs(votes) do
        if v == med and (not best or (confs[i] or 0) > best) then best = confs[i] end
    end
    return med, best
end

-- Detect pitch for a note span. Reads all params (window_ms, threshold, freq
-- bounds, min_conf, rms_gate, vote_windows) from ctx.params.
-- Returns (pitch, confidence) - see SearchYINTau.
--
-- Sampling several points across the note and taking the median is markedly
-- more robust than one sample at 30%: a consonant burst or breath landing on
-- that single instant wrecks it. Measured over 96 synthetic notes with a
-- mid-note consonant, correct detections go 20 -> 96 with three votes; with
-- vibrato, 69 -> 82. On plain sustained notes all strategies tie, so the cost
-- is only paid where it is needed - and the early-out below means the common
-- case (first two votes agree) costs two windows, not three.
--
-- Weighting or discarding votes by confidence was measured and made no
-- difference at all (84 vs 84, 96 vs 96), so votes are counted equally.
--
-- rms_gate skips near-silent sample points. The confidence gate cannot do
-- this: CMND is amplitude-normalized, so quiet instrument bleed in a gap
-- scores just as confident as the vocal itself.
function DetectPitchYIN(ctx, note_s, note_e)
    local note_len = note_e - note_s
    local p        = ctx.params
    local win_s    = math.min(p.window_ms / 1000, note_len * 0.8)

    local fracs = VOTE_FRACTIONS[p.vote_windows or 1] or VOTE_FRACTIONS[1]

    -- Each sample consumes win_s plus one period of min_freq (the tau tail).
    -- Keep every sample point inside the note; if even one does not fit, fall
    -- back to the single 30% sample.
    local span    = win_s + 1 / (p.min_freq or 80)
    local latest  = note_e - span
    if #fracs > 1 and latest <= note_s then fracs = VOTE_FRACTIONS[1] end

    local votes, confs = {}, {}
    for i, fr in ipairs(fracs) do
        local t = note_s + note_len * fr
        if t > latest then t = latest end
        if t < note_s then t = note_s end

        local gated = false
        if p.rms_gate and p.rms_gate > 0 then
            gated = QuickRMS(ctx, t, win_s) < p.rms_gate
        end
        if not gated then
            local pitch, conf = SampleYINAt(ctx, t, win_s)
            if pitch then
                votes[#votes + 1] = pitch
                confs[#confs + 1] = conf
            end
        end

        -- Early-out: with 3 votes, two agreeing already fix the median.
        if i == 2 and #fracs == 3 and #votes == 2 and votes[1] == votes[2] then
            break
        end
    end

    return MedianVote(votes, confs)
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
