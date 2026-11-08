-- Animation tab: DrawAnimationTab (the sub-tab bar), the Beat and Character
-- sub-tabs. Drums, Keys and Guitar sub-tabs are planned; each comes with its
-- own feature.
-- Requires globals: r, ctx, S, TIPS, Tooltip, SliderTooltip, Btn, BtnGroupWidth,
--                   BTN_H, WIDTH_STD, LabelColWidth, SectionHeader, RunAction,
--                   MakeProjectPoll, FindTrackByName, FindFirstMIDIItem,
--                   GenerateBeatTrack, CHAR_STATES, CHAR_ACTIVE_CHOICES, CHAR_GROUPS,
--                   CHAR_PARTS, CHAR_STATE_SET, CHAR_RIDE_EVENTS, CHAR_RIDE_SET,
--                   CharStateLabel, CharStateDesc,
--                   BeginVenueTooltip, EndVenueTooltip, DrawVenueTooltipSprite
--                   (venue_sprites.lua - the shared tooltip layout and sprites),
--                   CharGroupStatus, CharacterStateAt,
--                   GenerateCharacterAnimations, InsertCharacterState

local function DrawAnimationBeatTab()
    r.ImGui_TextWrapped(ctx, 'Writes the BEAT track from measure 1 up to [end], or inside ' ..
                             'the time selection: a downbeat note (12) on each bar\'s first ' ..
                             'beat, an upbeat note (13) on the others. Existing BEAT notes in ' ..
                             'that range are replaced.')
    r.ImGui_Spacing(ctx)

    SectionHeader('Generate')
    local labels = { 'Generate beats', 'Generate half-time beats' }
    local bw = BtnGroupWidth(labels)
    if Btn(labels[1], BTN_H, bw) then
        RunAction(function() GenerateBeatTrack(false) end)
    end
    Tooltip(TIPS.anim_beat_full)
    r.ImGui_SameLine(ctx)
    if Btn(labels[2], BTN_H, bw) then
        RunAction(function() GenerateBeatTrack(true) end)
    end
    Tooltip(TIPS.anim_beat_half)

    r.ImGui_Text(ctx, 'Half-time downbeat')
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Every other bar##beat_hs', S.beat_half_style == 0) then
        S.beat_half_style = 0
    end
    Tooltip(TIPS.anim_beat_half_style)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Every bar##beat_hs', S.beat_half_style == 1) then
        S.beat_half_style = 1
    end
    Tooltip(TIPS.anim_beat_half_style)
end

-- Character sub-tab. Track presence / mute and the state at the playhead are
-- read behind MakeProjectPoll; the playhead readout also refreshes when the
-- cursor or the picked part changes.
local _char_poll = MakeProjectPoll(1.0, 5.0)
local _char_groups = {}            -- CharGroupStatus() result
local _readout, _readout_key = nil, nil

-- A state's tooltip, laid out like Venue > Manual gen's Directed camera: the
-- animation sprite (when a sheet exists), the RBN description, then the event
-- text. No label line: the dropdown or readout already shows it. Shown only while the last item is hovered.
-- Sheets go in resources/img/spritesheets/animation/ as
-- {part}{state}_f{frames}_spritesheet.jpg (e.g. guitarplay, vocalsidlerealtime;
-- part = a CHAR_GROUPS key), or {state}_f{frames}_spritesheet.jpg for every
-- part (e.g. idle). No sheet: the tooltip is text only.
local function StateTooltip(msg, group, vocal)
    if not r.ImGui_IsItemHovered(ctx) then return end
    if not BeginVenueTooltip() then return end
    local bare = msg:sub(2, -2)
    if not (group and DrawVenueTooltipSprite('Animation', group .. '_' .. bare)) then
        DrawVenueTooltipSprite('Animation', bare)
    end
    r.ImGui_Text(ctx, CharStateDesc(msg, vocal))
    r.ImGui_Separator(ctx)
    r.ImGui_TextDisabled(ctx, msg)
    EndVenueTooltip()
end

