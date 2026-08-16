-- Metadata > Genre sub-tab rendering.
--
-- Converts a real-world genre into the closest supported Rock Band major genre and
-- subgenre. One direction only, by deliberate choice for the first release: a reverse
-- view (pick a supported genre, see what maps onto it) was built and then dropped,
-- because browsing the supported list is not a task an author actually has - they arrive
-- knowing what their song is and needing the other half. The lookup side of it is still
-- there and still tested (BuildReverseGenreIndex / ExtendedGenresForPair in
-- metadata_genres_lookup.lua), so restoring the view is a UI-only change if a use case
-- turns up. Keeping one direction keeps this tab to two combos and a result.
--
-- READ-ONLY, and more strictly so than the Difficulty sub-tab beside it: this one does
-- not even read the project. It is a lookup over two static tables, so there is no
-- Refresh button, nothing to recompute on a project switch, and no undo point ever.
--
-- Display names only, never .dta tokens. Token spellings drift between game eras and
-- the packaging tool that writes songs.dta has its own picker; printing a token here
-- would invite pasting a string this repo cannot stand behind. See metadata_genres.lua.
--
-- Results are drawn INLINE rather than into S.last_result: they change as the combo
-- moves, and the shared panel is wiped whenever the main tab changes.
--
-- Requires globals: r, ctx, S, TIPS, Tooltip, SectionHeader, LabelColWidth, WIDTH_STD,
--                   GENRE_FAMILY_ORDER, GENRE_FAMILIES (metadata_genres_ext.lua),
--                   GenresInFamily, ResolveExtendedGenre (metadata_genres_lookup.lua)

-- Secondary text that still has to wrap. ImGui's TextDisabled has no wrapping variant,
-- so the colour is pushed by hand around a TextWrapped.
local function DimWrapped(text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x9A9A9AFF)
    r.ImGui_TextWrapped(ctx, text)
    r.ImGui_PopStyleColor(ctx)
end

-- Clamp an index into a list that may have changed length. Always returns >= 1 so the
-- combos below can index without a nil guard.
local function ClampIdx(i, n)
    if n <= 0 then return 1 end
    if not i or i < 1 then return 1 end
    if i > n then return n end
    return i
end

-- The optional documentation for one supported subgenre. Most subgenres carry none of
-- this, so every line is conditional and the block can render as nothing at all.
local function DrawSubgenreDoc(sub)
    if sub.elements then DimWrapped('Typical elements: ' .. sub.elements) end
    if sub.artists  then DimWrapped('Example artists: '  .. sub.artists)  end
    if sub.albums   then DimWrapped('Example albums: '   .. sub.albums)   end
end

----------------------------------------------------------------------
-- Forward: my genre -> supported
----------------------------------------------------------------------

local function DrawForward(lbl_col)
    -- Family selector. Narrowing by family first keeps the genre list short enough to
    -- read; the full extended vocabulary runs past 200 entries.
    S.genre_family_idx = ClampIdx(S.genre_family_idx, #GENRE_FAMILY_ORDER)
    local fam_key = GENRE_FAMILY_ORDER[S.genre_family_idx]

    r.ImGui_Text(ctx, 'Family')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##genre_family', GENRE_FAMILIES[fam_key]) then
        for i, fk in ipairs(GENRE_FAMILY_ORDER) do
            local is_sel = (i == S.genre_family_idx)
            if r.ImGui_Selectable(ctx, GENRE_FAMILIES[fk], is_sel) then
                if i ~= S.genre_family_idx then
                    S.genre_family_idx = i
                    -- The genre index addresses the previous family's list, so keeping
                    -- it would silently select an unrelated entry.
                    S.genre_ext_idx = 1
                end
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.genre_family)

    fam_key = GENRE_FAMILY_ORDER[S.genre_family_idx]
    local entries = GenresInFamily(fam_key)
    S.genre_ext_idx = ClampIdx(S.genre_ext_idx, #entries)

    r.ImGui_Text(ctx, 'Your genre')
    r.ImGui_SameLine(ctx, lbl_col)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    local cur = entries[S.genre_ext_idx]
    if r.ImGui_BeginCombo(ctx, '##genre_pick', cur and cur.label or '(none)') then
        for i, e in ipairs(entries) do
            local is_sel = (i == S.genre_ext_idx)
            if r.ImGui_Selectable(ctx, e.label, is_sel) then S.genre_ext_idx = i end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.genre_pick)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    if not cur then
        r.ImGui_TextWrapped(ctx, 'No genres in this family.')
        return
    end

    local res = ResolveExtendedGenre(cur.key)
    if not res or #res.candidates == 0 then
        r.ImGui_TextWrapped(ctx, 'No supported genre is mapped to this entry yet.')
        return
    end

    if #res.candidates > 1 then
        r.ImGui_TextWrapped(ctx, ('%s maps more than one way. The first is the usual pick; ')
            :format(res.label) .. 'the others are there because the catalogue really does split.')
        Tooltip(TIPS.genre_candidates)
        r.ImGui_Spacing(ctx)
    end

    for i, c in ipairs(res.candidates) do
        r.ImGui_Text(ctx, ('%d.  %s  /  %s'):format(i, c.genre_label, c.sub_label))
        r.ImGui_Indent(ctx)
        r.ImGui_TextWrapped(ctx, c.why)
        if c.sub.blurb and c.sub.blurb ~= '' then
            DimWrapped('Described as: ' .. c.sub.blurb)
        end
        DrawSubgenreDoc(c.sub)
        r.ImGui_Unindent(ctx)
        if i < #res.candidates then r.ImGui_Spacing(ctx) end
    end

    -- Deliberately unnumbered and below a separator: these point at a different entry in
    -- this tool, not at another supported home for the one selected. Numbering them
    -- alongside the candidates is exactly the confusion this split exists to remove.
    if #res.see_also > 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        for _, sa in ipairs(res.see_also) do
            DimWrapped(('If %s, see "%s" instead.'):format(sa.when, sa.label))
        end
        Tooltip(TIPS.genre_see_also)
    end
end

----------------------------------------------------------------------

function DrawMetadataGenreTab(ctx)
    SectionHeader('Genre converter')

    r.ImGui_TextWrapped(ctx,
        'Rock Band accepts 29 major genres and 126 subgenres. Pick the genre you would ' ..
        'actually call the song and this suggests the closest supported pair. ' ..
        'Advisory only, treat with a grain of salt. ' ..
        'Names only - enter them in whichever tool writes your song metadata.')
    r.ImGui_Spacing(ctx)
    -- Two different caveats, and they are not interchangeable. The first is about THIS
    -- tool: which supported pair a style belongs to was decided by hand, so a reader who
    -- disagrees is not misusing the tool and their disagreement is the correction
    -- mechanism. The second is about the supported list itself, which says the same of
    -- its own contents. Metadata > Difficulty carries only the first kind, because its
    -- inputs are measurements rather than somebody's opinion.
    DimWrapped(
        'Where a style belongs is a judgment call, and some genres genuinely map more ' ..
        'than one way. If a suggestion looks plainly wrong to you, it is worth saying ' ..
        'so - these mappings are meant to be corrected.')
    r.ImGui_Spacing(ctx)

    DrawForward(LabelColWidth({ 'Your genre', 'Family' }))
end
