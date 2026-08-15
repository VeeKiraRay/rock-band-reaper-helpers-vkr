-- Vocal difficulty scoring - the factor set for PART VOCALS.
--
-- SEPARATE FROM difficulty_score.lua ON PURPOSE. The gem scorer measures a hand moving
-- across lanes; this measures a voice moving through pitch classes, and the two share no
-- factor definitions at all. It does share four small span/percentile helpers, which is
-- why they are globals over there rather than duplicated here:
--   NormalizeSpans, TotalSpanSeconds, EventsInSegments, Percentile, SpanOverlapSeconds
-- Load difficulty_score.lua first.
--
-- Pure: no `r`, no `ctx`, no `S`. Everything arrives as plain tables, so the tests drive
-- it directly with no REAPER project.
--
-- THE ONE RULE THAT SHAPES EVERY PITCH FACTOR: Rock Band scores pitch CLASS, not pitch.
-- A C sung in any octave scores against a notated C, so a 12-semitone leap is not a hard
-- interval - it is the same note name, and the singer need not move at all. Every
-- interval here is therefore a minimal circular distance mod 12, in [0, 6]. The raw
-- semitone twins exist only so the protocol can test that claim as a paired substitution
-- rather than take this comment's word for it.

VOCAL_PEAK_WINDOW_S = 10.0
VOCAL_PEAK_PCTL     = 0.95

-- A note tube at or below this many quarter notes is "short". The corpus median is
-- 0.312 QN and p10 is 0.125, so this sits between them and splits the distribution
-- rather than tagging a rare tail.
VOCAL_SHORT_QN = 0.25

-- BREATH THRESHOLDS, in seconds. Wall-clock, not grid: a four-beat note at 60 bpm and at
-- 180 bpm are not the same demand on a singer's lungs.
--
-- 1.0 s is the author's model - a note costs nothing to hold until about a second, and
-- accrues from there. The corpus mean longest note is 2.31 s, so this sits well below
-- the tail it is meant to weight rather than tagging only freak values.
BREATH_FREE_S = 1.0

-- "A long note" for the share-of-time measure. Deliberately a different question from
-- BREATH_FREE_S: that one asks how much excess is accumulated across the whole part,
-- this asks what fraction of the singing is spent inside sustained notes at all.
LONG_NOTE_S = 2.0

-- ROUND 14 PRE-REGISTRATION CONSTANTS. These are musical definitions, not thresholds
-- selected from the corpus: MIDI 70 is the stronger of the two already-declared high
-- register landmarks; two seconds is the already-declared sustained-note threshold;
-- and a two-second phrase gap is long enough that the next pitch must be reacquired.
VOCAL_HIGH_PITCH       = 70
VOCAL_HIGH_LONG_S      = 2.0
VOCAL_REENTRY_REST_S   = 2.0

----------------------------------------------------------------------
-- Lyric classification
----------------------------------------------------------------------

-- The suffix vocabulary, from the vocal authoring doc:
--   '+'  the WHOLE lyric - this note continues the previous syllable. Slides, bends,
--        trills, and any syllable sung across several notes.
--   '#'  non-pitched (talkie), standard scoring.
--   '^'  non-pitched, MORE GENEROUS scoring. 203 events in the whole corpus.
--   '-'  joins to the next syllable (multi-syllable word).
--   '='  joins and displays a hyphen.
--
-- ORDER MATTERS AND IS EASY TO GET BACKWARDS: the doc places the hyphen BEFORE the
-- talkie marker - `cow-#`, `ard-^` - so the talkie marker is the LAST character, not the
-- first suffix. Testing for a leading '#' or scanning for '-' first misclassifies every
-- hyphenated talkie, of which the corpus has thousands.
function VocalClassifyLyric(text)
    if not text then return 'syllable' end
    local s = text:gsub('%s+$', '')
    if s == '+' then return 'plus' end
    local last = s:sub(-1)
    if last == '^' then return 'caret' end
    if last == '#' then return 'hash' end
    return 'syllable'
end

-- Minimal circular distance between two pitch classes, in [0, 6].
-- An octave apart is 0. A semitone is 1. A tritone is 6, the furthest any two notes
-- can be from each other in this space.
function VocalPitchClassDistance(a, b)
    local d = (a - b) % 12
    if d > 6 then d = 12 - d end
    return d
