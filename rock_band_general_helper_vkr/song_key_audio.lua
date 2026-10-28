-- Metadata > Song key, audio mode: reads every audio item on the picked vocal and bass
-- tracks as mono, turns each into notes (lib/reaper_key_audio.lua) and ranks the keys
-- with one result: vocal + bass when both tracks give enough notes, else whichever does.
-- Read-only - never writes, never touches S, never creates an undo point.
--
-- RUNS AS A JOB, A SLICE PER UI FRAME. A whole song takes a few seconds, longer on a slow
-- laptop, and a blocking call would freeze the window for all of it. Coroutines are no
-- way out: GetAudioAccessorSamples and new_array fail inside them. So the work is a plain
-- state machine on the main thread: SongKeyAudioStep does at most `budget_s` of reading
-- or analysis per call, and the window's Loop calls it once a frame. One job at a time.
--
-- Requires globals: r, TrackAtIndex (lib/reaper_helper_common.lua), KeyAudioStart,
--                   KeyAudioStep, KeyAudioProgress, KeyAudioFinish, KeyAudioPickSet,
--                   KEY_AUDIO, KEY_AUDIO_BASS (lib/reaper_key_audio.lua), KeyFeatures,
--                   KeyRankSet, KeyConfidence (lib/reaper_key_detect.lua),
--                   RB_KEY_PROFILES (lib/reaper_key_profiles.lua)

-- Samples asked of the accessor per call. Short, so one read never takes a frame's budget.
local BLOCK_S = 2
-- Frames analysed between clock checks. Small enough that a slow machine still checks
-- the clock several times a frame.
local STEP_UNITS = 16

local _job = nil   -- the running job, or nil

-- The audio items of the track at REAPER index idx, as { item, take, len, pos }.
local function TrackItems(idx)
    local track = TrackAtIndex(idx)
    if not track then return nil end
    local items = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
            items[#items + 1] = { item = item, take = take,
                                  len = r.GetMediaItemInfo_Value(item, 'D_LENGTH'),
                                  pos = r.GetMediaItemInfo_Value(item, 'D_POSITION') }
        end
    end
    local _, name = r.GetTrackName(track)
    return items, name
end

local function CloseAccessor(job)
    if job and job.acc then
        r.DestroyAudioAccessor(job.acc)
        job.acc = nil
    end
end

