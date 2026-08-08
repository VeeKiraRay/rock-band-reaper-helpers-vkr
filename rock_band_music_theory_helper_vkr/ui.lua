local TABLE_FLAGS = r.ImGui_TableFlags_Borders()
                 | r.ImGui_TableFlags_RowBg()
                 | r.ImGui_TableFlags_SizingFixedFit()

local COL_HIGHLIGHT_FILL   = 0xFFFF0050  -- yellow, ~31% opacity (RRGGBBAA)
local COL_HIGHLIGHT_BORDER = 0xFFFF00FF  -- yellow, solid

-- Fixed pixel widths for "prose" table columns (long sentences that would
-- blow out a content-measured width) -- tune visually, same convention as
-- NOTE_IMG_OFFSET_X etc. below. Content-sized columns (short values like
-- names/shapes) are measured from their own data instead -- see ColWidth().
local NOTES_COL_W = 340   -- DRUM_NOTATION 'Notes'
local DESC_COL_W  = 380   -- DRUM_PATTERNS 'Description'

-- Widest CalcTextSize (+ padding) among a column header and all its row
-- values -- reuses LabelColWidth's CalcTextSize+padding idiom
-- (lib/reaper_imgui_helpers.lua) so short-value table columns size to their
-- own content instead of stretching with the window.
local function ColWidth(header, rows, field)
    local labels = { header }
    for _, row in ipairs(rows) do labels[#labels + 1] = row[field] end
    return LabelColWidth(labels)
end

local WIDTH_FIXED = r.ImGui_TableColumnFlags_WidthFixed()

local NOTE_IMG_OFFSET_X  = 12    -- px from image left edge to first note column; tune visually
local NOTE_W_WIDE_FACTOR = 1.83  -- width multiplier for wide note columns; tune visually
local NOTE_W_MED_FACTOR  = 1.40  -- width multiplier for medium note columns; tune visually

-- StopCurrentPreview and PlayPreviewPath live in audio_preview.lua -- the
-- Piano tab (ui_piano.lua) needs them too, so they are globals now.

-- Play a single file from the resources/audio/drums/ folder.
local function PlayAudioFile(filename)
    return PlayPreviewPath(AUDIO_DRUMS_DIR .. filename)
end

-- Play the audio for a DRUM_NOTATION row (passed directly or by 0-based img_idx).
-- audio_file = string → plays immediately.
-- audio_file = table  → plays first sample immediately, queues the rest as a 500ms burst.
-- Returns true if playback started, false if pack unavailable or no file set.
local function PlayDrumWAV(img_idx_or_row)
    if not AUDIO_DRUMS_DIR then return false end
    local row = type(img_idx_or_row) == 'table' and img_idx_or_row
                or DRUM_NOTATION[img_idx_or_row + 1]  -- 0-based img_idx -> 1-based table index
    if not row or not row.audio_file then return false end

    if type(row.audio_file) == 'table' then
        local files = row.audio_file
        if #files == 0 then return false end
        if not PlayAudioFile(files[1]) then return false end
        if #files > 1 then
            S.burst_files  = files
            S.burst_idx    = 2           -- first was already played
            S.burst_next_t = r.time_precise() + 0.5
        end
        return true
    else
        return PlayAudioFile(row.audio_file)
    end
end

-- Guitar chord playback goes through PlaySynthChord (audio_preview.lua) with
-- its default strum stagger. The pitches come straight from
-- lib/reaper_guitar_theory.lua's classifier, so that one code path covers
-- both the static reference table and arbitrary live Shape Search results
-- (any tuning).

local drum_notation_col_w  -- lazily computed once, first DrawDrumsTab() call
local drum_patterns_col_w  -- lazily computed once, first DrawDrumsTab() call

local function DrawDrumsTab()
    S.hovered_drum_idx = nil

    -- Notation legend
    SectionHeader('Drum Notation Legend')
    r.ImGui_Spacing(ctx)
    -- Three cases, not two: AUDIO_DRUMS_DIR is nil both when SWS is missing and
    -- when the sample pack isn't installed (the pack probe in the entry point is
    -- itself gated on AUDIO_CF_AVAILABLE), so collapsing them leaves a user with
    -- a correctly-installed pack no clue why clicking does nothing.
    if AUDIO_DRUMS_DIR then
        r.ImGui_TextWrapped(ctx, 'Hover a row to highlight it in the image below. Click to play the sample.')
    elseif not AUDIO_CF_AVAILABLE then
        r.ImGui_TextWrapped(ctx, 'Hover a row to highlight the corresponding note in the reference image below. ' ..
                                 'Install the SWS extension to hear rows played back (click enabled once installed).')
    else
        r.ImGui_TextWrapped(ctx, 'Hover a row to highlight the corresponding note in the reference image below. ' ..
                                 'Install the drum sample pack into resources/audio/drums/ to hear rows played back ' ..
                                 '(see resources/INSTALLATION_GUIDE.md).')
    end
    r.ImGui_Spacing(ctx)

    drum_notation_col_w = drum_notation_col_w or {
        voice = ColWidth('Drum Voice', DRUM_NOTATION, 'name'),
        lane  = ColWidth('Pro Drums Lane', DRUM_NOTATION, 'rb_pro'),
    }

    if r.ImGui_BeginTable(ctx, '##notation', 3, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Drum Voice', WIDTH_FIXED, drum_notation_col_w.voice)
        r.ImGui_TableSetupColumn(ctx, 'Pro Drums Lane', WIDTH_FIXED, drum_notation_col_w.lane)
        r.ImGui_TableSetupColumn(ctx, 'Notes', WIDTH_FIXED, NOTES_COL_W)
        r.ImGui_TableHeadersRow(ctx)

        for _, row in ipairs(DRUM_NOTATION) do
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            -- Use row.name as the Selectable label - all names are unique, which prevents
            -- ImGui from merging rows that share the same symbol text into one widget ID.
            r.ImGui_Selectable(ctx, row.name, false, r.ImGui_SelectableFlags_SpanAllColumns())
            if r.ImGui_IsItemHovered(ctx) and row.img_idx then
                S.hovered_drum_idx = row.img_idx
                if r.ImGui_IsItemClicked(ctx) then
                    PlayDrumWAV(row)
                end
            end
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_Text(ctx, row.rb_pro)
            r.ImGui_TableSetColumnIndex(ctx, 2)
            r.ImGui_TextWrapped(ctx, row.notes or '')
        end
        r.ImGui_EndTable(ctx)
    end

    -- Reference image + hover/playback highlight overlay
    r.ImGui_Spacing(ctx)
    if IMG_DRUM_NOTATION then
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        -- Scale down to fit content width; never scale up beyond native size
        local display_w = math.min(avail_w, IMG_DRUM_W)
        local display_h = IMG_DRUM_H * (display_w / IMG_DRUM_W)
        r.ImGui_Image(ctx, IMG_DRUM_NOTATION, display_w, display_h)

        if S.hovered_drum_idx then
            local ix, iy = r.ImGui_GetItemRectMin(ctx)
            local iw, ih = r.ImGui_GetItemRectSize(ctx)
            local scale   = iw / IMG_DRUM_W
            local note_w  = 35.5 * scale
            local note_x  = ix + NOTE_IMG_OFFSET_X * scale
            for i = 0, S.hovered_drum_idx - 1 do
                local dn = DRUM_NOTATION[i + 1]
                if dn and dn.col_w == 'wide' then
                    note_x = note_x + note_w * NOTE_W_WIDE_FACTOR
                elseif dn and dn.col_w == 'med' then
                    note_x = note_x + note_w * NOTE_W_MED_FACTOR
                else
                    note_x = note_x + note_w
                end
                if dn and dn.gap_after then note_x = note_x + dn.gap_after * scale end
            end
            local curr_dn = DRUM_NOTATION[S.hovered_drum_idx + 1]
            local curr_nw
            if curr_dn and curr_dn.col_w == 'wide' then
                curr_nw = note_w * NOTE_W_WIDE_FACTOR
            elseif curr_dn and curr_dn.col_w == 'med' then
                curr_nw = note_w * NOTE_W_MED_FACTOR
            else
                curr_nw = note_w
            end
            local dl = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, note_x, iy, note_x + curr_nw, iy + ih, COL_HIGHLIGHT_FILL)
            r.ImGui_DrawList_AddRect(dl, note_x, iy, note_x + curr_nw, iy + ih, COL_HIGHLIGHT_BORDER, 0, 0, 2.0)
        end
    else
        r.ImGui_TextDisabled(ctx, '(notation image not found - place drum.png in the resources/img/ folder next to the script)')
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)

    -- Common patterns
    SectionHeader('Common Drum Patterns')
    r.ImGui_Spacing(ctx)
    drum_patterns_col_w = drum_patterns_col_w or ColWidth('Pattern', DRUM_PATTERNS, 'name')
    if r.ImGui_BeginTable(ctx, '##patterns', 2, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Pattern', WIDTH_FIXED, drum_patterns_col_w)
        r.ImGui_TableSetupColumn(ctx, 'Description', WIDTH_FIXED, DESC_COL_W)
        r.ImGui_TableHeadersRow(ctx)
        for _, row in ipairs(DRUM_PATTERNS) do
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_Text(ctx, row.name)
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_TextWrapped(ctx, row.desc)
        end
        r.ImGui_EndTable(ctx)
    end
end

local GUITAR_SEARCH_INPUT_W = 320  -- wider than WIDTH_STD (200): fret lines like
                                    -- "x 10 12 12 10 x" run long; one-off, context-specific.

-- Widths are measured against the FULL GUITAR_CHORDS table, not the subset
-- filtered by the currently-selected Chord Type Explorer type, so columns
-- don't jump width when the selection changes.
local guitar_chords_col_w  -- lazily computed once, first DrawGuitarTab() call
local guitar_terms_col_w   -- lazily computed once, first DrawGuitarTab() call

local function DrawGuitarTab()
    SectionHeader('Shape Search')
    r.ImGui_Spacing(ctx)
    r.ImGui_TextWrapped(ctx, 'Paste a fret shape (space-separated) to classify it and see its suggested RB mapping.')
    r.ImGui_SetNextItemWidth(ctx, GUITAR_SEARCH_INPUT_W)
    local changed, val = r.ImGui_InputText(ctx, '##guitar_search', S.guitar_search_input)
    if changed then S.guitar_search_input = val end
    Tooltip(TIPS.guitar_search)

    r.ImGui_Spacing(ctx)
    if S.guitar_search_input and S.guitar_search_input:match('%S') then
        local results, err = GuitarAnalyzeShapeAllTunings(S.guitar_search_input)
        if not results then
            r.ImGui_TextWrapped(ctx, 'No notes recognized (' .. err .. ').')
        else
            local show_tuning_labels = #results > 1
            for _, entry in ipairs(results) do
                local result = entry.analysis
                local combo_text
                if result.combo then
                    combo_text = result.combo
                elseif result.ambiguous_options then
                    combo_text = 'any of ' .. table.concat(result.ambiguous_options, '/')
                else
                    combo_text = '?'
                end
                local line = result.type_name
                if result.detail then line = line .. '  (' .. result.detail .. ')' end
                line = line .. '  ->  ' .. (result.width or 'no RB mapping suggestion') .. '  (' .. combo_text .. ')'
                if show_tuning_labels then line = entry.tuning_name .. ': ' .. line end
                if r.ImGui_SmallButton(ctx, 'Play##guitar_search_play_' .. entry.tuning_name) then
                    PlaySynthChord(result.pitches)
                end
                Tooltip(TIPS.guitar_play)
                r.ImGui_SameLine(ctx)
                r.ImGui_TextWrapped(ctx, line)
            end
        end
    else
        r.ImGui_TextDisabled(ctx, '(no input)')
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)

    SectionHeader('Chord Type Explorer')
    r.ImGui_Spacing(ctx)
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    local selected_type = GUITAR_CHORD_TYPES[S.guitar_chord_type_idx]
    if r.ImGui_BeginCombo(ctx, '##guitar_chord_type', selected_type.name) then
        for i, t in ipairs(GUITAR_CHORD_TYPES) do
            local is_sel = (i == S.guitar_chord_type_idx)
            if r.ImGui_Selectable(ctx, t.name, is_sel) then
                S.guitar_chord_type_idx = i
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    selected_type = GUITAR_CHORD_TYPES[S.guitar_chord_type_idx]

    r.ImGui_Spacing(ctx)
    r.ImGui_TextWrapped(ctx, selected_type.description)
    r.ImGui_Spacing(ctx)
    if AUDIO_CF_AVAILABLE then
        r.ImGui_TextWrapped(ctx, 'Click a row to hear it.')
    else
        r.ImGui_TextWrapped(ctx, 'Install the SWS extension to hear rows played back (click enabled once installed).')
    end
    r.ImGui_Spacing(ctx)

    guitar_chords_col_w = guitar_chords_col_w or {
        shape      = ColWidth('Shape', GUITAR_CHORDS, 'shape'),
        name       = ColWidth('Name', GUITAR_CHORDS, 'name'),
        sound      = ColWidth('Sound', GUITAR_CHORDS, 'sound'),
        rb_mapping = ColWidth('RB Mapping', GUITAR_CHORDS, 'rb_mapping'),
    }

    if r.ImGui_BeginTable(ctx, '##guitar_chords', 4, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Shape', WIDTH_FIXED, guitar_chords_col_w.shape)
        r.ImGui_TableSetupColumn(ctx, 'Name', WIDTH_FIXED, guitar_chords_col_w.name)
        r.ImGui_TableSetupColumn(ctx, 'Sound', WIDTH_FIXED, guitar_chords_col_w.sound)
        r.ImGui_TableSetupColumn(ctx, 'RB Mapping', WIDTH_FIXED, guitar_chords_col_w.rb_mapping)
        r.ImGui_TableHeadersRow(ctx)
        for _, row in ipairs(GUITAR_CHORDS) do
            if row.type == selected_type.name then
                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                -- row.name is not unique across rows (a few shapes share a Name,
                -- e.g. two "Power chord" rows both named G5), so the Selectable
                -- label uses shape+name together to keep widget IDs distinct.
                r.ImGui_Selectable(ctx, row.shape .. '##' .. row.name, false, r.ImGui_SelectableFlags_SpanAllColumns())
                if r.ImGui_IsItemClicked(ctx) then
                    PlaySynthChord(GuitarParseFretInput(row.shape))
                end
                Tooltip(TIPS.guitar_play)
                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_Text(ctx, row.name)
                r.ImGui_TableSetColumnIndex(ctx, 2)
                r.ImGui_Text(ctx, row.sound)
                r.ImGui_TableSetColumnIndex(ctx, 3)
                r.ImGui_Text(ctx, row.rb_mapping)
            end
        end
        r.ImGui_EndTable(ctx)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)

    SectionHeader('RB Lane-Combo Terminology')
    r.ImGui_Spacing(ctx)
    r.ImGui_TextWrapped(ctx,
        'G=Green R=Red Y=Yellow B=Blue O=Orange. A combo name lists the lanes used, low to high.')
    r.ImGui_Spacing(ctx)
    guitar_terms_col_w = guitar_terms_col_w or {
        width  = ColWidth('Width', GUITAR_LANE_TERMS, 'width'),
        combos = ColWidth('Lane combos', GUITAR_LANE_TERMS, 'combos'),
    }

    if r.ImGui_BeginTable(ctx, '##guitar_terms', 2, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Width', WIDTH_FIXED, guitar_terms_col_w.width)
        r.ImGui_TableSetupColumn(ctx, 'Lane combos', WIDTH_FIXED, guitar_terms_col_w.combos)
        r.ImGui_TableHeadersRow(ctx)
        for _, row in ipairs(GUITAR_LANE_TERMS) do
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_Text(ctx, row.width)
            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_TextWrapped(ctx, row.combos)
        end
        r.ImGui_EndTable(ctx)
    end
end

local function Loop()
    -- Burst timer: fires remaining samples from a multi-sample row click.
    if S.burst_files then
        local now = r.time_precise()
        if now >= S.burst_next_t then
            local fname = S.burst_files[S.burst_idx]
            if fname then
                PlayAudioFile(fname)
                S.burst_idx    = S.burst_idx + 1
                S.burst_next_t = now + 0.5
            else
                S.burst_files = nil
            end
        end
    end

    r.ImGui_SetNextWindowSize(ctx, 700, 660, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'RB Music Theory Helper', true)

    if visible then
        if r.ImGui_BeginTabBar(ctx, '##tabs') then
            if r.ImGui_BeginTabItem(ctx, 'Drums') then
                r.ImGui_Spacing(ctx)
                r.ImGui_BeginChild(ctx, '##drums_scroll', 0, 0, r.ImGui_ChildFlags_None(), r.ImGui_WindowFlags_None())
                DrawDrumsTab()
                r.ImGui_EndChild(ctx)
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, 'Guitar') then
                r.ImGui_Spacing(ctx)
                r.ImGui_BeginChild(ctx, '##guitar_scroll', 0, 0, r.ImGui_ChildFlags_None(), r.ImGui_WindowFlags_None())
                DrawGuitarTab()
                r.ImGui_EndChild(ctx)
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, 'Piano') then
                r.ImGui_Spacing(ctx)
                r.ImGui_BeginChild(ctx, '##piano_scroll', 0, 0, r.ImGui_ChildFlags_None(), r.ImGui_WindowFlags_None())
                DrawPianoTab()
                r.ImGui_EndChild(ctx)
                r.ImGui_EndTabItem(ctx)
            end
            r.ImGui_EndTabBar(ctx)
        end
        r.ImGui_End(ctx)
    end

    if open then
        r.defer(Loop)
    else
        StopCurrentPreview()
    end
end

r.defer(Loop)
