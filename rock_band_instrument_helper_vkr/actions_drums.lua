-- MIDI converter: GM drum notation → Rock Band 5-lane drums
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, InsertNotes (globals)

-- GM pitch → { rb = RB gem note, tm = tom marker note or 0 }
-- In Pro Drums, 98/99/100 default to cymbal display. Adding tm (110/111/112)
-- switches the gem display to a tom pad. Cymbals get tm=0 (no marker needed).
-- Crash pitches (49, 55, 57) are handled separately via BuildMap() because
-- they are configurable: yellow (98) or green (100). Both are cymbals, so tm=0.
local GM_DRUM_MAP = {
    [35] = { rb = 96,  tm = 0   },  -- Acoustic Bass Drum → Kick
    [36] = { rb = 96,  tm = 0   },  -- Bass Drum 1 → Kick
    [38] = { rb = 97,  tm = 0   },  -- Acoustic Snare → Red
    [40] = { rb = 97,  tm = 0   },  -- Electric Snare → Red
    [42] = { rb = 98,  tm = 0   },  -- Closed Hi-Hat → Yellow cymbal (no marker = cymbal)
    [44] = { rb = 98,  tm = 0   },  -- Pedal Hi-Hat → Yellow cymbal
    [46] = { rb = 98,  tm = 0   },  -- Open Hi-Hat → Yellow cymbal
    [51] = { rb = 99,  tm = 0   },  -- Ride 1 → Blue cymbal
    [53] = { rb = 99,  tm = 0   },  -- Ride Bell → Blue cymbal
    [59] = { rb = 99,  tm = 0   },  -- Ride 2 → Blue cymbal
    [48] = { rb = 98,  tm = 110 },  -- Hi-Mid Tom → Yellow tom (marker 110 → tom)
    [50] = { rb = 98,  tm = 110 },  -- High Tom → Yellow tom
    [45] = { rb = 99,  tm = 111 },  -- Low Tom → Blue tom
    [47] = { rb = 99,  tm = 111 },  -- Low-Mid Tom → Blue tom
    [41] = { rb = 100, tm = 112 },  -- Low Floor Tom → Green tom
    [43] = { rb = 100, tm = 112 },  -- High Floor Tom → Green tom
    [52] = { rb = 100, tm = 0   },  -- Chinese Cymbal → Green cymbal (no marker = cymbal)
}

local CRASH_PITCHES = { 49, 55, 57 }  -- Crash 1, Splash, Crash 2

local NOTE_DUR_S = 0.05  -- fixed length for all drum gem notes (~1/32nd at 120 BPM)

local LANE_NAMES = {
    [96]  = 'Kick',
    [97]  = 'Red (snare)',
    [98]  = 'Yellow',
    [99]  = 'Blue',
    [100] = 'Green',
}

-- Build the full GM→RB mapping including the configurable crash assignment.
-- Called fresh on each convert so the crash toggle takes effect immediately.
local function BuildMap()
    local map = {}
    for k, v in pairs(GM_DRUM_MAP) do map[k] = v end
    local rb = S.mc_crash_to_green and 100 or 98
    for _, p in ipairs(CRASH_PITCHES) do
        map[p] = { rb = rb, tm = 0 }  -- crash is always a cymbal; no tom marker
    end
    return map
end

-- Read all notes with velocity and channel from every MIDI item on a track,
-- optionally restricted to [t_s, t_e]. Returns array sorted by start time.
local function ReadMIDINotes(track, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, _, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = { s = s, pitch = pitch, vel = vel }
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Apply the GM map to source notes. Returns (out_notes, counts, unmapped, n_ghost).
local function BuildDrumOutput(src_notes, gm_map)
    local out_notes = {}
    local counts    = {}
    local unmapped  = {}
    local n_ghost   = 0

    for _, n in ipairs(src_notes) do
        if n.vel <= S.mc_ghost_thresh then
            n_ghost = n_ghost + 1
        else
            local m = gm_map[n.pitch]
            if m then
                out_notes[#out_notes + 1] = { s = n.s, e = n.s + NOTE_DUR_S, pitch = m.rb }
                counts[m.rb] = (counts[m.rb] or 0) + 1
                if S.mc_pro_drums and m.tm ~= 0 then
                    out_notes[#out_notes + 1] = { s = n.s, e = n.s + NOTE_DUR_S, pitch = m.tm }
                end
            else
                unmapped[n.pitch] = (unmapped[n.pitch] or 0) + 1
            end
        end
    end

    return out_notes, counts, unmapped, n_ghost
end

local function BuildReport(src_notes, counts, unmapped, n_ghost, preview)
    local total_rb = 0
    for _, c in pairs(counts) do total_rb = total_rb + c end

    local lines = {}
    lines[#lines + 1] = ('Source notes: %d  (%d ghost-skipped)'):format(#src_notes, n_ghost)
    lines[#lines + 1] = ''
    for _, rb in ipairs({96, 97, 98, 99, 100}) do
        if counts[rb] then
            lines[#lines + 1] = ('  %-16s %d'):format(LANE_NAMES[rb], counts[rb])
        end
    end
    if next(unmapped) then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Unmapped GM pitches (skipped):'
        for pitch, cnt in pairs(unmapped) do
            lines[#lines + 1] = ('  GM %d  \xc3\x97%d'):format(pitch, cnt)
        end
    end
    if preview then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Preview only - switch to Auto-insert and run again to write.'
    end
    return total_rb, table.concat(lines, '\n')
end

function ConvertDrums()
    if S.mc_drum_src_idx < 0 then
        S.status = 'Error: no drum source track selected.'
        S.last_result = 'Select the source MIDI drum track in the Drums tab.'
        return
    end
    if S.mc_drum_tgt_idx < 0 then
        S.status = 'Error: no drum target track selected.'
        S.last_result = 'Select the PART DRUMS target track in the Drums tab.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_drum_src_idx)
    local tgt_tr = r.GetTrack(0, S.mc_drum_tgt_idx)
    if not src_tr or not tgt_tr then
        S.status = 'Error: a selected track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes = ReadMIDINotes(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.' or
                                  'Source track has no MIDI notes.'
        return
    end

    local gm_map = BuildMap()
    local out_notes, counts, unmapped, n_ghost = BuildDrumOutput(src_notes, gm_map)
    local total_rb, report = BuildReport(src_notes, counts, unmapped, n_ghost, S.mc_drum_preview)

    if S.mc_drum_preview then
        S.status = ('Drum preview: %d source → %d RB notes (not written)'):format(
            #src_notes, total_rb)
        S.last_result = report
        return
    end

    local tgt_item, tgt_take = FindFirstMIDIItem(tgt_tr)
    if not tgt_item then
        S.status = 'Error: target track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART DRUMS target track first.'
        return
    end

    local ip      = r.GetMediaItemInfo_Value(tgt_item, 'D_POSITION')
    local ie      = ip + r.GetMediaItemInfo_Value(tgt_item, 'D_LENGTH')
    local clear_s = sel_s and math.max(sel_s, ip) or ip
    local clear_e = sel_e and math.min(sel_e, ie) or ie

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(tgt_tr, tgt_item)
    local drum_pitches = {
        [96]=true,[97]=true,[98]=true,[99]=true,[100]=true,
        [110]=true,[111]=true,[112]=true,
    }
    ClearNotesAtPitchesInRange(tgt_take, drum_pitches, clear_s, clear_e)
    InsertNotes(tgt_take, out_notes, 100)
    r.Undo_EndBlock2(0, 'Convert Drums to Rock Band', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Drums converted: %d RB notes inserted.'):format(total_rb)
    S.last_result = report
end
