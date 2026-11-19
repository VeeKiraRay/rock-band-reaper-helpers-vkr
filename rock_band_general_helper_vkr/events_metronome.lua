-- Events > Metronome: the practice-mode drum clicks on the EVENTS track.
--
-- EVENTS notes 24 / 25 / 26 are the game's practice metronome (kick / snare / hi-hat
-- sounds). The game reads them only in practice and trainer modes, and plays them when
-- the player practises any part except drums. Official RB3 DLC songs all have them; Magma
-- keeps them.
--
-- What the official charts do (586 RB3 DLC songs, measured note by note):
--   24 = PART DRUMS Medium's kicks (97.6% of them clicked; the best fit in 500 of 583).
--   25 = Medium's snares (Easy and Medium snares agree in half the sections; where they
--        differ the clicks follow Medium 700 sections to Easy's 176). Harmonix thinned
--        busy snares by hand in some sections - not copied here.
--   26 = a steady pulse from the song's start to [end], plus a click on every Medium hit
--        (triplets and other off-grid hits included). The pulse keeps its grid whatever
--        the music plays: through drum rests, and at 8ths or 16ths in 99% of the bars
--        where the drums play only quarter notes. 8ths, or 16ths in slow songs: a median
--        tempo under 95 BPM picks 16ths in 502 of 583 songs (drum busyness predicts it
--        worse). Mid-song the pulse does not pause where the band stops (it keeps
--        clicking through 408 of 445 band-silent stretches).
--   The intro: most official songs open with a drummer's count-in on 26 instead of the
--        pulse - "one . two . one two three four" (clicks at 0 2 4 5 6 7 QN before a band
--        starting at bar 3, in 252 songs exactly and about 330 with variants) - and the
--        steady pulse starts with the band; about 100 run the pulse from the start. The
--        count-in is in the song audio (the template's COUNT IN track), not in the MIDI,
--        so the Intro choice reads it from there: each COUNT IN clip's start, snapped to
--        the nearest 8th. Without COUNT IN audio it counts in to the bar line nearest the
--        band's first note (a pickup counts in to the bar after it), which matches 63% of
--        the official intros exactly (16% for a pulse from the start).
--
-- MetronomePlan is pure (quarter notes in, notes out) so the offline evaluation in
-- dev/tools/metronome_eval_offline.lua runs the same rules over the official charts.
-- GenerateMetronome is the REAPER action; it touches r only when called.

METRONOME_PARAMS = {
    kick  = 24,
    snare = 25,
    hat   = 26,
    auto_16th_below_bpm = 95,     -- Auto pulse: 16ths when the median tempo is below this
    len_qn   = 100 / 480,         -- official notes are mostly 100 ticks at 480 PPQ
    vel      = 100,               -- the commonest official velocity
    dedup_qn = 1 / 32,            -- a Medium hit this close to a pulse step shares its click
    -- The chart count-in, before the bar line nearest the band's first note:
    count_in_qn = { -8, -6, -4, -3, -2, -1 },   -- "one . two . one two three four"
    count_in_snap_qn = 0.5,       -- COUNT IN clip starts snap to the nearest 8th
    count_in_lead_qn = 1,         -- the pulse picks up one beat after the last count-in click
}

METRONOME_PULSES = { 'auto', '8th', '16th' }       -- S.metronome_pulse 0 / 1 / 2
METRONOME_INTROS = { 'audio', 'chart', 'steady' }   -- S.metronome_intro 0 / 1 / 2

local EPS = 1e-6

local function SortedQN(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    table.sort(out)
    return out
end

-- The pulse for this song: 'auto' resolves by the median tempo.
function MetronomePulseFor(pulse, median_bpm, P)
    P = P or METRONOME_PARAMS
    if pulse == '8th' or pulse == '16th' then return pulse, 'picked' end
    if median_bpm and median_bpm < P.auto_16th_below_bpm then return '16th', 'auto' end
    return '8th', 'auto'
end

-- Snap a QN position to the nearest multiple of `grid` counted from `origin`.
function MetronomeSnap(qn, grid, origin)
    origin = origin or 0
    return origin + math.floor((qn - origin) / grid + 0.5) * grid
end

-- The count-in clicks and where the steady pulse starts, for the chosen intro.
-- Returns clicks (QN), anchor (nil = the pulse runs from measure 1) and the intro used.
local function IntroPlan(input, intro, P)
    local f = input.first_note_qn
    if intro == 'audio' then
        local clicks = SortedQN(input.count_in_clicks)
        if #clicks > 0 then
            local anchor = clicks[#clicks] + P.count_in_lead_qn
            if f and f < anchor then anchor = f end
            local before = {}
            for _, q in ipairs(clicks) do if q < anchor - EPS then before[#before + 1] = q end end
            return before, anchor, 'audio'
        end
        intro = 'chart'
    end
    if intro == 'chart' and f then
        local bar, nxt = input.first_bar_qn, input.next_bar_qn
        local at = f
        if bar then
            at = (nxt and nxt - f <= f - bar + EPS) and nxt or bar   -- a tie counts in to the later bar
        end
        local clicks = {}
        for _, d in ipairs(P.count_in_qn) do
            local q = at + d
            if q < f - EPS then clicks[#clicks + 1] = q end
        end
        return clicks, math.min(at, f), 'chart'
    end
    return {}, nil, 'steady'
end

-- MetronomePlan(input, opts):
-- input: { start_qn (song start, measure 1), end_qn ([end]), median_bpm,
--          kicks, snares, hits (PART DRUMS Medium onsets, QN; hits = every Medium gem),
--          first_note_qn, first_bar_qn, next_bar_qn (the band's first note, the bar
--          line at or before it and the one after),
--          count_in_clicks (COUNT IN clip starts in QN, already snapped; may be empty) }
-- opts:  { pulse = 'auto' | '8th' | '16th', intro = 'audio' | 'chart' | 'steady',
--          range_s_qn, range_e_qn, params }
--   intro 'audio': the count-in clicks, falling back to 'chart' when there are none;
--   'chart': the measured count-in from the band's first note, falling back to
--   'steady' without one; 'steady': the pulse from measure 1.
-- Returns notes = { {qn, pitch} ... } sorted by qn then pitch, and info.
function MetronomePlan(input, opts)
    opts = opts or {}
    local P = opts.params or METRONOME_PARAMS
    local start_qn = input.start_qn or 0
    local end_qn = input.end_qn
    local lo = opts.range_s_qn or start_qn
    local hi = opts.range_e_qn or end_qn
    -- Notes that start in [lo, hi), and never on or after [end].
    local function InRange(q)
        return q >= start_qn - EPS and q >= lo - EPS and q < end_qn - EPS and q < hi - EPS
    end

    local pulse, why = MetronomePulseFor(opts.pulse or 'auto', input.median_bpm, P)
    local step = pulse == '16th' and 0.25 or 0.5

    local notes = {}
    local counts = { kick = 0, snare = 0, hat = 0 }
    for _, q in ipairs(SortedQN(input.kicks)) do
        if InRange(q) then notes[#notes + 1] = { qn = q, pitch = P.kick } counts.kick = counts.kick + 1 end
    end
    for _, q in ipairs(SortedQN(input.snares)) do
        if InRange(q) then notes[#notes + 1] = { qn = q, pitch = P.snare } counts.snare = counts.snare + 1 end
    end

    -- 26: the pulse grid, counted from the song start, plus every Medium hit.
    local hats = {}
    local intro_clicks, anchor, intro_used = IntroPlan(input, opts.intro or 'steady', P)
    local intro_written = 0
    for _, q in ipairs(intro_clicks) do
        if InRange(q) then hats[#hats + 1] = q intro_written = intro_written + 1 end
    end
    local k = 0
    while true do
        local q = start_qn + k * step     -- by index, so float steps never drift
        if q >= end_qn - EPS then break end
        if InRange(q) and (not anchor or q >= anchor - EPS) then hats[#hats + 1] = q end
        k = k + 1
    end
    for _, h in ipairs(SortedQN(input.hits)) do
        if InRange(h) then hats[#hats + 1] = h end
    end
    table.sort(hats)
    local last
    for _, h in ipairs(hats) do
        if not last or h - last > P.dedup_qn - EPS then
            notes[#notes + 1] = { qn = h, pitch = P.hat }
            counts.hat = counts.hat + 1
            last = h
        end
    end

    table.sort(notes, function(a, b)
        if math.abs(a.qn - b.qn) > EPS then return a.qn < b.qn end
        return a.pitch < b.pitch
    end)

    return notes, {
        pulse = pulse, pulse_why = why, median_bpm = input.median_bpm,
        counts = counts, has_drums = #(input.hits or {}) > 0,
        intro = opts.intro or 'steady', intro_used = intro_used,
        intro_clicks = intro_written, pulse_from_qn = anchor,
    }
end

----------------------------------------------------------------------
-- REAPER action
----------------------------------------------------------------------
-- Requires globals: r, S, FindNamedTrackMIDI, GetAudioItems (helpers.lua),
-- FindTrackByName (lib/reaper_helper_common.lua), FindEventTime
-- (venue_awareness.lua), FindTrackExact, ReadGemEvents (lib/reaper_difficulty_read.lua),
-- ReplaceNotesBulk (lib/reaper_midi_helpers.lua), GetTimeSelection, FormatTime
-- (lib/reaper_imgui_helpers.lua)

local function Fail(status, detail)
    S.status = status
    S.last_result = detail
end

-- Median tempo (quarter notes per minute) over [qn_s, qn_e), one sample per quarter
-- note: each quarter note's own length, so linear tempo ramps count too.
local function MedianBPM(qn_s, qn_e)
    local bpms = {}
    local q = qn_s
    while q + 1 <= qn_e + EPS do
        local dt = r.TimeMap2_QNToTime(0, q + 1) - r.TimeMap2_QNToTime(0, q)
        if dt > 0 then bpms[#bpms + 1] = 60 / dt end
        q = q + 1
    end
    if #bpms == 0 then return nil end
    table.sort(bpms)
    return bpms[#bpms // 2 + 1]
end

-- PART DRUMS Medium (72-76) onsets in QN: kicks, snares and every hit. Muted notes are
-- skipped (ReadGemEvents). Returns nil and the reason when there are none to read; a
-- muted track counts as none.
local function ReadMediumDrums()
    local track = FindTrackExact('PART DRUMS')
    if not track then return nil, 'no PART DRUMS track' end
    if r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then return nil, 'PART DRUMS is muted' end
    local kicks, snares, hits = {}, {}, {}
    for _, ev in ipairs(ReadGemEvents(track, 72, 76)) do
        local q = r.TimeMap2_timeToQN(0, ev.s)
        hits[#hits + 1] = q
        for _, p in ipairs(ev.pitches) do
            if p == 72 then kicks[#kicks + 1] = q end
            if p == 73 then snares[#snares + 1] = q end
        end
    end
    if #hits == 0 then return nil, 'PART DRUMS has no Medium notes' end
    return { kicks = kicks, snares = snares, hits = hits }
end

local function MeasureAt(t)
    local _, meas = r.TimeMap2_timeToBeats(0, t)
    return math.floor(meas or 0) + 1
end

-- The count-in as the player hears it: the start of each audio clip on the COUNT IN
-- track (the community template's count-in, one hi-hat sample per clip), in QN, snapped
-- to the nearest 8th from measure 1 - the clips are usually placed on the grid, and a
-- tempo map adjusted after placing them leaves them slightly off. Muted clips are
-- skipped. Returns clicks, snapped (how many moved), or nil and the reason.
local function ReadCountInClicks(start_qn)
    local P = METRONOME_PARAMS
    local track = FindTrackByName('COUNT IN')
    if not track then return nil, 'no COUNT IN track' end
    if r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then return nil, 'COUNT IN is muted' end
    local clicks, seen, snapped = {}, {}, 0
    for _, it in ipairs(GetAudioItems(track)) do
        if r.GetMediaItemInfo_Value(it, 'B_MUTE') ~= 1 then
            local qn = r.TimeMap2_timeToQN(0, r.GetMediaItemInfo_Value(it, 'D_POSITION'))
            local q = MetronomeSnap(qn, P.count_in_snap_qn, start_qn)
            if math.abs(q - qn) > 1 / 64 then snapped = snapped + 1 end
            local key = string.format('%.4f', q)
            if not seen[key] then seen[key] = true clicks[#clicks + 1] = q end
        end
    end
    if #clicks == 0 then return nil, 'COUNT IN has no audio clips' end
    table.sort(clicks)
    return clicks, snapped
end

-- Expert notes of every part, for the band's first note (the chart count-in).
local BAND_PARTS = {
    { 'PART GUITAR', 96, 100 }, { 'PART BASS', 96, 100 }, { 'PART DRUMS', 96, 100 },
    { 'PART KEYS', 96, 100 }, { 'PART REAL_KEYS_X', 48, 72 }, { 'PART VOCALS', 36, 84 },
}

-- The band's first note in QN, with the bar line at or before it and the next one.
local function ReadBandStart()
    local first_t
    for _, part in ipairs(BAND_PARTS) do
        local track = FindTrackExact(part[1])
        if track then
            local evs = ReadGemEvents(track, part[2], part[3])
            if evs[1] and (not first_t or evs[1].s < first_t) then first_t = evs[1].s end
        end
    end
    if not first_t then return nil end
    local _, meas = r.TimeMap2_timeToBeats(0, first_t)
    local _, bar_qn, next_qn = r.TimeMap_GetMeasureInfo(0, math.floor(meas or 0))
    return r.TimeMap2_timeToQN(0, first_t), bar_qn, next_qn
end

-- The action behind Events > Metronome's Generate button. Pulse from S.metronome_pulse
-- (0 Auto, 1 8ths, 2 16ths), intro from S.metronome_intro (0 From COUNT IN, 1 Count in
-- from the chart, 2 Steady pulse).
function GenerateMetronome()
    local P = METRONOME_PARAMS
    local what = 'Metronome'
    local track, item, take = FindNamedTrackMIDI('EVENTS')
    if not track then
        return Fail(what .. ': no EVENTS track.',
                    'Add a track named EVENTS (the RBN template has one) with an [end] ' ..
                    'text event, then try again.')
    end
    if not take then
        return Fail(what .. ': the EVENTS track has no MIDI item.',
                    'Add a MIDI item on EVENTS with an [end] text event first.')
    end
    local end_t = FindEventTime('[end]')
    if not end_t then
        return Fail(what .. ': no [end] event.',
                    'The EVENTS track has no [end] text event. Add it first (Events > ' ..
                    'Manual gen > Insert bookends, or by hand): the metronome runs from ' ..
                    'measure 1 up to [end].')
    end
    local song_s_t = r.TimeMap_GetMeasureInfo(0, 0)
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
    local start_qn = r.TimeMap2_timeToQN(0, song_s_t)
    local end_qn   = r.TimeMap2_timeToQN(0, end_t)

    local drums, no_drums = ReadMediumDrums()
    local bpm = MedianBPM(start_qn, end_qn)
    local pulse = METRONOME_PULSES[(S.metronome_pulse or 0) + 1] or 'auto'
    local intro = METRONOME_INTROS[(S.metronome_intro or 0) + 1] or 'audio'
    local clicks, snapped_or_why
    if intro == 'audio' then clicks, snapped_or_why = ReadCountInClicks(start_qn) end
    local first_qn, bar_qn, next_qn
    if intro ~= 'steady' then first_qn, bar_qn, next_qn = ReadBandStart() end
    local notes, info = MetronomePlan({
        start_qn = start_qn, end_qn = end_qn, median_bpm = bpm,
        kicks = drums and drums.kicks, snares = drums and drums.snares,
        hits = drums and drums.hits,
        first_note_qn = first_qn, first_bar_qn = bar_qn, next_bar_qn = next_qn,
        count_in_clicks = clicks,
    }, {
        pulse = pulse, intro = intro,
        range_s_qn = r.TimeMap2_timeToQN(0, range_s_t),
        range_e_qn = r.TimeMap2_timeToQN(0, range_e_t),
    })
    if #notes == 0 then
        return Fail(what .. ': nothing to do.', 'No metronome note falls inside the time selection.')
    end

    -- Notes in seconds; none runs past [end].
    local out = {}
    for _, n in ipairs(notes) do
        out[#out + 1] = {
            s = r.TimeMap2_QNToTime(0, n.qn),
            e = r.TimeMap2_QNToTime(0, math.min(n.qn + P.len_qn, end_qn)),
            pitch = n.pitch,
        }
    end

    -- The item must hold every note.
    local pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local i_end = pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    if pos > out[1].s + 0.001 or i_end < out[#out].e - 0.001 then
        return Fail(what .. ': the EVENTS item is too short.',
                    string.format('The EVENTS MIDI item covers %s - %s but the metronome ' ..
                                  'runs %s - %s. Extend the item and try again.',
                                  FormatTime(pos), FormatTime(i_end),
                                  FormatTime(out[1].s), FormatTime(out[#out].e)))
    end

    -- Earlier metronome notes this run replaces: every 24-26 in the take on a whole-song
    -- run (strays past [end] too), else those starting in the selection - the same rule
    -- ReplaceNotesBulk applies.
    local function Replaced(sppq)
        if not sel_s then return true end
        local t = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
        return t >= range_s_t - 0.0005 and t < range_e_t - 0.0005
    end
    local removed = 0
    local _, n_notes = r.MIDI_CountEvts(take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
        if ok and pitch >= P.kick and pitch <= P.hat and Replaced(sppq) then removed = removed + 1 end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    local clear_s, clear_e
    if sel_s then clear_s, clear_e = range_s_t, range_e_t end
    if not ReplaceNotesBulk(take, clear_s, clear_e, { { P.kick, P.hat } }, out, P.vel) then
        for i = n_notes - 1, 0, -1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok and pitch >= P.kick and pitch <= P.hat and Replaced(sppq) then
                r.MIDI_DeleteNote(take, i)
            end
        end
        for _, n in ipairs(out) do
            r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjTime(take, n.s),
                              r.MIDI_GetPPQPosFromProjTime(take, n.e), 0, n.pitch, P.vel, false)
        end
    end
    r.Undo_EndBlock2(0, string.format('Generate practice metronome (%d notes)', #out), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    -- Result text
    local c = info.counts
    S.status = string.format('%s: %d notes written, measures %d-%d.', what, #out,
                             MeasureAt(out[1].s), MeasureAt(out[#out].s))
    local pulse_name = info.pulse == '16th' and '16ths' or '8ths'
    local lines = {
        'Kick (24)\t' .. c.kick,
        'Snare (25)\t' .. c.snare,
        'Hi-hat (26)\t' .. c.hat,
        '',
    }
    if info.pulse_why == 'auto' then
        lines[#lines + 1] = string.format('Pulse: %s (Auto - median tempo %.0f BPM; 16ths below %d).',
                                          pulse_name, bpm or 0, P.auto_16th_below_bpm)
    else
        lines[#lines + 1] = 'Pulse: ' .. pulse_name .. ' (picked).'
    end
    local function From()
        return info.pulse_from_qn
            and string.format('the pulse starts in measure %d', MeasureAt(r.TimeMap2_QNToTime(0, info.pulse_from_qn)))
            or 'the pulse runs from measure 1'
    end
    local n_in = info.intro_clicks
    local clicks_txt = string.format('%d count-in click%s', n_in, n_in == 1 and '' or 's')
    if sel_s and n_in == 0 and info.intro_used ~= 'steady' then
        clicks_txt = 'no count-in clicks in the time selection'
    end
    if info.intro_used == 'audio' then
        lines[#lines + 1] = string.format('Intro: %s from the COUNT IN clips; %s.', clicks_txt, From())
        if (snapped_or_why or 0) > 0 then
            lines[#lines + 1] = string.format('{info}%d COUNT IN clip%s sat off the 8th grid and %s ' ..
                                              'snapped to the nearest 8th - check the clips if the tempo map moved.',
                                              snapped_or_why, snapped_or_why == 1 and '' or 's',
                                              snapped_or_why == 1 and 'was' or 'were')
        end
    elseif info.intro_used == 'chart' then
        local lead = intro == 'audio'
            and ('{warn}Intro: ' .. tostring(snapped_or_why) .. ', so counted in from the chart: ')
            or  'Intro: counted in from the chart: '
        lines[#lines + 1] = lead .. clicks_txt .. ' before the band\'s first note; ' .. From() .. '.'
    elseif intro ~= 'steady' then
        lines[#lines + 1] = '{warn}Intro: no charted notes to count in to, so a steady pulse from measure 1.'
    else
        lines[#lines + 1] = 'Intro: steady pulse from measure 1.'
    end
    if drums then
        lines[#lines + 1] = 'Kick, snare and the hi-hat on every hit: PART DRUMS Medium.'
    else
        lines[#lines + 1] = '{warn}Hi-hat pulse only: ' .. no_drums ..
                            '. Generate again once Medium drums are charted.'
    end
    lines[#lines + 1] = sel_s and 'Range: the time selection, up to [end].'
                               or 'Range: measure 1 up to [end].'
    if removed > 0 then
        lines[#lines + 1] = string.format('Replaced %d earlier metronome notes.', removed)
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '{dim}Heard only in practice mode, when practising any part except drums.'
    S.last_result = table.concat(lines, '\n')
end
