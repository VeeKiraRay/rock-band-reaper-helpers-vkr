-- Directed Moves window (rock_band_directed_moves_vkr.lua): what the game can show for each directed camera cut.
-- Search by camera event (one section) or by keyword (up to CS_MAX_SECTIONS sections, each
-- headed by its camera event). A section lists the event's moves - the camera shots of all
-- 44 RB3 venues grouped by move, focus member, gender and styles - with the venue kinds that
-- have them, how many variants one venue rotates through, and how early each starts.
-- Filters (style, gender, venue kind, lineup) dim the moves that would not play.
-- Read-only: reads only the generated lib/reaper_venue_shots.lua, never the project.
-- Requires globals: r, ctx, S, TIPS, Tooltip, LabelColWidth, WIDTH_STD,
--                   VenueEventTooltip, DIRECTED_LABELS, DIRECTED_TIPS, COOP_LABELS,
--                   RB_VENUE_SHOTS, VenueShotEvents, VenueShotEvent, VenueShotRowMatches,
--                   VenueShotRemap, VenueShotSearch, VenueShotKindsText,
--                   VenueShotRowFilter, VenueShotWhoShort,
--                   VENUE_SHOT_KIND_LABELS, VENUE_SHOT_LINEUP_LABELS

local CS_MAX_SECTIONS = 10

local STYLE_OPTS  = { { '', 'Any style' }, { 'R', 'Rocker' }, { 'D', 'Dramatic' },
                      { 'B', 'Banger' }, { 'S', 'Spazz' } }
local GENDER_OPTS = { { '', 'Any gender' }, { 'M', 'Male' }, { 'F', 'Female' } }
local LINEUP_OPTS = { { '', 'All five' }, { 'no_keys', 'Without keys' },
                      { 'no_guitar', 'Without guitar' }, { 'no_bass', 'Without bass' } }
local STYLE_NAMES = { R = 'Rocker', D = 'Dramatic', B = 'Banger', S = 'Spazz' }
local GENDER_NAMES = { M = 'Male', F = 'Female', B = 'Both' }

local function EventLabel(cat)
    return DIRECTED_LABELS[cat] or COOP_LABELS[cat] or cat
end

local function EventTooltip(cat)
    VenueEventTooltip('Camera', cat, DIRECTED_TIPS[cat], { label = EventLabel(cat) })
end

local function StylesText(styles)
    if styles == 'RDBS' then return 'Any' end
    local out = {}
    for ch in styles:gmatch('.') do out[#out + 1] = STYLE_NAMES[ch] end
    return table.concat(out, ', ')
end

local function Range(a, b)
    if math.abs(a - b) < 0.005 then return ('%.1f s'):format(a) end
    return ('%.1f-%.1f s'):format(a, b)
end

-- A combo over { value, label } options writing S[field].
local function OptCombo(id, field, opts, tip)
    local cur = opts[1][2]
    for _, o in ipairs(opts) do if o[1] == S[field] then cur = o[2] end end
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, id, cur) then
        for _, o in ipairs(opts) do
            if r.ImGui_Selectable(ctx, o[2], o[1] == S[field]) then S[field] = o[1] end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(tip)
end

local function KindOpts()
    local opts = { { '', 'Any venue' } }
    for _, k in ipairs(RB_VENUE_SHOTS.kinds) do opts[#opts + 1] = { k, VENUE_SHOT_KIND_LABELS[k] } end
    return opts
end

local function CurrentFilter()
    local function v(x) return x ~= '' and x or nil end
    return { style = v(S.venue_cs_style), gender = v(S.venue_cs_gender),
             kind = v(S.venue_cs_kind), lineup = v(S.venue_cs_lineup) }
end

-- Event picker: the directed camera cuts, alphabetical. Normal (coop) shots are not listed:
-- they have no moves of their own, always play and exist in every venue.
local function DrawEventCombo()
    local cur = S.venue_cs_event ~= '' and EventLabel(S.venue_cs_event) or '(select)'
    r.ImGui_SetNextItemWidth(ctx, 230)
    if r.ImGui_BeginCombo(ctx, '##cs_event', cur) then
        if r.ImGui_Selectable(ctx, '(none)', S.venue_cs_event == '') then S.venue_cs_event = '' end
        for _, cat in ipairs(VenueShotEvents('directed')) do
            if r.ImGui_Selectable(ctx, EventLabel(cat), S.venue_cs_event == cat) then
                S.venue_cs_event = cat
            end
            if r.ImGui_IsItemHovered(ctx) then EventTooltip(cat) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) and S.venue_cs_event ~= '' then EventTooltip(S.venue_cs_event) end
