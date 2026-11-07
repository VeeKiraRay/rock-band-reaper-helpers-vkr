-- Keys > Tuner sub-tab: chord names from the keys stem (chord_tuner.lua does the reading).
-- Requires: S, TIPS, r, ctx (globals); TrackCombo (lib/reaper_helper_ui.lua); Btn, BTN_H,
--           Tooltip, SectionHeader, LabelColWidth, RadioGroupWidth, WIDTH_STD, WIDTH_SHORT
--           (lib/reaper_imgui_helpers.lua); ChordName, ChordNameOverBass, ChordUpperTriad,
--           ChordNotes, CHORD_PC_NAMES, ChordTemplateForMask (lib/reaper_chord_detect.lua);
--           PitchName (lib/reaper_imgui_helpers.lua); StartChordTuner, StopChordTuner,
--           ChordTunerReread, RefreshChordTunerProject, CHORD_KEY_MODES (chord_tuner.lua)

local KEY_MODE_LABELS = {
    off = 'Off', vocals = 'From charted vocals', prokeys = 'From charted Pro Keys', manual = 'Manual',
}
local CONF_COLOR = { clear = 0x88FF88FF, likely = 0xFFFFFFFF, maybe = 0xFFC04CFF, unsure = 0xFF8040FF }
local DIM = 0xAAAAAAFF

