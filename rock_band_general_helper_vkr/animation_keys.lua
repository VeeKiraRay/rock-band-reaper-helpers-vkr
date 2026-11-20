-- Animation > Keys: the keyboardist's hand animations, PART KEYS_ANIM_RH and
-- PART KEYS_ANIM_LH. The right hand copies Pro Keys Expert; the left hand comes from an
-- optional source track (a piano part holding the left hand, or both hands), placed so
-- the two hands stay apart on the in-game keyboard. Also the Validate check, which
-- runs on hand-made animations too.
-- Requires globals: r, S, FindTrackByName, TrackAtIndex, FindFirstMIDIItem,
--                   GetTimeSelection, ReplaceNotesBulk
--
-- How the game plays these tracks: only notes 48-72 are read, and the left-hand track
-- sits an octave below the right-hand one on the in-game keyboard (the RH track's 48 is
-- the keyboard's second C, the LH track's 48 its first). So in one keyboard coordinate
-- an RH note p is at p + 12, an LH note p at p. Each hand is placed at the middle of its
-- held notes and rests after more than 2 beats without notes.
--
-- What the official RB3 DLC charts do (352 songs with Pro Keys, measured offline):
-- - RH: a copy of Expert (85% of its notes exact, 95% of those the same length).
--   Expert is the right hand's part: 69% of Expert notes are on the RH only, 6% on the
--   LH only.
-- - LH: 290 of the 352 songs have one. Mostly the authors' own part, not in Expert
--   (44% of its notes are Expert notes), mostly single notes (85% of its onsets), and
--   playing in a median 77% of the bars with Expert notes.
-- - Both hands together, never the same key: while both sound, the RH's lowest key is a
--   median 16 semitones above the LH's highest (10th percentile 8); within 2 semitones
--   or crossed is under 0.1% of those moments.
-- - One hand's notes span more than an octave in 14 songs (RH) and 1 (LH).

local EPS = 1e-6   -- QN

KEYS_ANIM_LO, KEYS_ANIM_HI = 48, 72
KEYS_ANIM_TRACKS = { rh = 'PART KEYS_ANIM_RH', lh = 'PART KEYS_ANIM_LH' }
KEYS_ANIM_EXPERT = 'PART REAL_KEYS_X'

