-- Difficulty > Generate: the reduction planner for Pro Keys. Builds one tier from the
-- tier above it.
--
-- PURE: no r, no S. Load after difficulty_generate_rhythm.lua. Shared with the offline
-- evaluation like the 5-lane planner.
--
-- Input event:  { qn, qn_e, offs = { MIDI pitches 48-72, ascending }, bpm, down, bar_qn,
--   bar_len, pulse } - the 5-lane planner's event with real pitches in offs (the action reads
--   Pro Keys with a range low of 0). Output events have the same shape, so the next tier
--   of a chain is built from them.
--
-- Which onsets survive is Gen5SelectOnsets - the same rhythm as Guitar, Bass and Keys.
-- What this file adds is pitch (the sources and numbers: docs/difficulty_reduction.md,
-- "Pro Keys"):
--   - Chords lose notes from the BOTTOM - the opposite of 5-lane Easy, which keeps the
--     lowest gem.
--   - Hard keeps Expert's pitches and its lane shifts, dropping the ones it no longer
--     needs, except the first.
--   - Medium and Easy show one window for the whole song. Medium keeps Hard's window when
--     Hard shows one window all song; otherwise the best fit. Easy keeps Medium's. Notes
--     outside it move by whole octaves; notes inside never move.
--   - Sustains: Hard 1/16 before a simple transition, 1/8 otherwise; Medium and Easy a
--     quarter. A sustain cut under 3/16 becomes a 1/16 note ("stubby").
--   - Interval jumps over the doc's limits are NOT fixed; Validate lists them as advisories.
--
-- Requires (globals, read at call time): PK_MAX_CHORD, PK_MAX_SPAN (actions_difficulty.lua),
--   Gen5SelectOnsets (difficulty_generate_rhythm.lua), GenPlanOverlaps / GenNextAfterHold
--   (difficulty_generate_overlaps.lua).

-- Lane-shift marker pitch -> the 10 white keys it shows (lo..hi). The RBN doc's six.
GEN_PK_WINDOWS = {
    [0] = { lo = 48, hi = 64 },   -- C2-E3
    [2] = { lo = 50, hi = 65 },   -- D2-F3
    [4] = { lo = 52, hi = 67 },   -- E2-G3
    [5] = { lo = 53, hi = 69 },   -- F2-A3
    [7] = { lo = 55, hi = 71 },   -- G2-B3
    [9] = { lo = 57, hi = 72 },   -- A2-C4
}
-- Tie-break when two windows fit equally: the doc's preferred C, F and A ranges, then E
-- ("the most common" alternative), then D and G.
local WINDOW_ORDER = { 0, 5, 9, 4, 2, 7 }
local PK_LO, PK_HI = 48, 72

local SUSTAIN_QN = GEN5_SUSTAIN_QN
local MIN_LEN_QN = GEN5_MIN_LEN_QN
local EPS        = GEN5_EPS
local STUB_QN    = 0.75    -- a sustain cut shorter than 3/16 note is "stubby" (RBN doc)
local PLAIN_QN   = 0.25    -- ... and becomes a 1/16 note

local function Copy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    return out
end

