-- Tests for animation_drums.lua (General Helper Animation > Drums): the pure
-- DrumAnimPlan rules, then GenerateDrumAnimations against a fixture PART DRUMS.
-- The planner section needs no REAPER project; the integration section is
-- skipped when the project already has a PART DRUMS / PART DRUMS_2X track.

-- Onsets from a compact list: { qn, 'KRYBG' letters, tom = 'YBG' letters }
-- at a steady tempo.
local function On(list, bpm)
    local out = {}
    for _, e in ipairs(list) do
        local o = { qn = e[1], sec = e[1] * 60 / (bpm or 120) }
        for c in (e[2] or ''):gmatch('.') do o[c] = true end
        for c in (e.tom or ''):gmatch('.') do o[c .. 't'] = true end
        o.disco = e.disco
        out[#out + 1] = o
    end
    return out
end

-- Hands per onset as "piece+hand" joined: "hhR,snL hhR ..."
local function Hands(onsets)
    local out = {}
    for _, o in ipairs(onsets) do
        local s = {}
        for _, h in ipairs(o.hands) do s[#s + 1] = h[1] .. h[2] end
        table.sort(s)
        out[#out + 1] = table.concat(s, ',')
    end
    return table.concat(out, ' ')
end

local function Pitches(notes)
    local out = {}
    for _, n in ipairs(notes) do out[#out + 1] = string.format('%d@%g', n.pitch, n.qn) end
    return table.concat(out, ' ')
end

local function Expect(got, want, label)
    Test.expect(got == want, (label or '') .. ': got "' .. got .. '", want "' .. want .. '"')
end

-- A run of the same gem every `step` QN from `qn0`.
local function Run(qn0, step, n, gems, tom)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = { qn0 + i * step, gems, tom = tom } end
    return out
end

----------------------------------------------------------------------
Test.section('DrumAnimPlan - pieces')
----------------------------------------------------------------------

Test.it('gems map to the kit (CAT table): kick, snare L, hi-hat R, ride, crash 2', function()
    local o = On({ { 0, 'K' }, { 4, 'R' }, { 8, 'Y' }, { 12, 'B' }, { 12.5, 'B' }, { 16, 'G' } })
    local notes = DrumAnimPlan(o, { snare_variety = false })
    Expect(Pitches(notes), '24@0 26@4 31@8 42@12 42@12.5 38@16')
end)

Test.it('a lone blue cymbal (no other blue within a beat) is a crash 1 accent', function()
    local o = On({ { 0, 'B' }, { 4, 'RB' }, { 8, 'B' }, { 9, 'B' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'c1R c1R,snL rideR rideR')
end)

Test.it('blue cymbal option open hi-hat: every blue hit is the hi-hat; with yellow it stays the ride', function()
    local o = On({ { 0, 'B' }, { 0.5, 'B' }, { 4, 'B' }, { 8, 'YB' } })
    DrumAnimPlan(o, { blue_hh = true })
    Expect(Hands(o), 'hhR hhR hhR hhL,rideR')
end)

Test.it('tom markers: yellow tom 1, blue tom 2, green floor tom', function()
    local o = On({ { 0, 'Y', tom = 'Y' }, { 4, 'B', tom = 'B' }, { 8, 'G', tom = 'G' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 't1L t2R ftR')
end)

Test.it('crash 1 option', function()
    local o = On({ { 0, 'G' } })
    Expect(Pitches(DrumAnimPlan(o, { crash1 = true })), '36@0')
end)

Test.it('groove: hi-hat right, snare left (crossed)', function()
    local o = On({ { 0, 'KY' }, { 1, 'RY' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhR,snL')
end)

Test.it('disco flip: red is the hi-hat, yellow the snare', function()
    local o = On({ { 0, 'R', disco = true }, { 1, 'Y', disco = true } })
    DrumAnimPlan(o, { snare_variety = false })
    Expect(Hands(o), 'hhR snL')
end)

Test.it('disco spans: "d]" opens, the next Expert mix closes; "dnoflip" is not a flip', function()
    local spans = DrumAnimDiscoSpans({
        { qn = 4, text = '[mix 3 drums0d]' }, { qn = 8, text = '[mix 3 drums0]' },
        { qn = 12, text = '[mix 3 drums0dnoflip]' }, { qn = 16, text = '[mix 2 drums0d]' },
    })
    Test.expect(#spans == 1 and spans[1].qn_s == 4 and spans[1].qn_e == 8, 'one span 4-8')
end)

----------------------------------------------------------------------
Test.section('DrumAnimPlan - two hands')
----------------------------------------------------------------------

Test.it('snare + yellow tom = flam (default on); off = snare L + tom 1 R', function()
    local o = On({ { 0, 'RY', tom = 'Y' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'snL,snR', 'flam')
    o = On({ { 0, 'RY', tom = 'Y' } })
    DrumAnimPlan(o, { flam = false })
    Expect(Hands(o), 'snL,t1R', 'no flam')
end)

Test.it('hi-hat + crash = crash 1 left + crash 2 right', function()
    local o = On({ { 0, 'YG' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'c1L,c2R')
end)

Test.it('snare + blue tom: the right hand reaches the floor tom', function()
    local o = On({ { 0, 'RB', tom = 'B' } })
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'ftR,snL')
end)

Test.it('flam late: the left hand a 1/32 note after', function()
    local o = On({ { 0, 'RY', tom = 'Y' } })
    local notes = DrumAnimPlan(o, { flam_late = true })
    Expect(Pitches(notes), '26@0.03125 27@0')
end)

----------------------------------------------------------------------
Test.section('DrumAnimPlan - hands in runs')
----------------------------------------------------------------------

Test.it('fast 16th snare run from the beat: R L R L (120 BPM, 125 ms)', function()
    local o = On(Run(0, 0.25, 8, 'R'), 120)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'snR snL snR snL snR snL snR snL')
end)

Test.it('fast run starting on an "e": L first', function()
    local o = On(Run(0.25, 0.25, 4, 'R'), 120)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'snL snR snL snR')
end)

Test.it('slow 8th tom 2 hits (100 BPM, 300 ms): one hand', function()
    local o = On(Run(0, 0.5, 4, 'B', 'B'), 100)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 't2R t2R t2R t2R')
end)

Test.it('a fill moving right at mid speed: the right hand takes each new drum', function()
    local o = On({ { -0.5, 'RY' }, { 0, 'R' }, { 0.5, 'Y', tom = 'Y' }, { 1, 'B', tom = 'B' },
                   { 1.5, 'G', tom = 'G' } }, 160)
    DrumAnimPlan(o, { snare_variety = false })
    Expect(Hands(o), 'hhR,snL snL t1R t2R ftR')
end)

Test.it('8th hi-hats at 120 BPM: all right hand', function()
    local o = On(Run(0, 0.5, 8, 'Y'), 120)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhR hhR hhR hhR hhR hhR hhR')
end)

Test.it('fast 16th hi-hats (150 BPM, 100 ms): alternate from min cymbal hits on', function()
    local o = On(Run(0, 0.25, 6, 'Y'), 150)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhL hhR hhL hhR hhL')
    o = On(Run(0, 0.25, 2, 'Y'), 150)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhR', 'two hits stay on the right hand')
end)

Test.it('hi-hat 16ths: a disco beat alternates at any speed, plain ones from 110 BPM', function()
    local list = Run(0, 0.25, 8, 'R')
    for _, e in ipairs(list) do e.disco = true end
    local o = On(list, 100)   -- 150 ms apart
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhL hhR hhL hhR hhL hhR hhL', 'disco at 100 BPM')
    o = On(Run(0, 0.25, 6, 'Y'), 115)   -- 130 ms: plain 16ths alternate
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhL hhR hhL hhR hhL', 'plain at 115 BPM')
    o = On(Run(0, 0.25, 6, 'Y'), 100)   -- 150 ms: one hand
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR hhR hhR hhR hhR hhR', 'plain at 100 BPM')
end)

Test.it('a drum straight after a cymbal: the other hand, even on the beat', function()
    -- 8th hi-hats at 200 BPM (150 ms, one hand), then a snare on the beat: the
    -- left hand plays it, not the beat's right hand
    local list = Run(0, 0.5, 2, 'Y')
    list[#list + 1] = { 1, 'R' }
    local o = On(list, 200)
    DrumAnimPlan(o, { snare_variety = false })
    Expect(Hands(o), 'hhR hhR snL')
end)

Test.it('crash 2 straight into crash 1: crash 1 by the left hand', function()
    local o = On({ { 0, 'G' }, { 0.5, 'G' } })
    DrumAnimPlan(o, {})   -- both crash 2 by default: the rule needs a crash 1
    Expect(Hands(o), 'c2R c2R', 'same crash')
end)

Test.it('slow snare variety: snare-only passage right, accent both hands, ghost left', function()
    local o = On({ { 0, 'R' }, { 1, 'R' }, { 2, 'R' } }, 100)
    DrumAnimPlan(o, {})
    -- first and last: accents after a pause (600 ms); the middle one: the passage
    Expect(Hands(o), 'snL,snR snR snL,snR', 'passage')
    o = On({ { 0, 'R' }, { 1, 'R' }, { 2, 'R' } }, 100)
    DrumAnimPlan(o, { snare_variety = false })
    Expect(Hands(o), 'snL snL snL', 'off')
    o = On({ { 0, 'KY' }, { 0.75, 'R' }, { 1, 'KY' } }, 90)
    DrumAnimPlan(o, {})
    Expect(Hands(o), 'hhR snL hhR', 'ghost note before a cymbal')
end)

Test.it('crash riding soft / hard in 8ths (option)', function()
    local o = On(Run(0, 0.5, 4, 'G'), 120)
    Expect(Pitches(DrumAnimPlan(o, { crash_ride_alt = true })), '38@0 39@0.5 38@1 39@1.5')
    o = On(Run(0, 1, 4, 'G'), 120)
    Expect(Pitches(DrumAnimPlan(o, { crash_ride_alt = true })), '38@0 38@1 38@2 38@3', 'quarters stay hard')
end)

----------------------------------------------------------------------
Test.section('Drums - REAPER integration')
----------------------------------------------------------------------

if not (r and r.CountTracks) then
    -- offline harness: no REAPER
elseif FindTrackByName('PART DRUMS') or FindTrackByName('PART DRUMS_2X') then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has a drums track)\n')
else
    local function QNTime(qn) return r.TimeMap2_QNToTime(0, qn) end

    local function MakeDrums(name, notes)
        local tr = r.GetTrack(0, CreateEmptyFixtureTrack(name))
        local item = r.CreateNewMIDIItemInProj(tr, 0, QNTime(32), false)
        local take = r.GetActiveTake(item)
        for _, n in ipairs(notes) do
            r.MIDI_InsertNote(take, false, false, r.MIDI_GetPPQPosFromProjQN(take, n[1]),
                              r.MIDI_GetPPQPosFromProjQN(take, n[1] + (n[3] or 0.25)), 0, n[2], 100, false)
        end
        return tr, take
    end

    local function Anim(take)
        local out = {}
        local _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, _, sppq, _, _, pitch = r.MIDI_GetNote(take, i)
            if ok and pitch >= 24 and pitch <= 51 then
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
        local ok, err = pcall(fn)
        r.GetSet_LoopTimeRange(true, false, sel_s, sel_e, false)
        CleanupFixture(base)
        if not ok then error(err, 2) end
    end

    Test.it('writes kick + hands; keeps the hi-hat pedal; a muted 2X is skipped', function()
        WithFixture(function()
            local _, d = MakeDrums('PART DRUMS', { { 0, 96 }, { 0, 98 }, { 1, 97 }, { 1, 98 }, { 0, 25, 2 } })
            local x_tr, x = MakeDrums('PART DRUMS_2X', { { 0, 96 } })
            r.SetMediaTrackInfo_Value(x_tr, 'B_MUTE', 1)
            GenerateDrumAnimations()
            Expect(Anim(d), '24@0 25@0 26@1 31@0 31@1', 'PART DRUMS')
            Expect(Anim(x), '', 'muted 2X')
        end)
    end)

    Test.it('a time selection replaces only the notes inside it', function()
        WithFixture(function()
            local _, d = MakeDrums('PART DRUMS', { { 0, 97 }, { 4, 97 }, { 4, 30 } })
            r.GetSet_LoopTimeRange(true, false, QNTime(2), QNTime(8), false)
            GenerateDrumAnimations()
            Expect(Anim(d), '26@4', 'old 30@4 replaced, nothing at 0')
        end)
    end)

    Test.it('one undo step removes the run', function()
        WithFixture(function()
            local _, d = MakeDrums('PART DRUMS', { { 0, 96 }, { 1, 97 } })
            GenerateDrumAnimations()
            Test.expect(Anim(d) ~= '', 'notes written')
            r.Undo_DoUndo2(0)
            Expect(Anim(d), '', 'after undo')
        end)
    end)
end
