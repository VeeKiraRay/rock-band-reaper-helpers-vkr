-- Piano tab: translate staff notation into keys to press.
--
-- Set the context (a clef per staff, a key signature), click the staff where
-- the note heads are printed, and read back the pitches -- spelled names,
-- MIDI numbers, a highlighted keyboard, and audible playback.
--
-- All the music theory lives in lib/reaper_music_notation.lua (pure, tested
-- by dev/tests/music_notation.lua); this file is geometry and drawing only.
-- Playback goes through PlaySynthChord (audio_preview.lua).

----------------------------------------------------------------------
-- Canvas geometry. Pixel values, tuned visually -- same convention as the
-- Drums tab's NOTE_IMG_OFFSET_X etc. in ui.lua.
----------------------------------------------------------------------

local SPACE_PX   = 12                -- distance between adjacent staff lines
local HALF_PX    = SPACE_PX / 2      -- one slot: line -> adjacent space
local HEAD_R     = SPACE_PX * 0.46   -- note head radius
local LEDGER_HALF = HEAD_R * 1.9     -- half-width of a ledger line
local SIG_GLYPH_W = 9                -- horizontal pitch of key-signature accidentals
local HEAD_GAP    = 22               -- gap from the key signature to the note stack
local STAFF_PAD_X = 4                -- inset of the staff lines from the canvas edges

-- How far above and below each staff a note head may be placed: three ledger
-- positions each way. Slot 0 is the bottom line and slot 8 the top, so the
-- band is 20 half-spaces tall.
local SLOT_MIN = -6
local SLOT_MAX = 14
local BAND_H   = (SLOT_MAX - SLOT_MIN) * HALF_PX
local BAND_GAP = 16                  -- vertical gap between the two staff bands
local CANVAS_PAD_Y = 8
local CANVAS_MIN_W = 360

-- Keyboard diagram
local KB_MAX_WHITE_W = 18
local KB_MIN_WHITE_W = 7
local KB_H           = 64
local KB_BLACK_H_F   = 0.62          -- black key height as a fraction of KB_H
local KB_PAD_Y       = 6

