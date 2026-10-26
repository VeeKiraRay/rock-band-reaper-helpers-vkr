-- Overdrive tab: drum fill planning.
--
-- A drum fill (120-124, all five lanes) is where the drummer can deploy overdrive.
-- The RBN drum authoring doc's pacing: a 1-measure fill every 4 bars for most songs,
-- 2 measures every 8 when the song is very fast, half a measure every 2 when it is
-- very slow. Fills end exactly on the barline where the crash lands - never past it,
-- which "ruins the fill" - and should end at a section change rather than keep to the
-- grid blindly (a verse with 2 extra bars gets its fill into the chorus).
--
-- The reference corpus agrees: median fill 4 beats, 93% end on a barline, median
-- spacing 4 bars.
--
-- Pure over the model from OdBuildModel.
-- Requires (globals): OD_QN_EPS, OdAnyOverlap, OdSpansOverlap, OdSameQN, OdBarAt,
-- OdQNToSec (overdrive_read.lua)

OD_FILL_PACINGS = {
    [1] = { label = 'Half bar every 2 bars', every = 2, len = 0.5 },
    [2] = { label = '1 bar every 4 bars',    every = 4, len = 1   },
    [3] = { label = '2 bars every 8 bars',   every = 8, len = 2   },
}

-- Magma refuses to build a song when a fill starts less than 2.5 s after the previous
-- fill ends ("Drum fill ... too close ... Must be 2.5 sec between drum fills").
OD_FILL_MIN_GAP_SEC = 2.5

-- Tempo threshold for Auto's half-bar fills. The doc says "very slow"; this is where
-- a one-bar fill stops fitting comfortably.
--
-- No fast threshold: the doc's "2 measures every 8 when very fast" is not what
-- official charts do. Over the RB3 DLC (591 songs), fills at 170+ BPM are one bar
-- long 91-98% of the time and 2 bars ~0%, and 69-82% come every 4 bars - the same
-- as at 120-170 BPM. "2 bars every 8" stays available as a manual choice.
local SLOW_BPM = 75

function OdAutoFillPacing(bpm)
    if bpm <= SLOW_BPM then return 1 end
    return 2
end

