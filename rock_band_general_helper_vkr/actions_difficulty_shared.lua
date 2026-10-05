-- Cross-difficulty sanity checks shared by all four difficulty validation
-- modules (Pro Keys, Keys, Guitar/Bass, Drums). Compares the difficulty
-- being validated ("lower") against its immediately higher adjacent tier
-- (Hard vs Expert, Medium vs Hard, Easy vs Medium) - never always-vs-Expert.
-- Also holds what the per-instrument checks share: the DiffIssue record and
-- the report builder that turns check categories into Validate's text.
-- Requires: nothing (pure functions, no S/r access)

-- Same event count, and every event's start/end time within ~5ms and
-- normalized pitch-offset shape exactly matching, means the lower tier is an
-- unedited copy of the higher one (e.g. Expert notes octave-shifted down
-- with no reduction actually authored).
local function ChartsAreIdentical(lower_events, higher_events, lower_lo, higher_lo)
    if #lower_events ~= #higher_events then return false end
    for i = 1, #lower_events do
        local a, b = lower_events[i], higher_events[i]
        if math.abs(a.s - b.s) > 0.005 or math.abs(a.e - b.e) > 0.005 then return false end
        if #a.pitches ~= #b.pitches then return false end
        for k = 1, #a.pitches do
            if (a.pitches[k] - lower_lo) ~= (b.pitches[k] - higher_lo) then return false end
        end
    end
    return true
end

