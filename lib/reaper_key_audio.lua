-- Song key from a vocal recording - pure, no r / ctx / S.
--
-- Turns mono samples of an isolated vocal (or bass) into notes for the key scorer
-- (lib/reaper_key_detect.lua). The reader averages a stereo or multichannel recording to
-- mono first: a lead vocal or bass stem is centred, so both channels carry the same part
-- and nothing is lost. Then YIN pitch per frame (ComputeCMND / SearchYINTau from
-- lib/reaper_dsp.lua, which are pure), frames below a loudness gate skipped, then runs of
-- the same pitch held long enough become one note. Shared by the General Helper's
-- Metadata > Song key (song_key_audio.lua reads the samples from REAPER) and by offline
-- probes, so both analyse a recording identically.
--
-- WHY AN 8 kHz ANALYSIS RATE when the vocal helper's pitch tuning uses 24 kHz. That
-- helper needs every note's pitch right; a key needs the overall balance of pitch classes,
-- and an occasional semitone slip on a high note is noise against thousands of frames.
-- A higher rate costs several times as much without changing the answer. Octave errors -
-- YIN's commonest - do not change a note's pitch class at all.
--
-- WHAT IT CANNOT DO. A full mix, with the instruments in it, gives a pitch track of
-- whatever is loudest; the tab asks for isolated stems for that reason. And many notes
-- read "outside the key" even when the key is right (slides, vibrato and breaths smear
-- onto neighbouring semitones), so the tab shows no outside-the-key list for audio.
--
-- Requires globals: ComputeCMND, SearchYINTau (lib/reaper_dsp.lua); KEY_MIN_NOTES
-- (lib/reaper_key_detect.lua, loaded first) for KeyAudioPickSet.

KEY_AUDIO_SR = 8000   -- analysis rate, Hz; the reader asks REAPER to resample to it

KEY_AUDIO = {
    sr         = KEY_AUDIO_SR,   -- the rate the reader asks REAPER for
    hop_s      = 0.025,   -- frame step
    win_s      = 0.040,   -- samples read per frame (correlation width + longest lag)
    fmin       = 80,      -- lowest pitch searched, Hz
    fmax       = 1000,    -- highest
    threshold  = 0.15,    -- YIN dip threshold
    min_conf   = 0.5,     -- YIN periodicity a frame needs to count
    min_frames = 3,       -- a note must hold its pitch this many frames (75 ms)
    gate_rel   = 0.1,     -- loudness gate: this share of ...
    gate_pct   = 0.95,    -- ... the frame RMS at this percentile
    min_rms    = 1e-4,    -- and never below this (digital silence)
}

-- A bass stem: the same pipeline, searched lower. 30 Hz is below a 5-string's low B
-- (31 Hz); the window grows so it still holds two periods of the lowest note.
KEY_AUDIO_BASS = {}
for k, v in pairs(KEY_AUDIO) do KEY_AUDIO_BASS[k] = v end
KEY_AUDIO_BASS.fmin, KEY_AUDIO_BASS.fmax, KEY_AUDIO_BASS.win_s = 30, 400, 0.060

-- The audio results. Vocal notes go in as the `vocals` part and are scored with the PART
-- VOCALS profiles; bass notes go in as the `keys` part and are scored with Kbass, the
-- profile of the lowest Pro Keys note of each chord - the charted line nearest to a bass
-- part (too few official charts carry pro bass to fit a profile of its own).
--
-- Together they work best: the vocal gives the scale, and the bass keeps returning to the
-- home note, which is what a melody alone leaves unclear.
KEY_AUDIO_SETS = {
    vocal = { key = 'audio', label = 'Vocal audio', fixed_label = true,
              needs = 'vocals', parts = { 'vocals' },
              weights = { V = 2, Vlast = 0.5 } },
    bass  = { key = 'audio', label = 'Bass audio', fixed_label = true,
              needs = 'keys', parts = { 'keys' },
              weights = { Kbass = 1 } },
    both  = { key = 'audio', label = 'Vocal + bass audio', fixed_label = true,
              needs = 'vocals', parts = { 'vocals', 'keys' },
              weights = { V = 2, Vlast = 0.5, Kbass = 2 } },
}
KEY_AUDIO_SET = KEY_AUDIO_SETS.vocal   -- the vocal-only set, kept for tests and probes

-- Which audio set to rank with, from the note counts found: both stems when each has
-- enough notes, else whichever does, else nil.
function KeyAudioPickSet(vocal_notes, bass_notes)
    local v, b = (vocal_notes or 0) >= KEY_MIN_NOTES, (bass_notes or 0) >= KEY_MIN_NOTES
    if v and b then return KEY_AUDIO_SETS.both end
    if v then return KEY_AUDIO_SETS.vocal end
    if b then return KEY_AUDIO_SETS.bass end
    return nil
end