end

-- Column x offsets for one section, sized to its own content.
-- Styles before Gender, in the order of the filter rows above.
local COLS = { 'Move', 'Focus', 'Styles', 'Gender', 'Venues', 'Variants', 'Lead-in' }

local function RowCells(row)
    return { row.label, VenueShotWhoShort(row.who), StylesText(row.styles),
             GENDER_NAMES[row.gender] or row.gender, VenueShotKindsText(row.kinds),
             tostring(row.variants),
             -- " #": some of this move's versions hold the camera longer than the
             -- 0.25 s floor (row.lock is only set on those rows). A plain Text cell,
             -- so ImGui's "##" id syntax does not apply.
             Range(row.lead[1], row.lead[2]) .. (row.lock and ' #' or '') }
end

-- The Move column gives way: the other columns keep their width, Move takes what is left of
-- the window (down to MOVE_MIN_CHARS characters) and longer labels end in "...", shown whole
-- on hover. A wider window shows more of them.
local MOVE_MIN_CHARS = 18

local function ColumnX(rows)
    local pad = 16
    local widths = {}
    for i, h in ipairs(COLS) do widths[i] = r.ImGui_CalcTextSize(ctx, h) end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(RowCells(row)) do
            local w = r.ImGui_CalcTextSize(ctx, cell)
            if w > widths[i] then widths[i] = w end
        end
    end
    local rest = 0
    for i = 2, #COLS do rest = rest + widths[i] + pad end
    local avail = r.ImGui_GetContentRegionAvail(ctx)
    -- Each call in its own local: as the last argument of math.max, CalcTextSize passes on
    -- every value it returns, and ReaImGui returns nils past w / h ("compare number with nil").
    local head_w = r.ImGui_CalcTextSize(ctx, COLS[1])
    local chars_w = r.ImGui_CalcTextSize(ctx, string.rep('x', MOVE_MIN_CHARS))
    local min_w = math.max(head_w, chars_w)
    widths[1] = math.min(widths[1], math.max(min_w, avail - rest - pad))
    local xs, x = {}, 0
    for i = 1, #COLS do xs[i] = x; x = x + widths[i] + pad end
    return xs, widths[1]
end

-- text cut to fit w pixels with "..." at the end; second value true when it was cut.
local function FitText(text, w)
    local full_w = r.ImGui_CalcTextSize(ctx, text)
    if full_w <= w then return text, false end
    local lo, hi = 0, #text
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        local part_w = r.ImGui_CalcTextSize(ctx, text:sub(1, mid) .. '...')
        if part_w <= w then lo = mid else hi = mid - 1 end
    end
    return text:sub(1, lo):gsub('[%s,:]+$', '') .. '...', true
end

-- Clicking a move: show its camera event with the filters the move pins down, so the moves
-- left undimmed are the ones competing with it. Returns the new S values; applied after the
-- sections are drawn, so one frame never shows a half-changed choice.
local function RowClickPick(cat, row, ev)
    local f = VenueShotRowFilter(row, ev)
    return { venue_cs_mode = 1, venue_cs_event = cat, venue_cs_style = f.style or '',
             venue_cs_gender = f.gender or '', venue_cs_kind = f.kind or '', venue_cs_lineup = '' }
end

