-- Overdrive tab: instrument overdrive and unison planning, and the Generate action.
--
-- THE RULES (RBN/C3 "Overdrive and Big Rock Endings", checked against the reference
-- corpus - see .claude/CLAUDE_general.md, "Feature: Overdrive"):
--   * about one phrase per 40 COUNTED beats of the part's playing time, one measure long
--   * about half as many unisons as phrases; a unison is the same span on every
--     instrument (a subset without keys is allowed when keys is not playing)
--   * never two instruments sharing a bar outside a unison, never overlapping phrases
--   * nothing in the last 8 measures, no unison in the last 12, and nothing until the
--     band has played a few measures (the start keep-out)
--   * vocals are never part of a unison. Whether instrument phrases may also sit
--     under vocal overdrive is a setting (OdVocalNoGo); official charts allow it
--   * drums: no phrase in a fill's bar or starting on a fill's closing crash, and a
--     drum solo holds at most 4 phrases (2 when a unison leads into it)
--   * with `together`, a unison may take the measure before a section from the fill
--     leading into it, and prefers measures where the band plays together
--
-- The planner is pure over the model OdBuildModel returns, so tests drive it with a
-- hand-built model. Everything is in quarter notes.
--
-- Requires (globals): r, S, OD_* and Od* (overdrive_read.lua), OdBarInterest,
-- OdBandTogetherness (overdrive_interest.lua), OdPlanFills (actions_overdrive_fills.lua), OdPlanVocals
-- (actions_overdrive_vocals.lua), OdBuildOverview (actions_overdrive_validate.lua),
-- GetTempoContextBefore (helpers.lua)

-- A drum phrase in the bar before a fill stops this short of the barline, so its
-- end does not land on the fill's start (the CARV "touching" rule). A 32nd note.
local DRUM_TRIM_QN = 0.125

-- A new single is only squeezed into a gap at least this share of the ideal spacing.
local MIN_GAP_SHARE = 0.6

-- How far a single phrase may move from the middle of its gap, and what moving costs.
-- A single may wander SINGLE_REACH_DIV-th of the gap either way (at least 4 beats) to a
-- more interesting measure, paying SINGLE_SPACING_PENALTY x (distance / reach) against
-- its 0..1 interest score.
--
-- Spacing wins most ties on purpose. For single phrases the interest score barely
-- predicts official placement, while even spacing is what the doc asks for. The first
-- version (a quarter of the gap, penalty 0.15) let a section-start bonus pull a phrase
-- 3 measures off target, leaving 6.3% of gaps under 0.6x the song's own average; the
-- official charts have 3.6%. Tested over 60 reference songs, a sixth of the gap with
-- penalty 0.5 came closest (4.0%) and kept the official-measure hit rate (13.1% vs
-- 13.6%).
local SINGLE_REACH_DIV       = 6
local SINGLE_SPACING_PENALTY = 0.5

-- A phrase starts on its first gem only when that gem is within one beat of the
-- barline; see PhraseSpan.
local LATE_START_QN = 1

-- How much band togetherness counts in a unison's score, per member, against each
-- member's 0..1 interest. Tested at 0.25-5 over 60 reference songs: 2 was the best
-- exact hit rate and it levels off above it.
local TOGETHER_WEIGHT = 2

