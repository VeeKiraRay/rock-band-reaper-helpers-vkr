-- Tests for animation_drums.lua (General Helper Animation > Drums): the pure
-- DrumAnimPlan rules, then GenerateDrumAnimations against a fixture PART DRUMS.
-- The planner section needs no REAPER project; the integration section is
-- skipped when the project already has a PART DRUMS / PART DRUMS_2X track.

-- Onsets from a compact list: { qn, 'KRYBG' letters, tom = 'YBG' letters,
-- vel = { R = 30, ... } (gem velocity per lane, optional) } at a steady tempo.
local function On(list, bpm)
    local out = {}
    for _, e in ipairs(list) do
        local o = { qn = e[1], sec = e[1] * 60 / (bpm or 120) }
        for c in (e[2] or ''):gmatch('.') do o[c] = true end
        for c in (e.tom or ''):gmatch('.') do o[c .. 't'] = true end
        o.disco = e.disco
        o.vel = e.vel
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

Test.it('blue cymbal option hi-hat: every blue hit is the hi-hat; with yellow it stays the ride', function()
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
    -- every crash soft (threshold 128): the riding flips the other way
    o = On(Run(0, 0.5, 4, 'G'), 120)
    Expect(Pitches(DrumAnimPlan(o, { crash_ride_alt = true, soft_cym_below = 128 })),
           '39@0 38@0.5 39@1 38@1.5', 'soft crash + riding')
    -- constant velocity under no threshold: the riding alone alternates
    o = On(Run(0, 0.5, 4, 'G'), 120)
    for _, x in ipairs(o) do x.vel = { G = 100 } end
    Expect(Pitches(DrumAnimPlan(o, { crash_ride_alt = true, soft_cym_below = 50 })),
           '38@0 39@0.5 38@1 39@1.5', 'riding at a constant velocity')
end)

-- Plan a list with the planner's snare variety off, plus extra opts.
local function PlanWith(list, extra)
    local opts = { snare_variety = false }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return Pitches(DrumAnimPlan(On(list, 120), opts))
end

Test.it('soft snare and soft crash thresholds are separate (128 = every hit)', function()
    -- snare at 0, crash 2 at 4, hi-hat at 8 (no soft note), far apart, normal velocity
    local list = { { 0, 'R' }, { 4, 'G' }, { 8, 'Y' } }
    Expect(PlanWith(list), '26@0 38@4 31@8', 'both off')
    Expect(PlanWith(list, { soft_cym_below = 128 }), '26@0 39@4 31@8', 'every crash soft: snare stays hard')
    Expect(PlanWith(list, { soft_snare_below = 128 }), '28@0 38@4 31@8', 'every snare soft: crash stays hard')
    Expect(PlanWith(list, { soft_cym_below = 128, soft_snare_below = 128 }), '28@0 39@4 31@8', 'both')
    Expect(PlanWith(list, { soft_cym_below = 50, soft_snare_below = 50 }), '26@0 38@4 31@8',
           'normal velocity (100) under 50: nothing soft')
end)

Test.it('soft snare by velocity: under the threshold only', function()
    local list = { { 0, 'R', vel = { R = 30 } }, { 4, 'R', vel = { R = 49 } },
                   { 8, 'R', vel = { R = 50 } }, { 12, 'R', vel = { R = 96 } } }
    Expect(PlanWith(list, { soft_snare_below = 50 }), '28@0 28@4 26@8 26@12', '30 / 49 soft, 50 / 96 hard')
    Expect(PlanWith(list), '26@0 26@4 26@8 26@12', 'option off: velocity ignored')
end)

Test.it('crash by velocity: choke, soft, hit; crash 1 chokes on 41, crash 2 on 40', function()
    local list = { { 0, 'G', vel = { G = 10 } }, { 4, 'G', vel = { G = 40 } }, { 8, 'G', vel = { G = 100 } } }
    local opts = { choke_below = 20, soft_cym_below = 50 }
    Expect(PlanWith(list, opts), '40@0 39@4 38@8', 'crash 2: choke replaces the hit, then soft, then hit')
    opts.crash1 = true
    Expect(PlanWith(list, opts), '41@0 37@4 36@8', 'crash 1 (default crash option)')
    -- reversed: soft below 20, choke below 50 -> 0-19 soft, 20-49 choke
    opts.crash1 = nil
    Expect(PlanWith(list, { choke_below = 50, soft_cym_below = 20 }), '39@0 40@4 38@8',
           'reversed order: 10 soft, 40 choke, 100 hit')
    -- equal thresholds: the choke takes the band
    Expect(PlanWith(list, { choke_below = 50, soft_cym_below = 50 }), '40@0 40@4 38@8', 'equal: chokes')
    -- choke 0 = none
    Expect(PlanWith(list, { choke_below = 0, soft_cym_below = 50 }), '39@0 39@4 38@8', 'no chokes')
end)

