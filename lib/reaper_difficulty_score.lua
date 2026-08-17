-- Difficulty scoring factors for the gem instruments (guitar / bass / drums / keys).
--
-- PURE: no r.*, no S, no ctx. Everything it needs is passed in, so
-- dev/tests/difficulty_score.lua can drive it with synthetic charts and no
-- REAPER project. See dev/calibration/README.md for how the factors below were
-- calibrated and which model each instrument selected.
--
-- ONE IMPLEMENTATION, TWO CONSUMERS. The calibration harness in dev/calibration/
-- and the Metadata > Difficulty suggestion in the general helper both call this
-- file. A second production copy of these formulas would eventually drift, and
-- the drift would silently invalidate the fitted coefficients that were measured
-- against this one - the coefficients only mean anything paired with the exact
-- measurement that produced them. dev/calibration/difficulty_score.lua is a
-- one-line loader kept so the calibration entry points need no edits.
--
-- Well past the 800-line split guideline in CLAUDE.md, and deliberately kept
-- whole: the metrics share file-local constants and helpers, which is the case
-- that guideline's own exception covers. Splitting it is a separate change with
-- its own before/after factor comparison, never a side effect of another one.
--
-- ---------------------------------------------------------------------------
-- Input contract
--
--   events: array sorted by .s, each { s, e, qn, pitches }
--     s, e     project time in seconds (e <= s tolerated and treated as 0-length)
--     qn       quarter-note position of s, from r.TimeMap2_timeToQN
--     pitches  ascending array of MIDI pitches sharing this onset (a chord)
--
--     The caller attaches qn. That is the one thing this module cannot compute
--     for itself (it needs the project tempo map) and it is why the module can
--     stay pure - see the doc's note on keeping the scorer unit-testable.
--
--   spans: array sorted by .s, each { s, e } - the stretches where the
--     instrument is actually playing, from its animation state events.
--     May be empty: a track can carry a real rank and a real chart with no
--     playing state at all (wewillrockyou1's PART BASS). That is a legitimate
--     zero, not an error.
--     Need not be sorted or disjoint on entry: NormalizeSpans sorts and merges
--     first, so every span assumption downstream holds by construction.
--
-- SEGMENTS - the one structural idea in this file
--
--   The spans are not just a filter. Each span is a separate SEGMENT, and no
--   metric may pair the last event of one segment with the first of the next:
--   a chord change across a bar of rest is not a chord change the player has to
--   execute. An earlier version filtered events into the spans and then
--   flattened them into a single array, which silently counted exactly those
--   cross-rest pairs as changes, intervals and hand movement (measured at 0.3%
--   of changes on average, 4.2% worst case).
--
--   So EventsInSegments returns an ARRAY OF ARRAYS, and the pair-based metrics
--   iterate `for each segment, for each consecutive pair within it`. That makes
--   the no-cross-gap property structural rather than a rule each metric has to
--   remember - the previous shape needed six separate "same segment?" checks,
--   and the comment claiming rests were handled outlived the code that would
--   have handled them.
--
--   Pooled, not averaged. Every pair-based statistic collects its pairs from
--   within segments and then computes ONE statistic over the pooled collection.
--   It does NOT compute a per-segment statistic and average those: that would
--   weight a 3-note segment the same as a 300-note one, so a song's score would
--   move when an author split a phrase in two.
--
-- Output: a flat table of named factor values. Deliberately NOT a single
-- weighted score - the weights are what calibration is meant to discover, so
-- the pilot fits over the factor vector instead of guessing them up front.
-- ---------------------------------------------------------------------------

-- Peak-density window, in seconds. Fixed seconds rather than measures so it
-- stays tempo-neutral, consistent with measuring density in real time.
local PEAK_WINDOW_S = 8.0

-- Percentile used for the peak, rather than the single worst window: one
-- accidental double-note should not define a song's peak.
local PEAK_PCTL = 0.95

-- How far off a quarter-note beat an onset may sit and still count as on it, in
-- quarter notes. Well inside a 32nd (0.125 QN), so authored 32nds and 16ths count as
-- off the beat rather than being rounded onto it; loose enough to absorb the float
-- error in a tempo-map conversion, which is around 1e-6.
local OFFBEAT_TOL = 0.02

-- Percentiles of the change-interval distribution, in quarter notes. Replaces an
-- earlier pair of fixed grid buckets (fraction of changes within a 16th / a 32nd),
-- which had two problems: 64ths were folded in with 32nds rather than distinguished,
-- and TRIPLETS fell through entirely - an 8th triplet is 1/3 QN, wider than the 16th
-- threshold of 0.25 yet meaningfully tighter than a straight 8th, so it counted as
-- neither. Percentiles need no list of note values and capture any spacing.
--
-- Both are intervals, so SMALLER MEANS HARDER and their fitted coefficients are
-- expected to be negative.
local TIGHT_PCTL_LOW = 0.10   -- how tight the tightest tenth of changes are
local TIGHT_PCTL_MID = 0.50   -- the typical change interval

-- A note at or above this length (in quarter notes) counts as a sustain. An 8th
-- note, matching SUSTAIN_MIN_DENOM in the helper's actions_midi_length.lua so the
-- two agree on what a sustain is.
local SUSTAIN_MIN_QN = 0.5

-- N-gram length for the repetition measure. 3 is the shortest window that can tell
-- a repeated riff from coincidentally repeated pairs.
local REPEAT_NGRAM = 3

-- Context length for the conditional-entropy measure: how many previous shapes the
-- next one is predicted from.
--
-- 2, and the choice is load-bearing. On the arpeggio figure that motivated this factor
-- ("1 2 3 2" repeating) a context of ONE shape leaves real ambiguity - after shape 2 the
-- next is 3 or 1 with equal probability, so it reads 0.5 bits against log2(3) = 1.58 for
-- random. A context of TWO determines the successor outright and it reads 0 bits, which
-- is the honest description of a figure the hand plays without deciding anything.
--
-- Going further (3+) would discriminate no better and would make contexts too sparse to
-- estimate: the number of possible contexts grows as v^k, and the estimator's downward
-- bias grows with it.
local ENTROPY_K = 2

-- Default gap for the fallback span derivation, in quarter notes.
-- 8 QN = two 4/4 measures, the doc's starting suggestion.
local FALLBACK_GAP_QN = 8.0

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

function TotalSpanSeconds(spans)
    local total = 0
    for _, sp in ipairs(spans) do
        local d = sp.e - sp.s
        if d > 0 then total = total + d end
    end
    return total
end

-- Sorted, disjoint, positive-length spans. Every span assumption in this file
-- (TotalSpanSeconds not double-counting, EventsInSegments' single forward walk,
-- SpanOverlapSeconds' documented "non-overlapping" precondition) is true only
-- for input of this shape, so normalize once at entry rather than trusting each
-- caller. Touching spans merge too: an idle event at the exact instant the next
-- playing event starts is not a rest, and leaving them separate would split a
-- continuous passage into two segments and lose the pair across the join.
function NormalizeSpans(spans)
    local out = {}
    for _, sp in ipairs(spans or {}) do
        if sp.e > sp.s then out[#out + 1] = { s = sp.s, e = sp.e } end
    end
    table.sort(out, function(a, b) return a.s < b.s end)

    local merged = {}
    for _, sp in ipairs(out) do
        local last = merged[#merged]
        if last and sp.s <= last.e then
            if sp.e > last.e then last.e = sp.e end
        else
            merged[#merged + 1] = sp
        end
    end
    return merged
end

-- Events grouped into one array per span - see the SEGMENTS note in the header.
-- spans must be normalized (sorted and disjoint); walks both lists once rather
-- than testing every event against every span.
--
-- A span's end is INCLUSIVE: an event landing exactly on the closing idle
-- event's timestamp counts as in-span. Kept deliberately from the pre-segment
-- version so the restructure changes segmentation and nothing else.
--
-- Segments with no events are OMITTED rather than returned empty, so no consumer
-- needs an emptiness check and #segments carries no relationship to #spans (no
-- consumer wants one). A song of nothing but empty spans yields {}, which the
-- callers already handle as "no events".
function EventsInSegments(events, spans)
    local segs = {}
    local cur  = nil
    local si   = 1
    for _, ev in ipairs(events) do
        while si <= #spans and spans[si].e < ev.s do
            si  = si + 1
            cur = nil          -- a new span always opens a new segment
        end
        if si > #spans then break end
        if ev.s >= spans[si].s and ev.s <= spans[si].e then
            if not cur then
                cur = {}
                segs[#segs + 1] = cur
            end
            cur[#cur + 1] = ev
        end
    end
    return segs
end

-- Every in-span event in time order, for the metrics that are genuinely
-- per-event (counts, chord size/span, sustains) and so cannot be affected by
-- segment boundaries at all.
local function FlattenSegments(segs)
    local flat = {}
    for _, seg in ipairs(segs) do
        for _, ev in ipairs(seg) do flat[#flat + 1] = ev end
    end
    return flat
end

local function NoteCount(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

-- True when two chord events differ in their pitch SET (not just lowest note).
-- Both pitch arrays are ascending, so a positional compare is enough.
local function PitchSetChanged(a, b)
    if #a.pitches ~= #b.pitches then return true end
    for i = 1, #a.pitches do
        if a.pitches[i] ~= b.pitches[i] then return true end
    end
    return false
end

-- Pitches sounding at an event but struck earlier - the `held` field the reader
-- attaches. Absent on any caller that has not been updated, and empty on guitar and
-- bass by authoring rule, so both cases read as "no polyphony".
local function HeldCount(ev)
    return ev.held and #ev.held or 0
end

-- Whether the two events describe the same set of FINGERS ENGAGED, counting held
-- notes as well as struck ones.
--
-- The distinction only exists on 5-lane keys, where overlapping gems are legal: a
-- green sustained under a melody makes {green} then {red} then {yellow} look like
-- three different pitch sets, when the hand is holding green throughout and moving one
-- finger. PitchSetChanged calls each of those a change; this does not.
local function SoundingSetChanged(a, b)
    local function Set(ev)
        local s, n = {}, 0
        for _, p in ipairs(ev.pitches) do
            if not s[p] then s[p] = true; n = n + 1 end
        end
        for _, p in ipairs(ev.held or {}) do
            if not s[p] then s[p] = true; n = n + 1 end
        end
        return s, n
    end
    local sa, na = Set(a)
    local sb, nb = Set(b)
    if na ~= nb then return true end
    for p in pairs(sa) do
        if not sb[p] then return true end
    end
    return false
end

-- Linear-interpolated percentile of a SORTED array. Defined up here because both
-- HandMovement and PeakDensity need it.
function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then return 0 end
    if n == 1 then return sorted[1] end
    local idx = p * (n - 1) + 1
    local lo  = math.floor(idx)
    local hi  = math.ceil(idx)
    if lo == hi then return sorted[lo] end
    local frac = idx - lo
    return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
end

-- How far the hand has to travel between consecutive events, in lane units.
--
-- THE GAP THIS FILLS: nothing else here measures distance. change_rate counts
-- whether the gems changed, the tightness percentiles measure when, chord_span_mean
-- measures width within a single chord - but a chart alternating green-red and one
-- jumping green-orange score identically on every other factor, despite being very
-- different to play. That is the "identical density, different difficulty" case, and
-- it is the shape of the corpus's one persistent failure: charts around rank 180-225
-- (crawling2, californication, ridersonthestorm, workingfortheweekend) that are busy
-- but sit in one hand position, which the model over-rates as hard.
--
-- Uses the centroid (mean pitch) of each event so chords are handled sensibly rather
-- than by an arbitrary pick of lowest or highest note. Movement is per-event, not
-- per-second, which keeps it orthogonal to change_rate by construction: one is how
-- FAR, the other how OFTEN.
--
-- Rests are excluded STRUCTURALLY, by iterating within each segment: the first
-- event of a segment has no predecessor, so no distance is measured across a rest.
-- The hand does not travel from the last note before a bar of silence to the first
-- note after it under any time pressure, and counting that as movement inflated
-- exactly the songs with the most rests. Distances pool across segments; only the
-- pairing is per-segment.
--
-- Returns move_mean, move_p90, anchor_frac.
--   move_mean   average lane distance moved between consecutive events
--   move_p90    90th percentile, i.e. how big the big jumps are
--   anchor_frac fraction of consecutive pairs sharing at least one lane, so the
--               hand can stay anchored rather than relocating
local function HandMovement(segs)
    local function Centroid(ev)
        local s = 0
        for _, p in ipairs(ev.pitches) do s = s + p end
        return s / #ev.pitches
    end

    local dists, anchored = {}, 0
    for _, seg in ipairs(segs) do
        local prev_c = (#seg > 0) and Centroid(seg[1]) or 0
        for i = 2, #seg do
            local ev = seg[i]
            local c  = Centroid(ev)
            dists[#dists + 1] = math.abs(c - prev_c)
            prev_c = c

            -- Shared lane between this event and the previous one.
            local prev = seg[i - 1]
            local seen = {}
            for _, p in ipairs(prev.pitches) do seen[p] = true end
            for _, p in ipairs(ev.pitches) do
                if seen[p] then anchored = anchored + 1 break end
            end
        end
    end
    if #dists == 0 then return 0, 0, 0 end

    local sum = 0
    for _, d in ipairs(dists) do sum = sum + d end
    table.sort(dists)
    return sum / #dists, Percentile(dists, 0.90), anchored / #dists
end

-- Minimum cost of reassigning fingers between two struck note sets. Shared pitches
-- retain a finger for free; the remaining notes are optimally paired by semitone
-- distance, with one unit charged for each added or removed finger. Pro Keys chords
-- contain at most four notes, so the exhaustive assignment is tiny and exact.
local function FingerReassignmentCost(a, b)
    local aa, bb, used = {}, {}, {}
    local in_b = {}
    for _, p in ipairs(b.pitches) do in_b[p] = (in_b[p] or 0) + 1 end
    for _, p in ipairs(a.pitches) do
        if (in_b[p] or 0) > 0 then in_b[p] = in_b[p] - 1 else aa[#aa + 1] = p end
    end
    local in_a = {}
    for _, p in ipairs(a.pitches) do in_a[p] = (in_a[p] or 0) + 1 end
    for _, p in ipairs(b.pitches) do
        if (in_a[p] or 0) > 0 then in_a[p] = in_a[p] - 1 else bb[#bb + 1] = p end
    end

    if #aa > #bb then aa, bb = bb, aa end
    local best = math.huge
    local function visit(i, cost)
        if cost >= best then return end
        if i > #aa then
            best = cost + (#bb - #aa) -- fingers added/removed after optimal matching
            return
        end
        for j = 1, #bb do
            if not used[j] then
                used[j] = true
                visit(i + 1, cost + math.abs(aa[i] - bb[j]))
                used[j] = nil
            end
        end
    end
    if #aa == 0 then return #bb end
    visit(1, 0)
    return best
end

local function ProKeysCoordination(segs, window_s, pctl)
    local costs, timed, held_rates = {}, {}, {}
    for _, seg in ipairs(segs) do
        for i = 2, #seg do
            local cost = FingerReassignmentCost(seg[i - 1], seg[i])
            costs[#costs + 1] = cost
            timed[#timed + 1] = { s = seg[i].s, cost = cost }
        end
        for i = 1, #seg do
            local limit, held_hits = seg[i].s + window_s, 0
            for j = i, #seg do
                if seg[j].s > limit then break end
                if HeldCount(seg[j]) > 0 then held_hits = held_hits + #seg[j].pitches end
            end
            held_rates[#held_rates + 1] = held_hits / window_s
        end
    end
    if #costs == 0 then return 0, 0, 0, 0 end
    local sum = 0
    for _, v in ipairs(costs) do sum = sum + v end
    table.sort(costs)
    local window_costs = {}
    for i = 1, #timed do
        local total, limit = 0, timed[i].s + window_s
        for j = i, #timed do
            if timed[j].s > limit then break end
            total = total + timed[j].cost
        end
        window_costs[#window_costs + 1] = total / window_s
    end
    table.sort(window_costs)
    table.sort(held_rates)
    return sum / #costs, Percentile(costs, 0.90),
           Percentile(window_costs, pctl), Percentile(held_rates, pctl)
end

-- Compact key for one event's gem set. NOT transposed or normalized: on a PART
-- track these pitches are lanes, so the literal set is what repeats.
local function ShapeKey(ev)
    if #ev.pitches == 1 then return tostring(ev.pitches[1]) end
    return table.concat(ev.pitches, '.')
end

-- TRANSPOSITION-INVARIANT key: the MOTION into this event rather than its position.
-- Encodes the step from the previous event's lowest lane, plus this event's own
-- internal intervals, so a figure played at green/red/yellow and the same figure at
-- yellow/blue/orange produce identical keys.
--
-- WHY BOTH ENCODINGS EXIST. ShapeKey above is right for guitar - a lane is a lane, and
-- the literal set is what the hand has learned. But `surrender`'s keys chart is one
-- broken-chord figure played at three positions in turn (G/R/Y, then R/Y/B, then
-- Y/B/O) with the hand motion never changing. Literally, that is three unrelated
-- blocks and any context spanning them looks novel; as motion it is a single motif
-- repeated all song. The saturating repetition fraction below could not tell the
-- difference (it read 0.98 either way); an entropy measure can.
--
-- prev == nil marks a segment start, where there is no incoming step to encode.
local function MotionKey(ev, prev)
    local step = prev and (ev.pitches[1] - prev.pitches[1]) or 'x'
    if #ev.pitches == 1 then return tostring(step) end
    local rel = {}
    for i = 2, #ev.pitches do rel[#rel + 1] = ev.pitches[i] - ev.pitches[1] end
    return tostring(step) .. '/' .. table.concat(rel, '.')
end

-- Conditional entropy of the next shape given the previous k shapes, in BITS.
--
-- THE FIX THE DESIGN DOC HAS ASKED FOR SINCE ROUND 3. RepetitionFraction below
-- measures the share of n-gram windows already seen, which saturates: over a 5-lane
-- vocabulary almost every window recurs once a chart is long enough, so nearly
-- everything reads near 1.0 and the measure cannot separate "repetitive" from "very
-- repetitive". On the keys corpus it correlates -0.008 with rank while reading 0.98 on
-- both of the two charts it most obviously ought to flag.
--
--   H = -SUM over (context c, next s) of (n_cs / N) * log2(n_cs / n_c)
--
-- LENGTH-INVARIANT BY CONSTRUCTION, which is the whole point: looping a riff twice
-- doubles every count, leaves every conditional probability unchanged, and returns the
-- same number. A perfectly predictable part reads 0 bits; a uniformly random sequence
-- over v shapes reads log2(v).
--
-- SMALL-SAMPLE BIAS IS REAL AND RUNS THE WRONG WAY. The plug-in estimator is biased
-- DOWNWARD: with k=2, a short varied chart can have almost every context occur exactly
-- once, which makes it read as perfectly predictable - the old metric's confound in
-- reverse, and it would put the hardest sparse charts in the same bucket as the
-- easiest loops. Corrected with Miller-Madow, (m-1)/(2*N*ln2) where m counts observed
-- non-zero cells, and the caller also gets the context count so a chart too sparse to
-- trust is visible rather than silent.
--
-- Contexts never straddle a rest (they are built per segment), but the counts are
-- POOLED across segments: a motif returning in verse 2 is the same motif, and that is
-- exactly the predictability being measured.
--
-- key_fn(ev, prev) supplies the encoding, so the same estimator serves both the
-- literal and the transposition-invariant variants.
--
-- Returns entropy_bits, n_contexts.
local function ConditionalEntropy(segs, k, key_fn)
    local counts, ctx_total = {}, {}
    local n_trans = 0
    for _, seg in ipairs(segs) do
        -- Encode the whole segment first: MotionKey needs each event's predecessor.
        local sym = {}
        for i = 1, #seg do sym[i] = key_fn(seg[i], (i > 1) and seg[i - 1] or nil) end
        for i = k + 1, #sym do
            local parts = {}
            for j = i - k, i - 1 do parts[#parts + 1] = sym[j] end
            local c = table.concat(parts, '|')
            counts[c] = counts[c] or {}
            counts[c][sym[i]] = (counts[c][sym[i]] or 0) + 1
            ctx_total[c] = (ctx_total[c] or 0) + 1
            n_trans = n_trans + 1
        end
    end
    if n_trans == 0 then return 0, 0 end

    local h, cells, n_ctx = 0, 0, 0
    for c, nexts in pairs(counts) do
        n_ctx = n_ctx + 1
        local nc = ctx_total[c]
        for _, ncs in pairs(nexts) do
            cells = cells + 1
            h = h - (ncs / n_trans) * (math.log(ncs / nc) / math.log(2))
        end
    end
    -- Miller-Madow: the plug-in estimate understates entropy roughly in proportion to
    -- how many cells were observed relative to the sample size.
    h = h + (cells - 1) / (2 * n_trans * math.log(2))
    return h, n_ctx
end

-- Robust upper tail of sections that are busy AND unpredictable. Whole-song peak
-- density and whole-song entropy can cancel: a chart may have a fast repeated verse
-- and a slow novel bridge while never presenting both demands together. This explicit
-- local interaction uses the same real-time window and relative-motion entropy as the
-- existing factors. Windows with fewer than four events have no reliable transition
-- context and contribute zero.
local function LocalComplexityPeak(segs, window_s, pctl)
    local values = {}
    for _, seg in ipairs(segs) do
        for i = 1, #seg do
            local win, gems, limit = {}, 0, seg[i].s + window_s
            for j = i, #seg do
                if seg[j].s > limit then break end
                win[#win + 1] = seg[j]
                gems = gems + #seg[j].pitches
            end
            if #win >= 4 then
                local h = ConditionalEntropy({ win }, 1, MotionKey)
                values[#values + 1] = (gems / window_s) * h
            else
                values[#values + 1] = 0
            end
        end
    end
    if #values == 0 then return 0 end
    table.sort(values)
    return Percentile(values, pctl)
end

-- Fraction of n-gram windows over the gem-shape sequence whose exact pattern has
-- already appeared earlier in the chart.
--
-- This is the factor the residuals asked for. Nothing else in the set can separate
-- "1781 notes of one repeating bass line" (bluemonday, official rank 230) from
-- "240 notes of constantly shifting shapes" (wanteddeadoralive2, rank 315) - both
-- look similar on density, change rate and totals, yet the sparse technical chart
-- is officially the harder of the two.
--
-- A riff looped many times approaches 1.0; a passage that never repeats an n-gram
-- is 0.0. Counts distinct windows, so a pattern seen 40 times contributes 39
-- repeats rather than being collapsed to one.
--
-- Windows never straddle a rest, but `seen` is deliberately SHARED across
-- segments: a riff that returns in verse 2 after a rest is a repeat of the same
-- riff, which is the entire thing this factor is trying to notice. Only the
-- window may not span a gap; the memory must.
local function RepetitionFraction(segs, n)
    local seen, repeats, total = {}, 0, 0
    local parts = {}
    for _, seg in ipairs(segs) do
        for i = 1, #seg - n + 1 do
            for j = 1, n do parts[j] = ShapeKey(seg[i + j - 1]) end
            local key = table.concat(parts, '|')
            total = total + 1
            if seen[key] then repeats = repeats + 1 else seen[key] = true end
        end
    end
    if total == 0 then return 0 end
    return repeats / total
end

-- Fraction of in-span events at or above the sustain threshold.
--
-- Needs each event's END in quarter-note terms, which only the caller can supply
-- (it owns the tempo map). Returns nil when qn_e is absent, so a caller that has
-- not been updated reports "not measured" rather than a silent zero that would look
-- like "no sustains at all".
local function SustainFraction(in_span)
    local n_sus, n_tot = 0, 0
    for _, ev in ipairs(in_span) do
        if ev.qn_e == nil then return nil end
        local len = ev.qn_e - ev.qn
        if len > 0 then
            n_tot = n_tot + 1
            if len >= SUSTAIN_MIN_QN then n_sus = n_sus + 1 end
        end
    end
    if n_tot == 0 then return 0 end
    return n_sus / n_tot
end

-- Seconds of overlap between two sorted, non-overlapping span lists.
function SpanOverlapSeconds(a, b)
    if not a or not b or #a == 0 or #b == 0 then return 0 end
    local total, j = 0, 1
    for _, sa in ipairs(a) do
        while j <= #b and b[j].e < sa.s do j = j + 1 end
        local k = j
        while k <= #b and b[k].s <= sa.e do
            local lo = (b[k].s > sa.s) and b[k].s or sa.s
            local hi = (b[k].e < sa.e) and b[k].e or sa.e
            if hi > lo then total = total + (hi - lo) end
            k = k + 1
        end
    end
    return total
end

-- True when t falls inside any span. spans must be sorted and disjoint.
local function InSpans(spans, t)
    for _, sp in ipairs(spans) do
        if t < sp.s then return false end
        if t <= sp.e then return true end
    end
    return false
end

-- PRO DRUMS VOCABULARY. Rewrites yellow/blue/green gems sitting inside their own lane's
-- tom marker to a distinct pitch, so the eight things a Pro kit can be asked to hit are
-- eight different gems instead of five.
--
-- WHY THIS IS NOT THE SAME QUESTION AS tom_frac. Coverage is a fraction; this changes gem
-- IDENTITY, which is what every shape-based factor is built on. As things stand a yellow
-- cymbal followed by a yellow tom is not a change at all: total_changes - the strongest
-- or second-strongest factor on every instrument fitted so far - counts zero, the change
-- interval never opens, and the entropy encoder sees a repeated shape. A chart
-- alternating a colour between its cymbal and its tom reads as maximally repetitive while
-- the player alternates two pads.
--
-- THE OFFSET IS A DISTINCTNESS DEVICE, NOT A DISTANCE. Only the fact that a marked gem
-- gets a different value matters; the magnitude and sign are arbitrary and VERIFIED to be
-- so. Every factor the Pro pass keeps reads set IDENTITY (which gems, did the set change,
-- how long until it changed, what shape came next), and none reads lane distance. Scoring
-- a mixed chart at offsets of -0.9, -0.5, -0.1, +0.25, +0.5 and +3.0 gives bit-identical
-- pro_total_changes, pro_change_rate, pro_tight_p10, pro_tight_med and pro_entropy_h2,
-- while move_mean and move_p90 move around freely - which is exactly why those two are
-- not among the columns this pass keeps. There is a test pinning the invariance.
--
-- DO NOT REUSE THIS NUMBER AS GEOMETRY. An earlier version of this comment justified the
-- sign by saying a rack tom sits beside the snare while the hihat is further out. That
-- describes an acoustic kit, not the RB3 controller, where the cymbal attachments mount
-- ABOVE AND BEHIND the yellow/blue/green pads: reaching either the yellow pad or the
-- yellow cymbal is the same lateral move to the yellow station, and the cymbal costs only
-- a small extra excursion. So snare-to-yellow-cymbal and snare-to-yellow-tom are close to
-- the same distance, NOT the 2:1 that a half-lane offset would imply.
--
-- If a Pro-aware distance factor is ever added (pro_move_mean and friends), that geometry
-- has to be settled first, and the shape it wants is the opposite of what is written here:
-- the PAD is the lane position and the CYMBAL is the small excursion from it, rather than
-- the tom sitting half a lane away. Until then this offset is a symbol, not a measurement.
--
-- Returns a NEW event list. The caller's events are untouched, because the same chart
-- gets scored again under the standard five-gem vocabulary and the two compared.
local PRO_TOM_OFFSET = -0.5

function ProRemapEvents(events, tom_spans)
    local out = {}
    for i, ev in ipairs(events) do
        local pitches = {}
        for j, p in ipairs(ev.pitches) do
            local lane = tom_spans and tom_spans[p]
            pitches[j] = (lane and InSpans(lane, ev.s)) and (p + PRO_TOM_OFFSET) or p
        end
        table.sort(pitches)
        out[i] = { s = ev.s, e = ev.e, qn = ev.qn, qn_e = ev.qn_e,
                   pitches = pitches, held = ev.held }
    end
    return out
end

-- How much harder the marked solo is than the rest of the chart.
--
-- THE POINT, and why coverage alone will not do: solo COVERAGE does not predict
-- rank. ridersonthestorm carries the largest solo marker in the sampled corpus
-- (20.9% of its track) and is rated 180 - easy - while webuiltthiscity's 11.1%
-- solo belongs to a rank-418 chart. The difference is what is INSIDE the solo:
-- a slow melodic solo and a shred solo are the same fraction of playing time.
--
-- So this measures the change rate inside the solo against the change rate
-- outside it. A shred solo in an otherwise slow song scores high; a slow solo
-- scores near 1 and correctly leaves the rating alone.
--
-- Returns ratio, measured.
--   ratio     inside-solo change rate / outside-solo change rate
--   measured  false when there is no solo marker, or no changes outside it
--
-- Returns 1.0 (NEUTRAL), never 0, when unmeasurable. A 0 would tell the fit the
-- solo is infinitely easier than the rest of the chart, which is the same trap
-- sustain_frac and tight_measured already guard against - and unlike those it
-- would fire on the majority of songs, since most charts have no solo at all.
local function SoloChangeRatio(segs, solo_spans)
    if not solo_spans or #solo_spans == 0 then return 1.0, false end

    -- Changes and elapsed quarter notes, split by whether the change happened
    -- inside a solo. Rates are per QN rather than per second so the comparison
    -- is unaffected by a tempo change between the solo and the rest - a solo at
    -- double tempo would otherwise read as denser without more notes.
    -- A pair counts only when BOTH its events are on the same side of the solo
    -- boundary; one that straddles it belongs to neither. Attributing a straddling
    -- pair by its later event carries the whole pre-solo wait into the solo's
    -- elapsed time, which dilutes exactly the measurement being taken - a solo
    -- entered after 9 quiet quarter notes read 1.9x denser than its surroundings
    -- instead of the true 4x. Same principle as the segment rule: a pair spanning a
    -- boundary describes neither of the things the boundary separates.
    local ch_in,  qn_in  = 0, 0
    local ch_out, qn_out = 0, 0
    for _, seg in ipairs(segs) do
        for i = 2, #seg do
            local ev   = seg[i]
            local prev = seg[i - 1]
            local in_ev, in_prev = InSpans(solo_spans, ev.s), InSpans(solo_spans, prev.s)
            if in_ev == in_prev then
                local dqn = ev.qn - prev.qn
                local hit = PitchSetChanged(ev, prev) and 1 or 0
                if in_ev then
                    ch_in, qn_in = ch_in + hit, qn_in + dqn
                else
                    ch_out, qn_out = ch_out + hit, qn_out + dqn
                end
            end
        end
    end
    if qn_in <= 0 or qn_out <= 0 or ch_out == 0 then return 1.0, false end
    return (ch_in / qn_in) / (ch_out / qn_out), true
end

-- Notes per second in the busiest windows. Two pointers over each segment's
-- events: for each onset, count the notes falling in [t, t + window].
--
-- `weight_fn(ev)` decides what one event contributes, defaulting to its gem count.
-- Passing a constant 1 instead measures ATTACKS per second - how often the hand moves,
-- as opposed to how many gems are under it. The two differ by the chord size, and on a
-- chart of single notes they are identical. Kept as a parameter rather than two copies
-- of the sliding window, since the windowing is the part that is easy to get wrong.
--
-- Windows are confined to ONE SEGMENT, so a window can no longer collect notes
-- from two bursts either side of a rest while counting the rest as time - the
-- failure mode that let a song of short stabs read as continuously dense.
--
-- The denominator stays a fixed window_s even for a segment shorter than the
-- window, which understates such a segment's local density. That is not a
-- compromise, it is the definition: density_peak asks what the busiest 8 seconds
-- the player faces contains, and 8 real seconds holding a 5-second burst plus 3
-- seconds of rest genuinely is less demanding than 8 seconds of continuous burst.
-- The rest is real rest, and the player gets it. Clamping the denominator to the
-- segment length would instead report a 1-second span of 4 notes as 4 notes/sec,
-- which is the small-denominator noise PEAK_PCTL exists to suppress.
--
-- Windows late in a segment are truncated by the segment end and so understate -
-- now hundreds of times per song rather than once at the chart end. Still
-- harmless, because the percentile reads the busiest windows, not the sparsest.
--
-- Densities pool across segments; only the windowing is per-segment.
local function EventGems(ev) return #ev.pitches end
local function EventOne() return 1 end

local function PeakDensity(segs, window_s, pctl, weight_fn)
    if window_s <= 0 then return 0, 0 end
    weight_fn = weight_fn or EventGems
    -- Sliding window: j only ever moves forward within a segment, and each event
    -- leaves the window exactly once as the left edge passes it, so this is O(n).
    local densities = {}
    for _, seg in ipairs(segs) do
        local j, running = 1, 0
        for i = 1, #seg do
            if i > 1 then running = running - weight_fn(seg[i - 1]) end
            local limit = seg[i].s + window_s
            while j <= #seg and seg[j].s <= limit do
                running = running + weight_fn(seg[j])
                j = j + 1
            end
            densities[#densities + 1] = running / window_s
        end
    end
    if #densities == 0 then return 0, 0 end
    table.sort(densities)
    return Percentile(densities, pctl), densities[#densities]
end

-- How many DIFFERENT places the hand has to cover in the busiest windows: distinct gem
-- identities inside a sliding window, read at the same percentile as PeakDensity.
--
-- WHY THIS EXISTS ONLY FOR PRO DRUMS. Under the standard five-gem vocabulary the measure
-- is useless because it is saturated: across the corpus the busiest 8 seconds of a drum
-- chart contains a mean of 4.77 of the 5 available lanes, with the 25th AND 75th
-- percentiles both sitting at 5. Nearly every chart visits every lane, so there is nothing
-- to tell charts apart with. Under the eight-gem Pro vocabulary the same measure spreads
-- properly - mean 6.02 of 8, p25 5, p75 7, range 2 to 8 - because a colour used as a tom
-- in one section and a cymbal in another is two places rather than one.
--
-- So this is a difficulty axis that does not exist under the five-gem encoding, which is
-- the concrete form of "a player without the cymbal extension is playing an easier chart".
-- It needs NO geometry model: counting stations never asks how far apart they are, which
-- is what keeps the unsettled tom-versus-cymbal reach question out of it.
--
-- Counting is O(n * k) over the events in a window rather than incremental, because a
-- symbol leaving the window only drops the count if it was the last of its kind. Windows
-- hold tens of events, so the naive count is cheap and obviously correct.
local function PeakStations(segs, window_s, pctl)
    if window_s <= 0 then return 0 end
    local counts = {}
    for _, seg in ipairs(segs) do
        for i = 1, #seg do
            local limit, seen, n = seg[i].s + window_s, {}, 0
            for j = i, #seg do
                if seg[j].s > limit then break end
                for _, p in ipairs(seg[j].pitches) do
                    if not seen[p] then seen[p] = true; n = n + 1 end
                end
            end
            counts[#counts + 1] = n
        end
    end
    if #counts == 0 then return 0 end
    table.sort(counts)
    return Percentile(counts, pctl)
end

----------------------------------------------------------------------
-- Fallback span derivation
----------------------------------------------------------------------

-- Derive playing spans from the notes themselves, for tracks whose animation
-- states are missing or say the instrument never plays. Splits on any gap
-- wider than gap_qn quarter notes. Pure; operates on the qn field.
--
-- This is the fallback the doc insists on keeping: without it wewillrockyou1's
-- bass (rank 096, idle-only) drops out of the Warmup tier the corpus can least
-- afford to lose.
--
-- Returns NORMALIZED spans (sorted, disjoint). Resetting cur_e on a split is not
-- on its own enough to guarantee that: the gap is measured between ONSETS while a
-- span carries note ENDS, so a sustain longer than the gap has its tail overrun
-- the following span's start no matter what cur_e holds. Merging is the right
-- resolution rather than a papering-over - a note still ringing when the next one
-- arrives means the instrument never stopped, so it is one continuous span.
--
-- KNOWN LIMITATION, deliberately not changed here: because the gap is measured
-- onset-to-onset, a chart of long notes spaced just over gap_qn apart splits even
-- though the sustains leave little actual silence. Measuring onset-to-previous-END
-- would be more faithful to "a rest wider than gap_qn", but it changes what the
-- fallback measures, and doing that in the same change as the segmentation fix
-- would confound the one comparison that fix exists to make. Revisit separately;
-- it currently affects 1 row of the corpus.
function DeriveSpansFromEvents(events, gap_qn)
    gap_qn = gap_qn or FALLBACK_GAP_QN
    if #events == 0 then return {} end

    local spans   = {}
    local cur_s   = events[1].s
    local cur_e   = events[1].e > events[1].s and events[1].e or events[1].s
    local prev_qn = events[1].qn

    for i = 2, #events do
        local ev = events[i]
        if (ev.qn - prev_qn) > gap_qn then
            spans[#spans + 1] = { s = cur_s, e = cur_e }
            -- Reset the END as well as the start. Carrying cur_e forward let the
            -- closed span's end bleed into the next one, so a sustain outliving
            -- the gap produced two OVERLAPPING spans - double-counted by
            -- TotalSpanSeconds and able to drop an event in EventsInSegments.
            -- Rare (it needs a note longer than gap_qn), but span boundaries are
            -- now the precise thing being measured.
            cur_s = ev.s
            cur_e = (ev.e > ev.s) and ev.e or ev.s
        end
        cur_e   = (ev.e > cur_e) and ev.e or cur_e
        prev_qn = ev.qn
    end
    spans[#spans + 1] = { s = cur_s, e = cur_e }
    return NormalizeSpans(spans)
end

----------------------------------------------------------------------
-- The scorer
----------------------------------------------------------------------

-- opts (all optional):
--   peak_window_s, peak_pctl   peak-density window and percentile
--   solo_spans                 [play_solo] ANIMATION spans, for solo_frac
--   marked_solo_spans          pitch-103 spans - the authored solo
--   tremolo_spans              pitch-126 spans, for tremolo_frac
--   trill_spans                pitch-127 spans, for trill_frac
--   gliss_spans                PRO KEYS: pitch-126 spans read as GLISSANDO lanes, for
--                              gliss_frac. Same pitch as tremolo_spans, opposite meaning,
--                              so a caller passes one or the other and never both
--   lane_shifts                PRO KEYS: ordered { s = time, base = window base pitch },
--                              for shift_rate and shift_span_mean
--   force_hopo_count           lo+5 marker count, for force_hopo_rate
--   force_strum_count          lo+6 marker count, for force_strum_rate
--   kick_pitch                 DRUMS: the kick-pedal pitch (96). Its presence switches
--                              on the limb-aware factors and nothing else
--   tom_spans                  DRUMS: { [gem pitch] = spans }, e.g. { [98] = <110 spans> }.
--                              Its presence also triggers the Pro Drums second pass
--   pro_pass                    internal: set on the recursive Pro pass to stop it
--                              recursing again. Callers never set it
--   roll_spans                 DRUMS: 126 and 127 spans, already combined
--   offbeat                    measure offbeat_frac (instrument-agnostic; opt-in so the
--                              column is only computed where a caller asks for it)
--
-- Returns a table. Grouped by what each factor actually measures, because the groups
-- matter more than the individual columns:
--
--   ENDURANCE
--     playing_s        seconds the instrument is actually playing
--   SPEED
--     density_avg      notes per second over playing time
--     density_peak     95th-percentile windowed notes/sec
--     attack_density_avg   EVENTS per second - one per onset regardless of chord size
--     attack_density_peak  95th-percentile windowed events/sec
--     change_rate      pitch-set changes per second
--   LIMBS  (drums only; 0 elsewhere)
--     kick_density       kick gems per second - the foot's own rate
--     kick_density_peak  95th-percentile windowed kicks/sec
--     hand_density_peak  95th-percentile windowed HAND gems/sec, foot excluded
--     stick_size_mean    mean HAND gems per event that has any; 1.0 = never two sticks
--   DRUM MARKERS  (drums only)
--     tom_frac         share of yellow/blue/green gems under THEIR OWN lane's marker
--     roll_frac        share of playing time under a 126/127 roll lane
--   PRO DRUMS  (drums only) - the same chart over an EIGHT-gem vocabulary, where a tom
--   and a cymbal on one colour are two different gems. See ProRemapEvents.
--     pro_total_changes, pro_change_rate, pro_tight_p10, pro_tight_med, pro_entropy_h2
--     pro_stations_peak  distinct gem identities in the busiest window - the only one of
--                        these measuring something the five-gem vocabulary cannot express
--   RHYTHM
--     offbeat_frac     share of onsets off the quarter-note grid
--   TIGHTNESS  (intervals: SMALLER IS HARDER, expect negative coefficients)
--     tight_p10        10th-percentile change interval, in quarter notes
--     tight_med        median change interval, in quarter notes
--   HAND LOAD
--     chord_size_mean    mean pitches STRUCK per event; 1.0 = all single notes
--     chord_span_mean    mean lane spread over chord events only
--     chord_change_frac  fraction of changes that land on a chord
--   POLYPHONY  (5-lane keys; structurally 0 where overlaps are forbidden)
--     sounding_size_mean mean fingers ENGAGED per event, struck plus held
--     overlap_frac       fraction of events with a note still sounding from earlier
--     held_change_frac   fraction of struck-set changes that are not changes in the
--                        set of fingers engaged - a note re-articulated inside a shape
--                        that is still held. Expected small even on keys; it exists so
--                        the change tally's overstatement is measurable, not assumed
--   HAND MOVEMENT  (how FAR, as opposed to how often or when)
--     move_mean          mean lane distance between consecutive events
--     move_p90           90th percentile of that distance: the big jumps
--     anchor_frac        fraction of consecutive pairs sharing a lane, so the hand
--                        can stay put; HIGHER IS EASIER, expect a negative weight
--   SOLO  (authored: where the chart says the hard part is)
--     solo_frac_marked   fraction of playing time inside a pitch-103 solo
--     solo_change_ratio  change rate inside the solo / outside it; 1.0 = no solo
--   TEXTURE  (small nudges rather than primary signals)
--     sustain_frac       fraction of notes at or above an 8th (0 if qn_e absent)
--     solo_frac          fraction of playing time inside a [play_solo] span.
--                        ANIMATION CUE, not the solo - on borrowed time, see below
--     force_hopo_rate    lo+5 markers/sec - removes a strum, so EASIER
--     force_strum_rate   lo+6 markers/sec - adds a strum, so harder
--     tremolo_frac       fraction of playing time under a 126 lane
--     trill_frac         fraction of playing time under a 127 lane
--   PRO KEYS  (structurally 0 elsewhere - nothing else has a moving display window)
--     gliss_frac         fraction of playing time under a 126 GLISSANDO lane. Leniency,
--                        so expect a NEGATIVE coefficient - the opposite sign to the
--                        same pitch read as tremolo on guitar
--     shift_rate         range changes per second of playing time
--     shift_span_mean    mean size of a range change, in semitones
--     repetition         KNOWN WEAK: see the note below
--   PREDICTABILITY  (bits; LOW = predictable, so expect NEGATIVE coefficients)
--     entropy_h2         conditional entropy of the next gem shape given the last two
--     entropy_h2_rel     the same over transposition-invariant MOTION, so one figure
--                        played up the lanes reads as one figure rather than three
--   INTERACTIONS  (exact products, not independent measurements)
--     notes_total      == density_avg * playing_s
--     total_changes    == change_rate * playing_s
--
--   reference / non-factor: notes, chords, density_max, sustain_measured,
--                           tight_measured, solo_measured, no_playing_time,
--                           entropy_contexts (how many distinct contexts the entropy
--                           estimate was built from - a small count means the estimate
--                           is unreliable, and that has to be visible)
--
-- EXPECT SMALL AND UNINTERPRETABLY-SIGNED COEFFICIENTS ON THE LANE FACTORS, for
-- the same reason as force_hopo/force_strum and then one more. A 126/127 lane
-- marks a fast repeated or alternating passage, so the obvious reading is "this is
-- harder". That is at best half right: the lane's job in the engine is to make
-- such a passage MORE LENIENT, accepting loose alternation instead of demanding
-- each gem exactly. So one marker both indicates a busy section and reduces what
-- it costs to pass it, and the two effects partly cancel. They are fitted so the
-- corpus can answer empirically rather than by assumption - but a large
-- coefficient either way should be read as suspicious, not as a discovery. The
-- same caution applies to the drum lanes when drums are scored.
--
-- Two things worth knowing before reading any coefficient:
--
--   * notes_total and total_changes are EXACT products of two other factors. They
--     are included because a linear model cannot form a product on its own, and the
--     corpus showed that pure rates made song length invisible (a 13-minute epic
--     scored like a 3-minute pop song at equal density). But they are interaction
--     terms, so no coefficient in the endurance/speed/interaction group means
--     anything on its own.
--   * repetition is a length proxy rather than a repetitiveness measure: it
--     correlates ~+0.6/+0.75 with note count and saturates near 1. Kept for the
--     record; needs a length-invariant form (n-gram entropy) or removal.
function ScoreChart(events, spans, opts)
    opts = opts or {}
    local window_s = opts.peak_window_s or PEAK_WINDOW_S
    local pctl     = opts.peak_pctl     or PEAK_PCTL

    local out = {
        playing_s = 0, notes = 0, notes_total = 0, events = 0,
        density_avg = 0, density_peak = 0, density_max = 0,
        attack_density_avg = 0, attack_density_peak = 0,
        change_rate = 0, total_changes = 0,
        tight_p10 = 0, tight_med = 0,
        chord_size_mean = 0, chord_span_mean = 0, chord_change_frac = 0,
        sounding_size_mean = 0, overlap_frac = 0, held_change_frac = 0,
        move_mean = 0, move_p90 = 0, anchor_frac = 0,
        repetition = 0, entropy_h2 = 0, entropy_h2_rel = 0, entropy_contexts = 0,
        complex_peak = 0,
        sustain_frac = 0, solo_frac = 0,
        solo_frac_marked = 0, solo_change_ratio = 1.0,
        tremolo_frac = 0, trill_frac = 0,
        -- PRO KEYS. gliss_frac is the 126 lane read as a LENIENCY device (scoring off
        -- under the marker), which is why it is its own column rather than tremolo_frac -
        -- same pitch, opposite meaning. The two shift columns have no counterpart on any
        -- other instrument: nothing else has a display window that moves.
        gliss_frac = 0, shift_rate = 0, shift_span_mean = 0,
        finger_reassign_mean = 0, finger_reassign_p90 = 0,
        finger_reassign_peak = 0, held_independence_peak = 0,
        vocal_parts = 0,
        -- drums (see the block at the end of ScoreChart)
        kick_density = 0, kick_density_peak = 0, hand_density_peak = 0,
        stick_size_mean = 0, tom_frac = 0, roll_frac = 0, offbeat_frac = 0,
        -- the same chart read as PRO drums, where a tom and a cymbal on one colour are
        -- two different gems rather than one
        pro_total_changes = 0, pro_change_rate = 0,
        pro_tight_p10 = 0, pro_tight_med = 0, pro_entropy_h2 = 0,
        stations_peak = 0, pro_stations_peak = 0,
        force_hopo_rate = 0, force_strum_rate = 0,
        no_playing_time = false, tight_measured = false, solo_measured = false,
    }

    -- Normalize first: everything below assumes sorted, disjoint spans.
    spans = NormalizeSpans(spans)

    local playing_s = TotalSpanSeconds(spans)
    if playing_s <= 0 then
        out.no_playing_time = true
        return out
    end
    out.playing_s = playing_s

    -- One array per playing span. Pair-based metrics iterate within a segment so
    -- no rest is ever crossed; per-event metrics use the flattened view.
    local segs    = EventsInSegments(events, spans)
    local in_span = FlattenSegments(segs)
    if #in_span == 0 then return out end

    out.notes       = NoteCount(in_span)
    out.notes_total = out.notes
    out.events      = #in_span

    -- Factor 1: notes per second. Summing across all spans and dividing by
    -- total span time IS the length-weighted mean of the per-span densities,
    -- so no separate weighting step is needed.
    out.density_avg = out.notes / playing_s

    -- Factor 2: peak, reported separately and never folded into the average.
    out.density_peak, out.density_max = PeakDensity(segs, window_s, pctl)

    -- The same two measured in ATTACKS rather than gems. density_* counts a 3-note
    -- chord as 3, so gems/sec is attacks/sec multiplied by the chord size - two
    -- different demands (how fast the hand moves, how much it holds) fused into one
    -- number that a linear fit can only weight once.
    --
    -- This is not hypothetical. `dreampolice` is the ONE chordal chart in the 159-song
    -- bass corpus (chord_size_mean 1.50 against a bass mean of 1.011, higher even than
    -- the guitar mean of 1.35), and gem-counting drove its density_peak to 19 - z=+6.3
    -- against the other bass charts - which the fit exponentiated into a predicted rank
    -- of 943 for a chart actually ranked 299. The bass coefficient was calibrated on 157
    -- single-note charts where gems/sec and attacks/sec are the same quantity.
    --
    -- The gem-based pair stays, so the losing measurement remains auditable and the two
    -- can be compared as a paired substitution rather than by assertion.
    out.attack_density_avg  = out.events / playing_s
    out.attack_density_peak = PeakDensity(segs, window_s, pctl, EventOne)

    -- Distinct gem identities in the busiest windows. Computed on every pass because the
    -- PRO pass is where it earns its keep: on the five-gem vocabulary it is saturated
    -- (mean 4.77 of 5 across the corpus, p25 and p75 both 5) and is therefore not offered
    -- as a factor. Only pro_stations_peak reaches the CSV.
    out.stations_peak = PeakStations(segs, window_s, pctl)

    -- Changes, how tightly they arrive, and how much hand load each event carries.
    --
    -- One pass over the segments, doing two different kinds of work: the per-event
    -- sums (chord size and spread) are unaffected by segment boundaries, while a
    -- change and its interval need a PREDECESSOR IN THE SAME SEGMENT. The first
    -- event of each segment therefore contributes no change and no interval - the
    -- note after a bar of rest is not a chord change the player has to execute
    -- under time pressure, and the pre-segment version counted it as one with a
    -- large interval, dragging the tightness percentiles upward on exactly the
    -- charts with the most rests.
    local changes         = 0
    local intervals       = {}
    local size_sum        = 0
    local span_sum, n_chords = 0, 0
    local chord_changes   = 0
    -- Polyphony, for 5-lane keys. Zero on guitar and bass by authoring rule.
    local sounding_sum, n_overlapped = 0, 0
    local held_only_changes = 0

    for _, seg in ipairs(segs) do
        for i = 1, #seg do
            local ev = seg[i]
            local n  = #ev.pitches
            size_sum = size_sum + n
            local n_held = HeldCount(ev)
            sounding_sum = sounding_sum + n + n_held
            if n_held > 0 then n_overlapped = n_overlapped + 1 end
            if n > 1 then
                n_chords = n_chords + 1
                -- On a PART track these pitches are lanes, so the span is the lane
                -- spread: 1 is adjacent, 4 is green-to-orange.
                span_sum = span_sum + (ev.pitches[n] - ev.pitches[1])
            end
            if i > 1 and PitchSetChanged(ev, seg[i - 1]) then
                changes = changes + 1
                intervals[#intervals + 1] = ev.qn - seg[i - 1].qn
                -- A change INTO a chord is more work than one into a single note:
                -- the whole shape has to be re-formed, not one finger moved.
                if n > 1 then chord_changes = chord_changes + 1 end
                -- The struck set changed but the set of fingers ENGAGED did not: a
                -- note re-articulated inside a shape that is still being held, which
                -- is the broken-chord idiom keys allows and guitar forbids. Counted so
                -- the change tally's overstatement is visible rather than assumed.
                if not SoundingSetChanged(ev, seg[i - 1]) then
                    held_only_changes = held_only_changes + 1
                end
            end
        end
    end

    out.change_rate   = changes / playing_s
    out.total_changes = changes

    -- A chart with no within-segment changes has no intervals, so both percentiles
    -- stay 0 - and since these are intervals where SMALLER MEANS HARDER, a 0 reads
    -- to the fit as maximally tight, the opposite of the truth. The same trap
    -- sustain_frac already guards with sustain_measured.
    --
    -- Left at 0 rather than given a sentinel (any choice of "very wide" would be
    -- arbitrary and would enter the fit as a real measurement), but recorded, so the
    -- rescore can answer empirically whether any real chart hits it. Expected count
    -- is 0: it needs every gem change in a song to fall across a rest.
    out.tight_measured = (#intervals > 0)
    if #intervals > 0 then
        table.sort(intervals)
        out.tight_p10 = Percentile(intervals, TIGHT_PCTL_LOW)
        out.tight_med = Percentile(intervals, TIGHT_PCTL_MID)
    end
    if changes > 0 then
        out.chord_change_frac = chord_changes / changes
    end

    -- Mean pitches per event: 1.0 means every event is a single note. Blends how
    -- often chords occur with how big they are, which together are the per-event
    -- hand load. Replaces an earlier bare chord_ratio (fraction of events that were
    -- chords), which on guitar acted as an inverse proxy for change_rate
    -- (rho -0.427) rather than measuring chord difficulty at all - and flipped sign
    -- on bass, which is how a confound gives itself away.
    out.chord_size_mean = size_sum / #in_span
    -- Mean lane spread over CHORD events only, so this says "when there is a chord,
    -- how wide" independently of how often chords appear.
    if n_chords > 0 then out.chord_span_mean = span_sum / n_chords end

    -- Polyphony. All three are structurally 0 wherever overlapping notes are
    -- forbidden, which is guitar and bass; they exist for 5-lane keys.
    --
    -- sounding_size_mean deliberately sits BESIDE chord_size_mean rather than
    -- replacing it: on guitar the two are identical, so redefining the old column
    -- would have been safe but would have silently changed what a tracked measurement
    -- means. Two columns make the difference legible in a run-to-run diff.
    out.sounding_size_mean = sounding_sum / #in_span
    out.overlap_frac       = n_overlapped / #in_span
    if changes > 0 then out.held_change_frac = held_only_changes / changes end

    -- Hand movement: how far, as distinct from how often (change_rate) or when
    -- (the tightness percentiles). The one dimension nothing else covered.
    out.move_mean, out.move_p90, out.anchor_frac = HandMovement(segs)

    if opts.pro_keys then
        out.finger_reassign_mean, out.finger_reassign_p90,
        out.finger_reassign_peak, out.held_independence_peak =
            ProKeysCoordination(segs, window_s, pctl)
    end

    out.repetition = RepetitionFraction(segs, REPEAT_NGRAM)

    -- Predictability, in bits. Both variants share the estimator and differ only in how
    -- an event is encoded: literally (a lane is a lane, right for guitar) or as motion
    -- (position-independent, which is what a keyboard figure repeated up the lanes
    -- actually has in common). Low bits = the part plays itself once learned.
    out.entropy_h2, out.entropy_contexts = ConditionalEntropy(segs, ENTROPY_K, ShapeKey)
    out.entropy_h2_rel                   = ConditionalEntropy(segs, ENTROPY_K, MotionKey)
    out.complex_peak                     = LocalComplexityPeak(segs, window_s, pctl)

    -- nil means "the caller did not supply note ends", which is not the same as
    -- "this chart has no sustains" - report 0 but do not pretend it was measured.
    local sus = SustainFraction(in_span)
    out.sustain_frac    = sus or 0
    out.sustain_measured = (sus ~= nil)

    if opts.solo_spans then
        -- Normalized for the same reason as `spans`: SpanOverlapSeconds documents
        -- non-overlapping input as a precondition, and overlapping solo spans would
        -- count the shared seconds twice and push solo_frac above 1.
        out.solo_frac = SpanOverlapSeconds(spans, NormalizeSpans(opts.solo_spans)) / playing_s
    end

    -- The AUTHORED solo (pitch 103), as opposed to the animation cue above.
    -- Overlapped against `spans` rather than used raw, so a solo marker extending
    -- past where the instrument stops playing cannot push the fraction over 1.
    if opts.marked_solo_spans then
        local solo = NormalizeSpans(opts.marked_solo_spans)
        out.solo_frac_marked = SpanOverlapSeconds(spans, solo) / playing_s
        out.solo_change_ratio, out.solo_measured = SoloChangeRatio(segs, solo)
    end

    -- Technique lanes. Treated like the force-HOPO markers: authoring annotations
    -- fitted with low expectations, not primary signals. See the note above.
    if opts.tremolo_spans then
        out.tremolo_frac = SpanOverlapSeconds(spans, NormalizeSpans(opts.tremolo_spans)) / playing_s
    end
    if opts.trill_spans then
        out.trill_frac = SpanOverlapSeconds(spans, NormalizeSpans(opts.trill_spans)) / playing_s
    end
    -- PRO KEYS glissando lanes, pitch 126. Same shape as the drum roll lanes and
    -- deliberately NOT tremolo_frac: the Pro Keys doc says a glissando marker "turns off
    -- the scoring system for any notes below" it, so the marked passage is EASIER than
    -- its notes look. tremolo_frac carries the opposite reading on guitar, and one column
    -- cannot mean both. 21 charts, 76 notes - sparse, fitted with low expectations.
    if opts.gliss_spans then
        out.gliss_frac = SpanOverlapSeconds(spans, NormalizeSpans(opts.gliss_spans)) / playing_s
    end

    -- PRO KEYS LANE SHIFTS. The displayed 10-key window moves, and the authoring doc is
    -- unusually direct about the cost: "Because range shifts make gameplay more
    -- difficult, we try to keep them to a minimum."
    --
    -- opts.lane_shifts is an ordered array of { s = project time, base = window base
    -- pitch }, already whitelisted to the six documented markers by the reader.
    --
    -- A SHIFT IS A CHANGE OF BASE, NOT A MARKER. Two counting traps, both measured:
    --
    --   1. Every difficulty must carry an opening range marker (123 of 123 corpus charts
    --      do), so a marker count starts at 1 for a chart that never shifts. 35 of 123
    --      charts carry ONLY that opener - 28% of the instrument would read as one-shift
    --      charts, indistinguishable from a genuine single shift.
    --   2. A marker that re-asserts the range already displayed moves nothing. 28 of 538
    --      corpus transitions (5.2%, in 10 charts) do exactly that, so `markers - 1`
    --      overcounts on those charts even after trap 1 is handled.
    --
    -- Hence: count transitions where the base actually changes, and average the size of
    -- those changes only. Both read 0 for a chart that holds one range all the way
    -- through, which is the honest value.
    if opts.lane_shifts then
        local n_shift, shift_sum = 0, 0
        for i = 2, #opts.lane_shifts do
            local d = opts.lane_shifts[i].base - opts.lane_shifts[i - 1].base
            if d ~= 0 then
                n_shift   = n_shift + 1
                shift_sum = shift_sum + (d < 0 and -d or d)
            end
        end
        out.shift_rate      = n_shift / playing_s
        out.shift_span_mean = (n_shift > 0) and (shift_sum / n_shift) or 0
    end
    -- Force-HOPO and force-strum are counted SEPARATELY because they push
    -- difficulty in opposite directions: a force-HOPO on notes the engine would not
    -- auto-HOPO removes a strum (easier), while a force-strum on close notes adds
    -- one back (harder). Summing them, as an earlier single hopo_rate did, cancels
    -- the very signal they carry.
    if opts.force_hopo_count then
        out.force_hopo_rate = opts.force_hopo_count / playing_s
    end
    if opts.force_strum_count then
        out.force_strum_rate = opts.force_strum_count / playing_s
    end

    ------------------------------------------------------------------
    -- DRUMS. Gated on opts.kick_pitch, so every other instrument's numbers are
    -- bit-identical without these branches running at all.
    --
    -- THE PROBLEM THESE SOLVE. Pitch 96 on PART DRUMS is the kick PEDAL - a foot, not
    -- a hand - and a third of every drum chart is a kick struck together with a hand:
    -- measured over 42,915 corpus events, 34.6% are kick-plus-hand, against 22.8% that
    -- are two sticks at once. chord_size_mean scores those identically at 2.0, so the
    -- backbone of nearly every beat (and the easiest combination on the kit) is counted
    -- as the same demand as both hands landing together. Same shape of flaw as counting
    -- gems instead of attacks, on a third of all events.
    if opts.kick_pitch then
        local kick = opts.kick_pitch
        local n_kick, n_hand, n_stick_events = 0, 0, 0
        for _, ev in ipairs(in_span) do
            local hands = 0
            for _, p in ipairs(ev.pitches) do
                if p == kick then n_kick = n_kick + 1 else hands = hands + 1 end
            end
            n_hand = n_hand + hands
            if hands > 0 then n_stick_events = n_stick_events + 1 end
        end

        out.kick_density = n_kick / playing_s
        -- Peak as well as average, because one double-kick passage is what hurts and an
        -- average over a five-minute song hides it. Same window and percentile as every
        -- other peak, via the weight function PeakDensity already takes.
        out.kick_density_peak = PeakDensity(segs, window_s, pctl, function(ev)
            local n = 0
            for _, p in ipairs(ev.pitches) do if p == kick then n = n + 1 end end
            return n
        end)
        out.hand_density_peak = PeakDensity(segs, window_s, pctl, function(ev)
            local n = 0
            for _, p in ipairs(ev.pitches) do if p ~= kick then n = n + 1 end end
            return n
        end)
        -- chord_size_mean with the foot removed. 1.0 means the sticks never land
        -- together, however much kick sits underneath. Averaged over events that carry
        -- at least one hand gem, so a kick-only passage does not drag it below 1.
        out.stick_size_mean = (n_stick_events > 0) and (n_hand / n_stick_events) or 0
    end

    -- TOM MARKERS (110/111/112 turning yellow/blue/green from cymbal to tom).
    --
    -- Each marker governs ONE lane, so the spans arrive keyed by the gem pitch they
    -- affect and a gem is only counted under its own lane's marker - a blue gem inside
    -- a yellow marker is still a cymbal.
    --
    -- EXPECTED TO CARRY NOTHING, and measured rather than assumed. Pro Drums has no
    -- rank of its own: every songs.dta in the corpus carries `drum` and no
    -- `real_drums`, so the label being fitted was set for the standard four-pad kit,
    -- where a tom marker is invisible. 93 of 103 charts use them, so if they do carry
    -- signal it is worth knowing whether the rank reflects Pro authoring after all or
    -- whether tom markers merely coincide with busy fills.
    if opts.tom_spans then
        local marked, total = 0, 0
        for _, ev in ipairs(in_span) do
            for _, p in ipairs(ev.pitches) do
                local lane = opts.tom_spans[p]
                if lane then
                    total = total + 1
                    if InSpans(lane, ev.s) then marked = marked + 1 end
                end
            end
        end
        out.tom_frac = (total > 0) and (marked / total) or 0
    end

    -- ROLL LANES (126 and 127) - the drum equivalent of the tremolo/trill lanes, and
    -- the same kind of factor: a leniency device that marks where a part is too fast or
    -- too loose to chart literally. Combined into one column because 127 is 9 events in
    -- the whole corpus, far too sparse to fit on its own.
    if opts.roll_spans then
        out.roll_frac = SpanOverlapSeconds(spans, NormalizeSpans(opts.roll_spans)) / playing_s
    end

    -- SYNCOPATION. Share of onsets that do not land on a quarter-note beat.
    --
    -- The quarter-note grid is the definition, not an approximation of "the beat":
    -- compound meters make the perceived beat a dotted value, and the scorer has no
    -- time-signature information, so it uses the same unit tight_p10 / tight_med
    -- already report in. The tolerance is well inside a 32nd (0.125 QN), so authored
    -- 32nds and 16ths are correctly counted as off the beat rather than rounded onto it.
    if opts.offbeat then
        local off = 0
        for _, ev in ipairs(in_span) do
            local frac = ev.qn % 1
            if frac > OFFBEAT_TOL and frac < (1 - OFFBEAT_TOL) then off = off + 1 end
        end
        out.offbeat_frac = off / #in_span
    end

    -- THE PRO DRUMS PASS. Score the same chart a second time under the eight-gem
    -- vocabulary and keep the factors the vocabulary actually changes.
    --
    -- Recursing rather than exporting a second entry point keeps the factor set in one
    -- place: ScoreChart owns every SCORE_FACTOR_KEYS value, so the "every key is actually
    -- produced" test still covers these. `pro_pass` stops it at one level.
    --
    -- Only these five differ. Densities count gems and chord sizes count limbs, neither
    -- of which the vocabulary touches; the change-based factors and the entropy encoder
    -- read gem identity, which is exactly what it redefines.
    if opts.tom_spans and not opts.pro_pass then
        local sub = {}
        for k, v in pairs(opts) do sub[k] = v end
        sub.pro_pass = true
        local pro = ScoreChart(ProRemapEvents(events, opts.tom_spans), spans, sub)
        out.pro_total_changes = pro.total_changes
        out.pro_change_rate   = pro.change_rate
        out.pro_tight_p10     = pro.tight_p10
        out.pro_tight_med     = pro.tight_med
        out.pro_entropy_h2    = pro.entropy_h2
        -- The one Pro factor measuring something the five-gem vocabulary CANNOT express.
        -- The others are refinements of numbers that already existed; this is a new axis,
        -- and the pre-check says it is the only channel where the Pro distinction is large
        -- (see PeakStations, and the round-9 section of the design doc).
        out.pro_stations_peak = pro.stations_peak
    end

    return out
end

-- Column order for the calibration CSV, and the order the analysis fits over.
-- One place so the writer and the reader cannot drift apart.
--
-- This list is the CANDIDATE POOL, not a model. It is 96 columns wide once the
-- vocal scorer has appended its own, and no fitted model carries anything like
-- that many: the selected models run from 3 columns (bass) to 26 (drums), with 7
-- on both keyboards, 12 on vocals and 21 on guitar. A wide pool is the point -
-- the protocol chooses from it and the ridge is fitted inside each fold.
--
-- CHANGING THIS LIST IS A FULL RESCORE. Every consumer keys off the CSV header,
-- which is the authoritative record of the factor set, and a CSV written under a
-- different header can be neither refit nor row-compared against the current one.
-- Add a column only with a rescore budgeted; see dev/calibration/README.md.
SCORE_FACTOR_KEYS = {
    -- endurance / speed. The attack_* pair measures the same two rates in EVENTS
    -- rather than gems; they differ only on chordal charts and are declared as a
    -- paired substitution for the gem versions, never as an addition to them.
    'playing_s', 'density_avg', 'density_peak', 'change_rate',
    'attack_density_avg', 'attack_density_peak',
    -- tightness (intervals; smaller is harder)
    'tight_p10', 'tight_med',
    -- hand load
    'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
    -- polyphony (5-lane keys only; structurally 0 on guitar and bass)
    'sounding_size_mean', 'overlap_frac', 'held_change_frac',
    -- hand movement (anchor_frac: higher is easier)
    'move_mean', 'move_p90', 'anchor_frac',
    -- authored solo (pitch 103)
    'solo_frac_marked', 'solo_change_ratio',
    -- texture nudges
    'sustain_frac', 'solo_frac', 'force_hopo_rate', 'force_strum_rate',
    'tremolo_frac', 'trill_frac',
    -- PRO KEYS: the moving display window, which no other instrument has, plus 126 read
    -- as a leniency lane rather than as tremolo. Structurally 0 everywhere else.
    'gliss_frac', 'shift_rate', 'shift_span_mean',
    'finger_reassign_mean', 'finger_reassign_p90',
    'finger_reassign_peak', 'held_independence_peak',
    -- DRUMS: the third limb split out from the two hands, plus the drum-only markers.
    -- Structurally 0 on every other instrument, the way the polyphony trio is 0
    -- anywhere overlaps are forbidden. offbeat_frac is the exception - it is
    -- instrument-agnostic and gets measured everywhere, but is declared only in drum
    -- candidates until some later round offers it to the instruments already fitted.
    'kick_density', 'kick_density_peak', 'hand_density_peak', 'stick_size_mean',
    'tom_frac', 'roll_frac', 'offbeat_frac',
    -- PRO DRUMS: the same factors over an eight-gem vocabulary, where a tom and a cymbal
    -- on one colour are two different gems. Declared as a paired SUBSTITUTION for their
    -- five-gem twins, never alongside them - the question is which vocabulary the
    -- official rank was set against, and that is answered by swapping, not by adding.
    'pro_total_changes', 'pro_change_rate', 'pro_tight_p10', 'pro_tight_med',
    'pro_entropy_h2',
    -- The only Pro factor measuring something the five-gem vocabulary cannot express at
    -- all: how many different places the hand must cover in the busiest window. Its
    -- five-gem twin is saturated (4.77 of 5) and is deliberately NOT a factor.
    'pro_stations_peak',
    'repetition',
    -- predictability in bits; LOW means the part is predictable, so expect NEGATIVE
    -- coefficients. entropy_contexts is reference-only and deliberately absent.
    'entropy_h2', 'entropy_h2_rel', 'complex_peak',
    -- interaction terms (exact products of the above)
    'notes_total', 'total_changes',
}

-- Named subsets the analysis cross-validates alongside the full set, to keep the
-- question "is the full set earning its keep" in front of every run. It repeatedly
-- has not been: on the previous factor set, two factors scored higher on bass than
-- all thirteen. Groups here follow the primary axes - endurance/speed, tightness,
-- hand load - with texture left out on purpose.
SCORE_LEAN_SETS = {
    { name = 'lean 2 (speed+volume)',  keys = { 'total_changes', 'density_peak' } },
    { name = 'lean 4 (+tight, chord)', keys = { 'total_changes', 'density_peak',
                                                'tight_p10', 'chord_size_mean' } },
    { name = 'lean 6 (+endurance)',    keys = { 'total_changes', 'density_peak',
                                                'tight_p10', 'tight_med',
                                                'chord_size_mean', 'playing_s' } },
    { name = 'no interactions',        keys = { 'playing_s', 'density_avg', 'density_peak',
                                                'change_rate', 'tight_p10', 'tight_med',
                                                'chord_size_mean', 'chord_span_mean',
                                                'chord_change_frac' } },
    -- The targeted experiment: speed and tightness plus hand movement, nothing else.
    -- If movement is the missing signal, this small set should beat the leaner ones
    -- that lack it.
    { name = 'movement + speed',       keys = { 'total_changes', 'density_peak',
                                                'tight_p10',
                                                'move_mean', 'move_p90', 'anchor_frac' } },
    -- This round's targeted experiment, same shape as the one above: does knowing
    -- how much harder the authored solo is than the rest of the chart beat the
    -- whole-chart aggregates? Deliberately excludes solo_frac_marked, because solo
    -- COVERAGE is the thing shown not to predict rank (ridersonthestorm carries the
    -- largest solo in the corpus and is rated 180).
    { name = 'solo concentration',     keys = { 'total_changes', 'density_peak',
                                                'tight_p10', 'solo_change_ratio' } },
}
