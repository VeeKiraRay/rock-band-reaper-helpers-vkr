-- VENUE camera stack validation: which stacked shots can actually play.
-- Read-only - never writes to the track, never opens an undo block.
-- Requires: FindNamedTrackMIDI, GetTakePPQPerQN, GetMutedInstruments,
--           GetCoopRequiredInstruments, CAM_PRIORITY_TIERS, CAM_GENERIC_FALLBACK,
--           PickPriorityCameraEvent, CameraShotFitsBand, INST_LETTER_NAMES,
--           FormatTime, GetTimeSelection, r, S (globals)
--
-- Only 4 band members fit on stage, and keys physically replaces a guitarist or
-- bassist, so a song that charts guitar, bass AND keys can be played by three
-- different lineups. Authors stack several camera shots on one tick and let the
-- game pick per lineup (see "Camera shot priority" in
-- .claude/CLAUDE_venue_theme_generation.md). This validator replays that pick for
-- every lineup the project can actually produce and reports the two ways a stack
-- goes wrong:
--
--   a shot that wins under NO lineup - dead weight on the tick, either because it
--   needs an instrument this project never puts on stage, or because a sibling
--   outranks it everywhere it would otherwise fit;
--
--   a lineup with NO VALID CAMERA SHOT - the author has handed that spot back to
--   the game, which substitutes a generic full band shot (or, for a lone coop duo
--   cut, a single shot of the remaining member). Note this is about the camera
--   having no shot to cut to, not about a player having nothing to perform - an
--   instrument with nothing to play is an [idle] play state, handled elsewhere.
--
-- Plus two mechanical mistakes that break stacking outright: the same shot written
-- twice on one tick, and two shots a few ticks apart that were meant to be stacked
-- (the game reads those as two separate cuts, so the second immediately replaces
-- the first).

-- How far apart two camera events can sit and still read as "meant to be stacked,
-- just not quite aligned". A 32nd note: shorter than any deliberate cut, and the
-- same order of magnitude as the lighting validator's "on this tick" tolerance.
local NEAR_STACK_QN = 0.125

-- A track authored without companion events leaves two lineups uncovered at nearly
-- every spot, which is one finding per cut for the whole song. The count is always
-- reported in full; only the listing is capped, so the panel stays readable.
local UNCOVERED_LIST_MAX = 40

-- The coop two-character shots, read off the priority tiers rather than re-listed
-- here - they are the only shots with the documented duo-to-single fallback.
local COOP_DUO_SET = {}
for _, tier in ipairs(CAM_PRIORITY_TIERS) do
    if tier.key == 'coop_duo' then
        for _, name in ipairs(tier.events) do COOP_DUO_SET['[' .. name .. ']'] = true end
    end
end

