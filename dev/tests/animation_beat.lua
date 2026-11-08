-- Tests for animation_beat.lua (General Helper Animation > Beat): the pure
-- BeatPlan rules, then GenerateBeatTrack against fixture BEAT / EVENTS tracks.
-- The planner section needs no REAPER project; the integration section is
-- skipped when the project already has a BEAT or EVENTS track.

local EPS = 1e-6

-- Bars from a list of bar lengths in quarter notes, measure 1 at QN 0.
local function Bars(lens)
    local bars, qn = {}, 0
    for _, l in ipairs(lens) do
        bars[#bars + 1] = { qn_s = qn, qn_e = qn + l }
        qn = qn + l
    end
    return bars
end

local function Rep(len, n)
    local t = {}
    for i = 1, n do t[i] = len end
    return t
end

-- Notes as a compact string: "D0 u1 u2 u3 D4 ..." (D = 12, u = 13).
local function Str(notes)
    local out = {}
    for _, n in ipairs(notes) do
        out[#out + 1] = (n.pitch == BEAT_PITCH_DOWN and 'D' or 'u') .. string.format('%g', n.qn)
    end
    return table.concat(out, ' ')
end

local function Expect(notes, want, label)
    local got = Str(notes)
    Test.expect(got == want, (label or 'notes') .. ': got "' .. got .. '", want "' .. want .. '"')
end

----------------------------------------------------------------------
Test.section('BeatPlan - normal')
----------------------------------------------------------------------

Test.it('4/4: a note on every quarter, 12 on each downbeat', function()
    Expect(BeatPlan(Bars(Rep(4, 2)), { end_qn = 8 }), 'D0 u1 u2 u3 D4 u5 u6 u7')
end)

Test.it('[end] on a beat: no note on [end] itself', function()
    local notes = BeatPlan(Bars(Rep(4, 4)), { end_qn = 8 })
    Test.expect(#notes == 8, 'expected 8 notes, got ' .. #notes)
    Test.expect(notes[#notes].qn < 8 - EPS, 'last note must come before [end]')
end)

Test.it('[end] mid-bar: the bar is cut at [end]', function()
    Expect(BeatPlan(Bars(Rep(4, 3)), { end_qn = 5.5 }), 'D0 u1 u2 u3 D4 u5')
end)

Test.it('3/4 and 6/8 (3 QN): three quarter notes', function()
    Expect(BeatPlan(Bars(Rep(3, 2)), { end_qn = 6 }), 'D0 u1 u2 D3 u4 u5')
end)

Test.it('7/8: a note on the leftover half beat too (official charts)', function()
    Expect(BeatPlan(Bars(Rep(3.5, 2)), { end_qn = 7 }), 'D0 u1 u2 u3 D3.5 u4.5 u5.5 u6.5')
end)

Test.it('5/8: three notes, last gap an 8th', function()
    Expect(BeatPlan(Bars({ 2.5 }), { end_qn = 2.5 }), 'D0 u1 u2')
end)

Test.it('mixed meters: each bar counts from its own bar line', function()
    Expect(BeatPlan(Bars({ 4, 3, 2 }), { end_qn = 9 }), 'D0 u1 u2 u3 D4 u5 u6 D7 u8')
end)

Test.it('float noise on bar starts does not drop or double a note', function()
    local bars = { { qn_s = 0, qn_e = 4 - 1e-9 }, { qn_s = 4 - 1e-9, qn_e = 8 } }
    local notes = BeatPlan(bars, { end_qn = 8 + 1e-9 })
    Test.expect(#notes == 8, 'expected 8 notes, got ' .. #notes)
end)

----------------------------------------------------------------------
Test.section('BeatPlan - half time')
----------------------------------------------------------------------

Test.it('pair (default): downbeat on every other bar', function()
    Expect(BeatPlan(Bars(Rep(4, 4)), { end_qn = 16, half = true }),
           'D0 u2 u4 u6 D8 u10 u12 u14 u15')
end)

Test.it('bar: downbeat on every bar', function()
    Expect(BeatPlan(Bars(Rep(4, 2)), { end_qn = 8, half = true, half_style = 'bar' }),
           'D0 u2 D4 u6 u7')
end)

Test.it('3/4: beats 1 and 3, the short gap before the next bar', function()
    Expect(BeatPlan(Bars(Rep(3, 2)), { end_qn = 6, half = true }), 'D0 u2 u3 u5')
    Expect(BeatPlan(Bars(Rep(3, 2)), { end_qn = 6, half = true, half_style = 'bar' }),
           'D0 u2 D3 u5', 'bar style')
end)

Test.it('2/4: one note per bar (strict spacing), except the beat before [end]', function()
    Expect(BeatPlan(Bars(Rep(2, 2)), { end_qn = 4, half = true, half_style = 'bar' }), 'D0 D2 u3')
end)

Test.it('the beat just before [end] gets a note (Magma): [end] on beat 3', function()
    Expect(BeatPlan(Bars(Rep(4, 2)), { end_qn = 6, half = true }), 'D0 u2 u4 u5')
    Expect(BeatPlan(Bars(Rep(4, 2)), { end_qn = 6, half = true, half_style = 'bar' }),
           'D0 u2 D4 u5', 'bar style')
end)

Test.it('[end] on beat 2: the downbeat is already the beat before it', function()
    Expect(BeatPlan(Bars(Rep(4, 2)), { end_qn = 5, half = true }), 'D0 u2 u4')
end)

Test.it('3/4 with [end] on the bar line: beat 3 already holds a note', function()
    Expect(BeatPlan(Bars(Rep(3, 2)), { end_qn = 6, half = true }), 'D0 u2 u3 u5')
end)

----------------------------------------------------------------------
Test.section('BeatPlan - range (time selection)')
----------------------------------------------------------------------

Test.it('only notes starting inside the range', function()
    Expect(BeatPlan(Bars(Rep(4, 4)), { end_qn = 16, range_s_qn = 4, range_e_qn = 8 }),
           'D4 u5 u6 u7')
end)

Test.it('the range never runs past [end]', function()
    Expect(BeatPlan(Bars(Rep(4, 4)), { end_qn = 6, range_s_qn = 4, range_e_qn = 16 }),
           'D4 u5')
end)

Test.it('half pair: parity starts at the bar holding the range start', function()
    Expect(BeatPlan(Bars(Rep(4, 4)), { end_qn = 16, half = true, range_s_qn = 4 }),
           'D4 u6 u8 u10 D12 u14 u15')
end)

Test.it('range starting mid-bar: that bar keeps its parity, no 12 mid-bar', function()
    Expect(BeatPlan(Bars(Rep(4, 3)), { end_qn = 12, half = true, range_s_qn = 5 }),
           'u6 u8 u10 u11')
end)

----------------------------------------------------------------------
Test.section('GenerateBeatTrack - REAPER integration')
----------------------------------------------------------------------

if not (r and r.CountTracks) then
    -- offline harness: no REAPER
elseif FindTrackByName('BEAT') or FindTrackByName('EVENTS') then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has a BEAT or EVENTS track)\n')
elseif ({ r.TimeMap_GetMeasureInfo(0, 5) })[2] ~= 24 then
    -- the expected note lists below assume measures 1-6 are plain 4/4
    r.ShowConsoleMsg('  SKIP  integration tests (run them in a project whose first bars are 4/4)\n')
else
    local function MeasureQN(m) return ({ r.TimeMap_GetMeasureInfo(0, m - 1) })[2] end
    local function QNTime(qn) return r.TimeMap2_QNToTime(0, qn) end

    -- EVENTS with [end] at the start of end_measure; BEAT with an item when
    -- beat_item_qn is given (its length in QN from measure 1).
    local function WithFixture(end_measure, beat_item_qn, fn, no_end)
        local base = r.CountTracks(0)
        local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local ok, err = pcall(function()
            local ev = r.GetTrack(0, CreateEmptyFixtureTrack('EVENTS'))
            local end_qn = MeasureQN(end_measure)
            local ev_item = r.CreateNewMIDIItemInProj(ev, 0, QNTime(end_qn + 4), false)
            local ev_take = r.GetActiveTake(ev_item)
            if not no_end then
                r.MIDI_InsertTextSysexEvt(ev_take, false, false,
                    r.MIDI_GetPPQPosFromProjQN(ev_take, end_qn), 1, '[end]', false)
            end
            local beat = r.GetTrack(0, CreateEmptyFixtureTrack('BEAT'))
            if beat_item_qn then
                r.CreateNewMIDIItemInProj(beat, 0, QNTime(beat_item_qn), false)
            end
            r.GetSet_LoopTimeRange(true, false, 0, 0, false)   -- no selection
            fn(beat, end_qn)
        end)
        r.GetSet_LoopTimeRange(true, false, sel_s, sel_e, false)
        CleanupFixture(base)
        if not ok then error(err, 2) end
    end

    -- { {qn, pitch}, ... } sorted, from the first MIDI item on the track.
    local function ReadBeat(track)
        local _, take = FindFirstMIDIItem(track)
        local out = {}
        if not take then return out end
        local _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok then
                out[#out + 1] = { qn = r.MIDI_GetProjQNFromPPQPos(take, sppq), pitch = pitch }
            end
        end
        table.sort(out, function(a, b) return a.qn < b.qn end)
        return out
    end

    local saved_style = S.beat_half_style

    Test.it('no BEAT track: stops with a message', function()
        local base = r.CountTracks(0)
        local ok, err = pcall(function()
            local ev = r.GetTrack(0, CreateEmptyFixtureTrack('EVENTS'))
            r.CreateNewMIDIItemInProj(ev, 0, 10, false)
            S.status = nil
            GenerateBeatTrack(false)
            Test.expect(tostring(S.status):find('no BEAT track', 1, true), 'status: ' .. tostring(S.status))
        end)
        CleanupFixture(base)
        if not ok then error(err, 0) end
    end)

    Test.it('no [end]: stops, nothing written', function()
        WithFixture(5, 32, function(beat)
            GenerateBeatTrack(false)
            Test.expect(tostring(S.status):find('no [end]', 1, true), 'status: ' .. tostring(S.status))
            Test.expect(#ReadBeat(beat) == 0, 'BEAT must stay empty')
        end, true)
    end)

    Test.it('writes measure 1 up to [end], 12 on downbeats', function()
        WithFixture(5, 32, function(beat, end_qn)
            GenerateBeatTrack(false)
            local notes = ReadBeat(beat)
            Test.expect(#notes == 16, 'expected 16 notes in 4 bars of 4/4, got ' .. #notes)
            Test.expect(notes[1].pitch == BEAT_PITCH_DOWN and math.abs(notes[1].qn) < 1e-6,
                        'first note must be a 12 at measure 1')
            Test.expect(notes[#notes].qn < end_qn - 1e-6, 'last note must come before [end]')
        end)
    end)

    Test.it('no MIDI item on BEAT: one is created', function()
        WithFixture(3, nil, function(beat)
            GenerateBeatTrack(false)
            Test.expect(#ReadBeat(beat) == 8, 'expected 8 notes, got ' .. #ReadBeat(beat))
        end)
    end)

    Test.it('item ending before [end]: stops, nothing written', function()
        WithFixture(5, 6, function(beat)
            GenerateBeatTrack(false)
            Test.expect(tostring(S.status):find('too short', 1, true), 'status: ' .. tostring(S.status))
            Test.expect(#ReadBeat(beat) == 0, 'BEAT must stay empty')
        end)
    end)

    Test.it('half time in a time selection replaces only that range', function()
        WithFixture(5, 32, function(beat)
            S.beat_half_style = 0
            GenerateBeatTrack(false)
            r.GetSet_LoopTimeRange(true, false, QNTime(MeasureQN(2)), QNTime(MeasureQN(4)), false)
            GenerateBeatTrack(true)
            Test.expect(Str(ReadBeat(beat)) == 'D0 u1 u2 u3 D4 u6 u8 u10 D12 u13 u14 u15',
                        'got ' .. Str(ReadBeat(beat)))
        end)
        S.beat_half_style = saved_style
    end)

    Test.it('a selection reaching past [end] stops at [end]', function()
        WithFixture(3, 32, function(beat)
            r.GetSet_LoopTimeRange(true, false, QNTime(MeasureQN(2)), QNTime(MeasureQN(6)), false)
            GenerateBeatTrack(false)
            Test.expect(Str(ReadBeat(beat)) == 'D4 u5 u6 u7', 'got ' .. Str(ReadBeat(beat)))
        end)
    end)

    Test.it('one undo step removes the run', function()
        WithFixture(3, 32, function(beat)
            GenerateBeatTrack(false)
            Test.expect(#ReadBeat(beat) == 8, 'expected 8 notes before undo')
            r.Undo_DoUndo2(0)
            Test.expect(#ReadBeat(beat) == 0, 'undo must remove the notes, got ' .. #ReadBeat(beat))
        end)
    end)
end
