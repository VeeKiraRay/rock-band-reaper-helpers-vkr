-- Animation tab: DrawAnimationTab (the sub-tab bar) and the Beat sub-tab.
-- Character, Drums, Keys and Guitar sub-tabs are planned; each comes with its
-- own feature.
-- Requires globals: r, ctx, S, TIPS, Tooltip, Btn, BtnGroupWidth, BTN_H,
--                   SectionHeader, RunAction, GenerateBeatTrack

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

-- Animation main tab. Body only: the caller owns BeginTabItem / EndTabItem.
function DrawAnimationTab()
    if r.ImGui_BeginTabBar(ctx, '##animation_subtabs') then
        if r.ImGui_BeginTabItem(ctx, 'Beat') then
            DrawAnimationBeatTab()
            r.ImGui_EndTabItem(ctx)
        end
        r.ImGui_EndTabBar(ctx)
    end
end
