-- ImGui display helpers and track combo (shared library)
-- Requires globals: r (reaper), ctx (ImGui context)

local CTRL_CLICK_HINT = "\n\nTip: Ctrl+click the slider to type an exact value."

local NOTE_NAMES = { 'C','C#','D','D#','E','F','F#','G','G#','A','A#','B' }

local BTN_PAD   = 40   -- ~20 px padding each side
local LABEL_PAD = 16   -- gap after a row label before its aligned input begins

WIDTH_STD   = 200   -- standard slider/combo width
WIDTH_SHORT = 80    -- short selector width (e.g. note-name combo)
BTN_H       = 24    -- standard button height
local RADIO_PAD_FALLBACK = 28   -- used only if ImGui_GetFrameHeight is unavailable
local RADIO_CUSHION      = 16   -- extra just-in-case margin on top of the real style values
local HAS_FRAME_HEIGHT   = type(r.ImGui_GetFrameHeight) == 'function'

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

-- Width a Btn() call would use for this label, without drawing it. Needed
-- ahead of the draw call for pre-positioning (e.g. right-aligning a button
-- via SetCursorPosX before it's placed) - the one case Btn() itself can't
-- cover since it draws immediately. Strips any "##id" suffix, matching Btn().
function BtnWidth(label)
    local visible = label:match('^(.-)##') or label
    return r.ImGui_CalcTextSize(ctx, visible) + BTN_PAD
end

-- Widest BtnWidth() among a group of labels - use to give a row (or block)
-- of related buttons a uniform width instead of each sizing to its own text.
function BtnGroupWidth(labels)
    local w = 0
    for _, label in ipairs(labels) do
        local lw = BtnWidth(label)
        if lw > w then w = lw end
    end
    return w
end

-- Widest label (+ padding) among a group of row labels - use as the col arg
-- to SameLine(ctx, col) so a block of "Label <input>" rows all start their
-- input at the same X, instead of hardcoding what's presumed the longest
-- label (which silently stops aligning if a longer one is added later).
function LabelColWidth(labels)
    local w = 0
    for _, label in ipairs(labels) do
        local lw = r.ImGui_CalcTextSize(ctx, label) + LABEL_PAD
        if lw > w then w = lw end
    end
    return w
end

-- Widest radio-option label (+ padding) among a group - use as a uniform
-- per-option reserved width so every RadioButton in the group (across
-- however many rows) starts its Nth option at the same X, regardless of how
-- long that row's earlier options are. RadioButton has no width parameter,
-- so alignment works by positioning each option with SameLine(ctx, base +
-- (i-1) * RadioGroupWidth(...)) rather than resizing the widget itself.
--
-- Padding is the circle + its inner gap to the label + the gap before the
-- next item, derived from real ImGui style values (ImGui_GetFrameHeight for
-- the circle, ItemSpacing for the inter-widget gap - both track the current
-- font size / REAPER UI scale) plus a fixed cushion, rather than a bare
-- pixel guess - a guess only has to be a little too small to make option 2
-- crowd or overlap option 1's label, which is most visible on the widest
-- label in the group (e.g. "Horizontal"/"Vertical": a short gap reads as
-- "barely apart" right next to a long word, even where the same absolute
-- gap looks fine next to a short one like "1x"). Falls back to a fixed
-- constant if ImGui_GetFrameHeight is unavailable in the user's ReaImGui.
function RadioGroupWidth(labels)
    local pad
    if HAS_FRAME_HEIGHT then
        local circle    = r.ImGui_GetFrameHeight(ctx)
        local item_sp_x = ({ r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()) })[1]
        pad = circle + item_sp_x + RADIO_CUSHION
    else
        pad = RADIO_PAD_FALLBACK
    end
    local w = 0
    for _, label in ipairs(labels) do
        local lw = r.ImGui_CalcTextSize(ctx, label) + pad
        if lw > w then w = lw end
    end
    return w
end

-- Draws a button sized to its own label, so the label string only appears
-- once at each call site (no separate CalcTextSize copy to keep in sync).
-- Pass min_w (e.g. from BtnGroupWidth()) to widen it to match a button group.
function Btn(label, height, min_w)
    local w = BtnWidth(label)
    if min_w and min_w > w then w = min_w end
    return r.ImGui_Button(ctx, label, w, height)
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
