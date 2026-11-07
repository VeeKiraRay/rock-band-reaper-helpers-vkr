-- Keys > Tuner: chord names from the keys stem at the playhead or the edit cursor.
-- Read-only: never writes to the project, never creates an undo point.
-- Requires: S, r (globals); OpenYINContext / CloseYINContext (lib/reaper_dsp.lua);
--           ChordFrameChroma / ChordFrameAnalyse / ChordPassage / ChordSum* / ChordRank /
--           ChordBassPc / ChordBassVote /
--           ChordKeyMask / ChordConfidence and the CHORD_* constants
--           (lib/reaper_chord_detect.lua); KeyFeatures / KeyRankSet / KEY_RESULT_SETS /
--           KeyName / KeyLyricIsUnpitched / KEY_MIN_NOTES / KEY_* ranges (lib/reaper_key_detect.lua),
--           RB_KEY_PROFILES (lib/reaper_key_profiles.lua); TrackAtIndex, MakeProjectPoll
--           (lib/reaper_helper_common.lua); FindTrackExact (lib/reaper_difficulty_read.lua)
--
-- How a reading is made (the method measured on the official songs, see
-- lib/reaper_chord_detect.lua):
--   stopped, a Pro Keys chord charted under the cursor: that chord's own span (its start
--     + 30 ms, a frame every 64 ms, at most 6) - the chart gives the timing only, never
--     the answer;
--   stopped, nothing charted there: CHORD_READ_FRAMES[short | long] frames from the cursor;
--   playing: the CHORD_PLAY_FRAMES frames ending at the playhead.
-- The bass stem (optional) adds its pitch class over the same stretch.

local POLL_S          = 0.1    -- poll every 100 ms
local IDLE_STOP_S     = 60     -- stop when stopped and the cursor has not moved this long (as the vocal Tuner)
local FRAMES_PER_POLL = 2      -- a stopped reading is spread over polls so the window never stalls
local HISTORY_MAX     = 12
local PK_TRACK        = 'PART REAL_KEYS_X'

CHORD_KEY_MODES = { 'off', 'vocals', 'prokeys', 'manual' }   -- S.ct_key_mode values

local _chart_poll = MakeProjectPoll(1.0, 5.0)

----------------------------------------------------------------------
-- Project reads: charted Pro Keys chords, the song key
----------------------------------------------------------------------

-- Notes of a track in [lo, hi] as { pitch, s, e, qn, len }, unmuted; vocal = true drops
-- notes whose lyric marks them unpitched (as Metadata > Song key reads them).
local function ReadNotes(track, lo, hi, vocal)
    local out = {}
    if not track then return out end
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local take = r.GetActiveTake(r.GetTrackMediaItem(track, i))
        if take and r.TakeIsMIDI(take) then
            local _, notecnt, _, textcnt = r.MIDI_CountEvts(take)
            local lyric = {}
            if vocal then
                for j = 0, textcnt - 1 do
                    local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, j)
                    if ok and msg and (typ == 1 or typ == 5) and not msg:match('^%[') then lyric[ppq] = msg end
                end
            end
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= lo and pitch <= hi
                   and not (vocal and KeyLyricIsUnpitched(lyric[sppq])) then
                    local qn, qne = r.MIDI_GetProjQNFromPPQPos(take, sppq), r.MIDI_GetProjQNFromPPQPos(take, eppq)
                    out[#out + 1] = { pitch = pitch, qn = qn, len = qne - qn,
                        s = r.MIDI_GetProjTimeFromPPQPos(take, sppq), e = r.MIDI_GetProjTimeFromPPQPos(take, eppq) }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

