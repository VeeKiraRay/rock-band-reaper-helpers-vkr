-- Difficulty > Generate: Drums. Builds Hard, Medium or Easy from the tier above.
--
-- PURE: no r, no S. Load after difficulty_generate_retime.lua and
-- actions_difficulty_drums_checks.lua (it reads DRUMS_RULES at call time, so Validate
-- and Generate share one set of thresholds).
--
-- What each rule does and why - its source (RBN doc, official charts, user rule) and the
-- measured numbers - is in docs/difficulty_reduction.md, "Drums". Keep the two in step.
--
-- Drums are reduced limb by limb, not by the band's one-rhythm model
-- (difficulty_generate_rhythm.lua): each limb thins on its own terms. Rules delete or
-- relane notes and never move one - except Hard's fast-run rewrite of fills.
--
-- Input event: { qn, qn_e, offs, bpm, bar_qn, bar_len, pulse, down }, offs the gem
-- offsets 0 Kick, 1 Red (snare), 2 Yellow, 3 Blue, 4 Green, ascending.
-- opts:
--   fast_runs  'rewrite' | 'auto' | 'thin' (Hard only; GEN5_PARAMS.fast_runs_default)
--   unflip     the tier that un-flips Expert's disco beats ('H' default, 'none')
--   between    Medium kick/snare between hi-hat notes: 'beats' (default) | 'none' | 'keep'
--   eighth_hands  Medium/Easy at fast tempos, which of three hand hits an 8th apart goes:
--              'hands' (default) | 'beats'. See LowerEighthHands.
--   expert     Medium/Easy: the Expert events, for fills Hard's rewrite moved off the 8th
--              grid (ExpertForRewrittenRuns). nil = plan from the tier above only.
--   keep_kicks the kicks are already this tier's (Drums 2X): skip the kick-choosing rules
--   ctx        { fills, rolls, disco = { { qn, qn_e }... }, toms = { [2|3|4] = spans },
--                sections = { { qn, name }... }, song_bpm } - all optional, in quarter notes;
--                a roll span from a special roll lane (127) carries two = true, and every
--                roll span its marker's vel (GenKeepHardLanes: 41-50 = Hard plays Expert's)

local EPS = GEN5_EPS
-- Roll lane membership: Validate takes the notes from 1 ms before the lane's start to 1 ms
-- after its end (seconds). 0.004 QN is 1 ms at 240 BPM, so a note the planner counts in a
-- roll is one Validate counts too, at any song tempo.
local ROLL_TOL = 0.004
local KICK, SNARE, YEL, BLU, GRN = 0, 1, 2, 3, 4

-- The planner's own thresholds (the RBN tempo rules shared with Validate are DRUMS_RULES).
-- Tempos in BPM, spacings in quarter notes. nil turns a rule off where noted.
GEN_DRUMS_PARAMS = {
    -- Hard: a tom/snare 16th run stays at full speed when it lasts at most this many beats.
    hard_run_beats = 2,
    -- Hard below 140 BPM: this many tom/snare 16ths in a row make a run; a lone 16th snare
    -- stays on the "a" and goes on the "e" (HardSixteenths).
    hard_16th_min_run = 2,
    -- Hard kick spacing: two kicks at least this far apart ...
    hard_kick_gap = 0.5,
    -- ... an off-beat kick (8th or 16th position) this far, and every kick from _fast_bpm.
    hard_kick_gap_8th = 0.75,
    hard_kick_gap_fast_bpm = 140,
    hard_kick_gap_fast = 0.75,
    -- Drop the kick under a snare (off the bar line)? Per tier; off on both.
    kick_under_snare = { H = false, M = false },
    -- Medium/Easy kick spacing: a quarter note, half a bar from _fast_bpm ...
    lower_kick_gap = 1.0,
    lower_kick_gap_fast_bpm = 140,
    lower_kick_gap_fast = 2.0,
    -- ... and half a bar when the hands are busy around the kick (an 8th before and after).
    lower_kick_gap_busy = 2.0,
    -- Hard: half a bar between kicks under busy hands (BusyHands). nil = off.
    hard_kick_gap_busy = 2.0,
    -- Hard: the bar's last-beat kick comes back when the spacing removed it (EndOfBarKick).
    hard_end_of_bar_kick = true,
    -- Hard: one 8th kick paired with beat 3's kick comes back (PairedKick).
    hard_paired_kick = true,
    -- Hard: Expert's kicks and hands both on every 8th -> a kick on every beat (HardEighthKicks).
    hard_eighth_kicks = true,
    -- Hard drops hat-only "and"s in steady 8th-hat bars per "Hard 8th runs" (HardHatDrops):
    -- 'always' (every such bar), 'fallback' (only when Hard would keep more than
    -- hard_fallback_keep of Expert's notes), 'off'.
    hard_hat_drop = 'fallback',
    hard_fallback_keep = 0.95,
    -- Medium/Easy hi-hat/ride stream to quarter notes from this tempo (nil:
    -- DRUMS_RULES.general_medium_8th_bpm).
    lower_hat_quarter_bpm = 130,
    -- Medium keeping more than this share of Hard's gems puts its hi-hat/ride on quarter
    -- notes at any tempo, in songs whose median tempo is _bpm or more (GenDrumsPlanTier).
    medium_fallback_keep = 0.93,
    medium_fallback_bpm = 120,
    medium_fallback_on = 'hands',   -- what the share counts: 'hands' (every gem but the kick) | 'notes'
    -- Medium: the gems an 8th after a crash accent go from this tempo (AfterCrash) ...
    after_crash_bpm = 120,
    -- ... and the snare too from this one. nil = off.
    after_crash_snare_bpm = 140,
    -- Medium plays a roll lane as 8ths below this tempo, as quarters from it.
    medium_roll_8th_bpm = 120,
    -- Medium: a two-hand hit with a tom plays one gem from this tempo (MediumTomPairs). nil = off.
    medium_tom_pair_bpm = 140,
    -- ... except in a sparse bar.
    medium_tom_pair_sparse_keep = true,
    -- Medium/Easy: a cymbal change an 8th apart loses a hi-hat/ride (CymbalChanges).
    lower_cymbal_change = true,
    -- Easy: the same at a quarter note, from this tempo, for a hi-hat/ride between two hits
    -- on other cymbals (CymbalChangesQuarter). nil = off.
    easy_cymbal_change_quarter_bpm = 170,
    -- Easy: a verse plays kick + snare when its kick/snare hits come at least this often per
    -- quarter note (EasyBeats).
    easy_ks_min_density = 0.5,
    -- Easy: a lone drum "and" between two beat hits goes from this tempo (EasyLoneAnds). nil = off.
    easy_lone_and_bpm = 140,
    -- Easy two-hand bar: a half bar with no hand hit keeps its kicks.
    easy_quiet_half_kicks = true,
    -- Medium/Easy: no three hand hits in a row an 8th apart from this tempo (LowerEighthHands).
    lower_eighth_hands_bpm = { M = 150, E = 140 },
    -- Easy: no pair of hand hits an 8th apart either, from this tempo. nil = off.
    easy_no_pairs_bpm = 170,
    -- Which of the three goes: 'hands' | 'beats' ("Drums fast 8ths").
    lower_eighth_hands_default = 'hands',
    -- Easy: a bar with the backbeat on the "and"s plays the hands on the "and"s from this
    -- tempo (HardAndBackbeat). nil = off.
    easy_and_backbeat_bpm = 110,
    -- Easy: a run of _min+ hand hits an 8th apart, each with a snare, keeps only the beats
    -- from this tempo (SnareRuns). nil = off.
    easy_snare_run_bpm = 120,
    easy_snare_run_min = 5,
    -- Medium: the same from this tempo (official thins them on Medium too). nil = off.
    medium_snare_run_bpm = nil,
    -- Easy: a two-hand hit an 8th before a crash loses its hi-hat/ride (EasyBeforeCrash).
    easy_before_crash = true,
    -- Easy's quarter-note fills: 'more' (the beats or the "and"s, whichever keeps more of
    -- the fill) | 'beats' (always the beats). See GridFillRuns.
    easy_fill_phase = 'more',
}

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

-- On a grid of g quarter notes, counted from the bar line.
local function OnGrid(ev, g)
    return NearInt((ev.bar_qn or ev.qn) / g, EPS / g)
end

-- On the beat (or the bar line), in the bar's own pulse.
local function OnBeat(ev)
    return ev.down or NearInt((ev.bar_qn or ev.qn) / (ev.pulse or 1), EPS)
end

local function In(spans, qn)
    if not spans then return nil end
    for _, s in ipairs(spans) do
        if qn >= s.qn - EPS and qn < s.qn_e - EPS then return s end
    end
    return nil
end

local function Has(ev, o)
    for _, x in ipairs(ev.offs) do if x == o then return true end end
    return false
end

local function Drop(ev, o)
    for i, x in ipairs(ev.offs) do
        if x == o then table.remove(ev.offs, i); return true end
    end
    return false
end

