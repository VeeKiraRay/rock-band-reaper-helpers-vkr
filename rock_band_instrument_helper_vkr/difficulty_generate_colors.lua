-- Difficulty > Generate: chords and colors - reducing chord size and span, and moving
-- lines down a lane. Pure (no r, no S); used by the planner (difficulty_generate_5lane.lua)
-- and loaded before it. Reads GEN5_PARAMS at call time.

local function Copy(offs)
    local out = {}
    for i, o in ipairs(offs) do out[i] = o end
    return out
end

local function Dedupe(offs)
    table.sort(offs)
    local out = {}
    for _, o in ipairs(offs) do
        if out[#out] ~= o then out[#out + 1] = o end
    end
    return out
end

local function SameOffs(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Reduce a chord to max_n notes. Two notes keep the outer pair; three keep the outer
-- pair and the middle note; one keeps the lowest.
function Gen5ReduceChordSize(offs, max_n)
    if #offs <= max_n then return offs end
    if max_n == 1 then return { offs[1] } end
    if max_n == 2 then return { offs[1], offs[#offs] } end
    return { offs[1], offs[math.ceil(#offs / 2)], offs[#offs] }
end

-- Keys (5-lane): reduce a chord to max_n notes by keeping its TOP notes, as Pro Keys does -
-- on every tier, Easy's single note included; Gen5KeysEasyMotion then keeps Easy's line
-- moving.
function Gen5ReduceChordSizeKeys(offs, max_n)
    if #offs <= max_n then return offs end
    local out = {}
    for i = #offs - max_n + 1, #offs do out[#out + 1] = offs[i] end
    return out
end

-- Keys Easy: a Medium chord reduced to one note keeps the line moving. out: the Easy events
-- (offs already one note); upper_offs[i]: the offs of the Medium event out[i] came from.
--   1. the same chord as the previous one -> the previous Easy note (a chord repeated for a
--      while stays one note: GR GR GR is G G G, never G R G);
--   2. a different chord whose note would repeat the previous Easy note -> another note of
--      the chord, from the top down (GR then GY: G then Y);
--   3. otherwise the note the chord rule chose.
-- Picking one note per chord on its own made repeats Medium does not have. Returns notes
-- changed.
function Gen5KeysEasyMotion(out, upper_offs)
    local changed = 0
    for i = 2, #out do
        local ev, pv, up = out[i], out[i - 1], upper_offs[i]
        if up and #up >= 2 and #ev.offs == 1 and #pv.offs == 1 and upper_offs[i - 1] then
            if SameOffs(up, upper_offs[i - 1]) then
                if ev.offs[1] ~= pv.offs[1] then ev.offs = { pv.offs[1] }; changed = changed + 1 end
            elseif ev.offs[1] == pv.offs[1] then
                for k = #up, 1, -1 do
                    if up[k] ~= pv.offs[1] then ev.offs = { up[k] }; changed = changed + 1; break end
                end
            end
        end
    end
    return changed
end

-- Narrow a chord whose span exceeds max_span by lowering its top note.
function Gen5NarrowSpan(offs, max_span)
    if max_span and #offs >= 2 and offs[#offs] - offs[1] > max_span then
        offs[#offs] = offs[1] + max_span
        return Dedupe(offs)
    end
    return offs
end

-- Guitar/Bass Medium/Easy: shift each passage down as a whole until it fits under
-- the tier's focus ceiling, so the shape of the line survives (Orange>Blue,
-- Blue>Yellow ...) instead of only the top notes collapsing.
-- Notes that would fall below Green stay on Green.
function Gen5ShiftSegments(out, ceiling)
    local p = GEN5_PARAMS
    local i, changed = 1, 0
    while i <= #out do
        local j, top = i, 0
        repeat
            for _, o in ipairs(out[j].offs) do if o > top then top = o end end
            j = j + 1
        until j > #out
            or out[j].qn - out[j - 1].qn > p.segment_gap + 0.02
            or out[j].qn - out[i].qn >= p.segment_max
        local shift = top - ceiling
        if shift > 0 then
            for k = i, j - 1 do
                local before = Copy(out[k].offs)
                for m, o in ipairs(out[k].offs) do out[k].offs[m] = math.max(0, o - shift) end
                out[k].offs = Dedupe(out[k].offs)
                if not SameOffs(before, out[k].offs) then changed = changed + 1 end
            end
        end
        i = j
    end
    return changed
end

-- Hard's color fallback: move each BAR down as a whole until its top note is at most
-- `top`, so a line keeps its shape (O B Y -> B Y R). Bar-aligned rather than
-- Gen5ShiftSegments' rest-split passages: a sparse bar of notes a dotted quarter apart would
-- split into one passage per note there, and shift note by note (O B Y -> B B Y).
-- Returns the number of events whose colors changed.
function Gen5ShiftBars(out, top)
    local bars, order = {}, {}
    for k, ev in ipairs(out) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        if not bars[key] then bars[key] = {}; order[#order + 1] = key end
        table.insert(bars[key], k)
    end
    local changed = 0
    for _, key in ipairs(order) do
        local hi = 0
        for _, k in ipairs(bars[key]) do
            for _, o in ipairs(out[k].offs) do if o > hi then hi = o end end
        end
        local shift = hi - top
        if shift > 0 then
            for _, k in ipairs(bars[key]) do
                local before = Copy(out[k].offs)
                for m, o in ipairs(out[k].offs) do out[k].offs[m] = math.max(0, o - shift) end
                out[k].offs = Dedupe(out[k].offs)
                if not SameOffs(before, out[k].offs) then changed = changed + 1 end
            end
        end
    end
    return changed
end

-- Guitar/Bass Medium/Easy: move only the notes and chords above `top` down - unless that makes
-- a note repeat its neighbour's color where the tier above changes color; then the whole
-- bar moves down (Gen5ShiftBars), so the line keeps its shape. From the user's review:
-- G O Y B -> G B Y B (approved) moves only the Orange, while
-- G Y B O -> G Y B B (rejected: a Blue repeat Hard never had) moves the bar
-- (G R Y B). The neighbour across a bar line counts too.
-- Returns the number of events whose colors changed.
function Gen5ClampOrShiftBars(out, top)
    local bars, order = {}, {}
    for k, ev in ipairs(out) do
        local start = ev.bar_qn and (ev.qn - ev.bar_qn) or math.floor(ev.qn / 4) * 4
        local key = ('%.3f'):format(start)
        if not bars[key] then bars[key] = {}; order[#order + 1] = key end
        table.insert(bars[key], k)
    end
    local orig = {}
    for k, ev in ipairs(out) do orig[k] = Copy(ev.offs) end
    -- A note or chord above `top` moves down as a whole, so a chord keeps its shape
    -- (Y+O -> R+B, as the user's verified charts have it, not Y+B).
    local function Clamped(offs)
        local hi = 0
        for _, o in ipairs(offs) do if o > hi then hi = o end end
        local d, c = math.max(0, hi - top), {}
        for m, o in ipairs(offs) do c[m] = math.max(0, o - d) end
        return Dedupe(c)
    end
    local changed = 0
    for _, key in ipairs(order) do
        local idx = bars[key]
        local hi = 0
        for _, k in ipairs(idx) do
            for _, o in ipairs(out[k].offs) do if o > hi then hi = o end end
        end
        if hi > top then
            -- A new repeat: clamped equal to the note just before or after it in the same
            -- bar, at most a quarter note away, where the originals differ. Not across a
            -- bar line, and not further apart: the user's verified charts keep RB | RB over
            -- a bar line and Easy's Y . . Y a half note or more apart.
            local in_bar = {}
            for _, k in ipairs(idx) do in_bar[k] = true end
            local function Near(a, b) return in_bar[b] and math.abs(out[a].qn - out[b].qn) <= 1.02 end
            local repeat_made = false
            for _, k in ipairs(idx) do
                local mine = Clamped(out[k].offs)
                if Near(k, k - 1) and SameOffs(mine, Clamped(orig[k - 1])) and not SameOffs(orig[k], orig[k - 1]) then
                    repeat_made = true
                end
                if Near(k, k + 1) and SameOffs(mine, Clamped(orig[k + 1])) and not SameOffs(orig[k], orig[k + 1]) then
                    repeat_made = true
                end
            end
            if repeat_made then
                local shift = hi - top
                for _, k in ipairs(idx) do
                    for m, o in ipairs(out[k].offs) do out[k].offs[m] = math.max(0, o - shift) end
                    out[k].offs = Dedupe(out[k].offs)
                    if not SameOffs(orig[k], out[k].offs) then changed = changed + 1 end
                end
            else
                for _, k in ipairs(idx) do
                    out[k].offs = Clamped(out[k].offs)
                    if not SameOffs(orig[k], out[k].offs) then changed = changed + 1 end
                end
            end
        end
    end
    return changed
end
