-- MIDI converter: raw guitar pitches â†’ Rock Band Expert Guitar gems
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, InsertNotes, PitchName (globals)

-- Expert Guitar gem pitches: 96=Green, 97=Red, 98=Yellow, 99=Blue, 100=Orange
GEM_MIN     = 96
GEM_MAX     = 100
GEM_LETTERS = { [0]='G', [1]='R', [2]='Y', [3]='B', [4]='O' }

-- Notes within this window (seconds) are grouped as a single chord event
CHORD_WINDOW_S = 0.010  -- 10 ms

----------------------------------------------------------------------
-- Source MIDI reading
----------------------------------------------------------------------

local function ReadGuitarMIDI(track, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = { s = s, e = e, pitch = pitch, vel = vel }
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

-- Group simultaneous notes (within CHORD_WINDOW_S) into chord events.
-- Returns events[]: {s, e, pitches[] sorted ascending}
local function GroupIntoEvents(notes)
    local events = {}
    local i = 1
    while i <= #notes do
        local ev = { s = notes[i].s, e = notes[i].e, pitches = { notes[i].pitch } }
        i = i + 1
        while i <= #notes and (notes[i].s - ev.s) <= CHORD_WINDOW_S do
            ev.pitches[#ev.pitches + 1] = notes[i].pitch
            if notes[i].e > ev.e then ev.e = notes[i].e end
            i = i + 1
        end
        table.sort(ev.pitches)
        events[#events + 1] = ev
    end
    return events
end

----------------------------------------------------------------------
-- Tempo helper
----------------------------------------------------------------------

function GetBPMAt(time)
    local tidx = r.FindTempoTimeSigMarker(0, time)
    if tidx >= 0 then
        local ok, _, _, _, bpm = r.GetTempoTimeSigMarker(0, tidx)
        if ok and bpm and bpm > 0 then return bpm end
    end
    return 120
end

----------------------------------------------------------------------
-- Gem assignment helpers
----------------------------------------------------------------------

-- Keep at most max_chord pitches: lowest + best middle + highest.
-- Pitches must be sorted ascending.
function CompressChord(pitches, max_chord)
    if #pitches <= max_chord then return pitches end
    if max_chord == 1 then return { pitches[1] } end
    if max_chord == 2 then return { pitches[1], pitches[#pitches] } end
    local mid = math.floor(#pitches / 2) + 1
    return { pitches[1], pitches[mid], pitches[#pitches] }
end

-- True when a 3-note chord has both Green (pos 0) and Orange (pos 4) - illegal per authoring rules.
local function IsIllegalGO(gems)
    return #gems == 3 and gems[1] == 0 and gems[3] == 4
end

function GemLabel(gems)
    local parts = {}
    for _, g in ipairs(gems) do parts[#parts + 1] = GEM_LETTERS[g] end
    return '[' .. table.concat(parts, '+') .. ']'
end

function PitchLabel(pitches)
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = PitchName(p) end
    return table.concat(parts, '+')
end

function ChordTypeName(gems)
    if #gems == 1 then return 'single' end
    if #gems == 2 then
        local names = { [1]='1-2 chord', [2]='1-3 chord', [3]='1-4 chord', [4]='1-5 chord' }
        return names[gems[2] - gems[1]] or 'chord'
    end
    return '3-note chord'
end

----------------------------------------------------------------------
-- Gem assignment pools (shared by AssignGems and AssignGemsForGuide)
----------------------------------------------------------------------

-- Each sub-table is a gem combo ranked from smallest spread to largest.
-- For 2-note chords, pool starts with 1-2 entries so lower-pitch shapes
-- get adjacent gems first, maximising chord differentiation.
POOLS = {
    [1] = {{0},{1},{2},{3},{4}},
    [2] = {{0,1},{0,2},{1,2},{0,3},{1,3},{2,3},{1,4},{2,4},{3,4}},
    [3] = {{0,1,2},{0,1,3},{0,2,3},{1,2,3},{1,2,4},{1,3,4},{2,3,4}},
}

-- Pool for 2-note chords when allow_14 is off: spread ≤ 2 only (7 entries).
POOLS2_NO14 = {{0,1},{0,2},{1,2},{1,3},{2,3},{2,4},{3,4}}

----------------------------------------------------------------------
-- Gem assignment: main algorithm
----------------------------------------------------------------------

-- Shape-based algorithm:
--
-- Phase 1 (global map building):
--   All distinct compressed chord shapes across the entire event list are
--   collected, sorted by pitch (max then avg), and assigned gem combos from
--   the pool in order. Pool cycling (wrapping) only occurs when the number
--   of distinct shapes in a size group exceeds the pool size - unused gem
--   combos are never skipped. Gaps between notes do NOT reset assignments.
--
-- Phase 2 (output):
--   Walk events in order, emitting gem assignments using the global shape map.
--   Gaps > wrap_gap_s are annotated as phrase boundaries in the report only.
--
-- Returns assignments[]: each entry is either:
--   { s, e, gems[], reason, is_meta=false }  - a real gem event
--   { s, reason, is_meta=true }              - phrase/wrap annotation
local function AssignGems(events, wrap_gap_s, max_chord)
    if #events == 0 then return {} end

    local function shape_key(sorted_pitches)
        local t = {}
        for _, p in ipairs(sorted_pitches) do t[#t + 1] = p end
        return table.concat(t, ',')
    end

    -- Phase 1: build a single global shapeâ†’gem map -----------------------

    local all_shapes  = {}   -- key â†’ {avg, max, sz, pitches}
    local size_orders = {}   -- sz â†’ [keys in first-seen order, sorted later]

    for _, ev in ipairs(events) do
        local pitches = CompressChord(ev.pitches, max_chord)
        table.sort(pitches)
        local sz  = #pitches
        local key = shape_key(pitches)
        if not all_shapes[key] then
            local sum = 0
            for _, p in ipairs(pitches) do sum = sum + p end
            all_shapes[key] = { avg = sum / sz, max = pitches[sz], sz = sz, pitches = pitches }
            if not size_orders[sz] then size_orders[sz] = {} end
            size_orders[sz][#size_orders[sz] + 1] = key
        end
    end

    local pool2      = S.mc_gtr_allow_14 and POOLS[2] or POOLS2_NO14
    local shape_gems = {}   -- key â†’ gem combo (global, never reset)

    local sizes = {}
    for sz in pairs(size_orders) do sizes[#sizes + 1] = sz end
    table.sort(sizes)

    for _, sz in ipairs(sizes) do
        local order = size_orders[sz]
        table.sort(order, function(a, b)
            local sa, sb = all_shapes[a], all_shapes[b]
            if sa.max ~= sb.max then return sa.max < sb.max end
            return sa.avg < sb.avg
        end)
        local N = #order
        for rank, key in ipairs(order) do
            local combo
            if sz == 1 then
                local gem = N == 1 and 0 or math.min(4, math.floor((rank - 1) * 4 / (N - 1) + 0.5))
                combo = { gem }
            else
                local pool = (sz == 2) and pool2 or (POOLS[math.min(sz, 3)] or POOLS[1])
                combo = pool[((rank - 1) % #pool) + 1]
            end
            shape_gems[key] = combo
        end
    end

    -- Phrase ranges: for report annotations only - do NOT reset gem assignments
    local phrase_ranges = {}
    local cur_start     = 1
    local prev_e        = -1

    for i = 1, #events do
        local ev = events[i]
        if i > 1 and prev_e >= 0 and (ev.s - prev_e) > wrap_gap_s then
            phrase_ranges[#phrase_ranges + 1] = { i_s = cur_start, i_e = i - 1 }
            cur_start = i
        end
        prev_e = ev.e
    end
    phrase_ranges[#phrase_ranges + 1] = { i_s = cur_start, i_e = #events }

    -- Build per-phrase header strings using globally-assigned gems
    local phrase_headers = {}
    for _, pr in ipairs(phrase_ranges) do
        local seen       = {}
        local seen_order = {}
        for i = pr.i_s, pr.i_e do
            local pitches = CompressChord(events[i].pitches, max_chord)
            table.sort(pitches)
            local key = shape_key(pitches)
            if not seen[key] then
                seen[key] = true
                seen_order[#seen_order + 1] = key
            end
        end
        table.sort(seen_order, function(a, b)
            local sa, sb = all_shapes[a], all_shapes[b]
            if sa.max ~= sb.max then return sa.max < sb.max end
            return sa.avg < sb.avg
        end)
        local parts = {}
        for _, key in ipairs(seen_order) do
            local pitch_parts = {}
            for _, p in ipairs(all_shapes[key].pitches) do
                pitch_parts[#pitch_parts + 1] = PitchName(p)
            end
            parts[#parts + 1] = table.concat(pitch_parts, '+') .. '\xe2\x86\x92' .. GemLabel(shape_gems[key])
        end
        phrase_headers[#phrase_headers + 1] = table.concat(parts, '  ')
    end

    -- Phase 2: emit assignments ------------------------------------------
    local assignments = {}
    local pi          = 1
    local prev_ev_end = -1
    local prev_gems   = nil

    for i, ev in ipairs(events) do
        local pr = phrase_ranges[pi]

        if i == pr.i_s then
            prev_gems = nil
            local gap_s = (prev_ev_end >= 0) and (ev.s - prev_ev_end) or 0
            local meta_reason
            if prev_ev_end >= 0 and gap_s > wrap_gap_s then
                meta_reason = string.format(
                    'Phrase  gap=%.0f ms  %s',
                    gap_s * 1000, phrase_headers[pi])
            else
                meta_reason = 'Phrase start  ' .. phrase_headers[pi]
            end
            assignments[#assignments + 1] = { s = ev.s, reason = meta_reason, is_meta = true }
        end

        local pitches = CompressChord(ev.pitches, max_chord)
        table.sort(pitches)
        local n_orig = #ev.pitches
        local key    = shape_key(pitches)
        local src    = shape_gems[key]
        local gems   = {}
        for _, g in ipairs(src) do gems[#gems + 1] = g end

        local go_fixed = false
        if IsIllegalGO(gems) then
            gems     = { gems[1], gems[3] }
            go_fixed = true
        end

        -- Prefer R+O over G+O for playability.
        -- G+O is a full-fretboard stretch; R+O lets the player hold the lower finger from
        -- the previous note. Only keep G+O when prev note was at Green (hand already there).
        local go_subst = false
        if #gems == 2 and gems[1] == 0 and gems[2] == 4 then
            local prev_at_green = prev_gems and #prev_gems == 1 and prev_gems[1] == 0
            if not prev_at_green then
                gems     = { 1, 4 }  -- R+O
                go_subst = true
            end
        end

        -- Safety net: narrow any residual spread >= 3 when allow_14 is off
        -- (can occur after G+O â†’ R+O substitution above).
        local narrowed_14 = false
        if not S.mc_gtr_allow_14 and #gems == 2 and gems[2] - gems[1] >= 3 then
            gems        = { gems[1], gems[1] + 2 }
            narrowed_14 = true
        end

        local reason = string.format('%s  %s \xe2\x86\x92 %s',
            ChordTypeName(gems), PitchLabel(ev.pitches), GemLabel(gems))
        if n_orig > #pitches then
            reason = reason .. string.format('  (compressed %d\xe2\x86\x92%d)', n_orig, #pitches)
        end
        if go_fixed  then reason = reason .. '  (G+O 3-note illegal \xe2\x86\x92 kept as 1-5)' end
        if go_subst  then reason = reason .. '  (G\xe2\x86\x92R: G+O \xe2\x86\x92 R+O for playability)' end
        if narrowed_14 then reason = reason .. '  (1-4 \xe2\x86\x92 1-3: narrowed per setting)' end

        assignments[#assignments + 1] = {
            s = ev.s, e = ev.e, gems = gems, reason = reason, is_meta = false,
            tab_str = ev.tab_str,
        }

        prev_gems   = gems
        prev_ev_end = ev.e
        if i == pr.i_e then pi = pi + 1 end
    end

    return assignments
end

----------------------------------------------------------------------
-- Preview report
----------------------------------------------------------------------

local function BuildPreviewReport(assignments, n_src, n_gems)
    local lines = {}
    lines[#lines + 1] = string.format('Source notes: %d  â†’  Gems to write: %d', n_src, n_gems)
    lines[#lines + 1] = ''
    for _, a in ipairs(assignments) do
        if a.is_meta then
            lines[#lines + 1] = ''
            lines[#lines + 1] = '  *** ' .. a.reason
        else
            local ts = r.format_timestr_pos(a.s, '', 1)
            lines[#lines + 1] = string.format('  %-10s  %-7s  %s',
                ts, GemLabel(a.gems), a.reason)
        end
    end
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Target track write helpers
----------------------------------------------------------------------

local function BuildOutNotes(assignments)
    local out = {}
    for _, a in ipairs(assignments) do
        if not a.is_meta and a.gems then
            for _, g in ipairs(a.gems) do
                out[#out + 1] = { s = a.s, e = a.e, pitch = GEM_MIN + g }
            end
        end
    end
    return out
end


----------------------------------------------------------------------
-- Public action functions
----------------------------------------------------------------------

function ConvertGuitar()
    if S.mc_gtr_src_idx < 0 then
        S.status = 'Error: no guitar source track selected.'
        S.last_result = 'Select the source MIDI guitar track in the Guitar tab.'
        return
    end
    if S.mc_gtr_tgt_idx < 0 then
        S.status = 'Error: no guitar target track selected.'
        S.last_result = 'Select the PART GUITAR target track in the Guitar tab.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_gtr_src_idx)
    local tgt_tr = r.GetTrack(0, S.mc_gtr_tgt_idx)
    if not src_tr or not tgt_tr then
        S.status = 'Error: a selected track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes    = ReadGuitarMIDI(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.'
                               or 'Source track has no MIDI notes.'
        return
    end

    local events      = GroupIntoEvents(src_notes)
    local wrap_gap_s  = S.mc_gtr_wrap_gap_ms / 1000
    local assignments = AssignGems(events, wrap_gap_s, S.mc_gtr_max_chord)

    local n_gems = 0
    for _, a in ipairs(assignments) do
        if not a.is_meta and a.gems then n_gems = n_gems + #a.gems end
    end

    local preview_mode = (S.mc_gtr_workflow == 0)
    local report       = BuildPreviewReport(assignments, #src_notes, n_gems)

    if preview_mode then
        S.status = string.format('Guitar preview: %d source notes â†’ %d gems (not written)',
            #src_notes, n_gems)
        S.last_result = report
        return
    end

    local tgt_item, tgt_take = FindFirstMIDIItem(tgt_tr)
    if not tgt_item then
        S.status = 'Error: target track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART GUITAR target track first.'
        return
    end

    local out_notes = BuildOutNotes(assignments)
    local ip        = r.GetMediaItemInfo_Value(tgt_item, 'D_POSITION')
    local ie        = ip + r.GetMediaItemInfo_Value(tgt_item, 'D_LENGTH')
    local clear_s   = sel_s and math.max(sel_s, ip) or ip
    local clear_e   = sel_e and math.min(sel_e, ie) or ie

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(tgt_tr, tgt_item)
    ClearGuitarGems(tgt_take, clear_s, clear_e)
    InsertNotes(tgt_take, out_notes, 100)
    r.Undo_EndBlock2(0, 'Convert Guitar to Rock Band', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = string.format('Guitar converted: %d gems inserted from %d source notes.',
        n_gems, #src_notes)
    S.last_result = report
end

function ValidateGuitar()
    if S.mc_gtr_tgt_idx < 0 then
        S.status = 'Error: no guitar target track selected.'
        S.last_result = 'Select the PART GUITAR target track in the Guitar tab.'
        return
    end

    local tgt_tr = r.GetTrack(0, S.mc_gtr_tgt_idx)
    if not tgt_tr then
        S.status = 'Error: target track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local rb_notes      = ReadRBGuitarNotes(tgt_tr, sel_s, sel_e)
    if #rb_notes == 0 then
        S.status = 'No Rock Band guitar notes found on target track.'
        S.last_result = sel_s and 'No notes in the current time selection.'
                               or 'Target track has no RB guitar notes (pitch 96-100).'
        return
    end

    local violations, n_events = RunValidation(rb_notes)

    if #violations == 0 then
        S.status = string.format('Validation passed - %d chord events checked, no violations.',
            n_events)
        S.last_result = 'No violations found.'
    else
        S.status = string.format('Validation: %d violation%s in %d events.',
            #violations, #violations == 1 and '' or 's', n_events)
        S.last_result = table.concat(violations, '\n')
    end
end
