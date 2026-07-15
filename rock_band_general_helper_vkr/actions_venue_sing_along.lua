-- Analysis tab action: derives VENUE sing-along notes (pitch 87 = guitarist, pitch 85 =
-- bassist - same SING_PITCH_MAP convention as ReadSingNoteTimelines in venue_awareness.lua)
-- from HARM2/HARM3 vocal harmony content.
-- Requires: FindTrackByName, FindFirstMIDIItem, ClearNotesAtPitchesInRange, InsertNotes,
--           r, S (globals)

local RB3_VOCAL_MIN    = 36   -- C1, same vocal pitch range as PART VOCALS/HARM tracks
local RB3_VOCAL_MAX    = 84   -- C5
local RB3_PHRASE_PITCH = 105  -- phrase marker note; its own start/end is the phrase's start/end

-- Returns the take of an available source track (exists, unmuted, has a MIDI item), or nil.
local function AvailableHarmTake(track_name)
    local track = FindTrackByName(track_name)
    if not track then return nil end
    if r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then return nil end
    local _, take = FindFirstMIDIItem(track)
    return take
end

-- Returns phrase_markers ({s, e} in project time, sorted by s) and vocal_starts (sorted
-- project-time start positions of notes in the vocal range).
local function ReadPhrasesAndVocalNotes(take)
    local phrase_markers = {}
    local vocal_starts   = {}
    local _, note_cnt = r.MIDI_CountEvts(take)
    for i = 0, note_cnt - 1 do
        local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and not muted then
            if pitch == RB3_PHRASE_PITCH then
                phrase_markers[#phrase_markers + 1] = {
                    s = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                    e = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                }
            elseif pitch >= RB3_VOCAL_MIN and pitch <= RB3_VOCAL_MAX then
                vocal_starts[#vocal_starts + 1] = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            end
        end
    end
    table.sort(phrase_markers, function(a, b) return a.s < b.s end)
    table.sort(vocal_starts)
    return phrase_markers, vocal_starts
end

-- Returns the QN-length (converted to seconds) of the measure containing project time t.
-- Same forward-scan technique as FindNextMeasureStartPpq (venue_lighting.lua), tempo/time-sig
-- aware rather than assuming a fixed BPM.
local function MeasureDurationAtTime(t)
    local qn  = r.TimeMap_timeToQN(t)
    local est = math.max(0, math.floor(qn / 4) - 1)
    for m = est, est + 30 do
        local _, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, m)
        if not qn_s then break end
        if qn_e > qn + 1e-9 then
            return r.TimeMap_QNToTime(qn_e) - r.TimeMap_QNToTime(qn_s)
        end
    end
    return 2.0  -- fallback: ~one 4/4 measure at 120 BPM
end

-- Builds merged sing-along spans for one source track: a phrase qualifies when at least one
-- vocal note starts within it; consecutive qualifying phrases whose gap is <= one measure are
-- merged into a single continuous span. Returns (spans, qualifying_phrase_count).
local function BuildSpans(phrase_markers, vocal_starts, pitch)
    local qualifying = {}
    local vi = 1
    for _, pm in ipairs(phrase_markers) do
        while vi <= #vocal_starts and vocal_starts[vi] < pm.s do vi = vi + 1 end
        if vi <= #vocal_starts and vocal_starts[vi] < pm.e then
            qualifying[#qualifying + 1] = pm
        end
    end

    local spans = {}
    for _, pm in ipairs(qualifying) do
        local last = spans[#spans]
        if last and pm.s - last.e <= MeasureDurationAtTime(last.e) then
            last.e = pm.e
        else
            spans[#spans + 1] = { s = pm.s, e = pm.e, pitch = pitch }
        end
    end
    return spans, #qualifying
end

-- ---------------------------------------------------------------------------

function GenerateSingAlong()
    local venue_track, venue_item, venue_take = FindNamedTrackMIDI('VENUE')
    if not venue_track then
        S.status = 'No VENUE track found.'
        S.last_result = nil
        return
    end
    if not venue_item then
        S.status = 'No MIDI item on VENUE track.'
        S.last_result = nil
        return
    end

    local item_start_sec = r.GetMediaItemInfo_Value(venue_item, 'D_POSITION')
    local item_end_sec   = item_start_sec + r.GetMediaItemInfo_Value(venue_item, 'D_LENGTH')

    local SOURCES = {
        { track_name = 'HARM2', pitch = 87, label = 'Guitarist (HARM2)' },
        { track_name = 'HARM3', pitch = 85, label = 'Bassist (HARM3)' },
    }

    local all_spans        = {}
    local processed_pitches = {}
    local report_lines     = {}
    local any_available    = false

    for _, src in ipairs(SOURCES) do
        local take = AvailableHarmTake(src.track_name)
        if take then
            any_available = true
            processed_pitches[src.pitch] = true
            local phrase_markers, vocal_starts = ReadPhrasesAndVocalNotes(take)
            local spans, qual_count = BuildSpans(phrase_markers, vocal_starts, src.pitch)
            for _, sp in ipairs(spans) do all_spans[#all_spans + 1] = sp end
            report_lines[#report_lines + 1] = ('%s: %d qualifying phrase(s) -> %d note(s)')
                :format(src.label, qual_count, #spans)
        else
            report_lines[#report_lines + 1] =
                src.label .. ': skipped (muted or not found) - existing notes untouched'
        end
    end

    if not any_available then
        S.status = 'Tracks HARM2 and HARM3 are not unmuted.'
        S.last_result = nil
        return
    end

    if #all_spans == 0 then
        S.status = 'No qualifying phrases found in HARM2/HARM3.'
        S.last_result = table.concat(report_lines, '\n')
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(venue_track, venue_item)

    ClearNotesAtPitchesInRange(venue_take, processed_pitches, item_start_sec, item_end_sec)
    InsertNotes(venue_take, all_spans, 100)

    r.Undo_EndBlock2(0, 'RB Generate Sing Along (' .. #all_spans .. ' notes)', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Generated %d sing-along note(s) on VENUE track.'):format(#all_spans)
    S.last_result = table.concat(report_lines, '\n')
end
