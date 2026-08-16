-- The difficulty suggestion as pasteable text.
--
-- PURE: no r.*, no S, no ctx. Consumes only records DifficultyAnnotate has already filled
-- in, so dev/tests drives it with hand-built tables and the UI layer is a single
-- SetClipboardText call.
--
-- WHY THIS EXISTS. Recording a suggestion for discussion meant transcribing it by hand,
-- and the drum model has 26 factors. The hand-copied set that prompted this arrived with
-- one row missing - detectable only because the remaining 25 happened to reproduce the
-- reported rank to within 5 points. A copy button removes that whole class of error.
--
-- ALIGNED PLAIN TEXT, NOT MARKDOWN. This gets pasted into forum posts, text files, REAPER's
-- own console and chat windows. Aligned monospace reads correctly in all of them; a
-- markdown table reads correctly only where something renders it, and degrades into
-- pipe-and-dash noise everywhere else.
--
-- IT ALWAYS INCLUDES THE FULL FACTOR TABLE, whether or not the UI is currently showing it.
-- Producing those numbers for someone else to read is the entire purpose; a report that
-- honoured the on-screen toggle would silently copy less than the author expected.

local WRAP_AT = 78          -- warnings and notes are full sentences; keep lines readable
local INDENT  = '    '

----------------------------------------------------------------------
-- Small text helpers
----------------------------------------------------------------------

-- Greedy wrap. Long enough for the concentration and clamp notes, which are the only
-- multi-sentence strings that reach this file.
local function Wrap(text, width, indent)
    local out, line = {}, nil
    for word in tostring(text):gmatch('%S+') do
        if not line then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. ' ' .. word
        else
            out[#out + 1] = line
            line = word
        end
    end
    if line then out[#out + 1] = line end
    for i = 2, #out do out[i] = indent .. out[i] end
    return table.concat(out, '\n')
end

-- Right-pad without a trailing run of spaces at end of line: the caller appends the value
-- columns, and any line that ends here gets trimmed by Emit instead.
local function Pad(s, w)
    s = tostring(s)
    if #s >= w then return s end
    return s .. (' '):rep(w - #s)
end

----------------------------------------------------------------------
-- The report
----------------------------------------------------------------------

-- recs: the list SuggestProjectDifficulties returned, already annotated.
-- opts.project: optional project name for the header.
--
-- Always returns a string. An empty list produces a header and a "nothing scored" line
-- rather than nil, so the caller never has to decide whether there was anything to copy.
function DifficultyReportText(recs, opts)
    recs = recs or {}
    opts = opts or {}

    local lines = {}
    local function Emit(s)
        -- Trailing whitespace survives a clipboard round trip and shows up as ragged
        -- lines in whatever this is pasted into.
        lines[#lines + 1] = (s or ''):gsub('%s+$', '')
    end

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    local title = 'Rock Band difficulty suggestions'
    if opts.project and opts.project ~= '' then title = title .. ' - ' .. opts.project end
    Emit(title)
    Emit(Wrap('Advisory only. Estimated from the chart measurements; official and player '
           .. 'judgments can differ.', WRAP_AT, ''))
    -- Provenance. The keys model changed twice in one week, so a report pasted into a
    -- discussion has to be identifiable as pre- or post-change without guesswork.
    Emit(('Model artifact: schema %s'):format(tostring(RB_DIFFICULTY_MODELS_SCHEMA)))

    if #recs == 0 then
        Emit('')
        Emit('No parts scored.')
        return table.concat(lines, '\n')
    end

    ------------------------------------------------------------------
    -- One column width for every block
    --
    -- Measured across ALL instruments rather than per block, so the tables line up with
    -- each other down the report. Comparing two instruments is most of what this is for,
    -- and per-block widths would stagger them exactly where that matters.
    ------------------------------------------------------------------
    local label_w = 0
    for _, rec in ipairs(recs) do
        for _, row in ipairs(rec.factor_rows or {}) do
            if #row.label > label_w then label_w = #row.label end
        end
    end
    label_w = label_w + 2

    local val_w = 0
    for _, rec in ipairs(recs) do
        for _, row in ipairs(rec.factor_rows or {}) do
            if #tostring(row.value) > val_w then val_w = #tostring(row.value) end
        end
    end
    val_w = math.max(val_w, 5)

    ------------------------------------------------------------------
    -- Blocks
    ------------------------------------------------------------------
    for _, rec in ipairs(recs) do
        Emit('')
        Emit(('-'):rep(WRAP_AT))

        if not rec.ok then
            -- Kept for the same reason the card keeps it: an omitted instrument looks
            -- identical to the tool not having noticed it, and the reason is usually the
            -- whole answer.
            Emit(('%s - not scored'):format(rec.label or rec.instrument or '?'))
            Emit(INDENT .. (rec.reason or 'No chart'))
        else
            Emit(('%s - %s (rank %d)'):format(
                rec.label or rec.instrument or '?', rec.tier_name or '?',
                math.floor((rec.rank or 0) + 0.5)))

            local m = rec.model or {}
            local n_factors = 0
            for _, k in ipairs(m.keys or {}) do
                if k ~= 'is_lego' then n_factors = n_factors + 1 end
            end
            Emit(('%smodel    : %s / %s  (%d factors, %s)'):format(
                INDENT, tostring(m.candidate), tostring(m.scale), n_factors,
                tostring(rec.status or 'unknown')))

            if rec.ruler then
                Emit(('%sband     : %s ... %s'):format(
                    INDENT, rec.ruler.lo_label, rec.ruler.hi_label))
            end

            -- The uncapped score, included ONLY here and only when the clamp moved the
            -- number. It is untrustworthy by construction - a log-scale fit exponentiates,
            -- so one extreme input can produce a value that is not a rank at all - but in a
            -- report being pasted for analysis it is exactly what a reader needs, and the
            -- caveat travels with it.
            if rec.clamped and rec.raw_rank then
                Emit(('%suncapped : %.0f - past the end of the scale, so the rank is pinned')
                    :format(INDENT, rec.raw_rank))
            end

            for _, w in ipairs(rec.warnings or {}) do
                Emit('')
                Emit(INDENT .. '! ' .. Wrap(w.text, WRAP_AT - #INDENT - 2, INDENT .. '  '))
            end

            if #(rec.explanations or {}) > 0 then
                Emit('')
                for _, e in ipairs(rec.explanations) do
                    Emit(INDENT .. '. ' .. e.text)
                end
            end

            if #(rec.factor_rows or {}) > 0 then
                Emit('')
                Emit(('%s%s%s  how unusual'):format(
                    INDENT, Pad('measurement', label_w), Pad('value', val_w)))
                for _, row in ipairs(rec.factor_rows) do
                    local line = ('%s%s%s  %+.1f sd'):format(
                        INDENT, Pad(row.label, label_w),
                        Pad(row.value, val_w), row.z)
                    if row.out_of then
                        line = line .. ('   (%s any reference song)')
                            :format(row.out_of == 'above' and 'above' or 'below')
                    end
                    Emit(line)
                end
            end
        end
    end

    return table.concat(lines, '\n')
end
