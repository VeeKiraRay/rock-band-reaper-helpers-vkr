-- Tests for Remove2XKicks and the double-bass rules (actions_drums_2x.lua).
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
Test.section('Remove2XKicks')
----------------------------------------------------------------------

-- PART DRUMS_2X is the complete chart: every kick at 96, doubles included.
-- PART DRUMS is the same chart with the second foot taken out. Remove2XKicks
-- works out which those are in memory - nothing records the plan on the tracks.

-- These tests create tracks named "PART DRUMS" and "PART DRUMS_2X"; never run
-- them against a project that already has either one.
if FindTrackByName('PART DRUMS') or FindTrackByName('PART DRUMS_2X') then
    r.ShowConsoleMsg('  SKIP  Remove2XKicks tests (project already has a drums track)\n')
else

-- Note tables for a list of quarter-note positions, all at the kick pitch.
local function Kicks(qns, pitch)
    local out = {}
    for _, qn in ipairs(qns) do out[#out + 1] = { qn = qn, pitch = pitch or 96 } end
    return out
end

local function CountPitch(take, pitch)
    local _, n_notes = r.MIDI_CountEvts(take)
    local n = 0
    for i = 0, n_notes - 1 do
        local ok, _, _, _, _, _, p = r.MIDI_GetNote(take, i)
        if ok and p == pitch then n = n + 1 end
    end
    return n
end

-- A bar of 1/16 kicks: 4.0 4.25 4.5 4.75. The second foot is 4.25 and 4.75.
local BAR16 = { 4.0, 4.25, 4.5, 4.75 }

Test.it('removes the second foot of a 1/16 line from PART DRUMS', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(BAR16))

    Remove2XKicks()

    local kept   = HasNoteAtQN(tgt, 4.0, 96) and HasNoteAtQN(tgt, 4.5, 96)
    local gone   = not HasNoteAtQN(tgt, 4.25, 96) and not HasNoteAtQN(tgt, 4.75, 96)
    local left   = CountNotes(tgt)
    local x2_n   = CountNotes(x2)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(gone, 'the two second-foot kicks should be gone from PART DRUMS')
    Test.expect(kept, 'the two first-foot kicks should survive')
    Test.expect(left == 2, 'expected 2 kicks left on PART DRUMS, got ' .. left)
    Test.expect(x2_n == 4, 'PART DRUMS_2X must keep all 4 kicks, got ' .. x2_n)
    Test.expect(status:find('Removed 2 kicks'), 'status: ' .. status)
end)

Test.it('never thins PART DRUMS_2X or touches its other drum notes', function()
    ResetStatus()
    local base  = r.CountTracks(0)
    local notes = Kicks(BAR16)
    notes[#notes + 1] = { qn = 4.25, pitch = 97 }   -- snare on a second-foot position
    notes[#notes + 1] = { qn = 4.5,  pitch = 99 }
    local _, _, _, x2 = MakeTrack('PART DRUMS_2X', 0, notes)
    MakeTrack('PART DRUMS', 0, Kicks(BAR16))

    Remove2XKicks()

    local kicks = CountPitch(x2, 96)
    local snare = HasNoteAtQN(x2, 4.25, 97)
    local tom   = HasNoteAtQN(x2, 4.5, 99)
    CleanupFixture(base)

    Test.expect(kicks == 4, 'PART DRUMS_2X must keep every kick, got ' .. kicks)
    Test.expect(snare, 'the snare on PART DRUMS_2X must survive')
    Test.expect(tom, 'the tom on PART DRUMS_2X must survive')
end)

Test.it('counts a leftover pitch 95 as a kick and puts it back to 96', function()
    ResetStatus()
    local base = r.CountTracks(0)
    -- A chart left in the old marked state: 4.25 was written as 95 by the
    -- since-hidden Mark button. Rock Band 3 would never play it.
    local _, _, _, x2 = MakeTrack('PART DRUMS_2X', 0, {
        { qn = 4.0, pitch = 96 }, { qn = 4.25, pitch = 95 },
        { qn = 4.5, pitch = 96 }, { qn = 4.75, pitch = 96 },
    })
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(BAR16))

    Remove2XKicks()

    local repaired = CountPitch(x2, 96) == 4 and CountPitch(x2, 95) == 0
    local gone     = not HasNoteAtQN(tgt, 4.25, 96) and not HasNoteAtQN(tgt, 4.75, 96)
    local kept     = HasNoteAtQN(tgt, 4.0, 96) and HasNoteAtQN(tgt, 4.5, 96)
    local result   = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(repaired, 'the 95 must come back as a 96 so the 2x chart plays it')
    Test.expect(gone and kept, 'the removal must match an all-96 track')
    Test.expect(result:find('95'), 'the repair should be reported:\n' .. result)
end)

Test.it('a second run removes nothing and says so', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(BAR16))

    Remove2XKicks()
    local after_first = CountNotes(tgt)
    ResetStatus()
    Remove2XKicks()
    local after_second = CountNotes(tgt)
    local x2_n         = CountNotes(x2)
    local status       = tostring(S.status)
    local result       = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(after_first == 2, 'first run should leave 2 kicks, got ' .. after_first)
    Test.expect(after_second == 2, 'second run must change nothing')
    Test.expect(x2_n == 4, 'PART DRUMS_2X must still hold every kick')
    Test.expect(status:find('Nothing to remove'), 'status: ' .. status)
    Test.expect(result:find('already absent'), 'result: ' .. result)
end)

