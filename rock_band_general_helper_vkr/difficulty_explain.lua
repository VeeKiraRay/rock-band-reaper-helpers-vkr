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

-- Above this, two factors are treated as one observation and only the more unusual of them
-- gets a bullet. With three slots and a selection rule that looks only at how far each
-- measurement sits from the mean, nothing otherwise stops the panel saying the same thing
-- twice: measured over the whole corpus, 20% of rows spent two of three slots on a
-- correlated pair while a genuinely different property waited behind them.
--
-- The correlations are per-instrument and come from the model artifact (`model.corr`),
-- because which factors duplicate is a property of the instrument rather than of the
-- vocabulary - entropy_h2 and entropy_h2_rel are +0.96 on drums, while tight_p10 and
-- tight_med are +0.75 on vocals but only +0.45 on drums, where they genuinely carry two
-- facts. A hand-written grouping would have to be wrong in one direction or the other.
--
-- 0.70 rather than 0.80: it recovers a slot on 20% of rows instead of 14%, and everything
-- between the two is a real restatement (kick_density/kick_density_peak at 0.85,
-- move_mean/move_p90 at 0.82).
local COLLINEAR_R = 0.70

-- Tier-band position at or beyond which the suggestion is called a near thing.
local BOUNDARY_LOW  = 0.15
local BOUNDARY_HIGH = 0.85

----------------------------------------------------------------------
-- The vocabulary
--
-- One entry per factor any of the six selected models uses. `high` and `low` are complete
-- statements about the chart, chosen so neither implies a difficulty direction the
-- calibration does not support.
--
-- WHY NO DIRECTION IS EVER STATED, with the case that proves it. chord_size_mean is
-- -12.86 on keys and +12.22 on Pro Keys - the same music, scored from the same notes, with
-- the sign reversed. Nothing about chords changed between those two models. What changed
-- is the factor sitting beside it: keys measures density in GEMS, where a three-note chord
-- triples the count, so chord_size_mean is free to divide that back out and lands negative;
-- Pro Keys measures ATTACKS, where nothing needs dividing out, and it lands positive.
--
-- A coefficient's sign is only meaningful relative to the units of the factors it was
-- fitted alongside. Reading "-12.86" as "chords are easier" is reading a decomposition as
-- a mechanism. Holding attack rate fixed, larger chords in fact go with HIGHER official
-- ranks on both (+0.24 and +0.22).
--
-- So these strings describe what was measured and let the rank speak for the difficulty.
-- The temptation to explain a surprising sign in a tooltip is exactly the failure this
-- guards against: an earlier version told authors that simultaneous limbs read easier on
-- drums, which the shipped drum model contradicts (stick_size_mean is +4.72, and holding
-- attack rate fixed the correlation with rank is +0.01 - no effect in either direction).
--
-- INTERVAL FACTORS ARE INVERTED AND THIS IS THE EASIEST THING HERE TO GET WRONG.
-- tight_p10 and tight_med are spacings in quarter notes, so a LOW value means changes
-- arrive close together, which is the hard direction. Their `low` strings say so.
--
--   fmt  'num' 2dp | 'int' whole | 'frac' as a percentage | 'sec' seconds
--
-- `tip` IS OPTIONAL AND MOST FACTORS DO NOT NEED ONE. It exists to explain the sentence,
-- not the measurement, and it earns its place only where the sentence uses a term the
-- reader cannot map onto something in their own MIDI. Two ways it went wrong when every
-- factor had one:
--
--   * describing the number - "1.0 is all single notes, 2.0 is a two-note chord" - under a
--     bullet that shows no number at all, because the values are hidden by default;
--   * explaining game mechanics, like what a forced hammer-on does. An author writing
--     these markers already knows, and it pushed the one useful line off the tooltip.
--
-- So: "Many sustained notes" needs no gloss, "Long stretches of closely spaced changes"
-- does. When in doubt, leave it off - a bullet with no tooltip reads as self-explanatory,
-- which is what it should be.
----------------------------------------------------------------------

