-- Tests for RemoveKicksMarkedBy2X (actions_drums_2x.lua).
--
-- Synthetic tracks rather than MIDI fixtures: the whole point of the action is
-- which exact position a note sits on, so the positions have to be known exactly.
--
-- EVERYTHING IS BUILT AND ASSERTED IN QUARTER NOTES, never seconds. That is the
-- property under test: a note's QN position is what MIDI stores, and a tempo
-- change alters seconds-per-QN, never the QN number. The first version of this
-- action bridged between the two tracks through project seconds and silently
-- stopped matching after the first tempo marker; the "tempo change" section below
-- is the regression guard for that.
--
-- The tempo-change tests rewrite the project tempo map and restore it afterwards
-- (SnapshotTempoMap / RestoreTempoMap from fixture_helpers.lua), so the suite
-- stays safe to run against a project you care about.

local SPAN_QN = 64    -- default MIDI item length, in quarter notes
local GEM_LEN = 10    -- note length in ticks; drum gems are short

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

-- Create a track with one MIDI item and the given notes.
-- notes: { { qn = quarter_notes, pitch = p }, ... }, positions relative to project 0.
-- Returns track_idx, track, item, take.
local function MakeTrack(name, start_qn, notes, span_qn)
    local idx  = CreateEmptyFixtureTrack(name)
    local tr   = r.GetTrack(0, idx)
    local item = r.CreateNewMIDIItemInProj(tr,
                     r.TimeMap2_QNToTime(0, start_qn),
                     r.TimeMap2_QNToTime(0, start_qn + (span_qn or SPAN_QN)), false)
    local take = r.GetActiveTake(item)
    for _, n in ipairs(notes or {}) do
        local sp = r.MIDI_GetPPQPosFromProjQN(take, n.qn)
        r.MIDI_InsertNote(take, false, false, sp, sp + GEM_LEN, 0, n.pitch, 100, false)
    end
    return idx, tr, item, take
end

-- Replace the tempo map with a single tempo, or with `changes` = { {qn, bpm}, ... }.
-- Same helper difficulty_bpm.lua uses: positions are given in quarter notes so a
-- test can say "jump to 240 at bar 9" without computing seconds.
local function SetTempo(bpm, changes)
    -- Overwrite marker 0 rather than deleting it: REAPER refuses to delete the last one.
    for i = r.CountTempoTimeSigMarkers(0) - 1, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, i)
    end
    if r.CountTempoTimeSigMarkers(0) == 0 then
        r.AddTempoTimeSigMarker(0, 0, bpm, 4, 4, false)
    else
        r.SetTempoTimeSigMarker(0, 0, 0, -1, -1, bpm, 4, 4, false)
    end
    for _, c in ipairs(changes or {}) do
        -- QN -> time under the map as it stands so far, which is why the changes
        -- must be applied in ascending order.
        r.AddTempoTimeSigMarker(0, r.TimeMap2_QNToTime(0, c[1]), c[2], 4, 4, false)
    end
    r.UpdateTimeline()
end

-- Run fn under a temporary tempo map, then put the project's own map back.
local function WithTempo(bpm, changes, fn)
    EnsureDefaultTempoMarker()   -- a fresh project has none, so there'd be nothing to restore
    local snap = SnapshotTempoMap()
    SetTempo(bpm, changes)
    local ok, err = pcall(fn)
    RestoreTempoMap(snap)
    if not ok then error(err, 2) end
end

----------------------------------------------------------------------
-- Reading back
----------------------------------------------------------------------