Test.it('a line too slow to need two feet leaves both tracks alone', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local slow = { 4.0, 4.5, 5.0, 5.5 }   -- four 1/8s: one foot can play it
    local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, Kicks(slow))
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(slow))

    Remove2XKicks()

    local left   = CountNotes(tgt)
    local x2_n   = CountNotes(x2)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(left == 4, 'nothing should be removed, got ' .. left .. ' left')
    Test.expect(x2_n == 4, 'PART DRUMS_2X must be untouched')
    Test.expect(status:find('Nothing to remove'), 'status: ' .. status)
end)

Test.it('flags when PART DRUMS holds kicks the 2x chart does not', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
    local extra = { 4.0, 4.25, 4.5, 4.75, 8.0 }   -- 8.0 is on PART DRUMS only
    MakeTrack('PART DRUMS', 0, Kicks(extra))

    Remove2XKicks()

    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(result:find('different kicks'),
        'expected a consistency warning, got:\n' .. result)
end)

Test.it('a second-foot kick already absent from PART DRUMS is reported, not an error', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
    -- 4.75 was already taken out by hand; 4.25 is still there.
    MakeTrack('PART DRUMS', 0, Kicks({ 4.0, 4.25, 4.5 }))

    Remove2XKicks()

    local status = tostring(S.status)
    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(status:find('Removed 1 kick'), 'status: ' .. status)
    Test.expect(result:find('already absent'), 'result: ' .. result)
end)

Test.it('exits early when PART DRUMS_2X is missing', function()
    ResetStatus()
    local base = r.CountTracks(0)
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(BAR16))

    Remove2XKicks()

    local left   = CountNotes(tgt)
    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(left == 4, 'nothing should be removed, got ' .. left)
    Test.expect(status:find('PART DRUMS_2X') and status:find('not found'), 'status: ' .. status)
end)

Test.it('exits early when PART DRUMS is missing', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))

    Remove2XKicks()

    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(status:find('PART DRUMS track not found'), 'status: ' .. status)
end)

Test.it('exits early when either drum track is muted', function()
    for _, muted in ipairs({ 'PART DRUMS_2X', 'PART DRUMS' }) do
        ResetStatus()
        local base = r.CountTracks(0)
        local _, src_tr           = MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
        local _, tgt_tr, _, tgt   = MakeTrack('PART DRUMS', 0, Kicks(BAR16))
        r.SetMediaTrackInfo_Value(muted == 'PART DRUMS_2X' and src_tr or tgt_tr, 'B_MUTE', 1)

        Remove2XKicks()

        local left   = CountNotes(tgt)
        local status = tostring(S.status)
        CleanupFixture(base)

        Test.expect(left == 4, muted .. ' muted: nothing should be removed, got ' .. left)
        Test.expect(status:find(muted .. ' is muted', 1, true), muted .. ', status: ' .. status)
    end
end)

Test.it('reports when either track has no MIDI item', function()
    ResetStatus()
    local base = r.CountTracks(0)
    CreateEmptyFixtureTrack('PART DRUMS_2X')
    MakeTrack('PART DRUMS', 0, Kicks(BAR16))
    Remove2XKicks()
    local a = tostring(S.status)
    CleanupFixture(base)

    ResetStatus()
    base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, Kicks(BAR16))
    CreateEmptyFixtureTrack('PART DRUMS')
    Remove2XKicks()
    local b = tostring(S.status)
    CleanupFixture(base)

    Test.expect(a:find('PART DRUMS_2X has no MIDI item'), 'no 2x item, status: ' .. a)
    Test.expect(b:find('PART DRUMS has no MIDI item'), 'no drums item, status: ' .. b)