DIFFICULTY_FACTOR_INFO = {
    -- endurance and volume
    playing_s = { label = 'playing time', fmt = 'sec',
        high = 'Long playing time - the demand is sustained',
        low  = 'Short playing time',
        tip = 'Time with this instrument actually playing, not the length of the song.\n' ..
              'Rests and intros are removed, and every rate below is measured against it.' },
    notes_total = { label = 'total gems', fmt = 'int',
        high = 'A very high total gem count',
        low  = 'Few gems overall',
        tip = 'Every gem counts separately, so a three-note chord counts as three.' },
    total_changes = { label = 'total changes', fmt = 'int',
        high = 'A very high number of gem changes overall',
        low  = 'Few gem changes overall',
        tip = 'A change is a new gem shape. The same shape played over and over counts once.' },

    -- density: gems per second, and attacks per second
    density_avg = { label = 'average gem density', fmt = 'num',
        high = 'High average gem density',
        low  = 'Low average gem density',
        tip = 'Gems per second of playing time, so this rises\n' ..
              'with chord size as well as with speed.' },
    density_peak = { label = 'peak gem density', fmt = 'num',
        high = 'Very high peak gem density',
        low  = 'No especially dense passages' },
    -- THE ROLL-LANE TWINS. A 126/127 lane is a leniency device: the notes under it are a
    -- free-play region rather than required strikes, so the busiest window of a chart that
    -- ends on a roll was reading the easiest bar in the song as the hardest. The label
    -- says "outside rolls" rather than reusing the plain one, because a pasted report has
    -- to let the reader tell which measurement produced the number.
    density_peak_noroll = { label = 'peak gem density outside rolls', fmt = 'num',
        high = 'Very high peak gem density',
        low  = 'No especially dense passages',
        tip = 'Gems per second in the busiest stretch, ignoring\n' ..
              'anything under a roll lane - a roll does not ask\n' ..
              'for every note under it to be hit.' },
    attack_density_avg = { label = 'average attack rate', fmt = 'num',
        high = 'A high average attack rate',
        low  = 'A low average attack rate',
        tip = 'Strikes per second, counting a whole chord as\n' ..
              'one. Hand speed with chord size taken out.' },
    attack_density_peak = { label = 'peak attack rate', fmt = 'num',
        high = 'Very high peak attack density',
        low  = 'No especially fast passages',
        tip = 'Strikes per second in the busiest stretch, counting a whole chord as one.' },
    attack_density_peak_noroll = { label = 'peak attack rate outside rolls', fmt = 'num',
        high = 'Very high peak attack density',
        low  = 'No especially fast passages',
        tip = 'Strikes per second in the busiest stretch, counting\n' ..
              'a chord as one and ignoring anything under a roll\n' ..
              'lane.' },
    change_rate = { label = 'change rate', fmt = 'num',
        high = 'Gem shapes change very often',
        low  = 'Gem shapes change rarely' },

    -- tightness: spacings in quarter notes, so SMALLER IS HARDER
    tight_p10 = { label = 'tightest change spacing', fmt = 'num',
        high = 'Even the tightest changes are widely spaced',
        low  = 'Long stretches of closely spaced changes',
        tip = 'How close together the tightest tenth of the changes sit, in quarter notes.' },
    tight_med = { label = 'typical change spacing', fmt = 'num',
        high = 'Changes are widely spaced throughout',
        low  = 'Changes arrive close together throughout',
        tip = 'The typical gap between one gem shape and the next, in quarter notes.' },

    -- hand load
    chord_size_mean = { label = 'average chord size', fmt = 'num',
        high = 'Mostly chords',
        low  = 'Mostly single notes',
        tip = 'Gems struck at the same instant. On drums this\n' ..
              'counts limbs, so kick and snare together is a chord.' },
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
        high = 'Frequent large jumps between notes',
        low  = 'Few large jumps between notes' },
    anchor_frac = { label = 'anchored changes', fmt = 'frac',
        high = 'The hand can stay anchored through most changes',
        low  = 'Almost every change moves the hand',
        tip = 'Anchored means at least one lane carries over, so\n' ..
              'the hand does not have to reposition.' },

    -- the authored solo (pitch 103, or 115 on Pro Keys)
    solo_frac_marked = { label = 'authored solo coverage', fmt = 'frac',
        high = 'A large share of the chart sits inside an authored solo',
        low  = 'Little or no authored solo',
        tip = 'From the solo markers you wrote - pitch 103, or 115 on Pro Keys.' },
    solo_change_ratio = { label = 'solo vs the rest', fmt = 'num',
        high = 'Difficulty is concentrated in the authored solo',
        low  = 'The authored solo is no busier than the rest of the chart',
        tip = 'How much busier the marked solo is than everything outside it.' },

    -- texture. These are closer to authoring intent than to difficulty - a chart only
    -- needs a strum override where the engine's automatic behaviour was not what the
    -- author wanted - so the wording reports the marker, never a difficulty claim.
    --
    -- None of the marker factors carries a tip. An author who has written a tremolo lane
    -- or a forced HOPO knows what it does; a tooltip explaining the mechanic is the kind
    -- of filler that teaches people to stop hovering.
    sustain_frac = { label = 'sustained notes', fmt = 'frac',
        high = 'Many sustained notes',
        low  = 'Almost no sustains',
        tip = 'Counted as notes held an eighth note or longer.' },
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
        low  = 'Highly repetitive, predictable figures',
        tip = 'How well the two preceding gems predict the next one.' },
    entropy_h2_rel = { label = 'motion unpredictability', fmt = 'num',
        high = 'The next hand motion is hard to predict',
        low  = 'One figure repeated, moved around the lanes',
        tip = 'The same, but over hand motion instead of exact gems, so\n' ..
              'one riff moved up the lanes reads as a single figure.' },
    complex_peak = { label = 'dense and unpredictable together', fmt = 'num',
        high = 'Dense and unpredictable at the same time',
        low  = 'Where it is dense, it is predictable',
        tip = 'Separates a fast passage you can learn by rote\n' ..
              'from a fast passage that keeps changing.' },

    -- drums: the kick is a third limb and is measured apart from the hands
    kick_density = { label = 'kick rate', fmt = 'num',
        high = 'A busy kick pattern',
        low  = 'A sparse kick pattern' },
    kick_density_peak = { label = 'peak kick rate', fmt = 'num',
        high = 'Very fast kick passages',
        low  = 'No especially fast kick passages' },
    hand_density_peak = { label = 'peak hand rate', fmt = 'num',
        high = 'Very fast hand passages',
        low  = 'No especially fast hand passages',
        tip = 'The busiest stretch with the kick taken out, so it is the hands alone.' },
    hand_density_peak_noroll = { label = 'peak hand rate outside rolls', fmt = 'num',
        high = 'Very fast hand passages',
        low  = 'No especially fast hand passages',
        tip = 'The busiest stretch with the kick taken out and\n' ..
              'roll lanes ignored, so it is the hands alone on\n' ..
              'the notes the chart actually asks for.' },
    stick_size_mean = { label = 'limbs landing together', fmt = 'num',
        high = 'Many hits land on several limbs at once',
        low  = 'Mostly single-limb streams',
        tip = 'Average number of limbs landing together, counting the kick as one of\n' ..
              'them. A hit of kick plus snare is 2, and a single stroke anywhere is 1.' },
    tom_frac = { label = 'tom coverage', fmt = 'frac',
        high = 'A lot of toms',
        low  = 'Little to no toms' },
    roll_frac = { label = 'roll lanes', fmt = 'frac',
        high = 'Long roll lanes',
        low  = 'Almost no roll lanes' },
    offbeat_frac = { label = 'offbeat onsets', fmt = 'frac',
        high = 'Most onsets fall off the beat',
        low  = 'Most onsets land squarely on the beat',
        tip = 'Anything not on a quarter-note beat, so this is syncopation rather than speed.' },
    pro_stations_peak = { label = 'pads covered in the busiest passage', fmt = 'num',
        high = 'The busiest passages move between many different pads',
        low  = 'The busiest passages stay on a few pads',
        tip = 'A tom and a cymbal on the same colour count as two different places to reach.' },

    -- vocals. Pitch factors are pitch CLASS unless the name says otherwise; notated_range
    -- and pitch_p90 are the two that deliberately read the written octave, because the
    -- corpus says the official label means "sing it as written".
    syl_density_avg = { label = 'syllable rate', fmt = 'num',
        high = 'A high syllable rate',
        low  = 'A slow syllable rate',
        tip = 'Syllables per second of singing time. Rests between phrases\n' ..
              'are excluded, so this is how fast the words come when they do.' },
    syl_density_peak = { label = 'peak syllable rate', fmt = 'num',
        high = 'Very fast syllable passages',
        low  = 'No especially fast passages' },
    pc_interval_mean = { label = 'average interval', fmt = 'num',
        high = 'Large average intervals between notes',
        low  = 'Mostly stepwise motion',
        tip = 'Rock Band scores the note name, not the octave, so\n' ..
              'an octave leap counts as no distance at all here.' },
    notated_range = { label = 'notated range', fmt = 'num',
        high = 'A wide vocal register',
        low  = 'A narrow vocal register',
        tip = 'Lowest to highest written note, in semitones. Unlike\n' ..
              'the interval measures, this one does read the octave.' },
    pitch_p90 = { label = 'upper register', fmt = 'num',
        high = 'Sits high in the vocal register',
        low  = 'Sits low in the vocal register' },
    octave_jump_rate = { label = 'octave leaps', fmt = 'num',
        high = 'Frequent octave leaps',
        low  = 'Few octave leaps' },
    high_time_70 = { label = 'time sung high', fmt = 'pct',
        high = 'Much of the singing sits above the top of a comfortable range',
        low  = 'Little time spent high in the register',
        tip = 'Share of singing time above G4. This reads the written\n' ..
              'octave, and measures how LONG the part stays up there\n' ..
              'rather than how high it reaches once.' },
    pc_change_rate = { label = 'note change rate', fmt = 'num',
        high = 'The melody changes note constantly',
        low  = 'The melody holds or repeats notes',
        tip = 'Changes of note name per second of singing time.\n' ..
              'Repeating the same note costs nothing here.' },
    vocal_parts = { label = 'vocal parts', fmt = 'int',
        high = 'Multiple vocal parts are associated with the official vocal scale',
        low  = 'A single vocal part',
        tip = 'How many parts the song carries, counted from the HARM tracks.' },
    -- THE HARMONY COUNT AS A STEP RATHER THAN A NUMBER. Entering it linearly asserted that
    -- one singer to two costs what two to three costs; measured on the corpus with the
    -- other eleven factors held, one part and two sit 0.4 rank apart and the whole effect
    -- is the move to three. The wording claims an ASSOCIATION and not a cause, following
    -- vocal_parts above: three parts is the house default for a produced song, and the
    -- official rank grades PART VOCALS alone, so this reads arrangement scale rather than
    -- work the singer has to do.
    parts_3 = { label = 'full three-part harmony', fmt = 'int',
        high = 'Full three-part harmony is associated with the official vocal scale',
        low  = 'Fewer than three vocal parts',
        tip = 'Whether all three parts are authored. One part and\n' ..
              'two measured the same against the official scale;\n' ..
              'only the third separates.' },
}

