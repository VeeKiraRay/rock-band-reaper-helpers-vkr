-- Harmony style between a lead line and one harmony line - pure, no r / ctx / S.
--
-- The common names for harmony styles (octave, parallel, close, open, homophonic,
-- decorative, counter, cluster) mix three separate things, so this measures them as three
-- axes rather than picking one name:
--
--   rhythm  - homophonic  the harmony's onsets match the lead's, both ways
--             partial     the harmony's onsets match, but it sings only part of the lead's
--                         words (joins on a hook)
--             decorative  fewer, longer notes under a moving lead ("ooh" / "aah" pads)
--             counter     its own rhythm
--             alone       mostly sounds when the lead does not (call and response, echoes)
--   spacing - unison, octave, close (under an octave), open (over an octave), cluster
--             (seconds a large share of the time)
--   motion  - parallel: one interval most of the time, 'exact' when the semitones stay the
--             same, 'scale' when only the generic interval does (a 3rd moving between minor
--             and major, which is what the Harmonies tab's Diatonic 3rd mode makes)
--
-- Notes are { qn = start, len = length, pitch = MIDI note }, in quarter notes, pitched only
-- (the caller drops unpitched '#' notes). Measured offline over the official HARM1-3 charts
-- (a local probe); a future vocal-helper tab can call the same functions on REAPER notes.

HARMONY_ONSET_TOL_QN = 0.125   -- a 1/32 note: onsets this close count as together
HARMONY_SHARE        = 0.70    -- an axis value needs this share of the overlapping time
HARMONY_ALONE_COVER  = 0.30    -- under this share of its time with the lead -> 'alone'
HARMONY_CLUSTER      = 0.30    -- seconds this share of the time -> 'cluster'

-- Generic interval of a semitone distance (sign ignored, octaves folded): 1 unison,
-- 2 second, 3 third, ... 7 seventh. Tritone (6 st) counts as a 4th, the usual spelling
-- in a major key (F-B).
local GENERIC = { [0] = 1, 2, 2, 3, 3, 4, 4, 5, 6, 6, 7, 7 }
local GENERIC_NAME = { 'unison', '2nd', '3rd', '4th', '5th', '6th', '7th' }

-- '3rd above', 'octave below', '5th + octave above', 'unison'.
function HarmonyIntervalName(st)
    if st == 0 then return 'unison' end
    local a = math.abs(st)
    local dir = st > 0 and ' above' or ' below'
    local oct, rem = a // 12, a % 12
    if rem == 0 then
        return (oct == 1 and 'octave' or (oct .. ' octaves')) .. dir
    end
    local base = GENERIC_NAME[GENERIC[rem]]
    if oct > 0 then base = base .. ' + ' .. (oct == 1 and 'octave' or (oct .. ' octaves')) end
    return base .. dir
end

-- Signed generic interval key: same generic interval, same direction, same octave span.
-- 3 and 4 semitones above share a key; 3 above and 3 below do not.
local function GenericKey(st)
    if st == 0 then return 0 end
    local a = math.abs(st)
    local g = GENERIC[a % 12] + 7 * (a // 12)
    return st > 0 and g or -g
end

local function Overlap(a, b)
    local lo = math.max(a.qn, b.qn)
    local hi = math.min(a.qn + a.len, b.qn + b.len)
    return hi - lo
end

local function SortedCopy(notes)
    local out = {}
    for i, n in ipairs(notes) do out[i] = n end
    table.sort(out, function(a, b) return a.qn < b.qn end)
    return out
end

local function HasOnsetNear(notes, qn, tol)
    for _, n in ipairs(notes) do
        if math.abs(n.qn - qn) <= tol then return true end
    end
    return false
end

-- Measurements for one harmony line against the lead, over the notes given (normally one
-- phrase). Returns nil when the harmony has no notes.
--
--   harm_time / both_time   harmony duration, and the part of it with a lead note sounding
--   time_by_st[st]          overlapping time per signed interval (harmony - lead)
--   note_st[i]              each harmony note's interval to the lead note it overlaps most,
--                           or nil when it sings alone
--   h_onset_match           share of harmony onsets with a lead onset within the tolerance
--   l_onset_match           share of the lead onsets inside the harmony's span that the
--                           harmony also sings
--   note_ratio              harmony notes / lead notes inside the harmony's span
--   held_over               lead onsets falling inside a harmony note, per harmony note
--   motion                counts of 'parallel_exact', 'parallel_scale', 'similar',
--                           'contrary', 'oblique' over steps where either voice changes note
function HarmonyPairStats(lead, harm, opts)
    opts = opts or {}
    local tol = opts.onset_tol or HARMONY_ONSET_TOL_QN
    if not harm or #harm == 0 then return nil end
    lead = SortedCopy(lead or {})
    harm = SortedCopy(harm)

    local s = {
        n_harm = #harm, harm_time = 0, both_time = 0, time_by_st = {}, note_st = {},
        motion = { parallel_exact = 0, parallel_scale = 0, similar = 0, contrary = 0,
                   oblique = 0 },
    }

    -- Elementary segments where both sound, in time order, for the motion count.
    local segs = {}
    for i, h in ipairs(harm) do
        s.harm_time = s.harm_time + h.len
        local best, best_ov = nil, 0
        for _, l in ipairs(lead) do
            local ov = Overlap(h, l)
            if ov > 0 then
                local st = h.pitch - l.pitch
                s.both_time = s.both_time + ov
                s.time_by_st[st] = (s.time_by_st[st] or 0) + ov
                segs[#segs + 1] = { qn = math.max(h.qn, l.qn), hp = h.pitch, lp = l.pitch }
                if ov > best_ov then best, best_ov = st, ov end
            end
        end
        s.note_st[i] = best
    end
    table.sort(segs, function(a, b) return a.qn < b.qn end)

    -- A step is measured from an anchor segment to the first later segment where BOTH
    -- voices have moved, so a counter-melody whose notes change between the lead's still
    -- shows its direction. One voice moving twice while the other holds is 'oblique'.
    local anchor, moves_l, moves_h = segs[1], 0, 0
    for i = 2, #segs do
        local cur, prev = segs[i], segs[i - 1]
        if cur.lp ~= prev.lp then moves_l = moves_l + 1 end
        if cur.hp ~= prev.hp then moves_h = moves_h + 1 end
        local dl = cur.lp - anchor.lp
        local dh = cur.hp - anchor.hp
        local m
        if dl ~= 0 and dh ~= 0 then
            if (dl > 0) ~= (dh > 0) then
                m = 'contrary'
            elseif dl == dh then
                m = 'parallel_exact'
            elseif GenericKey(cur.hp - cur.lp) == GenericKey(anchor.hp - anchor.lp) then
                m = 'parallel_scale'
            else
                m = 'similar'
            end
        elseif (moves_l >= 2 and dh == 0) or (moves_h >= 2 and dl == 0) then
            m = 'oblique'
        end
        if m then
            s.motion[m] = s.motion[m] + 1
            anchor, moves_l, moves_h = cur, 0, 0
        end
    end

    -- Lead onsets falling inside a harmony note: how much it holds over the lead.
    local inside = 0
    for _, h in ipairs(harm) do
        for _, l in ipairs(lead) do
            if l.qn > h.qn + tol and l.qn < h.qn + h.len - tol then inside = inside + 1 end
        end
    end
    s.held_over = inside / #harm

    -- Onsets. The lead side only counts lead notes inside the harmony's own span, so a
    -- harmony that joins for the last words of a phrase is not 'counter'.
    local h_lo = harm[1].qn - tol
    local h_hi = harm[#harm].qn + harm[#harm].len
    local h_match = 0
    for _, h in ipairs(harm) do
        if HasOnsetNear(lead, h.qn, tol) then h_match = h_match + 1 end
    end
    local l_in, l_match = 0, 0
    for _, l in ipairs(lead) do
        if l.qn >= h_lo and l.qn < h_hi then
            l_in = l_in + 1
            if HasOnsetNear(harm, l.qn, tol) then l_match = l_match + 1 end
        end
    end
    s.h_onset_match = h_match / #harm
    s.l_onset_match = l_in > 0 and l_match / l_in or 0
    s.n_lead_in     = l_in
    s.note_ratio    = l_in > 0 and #harm / l_in or math.huge
    return s
end

-- Share of the overlapping time whose interval passes keep(st).
local function TimeShare(s, keep)
    if s.both_time <= 0 then return 0 end
    local t = 0
    for st, d in pairs(s.time_by_st) do if keep(st) then t = t + d end end
    return t / s.both_time
end

-- The most common value of key(st) by overlapping time: value, share.
local function TopBy(s, key)
    local acc = {}
    for st, d in pairs(s.time_by_st) do
        local k = key(st)
        acc[k] = (acc[k] or 0) + d
    end
    local best, best_t = nil, -1
    for k, t in pairs(acc) do
        if t > best_t or (t == best_t and math.abs(k) < math.abs(best or 0)) then best, best_t = k, t end
    end
    if best == nil or s.both_time <= 0 then return nil, 0 end
    return best, best_t / s.both_time
end

-- Classifies a HarmonyPairStats result. Returns nil for nil stats, else
--   { rhythm, spacing, parallel = nil | { kind = 'exact'|'scale', st = semitones,
--     name = '3rd above' }, above = share of overlapping time above the lead,
--     label = 'homophonic, close, parallel 3rd above (scale)' }
function HarmonyClassify(s)
    if not s then return nil end
    local c = {}

    local cover = s.harm_time > 0 and s.both_time / s.harm_time or 0
    if cover < HARMONY_ALONE_COVER then
        c.rhythm = 'alone'
    elseif s.h_onset_match >= 0.75 and s.l_onset_match >= 0.75 then
        c.rhythm = 'homophonic'
    elseif s.held_over >= 1 and s.note_ratio <= 0.5 then
        c.rhythm = 'decorative'
    elseif s.h_onset_match >= 0.75 then
        c.rhythm = 'partial'
    else
        c.rhythm = 'counter'
    end

    c.above = TimeShare(s, function(st) return st > 0 end)
    if s.both_time > 0 then
        local unison = TimeShare(s, function(st) return st == 0 end)
        local octave = TimeShare(s, function(st) return st ~= 0 and st % 12 == 0 end)
        local second = TimeShare(s, function(st) local a = math.abs(st) % 12; return a == 1 or a == 2 end)
        local wide   = TimeShare(s, function(st) return math.abs(st) > 12 end)
        if unison >= HARMONY_SHARE then
            c.spacing = 'unison'
        elseif octave >= HARMONY_SHARE then
            c.spacing = 'octave'
        elseif second >= HARMONY_CLUSTER then
            c.spacing = 'cluster'
        elseif wide >= 0.5 then
            c.spacing = 'open'
        else
            c.spacing = 'close'
        end

        if c.spacing ~= 'unison' and c.spacing ~= 'octave' then
            local st, share = TopBy(s, function(x) return x end)
            if share >= HARMONY_SHARE then
                c.parallel = { kind = 'exact', st = st, name = HarmonyIntervalName(st) }
            else
                local g, gshare = TopBy(s, GenericKey)
                if gshare >= HARMONY_SHARE then
                    -- Name it by its commonest semitone size within that generic interval.
                    local best_st, best_t = nil, -1
                    for x, d in pairs(s.time_by_st) do
                        if GenericKey(x) == g and d > best_t then best_st, best_t = x, d end
                    end
                    c.parallel = { kind = 'scale', st = best_st, name = HarmonyIntervalName(best_st) }
                end
            end
        end
    else
        c.spacing = 'none'
    end

    local parts = { c.rhythm, c.spacing }
    if c.parallel then
        parts[#parts + 1] = ('parallel %s (%s)'):format(c.parallel.name, c.parallel.kind)
    elseif c.spacing == 'octave' then
        parts[#parts] = 'octave ' .. (c.above >= 0.5 and 'above' or 'below')
    end
    c.label = table.concat(parts, ', ')
    return c
end

-- Which fixed semitone offset reproduces the most harmony notes exactly (a note counts
-- when its pitch = the lead note it overlaps most + offset). Returns offset, share of all
-- harmony notes; nil when no harmony note overlaps the lead. This is what a Harmonies tab
-- Fixed Copy style (or Copy as-is at 0) would get right, timing aside.
function HarmonyBestFixedOffset(s)
    if not s then return nil, 0 end
    local count = {}
    for i = 1, s.n_harm do
        local st = s.note_st[i]
        if st then count[st] = (count[st] or 0) + 1 end
    end
    local best, best_n = nil, 0
    for st, n in pairs(count) do
        if n > best_n or (n == best_n and math.abs(st) < math.abs(best or 0)) then best, best_n = st, n end
    end
    if best == nil then return nil, 0 end
    return best, best_n / s.n_harm
end
