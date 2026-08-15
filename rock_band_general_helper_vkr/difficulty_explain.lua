-- Turning a difficulty suggestion into words.
--
-- PURE: no r.*, no S, no ctx, so dev/tests can drive it with a hand-built factor table.
-- Requires (globals): DifficultyFactorZ, DifficultyOutOfRange
--                     (lib/reaper_difficulty_predict.lua)
--
-- ---------------------------------------------------------------------------
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- It does not show regression coefficients, and it does not rank factors by how much they
-- moved the prediction. Those are properties of the FIT, and the fit's per-factor weights
-- are not causal: the difficulty factors are near-collinear by construction, so a large
-- coefficient on one of a correlated pair says which one the solver happened to load, not
-- which one the chart demands. Presenting that as "why" would be inventing an explanation.
--
-- What it shows instead is what was MEASURED: the handful of properties on which this
-- chart is unusual compared with the songs the model was fitted on. That claim is honest -
-- it is a statement about the chart and the corpus, with no causal content - and it is the
-- one an author can check against their own MIDI.
--
-- It also never prints a confidence percentage. The fitted regressions do not produce
-- calibrated per-song probabilities, and distance from a tier boundary is a different
-- quantity that would be read as one.
-- ---------------------------------------------------------------------------

-- How unusual a factor must be before it is worth a sentence, in training standard
-- deviations. Below this an ordinary chart would collect three sentences saying nothing,
-- which trains authors to skip the whole panel.
local NOTABLE_Z = 1.0

-- At most this many properties per instrument. The panel is a summary, not a factor dump;
-- the full table is behind the expander.
local MAX_EXPLANATIONS = 3

-- Tier-band position at or beyond which the suggestion is called a near thing.
local BOUNDARY_LOW  = 0.15
local BOUNDARY_HIGH = 0.85

----------------------------------------------------------------------
-- The vocabulary
--
-- One entry per factor any of the six selected models uses. `high` and `low` are complete
-- statements about the chart, chosen so neither implies a difficulty direction the
-- calibration does not support - several of these factors have coefficients whose sign is
-- either instrument-specific or genuinely surprising (stick_size_mean is NEGATIVE on
-- drums: simultaneous limbs read easier, because simple rock beats land kick and snare
-- together while the hardest charts are fast single-limb streams). Describing the
-- measurement and letting the rank speak for the difficulty avoids asserting a mechanism
-- the corpus has not established.
--
-- INTERVAL FACTORS ARE INVERTED AND THIS IS THE EASIEST THING HERE TO GET WRONG.
-- tight_p10 and tight_med are spacings in quarter notes, so a LOW value means changes
-- arrive close together, which is the hard direction. Their `low` strings say so.
--
--   fmt  'num' 2dp | 'int' whole | 'frac' as a percentage | 'sec' seconds
----------------------------------------------------------------------

