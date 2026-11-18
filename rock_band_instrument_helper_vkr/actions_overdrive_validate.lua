-- Overdrive tab: read-only validation and the overview strip's data.
--
-- Checks authored overdrive, unisons, drum fills and vocal overdrive against the RBN
-- rules the generator follows (see actions_overdrive.lua). Never writes and creates no
-- undo point. Errors are the rules whose breach the docs tie to a game bug or to the
-- chart not working, or that Magma refuses (overdrive overlapping a fill, vocal
-- overdrive off its own track's phrase marker - PART VOCALS' or HARM1's, two phrases
-- with no gems between them on any difficulty, mismatched mirror tracks). HARM1 not
-- matching PART VOCALS is a warning: Magma and the game accept it, with a known visual
-- bug in harmonies. Everything else is
-- a warning, including two rules the docs state firmly but official charts break often
-- enough that an error would be noise: measured over the reference corpus, a drum
-- phrase ending exactly where a fill starts (the CARV "touching" rule) and one starting
-- on a fill's crash each turn up in 3-8% of fills, community RBN charts included.
--
-- OdValidateModel is pure over the model from OdBuildModel.
-- Requires (globals): r, S, OD_* and Od* (overdrive_read.lua), OdUnisonGroups
-- (actions_overdrive.lua), OdActivationQN / OdSplitEarlyFills (actions_overdrive_fills.lua)
--   ScoreReadSong / ScoreSimulatePart / ScoreFindings / ScoreCoverageText / SCORE_PARTS
--   (lib/reaper_score_read.lua, lib/reaper_score_sim.lua) for the "in play" lines

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
    local under_vocal = 0
    for _, g in ipairs(OD_INST_GROUPS) do
        local inst = model.inst[g.key]
        if inst.present then
            local list = inst.od
            local beats = PlayingBeats(model, inst, nb - ko_od)
            local target = beats > 0
                and math.max(1, math.floor(beats / opts.beats_per_phrase + 0.5)) or 0
            -- Gaps and the half-and-half balance count the part's own PLAYING measures
            -- (a note starts or a sustain still rings), as the generator does: a long
            -- rest - keys silent for a verse - is not a gap overdrive could have filled.
            -- cum[b] = playing measures up to and including b.
            local n_un, gap_max, gap_at = 0, 0, nil
            local cum, playing_bars = {}, 0
            for b = 1, nb do
                if inst.playing[b] then playing_bars = playing_bars + 1 end
                cum[b] = playing_bars
            end
            cum[0] = 0
            for i, sp in ipairs(list) do
                if InUnison(sp) then n_un = n_un + 1 end
                if i > 1 then
                    local gb = cum[OdBarAt(bars, sp.s) or nb] - cum[OdBarAt(bars, list[i - 1].s) or 1]
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
            -- Phrases against each authored difficulty's gems (Magma checks every one):
            -- two phrases with no gem between them is a Magma error; a phrase with no gem
            -- in it can never be earned. Pro Keys is its own chart under the same overdrive.
            for _, tier in ipairs(inst.tiers or {}) do
                local who = tier.own_label and tier.name or (g.label .. ' ' .. tier.name)
                local issues = OdPhraseGemIssues(tier.od or list, tier.events or {})
                for _, pair in ipairs(issues.adjacent) do
                    Err('no gems between', ('%s: no notes between the overdrive phrases at %s and %s - Magma refuses the song ("No gems between overdrive phrases"). Add notes between them, or remove one.'):format(
                        who, OdWhere(pair.a.s), OdWhere(pair.b.s)))
                end
                for _, sp in ipairs(issues.empty) do
                    Warn('empty', ('%s: overdrive phrase at %s has no notes - it can never be earned.'):format(
                        who, OdWhere(sp.s)))
                end
            end
            -- Markers carry facts only. Targets come from the current Generate settings,
            -- which need not be what the chart was made with (hand-placed overdrive,
            -- older settings), so only the warnings below use them - and say so.
            rep.summary[#rep.summary + 1] = ('%s\t%d phrases, %d in unisons%s'):format(
                g.label, #list, n_un,
                #list > 1 and (', largest gap %d playing measures'):format(gap_max) or '')
            if #list == 0 then
                if target > 0 then Warn('count', ('%s: no overdrive phrases (the current Generate settings would place ~%d).'):format(g.label, target)) end
            elseif #list < target * 0.6 then
                Warn('count', ('%s: %d phrases, well under the ~%d the current Generate settings would place (1 per %d counted beats).'):format(
                    g.label, #list, target, opts.beats_per_phrase))
            elseif #list > target * 1.5 then
                Warn('count', ('%s: %d phrases, well over the ~%d the current Generate settings would place (1 per %d counted beats).'):format(
                    g.label, #list, target, opts.beats_per_phrase))
            end
            if target > 0 and #list >= 2 then
                local spacing = playing_bars / target
                if gap_max > spacing * 2.5 and gap_at then
                    Warn('gap', ('%s: %d playing measures without overdrive after %s (the current Generate settings space phrases about %d apart; spacing should be even).'):format(
                        g.label, gap_max, OdWhere(gap_at), math.floor(spacing + 0.5)))
                end
            end
            if #list >= 4 and playing_bars > 0 then
                -- Halves of the part's playing measures, not of the song.
                local h1 = 0
                for _, sp in ipairs(list) do
                    if cum[OdBarAt(bars, sp.s) or nb] <= playing_bars / 2 then h1 = h1 + 1 end
                end
                local h2 = #list - h1
                if math.min(h1, h2) < #list / 4 then
                    Warn('balance', ('%s: %d phrases in the first half of its playing and %d in the second - the doc asks for even spacing.'):format(
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
        rep.summary[#rep.summary + 1] = ('First OD\t%s, %d measure%s of playing before it'):format(
            OdWhere(first_od), fb - band_first, fb - band_first == 1 and '' or 's')
    end
    if under_vocal > 0 then
        rep.summary[#rep.summary + 1] = ('Under vocal OD\t%d instrument phrase%s overlap vocal overdrive'):format(
            under_vocal, under_vocal == 1 and '' or 's')
    end
    rep.summary[#rep.summary + 1] = ('Unisons\t%d'):format(#unison_groups)

    ------------------------------------------------------------------
    -- Drums and fills
    ------------------------------------------------------------------
    local drums = model.inst.drums
    for i, f in ipairs(model.fills) do
        -- Magma refuses to build the song: "Drum fill at ... too close (N ms) to end of
        -- preceding fill. Must be 2.5 sec between drum fills".
        local pf = model.fills[i - 1]
        if pf and #bars > 0 then
            local gap = OdQNToSec(bars, f.s) - OdQNToSec(bars, pf.e)
            if gap < OD_FILL_MIN_GAP_SEC - 1e-3 then
                Err('fill gap', ('Drums: fill at %s starts %.2f s after the previous fill ends - Magma needs %.1f s.'):format(
                    OdWhere(f.s), gap, OD_FILL_MIN_GAP_SEC))
            end
        end
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
        -- Each track's overdrive against that track's own phrase markers and notes - what
        -- Magma checks, per track (OdVocalOdProblem). Our reason first, then the text
        -- Magma gives for it, so the two can be matched up.
        local REASON = {
            after_all   = 'comes after the last sung note',
            during_note = 'starts in the middle of a sung note',
            off         = 'is not on a phrase: the next sung note has no phrase marker (105)',
            mid_phrase  = 'starts after the first note of its phrase',
            no_notes    = 'is on a phrase with no %s notes in it, so it cannot be earned there',
            short       = 'ends before the last note of its phrase starts',
            long        = 'runs into the first note of the next phrase',
        }
        -- other: PART VOCALS' phrases and notes, for HARM1's hint.
        local function CheckTrack(track_name, od_list, phrases, notes, any_notes, other)
            for _, od in ipairs(od_list) do
                local key, magma
                if notes then
                    key, magma = OdVocalOdProblem(od, phrases, notes, any_notes)
                else
                    -- A hand-built model without notes: the marker check alone.
                    local fits = false
                    for _, ph in ipairs(phrases) do
                        if OdSameSpan(ph, od) then fits = true; break end
                    end
                    if not fits then key = 'off' end
                end
                if key then
                    local hint = ''
                    -- Fine on PART VOCALS but not on HARM1: the two tracks' phrases differ
                    -- here, and fitting HARM1 alone would make the overdrive differ from
                    -- PART VOCALS' - the fix for both is phrases that match.
                    if other and other.notes and not OdVocalOdProblem(od, other.phrases, other.notes) then
                        hint = ' It is fine on PART VOCALS: the two tracks\' phrases differ here, so fitting it to HARM1 alone would make it differ from PART VOCALS. Make the phrase markers (and notes) match on both tracks.'
                    end
                    local tail = ''
                    if key == 'no_notes' then
                        tail = (' Magma reports it as "%s".'):format(magma)
                    elseif magma then
                        tail = (' Magma: "vocal overdrive phrase ... %s".'):format(magma)
                    end
                    Err('vocal phrase', ('%s: overdrive at %s %s.%s%s'):format(track_name, OdWhere(od.s),
                        REASON[key]:format(track_name), tail, hint))
                end
            end
        end
        CheckTrack('PART VOCALS', v.od, v.phrases, v.sung)
        for _, od in ipairs(v.od) do
            if model.coda_qn and od.e > model.coda_qn + OD_QN_EPS then
                Err('bre', ('Vocals: overdrive at %s is in the Big Rock Ending.'):format(OdWhere(od.s)))
            elseif od.e > last_od_qn + OD_QN_EPS then
                Warn('late', ('Vocals: overdrive at %s is in the last %d measures.'):format(OdWhere(od.s), ko_od))
            end
        end
        local harm_extra = 0
        if v.harm_present then
            -- HARM1's overdrive is what harmonies play, checked against HARM1's own
            -- phrases and notes (SongData::ValidateVocalSPPhrases; Magma refuses it).
            CheckTrack('HARM1', v.harm_od, v.harm_phrases, v.harm_sung, v.harm_any,
                       { phrases = v.phrases, notes = v.sung })
            -- Magma and the game accept overdrive that differs between the two, but
            -- harmonies then show a known visual bug - worth fixing, not a refusal.
            -- HARM1 with no overdrive at all is fine: harmonies then earn it on PART
            -- VOCALS' phrases (verified in game; 169 official RB3 DLC harmony songs are
            -- authored that way), so only overdrive that exists and differs is warned.
            -- HARM1 overdrive where PART VOCALS has no phrase at all (a part only the
            -- harmonies sing) is left out of the comparison: PART VOCALS can have no
            -- overdrive there, so nothing differs from it (a community authoring tip,
            -- not verified in game).
            local harm_own = {}
            for _, od in ipairs(v.harm_od) do
                if OdAnyOverlap(v.phrases, od.s, od.e) then harm_own[#harm_own + 1] = od end
            end
            harm_extra = #v.harm_od - #harm_own
            local at = #v.harm_od > 0 and FirstMismatch(v.od, harm_own)
            if at then
                Warn('harm', ('Vocals: PART VOCALS and HARM1 overdrive differ, first at %s. Magma and Rock Band 3 accept it, but harmonies then show a known visual bug - make them match.'):format(
                    OdWhere(at)))
            end
        end
        local ratio = #v.od > 0 and sung / #v.od or 0
        rep.summary[#rep.summary + 1] = #v.od > 0
            and ('Vocals\t%d phrases, 1 per %.1f sung phrases%s'):format(#v.od, ratio,
                (v.harm_present and #v.harm_od == 0) and ' (HARM1 has none: harmonies use these)'
                or harm_extra > 0 and (' (HARM1 adds %d where PART VOCALS has no phrase)'):format(harm_extra)
                or '')
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

-- Overdrive in play: each part's authored overdrive run through the game's meter with a
-- full combo that deploys as soon as it can (lib/reaper_score_sim.lua, the same model as
-- the General Helper's Metadata > Score). Adds one coverage line per part to the summary
-- and a warning wherever overdrive goes to waste: earned into a full meter, never
-- deployed before the part ends, or a drum fill that cannot appear because it starts too
-- soon after the drummer becomes ready.
local function HasOverdrive(part)
    if not part then return false end
    if #(part.od or {}) > 0 then return true end
    for _, ph in ipairs(part.phrases or {}) do
        if ph.od then return true end
    end
    return false
end

-- 123456 -> "123,456" (lib/reaper_score_read.lua; looked up at call time, so load order
-- does not matter).
local function Num(n) return ScoreNum(n) end

-- "Overdrive in play": every part with overdrive run through the game's meter (perfect
-- run, deploy as soon as possible - lib/reaper_score_sim.lua, the same model as the
-- General Helper's Metadata > Score). Per part: time in overdrive, what overdrive adds
-- against the full combo and what gold needs, then the chart's real losses ("!", counted
-- as warnings) and the last-phrase advice ("?"). Notes about the simulated path itself
-- (where it holds overdrive) are left out: a player with a better path uses it all.
-- Returns the section's lines; adds its warnings to rep.n_warnings.
local function PlayReport(rep)
    local song = ScoreReadSong()
    local out = {}
    for _, spec in ipairs(SCORE_PARTS) do
        local part = song.parts[spec.key]
        -- PART DRUMS_2X and harmonies (optional) carry PART DRUMS' / PART VOCALS'
        -- overdrive: one entry for each.
        if not spec.optional and HasOverdrive(part) then
            local drums = spec.kind == 'drums'
            local res = ScoreSimulatePart(part, drums and { pro = true } or {})
            local fc = res.base_streak + res.base_bonus
            out[#out + 1] = ''
            -- "in OD" is the label already, so the coverage text drops its own.
            local cov = ScoreCoverageText(res)
            out[#out + 1] = ('%s in OD\t%s'):format(spec.label,
                cov and (cov:gsub(' in OD', '', 1)) or 'never deployed')
            if fc > 0 then
                -- Gold when reached, red when short - the Metadata > Score colours
                -- (result line tags, lib/reaper_helper_ui.lua).
                local gold = res.total >= res.stars[6]
                local verdict = gold and 'reached' or ('short by %s'):format(Num(res.gold_short))
                out[#out + 1] = ('%s%s OD boost\t+%s: x%.2f of the %sFC - gold needs x%.2f, %s')
                    :format(gold and '{gold}' or '{error}', spec.label, Num(res.total - fc),
                            res.total / fc, drums and 'Pro drums ' or '', res.stars[6] / fc, verdict)
            end
            for _, f in ipairs(ScoreFindings(res, song.bars, spec.kind)) do
                if f.level == 'warn' then
                    rep.n_warnings = rep.n_warnings + 1
                    out[#out + 1] = '! ' .. f.text
                elseif f.level == 'advice' then
                    out[#out + 1] = '{warn}? ' .. f.text   -- amber, as Metadata > Score
                elseif f.level == 'note' then
                    out[#out + 1] = '{dim}- ' .. f.text    -- grey, not counted
                end
            end
        end
    end
    if #out == 0 then return out end
    if song.no_beat then
        out[#out + 1] = ''
        out[#out + 1] = 'No BEAT track: overdrive drain is estimated at one beat per quarter note.'
    end
    table.insert(out, 1, 'Overdrive in play')
    table.insert(out, 2, 'A full combo (FC), overdrive (OD) deployed as soon as possible. The full scores '
        .. 'are in the General Helper, Metadata > Score.')
    return out
end

-- The check report Validate shows, and Generate shows under its own lines: Markers,
-- Errors, Warnings, Overdrive in play - read from the project as it is now. Returns
-- { lines, n_errors, n_warnings, model }, or nil, error.
function OdCheckReport()
    local model, err = OdBuildModel()
    if not model then return nil, err end
    local rep = OdValidateModel(model, {
        beats_per_phrase = S.od_beats_per_phrase,
        unison_share = S.od_unison_share / 100,
        keepout_od = S.od_keepout_od,
        keepout_unison = S.od_keepout_unison,
        keepout_start = S.od_keepout_start,
    })
    local play = PlayReport(rep)
    -- Section headings with two blank lines before them (each draws as spacing), so a
    -- heading stands out from the line above it.
    local lines = { 'Markers' }
    local function Heading(text)
        lines[#lines + 1] = ''
        lines[#lines + 1] = ''
        lines[#lines + 1] = text
    end
    for _, l in ipairs(rep.summary) do lines[#lines + 1] = l end
    if #rep.errors > 0 then
        Heading('Errors')
        for _, l in ipairs(rep.errors) do lines[#lines + 1] = l end
    end
    if #rep.warnings > 0 then
        Heading('Warnings')
        for _, l in ipairs(rep.warnings) do lines[#lines + 1] = l end
    end
    if not model.has_end_event then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'No [end] event on EVENTS: the song end was taken from the last note, so the end-of-song checks are approximate.'
    end
    if #play > 0 then
        Heading(play[1])
        for i = 2, #play do lines[#lines + 1] = play[i] end
    end
    return { lines = lines, n_errors = rep.n_errors, n_warnings = rep.n_warnings, model = model }
end

-- "0 errors, 2 warnings" / "no issues".
function OdCheckCounts(rep)
    local n_e, n_w = rep.n_errors, rep.n_warnings
    if n_e == 0 and n_w == 0 then return 'no issues' end
    return ('%d error%s, %d warning%s'):format(n_e, n_e == 1 and '' or 's',
                                              n_w, n_w == 1 and '' or 's')
end

function ValidateOverdrive()
    local rep, err = OdCheckReport()
    if not rep then
        S.status = 'Error'
        S.last_result = err
        return
    end
    S.last_result = table.concat(rep.lines, '\n')
    S.status = 'Overdrive check: ' .. OdCheckCounts(rep) .. '.'
    S.od_overview = OdBuildOverview(rep.model, S.od_keepout_od)
end
