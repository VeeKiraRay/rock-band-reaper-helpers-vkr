-- MIDI Pattern Replace: find-and-replace and fill-range for recurring note patterns.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, ReadMIDIPatternFromTake (globals)

local function BuildPatternLabel(sel_s, sel_e, note_count)
    local s_m   = tonumber(r.format_timestr_pos(sel_s, '', 1):match('^(%d+)')) or 0
    local e_m   = tonumber(r.format_timestr_pos(sel_e, '', 1):match('^(%d+)')) or 0
    local m_cnt = e_m - s_m
    return string.format('M%d\xe2\x80\x93M%d (%d measure%s with %d note%s)',
        s_m, e_m - 1,
        m_cnt, m_cnt ~= 1 and 's' or '',
        note_count, note_count ~= 1 and 's' or '')
end

-- Compare two sorted note arrays by pitch and relative start PPQ.
local function PatternsMatch(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i].pitch ~= b[i].pitch then return false end
        if math.abs(a[i].rel_s - b[i].rel_s) > 0.5 then return false end
    end
    return true
end

-- Delete all notes whose start PPQ is in [start_ppq, end_ppq).
local function ClearPatternWindow(take, start_ppq, end_ppq)
    local _, n = r.MIDI_CountEvts(take)
    for i = n - 1, 0, -1 do
        local ok, _, _, sppq = r.MIDI_GetNote(take, i)
        if ok and sppq >= start_ppq and sppq < end_ppq then
            r.MIDI_DeleteNote(take, i)
        end
    end
end

local function GetTrackAndTake(idx)
    local track = r.GetTrack(0, idx)
    if not track then return nil, nil, nil, 'Selected track no longer exists \xe2\x80\x94 refresh tracks.' end
    local item, take = FindFirstMIDIItem(track)
    if not take then return nil, nil, nil, 'No MIDI item on source track.' end
    return track, item, take, nil
end

----------------------------------------------------------------------

function SetSearchPattern()
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    local sel_s, sel_e = GetTimeSelection()
    if not sel_s then
        S.status = 'Set a time selection to define the search pattern.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
    local epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    local dur = epq - spq
    if dur < 1 then S.status = 'Time selection too short.'; return end

    local notes = ReadMIDIPatternFromTake(take, spq, epq)
    local s_m   = tonumber(r.format_timestr_pos(sel_s, '', 1):match('^(%d+)')) or 0
    local e_m   = tonumber(r.format_timestr_pos(sel_e, '', 1):match('^(%d+)')) or 0
    local m_cnt = e_m - s_m

    S.mr_search_notes    = notes
    S.mr_search_dur_ppq  = dur
    S.mr_search_step_ppq = m_cnt > 0 and (dur / m_cnt) or dur
    S.mr_search_label    = BuildPatternLabel(sel_s, sel_e, #notes)
    S.status = 'Search pattern set.'
end

----------------------------------------------------------------------

function SetReplacePattern()
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    local sel_s, sel_e = GetTimeSelection()
    if not sel_s then
        S.status = 'Set a time selection to define the replace pattern.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
    local epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    local dur = epq - spq
    if dur < 1 then S.status = 'Time selection too short.'; return end

    local notes = ReadMIDIPatternFromTake(take, spq, epq)

    S.mr_replace_notes   = notes
    S.mr_replace_dur_ppq = dur
    S.mr_replace_label   = BuildPatternLabel(sel_s, sel_e, #notes)
    S.status = 'Replace pattern set.'
end

----------------------------------------------------------------------

function FillRange()
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    if not S.mr_replace_notes then
        S.status = 'Set a Replace pattern first.'; return
    end
    local sel_s, sel_e = GetTimeSelection()
    if not sel_s then
        S.status = 'Set a time selection to define the fill range.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
    local epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    local dur = S.mr_replace_dur_ppq
    local n   = math.floor((epq - spq) / dur)
    if n < 1 then
        S.status = 'Time selection is shorter than the Replace pattern.'; return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    for i = 0, n - 1 do
        local w = spq + i * dur
        ClearPatternWindow(take, w, w + dur)
        for _, note in ipairs(S.mr_replace_notes) do
            r.MIDI_InsertNote(take, false, false, w + note.rel_s, w + note.rel_e, 0, note.pitch, 100, false)
        end
    end

    r.Undo_EndBlock2(0, 'Pattern Replace: fill range (' .. n .. ' slot' .. (n ~= 1 and 's' or '') .. ')', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = 'Filled ' .. n .. ' slot' .. (n ~= 1 and 's' or '') .. '.'
end

----------------------------------------------------------------------

function DoMIDIPatternReplace()
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    if not S.mr_search_notes then
        S.status = 'Set a Search pattern first.'; return
    end
    if not S.mr_replace_notes then
        S.status = 'Set a Replace pattern first.'; return
    end
    if #S.mr_search_notes == 0 then
        S.status = 'Search pattern has 0 notes \xe2\x80\x94 nothing to match.'; return
    end
    if math.abs(S.mr_search_dur_ppq - S.mr_replace_dur_ppq) > 0.5 then
        S.status = 'Search and Replace patterns must cover the same duration.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    -- Scan scope: time selection or full MIDI item
    local sel_s, sel_e = GetTimeSelection()
    local dur = S.mr_search_dur_ppq
    local spq, epq
    if sel_s then
        spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
        epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    else
        local item_pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        spq = r.MIDI_GetPPQPosFromProjTime(take, item_pos)
        epq = r.MIDI_GetPPQPosFromProjTime(take, item_pos + item_len)
    end

    local step    = S.mr_search_step_ppq > 0 and S.mr_search_step_ppq or dur
    local matches = 0
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    local w = spq
    while w + dur <= epq do
        local cand = ReadMIDIPatternFromTake(take, w, w + dur)
        if PatternsMatch(S.mr_search_notes, cand) then
            ClearPatternWindow(take, w, w + dur)
            for _, note in ipairs(S.mr_replace_notes) do
                r.MIDI_InsertNote(take, false, false, w + note.rel_s, w + note.rel_e, 0, note.pitch, 100, false)
            end
            matches = matches + 1
            w = w + dur   -- skip past the replaced region
        else
            w = w + step  -- try next measure boundary
        end
    end

    r.Undo_EndBlock2(0, 'Pattern Replace: ' .. matches .. ' replacement' .. (matches ~= 1 and 's' or ''), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if matches > 0 then
        S.status = 'Replaced ' .. matches .. ' instance' .. (matches ~= 1 and 's' or '') .. '.'
    else
        S.status = 'No matches found.'
    end
end