DIFFICULTY_FACTOR_INFO = {
    -- endurance and volume
    playing_s = { label = 'playing time', fmt = 'sec',
        high = 'A long chart - the demand is sustained',
        low  = 'A short chart' },
    notes_total = { label = 'total gems', fmt = 'int',
        high = 'A very high total gem count',
        low  = 'Few gems overall' },
    total_changes = { label = 'total changes', fmt = 'int',
        high = 'A very high number of gem changes overall',
        low  = 'Few gem changes overall' },

    -- density: gems per second, and attacks per second
    density_avg = { label = 'average gem density', fmt = 'num',
        high = 'High average gem density',
        low  = 'Low average gem density' },
    density_peak = { label = 'peak gem density', fmt = 'num',
        high = 'Very high peak gem density',
        low  = 'No especially dense passages' },
    attack_density_avg = { label = 'average attack rate', fmt = 'num',
        high = 'A high average attack rate',
        low  = 'A low average attack rate' },
    attack_density_peak = { label = 'peak attack rate', fmt = 'num',
        high = 'Very high peak attack density',
        low  = 'No especially fast passages' },
    change_rate = { label = 'change rate', fmt = 'num',
        high = 'Gem shapes change very often',
        low  = 'Gem shapes change rarely' },

    -- tightness: spacings in quarter notes, so SMALLER IS HARDER
    tight_p10 = { label = 'tightest change spacing', fmt = 'num',
        high = 'Even the tightest changes are widely spaced',
        low  = 'Long stretches of closely spaced changes' },
    tight_med = { label = 'typical change spacing', fmt = 'num',
        high = 'Changes are widely spaced throughout',
        low  = 'Changes arrive close together throughout' },

    -- hand load
    chord_size_mean = { label = 'average chord size', fmt = 'num',
        high = 'Large average chord load',
        low  = 'Mostly single notes' },
    chord_span_mean = { label = 'average chord width', fmt = 'num',
        high = 'Wide chord shapes',
        low  = 'Narrow chord shapes' },
    chord_change_frac = { label = 'changes into a chord', fmt = 'frac',
        high = 'Most changes re-form a whole chord shape',
        low  = 'Most changes move a single note' },

    -- movement across the lanes
    move_mean = { label = 'average hand movement', fmt = 'num',
        high = 'Large average hand movement between gems',
        low  = 'Very little hand movement' },
    move_p90 = { label = 'largest hand movements', fmt = 'num',
        high = 'Frequent large jumps across the lanes',
        low  = 'Few large jumps' },
    anchor_frac = { label = 'anchored changes', fmt = 'frac',
        high = 'The hand can stay anchored through most changes',
        low  = 'Almost every change moves the hand' },

    -- the authored solo (pitch 103, or 115 on Pro Keys)
    solo_frac_marked = { label = 'authored solo coverage', fmt = 'frac',
        high = 'A large share of the chart sits inside an authored solo',
        low  = 'Little or no authored solo' },
    solo_change_ratio = { label = 'solo vs the rest', fmt = 'num',
        high = 'Difficulty is concentrated in the authored solo',
        low  = 'The authored solo is no busier than the rest of the chart' },

    -- texture. These are closer to authoring intent than to difficulty - a chart only
    -- needs a strum override where the engine's automatic behaviour was not what the
    -- author wanted - so the wording reports the marker, never a difficulty claim.
    sustain_frac = { label = 'sustained notes', fmt = 'frac',
        high = 'Many sustained notes',
        low  = 'Almost no sustains' },
    force_hopo_rate = { label = 'forced hammer-on markers', fmt = 'num',
        high = 'Frequent forced hammer-on markers',
        low  = 'Few forced hammer-on markers' },
    force_strum_rate = { label = 'forced strum markers', fmt = 'num',
        high = 'Frequent forced strum markers',
        low  = 'Few forced strum markers' },
    tremolo_frac = { label = 'tremolo lanes', fmt = 'frac',
        high = 'Long tremolo lanes',
        low  = 'Almost no tremolo lanes' },
    trill_frac = { label = 'trill lanes', fmt = 'frac',
        high = 'Long trill lanes',
        low  = 'Almost no trill lanes' },

    -- predictability, in bits. LOW means the part is predictable.
    entropy_h2 = { label = 'shape unpredictability', fmt = 'num',
        high = 'The next gem shape is hard to predict',
        low  = 'Highly repetitive, predictable figures' },
    entropy_h2_rel = { label = 'motion unpredictability', fmt = 'num',
        high = 'The next hand motion is hard to predict',
        low  = 'One figure repeated, moved around the lanes' },
    complex_peak = { label = 'dense and unpredictable together', fmt = 'num',
        high = 'Dense and unpredictable at the same time',
        low  = 'Where it is dense, it is predictable' },

    -- drums: the kick is a third limb and is measured apart from the hands
    kick_density = { label = 'kick rate', fmt = 'num',
        high = 'A busy kick pattern',
        low  = 'A sparse kick pattern' },
    kick_density_peak = { label = 'peak kick rate', fmt = 'num',
        high = 'Very fast kick passages',
        low  = 'No especially fast kick passages' },
    hand_density_peak = { label = 'peak hand rate', fmt = 'num',
        high = 'Very fast hand passages',
        low  = 'No especially fast hand passages' },
    stick_size_mean = { label = 'limbs landing together', fmt = 'num',
        high = 'Many hits land on several limbs at once',
        low  = 'Mostly single-limb streams' },
    tom_frac = { label = 'tom coverage', fmt = 'frac',
        high = 'Much of the chart is written on toms',
        low  = 'Little tom work' },
    roll_frac = { label = 'roll lanes', fmt = 'frac',
        high = 'Long roll lanes',
        low  = 'Almost no roll lanes' },
    offbeat_frac = { label = 'offbeat onsets', fmt = 'frac',
        high = 'Most onsets fall off the beat',
        low  = 'Most onsets land squarely on the beat' },
    pro_stations_peak = { label = 'pads covered in the busiest passage', fmt = 'num',
        high = 'The busiest passages move between many different pads',
        low  = 'The busiest passages stay on a few pads' },

    -- vocals. Pitch factors are pitch CLASS unless the name says otherwise; notated_range
    -- and pitch_p90 are the two that deliberately read the written octave, because the
    -- corpus says the official label means "sing it as written".
    syl_density_avg = { label = 'syllable rate', fmt = 'num',
        high = 'A high syllable rate',
        low  = 'A slow syllable rate' },
    syl_density_peak = { label = 'peak syllable rate', fmt = 'num',
        high = 'Very fast syllable passages',
        low  = 'No especially fast passages' },
    pc_interval_mean = { label = 'average interval', fmt = 'num',
        high = 'Large average intervals between notes',
        low  = 'Mostly stepwise motion' },
    notated_range = { label = 'notated range', fmt = 'num',
        high = 'A wide vocal register as written',
        low  = 'A narrow vocal register as written' },
    pitch_p90 = { label = 'upper register', fmt = 'num',
        high = 'Sits high in the register',
        low  = 'Sits low in the register' },
    octave_jump_rate = { label = 'octave leaps', fmt = 'num',
        high = 'Frequent octave leaps',
        low  = 'Few octave leaps' },
    vocal_parts = { label = 'vocal parts', fmt = 'int',
        high = 'Multiple vocal parts are associated with the official vocal scale',
        low  = 'A single vocal part' },
}

