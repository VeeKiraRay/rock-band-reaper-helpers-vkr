-- Midi note: bulk non-sustain note-length unification and sustain-gap normalization.
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, GetTakePPQPerQN,
-- GetPatternPitchRange, GetBPMAt, and midi_length_rules.lua's MidiLength* (globals)
--
-- All length/gap math works in raw take-relative PPQ ticks (never seconds or
-- QN floats) so results always land exactly on REAPER's own note-length grid
-- - standard note values divide evenly into GetTakePPQPerQN's tick count.
-- Rule values (quarter notes) are converted to ticks once, per note.

local SUSTAIN_MIN_DENOM = 8    -- 1/8 note: minimum length to be treated as a sustain
local FLOOR_DENOM        = 32   -- 1/32 note: minimum length any note can be shortened to
local SEARCH_WINDOW_32NDS = 16  -- how far ahead (in 32nd notes) to look for "the next note"
                                -- (16x1/32 = a half note, i.e. half a measure in 4/4)
local USUAL_GAP_TOLERANCE = 1.5 -- a sustain is lengthened only when its gap is at most this
                                -- many times the track's most common gap; a longer gap is
                                -- taken as an intentional rest (muted guitar, a break)

local TIER_LETTERS = { 'X', 'H', 'M', 'E' }   -- S.mn_diff_idx 1-4

-- The song's tempo for the Length rules: the tempo at bar 1, as Generate reads it.
function MidiLengthSongBPM()
    return GetBPMAt(r.TimeMap2_QNToTime(0, 0))
end

-- The rules' kind and tier for a track and the Difficulty selector: Pro Keys takes its tier
-- from the track name (a track per tier), the others from diff_idx. kind nil = no rules.
function MidiLengthTarget(track_name, diff_idx)
    local kind, pk_tier = MidiLengthKind(track_name)
    if not kind then return nil end
    return kind, pk_tier or TIER_LETTERS[diff_idx]
end

-- Standard note length in take-relative PPQ ticks, rounded to the nearest tick.
local function NoteLenPPQ(ppq_per_qn, denom)
    return math.floor(ppq_per_qn * 4 / denom + 0.5)
end

-- Set every non-sustain note's (length < 1/8 note) end position (in [lo,hi]
-- pitch range, inside the scope) to start + the standard length for `denom`.
-- Existing sustains (>= 1/8 note) are left completely untouched. Single pass:
-- note count and start positions are never touched, so no re-sort/index-shift
-- concerns. Every matching pitch still gets its own MIDI_SetNote call, but a
-- chord (multiple notes sharing one start tick, e.g. a Green+Red+Blue chord)
-- is only counted once, so the report reads as "N notes", not "N pitches".
local function AdjustNonSustainLengths(take, lo, hi, sel_s, sel_e, denom)
    local ppq_per_qn = GetTakePPQPerQN(take)
    local len_ppq     = NoteLenPPQ(ppq_per_qn, denom)
    local sustain_min = NoteLenPPQ(ppq_per_qn, SUSTAIN_MIN_DENOM)
    local scope_s = sel_s and r.MIDI_GetPPQPosFromProjTime(take, sel_s) or nil
    local scope_e = sel_e and r.MIDI_GetPPQPosFromProjTime(take, sel_e) or nil

    local _, n = r.MIDI_CountEvts(take)
    local count = 0
    local counted_starts = {}
    for i = 0, n - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(take, i)
        if ok and p >= lo and p <= hi
           and (not scope_s or sppq >= scope_s) and (not scope_e or sppq < scope_e)
           and (eppq - sppq) < sustain_min then
            r.MIDI_SetNote(take, i, sel, mute, sppq, sppq + len_ppq, chan, p, vel, true)
            if not counted_starts[sppq] then
                counted_starts[sppq] = true
                count = count + 1
            end
        end
    end
    return count
end

-- The note `notes[i]` is followed by: the start tick of the EARLIEST note
-- starting strictly after its own start (notes sharing the start tick are
-- chord-mates, not "next"), or nil when that note starts past the search
-- window. A note starting inside the sustain always counts, however far the
-- next clean note is: it's buried under the sustain and must be uncovered.
-- Measuring only from the sustain's tail would step over such a note and
-- stretch the sustain toward a later one, leaving the overlap in place.
-- `notes` must be start-sorted. end_ppq: measure the window from this end
-- instead of the note's own (the plain-note pass, after the gap pass moved it).
local function NextNoteStart(notes, i, search_win, end_ppq)
    local note = notes[i]
    local e = end_ppq or note.eppq
    for j = i + 1, #notes do
        if notes[j].sppq > note.sppq then
            if notes[j].sppq < e or notes[j].sppq - e <= search_win then
                return notes[j].sppq
            end
            return nil
        end
    end
    return nil
end

