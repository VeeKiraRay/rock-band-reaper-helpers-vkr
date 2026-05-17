-- ImGui display helpers and track combo (shared library)
-- Requires globals: r (reaper), ctx (ImGui context)

local CTRL_CLICK_HINT = "\n\nTip: Ctrl+click the slider to type an exact value."

local NOTE_NAMES = { 'C','C#','D','D#','E','F','F#','G','G#','A','A#','B' }

function PitchName(p)
    p = math.floor(p + 0.5)
    if p < 0 then p = 0 elseif p > 127 then p = 127 end
    local octave = math.floor(p / 12) - 2  -- Rock Band octave convention (C1=36, not C2)
    return ('%s%d'):format(NOTE_NAMES[(p % 12) + 1], octave)
end

function Tooltip(text)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, text)
    end
end

function SliderTooltip(text)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, text .. CTRL_CLICK_HINT)
    end
end

function GetTrackList()
    local list = {}
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetTrackName(tr)
        if name == '' then name = ('Track %d'):format(i + 1) end
        list[#list + 1] = { idx = i, label = ('%d: %s'):format(i + 1, name) }
    end
    return list
end

function TrackCombo(label, sel_idx, tracks)
    local preview = (#tracks > 0 and sel_idx < #tracks)
        and tracks[sel_idx + 1].label or '<no tracks>'
    if r.ImGui_BeginCombo(ctx, label, preview) then
        for i, t in ipairs(tracks) do
            local is_sel = (i - 1 == sel_idx)
            if r.ImGui_Selectable(ctx, t.label, is_sel) then
                sel_idx = i - 1
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    return sel_idx
end

-- Format a project time position as "mNN  Xm SS.MMMsec" (measure + wall time).
-- Durations (not positions) should stay in plain seconds.
function FormatTime(t)
    local mbt = r.format_timestr_pos(t, '', 1)
    local measure = tonumber(mbt:match('^(%d+)'))
    local mins = math.floor(t / 60)
    local secs = t - mins * 60
    local ts = mins > 0 and ('%dm %06.3fs'):format(mins, secs) or ('%.3fs'):format(t)
    return measure and ('m%d  %s'):format(measure, ts) or ts
end

function GetTimeSelection()
    local s, e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if e > s then return s, e end
    return nil, nil
end

function SectionHeader(title, reset_label, reset_fn, reset_tip)
    r.ImGui_Text(ctx, title)
    if reset_label then
        r.ImGui_SameLine(ctx)
        local avail_x = r.ImGui_GetContentRegionAvail(ctx)
        local btn_w = 80
        if avail_x > btn_w + 4 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - btn_w))
        end
        if r.ImGui_SmallButton(ctx, reset_label) then
            reset_fn()
        end
        Tooltip(reset_tip)
    end
end
