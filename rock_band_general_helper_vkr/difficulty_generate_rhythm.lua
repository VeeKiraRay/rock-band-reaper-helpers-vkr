-- Difficulty > Generate: which onsets a tier keeps (the rhythm half of the planner).
-- Gen5SelectOnsets is shared by every planner - Guitar/Bass/Keys (Gen5PlanTier,
-- difficulty_generate_5lane.lua) and Pro Keys - so the one-rhythm rule (see GEN5_PARAMS,
-- difficulty_generate_params.lua) holds by construction, not by keeping copies in step.
--
-- PURE: no r, no S. Load after difficulty_generate_params.lua.
--
-- Input event: { qn, qn_e, offs, bpm, down, bar_qn, bar_len } as described in
-- difficulty_generate_5lane.lua. offs is read only for its size (a chord or a single):
-- Medium's chord bonus and the busy-bar accent rule. Pitches or colors never matter.
--
-- Requires (globals, read at call time): K5_MIN_SP (actions_difficulty_5k.lua),
--   Gen5RetimeDenseRuns (difficulty_generate_retime.lua).

local SUSTAIN_QN   = GEN5_SUSTAIN_QN
local MIN_LEN_QN   = GEN5_MIN_LEN_QN
local EPS          = GEN5_EPS
local GUIDE_TOL    = 0.125   -- Keys-follows-Pro-Keys onset match (1/32 note)
local MinGapQN, MinSustainQN, ReleaseGapQN = Gen5MinGapQN, Gen5MinSustainQN, Gen5ReleaseGapQN

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

----------------------------------------------------------------------
-- Thinning
----------------------------------------------------------------------

-- Beat position and note length (see the one-rhythm note above GEN5_PARAMS). The
-- planner's Weights adds Medium's chord bonus and Medium/Easy's "can it stay a sustain"
-- test on top.
local function Weight(ev)
    local p = GEN5_PARAMS
    local w = p.weight[Gen5BeatClass(ev)] or 1
    if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then w = w + p.sustain_bonus end
    return w
end

-- Keep the highest-weight subset of events in which every onset is at least
-- gap_fn(event, earlier) after the previous kept one (weighted interval scheduling). For a
-- fixed gap this is exact: no other subset that respects the gap keeps more weight,
-- so nothing is removed that the gap did not force out.
-- w: optional per-event weights (default Weight).
-- Returns an array of booleans, keep[i].
local function SelectByGap(events, gap_fn, w)
    local n = #events
    local best, take, prev = { [0] = 0 }, {}, {}
    for i = 1, n do
        local j = i - 1
        while j >= 1 and events[i].qn - events[j].qn < gap_fn(events[i], events[j]) - EPS do j = j - 1 end
        prev[i] = j
        local with = (w and w[i] or Weight(events[i])) + best[j]
        if with > best[i - 1] then
            best[i], take[i] = with, true
        else
            best[i], take[i] = best[i - 1], false
        end
    end
    local keep, i = {}, n
    while i >= 1 do
        if take[i] then keep[i] = true; i = prev[i] else i = i - 1 end
    end
    return keep
end