local function HasNoteAtQN(take, qn, pitch)
    local want = r.MIDI_GetPPQPosFromProjQN(take, qn)
    local _, n_notes = r.MIDI_CountEvts(take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(take, i)
        if ok and p == pitch and math.abs(sppq - want) < 0.5 then return true end
    end
    return false
end

local function CountNotes(take)
    local _, n_notes = r.MIDI_CountEvts(take)
    return n_notes
end

local function ResetStatus()
    S.status      = nil
    S.last_result = nil
end

----------------------------------------------------------------------
Test.section('RemoveKicksMarkedBy2X')
----------------------------------------------------------------------

-- These tests create tracks named "PART DRUMS" and "PART DRUMS_2X"; never run
-- them against a project that already has either one.
if FindTrackByName('PART DRUMS') or FindTrackByName('PART DRUMS_2X') then
    r.ShowConsoleMsg('  SKIP  RemoveKicksMarkedBy2X tests (project already has a drums track)\n')
else

Test.it('removes kicks on marked positions and leaves unmarked kicks alone', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 2, pitch = 95 }, { qn = 6, pitch = 95 },
    })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 2, pitch = 96 }, { qn = 4, pitch = 96 },
        { qn = 6, pitch = 96 }, { qn = 8, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local removed_ok = not HasNoteAtQN(tgt, 2, 96) and not HasNoteAtQN(tgt, 6, 96)
    local kept_ok    = HasNoteAtQN(tgt, 4, 96) and HasNoteAtQN(tgt, 8, 96)
    local count      = CountNotes(tgt)
    local status     = tostring(S.status)
    CleanupFixture(base)

    Test.expect(removed_ok, 'kicks at the two marked positions should be gone')
    Test.expect(kept_ok, 'kicks at unmarked positions should survive')
    Test.expect(count == 2, 'expected 2 notes left on PART DRUMS, got ' .. count)
    Test.expect(status:find('Removed 2 kicks'), 'status: ' .. status)
end)

Test.it('leaves non-kick notes on a marked position untouched', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 2, pitch = 95 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 2, pitch = 96 },   -- kick, removed
        { qn = 2, pitch = 97 },   -- snare at the same position, kept
        { qn = 2, pitch = 95 },   -- a 95 on PART DRUMS is not a kick either, kept
    })

    RemoveKicksMarkedBy2X()

    local gone  = not HasNoteAtQN(tgt, 2, 96)
    local snare = HasNoteAtQN(tgt, 2, 97)
    local mark  = HasNoteAtQN(tgt, 2, 95)
    CleanupFixture(base)

    Test.expect(gone, 'the kick on the marked position should be gone')
    Test.expect(snare, 'the snare at the same position should survive')
    Test.expect(mark, 'a pitch-95 note on PART DRUMS should survive - only 96 is removed')
end)

Test.it('matches across items placed at different project positions', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- The 2x item starts 5 QN later than the drums item, so the same musical
    -- position is a different raw PPQ on each take.
    MakeTrack('PART DRUMS_2X', 5, { { qn = 8, pitch = 95 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 8, pitch = 96 }, { qn = 12, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local gone  = not HasNoteAtQN(tgt, 8, 96)
    local kept  = HasNoteAtQN(tgt, 12, 96)
    local count = CountNotes(tgt)
    CleanupFixture(base)

    Test.expect(gone, 'the kick under the marker should be gone despite the item offset')
    Test.expect(kept, 'the unmarked kick should survive')
    Test.expect(count == 1, 'expected 1 note left, got ' .. count)
end)

Test.it('lists markers that had no kick to remove', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 2, pitch = 95 },    -- matches
        { qn = 20, pitch = 95 },   -- no kick anywhere near
    })
    MakeTrack('PART DRUMS', 0, { { qn = 2, pitch = 96 } })

    RemoveKicksMarkedBy2X()

    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(result:find('No kick matched at these markers:'),
        'expected the unmatched-marker heading, got: ' .. result)
    local _, n_lines = result:gsub('\n%s+%d+%.%d+%.%d+', '')
    Test.expect(n_lines == 1, 'expected 1 listed marker position, got ' .. n_lines)
end)

Test.it('a second run is a no-op and says so without listing every marker', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 2, pitch = 95 }, { qn = 4, pitch = 95 }, { qn = 6, pitch = 95 },
    })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 2, pitch = 96 }, { qn = 4, pitch = 96 }, { qn = 6, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()
    local after_first = CountNotes(tgt)
    ResetStatus()
    RemoveKicksMarkedBy2X()
    local after_second = CountNotes(tgt)
    local result       = tostring(S.last_result)
    local status       = tostring(S.status)
    CleanupFixture(base)

    Test.expect(after_first == 0, 'first run should remove all 3 kicks, ' .. after_first .. ' left')
    Test.expect(after_second == 0, 'second run must change nothing')
    Test.expect(result:find('No matching notes found'), 'result: ' .. result)
    Test.expect(status:find('Nothing to remove'), 'status: ' .. status)
    Test.expect(not result:find('No kick matched at these markers:'),
        'the no-op report must not enumerate the markers')
end)

