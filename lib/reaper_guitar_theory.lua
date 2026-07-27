-- Pure guitar-shape music theory helpers: fret shape -> pitches -> interval
-- pattern -> chord Type -> suggested RB gem-lane mapping.
-- No dependency on r/ctx/S -- pure global functions/tables only, safe to
-- dofile from a Lua-only context (see dev/tests/run_guitar_theory.lua).
--
-- TODO(guitar-integration): rock_band_general_helper_vkr's AssignGems
-- (actions_guitar.lua) and AssignGemsForGuide (actions_guitar_guide.lua)
-- currently pick gems purely by pitch rank / pool-cycling, with no
-- awareness of chord quality. A future task should have them consult
-- GuitarClassifyChordType/GuitarSuggestRBMapping instead. Not done here --
-- rock_band_general_helper_vkr/ is intentionally untouched by this change.
-- Currently only rock_band_music_theory_helper_vkr consumes this file.

-- Standard tuning, HIGH string to LOW string: e B G D A E.
-- Matches the pre-existing convention in
-- rock_band_general_helper_vkr/actions_guitar_guide.lua's local TAB_OPEN --
-- duplicated here deliberately rather than shared, since it's a fixed
-- physical constant (near-zero drift risk) and sharing it would require
-- touching rock_band_general_helper_vkr/, out of scope per the TODO above.
GUITAR_TAB_OPEN = { 64, 59, 55, 50, 45, 40 }

-- Drop D: identical to standard except the low E string is tuned down a
-- whole step to D. Only string 6 differs.
GUITAR_TAB_OPEN_DROP_D = { 64, 59, 55, 50, 45, 38 }

-- Tunings the live shape search checks a pasted shape against (see
-- GuitarAnalyzeShapeAllTunings). Small and deliberately extensible -- add
-- another altered tuning later by appending an entry -- but only these two
-- ship today; drop D is the one common enough to be worth the complexity.
GUITAR_TUNINGS = {
    { name = 'Standard', tab_open = GUITAR_TAB_OPEN },
    { name = 'Drop D',   tab_open = GUITAR_TAB_OPEN_DROP_D },
}

-- Raw semitone interval (NOT mod-12 -- an octave must stay distinct from a
-- unison) -> name + suggested RB width + specific lane-combo options.
-- width/options use the same letter names as GEM_LETTERS in
-- rock_band_general_helper_vkr/actions_guitar.lua (G/R/Y/B/O) and line up
-- with ChordTypeName's spread groups there: spread 1={GR,RY,YB,BO},
-- spread 2={GY,RB,YO}, spread 3={GB,RO}, spread 4={GO}.
GUITAR_DYAD_INTERVALS = {
    [3]  = { name = 'Minor third',                width = '1-2',        options = { 'GR', 'RY', 'YB', 'BO' } },
    [4]  = { name = 'Major third',                width = '1-2',        options = { 'GR', 'RY', 'YB', 'BO' } },
    [5]  = { name = 'Perfect fourth',              width = '1-2 or 1-3', options = nil }, -- genuinely ambiguous width, don't force one answer
    [7]  = { name = 'Perfect fifth (power chord)', width = '1-3',        options = { 'GY', 'RB', 'YO' } },
    [9]  = { name = 'Sixth dyad',                  width = '1-3',        options = { 'GY', 'RB', 'YO' } },
    [12] = { name = 'Octave',                      width = '1-4',        options = { 'GB', 'RO' } },
}