local function Add(ev, o)
    if Has(ev, o) then return end
    ev.offs[#ev.offs + 1] = o
    table.sort(ev.offs)
end

-- A Yellow/Blue/Green gem that shows as a cymbal (no Pro Drums tom marker over it).
local function IsCymbal(ev, o) return o >= YEL and not (ev.tom and ev.tom[o]) end
local function IsTom(ev, o) return o >= YEL and ev.tom and ev.tom[o] end

local function HasCymbal(ev)
    for _, o in ipairs(ev.offs) do if IsCymbal(ev, o) then return true end end
    return false
end

-- A fill-like onset: hands on the snare and toms only, no cymbal (a tom run, a snare
-- roll). By content, never by fill lane (a lane marks where overdrive can be activated).
local function FillLike(ev)
    if HasCymbal(ev) then return false end
    for _, o in ipairs(ev.offs) do
        if o == SNARE or IsTom(ev, o) then return true end
    end
    return false
end

local function Copy(ev)
    local c = {}
    for k, v in pairs(ev) do c[k] = v end
    c.offs = {}
    for i, o in ipairs(ev.offs) do c.offs[i] = o end
    return c
end

local function Compact(evs)
    local out = {}
    for _, ev in ipairs(evs) do if #ev.offs > 0 then out[#out + 1] = ev end end
    return out
end

-- The marker context of one event: fill, roll, disco, tom. Recomputed for events the
-- retime pass moved (it builds them afresh, without these fields).
local function Mark(ev, ctx)
    ev.fill  = In(ctx.fills, ev.qn) and true or nil
    -- A roll includes the note on its lane's end: the lane ends where the last hit is,
    -- and Validate counts that hit (even count, density).
    ev.roll  = nil
    for _, sp in ipairs(ctx.rolls or {}) do
        if ev.qn >= sp.qn - ROLL_TOL and ev.qn <= sp.qn_e + ROLL_TOL then ev.roll = sp; break end
    end
    ev.disco = In(ctx.disco, ev.qn) and true or nil
    if ctx.toms then
        ev.tom = {}
        for o = YEL, GRN do ev.tom[o] = In(ctx.toms[o], ev.qn) and true or nil end
    end
end

-- Medium/Easy below a fill Hard rewrote: Medium's 8th grid finds nothing of an 8th-triplet
-- rewrite but the beats, so the fill is taken from Expert instead. A Hard note with no
-- Expert note at its position was moved by the rewrite; each run of moved notes holding one
-- off the 8th grid is replaced by Expert's notes between the run's neighbours, which the
-- tier then reduces like any fill. Read from Expert (not kept from Hard's run) so a
-- Medium-only run, Hard read from the track, does the same. `expert`: nil = off. Returns
-- the new list and the number of bars with a run replaced.
local function ExpertForRewrittenRuns(events, expert)
    if not expert or #expert == 0 then return events, 0 end
    local function Key(qn) return math.floor(qn * 960 + 0.5) end
    local at = {}
    for _, x in ipairs(expert) do at[Key(x.qn)] = true end
    local function Moved(ev) return not at[Key(ev.qn)] end
    local out, bars, n, i = {}, {}, 0, 1
    while i <= #events do
        if Moved(events[i]) then
            local j = i
            while j < #events and Moved(events[j + 1]) do j = j + 1 end
            local off = false
            for k = i, j do if not OnGrid(events[k], 0.5) then off = true end end
            if off then
                local lo = events[i - 1] and events[i - 1].qn or -math.huge
                local hi = events[j + 1] and events[j + 1].qn or math.huge
                for _, x in ipairs(expert) do
                    if x.qn > lo + EPS and x.qn < hi - EPS then out[#out + 1] = Copy(x) end
                end
                local bar = ('%.3f'):format(events[i].qn - (events[i].bar_qn or 0))
                if not bars[bar] then bars[bar] = true; n = n + 1 end
            else
                for k = i, j do out[#out + 1] = events[k] end
            end
            i = j + 1
        else
            out[#out + 1] = events[i]
            i = i + 1
        end
    end
    return out, n
end

-- The tempo for a once-per-song decision (Easy's quarter-note fills): the faster of the
-- tempo at bar 1 (ctx.song_bpm, where a song's authored tempo is set) and the first note's -
-- a live tempo map can start the drums a fraction under a threshold. The faster one only,
-- so Generate is never looser than Validate, which reads each note's tempo.
local function SongTempo(evs, ctx)
    local first = evs[1] and evs[1].bpm or 120
    local song = ctx and ctx.song_bpm
    return song and song > first and song or first
end

-- Fresh copies carrying the marker context.
local function Annotate(events, ctx)
    local out = {}
    for i, ev in ipairs(events) do
        local c = Copy(ev)
        Mark(c, ctx)
        out[i] = c
    end
    return out
end

-- Weighted interval scheduling: the highest-weight subset of list whose neighbours are at
-- least gap(ev, earlier) apart - the later one's gap, which may depend on the earlier one
-- it is measured against. Returns a set of kept list indexes.
local function KeepByGap(list, gap, weight)
    local n = #list
    local best, take, prev = { [0] = 0 }, {}, {}
    for i = 1, n do
        local j = i - 1
        while j >= 1 and list[i].qn - list[j].qn < gap(list[i], list[j]) - EPS do j = j - 1 end
        prev[i] = j
        local with = weight(list[i]) + best[j]
        if with > best[i - 1] then best[i], take[i] = with, true
        else best[i], take[i] = best[i - 1], false end
    end
    local keep, i = {}, n
    while i >= 1 do
        if take[i] then keep[i] = true; i = prev[i] else i = i - 1 end
    end
    return keep
end

local CLASS_W = { down = 8, beat = 5, ['8th'] = 3, trip = 2, ['16th'] = 1.5, other = 1 }

----------------------------------------------------------------------
-- Disco flip
----------------------------------------------------------------------

-- Expert's disco-flip sections back to a normal beat: inside Expert's [mix 3 drumsNd] spans
-- Red is the hi-hat and Yellow the snare; the hi-hat goes back on Yellow (8ths only), the
-- snare on Red with a hi-hat above it. Hard un-flips unless opts.unflip names another tier.
local function Unflip(evs, log)
    for _, ev in ipairs(evs) do
        if ev.disco then
            local hat, snare = Has(ev, SNARE), Has(ev, YEL)
            Drop(ev, SNARE); Drop(ev, YEL)
            if hat and OnGrid(ev, 0.5) then Add(ev, YEL) end
            if snare then
                Add(ev, SNARE)
                if OnGrid(ev, 0.5) then Add(ev, YEL) end
            end
            log.unflipped = log.unflipped + 1
        end
    end
    return Compact(evs)
end

----------------------------------------------------------------------
-- Roll lanes
----------------------------------------------------------------------

local function RollGrid(dl, bpm)
    local R, P = DRUMS_RULES, GEN_DRUMS_PARAMS
    if dl == 'H' then return bpm < R.roll_hard_16th_bpm and 0.25 or 0.5 end
    if dl == 'M' then return bpm < P.medium_roll_8th_bpm and 0.5 or 1.0 end
    return 1.0
end

-- The notes under each roll lane, played on the tier's grid: the ones on it (or one per
-- grid step when the roll is off the grid, e.g. in triplets), at least two, and an even
-- number of gems (Validate's rules). They are marked `rolled` and later steps leave them.
local function Rolls(evs, dl, log)
    local groups, order = {}, {}
    for i, ev in ipairs(evs) do
        if ev.roll then
            local g = groups[ev.roll]
            if not g then g = {}; groups[ev.roll] = g; order[#order + 1] = ev.roll end
            g[#g + 1] = i
        end
    end
    for _, span in ipairs(order) do
        local idx = groups[span]
        local grid = RollGrid(dl, evs[idx[1]].bpm or 120)
        local keep, last = {}, nil
        for _, i in ipairs(idx) do
            if OnGrid(evs[i], grid) and (not last or evs[i].qn - evs[last].qn >= grid - EPS) then
                keep[#keep + 1] = i; last = i
            end
        end
        if #keep < 2 then
            keep, last = {}, nil
            for _, i in ipairs(idx) do
                if not last or evs[i].qn - evs[last].qn >= grid - EPS then keep[#keep + 1] = i; last = i end
            end
        end
        -- A special roll (127: a swell split between two pads) is one pad below Expert: the
        -- higher of the lane's pads (Green over Blue over Yellow), on every kept grid step,
        -- whichever pad the upper tier had there. The lane marks the sound, not exact hits.
        if span.two then
            local top = 0
            for _, i in ipairs(idx) do
                for _, o in ipairs(evs[i].offs) do if o ~= KICK and o > top then top = o end end
            end
            if top > 0 then
                for _, i in ipairs(keep) do
                    local ev = evs[i]
                    local kick = Has(ev, KICK)
                    ev.offs = kick and { KICK, top } or { top }
                end
            end
        end
        local gems = 0
        for _, i in ipairs(keep) do gems = gems + #evs[i].offs end
        -- An even number of hits: trim the start, so the roll still lands where Expert's does.
        while gems % 2 == 1 and #keep > 2 do
            gems = gems - #evs[keep[1]].offs
            table.remove(keep, 1)
        end
        -- Still odd: a kick in a roll chord goes; else a roll left with one hit gets the
        -- nearest note it dropped back.
        if gems % 2 == 1 then
            for _, i in ipairs(keep) do
                if #evs[i].offs > 1 and Drop(evs[i], KICK) then gems = gems - 1; break end
            end
        end
        if gems % 2 == 1 and #keep == 1 then
            local k0, best = keep[1], nil
            for _, i in ipairs(idx) do
                local d = math.abs(evs[i].qn - evs[k0].qn)
                if i ~= k0 and #evs[i].offs == 1 and d >= grid - EPS
                   and (not best or d < math.abs(evs[best].qn - evs[k0].qn)) then
                    best = i
                end
            end
            if best then
                keep[#keep + 1] = best
                table.sort(keep)
            elseif #evs[k0].offs == 1 then
                -- Nothing a grid step away: a roll of one hit is no roll.
                keep = {}
            end
        end
        local kept = {}
        for _, i in ipairs(keep) do kept[i] = true; evs[i].rolled = true end
        for _, i in ipairs(idx) do if not kept[i] then evs[i].offs = {} end end
        log.rolls = log.rolls + 1
    end
    return Compact(evs)
end

----------------------------------------------------------------------
-- Fills and runs
----------------------------------------------------------------------

-- Runs of fill-like onsets (toms/snare, no cymbal, not under a roll lane) at least
-- min_len (default 3) long, each within `step` of the next. Returns { { first, last }... }
-- index pairs.
local function FillRuns(evs, step, min_len)
    local runs, i = {}, 1
    while i <= #evs do
        if FillLike(evs[i]) and not evs[i].rolled then
            local j = i
            while j < #evs and FillLike(evs[j + 1]) and not evs[j + 1].rolled
                  and evs[j + 1].qn - evs[j].qn <= step + EPS do
                j = j + 1
            end
            if j - i + 1 >= (min_len or 3) then runs[#runs + 1] = { i, j } end
            i = j + 1
        else
            i = i + 1
        end
    end
    return runs
end

-- Tom markers over a rewritten run. Pro Drums tom markers (110-112) are shared by every
-- tier and often sit exactly on Expert's tom notes, so a tom the rewrite moved would fall
-- off its marker and show as a cymbal. For every color with a tom the rewrite moved (even
-- one its old marker still covers, so the result points at it), the markers in the run are
-- replaced by one marker over the whole run, grown over any marker reaching into it. A
-- marker already exactly that span is left alone. A fill run holds no cymbal, so this never
-- turns the run's own notes into toms; a cymbal of that color elsewhere under the new
-- marker - the tier above, or a tier this run does not write (opts.keep_cymbals) - would,
-- so that run is thinned instead and listed in the result.
local TOM_MARKER_TAIL = 0.125   -- the new marker ends a 32nd after the run's last note

-- The new markers one run needs, for the colors in need: { { o, qn, qn_e,
-- replaces = { old spans } }... }.
local function RunTomMarkers(run_s, run_e, ctx, need)
    local out = {}
    for o = YEL, GRN do
        local spans = ctx.toms and ctx.toms[o] or {}
        local s, e = run_s, run_e + TOM_MARKER_TAIL
        local used, replaces, grew = {}, {}, true
        while grew do
            grew = false
            for k, sp in ipairs(spans) do
                if not used[k] and sp.qn < e - EPS and sp.qn_e > s + EPS then
                    used[k] = true
                    replaces[#replaces + 1] = sp
                    if sp.qn < s then s = sp.qn; grew = true end
                    if sp.qn_e > e then e = sp.qn_e; grew = true end
                end
            end
        end
        local same = #replaces == 1 and math.abs(replaces[1].qn - s) <= EPS and math.abs(replaces[1].qn_e - e) <= EPS
        if need[o] and #replaces > 0 and not same then
            out[#out + 1] = { o = o, qn = s, qn_e = e, replaces = replaces }
        end
    end
    return out
end

-- A cymbal of the marker's color under it: in the tier above (its markers as they are),
-- or in a tier this run leaves as it is (keep_cymbals[o]: positions in QN).
local function TomMarkerConflict(m, evs, keep_cymbals)
    for _, ev in ipairs(evs) do
        if ev.qn >= m.qn - EPS and ev.qn < m.qn_e - EPS and Has(ev, m.o) and IsCymbal(ev, m.o) then return true end
    end
    for _, qn in ipairs(keep_cymbals and keep_cymbals[m.o] or {}) do
        if qn >= m.qn - EPS and qn < m.qn_e - EPS then return true end
    end
    return false
end

-- The context with the new markers in place of the ones they replace. Markers of one
-- color from neighbouring runs that overlap become one. Returns (ctx, merged markers).
local function ApplyTomMarkers(ctx, markers)
    local by_o = {}
    for _, m in ipairs(markers) do
        by_o[m.o] = by_o[m.o] or {}
        table.insert(by_o[m.o], m)
    end
    local toms, merged = {}, {}
    for o = YEL, GRN do
        local list = by_o[o] or {}
        table.sort(list, function(a, b) return a.qn < b.qn end)
        local gone, mine = {}, {}
        for _, m in ipairs(list) do
            local last = mine[#mine]
            if last and m.qn < last.qn_e - EPS then
                last.qn_e = math.max(last.qn_e, m.qn_e)
                for _, sp in ipairs(m.replaces) do last.replaces[#last.replaces + 1] = sp end
                for _, b in ipairs(m.bars) do last.bars[#last.bars + 1] = b end
            else
                mine[#mine + 1] = { o = o, qn = m.qn, qn_e = m.qn_e, replaces = { table.unpack(m.replaces) },
                                    bars = { table.unpack(m.bars) } }
            end
        end
        for _, m in ipairs(mine) do
            for _, sp in ipairs(m.replaces) do gone[sp] = true end
            merged[#merged + 1] = m
        end
        local spans = {}
        for _, sp in ipairs(ctx.toms and ctx.toms[o] or {}) do if not gone[sp] then spans[#spans + 1] = sp end end
        for _, m in ipairs(mine) do spans[#spans + 1] = { qn = m.qn, qn_e = m.qn_e } end
        table.sort(spans, function(a, b) return a.qn < b.qn end)
        toms[o] = spans
    end
    local out = {}
    for k, v in pairs(ctx) do out[k] = v end
    out.toms = toms
    return out, merged
end

-- Hard: fast fill runs rewritten one grid slower (Gen5RetimeDenseRuns, the Guitar/Bass/
-- Keys rewrite and its "Hard fast runs" setting). Only tom/snare runs are offered to it -
-- grooves with cymbals are thinned by the other rules. Returns the events and the marker
-- context after the run's tom markers changed (log.tom_markers lists the new markers,
-- log.tom_conflict_bars the runs thinned instead).
local function RetimeFills(evs, mode, log, ctx, keep_cymbals)
    if (mode or GEN5_PARAMS.fast_runs_default) == 'thin' then return evs, ctx end
    local runs = {}
    -- 8th-triplet tom/snare runs from hard_trip_stream_bpm: one grid slower is 8ths, which
    -- the run breaker accepts because Expert is faster there.
    for _, run in ipairs(FillRuns(evs, 1 / 3)) do
        local a, b = run[1], run[2]
        local trip = (evs[a].bpm or 120) >= DRUMS_RULES.hard_trip_stream_bpm
        for k = a + 1, b do if math.abs(evs[k].qn - evs[k - 1].qn - 1 / 3) > EPS then trip = false end end
        if trip then runs[#runs + 1] = { a = a, b = b } end
    end
    for _, run in ipairs(FillRuns(evs, 0.25)) do
        local a, b = run[1], run[2]
        local step = evs[a + 1].qn - evs[a].qn
        -- 16ths -> 8th triplets at any tempo; 16th triplets -> 16ths only where Hard may
        -- play 16ths. Anything faster (32nds -> 16th triplets) is still too fast for Hard
        -- and is thinned instead.
        if step >= 0.25 - EPS
           or (step >= 1 / 6 - EPS and (evs[a].bpm or 120) < DRUMS_RULES.roll_hard_16th_bpm) then
            runs[#runs + 1] = { a = a, b = b }
        end
    end
    -- Rewrite; a run whose new tom marker would cover a cymbal is taken out and the rest
    -- rewritten again (the runs are independent, so this ends within #runs passes).
    local out, bars, markers
    while true do
        local any = false
        for _, ev in ipairs(evs) do ev.fill_run, ev.run_id = nil, nil end
        for k, run in ipairs(runs) do
            if not run.thinned then
                for i = run.a, run.b do evs[i].fill_run, evs[i].run_id = true, k end
                any = true
            end
        end
        if not any then out, bars, markers = evs, {}, {}; break end
        out, bars = Gen5RetimeDenseRuns(evs, {
            gap  = function(ev) return ev.fill_run and 0.5 or GEN5_MIN_LEN_QN end,
            -- A group of a mixed run never lands faster than Hard may play: 16ths below
            -- roll_hard_16th_bpm, else 8th triplets (16th triplets are too fast for Hard).
            min_grid = function(ev)
                return (ev.bpm or 120) < DRUMS_RULES.roll_hard_16th_bpm and 0.25 or 1 / 3
            end,
            -- A mixed run's groups (16ths, then 32nds, then 16ths) each one grid slower than
            -- themselves, as a run of 16ths alone would be.
            group_grid = 'own',
            eps  = EPS, mode = mode })
        -- The runs that moved a tom (need[o]: its color), over Expert's span and the
        -- rewritten notes.
        local moved = {}
        for _, ev in ipairs(out) do
            local id = ev.retimed and ev.src and ev.src.run_id
            if id and math.abs(ev.qn - ev.src.qn) > EPS then
                for _, o in ipairs(ev.offs) do
                    if IsTom(ev.src, o) then
                        local run = runs[id]
                        local m = moved[id] or { s = evs[run.a].qn, e = evs[run.b].qn, need = {} }
                        moved[id] = m
                        m.need[o] = true
                    end
                end
            end
        end
        for _, ev in ipairs(out) do
            local m = ev.retimed and ev.src and moved[ev.src.run_id]
            if m then m.s, m.e = math.min(m.s, ev.qn), math.max(m.e, ev.qn) end
        end
        markers = {}
        local conflict = false
        for id, m in pairs(moved) do
            local first = evs[runs[id].a]
            local bar = first.qn - (first.bar_qn or 0)
            for _, mk in ipairs(RunTomMarkers(m.s, m.e, ctx, m.need)) do
                if TomMarkerConflict(mk, evs, keep_cymbals) then
                    runs[id].thinned, conflict = bar, true
                    break
                end
                mk.bars = { bar }
                markers[#markers + 1] = mk
            end
        end
        if not conflict then break end
    end
    log.retimed_bars = bars
    log.tom_conflict_bars = {}
    for _, run in ipairs(runs) do
        if run.thinned then log.tom_conflict_bars[#log.tom_conflict_bars + 1] = run.thinned end
    end
    local new_ctx
    new_ctx, log.tom_markers = ApplyTomMarkers(ctx, markers)
    for _, ev in ipairs(evs) do ev.fill_run, ev.run_id = nil, nil end
    for _, ev in ipairs(out) do
        ev.fill_run, ev.run_id, ev.src = nil, nil, nil
        if ev.retimed then
            -- A fresh event (moved): its own copy of the gems.
            local offs = {}
            for i, o in ipairs(ev.offs) do offs[i] = o end
            ev.offs = offs
        end
        -- The markers at its spot, with the new tom markers.
        if ev.retimed or #log.tom_markers > 0 then Mark(ev, new_ctx) end
    end
    return out, new_ctx
end

-- Fill runs a tier plays on a grid of `grid` QN (Medium 8ths, Easy 8ths or quarters):
-- the run's notes on that grid, or every other one when the run sits off it.
local function GridFillRuns(evs, step, grid)
    -- On the grid shifted by half a step (the "and"s of a quarter-note grid).
    local function OnShifted(ev)
        return NearInt(((ev.bar_qn or ev.qn) - grid / 2) / grid, EPS / grid)
    end
    for _, run in ipairs(FillRuns(evs, step)) do
        local a, b = run[1], run[2]
        local on, shifted = 0, 0
        for k = a, b do
            if OnGrid(evs[k], grid) then on = on + 1 elseif OnShifted(evs[k]) then shifted = shifted + 1 end
        end
        -- Quarter-note grid (Easy) only: the phase that keeps more of the run's hits, the
        -- beats on a tie - an 8th run on the "and"s keeps its "and"s (Rb R R -> Rb . R).
        -- Never on Medium's 8th grid: its shifted phase would be the 16th "e"s and "a"s.
        local Phase = OnGrid
        if grid >= 1 - EPS and shifted > on and GEN_DRUMS_PARAMS.easy_fill_phase ~= 'beats' then
            Phase = OnShifted; on = shifted
        end
        local last
        for k = a, b do
            local ev = evs[k]
            local keep
            if on > 0 then keep = Phase(ev, grid)
            else keep = not last or ev.qn - last.qn >= grid - EPS end
            if keep and last and ev.qn - last.qn < grid - EPS then keep = false end
            if keep then last = ev else ev.offs = {} end
        end
    end
    return Compact(evs)
end

----------------------------------------------------------------------
-- Hands
----------------------------------------------------------------------

-- Cymbal gems that are part of a stream: another cymbal within `near` QN before or after.
local function CymbalStream(evs, i, near)
    for _, k in ipairs({ i - 1, i + 1, i - 2, i + 2 }) do
        local o = evs[k]
        if o and math.abs(o.qn - evs[i].qn) <= near + EPS and HasCymbal(o) then return true end
    end
    return false
end

-- The timekeeping cymbals of a 16th stream: hi-hat and ride always, the crash only when
-- the stream is on the crash too (a crash accent next to 16th hi-hats stays).
local function DropStreamCymbals(evs, i)
    local ev = evs[i]
    for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
    if IsCymbal(ev, GRN) and Has(ev, GRN) then
        for _, k in ipairs({ i - 1, i + 1 }) do
            local o = evs[k]
            if o and math.abs(o.qn - ev.qn) <= 0.25 + EPS and IsCymbal(o, GRN) and Has(o, GRN) then
                Drop(ev, GRN)
                break
            end
        end
    end
end

-- Hard's 16th rules, for every onset not already settled (rolled, retimed):
--   * at or above DRUMS_RULES.roll_hard_16th_bpm: nothing off the 8th / 8th-triplet grid;
--   * below it: a tom/snare run of 16ths (hard_16th_min_run+ hits) stays only if it lasts
--     hard_run_beats or less, else it goes to the 8th grid; hi-hat/ride 16ths in a stream
--     go (right-hand timekeeping on 8ths); a lone snare 16th stays on the "a" and goes on
--     the "e", the same way throughout the song.
local function HardSixteenths(evs)
    local R, P = DRUMS_RULES, GEN_DRUMS_PARAMS
    local in_run = {}
    for _, run in ipairs(FillRuns(evs, 0.25, P.hard_16th_min_run)) do
        local a, b = run[1], run[2]
        -- A run shorter than 3 counts only as a 16th pair: two 32nds (a flam) are no run,
        -- and the faster-notes rule below keeps one of them.
        if b - a + 1 >= 3 or evs[b].qn - evs[a].qn >= 0.25 - EPS then
            local long = evs[b].qn - evs[a].qn + 0.25 > P.hard_run_beats + EPS
            for k = a, b do in_run[k] = long and 'long' or 'short' end
        end
    end
    for i, ev in ipairs(evs) do
        if not ev.rolled and not ev.retimed and not OnGrid(ev, 0.5) and not OnGrid(ev, 1 / 3) then
            if (ev.bpm or 120) >= R.roll_hard_16th_bpm then
                ev.offs = {}
            elseif in_run[i] == 'long' then
                ev.offs = {}
            elseif not in_run[i] then
                if CymbalStream(evs, i, 0.25) then DropStreamCymbals(evs, i) end
                if Has(ev, SNARE) and not HasCymbal(ev) then
                    local slot = math.floor(((ev.bar_qn or ev.qn) % 1) * 4 + 0.5) % 4
                    if slot == 1 then Drop(ev, SNARE) end
                end
                -- 16th triplets / 32nds outside a run: only a lone one stays.
                if not OnGrid(ev, 0.25) then
                    local pv, nx = evs[i - 1], evs[i + 1]
                    if (pv and ev.qn - pv.qn < 0.25 - EPS) or (nx and nx.qn - ev.qn < 0.25 - EPS) then ev.offs = {} end
                end
            end
        end
    end
    return Compact(evs)
end

-- A hit with both hands on it: a hi-hat/ride and a snare or tom.
local function TwoHand(ev)
    local cym, drum = false, Has(ev, SNARE)
    for _, o in ipairs(ev.offs) do
        if o == YEL or o == BLU then
            if IsCymbal(ev, o) then cym = true else drum = true end
        elseif IsTom(ev, o) then drum = true end
    end
    return cym and drum
end

-- Easy, where Easy ITSELF moved the hats to quarter notes (Medium had a cymbal-only "and"
-- a beat earlier that Easy dropped): a two-hand "and" keeps only its drum, and the beat
-- before it loses its hi-hat/ride too (a hit left with nothing goes), so the right hand no
-- longer moves hat -> drum on consecutive 8ths. Not where Medium was already on quarters:
-- there the "and" stays as Medium has it. upper_cym_only: positions (1/24 QN) of Medium's
-- cymbal-only hits.
local function EasyTwoHandAnds(evs, upper_cym_only)
    local at = {}
    for _, ev in ipairs(evs) do at[math.floor(ev.qn * 24 + 0.5)] = ev end
    local function CymOnly(ev)
        if not ev or not HasCymbal(ev) then return false end
        for _, o in ipairs(ev.offs) do if o == SNARE or IsTom(ev, o) then return false end end
        return true
    end
    local n = 0
    for _, ev in ipairs(evs) do
        local half = (ev.bar_qn or ev.qn) * 2
        local on_and = (ev.pulse or 1) == 1 and NearInt(half, EPS * 2) and not NearInt(half / 2, EPS)
        if on_and and not ev.rolled and TwoHand(ev) then
            local q = math.floor(ev.qn * 24 + 0.5)
            if upper_cym_only[q - 24] and not CymOnly(at[q - 24]) then
                for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
                local b = at[q - 12]
                if b and not b.rolled then
                    for o = YEL, BLU do if IsCymbal(b, o) then Drop(b, o) end end
                end
                n = n + 1
            end
        end
    end
    return n
end

-- Medium/Easy right hand: nothing on 16ths; a hi-hat/ride stream on quarter notes at or
-- above lower_hat_quarter_bpm, or at any tempo with all_quarters (Medium's fallback).
-- Triplet off-beats go unless they stand alone.
local function LowerHands(evs, all_quarters)
    local R = DRUMS_RULES
    local from_bpm = all_quarters and 0 or (GEN_DRUMS_PARAMS.lower_hat_quarter_bpm or R.general_medium_8th_bpm)
    for i, ev in ipairs(evs) do
        if not ev.rolled then
            if not OnGrid(ev, 0.5) then
                local pv, nx = evs[i - 1], evs[i + 1]
                local lone = (not pv or ev.qn - pv.qn >= 0.5 - EPS) and (not nx or nx.qn - ev.qn >= 0.5 - EPS)
                if not (OnGrid(ev, 1 / 3) and lone) then ev.offs = {} end
            elseif (ev.bpm or 120) >= from_bpm and not OnGrid(ev, 1)
                   and CymbalStream(evs, i, 0.5) and not TwoHand(ev) then
                -- A two-hand "and" (hat + snare/tom) keeps its hat; Easy may take it off
                -- (EasyTwoHandAnds).
                for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
            end
        end
    end
    return Compact(evs)
end

----------------------------------------------------------------------
-- Kicks
----------------------------------------------------------------------

local function KickWeight(ev)
    local w = CLASS_W[Gen5BeatClass(ev)] or 1
    if Has(ev, GRN) then w = w + 3 end          -- a crash wants its kick
    if #ev.offs == 1 then w = w + 1 end         -- a kick on its own carries the rhythm
    return w
end

-- The backbeat on the "and"s (Hard from DRUMS_RULES.general_hard_8th_bpm; Easy from
-- easy_and_backbeat_bpm): a bar with a snare on at least 3 of its 4 "and"s, none on the
-- beats, everything on the 8th grid - or a half bar with both its "and"s - plays the hands
-- on the "and"s only: the beats lose their hi-hat/ride (a kick and a crash stay), the
-- "and"s keep snare + cymbal, so every tier keeps the backbeat. The bar's events get
-- `and_beat`, so EndOfBarKick leaves Hard's kicks on beats 1 and 3. Returns the number of
-- bars (or half bars) changed.
local function HardAndBackbeat(evs, from_bpm)
    local bars = {}
    for _, ev in ipairs(evs) do
        if ev.bar_qn and Gen5Is44(ev) and (ev.bpm or 120) >= from_bpm then
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            bars[key] = bars[key] or {}
            table.insert(bars[key], ev)
        end
    end
    -- Snares on the "and"s of a stretch of events, and whether it qualifies at all (all on
    -- the 8th grid, no snare or tom on a beat).
    local function Count(list)
        local ands, ok = 0, true
        for k, ev in ipairs(list) do
            if not OnGrid(ev, 0.5) or ev.rolled then ok = false end
            local drum = Has(ev, SNARE)
            local tom = false
            for _, o in ipairs(ev.offs) do if IsTom(ev, o) then drum, tom = true, true end end
            if OnGrid(ev, 1) then
                -- A snare under a crash on the stretch's first beat is an accent, not a
                -- backbeat (`KRG RY KY RY`).
                local accent = k == 1 and Has(ev, SNARE) and not tom and Has(ev, GRN) and IsCymbal(ev, GRN)
                if drum and not accent then ok = false end
            elseif Has(ev, SNARE) then
                ands = ands + 1
            end
        end
        return ok, ands
    end
    local function Apply(list)
        for _, ev in ipairs(list) do
            ev.and_beat = true
            if OnGrid(ev, 1) then
                for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
            end
        end
    end
    local n = 0
    for _, list in pairs(bars) do
        local ok, ands = Count(list)
        if ok and ands >= 3 then
            Apply(list)
            n = n + 1
        else
            -- A HALF bar with the snare on both of its "and"s - the groove's first half
            -- before a fill (`KY RY KY R | R KG . KB` -> `K RY K R | ...`).
            local halves = { {}, {} }
            for _, ev in ipairs(list) do table.insert(halves[ev.bar_qn < 2 - EPS and 1 or 2], ev) end
            for _, half in ipairs(halves) do
                local hok, hands = Count(half)
                if hok and hands >= 2 then Apply(half); n = n + 1 end
            end
        end
    end
    return n
end

-- Hard below hard_kick_gap_fast_bpm: a kick on a beat with a kick-only hit a 16th after it
-- (a kick figure, `KY RY KY K RY`) keeps the beat's kick and loses the 16th one, and the
-- busy-hands half bar does not apply to that beat kick. Returns the set of beat events
-- kept that way.
local function HardKickFigures(evs)
    local figure = {}
    for i, ev in ipairs(evs) do
        local nx = evs[i + 1]
        if nx and Has(ev, KICK) and OnBeat(ev) and (ev.bpm or 120) < GEN_DRUMS_PARAMS.hard_kick_gap_fast_bpm
           and math.abs(nx.qn - ev.qn - 0.25) <= EPS and #nx.offs == 1 and nx.offs[1] == KICK and not nx.rolled then
            local nn = evs[i + 2]
            if not nn or nn.qn - nx.qn > 0.25 - EPS then   -- a lone 16th, not the start of a run
                nx.offs = {}
                figure[ev] = true
            end
        end
    end
    return figure
end

-- "Are the hands busy around this kick": a hand hit (any gem but the kick) an 8th before
-- AND an 8th after it. Returns a function of the event.
local function BusyHands(evs)
    local hands = {}
    for _, ev in ipairs(evs) do
        for _, o in ipairs(ev.offs) do
            if o ~= KICK then hands[math.floor(ev.qn * 24 + 0.5)] = true; break end
        end
    end
    return function(ev)
        local at = math.floor(ev.qn * 24 + 0.5)
        return hands[at - 12] and hands[at + 12]
    end
end

-- Kicks no closer than gap(ev) (adjacent 16ths, or 8ths too), the strongest kept.
local function ThinKicks(evs, gap)
    local list = {}
    for _, ev in ipairs(evs) do
        if Has(ev, KICK) and not ev.rolled then list[#list + 1] = ev end
    end
    local keep = KeepByGap(list, gap, KickWeight)
    for k, ev in ipairs(list) do
        if not keep[k] then Drop(ev, KICK); ev.kick_dropped = true end
    end
end

-- Hard: a bar of steady 8th hi-hats/rides loses n_drop of its hat-only "and"s - the drums
-- side of the band's "Hard 8th runs" setting (busy_drop: 1 or 2; Auto = 2 when the song
-- starts above GEN5_PARAMS.fast_8ths_bpm). Order: the "and" of 1 when the downbeat is a
-- crash (the hand comes back from the crash), then the "and" of 4, then the "and" of 2.
-- Only a hat-only hit loses its hat; a slot that is not hat-only is skipped. Returns the
-- number of hats removed.
local function HardHatDrops(evs, n_drop)
    local bars = {}
    for _, ev in ipairs(evs) do
        if ev.bar_qn and Gen5Is44(ev) then
            local s2 = ev.bar_qn * 2
            if NearInt(s2, EPS * 2) then
                local key = ('%.3f'):format(ev.qn - ev.bar_qn)
                local b = bars[key] or {}
                bars[key] = b
                b[math.floor(s2 + 0.5)] = ev
            end
        end
    end
    local function HatOnly(ev)
        if not ev or ev.rolled or #ev.offs ~= 1 then return false end
        local o = ev.offs[1]
        return (o == YEL or o == BLU) and IsCymbal(ev, o)
    end
    local n = 0
    for _, b in pairs(bars) do
        local steady = true
        for k = 0, 7 do if not (b[k] and HasCymbal(b[k])) then steady = false; break end end
        if steady then
            local order = { 7, 3 }
            if IsCymbal(b[0], GRN) and Has(b[0], GRN) then order = { 1, 7, 3 } end
            local left = n_drop
            for _, k in ipairs(order) do
                if left == 0 then break end
                if HatOnly(b[k]) then b[k].offs = {}; left = left - 1; n = n + 1 end
            end
        end
    end
    return n
end

-- The tier above's 4/4 bars on the 8th grid, read before any rule moves a note (Hard's fill
-- rewrite puts notes on other grids): bars[key] = { kick = { [slot] = true }, hands = {...} },
-- slot 0-7 = the bar's 8ths. Keyed like the kick rules' bars (the bar line's QN).
local function UpperEighths(events)
    local bars = {}
    for _, ev in ipairs(events) do
        if ev.bar_qn and Gen5Is44(ev) then
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            local b = bars[key] or { kick = {}, hands = {} }
            bars[key] = b
            local s = ev.bar_qn * 2
            local slot = math.floor(s + 0.5)
            if math.abs(s - slot) <= EPS then
                for _, o in ipairs(ev.offs) do
                    if o == KICK then b.kick[slot] = true else b.hands[slot] = true end
                end
            end
        end
    end
    return bars
end

local function AllSlots(set, slots)
    for _, s in ipairs(slots) do if not set[s] then return false end end
    return true
end
local EVERY_8TH = { 0, 1, 2, 3, 4, 5, 6, 7 }
local EVERY_BEAT = { 0, 2, 4, 6 }

-- Expert's kicks on exactly the four beats (no 8th kick between).
local function QuarterKickBar(up)
    if not (up and AllSlots(up.kick, EVERY_BEAT)) then return false end
    for _, s in ipairs({ 1, 3, 5, 7 }) do if up.kick[s] then return false end end
    return true
end

-- Hard: a bar whose Expert kicks AND hands both play every 8th keeps a kick on every beat -
-- one step slower, where the busy-hands spacing would leave 1 and 3, the same as Expert's
-- quarter-kick bars, and a build from quarter kicks to 8th kicks would vanish.
local function HardEighthKicks(evs, upper)
    local n = 0
    for _, ev in ipairs(evs) do
        local up = ev.bar_qn and upper[('%.3f'):format(ev.qn - ev.bar_qn)]
        if up and AllSlots(up.kick, EVERY_8TH) and AllSlots(up.hands, EVERY_8TH) then
            local s = ev.bar_qn * 2
            local slot = math.floor(s + 0.5)
            -- On a beat Expert has a kick (EVERY_8TH); the hit there may be another note the
            -- fill rewrite moved onto the beat, so it is not asked whether it lost one.
            if math.abs(s - slot) <= EPS and slot % 2 == 0 then
                if not Has(ev, KICK) then Add(ev, KICK); ev.kick_dropped = nil; n = n + 1 end
            elseif Has(ev, KICK) then
                Drop(ev, KICK)
                ev.kick_dropped = true
            end
        end
    end
    return n
end

-- Hard: the busy-hands spacing keeps the kicks on 1 and 3; one 8th kick paired with beat
-- 3's kick - the one leading into it (the "and" of 2), else the one right after it (the
-- "and" of 3) - comes back. Not when Expert has both: then 1 and 3 only - read from the
-- tier above itself, since the fill rewrite can move either "and" off the 8th grid.
local function PairedKick(evs, upper)
    local bars = {}
    for _, ev in ipairs(evs) do
        if ev.bar_qn and ev.bar_len and Gen5Is44(ev) then
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            local b = bars[key] or {}
            bars[key] = b
            for _, slot in ipairs({ { 'mid', 2 }, { 'before', 1.5 }, { 'after', 2.5 } }) do
                if math.abs(ev.bar_qn - slot[2]) <= EPS then b[slot[1]] = ev end
            end
        end
    end
    for key, b in pairs(bars) do
        local mid, pre, post = b.mid, b.before, b.after
        local up = upper[key]
        if mid and Has(mid, KICK) and not (up and up.kick[3] and up.kick[5]) then
            local pre_k = pre and pre.kick_dropped and not Has(pre, KICK)
            local post_k = post and post.kick_dropped and not Has(post, KICK)
            if pre_k and not post_k then Add(pre, KICK)
            elseif post_k and not pre_k then Add(post, KICK) end
        end
    end
end

-- Hard: a bar whose busy-hands spacing left no kick on its last beat or the "and" after it
-- gets the last-beat kick back when Expert had one there - the end of the bar keeps a
-- faster kick pattern than its start. With no Expert kick on beat 4 the "and" alone is left
-- thinned, and with Expert's kicks on exactly the four beats the bar keeps 1 and 3.
local function EndOfBarKick(evs, upper)
    local bars = {}
    for _, ev in ipairs(evs) do
        if ev.bar_qn and ev.bar_len then
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            local b = bars[key] or { evs = {} }
            bars[key] = b
            b.evs[#b.evs + 1] = ev
            local last = ev.bar_len - (ev.pulse or 1)
            if math.abs(ev.bar_qn - last) <= EPS then b.last = ev
            elseif math.abs(ev.bar_qn - (last + 0.5)) <= EPS then b.after = ev end
        end
    end
    for key, b in pairs(bars) do
        local ev = b.last
        -- Not in a backbeat-on-the-"and"s bar: kicks on beats 1 and 3 there (HardAndBackbeat).
        if ev and ev.kick_dropped and not Has(ev, KICK) and not (b.after and Has(b.after, KICK)) and not ev.and_beat
           and not QuarterKickBar(upper[key]) then
            Add(ev, KICK)
            -- The beat's kick wins over a 16th kick right after it, which the spacing kept
            -- only because the beat's had gone (KY on beat 4 + K on its "e").
            for _, o in ipairs(b.evs) do
                if o.qn > ev.qn + EPS and o.qn < ev.qn + GEN_DRUMS_PARAMS.hard_kick_gap_8th - EPS
                   and Has(o, KICK) then
                    Drop(o, KICK)
                    o.kick_dropped = true
                end
            end
        end
    end
end

-- Medium/Easy kicks: on quarter notes above DRUMS_RULES.kick_grid_bpm, never under an
-- off-beat crash, then spaced (a quarter note; half a bar at speed or under busy hands; one
-- a bar from kick_per_measure_bpm is OneKickPerBar's). keep_spacing: only the kicks the
-- tier may not contain go (Drums 2X, whose kicks are already a tier's - GenDrums2xInput).
local function LowerKicks(evs, keep_spacing)
    local R = DRUMS_RULES
    for _, ev in ipairs(evs) do
        if Has(ev, KICK) then
            local bpm = ev.bpm or 120
            local quarter = NearInt(ev.qn, 0.05)
            if (bpm > R.kick_grid_bpm and not quarter) or (not OnGrid(ev, 0.5)) then
                Drop(ev, KICK)
            elseif Has(ev, GRN) and #ev.offs == 2 and not quarter then
                Drop(ev, KICK)
            end
        end
    end
    if keep_spacing then return end
    local P = GEN_DRUMS_PARAMS
    local Busy = BusyHands(evs)
    ThinKicks(evs, function(ev, pv)
        if (ev.bpm or 120) >= P.lower_kick_gap_fast_bpm then return P.lower_kick_gap_fast end
        -- Busy hands' half bar reaches back only within the kick's own bar, as on Hard.
        local same_bar = not pv
            or math.abs((ev.qn - (ev.bar_qn or 0)) - (pv.qn - (pv.bar_qn or 0))) < EPS
        if Busy(ev) and same_bar then return P.lower_kick_gap_busy end
        return P.lower_kick_gap
    end)
end

-- Medium/Easy: one kick a bar from kick_per_measure_bpm, the strongest kept. Run on the
-- finished tier: the rule goes by the tempo at the bar's first kick, as Validate does, and
-- an earlier step removing that kick could move the bar across the threshold.
local function OneKickPerBar(evs)
    local R = DRUMS_RULES
    local function BarKey(ev) return ('%.3f'):format(ev.qn - (ev.bar_qn or 0)) end
    local bar_bpm = {}
    for _, ev in ipairs(evs) do
        if Has(ev, KICK) and not bar_bpm[BarKey(ev)] then bar_bpm[BarKey(ev)] = ev.bpm or 120 end
    end
    local bars = {}
    for _, ev in ipairs(evs) do
        if Has(ev, KICK) and bar_bpm[BarKey(ev)] >= R.kick_per_measure_bpm then
            local key = BarKey(ev)
            local b = bars[key]
            if not b or KickWeight(ev) > KickWeight(b) then
                if b then Drop(b, KICK) end
                bars[key] = ev
            else
                Drop(ev, KICK)
            end
        end
    end
end

-- The kick under a snare backbeat (GEN_DRUMS_PARAMS.kick_under_snare).
local function KickUnderSnare(evs, dl)
    if not GEN_DRUMS_PARAMS.kick_under_snare[dl] then return end
    for _, ev in ipairs(evs) do
        if Has(ev, KICK) and Has(ev, SNARE) and not ev.down and not ev.rolled then Drop(ev, KICK) end
    end
end

-- Fill lanes (pitch 120) change no kicks, on any tier: a lane marks where overdrive can be
-- activated, not what is played there.

----------------------------------------------------------------------
-- Medium: limb independence, crashes, three-limb hits
----------------------------------------------------------------------

-- Medium: a kick/snare-only hit between two hi-hat/ride notes at most a quarter apart.
-- mode 'beats' keeps the ones on a beat, 'none' removes them all, 'keep' leaves them. The
-- "hi-hat/ride" is right-hand timekeeping - a Yellow/Blue cymbal; a crash is not (a snare
-- on the "and" before a downbeat crash stays).
local function TimeCymbal(ev)
    return (IsCymbal(ev, YEL) and Has(ev, YEL)) or (IsCymbal(ev, BLU) and Has(ev, BLU))
end

local function Between(evs, mode)
    if mode == 'keep' then return end
    local last_cym
    for i, ev in ipairs(evs) do
        if TimeCymbal(ev) then
            last_cym = ev
        elseif last_cym and not ev.rolled and not HasCymbal(ev) then
            -- Kick and/or snare only: a tom makes it a fill note, which stays.
            local tom = false
            for _, o in ipairs(ev.offs) do if IsTom(ev, o) then tom = true end end
            if not tom then
                local nxt
                for k = i + 1, #evs do if TimeCymbal(evs[k]) then nxt = evs[k]; break end end
                if nxt and nxt.qn - last_cym.qn <= 1 + EPS and (mode == 'none' or not OnBeat(ev)) then
                    ev.offs = {}
                end
            end
        end
    end
end

-- A hi-hat/ride hit sandwiched between snare accents - an accent (snare, no cymbal) an
-- 8th before AND an 8th after - loses its cymbal; a kick on it stays. Otherwise the hands
-- alternate hat and accent on every 8th, and with a tom in the accent the right hand must
-- leap back to the hat (`Y Rb Y Rb Y`). need_tom: Medium, where snare-only accents are
-- Between's job. Crashes stay: a crash on the beat is an accent too.
local function SandwichedHats(evs, need_tom)
    local at = {}
    for _, ev in ipairs(evs) do at[math.floor(ev.qn * 24 + 0.5)] = ev end
    local function Accent(ev)
        if not ev or not Has(ev, SNARE) or HasCymbal(ev) then return false end
        if not need_tom then return true end
        for _, o in ipairs(ev.offs) do if IsTom(ev, o) then return true end end
        return false
    end
    local drop = {}
    for _, ev in ipairs(evs) do
        if not ev.rolled and not Has(ev, SNARE) and (IsCymbal(ev, YEL) and Has(ev, YEL) or IsCymbal(ev, BLU) and Has(ev, BLU)) then
            local q = math.floor(ev.qn * 24 + 0.5)
            if Accent(at[q - 12]) and Accent(at[q + 12]) then drop[#drop + 1] = ev end
        end
    end
    -- Decided on the tier as it came in, then applied, so one removal cannot hide the next.
    for _, ev in ipairs(drop) do
        for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
    end
    return #drop
end

-- Medium/Easy: two two-hand hits (one cymbal + one drum each) an 8th apart whose drum
-- changes - tom to snare, snare to tom, tom to another tom: the first loses its drum and
-- keeps its cymbal, so the drum hand gets a beat to move (`Yb RY` -> `Y RY`).
local function DrumChanges(evs)
    local function Split(ev)
        local cym, drum = {}, {}
        for _, o in ipairs(ev.offs) do
            if o == SNARE or IsTom(ev, o) then drum[#drum + 1] = o
            elseif IsCymbal(ev, o) then cym[#cym + 1] = o end
        end
        return cym, drum
    end
    local drop = {}
    for i = 1, #evs - 1 do
        local a, b = evs[i], evs[i + 1]
        if not a.rolled and math.abs(b.qn - a.qn - 0.5) <= EPS then
            local ca, da = Split(a)
            local cb, db = Split(b)
            if #ca == 1 and #da == 1 and #cb == 1 and #db == 1 and da[1] ~= db[1] then
                drop[#drop + 1] = { a, da[1] }
            end
        end
    end
    for _, d in ipairs(drop) do Drop(d[1], d[2]) end
    return #drop
end

-- Easy: a two-hand hit (hi-hat/ride + snare/tom) an 8th before a crash loses its hat and
-- keeps its drum, so the right hand is free to reach the crash (`RY | G` -> `R | G`). A
-- hat-only hit before a crash is left alone.
local function EasyBeforeCrash(evs)
    local n = 0
    if not GEN_DRUMS_PARAMS.easy_before_crash then return n end
    for i = 1, #evs - 1 do
        local a, b = evs[i], evs[i + 1]
        if not a.rolled and math.abs(b.qn - a.qn - 0.5) <= EPS and IsCymbal(b, GRN) and Has(b, GRN)
           and TwoHand(a) then
            for o = YEL, BLU do if IsCymbal(a, o) then Drop(a, o) end end
            n = n + 1
        end
    end
    return n
end

-- Medium: a two-hand hit with a tom - two toms, or a cymbal + a tom - plays one gem from
-- medium_tom_pair_bpm; two toms also on an off-beat at any tempo. A cymbal + tom off the
-- beat below that tempo is the two-hand "and" LowerHands keeps. The gem kept: of two toms
-- the higher lane (Green over Blue over Yellow), of a cymbal + tom the tom. A snare + tom
-- stays; a roll's notes are left to the roll.
local function MediumTomPairs(evs)
    local bpm, n = GEN_DRUMS_PARAMS.medium_tom_pair_bpm, 0
    if not bpm then return 0 end
    -- A sparse bar keeps its tom pairs: no more hand NOTES than beats - a double counts two,
    -- kicks none (`Kyb Kyb` stays; `bg Rg bg R`, 7 notes, does not). When the bar is over only
    -- because a two-tom hit repeats an 8th later, the repeats go and the doubles stay
    -- (`yb yb . yb yb` -> `yb . . yb`).
    local function Hands(ev)
        local n = 0
        for _, o in ipairs(ev.offs) do if o ~= KICK then n = n + 1 end end
        return n
    end
    local function TwoToms(ev)
        local t = 0
        for _, o in ipairs(ev.offs) do if o ~= KICK and IsTom(ev, o) then t = t + 1 end end
        return t == 2 and Hands(ev) == 2
    end
    local function Same(a, b)
        if #a.offs ~= #b.offs then return false end
        for k, o in ipairs(a.offs) do if b.offs[k] ~= o then return false end end
        return true
    end
    local per_bar, repeats = {}, {}
    for i, ev in ipairs(evs) do
        local key = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
        per_bar[key] = (per_bar[key] or 0) + Hands(ev)
        local pv = evs[i - 1]
        if pv and TwoToms(ev) and Same(pv, ev) and math.abs(ev.qn - pv.qn - 0.5) <= EPS and not ev.rolled then
            repeats[key] = repeats[key] or {}
            table.insert(repeats[key], ev)
        end
    end
    for key, list in pairs(repeats) do
        local ev = list[1]
        local beats = (ev.bar_len or 4) / (ev.pulse or 1)
        if per_bar[key] > beats + EPS and per_bar[key] - 2 * #list <= beats + EPS then
            for _, r in ipairs(list) do
                local keep = {}
                for _, o in ipairs(r.offs) do if o == KICK then keep[#keep + 1] = o end end
                r.offs = keep
                n = n + 1
            end
            per_bar[key] = per_bar[key] - 2 * #list
        end
    end
    for _, ev in ipairs(evs) do
        local key = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
        local beats = (ev.bar_len or 4) / (ev.pulse or 1)
        local sparse = GEN_DRUMS_PARAMS.medium_tom_pair_sparse_keep and per_bar[key] <= beats + EPS
        if not sparse then
        local lo, hi, count = nil, nil, 0
        for _, o in ipairs(ev.offs) do
            if o ~= KICK then
                count = count + 1
                if not lo or o < lo then lo = o end
                if not hi or o > hi then hi = o end
            end
        end
        local both = count == 2 and IsTom(ev, lo) and IsTom(ev, hi)
        if count == 2 and not ev.rolled and lo >= YEL and (IsTom(ev, lo) or IsTom(ev, hi))
           and ((ev.bpm or 120) >= bpm or (both and not OnBeat(ev))) then
            -- Two toms: the higher lane stays; a cymbal + tom: the tom stays.
            Drop(ev, (IsTom(ev, hi) and hi ~= lo) and lo or hi)
            n = n + 1
        end
        end
    end
    return n
end

-- Easy from easy_lone_and_bpm: a lone drum "and" - snare, tom or kick, no cymbal - with a
-- hit on the beat an 8th before and after it goes. A roll's notes stay.
local function EasyLoneAnds(evs)
    local bpm = GEN_DRUMS_PARAMS.easy_lone_and_bpm
    if not bpm then return evs, 0 end
    local drop, n = {}, 0
    for i = 2, #evs - 1 do
        local p, m, nx = evs[i - 1], evs[i], evs[i + 1]
        if (m.bpm or 120) >= bpm and not m.rolled and not OnBeat(m) and OnGrid(m, 0.5)
           and math.abs(m.qn - p.qn - 0.5) <= EPS and math.abs(nx.qn - m.qn - 0.5) <= EPS
           and OnBeat(p) and OnBeat(nx) and not HasCymbal(m) then
            drop[i] = true
            n = n + 1
        end
    end
    for i in pairs(drop) do evs[i].offs = {} end
    return Compact(evs), n
end

-- Medium/Easy: two hits an 8th apart on DIFFERENT cymbals that need 3+ hand pads between
-- them make a hand jump (`RY | RG`; with two pads, `B | G`, each hand stays on its own).
-- The hi-hat/ride that is not on both goes - Yellow before Blue - so the hand has one
-- cymbal to stay on; crashes, snares and toms stay. A double crash (Yellow/Blue + Green
-- cymbal) stays and the other hit keeps only its top gem (GemRank) - for an input that
-- still has one: DoubleCrashes leaves none on a generated tier.
-- GemRank: how much a hand gem matters when one of two must go.
local function GemRank(ev, o)
    if o == GRN then return IsCymbal(ev, o) and 7 or 5 end
    if o == SNARE then return 6 end
    if o == BLU then return IsCymbal(ev, o) and 2 or 4 end
    if o == YEL then return IsCymbal(ev, o) and 1 or 3 end
    return 0
end

local function CymbalChanges(evs)
    if not GEN_DRUMS_PARAMS.lower_cymbal_change then return 0 end
    local function Cyms(ev)
        local c = {}
        for _, o in ipairs(ev.offs) do if o >= YEL and IsCymbal(ev, o) then c[o] = true end end
        return c
    end
    local function Double(c) return c[GRN] and (c[YEL] or c[BLU]) end
    local function TopOnly(ev)
        local best, br = nil, -1
        for _, o in ipairs(ev.offs) do
            if o ~= KICK and GemRank(ev, o) > br then best, br = o, GemRank(ev, o) end
        end
        local keep = {}
        for _, o in ipairs(ev.offs) do if o == KICK or o == best then keep[#keep + 1] = o end end
        local changed = #keep < #ev.offs
        ev.offs = keep
        return changed
    end
    local n = 0
    for i = 1, #evs - 1 do
        local a, b = evs[i], evs[i + 1]
        if math.abs(b.qn - a.qn - 0.5) <= EPS and not a.rolled and not b.rolled then
            local ca, cb = Cyms(a), Cyms(b)
            local differ = false
            if next(ca) and next(cb) then
                for o in pairs(ca) do if not cb[o] then differ = true end end
                for o in pairs(cb) do if not ca[o] then differ = true end end
            end
            -- ... and the two hits need 3+ different hand pads between them (the kick does not
            -- count; a tom and a cymbal of one color are different pads): with two, each hand
            -- stays on its own pad (`B | G`).
            local pads, npads = {}, 0
            for _, ev in ipairs({ a, b }) do
                for _, o in ipairs(ev.offs) do
                    if o ~= KICK then
                        local key = o .. (IsTom(ev, o) and 't' or '')
                        if not pads[key] then pads[key] = true; npads = npads + 1 end
                    end
                end
            end
            if differ and npads >= 3 then
                local da, db = Double(ca), Double(cb)
                if da and not db then
                    if TopOnly(b) then n = n + 1 end
                elseif db and not da then
                    if TopOnly(a) then n = n + 1 end
                elseif not (da and db) then
                    -- The lowest-ranked hi-hat/ride on only one of the two hits.
                    local ev, o = nil, nil
                    for _, cand in ipairs({ YEL, BLU }) do
                        if not o then
                            if ca[cand] and not cb[cand] then ev, o = a, cand
                            elseif cb[cand] and not ca[cand] then ev, o = b, cand end
                        end
                    end
                    if o then Drop(ev, o); n = n + 1 end
                end
            end
        end
    end
    return n
end

-- Easy from easy_cymbal_change_quarter_bpm: CymbalChanges at a quarter note. A hi-hat/ride
-- on neither of the hits a quarter before and after it, both on other cymbals and each
-- needing 3+ hand pads with it, goes (`G RB G RG` -> `G R G RG`, `RG Y RG` -> `RG . RG`):
-- the hand stops jumping between cymbals on every beat. A hat with the same cymbal on one
-- side stays, so a crash on 1 into a hat beat (`G RY Y RY`) is left alone. A hit left
-- empty plays the kick the tier above has there, when its bar has no kick yet: the beat
-- is not silent, and one kick a bar keeps Easy's kick limits. upper_kick: positions (1/24
-- QN) of the incoming tier's kicks. Returns the number of hats removed.
local function CymbalChangesQuarter(evs, upper_kick)
    local from = GEN_DRUMS_PARAMS.easy_cymbal_change_quarter_bpm
    if not from then return 0 end
    local function Cyms(ev)
        local c = {}
        for _, o in ipairs(ev.offs) do if o >= YEL and IsCymbal(ev, o) then c[o] = true end end
        return c
    end
    local function Pads(a, b)
        local pads, n = {}, 0
        for _, ev in ipairs({ a, b }) do
            for _, o in ipairs(ev.offs) do
                if o ~= KICK then
                    local key = o .. (IsTom(ev, o) and 't' or '')
                    if not pads[key] then pads[key] = true; n = n + 1 end
                end
            end
        end
        return n
    end
    local list = {}
    for _, ev in ipairs(evs) do
        if not ev.rolled then
            for _, o in ipairs(ev.offs) do if o ~= KICK then list[#list + 1] = ev; break end end
        end
    end
    -- Decided on the tier as it came in, then applied, so one removal cannot hide the next.
    local drop = {}
    for i = 2, #list - 1 do
        local p, ev, nx = list[i - 1], list[i], list[i + 1]
        if (ev.bpm or 120) >= from and math.abs(ev.qn - p.qn - 1) <= EPS and math.abs(nx.qn - ev.qn - 1) <= EPS
           and Pads(p, ev) >= 3 and Pads(ev, nx) >= 3 then
            local cp, cn = Cyms(p), Cyms(nx)
            if next(cp) and next(cn) then
                for _, o in ipairs({ YEL, BLU }) do
                    if IsCymbal(ev, o) and Has(ev, o) and not cp[o] and not cn[o] then drop[#drop + 1] = { ev, o } end
                end
            end
        end
    end
    local function BarKey(ev) return ('%.3f'):format(ev.qn - (ev.bar_qn or 0)) end
    local bar_kick = {}
    for _, ev in ipairs(evs) do if Has(ev, KICK) then bar_kick[BarKey(ev)] = true end end
    for _, d in ipairs(drop) do
        local ev = d[1]
        Drop(ev, d[2])
        if #ev.offs == 0 and upper_kick[math.floor(ev.qn * 24 + 0.5)] and not bar_kick[BarKey(ev)] then
            Add(ev, KICK)
            bar_kick[BarKey(ev)] = true
        end
    end
    return #drop
end

-- Medium/Easy: a snare + tom hit (both hands on drums, no cymbal) a quarter note or less
-- before a crash loses its tom, so the hand gets to the crash.
local function TomBeforeCrash(evs)
    local n = 0
    for i = 1, #evs - 1 do
        local a, b = evs[i], evs[i + 1]
        if not a.rolled and b.qn - a.qn <= 1 + EPS and IsCymbal(b, GRN) and Has(b, GRN)
           and Has(a, SNARE) and not HasCymbal(a) then
            local dropped = false
            for o = YEL, GRN do if IsTom(a, o) and Drop(a, o) then dropped = true end end
            if dropped then n = n + 1 end
        end
    end
    return n
end

-- Medium: the hand that just crashed resets. From after_crash_bpm the cymbal/tom gems of
-- an onset an 8th or less after a crash accent go; from after_crash_snare_bpm its snare too
-- (`KG R . RY` -> `KG . . RY`). The kick stays. An accent, not a ride on the crash: one
-- with no crash an 8th before it. Easy follows Medium.
local function AfterCrash(evs)
    local P = GEN_DRUMS_PARAMS
    for i = 2, #evs do
        local pv, ev, pp = evs[i - 1], evs[i], evs[i - 2]
        local accent = IsCymbal(pv, GRN) and Has(pv, GRN)
            and not (pp and Has(pp, GRN) and pv.qn - pp.qn <= 0.5 + EPS)
        if accent and (ev.bpm or 120) >= P.after_crash_bpm and ev.qn - pv.qn <= 0.5 + EPS and not ev.rolled then
            for o = YEL, GRN do Drop(ev, o) end
            if P.after_crash_snare_bpm and (ev.bpm or 120) >= P.after_crash_snare_bpm then Drop(ev, SNARE) end
        end
    end
end

-- At most `max` gems: a three-limb hit loses the kick (KRY -> RY), anything bigger then
-- its non-crash cymbal.
local function MaxGems(evs, max)
    for i, ev in ipairs(evs) do
        -- A kick + a double crash with no room before it (DoubleCrashes will make it a single
        -- Green anyway): the Yellow/Blue goes, not the kick - KYG -> KG rather than YG -> G.
        if #ev.offs > max and max == 2 and #ev.offs == 3 and Has(ev, KICK) and Has(ev, GRN)
           and IsCymbal(ev, GRN) and (Has(ev, YEL) or Has(ev, BLU)) then
            local o = Has(ev, YEL) and YEL or BLU
            local pv = evs[i - 1]
            if IsCymbal(ev, o) and (not pv or ev.qn - pv.qn < 0.95) then Drop(ev, o) end
        end
        if #ev.offs > max then Drop(ev, KICK) end
        while #ev.offs > max do
            if not (Drop(ev, YEL) or Drop(ev, BLU)) then table.remove(ev.offs) end
        end
    end
end

----------------------------------------------------------------------
-- Easy: one beat type per section
----------------------------------------------------------------------

-- Easy plays one beat per section: kick + snare, or the two-hand beat (no kick). A verse
-- led by the hi-hat or the ride plays kick + snare when its Medium has at least
-- easy_ks_min_density kick/snare onsets per quarter note - a sparser verse keeps its
-- cymbal; a crash-led verse and every other section play the two-hand beat. A section whose
-- Medium has no cymbal at all is kick + snare by necessity.
function GenDrumsIsVerse(name) return (name or ''):lower():find('verse', 1, true) ~= nil end

local function SectionTypes(evs, sections)
    local secs = {}
    for _, s in ipairs(sections or {}) do secs[#secs + 1] = s end
    table.sort(secs, function(a, b) return a.qn < b.qn end)
    if #secs == 0 or secs[1].qn > (evs[1] and evs[1].qn or 0) + EPS then
        table.insert(secs, 1, { qn = -math.huge, name = '' })
    end
    local function SecIndex(qn)
        local idx = 1
        for k, s in ipairs(secs) do if s.qn <= qn + EPS then idx = k else break end end
        return idx
    end
    local count = {}
    for _, ev in ipairs(evs) do
        local k = SecIndex(ev.qn)
        local c = count[k] or { [YEL] = 0, [BLU] = 0, [GRN] = 0, ks = 0 }
        count[k] = c
        c.first = c.first or ev.qn
        c.last = ev.qn
        for _, o in ipairs(ev.offs) do if IsCymbal(ev, o) then c[o] = c[o] + 1 end end
        if Has(ev, KICK) or Has(ev, SNARE) then c.ks = c.ks + 1 end
    end
    local types = {}
    for k, s in ipairs(secs) do
        local c = count[k] or { [YEL] = 0, [BLU] = 0, [GRN] = 0, ks = 0 }
        local total = c[YEL] + c[BLU] + c[GRN]
        local hat = c[YEL] > 0 and c[YEL] >= c[BLU] and c[YEL] >= c[GRN]
        local ride = c[BLU] > 0 and c[BLU] >= c[YEL] and c[BLU] >= c[GRN]
        -- Kick/snare onsets per quarter note over the section's notes.
        local density = c.first and c.ks / (c.last - c.first + 1) or 0
        local ks = GenDrumsIsVerse(s.name) and (hat or ride)
                   and density >= (GEN_DRUMS_PARAMS.easy_ks_min_density or 0)
        types[k] = (total == 0 or ks) and 'ks' or 'hands'
    end
    return SecIndex, types, secs
end

local function EasyBeats(evs, sections, log)
    local SecIndex, types = SectionTypes(evs, sections)
    -- Bars with no cymbal at all play kick + snare whatever their section.
    local bar_cym = {}
    -- Half bars with a hand hit (a two-hand bar's kicks stay in a half bar without one).
    local half_hands = {}
    local function HalfKey(ev)
        local half = (ev.bar_qn or 0) >= (ev.bar_len or 4) / 2 - EPS and 2 or 1
        return ('%.3f:%d'):format(ev.qn - (ev.bar_qn or 0), half)
    end
    for _, ev in ipairs(evs) do
        local key = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
        if HasCymbal(ev) then bar_cym[key] = true end
        for _, o in ipairs(ev.offs) do
            if o ~= KICK then half_hands[HalfKey(ev)] = true; break end
        end
    end
    local seen = {}
    for _, ev in ipairs(evs) do
        local k = SecIndex(ev.qn)
        local t = types[k]
        if not seen[k] then seen[k] = true; log.easy_types[t] = log.easy_types[t] + 1 end
        if not ev.rolled then
            local bar = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
            if t == 'ks' then
                -- Kick + snare: the hi-hat/ride goes, a crash stays (instead of its kick),
                -- toms stay.
                for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
            elseif bar_cym[bar] and (half_hands[HalfKey(ev)] or not GEN_DRUMS_PARAMS.easy_quiet_half_kicks) then
                -- Two-hand beat: no kicks - except in a half bar with no hand hit at all
                -- (easy_quiet_half_kicks): there the kicks are all there is.
                Drop(ev, KICK)
            end
        end
    end
    -- No gem paired with a kick: the other gem wins.
    for _, ev in ipairs(evs) do if #ev.offs > 1 then Drop(ev, KICK) end end
end

----------------------------------------------------------------------
-- Every tier: double crashes, constant 8ths
----------------------------------------------------------------------

-- A Green + Yellow/Blue double crash is a single Green on every tier below Expert, room
-- around it or not; a kick under it stays. Cymbals only: a tom pair (`bg`) or a cymbal +
-- tom (`Yg`) is no double crash.
local function DoubleCrashes(evs)
    for _, ev in ipairs(evs) do
        local hands = {}
        for _, o in ipairs(ev.offs) do if o ~= KICK then hands[#hands + 1] = o end end
        if #hands == 2 and hands[2] == GRN and (hands[1] == YEL or hands[1] == BLU)
           and IsCymbal(ev, hands[1]) and IsCymbal(ev, GRN) then
            Drop(ev, hands[1])
        end
    end
end

-- Value of an onset when a run of 8ths must lose one: the backbeat and kicks first.
local function OnsetValue(ev)
    local v = OnBeat(ev) and 10 or 0
    if Has(ev, SNARE) then v = v + 3 end
    if Has(ev, KICK) then v = v + 2 end
    if Has(ev, GRN) then v = v + 2 end
    return v + 0.5 * #ev.offs
end

-- No run of min_run_len onsets an 8th apart at or above the tier's tempo (Hard
-- general_hard_8th_bpm, Medium/Easy general_medium_8th_bpm): each run loses its least
-- valuable onset. Medium/Easy count every onset. Hard counts hand notes only - the stream
-- is the hands' timekeeping, a kick-only hit is no part of it - and is relative to Expert: a
-- run at one spacing (8ths from general_hard_8th_bpm, 8th triplets from
-- DRUMS_RULES.hard_trip_stream_bpm) is only a problem where Expert does not play faster over
-- the same stretch - a reduction is what Hard is for, a copy of Expert's stream is not.
-- `upper`: the events Hard is planned from (Expert). Validate's Hard check
-- (CheckDrumsGeneralDensity) counts the same way.
local function BreakEighthRuns(evs, dl, upper)
    local R = DRUMS_RULES
    local hands_only = dl == 'H'
    -- Spacings checked and the tempo each starts at.
    local spacings = dl == 'H' and { { 0.5, R.general_hard_8th_bpm }, { 1 / 3, R.hard_trip_stream_bpm } }
                     or { { 0.5, R.general_medium_8th_bpm } }
    local function Hand(ev)
        if not hands_only then return true end
        for _, o in ipairs(ev.offs) do if o ~= KICK then return true end end
        return false
    end
    -- Expert's hand hits, for "is Expert faster over this stretch".
    local xq = {}
    if dl == 'H' and upper then
        for _, ev in ipairs(upper) do if Hand(ev) then xq[#xq + 1] = ev.qn end end
    end
    local function ExpertFaster(q0, q1, n, sp)
        if not upper then return false end
        local cnt, prev, closest = 0, nil, math.huge
        for _, q in ipairs(xq) do
            if q >= q0 - EPS and q <= q1 + EPS then
                cnt = cnt + 1
                if prev then closest = math.min(closest, q - prev) end
                prev = q
            end
        end
        return cnt > n or closest < sp - EPS
    end
    local function List()
        local l = {}
        for k, ev in ipairs(evs) do if Hand(ev) then l[#l + 1] = k end end
        return l
    end
    local L = List()
    local removed = 0
    local i = 1
    while i <= #L do
        local run, sp_found, floor = { L[i] }, nil, nil
        if i < #L then
            local gap = evs[L[i + 1]].qn - evs[L[i]].qn
            for _, sp in ipairs(spacings) do
                if math.abs(gap - sp[1]) <= 0.025 then sp_found, floor = sp[1], sp[2] end
            end
        end
        local j = i
        if sp_found then
            while j < #L and math.abs(evs[L[j + 1]].qn - evs[L[j]].qn - sp_found) <= 0.025 and #run < R.min_run_len do
                j = j + 1
                run[#run + 1] = L[j]
            end
        end
        local q0, q1 = evs[run[1]].qn, evs[run[#run]].qn
        if sp_found and #run >= R.min_run_len and (evs[L[i]].bpm or 120) >= floor
           and not (dl == 'H' and ExpertFaster(q0, q1, #run, sp_found)) then
            local worst, wv
            for _, k in ipairs(run) do
                local v = OnsetValue(evs[k])
                if not wv or v <= wv then worst, wv = k, v end
            end
            table.remove(evs, worst)
            removed = removed + 1
            local first = run[1]
            L = List()
            i = #L + 1
            for pos, k in ipairs(L) do if k >= first then i = pos; break end end
        else
            i = i + 1
        end
    end
    return removed
end

-- Medium/Easy at fast tempos (lower_eighth_hands_bpm): no three hand hits in a row an 8th
-- apart; a pair stays. Each window of three loses one hit's hands (its kick stays), left to
-- right; a roll's notes are not counted. Which hit goes is opts.eighth_hands:
--   'beats'  the "and"s first;
--   'hands'  the hit with the least important hand gems (GemRank; a beat wins a tie), so a
--            hat on the beat can go for two snares (`KY RY RY` -> `K RY RY`).
-- Easy from easy_no_pairs_bpm: a PAIR of hand hits an 8th apart loses one too, chosen the
-- same way; two equal hits (a tom pair `yb yb`) keep the first, the beat. A kick next to a
-- hand hit stays.
local function LowerEighthHands(evs, dl, mode)
    local from = (GEN_DRUMS_PARAMS.lower_eighth_hands_bpm or {})[dl]
    if not from then return 0 end
    mode = mode or GEN_DRUMS_PARAMS.lower_eighth_hands_default
    local function Hand(ev)
        for _, o in ipairs(ev.offs) do if o ~= KICK then return true end end
        return false
    end
    local function Value(ev)
        if mode == 'hands' then
            local top, n = 0, 0
            for _, o in ipairs(ev.offs) do
                if o ~= KICK then top = math.max(top, GemRank(ev, o)); n = n + 1 end
            end
            return top + 0.1 * n + (OnBeat(ev) and 0.5 or 0)
        end
        return OnsetValue(ev)
    end
    local n = 0
    local changed = true
    while changed do
        changed = false
        local list = {}
        for _, ev in ipairs(evs) do if Hand(ev) and not ev.rolled then list[#list + 1] = ev end end
        local pair_from = dl == 'E' and GEN_DRUMS_PARAMS.easy_no_pairs_bpm or nil
        for i = 1, #list - 1 do
            local a, b, c = list[i], list[i + 1], list[i + 2]
            local triple = c and (a.bpm or 120) >= from and b.qn - a.qn < 0.55 and c.qn - b.qn < 0.55
            if not triple then c = nil end
            if triple or (pair_from and (a.bpm or 120) >= pair_from and b.qn - a.qn < 0.55) then
                -- A hit whose removal leaves more than a quarter note with no hit at all (a
                -- kick under it stays, so it counts as a hit) is worth one GemRank step more
                -- (`R . b g | KG`: the "and" goes, not the beat-3 tom). A step, not a ban: in
                -- a backbeat on the "and"s every "and" opens such a gap. Only an end of the
                -- window can open one.
                local function Opens(ev)
                    for _, o in ipairs(ev.offs) do if o == KICK then return false end end
                    local k
                    for idx, e in ipairs(evs) do if e == ev then k = idx; break end end
                    local pv, nx
                    for j = k - 1, 1, -1 do if #evs[j].offs > 0 then pv = evs[j]; break end end
                    for j = k + 1, #evs do if #evs[j].offs > 0 then nx = evs[j]; break end end
                    return pv ~= nil and nx ~= nil and nx.qn - pv.qn > 1 + EPS
                end
                -- The least valuable; on a tie the middle one (two lone hits rather than a
                -- pair), then the earlier.
                local worst, wv
                for _, ev in ipairs(c and { b, a, c } or { a, b }) do
                    local v = Value(ev) + (Opens(ev) and 1 or 0)
                    if not wv or v < wv - 1e-9 then worst, wv = ev, v end
                end
                -- A pair of equal hits: the second goes (the gap step would otherwise keep
                -- whichever hit has more silence after it).
                if not c then
                    local function Sig(ev)
                        local h = {}
                        for _, o in ipairs(ev.offs) do if o ~= KICK then h[#h + 1] = o .. (IsTom(ev, o) and 't' or '') end end
                        return table.concat(h, ',')
                    end
                    if Sig(a) == Sig(b) then worst = b end
                end
                local keep = {}
                for _, o in ipairs(worst.offs) do if o == KICK then keep[#keep + 1] = o end end
                worst.offs = keep
                n = n + 1
                changed = true
                break
            end
        end
    end
    return n
end

-- From `from` BPM (Easy: easy_snare_run_bpm; Medium: medium_snare_run_bpm, off by default):
-- a run of easy_snare_run_min or more hand hits an 8th apart, each with a snare (a
-- build-up, `RY RY RY RY R R`), keeps only the hits on the beats - the "and"s lose their
-- hands (a kick there stays). Returns the number of hits changed.
local function SnareRuns(evs, from)
    if not from then return 0 end
    local min = GEN_DRUMS_PARAMS.easy_snare_run_min or 5
    local hands = {}
    for _, ev in ipairs(evs) do
        if not ev.rolled then
            for _, o in ipairs(ev.offs) do if o ~= KICK then hands[#hands + 1] = ev; break end end
        end
    end
    local n, i = 0, 1
    while i <= #hands do
        local j = i
        if Has(hands[i], SNARE) then
            while j < #hands and Has(hands[j + 1], SNARE) and math.abs(hands[j + 1].qn - hands[j].qn - 0.5) <= 0.025 do
                j = j + 1
            end
        end
        if j - i + 1 >= min and (hands[i].bpm or 120) >= from then
            for k = i, j do
                local ev = hands[k]
                if not OnBeat(ev) then
                    local keep = {}
                    for _, o in ipairs(ev.offs) do if o == KICK then keep[#keep + 1] = o end end
                    ev.offs = keep
                    n = n + 1
                end
            end
        end
        i = j + 1
    end
    return n
end

-- Last word on roll lanes: every roll covers an even number of gems in the finished tier
-- (later steps - kick pairing, the run breaker - can take a gem from a roll's notes after
-- Rolls evened it). A kick in a roll chord goes first, then the roll's first hit, and a
-- roll of one hit is emptied.
local function EvenRolls(evs, rolls)
    for _, sp in ipairs(rolls or {}) do
        local idx, gems = {}, 0
        for i, ev in ipairs(evs) do
            if ev.qn >= sp.qn - ROLL_TOL and ev.qn <= sp.qn_e + ROLL_TOL and #ev.offs > 0 then
                idx[#idx + 1] = i
                gems = gems + #ev.offs
            end
        end
        if gems % 2 == 1 then
            local fixed = false
            for _, i in ipairs(idx) do
                if #evs[i].offs > 1 and Drop(evs[i], KICK) then fixed = true; break end
            end
            if not fixed then
                for _, i in ipairs(idx) do
                    if #evs[i].offs == 1 then evs[i].offs = {}; break end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- The planner
----------------------------------------------------------------------

-- Build tier dl ('H', 'M', 'E') from `events`, the tier above. Returns (events, log).
-- log: upper, kept (onsets), notes, upper_notes, unflipped, rolls, retimed_bars,
--      runs_broken, easy_types = { ks, hands }, fallback (Medium, see below).
local PlanTier

-- A single-pedal Expert from a 2X Expert (events; offs 0 = kick), for Drums 2X when the song
-- has no usable PART DRUMS: exactly what General > Actions > "Remove 2x kicks" would leave on
-- PART DRUMS - DoubleBassPlan (actions_drums_2x.lua) finds the second-foot kicks and they
-- go; the hands stay. Any change to that rule belongs there, so the button and Generate
-- cannot disagree. Returns new events.
function GenDrumsSinglePedal(events)
    local out, kicks, qns, down, pos = {}, {}, {}, {}, {}
    for _, ev in ipairs(events) do
        local c = Copy(ev)
        out[#out + 1] = c
        if Has(c, KICK) then
            kicks[#kicks + 1] = c
            qns[#qns + 1] = c.qn
            down[#qns] = c.down or false
            pos[#qns] = c.bar_qn
        end
    end
    -- DoubleBassPlan asks only about the kicks' own positions.
    local by_qn, pos_qn, all_pos = {}, {}, true
    for k, q in ipairs(qns) do
        by_qn[q], pos_qn[q] = down[k], pos[k]
        if pos[k] == nil then all_pos = false end
    end
    local marks = DoubleBassPlan(qns, function(qn) return by_qn[qn] or false end,
        all_pos and function(qn) return pos_qn[qn] end or nil)
    for k, ev in ipairs(kicks) do if marks[k] then Drop(ev, KICK) end end
    return Compact(out)
end

-- Drums 2X (double bass pedal): PART DRUMS_2X carries the chart with both pedals, PART DRUMS
-- the same song for one pedal. Each 2X tier plays the kicks of the PART DRUMS tier one step
-- up - 2X Hard PART DRUMS Expert's, 2X Medium its Hard's, 2X Easy its Medium's - under the
-- 2X hands planned as usual (opts.keep_kicks skips the kick-choosing rules; what the tier
-- may not contain still goes). So a 2X tier never equals its PART DRUMS tier and is never
-- harder than the 2X tier above. Returns upper (the 2X tier above's events) with its kicks
-- replaced by single's (the PART DRUMS tier one step up); a kick where upper has no hit
-- becomes a hit of its own.
function GenDrums2xInput(upper, single)
    local x2, x1 = upper, single
    local out, at = {}, {}
    for _, ev in ipairs(x2) do
        local c = Copy(ev)
        Drop(c, KICK)
        out[#out + 1] = c
        at[math.floor(c.qn * 960 + 0.5)] = c
    end
    for _, ev in ipairs(x1) do
        if Has(ev, KICK) then
            local key = math.floor(ev.qn * 960 + 0.5)
            local c = at[key] or at[key - 1] or at[key + 1]
            if not c then
                c = Copy(ev)
                c.offs = {}
                out[#out + 1] = c
                at[key] = c
            end
            Add(c, KICK)
        end
    end
    table.sort(out, function(a, b) return a.qn < b.qn end)
    return Compact(out)
end

function GenDrumsPlanTier(dl, events, opts)
    opts = opts or {}
    if dl == 'H' then
        -- "Hard 8th runs" (opts.busy_drop: 1, 2 or nil = Auto from the first note's tempo).
        local n_drop = opts.busy_drop
        local auto = not n_drop
        if auto then n_drop = (events[1] and (events[1].bpm or 120) or 120) > GEN5_PARAMS.fast_8ths_bpm and 2 or 1 end
        local mode = GEN_DRUMS_PARAMS.hard_hat_drop
        local o2 = {}
        for k, v in pairs(opts) do o2[k] = v end
        if mode == 'always' then
            o2.hat_drops = n_drop
            local out, log = PlanTier(dl, events, o2)
            log.busy_drop, log.busy_auto = n_drop, auto
            return out, log
        end
        local out, log = PlanTier(dl, events, opts)
        local fb = GEN_DRUMS_PARAMS.hard_fallback_keep
        if mode == 'fallback' and fb and log.upper_notes > 0 and log.notes / log.upper_notes > fb then
            o2.hat_drops = n_drop
            local out2, log2 = PlanTier(dl, events, o2)
            log2.busy_drop, log2.busy_auto = n_drop, auto
            log2.hard_fallback = { before = log.notes }
            return out2, log2
        end
        return out, log
    end
    local out, log = PlanTier(dl, events, opts)
    -- Medium fallback: Medium's arms barely easier than Hard's (a song under
    -- lower_hat_quarter_bpm whose Hard is already simple) - plan it again with the
    -- hi-hat/ride on quarter notes whatever the tempo. The share counts HAND gems: counted
    -- with kicks, it moved with every kick rule while the arms stayed the same.
    local fb = GEN_DRUMS_PARAMS.medium_fallback_keep
    local min_bpm = GEN_DRUMS_PARAMS.medium_fallback_bpm or 0
    local hands = GEN_DRUMS_PARAMS.medium_fallback_on == 'hands'
    local kept, upper = log.notes, log.upper_notes
    if hands then kept, upper = log.hands, log.upper_hands end
    if dl == 'M' and fb and upper > 0 and kept / upper > fb and (log.median_bpm or 0) >= min_bpm then
        local o2 = {}
        for k, v in pairs(opts) do o2[k] = v end
        o2.all_quarters = true
        local out2, log2 = PlanTier(dl, events, o2)
        log2.fallback = { before = log.notes, before_hands = log.hands }
        return out2, log2
    end
    return out, log
end

PlanTier = function(dl, events, opts)
    opts = opts or {}
    local ctx = opts.ctx or {}
    local log = { upper = #events, kept = 0, notes = 0, upper_notes = 0, hands = 0, upper_hands = 0,
                  unflipped = 0, rolls = 0,
                  retimed_bars = {}, runs_broken = 0, easy_types = { ks = 0, hands = 0 },
                  tom_markers = {}, tom_conflict_bars = {},
                  -- The fields the 5-lane result lines read.
                  chords_reduced = 0, recolored = 0, shortened = 0, cut = 0 }
    if dl ~= 'H' then events, log.expert_runs = ExpertForRewrittenRuns(events, opts.expert) end
    local bpms = {}
    for _, ev in ipairs(events) do
        log.upper_notes = log.upper_notes + #ev.offs
        for _, o in ipairs(ev.offs) do if o ~= KICK then log.upper_hands = log.upper_hands + 1 end end
        bpms[#bpms + 1] = ev.bpm or 120
    end
    table.sort(bpms)
    log.median_bpm = bpms[#bpms // 2 + 1]
    -- Hits with more than two hand gems in the tier above: unplayable, a charting mistake to
    -- report (the result lists their bars).
    log.too_many_gems = {}
    for _, ev in ipairs(events) do
        local hands = 0
        for _, o in ipairs(ev.offs) do if o ~= KICK then hands = hands + 1 end end
        if hands > 2 then log.too_many_gems[#log.too_many_gems + 1] = ev.qn end
    end
    local evs = Annotate(events, ctx)
    -- Positions (1/24 QN) of the incoming tier's cymbal-only hits (EasyTwoHandAnds).
    local upper_cym_only = {}
    for _, ev in ipairs(evs) do
        local drum = Has(ev, SNARE)
        for _, o in ipairs(ev.offs) do if IsTom(ev, o) then drum = true end end
        if HasCymbal(ev) and not drum then upper_cym_only[math.floor(ev.qn * 24 + 0.5)] = true end
    end
    -- ... and of its kicks (CymbalChangesQuarter).
    local upper_kick = {}
    for _, ev in ipairs(evs) do if Has(ev, KICK) then upper_kick[math.floor(ev.qn * 24 + 0.5)] = true end end

    if (opts.unflip or 'H') == dl then evs = Unflip(evs, log) end
    evs = Rolls(evs, dl, log)

    if dl == 'H' then
        local upper8 = UpperEighths(events)
        evs, ctx = RetimeFills(evs, opts.fast_runs, log, ctx, opts.keep_cymbals)
        evs = HardSixteenths(evs)
        log.and_backbeat = HardAndBackbeat(evs, DRUMS_RULES.general_hard_8th_bpm)
        evs = Compact(evs)
        -- opts.keep_kicks: the kicks are already the ones this tier should play (Drums 2X
        -- takes them from PART DRUMS one tier up, GenDrums2xInput).
        if not opts.keep_kicks then
            KickUnderSnare(evs, 'H')
            local P = GEN_DRUMS_PARAMS
            local figure = HardKickFigures(evs)
            local Busy = BusyHands(evs)
            ThinKicks(evs, function(ev, pv)
                -- Busy hands' half bar reaches back only within the kick's own bar: a busy
                -- downbeat must not clear the last half of the bar before's kick line.
                local same_bar = not pv
                    or math.abs((ev.qn - (ev.bar_qn or 0)) - (pv.qn - (pv.bar_qn or 0))) < EPS
                if P.hard_kick_gap_busy and Busy(ev) and same_bar and not figure[ev] then return P.hard_kick_gap_busy end
                if (ev.bpm or 120) >= P.hard_kick_gap_fast_bpm then return P.hard_kick_gap_fast end
                -- A kick off the beat needs more room than one on it - on a 16th as on an
                -- 8th (kicks on every 16th off-beat, an 8th apart, keep every other one).
                local class = Gen5BeatClass(ev)
                if class == '8th' or class == '16th' then return P.hard_kick_gap_8th end
                return P.hard_kick_gap
            end)
            if GEN_DRUMS_PARAMS.hard_eighth_kicks then log.eighth_kicks = HardEighthKicks(evs, upper8) end
            if GEN_DRUMS_PARAMS.hard_end_of_bar_kick then EndOfBarKick(evs, upper8) end
            if GEN_DRUMS_PARAMS.hard_paired_kick then PairedKick(evs, upper8) end
        end
        if opts.hat_drops and opts.hat_drops > 0 then log.hat_drops = HardHatDrops(evs, opts.hat_drops) end
        -- More than two hand gems on one hit is unplayable (two hands, one foot) and never in an
        -- official chart, on any tier: a charting mistake in the tier above (listed by the
        -- planner's start, log.too_many_gems). Hard keeps the kick and two hand gems - a
        -- Yellow/Blue cymbal goes first.
        for _, ev in ipairs(evs) do
            local hands = 0
            for _, o in ipairs(ev.offs) do if o ~= KICK then hands = hands + 1 end end
            while hands > 2 do
                if not (Drop(ev, YEL) or Drop(ev, BLU)) then
                    for k = #ev.offs, 1, -1 do if ev.offs[k] ~= KICK then table.remove(ev.offs, k); break end end
                end
                hands = hands - 1
            end
        end
        MaxGems(evs, 3)
    else
        if dl == 'E' then
            -- The backbeat on the "and"s from easy_and_backbeat_bpm, the hands on the "and"s
            -- only (`G R Y RY Y RY Y RY` -> `G R . RY . RY . RY`). Tested on the bar as Medium
            -- has it, before Easy's own steps: its quarter-note fills can take a beat snare out
            -- of a bar and make it look like the groove.
            local and_from = GEN_DRUMS_PARAMS.easy_and_backbeat_bpm
            if and_from then log.and_backbeat = HardAndBackbeat(evs, and_from) end
        end
        local fill_grid = 0.5
        if dl == 'E' and SongTempo(evs, ctx) >= DRUMS_RULES.roll_easy_quarter_bpm then fill_grid = 1.0 end
        -- Easy's quarter-note fills: a run continues across a quarter-note gap, so a fill
        -- Medium broke into pieces (its runs of four 8ths lose one) is still one run and goes
        -- to quarters from its start.
        evs = GridFillRuns(evs, fill_grid >= 1 and 1.0 or 0.5 - EPS, fill_grid)
        evs = LowerHands(evs, opts.all_quarters)
        if dl == 'M' then
            KickUnderSnare(evs, 'M')
            log.sandwiched = SandwichedHats(evs, true)
            log.drum_changes = DrumChanges(evs)
            log.tom_pairs = MediumTomPairs(evs)
            evs = Compact(evs)   -- a repeated tom pair may have been emptied
            Between(evs, opts.between or 'beats')
            AfterCrash(evs)
        else
            EasyBeats(evs, ctx.sections, log)
            log.sandwiched = SandwichedHats(evs, false)
            log.two_hand_ands = EasyTwoHandAnds(evs, upper_cym_only)
            log.drum_changes = DrumChanges(evs)
            log.before_crash = EasyBeforeCrash(evs)
        end
        -- Three-limb hits lose their kick BEFORE the kicks are spaced, so the spacing only
        -- chooses among kicks that survive (otherwise it could keep a KRY's kick over the
        -- neighbouring one, then lose it to the two-gem limit, leaving neither).
        MaxGems(evs, 2)
        LowerKicks(evs, opts.keep_kicks)
    end
    if dl ~= 'H' then OneKickPerBar(evs) end
    evs = Compact(evs)
    DoubleCrashes(evs)
    log.runs_broken = BreakEighthRuns(evs, dl, dl == 'H' and events or nil)
    if dl ~= 'H' then
        log.snare_run_bpm = dl == 'E' and GEN_DRUMS_PARAMS.easy_snare_run_bpm or GEN_DRUMS_PARAMS.medium_snare_run_bpm
        log.snare_runs = SnareRuns(evs, log.snare_run_bpm)
        evs = Compact(evs)
    end
    if dl ~= 'H' then
        log.eighth_hands = LowerEighthHands(evs, dl, opts.eighth_hands)
        log.eighth_hands_mode = opts.eighth_hands or GEN_DRUMS_PARAMS.lower_eighth_hands_default
        evs = Compact(evs)
    end
    if dl == 'E' then evs, log.lone_ands = EasyLoneAnds(evs) end
    -- After the run breaker: it can remove the hit that stood right before a crash, and the
    -- one before it then needs the treatment.
    if dl ~= 'H' then log.tom_before_crash = TomBeforeCrash(evs) end
    if dl ~= 'H' then log.cym_changes = CymbalChanges(evs) end
    if dl == 'E' then log.cym_changes_quarter = CymbalChangesQuarter(evs, upper_kick) end
    EvenRolls(evs, ctx.rolls)
    evs = Compact(evs)
    -- A roll lane whose marker allows Hard (velocity 41-50) plays Expert's notes as they are.
    if dl == 'H' then evs, log.hard_lanes = GenKeepHardLanes(evs, events, ctx.rolls) end

    for _, ev in ipairs(evs) do
        ev.fill, ev.roll, ev.disco, ev.tom, ev.rolled, ev.kick_dropped, ev.and_beat = nil, nil, nil, nil, nil, nil, nil
        log.notes = log.notes + #ev.offs
        for _, o in ipairs(ev.offs) do if o ~= KICK then log.hands = log.hands + 1 end end
    end
    log.kept = #evs
    -- The marker context the next tier is planned with (Hard's rewrite may have changed
    -- the tom markers: log.tom_markers).
    log.ctx = ctx
    return evs, log
end
