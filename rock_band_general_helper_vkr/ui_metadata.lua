-- Metadata tab rendering.
--
-- Song-level properties, as opposed to every other tab in this script, which operates on
-- tracks, notes or events. Two sub-tabs: Genre and Difficulty.
--
-- Genre is drawn by ui_metadata_genre.lua; this file only wraps it in a tab item. It is
-- first because it is a pure lookup that needs no project at all, so it works in an
-- empty session, while Difficulty needs finished charts to say anything.
--
-- READ-ONLY. Nothing in this file writes to the project. There is deliberately no
-- "apply this rank" control: the suggestion is advisory, the author's judgment is final,
-- and a one-click apply would quietly turn an estimate into the answer.
--
-- Requires globals: r, ctx, S, TIPS, Btn, BTN_H, Tooltip, SectionHeader, LabelColWidth,
--                   RunAction, SuggestProjectDifficulties, HasAnyChartTrack
--                   (difficulty_suggester.lua)

-- Amber for advisory notes, matching the inline warnings elsewhere in this script.
local COL_WARN = 0xFFAA00FF

----------------------------------------------------------------------
-- The difficulty dots
--
-- Rock Band shows an instrument's difficulty as five dots, filled from the left, and turns
-- them red at the very top of the scale. Reproducing that is worth more than the tier name
-- alone: it is the form authors already read in-game, and five dots are comparable at a
-- glance down a column of six instruments in a way that six different words are not.
--
-- Seven tiers map onto five dots because the top two share the filled count: Warmup is
-- none, Nightmare is five, and Impossible is five in red. That is the game's own display,
-- not a compression introduced here.
--
-- An unfilled dot is drawn mid-grey on a near-black plate rather than black on the window
-- background. Black-on-dark is invisible in this theme, and the plate is also what makes
-- the five positions readable as a fixed-width scale when only one is filled.
----------------------------------------------------------------------

local DOT_FILLED = 0xFFFFFFFF   -- earned
local DOT_EMPTY  = 0x5A5A5AFF   -- unearned; grey, not black - see above
local DOT_MAX    = 0xE04444FF   -- Impossible, matching the game's red
local DOT_PLATE  = 0x1E1E1EFF

local function DrawDifficultyDots(tier)
    local h    = r.ImGui_GetTextLineHeight(ctx)
    local rad  = h * 0.22
    local gap  = rad * 2.8
    local pad  = rad * 1.4
    local w    = pad * 2 + gap * 4 + rad * 2
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local dl   = r.ImGui_GetWindowDrawList(ctx)

    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, DOT_PLATE, 3)

    local filled = math.min(tier or 0, 5)
    local maxed  = (tier == 6)
    for i = 1, 5 do
        local col = maxed and DOT_MAX
                 or (i <= filled and DOT_FILLED or DOT_EMPTY)
        r.ImGui_DrawList_AddCircleFilled(dl, x + pad + rad + (i - 1) * gap, y + h * 0.5,
                                         rad, col)
    end
    -- Reserves the layout box so SameLine and the tooltip below have something to attach
    -- to; the drawing above is on the window draw list and occupies no layout space.
    r.ImGui_Dummy(ctx, w, h)
end

----------------------------------------------------------------------
-- The tier ruler
--
-- Where the suggestion landed between the tier it earned and the next one up, with the
-- ranks that separate them. It replaced a line of prose ("near the bottom of this tier")
-- that said the same thing as the amber boundary warning below it while carrying none of
-- the numbers - the reader could see it was close without seeing how close.
--
-- DRAWN, NOT SPELLED WITH DASHES. `Solid (176) - - - | - - Moderate (221)` was the shape
-- this started from, and it does not survive a proportional font: nothing in this repo
-- loads a monospace one, so the dash columns drift between cards and the marker lands
-- near its value rather than on it. The DrawList idiom next door in DrawDifficultyDots
-- puts the tick exactly where the number is. The dashed form is still the right answer in
-- dev/tools/verify_suggester_vs_csv.lua, which prints to a monospace console.
----------------------------------------------------------------------