end)

Test.it('reports when PART DRUMS_2X has fewer than two kicks', function()
    ResetStatus()
    local base = r.CountTracks(0)
    MakeTrack('PART DRUMS_2X', 0, Kicks({ 4.0 }))
    MakeTrack('PART DRUMS', 0, Kicks({ 4.0 }))

    Remove2XKicks()

    local status = tostring(S.status)
    CleanupFixture(base)

    Test.expect(status:find('fewer than two kicks'), 'status: ' .. status)
end)

----------------------------------------------------------------------
Test.section('Remove2XKicks - across a tempo change')
----------------------------------------------------------------------

-- The matching between the two tracks is in quarter notes, so a BPM jump partway
-- through must not stop it finding kicks. An earlier version bridged through
-- project seconds and silently stopped matching after the first tempo marker.

Test.it('removes on both sides of a 210 -> 240 BPM jump', function()
    ResetStatus()
    WithTempo(210, { { 32, 240 } }, function()
        local base = r.CountTracks(0)
        local line = { 8.0, 8.25, 8.5, 8.75,      -- before the jump
                       40.0, 40.25, 40.5, 40.75 } -- after it
        local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, Kicks(line))
        local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(line))

        Remove2XKicks()

        local before_ok = not HasNoteAtQN(tgt, 8.25, 96) and not HasNoteAtQN(tgt, 8.75, 96)
        local after_ok  = not HasNoteAtQN(tgt, 40.25, 96) and not HasNoteAtQN(tgt, 40.75, 96)
        local kept_ok   = HasNoteAtQN(tgt, 8.0, 96) and HasNoteAtQN(tgt, 40.0, 96)
        local left      = CountNotes(tgt)
        local x2_n      = CountNotes(x2)
        local result    = tostring(S.last_result)
        CleanupFixture(base)

        Test.expect(before_ok, 'second-foot kicks BEFORE the jump should be gone')
        Test.expect(after_ok,
            'second-foot kicks AFTER the jump should be gone too:\n' .. result)
        Test.expect(kept_ok, 'first-foot kicks on both sides should survive')
        Test.expect(left == 4, 'expected 4 kicks left, got ' .. left)
        Test.expect(x2_n == 8, 'PART DRUMS_2X must keep all 8 kicks')
    end)
end)

