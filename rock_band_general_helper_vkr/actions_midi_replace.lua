-- MIDI Pattern Replace: find-and-replace and fill-range for recurring note patterns.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, ReadMIDIPatternFromTake (globals)

-- Per-difficulty pitch ranges on tracks that pack all four tiers into one
-- track at different pitch bands (matches DRUMS_RANGE in
-- actions_difficulty_drums.lua - the wider scan boundary, not the narrower
-- gem-legality ranges in GB_RANGE/K5_RANGE).
local DIFF_TIER_RANGE = {
    [1] = { lo = 96, hi = 100 }, -- Expert
    [2] = { lo = 84, hi = 88  }, -- Hard
    [3] = { lo = 72, hi = 76  }, -- Medium
    [4] = { lo = 60, hi = 64  }, -- Easy
}
local TIERED_TRACK_NAMES = {
    ['PART DRUMS'] = true, ['PART GUITAR'] = true,
    ['PART BASS']  = true, ['PART KEYS']   = true,
}
local FIXED_RANGE_TRACK_NAMES = {
    ['PART VOCALS'] = { lo = 36, hi = 84 }, ['HARM1'] = { lo = 36, hi = 84 },
    ['HARM2']       = { lo = 36, hi = 84 }, ['HARM3'] = { lo = 36, hi = 84 },
}
local FIXED_RANGE_PREFIXES = {
    { prefix = 'PART REAL_KEYS', lo = 48, hi = 72 },
    { prefix = 'PART KEYS_ANIM', lo = 48, hi = 72 },
}

