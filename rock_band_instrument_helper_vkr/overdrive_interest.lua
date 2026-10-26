-- Overdrive tab: how eventful each bar of a part is.
--
-- The doc puts overdrive on parts that are "interesting", and is explicit that
-- interesting means memorable rather than difficult. A tool cannot hear that, but it
-- can tell a bar of one power chord struck sixteen times from a bar where palm-muted
-- single notes are threaded between chords, or where the chord changes every beat.
-- The first is busy and dull; the second is what an author would reach for. So
-- DENSITY ALONE MUST NOT WIN: it carries the smallest weight below.
--
-- Scores are relative to the same song (percentile ranks), so a sparse ballad and a
-- thrash song both spread their bars over the full 0..1 range. They only ever choose
-- between nearby bars of one part, never compare songs or instruments.
--
-- WHAT THIS DOES NOT DO: reproduce the official charters' picks. Measured over 60
-- reference songs, the note-content terms barely separate official overdrive bars from
-- any other playing bar (lift 1.01-1.05 on change, entropy, variety and density), and a
-- generator using this score lands on an official bar about as often as a random pick
-- within the same spacing window. Official placement is driven by spacing, by keeping
-- drums out of fill bars, and by one structural cue: the bar just before a section
-- change (lift 1.39 on guitar) - a pickup or build-up, as the doc suggests. That is
-- why the context term favours the bar before a section over the section's own first
-- bar. The rest of the score is a tie-breaker (eventful beats beat a repeated
-- chord), not a claim about what official charts do.
--
-- Pure. Requires (globals): DIFFICULTY_PRIMITIVES (lib/reaper_difficulty_score.lua),
-- OdBarAt (overdrive_read.lua)