Test.it('crash velocity leaves the hi-hat and ride alone', function()
    local list = { { 0, 'Y', vel = { Y = 10 } }, { 4, 'B', vel = { B = 10 } }, { 4.5, 'B', vel = { B = 10 } } }
    Expect(PlanWith(list, { choke_below = 20, soft_cym_below = 50 }), '31@0 42@4 42@4.5', 'hi-hat and ride')
end)

Test.it('a choke is never flipped by crash riding', function()
    local o = On(Run(0, 0.5, 4, 'G'), 120)
    for i, x in ipairs(o) do x.vel = { G = (i == 2) and 10 or 100 } end
    Expect(Pitches(DrumAnimPlan(o, { crash_ride_alt = true, choke_below = 20, soft_cym_below = 50 })),
           '38@0 40@0.5 38@1 39@1.5', 'the second hit chokes; the riding still flips the fourth')
end)

Test.it('the piece takes its own gem\'s velocity (disco flip, flam)', function()
    -- disco flip: the yellow cymbal is the snare, the red gem the hi-hat
    local list = { { 0, 'RY', disco = true, vel = { R = 100, Y = 30 } } }
    local disco = PlanWith(list, { soft_snare_below = 50 })
    Test.expect(disco:find('28@0', 1, true) and disco:find('31@0', 1, true),
                'disco: snare soft from the yellow gem, hi-hat as is, got ' .. disco)
    -- flam: snare + yellow tom = both hands on the snare, by the red gem's velocity
    list = { { 0, 'RY', tom = 'Y', vel = { R = 30, Y = 100 } } }
    local got = PlanWith(list, { soft_snare_below = 50 })
    Test.expect(got:find('28@0', 1, true) and got:find('29@0', 1, true) and not got:find('26@', 1, true),
                'flam: both hands soft, got ' .. got)
end)

----------------------------------------------------------------------
Test.section('DrumAnimOpenHatSpans - open hi-hat pedal (25)')
----------------------------------------------------------------------