-- Charted chords: one entry per distinct start, { s, next, mask } where mask holds the
-- pitch classes sounding just after the start (notes starting there or still held 30 ms on).
local function ChartChords(notes)
    local ons = {}
    for _, n in ipairs(notes) do
        if not ons[#ons] or math.abs(ons[#ons].s - n.s) > 1e-4 then ons[#ons + 1] = { s = n.s } end
    end
    for i, o in ipairs(ons) do
        o.next = ons[i + 1] and ons[i + 1].s or o.s + 1.0
        local mask = 0
        for _, n in ipairs(notes) do
            if n.s > o.s + 1e-4 then break end
            if math.abs(n.s - o.s) <= 1e-4 or n.e > o.s + 0.030 then mask = mask | (1 << (n.pitch % 12)) end
        end
        o.mask = mask
    end
    return ons
end

local function KeyFrom(part_notes, set)
    local ranked = KeyRankSet(KeyFeatures(part_notes), set, RB_KEY_PROFILES.sources)
    local k = ranked and ranked[1]
    if not k then return nil end
    return { tonic = k.tonic, minor = k.minor }
end

-- Re-read the chart and the song key when the project changed (or force).
function RefreshChordTunerProject(force)
    if not _chart_poll() and not force and S.ct_chart then return end
    local pk = ReadNotes(FindTrackExact(PK_TRACK), KEY_KEYS_LO, KEY_KEYS_HI, false)
    S.ct_chart = ChartChords(pk)
    local mode = S.ct_key_mode
    local key, why
    if mode == 'vocals' then
        local v = ReadNotes(FindTrackExact('PART VOCALS'), KEY_VOCAL_LO, KEY_VOCAL_HI, true)
        key = #v > 0 and KeyFrom({ vocals = v }, KEY_RESULT_SETS[1]) or nil
        why = ('fewer than %d pitched PART VOCALS notes'):format(KEY_MIN_NOTES)
    elseif mode == 'prokeys' then
        local set
        for _, s in ipairs(KEY_RESULT_SETS) do if s.key == 'keysonly' then set = s end end
        key = #pk > 0 and set and KeyFrom({ keys = pk }, set) or nil
        why = ('fewer than %d %s notes'):format(KEY_MIN_NOTES, PK_TRACK)
    elseif mode == 'manual' then
        key = { tonic = S.ct_key_tonic, minor = S.ct_key_minor }
    end
    if key then
        key.name, key.mask = KeyName(key.tonic, key.minor), ChordKeyMask(key.tonic, key.minor)
        S.ct_key, S.ct_key_why = key, nil
    else
        S.ct_key, S.ct_key_why = nil, mode ~= 'off' and why or nil
    end
end

local function ChartChordAt(t)
    local list = S.ct_chart
    if not list then return nil end
    local lo, hi = 1, #list
    while lo <= hi do
        local mid = (lo + hi) // 2
        local o = list[mid]
        if t < o.s then hi = mid - 1
        elseif t >= o.next then lo = mid + 1
        else return o end
    end
    return nil
end

----------------------------------------------------------------------
-- Audio
----------------------------------------------------------------------

local function ItemAt(track, t)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local pos  = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        if t >= pos and t < pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH') then return item end
    end
    return nil
end

-- An accessor for the item of `track` under t, reopened when the item changes.
-- slot: 'keys' or 'bass'. Returns the context or nil.
local function ContextAt(slot, track, t)
    local item = track and ItemAt(track, t)
    local cur = S.ct_audio[slot]
    if cur and cur.item == item then return cur.ctx end
    if cur then CloseYINContext(cur.ctx) end
    S.ct_audio[slot] = nil
    if not item then return nil end
    local ctx = OpenYINContext(item, {})
    if not ctx then return nil end
    S.ct_audio[slot] = { item = item, ctx = ctx }
    return ctx
end

-- n samples at CHORD_SR from project time t, channels averaged; nil before the item.
local function ReadMono(actx, t, n)
    local t_off = t - actx.item_pos       -- the take accessor counts from the item start
    if t_off < 0 then return nil end
    local nch = actx.nch
    local buf = r.new_array(n * nch)
    buf.clear()
    r.GetAudioAccessorSamples(actx.accessor, CHORD_SR, nch, t_off, n, buf)
    local mono = {}
    for i = 1, n do
        local base, s = (i - 1) * nch, 0
        for c = 1, nch do s = s + buf[base + c] end
        mono[i] = s / nch
    end
    return mono
end

----------------------------------------------------------------------
-- Readings
----------------------------------------------------------------------

-- A reading job: frame start times, bass reading times, what it is for.
local function NewJob(kind, pos, frame_times, bass_from, bass_to, chart)
    local bass_times = {}
    local t = bass_from
    for _ = 1, 4 do
        bass_times[#bass_times + 1] = t
        t = t + CHORD_BASS_STEP_S
        if t + CHORD_BASS_WIN_S > bass_to then break end
    end
    return { kind = kind, pos = pos, frames = frame_times, bass_times = bass_times, chart = chart,
             i = 1, sum = ChordSumNew(), sal = {}, bass_pcs = {} }
end

-- The reading as one note: the strongest pitch class of the chroma (the best note namer
-- measured on official songs), in the octave where that class's harmonic sum is largest
-- (a guess - Pro Keys charts are folded into their range, so the octave was not scored).
local function SingleNote(job)
    if job.sum.n == 0 then return nil end
    local pc, best = nil, 0
    for i = 0, 11 do if job.sum[i] > best then pc, best = i, job.sum[i] end end
    if not pc then return nil end
    local note, nb = nil, -1
    for p, v in pairs(job.sal) do
        if p % 12 == pc and v > nb then note, nb = p, v end
    end
    return note
end

local function Publish(job)
    local opts = { key_mask = S.ct_key and S.ct_key.mask or nil, bass = ChordBassVote(job.bass_pcs) }
    local res = { kind = job.kind, pos = job.pos, chart = job.chart, bass = opts.bass, frames = job.sum.n,
                  single = SingleNote(job),
                  busy = job.i <= #job.frames }
    if job.sum.n > 0 then
        opts.plain = S.ct_plain
        local top, margin = ChordRank(job.sum, opts)
        if top then
            res.top, res.margin, res.conf = top, margin, ChordConfidence(margin)
            opts.plain = not S.ct_plain           -- the other reading, shown when it differs
            local other = ChordRank(job.sum, opts)
            if other and other[1].mask ~= top[1].mask then res.other = other[1] end
        end
    end
    S.ct_result = res
    -- Histories, oldest first so they read like the part: a reading joins only when it
    -- differs from the last one (polls while playing repeat the same reading), so a key
    -- pressed twice in a row shows once.
    local function Push(list, item)
        if list[#list] ~= item then
            list[#list + 1] = item
            if #list > HISTORY_MAX then table.remove(list, 1) end
        end
    end
    if res.top and not res.busy then
        Push(S.ct_history, ChordName(res.top[1]))
        if res.single then Push(S.ct_note_history, PitchName(res.single)) end
    end
end

-- Analyse up to `max` more frames of the job (and its bass readings); publish the result.
local function Step(job, max)
    local kctx = ContextAt('keys', TrackAtIndex(S.ct_keys_idx), job.pos)
    if not kctx then
        S.ct_result = { kind = 'noaudio', pos = job.pos }
        return true
    end
    local stop = math.min(#job.frames, job.i + max - 1)
    for k = job.i, stop do
        local mono = ReadMono(kctx, job.frames[k], CHORD_FRAME_N)
        if mono then
            local c, sal = ChordFrameAnalyse(mono, 0)
            ChordSumAdd(job.sum, c)
            if sal then
                for p, v in pairs(sal) do job.sal[p] = (job.sal[p] or 0) + v end
            end
        end
    end
    job.i = stop + 1
    if job.i > #job.frames and not job.bass_done then
        job.bass_done = true
        local bctx = ContextAt('bass', TrackAtIndex(S.ct_bass_idx), job.pos)
        if bctx then
            for _, t in ipairs(job.bass_times) do
                local mono = ReadMono(bctx, t, CHORD_BASS_N)
                local pc = mono and ChordBassPc(mono, 0)
                if pc then job.bass_pcs[#job.bass_pcs + 1] = pc end
            end
        end
    end
    Publish(job)
    return job.i > #job.frames
end

local function StoppedJob(pos)
    local o = ChartChordAt(pos)
    local frames = {}
    if o then
        for k = 0, CHORD_SPAN_MAX - 1 do
            local st = o.s + CHORD_ATTACK_S + k * CHORD_HOP_S
            if k > 0 and st + CHORD_HOP_S > o.next then break end
            frames[#frames + 1] = st
        end
        return NewJob('chart', pos, frames, o.s + 0.060, o.next, o)
    end
    local n = CHORD_READ_FRAMES[S.ct_read_long and 'long' or 'short']
    local t0 = pos + CHORD_ATTACK_S
    for k = 0, n - 1 do frames[#frames + 1] = t0 + k * CHORD_HOP_S end
    local t_end = frames[#frames] + CHORD_FRAME_N / CHORD_SR
    return NewJob('fixed', pos, frames, t0, t_end, nil)
end

local function PlayingJob(pos)
    local frames = {}
    local span = CHORD_FRAME_N / CHORD_SR
    for k = CHORD_PLAY_FRAMES - 1, 0, -1 do frames[#frames + 1] = pos - span - k * CHORD_HOP_S end
    return NewJob('playing', pos, frames, frames[1], pos, ChartChordAt(pos))
end

----------------------------------------------------------------------
-- Passage check: single notes or chords over about 4 s (ChordPassage)
----------------------------------------------------------------------
-- Stopped only: 4 s cannot keep up with playback. Frames on a fixed grid of CHORD_PASS_HOP_S
-- (frame g starts at g * hop), cached by g, so dragging the cursor only reads frames it has
-- not read yet. The verdict needs the passage's frames plus three before it and one after
-- (ChordPassage).

local PASS_PER_POLL     = 4      -- frames analysed per poll for the passage check

local function PassFrame(g)
    local cache = S.ct_pass_frames
    local v = cache[g]
    if v ~= nil then return v end
    local t = g * CHORD_PASS_HOP_S
    local kctx = ContextAt('keys', TrackAtIndex(S.ct_keys_idx), t)
    local mono = kctx and ReadMono(kctx, t, CHORD_FRAME_N)
    local sal = false
    if mono then
        local _, p = ChordFrameAnalyse(mono, 0)
        sal = p or false
    end
    cache[g] = sal
    return sal
end

-- The frames g_first .. g_first + CHORD_PASS_FRAMES + 3 as ChordPassage wants them; frames
-- not analysed yet count as missing (false). Returns the list and the share missing.
local function PassList(g_first)
    local list, missing = {}, 0
    local cache = S.ct_pass_frames
    for g = g_first, g_first + CHORD_PASS_FRAMES + 3 do
        local v = cache[g]
        if v == nil then missing = missing + 1; v = false end
        list[#list + 1] = v
    end
    return list, missing / #list
end

-- The verdict of frames g_first ...; the note named is the first key press whose frame
-- reaches the cursor (frame i starts at (g_first + i - 1) hops and covers CHORD_FRAME_N
-- samples, so a press at the cursor peaks in a frame starting up to one frame before it).
local function PassVerdict(list, g_first, pos)
    local res = ChordPassage(list)
    local note
    local from = pos - CHORD_FRAME_N / CHORD_SR
    for _, o in ipairs(res.onsets) do
        if (g_first + o.i - 1) * CHORD_PASS_HOP_S >= from then note = o.note; break end
    end
    S.ct_pass = { single = res.single, value = res.value, onsets = #res.onsets, note = note, pos = pos }
end

-- Stopped: ~4 s from the cursor, PASS_PER_POLL frames per poll until complete.
local function PassageStoppedStep()
    local job = S.ct_pass_job
    if not job then return end
    local done = 0
    for g = job.g_first, job.g_first + CHORD_PASS_FRAMES + 3 do
        if S.ct_pass_frames[g] == nil then
            if done >= PASS_PER_POLL then
                S.ct_pass = { busy = true, pos = job.pos }
                return
            end
            PassFrame(g)
            done = done + 1
        end
    end
    PassVerdict((PassList(job.g_first)), job.g_first, job.pos)
    S.ct_pass_job = nil
end

local function PassageStoppedStart(pos)
    if not S.ct_passage then S.ct_pass_job, S.ct_pass = nil, nil; return end
    -- The passage starts one grid frame before the cursor, so a key pressed right at the
    -- cursor is inside it (its flux peak can fall on the frame starting just before).
    local g_first = math.floor(pos / CHORD_PASS_HOP_S) - 1 - 3
    -- Frames already read stay cached (dragging the cursor re-reads only what is new);
    -- frames far from this passage are dropped.
    for g in pairs(S.ct_pass_frames) do
        if g < g_first - 200 or g > g_first + CHORD_PASS_FRAMES + 200 then S.ct_pass_frames[g] = nil end
    end
    S.ct_pass_job = { g_first = g_first, pos = pos }
    S.ct_pass = { busy = true, pos = pos }
end

----------------------------------------------------------------------
-- Start / stop / poll
----------------------------------------------------------------------
----------------------------------------------------------------------

local function CloseAudio()
    for slot, a in pairs(S.ct_audio or {}) do
        CloseYINContext(a.ctx)
        S.ct_audio[slot] = nil
    end
end

function StartChordTuner()
    local tr = TrackAtIndex(S.ct_keys_idx)
    if not tr then
        S.status = 'Pick the keys audio track first.'
        return
    end
    if r.CountTrackMediaItems(tr) == 0 then
        S.status = 'The keys audio track has no items.'
        return
    end
    S.ct_audio   = {}
    S.ct_active  = true
    S.ct_last_t  = 0
    S.ct_last_pos, S.ct_last_playing = nil, nil
    S.ct_last_move_t = r.time_precise()
    S.ct_job     = nil
    S.ct_result  = nil
    S.ct_history, S.ct_note_history = {}, {}
    S.ct_pass_frames, S.ct_pass_job, S.ct_pass = {}, nil, nil
    RefreshChordTunerProject(true)
    S.status = 'Chord tuner running.'
end

function StopChordTuner(reason)
    S.ct_active = false
    S.ct_job = nil
    S.ct_pass_job, S.ct_pass_frames = nil, {}
    if S.ct_pass and S.ct_pass.busy then S.ct_pass = nil end
    CloseAudio()
    if S.ct_result and S.ct_result.busy then S.ct_result.busy = false end
    if reason then S.status = reason end
end

-- A setting changed: re-read the key now (shown even while stopped) and, when running,
-- read the audio again at once, even with the cursor standing still.
function ChordTunerReread()
    S.ct_last_pos = nil
    S.ct_job = nil
    S.ct_pass_job, S.ct_pass = nil, nil
    RefreshChordTunerProject(true)
end

-- Called every frame from the window loop.
function ChordTunerTick()
    if not S.ct_active then return end
    if not S.ct_tab_active then
        StopChordTuner('Chord tuner stopped: left the Keys > Tuner sub-tab.')
        return
    end
    local now = r.time_precise()
    if now - S.ct_last_t < POLL_S then return end
    S.ct_last_t = now
    if not TrackAtIndex(S.ct_keys_idx) then
        StopChordTuner('Chord tuner stopped: the keys audio track is gone.')
        return
    end
    RefreshChordTunerProject(false)

    local playing = r.GetPlayState() & 1 ~= 0
    local pos = playing and r.GetPlayPosition2() or r.GetCursorPosition()
    if playing then
        S.ct_job = nil
        S.ct_last_pos, S.ct_last_playing = pos, true
        S.ct_last_move_t = now
        Step(PlayingJob(pos), CHORD_PLAY_FRAMES)
        S.ct_pass_job = nil
        S.ct_pass = nil          -- the passage check is for a stopped cursor only
        return
    end
    -- Stopped: a new reading when the cursor moved, else finish the one in progress.
    if S.ct_last_playing or not S.ct_last_pos or math.abs(pos - S.ct_last_pos) > 0.001 then
        S.ct_last_pos, S.ct_last_playing = pos, false
        S.ct_last_move_t = now
        S.ct_job = StoppedJob(pos)
        PassageStoppedStart(pos)
    end
    if S.ct_job then
        if Step(S.ct_job, FRAMES_PER_POLL) then S.ct_job = nil end
    elseif S.ct_pass_job then
        PassageStoppedStep()   -- after the chord, so its name shows first
    elseif now - (S.ct_last_move_t or now) >= IDLE_STOP_S then
        -- Nothing left to read and the cursor has not moved: do not run on in the background.
        StopChordTuner(('Chord tuner stopped: the cursor has not moved for %d seconds.'):format(IDLE_STOP_S))
    end
end

if r.atexit then r.atexit(function() CloseAudio() end) end
