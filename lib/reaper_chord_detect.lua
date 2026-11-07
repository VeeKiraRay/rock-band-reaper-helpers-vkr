-- Chord names from a keys recording - pure, no r / ctx / S.
--
-- Used by the Instrument Helper's Keys > Tuner. The caller reads short windows of the keys
-- stem (and optionally the bass stem) and this file turns them into chord candidates:
--
--   1. ChordFrameChroma: a 128 ms frame (CHORD_FRAME_N samples at CHORD_SR) -> per MIDI
--      pitch C3 .. C7 the weighted harmonic sum of its partials, squared, folded into 12
--      pitch classes. Pitches under C3 are left out (they smear over several semitones).
--   2. Add the frames of one chord together (ChordSumAdd).
--   3. ChordRank: cosine against chord templates (maj, m, 7, maj7, m7, sus4, dim on every
--      root), with an optional key prior, an optional bass-root prior, and "prefer plain
--      chords" - penalties on 7ths and sus4, the shapes a chord tone's 3rd partial fakes.
--
-- The method measured offline on the decrypted official moggs' keys stems against the
-- charted Pro Keys Expert: 81% right first / 92% in the top 3 on the songs it was developed
-- on, 60% / 83% on held-out songs (very song-dependent). The measured implementation is
-- dev/tools/chord_core.lua and this file must keep reproducing it:
-- dev/tools/chord_detect_parity_offline.lua compares the two on real audio. Change a
-- constant here and the measured accuracy no longer applies.
--
-- Requires: SPECTRUM_NFFT / SpectrumHann / SpectrumMagnitudes (lib/reaper_spectrum.lua) and
-- YINWindowSize / ComputeCMND / SearchYINTau (lib/reaper_dsp.lua), loaded BEFORE this file.

CHORD_SR        = 16000     -- the analysis rate the method was measured at
CHORD_FRAME_N   = 2048      -- samples per frame (128 ms)
CHORD_HOP_S     = 0.064     -- frame spacing inside one reading
CHORD_ATTACK_S  = 0.030     -- a chord's first frame starts this long after its start
CHORD_SPAN_MAX  = 6         -- frames per reading at most
-- Frames for a stopped reading with no charted chord to give its length: 'short' fits the
-- many chords under half a second, 'long' slow held chords. Playing reads CHORD_PLAY_FRAMES
-- frames ending at the playhead.
CHORD_READ_FRAMES = { short = 2, long = 6 }
CHORD_PLAY_FRAMES = 2

local SR, NFFT = CHORD_SR, SPECTRUM_NFFT
local DF = SR / NFFT
local SILENT = 1e-3
local F_TOP, MAX_H = 4000, 10
local LOW_PITCH, TOP_PITCH = 48, 96
local KEY_BONUS, BASS_BONUS = 0.08, 0.03
local PEN_7TH, PEN_SUS4 = 0.06, 0.05

----------------------------------------------------------------------
-- Templates
----------------------------------------------------------------------

CHORD_QUALITIES = {
    { name = 'maj',  suffix = '',     tones = { 0, 4, 7 } },
    { name = 'min',  suffix = 'm',    tones = { 0, 3, 7 } },
    { name = 'dom7', suffix = '7',    tones = { 0, 4, 7, 10 } },
    { name = 'maj7', suffix = 'maj7', tones = { 0, 4, 7, 11 } },
    { name = 'min7', suffix = 'm7',   tones = { 0, 3, 7, 10 } },
    { name = 'sus4', suffix = 'sus4', tones = { 0, 5, 7 } },
    { name = 'dim',  suffix = 'dim',  tones = { 0, 3, 6 } },
}
local SEVENTH = { [3] = true, [4] = true, [5] = true }
local SUS4 = 6

CHORD_PC_NAMES = { [0] = 'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B' }

