-- Difficulty > Generate: fast dense runs rewritten one grid slower on Hard.
--
-- PURE: no r, no S. Called by Gen5SelectOnsets (difficulty_generate_rhythm.lua) for Hard,
-- and loaded before it. Reads GEN5_PARAMS at call time.
--
-- On a fast song the Hard gap is a whole 1/8 note, so a run of 16ths thinned in place keeps
-- at most 8 notes a bar and loses its color motion (a 210 BPM solo kept 5 of 14 notes).
-- Instead each passage is played again on the next slower grid - 16ths become 8th triplets,
-- 8th triplets become 8ths - keeping the order of the colors and dropping the tail of each
-- half bar. That is how the chronosp_brutal_decay solo was reduced by hand, and this rule
-- reproduces that hand reduction: every note position, and 165 of 170 colors.

-- The grids a run can be on, fastest first (quarter notes): 32nd triplets, 32nds, 16th
-- triplets, 16ths, 8th triplets, 8ths. A bar moves ONE step slower: 16ths -> 8th triplets,
-- 8th triplets -> 8ths, 16th triplets -> 16ths. Alternating straight and triplet keeps the
-- density step near the 3/4 to 2/3 the hand reduction used, where a same-kind step (16ths
-- -> 8ths) would halve it.
local LADDER = { 1 / 12, 1 / 8, 1 / 6, 1 / 4, 1 / 3, 1 / 2 }

-- The grid a bar's dense notes are on, from their spacings: each spacing snapped to the
-- nearest LADDER step, then the fastest step that occurs at least twice, so one stray tick
-- (bar 152 of the hand-reduced song has a note at 37/24 instead of 36/24) cannot make a
-- bar of 16ths read as 16th triplets. With a single spacing, that one decides.
-- Returns the ladder index.
local function BarGrid(spacings)
    local count = {}
    for _, sp in ipairs(spacings) do
        local best, bd = 1, math.huge
        for k, g in ipairs(LADDER) do
            local d = math.abs(math.log(sp / g))
            if d < bd then best, bd = k, d end
        end
        count[best] = (count[best] or 0) + 1
    end
    local fallback
    for k = 1, #LADDER do
        if count[k] then
            if count[k] >= 2 then return k end
            fallback = fallback or k
        end
    end
    return fallback
end