-- The most common gap from a sustain's end to the next note, in whole 32nd
-- notes (each gap rounded to the nearest 32nd). Buried notes and gaps past
-- the search window are not playing gaps and are not counted; a chord counts
-- once. Ties go to the smaller gap. Returns usual, its count, total counted -
-- or nil when there is no gap to count.
local function UsualSustainGap(notes, thirty2_ppq, sustain_min, search_win)
    local counts, total = {}, 0
    local counted_starts = {}
    for i, note in ipairs(notes) do
        if note.eppq - note.sppq >= sustain_min and not counted_starts[note.sppq] then
            counted_starts[note.sppq] = true
            local next_sppq = NextNoteStart(notes, i, search_win)
            if next_sppq and next_sppq >= note.eppq then
                local g = math.floor((next_sppq - note.eppq) / thirty2_ppq + 0.5)
                counts[g] = (counts[g] or 0) + 1
                total = total + 1
            end
        end
    end
    local usual, best = nil, 0
    for g, c in pairs(counts) do
        if c > best or (c == best and g < usual) then usual, best = g, c end
    end
    if not usual then return nil end
    return usual, best, total
end

-- How long a gap (in 32nds) may still be closed up when the usual gap is
-- `usual`: usual x USUAL_GAP_TOLERANCE, rounded down, but always at least one
-- 32nd more than the usual gap (3 -> 4, 2 -> 3, 1 -> 2, 0 -> 1).
local function LengthenLimit32nds(usual)
    return math.max(math.floor(usual * USUAL_GAP_TOLERANCE), usual + 1)
end

