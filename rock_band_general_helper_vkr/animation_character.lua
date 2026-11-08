-- Animation > Character: the character animation state text events on each
-- part track ([play] / [mellow] / [intense] while the part plays, [idle] in
-- long breaks, [idle_realtime] after the last note).
--
-- Rules, measured over the official RB3 DLC charts (591 songs) and matched
-- against CAT's create_animation_markers:
--   - Only Expert notes count. Overlapping notes merge into one run, so a
--     sustain keeps the part playing.
--   - The active state goes 1 QN before a run, [idle] 1 QN after a run's end
--     (official: 0.5-1 QN both ways; the RBN vocal doc: idle "a beat or so"
--     after the last note).
--   - A gap idles when it is at least the part's threshold: instruments 3 bars
--     (CAT; official instruments idle ~70% of 3-4 bar gaps), vocals 2 bars
--     (official vocals idle 71% of 2-3 bar gaps). A bar here is 4 QN.
--   - First note later than bar 3: [idle] at bar 3, then the active state
--     (CAT, and the official charts' usual opening).
--   - [idle_realtime] 1 QN after the last note (official: ~99% of tracks).
--   - PART DRUMS_2X gets the PART DRUMS rules (Magma turns it into PART DRUMS);
--     HARM1 the PART VOCALS rules. HARM2/3 and PART REAL_KEYS_* get nothing:
--     the official charts carry no state events there.
--
-- CharacterPlan is pure (no r); the rest touches REAPER.
-- Requires globals: r, S, FindTrackByName, FindFirstMIDIItem, GetTimeSelection

local EPS  = 1e-6   -- QN
local LEAD = 1      -- QN before a run: the active state
local TAIL = 1      -- QN after a run: [idle] / [idle_realtime]

-- The seven state events, with the RBN docs' descriptions: inst from the
-- guitar/bass page, vox from the vocal page. solo = guitar/bass only.
CHAR_STATES = {
    { msg = '[play]',          label = 'Play',          active = true,
      inst = 'Character is playing.',
      vox  = 'The standard singing state.' },
    { msg = '[mellow]',        label = 'Mellow',        active = true,
      inst = 'Character is playing in a mellow manner.',
      vox  = 'Used for slow, quiet sections of a song.' },
    { msg = '[intense]',       label = 'Intense',       active = true,
      inst = 'Character is playing in an intense manner.',
      vox  = 'Used for hard, fast sections of a song.' },
    { msg = '[play_solo]',     label = 'Play solo',     active = true, solo = true,
      inst = 'Character is playing fast notes while showing off.' },
    { msg = '[idle]',          label = 'Idle',
      inst = 'Character is idling normally (not playing/singing).',
      vox  = 'The character has their microphone down and dances to the beat.' },
    { msg = '[idle_intense]',  label = 'Idle intense',
      inst = 'Character is idling in an intense manner.',
      vox  = 'The character idles in an intense manner. For example, vocalist picks up ' ..
             'mic stand and dances, or jumps up and down next to mic stand.' },
    { msg = '[idle_realtime]', label = 'Idle realtime',
      inst = 'Character is idling in real time, not synced to the beat. ' ..
             "Use this for the intro & ends of songs or anywhere else you don't want " ..
             'a non-playing character bopping to the beat.',
      vox  = 'The character has their microphone down and is not synced to the beat. ' ..
             "Use this for intros and ends of songs, or anywhere else you don't want " ..
             'your singer bopping to the beat.' },
}
CHAR_STATE_SET = {}
for _, st in ipairs(CHAR_STATES) do CHAR_STATE_SET[st.msg] = st end

-- Drummer ride options (RBN drum doc), Manual only and drums only. Not states:
-- they switch how the ride is hit, so Generate leaves them alone, the state
-- readout ignores them, and inserting one replaces only a ride event on that
-- tick. No official RB3 DLC chart uses them (0 of 591 songs).
CHAR_RIDE_EVENTS = {
    { msg = '[ride_side_true]',  label = 'Ride side swipe',
      inst = "Drummer uses Max Weinberg's side swipe when hitting the ride slowly. " ..
             '(RBN docs; no official RB3 DLC chart uses it.)' },
    { msg = '[ride_side_false]', label = 'Ride normal',
      inst = 'Drummer hits the ride normally always. ' ..
             '(RBN docs; no official RB3 DLC chart uses it.)' },
}
CHAR_RIDE_SET = {}
for _, ev in ipairs(CHAR_RIDE_EVENTS) do CHAR_RIDE_SET[ev.msg] = ev end

-- Label / description lookup over both lists.
local function EventInfo(msg) return CHAR_STATE_SET[msg] or CHAR_RIDE_SET[msg] end

-- Generate's choices for the active state (index = S.char_active value + 1).
CHAR_ACTIVE_CHOICES = { '[play]', '[mellow]', '[intense]' }

-- Generate's rows. Each group shares one active-state pick.
CHAR_GROUPS = {
    { key = 'drums',  label = 'Drums',  tracks = { 'PART DRUMS', 'PART DRUMS_2X' } },
    { key = 'guitar', label = 'Guitar', tracks = { 'PART GUITAR' } },
    { key = 'bass',   label = 'Bass',   tracks = { 'PART BASS' } },
    { key = 'vocals', label = 'Vocals', tracks = { 'PART VOCALS', 'HARM1' }, vocal = true },
    { key = 'keys',   label = 'Keys',   tracks = { 'PART KEYS' } },
}

-- Every track that gets events: its Expert note range and its group.
-- optional = a project without it is normal (not listed as missing).
CHAR_PARTS = {
    { label = 'Drums',    track = 'PART DRUMS',    lo = 95, hi = 100, group = 'drums' },
    { label = 'Drums 2X', track = 'PART DRUMS_2X', lo = 95, hi = 100, group = 'drums', optional = true },
    { label = 'Guitar',   track = 'PART GUITAR',   lo = 96, hi = 100, group = 'guitar', solo = true },
    { label = 'Bass',     track = 'PART BASS',     lo = 96, hi = 100, group = 'bass',   solo = true },
    { label = 'Keys',     track = 'PART KEYS',     lo = 96, hi = 100, group = 'keys' },
    { label = 'Vocals',   track = 'PART VOCALS',   lo = 36, hi = 84,  group = 'vocals', vocal = true },
    { label = 'HARM1',    track = 'HARM1',         lo = 36, hi = 84,  group = 'vocals', vocal = true, optional = true },
}

-- The description of a state for a part (vocal wording for vocal parts).
function CharStateDesc(msg, vocal)
    local st = EventInfo(msg)
    if not st then return '' end
    return (vocal and st.vox) or st.inst
end

-- The readable name shown in the UI ("Idle realtime"); the event text itself
-- goes in tooltips and the result, as in Venue > Manual gen.
function CharStateLabel(msg)
    local st = EventInfo(msg)
    return st and st.label or msg
end

local function Trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- Plans one part's state events.
--   notes: { { s, e }, ... } in QN (any order)
--   opts:  active   the active state text, e.g. '[play]'
--          gap_qn   a gap at least this long idles
--          idle_gaps false = stay active through every gap
--          bar2_qn, bar3_qn  starts of measures 2 and 3
-- Returns events { { qn, msg }, ... } sorted, and stats { idles, kept }
-- (kept = gaps long enough to idle that stayed active because idle_gaps is off).
function CharacterPlan(notes, opts)
    local events, stats = {}, { idles = 0, kept = 0 }
    if #notes == 0 then return events, stats end
    local sorted = {}
    for i, n in ipairs(notes) do sorted[i] = n end
    table.sort(sorted, function(a, b) return a.s < b.s end)

    local runs = {}
    for _, n in ipairs(sorted) do
        local last = runs[#runs]
        if last and n.s <= last.e + EPS then
            if n.e > last.e then last.e = n.e end
        else
            runs[#runs + 1] = { s = n.s, e = n.e }
        end
    end

    local function Add(qn, msg) events[#events + 1] = { qn = qn, msg = msg } end

    -- Opening
    local first = runs[1].s
    if first - LEAD > opts.bar3_qn + EPS then
        Add(opts.bar3_qn, '[idle]')
        Add(first - LEAD, opts.active)
    else
        local a = first - LEAD
        if a < opts.bar2_qn and first >= opts.bar2_qn - EPS then a = opts.bar2_qn end
        Add(math.max(a, 0), opts.active)
    end

    -- Gaps
    for i = 1, #runs - 1 do
        local gap = runs[i + 1].s - runs[i].e
        if gap >= opts.gap_qn - EPS and gap > LEAD + TAIL + EPS then
            if opts.idle_gaps ~= false then
                Add(runs[i].e + TAIL, '[idle]')
                Add(runs[i + 1].s - LEAD, opts.active)
                stats.idles = stats.idles + 1
            else
                stats.kept = stats.kept + 1
            end
        end
    end

    -- Song end
    Add(runs[#runs].e + TAIL, '[idle_realtime]')
    table.sort(events, function(a, b) return a.qn < b.qn end)
    return events, stats
end

----------------------------------------------------------------------
-- REAPER side
----------------------------------------------------------------------

local function TrackMuted(track)
    return r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1
end

-- Availability of each Generate row: { [group key] = nil (usable) | reason }.
-- A row is usable when at least one of its tracks exists and is not muted.
function CharGroupStatus()
    local out = {}
    for _, g in ipairs(CHAR_GROUPS) do
        local any, muted = false, false
        for _, name in ipairs(g.tracks) do
            local tr = FindTrackByName(name)
            if tr then
                if TrackMuted(tr) then muted = true else any = true end
            end
        end
        if not any then out[g.key] = muted and 'muted' or 'no track' end
    end
    return out
end

-- Expert notes of a take as { { s, e } } in QN.
local function ReadExpertNotes(take, lo, hi)
    local out = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and pitch >= lo and pitch <= hi then
            out[#out + 1] = { s = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                              e = r.MIDI_GetProjQNFromPPQPos(take, eppq) }
        end
    end
    return out
end

-- Delete events of one set (default: the states) whose ppq is in
-- [lo_ppq, hi_ppq) (nil = no limit). Returns how many went.
local function DeleteStates(take, lo_ppq, hi_ppq, set)
    set = set or CHAR_STATE_SET
    local removed = 0
    local _, _, _, n_txt = r.MIDI_CountEvts(take)
    for i = n_txt - 1, 0, -1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and typ == 1 and set[Trim(msg)]
           and (not lo_ppq or ppq >= lo_ppq) and (not hi_ppq or ppq < hi_ppq) then
            r.MIDI_DeleteTextSysexEvt(take, i)
            removed = removed + 1
        end
    end
    return removed
end

-- The last event of one set (default: the states) at or before ppq on a take:
-- its text and its ppq, or nil.
function CharacterStateAt(take, ppq, set)
    set = set or CHAR_STATE_SET
    local best_ppq, best
    local _, _, _, n_txt = r.MIDI_CountEvts(take)
    for i = 0, n_txt - 1 do
        local ok, _, _, p, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and typ == 1 and p <= ppq + 0.5 then
            local m = Trim(msg)
            if set[m] and (not best_ppq or p >= best_ppq) then best_ppq, best = p, m end
        end
    end
    return best, best_ppq
end

local function ActiveFor(group_key)
    local v = S.char_active and S.char_active[group_key] or 0
    return CHAR_ACTIVE_CHOICES[(v or 0) + 1] or '[play]'
end

-- The Generate button: every part track, whole song or the time selection.
function GenerateCharacterAnimations()
    local bar2_qn = select(2, r.TimeMap_GetMeasureInfo(0, 1))
    local bar3_qn = select(2, r.TimeMap_GetMeasureInfo(0, 2))
    local sel_s, sel_e = GetTimeSelection()
    local sel_s_qn = sel_s and r.TimeMap2_timeToQN(0, sel_s)
    local sel_e_qn = sel_e and r.TimeMap2_timeToQN(0, sel_e)

    local jobs, lines, skipped = {}, {}, {}
    for _, p in ipairs(CHAR_PARTS) do
        local track = FindTrackByName(p.track)
        if not track then
            if not p.optional then skipped[#skipped + 1] = p.track .. ': no track' end
        elseif TrackMuted(track) then
            skipped[#skipped + 1] = p.track .. ': muted'
        else
            local item, take = FindFirstMIDIItem(track)
            local notes = take and ReadExpertNotes(take, p.lo, p.hi) or {}
            if #notes == 0 then
                skipped[#skipped + 1] = p.track .. ': no Expert notes'
            else
                local active = ActiveFor(p.group)
                local gap_bars = p.vocal and S.char_gap_vox_bars or S.char_gap_inst_bars
                local events, stats = CharacterPlan(notes, {
                    active = active, gap_qn = gap_bars * 4, idle_gaps = S.char_idle_gaps,
                    bar2_qn = bar2_qn, bar3_qn = bar3_qn,
                })
                -- Keep the selection's events and those the item can hold.
                local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                local i_s = r.TimeMap2_timeToQN(0, pos)
                local i_e = r.TimeMap2_timeToQN(0, pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH'))
                local keep, outside = {}, 0
                for _, ev in ipairs(events) do
                    if not sel_s or (ev.qn >= sel_s_qn - EPS and ev.qn < sel_e_qn - EPS) then
                        if ev.qn >= i_s - EPS and ev.qn < i_e - EPS then
                            keep[#keep + 1] = ev
                        else
                            outside = outside + 1
                        end
                    end
                end
                jobs[#jobs + 1] = { part = p, track = track, item = item, take = take,
                                    events = keep, stats = stats, outside = outside,
                                    active = active }
            end
        end
    end

    if #jobs == 0 then
        S.status = 'Character: nothing to write.'
        S.last_result = #skipped > 0 and table.concat(skipped, '\n') or nil
        return
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local total = 0
    for _, j in ipairs(jobs) do
        r.MarkTrackItemsDirty(j.track, j.item)
        local lo_ppq = sel_s and r.MIDI_GetPPQPosFromProjQN(j.take, sel_s_qn) - 0.5
        local hi_ppq = sel_s and r.MIDI_GetPPQPosFromProjQN(j.take, sel_e_qn) - 0.5
        local removed = DeleteStates(j.take, lo_ppq, hi_ppq)
        for _, ev in ipairs(j.events) do
            local ppq = r.MIDI_GetPPQPosFromProjQN(j.take, ev.qn)
            r.MIDI_InsertTextSysexEvt(j.take, false, false, ppq, 1, ev.msg, false)
        end
        total = total + #j.events
        local line = string.format('%s: %d events (%s), %d idle%s', j.part.track, #j.events,
                                   j.active, j.stats.idles, j.stats.idles == 1 and '' or 's')
        if j.stats.kept > 0 then
            line = line .. string.format(', %d long gap%s kept playing', j.stats.kept,
                                         j.stats.kept == 1 and '' or 's')
        end
        if removed > 0 then line = line .. string.format(', replaced %d', removed) end
        lines[#lines + 1] = line
        if j.outside > 0 then
            lines[#lines + 1] = string.format('  %d event%s outside the MIDI item - extend ' ..
                                              'the item and run again.', j.outside,
                                              j.outside == 1 and '' or 's')
        end
    end
    r.Undo_EndBlock2(0, string.format('Generate character animations (%d events)', total), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = string.format('Character: %d events on %d track%s.', total, #jobs,
                             #jobs == 1 and '' or 's')
    if sel_s then table.insert(lines, 1, 'Range: the time selection (planned from the whole song).') end
    if #skipped > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Skipped:'
        for _, s in ipairs(skipped) do lines[#lines + 1] = '  ' .. s end
    end
    S.last_result = table.concat(lines, '\n')
end

-- Manual: put msg on a part track at the edit cursor, replacing an event of
-- the same kind already on that tick (a state replaces a state, a ride option
-- a ride option). part_idx indexes CHAR_PARTS.
function InsertCharacterState(part_idx, msg)
    local p = CHAR_PARTS[part_idx]
    local set = CHAR_STATE_SET[msg] and CHAR_STATE_SET
             or (CHAR_RIDE_SET[msg] and p and p.group == 'drums' and CHAR_RIDE_SET)
    if not p or not set then return end
    local track = FindTrackByName(p.track)
    if not track then
        S.status = 'Character: no ' .. p.track .. ' track.'
        S.last_result = nil
        return
    end
    if TrackMuted(track) then
        S.status = 'Character: ' .. p.track .. ' is muted.'
        S.last_result = 'Muted tracks get no animation events. Unmute it first.'
        return
    end
    local item, take = FindFirstMIDIItem(track)
    if not take then
        S.status = 'Character: ' .. p.track .. ' has no MIDI item.'
        S.last_result = nil
        return
    end
    local t = r.GetCursorPosition()
    local pos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    if t < pos or t >= pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH') then
        S.status = 'Character: the playhead is outside the ' .. p.track .. ' MIDI item.'
        S.last_result = nil
        return
    end
    local ppq = math.floor(r.MIDI_GetPPQPosFromProjTime(take, t) + 0.5)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    local removed = DeleteStates(take, ppq - 0.5, ppq + 0.5, set)
    r.MIDI_InsertTextSysexEvt(take, false, false, ppq, 1, msg, false)
    r.Undo_EndBlock2(0, 'Insert ' .. msg .. ' on ' .. p.track, -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = string.format('%s %s on %s at %s.', removed > 0 and 'Replaced with' or 'Inserted',
                             msg, p.track, r.format_timestr_pos(t, '', 1))
    S.last_result = nil
end
