-- Overdrive tab rendering.
-- Requires: S, TIPS, r, ctx (globals)
-- Requires: Btn, BtnWidth, LabelColWidth, Tooltip, SliderTooltip, SectionHeader,
--           WIDTH_STD, BTN_H (lib/reaper_imgui_helpers.lua), RunAction (helpers.lua),
--           OD_GROUP_CHOICES (overdrive_read.lua), OD_FILL_PACINGS
--           (actions_overdrive_fills.lua), GenerateOverdrive, ValidateOverdrive

-- Overview strip colours. The plate and grey match the Metadata tab's so the two
-- drawn widgets read as one family.
local COL_PLATE   = 0x1E1E1EFF
local COL_OD      = 0xFFFFFFFF   -- a phrase: white, as the game draws overdrive gems
local COL_UNISON  = 0xFFC83CFF   -- a unison phrase
local COL_FILL    = 0x5A9BE0FF   -- a drum fill, as a tick under the drum row
local COL_SECTION = 0xFFFFFF30   -- a section start
local COL_KEEPOUT = 0xE0444430   -- the end-of-song keep-out
local COL_LABEL   = 0xBBBBBBFF

-- "Over vocal OD" choices, keyed by the S.od_vocal_overlap value (see OdVocalNoGo),
-- listed most permissive first since that is the default.
local VOCAL_OVERLAP_LABELS = {
    [2] = 'Overlap anywhere',
    [1] = 'Avoid its first measure',
    [0] = 'Avoid vocal overdrive',
}
local VOCAL_OVERLAP_ORDER = { 2, 1, 0 }

local PACING_LABELS = { [0] = 'Auto (from tempo)' }
for i, p in ipairs(OD_FILL_PACINGS) do PACING_LABELS[i] = p.label end

-- One row per part across the whole song. Drawn on the window draw list, with a
-- Dummy reserving its box so hover and layout have something to attach to.
local function DrawOverview(ov)
    local lh     = r.ImGui_GetTextLineHeight(ctx)
    local row_h  = math.floor(lh * 0.9)
    local gap    = 3
    local labels = {}
    for i, row in ipairs(ov.rows) do labels[i] = row.label end
    local lab_w  = LabelColWidth(labels)
    local avail  = r.ImGui_GetContentRegionAvail(ctx)
    local w      = math.max(120, avail - lab_w)
    local x, y   = r.ImGui_GetCursorScreenPos(ctx)
    local dl     = r.ImGui_GetWindowDrawList(ctx)
    local x0     = x + lab_w
    local span   = math.max(ov.s1 - ov.s0, 1e-6)
    local function X(qn) return x0 + (qn - ov.s0) / span * w end
    local total_h = #ov.rows * (row_h + gap)

    r.ImGui_DrawList_AddRectFilled(dl, x0, y, x0 + w, y + total_h, COL_PLATE, 2)
    r.ImGui_DrawList_AddRectFilled(dl, X(ov.keep_qn), y, x0 + w, y + total_h, COL_KEEPOUT)
    for _, s in ipairs(ov.sections) do
        r.ImGui_DrawList_AddLine(dl, X(s), y, X(s), y + total_h, COL_SECTION, 1.0)
    end
    for i, row in ipairs(ov.rows) do
        local ry = y + (i - 1) * (row_h + gap)
        r.ImGui_DrawList_AddText(dl, x, ry + (row_h - lh) / 2, COL_LABEL, row.label)
        for _, sp in ipairs(row.spans) do
            -- At least 2 px wide, so a one-bar phrase stays visible in a long song.
            local a, b = X(sp.s), math.max(X(sp.e), X(sp.s) + 2)
            r.ImGui_DrawList_AddRectFilled(dl, a, ry + 1, b, ry + row_h - 1,
                                           sp.unison and COL_UNISON or COL_OD)
        end
        if row.fills then
            for _, f in ipairs(ov.fills) do
                r.ImGui_DrawList_AddLine(dl, X(f.s), ry + row_h - 1, math.max(X(f.e), X(f.s) + 1),
                                         ry + row_h - 1, COL_FILL, 2.0)
            end
        end
    end
    r.ImGui_Dummy(ctx, lab_w + w, total_h)

    -- Hovering the strip names the measure under the mouse.
    if r.ImGui_IsItemHovered(ctx) then
        local mx = r.ImGui_GetMousePos(ctx)
        if mx >= x0 then
            local qn = ov.s0 + (mx - x0) / w * span
            r.ImGui_SetTooltip(ctx, OdWhere(qn))
        end
    end
