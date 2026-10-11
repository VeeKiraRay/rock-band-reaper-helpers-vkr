-- Difficulty > Generate: Drums. Builds Hard, Medium or Easy from the tier above.
--
-- PURE: no r, no S. Load after difficulty_generate_retime.lua and
-- actions_difficulty_drums_checks.lua (it reads DRUMS_RULES at call time, so Validate
-- and Generate share one set of thresholds).
--
-- Drums are reduced limb by limb, not by the band's one-rhythm model
-- (difficulty_generate_rhythm.lua): a drum onset is several limbs at once, and each limb
-- thins on its own terms - the kick goes fastest, the snare backbeat stays, the right
-- hand drops from 8ths to quarters with tempo. Drums neither follow nor lead the other
-- instruments (user decision 2026-10-09; drums leading the band is a later prototype).
--
-- Official charts never move a drum note (RB3 DLC, 482 songs: 0.03% of Hard onsets are
-- not on an Expert onset), so every rule here deletes or relanes. The one exception is the
-- "Hard fast runs" setting: fills and tom/snare runs go through the same one-grid-slower
-- rewrite as Guitar's fast runs (Gen5RetimeDenseRuns), a user choice that keeps more of a
-- fill's speed than official's 8th grid. 'thin' gives the official behaviour.
--
-- Input event: { qn, qn_e, offs, bpm, bar_qn, bar_len, pulse, down }, offs the gem
-- offsets 0 Kick, 1 Red (snare), 2 Yellow, 3 Blue, 4 Green, ascending.
-- opts:
--   fast_runs  'rewrite' | 'auto' | 'thin' (Hard only; GEN5_PARAMS.fast_runs_default)
--   unflip     the tier that un-flips Expert's disco beats ('H' default, 'none')
--   between    Medium kick/snare between hi-hat notes: 'beats' (default, keep those on a
--              beat), 'none' (the RBN doc: never), 'keep'
--   ctx        { fills, rolls, disco = { { qn, qn_e }... }, toms = { [2|3|4] = spans },
--                sections = { { qn, name }... } } - all optional, in quarter notes

local EPS = GEN5_EPS
-- Roll lane membership: Validate takes the notes from 1 ms before the lane's start to 1 ms
-- after its end (seconds). 0.004 QN is 1 ms at 240 BPM, so a note the planner counts in a
-- roll is one Validate counts too, at any song tempo.
local ROLL_TOL = 0.004
local KICK, SNARE, YEL, BLU, GRN = 0, 1, 2, 3, 4