-- lower_events/higher_events: grouped {s, e, pitches[]} arrays (already
--   produced by each module's own Group*Events function), sorted by time.
-- lower_lo/higher_lo: pitch offset to subtract before comparing shape
--   (pass the same constant for both, e.g. PK_MIN, when a module's range
--   doesn't shift between difficulties; range.lo otherwise).
-- lower_count/higher_count: total individual note count (sum of chord sizes
--   across all events - not chord/event count).
-- Returns (block_text, extra_issues): block_text is 0-2 lines ending in a
-- blank line, meant to be prepended right after the report header;
-- extra_issues is how much to add to the caller's issue total.
function CheckDifficultyProgression(lower_label, higher_label,
                                     lower_events, higher_events,
                                     lower_lo, higher_lo,
                                     lower_count, higher_count)
    local lines, extra = {}, 0

    if #higher_events > 0 and #lower_events > 0 then
        if ChartsAreIdentical(lower_events, higher_events, lower_lo, higher_lo) then
            lines[#lines + 1] = ('%s appears to be an unchanged copy of %s (%d identical notes, same timing and shape) - some reduction is expected between difficulties'):format(
                lower_label, higher_label, lower_count)
            extra = extra + 1
        end
    end

    if higher_count > 0 then
        if lower_count < higher_count then
            lines[#lines + 1] = ('%s has %d notes and %s has %d notes: OK'):format(
                higher_label, higher_count, lower_label, lower_count)
        else
            lines[#lines + 1] = ('%s has %d notes and %s has %d notes: NOT REDUCED (expected fewer than %s)'):format(
                higher_label, higher_count, lower_label, lower_count, higher_label)
            extra = extra + 1
        end
    end

    if #lines == 0 then return '', 0 end
    return table.concat(lines, '\n') .. '\n\n', extra
end

-- Minimum gap, in quarter notes, between the end of a sustained note (1/8 note or
-- longer) and the next note on Medium and Easy - shared by Keys and Guitar/Bass.
--
-- Measured, not taken from the RBN docs' "try and leave a quarter note". Over every
-- official RB3 DLC chart (dev/calibration/run_difficulty_probe_vkr.lua, mode 'all':
-- 480 guitar, 483 bass, 352 keys) Harmonix follows the docs' method instead - pull
-- every sustain back by an 8th - so on Medium a 1/8 release gap is the commonest one
-- and a 1/4 rule fired on 50-88% of official charts. Under 1/8 is rare: about 1-2% of
-- gaps on Medium and under 1% on Easy, except Medium at 100 BPM or slower, where 1/16
-- gaps reach 5-8%. A reducer can still aim for the quarter note; this is the floor.
DIFF_RELEASE_GAP_QN      = { M = 0.5, E = 0.5 }
DIFF_RELEASE_GAP_SLOW_QN = { M = 0.25 }  -- at or below DIFF_SLOW_BPM
DIFF_SLOW_BPM            = 100

-- The release gap for diff_label at tempo bpm, or nil when the tier has no such rule.
function DiffReleaseGapQN(diff_label, bpm)
    if bpm and bpm <= DIFF_SLOW_BPM and DIFF_RELEASE_GAP_SLOW_QN[diff_label] then
        return DIFF_RELEASE_GAP_SLOW_QN[diff_label]
    end
    return DIFF_RELEASE_GAP_QN[diff_label]
end

-- A quarter-note length as the note value report lines name it.
local QN_LABELS = { [0.25] = '1/16 note', [0.5] = '1/8 note', [1.0] = '1/4 note', [2.0] = '1/2 note' }
function DiffQNLabel(qn)
    return QN_LABELS[qn] or ('%.2f beats'):format(qn)
end

-- Category heading for the Medium/Easy sustain-gap rule, built from the table above
-- so the heading cannot disagree with the threshold.
function DiffReleaseGapName(diff_label)
    local name = ('Sustain gaps (min %s gap to next'):format(DiffQNLabel(DIFF_RELEASE_GAP_QN[diff_label]))
    local slow = DIFF_RELEASE_GAP_SLOW_QN[diff_label]
    if slow then
        name = name .. (', %s at <=%d BPM'):format(DiffQNLabel(slow), DIFF_SLOW_BPM)
    end
    return name .. ')'
end

-- One issue found by a difficulty check. Checks return arrays of these rather
-- than bare strings, so the same rule can be counted per rule (the corpus
-- probe) or acted on (the Generate planners) without parsing report text.
--   s       - project time the issue is reported at (also the time in msg)
--   pitches - the gem pitches involved, sorted ascending
--   msg     - the report line, exactly as Validate prints it
--   extra   - optional table of check-specific fields copied onto the record
--             (e.g. prev_s, the start of the sustain a gap rule measured from)
function DiffIssue(s, pitches, msg, extra)
    local rec = { s = s, pitches = pitches, msg = msg }
    if extra then
        for k, v in pairs(extra) do rec[k] = v end
    end
    return rec
end

-- Report text for one tier's check categories. Each category is
-- { name, rule, issues = { DiffIssue... }, advisory = bool? }; rule is a stable
-- id for counting, name is the heading Validate prints.
-- Returns (report_text, total_issue_count). Advisory categories still count
-- toward the total, as they always have.
function BuildDiffCheckReport(header, cats)
    local lines = { header, '' }
    local total = 0
    local ok_cats = {}
    for _, cat in ipairs(cats) do
        if #cat.issues > 0 then
            lines[#lines + 1] = cat.name .. ':'
            for _, issue in ipairs(cat.issues) do
                lines[#lines + 1] = '  ' .. issue.msg
                total = total + 1
            end
            lines[#lines + 1] = ''
        else
            ok_cats[#ok_cats + 1] = cat.name
        end
    end
    if total == 0 then
        lines[#lines + 1] = 'No issues found.'
        lines[#lines + 1] = ''
    elseif #ok_cats > 0 then
        lines[#lines + 1] = 'Passed: ' .. table.concat(ok_cats, ', ')
        lines[#lines + 1] = ''
    end
    return table.concat(lines, '\n'), total
end

-- Keys and Guitar/Bass narrow their gem count at Medium/Easy (Green/Red/
-- Yellow/Blue/Orange all exist at every tier internally - RBN convention
-- just avoids the upper colors on the easier tiers, it's not an engine
-- limit). CopyKeys5Diff/CopyGtrBassDiff use this when copying a chord down
-- to a tier whose convention doesn't reach as high a color: a single note or
-- 2-note chord is shifted down as a whole (preserving its interval) when
-- that keeps every note >= offset 0; otherwise (3+ note chords, or a 2-note
-- chord that would go negative), any note above the target's ceiling is
-- simply dropped.
-- offsets: sorted-ascending array of gem offsets (pitch - source range.lo)
-- for one chord event. target_max_offset: highest allowed offset for the
-- target tier (target range.hi - target range.lo). Returns the new offsets
-- array (still sorted ascending, still relative - caller re-bases to the
-- target range's own lo).
function CompressChordOffsets(offsets, target_max_offset)
    local max_o = offsets[#offsets]
    if max_o <= target_max_offset then return offsets end

    local shift = max_o - target_max_offset
    if #offsets <= 2 and (offsets[1] - shift) >= 0 then
        local shifted = {}
        for i, o in ipairs(offsets) do shifted[i] = o - shift end
        return shifted
    end

    local kept = {}
    for _, o in ipairs(offsets) do
        if o <= target_max_offset then kept[#kept + 1] = o end
    end
    return kept
end