----------------------------------------------------------------------
-- Analysis, in resumable steps
--
-- A caller that must keep a UI responsive (song_key_audio.lua) calls KeyAudioStep with a
-- few frames at a time across UI frames; KeyAudioNotes runs the same steps to the end in
-- one go. Both produce identical notes.
----------------------------------------------------------------------

-- samples: 1-based mono array at rate sr. t0: time of samples[1], in seconds (so notes
-- from several items sort in project order). opts: KEY_AUDIO by default.
-- Returns the analysis state; nothing is computed yet.
function KeyAudioStart(samples, sr, t0, opts)
    opts = opts or KEY_AUDIO
    local st = {
        samples = samples, sr = sr, t0 = t0 or 0, opts = opts,
        hop     = math.max(1, math.floor(opts.hop_s * sr + 0.5)),
        win     = math.max(2, math.floor(opts.win_s * sr + 0.5)),
        tau_min = math.floor(sr / opts.fmax),
        tau_max = math.ceil(sr / opts.fmin),
        frames  = {}, levels = {},
        phase   = 'level',   -- 'level' -> 'pitch' -> 'done'
        next    = 1,         -- next sample start (level) or frame index (pitch)
        voiced  = 0,
    }
    if st.win <= st.tau_max + 1 then st.win = st.tau_max + 2 end
    st.n_frames = math.max(0, math.floor((#samples - st.win - 1) / st.hop) + 1)
    return st
end

-- Advances the analysis by up to `units` frames: loudness for every frame first (to set a
-- gate relative to this recording's own level), then pitch where loud enough. Returns
-- true when finished. A loudness frame costs about 1/tau_max of a pitch frame, so it is
-- worth that much of a unit.
function KeyAudioStep(st, units)
    local samples, win, hop = st.samples, st.win, st.hop
    if st.phase == 'level' then
        local budget = units * st.tau_max
        local start = st.next
        while budget > 0 and start <= #samples - win do
            local acc = 0
            for j = start, start + win - 1 do
                local x = samples[j]
                acc = acc + x * x
            end
            local rms = math.sqrt(acc / win)
            st.frames[#st.frames + 1] = { start = start, rms = rms }
            st.levels[#st.levels + 1] = rms
            start = start + hop
            budget = budget - 1
        end
        st.next = start
        if start <= #samples - win then return false end
        if #st.frames == 0 then st.phase = 'done'; return true end
        table.sort(st.levels)
        st.gate = math.max(st.opts.min_rms, st.opts.gate_rel *
            st.levels[math.max(1, math.floor(st.opts.gate_pct * #st.levels))])
        st.levels = nil
        st.phase, st.next = 'pitch', 1
    end
    if st.phase == 'pitch' then
        local opts, frames = st.opts, st.frames
        local last = math.min(#frames, st.next + units - 1)
        for f = st.next, last do
            local fr = frames[f]
            if fr.rms >= st.gate then
                local w = {}
                for j = 1, win do w[j] = samples[fr.start + j - 1] end
                local d = ComputeCMND(w, st.tau_max)
                local p = d and SearchYINTau(d, st.tau_min, st.tau_max, opts.threshold, st.sr,
                                             opts.fmin, opts.fmax, opts.min_conf)
                if p then fr.pitch = p; st.voiced = st.voiced + 1 end
            end
        end
        st.next = last + 1
        if st.next <= #frames then return false end
        st.phase = 'done'
    end
    return true
end

-- How far an analysis has got, 0..1: loudness is about a tenth of the work, pitch the rest.
function KeyAudioProgress(st)
    if st.phase == 'done' then return 1 end
    if st.n_frames == 0 then return 0 end
    if st.phase == 'level' then return 0.1 * #st.frames / st.n_frames end
    return 0.1 + 0.9 * (st.next - 1) / math.max(1, #st.frames)
end

-- The notes of a finished analysis: runs of one pitch held at least min_frames.
-- Returns notes { pitch, qn (start, seconds), len (seconds) }, plus { frames, voiced }.
function KeyAudioFinish(st)
    local frames, notes, i = st.frames, {}, 1
    local hop_s = st.hop / st.sr
    while i <= #frames do
        local p = frames[i].pitch
        if p then
            local j = i
            while j + 1 <= #frames and frames[j + 1].pitch == p do j = j + 1 end
            if j - i + 1 >= st.opts.min_frames then
                notes[#notes + 1] = { pitch = p, qn = st.t0 + (frames[i].start - 1) / st.sr,
                                      len = (j - i + 1) * hop_s }
            end
            i = j + 1
        else
            i = i + 1
        end
    end
    return notes, { frames = #frames, voiced = st.voiced }
end

-- All at once: the same steps, run to the end.
function KeyAudioNotes(samples, sr, t0, opts)
    local st = KeyAudioStart(samples, sr, t0, opts)
    while not KeyAudioStep(st, math.huge) do end
    return KeyAudioFinish(st)
end
