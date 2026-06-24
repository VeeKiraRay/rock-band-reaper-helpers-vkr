-- Alignment action functions (General tab)
-- Requires: S, r, FormatTime, GetTimeSelection (globals)
-- Requires: FindTrackByName, GetAudioItems, GetTempoContextBefore (from helpers.lua)

-- Compute beat-slot positions (0-indexed total beats from project start)
-- for COUNT IN clips given a time signature numerator.
local function CountInBeatSlots(num)
    local slots = {0}
    if num >= 4 and num % 2 == 0 then
        slots[#slots + 1] = num / 2
    end
    for b = 0, num - 1 do
        if #slots >= 6 then break end
        slots[#slots + 1] = num + b
    end
    return slots
end

-- Align the audio item on each selected drum track to the SONG AUDIO start position.
function AlignAudioTracks()
    local ref_track = FindTrackByName('SONG AUDIO')
    if not ref_track then
        S.status = 'Error: SONG AUDIO track not found.'
        S.last_result = 'Could not find a track named "SONG AUDIO".'
        return
    end

    local ref_count = r.CountTrackMediaItems(ref_track)
    if ref_count == 0 then
        S.status = 'Error: SONG AUDIO has no items.'
        S.last_result = 'SONG AUDIO track has no audio items.'
        return
    end
    if ref_count > 1 then
        S.status = 'Error: SONG AUDIO has multiple items.'
        S.last_result = ('SONG AUDIO has %d items - expected exactly one.'):format(ref_count)
        return
    end

    local ref_item = r.GetTrackMediaItem(ref_track, 0)
    local ref_pos  = r.GetMediaItemInfo_Value(ref_item, 'D_POSITION')

    local candidates = {}
    local idx_fields = { 'tm_kick_idx', 'tm_snare_idx', 'tm_kit_idx', 'tm_fallback_idx' }
    for _, field in ipairs(idx_fields) do
        local idx = S[field]
        if idx >= 0 then
            local tr = r.GetTrack(0, idx)
            if tr then
                local _, name = r.GetTrackName(tr)
                candidates[#candidates + 1] = { track = tr, name = name }
            end
        end
    end

    if #candidates == 0 then
        S.status = 'No audio tracks selected.'
        S.last_result = 'Select at least one audio track in the dropdowns first.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local lines = {}
    lines[#lines + 1] = ('SONG AUDIO position: %s'):format(FormatTime(ref_pos))
    lines[#lines + 1] = ''
    local changed = 0

    for _, entry in ipairs(candidates) do
        local count = r.CountTrackMediaItems(entry.track)
        if count == 0 then
            lines[#lines + 1] = ('  %s: no items - skipped.'):format(entry.name)
        elseif count > 1 then
            lines[#lines + 1] = ('  %s: %d items (expected 1) - skipped.'):format(entry.name, count)
        else
            local item = r.GetTrackMediaItem(entry.track, 0)
            local pos  = r.GetMediaItemInfo_Value(item, 'D_POSITION')
            if math.abs(pos - ref_pos) < 0.0001 then
                lines[#lines + 1] = ('  %s: already aligned at %s.'):format(entry.name, FormatTime(pos))
            else
                r.SetMediaItemInfo_Value(item, 'D_POSITION', ref_pos)
                lines[#lines + 1] = ('  %s: aligned  (%s → %s)'):format(
                    entry.name, FormatTime(pos), FormatTime(ref_pos))
                changed = changed + 1
            end
        end
    end

    r.UpdateArrange()
    r.Undo_EndBlock2(0, ('Align audio tracks to SONG AUDIO (%d moved)'):format(changed), -1)
    r.PreventUIRefresh(-1)

    S.status = changed > 0
        and ('Aligned %d track(s) to SONG AUDIO.'):format(changed)
        or  'All selected tracks already aligned.'
    S.last_result = table.concat(lines, '\n')
end

-- Align every single-audio-item track in the project to the SONG AUDIO start.
function AlignAllAudio()
    local ref_track = FindTrackByName('SONG AUDIO')
    if not ref_track then
        S.status = 'Error: SONG AUDIO track not found.'
        S.last_result = 'Could not find a track named "SONG AUDIO".'
        return
    end
    local ref_audio = GetAudioItems(ref_track)
    if #ref_audio == 0 then
        S.status = 'Error: SONG AUDIO has no audio items.'
        S.last_result = 'SONG AUDIO track has no audio items.'
        return
    end
    local ref_pos = r.GetMediaItemInfo_Value(ref_audio[1], 'D_POSITION')

    local SKIP_NAMES = { ['SONG AUDIO'] = true, ['COUNT IN'] = true }

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local lines   = {}
    local changed = 0
    local multi   = {}

    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetTrackName(tr)
        if not SKIP_NAMES[name] then
            local audio = GetAudioItems(tr)
            if #audio == 1 then
                local pos = r.GetMediaItemInfo_Value(audio[1], 'D_POSITION')
                if math.abs(pos - ref_pos) < 0.0001 then
                    lines[#lines + 1] = ('  %-30s already aligned'):format(name)
                else
                    r.SetMediaItemInfo_Value(audio[1], 'D_POSITION', ref_pos)
                    lines[#lines + 1] = ('  %-30s aligned  (%s → %s)'):format(
                        name, FormatTime(pos), FormatTime(ref_pos))
                    changed = changed + 1
                end
            elseif #audio > 1 then
                multi[#multi + 1] = name
            end
        end
    end

    r.UpdateArrange()
    r.Undo_EndBlock2(0, ('Align all audio (%d moved)'):format(changed), -1)
    r.PreventUIRefresh(-1)

    table.insert(lines, 1, ('SONG AUDIO reference: %s'):format(FormatTime(ref_pos)))
    table.insert(lines, 2, '')
    if #multi > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Skipped (%d track%s with multiple audio items):'):format(
            #multi, #multi == 1 and '' or 's')
        for _, n in ipairs(multi) do
            lines[#lines + 1] = '  ' .. n
        end
    end
    S.status = changed > 0
        and ('Aligned %d track%s to SONG AUDIO.'):format(changed, changed == 1 and '' or 's')
        or  'All audio tracks already aligned (or none to align).'
    S.last_result = table.concat(lines, '\n')
end

-- Position COUNT IN clips at the standard count-in beat slots.
function AlignCountIn()
    local track = FindTrackByName('COUNT IN')
    if not track then
        S.status = 'Error: COUNT IN track not found.'
        S.last_result = 'Could not find a track named "COUNT IN".'
        return
    end

    local bpm, num, _, _ = GetTempoContextBefore(0)
    if not bpm then
        S.status = 'Error: no tempo marker found.'
        S.last_result = 'Add at least one tempo marker to the project first.'
        return
    end

    local audio = GetAudioItems(track)
    if #audio == 0 then
        S.status = 'COUNT IN has no audio items.'
        S.last_result = 'COUNT IN track has no audio items to position.'
        return
    end

    table.sort(audio, function(a, b)
        return r.GetMediaItemInfo_Value(a, 'D_POSITION') <
               r.GetMediaItemInfo_Value(b, 'D_POSITION')
    end)

    local slots    = CountInBeatSlots(num)
    local to_place = math.min(#audio, #slots)
    local extra    = #audio - to_place

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local lines = {}
    lines[#lines + 1] = ('Time signature: %d/4  (%d slots available)'):format(num, #slots)
    lines[#lines + 1] = ''

    local changed = 0
    for i = 1, to_place do
        local item      = audio[i]
        local beat      = slots[i]
        local target_t  = r.TimeMap2_beatsToTime(0, beat)
        local cur_pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local measure   = math.floor(beat / num) + 1
        local beat_in_m = (beat % num) + 1
        local slot_label = ('m%d b%d'):format(measure, beat_in_m)
        if math.abs(cur_pos - target_t) < 0.0001 then
            lines[#lines + 1] = ('  Clip %d  %-7s  %s  already in place'):format(
                i, slot_label, FormatTime(target_t))
        else
            r.SetMediaItemInfo_Value(item, 'D_POSITION', target_t)
            lines[#lines + 1] = ('  Clip %d  %-7s  %s  (was %s)'):format(
                i, slot_label, FormatTime(target_t), FormatTime(cur_pos))
            changed = changed + 1
        end
    end

    if extra > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('WARNING: %d clip%s beyond the %d-slot limit - left untouched.'):format(
            extra, extra == 1 and '' or 's', #slots)
    end

    r.UpdateArrange()
    r.Undo_EndBlock2(0, ('Align COUNT IN (%d moved)'):format(changed), -1)
    r.PreventUIRefresh(-1)

    S.status = changed > 0
        and ('Aligned %d COUNT IN clip%s.'):format(changed, changed == 1 and '' or 's')
        or  'COUNT IN clips already in place.'
    S.last_result = table.concat(lines, '\n')
end

-- Convert all 6/4 time signature markers to 3/4. MIDI note PPQ positions are unaffected.
function ConvertTimeSig6to3()
    local t_s, t_e = GetTimeSelection()

    local count = r.CountTempoTimeSigMarkers(0)
    local to_convert = {}
    for i = 0, count - 1 do
        local ok, tp, _, _, bpm, num, denom, linear = r.GetTempoTimeSigMarker(0, i)
        if ok and num == 6 and denom == 4 then
            if not t_s or (tp >= t_s and tp < t_e) then
                table.insert(to_convert, { idx = i, tp = tp, bpm = bpm, linear = linear })
            end
        end
    end

    if #to_convert == 0 then
        S.status = 'No 6/4 markers found' .. (t_s and ' in time selection' or '') .. '.'
        S.last_result = nil
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for i = #to_convert, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, to_convert[i].idx)
    end
    for _, m in ipairs(to_convert) do
        r.AddTempoTimeSigMarker(0, m.tp, m.bpm, 3, 4, m.linear)
    end
    r.UpdateArrange()
    r.Undo_EndBlock2(0, ('Convert %d tempo marker%s: 6/4 \xe2\x86\x92 3/4'):format(
        #to_convert, #to_convert == 1 and '' or 's'), -1)
    r.PreventUIRefresh(-1)

    S.status = ('Converted %d marker%s from 6/4 to 3/4.'):format(
        #to_convert, #to_convert == 1 and '' or 's')
    S.last_result = nil
end

-- Create a volume fade out on the SONG AUDIO track from time selection start to end.
function CreateSongFadeOut()
    local track = FindTrackByName('SONG AUDIO')
    if not track then
        S.status = 'Track "SONG AUDIO" not found.'
        return
    end

    local ts, te = GetTimeSelection()
    if not ts then
        S.status = 'No time selection. Select the fade range first.'
        return
    end

    -- REAPER creates envelope objects lazily; a track with no volume automation
    -- returns nil. Force creation by injecting a minimal VOLENV2 block into the
    -- track state chunk - no actions or track-selection side-effects.
    local env = r.GetTrackEnvelopeByName(track, 'Volume')
    if not env then
        local _, chunk = r.GetTrackStateChunk(track, '', false)
        if chunk and not chunk:find('<VOLENV') then
            local env_block = '<VOLENV2\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0 -1 -1\n>'
            -- chunk always ends with \n> (closing the <TRACK block); insert before it
            local pos = chunk:find('>%s*$')
            if pos then
                r.SetTrackStateChunk(track, chunk:sub(1, pos - 1) .. '\n' .. env_block .. '\n>', false)
            end
        end
        env = r.GetTrackEnvelopeByName(track, 'Volume')
    end
    if not env then
        S.status = 'Could not create Volume envelope on "SONG AUDIO".'
        return
    end

    r.Undo_BeginBlock2(0)
    r.DeleteEnvelopePointRange(env, ts, te + 1e-9)  -- +epsilon: range is exclusive at end

    -- Read the last envelope point strictly before ts and use its stored value
    -- directly. Envelope_Evaluate is unreliable here: a shape-3 (fast-start)
    -- point just before ts extrapolates the downward curve past itself, giving
    -- a near-zero reading even after the range is cleared.
    local vol_start = 1.0  -- default: unity / 0 dB
    local n_pts = r.CountEnvelopePoints(env)
    for i = n_pts - 1, 0, -1 do
        local ok, pt_time, pt_val = r.GetEnvelopePoint(env, i)
        if ok and pt_time < ts then
            vol_start = pt_val > 0 and pt_val or 1.0
            break
        end
    end

    -- shape 3 = fast start (convex): drops perceptibly from the start,
    -- matching dB-linear perception. Better than linear amplitude for short fades.
    r.InsertEnvelopePoint(env, ts, vol_start, 3, 0, false, true)
    r.InsertEnvelopePoint(env, te, 0.0,       0, 0, false, false)
    r.Envelope_SortPoints(env)
    r.Undo_EndBlock2(0, 'Create fade out on SONG AUDIO', -1)

    local dur = te - ts
    local dur_note
    if dur < 2 then
        dur_note = ('Duration: %.1fs - very short; likely to sound like a cut rather than a fade.'):format(dur)
    elseif dur > 8 then
        dur_note = ('Duration: %.1fs - quite long for a game fade out.'):format(dur)
    elseif dur > 5 then
        dur_note = ('Duration: %.1fs - on the longer side for a game ending; may feel like it lingers.'):format(dur)
    end

    S.status = ('Fade out: %s → %s'):format(FormatTime(ts), FormatTime(te))
    S.last_result = dur_note  -- nil when duration is in the ideal range (clears any prior result)
end
