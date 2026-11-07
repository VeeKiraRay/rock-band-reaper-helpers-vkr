-- Chord detection core - offline, pure Lua, no REAPER.
--
-- The method measured in the 2026-11 chord probe rounds on the keys stems of the decrypted
-- official moggs, scored against the charted Pro Keys Expert (frozen after round 5; one
-- hold-out run). lib/reaper_chord_detect.lua is the shipped port and must reproduce this
-- file frame by frame: dev/tools/chord_detect_parity_offline.lua compares the two.
--
--   1. A 128 ms frame (2048 samples at 16 kHz, Hann, zero-padded to SPECTRUM_NFFT).
--   2. Per MIDI pitch C3 (48) .. C7 (96): the weighted harmonic sum of its first ten
--      partials up to 4 kHz (Klapuri's weights (f0 + 20) / (h f0 + 320), each partial the
--      peak within +-1.5% or one bin), squared and folded into 12 pitch classes. Pitches
--      under C3 are left out: low notes smear over several semitones in 128 ms.
--   3. A chord's chroma = the sum of its frames (onset + 30 ms, then every 64 ms, at most 6).
--   4. Cosine against binary templates (maj, m, 7, maj7, m7, sus4, dim on every root), plus:
--      key prior +0.08 for templates inside the key (minor: natural + raised 7th), bass prior
--      +0.03 for the template rooted on the bass stem's pitch class, and - "prefer plain
--      chords" - 7ths -0.06 and sus4 -0.05 (a chord tone's 3rd partial fakes those shapes).
--
--   local C = dofile(_root .. 'dev/tools/chord_core.lua')
--
-- Callers must have loaded lib/reaper_spectrum.lua and lib/reaper_dsp.lua first.

local C = {}

C.SR        = 16000
C.FRAME_N   = 2048          -- samples per frame
C.HOP_S     = 0.064         -- frame spacing inside a chord
C.ATTACK_S  = 0.030         -- the first frame starts this long after the chord's start
C.SPAN_MAX  = 6             -- frames per chord at most
C.LOW_PITCH = 48            -- C3: lowest pitch summed into the chroma
C.TOP_PITCH = 96
C.KEY_BONUS, C.BASS_BONUS = 0.08, 0.03
C.PEN_7TH, C.PEN_SUS4     = 0.06, 0.05

local SR, NFFT = C.SR, SPECTRUM_NFFT
local DF = SR / NFFT
local SILENT = 1e-3
local F_TOP, MAX_H = 4000, 10

----------------------------------------------------------------------
-- Templates
----------------------------------------------------------------------

