-- Difficulty > Generate: overlapping gems on Keys and Pro Keys - a note held while later
-- notes start over it (the RBN docs' broken chords) - and rolled chords.
--
-- The RBN docs (5 Lane Keyboard "Overlaps and Sustains", Pro Keyboard "Overlapping
-- Gems"): Expert/Hard at most 3 notes sounding at once on 5-lane and 4 on Pro Keys, those
-- within an octave; Medium "generally no overlapping notes ... in some rare cases 2 note
-- overlaps if they are spaced out over a 1/4 note or more"; none on Easy.
--
-- Official charts (RB3 DLC, hold-out excluded) decide Hard's overlaps per song: of the
-- songs with 5+ Expert overlaps whose notes both stay on Hard, about half keep none of them
-- (5-lane 52 of 107, Pro Keys 60 of 113) and about a sixth keep every one. Medium keeps
-- almost none (5-lane: none in 32 of 36 songs); what it does keep is mostly a note held a
-- bar or more. The rules here are the user's (2026-10-08): Hard keeps Expert's overlaps
-- within the limits and never loses an onset to one, Medium keeps only a long hold, Easy
-- none, and a rolled chord becomes one chord.
--
-- PURE: no r, no S. Load after difficulty_generate_params.lua.

-- Most notes sounding at once (held notes plus the onset's own) per kind and tier. A tier
-- not listed never holds a note over a later onset.
GEN_OVERLAP_MAX = { k5 = { H = 3, M = 2 }, pk = { H = 4, M = 2 } }
-- Pro Keys: notes sounding together stay within this many semitones (the docs' octave).
GEN_OVERLAP_SPAN = { pk = 12 }

local EPS        = GEN5_EPS
local SUSTAIN_QN = GEN5_SUSTAIN_QN

-- Beat strength by Gen5BeatClass, for where a rolled chord goes.
local STRENGTH = { down = 5, beat = 4, ['8th'] = 3, ['16th'] = 2, trip = 2, other = 1 }

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- A rolled chord on the upper tier: onsets each closer than gap_fn(ev) to the next, the
-- last one a sustain, and every earlier note still sounding an 8th or more past the last
-- onset. Hard plays it as ONE chord with every note of the roll, on the roll's strongest
-- beat position (user rule 2026-10-08, from vm_loiri_sydameeni_joulu_teen's final chord: R
-- and Y a 1/32 apart into a held O on the downbeat; as single notes the gap kept only the
-- O). The planner's chord rules reduce the chord afterwards.
-- Returns (events, merged): a new list, and how many rolls became chords.
function GenMergeRolls(events, gap_fn)
    local out, merged = {}, 0
    for _, ev in ipairs(events) do
        local first = #out + 1
        if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then
            local nxt = ev
            local k = #out
            -- A roll merged so far (rolled) is absorbed too: the roll goes on until the
            -- note it lands on.
            while k >= 1 and nxt.qn - out[k].qn < gap_fn(out[k]) - EPS
                  and out[k].qn_e >= ev.qn + SUSTAIN_QN - EPS do
                first, nxt, k = k, out[k], k - 1
            end
        end
        if first <= #out then
            -- The chord goes on the roll's strongest beat position, the later one on a tie:
            -- the downbeat a roll lands on (Loiri), or the downbeat it starts from
            -- (promisesinthedark: 53+60 on the downbeat, 62 a 16th later). On the 16th, the
            -- song-wide keep cap took the chord and left the bar empty.
            local anchor, best = ev, STRENGTH[Gen5BeatClass(ev)] or 0
            for k = #out, first, -1 do
                local st = STRENGTH[Gen5BeatClass(out[k])] or 0
                if st > best then anchor, best = out[k], st end
            end
            local c, seen, offs, grows = Copy(anchor), {}, {}, false
            for k = first, #out do
                if out[k].rolled then grows = true end
                for _, o in ipairs(out[k].offs) do if not seen[o] then seen[o] = true; offs[#offs + 1] = o end end
            end
            for _, o in ipairs(ev.offs) do if not seen[o] then seen[o] = true; offs[#offs + 1] = o end end
            table.sort(offs)
            c.offs, c.rolled = offs, true
            for k = #out, first, -1 do out[k] = nil end
            out[#out + 1] = c
            if not grows then merged = merged + 1 end
        else
            out[#out + 1] = ev
        end
    end
    return out, merged
end

-- Which notes of a planned tier stay held over the onsets that start under them.
-- out: the tier's events, sorted by qn, each still as long as on the upper tier (an
-- upper-tier overlap shows as qn_e past later onsets). At every onset, the notes still
-- sounding plus the onset's own must fit GEN_OVERLAP_MAX (and on Pro Keys lie within
-- GEN_OVERLAP_SPAN):
--   1. the onset's chord loses notes - reduce(offs, n), the instrument's own chord rule -
--      but never below one, so a held note does not cost a note that starts;
--   2. if the held notes alone fill the limit, the earliest-started ones end at the onset.
-- A note only holds over an onset when it is a sustain, rings on past the onset by at
-- least its release gap (release(held, onset)), and shares no lane or pitch with it.
-- Medium holds a note only over an onset a bar or more after the note starts.
-- A note held over at least one onset gets hold = true: FixLengths then measures its
-- release gap from the first onset after it ends. A note that has to stop ends AT the
-- onset, and FixLengths leaves the gap before it as for any sustain.
-- Returns { held = notes held over, chord_notes = notes onsets lost, trimmed = held
-- notes ended early to keep the limit }.
function GenPlanOverlaps(kind, dl, out, reduce, release)
    local stats = { held = 0, chord_notes = 0, trimmed = 0 }
    local lim = GEN_OVERLAP_MAX[kind] and GEN_OVERLAP_MAX[kind][dl]
    if not lim then return stats end
    local span = GEN_OVERLAP_SPAN[kind]
    for i = 2, #out do
        local ev = out[i]
        local held = {}
        for j = 1, i - 1 do
            local h = out[j]
            if h.qn_e > ev.qn + EPS then
                local ok = h.qn_e - h.qn >= SUSTAIN_QN - EPS
                           and h.qn_e - ev.qn >= release(h, ev) - EPS
                           and (dl ~= 'M' or ev.qn - h.qn >= (h.bar_len or 4) - EPS)
                if ok then
                    for _, o in ipairs(h.offs) do
                        for _, p in ipairs(ev.offs) do if o == p then ok = false end end
                    end
                end
                if ok then held[#held + 1] = h else h.qn_e = ev.qn end
            end
        end
        while #held > 0 do
            local n_held, lo, hi = 0, math.huge, -math.huge
            for _, h in ipairs(held) do
                n_held = n_held + #h.offs
                for _, o in ipairs(h.offs) do lo, hi = math.min(lo, o), math.max(hi, o) end
            end
            local offs = ev.offs
            if span then
                local f = {}
                for _, p in ipairs(offs) do
                    if math.max(hi, p) - math.min(lo, p) <= span then f[#f + 1] = p end
                end
                offs = f
            end
            local room = lim - n_held
            if room >= 1 and #offs >= 1 then
                if #offs > room then offs = reduce(offs, room) end
                if #offs ~= #ev.offs then
                    stats.chord_notes = stats.chord_notes + #ev.offs - #offs
                    ev.offs = offs
                end
                break
            end
            local h = table.remove(held, 1)
            h.qn_e = ev.qn
            stats.trimmed = stats.trimmed + 1
        end
        for _, h in ipairs(held) do
            if not h.hold then h.hold = true; stats.held = stats.held + 1 end
        end
    end
    return stats
end

-- The event FixLengths measures a sustain's release gap from: the next onset, or for a
-- held note (hold) the first onset at or after its end. nil at the end of the tier.
function GenNextAfterHold(out, i)
    local ev = out[i]
    if not ev.hold then return out[i + 1] end
    for k = i + 1, #out do
        if out[k].qn >= ev.qn_e - EPS then return out[k] end
    end
    return nil
end
