-- Audio preview plumbing shared by every tab of the music theory helper.
--
-- All playback -- recorded drum samples and synthesized chords alike -- goes
-- through the SWS extension's CF_Preview API and shares a single active
-- preview handle in S.preview_src / S.preview_pcm, so starting anything
-- stops whatever was already sounding. See .claude/CLAUDE_music_theory.md
-- for why synthesis-to-WAV was chosen over routing MIDI to a synth.
--
-- Globals (not locals): the Drums and Guitar tabs live in ui.lua, the Piano
-- tab in ui_piano.lua, and all three need these.

-- Stop and free the currently active preview (if any).
-- Tries the combined newer API first, falls back to the two-step older form.
function StopCurrentPreview()
    if S.preview_src then
        if r.CF_Preview_StopAndDestroyPreview then
            r.CF_Preview_StopAndDestroyPreview(S.preview_src)
        else
            r.CF_Preview_Stop(S.preview_src)
        end
        S.preview_src = nil
    end
    if S.preview_pcm then
        r.PCM_Source_Destroy(S.preview_pcm)
        S.preview_pcm = nil
    end
end

-- Preview an audio file at an absolute path via SWS CF_CreatePreview.
-- Returns false if SWS is unavailable, the file is missing, or creation fails.
function PlayPreviewPath(path)
    StopCurrentPreview()
    local pcm = r.PCM_Source_CreateFromFile(path)
    if not pcm then return false end
    local preview = r.CF_CreatePreview(pcm)
    if not preview then r.PCM_Source_Destroy(pcm); return false end
    r.CF_Preview_SetValue(preview, 'B_LOOP', 0)
    r.CF_Preview_SetValue(preview, 'D_VOLUME', 1.0)
    r.CF_Preview_Play(preview)
    S.preview_src = preview
    S.preview_pcm = pcm
    return true
end

-- Synthesize a chord as a short Karplus-Strong WAV and preview it through the
-- same path drum samples use -- zero project mutation, and no dependency on
-- whatever MIDI synth a given machine may or may not have configured.
local SYNTH_SAMPLE_RATE = 44100

-- pitches[] = MIDI note numbers.
--
-- opts.tone names a preset in SYNTH_TONES (lib/reaper_karplus_strong.lua) --
-- 'guitar' if omitted, which is why the Guitar tab's call sites pass no opts
-- at all. Any other key in opts overrides that preset for this one call. The
-- preset supplies the duration too: a struck piano note wants far longer to
-- decay than a plucked guitar chord, and cutting it short is audible.
--
-- Returns false if SWS is unavailable, the pitch list is empty, or the
-- write/preview fails.
function PlaySynthChord(pitches, opts)
    if not AUDIO_CF_AVAILABLE then return false end
    if not pitches or #pitches == 0 then return false end
    -- Stop any current preview BEFORE overwriting SYNTH_PREVIEW_WAV_PATH --
    -- releases whatever hold the previous preview had on that same file,
    -- avoiding a write/read race against REAPER's own file handle.
    StopCurrentPreview()
    local tone_opts = SynthToneOpts(opts and opts.tone, opts)
    local samples = SynthesizeChordSamples(pitches, SYNTH_SAMPLE_RATE,
                                           tone_opts.duration_s, tone_opts)
    if not WriteMonoWAV16(samples, SYNTH_SAMPLE_RATE, SYNTH_PREVIEW_WAV_PATH) then return false end
    return PlayPreviewPath(SYNTH_PREVIEW_WAV_PATH)
end