Test.it('exits early when PART DRUMS_2X is missing', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, { { qn = 2, pitch = 96 } })

    RemoveKicksMarkedBy2X()

    local count  = CountNotes(tgt)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(count == 1, 'nothing should be removed, got ' .. count .. ' notes left')
    Test.expect(status:find('PART DRUMS_2X') and status:find('not found'), 'status: ' .. status)
end)

Test.it('exits early when PART DRUMS is missing', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 2, pitch = 95 } })

    RemoveKicksMarkedBy2X()

    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(status:find('PART DRUMS track not found'), 'status: ' .. status)
end)

Test.it('exits early when either drum track is muted', function()
    for _, muted in ipairs({ 'PART DRUMS_2X', 'PART DRUMS' }) do
        ResetStatus()
        local base = r.CountTracks(0)
        local _, src_tr = MakeTrack('PART DRUMS_2X', 0, { { qn = 2, pitch = 95 } })
        local _, tgt_tr, _, tgt = MakeTrack('PART DRUMS', 0, { { qn = 2, pitch = 96 } })
        r.SetMediaTrackInfo_Value(muted == 'PART DRUMS_2X' and src_tr or tgt_tr, 'B_MUTE', 1)

        RemoveKicksMarkedBy2X()

        local count  = CountNotes(tgt)
        local status = tostring(S.status)
        CleanupFixture(base)

        Test.expect(count == 1, muted .. ' muted: nothing should be removed, got ' .. count)
        Test.expect(status:find(muted .. ' is muted', 1, true), muted .. ' muted, status: ' .. status)
    end
end)

Test.it('reports when PART DRUMS_2X has notes but no pitch-95 markers', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 2, pitch = 96 }, { qn = 4, pitch = 97 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, { { qn = 2, pitch = 96 } })

    RemoveKicksMarkedBy2X()

    local count  = CountNotes(tgt)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(count == 1, 'nothing should be removed, got ' .. count .. ' notes left')
    Test.expect(status:find('no 2x kick markers'), 'status: ' .. status)
end)

Test.it('reports when PART DRUMS has no MIDI item', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 2, pitch = 95 } })
    CreateEmptyFixtureTrack('PART DRUMS')   -- track exists, no item

    RemoveKicksMarkedBy2X()

    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(status:find('PART DRUMS has no MIDI item'), 'status: ' .. status)
end)

----------------------------------------------------------------------
Test.section('RemoveKicksMarkedBy2X - across a tempo change')
----------------------------------------------------------------------

-- THE REGRESSION THIS SECTION EXISTS FOR. The first implementation matched by
-- converting one track's notes to project seconds and back to PPQ on the other,
-- which walks the tempo map twice in opposite directions. Before the first tempo
-- marker both takes share one linear mapping and the round trip is exact; after
-- one, grid-quantized notes land a few ms out - many ticks at a metal tempo - and
-- matching silently stopped finding anything past the change.

Test.it('matches on both sides of a 210 -> 240 BPM jump', function()
    ResetStatus()
    WithTempo(210, { { 32, 240 } }, function()
        local base = r.CountTracks(0)
        MakeTrack('PART DRUMS_2X', 0, {
            { qn = 8,  pitch = 95 }, { qn = 12, pitch = 95 },   -- before the jump
            { qn = 40, pitch = 95 }, { qn = 44, pitch = 95 },   -- after it
            { qn = 48, pitch = 95 },
        })
        local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
            { qn = 8,  pitch = 96 }, { qn = 10, pitch = 96 }, { qn = 12, pitch = 96 },
            { qn = 40, pitch = 96 }, { qn = 42, pitch = 96 }, { qn = 44, pitch = 96 },
            { qn = 48, pitch = 96 },
        })

        RemoveKicksMarkedBy2X()

        local before_ok = not HasNoteAtQN(tgt, 8, 96) and not HasNoteAtQN(tgt, 12, 96)
        local after_ok  = not HasNoteAtQN(tgt, 40, 96) and not HasNoteAtQN(tgt, 44, 96)
                      and not HasNoteAtQN(tgt, 48, 96)
        local kept_ok   = HasNoteAtQN(tgt, 10, 96) and HasNoteAtQN(tgt, 42, 96)
        local count     = CountNotes(tgt)
        local result    = tostring(S.last_result)
        CleanupFixture(base)

        Test.expect(before_ok, 'marked kicks BEFORE the tempo jump should be gone')
        Test.expect(after_ok,
            'marked kicks AFTER the tempo jump should be gone too - this is the bug:\n' .. result)
        Test.expect(kept_ok, 'unmarked kicks on both sides should survive')
        Test.expect(count == 2, 'expected 2 notes left, got ' .. count)
    end)
