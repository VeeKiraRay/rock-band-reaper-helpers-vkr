-- @description Rock Band Helper Test Runner
-- @author VeeKiraRay
-- @about
--   Small launcher window with buttons to run tests.
--   Results appear in the REAPER console. For a fully isolated Lua context with no
--   shared globals, run dev/tests/run_vocal.lua or dev/tests/run_general.lua directly from
--   the REAPER Actions list instead.

r = reaper

if not r.ImGui_CreateContext then
    r.ShowMessageBox(
        'ReaImGui extension is required.',
        'Missing dependency', 0)
    return
end
if not r.ImGui_BeginDisabled then
    r.ShowMessageBox(
        'ReaImGui 0.7 or later is required.',
        'ReaImGui version too old', 0)
    return
end

ctx = r.ImGui_CreateContext('RB Helper Test Runner')

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _tdir   = _dir .. 'tests/'

local results = { vocal = nil, general = nil, vocal_midi = nil, general_midi = nil,
                  dsp_algo = nil, vocal_algo = nil, general_algo = nil,
                  quick_actions = nil, spritesheet = nil, venue_events = nil,
                  venue_subtracks = nil, venue_phrase_pacing = nil,
                  venue_labels = nil, workflow = nil,
                  guitar_theory = nil, music_notation = nil,
                  karplus_strong = nil, wav_writer = nil,
                  script_links = nil, difficulty_score = nil,
                  difficulty_bpm = nil, difficulty_suggester = nil }

local COL_OK  = 0x55DD55FF
local COL_ERR = 0xFF5555FF

local function run(runner_file, result_key)
    -- Save ctx: runner scripts set ctx = nil (they don't use ImGui),
    -- which would break our frame loop. Restore after.
    local _saved_ctx = ctx
    local ok, err = pcall(dofile, _tdir .. runner_file)
    ctx = _saved_ctx
    if not ok then
        r.ShowConsoleMsg('LOAD ERROR: ' .. tostring(err) .. '\n')
        results[result_key] = { load_error = true }
    else
        results[result_key] = { pass = Test._pass, fail = Test._fail }
    end
end

local function draw_status(res)
    if not res then
        r.ImGui_TextDisabled(ctx, '(not run)')
    elseif res.load_error then
        r.ImGui_TextColored(ctx, COL_ERR, 'load error - see console')
    elseif res.fail == 0 then
        local n = tostring(res.pass)
        r.ImGui_TextColored(ctx, COL_OK, n .. '/' .. n .. ' pass')
    else
        local total = res.pass + res.fail
        r.ImGui_TextColored(ctx, COL_ERR,
            res.pass .. '/' .. total .. '  (' .. res.fail .. ' failed)')
    end
end

function Loop()
    r.ImGui_SetNextWindowSizeConstraints(ctx, 340, 580, 9999, 9999)
    r.ImGui_SetNextWindowSize(ctx, 340, 580, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'RB Helper Test Runner', true)
    if visible then
        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Run Vocal Smoke Tests', 155, 24) then
            run('run_vocal.lua', 'vocal')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.vocal)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Run General Smoke Tests', 155, 24) then
            run('run_general.lua', 'general')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.general)

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Vocal MIDI Tests', 155, 24) then
            run('run_vocal_midi.lua', 'vocal_midi')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.vocal_midi)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'General MIDI Tests', 155, 24) then
            run('run_general_midi.lua', 'general_midi')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.general_midi)

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'DSP Algo Tests', 155, 24) then
            run('run_dsp_algorithms.lua', 'dsp_algo')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.dsp_algo)

        if r.ImGui_Button(ctx, 'Accessor Resampling', 155, 24) then
            run('run_accessor_resampling.lua', 'accessor_rs')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.accessor_rs)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Vocal Algo Tests', 155, 24) then
            run('run_vocal_algorithms.lua', 'vocal_algo')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.vocal_algo)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'General Algo Tests', 155, 24) then
            run('run_general_algorithms.lua', 'general_algo')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.general_algo)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Difficulty Score Tests', 155, 24) then
            run('run_difficulty_score.lua', 'difficulty_score')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.difficulty_score)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Difficulty Tempo Tests', 155, 24) then
            run('run_difficulty_bpm.lua', 'difficulty_bpm')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.difficulty_bpm)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Difficulty Suggester Tests', 155, 24) then
            run('run_difficulty_suggester.lua', 'difficulty_suggester')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.difficulty_suggester)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Guitar Theory Tests', 155, 24) then
            run('run_guitar_theory.lua', 'guitar_theory')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.guitar_theory)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Music Notation Tests', 155, 24) then
            run('run_music_notation.lua', 'music_notation')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.music_notation)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Karplus-Strong Tests', 155, 24) then
            run('run_karplus_strong.lua', 'karplus_strong')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.karplus_strong)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'WAV Writer Tests', 155, 24) then
            run('run_wav_writer.lua', 'wav_writer')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.wav_writer)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Script Links Tests', 155, 24) then
            run('run_script_links.lua', 'script_links')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.script_links)

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Quick Action Tests', 155, 24) then
            run('run_quick_actions.lua', 'quick_actions')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.quick_actions)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Spritesheet Coverage', 155, 24) then
            run('run_spritesheet_coverage.lua', 'spritesheet')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.spritesheet)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Events Tests', 155, 24) then
            run('run_venue_events.lua', 'venue_events')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_events)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Subtracks Tests', 155, 24) then
            run('run_venue_subtracks.lua', 'venue_subtracks')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_subtracks)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Phrase Pacing Tests', 155, 24) then
            run('run_venue_phrase_pacing.lua', 'venue_phrase_pacing')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_phrase_pacing)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Labels Tests', 155, 24) then
            run('run_venue_labels.lua', 'venue_labels')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_labels)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Validate Tests', 155, 24) then
            run('run_venue_validate.lua', 'venue_validate')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_validate)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Venue Blends Tests', 155, 24) then
            run('run_venue_blends.lua', 'venue_blends')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.venue_blends)

        r.ImGui_Spacing(ctx)

        if r.ImGui_Button(ctx, 'Workflow Tests', 155, 24) then
            run('run_workflow.lua', 'workflow')
        end
        r.ImGui_SameLine(ctx)
        draw_status(results.workflow)

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, 'Full output in REAPER console')

        r.ImGui_End(ctx)
    end
    if open then r.defer(Loop) end
end

Loop()
