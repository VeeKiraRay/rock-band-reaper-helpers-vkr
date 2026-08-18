-- Unit tests for the vocal difficulty scorer (dev/calibration/difficulty_score_vocals.lua):
-- ScoreVocalChart, VocalClassifyLyric, VocalPitchClassDistance, VocalSubtractPercussion.
--
-- Pure functions over plain tables - no project, no MIDI editor, no REAPER API. Each
-- test asserts a BEHAVIOUR the design claims, not a magic number, so the cases survive
-- re-tuning: "an octave leap is the easiest interval", "a '+' note is not a syllable",
-- "a short note only counts as hard when the pitch moves".

----------------------------------------------------------------------
-- Chart builders
----------------------------------------------------------------------

-- One note at quarter-note position `qn`, `len` quarter notes long, at 120 bpm so one
-- quarter note is 0.5 s. lyric defaults to an ordinary syllable.
local function VNote(qn, pitch, lyric, len)
    len = len or 0.5
    return {
        s = qn * 0.5, e = (qn + len) * 0.5,
        qn = qn, qn_e = qn + len,
        pitch = pitch, lyric = lyric or 'la',
    }
end

-- n notes at qn_step spacing. pitch_fn/lyric_fn take the 1-based index.
local function VRun(n, qn_step, pitch_fn, lyric_fn, len)
    local out = {}
    for i = 1, n do
        out[i] = VNote((i - 1) * qn_step,
                       pitch_fn and pitch_fn(i) or 60,
                       lyric_fn and lyric_fn(i) or 'la',
                       len)
    end
    return out
end