Test.it('removes across a tempo change with the items at different positions', function()
    ResetStatus()
    WithTempo(210, { { 32, 240 } }, function()
        local base = r.CountTracks(0)
        local line = { 40.0, 40.25, 40.5, 40.75 }
        MakeTrack('PART DRUMS_2X', 4, Kicks(line))
        local _, _, _, tgt = MakeTrack('PART DRUMS', 0, Kicks(line))

        Remove2XKicks()

        local gone   = not HasNoteAtQN(tgt, 40.25, 96) and not HasNoteAtQN(tgt, 40.75, 96)
        local kept   = HasNoteAtQN(tgt, 40.0, 96) and HasNoteAtQN(tgt, 40.5, 96)
        local result = tostring(S.last_result)
        CleanupFixture(base)

        Test.expect(gone, 'tempo change plus item offset must still match:\n' .. result)
        Test.expect(kept, 'the first-foot kicks should survive')
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

Test.it('a lone 1/8 leaning on a 1/16 burst is not part of it', function()
    -- The reference chart at m62 beat 3: one kick on the half beat, then a 1/16
    -- pair. The lone 1/8 is a separate hit, so the pair alternates on its own and
    -- the half beat - the stronger position - stays a plain kick.
    local qns = { 2.0, 2.5, 2.75 }
    Test.expect(PlanStr(qns) == 'ooX', PlanStr(qns))
end)

Test.it('but a line that merely starts with a stretch of 1/8s keeps them', function()
    -- The trim must not walk the whole 1/8 lead-in off a long mixed line: here
    -- only the last two kicks are 1/16s, so no single kick is "the lone one at
    -- the wider spacing" and every eighth stays in the alternation.
    local qns = { 1.0, 1.5, 2.0, 2.5, 3.0, 3.25 }
    Test.expect(PlanStr(qns) == 'oXoXoX', PlanStr(qns))
end)

Test.it('a lone 1/8 trailing off the end of a 1/16 burst is dropped too', function()
    local qns = { 2.0, 2.25, 2.5, 3.0 }
    Test.expect(PlanStr(qns) == 'oXoo', PlanStr(qns))
end)

-- A bar of 1/16 kicks from one downbeat to the next, with the kick on `hole_qn`
-- missing. This is the m14 shape: 16 kicks, so the line is even-length AND
-- bounded by two downbeats, which no alternation phase can satisfy.
local function BarWithHole(hole_qn)
    local qns = {}
    for i = 0, 16 do
        local qn = 4.0 + i * 0.25
        if math.abs(qn - hole_qn) > 1e-9 then qns[#qns + 1] = qn end
    end
    return qns
end

Test.it('a bar-long 1/16 line with a hole keeps both downbeats primary', function()
    -- The reference chart at m14: no kick on beat 3. Counting played notes would
    -- flip the feet after the hole and leave the closing downbeat to the second
    -- foot; reading the line as a continuous grid does not.
    local qns = BarWithHole(6.0)
    Test.expect(#qns == 16, 'fixture should be 16 kicks, got ' .. #qns)
    Test.expect(PlanStr(qns) == 'oXoXoXoXXoXoXoXo', PlanStr(qns))
    -- Stated as the properties that matter, so a future rule change that still
    -- passes the literal string above cannot quietly lose them.
    local marks = DoubleBassPlan(qns, Bar4)
    Test.expect(not marks[1], 'the opening downbeat must stay a primary kick')
    Test.expect(not marks[#qns], 'the closing downbeat must stay a primary kick')
end)

Test.it('the same bar with no hole is untouched by the grid tie-break', function()
    -- 17 kicks: odd, so alternating from the 2nd already avoids both downbeats
    -- and the grid branch never runs. Guards the property that makes it safe.
    local qns = {}
    for i = 0, 16 do qns[#qns + 1] = 4.0 + i * 0.25 end
    Test.expect(PlanStr(qns) == 'oXoXoXoXoXoXoXoXo', PlanStr(qns))
end)

Test.it('a hole does not trigger the tie-break when a phase is already clean', function()
    -- Same kind of gap, but the line neither starts nor ends on a downbeat, so
    -- the ordinary phase rule applies and the answer counts played notes.
    local qns = { 4.25, 4.5, 4.75, 5.25, 5.5, 5.75 }
    Test.expect(PlanStr(qns) == 'oXoXoX', PlanStr(qns))
end)

Test.it('an off-grid kick falls back to plain alternation, not to nonsense', function()
    -- Same bar, but one kick is nudged off the 1/16 grid, so slot numbers cannot
    -- be trusted. The tie-break must decline rather than round to a wrong slot.
    local qns = BarWithHole(6.0)
    for i, qn in ipairs(qns) do
        if math.abs(qn - 6.25) < 1e-9 then qns[i] = 6.20 end
    end
    Test.expect(PlanStr(qns) == 'oXoXoXoXoXoXoXoX', PlanStr(qns))
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

Test.it('Remove2XKicks repairs a chart the old Mark button produced', function()
    -- The migration path. MarkDoubleBassKicks leaves PART DRUMS_2X carrying 95s
    -- that Rock Band 3 discards, so its 2x chart plays FEWER kicks than the 1x
    -- one. Remove2XKicks must undo that: every kick back to 96 on the 2x track,
    -- and the second foot taken out of PART DRUMS instead.
    ResetStatus()
    local base = r.CountTracks(0)
    local qns  = { 4.0, 4.25, 4.5, 4.75 }
    local _, _, _, x2  = MakeTrack('PART DRUMS_2X', 0, KicksAt(qns))
    local _, _, _, tgt = MakeTrack('PART DRUMS', 0, KicksAt(qns))

    MarkDoubleBassKicks()
    local marked = TrackPattern(x2, qns)
    ResetStatus()
    Remove2XKicks()

    local x2_pat = TrackPattern(x2, qns)
    local left   = CountNotes(tgt)
    local kept   = HasNoteAtQN(tgt, 4.0, 96) and HasNoteAtQN(tgt, 4.5, 96)
    local result = tostring(S.last_result)
    CleanupFixture(base)

    Test.expect(marked == 'oXoX', 'the old button should have written 95s: ' .. marked)
    Test.expect(x2_pat == 'oooo', 'PART DRUMS_2X must end up all 96: ' .. x2_pat)
    Test.expect(left == 2, 'PART DRUMS should keep the 2 first-foot kicks, got ' .. left)
    Test.expect(kept, 'the surviving kicks should be the first-foot ones')
    Test.expect(result:find('consistent'), 'the counts should agree:\n' .. result)
end)

end  -- project-already-has-PART-DRUMS_2X guard
