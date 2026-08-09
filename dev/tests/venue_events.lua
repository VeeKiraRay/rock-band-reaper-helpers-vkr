-- Tests for section_events.lua + actions_venue_events.lua (Venue > Events
-- sub-tab): vocabulary validation against the full RB3 events list, the pure
-- NextSectionEvent / ValidatePlainInsert validation logic, and EVENTS-track
-- integration (inserts, quick actions).
--
-- The runner sets _EVENTS_LIST_PATH (path to the ground-truth txt); the
-- vocabulary test is skipped with a note when the file is not present
-- (e.g. deployed installs without _external_docs/).

-- Build a scan structure (same shape as ScanEventsTextEvents) from an array
-- of { msg=, t= } pairs. Pure - usable without a take.
local PPQ_PER_SEC = 960
local function P(t) return math.floor(t * PPQ_PER_SEC + 0.5) end
local function MakeScan(list)
    local events = {}
    for _, e in ipairs(list) do
        events[#events + 1] = {
            msg = e.msg, t = e.t, ppq = P(e.t), label = ('t=%.1f'):format(e.t),
        }
    end
    table.sort(events, function(a, b) return a.ppq < b.ppq end)
    local by_msg = {}
    for _, e in ipairs(events) do
        if not by_msg[e.msg] then by_msg[e.msg] = e end
    end
    return { events = events, by_msg = by_msg }
end

----------------------------------------------------------------------
Test.section('Event vocabulary (generated strings vs full list)')
----------------------------------------------------------------------

local function LoadEventList()
    local f = io.open(_EVENTS_LIST_PATH, 'r')
    if not f then return nil end
    local set = {}
    for line in f:lines() do
        line = line:gsub('^\239\187\191', ''):gsub('%s+$', '')  -- BOM, CR
        if line ~= '' then set[line] = true end
    end
    f:close()
    return set
end

local _list = LoadEventList()
if not _list then
    r.ShowConsoleMsg('  SKIP  vocabulary test (events list not found at\n         '
                     .. tostring(_EVENTS_LIST_PATH) .. ')\n')