-- Resolve the pitch range Pattern actions should be confined to for a given
-- track name + Difficulty selector (S.mr_diff_idx: 0=All, 1=X, 2=H, 3=M, 4=E).
-- Global: also used by ui_midi.lua for the resolved-range readout.
function GetPatternPitchRange(track_name, diff_idx)
    if TIERED_TRACK_NAMES[track_name] then
        if diff_idx and diff_idx >= 1 and diff_idx <= 4 then
            local rg = DIFF_TIER_RANGE[diff_idx]
            return rg.lo, rg.hi
        end
        return 60, 100  -- All: Easy's floor through Expert's ceiling
    end
    local fixed = FIXED_RANGE_TRACK_NAMES[track_name]
    if fixed then return fixed.lo, fixed.hi end
    for _, p in ipairs(FIXED_RANGE_PREFIXES) do
        if track_name:sub(1, #p.prefix) == p.prefix then return p.lo, p.hi end
    end
    return 0, 127  -- unrecognized track: no filtering
end

local function BuildPatternLabel(sel_s, sel_e, note_count)
    local s_m   = tonumber(r.format_timestr_pos(sel_s, '', 1):match('^(%d+)')) or 0
    local e_m   = tonumber(r.format_timestr_pos(sel_e, '', 1):match('^(%d+)')) or 0
    local m_cnt = e_m - s_m
    return string.format('M%d-M%d (%d measure%s with %d note%s)',
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

-- Delete all notes whose start PPQ is in [start_ppq, end_ppq) and whose
-- pitch is in [min_pitch, max_pitch] (defaults to 0/127 - no filtering).
local function ClearPatternWindow(take, start_ppq, end_ppq, min_pitch, max_pitch)
    min_pitch = min_pitch or 0
    max_pitch = max_pitch or 127
    local _, n = r.MIDI_CountEvts(take)
    for i = n - 1, 0, -1 do
        local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(take, i)
        if ok and sppq >= start_ppq and sppq < end_ppq and p >= min_pitch and p <= max_pitch then
            r.MIDI_DeleteNote(take, i)
        end
    end
end

local function GetTrackAndTake(idx)
    local track = r.GetTrack(0, idx)
    if not track then return nil, nil, nil, 'Selected track no longer exists - refresh tracks.' end
    local item, take = FindFirstMIDIItem(track)
    if not take then return nil, nil, nil, 'No MIDI item on source track.' end
    return track, item, take, nil
end

-- Resolve the scan scope for the source track's MIDI item to take-relative
-- PPQ bounds: the time selection if active, else the whole item.
local function ResolvePatternScope(take, item, sel_s, sel_e)
    if sel_s then
        return r.MIDI_GetPPQPosFromProjTime(take, sel_s), r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    end
    local item_pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    return r.MIDI_GetPPQPosFromProjTime(take, item_pos), r.MIDI_GetPPQPosFromProjTime(take, item_pos + item_len)
end

-- Walk [spq, epq) in Search-pattern-sized/strided windows and return an array
-- of take-relative PPQ match start positions. On a match, jumps past the
-- whole matched window (like DoMIDIPatternReplace does when replacing) so a
-- replaced region is never rescanned; on a miss, advances by one measure.
local function ScanPatternMatches(take, spq, epq, lo, hi)
    local dur  = S.mr_search_dur_ppq
    local step = S.mr_search_step_ppq > 0 and S.mr_search_step_ppq or dur
    local matches = {}
    local w = spq
    while w + dur <= epq do
        local cand = ReadMIDIPatternFromTake(take, w, w + dur, lo, hi)
        if PatternsMatch(S.mr_search_notes, cand) then
            matches[#matches + 1] = w
            w = w + dur
        else
            w = w + step
        end
    end
    return matches
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

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

    local spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
    local epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    local dur = epq - spq
    if dur < 1 then S.status = 'Time selection too short.'; return end

    local notes = ReadMIDIPatternFromTake(take, spq, epq, lo, hi)
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

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

    local spq = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
    local epq = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
    local dur = epq - spq
    if dur < 1 then S.status = 'Time selection too short.'; return end

    local notes = ReadMIDIPatternFromTake(take, spq, epq, lo, hi)

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

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

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
        ClearPatternWindow(take, w, w + dur, lo, hi)
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
        S.status = 'Search pattern has 0 notes - nothing to match.'; return
    end
    if math.abs(S.mr_search_dur_ppq - S.mr_replace_dur_ppq) > 0.5 then
        S.status = 'Search and Replace patterns must cover the same duration.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

    -- Scan scope: time selection or full MIDI item
    local sel_s, sel_e = GetTimeSelection()
    local dur = S.mr_search_dur_ppq
    local spq, epq = ResolvePatternScope(take, item, sel_s, sel_e)
    local match_positions = ScanPatternMatches(take, spq, epq, lo, hi)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    for _, w in ipairs(match_positions) do
        ClearPatternWindow(take, w, w + dur, lo, hi)
        for _, note in ipairs(S.mr_replace_notes) do
            r.MIDI_InsertNote(take, false, false, w + note.rel_s, w + note.rel_e, 0, note.pitch, 100, false)
        end
    end
    local matches = #match_positions

    r.Undo_EndBlock2(0, 'Pattern Replace: ' .. matches .. ' replacement' .. (matches ~= 1 and 's' or ''), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if matches > 0 then
        S.status = 'Replaced ' .. matches .. ' instance' .. (matches ~= 1 and 's' or '') .. '.'
    else
        S.status = 'No matches found.'
    end
end

----------------------------------------------------------------------

-- Move the edit cursor to the nearest Search-pattern match before/after the
-- current edit cursor position. direction: -1 = previous, 1 = next.
local function GoToPatternMatch(direction)
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    if not S.mr_search_notes or #S.mr_search_notes == 0 then
        S.status = 'Set a Search pattern first.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

    local sel_s, sel_e = GetTimeSelection()
    local spq, epq = ResolvePatternScope(take, item, sel_s, sel_e)
    local match_positions = ScanPatternMatches(take, spq, epq, lo, hi)

    local cur_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.GetCursorPosition())
    local EPS = 0.5

    -- Going back, step out of the match the cursor is sitting in rather than
    -- snapping to its start. Without this, a cursor anywhere inside an instance
    -- makes Go Prev jump backwards by a fraction of a measure to that same
    -- instance's start instead of reaching the previous one. Go Next needs no
    -- equivalent: a match the cursor is inside starts behind it, so it is
    -- already excluded. Anchor on the latest containing match so overlapping
    -- matches still step one at a time.
    local anchor = cur_ppq
    local dur    = S.mr_search_dur_ppq or 0
    if direction < 0 and dur > 0 then
        local containing = nil
        for _, w in ipairs(match_positions) do
            if cur_ppq >= w - EPS and cur_ppq < w + dur
               and (not containing or w > containing) then
                containing = w
            end
        end
        if containing then anchor = containing end
    end

    local best = nil
    for _, w in ipairs(match_positions) do
        if direction < 0 then
            if w < anchor - EPS and (not best or w > best) then best = w end
        else
            if w > cur_ppq + EPS and (not best or w < best) then best = w end
        end
    end

    if not best then
        S.status = direction < 0 and 'No previous instance found.' or 'No next instance found.'
        return
    end

    r.SetEditCurPos(r.MIDI_GetProjTimeFromPPQPos(take, best), true, false)
    S.status = direction < 0 and 'Moved to previous match.' or 'Moved to next match.'
end

function GoPrevPatternMatch() GoToPatternMatch(-1) end
function GoNextPatternMatch() GoToPatternMatch(1) end

----------------------------------------------------------------------

function ListPatternMatches()
    if S.mr_midi_src_idx < 0 then
        S.status = 'Set a source MIDI track first.'; return
    end
    if not S.mr_search_notes or #S.mr_search_notes == 0 then
        S.status = 'Set a Search pattern first.'; return
    end
    local track, item, take, err = GetTrackAndTake(S.mr_midi_src_idx)
    if err then S.status = err; return end

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mr_diff_idx)

    local sel_s, sel_e = GetTimeSelection()
    local spq, epq = ResolvePatternScope(take, item, sel_s, sel_e)
    local match_positions = ScanPatternMatches(take, spq, epq, lo, hi)

    if #match_positions == 0 then
        S.status = 'No matches found.'
        S.last_result = nil
        return
    end

    local lines = { ('%d match%s found:'):format(#match_positions, #match_positions ~= 1 and 'es' or ''), '' }
    for i, w in ipairs(match_positions) do
        local t = r.MIDI_GetProjTimeFromPPQPos(take, w)
        lines[#lines + 1] = ('%d. %s'):format(i, FormatTime(t))
    end
    S.status = ('Listed %d match%s.'):format(#match_positions, #match_positions ~= 1 and 'es' or '')
    S.last_result = table.concat(lines, '\n')
end
