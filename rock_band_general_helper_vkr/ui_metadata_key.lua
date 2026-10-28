-- Metadata > Song key sub-tab body.
--
-- TWO MODES, picked with a radio row, each with its own button and results so the author
-- reads one source at a time rather than a wall of guesses that may not agree:
--
-- CHARTED MIDI (the default). Four results side by side - PART VOCALS alone, plus
-- harmonies, plus Pro Keys, and Pro Keys alone as an independent check - rather than one
-- blend, so the author can weigh each input (Pro Keys is often not charted; a live vocal
-- take can be off key; a harmony a third above the melody can pull the answer toward the
-- relative key). Then CHECK A KEY: any key - a suggestion (its Check button) or one from
-- Tunebat, a chord chart or the author's ear - against each charted track on its own: the
-- share of notes outside the key, and those notes with their bars. That share is what the
-- data says matters (see KeyTrackReport); which of the key's notes a track uses mostly
-- does not, so there is no "found in key" list - only a note when a track uses so few
-- that many keys fit.
--
-- AUDIO STEMS (experimental). A vocal and a bass track, and one result: vocal + bass when
-- both give enough notes, else whichever does (song_key_audio.lua). It runs as a job over
-- several UI frames, with a progress bar and Cancel, advanced by SongKeyTick from the
-- window's Loop - so it keeps going while another tab is shown. No outside-the-key
-- list: pitch tracking smears a correct recording's notes across neighbouring semitones.
-- Its Check buttons switch to MIDI mode with that key loaded.
--
-- A key's notes are in its tooltip rather than a row, so the runner-up's are there too.
--
-- READ-ONLY, like the rest of the Metadata tab: nothing is written and there is no
-- "apply" control. No accuracy percentage is shown: the reference values it was fitted to
-- are one charter's judgement, and a result is only as good as its chart or recording.
--
-- Results are drawn inline from session-only S.key_suggestion (MIDI) and S.key_audio
-- (audio), both cleared on project switch, not into S.last_result, which ui.lua wipes on
-- any main-tab change. The mode and the checked key are session-only too.
--
-- Requires globals: r, ctx, S, TIPS, Btn, BTN_H, WIDTH_SHORT, WIDTH_STD, Tooltip,
--                   SectionHeader, LabelColWidth, RunAction, TrackCombo
--                   (lib/reaper_helper_ui.lua), SuggestProjectSongKey (song_key.lua),
--                   SongKeyAudioStart, SongKeyAudioStep, SongKeyAudioBusy,
--                   SongKeyAudioCancel (song_key_audio.lua),
--                   KeyName, KeyRelation, KeyScaleText, KeyTrackReport, KEY_TONIC_NAMES,
--                   KEY_MIN_NOTES, KEY_FEW_NOTES (lib/reaper_key_detect.lua)

local COL_WARN = 0xFFAA00FF
local COL_DIM  = 0x9A9A9AFF

-- Bars listed per note outside the key before the rest are summarized as "+N more".
local MAX_BARS = 8

-- A track with at least this share of its notes outside the checked key gets the share in
-- amber: past it, the key itself is more likely wrong than right (see TIPS.key_share_out).
local SHARE_OUT_WARN = 0.15

local function DimWrapped(text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_DIM)
    r.ImGui_TextWrapped(ctx, text)
    r.ImGui_PopStyleColor(ctx)
end

local function WarnWrapped(text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_WARN)
    r.ImGui_TextWrapped(ctx, text)
    r.ImGui_PopStyleColor(ctx)
end

local RELATION_TEXT = {
    relative = 'the relative %s - the same notes, a different home note',
    parallel = 'the parallel %s - the same home note, a different scale',
    fifth    = 'a fifth away',
}

local CONFIDENCE_TEXT = {
    clear = 'Clear lead over the runner-up.',
    fair  = 'Moderate lead - worth trying the runner-up too.',
    close = 'Close call - the runner-up fits about as well. Decide by ear.',
}

local UNAVAILABLE_TEXT = {
    no_vocals = 'Needs at least %d pitched PART VOCALS notes.',
    no_harm   = 'No harmony notes (HARM1-3) in this project.',
    no_keys   = 'No Pro Keys chart (PART REAL_KEYS_X) with at least %d notes in this project.',
}

