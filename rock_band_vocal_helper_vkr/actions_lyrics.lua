-- Lyrics tab actions (ParseLyricsFile, ClearLyricEvents, ClearLyricsInRange, ClearLyricsAction, AssignLyricsAction)

----------------------------------------------------------------------
-- Lyrics helpers (local — only called within this file)
----------------------------------------------------------------------
local function ParseLyricsFile(path)
    local f = io.open(path, 'r')
    if not f then return nil, 'Could not open file:\n' .. path end
    local content = f:read('*all')
    f:close()
    content = content:gsub('%b[]', '')  -- strip [comment] blocks
    local words = {}
    for w in content:gmatch('%S+') do words[#words + 1] = w end
    if #words == 0 then
        return nil, 'No lyrics found in file (after stripping comments).'
    end
    return words
end

-- Remove all type-5 (lyric) text events from a take, preserving LYRIC_IGNORE entries.
local function ClearLyricEvents(midi_take)
    local _, _, _, n_text = r.MIDI_CountEvts(midi_take)
    local removed = 0
    for i = n_text - 1, 0, -1 do
        local ok, _, _, _, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 and not LYRIC_IGNORE[msg] then
            r.MIDI_DeleteTextSysexEvt(midi_take, i)
            removed = removed + 1
        end
    end
    return removed
end

-- Global: also called from actions.lua (SnapToKeyAction) and actions_harmonies.lua (HarmoniesAction).
function ClearLyricsInRange(take, range_start, range_end)
    local removed = 0
    local _, _, _, n_text = r.MIDI_CountEvts(take)
    for i = n_text - 1, 0, -1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and typ == 5 and not LYRIC_IGNORE[msg] then
            local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
            if t >= range_start - 0.001 and t < range_end + 0.001 then
                r.MIDI_DeleteTextSysexEvt(take, i)
                removed = removed + 1
            end
        end
    end
    return removed
end

----------------------------------------------------------------------
-- Lyrics actions
----------------------------------------------------------------------
function ClearLyricsAction()
    local tracks = GetTrackList()
    if #tracks == 0 or S.midi_idx >= #tracks then
        S.status = 'Error'; S.last_result = 'Invalid MIDI destination track.'; return
    end
    local midi_track = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local midi_item, midi_take = FindFirstMIDIItem(midi_track)
    if not midi_take then
        S.status = 'Error'
        S.last_result = 'No MIDI item found on the destination track.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(midi_track, midi_item)
    local cleared = ClearLyricEvents(midi_take)
    r.Undo_EndBlock2(0, ('Vocal Helper: cleared %d lyric events'):format(cleared), -1)
    r.PreventUIRefresh(-1)

    S.status = ('Cleared %d lyric events.'):format(cleared)
    S.last_result = nil
end

function AssignLyricsAction()
    if S.lyrics_path == '' then
        S.status = 'No lyrics file selected.'
        S.last_result = 'Use Auto-detect or Browse to select a lyrics file first.'
        return
    end

    local lyrics, lerr = ParseLyricsFile(S.lyrics_path)
    if not lyrics then S.status = 'Error'; S.last_result = lerr; return end

    local tracks = GetTrackList()
    if #tracks == 0 or S.midi_idx >= #tracks then
        S.status = 'Error'; S.last_result = 'Invalid MIDI destination track.'; return
    end
    local midi_track = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local midi_item, midi_take = FindFirstMIDIItem(midi_track)
    if not midi_take then
        S.status = 'Error'
        S.last_result = 'No MIDI item found on the destination track.'
        return
    end

    -- Read all notes: vocal range + phrase markers (whole take, time selection ignored)
    local scoped = {}
    local phrase_markers = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                scoped[#scoped + 1] = { s = s_t, e = e_t }
            elseif p == RB3_PHRASE_PITCH then
                phrase_markers[#phrase_markers + 1] = { s = s_t }
            end
        end
    end
    table.sort(scoped,         function(a, b) return a.s < b.s end)
    table.sort(phrase_markers, function(a, b) return a.s < b.s end)

    if #scoped == 0 then
        S.status = 'No notes in range.'
        S.last_result = 'No notes in the RB3 vocal range found on the destination take.'
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(midi_track, midi_item)

    local cleared = ClearLyricEvents(midi_take)

    local assigned = {}  -- { s, lyric } for validation
    local inserted = 0
    for i, n in ipairs(scoped) do
        local lyric = lyrics[i]
        if lyric then
            local ppq = r.MIDI_GetPPQPosFromProjTime(midi_take, n.s)
            r.MIDI_InsertTextSysexEvt(midi_take, false, false, ppq, 5, lyric)
            inserted = inserted + 1
        end
        assigned[i] = { s = n.s, lyric = lyric }
    end
    r.Undo_EndBlock2(0, ('Vocal Helper: assigned %d lyrics'):format(inserted), -1)
    r.PreventUIRefresh(-1)

    -- Build result
    local lines = {}
    lines[#lines + 1] = ('Lyrics assigned: %d syllables added'):format(inserted)
    lines[#lines + 1] = 'Scope: whole take'
    lines[#lines + 1] = ('Cleared %d existing lyric events first'):format(cleared)

    -- Count mismatch
    local n_notes_in = #scoped
    local n_lyrics_in = #lyrics
    if n_notes_in ~= n_lyrics_in then
        lines[#lines + 1] = ''
        if n_notes_in > n_lyrics_in then
            lines[#lines + 1] = ('Warning: %d notes, %d lyrics — last %d notes have no lyric')
                :format(n_notes_in, n_lyrics_in, n_notes_in - n_lyrics_in)
        else
            lines[#lines + 1] = ('Warning: %d notes, %d lyrics — last %d lyrics are unused')
                :format(n_notes_in, n_lyrics_in, n_lyrics_in - n_notes_in)
        end
    end

    -- Phrase capitalization check
    lines[#lines + 1] = ''
    if #phrase_markers == 0 then
        lines[#lines + 1] = 'Phrase markers: none found — cannot validate capitalization.'
    else
        local violations = {}
        for _, pm in ipairs(phrase_markers) do
            for _, a in ipairs(assigned) do
                if a.s >= pm.s - 0.001 and a.lyric then
                    local first = a.lyric:sub(1, 1)
                    if first ~= first:upper() then
                        violations[#violations + 1] = { s = a.s, lyric = a.lyric }
                    end
                    break
                end
            end
        end
        if #violations == 0 then
            lines[#lines + 1] = ('Phrase capitalization: OK — all %d phrases start with a capital letter.')
                :format(#phrase_markers)
        else
            lines[#lines + 1] = ('Phrase capitalization: %d violation(s):'):format(#violations)
            for _, v in ipairs(violations) do
                lines[#lines + 1] = ('  %s  "%s"'):format(FormatTime(v.s), v.lyric)
            end
        end
    end

    S.status = ('Lyrics assigned: %d notes.'):format(inserted)
    S.last_result = table.concat(lines, '\n')
end
