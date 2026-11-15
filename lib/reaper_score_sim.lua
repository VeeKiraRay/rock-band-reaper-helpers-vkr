-- Rock Band 3 score and overdrive simulator: one part, a full combo, Expert.
--
-- PURE: plain tables in, plain tables out, no r / ctx / S. The project reader that
-- builds the input is lib/reaper_score_read.lua; the General Helper's Metadata > Score
-- draws the full result and the Instrument Helper's Overdrive > Validate reports the
-- overdrive half of it.
--
-- Every rule below is the game's own, read from the RB3 decompilation and its
-- config/scoring.dta + config/star_thresholds.dta (the 2026-11 game-data research):
--
--   BASE SCORE (what the stars are measured against; MultiplayerAnalyzer)
--     head 25 per note, a chord = 25 x its notes; Pro drums add 5 per note; Pro Keys
--       60 per note (scoring.dta real_keys).
--     tail 12 x sustain length in quarter notes x notes (Pro Keys 30), only for a
--       sustain longer than 160 ticks (1/3 QN); drums never have one.
--     streak multiplier: gem n (from 1) x min(floor(n / 10) + 1, 4), bass 6. The base
--       scores a tail at its head's multiplier.
--     gems in the Big Rock Ending are left out; the base counts the BRE at 100 per
--       second of its lanes (bonus).
--   BIG ROCK ENDING IN PLAY (GemPlayer::FillInProgress): each lane hit earns 100 x the
--     time since that lane's last hit, capped at 1.5 s - up to 500 per second with all
--     five lanes kept going. Paid once at the end, only if the final note is hit, never
--     multiplied. The simulation takes that maximum, so "up to".
--     solo bonus: 100 per gem in each solo (bonus).
--   STARS: star N = threshold[N] x streak points + bonus threshold[N] x bonus, rounded
--     down. Gold (6) is above the no-overdrive full combo: only overdrive reaches it.
--   OVERDRIVE METER 0..1
--     +0.251 per finished phrase; a unison +0.251 more (in solo play the player is
--       "every track", so every unison gives 0.502). A unison (PhraseAnalyzer) is
--       phrases on two or more DIFFERENT instruments whose starts are under a quarter
--       note apart (480 ticks; ends do not matter). Keys and Pro Keys are one
--       instrument; vocals never join one. The reader marks them.
--     whammy on a held sustain of an overdrive phrase: +0.034 per quarter note
--       (guitar, bass, keys and Pro Keys).
--     deploy from 0.5; drains 1/32 per BEAT-track beat; x2 on everything the part
--       scores while deployed - gem heads and the part of a sustain held during it.
--       The BRE and the solo bonus are never multiplied.
--   DRUMS deploy only through a fill. Fills appear only once the drummer is ready, and
--     only those starting at least a highway length (2.4 s) after that moment. Every
--     gem inside the fill used, its closing crash included, scores nothing (and is
--     left out of the streak - assumed).
--   VOCALS: each sung phrase 1000 x the phrase streak (+1 per phrase to x4), paid at
--     the phrase end. The phrase's points build up as it is sung, in proportion to each
--     note's weight (VocalPart::GetNoteSliceWeight: sung milliseconds, the first 150 ms
--     of a note ramping up as sqrt; pitched and unpitched alike); overdrive doubles the
--     share earned while deployed, so a deploy after a phrase's last note doubles none
--     of it. (Slides use another weight curve - taken as flat here, the one small
--     approximation left.) Percussion phrases score only 100 per percussion note (bonus).
--   VOCAL DEPLOY: in a freestyle section (VocalNoteList::DetermineFreestyleSections): a
--     gap between sung notes over 800 ms gives a section trimmed 100 ms at each end, over
--     600 ms one trimmed 50 ms; a gap after a syllable ending in '-' or '=' (mid-word)
--     gives none; before the first note and after the last there is one too. Deploying
--     takes unbroken mic noise over the scream threshold for 500 ms (section of 600 ms+)
--     or 400 ms (VocalPlayer::GetFreestyleDeploymentRequiredMs, Singer::
--     AddToFreestyleDeployment). With harmonies any part's own section will do.
--   HARMONIES: scored at HARM1's phrase ends; the best-sung part earns the full phrase
--     value, every other part singing in it 10% (part_score_multiplier 1.0 0.1 0.1), each
--     doubled by its own share sung while deployed. Only HARM1's overdrive counts; any
--     part's freestyle section can deploy (VocalPlayer::InFreestyleSection). The
--     star base is solo vocals' - each phrase once at the full value
--     (VocalPlayer::GetBaseMaxStreakPoints never applies the part multiplier) - so the
--     extra parts are pure gain over the cut-offs (matches play: about the same cut-offs
--     as solo vocals).
--
-- The deploy policy is "as soon as possible": guitar, bass and keys deploy the moment
-- the meter reaches 0.5; drums at the first fill the game shows; vocals as soon as a
-- freestyle section allows. One exception, at the end: when that leaves the last
-- overdrive unusable, ScoreSimulatePart tries holding any of the last three deploys for
-- the next phrase, and takes the best path that uses it. It is not the best possible
-- run (a deliberate choice: gold should be reachable without perfect overdrive paths),
-- so "gold not reached" means "not with this simple plan".

