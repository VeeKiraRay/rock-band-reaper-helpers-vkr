-- Live pitch tuner: polls the audio source track at the playhead every 100 ms.
-- Requires: S, r, SampleYINAt, OpenYINContext, CloseYINContext, QuickRMS,
--           PitchName, TrackAtIndex, MakeProjectPoll (globals); for the Harmony
--           readout also HarmonyAnalyseFrame / HarmonySpectralPitch / HarmonyVote* /
--           HarmonyScale
--           (lib/reaper_harmony_detect.lua) and KeyFeatures / KeyRankSet /
--           KEY_RESULT_SETS / RB_KEY_PROFILES (lib/reaper_key_detect.lua,
--           lib/reaper_key_profiles.lua)

local TUNER_INTERVAL_S  = 0.1    -- poll every 100 ms
local TUNER_IDLE_STOP_S = 60     -- auto-stop if no new pitch detected for 60 s

----------------------------------------------------------------------
-- Harmony readout: the second voice beside the charted lead
----------------------------------------------------------------------
-- The lead chart (HARM1 / PART VOCALS) says which note the lead sings at the playhead;
-- lib/reaper_harmony_detect.lua cancels that note from the audio and reads what is left.
-- While playing, the reading is a vote over the polls since the current lead note began
-- (single polls disagree with each other about half the time; the vote settles in ~250 ms).
-- When stopped, the whole lead note under the cursor is read at once, a few slices per
-- poll so the window never stalls.

local NOTE_STEP_S    = 0.03   -- slice spacing for the stopped whole-note reading
local NOTE_MAX_SLICE = 15     -- at most this many slices per note (spread evenly)
local NOTE_PER_POLL  = 3      -- slices analysed per poll
local DOUBLED_CORR   = 0.7    -- left/right correlation under this: "the sides differ"

local _lead_poll = MakeProjectPoll(1.0, 5.0)

