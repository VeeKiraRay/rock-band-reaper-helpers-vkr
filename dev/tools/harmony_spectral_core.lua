-- Harmony spectral core - offline, pure Lua, no REAPER.
--
-- The spectrogram-style second-voice readings measured in the 2026-11 harmony probe rounds,
-- shared by those probes and by dev/tools/harmony_detect_parity_offline.lua (which checks
-- lib/reaper_harmony_detect.lua's HarmonySpectralPitch against 'mask 128ms max' here).
-- The same frames as the time-domain method (harmony_audio_core.lua):
--
--   1. Spectrum of a longer window (64 or 128 ms, Hann, zero-padded to 4096 points).
--   2. The lead's exact pitch near its charted note: the best harmonic sum within +-1 st.
--   3. Remove the lead's partials: 'mask' zeroes them; 'smooth' takes away only what the
--      lead's neighbouring partials predict, so a harmony partial on the same frequency
--      keeps its excess (Klapuri's spectral smoothness); 'comb' first cancels the lead in
--      time (y[n] = x[n] - x[n-T] over the long window), then masks what vibrato left.
--   4. The second voice: the pitch within +-13 st of the lead whose harmonic sum is
--      largest ('max'), or the highest pitch nearly as large ('high', against readings an
--      octave too low - every second partial of the true voice also fits there).
--
--   local SP = dofile('harmony_spectral_core.lua')(sr, full)
--   SP.SetTotal(#pcm // 4); SP.SpectralFrame(pcm, t, lead_pitch, cents)
--
-- full = false: the two methods kept after round 1 ('mask' and 'comb', 128 ms, 'max');
-- true: every window / removal / rule (round 1). pcm is the probes' cached 16-bit stereo.
-- Change nothing here without re-running the parity tool: the shipped port must match it.

return function(SR, FULL)
    local NFFT         = 4096
    local DF           = SR / NFFT
    local F_TOP        = 4000                -- partials summed up to here
    local MAX_H        = 20
    local BAND_ST      = 13
    local STEP_ST      = 0.1                 -- candidate pitch step
    local HIGH_SHARE   = 0.85                -- 'high' rule: within this share of the best sum
    local SILENT       = 1e-3

    ----------------------------------------------------------------------
    -- FFT (radix 2, magnitudes of bins 0 .. N/2)
    ----------------------------------------------------------------------

    local REV, COS, SIN = {}, {}, {}
    do
        local bits = math.floor(math.log(NFFT, 2) + 0.5)
        for i = 0, NFFT - 1 do
            local r, x = 0, i
            for _ = 1, bits do r = r * 2 + (x % 2); x = x // 2 end
            REV[i] = r
        end
        for k = 0, NFFT // 2 - 1 do
            COS[k] = math.cos(-2 * math.pi * k / NFFT)
            SIN[k] = math.sin(-2 * math.pi * k / NFFT)
        end
    end

    local function Magnitudes(x, L)     -- x[1..L], already windowed
        local xr, xi = {}, {}
        for i = 0, NFFT - 1 do xr[i], xi[i] = 0, 0 end
        for i = 1, L do xr[REV[i - 1]] = x[i] end
        local size = 2
        while size <= NFFT do
            local half, step = size // 2, NFFT // size
            for st = 0, NFFT - 1, size do
                local k = 0
                for j = st, st + half - 1 do
                    local l = j + half
                    local wr, wi = COS[k], SIN[k]
                    local tr = wr * xr[l] - wi * xi[l]
                    local ti = wr * xi[l] + wi * xr[l]
                    xr[l], xi[l] = xr[j] - tr, xi[j] - ti
                    xr[j], xi[j] = xr[j] + tr, xi[j] + ti
                    k = k + step
                end
            end
            size = size * 2
        end
        local m = {}
        for b = 0, NFFT // 2 do m[b] = math.sqrt(xr[b] * xr[b] + xi[b] * xi[b]) end
        return m
    end

    local HANN = {}
    local function Hann(L)
        if not HANN[L] then
            local w = {}
            for i = 1, L do w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i - 1) / (L - 1)) end
            HANN[L] = w
        end
        return HANN[L]
    end

    ----------------------------------------------------------------------
    -- Harmonic sums
    ----------------------------------------------------------------------

    local function Hz(p, cents) return 440 * 2 ^ ((p - 69) / 12 + cents / 1200) end
    local function Midi(f, cents) return math.floor(69 + 12 * math.log(f / 440, 2) - cents / 100 + 0.5) end

    -- Bin range of partial frequency f: +-1.5% (a quarter semitone) and at least the window's
    -- main lobe.
    local function Range(f, lobe)
        local w = math.max(lobe, 0.015 * f)
        return math.max(1, math.floor((f - w) / DF)), math.min(NFFT // 2, math.ceil((f + w) / DF))
    end
    local function Peak(m, f, lobe)
        local a, b = Range(f, lobe)
        local best = 0
        for k = a, b do if m[k] > best then best = m[k] end end
        return best
    end
    -- Klapuri's harmonic sum: partial h weighted (f0 + 20) / (h f0 + 320).
    local function Salience(m, f0, lobe)
        local s = 0
        for h = 1, math.min(MAX_H, math.floor(F_TOP / f0)) do
            s = s + (f0 + 20) / (h * f0 + 320) * Peak(m, h * f0, lobe)
        end
        return s
    end

    local function Energy(m)
        local e = 0
        for k = math.floor(70 / DF), math.ceil(F_TOP / DF) do e = e + m[k] * m[k] end
        return e
    end

    -- The lead's partials removed from a copy of m. mode 'mask' | 'smooth'.
    local function RemoveLead(m, fl, lobe, mode)
        local out = {}
        for k = 0, NFFT // 2 do out[k] = m[k] end
        local nh = math.min(MAX_H, math.floor(F_TOP / fl))
        local amp = {}
        for h = 1, nh do amp[h] = Peak(m, h * fl, lobe) end
        for h = 1, nh do
            local a, b = Range(h * fl, math.max(lobe, 0.02 * h * fl))
            local keep = 0
            if mode == 'smooth' and amp[h] > 0 then
                local s, n = amp[h], 1
                if amp[h - 1] then s, n = s + amp[h - 1], n + 1 end
                if amp[h + 1] then s, n = s + amp[h + 1], n + 1 end
                local pred = math.min(amp[h], s / n)
                keep = 1 - pred / amp[h]
            end
            for k = a, b do out[k] = out[k] * keep end
        end
        return out
    end

    -- The second voice in m2: candidates every STEP_ST within +-BAND_ST of the lead, skipping
    -- half a semitone around it. Returns pitch_max, pitch_high, peakiness.
    local function SecondVoice(m2, fl, lobe, cents)
        local best, best_f, sum, n = -1, nil, 0, 0
        local cands = {}
        local st = -BAND_ST
        while st <= BAND_ST + 1e-9 do
            if math.abs(st) >= 0.5 then
                local f = fl * 2 ^ (st / 12)
                if f >= 70 and f <= 1000 then
                    local s = Salience(m2, f, lobe)
                    cands[#cands + 1] = { f = f, s = s }
                    sum, n = sum + s, n + 1
                    if s > best then best, best_f = s, f end
                end
            end
            st = st + STEP_ST
        end
        if not best_f or best <= 0 then return nil end
        -- 'high': the highest local maximum within HIGH_SHARE of the best.
        local hi_f = best_f
        for i = #cands, 1, -1 do
            local c = cands[i]
            local l, r = cands[i - 1], cands[i + 1]
            if c.s >= HIGH_SHARE * best and (not l or c.s >= l.s) and (not r or c.s >= r.s) then
                hi_f = c.f
                break
            end
        end
        return Midi(best_f, cents), Midi(hi_f, cents), best / (sum / n)
    end

    ----------------------------------------------------------------------
    -- One frame, every spectral method
    ----------------------------------------------------------------------

    local LENS = FULL and { 1024, 2048 } or { 2048 }
    local METHODS = {}   -- filled below: { name, L, removal, rule }
    for _, L in ipairs(LENS) do
        for _, rem in ipairs(FULL and { 'mask', 'smooth', 'comb' } or { 'mask', 'comb' }) do
            for _, rule in ipairs(FULL and { 'max', 'high' } or { 'max' }) do
                METHODS[#METHODS + 1] = { name = ('%s %dms %s'):format(rem, L * 1000 // SR, rule),
                                          L = L, rem = rem, rule = rule }
            end
        end
    end

    local TOTAL_SAMPLES
    local function ReadMono(pcm, s, n)
        local out = {}
        for i = 1, n do
            local k = s + i - 1
            local a, b = 0, 0
            if k >= 1 and k <= TOTAL_SAMPLES then a, b = string.unpack('<i2i2', pcm, (k - 1) * 4 + 1) end
            out[i] = (a + b) / 65536
        end
        return out
    end

    -- Returns { [method index] = { p = pitch, ratio = energy left after the lead } } or nil.
    local function SpectralFrame(pcm, t, lead_pitch, cents)
        local res = {}
        local center = math.floor(t * SR) + 1
        local pad = math.floor(SR / 70) + 2
        for _, L in ipairs(LENS) do
            local s0 = center - L // 2
            local raw = ReadMono(pcm, s0 - pad, L + pad)       -- raw[pad + i] = sample i
            local e = 0
            for i = 1, L do e = e + raw[pad + i] ^ 2 end
            if math.sqrt(e / L) < SILENT then return nil end
            local w = Hann(L)
            local x = {}
            for i = 1, L do x[i] = raw[pad + i] * w[i] end
            local m = Magnitudes(x, L)
            local lobe = 2 * SR / L                             -- Hann main lobe half-width, Hz
            -- The lead near its chart: best harmonic sum within +-1 st, 0.05 st steps.
            local f_chart = Hz(lead_pitch, cents)
            local fl, bs = f_chart, -1
            for st = -1, 1 + 1e-9, 0.05 do
                local f = f_chart * 2 ^ (st / 12)
                local s = Salience(m, f, lobe)
                if s > bs then fl, bs = f, s end
            end
            local e_all = Energy(m)
            -- Time-domain cancellation over the long window for 'comb'.
            local mc
            do
                local T = SR / fl
                local pi_, pf = math.floor(T), T - math.floor(T)
                local y = {}
                for i = 1, L do
                    local k = pad + i
                    y[i] = (raw[k] - (raw[k - pi_] * (1 - pf) + raw[k - pi_ - 1] * pf)) * w[i]
                end
                mc = Magnitudes(y, L)
            end
            local cache = {}
            for mi, me in ipairs(METHODS) do
                if me.L == L then
                    local key = me.rem
                    if not cache[key] then
                        local m2
                        if me.rem == 'comb' then m2 = RemoveLead(mc, fl, lobe, 'mask')
                        else m2 = RemoveLead(m, fl, lobe, me.rem) end
                        local pmax, phigh, peak = SecondVoice(m2, fl, lobe, cents)
                        -- comb doubles the level of what it keeps: compare like with like
                        local ratio = e_all > 0 and math.sqrt(Energy(m2) / e_all) / (me.rem == 'comb' and 2 or 1) or 0
                        cache[key] = { pmax = pmax, phigh = phigh, peak = peak, ratio = ratio }
                    end
                    local c = cache[key]
                    res[mi] = { p = me.rule == 'max' and c.pmax or c.phigh, ratio = c.ratio, peak = c.peak }
                end
            end
        end
        return res
    end

    return { SpectralFrame = SpectralFrame, METHODS = METHODS, LENS = LENS,
             SetTotal = function(n) TOTAL_SAMPLES = n end }
end
