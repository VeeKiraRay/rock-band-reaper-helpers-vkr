-- MIDI converter: Piano MIDI -> Rock Band Keys (hand split, Pro Keys range, 5-Lane Keys)
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, InsertNotes, PitchName (globals)

-- Read all notes with channel info from every MIDI item on a track.
-- Returns array sorted by start time: { s, e, pitch, vel, chan }
local function ReadMIDINotesWithChannel(track, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, chan, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = {
                            s     = s,
                            e     = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                            pitch = pitch,
                            vel   = vel,
                            chan  = chan,
                        }
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Returns true if a note belongs to the right hand, based on current split settings.
-- Channel-based: MIDI channel 1 (0-indexed chan == 0) = right hand.
-- Pitch-based:   pitch >= S.mc_keys_split_pitch = right hand.
local function IsRightHand(note)
    if S.mc_keys_split_by_ch then
        return note.chan == 0
    else
        return note.pitch >= S.mc_keys_split_pitch
    end
end

-- Write notes to a target track. Clears the range first, then inserts.
-- Returns (count written) or 0 on failure.
local function WriteNotesToTrack(tgt_idx, notes, sel_s, sel_e, undo_label)
    if tgt_idx < 0 then return 0 end
    local tgt_tr = r.GetTrack(0, tgt_idx)
    if not tgt_tr then return 0 end
    local tgt_item, tgt_take = FindFirstMIDIItem(tgt_tr)
    if not tgt_item then return 0 end

    local ip      = r.GetMediaItemInfo_Value(tgt_item, 'D_POSITION')
    local ie      = ip + r.GetMediaItemInfo_Value(tgt_item, 'D_LENGTH')
    local clear_s = sel_s and math.max(sel_s, ip) or ip
    local clear_e = sel_e and math.min(sel_e, ie) or ie

    r.MarkTrackItemsDirty(tgt_tr, tgt_item)
    ClearNotesInRange(tgt_take, clear_s, clear_e, 0, 127)
    InsertNotes(tgt_take, notes, 100)
    return #notes
end

-- Pro Keys range constants (used by ConvertPianoToProKeys and ProKeysTabGuide).
PK_MIN = 48   -- C2
PK_MAX = 72   -- C4

-- pref: 1 = preferred, 2 = common alternative, 3 = less common
PK_RANGES = {
    { name = 'C2-E3', lo = 48, hi = 64, pref = 1 },
    { name = 'D2-F3', lo = 50, hi = 65, pref = 3 },
    { name = 'E2-G3', lo = 52, hi = 67, pref = 2 },
    { name = 'F2-A3', lo = 53, hi = 69, pref = 1 },
    { name = 'G2-B3', lo = 55, hi = 71, pref = 3 },
    { name = 'A2-C4', lo = 57, hi = 72, pref = 1 },
}

PK_PREF_LABEL = { [1] = '[preferred]', [2] = '[common alternative]', [3] = '[less common]' }

-- Keep at most max_chord pitches from a sorted-ascending list.
-- Keeps lowest + highest + one middle note (the one nearest the centre of the span).
local function CompressChord(pitches, max_chord)
    if #pitches <= max_chord then return pitches end
    if max_chord <= 1 then return { pitches[1] } end
    if max_chord == 2 then return { pitches[1], pitches[#pitches] } end
    -- max_chord == 3: keep lowest, highest, and the middle note closest to centre
    local lo = pitches[1]
    local hi = pitches[#pitches]
    local centre = (lo + hi) / 2
    local best_mid, best_dist = nil, math.huge
    for i = 2, #pitches - 1 do
        local d = math.abs(pitches[i] - centre)
        if d < best_dist then best_dist = d; best_mid = pitches[i] end
    end
    return { lo, best_mid, hi }
end

function SplitHands()
    if S.mc_keys_src_idx < 0 then
        S.status = 'Error: no source track selected.'
        S.last_result = 'Select the piano MIDI source track in the Keys tab.'
        return
    end
    if S.mc_keys_rh_tgt_idx < 0 and S.mc_keys_lh_tgt_idx < 0 then
        S.status = 'Error: no target tracks selected.'
        S.last_result = 'Select at least one target track (right hand or left hand).'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_keys_src_idx)
    if not src_tr then
        S.status = 'Error: source track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes = ReadMIDINotesWithChannel(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.' or
                                  'Source track has no MIDI notes.'
        return
    end

    -- Partition into right-hand and left-hand note lists (strip channel for output).
    local rh_notes, lh_notes = {}, {}
    for _, n in ipairs(src_notes) do
        local out = { s = n.s, e = n.e, pitch = n.pitch }
        if IsRightHand(n) then
            rh_notes[#rh_notes + 1] = out
        else
            lh_notes[#lh_notes + 1] = out
        end
    end

    local split_desc
    if S.mc_keys_split_by_ch then
        split_desc = 'by MIDI channel (ch 1 = RH, ch 2 = LH)'
    else
        split_desc = ('by pitch  (%s and above = RH)'):format(
            PitchName(S.mc_keys_split_pitch))
    end

    if S.mc_keys_preview then
        local lines = {
            ('Source: %d notes total'):format(#src_notes),
            ('Split %s'):format(split_desc),
            '',
            ('Right hand: %d notes'):format(#rh_notes),
            ('Left hand:  %d notes'):format(#lh_notes),
            '',
            'Preview only - switch to Auto-insert and run again to write.',
        }
        S.status = ('Hand split preview: %d RH + %d LH (not written)'):format(
            #rh_notes, #lh_notes)
        S.last_result = table.concat(lines, '\n')
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local written_rh = WriteNotesToTrack(S.mc_keys_rh_tgt_idx, rh_notes, sel_s, sel_e)
    local written_lh = WriteNotesToTrack(S.mc_keys_lh_tgt_idx, lh_notes, sel_s, sel_e)

    r.Undo_EndBlock2(0, 'Split Piano Hands', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('Source: %d notes total'):format(#src_notes),
        ('Split %s'):format(split_desc),
        '',
    }
    if S.mc_keys_rh_tgt_idx >= 0 then
        lines[#lines + 1] = ('Right hand: %d notes written'):format(written_rh)
    end
    if S.mc_keys_lh_tgt_idx >= 0 then
        lines[#lines + 1] = ('Left hand:  %d notes written'):format(written_lh)
    end

    S.status = ('Hands split: %d RH + %d LH notes written.'):format(written_rh, written_lh)
    S.last_result = table.concat(lines, '\n')
end

function ConvertProKeys()
    if S.mc_keys_pk_src_idx < 0 then
        S.status = 'Error: no Expert PK source track selected.'
        S.last_result = 'Select the Expert Pro Keys source track in the Pro Keys section.'
        return
    end
    if S.mc_keys_rh_tgt_idx < 0 and S.mc_keys_lh_tgt_idx < 0 then
        S.status = 'Error: no animation target track selected.'
        S.last_result = 'Select at least one animation target (RH or LH) in Hand Split above.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_keys_pk_src_idx)
    if not src_tr then
        S.status = 'Error: source track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local raw = ReadMIDINotesWithChannel(src_tr, sel_s, sel_e)

    -- Keep only C2-C4 (48-72). Strips lane markers (0,2,4,5,7,9) automatically.
    local anim_notes = {}
    local stripped = 0
    for _, n in ipairs(raw) do
        if n.pitch >= 48 and n.pitch <= 72 then
            anim_notes[#anim_notes + 1] = { s = n.s, e = n.e, pitch = n.pitch }
        else
            stripped = stripped + 1
        end
    end

    if #anim_notes == 0 then
        S.status = 'No notes in C2-C4 found on source track.'
        S.last_result = sel_s and 'No C2-C4 notes in the time selection.'
                                or 'Source track has no notes in C2-C4.'
        return
    end

    local strip_note = stripped == 1 and '1 note' or (stripped .. ' notes')
    local anim_note  = #anim_notes == 1 and '1 note' or (#anim_notes .. ' notes')

    if S.mc_keys_preview then
        local lines = {
            ('Source: %d notes total'):format(#raw),
            ('Animation notes (C2-C4): %s'):format(anim_note),
        }
        if stripped > 0 then
            lines[#lines + 1] = ('Excluded (lane markers / out of range): %s'):format(strip_note)
        end
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Preview only - switch to Auto-insert and run again to write.'
        S.status = ('Animation preview: %s ready (not written)'):format(anim_note)
        S.last_result = table.concat(lines, '\n')
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local written_rh = WriteNotesToTrack(S.mc_keys_rh_tgt_idx, anim_notes, sel_s, sel_e)
    local written_lh = WriteNotesToTrack(S.mc_keys_lh_tgt_idx, anim_notes, sel_s, sel_e)
    r.Undo_EndBlock2(0, 'Generate Keys Animation', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('Source: %d notes total'):format(#raw),
        ('Animation notes (C2-C4): %s'):format(anim_note),
    }
    if stripped > 0 then
        lines[#lines + 1] = ('Excluded (lane markers / out of range): %s'):format(strip_note)
    end
    lines[#lines + 1] = ''
    if S.mc_keys_rh_tgt_idx >= 0 then
        lines[#lines + 1] = ('RH animation: %d notes written'):format(written_rh)
    end
    if S.mc_keys_lh_tgt_idx >= 0 then
        lines[#lines + 1] = ('LH animation: %d notes written'):format(written_lh)
    end

    local written_total = written_rh + written_lh
    S.status = ('Keys animation generated: %d note%s written.'):format(
        written_total, written_total == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end

function ConvertPianoToProKeys()
    if S.mc_keys_src_idx < 0 then
        S.status = 'Error: no source track selected.'
        S.last_result = 'Select the piano MIDI source track in the Hand Split section.'
        return
    end
    if S.mc_pk_conv_tgt_idx < 0 then
        S.status = 'Error: no Pro Keys target track selected.'
        S.last_result = 'Select the target track in the Convert to Pro Keys section.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_keys_src_idx)
    if not src_tr then
        S.status = 'Error: source track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes = ReadMIDINotesWithChannel(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.' or
                                  'Source track has no MIDI notes.'
        return
    end

    -- Octave-shift every note into [PK_MIN, PK_MAX] (C2-C4, MIDI 48-72).
    local out_notes   = {}
    local n_in_range  = 0
    local n_shift_up  = 0
    local n_shift_dn  = 0
    for _, n in ipairs(src_notes) do
        local p = n.pitch
        if p >= PK_MIN and p <= PK_MAX then
            n_in_range = n_in_range + 1
        elseif p < PK_MIN then
            repeat p = p + 12 until p >= PK_MIN
            n_shift_up = n_shift_up + 1
        else
            repeat p = p - 12 until p <= PK_MAX
            n_shift_dn = n_shift_dn + 1
        end
        out_notes[#out_notes + 1] = { s = n.s, e = n.e, pitch = p }
    end

    -- Deduplicate notes that shifted onto the same (time, pitch).
    -- Octave pairs like C#3+C#4 both map to C#3 after shifting - keep the longer one.
    local dedup = {}
    local n_collapsed = 0
    for _, n in ipairs(out_notes) do
        local key = math.floor(n.s * 1000 + 0.5) .. '_' .. n.pitch  -- 1 ms resolution
        local existing = dedup[key]
        if not existing then
            dedup[key] = n
        else
            if (n.e - n.s) > (existing.e - existing.s) then dedup[key] = n end
            n_collapsed = n_collapsed + 1
        end
    end
    do
        local deduped = {}
        for _, n in pairs(dedup) do deduped[#deduped + 1] = n end
        table.sort(deduped, function(a, b) return a.s < b.s end)
        out_notes = deduped
    end

    -- Optional lane shift marker insertion: walk converted notes and detect when the
    -- melody moves outside the current PK_RANGE window.
    local shift_markers = {}  -- { s = project_time, pitch = marker_pitch, range = new_range }

    if S.mc_pk_insert_shifts then
        -- Find initial best range for the first few notes.
        local function BestRangeForNote(p)
            local best_rng, best_score = PK_RANGES[1], -math.huge
            for _, rng in ipairs(PK_RANGES) do
                if p >= rng.lo and p <= rng.hi then
                    local score = 1000 - rng.pref
                    if score > best_score then best_score = score; best_rng = rng end
                end
            end
            return best_rng
        end

        local cur_range = BestRangeForNote(out_notes[1].pitch)
        for j = 2, #out_notes do
            local p = out_notes[j].pitch
            if p < cur_range.lo or p > cur_range.hi then
                -- Find new best range that contains this note.
                local new_range = BestRangeForNote(p)
                if new_range ~= cur_range then
                    -- Place marker ~1 measure before this note.
                    local marker_t = out_notes[j].s
                    local tidx = r.FindTempoTimeSigMarker(0, marker_t)
                    if tidx >= 0 then
                        local ok, tpos, _, _, bpm, num = r.GetTempoTimeSigMarker(0, tidx)
                        if ok and bpm and bpm > 0 then
                            local measure_dur = (num > 0 and num or 4) * 60.0 / bpm
                            marker_t = out_notes[j].s - measure_dur
                            if marker_t < (sel_s or 0) then marker_t = out_notes[j].s end
                        end
                    end
                    -- Marker pitch = range.lo - PK_MIN (maps C2->0, D2->2, E2->4, F2->5, G2->7, A2->9)
                    local marker_pitch = new_range.lo - PK_MIN
                    shift_markers[#shift_markers + 1] = {
                        s     = marker_t,
                        e     = marker_t + 0.125,  -- short fixed duration (1/8 note at 120 BPM)
                        pitch = marker_pitch,
                    }
                    cur_range = new_range
                end
            end
        end
    end

    local note_str = #src_notes == 1 and '1 note' or (#src_notes .. ' notes')

    if S.mc_keys_preview then
        local lines = {
            ('Source: %s'):format(note_str),
            '',
            ('Already in C2-C4:  %d notes'):format(n_in_range),
            ('Shifted up:      %d notes'):format(n_shift_up),
            ('Shifted down:    %d notes'):format(n_shift_dn),
        }
        if n_collapsed > 0 then
            lines[#lines + 1] = ('Octave pairs collapsed: %d  (voices merged to same pitch)'):format(n_collapsed)
        end
        if S.mc_pk_insert_shifts then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('Lane shift markers: %d'):format(#shift_markers)
        end
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Preview only - switch to Auto-insert and run again to write.'
        S.status = ('Pro Keys preview: %s \xe2\x80\x92 %d shifted (not written)'):format(
            note_str, n_shift_up + n_shift_dn)
        S.last_result = table.concat(lines, '\n')
        return
    end

    -- Combine melody notes and shift markers for writing.
    local all_out = {}
    for _, n in ipairs(out_notes)      do all_out[#all_out + 1] = n end
    for _, m in ipairs(shift_markers)  do all_out[#all_out + 1] = m end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local written = WriteNotesToTrack(S.mc_pk_conv_tgt_idx, all_out, sel_s, sel_e,
                                      'Convert Piano to Pro Keys')
    r.Undo_EndBlock2(0, 'Convert Piano to Pro Keys', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('Source: %s'):format(note_str),
        '',
        ('Already in C2-C4:  %d notes'):format(n_in_range),
        ('Shifted up:      %d notes'):format(n_shift_up),
        ('Shifted down:    %d notes'):format(n_shift_dn),
    }
    if n_collapsed > 0 then
        lines[#lines + 1] = ('Octave pairs collapsed: %d  (voices merged to same pitch)'):format(n_collapsed)
    end
    if S.mc_pk_insert_shifts then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Lane shift markers inserted: %d'):format(#shift_markers)
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('Total written: %d notes'):format(written)

    S.status = ('Pro Keys conversion: %d note%s written.'):format(
        written, written == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end

function ConvertKeys5()
    if S.mc_keys_src_idx < 0 then
        S.status = 'Error: no source track selected.'
        S.last_result = 'Select the piano MIDI source track in the Hand Split section.'
        return
    end
    if S.mc_5k_tgt_idx < 0 then
        S.status = 'Error: no 5-Lane Keys target selected.'
        S.last_result = 'Select the PART KEYS target track in the 5-Lane Keys section.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_keys_src_idx)
    if not src_tr then
        S.status = 'Error: source track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes = ReadMIDINotesWithChannel(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.' or
                                  'Source track has no MIDI notes.'
        return
    end

    -- Group simultaneous notes (within 10 ms) into chord events.
    local CHORD_WIN = 0.010
    local events = {}
    local i = 1
    while i <= #src_notes do
        local ev = { s = src_notes[i].s, e = src_notes[i].e, pitches = { src_notes[i].pitch } }
        i = i + 1
        while i <= #src_notes and (src_notes[i].s - ev.s) <= CHORD_WIN do
            ev.pitches[#ev.pitches + 1] = src_notes[i].pitch
            if src_notes[i].e > ev.e then ev.e = src_notes[i].e end
            i = i + 1
        end
        table.sort(ev.pitches)
        events[#events + 1] = ev
    end

    -- Assign gem positions using a sliding 5-semitone window [root, root+4] -> gems 96-100.
    local WINDOW_SIZE = 5
    local GEM_BASE    = 96
    local window_root   = nil
    local last_event_e  = -math.huge
    local out_notes     = {}
    local window_shifts = 0
    local phrase_resets = 0

    for _, ev in ipairs(events) do
        -- Phrase gap: reset window root.
        if window_root and (ev.s - last_event_e) * 1000 > S.mc_5k_phrase_gap_ms then
            window_root  = nil
            phrase_resets = phrase_resets + 1
        end

        local chord = CompressChord(ev.pitches, S.mc_5k_max_chord)
        local min_p = chord[1]
        local max_p = chord[#chord]

        -- Initialise or shift window to accommodate this chord.
        if not window_root then
            window_root = min_p
        elseif max_p > window_root + WINDOW_SIZE - 1 then
            -- Chord goes above top of window: anchor to high end (shift up).
            local new_root = max_p - (WINDOW_SIZE - 1)
            if new_root > min_p then new_root = min_p end  -- keep min_p inside if possible
            if new_root ~= window_root then
                window_root   = new_root
                window_shifts = window_shifts + 1
            end
        elseif min_p < window_root then
            -- Chord goes below bottom: shift down to include min_p.
            window_root   = min_p
            window_shifts = window_shifts + 1
        end

        -- Map pitches to gem positions, clamping to [0, WINDOW_SIZE-1] for any
        -- chord that spans more than WINDOW_SIZE semitones.
        local gem_set = {}
        for _, p in ipairs(chord) do
            local pos = p - window_root
            if pos < 0               then pos = 0               end
            if pos > WINDOW_SIZE - 1 then pos = WINDOW_SIZE - 1 end
            gem_set[pos] = true
        end
        for pos in pairs(gem_set) do
            out_notes[#out_notes + 1] = { s = ev.s, e = ev.e, pitch = GEM_BASE + pos }
        end

        last_event_e = ev.e
    end

    local note_str = #src_notes == 1 and '1 note' or (#src_notes .. ' notes')

    if S.mc_keys_preview then
        local lines = {
            ('Source: %s in %d chord events'):format(note_str, #events),
            ('Output: %d gem notes (96-100)'):format(#out_notes),
            ('Phrase resets: %d  |  Window shifts: %d'):format(phrase_resets, window_shifts),
            '',
            'Preview only - switch to Auto-insert and run again to write.',
        }
        S.status = ('5-Lane preview: %d events \xe2\x80\x92 %d gems (not written)'):format(
            #events, #out_notes)
        S.last_result = table.concat(lines, '\n')
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local written = WriteNotesToTrack(S.mc_5k_tgt_idx, out_notes, sel_s, sel_e, 'Convert 5-Lane Keys')
    r.Undo_EndBlock2(0, 'Convert 5-Lane Keys', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('Source: %s in %d chord events'):format(note_str, #events),
        ('Output: %d gem notes written (96-100)'):format(written),
        ('Phrase resets: %d  |  Window shifts: %d'):format(phrase_resets, window_shifts),
    }
    S.status = ('5-Lane Keys: %d gem note%s written.'):format(
        written, written == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end

