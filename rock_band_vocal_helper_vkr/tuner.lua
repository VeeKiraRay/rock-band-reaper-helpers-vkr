-- Live pitch tuner: polls the audio source track at the playhead every 100 ms.
-- Requires: S, r, SampleYINAt, OpenYINContext, CloseYINContext, PitchName (globals)

local TUNER_INTERVAL_S  = 0.1    -- poll every 100 ms
local TUNER_IDLE_STOP_S = 60     -- auto-stop if no new pitch detected for 60 s

local function QuickRMS(yctx, t, win_s)
    local samps = math.max(1, math.floor(yctx.sr * win_s))
    local buf   = r.new_array(samps)
    local t_off = math.max(0, t - yctx.item_pos)
    r.GetAudioAccessorSamples(yctx.accessor, yctx.sr, 1, t_off, samps, buf)
    local sum_sq = 0
    for i = 1, samps do sum_sq = sum_sq + buf[i] * buf[i] end
    return math.sqrt(sum_sq / samps)
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
    local ctx, err = OpenYINContext(item)
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
        S.status = 'Error: source track not found — refresh tracks.'
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
    S.tuner_pitch_ts       = nil
    S.tuner_quiet_since    = nil
    S.tuner_history        = {}
    S.last_result          = nil
end

function StopTuner(reason)
    S.tuner_active = false
    if S.tuner_yctx then
        CloseYINContext(S.tuner_yctx)
        S.tuner_yctx = nil
    end
    S.tuner_audio_item = nil
    if reason then S.status = reason end
    -- tuner_pitch, tuner_pitch_name, tuner_pitch_hz, tuner_pitch_ts, tuner_history
    -- intentionally preserved so the user can see the last detected result.
end

function RunTuner()
    if not S.tuner_active then return end

    -- Auto-stop when user navigates away (checked using previous frame's flag).
    if not S.tuner_tab_active then
        StopTuner('Pitch tuner stopped: navigated away from Tuner tab.')
        return
    end

    local now = r.time_precise()
    if now - S.tuner_last_t < TUNER_INTERVAL_S then return end
    S.tuner_last_t = now

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
        return  -- position unchanged — skip detection
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
        return
    end

    local note = SampleYINAt(S.tuner_yctx, play_pos, win_s)

    if note then
        local name = PitchName(note)
        local hz   = 440.0 * 2.0 ^ ((note - 69) / 12.0)
        S.tuner_prev_pitch    = S.tuner_pitch
        S.tuner_pitch         = note
        S.tuner_pitch_name    = name
        S.tuner_pitch_hz      = hz
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
