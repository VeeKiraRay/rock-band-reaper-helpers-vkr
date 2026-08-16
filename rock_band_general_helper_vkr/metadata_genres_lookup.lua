-- Genre converter lookup logic.
--
-- Reads metadata_genres.lua (supported vocabulary) and metadata_genres_ext.lua
-- (extended vocabulary + mapping) and answers the two questions the UI asks:
-- "what does my genre map to" and "what maps onto this supported pair".
--
-- Pure. No r / ctx / S / TIPS dependencies, so dev/tests drives it directly.
-- Both source tables are treated as immutable; nothing here writes to them.

-- Built on first use and then reused. The tables never change at runtime, so there is
-- no invalidation path and none is needed.
local _family_cache = nil
local _by_key       = nil
local _reverse      = nil

-- Stable key for one supported pair.
local function PairKey(genre_key, sub_key)
    return genre_key .. '/' .. sub_key
end

local function BuildCaches()
    if _family_cache then return end
    _family_cache, _by_key = {}, {}
    for _, fam in ipairs(GENRE_FAMILY_ORDER) do
        _family_cache[fam] = {}
    end
    for _, e in ipairs(EXTENDED_GENRES) do
        _by_key[e.key] = e
        local bucket = _family_cache[e.family]
        if bucket then bucket[#bucket + 1] = e end
    end
end

-- Ordered entries for one family, in the order EXTENDED_GENRES declares them.
-- Returns an empty table for an unknown family rather than nil, so a caller can
-- always take #result without a guard.
function GenresInFamily(family_key)
    BuildCaches()
    return _family_cache[family_key] or {}
end

function ExtendedGenreByKey(key)
    BuildCaches()
    return _by_key[key]
end

-- Look up one supported subgenre record. Returns nil when either key is unknown,
-- which is what lets ValidateGenreTables report a broken candidate.
function RB3Subgenre(genre_key, sub_key)
    local g = RB3_GENRES[genre_key]
    if not g then return nil end
    for _, s in ipairs(g.subgenres) do
        if s.key == sub_key then return s end
    end
    return nil
end

-- Forward direction: an extended genre to its ranked supported candidates.
--
-- Each candidate carries the display labels plus the supported subgenre record, so the
-- UI can show whatever description the documentation happens to have without looking
-- anything up itself. A candidate whose pair does not resolve is SKIPPED rather than
-- returned half-built - the test asserts this never happens, and a malformed row must
-- not be able to crash the tab.
function ResolveExtendedGenre(key)
    local e = ExtendedGenreByKey(key)
    if not e then return nil end

    local out = {
        key    = e.key,
        label  = e.label,
        family = e.family,
        family_label = GENRE_FAMILIES[e.family],
        candidates = {},
        see_also   = {},
    }
    -- see_also points at another EXTENDED entry, not at a supported pair: it means "you
    -- may have picked the wrong genre", which is a different claim from "here is another
    -- supported home for the genre you picked". Resolved to a label here so the UI can
    -- draw it without a second lookup, and skipped when unresolvable for the same reason
    -- a broken candidate is skipped.
    for _, sa in ipairs(e.see_also or {}) do
        local target = ExtendedGenreByKey(sa.key)
        if target then
            out.see_also[#out.see_also + 1] = {
                key = sa.key, label = target.label, when = sa.when,
            }
        end
    end
    for _, c in ipairs(e.candidates) do
        local g   = RB3_GENRES[c.genre]
        local sub = RB3Subgenre(c.genre, c.subgenre)
        if g and sub then
            out.candidates[#out.candidates + 1] = {
                genre_key    = c.genre,
                genre_label  = g.label,
                sub_key      = c.subgenre,
                sub_label    = sub.label,
                why          = c.why,
                sub          = sub,   -- blurb / elements / artists / albums, all optional
            }
        end
    end
    return out
end

-- Reverse direction: for every supported pair, which extended genres point at it.
--
-- NO UI CALLS THIS TODAY. The reverse view was cut from the first release (see the header
-- of ui_metadata_genre.lua), but this is kept rather than deleted for two reasons: it is
-- pure and already covered, so restoring the view is a UI-only change; and the
-- round-trip test over it is a genuine integrity check on the mapping - it proves every
-- candidate is reachable from its pair in the right rank bucket, which nothing else
-- verifies. Delete it only if that test goes too, and know what is being given up.
--
-- Split into `first` (the pair is that entry's best answer) and `lower` (it is offered
-- as an alternative). The distinction is the whole value of the reverse view: a pair
-- that only ever appears as somebody's second choice is a different thing from one that
-- is a style's primary home, and collapsing them would hide that.
function BuildReverseGenreIndex()
    if _reverse then return _reverse end
    _reverse = {}
    for _, e in ipairs(EXTENDED_GENRES) do
        for i, c in ipairs(e.candidates) do
            local pk = PairKey(c.genre, c.subgenre)
            local rec = _reverse[pk]
            if not rec then
                rec = { first = {}, lower = {} }
                _reverse[pk] = rec
            end
            local bucket = (i == 1) and rec.first or rec.lower
            bucket[#bucket + 1] = { key = e.key, label = e.label, family = e.family, why = c.why }
        end
    end
    return _reverse
end

-- Convenience for the reverse view: the entry lists for one pair, never nil.
function ExtendedGenresForPair(genre_key, sub_key)
    local rec = BuildReverseGenreIndex()[PairKey(genre_key, sub_key)]
    if not rec then return {}, {} end
    return rec.first, rec.lower
end

-- Returns a list of human-readable problems; empty means the tables agree.
-- Used by dev/tests/metadata_genres.lua, not by the UI.
function ValidateGenreTables()
    local problems = {}
    local function bad(fmt, ...) problems[#problems + 1] = string.format(fmt, ...) end

    -- Supported vocabulary: order list and keyed table must agree exactly.
    local in_order = {}
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        if in_order[gk] then bad('RB3_GENRE_ORDER lists %s twice', gk) end
        in_order[gk] = true
        if not RB3_GENRES[gk] then bad('RB3_GENRE_ORDER has %s with no RB3_GENRES entry', gk) end
    end
    for gk in pairs(RB3_GENRES) do
        if not in_order[gk] then bad('RB3_GENRES has %s, missing from RB3_GENRE_ORDER', gk) end
    end
    for gk, g in pairs(RB3_GENRES) do
        if not g.label or g.label == '' then bad('%s has no label', gk) end
        if not g.subgenres or #g.subgenres == 0 then bad('%s has no subgenres', gk) end
        local seen = {}
        for _, s in ipairs(g.subgenres or {}) do
            if seen[s.key] then bad('%s lists subgenre %s twice', gk, s.key) end
            seen[s.key] = true
            if not s.label or s.label == '' then bad('%s/%s has no label', gk, tostring(s.key)) end
        end
    end

    -- Extended vocabulary.
    local seen_key, seen_label = {}, {}
    local fam_ok, fam_used = {}, {}
    for _, f in ipairs(GENRE_FAMILY_ORDER) do
        if not GENRE_FAMILIES[f] then bad('family %s has no display label', f) end
        fam_ok[f] = true
    end
    for f in pairs(GENRE_FAMILIES) do
        if not fam_ok[f] then bad('GENRE_FAMILIES has %s, missing from GENRE_FAMILY_ORDER', f) end
    end

    for _, e in ipairs(EXTENDED_GENRES) do
        if seen_key[e.key] then bad('duplicate extended key: %s', e.key) end
        if seen_label[e.label] then bad('duplicate extended label: %s', e.label) end
        seen_key[e.key], seen_label[e.label] = true, true

        if not fam_ok[e.family] then
            bad('%s has unknown family %s', e.key, tostring(e.family))
        else
            fam_used[e.family] = true
        end

        local n = #(e.candidates or {})
        if n < 1 or n > 3 then bad('%s has %d candidates, want 1 to 3', e.key, n) end
        for _, c in ipairs(e.candidates or {}) do
            if not RB3_GENRES[c.genre] then
                bad('%s points at unknown genre %s', e.key, tostring(c.genre))
            elseif not RB3Subgenre(c.genre, c.subgenre) then
                bad('%s points at %s/%s, which does not exist', e.key, c.genre, tostring(c.subgenre))
            end
            if not c.why or #c.why < 20 then
                bad('%s -> %s/%s has no usable reason', e.key, tostring(c.genre), tostring(c.subgenre))
            end
        end

        for _, sa in ipairs(e.see_also or {}) do
            if type(sa.key) ~= 'string' then
                bad('%s has a see_also with no key', e.key)
            elseif sa.key == e.key then
                bad('%s points see_also at itself', e.key)
            end
            if not sa.when or #sa.when < 20 then
                bad('%s -> see_also %s has no usable condition', e.key, tostring(sa.key))
            end
        end
    end

    -- Resolved separately: every entry must exist before a see_also key can be checked
    -- against the set, and seen_key is only complete after the loop above.
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, sa in ipairs(e.see_also or {}) do
            if type(sa.key) == 'string' and not seen_key[sa.key] then
                bad('%s points see_also at %s, which does not exist', e.key, sa.key)
            end
        end
    end

    -- An empty family draws an empty combo, which reads as a broken tab.
    for _, f in ipairs(GENRE_FAMILY_ORDER) do
        if not fam_used[f] then bad('family %s has no entries', f) end
    end

    -- A supported genre nothing can reach is a hole in the mapping, not a valid state.
    local reached = {}
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, c in ipairs(e.candidates or {}) do reached[c.genre] = true end
    end
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        if not reached[gk] then bad('no extended genre maps to %s', gk) end
    end

    return problems
end