KEYS_ANIM_PARAMS = {
    onset_qn   = 0.02,   -- "same onset" (10 ticks at 480 PPQ)
    phrase_qn  = 2,      -- an LH phrase ends after 2 beats without notes (the game's rest)
    lh_target  = 55,     -- LH placement: the official LH median (written pitch)
    comfy_gap  = 8,      -- LH placement: in-game semitones under the RH (official 10th pct)
    close_gap  = 2,      -- Validate + LH drop: the hands this close or crossed
    span_max   = 12,     -- Validate: one hand's held notes wider than an octave
    lh_chord_max = 3,    -- Validate: LH chords of more notes (official 0.1% of LH onsets)
}

-- Left-hand source modes (S.keys_anim_lh_mode)
KEYS_ANIM_LH_MODES = {
    { key = 'track',    label = 'Whole track' },
    { key = 'channel',  label = 'Channel 2' },
    { key = 'subtract', label = 'Not on Expert' },
}

----------------------------------------------------------------------
-- Pure planning. Notes: { qn_s, qn_e, pitch, chan } in QN, sorted by qn_s.
----------------------------------------------------------------------

local function SortNotes(list)
    table.sort(list, function(a, b)
        if math.abs(a.qn_s - b.qn_s) > EPS then return a.qn_s < b.qn_s end
        return a.pitch < b.pitch
    end)
    return list
end

-- The right hand: Expert's notes in 48-72, lengths kept.
function KeysAnimRightHand(expert)
    local out = {}
    for _, n in ipairs(expert) do
        if n.pitch >= KEYS_ANIM_LO and n.pitch <= KEYS_ANIM_HI then
            out[#out + 1] = { qn_s = n.qn_s, qn_e = n.qn_e, pitch = n.pitch }
        end
    end
    return SortNotes(out)
end

-- 'subtract': the right hand's part removed from a track holding both hands. Each
-- Expert note claims one source note on the same onset: the same pitch, else the same
-- note in the nearest other octave (Expert is folded into the Pro Keys range), the
-- higher one on a tie (the right hand is the upper part). One claim per note, so a
-- left-hand root doubling a right-hand note an octave or two down stays.
-- Returns a set: claimed[source note] = true.
local function ClaimedByExpert(notes, expert, tol)
    local claimed, si = {}, 1
    for _, x in ipairs(expert) do
        while notes[si] and notes[si].qn_s < x.qn_s - tol - EPS do si = si + 1 end
        local best, best_d
        local j = si
        while notes[j] and notes[j].qn_s <= x.qn_s + tol + EPS do
            local n = notes[j]
            if not claimed[n] and (n.pitch - x.pitch) % 12 == 0 then
                local d = math.abs(n.pitch - x.pitch)
                if not best or d < best_d or (d == best_d and n.pitch > best.pitch) then
                    best, best_d = n, d
                end
            end
            j = j + 1
        end
        if best then claimed[best] = true end
    end
    return claimed
end

-- The left-hand notes of a source track. mode: 'track' (every note), 'channel' (MIDI
-- channel 2, chan == 1), 'subtract' (what Expert does not claim, ClaimedByExpert).
function KeysAnimLeftSource(notes, expert, mode, params)
    local P = params or KEYS_ANIM_PARAMS
    local claimed = mode == 'subtract' and ClaimedByExpert(notes, expert, P.onset_qn) or {}
    local out = {}
    for _, n in ipairs(notes) do
        local keep = not claimed[n]
        if mode == 'channel' then keep = n.chan == 1 end
        if keep then out[#out + 1] = { qn_s = n.qn_s, qn_e = n.qn_e, pitch = n.pitch } end
    end
    return SortNotes(out)
end

-- The lowest RH pitch sounding at any time during [s, e), or nil.
local function RightLowestDuring(rh, s, e)
    local low
    for _, n in ipairs(rh) do
        if n.qn_s >= e - EPS then break end
        if n.qn_e > s + EPS and (not low or n.pitch < low) then low = n.pitch end
    end
    return low
end

-- Phrases: notes whose gap to everything before is under phrase_qn.
local function Phrases(notes, gap_qn)
    local out, cur, cur_end = {}, nil, -math.huge
    for _, n in ipairs(notes) do
        if not cur or n.qn_s - cur_end > gap_qn + EPS then
            cur = {}
            out[#out + 1] = cur
        end
        cur[#cur + 1] = n
        if n.qn_e > cur_end then cur_end = n.qn_e end
    end
    return out
end

local function FoldInto(p)
    while p < KEYS_ANIM_LO do p = p + 12 end
    while p > KEYS_ANIM_HI do p = p - 12 end
    return p
end

-- Places the left hand on the LH track: each phrase moves by whole octaves into 48-72,
-- picking the octave where the fewest notes come closer than comfy_gap (in game) to the
-- right hand, then the one nearest the official LH register. A phrase too wide for any
-- one octave folds note by note. Notes that still end up close_gap or less from the RH,
-- or crossed, are dropped. Same onset + pitch after folding: one note, the longer.
-- Returns placed, dropped (the source notes left out), shifts (phrase count per octave
-- shift in semitones).
function KeysAnimPlaceLeft(lh, rh, params)
    local P = params or KEYS_ANIM_PARAMS
    local placed, dropped, shifts = {}, {}, {}
    for _, ph in ipairs(Phrases(lh, P.phrase_qn)) do
        local lo, hi, sum = math.huge, -math.huge, 0
        local rlow = {}
        for i, n in ipairs(ph) do
            if n.pitch < lo then lo = n.pitch end
            if n.pitch > hi then hi = n.pitch end
            sum = sum + n.pitch
            rlow[i] = RightLowestDuring(rh, n.qn_s, n.qn_e)
        end
        local mean = sum / #ph
        local best, best_close, best_dist
        for k = -6, 6 do
            local sh = 12 * k
            if lo + sh >= KEYS_ANIM_LO and hi + sh <= KEYS_ANIM_HI then
                local close = 0
                for i, n in ipairs(ph) do
                    if rlow[i] and (rlow[i] + 12) - (n.pitch + sh) < P.comfy_gap then close = close + 1 end
                end
                local dist = math.abs(mean + sh - P.lh_target)
                if not best or close < best_close or (close == best_close and dist < best_dist - EPS) then
                    best, best_close, best_dist = sh, close, dist
                end
            end
        end
        local function Pitch(n)
            if best then return n.pitch + best end
            -- too wide for one octave: centre the phrase on the target, fold the rest
            local sh = 12 * math.floor((P.lh_target - mean) / 12 + 0.5)
            return FoldInto(n.pitch + sh)
        end
        shifts[best or 'fold'] = (shifts[best or 'fold'] or 0) + 1
        for i, n in ipairs(ph) do
            local p = Pitch(n)
            if rlow[i] and (rlow[i] + 12) - p <= P.close_gap then
                dropped[#dropped + 1] = n
            else
                placed[#placed + 1] = { qn_s = n.qn_s, qn_e = n.qn_e, pitch = p }
            end
        end
    end
    -- octave folds can stack two notes on one key: keep the longer
    SortNotes(placed)
    local out = {}
    for _, n in ipairs(placed) do
        local prev = out[#out]
        if prev and prev.pitch == n.pitch and math.abs(prev.qn_s - n.qn_s) <= P.onset_qn + EPS then
            if n.qn_e > prev.qn_e then prev.qn_e = n.qn_e end
        else
            out[#out + 1] = n
        end
    end
    return out, dropped, shifts
end

----------------------------------------------------------------------
-- Pure Validate. bar_of(qn) -> measure number. Returns a list of
-- { level = 'error' | 'warn' | 'advisory' | 'info', text, bars = { n, ... } }.
----------------------------------------------------------------------

local function Onsets(notes, tol)
    local out = {}
    for _, n in ipairs(notes) do
        local g = out[#out]
        if g and n.qn_s - g.qn <= tol + EPS then g.n = g.n + 1
        else out[#out + 1] = { qn = n.qn_s, n = 1 } end
    end
    return out
end

-- Notes sounding at qn (started by qn + tol, not yet ended).
local function SoundingAt(notes, qn, tol)
    local out = {}
    for _, n in ipairs(notes) do
        if n.qn_s > qn + tol + EPS then break end
        if n.qn_e > qn + EPS or math.abs(n.qn_s - qn) <= tol + EPS then out[#out + 1] = n end
    end
    return out
end

local function AddBar(set, list, b) if not set[b] then set[b] = true list[#list + 1] = b end end

function KeysAnimValidate(rh, lh, expert, bar_of, params)
    local P = params or KEYS_ANIM_PARAMS
    local out = {}
    local function Finding(level, text, bars)
        table.sort(bars or {})
        out[#out + 1] = { level = level, text = text, bars = bars or {} }
    end

    -- 1. range
    for _, h in ipairs({ { 'right', rh }, { 'left', lh } }) do
        local set, bars, n = {}, {}, 0
        for _, x in ipairs(h[2]) do
            if x.pitch < KEYS_ANIM_LO or x.pitch > KEYS_ANIM_HI then
                n = n + 1
                AddBar(set, bars, bar_of(x.qn_s))
            end
        end
        if n > 0 then
            Finding('error', string.format('%d %s-hand note%s outside 48-72 (C2-C4) - the game ignores them',
                                           n, h[1], n == 1 and '' or 's'), bars)
        end
    end

    -- 2. hands meeting on the in-game keyboard
    if #rh > 0 and #lh > 0 then
        local times = {}
        for _, g in ipairs(Onsets(rh, P.onset_qn)) do times[#times + 1] = g.qn end
        for _, g in ipairs(Onsets(lh, P.onset_qn)) do times[#times + 1] = g.qn end
        table.sort(times)
        local set, bars = {}, {}
        for _, t in ipairs(times) do
            local ar, al = SoundingAt(rh, t, P.onset_qn), SoundingAt(lh, t, P.onset_qn)
            if #ar > 0 and #al > 0 then
                local rmin, lmax = math.huge, -math.huge
                for _, n in ipairs(ar) do if n.pitch < rmin then rmin = n.pitch end end
                for _, n in ipairs(al) do if n.pitch > lmax then lmax = n.pitch end end
                if (rmin + 12) - lmax <= P.close_gap then AddBar(set, bars, bar_of(t)) end
            end
        end
        if #bars > 0 then
            Finding('warn', 'The hands meet on the in-game keyboard (2 semitones or less apart, ' ..
                            'or crossed; the LH track plays an octave lower)', bars)
        end
    end

    -- 3. one hand wider than an octave; 4. big LH chords
    for _, h in ipairs({ { 'Right', rh }, { 'Left', lh } }) do
        local set, bars = {}, {}
        for _, g in ipairs(Onsets(h[2], P.onset_qn)) do
            local act = SoundingAt(h[2], g.qn, P.onset_qn)
            local a, b = math.huge, -math.huge
            for _, n in ipairs(act) do
                if n.pitch < a then a = n.pitch end
                if n.pitch > b then b = n.pitch end
            end
            if b - a > P.span_max then AddBar(set, bars, bar_of(g.qn)) end
        end
        if #bars > 0 then
            Finding('advisory', h[1] .. ' hand holds notes more than an octave apart', bars)
        end
    end
    do
        local set, bars = {}, {}
        for _, g in ipairs(Onsets(lh, P.onset_qn)) do
            if g.n > P.lh_chord_max then AddBar(set, bars, bar_of(g.qn)) end
        end
        if #bars > 0 then
            Finding('advisory', string.format('Left-hand chords of more than %d notes', P.lh_chord_max), bars)
        end
    end

    -- 5. Expert bars no hand animates
    if #expert > 0 then
        local played = {}
        for _, n in ipairs(rh) do played[bar_of(n.qn_s)] = true end
        for _, n in ipairs(lh) do played[bar_of(n.qn_s)] = true end
        local set, bars = {}, {}
        for _, n in ipairs(expert) do
            local b = bar_of(n.qn_s)
            if not played[b] then AddBar(set, bars, b) end
        end
        if #bars > 0 then
            Finding('info', 'Bars with Pro Keys Expert notes but no hand animation', bars)
        end
    end
    return out
end

-- "3, 5-8, 12" from a sorted list of bar numbers.
function KeysAnimBarList(bars)
    local parts, i = {}, 1
    while bars[i] do
        local j = i
        while bars[j + 1] and bars[j + 1] == bars[j] + 1 do j = j + 1 end
        parts[#parts + 1] = (j > i) and (bars[i] .. '-' .. bars[j]) or tostring(bars[i])
        i = j + 1
    end
    return table.concat(parts, ', ')
end

-- Result lines for a finding list (tags for DrawResultPanel).
function KeysAnimFindingLines(findings)
    local lines = {}
    local TAG = { error = '{error}', warn = '{warn}', advisory = '{warn}', info = '{dim}' }
    local WORD = { error = 'Error', warn = 'Warning', advisory = 'Check', info = 'Note' }
    if #findings == 0 then
        lines[#lines + 1] = '{ok}No problems found.'
        return lines
    end
    for _, f in ipairs(findings) do
        lines[#lines + 1] = TAG[f.level] .. WORD[f.level] .. ': ' .. f.text
        if #f.bars > 0 then
            lines[#lines + 1] = '  bars ' .. KeysAnimBarList(f.bars)
        end
    end
    return lines
end

----------------------------------------------------------------------
-- REAPER side
----------------------------------------------------------------------

-- Every unmuted note on a track's MIDI items, in QN, sorted. lo / hi: pitch window.
local function ReadTrackNotes(track, lo, hi)
    local out = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local take = r.GetActiveTake(r.GetTrackMediaItem(track, i))
        if take and r.TakeIsMIDI(take) then
            local _, n_notes = r.MIDI_CountEvts(take)
            for j = 0, n_notes - 1 do
                local ok, _, muted, sppq, eppq, chan, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= (lo or 0) and pitch <= (hi or 127) then
                    out[#out + 1] = { qn_s = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                                      qn_e = r.MIDI_GetProjQNFromPPQPos(take, eppq),
                                      pitch = pitch, chan = chan }
                end
            end
        end
    end
    return SortNotes(out)
end

local function BarOf(qn)
    local t = r.TimeMap2_QNToTime(0, qn + EPS)
    return tonumber(r.format_timestr_pos(t, '', 1):match('^(%-?%d+)')) or 0
end

local function Muted(track) return r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 end

local function Notes(n) return n == 1 and '1 note' or (n .. ' notes') end

-- Writes notes (QN) to a track's first MIDI item, replacing every note that starts in
-- range (the whole item without a time selection). Returns written, replaced, outside.
local function WriteHand(track, notes, sel_s, sel_e)
    local item, take = FindFirstMIDIItem(track)
    local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local i_s = r.TimeMap2_timeToQN(0, pos)
    local i_e = r.TimeMap2_timeToQN(0, pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH'))
    local s_qn = sel_s and r.TimeMap2_timeToQN(0, sel_s)
    local e_qn = sel_e and r.TimeMap2_timeToQN(0, sel_e)
    local function InRange(qn) return not sel_s or (qn >= s_qn - EPS and qn < e_qn - EPS) end
    local _, n_notes = r.MIDI_CountEvts(take)
    local replaced = 0
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq = r.MIDI_GetNote(take, i)
        if ok and InRange(r.MIDI_GetProjQNFromPPQPos(take, sppq)) then replaced = replaced + 1 end
    end
    local new, outside = {}, 0
    for _, n in ipairs(notes) do
        if InRange(n.qn_s) then
            if n.qn_s >= i_s - EPS and n.qn_e <= i_e + EPS then
                new[#new + 1] = { s = r.TimeMap2_QNToTime(0, n.qn_s), e = r.TimeMap2_QNToTime(0, n.qn_e),
                                  pitch = n.pitch }
            else
                outside = outside + 1
            end
        end
    end
    r.MarkTrackItemsDirty(track, item)
    if not ReplaceNotesBulk(take, sel_s, sel_e, { { 0, 127 } }, new, 100) then
        for i = n_notes - 1, 0, -1 do
            local ok, _, _, sppq = r.MIDI_GetNote(take, i)
            if ok and InRange(r.MIDI_GetProjQNFromPPQPos(take, sppq)) then r.MIDI_DeleteNote(take, i) end
        end
        for _, n in ipairs(new) do
            r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, n.s),
                              r.MIDI_GetPPQPosFromProjTime(take, n.e), 0, n.pitch, 100, false)
        end
    end
    r.MIDI_Sort(take)
    return #new, replaced, outside
end

-- The Expert source, or nil + a reason.
local function ReadExpert()
    local track = FindTrackByName(KEYS_ANIM_EXPERT)
    if not track then return nil, 'No ' .. KEYS_ANIM_EXPERT .. ' track.' end
    if Muted(track) then return nil, KEYS_ANIM_EXPERT .. ' is muted.' end
    return ReadTrackNotes(track, KEYS_ANIM_LO, KEYS_ANIM_HI)
end

-- A hand's animation track ready to write, or nil + a reason.
local function TargetTrack(name)
    local track = FindTrackByName(name)
    if not track then return nil, 'no track (add it from the RBN template)' end
    if Muted(track) then return nil, 'muted' end
    if not FindFirstMIDIItem(track) then return nil, 'no MIDI item' end
    return track
end

function KeysAnimLeftModeKey()
    local m = KEYS_ANIM_LH_MODES[(S.keys_anim_lh_mode or 0) + 1] or KEYS_ANIM_LH_MODES[1]
    return m.key, m.label
end

-- The Generate button: RH from Expert, LH from the picked source (or left alone),
-- whole song or the notes that start in the time selection; then Validate's findings
-- for what was written.
function GenerateKeysAnimations()
    local expert, why = ReadExpert()
    if not expert then
        S.status = 'Keys animations: nothing written.'
        S.last_result = why
        return
    end
    if #expert == 0 then
        S.status = 'Keys animations: nothing written.'
        S.last_result = KEYS_ANIM_EXPERT .. ' has no notes in 48-72.'
        return
    end
    local rh_track, rh_why = TargetTrack(KEYS_ANIM_TRACKS.rh)
    if not rh_track then
        S.status = 'Keys animations: nothing written.'
        S.last_result = KEYS_ANIM_TRACKS.rh .. ': ' .. rh_why
        return
    end

    local rh = KeysAnimRightHand(expert)
    local lh_src = TrackAtIndex(S.keys_anim_lh_idx)
    local lh, dropped, shifts, lh_track, lh_note
    local mode_key, mode_label = KeysAnimLeftModeKey()
    if lh_src then
        local _, src_name = r.GetTrackName(lh_src)
        if src_name == KEYS_ANIM_TRACKS.lh or src_name == KEYS_ANIM_TRACKS.rh then
            S.status = 'Keys animations: nothing written.'
            S.last_result = 'The left-hand source is an animation track itself - pick the ' ..
                            'piano part instead.'
            return
        end
        local lh_why
        lh_track, lh_why = TargetTrack(KEYS_ANIM_TRACKS.lh)
        if not lh_track then
            S.status = 'Keys animations: nothing written.'
            S.last_result = KEYS_ANIM_TRACKS.lh .. ': ' .. lh_why
            return
        end
        local src = KeysAnimLeftSource(ReadTrackNotes(lh_src), expert, mode_key)
        lh, dropped, shifts = KeysAnimPlaceLeft(src, rh)
        lh_note = string.format('from %s (%s)', src_name, mode_label)
        if #src == 0 then
            S.status = 'Keys animations: nothing written.'
            S.last_result = string.format('The left-hand source %s has no notes for "%s".',
                                          src_name, mode_label)
            return
        end
    end

    local sel_s, sel_e = GetTimeSelection()
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local rw, rr, ro = WriteHand(rh_track, rh, sel_s, sel_e)
    local lw, lr, lo
    if lh_track then lw, lr, lo = WriteHand(lh_track, lh, sel_s, sel_e) end
    r.Undo_EndBlock2(0, string.format('Generate keys animations (%d notes)', rw + (lw or 0)), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    local lines = {}
    if sel_s then lines[#lines + 1] = 'Range: the time selection (planned from the whole song).' end
    lines[#lines + 1] = KEYS_ANIM_TRACKS.rh
    lines[#lines + 1] = string.format('- %s copied from %s%s', Notes(rw), KEYS_ANIM_EXPERT,
                                      rr > 0 and string.format(' (replaced %s)', Notes(rr)) or '')
    if ro > 0 then
        lines[#lines + 1] = string.format('- %s outside the MIDI item - extend the item and run again', Notes(ro))
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = KEYS_ANIM_TRACKS.lh
    if not lh_track then
        lines[#lines + 1] = '{dim}- Not written: no left-hand source picked (right hand only is fine in game).'
    else
        lines[#lines + 1] = string.format('- %s %s%s', Notes(lw), lh_note,
                                          lr > 0 and string.format(' (replaced %s)', Notes(lr)) or '')
        local sh = {}
        for k, c in pairs(shifts) do
            if k == 'fold' then
                sh[#sh + 1] = string.format('%d folded note by note (wider than two octaves)', c)
            elseif k ~= 0 then
                sh[#sh + 1] = string.format('%d moved %s %d octave%s', c, k > 0 and 'up' or 'down',
                                            math.abs(k) // 12, math.abs(k) == 12 and '' or 's')
            end
        end
        table.sort(sh)
        if #sh > 0 then lines[#lines + 1] = '- Phrases: ' .. table.concat(sh, ', ') end
        if #dropped > 0 then
            local set, bars = {}, {}
            for _, n in ipairs(dropped) do AddBar(set, bars, BarOf(n.qn_s)) end
            table.sort(bars)
            lines[#lines + 1] = string.format('{warn}- %s left out: too close to the right hand ' ..
                                              'in game (bars %s)', Notes(#dropped), KeysAnimBarList(bars))
        end
        if lo > 0 then
            lines[#lines + 1] = string.format('- %s outside the MIDI item - extend the item and run again', Notes(lo))
        end
    end

    -- Validate what the tracks hold now
    local lh_now = lh_track and ReadTrackNotes(lh_track)
                   or (FindTrackByName(KEYS_ANIM_TRACKS.lh) and ReadTrackNotes(FindTrackByName(KEYS_ANIM_TRACKS.lh)))
                   or {}
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Validate'
    for _, l in ipairs(KeysAnimFindingLines(KeysAnimValidate(ReadTrackNotes(rh_track), lh_now, expert, BarOf))) do
        lines[#lines + 1] = l
    end
    S.status = string.format('Keys animations: %d right-hand%s notes written.', rw,
                             lh_track and string.format(' and %d left-hand', lw) or '')
    S.last_result = table.concat(lines, '\n')
end

-- The Validate button: the animation tracks as they are, hand-made or generated.
function ValidateKeysAnimations()
    local rh_tr = FindTrackByName(KEYS_ANIM_TRACKS.rh)
    local lh_tr = FindTrackByName(KEYS_ANIM_TRACKS.lh)
    if not rh_tr and not lh_tr then
        S.status = 'Keys animations: no animation tracks.'
        S.last_result = 'No ' .. KEYS_ANIM_TRACKS.rh .. ' or ' .. KEYS_ANIM_TRACKS.lh .. ' track.'
        return
    end
    local rh = rh_tr and ReadTrackNotes(rh_tr) or {}
    local lh = lh_tr and ReadTrackNotes(lh_tr) or {}
    local expert = ReadExpert() or {}
    local lines = {}
    lines[#lines + 1] = string.format('%s: %s', KEYS_ANIM_TRACKS.rh,
        not rh_tr and 'no track' or (#rh == 0 and 'no notes' or Notes(#rh)))
    lines[#lines + 1] = string.format('%s: %s', KEYS_ANIM_TRACKS.lh,
        not lh_tr and 'no track' or (#lh == 0 and 'no notes (right hand only is fine in game)' or Notes(#lh)))
    if #expert == 0 then
        lines[#lines + 1] = '{dim}No unmuted ' .. KEYS_ANIM_EXPERT .. ' notes: the bars check is skipped.'
    end
    lines[#lines + 1] = ''
    local findings = KeysAnimValidate(rh, lh, expert, BarOf)
    for _, l in ipairs(KeysAnimFindingLines(findings)) do lines[#lines + 1] = l end
    local n_err, n_warn = 0, 0
    for _, f in ipairs(findings) do
        if f.level == 'error' then n_err = n_err + 1
        elseif f.level == 'warn' or f.level == 'advisory' then n_warn = n_warn + 1 end
    end
    S.status = string.format('Keys animations validated: %d error%s, %d warning%s.',
                             n_err, n_err == 1 and '' or 's', n_warn, n_warn == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end
