-- Tempo handling for the difficulty scorer, END TO END through REAPER.
--
-- WHY THIS EXISTS SEPARATELY FROM difficulty_score.lua's TESTS. Those drive
-- ScoreChart with synthetic event tables that already carry a `qn` field, so they
-- prove the scorer's arithmetic and nothing else. The whole tempo path -
-- MIDI_GetProjTimeFromPPQPos, TimeMap2_timeToQN, and the project tempo map itself -
-- lives in corpus.lua's readers and was never covered by any test. The corpus run's
-- bpm_at_first_note column guards a total tempo-import failure, but it samples one
-- note and cannot see a tempo CHANGE being mishandled.
--
-- So these tests build real MIDI takes in the project, read them back through the
-- REAL readers (ReadGemEvents / ReadPlayingSpans), and assert the two properties
-- that make the factor set coherent:
--
--   REAL-TIME factors scale with tempo      density_avg, density_peak, change_rate
--                                            (and playing_s inversely)
--   GRID factors are tempo-INVARIANT        tight_p10, tight_med
--   COUNTS are tempo-invariant              notes, total_changes, chord_size_mean
--
-- Confusing those two families is the one silent failure this design invites: a
-- sixteenth note is 0.25 QN at any tempo, and a tightness factor that started
-- tracking tempo would look like a stronger predictor while measuring the same
-- thing density already measures.
--
-- Requires (globals): Test.* (framework), LoadFixture/CleanupFixture/
-- CreateEmptyFixtureTrack (fixture_helpers), ReadGemEvents/ReadPlayingSpans
-- (dev/calibration/corpus.lua), ScoreChart (dev/calibration/difficulty_score.lua).

local EXPERT_LO = 96

----------------------------------------------------------------------
-- Building a real chart in the project
----------------------------------------------------------------------

-- Replace the tempo map with a single tempo, or with `changes` = { {qn, bpm}, ... }.
-- Positions are given in quarter notes and converted, so a test can say "double the
-- tempo at bar 5" without computing seconds.
local function SetTempo(bpm, changes)
    -- Overwrite marker 0 rather than deleting it: REAPER refuses to delete the last
    -- tempo marker (the same constraint fixture_helpers documents).
    for i = r.CountTempoTimeSigMarkers(0) - 1, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, i)
    end
    if r.CountTempoTimeSigMarkers(0) == 0 then
        r.AddTempoTimeSigMarker(0, 0, bpm, 4, 4, false)
    else
        r.SetTempoTimeSigMarker(0, 0, 0, -1, -1, bpm, 4, 4, false)
    end
    for _, c in ipairs(changes or {}) do
        -- QN -> time under the map as it stands so far, which is why the changes must
        -- be applied in ascending order.
        r.AddTempoTimeSigMarker(0, r.TimeMap2_QNToTime(0, c[1]), c[2], 4, 4, false)
    end
    r.UpdateTimeline()
end

-- A PART GUITAR track carrying n gem notes at qn_step spacing, plus the [play] /
-- [idle] animation pair so ReadPlayingSpans finds a real span rather than falling
-- back to deriving one.
--
-- Returns the track index. Note lengths are set in QN so they stay musically the
-- same at every tempo - a length in seconds would make sustain_frac tempo-dependent
-- and confound the very thing being measured.
local function BuildChart(n, qn_step, pitches_fn, len_qn)
    local idx   = CreateEmptyFixtureTrack('PART GUITAR')
    local track = r.GetTrack(0, idx)
    local last_qn = (n - 1) * qn_step
    local item  = r.CreateNewMIDIItemInProj(track, 0,
                      r.TimeMap2_QNToTime(0, last_qn + 4))
    local take  = r.GetActiveTake(item)

    for i = 1, n do
        local qn  = (i - 1) * qn_step
        local sp  = r.MIDI_GetPPQPosFromProjQN(take, qn)
        local ep  = r.MIDI_GetPPQPosFromProjQN(take, qn + (len_qn or 0.1))
        local pit = pitches_fn and pitches_fn(i) or { EXPERT_LO }
        for _, p in ipairs(pit) do
            r.MIDI_InsertNote(take, false, false, sp, ep, 0, p, 96, false)
        end
    end
    -- Animation states, so the playing span is authored rather than derived.
    r.MIDI_InsertTextSysexEvt(take, false, false,
        r.MIDI_GetPPQPosFromProjQN(take, 0), 1, '[play]')
    r.MIDI_InsertTextSysexEvt(take, false, false,
        r.MIDI_GetPPQPosFromProjQN(take, last_qn + 1), 1, '[idle]')
    return idx, track