-- The audio result's reasons (SuggestAudioSongKey).
local AUDIO_UNAVAILABLE_TEXT = {
    no_track = 'Pick a vocal track, a bass track or both above.',
    no_items = 'The picked tracks have no audio on them.',
    no_notes = 'Too few pitched notes found on the picked tracks. Are they isolated stems, ' ..
               'with the singing or the bass line on them?',
    changed  = 'Stopped: an item on the picked tracks was removed while reading. Press ' ..
               'Suggest song key again.',
}

-- A line under a result's title for the Pro Keys-only check.
local SET_NOTE_TIP = { keysonly = 'key_keys_only' }

local MODE_LABELS = { 'Charted MIDI', 'Audio stems (experimental)' }

-- The key check's reports, rebuilt only when the result or the checked key changes.
local _check = { res = nil, tonic = nil, minor = nil, reports = nil }

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

-- MIDI mode, on demand rather than per frame: it walks every note on five tracks.
-- keep_check: leave the checked key alone (an audio Check button set it).
local function RefreshSongKey(keep_check)
    S.last_result = nil   -- the results are drawn in-tab
    local res = SuggestProjectSongKey()
    S.key_suggestion = res

    -- The fullest charted result available goes to the status line (so the footer's Copy
    -- result carries it) and becomes the checked key. Pro Keys alone is a second opinion,
    -- used only when nothing else is available.
    for _, i in ipairs({ 3, 2, 1, 4 }) do
        local x = res.sets[i]
        if x and x.ranked then
            local top = x.ranked[1]
            if not keep_check then S.key_check_tonic, S.key_check_minor = top.tonic, top.minor end
            S.status = ('Song key: %s (%s).'):format(KeyName(top.tonic, top.minor), x.label)
            return
        end
    end
    S.status = 'Song key: not enough pitched notes to suggest a key.'
end

-- Audio mode: a job over several UI frames (song_key_audio.lua), so the window stays
-- responsive; SongKeyTick, called by the Loop, advances it and stores the result.
local function SetAudioResult(res)
    S.key_audio = res
    if res.ranked then
        local top = res.ranked[1]
        S.status = ('Song key: %s (%s).'):format(KeyName(top.tonic, top.minor), res.label)
    elseif res.why == 'changed' then
        S.status = 'Song key: stopped - an item on the picked tracks was removed.'
    else
        S.status = 'Song key: no key from the audio.'
    end
end

local function RefreshAudioSongKey()
    S.last_result = nil
    S.key_audio = nil
    local res = SongKeyAudioStart(S.key_audio_idx, S.key_bass_idx)
    if res then SetAudioResult(res) else S.status = 'Song key: reading the audio...' end
end

-- Per-frame share of the audio job, in seconds. ~20 ms keeps the window at a usable
-- frame rate on a slow machine while the job still finishes in a few seconds.
local TICK_BUDGET_S = 0.02

-- Called by the window's Loop every frame, whichever tab is showing.
function SongKeyTick()
    local res = SongKeyAudioStep(TICK_BUDGET_S)
    if res then SetAudioResult(res) end
end

----------------------------------------------------------------------
-- A result
----------------------------------------------------------------------

-- One key row: label, key name (tooltip: its notes), and a Check button that loads it
-- into Check a key - switching to MIDI mode first when pressed from audio.
local function KeyRow(row_x, lbl_col, label, key, extra, tip, id, from_audio)
    r.ImGui_TextDisabled(ctx, label)
    r.ImGui_SameLine(ctx, row_x + lbl_col)
    r.ImGui_Text(ctx, KeyName(key.tonic, key.minor))
    Tooltip('Key notes: ' .. KeyScaleText(key.tonic, key.minor) .. (tip and ('\n\n' .. tip) or ''))
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, 'Check##' .. id) then
        S.key_check_tonic, S.key_check_minor = key.tonic, key.minor
        if from_audio then
            S.key_mode = 1
            if not S.key_suggestion then RunAction(function() RefreshSongKey(true) end) end
        end
    end
    Tooltip(from_audio and TIPS.key_check_button_audio or TIPS.key_check_button)
    if extra then
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, extra)
    end