local function Colored(col, text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
    r.ImGui_Text(ctx, text)
    r.ImGui_PopStyleColor(ctx)
end

-- Pitch classes of a mask as names, from C up: "C E G".
local function PcNames(mask)
    local t = {}
    for pc = 0, 11 do if mask & (1 << pc) ~= 0 then t[#t + 1] = CHORD_PC_NAMES[pc] end end
    return table.concat(t, ' ')
end

-- The read lengths as the Read length buttons name them (2 frames = 0.19 s, 6 = 0.45 s).
local function ReadSeconds(long) return long and '0.45 s' or '0.2 s' end

local function DrawSettings()
    local lbl_col = LabelColWidth({ 'Keys audio', 'Bass audio', 'Song key', 'Read length' })
    local radio_w = RadioGroupWidth({ 'Short (0.2 s)', 'Long (0.45 s)', 'Major', 'Minor' })
    local tracks = S.audio_track_list

    SectionHeader('Tracks')
    r.ImGui_Text(ctx, 'Keys audio')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    local idx = TrackCombo('##ct_keys', S.ct_keys_idx, tracks)
    if idx ~= S.ct_keys_idx then S.ct_keys_idx = idx; ChordTunerReread() end
    Tooltip(TIPS.ct_keys_track)

    r.ImGui_Text(ctx, 'Bass audio')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    idx = TrackCombo('##ct_bass', S.ct_bass_idx, tracks)
    if idx ~= S.ct_bass_idx then S.ct_bass_idx = idx; ChordTunerReread() end
    Tooltip(TIPS.ct_bass_track)

    SectionHeader('Reading')
    r.ImGui_Text(ctx, 'Song key')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##ct_keymode', KEY_MODE_LABELS[S.ct_key_mode]) then
        for _, m in ipairs(CHORD_KEY_MODES) do
            if r.ImGui_Selectable(ctx, KEY_MODE_LABELS[m], m == S.ct_key_mode) and m ~= S.ct_key_mode then
                S.ct_key_mode = m
                ChordTunerReread()
            end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.ct_key_mode)
    if S.ct_key_mode == 'manual' then
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
        if r.ImGui_BeginCombo(ctx, '##ct_keytonic', CHORD_PC_NAMES[S.ct_key_tonic]) then
            for pc = 0, 11 do
                if r.ImGui_Selectable(ctx, CHORD_PC_NAMES[pc], pc == S.ct_key_tonic) and pc ~= S.ct_key_tonic then
                    S.ct_key_tonic = pc
                    ChordTunerReread()
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SetCursorPosX(ctx, lbl_col)
        if r.ImGui_RadioButton(ctx, 'Major##ct_maj', not S.ct_key_minor) and S.ct_key_minor then
            S.ct_key_minor = false
            ChordTunerReread()
        end
        r.ImGui_SameLine(ctx, lbl_col + radio_w)
        if r.ImGui_RadioButton(ctx, 'Minor##ct_min', S.ct_key_minor) and not S.ct_key_minor then
            S.ct_key_minor = true
            ChordTunerReread()
        end
    end
    -- The key in use, or why the chosen source gave none.
    r.ImGui_SetCursorPosX(ctx, lbl_col)
    if S.ct_key_mode == 'off' then
        r.ImGui_TextDisabled(ctx, 'No key used.')
    elseif S.ct_key then
        r.ImGui_TextDisabled(ctx, 'Using ' .. S.ct_key.name .. '.')
    else
        r.ImGui_TextDisabled(ctx, 'No key: ' .. (S.ct_key_why or 'not found') .. '.')
    end

    r.ImGui_Text(ctx, 'Read length')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Short (0.2 s)##ct_short', not S.ct_read_long) and S.ct_read_long then
        S.ct_read_long = false
        ChordTunerReread()
    end
    Tooltip(TIPS.ct_read_length)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Long (0.45 s)##ct_long', S.ct_read_long) and not S.ct_read_long then
        S.ct_read_long = true
        ChordTunerReread()
    end
    Tooltip(TIPS.ct_read_length)

    local changed, plain = r.ImGui_Checkbox(ctx, 'Prefer plain chords##ct_plain', S.ct_plain)
    if changed then
        S.ct_plain = plain
        ChordTunerReread()
    end
    Tooltip(TIPS.ct_plain)

    changed, plain = r.ImGui_Checkbox(ctx, 'Passage check (single notes or chords?)##ct_pass', S.ct_passage)
    if changed then
        S.ct_passage = plain
        ChordTunerReread()
    end
    Tooltip(TIPS.ct_passage)
end

local READOUT_LABELS = { 'Charted:', 'Single:', 'Chord:', 'Top 3:', 'Chords:', 'Notes:' }
local PRIMARY = 0xFFFFFFFF

-- One readout row: a label in the shared column, then the value; each in its own colour.
local function Row(lbl_col, label, label_col, col, text)
    Colored(label_col, label)
    r.ImGui_SameLine(ctx, lbl_col)
    Colored(col, text)
end

-- The passage verdict for this reading (stopped only), or nil.
local function PassageNow(res)
    local p = S.ct_passage and S.ct_pass
    if not p or res.kind == 'playing' or p.pos ~= res.pos then return nil end
    return p
end

local function DrawReadout(lbl_col)
    local res = S.ct_result
    if not res then
        r.ImGui_TextWrapped(ctx, S.ct_active
            and 'Park the edit cursor on a chord, or play.'
            or 'Start the tuner, then park the edit cursor on a chord or play.')
        return
    end
    if res.kind == 'noaudio' then
        r.ImGui_TextWrapped(ctx, 'No keys audio at this position.')
        return
    end
    if not res.top then
        if res.busy then r.ImGui_TextDisabled(ctx, 'Reading...')
        else r.ImGui_TextWrapped(ctx, 'Quiet - nothing to read here.') end
        return
    end
    local best = res.top[1]

    -- Charted first, always in the primary colour: what the chart already says here.
    if res.chart and res.chart.mask and res.chart.mask ~= 0 then
        local t = ChordTemplateForMask(res.chart.mask)
        -- As a chord when the charted notes make one (in chord order), else the notes from C up.
        Row(lbl_col, 'Charted:', PRIMARY, PRIMARY, t and ('%s (%s)'):format(ChordName(t), ChordNotes(t))
                                                  or (PcNames(res.chart.mask):gsub(' ', '+')))
    elseif res.kind == 'fixed' then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), DIM)
        r.ImGui_TextWrapped(ctx, TIPS.ct_hint_nochart:format(ReadSeconds(S.ct_read_long)))
        r.ImGui_PopStyleColor(ctx)
    end
    r.ImGui_Spacing(ctx)

    -- Which reading the passage check favours: the other one - label, value and (for the
    -- chord) its confidence and top three - is dimmed.
    local p = PassageNow(res)
    local single_col, chord_col = PRIMARY, PRIMARY
    if p and not p.busy and p.single ~= nil then
        if p.single then chord_col = DIM else single_col = DIM end
    end

    -- Single: the reading as one note, then the passage verdict.
    Row(lbl_col, 'Single:', single_col, single_col, res.single and PitchName(res.single) or '-')
    Tooltip(TIPS.ct_single)
    if p then
        r.ImGui_SameLine(ctx)
        if p.busy then
            r.ImGui_TextDisabled(ctx, '(passage: reading the next 4 s...)')
        elseif p.single == nil then
            r.ImGui_TextDisabled(ctx, '(passage: no key presses found)')
        elseif p.single then
            Colored(0x66CCFFFF, '(passage: looks like single notes)')
        else
            Colored(DIM, '(passage: looks like chords)')
        end
        Tooltip(TIPS.ct_passage_line)
    end

    -- Chord: over the bass, its notes, the other reading when it differs, confidence.
    Row(lbl_col, 'Chord:', chord_col, chord_col, ('%s (%s)'):format(ChordNameOverBass(best, res.bass), ChordNotes(best)))
    if res.other then
        r.ImGui_SameLine(ctx)
        Colored(DIM, '(' .. ChordName(res.other) .. '?)')
    end
    r.ImGui_SameLine(ctx)
    Colored(chord_col == DIM and DIM or CONF_COLOR[res.conf], res.conf .. (res.busy and ', reading...' or ''))
    Tooltip(TIPS.ct_confidence)

    local top3 = {}
    for k = 1, 3 do top3[k] = ('%s (%s)'):format(ChordName(res.top[k]), ChordNotes(res.top[k])) end
    Row(lbl_col, 'Top 3:', chord_col, DIM, table.concat(top3, '   '))

    -- A 7th chord: the triad above its root, which a one-hand Pro Keys part often plays.
    local upper = ChordUpperTriad(best)
    if upper then
        r.ImGui_SetCursorPosX(ctx, lbl_col)
        Colored(DIM, ('%s = %s over %s: triad %s, root %s'):format(ChordName(best), ChordName(upper),
            CHORD_PC_NAMES[best.root], PcNames(upper.mask), CHORD_PC_NAMES[best.root]))
    end
