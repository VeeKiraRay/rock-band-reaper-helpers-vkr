-- Algorithm unit tests for GateAndSplit, ApplyMinOffset, SnapOnsets (lib/reaper_dsp.lua).
-- These functions take plain Lua tables and make no REAPER API calls.

local function make_ci(contour, win_samps, sr, time_offset)
    return { contour = contour, win_samps = win_samps, sr = sr,
             time_offset = time_offset or 0.0 }
end

----------------------------------------------------------------------
Test.section('ApplyMinOffset')

Test.it('non-overlapping notes: unchanged', function()
    local notes = { {s=0.0, e=0.5}, {s=1.0, e=1.5} }
    local out, capped, dropped = ApplyMinOffset(notes, 0.1)
    Test.expect(#out == 2,    '2 notes in → 2 notes out')
    Test.expect(capped == 0,  'nothing capped')
    Test.expect(dropped == 0, 'nothing dropped')
    Test.expect(math.abs(out[1].e - 0.5) < 1e-9, 'note 1 end unchanged at 0.5')
end)

Test.it('overlapping note: end capped to maintain min offset', function()
    -- note[1].e=1.05, note[2].s=1.0, min_off=0.1 → cap = 1.0-0.1 = 0.9
    local notes = { {s=0.0, e=1.05}, {s=1.0, e=2.0} }
    local out, capped = ApplyMinOffset(notes, 0.1)
    Test.expect(capped == 1, '1 note capped')
    Test.expect(math.abs(out[1].e - 0.9) < 1e-9, 'note 1 end capped to 0.9')
end)

Test.it('note crushed to zero length after cap: dropped', function()
    -- note[2].s=0.1, min_off=0.5 → cap = 0.1-0.5 = -0.4; note[1].e(1.5) → -0.4 < s(0) → dropped
    local notes = { {s=0.0, e=1.5}, {s=0.1, e=2.0} }
    local _, _, dropped = ApplyMinOffset(notes, 0.5)
    Test.expect(dropped == 1, '1 note dropped after cap reduces it below zero length')
end)

Test.it('last note end is never capped', function()
    -- note[1] overlaps note[2]; note[2] is last and must remain unchanged
    local notes = { {s=0.0, e=0.3}, {s=0.2, e=1.0} }
    local out = ApplyMinOffset(notes, 0.0)
    Test.expect(math.abs(out[#out].e - 1.0) < 1e-9, 'last note end unchanged at 1.0')
end)

----------------------------------------------------------------------
Test.section('GateAndSplit — no-split mode')

Test.it('two distinct loud sections → 2 notes, 2 phrases', function()
    -- win_s=1s; two blobs of 2 windows above threshold, separated by quiet
    local ci = make_ci({0, 0.8, 0.8, 0, 0, 0, 0.8, 0.8, 0}, 100, 100)
    local notes, phrases = GateAndSplit(ci, 0.5, 0, 1.5)
    Test.expect(#notes == 2,  '2 notes detected')
    Test.expect(phrases == 2, '2 phrases')
end)

Test.it('min-duration filter removes events shorter than threshold', function()
    -- each "note" is 1 window = 1s; min_note_s=2s → min_wins=2 → both filtered
    local ci = make_ci({0, 0.8, 0, 0, 0.8, 0}, 100, 100)
    local notes = GateAndSplit(ci, 0.5, 0, 2.0)
    Test.expect(#notes == 0, 'short notes filtered out by min_note_s')
end)

Test.it('note times are shifted by time_offset', function()
    local ci = make_ci({0, 0.8, 0.8, 0}, 100, 100, 10.0)
    local notes = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 1, '1 note')
    Test.expect(notes[1].s >= 10.0, 'start time includes time_offset')
end)

Test.it('empty contour → 0 notes, 0 phrases', function()
    local ci = make_ci({}, 100, 100)
    local notes, phrases = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 0 and phrases == 0, 'empty contour → nothing')
end)

Test.it('all-below-threshold contour → 0 notes', function()
    local ci = make_ci({0.1, 0.2, 0.1, 0.0, 0.1}, 100, 100)
    local notes = GateAndSplit(ci, 0.5, 0, 0.5)
    Test.expect(#notes == 0, 'all quiet → 0 notes')
end)

----------------------------------------------------------------------
Test.section('GateAndSplit — split mode')

Test.it('single phrase with internal valley → 2 sub-notes, split_extra >= 1', function()
    -- threshold=0.3 (gate). Valley=0.4 is above gate → whole contour is 1 phrase.
    -- peak=0.8, split_ratio=0.7 → cut=0.56; valley=0.4 < cut → 2 sub-notes.
    local ci = make_ci({0, 0.6, 0.8, 0.4, 0.8, 0.6, 0}, 100, 100)
    local notes, phrases, split_extra = GateAndSplit(ci, 0.3, 0.7, 1.0)
    Test.expect(phrases == 1,      '1 phrase before split')
    Test.expect(split_extra >= 1,  'split produced at least 1 extra note')
    Test.expect(#notes >= 2,       'at least 2 sub-notes')
end)

Test.it('flat phrase above cut level → 1 sub-note, split_extra=0', function()
    local ci = make_ci({0, 0.8, 0.8, 0.8, 0.8, 0}, 100, 100)
    local _, _, split_extra = GateAndSplit(ci, 0.5, 0.7, 1.0)
    Test.expect(split_extra == 0, 'no valley → no split')
end)

----------------------------------------------------------------------
Test.section('SnapOnsets')

Test.it('snaps start to nearest positive derivative, end to nearest negative', function()
    -- win_s=1s, t_off=0. Note start at 2.5s (si=3), end at 6.5s (ei=7), window_ms=3000 (half=3).
    -- Sharpest rise: i=4 (0.9-0.0=0.9) → snapped_s = (4-1)*1 = 3.0
    -- Sharpest fall: i=8 (0.0-0.9=-0.9) → snapped_e = (8-1)*1 = 7.0
    local ci = make_ci({0,0,0,0.9,0.9,0.9,0.9,0,0}, 100, 100)
    local out = SnapOnsets({{s=2.5, e=6.5}}, ci, 3000)
    Test.expect(#out == 1, '1 note in → 1 note out')
    Test.expect(math.abs(out[1].s - 3.0) < 1e-9, 'start snapped to t=3.0')
    Test.expect(math.abs(out[1].e - 7.0) < 1e-9, 'end snapped to t=7.0')
end)

Test.it('fallback to original when snapping would produce empty note', function()
    -- Flat contour: all derivatives ~0; best_si and best_ei may coincide → use original
    local ci = make_ci({0.9, 0.9, 0.9, 0.9, 0.9}, 100, 100)
    local note = {s=1.5, e=3.5}
    local out = SnapOnsets({note}, ci, 1000)
    Test.expect(out[1].e > out[1].s, 'output note must not be empty')
end)

Test.it('empty note list returns empty list', function()
    local ci = make_ci({0.5, 0.8, 0.3}, 100, 100)
    local out = SnapOnsets({}, ci, 500)
    Test.expect(#out == 0, 'empty input → empty output')
end)