-- Starts the analysis of the picked tracks (REAPER indices, -1 = none).
-- Returns a finished result right away when there is nothing to read (see
-- SongKeyAudioResult for its shape), else nil and the job runs on SongKeyAudioStep.
function SongKeyAudioStart(vocal_idx, bass_idx)
    SongKeyAudioCancel()
    local job = { parts = {}, part = 1, item = 1, work_done = 0, work_total = 0 }
    for _, p in ipairs({ { key = 'vocal', idx = vocal_idx, opts = KEY_AUDIO },
                         { key = 'bass',  idx = bass_idx,  opts = KEY_AUDIO_BASS } }) do
        local items, name = TrackItems(p.idx)
        local part = { key = p.key, opts = p.opts, picked = items ~= nil, name = name,
                       items = items or {}, notes = {}, seconds = 0 }
        for _, it in ipairs(part.items) do
            -- Expected work for the progress bar: frames x the pitch search per frame
            -- (window x longest lag), so a bass second counts for more than a vocal one.
            local o = p.opts
            it.cost = (it.len / o.hop_s) * (o.win_s * o.sr) * (o.sr / o.fmin)
            job.work_total = job.work_total + it.cost
        end
        job.parts[#job.parts + 1] = part
    end
    _job = job
    if not job.parts[1].picked and not job.parts[2].picked then return SongKeyAudioResult() end
    if #job.parts[1].items == 0 and #job.parts[2].items == 0 then return SongKeyAudioResult() end
    return nil
end

-- True while a job is running, with its progress (0..1) and what it is doing.
function SongKeyAudioBusy()
    if not _job or _job.finished then return false end
    local p = _job.parts[_job.part]
    local frac = _job.work_total > 0 and _job.work_done / _job.work_total or 0
    local it = p and p.items[_job.item]
    if it and _job.work_total > 0 then
        -- Within an item: reading is roughly the first 15% of its time, analysis the rest.
        local part_frac = 0
        if _job.st then
            part_frac = 0.15 + 0.85 * KeyAudioProgress(_job.st)
        elseif _job.acc and _job.total > 0 then
            part_frac = 0.15 * _job.done / _job.total
        end
        frac = frac + it.cost * part_frac / _job.work_total
    end
    local label = p and (('%s: %s'):format(p.key == 'vocal' and 'Vocal' or 'Bass',
                                           _job.reading and 'reading' or 'analysing')) or ''
    return true, math.min(1, frac), label
end

function SongKeyAudioCancel()
    CloseAccessor(_job)
    _job = nil
end

-- Reads one block of the current item. Returns true when the item is fully read.
local function ReadBlock(job, it, opts)
    -- Checked every block: the author may delete the item while the job runs.
    if not r.ValidatePtr2(0, it.take, 'MediaItem_Take*') then return nil end
    if not job.acc then
        local src = r.GetMediaItemTake_Source(it.take)
        job.nch = math.max(1, math.floor(r.GetMediaSourceNumChannels(src)))
        job.acc = r.CreateTakeAudioAccessor(it.take)
        job.samples, job.done = {}, 0
        job.total = math.floor(it.len * opts.sr)
        job.block = math.floor(BLOCK_S * opts.sr)
        job.buf = r.new_array(job.block * job.nch)
    end
    local n = math.min(job.block, job.total - job.done)
    if n > 0 then
        local buf, nch, out = job.buf, job.nch, job.samples
        buf.clear()
        -- Item-relative accessor: time 0 is the item's start.
        r.GetAudioAccessorSamples(job.acc, opts.sr, nch, job.done / opts.sr, n, buf)
        for i = 1, n do
            local s = 0
            for c = 1, nch do s = s + buf[(i - 1) * nch + c] end
            out[#out + 1] = s / nch   -- mono: the average of the channels
        end
        job.done = job.done + n
    end
    if job.done < job.total then return false end
    CloseAccessor(job)
    return true
end

-- Advances the job by at most budget_s seconds. Returns the result when the job finishes
-- (or fails), else nil.
function SongKeyAudioStep(budget_s)
    local job = _job
    if not job or job.finished then return nil end
    local t_end = r.time_precise() + budget_s
    repeat
        local p = job.parts[job.part]
        if not p then return SongKeyAudioResult() end
        local it = p.items[job.item]
        if not it then
            job.part, job.item = job.part + 1, 1
        elseif not job.st then
            job.reading = true
            local done = ReadBlock(job, it, p.opts)
            if done == nil then   -- the item was deleted mid-run
                SongKeyAudioCancel()
                return { why = 'changed' }
            end
            if done then
                job.reading = false
                p.seconds = p.seconds + #job.samples / p.opts.sr
                job.st = KeyAudioStart(job.samples, p.opts.sr, it.pos, p.opts)
                job.samples = nil
            end
        elseif KeyAudioStep(job.st, STEP_UNITS) then
            for _, n in ipairs((KeyAudioFinish(job.st))) do p.notes[#p.notes + 1] = n end
            job.st = nil
            job.work_done = job.work_done + it.cost
            job.item = job.item + 1
        end
    until r.time_precise() >= t_end
    return nil
end

-- The finished job's result, and the job cleared.
-- Returns {
--   vocal, bass = { picked, items, notes (count), seconds, name },
--   set, label, ranked, used, confidence    -- when a key could be ranked
--   why = 'no_track' | 'no_items' | 'no_notes' | 'changed' -- when not
-- }
function SongKeyAudioResult()
    local job = _job
    SongKeyAudioCancel()
    if not job then return { why = 'no_track' } end
    local v, b = job.parts[1], job.parts[2]
    local function Summary(p)
        return { picked = p.picked, items = #p.items, notes = #p.notes, seconds = p.seconds, name = p.name }
    end
    local out = { vocal = Summary(v), bass = Summary(b) }
    if not v.picked and not b.picked then out.why = 'no_track'; return out end
    if #v.items == 0 and #b.items == 0 then out.why = 'no_items'; return out end

    local set = KeyAudioPickSet(#v.notes, #b.notes)
    if not set then out.why = 'no_notes'; return out end
    local ranked, extra = KeyRankSet(KeyFeatures({ vocals = v.notes, keys = b.notes }), set,
                                     RB_KEY_PROFILES.sources)
    if not ranked then out.why = 'no_notes'; return out end
    out.set, out.label = set, set.label
    out.ranked, out.used, out.confidence = ranked, extra, KeyConfidence(ranked)
    return out
end

-- The whole analysis in one blocking call (tests and offline checks).
function SuggestAudioSongKey(vocal_idx, bass_idx)
    local res = SongKeyAudioStart(vocal_idx, bass_idx)
    while not res do res = SongKeyAudioStep(3600) end
    return res
end

-- An accessor left open when the script ends would hold the file open; close it.
if r.atexit then r.atexit(SongKeyAudioCancel) end
