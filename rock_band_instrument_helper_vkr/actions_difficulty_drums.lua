-- Drums difficulty validation and copy-to-next-tier tools. The checks themselves, the
-- tier reader and the rule thresholds live in actions_difficulty_drums_checks.lua
-- (CollectDrumsChecks), shared with Difficulty > Generate.
-- Requires: S, r, GetTimeSelection, FormatTime, PitchName, FindFirstMIDIItem, InsertNotes,
--           ClearNotesInRange, CompressChordOffsets, CheckDifficultyProgression,
--           BuildDiffCheckReport, DRUMS_RANGE, ReadDrumsTierEvents, CollectDrumsChecks (globals)

local DIFF_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

local DIFF_BY_MIX_IDX = { [0] = 'Easy', [1] = 'Medium', [2] = 'Hard', [3] = 'Expert' }

-- Immediately-higher adjacent tier, for the cross-difficulty progression
-- check (CheckDifficultyProgression in actions_difficulty_shared.lua).
local ADJACENT_HIGHER = { H = 'X', M = 'H', E = 'M' }

-- Sum of individual notes across all chord events (not chord/event count).
local function CountNotes(events)
    local n = 0
    for _, ev in ipairs(events) do n = n + #ev.pitches end
    return n
end

----------------------------------------------------------------------
-- Cross-tier checks (need the tier above, so not part of CollectDrumsChecks)
----------------------------------------------------------------------