----------------------------------------------------------------------
-- Display order for the Details table
--
-- FIXED PER INSTRUMENT, and deliberately not "most unusual first". The rows used to sort
-- by how far each measurement sat from the corpus mean, which reshuffled the table for
-- every song: two charts on the same instrument could not be read side by side, because
-- the third row was a different factor in each. Comparison is the whole reason the detail
-- table exists, so its shape has to be a property of the instrument, not of the chart.
--
-- Most-unusual-first still exists - it is what picks the three bullets above, where a
-- ranking is the point and there is nothing to line up against.
--
-- Grouped the way the vocabulary above is, so the same kind of measurement lands in the
-- same part of the table on every instrument. dev/tests asserts this list and
-- DIFFICULTY_FACTOR_INFO hold exactly the same keys, so a factor cannot be added to one
-- and silently missed in the other.
----------------------------------------------------------------------

DIFFICULTY_FACTOR_ORDER = {
    -- endurance and volume
    'playing_s', 'notes_total', 'total_changes',
    -- density
    'density_avg', 'density_peak', 'density_peak_noroll',
    'attack_density_avg', 'attack_density_peak', 'attack_density_peak_noroll',
    'change_rate',
    -- tightness
    'tight_p10', 'tight_med',
    -- hand load
    'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
    -- movement
    'move_mean', 'move_p90', 'anchor_frac',
    -- the authored solo
    'solo_frac_marked', 'solo_change_ratio',
    -- texture
    'sustain_frac', 'force_hopo_rate', 'force_strum_rate', 'tremolo_frac', 'trill_frac',
    -- predictability
    'entropy_h2', 'entropy_h2_rel', 'complex_peak',
    -- drums
    'kick_density', 'kick_density_peak', 'hand_density_peak',
    'hand_density_peak_noroll', 'stick_size_mean',
    'tom_frac', 'roll_frac', 'offbeat_frac', 'pro_stations_peak',
    -- vocals
    'syl_density_avg', 'syl_density_peak', 'pc_change_rate', 'pc_interval_mean',
    'notated_range', 'pitch_p90', 'high_time_70', 'octave_jump_rate',
    'vocal_parts', 'parts_3',
}