local function VSpanAll(notes)
    return { { s = notes[1].s, e = notes[#notes].e } }
end

----------------------------------------------------------------------
Test.section('Vocals - lyric classification')

Test.it('the talkie marker is the LAST character, after any hyphen', function()
    -- The authoring doc places the hyphen BEFORE the # or ^ ("cow-#", "ard-^"), so a
    -- parser that looks at the first suffix character, or splits on '-' first,
    -- misclassifies every hyphenated talkie. The corpus has thousands.
    Test.expect(VocalClassifyLyric('cow-#') == 'hash', 'cow-# is a talkie')
    Test.expect(VocalClassifyLyric('ard-^') == 'caret', 'ard-^ is a generous talkie')
    Test.expect(VocalClassifyLyric('All#') == 'hash', 'All# is a talkie')
    Test.expect(VocalClassifyLyric('Hel-') == 'syllable', 'a bare hyphen is just a syllable')
    Test.expect(VocalClassifyLyric('Ex=') == 'syllable', 'an equals is just a syllable')
    Test.expect(VocalClassifyLyric('Yeah') == 'syllable', 'a plain word is a syllable')
end)

Test.it('a bare + is a continuation, not a syllable', function()
    Test.expect(VocalClassifyLyric('+') == 'plus', 'plus is its own class')
    Test.expect(VocalClassifyLyric('+ ') == 'plus', 'trailing space tolerated')
end)

Test.it('a missing lyric degrades to a syllable rather than erroring', function()
    Test.expect(VocalClassifyLyric(nil) == 'syllable', 'nil is a syllable')
end)

Test.it('the classifier CANNOT recognise an animation state, by design', function()
    -- `[intense]#` is a real corpus event and classifies as a talkie here, which is
    -- correct behaviour for this function and exactly why the READER must filter by
    -- tick alignment rather than by content. Asserted so nobody later "fixes" the
    -- classifier and assumes the reader is therefore safe.
    Test.expect(VocalClassifyLyric('[intense]#') == 'hash',
        'the classifier is content-blind - tick alignment is what protects us')
end)

----------------------------------------------------------------------
Test.section('Vocals - the octave trap')

Test.it('an octave apart is distance 0, a semitone is 1, a tritone is 6', function()
    -- The single claim the whole vocal factor set rests on: the game scores pitch
    -- CLASS, so the same note name an octave up needs no movement at all.
    Test.expect(VocalPitchClassDistance(72, 60) == 0, 'C4 to C5 is zero distance')
    Test.expect(VocalPitchClassDistance(61, 60) == 1, 'a semitone is 1')
    Test.expect(VocalPitchClassDistance(66, 60) == 6, 'a tritone is 6, the maximum')
    Test.expect(VocalPitchClassDistance(71, 60) == 1, 'a major 7th up is 1, not 11')
    Test.expect(VocalPitchClassDistance(60, 71) == 1, 'and it is symmetric')
end)

Test.it('an octave-leap melody reads easier than a semitone melody', function()
    -- The end-to-end version of the same claim, and the reason the raw-semitone twin
    -- exists as a declared substitution: the two measures disagree in OPPOSITE
    -- directions on these two charts.
    local oct  = VRun(12, 1.0, function(i) return (i % 2 == 0) and 60 or 72 end)
    local semi = VRun(12, 1.0, function(i) return 60 + (i % 2) end)
    local a = ScoreVocalChart(oct,  VSpanAll(oct))
    local b = ScoreVocalChart(semi, VSpanAll(semi))
    Test.expect(a.pc_interval_mean == 0, 'octave leaps cost nothing in pitch-class space')
    Test.expect(b.pc_interval_mean == 1, 'semitone steps cost 1')
    Test.expect(a.semi_interval_mean == 12, 'the raw twin still sees 12 semitones')
    Test.expect(a.semi_interval_mean > b.semi_interval_mean,
        'raw semitones rank the octave chart as the harder one - the trap')
end)

----------------------------------------------------------------------
Test.section('Vocals - syllables versus note tubes')

Test.it('a syllable sung over three notes is one syllable and three tubes', function()
    -- 'la + +' repeated: 12 notes, 4 syllables. The two density columns must differ by
    -- exactly that factor, which is what makes them a meaningful substitution pair.
    local notes = VRun(12, 1.0, nil, function(i) return (i % 3 == 1) and 'la' or '+' end)
    local res = ScoreVocalChart(notes, VSpanAll(notes))
    Test.expect(res.tubes_total == 12, 'twelve tubes')
    Test.expect(res.syllables_total == 4, 'four syllables')
    Test.expect(math.abs(res.plus_frac - 8 / 12) < 1e-9, 'plus_frac is 8 of 12')
    Test.expect(math.abs(res.tube_density_avg / res.syl_density_avg - 3) < 1e-9,
        'tube density is exactly 3x syllable density here')
end)

Test.it('a chart with no + notes scores both units identically', function()
    local notes = VRun(10, 1.0)
    local res = ScoreVocalChart(notes, VSpanAll(notes))
    Test.expect(res.tubes_total == res.syllables_total, 'same count')
    Test.expect(res.tube_density_avg == res.syl_density_avg, 'same density')
    Test.expect(res.plus_frac == 0, 'no continuations')
end)

----------------------------------------------------------------------
Test.section('Vocals - note length only bites when the pitch moves')

Test.it('short notes at a moving pitch count; short notes holding pitch do not', function()
    -- The author's mechanism: a short tube gives no time to FIND a new pitch, but a
    -- short tube on the note you are already singing is among the easiest things in
    -- the game. A plain short_frac cannot tell the two apart, which is the whole
    -- argument for the joint factor.
    local moving = VRun(12, 1.0, function(i) return 60 + (i % 2) end, nil, 0.1)
    local static = VRun(12, 1.0, function() return 60 end, nil, 0.1)
    local a = ScoreVocalChart(moving, VSpanAll(moving))
    local b = ScoreVocalChart(static, VSpanAll(static))
    Test.expect(a.short_frac == 1.0 and b.short_frac == 1.0,
        'both charts are entirely short notes')
    Test.expect(a.short_moving_frac > 0.9, 'the moving chart is nearly all short-and-moving')
    Test.expect(b.short_moving_frac == 0,
        'the static chart has none, though short_frac cannot see the difference')
end)

Test.it('long notes at a moving pitch do not count as short', function()
    local notes = VRun(12, 2.0, function(i) return 60 + (i % 2) end, nil, 1.5)
    local res = ScoreVocalChart(notes, VSpanAll(notes))
    Test.expect(res.short_frac == 0, 'no short notes')
    Test.expect(res.short_moving_frac == 0, 'so none short-and-moving either')
end)

----------------------------------------------------------------------
Test.section('Vocals - percussion ranges and playing time')

Test.it('a percussion range holding no sung note is subtracted', function()
    local notes = VRun(6, 1.0)                       -- notes span 0 .. 2.75 s
    local res = ScoreVocalChart(notes, { { s = 0, e = 10 } },
        { perc_spans = { { s = 6, e = 10 } } })
    Test.expect(math.abs(res.playing_s - 6) < 1e-9,
        ('10 s minus a 4 s empty percussion range; got %.3f'):format(res.playing_s))
end)

Test.it('a percussion range holding sung notes is NOT subtracted', function()
    -- 43% of corpus percussion ranges begin while the vocalist is still singing, so a
    -- blanket rule would throw away real singing time.
    local notes = VRun(6, 1.0)
    local res = ScoreVocalChart(notes, { { s = 0, e = 10 } },
        { perc_spans = { { s = 0, e = 3 } } })
    Test.expect(math.abs(res.playing_s - 10) < 1e-9,
        ('playing time untouched; got %.3f'):format(res.playing_s))
end)

Test.it('no percussion spans at all leaves playing time alone', function()
    local notes = VRun(6, 1.0)
    local res = ScoreVocalChart(notes, { { s = 0, e = 10 } })
    Test.expect(math.abs(res.playing_s - 10) < 1e-9, 'unchanged')
end)

----------------------------------------------------------------------
Test.section('Vocals - phrases are the scoring unit')

Test.it('phrase counts use syllables, not tubes', function()
    -- Two phrases of 6 notes each, the second phrase all continuations of one syllable.
    local notes = {}
    for i = 1, 6 do notes[#notes + 1] = VNote(i - 1, 60, 'la') end
    for i = 1, 6 do notes[#notes + 1] = VNote(9 + i - 1, 62, (i == 1) and 'oh' or '+') end
    local spans = { { s = 0, e = 3.0 }, { s = 4.5, e = 7.5 } }
    local res = ScoreVocalChart(notes, spans)
    Test.expect(math.abs(res.phrase_syl_mean - 3.5) < 1e-9,
        ('phrases hold 6 and 1 syllables, mean 3.5; got %.3f'):format(res.phrase_syl_mean))
end)

Test.it('intervals never cross a phrase boundary', function()
    -- The first note of a phrase has no predecessor the singer must move from - it
    -- follows a rest. Counting it would charge every song for its own phrase structure.
    local a = { VNote(0, 60), VNote(1, 60) }
    local b = { VNote(0, 60), VNote(1, 60), VNote(8, 66), VNote(9, 66) }
    local ra = ScoreVocalChart(a, { { s = 0, e = 1.0 } })
    local rb = ScoreVocalChart(b, { { s = 0, e = 1.0 }, { s = 4, e = 5.0 } })
    Test.expect(ra.pc_interval_mean == 0, 'one phrase, no movement')
    Test.expect(rb.pc_interval_mean == 0,
        'two phrases a tritone apart still read no movement - the jump is across a rest')
end)

----------------------------------------------------------------------
Test.section('Vocals - phrase boundaries survive normalization')

Test.it('two touching phrases stay two phrases', function()
    -- The round-12 repair. NormalizeSpans merges touching spans, which is right for an
    -- idle/play join and fatal here: the game scores each phrase separately, so the
    -- boundary is the entire meaning. Merging destroyed 35.6% of the corpus's phrase
    -- boundaries before this existed.
    local sp = NormalizeVocalPhrases({ { s = 0, e = 4 }, { s = 4, e = 8 } })
    Test.expect(#sp == 2, ('two spans; got %d'):format(#sp))
end)

Test.it('overlapping phrases are CLIPPED, not merged, and cover the same time', function()
    local sp = NormalizeVocalPhrases({ { s = 0, e = 5 }, { s = 4, e = 8 } })
    Test.expect(#sp == 2, 'still two phrases')
    Test.expect(sp[2].s == 5, 'the second starts where the first ended')
    local covered = 0
    for _, s in ipairs(sp) do covered = covered + (s.e - s.s) end
    Test.expect(math.abs(covered - 8) < 1e-9,
        'covered time equals the union, so playing_s is unaffected by the repair')
end)

Test.it('a phrase wholly inside another is dropped', function()
    local sp = NormalizeVocalPhrases({ { s = 0, e = 8 }, { s = 2, e = 4 } })
    Test.expect(#sp == 1, 'the nested span contributes no time of its own')
end)

Test.it('NormalizeSpans still merges - the gem behaviour must NOT have changed', function()
    -- Five instruments depend on that merge. This test exists so a future edit to the
    -- vocal path cannot quietly alter it and move three passing gates.
    Test.expect(#NormalizeSpans({ { s = 0, e = 4 }, { s = 4, e = 8 } }) == 1,
        'touching gem spans still merge into one')
end)

Test.it('an interval does not cross a phrase boundary after the repair', function()
    -- Two TOUCHING phrases, a tritone apart across the join. Under the old merge the
    -- pair became one segment and that leap was counted as a sung interval.
    --
    -- The join sits at 0.75 s, between the notes rather than on one: EventsInSegments
    -- treats a span's end as INCLUSIVE, so a note landing exactly on the boundary would
    -- be assigned to the earlier phrase and would make this test measure the tie-break
    -- rule instead of the segmentation.
    local notes = { VNote(0, 60), VNote(1, 60), VNote(2, 66), VNote(3, 66) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 0.75 }, { s = 0.75, e = 2.0 } })
    Test.expect(res.tubes_total == 4, 'all four notes are inside a phrase')
    Test.expect(res.pc_interval_mean == 0,
        ('no movement inside either phrase; got %.3f'):format(res.pc_interval_mean))
end)

----------------------------------------------------------------------
Test.section('Vocals - talkie pitches are not scored')

Test.it('talkie pitches are excluded from the pitched range', function()
    -- The nookie2 shape: talkies scattered across the octave, pitched notes in a narrow
    -- band. The all-notes reading sees a wide-ranging melody that does not exist.
    local notes = {}
    for i = 0, 23 do
        local talkie = (i % 4 ~= 0)
        notes[#notes + 1] = VNote(i,
            talkie and (48 + (i * 5) % 12) or (60 + (i % 3)),
            talkie and 'yo#' or 'la')
    end
    local res = ScoreVocalChart(notes, { { s = 0, e = 12 } })
    Test.expect(math.abs(res.pitched_frac - 0.25) < 1e-9, 'six of twenty-four are pitched')
    Test.expect(res.pc_range_p < res.pc_range,
        ('pitched range %d is narrower than the all-notes %d')
            :format(res.pc_range_p, res.pc_range))
    Test.expect(res.pc_range_p == 3, 'the pitched notes use three classes')
end)

Test.it('an all-talkie chart reads zero pitch demand and no NaN', function()
    -- killinginthename is shouted end to end: 0 of 628 notes carry a scored pitch. Zero
    -- is the honest reading, and pitched_frac is what tells it apart from a measured 0.
    local notes = {}
    for i = 0, 15 do notes[#notes + 1] = VNote(i, 50 + (i % 12), 'yo#') end
    local res = ScoreVocalChart(notes, { { s = 0, e = 8 } })
    Test.expect(res.pitched_frac == 0, 'no pitched notes')
    Test.expect(res.pc_range_p == 0 and res.notated_range == 0, 'no pitch demand')
    for _, k in ipairs(VOCAL_FACTOR_KEYS) do
        Test.expect(res[k] == res[k], 'factor ' .. k .. ' is not NaN')
    end
end)

Test.it('octave_jump_rate counts an octave and ignores a major seventh', function()
    -- The sharpest form of the register question: an octave is the move pitch-class
    -- scoring discards entirely and a singer must still produce.
    local oct, maj7 = {}, {}
    for i = 0, 9 do
        oct[#oct + 1]  = VNote(i, (i % 2 == 0) and 60 or 72, 'la')
        maj7[#maj7 + 1] = VNote(i, (i % 2 == 0) and 60 or 71, 'la')
    end
    local a = ScoreVocalChart(oct,  { { s = 0, e = 5 } })
    local b = ScoreVocalChart(maj7, { { s = 0, e = 5 } })
    Test.expect(a.octave_jump_rate > 0, 'twelve semitones counts')
    Test.expect(b.octave_jump_rate == 0, 'eleven does not')
    Test.expect(a.pc_interval_mean_p == 0,
        'and the same octave leaps are still zero distance in pitch-class space')
end)

Test.it('register factors read the pitched notes, not the talkies', function()
    -- A part whose talkies sit an octave below its sung notes must not report a
    -- two-octave notated range.
    local notes = {}
    for i = 0, 11 do
        local talkie = (i % 2 == 1)
        notes[#notes + 1] = VNote(i, talkie and 40 or (64 + (i % 4)), talkie and 'yo#' or 'la')
    end
    local res = ScoreVocalChart(notes, { { s = 0, e = 6 } })
    Test.expect(res.notated_range <= 3,
        ('range over the sung notes only; got %d'):format(res.notated_range))
    Test.expect(res.pitch_mean > 60, 'register reflects the sung notes, not the shouts')
end)

----------------------------------------------------------------------
Test.section('Vocals - breath load: the long arm of a U-shaped relationship')

-- Note length in SECONDS, which is what breath costs. VNote takes quarter notes, so
-- these build directly: one note per second of grid at 120 bpm.
local function VSec(qn, pitch, lyric, len_s)
    local s = qn * 0.5
    return { s = s, e = s + len_s, qn = qn, qn_e = qn + len_s * 2,
             pitch = pitch, lyric = lyric or 'la' }
end

Test.it('nothing accrues below the free threshold', function()
    -- A part of ordinary half-second notes costs no breath at all. This is the arm that
    -- made round 12's monotonic measurement read zero: short notes are hard for a
    -- different reason, and averaging the two directions cancels both.
    local notes = {}
    for i = 0, 11 do notes[#notes + 1] = VSec(i, 60, 'la', 0.5) end
    local res = ScoreVocalChart(notes, { { s = 0, e = 6 } })
    Test.expect(res.breath_load == 0, 'no breath load')
    Test.expect(res.longtime_frac == 0, 'no sustained time')
    Test.expect(math.abs(res.longest_note_s - 0.5) < 1e-9, 'longest note is half a second')
end)

Test.it('the threshold is exact at one second', function()
    local at   = ScoreVocalChart({ VSec(0, 60, 'la', 1.0) },  { { s = 0, e = 5 } })
    local over = ScoreVocalChart({ VSec(0, 60, 'la', 1.01) }, { { s = 0, e = 5 } })
    Test.expect(at.breath_load == 0, 'exactly one second is free')
    Test.expect(over.breath_load > 0, 'a hundredth over is not')
end)

Test.it('one very long note dominates the peak measure but barely the mean', function()
    -- The flightoficarus shape, and the whole argument for a threshold measure: eleven
    -- short notes and one eleven-second hold. longest_note_s sees it immediately;
    -- a mean note length barely moves.
    -- 0.1 s at 120 bpm is 0.2 quarter notes, inside VOCAL_SHORT_QN, so these count as
    -- short by the round-11 measure as well as being short in wall-clock terms.
    local notes = {}
    for i = 0, 10 do notes[#notes + 1] = VSec(i, 60, 'la', 0.1) end
    notes[#notes + 1] = VSec(12, 72, 'la', 11.0)
    local res = ScoreVocalChart(notes, { { s = 0, e = 20 } })
    Test.expect(math.abs(res.longest_note_s - 11.0) < 1e-9, 'the held note is found')
    Test.expect(res.breath_load > 0, 'and it accrues breath load')
    Test.expect(res.longtime_frac > 0.5, 'most sung TIME is inside that one note')
    -- BOTH ARMS OF THE U AT ONCE, which is the point: by note COUNT this chart is
    -- 11/12 short, and by TIME it is one long hold. A single monotonic length statistic
    -- reports the average of two opposite demands and sees neither.
    Test.expect(res.short_frac > 0.5, 'yet most NOTES are short - the two arms coexist')
end)

Test.it('talkies are excluded from the breath family', function()
    local notes = { VSec(0, 60, 'la', 0.3), VSec(4, 60, 'yo#', 9.0) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 15 } })
    Test.expect(math.abs(res.longest_note_s - 0.3) < 1e-9,
        'a shouted nine-second note is not a sung hold')
end)

----------------------------------------------------------------------
Test.section('Vocals - tessitura: where the part sits')

Test.it('the two high thresholds are a real substitution, not duplicates', function()
    -- A part sitting at 68 is above G4 and below B flat 4, so the two readings disagree
    -- completely. That is what makes them worth declaring as a swap rather than picking
    -- one after seeing which scores better.
    local notes = {}
    for i = 0, 9 do notes[#notes + 1] = VSec(i, 68, 'la', 0.5) end
    local res = ScoreVocalChart(notes, { { s = 0, e = 5 } })
    Test.expect(math.abs(res.high_time_67 - 1.0) < 1e-9, 'all of it is above 67')
    Test.expect(res.high_time_70 == 0, 'none of it is above 70')
end)

Test.it('a comfortable part reads zero on both', function()
    local notes = {}
    for i = 0, 9 do notes[#notes + 1] = VSec(i, 60, 'la', 0.5) end
    local res = ScoreVocalChart(notes, { { s = 0, e = 5 } })
    Test.expect(res.high_time_67 == 0 and res.high_time_70 == 0, 'nothing high')
end)

Test.it('tessitura is TIME-weighted, not note-counted', function()
    -- One long high note against many short low ones. Counting onsets would call this a
    -- low part; the singer is up there for most of the song.
    local notes = { VSec(0, 60, 'la', 0.2), VSec(1, 60, 'la', 0.2), VSec(2, 72, 'la', 6.0) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 10 } })
    Test.expect(res.high_time_70 > 0.9,
        ('most sung time is high; got %.3f'):format(res.high_time_70))
end)

Test.it('top_note ignores a talkie written above the sung range', function()
    -- Shouted syllables carry a written pitch the game never reads, and they are often
    -- parked high. Letting one set the ceiling would invent a range the part never asks
    -- the singer to reach.
    local notes = { VSec(0, 60, 'la', 0.5), VSec(1, 62, 'la', 0.5), VSec(2, 80, 'yo#', 0.5) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 3 } })
    Test.expect(res.top_note == 62, ('top note is the highest SUNG note; got %d'):format(res.top_note))
end)

Test.it('high sustained interaction requires both conditions', function()
    local high_long = ScoreVocalChart({ VSec(0, 72, 'la', 3.0) }, { { s = 0, e = 4 } })
    local high_short = ScoreVocalChart({ VSec(0, 72, 'la', 0.5) }, { { s = 0, e = 1 } })
    local low_long = ScoreVocalChart({ VSec(0, 60, 'la', 3.0) }, { { s = 0, e = 4 } })
    Test.expect(high_long.high_hold_time_70 > 0, 'a high long note contributes')
    Test.expect(high_short.high_hold_time_70 == 0, 'high but short does not')
    Test.expect(low_long.high_hold_time_70 == 0, 'long but low does not')
    Test.expect(high_long.high_longest_note_70 == 3.0, 'joint peak keeps wall-clock duration')
end)

Test.it('duration-weighted upper pitch ignores a tiny exceptional onset', function()
    local notes = {}
    for i = 0, 19 do notes[#notes + 1] = VSec(i, 60, 'la', 0.5) end
    notes[#notes + 1] = VSec(21, 84, 'la', 0.05)
    local res = ScoreVocalChart(notes, { { s = 0, e = 12 } })
    Test.expect(res.top_note == 84, 'raw maximum sees the exceptional onset')
    Test.expect(res.pitch_p98_time == 60, 'time-weighted p98 remains at the occupied register')
end)

Test.it('a high phrase entry after a real rest is counted cold', function()
    local notes = { VSec(0, 60, 'la', 0.5), VSec(8, 72, 'la', 0.5) }
    local spans = { { s = 0, e = 1 }, { s = 4, e = 5 } }
    local res = ScoreVocalChart(notes, spans)
    Test.expect(res.high_reentry_rate_70 > 0, 'high entry after three seconds away counts')
end)

Test.it('phrase tail combines local density and movement', function()
    local plain, moving = {}, {}
    for i = 0, 9 do
        plain[#plain + 1] = VSec(i * 0.5, 60, 'la', 0.1)
        moving[#moving + 1] = VSec(i * 0.5, 60 + (i % 2) * 5, 'la', 0.1)
    end
    local spans = { { s = 0, e = 3 } }
    local a, b = ScoreVocalChart(plain, spans), ScoreVocalChart(moving, spans)
    Test.expect(a.phrase_density_p90 == b.phrase_density_p90, 'density is held constant')
    Test.expect(b.phrase_complex_p90 > a.phrase_complex_p90,
        'moving phrase has greater joint local demand')
end)

Test.it('vocal_parts is an explicit supplied label-context factor', function()
    local notes = { VSec(0, 60, 'la', 0.5) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 1 } }, { vocal_parts = 3 })
    Test.expect(res.vocal_parts == 3, 'three-part metadata survives into the factors')
end)

Test.it('the harmony count is offered in three competing shapes', function()
    -- Round 20. The count enters the model as a number, which asserts that 1 -> 2 costs
    -- what 2 -> 3 costs; the corpus says one and two parts are the same level and the
    -- whole effect is the step to three. These are the alternative shapes, and they are
    -- pure functions of the label - no chart is read to produce them.
    local notes = { VSec(0, 60, 'la', 0.5) }
    local spans = { { s = 0, e = 1 } }
    local got = {}
    for p = 1, 3 do got[p] = ScoreVocalChart(notes, spans, { vocal_parts = p }) end

    Test.expect(got[1].parts_2 == 0 and got[2].parts_2 == 1 and got[3].parts_2 == 1,
        'parts_2 is the "has any harmony" step')
    Test.expect(got[1].parts_3 == 0 and got[2].parts_3 == 0 and got[3].parts_3 == 1,
        'parts_3 is the "full three-part" step, and two parts is NOT half of it')
    Test.expect(got[1].parts_log == 0 and got[3].parts_log > got[2].parts_log
        and got[2].parts_log > got[1].parts_log,
        'parts_log rises with the count but by a shrinking step')
    -- The two indicators together are the assumption-free form: every level distinct.
    Test.expect(got[1].parts_2 + got[1].parts_3 == 0
        and got[2].parts_2 + got[2].parts_3 == 1
        and got[3].parts_2 + got[3].parts_3 == 2,
        'parts_2 and parts_3 together separate all three levels')
end)

Test.it('the harmony shapes survive a chart with nothing to measure', function()
    -- The early returns leave the initialiser table, so a chart with no usable notes
    -- must still carry the label shapes rather than nil - an unset column reaches the
    -- CSV as empty and drops the whole row from every fit.
    local res = ScoreVocalChart({}, {}, { vocal_parts = 3 })
    Test.expect(res.parts_3 == 1 and res.parts_2 == 1,
        'a chart with no notes still reports its declared harmony count')
    local d = ScoreVocalChart({ VSec(0, 60, 'la', 0.5) }, { { s = 0, e = 1 } })
    Test.expect(d.parts_2 == 0 and d.parts_3 == 0 and d.parts_log == 0,
        'an absent count defaults to one part in every shape, never nil')
end)

----------------------------------------------------------------------
----------------------------------------------------------------------
Test.section('Vocals - breath groups')

-- Absolute seconds, so a gap can be stated in milliseconds without going through qn.
local function BSec(s, len, pitch, lyric)
    return { s = s, e = s + len, qn = s * 2, qn_e = (s + len) * 2,
             pitch = pitch or 60, lyric = lyric or 'la' }
end

Test.it('back-to-back short notes are ONE demand on the air', function()
    -- The reason the round exists. Ten tenth-second syllables with no gap are ten easy
    -- notes to longest_note_s and one continuous second of singing to a singer.
    local notes = {}
    for i = 0, 9 do notes[#notes + 1] = BSec(i * 0.1, 0.1) end
    local res = ScoreVocalChart(notes, { { s = 0, e = 2 } })
    Test.expect(math.abs(res.longest_note_s - 0.1) < 1e-9,
        'every individual note is a tenth of a second')
    Test.expect(math.abs(res.breath_max_100 - 1.0) < 1e-9,
        'and together they are one unbroken second')
end)

Test.it('the threshold is what decides, and the two are not the same column', function()
    -- A 75 ms gap is room to breathe at the tight threshold and not at the wide one.
    -- If this passes with both equal, the substitution is measuring one thing twice.
    local notes = { BSec(0, 0.2), BSec(0.275, 0.2) }
    local res = ScoreVocalChart(notes, { { s = 0, e = 1 } })
    Test.expect(math.abs(res.breath_max_50 - 0.2) < 1e-9,
        '75 ms is a breath at the 50 ms threshold, so the run splits')
    Test.expect(math.abs(res.breath_max_100 - 0.475) < 1e-9,
        'and is not one at 100 ms, so the run holds together')
end)

Test.it('a phrase boundary ends a group even when the notes nearly touch', function()
    -- Two phrases separated by a marker gap, with notes only 20 ms apart across the seam.
    -- Without the segment split those 20 ms are well inside every threshold and the two
    -- phrases would read as one passage.
    local a, b = BSec(0.1, 0.2), BSec(0.32, 0.18)
    local res = ScoreVocalChart({ a, b }, { { s = 0, e = 0.31 }, { s = 0.315, e = 0.6 } })
    Test.expect(math.abs(res.breath_max_50 - 0.2) < 1e-9,
        'the group stops at the phrase edge rather than spanning both')
end)

Test.it('phrases that touch exactly are one passage, and that is correct', function()
    -- EventsInSegments merges spans that share an edge, so a zero-length seam is not a
    -- split. Inherited behaviour, and for THIS family it is the honest reading rather
    -- than a wart to work around: breath is wall-clock, and a phrase marker that ends
    -- exactly where the next begins gives the singer no air whatsoever. Pinned so that a
    -- later fix to the segment seam is a deliberate decision about breath and not a
    -- silent side effect.
    local a, b = BSec(0, 0.3), BSec(0.3, 0.3)
    local res = ScoreVocalChart({ a, b }, { { s = 0, e = 0.3 }, { s = 0.3, e = 0.6 } })
    Test.expect(math.abs(res.breath_max_100 - 0.6) < 1e-9,
        'no gap in wall-clock time means no breath, whatever the markers say')
end)

Test.it('a shouted chart still registers breath demand', function()
    -- killinginthename is 0 of 628 notes pitched. Computing breath on the @pitched twins
    -- would report nothing at all for it, and a fast rapped passage needs air like any
    -- other. Movement is the deliberate exception: a talkie's written pitch is not scored
    -- by the game and must not invent motion.
    local notes = {}
    for i = 0, 9 do notes[#notes + 1] = BSec(i * 0.15, 0.15, 55 + i, 'x#') end
    local res = ScoreVocalChart(notes, { { s = 0, e = 2 } })
    Test.expect(res.pitched_frac == 0, 'nothing on this chart is pitched')
    Test.expect(math.abs(res.breath_max_100 - 1.5) < 1e-9,
        'and it is still an unbroken passage of singing')
    Test.expect(res.breath_move_100 == 0,
        'while the talkies contribute no pitch movement')
end)

Test.it('movement steps over a talkie rather than breaking on it', function()
    -- The same rule semi_interval_mean_p uses. A talkie between two sung notes an octave
    -- apart must leave them adjacent, or every rap-inflected chart reads as motionless.
    local notes = { BSec(0, 0.2, 60, 'la'), BSec(0.2, 0.2, 41, 'yeah#'),
                    BSec(0.4, 0.2, 72, 'la') }
    local res = ScoreVocalChart(notes, { { s = 0, e = 1 } })
    Test.expect(math.abs(res.breath_move_100 - 12) < 1e-9,
        'one group, and the octave between the two sung notes is the whole travel')
end)

Test.it('the mean and max movement forms are a real substitution', function()
    -- One busy passage among three still ones. The mean dilutes it by the count of quiet
    -- groups; the max reports it. Round 14's finding is that the decisive passage is the
    -- one that sets the rank, and this is the pair that lets the corpus rule on it.
    local notes, t = {}, 0
    for _ = 1, 4 do notes[#notes + 1] = BSec(t, 0.2, 60); t = t + 0.2 end
    t = t + 0.5
    for i = 1, 4 do notes[#notes + 1] = BSec(t, 0.2, 60 + (i % 2) * 9); t = t + 0.2 end
    local res = ScoreVocalChart(notes, { { s = 0, e = 3 } })
    Test.expect(res.breath_movemax_100 > res.breath_move_100,
        'the busiest group exceeds the average over both groups')
    Test.expect(math.abs(res.breath_movemax_100 - 27) < 1e-9,
        'and the max is that group\'s own travel, undiluted')
end)

Test.it('degenerate charts read zero without dividing by nothing', function()
    local one = ScoreVocalChart({ BSec(0, 0.4) }, { { s = 0, e = 1 } })
    Test.expect(math.abs(one.breath_max_100 - 0.4) < 1e-9 and one.breath_move_100 == 0,
        'a single note is a group of itself and travels nowhere')
    for _, k in ipairs({ 'breath_max_50', 'breath_mean_50',
                         'breath_move_50', 'breath_movemax_50',
                         'breath_max_100', 'breath_mean_100',
                         'breath_move_100', 'breath_movemax_100' }) do
        local v = ScoreVocalChart({}, {})[k]
        Test.expect(v == 0, k .. ' is a structural zero on an empty chart, not nil')
    end
    -- A group cannot outlast the part it is measured on.
    local notes = {}
    for i = 0, 9 do notes[#notes + 1] = BSec(i * 0.1, 0.1) end
    local res = ScoreVocalChart(notes, { { s = 0, e = 2 } })
    Test.expect(res.breath_max_100 <= res.playing_s + 1e-9,
        'the longest group never exceeds the playing time')
    Test.expect(res.breath_mean_100 <= res.breath_max_100 + 1e-9,
        'and the mean group never exceeds the longest')
end)

----------------------------------------------------------------------
Test.section('Vocals - the phrase as a pitch journey')

Test.it('span sees a climb that every interval measure reads as small', function()
    -- The antsmarching shape, reduced: one phrase walking from MIDI 50 to 66 in whole
    -- tones. Every step is two semitones, so the interval columns report an easy melody;
    -- the phrase still spans sixteen semitones with no rest to reset the voice. This is
    -- the entire reason the factor exists.
    local notes = VRun(9, 1, function(i) return 48 + i * 2 end)   -- 50, 52 ... 66
    local res = ScoreVocalChart(notes, VSpanAll(notes))
    Test.expect(math.abs(res.semi_interval_mean_p - 2) < 1e-9,
        'every interval is two semitones')
    Test.expect(math.abs(res.pc_interval_mean - 2) < 1e-9,
        'and two in pitch class as well')
    Test.expect(res.phrase_span_p90 == 16,
        ('the phrase spans sixteen semitones, read as %d'):format(res.phrase_span_p90))
end)

Test.it('travel separates a see-saw from a straight line of the same width', function()
    -- Two phrases of equal note count and equal span. The climb passes through its range
    -- once; the see-saw crosses it repeatedly. Same reach, different amount of singing.
    local climb  = VRun(7, 1, function(i) return 60 + (i - 1) * 2 end)  -- 60..72
    local seesaw = VRun(7, 1, function(i) return (i % 2 == 1) and 60 or 72 end)
    local rc = ScoreVocalChart(climb,  VSpanAll(climb))
    local rs = ScoreVocalChart(seesaw, VSpanAll(seesaw))
    Test.expect(rc.phrase_span_p90 == rs.phrase_span_p90,
        'the two phrases reach equally far')
    Test.expect(rs.phrase_travel_p90 > rc.phrase_travel_p90,
        ('the see-saw covers more ground: %d against %d')
            :format(rs.phrase_travel_p90, rc.phrase_travel_p90))
end)

Test.it('span separates two phrases that travel the same distance', function()
    -- The converse, so neither column is assumed to stand in for the other: an out-and-back
    -- and a straight climb both travel twelve semitones and reach different distances.
    local outback = VRun(7, 1, function(i) return 60 + (i <= 4 and (i - 1) * 2
                                                                or (7 - i) * 2) end)
    local climb   = VRun(7, 1, function(i) return 60 + (i - 1) * 2 end)
    local ro = ScoreVocalChart(outback, VSpanAll(outback))
    local rc = ScoreVocalChart(climb,   VSpanAll(climb))
    Test.expect(ro.phrase_travel_p90 == rc.phrase_travel_p90,
        'both cover the same ground')
    Test.expect(rc.phrase_span_p90 > ro.phrase_span_p90,
        ('the climb reaches further: %d against %d')
            :format(rc.phrase_span_p90, ro.phrase_span_p90))
end)

Test.it('a talkie between two sung notes joins them rather than breaking the pair', function()
    -- Computed over psegs, where the talkie is already filtered out, so the two sung notes
    -- are neighbours - the same reading semi_interval_mean_p and octave_jump_rate use.
    -- The phrase loop further down the scorer walks the talkie-INCLUSIVE list and guards
    -- its pitch step on adjacency there, so an implementation moved into that loop would
    -- read zero here. That is what this test is for.
    local notes = { VNote(0, 60, 'la'), VNote(1, 65, 'yo#'), VNote(2, 72, 'la') }
    local res = ScoreVocalChart(notes, { { s = notes[1].s, e = notes[3].e } })
    Test.expect(res.phrase_travel_p90 == 12,
        ('the octave is travelled through the talkie, read as %d'):format(res.phrase_travel_p90))
    Test.expect(res.phrase_span_p90 == 12, 'and the span ignores the talkie pitch')
end)

Test.it('neither quantity crosses a phrase boundary', function()
    -- Two phrases an octave apart, each flat. The song ranges twelve semitones and no
    -- phrase asks the singer to move at all.
    local notes = {}
    for i = 0, 3 do notes[#notes + 1] = VNote(i, 60, 'la') end
    for i = 8, 11 do notes[#notes + 1] = VNote(i, 72, 'la') end
    local res = ScoreVocalChart(notes, {
        { s = VNote(0, 60).s, e = VNote(3, 60).e },
        { s = VNote(8, 72).s, e = VNote(11, 72).e },
    })
    Test.expect(res.notated_range == 12, 'the song ranges an octave')
    Test.expect(res.phrase_travel_p90 == 0 and res.phrase_span_p90 == 0,
        'but no phrase moves, so travel and span are both zero')
end)

Test.it('degenerate charts read zero, and span never exceeds the song range', function()
    -- One-note phrases have no journey in them and are counted rather than skipped:
    -- excluding them would make the denominator depend on the chart's phrasing style.
    local single = { VNote(0, 60, 'la') }
    local rs = ScoreVocalChart(single, VSpanAll(single))
    Test.expect(rs.phrase_span_p90 == 0 and rs.phrase_travel_p90 == 0,
        'a one-note phrase is span zero and travel zero')

    local shouted = {}
    for i = 0, 15 do shouted[#shouted + 1] = VNote(i, 50 + (i % 12), 'yo#') end
    local rt = ScoreVocalChart(shouted, { { s = 0, e = 8 } })
    for _, k in ipairs({ 'phrase_span_mean', 'phrase_span_p90',
                         'phrase_travel_mean', 'phrase_travel_p90' }) do
        Test.expect(rt[k] == 0, 'an all-talkie chart reads zero for ' .. k)
        Test.expect(rt[k] == rt[k], k .. ' is not NaN')
    end

    -- A phrase cannot reach wider than the song it sits in.
    local wander = VRun(24, 1, function(i) return 55 + ((i * 7) % 13) end)
    local rw = ScoreVocalChart(wander, VSpanAll(wander))
    Test.expect(rw.phrase_span_p90 <= rw.notated_range,
        ('phrase span %d within song range %d')
            :format(rw.phrase_span_p90, rw.notated_range))
end)

----------------------------------------------------------------------
Test.section('Vocals - guards and the factor list')

Test.it('a chart with no playing time flags itself instead of dividing by zero', function()
    local notes = VRun(4, 1.0)
    local res = ScoreVocalChart(notes, {})
    Test.expect(res.no_playing_time == true, 'flagged')
    Test.expect(res.playing_s == 0, 'and zero rather than nan')
end)

Test.it('notes outside every phrase span score nothing', function()
    local notes = VRun(4, 1.0)
    local res = ScoreVocalChart(notes, { { s = 100, e = 110 } })
    Test.expect(res.tubes_total == 0, 'no notes inside the span')
    Test.expect(res.playing_s == 10, 'but the span time is still real')
end)

Test.it('VOCAL_FACTOR_KEYS names only factors the scorer produces', function()
    local notes = VRun(16, 0.5, function(i) return 60 + (i % 5) end,
                       function(i) return (i % 4 == 0) and '+' or 'la' end)
    local res = ScoreVocalChart(notes, VSpanAll(notes), { perc_spans = {} })
    for _, k in ipairs(VOCAL_FACTOR_KEYS) do
        Test.expect(type(res[k]) == 'number', 'factor ' .. k .. ' is a number')
    end
end)

Test.it('the vocal columns were folded into SCORE_FACTOR_KEYS exactly once', function()
    -- The CSV writer, the protocol and the analysis all drive off that one list, so a
    -- duplicate would write two columns of the same quantity and let a candidate fit
    -- both. The four shared names (playing_s, tight_p10, tight_med, entropy_h2_rel)
    -- must appear once, not twice.
    local seen = {}
    for _, k in ipairs(SCORE_FACTOR_KEYS) do
        Test.expect(not seen[k], 'no duplicate column: ' .. k)
        seen[k] = true
    end
    for _, k in ipairs(VOCAL_FACTOR_KEYS) do
        Test.expect(seen[k], 'vocal factor present in the master list: ' .. k)
    end
end)

Test.it('every column in the master list is produced by ONE of the two scorers', function()
    -- The invariant the gem-side test used to carry on its own, restored now that
    -- SCORE_FACTOR_KEYS spans both factor sets: a column neither scorer ever writes
    -- would be an all-zero CSV column that no fit could use and nobody would notice.
    local ev = {}
    for i = 1, 32 do
        local t = (i - 1) * 0.25
        ev[i] = { s = t, e = t + 0.05, qn = (i - 1) * 0.5, qn_e = (i - 1) * 0.5 + 0.1,
                  pitches = { 96 + (i % 2) }, held = {} }
    end
    local gem = ScoreChart(ev, { { s = 0, e = ev[#ev].e } }, {
        solo_spans = { { s = 0, e = 1 } }, force_hopo_count = 1, force_strum_count = 1,
    })

    local notes = VRun(16, 0.5, function(i) return 60 + (i % 5) end,
                       function(i) return (i % 4 == 0) and '+' or 'la' end)
    local voc = ScoreVocalChart(notes, VSpanAll(notes))

    for _, k in ipairs(SCORE_FACTOR_KEYS) do
        Test.expect(type(gem[k]) == 'number' or type(voc[k]) == 'number',
            'column ' .. k .. ' is produced by the gem scorer or the vocal scorer')
    end
end)
