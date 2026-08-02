-- Guitar validation action helpers (called by ValidateGuitar)
----------------------------------------------------------------------
-- Validation
----------------------------------------------------------------------

-- Returns sustain tail threshold (seconds), minimum gap after sustain, minimum note length.
-- Sustain threshold: note must be LONGER than this to show a tail.
-- >100 BPM: dotted 8th note; <=100 BPM: 3/16th note (per updated authoring rules).
-- Min gap after sustain: 1/32nd note (standard: 1/16th).
-- Min note length: 1/64th note.
function SustainThresholds(time)
    local bpm         = GetBPMAt(time)
    local beat_s      = 60 / bpm
    local sixteenth   = beat_s / 4
    local eighth      = beat_s / 2
    local dot_eighth  = eighth * 1.5
    local three16th   = sixteenth * 3
    local thirtysec   = beat_s / 8
    local sixtyfourth = beat_s / 16
    local sustain_thresh = (bpm > 100) and dot_eighth or three16th
    return sustain_thresh, thirtysec, sixtyfourth
end

function ReadRBGuitarNotes(track, t_s, t_e)
    local notes = {}
    local keep  = {}
    for p = 96, 103 do keep[p] = true end
    keep[126] = true; keep[127] = true

    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and keep[pitch] then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = { s = s, e = e, pitch = pitch }
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.pitch < b.pitch
    end)
    return notes
end

function RunValidation(notes)
    local violations = {}
    local function add(s, msg)
        violations[#violations + 1] = r.format_timestr_pos(s, '', 1) .. '  ' .. msg
    end

    -- Group gem notes (96-100) into chord events; skip marker pitches
    local events = {}
    local i = 1
    while i <= #notes do
        local n = notes[i]
        if n.pitch >= GEM_MIN and n.pitch <= GEM_MAX then
            local ev = { s = n.s, e = n.e, pitches = { n.pitch } }
            local j  = i + 1
            while j <= #notes and (notes[j].s - ev.s) <= CHORD_WINDOW_S do
                if notes[j].pitch >= GEM_MIN and notes[j].pitch <= GEM_MAX then
                    ev.pitches[#ev.pitches + 1] = notes[j].pitch
                    if notes[j].e > ev.e then ev.e = notes[j].e end
                end
                j = j + 1
            end
            table.sort(ev.pitches)
            events[#events + 1] = ev
            i = j
        else
            i = i + 1
        end
    end

    local prev_ev = nil
    for _, ev in ipairs(events) do
        local dur = ev.e - ev.s

        -- Max 3 notes per chord
        if #ev.pitches > 3 then
            local parts = {}
            for _, p in ipairs(ev.pitches) do parts[#parts + 1] = GEM_LETTERS[p - GEM_MIN] end
            add(ev.s, string.format('Chord has %d notes (max 3): [%s]',
                #ev.pitches, table.concat(parts, '+')))
        end

        -- Illegal G+O 3-note chord
        if #ev.pitches == 3 and ev.pitches[1] == 96 and ev.pitches[3] == 100 then
            add(ev.s, 'Illegal 3-note chord: Green+Orange combination not allowed')
        end

        -- Minimum note length: 1/64th
        local _, _, note_min_s = SustainThresholds(ev.s)
        if dur < note_min_s - 0.001 then
            add(ev.s, string.format('Note too short: %.1f ms (min 1/64th ~ %.1f ms)',
                dur * 1000, note_min_s * 1000))
        end

        -- Overlap with previous event
        if prev_ev and ev.s < prev_ev.e - 0.001 then
            add(ev.s, string.format('Overlap: starts %.1f ms before previous event ends',
                (prev_ev.e - ev.s) * 1000))
        end

        -- Gap after previous sustain (1/32nd minimum, standard 1/16th)
        if prev_ev then
            local sustain_thresh, gap_min_s = SustainThresholds(prev_ev.s)
            if (prev_ev.e - prev_ev.s) > sustain_thresh + 0.001 then
                local gap = ev.s - prev_ev.e
                if gap < gap_min_s - 0.001 then
                    add(ev.s, string.format(
                        'Gap after sustain too small: %.1f ms (min 1/32nd ~ %.1f ms)',
                        gap * 1000, gap_min_s * 1000))
                end
            end
        end

        prev_ev = ev
    end

    return violations, #events
end
