-- Overdrive tab: read-only validation and the overview strip's data.
--
-- Checks authored overdrive, unisons, drum fills and vocal overdrive against the RBN
-- rules the generator follows (see actions_overdrive.lua). Never writes and creates no
-- undo point. Errors are the rules whose breach the docs tie to a game bug or to the
-- chart not working (overdrive overlapping a fill, vocal overdrive off its phrase
-- marker, HARM1 not matching PART VOCALS, mismatched mirror tracks). Everything else is
-- a warning, including two rules the docs state firmly but official charts break often
-- enough that an error would be noise: measured over the reference corpus, a drum
-- phrase ending exactly where a fill starts (the CARV "touching" rule) and one starting
-- on a fill's crash each turn up in 3-8% of fills, community RBN charts included.
--
-- OdValidateModel is pure over the model from OdBuildModel.
-- Requires (globals): r, S, OD_* and Od* (overdrive_read.lua), OdUnisonGroups
-- (actions_overdrive.lua), OdActivationQN / OdSplitEarlyFills (actions_overdrive_fills.lua)

local LIST_MAX = 12   -- per category; a broken chart must not dump hundreds of lines

-- Counted beats of the bars an instrument plays in, up to bar `last`.
local function PlayingBeats(model, inst, last)
    local beats = 0
    for b = 1, math.min(last, #model.bars) do
        if inst.playing[b] then beats = beats + model.bars[b].beats end
    end
    return beats
end

-- Where two span lists first differ, as a QN position, or nil when they match.
local function FirstMismatch(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i], b[i]
        if not x or not y or not OdSameSpan(x, y) then
            if x and y then return math.min(x.s, y.s) end
            return (x or y).s
        end
    end
    return nil
end

local function BarLenAt(model, qn)
    local b = OdBarAt(model.bars, qn)
    local bar = model.bars[b or 1]
    return bar.qn_e - bar.qn_s
end

-- A group of identical spans counts as a unison when three or more instruments
-- share it, or when two do and those are the only instruments in the song.
local function IsUnison(group, n_present)
    return group.n >= 3 or (group.n >= 2 and group.n == n_present)
end

-- opts: beats_per_phrase, unison_share (0..1), keepout_od, keepout_unison, keepout_start
-- Returns { errors = {}, warnings = {}, summary = {} } of display lines, plus
-- n_errors / n_warnings - the true totals, including lines the per-category cap left
-- out of the lists.
function OdValidateModel(model, opts)
    local rep = { errors = {}, warnings = {}, summary = {}, n_errors = 0, n_warnings = 0 }
    local n_err, n_warn = {}, {}
    local function Add(list, counts, cat, msg)
        counts[cat] = (counts[cat] or 0) + 1
        if counts[cat] <= LIST_MAX then
            list[#list + 1] = msg
        elseif counts[cat] == LIST_MAX + 1 then
            list[#list + 1] = ('  ... more of the same (%s)'):format(cat)
        end
    end
    local function Err(cat, msg)
        rep.n_errors = rep.n_errors + 1
        Add(rep.errors, n_err, cat, msg)
    end
    local function Warn(cat, msg)
        rep.n_warnings = rep.n_warnings + 1
        Add(rep.warnings, n_warn, cat, msg)
    end

    local bars, nb = model.bars, #model.bars
    local ko_od, ko_un = opts.keepout_od or 8, opts.keepout_unison or 12
    local last_od_qn = bars[math.max(1, nb - ko_od)].qn_e
    local last_un_qn = bars[math.max(1, nb - ko_un)].qn_e
    local v = model.vocal

    local final, n_present = {}, 0
    for _, g in ipairs(OD_INST_GROUPS) do
        if model.inst[g.key].present then
            final[g.key] = model.inst[g.key].od
            n_present = n_present + 1
        end
    end
    local groups = OdUnisonGroups(final)
    local unison_groups = {}
    for _, gr in ipairs(groups) do
        if IsUnison(gr, n_present) then unison_groups[#unison_groups + 1] = gr end
    end
    local function InUnison(sp)
        for _, gr in ipairs(unison_groups) do
            if OdSameSpan(gr.span, sp) then return true end
        end
        return false
    end

    ------------------------------------------------------------------
    -- Per instrument
    ------------------------------------------------------------------
    local counts, under_vocal = {}, 0
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst.present then
            local list = inst.od
            local beats = PlayingBeats(model, inst, nb - ko_od)
            local target = beats > 0
                and math.max(1, math.floor(beats / opts.beats_per_phrase + 0.5)) or 0
            counts[#counts + 1] = target
            local n_un, gap_max, gap_at = 0, 0, nil
            local playing_bars = 0
            for b = 1, nb do if inst.playing[b] then playing_bars = playing_bars + 1 end end
            for i, sp in ipairs(list) do
                if InUnison(sp) then n_un = n_un + 1 end
                if i > 1 then
                    local gb = (OdBarAt(bars, sp.s) or nb) - (OdBarAt(bars, list[i - 1].s) or 1)
                    if gb > gap_max then gap_max, gap_at = gb, list[i - 1].e end
                end
                local len = (sp.e - sp.s) / BarLenAt(model, sp.s)
                if len < 0.5 then
                    Warn('short', ('%s: phrase at %s is under half a measure long.'):format(g.label, OdWhere(sp.s)))
                elseif len > 2 + 1e-6 then
                    Warn('long', ('%s: phrase at %s is %.1f measures long (the guideline is one).'):format(
                        g.label, OdWhere(sp.s), len))
                end
                if model.coda_qn and sp.e > model.coda_qn + OD_QN_EPS then
                    Err('bre', ('%s: phrase at %s runs into the Big Rock Ending.'):format(g.label, OdWhere(sp.s)))
                elseif sp.e > last_od_qn + OD_QN_EPS then
                    Warn('late', ('%s: phrase at %s is in the last %d measures.'):format(
                        g.label, OdWhere(sp.s), ko_od))
                end
                -- Counted, not listed: official charts overlap vocal overdrive routinely
                -- (about 9 phrases per song across the reference corpus). The
                -- generator avoids it by choice, so it is worth knowing, not flagging.
                if OdAnyOverlap(v.od, sp.s, sp.e) then under_vocal = under_vocal + 1 end
            end
            rep.summary[#rep.summary + 1] = ('%s\t%d phrases (target ~%d), %d in unisons%s'):format(
                g.label, #list, target, n_un,
                #list > 1 and (', largest gap %d measures'):format(gap_max) or '')
            if #list == 0 then
                if target > 0 then Warn('count', ('%s: no overdrive phrases (about %d expected).'):format(g.label, target)) end
            elseif #list < target * 0.6 then
                Warn('count', ('%s: %d phrases, well under the ~%d the 1-per-%d-beats rule suggests.'):format(
                    g.label, #list, target, opts.beats_per_phrase))
            elseif #list > target * 1.5 then
                Warn('count', ('%s: %d phrases, well over the ~%d the 1-per-%d-beats rule suggests.'):format(
                    g.label, #list, target, opts.beats_per_phrase))
            end
            if target > 0 and #list >= 2 then
                local spacing = playing_bars / target
                if gap_max > spacing * 2.5 and gap_at then
                    Warn('gap', ('%s: %d measures without overdrive after %s (spacing should be even).'):format(
                        g.label, gap_max, OdWhere(gap_at)))
                end
            end
            if #list >= 4 then
                local mid = bars[math.max(1, (nb + 1) // 2)].qn_s
                local h1 = 0
                for _, sp in ipairs(list) do if sp.s < mid then h1 = h1 + 1 end end
                local h2 = #list - h1
                if math.min(h1, h2) < #list / 4 then
                    Warn('balance', ('%s: %d phrases in the first half of the song and %d in the second - the doc asks for even spacing.'):format(
                        g.label, h1, h2))
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Across instruments
    ------------------------------------------------------------------
    for _, gr in ipairs(groups) do
        if gr.n == 2 and not IsUnison(gr, n_present) then
            local names = {}
            for key in pairs(gr.keys) do names[#names + 1] = OdInstGroup(key).label end
            table.sort(names)
            Warn('pair', ('%s share a phrase at %s: a phrase is either one instrument or a unison, not a pair.'):format(
                table.concat(names, ' and '), OdWhere(gr.span.s)))
        end
    end
    for _, gr in ipairs(unison_groups) do
        if gr.span.e > last_un_qn + OD_QN_EPS then
            Warn('late unison', ('Unison at %s is in the last %d measures.'):format(OdWhere(gr.span.s), ko_un))
        end
    end
    local keys_list = {}
    for _, g in ipairs(OD_INST_GROUPS) do if final[g.key] then keys_list[#keys_list + 1] = g.key end end
    for i = 1, #keys_list do
        for j = i + 1, #keys_list do
            for _, a in ipairs(final[keys_list[i]]) do
                for _, b in ipairs(final[keys_list[j]]) do
                    if not OdSameSpan(a, b) and OdSpansOverlap(a.s, a.e, b.s, b.e) then
                        Warn('overlap', ('%s and %s phrases overlap at %s without being a unison.'):format(
                            OdInstGroup(keys_list[i]).label, OdInstGroup(keys_list[j]).label,
                            OdWhere(math.max(a.s, b.s))))
                    end
                end
            end
        end
    end
    -- Where the first instrument phrase lands, as measures of band playing before it.
    -- Reported, not warned about: the start keep-out is a preference, and
    -- official charts spread widely (median 5 measures, p10 2, p90 9), so a warning at
    -- the default would fire on about half of them.
    local band_first, first_od
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst.present then
            for b = 1, nb do
                if inst.onset[b] then
                    if not band_first or b < band_first then band_first = b end
                    break
                end
            end
            for _, sp in ipairs(inst.od) do
                if not first_od or sp.s < first_od then first_od = sp.s end
            end
        end
    end
    if band_first and first_od then
        local fb = OdBarAt(bars, first_od) or 1
        rep.summary[#rep.summary + 1] = ('First OD\t%s, %d measure%s of playing before it (start keep-out %d)'):format(
            OdWhere(first_od), fb - band_first, fb - band_first == 1 and '' or 's', opts.keepout_start or 0)
    end
    if under_vocal > 0 then
        rep.summary[#rep.summary + 1] = ('Under vocal OD\t%d instrument phrase%s overlap vocal overdrive'):format(
            under_vocal, under_vocal == 1 and '' or 's')
    end
    local expect_un = math.floor((opts.unison_share or 0.5) * (function()
        table.sort(counts)
        if #counts == 0 then return 0 end
        return (counts[math.floor((#counts + 1) / 2)] + counts[math.ceil((#counts + 1) / 2)]) / 2
    end)() + 0.5)
    rep.summary[#rep.summary + 1] = ('Unisons\t%d (about %d expected)'):format(#unison_groups, expect_un)

    ------------------------------------------------------------------
    -- Drums and fills
    ------------------------------------------------------------------
    local drums = model.inst.drums
    for _, f in ipairs(model.fills) do
        local fa = OdBarAt(bars, f.s)
        local fbar_s = fa and bars[fa].qn_s or f.s
        for _, od in ipairs(drums.od) do
            if OdSpansOverlap(od.s, od.e, f.s, f.e) then
                Err('fill overlap', ('Drums: overdrive at %s overlaps a fill.'):format(OdWhere(od.s)))
            elseif OdSpansOverlap(od.s, od.e, fbar_s, f.e) then
                Warn('fill bar', ('Drums: overdrive at %s shares a measure with a fill.'):format(OdWhere(od.s)))
            elseif OdSameQN(od.e, f.s) then
                Warn('touch', ('Drums: overdrive at %s ends exactly where a fill starts (CARV: an overdrive note-off and a fill note-on on the same tick).'):format(
                    OdWhere(od.s)))
            elseif OdSameQN(od.s, f.e) then
                Warn('crash', ('Drums: overdrive at %s starts on a fill\'s closing crash - the game can withhold its energy.'):format(
                    OdWhere(od.s)))
            end
        end
        for _, gr in ipairs(unison_groups) do
            if not gr.keys.drums and OdSpansOverlap(gr.span.s, gr.span.e, fbar_s, f.e) then
                Err('fill bar', ('Unison at %s shares a measure with a drum fill.'):format(OdWhere(gr.span.s)))
            end
        end
        if not OdBarStartingAt(bars, f.e) then
            Warn('fill end', ('Drums: fill ending at %s does not end on a barline.'):format(OdWhere(f.e)))
        end
        if f.lanes and f.lanes < 5 then
            Warn('fill lanes', ('Drums: fill at %s uses %d of the 5 lanes (120-124).'):format(OdWhere(f.s), f.lanes))
        end
        if OdAnyOverlap(model.rolls, f.s, f.e) then
            Warn('fill roll', ('Drums: fill at %s is over a drum roll.'):format(OdWhere(f.s)))
        end
        if OdAnyOverlap(model.drum_solos, f.s, f.e) then
            Err('fill solo', ('Drums: fill at %s is inside a drum solo, where fills cannot occur.'):format(OdWhere(f.s)))
        end
    end
    for _, solo in ipairs(model.drum_solos) do
        local inside = 0
        for _, od in ipairs(drums.od) do
            if OdSpansOverlap(od.s, od.e, solo.s, solo.e) then inside = inside + 1 end
        end
        if inside > 4 then
            Warn('solo', ('Drums: %d phrases in the drum solo at %s - with no fills there, more than 4 is energy the drummer cannot deploy.'):format(
                inside, OdWhere(solo.s)))
        end
    end
    if drums.present then
        rep.summary[#rep.summary + 1] = ('Fills\t%d'):format(#model.fills)
        -- Fills before drum overdrive can first be activated. Reported, not warned
        -- about: they cannot be used, but official charts often leave one in.
        local phrases = {}
        for _, sp in ipairs(drums.od) do phrases[#phrases + 1] = { s = sp.s, e = sp.e, unison = InUnison(sp) } end
        local arm = OdActivationQN(phrases)
        local _, early = OdSplitEarlyFills(model.fills, arm)
        if #model.fills > 0 and #early > 0 then
            rep.summary[#rep.summary + 1] = arm
                and ('Early fills\t%d before drum overdrive can first be activated (at %s)'):format(#early, OdWhere(arm))
                or  'Early fills\tall of them - the drums never collect enough overdrive to activate'
        end
    end

    ------------------------------------------------------------------
    -- Tracks that must match
    ------------------------------------------------------------------
    local keys = model.inst.keys
    if keys.track and keys.mirror_track then
        local at = FirstMismatch(keys.od, keys.mirror_od or {})
        if at then
            Err('mirror', ('Keys: PART KEYS and PART REAL_KEYS_X overdrive differ, first at %s - the game needs them to match.'):format(
                OdWhere(at)))
        end
    end
    if drums.track and drums.mirror_track then
        local at = FirstMismatch(drums.od, drums.mirror_od or {})
        if at then
            Err('mirror', ('Drums: PART DRUMS and PART DRUMS_2X overdrive differ, first at %s.'):format(OdWhere(at)))
        end
        at = FirstMismatch(model.fills, model.fills_2x or {})
        if at then
            Err('mirror', ('Drums: PART DRUMS and PART DRUMS_2X fills differ, first at %s.'):format(OdWhere(at)))
        end
    end

    ------------------------------------------------------------------
    -- Vocals
    ------------------------------------------------------------------
    if v.present then
        local sung = 0
        for _, ph in ipairs(v.phrases) do if ph.has_notes then sung = sung + 1 end end
        for _, od in ipairs(v.od) do
            local match = false
            for _, ph in ipairs(v.phrases) do
                if OdSameSpan(ph, od) then match = true; break end
            end
            if not match then
                Err('vocal phrase', ('Vocals: overdrive at %s does not line up exactly with a phrase marker (105).'):format(
                    OdWhere(od.s)))
            end
            if model.coda_qn and od.e > model.coda_qn + OD_QN_EPS then
                Err('bre', ('Vocals: overdrive at %s is in the Big Rock Ending.'):format(OdWhere(od.s)))
            elseif od.e > last_od_qn + OD_QN_EPS then
                Warn('late', ('Vocals: overdrive at %s is in the last %d measures.'):format(OdWhere(od.s), ko_od))
            end
        end
        if v.harm_present then
            local at = FirstMismatch(v.od, v.harm_od)
            if at then
                Err('harm', ('Vocals: PART VOCALS and HARM1 overdrive differ, first at %s. Rock Band 3 has a visual bug in harmonies if the parts differ.'):format(
                    OdWhere(at)))
            end
        end
        local ratio = #v.od > 0 and sung / #v.od or 0
        rep.summary[#rep.summary + 1] = #v.od > 0
            and ('Vocals\t%d phrases, 1 per %.1f sung phrases'):format(#v.od, ratio)
            or  'Vocals\tno overdrive'
        if #v.od > 0 and (ratio < 3 or ratio > 7) then
            Warn('vocal count', ('Vocals: 1 overdrive per %.1f phrases (the guideline is 1 per 5).'):format(ratio))
        end
    end
    return rep
end

----------------------------------------------------------------------
-- Overview strip data
----------------------------------------------------------------------

-- What ui_overdrive.lua draws: one row per part across the whole song, fills on the
-- drum row, section starts and the end keep-out.
function OdBuildOverview(model, keepout_od)
    local bars, nb = model.bars, #model.bars
    local ov = {
        s0 = bars[1].qn_s, s1 = bars[nb].qn_e,
        keep_qn = bars[math.max(1, nb - (keepout_od or 8))].qn_e,
        rows = {}, fills = model.fills, sections = {},
    }
    if model.vocal.present then
        ov.rows[#ov.rows + 1] = { label = 'Vocals', spans = model.vocal.od }
    end
    local final, n_present = {}, 0
    for _, g in ipairs(OD_INST_GROUPS) do
        if model.inst[g.key].present then
            final[g.key] = model.inst[g.key].od
            n_present = n_present + 1
        end
    end
    local groups = OdUnisonGroups(final)
    for _, g in ipairs(OD_INST_GROUPS) do
        if final[g.key] then
            local spans = {}
            for _, sp in ipairs(final[g.key]) do
                local un = false
                for _, gr in ipairs(groups) do
                    if IsUnison(gr, n_present) and OdSameSpan(gr.span, sp) then un = true; break end
                end
                spans[#spans + 1] = { s = sp.s, e = sp.e, unison = un }
            end
            ov.rows[#ov.rows + 1] = { label = g.label, spans = spans, fills = g.key == 'drums' }
        end
    end
    for _, sec in ipairs(model.sections) do ov.sections[#ov.sections + 1] = sec.s end
    return ov
end

----------------------------------------------------------------------
-- The Validate action
----------------------------------------------------------------------

function ValidateOverdrive()
    local model, err = OdBuildModel()
    if not model then
        S.status = 'Error'
        S.last_result = err
        return
    end
    local rep = OdValidateModel(model, {
        beats_per_phrase = S.od_beats_per_phrase,
        unison_share = S.od_unison_share / 100,
        keepout_od = S.od_keepout_od,
        keepout_unison = S.od_keepout_unison,
        keepout_start = S.od_keepout_start,
    })
    local n_e, n_w = rep.n_errors, rep.n_warnings
    local lines = {}
    for _, l in ipairs(rep.summary) do lines[#lines + 1] = l end
    if #rep.errors > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Errors'
        for _, l in ipairs(rep.errors) do lines[#lines + 1] = l end
    end
    if #rep.warnings > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'Warnings'
        for _, l in ipairs(rep.warnings) do lines[#lines + 1] = l end
    end
    if not model.has_end_event then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'No [end] event on EVENTS: the song end was taken from the last note, so the end-of-song checks are approximate.'
    end
    S.last_result = table.concat(lines, '\n')
    S.status = (n_e == 0 and n_w == 0) and 'Overdrive check: no issues.'
        or ('Overdrive check: %d error%s, %d warning%s.'):format(n_e, n_e == 1 and '' or 's',
                                                               n_w, n_w == 1 and '' or 's')
    S.od_overview = OdBuildOverview(model, S.od_keepout_od)
end
