-- Drums 2x kick action functions (General tab)
-- Requires: S, r (globals)
-- Requires: FindTrackByName, GetTakePPQPerQN (from helpers.lua)

local TRACK_2X = 'PART DRUMS_2X'
local TRACK_1X = 'PART DRUMS'
local MARK_2X  = 95   -- 2x kick marker on PART DRUMS_2X
local KICK     = 96   -- Expert kick gem on both drum tracks

-- Matching guards, in quarter notes. See the comment above MatchMarkers for why
-- a nearest-with-ambiguity-guard beats a fixed tolerance.
local MAX_SNAP_QN     = 0.03125  -- a 1/32 note: nothing further away is "the same note"
local AMBIGUITY_RATIO = 0.25     -- the winner must be 4x closer than the runner-up

local UNMATCHED_LIST_MAX = 20    -- cap the report; a broken chart must not dump 500 lines

-- "M.B.HH" position string at quarter-note position qn, e.g. "27.3.00".
-- Display only - the seconds conversion never feeds a match decision.
local function MBTAtQN(qn)
    return r.format_timestr_pos(r.TimeMap2_QNToTime(0, qn), '', 1)
end

-- Collect every MIDI take on a track, with its item (both are needed:
-- MarkTrackItemsDirty takes the item, the note calls take the take).
local function MIDITakesOn(track)
    local out = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            out[#out + 1] = { item = item, take = take }
        end
    end
    return out
end

-- Every note at `pitch` across a list of takes, as { qn = , take = , item = , idx = },
-- sorted by musical position.
--
-- QUARTER NOTES, NOT SECONDS. A note's QN position is what the MIDI data natively
-- stores; a tempo change alters seconds-per-QN, never the QN number. Reading one
-- track in seconds and converting back on the other walks the project tempo map
-- twice in opposite directions, and the round trip is only exact while both takes
-- share one linear mapping - i.e. before the first tempo marker. After one, even
-- grid-quantized notes land a few ms out, which is many ticks at a metal tempo.
-- The same rule governs the difficulty validators' beat-fraction checks.
local function NotesAtPitch(takes, pitch)
    local notes = {}
    for _, tk in ipairs(takes) do
        local _, n_notes = r.MIDI_CountEvts(tk.take)
        for i = 0, n_notes - 1 do
            local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(tk.take, i)
            if ok and p == pitch then
                notes[#notes + 1] = {
                    qn    = r.MIDI_GetProjQNFromPPQPos(tk.take, sppq),
                    take  = tk.take,
                    item  = tk.item,
                    idx   = i,
                    pitch = p,
                }
            end
        end
    end
    table.sort(notes, function(a, b) return a.qn < b.qn end)
    return notes
end

-- Ticks and milliseconds a QN distance corresponds to at `qn`, for the report.
local function DescribeGap(d_qn, qn, ppq_per_qn)
    local ms = (r.TimeMap2_QNToTime(0, qn + d_qn)
              - r.TimeMap2_QNToTime(0, qn)) * 1000
    return ('%.1f ticks (%.1f ms)'):format(d_qn * ppq_per_qn, math.abs(ms))
end

-- Pair each marker with the kick it refers to.
--
-- NEAREST, NOT "WITHIN N MILLISECONDS". PART DRUMS_2X normally carries every kick -
-- the 1x ones as 96, the double kicks as 95 - because the workflow is to author all
-- of them, copy the lot into both tracks, then remove the excess. So a marker's kick
-- is normally at the identical QN, and the interesting question is not "how close is
-- close enough" but "is this the right one of two candidates". In a blast beat the
-- neighbouring kick is only a 1/32 away, so any fixed buffer generous enough to
-- forgive hand-nudging is also large enough to grab the wrong note. Comparing the
-- nearest against the runner-up tightens automatically exactly where it must.
--
-- Both lists are sorted by qn, so a moving insertion point plus a few entries
-- either side finds every candidate: SCAN_SPAN kicks away is at least
-- SCAN_SPAN/32 QN even in a continuous 1/32 blast beat, already past MAX_SNAP_QN.
--
-- Returns matched (array of kick entries to delete) and misses (array of
-- { qn = , why = } for the report). Each kick is claimed at most once.
local SCAN_SPAN = 4

local function MatchMarkers(markers, kicks, ppq_per_qn)
    local matched, misses = {}, {}
    local claimed = {}
    local n, j    = #kicks, 1
    for _, m in ipairs(markers) do
        while j <= n and kicks[j].qn < m.qn do j = j + 1 end
        -- best     = nearest kick not already taken by an earlier marker
        -- runner_d = nearest OTHER kick, claimed or not; a claimed neighbour is
        --            still evidence that two markers are competing for one spot
        local best, best_d, runner_d = nil, math.huge, math.huge
        for k = math.max(1, j - SCAN_SPAN), math.min(n, j + SCAN_SPAN) do
            local d = math.abs(kicks[k].qn - m.qn)
            if claimed[k] then
                if d < runner_d then runner_d = d end
            elseif d < best_d then
                if best_d < runner_d then runner_d = best_d end
                best, best_d = k, d
            elseif d < runner_d then
                runner_d = d
            end
        end
        if not best then
            misses[#misses + 1] = { qn = m.qn,
                why = 'no kick on ' .. TRACK_1X .. ' anywhere near' }
        elseif best_d > MAX_SNAP_QN then
            misses[#misses + 1] = { qn = m.qn,
                why = 'nearest kick ' .. DescribeGap(best_d, m.qn, ppq_per_qn) ..
                      ' away - too far' }
        elseif best_d > runner_d * AMBIGUITY_RATIO then
            misses[#misses + 1] = { qn = m.qn,
                why = 'nearest kick ' .. DescribeGap(best_d, m.qn, ppq_per_qn) ..
                      ' away, but another is nearly as close - ambiguous' }
        else
            claimed[best]         = true
            matched[#matched + 1] = kicks[best]
        end
    end
    return matched, misses
end

-- Remove every kick on PART DRUMS that lines up with a 2x kick marker on
-- PART DRUMS_2X. Whole track - a time selection does not narrow it.
function RemoveKicksMarkedBy2X()
    local src_tr = FindTrackByName(TRACK_2X)
    if not src_tr then
        S.status      = 'Error: ' .. TRACK_2X .. ' track not found.'
        S.last_result = 'Could not find a track named "' .. TRACK_2X .. '".'
        return
    end
    local tgt_tr = FindTrackByName(TRACK_1X)
    if not tgt_tr then
        S.status      = 'Error: ' .. TRACK_1X .. ' track not found.'
        S.last_result = 'Could not find a track named "' .. TRACK_1X .. '".'
        return
    end
    for _, pair in ipairs({ { src_tr, TRACK_2X }, { tgt_tr, TRACK_1X } }) do
        if r.GetMediaTrackInfo_Value(pair[1], 'B_MUTE') == 1 then
            S.status      = 'Error: ' .. pair[2] .. ' is muted.'
            S.last_result = 'Unmute ' .. pair[2] .. ' and run this again.\n' ..
                            'A muted drum track is treated as not part of the chart.'
            return
        end
    end

    local src_takes = MIDITakesOn(src_tr)
    if #src_takes == 0 then
        S.status      = 'Error: ' .. TRACK_2X .. ' has no MIDI item.'
        S.last_result = TRACK_2X .. ' track has no MIDI item to read markers from.'
        return
    end
    local tgt_takes = MIDITakesOn(tgt_tr)
    if #tgt_takes == 0 then
        S.status      = 'Error: ' .. TRACK_1X .. ' has no MIDI item.'
        S.last_result = TRACK_1X .. ' track has no MIDI item to remove kicks from.'
        return
    end

    local markers = NotesAtPitch(src_takes, MARK_2X)
    if #markers == 0 then
        S.status      = TRACK_2X .. ' has no 2x kick markers (pitch ' .. MARK_2X .. ').'
        S.last_result = 'Nothing to do: ' .. TRACK_2X .. ' carries no pitch-' .. MARK_2X ..
                        ' notes.\nThose are the markers this action reads.'
        return
    end

    local kicks   = NotesAtPitch(tgt_takes, KICK)
    local src_1x  = NotesAtPitch(src_takes, KICK)   -- for the consistency check below
    local matched, misses = MatchMarkers(markers, kicks,
                                         GetTakePPQPerQN(tgt_takes[1].take))

    -- Nothing to remove: report and return before any Undo_* call, so a no-op
    -- run leaves no undo point behind.
    if #matched == 0 then
        S.status      = 'Nothing to remove - no kick matched a 2x marker.'
        S.last_result = ('%s   %d 2x kick marker(s), pitch %d'):format(TRACK_2X, #markers, MARK_2X) ..
                        '\n\nNo matching notes found - already run, or the 2x markers do not\n' ..
                        'line up with any kick on ' .. TRACK_1X .. '.'
        return
    end

    -- Delete per take, descending by note index: MIDI_DeleteNote shifts the
    -- indices of everything after it.
    local by_take = {}
    for _, k in ipairs(matched) do
        local slot = by_take[k.take]
        if not slot then
            slot = { item = k.item, idx = {} }
            by_take[k.take] = slot
        end
        slot.idx[#slot.idx + 1] = k.idx
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for take, slot in pairs(by_take) do
        r.MarkTrackItemsDirty(tgt_tr, slot.item)   -- REQUIRED: MIDI edits do not mark the take dirty
        table.sort(slot.idx, function(a, b) return a > b end)
        for _, i in ipairs(slot.idx) do
            r.MIDI_DeleteNote(take, i)
        end
    end
    r.Undo_EndBlock2(0, ('Remove 2x-marked kicks (%d notes)'):format(#matched), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('%s   %d 2x kick marker(s), pitch %d'):format(TRACK_2X, #markers, MARK_2X),
        ('%s      %d kick(s) removed, pitch %d'):format(TRACK_1X, #matched, KICK),
    }

    -- PART DRUMS_2X normally carries the 1x kicks as 96 too, so its 96 count is
    -- what PART DRUMS should be left with. Only a cross-check - the action does
    -- not require that authoring style, so say nothing when there are no 96s.
    if #src_1x > 0 then
        local left = #kicks - #matched
        lines[#lines + 1] = ''
        if left == #src_1x then
            lines[#lines + 1] = ('%s now has %d kick(s), matching %s\'s %d - consistent.')
                :format(TRACK_1X, left, TRACK_2X, #src_1x)
        else
            lines[#lines + 1] = ('%s now has %d kick(s) but %s has %d at pitch %d.')
                :format(TRACK_1X, left, TRACK_2X, #src_1x, KICK)
            lines[#lines + 1] = 'The two charts disagree - worth a look.'
        end
    end

    if #misses > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'No kick matched at these markers:'
        for i, miss in ipairs(misses) do
            if i > UNMATCHED_LIST_MAX then
                lines[#lines + 1] = ('  ... and %d more'):format(#misses - UNMATCHED_LIST_MAX)
                break
            end
            lines[#lines + 1] = ('  %-10s %s'):format(MBTAtQN(miss.qn), miss.why)
        end
    end

    S.status = ('Removed %d kick%s from %s.'):format(
        #matched, #matched == 1 and '' or 's', TRACK_1X)
    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Double-bass detection: which kicks in a fast line are the second foot
----------------------------------------------------------------------
--
-- The rules below were derived from, and reproduce exactly (1080 of 1080 kicks),
-- the double-bass authoring in a hand-charted reference song. They are stated in
-- quarter notes for the same reason the matcher above is - see NotesAtPitch.
--
--   1. Kicks no more than a 1/8 apart form one line.
--   2. An edge kick joined to the line by a gap wider than the line's tightest,
--      whose neighbour inside the line is on a bar downbeat, is a pickup into or
--      a tail out of the line rather than part of it - drop it.
--   3. The line is double bass if its tightest gap is a 1/16 or closer (two
--      back-to-back 1/16 kicks are already two feet), or if it is a straight
--      run of more than MAX_EIGHTH_RUN 1/8s.
--   4. Every other kick becomes the second foot, phased so that no kick landing
--      on a bar downbeat is taken. Preferring the 2nd kick and falling back to
--      the 1st when that would take a downbeat is what produces the "start from
--      the first" case in an even-length line that ends on a bar line.
--
-- MAX_EIGHTH_RUN is the one value the reference chart could not settle: its
-- straight-1/8 runs are 2, 3, 13, 61 and 110 kicks long, so anything from 3 to
-- 12 scores identically on it.

local SIXTEENTH_QN   = 0.25
local EIGHTH_QN      = 0.5
local MAX_EIGHTH_RUN = 4
local QN_EPS         = 1e-6
local BEAT_EPS       = 0.001   -- beats; guards the float noise in a QN -> beat conversion

local REVIEW_LIST_MAX = 20

-- Is this quarter-note position the first beat of a measure? Asked through
-- REAPER's beat map rather than "qn % 4", so a song with time-signature changes
-- (or anything that is not 4/4) is read correctly.
local function MakeBarDownbeatTest()
    return function(qn)
        local beat_in_meas, _, per_meas = r.TimeMap2_timeToBeats(0, r.TimeMap2_QNToTime(0, qn))
        if not beat_in_meas then return false end
        if beat_in_meas < BEAT_EPS then return true end
        -- A hair under the bar line reads as the end of this measure, not the
        -- start of the next; treat it as the downbeat it is about to be.
        return per_meas ~= nil and (per_meas - beat_in_meas) < BEAT_EPS
    end
end

local function TightestGap(run, qns)
    local tight = math.huge
    for i = 2, #run do
        local g = qns[run[i]] - qns[run[i - 1]]
        if g < tight then tight = g end
    end
    return tight
end

-- Rule 2. Loops because both ends can qualify.
--
-- Two things mark an edge kick as hanging off the line rather than belonging to
-- it, and either is enough. Its neighbour inside the line is on a bar downbeat -
-- the line starts or lands there, and the edge kick is a pickup into or a tail
-- out of it. Or the line's tight section begins right at that neighbour, which
-- makes the edge kick the ONLY one at the wider spacing: a lone 1/8 leaning
-- against a burst of 1/16s is a separate hit, not the first of the burst.
--
-- The second test is what keeps a long line that merely STARTS with a stretch of
-- 1/8s intact. Trimming on the wider gap alone would strip every one of those
-- leading eighths off it, one pass at a time.
local function TrimRunEdges(run, qns, is_downbeat)
    while #run >= 3 do
        local tight = TightestGap(run, qns)
        local head  = qns[run[2]]    - qns[run[1]]
        local tail  = qns[run[#run]] - qns[run[#run - 1]]
        -- Is the tight section adjacent to the edge, i.e. is this the only kick
        -- sitting at the wider spacing?
        local head_alone = math.abs((qns[run[3]] - qns[run[2]]) - tight) < QN_EPS
        local tail_alone = math.abs((qns[run[#run - 1]] - qns[run[#run - 2]]) - tight) < QN_EPS
        if head > tight + QN_EPS and (is_downbeat(qns[run[2]]) or head_alone) then
            table.remove(run, 1)
        elseif tail > tight + QN_EPS and (is_downbeat(qns[run[#run - 1]]) or tail_alone) then
            table.remove(run)
        else
            return run
        end
    end
    return run
end

-- Rule 3.
local function IsDoubleBassLine(run, qns)
    if #run < 2 then return false end
    return TightestGap(run, qns) <= SIXTEENTH_QN + QN_EPS or #run > MAX_EIGHTH_RUN
end

-- Each kick's slot on the line's own subdivision grid, or nil when the kicks do
-- not sit on one. Rounding to a grid is meaningless for a hand-played line, so
-- every kick has to land on a multiple of the tightest gap for this to be usable.
local function GridSlots(run, qns)
    local step = TightestGap(run, qns)
    if step <= 0 then return nil end
    local slots = {}
    for i, idx in ipairs(run) do
        local exact = (qns[idx] - qns[run[1]]) / step
        local slot  = math.floor(exact + 0.5)
        if math.abs(exact - slot) * step > QN_EPS then return nil end
        slots[i] = slot
    end
    return slots
end

-- Rule 4. Returns the run positions to take, 1-based within the run.
local function PickAlternating(run, qns, is_downbeat)
    for _, phase in ipairs({ 2, 1 }) do
        local picks, clean = {}, true
        for i = phase, #run, 2 do
            picks[#picks + 1] = i
            if is_downbeat(qns[run[i]]) then clean = false end
        end
        if clean then return picks end
    end

    -- Neither phase could keep every bar downbeat on a primary kick. That happens
    -- when the line is even-length and starts AND ends on a downbeat - and a line
    -- like that is usually even-length only because it has a HOLE in it. Counting
    -- played notes then flips the feet relative to the beat for the rest of the
    -- line, stranding the primaries on offbeats and leaving the closing downbeat
    -- to the second foot.
    --
    -- So read the line as a continuous grid instead and give each kick the foot
    -- its slot calls for, ignoring that a slot is empty. The same foot then plays
    -- either side of the rest, which is what actually happens: the silent slot
    -- belonged to the other foot.
    --
    -- ONLY as a tie-break, never as the general rule. A long line that mixes 1/8s
    -- and 1/16s has a grid of 1/16s in which every eighth-spaced kick sits on an
    -- even slot, so grid parity would mark none of them - it scores 974/1080 on
    -- the first reference chart when applied to every line. As a tie-break it is
    -- inert on a line with no hole: grid slot and note index are then the same
    -- sequence, so it re-offers the two sets the loop above already rejected and
    -- falls through.
    local slots = GridSlots(run, qns)
    if slots then
        for _, parity in ipairs({ 1, 0 }) do
            local picks, clean = {}, true
            for i = 1, #run do
                if slots[i] % 2 == parity then
                    picks[#picks + 1] = i
                    if is_downbeat(qns[run[i]]) then clean = false end
                end
            end
            if clean and #picks > 0 then return picks end
        end
    end

    local picks = {}
    for i = 2, #run, 2 do picks[#picks + 1] = i end
    return picks
end

-- The whole rule set, pure: quarter-note positions in, a parallel array of
-- "this one is the second foot" booleans out. `is_downbeat(qn)` is injected so
-- tests can drive the rules against a plain grid with no project at all.
function DoubleBassPlan(qns, is_downbeat)
    local marks = {}
    for i = 1, #qns do marks[i] = false end
    if #qns < 2 then return marks end

    local runs, cur = {}, { 1 }
    for i = 2, #qns do
        if qns[i] - qns[i - 1] <= EIGHTH_QN + QN_EPS then
            cur[#cur + 1] = i
        else
            runs[#runs + 1] = cur
            cur = { i }
        end
    end
    runs[#runs + 1] = cur

    for _, run in ipairs(runs) do
        run = TrimRunEdges(run, qns, is_downbeat)
        if IsDoubleBassLine(run, qns) then
            for _, i in ipairs(PickAlternating(run, qns, is_downbeat)) do
                marks[run[i]] = true
            end
        end
    end
    return marks
end

-- Find the double-bass lines on PART DRUMS_2X and move every second foot from
-- pitch 96 to pitch 95. Whole track - a time selection does not narrow it.
function MarkDoubleBassKicks()
    local src_tr = FindTrackByName(TRACK_2X)
    if not src_tr then
        S.status      = 'Error: ' .. TRACK_2X .. ' track not found.'
        S.last_result = 'Could not find a track named "' .. TRACK_2X .. '".\n' ..
                        'This action reads and writes that track only.'
        return
    end
    if r.GetMediaTrackInfo_Value(src_tr, 'B_MUTE') == 1 then
        S.status      = 'Error: ' .. TRACK_2X .. ' is muted.'
        S.last_result = 'Unmute ' .. TRACK_2X .. ' and run this again.\n' ..
                        'A muted drum track is treated as not part of the chart.'
        return
    end
    local takes = MIDITakesOn(src_tr)
    if #takes == 0 then
        S.status      = 'Error: ' .. TRACK_2X .. ' has no MIDI item.'
        S.last_result = TRACK_2X .. ' track has no MIDI item to read kicks from.'
        return
    end

    -- Both pitches: a 95 is a kick too, so it has to be in the line for the
    -- alternation to come out right on a track that is already part-marked.
    local kicks = {}
    for _, n in ipairs(NotesAtPitch(takes, KICK)) do   kicks[#kicks + 1] = n end
    for _, n in ipairs(NotesAtPitch(takes, MARK_2X)) do kicks[#kicks + 1] = n end
    table.sort(kicks, function(a, b) return a.qn < b.qn end)
    if #kicks < 2 then
        S.status      = TRACK_2X .. ' has fewer than two kicks.'
        S.last_result = 'Nothing to analyse: a double-bass line needs at least two\n' ..
                        'kick notes (pitch ' .. KICK .. ' or ' .. MARK_2X .. ') on ' .. TRACK_2X .. '.'
        return
    end

    local qns = {}
    for i, k in ipairs(kicks) do qns[i] = k.qn end
    local marks = DoubleBassPlan(qns, MakeBarDownbeatTest())

    local to_mark, already, review = {}, 0, {}
    for i, k in ipairs(kicks) do
        if marks[i] and k.pitch == KICK then
            to_mark[#to_mark + 1] = k
        elseif marks[i] then
            already = already + 1
        elseif k.pitch == MARK_2X then
            -- Already the second foot where the rules would not put one. Left
            -- alone on purpose: reverting a deliberate hand edit is not this
            -- button's job, but it is worth showing.
            review[#review + 1] = k.qn
        end
    end

    if #to_mark == 0 then
        S.status = already > 0
            and ('Nothing to mark - %d kick(s) already marked.'):format(already)
            or  'Nothing to mark - no double-bass lines found.'
        local lines = {
            ('%s   %d kick(s) scanned'):format(TRACK_2X, #kicks),
            '',
            already > 0
                and ('All %d second-foot kick(s) the rules find are already pitch %d.')
                    :format(already, MARK_2X)
                or  ('No run of kicks on ' .. TRACK_2X .. ' is fast enough to need two feet.'),
        }
        if #review > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('%d kick(s) are already pitch %d where the rules would not')
                :format(#review, MARK_2X)
            lines[#lines + 1] = 'mark one. Left alone - worth a look:'
            for i, qn in ipairs(review) do
                if i > REVIEW_LIST_MAX then
                    lines[#lines + 1] = ('  ... and %d more'):format(#review - REVIEW_LIST_MAX)
                    break
                end
                lines[#lines + 1] = '  ' .. MBTAtQN(qn)
            end
        end
        S.last_result = table.concat(lines, '\n')
        return
    end

    local dirtied = {}
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for _, k in ipairs(to_mark) do
        if not dirtied[k.item] then
            r.MarkTrackItemsDirty(src_tr, k.item)   -- REQUIRED: MIDI edits do not mark the take dirty
            dirtied[k.item] = true
        end
        -- Pitch only; nil leaves a field untouched. noSort=true because the loop
        -- holds precomputed note indices: a sort between two writes could reorder
        -- events sharing a tick and invalidate every index still to be used. The
        -- pitch change never moves a note, so one sort per take afterwards is
        -- enough - and MarkTrackItemsDirty above, not the sort, is what keeps the
        -- undo point.
        r.MIDI_SetNote(k.take, k.idx, nil, nil, nil, nil, nil, MARK_2X, nil, true)
    end
    for _, k in ipairs(to_mark) do
        if dirtied[k.item] then
            r.MIDI_Sort(k.take)
            dirtied[k.item] = false
        end
    end
    r.Undo_EndBlock2(0, ('Mark double kicks (%d notes)'):format(#to_mark), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {
        ('%s   %d kick(s) scanned'):format(TRACK_2X, #kicks),
        ('%s   %d moved from pitch %d to %d'):format(TRACK_2X, #to_mark, KICK, MARK_2X),
    }
    if already > 0 then
        lines[#lines + 1] = ('%d more were already pitch %d.'):format(already, MARK_2X)
    end
    if #review > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('%d kick(s) are pitch %d where the rules would not mark one.')
            :format(#review, MARK_2X)
        lines[#lines + 1] = 'Left alone - worth a look:'
        for i, qn in ipairs(review) do
            if i > REVIEW_LIST_MAX then
                lines[#lines + 1] = ('  ... and %d more'):format(#review - REVIEW_LIST_MAX)
                break
            end
            lines[#lines + 1] = '  ' .. MBTAtQN(qn)
        end
    end

    S.status = ('Marked %d double kick%s on %s.'):format(
        #to_mark, #to_mark == 1 and '' or 's', TRACK_2X)
    S.last_result = table.concat(lines, '\n')
end
