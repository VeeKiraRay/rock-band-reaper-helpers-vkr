-- Difficulty > Generate: build Hard, Medium and Easy automatically from the tier above.
--
-- The REAPER side of the generator. Reads tiers off the instrument tracks, hands them to
-- the pure planner (difficulty_generate_5lane.lua), writes the result back, and re-runs
-- Validate's own checks on what it wrote. One undo block covers a whole run, every
-- instrument and tier included.
--
-- Requires (globals): S, r, GetTimeSelection, FindFirstMIDIItem, ClearNotesInRange,
--   InsertNotes, FindTrackExact (difficulty_read.lua), Gen5PlanTier,
--   GB_RANGE / K5_RANGE, ReadGBTierEvents / ReadK5TierEvents, CollectGBChecks /
--   CollectK5Checks, ReadProKeysEvents (actions_difficulty_5k.lua), Gen5MarkHopos /
--   Gen5ForceHopoSpans (difficulty_generate_hopo.lua).

-- The instruments Generate supports, in dropdown order. Adding one (Drums, Pro Keys) is
-- one entry here plus its planner. idx_field is the track field the instrument's own
-- Difficulty sub-tab uses, so the selection is shared rather than duplicated.
GEN_INSTRUMENTS = {
    { key = 'gtr',  label = 'Guitar', track_name = 'PART GUITAR', idx_field = 'diff_gtr_idx',  kind = 'gb' },
    { key = 'bass', label = 'Bass',   track_name = 'PART BASS',   idx_field = 'diff_bass_idx', kind = 'gb' },
    { key = 'keys', label = 'Keys',   track_name = 'PART KEYS',   idx_field = 'diff_5k_idx',   kind = 'k5' },
}
GEN_ALL_KEY = 'all'

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }
local UPPER      = { H = 'X', M = 'H', E = 'M' }
local MAX_LISTED = 8   -- unresolved Validate lines listed per tier in the result

function GenInstrumentByKey(key)
    for _, inst in ipairs(GEN_INSTRUMENTS) do
        if inst.key == key then return inst end
    end
    return nil
end

local function RangeLo(inst, dl)
    return (inst.kind == 'gb' and GB_RANGE or K5_RANGE)[dl].lo
end

local function ReadTier(inst, track, dl, sel_s, sel_e)
    if inst.kind == 'gb' then return ReadGBTierEvents(track, dl, sel_s, sel_e) end
    return ReadK5TierEvents(track, dl, sel_s, sel_e)
end

local function CheckTier(inst, track, dl, events, sel_s, sel_e)
    if inst.kind == 'gb' then return CollectGBChecks(dl, events, track, sel_s, sel_e) end
    return CollectK5Checks(dl, events)
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