local function DrawSection(cat, rows, filter)
    local pick
    local ev = VenueShotEvent(cat)
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, EventLabel(cat))
    if r.ImGui_IsItemHovered(ctx) then EventTooltip(cat) end
    r.ImGui_SameLine(ctx)
    TextDim('[' .. cat .. ']')

    -- Under the name, one fact per line. Timing (dim) always - the lead-in is not
    -- repeated here, each move row has its own; the rest only where the cut is
    -- unusual: one of the game's free cuts (dim), not in every venue (amber),
    -- changed by the chosen band (amber). length is the range the game allows the
    -- cut's clips (its own asset check), not a measured per-venue value - so the
    -- wording says "may".
    r.ImGui_PushTextWrapPos(ctx, 0)
    if ev.length then
        TextDimWrapped('The move may run ' .. Range(ev.length[1], ev.length[2]) .. ' after its event.')
        Tooltip(TIPS.venue_cs_length)
    end
    if ev.lock then
        TextDimWrapped(ev.lock[2] - ev.lock[1] < 0.005
            and ('The camera cannot change for %.2g s after its event.'):format(ev.lock[1])
            or  ('The camera cannot change for %.2g s after its event (some versions: up to %.2g s, '
                 .. 'marked # below).'):format(ev.lock[1], ev.lock[2]))
    end
    if ev.free then
        -- FREE_DIRCUTS (the game's macros.dta): skipped by its style / gender filter.
        TextDimWrapped('Not picked by song style or member gender (a free cut).')
        Tooltip(TIPS.venue_cs_free)
    end
    local kinds = VenueShotKindsText(ev.kinds)
    if kinds ~= 'All' then
        TextColoredWrapped(COL_WARN, 'Not in every venue: only in ' .. kinds
            .. (kinds:find('%*') and ' (* = only some venues of that kind).' or '.'))
    end
    local remap = VenueShotRemap(cat, filter.lineup)
    if remap == 'dropped' then
        TextColoredWrapped(COL_WARN, VENUE_SHOT_LINEUP_LABELS[filter.lineup]
            .. ': dropped, a random generic band shot plays instead.')
    elseif remap then
        local names = {}
        for _, t in ipairs(remap) do names[#names + 1] = EventLabel(t) end
        TextColoredWrapped(COL_WARN, VENUE_SHOT_LINEUP_LABELS[filter.lineup] .. ': becomes '
            .. table.concat(names, ' / ') .. '.')
    end
    r.ImGui_PopTextWrapPos(ctx)

    if not rows or #rows == 0 then rows = ev.moves or {} end

    local playing = 0
    for _, row in ipairs(rows) do
        if VenueShotRowMatches(row, filter, ev) and remap ~= 'dropped' then playing = playing + 1 end
    end
    -- A lineup that drops the cut is already said in the summary line (a random
    -- generic band shot plays). With no move for the song's style / the member's
    -- gender the game has no shot for the cut at all.
    if playing == 0 and remap ~= 'dropped' then
        r.ImGui_PushTextWrapPos(ctx, 0)
        r.ImGui_TextWrapped(ctx, 'None of these moves plays for this choice - the game skips the cut, '
            .. 'and the camera event after it plays right away.')
        r.ImGui_PopTextWrapPos(ctx)
    end

    local xs, move_w = ColumnX(rows)
    local x0 = r.ImGui_GetCursorPosX(ctx)
    for i, h in ipairs(COLS) do
        if i > 1 then r.ImGui_SameLine(ctx, x0 + xs[i]) end
        TextDim(h)
        Tooltip(TIPS['venue_cs_col_' .. i])
    end
    local dim_col = COL_DIM
    for ri, row in ipairs(rows) do
        local on = VenueShotRowMatches(row, filter, ev) and remap ~= 'dropped'
        for i, cell in ipairs(RowCells(row)) do
            if i > 1 then r.ImGui_SameLine(ctx, x0 + xs[i]) end
            if i == 1 then
                -- The move name is a Selectable (hover highlight = clickable), dimmed rows too.
                local shown, cut = FitText(cell, move_w)
                if not on then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), dim_col) end
                local clicked = r.ImGui_Selectable(ctx, shown .. '##csrow_' .. cat .. '_' .. ri, false, 0, move_w)
                if not on then r.ImGui_PopStyleColor(ctx) end
                if clicked then pick = RowClickPick(cat, row, ev) end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, (cut and cell .. '\n\n' or '') .. TIPS.venue_cs_row_click)
                end
            else
                if on then r.ImGui_Text(ctx, cell) else TextDim(cell) end
                if r.ImGui_IsItemHovered(ctx) then
                    if i == 2 and cell ~= row.who then r.ImGui_SetTooltip(ctx, row.who)
                    elseif i == 5 and cell:find('*', 1, true) then r.ImGui_SetTooltip(ctx, TIPS.venue_cs_partial)
                    elseif i == 7 and row.lock then
                        r.ImGui_SetTooltip(ctx, TIPS.venue_cs_lock_row:format(('%.2g'):format(row.lock[2])))
                    end
                end
            end
        end
    end
    return pick