local function Median(list)
    if #list == 0 then return 0 end
    local c = {}
    for i, v in ipairs(list) do c[i] = v end
    table.sort(c)
    local m = (#c + 1) / 2
    return (c[math.floor(m)] + c[math.ceil(m)]) / 2
end

local function FirstOnsetBar(inst, nb)
    for b = 1, nb do
        if inst.onset[b] then return b end
    end
    return nil
end

-- Groups of identical spans across instruments: { span, keys = { key = true }, n }.
-- `spans_by_key` maps instrument key -> span list. A group of 3 or more is a unison;
-- a group of 2 is a unison only when those are the only instruments present.
function OdUnisonGroups(spans_by_key)
    local groups = {}
    for key, spans in pairs(spans_by_key) do
        for _, sp in ipairs(spans) do
            local hit
            for _, g in ipairs(groups) do
                if OdSameSpan(g.span, sp) then hit = g; break end
            end
            if not hit then
                hit = { span = sp, keys = {}, n = 0 }
                groups[#groups + 1] = hit
            end
            if not hit.keys[key] then hit.keys[key] = true; hit.n = hit.n + 1 end
        end
    end
    table.sort(groups, function(a, b) return a.span.s < b.span.s end)
    return groups
end

----------------------------------------------------------------------
-- Instrument planner (pure)
----------------------------------------------------------------------

-- Plan overdrive for the instruments in opts.gen.
--
-- opts:
--   gen               set of instrument keys to generate ({ guitar = true, ... })
--   beats_per_phrase  counted beats of playing time per phrase (40)
--   unison_share      unisons as a share of the median phrase count (0.5)
--   keepout_od        measures at the end with no overdrive (8)
--   keepout_unison    measures at the end with no unison (12)
--   keepout_start     measures the band plays before the first phrase may start (5),
--                     counted from the first measure ANY present instrument plays in.
--                     Official charts: median 5 (p10 2, p90 9) across 699 songs; the
--                     first version, with no such rule, put 27% of songs' first
--                     phrase in the very first playing measure against the corpus's
--                     2-14%. Joining an existing unison ignores it - matching what is
--                     already authored matters more than the lead-in
--   nogo              spans no instrument phrase may overlap (see OdVocalNoGo)
--   fills             drum fills to respect: the ones planned this run, or the existing
--                     ones when fills are not being regenerated. Not modified; a fill
--                     that gives way to a unison is returned in plan.yielded
--   together          prefer unison measures where the band plays together (below)
--
-- TOGETHER, measured over 60 reference songs: official unisons sit on the LAST MEASURE
-- BEFORE A SECTION 5.8x as often as chance (20.6% of unisons vs 3.6% of bars) - the
-- doc's "pickup, build-up to a chorus" - and where guitar and bass share rhythm and
-- contour (OdBandTogetherness, lift 1.14). Fills end on that same pre-section measure,
-- so with fills planned first the best unison spot was always taken. With `together`:
--   * a unison may take the last measure before a section when the only thing in the
--     way is the fill leading into it - that fill gives way (plan.yielded)
--   * OdBandTogetherness is added to the unison score (TOGETHER_WEIGHT)
-- Together these put 13.2% of generated unisons on an official unison measure
-- (22.5% within one measure) against 5.2% (14.5%) without, at the cost of about 11%
-- of the fills. Charters are not consistent enough for much more: a chorus with a
-- unison has one in the same spot of the next chorus only 19% of the time.
--
-- Instruments present but not in `gen` keep their existing overdrive, which acts
-- as fixed anchors: their bars are taken, and where two or more of them share an
-- identical span (an existing unison) a generated instrument joins it.
--
-- Returns { phrases = { key = { {s, e, bar, unison} } }, targets = { key = N },
--           unison_bars = { b }, unplaced = { {key, kind, bar, count} },
--           solo_trimmed = n, unison_mode = 'fresh' | 'joined' | nil,
--           yielded = { fill } }
function OdPlanInstruments(model, opts)
    local bars = model.bars
    local nb = #bars
    local last_od = nb - (opts.keepout_od or 8)
    local last_un = nb - (opts.keepout_unison or 12)
    local nogo = opts.nogo or {}
    -- A private copy: fills that give way to a unison are removed from it, so later
    -- checks (drum singles, phrase trimming) see the fills that will actually exist.
    local fills = {}
    for i, f in ipairs(opts.fills or {}) do fills[i] = f end
    local plan = { phrases = {}, targets = {}, unison_bars = {}, unplaced = {}, solo_trimmed = 0,
                   unison_mode = nil, yielded = {} }

    local gen_list, fixed_list = {}, {}
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst and inst.present then
            if opts.gen[g.key] then gen_list[#gen_list + 1] = inst
            else fixed_list[#fixed_list + 1] = inst end
        end
    end
    -- The first bar a phrase may start in: keepout_start measures after the band
    -- starts playing.
    local band_first
    for _, inst in ipairs(gen_list) do
        local f = FirstOnsetBar(inst, nb)
        if f and (not band_first or f < band_first) then band_first = f end
    end
    for _, inst in ipairs(fixed_list) do
        local f = FirstOnsetBar(inst, nb)
        if f and (not band_first or f < band_first) then band_first = f end
    end
    local first_ok = (band_first or 1) + (opts.keepout_start or 0)
    plan.first_ok = first_ok

    for _, inst in ipairs(gen_list) do
        if not inst.interest then
            inst.interest = OdBarInterest(bars, inst.events, model.section_bars)
        end
        plan.phrases[inst.key] = {}
    end
    if #gen_list == 0 then return plan end

    -- occ[b][key] = span: which instruments already have a phrase touching bar b.
    local occ = {}
    local function Occupy(key, sp)
        local a, z = OdBarsOfSpan(bars, sp.s, sp.e)
        if not a then return end
        for b = a, z do
            occ[b] = occ[b] or {}
            occ[b][key] = sp
        end
    end
    local function BarFree(b) return occ[b] == nil or next(occ[b]) == nil end
    for _, inst in ipairs(fixed_list) do
        for _, sp in ipairs(inst.od) do Occupy(inst.key, sp) end
    end

    -- A fill in this bar, or ending on its downbeat: the fill's closing crash would be
    -- the phrase's first note, and the game can then withhold the energy. `skip` is
    -- the index of a fill to ignore - one that would give way to a unison here.
    local function FillBlocks(b, skip)
        local bar = bars[b]
        for i, f in ipairs(fills) do
            if i ~= skip then
                if OdSpansOverlap(f.s, f.e, bar.qn_s, bar.qn_e) then return true end
                if OdSameQN(f.e, bar.qn_s) then return true end
            end
        end
        return false
    end

    -- With `together`: the index of the fill that would give way if a unison took bar
    -- b - only when b is the last measure before a section, the fill is the one leading
    -- into that section, and nothing else blocks the bar. Otherwise nil.
    local function YieldableFill(b)
        if not opts.together or b >= nb or not (model.section_change_bars or {})[b + 1] then return nil end
        for i, f in ipairs(fills) do
            if OdSameQN(f.e, bars[b + 1].qn_s) then
                if not FillBlocks(b, i) then return i end
                return nil
            end
        end
        return nil
    end

    local function Eligible(inst, b, last, skip)
        if b < first_ok or b > last or not inst.onset[b] then return false end
        local bar = bars[b]
        if OdAnyOverlap(nogo, bar.qn_s, bar.qn_e) then return false end
        if inst.key == 'drums' and FillBlocks(b, skip) then return false end
        return true
    end

    -- The phrase span for bar b, to the next barline. It starts on the barline, or on
    -- the first gem any member plays when the downbeat is empty and that gem comes
    -- within the first beat - the corpus puts a phrase's start exactly on its first
    -- gem. A later first gem would leave a phrase of half a measure or less, so the
    -- phrase keeps the barline instead.
    local function PhraseSpan(b, members)
        local bar = bars[b]
        local s = bar.qn_e
        local has_drums = false
        for _, inst in ipairs(members) do
            if inst.first[b] and inst.first[b] < s then s = inst.first[b] end
            if inst.key == 'drums' then has_drums = true end
        end
        if s > bar.qn_s + LATE_START_QN then s = bar.qn_s end
        local e = bar.qn_e
        if has_drums then
            for _, f in ipairs(fills) do
                if OdSameQN(f.s, bar.qn_e) then
                    e = math.max(bar.qn_e - DRUM_TRIM_QN, s + DRUM_TRIM_QN / 2)
                end
            end
        end
        return s, e
    end

    local function Add(inst, b, s, e, unison)
        local sp = { s = s, e = e, bar = b, unison = unison }
        local list = plan.phrases[inst.key]
        list[#list + 1] = sp
        Occupy(inst.key, sp)
    end

    -- Targets: the frequency rule over the bars the part is actually playing.
    for _, inst in ipairs(gen_list) do
        local beats = 0
        for b = 1, math.max(0, math.min(last_od, nb)) do
            if inst.playing[b] then beats = beats + bars[b].beats end
        end
        plan.targets[inst.key] = beats > 0
            and math.max(1, math.floor(beats / opts.beats_per_phrase + 0.5)) or 0
    end

    ------------------------------------------------------------------
    -- Unisons
    ------------------------------------------------------------------
    if #fixed_list == 0 and #gen_list >= 2 then
        -- Fresh unisons, only when every present instrument is being generated: a
        -- unison is a band-wide decision, and a kept track's phrases are not ours
        -- to line up with.
        local core = {}
        for _, inst in ipairs(gen_list) do
            if inst.key ~= 'keys' then core[#core + 1] = inst end
        end
        if #core == 0 then core = gen_list end
        local min_members = math.min(3, #gen_list)

        local counts = {}
        for _, inst in ipairs(gen_list) do counts[#counts + 1] = plan.targets[inst.key] end
        local U = math.floor((opts.unison_share or 0.5) * Median(counts) + 0.5)

        local lo = first_ok
        for _, inst in ipairs(core) do
            local f = FirstOnsetBar(inst, nb)
            if f and f > lo then lo = f end
        end
        local hi = last_un
        plan.unison_mode = 'fresh'
        -- Band togetherness as an extra unison score (see `together` above). Needs
        -- guitar and bass both present; without them the score is simply absent.
        local together
        if opts.together and model.inst.guitar.present and model.inst.bass.present then
            together = OdBandTogetherness(bars, model.inst.guitar.events,
                                          model.inst.bass.events, model.inst.drums.events)
        end
        local tw = together and TOGETHER_WEIGHT or 0
        if U > 0 and hi >= lo then
            local step = (hi - lo + 1) / U
            local reach = math.max(1, math.floor(step / 2))
            for j = 1, U do
                local center = lo + math.floor((j - 0.5) * step)
                local best, best_key, best_members, best_yield
                for b = math.max(lo, center - reach), math.min(hi, center + reach) do
                    local blocked = FillBlocks(b)
                    local yield = blocked and YieldableFill(b) or nil
                    if BarFree(b) and (not blocked or yield)
                       and not OdAnyOverlap(nogo, bars[b].qn_s, bars[b].qn_e) then
                        local members, sum, ok = {}, 0, true
                        for _, inst in ipairs(gen_list) do
                            if Eligible(inst, b, last_un, yield) then
                                members[#members + 1] = inst
                                sum = sum + (inst.interest[b] or 0)
                            elseif inst.key ~= 'keys' then
                                ok = false   -- a subset may drop keys, nothing else
                            end
                        end
                        if ok and #members >= min_members then
                            -- Togetherness is scaled by the member count so it weighs
                            -- the same against a 3-part and a 4-part interest sum.
                            local tog = together and together[b] or 0
                            local key = sum + tw * tog * #members - 0.001 * math.abs(b - center)
                            if not best or key > best_key then
                                best, best_key, best_members, best_yield = b, key, members, yield
                            end
                        end
                    end
                end
                if best then
                    if best_yield then
                        plan.yielded[#plan.yielded + 1] = fills[best_yield]
                        table.remove(fills, best_yield)
                    end
                    local s, e = PhraseSpan(best, best_members)
                    for _, inst in ipairs(best_members) do Add(inst, best, s, e, true) end
                    plan.unison_bars[#plan.unison_bars + 1] = best
                else
                    plan.unplaced[#plan.unplaced + 1] = { kind = 'unison', bar = center, count = 1 }
                end
            end
        end
    elseif #fixed_list >= 2 then
        -- Join the unisons the kept tracks already have.
        plan.unison_mode = 'joined'
        local by_key = {}
        for _, inst in ipairs(fixed_list) do by_key[inst.key] = inst.od end
        for _, g in ipairs(OdUnisonGroups(by_key)) do
            local b = OdBarAt(bars, g.span.s)
            if g.n >= 2 and b and not OdAnyOverlap(nogo, g.span.s, g.span.e) then
                local joined = false
                for _, inst in ipairs(gen_list) do
                    if inst.onset[b] then
                        Add(inst, b, g.span.s, g.span.e, true)
                        joined = true
                    end
                end
                if joined then plan.unison_bars[#plan.unison_bars + 1] = b end
            end
        end
    end

    ------------------------------------------------------------------
    -- Singles: largest gap first, in playing-beat space
    ------------------------------------------------------------------
    -- Measured in counted beats of PLAYING bars only, so a long rest does not look
    -- like a gap that needs a phrase. Each new phrase goes near the middle of the
    -- widest remaining gap, to the most interesting free bar within reach of it.
    for _, inst in ipairs(gen_list) do
        local N = plan.targets[inst.key]
        local need = N - #plan.phrases[inst.key]
        local px, x = {}, 0
        for b = 1, nb do
            px[b] = x
            if inst.playing[b] then x = x + bars[b].beats end
        end
        local X = (last_od >= 1 and last_od < nb) and px[last_od + 1] or x
        -- The usable stretch starts at the start keep-out, so the spacing is spread
        -- over the bars a phrase can actually go in.
        local X0 = (first_ok <= nb) and px[first_ok] or X
        if need > 0 and X > X0 then
            local d = (X - X0) / N
            local anchors = { X0 - d / 2, X + d / 2 }
            for _, sp in ipairs(plan.phrases[inst.key]) do
                anchors[#anchors + 1] = px[sp.bar] + bars[sp.bar].beats / 2
            end
            local blocked = {}
            while need > 0 do
                table.sort(anchors)
                local gaps = {}
                for i = 1, #anchors - 1 do
                    gaps[#gaps + 1] = { a = anchors[i], b = anchors[i + 1],
                                        len = anchors[i + 1] - anchors[i] }
                end
                table.sort(gaps, function(g1, g2) return g1.len > g2.len end)
                local placed, first_blocked = false, nil
                for _, gap in ipairs(gaps) do
                    if gap.len < d * MIN_GAP_SHARE then break end
                    local gk = ('%.4f:%.4f'):format(gap.a, gap.b)
                    if not blocked[gk] then
                        local tx = (gap.a + gap.b) / 2
                        local reach = math.max(gap.len / SINGLE_REACH_DIV, 4)
                        local best, best_key
                        for b = 1, math.max(0, last_od) do
                            local mid = px[b] + bars[b].beats / 2
                            if inst.playing[b] and math.abs(mid - tx) <= reach
                               and mid > gap.a and mid < gap.b
                               and BarFree(b) and Eligible(inst, b, last_od) then
                                local key = (inst.interest[b] or 0)
                                          - SINGLE_SPACING_PENALTY * math.abs(mid - tx) / reach
                                if not best or key > best_key then best, best_key = b, key end
                            end
                        end
                        if best then
                            local s, e = PhraseSpan(best, { inst })
                            Add(inst, best, s, e, false)
                            anchors[#anchors + 1] = px[best] + bars[best].beats / 2
                            need = need - 1
                            placed = true
                            break
                        end
                        blocked[gk] = true
                        if not first_blocked then first_blocked = tx end
                    end
                end
                if not placed then
                    -- Name the bar nearest the widest gap that could not be split.
                    local near
                    if first_blocked then
                        for b = 1, nb do
                            if px[b] + bars[b].beats > first_blocked then near = b; break end
                        end
                    end
                    plan.unplaced[#plan.unplaced + 1] =
                        { key = inst.key, kind = 'single', bar = near, count = need }
                    break
                end
            end
        end
        table.sort(plan.phrases[inst.key], function(a, b) return a.s < b.s end)
    end

    ------------------------------------------------------------------
    -- Drum solos: at most 4 phrases, 2 when a unison leads straight in
    ------------------------------------------------------------------
    -- There are no fills in a drum solo, so every phrase earned there is energy the
    -- drummer cannot deploy until it ends.
    local drums = plan.phrases.drums
    if drums then
        for _, solo in ipairs(model.drum_solos or {}) do
            local sb = OdBarAt(bars, solo.s)
            local preceded = false
            for _, sp in ipairs(drums) do
                if sp.unison and sb and sp.bar >= sb - 2 and sp.bar < sb then preceded = true end
            end
            local cap = preceded and 2 or 4
            while true do
                local inside, worst, worst_i = 0, nil, nil
                for i, sp in ipairs(drums) do
                    if OdSpansOverlap(sp.s, sp.e, solo.s, solo.e) then
                        inside = inside + 1
                        local sc = model.inst.drums.interest[sp.bar] or 0
                        if not sp.unison and (not worst or sc < worst) then worst, worst_i = sc, i end
                    end
                end
                if inside <= cap or not worst_i then break end
                table.remove(drums, worst_i)
                plan.solo_trimmed = plan.solo_trimmed + 1
            end
        end
    end
    return plan
end

----------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------

-- The take whose item covers qn, else the first. Writing to the item a phrase sits
-- in keeps it visible in that item; the first take is the fallback for a phrase
-- that falls between items.
local function TakeAtQN(takes, qn)
    local t = r.TimeMap2_QNToTime(0, qn)
    for _, tk in ipairs(takes) do
        local pos = r.GetMediaItemInfo_Value(tk.item, 'D_POSITION')
        local len = r.GetMediaItemInfo_Value(tk.item, 'D_LENGTH')
        if t >= pos - 1e-9 and t < pos + len then return tk end
    end
    return takes[1]
end

local function InsertQN(take, s, e, pitch)
    local sp = math.floor(r.MIDI_GetPPQPosFromProjQN(take, s) + 0.5)
    local ep = math.floor(r.MIDI_GetPPQPosFromProjQN(take, e) + 0.5)
    if ep <= sp then ep = sp + 1 end
    r.MIDI_InsertNote(take, false, false, sp, ep, 0, pitch, 100, false)
end

-- Delete every note with pitch in [lo, hi] across the takes, keeping any that start
-- at or after keep_from_qn (the Big Rock Ending lanes, which share the fill pitches).
-- Returns the number deleted.
local function ClearPitches(takes, lo, hi, keep_from_qn)
    local n_del = 0
    for _, tk in ipairs(takes) do
        local _, n = r.MIDI_CountEvts(tk.take)
        for i = n - 1, 0, -1 do
            local ok, _, _, sppq, _, _, p = r.MIDI_GetNote(tk.take, i)
            if ok and p >= lo and p <= hi then
                local keep = keep_from_qn
                    and r.MIDI_GetProjQNFromPPQPos(tk.take, sppq) >= keep_from_qn - OD_QN_EPS
                if not keep then
                    r.MIDI_DeleteNote(tk.take, i)
                    n_del = n_del + 1
                end
            end
        end
    end
    return n_del
end

-- Tracks a group writes to, primary first; either may be absent.
local function GroupTracks(inst)
    local out = {}
    if inst.track then out[#out + 1] = inst.track end
    if inst.mirror_track then out[#out + 1] = inst.mirror_track end
    return out
end

local function TrackName(track)
    local _, nm = r.GetTrackName(track)
    return nm
end

----------------------------------------------------------------------
-- The Generate action
----------------------------------------------------------------------

-- What the current dropdown choice and include boxes ask for.
function OdJobs()
    local choice = OD_GROUP_CHOICES[(S.od_group or 0) + 1] or OD_GROUP_CHOICES[1]
    local jobs = { inst = {}, fills = false, vocals = false, choice = choice }
    if S.od_inc_phrases then
        if choice.all then
            for _, g in ipairs(OD_INST_GROUPS) do jobs.inst[g.key] = true end
        elseif choice.inst then
            jobs.inst[choice.inst] = true
        end
    end
    jobs.fills  = S.od_inc_fills and (choice.all or choice.inst == 'drums') or false
    jobs.vocals = S.od_inc_vocals and choice.vocals == true or false
    return jobs
end

-- Spans the fill planner must keep clear of: drum phrases and every unison (the doc:
-- no unison in the same measure as a fill) that will SURVIVE this run. Fills are
-- planned before instrument overdrive, so only kept tracks' overdrive counts; a track
-- being regenerated is about to lose its phrases and gets out of the fills' way instead.
-- The spans instrument overdrive must stay clear of, from the vocal overdrive, per
-- the "Over vocal overdrive" setting:
--   0  avoid it entirely - every measure a vocal OD phrase touches
--   1  avoid only its first measure (the one the phrase starts in); a long vocal
--      phrase may be overlapped after that
--   2  overlap anywhere - what official charts do (24% of instrument phrases overlap
--      vocal OD, in 59 of 60 reference songs). The doc only forbids vocals being
--      PART of a unison, and that cannot happen: vocal OD follows the phrase
--      markers and never shares an instrument span
function OdVocalNoGo(bars, vocal_spans, mode)
    if mode == 2 then return {} end
    if mode ~= 1 then return vocal_spans or {} end
    local out = {}
    for _, v in ipairs(vocal_spans or {}) do
        local b = OdBarAt(bars, v.s)
        if b then out[#out + 1] = { s = bars[b].qn_s, e = bars[b].qn_e } end
    end
    return out
end

function OdFillAvoidSpans(model, jobs)
    local kept = {}
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst.present and not jobs.inst[g.key] then kept[g.key] = inst.od end
    end
    local out = {}
    for _, sp in ipairs(kept.drums or {}) do out[#out + 1] = sp end
    for _, g in ipairs(OdUnisonGroups(kept)) do
        if g.n >= 2 then out[#out + 1] = g.span end
    end
    return out
end

-- The drum phrases that will exist after this run, with unison flags, for working out
-- when drum overdrive can first be activated: the planned ones when drums are being
-- generated, otherwise the kept ones (a kept phrase counts as a unison when it shares
-- its span with the other parts, the same test Validate uses).
function OdDrumPhrasesForActivation(model, iplan, jobs)
    if iplan and jobs.inst.drums then return iplan.phrases.drums or {} end
    local final, n = {}, 0
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst.present then
            final[g.key] = (iplan and jobs.inst[g.key] and iplan.phrases[g.key]) or inst.od
            n = n + 1
        end
    end
    local groups = OdUnisonGroups(final)
    local out = {}
    for _, sp in ipairs(model.inst.drums.od) do
        local un = false
        for _, gr in ipairs(groups) do
            if (gr.n >= 3 or (gr.n >= 2 and gr.n == n)) and OdSameSpan(gr.span, sp) then un = true end
        end
        out[#out + 1] = { s = sp.s, e = sp.e, unison = un }
    end
    return out
end

-- mode: nil = first press (asks before replacing anything), 'replace', or 'keep'
-- (leave every track that already has notes alone and generate the rest).
function GenerateOverdrive(mode)
    S.od_pending = nil
    local model, err = OdBuildModel()
    if not model then
        S.status = 'Error'
        S.last_result = err
        return
    end
    local jobs = OdJobs()
    local notes_out = {}

    -- Drop what the project does not have.
    for _, g in ipairs(OD_INST_GROUPS) do
        if jobs.inst[g.key] and not model.inst[g.key].present then
            jobs.inst[g.key] = nil
            notes_out[#notes_out + 1] = ('%s: no %s track with MIDI - skipped.'):format(g.label, g.track)
        end
    end
    if jobs.fills and not model.inst.drums.present then
        jobs.fills = false
        notes_out[#notes_out + 1] = 'Drum fills: no PART DRUMS track with MIDI - skipped.'
    end
    if jobs.vocals and not model.vocal.present then
        jobs.vocals = false
        notes_out[#notes_out + 1] = 'Vocals: no PART VOCALS track with MIDI - skipped.'
    end

    -- What would be replaced.
    local existing = {}
    local function Note(kind, key, text, n)
        if n > 0 then existing[#existing + 1] = { kind = kind, key = key, text = text, n = n } end
    end
    for _, g in ipairs(OD_INST_GROUPS) do
        if jobs.inst[g.key] then
            local inst = model.inst[g.key]
            Note('inst', g.key, g.label .. ' overdrive',
                 #inst.od + (inst.mirror_od and #inst.mirror_od or 0))
        end
    end
    if jobs.fills then
        Note('fills', 'drums', 'drum fills', #model.fills + (model.fills_2x and #model.fills_2x or 0))
    end
    if jobs.vocals then
        Note('vocals', 'vocals', 'vocal overdrive', #model.vocal.od + #model.vocal.harm_od)
    end
    local n_jobs = (jobs.fills and 1 or 0) + (jobs.vocals and 1 or 0)
    for _ in pairs(jobs.inst) do n_jobs = n_jobs + 1 end

    if n_jobs == 0 then
        S.status = 'Nothing to generate.'
        notes_out[#notes_out + 1] = 'Tick at least one of Overdrive phrases, Drum fills or Vocal overdrive.'
        S.last_result = table.concat(notes_out, '\n')
        return
    end

    if #existing > 0 and mode == nil then
        local parts = {}
        for _, e in ipairs(existing) do parts[#parts + 1] = ('%s (%d notes)'):format(e.text, e.n) end
        S.od_pending = {
            message = 'These already contain overdrive notes:\n\n  ' .. table.concat(parts, '\n  ')
                   .. '\n\nReplace them?',
            can_keep = #existing < n_jobs,
            on_replace = function() GenerateOverdrive('replace') end,
            on_keep    = function() GenerateOverdrive('keep') end,
        }
        S.status = 'Waiting for confirmation.'
        S.last_result = nil
        return
    end
    if mode == 'keep' then
        for _, e in ipairs(existing) do
            if e.kind == 'inst' then jobs.inst[e.key] = nil
            elseif e.kind == 'fills' then jobs.fills = false
            else jobs.vocals = false end
        end
        if not (jobs.fills or jobs.vocals or next(jobs.inst)) then
            S.status = 'Nothing to generate.'
            S.last_result = 'Every selected track already has overdrive notes, and they were kept.'
            return
        end
    end

    -- Plan, least flexible first:
    --   1. vocals - tied to phrase markers and to HARM1; their spans then fence off
    --      every instrument phrase
    --   2. fills - a grid from the drum part and the sections, the order drum
    --      authoring happens in anyway
    --   3. instrument overdrive and unisons, around both
    local vplan
    if jobs.vocals then
        vplan = OdPlanVocals(model, { every = S.od_vocal_every, keepout_od = S.od_keepout_od })
    end
    local nogo = OdVocalNoGo(model.bars, vplan and vplan.phrases or model.vocal.od, S.od_vocal_overlap)

    local fplan, pacing, bpm
    if jobs.fills then
        pacing = S.od_fill_pacing
        if pacing == 0 then
            local mid = model.bars[math.max(1, #model.bars // 2)]
            bpm = GetTempoContextBefore(mid.t_s)
            pacing = OdAutoFillPacing(bpm or 120)
        end
        fplan = OdPlanFills(model, {
            pacing = pacing,
            align = S.od_fill_sections,
            keepout_end = S.od_fill_keepout_end,
            drum_od = OdFillAvoidSpans(model, jobs),
        })
    end

    local iplan
    if next(jobs.inst) then
        iplan = OdPlanInstruments(model, {
            gen = jobs.inst,
            beats_per_phrase = S.od_beats_per_phrase,
            unison_share = S.od_unison_share / 100,
            keepout_od = S.od_keepout_od,
            keepout_unison = S.od_keepout_unison,
            keepout_start = S.od_keepout_start,
            together = S.od_together,
            nogo = nogo,
            fills = fplan and fplan.fills or model.fills,
        })
    end

    -- Drop fills the drummer could never use: those before drum overdrive can first be
    -- activated. Done last, because it needs the drum phrases, which are placed after
    -- the fills.
    -- Fills that gave way to a unison on the measure before a section.
    if fplan and iplan and #iplan.yielded > 0 then
        local gone = {}
        for _, f in ipairs(iplan.yielded) do gone[f] = true end
        local kept = {}
        for _, f in ipairs(fplan.fills) do
            if not gone[f] then kept[#kept + 1] = f end
        end
        fplan.fills = kept
    end

    local early_fills = {}
    if fplan and S.od_fill_skip_early then
        local arm = OdActivationQN(OdDrumPhrasesForActivation(model, iplan, jobs))
        fplan.fills, early_fills = OdSplitEarlyFills(fplan.fills, arm)
        fplan.no_activation = arm == nil
    end

    -- Write, as one undo step.
    local written = 0
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)

    local function Prepare(track)
        local takes = OdTrackTakes(track)
        for _, tk in ipairs(takes) do
            r.MarkTrackItemsDirty(track, tk.item)   -- REQUIRED: MIDI edits do not mark the take dirty
        end
        return takes
    end

    if vplan then
        local vt = Prepare(model.vocal.track)
        ClearPitches(vt, OD_PITCH, OD_PITCH)
        local ht = model.vocal.harm_present and Prepare(model.vocal.harm_track) or nil
        if ht then ClearPitches(ht, OD_PITCH, OD_PITCH) end
        for _, ph in ipairs(vplan.phrases) do
            -- The phrase marker's own ticks, not a QN round trip: the doc requires the
            -- overdrive note and the phrase marker to line up exactly.
            r.MIDI_InsertNote(ph.take, false, false, ph.sppq, ph.eppq, 0, OD_PITCH, 100, false)
            written = written + 1
            if ht and ph.harm then
                r.MIDI_InsertNote(ph.harm.take, false, false, ph.harm.sppq, ph.harm.eppq,
                                  0, OD_PITCH, 100, false)
                written = written + 1
            end
        end
    end

    if iplan then
        for _, g in ipairs(OD_INST_GROUPS) do
            if jobs.inst[g.key] then
                for _, tr in ipairs(GroupTracks(model.inst[g.key])) do
                    local takes = Prepare(tr)
                    if #takes > 0 then
                        ClearPitches(takes, OD_PITCH, OD_PITCH)
                        for _, sp in ipairs(iplan.phrases[g.key] or {}) do
                            InsertQN(TakeAtQN(takes, sp.s).take, sp.s, sp.e, OD_PITCH)
                            written = written + 1
                        end
                    end
                end
            end
        end
    end

    if fplan then
        for _, tr in ipairs(GroupTracks(model.inst.drums)) do
            local takes = Prepare(tr)
            if #takes > 0 then
                ClearPitches(takes, OD_FILL_LO, OD_FILL_HI, model.coda_qn)
                for _, f in ipairs(fplan.fills) do
                    local tk = TakeAtQN(takes, f.s).take
                    for p = OD_FILL_LO, OD_FILL_HI do
                        InsertQN(tk, f.s, f.e, p)
                        written = written + 1
                    end
                end
            end
        end
    end

    r.Undo_EndBlock2(0, ('Generate overdrive (%d notes)'):format(written), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    -- Report.
    local lines = { 'Generated for the whole song - one undo step reverts all of it.', '' }
    if vplan then
        local where = model.vocal.harm_present and 'PART VOCALS + HARM1' or 'PART VOCALS'
        lines[#lines + 1] = ('Vocals\t%d phrases on %s (1 per %d of %d phrases)'):format(
            #vplan.phrases, where, S.od_vocal_every, vplan.candidates)
        for _, ph in ipairs(vplan.unplaced) do
            lines[#lines + 1] = ('  OD would have been generated starting at %s, but PART VOCALS and ' ..
                'HARM1 have different phrase markers there. Rock Band 3 has a visual bug in ' ..
                'harmonies if the parts differ.'):format(OdWhere(ph.s))
        end
    end
    if iplan then
        for _, g in ipairs(OD_INST_GROUPS) do
            local list = jobs.inst[g.key] and iplan.phrases[g.key]
            if list then
                local n_un = 0
                for _, sp in ipairs(list) do if sp.unison then n_un = n_un + 1 end end
                local names = {}
                for _, tr in ipairs(GroupTracks(model.inst[g.key])) do names[#names + 1] = TrackName(tr) end
                lines[#lines + 1] = ('%s\t%d phrases (target %d), %d in unisons - %s'):format(
                    g.label, #list, iplan.targets[g.key] or 0, n_un, table.concat(names, ' + '))
            end
        end
        if iplan.unison_mode == 'fresh' then
            lines[#lines + 1] = ('Unisons\t%d'):format(#iplan.unison_bars)
        elseif iplan.unison_mode == 'joined' then
            lines[#lines + 1] = ('Unisons\tjoined %d the other parts already had'):format(
                #iplan.unison_bars)
        end
        for _, u in ipairs(iplan.unplaced) do
            local g = u.key and OdInstGroup(u.key)
            local at = u.bar and model.bars[u.bar] and (' near ' .. OdWhere(model.bars[u.bar].qn_s)) or ''
            if u.kind == 'unison' then
                lines[#lines + 1] = ('  No bar where the whole band plays freely for a unison%s.'):format(at)
            else
                lines[#lines + 1] = ('  %s: %d phrase%s could not be placed%s - the bars there are taken by ' ..
                    'vocal overdrive, fills, other phrases, or the part is resting.'):format(
                    g and g.label or '?', u.count, u.count == 1 and '' or 's', at)
            end
        end
        if iplan.solo_trimmed > 0 then
            lines[#lines + 1] = ('  Drums: %d phrase%s dropped to keep drum solos within the cap.'):format(
                iplan.solo_trimmed, iplan.solo_trimmed == 1 and '' or 's')
        end
    end
    if fplan then
        local names = {}
        for _, tr in ipairs(GroupTracks(model.inst.drums)) do names[#names + 1] = TrackName(tr) end
        local how = OD_FILL_PACINGS[pacing].label
        if S.od_fill_pacing == 0 then how = how .. (', auto from %.0f BPM'):format(bpm or 120) end
        lines[#lines + 1] = ('Fills\t%d on %s (%s)'):format(#fplan.fills, table.concat(names, ' + '), how)
        local skipped = {}
        for reason, n in pairs(fplan.skipped) do skipped[#skipped + 1] = ('%d %s'):format(n, reason) end
        table.sort(skipped)
        if #skipped > 0 then
            lines[#lines + 1] = '  Skipped slots: ' .. table.concat(skipped, ', ')
        end
        if iplan and #iplan.yielded > 0 then
            lines[#lines + 1] = ('  %d fill%s gave way to a unison on the measure before a section.'):format(
                #iplan.yielded, #iplan.yielded == 1 and '' or 's')
        end
        if fplan.no_activation then
            lines[#lines + 1] = ('  No fills written: the drums never collect enough overdrive to activate ' ..
                '(2 phrases, or 1 unison). Generate drum overdrive too, or untick "Skip fills ' ..
                'before overdrive can be activated".')
        elseif #early_fills > 0 then
            lines[#lines + 1] = ('  Left out %d fill%s before drum overdrive can first be activated (%s).'):format(
                #early_fills, #early_fills == 1 and '' or 's', OdWhere(early_fills[1].s))
        end
        -- A fill followed a section start the drums do not mark: the section event may
        -- be a measure off, and moving it moves the fill with it.
        local sec_name = {}
        for _, sec in ipairs(model.sections) do if sec.bar then sec_name[sec.bar] = sec.name end end
        for _, f in ipairs(fplan.fills) do
            if f.crash_near then
                lines[#lines + 1] = ('  Fill ends at the [prc_%s] start at %s, but the drums crash at %s ' ..
                    'instead - that section event may be a measure off. Move it and generate again ' ..
                    'to move the fill.'):format(sec_name[f.bar] or '?', OdWhere(f.e),
                    OdWhere(model.bars[f.crash_near].qn_s))
            end
        end
    end
    if model.coda_qn then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'A [coda] is present: nothing was placed in the Big Rock Ending, and its lanes were left alone.'
    end
    if #notes_out > 0 then
        lines[#lines + 1] = ''
        for _, n in ipairs(notes_out) do lines[#lines + 1] = n end
    end
    S.last_result = table.concat(lines, '\n')
    S.status = ('Overdrive generated (%d notes).'):format(written)

    local fresh = OdBuildModel()
    S.od_overview = fresh and OdBuildOverview(fresh, S.od_keepout_od) or nil
end