local function DrawTierRuler(ruler)
    local h    = r.ImGui_GetTextLineHeight(ctx)
    local w    = h * 13          -- fixed, so six stacked cards read as one scale
    local pad  = h * 0.5         -- keeps the end caps and a pinned marker inside the plate
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local dl   = r.ImGui_GetWindowDrawList(ctx)

    local x0, x1 = x + pad, x + w - pad
    local mid    = y + h * 0.5

    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, DOT_PLATE, 3)
    r.ImGui_DrawList_AddLine(dl, x0, mid, x1, mid, DOT_EMPTY, 1.0)

    -- End caps full height, interior ticks half, so the band's own edges stay legible as
    -- edges when the marker happens to sit on one.
    for i = 0, 6 do
        local tx  = x0 + (x1 - x0) * (i / 6)
        local cap = (i == 0 or i == 6)
        local hh  = cap and h * 0.30 or h * 0.16
        r.ImGui_DrawList_AddLine(dl, tx, mid - hh, tx, mid + hh, DOT_EMPTY, 1.0)
    end

    -- The marker. Amber and hard against the end when the rank was clamped: a pinned rank
    -- is not a position on this scale, it is a limit, and drawing it as an ordinary tick
    -- somewhere along the band would claim a precision the clamp exists to deny.
    local pos = math.max(0, math.min(1, ruler.pos or 0))
    if ruler.pinned == 'lo' then pos = 0 elseif ruler.pinned == 'hi' then pos = 1 end
    local mx  = x0 + (x1 - x0) * pos
    local col = ruler.pinned and COL_WARN or DOT_FILLED
    local tw  = h * 0.22
    r.ImGui_DrawList_AddTriangleFilled(dl, mx, mid, mx - tw, mid - h * 0.36,
                                       mx + tw, mid - h * 0.36, col)
    r.ImGui_DrawList_AddLine(dl, mx, mid - h * 0.36, mx, mid + h * 0.30, col, 1.5)

    -- Reserves the layout box: the drawing above is on the window draw list and occupies
    -- no layout space, so SameLine and the tooltip would otherwise have nothing to sit on.
    r.ImGui_Dummy(ctx, w, h)
end

----------------------------------------------------------------------
-- The action
----------------------------------------------------------------------

