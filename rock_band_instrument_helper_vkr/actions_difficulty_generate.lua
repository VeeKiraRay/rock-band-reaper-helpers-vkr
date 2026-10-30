-- Difficulty > Generate: build Hard, Medium and Easy automatically from the tier above.
--
-- The REAPER side of the generator. Reads tiers off the instrument tracks, hands them to
-- the pure planners (difficulty_generate_5lane.lua, difficulty_generate_prokeys.lua),
-- writes the result back, and re-runs Validate's own checks on what it wrote. One undo
-- block covers a whole run, every instrument and tier included.
--
-- Requires (globals): S, r, GetTimeSelection, FindFirstMIDIItem, ClearNotesInRange,
--   InsertNotes, FindTrackExact (lib/reaper_difficulty_read.lua), Gen5PlanTier, GenPKPlanTier,
--   GenDrumsPlanTier (difficulty_generate_drums.lua), DRUMS_RANGE / ReadDrumsTierEvents /
--   CollectDrumsChecks (actions_difficulty_drums_checks.lua),
--   GEN_PK_WINDOWS, GB_RANGE / K5_RANGE, ReadGBTierEvents / ReadK5TierEvents,
--   CollectGBChecks / CollectK5Checks / CollectPKChecks, ReadPKTierEvents
--   (actions_difficulty.lua), ReadProKeysEvents (actions_difficulty_5k.lua), Gen5MarkHopos /
--   Gen5ForceHopoSpans (difficulty_generate_hopo.lua), Gen5PulseQN
--   (difficulty_generate_params.lua), GetBPMAt (actions_guitar.lua).

-- The instruments Generate supports, in dropdown order - which is also the run order of
-- All instruments, so Pro Keys comes before Keys (Keys follows the Pro Keys this run
-- generated). Adding one is one entry here plus its planner. idx_field is the
-- track field the instrument's own Difficulty sub-tab uses, so the selection is shared
-- rather than duplicated. Pro Keys has a track per tier: tier_fields instead.
GEN_INSTRUMENTS = {
    { key = 'gtr',  label = 'Guitar', track_name = 'PART GUITAR', idx_field = 'diff_gtr_idx',  kind = 'gb' },
    { key = 'bass', label = 'Bass',   track_name = 'PART BASS',   idx_field = 'diff_bass_idx', kind = 'gb' },
    { key = 'pk',   label = 'Pro Keys', track_name = 'PART REAL_KEYS_X', kind = 'pk',
      tier_fields = { X = 'diff_pk_x_idx', H = 'diff_pk_h_idx', M = 'diff_pk_m_idx', E = 'diff_pk_e_idx' } },
    { key = 'keys', label = 'Keys',   track_name = 'PART KEYS',   idx_field = 'diff_5k_idx',   kind = 'k5' },
    -- Drums: its own planner, independent of the band (difficulty_generate_drums.lua).
    -- x2: the song's PART DRUMS_2X (double bass pedal), generated in the same run, after
    -- PART DRUMS (ResolveTargets).
    { key = 'drums', label = 'Drums', track_name = 'PART DRUMS', idx_field = 'diff_drums_idx', kind = 'drums',
      x2 = { key = 'drums2x', label = 'Drums 2X', track_name = 'PART DRUMS_2X',
             idx_field = 'diff_drums2x_idx', kind = 'drums', double_pedal = true } },
}
-- Pro Keys pitches a tier owns: the lane-shift markers and the playable keys.
local PK_RANGES = { { 0, 0 }, { 2, 2 }, { 4, 5 }, { 7, 7 }, { 9, 9 }, { 48, 72 } }
local PK_WINDOW_NAMES = { [0] = 'C2-E3', [2] = 'D2-F3', [4] = 'E2-G3', [5] = 'F2-A3', [7] = 'G2-B3', [9] = 'A2-C4' }
GEN_ALL_KEY = 'all'

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

-- How a tier is written. 'bulk' (ReplaceNotesBulk): the take is read in one call, the
-- tier's old notes dropped and the new ones added in Lua, and written back in one call.
-- 'batched': ClearNotesInRange + InsertNotes with sorting off and one MIDI_Sort.
-- 'per_note': the same with REAPER sorting after every note.
-- Timed on a 210 BPM song (Guitar + Bass, Hard > Medium > Easy): per_note froze the
-- window for about 10 s, batched took 3.6 s, nearly all of it writing - deleting notes one
-- at a time shifts the whole take on every delete. Kept switchable only so the modes can
-- be timed against each other with the result's timing line.
local WRITE_MODE = 'bulk'
-- A run longer than this (seconds) lists its phases on the result's last line. A full
-- All instruments Hard > Medium > Easy takes 0.1-0.3 s with bulk writes.
local SLOW_RUN_S = 2.0
local UPPER      = { H = 'X', M = 'H', E = 'M' }
local MAX_LISTED = 8   -- unresolved Validate lines listed per tier in the result

function GenInstrumentByKey(key)
    for _, inst in ipairs(GEN_INSTRUMENTS) do
        if inst.key == key then return inst end
    end
    return nil
end

-- Pro Keys planner events carry real pitches (offs = pitch - 0).
local function RangeLo(inst, dl)
    if inst.kind == 'pk' then return 0 end
    if inst.kind == 'drums' then return DRUMS_RANGE[dl].lo end
    return (inst.kind == 'gb' and GB_RANGE or K5_RANGE)[dl].lo
end

-- One tier's events. track is that tier's own track for Pro Keys, the instrument's track
-- otherwise. Pro Keys also returns its lane-shift markers.
local function ReadTier(inst, track, dl, sel_s, sel_e)
    if inst.kind == 'pk' then
        local shifts, events = ReadPKTierEvents(track, sel_s, sel_e)
        return events, shifts
    end
    if inst.kind == 'gb' then return ReadGBTierEvents(track, dl, sel_s, sel_e) end
    if inst.kind == 'drums' then return ReadDrumsTierEvents(track, dl, sel_s, sel_e) end
    return ReadK5TierEvents(track, dl, sel_s, sel_e)
end

-- ctx: { shifts, exp_events } for Pro Keys (its checks need the markers and Expert).
local function CheckTier(inst, track, dl, events, sel_s, sel_e, ctx)
    if inst.kind == 'pk' then return CollectPKChecks(dl, events, ctx.shifts, ctx.exp_events, sel_s) end
    if inst.kind == 'gb' then return CollectGBChecks(dl, events, track, sel_s, sel_e) end
    if inst.kind == 'drums' then return CollectDrumsChecks(dl, events, track, sel_s, sel_e) end
    return CollectK5Checks(dl, events)
end

-- The pitch ranges a tier's write replaces: { { lo, hi }... }.
local function TierRanges(inst, dl)
    if inst.kind == 'pk' then return PK_RANGES end
    local lo = RangeLo(inst, dl)
    -- Guitar/Bass Hard also replaces its force-HOPO markers (lo + 5).
    return { { lo, (inst.kind == 'gb' and dl == 'H') and lo + 5 or lo + 4 } }
end

-- Validate's events ({ s, e, pitches }, project time) -> planner input.
-- Zero-length notes are left out: REAPER deletes them from a take the next time it is
-- edited (writing the generated tier is such an edit), so they are not part of the
-- chart, and generating from one would put a real note on the lower tier where the
-- upper has none.
local ZERO_LEN_S = 0.001

-- Positions and lengths snapped to 1/960 of a quarter note. Notes are read in seconds
-- and converted through the tempo map, and that round trip leaves float noise (around
-- 1e-9 QN): identical repeats of a riff came out a hair either side of a threshold (a
-- sustain exactly 1/8 long kept in one bar, cut in the next). Snapped, equal notes are
-- exactly equal, as their note values are.
--
-- 960 is a grid, NOT an assumed tick rate. Rock Band projects use 480 ticks per quarter
-- note, REAPER's own default is 960, and every tick at either rate falls exactly on this
-- grid, so snapping never moves a note that sits on a tick. Code that needs the real tick
-- rate must read it from the take (GetTakePPQPerQN, helpers.lua).
local SNAP = 960
local function SnapQN(qn) return math.floor(qn * SNAP + 0.5) / SNAP end