-- Short badge for the model-maturity chip beside the instrument name.
DIFFICULTY_STATUS_BADGE = {
    validated = nil, beta = 'Beta', experimental = 'Experimental',
}

-- The longer sentence, shown as a warning. Separate from the badge on purpose: the chip
-- is an at-a-glance marker and the sentence says what it means, so neither has to do both
-- jobs. These describe validation against noisy official ranks - they are NOT the
-- probability that a particular prediction is correct.
DIFFICULTY_STATUS_NOTE = {
    validated   = nil,
    beta        = 'Beta: this model is just below the validation threshold.',
    experimental = 'Experimental: this model did not reach the validation threshold - use extra judgment.',
}

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------

local function FormatValue(v, fmt)
    if type(v) ~= 'number' then return '-' end
    if fmt == 'int'  then return ('%d'):format(math.floor(v + 0.5)) end
    if fmt == 'frac' then return ('%.0f%%'):format(v * 100) end
    if fmt == 'sec'  then
        local m = math.floor(v / 60)
        return ('%d:%02d'):format(m, math.floor(v - m * 60 + 0.5))
    end
    return ('%.2f'):format(v)
end

-- Where inside its tier band the suggestion sits, in words. The tier alone hides how close
-- a call it was, and a bare 0.06 means nothing to an author.
function DifficultyPositionText(pos)
    if type(pos) ~= 'number' then return nil end
    if pos <= BOUNDARY_LOW  then return 'near the bottom of this tier' end
    if pos >= BOUNDARY_HIGH then return 'near the top of this tier' end
    return 'around the middle of this tier'
end

----------------------------------------------------------------------
-- Explanations
----------------------------------------------------------------------

-- Every model factor with its value and how unusual it is, most unusual first. Backs the
-- expandable detail table; the caller decides how many rows to draw.
function DifficultyFactorRows(rec)
    if not (rec and rec.ok and rec.model and rec.factors) then return {} end
    local zs = DifficultyFactorZ(rec.model, rec.factors)
    local rows = {}
    for _, z in ipairs(zs) do
        local info = DIFFICULTY_FACTOR_INFO[z.key]
        rows[#rows + 1] = {
            key   = z.key,
            label = info and info.label or z.key,
            value = FormatValue(z.value, info and info.fmt),
            z     = z.z,
        }
    end
    table.sort(rows, function(a, b)
        if math.abs(a.z) ~= math.abs(b.z) then return math.abs(a.z) > math.abs(b.z) end
        return a.key < b.key   -- stable, so repeated runs render identically
    end)
    return rows
end

