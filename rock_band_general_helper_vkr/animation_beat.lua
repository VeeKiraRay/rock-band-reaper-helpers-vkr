-- Animation > Beat: writes the BEAT track.
--
-- Note 12 = downbeat (a bar's first beat), note 13 = upbeat (the bar's other beats;
-- the RBN docs, CAT and the community template call it that). Rules, measured over the
-- official RB3 DLC BEAT tracks (591 songs) and matched against CAT's
-- "Create BEAT track notes" / "Halve BEAT track notes":
--   - One note per quarter note, counted from each bar line, in every meter -
--     6/8 too (three quarters, not two dotted quarters). A quarter that starts
--     inside the bar gets a note even when the bar ends half a beat later
--     (7/8 = D u u u), as the official charts do.
--   - From measure 1 up to [end], never on or after [end].
--   - Half time: notes two quarters apart, each bar restarting at its bar line,
--     so odd bars (3/4, 5/4, 6/8) leave the shorter gap before the next bar.
--     'pair' puts the downbeat only on every other bar (CAT and most halved
--     official songs); 'bar' keeps it on every bar.
--   - The beat just before [end] always gets a note, half time included:
--     Magma refuses a song without one (4/4 with [end] on beat 3 needs beat 2).
--
-- BeatPlan is pure (no r); ReadProjectBars and GenerateBeatTrack touch REAPER.
-- Requires globals: r, S, FindTrackByName, FindNamedTrackMIDI, FindEventTime,
--                   FindFirstMIDIItem, GetTimeSelection, FormatTime

BEAT_PITCH_DOWN = 12
BEAT_PITCH_UP   = 13

local BEAT_VEL    = 100    -- what the official charts use
local BEAT_LEN_QN = 0.25   -- a 16th, as CAT writes; length has no effect in game
local EPS         = 1e-6   -- QN; float noise from the tempo map conversions

