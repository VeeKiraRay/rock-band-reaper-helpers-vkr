-- Venue > Keyframes sub-tab
-- Bulk-regenerates [first]/[next] keyframes for every manual lighting event already on the
-- VENUE track, respecting time selection.
-- Requires globals: r, ctx, S, TIPS, Tooltip, SliderTooltip, RunAction, RegenerateVenueKeyframes

function DrawVenueKeyframesTab()
    local _bp = 40

    r.ImGui_TextDisabled(ctx,
        'Regenerate [first]/[next] keyframes for every manual lighting event already on the VENUE track')
    r.ImGui_Spacing(ctx)

    local _kfa_labels = {
        'Lighting start', 'Closest beat', 'Downbeat',
        'Guitar notes', 'Bass notes', 'Keys notes',
        'Drum kicks', 'Drum snare',
    }
    local _lbl_col = r.ImGui_CalcTextSize(ctx, 'Keyframe align') + 16

    r.ImGui_Text(ctx, 'Keyframe align')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 170)
    local _kfa_preview = _kfa_labels[S.venue_keyframe_align + 1] or 'Lighting start'
    if r.ImGui_BeginCombo(ctx, '##vkf_kfa', _kfa_preview) then
        for _ki, _kl in ipairs(_kfa_labels) do
            local _ksel = (_ki - 1 == S.venue_keyframe_align)
            if r.ImGui_Selectable(ctx, _kl, _ksel) then
                S.venue_keyframe_align = _ki - 1
            end
            if _ksel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.venue_keyframe_align)

    if S.venue_keyframe_align >= 3 then
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every beat##vkf_kfis', S.venue_kf_inst_subdiv == 0) then
            S.venue_kf_inst_subdiv = 0
        end
        Tooltip(TIPS.venue_kf_inst_subdiv)
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, 'Every half beat##vkf_kfis', S.venue_kf_inst_subdiv == 1) then
            S.venue_kf_inst_subdiv = 1
        end
        Tooltip(TIPS.venue_kf_inst_subdiv)
    end

    r.ImGui_Text(ctx, 'Keyframe rate')
    r.ImGui_SameLine(ctx, _lbl_col)
    r.ImGui_SetNextItemWidth(ctx, 120)
    _, S.venue_kf_rate = r.ImGui_SliderInt(ctx, '##vkf_rate', S.venue_kf_rate, 1, 8)
    SliderTooltip(TIPS.venue_sec_kr)

    r.ImGui_Spacing(ctx)
    local bw_kf = r.ImGui_CalcTextSize(ctx, 'Regenerate keyframes') + _bp
    if r.ImGui_Button(ctx, 'Regenerate keyframes', bw_kf, 24) then
        RunAction(RegenerateVenueKeyframes)
    end
    Tooltip(TIPS.venue_kf_regenerate)
end
