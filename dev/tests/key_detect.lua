-- Unit tests for lib/reaper_key_detect.lua and the generated lib/reaper_key_profiles.lua -
-- the Metadata > Song key suggestion. Pure; no REAPER objects.

-- A note list from { pitch, length in QN } pairs played one after another. Bar lines every
-- 4 QN.
local function Melody(seq, transpose)
    local out, qn = {}, 0
    for _, x in ipairs(seq) do
        out[#out + 1] = { pitch = x[1] + (transpose or 0), qn = qn, len = x[2],
                          down = qn % 4 < 1e-9 }
        qn = qn + x[2]
    end
    return out
end

-- Repeat a phrase n times.
local function Times(seq, n)
    local out = {}
    for _ = 1, n do for _, x in ipairs(seq) do out[#out + 1] = x end end
    return out
end

-- C major: home on C, leaning on the triad, ending on C. 4 bars, repeated.
local C_MAJOR = Times({
    { 60, 2 }, { 64, 1 }, { 67, 1 },   { 65, 1 }, { 64, 1 }, { 62, 1 }, { 64, 1 },
    { 67, 2 }, { 69, 1 }, { 67, 1 },   { 65, 1 }, { 62, 1 }, { 71, 1 }, { 72, 1 },
    { 60, 4 },
}, 4)

-- A minor: home on A, leaning on A C E, ending on A.
local A_MINOR = Times({
    { 57, 2 }, { 60, 1 }, { 64, 1 },   { 62, 1 }, { 60, 1 }, { 59, 1 }, { 60, 1 },
    { 64, 2 }, { 65, 1 }, { 64, 1 },   { 62, 1 }, { 59, 1 }, { 56, 1 }, { 57, 1 },
    { 57, 4 },
}, 4)

local VOCALS_SET = KEY_RESULT_SETS[1]
local HARM_SET   = KEY_RESULT_SETS[2]
local KEYS_SET   = KEY_RESULT_SETS[3]

local function Top(parts, set)
    local ranked = KeyRankSet(KeyFeatures(parts), set or VOCALS_SET, RB_KEY_PROFILES.sources)
    return ranked and ranked[1], ranked
end

----------------------------------------------------------------------
Test.section('Names and relations')

Test.it('KeyName spells sharps and flats', function()
    Test.expect(KeyName(0, false) == 'C major', KeyName(0, false))
    Test.expect(KeyName(6, false) == 'F#/Gb major', KeyName(6, false))
    Test.expect(KeyName(9, true) == 'A minor', KeyName(9, true))
end)

Test.it('KeyRelation finds relative, parallel and fifth', function()
    Test.expect(KeyRelation(0, false, 9, true) == 'relative', 'C major / A minor')
    Test.expect(KeyRelation(9, true, 0, false) == 'relative', 'A minor / C major')
    Test.expect(KeyRelation(0, false, 0, true) == 'parallel', 'C major / C minor')
    Test.expect(KeyRelation(0, false, 7, false) == 'fifth', 'C / G')
    Test.expect(KeyRelation(0, false, 5, false) == 'fifth', 'C / F')
    Test.expect(KeyRelation(0, false, 2, false) == nil, 'C / D')
    Test.expect(KeyRelation(0, false, 4, true) == nil, 'C major / E minor')
end)

----------------------------------------------------------------------
Test.section('Scales')

local function ScaleNames(tonic, minor)
    local out = {}
    for i, s in ipairs((KeyScale(tonic, minor))) do out[i] = s.name end
    return table.concat(out, ' ')
end

Test.it('scales are spelled one letter per degree', function()
    local cases = {
        { 0, false, 'C D E F G A B' },
        { 9, true,  'A B C D E F G' },
        { 6, false, 'F# G# A# B C# D# E#' },
        { 1, false, 'Db Eb F Gb Ab Bb C' },
        { 3, true,  'Eb F Gb Ab Bb Cb Db' },
        { 8, true,  'G# A# B C# D# E F#' },
    }
    for _, c in ipairs(cases) do
        local got = ScaleNames(c[1], c[2])
        Test.expect(got == c[3], KeyName(c[1], c[2]) .. ': ' .. got)
    end
end)

Test.it('every key uses seven different letters and no double accidentals', function()
    for tonic = 0, 11 do
        for _, minor in ipairs({ false, true }) do
            local letters = {}
            for _, s in ipairs((KeyScale(tonic, minor))) do
                letters[s.name:sub(1, 1)] = true
                Test.expect(not s.name:find('##') and not s.name:find('bb') and not s.name:find('?', 1, true),
                    KeyName(tonic, minor) .. ': ' .. s.name)
            end
            local n = 0
            for _ in pairs(letters) do n = n + 1 end
            Test.expect(n == 7, KeyName(tonic, minor) .. ' uses ' .. n .. ' letters')
        end
    end
end)

Test.it('KeyScaleText lists the key notes on one line', function()
    Test.expect(KeyScaleText(9, true) == 'A  B  C  D  E  F  G', KeyScaleText(9, true))
end)

----------------------------------------------------------------------
Test.section('Track report')

Test.it('KeyTrackReport counts the notes outside the key, with their bars', function()
    -- A minor melody: its phrase has one G# (the raised 7th), x4 repeats, no bar numbers.
    -- Plus two more G# in bars 3 and 9 (bar 9 twice) and one C#.
    local v = Melody(A_MINOR)
    v[#v + 1] = { pitch = 68, bar = 3 }
    v[#v + 1] = { pitch = 56, bar = 9 }
    v[#v + 1] = { pitch = 56, bar = 9 }
    v[#v + 1] = { pitch = 61, bar = 9 }
    local rep = KeyTrackReport(v, 9, true)

    Test.expect(rep.total == #v, 'total ' .. rep.total)
    Test.expect(#rep.outside == 2, 'two notes outside: ' .. #rep.outside)
    local g = rep.outside[1]
    Test.expect(g.name == 'G#' and g.n == 7, 'G# x7 first, got ' .. g.name .. ' x' .. g.n)
    Test.expect(#g.bars == 2 and g.bars[1] == 3 and g.bars[2] == 9, 'bars 3, 9 once each')
    Test.expect(rep.outside[2].name == 'C#' and rep.outside[2].n == 1, 'then C# x1')
    Test.expect(math.abs(rep.share_out - 8 / #v) < 1e-9, 'share_out ' .. rep.share_out)
    -- The melody has G# where the scale has G, so it uses 6 of the 7.
    Test.expect(rep.used == 6, 'uses 6 key notes, got ' .. rep.used)
end)

Test.it('used counts only key notes with a real share of the track', function()
    -- 60 notes on A C E, one stray B: B is under 2%, so 3 notes used.
    local notes = {}
    for i = 1, 60 do notes[i] = { pitch = ({ 57, 60, 64 })[i % 3 + 1] } end
    notes[#notes + 1] = { pitch = 59 }
    local rep = KeyTrackReport(notes, 9, true)
    Test.expect(rep.used == 3, 'used ' .. rep.used)
    Test.expect(rep.used <= KEY_FEW_NOTES, 'flags as few')
end)

Test.it('notes outside a flat key are spelled with flats', function()
    local rep = KeyTrackReport({ { pitch = 66 } }, 5, false)   -- F#/Gb against F major
    Test.expect(rep.outside[1].name == 'Gb', 'got ' .. rep.outside[1].name)
end)

Test.it('an empty track reports nothing', function()
    local rep = KeyTrackReport({}, 0, false)
    Test.expect(rep.total == 0 and rep.share_out == 0 and #rep.outside == 0, 'empty')
end)

----------------------------------------------------------------------
Test.section('Result set labels')

Test.it('a label names only the parts that were read', function()
    local v = Melody(C_MAJOR)
    local f = KeyFeatures({ vocals = v, keys = v })   -- no harmonies
    Test.expect(KeySetLabel(KEY_RESULT_SETS[3], f) == 'PART VOCALS + Pro Keys',
        KeySetLabel(KEY_RESULT_SETS[3], f))
    Test.expect(KeySetLabel(KEY_RESULT_SETS[4], f) == KEY_RESULT_SETS[4].label, 'fixed label')
    local fh = KeyFeatures({ vocals = v, harm = v, keys = v })
    Test.expect(KeySetLabel(KEY_RESULT_SETS[3], fh) == 'PART VOCALS + harmonies + Pro Keys',
        KeySetLabel(KEY_RESULT_SETS[3], fh))
end)

Test.it('Pro Keys only reads the keys and ignores the vocals', function()
    -- Vocals say A minor, keys say C major: the keys-only set must follow the keys.
    local top = Top({ vocals = Melody(A_MINOR), keys = Melody(C_MAJOR) }, KEY_RESULT_SETS[4])
    Test.expect(top.tonic == 0 and not top.minor, 'got ' .. KeyName(top.tonic, top.minor))
end)

----------------------------------------------------------------------
Test.section('Unpitched lyrics')

Test.it('# and #$ mark a note unpitched; ^ and plain lyrics do not', function()
    Test.expect(KeyLyricIsUnpitched('yeah#'), 'yeah#')
    Test.expect(KeyLyricIsUnpitched('yeah#$'), 'yeah#$')
    Test.expect(not KeyLyricIsUnpitched('yeah'), 'yeah')
    Test.expect(not KeyLyricIsUnpitched('yeah^'), 'yeah^ is pitch-forgiving, still pitched')
    Test.expect(not KeyLyricIsUnpitched(nil), 'no lyric')
end)

----------------------------------------------------------------------
Test.section('Generated profiles')

Test.it('every source has a major and a minor profile that sums to 1', function()
    Test.expect(RB_KEY_PROFILES_SCHEMA == 1, 'schema ' .. tostring(RB_KEY_PROFILES_SCHEMA))
    for _, name in ipairs(KEY_SOURCES) do
        local p = RB_KEY_PROFILES.sources[name]
        Test.expect(p, 'missing source ' .. name)
        for m = 0, 1 do
            local s = 0
            for i = 1, 12 do s = s + p[m][i] end
            Test.expect(math.abs(s - 1) < 0.01, ('%s[%d] sums to %.4f'):format(name, m, s))
        end
    end
end)

Test.it('the tonic is the strongest pitch class in the vocal profiles', function()
    for m = 0, 1 do
        local p = RB_KEY_PROFILES.sources.V[m]
        for i = 2, 12 do
            Test.expect(p[1] > p[i], ('V[%d]: index %d beats the tonic'):format(m, i))
        end
    end
end)

----------------------------------------------------------------------
Test.section('Ranking')

Test.it('a C major melody comes out C major', function()
    local top = Top({ vocals = Melody(C_MAJOR) })
    Test.expect(top.tonic == 0 and not top.minor, 'got ' .. KeyName(top.tonic, top.minor))
end)

Test.it('an A minor melody comes out A minor', function()
    local top = Top({ vocals = Melody(A_MINOR) })
    Test.expect(top.tonic == 9 and top.minor, 'got ' .. KeyName(top.tonic, top.minor))
end)

Test.it('transposing the melody moves the tonic by the same amount', function()
    for shift = 1, 11 do
        local top = Top({ vocals = Melody(C_MAJOR, shift) })
        Test.expect(top.tonic == shift and not top.minor,
            ('+%d: got %s'):format(shift, KeyName(top.tonic, top.minor)))
    end
end)

Test.it('all 24 keys are ranked, best first, scores within -1..1', function()
    local _, ranked = Top({ vocals = Melody(C_MAJOR) })
    Test.expect(#ranked == 24, '#ranked ' .. #ranked)
    for i = 1, 24 do
        Test.expect(ranked[i].score >= -1 - 1e-9 and ranked[i].score <= 1 + 1e-9, 'score range')
        if i > 1 then Test.expect(ranked[i - 1].score >= ranked[i].score, 'not sorted at ' .. i) end
    end
end)

Test.it('Pro Keys chords on A minor pull an ambiguous melody to A minor', function()
    -- A melody on C E G A only - fits C major and A minor alike.
    local amb = Melody(Times({ { 64, 1 }, { 67, 1 }, { 69, 1 }, { 60, 1 } }, 16))
    local chords, qn = {}, 0
    for _ = 1, 16 do
        for _, p in ipairs({ 57, 60, 64 }) do   -- A minor triad, A in the bass
            chords[#chords + 1] = { pitch = p, qn = qn, len = 4, down = true }
        end
        qn = qn + 4
    end
    local top = Top({ vocals = amb, keys = chords }, KEYS_SET)
    Test.expect(top.tonic == 9 and top.minor, 'got ' .. KeyName(top.tonic, top.minor))
end)

----------------------------------------------------------------------
Test.section('Unavailable result sets')

Test.it('too few pitched vocal notes -> no_vocals', function()
    local few = Melody({ { 60, 1 }, { 62, 1 }, { 64, 1 } })
    local ranked, why = KeyRankSet(KeyFeatures({ vocals = few }), VOCALS_SET, RB_KEY_PROFILES.sources)
    Test.expect(ranked == nil and why == 'no_vocals', tostring(why))
end)

Test.it('the harmony set needs harmony notes', function()
    local ranked, why = KeyRankSet(KeyFeatures({ vocals = Melody(C_MAJOR) }), HARM_SET,
                                   RB_KEY_PROFILES.sources)
    Test.expect(ranked == nil and why == 'no_harm', tostring(why))
end)

Test.it('the Pro Keys set needs Pro Keys notes', function()
    local ranked, why = KeyRankSet(KeyFeatures({ vocals = Melody(C_MAJOR) }), KEYS_SET,
                                   RB_KEY_PROFILES.sources)
    Test.expect(ranked == nil and why == 'no_keys', tostring(why))
end)

Test.it('Pro Keys alone still gives a key when the vocals are all unpitched', function()
    local top = Top({ vocals = {}, keys = Melody(C_MAJOR) }, KEYS_SET)
    Test.expect(top and top.tonic == 0 and not top.minor,
        top and ('got ' .. KeyName(top.tonic, top.minor)) or 'no result')
end)

----------------------------------------------------------------------
Test.section('Vocal audio')

-- Mono samples at KEY_AUDIO_SR for a melody of { pitch, QN } pairs, 0.25 s per QN,
-- each note a sine with a short gap after it.
local function Tones(seq)
    local sr, out = KEY_AUDIO_SR, {}
    for _, x in ipairs(seq) do
        local f = 440 * 2 ^ ((x[1] - 69) / 12)
        local n = math.floor(x[2] * 0.25 * sr)
        for i = 1, n do out[#out + 1] = 0.5 * math.sin(2 * math.pi * f * i / sr) end
        for _ = 1, math.floor(0.02 * sr) do out[#out + 1] = 0 end
    end
    return out
end

Test.it('a held sine comes back as its own note', function()
    local notes = KeyAudioNotes(Tones({ { 69, 4 } }), KEY_AUDIO_SR, 0)
    Test.expect(#notes == 1, 'one note, got ' .. #notes)
    Test.expect(notes[1] and notes[1].pitch == 69, 'A4 = 69, got ' .. tostring(notes[1] and notes[1].pitch))
    Test.expect(notes[1] and math.abs(notes[1].len - 1.0) < 0.1, 'about 1 s long')
end)

Test.it('silence gives no notes', function()
    local s = {}
    for i = 1, KEY_AUDIO_SR * 2 do s[i] = 0 end
    local notes, stats = KeyAudioNotes(s, KEY_AUDIO_SR, 0)
    Test.expect(#notes == 0 and stats.voiced == 0, #notes .. ' notes')
end)

Test.it('notes start at t0 plus their place in the recording', function()
    local notes = KeyAudioNotes(Tones({ { 60, 2 }, { 64, 2 } }), KEY_AUDIO_SR, 10)
    Test.expect(#notes == 2 and notes[1].qn >= 10 and notes[2].qn > notes[1].qn + 0.4,
        'two notes after t0 = 10')
end)

Test.it('a C major melody played as tones comes out C major', function()
    local notes = KeyAudioNotes(Tones(C_MAJOR), KEY_AUDIO_SR, 0)
    local ranked = KeyRankSet(KeyFeatures({ vocals = notes }), KEY_AUDIO_SET, RB_KEY_PROFILES.sources)
    Test.expect(ranked, 'ranked')
    local top = ranked[1]
    Test.expect(top.tonic == 0 and not top.minor, 'got ' .. KeyName(top.tonic, top.minor))
end)

Test.it('analysing in small steps gives the same notes as one pass', function()
    local s = Tones(Times({ { 60, 2 }, { 64, 1 }, { 67, 1 } }, 4))
    local whole = KeyAudioNotes(s, KEY_AUDIO_SR, 0)
    local st = KeyAudioStart(s, KEY_AUDIO_SR, 0)
    local last, steps = -1, 0
    while not KeyAudioStep(st, 3) do
        local p = KeyAudioProgress(st)
        Test.expect(p >= last and p <= 1, 'progress goes forward, got ' .. p .. ' after ' .. last)
        last, steps = p, steps + 1
    end
    Test.expect(steps > 10, 'took several steps: ' .. steps)
    Test.expect(KeyAudioProgress(st) == 1, 'finished at 1')
    local stepped = KeyAudioFinish(st)
    Test.expect(#stepped == #whole, ('%d notes vs %d'):format(#stepped, #whole))
    for i, n in ipairs(whole) do
        local m = stepped[i]
        Test.expect(m and m.pitch == n.pitch and m.qn == n.qn and m.len == n.len, 'note ' .. i .. ' differs')
    end
end)

Test.it('the bass settings hear a low E that the vocal settings cannot', function()
    local low_e = Tones({ { 28, 8 } })   -- E1, 41 Hz
    local bass = KeyAudioNotes(low_e, KEY_AUDIO_SR, 0, KEY_AUDIO_BASS)
    Test.expect(#bass >= 1 and bass[1].pitch % 12 == 4, 'bass: an E, got ' ..
        tostring(bass[1] and bass[1].pitch))
    local vocal = KeyAudioNotes(low_e, KEY_AUDIO_SR, 0)
    for _, n in ipairs(vocal) do
        Test.expect(n.pitch >= 40, 'vocal settings report nothing below 80 Hz, got ' .. n.pitch)
    end
end)

Test.it('KeyAudioPickSet uses both stems when each has enough notes', function()
    local enough, few = KEY_MIN_NOTES, KEY_MIN_NOTES - 1
    Test.expect(KeyAudioPickSet(enough, enough) == KEY_AUDIO_SETS.both, 'both')
    Test.expect(KeyAudioPickSet(enough, few) == KEY_AUDIO_SETS.vocal, 'vocal only')
    Test.expect(KeyAudioPickSet(0, enough) == KEY_AUDIO_SETS.bass, 'bass only')
    Test.expect(KeyAudioPickSet(few, few) == nil, 'neither')
end)

Test.it('a bass line on A pulls an ambiguous vocal to A minor', function()
    -- Vocal on C E G A only (fits C major and A minor); bass walks A - E - A - C.
    local vocal = KeyAudioNotes(Tones(Times({ { 64, 1 }, { 67, 1 }, { 69, 1 }, { 60, 1 } }, 16)),
                                KEY_AUDIO_SR, 0)
    local bass = KeyAudioNotes(Tones(Times({ { 33, 4 }, { 40, 2 }, { 33, 4 }, { 36, 2 } }, 6)),
                               KEY_AUDIO_SR, 0, KEY_AUDIO_BASS)
    local set = KeyAudioPickSet(#vocal, #bass)
    Test.expect(set == KEY_AUDIO_SETS.both, 'both stems used')
    local ranked = KeyRankSet(KeyFeatures({ vocals = vocal, keys = bass }), set, RB_KEY_PROFILES.sources)
    local top = ranked and ranked[1]
    Test.expect(top and top.tonic == 9 and top.minor,
        'got ' .. (top and KeyName(top.tonic, top.minor) or 'nothing'))
end)

----------------------------------------------------------------------
Test.section('Confidence and fitting')

Test.it('KeyConfidence follows the score lead', function()
    local function R(a, b) return { { score = a }, { score = b } } end
    -- Leads measured from 0 so each margin is exact (0.9 - (0.9 - x) is not x in floats).
    Test.expect(KeyConfidence(R(KEY_CLEAR_MARGIN, 0)) == 'clear', 'clear')
    Test.expect(KeyConfidence(R(KEY_CLOSE_MARGIN, 0)) == 'fair', 'fair')
    Test.expect(KeyConfidence(R(KEY_CLOSE_MARGIN / 2, 0)) == 'close', 'close')
end)

Test.it('KeyFitProfiles rotates each song to its tonic', function()
    -- One D major song and one E minor song, each a single note on the tonic.
    local songs = {
        { features = KeyFeatures({ vocals = Melody({ { 62, 1 } }) }), tonic = 2, minor = false },
        { features = KeyFeatures({ vocals = Melody({ { 64, 1 } }) }), tonic = 4, minor = true },
    }
    local p = KeyFitProfiles(songs)
    Test.expect(p.V and p.V[0][1] == 1 and p.V[1][1] == 1, 'tonic should hold all the weight')
    Test.expect(p.H == nil, 'a source no song has gets no profile')
end)
