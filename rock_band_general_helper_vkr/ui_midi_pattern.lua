-- MIDI > Pattern sub-tab rendering.
--
-- Body only - no Begin/End, no BeginTabItem: the caller owns the window and the
-- tab item. Drawn both by the general helper's MIDI tab (ui_midi.lua) and by the
-- standalone rock_band_midi_pattern_vkr.lua window, so it must not assume either
-- context. Same contract as ui_venue_preview.lua's DrawVenuePreviewTab.
--
-- Requires globals: r, ctx, S, TIPS, RunAction, TrackCombo (ui_common.lua),
--   MidiEditorTrackWarning (ui_common.lua), GetPatternPitchRange and the seven
--   action functions (actions_midi_replace.lua), Btn / BtnGroupWidth /
--   LabelColWidth / Tooltip / BTN_H / WIDTH_STD / WIDTH_SHORT (lib).

-- Difficulty filter dropdown options (S.mr_diff_idx).
local MR_DIFF_OPTIONS = {
    { idx = 0, label = 'All' },
    { idx = 1, label = 'Expert' },
    { idx = 2, label = 'Hard' },
    { idx = 3, label = 'Medium' },
    { idx = 4, label = 'Easy' },
}

function DrawMIDIPatternTab()
    local midi_tracks = S.midi_track_list
    -- S.busy is never assigned anywhere in this script, so every guard below is
    -- currently a no-op. Kept as-is: it is the existing behaviour, and the hook
    -- is what a future long-running Pattern action would set.
    local is_busy_mr = S.busy

    local lbl_col_pat = LabelColWidth({ 'Source track', 'Difficulty' })

    r.ImGui_Text(ctx, 'Source track')
    r.ImGui_SameLine(ctx, lbl_col_pat)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    S.mr_midi_src_idx = TrackCombo('##mr_src', S.mr_midi_src_idx, midi_tracks)
    Tooltip(TIPS.mr_midi_src)
    MidiEditorTrackWarning(S.mr_midi_src_idx)

    r.ImGui_Text(ctx, 'Difficulty')
    r.ImGui_SameLine(ctx, lbl_col_pat)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_SHORT)
    S.mr_diff_idx = TrackCombo('##mr_diff', S.mr_diff_idx, MR_DIFF_OPTIONS)
    Tooltip(TIPS.mr_diff)
    if S.mr_midi_src_idx >= 0 then
        local _tr = r.GetTrack(0, S.mr_midi_src_idx)
        if _tr then
            local _, _trname = r.GetTrackName(_tr)
            local _lo, _hi = GetPatternPitchRange(_trname, S.mr_diff_idx)
            r.ImGui_TextDisabled(ctx, ('Pitch range: %d-%d'):format(_lo, _hi))
        end
    end

    r.ImGui_Spacing(ctx)
    local bw_pat = BtnGroupWidth({
        'Set Search', 'Set Replace', 'Replace All', 'Fill Range',
        'Go Prev', 'Go Next', 'List Search',
    })
    if is_busy_mr then r.ImGui_BeginDisabled(ctx) end
    if Btn('Set Search', BTN_H, bw_pat) then
        RunAction(SetSearchPattern)
    end
    Tooltip(TIPS.mr_set_search)
    r.ImGui_SameLine(ctx)
    if Btn('Set Replace', BTN_H, bw_pat) then
        RunAction(SetReplacePattern)
    end
    Tooltip(TIPS.mr_set_replace)
    if is_busy_mr then r.ImGui_EndDisabled(ctx) end

    local no_replace = not S.mr_replace_notes
    local no_both    = not S.mr_search_notes or no_replace
    if is_busy_mr or no_both then r.ImGui_BeginDisabled(ctx) end
    if Btn('Replace All', BTN_H, bw_pat) then
        RunAction(DoMIDIPatternReplace)
    end
    Tooltip(TIPS.mr_do_replace)
    if is_busy_mr or no_both then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    if is_busy_mr or no_replace then r.ImGui_BeginDisabled(ctx) end
    if Btn('Fill Range', BTN_H, bw_pat) then
        RunAction(FillRange)
    end
    Tooltip(TIPS.mr_fill_range)
    if is_busy_mr or no_replace then r.ImGui_EndDisabled(ctx) end

    local no_search = not S.mr_search_notes
    if is_busy_mr or no_search then r.ImGui_BeginDisabled(ctx) end
    if Btn('Go Prev', BTN_H, bw_pat) then
        RunAction(GoPrevPatternMatch)
    end
    Tooltip(TIPS.mr_go_prev)
    r.ImGui_SameLine(ctx)
    if Btn('Go Next', BTN_H, bw_pat) then
        RunAction(GoNextPatternMatch)
    end
    Tooltip(TIPS.mr_go_next)
    r.ImGui_SameLine(ctx)
    if Btn('List Search', BTN_H, bw_pat) then
        RunAction(ListPatternMatches)
    end
    Tooltip(TIPS.mr_list_search)
    if is_busy_mr or no_search then r.ImGui_EndDisabled(ctx) end

    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Search: ')
    r.ImGui_SameLine(ctx)
    if S.mr_search_notes then
        r.ImGui_Text(ctx, S.mr_search_label)
    else
        r.ImGui_TextDisabled(ctx, 'not set')
    end
    r.ImGui_Text(ctx, 'Replace:')
    r.ImGui_SameLine(ctx)
    if S.mr_replace_notes then
        r.ImGui_Text(ctx, S.mr_replace_label)
    else
        r.ImGui_TextDisabled(ctx, 'not set')
    end
end

-- Reset the Pattern sub-tab's session state. Called on project switch by both
-- entry points: the captured patterns are take-relative PPQ offsets and their
-- labels name measures of the project they were captured in, so carrying them
-- across would silently target the wrong material.
function ResetMIDIPatternState()
    S.mr_midi_src_idx    = -1
    S.mr_search_notes    = nil
    S.mr_search_label    = ''
    S.mr_search_dur_ppq  = 0
    S.mr_search_step_ppq = 0
    S.mr_replace_notes   = nil
    S.mr_replace_label   = ''
    S.mr_replace_dur_ppq = 0
end