SCORE_RULES = {
    head          = 25,          -- per note; Pro Keys see SCORE_POINTS
    pro_bonus     = 5,
    tail          = 12,
    tail_min_qn   = 160 / 480,   -- the game's sustain threshold, in quarter notes
    solo_per_gem  = 100,
    coda_per_sec  = 100,         -- the star base's BRE rate
    coda_play_per_sec = 500,     -- most a played BRE earns: 100 per lane, five lanes
    perc_per_gem  = 100,
    phrase_value  = 1000,        -- vocals, Expert
    od_phrase     = 0.251,
    od_threshold  = 0.5,
    deploy_beats  = 32,
    whammy_per_qn = 0.034,
    fill_gate_sec = 2.4,         -- one highway length: depends on track speed; a working value
    -- Vocal freestyle sections: { gap over, trim each end, deploy needs } in seconds,
    -- longest first (scoring.dta freestyle_min_duration / _pad / _deployment_time).
    freestyle     = { { gap = 0.8, pad = 0.1, deploy = 0.5 },
                      { gap = 0.6, pad = 0.05, deploy = 0.4 } },
    note_ramp_ms  = 150,         -- a vocal note's first 150 ms earn less (sqrt ramp)
    hold_margin_beats = 0.25,    -- a held deploy starts this much early, so it is still
                                 -- running when the next phrase is collected
    harmony_part  = 0.1,         -- each harmony part past the best-sung one
}

-- Head and tail points per part kind where they differ from SCORE_RULES' 25 / 12.
SCORE_POINTS = { prokeys = { head = 60, tail = 30 } }

-- Streak multiplier cap per part.
SCORE_MAX_MULT = { guitar = 4, bass = 6, drums = 4, keys = 4, prokeys = 4, vocals = 4 }

-- config/star_thresholds.dta, new_instrument_thresholds: stars 1..5 and gold.
SCORE_STAR_THRESHOLDS = {
    guitar = { 0.06, 0.12, 0.20, 0.47, 0.78, 1.15 },
    bass   = { 0.05, 0.10, 0.19, 0.47, 0.78, 1.15 },
    drums  = { 0.06, 0.12, 0.20, 0.45, 0.75, 1.09 },
    vocals = { 0.05, 0.11, 0.19, 0.46, 0.77, 1.06 },
    keys   = { 0.06, 0.12, 0.20, 0.47, 0.78, 1.15 },
    prokeys = { 0.06, 0.12, 0.20, 0.47, 0.78, 1.15 },   -- real_keys: the same as keys
}
-- new_bonus_thresholds, the same star positions.
SCORE_BONUS_THRESHOLDS = { 0.05, 0.10, 0.20, 0.30, 0.40, 0.95 }

local EPS = 1e-4

----------------------------------------------------------------------
-- Beats (overdrive drain)
----------------------------------------------------------------------

-- Beat count at a QN position from the BEAT track's notes: one beat per note, linear in
-- between, extended past both ends with the nearest spacing. Fewer than two notes: one
-- beat per quarter note (the reader warns when that happens).
function ScoreBeatAt(beats, qn)
    local n = #beats
    if n < 2 then return qn end
    if qn <= beats[1] then
        return (qn - beats[1]) / (beats[2] - beats[1])
    end
    if qn >= beats[n] then
        return (n - 1) + (qn - beats[n]) / (beats[n] - beats[n - 1])
    end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if beats[mid] <= qn then lo = mid else hi = mid end
    end
    return (lo - 1) + (qn - beats[lo]) / (beats[hi] - beats[lo])
end

-- The QN position of a beat count (inverse of ScoreBeatAt).
function ScoreQNAtBeat(beats, b)
    local n = #beats
    if n < 2 then return b end
    if b <= 0 then return beats[1] + b * (beats[2] - beats[1]) end
    if b >= n - 1 then return beats[n] + (b - (n - 1)) * (beats[n] - beats[n - 1]) end
    local i = math.floor(b) + 1
    return beats[i] + (b - (i - 1)) * (beats[i + 1] - beats[i])
end

----------------------------------------------------------------------
-- Stars
----------------------------------------------------------------------

-- Star cut-offs 1..6 (6 = gold) for a part's streak points and bonus.
function ScoreStars(kind, streak_pts, bonus)
    local thr = SCORE_STAR_THRESHOLDS[kind] or SCORE_STAR_THRESHOLDS.guitar
    local out = {}
    for i = 1, 6 do
        out[i] = math.floor(thr[i] * streak_pts + SCORE_BONUS_THRESHOLDS[i] * bonus)
    end
    return out
end

-- How many stars a score reaches (0..6).
function ScoreStarsReached(stars, score)
    local n = 0
    for i = 1, 6 do if score >= stars[i] then n = i end end
    return n
end

----------------------------------------------------------------------
-- Gem parts (guitar, bass, drums, keys)
----------------------------------------------------------------------

local function InSpan(qn, sp)
    return sp and qn >= sp.s - EPS and qn < sp.e - EPS
end