-- keep_zero: Pro Keys. Its tiers are separate tracks, so writing one never touches
-- Expert's take and its zero-length notes stay - and Validate still counts them. They are
-- used like any note (the planner gives every written note its minimum length), or the
-- lower tiers would miss a measure Expert plays (rb_pro_keys.mid's last chord).
function GenToPlannerEvents(events, lo, keep_zero)
    local out = {}
    for _, ev in ipairs(events) do
        if ev.e - ev.s < ZERO_LEN_S and not keep_zero then goto next_ev end
        local qn = SnapQN(r.TimeMap2_timeToQN(0, ev.s))
        -- Bar start and end in quarter notes, so time signature changes are honoured.
        local _, bar_s, bar_e = r.TimeMap_QNToMeasures(0, qn)
        bar_s, bar_e = SnapQN(bar_s), SnapQN(bar_e)
        local num, den = r.TimeMap_GetTimeSigAtTime(0, ev.s)
        local offs = {}
        for i, p in ipairs(ev.pitches) do offs[i] = p - lo end
        out[#out + 1] = {
            qn     = qn,
            qn_e   = SnapQN(r.TimeMap2_timeToQN(0, ev.e)),
            offs   = offs,
            -- The tempo marker in effect (GetBPMAt, actions_guitar.lua): quarter notes per
            -- minute, what Validate's rules and the offline tools read. NOT
            -- TimeMap_GetDividedBpmAtTime, which is "2x in /8 signatures" - a 6/8 song at
            -- 105 read as 210, and every rule for songs over 160 BPM fired.
            bpm    = GetBPMAt(ev.s),
            bar_qn  = qn - bar_s,
            bar_len = bar_e - bar_s,
            pulse   = Gen5PulseQN(num or 4, den or 4),
            down    = qn - bar_s <= 0.02 or bar_e - qn <= 0.02,
        }
        ::next_ev::
    end
    return out
end

-- Zero-length notes in a take, keyed "ppq:pitch". Writing a generated tier into the take
-- makes REAPER drop zero-length notes from ALL of it - Expert, other tiers, markers - so
-- GenerateDifficulties records them before writing and reports the ones that are gone
-- afterwards. They are authoring errors (the RBN minimum is a 1/64 note), and once REAPER
-- has removed them Validate can no longer find them, so this report is the only trace.
local function ZeroLengthNotes(take)
    local found = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and eppq <= sppq then found[('%d:%d'):format(sppq, pitch)] = { ppq = sppq, pitch = pitch } end
    end
    return found
end

local TIER_LO     = { { 'Expert', 96 }, { 'Hard', 84 }, { 'Medium', 72 }, { 'Easy', 60 } }
local GEM_LETTERS = { [0] = 'G', 'R', 'Y', 'B', 'O' }
-- Guitar/Bass/Keys marker pitches, named so a removed marker is recognisable.
local MARKER_NAMES = {
    [103] = 'Solo marker', [116] = 'Overdrive marker',
    [126] = 'Tremolo marker', [127] = 'Trill marker',
}

-- "Expert R" for a gem pitch, "Overdrive marker (116)" for a known marker, else "pitch N".
local function DescribePitch(pitch)
    for _, t in ipairs(TIER_LO) do
        local o = pitch - t[2]
        if o >= 0 and o <= 4 then return t[1] .. ' ' .. GEM_LETTERS[o] end
    end
    if MARKER_NAMES[pitch] then return ('%s (%d)'):format(MARKER_NAMES[pitch], pitch) end
    return 'pitch ' .. pitch
end

-- Result lines for zero-length notes REAPER removed while this run wrote to the take.
-- replaced: { { lo, hi }... } pitch ranges of the tiers this run regenerated - their old
-- notes are cleared by Generate itself, so they are not reported as REAPER's doing.
local function RemovedZeroLengthLines(take, before, replaced)
    local after = ZeroLengthNotes(take)
    local function Replaced(pitch)
        for _, rg in ipairs(replaced) do
            if pitch >= rg[1] and pitch <= rg[2] then return true end
        end
        return false
    end
    local gone = {}
    for key, z in pairs(before) do
        if not after[key] and not Replaced(z.pitch) then gone[#gone + 1] = z end
    end
    if #gone == 0 then return {} end
    table.sort(gone, function(a, b)
        if a.ppq ~= b.ppq then return a.ppq < b.ppq end
        return a.pitch < b.pitch
    end)
    -- One entry per position: "m11  19.290s: Expert R + Expert Y + Expert B".
    local by_pos, order = {}, {}
    for _, z in ipairs(gone) do
        if not by_pos[z.ppq] then by_pos[z.ppq] = {}; order[#order + 1] = z.ppq end
        table.insert(by_pos[z.ppq], DescribePitch(z.pitch))
    end
    local lines = { ('  %d zero-length note%s removed by REAPER when Generate wrote to this track:'):format(
        #gone, #gone == 1 and ' was' or 's were') }
    for k, ppq in ipairs(order) do
        if k > MAX_LISTED then
            lines[#lines + 1] = ('    ... and %d more positions'):format(#order - MAX_LISTED)
            break
        end
        lines[#lines + 1] = ('    %s: %s'):format(FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, ppq)),
            table.concat(by_pos[ppq], ' + '))
    end
    lines[#lines + 1] = '    A note needs a length (1/64 or more). If these were meant to be notes,'
    lines[#lines + 1] = '    re-author them with a length and generate again.'
    return lines
end

-- The same-tier Pro Keys chart Keys follows, as { { qn, qn_e }... }, or nil when there
-- is no such track or it is empty.
-- by_name false: the Pro Keys sub-tab's track selection only (auto-detected at startup),
--   so Keys never follows a track the user did not pick.
-- by_name true (All instruments): the default track name, like every other track in
--   that mode.
-- generated: this run's Pro Keys output per tier ({ [dl] = planner events }), which wins
--   over the track - Keys follows the Pro Keys the same run just built.
local function ProKeysGuide(dl, sel_s, sel_e, by_name, generated)
    if generated and generated[dl] then
        local guide = {}
        for _, ev in ipairs(generated[dl]) do guide[#guide + 1] = { qn = ev.qn, qn_e = ev.qn_e } end
        return #guide > 0 and guide or nil
    end
    local track
    if by_name then
        track = FindTrackExact('PART REAL_KEYS_' .. dl)
    else
        local idx = S['diff_pk_' .. dl:lower() .. '_idx']
        track = idx and idx >= 0 and r.GetTrack(0, idx) or nil
    end
    if not track then return nil end
    local events = ReadProKeysEvents(track, sel_s, sel_e)
    if #events == 0 then return nil end
    local guide = {}
    for _, ev in ipairs(events) do
        guide[#guide + 1] = { qn = SnapQN(r.TimeMap2_timeToQN(0, ev.s)),
                              qn_e = SnapQN(r.TimeMap2_timeToQN(0, ev.e)) }
    end
    return guide
end

-- Result lines for the bars whose fast runs Hard rewrote one grid slower
-- (log.retimed_bars): measure ranges per target grid, as an advisory to check by hand -
-- the rewrite keeps the motion of the line, but a solo may want its own touch.
-- Notes per quarter note -> the grid's name.
local GRID_NAMES = { [2] = '8ths', [3] = '8th triplets', [4] = '16ths', [6] = '16th triplets', [8] = '32nds' }

-- The measure number (as REAPER shows it) of a position in quarter notes.
local function MeasureAt(qn)
    local t = r.TimeMap2_QNToTime(0, qn + 0.001)
    return tonumber((r.format_timestr_pos(t, '', 1) or ''):match('^%s*(%-?%d+)'))
end

-- Measure numbers -> "m20-25, m28" (sorted, consecutive ones joined).
local function MeasureRanges(bars)
    table.sort(bars)
    local ranges, i = {}, 1
    while i <= #bars do
        local j = i
        while j < #bars and bars[j + 1] <= bars[j] + 1 do j = j + 1 end
        ranges[#ranges + 1] = j > i and bars[j] ~= bars[i] and ('m%d-%d'):format(bars[i], bars[j])
                              or ('m%d'):format(bars[i])
        i = j + 1
    end
    return table.concat(ranges, ', ')
end

local function RetimedLines(retimed)
    if not retimed or #retimed == 0 then return {} end
    local by_grid, order = {}, {}
    for _, rb in ipairs(retimed) do
        local name = 'to ' .. (GRID_NAMES[math.floor(1 / rb.grid + 0.5)] or ('1/%g QN'):format(1 / rb.grid))
        if not by_grid[name] then by_grid[name] = {}; order[#order + 1] = name end
        local bar = MeasureAt(rb.start)
        if bar then table.insert(by_grid[name], bar) end
    end
    local parts = {}
    for _, name in ipairs(order) do
        parts[#parts + 1] = ('%s: %s'):format(name, MeasureRanges(by_grid[name]))
    end
    return {
        ('    %d bar%s of fast runs rewritten one grid slower - review by hand:'):format(
            #retimed, #retimed == 1 and '' or 's'),
        '      ' .. table.concat(parts, '; '),
    }
end

-- Replace the notes of the pitch ranges ({ { lo, hi }... }) that START in [clear_s,
-- clear_e) (seconds) - or, with clear_s nil, every such note in the take - with `notes` ({ s, e, pitch } in seconds, written on channel 1 at
-- velocity vel), in one MIDI_GetAllEvts / MIDI_SetAllEvts round trip. By start, not by
-- overlap (ClearNotesInRange's rule): the selection rule in GenerateDifficulties, so a
-- sustain from before the selection is kept rather than deleted and never regenerated.
-- Every other event - other pitches, CCs, text, sysex, the take's end marker - is written
-- back unchanged and in its original order. (The 'batched' / 'per_note' timing modes
-- still clear by overlap.)
-- Buffer format (ReaScript API): per event an int32 offset in ticks from the previous
-- event, a flag byte, an int32 length and the message bytes.
-- Returns false when the take could not be read (the caller falls back to batched).
local function ReplaceNotesBulk(take, clear_s, clear_e, ranges, notes, vel)
    local ok, buf = r.MIDI_GetAllEvts(take, '')
    if not ok or type(buf) ~= 'string' then return false end
    local whole = clear_s == nil
    local s_ppq = not whole and r.MIDI_GetPPQPosFromProjTime(take, clear_s) or 0
    local e_ppq = not whole and r.MIDI_GetPPQPosFromProjTime(take, clear_e) or 0
    local owned = {}
    for _, rg in ipairs(ranges) do
        for p = rg[1], rg[2] do owned[p] = true end
    end

    -- Half a tick each way: a note exactly on the selection's start is in, one exactly on
    -- its end is out, whatever the float rounding.
    local function InWindow(at) return whole or (at >= s_ppq - 0.5 and at < e_ppq - 0.5) end

    local evs, open, drop = {}, {}, {}
    -- A zero-length note is stored with its note-off FIRST, at the note-on's own tick, so
    -- first-on-first-off pairing never matched it: the old note stayed, and the new one
    -- written at that position doubled every pitch (rb_pro_keys.mid's last chord, in
    -- REAPER: [E2+E2+G2+G2+B2+B2]). An off with nothing open waits here for an on at the
    -- same tick.
    local early_off = {}
    local pos, ppq, n = 1, 0, #buf
    while pos <= n do
        local off, flag, msg
        off, flag, msg, pos = string.unpack('<i4Bs4', buf, pos)
        ppq = ppq + off
        local k = #evs + 1
        evs[k] = { ppq = ppq, flag = flag, msg = msg, cls = 1, ord = k }
        if #msg >= 3 then
            local st = msg:byte(1)
            local typ, pitch, v = st & 0xF0, msg:byte(2), msg:byte(3)
            if (typ == 0x90 or typ == 0x80) and owned[pitch] then
                local key = (st & 0x0F) * 128 + pitch
                if typ == 0x90 and v > 0 then
                    local eo = early_off[key]
                    if eo and evs[eo].ppq == ppq then
                        -- The zero-length note this early off belongs to.
                        early_off[key] = nil
                        if InWindow(ppq) then drop[eo], drop[k] = true, true end
                    else
                        open[key] = open[key] or {}
                        table.insert(open[key], k)
                    end
                else
                    -- First on, first off - the pairing REAPER's note list uses.
                    local q = open[key]
                    local on = q and table.remove(q, 1)
                    if on then
                        if InWindow(evs[on].ppq) then drop[on], drop[k] = true, true end
                    else
                        early_off[key] = k
                    end
                end
            end
        end
    end
    -- A note-on that never closed, inside the window: nothing may stay behind to pair with
    -- a note-off written below.
    for _, q in pairs(open) do
        for _, k in ipairs(q) do if InWindow(evs[k].ppq) then drop[k] = true end end
    end

    local out = {}
    for k, ev in ipairs(evs) do if not drop[k] then out[#out + 1] = ev end end
    -- New notes: at one tick, a new note-off goes before the old events there and a new
    -- note-on after them, so a new note never swallows an old one's end or start.
    local m = #evs
    for _, nt in ipairs(notes) do
        local sp = math.floor(r.MIDI_GetPPQPosFromProjTime(take, nt.s) + 0.5)
        local ep = math.floor(r.MIDI_GetPPQPosFromProjTime(take, nt.e) + 0.5)
        m = m + 1
        out[#out + 1] = { ppq = sp, flag = 0, msg = string.char(0x90, nt.pitch, vel), cls = 2, ord = m }
        m = m + 1
        out[#out + 1] = { ppq = ep, flag = 0, msg = string.char(0x80, nt.pitch, 0), cls = 0, ord = m }
    end
    table.sort(out, function(a, b)
        if a.ppq ~= b.ppq then return a.ppq < b.ppq end
        if a.cls ~= b.cls then return a.cls < b.cls end
        return a.ord < b.ord
    end)

    local parts, last = {}, 0
    for i, ev in ipairs(out) do
        parts[i] = string.pack('<i4Bs4', ev.ppq - last, ev.flag, ev.msg)
        last = ev.ppq
    end
    r.MIDI_SetAllEvts(take, table.concat(parts))
    return true
end

-- One marker pitch's notes in a take as spans { { qn, qn_e }... }, inside [sel_s, sel_e]
-- (seconds) when given.
local function MarkerSpans(take, pitch, sel_s, sel_e)
    local spans = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, p, vel = r.MIDI_GetNote(take, i)
        if ok and p == pitch then
            local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            if not sel_s or (s >= sel_s - 0.001 and s < sel_e) then
                spans[#spans + 1] = { qn = SnapQN(r.TimeMap2_timeToQN(0, s)), vel = vel,
                                      qn_e = SnapQN(r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(take, eppq))) }
            end
        end
    end
    return spans
end

-- The marker context the Drums planner takes (difficulty_generate_drums.lua, opts.ctx),
-- over the WHOLE take even in a time selection (a fill or disco section may start before
-- it): fill lanes (120), roll lanes (126/127), Pro Drums tom markers (110-112), Expert's
-- disco-flip spans ([mix 3 drumsNd] up to the next [mix 3 drumsN]; "dnoflip" is not a
-- flip), and the EVENTS track's [section] / [prc_] names (Easy's beat type).
local function DrumsContext(take)
    local ctx = { fills = MarkerSpans(take, 120), rolls = MarkerSpans(take, 126),
                  toms = { [2] = MarkerSpans(take, 110), [3] = MarkerSpans(take, 111), [4] = MarkerSpans(take, 112) },
                  disco = {}, sections = {} }
    for _, sp in ipairs(MarkerSpans(take, 127)) do sp.two = true; ctx.rolls[#ctx.rolls + 1] = sp end
    local function QN(ppq, tk) return SnapQN(r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(tk, ppq))) end
    local texts = {}
    local _, _, _, n_txt = r.MIDI_CountEvts(take)
    for i = 0, n_txt - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and typ == 1 then texts[#texts + 1] = { qn = QN(ppq, take), msg = msg } end
    end
    table.sort(texts, function(a, b) return a.qn < b.qn end)
    local open
    for _, t in ipairs(texts) do
        local suffix = t.msg:match('^%[mix 3 drums%d(%a*)%]')
        if suffix == 'd' then
            open = open or t.qn
        elseif suffix and open then
            ctx.disco[#ctx.disco + 1] = { qn = open, qn_e = t.qn }
            open = nil
        end
    end
    if open then ctx.disco[#ctx.disco + 1] = { qn = open, qn_e = math.huge } end
    local ev_track = FindTrackExact('EVENTS')
    local ev_take
    if ev_track then ev_take = select(2, FindFirstMIDIItem(ev_track)) end
    if ev_take then
        local _, _, _, n = r.MIDI_CountEvts(ev_take)
        for i = 0, n - 1 do
            local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(ev_take, i)
            local name = ok and typ == 1 and (msg:match('^%[section (.-)%]') or msg:match('^%[prc_(.-)%]'))
            if name then ctx.sections[#ctx.sections + 1] = { qn = QN(ppq, ev_take), name = name } end
        end
    end
    -- The tempo at bar 1, the song's authored tempo (difficulty_generate_drums.lua, SongTempo).
    ctx.song_bpm = GetBPMAt(r.TimeMap2_QNToTime(0, 0))
    return ctx
end

-- Positions (QN, per color 2-4) of the cymbal gems - Yellow/Blue/Green with no tom marker
-- over them - this run leaves in the take: Expert's, every tier it does not write, and
-- the written tiers' notes outside the time selection. Hard's rewrite never puts a tom
-- marker over one (opts.keep_cymbals, difficulty_generate_drums.lua).
local function DrumsKeptCymbals(track, ctx, tiers, sel_s, sel_e)
    local writing = {}
    for _, dl in ipairs(tiers) do writing[dl] = true end
    local out = { [2] = {}, [3] = {}, [4] = {} }
    for _, dl in ipairs({ 'X', 'H', 'M', 'E' }) do
        local lo = DRUMS_RANGE[dl].lo
        for _, n in ipairs(ReadDrumsNotes(track, lo + 2, lo + 4)) do
            local inside = not sel_s or (n.s >= sel_s - 0.001 and n.s < sel_e)
            if not (writing[dl] and inside) then
                local o, qn = n.pitch - lo, SnapQN(r.TimeMap2_timeToQN(0, n.s))
                local tom = false
                for _, sp in ipairs(ctx.toms[o] or {}) do
                    if qn >= sp.qn - 0.004 and qn < sp.qn_e - 0.004 then tom = true; break end
                end
                if not tom then table.insert(out[o], qn) end
            end
        end
    end
    return out
end

-- Hard's rewrite moved toms off their Pro Drums tom markers: each new marker
-- (log.tom_markers) replaces the old ones it covers. Markers are shared by every tier; the
-- planner made sure no cymbal ends up under a new one. Inside the caller's undo block.
local function WriteTomMarkers(take, markers)
    if #markers == 0 then return end
    local gone = {}
    for _, m in ipairs(markers) do
        for _, sp in ipairs(m.replaces) do gone[#gone + 1] = { pitch = 108 + m.o, qn = sp.qn, qn_e = sp.qn_e } end
    end
    local function QN(ppq) return SnapQN(r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(take, ppq))) end
    local _, n = r.MIDI_CountEvts(take)
    for i = n - 1, 0, -1 do   -- reverse: deleting shifts the later indexes
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= 110 and p <= 112 then
            local qn, qn_e = QN(sppq), QN(eppq)
            for _, g in ipairs(gone) do
                if g.pitch == p and math.abs(g.qn - qn) < 0.002 and math.abs(g.qn_e - qn_e) < 0.002 then
                    r.MIDI_DeleteNote(take, i)
                    break
                end
            end
        end
    end
    for _, m in ipairs(markers) do
        local s = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap2_QNToTime(0, m.qn))
        local e = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap2_QNToTime(0, m.qn_e))
        r.MIDI_InsertNote(take, false, false, s, e, 0, 108 + m.o, 100, false)
    end
end

-- kept of upper as a whole percentage that never rounds to the ends: 100 only when
-- nothing was dropped (829 of 833 is 99, not 100), 0 only when nothing was kept.
function KeptPercent(kept, upper)
    if upper <= 0 then return 0 end
    local p = math.floor(100 * kept / upper + 0.5)
    if kept < upper then p = math.min(p, 99) end
    if kept > 0 then p = math.max(p, 1) end
    return p
end

-- Result lines for one Drums tier (log from GenDrumsPlanTier).
local function DrumsLines(dl, log, opts)
    local lines = {}
    if log.unflipped > 0 then
        lines[#lines + 1] = ('    %d hits in Expert\'s disco-flip sections played as a normal beat (hi-hat back on'
            .. ' Yellow, snare on Red); set this tier\'s [mix N drums...] events to the plain config'):format(log.unflipped)
    end
    if log.rolls > 0 then
        lines[#lines + 1] = ('    %d roll lane%s played on the %s grid with an even number of hits'):format(log.rolls,
            log.rolls == 1 and '' or 's', dl == 'H' and '16th (8th at 140+ BPM)' or dl == 'M' and '8th (quarter at 120+ BPM)'
            or 'quarter-note')
    end
    if dl == 'H' then
        local what = ({ auto = 'rewritten one grid slower above 160 BPM, thinned below',
                        thin = 'thinned to the Hard grid (never rewritten)',
                        rewrite = 'rewritten one grid slower (at or below 160 BPM: runs of half a bar or more)' })[
                        opts.fast_runs or GEN5_PARAMS.fast_runs_default]
        if what then lines[#lines + 1] = '    tom/snare fill runs: ' .. what end
        for _, l in ipairs(RetimedLines(log.retimed_bars)) do lines[#lines + 1] = l end
        local function Bars(list)
            local bars = {}
            for _, bq in ipairs(list) do bars[#bars + 1] = MeasureAt(bq) end
            return MeasureRanges(bars)
        end
        if #(log.tom_markers or {}) > 0 then
            local starts = {}
            for _, m in ipairs(log.tom_markers) do
                for _, bq in ipairs(m.bars) do starts[#starts + 1] = bq end
            end
            lines[#lines + 1] = ('    %s: tom markers were modified to support Hard\'s rewrite to a different grid'
                .. ' - check the result'):format(Bars(starts))
        end
        if #(log.too_many_gems or {}) > 0 then
            lines[#lines + 1] = ('    %s: a hit with more than two hand gems in the tier above (unplayable: two hands,'
                .. ' one foot) - fix it there; Hard keeps the kick and two'):format(Bars(log.too_many_gems))
        end
        if #(log.tom_conflict_bars or {}) > 0 then
            lines[#lines + 1] = ('    %s: fill run not rewritten - its tom marker would cover a cymbal of the same'
                .. ' color, so it was thinned instead; reduce it by hand to rewrite it'):format(Bars(log.tom_conflict_bars))
        end
    end
    if log.single_from then
        local from = DIFF_NAMES[log.single_from]
        if log.single_mem then
            lines[#lines + 1] = ('    kicks: the in-memory single-pedal %s\'s %d, kept except where %s may not have'
                .. ' one'):format(from, log.single_kicks, DIFF_NAMES[dl])
            if log.single_from == 'X' then
                lines[#lines + 1] = '      (this track\'s Expert as "Remove 2x kicks" would leave it, then reduced with'
                    .. ' the single-pedal rules; never written)'
            end
        elseif opts.keep_kicks then
            lines[#lines + 1] = ('    kicks: PART DRUMS %s\'s %d, kept except where %s may not have one - review'
                .. ' them against the 2X hands'):format(from, log.single_kicks, DIFF_NAMES[dl])
        else
            lines[#lines + 1] = ('    kicks: PART DRUMS %s has no kicks here, so %s\'s were reduced as usual -'
                .. ' generate PART DRUMS first'):format(from, DIFF_NAMES[dl])
        end
    end
    if dl == 'H' and log.hard_fallback then
        lines[#lines + 1] = ('    Hard would have kept %d of %d notes (more than %d%% of Expert), so %d hi-hat%s left'
            .. ' steady 8th bars (%d per bar - "Hard 8th runs": %s)'):format(log.hard_fallback.before, log.upper_notes,
            math.floor(100 * GEN_DRUMS_PARAMS.hard_fallback_keep + 0.5), log.hat_drops or 0,
            (log.hat_drops or 0) == 1 and '' or 's', log.busy_drop, log.busy_auto and 'Auto' or 'your choice')
    elseif dl == 'H' and (log.hat_drops or 0) > 0 then
        lines[#lines + 1] = ('    %d hi-hat%s left steady 8th bars (%d per bar - "Hard 8th runs": %s)'):format(
            log.hat_drops, log.hat_drops == 1 and '' or 's', log.busy_drop, log.busy_auto and 'Auto' or 'your choice')
    end
    if dl == 'M' and log.fallback then
        lines[#lines + 1] = ("    Medium's hands would have kept %d of Hard's %d hand notes (more than %d%%), so the"
            .. ' hi-hat/ride moved to quarter notes'):format(log.fallback.before_hands, log.upper_hands,
            math.floor(100 * GEN_DRUMS_PARAMS.medium_fallback_keep + 0.5))
    end
    if dl == 'M' then
        lines[#lines + 1] = '    kick/snare between hi-hat notes: ' .. (({ beats = 'kept on the beat only',
            none = 'none kept', keep = 'all kept' })[opts.between or 'beats'] or '?')
    end
    if dl == 'E' then
        local ks, hands = log.easy_types.ks, log.easy_types.hands
        lines[#lines + 1] = ('    beat per section: %d kick + snare, %d two-hand%s'):format(ks, hands,
            (ks + hands <= 1) and ' (no EVENTS sections found - one beat type for the whole song)' or '')
    end
    if (log.sandwiched or 0) > 0 then
        lines[#lines + 1] = ('    %d hi-hat/ride hit%s between snare accents removed, so the hands do not alternate'
            .. ' hat and accent on every 8th'):format(log.sandwiched, log.sandwiched == 1 and '' or 's')
    end
    if (log.tom_before_crash or 0) > 0 then
        lines[#lines + 1] = ('    %d tom%s before a crash removed (the snare stays), so the hand can reach the crash'):format(
            log.tom_before_crash, log.tom_before_crash == 1 and '' or 's')
    end
    if (log.before_crash or 0) > 0 then
        lines[#lines + 1] = ('    %d hi-hat/ride note%s an 8th before a crash removed, so the hand can reach the crash'):format(
            log.before_crash, log.before_crash == 1 and '' or 's')
    end
    if (log.drum_changes or 0) > 0 then
        lines[#lines + 1] = ('    %d two-hand hit%s lost the drum before a change of drum an 8th later'):format(
            log.drum_changes, log.drum_changes == 1 and '' or 's')
    end
    if (log.cym_changes or 0) > 0 then
        lines[#lines + 1] = ('    %d hi-hat/ride hit%s removed where the hand would jump to another cymbal an 8th later'
            .. ' or earlier'):format(log.cym_changes, log.cym_changes == 1 and '' or 's')
    end
    if (log.cym_changes_quarter or 0) > 0 then
        lines[#lines + 1] = ('    %d hi-hat/ride hit%s removed between two hits on other cymbals a quarter apart (%d+ BPM)'):format(
            log.cym_changes_quarter, log.cym_changes_quarter == 1 and '' or 's',
            GEN_DRUMS_PARAMS.easy_cymbal_change_quarter_bpm)
    end
    if (log.lone_ands or 0) > 0 then
        lines[#lines + 1] = ('    %d lone drum "and"%s between two beat hits removed (%d+ BPM: too quick for Easy)'):format(
            log.lone_ands, log.lone_ands == 1 and '' or 's', GEN_DRUMS_PARAMS.easy_lone_and_bpm)
    end
    if (log.tom_pairs or 0) > 0 then
        lines[#lines + 1] = ('    %d two-hand hit%s with a tom played as one gem (two toms: the higher lane; cymbal + tom:'
            .. ' the tom)'):format(log.tom_pairs, log.tom_pairs == 1 and '' or 's')
    end
    if log.runs_broken > 0 then
        lines[#lines + 1] = ('    %d run%s of four 8ths broken up (too fast for constant 8ths on %s)'):format(
            log.runs_broken, log.runs_broken == 1 and '' or 's', DIFF_NAMES[dl])
    end
    if (log.snare_runs or 0) > 0 then
        lines[#lines + 1] = ('    %d "and" hit%s of long 8th snare runs removed - quarter notes on the beats (%d+ BPM)'):format(
            log.snare_runs, log.snare_runs == 1 and '' or 's', GEN_DRUMS_PARAMS.easy_snare_run_bpm or 0)
    end
    if (log.expert_runs or 0) > 0 then
        lines[#lines + 1] = ('    %d bar%s with a fill Hard rewrote off the 8th grid: reduced from Expert\'s notes instead'):format(
            log.expert_runs, log.expert_runs == 1 and '' or 's')
    end
    if (log.eighth_hands or 0) > 0 then
        local bpm = (GEN_DRUMS_PARAMS.lower_eighth_hands_bpm or {})[dl] or 0
        lines[#lines + 1] = ('    %d hand hit%s removed so no three come an 8th apart (%d+ BPM; "Drums fast 8ths": %s)'):format(
            log.eighth_hands, log.eighth_hands == 1 and '' or 's', bpm,
            log.eighth_hands_mode == 'hands' and 'Hands' or 'Beats')
    end
    return lines
end

-- Result line for the force-HOPO markers written on Hard (spans from Gen5ForceHopoSpans).
local function HopoLines(spans)
    if #spans == 0 then return {} end
    local notes, bars = 0, {}
    for _, sp in ipairs(spans) do
        notes = notes + sp.count
        local a, b = MeasureAt(sp.qn), MeasureAt(sp.qn_e - 0.01)
        if a then
            for m = a, b or a do bars[#bars + 1] = m end
        end
    end
    return { ('    %d note%s kept Expert\'s hammer-ons with force-HOPO markers (%s)'):format(
        notes, notes == 1 and '' or 's', MeasureRanges(bars)) }
end

-- What Bass and Keys follow from Guitar, planned in memory from PART GUITAR (nothing is
-- written): its Hard busy bars (a bar of the same rhythm loses the same notes) and its
-- Medium rhythm (a bar of the same Hard rhythm keeps the same Medium onsets). Computed the
-- same way whether Guitar is part of this run or not, so generating Bass alone gives what
-- All instruments gives. A run starting at Hard plans Guitar's Hard from its Expert and its
-- Medium from that; a run starting at Medium plans it from Guitar's Hard as it is.
-- Track: by name in All instruments, else the Guitar sub-tab's selection - and by name
-- when nothing is selected there, since Bass and Keys always follow PART GUITAR.
-- Returns { H = log.busy_bars, M = log.rhythm_bars } (entries nil when there is nothing).
local function GuitarRefs(sel_s, sel_e, by_name, busy_drop, first_tier, fast_runs)
    local refs = {}
    if first_tier == 'E' then return refs end
    local inst = GenInstrumentByKey('gtr')
    local idx = not by_name and S[inst.idx_field] or nil
    local track = idx and idx >= 0 and r.GetTrack(0, idx) or FindTrackExact(inst.track_name)
    if not track then return refs end
    local src_dl = first_tier == 'H' and 'X' or 'H'
    local src = ReadTier(inst, track, src_dl, sel_s, sel_e)
    if #src == 0 then return refs end
    local upper = GenToPlannerEvents(src, RangeLo(inst, src_dl))
    if first_tier == 'H' then
        local log
        upper, log = Gen5PlanTier('gb', 'H', upper, { busy_drop = busy_drop, fast_runs = fast_runs })
        refs.H = log.busy_bars
    end
    local _, mlog = Gen5PlanTier('gb', 'M', upper)
    refs.M = mlog.rhythm_bars
    return refs
end

-- Drums 2X with no usable PART DRUMS: the single-pedal tiers it would have, made in memory
-- and never written - Expert from the 2X Expert (GenDrumsSinglePedal), Hard and Medium
-- planned from it as PART DRUMS would be. opts: the run's Drums options.
local function SinglePedalTiers(job, sel_s, read_e, opts)
    local x2 = GenToPlannerEvents((ReadTier(job.inst, job.track, 'X', sel_s, read_e)), DRUMS_RANGE.X.lo, false)
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.ctx = job.drums_ctx
    local tiers = { X = GenDrumsSinglePedal(x2) }
    local hlog
    tiers.H, hlog = GenDrumsPlanTier('H', tiers.X, o)
    o.ctx = hlog.ctx
    o.expert = tiers.X
    tiers.M = GenDrumsPlanTier('M', tiers.H, o)
    return tiers
end

-- One instrument's targets. Drums with a PART DRUMS_2X: the PART DRUMS target (when its track is there and not
-- muted) and the 2X one after it, which takes its kicks from that PART DRUMS - or, with
-- none usable, from a single-pedal version made in memory (single_track = nil). Generate
-- never writes to a muted track (a template's muted PART DRUMS_2X must not be overwritten):
-- All instruments skips muted tracks and
-- passes x2 = nil for a muted 2X track; a single selection with a muted track stops before
-- anything (ResolveTargets). A song without a 2X track gets the plain Drums target.
local function AddTargets(inst, base, x2, targets, skipped)
    local muted = base and r.GetMediaTrackInfo_Value(base, 'B_MUTE') == 1
    if not x2 then
        if base then targets[#targets + 1] = { inst = inst, track = base } end
        return
    end
    local usable = base and not muted
    if usable then
        targets[#targets + 1] = { inst = inst, track = base }
    else
        skipped[#skipped + 1] = ('%s: %s %s - not generated; Drums 2X takes its kicks from a single-pedal'
            .. ' version made in memory'):format(inst.label, inst.track_name, base and 'is muted' or 'not found')
    end
    targets[#targets + 1] = { inst = inst.x2, track = x2, single_track = usable and base or nil }
end

-- "Only 2x bass pedal authored on PART DRUMS" (S.diff_gen_drums_2x_on_1x, opt-in): a song
-- charted only in its double-pedal version, on PART DRUMS. That track
-- is then generated as Drums 2X is - its tiers play the kicks of a single-pedal version made
-- in memory ("Remove 2x kicks"), one tier up. Returns the target, or nil and the error
-- that stops the whole run: a song that also has PART DRUMS_2X has both versions, so the
-- setting is wrong for it. Stopping, not skipping, even in All instruments: one skip line
-- in a long result is easy to miss, and the setting should be put right before anything
-- is written.
local function TwoXOnOneTarget(inst, base, x2)
    if x2 then
        return nil, ('%s found - this song has both drum versions. Untick "Only 2x bass pedal authored on'
            .. ' PART DRUMS" to generate both.'):format(inst.x2.track_name)
    end
    local v = {}
    for k, val in pairs(inst.x2) do v[k] = val end
    v.track_name, v.label, v.on_one = inst.track_name, inst.label .. ' (2x bass pedal on PART DRUMS)', true
    return { inst = v, track = base }
end

-- The tracks a run covers: { { inst, track, tracks }... } plus skip notes for the result.
-- tracks: Pro Keys only, its tier tracks { X, H, M, E } (any may be nil; the run checks
-- the ones it needs).
local function ResolveTargets(inst_key)
    local targets, skipped = {}, {}
    local two_on_one = S.diff_gen_drums_2x_on_1x
    if inst_key == GEN_ALL_KEY then
        -- All instruments: each instrument's default track name, ignoring the combos.
        for _, inst in ipairs(GEN_INSTRUMENTS) do
            local track = FindTrackExact(inst.track_name)
            local x2 = inst.x2 and FindTrackExact(inst.x2.track_name)
            local muted = track and r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1
            -- A muted PART DRUMS_2X is skipped like any muted track.
            if x2 and r.GetMediaTrackInfo_Value(x2, 'B_MUTE') == 1 and not two_on_one then
                skipped[#skipped + 1] = ('%s: %s is muted'):format(inst.x2.label, inst.x2.track_name)
                x2 = nil
            end
            if inst.x2 and two_on_one and (x2 or (track and not muted)) then
                local t, err = TwoXOnOneTarget(inst, track, x2)
                if not t then return nil, nil, err end
                targets[#targets + 1] = t
            elseif x2 then
                AddTargets(inst, track, x2, targets, skipped)
            elseif not track then
                skipped[#skipped + 1] = ('%s: no %s track'):format(inst.label, inst.track_name)
            elseif r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then
                skipped[#skipped + 1] = ('%s: %s is muted'):format(inst.label, inst.track_name)
            else
                local t = { inst = inst, track = track }
                local muted_tier
                if inst.tier_fields then
                    t.tracks = {}
                    for dl in pairs(inst.tier_fields) do
                        t.tracks[dl] = FindTrackExact('PART REAL_KEYS_' .. dl)
                        if t.tracks[dl] and r.GetMediaTrackInfo_Value(t.tracks[dl], 'B_MUTE') == 1 then
                            muted_tier = 'PART REAL_KEYS_' .. dl
                        end
                    end
                end
                if muted_tier then
                    skipped[#skipped + 1] = ('%s: %s is muted'):format(inst.label, muted_tier)
                else
                    targets[#targets + 1] = t
                end
            end
        end
    else
        local inst = GenInstrumentByKey(inst_key)
        -- Generate never writes to a muted track: a track picked for this run that is muted
        -- stops it before anything is read or written.
        local function MutedError(track, name)
            if track and r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then
                local _, tname = r.GetTrackName(track)
                return ('%s is muted - unmute it first (Generate never writes to a muted track).'):format(
                    tname ~= '' and tname or name)
            end
        end
        if inst and inst.tier_fields then
            local tracks = {}
            for dl, field in pairs(inst.tier_fields) do
                local idx = S[field]
                tracks[dl] = idx and idx >= 0 and r.GetTrack(0, idx) or nil
            end
            for dl, tr in pairs(tracks) do
                local err = MutedError(tr, 'PART REAL_KEYS_' .. dl)
                if err then return nil, nil, err end
            end
            targets[1] = { inst = inst, track = tracks.X, tracks = tracks }
        else
            local idx  = inst and S[inst.idx_field]
            local track = idx and idx >= 0 and r.GetTrack(0, idx) or nil
            local x2_idx = inst and inst.x2 and S[inst.x2.idx_field]
            local x2 = x2_idx and x2_idx >= 0 and r.GetTrack(0, x2_idx) or nil
            if x2 == track then x2 = nil end
            if not track and not x2 then
                return nil, nil, ('Select the %s track first.'):format(inst and inst.track_name or '?')
            end
            local err = MutedError(track, inst.track_name) or (inst.x2 and MutedError(x2, inst.x2.track_name))
            if err then return nil, nil, err end
            if inst.x2 and two_on_one then
                local t, err = TwoXOnOneTarget(inst, track, x2)
                if not t then return nil, nil, err end
                targets[1] = t
            else
                AddTargets(inst, track, x2, targets, skipped)
            end
        end
    end
    return targets, skipped
end

-- A tier's track: Pro Keys' own tier track, otherwise the instrument's one track.
local function TierTrack(t, dl)
    if t.tracks then return t.tracks[dl] end
    return t.track
end

-- Planner events from Validate's lane-shift notes ({ s, e, pitch }).
local function ToPlannerShifts(shifts)
    local out = {}
    for _, sh in ipairs(shifts or {}) do
        out[#out + 1] = { qn = SnapQN(r.TimeMap2_timeToQN(0, sh.s)), qn_e = SnapQN(r.TimeMap2_timeToQN(0, sh.e)),
                          pitch = sh.pitch }
    end
    table.sort(out, function(a, b) return a.qn < b.qn end)
    return out
end

-- Expert sustains too short to read as one: under 3/16 at 100+ BPM (DiffSustainTooShort,
-- the rule Validate checks on Expert and Hard). A run from Expert asks once, for every
-- instrument in it, whether to make them plain notes on Expert first.
local SHORT_FIX_KINDS = { gb = true, k5 = true, pk = true }
local EXPERT_PLAIN_QN = 0.25   -- the plain note they become: a 1/16, official charts' commonest
local POPUP_MAX_RANGES = 10    -- bar ranges listed per instrument in the question

-- The job's Expert events (planner events) that are such sustains.
local function ShortExpertSustains(job)
    local found = {}
    for _, ev in ipairs(job.src) do
        if DiffSustainTooShort(ev.qn_e - ev.qn, ev.bpm) then found[#found + 1] = ev end
    end
    return found
end

-- "m5-8, m40" for planner events; max_ranges cuts a long list short with ", ...".
local function BarsOf(evs, max_ranges)
    local bars = {}
    for _, ev in ipairs(evs) do
        local m = MeasureAt(ev.qn)
        if m then bars[#bars + 1] = m end
    end
    local text = MeasureRanges(bars)
    if max_ranges then
        local parts = {}
        for part in text:gmatch('[^,]+') do parts[#parts + 1] = part:match('^%s*(.-)%s*$') end
        if #parts > max_ranges then text = table.concat(parts, ', ', 1, max_ranges) .. ', ...' end
    end
    return text
end

-- Make the Expert notes at those onsets plain: every Expert-range note starting there and
-- held 1/8 or longer ends a 1/16 after its start (a chord's notes alike). Runs inside the
-- run's undo block. Returns the number of notes changed.
local function MakeExpertNotesPlain(inst, track, evs)
    local at = {}
    for _, ev in ipairs(evs) do at[math.floor(ev.qn * 96 + 0.5)] = true end
    local lo, hi
    if inst.kind == 'pk' then lo, hi = 48, 72 else lo = RangeLo(inst, 'X'); hi = lo + 4 end
    local n = 0
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local changed = false
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= lo and pitch <= hi then
                    local qs = r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(take, sppq))
                    local qe = r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(take, eppq))
                    if at[math.floor(qs * 96 + 0.5)] and qe - qs >= GEN5_SUSTAIN_QN - 0.01 then
                        if not changed then
                            r.MarkTrackItemsDirty(track, item)
                            changed = true
                        end
                        local new_e = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap2_QNToTime(0, qs + EXPERT_PLAIN_QN))
                        r.MIDI_SetNote(take, j, sel, muted, sppq, new_e, chan, pitch, vel, true)
                        n = n + 1
                    end
                end
            end
            if changed then r.MIDI_Sort(take) end
        end
    end
    return n
end

-- A copy of answers with one more answer, for the run a popup starts.
local function WithAnswer(answers, key, value)
    local out = {}
    for k, v in pairs(answers) do out[k] = v end
    out[key] = value
    return out
end

-- Generate tiers (an ordered list such as { 'H' } or { 'H', 'M', 'E' }) for one
-- instrument key, or GEN_ALL_KEY for every supported instrument. Each tier is built from
-- the tier above it - the one just generated, when the run made it.
-- force: skip the overwrite confirmation (set when called again from the popup).
-- answers: the user's answers to questions this run asked, so the run that follows the
--   popup does not ask again (nil = not asked yet). expert_short: true / false once asked
--   whether to make Expert's too-short sustains plain notes first. pk_pull_back: true /
--   false once asked whether to shorten Pro Keys Hard's sustains because Hard would equal
--   Expert.
function GenerateDifficulties(inst_key, tiers, force, answers)
    answers = answers or {}
    local targets, skipped, err = ResolveTargets(inst_key)
    if not targets then
        S.status, S.last_result = 'Generate: ' .. err, err
        return
    end
    local sel_s, sel_e = GetTimeSelection()
    -- A time selection covers the notes that START in it: its start inclusive (a note on
    -- the selection's first downbeat is replaced), its end exclusive (a note on the
    -- downbeat where it ends belongs to the next section). The tier readers keep notes up
    -- to 1 ms past the end, as Validate wants; Generate reads to 2 ms before it, so it
    -- never regenerates a note it does not clear - that wrote a second note on top of the
    -- old one. ReplaceNotesBulk clears by the same rule.
    local read_e = sel_e and (sel_e - 0.002)

    -- Seconds per phase, reported on the result's last line (see WRITE_MODE).
    local T = { read = 0, ref = 0, plan = 0, write = 0, validate = 0, finish = 0 }
    local t_start = r.time_precise()
    local clock = t_start
    local function Lap(key)
        local now = r.time_precise()
        T[key] = T[key] + (now - clock)
        clock = now
    end

    -- Read every source before writing anything, and find what would be overwritten.
    local jobs, replaced = {}, {}
    for _, t in ipairs(targets) do
        local src_dl = UPPER[tiers[1]]
        local src_track = TierTrack(t, src_dl)
        -- Every tier this run writes needs a track with a MIDI item (one track for 5-lane).
        local dest, missing = {}, nil
        for _, dl in ipairs(tiers) do
            local tr = TierTrack(t, dl)
            local item, take
            if tr then item, take = FindFirstMIDIItem(tr) end
            if not tr then
                missing = ('%s: no %s track - select it on the Pro Keys sub-tab'):format(t.inst.label, 'PART REAL_KEYS_' .. dl)
                break
            elseif not item then
                missing = ('%s: %s has no MIDI item'):format(t.inst.label,
                    t.tracks and ('PART REAL_KEYS_' .. dl) or t.inst.track_name)
                break
            end
            dest[dl] = { track = tr, item = item, take = take }
        end
        local src, src_shifts = {}, nil
        if src_track then src, src_shifts = ReadTier(t.inst, src_track, src_dl, sel_s, read_e) end
        if not src_track then
            skipped[#skipped + 1] = ('%s: no %s track - select it on the Pro Keys sub-tab'):format(
                t.inst.label, 'PART REAL_KEYS_' .. src_dl)
        elseif #src == 0 then
            skipped[#skipped + 1] = ('%s: %s has no notes to generate from'):format(t.inst.label, DIFF_NAMES[src_dl])
        elseif missing then
            skipped[#skipped + 1] = missing
        else
            local job = { inst = t.inst, track = t.track, tracks = t.tracks, dest = dest,
                          src = GenToPlannerEvents(src, RangeLo(t.inst, src_dl), t.inst.kind == 'pk') }
            if t.inst.kind == 'pk' then
                -- The upper tier's lane shifts over the WHOLE track, even in a time
                -- selection: the window showing at the selection's start was set before it.
                job.src_shifts = ToPlannerShifts((ReadPKTierEvents(src_track)))
                -- Expert, for Validate's cross-difficulty checks of the written tiers.
                if t.tracks.X then job.exp_events = select(1, ReadTier(t.inst, t.tracks.X, 'X', sel_s, read_e)) end
            end
            if t.inst.kind == 'drums' then job.drums_ctx = DrumsContext(dest[tiers[1]].take) end
            -- Drums 2X: each tier takes the kicks of the PART DRUMS tier one step up (read
            -- when the tier is planned, so the run uses the PART DRUMS tiers it has just
            -- written - its target comes first), or of a single-pedal version made in memory.
            if t.inst.double_pedal then job.single_track = t.single_track end
            -- 2x bass pedal on PART DRUMS: an Expert with no second-foot kicks is a
            -- single-pedal chart, so the setting is wrong for it - stop before writing.
            if t.inst.on_one then
                local x = GenToPlannerEvents((ReadTier(t.inst, t.track, 'X', sel_s, read_e)), DRUMS_RANGE.X.lo, false)
                local function Kicks(evs)
                    local n = 0
                    for _, ev in ipairs(evs) do for _, o in ipairs(ev.offs) do if o == 0 then n = n + 1 end end end
                    return n
                end
                if Kicks(GenDrumsSinglePedal(x)) == Kicks(x) then
                    local msg = 'Generate: "Remove 2x kicks" finds no double-bass kicks on PART DRUMS Expert'
                        .. (sel_s and ' in the time selection' or '') .. ', so it is a single-pedal chart.'
                    S.status = msg
                    S.last_result = msg .. '\nUntick "Only 2x bass pedal authored on PART DRUMS" to use the'
                        .. ' single-pedal rules. Nothing was written.'
                    return
                end
            end
            -- Guitar/Bass Hard from Expert: which Expert notes hammer on (automatic or
            -- forced), so Hard can keep them (difficulty_generate_hopo.lua).
            if t.inst.kind == 'gb' and src_dl == 'X' then
                local lo, take = RangeLo(t.inst, 'X'), dest[tiers[1]].take
                Gen5MarkHopos(job.src, MarkerSpans(take, lo + 5, sel_s, sel_e),
                              MarkerSpans(take, lo + 6, sel_s, sel_e))
            end
            jobs[#jobs + 1] = job
            for _, dl in ipairs(tiers) do
                -- Pro Keys: markers alone count too (the second value is a note count for
                -- the 5-lane readers).
                local evs, shifts = ReadTier(t.inst, dest[dl].track, dl, sel_s, read_e)
                if #evs > 0 or (t.inst.kind == 'pk' and #shifts > 0) then
                    replaced[#replaced + 1] = ('%s %s'):format(t.inst.label, DIFF_NAMES[dl])
                end
            end
        end
    end

    if #jobs == 0 then
        S.status = 'Generate: nothing to generate.'
        S.last_result = table.concat(skipped, '\n')
        return
    end

    if #replaced > 0 and not force then
        S.diff_copy_pending = {
            message = 'These already have notes and will be replaced:\n  '
                      .. table.concat(replaced, '\n  ') .. '\n\nGenerate and overwrite them?',
            confirm_label = 'Generate',
            on_confirm = function() GenerateDifficulties(inst_key, tiers, true) end,
        }
        return
    end

    local lines, total_errors = {}, 0
    local scope = sel_s and ' [time selection]' or ''
    Lap('read')

    -- 'auto' (or anything else) leaves busy_drop unset: the planner decides from the tempo
    -- at the first note.
    -- Hard fast runs: 'auto' | 'thin' | 'rewrite' (GEN5_PARAMS.fast_runs_default).
    local fast_runs = S.diff_gen_fast_runs
    local busy = S.diff_gen_busy_drop
    local busy_drop = (busy == 1 or busy == 2) and busy or nil
    -- Guitar leads Bass, Keys and Pro Keys on Hard's busy bars and Medium's rhythm (GuitarRefs).
    local refs = {}
    for _, job in ipairs(jobs) do
        if job.inst.key ~= 'gtr' and job.inst.kind ~= 'drums' then
            refs = GuitarRefs(sel_s, read_e, inst_key == GEN_ALL_KEY, busy_drop, tiers[1], fast_runs)
            break
        end
    end
    Lap('ref')

    -- Expert sustains too short to read as one (ShortExpertSustains). Hard plays them as
    -- plain notes either way; the question is whether Expert itself is fixed. Asked once for
    -- every instrument, before anything is written, so the fix and the tiers stay one undo
    -- step - and before the Pro Keys question below, which plans from the fixed Expert.
    if tiers[1] == 'H' then
        local listed = {}
        for _, job in ipairs(jobs) do
            if SHORT_FIX_KINDS[job.inst.kind] then
                job.short_x = ShortExpertSustains(job)
                if #job.short_x > 0 then
                    listed[#listed + 1] = ('  %s: %d (%s)'):format(job.inst.label, #job.short_x,
                        BarsOf(job.short_x, POPUP_MAX_RANGES))
                end
            end
        end
        if #listed > 0 and answers.expert_short == nil then
            S.diff_copy_pending = {
                message = 'Expert has sustains shorter than a dotted 8th (3/16 note) at 100+ BPM:\n'
                          .. table.concat(listed, '\n') .. '\n\n'
                          .. 'RBN: "Durations should only be authored for notes longer than a dotted\n'
                          .. '8th note for songs over 100bpm." Validate lists them as errors, and\n'
                          .. 'Hard plays them as plain notes either way.\n\n'
                          .. 'Make them plain 1/16 notes on Expert before generating?',
                confirm_label = 'Make them plain notes',
                on_confirm = function()
                    GenerateDifficulties(inst_key, tiers, true, WithAnswer(answers, 'expert_short', true))
                end,
                alt_label = 'Keep them',
                on_alt = function()
                    GenerateDifficulties(inst_key, tiers, true, WithAnswer(answers, 'expert_short', false))
                end,
            }
            return
        end
        -- The planners build from the fixed Expert; the notes are written in the undo block.
        if answers.expert_short then
            for _, job in ipairs(jobs) do
                for _, ev in ipairs(job.short_x or {}) do ev.qn_e = ev.qn + EXPERT_PLAIN_QN end
            end
        end
    end

    -- Pro Keys Hard that would come out as Expert exactly (a simple Expert: the RBN doc has
    -- no rule that Hard must differ, and official Hard sometimes is Expert as it is). Ask
    -- BEFORE writing anything, so Medium and Easy are built from the Hard the user picks
    -- and the run stays one undo step. The same planning runs again below.
    if answers.pk_pull_back == nil and tiers[1] == 'H' then
        for _, job in ipairs(jobs) do
            if job.inst.kind == 'pk' then
                local out = GenPKPlanTier('H', job.src, { busy_drop = busy_drop, busy_ref = refs.H, fast_runs = fast_runs,
                                                          shifts = job.src_shifts })
                if #out > 0 and GenPKSameAsUpper(out, job.src) then
                    S.diff_copy_pending = {
                        message = 'Pro Keys Expert is already easy enough to meet the Hard rules,\n'
                                  .. 'so Hard would be an exact copy of Expert.\n\n'
                                  .. 'Shorten the sustains on Hard so it differs slightly?\n'
                                  .. '(Some official charters reduce a simple Hard this way.)',
                        confirm_label = 'Shorten sustains',
                        on_confirm = function()
                            GenerateDifficulties(inst_key, tiers, true, WithAnswer(answers, 'pk_pull_back', true))
                        end,
                        alt_label = 'Keep as Expert',
                        on_alt = function()
                            GenerateDifficulties(inst_key, tiers, true, WithAnswer(answers, 'pk_pull_back', false))
                        end,
                    }
                    return
                end
            end
        end
    end

    -- This run's Pro Keys tiers, for Keys to follow (ProKeysGuide).
    local pk_generated = {}

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for _, job in ipairs(jobs) do
        local inst = job.inst
        -- Zero-length notes per take, before this job writes to it (RemovedZeroLengthLines).
        local takes, zero_before = {}, {}
        for _, dl in ipairs(tiers) do
            local d = job.dest[dl]
            r.MarkTrackItemsDirty(d.track, d.item)
            if not zero_before[d.take] then
                zero_before[d.take] = ZeroLengthNotes(d.take)
                takes[#takes + 1] = d
            end
        end
        Lap('read')
        local upper, upper_shifts = job.src, job.src_shifts
        -- Each tier's planner events as this run has them (Easy's "and" phrases look at Hard).
        local tier_events = { [UPPER[tiers[1]]] = job.src }
        lines[#lines + 1] = ('%s  (%s)%s'):format(inst.label, inst.track_name, scope)
        -- Expert's too-short sustains: made plain (the user's answer), or kept.
        local short_x = job.short_x or {}
        if #short_x > 0 then
            local n, bars = #short_x, BarsOf(short_x)
            if answers.expert_short then
                local xtrack = inst.kind == 'pk' and job.tracks.X or job.track
                local notes = MakeExpertNotesPlain(inst, xtrack, short_x)
                -- Pro Keys' cross-difficulty checks compare the written tiers with Expert.
                if inst.kind == 'pk' then job.exp_events = select(1, ReadTier(inst, xtrack, 'X', sel_s, read_e)) end
                lines[#lines + 1] = ('  Expert: %d sustain%s shorter than a dotted 8th at 100+ BPM made plain 1/16 notes'
                    .. ' (%d note%s): %s'):format(n, n == 1 and '' or 's', notes, notes == 1 and '' or 's', bars)
            else
                lines[#lines + 1] = ('  Expert: %d sustain%s shorter than a dotted 8th at 100+ BPM kept, as you chose'
                    .. ' (Validate lists them; Hard plays them as plain notes): %s'):format(n, n == 1 and '' or 's', bars)
            end
        end
        for _, dl in ipairs(tiers) do
            local d = job.dest[dl]
            -- No time selection: the whole take, not 0 .. the item's end. An imported item
            -- ends at its last note, and a zero-length chord there sits exactly ON that end,
            -- outside [0, end): it was never cleared and the new chord doubled every pitch
            -- (rb_pro_keys.mid bar 11). whole_take also covers a Pro Keys tier generated
            -- as new in a time selection (below).
            local whole_take = not sel_s
            local clear_s = sel_s or 0
            local clear_e = sel_e or (r.GetMediaItemInfo_Value(d.item, 'D_POSITION')
                                      + r.GetMediaItemInfo_Value(d.item, 'D_LENGTH'))
            local guide = inst.kind == 'k5'
                and ProKeysGuide(dl, sel_s, read_e, inst_key == GEN_ALL_KEY, pk_generated) or nil
            local opts = { guide = guide, busy_drop = busy_drop, fast_runs = fast_runs,
                           busy_ref   = inst.key ~= 'gtr' and dl == 'H' and refs.H or nil,
                           rhythm_ref = inst.key ~= 'gtr' and dl == 'M' and refs.M or nil }
            -- Guitar/Bass/Keys Hard: trill (127) and tremolo (126) lanes, whose marker
            -- velocity says whether Hard plays them as lanes (GenKeepHardLanes).
            if dl == 'H' and (inst.kind == 'gb' or inst.kind == 'k5') then
                local take = d.take
                opts.lanes = MarkerSpans(take, 126)
                for _, sp in ipairs(MarkerSpans(take, 127)) do opts.lanes[#opts.lanes + 1] = sp end
            end
            -- Pro Keys in a time selection. A tier with no notes outside the selection is
            -- generated as a new one: its lane shifts are cleared over the whole item, as a
            -- template's default C2-E3 marker must be (it was kept as "the window this tier
            -- shows" and turned an A2-C4 song's Medium to C2-E3). A tier
            -- with notes elsewhere keeps its markers outside the selection, and Medium/Easy
            -- keep the window set before the selection.
            if inst.kind == 'pk' then
                opts.shifts = upper_shifts
                -- Trill markers the author put on the Hard track (Generate never writes or
                -- clears them): Hard keeps Expert's notes there, at any marker velocity.
                if dl == 'H' then
                    opts.lanes = MarkerSpans(d.take, 127)
                    for _, sp in ipairs(opts.lanes) do sp.hard = true end
                end
                if sel_s then
                    local tier_shifts, tier_notes = ReadPKTierEvents(d.track)
                    local outside = false
                    for _, ev in ipairs(tier_notes) do
                        if ev.s < sel_s - 0.001 or ev.s >= sel_e then outside = true; break end
                    end
                    if not outside then
                        whole_take = true
                        clear_s = 0
                        clear_e = r.GetMediaItemInfo_Value(d.item, 'D_POSITION')
                                  + r.GetMediaItemInfo_Value(d.item, 'D_LENGTH')
                    elseif dl ~= 'H' then
                        -- Medium/Easy have one window: the tier's first marker, wherever it
                        -- is - the notes outside the selection are drawn in it, even when
                        -- the selection covers the marker itself.
                        local first = tier_shifts[1]
                        for _, sh in ipairs(tier_shifts) do if sh.s < first.s then first = sh end end
                        if first and GEN_PK_WINDOWS[first.pitch] then opts.window = first.pitch end
                    end
                end
            end
            -- Keys / Pro Keys Easy: the Hard events, so a lick Medium reduced on the "and"s
            -- goes back to Hard's downbeats (GEN5_PARAMS.and_phrase). Hard from this run, or
            -- read from its track when the run starts below it.
            if dl == 'E' and (inst.kind == 'k5' or inst.kind == 'pk') then
                local hard = tier_events.H
                if not hard then
                    local htrack = inst.kind == 'pk' and (job.tracks or {}).H or job.track
                    if htrack then
                        hard = GenToPlannerEvents((ReadTier(inst, htrack, 'H', sel_s, read_e)), RangeLo(inst, 'H'),
                                               inst.kind == 'pk')
                    end
                end
                opts.and_source = hard
            end
            Lap('read')
            local out, log
            if inst.kind == 'pk' then
                opts.pull_back = dl == 'H' and answers.pk_pull_back or nil
                out, log = GenPKPlanTier(dl, upper, opts)
                pk_generated[dl] = out
            elseif inst.kind == 'drums' then
                opts = { fast_runs = fast_runs, between = S.diff_gen_drums_between, ctx = job.drums_ctx,
                         busy_drop = busy_drop, eighth_hands = S.diff_gen_drums_eighths }
                local plan_in = upper
                if dl == 'H' then
                    opts.keep_cymbals = DrumsKeptCymbals(d.track, job.drums_ctx, tiers, sel_s, sel_e)
                elseif dl == 'M' then
                    -- Fills Hard's rewrite moved off the 8th grid are reduced from Expert's
                    -- notes (ExpertForRewrittenRuns): Expert from this run, else read.
                    opts.expert = tier_events.X
                        or GenToPlannerEvents((ReadTier(inst, job.track, 'X', sel_s, read_e)), RangeLo(inst, 'X'), false)
                end
                local single_kicks
                if inst.double_pedal then
                    local single
                    if job.single_track then
                        single = GenToPlannerEvents((ReadTier(inst, job.single_track, UPPER[dl], sel_s, read_e)),
                                                    RangeLo(inst, UPPER[dl]), false)
                    else
                        job.single_mem = job.single_mem or SinglePedalTiers(job, sel_s, read_e,
                            { fast_runs = fast_runs, between = S.diff_gen_drums_between, busy_drop = busy_drop,
                              eighth_hands = S.diff_gen_drums_eighths })
                        single = job.single_mem[UPPER[dl]]
                    end
                    single_kicks = 0
                    for _, ev in ipairs(single) do
                        for _, o in ipairs(ev.offs) do if o == 0 then single_kicks = single_kicks + 1 end end
                    end
                    if single_kicks > 0 then
                        plan_in = GenDrums2xInput(upper, single)
                        opts.keep_kicks = true
                    end
                end
                out, log = GenDrumsPlanTier(dl, plan_in, opts)
                log.single_kicks, log.single_from = single_kicks, inst.double_pedal and UPPER[dl] or nil
                log.single_mem = inst.double_pedal and not job.single_track
                -- Hard's rewrite may have changed the tom markers: the tiers below are
                -- planned with the new ones (written after the notes, below).
                job.drums_ctx = log.ctx
            else
                out, log = Gen5PlanTier(inst.kind, dl, upper, opts)
            end

            local lo, notes = RangeLo(inst, dl), {}
            for _, ev in ipairs(out) do
                local s = r.TimeMap2_QNToTime(0, ev.qn)
                local e = r.TimeMap2_QNToTime(0, ev.qn_e)
                for _, o in ipairs(ev.offs) do notes[#notes + 1] = { s = s, e = e, pitch = lo + o } end
            end
            -- Markers written with the notes: Guitar/Bass Hard's force-HOPO markers (lo + 5)
            -- where Expert hammered on and Hard would not - they replace Hard's old ones,
            -- which belonged to the notes just replaced; force-strum markers (lo + 6) are left
            -- alone. Pro Keys' lane-shift markers, inside the cleared range only.
            local hopo_spans, marks = {}, {}
            if inst.kind == 'gb' and dl == 'H' then
                hopo_spans = Gen5ForceHopoSpans(out)
                for _, sp in ipairs(hopo_spans) do
                    marks[#marks + 1] = { s = r.TimeMap2_QNToTime(0, sp.qn), e = r.TimeMap2_QNToTime(0, sp.qn_e),
                                          pitch = lo + 5 }
                end
            elseif inst.kind == 'pk' then
                for _, sh in ipairs(log.shifts or {}) do
                    local s = r.TimeMap2_QNToTime(0, sh.qn)
                    if whole_take or (s >= clear_s - 0.001 and s < clear_e) then
                        marks[#marks + 1] = { s = s, e = r.TimeMap2_QNToTime(0, sh.qn_e), pitch = sh.pitch }
                    end
                end
            end
            local all = notes
            if #marks > 0 then
                all = {}
                for _, nt in ipairs(notes) do all[#all + 1] = nt end
                for _, mk in ipairs(marks) do all[#all + 1] = mk end
            end
            Lap('plan')
            local ranges = TierRanges(inst, dl)
            local written_bulk = WRITE_MODE == 'bulk'
                and ReplaceNotesBulk(d.take, not whole_take and clear_s or nil, clear_e, ranges, all, 100)
            if not written_bulk then
                if WRITE_MODE ~= 'per_note' then r.MIDI_DisableSort(d.take) end
                for _, rg in ipairs(ranges) do
                    ClearNotesInRange(d.take, whole_take and -math.huge or clear_s, whole_take and math.huge or clear_e,
                                      rg[1], rg[2])
                end
                if #all > 0 then InsertNotes(d.take, all, 100) end
            end
            if inst.kind == 'drums' and #(log.tom_markers or {}) > 0 then WriteTomMarkers(d.take, log.tom_markers) end
            -- Sorted before anything reads the take back.
            r.MIDI_Sort(d.take)
            Lap('write')

            -- Validate what was written, with Validate's own checks.
            local written, written_shifts = ReadTier(inst, d.track, dl, sel_s, read_e)
            local errors, listed = 0, {}
            local checks = CheckTier(inst, d.track, dl, written, sel_s, read_e,
                                     { shifts = written_shifts, exp_events = job.exp_events })
            local marker_issues = 0
            for _, cat in ipairs(checks) do
                if cat.marker then
                    -- About a marker the tier shares with Expert (a Drums roll lane), not
                    -- the notes Generate wrote: noted once below, not counted.
                    marker_issues = marker_issues + #cat.issues
                elseif not cat.advisory then
                    for _, rec in ipairs(cat.issues) do
                        if not rec.advisory then
                            errors = errors + 1
                            if #listed < MAX_LISTED then listed[#listed + 1] = '      ' .. rec.msg end
                        end
                    end
                end
            end
            if marker_issues > 0 and dl == tiers[1] then
                lines[#lines + 1] = ('    %d issue%s with the roll lane markers themselves (start off the grid, or'
                    .. ' a velocity Hard cannot use) - Validate lists them; Generate does not change markers'):format(
                    marker_issues, marker_issues == 1 and '' or 's')
            end
            total_errors = total_errors + errors
            Lap('validate')

            local parts = {}
            if log.chords_reduced > 0 then parts[#parts + 1] = ('%d chords reduced'):format(log.chords_reduced) end
            if log.color_fallback then
                parts[#parts + 1] = ('%d moved down a lane (Hard barely thinned, so eased by color)'):format(log.recolored)
            elseif log.recolored > 0 then
                parts[#parts + 1] = ('%d recolored'):format(log.recolored)
            end
            if log.shortened > 0 then parts[#parts + 1] = ('%d sustains shortened'):format(log.shortened) end
            if log.cut > 0 then parts[#parts + 1] = ('%d cut back to a plain note'):format(log.cut) end
            -- Onsets AND notes: a chord losing a note, or a kick dropped under a hi-hat,
            -- keeps the onset, so the onset count alone hides most of a reduction (Drums Hard
            -- kept 829 of 833 onsets but 1273 of 1569 notes).
            local function CountNotes(evs)
                local n = 0
                for _, ev in ipairs(evs) do n = n + #ev.offs end
                return n
            end
            local n_up, n_out = CountNotes(upper), CountNotes(out)
            lines[#lines + 1] = ('  %s: kept %d of %d onsets (%d%%), %d of %d notes (%d%%) from %s%s'):format(
                DIFF_NAMES[dl], log.kept, log.upper, KeptPercent(log.kept, log.upper),
                n_out, n_up, KeptPercent(n_out, n_up), DIFF_NAMES[UPPER[dl]],
                log.guided and (', following PART REAL_KEYS_' .. dl) or '')
            if #parts > 0 then lines[#lines + 1] = '    ' .. table.concat(parts, ', ') end
            if (log.hard_lanes or 0) > 0 and inst.kind == 'pk' then
                lines[#lines + 1] = ('    %d trill marker%s on PART REAL_KEYS_H: Expert\'s notes kept there as they are'):format(
                    log.hard_lanes, log.hard_lanes == 1 and '' or 's')
            elseif (log.hard_lanes or 0) > 0 then
                lines[#lines + 1] = ('    %d %s lane%s marked for Hard (marker velocity 41-50): Expert\'s notes kept'
                    .. ' there as they are'):format(log.hard_lanes, inst.kind == 'drums' and 'roll' or 'trill/tremolo',
                    log.hard_lanes == 1 and '' or 's')
            end
            if inst.kind == 'drums' then
                for _, l in ipairs(DrumsLines(dl, log, opts)) do lines[#lines + 1] = l end
            end
            -- Keys plays Pro Keys' onsets exactly; a Pro Keys note with no Keys note within a
            -- 32nd means the two Expert charts differ there (they are meant to match).
            if log.guided and log.guide_missed and #log.guide_missed > 0 then
                local bars = {}
                for _, q in ipairs(log.guide_missed) do bars[#bars + 1] = MeasureAt(q) end
                lines[#lines + 1] = ('    %d PART REAL_KEYS_%s note%s with no Keys note to follow (%s): Keys and'
                    .. ' Pro Keys should have the same notes at the same positions - check the Expert charts there'):format(
                    #log.guide_missed, dl, #log.guide_missed == 1 and '' or 's', MeasureRanges(bars))
            end
            -- The "Hard equals Expert" question: what was asked, what the user chose, what
            -- was done.
            if inst.kind == 'pk' and dl == 'H' and answers.pk_pull_back ~= nil then
                lines[#lines + 1] = '    Hard would have been an exact copy of Expert (Expert is already simple).'
                if answers.pk_pull_back then
                    lines[#lines + 1] = ('    You chose to shorten sustains: %d pulled back%s.'):format(log.pulled or 0,
                        (log.pull_cut or 0) > 0 and (', %d of them to a 1/16 note'):format(log.pull_cut) or '')
                else
                    lines[#lines + 1] = '    You chose to keep it as Expert (Validate lists this as an advisory).'
                end
            end
            if inst.kind == 'pk' then
                if dl == 'H' and log.shift_added then
                    lines[#lines + 1] = ('    %s has no lane shift: added one before the first note (%s)'):format(
                        DIFF_NAMES[UPPER[dl]], PK_WINDOW_NAMES[log.shifts[1].pitch] or '?')
                elseif dl == 'H' then
                    lines[#lines + 1] = ('    %d lane shift%s kept from %s%s'):format(#(log.shifts or {}),
                        #(log.shifts or {}) == 1 and '' or 's', DIFF_NAMES[UPPER[dl]],
                        log.shifts_dropped > 0 and (', %d no longer needed and left out'):format(log.shifts_dropped) or '')
                elseif log.window then
                    lines[#lines + 1] = ('    one range for the whole tier: %s%s%s'):format(PK_WINDOW_NAMES[log.window] or '?',
                        opts.window and ' (the range this tier already shows)' or '',
                        log.folded > 0 and (', %d note%s moved by octaves to fit'):format(
                            log.folded, log.folded == 1 and '' or 's') or '')
                end
            end
            if dl == 'H' and inst.kind ~= 'drums' then
                local why = log.busy_auto
                    and ('Auto: song starts at %.0f BPM, %s %d'):format(log.first_bpm or 0,
                        (log.first_bpm or 0) > GEN5_PARAMS.fast_8ths_bpm and 'over' or 'not over',
                        GEN5_PARAMS.fast_8ths_bpm)
                    or 'your choice'
                lines[#lines + 1] = ('    busy bars of 8ths: drop %d per bar, less any 8th rests already there (%s)'):format(
                    log.busy_drop, why)
                if log.fast_runs then
                    local what = ({ auto = 'rewritten one grid slower above 160 BPM, thinned below',
                                    thin = 'thinned to the Hard grid (never rewritten)',
                                    rewrite = 'rewritten one grid slower (at or below 160 BPM: runs of half a bar or more)' })[log.fast_runs]
                    if what then lines[#lines + 1] = '    fast runs: ' .. what end
                end
                for _, l in ipairs(RetimedLines(log.retimed_bars)) do lines[#lines + 1] = l end
                for _, l in ipairs(HopoLines(hopo_spans)) do lines[#lines + 1] = l end
                if (log.busy_followed or 0) > 0 then
                    lines[#lines + 1] = ('    %d busy bar%s in the same rhythm as Guitar: dropped the same notes'):format(
                        log.busy_followed, log.busy_followed == 1 and '' or 's')
                end
            end
            -- Phrases reduced on the "and" grid (Medium) and the downbeats Easy took back.
            if log.and_phrases and #log.and_phrases > 0 then
                local bars = {}
                for _, sp in ipairs(log.and_phrases) do
                    local a, b = MeasureAt(sp.qn_s), MeasureAt(sp.qn_e)
                    if a then for m = a, b or a do bars[#bars + 1] = m end end
                end
                local n = #log.and_phrases
                if dl == 'M' then
                    lines[#lines + 1] = ('    %d phrase%s starting on an "and" reduced on the "and"s, so the line keeps moving (%s)'):format(
                        n, n == 1 and '' or 's', MeasureRanges(bars))
                elseif dl == 'E' then
                    lines[#lines + 1] = ("    in %d such phrase%s Easy keeps Hard's downbeats (%s)"):format(
                        n, n == 1 and '' or 's', MeasureRanges(bars))
                end
            end
            -- Keys/Pro Keys overlapping gems (GenPlanOverlaps) and rolled chords (GenMergeRolls).
            if inst.kind == 'k5' or inst.kind == 'pk' then
                local held = 0
                for i, ev in ipairs(out) do
                    local nx = out[i + 1]
                    if nx and ev.qn_e > nx.qn + GEN5_EPS then held = held + 1 end
                end
                local ov = log.overlaps or {}
                if held > 0 then
                    lines[#lines + 1] = ('    %d note%s held over later notes, as Expert does%s'):format(held, held == 1 and '' or 's',
                        (ov.chord_notes or 0) + (ov.trimmed or 0) > 0
                            and (' (to keep the overlap limit: %d chord note%s left out, %d held note%s ended earlier)'):format(
                                ov.chord_notes, ov.chord_notes == 1 and '' or 's', ov.trimmed, ov.trimmed == 1 and '' or 's')
                            or '')
                end
                if (log.rolls or 0) > 0 then
                    lines[#lines + 1] = ('    %d rolled chord%s played as one chord on the beat'):format(log.rolls, log.rolls == 1 and '' or 's')
                end
            end
            if dl == 'M' then
                if (log.filled or 0) > 0 then
                    lines[#lines + 1] = ('    %d note%s kept so busy bars keep a note per beat'):format(
                        log.filled, log.filled == 1 and '' or 's')
                end
                if (log.rhythm_followed or 0) > 0 then
                    lines[#lines + 1] = ('    %d bar%s in the same rhythm as Guitar: kept the same notes'):format(
                        log.rhythm_followed, log.rhythm_followed == 1 and '' or 's')
                end
            end
            lines[#lines + 1] = errors == 0 and '    Validate: no errors'
                or ('    Validate: %d error%s left to fix by hand:'):format(errors, errors == 1 and '' or 's')
            for _, l in ipairs(listed) do lines[#lines + 1] = l end
            if errors > #listed then
                lines[#lines + 1] = ('      ... and %d more (run Validate for the full list)'):format(errors - #listed)
            end

            upper, upper_shifts = out, log.shifts   -- the next tier is built from this one
            tier_events[dl] = out
        end
        -- Zero-length notes REAPER dropped from each take this job wrote, outside the
        -- tiers the job regenerated.
        for _, d in ipairs(takes) do
            local replaced_ranges = {}
            for _, dl in ipairs(tiers) do
                if job.dest[dl].take == d.take then
                    for _, rg in ipairs(TierRanges(inst, dl)) do replaced_ranges[#replaced_ranges + 1] = rg end
                end
            end
            for _, l in ipairs(RemovedZeroLengthLines(d.take, zero_before[d.take], replaced_ranges)) do
                lines[#lines + 1] = l
            end
        end
        lines[#lines + 1] = ''
        Lap('validate')
    end
    local tier_str = table.concat(tiers, '-')
    local what = inst_key == GEN_ALL_KEY and 'all instruments' or GenInstrumentByKey(inst_key).label
    r.Undo_EndBlock2(0, ('Generate %s %s'):format(what, tier_str), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    if #skipped > 0 then
        lines[#lines + 1] = 'Skipped:'
        for _, s in ipairs(skipped) do lines[#lines + 1] = '  ' .. s end
    end
    S.status = ('Generate %s %s: done, %s.'):format(what, tier_str,
        total_errors == 0 and 'no Validate errors' or (total_errors .. ' Validate errors left'))
    Lap('finish')   -- closing the undo block and refreshing the arrange view
    -- The phases only when the run was slow (SLOW_RUN_S): a slow run's report then says
    -- where the time went, and a normal one stays a single short line.
    local took = r.time_precise() - t_start
    lines[#lines + 1] = took < SLOW_RUN_S and ('Done in %.1f s'):format(took)
        or ('Done in %.1f s - read %.1f, guitar reference %.1f, plan %.1f, write %.1f, validate %.1f, undo %.1f'):format(
            took, T.read, T.ref, T.plan, T.write, T.validate, T.finish)
    S.last_result = table.concat(lines, '\n')
end
