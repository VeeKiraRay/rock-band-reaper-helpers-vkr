-- Tests for animation_character.lua (General Helper Animation > Character): the
-- pure CharacterPlan rules, then Generate / Manual against fixture part tracks.
-- The planner section needs no REAPER project; the integration section is
-- skipped when the project already has any of the part tracks.

-- Measures 2 and 3 start at QN 4 and 8 (4/4 from the start).
local BAR2, BAR3 = 4, 8

local function Plan(notes, over)
    local opts = { active = '[play]', gap_qn = 12, idle_gaps = true, bar2_qn = BAR2, bar3_qn = BAR3 }
    for k, v in pairs(over or {}) do opts[k] = v end
    return CharacterPlan(notes, opts)
end

-- Events as "msg@qn msg@qn ...".
local function Str(events)
    local out = {}
    for _, e in ipairs(events) do out[#out + 1] = string.format('%s@%g', e.msg, e.qn) end
    return table.concat(out, ' ')
end

local function Expect(events, want, label)
    local got = Str(events)
    Test.expect(got == want, (label or 'events') .. ': got "' .. got .. '", want "' .. want .. '"')
end

----------------------------------------------------------------------
Test.section('CharacterPlan')
----------------------------------------------------------------------

Test.it('first note in bar 3: active 1 beat before, no idle; idle_realtime after the last', function()
    Expect(Plan({ { s = 8, e = 9 }, { s = 10, e = 11 } }), '[play]@7 [idle_realtime]@12')
end)

Test.it('first note later: [idle] at bar 3, then the active state', function()
    Expect(Plan({ { s = 32, e = 33 } }), '[idle]@8 [play]@31 [idle_realtime]@34')
end)

Test.it('first note just after bar 3 (within a beat): no idle at bar 3', function()
    Expect(Plan({ { s = 8.5, e = 9 } }), '[play]@7.5 [idle_realtime]@10')
end)

Test.it('pickup in bar 2: the active state not before bar 2', function()
    Expect(Plan({ { s = 4.5, e = 5 } }), '[play]@4 [idle_realtime]@6')
end)

Test.it('gap under the threshold stays active', function()
    Expect(Plan({ { s = 8, e = 9 }, { s = 20, e = 21 } }), '[play]@7 [idle_realtime]@22')
end)

Test.it('gap at the threshold idles 1 beat after, back 1 beat before', function()
    Expect(Plan({ { s = 8, e = 9 }, { s = 21, e = 22 } }),
           '[play]@7 [idle]@10 [play]@20 [idle_realtime]@23')
end)

Test.it('vocal threshold (2 bars) idles where the instrument one does not', function()
    local notes = { { s = 8, e = 9 }, { s = 17, e = 18 } }
    Expect(Plan(notes), '[play]@7 [idle_realtime]@19', 'instrument')
    Expect(Plan(notes, { gap_qn = 8 }), '[play]@7 [idle]@10 [play]@16 [idle_realtime]@19', 'vocal')
end)

Test.it('a sustain bridges the gap', function()
    Expect(Plan({ { s = 8, e = 20 }, { s = 9, e = 10 }, { s = 22, e = 23 } }),
           '[play]@7 [idle_realtime]@24')
end)

Test.it('Idle in long gaps off: stays active, counts the gap', function()
    local ev, stats = Plan({ { s = 8, e = 9 }, { s = 40, e = 41 } }, { idle_gaps = false })
    Expect(ev, '[play]@7 [idle_realtime]@42')
    Test.expect(stats.kept == 1 and stats.idles == 0, 'kept 1, idles 0')
end)

Test.it('the chosen active state is used everywhere', function()
    Expect(Plan({ { s = 32, e = 33 }, { s = 60, e = 61 } }, { active = '[intense]' }),
           '[idle]@8 [intense]@31 [idle]@34 [intense]@59 [idle_realtime]@62')
end)

Test.it('notes in any order', function()
    Expect(Plan({ { s = 21, e = 22 }, { s = 8, e = 9 } }),
           '[play]@7 [idle]@10 [play]@20 [idle_realtime]@23')
end)

Test.it('no notes: no events', function()
    Test.expect(#Plan({}) == 0, 'expected no events')
end)

Test.it('descriptions: vocal wording for vocal parts', function()
    Test.expect(CharStateDesc('[idle]', true):find('microphone', 1, true), 'vocal [idle]')
    Test.expect(CharStateDesc('[idle]', false):find('idling normally', 1, true), 'instrument [idle]')
    Test.expect(CharStateDesc('[play_solo]', true) ~= '', '[play_solo] falls back to the instrument text')
end)

----------------------------------------------------------------------
Test.section('Character - REAPER integration')
----------------------------------------------------------------------

local function AnyPartTrack()
    for _, p in ipairs(CHAR_PARTS) do if FindTrackByName(p.track) then return true end end
    return false
end

if not (r and r.CountTracks) then
    -- offline harness: no REAPER
elseif AnyPartTrack() then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has a part track)\n')
elseif ({ r.TimeMap_GetMeasureInfo(0, 2) })[2] ~= 8 then
    r.ShowConsoleMsg('  SKIP  integration tests (run them in a project whose first bars are 4/4)\n')
else
    local function QNTime(qn) return r.TimeMap2_QNToTime(0, qn) end

    -- Part tracks with one MIDI item (64 QN) and the given Expert notes.
    local function MakePart(name, notes, pitch)
        local tr = r.GetTrack(0, CreateEmptyFixtureTrack(name))
        local item = r.CreateNewMIDIItemInProj(tr, 0, QNTime(64), false)
        local take = r.GetActiveTake(item)
        for _, n in ipairs(notes) do
            r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjQN(take, n[1]),
                              r.MIDI_GetPPQPosFromProjQN(take, n[2]), 0, pitch or 96, 100, false)
        end
        return tr, take
    end

    local function States(take)
        local out = {}
        local _, _, _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
            if ok and typ == 1 and CHAR_STATE_SET[msg] then
                out[#out + 1] = { qn = r.MIDI_GetProjQNFromPPQPos(take, ppq), msg = msg }
            end
        end
        table.sort(out, function(a, b) return a.qn < b.qn end)
        return out
    end

    local function WithParts(fn)
        local base = r.CountTracks(0)
        local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local cur = r.GetCursorPosition()
        local saved = { S.char_gap_inst_bars, S.char_idle_gaps, S.char_active.guitar }
        S.char_gap_inst_bars, S.char_idle_gaps, S.char_active.guitar = 3, true, 0
        r.GetSet_LoopTimeRange(true, false, 0, 0, false)
        local ok, err = pcall(fn)
        S.char_gap_inst_bars, S.char_idle_gaps, S.char_active.guitar = saved[1], saved[2], saved[3]
        r.GetSet_LoopTimeRange(true, false, sel_s, sel_e, false)
        r.SetEditCurPos(cur, false, false)
        CleanupFixture(base)
        if not ok then error(err, 2) end
    end

    Test.it('Generate writes the plan; a muted track gets nothing', function()
        WithParts(function()
            local _, g = MakePart('PART GUITAR', { { 32, 33 } })
            local b_tr, b = MakePart('PART BASS', { { 32, 33 } })
            r.SetMediaTrackInfo_Value(b_tr, 'B_MUTE', 1)
            GenerateCharacterAnimations()
            Test.expect(Str(States(g)) == '[idle]@8 [play]@31 [idle_realtime]@34', 'guitar: ' .. Str(States(g)))
            Test.expect(#States(b) == 0, 'muted bass must stay empty')
            Test.expect(tostring(S.last_result):find('PART BASS: muted', 1, true), 'result lists the muted track')
        end)
    end)

    Test.it('per-part active state', function()
        WithParts(function()
            local _, g = MakePart('PART GUITAR', { { 8, 9 } })
            S.char_active.guitar = 2
            GenerateCharacterAnimations()
            Test.expect(Str(States(g)) == '[intense]@7 [idle_realtime]@10', 'guitar: ' .. Str(States(g)))
        end)
    end)

    Test.it('a time selection replaces only the states inside it', function()
        WithParts(function()
            local _, g = MakePart('PART GUITAR', { { 8, 9 }, { 40, 41 } })
            GenerateCharacterAnimations()   -- [play]@7 [idle]@10 [play]@39 [idle_realtime]@42
            S.char_active.guitar = 1
            r.GetSet_LoopTimeRange(true, false, QNTime(30), QNTime(41), false)
            GenerateCharacterAnimations()
            Test.expect(Str(States(g)) == '[play]@7 [idle]@10 [mellow]@39 [idle_realtime]@42',
                        'guitar: ' .. Str(States(g)))
        end)
    end)

    Test.it('Manual replaces a state on the same tick', function()
        WithParts(function()
            local _, g = MakePart('PART GUITAR', { { 8, 9 } })
            local idx
            for i, p in ipairs(CHAR_PARTS) do if p.track == 'PART GUITAR' then idx = i end end
            r.SetEditCurPos(QNTime(16), false, false)
            InsertCharacterState(idx, '[play]')
            InsertCharacterState(idx, '[play_solo]')
            Test.expect(Str(States(g)) == '[play_solo]@16', 'guitar: ' .. Str(States(g)))
            Test.expect(CharacterStateAt(g, r.MIDI_GetPPQPosFromProjQN(g, 20)) == '[play_solo]',
                        'state at playhead')
        end)
    end)

    Test.it('ride options: drums only, replace only each other, Generate keeps them', function()
        WithParts(function()
            local _, d = MakePart('PART DRUMS', { { 8, 9 } })
            local _, g = MakePart('PART GUITAR', { { 8, 9 } })
            local di, gi
            for i, p in ipairs(CHAR_PARTS) do
                if p.track == 'PART DRUMS' then di = i elseif p.track == 'PART GUITAR' then gi = i end
            end
            local function Texts(take)
                local out = {}
                local _, _, _, n = r.MIDI_CountEvts(take)
                for i = 0, n - 1 do
                    local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
                    if ok and typ == 1 then
                        out[#out + 1] = string.format('%s@%g', msg, r.MIDI_GetProjQNFromPPQPos(take, ppq))
                    end
                end
                table.sort(out)
                return table.concat(out, ' ')
            end
            r.SetEditCurPos(QNTime(16), false, false)
            InsertCharacterState(gi, '[ride_side_true]')
            Test.expect(Texts(g) == '', 'guitar must refuse a ride option: ' .. Texts(g))
            InsertCharacterState(di, '[play]')
            InsertCharacterState(di, '[ride_side_true]')
            InsertCharacterState(di, '[ride_side_false]')
            Test.expect(Texts(d) == '[play]@16 [ride_side_false]@16',
                        'state kept, ride replaced: ' .. Texts(d))
            GenerateCharacterAnimations()
            Test.expect(Texts(d):find('[ride_side_false]@16', 1, true), 'Generate must keep the ride option')
            Test.expect(CharacterStateAt(d, r.MIDI_GetPPQPosFromProjQN(d, 9.5)) == '[play]',
                        'readout must ignore the ride option')
        end)
    end)

    Test.it('one undo step removes a Generate run', function()
        WithParts(function()
            local _, g = MakePart('PART GUITAR', { { 8, 9 } })
            GenerateCharacterAnimations()
            Test.expect(#States(g) == 2, 'expected 2 events before undo')
            r.Undo_DoUndo2(0)
            Test.expect(#States(g) == 0, 'undo must remove them, got ' .. #States(g))
        end)
    end)
end