-- Inside the Big Rock Ending lanes. The final hit after them scores as usual (the game
-- leaves out only the gems from the lanes' start to their end).
local function InBRE(part, qn)
    return part.bre and qn >= part.bre.s - EPS and qn < part.bre.e - EPS
end

local function Points(part)
    return SCORE_POINTS[part.kind] or SCORE_RULES
end

local function HasTail(part, g)
    return part.kind ~= 'drums' and (g.qn_e - g.qn) > SCORE_RULES.tail_min_qn + EPS
end

-- Head points of one gem. `base` = what the star base counts; Pro drums only differ
-- in play, where a tom earns no Pro bonus.
local function HeadPoints(part, g, opts, base)
    local n = g.n or 1
    local pts = Points(part).head * n
    if part.kind == 'drums' and opts.pro then
        local bonus_notes = base and n or (n - (g.toms or 0))
        pts = pts + SCORE_RULES.pro_bonus * bonus_notes
    end
    return pts
end

-- Per-gem flags the simulation needs: in which overdrive phrase, which gem ends it,
-- which gem ends a solo (and the solo's gem count). Gems in the BRE are skipped.
local function MarkGems(part)
    local gems = part.gems
    for _, g in ipairs(gems) do g.od_i, g.od_last, g.solo_last = nil, nil, nil end
    for i, sp in ipairs(part.od or {}) do
        local last
        for _, g in ipairs(gems) do
            if not InBRE(part, g.qn) and InSpan(g.qn, sp) then g.od_i = i; last = g end
        end
        if last then last.od_last = i end
    end
    for _, sp in ipairs(part.solos or {}) do
        local last, count = nil, 0
        for _, g in ipairs(gems) do
            if not InBRE(part, g.qn) and InSpan(g.qn, sp) then last = g; count = count + 1 end
        end
        if last then last.solo_last = count end
    end
end

-- The star base: streak points (with tails at their head's multiplier), and bonus
-- (solos + BRE). Returns streak_pts, bonus, solo_bonus, coda_bonus.
function ScoreBasePart(part, opts)
    opts = opts or {}
    local maxm = SCORE_MAX_MULT[part.kind] or 4
    local streak, count = 0, 0
    local solo = 0
    for _, sp in ipairs(part.solos or {}) do
        local c = 0
        for _, g in ipairs(part.gems) do
            if not InBRE(part, g.qn) and InSpan(g.qn, sp) then c = c + 1 end
        end
        solo = solo + c * SCORE_RULES.solo_per_gem
    end
    for _, g in ipairs(part.gems) do
        if not InBRE(part, g.qn) then
            count = count + 1
            local mult = math.min(count // 10 + 1, maxm)
            local pts = HeadPoints(part, g, opts, true)
            if HasTail(part, g) then
                pts = pts + Points(part).tail * (g.qn_e - g.qn) * (g.n or 1)
            end
            streak = streak + pts * mult
        end
    end
    local coda = part.bre and (SCORE_RULES.coda_per_sec * (part.bre.sec or 0)) or 0
    return streak, solo + coda, solo, coda
end

-- Bars covered by spans, in bars (fractional), given bars = { { qn_s, qn_e } }.
local function BarsCovered(bars, spans)
    if not bars then return nil end
    local total = 0
    for _, b in ipairs(bars) do
        local len = b.qn_e - b.qn_s
        if len > 0 then
            for _, sp in ipairs(spans) do
                local o = math.min(b.qn_e, sp.e) - math.max(b.qn_s, sp.s)
                if o > 0 then total = total + o / len end
            end
        end
    end
    return total
end

-- The shared result tail: base, stars, gold, coverage.
local function Finish(res, part, opts, first_qn, end_qn)
    res.stars = ScoreStars(part.kind, res.base_streak, res.base_bonus)
    res.total = res.score + res.bonus
    res.stars_reached = ScoreStarsReached(res.stars, res.total)
    res.gold_short = math.max(0, res.stars[6] - res.total)
    res.span = { s = first_qn or 0, e = end_qn or 0 }
    local od_qn = 0
    for _, d in ipairs(res.deploys) do od_qn = od_qn + (d.e - d.s) end
    res.od_qn = od_qn
    local span_len = (end_qn or 0) - (first_qn or 0)
    res.od_share = span_len > 0 and od_qn / span_len or 0
    res.od_bars = BarsCovered(part.bars, res.deploys)
    res.no_beat = #(part.beats or {}) < 2
    return res
end

-- Room after the last overdrive phrase: the beats from where it completes to the part's
-- last note, against the beats its overdrive lasts (0.251 of a meter = 8 beats, a unison
-- 16). Fewer means its overdrive can never be fully spent, however it is deployed.
local function LastOdRoom(res, beats, last_qn)
    local lo = res.last_od
    if not lo then return end
    lo.beats_left = ScoreBeatAt(beats, last_qn) - ScoreBeatAt(beats, lo.qn)
    lo.beats_needed = SCORE_RULES.od_phrase * (lo.unison and 2 or 1) * SCORE_RULES.deploy_beats
    lo.too_late = lo.beats_left < lo.beats_needed - 1e-6
end

-- Simulate a full combo with overdrive deployed as soon as possible.
--   part = { kind, gems = { { qn, qn_e, sec, n, toms } } sorted, od = { { s, e,
--            unison } }, solos = { { s, e } }, fills = { { s, e, s_sec } } (drums),
--            bre = { s, e, sec } or nil, beats = { qn }, bars = { { qn_s, qn_e } } }
--   opts = { pro = bool (drums), whammy = bool (default true) }
-- Returns { score, bonus, total, base_streak, base_bonus, stars, stars_reached,
--   gold_qn, gold_short, deploys = { { s, e } }, od_qn, od_share, od_bars, od_gems,
--   gems, waste = { { qn, kind = 'full' | 'unspent', amount, ready } },
--   lost_fills = { { qn, gap_sec } }, fill_points_lost, no_beat }
function ScoreSimulateOD(part, opts)
    opts = opts or {}
    local whammy_on = opts.whammy ~= false and part.kind ~= 'drums'
    local kind = part.kind
    local maxm = SCORE_MAX_MULT[kind] or 4
    local beats = part.beats or {}
    local fills = part.fills or {}
    MarkGems(part)

    local res = { score = 0, bonus = 0, deploys = {}, waste = {}, lost_fills = {},
                  od_gems = 0, gems = 0, fill_points_lost = 0 }
    res.base_streak, res.base_bonus = ScoreBasePart(part, opts)
    local gold = ScoreStars(kind, res.base_streak, res.base_bonus)[6]

    -- Scored gems only (the BRE is left out).
    local gems = {}
    for _, g in ipairs(part.gems) do
        if not InBRE(part, g.qn) then gems[#gems + 1] = g end
    end
    if #gems == 0 then return Finish(res, part, opts, 0, 0) end

    -- Breakpoints: gem heads, tail ends, beats, fill ends.
    local pts = {}
    for _, g in ipairs(gems) do
        pts[#pts + 1] = g.qn
        if HasTail(part, g) then pts[#pts + 1] = g.qn_e end
    end
    local first_qn = gems[1].qn
    local last_qn = 0
    for _, g in ipairs(gems) do
        last_qn = math.max(last_qn, HasTail(part, g) and g.qn_e or g.qn)
    end
    for _, b in ipairs(beats) do
        if b > first_qn and b < last_qn then pts[#pts + 1] = b end
    end
    for _, f in ipairs(fills) do
        if f.e > first_qn and f.e < last_qn then pts[#pts + 1] = f.e end
    end
    table.sort(pts)
    local uniq = {}
    for _, p in ipairs(pts) do
        if #uniq == 0 or p - uniq[#uniq] > EPS then uniq[#uniq + 1] = p end
    end

    local meter, dep, dep_s = 0, false, nil
    local streak = 0
    local tails = {}            -- { e, n, od }
    local gain_since            -- first gain since the meter was last empty
    local ready_qn
    local active_fill           -- drums: the fill that will deploy
    local gi = 1

    local function Mult() return math.min(streak // 10 + 1, maxm) end

    local function CheckGold(qn)
        if not res.gold_qn and res.score + res.bonus >= gold then res.gold_qn = qn end
    end

    local pending_hold            -- the res.held entry waiting for its deploy
    local function Deploy(qn)
        if pending_hold then pending_hold.deploy = qn; pending_hold = nil end
        dep, dep_s = true, qn
        ready_qn, active_fill = nil, nil
    end
    local function EndDeploy(qn)
        res.deploys[#res.deploys + 1] = { s = dep_s, e = qn }
        dep, dep_s = false, nil
        gain_since = nil
    end

    -- Each time the meter becomes ready is a decision: deploy, or (opts.hold[i]) keep it
    -- for the next phrase. A held meter decides again only when a PHRASE completes - not
    -- on every step of whammy.
    -- A held deploy does not wait for the next phrase: it starts at the earliest moment
    -- it is still running when that phrase is collected (the phrase then just extends
    -- it), planned_qn. Its gems carry od_last; the next one after the current position.
    local planned_qn
    local function NextGainQN(from)
        for i = gi, #gems do
            local g = gems[i]
            if g.od_last and g.qn > from + EPS then return g.qn end
        end
        return nil
    end
    local function PlannedStart(qn)
        local nxt = NextGainQN(qn)
        if not nxt then return nil, nil end
        local b = ScoreBeatAt(beats, nxt) - meter * SCORE_RULES.deploy_beats
                  + SCORE_RULES.hold_margin_beats
        return math.max(qn, ScoreQNAtBeat(beats, b)), nxt
    end
    local decisions, hold_wait = 0, false
    local function BecameReady(qn, sec, from_phrase)
        if dep or ready_qn or meter < SCORE_RULES.od_threshold - 1e-9 then return end
        if hold_wait and not from_phrase then return end
        hold_wait = false
        planned_qn = nil
        decisions = decisions + 1
        if opts.hold and opts.hold[decisions] then
            hold_wait = true
            res.held = res.held or {}
            res.held[#res.held + 1] = { qn = qn }
            pending_hold = res.held[#res.held]
            local start, nxt
            if opts.hold[decisions] == 'early' then start, nxt = PlannedStart(qn) end
            if start and kind ~= 'drums' then
                planned_qn = start
            elseif start then
                -- Drums: the first fill the game shows that ends (deploys) from the
                -- planned start and before the next phrase; none: wait for the phrase.
                for _, f in ipairs(fills) do
                    if f.s > qn + EPS and (f.s_sec or 0) - (sec or 0)
                       >= SCORE_RULES.fill_gate_sec - 1e-6
                       and f.e >= start - EPS and f.e < nxt - EPS then
                        active_fill = f
                        break
                    end
                end
            end
            return
        end
        ready_qn = qn
        -- opts.deploy_anywhere: drums deploy like the others (autoplay does, with no fill),
        -- for comparing with autoplay recordings.
        if kind ~= 'drums' or opts.deploy_anywhere then
            Deploy(qn)
            return
        end
        -- Drums: the first fill that starts a highway length after this moment.
        for _, f in ipairs(fills) do
            if f.s > qn + EPS then
                local gap = (f.s_sec or 0) - (sec or 0)
                if gap >= SCORE_RULES.fill_gate_sec - 1e-6 then
                    active_fill = f
                    break
                end
                res.lost_fills[#res.lost_fills + 1] = { qn = f.s, gap_sec = gap, ready_qn = qn }
            end
        end
    end

    local function Gain(x, qn, sec)
        if x <= 0 then return end
        gain_since = gain_since or qn
        meter = meter + x
        if meter > 1 + 1e-9 then
            local w = res.waste[#res.waste]
            if w and w.kind == 'full' and math.abs(w.qn - qn) < EPS then
                w.amount = w.amount + (meter - 1)
            else
                res.waste[#res.waste + 1] = { qn = qn, kind = 'full', amount = meter - 1 }
            end
            meter = 1
        end
        BecameReady(qn, sec, true)
    end

    -- Continuous part between two breakpoints: tails score, whammy fills, deploy drains.
    local function Advance(a, b)
        if b - a <= EPS then return end
        local tail_n, whammy = 0, false
        for _, t in ipairs(tails) do
            if t.e > a + EPS then
                tail_n = tail_n + t.n
                if t.od then whammy = true end
            end
        end
        local wr = (whammy_on and whammy) and SCORE_RULES.whammy_per_qn or 0
        local function Seg(x0, x1)
            local d = x1 - x0
            if d <= 0 then return end
            local dr = dep and ((ScoreBeatAt(beats, x1) - ScoreBeatAt(beats, x0))
                                / SCORE_RULES.deploy_beats / d) or 0
            res.score = res.score + Points(part).tail * tail_n * d * Mult() * (dep and 2 or 1)
            local new = meter + (wr - dr) * d
            if dep and new <= 1e-9 then
                -- Runs dry inside this segment: split there.
                local tz = x0 + meter / (dr - wr)
                res.score = res.score - Points(part).tail * tail_n * (x1 - tz) * Mult()
                meter = 0
                EndDeploy(tz)
                -- The rest of the segment at x1 (whammy after the end, if any).
                meter = math.min(1, wr * (x1 - tz))
                if meter > 0 then gain_since = tz end
            else
                if new > 1 then
                    res.waste[#res.waste + 1] = { qn = x0, kind = 'full', amount = new - 1,
                                                  whammy = true }
                    new = 1
                end
                meter = new
                if wr > 0 then gain_since = gain_since or x0 end
            end
        end
        Seg(a, b)
        CheckGold(b)
        if wr > 0 then BecameReady(b, 0, false) end
    end

    local prev = uniq[1]
    for _, t in ipairs(uniq) do
        Advance(prev, t)
        prev = t
        -- Tails ending here.
        local still = {}
        for _, tl in ipairs(tails) do
            if tl.e > t + EPS then still[#still + 1] = tl end
        end
        tails = still

        -- Gems at this position.
        while gi <= #gems and gems[gi].qn <= t + EPS do
            local g = gems[gi]
            gi = gi + 1
            local ignored = active_fill and g.qn >= active_fill.s - EPS
                            and g.qn <= active_fill.e + EPS
            if ignored then
                res.fill_points_lost = res.fill_points_lost
                                       + HeadPoints(part, g, opts, false) * Mult()
            else
                streak = streak + 1
                res.gems = res.gems + 1
                if dep then res.od_gems = res.od_gems + 1 end
                res.score = res.score + HeadPoints(part, g, opts, false) * Mult() * (dep and 2 or 1)
                if HasTail(part, g) then
                    tails[#tails + 1] = { e = g.qn_e, n = g.n or 1, od = g.od_i ~= nil }
                end
                if g.solo_last then
                    res.bonus = res.bonus + g.solo_last * SCORE_RULES.solo_per_gem
                end
                if g.od_last then
                    local sp = part.od[g.od_last]
                    Gain(SCORE_RULES.od_phrase * (sp.unison and 2 or 1), g.qn, g.sec)
                    res.last_od = { qn = g.qn, unison = sp.unison == true }
                end
            end
            CheckGold(g.qn)
        end

        -- Drums: the fill's closing crash has passed - overdrive starts.
        if active_fill and t >= active_fill.e - EPS then
            Deploy(active_fill.e)
            hold_wait = false
        end
        -- A held deploy's planned start has come.
        if planned_qn and not dep and t >= planned_qn - EPS then
            planned_qn = nil
            hold_wait = false
            Deploy(t)
        end
    end

    res.decisions = decisions
    LastOdRoom(res, beats, last_qn)
    -- The song's end for this part. end_left: meter still in a deploy when the part's
    -- last note passes - overdrive that runs on doubling nothing.
    if dep then
        res.end_left = meter
        res.deploys[#res.deploys + 1] = { s = dep_s, e = math.max(dep_s, last_qn) }
        dep = false
    elseif meter > 1e-6 then
        res.waste[#res.waste + 1] = { qn = gain_since or last_qn, kind = 'unspent',
                                      amount = meter, ready = ready_qn ~= nil,
                                      ready_qn = ready_qn }
    end
    if part.bre then
        res.bre_points = SCORE_RULES.coda_play_per_sec * (part.bre.sec or 0)
        res.bonus = res.bonus + res.bre_points
        CheckGold(part.bre.e or last_qn)
    end
    return Finish(res, part, opts, first_qn, last_qn)
end

----------------------------------------------------------------------
-- Vocals
----------------------------------------------------------------------

-- part = { kind = 'vocals', phrases = { { s, e, e_sec, sung = bool, perc = n,
--          od = bool, voices = { notes, notes, ... } } } sorted,
--          notes = { { qn, qn_e, s, e, lyric } } the part's sung notes (QN + seconds),
--          lines = { notes, ... } every singer's line for the freestyle sections
--          (default { notes }), beats, bars }
-- `voices`: each singing part's notes in the phrase window, the first the one scored at
-- the full value (HARM1, or the first part that sings there). A note there may be a
-- piece of a longer one (clipped to the window): `oq` / `oq_e` keep the whole note's QN
-- span so its weight ramp starts at the note's real start. Without `voices` the
-- phrase's notes are taken from `notes` (solo vocals).
-- A phrase scores when it has sung notes and no percussion notes.
local function VocalScored(ph) return ph.sung and (ph.perc or 0) == 0 end

function ScoreBaseVocals(part)
    local n, bonus = 0, 0
    for _, ph in ipairs(part.phrases or {}) do
        if VocalScored(ph) then n = n + 1 end
        bonus = bonus + (ph.perc or 0) * SCORE_RULES.perc_per_gem
    end
    local mult = (n == 0 and 0) or (n == 1 and 1) or (n == 2 and 3) or (4 * n - 6)
    return SCORE_RULES.phrase_value * mult, bonus
end

-- Freestyle sections of one singer's line, as { s_sec, e_sec, s_qn, rate } (rate =
-- quarter notes per second, to place a deploy inside the section). `notes` sorted by
-- start, with seconds, QN and the lyric. Pure, so tests can build lines by hand.
function ScoreFreestyleSections(notes)
    local out = {}
    local ss, ss_qn, boundary = 0, 0, true
    local rate = 2
    for _, n in ipairs(notes) do
        if n.e > n.s then rate = (n.qn_e - n.qn) / (n.e - n.s) end
        if boundary then
            local gap = n.s - ss
            for _, f in ipairs(SCORE_RULES.freestyle) do
                -- gap > 2 x pad + freestyle_min_duration: 800 / 600 ms
                if gap > f.gap then
                    local a = ss + f.pad
                    out[#out + 1] = { s_sec = a, e_sec = n.s - f.pad,
                                      s_qn = ss_qn + (n.qn - ss_qn) * (f.pad / gap),
                                      rate = (n.qn - ss_qn) / gap }
                    break
                end
            end
        end
        if n.e > ss then ss, ss_qn = n.e, n.qn_e end
        local l = n.lyric or ''
        local last = l:sub(-1)
        boundary = l == '' or (last ~= '-' and last ~= '=')
    end
    out[#out + 1] = { s_sec = ss + SCORE_RULES.freestyle[1].pad, e_sec = math.huge,
                      s_qn = ss_qn + SCORE_RULES.freestyle[1].pad * rate, rate = rate }
    return out
end

-- How long a deploy takes in a section of this length (nil: too short to deploy).
local function DeployNeeds(dur)
    for _, f in ipairs(SCORE_RULES.freestyle) do
        if dur >= f.gap - 2 * f.pad - 1e-9 then return f.deploy end
    end
    return nil
end

-- Weight of a vocal note's slice [x, y] (QN): its sung milliseconds, the first
-- note_ramp_ms of the whole note ramping up as sqrt (GetNoteSliceWeight).
function ScoreVocalSliceWeight(n, x, y)
    local oq, oq_e = n.oq or n.qn, n.oq_e or n.qn_e
    local dur_ms = ((n.e or 0) - (n.s or 0)) * 1000
    if oq_e - oq <= 0 or dur_ms <= 0 then return math.max(0, y - x) end
    local function T(q) return (q - oq) / (oq_e - oq) * dur_ms end
    local cap = math.min(SCORE_RULES.note_ramp_ms, dur_ms)
    local function F(t)
        if t <= cap then return (2 / 3) * t ^ 1.5 / math.sqrt(cap) end
        return (2 / 3) * cap + (t - cap)
    end
    local a, b = T(math.max(x, n.qn)), T(math.min(y, n.qn_e))
    if b <= a then return 0 end
    return F(b) - F(a)
end

function ScoreSimulateVocals(part, opts)
    local beats = part.beats or {}
    local phrases = part.phrases or {}
    local res = { score = 0, bonus = 0, deploys = {}, waste = {}, lost_fills = {},
                  od_gems = 0, gems = 0, fill_points_lost = 0, vocals = true }
    res.base_streak, res.base_bonus = ScoreBaseVocals(part)
    local gold = ScoreStars('vocals', res.base_streak, res.base_bonus)[6]
    -- Freestyle sections of every singer's line: any of them can deploy (harmonies: each
    -- part has its own). Merged by start, so the first usable one is the earliest.
    local sections = {}
    for _, line in ipairs(part.lines or { part.notes or {} }) do
        for _, sec in ipairs(ScoreFreestyleSections(line)) do sections[#sections + 1] = sec end
    end
    table.sort(sections, function(a, b) return a.s_sec < b.s_sec end)

    local meter, dep, dep_s, dep_b = 0, false, nil, nil
    local ready_qn, ready_sec, gain_since
    local k = 0
    local decisions = 0
    local min_deploy_qn         -- a held deploy's earliest start (see the hold below)
    local pending_hold          -- the res.held entry waiting for its deploy

    local function EndAt(qn)
        res.deploys[#res.deploys + 1] = { s = dep_s, e = qn }
        dep, dep_s, gain_since = false, nil, nil
    end
    -- Drain from the deploy start; meter is the level at dep_b beats.
    local function DrainTo(qn)
        if not dep then return end
        local b = ScoreBeatAt(beats, qn)
        local used = (b - dep_b) / SCORE_RULES.deploy_beats
        if used >= meter - 1e-9 then
            local end_qn = ScoreQNAtBeat(beats, dep_b + meter * SCORE_RULES.deploy_beats)
            meter = 0
            EndAt(end_qn)
        else
            meter = meter - used
            dep_b = b
        end
    end
    local function TryDeploy(upto_qn)
        -- Deploy in the first freestyle section where the noise can be held long enough
        -- after becoming ready: from max(section start, ready) for the time the section's
        -- length asks for, all inside the section.
        if dep or not ready_qn then return end
        for _, sec in ipairs(sections) do
            local needs = DeployNeeds(sec.e_sec - sec.s_sec)
            if needs then
                local from_sec = math.max(sec.s_sec, ready_sec)
                if min_deploy_qn then
                    from_sec = math.max(from_sec,
                        sec.s_sec + (min_deploy_qn - sec.s_qn) / math.max(sec.rate, 1e-6))
                end
                local at_sec = from_sec + needs
                if at_sec <= sec.e_sec + 1e-9 then
                    local qn = sec.s_qn + (at_sec - sec.s_sec) * sec.rate
                    if qn >= upto_qn - EPS then return end   -- later than this phrase end
                    qn = math.max(qn, ready_qn)
                    if pending_hold then pending_hold.deploy = qn; pending_hold = nil end
                    dep, dep_s, dep_b = true, qn, ScoreBeatAt(beats, qn)
                    ready_qn, ready_sec, min_deploy_qn = nil, nil, nil
                    return
                end
            end
        end
    end

    -- The deploy's end if nothing refills it before then.
    local function PlannedEnd()
        return ScoreQNAtBeat(beats, dep_b + meter * SCORE_RULES.deploy_beats)
    end
    -- Share of a list of sung notes' weight (GetNoteSliceWeight) inside [a, b].
    local function SungShare(notes, a, b)
        local tot, inside = 0, 0
        for _, n in ipairs(notes) do
            tot = tot + ScoreVocalSliceWeight(n, n.qn, n.qn_e)
            inside = inside + ScoreVocalSliceWeight(n, a, b)
        end
        return tot > 0 and inside / tot or 0
    end
    -- The singing parts of a phrase: its voices, or (solo) the notes inside it.
    local function Voices(ph)
        if ph.voices then return ph.voices end
        local own = {}
        for _, n in ipairs(part.notes or {}) do
            if n.qn >= ph.s - EPS and n.qn < ph.e - EPS then own[#own + 1] = n end
        end
        return { own }
    end

    local first_qn = phrases[1] and phrases[1].s or 0
    local last_qn = phrases[#phrases] and phrases[#phrases].e or 0
    for pi, ph in ipairs(phrases) do
        TryDeploy(ph.e)
        -- The game splits a phrase's points as they are sung: the part earned while
        -- deployed is doubled. So deploying after its last note doubles nothing of it,
        -- and a deploy running dry halfway doubles about half.
        local voices = Voices(ph)
        local fracs = {}
        for i, notes in ipairs(voices) do
            fracs[i] = dep and SungShare(notes, dep_s, PlannedEnd()) or 0
        end
        DrainTo(ph.e)
        if VocalScored(ph) then
            k = k + 1
            res.gems = res.gems + 1
            if (fracs[1] or 0) > 0 then res.od_gems = res.od_gems + fracs[1] end
            local value = 0
            for i in ipairs(voices) do
                value = value + (i == 1 and 1 or SCORE_RULES.harmony_part)
                                * (1 + fracs[i])
            end
            res.score = res.score + SCORE_RULES.phrase_value * math.min(k, 4) * value
        end
        res.bonus = res.bonus + (ph.perc or 0) * SCORE_RULES.perc_per_gem
        if not res.gold_qn and res.score + res.bonus >= gold then res.gold_qn = ph.e end
        if ph.od and ph.sung then
            res.last_od = { qn = ph.e, unison = false }
            gain_since = gain_since or ph.e
            meter = meter + SCORE_RULES.od_phrase
            if meter > 1 + 1e-9 then
                res.waste[#res.waste + 1] = { qn = ph.e, kind = 'full', amount = meter - 1 }
                meter = 1
            end
            if not dep and not ready_qn and meter >= SCORE_RULES.od_threshold - 1e-9 then
                decisions = decisions + 1
                if opts and opts.hold and opts.hold[decisions] then
                    res.held = res.held or {}
                    res.held[#res.held + 1] = { qn = ph.e }
                    pending_hold = res.held[#res.held]
                    -- Held: deploy from the earliest moment it is still running when the
                    -- next overdrive phrase ends (that phrase then extends it).
                    for j = pi + 1, (opts.hold[decisions] == 'early') and #phrases or 0 do
                        local nx = phrases[j]
                        if nx.od and nx.sung then
                            local b = ScoreBeatAt(beats, nx.e)
                                      - meter * SCORE_RULES.deploy_beats
                                      + SCORE_RULES.hold_margin_beats
                            ready_qn, ready_sec = ph.e, ph.e_sec
                            min_deploy_qn = math.max(ph.e, ScoreQNAtBeat(beats, b))
                            break
                        end
                    end
                else
                    ready_qn, ready_sec = ph.e, ph.e_sec
                end
            end
        end
    end
    res.decisions = decisions
    LastOdRoom(res, beats, last_qn)
    if dep then
        DrainTo(last_qn)
        if dep then res.end_left = meter; EndAt(last_qn) end
    elseif meter > 1e-6 then
        res.waste[#res.waste + 1] = { qn = gain_since or last_qn, kind = 'unspent',
                                      amount = meter, ready = ready_qn ~= nil,
                                      ready_qn = ready_qn }
    end
    part.kind = 'vocals'
    return Finish(res, part, opts, first_qn, last_qn)
end

local function SimulateOnce(part, opts)
    if part.kind == 'vocals' then return ScoreSimulateVocals(part, opts) end
    return ScoreSimulateOD(part, opts)
end

-- How many of the last deploy decisions the path search may hold back.
SCORE_HOLD_LAST = 3

-- One entry point for any part: deploy as soon as possible; if that leaves the last
-- overdrive unused, hold the fewest (latest first) of the last SCORE_HOLD_LAST deploys
-- that makes it usable (none found: the plain path stays, with its "never used" note).
-- res.held lists the holds as { qn = where the meter was ready, deploy = where that
-- overdrive was finally deployed }; res.asap_total is the plain total, for comparison.
local function Unspent(res)
    for _, w in ipairs(res.waste) do if w.kind == 'unspent' then return true end end
    return false
end

function ScoreSimulatePart(part, opts)
    opts = opts or {}
    local best = SimulateOnce(part, opts)
    local asap_total = best.total
    -- Only when the last overdrive would otherwise go unused, and a path is taken only if
    -- it uses it. opts.search = 'off' gives plain deploy-as-soon-as-possible (tests).
    if opts.search == 'off' or not Unspent(best) then
        best.asap_total = asap_total
        return best
    end
    -- The smallest fix (user): hold as few deploys as possible, the latest first - the
    -- last deploy alone, then the one before it alone, then the third; then pairs; then
    -- all three. Each held deploy either starts early (still running when the next
    -- phrase comes in) or waits for that phrase. The first set that gives a path using
    -- the last overdrive AND scoring more than deploy-asap wins (its best-scoring mode);
    -- usually that is the first try, two runs.
    local d = best.decisions or 0
    local n = math.min(SCORE_HOLD_LAST, d)
    local sets = {}
    for size = 1, n do
        local function Pick(from, chosen)
            if #chosen == size then
                sets[#sets + 1] = { table.unpack(chosen) }
                return
            end
            for i = from, n do
                chosen[#chosen + 1] = d - (i - 1)       -- i = 1 is the last decision
                Pick(i + 1, chosen)
                chosen[#chosen] = nil
            end
        end
        Pick(1, {})
    end
    for _, set in ipairs(sets) do
        local found
        for modes = 0, (1 << #set) - 1 do
            local hold = {}
            for j, dec in ipairs(set) do
                hold[dec] = (modes & (1 << (j - 1)) ~= 0) and 'wait' or 'early'
            end
            local o = {}
            for k, v in pairs(opts) do o[k] = v end
            o.hold = hold
            local res = SimulateOnce(part, o)
            if not Unspent(res) and res.total > asap_total + 1e-6
               and (not found or res.total > found.total + 1e-6) then
                found = res
            end
        end
        if found then
            best = found
            break
        end
    end
    best.asap_total = asap_total
    return best
end