end

function DrawOverdriveTab(ctx)
    r.ImGui_TextWrapped(ctx, 'Generates overdrive phrases, unisons, drum fills and vocal overdrive '
        .. 'for the whole song, following the RBN authoring rules. A time selection is ignored. '
        .. 'Validate is read-only.')
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Instrument', 'Beats per phrase', 'Unison share',
                                    'Over vocal OD', 'Start keep-out', 'OD keep-out', 'Unison keep-out',
                                    'Pacing', 'Fill end keep-out', 'Phrases per OD' })

    -- Instrument group
    local choice = OD_GROUP_CHOICES[S.od_group + 1] or OD_GROUP_CHOICES[1]
    r.ImGui_Text(ctx, 'Instrument')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##od_group', choice.label) then
        for i, c in ipairs(OD_GROUP_CHOICES) do
            local sel = (i - 1 == S.od_group)
            if r.ImGui_Selectable(ctx, c.label, sel) then S.od_group = i - 1 end
            if sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.od_group)
    if choice.desc then
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, choice.desc)
    end

    local is_all      = choice.all == true
    local do_phrases  = choice.inst ~= nil or is_all
    local do_fills    = is_all or choice.inst == 'drums'
    local do_vocals   = choice.vocals == true

    -- Overdrive phrases
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    if not do_phrases then r.ImGui_BeginDisabled(ctx) end
    _, S.od_inc_phrases = r.ImGui_Checkbox(ctx, 'Overdrive phrases##od_inc_ph', S.od_inc_phrases)
    Tooltip(TIPS.od_inc_phrases)
    r.ImGui_Text(ctx, 'Beats per phrase')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_beats_per_phrase = r.ImGui_SliderInt(ctx, '##od_bpp', S.od_beats_per_phrase, 20, 80)
    SliderTooltip(TIPS.od_beats_per_phrase)
    r.ImGui_SameLine(ctx)
    r.ImGui_TextDisabled(ctx, ('(~%d measures in 4/4)'):format(math.floor(S.od_beats_per_phrase / 4 + 0.5)))

    local lock_share = not is_all
    if lock_share and do_phrases then r.ImGui_BeginDisabled(ctx) end
    r.ImGui_Text(ctx, 'Unison share')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_unison_share = r.ImGui_SliderInt(ctx, '##od_ush', S.od_unison_share, 0, 100, '%d%%')
    SliderTooltip(TIPS.od_unison_share)
    _, S.od_together = r.ImGui_Checkbox(ctx, 'Prefer measures where the band plays together##od_tog',
                                        S.od_together)
    Tooltip(TIPS.od_together)
    if lock_share and do_phrases then r.ImGui_EndDisabled(ctx) end

    r.ImGui_Text(ctx, 'Over vocal OD')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##od_vol', VOCAL_OVERLAP_LABELS[S.od_vocal_overlap] or VOCAL_OVERLAP_LABELS[2]) then
        for _, m in ipairs(VOCAL_OVERLAP_ORDER) do
            local sel = (m == S.od_vocal_overlap)
            if r.ImGui_Selectable(ctx, VOCAL_OVERLAP_LABELS[m], sel) then S.od_vocal_overlap = m end
            if sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.od_vocal_overlap)

    r.ImGui_Text(ctx, 'Start keep-out')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_keepout_start = r.ImGui_SliderInt(ctx, '##od_kst', S.od_keepout_start, 0, 16, '%d measures')
    SliderTooltip(TIPS.od_keepout_start)
    r.ImGui_Text(ctx, 'OD keep-out')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_keepout_od = r.ImGui_SliderInt(ctx, '##od_kod', S.od_keepout_od, 0, 32, '%d measures')
    SliderTooltip(TIPS.od_keepout_od)
    r.ImGui_Text(ctx, 'Unison keep-out')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_keepout_unison = r.ImGui_SliderInt(ctx, '##od_kun', S.od_keepout_unison, 0, 32, '%d measures')
    SliderTooltip(TIPS.od_keepout_unison)
    if not do_phrases then r.ImGui_EndDisabled(ctx) end

    -- Drum fills
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    if not do_fills then r.ImGui_BeginDisabled(ctx) end
    _, S.od_inc_fills = r.ImGui_Checkbox(ctx, 'Drum fills##od_inc_fl', S.od_inc_fills)
    Tooltip(TIPS.od_inc_fills)
    r.ImGui_Text(ctx, 'Pacing')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##od_fpc', PACING_LABELS[S.od_fill_pacing] or PACING_LABELS[0]) then
        for i = 0, #OD_FILL_PACINGS do
            local sel = (i == S.od_fill_pacing)
            if r.ImGui_Selectable(ctx, PACING_LABELS[i], sel) then S.od_fill_pacing = i end
            if sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.od_fill_pacing)
    r.ImGui_Text(ctx, 'Fill end keep-out')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_fill_keepout_end = r.ImGui_SliderInt(ctx, '##od_fke', S.od_fill_keepout_end, 0, 8, '%d measures')
    SliderTooltip(TIPS.od_fill_keepout_end)
    _, S.od_fill_sections = r.ImGui_Checkbox(ctx, 'End fills at section changes / crashes##od_fsc',
                                             S.od_fill_sections)
    Tooltip(TIPS.od_fill_sections)
    _, S.od_fill_skip_early = r.ImGui_Checkbox(ctx, 'Skip fills before overdrive can be activated##od_fse',
                                               S.od_fill_skip_early)
    Tooltip(TIPS.od_fill_skip_early)
    if not do_fills then r.ImGui_EndDisabled(ctx) end

    -- Vocal overdrive
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    if not do_vocals then r.ImGui_BeginDisabled(ctx) end
    _, S.od_inc_vocals = r.ImGui_Checkbox(ctx, 'Vocal overdrive##od_inc_vo', S.od_inc_vocals)
    Tooltip(TIPS.od_inc_vocals)
    r.ImGui_Text(ctx, 'Phrases per OD')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    _, S.od_vocal_every = r.ImGui_SliderInt(ctx, '##od_vev', S.od_vocal_every, 2, 10)
    SliderTooltip(TIPS.od_vocal_every)
    if not do_vocals then r.ImGui_EndDisabled(ctx) end

    -- Generate
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    local any = (do_phrases and S.od_inc_phrases) or (do_fills and S.od_inc_fills)
             or (do_vocals and S.od_inc_vocals)
    if not any then r.ImGui_BeginDisabled(ctx) end
    if Btn('Generate', BTN_H) then RunAction(function() GenerateOverdrive() end) end
    if not any then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.od_generate)

    -- Check
    r.ImGui_Spacing(ctx)
    SectionHeader('Check')
    if Btn('Validate', BTN_H) then RunAction(ValidateOverdrive) end
    Tooltip(TIPS.od_validate)
    if S.od_overview then
        r.ImGui_Spacing(ctx)
        DrawOverview(S.od_overview)
        r.ImGui_TextDisabled(ctx, 'White: phrase   Gold: unison   Blue: fill   Red: end keep-out')
    else
        r.ImGui_TextDisabled(ctx, 'Validate or Generate to show an overview of the song.')
    end

    -- Replace confirmation, set by GenerateOverdrive when a target already has notes.
    if S.od_pending then r.ImGui_OpenPopup(ctx, 'ConfirmOverdriveReplace') end
    if r.ImGui_BeginPopupModal(ctx, 'ConfirmOverdriveReplace', nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        local pending = S.od_pending
        if pending then r.ImGui_Text(ctx, pending.message) end
        r.ImGui_Spacing(ctx)
        if Btn('Replace', BTN_H) then
            S.od_pending = nil
            if pending then RunAction(pending.on_replace) end
            r.ImGui_CloseCurrentPopup(ctx)
        end
        Tooltip(TIPS.od_replace)
        if pending and pending.can_keep then
            r.ImGui_SameLine(ctx)
            if Btn('Keep existing', BTN_H) then
                S.od_pending = nil
                RunAction(pending.on_keep)
                r.ImGui_CloseCurrentPopup(ctx)
            end
            Tooltip(TIPS.od_keep)
        end
        r.ImGui_SameLine(ctx)
        if Btn('Cancel', BTN_H) then
            S.od_pending = nil
            S.status = 'Generate cancelled.'
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end