-- Hard only: Hard should have fewer kicks than Expert (Medium/Easy already
-- have their own distinct/stronger kick rules, so this isn't cascaded).
local function CheckDrumsKickCountVsHigher(events, higher_events, offset_rng, higher_offset_rng)
    local function KickCount(evs, rng)
        local n = 0
        for _, ev in ipairs(evs) do
            for _, p in ipairs(ev.pitches) do
                if p - rng.lo == 0 then n = n + 1 end
            end
        end
        return n
    end
    local higher_kicks = KickCount(higher_events, higher_offset_rng)
    if higher_kicks == 0 then return {} end
    local lower_kicks = KickCount(events, offset_rng)
    if lower_kicks < higher_kicks then return {} end
    return {
        ('Hard has %d kicks and Expert has %d kicks - Hard should have fewer kicks than Expert'):format(
            lower_kicks, higher_kicks),
    }
end

-- Hard only: the Hard-tier (diff_idx==2) [mix N drums<config>] event should
-- use the un-flipped/base config, not the disco ("d") variant - on Hard,
-- disco beats are charted as a normal 8-beat.
local function CheckDrumsDiscoUnflip(track, sel_s, sel_e)
    local issues = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textsyxevtcnt = r.MIDI_CountEvts(take)
            for j = 0, textsyxevtcnt - 1 do
                local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and evtype == 1 then
                    local mix_idx, cfg, suffix = msg:match('%[mix (%d+) drums(%d)(%a*)%]')
                    if mix_idx and tonumber(mix_idx) == 2 then
                        local s = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
                        if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                            if suffix == 'd' then
                                issues[#issues + 1] = ('%s: Hard mix event uses the disco variant (drums%sd) - Hard should use the un-flipped/base config (drums%s or drums%snoflip)'):format(
                                    FormatTime(s), cfg, cfg, cfg)
                            end
                        end
                    end
                end
            end
        end
    end
    return issues
end

-- Informational scan of [mix <difficulty 0-3> drums<config>] text/sysex events.
-- Not a pass/fail check: whether a given disco-flip configuration is correct
-- depends on the surrounding beat pattern, which can't be judged from note
-- data alone. Reports which difficulty tiers have a mix event authored.
local function ScanDiscoFlipStatus(track, sel_s, sel_e)
    local found = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textsyxevtcnt = r.MIDI_CountEvts(take)
            for j = 0, textsyxevtcnt - 1 do
                local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and evtype == 1 then
                    local mix_idx, cfg, suffix = msg:match('%[mix (%d+) drums(%d)(%a*)%]')
                    if mix_idx then
                        local s = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
                        if (not sel_s or s >= sel_s - 0.001) and (not sel_e or s < sel_e + 0.001) then
                            found[#found + 1] = {
                                s = s, diff_idx = tonumber(mix_idx), cfg = cfg, suffix = suffix,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.s < b.s end)

    if #found == 0 then
        return 'Disco flip: no [mix N drums...] events found on this track.'
    end
    local lines = { 'Disco flip status (informational only - not pass/fail):' }
    for _, f in ipairs(found) do
        local diff_name = DIFF_BY_MIX_IDX[f.diff_idx] or ('idx ' .. f.diff_idx)
        lines[#lines + 1] = ('  %s: mix %d drums%s%s (%s)'):format(
            FormatTime(f.s), f.diff_idx, f.cfg, f.suffix, diff_name)
    end
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Authoring hints - qualitative/subjective source rules that can't become a
-- deterministic pass/fail check. Always shown, never counted as an issue.
----------------------------------------------------------------------

local DRUMS_HINTS = {
    H = {
        'Try removing kicks from adjacent 8th or 16th notes.',
        'In a section filled with little snare accents, remove about half of them.',
        'Trim a note or two from the start of a fast roll.',
        'Reduce hand motion: if a crash happens right after a snare flam (Red+Yellow), consider making the flam a one-handed snare hit instead.',
    },
    M = {
        'It is usually best to reduce triplets to quarter notes.',
    },
    E = {
        'Favor crash (Green) over kick when simplifying a beat.',
    },
}

local function DrumsAuthoringHints(diff_label)
    local hints = DRUMS_HINTS[diff_label]
    if not hints or #hints == 0 then return '' end
    local lines = { 'Authoring hints (suggestions, not hard rules):' }
    for _, h in ipairs(hints) do
        lines[#lines + 1] = '  \xe2\x80\xa2 ' .. h
    end
    return table.concat(lines, '\n') .. '\n\n'
end

----------------------------------------------------------------------
-- Report and validation runner
----------------------------------------------------------------------

-- upper_events: the tier above as hit events (nil for Expert) - see CollectDrumsChecks.
local function RunDrumsChecks(diff_label, events, header, track, sel_s, sel_e, upper_events)
    return BuildDiffCheckReport(header, CollectDrumsChecks(diff_label, events, track, sel_s, sel_e, upper_events))
end

----------------------------------------------------------------------
-- Global action functions
----------------------------------------------------------------------

-- Validate notes in the diff_label pitch range on PART DRUMS.
function ValidateDrumsDiff(diff_label)
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local rng              = DRUMS_RANGE[diff_label]
    local sel_s, sel_e     = GetTimeSelection()
    local events, n_notes  = ReadDrumsTierEvents(track, diff_label, sel_s, sel_e)
    local higher_dl        = ADJACENT_HIGHER[diff_label]
    local higher_events    = higher_dl and ReadDrumsTierEvents(track, higher_dl, sel_s, sel_e) or nil

    if n_notes == 0 then
        S.status = ('Validate Drums %s: no notes in %s-%s (%d-%d).'):format(
            diff_label, PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi)
        S.last_result = sel_s
            and ('No %s notes (%s-%s) in the current time selection.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
            or  ('No %s notes (%s-%s) on PART DRUMS track.'):format(
                DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi))
        return
    end

    local scope  = sel_s and ' [time selection]' or ''
    local header = ('Drums %s Validation  [%s-%s, %d-%d]%s'):format(
        DIFF_NAMES[diff_label], PitchName(rng.lo), PitchName(rng.hi), rng.lo, rng.hi, scope)
    local report, total = RunDrumsChecks(diff_label, events, header, track, sel_s, sel_e, higher_events)

    -- Cross-difficulty progression check (vs the immediately higher tier),
    -- plus the Hard-only kick-count and disco-unflip checks that reuse the
    -- same higher-tier data.
    if higher_dl then
        local higher_rng    = DRUMS_RANGE[higher_dl]
        local block, extra = CheckDifficultyProgression(
            DIFF_NAMES[diff_label], DIFF_NAMES[higher_dl],
            events, higher_events, rng.lo, higher_rng.lo,
            CountNotes(events), CountNotes(higher_events))
        report = block .. report
        total  = total + extra

        if diff_label == 'H' then
            local kick_issues = CheckDrumsKickCountVsHigher(events, higher_events, rng, higher_rng)
            if #kick_issues > 0 then
                report = report .. table.concat(kick_issues, '\n') .. '\n\n'
                total  = total + #kick_issues
            end
            local unflip_issues = CheckDrumsDiscoUnflip(track, sel_s, sel_e)
            if #unflip_issues > 0 then
                report = report .. table.concat(unflip_issues, '\n') .. '\n\n'
                total  = total + #unflip_issues
            end
        end
    end

    report = report .. DrumsAuthoringHints(diff_label)
    report = report .. ScanDiscoFlipStatus(track, sel_s, sel_e)

    if total == 0 then
        S.status = ('Validate Drums %s: all checks passed%s.'):format(diff_label, scope)
    else
        S.status = ('Validate Drums %s: %d issue%s found%s.'):format(
            diff_label, total, total == 1 and '' or 's', scope)
    end
    S.last_result = report
end

-- Validate all four difficulty ranges on PART DRUMS in a combined report.
function ValidateAllDrums()
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local scope         = sel_s and ' [time selection]' or ''
    local diff_order    = { 'X', 'H', 'M', 'E' }
    local all_lines     = { ('Drums Validate All%s'):format(scope), '' }
    local summary       = {}

    -- Carried forward from the previous (higher) tier for the cross-difficulty
    -- progression check - avoids re-reading a range already read this loop.
    local prev_dl, prev_events, prev_count = nil, {}, 0

    for _, dl in ipairs(diff_order) do
        local rng             = DRUMS_RANGE[dl]
        local events, n_notes = ReadDrumsTierEvents(track, dl, sel_s, sel_e)

        if n_notes == 0 then
            summary[#summary + 1] = dl .. ':empty'
            all_lines[#all_lines + 1] = ('=== %s ===  (no notes in range %d-%d)'):format(
                DIFF_NAMES[dl], rng.lo, rng.hi)
            all_lines[#all_lines + 1] = ''
            prev_dl, prev_events, prev_count = dl, {}, 0
        else
            local header        = ('=== Drums %s  [%d-%d] ==='):format(DIFF_NAMES[dl], rng.lo, rng.hi)
            local upper = dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] and prev_events or nil
            local report, total = RunDrumsChecks(dl, events, header, track, sel_s, sel_e, upper)

            if dl ~= 'X' and prev_dl == ADJACENT_HIGHER[dl] then
                local block, extra = CheckDifficultyProgression(
                    DIFF_NAMES[dl], DIFF_NAMES[prev_dl],
                    events, prev_events, rng.lo, DRUMS_RANGE[prev_dl].lo,
                    CountNotes(events), prev_count)
                report = block .. report
                total  = total + extra

                if dl == 'H' then
                    local kick_issues = CheckDrumsKickCountVsHigher(events, prev_events, rng, DRUMS_RANGE[prev_dl])
                    if #kick_issues > 0 then
                        report = report .. table.concat(kick_issues, '\n') .. '\n\n'
                        total  = total + #kick_issues
                    end
                    local unflip_issues = CheckDrumsDiscoUnflip(track, sel_s, sel_e)
                    if #unflip_issues > 0 then
                        report = report .. table.concat(unflip_issues, '\n') .. '\n\n'
                        total  = total + #unflip_issues
                    end
                end
            end

            report = report .. DrumsAuthoringHints(dl)

            summary[#summary + 1] = total == 0 and (dl .. ':OK') or ('%s:%d'):format(dl, total)
            for line in (report .. '\n'):gmatch('([^\n]*)\n') do
                all_lines[#all_lines + 1] = line
            end
            prev_dl, prev_events, prev_count = dl, events, CountNotes(events)
        end
    end

    all_lines[#all_lines + 1] = ScanDiscoFlipStatus(track, sel_s, sel_e)

    S.status      = ('Validate All Drums%s: %s'):format(scope, table.concat(summary, ' | '))
    S.last_result = table.concat(all_lines, '\n')
end

-- Copy notes from the immediately higher tier's range onto diff_label's own
-- range on PART DRUMS. Every Drums tier has the same 5 lanes (hi-lo=4
-- always), so CompressChordOffsets is a no-op here - included anyway for
-- consistency with Keys/Guitar-Bass's copy functions.
-- force: skip the "target already has notes" confirmation and overwrite
-- directly (set true when called again from the confirm popup).
function CopyDrumsDiff(diff_label, force)
    if S.diff_drums_idx < 0 then
        S.status      = 'Error: PART DRUMS track not selected.'
        S.last_result = 'Select the PART DRUMS track in the Difficulty \xe2\x86\x92 Drums tab.'
        return
    end
    local track = r.GetTrack(0, S.diff_drums_idx)
    if not track then
        S.status      = 'Error: PART DRUMS track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local src_dl = ADJACENT_HIGHER[diff_label]
    if not src_dl then
        S.status = 'Copy: unknown difficulty ' .. tostring(diff_label)
        return
    end

    local src_rng, tgt_rng = DRUMS_RANGE[src_dl], DRUMS_RANGE[diff_label]
    local sel_s, sel_e = GetTimeSelection()
    local src_events, n_src = ReadDrumsTierEvents(track, src_dl, sel_s, sel_e)

    if n_src == 0 then
        S.status      = ('Copy to %s: no notes on %s to copy.'):format(DIFF_NAMES[diff_label], DIFF_NAMES[src_dl])
        S.last_result = ('%s range (%d-%d) has no notes%s.'):format(
            DIFF_NAMES[src_dl], src_rng.lo, src_rng.hi, sel_s and ' in the current time selection' or '')
        return
    end

    local _, n_tgt = ReadDrumsTierEvents(track, diff_label, sel_s, sel_e)
    if n_tgt > 0 and not force then
        S.diff_copy_pending = {
            message = ('%s range already has notes. Clear them and overwrite with a copy of %s?'):format(
                DIFF_NAMES[diff_label], DIFF_NAMES[src_dl]),
            on_confirm = function() CopyDrumsDiff(diff_label, true) end,
        }
        return
    end

    local item, take = FindFirstMIDIItem(track)
    if not item then
        S.status      = 'Error: PART DRUMS track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART DRUMS track first.'
        return
    end

    local clear_s = sel_s or 0
    local clear_e = sel_e or (r.GetMediaItemInfo_Value(item, 'D_POSITION') + r.GetMediaItemInfo_Value(item, 'D_LENGTH'))

    local target_max_offset = tgt_rng.hi - tgt_rng.lo
    local out_notes = {}
    for _, ev in ipairs(src_events) do
        local offsets = {}
        for _, p in ipairs(ev.pitches) do offsets[#offsets + 1] = p - src_rng.lo end
        local new_offsets = CompressChordOffsets(offsets, target_max_offset)
        for _, o in ipairs(new_offsets) do
            out_notes[#out_notes + 1] = { s = ev.s, e = ev.e, pitch = tgt_rng.lo + o }
        end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(track, item)
    ClearNotesInRange(take, clear_s, clear_e, tgt_rng.lo, tgt_rng.lo + 4)
    InsertNotes(take, out_notes, 100)
    r.Undo_EndBlock2(0, ('Copy Drums %s to %s'):format(src_dl, diff_label), -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status      = ('Copy to %s: copied %d notes from %s.'):format(DIFF_NAMES[diff_label], #out_notes, DIFF_NAMES[src_dl])
    S.last_result = nil
end
