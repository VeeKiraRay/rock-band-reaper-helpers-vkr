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
        S.last_result = ('SONG AUDIO has %d items — expected exactly one.'):format(ref_count)
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
    r.Undo_BeginBlock()

    local lines = {}
    lines[#lines + 1] = ('SONG AUDIO position: %s'):format(FormatTime(ref_pos))
    lines[#lines + 1] = ''
    local changed = 0

    for _, entry in ipairs(candidates) do
        local count = r.CountTrackMediaItems(entry.track)
        if count == 0 then
            lines[#lines + 1] = ('  %s: no items — skipped.'):format(entry.name)
        elseif count > 1 then
            lines[#lines + 1] = ('  %s: %d items (expected 1) — skipped.'):format(entry.name, count)
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

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock(('Align audio tracks to SONG AUDIO (%d moved)'):format(changed), -1)

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
    r.Undo_BeginBlock()

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

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock(('Align all audio (%d moved)'):format(changed), -1)

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
    r.Undo_BeginBlock()

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
        lines[#lines + 1] = ('WARNING: %d clip%s beyond the %d-slot limit — left untouched.'):format(
            extra, extra == 1 and '' or 's', #slots)
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock(('Align COUNT IN (%d moved)'):format(changed), -1)

    S.status = changed > 0
        and ('Aligned %d COUNT IN clip%s.'):format(changed, changed == 1 and '' or 's')
        or  'COUNT IN clips already in place.'
    S.last_result = table.concat(lines, '\n')
end