-- Plans the BEAT notes.
--   bars: { { qn_s, qn_e }, ... } in order, bars[1] = measure 1
--   opts: end_qn      [end] in QN (required); no note at or after it
--         range_s_qn  first allowed note start (default: measure 1)
--         range_e_qn  notes start before this (default: end_qn)
--         half        true = a note every two quarters
--         half_style  'pair' (default) or 'bar' - see the file header
-- Returns notes { { qn, pitch, bar }, ... } sorted by qn, where bar is the
-- 1-based measure number.
function BeatPlan(bars, opts)
    local notes = {}
    if #bars == 0 then return notes end
    local end_qn  = opts.end_qn
    local range_s = opts.range_s_qn or bars[1].qn_s
    local range_e = math.min(opts.range_e_qn or end_qn, end_qn)
    local step    = opts.half and 2 or 1
    local style   = opts.half_style or 'pair'

    -- Half-time parity counts from the bar holding the range start, so a
    -- selected section starts on a downbeat (as CAT's "Halve selected" does).
    local anchor = 1
    for i, b in ipairs(bars) do
        if b.qn_s <= range_s + EPS and range_s < b.qn_e - EPS then anchor = i break end
    end

    for i, b in ipairs(bars) do
        if b.qn_s >= range_e - EPS then break end
        local down
        if opts.half and style == 'pair' then
            down = (i - anchor) % 2 == 0
        else
            down = true
        end
        local qn = b.qn_s
        while qn < b.qn_e - EPS and qn < range_e - EPS do
            if qn >= range_s - EPS then
                local first = qn <= b.qn_s + EPS
                local pitch = (first and down) and BEAT_PITCH_DOWN or BEAT_PITCH_UP
                notes[#notes + 1] = { qn = qn, pitch = pitch, bar = i }
            end
            -- Magma needs a note on the beat just before [end]: in half time,
            -- when the next step would reach [end], step one beat instead (as CAT does).
            if step == 2 and qn + 2 >= end_qn - EPS then
                qn = qn + 1
            else
                qn = qn + step
            end
        end
    end
    return notes
end

-- Every measure from measure 1 that starts before end_qn, as BeatPlan's bars
-- (plus num / den for the result text).
function ReadProjectBars(end_qn)
    local bars = {}
    for m = 0, 99999 do
        local _, qn_s, qn_e, num, den = r.TimeMap_GetMeasureInfo(0, m)
        if qn_s >= end_qn - EPS then break end
        bars[#bars + 1] = { qn_s = qn_s, qn_e = qn_e, num = num, den = den }
    end
    return bars
end

local function Fail(status, detail)
    S.status = status
    S.last_result = detail
end

-- The action behind both Beat buttons. half = true writes half-time beats in
-- the style picked in S.beat_half_style (0 = every other bar, 1 = every bar).
function GenerateBeatTrack(half)
    local what = half and 'Half-time beats' or 'Beats'

    local track = FindTrackByName('BEAT')
    if not track then
        return Fail(what .. ': no BEAT track.',
                    'Add a track named BEAT (the RBN template has one), then try again.')
    end
    local end_t = FindEventTime('[end]')
    if not end_t then
        local ev_track = FindNamedTrackMIDI('EVENTS')
        return Fail(what .. ': no [end] event.',
                    ev_track and 'The EVENTS track has no [end] text event. Add it first ' ..
                                 '(Events > Manual gen > Insert bookends, or by hand): ' ..
                                 'the BEAT track runs from measure 1 up to [end].'
                             or 'No EVENTS track. Add one with an [end] text event first: ' ..
                                'the BEAT track runs from measure 1 up to [end].')
    end

    local song_s_t = r.TimeMap_GetMeasureInfo(0, 0)
    local end_qn   = r.TimeMap2_timeToQN(0, end_t)
    if end_t <= song_s_t then
        return Fail(what .. ': [end] is at or before measure 1.', nil)
    end

    local sel_s, sel_e = GetTimeSelection()
    local range_s_t, range_e_t = song_s_t, end_t
    if sel_s then
        range_s_t = math.max(sel_s, song_s_t)
        range_e_t = math.min(sel_e, end_t)
        if range_s_t >= range_e_t then
            return Fail(what .. ': nothing to do.',
                        'The time selection lies outside measure 1 to [end].')
        end
    end
    local range_s_qn = r.TimeMap2_timeToQN(0, range_s_t)
    local range_e_qn = r.TimeMap2_timeToQN(0, range_e_t)

    local bars  = ReadProjectBars(end_qn)
    local style = (S.beat_half_style == 1) and 'bar' or 'pair'
    local notes = BeatPlan(bars, {
        end_qn = end_qn, range_s_qn = range_s_qn, range_e_qn = range_e_qn,
        half = half, half_style = style,
    })
    if #notes == 0 then
        return Fail(what .. ': nothing to do.', 'No beat falls inside the time selection.')
    end

    -- The item must hold every note (the last one may run a 16th past the range).
    local last_end_qn = math.min(notes[#notes].qn + BEAT_LEN_QN, end_qn)
    local item, take = FindFirstMIDIItem(track)
    if item then
        local pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local i_end = pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local need_s = r.TimeMap2_QNToTime(0, notes[1].qn)
        local need_e = r.TimeMap2_QNToTime(0, last_end_qn)
        if pos > need_s + 0.001 or i_end < need_e - 0.001 then
            return Fail(what .. ': the BEAT item is too short.',
                        string.format('The BEAT MIDI item covers %s - %s but the beats ' ..
                                      'run %s - %s. Extend the item to [end] and try again.',
                                      FormatTime(pos), FormatTime(i_end),
                                      FormatTime(need_s), FormatTime(need_e)))
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local created = false
    if not item then
        item = r.CreateNewMIDIItemInProj(track, song_s_t, end_t, false)
        take = item and r.GetActiveTake(item)
        created = true
    end
    if not take then
        r.Undo_EndBlock2(0, 'Generate BEAT track', -1)
        r.PreventUIRefresh(-1)
        return Fail(what .. ': could not create a MIDI item on BEAT.', nil)
    end
    r.MarkTrackItemsDirty(track, item)

    -- Replace: every note in the take on a whole-song run (stray notes past
    -- [end] go too), else the notes that start inside the time selection.
    local removed = 0
    local lo_ppq = r.MIDI_GetPPQPosFromProjQN(take, range_s_qn)
    local hi_ppq = r.MIDI_GetPPQPosFromProjQN(take, range_e_qn)
    local _, n_notes = r.MIDI_CountEvts(take)
    for i = n_notes - 1, 0, -1 do
        local ok, _, _, sppq = r.MIDI_GetNote(take, i)
        if ok and (not sel_s or (sppq >= lo_ppq - 0.5 and sppq < hi_ppq - 0.5)) then
            r.MIDI_DeleteNote(take, i)
            removed = removed + 1
        end
    end

    for _, n in ipairs(notes) do
        local sp = r.MIDI_GetPPQPosFromProjQN(take, n.qn)
        local ep = r.MIDI_GetPPQPosFromProjQN(take, math.min(n.qn + BEAT_LEN_QN, end_qn))
        r.MIDI_InsertNote(take, false, false, sp, ep, 0, n.pitch, BEAT_VEL, false)
    end

    r.Undo_EndBlock2(0, string.format('Generate BEAT track (%d notes)', #notes), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    -- Result text
    local first_bar, last_bar = notes[1].bar, notes[#notes].bar
    local meters, seen = {}, {}
    for i = first_bar, last_bar do
        local b = bars[i]
        local sig = string.format('%d/%d', b.num, b.den)
        if not seen[sig] then seen[sig] = true meters[#meters + 1] = sig end
    end
    local downs = 0
    for _, n in ipairs(notes) do if n.pitch == BEAT_PITCH_DOWN then downs = downs + 1 end end

    S.status = string.format('%s: %d notes written, measures %d-%d.', what, #notes,
                             first_bar, last_bar)
    local lines = {
        string.format('%d notes: %d downbeats, %d upbeats, measures %d-%d.',
                      #notes, downs, #notes - downs, first_bar, last_bar),
        sel_s and 'Range: the time selection, up to [end].'
              or 'Range: measure 1 up to [end].',
        'Time signatures: ' .. table.concat(meters, ', '),
    }
    if half then
        lines[#lines + 1] = style == 'pair'
            and 'Half time: downbeat on every other bar.'
            or  'Half time: downbeat on every bar.'
    end
    if removed > 0 then
        lines[#lines + 1] = string.format('Replaced %d existing BEAT notes.', removed)
    end
    if created then
        lines[#lines + 1] = 'BEAT had no MIDI item: created one from measure 1 to [end].'
    end
    S.last_result = table.concat(lines, '\n')
end