end)

Test.it('matches across a tempo change with the items at different positions', function()
    ResetStatus()
    WithTempo(210, { { 32, 240 } }, function()
        local base = r.CountTracks(0)
        MakeTrack('PART DRUMS_2X', 4, { { qn = 40, pitch = 95 } })
        local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
            { qn = 40, pitch = 96 }, { qn = 44, pitch = 96 },
        })

        RemoveKicksMarkedBy2X()

        local gone  = not HasNoteAtQN(tgt, 40, 96)
        local kept  = HasNoteAtQN(tgt, 44, 96)
        local result = tostring(S.last_result)
        CleanupFixture(base)

        Test.expect(gone, 'tempo change plus item offset must still match:\n' .. result)
        Test.expect(kept, 'the unmarked kick should survive')
    end)
end)

Test.it('the project tempo map is restored afterwards', function()
    -- Cheap guard on the tests themselves: a leaked tempo change would make every
    -- later suite's position math wrong rather than failing loudly here.
    EnsureDefaultTempoMarker()
    local before_n   = r.CountTempoTimeSigMarkers(0)
    local _, _, _, _, before_bpm = r.GetTempoTimeSigMarker(0, 0)
    WithTempo(210, { { 32, 240 } }, function() end)
    local after_n    = r.CountTempoTimeSigMarkers(0)
    local _, _, _, _, after_bpm  = r.GetTempoTimeSigMarker(0, 0)

    Test.expect(after_n == before_n,
        ('marker count %d -> %d'):format(before_n, after_n))
    Test.expect(math.abs(after_bpm - before_bpm) < 1e-6,
        ('root tempo %.3f -> %.3f'):format(before_bpm, after_bpm))
end)

----------------------------------------------------------------------
Test.section('RemoveKicksMarkedBy2X - nearest kick, with an ambiguity guard')
----------------------------------------------------------------------

