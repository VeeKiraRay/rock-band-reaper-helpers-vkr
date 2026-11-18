-- Metadata > Score: the score each Expert part can reach with a full combo, its star
-- cut-offs, and whether overdrive (deployed as soon as possible) reaches gold stars.
--
-- READ-ONLY. On demand, like Metadata > Difficulty: the numbers describe the charts as
-- they were when Calculate was pressed. Meant to be used beside the Instrument Helper's
-- Overdrive tab - change the overdrive there, press Calculate here.
--
-- The model is lib/reaper_score_sim.lua (the game's rules, with the sources), the
-- project reading lib/reaper_score_read.lua.
--
-- Every part is read from the tracks as they are: a missing or muted track gets a card
-- saying so. PART DRUMS_2X is the exception - its card appears only when the track is
-- there and unmuted (SCORE_PARTS' `optional`).
--
-- Requires globals: r, ctx, S, TIPS, Btn, BTN_H, Tooltip, SectionHeader, RunAction,
--                   SetCopyView, ScoreReadSong, ScoreSimulatePart, ScoreFindings,
--                   ScoreCoverageText, ScoreBarOf, ScoreNum, ScoreReportText, SCORE_PARTS

-- Colours are the shared COL_* (lib/reaper_imgui_helpers.lua). "Short of gold" is
-- COL_ERROR, not COL_WARN: something to fix or at least look at, and amber sits too
-- close to the gold used all over this tab to stand out.

-- 123456 -> "123,456" (lib/reaper_score_read.lua; looked up at call time, so load order
-- does not matter).
local function Num(n) return ScoreNum(n) end

-- ASCII '*' for a star, as the game's own star_ratings symbols ('*' .. '*****'): the
-- default font has no star glyph we can rely on.
local STAR_NAMES = { '1*', '2*', '3*', '4*', '5*' }

----------------------------------------------------------------------
-- The action
----------------------------------------------------------------------

-- One simulated run as the card shows it.
local function Run(part, opts, label)
    local res = ScoreSimulatePart(part, opts)
    res.label = label
    return res
end

function ScoreProjectParts()
    S.last_result = nil
    local song = ScoreReadSong()
    local cards = {}
    local found = 0
    for _, spec in ipairs(SCORE_PARTS) do
        local part = song.parts[spec.key]
        -- An optional part (PART DRUMS_2X) that is not there gets no card at all.
        if part or not spec.optional then
            local card = { key = spec.key, kind = spec.kind, label = spec.label,
                           reason = song.reasons[spec.key] }
            if part then
                found = found + 1
                if spec.kind == 'drums' then
                    card.runs = { Run(part, { pro = true }, 'Pro drums'),
                                  Run(part, { pro = false }, 'Drums') }
                else
                    card.runs = { Run(part, {}, nil) }
                end
                card.findings = ScoreFindings(card.runs[1], song.bars, spec.kind)
            end
            cards[#cards + 1] = card
        end
    end
    S.score_result = { cards = cards, bars = song.bars, no_beat = song.no_beat }
    S.status = found == 0 and 'Score: no Expert parts found.'
               or ('Score: %d of %d parts calculated.'):format(found, #cards)
end

----------------------------------------------------------------------
-- One card
----------------------------------------------------------------------

-- Rows in reading order: what each star needs, the full combo without overdrive, the
-- score with it. Coverage and findings follow in DrawCard.
local function DrawRun(res, bars)
    if res.label then TextDim(res.label) end

    local parts = {}
    for i = 1, 5 do parts[i] = ('%s %s'):format(STAR_NAMES[i], Num(res.stars[i])) end
    r.ImGui_Text(ctx, 'Stars: ' .. table.concat(parts, '  '))
    Tooltip(TIPS.score_stars)
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, COL_GOLD, 'Gold ' .. Num(res.stars[6]))
    Tooltip(TIPS.score_stars)

    r.ImGui_Text(ctx, ('FC without OD: %s'):format(
        Num(res.base_streak + res.base_bonus)))
    if res.base_bonus > 0 then
        r.ImGui_SameLine(ctx)
        TextDim(('(%s of it bonus)'):format(Num(res.base_bonus)))
    end

    local got = ('FC with OD: %s (%s)'):format(Num(res.total),
        res.stars_reached == 6 and 'gold' or (res.stars_reached .. '*'))
    if res.gold_qn then
        r.ImGui_TextColored(ctx, COL_GOLD, ('%s - gold from bar %d'):format(
            got, ScoreBarOf(bars, res.gold_qn)))
    else
        r.ImGui_TextColored(ctx, COL_ERROR, ('%s - short of gold by %s'):format(
            got, Num(res.gold_short)))
    end
    Tooltip(TIPS.score_od)
    -- The played BRE is the one part of the score that depends on how it is played (how
    -- often each lane is hit), so its share is named: the total assumes the most.
    if res.bre_points and res.bre_points > 0 then
        r.ImGui_SameLine(ctx)
        TextDim(('(up to %s of it from the Big Rock Ending)'):format(
            Num(res.bre_points)))
        Tooltip(TIPS.score_bre)
    end
end

local function DrawCard(card, bars)
    r.ImGui_Text(ctx, card.label)
    -- How vocal scoring and deploying work: on the label, not as a tag. The model follows
    -- the game's own rules (lib/reaper_score_sim.lua); only slides are approximated.
    if card.kind == 'vocals' and card.runs then Tooltip(TIPS.score_vocals) end
    r.ImGui_Indent(ctx)
    if not card.runs then
        TextDim(card.reason or 'No chart')
        r.ImGui_Unindent(ctx)
        return
    end
    for i, res in ipairs(card.runs) do
        if i > 1 then r.ImGui_Spacing(ctx) end
        DrawRun(res, bars)
        if card.kind == 'drums' and i == 1 then Tooltip(TIPS.score_pro) end
    end

    local cov = ScoreCoverageText(card.runs[1])
    r.ImGui_Text(ctx, cov or 'Never in OD.')
    Tooltip(TIPS.score_coverage)
    -- Levels (ScoreFindings): a warning gets "!", advice is amber (worth a look, not an
    -- error), a harmless note about the chart and information about the simulated path
    -- are grey.
    for _, f in ipairs(card.findings or {}) do
        if f.level == 'warn' then
            r.ImGui_TextColored(ctx, COL_WARN, '!')
            r.ImGui_SameLine(ctx)
            r.ImGui_TextWrapped(ctx, f.text)
        else
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), f.level == 'advice' and COL_WARN
                or COL_DIM)
            r.ImGui_TextWrapped(ctx, f.text)
            r.ImGui_PopStyleColor(ctx)
        end
    end
    r.ImGui_Unindent(ctx)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

function DrawMetadataScoreTab(ctx)
    SectionHeader('Score and stars')
    r.ImGui_TextWrapped(ctx,
        'The score each Expert part reaches with a full combo (FC), its star cut-offs, and ' ..
        'whether gold stars are in reach. Uses the game\'s own scoring rules. ' ..
        'Overdrive (OD) is deployed as soon as it is useful (not into a rest or an ' ..
        'instrumental break) - except at the end: when that would ' ..
        'leave the last overdrive unusable, an earlier one is held so it can be used. ' ..
        'That is a simple plan, not the best one, so a player with a better plan can ' ..
        'score more. The whole song is read - a time selection does not change the result.')
    r.ImGui_Spacing(ctx)

    if Btn('Calculate', BTN_H) then RunAction(ScoreProjectParts) end
    Tooltip(TIPS.score_calculate)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)

    local result = S.score_result
    if not result then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, 'Nothing calculated yet. Press Calculate to score this project.')
        return
    end
    -- Copy result copies these cards as text (ScoreReportText, the same order).
    SetCopyView(function() return ScoreReportText(result) end)
    if result.no_beat then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextColored(ctx, COL_WARN, '!')
        r.ImGui_SameLine(ctx)
        r.ImGui_TextWrapped(ctx, 'No BEAT track: overdrive drain is estimated at one beat ' ..
            'per quarter note. The game drains per BEAT note (Animation > Beat writes them).')
    end
    for i, card in ipairs(result.cards) do
        if i > 1 then r.ImGui_Separator(ctx) end
        r.ImGui_Spacing(ctx)
        DrawCard(card, result.bars)
        r.ImGui_Spacing(ctx)
    end
end
