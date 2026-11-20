-- Tests for animation_keys.lua (General Helper Animation > Keys): the pure planner
-- (right hand, left-hand source, left-hand placement) and Validate, then
-- GenerateKeysAnimations / ValidateKeysAnimations against fixture tracks. The pure
-- sections need no REAPER project; the integration section is skipped when the
-- project already has a Pro Keys or keys animation track.

-- Notes from { qn_s, pitch, len, chan } rows.
local function N(rows)
    local out = {}
    for _, e in ipairs(rows) do
        out[#out + 1] = { qn_s = e[1], qn_e = e[1] + (e[3] or 0.5), pitch = e[2], chan = e[4] or 0 }
    end
    return out
end

local function P(notes)
    local out = {}
    for _, n in ipairs(notes) do out[#out + 1] = string.format('%d@%g', n.pitch, n.qn_s) end
    return table.concat(out, ' ')
end

local function Expect(got, want, label)
    Test.expect(got == want, (label or '') .. ': got "' .. tostring(got) .. '", want "' .. want .. '"')
end

local function Bar4(qn) return math.floor(qn / 4) + 1 end

-- "level:bars" per finding
local function F(findings)
    local out = {}
    for _, f in ipairs(findings) do out[#out + 1] = f.level .. ':' .. KeysAnimBarList(f.bars) end
    return table.concat(out, ' | ')
end

----------------------------------------------------------------------
Test.section('KeysAnimRightHand / KeysAnimLeftSource')
----------------------------------------------------------------------

Test.it('the right hand copies Expert 48-72 with its lengths; lane markers and out-of-range notes go', function()
    local rh = KeysAnimRightHand(N({ { 0, 5 }, { 0, 60, 2 }, { 1, 47 }, { 1, 72 }, { 2, 73 } }))
    Expect(P(rh), '60@0 72@1')
    Test.expect(math.abs(rh[1].qn_e - 2) < 1e-9, 'length kept')
end)

Test.it('Channel 2 keeps only MIDI channel 2 notes', function()
    local src = N({ { 0, 60, nil, 0 }, { 0, 40, nil, 1 }, { 1, 43, nil, 1 } })
    Expect(P(KeysAnimLeftSource(src, {}, 'channel')), '40@0 43@1')
end)

Test.it('Not on Expert: each Expert note takes one source note, the nearest octave', function()
    local expert = N({ { 0, 64 }, { 1, 67 } })
    -- Expert E 64 takes E 76 (12 away; E 40 is 24 away and stays), G 67 at 1 takes G 55;
    -- G 43 at 0 has no Expert G on its onset
    local src = N({ { 0, 76 }, { 0, 40 }, { 0, 43 }, { 1, 55 }, { 1, 48 } })
    Expect(P(KeysAnimLeftSource(src, expert, 'subtract')), '40@0 43@0 48@1')
end)

Test.it('Not on Expert keeps a left-hand root doubling the right hand; a tie goes to the higher note', function()
    Expect(P(KeysAnimLeftSource(N({ { 0, 60 }, { 0, 36 } }), N({ { 0, 60 } }), 'subtract')), '36@0',
           'exact match taken, root stays')
    Expect(P(KeysAnimLeftSource(N({ { 0, 72 }, { 0, 48 } }), N({ { 0, 60 } }), 'subtract')), '48@0',
           '72 and 48 both 12 away: the higher is the right hand')
end)

Test.it('Whole track keeps every note', function()
    Expect(P(KeysAnimLeftSource(N({ { 0, 30 }, { 1, 90 } }), {}, 'track')), '30@0 90@1')
end)

----------------------------------------------------------------------
Test.section('KeysAnimPlaceLeft')
----------------------------------------------------------------------

Test.it('a low piano phrase moves up to the octave that stays clear of the right hand', function()
    local rh = N({ { 0, 60, 4 }, { 0, 64, 4 }, { 0, 67, 4 } })   -- in game: lowest key 72
    -- +12 -> 48 52 55 (17 under the RH); +24 -> 60 64 67 (5 under: too close)
    local placed, dropped, shifts = KeysAnimPlaceLeft(N({ { 0, 36 }, { 1, 40 }, { 2, 43 } }), rh)
    Expect(P(placed), '48@0 52@1 55@2')
    Test.expect(#dropped == 0, 'nothing dropped')
    Test.expect(shifts[12] == 1, 'one phrase moved up an octave')
end)

Test.it('with no right hand under it, the phrase goes nearest the official LH register (55)', function()
    local placed = KeysAnimPlaceLeft(N({ { 0, 79 }, { 1, 83 } }), {})
    Expect(P(placed), '55@0 59@1')
end)

Test.it('phrases separated by more than 2 beats are placed on their own', function()
    local rh = N({ { 8, 50, 4 } })   -- low RH in the second phrase only (in game 62)
    local placed = KeysAnimPlaceLeft(N({ { 0, 67 }, { 1, 69 }, { 8, 67 }, { 9, 69 } }), rh)
    -- phrase 1: 55 57 (nearest 55). Phrase 2: 67 69 (above the RH) and 55 57 (7 and 5
    -- under it) both come closer than 8; equal, so nearest 55 wins - and 5+ apart is
    -- not dropped

    Expect(P(placed), '55@0 57@1 55@8 57@9')
end)

Test.it('a note that would meet the right hand in game is dropped', function()
    local rh = N({ { 0, 48, 1 } })   -- in game 60
    -- span 48-72 fits only as is; 72 sounds with the RH (72 > 60): dropped; 48 later is fine
    local placed, dropped = KeysAnimPlaceLeft(N({ { 0, 72 }, { 1, 48 } }), rh)
    Expect(P(placed), '48@1')
    Expect(P(dropped), '72@0', 'dropped')
end)

Test.it('a phrase wider than two octaves folds note by note; stacked keys merge', function()
    local placed, _, shifts = KeysAnimPlaceLeft(N({ { 0, 30 }, { 0, 42 }, { 1, 90 } }), {})
    Test.expect(shifts.fold == 1, 'folded')
    for _, n in ipairs(placed) do
        Test.expect(n.pitch >= 48 and n.pitch <= 72, 'in range: ' .. n.pitch)
    end
    Test.expect(#placed == 2, '30 and 42 land on one key: ' .. P(placed))
end)

----------------------------------------------------------------------
Test.section('KeysAnimValidate')
----------------------------------------------------------------------

Test.it('clean animations: no findings', function()
    local expert = N({ { 0, 60 }, { 4, 62 } })
    local f = KeysAnimValidate(KeysAnimRightHand(expert), N({ { 0, 48 } }), expert, Bar4)
    Expect(F(f), '')
    Expect(KeysAnimFindingLines(f)[1], '{ok}No problems found.')
end)

Test.it('out of range, hands meeting, wide hand, big LH chord, bars without animation', function()
    local expert = N({ { 0, 60 }, { 16, 60 } })
    local rh = N({ { 0, 74 }, { 4, 50, 1 }, { 8, 50 }, { 8, 64 } })
    local lh = N({ { 4, 62, 1 }, { 12, 48 }, { 12, 50 }, { 12, 52 }, { 12, 53 } })
    Expect(F(KeysAnimValidate(rh, lh, expert, Bar4)),
           'error:1 | warn:2 | advisory:3 | advisory:4 | info:5')
end)

Test.it('the hands 3 semitones apart in game are fine', function()
    -- RH 50 (in game 62) over LH 59
    Expect(F(KeysAnimValidate(N({ { 0, 50 } }), N({ { 0, 59 } }), {}, Bar4)), '')
end)

Test.it('bar lists collapse runs', function()
    Expect(KeysAnimBarList({ 1, 2, 3, 5, 8, 9 }), '1-3, 5, 8-9')
end)

----------------------------------------------------------------------
Test.section('Keys animations - REAPER integration')
----------------------------------------------------------------------

if not (r and r.CountTracks) then
    -- offline harness: no REAPER
elseif FindTrackByName(KEYS_ANIM_EXPERT) or FindTrackByName(KEYS_ANIM_TRACKS.rh)
       or FindTrackByName(KEYS_ANIM_TRACKS.lh) then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has a Pro Keys or keys animation track)\n')
else
    local function QNTime(qn) return r.TimeMap2_QNToTime(0, qn) end

    local function Make(name, rows)
        local tr = r.GetTrack(0, CreateEmptyFixtureTrack(name))
        local item = r.CreateNewMIDIItemInProj(tr, 0, QNTime(32), false)
        local take = r.GetActiveTake(item)
        for _, n in ipairs(rows) do
            r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjQN(take, n[1]),
                              r.MIDI_GetPPQPosFromProjQN(take, n[1] + (n[3] or 0.5)), n[4] or 0, n[2], 100, false)
        end
        return tr, take
    end

    local function Notes(take)
        local out = {}
        local _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok then
                out[#out + 1] = string.format('%d@%g', pitch,
                    math.floor(r.MIDI_GetProjQNFromPPQPos(take, sppq) * 1000 + 0.5) / 1000)
            end
        end
        table.sort(out)
        return table.concat(out, ' ')
    end

    local function WithFixture(fn)
        local base = r.CountTracks(0)
        local sel_s, sel_e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        r.GetSet_LoopTimeRange(true, false, 0, 0, false)
        local keep = { S.keys_anim_lh_idx, S.keys_anim_lh_mode }
        local ok, err = pcall(fn)
        S.keys_anim_lh_idx, S.keys_anim_lh_mode = table.unpack(keep)
        r.GetSet_LoopTimeRange(true, false, sel_s, sel_e, false)
        CleanupFixture(base)
        if not ok then error(err, 2) end
    end

    Test.it('right hand only: RH copies Expert, LH untouched, old RH notes replaced', function()
        WithFixture(function()
            Make(KEYS_ANIM_EXPERT, { { 0, 60 }, { 1, 64 }, { 2, 5, 0.25 } })
            local _, rh = Make(KEYS_ANIM_TRACKS.rh, { { 3, 70 } })
            local _, lh = Make(KEYS_ANIM_TRACKS.lh, { { 0, 50 } })
            S.keys_anim_lh_idx = -1
            GenerateKeysAnimations()
            Expect(Notes(rh), '60@0 64@1', 'RH')
            Expect(Notes(lh), '50@0', 'LH left alone')
        end)
    end)

    Test.it('left hand from channel 2 of a piano track, placed under the right hand', function()
        WithFixture(function()
            Make(KEYS_ANIM_EXPERT, { { 0, 60, 2 } })
            local _, rh = Make(KEYS_ANIM_TRACKS.rh, {})
            local _, lh = Make(KEYS_ANIM_TRACKS.lh, {})
            local piano = Make('PIANO', { { 0, 72, 2, 0 }, { 0, 36, 1, 1 }, { 1, 43, 1, 1 } })
            local _, idx = FindTrackByName('PIANO')
            S.keys_anim_lh_idx, S.keys_anim_lh_mode = idx, 1
            GenerateKeysAnimations()
            Expect(Notes(rh), '60@0', 'RH')
            Expect(Notes(lh), '48@0 55@1', 'LH an octave up, under the RH')
            Test.expect(piano ~= nil, 'piano track')
        end)
    end)

    Test.it('Validate reports what is wrong and changes nothing', function()
        WithFixture(function()
            Make(KEYS_ANIM_EXPERT, { { 0, 60 } })
            local _, rh = Make(KEYS_ANIM_TRACKS.rh, { { 0, 80 } })
            Make(KEYS_ANIM_TRACKS.lh, {})
            ValidateKeysAnimations()
            Test.expect(S.last_result:find('outside 48-72', 1, true), 'result: ' .. tostring(S.last_result))
            Expect(Notes(rh), '80@0', 'unchanged')
        end)
    end)
end