local TEMPLATES, BY_MASK = {}, {}
for qi, q in ipairs(CHORD_QUALITIES) do
    for root = 0, 11 do
        local v, mask = {}, 0
        for i = 0, 11 do v[i] = 0 end
        for _, t in ipairs(q.tones) do
            local pc = (root + t) % 12
            v[pc] = 1
            mask = mask | (1 << pc)
        end
        local norm = math.sqrt(#q.tones)
        for i = 0, 11 do v[i] = v[i] / norm end
        local t = { root = root, q = qi, mask = mask, v = v }
        TEMPLATES[#TEMPLATES + 1] = t
        BY_MASK[mask] = t
    end
end

-- The template whose pitch classes are exactly `mask`, or nil.
function ChordTemplateForMask(mask) return BY_MASK[mask] end

-- "C", "Am7", "F#sus4" ...
function ChordName(t) return CHORD_PC_NAMES[t.root] .. CHORD_QUALITIES[t.q].suffix end

-- The chord's notes in chord order from the root: "D+F+A", "A+C+E+G".
function ChordNotes(t)
    local out = {}
    for _, st in ipairs(CHORD_QUALITIES[t.q].tones) do out[#out + 1] = CHORD_PC_NAMES[(t.root + st) % 12] end
    return table.concat(out, '+')
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

local function PeakAt(m, f)
    local w = math.max(DF, 0.015 * f)
    local a, b = math.max(1, math.floor((f - w) / DF)), math.min(NFFT // 2, math.ceil((f + w) / DF))
    local best = 0
    for k = a, b do if m[k] > best then best = m[k] end end
    return best
end

CHORD_PASS_LO = 40          -- lowest pitch the passage check reads (per-pitch sums)

-- One frame, both readings from one spectrum: the raw chroma[0 .. 11] (pitches C3 up, sums
-- squared) and the per-pitch harmonic sums [CHORD_PASS_LO .. 96] the passage check uses.
-- mono[1 .. CHORD_FRAME_N], not windowed. Returns nil when silent.
-- cents: the song's tuning offset from concert pitch (0 when unknown).
function ChordFrameAnalyse(mono, cents)
    cents = cents or 0
    local L = CHORD_FRAME_N
    local e = 0
    for i = 1, L do e = e + mono[i] * mono[i] end
    if math.sqrt(e / L) < SILENT then return nil end
    local w = SpectrumHann(L)
    local x = {}
    for i = 1, L do x[i] = mono[i] * w[i] end
    local m = SpectrumMagnitudes(x, L)
    local c, sal = {}, {}
    for i = 0, 11 do c[i] = 0 end
    for p = CHORD_PASS_LO, TOP_PITCH do
        local f0 = 440 * 2 ^ ((p - 69) / 12 + cents / 1200)
        local s = 0
        for h = 1, math.min(MAX_H, math.floor(F_TOP / f0)) do
            s = s + (f0 + 20) / (h * f0 + 320) * PeakAt(m, h * f0)
        end
        sal[p] = s
        if p >= LOW_PITCH then c[p % 12] = c[p % 12] + s * s end
    end
    return c, sal
end

-- The chroma alone (see ChordFrameAnalyse).
function ChordFrameChroma(mono, cents)
    return (ChordFrameAnalyse(mono, cents))
end

-- A running sum of frame chromas: { n = frames, [0..11] }.
function ChordSumNew()
    local s = { n = 0 }
    for i = 0, 11 do s[i] = 0 end
    return s
end
function ChordSumAdd(sum, raw)
    if not raw then return end
    sum.n = sum.n + 1
    for i = 0, 11 do sum[i] = sum[i] + raw[i] end
end

----------------------------------------------------------------------
-- Ranking
----------------------------------------------------------------------

-- Pitch-class mask of a key (0 = C): its major scale, or natural minor plus the raised 7th.
function ChordKeyMask(tonic, minor)
    local steps = minor and { 0, 2, 3, 5, 7, 8, 10, 11 } or { 0, 2, 4, 5, 7, 9, 11 }
    local mask = 0
    for _, s in ipairs(steps) do mask = mask | (1 << ((tonic + s) % 12)) end
    return mask
end

-- raw: a summed chroma[0..11]. opts: { key_mask = n or nil, bass = pc or nil, plain = bool }.
-- Returns the three best templates (best first) and the margin best - second, or nil when
-- there is nothing to rank.
function ChordRank(raw, opts)
    opts = opts or {}
    local s2 = 0
    for i = 0, 11 do s2 = s2 + raw[i] * raw[i] end
    if s2 <= 0 then return nil end
    local norm = math.sqrt(s2)
    local km, bass, plain = opts.key_mask, opts.bass, opts.plain
    local best = { { s = -math.huge }, { s = -math.huge }, { s = -math.huge } }
    for _, t in ipairs(TEMPLATES) do
        local s = 0
        for i = 0, 11 do s = s + raw[i] / norm * t.v[i] end
        if km and t.mask & km == t.mask then s = s + KEY_BONUS end
        if bass and t.root == bass then s = s + BASS_BONUS end
        if plain then
            if SEVENTH[t.q] then s = s - PEN_7TH end
            if t.q == SUS4 then s = s - PEN_SUS4 end
        end
        if s > best[1].s then best[3], best[2], best[1] = best[2], best[1], { t = t, s = s }
        elseif s > best[2].s then best[3], best[2] = best[2], { t = t, s = s }
        elseif s > best[3].s then best[3] = { t = t, s = s } end
    end
    return { best[1].t, best[2].t, best[3].t }, best[1].s - best[2].s
end

-- How far the best candidate leads the second, as measured on the official songs:
-- 'clear' (>= 0.10, ~95% right), 'likely' (0.05-0.10, ~80%), 'maybe' (0.02-0.05, ~60%),
-- 'unsure' (< 0.02, ~40%).
function ChordConfidence(margin)
    if margin >= 0.10 then return 'clear' end
    if margin >= 0.05 then return 'likely' end
    if margin >= 0.02 then return 'maybe' end
    return 'unsure'
end

-- The triad above a 4-note chord's root ("Am7" -> the C triad), or nil for a triad. Pro Keys
-- charts one hand, and with a 7th chord that hand often plays this triad while the root is
-- the other hand's (or the bass's).
function ChordUpperTriad(t)
    if #CHORD_QUALITIES[t.q].tones < 4 then return nil end
    return BY_MASK[t.mask & ~(1 << t.root)]
end

-- The name with the bass under it: "C" (bass on the root or unknown), "C/E" (bass on another
-- chord tone), "C (bass A)" (bass outside the chord).
function ChordNameOverBass(t, bass)
    local name = ChordName(t)
    if not bass or bass == t.root then return name end
    if t.mask & (1 << bass) ~= 0 then return name .. '/' .. CHORD_PC_NAMES[bass] end
    return ('%s (bass %s)'):format(name, CHORD_PC_NAMES[bass])
end

----------------------------------------------------------------------
-- Bass stem: one YIN reading (35-400 Hz, 60 ms)
----------------------------------------------------------------------

CHORD_BASS_STEP_S = 0.060   -- spacing of bass readings over a chord
local B_MIN_F, B_MAX_F, B_WIN_S = 35, 400, 0.060
local B_TAU_MAX, B_M = YINWindowSize(SR, B_WIN_S, B_MIN_F)
local B_TAU_MIN = math.floor(SR / B_MAX_F)
CHORD_BASS_N = B_M          -- samples per bass reading (at CHORD_SR)
CHORD_BASS_WIN_S = B_WIN_S

-- mono[1 .. CHORD_BASS_N] -> pitch class, or nil (silent / unclear).
function ChordBassPc(mono, cents)
    cents = cents or 0
    local e = 0
    for i = 1, B_M do e = e + mono[i] * mono[i] end
    if math.sqrt(e / B_M) < SILENT then return nil end
    local d = ComputeCMND(mono, B_TAU_MAX)
    if not d then return nil end
    local p = SearchYINTau(d, B_TAU_MIN, B_TAU_MAX, 0.15, SR * 2 ^ (-cents / 1200), B_MIN_F, B_MAX_F, 0.5)
    return p and math.floor(p + 0.5) % 12 or nil
end

-- The commonest pitch class of a list of readings (no nil entries: append only real readings;
-- a tie goes to the class that reached the count first).
function ChordBassVote(pcs)
    local votes, best, bc = {}, nil, 0
    for _, pc in ipairs(pcs) do
        if pc then
            votes[pc] = (votes[pc] or 0) + 1
            if votes[pc] > bc then best, bc = pc, votes[pc] end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Single notes or chords? A passage verdict from the audio alone
----------------------------------------------------------------------
-- Pro Keys parts are often single notes or broken chords, where naming every key press as a
-- chord would mislead. One onset is too little to tell, a few seconds is enough: measured
-- over 4 s passages of the official songs, this keeps 90% of chord passages as chords and
-- calls about half the single-note passages single (much more on a clean melody).
--   Frames every CHORD_PASS_HOP_S; flux = the summed per-pitch increase over the frame two
--   hops earlier; an onset = a local flux peak over 1.5 x the passage's median flux. At each
--   onset: the frame's best template score and the struck ratio (notes picked from the
--   increase - strongest pitch, then it, its neighbours and overtone / sub-octave relatives
--   zeroed, repeat - second pick over first), as z-scores against the measured statistics,
--   averaged. The passage value is the mean over its onsets.
-- The struck note of each onset (the first pick, a MIDI pitch) names a key press: right
-- about 6 in 10 times on official songs, more on a clean melody; its octave is a guess.

CHORD_PASS_HOP_S  = 0.064
CHORD_PASS_FRAMES = 62      -- frames per passage (about 4 s)
local PASS_FLUX_K = 1.5
local PASS_TMPL_MEAN, PASS_TMPL_SD = 0.833093, 0.090663
local PASS_ST_MEAN, PASS_ST_SD = 0.601260, 0.253554
local PASS_THRESHOLD = -0.098
local PASS_REL = { 0, 1, -1, 12, -12, 19, 24, 28, 31, 34, 36, -19, -24 }

local function PassPicks(v)
    local w = {}
    for p = CHORD_PASS_LO, TOP_PITCH do w[p] = v[p] end
    local picks, vals = {}, {}
    for _ = 1, 6 do
        local bp, bv = nil, 0
        for p = CHORD_PASS_LO, TOP_PITCH do if w[p] > bv then bp, bv = p, w[p] end end
        if not bp or bv <= 0 then break end
        picks[#picks + 1], vals[#vals + 1] = bp, bv
        for _, d in ipairs(PASS_REL) do
            local q = bp + d
            if w[q] then w[q] = 0 end
        end
    end
    return picks, vals
end

local function PassMedian(a)
    local s = {}
    for i, v in ipairs(a) do s[i] = v end
    table.sort(s)
    return s[math.max(1, math.min(#s, math.floor(0.5 * #s + 0.5)))]
end

-- frames[1 .. n]: the per-pitch sums of ChordFrameAnalyse (false when silent or missing)
-- every CHORD_PASS_HOP_S; the passage is frames 4 .. n - 1 (three frames before it for the
-- flux, one after for the peak test) - n = CHORD_PASS_FRAMES + 4 for a full passage.
-- Returns { onsets = { { i, tmpl, st, note } }, value, single }; value / single are nil when
-- no key press was found.
function ChordPassage(frames)
    local n = #frames
    local flux, inc = {}, {}
    for i = 3, n do
        local a, b = frames[i], frames[i - 2]
        if a then
            local f, iv = 0, {}
            for p = CHORD_PASS_LO, TOP_PITCH do
                local d = math.max(0, a[p] - (b and b[p] or 0))
                iv[p] = d
                f = f + d
            end
            flux[i], inc[i] = f, iv
        end
    end
    local vals = {}
    for i = 4, n - 1 do if flux[i] then vals[#vals + 1] = flux[i] end end
    local out = { onsets = {} }
    if #vals == 0 then return out end
    local med = PassMedian(vals)
    local sum = 0
    for i = 4, n - 1 do
        local f = flux[i]
        if f and f > PASS_FLUX_K * med and f > 1e-6 and f >= (flux[i - 1] or 0) and f >= (flux[i + 1] or 0) then
            local a = frames[i]
            local raw, s2 = {}, 0
            for q = 0, 11 do raw[q] = 0 end
            for p = LOW_PITCH, TOP_PITCH do raw[p % 12] = raw[p % 12] + a[p] * a[p] end
            for q = 0, 11 do s2 = s2 + raw[q] * raw[q] end
            local tm = 0
            if s2 > 0 then
                local norm = math.sqrt(s2)
                for _, t in ipairs(TEMPLATES) do
                    local s = 0
                    for q = 0, 11 do s = s + raw[q] / norm * t.v[q] end
                    if s > tm then tm = s end
                end
            end
            local picks, pv = PassPicks(inc[i])
            local st = (#pv >= 2) and pv[2] / pv[1] or 0
            out.onsets[#out.onsets + 1] = { i = i, tmpl = tm, st = st, note = picks[1] }
            sum = sum + ((tm - PASS_TMPL_MEAN) / PASS_TMPL_SD + (st - PASS_ST_MEAN) / PASS_ST_SD) / 2
        end
    end
    if #out.onsets > 0 then
        out.value = sum / #out.onsets
        out.single = out.value < PASS_THRESHOLD
    end
    return out
end