Test.it('a blast beat of 1/32 kicks loses only the marked ones', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- Kicks on every 1/32 (0.125 QN) for 4 beats; markers on alternate ones.
    -- The neighbouring kick is only 0.125 QN away, so a matcher with a fixed
    -- millisecond buffer would be at risk of taking the wrong one.
    local marks, kicks = {}, {}
    for i = 0, 32 do
        local qn = i * 0.125
        kicks[#kicks + 1] = { qn = qn, pitch = 96 }
        if i % 2 == 0 then marks[#marks + 1] = { qn = qn, pitch = 95 } end
    end
    MakeTrack('PART DRUMS_2X', 0, marks)
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, kicks)

    RemoveKicksMarkedBy2X()

    local wrong = {}
    for i = 0, 32 do
        local qn   = i * 0.125
        local here = HasNoteAtQN(tgt, qn, 96)
        if (i % 2 == 0) == here then wrong[#wrong + 1] = ('%.3f'):format(qn) end
    end
    local count = CountNotes(tgt)
    CleanupFixture(base)

    Test.expect(#wrong == 0, 'wrong notes at qn ' .. table.concat(wrong, ', '))
    Test.expect(count == 16, 'expected the 16 unmarked kicks left, got ' .. count)
end)

Test.it('a marker midway between two kicks is rejected as ambiguous', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- Both kicks a 1/64 away: inside MAX_SNAP_QN, but equally close, so neither
    -- can be called the marker's kick.
    MakeTrack('PART DRUMS_2X', 0, { { qn = 4.0, pitch = 95 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 4.0 - 0.015625, pitch = 96 }, { qn = 4.0 + 0.015625, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local count  = CountNotes(tgt)
    local result = tostring(S.last_result)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(count == 2, 'neither kick should be removed, got ' .. count .. ' left')
    Test.expect(status:find('Nothing to remove'), 'status: ' .. status)
    Test.expect(result:find('No matching notes found'), 'result: ' .. result)
end)

Test.it('a marker with its nearest kick a beat away removes nothing', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 1.0, pitch = 95 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, { { qn = 2.0, pitch = 96 } })

    RemoveKicksMarkedBy2X()

    local count = CountNotes(tgt)
    CleanupFixture(base)

    Test.expect(count == 1, 'the distant kick must not be snapped to, got ' .. count .. ' left')
end)

Test.it('a kick nudged ~10 ticks off its marker still matches', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local nudge = 10 / 960   -- ~0.0104 QN, inside MAX_SNAP_QN, nothing else nearby
    MakeTrack('PART DRUMS_2X', 0, { { qn = 4.0, pitch = 95 } })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, {
        { qn = 4.0 + nudge, pitch = 96 }, { qn = 8.0, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local gone  = not HasNoteAtQN(tgt, 4.0 + nudge, 96)
    local kept  = HasNoteAtQN(tgt, 8.0, 96)
    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(gone, 'a hand-nudged kick should still match:\n' .. result)
    Test.expect(kept, 'the far kick should survive')
end)

Test.it('two markers never claim the same kick', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- Two markers a 1/32 apart but only one kick, sitting on the first of them.
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 4.0, pitch = 95 }, { qn = 4.03125, pitch = 95 },
    })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, { { qn = 4.0, pitch = 96 } })

    RemoveKicksMarkedBy2X()

    local count  = CountNotes(tgt)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(count == 0, 'the one kick should be removed exactly once, got ' .. count)
    Test.expect(status:find('Removed 1 kick'), 'status: ' .. status)
end)

----------------------------------------------------------------------
Test.section('RemoveKicksMarkedBy2X - consistency check against the 2x track')
----------------------------------------------------------------------

Test.it('reports agreement when the leftover kicks match PART DRUMS_2X', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- The authoring workflow: PART DRUMS_2X carries the 1x kicks as 96 and the
    -- double kicks as 95; PART DRUMS starts as a copy of every kick.
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 0, pitch = 96 }, { qn = 0.5, pitch = 95 }, { qn = 1, pitch = 96 },
    })
    MakeTrack('PART DRUMS', 0, {
        { qn = 0, pitch = 96 }, { qn = 0.5, pitch = 96 }, { qn = 1, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(result:find('consistent'), 'expected a consistency line, got:\n' .. result)
end)

Test.it('flags a discrepancy when the counts do not line up', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, {
        { qn = 0, pitch = 96 }, { qn = 0.5, pitch = 95 }, { qn = 1, pitch = 96 },
    })
    MakeTrack('PART DRUMS', 0, {
        { qn = 0, pitch = 96 }, { qn = 0.5, pitch = 96 }, { qn = 1, pitch = 96 },
        { qn = 2, pitch = 96 },   -- a kick PART DRUMS_2X does not know about
    })

    RemoveKicksMarkedBy2X()

    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(result:find('disagree'), 'expected a discrepancy line, got:\n' .. result)
end)

Test.it('says nothing about consistency when PART DRUMS_2X carries no 96s', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 0.5, pitch = 95 } })
    MakeTrack('PART DRUMS', 0, {
        { qn = 0, pitch = 96 }, { qn = 0.5, pitch = 96 },
    })

    RemoveKicksMarkedBy2X()

    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(not result:find('consistent') and not result:find('disagree'),
        'the check must be skipped, not guessed at:\n' .. result)
end)

end  -- project-already-has-a-drums-track guard

----------------------------------------------------------------------
Test.section('DoubleBassPlan - the rules, pure')
----------------------------------------------------------------------

-- DoubleBassPlan takes quarter-note positions and an is_downbeat predicate, so
-- these need no project at all. 4/4 assumed: a bar downbeat is every 4 QN.
local function Bar4(qn) return math.abs(qn % 4) < 1e-6 or math.abs(qn % 4 - 4) < 1e-6 end

-- 'o' = stays a kick, 'X' = becomes the second foot. Same notation the reference
-- chart was read in, so a case here can be compared with the song by eye.
local function PlanStr(qns, downbeat)
    local marks = DoubleBassPlan(qns, downbeat or Bar4)
    local out = {}
    for i = 1, #qns do out[i] = marks[i] and 'X' or 'o' end
    return table.concat(out)
end

