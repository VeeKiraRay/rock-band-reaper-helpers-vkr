-- Unit tests for lib/reaper_chord_detect.lua - chord names from a keys recording (the
-- Instrument Helper's Keys > Tuner). Pure; synthetic tones and hand-built chroma, no REAPER.

local SR = CHORD_SR
local N  = CHORD_FRAME_N

local function Hz(p) return 440 * 2 ^ ((p - 69) / 12) end

-- A piano-like tone: eight partials falling off as 1/k, fixed phases so runs are repeatable.
local function Tone(pitch, amp, n, cents)
    local f = Hz(pitch) * 2 ^ ((cents or 0) / 1200)
    local out = {}
    for i = 1, n do
        local t = (i - 1) / SR
        local s = 0
        for k = 1, 8 do s = s + math.sin(2 * math.pi * k * f * t + 0.7 * k) / k end
        out[i] = amp * s
    end
    return out
end

local function Chord(pitches, cents)
    local out = {}
    for i = 1, N do out[i] = 0 end
    for _, p in ipairs(pitches) do
        local t = Tone(p, 0.15, N, cents)
        for i = 1, N do out[i] = out[i] + t[i] end
    end
    return out
end

-- A chroma vector from pitch-class weights { [pc] = w }.
local function Raw(w)
    local c = {}
    for i = 0, 11 do c[i] = w[i] or 0 end
    return c
end

local function Top(raw, opts)
    local list, margin = ChordRank(raw, opts)
    return list and ChordName(list[1]), list, margin
end

local function Names(list)
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = ChordName(t) end
    return table.concat(out, ' ')
end

Test.section('Chord detect - frames')

Test.it('a C major triad reads as C', function()
    local name, list = Top(ChordFrameChroma(Chord({ 60, 64, 67 }), 0), { plain = true })
    Test.expect(name == 'C', 'got ' .. Names(list))
end)

Test.it('an A minor triad reads as Am', function()
    local name, list = Top(ChordFrameChroma(Chord({ 57, 60, 64 }), 0), { plain = true })
    Test.expect(name == 'Am', 'got ' .. Names(list))
end)

Test.it('a song tuned 30 cents sharp still reads right with its offset', function()
    local name, list = Top(ChordFrameChroma(Chord({ 62, 66, 69 }, 30), 30), { plain = true })
    Test.expect(name == 'D', 'got ' .. Names(list))
end)

Test.it('a played 7th wins without "prefer plain chords" and stays in the top 3 with it', function()
    local raw = ChordFrameChroma(Chord({ 55, 59, 62, 65 }), 0)
    local name, list = Top(raw, { plain = false })
    Test.expect(name == 'G7', 'plain off: ' .. Names(list))
    local _, plist = Top(raw, { plain = true })
    Test.expect(Names(plist):find('G7', 1, true) ~= nil, 'plain on, top 3: ' .. Names(plist))
end)

Test.it('silence gives no chroma, an empty sum no ranking', function()
    local quiet = {}
    for i = 1, N do quiet[i] = 0 end
    Test.expect(ChordFrameChroma(quiet, 0) == nil, 'nil for silence')
    Test.expect(ChordRank(ChordSumNew(), {}) == nil, 'nil for an empty sum')
end)

Test.it('sums count only real frames', function()
    local s = ChordSumNew()
    ChordSumAdd(s, Raw({ [0] = 1 }))
    ChordSumAdd(s, nil)
    ChordSumAdd(s, Raw({ [0] = 2, [4] = 1 }))
    Test.expect(s.n == 2 and s[0] == 3 and s[4] == 1, ('n %d, C %g, E %g'):format(s.n, s[0], s[4]))
end)

Test.section('Chord detect - ranking rules')

Test.it('"prefer plain chords" turns a faint 7th back into the triad', function()
    local raw = Raw({ [0] = 1, [4] = 1, [7] = 1, [11] = 0.5 })    -- C E G + half a B
    Test.expect(Top(raw, { plain = false }) == 'Cmaj7', 'off: ' .. tostring(Top(raw, { plain = false })))
    Test.expect(Top(raw, { plain = true }) == 'C', 'on: ' .. tostring(Top(raw, { plain = true })))
end)

Test.it('the key prior decides between C and Cm', function()
    local raw = Raw({ [0] = 1, [7] = 1, [4] = 0.5, [3] = 0.5 })   -- C G, E and Eb alike
    Test.expect(Top(raw, { plain = true, key_mask = ChordKeyMask(0, false) }) == 'C', 'in C major')
    Test.expect(Top(raw, { plain = true, key_mask = ChordKeyMask(0, true) }) == 'Cm', 'in C minor')
end)

Test.it('the bass prior decides between C and Am', function()
    local raw = Raw({ [0] = 1, [4] = 1, [7] = 0.5, [9] = 0.5 })   -- C E, G and A alike
    Test.expect(Top(raw, { plain = true, bass = 0 }) == 'C', 'bass C')
    Test.expect(Top(raw, { plain = true, bass = 9 }) == 'Am', 'bass A')
end)

Test.it('the margin is best minus second', function()
    local raw = Raw({ [0] = 1, [4] = 1, [7] = 1 })
    local _, list, margin = Top(raw, { plain = true })
    Test.expect(ChordName(list[1]) == 'C' and margin > 0.1, ('%s, margin %.3f'):format(ChordName(list[1]), margin))
end)

Test.section('Chord detect - keys, names, display')

Test.it('key masks: C major, and A minor with its raised 7th', function()
    local function Pcs(mask)
        local t = {}
        for pc = 0, 11 do if mask & (1 << pc) ~= 0 then t[#t + 1] = pc end end
        return table.concat(t, ',')
    end
    Test.expect(Pcs(ChordKeyMask(0, false)) == '0,2,4,5,7,9,11', Pcs(ChordKeyMask(0, false)))
    Test.expect(Pcs(ChordKeyMask(9, true)) == '0,2,4,5,7,8,9,11', Pcs(ChordKeyMask(9, true)))
end)

Test.it('confidence bands', function()
    Test.expect(ChordConfidence(0.12) == 'clear' and ChordConfidence(0.07) == 'likely'
        and ChordConfidence(0.03) == 'maybe' and ChordConfidence(0.01) == 'unsure', 'bands')
end)

Test.it('the triad above a 7th chord\'s root', function()
    local function Upper(mask)
        local t = ChordUpperTriad(ChordTemplateForMask(mask))
        return t and ChordName(t) or 'none'
    end
    local am7 = (1 << 9) | (1 << 0) | (1 << 4) | (1 << 7)
    local cmaj7 = (1 << 0) | (1 << 4) | (1 << 7) | (1 << 11)
    local g7 = (1 << 7) | (1 << 11) | (1 << 2) | (1 << 5)
    local c = (1 << 0) | (1 << 4) | (1 << 7)
    Test.expect(Upper(am7) == 'C', 'Am7 -> ' .. Upper(am7))
    Test.expect(Upper(cmaj7) == 'Em', 'Cmaj7 -> ' .. Upper(cmaj7))
    Test.expect(Upper(g7) == 'Bdim', 'G7 -> ' .. Upper(g7))
    Test.expect(Upper(c) == 'none', 'C -> ' .. Upper(c))
end)

Test.it('notes in chord order from the root', function()
    local dm = ChordTemplateForMask((1 << 2) | (1 << 5) | (1 << 9))
    local am7 = ChordTemplateForMask((1 << 9) | (1 << 0) | (1 << 4) | (1 << 7))
    Test.expect(ChordNotes(dm) == 'D+F+A', ChordNotes(dm))
    Test.expect(ChordNotes(am7) == 'A+C+E+G', ChordNotes(am7))
end)

Test.it('names over the bass', function()
    local c = ChordTemplateForMask((1 << 0) | (1 << 4) | (1 << 7))
    Test.expect(ChordNameOverBass(c, nil) == 'C' and ChordNameOverBass(c, 0) == 'C', 'root / unknown')
    Test.expect(ChordNameOverBass(c, 4) == 'C/E', ChordNameOverBass(c, 4))
    Test.expect(ChordNameOverBass(c, 9) == 'C (bass A)', ChordNameOverBass(c, 9))
end)

Test.section('Chord detect - passage check (single notes or chords)')

-- A passage of struck notes: { onset seconds, { pitches } }, each decaying, as frames every
-- CHORD_PASS_HOP_S (three before the passage, one after) through ChordFrameAnalyse.
local function PassageFrames(events)
    local function At(t)
        local s = 0
        for _, ev in ipairs(events) do
            local dt = t - ev[1]
            if dt >= 0 then
                local env = math.exp(-4 * dt)
                for _, p in ipairs(ev[2]) do
                    local f = Hz(p)
                    for k = 1, 8 do s = s + env * math.sin(2 * math.pi * k * f * dt + 0.7 * k) / k end
                end
            end
        end
        return 0.1 * s
    end
    local frames = {}
    for g = -3, CHORD_PASS_FRAMES do
        local t0 = 0.3 + g * CHORD_PASS_HOP_S
        local mono = {}
        for i = 1, N do mono[i] = At(t0 + (i - 1) / SR) end
        local _, sal = ChordFrameAnalyse(mono, 0)
        frames[#frames + 1] = sal or false
    end
    return frames
end

Test.it('a melody of single notes reads as single notes, naming the struck notes', function()
    local line, events = { 60, 64, 67, 65, 62, 60, 71, 72, 69, 67, 65, 64, 62, 60 }, {}
    for i, p in ipairs(line) do events[#events + 1] = { 0.3 + 0.28 * i, { p } } end
    local res = ChordPassage(PassageFrames(events))
    Test.expect(#res.onsets >= 8, 'onsets found: ' .. #res.onsets)
    Test.expect(res.single == true, ('single notes, value %s'):format(tostring(res.value)))
    local right = 0
    for _, o in ipairs(res.onsets) do
        for _, p in ipairs(line) do if o.note and o.note % 12 == p % 12 then right = right + 1; break end end
    end
    Test.expect(right >= #res.onsets * 0.7, ('%d of %d struck notes are melody notes'):format(right, #res.onsets))
end)

Test.it('changing triads read as chords', function()
    local seq = { { 60, 64, 67 }, { 57, 60, 64 }, { 53, 57, 60 }, { 55, 59, 62 } }
    local events = {}
    for i = 1, 8 do events[#events + 1] = { 0.3 + 0.5 * i, seq[(i - 1) % 4 + 1] } end
    local res = ChordPassage(PassageFrames(events))
    Test.expect(#res.onsets >= 4, 'onsets found: ' .. #res.onsets)
    Test.expect(res.single == false, ('chords, value %s'):format(tostring(res.value)))
end)

Test.it('a silent passage finds no key presses', function()
    local frames = {}
    for i = 1, CHORD_PASS_FRAMES + 4 do frames[i] = false end
    local res = ChordPassage(frames)
    Test.expect(#res.onsets == 0 and res.value == nil and res.single == nil, 'no verdict')
end)

Test.it('the chroma from ChordFrameAnalyse equals ChordFrameChroma', function()
    local mono = Chord({ 60, 64, 67 })
    local a = ChordFrameChroma(mono, 0)
    local b = ChordFrameAnalyse(mono, 0)
    local same = true
    for i = 0, 11 do if a[i] ~= b[i] then same = false end end
    Test.expect(same, 'identical')
end)

Test.section('Chord detect - bass stem')

Test.it('a low A and a low E read as their pitch classes', function()
    Test.expect(ChordBassPc(Tone(33, 0.3, CHORD_BASS_N), 0) == 9, 'A1 (55 Hz)')
    Test.expect(ChordBassPc(Tone(28, 0.3, CHORD_BASS_N), 0) == 4, 'E1 (41 Hz)')
end)

Test.it('silence gives no bass reading', function()
    local quiet = {}
    for i = 1, CHORD_BASS_N do quiet[i] = 0 end
    Test.expect(ChordBassPc(quiet, 0) == nil, 'nil')
end)

Test.it('bass vote: commonest class, a tie to the first to reach it', function()
    Test.expect(ChordBassVote({ 9, 4, 9 }) == 9, 'commonest')
    Test.expect(ChordBassVote({ 4, 9 }) == 4, 'tie')
    Test.expect(ChordBassVote({}) == nil, 'empty')
end)
