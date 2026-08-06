-- VENUE lighting/post-proc validation: [first] keyframe placement and blend anchors.
-- Read-only - never writes to the track, never opens an undo block.
-- Requires: FindNamedTrackMIDI, GetTakePPQPerQN, CategorizeVenueEvent,
--           MANUAL_LIGHTING_SET, IsBlendAnchor, FormatTime, GetTimeSelection,
--           r, S (globals)
--
-- The two rules checked here are the same ones the generators write from, read back
-- off the track:
--   [first]  belongs on the exact tick of a manual lighting event that CHANGES the
--            running preset. An event restating the preset already running (a blend
--            anchor) starts no keyframe train, so it must NOT carry one - see
--            "Keyframe placement rule" in .claude/CLAUDE_general.md.
--   blend    a preset change reads as a soft fade only when the OUTGOING preset is
--            restated shortly before it. That restatement is the anchor - the same
--            duplicate EmitBlendDuplicates emits from lightpreset_blendin /
--            postproc_blendin, and the same one Manual gen's Blend button places.

-- How far from a lighting change a [first] can sit and still read as "meant for that
-- event, just misplaced" rather than a stray. One beat: the generators' own minimum
-- [next] spacing, so anything further out is a keyframe position in its own right.
local NEAR_FIRST_BEATS = 1