-- Tunables that are this planner's own choices (the RBN tempo rules are DRUMS_RULES).
-- Every number is from the RB3 DLC probe over official charts (development songs,
-- hold-out excluded) unless marked as a user rule.
GEN_DRUMS_PARAMS = {
    -- Hard keeps a 16th tom/snare run at full speed only when it lasts at most this many
    -- beats (RBN Hard: "Such passages should be authored only if they last a beat or two").
    hard_run_beats = 2,
    -- Hard: two kicks never closer than this (RBN: "remove kicks on adjacent 8th or 16th
    -- notes" as a first step). Official Hard keeps 60% of 8th kicks, 33% of 16th ones.
    hard_kick_gap = 0.5,
    -- ... and from this tempo, a quarter note between kicks (official Hard keeps 46% of
    -- 8th kicks at 140+ BPM, 65% below).
    hard_kick_gap_8th = 0.75,
    hard_kick_gap_fast_bpm = 140,
    hard_kick_gap_fast = 0.75,
    -- Drop the kick under the snare (off the bar line)? OFF - user decision 2026-10-09: no
    -- RBN rule forbids kick + snare together below Easy, and the kick on the beat carries
    -- the groove; Hard thins the off-beat kicks around it instead (hard_kick_gap_8th).
    -- Official charts mostly do drop it, but per song: of 222 songs with 20+ such hits,
    -- 156 drop it almost always (Hard keeps < 5%), 15 keep it almost always (95%+), the
    -- rest mix; overall Hard keeps 21.5% (bar line 43%, beat 22%, off-beat 8%).
    kick_under_snare = { H = false, M = false },
    -- Medium/Easy: kicks a quarter note apart, half a bar from 140 BPM (official Medium
    -- keeps 66% of Hard's beat kicks below 140 BPM, 42% above; 1.3 kicks a bar at 120-139).
    lower_kick_gap = 1.0,
    lower_kick_gap_fast_bpm = 140,
    lower_kick_gap_fast = 2.0,
    -- ... and half a bar when the hands are busy around the kick: a hand hit an 8th before
    -- AND after it (user idea 2026-10-09). The oom-pah groove KY RY KY RY ... (370 Hard
    -- bars in 22 official songs, all under 140 BPM) becomes KY RY Y RY KY RY Y RY on
    -- official Medium 154 times, stays as Hard 13 times.
    lower_kick_gap_busy = 2.0,
    -- Hard too (TRIAL 2026-10-10): official Hard turns Expert's kick on every beat under
    -- steady 8th hats into kicks on 1 and 3 in 49% of bars (all four kept 23%; 1,400 bars
    -- at 100-139 BPM). nil = off.
    hard_kick_gap_busy = 2.0,
    -- ... and the bar's last-beat kick comes back when that spacing removed it (EndOfBarKick).
    hard_end_of_bar_kick = true,
    -- ... and one 8th kick paired with beat 3's kick comes back (PairedKick).
    hard_paired_kick = true,
    -- Hard drops hat-only "and"s in steady 8th-hat bars per "Hard 8th runs" (HardHatDrops):
    -- 'always' (every such bar, as the band's busy bars), 'fallback' (only when Hard would
    -- keep more than hard_fallback_keep of Expert's notes), 'off'.
    hard_hat_drop = 'fallback',
    hard_fallback_keep = 0.95,
    -- Medium/Easy hi-hat/ride stream to quarter notes from this tempo (2026-10-10). The RBN
    -- doc says 140 (DRUMS_RULES.general_medium_8th_bpm, used when nil); official Medium
    -- switches at 130: steady 8th hats stay all 8 in 54% of bars at 125-129 BPM, 18% at
    -- 130-134 (quarters 67%), 3% at 135-139. Per song, Medium then keeps 76% of Hard's
    -- notes at 125-134 BPM (official 76%) instead of 86%.
    lower_hat_quarter_bpm = 130,
    -- Medium keeping more than this share of Hard's hand gems (kicks not counted) puts its
    -- hi-hat/ride on quarter notes at any tempo (GenDrumsPlanTier). nil = off.
    medium_fallback_keep = 0.93,
    medium_fallback_bpm = 120,
    medium_fallback_on = 'hands',   -- what the share counts: 'hands' (every gem but the kick) | 'notes'      -- only songs whose median tempo (of the tier above) is this or more
    -- Medium: from this tempo the hand that just crashed gets an 8th to reset (RBN "at
    -- faster tempos, remove gems immediately after a crash"; official Medium keeps the
    -- next note 66% below 120 BPM, 32% at 120-139, 5% above).
    after_crash_bpm = 120,
    -- Roll lanes (126/127) are Expert-only in official charts (all 226 markers velocity
    -- > 50); the lower tiers play the roll on a grid: Hard 16ths below
    -- DRUMS_RULES.roll_hard_16th_bpm, else 8ths (official 38% / 46%); Medium 8ths below
    -- this tempo, else quarters; Easy quarters.
    medium_roll_8th_bpm = 120,
    -- Easy fills go to quarter notes from DRUMS_RULES.roll_easy_quarter_bpm.
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
-- roll, a fill under a fill lane).
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
-- least gap(ev) apart. Returns a set of kept list indexes.
local function KeepByGap(list, gap, weight)
    local n = #list
    local best, take, prev = { [0] = 0 }, {}, {}
    for i = 1, n do
        local j = i - 1
        while j >= 1 and list[i].qn - list[j].qn < gap(list[i]) - EPS do j = j - 1 end
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

-- RBN Hard: "Un-flip any 'Disco' beats ... put the hihat gems back on yellow, snares back
-- on red, delete the in-between 16th notes, and add a yellow hihat gem above the snare
-- gem." Inside Expert's [mix 3 drumsNd] spans Red is the hi-hat and Yellow the snare.
-- Official lower tiers never carry a "d" mix event (RB3 DLC: 0 of ~1500), so the tier
-- that un-flips is Hard unless the user picks another (CAT offers the same choice).
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
        local gems = 0
        for _, i in ipairs(keep) do gems = gems + #evs[i].offs end
        -- An even number of hits (RBN Hard: "16th note rolls with an uneven number of hits
        -- require an extra bit of advanced reading ... so even them out"): trim the start,
        -- so the roll still lands where Expert's does.
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
                -- Nothing a grid step away: a roll of one hit is no roll (official Medium
                -- and Easy often leave the lane empty or with its landing note only).
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

-- Runs of fill-like onsets (toms/snare, no cymbal, not under a roll lane) at least 3
-- long, each within `step` of the next. Returns { { first, last }... } index pairs.
local function FillRuns(evs, step)
    local runs, i = {}, 1
    while i <= #evs do
        if FillLike(evs[i]) and not evs[i].rolled then
            local j = i
            while j < #evs and FillLike(evs[j + 1]) and not evs[j + 1].rolled
                  and evs[j + 1].qn - evs[j].qn <= step + EPS do
                j = j + 1
            end
            if j - i + 1 >= 3 then runs[#runs + 1] = { i, j } end
            i = j + 1
        else
            i = i + 1
        end
    end
    return runs
end

-- Hard: fast fill runs rewritten one grid slower (Gen5RetimeDenseRuns, the Guitar/Bass/
-- Keys rewrite and its "Hard fast runs" setting). Only runs of 16ths (and 16th triplets
-- below roll_hard_16th_bpm, where Hard may still play 16ths) are offered to it; grooves
-- with cymbals are never rewritten - official Hard thins them to 8ths.
local function RetimeFills(evs, mode, log, ctx)
    if (mode or GEN5_PARAMS.fast_runs_default) == 'thin' then return evs end
    local any = false
    for _, run in ipairs(FillRuns(evs, 0.25)) do
        local a, b = run[1], run[2]
        local step = evs[a + 1].qn - evs[a].qn
        -- 16ths -> 8th triplets at any tempo; 16th triplets -> 16ths only where Hard may
        -- play 16ths. Anything faster (32nds -> 16th triplets) is still too fast for Hard
        -- and is thinned instead.
        if step >= 0.25 - EPS
           or (step >= 1 / 6 - EPS and (evs[a].bpm or 120) < DRUMS_RULES.roll_hard_16th_bpm) then
            for k = a, b do evs[k].fill_run = true end
            any = true
        end
    end
    if not any then return evs end
    local out, bars = Gen5RetimeDenseRuns(evs, {
        gap  = function(ev) return ev.fill_run and 0.5 or GEN5_MIN_LEN_QN end,
        eps  = EPS, mode = mode })
    log.retimed_bars = bars
    for _, ev in ipairs(out) do
        ev.fill_run = nil
        if ev.retimed then
            -- A fresh event (moved): its own copy of the gems, and the markers at its new spot.
            local offs = {}
            for i, o in ipairs(ev.offs) do offs[i] = o end
            ev.offs = offs
            Mark(ev, ctx)
        end
    end
    return out
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
        -- beats on a tie. An 8th run that starts and ends on "and"s keeps its "and"s
        -- (molto bar 22's snare accents, Rb R R -> Rb . R on Easy, not . R .). Costs 0.3 of
        -- Easy's chain F1 against official, which puts such quarters on the beats more often.
        -- Never on Medium's 8th grid: its shifted phase would be the 16th "e"s and "a"s.
        local Phase = OnGrid
        if grid >= 1 - EPS and shifted > on then Phase = OnShifted; on = shifted end
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

-- Hard's 16th rules, for every onset not already settled (rolled, retimed).
--   * at or above DRUMS_RULES.roll_hard_16th_bpm: nothing off the 8th / 8th-triplet grid
--     (RBN: avoid 16ths at 140+; official keeps 3-5% of them);
--   * below it: a tom/snare run of 16ths stays only if it lasts hard_run_beats or less,
--     else it goes to the 8th grid; hi-hat/ride 16ths in a stream go (right-hand
--     timekeeping on 8ths); a lone snare 16th stays on the "a" and goes on the "e" (RBN:
--     "remove about half of them in a way that is consistent").
local function HardSixteenths(evs)
    local R, P = DRUMS_RULES, GEN_DRUMS_PARAMS
    local in_run = {}
    for _, run in ipairs(FillRuns(evs, 0.25)) do
        local a, b = run[1], run[2]
        local long = evs[b].qn - evs[a].qn + 0.25 > P.hard_run_beats + EPS
        for k = a, b do in_run[k] = long and 'long' or 'short' end
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
-- before it loses its hi-hat/ride too (a hit left with nothing goes). Official Easy in that
-- case (373): the "and" keeps only its drum 87%; the beat before keeps its cymbal 11%
-- (drum only 36%, gone 53%). The right hand no longer moves hat -> drum on consecutive
-- 8ths. User decision 2026-10-10. NOT where Medium was already on quarters (molto after its
-- Medium fallback): there official Easy keeps the "and" as Medium has it - hat + drum 72%
-- (ride 86%), the beat before keeps its cymbal 84% - and firing there cost Easy's ride
-- 5 points of recall. upper_cym_only: positions (1/24 QN) of Medium's cymbal-only hits.
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
-- above lower_hat_quarter_bpm (RBN Medium: "The player's right hand shouldn't be expected
-- to keep time with 8th notes if the song is 140bpm or faster"; official switches at 130),
-- or at any tempo with all_quarters (Medium's fallback). Triplet off-beats go unless they
-- stand alone (official Medium keeps 16% of them).
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
                -- A two-hand "and" (hat + snare/tom) keeps its hat: official Medium in such
                -- quarter-hat passages keeps both 44% / drum only 27% / drops it 25% under
                -- 130 BPM (user decision 2026-10-10; at 130+ official drops the whole hit 58% -
                -- tempo split left for the user's fast-song testing). Easy then takes the hat
                -- off it (EasyTwoHandAnds).
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

-- Hard: a bar whose busy-hands spacing left no kick on its last beat or the "and" after it
-- gets the last-beat kick back when Expert had one there - the end of the bar keeps a
-- faster kick pattern than its start (user idea 2026-10-10). Official Hard, steady 8th
-- hats at 100-139 BPM, Expert kicks on 1, 3, 4 and the "and" of 4 (316 bars): beat 4
-- kept 33%, the "and" 27%, both 1%, neither 39%. With no Expert kick on beat 4 the "and"
-- alone stays only 34% of the time, so that case is left thinned.
-- Hard: a bar of steady 8th hi-hats/rides loses n_drop of its hat-only "and"s - the drums
-- side of the band's "Hard 8th runs" setting (busy_drop: 1 or 2; Auto = 2 when the song
-- starts above GEN5_PARAMS.fast_8ths_bpm). Order: the "and" of 1 when the downbeat is a
-- crash (the hand comes back from the crash), then the "and" of 4, then the "and" of 2 -
-- so after a crash, Drop 1 takes the "and" of 1 and Drop 2 the "and"s of 1 and 4. Only a
-- hat-only hit loses its hat (with a kick or snare it stays; official drops those 5% vs
-- 13%); a slot that is not hat-only is skipped. User rule 2026-10-10. Official Hard, steady
-- 8th hats at 130-169 BPM: a crash on 1 -> the "and" of 1 goes 41% (100% of bars losing
-- one); otherwise each "and" ~13%, a single drop the "and" of 1 49% / of 4 38%.
-- Returns the number of hats removed.
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

-- Hard: the busy-hands spacing keeps the kicks on 1 and 3; one 8th kick paired with beat
-- 3's kick - the one leading into it (the "and" of 2), else the one right after it (the
-- "and" of 3) - comes back. Not when Expert has both: then official Hard keeps 1 and 3 only.
-- Official Hard, steady 8th hats: Expert K . . K K . . . kept as is 93% at 140+ BPM (58 bars),
-- 55% under 140 (766); K . . . K K . K -> K . . . K K . . 46% at 140+ (76), 62% under 140
-- (216); K . . K K K . . -> K . . . K . . . 83-100% (19). User question 2026-10-10 (pojat).
local function PairedKick(evs)
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
    for _, b in pairs(bars) do
        local mid, pre, post = b.mid, b.before, b.after
        if mid and Has(mid, KICK) then
            local pre_k = pre and pre.kick_dropped and not Has(pre, KICK)
            local post_k = post and post.kick_dropped and not Has(post, KICK)
            if pre_k and not post_k then Add(pre, KICK)
            elseif post_k and not pre_k then Add(post, KICK) end
        end
    end
end

local function EndOfBarKick(evs)
    local bars = {}
    for _, ev in ipairs(evs) do
        if ev.bar_qn and ev.bar_len then
            local key = ('%.3f'):format(ev.qn - ev.bar_qn)
            local b = bars[key] or {}
            bars[key] = b
            local last = ev.bar_len - (ev.pulse or 1)
            if math.abs(ev.bar_qn - last) <= EPS then b.last = ev
            elseif math.abs(ev.bar_qn - (last + 0.5)) <= EPS then b.after = ev end
        end
    end
    for _, b in pairs(bars) do
        local ev = b.last
        if ev and ev.kick_dropped and not Has(ev, KICK) and not (b.after and Has(b.after, KICK)) then
            Add(ev, KICK)
        end
    end
end

-- Medium/Easy kicks (RBN Medium/Easy and Validate): on quarter notes above
-- DRUMS_RULES.kick_grid_bpm, at most one per bar from kick_per_measure_bpm, never under
-- an off-beat crash (Medium: "Syncopated or off-beat crashes ... leave them with no kick").
local function LowerKicks(evs)
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
    local P = GEN_DRUMS_PARAMS
    local Busy = BusyHands(evs)
    ThinKicks(evs, function(ev)
        if (ev.bpm or 120) >= P.lower_kick_gap_fast_bpm then return P.lower_kick_gap_fast end
        if Busy(ev) then return P.lower_kick_gap_busy end
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

-- Kicks inside drum fills (the fill lane): official charts thin them, not remove them -
-- a fill with 4-6 Expert kicks keeps 3.2 on Hard, 2.1 on Medium, 0.6 on Easy (64-84% of
-- Easy fills keep none). Easy: no kicks in a fill. Hard and Medium
-- thin fill kicks no differently from any other kicks - official Hard keeps ~67% of a
-- fill's kicks, its share everywhere - and a fill lane usually covers an ordinary groove
-- bar (the fill only shows when overdrive is ready): a quarter-note spacing there took
-- pojat_lemmikkih's "and" of 2 kick in every fill-lane bar (2026-10-10). Dropping it left
-- the offline evaluation unchanged (Hard kick recall 73 -> 75).
local function EasyFillKicks(evs)
    for _, ev in ipairs(evs) do if ev.fill and #ev.offs > 1 then Drop(ev, KICK) end end
    for _, ev in ipairs(evs) do if ev.fill and Has(ev, KICK) then ev.offs = {} end end
end

----------------------------------------------------------------------
-- Medium: limb independence, crashes, three-limb hits
----------------------------------------------------------------------

-- RBN Medium: "No kicks or snares in between hihat/ride (ie, right hand time keeping)
-- gems." Official Medium is looser - a kick or snare on the beat stays (83-94% of them),
-- one on an 8th mostly goes (22% stay), on a 16th it goes (2%). mode 'beats' keeps the
-- ones on a beat (official), 'none' removes them all (the doc), 'keep' leaves them.
-- The "hi-hat/ride" of the rule is right-hand timekeeping: a Yellow/Blue cymbal. A crash is
-- not (molto bar 82: hat, snare on the "and" of 4, crash on the next downbeat - the snare
-- went because the crash counted as a hat; official Medium under 130 BPM keeps such a snare
-- 76%, Easy 85%).
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
-- alternate hat and snare on every 8th, and with a tom in the accent both hands are on the
-- accent and the right hand must leap back to the hat (molto_c_love_for_sale bar 22:
-- Y Rb Y Rb Y). Official (55 songs): Medium, accents with a tom, keeps the accents and
-- drops the hat between 43 of 55 times (12 drop the tom); Easy at 120+ BPM drops the hat
-- 18 of 24 times. need_tom: Medium - snare-only accents there are Between's job (official
-- Medium drops the snares instead). Crashes stay: a crash on the beat is an accent too.
-- User decision 2026-10-10: both tiers, the official way.
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

-- Two two-hand hits (one cymbal + one drum each) an 8th apart whose drum changes - tom to
-- snare, snare to tom, tom to another tom: the first loses its drum and keeps its cymbal,
-- so the drum hand gets a beat to move (molto bar 34: Yb RY -> Y RY). Official Medium,
-- under 130 BPM: tom -> snare, the first drops its tom 94% (45 of 48); snare -> tom, the
-- first drops its snare 67% (10 of 15). Medium and Easy (user decision 2026-10-10).
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
-- keeps its drum, so the right hand is free to reach the crash (molto bar 18: RY | G ->
-- R | G). A user rule (2026-10-10): official Easy under 130 BPM keeps that hat 66% and drops
-- it 34% (n=422); official Medium drops it 39% under 130 BPM and almost always from 130 (hat
-- kept 1%, the whole hit gone 57%) - Medium's tempo split waits for the fast-song testing.
-- A hat-only hit before a crash is left alone (official Easy keeps it 74% under 130 BPM).
local function EasyBeforeCrash(evs)
    local n = 0
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

-- A snare + tom hit (both hands on drums, no cymbal) a quarter note or less before a crash
-- loses its tom, so the hand gets to the crash (pojat_lemmikkih bar 74's last Rg into bar
-- 75's crash). Official Medium drops that tom 79% a quarter before / 69% an 8th before
-- under 130 BPM, 70% a quarter before at 130+ (n=669); official Easy has few left. Medium
-- and Easy (user request 2026-10-10).
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

-- The hand that just crashed resets: from after_crash_bpm the cymbal/tom gems of an
-- onset an 8th or less after a crash accent go (the snare - the other hand - and the kick
-- stay). An accent, not a ride on the crash: one with no crash an 8th before it.
local function AfterCrash(evs)
    local P = GEN_DRUMS_PARAMS
    for i = 2, #evs do
        local pv, ev, pp = evs[i - 1], evs[i], evs[i - 2]
        local accent = IsCymbal(pv, GRN) and Has(pv, GRN)
            and not (pp and Has(pp, GRN) and pv.qn - pp.qn <= 0.5 + EPS)
        if accent and (ev.bpm or 120) >= P.after_crash_bpm and ev.qn - pv.qn <= 0.5 + EPS and not ev.rolled then
            for o = YEL, GRN do Drop(ev, o) end
        end
    end
end

-- At most `max` gems: a three-limb hit loses the kick (official KRY -> RY), anything
-- bigger then its non-crash cymbal.
local function MaxGems(evs, max)
    for _, ev in ipairs(evs) do
        if #ev.offs > max then Drop(ev, KICK) end
        while #ev.offs > max do
            if not (Drop(ev, YEL) or Drop(ev, BLU)) then table.remove(ev.offs) end
        end
    end
end

----------------------------------------------------------------------
-- Easy: one beat type per section
----------------------------------------------------------------------

-- RBN Easy: "the player either is playing a 2-hand beat with no kick, or a beat with just
-- kick and snare ... less intense sections should be authored a kick/snare beat, and more
-- rocking sections should be authored as a 2-hand beat." Official Easy (RB3 DLC) picks it
-- per section, and the section name with the right hand's cymbal predicts it: a verse kept
-- on the hi-hat is kick + snare 74% of the time, every other section (and a verse on the
-- ride or crash) is mostly the 2-hand beat (chorus 89%, outro 90%, intro 80%). A section
-- whose Medium has no cymbal at all is kick + snare by necessity.
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
        local c = count[k] or { [YEL] = 0, [BLU] = 0, [GRN] = 0 }
        count[k] = c
        for _, o in ipairs(ev.offs) do if IsCymbal(ev, o) then c[o] = c[o] + 1 end end
    end
    local types = {}
    for k, s in ipairs(secs) do
        local c = count[k] or { [YEL] = 0, [BLU] = 0, [GRN] = 0 }
        local total = c[YEL] + c[BLU] + c[GRN]
        local hat = c[YEL] > 0 and c[YEL] >= c[BLU] and c[YEL] >= c[GRN]
        types[k] = (total == 0 or (GenDrumsIsVerse(s.name) and hat)) and 'ks' or 'hands'
    end
    return SecIndex, types, secs
end

local function EasyBeats(evs, sections, log)
    local SecIndex, types = SectionTypes(evs, sections)
    -- Bars with no cymbal at all play kick + snare whatever their section.
    local bar_cym = {}
    for _, ev in ipairs(evs) do
        local key = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
        if HasCymbal(ev) then bar_cym[key] = true end
    end
    local seen = {}
    for _, ev in ipairs(evs) do
        local k = SecIndex(ev.qn)
        local t = types[k]
        if not seen[k] then seen[k] = true; log.easy_types[t] = log.easy_types[t] + 1 end
        if not ev.rolled then
            local bar = ('%.3f'):format(ev.qn - (ev.bar_qn or 0))
            if t == 'ks' then
                -- Kick + snare: the hi-hat/ride goes, a crash stays (instead of its kick -
                -- RBN Easy: "author the crashes instead of the kicks"), toms stay.
                for o = YEL, BLU do if IsCymbal(ev, o) then Drop(ev, o) end end
            elseif bar_cym[bar] then
                Drop(ev, KICK)
            end
        end
    end
    -- No gem paired with a kick (RBN Easy): the other gem wins.
    for _, ev in ipairs(evs) do if #ev.offs > 1 then Drop(ev, KICK) end end
end

----------------------------------------------------------------------
-- Every tier: double crashes, constant 8ths
----------------------------------------------------------------------

-- A Green + Yellow/Blue double crash needs a quarter note of space before it (Validate,
-- H/M/E; RBN Hard "unless there is plenty of empty space around them"), else it is a
-- single Green.
local function DoubleCrashes(evs)
    for i, ev in ipairs(evs) do
        if #ev.offs == 2 and ev.offs[2] == GRN and (ev.offs[1] == YEL or ev.offs[1] == BLU) then
            local pv = evs[i - 1]
            if not pv or ev.qn - pv.qn < 0.95 then table.remove(ev.offs, 1) end
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

-- No run of min_run_len onsets an 8th apart at or above the tier's tempo (Validate:
-- Hard general_hard_8th_bpm, Medium/Easy general_medium_8th_bpm; RBN Hard "the upper
-- threshold for playing a constant stream of 8th notes at this difficulty is about
-- 170bpm"). Each run of four loses its least valuable onset.
local function BreakEighthRuns(evs, dl)
    local R = DRUMS_RULES
    local bpm_lim = dl == 'H' and R.general_hard_8th_bpm or R.general_medium_8th_bpm
    local removed = 0
    local i = 1
    while i <= #evs do
        local run = { i }
        local j = i
        while j < #evs and math.abs(evs[j + 1].qn - evs[j].qn - 0.5) <= 0.025 and #run < R.min_run_len do
            j = j + 1
            run[#run + 1] = j
        end
        if #run >= R.min_run_len and (evs[i].bpm or 120) >= bpm_lim then
            local worst, wv
            for _, k in ipairs(run) do
                local v = OnsetValue(evs[k])
                if not wv or v <= wv then worst, wv = k, v end
            end
            table.remove(evs, worst)
            removed = removed + 1
            i = run[1]
        else
            i = i + 1
        end
    end
    return removed
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
    -- Medium's arms barely easier than Hard's (a song under lower_hat_quarter_bpm whose
    -- Hard is already simple - molto_c_love_for_sale at 128 kept 94% of Hard's hand gems):
    -- the hi-hat/ride goes to quarter notes whatever the tempo. User rule 2026-10-10, like
    -- the 5-lane Medium fallback - a product choice: near 128 BPM official Medium often
    -- keeps the 8th hats, so every setting costs some agreement. It counts HAND gems, not
    -- all notes: with all notes, Hard's end-of-bar kick (EndOfBarKick) gave Medium more
    -- kicks to remove, molto's share fell from 94.5% to 88% and the fallback stopped firing
    -- although the arms had not changed. Swept on the chain (X > H > M vs official Medium,
    -- 482 dev songs, from 120 BPM): hands > 93% fires in 50 songs, onset F1 94.0 -> 92.8;
    -- notes > 88% fires in 37 (92.9) but moves with every kick rule; from 0 BPM far more.
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
                  -- The fields the 5-lane result lines read.
                  chords_reduced = 0, recolored = 0, shortened = 0, cut = 0 }
    local bpms = {}
    for _, ev in ipairs(events) do
        log.upper_notes = log.upper_notes + #ev.offs
        for _, o in ipairs(ev.offs) do if o ~= KICK then log.upper_hands = log.upper_hands + 1 end end
        bpms[#bpms + 1] = ev.bpm or 120
    end
    table.sort(bpms)
    log.median_bpm = bpms[#bpms // 2 + 1]
    local evs = Annotate(events, ctx)
    -- Positions (1/24 QN) of the incoming tier's cymbal-only hits (EasyTwoHandAnds).
    local upper_cym_only = {}
    for _, ev in ipairs(evs) do
        local drum = Has(ev, SNARE)
        for _, o in ipairs(ev.offs) do if IsTom(ev, o) then drum = true end end
        if HasCymbal(ev) and not drum then upper_cym_only[math.floor(ev.qn * 24 + 0.5)] = true end
    end

    if (opts.unflip or 'H') == dl then evs = Unflip(evs, log) end
    evs = Rolls(evs, dl, log)

    if dl == 'H' then
        evs = RetimeFills(evs, opts.fast_runs, log, ctx)
        evs = HardSixteenths(evs)
        KickUnderSnare(evs, 'H')
        local P = GEN_DRUMS_PARAMS
        local Busy = BusyHands(evs)
        ThinKicks(evs, function(ev)
            if P.hard_kick_gap_busy and Busy(ev) then return P.hard_kick_gap_busy end
            if (ev.bpm or 120) >= P.hard_kick_gap_fast_bpm then return P.hard_kick_gap_fast end
            -- An off-beat 8th kick needs more room than one on the beat.
            if Gen5BeatClass(ev) == '8th' then return P.hard_kick_gap_8th end
            return P.hard_kick_gap
        end)
        if GEN_DRUMS_PARAMS.hard_end_of_bar_kick then EndOfBarKick(evs) end
        if GEN_DRUMS_PARAMS.hard_paired_kick then PairedKick(evs) end
        if opts.hat_drops and opts.hat_drops > 0 then log.hat_drops = HardHatDrops(evs, opts.hat_drops) end
        MaxGems(evs, 3)
    else
        local fill_grid = 0.5
        if dl == 'E' and (evs[1] and evs[1].bpm or 120) >= DRUMS_RULES.roll_easy_quarter_bpm then fill_grid = 1.0 end
        -- Easy's quarter-note fills: a run continues across a quarter-note gap, so a fill
        -- Medium broke into pieces (its runs of four 8ths lose one) is still one run and goes
        -- to quarters from its start (pojat_lemmikkih bars 73-74: Rg Rg . Rg Rg Rg ... kept
        -- its first 8th pair on Easy). 2026-10-10.
        evs = GridFillRuns(evs, fill_grid >= 1 and 1.0 or 0.5 - EPS, fill_grid)
        evs = LowerHands(evs, opts.all_quarters)
        if dl == 'M' then
            KickUnderSnare(evs, 'M')
            log.sandwiched = SandwichedHats(evs, true)
            log.drum_changes = DrumChanges(evs)
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
        -- chooses among kicks that survive (molto bar 7: it kept beat 4's KRY kick over
        -- beat 3's, then lost it to the two-gem limit, and beat 3 had none).
        MaxGems(evs, 2)
        LowerKicks(evs)
        if dl == 'E' then EasyFillKicks(evs) end   -- Hard/Medium: see EasyFillKicks
    end
    if dl ~= 'H' then OneKickPerBar(evs) end
    evs = Compact(evs)
    DoubleCrashes(evs)
    log.runs_broken = BreakEighthRuns(evs, dl)
    -- After the run breaker: it can remove the hit that stood right before a crash, and the
    -- one before it then needs the treatment (pojat bar 74 on Medium).
    if dl ~= 'H' then log.tom_before_crash = TomBeforeCrash(evs) end
    EvenRolls(evs, ctx.rolls)
    evs = Compact(evs)

    for _, ev in ipairs(evs) do
        ev.fill, ev.roll, ev.disco, ev.tom, ev.rolled, ev.kick_dropped = nil, nil, nil, nil, nil, nil
        log.notes = log.notes + #ev.offs
        for _, o in ipairs(ev.offs) do if o ~= KICK then log.hands = log.hands + 1 end end
    end
    log.kept = #evs
    return evs, log
end