local function ToPlannerEvents(events, lo)
    local out = {}
    for _, ev in ipairs(events) do
        if ev.e - ev.s < ZERO_LEN_S then goto next_ev end
        local qn = SnapQN(r.TimeMap2_timeToQN(0, ev.s))
        -- Bar start and end in quarter notes, so time signature changes are honoured.
        local _, bar_s, bar_e = r.TimeMap_QNToMeasures(0, qn)
        bar_s, bar_e = SnapQN(bar_s), SnapQN(bar_e)
        local offs = {}
        for i, p in ipairs(ev.pitches) do offs[i] = p - lo end
        out[#out + 1] = {
            qn     = qn,
            qn_e   = SnapQN(r.TimeMap2_timeToQN(0, ev.e)),
            offs   = offs,
            bpm    = select(1, r.TimeMap_GetDividedBpmAtTime(ev.s)) or 120,
            bar_qn  = qn - bar_s,
            bar_len = bar_e - bar_s,
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
local function ProKeysGuide(dl, sel_s, sel_e, by_name)
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

-- One marker pitch's notes in a take as spans { { qn, qn_e }... }, inside [sel_s, sel_e]
-- (seconds) when given.
local function MarkerSpans(take, pitch, sel_s, sel_e)
    local spans = {}
    local _, n = r.MIDI_CountEvts(take)
    for i = 0, n - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p == pitch then
            local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            if not sel_s or (s >= sel_s - 0.001 and s < sel_e) then
                spans[#spans + 1] = { qn = SnapQN(r.TimeMap2_timeToQN(0, s)),
                                      qn_e = SnapQN(r.TimeMap2_timeToQN(0, r.MIDI_GetProjTimeFromPPQPos(take, eppq))) }
            end
        end
    end
    return spans
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
local function GuitarRefs(sel_s, sel_e, by_name, busy_drop, first_tier)
    local refs = {}
    if first_tier == 'E' then return refs end
    local inst = GenInstrumentByKey('gtr')
    local idx = not by_name and S[inst.idx_field] or nil
    local track = idx and idx >= 0 and r.GetTrack(0, idx) or FindTrackExact(inst.track_name)
    if not track then return refs end
    local src_dl = first_tier == 'H' and 'X' or 'H'
    local src = ReadTier(inst, track, src_dl, sel_s, sel_e)
    if #src == 0 then return refs end
    local upper = ToPlannerEvents(src, RangeLo(inst, src_dl))
    if first_tier == 'H' then
        local log
        upper, log = Gen5PlanTier('gb', 'H', upper, { busy_drop = busy_drop })
        refs.H = log.busy_bars
    end
    local _, mlog = Gen5PlanTier('gb', 'M', upper)
    refs.M = mlog.rhythm_bars
    return refs
end

-- The tracks a run covers: { { inst, track }... } plus skip notes for the result.
local function ResolveTargets(inst_key)
    local targets, skipped = {}, {}
    if inst_key == GEN_ALL_KEY then
        -- All instruments: each instrument's default track name, ignoring the combos.
        for _, inst in ipairs(GEN_INSTRUMENTS) do
            local track = FindTrackExact(inst.track_name)
            if not track then
                skipped[#skipped + 1] = ('%s: no %s track'):format(inst.label, inst.track_name)
            elseif r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then
                skipped[#skipped + 1] = ('%s: %s is muted'):format(inst.label, inst.track_name)
            else
                targets[#targets + 1] = { inst = inst, track = track }
            end
        end
    else
        local inst = GenInstrumentByKey(inst_key)
        local idx  = inst and S[inst.idx_field]
        local track = idx and idx >= 0 and r.GetTrack(0, idx) or nil
        if not track then
            return nil, nil, ('Select the %s track first.'):format(inst and inst.track_name or '?')
        end
        targets[1] = { inst = inst, track = track }
    end
    return targets, skipped
end

-- Generate tiers (an ordered list such as { 'H' } or { 'H', 'M', 'E' }) for one
-- instrument key, or GEN_ALL_KEY for every supported instrument. Each tier is built from
-- the tier above it - the one just generated, when the run made it.
-- force: skip the overwrite confirmation (set when called again from the popup).
function GenerateDifficulties(inst_key, tiers, force)
    local targets, skipped, err = ResolveTargets(inst_key)
    if not targets then
        S.status, S.last_result = 'Generate: ' .. err, err
        return
    end
    local sel_s, sel_e = GetTimeSelection()

    -- Read every source before writing anything, and find what would be overwritten.
    local jobs, replaced = {}, {}
    for _, t in ipairs(targets) do
        local src_dl = UPPER[tiers[1]]
        local src = ReadTier(t.inst, t.track, src_dl, sel_s, sel_e)
        if #src == 0 then
            skipped[#skipped + 1] = ('%s: %s has no notes to generate from'):format(t.inst.label, DIFF_NAMES[src_dl])
        else
            local item, take = FindFirstMIDIItem(t.track)
            if not item then
                skipped[#skipped + 1] = ('%s: %s has no MIDI item'):format(t.inst.label, t.inst.track_name)
            else
                local job = { inst = t.inst, track = t.track, item = item, take = take,
                              src = ToPlannerEvents(src, RangeLo(t.inst, src_dl)) }
                -- Guitar/Bass Hard from Expert: which Expert notes hammer on (automatic or
                -- forced), so Hard can keep them (difficulty_generate_hopo.lua).
                if t.inst.kind == 'gb' and src_dl == 'X' then
                    local lo = RangeLo(t.inst, 'X')
                    Gen5MarkHopos(job.src, MarkerSpans(take, lo + 5, sel_s, sel_e),
                                  MarkerSpans(take, lo + 6, sel_s, sel_e))
                end
                jobs[#jobs + 1] = job
                for _, dl in ipairs(tiers) do
                    if #ReadTier(t.inst, t.track, dl, sel_s, sel_e) > 0 then
                        replaced[#replaced + 1] = ('%s %s'):format(t.inst.label, DIFF_NAMES[dl])
                    end
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

    -- 'auto' (or anything else) leaves busy_drop unset: the planner decides from the tempo
    -- at the first note.
    local busy = S.diff_gen_busy_drop
    local busy_drop = (busy == 1 or busy == 2) and busy or nil
    -- Guitar leads Bass and Keys on Hard's busy bars and Medium's rhythm (GuitarRefs).
    local refs = {}
    for _, job in ipairs(jobs) do
        if job.inst.key ~= 'gtr' then
            refs = GuitarRefs(sel_s, sel_e, inst_key == GEN_ALL_KEY, busy_drop, tiers[1])
            break
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for _, job in ipairs(jobs) do
        local inst = job.inst
        r.MarkTrackItemsDirty(job.track, job.item)
        local zero_before = ZeroLengthNotes(job.take)   -- see RemovedZeroLengthLines
        local clear_s = sel_s or 0
        local clear_e = sel_e or (r.GetMediaItemInfo_Value(job.item, 'D_POSITION')
                                  + r.GetMediaItemInfo_Value(job.item, 'D_LENGTH'))
        local upper = job.src
        lines[#lines + 1] = ('%s  (%s)%s'):format(inst.label, inst.track_name, scope)
        for _, dl in ipairs(tiers) do
            local guide = inst.kind == 'k5'
                and ProKeysGuide(dl, sel_s, sel_e, inst_key == GEN_ALL_KEY) or nil
            local out, log = Gen5PlanTier(inst.kind, dl, upper, {
                guide = guide, busy_drop = busy_drop,
                busy_ref   = inst.key ~= 'gtr' and dl == 'H' and refs.H or nil,
                rhythm_ref = inst.key ~= 'gtr' and dl == 'M' and refs.M or nil })

            local lo, notes = RangeLo(inst, dl), {}
            for _, ev in ipairs(out) do
                local s = r.TimeMap2_QNToTime(0, ev.qn)
                local e = r.TimeMap2_QNToTime(0, ev.qn_e)
                for _, o in ipairs(ev.offs) do notes[#notes + 1] = { s = s, e = e, pitch = lo + o } end
            end
            ClearNotesInRange(job.take, clear_s, clear_e, lo, lo + 4)
            InsertNotes(job.take, notes, 100)
            -- Guitar/Bass Hard: force-HOPO markers (lo + 5) where Expert hammered on and Hard
            -- would not. They replace Hard's old ones, which belonged to the notes just
            -- replaced. Force-strum markers (lo + 6) are left alone.
            local hopo_spans = {}
            if inst.kind == 'gb' and dl == 'H' then
                hopo_spans = Gen5ForceHopoSpans(out)
                local marks = {}
                for _, sp in ipairs(hopo_spans) do
                    marks[#marks + 1] = { s = r.TimeMap2_QNToTime(0, sp.qn), e = r.TimeMap2_QNToTime(0, sp.qn_e),
                                          pitch = lo + 5 }
                end
                ClearNotesInRange(job.take, clear_s, clear_e, lo + 5, lo + 5)
                if #marks > 0 then InsertNotes(job.take, marks, 100) end
            end

            -- Validate what was written, with Validate's own checks.
            local written = ReadTier(inst, job.track, dl, sel_s, sel_e)
            local errors, listed = 0, {}
            for _, cat in ipairs(CheckTier(inst, job.track, dl, written, sel_s, sel_e)) do
                if not cat.advisory then
                    for _, rec in ipairs(cat.issues) do
                        if not rec.advisory then
                            errors = errors + 1
                            if #listed < MAX_LISTED then listed[#listed + 1] = '      ' .. rec.msg end
                        end
                    end
                end
            end
            total_errors = total_errors + errors

            local parts = {}
            if log.chords_reduced > 0 then parts[#parts + 1] = ('%d chords reduced'):format(log.chords_reduced) end
            if log.color_fallback then
                parts[#parts + 1] = ('%d moved down a lane (Hard barely thinned, so eased by color)'):format(log.recolored)
            elseif log.recolored > 0 then
                parts[#parts + 1] = ('%d recolored'):format(log.recolored)
            end
            if log.shortened > 0 then parts[#parts + 1] = ('%d sustains shortened'):format(log.shortened) end
            if log.cut > 0 then parts[#parts + 1] = ('%d cut back to a plain note'):format(log.cut) end
            lines[#lines + 1] = ('  %s: kept %d of %d onsets from %s (%.0f%%)%s'):format(
                DIFF_NAMES[dl], log.kept, log.upper, DIFF_NAMES[UPPER[dl]],
                100 * log.kept / math.max(1, log.upper),
                log.guided and (', following PART REAL_KEYS_' .. dl) or '')
            if #parts > 0 then lines[#lines + 1] = '    ' .. table.concat(parts, ', ') end
            if dl == 'H' then
                local why = log.busy_auto
                    and ('Auto: song starts at %.0f BPM, %s %d'):format(log.first_bpm or 0,
                        (log.first_bpm or 0) > GEN5_PARAMS.fast_8ths_bpm and 'over' or 'not over',
                        GEN5_PARAMS.fast_8ths_bpm)
                    or 'your choice'
                lines[#lines + 1] = ('    busy bars of 8ths: drop %d per bar, less any 8th rests already there (%s)'):format(
                    log.busy_drop, why)
                for _, l in ipairs(RetimedLines(log.retimed_bars)) do lines[#lines + 1] = l end
                for _, l in ipairs(HopoLines(hopo_spans)) do lines[#lines + 1] = l end
                if (log.busy_followed or 0) > 0 then
                    lines[#lines + 1] = ('    %d busy bar%s in the same rhythm as Guitar: dropped the same notes'):format(
                        log.busy_followed, log.busy_followed == 1 and '' or 's')
                end
            elseif dl == 'M' then
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

            upper = out   -- the next tier is built from this one
        end
        local replaced = {}
        for _, dl in ipairs(tiers) do
            local lo = RangeLo(inst, dl)
            -- Guitar/Bass Hard also replaces its force-HOPO markers (lo + 5).
            replaced[#replaced + 1] = { lo, (inst.kind == 'gb' and dl == 'H') and lo + 5 or lo + 4 }
        end
        for _, l in ipairs(RemovedZeroLengthLines(job.take, zero_before, replaced)) do lines[#lines + 1] = l end
        lines[#lines + 1] = ''
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
    S.last_result = table.concat(lines, '\n')
end
