-- Second voice beside a known lead, from one mixed vocal recording - pure, no r / ctx / S.
--
-- Used by the vocal helper's Pitch > Tuner Harmony readout (and the standalone Pitch Tuner).
-- The caller knows which note the lead sings (its chart, e.g. HARM1) and passes a short
-- window of the vocal recording. The method:
--
--   1. Find the lead's exact period T near its charted pitch (+-2 semitones; singers sit off
--      the chart by some cents).
--   2. Cancel it: y[n] = x[n] - x[n - T] removes everything that repeats every T - the lead
--      and all its overtones. Other voices survive.
--   3. Search y for a pitch within an octave of the lead, with two rules ('yin': the first
--      clear dip; 'short': the shortest period nearly as good as the best, against readings
--      an octave or an octave and a fifth too low). Both candidates are kept.
--   4. Vote over the frames of one lead note: the commonest pitch class, then its commonest
--      exact pitch; optionally snapped into the song's key when one semitone outside it.
--
-- This is the method measured offline on 70 official songs (round 5 of the 2026-11 harmony
-- probe rounds, then a round on the Tuner's way of reading). The measured implementation is
-- dev/tools/harmony_audio_core.lua, and this file must keep reproducing it:
-- dev/tools/harmony_detect_parity_offline.lua compares the two on real audio. Change a
-- constant here and the measured accuracy no longer applies.
--
-- Not covered: a voice an octave ABOVE the lead (removed together with the lead), and a third
-- voice (measured at ~25%, too weak to show).
--
-- Requires: ComputeCMND (lib/reaper_dsp.lua); SPECTRUM_NFFT / SpectrumHann /
-- SpectrumMagnitudes (lib/reaper_spectrum.lua, loaded BEFORE this file).

HARMONY_SR = 16000          -- the analysis rate the method was measured at

local WIN_S        = 0.040  -- correlation width
local MIN_F        = 70
local MAX_F        = 1000
local THRESH       = 0.15   -- 'yin' rule: a dip under this counts as clear
local MIN_CONF     = 0.5    -- the lead counts as heard (lead_pitch) at this confidence
local SEARCH_ST    = 2      -- the lead's period is searched within +-2 st of the chart
local BAND_ST      = 13     -- the second voice is searched within +-13 st of the lead
local SHORT_MARGIN = 0.10   -- 'short' rule margin above the deepest dip
local SILENT       = 1e-3   -- frame rms below this is not analysed

HARMONY_RATIO = 0.2         -- a frame votes only when this much is left after cancelling
HARMONY_FLOOR = 0.3         -- ... and its second-voice pitch has at least this confidence

local SR      = HARMONY_SR
local TAU_MAX = math.floor(SR / MIN_F)
local TAU_MIN = math.floor(SR / MAX_F)
local W       = math.max(2, math.floor(WIN_S * SR))
local M       = W + TAU_MAX            -- samples ComputeCMND needs
local PAD     = TAU_MAX + 2            -- history for x[n - T]

-- How many samples one frame reads (at HARMONY_SR), and where the read starts relative to
-- the frame's centre time t: read HARMONY_FRAME_N samples from t - HARMONY_FRAME_LEAD seconds.
HARMONY_FRAME_N    = M + PAD
HARMONY_FRAME_LEAD = (M // 2 + PAD) / SR

local function Rms(t, a, b)
    local s = 0
    for i = a, b do s = s + t[i] * t[i] end
    return math.sqrt(s / math.max(1, b - a + 1))
end

local function Corr(x, y, a, b)
    local sx, sy, sxx, syy, sxy, n = 0, 0, 0, 0, 0, b - a + 1
    for i = a, b do
        sx, sy = sx + x[i], sy + y[i]
        sxx, syy, sxy = sxx + x[i] * x[i], syy + y[i] * y[i], sxy + x[i] * y[i]
    end
    local vx, vy = sxx - sx * sx / n, syy - sy * sy / n
    if vx <= 1e-12 or vy <= 1e-12 then return nil end
    return (sxy - sx * sy / n) / math.sqrt(vx * vy)
end

local function PeriodOf(pitch, cents)
    return SR / (440 * 2 ^ ((pitch - 69) / 12) * 2 ^ ((cents or 0) / 1200))
end

local function TauPitch(tau, sr_eff)
    local f = sr_eff / tau
    if f < MIN_F or f > MAX_F then return nil end
    return math.floor(69 + 12 * math.log(f / 440, 2) + 0.5)
end

-- The CMND minimum within +-st semitones of an expected period, refined by at most one
-- sample. Returns the period and its dip, or nil.
local function PeriodNear(d, t0, st)
    local lo = math.max(TAU_MIN + 1, math.floor(t0 / 2 ^ (st / 12)))
    local hi = math.min(TAU_MAX - 1, math.ceil(t0 * 2 ^ (st / 12)))
    if lo >= hi then return nil end
    local bt, bd = lo, math.huge
    for tau = lo, hi do if d[tau] < bd then bt, bd = tau, d[tau] end end
    local T = bt
    local den = 2 * d[bt] - d[bt - 1] - d[bt + 1]
    if den > 1e-10 then T = bt + math.max(-1, math.min(1, (d[bt - 1] - d[bt + 1]) / (2 * den))) end
    return T, d[bt]
end

-- Pitch search over d in periods [lo, hi], skipping skip(tau). Rules as in the header.
-- Returns pitch, confidence or nil when the confidence is under `floor`.
local function PickPitch(d, lo, hi, skip, sr_eff, rule, floor)
    lo, hi = math.max(lo, TAU_MIN + 1), math.min(hi, TAU_MAX - 1)
    if lo >= hi then return nil end
    local best
    if rule == 'short' then
        local gmin = math.huge
        for tau = lo, hi do
            if not skip(tau) and d[tau] < gmin then gmin = d[tau] end
        end
        for tau = lo, hi do
            if not skip(tau) and d[tau] <= d[tau - 1] and d[tau] <= d[tau + 1]
               and d[tau] <= gmin + SHORT_MARGIN then
                best = tau
                break
            end
        end
    else
        for tau = lo, hi do
            if not skip(tau) and d[tau] < THRESH then
                while tau < hi and d[tau + 1] < d[tau] do tau = tau + 1 end
                best = tau
                break
            end
        end
        if not best then
            local bd = math.huge
            for tau = lo, hi do
                if not skip(tau) and d[tau] < bd then best, bd = tau, d[tau] end
            end
        end
    end
    if not best or 1 - d[best] < floor then return nil end
    local conf = 1 - d[best]
    local tau = best
    local den = 2 * d[best] - d[best - 1] - d[best + 1]
    if den > 1e-10 then tau = best + math.max(-1, math.min(1, (d[best - 1] - d[best + 1]) / (2 * den))) end
    local p = TauPitch(tau, sr_eff)
    if not p then return nil end
    return p, conf
end

-- One frame. mono / left / right: HARMONY_FRAME_N samples each (left / right may be nil
-- for a mono source), read as described at HARMONY_FRAME_N. lead_pitch: the charted lead
-- note sounding at the frame. cents: how far the recording is tuned off A440 (0 normally).
-- Returns nil for a silent frame, else:
--   lead_pitch / lead_conf  the lead heard near its chart (MIDI note, 0..1), nil if not found
--   ratio                   what is left after cancelling the lead (0 = nothing; a frame
--                           votes only above HARMONY_RATIO)
--   p_yin, c_yin, p_short, c_short   second-voice candidates (MIDI note, confidence) or nil
--   corr                    left/right correlation (nil for mono): low = the sides differ
function HarmonyAnalyseFrame(mono, left, right, lead_pitch, cents)
    local OFF = PAD                      -- mono[OFF + i] = analysis sample i
    local x = {}
    for i = 1, M do x[i] = mono[OFF + i] end
    local rx = Rms(x, 1, M)
    if rx < SILENT then return nil end
    local res = {}
    if left and right then
        local c0 = OFF + (M - W) // 2
        res.corr = Corr(left, right, c0 + 1, c0 + W)
    end
    if not lead_pitch then return res end

    local sr_eff = SR * 2 ^ (-(cents or 0) / 1200)
    local d = ComputeCMND(x, TAU_MAX)
    if not d then return res end
    local T, dip = PeriodNear(d, PeriodOf(lead_pitch, cents), SEARCH_ST)
    if not T then return res end
    if 1 - dip >= MIN_CONF then
        res.lead_pitch, res.lead_conf = TauPitch(T, sr_eff), 1 - dip
    end

    local pi_, pf = math.floor(T), T - math.floor(T)
    local y = {}
    for i = 1, M do
        local k = OFF + i
        local j = k - pi_
        y[i] = mono[k] - (mono[j] * (1 - pf) + mono[j - 1] * pf)
    end
    res.ratio = Rms(y, 1, M) / (math.sqrt(2) * rx)
    local d2 = ComputeCMND(y, TAU_MAX)
    if not d2 then return res end
    local lo = math.floor(T * 2 ^ (-BAND_ST / 12))
    local hi = math.ceil(T * 2 ^ (BAND_ST / 12))
    local function skip(tau) return math.abs(12 * math.log(tau / T, 2)) < 0.5 end
    res.p_yin, res.c_yin = PickPitch(d2, lo, hi, skip, sr_eff, 'yin', 0)
    res.p_short, res.c_short = PickPitch(d2, lo, hi, skip, sr_eff, 'short', 0)
    return res
end

----------------------------------------------------------------------
-- Voting over the frames of one lead note
----------------------------------------------------------------------

function HarmonyVoteNew() return { n = 0, frames = 0, pcs = {}, exact = {} } end

-- Adds one frame's candidates (those passing HARMONY_RATIO / HARMONY_FLOOR and not the
-- lead pitch itself). Returns how many it added (0 = this frame found only the lead).
function HarmonyVoteAdd(v, res, lead_pitch)
    v.frames = v.frames + 1
    if not res or not res.ratio or res.ratio <= HARMONY_RATIO then return 0 end
    local added = 0
    for _, pc in ipairs({ { res.p_yin, res.c_yin }, { res.p_short, res.c_short } }) do
        local p, c = pc[1], pc[2]
        if p and c and c >= HARMONY_FLOOR and p ~= lead_pitch then
            v.n = v.n + 1
            v.pcs[p % 12] = (v.pcs[p % 12] or 0) + 1
            v.exact[p] = (v.exact[p] or 0) + 1
            added = added + 1
        end
    end
    return added
end

-- scale: set of pitch classes { [pc] = true } or nil (no key snap).
local function KeySnap(p, scale, exact)
    if not scale or scale[p % 12] then return p end
    local up, dn = scale[(p + 1) % 12], scale[(p - 1) % 12]
    if up and dn then
        local cu, cd = exact[p + 1] or 0, exact[p - 1] or 0
        if cu > cd then return p + 1 elseif cd > cu then return p - 1 end
        return p
    end
    if up then return p + 1 end
    if dn then return p - 1 end
    return p
end

-- The vote's reading: pitch, agreement (0..1, the share of votes for the winning pitch
-- class - 80%+ was right ~3 times in 4 in the measurements), or nil when nothing voted.
-- ref: the lead pitch, used to break a tie between octaves.
function HarmonyVoteResult(v, ref, scale)
    if v.n == 0 then return nil end
    local best_pc, best_c = nil, 0
    for pc, c in pairs(v.pcs) do
        if c > best_c or (c == best_c and pc < best_pc) then best_pc, best_c = pc, c end
    end
    local mode, mode_c
    for p, c in pairs(v.exact) do
        if p % 12 == best_pc and (not mode or c > mode_c
           or (c == mode_c and math.abs(p - ref) < math.abs(mode - ref))) then
            mode, mode_c = p, c
        end
    end
    return KeySnap(mode, scale, v.exact), best_c / v.n
