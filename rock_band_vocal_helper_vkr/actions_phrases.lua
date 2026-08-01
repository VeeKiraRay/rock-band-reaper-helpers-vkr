-- Phrases tab actions (CreatePhrasesAction, NoteLenPPQ); ParseLyricsLines from
-- actions_lyrics.lua supplies line-preserving lyric parsing.

----------------------------------------------------------------------
-- Module constants (local - not user-tunable, no UI, no persistence)
----------------------------------------------------------------------
local GRID_DENOM        = 32   -- pass-1 placement grid, and the unit everything else in phase 2
                                -- is expressed as an integer multiple of: 1 unit = 1/32 note
local IDEAL_UNITS       = 4    -- ideal lead-in/tail growth cap, in grid units (4 = 1/8 note)
local GAP_IDEAL_UNITS   = 4    -- ideal final gap between adjacent phrase markers (1/8 note) - a
                                -- distinct constant from IDEAL_UNITS even though both are 4 today:
                                -- conceptually different things (gap between markers vs. one
                                -- edge's growth past its note)
local MIN_EDGE_UNITS    = 1    -- guaranteed minimum lead-in/tail growth (1/32 note each),
                                -- prioritized ahead of growing the gap toward GAP_IDEAL_UNITS
local NEXT_LEADIN_SHARE = 0.6  -- of leftover room (after the gap and each side's minimum are
                                -- reserved), 60% grows the next phrase's lead-in, 40% grows this
                                -- phrase's tail (lead-in prioritized per user direction)

----------------------------------------------------------------------
-- Grid math
----------------------------------------------------------------------
-- Global (promoted for testability, same as EditDistance/ParseLyricsFile):
-- also used by dev/tests/vocal_midi.lua to compute the grid unit for its
-- grid-alignment assertions. Formula duplicated from actions_midi_length.lua
-- (general helper's tree isn't dofile'd here, only lib/ is shared).
function NoteLenPPQ(ppq_per_qn, denom)
    return math.floor(ppq_per_qn * 4 / denom + 0.5)
end

local function SnapDown(ppq, grid) return math.floor(ppq / grid) * grid end
local function SnapUp(ppq, grid)   return math.ceil(ppq  / grid) * grid end

----------------------------------------------------------------------
-- Beat/measure boundary lookup (local)
----------------------------------------------------------------------
-- Nearest beat-grid PPQ to ppq_pos. Uses TimeMap2_timeToBeats' 4th return
-- only (fullbeats, running total) - the 3rd return is beats-within-measure,
-- not safe here (see .claude/CLAUDE_general.md).
local function NearestBeatPpq(take, ppq_pos)
    local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local _, _, _, fullbeats = r.TimeMap2_timeToBeats(0, t)
    local snapped_t = r.TimeMap2_beatsToTime(0, math.floor(fullbeats + 0.5))
    return r.MIDI_GetPPQPosFromProjTime(take, snapped_t)
end

-- Nearest half-beat-grid PPQ to ppq_pos - a lower-priority fallback snap
-- candidate (see GrowEdge) for when neither a measure nor a full-beat
-- boundary falls within the growth window. Same fullbeats-only approach as
-- NearestBeatPpq, rounded to the nearest 0.5 beat instead of 1.0.
local function NearestHalfBeatPpq(take, ppq_pos)
    local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local _, _, _, fullbeats = r.TimeMap2_timeToBeats(0, t)
    local snapped_t = r.TimeMap2_beatsToTime(0, math.floor(fullbeats * 2 + 0.5) / 2)
    return r.MIDI_GetPPQPosFromProjTime(take, snapped_t)
end

-- Nearest quarter-beat-grid PPQ to ppq_pos - the lowest-priority landmark
-- (see GrowEdge), tried when neither measure, beat, nor half-beat falls
-- within the growth window. Same fullbeats-only approach as NearestBeatPpq,
-- rounded to the nearest 0.25 beat instead of 1.0.
local function NearestQuarterBeatPpq(take, ppq_pos)
    local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local _, _, _, fullbeats = r.TimeMap2_timeToBeats(0, t)
    local snapped_t = r.TimeMap2_beatsToTime(0, math.floor(fullbeats * 4 + 0.5) / 4)
    return r.MIDI_GetPPQPosFromProjTime(take, snapped_t)
end

-- Nearest measure-start PPQ to ppq_pos. Same estimate-then-forward-walk
-- pattern as the general helper's FindNextMeasureStartPpq (venue_lighting.lua)
-- - not directly callable here (different dofile tree), so reimplemented.
local function NearestMeasurePpq(take, ppq_pos)
    local t  = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local qn = r.TimeMap_timeToQN(t)
    local est = math.max(0, math.floor(qn / 4) - 1)
    local t0, t1 = t, t
    for m = est, est + 30 do
        local ts, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, m)
        if not qn_s then break end
        if qn_e > qn - 1e-9 then
            t0 = ts
            local ts_next = ({ r.TimeMap_GetMeasureInfo(0, m + 1) })[1]
            t1 = ts_next or ts
            break
        end
    end
    local best_t = (math.abs(t1 - t) < math.abs(t - t0)) and t1 or t0
    return r.MIDI_GetPPQPosFromProjTime(take, best_t)
end

----------------------------------------------------------------------
-- Note/lyric collection (local)
----------------------------------------------------------------------
-- Scoped vocal-range notes (same filter/sort as AssignLyricsAction - whole
-- take, RB3_MIN_PITCH..RB3_MAX_PITCH) in raw take PPQ (grid math needs PPQ,
-- not seconds), plus a ppq -> lyric-text lookup from type-5 events.
local function CollectScopedAndLyrics(midi_take)
    local scoped = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            scoped[#scoped + 1] = { s_ppq = sppq, e_ppq = eppq }
        end
    end
    table.sort(scoped, function(a, b) return a.s_ppq < b.s_ppq end)

    local lyric_at = {}
    local _, _, _, n_text = r.MIDI_CountEvts(midi_take)
    for i = 0, n_text - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 then lyric_at[ppq] = msg end
    end
    return scoped, lyric_at
end

----------------------------------------------------------------------
-- Mismatch validation (local, read-only)
----------------------------------------------------------------------
-- Returns nil (no mismatches) or an array of { line_no, word_idx, word, s_ppq }.
-- Checks i = 1..min(#flat, #scoped) - the full range AssignLyricsAction would
-- have written, not just line-boundary words, so drift anywhere is caught.
local function FindMismatches(flat, scoped, lyric_at, lines)
    local mismatches = {}
    local n = math.min(#flat, #scoped)
    local line_no_at = {}  -- word index -> 1-based line number, for reporting
    for ln, line in ipairs(lines) do
        for idx = line.start_idx, line.end_idx do line_no_at[idx] = ln end
    end
    for i = 1, n do
        local actual = lyric_at[scoped[i].s_ppq]
        if actual ~= flat[i] then
            mismatches[#mismatches + 1] = {
                line_no = line_no_at[i], word_idx = i, word = flat[i],
                s_ppq = scoped[i].s_ppq, actual = actual,
            }
        end
    end
    return #mismatches > 0 and mismatches or nil
end

----------------------------------------------------------------------
-- Phase 1 - pass-1 placement + sequential collision check + insert (local)
----------------------------------------------------------------------
-- Runs only after FindMismatches returns nil (validate everything first,
-- mutate second). `lines` beyond the last one whose start_idx fits within
-- #scoped are the "excess lyrics" case (ran out of notes) - not an abort.
-- Returns snapshot ({pass1_start_ppq, pass1_end_ppq, note_idx} per phrase,
-- in line order), K (= #snapshot), collision (nil or details), excess_lines.
local function RunPhase1(midi_take, lines, scoped, thirty2_ppq)
    local n_scoped = #scoped
    local m = 0
    for _, line in ipairs(lines) do
        if line.start_idx <= n_scoped then m = m + 1 else break end
    end

    local snapshot, collision = {}, nil
    for k = 1, m do
        local line = lines[k]
        local next_start = (lines[k + 1] and lines[k + 1].start_idx) or (n_scoped + 1)
        local last_note_idx = math.min(line.end_idx, next_start - 1, n_scoped)
        local raw_start_ppq = SnapDown(scoped[line.start_idx].s_ppq, thirty2_ppq)
        local raw_end_ppq   = SnapUp(scoped[last_note_idx].e_ppq, thirty2_ppq)

        if k > 1 and raw_start_ppq - snapshot[k - 1].pass1_end_ppq < thirty2_ppq then
            collision = {
                line_a = k - 1, line_b = k,
                pos_a = snapshot[k - 1].pass1_end_ppq, pos_b = raw_start_ppq,
            }
            break
        end

        r.MIDI_InsertNote(midi_take, false, false, raw_start_ppq, raw_end_ppq, 0,
            RB3_PHRASE_PITCH, S.velocity, false)
        snapshot[#snapshot + 1] = { pass1_start_ppq = raw_start_ppq, pass1_end_ppq = raw_end_ppq }
    end

    -- One rescan to map each snapshot entry to its (post-insert, re-sorted)
    -- note index, by exact-integer-PPQ match on pass1_start_ppq - avoids
    -- noSort=true on inserts (CLAUDE.md warns that breaks undo detection).
    local by_start_ppq = {}
    for k = 1, #snapshot do by_start_ppq[snapshot[k].pass1_start_ppq] = k end
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(midi_take, i)
        if ok and p == RB3_PHRASE_PITCH then
            local k = by_start_ppq[sppq]
            if k then snapshot[k].note_idx = i end
        end
    end

    return snapshot, #snapshot, collision, #lines - m
end

----------------------------------------------------------------------
-- Phase 2 - spacing refinement (local)
----------------------------------------------------------------------
-- direction: -1 grows the start earlier, +1 grows the end later. budget_units
-- and ideal_units are integer counts of thirty2_ppq grid steps - working in
-- whole grid units (rather than fractional ppq clamped to a fractional
-- bound) guarantees every returned edge is an exact multiple of thirty2_ppq,
-- for both note edges, with no separate snapping/clamping step needed: the
-- plain-grid fallback IS pass1_edge_ppq plus a whole number of grid steps.
local function GrowEdge(take, pass1_edge_ppq, direction, budget_units, ideal_units, thirty2_ppq)
    if budget_units <= 0 then return pass1_edge_ppq end
    local grow_units = math.min(budget_units, ideal_units)
    local target_ppq = pass1_edge_ppq + direction * grow_units * thirty2_ppq

    -- Landmark window: represents between 1 and budget_units grid-steps of
    -- growth (any nonzero growth qualifies - no separate minimum threshold;
    -- coarser landmarks like measure/beat simply won't often fall within a
    -- small budget window, so they naturally only win when there's enough
    -- room for them to be in range). Tolerant of float fuzz from the
    -- tempo-map round trip (time <-> beats <-> ppq) that produces the
    -- landmark candidates below.
    local function in_range(ppq)
        local units = (ppq - pass1_edge_ppq) * direction / thirty2_ppq
        return units >= 1 - 1e-6 and units <= budget_units + 1e-6
    end

    local m_ppq = NearestMeasurePpq(take, target_ppq)
    local b_ppq = NearestBeatPpq(take, target_ppq)
    local h_ppq = NearestHalfBeatPpq(take, target_ppq)
    local q_ppq = NearestQuarterBeatPpq(take, target_ppq)
    local m_ok, b_ok, h_ok, q_ok = in_range(m_ppq), in_range(b_ppq), in_range(h_ppq), in_range(q_ppq)

    if m_ok and b_ok then
        -- Prefer measure unless the beat candidate is clearly closer to the
        -- ideal target (tie window: within one 32nd note of each other).
        if math.abs(m_ppq - target_ppq) <= math.abs(b_ppq - target_ppq) + thirty2_ppq then
            return m_ppq
        end
        return b_ppq
    elseif m_ok then
        return m_ppq
    elseif b_ok then
        return b_ppq
    elseif h_ok then
        return h_ppq
    elseif q_ok then
        -- Lowest-priority landmark: neither measure, beat, nor half-beat
        -- falls within the growth window, but a quarter-beat does.
        return q_ppq
    end

    -- No qualifying landmark: exact grid-unit growth - already grid-aligned
    -- by construction (pass1_edge_ppq is a grid multiple, grow_units is a
    -- whole number), no snapping or clamping needed.
    return target_ppq
end

-- Reads only snapshot[] (phase-1 values) for neighbor lookups - matches
-- actions_midi_length.lua's AdjustSustainGaps precedent (original snapshotted
-- positions, not evolving live state). Writes via MIDI_SetNote(noSort=true).
local function RunPhase2(midi_take, snapshot, ideal_units, thirty2_ppq)
    local k_count = #snapshot
    if k_count == 0 then return end

    local final_start, final_end = {}, {}

    for k = 1, k_count - 1 do
        -- Exact integer: both pass1 positions are already grid multiples.
        local available_units = (snapshot[k + 1].pass1_start_ppq - snapshot[k].pass1_end_ppq) / thirty2_ppq
        local remaining = available_units

        -- Priority waterfall (highest first):
        --   1. Hard gap floor (1 unit) - always affordable, phase 1's own guarantee.
        --   2. A guaranteed minimum of individual growth for EACH side, before
        --      the gap gets to grow further - a phrase touching its neighbor's
        --      note reads worse than a slightly-smaller-than-ideal gap.
        --   3. Grow the gap the rest of the way toward its own ideal.
        --   4. Any further leftover: 60/40 split on top of step 2's minimum,
        --      each still capped at the individual ideal.
        local gap_units = 1
        remaining = remaining - 1

        local leadin_units = math.min(MIN_EDGE_UNITS, remaining)
        remaining = remaining - leadin_units
        local tail_units = math.min(MIN_EDGE_UNITS, remaining)
        remaining = remaining - tail_units

        local gap_extra = math.min(GAP_IDEAL_UNITS - gap_units, remaining)
        remaining = remaining - gap_extra

        -- ceil (not floor) so lead-in never loses a tied/rounded-down split
        -- at small leftovers - keeps "lead-in prioritized" true throughout.
        local leadin_extra = math.min(math.ceil(remaining * NEXT_LEADIN_SHARE), ideal_units - leadin_units)
        leadin_units = leadin_units + leadin_extra
        remaining = remaining - leadin_extra
        local tail_extra = math.min(remaining, ideal_units - tail_units)
        tail_units = tail_units + tail_extra

        final_end[k] = GrowEdge(midi_take, snapshot[k].pass1_end_ppq, 1,
            tail_units, ideal_units, thirty2_ppq)
        final_start[k + 1] = GrowEdge(midi_take, snapshot[k + 1].pass1_start_ppq, -1,
            leadin_units, ideal_units, thirty2_ppq)
    end

    -- First/last phrase: no neighbor on that side, grow freely toward the ideal.
    final_start[1] = GrowEdge(midi_take, snapshot[1].pass1_start_ppq, -1,
        ideal_units, ideal_units, thirty2_ppq)
    final_end[k_count] = GrowEdge(midi_take, snapshot[k_count].pass1_end_ppq, 1,
        ideal_units, ideal_units, thirty2_ppq)

    final_start[1] = math.max(0, final_start[1])

    for k = 1, k_count do
        r.MIDI_SetNote(midi_take, snapshot[k].note_idx, false, false,
            final_start[k], final_end[k], 0, RB3_PHRASE_PITCH, S.velocity, true)
    end
end

----------------------------------------------------------------------
-- Phrases action
----------------------------------------------------------------------
function CreatePhrasesAction()
    if S.lyrics_path == '' then
        S.status = 'No lyrics file selected.'
        S.last_result = 'Use Auto-detect or Browse to select a lyrics file first.'
        return
    end

    local lines, flat = ParseLyricsLines(S.lyrics_path)
    if not lines then S.status = 'Error'; S.last_result = flat; return end

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

    local scoped, lyric_at = CollectScopedAndLyrics(midi_take)
    if #scoped == 0 then
        S.status = 'No notes in range.'
        S.last_result = 'No notes in the RB3 vocal range found on the destination take.'
        return
    end

    local mismatches = FindMismatches(flat, scoped, lyric_at, lines)
    if mismatches then
        local out = { ('Lyrics out of sync: %d mismatch(es):'):format(#mismatches) }
        for _, m in ipairs(mismatches) do
            local t = r.MIDI_GetProjTimeFromPPQPos(midi_take, m.s_ppq)
            out[#out + 1] = ('  line %d, word %d: expected "%s", found %s at %s'):format(
                m.line_no or 0, m.word_idx, m.word,
                m.actual and ('"' .. m.actual .. '"') or '(none)', FormatTime(t))
        end
        out[#out + 1] = ''
        out[#out + 1] = 'Run Assign lyrics first, then try Create phrases again.'
        S.status = 'Error: lyrics out of sync.'
        S.last_result = table.concat(out, '\n')
        return
    end

    local ppq_per_qn  = GetTakePPQPerQN(midi_take)
    local thirty2_ppq = NoteLenPPQ(ppq_per_qn, GRID_DENOM)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(midi_track, midi_item)

    local item_pos = r.GetMediaItemInfo_Value(midi_item, 'D_POSITION')
    local item_len = r.GetMediaItemInfo_Value(midi_item, 'D_LENGTH')
    local cleared = ClearNotesAtPitchesInRange(midi_take, { [RB3_PHRASE_PITCH] = true },
        item_pos, item_pos + item_len)

    local snapshot, K, collision, excess_lines = RunPhase1(midi_take, lines, scoped, thirty2_ppq)
    RunPhase2(midi_take, snapshot, IDEAL_UNITS, thirty2_ppq)

    r.Undo_EndBlock2(0, ('Vocal Helper: created %d phrase markers'):format(K), -1)
    r.PreventUIRefresh(-1)

    local lines_out = {}
    lines_out[#lines_out + 1] = ('Phrase markers created: %d'):format(K)
    lines_out[#lines_out + 1] = 'Scope: whole take'
    lines_out[#lines_out + 1] = ('Cleared %d existing phrase markers first'):format(cleared)

    if excess_lines > 0 then
        lines_out[#lines_out + 1] = ''
        lines_out[#lines_out + 1] = ('Warning: %d line(s) after the last available note were not processed.')
            :format(excess_lines)
    end

    if collision then
        lines_out[#lines_out + 1] = ''
        local ta = r.MIDI_GetProjTimeFromPPQPos(midi_take, collision.pos_a)
        local tb = r.MIDI_GetProjTimeFromPPQPos(midi_take, collision.pos_b)
        lines_out[#lines_out + 1] = ('Stopped at lines %d/%d: not enough room for a 1/32-note gap ' ..
            '(previous phrase ends %s, next phrase would start %s).'):format(
            collision.line_a, collision.line_b, FormatTime(ta), FormatTime(tb))
        lines_out[#lines_out + 1] = "Shorten the previous phrase's last note, or add spacing, then re-run."
    end

    S.status = collision and 'Stopped early - see details.' or ('Created %d phrase markers.'):format(K)
    S.last_result = table.concat(lines_out, '\n')
end
