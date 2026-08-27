-- @description Rock Band DSP Library - Audio Accessor Resampling Probe
-- @author VeeKiraRay
-- @about
--   Answers whether REAPER's audio accessor honours the samplerate argument
--   to GetAudioAccessorSamples, which is the open question blocking a
--   proposed pitch-engine change (analyse at a fixed 16 kHz).
--   Builds its own WAV fixture, so no project setup is needed - just run it.
--   Creates and removes one temporary track. Results appear in the REAPER
--   console (View > Show REAPER console).

r = reaper

local _ctx_script = ({reaper.get_action_context()})[2]
local _ctx_dir    = _ctx_script:match('^(.+[\\/])')
local _in_dev_tests = _ctx_dir:lower():find('[/\\]dev[/\\]tests[/\\]$')
local _in_dev       = _ctx_dir:lower():find('[/\\]dev[/\\]$')
local function _strip(d)
    return (d:match('^(.+)[/\\]+$') or d):match('^(.+[/\\])') or d
end
local _root = _in_dev_tests and _strip(_strip(_ctx_dir))
           or _in_dev       and _strip(_ctx_dir)
           or _ctx_dir
local _tdir = _root .. 'dev/tests/'

ctx = nil

r.ClearConsole()
r.ShowConsoleMsg('======  Audio accessor - resampling probe  ======\n')

dofile(_tdir .. 'framework.lua')
dofile(_root .. 'lib/reaper_wav_writer.lua')
dofile(_root .. 'lib/reaper_dsp.lua')

dofile(_tdir .. 'accessor_resampling.lua')
Test.report()

r.ShowConsoleMsg(
    '\nIf "THE QUESTION" passed, item 7 (16 kHz analysis) is viable as a\n' ..
    'small change to YINWindowSize + ReadMonoWindow.\n' ..
    'If it failed, the accessor does not resample and item 7 needs a\n' ..
    'hand-rolled anti-alias filter and decimator instead.\n')
