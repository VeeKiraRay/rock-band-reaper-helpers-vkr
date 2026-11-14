-- Queries over RB_VENUE_SHOTS (lib/reaper_venue_shots.lua, generated) for the Directed Moves window (rock_band_directed_moves_vkr.lua).
-- Pure: no r / ctx / S. Load after reaper_venue_shots.lua.
--
-- A filter is { style = 'R'|'D'|'B'|'S'|nil, gender = 'M'|'F'|nil, kind = <kind>|nil,
-- lineup = 'no_keys'|'no_guitar'|'no_bass'|nil } - nil means "any" (lineup nil = all five
-- members on stage, where the game applies no lineup check). How the game picks a shot, which
-- these tests follow: a cut tagged for every style and both genders always plays, free cuts
-- always play, other directed cuts need the focus member's gender and the song's style tagged;
-- in a band with one member off stage the shot must be tagged for that lineup.

VENUE_SHOT_KIND_LABELS = {
    arena = 'Arena', big_club = 'Big club', festival = 'Festival',
    small_club = 'Small club', video = 'Video',
}

VENUE_SHOT_LINEUP_LABELS = {
    no_keys = 'without keys', no_guitar = 'without guitar', no_bass = 'without bass',
}

-- Every directed camera event in the data, sorted (normal / coop shots are not listed - only
-- their lineup remaps are kept); group 'directed' narrows it the same way.
function VenueShotEvents(group)
    local out = {}
    for cat in pairs(RB_VENUE_SHOTS.events) do
        if not group or cat:sub(1, #group + 1) == group .. '_' then out[#out + 1] = cat end
    end
    table.sort(out)
    return out
end

function VenueShotEvent(cat)
    return RB_VENUE_SHOTS.events[cat]
end

local function HasKind(kinds, kind)
    for _, k in ipairs(kinds) do
        if k == kind or k == kind .. '*' then return true end
    end
    return false
end

-- Does a move row play under the filter?
function VenueShotRowMatches(row, filter, ev)
    filter = filter or {}
    local free = ev and ev.free
    if not free then
        if filter.gender and row.gender ~= 'B' and row.gender ~= filter.gender then return false end
        if filter.style and not row.styles:find(filter.style, 1, true) then return false end
    end
    if filter.kind and not HasKind(row.kinds, filter.kind) then return false end
    if filter.lineup and not (' ' .. row.lineups .. ' '):find(' ' .. filter.lineup .. ' ', 1, true) then
        return false
    end
    return true
end

-- What the event becomes when a member is off stage: nil (unchanged), 'dropped', or a list
-- of camera events the game picks from instead. Covers directed cuts and normal (coop) shots.
function VenueShotRemap(cat, lineup)
    if not lineup then return nil end
    local ev = RB_VENUE_SHOTS.events[cat]
    local remap = ev and ev.remap or RB_VENUE_SHOTS.coop_remap[cat]
    return remap and remap[lineup] or nil
end

-- "Arena, Big club*" from a kinds list; "All" when every venue kind has it in all its venues.
function VenueShotKindsText(kinds)
    if #kinds == #RB_VENUE_SHOTS.kinds then
        local whole = true
        for _, k in ipairs(kinds) do
            if k:sub(-1) == '*' then whole = false end
        end
        if whole then return 'All' end
    end
    local parts = {}
    for _, k in ipairs(kinds) do
        local partial = k:sub(-1) == '*'
        local base = partial and k:sub(1, -2) or k
        parts[#parts + 1] = (VENUE_SHOT_KIND_LABELS[base] or base) .. (partial and '*' or '')
    end
    return table.concat(parts, ', ')
end

-- The filter a move pins down: { style, gender, kind }, each set only when the row allows
-- exactly one value (one style letter, a gender other than Both, one venue kind - '*'
-- stripped). A free cut ignores style and gender, so those stay nil. Lineup is never set:
-- a full band has no lineup check, so every move plays for it.
function VenueShotRowFilter(row, ev)
    local f = {}
    if not (ev and ev.free) then
        if #row.styles == 1 then f.style = row.styles end
        if row.gender == 'M' or row.gender == 'F' then f.gender = row.gender end
    end
    if #row.kinds == 1 then f.kind = (row.kinds[1]:gsub('%*$', '')) end
    return f
end

local WHO_LETTERS = { vocals = 'V', guitar = 'G', bass = 'B', drums = 'D', keys = 'K' }

-- "vocals+guitar+bass" -> "V+G+B"; one member stays spelled out.
function VenueShotWhoShort(who)
    if not who:find('+', 1, true) then return who end
    return (who:gsub('[^+]+', function(m) return WHO_LETTERS[m] or m end))
end

-- Keyword search. A section per camera event whose name, or any move's label / keywords /
-- member, contains every word of `text` (case-insensitive). An event whose own name matches
-- lists all its moves; otherwise only the matching ones. Coop events have no move rows and
-- match on their name only. Returns up to `limit` sections { cat = , rows = {...} } in event
-- order, and the total number of matching events.
function VenueShotSearch(text, limit)
    local words = {}
    for w in (text or ''):lower():gmatch('%S+') do words[#words + 1] = w end
    if #words == 0 then return {}, 0 end
    local function all_in(hay)
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then return false end
        end
        return true
    end
    local out, total = {}, 0
    for _, cat in ipairs(VenueShotEvents()) do
        local ev = RB_VENUE_SHOTS.events[cat]
        local rows
        if all_in(cat:lower() .. ' ' .. cat:gsub('_', ' '):lower()) then
            rows = ev.moves or {}
        else
            rows = {}
            for _, row in ipairs(ev.moves or {}) do
                local hay = (row.label .. ' ' .. (row.keywords or '') .. ' ' .. row.who):lower()
                if all_in(hay) then rows[#rows + 1] = row end
            end
            if #rows == 0 then rows = nil end
        end
        if rows then
            total = total + 1
            if not limit or #out < limit then out[#out + 1] = { cat = cat, rows = rows } end
        end
    end
    return out, total
end