else
    Test.it('every generatable event string exists in the full list', function()
        local missing = {}
        local function check(ev)
            if not _list[ev] then missing[#missing + 1] = ev end
        end
        -- Drive the real generator, respecting its own sequence rules:
        -- num 0 alone (exclusivity forbids mixing with numbered), then the
        -- numbered families 1..max in order, each event placed after all
        -- previous ones - once with letters off (plain forms) and once with
        -- letters on (lettered forms).
        local function ladder(base, caps, is_generic)
            for _, use_letters in ipairs({ false, true }) do
                local passes = { { 0 }, {} }
                local max_num = is_generic and 9 or (#caps - 1)
                for num = 1, max_num do passes[2][#passes[2] + 1] = num end
                for _, nums in ipairs(passes) do
                    local entries, t = {}, 0
                    for _, num in ipairs(nums) do
                        while true do
                            t = t + 1
                            -- generous bound: gtr_solo needs 9 nums x 15 letters
                            if t > 500 then
                                error('ladder did not terminate for ' .. base)
                            end
                            local ev = NextSectionEvent(MakeScan(entries), base, num,
                                                        caps, is_generic, use_letters,
                                                        t, P(t))
                            if not ev then break end
                            check(ev)
                            entries[#entries + 1] = { msg = ev, t = t }
                        end
                    end
                end
            end
        end
        for _, g in ipairs(SECTION_EVENT_GROUPS) do
            if g.kind == 'plain' then
                for _, ev in ipairs(g.events) do check(ev) end
            else
                for _, b in ipairs(g.bases) do
                    ladder(b.base, b.caps, g.kind == 'generic')
                end
            end
        end
        Test.expect(#missing == 0, #missing .. ' generated event(s) not in the list, e.g. '
                    .. tostring(missing[1]))
    end)
end

----------------------------------------------------------------------
Test.section('NextSectionEvent / ValidatePlainInsert (pure validation)')
----------------------------------------------------------------------

local V = SECTION_EVENT_BASE.verse.caps       -- 'ffffdddddd'
local A = SECTION_EVENT_BASE.alt_verse.caps   -- 'd'
local B = SECTION_EVENT_BASE.bre.caps         -- '.'
local EMPTY = MakeScan({})

Test.it('letters off -> plain forms; letters on -> lettered from the start', function()
    Test.expect(NextSectionEvent(EMPTY, 'verse', 0, V, false, false, 10, P(10)) == '[prc_verse]')
    Test.expect(NextSectionEvent(EMPTY, 'verse', 1, V, false, false, 10, P(10)) == '[prc_verse_1]')
    Test.expect(NextSectionEvent(EMPTY, 'verse', 0, V, false, true, 10, P(10)) == '[prc_verse_a]')
    Test.expect(NextSectionEvent(EMPTY, 'verse', 1, V, false, true, 10, P(10)) == '[prc_verse_1a]')
end)

Test.it('letter escalation: a -> b', function()
    local scan = MakeScan({ { msg = '[prc_verse_a]', t = 1 } })
    Test.expect(NextSectionEvent(scan, 'verse', 0, V, false, true, 10, P(10)) == '[prc_verse_b]')
    scan = MakeScan({ { msg = '[prc_verse_1a]', t = 1 } })
    Test.expect(NextSectionEvent(scan, 'verse', 1, V, false, true, 10, P(10)) == '[prc_verse_1b]')
end)

Test.it('plain and lettered forms must not be mixed (both directions)', function()
    local scan = MakeScan({ { msg = '[prc_verse_1]', t = 1 } })
    local ev, err = NextSectionEvent(scan, 'verse', 1, V, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('must not be mixed', 1, true), 'got ' .. tostring(err))
    scan = MakeScan({ { msg = '[prc_verse_1a]', t = 1 } })
    ev, err = NextSectionEvent(scan, 'verse', 1, V, false, false, 10, P(10))
    Test.expect(ev == nil and err:find('Lettered [prc_verse_1a] exists', 1, true),
                'got ' .. tostring(err))
end)

Test.it('numbers must be used in order: _2 needs a _1 family', function()
    local ev, err = NextSectionEvent(EMPTY, 'verse', 2, V, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('[prc_verse_1]', 1, true)
                and err:find('in order', 1, true), 'got ' .. tostring(err))
    -- a lettered _1 counts as the _1 family
    local scan = MakeScan({ { msg = '[prc_verse_1a]', t = 5 } })
    Test.expect(NextSectionEvent(scan, 'verse', 2, V, false, true, 10, P(10))
                == '[prc_verse_2a]')
end)

Test.it('letter gaps are filled, placed between their neighbors', function()
    local scan = MakeScan({ { msg = '[prc_verse_1a]', t = 2 },
                            { msg = '[prc_verse_1c]', t = 6 } })
    -- cursor between _1a and _1c -> the missing _1b is offered
    Test.expect(NextSectionEvent(scan, 'verse', 1, V, false, true, 4, P(4)) == '[prc_verse_1b]')
    -- cursor after _1c -> ordering refusal naming _1c
    local ev, err = NextSectionEvent(scan, 'verse', 1, V, false, true, 8, P(8))
    Test.expect(ev == nil and err:find('before [prc_verse_1c]', 1, true),
                'got ' .. tostring(err))
    -- cursor before _1a -> must be after _1a
    ev, err = NextSectionEvent(scan, 'verse', 1, V, false, true, 1, P(1))
    Test.expect(ev == nil and err:find('after [prc_verse_1a]', 1, true),
                'got ' .. tostring(err))
end)

Test.it('timeline ordering across numbers (both directions)', function()
    local scan = MakeScan({ { msg = '[prc_verse_1]', t = 10 },
                            { msg = '[prc_verse_3]', t = 30 } })
    -- _2 into the gap is fine (letters off - families are plain here)
    Test.expect(NextSectionEvent(scan, 'verse', 2, V, false, false, 20, P(20)) == '[prc_verse_2]')
    -- _2 before _1 refused
    local ev, err = NextSectionEvent(scan, 'verse', 2, V, false, false, 5, P(5))
    Test.expect(ev == nil and err:find('after [prc_verse_1]', 1, true), 'got ' .. tostring(err))
    -- _2 after _3 refused
    ev, err = NextSectionEvent(scan, 'verse', 2, V, false, false, 40, P(40))
    Test.expect(ev == nil and err:find('before [prc_verse_3]', 1, true), 'got ' .. tostring(err))
    -- same with lettered families
    scan = MakeScan({ { msg = '[prc_verse_1a]', t = 10 },
                      { msg = '[prc_verse_3a]', t = 30 } })
    Test.expect(NextSectionEvent(scan, 'verse', 2, V, false, true, 20, P(20)) == '[prc_verse_2a]')
end)

Test.it('bare and numbered must not co-exist (both directions)', function()
    local scan = MakeScan({ { msg = '[prc_verse]', t = 1 } })
    local ev, err = NextSectionEvent(scan, 'verse', 1, V, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('Bare [prc_verse] exists', 1, true), 'got ' .. tostring(err))
    scan = MakeScan({ { msg = '[prc_verse_2a]', t = 1 } })
    ev, err = NextSectionEvent(scan, 'verse', 0, V, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('Numbered [prc_verse_2a] exists', 1, true),
                'got ' .. tostring(err))
end)

Test.it('use_letters=false: duplicate refused with location', function()
    local scan = MakeScan({ { msg = '[prc_verse_1]', t = 3 } })
    local ev, err = NextSectionEvent(scan, 'verse', 1, V, false, false, 10, P(10))
    Test.expect(ev == nil and err:find('already exists at t=3.0', 1, true),
                'got ' .. tostring(err))
end)

Test.it('cap exhaustion refuses with a reason', function()
    local scan = MakeScan({ { msg = '[prc_alt_verse_a]', t = 2 },
                            { msg = '[prc_alt_verse_b]', t = 3 },
                            { msg = '[prc_alt_verse_c]', t = 4 },
                            { msg = '[prc_alt_verse_d]', t = 5 } })
    local ev, err = NextSectionEvent(scan, 'alt_verse', 0, A, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('No more letters', 1, true), 'got ' .. tostring(err))
end)

Test.it('invalid number refuses', function()
    local ev, err = NextSectionEvent(EMPTY, 'alt_verse', 1, A, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('no _1 variant', 1, true), 'got ' .. tostring(err))
end)

Test.it('bare-only base ("." caps) falls back to plain even in letter mode', function()
    Test.expect(NextSectionEvent(EMPTY, 'bre', 0, B, false, true, 10, P(10)) == '[prc_bre]')
    local scan = MakeScan({ { msg = '[prc_bre]', t = 1 } })
    local ev, err = NextSectionEvent(scan, 'bre', 0, B, false, true, 10, P(10))
    Test.expect(ev == nil and err:find('already exists', 1, true), 'got ' .. tostring(err))
end)

Test.it('same-spot refused; crowd events at the spot do not block', function()
    local scan = MakeScan({ { msg = '[prc_chorus]', t = 5 } })
    local ev, err = NextSectionEvent(scan, 'verse', 0, V, false, true, 5, P(5))
    Test.expect(ev == nil and err:find('already at this position', 1, true),
                'got ' .. tostring(err))
    scan = MakeScan({ { msg = '[crowd_normal]', t = 5 } })
    Test.expect(NextSectionEvent(scan, 'verse', 0, V, false, true, 5, P(5)) == '[prc_verse_a]')
end)

Test.it('generic: no underscore, sequence rules, never letters', function()
    Test.expect(NextSectionEvent(EMPTY, 'a', 0, nil, true, true, 10, P(10)) == '[prc_a]')
    Test.expect(NextSectionEvent(EMPTY, 'a', 1, nil, true, true, 10, P(10)) == '[prc_a1]')
    -- _3 needs _2
    local scan = MakeScan({ { msg = '[prc_a1]', t = 1 } })
    local ev, err = NextSectionEvent(scan, 'a', 3, nil, true, true, 10, P(10))
    Test.expect(ev == nil and err:find('[prc_a2]', 1, true), 'got ' .. tostring(err))
    -- bare vs numbered exclusivity applies too
    ev, err = NextSectionEvent(scan, 'a', 0, nil, true, true, 10, P(10))
    Test.expect(ev == nil and err:find('Numbered', 1, true), 'got ' .. tostring(err))
    -- duplicates refused (letters never offered)
    ev, err = NextSectionEvent(scan, 'a', 1, nil, true, true, 10, P(10))
    Test.expect(ev == nil and err:find('already exists', 1, true), 'got ' .. tostring(err))
end)

Test.it('ValidatePlainInsert: crowd exempt, others duplicate/spot-checked', function()
    local scan = MakeScan({ { msg = '[crowd_normal]', t = 2 },
                            { msg = '[music_start]',  t = 4 } })
    -- crowd: duplicates and stacking allowed
    Test.expect(ValidatePlainInsert(scan, '[crowd_normal]', P(4)) == true)
    -- global duplicate refused
    local ok, err = ValidatePlainInsert(scan, '[music_start]', P(8))
    Test.expect(ok == nil and err:find('already exists', 1, true), 'got ' .. tostring(err))
    -- global on an occupied (non-crowd) spot refused
    ok, err = ValidatePlainInsert(scan, '[music_end]', P(4))
    Test.expect(ok == nil and err:find('already at this position', 1, true),
                'got ' .. tostring(err))
    -- global on a crowd-occupied spot allowed
    Test.expect(ValidatePlainInsert(scan, '[music_end]', P(2)) == true)
end)

----------------------------------------------------------------------
Test.section('MakeProjectPoll (shared poll gate)')
----------------------------------------------------------------------

Test.it('first call fires, unchanged project does not, force does', function()
    local poll = MakeProjectPoll(0, 3600)
    Test.expect(poll() == true, 'first call fires')
    Test.expect(poll() == false, 'no change -> no fire')
    Test.expect(poll(true) == true, 'force fires')
    Test.expect(poll() == false, 'still quiet right after force')
end)

Test.it('project change fires at min 0, held back inside the min window', function()
    local p0 = MakeProjectPoll(0, 3600)
    local p1 = MakeProjectPoll(3600, 7200)
    p0(); p1()                                          -- prime both
    -- GetProjectStateChangeCount only increments when an undo point is
    -- registered - bare API edits (InsertTrackAtIndex etc.) don't bump it.
    -- That is also why the production pollers work: every edit path in the
    -- helpers is wrapped in an undo block, and user edits in REAPER always
    -- create undo points. The fixture edit must do the same.
    r.Undo_BeginBlock2(0)
    local idx = CreateEmptyFixtureTrack('POLL TEST')
    r.Undo_EndBlock2(0, 'RB test: poll fixture track', -1)
    CleanupFixture(idx)
    Test.expect(p0() == true,  'min 0: fires right after a project change')
    Test.expect(p1() == false, 'min 3600: change held back inside the window')
end)

----------------------------------------------------------------------
Test.section('GenerateKeyframesForSpan ([first] on the lighting event)')
----------------------------------------------------------------------
-- start_ppq is always the manual lighting event's own tick, so [first] belongs
-- there. Align modes only decide where the first [next] lands. Modes 0 and 1 are
-- pure tick arithmetic - no take needed (only mode 2 and the instrument modes
-- consult the tempo map / instrument tracks).

local KF_PPQ = 960  -- ticks per quarter note

-- Run one span with the given align mode, restoring the shared setting after.
local function KfSpan(align, start_ppq, end_ppq, rate_beats)
    local saved = S.venue_keyframe_align
    S.venue_keyframe_align = align
    local ok, res = pcall(GenerateKeyframesForSpan, nil, start_ppq, end_ppq, KF_PPQ, rate_beats)
    S.venue_keyframe_align = saved
    if not ok then error(res, 2) end
    return res
end

-- Positions of every event carrying `text`, in emission order.
local function KfPositions(events, text)
    local out = {}
    for _, ev in ipairs(events) do
        if ev.text == text then out[#out + 1] = ev.ppq end
    end
    return out
end

Test.it('exactly one [first], always on start_ppq, always the earliest event', function()
    for _, align in ipairs({ 0, 1 }) do
        for _, start_ppq in ipairs({ 0, 700, 960, 2 * KF_PPQ }) do
            local evs   = KfSpan(align, start_ppq, start_ppq + 16 * KF_PPQ, 2)
            local firsts = KfPositions(evs, '[first]')
            Test.expect(#firsts == 1,
                ('align %d, start %d: expected 1 [first], got %d'):format(align, start_ppq, #firsts))
            Test.expect(firsts[1] == start_ppq,
                ('align %d: [first] at %d, expected the lighting event tick %d')
                    :format(align, firsts[1], start_ppq))
            Test.expect(evs[1].text == '[first]', 'the [first] must be emitted before any [next]')
            for _, p in ipairs(KfPositions(evs, '[next]')) do
                Test.expect(p > start_ppq,
                    ('align %d: a [next] landed at %d, on or before [first]'):format(align, p))
            end
        end
    end
end)

Test.it('Keyframe rate only: no keyframe at the anchor, first [next] one rate on', function()
    -- Off-beat start: the [next] grid still anchors to the nearest beat (0 here).
    local evs   = KfSpan(0, 240, 16 * KF_PPQ, 2)
    local nexts = KfPositions(evs, '[next]')
    Test.expect(nexts[1] == 2 * KF_PPQ,
        ('expected the first [next] at %d (beat anchor + 2 beats), got %s')
            :format(2 * KF_PPQ, tostring(nexts[1])))
    Test.expect(nexts[2] == 4 * KF_PPQ, 'the [next] train continues at the keyframe rate')
end)

Test.it('Closest beat: the snapped beat is now a [next], not the [first]', function()
    -- start 700 -> nearest beat is 960, forward of the lighting event.
    local evs   = KfSpan(1, 700, 16 * KF_PPQ, 2)
    local nexts = KfPositions(evs, '[next]')
    Test.expect(KfPositions(evs, '[first]')[1] == 700,
        '[first] must stay on the lighting event, not move to the snapped beat')
    Test.expect(nexts[1] == KF_PPQ,
        ('expected a [next] on the snapped beat %d, got %s'):format(KF_PPQ, tostring(nexts[1])))
    Test.expect(nexts[2] == 3 * KF_PPQ,
        'the train continues one rate past the beat anchor')
end)

Test.it('Closest beat: a beat-aligned lighting event gets no duplicate at its own tick', function()
    local evs = KfSpan(1, KF_PPQ, 16 * KF_PPQ, 2)
    local at_start = 0
    for _, ev in ipairs(evs) do
        if ev.ppq == KF_PPQ then at_start = at_start + 1 end
    end
    Test.expect(at_start == 1,
        ('expected exactly 1 event on the lighting tick, got %d'):format(at_start))
    Test.expect(KfPositions(evs, '[next]')[1] == 3 * KF_PPQ,
        'first [next] one rate past the beat anchor')
end)

Test.it('a span too short for any keyframe yields nothing', function()
    Test.expect(#KfSpan(0, 5 * KF_PPQ, 5 * KF_PPQ, 2) == 0, 'zero-length span')
end)

----------------------------------------------------------------------
Test.section('GenerateThemedSectionEvents (blend-in duplicates the OUTGOING preset)')
----------------------------------------------------------------------
-- Themes gen and Section gen both route through this. A section's own lighting
-- and postproc events always sit ON its section start; lightpreset_blendin /
-- postproc_blendin only say how many beats earlier the PREVIOUSLY active preset
-- is re-stated as a blend anchor.

do
    -- Presets pinned to one lightpreset/postproc each so the random picks are
    -- deterministic. Section 'a' is the outgoing preset, 'b' the incoming one.
    local function TwoSectionTheme(a_lt, a_pp, b_lt, b_pp, lp_blend, pp_blend, kf_rate)
        local function preset(lt, pp, lpb, ppb)
            return {
                allowed_lightpresets = lt and { lt } or nil,
                allowed_postprocs    = pp and { pp } or nil,
                lightpreset_blendin  = lpb,
                postproc_blendin     = ppb,
                keyframe_rate        = kf_rate,
            }
        end
        return { section_presets = {
            versea = preset(a_lt, a_pp, 0, 0),
            verseb = preset(b_lt, b_pp, lp_blend, pp_blend),
        } }
    end

    -- Runs `sec_qns` sections (start QN per entry, each running to the next start or
    -- +16 QN) through the generator on a throwaway MIDI take. Section i takes its
    -- preset from names[i]. Returns the raw event arrays plus absolute helpers.
    local function RunThemed(align, theme, names, sec_qns, incoming)
        local idx   = CreateEmptyFixtureTrack('KF THEME TEST')
        local item  = r.CreateNewMIDIItemInProj(r.GetTrack(0, idx), 0, 120, false)
        local take  = r.GetActiveTake(item)
        local saved = S.venue_keyframe_align
        S.venue_keyframe_align = align
        local ok, res = pcall(function()
            local ppq  = GetTakePPQPerQN(take)
            local secs, starts = {}, {}
            for i, qn in ipairs(sec_qns) do
                local t_end = sec_qns[i + 1] and r.TimeMap_QNToTime(sec_qns[i + 1])
                               or r.TimeMap_QNToTime(qn + 16)
                secs[i] = { name = names[i], num = nil,
                            t_start = r.TimeMap_QNToTime(qn), t_end = t_end }
                starts[i] = r.MIDI_GetPPQPosFromProjTime(take, secs[i].t_start)
            end
            local range_e = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap_QNToTime(64))
            local lt, ctrl, pp, stats = GenerateThemedSectionEvents(
                secs, theme, take, 0, range_e, ppq, incoming)
            return { lt = lt, ctrl = ctrl, pp = pp, stats = stats,
                     ppq = ppq, starts = starts }
        end)
        S.venue_keyframe_align = saved
        CleanupFixture(idx)
        if not ok then error(res, 2) end
        return res
    end

    -- Absolute ticks of every event in `events` whose text is `text` (range starts at 0).
    local function TicksOf(events, text)
        local out = {}
        for _, ev in ipairs(events) do
            if ev.text == text then out[#out + 1] = ev.tick end
        end
        return out
    end

    Test.it("a section's own lighting and postproc land ON its section start", function()
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        Test.expect(TicksOf(g.lt, '[lighting (verse)]')[1] == g.starts[2],
            'the incoming lighting must not be moved off the section start')
        Test.expect(TicksOf(g.pp, '[ProFilm_b.pp]')[1] == g.starts[2],
            'the incoming postproc must not be moved off the section start')
    end)

    Test.it('the outgoing preset is duplicated at each blend point', function()
        -- lightpreset_blendin 1, postproc_blendin 2 - the user's m9b4 / m9b3 example.
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        local lt_dups = TicksOf(g.lt, '[lighting (stomp)]')
        local pp_dups = TicksOf(g.pp, '[ProFilm_a.pp]')
        Test.expect(#lt_dups == 2, 'expected the original + one duplicate, got ' .. #lt_dups)
        Test.expect(#pp_dups == 2, 'expected the original + one duplicate, got ' .. #pp_dups)
        Test.expect(lt_dups[1] == g.starts[1], 'section 1 keeps its own event in place')
        Test.expect(lt_dups[2] == g.starts[2] - 1 * g.ppq,
            ('lighting duplicate expected at %d (1 beat early), got %d')
                :format(g.starts[2] - g.ppq, lt_dups[2]))
        Test.expect(pp_dups[2] == g.starts[2] - 2 * g.ppq,
            ('postproc duplicate expected at %d (2 beats early), got %d')
                :format(g.starts[2] - 2 * g.ppq, pp_dups[2]))
        Test.expect(lt_dups[2] ~= pp_dups[2],
            'differing blendin values must put the two duplicates on different ticks')
    end)

    Test.it('a blend duplicate is a bare lighting event - no [first] of its own', function()
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        local blend_ppq = SnapPpqToHalfBeat(g.starts[2] - 1 * g.ppq, g.ppq)
        local firsts    = TicksOf(g.ctrl, '[first]')
        local found = {}
        for _, t in ipairs(firsts) do found[t] = true end
        Test.expect(not found[blend_ppq],
            'the duplicate restates a running preset - it must not restart the sequence')
        Test.expect(found[g.starts[1]] and found[g.starts[2]],
            'both sections should still have a [first] on their own start')
        Test.expect(#firsts == 2,
            'expected 2 [first]s (one per section), got ' .. #firsts)
    end)

    Test.it("the outgoing section's [next] train runs through the blend zone", function()
        -- Sections at QN 8 and 24, 4-beat lighting blend (blend point QN 20), rate 4.
        -- Nothing restarts the sequence at the blend point any more, so section 1's
        -- train keeps its full length right up to the section boundary.
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 4, 4, 4),
                            { 'versea', 'verseb' }, { 8, 24 })
        local qn    = function(n) return g.starts[1] + (n - 8) * g.ppq end
        local nexts = {}
        for _, t in ipairs(TicksOf(g.ctrl, '[next]')) do nexts[t] = true end
        Test.expect(nexts[qn(12)] and nexts[qn(16)], "section 1's train should run")
        Test.expect(nexts[qn(20)],
            'the [next] on the blend point should no longer be clamped away')
    end)

    Test.it('a section keeping the previous preset writes nothing, but keeps keyframing', function()
        -- Lighting unchanged across the boundary. Both single-entry pools, so the
        -- re-roll has nowhere to go and the emit gate is what handles it: the section
        -- writes no lighting event at all, because re-stating the running preset is
        -- exactly how a blend anchor is written and this one is not a blend.
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'stomp', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        local found = {}
        for _, t in ipairs(TicksOf(g.ctrl, '[first]')) do found[t] = true end
        Test.expect(found[g.starts[1]], 'the first section still starts the sequence')
        Test.expect(not found[g.starts[2]],
            'a section restating the running preset must not restart the sequence')
        Test.expect(#TicksOf(g.lt, '[lighting (stomp)]') == 1,
            'only section 1s event should exist, got '
            .. #TicksOf(g.lt, '[lighting (stomp)]'))
        Test.expect(g.stats.lt_skipped == 1,
            'the skip should be counted, got ' .. g.stats.lt_skipped)
        -- The keyframes are NOT skipped with it: section 1s train stopped at its own
        -- end, so without one here the preset would run on with its lights frozen.
        local past = false
        for _, t in ipairs(TicksOf(g.ctrl, '[next]')) do
            if t > g.starts[2] then past = true end
        end
        Test.expect(past, 'the [next] train should still run inside the second section')
    end)

    Test.it('an unchanged preset is judged per kind', function()
        -- Lighting is the same across both sections, postproc changes. The two are
        -- decided independently, so the postproc still gets its blend duplicate.
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'stomp', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        Test.expect(#TicksOf(g.lt, '[lighting (stomp)]') == 1,
            'unchanged lighting must not be re-stated (1 = section 1s own event)')
        Test.expect(#TicksOf(g.pp, '[ProFilm_a.pp]') == 2,
            'the changed postproc should still be duplicated once')
        Test.expect(g.stats.pp_skipped == 0,
            'postproc was a real change, nothing to skip')
    end)

    Test.it('a blendin longer than the previous section emits no duplicate', function()
        -- Section 1 is 2 QN long; section 2 asks for an 8-beat lighting blend, which
        -- would place the copy before the event it copies.
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 8, 8, 2),
                            { 'versea', 'verseb' }, { 8, 10 })
        Test.expect(#TicksOf(g.lt, '[lighting (stomp)]') == 1,
            'expected only section 1s own lighting event, no duplicate ahead of it')
        Test.expect(#TicksOf(g.pp, '[ProFilm_a.pp]') == 1,
            'expected only section 1s own postproc event, no duplicate ahead of it')
    end)

    Test.it('incoming: the first section blends out of the caller-supplied preset', function()
        local theme = TwoSectionTheme(nil, nil, 'verse', 'ProFilm_b.pp', 1, 2, 2)
        local g = RunThemed(0, theme, { 'verseb' }, { 8 }, {
            lt_text = '[lighting (intro)]', pp_text = '[ProFilm_a.pp]', sec_ppq = 0,
        })
        Test.expect(TicksOf(g.lt, '[lighting (intro)]')[1] == g.starts[1] - 1 * g.ppq,
            'the incoming lighting should be re-stated at the blend point')
        Test.expect(TicksOf(g.pp, '[ProFilm_a.pp]')[1] == g.starts[1] - 2 * g.ppq,
            'the incoming postproc should be re-stated at its own blend point')
    end)

    Test.it('no incoming: the first section emits no duplicate', function()
        local g = RunThemed(0, TwoSectionTheme(nil, nil, 'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'verseb' }, { 8 })
        Test.expect(#g.lt == 1 and g.lt[1].tick == g.starts[1],
            'nothing known to blend out of - only the section own event')
        Test.expect(#g.pp == 1 and g.pp[1].tick == g.starts[1], 'same for postproc')
    end)

    Test.it('zero blend-in: [first] on the section start, nothing else there', function()
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 0, 0, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        local at_sec = {}
        for _, ev in ipairs(g.ctrl) do
            if ev.tick == g.starts[2] then at_sec[#at_sec + 1] = ev.text end
        end
        Test.expect(#at_sec == 1 and at_sec[1] == '[first]',
            'expected exactly one [first] at the section start, got ' ..
            table.concat(at_sec, ','))
        Test.expect(#TicksOf(g.lt, '[lighting (stomp)]') == 1, 'no duplicate without blendin')
    end)

    Test.it('every [first] sits on a manual lighting event, never orphaned', function()
        local g = RunThemed(0, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })
        -- The callers half-beat-snap lighting events and insert keyframes unsnapped,
        -- so this is the equality that decides whether they share a tick on the track.
        local lt_ticks = {}
        for _, ev in ipairs(g.lt) do
            if MANUAL_LIGHTING_SET[ev.text] then
                lt_ticks[SnapPpqToHalfBeat(ev.tick, g.ppq)] = true
            end
        end
        for _, t in ipairs(TicksOf(g.ctrl, '[first]')) do
            Test.expect(lt_ticks[t],
                ('[first] at %d has no manual lighting event on that tick'):format(t))
        end
    end)

    Test.it('instrument modes: no [next] at the section start', function()
        local g = RunThemed(3, TwoSectionTheme('stomp', 'ProFilm_a.pp',
                                               'verse', 'ProFilm_b.pp', 1, 2, 2),
                            { 'versea', 'verseb' }, { 8, 24 })   -- 3 = Guitar notes
        for _, ev in ipairs(g.ctrl) do
            Test.expect(not (ev.text == '[next]' and ev.tick == g.starts[2]),
                'instrument modes must not emit a [next] at the (note-less) section start')
        end
        Test.expect(#TicksOf(g.ctrl, '[first]') >= 2, 'each lighting event still gets a [first]')
    end)
end

----------------------------------------------------------------------
Test.section('EVENTS track integration')
----------------------------------------------------------------------

-- These tests create a track named EVENTS; never run them against a project
-- that already has a real one.
if FindTrackByName('EVENTS') then
    r.ShowConsoleMsg('  SKIP  integration tests (this project already has an EVENTS track)\n')
else

    -- Run fn with a fixture EVENTS track (+ optional MIDI item), always
    -- cleaning up. item_len defaults to 10 seconds; pass len_is_qn = true to
    -- interpret it in quarter notes (tempo-independent measure counts for
    -- the bookends tests).
    local function WithEventsFixture(with_item, fn, item_len, len_is_qn)
        local idx = CreateEmptyFixtureTrack('EVENTS')
        local take
        if with_item then
            local item = r.CreateNewMIDIItemInProj(r.GetTrack(0, idx), 0,
                                                   item_len or 10, len_is_qn or false)
            take = r.GetActiveTake(item)
        end
        local ok, err = pcall(fn, take)
        CleanupFixture(idx)
        if not ok then error(err, 2) end
    end

    -- Project time of a 1-based measure's start
    local function MeasureStart(mnum)
        return ({r.TimeMap_GetMeasureInfo(0, mnum - 1)})[1]
    end

    -- Last measure fully contained in the take's item (same rule the
    -- bookends action implements, computed independently here)
    local function LastFullMeasure(take)
        local item = r.GetMediaItemTake_Item(take)
        local item_end = r.GetMediaItemInfo_Value(item, 'D_POSITION')
                       + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local end_qn = r.TimeMap2_timeToQN(0, item_end)
        local last, m = nil, 0
        while m < 100000 do
            local _, qn_start, qn_end = r.TimeMap_GetMeasureInfo(0, m)
            if qn_start > end_qn + 1e-9 then break end
            if qn_end <= end_qn + 1e-9 then last = m + 1 end
            m = m + 1
        end
        return last
    end

    local function TextEvtCount(take)
        local _, _, _, textcnt = r.MIDI_CountEvts(take)
        return textcnt
    end

    -- All type-1 events as { msg -> project time } (assumes unique msgs)
    local function ReadTextEvents(take)
        local out = {}
        local _, _, _, textcnt = r.MIDI_CountEvts(take)
        for i = 0, textcnt - 1 do
            local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, i)
            if ok and typ == 1 then out[msg] = r.MIDI_GetProjTimeFromPPQPos(take, ppq) end
        end
        return out
    end

    Test.it('FindNamedTrackMIDI: track+item+take / track-only / missing', function()
        local t1, i1, k1 = FindNamedTrackMIDI('EVENTS')
        Test.expect(t1 == nil and i1 == nil and k1 == nil, 'missing track -> all nil')
        WithEventsFixture(false, function()
            local t2, i2, k2 = FindNamedTrackMIDI('EVENTS')
            Test.expect(t2 ~= nil and i2 == nil and k2 == nil,
                        'track without MIDI item -> track only')
        end)
        WithEventsFixture(true, function(take)
            local t3, i3, k3 = FindNamedTrackMIDI('EVENTS')
            Test.expect(t3 ~= nil and i3 ~= nil and k3 == take,
                        'track with MIDI item -> track, item, take')
            Test.expect(GetTakePPQPerQN(take) > 0, 'GetTakePPQPerQN positive')
        end)
    end)

    Test.it('missing EVENTS track: status set, nothing inserted', function()
        S.status = ''
        AddSectionEvent('verse', 0, V, false, true)
        Test.expect(S.status == 'No EVENTS track found.', 'status: ' .. tostring(S.status))
    end)

    Test.it('EVENTS track without MIDI item: status set', function()
        WithEventsFixture(false, function()
            S.status = ''
            AddSectionEvent('verse', 0, V, false, true)
            Test.expect(S.status == 'No MIDI item on EVENTS track.',
                        'status: ' .. tostring(S.status))
        end)
    end)

    Test.it('insert, escalation, and validation round-trip', function()
        WithEventsFixture(true, function(take)
            local _, _, found = FindEventsTake()
            Test.expect(found == take, 'FindEventsTake finds the fixture take')

            -- letters on: _1a -> _1b -> _1c at increasing cursor positions
            -- (no unlettered form is ever created)
            r.SetEditCurPos(2.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)
            r.SetEditCurPos(4.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)
            r.SetEditCurPos(6.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)
            local ev = ReadTextEvents(take)
            Test.expect(ev['[prc_verse_1a]'] and ev['[prc_verse_1b]'] and ev['[prc_verse_1c]']
                        and not ev['[prc_verse_1]'],
                        'lettered chain present, no unlettered form')

            -- letters off on the same family: mixing refused, count unchanged
            local before = TextEvtCount(take)
            r.SetEditCurPos(8.0, false, false)
            S.status = ''
            AddSectionEvent('verse', 1, V, false, false)
            Test.expect(TextEvtCount(take) == before and
                        S.status:find('Lettered', 1, true),
                        'mixing refused: ' .. tostring(S.status))
            Test.expect(S.last_result == S.status, 'refusal reported in result section')

            -- bare while numbered exist: refused
            S.status = ''
            AddSectionEvent('verse', 0, V, false, true)
            Test.expect(TextEvtCount(take) == before and
                        S.status:find('must not', 1, true),
                        'exclusivity refused: ' .. tostring(S.status))

            -- same-spot: another prc event on _1a's position refused
            r.SetEditCurPos(2.0, false, false)
            S.status = ''
            AddSectionEvent('chorus', 1, SECTION_EVENT_BASE.chorus.caps, false, true)
            Test.expect(TextEvtCount(take) == before and
                        S.status:find('already at this position', 1, true),
                        'same-spot refused: ' .. tostring(S.status))

            -- ...but a crowd event may stack there
            InsertEventsEvent('[crowd_intense]')
            Test.expect(TextEvtCount(take) == before + 1, 'crowd stacked on occupied spot')

            -- global insert + duplicate refusal
            r.SetEditCurPos(9.0, false, false)
            InsertEventsEvent('[music_start]')
            Test.expect(ReadTextEvents(take)['[music_start]'], '[music_start] present')
            S.status = ''
            r.SetEditCurPos(9.5, false, false)
            InsertEventsEvent('[music_start]')
            Test.expect(S.status:find('already exists', 1, true),
                        'global duplicate refused: ' .. tostring(S.status))
        end)
    end)

    Test.it('letter exhaustion refuses at Add level', function()
        WithEventsFixture(true, function(take)
            local seeds = { '[prc_alt_verse_a]', '[prc_alt_verse_b]',
                            '[prc_alt_verse_c]', '[prc_alt_verse_d]' }
            for i, ev in ipairs(seeds) do
                local ppq = r.MIDI_GetPPQPosFromProjTime(take, i * 0.5)
                r.MIDI_InsertTextSysexEvt(take, false, false, ppq, 1, ev)
            end
            local before = TextEvtCount(take)
            r.SetEditCurPos(8.0, false, false)
            S.status = ''
            AddSectionEvent('alt_verse', 0, A, false, true)
            Test.expect(TextEvtCount(take) == before, 'nothing inserted on refusal')
            Test.expect(S.status:find('No more letters', 1, true),
                        'status: ' .. tostring(S.status))
        end)
    end)

    Test.it('lettered parts merge cleanly in ReadEventSections', function()
        WithEventsFixture(true, function(take)
            r.SetEditCurPos(2.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)   -- [prc_verse_1a]
            r.SetEditCurPos(4.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)   -- [prc_verse_1b]
            r.SetEditCurPos(6.0, false, false)
            AddSectionEvent('verse', 1, V, false, true)   -- [prc_verse_1c]
            r.SetEditCurPos(8.0, false, false)
            AddSectionEvent('verse', 2, V, false, true)   -- [prc_verse_2a]
            local sections = ReadEventSections(10.0)
            Test.expect(sections, 'ReadEventSections succeeded')
            -- _1a/_1b/_1c merge into one lettered section; _2a is separate
            Test.expect(#sections == 2, #sections .. ' sections (want 2)')
            Test.expect(sections[1].is_lettered and sections[1].sub_count == 3,
                        'first section merged from _1a/_1b/_1c')
        end)
    end)

    Test.it('letter-only parts (no number) merge cleanly in ReadEventSections', function()
        WithEventsFixture(true, function(take)
            r.SetEditCurPos(2.0, false, false)
            AddSectionEvent('verse', 0, V, false, true)   -- [prc_verse_a]
            r.SetEditCurPos(4.0, false, false)
            AddSectionEvent('verse', 0, V, false, true)   -- [prc_verse_b]
            r.SetEditCurPos(6.0, false, false)
            AddSectionEvent('verse', 0, V, false, true)   -- [prc_verse_c]
            r.SetEditCurPos(8.0, false, false)
            AddSectionEvent('chorus', 0, SECTION_EVENT_BASE.chorus.caps, false, false)  -- [prc_chorus]
            local sections = ReadEventSections(10.0)
            Test.expect(sections, 'ReadEventSections succeeded')
            -- _a/_b/_c (no number) merge into one lettered section; bare
            -- chorus stays standalone
            Test.expect(#sections == 2, #sections .. ' sections (want 2)')
            Test.expect(sections[1].is_lettered and sections[1].sub_count == 3
                        and sections[1].num == nil,
                        'letter-only parts merged (num=nil, sub_count=3)')
            Test.expect(not sections[2].is_lettered and sections[2].sub_count == 1,
                        'bare chorus is standalone')
        end)
    end)

    Test.it('Clear all removes every text event', function()
        WithEventsFixture(true, function(take)
            r.SetEditCurPos(2.0, false, false)
            AddSectionEvent('verse', 0, V, false, true)   -- [prc_verse_a]
            InsertEventsEvent('[crowd_normal]')
            Test.expect(TextEvtCount(take) == 2, 'seeded 2 events')
            ClearAllEventsTexts()
            Test.expect(TextEvtCount(take) == 0, 'all text events removed')
            Test.expect(S.status:find('Removed 2', 1, true), 'status: ' .. tostring(S.status))
        end)
    end)

    -- Bookend items are created with QN lengths so measure counts don't
    -- depend on the open project's tempo (120 QN = 30 measures in 4/4).
    Test.it('bookends: full set on a long item, recalculated on re-run', function()
        WithEventsFixture(true, function(take)
            local E = LastFullMeasure(take)
            Test.expect(E and E >= 7, 'fixture long enough (E=' .. tostring(E) .. ')')
            InsertEventsBookends()
            local ev = ReadTextEvents(take)
            Test.expect(TextEvtCount(take) == 6, TextEvtCount(take) .. ' events (want 6)')
            local function near(a, b) return a and math.abs(a - b) < 0.01 end
            Test.expect(near(ev['[prc_intro]'],   MeasureStart(1)),     'intro at measure 1')
            Test.expect(near(ev['[crowd_normal]'], MeasureStart(1)),    'crowd at measure 1')
            Test.expect(near(ev['[music_start]'], MeasureStart(3)),     'music_start at measure 3')
            Test.expect(near(ev['[end]'],         MeasureStart(E)),     '[end] at measure E')
            Test.expect(near(ev['[music_end]'],   MeasureStart(E - 2)), '[music_end] at E-2')
            Test.expect(near(ev['[prc_outro]'],   MeasureStart(E - 5)), '[prc_outro] at E-5')
            -- re-run: removes and re-inserts, count unchanged
            InsertEventsBookends()
            Test.expect(TextEvtCount(take) == 6, 're-run is idempotent')
        end, 120, true)
    end)

    Test.it('bookends: end events skipped on a short item', function()
        WithEventsFixture(true, function(take)
            local E = LastFullMeasure(take)
            Test.expect(not E or E < 7, 'fixture short enough (E=' .. tostring(E) .. ')')
            InsertEventsBookends()
            local ev = ReadTextEvents(take)
            Test.expect(TextEvtCount(take) == 3, TextEvtCount(take) .. ' events (want 3)')
            Test.expect(ev['[prc_intro]'] and ev['[crowd_normal]'] and ev['[music_start]'],
                        'start trio present')
            Test.expect(not ev['[end]'], 'no [end] on short item')
            Test.expect(S.last_result and S.last_result:find('End events skipped', 1, true),
                        'skip reported in result')
        end, 12, true)   -- 12 QN = 3 full measures in 4/4
    end)

    Test.it('bookends: occupied spot is skipped and reported', function()
        WithEventsFixture(true, function(take)
            -- foreign event exactly on measure 3's start
            local ppq = r.MIDI_GetPPQPosFromProjTime(take, MeasureStart(3))
            r.MIDI_InsertTextSysexEvt(take, false, false, ppq, 1, '[prc_verse]')
            InsertEventsBookends()
            local ev = ReadTextEvents(take)
            Test.expect(not ev['[music_start]'], '[music_start] skipped')
            Test.expect(S.last_result:find('Skipped [music_start]', 1, true),
                        'skip reported: ' .. tostring(S.last_result))
        end, 120, true)
    end)

    ------------------------------------------------------------------
    Test.section('FindEventTime / ResolveSongEndAndAnchor (venue song end)')
    ------------------------------------------------------------------

    Test.it('FindEventTime: nil when absent, earliest when duplicated', function()
        WithEventsFixture(true, function(take)
            Test.expect(FindEventTime('[end]') == nil, 'nil when no [end] event exists')
            local p_late  = r.MIDI_GetPPQPosFromProjTime(take, MeasureStart(5))
            local p_early = r.MIDI_GetPPQPosFromProjTime(take, MeasureStart(3))
            r.MIDI_InsertTextSysexEvt(take, false, false, p_late,  1, '[end]')
            r.MIDI_InsertTextSysexEvt(take, false, false, p_early, 1, '[end]')
            local t = FindEventTime('[end]')
            Test.expect(t and math.abs(t - MeasureStart(3)) < 0.01,
                        'earliest occurrence returned, got ' .. tostring(t))
        end, 120, true)
    end)

    -- 120 QN item = 30 measures in 4/4 (same convention as the bookends tests above).
    local function ItemBounds(take)
        local item = r.GetMediaItemTake_Item(take)
        local item_start = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_end    = item_start + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        return item_start, item_end
    end

    Test.it('ResolveSongEndAndAnchor: no [end] -> item length fallback, no anchor', function()
        WithEventsFixture(true, function(take)
            local item_start, item_end = ItemBounds(take)
            local range_end, end_in_range, slack, anchor =
                ResolveSongEndAndAnchor(take, GetTakePPQPerQN(take), item_start, item_end)
            Test.expect(not end_in_range, 'no [end] -> fallback')
            Test.expect(math.abs(range_end - item_end) < 0.01, 'range end = item end')
            Test.expect(slack == 0, 'no slack when falling back')
            Test.expect(anchor == nil, 'no final anchor without [end]')
        end, 120, true)
    end)

    Test.it('ResolveSongEndAndAnchor: [end] present, no [music_end] -> anchor nil, slack measured', function()
        WithEventsFixture(true, function(take)
            local item_start, item_end = ItemBounds(take)
            local end_t = MeasureStart(25)  -- inside the 30-measure item, leaves trailing slack
            r.MIDI_InsertTextSysexEvt(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, end_t), 1, '[end]')
            local range_end, end_in_range, slack, anchor =
                ResolveSongEndAndAnchor(take, GetTakePPQPerQN(take), item_start, item_end)
            Test.expect(end_in_range, '[end] found and used')
            Test.expect(math.abs(range_end - end_t) < 0.01, 'range end = [end] marker time')
            Test.expect(slack > 0.01, 'trailing slack measured (item runs past [end])')
            Test.expect(anchor == nil, 'no [music_end] -> no final anchor')
        end, 120, true)
    end)

    Test.it('ResolveSongEndAndAnchor: [music_end] within 10 measures of [end] -> final anchor', function()
        WithEventsFixture(true, function(take)
            local item_start, item_end = ItemBounds(take)
            local end_t        = MeasureStart(30)
            local music_end_t  = MeasureStart(28)  -- 2 measures before [end] (default bookend spacing)
            r.MIDI_InsertTextSysexEvt(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, end_t), 1, '[end]')
            r.MIDI_InsertTextSysexEvt(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, music_end_t), 1, '[music_end]')
            local _, end_in_range, _, anchor =
                ResolveSongEndAndAnchor(take, GetTakePPQPerQN(take), item_start, item_end)
            Test.expect(end_in_range, '[end] found')
            local anchor_t = anchor and r.MIDI_GetProjTimeFromPPQPos(take, anchor)
            Test.expect(anchor_t and math.abs(anchor_t - music_end_t) < 0.01,
                        'final anchor = [music_end] position, got ' .. tostring(anchor_t))
        end, 120, true)
    end)

    Test.it('ResolveSongEndAndAnchor: [music_end] more than 10 measures before [end] -> no anchor', function()
        WithEventsFixture(true, function(take)
            local item_start, item_end = ItemBounds(take)
            local end_t       = MeasureStart(30)
            local music_end_t = MeasureStart(15)  -- far from [end] - a long instrumental outro
            r.MIDI_InsertTextSysexEvt(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, end_t), 1, '[end]')
            r.MIDI_InsertTextSysexEvt(take, false, false,
                r.MIDI_GetPPQPosFromProjTime(take, music_end_t), 1, '[music_end]')
            local _, _, _, anchor =
                ResolveSongEndAndAnchor(take, GetTakePPQPerQN(take), item_start, item_end)
            Test.expect(anchor == nil, 'far [music_end] does not become the final anchor')
        end, 120, true)
    end)

end