C.QUALS = {
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

C.TEMPLATES = {}            -- { root, q, mask, v[0..11] (unit length) }
C.LABEL = {}                -- pitch-class mask -> template (chart chords that match one)
for qi, q in ipairs(C.QUALS) do
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
        C.TEMPLATES[#C.TEMPLATES + 1] = t
        C.LABEL[mask] = t
    end
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

-- mono[1 .. FRAME_N] (not windowed) -> raw chroma[0 .. 11], or nil when silent.
-- cents: the song's tuning offset (songs.dta tuning_offset_cents; 0 when unknown).
function C.FrameChroma(mono, cents)
    local L = C.FRAME_N
    local e = 0
    for i = 1, L do e = e + mono[i] * mono[i] end
    if math.sqrt(e / L) < SILENT then return nil end
    local w = SpectrumHann(L)
    local x = {}
    for i = 1, L do x[i] = mono[i] * w[i] end
    local m = SpectrumMagnitudes(x, L)
    local c = {}
    for i = 0, 11 do c[i] = 0 end
    for p = C.LOW_PITCH, C.TOP_PITCH do
        local f0 = 440 * 2 ^ ((p - 69) / 12 + cents / 1200)
        local s = 0
        for h = 1, math.min(MAX_H, math.floor(F_TOP / f0)) do
            s = s + (f0 + 20) / (h * f0 + 320) * PeakAt(m, h * f0)
        end
        c[p % 12] = c[p % 12] + s * s
    end
    return c
end

----------------------------------------------------------------------
-- Ranking
----------------------------------------------------------------------

-- Pitch-class mask of a key: its major / natural minor scale, minor with the raised 7th.
function C.KeyMask(tonic, minor)
    local steps = minor and { 0, 2, 3, 5, 7, 8, 10, 11 } or { 0, 2, 4, 5, 7, 9, 11 }
    local mask = 0
    for _, s in ipairs(steps) do mask = mask | (1 << ((tonic + s) % 12)) end
    return mask
end

-- raw: a summed chroma[0..11]. opts: { key_mask = n or nil, bass = pc or nil, plain = bool }.
-- Returns the three best templates (best first) and the margin best - second, or nil.
function C.Rank(raw, opts)
    local s2 = 0
    for i = 0, 11 do s2 = s2 + raw[i] * raw[i] end
    if s2 <= 0 then return nil end
    local norm = math.sqrt(s2)
    local km, bass, plain = opts.key_mask, opts.bass, opts.plain
    local best = { { s = -math.huge }, { s = -math.huge }, { s = -math.huge } }
    for _, t in ipairs(C.TEMPLATES) do
        local s = 0
        for i = 0, 11 do s = s + raw[i] / norm * t.v[i] end
        if km and t.mask & km == t.mask then s = s + C.KEY_BONUS end
        if bass and t.root == bass then s = s + C.BASS_BONUS end
        if plain then
            if SEVENTH[t.q] then s = s - C.PEN_7TH end
            if t.q == SUS4 then s = s - C.PEN_SUS4 end
        end
        if s > best[1].s then best[3], best[2], best[1] = best[2], best[1], { t = t, s = s }
        elseif s > best[2].s then best[3], best[2] = best[2], { t = t, s = s }
        elseif s > best[3].s then best[3] = { t = t, s = s } end
    end
    return { best[1].t, best[2].t, best[3].t }, best[1].s - best[2].s
end

----------------------------------------------------------------------
-- Bass stem: one YIN reading (35-400 Hz, 60 ms)
----------------------------------------------------------------------

C.BASS_MIN_F, C.BASS_MAX_F, C.BASS_WIN_S, C.BASS_STEP_S = 35, 400, 0.060, 0.060
local B_TAU_MAX, B_M = YINWindowSize(SR, C.BASS_WIN_S, C.BASS_MIN_F)
local B_TAU_MIN = math.floor(SR / C.BASS_MAX_F)
C.BASS_N = B_M              -- samples per reading

-- mono[1 .. BASS_N] -> pitch class, or nil (silent / unclear).
function C.BassPc(mono, cents)
    local e = 0
    for i = 1, B_M do e = e + mono[i] * mono[i] end
    if math.sqrt(e / B_M) < SILENT then return nil end
    local d = ComputeCMND(mono, B_TAU_MAX)
    if not d then return nil end
    local p = SearchYINTau(d, B_TAU_MIN, B_TAU_MAX, 0.15, SR * 2 ^ (-cents / 1200), C.BASS_MIN_F, C.BASS_MAX_F, 0.5)
    return p and math.floor(p + 0.5) % 12 or nil
end

-- The commonest pitch class of a list of readings (no nil entries; ties: the earliest to
-- reach the count).
function C.BassVote(pcs)
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
-- Single notes or chords? A passage verdict without chart onsets
----------------------------------------------------------------------
-- Measured over 4 s passages of the official songs (all chart onsets in the passage single
-- notes, or all 3+ pitch class chords). Frames every PASS_HOP_S; per frame the harmonic sum
-- of every MIDI pitch PASS_LO .. TOP_PITCH. Flux = the summed per-pitch increase over the
-- frame two hops (128 ms) earlier; an onset = a local flux peak over PASS_FLUX_K x the
-- passage's median flux. At each onset: the best template score of the frame (chroma from
-- C3 up, no priors) and the struck ratio - after picking notes from the increase (strongest
-- pitch, zero it, its neighbours and overtone / sub-octave relatives, repeat), the second
-- pick over the first. Their z-scores (dev statistics, frozen) are averaged; the passage
-- value is the mean over its onsets, and under PASS_THRESHOLD it reads as single notes.

C.PASS_HOP_S, C.PASS_FRAMES, C.PASS_LO, C.PASS_FLUX_K = 0.064, 62, 40, 1.5
C.PASS_TMPL_MEAN, C.PASS_TMPL_SD = 0.833093, 0.090663
C.PASS_ST_MEAN, C.PASS_ST_SD = 0.601260, 0.253554
C.PASS_THRESHOLD = -0.098           -- keeps 90% of the dev chord passages as chords
local PASS_REL = { 0, 1, -1, 12, -12, 19, 24, 28, 31, 34, 36, -19, -24 }

-- mono[1 .. FRAME_N] (not windowed) -> per-pitch harmonic sums [PASS_LO .. TOP_PITCH], or nil.
function C.FramePitches(mono, cents)
    local L = C.FRAME_N
    local e = 0
    for i = 1, L do e = e + mono[i] * mono[i] end
    if math.sqrt(e / L) < SILENT then return nil end
    local w = SpectrumHann(L)
    local x = {}
    for i = 1, L do x[i] = mono[i] * w[i] end
    local m = SpectrumMagnitudes(x, L)
    local sal = {}
    for p = C.PASS_LO, C.TOP_PITCH do
        local f0 = 440 * 2 ^ ((p - 69) / 12 + cents / 1200)
        local s = 0
        for h = 1, math.min(MAX_H, math.floor(F_TOP / f0)) do
            s = s + (f0 + 20) / (h * f0 + 320) * PeakAt(m, h * f0)
        end
        sal[p] = s
    end
    return sal
end

local function Picks(v)
    local w = {}
    for p = C.PASS_LO, C.TOP_PITCH do w[p] = v[p] end
    local picks, vals = {}, {}
    for _ = 1, 6 do
        local bp, bv = nil, 0
        for p = C.PASS_LO, C.TOP_PITCH do if w[p] > bv then bp, bv = p, w[p] end end
        if not bp or bv <= 0 then break end
        picks[#picks + 1], vals[#vals + 1] = bp, bv
        for _, d in ipairs(PASS_REL) do
            local q = bp + d
            if w[q] then w[q] = 0 end
        end
    end
    return picks, vals
end

local function Median(a)
    local s = {}
    for i, v in ipairs(a) do s[i] = v end
    table.sort(s)
    return s[math.max(1, math.min(#s, math.floor(0.5 * #s + 0.5)))]
end

-- frames[1 .. n]: FramePitches results (false when silent) every PASS_HOP_S; the passage is
-- frames 4 .. n - 1 (three before it for the flux, one after for the peak test).
-- Returns { onsets = { { i, tmpl, st, note } }, value, single } - value nil when no onset.
function C.Passage(frames)
    local n = #frames
    local flux, inc = {}, {}
    for i = 3, n do
        local a, b = frames[i], frames[i - 2]
        if a then
            local f, iv = 0, {}
            for p = C.PASS_LO, C.TOP_PITCH do
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
    local med = Median(vals)
    local sum = 0
    for i = 4, n - 1 do
        local f = flux[i]
        if f and f > C.PASS_FLUX_K * med and f > 1e-6 and f >= (flux[i - 1] or 0) and f >= (flux[i + 1] or 0) then
            local a = frames[i]
            local raw, s2 = {}, 0
            for q = 0, 11 do raw[q] = 0 end
            for p = 48, C.TOP_PITCH do raw[p % 12] = raw[p % 12] + a[p] * a[p] end
            for q = 0, 11 do s2 = s2 + raw[q] * raw[q] end
            local tm = 0
            if s2 > 0 then
                local norm = math.sqrt(s2)
                for _, t in ipairs(C.TEMPLATES) do
                    local s = 0
                    for q = 0, 11 do s = s + raw[q] / norm * t.v[q] end
                    if s > tm then tm = s end
                end
            end
            local picks, pv = Picks(inc[i])
            local st = (#pv >= 2) and pv[2] / pv[1] or 0
            out.onsets[#out.onsets + 1] = { i = i, tmpl = tm, st = st, note = picks[1] }
            sum = sum + ((tm - C.PASS_TMPL_MEAN) / C.PASS_TMPL_SD + (st - C.PASS_ST_MEAN) / C.PASS_ST_SD) / 2
        end
    end
    if #out.onsets > 0 then
        out.value = sum / #out.onsets
        out.single = out.value < C.PASS_THRESHOLD
    end
    return out
end

return C
