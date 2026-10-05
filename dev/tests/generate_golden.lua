-- Golden-chart tests for Difficulty > Generate.
--
-- dev/tests/golden/ (gitignored - the files are the author's own charts) holds MIDI files
-- whose Hard, Medium and Easy were generated and then checked by hand as correct. For
-- every Guitar, Bass and Keys part in each file, this runs the planner on the file's
-- Expert exactly as the "Hard > Medium > Easy" button would (each tier from the one just
-- generated, Auto options) and compares the result with the verified tiers.
--
-- A failure means a rule change altered a chart someone already approved. Then either the
-- change is right - regenerate the song, check it, and replace the golden file - or the
-- rule is reworked so the verified song stays as it was.
--
-- Rhythm (which notes exist), colors and lengths are compared and reported separately, so
-- a color-only change is easy to tell from a rhythm change.
--
-- Requires (globals): Test, r, GOLDEN_DIR, SmfReadFile, SmfFindTrack, SmfNotesInRange,
--   SmfSongTiming, SmfTierEvents, Gen5PlanTier, Gen5MarkHopos, Gen5ForceHopoSpans.

-- Parts compared. verify = false lists a part Generate cannot build yet: it is reported as
-- skipped, never failed. Flip it to true once that instrument's planner is ready.
local PARTS = {
    { track = 'PART GUITAR',      kind = 'gb', label = 'Guitar',   verify = true  },
    { track = 'PART BASS',        kind = 'gb', label = 'Bass',     verify = true  },
    { track = 'PART KEYS',        kind = 'k5', label = 'Keys',     verify = true  },
    { track = 'PART DRUMS',                    label = 'Drums',    verify = false },
    { track = 'PART REAL_KEYS_X',              label = 'Pro Keys', verify = false },
}
local LO        = { X = 96, H = 84, M = 72, E = 60 }
local ONSET_TOL = 0.005  -- QN: under one tick at 480 PPQ apart counts as the same onset
local LEN_TOL   = 0.006  -- QN: the action rounds lengths to the take's ticks on write
local MAX_LINES = 10     -- differences listed per tier (all are counted)
local COLORS    = { [0] = 'G', 'R', 'Y', 'B', 'O' }

local function ListMidi(dir)
    local out = {}
    if reaper and reaper.EnumerateFiles then
        local i = 0
        while true do
            local f = reaper.EnumerateFiles(dir, i)
            if type(f) ~= 'string' then break end
            if f:lower():match('%.mid$') then out[#out + 1] = f end
            i = i + 1
        end
    else
        local pipe = io.popen(('dir /b "%s" 2>nul'):format(dir:gsub('/', '\\')))
        if pipe then
            for f in pipe:lines() do
                if f:lower():match('%.mid$') then out[#out + 1] = f end
            end
            pipe:close()
        end
    end
    table.sort(out)
    return out
end

-- The same-difficulty Pro Keys chart Keys follows in REAPER (auto-detected by name at
-- startup), as { { qn, qn_e }... }, or nil. Mirrors ReadProKeysEvents: playable range
-- 48-72, lane-shift markers excluded, chords grouped.
local function ProKeysGuide(song, dl)
    local trk = SmfFindTrack(song, 'PART REAL_KEYS_' .. dl)
    if not trk then return nil end
    local notes = SmfNotesInRange(trk, 48, 72)
    if #notes == 0 then return nil end
    local guide, tpqn, tol = {}, song.tpqn, song.tpqn / 96
    local i = 1
    while i <= #notes do
        local ev = { qn = notes[i].tick / tpqn, qn_e = (notes[i].tick + notes[i].len) / tpqn }
        local j = i + 1
        while j <= #notes and notes[j].tick - notes[i].tick <= tol do
            ev.qn_e = math.max(ev.qn_e, (notes[j].tick + notes[j].len) / tpqn)
            j = j + 1
        end
        guide[#guide + 1] = ev
        i = j
    end
    return guide
end

-- One marker pitch's notes as spans { { qn, qn_e }... }.
local function MarkerSpans(trk, pitch, tpqn)
    local out = {}
    for _, n in ipairs(SmfNotesInRange(trk, pitch, pitch)) do
        out[#out + 1] = { qn = n.tick / tpqn, qn_e = (n.tick + n.len) / tpqn }
    end
    return out
end

-- Guitar/Bass Hard force-HOPO markers (lo + 5), generated vs verified: start and end of
-- every span. Returns a list of difference lines.
local function CompareHopo(gen_spans, want_spans, song, timing)
    local function Where(qn)
        local tick = math.floor(qn * song.tpqn + 0.5)
        return ('bar %d beat %g'):format(timing.BarNumber(tick), math.floor((timing.BarPos(tick) + 1) * 100 + 0.5) / 100)
    end
    local function List(spans)
        local out = {}
        for _, sp in ipairs(spans) do out[#out + 1] = Where(sp.qn) .. ' to ' .. Where(sp.qn_e) end
        return out
    end
    local g, w, lines = List(gen_spans), List(want_spans), {}
    local i, j = 1, 1
    while i <= #g or j <= #w do
        if g[i] == w[j] then
            i, j = i + 1, j + 1
        elseif w[j] and (not g[i] or gen_spans[i].qn > want_spans[j].qn + 0.005) then
            lines[#lines + 1] = 'verified marker ' .. w[j] .. ' not generated'; j = j + 1
        else
            lines[#lines + 1] = 'generated marker ' .. g[i] .. ' not in the verified chart'; i = i + 1
        end
    end
    return lines
end

local function Shape(offs)
    local s = {}
    for _, o in ipairs(offs) do s[#s + 1] = COLORS[o] or '?' end
    return table.concat(s)
end

-- Compare generated tier `gen` with the verified tier `want`. Returns (counts, lines).
local function Compare(gen, want, song, timing)
    local counts = { missing = 0, extra = 0, color = 0, length = 0 }
    local lines = {}
    local function Where(qn)
        local tick = math.floor(qn * song.tpqn + 0.5)
        local bar_qn = timing.BarPos(tick)
        return ('bar %d beat %g'):format(timing.BarNumber(tick), math.floor((bar_qn + 1) * 100 + 0.5) / 100)
    end
    local function Add(text)
        if #lines < MAX_LINES then lines[#lines + 1] = text end
    end
    local i, j = 1, 1
    while i <= #gen or j <= #want do
        local g, w = gen[i], want[j]
        if g and w and math.abs(g.qn - w.qn) <= ONSET_TOL then
            if Shape(g.offs) ~= Shape(w.offs) then
                counts.color = counts.color + 1
                Add(('%s: color %s, verified %s'):format(Where(w.qn), Shape(g.offs), Shape(w.offs)))
            end
            local gl, wl = g.qn_e - g.qn, w.qn_e - w.qn
            if math.abs(gl - wl) > LEN_TOL then
                counts.length = counts.length + 1
                Add(('%s: length %.3f QN, verified %.3f'):format(Where(w.qn), gl, wl))
            end
            i, j = i + 1, j + 1
        elseif w and (not g or w.qn < g.qn) then
            counts.missing = counts.missing + 1
            Add(('%s: verified note %s not generated'):format(Where(w.qn), Shape(w.offs)))
            j = j + 1
        else
            counts.extra = counts.extra + 1
            Add(('%s: generated %s, not in the verified chart'):format(Where(g.qn), Shape(g.offs)))
            i = i + 1
        end
    end
    return counts, lines
end

local files = ListMidi(GOLDEN_DIR)
if #files == 0 then
    r.ShowConsoleMsg('  (no golden charts in dev/tests/golden/ - nothing to compare)\n')
end

for _, name in ipairs(files) do
    Test.section('Golden: ' .. name)
    local song = SmfReadFile(GOLDEN_DIR .. name)
    if not song then
        Test.it(name .. ' reads', function() Test.expect(false, 'could not parse ' .. name) end)
    else
        local timing = SmfSongTiming(song)
        -- Bass and Keys follow Guitar, as the action does: Guitar's Hard planned from its
        -- Expert (busy bars) and its Medium from that Hard (rhythm), in memory.
        local refs = {}
        local gtr = SmfFindTrack(song, 'PART GUITAR')
        if gtr then
            local gx = SmfTierEvents(gtr, LO.X, song.tpqn, timing, { skip_zero = true })
            if #gx > 0 then
                local gh, hlog = Gen5PlanTier('gb', 'H', gx)
                refs.H = hlog.busy_bars
                refs.M = select(2, Gen5PlanTier('gb', 'M', gh)).rhythm_bars
            end
        end
        for _, part in ipairs(PARTS) do
            local trk = SmfFindTrack(song, part.track)
            if trk and not part.verify then
                r.ShowConsoleMsg(('  SKIP  %s: no Generate planner yet\n'):format(part.label))
            elseif trk then
                -- Zero-length notes are skipped, as the REAPER action skips them.
                local upper = SmfTierEvents(trk, LO.X, song.tpqn, timing, { skip_zero = true })
                -- Guitar/Bass: which Expert notes hammer on, for Hard's force-HOPO markers.
                if part.kind == 'gb' then
                    Gen5MarkHopos(upper, MarkerSpans(trk, LO.X + 5, song.tpqn), MarkerSpans(trk, LO.X + 6, song.tpqn))
                end
                if #upper == 0 then
                    r.ShowConsoleMsg(('  SKIP  %s: no Expert notes\n'):format(part.label))
                else
                    for _, dl in ipairs({ 'H', 'M', 'E' }) do
                        local guide = part.kind == 'k5' and ProKeysGuide(song, dl) or nil
                        local follower = part.track ~= 'PART GUITAR'
                        local gen = Gen5PlanTier(part.kind, dl, upper, { guide = guide,
                            busy_ref   = follower and dl == 'H' and refs.H or nil,
                            rhythm_ref = follower and dl == 'M' and refs.M or nil })
                        local want = SmfTierEvents(trk, LO[dl], song.tpqn, timing)
                        Test.it(('%s %s'):format(part.label, ({ H = 'Hard', M = 'Medium', E = 'Easy' })[dl]), function()
                            local c, lines = Compare(gen, want, song, timing)
                            local total = c.missing + c.extra + c.color + c.length
                            Test.expect(total == 0, ('%d differences - rhythm: %d missing, %d extra; colors: %d; lengths: %d\n           %s')
                                :format(total, c.missing, c.extra, c.color, c.length, table.concat(lines, '\n           ')))
                        end)
                        if part.kind == 'gb' and dl == 'H' then
                            Test.it(part.label .. ' Hard force-HOPO markers', function()
                                local lines = CompareHopo(Gen5ForceHopoSpans(gen),
                                    MarkerSpans(trk, LO.H + 5, song.tpqn), song, timing)
                                Test.expect(#lines == 0, ('%d differences\n           %s'):format(#lines,
                                    table.concat(lines, '\n           ', 1, math.min(#lines, MAX_LINES))))
                            end)
                        end
                        upper = gen  -- the chain: the next tier is built from this one
                    end
                end
            end
        end
    end
end