end

-- Score a freshly built chart through the real REAPER readers.
local function ScoreBuilt(track)
    local events = ReadGemEvents(track, EXPERT_LO, EXPERT_LO + 4)
    local spans  = ReadPlayingSpans(track)
    return ScoreChart(events, spans)
end

local function Alternating(i) return { EXPERT_LO + (i % 2) } end

-- Build, score and clean up in one call, so no test can leak a track.
local function ScoreAtTempo(bpm, changes, n, qn_step)
    local base = r.CountTracks(0)
    SetTempo(bpm, changes)
    local _, track = BuildChart(n or 64, qn_step or 0.25, Alternating)
    local sc = ScoreBuilt(track)
    CleanupFixture(base)
    return sc
end

----------------------------------------------------------------------
Test.section('Tempo - real-time factors scale, grid factors do not')

EnableFixtureAutoCleanup()

Test.it('the readers see the notes at all three tempos', function()
    -- Guards the whole section: if the build or the readers are broken, every
    -- ratio below would be 0/0 and the failures would be misleading.
    for _, bpm in ipairs({ 60, 120, 240 }) do
        local sc = ScoreAtTempo(bpm, nil, 64, 0.25)
        Test.expect(sc.notes == 64,
            ('%d bpm: expected 64 notes, got %d'):format(bpm, sc.notes))
        Test.expect(sc.no_playing_time == false,
            ('%d bpm: animation span not found'):format(bpm))
    end
end)

Test.it('density and change rate double when the tempo doubles', function()
    local slow = ScoreAtTempo(60,  nil, 64, 0.25)
    local fast = ScoreAtTempo(120, nil, 64, 0.25)
    local dr = fast.density_avg / slow.density_avg
    local cr = fast.change_rate / slow.change_rate
    Test.expect(dr > 1.9 and dr < 2.1,
        ('density ratio should be ~2; got %.3f'):format(dr))
    Test.expect(cr > 1.9 and cr < 2.1,
        ('change_rate ratio should be ~2; got %.3f'):format(cr))
end)

Test.it('playing time halves when the tempo doubles', function()
    local slow = ScoreAtTempo(60,  nil, 64, 0.25)
    local fast = ScoreAtTempo(120, nil, 64, 0.25)
    local ratio = fast.playing_s / slow.playing_s
    Test.expect(ratio > 0.45 and ratio < 0.55,
        ('playing_s ratio should be ~0.5; got %.3f'):format(ratio))
end)

Test.it('peak density scales with tempo too', function()
    -- density_peak is windowed in SECONDS, so unlike the tightness percentiles it
    -- must follow tempo. This is the pair that pins the two families apart.
    local slow = ScoreAtTempo(60,  nil, 64, 0.25)
    local fast = ScoreAtTempo(120, nil, 64, 0.25)
    Test.expect(fast.density_peak > slow.density_peak * 1.5,
        ('peak should rise sharply; %.3f vs %.3f')
            :format(fast.density_peak, slow.density_peak))
end)

