local TABLE_FLAGS = r.ImGui_TableFlags_Borders()
                 | r.ImGui_TableFlags_RowBg()
                 | r.ImGui_TableFlags_SizingStretchProp()

local COL_HIGHLIGHT_FILL   = 0xFFFF0050  -- yellow, ~31% opacity (RRGGBBAA)
local COL_HIGHLIGHT_BORDER = 0xFFFF00FF  -- yellow, solid

local NOTE_IMG_OFFSET_X  = 12    -- px from image left edge to first note column; tune visually
local NOTE_W_WIDE_FACTOR = 1.83  -- width multiplier for wide note columns; tune visually
local NOTE_W_MED_FACTOR  = 1.40  -- width multiplier for medium note columns; tune visually

-- Stop and free the currently active preview (if any).
-- Tries the combined newer API first, falls back to the two-step older form.
local function StopCurrentPreview()
    if S.preview_src then
        if r.CF_Preview_StopAndDestroyPreview then
            r.CF_Preview_StopAndDestroyPreview(S.preview_src)
        else
            r.CF_Preview_Stop(S.preview_src)
        end
        S.preview_src = nil
    end
    if S.preview_pcm then
        r.PCM_Source_Destroy(S.preview_pcm)
        S.preview_pcm = nil
    end
end

-- Play a single file from the resources/audio/drums/ folder via SWS CF_CreatePreview.
-- Returns false if SWS is unavailable, the file is missing, or creation fails.
local function PlayAudioFile(filename)
    StopCurrentPreview()
    local pcm = r.PCM_Source_CreateFromFile(AUDIO_DRUMS_DIR .. filename)
    if not pcm then return false end
    local preview = r.CF_CreatePreview(pcm)
    if not preview then r.PCM_Source_Destroy(pcm); return false end
    r.CF_Preview_SetValue(preview, 'B_LOOP', 0)
    r.CF_Preview_SetValue(preview, 'D_VOLUME', 1.0)
    r.CF_Preview_Play(preview)
    S.preview_src = preview
    S.preview_pcm = pcm
    return true
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

local function DrawDrumsTab()
    S.hovered_drum_idx = nil

    -- Notation legend
    SectionHeader('Drum Notation Legend')
    r.ImGui_Spacing(ctx)
    if AUDIO_DRUMS_DIR then
        r.ImGui_TextWrapped(ctx, 'Hover a row to highlight it in the image below. Click to play the sample.')
    else
        r.ImGui_TextWrapped(ctx, 'Hover a row to highlight the corresponding note in the reference image below.')
    end
    r.ImGui_Spacing(ctx)

    if r.ImGui_BeginTable(ctx, '##notation', 3, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Drum Voice')
        r.ImGui_TableSetupColumn(ctx, 'Pro Drums Lane')
        r.ImGui_TableSetupColumn(ctx, 'Notes')
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
    if r.ImGui_BeginTable(ctx, '##patterns', 2, TABLE_FLAGS) then
        r.ImGui_TableSetupColumn(ctx, 'Pattern')
        r.ImGui_TableSetupColumn(ctx, 'Description')
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