-- Positions from a start, at a fixed spacing.
local function Grid(start_qn, step, n)
    local qns = {}
    for i = 0, n - 1 do qns[#qns + 1] = start_qn + i * step end
    return qns
end

Test.it('two back-to-back 1/16 kicks are a double-bass line', function()
    Test.expect(PlanStr(Grid(1.0, 0.25, 2)) == 'oX', PlanStr(Grid(1.0, 0.25, 2)))
end)

Test.it('1/8 runs of 2, 3 and 4 are left alone; 5 is a line', function()
    for n = 2, 4 do
        local got = PlanStr(Grid(1.0, 0.5, n))
        Test.expect(got == ('o'):rep(n), ('%d eighths: %s'):format(n, got))
    end
    -- Five 1/8s from qn 1.0 end at qn 3.0, so no downbeat is involved.
    Test.expect(PlanStr(Grid(1.0, 0.5, 5)) == 'oXoXo', PlanStr(Grid(1.0, 0.5, 5)))
end)

Test.it('kicks more than a 1/8 apart are not one line', function()
    Test.expect(PlanStr({ 0.0, 1.0, 2.0, 3.0 }) == 'oooo', PlanStr({ 0.0, 1.0, 2.0, 3.0 }))
end)

Test.it('the alternation is phased so a bar downbeat is never taken', function()
    -- The reference chart's run of eight 1/16s starting at m27 beat 3.25 and
    -- landing on the next bar line. Marking from the 2nd would take that
    -- downbeat, so it starts on the first kick instead.
    local qns = Grid(2.25, 0.25, 8)          -- ends exactly on qn 4.0
    Test.expect(qns[#qns] == 4.0, 'fixture should end on the bar line')
    Test.expect(PlanStr(qns) == 'XoXoXoXo', PlanStr(qns))
end)

Test.it('an odd-length line ending on a downbeat still starts on the 2nd', function()
    local qns = Grid(3.0, 0.25, 5)           -- 3.0 .. 4.0, odd length
    Test.expect(PlanStr(qns) == 'oXoXo', PlanStr(qns))
end)

Test.it('a 1/8 pickup across the bar line into a 1/16 run is not part of it', function()
    -- The reference chart at m50 beat 4.5: one 1/8 then three 1/16s, and the
    -- 1/16 run starts on the bar line. Its pickup stays a plain kick.
    local qns = { 3.5, 4.0, 4.25, 4.5, 4.75 }
    Test.expect(PlanStr(qns) == 'ooXoX', PlanStr(qns))
end)

Test.it('a 1/8 tail past the closing bar line is not part of the line either', function()
    -- The reference chart's long runs end on a bar downbeat with one more 1/8
    -- after it; that last kick stays a plain kick.
    local qns = { 3.0, 3.25, 3.5, 3.75, 4.0, 4.5 }
    Test.expect(PlanStr(qns) == 'oXoXoo', PlanStr(qns))
end)

Test.it('a lone kick, and an empty chart, plan to nothing', function()
    Test.expect(PlanStr({ 1.0 }) == 'o', 'single kick')
    Test.expect(#DoubleBassPlan({}, Bar4) == 0, 'empty input')
end)

----------------------------------------------------------------------
Test.section('MarkDoubleBassKicks - against the project')
----------------------------------------------------------------------

if FindTrackByName('PART DRUMS_2X') then
    r.ShowConsoleMsg('  SKIP  MarkDoubleBassKicks tests (project already has PART DRUMS_2X)\n')
else

-- Read the track back as the same o/X string the pure tests use.
local function TrackPattern(take, qns)
    local out = {}
    for i, qn in ipairs(qns) do
        out[i] = HasNoteAtQN(take, qn, 95) and 'X'
              or (HasNoteAtQN(take, qn, 96) and 'o' or '?')
    end
    return table.concat(out)
end

local function KicksAt(qns)
    local notes = {}
    for _, qn in ipairs(qns) do notes[#notes + 1] = { qn = qn, pitch = 96 } end
    return notes
end

Test.it('moves every second foot of a 1/16 line from 96 to 95', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.25, 4.5, 4.75 }
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, KicksAt(qns))

    MarkDoubleBassKicks()

    local pat    = TrackPattern(take, qns)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(pat == 'oXoX', 'pattern: ' .. pat)
    Test.expect(status:find('Marked 2 double kicks'), 'status: ' .. status)
end)

Test.it('leaves a four-kick 1/8 run alone and reports nothing to mark', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.5, 5.0, 5.5 }
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, KicksAt(qns))

    MarkDoubleBassKicks()

    local pat    = TrackPattern(take, qns)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(pat == 'oooo', 'pattern: ' .. pat)
    Test.expect(status:find('Nothing to mark'), 'status: ' .. status)
end)

Test.it('does not touch non-kick drum notes', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.25, 4.5, 4.75 }
    local notes = KicksAt(qns)
    notes[#notes + 1] = { qn = 4.25, pitch = 97 }   -- snare on a marked position
    notes[#notes + 1] = { qn = 4.5,  pitch = 99 }
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, notes)

    MarkDoubleBassKicks()

    local snare = HasNoteAtQN(take, 4.25, 97)
    local blue  = HasNoteAtQN(take, 4.5, 99)
    CleanupFixture(base)

    Test.expect(snare, 'the snare must survive untouched')
    Test.expect(blue, 'the blue tom must survive untouched')
end)

Test.it('re-running changes nothing and says so', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.25, 4.5, 4.75 }
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, KicksAt(qns))

    MarkDoubleBassKicks()
    local first = TrackPattern(take, qns)
    ResetStatus()
    MarkDoubleBassKicks()
    local second = TrackPattern(take, qns)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(first == 'oXoX' and second == 'oXoX', first .. ' then ' .. second)
    Test.expect(status:find('already marked'), 'status: ' .. status)