-- A dropdown of the active states (Play / Mellow / Intense), each entry with
-- its state tooltip; hovering the closed dropdown shows the current state's.
-- group = a CHAR_GROUPS key for the sprite, or nil (Set all).
-- Returns the picked index (0-based) or nil.
local function ActiveCombo(id, preview, group, vocal)
    local picked
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, id, preview) then
        for i, msg in ipairs(CHAR_ACTIVE_CHOICES) do
            if r.ImGui_Selectable(ctx, CharStateLabel(msg) .. id .. i, CharStateLabel(msg) == preview) then
                picked = i - 1
            end
            StateTooltip(msg, group, vocal)
        end
        r.ImGui_EndCombo(ctx)
    elseif group then
        for _, msg in ipairs(CHAR_ACTIVE_CHOICES) do
            if CharStateLabel(msg) == preview then StateTooltip(msg, group, vocal) end
        end
    end
    return picked
end

-- _readout = { msg, where } for the Manual part at the edit cursor, or nil
-- when the part has no MIDI item. where = 'on the playhead' or 'from <bar>'.
local function RefreshReadout(force)
    local p = CHAR_PARTS[S.char_manual_part]
    local t = r.GetCursorPosition()
    local key = tostring(S.char_manual_part) .. '@' .. t
    if not force and key == _readout_key then return end
    _readout_key = key
    _readout = nil
    local track = p and FindTrackByName(p.track)
    local take
    if track then _, take = FindFirstMIDIItem(track) end
    if not take then return end
    local cur_ppq = r.MIDI_GetPPQPosFromProjTime(take, t)
    local msg, ppq = CharacterStateAt(take, cur_ppq)
    if not msg then
        _readout = { none = true }
    elseif math.abs(ppq - cur_ppq) < 0.5 then
        _readout = { msg = msg, exact = true, where = 'on the playhead' }
    else
        _readout = { msg = msg, where = 'from ' ..
                     r.format_timestr_pos(r.MIDI_GetProjTimeFromPPQPos(take, ppq), '', 1) }
    end
    -- A ride option exactly on the playhead (drives Insert / Replace for those).
    local ride, ride_ppq = CharacterStateAt(take, cur_ppq, CHAR_RIDE_SET)
    _readout.ride_exact = ride ~= nil and math.abs(ride_ppq - cur_ppq) < 0.5
end

local function DrawCharacterGenerate(lbl_col)
    r.ImGui_Text(ctx, 'Set all')
    r.ImGui_SameLine(ctx, lbl_col)
    local all = ActiveCombo('##char_all', '(choose)', nil, false)
    if all then
        for _, g in ipairs(CHAR_GROUPS) do S.char_active[g.key] = all end
    end
    Tooltip(TIPS.char_set_all)

    for _, g in ipairs(CHAR_GROUPS) do
        local reason = _char_groups[g.key]   -- snapshot: drives Begin/EndDisabled
        if reason then r.ImGui_BeginDisabled(ctx) end
        r.ImGui_Text(ctx, g.label)
        r.ImGui_SameLine(ctx, lbl_col)
        local cur = CharStateLabel(CHAR_ACTIVE_CHOICES[(S.char_active[g.key] or 0) + 1])
        local v = ActiveCombo('##char_' .. g.key, cur, g.key, g.vocal)
        if v then S.char_active[g.key] = v end
        if reason then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, '(' .. reason .. ')')
            r.ImGui_EndDisabled(ctx)
        end
    end

    r.ImGui_Text(ctx, 'Instrument idle gap')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.char_gap_inst_bars = r.ImGui_SliderInt(ctx, '##char_gap_inst', S.char_gap_inst_bars,
                                                1, 8, '%d bars')
    SliderTooltip(TIPS.char_gap_inst)
    r.ImGui_Text(ctx, 'Vocal idle gap')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.char_gap_vox_bars = r.ImGui_SliderInt(ctx, '##char_gap_vox', S.char_gap_vox_bars,
                                               1, 8, '%d bars')
    SliderTooltip(TIPS.char_gap_vox)
    _, S.char_idle_gaps = r.ImGui_Checkbox(ctx, 'Idle in long gaps##char_idle', S.char_idle_gaps)
    Tooltip(TIPS.char_idle_gaps)

    r.ImGui_Spacing(ctx)
    if Btn('Generate character animations', BTN_H) then
        RunAction(GenerateCharacterAnimations)
        _readout_key = nil
    end
    Tooltip(TIPS.char_generate)
