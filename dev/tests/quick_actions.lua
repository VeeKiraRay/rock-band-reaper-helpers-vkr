-- Tests for quick_actions/lib/vocal_note_snap_core.lua.
--
-- Builds MIDI items on a temp track and drives VocalNoteSnapInTake directly
-- (no MIDI editor needed), then asserts on the resulting note positions.

-- PPQ round-trip tolerance: one tick at 960 PPQ / 120 bpm is ~0.5 ms
local EPS = 0.002

-- Create a temp track with one 0-10 s MIDI item holding the given notes
-- ({ s, e, pitch [, sel] [, lyric] }); lyric adds a type-5 text event at the
-- note start. Returns (take, track_idx).
local function MakeTake(notes)
    local idx  = CreateEmptyFixtureTrack('QA SNAP TEST')
    local tr   = r.GetTrack(0, idx)
    local item = r.CreateNewMIDIItemInProj(tr, 0, 10, false)
    local take = r.GetActiveTake(item)
    for _, n in ipairs(notes) do
        local sp = r.MIDI_GetPPQPosFromProjTime(take, n.s)
        local ep = r.MIDI_GetPPQPosFromProjTime(take, n.e)
        r.MIDI_InsertNote(take, n.sel or false, false, sp, ep, 0, n.pitch, 96, false)
        if n.lyric then
            r.MIDI_InsertTextSysexEvt(take, false, false, sp, 5, n.lyric, false)
        end
    end
    return take, idx
end

-- Read all notes back as { s, e, pitch, vel, sel } in project time, sorted by s.
local function ReadNotes(take)
    local _, cnt = r.MIDI_CountEvts(take)
    local out = {}
    for i = 0, cnt - 1 do
        local _, sel, _, sp, ep, _, pitch, vel = r.MIDI_GetNote(take, i)
        out[#out + 1] = { s = r.MIDI_GetProjTimeFromPPQPos(take, sp),
                          e = r.MIDI_GetProjTimeFromPPQPos(take, ep),
                          pitch = pitch, vel = vel, sel = sel }
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

local function Near(a, b) return math.abs(a - b) < EPS end

-- Read all type-5 lyric events back as { t, msg } in project time, sorted by t.
local function ReadLyrics(take)
    local _, _, _, textcnt = r.MIDI_CountEvts(take)
    local out = {}
    for i = 0, textcnt - 1 do
        local _, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
        if typ == 5 then
            out[#out + 1] = { t = r.MIDI_GetProjTimeFromPPQPos(take, ppq), msg = msg }
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- Run one snap against a fresh take, always cleaning up the temp track.
-- Returns (result_verb, notes_after, lyrics_after).
local function Snap(notes, cursor, mode)
    local take, idx = MakeTake(notes)
    local ok, res = pcall(VocalNoteSnapInTake, take, cursor, mode)
    local after  = ok and ReadNotes(take) or nil
    local lyrics = ok and ReadLyrics(take) or nil
    CleanupFixture(idx)
    if not ok then error(res, 2) end
    return res, after, lyrics
end

----------------------------------------------------------------------
Test.section('Vocal note snap - auto mode')

Test.it('cursor inside note, near start: moves note, length preserved', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 2.2, 'auto')
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2.2) and Near(n[1].e, 3.2),
        ('note at %.4f-%.4f, expected 2.2-3.2'):format(n[1].s, n[1].e))
    Test.expect(n[1].pitch == 60, 'pitch changed')
    Test.expect(n[1].sel, 'snapped note not selected')
end)

Test.it('cursor inside note, near end: stretches end to cursor', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 2.8, 'auto')
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 2.8),
        ('note at %.4f-%.4f, expected 2-2.8'):format(n[1].s, n[1].e))
end)

Test.it('cursor before note within 1 s: moves note to cursor', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 1.5, 'auto')
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 1.5) and Near(n[1].e, 2.5),
        ('note at %.4f-%.4f, expected 1.5-2.5'):format(n[1].s, n[1].e))
end)

Test.it('cursor after note within 1 s: stretches end to cursor', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 3.5, 'auto')
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3.5),
        ('note at %.4f-%.4f, expected 2-3.5'):format(n[1].s, n[1].e))
end)

