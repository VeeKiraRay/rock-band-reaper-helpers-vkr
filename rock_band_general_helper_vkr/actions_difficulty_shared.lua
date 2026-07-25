-- Cross-difficulty sanity checks shared by all four difficulty validation
-- modules (Pro Keys, Keys, Guitar/Bass, Drums). Compares the difficulty
-- being validated ("lower") against its immediately higher adjacent tier
-- (Hard vs Expert, Medium vs Hard, Easy vs Medium) - never always-vs-Expert.
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
