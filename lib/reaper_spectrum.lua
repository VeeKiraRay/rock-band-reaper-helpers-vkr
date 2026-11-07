-- Magnitude spectrum of a short window - pure Lua, no r / ctx / S.
--
-- Shared by the spectral readers: lib/reaper_harmony_detect.lua (the Tuner's Harmony
-- readout) and lib/reaper_chord_detect.lua (Keys > Tuner chords). Pure so the same code
-- runs offline, where the parity tools check each port against the method it was measured
-- with - change the arithmetic here and both parity tools must still pass.
--
-- One fixed size: SPECTRUM_NFFT points, a window of up to that many samples zero-padded.
-- Bins 0 .. SPECTRUM_NFFT / 2; bin k is k * sr / SPECTRUM_NFFT Hz.

SPECTRUM_NFFT = 4096

local NFFT = SPECTRUM_NFFT
local REV, COS, SIN               -- built on first use
local HANN = {}                   -- [L] = window table

local function Tables()
    if REV then return end
    REV, COS, SIN = {}, {}, {}
    local bits = math.floor(math.log(NFFT, 2) + 0.5)
    for i = 0, NFFT - 1 do
        local rv, x = 0, i
        for _ = 1, bits do rv = rv * 2 + (x % 2); x = x // 2 end
        REV[i] = rv
    end
    for k = 0, NFFT // 2 - 1 do
        COS[k] = math.cos(-2 * math.pi * k / NFFT)
        SIN[k] = math.sin(-2 * math.pi * k / NFFT)
    end
end

-- Hann window of L samples: w[i] = 0.5 - 0.5 cos(2 pi (i - 1) / (L - 1)), i = 1 .. L.
function SpectrumHann(L)
    local w = HANN[L]
    if not w then
        w = {}
        for i = 1, L do w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i - 1) / (L - 1)) end
        HANN[L] = w
    end
    return w
end

-- x[1 .. L] (already windowed, L <= SPECTRUM_NFFT) -> magnitudes m[0 .. SPECTRUM_NFFT / 2].
-- Radix-2 decimation in time.
function SpectrumMagnitudes(x, L)
    Tables()
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