end

local function DrawCharacterManual(lbl_col)
    -- Part
    r.ImGui_Text(ctx, 'Part')
    r.ImGui_SameLine(ctx, lbl_col)
    local p = CHAR_PARTS[S.char_manual_part] or CHAR_PARTS[1]
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##char_part', p.label) then
        for i, q in ipairs(CHAR_PARTS) do
            if r.ImGui_Selectable(ctx, q.label .. '##char_part' .. i, i == S.char_manual_part) then
                S.char_manual_part = i
            end
            Tooltip(q.track)
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.char_manual_part .. '\n\nTrack: ' .. p.track)
    p = CHAR_PARTS[S.char_manual_part] or CHAR_PARTS[1]

    -- State (Play solo only for guitar and bass)
    -- Play solo is guitar / bass only, the ride options drums only.
    local is_ride = CHAR_RIDE_SET[S.char_manual_state] ~= nil
    if (is_ride and p.group ~= 'drums')
       or (not is_ride and CHAR_STATE_SET[S.char_manual_state].solo and not p.solo) then
        S.char_manual_state = '[play]'
        is_ride = false
    end
    r.ImGui_Text(ctx, 'State')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##char_state', CharStateLabel(S.char_manual_state)) then
        for _, st in ipairs(CHAR_STATES) do
            if not st.solo or p.solo then
                if r.ImGui_Selectable(ctx, st.label .. '##char_state', st.msg == S.char_manual_state) then
                    S.char_manual_state = st.msg
                end
                StateTooltip(st.msg, p.group, p.vocal)
            end
        end
        if p.group == 'drums' then
            r.ImGui_Separator(ctx)
            for _, ev in ipairs(CHAR_RIDE_EVENTS) do
                if r.ImGui_Selectable(ctx, ev.label .. '##char_state', ev.msg == S.char_manual_state) then
                    S.char_manual_state = ev.msg
                end
                StateTooltip(ev.msg, p.group, false)
            end
        end
        r.ImGui_EndCombo(ctx)
    else
        StateTooltip(S.char_manual_state, p.group, p.vocal)
    end

    -- Insert, or Replace when a state already sits on the playhead
    r.ImGui_SameLine(ctx)
    local exact = _readout and (is_ride and _readout.ride_exact or (not is_ride and _readout.exact))
    local bw = BtnGroupWidth({ 'Insert', 'Replace' })
    if Btn((exact and 'Replace' or 'Insert') .. '##char_ins', BTN_H, bw) then
        local idx, msg = S.char_manual_part, S.char_manual_state
        RunAction(function() InsertCharacterState(idx, msg) end)
        _readout_key = nil
    end
    Tooltip(TIPS.char_manual_btn)

    -- What the part is doing at the playhead
    r.ImGui_Text(ctx, 'At playhead')
    r.ImGui_SameLine(ctx, lbl_col)
    if not _readout then
        r.ImGui_TextDisabled(ctx, '(no MIDI item)')
    elseif _readout.none then
        r.ImGui_TextDisabled(ctx, '(no state yet)')
    else
        r.ImGui_Text(ctx, CharStateLabel(_readout.msg))
        StateTooltip(_readout.msg, p.group, p.vocal)
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, _readout.where)
        Tooltip(TIPS.char_readout)
    end
end

local function DrawAnimationCharacterTab()
    local changed = _char_poll()
    if changed then _char_groups = CharGroupStatus() end
    RefreshReadout(changed)

    r.ImGui_TextWrapped(ctx, 'Character animation states on each part: active while the ' ..
                             'part plays, idle in long breaks, idle realtime after its ' ..
                             'last note. Muted parts get nothing.')
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Mode', 'Set all', 'Drums', 'Guitar', 'Bass', 'Vocals',
                                    'Keys', 'Instrument idle gap', 'Vocal idle gap',
                                    'Part', 'State', 'At playhead' })
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Generate##char_mode', S.char_mode == 0) then S.char_mode = 0 end
    Tooltip(TIPS.char_mode)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Manual##char_mode', S.char_mode == 1) then S.char_mode = 1 end
    Tooltip(TIPS.char_mode)
    r.ImGui_Spacing(ctx)

    if S.char_mode == 1 then
        DrawCharacterManual(lbl_col)
    else
        DrawCharacterGenerate(lbl_col)
    end