end

-- A note whose pitch the GAME ACTUALLY SCORES. A '#' or '^' lyric marks a non-pitched
-- syllable: the game ignores what pitch is written, so including it in an interval, a
-- range or an entropy stream measures a demand that does not exist.
--
-- This is not a small correction on the charts where it applies. `nookie2` is 82.5%
-- talkies and reads pc_range 12 - every pitch class - against a true pitched range of 7,
-- which is why it was the worst OVER-predicted song in the corpus. `killinginthename` is
-- entirely shouted: 0 of its 628 notes carry a pitch that matters, and the scorer was
-- computing a full pitch profile for it.
function VocalNoteIsPitched(n)
    return n.cls ~= 'hash' and n.cls ~= 'caret'
end

----------------------------------------------------------------------
-- Phrase spans
----------------------------------------------------------------------

-- Sorted, disjoint, and NEVER MERGED. The vocal counterpart to NormalizeSpans.
--
-- WHY IT CANNOT BE NormalizeSpans. That merges TOUCHING spans, which is right for the
-- gem instruments: an idle event at the instant the next playing event starts is not a
-- rest, and splitting there would lose the pair across the join. For phrases it is
-- exactly backwards - the boundary IS the meaning, because the game scores each phrase
-- separately and then starts again.
--
-- Overlaps are CLIPPED, not merged: a span starting before its predecessor ends has its
-- start moved to that end. The union is therefore unchanged, so playing_s and every
-- density factor read the same as before - only the segmentation moves.
--
-- Lives here rather than in corpus.lua so it stays pure and testable; corpus.lua calls
-- it from ReadPhraseSpans and is loaded after this file.
function NormalizeVocalPhrases(spans)
    local out = {}
    for _, sp in ipairs(spans or {}) do
        if sp.e > sp.s then out[#out + 1] = { s = sp.s, e = sp.e } end
    end
    table.sort(out, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.e < b.e
    end)

    local kept = {}
    for _, sp in ipairs(out) do
        local last = kept[#kept]
        if last and sp.s < last.e then sp.s = last.e end
        -- A span wholly inside its predecessor is left with nothing and dropped: it
        -- contributed no covered time of its own.
        if sp.e > sp.s then kept[#kept + 1] = sp end
    end
    return kept
end

----------------------------------------------------------------------
-- Playing time
----------------------------------------------------------------------

-- Percussion ranges are removed from playing time ONLY where they contain no sung note.
--
-- The two cases are genuinely different and a blanket rule gets one of them wrong: a
-- range holding nothing but percussion has no pitch to hit and is idle in every sense,
-- while a vocalist singing AND hitting a tambourine is doing real singing work that must
-- still count. Measured: only ~54% of percussion ranges begin from an idle state, so 43%
-- of them would be discarding real singing.
function VocalSubtractPercussion(spans, perc_spans, notes)
    if not perc_spans or #perc_spans == 0 then return spans end

    local drop = {}
    for _, ps in ipairs(perc_spans) do
        local has_note = false
        for _, n in ipairs(notes) do
            if n.s >= ps.s and n.s <= ps.e then has_note = true; break end
        end
        if not has_note then drop[#drop + 1] = ps end
    end
    if #drop == 0 then return spans end

    -- Subtract each empty percussion range from the span set.
    local out = {}
    for _, sp in ipairs(spans) do
        local pieces = { { s = sp.s, e = sp.e } }
        for _, d in ipairs(drop) do
            local next_pieces = {}
            for _, p in ipairs(pieces) do
                if d.e <= p.s or d.s >= p.e then
                    next_pieces[#next_pieces + 1] = p
                else
                    if d.s > p.s then next_pieces[#next_pieces + 1] = { s = p.s, e = d.s } end
                    if d.e < p.e then next_pieces[#next_pieces + 1] = { s = d.e, e = p.e } end
                end
            end
            pieces = next_pieces
        end
        for _, p in ipairs(pieces) do
            if p.e > p.s then out[#out + 1] = p end
        end
    end
    return NormalizeSpans(out)
end

----------------------------------------------------------------------
-- Windowed peak
----------------------------------------------------------------------

-- 95th-percentile count per second over a sliding window, counted only inside one
-- segment so a window can never gather notes from two sides of a rest while charging
-- itself the rest as time. weight_fn returns what each note contributes: 1 for tubes,
-- 0 for a continuation when counting syllables.
local function VocalPeak(segs, window_s, pctl, weight_fn)
    local rates = {}
    for _, seg in ipairs(segs) do
        for i = 1, #seg do
            local t0, sum = seg[i].s, 0
            for j = i, #seg do
                if seg[j].s - t0 > window_s then break end
                sum = sum + weight_fn(seg[j])
            end
            rates[#rates + 1] = sum / window_s
        end
    end
    if #rates == 0 then return 0 end
    table.sort(rates)
    return Percentile(rates, pctl)
end

----------------------------------------------------------------------
-- Entropy over pitch-class motion
----------------------------------------------------------------------

-- Conditional entropy of the next MOTION given the last two, where a motion is the
-- signed pitch-class step. Transposition-invariant by construction: the same melodic
-- shape in a different key produces the same symbol stream, which is what makes a
-- repetitive part read as predictable rather than as merely low-range.
local function VocalEntropy(segs, k)
    local counts, ctx_counts, n_ctx = {}, {}, 0
    for _, seg in ipairs(segs) do
        local motions = {}
        for i = 2, #seg do
            motions[#motions + 1] = (seg[i].pitch - seg[i - 1].pitch) % 12
        end
        for i = k + 1, #motions do
            local ctx = {}
            for j = i - k, i - 1 do ctx[#ctx + 1] = motions[j] end
            local key = table.concat(ctx, ',')
            counts[key] = counts[key] or {}
            counts[key][motions[i]] = (counts[key][motions[i]] or 0) + 1
            ctx_counts[key] = (ctx_counts[key] or 0) + 1
            n_ctx = n_ctx + 1
        end
    end
    if n_ctx == 0 then return 0, 0 end

    local h, n_distinct = 0, 0
    for key, nexts in pairs(counts) do
        n_distinct = n_distinct + 1
        local total = ctx_counts[key]
        local hk = 0
        for _, c in pairs(nexts) do
            local p = c / total
            hk = hk - p * math.log(p, 2)
        end
        h = h + (total / n_ctx) * hk
    end
    return h, n_distinct
end

----------------------------------------------------------------------
-- The scorer
----------------------------------------------------------------------

-- notes: array of { s, e, qn, qn_e, pitch, lyric }, sorted by s.
-- spans: phrase spans (pitch 105/106). Empty is handled by the caller's fallback.
-- opts:
--   perc_spans     percussion ranges, subtracted where they hold no note
--   peak_window_s, peak_pctl
--   short_qn       override for VOCAL_SHORT_QN
--
-- Returns a flat table of factors. Groups, and what each is for:
--
--   VOLUME      playing_s, syllables_total, tubes_total
--   SPEED       syl_density_avg/peak, tube_density_avg/peak, pc_change_rate
--               The syl/tube pair is a SUBSTITUTION, never fitted together - see below.
--   TIMING      tight_p10, tight_med - onset gaps in QN, smaller is harder
--   PHRASE      phrase_syl_mean/peak, phrase_len_mean. Phrases are the unit the game
--               actually scores, so a phrase packed with syllables is the real load.
--   PITCH       pc_interval_mean/p90, pc_range   (mod 12 - the honest measure)
--               semi_interval_mean/p90, notated_range   (raw - the twin, and reported)
--   LYRIC       talkie_frac, caret_frac, plus_frac
--   LENGTH      short_frac, short_moving_frac
--   PREDICT     entropy_h2_rel
function ScoreVocalChart(notes, spans, opts)
    opts = opts or {}
    local window_s = opts.peak_window_s or VOCAL_PEAK_WINDOW_S
    local pctl     = opts.peak_pctl     or VOCAL_PEAK_PCTL
    local short_qn = opts.short_qn      or VOCAL_SHORT_QN

    local out = {
        playing_s = 0, syllables_total = 0, tubes_total = 0,
        syl_density_avg = 0, syl_density_peak = 0,
        tube_density_avg = 0, tube_density_peak = 0,
        pc_change_rate = 0,
        tight_p10 = 0, tight_med = 0,
        phrase_syl_mean = 0, phrase_syl_peak = 0, phrase_len_mean = 0,
        pc_interval_mean = 0, pc_interval_p90 = 0, pc_range = 0,
        semi_interval_mean = 0, semi_interval_p90 = 0,
        -- The @pitched substitution family: the same measurements over notes whose pitch
        -- the game actually scores. Never fitted alongside their twins above.
        pc_interval_mean_p = 0, pc_interval_p90_p = 0, pc_range_p = 0,
        pc_change_rate_p = 0, entropy_h2_rel_p = 0,
        semi_interval_mean_p = 0, semi_interval_p90_p = 0,
        pitched_frac = 0,
        -- RANGE AND REGISTER, all on pitched notes. Round 11 computed notated_range and
        -- refused to fit it, on the rule that difficulty follows what the game REQUIRES.
        -- Round 11's prediction 1 then came out a wash - raw semitone distance predicted
        -- the label as well as pitch class - which suggests the physical effort of
        -- PRODUCING a leap counts even though the scorer discards it. These test that.
        notated_range = 0, pitch_mean = 0, pitch_p90 = 0, octave_jump_rate = 0,
        -- BREATH LOAD. Note length is U-SHAPED against difficulty: a short tube is hard
        -- because there is no time to find the pitch, and a very long one is hard because
        -- it has to be held. Round 12 measured note length monotonically and got nothing
        -- (long_frac -0.013, note_len_mean -0.035) because the two arms cancel under a
        -- rank correlation. These look only at the long tail and recover +0.21 to +0.28.
        longest_note_s = 0, breath_load = 0, longtime_frac = 0,
        -- TESSITURA. Where the part SITS, as distinct from how wide it ranges.
        -- `flightoficarus` is the case: notated_range z -0.62 (narrow) yet 46.7% of its
        -- sung time above G4 against a 19% corpus mean, and an 11-second held note.
        top_note = 0, high_time_67 = 0, high_time_70 = 0,
        -- INTERACTIONS. The additive fit cannot manufacture "high AND held" from the
        -- two marginal columns, so these explicitly measure that joint demand. The
        -- robust top is the duration-weighted 98th percentile rather than one onset.
        high_hold_time_70 = 0, high_longest_note_70 = 0,
        high_reentry_rate_70 = 0, pitch_p98_time = 0,
        -- PHRASE TAIL. Whole-song means erase a small number of decisive phrases.
        phrase_density_p90 = 0, phrase_complex_p90 = 0,
        -- Label context, supplied from songs.dta. It does not claim that the lead chart
        -- became harder; it tests whether Harmonix's one vocal rank includes harmonies.
        vocal_parts = opts.vocal_parts or 1,
        talkie_frac = 0, caret_frac = 0, plus_frac = 0,
        short_frac = 0, short_moving_frac = 0,
        entropy_h2_rel = 0, entropy_contexts = 0,
        no_playing_time = false,
    }

    -- Phrases, not gem spans: adjacent phrases must stay separate segments.
    spans = NormalizeVocalPhrases(spans or {})
    spans = VocalSubtractPercussion(spans, opts.perc_spans, notes)

    local playing_s = TotalSpanSeconds(spans)
    if playing_s <= 0 then
        out.no_playing_time = true
        return out
    end
    out.playing_s = playing_s

    local segs = EventsInSegments(notes, spans)
    local in_span = {}
    for _, seg in ipairs(segs) do
        for _, n in ipairs(seg) do in_span[#in_span + 1] = n end
    end
    if #in_span == 0 then return out end

    ------------------------------------------------------------------
    -- Lyric classes, and the syllable/tube split
    ------------------------------------------------------------------
    -- A '+' note is not a separate thing to hit: it is joined to its predecessor by a
    -- diagonal tube, making one long note whose pitch slides. So a syllable sung across
    -- three notes is ONE syllable and THREE tubes, and the two counts genuinely measure
    -- different demands. Which one the official rank was set against is an open question,
    -- answered by the protocol as a substitution - exactly as attacks-vs-gems was.
    local n_plus, n_hash, n_caret = 0, 0, 0
    for _, n in ipairs(in_span) do
        local cls = VocalClassifyLyric(n.lyric)
        n.cls = cls
        if cls == 'plus' then n_plus = n_plus + 1
        elseif cls == 'hash' then n_hash = n_hash + 1
        elseif cls == 'caret' then n_caret = n_caret + 1 end
    end

    out.tubes_total     = #in_span
    out.syllables_total = #in_span - n_plus
    out.talkie_frac     = (n_hash + n_caret) / #in_span
    out.caret_frac      = n_caret / #in_span
    out.plus_frac       = n_plus / #in_span

    out.tube_density_avg = out.tubes_total / playing_s
    out.syl_density_avg  = out.syllables_total / playing_s

    local function OneTube() return 1 end
    local function OneSyllable(n) return (n.cls == 'plus') and 0 or 1 end
    out.tube_density_peak = VocalPeak(segs, window_s, pctl, OneTube)
    out.syl_density_peak  = VocalPeak(segs, window_s, pctl, OneSyllable)

    ------------------------------------------------------------------
    -- Intervals, timing and length
    ------------------------------------------------------------------
    -- Every pair needs a PREDECESSOR IN THE SAME SEGMENT: the first note after a phrase
    -- break is not an interval the singer has to execute under time pressure, and
    -- counting it as one would charge every song for its own phrase structure.
    local pc_iv, semi_iv, gaps = {}, {}, {}
    local pc_changes = 0
    local n_short, n_short_moving = 0, 0
    local lo_pitch, hi_pitch = math.huge, -math.huge
    local classes = {}

    for _, seg in ipairs(segs) do
        for i = 1, #seg do
            local n = seg[i]
            if n.pitch < lo_pitch then lo_pitch = n.pitch end
            if n.pitch > hi_pitch then hi_pitch = n.pitch end
            classes[n.pitch % 12] = true

            local len_qn = (n.qn_e and n.qn) and (n.qn_e - n.qn) or 0
            local is_short = len_qn > 0 and len_qn <= short_qn

            if is_short then n_short = n_short + 1 end

            if i > 1 then
                local prev = seg[i - 1]
                local d_pc = VocalPitchClassDistance(n.pitch, prev.pitch)
                pc_iv[#pc_iv + 1]     = d_pc
                semi_iv[#semi_iv + 1] = math.abs(n.pitch - prev.pitch)
                if d_pc > 0 then pc_changes = pc_changes + 1 end
                gaps[#gaps + 1] = (n.qn and prev.qn) and (n.qn - prev.qn) or 0
                -- THE JOINT FACTOR. A short tube is hard to hit only when the pitch
                -- moves: there is no time to find the new note before the window
                -- closes. A short tube holding the previous pitch is among the easiest
                -- things in the game, and a separate short_frac cannot tell them apart.
                if is_short and d_pc > 0 then n_short_moving = n_short_moving + 1 end
            end
        end
    end

    out.short_frac        = n_short / #in_span
    out.short_moving_frac = n_short_moving / #in_span
    out.pc_change_rate    = pc_changes / playing_s

    if #pc_iv > 0 then
        local sum = 0
        for _, v in ipairs(pc_iv) do sum = sum + v end
        out.pc_interval_mean = sum / #pc_iv
        table.sort(pc_iv)
        out.pc_interval_p90 = Percentile(pc_iv, 0.90)

        sum = 0
        for _, v in ipairs(semi_iv) do sum = sum + v end
        out.semi_interval_mean = sum / #semi_iv
        table.sort(semi_iv)
        out.semi_interval_p90 = Percentile(semi_iv, 0.90)
    end

    ------------------------------------------------------------------
    -- The @pitched twins, and range / register
    ------------------------------------------------------------------
    -- The same measurements over only the notes whose pitch the game scores. Segment
    -- structure is preserved through the filter, so an interval still never crosses a
    -- phrase boundary - dropping the talkies must not silently join two phrases.
    local psegs = {}
    local n_pitched = 0
    for _, seg in ipairs(segs) do
        local keep = {}
        for _, n in ipairs(seg) do
            if VocalNoteIsPitched(n) then keep[#keep + 1] = n end
        end
        if #keep > 0 then
            psegs[#psegs + 1] = keep
            n_pitched = n_pitched + #keep
        end
    end
    out.pitched_frac = n_pitched / #in_span

    -- Zero pitched notes is a real corpus case, not a defensive branch:
    -- `killinginthename` is shouted end to end, 0 of 628. Every column below stays 0,
    -- which is the honest reading - that chart asks for no pitch at all - and
    -- pitched_frac is what keeps a structural zero distinguishable from a measured one.
    if n_pitched > 0 then
        local pc_iv_p, semi_iv_p = {}, {}
        local pc_changes_p, n_octave = 0, 0
        local classes_p = {}
        local lo_p, hi_p = math.huge, -math.huge
        local pitch_sum, pitch_list = 0, {}

        for _, seg in ipairs(psegs) do
            for i = 1, #seg do
                local n = seg[i]
                if n.pitch < lo_p then lo_p = n.pitch end
                if n.pitch > hi_p then hi_p = n.pitch end
                classes_p[n.pitch % 12] = true
                pitch_sum = pitch_sum + n.pitch
                pitch_list[#pitch_list + 1] = n.pitch
                if i > 1 then
                    local prev   = seg[i - 1]
                    local d_pc   = VocalPitchClassDistance(n.pitch, prev.pitch)
                    local d_semi = math.abs(n.pitch - prev.pitch)
                    pc_iv_p[#pc_iv_p + 1]     = d_pc
                    semi_iv_p[#semi_iv_p + 1] = d_semi
                    if d_pc > 0 then pc_changes_p = pc_changes_p + 1 end
                    -- An octave or more: exactly the move pitch-class scoring throws
                    -- away and a singer must still physically produce. The sharpest
                    -- test of whether vocal EFFORT explains what the game's own
                    -- scoring rule cannot.
                    if d_semi >= 12 then n_octave = n_octave + 1 end
                end
            end
        end

        out.pc_change_rate_p  = pc_changes_p / playing_s
        out.octave_jump_rate  = n_octave / playing_s
        out.notated_range     = hi_p - lo_p
        out.pitch_mean        = pitch_sum / n_pitched
        table.sort(pitch_list)
        out.pitch_p90         = Percentile(pitch_list, 0.90)
        out.top_note          = hi_p

        ------------------------------------------------------------------
        -- Breath load and tessitura
        ------------------------------------------------------------------
        -- Both are measured in SECONDS, not quarter notes. Breath is wall-clock: a
        -- four-beat note at 60 bpm and at 180 bpm are not the same demand on the singer,
        -- and a grid-relative reading would call them equal.
        local longest, excess, long_time, sung_time = 0, 0, 0, 0
        local t67, t70, high_hold, high_longest = 0, 0, 0, 0
        local pitch_time = {}
        for _, seg in ipairs(psegs) do
            for _, n in ipairs(seg) do
                local d = n.e - n.s
                if d > 0 then
                    sung_time = sung_time + d
                    if d > longest then longest = d end
                    -- The author's model: a note costs nothing until a second, then
                    -- accrues with every extra second held.
                    if d > BREATH_FREE_S then excess = excess + (d - BREATH_FREE_S) end
                    if d >= LONG_NOTE_S then long_time = long_time + d end
                    -- Time-weighted, not note-counted: holding one long high note is the
                    -- demand, and counting onsets would score it the same as one short
                    -- high note in passing.
                    if n.pitch >= 67 then t67 = t67 + d end
                    if n.pitch >= 70 then t70 = t70 + d end
                    if n.pitch >= VOCAL_HIGH_PITCH and d >= VOCAL_HIGH_LONG_S then
                        high_hold = high_hold + d
                        if d > high_longest then high_longest = d end
                    end
                    pitch_time[#pitch_time + 1] = { pitch = n.pitch, seconds = d }
                end
            end
        end
        out.longest_note_s = longest
        out.breath_load    = excess / playing_s
        if sung_time > 0 then
            out.longtime_frac = long_time / sung_time
            -- TWO THRESHOLDS, DECLARED AS A SUBSTITUTION rather than one chosen. 67 is
            -- G4, the male passaggio and a musical landmark; 70 measured stronger
            -- standalone (+0.532 against +0.405). Picking 70 on that basis would be
            -- exactly the threshold-fishing the protocol exists to prevent, so both are
            -- computed and the corpus decides between them as a paired swap.
            out.high_time_67 = t67 / sung_time
            out.high_time_70 = t70 / sung_time
            out.high_hold_time_70 = high_hold / sung_time
            out.high_longest_note_70 = high_longest

            -- Duration-weighted upper quantile. One very short exceptional onset cannot
            -- set it; a register must occupy at least two percent of sung time.
            table.sort(pitch_time, function(a, b) return a.pitch < b.pitch end)
            local target, acc = sung_time * 0.98, 0
            for _, pt in ipairs(pitch_time) do
                acc = acc + pt.seconds
                if acc >= target then out.pitch_p98_time = pt.pitch; break end
            end
        end

        -- Cold high entries: first pitched note of a phrase after at least two seconds
        -- away from the preceding phrase. Phrase starts are deliberately excluded from
        -- interval measures, but reacquiring a high pitch after rest is its own demand.
        local reentries = 0
        for i = 2, #psegs do
            local prev, cur = psegs[i - 1], psegs[i]
            if #prev > 0 and #cur > 0 then
                local rest = cur[1].s - prev[#prev].e
                if rest >= VOCAL_REENTRY_REST_S and cur[1].pitch >= VOCAL_HIGH_PITCH then
                    reentries = reentries + 1
                end
            end
        end
        out.high_reentry_rate_70 = reentries / playing_s

        local nc = 0
        for _ in pairs(classes_p) do nc = nc + 1 end
        out.pc_range_p = nc

        if #pc_iv_p > 0 then
            local sum = 0
            for _, v in ipairs(pc_iv_p) do sum = sum + v end
            out.pc_interval_mean_p = sum / #pc_iv_p
            table.sort(pc_iv_p)
            out.pc_interval_p90_p = Percentile(pc_iv_p, 0.90)

            sum = 0
            for _, v in ipairs(semi_iv_p) do sum = sum + v end
            out.semi_interval_mean_p = sum / #semi_iv_p
            table.sort(semi_iv_p)
            out.semi_interval_p90_p = Percentile(semi_iv_p, 0.90)
        end

        out.entropy_h2_rel_p = VocalEntropy(psegs, 2)
    end

    if #gaps > 0 then
        table.sort(gaps)
        out.tight_p10 = Percentile(gaps, 0.10)
        out.tight_med = Percentile(gaps, 0.50)
    end

    -- pc_range over ALL notes, kept as the twin of pc_range_p so the substitution stays
    -- auditable. `nookie2` is the case that shows why they differ: 12 here against 7 on
    -- its pitched notes, because its talkie pitches are scattered across the octave and
    -- the game reads none of them.
    --
    -- notated_range moved into the pitched block above and is now a FITTABLE factor,
    -- reversing round 11's decision. The reasoning is recorded there.
    local n_classes = 0
    for _ in pairs(classes) do n_classes = n_classes + 1 end
    out.pc_range = n_classes

    ------------------------------------------------------------------
    -- Phrase load - the unit the game actually scores
    ------------------------------------------------------------------
    local per_phrase, phrase_density, phrase_complex, len_sum = {}, {}, {}, 0
    for _, sp in ipairs(spans) do
        local c = 0
        local phrase_notes = {}
        for _, n in ipairs(in_span) do
            if n.s >= sp.s and n.s <= sp.e then
                phrase_notes[#phrase_notes + 1] = n
                if n.cls ~= 'plus' then c = c + 1 end
            end
        end
        if c > 0 then
            per_phrase[#per_phrase + 1] = c
            local duration = sp.e - sp.s
            len_sum = len_sum + duration
            local density = (duration > 0) and (c / duration) or 0
            phrase_density[#phrase_density + 1] = density
            local move_sum, move_n = 0, 0
            for i = 2, #phrase_notes do
                if VocalNoteIsPitched(phrase_notes[i - 1]) and VocalNoteIsPitched(phrase_notes[i]) then
                    move_sum = move_sum + VocalPitchClassDistance(
                        phrase_notes[i].pitch, phrase_notes[i - 1].pitch)
                    move_n = move_n + 1
                end
            end
            local mean_move = (move_n > 0) and (move_sum / move_n) or 0
            phrase_complex[#phrase_complex + 1] = density * mean_move
        end
    end
    if #per_phrase > 0 then
        local sum = 0
        for _, c in ipairs(per_phrase) do sum = sum + c end
        out.phrase_syl_mean = sum / #per_phrase
        table.sort(per_phrase)
        out.phrase_syl_peak = Percentile(per_phrase, 0.95)
        out.phrase_len_mean = len_sum / #per_phrase
        table.sort(phrase_density)
        table.sort(phrase_complex)
        out.phrase_density_p90 = Percentile(phrase_density, 0.90)
        out.phrase_complex_p90 = Percentile(phrase_complex, 0.90)
    end

    out.entropy_h2_rel, out.entropy_contexts = VocalEntropy(segs, 2)

    return out
end

-- The CSV column order for vocal rows. Kept beside the scorer for the same reason
-- SCORE_FACTOR_KEYS is: the writer and the analysis both drive off it, so a key here
-- that the scorer never sets becomes a silently empty column.
VOCAL_FACTOR_KEYS = {
    'playing_s', 'syllables_total', 'tubes_total',
    'syl_density_avg', 'syl_density_peak',
    'tube_density_avg', 'tube_density_peak',
    'pc_change_rate',
    'tight_p10', 'tight_med',
    'phrase_syl_mean', 'phrase_syl_peak', 'phrase_len_mean',
    'pc_interval_mean', 'pc_interval_p90', 'pc_range',
    -- The raw-semitone twins. Present so the octave claim can be tested as a paired
    -- substitution against the mod-12 pair above, never fitted alongside them.
    'semi_interval_mean', 'semi_interval_p90',
    -- The @pitched family: the same pitch measurements over only the notes whose pitch
    -- the game scores. A substitution for the columns above, never fitted with them.
    'pc_interval_mean_p', 'pc_interval_p90_p', 'pc_range_p', 'pc_change_rate_p',
    'entropy_h2_rel_p', 'semi_interval_mean_p', 'semi_interval_p90_p', 'pitched_frac',
    -- RANGE AND REGISTER, on pitched notes. Round 12 reverses round 11's refusal to fit
    -- notated_range: the labels were set by playtesters singing, and producing a leap
    -- costs effort the game's pitch-class scoring does not charge for.
    'notated_range', 'pitch_mean', 'pitch_p90', 'octave_jump_rate',
    -- BREATH: the long arm of the U-shaped length relationship, which a monotonic
    -- measure reads as zero because the short arm cancels it.
    'longest_note_s', 'breath_load', 'longtime_frac',
    -- TESSITURA: where the part sits. high_time_67 and high_time_70 are a declared
    -- threshold SUBSTITUTION, never fitted together.
    'top_note', 'high_time_67', 'high_time_70',
    'high_hold_time_70', 'high_longest_note_70', 'high_reentry_rate_70',
    'pitch_p98_time', 'phrase_density_p90', 'phrase_complex_p90',
    'vocal_parts',
    'talkie_frac', 'caret_frac', 'plus_frac',
    'short_frac', 'short_moving_frac',
    'entropy_h2_rel',
}

-- Fold the vocal-only columns into SCORE_FACTOR_KEYS, which is what the CSV writer, the
-- protocol and the analysis all drive off. Doing it here rather than editing the gem
-- list keeps the two factor sets defined beside their own scorers, and means no consumer
-- needs to learn about a second list.
--
-- FOUR NAMES ARE DELIBERATELY SHARED rather than prefixed: playing_s, tight_p10,
-- tight_med and entropy_h2_rel mean the same thing here as they do for a gem chart
-- (seconds of playing, onset-gap percentiles in QN, conditional entropy of relative
-- motion) and are measured the same way. Giving them vocal-specific twins would put two
-- columns of one quantity in the CSV and let a candidate accidentally fit both.
--
-- Every other vocal column reads 0 on a gem row and every gem column reads 0 on a vocal
-- row - the same structural-zero arrangement the drum and Pro Keys columns already use.
-- MultiFit clamps a zero-variance column, so a constant contributes nothing to a fit.
do
    local have = {}
    for _, k in ipairs(SCORE_FACTOR_KEYS) do have[k] = true end
    for _, k in ipairs(VOCAL_FACTOR_KEYS) do
        if not have[k] then
            SCORE_FACTOR_KEYS[#SCORE_FACTOR_KEYS + 1] = k
            have[k] = true
        end
    end
end