-- One step slower than the bar's grid; the slowest step stays 8ths.
local function TargetGrid(spacings)
    local k = BarGrid(spacings)
    return LADDER[math.min(k + 1, #LADDER)]
end

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

local function ShapeKey(ev) return table.concat(ev.offs, ',') end

-- Map the dense notes `notes` (sorted) onto `slots` (sorted QN positions). Keeps as many
-- notes as fit, in order, then the cheapest: distance moved (in 1/24 QN), plus a penalty
-- for each skip that creates a color move the source never makes here, plus a tiny cost
-- per note index so a tie keeps the earlier notes and drops the tail. anchor: the first
-- note sits on the first slot (a note on beat 1 or 3 stays there).
-- Returns { { note = i, slot = j }... }.
local function Assign(notes, slots, anchor, penalty)
    local m, ns = #notes, #slots
    if m == 0 or ns == 0 then return {} end
    local moves = {}
    for k = 2, m do moves[ShapeKey(notes[k - 1]) .. '>' .. ShapeKey(notes[k])] = true end
    local function Better(a, b)
        if not b then return true end
        if a[1] ~= b[1] then return a[1] > b[1] end
        return a[2] < b[2]
    end
    local best = {}   -- best[i][j] = { count, cost, prev_i, prev_j }: note i on slot j last
    for i = 1, m do
        best[i] = {}
        for j = 1, ns do
            if not anchor or ((i == 1) == (j == 1)) then
                local d = math.abs(slots[j] - notes[i].qn) * 24 + 0.01 * i
                local cand = (not anchor or i == 1) and { 1, d, 0, 0 } or nil
                for pi = 1, i - 1 do
                    for pj = 1, j - 1 do
                        local pb = best[pi][pj]
                        if pb then
                            local c = pb[2] + d
                            if i - pi > 1 and not moves[ShapeKey(notes[pi]) .. '>' .. ShapeKey(notes[i])] then
                                c = c + penalty
                            end
                            local v = { pb[1] + 1, c, pi, pj }
                            if Better(v, cand) then cand = v end
                        end
                    end
                end
                best[i][j] = cand
            end
        end
    end
    local top, ti, tj
    for i = 1, m do
        for j = 1, ns do
            if best[i][j] and Better(best[i][j], top) then top, ti, tj = best[i][j], i, j end
        end
    end
    local out = {}
    while ti and ti > 0 do
        table.insert(out, 1, { note = ti, slot = tj })
        local b = best[ti][tj]
        ti, tj = b[3], b[4]
    end
    return out
end

-- events: the upper tier (planner input, sorted). opts = { gap = fn(ev) -> the tier's
-- minimum gap at that onset, eps = tolerance }.
-- A DENSE onset is closer than gap(ev) to a neighbour. Above GEN5_PARAMS.fast_8ths_bpm any
-- dense run is rewritten (but a short flourish); at or below it only a run lasting at least
-- GEN5_PARAMS.retime_min_run.slow of its bar - shorter ones are thinned as before. Bars
-- holding dense onsets are rewritten:
--   * grid: one step slower than the bar's closest dense notes (TargetGrid);
--   * segments: half bars, anchored on the bar line and the middle of the bar (one segment
--     when the bar does not split into whole beats), so a bar never loses only its end;
--   * slots: the grid inside the segment, at least a grid step from every note that is not
--     dense (those stay where they are), and between the same two such notes as the dense
--     notes themselves;
--   * a run that LANDS - its last note on a beat, then a beat or more of silence - keeps
--     landing there: no slot after that beat;
--   * a 16th rest before a note on the 8th grid stays: the run restarts at that note;
--   * a LONG run (half a bar or more) sits on one grid aligned to the beats, between its
--     first and last Expert notes, with no free step before the next half bar while it
--     carries on into it (no break in the middle of a run);
--   * a short group that runs straight into the next half bar's beat counts its grid back
--     from that beat, so it still leads into it;
--   * Assign picks which notes go to which slot.
-- Returns (events, retimed_bars): a new event list with the rewritten notes moved
-- (retimed = true) and the dropped ones gone, and { { start = bar start QN, grid }... } for
-- every bar that changed.
function Gen5RetimeDenseRuns(events, opts)
    local p, eps = GEN5_PARAMS, opts.eps
    -- opts.mode: 'auto' | 'thin' | 'rewrite' (GEN5_PARAMS.fast_runs_default when unset).
    local mode = opts.mode or p.fast_runs_default
    if mode == 'thin' then return events, {} end
    local dense, any = {}, false
    for i, ev in ipairs(events) do
        local g = opts.gap(ev) - eps
        local pv, nx = events[i - 1], events[i + 1]
        if (pv and ev.qn - pv.qn < g) or (nx and nx.qn - ev.qn < g) then
            dense[i], any = true, true
        end
    end
    local function Fast(ev) return (ev.bpm or 120) > p.fast_8ths_bpm end
    -- A short flourish into 8ths is thinned on the 8th grid, not rewritten: a run of at
    -- most 3 dense notes that starts on a beat and ends off it (chronosp bass bar 73:
    -- G G R | R R, 16ths then 8ths). As triplets its last note ran on into the 8ths at the
    -- same spacing (G G R R evenly, then a lone R); thinned it keeps G R R, and the busy-bar
    -- rule then takes the bar's "and" of 2 and 4. Runs that end ON a beat lead into it and
    -- stay rewritten (bar 21's 36 G 42 G | 48 Y -> 40 G | 48 Y). The notes get
    -- `flourish`, so the busy-bar rule still counts the bar as whole.
    do
        local i = 1
        while i <= #events do
            if dense[i] then
                local j = i
                while dense[j + 1] and events[j + 1].qn - events[j].qn < opts.gap(events[j]) - eps do j = j + 1 end
                local first, last = events[i], events[j]
                local step = j > i and (events[i + 1].qn - first.qn) or 0
                if not Fast(first) then
                    -- At or below fast_8ths_bpm only a run lasting retime_min_run.slow of its
                    -- bar is rewritten ('auto': none); a shorter one is thinned as before -
                    -- and is NOT marked flourish, which would switch the busy-bar rule on in
                    -- a slow song (korpiklaani changed 62 bars that way in a trial).
                    if mode == 'auto'
                       or last.qn - first.qn + step < (first.bar_len or 4) * p.retime_min_run.slow - eps then
                        for k = i, j do dense[k] = nil end
                    end
                elseif j - i + 1 <= 3 and first.bar_qn and NearInt(first.bar_qn, eps)
                   and last.bar_qn and not NearInt(last.bar_qn, eps) then
                    for k = i, j do dense[k] = nil; events[k].flourish = true end
                end
                i = j + 1
            else
                i = i + 1
            end
        end
        any = false
        for k in pairs(dense) do if dense[k] then any = true; break end end
    end
    if not any then return events, {} end

    -- LONG runs: dense notes that keep going for half a bar or more (a 16th rest ends a
    -- run). Their rewrite stays inside the notes Expert plays - no slot before its first or
    -- after its last note - on one beat-aligned grid with no break where it crosses the
    -- middle of the bar (user rules, 2026-10-07: korpiklaani keys bar 26's run of 16ths from
    -- the "and" of 1 was laid out from the downbeat, a note where Expert has none; Pro Keys
    -- bars 26/32/53/55 then broke at beat 3). Short groups keep the layouts below, which
    -- the hand-reduced chronosp solo verified (bars 20-24, 162).
    local long = {}
    do
        local i = 1
        while i <= #events do
            if dense[i] then
                local j = i
                while dense[j + 1] and events[j + 1].qn - events[j].qn < opts.gap(events[j]) - eps do j = j + 1 end
                local step = j > i and (events[i + 1].qn - events[i].qn) or 0
                if events[j].qn - events[i].qn + step >= (events[i].bar_len or 4) / 2 - eps then
                    for k = i, j do long[k] = true end
                end
                i = j + 1
            else
                i = i + 1
            end
        end
    end

    local bars, order = {}, {}
    for i, ev in ipairs(events) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        local b = bars[key]
        if not b then
            b = { start = start, len = ev.bar_len or 4, idx = {} }
            bars[key] = b
            order[#order + 1] = b
        end
        b.idx[#b.idx + 1] = i
    end

    local moved, dropped, retimed_bars = {}, {}, {}
    for _, b in ipairs(order) do
        -- Spacings between neighbouring dense notes, from each dense note of this bar to the
        -- next one (which may be in the next bar).
        local spacings = {}
        for _, i in ipairs(b.idx) do
            local nx = events[i + 1]
            if dense[i] and nx and dense[i + 1] and nx.qn - events[i].qn > eps then
                spacings[#spacings + 1] = nx.qn - events[i].qn
            end
        end
        if #spacings == 0 then
            -- A lone dense note: its spacing to the dense note before it (previous bar).
            for _, i in ipairs(b.idx) do
                local pv = events[i - 1]
                if dense[i] and pv and dense[i - 1] then spacings[#spacings + 1] = events[i].qn - pv.qn end
            end
        end
        if #spacings > 0 then
            local grid = TargetGrid(spacings)
            local half = b.len / 2
            local segs = NearInt(half, eps) and { { b.start, b.start + half }, { b.start + half, b.start + b.len } }
                         or { { b.start, b.start + b.len } }
            local changed = false
            for _, seg in ipairs(segs) do
                local h0, h1 = seg[1], seg[2]
                -- Runs of dense notes between the notes that stay put.
                local runs, cur = {}, nil
                local fixed_before = nil
                for _, i in ipairs(b.idx) do
                    local ev = events[i]
                    if ev.qn >= h0 - eps and ev.qn < h1 - eps then
                        if dense[i] then
                            -- A 16th rest the run restarts after, on the 8th grid: the rest
                            -- stays, and the run starts again where Expert starts it.
                            local pv = events[i - 1]
                            local restart = grid == LADDER[5] and pv and ev.qn > h0 + eps
                                            and math.abs(ev.qn - pv.qn - 0.5) <= eps
                                            and ev.bar_qn and NearInt(ev.bar_qn * 2, eps * 2)
                            if restart then
                                if cur then cur.hi = ev.qn end
                                cur = { notes = {}, idx = {}, start_at = ev.qn }
                                runs[#runs + 1] = cur
                            elseif not cur then
                                cur = { notes = {}, idx = {}, lo = fixed_before }
                                runs[#runs + 1] = cur
                            end
                            cur.notes[#cur.notes + 1] = ev
                            cur.idx[#cur.idx + 1] = i
                        else
                            if cur then cur.hi = ev.qn end
                            cur, fixed_before = nil, ev.qn
                        end
                    end
                end
                for _, run in ipairs(runs) do
                    local last_i = run.idx[#run.idx]
                    local last, nx = events[last_i], events[last_i + 1]
                    local land = last.bar_qn and NearInt(last.bar_qn, eps)
                                 and (not nx or nx.qn - last.qn >= 1 - eps)
                    -- Notes that stay put just outside this segment also hold slots off.
                    local lo = run.lo or -math.huge
                    local hi = run.hi or math.huge
                    local first_i = run.idx[1]
                    if not run.lo and not run.start_at and events[first_i - 1] and not dense[first_i - 1] then
                        lo = events[first_i - 1].qn
                    end
                    if not run.hi and nx and not dense[last_i + 1] then hi = nx.qn end
                    -- The grid counts from the half bar's beat, or from a restart's own note.
                    -- A grid step stays free before the next half bar, whose first slot is
                    -- its beat.
                    local g0 = run.start_at or h0
                    -- A LONG run (see `long` above) - a restart after a 16th rest too - sits
                    -- on one grid aligned to the beats, between its first and last Expert
                    -- notes, laid out forward, and with no free step before the next half
                    -- bar while it carries on into it: no break in the middle of a run.
                    -- Expert's first note drops when it falls between grid points (bar 55 of
                    -- korpiklaani's Pro Keys: 12-72 -> 16 24 32 40 48 56 64 72, the user's
                    -- drawing; chronosp's riff 12-90 -> 16 24 32 40 | 48, its hand reduction).
                    local is_long = long[run.idx[1]]
                    local late_long = is_long and run.notes[1].qn > h0 + eps
                    if is_long then g0 = h0 end
                    local carries = is_long and events[last_i + 1] and dense[last_i + 1]
                                    and events[last_i + 1].qn >= h1 - eps
                    local slots, anchor = {}, false
                    -- A group that runs straight into the next half bar's beat (beat 3, or
                    -- the next bar's downbeat) leads into it: its grid counts back from that
                    -- beat, so a group cut to one note keeps the one that hammers into the
                    -- beat (36 G 42 G | 48 Y -> 40 G | 48 Y). From the user's hand reduction
                    -- of chronosp_brutal_decay bars 21/23. A run that starts on its own beat
                    -- keeps the forward grid - on a whole half bar both give the same slots.
                    local joins = nx and math.abs(nx.qn - h1) <= eps
                                  and nx.qn - last.qn < opts.gap(last) - eps
                    if joins and math.abs(run.notes[1].qn - h0) > eps and not late_long then
                        local floor = math.max(h0, run.start_at or (lo + grid))
                        local k = 1
                        while h1 - k * grid >= floor - eps do
                            table.insert(slots, 1, h1 - k * grid)
                            k = k + 1
                        end
                    else
                        for k = 0, math.floor((h1 - g0) / grid + eps) do
                            local s = g0 + k * grid
                            if (s <= h1 - grid + eps or (carries and s < h1 - eps))
                               and s >= lo + grid - eps and s <= hi - grid + eps
                               and not (land and s > last.qn + eps)
                               and not (is_long and (s < run.notes[1].qn - eps or s > last.qn + eps)) then
                                slots[#slots + 1] = s
                            end
                        end
                        anchor = math.abs(run.notes[1].qn - g0) <= eps and slots[1]
                                 and math.abs(slots[1] - g0) <= eps
                    end
                    local kept = {}
                    for _, a in ipairs(Assign(run.notes, slots, anchor, p.retime_color_penalty)) do
                        local i = run.idx[a.note]
                        kept[i] = slots[a.slot]
                    end
                    for _, i in ipairs(run.idx) do
                        if kept[i] then
                            moved[i] = kept[i]
                            if math.abs(kept[i] - events[i].qn) > eps / 4 then changed = true end
                        else
                            dropped[i], changed = true, true
                        end
                    end
                end
            end
            if changed then retimed_bars[#retimed_bars + 1] = { start = b.start, grid = grid } end
        end
    end

    local out = {}
    for i, ev in ipairs(events) do
        if not dropped[i] then
            if moved[i] then
                local qn = moved[i]
                local bar_s = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
                out[#out + 1] = { qn = qn, qn_e = qn + (ev.qn_e - ev.qn), offs = ev.offs, bpm = ev.bpm,
                                  bar_qn = qn - bar_s, bar_len = ev.bar_len,
                                  down = math.abs(qn - bar_s) <= eps, retimed = true,
                                  hopo = ev.hopo }
            else
                out[#out + 1] = ev
            end
        end
    end
    table.sort(out, function(a, c) return a.qn < c.qn end)

    -- A beat Expert plays that the rewrite left empty: the rewritten note nearest to it,
    -- within a 16th, records the beat (beat_qn), so Medium and Easy - which play the
    -- beats - can put it back there (chronosp bar 20: beat 4 sat empty on Hard, the G that
    -- replaced it at 76/24, and Medium left a long pause). Expert's own color on that beat
    -- wins a tie, then the nearer note, then the earlier.
    local function Key(qn) return ('%.3f'):format(qn) end
    local expert_at, on = {}, {}
    for _, ev in ipairs(events) do expert_at[Key(ev.qn)] = ev end
    for _, ev in ipairs(out) do on[Key(ev.qn)] = true end
    local best = {}
    for _, ev in ipairs(out) do
        if ev.retimed and ev.bar_qn then
            local beat = ev.qn - ev.bar_qn + math.floor(ev.bar_qn + 0.5)
            local d = math.abs(ev.qn - beat)
            local x = expert_at[Key(beat)]
            if d > eps and d <= 0.25 + eps and x and not on[Key(beat)] then
                local same = table.concat(ev.offs, ',') == table.concat(x.offs, ',') and 1 or 0
                local b = best[Key(beat)]
                if not b or same > b.same or (same == b.same and d < b.d - eps / 4) then
                    best[Key(beat)] = { ev = ev, beat = beat, same = same, d = d }
                end
            end
        end
    end
    for _, b in pairs(best) do b.ev.beat_qn = b.beat end
    return out, retimed_bars
end