-- Root-relative pitch-class-set templates for 3+ distinct-pitch shapes.
-- Extends the interval-template idea sketched (unimplemented) in
-- _future_ideas/CHORD_PLAN.md for piano chord detection, with the extra
-- 2-note-adjacent qualities that plan doesn't need but guitar dyads do
-- (those live in GUITAR_DYAD_INTERVALS above, not here).
local function _mk_template(name, pcs)
    local sorted = {}
    for _, pc in ipairs(pcs) do sorted[#sorted + 1] = pc end
    table.sort(sorted)
    return { name = name, key = table.concat(sorted, ',') }
end

GUITAR_CHORD_TEMPLATES = {
    _mk_template('Power chord',      { 0, 7 }),
    _mk_template('Major triad',      { 0, 4, 7 }),
    _mk_template('Minor triad',      { 0, 3, 7 }),
    _mk_template('Sus2',             { 0, 2, 7 }),
    _mk_template('Sus4',             { 0, 5, 7 }),
    _mk_template('Dominant 7',       { 0, 4, 7, 10 }),
    _mk_template('Minor 7',          { 0, 3, 7, 10 }),
    _mk_template('Major 7',          { 0, 4, 7, 11 }),
    _mk_template('Diminished',       { 0, 3, 6 }),
    _mk_template('Augmented',        { 0, 4, 8 }),
    _mk_template('Half-diminished',  { 0, 3, 6, 10 }),
    _mk_template('Add9',             { 0, 2, 4, 7 }),
    _mk_template('Add11',            { 0, 4, 5, 7 }),
}

-- The 7 three-note lane combos (matches POOLS[3] in actions_guitar.lua).
-- No principled per-chord-quality mapping exists today (AssignGems doesn't
-- have one either) -- always offered as the full set of options.
GUITAR_3NOTE_COMBOS = { 'GRY', 'GRB', 'GYB', 'RYB', 'RYO', 'RBO', 'YBO' }

----------------------------------------------------------------------
-- shape = { {str=1..6, fret=int}, ... }  (str indexes tab_open)
-- tab_open defaults to GUITAR_TAB_OPEN (standard tuning); pass
-- GUITAR_TAB_OPEN_DROP_D (or any other 6-entry tuning table) to voice the
-- same shape under a different tuning.
-- Returns pitches[] (one per shape entry, unsorted).
----------------------------------------------------------------------
function GuitarShapeToPitches(shape, tab_open)
    tab_open = tab_open or GUITAR_TAB_OPEN
    local pitches = {}
    for _, note in ipairs(shape) do
        pitches[#pitches + 1] = tab_open[note.str] + note.fret
    end
    return pitches
end

----------------------------------------------------------------------
-- pitches[] (any order/register) -> normalized form:
--   sorted     -- distinct pitches, ascending
--   intervals  -- sorted[i] - sorted[1], ascending (may exceed 12)
--   pcs        -- deduped sorted set of intervals[i] % 12
----------------------------------------------------------------------
function GuitarNormalizeIntervals(pitches)
    local seen, distinct = {}, {}
    for _, p in ipairs(pitches) do
        if not seen[p] then seen[p] = true; distinct[#distinct + 1] = p end
    end
    table.sort(distinct)

    local intervals = {}
    local lowest = distinct[1]
    for i, p in ipairs(distinct) do intervals[i] = p - lowest end

    local pcs_seen, pcs = {}, {}
    for _, iv in ipairs(intervals) do
        local pc = iv % 12
        if not pcs_seen[pc] then pcs_seen[pc] = true; pcs[#pcs + 1] = pc end
    end
    table.sort(pcs)

    return { sorted = distinct, intervals = intervals, pcs = pcs }
end

----------------------------------------------------------------------
-- pitches[] -> type_name, detail (detail is nil unless there's something
-- worth flagging, e.g. a slash/inversion).
----------------------------------------------------------------------
function GuitarClassifyChordType(pitches)
    local norm = GuitarNormalizeIntervals(pitches)
    local n = #norm.sorted

    if n == 0 then return 'No notes', nil end
    if n == 1 then return 'Single note', nil end

    if n == 2 then
        local interval = norm.intervals[2]
        local info = GUITAR_DYAD_INTERVALS[interval]
        if info then return info.name, nil end
        if interval > 12 then
            return string.format('Wide/compound interval (%d semitones, approx)', interval), nil
        end
        return string.format('Unrecognized interval (%d semitones)', interval), nil
    end

    -- 3+ distinct pitches: try each pitch class as a candidate root,
    -- lowest-derived pc (0) first, matching against known templates.
    for _, root_pc in ipairs(norm.pcs) do
        local rel = {}
        for _, pc in ipairs(norm.pcs) do rel[#rel + 1] = (pc - root_pc) % 12 end
        table.sort(rel)
        local key = table.concat(rel, ',')
        for _, tmpl in ipairs(GUITAR_CHORD_TEMPLATES) do
            if tmpl.key == key then
                if root_pc == 0 then
                    return tmpl.name, nil
                end
                return tmpl.name, string.format(
                    'possible slash/inversion (bass is %d semitones below the root)', root_pc)
            end
        end
    end
    return string.format('Unrecognized chord shape (%d distinct notes)', n), nil
end

----------------------------------------------------------------------
-- pitches[] -> width, combo, ambiguous_options
--   width:  '1-2' | '1-3' | '1-4' | '1-5' | '1-2 or 1-3' | '3-note chord' | nil
--   combo:  specific letter combo when unambiguous (only '1-5' -> 'GO'),
--           else nil
--   ambiguous_options: table of letter-combo strings when width is known
--     but no single combo is principled, else nil
--
-- Branches on distinct PITCH CLASSES for 3+-physical-note shapes, not raw
-- physical note count: a power chord voiced as root+5th+octave-doubled-root
-- is 3 physical pitches but only 2 pitch classes, and is harmonically a
-- dyad (width 1-3), not a "3-note chord". GuitarClassifyChordType already
-- reasons this way (via pitch classes) -- this function used to disagree
-- with it by using physical note count instead, which is the bug.
----------------------------------------------------------------------
function GuitarSuggestRBMapping(pitches)
    local norm = GuitarNormalizeIntervals(pitches)
    local n_pitches = #norm.sorted

    if n_pitches < 2 then return nil, nil, nil end

    if n_pitches == 2 then
        -- Only case where the RAW (non-mod-12) interval matters, so a true
        -- octave (12) stays distinct from a unison (0, already collapsed
        -- to n_pitches==1 by GuitarNormalizeIntervals's dedup) or a wide
        -- compound interval (>12).
        local interval = norm.intervals[2]
        local info = GUITAR_DYAD_INTERVALS[interval]
        if info then return info.width, nil, info.options end
        if interval > 12 then return '1-5', 'GO', nil end
        return nil, nil, nil
    end

    local n_pcs = #norm.pcs
    if n_pcs == 1 then
        -- 3+ physical notes, all the same pitch class (e.g. a root doubled
        -- at multiple octaves) -- musically just "the note", no width to suggest.
        return nil, nil, nil
    end
    if n_pcs == 2 then
        -- Harmonically a dyad voiced with a doubled note. pcs are already
        -- mod-12 and pcs[1] is always 0 (relative to the lowest pitch), so
        -- pcs[2] is the interval class 1-11.
        local info = GUITAR_DYAD_INTERVALS[norm.pcs[2]]
        if info then return info.width, nil, info.options end
        return nil, nil, nil
    end

    return '3-note chord', nil, GUITAR_3NOTE_COMBOS
end

----------------------------------------------------------------------
-- One-call pipeline for both the static reference table (offline, at
-- content-authoring time) and the live search box (per-frame).
----------------------------------------------------------------------
function GuitarAnalyzeShape(pitches)
    local norm = GuitarNormalizeIntervals(pitches)
    local type_name, detail = GuitarClassifyChordType(pitches)
    local width, combo, ambiguous_options = GuitarSuggestRBMapping(pitches)
    return {
        type_name = type_name,
        detail = detail,
        width = width,
        combo = combo,
        ambiguous_options = ambiguous_options,
        pitches = norm.sorted,
        intervals = norm.intervals,
    }
end

----------------------------------------------------------------------
-- Parse fret input for the live shape search box. One line, space-separated
-- tokens. Two forms, told apart by token count:
--   Full form (exactly 6 tokens): direct 1:1 positional mapping, token i is
--     string i literally -- fret number or any non-numeric token (e.g. 'x')
--     for muted, edge or interior, no reinterpretation. Same per-line
--     convention as ParseTabHorizontal in
--     rock_band_general_helper_vkr/actions_guitar_guide.lua, so a line
--     copy-pasted between the two tools behaves identically. This is the
--     only way to reach a shape anchored above the lowest strings.
--   Compact form (1-5 tokens): edge mutes are optional noise and are
--     ignored -- 'x'/'-'/any non-numeric token at the very start or end of
--     the list (or simply omitting trailing strings) doesn't change the
--     shape, so '7 7 5', 'x x x 7 7 5', '- - - 7 7 5', and '- 7 7 5 -' all
--     parse to the same pitches. Concretely: trim to the span between the
--     first and last NUMERIC token (that span is the "core", length L);
--     the core is right-anchored to the lowest L strings (core position k
--     -> GUITAR_TAB_OPEN[(7 - L) + k - 1]).
--     Interior mutes (non-numeric tokens strictly between two numeric
--     tokens) are NOT optional -- they mean "skip this string" and change
--     the interval (e.g. '7 x 5' is an octave; '7 5' is not) -- so they
--     stay in the core and consume a string slot instead of being dropped.
--     LIMITATION (by design, not a silent guess): since a short list always
--     anchors to the bottom, a shape meant for strings above the lowest
--     few (e.g. one that needs the G-B pair specifically, whose open gap is
--     a major third/4 semitones instead of the perfect-fourth/5-semitone
--     gap every other adjacent pair has) can't be expressed compactly and
--     needs the full 6-token form instead.
-- Returns shape[] ({str=1..6, fret=int}, tuning-independent) or nil, err_string
-- ('empty' | 'too many tokens' | 'no frets recognized'). local: only called
-- from within this file (by GuitarParseFretInput and
-- GuitarAnalyzeShapeAllTunings), which then apply a tuning via
-- GuitarShapeToPitches.
----------------------------------------------------------------------
local function _ParseFretPositions(text)
    if not text then return nil, 'empty' end
    local trimmed = text:match('^%s*(.-)%s*$')
    if trimmed == '' then return nil, 'empty' end

    local toks = {}
    for tok in trimmed:gmatch('%S+') do toks[#toks + 1] = tok end
    if #toks > 6 then return nil, 'too many tokens (max 6)' end

    if #toks == 6 then
        local shape = {}
        for i, tok in ipairs(toks) do
            local fret = tonumber(tok)
            if fret then shape[#shape + 1] = { str = i, fret = fret } end
        end
        if #shape == 0 then return nil, 'no frets recognized' end
        return shape
    end

    -- Compact/partial form: trim pure leading/trailing mute runs by finding
    -- the first/last numeric token; everything strictly between them
    -- (including any non-numeric interior tokens) is the core.
    local lo, hi
    for i, tok in ipairs(toks) do
        if tonumber(tok) then
            if not lo then lo = i end
            hi = i
        end
    end
    if not lo then return nil, 'no frets recognized' end

    local base_pos = 7 - (hi - lo + 1)  -- string index the core's first token maps to
    local shape = {}
    for i = lo, hi do
        local fret = tonumber(toks[i])
        if fret then
            shape[#shape + 1] = { str = base_pos + (i - lo), fret = fret }
        end
    end
    if #shape == 0 then return nil, 'no frets recognized' end
    return shape
end

-- Public wrapper: standard-tuning pitches[] (or nil, err), unchanged contract.
function GuitarParseFretInput(text)
    local shape, err = _ParseFretPositions(text)
    if not shape then return nil, err end
    return GuitarShapeToPitches(shape, GUITAR_TAB_OPEN)
end

----------------------------------------------------------------------
-- Analyze a fret-shape search string under every tuning in GUITAR_TUNINGS,
-- returning one result per DISTINCT outcome. Tunings that produce the exact
-- same pitch set for this shape (e.g. any shape that never touches string 6,
-- the only string drop D changes) are deduplicated automatically -- there's
-- no separate "does this shape touch the low string" check, comparing the
-- resulting pitch sets already covers it.
-- Not power-chord-specific: it just re-runs GuitarAnalyzeShape once per
-- tuning and reports whatever falls out, so a shape can come back as two
-- different (both meaningful) chords under two tunings, not just
-- "recognized vs. unrecognized".
-- Returns { { tuning_name = 'Standard', analysis = {...} }, ... } or nil, err.
----------------------------------------------------------------------
function GuitarAnalyzeShapeAllTunings(text)
    local shape, err = _ParseFretPositions(text)
    if not shape then return nil, err end

    local results, seen = {}, {}
    for _, tuning in ipairs(GUITAR_TUNINGS) do
        local pitches = GuitarShapeToPitches(shape, tuning.tab_open)
        local norm = GuitarNormalizeIntervals(pitches)
        local key = table.concat(norm.sorted, ',')
        if not seen[key] then
            seen[key] = true
            results[#results + 1] = { tuning_name = tuning.name, analysis = GuitarAnalyzeShape(pitches) }
        end
    end
    return results
end