-- Pitched notes of a vocal chart track in project time: vocal range, '#' (unpitched)
-- lyrics dropped - the same notes the method was measured with.
local function ReadLeadNotes(track)
    local notes = {}
    for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local take = r.GetActiveTake(r.GetTrackMediaItem(track, ii))
        if take and r.TakeIsMIDI(take) then
            local _, n_notes, _, n_text = r.MIDI_CountEvts(take)
            local lyric = {}
            for k = 0, n_text - 1 do
                local _, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, k)
                if (typ == 1 or typ == 5) and not msg:match('^%[') then lyric[ppq] = msg end
            end
            for k = 0, n_notes - 1 do
                local _, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, k)
                local l = lyric[sppq]
                if not muted and pitch >= RB3_MIN_PITCH and pitch <= RB3_MAX_PITCH
                   and not (l and l:find('#', 1, true)) then
                    notes[#notes + 1] = {
                        pitch = pitch,
                        s = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                        e = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                    }
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- The song key from the charted lead (Metadata > Song key's PART VOCALS set), or nil.
local function LeadKey(notes)
    if not (KeyFeatures and KeyRankSet and RB_KEY_PROFILES) then return nil end
    local kn = {}
    for _, n in ipairs(notes) do kn[#kn + 1] = { pitch = n.pitch, qn = n.s, len = n.e - n.s } end
    local ranked = KeyRankSet(KeyFeatures({ vocals = kn }), KEY_RESULT_SETS[1], RB_KEY_PROFILES.sources)
    local k = ranked and ranked[1]
    if not k then return nil end
    return { tonic = k.tonic, minor = k.minor, name = KeyName(k.tonic, k.minor) }
end

-- Re-read the lead chart when the picked track changes, or after a project edit.
function RefreshTunerLead(force)
    local tr = TrackAtIndex(S.tuner_lead_idx)
    local due = _lead_poll()
    if not force and S.tuner_lead and S.tuner_lead.track == tr and not due then return end
    if not tr then S.tuner_lead = { track = nil }; return end
    local notes = ReadLeadNotes(tr)
    S.tuner_lead = { track = tr, notes = notes, key = #notes > 0 and LeadKey(notes) or nil }
end

-- The key snap scale, or nil (S.tuner_key_mode: off / from the lead / a picked key note).
local function SnapScale()
    local m = S.tuner_key_mode or TUNER_KEY_OFF
    if m == TUNER_KEY_OFF then return nil end
    if m == TUNER_KEY_LEAD then
        local k = S.tuner_lead and S.tuner_lead.key
        return k and HarmonyScale(k.tonic, k.minor) or nil
    end
    return HarmonyScale(m - 2, S.tuner_key_minor)
end

-- The charted lead note sounding at t (start inclusive, end exclusive), or nil.
local function LeadNoteAt(notes, t)
    local lo, hi = 1, #notes
    while lo <= hi do
        local mid = (lo + hi) // 2
        local n = notes[mid]
        if t < n.s then hi = mid - 1
        elseif t >= n.e then lo = mid + 1
        else return n end
    end
    return nil
end

-- n samples at HARMONY_SR from the tuner's accessor, starting `lead` seconds before t:
-- mono (channel average), and left / right when the source has two channels or more.
local function ReadAt(t, lead, n)
    local yctx = S.tuner_yctx
    if not yctx then return nil end
    local t_off = t - lead - yctx.item_pos
    if t_off < 0 then return nil end
    local nch = yctx.nch
    local buf = r.new_array(n * nch)
    buf.clear()
    r.GetAudioAccessorSamples(yctx.accessor, HARMONY_SR, nch, t_off, n, buf)
    local mono, left, right = {}, nil, nil
    if nch >= 2 then left, right = {}, {} end
    for i = 1, n do
        local base, s = (i - 1) * nch, 0
        for c = 1, nch do s = s + buf[base + c] end
        mono[i] = s / nch
        if left then left[i], right[i] = buf[base + 1], buf[base + 2] end
    end
    return mono, left, right
end

-- One frame for HarmonyAnalyseFrame; with "Spectral reading too" also the spectral
-- reading of the same moment (res.spec_p), only where the frame was analysed - as measured.
local function HarmonyAt(t, lead_pitch)
    local mono, left, right = ReadAt(t, HARMONY_FRAME_LEAD, HARMONY_FRAME_N)
    if not mono then return nil end
    local res = HarmonyAnalyseFrame(mono, left, right, lead_pitch, 0)
    if res and res.ratio and S.tuner_spectral then
        local m2 = ReadAt(t, HARMONY_SPEC_LEAD, HARMONY_SPEC_N)
        if m2 then res.spec_p = HarmonySpectralPitch(m2, lead_pitch, 0) end
    end
    return res
end

function ResetTunerHarmony()
    S.tuner_harm      = {}
    S.tuner_vote      = nil
    S.tuner_vote_note = nil
    S.tuner_note_job  = nil
end

local function NewTally() return { vote = HarmonyVoteNew(), leads = {}, lead_conf = 0, lead_n = 0, single_split = 0 } end

local function TallyFrame(tl, res, lead_pitch)
    local added = HarmonyVoteAdd(tl.vote, res, lead_pitch)
    if res and res.spec_p then added = added + HarmonyVoteAddPitch(tl.vote, res.spec_p, lead_pitch) end
    if res and res.lead_pitch then
        tl.leads[res.lead_pitch] = (tl.leads[res.lead_pitch] or 0) + 1
        tl.lead_conf, tl.lead_n = tl.lead_conf + res.lead_conf, tl.lead_n + 1
    end
    -- A frame that found only the lead while its left and right differ: a doubled lead?
    if res and added == 0 and res.corr and res.corr < DOUBLED_CORR then tl.single_split = tl.single_split + 1 end
end

-- Publish a tally to S.tuner_harm for the readout. mode: 'held' / 'note' / 'note_busy'.
local function ShowTally(tl, n, mode)
    local p, agree = HarmonyVoteResult(tl.vote, n.pitch, SnapScale())
    local lead, best = nil, 0
    for lp, c in pairs(tl.leads) do if c > best then lead, best = lp, c end end
    S.tuner_harm = {
        mode       = mode,
        chart      = n.pitch,
        lead       = lead,
        lead_conf  = tl.lead_n > 0 and tl.lead_conf / tl.lead_n or nil,
        harm       = p,
        agree      = agree,
        frames     = tl.vote.frames,
        single     = (p == nil and tl.vote.frames > 0),
        doubled    = tl.vote.frames > 0 and tl.single_split * 2 >= tl.vote.frames,
    }
end

-- Advance a stopped whole-note reading by a few slices (runs every poll, also while the
-- cursor stands still).
local function TunerNoteJobStep()
    local job = S.tuner_note_job
    if not job or job.done then return end
    local stop = math.min(#job.times, job.i + NOTE_PER_POLL - 1)
    for k = job.i, stop do TallyFrame(job.tally, HarmonyAt(job.times[k], job.note.pitch), job.note.pitch) end
    job.i = stop + 1
    job.done = job.i > #job.times
    ShowTally(job.tally, job.note, job.done and 'note' or 'note_busy')
end

local function StartNoteJob(n)
    local times = {}
    local a, b = n.s + 0.15 * (n.e - n.s), n.e - 0.15 * (n.e - n.s)
    local t = a
    repeat times[#times + 1] = t; t = t + NOTE_STEP_S until t > b
    if #times > NOTE_MAX_SLICE then           -- spread NOTE_MAX_SLICE evenly instead
        local spread = {}
        for k = 1, NOTE_MAX_SLICE do spread[k] = a + (b - a) * (k - 1) / (NOTE_MAX_SLICE - 1) end
        times = spread
    end
    S.tuner_note_job = { note = n, times = times, i = 1, tally = NewTally() }
    S.tuner_vote, S.tuner_vote_note = nil, nil
    TunerNoteJobStep()
end

-- One poll of the Harmony readout at play_pos (audio is not silent there).
local function RunHarmony(play_pos, playing)
    local lead = S.tuner_lead
    if not (lead and lead.notes and #lead.notes > 0) then
        S.tuner_harm = { mode = 'nolead' }
        return
    end
    local n = LeadNoteAt(lead.notes, play_pos)
    if not n then
        ResetTunerHarmony()
        S.tuner_harm = { mode = 'silent' }
        return
    end
    if playing then
        S.tuner_note_job = nil
        if S.tuner_vote_note ~= n then S.tuner_vote, S.tuner_vote_note = NewTally(), n end
        TallyFrame(S.tuner_vote, HarmonyAt(play_pos, n.pitch), n.pitch)
        ShowTally(S.tuner_vote, n, 'held')
    elseif not (S.tuner_note_job and S.tuner_note_job.note == n) then
        StartNoteJob(n)
    end
end

local function FindItemAtPos(track, t)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local pos  = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local len  = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        if t >= pos and t < pos + len then return item end
    end
    return nil
end

local function OpenContextForItem(item)
    if S.tuner_yctx then
        CloseYINContext(S.tuner_yctx)
        S.tuner_yctx = nil
    end
    local ctx, err = OpenYINContext(item, {
        threshold = S.yin_threshold,
        min_freq  = S.yin_min_freq,
        max_freq  = S.yin_max_freq,
        window_ms = S.yin_window_ms,
        min_conf  = S.yin_min_confidence,
    })
    if not ctx then return nil, err end
    S.tuner_yctx       = ctx
    S.tuner_audio_item = item
    return true
end

function StartTuner()
    if S.audio_idx < 0 then
        S.status = 'Error: no audio source track selected.'
        return
    end
    local tr = r.GetTrack(0, S.audio_idx)
    if not tr then
        S.status = 'Error: source track not found - pick it again.'
        return
    end
    local play_pos = r.GetPlayPosition2()
    local item = FindItemAtPos(tr, play_pos)
    if not item then
        item = r.GetTrackMediaItem(tr, 0)   -- fall back to first item
    end
    if not item then
        S.status = 'Error: no audio items on source track.'
        return
    end
    local ok, err = OpenContextForItem(item)
    if not ok then
        S.status = 'Error opening audio: ' .. (err or 'unknown')
        return
    end
    S.tuner_active         = true
    S.tuner_last_t         = 0
    S.tuner_last_play_pos  = nil
    S.tuner_pos_stable_t   = nil
    S.tuner_last_detect_t  = r.time_precise()
    S.tuner_pitch          = nil
    S.tuner_prev_pitch     = nil
    S.tuner_pitch_name     = nil
    S.tuner_pitch_hz       = nil
    S.tuner_confidence     = nil
    S.tuner_pitch_ts       = nil
    S.tuner_quiet_since    = nil
    S.tuner_history        = {}
    S.last_result          = nil
    ResetTunerHarmony()
    if S.tuner_harmony then RefreshTunerLead(true) end
end

function StopTuner(reason)
    S.tuner_active = false
    if S.tuner_yctx then
        CloseYINContext(S.tuner_yctx)
        S.tuner_yctx = nil
    end
    S.tuner_audio_item = nil
    -- A whole-note reading cut short keeps what it had: shown as a result, not "reading".
    S.tuner_note_job   = nil   -- its audio accessor is gone; the last readout stays shown
    if S.tuner_harm and S.tuner_harm.mode == 'note_busy' then S.tuner_harm.mode = 'note' end
    if reason then S.status = reason end
    -- tuner_pitch, tuner_pitch_name, tuner_pitch_hz, tuner_pitch_ts, tuner_history
    -- intentionally preserved so the user can see the last detected result.
end

function RunTuner()
    if not S.tuner_active then return end

    -- Auto-stop when user navigates away (checked using previous frame's flag).
    if not S.tuner_tab_active then
        StopTuner('Pitch tuner stopped: navigated away from the Tuner sub-tab.')
        return
    end

    local now = r.time_precise()
    if now - S.tuner_last_t < TUNER_INTERVAL_S then return end
    S.tuner_last_t = now

    -- Harmony readout upkeep that must also run while the cursor stands still: the lead
    -- chart re-read after edits, and a stopped whole-note reading still in progress.
    if S.tuner_harmony then
        RefreshTunerLead()
        TunerNoteJobStep()
    end

    -- When playing, use the audio output position; when stopped/scrubbing, use the
    -- edit cursor so that clicking and dragging the playhead is detected correctly.
    local play_state = r.GetPlayState()
    local play_pos = (play_state & 1 ~= 0) and r.GetPlayPosition2()
                                            or  r.GetCursorPosition()

    -- If position hasn't changed since the last scan, skip detection.
    -- Auto-stop fires here if no new pitch has been detected for 60 s.
    if S.tuner_last_play_pos and math.abs(play_pos - S.tuner_last_play_pos) < 0.001 then
        if not S.tuner_pos_stable_t then
            S.tuner_pos_stable_t = now
        elseif now - S.tuner_last_detect_t >= TUNER_IDLE_STOP_S then
            StopTuner('Pitch tuner stopped: no new pitch detected for 60 seconds.')
        end
        return  -- position unchanged - skip detection
    end

    S.tuner_pos_stable_t  = nil
    S.tuner_last_play_pos = play_pos

    -- Validate track.
    local tr = r.GetTrack(0, S.audio_idx)
    if not tr then
        StopTuner('Pitch tuner stopped: source track was removed.')
        return
    end

    -- Check whether there is an audio item at the current position.
    local item = FindItemAtPos(tr, play_pos)
    if not item then
        if not S.tuner_quiet_since then S.tuner_quiet_since = now end
        return
    end

    -- Reopen context if the playhead crossed into a different item.
    if item ~= S.tuner_audio_item then
        local ok, err = OpenContextForItem(item)
        if not ok then
            StopTuner('Pitch tuner stopped: ' .. (err or 'error reopening audio.'))
            return
        end
    end

    if not S.tuner_yctx then return end

    -- Skip YIN on silent audio to avoid spurious low-frequency results.
    local win_s = S.yin_window_ms / 1000
    if QuickRMS(S.tuner_yctx, play_pos, win_s) < S.tuner_rms_threshold then
        if not S.tuner_quiet_since then S.tuner_quiet_since = now end
        if S.tuner_harmony then S.tuner_harm = { mode = 'quiet' } end
        return
    end

    if S.tuner_harmony then RunHarmony(play_pos, play_state & 1 ~= 0) end

    local note, conf = SampleYINAt(S.tuner_yctx, play_pos, win_s)

    if note then
        local name = PitchName(note)
        local hz   = 440.0 * 2.0 ^ ((note - 69) / 12.0)
        S.tuner_prev_pitch    = S.tuner_pitch
        S.tuner_pitch         = note
        S.tuner_pitch_name    = name
        S.tuner_pitch_hz      = hz
        S.tuner_confidence    = conf
        S.tuner_pitch_ts      = play_pos
        S.tuner_last_detect_t = now   -- reset the 60 s auto-stop timer
        S.tuner_quiet_since   = nil
        table.insert(S.tuner_history, 1, name)
        if #S.tuner_history > 10 then
            S.tuner_history[11] = nil
        end
    else
        if not S.tuner_quiet_since then S.tuner_quiet_since = now end
    end
end