-- For every sustain (length >= 1/8 note) in [lo,hi] pitch range inside the
-- scope, set its end position so the gap to the next in-range note is the
-- target gap - widening or narrowing the sustain as needed. A sustain with no
-- next note within SEARCH_WINDOW_32NDS x 1/32 notes of its own end is left
-- unchanged (skipped). If honoring the gap would shrink the sustain below the
-- 1/32-note floor, it's clamped to that floor instead (becomes a non-sustain).
-- See NextNoteStart for "next note".
--
-- rule: { gap32 = n } - one gap for every sustain (Custom); otherwise the gap
-- is MidiLengthGapQN(kind, dl, bpm, chord, next chord) per sustain (Default).
-- kind / dl / bpm, when kind is set, also drive the plain-note pass below.
--
-- Lengthening is limited: the track's most common gap is measured over the
-- WHOLE take in the pitch range (not just the scope, so a section-by-section
-- run sees the song's value), and a sustain whose gap is longer than
-- LengthenLimit32nds of it is left alone - an author who ends a sustain much
-- earlier than usual means a rest. A gap tighter than the target is always
-- fixed, whatever its size: shortening a sustain never fills a rest.
--
-- Then the plain-note pass: every sustain in scope (adjusted, left alone or
-- skipped) that MidiLengthTooShort finds too short for the tier - or that the
-- gap cut under 1/8 - becomes a plain note MidiLengthPlainQN long, as Generate
-- makes it.
--
-- Every matching pitch still gets its own MIDI_SetNote call, but a chord
-- sustain (multiple notes sharing one start tick, e.g. a Green+Red+Blue
-- chord) is only counted once toward adjusted/skipped/clamped/left/plain, so
-- the report reads as "N sustains", not "N pitches" - the first note processed
-- at a given start tick decides which bucket the whole chord is counted in.
--
-- Returns adjusted (end moved), skipped (no next note in the window), clamped,
-- left (list of { sppq, gap_32nds }), usual ({ gap_32nds, count, total,
-- limit_32nds } or nil), plain (list of { sppq, len_32nds } - the length
-- before it became plain), already (gap already the target - not rewritten).
local function AdjustSustainGaps(take, lo, hi, sel_s, sel_e, rule)
    local ppq_per_qn  = GetTakePPQPerQN(take)
    local thirty2_ppq = NoteLenPPQ(ppq_per_qn, FLOOR_DENOM)
    local sustain_min = NoteLenPPQ(ppq_per_qn, SUSTAIN_MIN_DENOM)
    local search_win  = SEARCH_WINDOW_32NDS * thirty2_ppq
    local scope_s = sel_s and r.MIDI_GetPPQPosFromProjTime(take, sel_s) or nil
    local scope_e = sel_e and r.MIDI_GetPPQPosFromProjTime(take, sel_e) or nil
    local function Ticks(qn) return math.floor(qn * ppq_per_qn + 0.5) end

    -- Pass 1: collect every in-range note's original start/end, sorted by
    -- start - "next note" lookups must see original, unmodified positions.
    -- `all` ignores the scope (for the usual gap); `notes` is the scope.
    local all = {}
    local chord_at = {}   -- start tick -> ascending pitches (the rules' chord tests)
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, sel, mute, sppq, eppq, chan, p, vel = r.MIDI_GetNote(take, i)
        if ok and p >= lo and p <= hi then
            all[#all + 1] = {
                idx = i, sppq = sppq, eppq = eppq, chan = chan, pitch = p, vel = vel,
                sel = sel, mute = mute,
            }
            chord_at[sppq] = chord_at[sppq] or {}
            table.insert(chord_at[sppq], p)
        end
    end
    table.sort(all, function(a, b) return a.sppq < b.sppq end)
    for _, c in pairs(chord_at) do table.sort(c) end
    local notes = {}
    for _, note in ipairs(all) do
        if (not scope_s or note.sppq >= scope_s) and (not scope_e or note.sppq < scope_e) then
            notes[#notes + 1] = note
        end
    end

    local function TargetGap(note, next_sppq)
        if rule.gap32 then return rule.gap32 * thirty2_ppq end
        return Ticks(MidiLengthGapQN(rule.kind, rule.dl, rule.bpm,
            chord_at[note.sppq], chord_at[next_sppq]))
    end

    local usual_g, usual_n, usual_total = UsualSustainGap(all, thirty2_ppq, sustain_min, search_win)
    local usual, limit_32nds = nil, nil
    if usual_g then
        limit_32nds = LengthenLimit32nds(usual_g)
        usual = { gap_32nds = usual_g, count = usual_n, total = usual_total,
                  limit_32nds = limit_32nds }
    end

    -- Pass 2: adjust sustains against the (unmodified) start positions above.
    local adjusted, skipped, clamped, already = 0, 0, 0, 0
    local left = {}
    local counted_starts = {}
    for i, note in ipairs(notes) do
        local len = note.eppq - note.sppq
        note.new_e = note.eppq
        if len >= sustain_min then
            local next_sppq = NextNoteStart(notes, i, search_win)
            local first_at_start = not counted_starts[note.sppq]
            counted_starts[note.sppq] = true
            local gap_target = next_sppq and TargetGap(note, next_sppq)
            local leave_gap = nil   -- set (in 32nds) when this is a rest to leave alone
            if next_sppq and next_sppq >= note.eppq then
                local gap = next_sppq - note.eppq
                local gap_r = math.floor(gap / thirty2_ppq + 0.5)
                if gap > gap_target and limit_32nds and gap_r > limit_32nds then
                    leave_gap = gap_r
                end
            end
            if next_sppq and not leave_gap then
                local new_eppq = next_sppq - gap_target
                local floor_eppq = note.sppq + thirty2_ppq
                local was_clamped = false
                if new_eppq < floor_eppq then
                    new_eppq = floor_eppq
                    was_clamped = true
                end
                if new_eppq ~= note.eppq then
                    r.MIDI_SetNote(take, note.idx, note.sel, note.mute, note.sppq, new_eppq,
                        note.chan, note.pitch, note.vel, true)
                    note.new_e = new_eppq
                end
                if first_at_start then
                    if new_eppq == note.eppq then
                        already = already + 1   -- the gap was already the target
                    else
                        adjusted = adjusted + 1
                        if was_clamped then clamped = clamped + 1 end
                    end
                end
            elseif first_at_start then
                if leave_gap then
                    left[#left + 1] = { sppq = note.sppq, gap_32nds = leave_gap }
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    -- Pass 3: sustains too short for the tier become plain notes - including one the
    -- gap pass cut under 1/8 (a stub that is neither sustain nor plain), as Generate
    -- does. Only ever shortens: a note already at or under the plain length stays.
    local plain = {}
    if rule.kind then
        local plain_ppq = Ticks(MidiLengthPlainQN(rule.kind, rule.dl))
        local listed = {}
        for i, note in ipairs(notes) do
            local len = note.new_e - note.sppq
            if note.eppq - note.sppq >= sustain_min and len > plain_ppq then
                local next_sppq = NextNoteStart(notes, i, search_win, note.new_e)
                local room_qn = next_sppq and (next_sppq - note.new_e) / ppq_per_qn
                if len < sustain_min
                   or MidiLengthTooShort(rule.kind, rule.dl, len / ppq_per_qn, rule.bpm, room_qn) then
                    r.MIDI_SetNote(take, note.idx, note.sel, note.mute, note.sppq,
                        note.sppq + plain_ppq, note.chan, note.pitch, note.vel, true)
                    note.new_e = note.sppq + plain_ppq
                    if not listed[note.sppq] then
                        listed[note.sppq] = true
                        plain[#plain + 1] = { sppq = note.sppq,
                            len_32nds = math.floor(len / thirty2_ppq + 0.5) }
                    end
                end
            end
        end
    end
    return adjusted, skipped, clamped, left, usual, plain, already
end

local TIER_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

function AdjustMidiNoteLengths()
    if S.mn_midi_idx < 0 then
        S.status = 'Set a MIDI track first.'; return
    end
    local track = r.GetTrack(0, S.mn_midi_idx)
    if not track then
        S.status = 'Selected track no longer exists - pick the track again.'; return
    end
    local item, take = FindFirstMIDIItem(track)
    if not take then
        S.status = 'No MIDI item on selected track.'; return
    end
    if S.mn_note_type == 0 and S.mn_note_denom <= 0 then
        S.status = 'Set a Note size first.'; return
    end

    local _, track_name = r.GetTrackName(track)
    local lo, hi = GetPatternPitchRange(track_name, S.mn_diff_idx)
    local sel_s, sel_e = GetTimeSelection()

    -- Sustain rules: kind nil = a track without them (Custom only, no plain-note pass).
    local kind, dl = MidiLengthTarget(track_name, S.mn_diff_idx)
    local bpm = MidiLengthSongBPM()
    if S.mn_note_type == 1 and S.mn_gap_mode == 0 and not kind then
        S.status = ('No sustain rules for %s - pick Custom.'):format(track_name); return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)

    if S.mn_note_type == 0 then
        local count = AdjustNonSustainLengths(take, lo, hi, sel_s, sel_e, S.mn_note_denom)
        r.Undo_EndBlock2(0, ('Adjust notes: unify %d non-sustain note%s to 1/%d'):format(
            count, count ~= 1 and 's' or '', S.mn_note_denom), -1)
        S.status = ('Adjusted %d non-sustain note%s.'):format(count, count ~= 1 and 's' or '')
        S.last_result = nil
    else
        local rule = { kind = kind, dl = dl, bpm = bpm }
        if S.mn_gap_mode == 1 then rule.gap32 = S.mn_sustain_32nds end
        local adjusted, skipped, clamped, left, usual, plain, already =
            AdjustSustainGaps(take, lo, hi, sel_s, sel_e, rule)
        r.Undo_EndBlock2(0, ('Adjust notes: sustain gaps (%d adjusted)'):format(adjusted), -1)
        local lines = {}
        if rule.gap32 then
            lines[#lines + 1] = ('Custom gap: %d/32.'):format(rule.gap32)
            if kind then
                lines[#lines + 1] = 'Plain notes: ' .. MidiLengthRuleText(kind, dl, bpm)
            end
        else
            lines[#lines + 1] = MidiLengthRuleText(kind, dl, bpm)
        end
        if usual then
            lines[#lines + 1] = ('Most common gap: %d/32 (%d of %d sustains). Lengthened only where the gap was %d/32 or less.'):format(
                usual.gap_32nds, usual.count, usual.total, usual.limit_32nds)
        else
            lines[#lines + 1] = 'No gaps to measure a most common gap from.'
        end
        local function Sus(n) return ('%d sustain%s'):format(n, n ~= 1 and 's' or '') end
        lines[#lines + 1] = ''
        lines[#lines + 1] = Sus(adjusted) .. ' adjusted.'
        if already > 0 then
            lines[#lines + 1] = ('%d skipped - gap already correct.'):format(already)
        end
        if #left > 0 then
            lines[#lines + 1] = ('%d skipped - gap longer than %d/32 (listed below).'):format(
                #left, usual.limit_32nds)
        end
        if skipped > 0 then
            lines[#lines + 1] = ('%d skipped - no next note within a half note.'):format(skipped)
        end
        if clamped > 0 then
            lines[#lines + 1] = ('%d clamped to the 1/32-note floor (became non-sustain).'):format(clamped)
        end
        local function Pos(sppq)
            return r.format_timestr_pos(r.MIDI_GetProjTimeFromPPQPos(take, sppq), '', 1)
        end
        if #plain > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('%d became plain notes (too short for %s):'):format(#plain, TIER_NAMES[dl])
            for _, p in ipairs(plain) do
                lines[#lines + 1] = ('%s\twas %d/32'):format(Pos(p.sppq), p.len_32nds)
            end
        end
        if #left > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('%d left alone - gap longer than %d/32 (check by hand):'):format(
                #left, usual.limit_32nds)
            for _, l in ipairs(left) do
                lines[#lines + 1] = ('%s\tgap %d/32'):format(Pos(l.sppq), l.gap_32nds)
            end
        end
        local extra = {}
        if #plain > 0 then
            extra[#extra + 1] = ('%d became plain'):format(#plain)
        end
        if #left > 0 then
            extra[#extra + 1] = ('%d long gap%s left alone'):format(#left, #left ~= 1 and 's' or '')
        end
        S.status = 'Adjust notes done' .. (#extra > 0 and (' - ' .. table.concat(extra, ', ')) or '') .. '.'
        S.last_result = table.concat(lines, '\n')
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end