-- Index of the entry in `events` (sorted ascending by ppq) nearest ppq_pos, plus a
-- cursor to resume from on the next, later, lookup. Returns nil for an empty list.
local function NearestIndex(events, ppq_pos, cursor)
    if #events == 0 then return nil, 1 end
    local i = math.max(1, math.min(cursor or 1, #events))
    while i < #events and events[i + 1].ppq <= ppq_pos do i = i + 1 end
    local best = i
    if events[i + 1] and
       math.abs(events[i + 1].ppq - ppq_pos) < math.abs(events[i].ppq - ppq_pos) then
        best = i + 1
    end
    return best, i
end

-- ---------------------------------------------------------------------------

-- The whole validation, as a pure function over three sorted arrays of {ppq=, msg=}
-- (`firsts` needs only ppq). No REAPER calls, so the rules can be tested against
-- hand-built event lists without a project - same discipline as ResolveBlendSource.
--
--   tol       ticks either side of an event that still count as "on this tick"
--   near_ppq  ticks within which a stray [first] is read as misplaced, not orphaned
--
-- Returns a findings table; every list is empty when the track is clean.
function ValidateVenueLightingBlends(lighting, postproc, firsts, tol, near_ppq)
    tol      = tol or 0
    near_ppq = near_ppq or 0

    local out = {
        missing_first  = {},   -- { idx=, ppq=, msg=, near_delta= }
        stray_first    = {},   -- { ppq=, kind=, lt=, delta= }
        blend          = {
            lt = { missing = {}, changes = 0, anchored = 0 },
            pp = { missing = {}, changes = 0, anchored = 0 },
        },
        changes        = 0,    -- lighting preset changes, including the first event
        manual_changes = 0,    -- of those, the manual presets (the ones wanting [first])
    }

    -- A lighting event is a preset CHANGE when it differs from the one immediately
    -- before it; the first event on the track always is one. Only ADJACENT events are
    -- compared, so two sections sharing a preset with a different one between them are
    -- each a real change.
    local is_change = {}
    for i, ev in ipairs(lighting) do
        is_change[i] = (i == 1) or (lighting[i - 1].msg ~= ev.msg)
        if is_change[i] then
            out.changes = out.changes + 1
            if MANUAL_LIGHTING_SET[ev.msg] then out.manual_changes = out.manual_changes + 1 end
        end
    end

    -- Does a [first] sit on this lighting event's own tick? Both lists are sorted, so
    -- one monotonic pass over `firsts` covers every lighting event.
    local has_first = {}
    do
        local fi = 1
        for i, ev in ipairs(lighting) do
            while fi <= #firsts and firsts[fi].ppq < ev.ppq - tol do fi = fi + 1 end
            has_first[i] = firsts[fi] ~= nil and math.abs(firsts[fi].ppq - ev.ppq) <= tol
        end
    end

    ---- Check 1: a manual lighting change with no [first] on its tick ----
    local wants_first = {}
    for i, ev in ipairs(lighting) do
        if is_change[i] and MANUAL_LIGHTING_SET[ev.msg] and not has_first[i] then
            wants_first[i] = true
            out.missing_first[#out.missing_first + 1] = { idx = i, ppq = ev.ppq, msg = ev.msg }
        end
    end

    ---- Check 2: a [first] that is not on a manual lighting change ----
    local cursor, prev_ppq = 1, nil
    for _, f in ipairs(firsts) do
        local kind, lt, delta
        if prev_ppq and math.abs(f.ppq - prev_ppq) <= tol then
            kind = 'duplicate'
        elseif #lighting == 0 then
            kind = 'orphan'
        else
            local idx
            idx, cursor = NearestIndex(lighting, f.ppq, cursor)
            lt    = lighting[idx]
            delta = f.ppq - lt.ppq
            if math.abs(delta) <= tol then
                -- On a lighting event, but not one that starts a keyframe train.
                if not MANUAL_LIGHTING_SET[lt.msg] then
                    kind = 'on_auto'
                elseif not is_change[idx] then
                    kind = 'on_restatement'
                end   -- else: correctly placed - no finding
            elseif math.abs(delta) <= near_ppq and wants_first[idx] then
                -- Close to a change that is missing its own [first]: this is almost
                -- certainly that [first], off by a nudge. Reported as "move it" rather
                -- than "delete it", so acting on check 1 doesn't leave a duplicate.
                kind = 'misaligned'
            else
                kind = 'orphan'
            end
        end
        if kind then
            out.stray_first[#out.stray_first + 1] =
                { ppq = f.ppq, kind = kind, lt = lt, delta = delta }
        end
        prev_ppq = f.ppq
    end

    -- Cross-link the two checks: a change missing its [first] says so when a misplaced
    -- one was found nearby, so the report reads as one problem, not two.
    for _, s in ipairs(out.stray_first) do
        if s.kind == 'misaligned' then
            for _, m in ipairs(out.missing_first) do
                if lighting[m.idx] == s.lt then m.near_delta = s.delta end
            end
        end
    end

    ---- Checks 3 and 4: preset changes with no blend anchor before them ----
    -- Lighting and post proc are judged independently, exactly as EmitBlendDuplicates
    -- decides them. The very first event of a kind is exempt: there is no outgoing
    -- preset to restate ahead of it.
    local function ScanBlends(events, acc)
        for i = 2, #events do
            if events[i].msg ~= events[i - 1].msg then
                acc.changes = acc.changes + 1
                if IsBlendAnchor(events[i - 2], events[i - 1]) then
                    acc.anchored = acc.anchored + 1
                else
                    acc.missing[#acc.missing + 1] = {
                        ppq      = events[i].ppq,     msg      = events[i].msg,
                        from_ppq = events[i - 1].ppq, from_msg = events[i - 1].msg,
                    }
                end
            end
        end
    end
    ScanBlends(lighting, out.blend.lt)
    ScanBlends(postproc, out.blend.pp)

    return out
end

-- ---------------------------------------------------------------------------

function ValidateVenueLighting()
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

    -- Always read the WHOLE track, whatever the time selection: deciding whether an
    -- event is a change, and whether a blend anchor precedes it, needs the events
    -- before the selection. Only the reporting is scoped, further down.
    local lighting, postproc, firsts = {}, {}, {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evtype == 1 then
            -- Classified by the shared CategorizeVenueEvent (actions_venue_subtracks.lua)
            -- rather than re-deriving the patterns here.
            local cat = CategorizeVenueEvent(msg)
            if cat == 'lighting' then
                lighting[#lighting + 1] = { ppq = ppq, msg = msg }
            elseif cat == 'postproc' then
                postproc[#postproc + 1] = { ppq = ppq, msg = msg }
            elseif msg == '[first]' then
                firsts[#firsts + 1] = { ppq = ppq }
            end
        end
    end

    if #lighting == 0 and #postproc == 0 and #firsts == 0 then
        S.status      = 'VENUE has no lighting or post proc events.'
        S.last_result = 'The VENUE track has no [lighting*], *.pp] or [first] events to validate.'
        return
    end

    local by_ppq = function(a, b) return a.ppq < b.ppq end
    table.sort(lighting, by_ppq)
    table.sort(postproc, by_ppq)
    table.sort(firsts,   by_ppq)

    local ppq_per_qn = GetTakePPQPerQN(take)
    -- Same 1/128-note "on this tick" tolerance Manual gen's [first] gate uses, so both
    -- mean the same thing by it.
    local tol      = math.floor(ppq_per_qn / 32)
    local near_ppq = math.floor(ppq_per_qn * NEAR_FIRST_BEATS)

    local f = ValidateVenueLightingBlends(lighting, postproc, firsts, tol, near_ppq)

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
        f.missing_first     = Keep(f.missing_first)
        f.stray_first       = Keep(f.stray_first)
        f.blend.lt.missing  = Keep(f.blend.lt.missing)
        f.blend.pp.missing  = Keep(f.blend.pp.missing)
    end

    local function At(ppq) return FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, ppq)) end
    local function Beats(d) return ('%.2f beats'):format(math.abs(d) / ppq_per_qn) end

    local total = #f.missing_first + #f.stray_first
                  + #f.blend.lt.missing + #f.blend.pp.missing

    local lines = {}
    lines[#lines + 1] = total == 0
        and ('VENUE lighting validation - no issues  (%s)'):format(scope_label)
        or  ('VENUE lighting validation - %d issue%s  (%s)')
            :format(total, total == 1 and '' or 's', scope_label)
    lines[#lines + 1] = ''

    ---- Missing [first] ----
    if #f.missing_first == 0 then
        lines[#lines + 1] = 'Manual lighting changes missing a [first]: none.'
    else
        lines[#lines + 1] = ('Manual lighting changes missing a [first] (%d):'):format(#f.missing_first)
        for _, m in ipairs(f.missing_first) do
            local extra = m.near_delta
                and ('   - a [first] sits %s away, see below'):format(Beats(m.near_delta))
                or  ''
            lines[#lines + 1] = ('  %s   %s%s'):format(At(m.ppq), m.msg, extra)
        end
    end
    lines[#lines + 1] = ''

    ---- Stray [first] ----
    if #f.stray_first == 0 then
        lines[#lines + 1] = '[first] events off a lighting change: none.'
    else
        lines[#lines + 1] = ('[first] events off a lighting change (%d):'):format(#f.stray_first)
        for _, s in ipairs(f.stray_first) do
            local why, fix
            if s.kind == 'misaligned' then
                why = ('%s %s %s at %s'):format(
                    Beats(s.delta), s.delta > 0 and 'after' or 'before', s.lt.msg, At(s.lt.ppq))
                fix = 'move it onto that event'
            elseif s.kind == 'on_restatement' then
                why = ('on %s, which restates the preset already running (a blend anchor)')
                      :format(s.lt.msg)
                fix = 'delete it: only a preset change starts a keyframe train'
            elseif s.kind == 'on_auto' then
                why = ('on %s, an automatic preset that takes no keyframes'):format(s.lt.msg)
                fix = 'delete it'
            elseif s.kind == 'duplicate' then
                why = 'a second [first] on the same tick'
                fix = 'delete one'
            else
                why = 'no lighting event on this tick'
                fix = 'delete it'
            end
            lines[#lines + 1] = ('  %s   %s'):format(At(s.ppq), why)
            lines[#lines + 1] = ('           - %s'):format(fix)
        end
    end
    lines[#lines + 1] = ''

    ---- Blend anchors ----
    local function AppendBlend(label, acc)
        if #acc.missing == 0 then
            lines[#lines + 1] = ('%s changes with no blend anchor: none.'):format(label)
        else
            lines[#lines + 1] = ('%s changes with no blend anchor (%d):'):format(label, #acc.missing)
            for _, b in ipairs(acc.missing) do
                lines[#lines + 1] = ('  %s   %s  ->  %s'):format(At(b.ppq), b.from_msg, b.msg)
                lines[#lines + 1] = ('           - restate %s shortly before it (running since %s)')
                                    :format(b.from_msg, At(b.from_ppq))
            end
            -- A hard cut is a legitimate authoring choice, not a mistake - this list is
            -- "where a fade would need an anchor", not "where the track is wrong".
            lines[#lines + 1] = '  A hard cut is valid - only act on the ones you wanted to fade.'
        end
        lines[#lines + 1] = ''
    end
    AppendBlend('Lighting',  f.blend.lt)
    AppendBlend('Post proc', f.blend.pp)

    ---- Summary ----
    -- Always the whole track, even when the report above is scoped: the counts describe
    -- what was read, and reading everything is what makes the scoped findings correct.
    lines[#lines + 1] = 'Checked (whole track):'
    lines[#lines + 1] = ('  %d lighting events - %d preset changes, %d of them manual (need a [first])')
                        :format(#lighting, f.changes, f.manual_changes)
    lines[#lines + 1] = ('  %d [first] events'):format(#firsts)
    lines[#lines + 1] = ('  Lighting blends:  %d of %d changes anchored')
                        :format(f.blend.lt.anchored, f.blend.lt.changes)
    lines[#lines + 1] = ('  Post proc blends: %d of %d changes anchored')
                        :format(f.blend.pp.anchored, f.blend.pp.changes)

    S.status = total == 0
        and 'VENUE lighting: no issues found.'
        or  ('VENUE lighting: %d issue%s found.'):format(total, total == 1 and '' or 's')
    S.last_result = table.concat(lines, '\n')
end
