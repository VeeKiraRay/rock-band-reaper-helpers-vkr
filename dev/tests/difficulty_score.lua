-- Unit tests for the difficulty scoring factors (dev/calibration/difficulty_score.lua):
-- ScoreChart and DeriveSpansFromEvents.
--
-- These are pure functions over plain Lua tables - no project, no MIDI editor,
-- no REAPER API beyond the console. Each test asserts the BEHAVIOUR the design
-- claims for a factor, not a magic number: "double the tempo and factor 1
-- doubles", "repeat one gem and factor 3 goes to zero while factor 1 does not".
-- That is what makes them useful when the weights are later re-tuned.

----------------------------------------------------------------------
-- Chart builders
----------------------------------------------------------------------

-- n notes at qn_step quarter-note spacing, starting at qn0, at a fixed BPM.
-- pitches_fn(i) supplies each event's pitch array; defaults to a single gem.
-- len_qn (optional) sets each note's length in quarter notes, which is what the
-- sustain factor measures; default is a short 10% of a quarter note.
local function Run(n, qn_step, bpm, pitches_fn, qn0, len_qn)
    local ev  = {}
    local qn  = qn0 or 0
    local spq = 60.0 / bpm  -- seconds per quarter note
    local len = len_qn or 0.1
    for i = 1, n do
        local t = qn * spq
        ev[#ev + 1] = {
            s = t, e = t + len * spq, qn = qn, qn_e = qn + len,
            pitches = pitches_fn and pitches_fn(i) or { 96 },
        }
        qn = qn + qn_step
    end
    return ev
end