Test.it('no note within 1 s: does nothing', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 5, 'auto')
    Test.expect(res == nil, 'expected nil, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3), 'note was modified')
end)

Test.it('notes outside vocal range (36-84) are ignored', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 105 } }, 2.5, 'auto')
    Test.expect(res == nil, 'phrase marker was targeted')
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3), 'phrase marker was modified')
end)

Test.it('nearest of two notes wins; others get deselected', function()
    local res, n = Snap({ { s = 2,   e = 3, pitch = 60, sel = true },
                          { s = 3.4, e = 4, pitch = 62 } }, 3.3, 'auto')
    -- note 1 end is 0.3 away, note 2 start is 0.1 away -> note 2 moves
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(Near(n[2].s, 3.3) and Near(n[2].e, 3.9),
        ('note at %.4f-%.4f, expected 3.3-3.9'):format(n[2].s, n[2].e))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3), 'wrong note was modified')
    Test.expect(not n[1].sel and n[2].sel, 'selection not exclusive to target')
end)

Test.it('note on cursor beats a nearer-edged neighbour', function()
    -- cursor inside note 1 (dist 0) even though note 2 start is closer to it
    local res, n = Snap({ { s = 2,    e = 2.95, pitch = 60 },
                          { s = 2.96, e = 4,    pitch = 62 } }, 2.94, 'auto')
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(Near(n[1].e, 2.94), 'on-cursor note not targeted')
    Test.expect(Near(n[2].s, 2.96) and Near(n[2].e, 4), 'wrong note was modified')
end)

----------------------------------------------------------------------
Test.section('Vocal note snap - forced start / end modes')

Test.it('start mode: cursor past midpoint still moves (never stretches)', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 2.9, 'start')
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2.9) and Near(n[1].e, 3.9),
        ('note at %.4f-%.4f, expected 2.9-3.9'):format(n[1].s, n[1].e))
end)

Test.it('end mode: cursor before note start does nothing', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 1.5, 'end')
    Test.expect(res == nil, 'expected nil, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3), 'note was modified')
end)

Test.it('end mode: cursor near start inside note still stretches', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 2.2, 'end')
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 2.2),
        ('note at %.4f-%.4f, expected 2-2.2'):format(n[1].s, n[1].e))
end)

Test.it('end mode: skips a later note to stretch one starting before cursor', function()
    local res, n = Snap({ { s = 2,   e = 3, pitch = 60 },
                          { s = 3.4, e = 4, pitch = 62 } }, 3.3, 'end')
    -- note 2 is nearer but starts after the cursor -> note 1 stretches
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(Near(n[1].e, 3.3), 'earlier note not stretched to cursor')
    Test.expect(Near(n[2].s, 3.4) and Near(n[2].e, 4), 'wrong note was modified')
end)

Test.it('note already in target position: selects it, reports selected', function()
    local res, n = Snap({ { s = 2, e = 3, pitch = 60 } }, 2, 'start')
    Test.expect(res == 'selected', 'expected selected, got ' .. tostring(res))
    Test.expect(Near(n[1].s, 2) and Near(n[1].e, 3), 'note was modified')
    Test.expect(n[1].sel, 'note not selected')
end)

----------------------------------------------------------------------
Test.section('Vocal note snap - lyric follows note')

