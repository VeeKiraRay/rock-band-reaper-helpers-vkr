-- Shared core of the harmony audio tools - offline, pure Lua + ffmpeg, no REAPER.
--
-- The time-domain method measured in the 2026-11 harmony probe rounds (rounds 1-5, then how
-- it reads in the Pitch Tuner). Loaded by those probes and by
-- dev/tools/harmony_detect_parity_offline.lua:
--
--   local H = dofile(_root .. 'dev/tools/harmony_audio_core.lua')
--
-- Holds the decoding of the decrypted official moggs (vocal channels from songs.dta, via
-- ffmpeg), the chart readers, and the frame analysis: lead cancellation y[n] = x[n] - x[n - T]
-- and the pitch searches on what is left. It is the reference for
-- lib/reaper_harmony_detect.lua, which must reproduce it frame by frame (the parity tool).
--
-- Callers must have loaded dev/tools/smf_reader.lua and lib/reaper_dsp.lua first.
-- Env: FFMPEG (default 'ffmpeg' on PATH), TEMP for temp files, HAP_CACHE=<folder> to keep the
-- decoded audio between runs (~15 MB a song; derived commercial audio, keep it outside the repo).

local H = {}

H.FOLDER_REL = '_external_docs/reference_songs'
local FFMPEG = os.getenv('FFMPEG') or 'ffmpeg'
local TMP    = (os.getenv('TEMP') or os.getenv('TMP') or '.'):gsub('[\\/]$', '') .. '\\'

local SR        = 16000
local WIN_S     = 0.040
local MIN_F     = 70
local MAX_F     = 1000
local THRESH    = 0.15
local MIN_CONF  = 0.5
local SILENT    = 1e-3     -- frame rms below this is skipped
local SEARCH_ST = 2        -- lead period searched within +-2 semitones of the chart
H.SR, H.WIN_S, H.THRESH, H.MIN_CONF = SR, WIN_S, THRESH, MIN_CONF

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

