-- VENUE lighting/post-proc validation: keyframe events with no effect, and blend anchors.
-- Read-only - never writes to the track, never opens an undo block.
-- Requires: FindNamedTrackMIDI, GetTakePPQPerQN, CategorizeVenueEvent,
--           MANUAL_LIGHTING_SET, IsBlendAnchor, FormatTime, GetTimeSelection,
--           VENUE_KEYFRAME_TYPO, r, S (globals)
--
-- Checked here, read back off the track:
--   keyframes  [first] / [next] / [prev] that do nothing in game (KeyframeNoEffect
--            below) - listed as advice, not counted as issues: they are harmless.
--   blend    a preset change reads as a soft fade only when the OUTGOING preset is
--            restated shortly before it. That restatement is the anchor - the same
--            duplicate EmitBlendDuplicates emits from lightpreset_blendin /
--            postproc_blendin, and the same one Manual gen's Blend button places.

-- ---------------------------------------------------------------------------
-- Keyframe events with no effect. How the game treats [first] / [next] / [prev]
-- (LightPreset / LightPresetManager, read from the RB3 decompilation):
--   - a preset change always starts the new preset on its first look (keyframe 0);
--     restating the running preset does not restart it;
--   - [first] goes to the first look, [next] / [prev] one look on / back, and manual
--     presets loop; [first] while already on the first look does nothing;
--   - only the manual presets (MANUAL_LIGHTING_SET: verse, chorus, manual_cool,
--     manual_warm, dischord, stomp) react; every other preset ignores them.
-- Not judged: a [next] / [prev] on the change tick itself. The new preset starts when
-- the fade into it starts, which with a blend anchor is before the tick, so such an
-- event may well count.

local KEYFRAME_STEPS = { ['[next]'] = true, ['[prev]'] = true }

-- Does the keyframe event `text` at `ppq` do nothing? Pure.
--   lighting  sorted {ppq=, msg=} of every lighting event (same tick units as ppq)
--   keys      sorted {ppq=, msg=} of the keyframe events around it (the judged event
--             itself may be in the list - only [next] / [prev] are read from it)
--   tol       ticks that still count as "on the same tick"
-- Returns nil when it has an effect, else kind, lt:
--   'no_preset'    before the first lighting event - nothing is running yet
--   'ignored'      the running preset (lt) ignores keyframe events
--   'first_look'   a [first] with no [next] / [prev] since its preset (lt) started:
--                  still on the first look. Covers a [first] on the change tick.
function KeyframeNoEffect(text, ppq, lighting, keys, tol)
    tol = tol or 0
    local idx
    for i, ev in ipairs(lighting) do
        if ev.ppq <= ppq + tol then idx = i else break end
    end
    if not idx then return 'no_preset' end
    local lt = lighting[idx]
    if not MANUAL_LIGHTING_SET[lt.msg] then return 'ignored', lt end
    if text ~= '[first]' then return nil end
    -- The preset's start: restatements before it do not restart it.
    local start = idx
    while start > 1 and lighting[start - 1].msg == lt.msg do start = start - 1 end
    local start_ppq = lighting[start].ppq
    for _, k in ipairs(keys) do
        -- Any step from the preset's own tick on (it may count, see above) up to just
        -- before this [first] may have moved the look.
        if KEYFRAME_STEPS[k.msg] and k.ppq >= start_ppq - tol and k.ppq < ppq - tol then
            return nil
        end
    end
    return 'first_look', lighting[start]
end

-- One-line reason for a KeyframeNoEffect finding, for Manual gen's "(does nothing
-- here)" hover and Add result (both already say that it does nothing).
function KeyframeNoEffectReason(kind, text, lt)
    if kind == 'no_preset' then
        return 'It is before the first lighting event - no preset is running yet.'
    elseif kind == 'ignored' then
        return ('%s ignores keyframe events - only verse, chorus, manual_cool, manual_warm, ' ..
                'dischord and stomp use them.'):format(lt.msg)
    end
    return ('%s is still on its first look - a lighting preset always starts on it, and ' ..
            'no [next] / [prev] has moved it since.'):format(lt.msg)
end

-- ---------------------------------------------------------------------------

