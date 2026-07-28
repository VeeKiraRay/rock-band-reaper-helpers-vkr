-- Generic mono 16-bit PCM WAV writer. Pure Lua (io/string/math only -- no
-- reaper.*) -- fully unit-testable standalone, safe to dofile from a
-- Lua-only context (see dev/tests/run_wav_writer.lua).
--
-- Deliberately generic to any float sample buffer, not specific to
-- lib/reaper_karplus_strong.lua -- a future different synthesis source
-- (or a different instrument's voice generator) reuses this file unchanged.
--
-- Byte-packed manually via string.char (not string.pack) for both the
-- header and sample data: no assumption about the exact Lua version REAPER
-- embeds on a given user's machine. This codebase already relies on
-- bitwise `|` elsewhere (confirmed working), but string.pack has no
-- existing precedent here to lean on, so this avoids introducing that risk.

local function u16le(v)
    if v < 0 then v = v + 65536 end
    local lo = v % 256
    local hi = (v - lo) / 256
    return string.char(lo, hi)
end

local function u32le(v)
    local b1 = v % 256; v = (v - b1) / 256
    local b2 = v % 256; v = (v - b2) / 256
    local b3 = v % 256; v = (v - b3) / 256
    local b4 = v % 256
    return string.char(b1, b2, b3, b4)
end

local function i16le(v)
    if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
    return u16le(v)
end

----------------------------------------------------------------------
-- Write `samples` (a flat table of floats, any range) as a mono 16-bit
-- PCM WAV at `path`. Peak-normalizes first (scales so the loudest sample
-- sits at ~90% of full scale) so multi-voice mixes never clip regardless
-- of how many were summed together.
-- Returns true, or nil, err ('empty buffer' | file-open error from io.open).
----------------------------------------------------------------------
local PEAK_HEADROOM = 0.9

function WriteMonoWAV16(samples, sample_rate, path)
    if not samples or #samples == 0 then return nil, 'empty buffer' end

    local peak = 0.0
    for i = 1, #samples do
        local a = math.abs(samples[i])
        if a > peak then peak = a end
    end
    local scale = (peak > 0) and (PEAK_HEADROOM / peak) or 1.0

    local sample_bytes = {}
    for i = 1, #samples do
        sample_bytes[i] = i16le(math.floor(samples[i] * scale * 32767 + 0.5))
    end
    local data = table.concat(sample_bytes)
    local data_size = #data

    local channels, bits = 1, 16
    local byte_rate = sample_rate * channels * (bits // 8)
    local block_align = channels * (bits // 8)

    local header = table.concat({
        'RIFF', u32le(36 + data_size), 'WAVE',
        'fmt ', u32le(16), u16le(1), u16le(channels), u32le(sample_rate),
        u32le(byte_rate), u16le(block_align), u16le(bits),
        'data', u32le(data_size),
    })

    local f, err = io.open(path, 'wb')
    if not f then return nil, err end
    f:write(header)
    f:write(data)
    f:close()
    return true
end