end)

Test.it('an existing 95 the rules would not place is reported, not reverted', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- A lone pair of quarter-note kicks: no line at all, but one is already a 95.
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, {
        { qn = 4.0, pitch = 96 }, { qn = 5.0, pitch = 95 },
    })

    MarkDoubleBassKicks()

    local still95 = HasNoteAtQN(take, 5.0, 95)
    local result  = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(still95, 'a hand-placed 95 must not be reverted')
    Test.expect(result:find('would not'), 'expected a review line, got:\n' .. result)
end)

Test.it('counts an existing 95 as part of the line when alternating', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- Second kick already marked; the rules agree, so the run is left as it is.
    local qns = { 4.0, 4.25, 4.5, 4.75 }
    local _, _, _, take = MakeTrack('PART DRUMS_2X', 0, {
        { qn = 4.0, pitch = 96 }, { qn = 4.25, pitch = 95 },
        { qn = 4.5, pitch = 96 }, { qn = 4.75, pitch = 96 },
    })

    MarkDoubleBassKicks()

    local pat    = TrackPattern(take, qns)
    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(pat == 'oXoX', 'pattern: ' .. pat)
    Test.expect(not result:find('would not'), 'nothing should need review:\n' .. result)
end)

Test.it('exits early when PART DRUMS_2X is missing', function()
    ResetStatus()
    MarkDoubleBassKicks()
    local status = tostring(S.status)
    Test.expect(status:find('PART DRUMS_2X') and status:find('not found'), 'status: ' .. status)
end)

Test.it('exits early when PART DRUMS_2X is muted', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local _, tr, _, take = MakeTrack('PART DRUMS_2X', 0,
        KicksAt({ 4.0, 4.25, 4.5, 4.75 }))
    r.SetMediaTrackInfo_Value(tr, 'B_MUTE', 1)

    MarkDoubleBassKicks()

    local untouched = HasNoteAtQN(take, 4.25, 96)
    local status    = tostring(S.status)
    CleanupFixture(base)

    Test.expect(untouched, 'a muted track must not be edited')
    Test.expect(status:find('is muted'), 'status: ' .. status)
end)

Test.it('reports when there are fewer than two kicks', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, { { qn = 4.0, pitch = 96 } })

    MarkDoubleBassKicks()

    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(status:find('fewer than two kicks'), 'status: ' .. status)
end)

Test.it('the two buttons compose: mark, then remove from PART DRUMS', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.25, 4.5, 4.75 }
    -- The authoring workflow: every kick on both tracks, then mark, then remove.
    local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, KicksAt(qns))
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, KicksAt(qns))

    MarkDoubleBassKicks()
    ResetStatus()
    RemoveKicksMarkedBy2X()

    local x2_pat = TrackPattern(x2, qns)
    local left   = CountNotes(tgt)
    local kept   = HasNoteAtQN(tgt, 4.0, 96) and HasNoteAtQN(tgt, 4.5, 96)
    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(x2_pat == 'oXoX', 'PART DRUMS_2X: ' .. x2_pat)
    Test.expect(left == 2, 'PART DRUMS should keep the 2 first-foot kicks, got ' .. left)
    Test.expect(kept, 'the surviving kicks should be the unmarked ones')
    Test.expect(result:find('consistent'), 'the counts should agree:\n' .. result)
end)

end  -- project-already-has-PART-DRUMS_2X guard