end

-- Drums sub-tab: the options and Generate.
local function DrawAnimationDrumsTab()
    r.ImGui_TextWrapped(ctx, 'Writes the drummer\'s hand and kick animation notes on PART DRUMS ' ..
                             'and PART DRUMS_2X from the Expert gems: which drum or cymbal, and ' ..
                             'which hand - alternating only when the hits come fast, following ' ..
                             'the beat, and moving around the kit without crossing the arms. ' ..
                             'The hi-hat pedal notes are not generated.')
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Default crash', 'Blue cymbal', 'Min cymbal hits' })
    local radio_w = RadioGroupWidth({ 'Crash 2 (right)', 'Crash 1 (left)', 'Ride', 'Open hi-hat' })
    r.ImGui_Text(ctx, 'Default crash')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Crash 2 (right)##da_crash', S.drum_anim_crash == 0) then S.drum_anim_crash = 0 end
    Tooltip(TIPS.drum_anim_crash)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Crash 1 (left)##da_crash', S.drum_anim_crash == 1) then S.drum_anim_crash = 1 end
    Tooltip(TIPS.drum_anim_crash)

    r.ImGui_Text(ctx, 'Blue cymbal')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Ride##da_blue', not S.drum_anim_blue_hh) then S.drum_anim_blue_hh = false end
    Tooltip(TIPS.drum_anim_blue)
    r.ImGui_SameLine(ctx, lbl_col + radio_w)
    if r.ImGui_RadioButton(ctx, 'Open hi-hat##da_blue', S.drum_anim_blue_hh) then S.drum_anim_blue_hh = true end
    Tooltip(TIPS.drum_anim_blue)

    r.ImGui_Text(ctx, 'Min cymbal hits')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.drum_anim_min_cym = r.ImGui_SliderInt(ctx, '##da_mincym', S.drum_anim_min_cym, 2, 8, '%d hits')
    SliderTooltip(TIPS.drum_anim_min_cym)

    _, S.drum_anim_flam = r.ImGui_Checkbox(ctx, 'Snare + yellow tom as a flam##da_flam', S.drum_anim_flam)
    Tooltip(TIPS.drum_anim_flam)
    _, S.drum_anim_snare_variety = r.ImGui_Checkbox(ctx, 'Slow snare variety##da_sv', S.drum_anim_snare_variety)
    Tooltip(TIPS.drum_anim_snare_variety)
    _, S.drum_anim_soft = r.ImGui_Checkbox(ctx, 'Soft snare and crash hits##da_soft', S.drum_anim_soft)
    Tooltip(TIPS.drum_anim_soft)
    _, S.drum_anim_ride_alt = r.ImGui_Checkbox(ctx, 'Crash riding: alternate soft and hard##da_ra',
                                               S.drum_anim_ride_alt)
    Tooltip(TIPS.drum_anim_ride_alt)
    _, S.drum_anim_flam_late = r.ImGui_Checkbox(ctx, 'Flam: left hand slightly late##da_fl',
                                                S.drum_anim_flam_late)
    Tooltip(TIPS.drum_anim_flam_late)

    r.ImGui_Spacing(ctx)
    if Btn('Generate drum animations', BTN_H) then
        RunAction(GenerateDrumAnimations)
    end
    Tooltip(TIPS.drum_anim_generate)
end

-- Animation main tab. Body only: the caller owns BeginTabItem / EndTabItem.
function DrawAnimationTab()
    if r.ImGui_BeginTabBar(ctx, '##animation_subtabs') then
        if r.ImGui_BeginTabItem(ctx, 'Beat') then
            DrawAnimationBeatTab()
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, 'Character') then
            DrawAnimationCharacterTab()
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, 'Drums') then
            DrawAnimationDrumsTab()
            r.ImGui_EndTabItem(ctx)
        end
        r.ImGui_EndTabBar(ctx)
    end
end