Test.it('the tightness percentiles are IDENTICAL at every tempo', function()
    -- A sixteenth is 0.25 QN at 60 bpm and at 240 bpm. If these ever move with
    -- tempo they have silently become a second density factor.
    local a = ScoreAtTempo(60,  nil, 64, 0.25)
    local b = ScoreAtTempo(120, nil, 64, 0.25)
    local c = ScoreAtTempo(240, nil, 64, 0.25)
    Test.expect(math.abs(a.tight_med - b.tight_med) < 1e-6
            and math.abs(b.tight_med - c.tight_med) < 1e-6,
        ('tight_med must not move; %.6f / %.6f / %.6f')
            :format(a.tight_med, b.tight_med, c.tight_med))
    Test.expect(math.abs(a.tight_p10 - c.tight_p10) < 1e-6,
        ('tight_p10 must not move; %.6f vs %.6f'):format(a.tight_p10, c.tight_p10))
    Test.expect(math.abs(b.tight_med - 0.25) < 1e-6,
        ('and should read the actual grid spacing; got %.6f'):format(b.tight_med))
end)

Test.it('counts are tempo-invariant', function()
    local a = ScoreAtTempo(60,  nil, 64, 0.25)
    local c = ScoreAtTempo(240, nil, 64, 0.25)
    Test.expect(a.notes == c.notes, 'notes')
    Test.expect(a.total_changes == c.total_changes,
        ('total_changes; %d vs %d'):format(a.total_changes, c.total_changes))
    Test.expect(math.abs(a.chord_size_mean - c.chord_size_mean) < 1e-9, 'chord_size_mean')
    Test.expect(math.abs(a.anchor_frac - c.anchor_frac) < 1e-9, 'anchor_frac')
end)

----------------------------------------------------------------------
Test.section('Tempo - a tempo CHANGE mid-chart is followed')

Test.it('a chart that speeds up halfway lands between the two fixed tempos', function()
    -- THE CASE NOTHING ELSE COVERS. bpm_at_first_note samples only the first note,
    -- so a tempo map applied wrongly after that point is invisible to the corpus
    -- run's own guard. 64 sixteenths, doubling tempo at the midpoint.
    local at_120 = ScoreAtTempo(120, nil, 64, 0.25)
    local at_240 = ScoreAtTempo(240, nil, 64, 0.25)
    local mixed  = ScoreAtTempo(120, { { 8.0, 240 } }, 64, 0.25)  -- qn 8 = halfway

    Test.expect(mixed.density_avg > at_120.density_avg
            and mixed.density_avg < at_240.density_avg,
        ('mixed density %.3f must sit between %.3f and %.3f')
            :format(mixed.density_avg, at_120.density_avg, at_240.density_avg))
    Test.expect(mixed.playing_s < at_120.playing_s and mixed.playing_s > at_240.playing_s,
        ('mixed playing_s %.3f must sit between %.3f and %.3f')
            :format(mixed.playing_s, at_240.playing_s, at_120.playing_s))
end)

Test.it('a tempo change does not disturb the grid-relative factors', function()
    -- The notes stay on a sixteenth grid throughout; only the clock changes. If
    -- tight_med moves here, qn is being computed against the wrong tempo segment,
    -- which is exactly the bug this section exists to catch.
    local fixed = ScoreAtTempo(120, nil, 64, 0.25)
    local mixed = ScoreAtTempo(120, { { 8.0, 240 } }, 64, 0.25)
    Test.expect(math.abs(mixed.tight_med - fixed.tight_med) < 1e-6,
        ('tight_med must stay on the grid; %.6f vs %.6f')
            :format(mixed.tight_med, fixed.tight_med))
    Test.expect(mixed.notes == fixed.notes and mixed.total_changes == fixed.total_changes,
        'and the counts must not change')
end)

Test.it('the tempo map is restored after each chart', function()
    -- Cheap guard on the tests themselves: a leaked tempo change would make every
    -- later assertion in the suite meaningless rather than failing loudly.
    ScoreAtTempo(240, { { 4.0, 90 } }, 32, 0.5)
    local bpm = select(1, r.TimeMap_GetDividedBpmAtTime(0))
    Test.expect(bpm and bpm > 0, 'a tempo is defined after cleanup; got ' .. tostring(bpm))
end)