-- Weights. Fixed and deliberately not exposed in the UI: they decide which of two
-- neighbouring bars wins, and nobody can tune that meaningfully by feel.
local W_CHANGE  = 0.20   -- share of consecutive hits whose gem set changes
local W_VARIETY = 0.10   -- distinct gem shapes in the busiest window
local W_ENTROPY = 0.15   -- how unpredictable the motion is (the difficulty scorer's measure)
local W_DENSITY = 0.05   -- gems per counted beat
local W_NOVELTY = 0.10   -- the bar is not a literal repeat of the one before
local W_CONTEXT = 0.40   -- a section starts right after this bar (full) or at it (0.4)
local CONTEXT_OWN_START = 0.4

-- A beat or two of change is enough to make a bar stand out, so the change terms
-- are measured over short windows and the bar keeps its best one.
local WINDOW_QN = 2

-- Percentile rank of every value in `vals` (indexed by bar), ties sharing the mean
-- rank, in 0..1. Bars absent from `vals` stay absent.
local function PercentileRanks(vals)
    local list = {}
    for b, v in pairs(vals) do list[#list + 1] = { b = b, v = v } end
    table.sort(list, function(a, c) return a.v < c.v end)
    local ranks, n = {}, #list
    local i = 1
    while i <= n do
        local j = i
        while j < n and list[j + 1].v == list[i].v do j = j + 1 end
        local rk = n > 1 and ((i + j) / 2 - 1) / (n - 1) or 1
        for k = i, j do ranks[list[k].b] = rk end
        i = j + 1
    end
    return ranks
end

-- The change, variety and entropy terms for one window of events.
local function WindowTerms(win)
    local P = DIFFICULTY_PRIMITIVES
    local n = #win
    local change = 0
    if n >= 2 then
        local c = 0
        for i = 2, n do
            if P.PitchSetChanged(win[i - 1], win[i]) then c = c + 1 end
        end
        change = c / (n - 1)
    end
    local shapes, variety = {}, 0
    for _, ev in ipairs(win) do
        local k = P.ShapeKey(ev)
        if not shapes[k] then shapes[k] = true; variety = variety + 1 end
    end
    -- Fewer than four events have no reliable transition context; the difficulty
    -- scorer's LocalComplexityPeak draws the same line.
    local entropy = n >= 4 and P.ConditionalEntropy({ win }, 1, P.MotionKey) or 0
    return change, variety, entropy
end

-- A bar's content as a string, position-relative, so two identical bars compare equal.
local function BarSignature(evs, qn_s)
    local parts = {}
    for _, ev in ipairs(evs) do
        parts[#parts + 1] = ('%.3f:%s'):format(ev.qn - qn_s, table.concat(ev.pitches, '.'))
    end
    return table.concat(parts, '|')
end

-- Interest score per bar, 0..1, for a sorted gem event list (ReadGemEvents shape:
-- { qn, qn_e, pitches }). Bars with no onset get no score (nil): the instrument is
-- not playing there and no phrase can go on it.
--
-- section_bars: set of bar indexes where a section starts (OdFinishModel builds it).
-- Returns scores (by bar), plus the raw terms for tests and debugging.
function OdBarInterest(bars, events, section_bars)
    local by_bar = {}
    for _, ev in ipairs(events) do
        local b = OdBarAt(bars, ev.qn)
        if b then
            by_bar[b] = by_bar[b] or {}
            by_bar[b][#by_bar[b] + 1] = ev
        end
    end

    local change, variety, entropy, density, novelty, context = {}, {}, {}, {}, {}, {}
    local prev_sig
    for b, bar in ipairs(bars) do
        local evs = by_bar[b]
        local sig = evs and BarSignature(evs, bar.qn_s) or ''
        if evs then
            local best_c, best_v, best_h = 0, 0, 0
            local start = bar.qn_s
            while start < bar.qn_e - 1e-6 do
                local stop = math.min(start + WINDOW_QN, bar.qn_e)
                local win = {}
                for _, ev in ipairs(evs) do
                    if ev.qn >= start - 1e-6 and ev.qn < stop - 1e-6 then win[#win + 1] = ev end
                end
                local c, v, h = WindowTerms(win)
                if c > best_c then best_c = c end
                if v > best_v then best_v = v end
                if h > best_h then best_h = h end
                start = start + 1
            end
            local gems = 0
            for _, ev in ipairs(evs) do gems = gems + #ev.pitches end
            change[b], variety[b], entropy[b] = best_c, best_v, best_h
            density[b] = gems / math.max(bar.beats or 4, 1)
            novelty[b] = (sig ~= prev_sig) and 1 or 0
            local sb = section_bars or {}
            context[b] = (sb[b + 1] and 1) or (sb[b] and CONTEXT_OWN_START) or 0
        end
        prev_sig = sig
    end

    local rc, rv, rh, rd = PercentileRanks(change), PercentileRanks(variety),
                           PercentileRanks(entropy), PercentileRanks(density)
    local scores = {}
    for b in pairs(change) do
        scores[b] = W_CHANGE * rc[b] + W_VARIETY * rv[b] + W_ENTROPY * rh[b]
                  + W_DENSITY * rd[b] + W_NOVELTY * novelty[b] + W_CONTEXT * context[b]
    end
    return scores, { change = change, variety = variety, entropy = entropy,
                     density = density, novelty = novelty, context = context }
end

----------------------------------------------------------------------
-- Band togetherness: does the band play one figure together in this bar?
----------------------------------------------------------------------
-- The doc's advice for unisons is "measures where the whole band plays an interesting
-- part together: a lead line, a breakdown, a pickup, a build-up". Three measures of
-- "together", over the gem onsets two or more parts share (1/48-quarter grid):
--   rhythm   shared onsets of guitar and bass, as a share of their combined onsets
--   contour  on those shared onsets, how often guitar's lowest gem and the bass move
--            the same way (up / down / same) - GR RY YB BO against G R Y B agrees
--            completely, though no lane matches. Needs 3+ shared onsets
--   band     onsets shared by guitar, bass AND drums, of the three parts' combined
--            onsets - the slow part where everyone hits the downbeat and the next beat
--
-- Measured over 60 reference songs, each is higher on official unison bars than on
-- other bars (percentile lift 1.10-1.15) and NOT on bars carrying a guitar-only
-- phrase (1.00). So this scores unison candidates only, never single phrases.
--
-- Returns a 0..1 score per bar (mean of the three percentile ranks present) for bars
-- where guitar and bass both play; nil elsewhere. Keys and other parts are not read.
local function OnsetMap(bars, events)
    local out = {}
    for _, ev in ipairs(events or {}) do
        local b = OdBarAt(bars, ev.qn)
        if b then
            out[b] = out[b] or {}
            out[b][math.floor(ev.qn * 48 + 0.5)] = ev.pitches[1]
        end
    end
    return out
end

local function Sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end

function OdBandTogetherness(bars, gtr_events, bass_events, drum_events)
    local g, bs, d = OnsetMap(bars, gtr_events), OnsetMap(bars, bass_events), OnsetMap(bars, drum_events)
    local rhythm, contour, band = {}, {}, {}
    for b, gb in pairs(g) do
        local bb = bs[b]
        if bb then
            local union, shared, keys = 0, 0, {}
            local all = {}
            for t in pairs(gb) do all[t] = true end
            for t in pairs(bb) do all[t] = true end
            for t in pairs(all) do
                union = union + 1
                if gb[t] and bb[t] then shared = shared + 1; keys[#keys + 1] = t end
            end
            rhythm[b] = shared / union
            table.sort(keys)
            if #keys >= 3 then
                local agree = 0
                for i = 2, #keys do
                    if Sign(gb[keys[i]] - gb[keys[i - 1]]) == Sign(bb[keys[i]] - bb[keys[i - 1]]) then
                        agree = agree + 1
                    end
                end
                contour[b] = agree / (#keys - 1)
            end
            local db = d[b]
            if db then
                local u3, s3 = 0, 0
                for t in pairs(db) do all[t] = true end
                for t in pairs(all) do
                    u3 = u3 + 1
                    if gb[t] and bb[t] and db[t] then s3 = s3 + 1 end
                end
                band[b] = s3 / u3
            end
        end
    end
    local rr, rc, rb = PercentileRanks(rhythm), PercentileRanks(contour), PercentileRanks(band)
    local out = {}
    for b in pairs(rhythm) do
        local sum, n = rr[b], 1
        if rc[b] then sum, n = sum + rc[b], n + 1 end
        if rb[b] then sum, n = sum + rb[b], n + 1 end
        out[b] = sum / n
    end
    return out
end
