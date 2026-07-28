-- WAV writer algorithm test set. Run via run_wav_writer.lua.
-- Requires: Test (framework.lua), WriteMonoWAV16 (lib/reaper_wav_writer.lua).

-- Scratch path for round-trip tests -- REAPER's resource dir when running
-- for real, the OS temp dir (TEMP/TMP env var) when running standalone via
-- `lua` (os.tmpname() returns a root-of-drive path on Windows that needs
-- admin rights to write to -- not usable here).
local SCRATCH_PATH = (r.GetResourcePath and (r.GetResourcePath() .. '/wav_writer_test_scratch.wav'))
                   or ((os.getenv('TEMP') or os.getenv('TMP') or '.') .. '/wav_writer_test_scratch.wav')

local function read_file(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local raw = f:read('a')
    f:close()
    return raw
end

local function read_u32le(s, i)
    local b1, b2, b3, b4 = s:byte(i), s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function read_i16le(s, i)
    local lo, hi = s:byte(i), s:byte(i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    return v
end

----------------------------------------------------------------------

Test.section('WriteMonoWAV16 -- structure')

Test.it('writes a byte-correct RIFF/WAVE/fmt/data header', function()
    local samples = {}
    for i = 1, 1000 do samples[i] = math.sin(i * 0.1) end
    local ok = WriteMonoWAV16(samples, 44100, SCRATCH_PATH)
    Test.expect(ok == true, 'expected write to succeed')

    local raw = read_file(SCRATCH_PATH)
    Test.expect(raw ~= nil, 'expected file to be readable')
    Test.expect(raw:sub(1, 4) == 'RIFF', 'missing RIFF tag')
    Test.expect(raw:sub(9, 12) == 'WAVE', 'missing WAVE tag')
    Test.expect(raw:sub(13, 16) == 'fmt ', 'missing fmt tag')
    Test.expect(raw:sub(37, 40) == 'data', 'missing data tag')

    local expected_data_size = 1000 * 2  -- mono 16-bit
    Test.expect(read_u32le(raw, 41) == expected_data_size,
        'data chunk size field mismatch: got ' .. read_u32le(raw, 41))
    Test.expect(#raw == 44 + expected_data_size,
        'total file size mismatch: got ' .. #raw)
    Test.expect(read_u32le(raw, 5) == #raw - 8,
        'RIFF chunk size field should be file size minus 8')
end)

Test.it('file size matches sample count exactly for a different length', function()
    local samples = {}
    for i = 1, 250 do samples[i] = 0.5 end
    Test.expect(WriteMonoWAV16(samples, 22050, SCRATCH_PATH), 'expected write to succeed')
    local raw = read_file(SCRATCH_PATH)
    Test.expect(#raw == 44 + 250 * 2, 'expected 44 + 500 bytes, got ' .. #raw)
end)

----------------------------------------------------------------------

Test.section('WriteMonoWAV16 -- normalization / clipping')

Test.it('a loud multi-voice-style buffer (amplitude > 1.0) never clips', function()
    local samples = {}
    for i = 1, 2000 do
        -- simulate several summed Karplus-Strong voices exceeding -1..1
        samples[i] = 3.5 * math.sin(i * 0.05) + 1.5 * math.sin(i * 0.13)
    end
    Test.expect(WriteMonoWAV16(samples, 44100, SCRATCH_PATH), 'expected write to succeed')
    local raw = read_file(SCRATCH_PATH)
    local max_abs = 0
    for i = 1, 2000 do
        local v = read_i16le(raw, 44 + (i - 1) * 2 + 1)
        Test.expect(v >= -32768 and v <= 32767, 'sample ' .. i .. ' out of int16 range: ' .. v)
        if math.abs(v) > max_abs then max_abs = math.abs(v) end
    end
    -- peak headroom is 0.9 of full scale -- loudest sample should land near
    -- (not at, not far below) 0.9 * 32767
    Test.expect(max_abs > 25000 and max_abs <= 29491,
        'expected peak near the 0.9 headroom target, got ' .. max_abs)
end)

Test.it('an all-silent buffer writes without a divide-by-zero error', function()
    local samples = {}
    for i = 1, 100 do samples[i] = 0.0 end
    local ok = WriteMonoWAV16(samples, 44100, SCRATCH_PATH)
    Test.expect(ok == true, 'expected silent buffer to write successfully')
    local raw = read_file(SCRATCH_PATH)
    for i = 1, 100 do
        Test.expect(read_i16le(raw, 44 + (i - 1) * 2 + 1) == 0, 'expected silence at sample ' .. i)
    end
end)

----------------------------------------------------------------------

Test.section('WriteMonoWAV16 -- error cases')

Test.it('empty buffer returns nil, "empty buffer"', function()
    local ok, err = WriteMonoWAV16({}, 44100, SCRATCH_PATH)
    Test.expect(ok == nil and err == 'empty buffer', 'expected nil, "empty buffer"')
end)

Test.it('nil buffer returns nil, "empty buffer"', function()
    local ok, err = WriteMonoWAV16(nil, 44100, SCRATCH_PATH)
    Test.expect(ok == nil and err == 'empty buffer', 'expected nil, "empty buffer"')
end)

Test.it('unwritable path returns nil, err', function()
    local ok, err = WriteMonoWAV16({ 0.1, 0.2 }, 44100, '/this/path/does/not/exist/x.wav')
    Test.expect(ok == nil and err ~= nil, 'expected nil, err for an unwritable path')
end)

os.remove(SCRATCH_PATH)
