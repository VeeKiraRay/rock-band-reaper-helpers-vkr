-- Harmony detect parity - offline, pure Lua (+ ffmpeg unless cached), no REAPER.
--
-- Checks that lib/reaper_harmony_detect.lua (what the Pitch > Tuner Harmony readout runs)
-- gives the same answers as dev/tools/harmony_audio_core.lua and
-- dev/tools/harmony_spectral_core.lua (the methods the 2026-11 harmony probe rounds
-- measured), frame by frame, on the decrypted official moggs. The shipped accuracy numbers
-- only apply while this passes.
--
--   lua dev/tools/harmony_detect_parity_offline.lua [shortname ...]
--
-- Default songs: a few with harmonies. Inputs and env: see harmony_audio_core.lua
-- (HAP_CACHE advised).
-- Compares, at 3 points of every charted lead note: the residual ratio, the lead heard near
-- the chart, both second-voice candidates once filtered as the vote filters them, the
-- left/right correlation, the spectral reading (HarmonySpectralPitch vs
-- harmony_spectral_core.lua's 'mask 128ms max'), and the voted reading per note.

local _dir  = (arg[0]:match('^(.+[\\/])') or './')
local _root = _dir .. '../../'
dofile(_dir .. 'smf_reader.lua')
dofile(_root .. 'lib/reaper_dsp.lua')
dofile(_root .. 'lib/reaper_spectrum.lua')
dofile(_root .. 'lib/reaper_harmony_detect.lua')
local H = dofile(_dir .. 'harmony_audio_core.lua')
local SP = dofile(_dir .. 'harmony_spectral_core.lua')(H.SR, false)
local SP_MI
for i, me in ipairs(SP.METHODS) do if me.name == 'mask 128ms max' then SP_MI = i end end
assert(SP_MI, 'the spectral core no longer has the measured method')

local SONGS = {}
for i = 1, #arg do SONGS[arg[i]] = true end
if #arg == 0 then
    for _, s in ipairs({ 'californication', 'amaranth', 'webuiltthiscity', 'takeonme', 'otherside' }) do
        SONGS[s] = true
    end
end

local SR = H.SR
assert(SR == HARMONY_SR, 'the probe core and the lib must analyse at the same rate')

-- The lib's frame from the cached pcm: HARMONY_FRAME_N samples from t - HARMONY_FRAME_LEAD.
local function LibFrame(pcm, t)
    local n = HARMONY_FRAME_N
    local start = math.floor(t * SR) - math.floor(HARMONY_FRAME_LEAD * SR + 0.5) + 1
    local m, l, rr = {}, {}, {}
    local total = #pcm // 4
    for i = 1, n do
        local k = start + i - 1
        local a, b = 0, 0
        if k >= 1 and k <= total then a, b = string.unpack('<i2i2', pcm, (k - 1) * 4 + 1) end
        a, b = a / 32768, b / 32768
        l[i], rr[i], m[i] = a, b, (a + b) / 2
    end
    return m, l, rr
end

-- The lib's spectral window: HARMONY_SPEC_N samples from t - HARMONY_SPEC_LEAD.
local function LibSpecFrame(pcm, t)
    local start = math.floor(t * SR) - math.floor(HARMONY_SPEC_LEAD * SR + 0.5) + 1
    local m, total = {}, #pcm // 4
    for i = 1, HARMONY_SPEC_N do
        local k = start + i - 1
        local a, b = 0, 0
        if k >= 1 and k <= total then a, b = string.unpack('<i2i2', pcm, (k - 1) * 4 + 1) end
        m[i] = (a + b) / 65536
    end
    return m
end

-- A candidate as the vote sees it: kept only at the floor and off the lead.
local function Kept(p, c, lead)
    if p and c and c >= HARMONY_FLOOR and p ~= lead then return p end
    return nil
end

local frames, mism, notes, note_mism = 0, {}, 0, 0
local function Bad(what, sn, t, a, b)
    mism[what] = (mism[what] or 0) + 1
    if mism[what] <= 3 then
        print(('  MISMATCH %-10s %s at %.3f s: probe %s, lib %s'):format(what, sn, t, tostring(a), tostring(b)))
    end
end

for _, mogg in ipairs(SmfListFiles(_root .. H.FOLDER_REL, 'decrypted[\\/][^\\/]+%.mogg$')) do
    local sn = mogg:match('([^\\/]+)%.[Mm][Oo][Gg][Gg]$')
    if SONGS[sn] then
        local song_dir = mogg:match('^(.*[\\/])decrypted[\\/]')
        local dta = H.read_all(song_dir:match('^(.*[\\/])[^\\/]+[\\/]$') .. 'songs.dta')
        local info = dta and H.DtaInfo(dta, sn)
        local song = SmfReadFile(song_dir .. sn .. '.mid')
        local pcm = info and song and H.Decode(mogg, info, sn)
        if not pcm then
            print('skipped ' .. sn)
        else
            SP.SetTotal(#pcm // 4)
            local map = SmfTempoMap(song)
            local lead = H.PitchedNotes(song, map, SmfFindTrack(song, 'HARM1'))
            for _, n in ipairs(lead) do
                if n.e - n.s >= 0.15 then
                    local vp, vl = HarmonyVoteNew(), HarmonyVoteNew()
                    for _, f in ipairs({ 0.25, 0.5, 0.75 }) do
                        local t = n.s + f * (n.e - n.s)
                        local rp = H.Analyse(pcm, t, n.pitch, info.cents, 2)
                        local m, l, rr = LibFrame(pcm, t)
                        local rl = HarmonyAnalyseFrame(m, l, rr, n.pitch, info.cents)
                        frames = frames + 1
                        if (rp == nil) ~= (rl == nil) then
                            Bad('silence', sn, t, rp ~= nil, rl ~= nil)
                        elseif rp then
                            if (rp.ratio == nil) ~= (rl.ratio == nil)
                               or (rp.ratio and math.abs(rp.ratio - rl.ratio) > 1e-9) then
                                Bad('ratio', sn, t, rp.ratio, rl.ratio)
                            end
                            local lp = rp.lead_cents and n.pitch and rl.lead_pitch
                            if (rp.lead_cents ~= nil) ~= (rl.lead_pitch ~= nil) then Bad('lead', sn, t, rp.lead_cents, lp) end
                            if Kept(rp.p2b, rp.p2b_c, n.pitch) ~= Kept(rl.p_yin, rl.c_yin, n.pitch) then
                                Bad('yin', sn, t, rp.p2b, rl.p_yin)
                            end
                            if Kept(rp.p2bs, rp.p2bs_c, n.pitch) ~= Kept(rl.p_short, rl.c_short, n.pitch) then
                                Bad('short', sn, t, rp.p2bs, rl.p_short)
                            end
                            if (rp.corr == nil) ~= (rl.corr == nil)
                               or (rp.corr and math.abs(rp.corr - rl.corr) > 1e-9) then
                                Bad('corr', sn, t, rp.corr, rl.corr)
                            end
                            -- Votes: the probe's candidates fed through the lib's vote.
                            HarmonyVoteAdd(vp, rp.ratio and { ratio = rp.ratio, p_yin = rp.p2b, c_yin = rp.p2b_c,
                                p_short = rp.p2bs, c_short = rp.p2bs_c }, n.pitch)
                            HarmonyVoteAdd(vl, rl, n.pitch)
                            local spf = SP.SpectralFrame(pcm, t, n.pitch, info.cents)
                            local sp_p = spf and spf[SP_MI] and spf[SP_MI].p
                            local sl_p = HarmonySpectralPitch(LibSpecFrame(pcm, t), n.pitch, info.cents)
                            if sp_p ~= sl_p then Bad('spectral', sn, t, sp_p, sl_p) end
                            HarmonyVoteAddPitch(vp, sp_p, n.pitch)
                            HarmonyVoteAddPitch(vl, sl_p, n.pitch)
                        end
                    end
                    notes = notes + 1
                    local a, b = HarmonyVoteResult(vp, n.pitch), HarmonyVoteResult(vl, n.pitch)
                    if a ~= b then note_mism = note_mism + 1 end
                end
            end
            print(('%-26s done'):format(sn))
        end
    end
end

local total = 0
for _, c in pairs(mism) do total = total + c end
print(('Frames compared: %d, mismatching fields: %d; notes compared: %d, different readings: %d'):format(
    frames, total, notes, note_mism))
for k, c in pairs(mism) do print(('  %-10s %d'):format(k, c)) end
print((total == 0 and note_mism == 0) and 'PARITY OK' or 'PARITY FAILED')