end

local function DrawSuggestion(x, id, lbl_col, unavailable, from_audio)
    r.ImGui_Text(ctx, x.label)
    r.ImGui_Indent(ctx)

    if not x.ranked then
        DimWrapped((unavailable[x.why] or 'Not available.'):format(KEY_MIN_NOTES))
        r.ImGui_Unindent(ctx)
        return
    end
    local note = x.set and SET_NOTE_TIP[x.set.key]
    if note then DimWrapped(TIPS[note]) end

    local top, second = x.ranked[1], x.ranked[2]
    local row_x = r.ImGui_GetCursorPosX(ctx)   -- includes the indent

    KeyRow(row_x, lbl_col, 'Suggested', top, nil, TIPS.key_suggested, 's' .. id, from_audio)
    local rel = KeyRelation(top.tonic, top.minor, second.tonic, second.minor)
    KeyRow(row_x, lbl_col, 'Runner-up', second,
           rel and ('(' .. RELATION_TEXT[rel]:format(second.minor and 'minor' or 'major') .. ')'),
           nil, 'r' .. id, from_audio)

    if x.confidence == 'close' then
        WarnWrapped(CONFIDENCE_TEXT.close)
    else
        DimWrapped(CONFIDENCE_TEXT[x.confidence])
    end

    r.ImGui_Unindent(ctx)
end

----------------------------------------------------------------------
-- MIDI mode
----------------------------------------------------------------------

-- Lines about PART VOCALS itself, above the results: a missing or all-unpitched part
-- explains why the vocal results are unavailable, which a bare "unavailable" would not.
local function DrawVocalsNote(parts)
    local v = parts.vocals
    if not v.found then
        WarnWrapped('No PART VOCALS track in this project. Chart the vocals first, or try ' ..
                    'the audio stems mode.')
    elseif v.notes == 0 and v.unpitched > 0 then
        WarnWrapped(('Every PART VOCALS note is marked unpitched (#), %d in all. A part with ' ..
                     'no sung pitches gives no key to suggest, and may not need one. If ' ..
                     'it does, use a Pro Keys result below or your ear.'):format(v.unpitched))
    elseif v.notes == 0 then
        WarnWrapped('PART VOCALS has no notes yet. Chart the vocals first, or try the audio ' ..
                    'stems mode.')
    elseif v.notes < KEY_MIN_NOTES then
        WarnWrapped(('PART VOCALS has only %d pitched notes - too few to suggest a key ' ..
                     'from.'):format(v.notes))
    elseif v.unpitched > 0 then
        DimWrapped(('%d unpitched PART VOCALS notes (#) were left out.'):format(v.unpitched))
    end
end

