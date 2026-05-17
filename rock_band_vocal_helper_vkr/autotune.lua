-- Auto-tune parameter sweep for detection and YIN pitch assignment

----------------------------------------------------------------------
-- Score detection vs reference (for auto-tune)
----------------------------------------------------------------------
local MATCH_TOLERANCE_S = 0.25

local function ScoreNotes(detected, reference)
    local pairs_list = {}
    for i, ref in ipairs(reference) do
        for j, det in ipairs(detected) do
            local dist = math.abs(det.s - ref.s)
            if dist <= MATCH_TOLERANCE_S then
                pairs_list[#pairs_list + 1] = { i = i, j = j, dist = dist }
            end
        end
    end
    table.sort(pairs_list, function(a, b) return a.dist < b.dist end)

    local matches = {}
    local ref_used, det_used = {}, {}
    for _, p in ipairs(pairs_list) do
        if not ref_used[p.i] and not det_used[p.j] then
            ref_used[p.i] = true
            det_used[p.j] = true
            local ref = reference[p.i]
            local det = detected[p.j]
            matches[#matches + 1] = {
                start_diff = det.s - ref.s,
                len_diff   = (det.e - det.s) - (ref.e - ref.s),
            }
        end
    end

    local matched = #matches
    local misses  = #reference - matched
    local extras  = #detected  - matched

    local sum_start, sum_len = 0, 0
    for _, m in ipairs(matches) do
        sum_start = sum_start + math.abs(m.start_diff)
        sum_len   = sum_len   + math.abs(m.len_diff)
    end
    local mean_start = matched > 0 and sum_start / matched or 0
    local mean_len   = matched > 0 and sum_len   / matched or 0

    local score = (misses + extras) * 1000
                + mean_start * 1000
                + mean_len   * 100

    return {
        score        = score,
        matched      = matched,
        misses       = misses,
        extras       = extras,
        mean_start_s = mean_start,
        mean_len_s   = mean_len,
        ref_count    = #reference,
        det_count    = #detected,
    }
end

----------------------------------------------------------------------
-- Auto-tune
----------------------------------------------------------------------
local function FineCandidates(value, deltas, lo, hi)
    local out = {}
    for _, d in ipairs(deltas) do
        local v = value + d
        if v >= lo and v <= hi then out[#out + 1] = v end
    end
    return out
end

local function EvaluateParams(contour_cache, range_info, params)
    local key = ('%.0f|%.2f'):format(params.window_ms, params.lpf_cutoff_hz)
    local contour_info = contour_cache[key]
    if not contour_info then
        local ci, err = ComputeRMSContour(
            range_info.item, range_info.range_start, range_info.range_end,
            params.window_ms / 1000, params.lpf_cutoff_hz)
        if not ci then return nil, err end
        contour_cache[key] = ci
        contour_info = ci
    end
    local notes = GateAndSplit(contour_info,
        params.rms_threshold, params.split_ratio / 100, params.min_note_ms / 1000)
    notes = ApplyMinOffset(notes, params.min_offset_ms / 1000)
    return notes
end

function AutoTune(range_info, midi_take)
    local ref_notes = ReadAutoTuneRefNotes(midi_take,
        range_info.range_start, range_info.range_end)
    if #ref_notes == 0 then
        return nil, 'No notes in the time selection to use as reference.\n' ..
            'Place a few notes manually on the destination MIDI item first, then run Auto-tune.'
    end

    local cache = {}
    local CANDIDATES_COARSE = {
        rms_threshold = { 0.005, 0.01, 0.02, 0.04, 0.07, 0.1, 0.15, 0.2 },
        lpf_cutoff_hz = { 0, 1500, 2000, 2500, 3000 },
        split_ratio   = { 0, 30, 50, 70 },
        min_offset_ms = { 0, 25, 50, 100, 150, 200, 300 },
        min_note_ms   = { 30, 50, 80, 120, 200 },
    }

    local best = {
        rms_threshold = S.rms_threshold,
        lpf_cutoff_hz = S.lpf_cutoff_hz,
        split_ratio   = S.split_ratio,
        min_offset_ms = S.min_offset_ms,
        min_note_ms   = S.min_note_ms,
        window_ms     = S.window_ms,
    }

    local function Eval(params)
        local notes, err = EvaluateParams(cache, range_info, params)
        if not notes then return nil, err end
        return ScoreNotes(notes, ref_notes)
    end

    local best_score, eval_err = Eval(best)
    if not best_score then return nil, eval_err end

    local function SweepParam(name, candidates)
        for _, val in ipairs(candidates) do
            if val ~= best[name] then
                local trial = {}
                for k, v in pairs(best) do trial[k] = v end
                trial[name] = val
                local sc = Eval(trial)
                if sc and sc.score < best_score.score then
                    best = trial
                    best_score = sc
                end
            end
        end
    end

    for _ = 1, 2 do
        SweepParam('rms_threshold', CANDIDATES_COARSE.rms_threshold)
        SweepParam('lpf_cutoff_hz', CANDIDATES_COARSE.lpf_cutoff_hz)
        SweepParam('split_ratio',   CANDIDATES_COARSE.split_ratio)
        SweepParam('min_offset_ms', CANDIDATES_COARSE.min_offset_ms)
        SweepParam('min_note_ms',   CANDIDATES_COARSE.min_note_ms)
    end

    SweepParam('rms_threshold', FineCandidates(best.rms_threshold,
        { -0.015, -0.01, -0.005, 0.005, 0.01, 0.015 }, 0.001, 0.5))
    if best.lpf_cutoff_hz > 0 then
        SweepParam('lpf_cutoff_hz', FineCandidates(best.lpf_cutoff_hz,
            { -500, -250, 250, 500 }, 100, 8000))
    end
    if best.split_ratio > 0 then
        SweepParam('split_ratio', FineCandidates(best.split_ratio,
            { -15, -10, -5, 5, 10, 15 }, 1, 95))
    end
    SweepParam('min_offset_ms', FineCandidates(best.min_offset_ms,
        { -30, -15, 15, 30 }, 0, 500))
    SweepParam('min_note_ms', FineCandidates(best.min_note_ms,
        { -30, -15, 15, 30 }, 10, 500))

    return { params = best, score = best_score, ref_count = #ref_notes }
end

function FormatAutoTuneResult(result)
    local p  = result.params
    local sc = result.score
    local denom = math.max(sc.ref_count, sc.det_count, 1)
    local accuracy = (sc.matched / denom) * 100

    local lines = {
        'Auto-tune complete',
        ('  Reference     : %d notes'):format(sc.ref_count),
        ('  Detected      : %d notes'):format(sc.det_count),
        ('  Matched       : %d  (%.0f%% accuracy)'):format(sc.matched, accuracy),
        ('  Misses / extras: %d / %d'):format(sc.misses, sc.extras),
        ('  Avg start diff : ±%.0f ms'):format(sc.mean_start_s * 1000),
        ('  Avg length diff: ±%.0f ms'):format(sc.mean_len_s   * 1000),
        '',
        'Applied values:',
        ('  RMS threshold : %.4f'):format(p.rms_threshold),
        ('  Low-pass      : %s'):format(
            p.lpf_cutoff_hz > 0 and ('%.0f Hz'):format(p.lpf_cutoff_hz) or 'Off'),
        ('  Split ratio   : %s'):format(
            p.split_ratio > 0 and ('%.0f%%'):format(p.split_ratio) or 'Off'),
        ('  Min offset    : %.0f ms'):format(p.min_offset_ms),
        ('  Min note      : %.0f ms'):format(p.min_note_ms),
    }
    return table.concat(lines, '\n')
end

function ApplyAutoTuneResult(result)
    local p = result.params
    S.rms_threshold = p.rms_threshold
    S.lpf_cutoff_hz = p.lpf_cutoff_hz
    S.split_ratio   = p.split_ratio
    S.min_offset_ms = p.min_offset_ms
    S.min_note_ms   = p.min_note_ms
end

function FormatAutoTuneYINResult(result)
    local p   = result.params
    local pct = result.ref_count > 0
        and (result.pc_hits / result.ref_count * 100) or 0

    local lines = {
        'YIN auto-tune complete',
        ('  Reference notes  : %d'):format(result.ref_count),
        ('  Detected         : %d  (fallback to default: %d)'):format(
            result.detected, result.fallback),
        ('  Pitch-class hits : %d  (%.0f%%)'):format(result.pc_hits, pct),
        '',
        'Applied values:',
        ('  YIN threshold  : %.3f'):format(p.yin_threshold),
        ('  Min frequency  : %.0f Hz'):format(p.yin_min_hz),
        ('  Max frequency  : %.0f Hz'):format(p.yin_max_hz),
        ('  YIN window     : %.0f ms'):format(p.yin_window_ms),
    }

    if result.octave_mismatches > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Octave mismatches: %d (correct pitch class, wrong octave).')
            :format(result.octave_mismatches)
        lines[#lines + 1] = ('Reference spans %s\xe2\x80\x93%s. Consider enabling pitch range constraints:')
            :format(PitchName(result.ref_min_pitch), PitchName(result.ref_max_pitch))
        lines[#lines + 1] = ('  Min pitch: %d (%s),  Max pitch: %d (%s)')
            :format(result.ref_min_pitch, PitchName(result.ref_min_pitch),
                    result.ref_max_pitch, PitchName(result.ref_max_pitch))
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = 'These are starting values \xe2\x80\x94 review and fine-tune the sliders as needed.'
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- YIN auto-tune from reference
----------------------------------------------------------------------
function AutoTuneYIN(audio_item, ref_notes)
    local yin_ctx, err = OpenYINContext(audio_item)
    if not yin_ctx then return nil, err end

    local sr  = yin_ctx.sr
    local nch = yin_ctx.nch

    local CANDIDATES_COARSE = {
        yin_threshold = { 0.05, 0.08, 0.10, 0.12, 0.15, 0.18, 0.20, 0.25, 0.30, 0.40 },
        yin_min_hz    = { 40, 60, 80, 100, 130, 160, 200 },
        yin_max_hz    = { 400, 600, 800, 1000, 1300, 1600, 2000 },
        yin_window_ms = { 10, 15, 20, 25, 30, 40, 50, 70 },
    }

    -- CMND cache keyed by window_ms. Built lazily; each entry is a list of
    -- per-note { d, n_samps, tau_max } or false when the note is too short.
    -- Computed up to tau for 40 Hz (the lowest possible candidate min freq) so
    -- that any min/max freq combination can be evaluated without re-reading audio.
    local cmnd_cache      = {}
    local MIN_HZ_ABSOLUTE = 40

    local function GetOrComputeCMND(window_ms)
        if cmnd_cache[window_ms] then return cmnd_cache[window_ms] end
        local entries = {}
        for ni, n in ipairs(ref_notes) do
            local note_len = n.e - n.s
            local win_s    = math.min(window_ms / 1000, note_len * 0.8)
            if win_s < 0.01 then
                entries[ni] = false
            else
                local n_samps = math.max(2, math.floor(win_s * sr))
                local tau_max = math.min(math.floor(sr / MIN_HZ_ABSOLUTE),
                                         math.floor(n_samps / 2) - 1)
                local t_off   = n.s + note_len * 0.3 - yin_ctx.item_pos
                if t_off < 0 then t_off = 0 end

                local buf = r.new_array(n_samps * nch)
                buf.clear()
                r.GetAudioAccessorSamples(yin_ctx.accessor, sr, nch, t_off, n_samps, buf)

                local mono = {}
                for i = 1, n_samps do
                    local s = 0
                    for c = 0, nch - 1 do s = s + buf[(i - 1) * nch + c + 1] end
                    mono[i] = nch > 1 and s / nch or s
                end

                local d = {}; d[0] = 0
                local running_sum = 0
                for tau = 1, tau_max do
                    local sq = 0
                    for j = 1, n_samps - tau do
                        local diff = mono[j] - mono[j + tau]
                        sq = sq + diff * diff
                    end
                    running_sum = running_sum + sq
                    d[tau] = running_sum > 0 and sq * tau / running_sum or 1
                end
                entries[ni] = { d = d, n_samps = n_samps, tau_max = tau_max }
            end
        end
        cmnd_cache[window_ms] = entries
        return entries
    end

    -- Scan a cached CMND with given freq/threshold bounds.
    -- Returns MIDI pitch or nil on fallback. No audio I/O.
    local function ScanCMND(e, tau_min, tau_max_eff, threshold, min_hz, max_hz)
        local d       = e.d
        local tau_est
        for tau = tau_min, tau_max_eff - 1 do
            if d[tau] < threshold then
                while tau < tau_max_eff and d[tau + 1] < d[tau] do tau = tau + 1 end
                tau_est = tau
                break
            end
        end
        if not tau_est then
            local min_d, min_tau = math.huge, tau_min
            for tau = tau_min, tau_max_eff do
                if d[tau] < min_d then min_d = d[tau]; min_tau = tau end
            end
            if min_d > 0.5 then return nil end
            tau_est = min_tau
        end
        if tau_est > tau_min and tau_est < tau_max_eff then
            local s0, s1, s2 = d[tau_est - 1], d[tau_est], d[tau_est + 1]
            local denom = 2 * s1 - s0 - s2
            if math.abs(denom) > 1e-10 then
                tau_est = tau_est + (s0 - s2) / (2 * denom)
            end
        end
        local freq = sr / tau_est
        if freq < min_hz or freq > max_hz then return nil end
        return math.floor(69 + 12 * math.log(freq / 440) / math.log(2) + 0.5)
    end

    -- Score params using cached CMNDs; no audio access after first call per window_ms.
    local function EvalYIN(params)
        if params.yin_min_hz >= params.yin_max_hz then return nil end
        local entries    = GetOrComputeCMND(params.yin_window_ms)
        local tau_min    = math.max(1, math.floor(sr / params.yin_max_hz))
        local tau_max_hz = math.floor(sr / params.yin_min_hz)
        local total      = 0
        for ni, n in ipairs(ref_notes) do
            local e = entries[ni]
            if not e then
                total = total + 6
            else
                local tau_max = math.min(tau_max_hz, e.tau_max, math.floor(e.n_samps / 2) - 1)
                if tau_max < tau_min then
                    total = total + 6
                else
                    local p = ScanCMND(e, tau_min, tau_max, params.yin_threshold,
                                       params.yin_min_hz, params.yin_max_hz)
                    if p then
                        local diff = math.abs(p - n.pitch) % 12
                        total = total + math.min(diff, 12 - diff)
                    else
                        total = total + 6
                    end
                end
            end
        end
        return total
    end

    local best = {
        yin_threshold = S.yin_threshold,
        yin_min_hz    = S.yin_min_freq,
        yin_max_hz    = S.yin_max_freq,
        yin_window_ms = S.yin_window_ms,
    }
    local best_score = EvalYIN(best) or math.huge

    local function SweepParam(name, candidates)
        for _, val in ipairs(candidates) do
            if val ~= best[name] then
                local trial = {}
                for k, v in pairs(best) do trial[k] = v end
                trial[name] = val
                local sc = EvalYIN(trial)
                if sc and sc < best_score then
                    best       = trial
                    best_score = sc
                end
            end
        end
    end

    for _ = 1, 2 do
        SweepParam('yin_threshold', CANDIDATES_COARSE.yin_threshold)
        SweepParam('yin_min_hz',    CANDIDATES_COARSE.yin_min_hz)
        SweepParam('yin_max_hz',    CANDIDATES_COARSE.yin_max_hz)
        SweepParam('yin_window_ms', CANDIDATES_COARSE.yin_window_ms)
    end

    SweepParam('yin_threshold', FineCandidates(best.yin_threshold,
        { -0.04, -0.02, -0.01, 0.01, 0.02, 0.04 }, 0.01, 0.5))
    SweepParam('yin_min_hz', FineCandidates(best.yin_min_hz,
        { -20, -10, 10, 20 }, 40, 400))
    SweepParam('yin_max_hz', FineCandidates(best.yin_max_hz,
        { -100, -50, 50, 100 }, 200, 2000))
    SweepParam('yin_window_ms', FineCandidates(best.yin_window_ms,
        { -10, -5, 5, 10 }, 10, 100))

    -- All audio access is done; close accessor before the stats pass.
    CloseYINContext(yin_ctx)

    -- Final pass at best params from cached CMNDs for detailed result panel stats.
    local final_entries = cmnd_cache[best.yin_window_ms]
    local tau_min_final = math.max(1, math.floor(sr / best.yin_max_hz))
    local tau_max_hz_f  = math.floor(sr / best.yin_min_hz)

    local final_detected    = 0
    local final_fallback    = 0
    local pc_hits           = 0
    local octave_mismatches = 0
    local ref_min_pitch     = math.huge
    local ref_max_pitch     = -math.huge

    for ni, n in ipairs(ref_notes) do
        ref_min_pitch = math.min(ref_min_pitch, n.pitch)
        ref_max_pitch = math.max(ref_max_pitch, n.pitch)
        local e = final_entries and final_entries[ni]
        local p
        if e then
            local tau_max = math.min(tau_max_hz_f, e.tau_max, math.floor(e.n_samps / 2) - 1)
            if tau_max >= tau_min_final then
                p = ScanCMND(e, tau_min_final, tau_max, best.yin_threshold,
                             best.yin_min_hz, best.yin_max_hz)
            end
        end
        if p then
            final_detected = final_detected + 1
            local diff   = math.abs(p - n.pitch) % 12
            local pc_err = math.min(diff, 12 - diff)
            if pc_err == 0 then
                pc_hits = pc_hits + 1
                if p ~= n.pitch then octave_mismatches = octave_mismatches + 1 end
            end
        else
            final_fallback = final_fallback + 1
        end
    end

    return {
        params            = best,
        score             = best_score,
        ref_count         = #ref_notes,
        detected          = final_detected,
        fallback          = final_fallback,
        pc_hits           = pc_hits,
        octave_mismatches = octave_mismatches,
        ref_min_pitch     = ref_min_pitch,
        ref_max_pitch     = ref_max_pitch,
    }
end