-- The lineups this project can put on stage, as { label, muted } pairs that
-- CameraShotFitsBand understands.
--
-- Drums and vocals are in every lineup (or in none, if their PART track is missing).
-- Of bass/guitar/keys only two can play at once, so a project charting all three has
-- three possible lineups and a stack has to cover each; a project charting two or
-- fewer has exactly one, and shots for the absent instrument can never play.
function BuildBandLineups(muted)
    local trio    = { 'b', 'g', 'k' }
    local present = {}
    for _, ltr in ipairs(trio) do
        if not muted[ltr] then present[#present + 1] = ltr end
    end

    local function Named(letters)
        if #letters == 0 then return 'Drums + Vocals only' end
        local names = {}
        for _, ltr in ipairs(letters) do names[#names + 1] = INST_LETTER_NAMES[ltr] end
        return table.concat(names, ' + ')
    end

    -- Copy the base muted table (which carries drums/vocals state) and add the
    -- members of the trio this lineup leaves off stage.
    local function Lineup(on_stage)
        local m = {}
        for k, v in pairs(muted) do m[k] = v end
        local keep = {}
        for _, ltr in ipairs(on_stage) do keep[ltr] = true end
        for _, ltr in ipairs(trio) do
            if not keep[ltr] then m[ltr] = true end
        end
        return { label = Named(on_stage), muted = m }
    end

    if #present < 3 then return { Lineup(present) } end
    return { Lineup({'b','g'}), Lineup({'b','k'}), Lineup({'g','k'}) }
end

-- ---------------------------------------------------------------------------

-- The whole validation, as a pure function over a ppq-sorted array of {ppq=, msg=}
-- camera events and the lineups from BuildBandLineups. No REAPER calls, so the
-- rules can be tested against hand-built event lists without a project - same
-- discipline as ValidateVenueLightingBlends.
--
--   near_ppq  ticks within which two events read as a botched stack, not two cuts
--
-- Returns a findings table; every list is empty when the track is clean.
function ValidateVenueCameraStacks(camera, lineups, near_ppq)
    near_ppq = near_ppq or 0

    local out = {
        duplicates  = {},   -- { ppq=, msg=, count= }
        near_stacks = {},   -- { ppq=, msg=, prev_ppq=, prev_msg=, delta= }
        unreachable = {},   -- { ppq=, msg=, fits_any=, beaten_by= }
        -- One entry per SPOT, not per lineup: a track authored without companions
        -- leaves two lineups uncovered at nearly every spot, and listing those
        -- separately buries the report in near-identical lines.
        uncovered   = {},   -- { ppq=, shots={}, lineups={ {label=,kind=,note=} } }
        spots       = 0,    -- camera ticks
        stacked     = 0,    -- of those, ticks carrying more than one distinct shot
        events      = #camera,
    }
    if #camera == 0 then return out end

    ---- Walk the track one PPQ group at a time ----
    local i = 1
    local prev_group_ppq, prev_group_last
    while i <= #camera do
        local ppq  = camera[i].ppq
        local last = i
        while last < #camera and camera[last + 1].ppq == ppq do last = last + 1 end
        out.spots = out.spots + 1

        ---- Check 1: the same shot written twice on one tick ----
        -- Deduped before anything else, so a copy is reported once as a duplicate
        -- rather than a second time as a shot that never plays.
        local group, seen, order = {}, {}, {}
        for j = i, last do
            local msg = camera[j].msg
            if seen[msg] then
                seen[msg] = seen[msg] + 1
            else
                seen[msg] = 1
                order[#order + 1] = msg
                group[#group + 1] = camera[j]
            end
        end
        for _, msg in ipairs(order) do
            if seen[msg] > 1 then
                out.duplicates[#out.duplicates + 1] = { ppq = ppq, msg = msg, count = seen[msg] }
            end
        end
        if #group > 1 then out.stacked = out.stacked + 1 end

        ---- Check 2: two shots that were meant to be stacked, but are not ----
        if prev_group_ppq and near_ppq > 0 and (ppq - prev_group_ppq) <= near_ppq then
            out.near_stacks[#out.near_stacks + 1] = {
                ppq      = ppq,            msg      = group[1].msg,
                prev_ppq = prev_group_ppq, prev_msg = prev_group_last,
                delta    = ppq - prev_group_ppq,
            }
        end

        ---- Replay the game's pick for every possible lineup ----
        local won, blind = {}, {}
        for _, lineup in ipairs(lineups) do
            local chosen = PickPriorityCameraEvent(group, lineup.muted)
            if chosen then
                won[chosen.msg] = true
            else
                ---- Check 3: a lineup with no valid camera shot ----
                -- The documented duo-to-single fallback needs a lone coop duo cut
                -- ("no other stacked flags"); anything else drops to a generic shot.
                local kind, note = 'generic', nil
                if #group == 1 and COOP_DUO_SET[group[1].msg] then
                    local remaining = {}
                    for _, ltr in ipairs(GetCoopRequiredInstruments(group[1].msg)) do
                        if not lineup.muted[ltr] then
                            remaining[#remaining + 1] = INST_LETTER_NAMES[ltr]
                        end
                    end
                    if #remaining > 0 then
                        kind = 'duo_single'
                        note = table.concat(remaining, ' + ')
                    end
                end
                blind[#blind + 1] = { label = lineup.label, kind = kind, note = note }
            end
        end
        if #blind > 0 then
            local shots = {}
            for _, ev in ipairs(group) do shots[#shots + 1] = ev.msg end
            out.uncovered[#out.uncovered + 1] =
                { ppq = ppq, shots = shots, lineups = blind }
        end

        ---- Check 4: a shot that wins under no lineup ----
        -- A lone shot that fits nothing is already reported by check 3 as an
        -- uncovered spot, so only genuinely shadowed siblings are listed here.
        if #group > 1 then
            for _, ev in ipairs(group) do
                if not won[ev.msg] then
                    local fits_any, beaten_by = false, nil
                    for _, lineup in ipairs(lineups) do
                        if CameraShotFitsBand(ev.msg, lineup.muted) then
                            fits_any = true
                            local winner = PickPriorityCameraEvent(group, lineup.muted)
                            if winner then beaten_by = winner.msg end
                        end
                    end
                    out.unreachable[#out.unreachable + 1] = {
                        ppq = ppq, msg = ev.msg, fits_any = fits_any, beaten_by = beaten_by,
                    }
                end
            end
        end

        prev_group_ppq  = ppq
        prev_group_last = group[#group].msg
        i = last + 1
    end

    return out
end

-- ---------------------------------------------------------------------------

function ValidateVenueCamera()
    local track, _, take = FindNamedTrackMIDI('VENUE')
    if not track then
        S.status      = 'No VENUE track found.'
        S.last_result = 'No VENUE track detected.'
        return
    end
    if not take then
        S.status      = 'Error reading VENUE track.'
        S.last_result = 'No MIDI item found on VENUE track.'
        return
    end

    -- Whole track regardless of time selection: only the reporting is scoped, so a
    -- stack straddling the selection edge is still judged against all of its shots.
    local camera = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evtype == 1 and (msg:find('^%[coop_') or msg:find('^%[directed_')) then
            camera[#camera + 1] = { ppq = ppq, msg = msg }
        end
    end

    if #camera == 0 then
        S.status      = 'VENUE has no camera events.'
        S.last_result = 'The VENUE track has no [coop_*] or [directed_*] events to validate.'
        return
    end

    table.sort(camera, function(a, b) return a.ppq < b.ppq end)

    local muted   = GetMutedInstruments()
    local lineups = BuildBandLineups(muted)

    local ppq_per_qn = GetTakePPQPerQN(take)
    local near_ppq   = math.floor(ppq_per_qn * NEAR_STACK_QN)

    local f = ValidateVenueCameraStacks(camera, lineups, near_ppq)

    -- Scope: report only findings whose own position falls inside the time selection.
    local sel_s, sel_e = GetTimeSelection()
    local scope_label  = 'whole song'
    if sel_s then
        local lo = r.MIDI_GetPPQPosFromProjTime(take, sel_s)
        local hi = r.MIDI_GetPPQPosFromProjTime(take, sel_e)
        scope_label = ('time selection %s - %s'):format(FormatTime(sel_s), FormatTime(sel_e))
        local function Keep(list)
            local out = {}
            for _, it in ipairs(list) do
                if it.ppq >= lo and it.ppq <= hi then out[#out + 1] = it end
            end
            return out
        end
        f.duplicates  = Keep(f.duplicates)
        f.near_stacks = Keep(f.near_stacks)
        f.unreachable = Keep(f.unreachable)
        f.uncovered   = Keep(f.uncovered)
    end

    local function At(ppq) return FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, ppq)) end

    local total = #f.duplicates + #f.near_stacks + #f.unreachable + #f.uncovered

    local lines = {}
    lines[#lines + 1] = total == 0
        and ('VENUE camera validation - no issues  (%s)'):format(scope_label)
        or  ('VENUE camera validation - %d issue%s  (%s)')
            :format(total, total == 1 and '' or 's', scope_label)
    lines[#lines + 1] = ''

    ---- Lineups ----
    lines[#lines + 1] = ('Lineups this project can put on stage (%d):'):format(#lineups)
    for _, lu in ipairs(lineups) do
        lines[#lines + 1] = '  ' .. lu.label
    end
    if #lineups == 1 then
        lines[#lines + 1] = '  Only one lineup is possible, so no stacking is needed to cover'
        lines[#lines + 1] = '  alternatives. Chart guitar, bass and keys together and this'
        lines[#lines + 1] = '  becomes three lineups, each needing a shot at every spot.'
    end
    lines[#lines + 1] = ''

    ---- Duplicates ----
    if #f.duplicates == 0 then
        lines[#lines + 1] = 'Shots written twice on one tick: none.'
    else
        lines[#lines + 1] = ('Shots written twice on one tick (%d):'):format(#f.duplicates)
        for _, d in ipairs(f.duplicates) do
            lines[#lines + 1] = ('  %s   %s  x%d'):format(At(d.ppq), d.msg, d.count)
            lines[#lines + 1] = '           - delete the extra copies, they change nothing'
        end
    end
    lines[#lines + 1] = ''

    ---- Near stacks ----
    if #f.near_stacks == 0 then
        lines[#lines + 1] = 'Shots too close to be separate cuts: none.'
    else
        lines[#lines + 1] = ('Shots too close to be separate cuts (%d):'):format(#f.near_stacks)
        for _, n in ipairs(f.near_stacks) do
            lines[#lines + 1] = ('  %s   %s  is %d tick%s after  %s')
                :format(At(n.ppq), n.msg, n.delta, n.delta == 1 and '' or 's', n.prev_msg)
            lines[#lines + 1] = '           - if these were meant to be stacked, put them on the'
            lines[#lines + 1] = '             same tick; as authored the second replaces the first'
        end
    end
    lines[#lines + 1] = ''

    ---- Unreachable ----
    if #f.unreachable == 0 then
        lines[#lines + 1] = 'Stacked shots that never play: none.'
    else
        lines[#lines + 1] = ('Stacked shots that never play (%d):'):format(#f.unreachable)
        for _, u in ipairs(f.unreachable) do
            lines[#lines + 1] = ('  %s   %s'):format(At(u.ppq), u.msg)
            if not u.fits_any then
                lines[#lines + 1] = '           - needs an instrument no lineup puts on stage'
                lines[#lines + 1] = '           - delete it, or chart the instrument it wants'
            else
                lines[#lines + 1] = ('           - outranked by %s wherever it fits')
                                    :format(tostring(u.beaten_by))
                lines[#lines + 1] = '           - delete it, or remove the shot that outranks it'
            end
        end
    end
    lines[#lines + 1] = ''

    ---- Uncovered ----
    -- "No valid camera shot", never "nothing to play": an instrument with nothing
    -- to play is an [idle] play state, a different thing entirely, and the Venue
    -- tab reports on that too.
    if #f.uncovered == 0 then
        lines[#lines + 1] = 'Spots with no valid camera shot for some lineup: none.'
    else
        lines[#lines + 1] = ('Spots with no valid camera shot for some lineup (%d):')
                            :format(#f.uncovered)
        for i, c in ipairs(f.uncovered) do
            if i > UNCOVERED_LIST_MAX then
                lines[#lines + 1] = ('  ... and %d more spots. Narrow the time selection to see them.')
                                    :format(#f.uncovered - UNCOVERED_LIST_MAX)
                break
            end
            lines[#lines + 1] = ('  %s   %s'):format(At(c.ppq), table.concat(c.shots, ', '))
            lines[#lines + 1] = '           no valid camera shot for:'
            for _, lu in ipairs(c.lineups) do
                if lu.kind == 'duo_single' then
                    lines[#lines + 1] = ('             - %s lineup  ->  the game converts this duo cut to a single shot of %s')
                                        :format(lu.label, lu.note)
                else
                    lines[#lines + 1] = ('             - %s lineup  ->  the game shows a generic full band shot')
                                        :format(lu.label)
                end
            end
            lines[#lines + 1] = '           - stack a shot for those lineups to choose it yourself'
        end
        lines[#lines + 1] = ('  The generic shots are %s.')
                            :format(table.concat(CAM_GENERIC_FALLBACK, ', '))
        -- Handing a spot to the game is a legitimate choice, not a mistake - this
        -- list is "where the game decides", not "where the track is wrong".
        lines[#lines + 1] = '  Letting the game fall back is valid - only act on the spots you'
        lines[#lines + 1] = '  wanted to control.'
    end
    lines[#lines + 1] = ''

    ---- Summary ----
    -- Always the whole track, even when the report above is scoped: the counts
    -- describe what was read, and reading everything is what makes the scoped
    -- findings correct.
    lines[#lines + 1] = 'Checked (whole track):'
    lines[#lines + 1] = ('  %d camera events across %d spots, %d of them stacked')
                        :format(f.events, f.spots, f.stacked)
    lines[#lines + 1] = ('  %d lineup%s replayed at every spot')
                        :format(#lineups, #lineups == 1 and '' or 's')

    S.status = total == 0
        and 'VENUE camera: no issues found.'
        or  ('VENUE camera: %d issue%s found.'):format(total, total == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end