end

----------------------------------------------------------------------
-- Spectral reading (optional second vote)
----------------------------------------------------------------------
-- The same question read the way a spectrogram shows it: the spectrum of a 128 ms window,
-- the lead's partials masked out, and the second voice = the pitch within an octave of the
-- lead whose partials add up loudest (Klapuri's weighted harmonic sum). Alone it finds the
-- note name more often than the cancellation but the octave less often; its votes pooled
-- with HarmonyAnalyseFrame's were right more often than either. The measured implementation
-- is 'mask 128ms max' in dev/tools/harmony_spectral_core.lua; the parity tool checks this
-- port against it.

local SPEC_L     = 2048                 -- window (128 ms at HARMONY_SR)
local NFFT       = SPECTRUM_NFFT        -- zero-padded (lib/reaper_spectrum.lua, load it first)
local DF         = SR / NFFT
local SPEC_F_TOP = 4000                 -- partials summed up to here
local SPEC_MAX_H = 20
local SPEC_STEP  = 0.1                  -- candidate step, semitones

-- Read HARMONY_SPEC_N samples (at HARMONY_SR) from t - HARMONY_SPEC_LEAD seconds.
HARMONY_SPEC_N    = SPEC_L
HARMONY_SPEC_LEAD = (SPEC_L // 2) / SR

-- Bins of a partial at f: +-1.5% (a quarter semitone), at least the window's main lobe.
local function BinRange(f, lobe)
    local w = math.max(lobe, 0.015 * f)
    return math.max(1, math.floor((f - w) / DF)), math.min(NFFT // 2, math.ceil((f + w) / DF))
end
local function PartialPeak(m, f, lobe)
    local a, b = BinRange(f, lobe)
    local best = 0
    for k = a, b do if m[k] > best then best = m[k] end end
    return best
end
local function HarmonicSum(m, f0, lobe)
    local s = 0
    for h = 1, math.min(SPEC_MAX_H, math.floor(SPEC_F_TOP / f0)) do
        s = s + (f0 + 20) / (h * f0 + 320) * PartialPeak(m, h * f0, lobe)
    end
    return s
end
local function SpecEnergy(m)
    local e = 0
    for k = math.floor(70 / DF), math.ceil(SPEC_F_TOP / DF) do e = e + m[k] * m[k] end
    return e
end

-- mono: HARMONY_SPEC_N samples, read as described at HARMONY_SPEC_N. lead_pitch: the
-- charted lead note there. Returns the second voice's MIDI pitch, or nil (silent, or nothing
-- left once the lead is masked).
function HarmonySpectralPitch(mono, lead_pitch, cents)
    cents = cents or 0
    local e = 0
    for i = 1, SPEC_L do e = e + mono[i] * mono[i] end
    if math.sqrt(e / SPEC_L) < SILENT then return nil end
    local hann = SpectrumHann(SPEC_L)
    local x = {}
    for i = 1, SPEC_L do x[i] = mono[i] * hann[i] end
    local m = SpectrumMagnitudes(x, SPEC_L)
    local lobe = 2 * SR / SPEC_L
    -- The lead near its chart: the best harmonic sum within +-1 st.
    local f_chart = 440 * 2 ^ ((lead_pitch - 69) / 12 + cents / 1200)
    local fl, bs = f_chart, -1
    for st = -1, 1 + 1e-9, 0.05 do
        local f = f_chart * 2 ^ (st / 12)
        local s = HarmonicSum(m, f, lobe)
        if s > bs then fl, bs = f, s end
    end
    local e_all = SpecEnergy(m)
    -- Mask the lead's partials (+-2% or the main lobe).
    local m2 = {}
    for k = 0, NFFT // 2 do m2[k] = m[k] end
    for h = 1, math.min(SPEC_MAX_H, math.floor(SPEC_F_TOP / fl)) do
        local a, b = BinRange(h * fl, math.max(lobe, 0.02 * h * fl))
        for k = a, b do m2[k] = 0 end
    end
    if e_all <= 0 or SpecEnergy(m2) <= 0 then return nil end
    -- The loudest harmonic sum within +-13 st, half a semitone around the lead skipped.
    local best, best_f = -1, nil
    local st = -BAND_ST
    while st <= BAND_ST + 1e-9 do
        if math.abs(st) >= 0.5 then
            local f = fl * 2 ^ (st / 12)
            if f >= MIN_F and f <= MAX_F then
                local s = HarmonicSum(m2, f, lobe)
                if s > best then best, best_f = s, f end
            end
        end
        st = st + SPEC_STEP
    end
    if not best_f or best <= 0 then return nil end
    return math.floor(69 + 12 * math.log(best_f / 440, 2) - cents / 100 + 0.5)
end

-- Adds one spectral reading to a vote (not counted as a frame: HarmonyVoteAdd already did).
-- Returns 1 when it voted.
function HarmonyVoteAddPitch(v, p, lead_pitch)
    if not p or p == lead_pitch then return 0 end
    v.n = v.n + 1
    v.pcs[p % 12] = (v.pcs[p % 12] or 0) + 1
    v.exact[p] = (v.exact[p] or 0) + 1
    return 1
end

-- Major or natural minor scale on a tonic (0 = C) as a pitch-class set.
local SCALE_STEPS = { [false] = { 0, 2, 4, 5, 7, 9, 11 }, [true] = { 0, 2, 3, 5, 7, 8, 10 } }
function HarmonyScale(tonic, minor)
    local s = {}
    for _, st in ipairs(SCALE_STEPS[minor and true or false]) do s[(tonic + st) % 12] = true end
    return s
end
