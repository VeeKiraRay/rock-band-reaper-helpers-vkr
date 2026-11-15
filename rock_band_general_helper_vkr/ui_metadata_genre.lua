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
-- A second mode, shown first: Animation style - the game's genre -> band animation style
-- table (metadata_genres.lua). The converter's result names each pair's style too.
--
-- Requires globals: r, ctx, S, TIPS, Tooltip, SectionHeader, LabelColWidth, WIDTH_STD,
--                   RB3_GENRE_ORDER, RB3_GENRES, ANIM_STYLE_ORDER, ANIM_STYLES,
--                   GENRE_ANIM_STYLE, GenreAnimStyle (metadata_genres.lua),
--                   GENRE_FAMILY_ORDER, GENRE_FAMILIES (metadata_genres_ext.lua),
--                   GenresInFamily, ResolveExtendedGenre (metadata_genres_lookup.lua)


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
    if sub.elements then TextDimWrapped('Typical elements: ' .. sub.elements) end
    if sub.artists  then TextDimWrapped('Example artists: '  .. sub.artists)  end
    if sub.albums   then TextDimWrapped('Example albums: '   .. sub.albums)   end
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
        r.ImGui_Text(ctx, 'Animation style: ' .. GenreAnimStyle(c.genre_key).label)
        r.ImGui_TextWrapped(ctx, c.why)
        if c.sub.blurb and c.sub.blurb ~= '' then
            TextDimWrapped('Described as: ' .. c.sub.blurb)
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
            TextDimWrapped(('If %s, see "%s" instead.'):format(sa.when, sa.label))
        end
        Tooltip(TIPS.genre_see_also)
    end
end

----------------------------------------------------------------------
-- Animation style: which supported genre gives which band style
----------------------------------------------------------------------

local function DrawAnimStyles()
    r.ImGui_TextWrapped(ctx,
        'The song\'s major genre picks how the band moves in game: one of four animation ' ..
        'styles, for the whole band. It also changes which directed camera cuts are ' ..
        'available, since some cuts exist only for one style. A genre the game does not ' ..
        'know gets Rocker.')
    r.ImGui_Spacing(ctx)
    TextDimWrapped(
        'Official songs have set the style per song inside their own game files, and many ' ..
        'differ from this table. A custom song built with Magma has no such setting, so ' ..
        'its genre decides the style - unless the built song is edited afterwards with a ' ..
        'community tool such as MiloMod, which can set it for customs.')

    for _, key in ipairs(ANIM_STYLE_ORDER) do
        local st = ANIM_STYLES[key]
        local names = {}
        for _, gk in ipairs(RB3_GENRE_ORDER) do
            if GENRE_ANIM_STYLE[gk] == key then names[#names + 1] = RB3_GENRES[gk].label end
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, st.label)
        r.ImGui_Indent(ctx)
        r.ImGui_TextWrapped(ctx, table.concat(names, ', '))
        r.ImGui_Unindent(ctx)
    end

    -- What else picks the moves (game files: the clip bank is
    -- instrument x character gender x anim_tempo x style; the per-part animation
    -- events then pick moves inside it).
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'What else shapes the animations')
    r.ImGui_Indent(ctx)
    r.ImGui_TextWrapped(ctx,
        'The style is one of four things that pick the set of moves a band member uses:')
    r.ImGui_TextWrapped(ctx, '- Instrument: each part has its own moves.')
    r.ImGui_TextWrapped(ctx, '- Gender: each character\'s own, set in the character ' ..
        'creator - not song data. Some directed cuts have moves for one gender only: a ' ..
        'male guitarist can slide on his knees, a female guitarist blows a kiss to the ' ..
        'camera (Dramatic songs only).')
    r.ImGui_TextWrapped(ctx, '- Speed: Magma\'s Animation speed (anim_tempo in ' ..
        'songs.dta) - slow, medium or fast. A missing value counts as medium.')
    r.ImGui_TextWrapped(ctx, '- Style: from the genre, as above.')
    r.ImGui_Spacing(ctx)
    r.ImGui_TextWrapped(ctx,
        'During the song, each part\'s animation events ([idle], [play], [mellow], ' ..
        '[intense], ...) choose which of those moves play - see the Animation tab\'s ' ..
        'Character sub-tab.')
    r.ImGui_Unindent(ctx)
end

----------------------------------------------------------------------

local MODE_LABELS = { 'Animation style', 'Genre converter' }

function DrawMetadataGenreTab(ctx)
    -- Mode: one view at a time. Session only, like the converter's combos.
    local mode = S.genre_mode == 2 and 2 or 1
    if r.ImGui_RadioButton(ctx, MODE_LABELS[1] .. '##genre_mode', mode == 1) then S.genre_mode = 1 end
    Tooltip(TIPS.genre_mode_style)
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, MODE_LABELS[2] .. '##genre_mode', mode == 2) then S.genre_mode = 2 end
    Tooltip(TIPS.genre_mode_converter)
    r.ImGui_Spacing(ctx)

    if mode == 1 then
        SectionHeader('Animation style')
        DrawAnimStyles()
        return
    end

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
    TextDimWrapped(
        'Where a style belongs is a judgment call, and some genres genuinely map more ' ..
        'than one way. If a suggestion looks plainly wrong to you, it is worth saying ' ..
        'so - these mappings are meant to be corrected.')
    r.ImGui_Spacing(ctx)

    DrawForward(LabelColWidth({ 'Your genre', 'Family' }))
end