-- On demand rather than continuously: scoring six charts walks every note on every PART
-- track, which is far too much to repeat per frame, and a number that silently changed
-- while an author was reading it would be worse than a stale one.
local function RefreshSuggestions()
    S.last_result = nil   -- the cards are drawn in-tab; a leftover report would duplicate

    if not HasAnyChartTrack() then
        S.diff_suggestions = nil
        S.status = 'No Rock Band PART tracks found in this project.'
        return
    end

    local recs = SuggestProjectDifficulties()
    S.diff_suggestions = recs

    local scored = 0
    for _, rec in ipairs(recs) do
        if rec.ok then scored = scored + 1 end
    end
    S.status = ('Difficulty: %d of %d parts scored.'):format(scored, #recs)
end

-- Copy every scored part to the clipboard as plain text.
--
-- The formatting is difficulty_report.lua's job so it can be tested without a UI; this is
-- only the acquisition of the two things that need REAPER - the project name and the
-- clipboard - plus the confirmation, because a clipboard write is otherwise completely
-- invisible and an author cannot tell a working button from a dead one.
local function CopySuggestionDetails()
    local recs = S.diff_suggestions
    if not recs then return end

    -- GetProjectName's signature has changed across REAPER versions, and the report is
    -- perfectly readable without it, so a failure here drops the header line rather than
    -- the whole copy.
    local ok, name = pcall(function() return r.GetProjectName(0, '') end)
    if not ok or type(name) ~= 'string' then name = nil end

    local text = DifficultyReportText(recs, { project = name })
    r.ImGui_SetClipboardText(ctx, text)

    local n = select(2, text:gsub('\n', '\n')) + 1
    S.status = ('Copied %d lines to the clipboard.'):format(n)
end

----------------------------------------------------------------------
-- One instrument card
----------------------------------------------------------------------

local function DrawCard(rec, lbl_col)
    -- Instrument name, then the model-maturity chip. The chip is the at-a-glance marker;
    -- the sentence explaining it arrives with the warnings below, so neither has to do
    -- both jobs.
    r.ImGui_Text(ctx, rec.label)
    if rec.badge then
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, COL_WARN, '[' .. rec.badge .. ']')
        -- What the chip means lives here rather than as a line on the card: the wording is
        -- a property of the model, identical on every keys/Pro Keys/vocals result in every
        -- project, so on the card it would be permanent clutter sitting exactly where the
        -- chart-specific notes need to be noticed.
        Tooltip(DIFFICULTY_STATUS_NOTE[rec.status or ''] or '')
    end

    r.ImGui_Indent(ctx)

    if not rec.ok then
        -- An expected part that cannot be scored still gets a row. Dropping it silently
        -- looks identical to the tool not having noticed the instrument, and the reason
        -- ("PART KEYS not found" vs "PART KEYS is muted") is usually the whole answer.
        r.ImGui_TextDisabled(ctx, rec.reason or 'No chart')
        r.ImGui_Unindent(ctx)
        return
    end

    DrawDifficultyDots(rec.tier)
    Tooltip(TIPS.diff_dots)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, ('%s (rank %d)')
        :format(rec.tier_name, math.floor(rec.rank + 0.5)))
    if rec.ruler then
        -- The band's own name on the left, what lies above it on the right, the ruler
        -- between. lbl_col comes from the whole card set rather than this card, so the six
        -- rulers start at one x and can be read down the column as a single scale.
        --
        -- OFFSET FROM THIS ROW'S OWN START, NOT FROM ZERO. SameLine(ctx, x) is an absolute
        -- position measured from the window's content edge and it does NOT include the
        -- Indent the card body is sitting inside - so passing lbl_col alone leaves the
        -- label only (lbl_col - indent) of room and the ruler overlaps the end of the
        -- longest one. Reading the cursor first also keeps this correct if the card ever
        -- gains or loses an indent level.
        local row_x = r.ImGui_GetCursorPosX(ctx)
        r.ImGui_TextDisabled(ctx, rec.ruler.lo_label)
        r.ImGui_SameLine(ctx, row_x + lbl_col)
        DrawTierRuler(rec.ruler)
        -- The prose that used to be a line of its own. Same words, no longer competing
        -- with the boundary warning for the reader's attention.
        Tooltip(rec.position_text and (TIPS.diff_ruler .. '\n\n' .. 'This one is '
                .. rec.position_text .. '.') or TIPS.diff_ruler)
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, rec.ruler.hi_label)
    end

    for _, w in ipairs(rec.warnings or {}) do
        r.ImGui_TextColored(ctx, COL_WARN, '!')
        r.ImGui_SameLine(ctx)
        -- Wrapped: the concentration and beyond-the-references notes are full sentences and
        -- will clip on any sensible window width otherwise.
        r.ImGui_TextWrapped(ctx, w.text)
    end

    -- The plain-language properties are ALWAYS VISIBLE. They are the answer to "why that
    -- rank" and are the part of this panel written for the reader; hiding them behind a
    -- disclosure put the useful half of the card one click away from everyone.
    if #(rec.explanations or {}) > 0 then
        for _, e in ipairs(rec.explanations) do
            r.ImGui_Bullet(ctx)
            r.ImGui_TextWrapped(ctx, e.text)
            -- Each bullet explains its own terminology on hover. "Large average chord
            -- load" is only an explanation if the reader knows what chord load is.
            if e.tip then Tooltip(e.tip) end
        end
    else
        r.ImGui_TextDisabled(ctx, 'Nothing about this chart stands out from the reference songs.')
    end

    -- The raw measurements are the development view: useful when comparing against the
    -- calibration corpus, meaningless to an author. Off unless asked for, and then still
    -- behind a disclosure, because it is six instruments' worth of table.
    -- Gated on the WIP flag as well as the checkbox, because the checkbox itself is only
    -- drawn when that flag is on: ticking it and then turning work-in-progress off would
    -- otherwise leave a Details panel open with nothing on screen able to close it.
    if S.show_wip_tabs and S.diff_show_factors then
        if r.ImGui_CollapsingHeader(ctx, 'Details##diffdet_' .. rec.instrument) then
            r.ImGui_Indent(ctx)
            -- The uncapped score, shown ONLY here. It is the number the clamp replaced,
            -- and it is untrustworthy by construction - a log-scale fit exponentiates, so
            -- one extreme input can produce a value that is not a rank at all. On the card
            -- it would read as the real answer; in the development view it is exactly what
            -- someone comparing against the corpus wants to see.
            if rec.clamped and rec.raw_rank then
                r.ImGui_TextDisabled(ctx,
                    ('Uncapped score: %.0f (shown as %d)'):format(rec.raw_rank, rec.rank))
            end
            r.ImGui_TextDisabled(ctx, 'Measured value, and how unusual it is:')
            Tooltip(TIPS.diff_suggest_why)
            for _, row in ipairs(rec.factor_rows or {}) do
                r.ImGui_Text(ctx, row.label)
                if row.tip then Tooltip(row.tip) end
                r.ImGui_SameLine(ctx, 240)
                if row.out_of then
                    -- Amber and named, but only here. On the card this read as a reason for
                    -- the rank; beside the number it is what it actually is - a measurement
                    -- no reference song reached.
                    r.ImGui_TextColored(ctx, COL_WARN, ('%-10s %+.1f sd   (%s any reference song)')
                        :format(row.value, row.z, row.out_of == 'above' and 'above' or 'below'))
                else
                    r.ImGui_Text(ctx, ('%-10s %+.1f sd'):format(row.value, row.z))
                end
            end
            r.ImGui_Unindent(ctx)
        end
    end

    r.ImGui_Unindent(ctx)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