Test.it('move: lyric at note start moves with the note', function()
    local res, n, lyr = Snap({ { s = 2, e = 3, pitch = 60, lyric = 'word' } },
                             1.5, 'auto')
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(#lyr == 1 and lyr[1].msg == 'word', 'lyric lost or changed')
    Test.expect(Near(lyr[1].t, n[1].s) and Near(lyr[1].t, 1.5),
        ('lyric at %.4f, expected 1.5'):format(lyr[1].t))
end)

Test.it('stretch: lyric stays at the unchanged note start', function()
    local res, _, lyr = Snap({ { s = 2, e = 3, pitch = 60, lyric = 'word' } },
                             3.5, 'auto')
    Test.expect(res == 'stretched', 'expected stretched, got ' .. tostring(res))
    Test.expect(#lyr == 1 and lyr[1].msg == 'word', 'lyric lost or changed')
    Test.expect(Near(lyr[1].t, 2),
        ('lyric at %.4f, expected 2'):format(lyr[1].t))
end)

Test.it('move: only the target note\'s lyric moves', function()
    local res, _, lyr = Snap({ { s = 2,   e = 3, pitch = 60, lyric = 'one' },
                               { s = 3.4, e = 4, pitch = 62, lyric = 'two' } },
                             3.3, 'auto')
    -- note 2 moves to 3.3 (nearest edge); note 1's lyric must not move
    Test.expect(res == 'moved', 'expected moved, got ' .. tostring(res))
    Test.expect(#lyr == 2, 'expected 2 lyrics, got ' .. #lyr)
    Test.expect(Near(lyr[1].t, 2)   and lyr[1].msg == 'one', 'wrong lyric moved')
    Test.expect(Near(lyr[2].t, 3.3) and lyr[2].msg == 'two', 'target lyric did not move')
end)

----------------------------------------------------------------------
Test.section('Vocal note create')

-- Run one create against a fresh take, always cleaning up the temp track.
-- Returns (result_verb, notes_after, expected_grid_end) where the last is the
-- project time one grid unit after cursor, computed the same way as the core.
local function Create(notes, cursor)
    local take, idx = MakeTake(notes)
    local sppq     = r.MIDI_GetPPQPosFromProjTime(take, cursor)
    local grid_end = r.MIDI_GetProjTimeFromPPQPos(take,
        r.MIDI_GetPPQPosFromProjQN(take,
            r.MIDI_GetProjQNFromPPQPos(take, sppq) + r.MIDI_GetGrid(take)))
    local ok, res = pcall(VocalNoteCreateInTake, take, cursor)
    local after = ok and ReadNotes(take) or nil
    CleanupFixture(idx)
    if not ok then error(res, 2) end
    return res, after, grid_end
end

Test.it('creates grid-length note: pitch from nearest note, vel 96, selected', function()
    local res, n, grid_end = Create({ { s = 2, e = 3, pitch = 65 } }, 5)
    Test.expect(res == 'created', 'expected created, got ' .. tostring(res))
    Test.expect(#n == 2, 'expected 2 notes, got ' .. #n)
    Test.expect(Near(n[2].s, 5) and Near(n[2].e, grid_end),
        ('note at %.4f-%.4f, expected 5-%.4f'):format(n[2].s, n[2].e, grid_end))
    Test.expect(n[2].pitch == 65, 'pitch not copied from nearest note')
    Test.expect(n[2].vel == 96, 'velocity is ' .. n[2].vel .. ', expected 96')
    Test.expect(n[2].sel and not n[1].sel, 'created note not the sole selection')
end)

Test.it('empty take: creates at default pitch C3 (60)', function()
    local res, n = Create({}, 5)
    Test.expect(res == 'created', 'expected created, got ' .. tostring(res))
    Test.expect(#n == 1 and n[1].pitch == 60,
        'expected one note at pitch 60')
end)

Test.it('cursor inside an existing note: does nothing', function()
    local res, n = Create({ { s = 2, e = 3, pitch = 60 } }, 2.5)
    Test.expect(res == nil, 'expected nil, got ' .. tostring(res))
    Test.expect(#n == 1, 'a note was created inside another')
end)

Test.it('clamps end to the next note start', function()
    -- next note starts 0.05 s after cursor, inside one grid unit for any
    -- common grid setting (if the grid is finer than that, no clamp needed)
    local res, n, grid_end = Create({ { s = 5.05, e = 6, pitch = 62 } }, 5)
    local exp_e = math.min(grid_end, 5.05)
    Test.expect(res == 'created', 'expected created, got ' .. tostring(res))
    Test.expect(#n == 2, 'expected 2 notes, got ' .. #n)
    Test.expect(Near(n[1].s, 5) and Near(n[1].e, exp_e),
        ('note at %.4f-%.4f, expected 5-%.4f'):format(n[1].s, n[1].e, exp_e))
end)

Test.it('notes outside vocal range do not donate pitch', function()
    local res, n = Create({ { s = 2, e = 3, pitch = 105 } }, 5)
    Test.expect(res == 'created', 'expected created, got ' .. tostring(res))
    Test.expect(#n == 2, 'expected 2 notes, got ' .. #n)
    Test.expect(n[2].pitch == 60, 'pitch copied from out-of-range marker')
end)