-- Plan fills for PART DRUMS.
--
-- opts:
--   pacing          1..3, an OD_FILL_PACINGS index
--   align           end a fill on a [prc_*] section change within reach of the grid
--                   slot, or, when there is none, on a drum crash; off = the plain grid.
--                   Only a real change counts (model.section_change_bars): chorus_1a
--                   -> chorus_1b is one section split for practice, not a change
--   keepout_end     a fill's crash must land at least this many measures before the
--                   drums' last measure (2). Official charts: the last fill lands a
--                   median 4 measures before it; on the final measure itself in 1%
--                   (RB3 DLC) / 0% (RBN) of songs, within 2 measures in 25% / 6%
--   drum_od         spans to keep clear of: drum phrases and every unison that
--                   will still be there afterwards (kept, not regenerated)
--
-- A slot is skipped, not moved, when it would:
--   * share a bar with, or touch, overdrive in the spans given (the doc's "no drum
--     overdrive in a fill's bar", the CARV "touching" rule, and the no-energy bug
--     when a phrase starts on the fill's crash)
--   * fall in a drum solo (no fills there) or over a drum roll
--   * lead into a bar where the drums do not come back in (the fill would waste
--     the drummer's overdrive on a rest)
--   * start less than OD_FILL_MIN_GAP_SEC after the previous fill ends (Magma error)
-- Skipping keeps the grid: the next fill is still counted from where this one would
-- have ended, so one blocked slot does not shift every fill after it.
--
-- THE PACING IS A MINIMUM. Two fills never end closer than `every` bars apart (user
-- rule). A section change closer than that to the previous fill still gets its fill,
-- and the previous fill is removed instead - the section is where the drummer should
-- be able to deploy, and a gap of 6 or 7 bars to the fill before is fine. A previous
-- fill that itself leads into a section change is kept, and the closer section gets
-- none. Before this rule the alignment let a fill end half the pacing after the
-- previous one, which with 2-bar fills at 193 BPM left 2.49 s between them.
--
-- FILLS ARE PLANNED BEFORE INSTRUMENT OVERDRIVE, the order drum authoring happens in
-- anyway. The instrument planner then keeps drum phrases and unisons out of fill bars
-- and off their crashes, and ends a drum phrase short of a fill that follows it.
-- Planned the other way round, every drum phrase knocked out one or two fill slots:
-- run over 60 reference songs, that dropped 30% of the fills.
--
-- ONE EXCEPTION: with "Prefer measures where the band plays together", a unison may
-- take the last measure before a section, and the fill leading into that section
-- gives way (OdPlanInstruments, plan.yielded). That measure is where official charts
-- put unisons most often, and the grid always gives it to a fill first.
--
-- Returns { fills = { {s, e, bar, crash_near} }, skipped = { reason = count } }.
-- crash_near is set when the fill followed a section start whose downbeat has no
-- crash while the neighbouring downbeat does - the bar of that crash, for the report.
function OdPlanFills(model, opts)
    local bars, nb = model.bars, #model.bars
    local drums = model.inst.drums
    local P = OD_FILL_PACINGS[opts.pacing] or OD_FILL_PACINGS[2]
    local plan = { fills = {}, skipped = {} }
    if not (drums and drums.present) then return plan end

    local first
    for b = 1, nb do
        if drums.onset[b] then first = b; break end
    end
    if not first then return plan end

    -- The drums' last measure with a gem: fills landing within keepout_end measures of
    -- it only lead into the final hit, where overdrive has nothing left to do.
    local last_drum = first
    for b = nb, first, -1 do
        if drums.onset[b] then last_drum = b; break end
    end

    local section_bars = model.section_change_bars or {}
    local all_starts = model.section_bars or {}   -- subsections too
    local min_gap = math.max(2, math.ceil(P.every / 2))   -- earliest crash, after a skipped slot
    local len_bars = math.max(1, math.ceil(P.len))
    local function Skip(reason)
        plan.skipped[reason] = (plan.skipped[reason] or 0) + 1
    end

    local crash_bars = model.crash_bars or {}

    -- A fill "ends at bar e": it finishes on bar e's downbeat, where the crash is.
    local prev = first
    while true do
        local e = prev + P.every
        local last = plan.fills[#plan.fills]
        -- No fill ends closer than `every` bars after the last kept one - except at a
        -- section change, where the last one gives way (see THE PACING IS A MINIMUM).
        local min_e = last and last.bar + P.every or -math.huge
        local crash_near   -- a crash beside a section start that has none of its own
        local at_section
        if opts.align then
            -- SECTIONS FIRST, CRASHES AS THE FALLBACK. Within reach of the grid slot, a
            -- [prc_*] section change moves the fill. Only when no section is in reach
            -- does a drum crash (nearest the slot first) move it.
            --
            -- Measured against 60 reference songs: sections first puts 76% of fills
            -- where the official fill ends; crashes first, 61%. Drummers crash in
            -- plenty of places that are not phrase starts, and a crash inside a phrase
            -- pulls the fill off a correct section. Where the two disagreed, the
            -- official fill followed the section 32 times and the crash 10 times.
            --
            -- A crash still earns its keep as a CHECK. A section start with no crash
            -- of its own but one on the neighbouring downbeat is reported: that
            -- usually means the section event is a measure off (placed by the vocals
            -- rather than the band), and moving it moves the fill with it.
            --
            -- A SUBSECTION (chorus_1a -> chorus_1b) still lines a fill up, but only at
            -- the full pacing or later - it never replaces the last fill. Official
            -- charters often put a fill into one: over the RB3 DLC (hold-out excluded),
            -- ignoring subsections entirely matched 76.0% of official fill ends, this
            -- 77.1%, and letting them replace fills like a real change 78.2%.
            local hi_b = prev + P.every + 2
            -- A section change may replace the last fill, unless that one leads into a
            -- section change itself.
            local sec_lo = prev + 1
            if last and last.section then sec_lo = math.max(sec_lo, min_e) end
            local sec_b
            for b = sec_lo, hi_b do
                if section_bars[b] or (all_starts[b] and b >= min_e) then sec_b = b; break end
            end
            if sec_b then
                e, at_section = sec_b, section_bars[sec_b] or nil
                if not crash_bars[sec_b] then
                    for _, c in ipairs({ sec_b + 1, sec_b - 1 }) do
                        if not crash_near and crash_bars[c] then crash_near = c end
                    end
                end
            else
                local lo_b = math.max(prev + min_gap, min_e)
                for d = 0, P.every do
                    local hit
                    for _, b in ipairs(d == 0 and { e } or { e - d, e + d }) do
                        if not hit and b >= lo_b and b <= hi_b and crash_bars[b] then hit = b end
                    end
                    if hit then e = hit; break end
                end
            end
        end
        -- Bar e must exist inside the song: the crash has to land somewhere, and never
        -- in a Big Rock Ending (the model's bars stop at the coda).
        if e > nb then break end

        local s_qn
        if P.len < 1 then
            local bb = bars[e - 1]
            s_qn = bb.qn_s + (bb.qn_e - bb.qn_s) * (1 - P.len)
        else
            s_qn = bars[math.max(1, e - len_bars)].qn_s
        end
        local e_qn = bars[e].qn_s
        local fill_bar_s = bars[OdBarAt(bars, s_qn) or (e - 1)].qn_s

        local reason
        if e - len_bars < first then
            reason = 'before the drums start'
        elseif OdAnyOverlap(model.drum_solos, s_qn, e_qn) then
            reason = 'in a drum solo'
        elseif OdAnyOverlap(model.rolls, s_qn, e_qn) then
            reason = 'over a drum roll'
        elseif not drums.onset[e] then
            reason = 'drums rest after it'
        elseif last_drum - e < (opts.keepout_end or 0) then
            reason = 'too close to the last drum note'
        else
            for _, od in ipairs(opts.drum_od or {}) do
                if OdSpansOverlap(od.s, od.e, fill_bar_s, e_qn)
                   or OdSameQN(od.s, e_qn) or OdSameQN(od.e, s_qn) then
                    reason = 'next to kept overdrive'
                    break
                end
            end
        end
        -- The fill this one would follow: the last kept fill, or the one before it
        -- when this section fill replaces it.
        local replaces = not reason and last and e < min_e
        local before = replaces and plan.fills[#plan.fills - 1] or last
        if not reason and before
           and OdQNToSec(bars, s_qn) - OdQNToSec(bars, before.e) < OD_FILL_MIN_GAP_SEC - 1e-3 then
            reason = ('under %.1f s after the previous fill'):format(OD_FILL_MIN_GAP_SEC)
        end
        if reason then
            Skip(reason)
        else
            if replaces then
                plan.fills[#plan.fills] = nil
                Skip('gave way to a fill into a section change')
            end
            plan.fills[#plan.fills + 1] = { s = s_qn, e = e_qn, bar = e, crash_near = crash_near,
                                            section = at_section }
        end
        prev = e
    end
    return plan
end

----------------------------------------------------------------------
-- Fills before overdrive can be activated
----------------------------------------------------------------------
-- A fill is where the drummer deploys overdrive, so a fill before the drummer can
-- possibly have enough overdrive is never usable. The docs never mention a use for
-- one. The reference charts are split: official RB3 DLC leaves one in a little over
-- half its songs (6% of all fills), RBN charts mostly do not (1.6%). Removing them is
-- the default, with an option to keep them.
--
-- ACTIVATION: two single drum phrases, or one unison, which counts double.

-- End of the drum phrase that makes activation possible, or nil when the drums never
-- collect enough. drum_phrases: sorted { s, e, unison }.
function OdActivationQN(drum_phrases)
    local count = 0
    for _, sp in ipairs(drum_phrases) do
        count = count + (sp.unison and 2 or 1)
        if count >= 2 then return sp.e end
    end
    return nil
end

-- Split fills into those that can be used and those that start before activation.
-- With no activation point at all, every fill is early. Returns kept, early.
function OdSplitEarlyFills(fills, arm_qn)
    local kept, early = {}, {}
    for _, f in ipairs(fills) do
        if arm_qn and f.s >= arm_qn - OD_QN_EPS then kept[#kept + 1] = f
        else early[#early + 1] = f end
    end
    return kept, early
end