function DrawMetadataTab(ctx)
    if r.ImGui_BeginTabBar(ctx, '##metadata_subtabs') then

        ------------------------------------------------
        -- Metadata > Genre sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Genre') then
            DrawMetadataGenreTab(ctx)
            r.ImGui_EndTabItem(ctx)
        end

        ------------------------------------------------
        -- Metadata > Difficulty sub-tab
        ------------------------------------------------
        if r.ImGui_BeginTabItem(ctx, 'Difficulty') then
            SectionHeader('Suggested difficulty (Beta)')

            r.ImGui_TextWrapped(ctx,
                'Estimates a rank and tier for each finished Expert chart in this ' ..
                'project, from measurements of the charts themselves. ' ..
                'Advisory only, treat with a grain of salt. The whole chart is ' ..
                'scored - a time selection does not change the result.')
            r.ImGui_Spacing(ctx)

            -- BOTH DEVELOPER CONTROLS SIT BEHIND General > Other > work-in-progress.
            --
            -- The first release is being shown to authors to find out whether the
            -- suggestion itself reads correctly, and the two of them answer a different
            -- question: the raw factor table is a calibration view, and Copy details
            -- exists to move those same numbers into a discussion. Neither helps an author
            -- decide a rank, and on the default panel they invite the reader to treat the
            -- measurements as the point. They stay one checkbox away rather than removed,
            -- because they are exactly what is wanted the moment a suggestion is disputed.
            local dev_tools = S.show_wip_tabs

            -- One width for the group, so the row reads as a group rather than as buttons
            -- that happen to be adjacent. Measured over every label that can appear, so
            -- Refresh does not change width when the WIP flag is toggled.
            local bw = BtnGroupWidth({ 'Refresh suggestions', 'Copy details' })

            if Btn('Refresh suggestions', BTN_H, bw) then
                RunAction(RefreshSuggestions)
            end
            Tooltip(TIPS.diff_suggest_refresh)

            if dev_tools then
                r.ImGui_SameLine(ctx)
                -- Snapshotted once: the Refresh above can populate S.diff_suggestions
                -- mid-frame, which would leave BeginDisabled without its EndDisabled.
                local no_recs = (S.diff_suggestions == nil)
                if no_recs then r.ImGui_BeginDisabled(ctx) end
                if Btn('Copy details', BTN_H, bw) then
                    RunAction(CopySuggestionDetails)
                end
                Tooltip(TIPS.diff_copy)
                if no_recs then r.ImGui_EndDisabled(ctx) end

                r.ImGui_SameLine(ctx)
                _, S.diff_show_factors =
                    r.ImGui_Checkbox(ctx, 'Show measured values', S.diff_show_factors)
                Tooltip(TIPS.diff_show_factors)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)

            local recs = S.diff_suggestions
            if not recs then
                r.ImGui_Spacing(ctx)
                r.ImGui_TextWrapped(ctx,
                    'No suggestions yet. Press Refresh suggestions to score this project.')
            else
                -- One column position for every card's left ruler label, measured across
                -- all six: 'Warmup (1)' and 'Challenging (333)' are very different widths,
                -- and sizing each card to its own label would stagger the rulers down the
                -- panel just where they most need to be compared.
                local edge_labels = {}
                for _, rec in ipairs(recs) do
                    if rec.ruler then edge_labels[#edge_labels + 1] = rec.ruler.lo_label end
                end
                local lbl_col = LabelColWidth(edge_labels)

                for i, rec in ipairs(recs) do
                    if i > 1 then r.ImGui_Separator(ctx) end
                    r.ImGui_Spacing(ctx)
                    DrawCard(rec, lbl_col)
                    r.ImGui_Spacing(ctx)
                end
            end

            r.ImGui_EndTabItem(ctx)
        end

        r.ImGui_EndTabBar(ctx)
    end
end