-- How often official Hard keeps an off-beat onset of Expert, by bar position (quarter
-- notes from the bar line, on a 1/12 grid). Pooled over Guitar, Bass and Keys - one
-- rhythm model - over the development songs (official X>H, positions with 800+ onsets;
-- run_generate_eval_offline.lua's reader, hold-out excluded). The least-kept position
-- goes first. The 8th off-beats are the telling rows: official Hard drops "the and of 4"
-- (3.5, kept 49%) far more readily than the and of 2 (73%), of 1 (84%) or of 3 (85%).
local CAP_KEEP_RATE = {
    ['0.167'] = 0.03, ['1.167'] = 0.04, ['3.167'] = 0.06, ['3.917'] = 0.06, ['2.167'] = 0.06,
    ['3.750'] = 0.11, ['3.833'] = 0.19, ['0.250'] = 0.20, ['2.750'] = 0.25, ['2.833'] = 0.26,
    ['0.333'] = 0.26, ['1.833'] = 0.26, ['3.250'] = 0.27, ['1.750'] = 0.30, ['1.250'] = 0.30,
    ['3.667'] = 0.33, ['2.250'] = 0.35, ['3.333'] = 0.37, ['2.333'] = 0.38, ['0.750'] = 0.39,
    ['1.667'] = 0.42, ['1.333'] = 0.42, ['0.667'] = 0.43, ['2.667'] = 0.45, ['0.833'] = 0.46,
    ['3.500'] = 0.49, ['1.500'] = 0.73, ['0.500'] = 0.84, ['2.500'] = 0.85,
}
-- For a position the table does not list (an odd meter, a rare position): the beat
-- class's typical official keep rate, so it still sorts sensibly.
local CAP_CLASS_RATE = { ['8th'] = 0.6, ['16th'] = 0.25, trip = 0.4, other = 0.15 }

-- An onset's bar position, as CAP_KEEP_RATE keys it. bar_qn is optional (4/4 assumed).
local function BarPosKey(ev)
    return ('%.3f'):format(math.floor((ev.bar_qn or ev.qn % 4) * 12 + 0.5) / 12)
end

local function PosRate(ev)
    return CAP_KEEP_RATE[BarPosKey(ev)] or CAP_CLASS_RATE[Gen5BeatClass(ev)] or 0.5
end

-- Retimed notes (Gen5RetimeDenseRuns) are already the reduction: never removed again.
local function IsCandidate(ev)
    if ev.retimed then return false end
    local c = Gen5BeatClass(ev)
    return c ~= 'down' and c ~= 'beat'
end

-- Both gaps to the neighbouring onsets (in events) more than GEN5_PARAMS.isolated_qn.
-- The first and last onsets count their missing side as infinitely far.
local function IsIsolated(events, i)
    local lim = GEN5_PARAMS.isolated_qn + EPS
    local ev, pv, nx = events[i], events[i - 1], events[i + 1]
    return (not pv or ev.qn - pv.qn > lim) and (not nx or nx.qn - ev.qn > lim)
end

-- Medium's fallback: drop every kept off-beat onset that is isolated in the upper tier.
-- Returns how many were dropped.
local function DropIsolatedOffbeats(events, keep)
    local n = 0
    for i, ev in ipairs(events) do
        if keep[i] and IsCandidate(ev) and IsIsolated(events, i) then keep[i] = nil; n = n + 1 end
    end
    return n
end

-- Drop kept onsets until at most cap * #events remain. Removes WHOLE bar positions
-- across the whole song at once, least-kept first (CAP_KEEP_RATE), never a downbeat or
-- beat. So the same riff reduces the same way every time it comes round, rather than
-- the start of the song absorbing the whole cut. It can overshoot the cap by up to one
-- position. Removing an onset only widens gaps, so SelectByGap's gap still holds.
-- n_upper: the upper tier's onset count the cap is a share of - more than #events when
-- the Hard fast-run rewrite already took notes out.
local function CapKeep(events, keep, cap, protect_isolated, n_upper)
    if not cap then return end
    local kept, groups = 0, {}
    for i, ev in ipairs(events) do
        if keep[i] then
            kept = kept + 1
            if IsCandidate(ev) and not (protect_isolated and IsIsolated(events, i)) then
                local key = BarPosKey(ev)
                local g = groups[key]
                if not g then
                    g = { key = key, members = {}, rate = PosRate(ev) }
                    groups[key] = g
                end
                g.members[#g.members + 1] = i
            end
        end
    end
    local limit = math.floor(cap * (n_upper or #events))
    if kept <= limit then return end
    local order = {}
    for _, g in pairs(groups) do order[#order + 1] = g end
    table.sort(order, function(a, b)
        if a.rate ~= b.rate then return a.rate < b.rate end
        return a.key < b.key
    end)
    for _, g in ipairs(order) do
        if kept <= limit then break end
        for _, i in ipairs(g.members) do keep[i] = nil end
        kept = kept - #g.members
    end
end

-- An onset's position in its bar, as the busy-bar reference (busy_ref) records it.
local function PosStr(ev)
    return ('%.3f'):format(ev.bar_qn or ev.qn % 4)
end

-- Empty 8th-note slots in a bar: its length in 8ths minus the 8th-grid slots holding an
-- onset. A bar that already rests somewhere is easier than a full one, so it loses less.
local function EmptyEighths(events, idx)
    local slots, n = {}, 0
    local bar_len = events[idx[1]].bar_len or 4
    for _, i in ipairs(idx) do
        local x = (events[i].bar_qn or events[i].qn % 4) * 2
        if NearInt(x, EPS * 2) then
            local s = math.floor(x + 0.5)
            if not slots[s] then slots[s] = true; n = n + 1 end
        end
    end
    return math.max(0, math.floor(bar_len * 2 + 0.5) - n)
end

-- The notes in a bar that go last. A sustain always (it holds the line); a chord only in
-- a bar that mixes chords and single notes, where it is the accent. In a bar of all
-- chords or all single notes they are all alike and the usual "and" notes go.
local function ProtectedSet(events, idx)
    local chords, singles = 0, 0
    for _, i in ipairs(idx) do
        if #events[i].offs >= 2 then chords = chords + 1 else singles = singles + 1 end
    end
    local mixed, prot = chords > 0 and singles > 0, {}
    for _, i in ipairs(idx) do
        local ev = events[i]
        if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS or (mixed and #ev.offs >= 2) then prot[i] = true end
    end
    return prot
end

-- Every bar the selection left complete - all of its upper onsets kept, none retimed -
-- with at least min_onsets onsets is thinned. It loses n_drop notes less the 8th slots it
-- already leaves empty, at least one - unless two or more slots are empty already, then
-- none: Drop 2 on a bar of straight 8ths takes two, on a bar with one rest one, on a bar
-- with two rests nothing. Which notes go:
--   1. the RBN doc positions first - "remove every fourth note per half measure", the and
--      of 2 and the and of 4 (with Drop 1 the and of 4 wins: official Hard drops it most);
--   2. then the other off-beats, least-kept bar position first (CAP_KEEP_RATE), the later
--      one on a tie;
--   3. protected notes (ProtectedSet) last, whatever their position.
-- Rhythm, length and chord size only - never colors.
--
-- ref (optional): the leading instrument's busy bars, { [bar start] = { sig, removed } }.
-- A bar whose onset positions equal the leader's (sig) loses the leader's notes, so the
-- band drops the same notes - unless one of them is protected HERE (this instrument's own
-- sustain or accent wins); then the bar uses its own order above.
-- Returns { [bar start] = { sig, removed } } for the bars it thinned, and how many of
-- them followed ref.
local function ThinBusyBars(events, keep, min_onsets, protect_isolated, n_drop, ref)
    local record, followed = {}, 0
    if not min_onsets then return record, followed end
    local bars, order = {}, {}
    for i, ev in ipairs(events) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        local b = bars[key]
        if not b then
            b = { key = key, idx = {} }
            bars[key] = b
            order[#order + 1] = b
        end
        b.idx[#b.idx + 1] = i
    end
    for _, b in ipairs(order) do
        if #b.idx >= min_onsets then
            local complete = true
            for _, i in ipairs(b.idx) do
                -- A flourish note the gap dropped (Gen5RetimeDenseRuns) does not count: the
                -- bar left is still a full bar of 8ths.
                if (not keep[i] and not events[i].flourish) or events[i].retimed then complete = false; break end
            end
            -- Two or more 8th rests already: the bar is thin enough as it is.
            local empty = complete and EmptyEighths(events, b.idx) or 0
            if complete and empty < 2 then
                local pos, at = {}, {}
                for k, i in ipairs(b.idx) do
                    pos[k] = PosStr(events[i])
                    at[pos[k]] = i
                end
                local sig  = table.concat(pos, ' ')
                local prot = ProtectedSet(events, b.idx)
                local drop
                local lead = ref and ref[b.key]
                if lead and lead.sig == sig then
                    drop = {}
                    for _, p in ipairs(lead.removed) do
                        local i = at[p]
                        if not i or prot[i] or (protect_isolated and IsIsolated(events, i)) then
                            drop = nil
                            break
                        end
                        drop[#drop + 1] = i
                    end
                    if drop then followed = followed + 1 end
                end
                if not drop then
                    local cands = {}
                    for _, i in ipairs(b.idx) do
                        if keep[i] and IsCandidate(events[i]) and not (protect_isolated and IsIsolated(events, i)) then
                            local key = BarPosKey(events[i])
                            cands[#cands + 1] = { i = i, r = PosRate(events[i]), p = prot[i] and 1 or 0,
                                                  doc = (key == '1.500' or key == '3.500') and 0 or 1 }
                        end
                    end
                    table.sort(cands, function(a, c)
                        if a.p ~= c.p then return a.p < c.p end
                        if a.doc ~= c.doc then return a.doc < c.doc end
                        if a.r ~= c.r then return a.r < c.r end
                        return a.i > c.i
                    end)
                    local n = math.max(1, (n_drop or 1) - empty)
                    drop = {}
                    for k = 1, math.min(n, #cands) do drop[k] = cands[k].i end
                end
                local removed = {}
                for _, i in ipairs(drop) do
                    keep[i] = nil
                    removed[#removed + 1] = PosStr(events[i])
                end
                table.sort(removed)
                record[b.key] = { sig = sig, removed = removed }
            end
        end
    end
    return record, followed
end

-- Keys following the same-tier Pro Keys chart: keep the events that land on a Pro
-- Keys onset, with that note's length. guide = sorted { { qn, qn_e }... }.
-- One Keys onset per Pro Keys onset, the closest: a 32nd grace note before a beat sits
-- within GUIDE_TOL of the beat's Pro Keys onset too, and kept both (lovegame Keys Hard
-- had 24 more onsets than the Pro Keys Hard it followed).
-- Returns (keep, lens, at, missed): at[i] = the Pro Keys onset a kept event takes over (Keys
-- plays Pro Keys' rhythm exactly - a rewritten Pro Keys run sits on 8th triplets, and
-- Keys' nearest 16ths made uneven groups with gaps, korpiklaani bar 55); missed = the
-- Pro Keys onsets no Keys note matched (Keys and Pro Keys Expert differ there).
local function SelectByGuide(events, guide)
    local keep, lens, at, j = {}, {}, {}, 1
    local owner = {}   -- guide index -> event index matched to it
    for i, ev in ipairs(events) do
        while j <= #guide and guide[j].qn < ev.qn - GUIDE_TOL do j = j + 1 end
        local best
        for k = j, math.min(#guide, j + 1) do
            if math.abs(guide[k].qn - ev.qn) <= GUIDE_TOL
               and (not best or math.abs(guide[k].qn - ev.qn) < math.abs(guide[best].qn - ev.qn)) then
                best = k
            end
        end
        if best then
            local prev = owner[best]
            if not prev or math.abs(guide[best].qn - ev.qn) < math.abs(guide[best].qn - events[prev].qn) then
                if prev then keep[prev], lens[prev], at[prev] = nil, nil, nil end
                owner[best] = i
                keep[i] = true
                lens[i] = guide[best].qn_e - guide[best].qn
                at[i] = guide[best].qn
            end
        end
    end
    local missed = {}
    for k, g in ipairs(guide) do if not owner[k] then missed[#missed + 1] = g.qn end end
    return keep, lens, at, missed
end

----------------------------------------------------------------------
-- A keys lick that starts on an "and" (GEN5_PARAMS.and_phrase)
----------------------------------------------------------------------

local function BarPos(ev) return ev.bar_qn or ev.qn % 4 end
local function OnAnd(ev) return NearInt(BarPos(ev) - 0.5, EPS) end
local function OnBeat(ev) return NearInt(BarPos(ev), EPS) end

-- How often a line of notes changes note, per step (0 = one note repeated, 1 = a new
-- note every time). Colours on Keys, pitches on Pro Keys.
local function Variety(line)
    if #line < 2 then return 0 end
    local n = 0
    for k = 2, #line do
        if table.concat(line[k].offs, ',') ~= table.concat(line[k - 1].offs, ',') then n = n + 1 end
    end
    return n / (#line - 1)
end

-- The phrases of the upper tier that Medium reduces on the "and" grid, as spans
-- { { qn_s, qn_e }... } (first and last onset). See GEN5_PARAMS.and_phrase.
function Gen5AndPhrases(events, kind)
    local p, spans = GEN5_PARAMS.and_phrase, {}
    if not (p and p.kinds[kind]) then return spans end
    local i = 1
    while i <= #events do
        local j = i
        while j < #events and events[j + 1].qn - events[j].qn < p.rest - EPS do j = j + 1 end
        if j - i + 1 >= p.min_onsets and OnAnd(events[i]) then
            local ands, beats = {}, {}
            for k = i, j do
                if OnAnd(events[k]) then ands[#ands + 1] = events[k]
                elseif OnBeat(events[k]) then beats[#beats + 1] = events[k] end
            end
            if #ands >= 2 and #beats >= 2 and Variety(ands) > Variety(beats) + p.variety_margin then
                spans[#spans + 1] = { qn_s = events[i].qn, qn_e = events[j].qn }
            end
        end
        i = j + 1
    end
    return spans
end

local function InSpans(spans, qn)
    for _, s in ipairs(spans) do
        if qn >= s.qn_s - EPS and qn <= s.qn_e + EPS then return true end
    end
    return false
end

-- The beat class of an onset in a phrase reduced on the "and" grid: classed as if half a
-- beat earlier, so the "and" of 4 that opens it counts as the downbeat.
local function ShiftedClass(ev)
    return Gen5BeatClass({ qn = ev.qn - 0.5, down = math.abs(BarPos(ev) - 0.5) <= EPS })
end

-- The class an onset weighs as: shifted inside an "and" phrase, else its own.
local function ClassOf(ev, shifted)
    return shifted and ShiftedClass(ev) or Gen5BeatClass(ev)
end

----------------------------------------------------------------------
-- Medium: weights, a note per beat, and following Guitar
----------------------------------------------------------------------

-- Per-event weights for tier dl. Hard: Weight as it always was. Medium/Easy: the sustain
-- bonus only for a note that can stay a sustain on this tier (held at most to the next
-- upper onset less the release gap, at least MinSustainQN); Medium adds chord_bonus.
-- shifted: optional { [i] = true } for onsets in an "and" phrase (ShiftedClass).
local function Weights(kind, dl, events, shifted)
    local p, w = GEN5_PARAMS, {}
    shifted = shifted or {}
    for i, ev in ipairs(events) do
        if dl == 'H' then
            w[i] = Weight(ev)
        else
            w[i] = p.weight[ClassOf(ev, shifted[i])] or 1
            local len, nx = ev.qn_e - ev.qn, events[i + 1]
            if nx then len = math.min(len, nx.qn - ev.qn - ReleaseGapQN(kind, dl, ev)) end
            if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS and len >= MinSustainQN(dl, ev.bpm) - EPS then
                w[i] = w[i] + p.sustain_bonus
            end
            if #ev.offs >= 2 and p.chord_bonus[dl] then
                -- Only against a single note it competes with (within the tier's gap): a
                -- bonus on every chord of an all-chord passage only rewarded keeping more
                -- of them, off-beats over the downbeat (chronosp bars 18-19).
                local gap = MinGapQN(dl, ev.bpm)
                for j = i - 1, i + 1, 2 do
                    local o = events[j]
                    if o and #o.offs == 1 and math.abs(o.qn - ev.qn) < gap - EPS then
                        w[i] = w[i] + p.chord_bonus[dl]
                        break
                    end
                end
            end
        end
    end
    return w
end

-- The bar each event is in: list of { key, start, len, idx = { event indices } }.
local function Bars(events)
    local bars, order = {}, {}
    for i, ev in ipairs(events) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        local b = bars[key]
        if not b then
            b = { key = key, start = start, len = ev.bar_len or 4, idx = {} }
            bars[key] = b
            order[#order + 1] = b
        end
        b.idx[#b.idx + 1] = i
    end
    return order
end

-- Medium keeps a note per beat in a busy bar. In a bar where the upper tier has more
-- onsets than the bar has beats and Medium kept fewer than its beats, removed upper
-- onsets come back until it has as many as beats: at least an 8th from every kept
-- onset, beats and downbeats first, then by weight, then a held note, then the earlier.
-- From the user's review of chronosp_brutal_decay: bar 7 keeps beat 3 AND the held note on
-- 3& (B . B . G B), bar 11 beat 3 AND the 3& chord (B . B . G GY). Official fast Medium
-- keeps both of such a pair only 5% of the time; the user preferred the bar's pulse.
-- Returns the number of onsets added. shifted: as for Weights - in an "and" phrase the
-- "and"s are the beats.
local function FillBeats(events, keep, w, shifted)
    shifted = shifted or {}
    local added, kept_qn = 0, {}
    for i, ev in ipairs(events) do if keep[i] then kept_qn[#kept_qn + 1] = ev.qn end end
    -- At least an 8th from every kept onset, and not closer than a quarter on BOTH sides:
    -- filling the middle of 36 . 60 (chronosp bar 18) made three 8th chords in a row.
    local function Clear(qn)
        local near_l, near_r = false, false
        for _, k in ipairs(kept_qn) do
            local d = k - qn
            if math.abs(d) < 0.5 - EPS then return false end
            if d < 0 and -d < 1 - EPS then near_l = true end
            if d > 0 and d < 1 - EPS then near_r = true end
        end
        return not (near_l and near_r)
    end
    for _, b in ipairs(Bars(events)) do
        local beats = math.floor(b.len + EPS)
        local n = 0
        for _, i in ipairs(b.idx) do if keep[i] then n = n + 1 end end
        if #b.idx > beats and n < beats then
            local cands = {}
            for _, i in ipairs(b.idx) do
                if not keep[i] then
                    local c = ClassOf(events[i], shifted[i])
                    local ev = events[i]
                    cands[#cands + 1] = { i = i, beat = (c == 'down' or c == 'beat') and 1 or 0, w = w[i],
                                          held = ev.qn_e - ev.qn >= SUSTAIN_QN - EPS and 1 or 0,
                                          rate = PosRate(ev) }
                end
            end
            -- Last tie-break: the bar position official charts keep most (CAP_KEEP_RATE), so
            -- an all-chord syncopated bar (chronosp bar 18) gets 0 12 | 48 60, Hard's own
            -- pairs, rather than three 8ths in a row.
            table.sort(cands, function(a, c)
                if a.beat ~= c.beat then return a.beat > c.beat end
                if a.w ~= c.w then return a.w > c.w end
                if a.held ~= c.held then return a.held > c.held end
                if a.rate ~= c.rate then return a.rate > c.rate end
                return a.i < c.i
            end)
            for _, c in ipairs(cands) do
                if n >= beats then break end
                if Clear(events[c.i].qn) then
                    keep[c.i] = true
                    kept_qn[#kept_qn + 1] = events[c.i].qn
                    n, added = n + 1, added + 1
                end
            end
        end
    end
    return added
end

-- A rewritten Hard note that stands for a beat Expert plays (beat_qn, set by
-- Gen5RetimeDenseRuns) goes back to that beat for Medium and Easy, so the beat is not left
-- empty below Hard: chronosp bar 20's beat 4 sat at 76/24 on Hard. Returns a new list.
local function SnapRewrittenToBeats(events)
    local out, moved = {}, false
    for i, ev in ipairs(events) do
        local src = ev.beat_qn
        if src and math.abs(src - ev.qn) > EPS and ev.bar_qn then
            local pv, nx = events[i - 1], events[i + 1]
            if (not pv or src - pv.qn > MIN_LEN_QN) and (not nx or nx.qn - src > MIN_LEN_QN) then
                local d = src - ev.qn
                local bar_qn = ev.bar_qn + d
                ev = { qn = src, qn_e = ev.qn_e + d, qn_e_full = (ev.qn_e_full or ev.qn_e) + d,
                       offs = ev.offs, bpm = ev.bpm, bar_qn = bar_qn,
                       bar_len = ev.bar_len, down = math.abs(bar_qn) <= EPS, hopo = ev.hopo, src_qn = src }
                moved = true
            end
        end
        out[#out + 1] = ev
    end
    if moved then table.sort(out, function(a, c) return a.qn < c.qn end) end
    return out
end

-- Bars of the same rhythm keep the same Medium onsets on every instrument: the leader's
-- record { [bar start] = { sig = upper onset positions, kept = kept positions } }.
local function RhythmRecord(events, keep)
    local rec = {}
    for _, b in ipairs(Bars(events)) do
        local sig, kept = {}, {}
        for _, i in ipairs(b.idx) do
            local pos = ('%.3f'):format(events[i].bar_qn or events[i].qn % 4)
            sig[#sig + 1] = pos
            if keep[i] then kept[pos] = true end
        end
        rec[b.key] = { sig = table.concat(sig, ' '), kept = kept }
    end
    return rec
end

-- Follow the leader's Medium in bars whose upper rhythm matches. Returns bars followed.
-- spans: "and" phrases (Gen5AndPhrases); a bar touching one keeps its own Medium - the
-- keys lick wins over Guitar's.
local function FollowRhythm(events, keep, ref, spans)
    if not ref then return 0 end
    local followed = 0
    local mine = RhythmRecord(events, keep)
    for _, b in ipairs(Bars(events)) do
        local lead = ref[b.key]
        local in_phrase = false
        for _, s in ipairs(spans or {}) do
            if s.qn_s < b.start + b.len - EPS and s.qn_e > b.start - EPS then in_phrase = true; break end
        end
        if lead and not in_phrase and mine[b.key] and lead.sig == mine[b.key].sig then
            for _, i in ipairs(b.idx) do
                keep[i] = lead.kept[('%.3f'):format(events[i].bar_qn or events[i].qn % 4)] or nil
            end
            followed = followed + 1
        end
    end
    return followed
end

----------------------------------------------------------------------
-- Onset selection
----------------------------------------------------------------------

-- Decide which of the upper tier's onsets tier dl keeps. Arguments and opts as for
-- Gen5PlanTier (difficulty_generate_5lane.lua); log is filled with the rhythm fields
-- (guided, retimed_bars, first_bpm, busy_*, filled, offbeats_dropped, rhythm_*, and_phrases,
-- easy_from_hard). opts.and_source: Easy only, the Hard events (Gen5AndPhrases).
-- Returns (events, keep, guide_len): events is the list keep indexes - on Hard the fast
-- runs already rewritten, on Medium/Easy rewritten notes moved back to their beat - and
-- guide_len[i] the Pro Keys note length a guided Keys onset takes over.
function Gen5SelectOnsets(kind, dl, events, opts, log)
    local keep, guide_len, weights, shifted
    if kind == 'k5' and opts.guide and #opts.guide > 0 then
        -- Easy following a Pro Keys Easy that went back to Hard's downbeats in an "and"
        -- phrase: those notes are not in Keys Medium, so Keys' own Hard notes are
        -- candidates too (the guide decides which survive).
        if dl == 'E' and opts.and_source then
            local have, merged = {}, {}
            for _, ev in ipairs(events) do
                have[math.floor(ev.qn * 96 + 0.5)] = true
                merged[#merged + 1] = ev
            end
            for _, ev in ipairs(opts.and_source) do
                if not have[math.floor(ev.qn * 96 + 0.5)] then
                    local c = {}
                    for k, v in pairs(ev) do c[k] = v end
                    merged[#merged + 1] = c
                end
            end
            table.sort(merged, function(a, c) return a.qn < c.qn end)
            events = merged
        end
        local at
        keep, guide_len, at, log.guide_missed = SelectByGuide(events, opts.guide)
        log.guided = true
        -- Kept notes move onto the Pro Keys onset they follow (same index, so keep and
        -- guide_len still line up; the matching is one-to-one and in order).
        do
            local moved = {}
            for i, ev in ipairs(events) do
                local q = at[i]
                if q and math.abs(q - ev.qn) > 1e-9 then
                    local c = {}
                    for k, v in pairs(ev) do c[k] = v end
                    local d = q - ev.qn
                    c.qn, c.qn_e = q, ev.qn_e + d
                    if ev.qn_e_full then c.qn_e_full = ev.qn_e_full + d end
                    if ev.bar_qn then
                        c.bar_qn = ev.bar_qn + d
                        c.down = math.abs(c.bar_qn) <= EPS
                    end
                    moved[i] = c
                else
                    moved[i] = ev
                end
            end
            events = moved
        end
        -- The guide is a chart someone reduced by hand; still hold Validate's floor, and
        -- never keep two onsets closer than the shortest note that can be written.
        local floor = math.max(K5_MIN_SP[dl] or 0, MIN_LEN_QN)
        do
            local sub = {}
            for i, ev in ipairs(events) do if keep[i] then sub[#sub + 1] = ev end end
            local sub_keep = SelectByGap(sub, function() return floor end)
            local k = 0
            for i in ipairs(events) do
                if keep[i] then
                    k = k + 1
                    if not sub_keep[k] then keep[i] = nil end
                end
            end
        end
    else
        -- Hard on a fast song: dense runs are rewritten one grid slower first. Those notes
        -- are already the reduction, so the gap does not apply between them and their
        -- neighbours (the rewrite keeps them a grid step apart).
        if dl == 'H' then
            -- opts.fast_runs: 'auto' | 'thin' | 'rewrite' (GEN5_PARAMS.fast_runs_default).
            events, log.retimed_bars = Gen5RetimeDenseRuns(events, {
                gap = function(ev) return MinGapQN('H', ev.bpm) end, eps = EPS, mode = opts.fast_runs })
            log.fast_runs = opts.fast_runs or GEN5_PARAMS.fast_runs_default
            -- A note of a run in a bar the rewrite did not change (it neither moved nor
            -- dropped anything there) is an ordinary note again: chronosp bass bar 85's
            -- downbeat ends bar 84's 16ths, and as `retimed` it kept the busy-bar rule off
            -- a bar of straight 8ths.
            local changed = {}
            for _, rb in ipairs(log.retimed_bars) do changed[('%.3f'):format(rb.start)] = true end
            for _, ev in ipairs(events) do
                if ev.retimed then
                    local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
                    -- Still part of the rewritten passage for the force-HOPO markers
                    -- (`rewritten` below): a run's landing note keeps Expert's hammer-on.
                    if not changed[('%.3f'):format(start)] then ev.retimed, ev.joined = nil, true end
                end
            end
        else
            events = SnapRewrittenToBeats(events)
        end
        -- Keys/Pro Keys lick that starts on an "and" (GEN5_PARAMS.and_phrase). Medium: its
        -- phrases are weighed on the "and" grid. Easy (opts.and_source = Hard): the same
        -- phrases, found on Hard, take Hard's notes on the beats instead of Medium's - back
        -- to the downbeats, as the user's korpiklaani hand chart (0:B 2:C).
        if dl == 'M' then
            log.and_phrases = Gen5AndPhrases(events, kind)
            if #log.and_phrases > 0 then
                shifted = {}
                for i, ev in ipairs(events) do
                    if InSpans(log.and_phrases, ev.qn) then shifted[i] = true end
                end
            end
        elseif dl == 'E' and opts.and_source then
            local spans = Gen5AndPhrases(opts.and_source, kind)
            if #spans > 0 then
                local out, n = {}, 0
                for _, ev in ipairs(events) do
                    if not InSpans(spans, ev.qn) then out[#out + 1] = ev end
                end
                for _, ev in ipairs(opts.and_source) do
                    if InSpans(spans, ev.qn) and OnBeat(ev) then
                        local c = {}
                        for k, v in pairs(ev) do c[k] = v end
                        out[#out + 1] = c
                        n = n + 1
                    end
                end
                table.sort(out, function(a, c) return a.qn < c.qn end)
                events = out
                log.and_phrases, log.easy_from_hard = spans, n
            end
        end
        weights = Weights(kind, dl, events, shifted)
        keep = SelectByGap(events, function(ev, earlier)
            if ev.retimed or earlier.retimed then return MIN_LEN_QN end
            return MinGapQN(dl, ev.bpm)
        end, weights)
    end

    -- Busy bars: how many notes each loses (busy_drop). Unset = once per song, from the
    -- tempo at the first note (fast_8ths_bpm).
    local n_drop = opts.busy_drop
    log.first_bpm = events[1] and events[1].bpm or nil
    if not n_drop then
        n_drop = (log.first_bpm or 0) > GEN5_PARAMS.fast_8ths_bpm and 2 or 1
        log.busy_auto = true
    end
    log.busy_drop = n_drop

    -- Busy bars first, in both paths (so Keys following Pro Keys keeps the rule): a bar
    -- gets the per-bar treatment before the song-wide cap could take a whole position
    -- from every bar and leave nothing for it. Hard never takes an isolated onset (see
    -- isolated_qn).
    log.busy_bars, log.busy_followed = ThinBusyBars(events, keep, GEN5_PARAMS.busy_bar_onsets[dl],
        dl == 'H', n_drop, opts.busy_ref)
    if not log.guided then
        CapKeep(events, keep, GEN5_PARAMS.max_keep[dl], dl == 'H', log.upper)
        -- Not when following Pro Keys: Keys and Pro Keys keep the same density.
        if dl == 'M' then
            log.filled = GEN5_PARAMS.fill_beats[dl] and FillBeats(events, keep, weights, shifted) or 0
            -- Barely thinner than Hard: drop the isolated off-beats (offbeat_fallback_keep).
            local fb = GEN5_PARAMS.offbeat_fallback_keep[dl]
            if fb and log.upper > 0 then
                local n = 0
                for i in ipairs(events) do if keep[i] then n = n + 1 end end
                if n / log.upper > fb then log.offbeats_dropped = DropIsolatedOffbeats(events, keep) end
            end
            log.rhythm_followed = FollowRhythm(events, keep, opts.rhythm_ref, log.and_phrases)
            log.rhythm_bars = RhythmRecord(events, keep)
        end
    end
    return events, keep, guide_len
end