end

function DrawVenueCameraShotsTab()
    r.ImGui_TextWrapped(ctx,
        'What the game can show for each directed camera cut: its moves in every RB3 venue, read '
        .. 'from the game\'s venue files. Pick an event or type a word; the filters dim the '
        .. 'moves that would not play for that song style, focus member and band.')
    r.ImGui_PushTextWrapPos(ctx, 0)
    TextDimWrapped('Normal (coop) camera shots are not listed: they only place the '
        .. 'camera and do not make the band move.')
    r.ImGui_PopTextWrapPos(ctx)
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Search', 'Song style', 'Focus member', 'Venue', 'Band' })
    r.ImGui_Text(ctx, 'Search')
    r.ImGui_SameLine(ctx, lbl_col)
    if r.ImGui_RadioButton(ctx, 'Camera event##cs_mode', S.venue_cs_mode == 1) then S.venue_cs_mode = 1 end
    Tooltip(TIPS.venue_cs_mode_event)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, 'Keyword##cs_mode', S.venue_cs_mode == 2) then S.venue_cs_mode = 2 end
    Tooltip(TIPS.venue_cs_mode_keyword)
    r.ImGui_SameLine(ctx)
    if S.venue_cs_mode == 2 then
        r.ImGui_SetNextItemWidth(ctx, 230)
        local _, txt = r.ImGui_InputText(ctx, '##cs_text', S.venue_cs_text)
        S.venue_cs_text = txt
        Tooltip(TIPS.venue_cs_mode_keyword)
    else
        DrawEventCombo()
    end

    r.ImGui_Text(ctx, 'Song style')
    r.ImGui_SameLine(ctx, lbl_col)
    OptCombo('##cs_style', 'venue_cs_style', STYLE_OPTS, TIPS.venue_cs_style)
    r.ImGui_Text(ctx, 'Focus member')
    r.ImGui_SameLine(ctx, lbl_col)
    OptCombo('##cs_gender', 'venue_cs_gender', GENDER_OPTS, TIPS.venue_cs_gender)
    r.ImGui_Text(ctx, 'Venue')
    r.ImGui_SameLine(ctx, lbl_col)
    OptCombo('##cs_kind', 'venue_cs_kind', KindOpts(), TIPS.venue_cs_kind)
    r.ImGui_Text(ctx, 'Band')
    r.ImGui_SameLine(ctx, lbl_col)
    OptCombo('##cs_lineup', 'venue_cs_lineup', LINEUP_OPTS, TIPS.venue_cs_lineup)

    local filter = CurrentFilter()
    local pick
    if S.venue_cs_mode == 2 then
        local sections, total = VenueShotSearch(S.venue_cs_text, CS_MAX_SECTIONS)
        if S.venue_cs_text:match('%S') and total == 0 then
            r.ImGui_Spacing(ctx)
            r.ImGui_TextWrapped(ctx, 'No camera event or move matches "' .. S.venue_cs_text .. '".')
        end
        for _, sec in ipairs(sections) do pick = DrawSection(sec.cat, sec.rows, filter) or pick end
        if total > #sections then
            r.ImGui_Spacing(ctx)
            r.ImGui_TextWrapped(ctx, ('%d more camera events match - add a word to narrow it down.')
                :format(total - #sections))
        end
    elseif S.venue_cs_event ~= '' and VenueShotEvent(S.venue_cs_event) then
        pick = DrawSection(S.venue_cs_event, nil, filter)
    end
    if pick then
        for k, v in pairs(pick) do S[k] = v end
    end
end