-- Reduce a chord (ascending pitches) to tier dl: keep the top note, then add notes
-- downward while the chord has room and stays within the tier's span. max_n: optional,
-- fewer notes than the tier allows (an onset under held notes, GenPlanOverlaps).
function GenPKReduceChord(pitches, dl, max_n)
    local span = PK_MAX_SPAN[dl] or 0
    max_n = math.min(max_n or math.huge, PK_MAX_CHORD[dl] or 1)
    if #pitches <= max_n and (#pitches < 2 or pitches[#pitches] - pitches[1] <= span) then
        return Copy(pitches)
    end
    local top = pitches[#pitches]
    local kept = { top }
    for i = #pitches - 1, 1, -1 do
        if #kept >= max_n then break end
        if top - pitches[i] <= span then table.insert(kept, 1, pitches[i]) end
    end
    return kept
end

-- The window marker (0-9) that holds the most of the notes in events; ties go to
-- `prefer` (the upper tier's own window), then WINDOW_ORDER.
function GenPKBestWindow(events, prefer)
    local best, best_n
    local order = prefer and { prefer } or {}
    for _, w in ipairs(WINDOW_ORDER) do if w ~= prefer then order[#order + 1] = w end end
    for _, w in ipairs(order) do
        local win, n = GEN_PK_WINDOWS[w], 0
        for _, ev in ipairs(events) do
            for _, p in ipairs(ev.offs) do
                if p >= win.lo and p <= win.hi then n = n + 1 end
            end
        end
        if not best_n or n > best_n then best, best_n = w, n end
    end
    return best
end

-- The upper tier's window when Medium/Easy simply keep it: the upper tier shows ONE window
-- for the whole song (every lane shift the same). The charter chose it, so it stays, a
-- non-preferred one too; Easy keeps Medium's. Notes outside fold by octaves. nil when the
-- upper tier shows several windows: the best fit decides.
function GenPKUpperWindow(shifts)
    local w
    for _, sh in ipairs(shifts or {}) do
        if w and sh.pitch ~= w then return nil end
        w = sh.pitch
    end
    return w and GEN_PK_WINDOWS[w] and w or nil
end

-- Move each event into window w by whole octaves. A note or chord that fits stays where it
-- is, so the same upper note always becomes the same note here: choosing the octave
-- nearest the previous note moved notes that already fit and left one D3 an octave above
-- every other D. One that does not fit moves
-- as a whole by the smallest number of octaves that fits; a chord that fits no whole
-- placement folds note by note and is reduced again. Returns how many events changed.
local function FitWindow(out, w, dl)
    local win, n = GEN_PK_WINDOWS[w], 0
    for _, ev in ipairs(out) do
        local orig = table.concat(ev.offs, ',')
        local best
        for _, k in ipairs({ 0, -12, 12, -24, 24 }) do
            local ok = true
            for _, p in ipairs(ev.offs) do
                local q = p + k
                if q < win.lo or q > win.hi then ok = false; break end
            end
            if ok then
                best = {}
                for i, p in ipairs(ev.offs) do best[i] = p + k end
                break
            end
        end
        if not best then
            local seen, folded = {}, {}
            for _, p in ipairs(ev.offs) do
                local q = p
                while q > win.hi do q = q - 12 end
                while q < win.lo do q = q + 12 end
                if q <= win.hi and not seen[q] then seen[q] = true; folded[#folded + 1] = q end
            end
            table.sort(folded)
            best = GenPKReduceChord(folded, dl)
        end
        ev.offs = best
        if table.concat(best, ',') ~= orig then n = n + 1 end
    end
    return n
end

-- Hard keeps Expert's lane shifts, less the ones it no longer needs: a shift whose notes
-- (up to the next shift) all fit the window already showing, or that shows the same
-- window again. The first shift always stays. shifts: { { qn, qn_e, pitch }... } sorted.
-- Returns (kept shifts, how many were dropped).
local function KeepNeededShifts(shifts, out)
    if #shifts == 0 then return {}, 0 end
    local kept, dropped = { shifts[1] }, 0
    local cur = shifts[1].pitch
    for k = 2, #shifts do
        local sh, nx = shifts[k], shifts[k + 1]
        local needed = sh.pitch ~= cur
        if needed and GEN_PK_WINDOWS[cur] then
            local win = GEN_PK_WINDOWS[cur]
            needed = false
            for _, ev in ipairs(out) do
                if ev.qn >= sh.qn - EPS and (not nx or ev.qn < nx.qn - EPS) then
                    for _, p in ipairs(ev.offs) do
                        if p < win.lo or p > win.hi then needed = true end
                    end
                end
            end
        end
        if needed then
            kept[#kept + 1] = sh
            cur = sh.pitch
        else
            dropped = dropped + 1
        end
    end
    return kept, dropped
end

-- Simple transition (RBN doc, as CheckSustainGaps reads it): single to single, a single
-- into a chord holding it or out of one, or a chord repeated exactly.
local function SimpleTransition(a, b)
    if #a == 1 and #b == 1 then return true end
    if #a == 1 or #b == 1 then
        local one, many = (#a == 1) and a[1] or b[1], (#a == 1) and b or a
        for _, p in ipairs(many) do if p == one then return true end end
        return false
    end
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Gap a sustain leaves before the next onset on tier dl.
local function ReleaseGap(dl, ev, nx)
    if dl == 'M' or dl == 'E' then return 1.0 end
    return SimpleTransition(ev.offs, nx.offs) and 0.25 or 0.5
end

-- Sustains leave the tier's gap; one cut shorter than 3/16 becomes a 1/16 note. No note
-- runs into the next onset, except a sustain GenPlanOverlaps holds over later onsets
-- (hold): its gap is measured from the first onset after it ends. Returns (shortened, cut).
local function FixLengths(dl, out)
    local shortened, cut = 0, 0
    for i, ev in ipairs(out) do
        local first = out[i + 1]
        local nx = GenNextAfterHold(out, i)
        -- A held note pulled back can end at or just after a note it was held over: then
        -- that note is the one after its end, and the gap is measured again.
        while nx and ev.qn_e - ev.qn >= SUSTAIN_QN - EPS do
            local limit = nx.qn - ReleaseGap(dl, ev, nx)
            -- Not EPS: Validate forgives only 5% of a 1/16 gap (0.0125 QN), and Expert
            -- sometimes leaves 0.23 QN, which Hard keeps unless it is shortened here.
            -- Positions are snapped to 1/960 QN, so there is no float noise to absorb.
            if ev.qn_e <= limit + 1e-3 then break end
            ev.qn_e = limit
            shortened = shortened + 1
            if ev.qn_e - ev.qn < STUB_QN - EPS then
                ev.qn_e = ev.qn + PLAIN_QN
                cut = cut + 1
                break
            end
            local again = GenNextAfterHold(out, i)
            if again == nx then break end
            nx = again
        end
        if ev.qn_e - ev.qn < MIN_LEN_QN then ev.qn_e = ev.qn + MIN_LEN_QN end
        -- A held sustain stops only for the first onset after its end (nil: none follows).
        local stop = first
        if ev.hold and ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then stop = nx end
        if stop and ev.qn_e > stop.qn - EPS / 2 then
            ev.qn_e = math.max(ev.qn + MIN_LEN_QN * 0.6, stop.qn - EPS / 2)
        end
    end
    return shortened, cut
end

-- True when a generated tier is the upper tier as it is: every onset, pitch and length
-- (within 1/96 QN). Happens on Hard when Expert is already simple.
function GenPKSameAsUpper(out, upper)
    if #out ~= #upper then return false end
    for i, ev in ipairs(out) do
        local up = upper[i]
        if math.abs(ev.qn - up.qn) > 0.01 or math.abs(ev.qn_e - up.qn_e) > 0.01
           or table.concat(ev.offs, ',') ~= table.concat(up.offs, ',') then
            return false
        end
    end
    return true
end

-- Pull every sustain back (the "Shorten sustains" answer when Hard would equal Expert): by
-- a 1/16 before a simple transition (or at a phrase end), by a 1/8 otherwise. One left
-- shorter than 3/16 becomes a 1/16 note. Returns (pulled, cut).
local function PullBackSustains(out)
    local pulled, cut = 0, 0
    for i, ev in ipairs(out) do
        if ev.qn_e - ev.qn >= SUSTAIN_QN - EPS then
            local nx = out[i + 1]
            local step = (not nx or SimpleTransition(ev.offs, nx.offs)) and 0.25 or 0.5
            ev.qn_e = ev.qn_e - step
            pulled = pulled + 1
            if ev.qn_e - ev.qn < STUB_QN - EPS then
                ev.qn_e = ev.qn + PLAIN_QN
                cut = cut + 1
            end
        end
    end
    return pulled, cut
end

-- Build Pro Keys tier dl ('H', 'M' or 'E') from the tier above it.
--   events - the upper tier (see the top of this file), sorted by qn
--   opts   - Gen5PlanTier's busy_drop / busy_ref / rhythm_ref, plus
--            shifts: the upper tier's lane-shift markers { { qn, qn_e, pitch }... };
--            window: Medium/Easy only, the marker to use (a time-selection run keeps the
--              target's existing window); unset = the upper tier's single window
--              (GenPKUpperWindow), else the best fit;
--            pull_back: Hard only, pull every sustain back (PullBackSustains) - the
--              user's answer when Hard would otherwise equal Expert.
-- Returns (out_events, log): Gen5SelectOnsets' rhythm fields plus upper, kept, removed,
--   chords_reduced, shortened, cut, window (M/E), folded (M/E: events moved by octaves),
--   shifts (the tier's lane-shift markers to write), shifts_dropped (H).
function GenPKPlanTier(dl, events, opts)
    opts = opts or {}
    local log = { upper = #events, kept = 0, removed = 0, chords_reduced = 0,
                  recolored = 0, shortened = 0, cut = 0, guided = false, color_fallback = false,
                  folded = 0, shifts_dropped = 0 }

    local keep
    events, keep = Gen5SelectOnsets('pk', dl, events, opts, log)

    local out = {}
    for i, ev in ipairs(events) do
        if keep[i] then
            local offs = GenPKReduceChord(ev.offs, dl)
            if #offs ~= #ev.offs then log.chords_reduced = log.chords_reduced + 1 end
            out[#out + 1] = { qn = ev.qn, qn_e = ev.qn_e, qn_e_full = ev.qn_e_full or ev.qn_e, offs = offs,
                              bpm = ev.bpm, down = ev.down, bar_qn = ev.bar_qn, bar_len = ev.bar_len, pulse = ev.pulse,
                              rewritten = ev.retimed or ev.joined, beat_qn = ev.beat_qn }
        end
    end
    log.kept    = #out
    log.removed = log.upper - #out

    local shifts = opts.shifts or {}
    if dl == 'H' and #shifts > 0 then
        log.shifts, log.shifts_dropped = KeepNeededShifts(shifts, out)
    elseif dl == 'H' and #out > 0 then
        -- Expert has no lane shift at all (Validate flags it there too). Every tier needs
        -- one before its first note, so Hard gets the best-fit window there.
        local w = GenPKBestWindow(out)
        log.shifts = { { qn = out[1].qn, qn_e = out[1].qn + 0.25, pitch = w } }
        log.shift_added = true
    elseif #out > 0 then
        -- One window, set once before the first note: at the upper tier's first marker
        -- when that comes before the first note, else on the first note.
        local w = opts.window or GenPKUpperWindow(shifts) or GenPKBestWindow(out)
        log.window = w
        log.folded = FitWindow(out, w, dl)
        local first = shifts[1]
        local at = (first and first.qn <= out[1].qn + EPS) and first.qn or out[1].qn
        log.shifts = { { qn = at, qn_e = at + ((first and first.qn_e - first.qn) or 0.25), pitch = w } }
    else
        log.shifts = {}
    end
    -- Expert's notes are 48-72 and every window lies inside that range, so nothing here
    -- leaves the playable keys; a stray note outside it is dropped rather than written.
    for _, ev in ipairs(out) do
        local inside = {}
        for _, p in ipairs(ev.offs) do if p >= PK_LO and p <= PK_HI then inside[#inside + 1] = p end end
        ev.offs = inside
    end
    for i = #out, 1, -1 do if #out[i].offs == 0 then table.remove(out, i) end end
    log.kept, log.removed = #out, log.upper - #out

    -- Notes Expert holds while later notes start keep sounding within the docs' limits
    -- (GenPlanOverlaps); after the window fit, so the octave check sees the final pitches.
    log.overlaps = GenPlanOverlaps('pk', dl, out, function(offs, n) return GenPKReduceChord(offs, dl, n) end,
        function(h, ev) return ReleaseGap(dl, h, ev) end)
    log.shortened, log.cut = FixLengths(dl, out)
    if dl == 'H' and opts.pull_back then log.pulled, log.pull_cut = PullBackSustains(out) end
    return out, log
end