-- Up to MAX_EXPLANATIONS statements about what makes this chart unusual. Empty when
-- nothing is: an ordinary chart should say so rather than manufacture three observations.
function DifficultyExplanations(rec)
    if not (rec and rec.ok and rec.model and rec.factors) then return {} end
    local zs = DifficultyFactorZ(rec.model, rec.factors)
    table.sort(zs, function(a, b)
        if math.abs(a.z) ~= math.abs(b.z) then return math.abs(a.z) > math.abs(b.z) end
        return a.key < b.key
    end)

    local out = {}
    for _, z in ipairs(zs) do
        if #out >= MAX_EXPLANATIONS then break end
        if math.abs(z.z) >= NOTABLE_Z then
            local info = DIFFICULTY_FACTOR_INFO[z.key]
            local text = info and ((z.z > 0) and info.high or info.low)
            if text then out[#out + 1] = text end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Warnings
----------------------------------------------------------------------

-- Advisory notes, none of which change the predicted rank. Each is { kind, text } so the
-- UI can style them without matching on the wording.
function DifficultyWarnings(rec)
    local out = {}
    if not (rec and rec.ok and rec.model) then return out end
    local m, f = rec.model, rec.factors

    -- 1. Boundary. The suggestion is one measurement; if it lands this close to a
    --    threshold, the tier above or below is a live possibility.
    if type(rec.tier_position) == 'number' then
        if rec.tier_position <= BOUNDARY_LOW and (rec.tier or 0) > 0 then
            out[#out + 1] = { kind = 'boundary',
                text = 'Near the lower tier boundary - the tier below is a close call.' }
        elseif rec.tier_position >= BOUNDARY_HIGH and (rec.tier or 6) < 6 then
            out[#out + 1] = { kind = 'boundary',
                text = 'Near the upper tier boundary - the tier above is a close call.' }
        end
    end

    -- 2. Concentration. A single tier cannot express a chart whose difficulty lives in one
    --    passage, so it is reported rather than folded in. The threshold is the model's own
    --    training 90th percentile, per instrument: a shared cutoff is provably wrong here,
    --    since bass and drums never mark a solo at all.
    local conc = m.conc or {}
    if conc.solo_change_ratio and conc.solo_change_ratio > 1.0
        and (f.solo_change_ratio or 0) > conc.solo_change_ratio then
        out[#out + 1] = { kind = 'concentration',
            text = ('The authored solo is %.1fx busier than the rest of the chart. Rated on '
                 .. 'its hardest passage this would read higher; players wanting a sustained '
                 .. 'challenge may find the rest easier than the tier suggests.')
                :format(f.solo_change_ratio) }
    elseif conc.density_ratio and (f.density_avg or 0) > 0
        and (f.density_peak or 0) / f.density_avg > conc.density_ratio then
        out[#out + 1] = { kind = 'concentration',
            text = ('Difficulty is concentrated in a short passage - its busiest stretch is '
                 .. '%.1fx the chart average.')
                :format(f.density_peak / f.density_avg) }
    end

    -- 3. Outside the calibration range. THE CLAMP HIDES EXACTLY THIS: a rank pinned to the
    --    observed maximum looks like an ordinary confident answer, so the extrapolation has
    --    to be said out loud or the author is never told.
    local out_of = DifficultyOutOfRange(m, f)
    if #out_of > 0 then
        local names = {}
        for _, o in ipairs(out_of) do
            local info = DIFFICULTY_FACTOR_INFO[o.key]
            names[#names + 1] = (info and info.label or o.key) .. ' (' .. o.side .. ')'
        end
        out[#out + 1] = { kind = 'range',
            text = 'Outside the range this model was calibrated on: '
                 .. table.concat(names, ', ')
                 .. '. The suggestion is an extrapolation.' }
    end

    -- 4. The clamp actually firing is a stronger statement than a factor being out of
    --    range: the chart scored past every rank the model has ever seen.
    if rec.clamped then
        out[#out + 1] = { kind = 'clamped',
            text = ('Scored beyond the calibrated rank range and reported at its %s (%d).')
                :format(rec.raw_rank and rec.raw_rank > m.rank_hi and 'ceiling' or 'floor',
                        rec.raw_rank and rec.raw_rank > m.rank_hi and m.rank_hi or m.rank_lo) }
    end

    -- 5. No authored playing states. Every rate factor divides by playing time, so where
    --    that came from changes what the numbers mean - and this is recoverable by the
    --    author, unlike the notes above.
    if rec.span_source == 'fallback_idle_only' or rec.span_source == 'fallback_no_events' then
        out[#out + 1] = { kind = 'spans',
            text = 'This track has no authored playing states, so playing time was inferred '
                 .. 'from the notes. Authoring them will make the suggestion more reliable.' }
    end

    -- 6. Model maturity, last: it qualifies everything above rather than being one more
    --    observation about the chart.
    local note = DIFFICULTY_STATUS_NOTE[m.status or '']
    if note then out[#out + 1] = { kind = 'maturity', text = note } end

    return out
end

-- Fill in the presentation fields on a suggestion record, in place.
function DifficultyAnnotate(rec)
    if not rec then return rec end
    rec.explanations  = DifficultyExplanations(rec)
    rec.warnings      = DifficultyWarnings(rec)
    rec.factor_rows   = DifficultyFactorRows(rec)
    rec.position_text = DifficultyPositionText(rec.tier_position)
    rec.badge         = rec.status and DIFFICULTY_STATUS_BADGE[rec.status] or nil
    return rec
end