-- Default keyboard span, four octaves -- wide enough for both hands of a
-- grand staff without ledger lines. Widened at draw time if a note falls
-- outside. (Written as MIDI numbers because the octave those read as depends
-- on the naming toggle: 36 is C2 in sheet-music numbering, C1 in RB's.)
local KB_DEFAULT_LO = 36
local KB_DEFAULT_HI = 84

-- Colours are RRGGBBAA, matching COL_HIGHLIGHT_FILL etc. in ui.lua.
local COL_STAFF      = 0x909090FF
local COL_LABEL      = 0xD0D0D0FF
local COL_HEAD       = 0xE8E8E8FF
local COL_HEAD_GHOST = 0x66CCFF88    -- hover preview: tinted so it reads as "not placed yet"
local COL_KEY_WHITE  = 0xE8E8E8FF
local COL_KEY_BLACK  = 0x1A1A1AFF
local COL_KEY_EDGE   = 0x404040FF
local COL_KEY_ON_W   = 0x66CCFFFF
local COL_KEY_ON_B   = 0x2E86B0FF

local clef_col_w  -- lazily computed once; widest clef label, measured not assumed

----------------------------------------------------------------------
-- Staff model
----------------------------------------------------------------------

-- The staves currently shown, top to bottom. Rebuilt each frame -- the clef
-- combos can change under it. Indices are clamped rather than trusted so a
-- stale value can never index nil out of NOTATION_CLEFS.
local function StaffList()
    local list = {
        {
            notes = S.piano_notes_upper,
            clef  = NOTATION_CLEFS[S.piano_clef_upper_idx]
                    or NOTATION_CLEFS[NOTATION_CLEF_IDX.treble],
        },
    }
    if S.piano_show_lower then
        list[2] = {
            notes = S.piano_notes_lower,
            clef  = NOTATION_CLEFS[S.piano_clef_lower_idx]
                    or NOTATION_CLEFS[NOTATION_CLEF_IDX.bass],
        }
    end
    return list
end

local function CurrentKeyN()
    local row = KEY_SIGNATURES[S.piano_key_sig_idx] or KEY_SIGNATURES[KEY_SIG_NATURAL_IDX]
    return row.n
end

-- Every note head currently placed, across both staves, as
-- { midi, name } sorted low to high. A pitch reachable from both staves
-- appears twice, deliberately -- that is two hands playing the same key,
-- which is what the page says.
local function CollectNotes()
    local key_n = CurrentKeyN()
    local out   = {}
    for _, staff in ipairs(StaffList()) do
        for step in pairs(staff.notes) do
            local alt   = NotationKeySigAlteration(key_n, step % 7)
            local sound = NotationSoundingStep(step, staff.clef.octave_shift)
            out[#out + 1] = {
                midi = NotationStepToNatural(sound) + alt,
                name = NotationNoteName(sound, alt),
            }
        end
    end
    table.sort(out, function(a, b) return a.midi < b.midi end)
    return out
end

-- Placed slots for one staff, ascending, each with a horizontal offset.
-- A note a single step above its neighbour is pushed to the right of the
-- stack so the two heads don't overlap -- the standard engraving of a
-- second, and without it a close voicing draws as one blob.
local function LayOutHeads(staff)
    local slots = {}
    for step in pairs(staff.notes) do
        slots[#slots + 1] = step - staff.clef.bottom_step
    end
    table.sort(slots)

    local heads, prev_slot, prev_off = {}, nil, 0
    for _, slot in ipairs(slots) do
        local off = 0
        if prev_slot and slot - prev_slot == 1 and prev_off == 0 then off = 1 end
        heads[#heads + 1] = { slot = slot, off = off }
        prev_slot, prev_off = slot, off
    end
    return heads
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

-- Ledger lines from the staff edge out to `slot`, at even slots only (odd
-- slots are spaces, which sit between ledger lines and need none of their own).
local function DrawLedgers(dl, hx, bottom_y, slot)
    local function line(s)
        local ly = bottom_y - s * HALF_PX
        r.ImGui_DrawList_AddLine(dl, hx - LEDGER_HALF, ly, hx + LEDGER_HALF, ly, COL_STAFF, 1.0)
    end
    if slot > 8 then
        for s = 10, slot, 2 do line(s) end
    elseif slot < 0 then
        for s = -2, slot, -2 do line(s) end
    end
end

-- Draw one five-line staff with its clef, key signature and note heads.
-- bottom_y is the y of slot 0 (the bottom line). hover_slot is the slot the
-- mouse is over on THIS staff, or nil.
local function DrawStaff(dl, ox, canvas_w, bottom_y, staff, key_n, hover_slot, text_h)
    local x0 = ox + STAFF_PAD_X
    local x1 = ox + canvas_w - STAFF_PAD_X

    for i = 0, 4 do
        local y = bottom_y - i * SPACE_PX
        r.ImGui_DrawList_AddLine(dl, x0, y, x1, y, COL_STAFF, 1.0)
    end

    -- Clef as a text label: the default ImGui font has no music glyphs (the
    -- same reason ui_venue_players.lua draws its dot with AddCircleFilled
    -- rather than a character).
    local mid_y = bottom_y - 2 * SPACE_PX
    r.ImGui_DrawList_AddText(dl, x0 + 4, mid_y - text_h / 2, COL_LABEL, staff.clef.label)

    local sx = x0 + 4 + clef_col_w
    for _, glyph in ipairs(NotationKeySigSlots(key_n, staff.clef)) do
        local gy = bottom_y - glyph.slot * HALF_PX - text_h / 2
        r.ImGui_DrawList_AddText(dl, sx, gy, COL_LABEL, glyph.sign)
        sx = sx + SIG_GLYPH_W
    end

    local head_x = sx + HEAD_GAP

    if hover_slot and not staff.notes[staff.clef.bottom_step + hover_slot] then
        local hy = bottom_y - hover_slot * HALF_PX
        DrawLedgers(dl, head_x, bottom_y, hover_slot)
        r.ImGui_DrawList_AddCircleFilled(dl, head_x, hy, HEAD_R, COL_HEAD_GHOST)
    end

    for _, head in ipairs(LayOutHeads(staff)) do
        local hx = head_x + head.off * HEAD_R * 2
        local hy = bottom_y - head.slot * HALF_PX
        DrawLedgers(dl, hx, bottom_y, head.slot)
        r.ImGui_DrawList_AddCircleFilled(dl, hx, hy, HEAD_R, COL_HEAD)
    end
end

-- The clickable grand staff. Returns nothing; toggles S.piano_notes_* on click.
local function DrawStaffCanvas()
    local staves   = StaffList()
    local key_n    = CurrentKeyN()
    local text_h   = r.ImGui_GetTextLineHeight(ctx)
    local avail_w  = r.ImGui_GetContentRegionAvail(ctx)
    local canvas_w = math.max(avail_w, CANVAS_MIN_W)
    local canvas_h = CANVAS_PAD_Y * 2 + BAND_H * #staves + BAND_GAP * (#staves - 1)

    local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
    -- InvisibleButton rather than Dummy: this region reserves layout space
    -- AND hit-tests, which is what makes the staff clickable. Same
    -- GetCursorScreenPos -> GetWindowDrawList -> DrawList_Add* idiom the
    -- rest of the codebase uses for custom drawing.
    r.ImGui_InvisibleButton(ctx, '##piano_staff', canvas_w, canvas_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx)

    -- Slot 0 (bottom line) of each staff. SLOT_MAX half-spaces down from the
    -- top of that staff's band.
    local bottoms = {}
    for i = 1, #staves do
        bottoms[i] = oy + CANVAS_PAD_Y + (i - 1) * (BAND_H + BAND_GAP) + SLOT_MAX * HALF_PX
    end

    -- Which staff the mouse is over, and where. The two bands are split down
    -- the middle of the gap BETWEEN them, not between their bottom lines --
    -- splitting between the bottom lines would put the lower staff's topmost
    -- ledger positions on the upper staff's side of the line, where they
    -- resolve to no slot at all and become unclickable. A slot outside
    -- [SLOT_MIN, SLOT_MAX] is simply not a note position.
    local hover_i, hover_slot
    if hovered then
        local _, my = r.ImGui_GetMousePos(ctx)
        local split = oy + CANVAS_PAD_Y + BAND_H + BAND_GAP / 2
        local i = (#staves > 1 and my >= split) and 2 or 1
        local slot = math.floor((bottoms[i] - my) / HALF_PX + 0.5)
        if slot >= SLOT_MIN and slot <= SLOT_MAX then
            hover_i, hover_slot = i, slot
        end
    end

    local dl = r.ImGui_GetWindowDrawList(ctx)
    for i, staff in ipairs(staves) do
        DrawStaff(dl, ox, canvas_w, bottoms[i], staff, key_n,
                  (i == hover_i) and hover_slot or nil, text_h)
    end

    if clicked and hover_i then
        local staff = staves[hover_i]
        local step  = staff.clef.bottom_step + hover_slot
        staff.notes[step] = (not staff.notes[step]) or nil
    end
end

-- Piano keyboard with the resulting pitches highlighted. Read-only.
local function DrawKeyboard(notes)
    local lo, hi = KB_DEFAULT_LO, KB_DEFAULT_HI
    for _, note in ipairs(notes) do
        if note.midi < lo then lo = math.max(0,   math.floor(note.midi / 12) * 12) end
        if note.midi > hi then hi = math.min(127, math.floor(note.midi / 12) * 12 + 12) end
    end

    local on = {}
    for _, note in ipairs(notes) do on[note.midi] = true end

    local keys, white_count = PianoKeyLayout(lo, hi)
    if white_count == 0 then return end

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local white_w = math.max(KB_MIN_WHITE_W, math.min(KB_MAX_WHITE_W, avail_w / white_count))
    local text_h  = r.ImGui_GetTextLineHeight(ctx)
    local total_h = KB_PAD_Y + KB_H + 2 + text_h

    local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_Dummy(ctx, white_count * white_w, total_h)

    local dl   = r.ImGui_GetWindowDrawList(ctx)
    local top  = oy + KB_PAD_Y
    local bot  = top + KB_H
    local bbot = top + KB_H * KB_BLACK_H_F

    -- Two passes: every white key first, then the black keys on top of them.
    for _, key in ipairs(keys) do
        if not key.is_black then
            local x = ox + key.x * white_w
            r.ImGui_DrawList_AddRectFilled(dl, x, top, x + white_w, bot,
                                           on[key.midi] and COL_KEY_ON_W or COL_KEY_WHITE)
            r.ImGui_DrawList_AddRect(dl, x, top, x + white_w, bot, COL_KEY_EDGE)
            -- Octave label under each C. Follows the same naming toggle as the
            -- readout -- a keyboard saying C2 under a note the list calls C1
            -- would be worse than no label at all.
            if key.midi % 12 == 0 then
                local label = S.piano_rb_names and RBPitchName(key.midi)
                              or ('C' .. (math.floor(key.midi / 12) - 1))
                r.ImGui_DrawList_AddText(dl, x + 1, bot + 2, COL_LABEL, label)
            end
        end
    end
    for _, key in ipairs(keys) do
        if key.is_black then
            local x = ox + key.x * white_w
            local w = key.w * white_w
            r.ImGui_DrawList_AddRectFilled(dl, x, top, x + w, bbot,
                                           on[key.midi] and COL_KEY_ON_B or COL_KEY_BLACK)
            r.ImGui_DrawList_AddRect(dl, x, top, x + w, bbot, COL_KEY_EDGE)
        end
    end
end

----------------------------------------------------------------------
-- Tab
----------------------------------------------------------------------

-- id_suffix distinguishes the two clef combos' widget IDs; it must not
-- already contain '##' (ImGui splits a label at the first one).
local function ClefCombo(id_suffix, state_field)
    local sel = NOTATION_CLEFS[S[state_field]] or NOTATION_CLEFS[NOTATION_CLEF_IDX.treble]
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##' .. id_suffix, sel.label) then
        for i, clef in ipairs(NOTATION_CLEFS) do
            local is_sel = (i == S[state_field])
            if r.ImGui_Selectable(ctx, clef.label .. '##' .. id_suffix, is_sel) then
                S[state_field] = i
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.piano_clef)
end

function DrawPianoTab()
    if not clef_col_w then
        local labels = {}
        for _, clef in ipairs(NOTATION_CLEFS) do labels[#labels + 1] = clef.label end
        clef_col_w = LabelColWidth(labels)
    end

    SectionHeader('Staff Reader')
    r.ImGui_Spacing(ctx)
    r.ImGui_TextWrapped(ctx,
        'Set the clef and key signature the music is written in, then click the staff ' ..
        'wherever you see a note head -- click it again to remove it. Positions above ' ..
        'and below the staff get ledger lines, the same as on paper. Everything placed ' ..
        'sounds together as one chord: this reads a single stack of note heads, not a ' ..
        'bar of music.')
    r.ImGui_Spacing(ctx)

    local lbl_col = LabelColWidth({ 'Upper staff', 'Lower staff', 'Key signature', 'Note names', 'Tone' })

    r.ImGui_Text(ctx, 'Upper staff')
    r.ImGui_SameLine(ctx, lbl_col)
    ClefCombo('piano_clef_upper', 'piano_clef_upper_idx')

    r.ImGui_Text(ctx, 'Lower staff')
    r.ImGui_SameLine(ctx, lbl_col)
    local show_lower = S.piano_show_lower   -- snapshot: the checkbox below can flip it mid-frame
    if not show_lower then r.ImGui_BeginDisabled(ctx) end
    ClefCombo('piano_clef_lower', 'piano_clef_lower_idx')
    if not show_lower then r.ImGui_EndDisabled(ctx) end
    r.ImGui_SameLine(ctx)
    _, S.piano_show_lower = r.ImGui_Checkbox(ctx, 'Show##piano_show_lower', S.piano_show_lower)
    Tooltip(TIPS.piano_show_lower)

    r.ImGui_Text(ctx, 'Key signature')
    r.ImGui_SameLine(ctx, lbl_col)
    local key_row = KEY_SIGNATURES[S.piano_key_sig_idx] or KEY_SIGNATURES[KEY_SIG_NATURAL_IDX]
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##piano_key_sig', key_row.label) then
        for i, row in ipairs(KEY_SIGNATURES) do
            local is_sel = (i == S.piano_key_sig_idx)
            if r.ImGui_Selectable(ctx, row.label, is_sel) then S.piano_key_sig_idx = i end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.piano_key_sig)

    r.ImGui_Text(ctx, 'Note names')
    r.ImGui_SameLine(ctx, lbl_col)
    _, S.piano_rb_names = r.ImGui_Checkbox(ctx, 'REAPER piano roll##piano_rb_names', S.piano_rb_names)
    Tooltip(TIPS.piano_rb_names)

    r.ImGui_Text(ctx, 'Tone')
    r.ImGui_SameLine(ctx, lbl_col)
    local piano_tones = SynthTonesInFamily('piano')
    local tone_label  = (SYNTH_TONES[S.piano_tone] or {}).label or '?'
    r.ImGui_SetNextItemWidth(ctx, WIDTH_STD)
    if r.ImGui_BeginCombo(ctx, '##piano_tone', tone_label) then
        for _, entry in ipairs(piano_tones) do
            local is_sel = (entry.name == S.piano_tone)
            if r.ImGui_Selectable(ctx, entry.preset.label .. '##piano_tone', is_sel) then
                S.piano_tone = entry.name
            end
            if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    Tooltip(TIPS.piano_tone)

    r.ImGui_Spacing(ctx)
    DrawStaffCanvas()
    r.ImGui_Spacing(ctx)

    -- Read back after the canvas, so a click this frame is already reflected.
    local notes = CollectNotes()

    local bw = BtnGroupWidth({ 'Play', 'Clear' })
    local can_play = AUDIO_CF_AVAILABLE and #notes > 0
    if not can_play then r.ImGui_BeginDisabled(ctx) end
    if Btn('Play', BTN_H, bw) then
        local pitches = {}
        for _, note in ipairs(notes) do pitches[#pitches + 1] = note.midi end
        -- The piano presets carry stagger_s = 0 (a block chord -- a keyboard is
        -- struck, not strummed) along with their hammer, sustain and duration.
        PlaySynthChord(pitches, { tone = S.piano_tone })
    end
    if not can_play then r.ImGui_EndDisabled(ctx) end
    Tooltip(TIPS.piano_play)

    r.ImGui_SameLine(ctx)
    if Btn('Clear', BTN_H, bw) then
        S.piano_notes_upper = {}
        S.piano_notes_lower = {}
        notes = {}
    end
    Tooltip(TIPS.piano_clear)

    if not AUDIO_CF_AVAILABLE then
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, '(install the SWS extension to hear playback)')
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Spacing(ctx)

    SectionHeader('Keys to Press')
    r.ImGui_Spacing(ctx)
    if #notes == 0 then
        r.ImGui_TextDisabled(ctx, '(no note heads placed)')
    else
        local parts = {}
        for _, note in ipairs(notes) do
            parts[#parts + 1] = string.format('%s (%d)',
                S.piano_rb_names and RBPitchName(note.midi) or note.name, note.midi)
        end
        r.ImGui_TextWrapped(ctx, table.concat(parts, '   '))
    end
    r.ImGui_Spacing(ctx)
    if S.piano_rb_names then
        r.ImGui_TextWrapped(ctx,
            'REAPER piano-roll names: one fixed set of 12, so a Db on the page reads as ' ..
            'C#. Rock Band octaves, where C1 = 36 and middle C is C3.')
    else
        r.ImGui_TextWrapped(ctx,
            'Sheet-music spelling: names follow the key signature, as printed on the ' ..
            'page. Octaves are scientific pitch, where middle C is C4.')
    end

    r.ImGui_Spacing(ctx)
    DrawKeyboard(notes)
end