-- One span covering every event, i.e. "the instrument plays throughout".
local function SpanAll(ev)
    return { { s = ev[1].s, e = ev[#ev].e } }
end

local function Concat(a, b)
    local out = {}
    for _, e in ipairs(a) do out[#out + 1] = e end
    for _, e in ipairs(b) do out[#out + 1] = e end
    return out
end

local function Alternating(i) return { 96 + (i % 2) } end

----------------------------------------------------------------------
Test.section('ScoreChart - factor 1: density is real-time, not beat-relative')

Test.it('same note count at double tempo doubles density', function()
    local slow = Run(64, 0.5, 100)
    local fast = Run(64, 0.5, 200)
    local a = ScoreChart(slow, SpanAll(slow))
    local b = ScoreChart(fast, SpanAll(fast))
    Test.expect(a.notes == b.notes, 'same note count both charts')
    local ratio = b.density_avg / a.density_avg
    Test.expect(ratio > 1.9 and ratio < 2.1,
        ('double tempo ~doubles density; got ratio %.3f'):format(ratio))
end)

Test.it('chord events count every note, not one per onset', function()
    local single = Run(16, 1.0, 120, function() return { 96 } end)
    local triple = Run(16, 1.0, 120, function() return { 96, 97, 98 } end)
    local a = ScoreChart(single, SpanAll(single))
    local b = ScoreChart(triple, SpanAll(triple))
    Test.expect(b.notes == 3 * a.notes, 'three gems per onset = 3x the notes')
    Test.expect(b.events == a.events, 'but the same number of events')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - factor 3: note-change density is independent of factor 1')

Test.it('repeating one gem gives zero change rate but full density', function()
    local ev = Run(64, 0.5, 120, function() return { 96 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.density_avg > 0, 'density is non-zero')
    Test.expect(res.change_rate == 0, 'no pitch-set changes; got ' .. res.change_rate)
end)

Test.it('alternating gems at identical spacing: same density, non-zero changes', function()
    local rep = Run(64, 0.5, 120, function() return { 96 } end)
    local alt = Run(64, 0.5, 120, Alternating)
    local a = ScoreChart(rep, SpanAll(rep))
    local b = ScoreChart(alt, SpanAll(alt))
    Test.expect(math.abs(a.density_avg - b.density_avg) < 1e-9,
        'factor 1 cannot tell them apart (by design)')
    Test.expect(b.change_rate > 0, 'factor 3 can; got ' .. b.change_rate)
end)

Test.it('a chord counts as changed when its pitch SET differs, not just its lowest note', function()
    local ev = {
        { s = 0.0, e = 0.1, qn = 0.0, pitches = { 96, 97 } },
        { s = 0.5, e = 0.6, qn = 1.0, pitches = { 96, 98 } },  -- same lowest, different set
    }
    local res = ScoreChart(ev, { { s = 0, e = 0.6 } })
    Test.expect(res.change_rate > 0, 'set difference registers as a change')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - factors 2 and 4: bursts move peak and tightness, not the average')

Test.it('a 32nd burst inside a slow chart moves peak and tightness far more than density', function()
    local base  = Run(32, 1.0,   120, function(i) return { 96 + (i % 3) } end)
    local burst = Run(16, 0.125, 120, Alternating, 40)
    local mixed = Concat(base, burst)

    local a = ScoreChart(base,  SpanAll(base))
    local b = ScoreChart(mixed, SpanAll(mixed))

    -- Intervals: smaller is tighter, so the burst chart's low percentile drops.
    Test.expect(b.tight_p10 < a.tight_p10,
        ('burst pulls the tight end down; %.4f vs %.4f'):format(b.tight_p10, a.tight_p10))
    Test.expect(b.density_peak > a.density_peak, 'peak rises')

    -- The point of separating the average from the peak: the average barely notices.
    local dens_rise = b.density_avg  / a.density_avg
    local peak_rise = b.density_peak / a.density_peak
    Test.expect(peak_rise > dens_rise,
        ('peak reacts more than the average; %.3f vs %.3f'):format(peak_rise, dens_rise))
end)

Test.it('tightness percentiles report the actual interval in quarter notes', function()
    local ev  = Run(32, 0.25, 120, Alternating)   -- every change a 16th apart
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.tight_p10 - 0.25) < 1e-6,
        'p10 is the 16th interval; got ' .. res.tight_p10)
    Test.expect(math.abs(res.tight_med - 0.25) < 1e-6, 'median likewise')
end)

Test.it('tight_p10 is at or below the median by definition', function()
    local slow = Run(20, 1.0,  120, Alternating)
    local fast = Run(20, 0.25, 120, Alternating, 40)
    local ev   = Concat(slow, fast)
    local res  = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.tight_p10 <= res.tight_med + 1e-9,
        ('p10 %.4f <= median %.4f'):format(res.tight_p10, res.tight_med))
end)

Test.it('triplet spacing is captured, which the old fixed 16th/32nd buckets missed', function()
    -- An 8th triplet is 1/3 QN: tighter than a straight 8th (0.5) but WIDER than a
    -- 16th (0.25), so it fell into neither of the old cumulative buckets and was
    -- invisible. A percentile has no such gap.
    local straight = Run(24, 0.5,     120, Alternating)
    local triplet  = Run(24, 1.0 / 3, 120, Alternating)
    local a = ScoreChart(straight, SpanAll(straight))
    local b = ScoreChart(triplet,  SpanAll(triplet))
    Test.expect(b.tight_med < a.tight_med,
        ('triplets read tighter than straight 8ths; %.4f vs %.4f')
            :format(b.tight_med, a.tight_med))
    Test.expect(math.abs(b.tight_med - 1.0 / 3) < 1e-6, 'and the value is the triplet interval')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - attack density: hand rate, not gem count')

-- The property the whole round-8 change rests on. density_* counts a 3-note chord as
-- 3 gems, so on a chordal chart it reports a hand moving three times as fast as it is.
-- `dreampolice` bass is the real case: the only chordal chart in the 159-song bass
-- corpus, its gem-based density_peak reached z = +6.34 and the fit returned a rank of
-- 943 for a chart ranked 299.
Test.it('chords inflate gem density by their size and leave attack density alone', function()
    local single = Run(20, 0.5, 120, function() return { 96 } end)
    local triple = Run(20, 0.5, 120, function() return { 96, 97, 98 } end)
    local a = ScoreChart(single, SpanAll(single))
    local b = ScoreChart(triple, SpanAll(triple))

    Test.expect(math.abs(b.density_avg - 3 * a.density_avg) < 1e-9,
        ('gem density triples: %.4f vs %.4f'):format(b.density_avg, a.density_avg))
    Test.expect(math.abs(b.density_peak - 3 * a.density_peak) < 1e-9,
        ('gem peak triples: %.4f vs %.4f'):format(b.density_peak, a.density_peak))

    Test.expect(math.abs(b.attack_density_avg - a.attack_density_avg) < 1e-9,
        ('attack density is identical: %.4f vs %.4f')
            :format(b.attack_density_avg, a.attack_density_avg))
    Test.expect(math.abs(b.attack_density_peak - a.attack_density_peak) < 1e-9,
        ('attack peak is identical: %.4f vs %.4f')
            :format(b.attack_density_peak, a.attack_density_peak))
end)

Test.it('the two measures agree exactly on an all-single-note chart', function()
    -- Which is why bass is expected to be unmoved: 157 of its 159 charts look like this.
    local ev  = Run(40, 0.25, 140, function() return { 97 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.density_avg - res.attack_density_avg) < 1e-9, 'averages agree')
    Test.expect(math.abs(res.density_peak - res.attack_density_peak) < 1e-9, 'peaks agree')
    Test.expect(math.abs(res.chord_size_mean - 1.0) < 1e-9, 'and chord size is 1.0')
end)

Test.it('attack_density_avg is events per second of playing time', function()
    -- 24 events at a 0.5 QN step and 120 bpm: 0.25 s apart, so the span from the first
    -- onset to the last note's end is 23 * 0.25 plus the 10% tail = 5.775 s.
    local ev  = Run(24, 0.5, 120, function() return { 96, 100 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.events == 24, 'event count; got ' .. tostring(res.events))
    Test.expect(res.notes == 48, 'gem count is double; got ' .. tostring(res.notes))
    Test.expect(math.abs(res.attack_density_avg - res.events / res.playing_s) < 1e-9,
        'events / playing_s')
    Test.expect(math.abs(res.density_avg - res.notes / res.playing_s) < 1e-9,
        'and the gem version is notes / playing_s')
end)

Test.it('a burst still moves the attack peak, so the factor has not gone blind', function()
    local base  = Run(32, 1.0,   120, function() return { 96, 97 } end)
    local burst = Run(16, 0.125, 120, function() return { 96, 97 } end, 40)
    local mixed = Concat(base, burst)
    local a = ScoreChart(base,  SpanAll(base))
    local b = ScoreChart(mixed, SpanAll(mixed))
    Test.expect(b.attack_density_peak > a.attack_density_peak,
        ('%.4f > %.4f'):format(b.attack_density_peak, a.attack_density_peak))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - hand movement: how far, not how often')

Test.it('identical density and change rate, different hand travel', function()
    -- THE case the whole factor exists for: these two charts are indistinguishable
    -- on every other factor, and one is far harder to play. It is the shape of the
    -- corpus failure cluster (busy riffs in one hand position, over-rated as hard).
    local near = Run(64, 0.25, 120, function(i) return { 96 + (i % 2) } end)      -- green/red
    local far  = Run(64, 0.25, 120, function(i) return { 96 + (i % 2) * 4 } end)  -- green/orange

    local a = ScoreChart(near, SpanAll(near))
    local b = ScoreChart(far,  SpanAll(far))

    Test.expect(math.abs(a.density_avg - b.density_avg) < 1e-9, 'same density')
    Test.expect(math.abs(a.change_rate - b.change_rate) < 1e-9, 'same change rate')
    Test.expect(math.abs(a.tight_p10   - b.tight_p10)   < 1e-9, 'same tightness')
    Test.expect(b.move_mean > 3 * a.move_mean,
        ('but movement separates them: %.2f vs %.2f'):format(b.move_mean, a.move_mean))
end)

Test.it('move_mean is the mean lane distance between consecutive events', function()
    local ev  = Run(20, 0.5, 120, function(i) return { 96 + (i % 2) * 2 } end)  -- alternate 96/98
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.move_mean - 2.0) < 1e-9, 'every move is 2 lanes; got '
        .. res.move_mean)
end)

Test.it('a chart that never leaves one lane has zero movement', function()
    local ev  = Run(32, 0.25, 120, function() return { 98 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.move_mean == 0 and res.move_p90 == 0, 'no travel at all')
end)

Test.it('move_p90 catches occasional big jumps the mean smooths over', function()
    -- Mostly adjacent steps with a few wide leaps: the mean stays low, the 90th
    -- percentile does not.
    local ev = Run(60, 0.25, 120, function(i)
        if i % 10 == 0 then return { 100 } end
        return { 96 + (i % 2) }
    end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.move_p90 > res.move_mean * 1.5,
        ('p90 %.2f well above mean %.2f'):format(res.move_p90, res.move_mean))
end)

Test.it('anchor_frac is 1.0 when consecutive events always share a lane', function()
    -- A held anchor note with a moving partner: the hand never relocates.
    local ev  = Run(24, 0.5, 120, function(i) return { 96, 98 + (i % 2) } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.anchor_frac - 1.0) < 1e-9,
        'lane 96 is always shared; got ' .. res.anchor_frac)
end)

Test.it('anchor_frac is 0 when no consecutive pair shares a lane', function()
    local ev  = Run(24, 0.5, 120, function(i) return { 96 + (i % 2) * 4 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.anchor_frac == 0, 'green then orange, never both; got '
        .. res.anchor_frac)
end)

Test.it('movement uses the chord centroid, not an arbitrary lowest note', function()
    -- Same lowest gem throughout, but the chord widens: a lowest-note measure would
    -- report zero movement, a centroid correctly reports some.
    local ev  = Run(20, 0.5, 120, function(i)
        if i % 2 == 0 then return { 96, 97 } end
        return { 96, 100 }
    end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.move_mean > 0, 'centroid moves even with a fixed bass gem')
end)

Test.it('a single event yields zero movement rather than an error', function()
    local ev = Run(1, 0.5, 120, Alternating)
    Test.expect(ScoreChart(ev, SpanAll(ev)).move_mean == 0, 'zero, no error')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - hand load: chord size, span and chord changes')

Test.it('chord_size_mean is 1.0 for an all-single-note chart', function()
    local ev = Run(24, 0.5, 120, function() return { 96 } end)
    Test.expect(ScoreChart(ev, SpanAll(ev)).chord_size_mean == 1.0, 'exactly 1')
end)

Test.it('bigger chords raise chord_size_mean at identical event count', function()
    local singles = Run(24, 0.5, 120, function() return { 96 } end)
    local triples = Run(24, 0.5, 120, function() return { 96, 97, 98 } end)
    local a = ScoreChart(singles, SpanAll(singles))
    local b = ScoreChart(triples, SpanAll(triples))
    Test.expect(a.events == b.events, 'same number of events')
    Test.expect(math.abs(b.chord_size_mean - 3.0) < 1e-9, 'three per event; got '
        .. b.chord_size_mean)
end)

Test.it('chord_span_mean measures lane spread, so a wide chord beats an adjacent one', function()
    local narrow = Run(20, 0.5, 120, function() return { 96, 97 } end)   -- adjacent
    local wide   = Run(20, 0.5, 120, function() return { 96, 100 } end)  -- green to orange
    local a = ScoreChart(narrow, SpanAll(narrow))
    local b = ScoreChart(wide,   SpanAll(wide))
    Test.expect(math.abs(a.chord_size_mean - b.chord_size_mean) < 1e-9,
        'same size, so size alone cannot tell them apart')
    Test.expect(math.abs(a.chord_span_mean - 1) < 1e-9, 'adjacent span 1')
    Test.expect(math.abs(b.chord_span_mean - 4) < 1e-9, 'wide span 4')
end)

Test.it('chord_span_mean ignores single notes rather than counting them as span 0', function()
    -- Otherwise "few chords" and "narrow chords" would be indistinguishable.
    local mixed = Run(20, 0.5, 120, function(i)
        if i % 2 == 0 then return { 96, 100 } end
        return { 96 }
    end)
    local res = ScoreChart(mixed, SpanAll(mixed))
    Test.expect(math.abs(res.chord_span_mean - 4) < 1e-9,
        'averaged over chord events only; got ' .. res.chord_span_mean)
end)

Test.it('chord_change_frac counts changes that land on a chord', function()
    -- Changing into a chord means re-forming the whole shape, not moving one finger.
    local to_chords = Run(20, 0.5, 120, function(i) return { 96 + (i % 2), 99 } end)
    local to_single = Run(20, 0.5, 120, Alternating)
    Test.expect(ScoreChart(to_chords, SpanAll(to_chords)).chord_change_frac == 1.0,
        'every change lands on a chord')
    Test.expect(ScoreChart(to_single, SpanAll(to_single)).chord_change_frac == 0.0,
        'none do')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - rest exclusion')

Test.it('silence between two halves must not dilute density', function()
    local a = Run(32, 0.5, 120, Alternating)
    local b = Run(32, 0.5, 120, Alternating, 200)  -- resumes far later
    local both = Concat(a, b)

    local tight = ScoreChart(both, { { s = a[1].s, e = a[#a].e },
                                     { s = b[1].s, e = b[#b].e } })
    local naive = ScoreChart(both, { { s = both[1].s, e = both[#both].e } })

    Test.expect(tight.notes == naive.notes, 'same notes scored either way')
    Test.expect(tight.density_avg > 4 * naive.density_avg,
        ('excluding the rest matters a lot; %.3f vs %.3f'):format(
            tight.density_avg, naive.density_avg))
end)

Test.it('events outside the playing spans are not counted at all', function()
    local ev = Run(32, 0.5, 120, Alternating)
    local half = ScoreChart(ev, { { s = ev[1].s, e = ev[16].e } })
    Test.expect(half.notes == 16, 'only the in-span onsets; got ' .. half.notes)
end)

----------------------------------------------------------------------
Test.section('ScoreChart - zero playing time (wewillrockyou1 PART BASS)')

Test.it('notes with no playing spans give a clean zero, never NaN', function()
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, {})
    Test.expect(res.no_playing_time == true, 'flagged')
    Test.expect(res.density_avg == 0, 'density is exactly 0; got ' .. tostring(res.density_avg))
    Test.expect(res.density_avg == res.density_avg, 'not NaN')
    Test.expect(res.playing_s == 0, 'no playing seconds')
end)

Test.it('a chart with no events at all is also a clean zero', function()
    local res = ScoreChart({}, { { s = 0, e = 10 } })
    Test.expect(res.notes == 0 and res.density_avg == 0, 'zeros, no error')
end)

----------------------------------------------------------------------
Test.section('DeriveSpansFromEvents - the fallback')

Test.it('a continuous run yields exactly one span', function()
    local ev = Run(32, 0.5, 120, Alternating)
    Test.expect(#DeriveSpansFromEvents(ev, 8.0) == 1, 'one span')
end)

Test.it('a long rest splits the chart in two', function()
    local both = Concat(Run(32, 0.5, 120, Alternating),
                        Run(32, 0.5, 120, Alternating, 200))
    Test.expect(#DeriveSpansFromEvents(both, 8.0) == 2, 'two spans')
end)

Test.it('derived spans reproduce the authored-span score on an unambiguous chart', function()
    local a = Run(32, 0.5, 120, Alternating)
    local b = Run(32, 0.5, 120, Alternating, 200)
    local both = Concat(a, b)

    local authored = ScoreChart(both, { { s = a[1].s, e = a[#a].e },
                                        { s = b[1].s, e = b[#b].e } })
    local derived  = ScoreChart(both, DeriveSpansFromEvents(both, 8.0))

    Test.expect(math.abs(authored.density_avg - derived.density_avg) < 1e-9,
        ('fallback matches authored spans; %.4f vs %.4f'):format(
            authored.density_avg, derived.density_avg))
end)

Test.it('no events yields no spans rather than an error', function()
    Test.expect(#DeriveSpansFromEvents({}, 8.0) == 0, 'empty')
end)

Test.it('a sustain outliving the gap cannot produce overlapping spans', function()
    -- The precise shape that used to overlap. A 12 QN sustain at qn 3 runs to qn 15;
    -- the next onset is at qn 12, a 9 QN gap that trips the 8 QN threshold, yet its
    -- own note ends at qn 12.1 - long before the stale end. The old code emitted
    -- 0..7.5 s and 6.0..7.5 s, so TotalSpanSeconds read 9.0 s of playing time for a
    -- 7.5 s chart. Note that resetting cur_e alone is not enough here: the gap is
    -- measured onset-to-onset while a span carries note ends, so the sustain's tail
    -- overruns the next span's start regardless. Merging is what actually settles it.
    local function Ev(qn, len_qn)
        local spq = 0.5   -- 120 bpm
        return { s = qn * spq, e = (qn + len_qn) * spq,
                 qn = qn, qn_e = qn + len_qn, pitches = { 96 } }
    end
    local events = { Ev(0, 0.1), Ev(3, 12.0), Ev(12, 0.1) }

    local spans = DeriveSpansFromEvents(events, 8.0)
    for i = 2, #spans do
        Test.expect(spans[i].s >= spans[i - 1].e,
            ('spans must not overlap; span %d starts %.3f, span %d ended %.3f')
                :format(i, spans[i].s, i - 1, spans[i - 1].e))
    end
    -- The chart runs 0 .. 7.5 s, so that is the ceiling on playing time.
    local total = 0
    for _, sp in ipairs(spans) do total = total + (sp.e - sp.s) end
    Test.expect(math.abs(total - 7.5) < 1e-9,
        ('playing seconds must be the real 7.5, not the double-counted 9.0; got %.3f')
            :format(total))
end)

Test.it('a wide rest still splits when no sustain bridges it', function()
    -- The counterpart: merging must not swallow a genuine rest.
    local both = Concat(Run(8, 0.5, 120, Alternating),
                        Run(8, 0.5, 120, Alternating, 200))
    local spans = DeriveSpansFromEvents(both, 8.0)
    Test.expect(#spans == 2, 'two spans across a real rest; got ' .. #spans)
end)

----------------------------------------------------------------------
Test.section('ScoreChart - segments: no metric may cross a rest')

-- Two 16-note runs, far apart in time, on deliberately different gem shapes so a
-- cross-gap pair would be a change, a big jump AND a wide interval all at once.
local function TwoRuns()
    local a = Run(16, 0.25, 120, function() return { 96 } end)          -- all green
    local b = Run(16, 0.25, 120, function() return { 100 } end, 200)    -- all orange
    return a, b, Concat(a, b)
end

local function SpansOf(...)
    local out = {}
    for _, run in ipairs({ ... }) do
        out[#out + 1] = { s = run[1].s, e = run[#run].e }
    end
    return out
end

Test.it('a gem change across an idle gap is not counted as a change', function()
    local a, b, both = TwoRuns()
    local res = ScoreChart(both, SpansOf(a, b))
    -- Within each run the shape never changes, so the only candidate change in the
    -- whole chart is green->orange across the gap. It must not count.
    Test.expect(res.total_changes == 0,
        'no changes at all; got ' .. res.total_changes)
    Test.expect(res.notes == 32, 'but both runs were still measured; got ' .. res.notes)
end)

Test.it('hand movement is not measured across an idle gap', function()
    local a, b, both = TwoRuns()
    local res = ScoreChart(both, SpansOf(a, b))
    -- green->orange is a 4-lane jump; every within-segment pair moves 0 lanes.
    Test.expect(res.move_mean == 0,
        'no travel inside either run; got ' .. res.move_mean)
    Test.expect(res.move_p90 == 0, 'and no big jumps; got ' .. res.move_p90)
end)

Test.it('the tightness percentiles never see the gap as an interval', function()
    -- Changes inside each run, so intervals exist and the gap could pollute them.
    local a = Run(16, 0.25, 120, Alternating)
    local b = Run(16, 0.25, 120, Alternating, 200)
    local both = Concat(a, b)

    local seg  = ScoreChart(both, SpansOf(a, b))
    local one  = ScoreChart(a, SpansOf(a))

    -- The gap is ~800 QN wide. If it leaked in as an interval the median would be
    -- dragged well above the 0.25 QN spacing the chart is actually built on.
    Test.expect(math.abs(seg.tight_med - one.tight_med) < 1e-9,
        ('median interval matches the single run; %.4f vs %.4f')
            :format(seg.tight_med, one.tight_med))
    Test.expect(seg.tight_med < 1.0,
        'median stays on the 16th-note grid; got ' .. seg.tight_med)
end)

Test.it('peak density does not combine bursts either side of a gap', function()
    -- Two dense bursts 200 QN apart. Each is 16 notes inside ~2 s, so a window
    -- that swallowed both would report roughly double the true peak.
    local a = Run(16, 0.25, 120, function() return { 96 } end)
    local b = Run(16, 0.25, 120, function() return { 96 } end, 200)
    local both = Concat(a, b)

    local seg  = ScoreChart(both, SpansOf(a, b))
    local one  = ScoreChart(a, SpansOf(a))
    Test.expect(seg.density_max <= one.density_max + 1e-9,
        ('peak must not exceed one burst; %.3f vs %.3f')
            :format(seg.density_max, one.density_max))
end)

Test.it('a span holding no notes changes nothing and raises no error', function()
    local a, b, both = TwoRuns()
    -- An extra span in the silence between the two runs. It contains no onsets, so
    -- it adds playing seconds but no segment.
    local empty = { s = both[16].e + 1.0, e = both[16].e + 2.0 }
    local spans = SpansOf(a, b)
    table.insert(spans, 2, empty)

    local with    = ScoreChart(both, spans)
    local without = ScoreChart(both, SpansOf(a, b))
    Test.expect(with.notes == without.notes, 'same notes measured')
    Test.expect(with.total_changes == without.total_changes, 'same changes')
    Test.expect(with.chord_size_mean == without.chord_size_mean, 'same chord load')
    -- The empty span is still real playing time, so the RATES do move. That is
    -- correct: an author marked the instrument as playing there.
    Test.expect(with.playing_s > without.playing_s, 'but it does add playing time')
end)

Test.it('an uninterrupted span scores exactly as it did before segmentation', function()
    -- The regression guard for the whole restructure: with one span there are no
    -- boundaries, so every factor must be untouched by the segment machinery.
    local ev = Run(64, 0.25, 120, function(i)
        if i % 4 == 0 then return { 96, 98 } end
        return { 96 + (i % 5) }
    end)
    local res = ScoreChart(ev, SpanAll(ev))
    -- 63 consecutive pairs, every one a shape change by construction.
    Test.expect(res.total_changes == 63,
        'every pair changes; got ' .. res.total_changes)
    Test.expect(math.abs(res.tight_med - 0.25) < 1e-9,
        'median interval is the note spacing; got ' .. res.tight_med)
    Test.expect(res.move_mean > 0, 'movement is measured; got ' .. res.move_mean)
    Test.expect(res.density_max > 0, 'peak is measured; got ' .. res.density_max)
end)

Test.it('overlapping spans are merged rather than double-counted', function()
    local ev = Run(32, 0.5, 120, Alternating)
    local one = ScoreChart(ev, SpanAll(ev))
    -- The same coverage expressed as two overlapping spans.
    local mid = ev[20].s
    local two = ScoreChart(ev, { { s = ev[1].s, e = mid },
                                 { s = ev[10].s, e = ev[#ev].e } })
    Test.expect(math.abs(one.playing_s - two.playing_s) < 1e-9,
        ('overlap must not inflate playing time; %.4f vs %.4f')
            :format(two.playing_s, one.playing_s))
    Test.expect(one.total_changes == two.total_changes,
        ('merged spans are one segment; %d vs %d')
            :format(two.total_changes, one.total_changes))
end)

Test.it('no within-segment change is reported as unmeasured, not as maximally tight', function()
    -- The trap segmentation creates: with every candidate change falling across a
    -- rest there are no intervals, and the percentiles sit at 0 - which for an
    -- interval factor (smaller is harder) reads as infinitely tight. The value stays
    -- 0 by design; the flag is what lets the corpus run say whether it ever happens.
    local a, b, both = TwoRuns()
    local none = ScoreChart(both, SpansOf(a, b))
    Test.expect(none.tight_measured == false, 'flagged as unmeasured')
    Test.expect(none.tight_p10 == 0 and none.tight_med == 0, 'and left at zero')

    local ev = Run(16, 0.25, 120, Alternating)
    Test.expect(ScoreChart(ev, SpanAll(ev)).tight_measured == true,
        'a normal chart measures its intervals')
end)

Test.it('unsorted spans are handled rather than silently dropping events', function()
    local a, b, both = TwoRuns()
    local fwd = ScoreChart(both, SpansOf(a, b))
    local rev = ScoreChart(both, { SpansOf(a, b)[2], SpansOf(a, b)[1] })
    Test.expect(fwd.notes == rev.notes,
        ('order must not matter; %d vs %d'):format(rev.notes, fwd.notes))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - totals: length must not be invisible')

Test.it('a longer chart at identical density has larger totals', function()
    -- The corpus lesson behind these factors: with only rates and fractions, a
    -- 13-minute epic and a 3-minute song at equal density scored identically, and
    -- officially they are not equally hard.
    local short_ = Run(32,  0.5, 120, Alternating)
    local long_  = Run(256, 0.5, 120, Alternating)
    local a = ScoreChart(short_, SpanAll(short_))
    local b = ScoreChart(long_,  SpanAll(long_))
    Test.expect(math.abs(a.density_avg - b.density_avg) < 0.2,
        'density is near-identical by construction')
    Test.expect(b.notes_total > 6 * a.notes_total, 'notes_total scales with length')
    Test.expect(b.playing_s  > 6 * a.playing_s,    'playing_s scales with length')
    Test.expect(b.total_changes > 6 * a.total_changes, 'total_changes scales too')
end)

Test.it('total_changes is a count, change_rate a rate', function()
    local ev  = Run(64, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.total_changes == 63, 'every event after the first changes; got '
        .. res.total_changes)
    Test.expect(math.abs(res.change_rate - res.total_changes / res.playing_s) < 1e-9,
        'rate is the count over playing time')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - repetition: the technique-vs-volume axis')

Test.it('a looped riff scores high, a never-repeating passage scores 0', function()
    -- This is the factor the residuals asked for: bluemonday (1781 notes of one
    -- repeating bass line, official rank 230) vs wanteddeadoralive2 (240 notes of
    -- shifting shapes, rank 315). Volume and density cannot tell them apart.
    local riff = Run(80, 0.25, 120, function(i) return { 96 + (i % 4) } end)
    local varied = Run(80, 0.25, 120, function(i)
        -- Walk through distinct chord shapes so no 3-gram ever repeats.
        local a = 96 + (i % 5)
        local b = 96 + (math.floor(i / 5) % 5)
        if a == b then return { a } end
        return { math.min(a, b), math.max(a, b) }
    end)
    local r_rep = ScoreChart(riff,   SpanAll(riff)).repetition
    local r_var = ScoreChart(varied, SpanAll(varied)).repetition
    Test.expect(r_rep > 0.8, 'looped riff is highly repetitive; got ' .. r_rep)
    Test.expect(r_var < r_rep, ('varied passage is less repetitive; %.3f vs %.3f')
        :format(r_var, r_rep))
end)

-- DOCUMENTS A KNOWN DEFECT, does not endorse it. The title used to claim this was
-- a length-invariance test while the body asserted the opposite, which is how the
-- confound survived: repetition is a note-count proxy, not a repetitiveness
-- measure (rho ~+0.6/+0.75 against note count, saturating near 1), and the same
-- riff scores higher merely for being played longer. The factor needs a
-- length-invariant form - n-gram entropy or a normalized compression score - or
-- removal; until then this test pins the current behaviour so a replacement can be
-- seen to change it.
Test.it('KNOWN DEFECT - repetition rises with length for an identical riff', function()
    local short_ = Run(40, 0.25, 120, function(i) return { 96 + (i % 4) } end)
    local long_  = Run(80, 0.25, 120, function(i) return { 96 + (i % 4) } end)
    local a = ScoreChart(short_, SpanAll(short_)).repetition
    local b = ScoreChart(long_,  SpanAll(long_)).repetition
    Test.expect(b > a, 'the length dependence, asserted so its removal is visible')
    Test.expect(a > 0.7 and b > 0.85, ('both clearly repetitive; %.3f / %.3f'):format(a, b))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - entropy rate: predictability in bits')

-- The author's arpeggio figure: lanes 1 2 3 2 repeating, which is what `surrender`'s
-- keys chart does for its whole length.
local function Arpeggio(n, qn0, base)
    local pat = { 0, 1, 2, 1 }
    return Run(n, 0.25, 120, function(i)
        return { (base or 96) + pat[((i - 1) % 4) + 1] }
    end, qn0)
end

Test.it('a perfectly predictable figure reads 0 bits at k=2', function()
    -- With two shapes of context the successor is determined, so there is nothing left
    -- to predict. This is the number that says "the hand plays this without deciding".
    local ev  = Arpeggio(80)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.entropy_h2 < 0.10,
        ('a fixed loop should be near 0 bits; got %.4f'):format(res.entropy_h2))
end)

Test.it('a varied passage reads far more bits than a loop', function()
    -- Same vocabulary and the same note count, so only predictability differs.
    local loop = Arpeggio(80)
    local vary = Run(80, 0.25, 120, function(i)
        -- A non-repeating walk over the same three lanes.
        return { 96 + (math.floor(i * i / 3) % 3) }
    end)
    local a = ScoreChart(loop, SpanAll(loop)).entropy_h2
    local b = ScoreChart(vary, SpanAll(vary)).entropy_h2
    Test.expect(b > a + 0.3,
        ('varied must exceed looped by a clear margin; %.4f vs %.4f'):format(b, a))
end)

Test.it('LENGTH-INVARIANT: the same riff twice as long reads the same', function()
    -- THE PROPERTY WHOSE ABSENCE BROKE `repetition`. That measure counted the share of
    -- windows already seen, which rises with length no matter how repetitive the part
    -- is, so it saturated near 1 and correlated -0.008 with rank on keys. An entropy
    -- RATE is a per-symbol quantity: doubling the loop doubles every count and changes
    -- no probability.
    local short_ = Arpeggio(40)
    local long_  = Arpeggio(80)
    local a = ScoreChart(short_, SpanAll(short_)).entropy_h2
    local b = ScoreChart(long_,  SpanAll(long_)).entropy_h2
    Test.expect(math.abs(a - b) < 0.05,
        ('length must not move the entropy; %.4f vs %.4f'):format(a, b))
    -- And the contrast with the old metric, asserted so the improvement is pinned.
    local ra = ScoreChart(short_, SpanAll(short_)).repetition
    local rb = ScoreChart(long_,  SpanAll(long_)).repetition
    Test.expect(rb > ra,
        ('the old measure still drifts with length, by construction; %.3f -> %.3f')
            :format(ra, rb))
end)

Test.it('TRANSPOSITION-INVARIANT: the relative variant ignores hand position', function()
    -- `surrender` plays one figure at G/R/Y, then R/Y/B, then Y/B/O. As motion that is a
    -- single motif; as literal lanes it is three unrelated blocks.
    local at_green  = Arpeggio(40, 0)
    local at_yellow = Arpeggio(40, 0, 98)
    local a = ScoreChart(at_green,  SpanAll(at_green))
    local b = ScoreChart(at_yellow, SpanAll(at_yellow))
    Test.expect(math.abs(a.entropy_h2_rel - b.entropy_h2_rel) < 1e-9,
        ('motion entropy must not depend on position; %.4f vs %.4f')
            :format(a.entropy_h2_rel, b.entropy_h2_rel))

    -- The whole point: one figure moved up mid-song. Literally the lanes change, so the
    -- literal measure sees novelty; as motion nothing changed.
    local shifted = Concat(Arpeggio(40, 0), Arpeggio(40, 40, 98))
    local res = ScoreChart(shifted, SpanAll(shifted))
    Test.expect(res.entropy_h2_rel < res.entropy_h2 + 1e-9,
        ('motion entropy must not exceed literal entropy here; %.4f vs %.4f')
            :format(res.entropy_h2_rel, res.entropy_h2))
    Test.expect(res.entropy_h2_rel < 0.35,
        ('a position shift is still one motif; got %.4f'):format(res.entropy_h2_rel))
end)

Test.it('the context count is reported so a sparse estimate is not trusted blindly', function()
    -- Conditional entropy is biased DOWNWARD when contexts are seen once each, which
    -- would make a short varied chart look perfectly predictable. The count is what
    -- makes that visible in the CSV.
    local ev  = Arpeggio(80)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.entropy_contexts > 0,
        'contexts counted; got ' .. res.entropy_contexts)
    local tiny = ScoreChart(Run(3, 0.5, 120, Alternating), SpanAll(Run(3, 0.5, 120, Alternating)))
    Test.expect(tiny.entropy_contexts <= 1,
        'a 3-note chart supports almost no contexts; got ' .. tiny.entropy_contexts)
end)

Test.it('a chart too short for any context reads zero rather than erroring', function()
    local ev = Run(2, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.entropy_h2 == 0 and res.entropy_h2_rel == 0, 'zeros, no error')
    Test.expect(res.entropy_contexts == 0, 'and no contexts')
end)

Test.it('contexts do not straddle a rest but counts pool across segments', function()
    -- Same rule as every other pair-based factor. Two copies of one figure either side
    -- of a long rest must stay predictable: the motif recurring after a break is the
    -- predictability being measured.
    local a = Arpeggio(40, 0)
    local b = Arpeggio(40, 400)
    local both = Concat(a, b)
    local res = ScoreChart(both, { { s = a[1].s, e = a[#a].e },
                                   { s = b[1].s, e = b[#b].e } })
    Test.expect(res.entropy_h2 < 0.15,
        ('the motif is still predictable across the rest; got %.4f'):format(res.entropy_h2))
end)

Test.it('a riff returning after a rest still counts as a repeat', function()
    -- Windows may not straddle a gap, but the memory of what has been seen must:
    -- verse 2 repeating verse 1's riff is the exact thing this factor looks for.
    local a = Run(24, 0.25, 120, function(i) return { 96 + (i % 4) } end)
    local b = Run(24, 0.25, 120, function(i) return { 96 + (i % 4) } end, 200)
    local both = Concat(a, b)
    local res = ScoreChart(both, { { s = a[1].s, e = a[#a].e },
                                   { s = b[1].s, e = b[#b].e } })
    Test.expect(res.repetition > 0.8,
        'the returning riff is recognised across the rest; got ' .. res.repetition)
end)

Test.it('a chart too short for one n-gram window scores 0 rather than erroring', function()
    local ev = Run(2, 0.5, 120, Alternating)
    Test.expect(ScoreChart(ev, SpanAll(ev)).repetition == 0, 'zero, no error')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - polyphony: held notes (5-lane keys)')

-- The keys idiom guitar forbids: one gem sustained while others are struck under it.
-- `held` is attached by ReadGemEvents in corpus.lua; these tests supply it directly so
-- they stay pure.
local function WithHeld(events, held_fn)
    for i, ev in ipairs(events) do ev.held = held_fn(i) or {} end
    return events
end

Test.it('no held notes reads as zero polyphony, which is every guitar chart', function()
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.overlap_frac == 0, 'no overlap; got ' .. res.overlap_frac)
    Test.expect(res.held_change_frac == 0, 'no held-only changes')
    Test.expect(res.sounding_size_mean == res.chord_size_mean,
        ('with nothing held the two sizes agree; %.3f vs %.3f')
            :format(res.sounding_size_mean, res.chord_size_mean))
end)

Test.it('a sustained gem under a melody is counted as an engaged finger', function()
    -- Green (96) held throughout while a melody moves on 97-99. chord_size_mean sees
    -- single notes; sounding_size_mean sees two fingers.
    local ev = Run(24, 0.25, 120, function(i) return { 97 + (i % 3) } end)
    WithHeld(ev, function(i) return (i > 1) and { 96 } or {} end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.chord_size_mean - 1.0) < 1e-9,
        'every event strikes one gem; got ' .. res.chord_size_mean)
    Test.expect(res.sounding_size_mean > 1.9,
        ('but two fingers are engaged for almost all of it; got %.3f')
            :format(res.sounding_size_mean))
    Test.expect(res.overlap_frac > 0.9,
        ('nearly every onset has something held; got %.3f'):format(res.overlap_frac))
end)

Test.it('held notes do not inflate the struck-note count', function()
    -- The held pitch is already counted at its own onset; counting it again at every
    -- later onset would multiply a song's note total by its polyphony.
    local plain = Run(16, 0.25, 120, Alternating)
    local held  = WithHeld(Run(16, 0.25, 120, Alternating), function() return { 96 } end)
    local a = ScoreChart(plain, SpanAll(plain))
    local b = ScoreChart(held,  SpanAll(held))
    Test.expect(a.notes == b.notes, ('notes unchanged; %d vs %d'):format(b.notes, a.notes))
    Test.expect(a.density_avg == b.density_avg, 'and so is density')
end)

Test.it('re-articulating inside a held shape is not a change in fingers engaged', function()
    -- {96,97} then {97} with 96 still held: the struck set changed, the set of engaged
    -- fingers did not. This is what held_change_frac counts, and it is the measure of
    -- how much the change tally overstates the work on keys.
    local ev = {}
    local spq = 0.5
    for i = 1, 8 do
        local qn = (i - 1) * 0.5
        local t  = qn * spq
        local both = (i % 2 == 1)
        ev[i] = {
            s = t, e = t + 0.1 * spq, qn = qn, qn_e = qn + 0.1,
            pitches = both and { 96, 97 } or { 97 },
            held    = both and {} or { 96 },
        }
    end
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.total_changes > 0, 'the struck sets do change')
    Test.expect(res.held_change_frac > 0.9,
        ('but almost none of those change the engaged fingers; got %.3f')
            :format(res.held_change_frac))
end)

Test.it('a genuine two-voice move still counts as a real change', function()
    -- Green held, melody moving: the engaged set changes every time, so this must NOT
    -- be written off as a held-only change.
    local ev = Run(16, 0.25, 120, function(i) return { 97 + (i % 3) } end)
    WithHeld(ev, function() return { 96 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.held_change_frac == 0,
        ('the engaged set moves with the melody; got %.3f'):format(res.held_change_frac))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - the authored solo (pitch 103)')

-- A chart that is slow for its first half and fast for its second, so a solo
-- marker over one half or the other has an unambiguous expected direction.
-- 32 notes at a quarter note apart, then 32 at a 16th apart.
local function SlowThenFast()
    local slow = Run(32, 1.0, 120, Alternating)          -- qn 0 .. 31
    local fast = Run(32, 0.25, 120, Alternating, 40)     -- qn 40 .. 47.75
    return slow, fast, Concat(slow, fast)
end

Test.it('no solo marker reads as neutral 1.0, not as zero', function()
    -- A 0 would tell the fit the solo is infinitely easier than the rest, and it
    -- would fire on the majority of charts, which have no solo at all.
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.solo_change_ratio == 1.0,
        'neutral; got ' .. res.solo_change_ratio)
    Test.expect(res.solo_measured == false, 'and flagged as unmeasured')
    Test.expect(res.solo_frac_marked == 0, 'no solo coverage')
end)

Test.it('a solo over the fast half scores well above 1', function()
    local _, fast, both = SlowThenFast()
    local res = ScoreChart(both, SpanAll(both), {
        marked_solo_spans = { { s = fast[1].s, e = fast[#fast].e } },
    })
    Test.expect(res.solo_measured == true, 'measured')
    -- 16ths against quarter notes is a 4x change rate in grid terms.
    Test.expect(res.solo_change_ratio > 3.0,
        'the solo is far denser than the rest; got ' .. res.solo_change_ratio)
end)

Test.it('a solo over the slow half scores well below 1', function()
    -- THE ridersonthestorm CASE: a big solo marker over an easy passage must not
    -- read as difficulty. This is what stops solo coverage being mistaken for the
    -- mechanism - the corpus song with the largest solo is one of the easiest.
    local slow, _, both = SlowThenFast()
    local res = ScoreChart(both, SpanAll(both), {
        marked_solo_spans = { { s = slow[1].s, e = slow[#slow].e } },
    })
    Test.expect(res.solo_change_ratio < 0.5,
        'a slow solo is easier than the rest; got ' .. res.solo_change_ratio)
end)

Test.it('solo coverage and solo difficulty are independent measurements', function()
    -- Same coverage fraction, opposite ratios. If these two ever move together the
    -- ratio has collapsed into a coverage proxy.
    local slow, fast, both = SlowThenFast()
    local over_fast = ScoreChart(both, SpanAll(both),
        { marked_solo_spans = { { s = fast[1].s, e = fast[#fast].e } } })
    local over_slow = ScoreChart(both, SpanAll(both),
        { marked_solo_spans = { { s = slow[1].s, e = slow[#slow].e } } })
    Test.expect(over_fast.solo_change_ratio > 1 and over_slow.solo_change_ratio < 1,
        ('ratios straddle 1; %.2f vs %.2f')
            :format(over_fast.solo_change_ratio, over_slow.solo_change_ratio))
end)

Test.it('a solo marker overrunning the playing spans cannot exceed full coverage', function()
    local ev = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev), {
        -- Marker runs far past where the instrument stops playing.
        marked_solo_spans = { { s = ev[1].s, e = ev[#ev].e + 500 } },
    })
    Test.expect(res.solo_frac_marked <= 1.0 + 1e-9,
        'clamped by the playing spans; got ' .. res.solo_frac_marked)
end)

----------------------------------------------------------------------
Test.section('ScoreChart - technique lanes (126 / 127)')

Test.it('lane coverage is measured as a fraction of playing time', function()
    local ev = Run(64, 0.25, 120, Alternating)
    local half = ev[32].e
    local res = ScoreChart(ev, SpanAll(ev), {
        tremolo_spans = { { s = ev[1].s, e = half } },
    })
    Test.expect(res.tremolo_frac > 0.4 and res.tremolo_frac < 0.6,
        'about half the chart; got ' .. res.tremolo_frac)
    Test.expect(res.trill_frac == 0, 'trill unset when no 127 spans given')
end)

Test.it('tremolo and trill stay separate measurements', function()
    -- They are different techniques, and one chart in the corpus sample had one
    -- without the other. Folding them together would hide that.
    local ev = ScoreChart(Run(32, 0.25, 120, Alternating),
                          SpanAll(Run(32, 0.25, 120, Alternating)), {
        trill_spans = { { s = 0, e = 1000 } },
    })
    Test.expect(ev.trill_frac > 0.9 and ev.tremolo_frac == 0,
        ('trill %.2f, tremolo %.2f'):format(ev.trill_frac, ev.tremolo_frac))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - drums: the kick is a third limb, not a chord tone')

local KICK, SNARE, YELLOW, BLUE, GREEN = 96, 97, 98, 99, 100
local function DrumOpts(extra)
    local o = { kick_pitch = KICK, offbeat = true }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

-- THE CENTRAL CLAIM OF THE ROUND. A kick with a snare is a foot and a hand - the
-- backbone of nearly every beat and the easiest combination on the kit. Two sticks
-- landing together is a genuinely harder demand. chord_size_mean scores both at 2.0,
-- which is why stick_size_mean exists; 34.6% of the corpus's drum events are the
-- first case.
Test.it('a foot-plus-hand and a two-stick chart differ only in stick_size_mean', function()
    local foot = Run(24, 0.5, 120, function() return { KICK, SNARE } end)
    local both = Run(24, 0.5, 120, function() return { SNARE, YELLOW } end)
    local a = ScoreChart(foot, SpanAll(foot), DrumOpts())
    local b = ScoreChart(both, SpanAll(both), DrumOpts())

    Test.expect(math.abs(a.chord_size_mean - 2.0) < 1e-9
            and math.abs(b.chord_size_mean - 2.0) < 1e-9,
        ('chord_size_mean cannot tell them apart: %.3f vs %.3f')
            :format(a.chord_size_mean, b.chord_size_mean))
    Test.expect(math.abs(a.stick_size_mean - 1.0) < 1e-9,
        ('one hand busy: got %.3f'):format(a.stick_size_mean))
    Test.expect(math.abs(b.stick_size_mean - 2.0) < 1e-9,
        ('two hands busy: got %.3f'):format(b.stick_size_mean))
end)

Test.it('the hand and foot rates are measured apart', function()
    local ev  = Run(24, 0.5, 120, function() return { KICK, SNARE } end)
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts())
    -- Half the gems are the foot's, so each rate is half the total.
    Test.expect(math.abs(res.kick_density - res.attack_density_avg) < 1e-9,
        'one kick per event, so kicks/sec equals events/sec')
    Test.expect(math.abs(res.kick_density_peak - res.hand_density_peak) < 1e-9,
        ('one of each per event: %.3f vs %.3f')
            :format(res.kick_density_peak, res.hand_density_peak))
    Test.expect(res.density_peak > res.hand_density_peak,
        'gem density counts both limbs and so exceeds either alone')
end)

Test.it('a kick-only chart has no hand load, and a hands-only chart has no foot', function()
    local feet  = Run(24, 0.5, 120, function() return { KICK } end)
    local hands = Run(24, 0.5, 120, function() return { SNARE } end)
    local a = ScoreChart(feet,  SpanAll(feet),  DrumOpts())
    local b = ScoreChart(hands, SpanAll(hands), DrumOpts())
    Test.expect(a.hand_density_peak == 0, 'no hand gems')
    Test.expect(a.stick_size_mean == 0, 'no event carries a hand, so the mean has no terms')
    Test.expect(b.kick_density == 0 and b.kick_density_peak == 0, 'no kicks')
    Test.expect(math.abs(b.hand_density_peak - b.density_peak) < 1e-9,
        'with no foot, the hand rate IS the gem rate')
end)

Test.it('stick_size_mean may exceed chord_size_mean, and that is correct', function()
    -- It averages only over events carrying a hand gem, so kick-only events dilute
    -- chord_size_mean without entering stick_size_mean's denominator. Two real corpus
    -- charts do this (saygoodbyetohollywood 1.4391 vs 1.4273, thepassenger 1.4695 vs
    -- 1.4541), so an invariant asserting the opposite would be wrong - pinned here to stop
    -- it being "fixed".
    local kicks = Run(10, 0.5, 120, function() return { KICK } end)
    local pairs_ = Run(10, 0.5, 120, function() return { SNARE, YELLOW } end, 20)
    local ev  = Concat(kicks, pairs_)
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts())
    Test.expect(math.abs(res.chord_size_mean - 1.5) < 1e-9,
        ('30 gems over 20 events: got %.4f'):format(res.chord_size_mean))
    Test.expect(math.abs(res.stick_size_mean - 2.0) < 1e-9,
        ('20 hand gems over the 10 events that have any: got %.4f'):format(res.stick_size_mean))
    Test.expect(res.stick_size_mean > res.chord_size_mean, 'and so it is the larger of the two')
end)

Test.it('tom markers only count for their own lane', function()
    -- 110 governs yellow, 111 blue, 112 green. A yellow marker over a blue gem changes
    -- nothing, and getting this wrong would report toms on charts that have none.
    local ev = Run(20, 0.5, 120, function() return { BLUE } end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local right = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [BLUE]   = whole } }))
    local wrong = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [YELLOW] = whole } }))
    Test.expect(math.abs(right.tom_frac - 1.0) < 1e-9,
        ('every blue gem under a blue marker: got %.3f'):format(right.tom_frac))
    Test.expect(wrong.tom_frac == 0,
        ('a yellow marker must not claim blue gems: got %.3f'):format(wrong.tom_frac))
end)

Test.it('the kick is never a tom, however the markers are drawn', function()
    local ev = Run(20, 0.5, 120, function() return { KICK, SNARE } end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local res = ScoreChart(ev, SpanAll(ev),
        DrumOpts({ tom_spans = { [YELLOW] = whole, [BLUE] = whole } }))
    Test.expect(res.tom_frac == 0, 'neither the pedal nor the snare has a tom form')
end)

Test.it('roll lanes are a fraction of playing time, like the guitar technique lanes', function()
    local ev = Run(64, 0.25, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev),
        DrumOpts({ roll_spans = { { s = ev[1].s, e = ev[32].e } } }))
    Test.expect(res.roll_frac > 0.4 and res.roll_frac < 0.6,
        ('about half: got %.3f'):format(res.roll_frac))
    Test.expect(res.trill_frac == 0 and res.tremolo_frac == 0,
        'and it does not leak into the guitar-named columns')
end)

Test.it('the noroll peaks discount a roll lane and the originals do NOT move', function()
    -- makemesmile2 reduced: the densest passage sits under a roll lane, which is a
    -- leniency device rather than a demand to hit every gem. The twin must see that and
    -- the shipped column must not - it is fitted in five models, and silently redefining
    -- it would re-open every instrument at once.
    local ev = Run(64, 0.25, 120, Alternating)
    local plain = ScoreChart(ev, SpanAll(ev), DrumOpts({}))
    local rolled = ScoreChart(ev, SpanAll(ev),
        DrumOpts({ roll_spans = { { s = ev[1].s, e = ev[32].e } } }))
    Test.expect(rolled.density_peak == plain.density_peak,
        'density_peak is untouched by the presence of a lane')
    Test.expect(rolled.attack_density_peak == plain.attack_density_peak,
        'and so is attack_density_peak')
    Test.expect(rolled.density_peak_noroll < plain.density_peak_noroll,
        'while the twin drops once half the gems stop counting')
    Test.expect(rolled.hand_density_peak_noroll < rolled.hand_density_peak,
        'the hand twin discounts the lane too')
end)

Test.it('an instrument with no roll lanes gets twins equal to the originals', function()
    -- A structural zero here would read as "this chart has no peak density", which is a
    -- different claim and would put every guitar row several sd from the column mean.
    local ev = Run(24, 0.5, 120, function() return { 96 } end)
    local g = ScoreChart(ev, SpanAll(ev), {})
    Test.expect(g.density_peak_noroll == g.density_peak,
        'guitar carries no roll_spans, so the twin IS the original')
    Test.expect(g.attack_density_peak_noroll == g.attack_density_peak,
        'the same for attacks')
    Test.expect(g.hand_density_peak_noroll == g.hand_density_peak,
        'and for hands')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - Pro Drums: a tom and a cymbal are two different gems')

-- The claim being tested by the whole @pro candidate family. Under the standard five-gem
-- vocabulary a yellow cymbal and a yellow tom are the same gem, so alternating between
-- them is not a change at all. Under the Pro vocabulary it is.
Test.it('alternating cymbal and tom on one colour is invisible to the five-gem read', function()
    local ev = Run(32, 0.5, 120, function() return { YELLOW } end)
    -- Marker over every other gem, so the chart alternates cymbal, tom, cymbal, tom.
    local spans = {}
    for i = 2, #ev, 2 do spans[#spans + 1] = { s = ev[i].s - 0.001, e = ev[i].e + 0.001 } end
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [YELLOW] = spans } }))

    Test.expect(res.total_changes == 0,
        ('five gems: one repeated yellow, no changes; got %d'):format(res.total_changes))
    Test.expect(res.pro_total_changes > 0,
        ('eight gems: every onset switches pad; got %d'):format(res.pro_total_changes))
    Test.expect(res.pro_total_changes == #ev - 1,
        ('every consecutive pair is a change; got %d of %d')
            :format(res.pro_total_changes, #ev - 1))
end)

Test.it('the Pro read is identical when no marker is present', function()
    -- The overwhelming majority of gems on any chart, so the two vocabularies must agree
    -- wherever the author did not mark a tom.
    local ev  = Run(24, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [YELLOW] = {} } }))
    Test.expect(res.pro_total_changes == res.total_changes, 'changes agree')
    Test.expect(math.abs(res.pro_tight_p10 - res.tight_p10) < 1e-9, 'intervals agree')
    Test.expect(math.abs(res.pro_entropy_h2 - res.entropy_h2) < 1e-9, 'entropy agrees')
end)

Test.it('a marker on the wrong lane changes nothing in the Pro read either', function()
    local ev  = Run(24, 0.5, 120, function() return { BLUE } end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [YELLOW] = whole } }))
    Test.expect(res.pro_total_changes == res.total_changes,
        'a yellow marker cannot make a blue gem a tom')
end)

Test.it('a wholly-marked chart is as repetitive as a wholly-unmarked one', function()
    -- Every gem a tom is still one repeated gem: the vocabulary must add a distinction
    -- only where the chart actually switches, not a blanket penalty for using markers.
    local ev = Run(24, 0.5, 120, function() return { BLUE } end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local marked   = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [BLUE] = whole } }))
    local unmarked = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [BLUE] = {} } }))
    Test.expect(marked.pro_total_changes == 0 and unmarked.pro_total_changes == 0,
        ('%d and %d'):format(marked.pro_total_changes, unmarked.pro_total_changes))
    Test.expect(math.abs(marked.tom_frac - 1.0) < 1e-9,
        'while tom_frac correctly reports full coverage')
end)

Test.it('ProRemapEvents leaves the caller list alone and keeps pitches sorted', function()
    local ev = Run(4, 0.5, 120, function() return { SNARE, YELLOW } end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local out = ProRemapEvents(ev, { [YELLOW] = whole })
    Test.expect(ev[1].pitches[2] == YELLOW, 'the input event is untouched')
    -- 97.5 sits between the snare at 97 and the yellow cymbal at 98, which is the whole
    -- point of the half-lane offset: rack tom 1 is beside the snare, the hihat further out.
    Test.expect(out[1].pitches[1] == SNARE and out[1].pitches[2] == YELLOW - 0.5,
        ('a yellow tom sorts between snare and yellow cymbal: got %s, %s')
            :format(tostring(out[1].pitches[1]), tostring(out[1].pitches[2])))
    Test.expect(out[1].qn == ev[1].qn and out[1].s == ev[1].s, 'timing carried over')
end)

-- THE GUARANTEE THAT MAKES THE OFFSET SAFE. Every factor the Pro pass keeps reads set
-- identity, so the offset is a symbol rather than a distance and its size cannot move a
-- result. Pinned here because the day someone adds a Pro-aware DISTANCE factor
-- (pro_move_mean), that stops being true and this test is where they find out - on the
-- RB3 kit the cymbals mount above and behind the pads, so reaching the yellow pad and the
-- yellow cymbal is nearly the same move, not the 2:1 a half-lane offset would imply.
Test.it('the kept Pro factors do not depend on the size of the offset', function()
    local ev = Run(48, 0.5, 140, function(i)
        local pats = { { SNARE }, { YELLOW }, { SNARE, YELLOW }, { BLUE } }
        return pats[(i - 1) % 4 + 1]
    end)
    -- Marked in alternating stretches, so tom/cymbal boundaries actually occur.
    local spans = {}
    for i = 1, #ev, 4 do
        spans[#spans + 1] = { s = ev[i].s - 0.001, e = ev[math.min(i + 1, #ev)].e + 0.001 }
    end

    -- Remap by hand at an arbitrary offset and score, bypassing ProRemapEvents.
    local function ScoreAt(offset)
        local out = {}
        for i, e in ipairs(ev) do
            local p = {}
            for j, x in ipairs(e.pitches) do
                local inside = false
                if x == YELLOW then
                    for _, sp in ipairs(spans) do
                        if e.s >= sp.s and e.s <= sp.e then inside = true end
                    end
                end
                p[j] = inside and (x + offset) or x
            end
            table.sort(p)
            out[i] = { s = e.s, e = e.e, qn = e.qn, qn_e = e.qn_e, pitches = p }
        end
        return ScoreChart(out, SpanAll(ev))
    end

    local ref = ScoreAt(-0.5)
    Test.expect(ref.total_changes > 0, 'the fixture has to actually change to be a test')
    for _, offset in ipairs({ -0.9, -0.1, 0.25, 0.5, 3.0 }) do
        local sc = ScoreAt(offset)
        Test.expect(sc.total_changes == ref.total_changes,
            ('total_changes at offset %+.2f: %d vs %d')
                :format(offset, sc.total_changes, ref.total_changes))
        Test.expect(math.abs(sc.tight_p10 - ref.tight_p10) < 1e-12
                and math.abs(sc.tight_med - ref.tight_med) < 1e-12,
            ('change intervals at offset %+.2f'):format(offset))
        Test.expect(math.abs(sc.entropy_h2 - ref.entropy_h2) < 1e-12,
            ('entropy at offset %+.2f: %.9f vs %.9f')
                :format(offset, sc.entropy_h2, ref.entropy_h2))
    end
    -- And the contrast that explains why: distance DOES move, which is why move_* is not
    -- among the columns the Pro pass keeps.
    Test.expect(math.abs(ScoreAt(3.0).move_mean - ref.move_mean) > 1e-6,
        'lane distance is offset-sensitive, so it must stay out of the Pro columns')
end)

Test.it('the Pro pass does not run for instruments without tom markers', function()
    local ev  = Run(24, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.pro_total_changes == 0 and res.pro_entropy_h2 == 0,
        'no tom_spans means the columns stay at their neutral 0')
    Test.expect(res.pro_stations_peak == 0, 'and the station count likewise')
end)

-- WHY pro_stations_peak IS THE FACTOR THAT SURVIVED. The corpus pre-check found the
-- eight-gem vocabulary raises total_changes by +0.0% - authors use toms for one section
-- and cymbals for another, so only marker boundaries create a change, 36 in the whole
-- corpus. What it DOES change is how many different places the hand must cover, and the
-- five-gem version of that measure is saturated (4.77 of 5 across the corpus, p25 and p75
-- both 5) while the eight-gem version spreads from 2 to 8.
Test.it('a colour used as both tom and cymbal is two stations, not one', function()
    local ev = Run(32, 0.5, 120, function(i)
        -- Only three lanes are ever touched, so the five-gem count cannot exceed 3.
        local pats = { { SNARE }, { YELLOW }, { BLUE }, { YELLOW } }
        return pats[(i - 1) % 4 + 1]
    end)
    -- First half of the chart plays its yellows and blues as toms, second half as cymbals.
    local half = ev[#ev // 2].e
    local spans = { { s = ev[1].s, e = half } }
    local res = ScoreChart(ev, SpanAll(ev),
        DrumOpts({ tom_spans = { [YELLOW] = spans, [BLUE] = spans } }))

    Test.expect(res.stations_peak == 3,
        ('three lanes touched: got %s'):format(tostring(res.stations_peak)))
    Test.expect(res.pro_stations_peak > res.stations_peak,
        ('the Pro read must see more places: %s vs %s')
            :format(tostring(res.pro_stations_peak), tostring(res.stations_peak)))
    -- And the change count is nearly unmoved, which is the pre-check's finding in miniature.
    Test.expect(res.pro_total_changes - res.total_changes <= 2,
        ('a sectional marker adds changes only at its boundary: %d vs %d')
            :format(res.pro_total_changes, res.total_changes))
end)

Test.it('a chart that never switches a colour form gains no extra stations', function()
    -- Blue is always a tom, so Pro sees the same number of places as the standard read.
    local ev = Run(24, 0.5, 120, function(i)
        return ({ { SNARE }, { BLUE } })[(i - 1) % 2 + 1]
    end)
    local whole = { { s = ev[1].s, e = ev[#ev].e } }
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts({ tom_spans = { [BLUE] = whole } }))
    Test.expect(res.pro_stations_peak == res.stations_peak,
        ('%s vs %s'):format(tostring(res.pro_stations_peak), tostring(res.stations_peak)))
end)

Test.it('the station count is a window measure, not a whole-chart one', function()
    -- Two lanes early and two different lanes late: the chart uses four, but no eight-second
    -- window sees more than two. A chart-level count would miss that distinction entirely.
    local early = Run(16, 0.5, 120, function(i)
        return ({ { SNARE }, { YELLOW } })[(i - 1) % 2 + 1] end)
    local late  = Run(16, 0.5, 120, function(i)
        return ({ { BLUE }, { GREEN } })[(i - 1) % 2 + 1] end, 400)
    local ev  = Concat(early, late)
    local res = ScoreChart(ev, SpanAll(ev), DrumOpts())
    Test.expect(res.stations_peak == 2,
        ('two at a time despite four overall: got %s'):format(tostring(res.stations_peak)))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - syncopation')

Test.it('offbeat_frac counts onsets off the quarter-note grid', function()
    local quarters = Run(16, 1.0,  120)
    local eighths  = Run(16, 0.5,  120)
    local teenths  = Run(16, 0.25, 120)
    local a = ScoreChart(quarters, SpanAll(quarters), { offbeat = true })
    local b = ScoreChart(eighths,  SpanAll(eighths),  { offbeat = true })
    local c = ScoreChart(teenths,  SpanAll(teenths),  { offbeat = true })
    Test.expect(a.offbeat_frac == 0, ('quarters are all on the beat: %.3f'):format(a.offbeat_frac))
    Test.expect(math.abs(b.offbeat_frac - 0.5) < 1e-9,
        ('every other 8th is off: %.3f'):format(b.offbeat_frac))
    Test.expect(math.abs(c.offbeat_frac - 0.75) < 1e-9,
        ('three of four 16ths are off: %.3f'):format(c.offbeat_frac))
end)

Test.it('it is tempo-independent, because the grid is not seconds', function()
    -- The same figure at half the tempo is the same rhythm and must read the same, which
    -- is why this is measured in quarter notes rather than in time.
    local slow = Run(16, 0.5, 80)
    local fast = Run(16, 0.5, 200)
    local a = ScoreChart(slow, SpanAll(slow), { offbeat = true })
    local b = ScoreChart(fast, SpanAll(fast), { offbeat = true })
    Test.expect(math.abs(a.offbeat_frac - b.offbeat_frac) < 1e-9,
        ('%.3f vs %.3f'):format(a.offbeat_frac, b.offbeat_frac))
end)

Test.it('a swung or dragged onset still counts as off the beat', function()
    -- The tolerance exists for tempo-map float error, not for humanised timing: an onset
    -- a 32nd late is a real syncopation and must not be rounded onto the beat.
    local ev = Run(8, 1.0, 120)
    for i = 2, #ev, 2 do ev[i].qn = ev[i].qn + 0.125 end
    local res = ScoreChart(ev, SpanAll(ev), { offbeat = true })
    Test.expect(math.abs(res.offbeat_frac - 0.5) < 1e-9,
        ('half the onsets dragged: got %.3f'):format(res.offbeat_frac))
end)

----------------------------------------------------------------------
Test.section('ScoreChart - sustains')

Test.it('long notes register as sustains, short ones do not', function()
    local short_ = Run(32, 1.0, 120, Alternating, nil, 0.1)  -- well under an 8th
    local long_  = Run(32, 1.0, 120, Alternating, nil, 0.9)  -- comfortably over
    Test.expect(ScoreChart(short_, SpanAll(short_)).sustain_frac == 0, 'no sustains')
    Test.expect(ScoreChart(long_,  SpanAll(long_)).sustain_frac  == 1, 'all sustains')
end)

Test.it('sustain_frac reports as unmeasured when the caller omits note ends', function()
    -- A caller that has not been updated must not look like "this chart has no
    -- sustains" - that is a different claim from "nobody measured".
    local ev = Run(16, 1.0, 120, Alternating, nil, 0.9)
    for _, e in ipairs(ev) do e.qn_e = nil end
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.sustain_measured == false, 'flagged as not measured')
    Test.expect(res.sustain_frac == 0, 'and reported as 0')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - solo fraction and HOPO rate')

Test.it('a chart entirely inside a solo span reads 1.0', function()
    local ev = Run(32, 0.5, 120, Alternating)
    local spans = SpanAll(ev)
    local res = ScoreChart(ev, spans, { solo_spans = spans })
    Test.expect(math.abs(res.solo_frac - 1.0) < 1e-9, 'got ' .. res.solo_frac)
end)

Test.it('a solo covering half the playing time reads ~0.5', function()
    local ev    = Run(64, 0.5, 120, Alternating)
    local spans = SpanAll(ev)
    local mid   = spans[1].s + (spans[1].e - spans[1].s) / 2
    local res = ScoreChart(ev, spans, { solo_spans = { { s = spans[1].s, e = mid } } })
    Test.expect(math.abs(res.solo_frac - 0.5) < 0.02, 'got ' .. res.solo_frac)
end)

Test.it('no solo spans reads 0', function()
    local ev = Run(16, 0.5, 120, Alternating)
    Test.expect(ScoreChart(ev, SpanAll(ev)).solo_frac == 0, 'zero')
end)

Test.it('force-HOPO and force-strum are kept separate, not summed', function()
    -- They push difficulty in OPPOSITE directions: a force-HOPO removes a required
    -- strum (easier), a force-strum adds one back (harder). An earlier single
    -- hopo_rate summed the two marker pitches, which cancels the signal.
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev),
        { force_hopo_count = 30, force_strum_count = 5 })
    Test.expect(math.abs(res.force_hopo_rate - 30 / res.playing_s) < 1e-9,
        'hopo rate; got ' .. res.force_hopo_rate)
    Test.expect(math.abs(res.force_strum_rate - 5 / res.playing_s) < 1e-9,
        'strum rate; got ' .. res.force_strum_rate)
    Test.expect(res.force_hopo_rate ~= res.force_strum_rate, 'and they are distinct')
end)

Test.it('absent marker counts read 0 rather than nil', function()
    local ev   = Run(16, 0.5, 120, Alternating)
    local none = ScoreChart(ev, SpanAll(ev))
    Test.expect(none.force_hopo_rate == 0 and none.force_strum_rate == 0, 'both zero')
end)

----------------------------------------------------------------------
Test.section('ScoreChart - Pro Keys: the display window moves')

-- Lane-shift markers as ScoreChart consumes them: ordered { s, base }, where base is
-- the window's base pitch. The reader (ReadLaneShifts) whitelists the six documented
-- marker pitches and maps them through pitch + 48; these tests drive the arithmetic
-- that sits on the far side of that.
local function Shifts(bases, step)
    local out = {}
    for i, b in ipairs(bases) do out[i] = { s = (i - 1) * (step or 4), base = b } end
    return out
end

local PK_BASE = { C2 = 48, D2 = 50, E2 = 52, F2 = 53, G2 = 55, A2 = 57 }

Test.it('the mandatory opening marker alone is ZERO shifts, not one', function()
    -- Every Pro Keys difficulty must carry a range marker at the start of the song, so
    -- a marker COUNT starts at 1 for a chart that never shifts. 35 of the 123 corpus
    -- charts are exactly this case - 28% of the instrument - and counting markers
    -- instead of transitions would make all of them look like one-shift charts.
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev), { lane_shifts = Shifts({ PK_BASE.C2 }) })
    Test.expect(res.shift_rate == 0, 'opener only scores no shift')
    Test.expect(res.shift_span_mean == 0, 'and no shift magnitude')
end)

Test.it('a marker that re-asserts the SAME range is not a shift', function()
    -- 28 of 538 corpus transitions (5.2%, across 10 charts) re-state the range already
    -- displayed. Nothing moves on screen, so nothing should be counted.
    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev),
        { lane_shifts = Shifts({ PK_BASE.C2, PK_BASE.C2, PK_BASE.C2 }) })
    Test.expect(res.shift_rate == 0, 'three identical markers are still no shift')
end)

Test.it('a real range change is counted, and sized in semitones', function()
    local ev  = Run(32, 0.5, 120, Alternating)   -- 16 QN at 120bpm = 8 s of playing
    local res = ScoreChart(ev, SpanAll(ev),
        { lane_shifts = Shifts({ PK_BASE.C2, PK_BASE.F2, PK_BASE.C2 }) })
    Test.expect(math.abs(res.shift_rate * res.playing_s - 2) < 1e-9,
        ('two shifts over the playing time; got %.4f/s x %.3f s')
            :format(res.shift_rate, res.playing_s))
    -- C2 -> F2 and back is 5 semitones each way.
    Test.expect(math.abs(res.shift_span_mean - 5) < 1e-9,
        ('mean shift 5 semitones; got %.3f'):format(res.shift_span_mean))
end)

Test.it('shift magnitude is absolute - down counts the same as up', function()
    -- The window moving four semitones is the same relocation whichever way it goes.
    -- Signed arithmetic here would let a chart that shifts up and back cancel to zero.
    local ev = Run(32, 0.5, 120, Alternating)
    local up = ScoreChart(ev, SpanAll(ev),
        { lane_shifts = Shifts({ PK_BASE.C2, PK_BASE.E2 }) })
    local dn = ScoreChart(ev, SpanAll(ev),
        { lane_shifts = Shifts({ PK_BASE.E2, PK_BASE.C2 }) })
    Test.expect(up.shift_span_mean == dn.shift_span_mean, 'same magnitude either way')
    Test.expect(math.abs(up.shift_span_mean - 4) < 1e-9, 'C2 to E2 is 4 semitones')
end)

Test.it('the shift columns are a structural zero without lane_shifts', function()
    -- No other instrument has a moving window, so every non-Pro-Keys row must read 0
    -- rather than nil - a nil would break the CSV writer and the fit alike.
    local ev  = Run(16, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.shift_rate == 0 and res.shift_span_mean == 0, 'both zero')
end)

Test.it('126 as a glissando lane is a different column from 126 as tremolo', function()
    -- Same pitch, opposite meaning: a glissando marker turns scoring OFF for the notes
    -- under it (easier), while tremolo on guitar marks a passage too fast to chart
    -- literally (harder). Routing both through one column would fit one measurement
    -- under two contradictory signs.
    local ev   = Run(32, 0.5, 120, Alternating)
    local half = { { s = ev[1].s, e = ev[16].e } }
    local g = ScoreChart(ev, SpanAll(ev), { gliss_spans = half })
    local t = ScoreChart(ev, SpanAll(ev), { tremolo_spans = half })
    Test.expect(g.gliss_frac > 0, 'gliss_spans fills gliss_frac')
    Test.expect(g.tremolo_frac == 0, 'and leaves tremolo_frac alone')
    Test.expect(t.tremolo_frac > 0, 'tremolo_spans fills tremolo_frac')
    Test.expect(t.gliss_frac == 0, 'and leaves gliss_frac alone')
    Test.expect(math.abs(g.gliss_frac - t.tremolo_frac) < 1e-9,
        'the same spans measure the same fraction under either name')
end)

Test.it('a 4-note chord is one event of size 4', function()
    -- Expert Pro Keys allows up to 4-note chords where 5-lane keys caps at 3 (982
    -- corpus events, and zero over 4). The onset grouping must not split them.
    local ev  = Run(16, 1.0, 120, function() return { 48, 52, 55, 60 } end)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(res.events == 16, 'sixteen events')
    Test.expect(res.notes == 64, 'sixty-four gems')
    Test.expect(math.abs(res.chord_size_mean - 4) < 1e-9,
        ('chord_size_mean 4; got %.3f'):format(res.chord_size_mean))
end)

Test.it('finger reassignment sees work that chord centroid misses', function()
    local ev = Run(16, 0.5, 120, function(i)
        return (i % 2 == 0) and { 48, 60 } or { 52, 56 }
    end)
    local res = ScoreChart(ev, SpanAll(ev), { pro_keys = true })
    Test.expect(res.move_mean == 0, 'both chord shapes have the same centroid')
    Test.expect(res.finger_reassign_mean > 0, 'all fingers still have to move')
    Test.expect(res.finger_reassign_peak > 0, 'the local peak sees repeated re-voicing')
end)

Test.it('shared pitches retain fingers at zero cost', function()
    local ev = Run(12, 0.5, 120, function() return { 48, 52, 55 } end)
    local res = ScoreChart(ev, SpanAll(ev), { pro_keys = true })
    Test.expect(res.finger_reassign_mean == 0, 'an unchanged chord needs no reassignment')
end)

Test.it('held independence is a local articulation rate', function()
    local ev = Run(20, 0.25, 120, function(i) return { 52 + (i % 2) } end)
    for _, e in ipairs(ev) do e.held = { 48 } end
    local held = ScoreChart(ev, SpanAll(ev), { pro_keys = true, peak_window_s = 2 })
    for _, e in ipairs(ev) do e.held = {} end
    local free = ScoreChart(ev, SpanAll(ev), { pro_keys = true, peak_window_s = 2 })
    Test.expect(held.held_independence_peak > 0, 'articulation under a held voice counts')
    Test.expect(free.held_independence_peak == 0, 'the same attacks without a hold do not')
end)

Test.it('local complexity requires density and unpredictability in the same window', function()
    local repeated = Run(48, 0.25, 120, function(i) return { 96 + (i % 2) } end)
    local varied = Run(48, 0.25, 120, function(i)
        return { 96 + ((i * i + math.floor(i / 3)) % 5) }
    end)
    local a = ScoreChart(repeated, SpanAll(repeated), { peak_window_s = 2 })
    local b = ScoreChart(varied, SpanAll(varied), { peak_window_s = 2 })
    Test.expect(b.complex_peak > a.complex_peak,
        'varied motion scores above an equally dense alternating pattern')
end)

----------------------------------------------------------------------
Test.section('SCORE_FACTOR_KEYS - every key is actually produced')

Test.it('the factor list and the scorer output agree', function()
    -- Guards the CSV writer and the analysis, which both drive off this list: a key
    -- here that NEITHER scorer sets would silently become an empty column.
    --
    -- Since round 11, SCORE_FACTOR_KEYS is the UNION of the gem set and the vocal set -
    -- difficulty_score_vocals.lua appends its own columns to it. So ScoreChart is
    -- responsible for every key that is not vocal-only, and the vocal-only ones are
    -- covered by the matching test in difficulty_score_vocals.lua. The row writer fills
    -- the other set with zeros, which is what makes a gem row and a vocal row the same
    -- width.
    local vocal_only = {}
    if VOCAL_FACTOR_KEYS then
        local gem = {
            -- The four names the two scorers genuinely share, measured the same way in
            -- both. They are NOT vocal-only and ScoreChart must still produce them.
            playing_s = true, tight_p10 = true, tight_med = true, entropy_h2_rel = true,
        }
        for _, k in ipairs(VOCAL_FACTOR_KEYS) do
            if not gem[k] then vocal_only[k] = true end
        end
    end

    local ev  = Run(32, 0.5, 120, Alternating)
    local res = ScoreChart(ev, SpanAll(ev), {
        solo_spans = SpanAll(ev), force_hopo_count = 3, force_strum_count = 1,
    })
    for _, k in ipairs(SCORE_FACTOR_KEYS) do
        if not vocal_only[k] then
            Test.expect(type(res[k]) == 'number', 'gem factor ' .. k .. ' is a number')
        end
    end
end)

Test.it('every lean-set key exists in the full factor list', function()
    -- The analysis slices lean sets out of the full feature vector by name, so a typo
    -- would silently skip a whole comparison row.
    local known = {}
    for _, k in ipairs(SCORE_FACTOR_KEYS) do known[k] = true end
    for _, S in ipairs(SCORE_LEAN_SETS) do
        for _, k in ipairs(S.keys) do
            Test.expect(known[k], ('lean set "%s" references unknown factor %s')
                :format(S.name, k))
        end
    end
end)

Test.it('the interaction factors really are exact products, as documented', function()
    -- notes_total == density_avg * playing_s and total_changes == change_rate *
    -- playing_s. Asserted because the doc and the coefficient warnings depend on it.
    local ev  = Run(48, 0.5, 132, Alternating)
    local res = ScoreChart(ev, SpanAll(ev))
    Test.expect(math.abs(res.density_avg * res.playing_s - res.notes_total) < 1e-6,
        'notes_total is the product')
    Test.expect(math.abs(res.change_rate * res.playing_s - res.total_changes) < 1e-6,
        'total_changes is the product')
end)
