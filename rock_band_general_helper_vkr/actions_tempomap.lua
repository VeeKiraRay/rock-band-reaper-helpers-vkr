-- Tempo map action functions (Tempo Map tab)
-- Requires: S, r, FormatTime, GetTimeSelection (globals)
-- Requires: GetTempoContextBefore, GetMeasureStartTime (from helpers.lua)
-- Requires: ComputeTempoRMSContour, DetectOnsets, EstimateBPM, GuessTimeSig,
--           GetSourcesForRange, FitBeatGrid (from tempomap.lua)

local BPM_MIN, BPM_MAX = 60, 250

-- Read-only: show the tempo context and first-measure anchor time.
function ShowTempoContext()
    local sel_s = GetTimeSelection()
    local query_t = sel_s or 0.0
    local bpm, num, denom, marker_t = GetTempoContextBefore(query_t)
    if not bpm then
        S.status = 'Error: ' .. (num or 'no tempo markers found.')
        S.last_result = nil
        return
    end

    local eff_num = (S.tm_timesig_num > 0) and S.tm_timesig_num or num

    local first_gen_measure
    if sel_s then
        local mbt = r.format_timestr_pos(sel_s, '', 1)
        local current_measure = tonumber(mbt:match('^(%d+)')) or 1
        local measure_start_t = GetMeasureStartTime(current_measure, eff_num, denom)
        if math.abs(sel_s - measure_start_t) < 0.001 then
            first_gen_measure = current_measure
        else
            first_gen_measure = current_measure + 1
        end
    else
        first_gen_measure = S.tm_first_measure
    end

    local measure_t = GetMeasureStartTime(first_gen_measure, eff_num, denom)
    local beat_dur  = 60.0 / bpm

    local lines = {}
    lines[#lines + 1] = ('Query position: %s'):format(
        sel_s and FormatTime(sel_s) or 'project start')
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Tempo context at that position:'
    lines[#lines + 1] = ('  BPM:            %.3f'):format(bpm)
    lines[#lines + 1] = ('  Time signature: %d/%d'):format(num, denom)
    lines[#lines + 1] = ('  Marker at:      %s'):format(FormatTime(marker_t))
    lines[#lines + 1] = ('  Beat duration:  %.4fs  (%.1f ms)'):format(beat_dur, beat_dur * 1000)
    lines[#lines + 1] = ('  Measure dur:    %.4fs  (%.1f ms)'):format(
        beat_dur * eff_num, beat_dur * eff_num * 1000)
    lines[#lines + 1] = ''
    if sel_s then
        lines[#lines + 1] = ('First generated measure: %d  (auto from time selection)'):format(first_gen_measure)
    else
        lines[#lines + 1] = ('First generated measure: %d  (from "First measure" slider)'):format(first_gen_measure)
    end
    lines[#lines + 1] = ('  Measure start:  %s'):format(FormatTime(measure_t))
    if S.tm_timesig_num > 0 then
        lines[#lines + 1] = ('  (numerator override: %d  —  project marker is %d/%d)'):format(
            S.tm_timesig_num, num, denom)
    end
    if measure_t < 2.5 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('WARNING: measure %d starts at %.3fs — community guideline'):format(
            first_gen_measure, measure_t)
        lines[#lines + 1] = '  requires at least 2.5s before the first tempo marker.'
        lines[#lines + 1] = ('  Consider using measure %d or later.'):format(first_gen_measure + 1)
    end

    S.status = ('%.3f BPM  %d/%d  —  m%d starts at %s'):format(
        bpm, num, denom, first_gen_measure, FormatTime(measure_t))
    S.last_result = table.concat(lines, '\n')
end

-- Read-only: detect onsets and report BPM and time-signature estimates.
function EstimateInitialBPM()
    local track, source_name
    for _, field in ipairs({'tm_kick_idx','tm_snare_idx','tm_kit_idx','tm_fallback_idx'}) do
        local idx = S[field]
        if idx >= 0 then
            local tr = r.GetTrack(0, idx)
            if tr and r.CountTrackMediaItems(tr) > 0 then
                track = tr
                _, source_name = r.GetTrackName(tr)
                break
            end
        end
    end
    if not track then
        S.status = 'Error: no audio track selected.'
        S.last_result = 'Select at least one audio track in the dropdowns first.'
        return
    end

    local audio_item = r.GetTrackMediaItem(track, 0)
    if not audio_item then
        S.status = 'Error: no audio item on ' .. source_name .. '.'
        S.last_result = source_name .. ' has no audio items.'
        return
    end
    local item_pos = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION')
    local item_end = item_pos + r.GetMediaItemInfo_Value(audio_item, 'D_LENGTH')

    local bpm_ctx, num_ctx, denom_ctx = GetTempoContextBefore(item_pos)
    if not bpm_ctx then
        S.status = 'Error: no tempo markers found.'
        S.last_result = 'Add at least one tempo marker to the project before running Estimate BPM.'
        return
    end
    local eff_num = (S.tm_timesig_num > 0) and S.tm_timesig_num or num_ctx

    local window_s = S.tm_rms_window_ms / 1000.0

    local ci_whole, werr = ComputeTempoRMSContour(audio_item, item_pos, item_end, window_s)
    if not ci_whole then
        S.status = 'Error: ' .. werr
        S.last_result = werr
        return
    end
    local onsets_whole  = DetectOnsets(ci_whole, S.tm_rms_threshold, 0.05)
    local bpm_whole, conf_whole = EstimateBPM(onsets_whole)
    local ts_num_whole
    if bpm_whole then
        local anchor_whole = GetMeasureStartTime(1, eff_num, denom_ctx)
        ts_num_whole = GuessTimeSig(onsets_whole, 60.0 / bpm_whole, anchor_whole)
    end

    local sel_s, sel_e = GetTimeSelection()
    local ci_local, onsets_local
    local t_s_local, t_e_local, window_desc

    if sel_s then
        t_s_local   = math.max(sel_s, item_pos)
        t_e_local   = math.min(sel_e, item_end)
        window_desc = 'time selection'
        ci_local    = ComputeTempoRMSContour(audio_item, t_s_local, t_e_local, window_s)
        if ci_local then
            onsets_local = DetectOnsets(ci_local, S.tm_rms_threshold, 0.05)
        end
    else
        local scan_m     = S.tm_first_measure
        local fallback_m = nil
        local stable_m   = nil
        local prev_m, prev_count = nil, 0

        while scan_m <= 30 and not stable_m do
            local m_s = GetMeasureStartTime(scan_m,     eff_num, denom_ctx)
            local m_e = GetMeasureStartTime(scan_m + 1, eff_num, denom_ctx)
            local ts  = math.max(m_s, item_pos)
            local te  = math.min(m_e, item_end)
            if ts >= te then break end

            local ci_m    = ComputeTempoRMSContour(audio_item, ts, te, window_s)
            local count_m = (ci_m and #DetectOnsets(ci_m, S.tm_rms_threshold, 0.05)) or 0

            if count_m > 0 then
                if fallback_m == nil then fallback_m = scan_m end
                if prev_m ~= nil and count_m == prev_count then
                    stable_m = prev_m
                else
                    prev_m     = scan_m
                    prev_count = count_m
                end
            else
                prev_m     = nil
                prev_count = 0
            end
            scan_m = scan_m + 1
        end

        local win_m = stable_m or fallback_m
        if win_m then
            local m_s = GetMeasureStartTime(win_m,     eff_num, denom_ctx)
            local m_e = GetMeasureStartTime(win_m + 5, eff_num, denom_ctx)
            local ts  = math.max(m_s, item_pos)
            local te  = math.min(m_e, item_end)
            if ts < te then
                local ci_try  = ComputeTempoRMSContour(audio_item, ts, te, window_s)
                local ons_try = ci_try and DetectOnsets(ci_try, S.tm_rms_threshold, 0.05) or {}
                if #ons_try > 0 then
                    t_s_local    = ts
                    t_e_local    = te
                    ci_local     = ci_try
                    onsets_local = ons_try
                    if stable_m ~= nil and fallback_m ~= nil and stable_m ~= fallback_m then
                        window_desc = ('m%d – m%d  (m%d partial entry, skipped)'):format(
                            win_m, win_m + 5, fallback_m)
                    else
                        window_desc = ('m%d – m%d'):format(win_m, win_m + 5)
                    end
                end
            end
        end
    end

    local lines = {}
    lines[#lines + 1] = ('Source:  %s'):format(source_name)
    lines[#lines + 1] = ''

    if bpm_whole then
        local dev = math.min(
            math.abs(bpm_whole       - bpm_ctx),
            math.abs(bpm_whole * 2.0 - bpm_ctx),
            math.abs(bpm_whole / 2.0 - bpm_ctx))
        if dev > 10 then
            lines[#lines + 1] = ('WARNING: estimated BPM (%d) differs from project tempo (%.0f) by %.0f.'):format(
                bpm_whole, bpm_ctx, dev)
            lines[#lines + 1] = 'Local window scan used project measure boundaries — onset'
            lines[#lines + 1] = 'measure labels may not match actual song measures.'
            lines[#lines + 1] = 'If the estimated BPM looks correct, apply it to the project'
            lines[#lines + 1] = '(add a tempo marker), then re-run for accurate time signature results.'
            lines[#lines + 1] = ''
        end
    end

    lines[#lines + 1] = '--- Whole song ---'
    lines[#lines + 1] = ('Contour:   %d windows @ %.0f ms'):format(#ci_whole.contour, window_s * 1000)
    lines[#lines + 1] = ('Onsets:    %d  (not listed)'):format(#onsets_whole)
    if bpm_whole then
        lines[#lines + 1] = ('Est. BPM:  %d  (conf %.0f%%)'):format(bpm_whole, conf_whole * 100)
        if bpm_whole * 2 <= BPM_MAX then
            lines[#lines + 1] = ('Alt. BPM:  %d  (×2)'):format(bpm_whole * 2)
        end
        lines[#lines + 1] = ('Time sig:  %d/4 guess'):format(ts_num_whole or 4)
    else
        lines[#lines + 1] = 'Est. BPM:  insufficient onsets'
    end
    lines[#lines + 1] = ''

    if ci_local and onsets_local then
        local bpm_local, conf_local = EstimateBPM(onsets_local)
        lines[#lines + 1] = ('--- Local window (%s) ---'):format(window_desc)
        lines[#lines + 1] = ('Range:     %s — %s  (%.1fs)'):format(
            FormatTime(t_s_local), FormatTime(t_e_local), t_e_local - t_s_local)
        lines[#lines + 1] = ('Onsets:    %d'):format(#onsets_local)
        if bpm_local then
            lines[#lines + 1] = ('Est. BPM:  %d  (conf %.0f%%)'):format(bpm_local, conf_local * 100)
            if bpm_local * 2 <= BPM_MAX then
                lines[#lines + 1] = ('Alt. BPM:  %d  (×2)'):format(bpm_local * 2)
            end
            local ts_onsets = (bpm_whole and #onsets_whole > #onsets_local)
                              and onsets_whole or onsets_local
            local ts_anchor  = (ts_onsets == onsets_whole)
                              and GetMeasureStartTime(1, eff_num, denom_ctx) or t_s_local
            local ts_num_local = GuessTimeSig(ts_onsets, 60.0 / bpm_local, ts_anchor)
            lines[#lines + 1] = ('Time sig:  %d/4 guess'):format(ts_num_local)
        else
            lines[#lines + 1] = 'Est. BPM:  insufficient onsets'
        end
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Onset times:'
        local MAX_SHOW = 50
        local m_lines, m_num = {}, nil
        local function flush_m()
            if m_num and #m_lines > 0 then
                lines[#lines + 1] = ('  m%d  —  %d onset%s'):format(
                    m_num, #m_lines, #m_lines == 1 and '' or 's')
                for _, l in ipairs(m_lines) do lines[#lines + 1] = l end
                lines[#lines + 1] = ''
            end
            m_lines = {}
        end
        local shown = 0
        local ONSET_GRACE_S_local = 0.05
        for k, t in ipairs(onsets_local) do
            if shown >= MAX_SHOW then
                flush_m()
                lines[#lines + 1] = ('  ... (%d more not shown)'):format(#onsets_local - MAX_SHOW)
                break
            end
            local mbt      = r.format_timestr_pos(t, '', 1)
            local cur_m    = tonumber(mbt:match('^(%d+)')) or 1
            local next_m_t = GetMeasureStartTime(cur_m + 1, eff_num, denom_ctx)
            local early_ms = (next_m_t - t) * 1000
            if cur_m ~= m_num then flush_m(); m_num = cur_m end
            local line
            if early_ms > 0 and early_ms <= ONSET_GRACE_S_local * 1000 then
                line = ('    %3d  %s  (calc as m%d, %.0f ms early)'):format(
                    k, FormatTime(t), cur_m + 1, early_ms)
            else
                line = ('    %3d  %s'):format(k, FormatTime(t))
            end
            m_lines[#m_lines + 1] = line
            shown = shown + 1
        end
        flush_m()
    else
        lines[#lines + 1] = '--- Local window ---'
        if sel_s then
            lines[#lines + 1] = 'No onsets found in time selection. Try lowering the RMS threshold.'
        else
            lines[#lines + 1] = ('No onsets found scanning m%d – m25.'):format(S.tm_first_measure)
            lines[#lines + 1] = 'Try lowering the RMS threshold or adjusting "First measure".'
        end
    end

    local status_bpm = bpm_whole and ('%d'):format(bpm_whole) or '?'
    S.status = ('Est. BPM: %s  —  %d onsets (whole song)  from %s'):format(
        status_bpm, #onsets_whole, source_name)
    S.last_result = table.concat(lines, '\n')
end

function ClearGeneratedTempoMarkers()
    local n = r.CountTempoTimeSigMarkers(0)
    if n <= 1 then
        S.status = 'Nothing to clear — only the root marker exists.'
        S.last_result = nil
        return
    end
    local sel_s, sel_e = GetTimeSelection()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local deleted = 0
    for i = n - 1, 1, -1 do
        local ok, tp = r.GetTempoTimeSigMarker(0, i)
        if ok then
            local in_range = (not sel_s) or (tp >= sel_s and tp < sel_e)
            if in_range then
                r.DeleteTempoTimeSigMarker(0, i)
                deleted = deleted + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock(('Clear tempo markers: %d removed'):format(deleted), -1)
    if deleted == 0 then
        S.status = 'No markers in selection to clear.'
    elseif sel_s then
        S.status = ('Cleared %d marker%s in selection.'):format(deleted, deleted == 1 and '' or 's')
    else
        S.status = ('Cleared %d tempo marker%s — root marker kept.'):format(
            deleted, deleted == 1 and '' or 's')
    end
    S.last_result = nil
end

function GenerateTempoMap()
    local primary_track, primary_name
    for _, field in ipairs({'tm_kick_idx','tm_snare_idx','tm_kit_idx','tm_fallback_idx'}) do
        local idx = S[field]
        if idx >= 0 then
            local tr = r.GetTrack(0, idx)
            if tr and r.CountTrackMediaItems(tr) > 0 then
                primary_track = tr
                _, primary_name = r.GetTrackName(tr)
                break
            end
        end
    end
    if not primary_track then
        S.status = 'Error: no audio track selected.'
        S.last_result = 'Select at least one audio track (KICK, SNARE, KIT, or fallback).'
        return
    end
    local audio_item = r.GetTrackMediaItem(primary_track, 0)
    local item_pos = r.GetMediaItemInfo_Value(audio_item, 'D_POSITION')
    local item_end = item_pos + r.GetMediaItemInfo_Value(audio_item, 'D_LENGTH')

    local sel_s, sel_e = GetTimeSelection()
    local t_s = sel_s and math.max(sel_s, item_pos) or item_pos
    local t_e = sel_e and math.min(sel_e, item_end) or item_end
    if t_s >= t_e then
        S.status = 'Error: empty analysis range.'
        S.last_result = 'Time selection does not overlap the audio item.'
        return
    end

    local bpm_ctx, num_ctx, denom_ctx = GetTempoContextBefore(t_s)
    if not bpm_ctx then
        S.status = 'Error: no tempo markers found.'
        S.last_result = 'Add at least one tempo marker to the project first.'
        return
    end
    local eff_num = (S.tm_timesig_num > 0) and S.tm_timesig_num or num_ctx

    local window_s        = S.tm_rms_window_ms / 1000.0
    local search_window_s = S.tm_search_window_ms / 1000.0

    local ci_whole = ComputeTempoRMSContour(audio_item, item_pos, item_end, window_s)
    if not ci_whole then
        S.status = 'Error: could not analyse audio.'
        return
    end
    local onsets_whole = DetectOnsets(ci_whole, S.tm_rms_threshold, 0.05)
    local bpm_est      = EstimateBPM(onsets_whole)

    local bpm_fit, bpm_fit_note
    if bpm_est then
        local best_bpm, best_dev, best_note = bpm_est, math.abs(bpm_est - bpm_ctx), ''
        for _, c in ipairs({{bpm_est * 2.0, ' (est x2, closer to project BPM)'},
                             {bpm_est / 2.0, ' (est /2, closer to project BPM)'}}) do
            local cand, note = c[1], c[2]
            if cand >= BPM_MIN and cand <= BPM_MAX then
                local dev = math.abs(cand - bpm_ctx)
                if dev < best_dev then best_dev = dev; best_bpm = cand; best_note = note end
            end
        end
        bpm_fit      = best_bpm
        bpm_fit_note = best_note
    else
        bpm_fit      = bpm_ctx
        bpm_fit_note = '  (project fallback — estimation failed)'
    end
    local beat_dur = 60.0 / bpm_fit

    local sources = GetSourcesForRange(t_s, t_e, window_s)
    if #sources == 0 then
        S.status = 'Error: no onsets in analysis range.'
        S.last_result = 'No onsets detected in any source track. Try lowering RMS threshold or using a time selection.'
        return
    end

    local anchor_target
    if sel_s then
        local mbt         = r.format_timestr_pos(t_s, '', 1)
        local cur_m       = tonumber(mbt:match('^(%d+)')) or 1
        local cur_m_t     = GetMeasureStartTime(cur_m, eff_num, denom_ctx)
        if math.abs(t_s - cur_m_t) < 0.001 then
            anchor_target = cur_m_t
        else
            anchor_target = GetMeasureStartTime(cur_m + 1, eff_num, denom_ctx)
        end
    else
        anchor_target = GetMeasureStartTime(S.tm_first_measure, eff_num, denom_ctx)
    end
    local anchor_t       = anchor_target
    local anchor_snapped = false
    local anchor_source  = nil
    local best_snap_d    = search_window_s
    for _, src in ipairs(sources) do
        for _, ot in ipairs(src.onsets) do
            local d = math.abs(ot - anchor_target)
            if d < best_snap_d then
                best_snap_d = d; anchor_t = ot
                anchor_snapped = true; anchor_source = src.name
            end
        end
        if anchor_snapped then break end
    end

    local grid = FitBeatGrid(anchor_t, t_e, beat_dur, eff_num, sources, search_window_s)

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local n = r.CountTempoTimeSigMarkers(0)
    local delete_count = 0
    for i = n - 1, 0, -1 do
        local ok, tp = r.GetTempoTimeSigMarker(0, i)
        if ok and tp >= t_s and tp < t_e then
            r.DeleteTempoTimeSigMarker(0, i)
            delete_count = delete_count + 1
        end
    end

    local inserts    = {{t = anchor_t}}
    local stopped_at = nil

    for _, entry in ipairs(grid) do
        if entry.detected_t then
            local dev_ms = math.abs(entry.deviation_s) * 1000
            if dev_ms > S.tm_drift_threshold_ms then
                if not S.tm_override_failsafe and
                        math.abs(entry.bpm - bpm_fit) > S.tm_bpm_failsafe then
                    stopped_at = entry
                    break
                end
                inserts[#inserts + 1] = {t = entry.detected_t}
            end
        end
    end

    local measure_dur_est = eff_num * 60.0 / bpm_fit
    for i = 1, #inserts do
        if inserts[i + 1] then
            local span = inserts[i + 1].t - inserts[i].t
            local n    = math.max(1, math.floor(span / measure_dur_est + 0.5))
            inserts[i].bpm = n * eff_num * 60.0 / span
        else
            inserts[i].bpm = bpm_fit
        end
    end

    for _, ins in ipairs(inserts) do
        r.AddTempoTimeSigMarker(0, ins.t, ins.bpm, eff_num, denom_ctx, false)
    end
    local inserted = #inserts

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock(('Generate tempo map: %d marker%s'):format(
        inserted, inserted == 1 and '' or 's'), -1)

    local source_names = {}
    for _, src in ipairs(sources) do source_names[#source_names + 1] = src.name end
    local lines = {}
    lines[#lines + 1] = ('BPM src:  %s  (BPM estimation)'):format(primary_name)
    lines[#lines + 1] = ('Sources:  %s'):format(table.concat(source_names, ', '))
    lines[#lines + 1] = ('BPM used: %.1f%s'):format(bpm_fit, bpm_fit_note)
    lines[#lines + 1] = ('Time sig: %d/%d'):format(eff_num, denom_ctx)
    lines[#lines + 1] = ('Range:    %s — %s  (%.1fs)'):format(
        FormatTime(t_s), FormatTime(t_e), t_e - t_s)
    lines[#lines + 1] = ('Deleted:  %d existing marker%s in range'):format(
        delete_count, delete_count == 1 and '' or 's')
    lines[#lines + 1] = ('Inserted: %d marker%s  (* = marker inserted)'):format(
        inserted, inserted == 1 and '' or 's')
    if stopped_at then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('STOPPED at %s: BPM jumped to %.1f (failsafe ±%.1f).'):format(
            FormatTime(stopped_at.expected_t), stopped_at.bpm, S.tm_bpm_failsafe)
        lines[#lines + 1] = 'Enable "Override BPM limit" to continue past tempo jumps.'
    end
    lines[#lines + 1] = ''
    local anchor_dev_ms = (anchor_t - anchor_target) * 1000
    if anchor_snapped then
        lines[#lines + 1] = ('Anchor:  * %s  (snapped to %s, %+.0f ms from measure)'):format(
            FormatTime(anchor_t), anchor_source, anchor_dev_ms)
    else
        lines[#lines + 1] = ('Anchor:  * %s  (no onset nearby — using project measure boundary)'):format(
            FormatTime(anchor_t))
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Measure grid:  (* = marker inserted,  src shown when not primary)'
    local primary_src_name = sources[1] and sources[1].name or primary_name
    for _, entry in ipairs(grid) do
        local mbt   = r.format_timestr_pos(entry.expected_t, '', 1)
        local m_num = tonumber(mbt:match('^(%d+)')) or 0
        if entry.detected_t then
            local dev_ms  = entry.deviation_s * 1000
            local mark    = math.abs(dev_ms) > S.tm_drift_threshold_ms and '*' or ' '
            local src_tag = (entry.source and entry.source ~= primary_src_name)
                            and ('  [%s]'):format(entry.source) or ''
            lines[#lines + 1] = ('  %s m%d  %s  dev %+.0f ms  %.1f BPM%s'):format(
                mark, m_num, FormatTime(entry.detected_t), dev_ms, entry.bpm, src_tag)
        else
            lines[#lines + 1] = ('    m%d  %s  no onset — extrapolated'):format(
                m_num, FormatTime(entry.expected_t))
        end
        if entry == stopped_at then break end
    end

    S.status = ('Generated %d marker%s from %s'):format(
        inserted, inserted == 1 and '' or 's', table.concat(source_names, '/'))
    S.last_result = table.concat(lines, '\n')
end