function H.inc(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
function H.pct(a, b) return b > 0 and ('%5.1f%%'):format(100 * a / b) or '   - ' end
function H.header(s) print(''); print(('='):rep(78)); print(s); print(('='):rep(78)) end
function H.quant(a, p)
    if #a == 0 then return 0 end
    table.sort(a)
    return a[math.max(1, math.min(#a, math.floor(p * #a + 0.5)))]
end
function H.qline(a)
    if #a == 0 then return '(none)' end
    return ('n %6d  10%% %.3f  median %.3f  90%% %.3f'):format(#a, H.quant(a, 0.1), H.quant(a, 0.5), H.quant(a, 0.9))
end
function H.share_above(a, x)
    if #a == 0 then return 0 end
    local n = 0
    for _, v in ipairs(a) do if v > x then n = n + 1 end end
    return n / #a
end
function H.read_all(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local d = f:read('a')
    f:close()
    return d
end
local read_all = H.read_all

----------------------------------------------------------------------
-- songs.dta: vocal channels, pans, tuning, key
----------------------------------------------------------------------

function H.DtaInfo(dta, sn)
    local text = '\n' .. dta:gsub(';[^\n]*', '')
    local esc = sn:gsub('%p', '%%%0')
    local s = text:find('\n%(' .. esc .. '%s')
    if not s then return nil, 'no dta entry' end
    local e = text:find('\n%(', s + 1) or #text
    local entry = text:sub(s, e)
    local tracks = entry:match('%(tracks(.-)%(pans')
    if not tracks then return nil, 'no tracks block' end
    local list = tracks:match('%(vocals%s*%(([%d%s]+)%)') or tracks:match('%(vocals%s+(%d+)%s*%)')
    if not list then return nil, 'no vocal channels' end
    local ch = {}
    for d in list:gmatch('%d+') do ch[#ch + 1] = tonumber(d) end
    local pans = {}
    local pl = entry:match('%(pans%s*%(([^%)]*)%)') or ''
    for v in pl:gmatch('-?[%d%.]+') do pans[#pans + 1] = tonumber(v) end
    local cents = tonumber(entry:match('%(tuning_offset_cents%s+(-?[%d%.]+)%s*%)') or '0') or 0
    local tonic = tonumber(entry:match('%(vocal_tonic_note%s+(%d+)%s*%)') or '')
    local tonality = tonumber(entry:match('%(song_tonality%s+(%d+)%s*%)') or '')
    return { ch = ch, pans = pans, cents = cents, tonic = tonic and tonic % 12, minor = tonality == 1 }
end

----------------------------------------------------------------------
-- Decode: mogg -> 16 kHz stereo s16le of the vocal channels
----------------------------------------------------------------------

local CACHE = os.getenv('HAP_CACHE')
if CACHE then CACHE = CACHE:gsub('[\\/]$', '') .. '\\' end

function H.Decode(mogg_path, info, sn)
    local mono = #info.ch == 1
    if CACHE then
        local pcm = read_all(CACHE .. sn .. '.s16')
        if pcm and #pcm >= 4 * SR then return pcm, mono end
    end
    local data = read_all(mogg_path)
    if not data or #data < 8 then return nil, 'cannot read mogg' end
    local off = string.unpack('<I4', data, 5)
    if data:sub(off + 1, off + 4) ~= 'OggS' then return nil, 'no OggS at header offset' end
    local ogg, raw = TMP .. 'hap_' .. sn .. '.ogg', TMP .. 'hap_' .. sn .. '.raw'
    local f = assert(io.open(ogg, 'wb'))
    f:write(data:sub(off + 1))
    f:close()
    data = nil

    local left, right = {}, {}
    for _, c in ipairs(info.ch) do
        local p = info.pans[c + 1] or 0
        if p <= 0.01 then left[#left + 1] = c end
        if p >= -0.01 then right[#right + 1] = c end
    end
    local function expr(list)
        local g = 1 / #list
        local parts = {}
        for _, c in ipairs(list) do parts[#parts + 1] = ('%.4f*c%d'):format(g, c) end
        return table.concat(parts, '+')
    end
    if CACHE then
        os.execute(('mkdir "%s" 2>nul'):format(CACHE:sub(1, -2)))
        raw = CACHE .. sn .. '.s16'
    end
    local cmd = ('"%s" -v error -y -i "%s" -filter_complex "pan=stereo|c0=%s|c1=%s" -ar %d -f s16le "%s"')
        :format(FFMPEG, ogg, expr(left), expr(right), SR, raw)
    os.execute('"' .. cmd .. '"')
    os.remove(ogg)
    local pcm = read_all(raw)
    if not CACHE then os.remove(raw) end
    if not pcm or #pcm < 4 * SR then return nil, 'ffmpeg produced no audio' end
    return pcm, mono
end

-- Samples [s, s + n - 1] (1-based sample index) as mono / left / right tables.
local function Window(pcm, s, n)
    local m, l, r_ = {}, {}, {}
    local total = #pcm // 4
    for i = 1, n do
        local k = s + i - 1
        local a, b = 0, 0
        if k >= 1 and k <= total then a, b = string.unpack('<i2i2', pcm, (k - 1) * 4 + 1) end
        a, b = a / 32768, b / 32768
        l[i], r_[i], m[i] = a, b, (a + b) / 2
    end
    return m, l, r_
end

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

----------------------------------------------------------------------
-- Chart
----------------------------------------------------------------------

-- Pitched notes of a vocal part in seconds ('#' lyrics dropped as unpitched, unless
-- keep_unpitched: then every vocal-range note, for "is the singer sounding here").
function H.PitchedNotes(song, map, trk, keep_unpitched)
    if not trk then return {} end
    local lyric = {}
    for _, t in ipairs(trk.texts) do
        if (t.type == 1 or t.type == 5) and not t.text:match('^%[') then lyric[t.tick] = t.text end
    end
    local out = {}
    for _, n in ipairs(trk.notes) do
        local l = lyric[n.tick]
        if n.pitch >= 36 and n.pitch <= 84 and (keep_unpitched or not (l and l:find('#', 1, true))) then
            local s = SmfTickToSec(map, song.tpqn, n.tick)
            out[#out + 1] = { pitch = n.pitch, s = s, e = SmfTickToSec(map, song.tpqn, n.tick + n.len) }
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

function H.SoundingAt(notes, t)
    for _, n in ipairs(notes) do
        if n.s > t then return nil end
        if t < n.e then return n.pitch end
    end
    return nil
end

function H.IntervalBucket(i)
    local a = math.abs(i)
    if a % 12 == 0 then return i > 0 and 'octave above' or 'octave below' end
    if a > 12 then return 'compound (> octave)' end
    local name = (a == 3 or a == 4) and '3rd' or (a >= 5 and a <= 7) and '4th/5th'
              or (a == 8 or a == 9) and '6th' or '2nd/7th'
    return name .. (i > 0 and ' above' or ' below')
end

-- Share of a vocal track's notes (vocal range) whose lyric is unpitched ('#').
function H.HashShare(trk)
    if not trk then return 0 end
    local lyric = {}
    for _, t in ipairs(trk.texts) do
        if (t.type == 1 or t.type == 5) and not t.text:match('^%[') then lyric[t.tick] = t.text end
    end
    local n, h = 0, 0
    for _, nt in ipairs(trk.notes) do
        if nt.pitch >= 36 and nt.pitch <= 84 then
            n = n + 1
            local l = lyric[nt.tick]
            if l and l:find('#', 1, true) then h = h + 1 end
        end
    end
    return n > 0 and h / n or 0
end

----------------------------------------------------------------------
-- Frame analysis
----------------------------------------------------------------------

local TAU_MAX, M = YINWindowSize(SR, WIN_S, MIN_F)    -- M = W + tau_max samples for CMND
local TAU_MIN = math.floor(SR / MAX_F)
local PAD = TAU_MAX + 2                                -- room for x[n - T]
local W = M - TAU_MAX

-- Pitch search over CMND d in periods [lo, hi], skipping periods where skip(tau) is true.
-- rule 'yin':   first dip below THRESH (from the high-pitch end), slid to its local
--               minimum, else the deepest dip - what lib/reaper_dsp.lua's SearchYINTau does.
-- rule 'short': the shortest period whose local minimum is within SHORT_MARGIN of the
--               deepest one. Against sub-harmonic picks (2T, 3T = an octave / an octave
--               and a fifth too low), which most 12+ semitone misses turned out to be.
-- Returns a MIDI pitch and its confidence (1 - dip), or nil when the confidence is under
-- `floor` (default MIN_CONF).
local SHORT_MARGIN = 0.10
H.RES_FLOOR = 0.2   -- the residual searches keep pitches down to this; callers filter
local function PickPitch(d, lo, hi, skip, sr_eff, rule, floor)
    lo, hi = math.max(lo, TAU_MIN + 1), math.min(hi, TAU_MAX - 1)
    if lo >= hi then return nil end
    local best
    if rule == 'short' then
        local gmin = math.huge
        for tau = lo, hi do
            if not (skip and skip(tau)) and d[tau] < gmin then gmin = d[tau] end
        end
        for tau = lo, hi do
            if not (skip and skip(tau)) and d[tau] <= d[tau - 1] and d[tau] <= d[tau + 1]
               and d[tau] <= gmin + SHORT_MARGIN then
                best = tau
                break
            end
        end
    else
        for tau = lo, hi do
            if not (skip and skip(tau)) and d[tau] < THRESH then
                while tau < hi and d[tau + 1] < d[tau] do tau = tau + 1 end
                best = tau
                break
            end
        end
        if not best then
            local bd = math.huge
            for tau = lo, hi do
                if not (skip and skip(tau)) and d[tau] < bd then best, bd = tau, d[tau] end
            end
        end
    end
    if not best or 1 - d[best] < (floor or MIN_CONF) then return nil end
    local conf = 1 - d[best]
    local tau = best
    local den = 2 * d[best] - d[best - 1] - d[best + 1]
    if den > 1e-10 then tau = best + math.max(-1, math.min(1, (d[best - 1] - d[best + 1]) / (2 * den))) end
    local f = sr_eff / tau
    if f < MIN_F or f > MAX_F then return nil end
    return math.floor(69 + 12 * math.log(f / 440, 2) + 0.5), conf
end

-- Second (or third) voice searched only within BAND_ST semitones of the lead (period T).
-- Periods within half a semitone of any period in `avoid` are skipped (the voices already
-- cancelled). 2T (an octave below the lead) is inside the band; T/2 (an octave above)
-- cannot be found, because the cancellation removes it with the lead.
local BAND_ST = 13
local function BandPitch(d2, T, sr_eff, rule, floor, avoid)
    avoid = avoid or { T }
    local lo = math.floor(T * 2 ^ (-BAND_ST / 12))
    local hi = math.ceil(T * 2 ^ (BAND_ST / 12))
    return PickPitch(d2, lo, hi, function(tau)
        for _, a in ipairs(avoid) do
            if math.abs(12 * math.log(tau / a, 2)) < 0.5 then return true end
        end
        return false
    end, sr_eff, rule or 'yin', floor)
end

-- The CMND minimum within +-st semitones of an expected period, refined by at most one
-- sample (a minimum on the search edge would otherwise extrapolate out of the buffer).
-- Returns the period and its dip, or nil.
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

-- Expected period (samples) of a MIDI pitch in a song tuned `cents` off concert pitch.
local function PeriodOf(pitch, cents)
    return SR / (440 * 2 ^ ((pitch - 69) / 12) * 2 ^ (cents / 1200))
end

-- One voice's reading from a residual frame: the band search with both rules, kept when the
-- confidence reaches `floor` and the pitch is not the lead's. Equal -> that pitch; different
-- -> the more confident one. Returns pitch, confidence or nil.
function H.VoiceReading(p_yin, c_yin, p_short, c_short, lead_pitch, floor)
    local a = p_yin and p_yin ~= lead_pitch and c_yin >= floor and p_yin or nil
    local b = p_short and p_short ~= lead_pitch and c_short >= floor and p_short or nil
    if a and b then
        if a == b then return a, math.max(c_yin, c_short) end
        if c_short > c_yin then return b, c_short end
        return a, c_yin
    end
    if a then return a, c_yin end
    if b then return b, c_short end
    return nil
end

-- Candidate periods for a voice in a residual's CMND: the deepest local minima within the
-- band around the lead, outside `avoid`, refined by at most a sample; deepest first.
local K_CANDS = 8
-- HAP_EXPERIMENTS=1: also compute the rejected variants (volume-matched cancellation, pair
-- search, least-energy third voice) - kept so their numbers can be reproduced; ~70% slower.
H.EXPERIMENTS = os.getenv('HAP_EXPERIMENTS') ~= nil
local function BandCandidates(d2, T, avoid, k)
    local lo = math.max(TAU_MIN + 1, math.floor(T * 2 ^ (-BAND_ST / 12)))
    local hi = math.min(TAU_MAX - 1, math.ceil(T * 2 ^ (BAND_ST / 12)))
    local list = {}
    for tau = lo, hi do
        if d2[tau] <= d2[tau - 1] and d2[tau] <= d2[tau + 1] then
            local skip = false
            for _, a in ipairs(avoid) do
                if math.abs(12 * math.log(tau / a, 2)) < 0.5 then skip = true end
            end
            if not skip then
                local p = tau
                local den = 2 * d2[tau] - d2[tau - 1] - d2[tau + 1]
                if den > 1e-10 then p = tau + math.max(-1, math.min(1, (d2[tau - 1] - d2[tau + 1]) / (2 * den))) end
                list[#list + 1] = { tau = p, dip = d2[tau] }
            end
        end
    end
    -- A voice repeating every tau also repeats every 2*tau and 3*tau, so a long period
    -- cancels it just as well (and two voices share a long joint period). Replace each
    -- candidate by its shortest sub-period whose dip is nearly as deep, then drop duplicates.
    for _, c in ipairs(list) do
        for div = 4, 2, -1 do
            local sub, sub_dip = PeriodNear(d2, c.tau / div, 0.5)
            if sub and sub_dip <= c.dip + SHORT_MARGIN then c.tau, c.dip = sub, math.min(c.dip, sub_dip); break end
        end
    end
    table.sort(list, function(a, b) return a.dip < b.dip end)
    local out = {}
    for _, c in ipairs(list) do
        local dup = false
        for _, o in ipairs(out) do
            if math.abs(12 * math.log(c.tau / o.tau, 2)) < 0.5 then dup = true end
        end
        for _, a in ipairs(avoid) do
            if math.abs(12 * math.log(c.tau / a, 2)) < 0.5 then dup = true end
        end
        if not dup then out[#out + 1] = c end
        if #out >= k then break end
    end
    return out
end

-- True when one period is (about) 2, 3 or 4 times the other: cancelling the longer one
-- would also remove the shorter one's voice.
local function Multiple(a, b)
    local r = math.max(a, b) / math.min(a, b)
    for m = 2, 4 do
        if math.abs(12 * math.log(r / m, 2)) < 0.5 then return true end
    end
    return false
end

local function TauPitch(tau, sr_eff)
    local f = sr_eff / tau
    if f < MIN_F or f > MAX_F then return nil end
    return math.floor(69 + 12 * math.log(f / 440, 2) + 0.5)
end

-- Frame centred on t (seconds). Returns nil when silent, else a result table:
--   level 1 (or false/nil): p1 (lead search, 'yin' rule = SearchYINTau), p1s ('short' rule)
--   level 2 (or true):      + lead_cents, ratio, half, corr, the residual's p2 / p2b / p2bs /
--                           p2s with their confidences (_c);
--                           + the same with a volume-matched lead cancellation (y = x - g*x[n-T],
--                           least-squares g): p2g_ratio, p2gb / p2gbs (+ _c), lead_gain
--   level 3:                + a third voice, three ways:
--                           cascade - the detected second voice (VoiceReading of p2b / p2bs at
--                             floor3) cancelled too, then p3b / p3bs; with h2_hint (charted
--                             HARM2) instead: p3cb / p3cbs, p3cratio
--                           pair search - of the residual's best K_CANDS candidate periods, the
--                             pair whose double cancellation leaves the least: pra / prb (plain),
--                             prga / prgb (volume-matched), pr_left / prg_left
--                           chart + least energy - HARM2 cancelled from the chart hint, then the
--                             candidate whose cancellation leaves the least: p3e / p3eg
function H.Analyse(pcm, t, lead_pitch, cents, level, h2_hint, floor3)
    if level == true then level = 2 elseif not level then level = 1 end
    local sr_eff = SR * 2 ^ (-cents / 1200)            -- YIN rounds against the song's tuning
    -- Three PADs of history: each chained cancellation needs the previous one's output a
    -- PAD further back (lead -> candidate -> candidate).
    local start = math.floor(t * SR) - (M // 2) - 3 * PAD + 1
    local buf, lb, rb = Window(pcm, start, M + 3 * PAD)
    local OFF = 3 * PAD                                 -- buf[OFF + i] = analysis sample i
    local x = {}
    for i = 1, M do x[i] = buf[i + OFF] end
    local rx = Rms(x, 1, M)
    if rx < SILENT then return nil end

    local d = ComputeCMND(x, TAU_MAX)
    if not d then return nil end
    local res = {}
    res.p1 = SearchYINTau(d, TAU_MIN, TAU_MAX, THRESH, sr_eff, MIN_F, MAX_F, MIN_CONF)
    res.p1s, res.p1s_c = PickPitch(d, TAU_MIN + 1, TAU_MAX - 1, nil, sr_eff, 'short')
    if level < 2 or not lead_pitch then return res end

    local t0 = PeriodOf(lead_pitch, cents)
    local T, dip = PeriodNear(d, t0, SEARCH_ST)
    if not T then return res end
    if 1 - dip >= MIN_CONF then res.lead_cents = 1200 * math.log(t0 / T, 2) end

    -- Cancel `period` from signal s, writing indices OFF - depth*PAD + 1 .. OFF + M (depth 0 =
    -- the analysis span only; each depth keeps the history one more cancellation needs).
    -- fit: scale the delayed copy by the least-squares gain over the span (volume-matched).
    local function Cancel(s, period, depth, fit)
        local pi_, pf = math.floor(period), period - math.floor(period)
        local g = 1
        if fit then
            local num, den = 0, 0
            for k = OFF + 1, OFF + M do
                local j = k - pi_
                local p = s[j] * (1 - pf) + s[j - 1] * pf
                num, den = num + s[k] * p, den + p * p
            end
            if den > 1e-12 then g = math.max(0, math.min(1.5, num / den)) end
        end
        local out = {}
        for k = OFF - depth * PAD + 1, OFF + M do
            local j = k - pi_
            out[k] = s[k] - g * (s[j] * (1 - pf) + s[j - 1] * pf)
        end
        return out, g
    end
    local function Span(s)
        local out = {}
        for i = 1, M do out[i] = s[OFF + i] end
        return out
    end
    local function Energy(s)
        local e = 0
        for k = OFF + 1, OFF + M do e = e + s[k] * s[k] end
        return e
    end

    local depth = level >= 3 and 2 or 0
    local yfull = Cancel(buf, T, depth)
    local y = Span(yfull)
    res.ratio = Rms(y, 1, M) / (math.sqrt(2) * rx)
    -- Octave-up test: cancelling T/2 removes the lead's even harmonics AND any voice an
    -- octave above.
    res.half = Rms(Span(Cancel(buf, T / 2, 0)), 1, M) / (math.sqrt(2) * rx)
    local d2 = ComputeCMND(y, TAU_MAX)
    if d2 then
        res.p2, res.p2_c = SearchYINTau(d2, TAU_MIN, TAU_MAX, THRESH, sr_eff, MIN_F, MAX_F, MIN_CONF)
        res.p2b, res.p2b_c = BandPitch(d2, T, sr_eff, 'yin', H.RES_FLOOR)
        res.p2bs, res.p2bs_c = BandPitch(d2, T, sr_eff, 'short', H.RES_FLOOR)
        res.p2s, res.p2s_c = PickPitch(d2, TAU_MIN + 1, TAU_MAX - 1,
                            function(tau) return math.abs(12 * math.log(tau / T, 2)) < 0.5 end, sr_eff, 'short')
    end
    local c0 = OFF + (M - W) // 2
    res.corr = Corr(lb, rb, c0 + 1, c0 + W)

    -- Volume-matched lead cancellation, the same searches on what is left. Tried and
    -- rejected (worse everywhere: the fitted gain absorbs the other voices, comes out under
    -- 1 and leaves lead residue); only with H.EXPERIMENTS.
    local ygfull, d2g
    if H.EXPERIMENTS then
        local g
        ygfull, g = Cancel(buf, T, depth, true)
        res.lead_gain = g
        local yg = Span(ygfull)
        res.p2g_ratio = Rms(yg, 1, M) / (math.sqrt(2) * rx)
        d2g = ComputeCMND(yg, TAU_MAX)
        if d2g then
            res.p2gb, res.p2gb_c = BandPitch(d2g, T, sr_eff, 'yin', H.RES_FLOOR)
            res.p2gbs, res.p2gbs_c = BandPitch(d2g, T, sr_eff, 'short', H.RES_FLOOR)
        end
    end

    if level >= 3 and d2 then
        -- Cascade: cancel the second voice's period too, then search the band again,
        -- skipping both voices already removed.
        local function Third(T2, prefix)
            local y3 = Span(Cancel(yfull, T2, 0))
            res[prefix .. 'ratio'] = Rms(y3, 1, M) / (math.sqrt(2) * rx)
            local d3 = ComputeCMND(y3, TAU_MAX)
            if not d3 then return end
            local avoid = { T, T2 }
            res[prefix .. 'b'], res[prefix .. 'b_c'] = BandPitch(d3, T, sr_eff, 'yin', H.RES_FLOOR, avoid)
            res[prefix .. 'bs'], res[prefix .. 'bs_c'] = BandPitch(d3, T, sr_eff, 'short', H.RES_FLOOR, avoid)
            return d3
        end
        local p2 = H.VoiceReading(res.p2b, res.p2b_c, res.p2bs, res.p2bs_c, lead_pitch, floor3 or 0.3)
        if p2 then
            res.p3_from = p2
            local T2 = PeriodNear(d2, PeriodOf(p2, cents), 1)
            if T2 then Third(T2, 'p3') end
        end

        -- Pair search: of the best candidates, the pair whose double cancellation leaves the
        -- least energy. Two voices sounding together are found together, so their shared
        -- lower period (the error of the cascade) is no longer a single answer to pick.
        local function Pair(sfull, dd, fit, prefix)
            local cands = BandCandidates(dd, T, { T }, K_CANDS)
            if #cands < 2 then return end
            local first = {}
            for i, c in ipairs(cands) do first[i] = Cancel(sfull, c.tau, 1, fit) end
            local best, bi, bj = math.huge, nil, nil
            for i = 1, #cands - 1 do
                for j = i + 1, #cands do
                    local ti, tj = cands[i].tau, cands[j].tau
                    if math.abs(12 * math.log(ti / tj, 2)) >= 0.5 and not Multiple(ti, tj)
                       and not Multiple(ti, T) and not Multiple(tj, T) then
                        local e = Energy(Cancel(first[i], cands[j].tau, 0, fit))
                        if e < best then best, bi, bj = e, i, j end
                    end
                end
            end
            if bi then
                res[prefix .. 'a'] = TauPitch(cands[bi].tau, sr_eff)
                res[prefix .. 'b'] = TauPitch(cands[bj].tau, sr_eff)
                res[prefix .. '_left'] = math.sqrt(best / M) / (math.sqrt(2) * rx)
            end
        end
        -- Tried and rejected (both parts right 4.8%): only with H.EXPERIMENTS.
        if H.EXPERIMENTS then
            Pair(yfull, d2, false, 'pr')
            if d2g then Pair(ygfull, d2g, true, 'prg') end
        end

        -- With charted HARM2: cancel it from its chart hint, then take the candidate whose
        -- cancellation leaves the least energy (plain and volume-matched).
        if h2_hint and h2_hint ~= lead_pitch then
            local T2 = PeriodNear(d2, PeriodOf(h2_hint, cents), SEARCH_ST)
            if T2 then
                local d3 = Third(T2, 'p3c')
                local function ChartThird(sfull, fit, key)
                    local base = Cancel(sfull, T2, 1, fit)
                    local dd = d3 or ComputeCMND(Span(base), TAU_MAX)
                    if not dd then return end
                    local best, bt = math.huge, nil
                    for _, c in ipairs(BandCandidates(dd, T, { T, T2 }, K_CANDS)) do
                        if not Multiple(c.tau, T) and not Multiple(c.tau, T2) then
                            local e = Energy(Cancel(base, c.tau, 0, fit))
                            if e < best then best, bt = e, c.tau end
                        end
                    end
                    if bt then res[key] = TauPitch(bt, sr_eff) end
                end
                -- Tried and rejected (held 22.8% vs the cascade's 25.4%): H.EXPERIMENTS only.
                if H.EXPERIMENTS then
                    ChartThird(yfull, false, 'p3e')
                    if ygfull then ChartThird(ygfull, true, 'p3eg') end
                end
            end
        end
    end
    return res
end

return H