local ORDER_INDEX = {}
for i, k in ipairs(DIFFICULTY_FACTOR_ORDER) do ORDER_INDEX[k] = i end

-- Short badge for the model-maturity chip beside the instrument name.
DIFFICULTY_STATUS_BADGE = {
    validated = nil, beta = 'Beta', experimental = 'Experimental',
}

-- What the chip means, shown as its TOOLTIP rather than as a warning line. The wording is
-- about the model and never changes, so on the card it would be the same sentence under
-- every keys, Pro Keys and vocals result in every project - clutter that trains the eye to
-- skip the warning area where the chart-specific notes live.
--
-- These describe how well the model matched official ranks across the reference songs.
-- They are NOT the probability that this particular prediction is right.
DIFFICULTY_STATUS_NOTE = {
    validated = nil,
    beta =
        'Beta: this model came close to the accuracy bar\n' ..
        'set for the project but did not clear it.\n\n' ..
        'Its suggestions are usually sound; weigh them a\n' ..
        'little more lightly than guitar, bass or drums.',
    experimental =
        'Experimental: this model did not reach the accuracy bar set for the project.\n\n' ..
        'It still measures the chart and the ordering is meaningful, but\n' ..
        'expect it to be a tier out more often. Use your own judgment first.',
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
--
-- No longer a line on the card - the ruler below shows the same thing with the numbers
-- attached, and the two together were saying it twice. This is the ruler's TOOLTIP now, so
-- the wording is still there for whoever wants it without occupying a row.
function DifficultyPositionText(pos)
    if type(pos) ~= 'number' then return nil end
    if pos <= BOUNDARY_LOW  then return 'near the bottom of this tier' end
    if pos >= BOUNDARY_HIGH then return 'near the top of this tier' end
    return 'around the middle of this tier'
end

----------------------------------------------------------------------
-- The tier ruler
--
-- The band this chart landed in, its two neighbours with the ranks that separate them, and
-- where inside it the suggestion sits. It replaced a line of prose ("near the bottom of
-- this tier") that duplicated the boundary warning underneath it while carrying none of
-- the numbers - so a reader could see it was a close call but not how close, nor what it
-- would take to move.
--
-- BOTH OPEN BANDS ARE CLOSED BY THE MODEL, NOT BY THE TIER TABLE, and on the bottom end
-- that is the whole reason this is drawable at all. See the TierBand comment: measured
-- from rank 1, a floor-clamped Warmup chart sits 85-97% along and would draw one tick from
-- Apprentice while actually having fallen off the other end of the scale.
--
-- Returns nil for anything unscored, so the caller tests one thing.
----------------------------------------------------------------------

function DifficultyRulerBand(rec)
    if not (rec and rec.ok and rec.model and rec.tier) then return nil end
    local inst, tier = rec.instrument, rec.tier
    local m = rec.model
    local lo, hi = TierBand(inst, tier, m.rank_hi, m.rank_lo)
    if not lo or not hi or hi <= lo then return nil end

    -- The ends are labelled by what lies beyond them, which is the question being asked:
    -- an author reading this wants to know what the next tier costs. Where nothing lies
    -- beyond, the label is the model's own limit instead, said as a limit - "max 605" is
    -- honest in a way that a seventh tier name would not be.
    local lo_label = (tier == 0) and ('min %d'):format(lo)
                                  or ('%s (%d)'):format(TierName(tier), lo)
    local hi_label = (tier == 6) and ('max %d'):format(hi)
                                  or ('%s (%d)'):format(TierName(tier + 1), hi)

    -- `pinned` is the clamp, and it exists so the marker can be drawn as a limit rather
    -- than as a measurement. A clamped rank is not "here on the scale", it is "at least
    -- this far" - the uncapped number that produced it is untrustworthy by construction.
    local pinned
    if rec.clamped then
        pinned = (rec.raw_rank and m.rank_hi and rec.raw_rank > m.rank_hi) and 'hi' or 'lo'
    end

    return {
        lo = lo, hi = hi,
        pos = rec.tier_position or 0,
        lo_label = lo_label, hi_label = hi_label,
        pinned = pinned,
    }
end

----------------------------------------------------------------------
-- Explanations
----------------------------------------------------------------------

-- Every model factor with its value and how unusual it is, in DIFFICULTY_FACTOR_ORDER.
-- Backs the expandable detail table; the caller decides how many rows to draw.
function DifficultyFactorRows(rec)
    if not (rec and rec.ok and rec.model and rec.factors) then return {} end

    -- Which measurements fall outside anything in the reference songs. Reported HERE, as a
    -- property of the row, rather than as a warning on the card: out of range means
    -- "unusual", and on the card that reads as "this is why the rank came out like that",
    -- which it is not. Beside the number it is just a fact about the number.
    local flagged = {}
    for _, o in ipairs(DifficultyOutOfRange(rec.model, rec.factors)) do
        flagged[o.key] = o.side
    end

    local zs = DifficultyFactorZ(rec.model, rec.factors)
    local rows = {}
    for _, z in ipairs(zs) do
        local info = DIFFICULTY_FACTOR_INFO[z.key]
        rows[#rows + 1] = {
            key    = z.key,
            label  = info and info.label or z.key,
            value  = FormatValue(z.value, info and info.fmt),
            z      = z.z,
            tip    = info and info.tip,
            out_of = flagged[z.key],   -- 'above' | 'below' | nil
        }
    end
    -- Canonical order, NOT most-unusual-first: see DIFFICULTY_FACTOR_ORDER. Two songs on
    -- the same instrument produce the same rows in the same places, which is what makes
    -- the table comparable. Anything unlisted sorts to the end rather than vanishing.
    table.sort(rows, function(a, b)
        local ia = ORDER_INDEX[a.key] or math.huge
        local ib = ORDER_INDEX[b.key] or math.huge
        if ia ~= ib then return ia < ib end
        return a.key < b.key
    end)
    return rows
end

-- Correlation between two of a model's factors, from the artifact. 0 when the pair was not
-- emitted - either it is below the exporter's threshold and genuinely says something
-- different, or the artifact predates the field, in which case this degrades to the old
-- behaviour of showing whatever is most unusual.
--
-- Both orderings are tried because the exporter writes the pair in the model's own key
-- order rather than sorting, so there is no convention to remember at either end.
local function FactorCorr(model, a, b)
    local c = model.corr
    if not c then return 0 end
    return c[a .. '|' .. b] or c[b .. '|' .. a] or 0
end

-- Whether `key` would merely restate a bullet already chosen.
local function RestatesAChosenOne(model, chosen, key)
    for _, e in ipairs(chosen) do
        if math.abs(FactorCorr(model, e.key, key)) >= COLLINEAR_R then return true end
    end
    return false
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

    -- Records rather than bare strings, so the UI can hang the factor's own explanation off
    -- each bullet. A statement like "Large average chord load" is only useful if the reader
    -- can find out what chord load is without leaving the panel.
    local out = {}
    for _, z in ipairs(zs) do
        if #out >= MAX_EXPLANATIONS then break end
        if math.abs(z.z) >= NOTABLE_Z then
            local info = DIFFICULTY_FACTOR_INFO[z.key]
            local text = info and ((z.z > 0) and info.high or info.low)
            -- SKIP, DO NOT STOP, on a restatement: the whole point is that the slot goes
            -- to the next factor saying something different, so the loop keeps scanning.
            if text and not RestatesAChosenOne(rec.model, out, z.key) then
                out[#out + 1] = { key = z.key, text = text, tip = info.tip }
            end
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
    --
    --    SUPPRESSED WHEN THE RANK IS PINNED, because a clamped rank is not a position on
    --    the scale at all - it is "at least this far", and the tier above or below being
    --    close is not the useful thing to say about it. The clamp note says the useful
    --    thing.
    --
    --    This guard used to be load-bearing for a different reason: tier 0's band started
    --    at rank 1, so a floor-clamped drum chart at 120 computed 0.97 of the way up a
    --    band ending at 124 and collected a false "near the upper tier boundary". That is
    --    fixed at the source now - TierBand floors the band at the model's own rank_lo -
    --    so the guard is belt-and-braces rather than the fix. Keep it: a clamped rank
    --    should not be described by its position under any band definition.
    if type(rec.tier_position) == 'number' and not rec.clamped then
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

    -- 3. The rank pinned to the end of the scale.
    --
    --    IT DOES NOT SAY WHY, and that restraint is the whole point. The obvious thing to
    --    append is the list of measurements outside the reference range, and it is wrong:
    --    those say a factor is UNUSUAL, not that it caused the rank. A near-empty keys
    --    chart came out with the highest average chord size in the corpus - a sustained
    --    two-note pad, unusual and easy for unrelated reasons - and naming it here read as
    --    "it is easy because its chords are large", which is both backwards and unsupported.
    --    Same trap this file avoids for the explanations; it crept back in through a
    --    friendlier-sounding sentence.
    --
    --    The out-of-range measurements are still reported, on the factor rows in the
    --    Details view, where a reader is looking at numbers rather than being told a story
    --    about them.
    if rec.clamped then
        -- NO RAW SCORE HERE, deliberately. The number the clamp replaced is exactly the one
        -- that cannot be trusted - a log-scale fit exponentiates, and one extreme input
        -- once produced 943 for a chart whose whole corpus spanned 135-488. Printing it
        -- would invite an author to treat it as the real answer, which is the failure the
        -- clamp exists to prevent. It is in the Details panel instead.
        local over = rec.raw_rank and rec.raw_rank > m.rank_hi
        out[#out + 1] = { kind = 'clamped', text = over
            and ('%d is as high as this tool can score, and this chart came in above it. '
              .. 'It may well deserve more than %s.')
                :format(m.rank_hi, rec.tier_name or 'this')
            or  ('%d is as low as this tool can score, and this chart came in under it. '
              .. 'Worth judging for yourself whether %s is right.')
                :format(m.rank_lo, rec.tier_name or 'this tier') }
    end

    -- 5. No authored playing states. Every rate factor divides by playing time, so where
    --    that came from changes what the numbers mean - and this is recoverable by the
    --    author, unlike the notes above.
    if rec.span_source == 'fallback_idle_only' or rec.span_source == 'fallback_no_events' then
        out[#out + 1] = { kind = 'spans',
            text = 'This track has no authored playing states, so playing time was inferred '
                 .. 'from the notes. Authoring them will make the suggestion more reliable.' }
    end

    -- Model maturity is deliberately NOT a warning. It is a property of the model, not of
    -- this chart, so it would repeat identically on every keys/Pro Keys/vocals card in
    -- every project - the definition of clutter. It rides on the badge instead, as a
    -- tooltip: see DIFFICULTY_STATUS_NOTE and the card's chip.
    return out
end

-- Fill in the presentation fields on a suggestion record, in place.
function DifficultyAnnotate(rec)
    if not rec then return rec end
    rec.explanations  = DifficultyExplanations(rec)
    rec.warnings      = DifficultyWarnings(rec)
    rec.factor_rows   = DifficultyFactorRows(rec)
    rec.ruler         = DifficultyRulerBand(rec)
    rec.position_text = DifficultyPositionText(rec.tier_position)   -- the ruler's tooltip
    -- Do not show the model status
    -- rec.badge         = rec.status and DIFFICULTY_STATUS_BADGE[rec.status] or nil
    rec.badge         = nil
    return rec
end