end

function DrawKeysTunerTab()
    RefreshChordTunerProject(false)   -- the chart and key (polled; cheap when nothing changed)
    r.ImGui_Spacing(ctx)
    DrawSettings()

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    SectionHeader('Chord Tuner')
    local active = S.ct_active
    if active then
        if Btn('Stop Tuner##ct', BTN_H) then StopChordTuner('Chord tuner stopped.') end
    else
        local no_keys = S.ct_keys_idx < 0
        if no_keys then r.ImGui_BeginDisabled(ctx) end
        if Btn('Start Tuner##ct', BTN_H) then StartChordTuner() end
        if no_keys then r.ImGui_EndDisabled(ctx) end
    end
    Tooltip(TIPS.ct_toggle)
    r.ImGui_SameLine(ctx)
    Colored(active and 0x88FF88FF or 0x888888FF, active and 'Tuner: Active' or 'Tuner: Stopped')

    r.ImGui_Separator(ctx)
    local lbl_col = LabelColWidth(READOUT_LABELS)
    DrawReadout(lbl_col)

    -- Histories, oldest first, so they read like the part.
    if #S.ct_history > 0 or #S.ct_note_history > 0 then
        r.ImGui_Spacing(ctx)
        Row(lbl_col, 'Chords:', PRIMARY, DIM, table.concat(S.ct_history, '  '))
        Row(lbl_col, 'Notes:', PRIMARY, DIM, table.concat(S.ct_note_history, '  '))
    end
end
