-- Tests for events_metronome.lua (General Helper Events > Metronome): the pure
-- MetronomePlan rules, then GenerateMetronome against fixture EVENTS / PART DRUMS
-- tracks. The planner section needs no REAPER; the integration section is skipped
-- offline and when the project already has an EVENTS or PART DRUMS track.

local EPS = 1e-6
local KICK, SNARE, HAT = METRONOME_PARAMS.kick, METRONOME_PARAMS.snare, METRONOME_PARAMS.hat

-- QN list of one pitch, as "0 0.5 1 ...".
local function Of(notes, pitch)
    local out = {}
    for _, n in ipairs(notes) do
        if n.pitch == pitch then out[#out + 1] = string.format('%g', n.qn) end
    end
    return table.concat(out, ' ')
end

local function Expect(got, want, label)
    Test.expect(got == want, (label or 'notes') .. ': got "' .. got .. '", want "' .. want .. '"')
end

local function Plan(input, opts)
    input.start_qn = input.start_qn or 0
    input.median_bpm = input.median_bpm or 120
    return MetronomePlan(input, opts)
end

----------------------------------------------------------------------
Test.section('MetronomePlan - pulse')
----------------------------------------------------------------------

Test.it('Auto at 120 BPM: an 8th pulse from the song start, none on [end]', function()
    local notes, info = Plan({ end_qn = 2 })
    Expect(Of(notes, HAT), '0 0.5 1 1.5')
    Test.expect(info.pulse == '8th' and info.pulse_why == 'auto', 'pulse ' .. info.pulse)
end)

Test.it('Auto: 16ths below 95 BPM, 8ths at 95', function()
    local _, slow = Plan({ end_qn = 1, median_bpm = 94.9 })
    local _, at = Plan({ end_qn = 1, median_bpm = 95 })
    Test.expect(slow.pulse == '16th', 'at 94.9 BPM: ' .. slow.pulse)
    Test.expect(at.pulse == '8th', 'at 95 BPM: ' .. at.pulse)
end)

Test.it('a picked pulse overrides Auto', function()
    local notes, info = Plan({ end_qn = 1, median_bpm = 140 }, { pulse = '16th' })
    Expect(Of(notes, HAT), '0 0.25 0.5 0.75')
    Test.expect(info.pulse_why == 'picked', 'why ' .. info.pulse_why)
    local _, info8 = Plan({ end_qn = 1, median_bpm = 60 }, { pulse = '8th' })
    Test.expect(info8.pulse == '8th', 'picked 8ths at 60 BPM: ' .. info8.pulse)
end)

Test.it('the pulse counts from measure 1, wherever that is', function()
    local notes = Plan({ start_qn = 3, end_qn = 4.5 })
    Expect(Of(notes, HAT), '3 3.5 4')
end)

Test.it('a long song: grid steps do not drift', function()
    local notes = Plan({ end_qn = 2000 })
    local hats = 0
    for _, n in ipairs(notes) do
        if n.pitch == HAT then
            hats = hats + 1
            Test.expect(math.abs(n.qn * 2 - math.floor(n.qn * 2 + 0.5)) < EPS, 'off the grid at ' .. n.qn)
        end
    end
    Test.expect(hats == 4000, 'expected 4000 hats, got ' .. hats)
end)

----------------------------------------------------------------------
Test.section('MetronomePlan - drums')
----------------------------------------------------------------------

Test.it('24 on Medium kicks, 25 on Medium snares', function()
    local notes = Plan({ end_qn = 4, kicks = { 0, 2 }, snares = { 1, 3 }, hits = { 0, 1, 2, 3 } })
    Expect(Of(notes, KICK), '0 2')
    Expect(Of(notes, SNARE), '1 3')
end)

Test.it('26: a hit on the grid shares the pulse click, one off it gets its own', function()
    local notes = Plan({ end_qn = 2, hits = { 0.5, 1 + 1 / 3, 1 + 2 / 3 } })
    Expect(Of(notes, HAT), '0 0.5 1 1.33333 1.5 1.66667')
end)

Test.it('26: a hit within a 1/32 of a pulse step is not doubled', function()
    local notes = Plan({ end_qn = 1, hits = { 0.51 } })
    Expect(Of(notes, HAT), '0 0.5')
end)

Test.it('no drums: the pulse only', function()
    local notes, info = Plan({ end_qn = 1 })
    Expect(Of(notes, KICK), '')
    Expect(Of(notes, SNARE), '')
    Expect(Of(notes, HAT), '0 0.5')
    Test.expect(not info.has_drums, 'has_drums should be false')
end)

Test.it('drum notes on or past [end] are left out', function()
    local notes = Plan({ end_qn = 2, kicks = { 1, 2, 3 }, hits = { 1, 2, 3 } })
    Expect(Of(notes, KICK), '1')
end)

Test.it('notes come sorted by time, then pitch', function()
    local notes = Plan({ end_qn = 1, kicks = { 0 }, snares = { 0 }, hits = { 0 } })
    Expect(Of(notes, KICK) .. '|' .. Of(notes, SNARE) .. '|' .. Of(notes, HAT), '0|0|0 0.5')
    Test.expect(notes[1].pitch == KICK and notes[2].pitch == SNARE and notes[3].pitch == HAT,
                'order at QN 0: 24, 25, 26')
end)

----------------------------------------------------------------------
Test.section('MetronomePlan - range (time selection)')
----------------------------------------------------------------------

Test.it('only notes starting inside the range: start in, end out', function()
    local notes = Plan({ end_qn = 8, kicks = { 1, 2, 4 }, hits = { 1, 2, 4 } },
                       { range_s_qn = 2, range_e_qn = 4 })
    Expect(Of(notes, KICK), '2')
    Expect(Of(notes, HAT), '2 2.5 3 3.5')
end)

Test.it('the range never runs past [end]', function()
    local notes = Plan({ end_qn = 3 }, { range_s_qn = 2, range_e_qn = 10 })
    Expect(Of(notes, HAT), '2 2.5')
end)

Test.it('the range keeps the song grid (a selection starting off the grid)', function()
    local notes = Plan({ end_qn = 4 }, { range_s_qn = 1.2, range_e_qn = 2.2 })
    Expect(Of(notes, HAT), '1.5 2')
end)

----------------------------------------------------------------------
Test.section('MetronomePlan - intro (count-in)')
----------------------------------------------------------------------

-- A band starting at QN `first`, in 4/4 from QN 0.
local function Band(first, extra)
    local bar = math.floor(first / 4) * 4
    local t = { end_qn = 20, first_note_qn = first, first_bar_qn = bar, next_bar_qn = bar + 4 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

-- The 26s before `upto`, as "0 2 4 ...".
local function HatsBefore(notes, upto)
    local out = {}
    for _, n in ipairs(notes) do
        if n.pitch == HAT and n.qn < upto - EPS then out[#out + 1] = string.format('%g', n.qn) end
    end
    return table.concat(out, ' ')
end

Test.it('From COUNT IN: a click on each clip, the pulse from the beat after the last', function()
    local notes, info = Plan(Band(8, { count_in_clicks = { 0, 2, 4, 5, 6, 7 } }), { intro = 'audio' })
    Expect(HatsBefore(notes, 9.1), '0 2 4 5 6 7 8 8.5 9')
    Test.expect(info.intro_used == 'audio' and info.intro_clicks == 6, 'used ' .. info.intro_used)
end)

Test.it('From COUNT IN: a pickup before the beat after the last click starts the pulse there', function()
    local notes = Plan(Band(7.5, { count_in_clicks = { 0, 2, 4, 5, 6, 7 } }), { intro = 'audio' })
    Expect(HatsBefore(notes, 8.1), '0 2 4 5 6 7 7.5 8')
end)

Test.it('From COUNT IN: a gap before the band keeps the pulse going after the count-in', function()
    local notes = Plan(Band(16, { count_in_clicks = { 0, 2, 4, 5, 6, 7 } }), { intro = 'audio' })
    Expect(HatsBefore(notes, 9.1), '0 2 4 5 6 7 8 8.5 9')
end)

Test.it('From COUNT IN without clips: counts in from the chart instead', function()
    local notes, info = Plan(Band(8, { count_in_clicks = {} }), { intro = 'audio' })
    Expect(HatsBefore(notes, 8.1), '0 2 4 5 6 7 8')
    Test.expect(info.intro_used == 'chart', 'used ' .. info.intro_used)
end)

Test.it('chart: a band at bar 3 is counted in over bars 1-2', function()
    local notes = Plan(Band(8), { intro = 'chart' })
    Expect(HatsBefore(notes, 8.6), '0 2 4 5 6 7 8 8.5')
end)

Test.it('chart: a band starting later is counted in just before it, nothing earlier', function()
    local notes = Plan(Band(16), { intro = 'chart' })
    Expect(HatsBefore(notes, 16.1), '8 10 12 13 14 15 16')
end)

Test.it('chart: a pickup counts in to the bar after it, cut at the first note', function()
    local notes = Plan(Band(7), { intro = 'chart' })
    Expect(HatsBefore(notes, 8.1), '0 2 4 5 6 7 7.5 8')
end)

Test.it('chart: a first note halfway into a bar counts in to the later bar', function()
    local notes = Plan(Band(6), { intro = 'chart' })
    Expect(HatsBefore(notes, 7.1), '0 2 4 5 6 6.5 7')
end)

Test.it('chart without any band note: the steady pulse', function()
    local notes, info = Plan({ end_qn = 2 }, { intro = 'chart' })
    Expect(Of(notes, HAT), '0 0.5 1 1.5')
    Test.expect(info.intro_used == 'steady', 'used ' .. info.intro_used)
end)

Test.it('steady: the pulse from measure 1, whatever the band and the clips', function()
    local notes = Plan(Band(8, { count_in_clicks = { 0, 2 } }), { intro = 'steady' })
    Expect(HatsBefore(notes, 2.1), '0 0.5 1 1.5 2')
end)

Test.it('a time selection after the count-in leaves it out', function()
    local notes, info = Plan(Band(8, { count_in_clicks = { 0, 2, 4, 5, 6, 7 } }),
                             { intro = 'audio', range_s_qn = 8, range_e_qn = 9 })
    Expect(Of(notes, HAT), '8 8.5')
    Test.expect(info.intro_clicks == 0, 'intro clicks ' .. info.intro_clicks)
end)

Test.it('MetronomeSnap: to the nearest 8th from measure 1', function()
    Test.expect(MetronomeSnap(3.97, 0.5, 0) == 4, '3.97 -> 4')
    Test.expect(MetronomeSnap(4.3, 0.5, 0) == 4.5, '4.3 -> 4.5')
    Test.expect(MetronomeSnap(5.2, 0.5, 1) == 5, 'origin 1: 5.2 -> 5')
end)

----------------------------------------------------------------------
Test.section('GenerateMetronome - REAPER integration')
----------------------------------------------------------------------

if not (r and r.CountTracks) then
    -- offline harness: no REAPER
elseif FindTrackByName('EVENTS') or FindTrackByName('PART DRUMS') then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has an EVENTS or PART DRUMS track)\n')
elseif ({ r.TimeMap_GetMeasureInfo(0, 5) })[2] ~= 24 then
    r.ShowConsoleMsg('  SKIP  integration tests (run them in a project whose first bars are 4/4)\n')
else
    local function QNTime(qn) return r.TimeMap2_QNToTime(0, qn) end

    -- EVENTS with [end] at end_qn (unless no_end) and a text event plus a note 30 the
    -- run must leave alone; PART DRUMS with Medium notes { {qn, pitch} } when given.
    local function WithFixture(end_qn, drums, fn, no_end)
        local base = r.CountTracks(0)
        local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local saved_pulse, saved_intro = S.metronome_pulse, S.metronome_intro
        local ok, err = pcall(function()
            local ev = r.GetTrack(0, CreateEmptyFixtureTrack('EVENTS'))
            local ev_item = r.CreateNewMIDIItemInProj(ev, 0, QNTime(end_qn + 4), false)
            local ev_take = r.GetActiveTake(ev_item)
            if not no_end then
                r.MIDI_InsertTextSysexEvt(ev_take, false, false,
                    r.MIDI_GetPPQPosFromProjQN(ev_take, end_qn), 1, '[end]', false)
            end
            r.MIDI_InsertTextSysexEvt(ev_take, false, false,
                r.MIDI_GetPPQPosFromProjQN(ev_take, 1), 1, '[prc_intro]', false)
            r.MIDI_InsertNote(ev_take, false, false, r.MIDI_GetPPQPosFromProjQN(ev_take, 1),
                r.MIDI_GetPPQPosFromProjQN(ev_take, 1.25), 0, 30, 100, false)
            if drums then
                local dr = r.GetTrack(0, CreateEmptyFixtureTrack('PART DRUMS'))
                local dr_item = r.CreateNewMIDIItemInProj(dr, 0, QNTime(end_qn), false)
                local dr_take = r.GetActiveTake(dr_item)
                for _, d in ipairs(drums) do
                    r.MIDI_InsertNote(dr_take, false, false, r.MIDI_GetPPQPosFromProjQN(dr_take, d[1]),
                        r.MIDI_GetPPQPosFromProjQN(dr_take, d[1] + 0.25), 0, d[2], 100, false)
                end
            end
            r.GetSet_LoopTimeRange(true, false, 0, 0, false)   -- no selection
            S.metronome_pulse = 1                               -- 8ths, whatever the tempo
            S.metronome_intro = 2                               -- steady pulse unless a test picks one
            fn(ev, ev_take)
        end)
        S.metronome_pulse, S.metronome_intro = saved_pulse, saved_intro
        r.GetSet_LoopTimeRange(true, false, sel_s, sel_e, false)
        CleanupFixture(base)
        if not ok then error(err, 2) end
    end

    -- "pitch@qn" for every note, sorted.
    local function Read(take)
        local out = {}
        local _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok then
                out[#out + 1] = { qn = r.MIDI_GetProjQNFromPPQPos(take, sppq), pitch = pitch }
            end
        end
        table.sort(out, function(a, b)
            if math.abs(a.qn - b.qn) > EPS then return a.qn < b.qn end
            return a.pitch < b.pitch
        end)
        return out
    end
    local function Count(notes, pitch)
        local c = 0
        for _, n in ipairs(notes) do if n.pitch == pitch then c = c + 1 end end
        return c
    end
    local function Texts(take)
        local _, _, _, nt = r.MIDI_CountEvts(take)
        return nt
    end

    Test.it('no EVENTS track: stops with a message', function()
        S.status = nil
        GenerateMetronome()
        Test.expect(tostring(S.status):find('no EVENTS track', 1, true), 'status: ' .. tostring(S.status))
    end)

    Test.it('no [end]: stops, nothing written', function()
        WithFixture(8, nil, function(_, take)
            GenerateMetronome()
            Test.expect(tostring(S.status):find('no [end]', 1, true), 'status: ' .. tostring(S.status))
            Test.expect(Count(Read(take), HAT) == 0, 'EVENTS must get no 26')
        end, true)
    end)

    Test.it('no PART DRUMS: the 8th pulse from measure 1 up to [end]', function()
        WithFixture(8, nil, function(_, take)
            GenerateMetronome()
            local notes = Read(take)
            Test.expect(Count(notes, HAT) == 16, 'expected 16 hats, got ' .. Count(notes, HAT))
            Test.expect(Count(notes, KICK) == 0 and Count(notes, SNARE) == 0, 'no 24 / 25')
            Test.expect(tostring(S.last_result):find('Hi-hat pulse only', 1, true),
                        'result: ' .. tostring(S.last_result))
        end)
    end)

    Test.it('Medium kicks and snares become 24 / 25; other EVENTS notes and texts stay', function()
        WithFixture(8, { { 0, 72 }, { 1, 73 }, { 2, 72 }, { 3, 73 }, { 0, 96 }, { 1.75, 74 } },
                    function(_, take)
            local texts = Texts(take)
            GenerateMetronome()
            local notes = Read(take)
            Test.expect(Count(notes, KICK) == 2, 'kicks: ' .. Count(notes, KICK))
            Test.expect(Count(notes, SNARE) == 2, 'snares: ' .. Count(notes, SNARE))
            Test.expect(Count(notes, HAT) == 17, '16 pulse steps + the 1.75 hit, got ' .. Count(notes, HAT))
            Test.expect(Count(notes, 30) == 1, 'note 30 must stay')
            Test.expect(Texts(take) == texts, 'text events must stay')
        end)
    end)

    Test.it('a re-run replaces the earlier clicks instead of doubling them', function()
        WithFixture(8, { { 0, 72 } }, function(_, take)
            GenerateMetronome()
            GenerateMetronome()
            local notes = Read(take)
            Test.expect(Count(notes, HAT) == 16 and Count(notes, KICK) == 1,
                        'hats ' .. Count(notes, HAT) .. ', kicks ' .. Count(notes, KICK))
            Test.expect(tostring(S.last_result):find('Replaced 17 earlier', 1, true),
                        'result: ' .. tostring(S.last_result))
        end)
    end)

    Test.it('a time selection replaces only that range, on the song grid', function()
        WithFixture(8, nil, function(_, take)
            GenerateMetronome()
            S.metronome_pulse = 2   -- 16ths in measure 2 only
            r.GetSet_LoopTimeRange(true, false, QNTime(4), QNTime(8), false)
            GenerateMetronome()
            Test.expect(Count(Read(take), HAT) == 8 + 16, 'expected 24 hats, got ' .. Count(Read(take), HAT))
        end)
    end)

    local function HatsBefore8(take)
        local out = {}
        for _, n in ipairs(Read(take)) do
            if n.pitch == HAT and n.qn < 8 - EPS then out[#out + 1] = string.format('%g', n.qn) end
        end
        return table.concat(out, ' ')
    end

    Test.it('Count in from chart: the count-in before the band\'s first Expert note', function()
        WithFixture(16, { { 8, 96 } }, function(_, take)
            S.metronome_intro = 1
            GenerateMetronome()
            Test.expect(HatsBefore8(take) == '0 2 4 5 6 7', 'count-in: ' .. HatsBefore8(take))
            Test.expect(tostring(S.last_result):find('counted in from the chart', 1, true),
                        'result: ' .. tostring(S.last_result))
        end)
    end)

    Test.it('From COUNT IN: the clips become the count-in, snapped to 8ths', function()
        WithFixture(16, { { 8, 96 } }, function(_, take)
            local ci = r.GetTrack(0, CreateEmptyFixtureTrack('COUNT IN'))
            local made = 0
            for _, qn in ipairs({ 0, 2.02, 4, 5, 6, 7 }) do
                local ok = pcall(function()
                    local it = r.AddMediaItemToTrack(ci)
                    r.SetMediaItemInfo_Value(it, 'D_POSITION', QNTime(qn))
                    r.SetMediaItemInfo_Value(it, 'D_LENGTH', 0.1)
                    local tk = r.AddTakeToMediaItem(it)
                    r.SetMediaItemTake_Source(tk, r.PCM_Source_CreateFromType('WAVE'))
                end)
                if ok then made = made + 1 end
            end
            S.metronome_intro = 0
            GenerateMetronome()
            Test.expect(HatsBefore8(take) == '0 2 4 5 6 7', 'count-in: ' .. HatsBefore8(take))
            if made == 6 then
                Test.expect(tostring(S.last_result):find('from the COUNT IN clips', 1, true),
                            'result: ' .. tostring(S.last_result))
                Test.expect(tostring(S.last_result):find('1 COUNT IN clip sat off the 8th grid', 1, true),
                            'the clip at 2.02 should be reported as snapped')
            else
                r.ShowConsoleMsg('  (audio clips could not be made here; only the chart fallback was checked)\n')
            end
        end)
    end)

    Test.it('one undo step removes the run', function()
        WithFixture(8, nil, function(_, take)
            FixtureUndoPoint()   -- else the undo below deletes the fixture tracks too
            GenerateMetronome()
            Test.expect(Count(Read(take), HAT) == 16, 'expected 16 hats before undo')
            r.Undo_DoUndo2(0)
            Test.expect(Count(Read(take), HAT) == 0, 'undo must remove them, got ' .. Count(Read(take), HAT))
        end)
    end)
end