-- "G#: 14 notes, bars 12, 20, 44, +3 more".
local function OutsideLine(o)
    local bars = {}
    for i = 1, math.min(#o.bars, MAX_BARS) do bars[i] = tostring(o.bars[i]) end
    local more = #o.bars > MAX_BARS and (', +%d more'):format(#o.bars - MAX_BARS) or ''
    return ('%s: %d note%s%s'):format(o.name, o.n, o.n == 1 and '' or 's',
        #bars > 0 and (', bar' .. (#o.bars == 1 and ' ' or 's ') .. table.concat(bars, ', ') .. more) or '')
end

local function CheckReports(res, tonic, minor)
    if _check.res ~= res or _check.tonic ~= tonic or _check.minor ~= minor then
        local reports = {}
        for i, t in ipairs(res.tracks) do reports[i] = KeyTrackReport(t.notes, tonic, minor) end
        _check = { res = res, tonic = tonic, minor = minor, reports = reports }
    end
    return _check.reports
end

local function DrawTrackCheck(t, rep)
    r.ImGui_Text(ctx, t.label)
    r.ImGui_Indent(ctx)
    if not t.found then
        DimWrapped('No track.')
    elseif rep.total == 0 then
        DimWrapped(t.unpitched > 0
            and ('No pitched notes (%d unpitched).'):format(t.unpitched)
            or 'No notes.')
    else
        -- "Under 1%" rather than a rounded "0%" above a list of notes.
        local pct = rep.share_out < 0.005 and 'Under 1%' or ('%.0f%%'):format(100 * rep.share_out)
        local line = ('%s of %d notes outside the key.'):format(pct, rep.total)
        if #rep.outside == 0 then
            DimWrapped(('No notes outside the key (%d notes).'):format(rep.total))
        elseif rep.share_out >= SHARE_OUT_WARN then
            WarnWrapped(line)
            Tooltip(TIPS.key_share_out)
        else
            r.ImGui_TextWrapped(ctx, line)
            Tooltip(TIPS.key_share_out)
        end
        if rep.used <= KEY_FEW_NOTES then
            DimWrapped(('Uses only %d of the key\'s notes, so many keys fit this track.'):format(rep.used))
        end
        for _, o in ipairs(rep.outside) do
            r.ImGui_TextWrapped(ctx, OutsideLine(o))
        end
    end
    r.ImGui_Unindent(ctx)
end

local function DrawKeyCheck(res)
    SectionHeader('Check a key')
    r.ImGui_TextWrapped(ctx,
        'Pick any key - a suggestion (its Check button), or one from Tunebat, a chord chart ' ..
        'or your ear - to see, track by track, which charted notes fall outside it.')
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Key', 'Key notes' })
    local tonic = S.key_check_tonic or 0
    local minor = S.key_check_minor and true or false

    r.ImGui_Text(ctx, 'Key')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
    if r.ImGui_BeginCombo(ctx, '##key_check_tonic', KEY_TONIC_NAMES[tonic]) then
        for pc = 0, 11 do
            if r.ImGui_Selectable(ctx, KEY_TONIC_NAMES[pc], pc == tonic) then
                S.key_check_tonic = pc
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.key_check_pick)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Major##key_check', not minor) then S.key_check_minor = false end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Minor##key_check', minor) then S.key_check_minor = true end

    tonic = S.key_check_tonic or 0
    minor = S.key_check_minor and true or false
    r.ImGui_Text(ctx, 'Key notes')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_Text(ctx, KeyScaleText(tonic, minor))
    Tooltip(TIPS.key_scale)

    local reports = CheckReports(res, tonic, minor)
    for i, t in ipairs(res.tracks) do
        r.ImGui_Spacing(ctx)
        DrawTrackCheck(t, reports[i])
    end
end

local function DrawMidiMode()
    r.ImGui_TextWrapped(ctx,
        'Reads PART VOCALS, HARM1-3 and Pro Keys (PART REAL_KEYS_X). It can only be as ' ..
        'accurate as the chart it reads - stray or mis-pitched notes can pull it off.')
    r.ImGui_Spacing(ctx)

    if Btn('Suggest song key##midi', BTN_H) then
        RunAction(function() RefreshSongKey(false) end)
    end
    Tooltip(TIPS.key_analyze)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    local res = S.key_suggestion
    if not res then
        r.ImGui_TextWrapped(ctx, 'No suggestion yet. Press Suggest song key to read the chart.')
        return
    end

    DrawVocalsNote(res.parts)
    local lbl_col = LabelColWidth({ 'Suggested', 'Runner-up' })
    for i, x in ipairs(res.sets) do
        r.ImGui_Spacing(ctx)
        DrawSuggestion(x, 'm' .. i, lbl_col, UNAVAILABLE_TEXT, false)
    end

    r.ImGui_Spacing(ctx)
    DimWrapped('The results can disagree, and none of them is the final word. The ' ..
               'usual mix-ups are the relative key (C major and A minor share every note) ' ..
               'and the parallel key (C major and C minor share the home note) - if a ' ..
               'suggestion sounds wrong, try those first. Re-run after editing the chart.')

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    DrawKeyCheck(res)
end

----------------------------------------------------------------------
-- Audio mode
----------------------------------------------------------------------

-- "Vocal: VOCALS AUDIO, 3:12 read, 410 notes" for the line under the result.
local function TrackLine(label, t)
    if not t.picked then return nil end
    if t.items == 0 then return ('%s: %s, no audio on it'):format(label, t.name or '?') end
    return ('%s: %s, %d:%02d read, %d notes'):format(label, t.name or '?',
        math.floor(t.seconds / 60), math.floor(t.seconds % 60), t.notes)
end

local function DrawAudioMode()
    r.ImGui_TextWrapped(ctx,
        'Reads the recordings on a vocal track and a bass track - each must hold that ' ..
        'part on its own: a stem, or one separated from the song with a stem-splitting ' ..
        'tool. Not the full mix: with every instrument in it, the result means nothing. ' ..
        'Experimental: useful before the vocals are charted, and as a second opinion ' ..
        'after.')
    r.ImGui_Spacing(ctx)

    -- Snapshotted once: the Suggest or Cancel button below changes it mid-frame, which
    -- would leave BeginDisabled without its EndDisabled.
    local busy, frac, label = SongKeyAudioBusy()

    if busy then r.ImGui_BeginDisabled(ctx) end
    local lbl_col = LabelColWidth({ 'Vocal track', 'Bass track' })
    r.ImGui_Text(ctx, 'Vocal track')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.key_audio_idx = TrackCombo('##key_audio_track', S.key_audio_idx, S.audio_track_list or {})
    Tooltip(TIPS.key_audio_track)

    r.ImGui_Text(ctx, 'Bass track')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.key_bass_idx = TrackCombo('##key_bass_track', S.key_bass_idx, S.audio_track_list or {})
    Tooltip(TIPS.key_bass_track)
    r.ImGui_Spacing(ctx)

    if Btn('Suggest song key##audio', BTN_H) then
        RunAction(RefreshAudioSongKey)
    end
    Tooltip(TIPS.key_analyze_audio)
    if busy then r.ImGui_EndDisabled(ctx) end

    if busy then
        r.ImGui_SameLine(ctx)
        if Btn('Cancel##key_audio', BTN_H) then
            SongKeyAudioCancel()
            S.status = 'Song key: cancelled.'
        end
        r.ImGui_ProgressBar(ctx, frac, WIDTH_STD, 0, ('%s %d%%'):format(label, math.floor(frac * 100)))
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    local res = S.key_audio
    if not res then
        r.ImGui_TextWrapped(ctx, busy and 'Reading the audio - the result appears here when it is done.'
            or 'No suggestion yet. Pick the tracks and press Suggest song key.')
        return
    end

    res.label = res.label or 'Audio stems'
    DrawSuggestion(res, 'a', LabelColWidth({ 'Suggested', 'Runner-up' }), AUDIO_UNAVAILABLE_TEXT, true)
    for _, l in ipairs({ TrackLine('Vocal', res.vocal), TrackLine('Bass', res.bass) }) do
        if l then DimWrapped(l) end
    end

    r.ImGui_Spacing(ctx)
    DimWrapped('Verify it by ear, and against the chart once there is one: Check loads a ' ..
               'key into the charted MIDI mode to show which charted notes fall outside it.')
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

function DrawMetadataKeyTab(ctx)
    SectionHeader('Suggested song key (Beta)')

    r.ImGui_TextWrapped(ctx,
        'Suggests the vocal tonic note and whether the song is major or minor. Treat it ' ..
        'as a starting point and always verify it by ear or against a chord chart. The ' ..
        'whole song is read - a time selection does not change the result.')
    r.ImGui_Spacing(ctx)

    -- The source. One at a time, so the screen shows one set of answers.
    local mode = S.key_mode or 1
    r.ImGui_Text(ctx, 'Read from')
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, MODE_LABELS[1] .. '##key_mode', mode == 1) then S.key_mode = 1 end
    Tooltip(TIPS.key_mode_midi)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, MODE_LABELS[2] .. '##key_mode', mode == 2) then S.key_mode = 2 end
    Tooltip(TIPS.key_mode_audio)
    r.ImGui_Spacing(ctx)

    if (S.key_mode or 1) == 2 then
        DrawAudioMode()
    else
        DrawMidiMode()
    end
end