-- The whole validation, as a pure function over three sorted arrays of {ppq=, msg=}:
-- lighting events, post proc events and keyframe events ([first] / [next] / [prev]).
-- No REAPER calls, so the rules can be tested against hand-built event lists without a
-- project - same discipline as ResolveBlendSource.
--
--   tol       ticks either side of an event that still count as "on this tick"
--
-- Returns a findings table; every list is empty when the track is clean.
function ValidateVenueLightingBlends(lighting, postproc, keys, tol)
    tol = tol or 0

    local out = {
        no_effect      = {},   -- { ppq=, msg=, kind=, lt= } - advisory, not issues
        blend          = {
            lt = { missing = {}, changes = 0, anchored = 0 },
            pp = { missing = {}, changes = 0, anchored = 0 },
        },
        changes        = 0,    -- lighting preset changes, including the first event
        manual_changes = 0,    -- of those, the manual presets (the ones keyframes drive)
    }

    -- A lighting event is a preset CHANGE when it differs from the one immediately
    -- before it; the first event on the track always is one. Only ADJACENT events are
    -- compared, so two sections sharing a preset with a different one between them are
    -- each a real change.
    for i, ev in ipairs(lighting) do
        if i == 1 or lighting[i - 1].msg ~= ev.msg then
            out.changes = out.changes + 1
            if MANUAL_LIGHTING_SET[ev.msg] then out.manual_changes = out.manual_changes + 1 end
        end
    end

    ---- Keyframe events that do nothing (KeyframeNoEffect) ----
    for _, k in ipairs(keys) do
        local kind, lt = KeyframeNoEffect(k.msg, k.ppq, lighting, keys, tol)
        if kind then
            out.no_effect[#out.no_effect + 1] = { ppq = k.ppq, msg = k.msg, kind = kind, lt = lt }
        end
    end

    ---- Preset changes with no blend anchor before them ----
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
    local lighting, postproc, keys = {}, {}, {}
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
            elseif cat == 'keyframe' and msg ~= VENUE_KEYFRAME_TYPO then
                -- [previous] is not a game event at all; the vocabulary check says so
                keys[#keys + 1] = { ppq = ppq, msg = msg }
            end
        end
    end

    if #lighting == 0 and #postproc == 0 and #keys == 0 then
        S.status      = 'VENUE has no lighting or post proc events.'
        S.last_result = 'The VENUE track has no lighting, post proc or keyframe events to validate.'
        return
    end

    local by_ppq = function(a, b) return a.ppq < b.ppq end
    table.sort(lighting, by_ppq)
    table.sort(postproc, by_ppq)
    table.sort(keys,     by_ppq)

    local ppq_per_qn = GetTakePPQPerQN(take)
    -- Same 1/128-note "on this tick" tolerance Manual gen uses, so both mean the same
    -- thing by it.
    local tol = math.floor(ppq_per_qn / 32)

    local f = ValidateVenueLightingBlends(lighting, postproc, keys, tol)

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
        f.no_effect         = Keep(f.no_effect)
        f.blend.lt.missing  = Keep(f.blend.lt.missing)
        f.blend.pp.missing  = Keep(f.blend.pp.missing)
    end

    local function At(ppq) return FormatTime(r.MIDI_GetProjTimeFromPPQPos(take, ppq)) end

    -- Keyframe events with no effect are advice, not issues: they are harmless.
    local total = #f.blend.lt.missing + #f.blend.pp.missing

    local lines = {}
    lines[#lines + 1] = total == 0
        and ('VENUE lighting validation - no issues  (%s)'):format(scope_label)
        or  ('VENUE lighting validation - %d issue%s  (%s)')
            :format(total, total == 1 and '' or 's', scope_label)
    lines[#lines + 1] = ''

    ---- Keyframe events with no effect (advice, not counted as issues) ----
    if #f.no_effect == 0 then
        lines[#lines + 1] = 'Keyframe events with no effect: none.'
    else
        lines[#lines + 1] = ('Keyframe events with no effect (%d) - harmless, not counted as issues:')
                            :format(#f.no_effect)
        for _, k in ipairs(f.no_effect) do
            local why
            if k.kind == 'no_preset' then
                why = 'before the first lighting event'
            elseif k.kind == 'ignored' then
                why = ('under %s, which ignores keyframe events'):format(k.lt.msg)
            else
                why = ('%s is still on its first look'):format(k.lt.msg)
            end
            lines[#lines + 1] = ('  %s   %s  -  %s'):format(At(k.ppq), k.msg, why)
        end
        lines[#lines + 1] = '  Only verse, chorus, manual_cool, manual_warm, dischord and stomp use ' ..
                            'keyframe events, and'
        lines[#lines + 1] = '  a preset always starts on its first look, so a [first] before any ' ..
                            '[next] does nothing.'
        lines[#lines + 1] = '  Keyframes > Regenerate rewrites the manual presets\' keyframes ' ..
                            '(and drops a [first] on their own tick).'
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
    lines[#lines + 1] = ('  %d lighting events - %d preset changes, %d of them manual (keyframes drive them)')
                        :format(#lighting, f.changes, f.manual_changes)
    lines[#lines + 1] = ('  %d keyframe events'):format(#keys)
    lines[#lines + 1] = ('  Lighting blends:  %d of %d changes anchored')
                        :format(f.blend.lt.anchored, f.blend.lt.changes)
    lines[#lines + 1] = ('  Post proc blends: %d of %d changes anchored')
                        :format(f.blend.pp.anchored, f.blend.pp.changes)

    S.status = total == 0
        and 'VENUE lighting: no issues found.'
        or  ('VENUE lighting: %d issue%s found.'):format(total, total == 1 and '' or 's')
    if #f.no_effect > 0 then
        S.status = S.status:gsub('%.$', '') ..
                   (' (%d keyframe event%s with no effect).'):format(#f.no_effect, #f.no_effect == 1 and '' or 's')
    end
    S.last_result = table.concat(lines, '\n')
end