-- Plan a list, then its open-hat spans as "s-e:hits" joined.
local function Spans(list, opts)
    opts = opts or {}
    opts.snare_variety = false
    local o = On(list, 120)
    DrumAnimPlan(o, opts)
    local out = {}
    for _, sp in ipairs(DrumAnimOpenHatSpans(o, opts)) do
        out[#out + 1] = string.format('%g-%g:%d', sp.qn_s, sp.qn_e, sp.hits)
    end
    return table.concat(out, ' ')
end

-- Yellow hi-hat 8ths from qn0, velocity 96 except `loud` (index -> velocity).
local function Hats(qn0, n, loud)
    local out = {}
    for i = 1, n do
        out[#out + 1] = { qn0 + (i - 1) * 0.5, 'Y', vel = { Y = (loud and loud[i]) or 96 } }
    end
    return out
end

Test.it('a loud yellow hat opens: a 16th before it to the next hi-hat hit', function()
    Expect(Spans(Hats(0, 4, { [3] = 110 }), { open_hat_above = 100 }), '0.75-1.5:1', 'one open hit')
    Expect(Spans(Hats(0, 4, { [3] = 100 }), { open_hat_above = 100 }), '', 'at 100 stays closed (above, not at)')
    Expect(Spans(Hats(0, 4, { [3] = 110 }), {}), '', 'option off: no pedal')
end)

Test.it('a run of open hits shares one pedal note', function()
    Expect(Spans(Hats(0, 6, { [3] = 110, [4] = 110, [5] = 110 }), { open_hat_above = 100 }),
           '0.75-2.5:3', 'three open hits, closed by the sixth')
end)

Test.it('no hi-hat hit after: held a quarter note; never back past the previous hit', function()
    Expect(Spans({ { 4, 'Y', vel = { Y = 110 } } }, { open_hat_above = 100 }), '3.75-5:1', 'quarter tail')
    -- 16ths: the lead stops halfway back to the previous hit; the next hit closes it
    -- before the 8th minimum
    local list = { { 0, 'Y' }, { 0.25, 'Y', vel = { Y = 110 } }, { 0.5, 'Y' } }
    Expect(Spans(list, { open_hat_above = 100 }), '0.125-0.5:1', 'tight 16ths')
end)

Test.it('blue hi-hat hits open only with their own option; ride and crashes never open', function()
    local list = { { 0, 'B' }, { 0.5, 'B' }, { 1, 'Y' }, { 1.5, 'Y' } }
    Expect(Spans(list, { blue_hh = true, blue_open = true }), '-0.25-1:2', 'the two blue hits, closed by yellow')
    Expect(Spans(list, { blue_hh = true }), '', 'blue as the hi-hat, option off: closed')
    -- blue as the ride, loud: no pedal; a loud crash: no pedal
    list = { { 0, 'B', vel = { B = 120 } }, { 0.5, 'B', vel = { B = 120 } }, { 4, 'G', vel = { G = 120 } } }
    Expect(Spans(list, { open_hat_above = 100 }), '', 'ride and crash')
end)

Test.it('disco flip: the red gem is the hi-hat, by its velocity', function()
    local list = { { 0, 'R', disco = true }, { 0.5, 'R', disco = true, vel = { R = 110 } },
                   { 1, 'R', disco = true } }
    Expect(Spans(list, { open_hat_above = 100 }), '0.25-1:1', 'disco hat')
end)

Test.it('DrumAnimOnsets keeps each lane\'s velocity', function()
    local onsets = DrumAnimOnsets({ { qn = 0, sec = 0, pitch = 97, vel = 33 },
                                    { qn = 0, sec = 0, pitch = 100, vel = 120 },
                                    { qn = 0, sec = 0, pitch = 96, vel = 5 } }, {}, {})
    local v = onsets[1].vel or {}
    Test.expect(v.R == 33 and v.G == 120 and v.K == nil, 'R 33, G 120, no kick entry')
end)

Test.section('Drums - velocity settings')

if not (r and r.GetProjExtState and LoadSettings) then
    -- offline harness: no REAPER / settings.lua
else
-- LoadSettings from a given saved string (GetProjExtState stubbed, and GetExtState so
-- the tester's own My defaults do not apply; both restored after).
local function LoadFrom(str)
    local real, real_ext = r.GetProjExtState, r.GetExtState
    r.GetProjExtState = function() return 1, str end
    r.GetExtState = function() return '' end
    local ok, err = pcall(LoadSettings)
    r.GetProjExtState, r.GetExtState = real, real_ext
    if not ok then error(err, 0) end
end

Test.it('old project with a soft option on loads threshold 128 (every hit, as before)', function()
    S.drum_anim_soft_snare_below, S.drum_anim_soft_cym_below, S.drum_anim_choke_below = 50, 50, 20
    LoadFrom('v=1;adss=1;adsc=1')
    Test.expect(S.drum_anim_soft_snare_below == 128 and S.drum_anim_soft_cym_below == 128
                and S.drum_anim_choke_below == 0, 'snare 128, crash soft 128, choke 0')
    S.drum_anim_soft_snare_below, S.drum_anim_soft_cym_below = 50, 50
    LoadFrom('v=1;adso=1')
    Test.expect(S.drum_anim_soft_snare_below == 128 and S.drum_anim_soft_cym_below == 128,
                'the older combined adso=1 too')
end)

Test.it('saved thresholds load as saved, clamped to 0-128', function()
    LoadFrom('v=1;adss=1;adsc=1;adsnb=33;adchb=12;adcyb=200')
    Test.expect(S.drum_anim_soft_snare_below == 33 and S.drum_anim_choke_below == 12
                and S.drum_anim_soft_cym_below == 128, 'snare 33, choke 12, crash soft clamped to 128')
    S.drum_anim_soft_snare_below = 50
    LoadFrom('v=1;adss=0')
    Test.expect(S.drum_anim_soft_snare_below == 50, 'option off: threshold untouched')
    S.drum_anim_soft_snare, S.drum_anim_soft_cym = false, false
    S.drum_anim_soft_snare_below, S.drum_anim_soft_cym_below, S.drum_anim_choke_below = 50, 50, 20
end)
end

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
                              r.MIDI_GetPPQPosFromProjQN(take, n[1] + (n[3] or 0.25)), 0, n[2],
                              n[4] or 100, false)
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
            -- This test is about the selection, not the hands: with snare variety on, the
            -- snare 4 QN after the last one is a both-hands accent (26 + 27).
            local variety = S.drum_anim_snare_variety
            S.drum_anim_snare_variety = false
            local ok, err = pcall(GenerateDrumAnimations)
            S.drum_anim_snare_variety = variety
            if not ok then error(err, 0) end
            Expect(Anim(d), '26@4', 'old 30@4 replaced, nothing at 0')
        end)
    end)

    Test.it('gem velocity from the take: ghost snare, choke, soft crash', function()
        WithFixture(function()
            -- snare 30 (ghost) at 0, snare 100 at 4, crash 2 10 (choke) at 8, crash 2 40 (soft) at 12
            local _, d = MakeDrums('PART DRUMS', { { 0, 97, nil, 30 }, { 4, 97, nil, 100 },
                                                   { 8, 100, nil, 10 }, { 12, 100, nil, 40 } })
            local keep = { S.drum_anim_soft_snare, S.drum_anim_soft_snare_below, S.drum_anim_soft_cym,
                           S.drum_anim_choke_below, S.drum_anim_soft_cym_below, S.drum_anim_snare_variety,
                           S.drum_anim_crash }
            S.drum_anim_soft_snare, S.drum_anim_soft_snare_below = true, 50
            S.drum_anim_soft_cym, S.drum_anim_choke_below, S.drum_anim_soft_cym_below = true, 20, 50
            S.drum_anim_snare_variety, S.drum_anim_crash = false, 0
            local ok, err = pcall(GenerateDrumAnimations)
            S.drum_anim_soft_snare, S.drum_anim_soft_snare_below, S.drum_anim_soft_cym,
                S.drum_anim_choke_below, S.drum_anim_soft_cym_below, S.drum_anim_snare_variety,
                S.drum_anim_crash = table.unpack(keep)
            if not ok then error(err, 0) end
            Expect(Anim(d), '26@4 28@0 39@12 40@8', 'ghost, hard, choke, soft')
            Test.expect(S.last_result:find('1 soft snares, 1 soft crashes, 1 chokes', 1, true),
                        'counted in the result: ' .. tostring(S.last_result))
        end)
    end)

    Test.it('open hi-hat: new pedal written, old open-hat 25 replaced, foot-only 25 kept', function()
        WithFixture(function()
            -- yellow hats 8ths 0-1.5, the one at 0.5 loud; an old 25 over the (closed) hat
            -- at 1.5; a foot-only 25 at 4 with no hat hit under it
            local _, d = MakeDrums('PART DRUMS', { { 0, 98 }, { 0.5, 98, nil, 110 }, { 1, 98 }, { 1.5, 98 },
                                                   { 1.4, 25, 0.4 }, { 4, 25, 0.5 } })
            local keep = { S.drum_anim_open_hat, S.drum_anim_open_hat_above, S.drum_anim_blue_hh }
            S.drum_anim_open_hat, S.drum_anim_open_hat_above, S.drum_anim_blue_hh = true, 100, false
            local ok, err = pcall(GenerateDrumAnimations)
            S.drum_anim_open_hat, S.drum_anim_open_hat_above, S.drum_anim_blue_hh = table.unpack(keep)
            if not ok then error(err, 0) end
            local pedal = {}
            for p in Anim(d):gmatch('25@[%d%.]+') do pedal[#pedal + 1] = p end
            Expect(table.concat(pedal, ' '), '25@0.25 25@4', 'new open-hat 25 + the foot-only one')
            Test.expect(S.last_result:find('1 pedal notes (25) over 1 open hits, 1 old open-hat 25s replaced',
                        1, true), 'result: ' .. tostring(S.last_result))
        end)
    end)

    Test.it('open hi-hat options off: pedal notes untouched', function()
        WithFixture(function()
            local _, d = MakeDrums('PART DRUMS', { { 0, 98 }, { 0.5, 98, nil, 110 }, { 0.4, 25, 0.4 } })
            local keep = { S.drum_anim_open_hat, S.drum_anim_blue_hh }
            S.drum_anim_open_hat, S.drum_anim_blue_hh = false, false
            local ok, err = pcall(GenerateDrumAnimations)
            S.drum_anim_open_hat, S.drum_anim_blue_hh = table.unpack(keep)
            if not ok then error(err, 0) end
            Test.expect(Anim(d):find('25@0.4', 1, true), 'the 25 over a hat is kept: ' .. Anim(d))
        end)
    end)

    Test.it('one undo step removes the run', function()
        WithFixture(function()
            local tr, d = MakeDrums('PART DRUMS', { { 0, 96 }, { 1, 97 } })
            FixtureUndoPoint()   -- else the undo below deletes the fixture track too
            GenerateDrumAnimations()
            Test.expect(Anim(d) ~= '', 'notes written')
            r.Undo_DoUndo2(0)
            -- The take pointer can change across undo; read it again.
            Expect(Anim(r.GetActiveTake(r.GetTrackMediaItem(tr, 0))), '', 'after undo')
        end)
    end)
end
