-- THE LOCKED EVALUATION PROTOCOL for the difficulty suggester.
--
-- PURE apart from stats.lua: no r.*, no S, no ctx. Driven by
-- run_calibration_protocol_vkr.lua, which reads the CSV and prints the report.
--
-- ---------------------------------------------------------------------------
-- Why this file exists, and what it is protecting against
--
-- Across four calibration rounds the factor set went 6 -> 9 -> 19 -> 23 factors,
-- with six lean subsets and three target scales evaluated alongside - roughly forty
-- model comparisons, every one of them on the SAME 158 guitar rows under the SAME
-- deterministic fold assignment, keeping whatever looked best each time.
--
-- That is selection inflation, and it means the headline 93.7% is an optimistic
-- estimate of what the model would do on an unseen song. Nothing in the previous
-- rounds is wrong; the number simply cannot be defended as an out-of-sample estimate
-- because the folds that produced it also chose the model.
--
-- So the rules below are fixed BEFORE looking at their output:
--
--   1. Candidates are PREDECLARED (CANDIDATES / SCALES). No candidate may be added
--      after seeing results - that is a new round, with its own pre-registration.
--   2. Every candidate is scored on the SAME fold assignments within each repeat, so
--      comparisons are PAIRED. Round 3's supporting result turned on a difference of
--      roughly one song; unpaired marginal percentages cannot see that.
--   3. Ridge is tuned INSIDE the training folds (nested), never on the rows it will
--      be evaluated on. The old 1e-6 was numerical stabilisation, not a validated
--      choice.
--   4. The gate reads an INTERVAL LOWER BOUND, not a point estimate.
--   5. Ties go to the SIMPLER candidate. Explicitly: a bigger model must beat the
--      smaller one by more than split noise to be selected.
--
-- WHAT THIS PHASE IS NOT. It does not draw the reserved test partition. The current
-- question is whether the framework is sound enough to extend to four more
-- instruments, and repeated CV answers that using all 158 rows. A reserved partition
-- can only be spent once, and at this sample size 40 rows is a quarter of the
-- fitting data for a one-shot number with a roughly +/-10 point interval. It is
-- defined in the design doc and deliberately not looked at until the real release
-- decision.
-- ---------------------------------------------------------------------------

PROTOCOL = {
    -- Repeats of the whole k-fold procedure, each with a different shuffle.
    N_REPEATS = 10,
    NFOLD     = 5,
    -- Recorded so every interval in the report is reproducible. Changing it is
    -- changing the experiment.
    SEED      = 20260812,
    -- Inner folds for the nested ridge search.
    INNER_FOLD = 3,
    RIDGE_GRID = { 1e-6, 1e-3, 1e-2, 1e-1, 1.0, 10.0 },
    -- Down-weight on the Lego-era rows, unchanged from earlier rounds (a sweep from 0
    -- to 1.0 moved rho by at most +/-0.02, so it is not a sensitive knob).
    LEGO_WEIGHT = 0.3,
    -- Gate thresholds. USABLE_FLOOR is read against the interval LOWER bound and
    -- MISS_CEILING against the miss rate's UPPER bound - both the pessimistic end, so
    -- a pass cannot come from a lucky split.
    USABLE_FLOOR  = 0.90,
    MISS_CEILING  = 0.05,
    RHO_FLOOR     = 0.70,
    -- One-sided 95%.
    Z = 1.645,
}

----------------------------------------------------------------------
-- Predeclared candidates
----------------------------------------------------------------------

-- Feature sets, smallest first. The order matters: it IS the simplicity ranking used
-- by the tie-break, so a candidate's position encodes "prefer this if the evidence
-- does not clearly favour something later".
--
-- Two factors present in the CSV are deliberately absent from every candidate:
--
--   repetition  measured as a length proxy rather than a repetitiveness measure
--               (rho ~+0.6/+0.75 with note count, saturating near 1). Phase 2's
--               first act was to drop it; the column stays for the record.
--   solo_frac   the [play_solo] ANIMATION cue, absent on 87% of songs below rank 230.
--               Round 4 ran it against the authored pitch-103 version and it lost on
--               both rho and coefficient. Dropped as planned.
--
-- Excluding them here rather than deleting the columns means no rescore is needed and
-- the losing measurements remain auditable.
-- GUITAR AND BASS: unchanged from the locked run. Do not edit this table without
-- saying so - the selected models for both instruments were chosen from exactly these
-- declarations, and altering them retroactively invalidates that result.
CANDIDATES = {
    { name = 'baseline',
      keys = { 'total_changes', 'density_peak' } },

    { name = 'primary',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s' } },

    { name = 'primary+solo',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'solo_change_ratio' } },

    { name = 'primary+movement',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s',
               'move_mean', 'move_p90', 'anchor_frac' } },

    { name = 'primary+solo+movement',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'solo_change_ratio',
               'move_mean', 'move_p90', 'anchor_frac' } },

    -- The diagnostic set: everything the CSV carries except the two dropped above.
    -- Retained only to show whether the full set earns a stable improvement; it is
    -- not expected to be selected, and being last means the tie-break disfavours it.
    { name = 'full',
      keys = { 'playing_s', 'density_avg', 'density_peak', 'change_rate',
               'tight_p10', 'tight_med',
               'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
               'move_mean', 'move_p90', 'anchor_frac',
               'solo_frac_marked', 'solo_change_ratio',
               'sustain_frac', 'force_hopo_rate', 'force_strum_rate',
               'tremolo_frac', 'trill_frac',
               'notes_total', 'total_changes' } },
}

-- 5-LANE KEYS. A separate declaration rather than a reuse, because keys differs
-- structurally in ways the authoring docs spell out:
--
--   * NO strum system at all, so force_hopo_rate / force_strum_rate are not weak
--     signals here - they are constants, and fitting a constant is meaningless.
--   * NO tremolo lanes (the keys doc lists trill markers only), so tremolo_frac is
--     likewise constant. Trill lanes DO exist and stay in.
--   * OVERLAPPING NOTES ARE LEGAL, up to three at a time, to write broken chords -
--     the thing guitar forbids outright. That is what the polyphony factors measure,
--     and keys is the only instrument where they can be non-zero.
--
-- The set below deliberately holds BOTH a pure-transfer family (`primary`, identical
-- to guitar's) and an overlap family, so one run answers two questions as a paired
-- comparison: does the guitar factor set transfer, and do the keys-specific factors
-- earn their place on top of it.
CANDIDATES_KEYS = {
    { name = 'baseline',
      keys = { 'total_changes', 'density_peak' } },

    -- Byte-identical to guitar's `primary`. THE TRANSFER TEST: if this lands near
    -- guitar's 87.78% the framework generalises; if `baseline` beats it, keys reduces
    -- to speed+volume the way bass did and guitar is the outlier.
    { name = 'primary',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s' } },

    { name = 'primary+solo',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'solo_change_ratio' } },

    -- EXPECTED TO FAIL. The keys doc says the hand never shifts across the five lanes,
    -- which is why every colour is legal on every difficulty - so the lane-distance
    -- factors have no physical basis here, unlike guitar where the doc warns that
    -- green-to-orange jumps are a Nightmare-tier concern to be wrapped away. If this
    -- candidate wins, the movement factors were never measuring hand travel.
    { name = 'primary+movement',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s',
               'move_mean', 'move_p90', 'anchor_frac' } },

    -- PREDICTABILITY. The round-6 hypothesis, and the reason it exists: `surrender` is a
    -- rank-158 chart that the model called 354, driven almost entirely by
    -- total_changes at z = +2.50 - 1087 pitch-set changes from a broken-chord arpeggio
    -- the hand plays without deciding anything. No coefficient tweak can fix an outlier
    -- that extreme (the fit already weights changes at +0.103 against density's +0.196);
    -- it needs a factor that says "but this one is predictable".
    { name = 'primary+entropy',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2' } },

    { name = 'primary+entropy_rel',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel' } },

    { name = 'primary+solo+entropy_rel',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'solo_change_ratio', 'entropy_h2_rel' } },

    -- The polyphony factors (sounding_size_mean, overlap_frac, held_change_frac) are
    -- DELIBERATELY ABSENT. Round 5 measured them correctly and they carry no difficulty
    -- signal on keys (rho -0.079 / +0.037 / +0.033) while costing ~3 points of usable%.
    -- The most polyphonic charts turn out to be among the EASIEST - holding a pad under
    -- a sparse melody is a beginner idiom - so the mechanism was backwards. Columns kept
    -- in the CSV as the record; never fitted again without a new pre-registration.
    -- ROUND 8: the round-6 selection with gem density swapped for attack density. Keys
    -- is the MOST chordal instrument in the corpus (75% of charts above chord_size_mean
    -- 1.2, mean 1.512), yet its standalone gain from the swap is only +0.027 against
    -- guitar's +0.141 - so this tests whether chordal-ness alone predicts who benefits,
    -- or whether something else about guitar's charts is doing the work.
    --
    -- RESULT: IT LOST. 90.90% against the gem version's 92.21% on log(rank), 91.23%
    -- against 91.56% on rank - consistent in sign on both scales, and against a
    -- standalone rho that IMPROVED (+0.784 -> +0.800). Keys is frozen on the gem
    -- version. Kept in the declaration rather than deleted, unlike the round-5
    -- polyphony candidates: this one is the paired evidence for a live claim about the
    -- next instrument, so it is worth seeing in every run.
    --
    -- WHY, and it is physical rather than statistical: on guitar and bass a chord is one
    -- strum, so counting gems overstates the work and attacks are the right unit. On a
    -- keyboard a chord is one finger per note, so the gem count IS the hand load and
    -- discarding it throws away a real demand. PREDICTION FOR DRUMS: it behaves like
    -- keys - each gem is a separate limb or stick - so gem density should win there too.
    { name = 'primary+ent_rel@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel' } },

    { name = 'full_keys',
      keys = { 'playing_s', 'density_avg', 'density_peak', 'change_rate',
               'tight_p10', 'tight_med',
               'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
               'move_mean', 'move_p90', 'anchor_frac',
               'solo_frac_marked', 'solo_change_ratio',
               'sustain_frac', 'trill_frac',
               'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },
}

-- GUITAR, ROUND 8. A DECLARED RE-OPENING, same shape as bass's in round 7.
--
-- Why guitar: `density_peak` counts GEMS, so on a chart with chords it fuses "how fast
-- the hand moves" with "how much it holds" into one number a linear fit can weight only
-- once. 65% of guitar charts have chord_size_mean above 1.2, and measured against rank,
-- attacks/sec beats gems/sec by a wide margin on guitar and by almost nothing elsewhere:
--
--     guitar   density_avg +0.465   attacks/sec +0.606     <- +0.141
--     keys     density_avg +0.630   attacks/sec +0.657
--     bass     density_avg +0.642   attacks/sec +0.636     <- neutral, as expected:
--                                   157 of 159 bass charts are all single notes
--
-- Guitar also currently ships the 21-feature `full`, so the interesting question is not
-- only whether accuracy improves but whether a SMALL model can now clear the floor.
--
-- THE RISK, stated before running: guitar passes with 1.16 points of headroom on its
-- lower bound, and re-opening changes which model gets selected. A new candidate landing
-- within the selection margin would be chosen on simplicity and could fail. That is the
-- rule working, not a regression, and the author accepted it to get the factor tested
-- where the gain actually is.
--
-- CANDIDATES ARE SUBSTITUTIONS, NOT ADDITIONS. Each `@attacks` entry is its sealed twin
-- with density_peak -> attack_density_peak (and density_avg -> attack_density_avg where
-- the set carries it) and nothing else changed, so the paired comparison isolates the
-- measurement. `primary+both_density` is the one exception, and it exists only to answer
-- whether the two densities carry independent information or are merely collinear.
CANDIDATES_GUITAR = {}
for _, c in ipairs(CANDIDATES) do
    CANDIDATES_GUITAR[#CANDIDATES_GUITAR + 1] = c
end
for _, c in ipairs({
    { name = 'baseline@attacks',
      keys = { 'total_changes', 'attack_density_peak' } },

    { name = 'primary@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s' } },

    { name = 'primary+solo@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'solo_change_ratio' } },

    -- Does gem density say anything attack density does not? If this fails to beat
    -- primary@attacks, the gem pair is pure redundancy and can eventually be dropped.
    { name = 'primary+both_density',
      keys = { 'total_changes', 'attack_density_peak', 'density_peak',
               'tight_p10', 'tight_med', 'chord_size_mean', 'playing_s' } },

    { name = 'full@attacks',
      keys = { 'playing_s', 'attack_density_avg', 'attack_density_peak', 'change_rate',
               'tight_p10', 'tight_med',
               'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
               'move_mean', 'move_p90', 'anchor_frac',
               'solo_frac_marked', 'solo_change_ratio',
               'sustain_frac', 'force_hopo_rate', 'force_strum_rate',
               'tremolo_frac', 'trill_frac',
               'notes_total', 'total_changes' } },
}) do
    CANDIDATES_GUITAR[#CANDIDATES_GUITAR + 1] = c
end

-- BASS, ROUND 7. A DECLARED RE-OPENING, not an edit to the sealed table.
--
-- Why bass and why now: bass fails the gate at an 88.63% lower bound and needs a 93.93%
-- mean at n=159, i.e. +1.16 points - the smallest gap of any instrument. Its selected
-- model is still the 2-factor `baseline`, so entropy has never been offered to it, and
-- entropy just bought keys +2.78 points. That makes it the cheapest remaining shot at a
-- pass, and no rescore is needed because the entropy columns were written for every
-- instrument.
--
-- THE SEALED SIX ARE COPIED BY REFERENCE, not retyped, so the round-6 comparison stays
-- exactly reproducible and cannot drift. New candidates are APPENDED, which puts them
-- last in the simplicity tie-break - the conservative direction.
--
-- GUITAR IS DELIBERATELY NOT RE-OPENED. It already passes, and adding candidates there
-- can only move its selection, not its data. Whether entropy helps guitar is a separate
-- question left for its own round; guitar's standalone rho (+0.448 literal / +0.424
-- relative) says it is worth asking.
--
-- WHICH ENCODING IS EXPECTED TO WIN HERE IS THE OPPOSITE OF KEYS. On keys the relative
-- encoding won because the hand holds one shape and slides position, so literal lane sets
-- read as unrelated blocks. On bass a transposed figure is a different fingering on
-- different strings, so the literal set is the meaningful repeat unit. Both encodings are
-- declared and the standalone rho already leans literal (+0.263 vs +0.255), weakly enough
-- that it is a real test.
CANDIDATES_BASS = {}
for _, c in ipairs(CANDIDATES) do
    CANDIDATES_BASS[#CANDIDATES_BASS + 1] = c
end
for _, c in ipairs({
    -- Cheapest first: bass's selected model is `baseline`, so this is the smallest
    -- possible test of the factor - two features that already work plus one new one.
    { name = 'baseline+entropy',
      keys = { 'total_changes', 'density_peak', 'entropy_h2' } },

    { name = 'baseline+entropy_rel',
      keys = { 'total_changes', 'density_peak', 'entropy_h2_rel' } },

    -- The same pair on top of `primary`, mirroring what was selected on keys. Bass has
    -- punished every added factor so far, so these are expected to lose to the 3-feature
    -- versions rather than to win.
    { name = 'primary+entropy',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2' } },

    { name = 'primary+entropy_rel',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel' } },

    -- ROUND 8. The round-7 selection and its leader with gem density swapped for attack
    -- density. EXPECTED TO BE A NEAR-IDENTITY: 157 of 159 bass charts are all single
    -- notes, so the two columns are equal on almost every row. Declared anyway, because
    -- "we assumed it could not matter" is not a measurement - and because the one chart
    -- where it does matter, `dreampolice`, is bass's worst miss.
    { name = 'baseline+ent_rel@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'entropy_h2_rel' } },

    { name = 'primary+entropy@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2' } },
}) do
    CANDIDATES_BASS[#CANDIDATES_BASS + 1] = c
end

-- DRUMS, ROUND 9. A new instrument, so nothing is being re-opened.
--
-- Drums differs structurally from every instrument fitted so far, and the doc plus a
-- census of the 103 corpus PART DRUMS tracks says how:
--
--   * PITCH 96 IS THE KICK PEDAL - a foot, not a hand. 34.6% of the corpus's 42,915
--     drum events are a kick struck together with a hand, against 22.8% that are two
--     sticks at once, and chord_size_mean scores both at 2.0. The backbone of nearly
--     every beat is being counted as the same demand as both hands landing together.
--   * NO SUSTAINS AT ALL - the longest gem in 67,527 is a 16th - so sustain_frac is
--     exactly 0 and the polyphony trio cannot be anything but 0 either.
--   * NO STRUM SYSTEM - pitches 101/102 do not occur on any drum track.
--   * PITCH 103 APPEARS IN 5 CHARTS, 6 EVENTS TOTAL, so the authored-solo factors are
--     constants here in all but name.
--   * 126/127 ARE ROLL LANES, not tremolo and trill. Same pitches, different meaning,
--     so they get roll_frac rather than being poured into a column whose name would
--     then be a lie - the mistake the `chords`-was-really-`events` rename fixed.
--
-- Every one of those is EXCLUDED below rather than fitted as a near-constant, which is
-- the same treatment force_hopo_rate gets on keys.
--
-- THE TRANSFER TEST COMES FIRST. `baseline` and `primary` are the guitar tables
-- themselves, by reference, so "does the framework generalise to a third limb" is
-- answered as a paired comparison against the limb-aware family in one run.
CANDIDATES_DRUM = {
    -- Byte-identical to guitar's, by reference. Do not retype these.
    CANDIDATES[1],   -- baseline
    CANDIDATES[2],   -- primary
}
for _, c in ipairs({
    -- ROUND 8'S PREDICTION, AND THE ONE THAT MATTERS HERE. Round 8 found attack density
    -- beats gem density on guitar and bass but LOSES on keys, and explained it
    -- physically: a guitar chord is one strum so gems overstate the work, while a
    -- keyboard chord is one finger per note so the gem count IS the load. That was
    -- written down as a claim about drums before drums existed in the corpus - each drum
    -- gem is a separate limb or stick, so gem density should win here too.
    --
    -- These two candidates are therefore EXPECTED TO LOSE to `baseline` and `primary`.
    -- If they win, round 8's explanation was a rationalisation and the record should say
    -- so; that is the whole reason for stating it in advance.
    { name = 'baseline@attacks',
      keys = { 'total_changes', 'attack_density_peak' } },

    { name = 'primary@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s' } },

    -- THE KICK SPLIT, cheapest form first: keep everything and just tell the fit how
    -- much foot work there is.
    { name = 'primary+kick',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'kick_density_peak' } },

    -- The substitution form: hands and foot measured apart throughout, so
    -- chord_size_mean -> stick_size_mean and density_peak -> hand_density_peak.
    { name = 'primary+limbs',
      keys = { 'total_changes', 'hand_density_peak', 'tight_p10', 'tight_med',
               'stick_size_mean', 'playing_s', 'kick_density_peak' } },

    -- Syncopation. 42.2% of corpus onsets are on the beat, 31.5% on the 8th offbeat,
    -- 26.4% on a 16th or finer, so there is real spread to read.
    { name = 'primary+offbeat',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'offbeat_frac' } },

    -- Predictability. LITERAL entropy is the one expected to work: a repeating beat is
    -- genuinely easier, and there is no transposition on a drum kit, so the
    -- motion-invariant encoding that won on keys has nothing physical to correspond to
    -- here. Both are declared so the comparison is direct rather than assumed.
    { name = 'primary+entropy',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2' } },

    { name = 'primary+entropy_rel',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel' } },

    { name = 'primary+limbs+ent+offbeat',
      keys = { 'total_changes', 'hand_density_peak', 'tight_p10', 'tight_med',
               'stick_size_mean', 'playing_s', 'kick_density_peak',
               'entropy_h2', 'offbeat_frac' } },

    -- PRO DRUMS - THE EIGHT-GEM VOCABULARY.
    --
    -- WHAT IS IN DISPUTE. There is no `real_drums` rank anywhere in the corpus, so Pro
    -- Drums shares the plain `drum` rank. That says Harmonix did not rate Pro SEPARATELY;
    -- it does not establish which kit their raters played. The author's position is that
    -- Pro is the authoring default and a player without the cymbal extension is simply
    -- playing an easier chart than the one that was authored.
    --
    -- A PRE-CHECK KILLED THE FIRST VERSION OF THIS FAMILY, and the numbers are recorded
    -- here because they are what makes the surviving candidate worth fitting. The original
    -- idea was that the eight-gem vocabulary would raise the change count, since a yellow
    -- cymbal followed by a yellow tom is currently no change at all. Measured over 102
    -- corpus drum charts:
    --
    --     total_changes         88302 -> 88338    +0.0%, median ratio exactly 1.000
    --
    -- Authors do not alternate a colour's two forms at consecutive onsets - they use toms
    -- for a section and cymbals for another, so only the marker BOUNDARIES create a change
    -- and that is 36 extra changes in the whole corpus. Swapping the change-based factors
    -- is therefore a near-identity and would have burned a comparison on noise. Dropped.
    --
    -- AND THE ABSENCE IS DELIBERATE, WHICH MAKES THIS STRUCTURAL RATHER THAN EMPIRICAL.
    -- Per the author: same-colour cymbal-to-tom adjacency is something drum authoring
    -- advises against, because the visual difference between the two gem forms is small and
    -- in a fast song it trips the player up. Transitions go BETWEEN colours instead - a
    -- rock beat on red and yellow moves into a fill starting on the red snare or a blue
    -- tom, so back-to-back yellows of different form simply do not occur. The five-gem
    -- encoding already counts the colour change at that transition, so the Pro identity
    -- adds nothing there. Nobody should retry this on a bigger corpus expecting a different
    -- answer: the pattern is absent by convention, not by sample size.
    --
    -- WHAT THE VOCABULARY DOES CHANGE is how many different PLACES the hand must cover:
    --
    --     distinct stations, busiest ~8 s   five-gem 4.77 of 5   (p25 5, p75 5)
    --                                       eight-gem 6.02 of 8   (p25 5, p75 7, range 2-8)
    --
    -- The five-gem version is saturated - nearly every chart visits every lane - so this
    -- axis DOES NOT EXIST under the standard vocabulary and could never have been fitted.
    -- Under the Pro vocabulary it spreads properly. That is the concrete form of the
    -- author's argument, and pro_stations_peak is the factor that tests it.
    --
    -- The authoring convention above is what makes this the RIGHT measure rather than a
    -- consolation prize. A groove riding the yellow cymbal and a fill using the yellow tom
    -- are two places the hand must know, and they can sit inside the same eight seconds
    -- while never being adjacent - which is exactly the case a transition count cannot see
    -- and a station count can.
    --
    -- Only SPREAD was pre-checked, deliberately, not correlation with rank - so the
    -- prediction below is still a prediction.
    --
    -- A CONFOUND TO KEEP FOR READING THE RESULT. A win does not establish that the rank is
    -- Pro-aware: tom markers track what the drummer is actually playing, and a chart with
    -- heavy tom work is a busier part on any kit. A win establishes that the eight-gem
    -- vocabulary carries difficulty signal - worth having either way - and leaves the
    -- mechanism open.
    { name = 'primary+stations@pro',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'pro_stations_peak' } },

    { name = 'primary+limbs+stations',
      keys = { 'total_changes', 'hand_density_peak', 'tight_p10', 'tight_med',
               'stick_size_mean', 'playing_s', 'kick_density_peak',
               'pro_stations_peak' } },

    -- Kept as the RECORD of the pre-check above rather than as a live hypothesis: one
    -- candidate showing what swapping the change-based factors does, so "it made no
    -- difference" is visible in the report instead of being a claim in a comment. Expected
    -- to land within noise of `primary`.
    { name = 'primary@pro',
      keys = { 'pro_total_changes', 'density_peak', 'pro_tight_p10', 'pro_tight_med',
               'chord_size_mean', 'playing_s' } },

    -- Everything the drum CSV carries that is not a structural constant here and not
    -- banned everywhere (repetition, solo_frac). tom_frac and roll_frac appear only in
    -- this candidate: both are predicted to carry nothing, and this is where that gets
    -- measured without letting them near a candidate that might be selected.
    { name = 'full_drum',
      keys = { 'playing_s', 'density_avg', 'density_peak', 'change_rate',
               'attack_density_avg', 'attack_density_peak',
               'tight_p10', 'tight_med',
               'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
               'move_mean', 'move_p90', 'anchor_frac',
               'kick_density', 'kick_density_peak', 'hand_density_peak',
               'stick_size_mean', 'tom_frac', 'roll_frac', 'offbeat_frac',
               -- Not a vocabulary swap: a new axis with no five-gem twin among the
               -- factors, so it belongs here alongside them rather than instead of one.
               'pro_stations_peak',
               'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },
}) do
    CANDIDATES_DRUM[#CANDIDATES_DRUM + 1] = c
end

----------------------------------------------------------------------
-- ROUND 10: PRO KEYS
--
-- The same physical instrument as 5-lane keys over a 25-note range instead of five
-- lanes, so this starts from the keys declaration rather than guitar's, and the
-- keys exclusions carry over unchanged: no strum system (force_hopo_rate /
-- force_strum_rate are constants here), no tremolo lanes, and the round-5 polyphony
-- factors stay out - they measured correctly on keys and carried no signal, and
-- nothing about a wider range revives them.
--
-- WHAT IS GENUINELY NEW: the display window moves. `shift_rate` and
-- `shift_span_mean` have no counterpart on any instrument scored so far, and unlike
-- most candidate factors they arrive with the authoring doc asserting the mechanism
-- outright - "Because range shifts make gameplay more difficult, we try to keep them
-- to a minimum."
--
-- `gliss_frac` is pitch 126 read as a LENIENCY device rather than as tremolo, so it
-- is the one factor here expected to carry a NEGATIVE coefficient. Sparse (21 of 123
-- charts), fitted with low expectations, same standing as the technique lanes.
--
-- WHAT IS DELIBERATELY NOT DECLARED, so a later session does not read the absence as
-- an oversight: the authoring doc says C2/F2/A2 are the easiest windows to read and
-- E2 the hardest, which invites a "time spent in an awkward range" factor. It is not
-- here. The evidence is one sentence of authoring advice, this instrument has no
-- selection history to spend on factor fishing, and the measured split (E2 at 9.4% of
-- displayed time) says the effect would be small and concentrated. It belongs in the
-- PRODUCT as an authoring check that does not move the rank - see the design doc.
--
-- PRE-REGISTERED PREDICTIONS, written before the first row was scored:
--
--   1. GEM DENSITY BEATS ATTACK DENSITY, as on keys and drums. The finger-load rule -
--      count attacks where one motion strikes many gems, count gems where each needs
--      its own finger or limb - is now 4 for 4, and Pro Keys is the same keyboard.
--      This is its fifth test and the one with the least excuse for failing.
--   2. PRO KEYS FAILS THE GATE, landing near keys' 92.21% against the same 94.47%
--      bar at n=122. `keys` and `real_keys` official ranks correlate at +0.975 - this
--      corpus's control case for two labels describing one thing - so the two
--      instruments should be about equally predictable. Recorded so that a failure is
--      an expected outcome rather than a reason to reopen anything.
--   3. `overlap_frac` IS HIGHER THAN ON 5-LANE KEYS. Measured ahead of the run:
--      0.0180 against 0.0145. Directionally as the docs imply (4 overlapping notes
--      allowed here against a 3-note chord cap), but note the size - a 24% relative
--      difference on a small base, not a new axis.
--   4. LANE SHIFTS EARN SELECTION. If `primary+shift` does not beat `primary` by the
--      predeclared margin, then the range dimension is not what distinguishes Pro
--      Keys from keys, and prediction 2's label correlation is the whole story.
--   5. `chord_span_mean` CARRIES MORE SIGNAL THAN ON KEYS, where the five-lane
--      version had almost nowhere to vary. A 25-note range gives it room.
--
-- Prediction 5 is the one to be most sceptical of: it is a standalone-rho intuition,
-- and this document's most repeated error is that standalone rho does not predict
-- fitted gain in either direction.
CANDIDATES_REAL_KEYS = {}
for _, c in ipairs(CANDIDATES_KEYS) do
    CANDIDATES_REAL_KEYS[#CANDIDATES_REAL_KEYS + 1] = c
end
for _, c in ipairs({
    -- The new axis, added to the model keys actually selected (primary+entropy_rel)
    -- rather than to bare `primary`, so the comparison is against the best keys result
    -- and not a weaker one that flatters the addition.
    { name = 'primary+shift',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel',
               'shift_rate', 'shift_span_mean' } },

    -- Rate alone. If this matches the pair, magnitude is not carrying anything and the
    -- simpler column survives - the protocol's tie-break rule prefers it.
    { name = 'primary+shift_rate',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel', 'shift_rate' } },

    { name = 'full_real_keys',
      keys = { 'playing_s', 'density_avg', 'density_peak', 'change_rate',
               'tight_p10', 'tight_med',
               'chord_size_mean', 'chord_span_mean', 'chord_change_frac',
               'move_mean', 'move_p90', 'anchor_frac',
               'solo_frac_marked', 'solo_change_ratio',
               'sustain_frac', 'trill_frac', 'gliss_frac',
               'shift_rate', 'shift_span_mean',
               'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },
}) do
    CANDIDATES_REAL_KEYS[#CANDIDATES_REAL_KEYS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 11: VOCALS
--
-- The only instrument sharing NO factor with the gem sets except playing_s, the two
-- tightness percentiles and the entropy rate - the four quantities that mean the same
-- thing for a voice as for a hand. Everything else is its own vocabulary, so this is a
-- fresh declaration rather than a derived one.
--
-- THREE PAIRED SUBSTITUTIONS, and they are the round. Each is a pair of columns that
-- measure the SAME demand in two defensible units, declared as swaps and never fitted
-- together:
--
--   1. PITCH CLASS vs RAW SEMITONE (`@semitone`). Rock Band scores pitch class, so a
--      12-semitone leap is the same note name and costs the singer nothing, while a
--      semitone is a real move. The whole vocal design rests on that claim. Declaring
--      the raw-semitone twin is what turns it from an assertion in a design document
--      into a measured result. THE MOST IMPORTANT COMPARISON IN THE ROUND.
--
--   2. SYLLABLES vs NOTE TUBES (`@tubes`). A '+' lyric means the note is joined to its
--      predecessor by a diagonal tube - one long note with a sliding pitch, not a
--      second thing to hit. So a syllable sung over three notes is one syllable and
--      three tubes, and 14.3% of all corpus lyrics are '+'. Structurally the same
--      question as attacks-vs-gems, which decided four rounds and then FAILED on Pro
--      Keys in round 10. That failure is the reason this is declared as a pair rather
--      than assumed.
--
--   3. JOINT vs SEPARATE LENGTH. `short_moving_frac` counts notes that are both short
--      AND a pitch change from their predecessor - the author's mechanism, and one a
--      linear model cannot form for itself. Its rival declares `short_frac` alongside
--      the interval factors and lets the fit try.
--
-- NOT DECLARED, deliberately: `notated_range` (the design doc is explicit that
-- difficulty follows what the game REQUIRES, and required range is `pc_range`;
-- notated range is reported as a caveat), `caret_frac` (203 events corpus-wide, far too
-- thin to fit as its own grade - it is folded into talkie_frac and kept as a column for
-- the record), and anything harmony-derived (the author's call: PART VOCALS only).
--
-- PRE-REGISTERED PREDICTIONS, written before a single vocal row was scored:
--
--   1. PITCH CLASS BEATS RAW SEMITONE. If it does not, the design doc's central claim
--      about vocals is wrong and everything resting on it needs revisiting.
--   2. SYLLABLES BEAT NOTE TUBES, by the round-8 argument. Held loosely: the identical
--      reasoning failed on Pro Keys one round ago.
--   3. `talkie_frac` AND `plus_frac` BOTH FIT NEGATIVE. Both mark passages easier than
--      their note count implies. A positive coefficient on either means the marker
--      tracks showy songs rather than easy passages and the reasoning is backwards.
--   4. THE JOINT `short_moving_frac` BEATS THE SEPARATE PAIR, and `short_frac` alone is
--      weak - length only bites when the pitch moves.
--   5. VOCALS SCORES BELOW ALL THREE PASSING INSTRUMENTS. Different physical task, and
--      labels that rate a performance rather than a chart.
--
-- Prediction 5 is the safe one. 2 and 3 are mechanism guesses and are where this round
-- is most likely to be wrong.
CANDIDATES_VOCALS = {
    { name = 'baseline',
      keys = { 'syl_density_peak', 'playing_s' } },

    { name = 'primary_vocal',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s' } },

    { name = 'primary+phrase',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'phrase_syl_mean', 'phrase_syl_peak' } },

    { name = 'primary+entropy_rel',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s', 'entropy_h2_rel' } },

    -- The two lyric-marker factors, which are the only ones expected to fit negative.
    { name = 'primary+markers',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s', 'talkie_frac', 'plus_frac' } },

    -- Substitution 3: the joint length factor against the separate pair.
    { name = 'primary+length_joint',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s', 'short_moving_frac' } },

    { name = 'primary+length_separate',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s', 'short_frac', 'pc_interval_p90' } },

    -- Substitution 1: the octave trap. Identical to primary_vocal with the pitch-class
    -- interval swapped for the raw semitone distance.
    { name = 'primary_vocal@semitone',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'semi_interval_mean', 'playing_s' } },

    -- Substitution 2: the same set counted in note tubes rather than syllables.
    { name = 'primary_vocal@tubes',
      keys = { 'tube_density_avg', 'tube_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s' } },

    { name = 'full_vocal',
      keys = { 'playing_s', 'syllables_total',
               'syl_density_avg', 'syl_density_peak', 'pc_change_rate',
               'tight_p10', 'tight_med',
               'phrase_syl_mean', 'phrase_syl_peak', 'phrase_len_mean',
               'pc_interval_mean', 'pc_interval_p90', 'pc_range',
               'talkie_frac', 'plus_frac',
               'short_frac', 'short_moving_frac',
               'entropy_h2_rel' } },

    { name = 'full_vocal@tubes',
      keys = { 'playing_s', 'tubes_total',
               'tube_density_avg', 'tube_density_peak', 'pc_change_rate',
               'tight_p10', 'tight_med',
               'phrase_syl_mean', 'phrase_syl_peak', 'phrase_len_mean',
               'pc_interval_mean', 'pc_interval_p90', 'pc_range',
               'talkie_frac', 'plus_frac',
               'short_frac', 'short_moving_frac',
               'entropy_h2_rel' } },
}

----------------------------------------------------------------------
-- ROUND 12: VOCALS - two measurement repairs and the register lead
--
-- Round 11 selected primary_vocal@tubes at 84.46% usable and rho +0.411 against a 0.70
-- floor. The rho is the part that mattered: every other instrument orders its charts at
-- +0.830 to +0.884, so vocals was not a hard instrument, it was a broken measurement.
-- Two defects were then found, and this round is their repair plus one new axis.
--
-- The candidates above are UNCHANGED and all of them stay. Dropping one now that its
-- result is known would be the post-hoc pruning this protocol exists to prevent.
--
-- REPAIR 1, NOT A CANDIDATE: phrase segmentation. ReadPhraseSpans ran its markers
-- through NormalizeSpans, which merges TOUCHING spans - correct for an idle/play join,
-- fatal for phrases, where the boundary is the entire meaning. 8335 raw markers across
-- 189 tracks collapsed to 5364, destroying 35.6% of every phrase boundary in the corpus
-- (`whativedone2` 32 -> 2, `nookie2` 75 -> 15). It is fixed in the reader rather than
-- offered as a choice, because measuring a merged blob was never a defensible reading.
-- The covered time is unchanged, so playing_s and the density factors do not move.
--
-- REPAIR 2, DECLARED AS A SUBSTITUTION (`@pitched`): a '#' or '^' syllable is not
-- pitched, and the game ignores what pitch is written on it. The scorer was computing
-- every interval, range and entropy figure across those notes anyway. `nookie2` - the
-- worst OVER-predicted song - reads pc_range 12 against a true pitched range of 7, and
-- `killinginthename` is shouted end to end with 0 of 628 notes carrying a scored pitch.
-- Offered as a swap rather than a straight correction so the size of the fix is measured
-- rather than asserted.
--
-- NEW AXIS: range and register, on pitched notes. THIS REVERSES A ROUND-11 DECISION and
-- the reversal is deliberate. Round 11 computed notated_range and refused to fit it, on
-- the design doc's rule that difficulty follows what the game REQUIRES. Its prediction 1
-- then came out a wash - raw semitone distance predicted the label as well as pitch class
-- (standalone +0.379 against +0.332). The resolution that fits both facts: the ranks were
-- set by playtesters SINGING, and producing an octave leap is real physical work even
-- though the scorer does not require it. `octave_jump_rate` is the sharpest form of that
-- question, since it counts exactly the moves pitch-class scoring throws away.
--
-- PRE-REGISTERED PREDICTIONS:
--
--   1. THE PHRASE REPAIR MOVES THE PHRASE FACTORS OFF ZERO. phrase_syl_mean reads rho
--      -0.008 today. If it is still near zero once the boundaries are real, phrase load
--      carries no signal and the factor should be retired rather than re-measured.
--   2. `@pitched` BEATS THE ALL-NOTES READING, and by more than a typical factor margin,
--      because it repairs a measurement rather than adding information.
--   3. AT LEAST ONE RANGE/REGISTER FACTOR EARNS SELECTION. If none does, round 11's
--      prediction 1 was a coincidence and the pitch-class reading needs no defending.
--   4. `nookie2` STOPS BEING OVER-PREDICTED - a single-song check, falsifiable.
--   5. VOCALS STILL FAILS THE GATE. rho should rise from +0.411 but not reach +0.70.
--      Two repairs and one axis do not close a gap that large.
for _, c in ipairs({
    -- Substitution: the round-11 primary with its pitch factor read on pitched notes.
    { name = 'primary_vocal@pitched',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean_p', 'playing_s' } },

    -- The new axis on its own, so its contribution is separable from the repair.
    { name = 'primary+range',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate' } },

    -- Both together - the round's best guess at where vocals actually lands.
    { name = 'primary@pitched+range',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean_p', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate' } },

    { name = 'primary@pitched+entropy_p',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean_p', 'playing_s', 'entropy_h2_rel_p' } },

    { name = 'full_vocal@pitched',
      keys = { 'playing_s', 'syllables_total',
               'syl_density_avg', 'syl_density_peak', 'pc_change_rate_p',
               'tight_p10', 'tight_med',
               'phrase_syl_mean', 'phrase_syl_peak', 'phrase_len_mean',
               'pc_interval_mean_p', 'pc_interval_p90_p', 'pc_range_p',
               'notated_range', 'pitch_mean', 'pitch_p90', 'octave_jump_rate',
               'talkie_frac', 'plus_frac',
               'short_frac', 'short_moving_frac',
               'entropy_h2_rel_p' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 13: VOCALS - breath load and tessitura
--
-- Round 12 reached 89.30% usable and rho +0.579 and left all of its remaining error at
-- the HARD end. `flightoficarus` (rank 442, tier 6) predicted 239. The author read that
-- chart and confirmed the model is RIGHT about its shape and speed - it is genuinely
-- sparse and slow. The difficulty is elsewhere, and two author hypotheses named it.
--
-- BREATH: NOTE LENGTH IS U-SHAPED, WHICH IS WHY ROUND 12 MEASURED NOTHING. Round 12
-- concluded "sustain is not the answer" from long_frac -0.013 and note_len_mean -0.035.
-- That conclusion was wrong for a specific and instructive reason: a short tube is hard
-- (no time to find the pitch) AND a very long one is hard (it has to be held), so the
-- two arms cancel under a rank correlation. Threshold measures that look only at the
-- long tail recover it - longest_s +0.283, longtime_frac +0.224, breath_load +0.208 -
-- and `flightoficarus` holds an ELEVEN-SECOND NOTE at z +4.31, its most extreme
-- measurement by a wide margin against a corpus mean of 2.31 s.
--
-- TESSITURA: where the part SITS, which is not where it RANGES. `flightoficarus` reads
-- notated_range z -0.62 - narrow - while spending 46.7% of its sung time above G4
-- against a 19% corpus mean. top_note measures +0.561 standalone, stronger than any
-- factor currently fitted, and is only +0.251 collinear with the breath axis, so the two
-- are separate demands rather than one restated.
--
-- MEASURED AND REJECTED, so it is not retried: THE LOW END IS NOT HARD. The author asked
-- whether register should be U-shaped like length. It is not - bottom_note +0.053,
-- low_time_50 -0.167 (time spent low tracks EASIER songs), and every symmetric measure is
-- weaker than the high side alone (absdev_from_60 +0.149, extreme_54_67 +0.126, against
-- high_time_70 +0.532). Combining the ends destroys signal. Recorded as a CORPUS
-- LIMITATION rather than a law: this is a rock corpus, mostly male, whose sung notes have
-- a p10 of 55, so there is little genuinely deep material to test against.
--
-- PRE-REGISTERED PREDICTIONS:
--
--   1. THE BREATH FAMILY EARNS SELECTION. If not, the U-shape argument is right about
--      the mechanism and wrong about the magnitude.
--   2. `longest_note_s` BEATS `breath_load` STANDALONE, but the family beats either
--      alone: peak and cumulative demand are different, and `flightoficarus` is extreme
--      on one (z +4.31) and mild on the other (z +1.19).
--   3. `top_note` IS THE STRONGEST NEW FACTOR, and tessitura earns selection ALONGSIDE
--      breath rather than instead of it.
--   4. `flightoficarus` IMPROVES BY AT LEAST TWO TIERS - currently 239 against 442. A
--      concrete single-song check, as `nookie2` was in round 12.
--   5. VOCALS STILL FAILS THE GATE. rho should clear +0.65, but the usable LOWER BOUND
--      needs 90% and sits at 84.55%; two factor families do not close that.
for _, c in ipairs({
    -- The round-12 selection plus each new family on its own, so their contributions are
    -- separable rather than entangled in one big candidate.
    { name = 'primary+range+breath',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'longest_note_s', 'breath_load', 'longtime_frac' } },

    { name = 'primary+range+tess',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'top_note', 'high_time_67' } },

    -- The threshold substitution: identical but for which "high" means.
    { name = 'primary+range+tess@70',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'top_note', 'high_time_70' } },

    -- Both families - the round's best guess at where vocals lands.
    { name = 'primary+range+breath+tess',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'longest_note_s', 'breath_load', 'longtime_frac',
               'top_note', 'high_time_67' } },

    { name = 'primary+range+breath+tess@70',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'longest_note_s', 'breath_load', 'longtime_frac',
               'top_note', 'high_time_70' } },

    -- Ceiling check: everything that has ever measured anything on this instrument.
    { name = 'full_vocal+all',
      keys = { 'playing_s', 'syllables_total',
               'syl_density_avg', 'syl_density_peak', 'pc_change_rate',
               'tight_p10', 'tight_med',
               'phrase_syl_mean', 'phrase_syl_peak', 'phrase_len_mean',
               'pc_interval_mean', 'pc_interval_p90', 'pc_range',
               'notated_range', 'pitch_mean', 'pitch_p90', 'octave_jump_rate',
               'longest_note_s', 'breath_load', 'longtime_frac',
               'top_note', 'high_time_70',
               'talkie_frac', 'plus_frac',
               'short_frac', 'short_moving_frac',
               'entropy_h2_rel' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 14: CONTEXT, LOCAL INTERACTIONS, AND KEYBOARD COORDINATION
--
-- Declared before the new corpus score is inspected. Prior candidates remain byte-for-
-- byte intact above. Predictions:
--   1. vocal_parts removes the measured monotone harmony residual and earns selection;
--   2. high+sustained interaction improves hard-end vocal residuals without top_note's
--      one-onset failure; pitch_p98_time beats raw top_note when used with high time;
--   3. phrase_complex_p90 helps only if difficulty is concentrated locally;
--   4. complex_peak is more useful on ordinary Keys than another global count, but Keys
--      may remain frozen because the selection margin is intentionally conservative;
--   5. Pro Keys finger reassignment beats centroid/shift features, while local held-note
--      independence is secondary rather than sufficient alone.
for _, c in ipairs({
    { name = 'primary+range+parts',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts' } },

    { name = 'primary+range+highhold',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'high_hold_time_70', 'high_longest_note_70',
               'high_reentry_rate_70', 'pitch_p98_time' } },

    { name = 'primary+range+parts+highhold',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_hold_time_70', 'high_longest_note_70',
               'high_reentry_rate_70', 'pitch_p98_time' } },

    { name = 'primary+range+phrase_tail',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate',
               'phrase_density_p90', 'phrase_complex_p90' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

-- Ordinary Keys is re-opened only for the one predeclared local interaction. It is
-- appended last, so the established seven-feature model wins unless this clears the
-- same paired margin as every earlier expansion.
CANDIDATES_KEYS[#CANDIDATES_KEYS + 1] = {
    name = 'primary+entropy_rel+complex_peak',
    keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
             'chord_size_mean', 'playing_s', 'entropy_h2_rel', 'complex_peak' },
}

for _, c in ipairs({
    { name = 'primary+ent_rel+fingers',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel',
               'finger_reassign_mean', 'finger_reassign_p90', 'finger_reassign_peak' } },
    { name = 'primary+ent_rel+fingers+held',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel',
               'finger_reassign_mean', 'finger_reassign_p90', 'finger_reassign_peak',
               'held_independence_peak' } },
}) do
    CANDIDATES_REAL_KEYS[#CANDIDATES_REAL_KEYS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 15: PRO KEYS - LOCAL DENSITY x UNPREDICTABILITY
--
-- Round 14 pre-registered complex_peak only for ordinary Keys. It became that
-- instrument's strongest standalone factor (+0.840) and earned selection with a
-- +1.56-point paired gain. The same already-written column reads +0.797 on Pro Keys,
-- stronger than attack_density_peak (+0.772), finger_reassign_peak (+0.646), and every
-- other Pro-specific factor. Its fitted result on Pro Keys has NOT been viewed.
--
-- One question, one candidate: add complex_peak to the existing selected seven-feature
-- Pro Keys model. Do not offer combinations with the failed finger/shift families, and
-- do not alter the one-point/70%-of-repeats selection bar.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. The candidate beats primary+ent_rel@attacks on both target scales.
--   2. It earns selection (>1 point AND >70% of paired repeats).
--   3. Pro Keys still fails the usable lower-bound gate; one factor cannot plausibly
--      close the current 8.95-point interval gap.
--   4. The hard-end under-ratings improve more than the easy-end over-ratings, because
--      complex_peak measures concentrated technical passages rather than song volume.
CANDIDATES_REAL_KEYS[#CANDIDATES_REAL_KEYS + 1] = {
    name = 'primary+ent_rel@attacks+complex_peak',
    keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
             'chord_size_mean', 'playing_s', 'entropy_h2_rel', 'complex_peak' },
}

-- Which declaration governs an instrument. Anything without its own entry uses the
-- guitar/bass set, so adding an instrument without declaring candidates for it fails
-- visibly (unavailable factors are reported, not silently dropped) rather than quietly
-- fitting the wrong thing.
CANDIDATES_BY_INSTRUMENT = {
    keys      = CANDIDATES_KEYS,
    bass      = CANDIDATES_BASS,
    guitar    = CANDIDATES_GUITAR,
    drum      = CANDIDATES_DRUM,
    real_keys = CANDIDATES_REAL_KEYS,
    vocals    = CANDIDATES_VOCALS,
}

function CandidatesFor(inst)
    return CANDIDATES_BY_INSTRUMENT[inst] or CANDIDATES
end

-- Target scales. The model is fitted on fwd(rank) and predictions are mapped back
-- through inv before grading, so both scales are graded identically on the rank scale
-- the product uses.
--
-- WHY log(rank) IS A DECLARED CANDIDATE AND NOT A TWEAK. The tier ladder is close to
-- GEOMETRIC, not arithmetic: guitar's thresholds 139/176/221/267/333/409 give
-- successive ratios 1.27, 1.26, 1.21, 1.25, 1.23. Equal steps of difficulty map to
-- growing steps of rank, so a fit that minimises absolute rank error is optimising
-- something the grade does not measure - a 40-point miss at rank 150 and at rank 450
-- cost the fit the same but only the first crosses a tier boundary. Round 3 measured
-- log(rank) at +2.5 points of usable% on guitar, unpaired and on one fold assignment,
-- which is exactly the kind of result this protocol exists to confirm or kill.
--
-- MAE IS NOT COMPARABLE ACROSS SCALES and must never be used to choose between them:
-- fitting log(rank) buys proportional accuracy at the cost of absolute accuracy, so
-- its MAE can rise while its tier accuracy improves. Grade on tier distance.
SCALES = {
    { name = 'rank',      fwd = function(v) return v end,
                          inv = function(v) return v end },
    { name = 'log(rank)', fwd = function(v) return math.log(math.max(1, v)) end,
                          inv = function(v) return math.exp(v) end },
}

----------------------------------------------------------------------
-- Never report a rank outside the observed label range
----------------------------------------------------------------------

-- A fit on log(rank) exponentiates its output, so an extreme input on a strong factor
-- does not merely overshoot - it produces a number that is not a rank at all.
-- `dreampolice` (bass, actual rank 299) carries density_peak at z = +6.34 and came back
-- at 943, against a corpus that spans 135-488. An author shown 943 would read it as a
-- bug, correctly.
--
-- THIS CHANGES NO HEADLINE NUMBER, and the comment says so on purpose so nobody later
-- mistakes it for an accuracy fix: tier 6 is tier 6 whether the prediction is 943 or
-- 488, so usable% and miss% are untouched, and Spearman is order-preserving, so rho is
-- untouched too. MAE is the only figure that moves. This is about not printing nonsense.
--
-- The bounds come from the observed ranks rather than a constant, because the honest
-- claim is only ever "within the range of labels the model has seen".
function ClampRank(rank, lo, hi)
    if rank < lo then return lo end
    if rank > hi then return hi end
    return rank
end

-- Observed rank range over every row a fit is allowed to train on.
function RankRange(d, ...)
    local lo, hi = math.huge, -math.huge
    for _, set in ipairs({ ... }) do
        for _, i in ipairs(set) do
            local rk = d.ranks[i]
            if rk and rk > 0 then
                if rk < lo then lo = rk end
                if rk > hi then hi = rk end
            end
        end
    end
    if lo > hi then return 1, math.huge end   -- nothing to bound with
    return lo, hi
end

----------------------------------------------------------------------
-- One fit, with the ridge chosen inside the training rows
----------------------------------------------------------------------

local function Slice(feats, keys, pos)
    local out = {}
    for i = 1, #feats do
        local v = {}
        for _, k in ipairs(keys) do v[#v + 1] = feats[i][pos[k]] end
        out[i] = v
    end
    return out
end

local function WithOrigin(fv, is_lego)
    local out = {}
    for j = 1, #fv do out[j] = fv[j] end
    out[#out + 1] = is_lego
    return out
end

-- Nested ridge search. Splits the TRAINING rows again, scores each ridge value on the
-- inner holdouts, and returns the best. The training rows here never include the outer
-- fold being predicted, so nothing the model is graded on informs its ridge.
local function ChooseRidge(X, ys, ws)
    local n = #X
    if n < PROTOCOL.INNER_FOLD * 2 then return PROTOCOL.RIDGE_GRID[1] end
    local folds = KFoldIndices(n, PROTOCOL.INNER_FOLD)
    local best, best_err = PROTOCOL.RIDGE_GRID[1], math.huge
    for _, ridge in ipairs(PROTOCOL.RIDGE_GRID) do
        local err, cnt = 0, 0
        for f = 1, #folds do
            local tx, ty, tw = {}, {}, {}
            for g = 1, #folds do
                if g ~= f then
                    for _, i in ipairs(folds[g]) do
                        tx[#tx + 1], ty[#ty + 1], tw[#tw + 1] = X[i], ys[i], ws[i]
                    end
                end
            end
            local fit = MultiFit(tx, ty, ridge, tw)
            if fit then
                for _, i in ipairs(folds[f]) do
                    err = err + math.abs(ApplyFit(X[i], fit) - ys[i])
                    cnt = cnt + 1
                end
            end
        end
        if cnt > 0 and err / cnt < best_err then best, best_err = ridge, err / cnt end
    end
    return best
end

----------------------------------------------------------------------
-- One repeat of k-fold CV for one candidate on one scale
----------------------------------------------------------------------

-- d          { feats, ranks, origins, names }
-- target     row indices to predict (the rb3_dlc development rows)
-- extra      row indices always in training, never predicted (the Lego rows)
-- folds      fold assignment over 1..#target, shared by every candidate in this repeat
--
-- Returns pred, act (parallel arrays over the target rows) and the ridge values used.
function RunOneRepeat(d, target, extra, folds, keys, pos, scale)
    local feats = Slice(d.feats, keys, pos)
    local pred, act, ridges = {}, {}, {}

    for f = 1, #folds do
        local X, ys, ws = {}, {}, {}
        for g = 1, #folds do
            if g ~= f then
                for _, ti in ipairs(folds[g]) do
                    local i = target[ti]
                    X[#X + 1]   = WithOrigin(feats[i], 0)
                    ys[#ys + 1] = scale.fwd(d.ranks[i])
                    ws[#ws + 1] = 1.0
                end
            end
        end
        for _, i in ipairs(extra) do
            X[#X + 1]   = WithOrigin(feats[i], 1)
            ys[#ys + 1] = scale.fwd(d.ranks[i])
            ws[#ws + 1] = PROTOCOL.LEGO_WEIGHT
        end

        local ridge = ChooseRidge(X, ys, ws)
        ridges[#ridges + 1] = ridge
        local fit = MultiFit(X, ys, ridge, ws)
        if not fit then return nil end

        for _, ti in ipairs(folds[f]) do
            local i = target[ti]
            local n = #pred + 1
            -- Mapped back through inv, so both scales are graded on the rank scale.
            pred[n] = scale.inv(ApplyFit(WithOrigin(feats[i], 0), fit))
            act[n]  = d.ranks[i]
        end
    end
    return pred, act, ridges
end

----------------------------------------------------------------------
-- The full protocol: every candidate x scale, paired across repeats
----------------------------------------------------------------------

-- Returns an array of result records, one per (candidate, scale), each holding the
-- per-repeat usable / miss / rho series plus their summaries. Also returns the fold
-- assignments actually used, so a report can state them.
function RunProtocol(d, target, extra, inst, factor_pos)
    -- Stratify by ACTUAL TIER, because whole tiers hold 2-3 songs (bass Impossible has
    -- 2) and an unstratified shuffle can leave a fold with none of them.
    local strata = {}
    for n, ti in ipairs(target) do
        strata[n] = tostring(TierForRank(inst, d.ranks[ti]))
    end

    -- Bounds from the TARGET rows only, not the down-weighted other-origin rows: every
    -- prediction is made with is_lego = 0, i.e. on the RB3 scale, so a Lego rank is not
    -- a label this prediction could legitimately take. (It moves only the floor in
    -- practice - guitar 95 -> 125, bass 96 -> 117 - and no prediction currently reaches
    -- it, so nothing observable changes. Correct anyway.)
    local rank_lo, rank_hi = RankRange(d, target)

    -- One fold assignment per repeat, SHARED by every candidate. This is what makes
    -- the comparisons paired.
    local folds_by_repeat = {}
    for rep = 1, PROTOCOL.N_REPEATS do
        folds_by_repeat[rep] = ShuffledStratifiedFolds(
            strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
    end

    local results = {}
    for _, cand in ipairs(CandidatesFor(inst)) do
        -- A candidate naming a factor the CSV does not carry is skipped loudly rather
        -- than silently scored on fewer features.
        local ok = true
        for _, k in ipairs(cand.keys) do
            if not factor_pos[k] then ok = false end
        end
        for _, scale in ipairs(SCALES) do
            local rec = { candidate = cand.name, scale = scale.name,
                          n_features = #cand.keys, usable = {}, miss = {}, rho = {},
                          ridges = {}, ok = ok, per_row = nil,
                          keys = cand.keys, scale_obj = scale }
            if ok then
                for rep = 1, PROTOCOL.N_REPEATS do
                    local pred, act, ridges = RunOneRepeat(
                        d, target, extra, folds_by_repeat[rep],
                        cand.keys, factor_pos, scale)
                    if pred then
                        local pt, at = {}, {}
                        for i = 1, #pred do
                            pred[i] = ClampRank(pred[i], rank_lo, rank_hi)
                            pt[i] = TierForRank(inst, pred[i])
                            at[i] = TierForRank(inst, act[i])
                        end
                        local dist = TierDistance(pt, at)
                        rec.usable[#rec.usable + 1] = dist.usable / dist.n
                        rec.miss[#rec.miss + 1]     = dist.miss / dist.n
                        rec.rho[#rec.rho + 1]       = Spearman(pred, act) or 0
                        rec.n_rows = dist.n
                        for _, rg in ipairs(ridges) do
                            rec.ridges[#rec.ridges + 1] = rg
                        end
                    end
                end
            end
            if #rec.usable > 0 then
                rec.usable_mean = MeanOf(rec.usable)
                rec.miss_mean   = MeanOf(rec.miss)
                rec.rho_mean    = MeanOf(rec.rho)
                -- Split stability: how much the answer moves when only the shuffle
                -- changes. Reported, but NOT the gate's interval - see WilsonBounds.
                rec.usable_lo_split = Quantile(rec.usable, 0.10)
                rec.usable_hi_split = Quantile(rec.usable, 0.90)
                -- The gate's interval: binomial on the row count, the dominant term.
                rec.usable_lower = WilsonLower(rec.usable_mean, rec.n_rows, PROTOCOL.Z)
                rec.miss_upper   = WilsonUpper(rec.miss_mean,   rec.n_rows, PROTOCOL.Z)
            end
            results[#results + 1] = rec
        end
    end
    return results, folds_by_repeat
end

----------------------------------------------------------------------
-- Paired comparison and the selection rule
----------------------------------------------------------------------

-- Paired differences in usable% between two candidates, repeat by repeat. Both were
-- scored on identical folds, so the difference within a repeat removes split noise -
-- which is the whole reason for pairing.
--
-- Returns mean_diff, share_of_repeats_where_a_wins, n_paired.
function PairedDiff(a, b)
    local n = math.min(#a.usable, #b.usable)
    if n == 0 then return 0, 0, 0 end
    local sum, wins = 0, 0
    for i = 1, n do
        local diff = a.usable[i] - b.usable[i]
        sum = sum + diff
        if diff > 0 then wins = wins + 1 end
    end
    return sum / n, wins / n, n
end

-- THE PREDECLARED SELECTION RULE.
--
-- 1. Order candidates by simplicity: fewest features first, and within that, the order
--    they are declared in CANDIDATES.
-- 2. Take the best mean usable% as the leader.
-- 3. Walk from the simplest candidate upward and select the FIRST one that the leader
--    does not clearly beat. "Clearly" means the leader wins more than
--    WIN_SHARE of the paired repeats AND by more than MIN_GAIN on average.
--
-- The effect is that a bigger model has to earn its place consistently across repeats,
-- not merely post a higher average once. Both thresholds are set here, before any
-- results are seen.
SELECT_MIN_GAIN  = 0.01   -- one percentage point of usable%
SELECT_WIN_SHARE = 0.70   -- and it must win at least 70% of paired repeats

function SelectCandidate(results, inst)
    local usable = {}
    for _, r in ipairs(results) do
        if r.usable_mean then usable[#usable + 1] = r end
    end
    if #usable == 0 then return nil end

    -- Simplicity order: fewest features first. Among candidates of EQUAL complexity,
    -- the better mean wins - the tie-break is only meant to prefer small models over
    -- big ones, never to choose between two models of the same size.
    --
    -- (This was originally written to fall through to declaration order and then to
    -- the scale name alphabetically, which is arbitrary: on bass it picked
    -- baseline/log(rank) over the equally simple and slightly better baseline/rank
    -- purely because "log" sorts before "rank". Corrected here. The correction cannot
    -- flip a gate outcome - it only ever swaps between candidates of identical
    -- complexity - and it is verified not to change either instrument's verdict.)
    local order = {}
    for i, r in ipairs(usable) do order[i] = r end
    local decl = {}
    for i, c in ipairs(CandidatesFor(inst)) do decl[c.name] = i end
    table.sort(order, function(x, y)
        if x.n_features ~= y.n_features then return x.n_features < y.n_features end
        if x.usable_mean ~= y.usable_mean then return x.usable_mean > y.usable_mean end
        return decl[x.candidate] < decl[y.candidate]
    end)

    local leader = usable[1]
    for _, r in ipairs(usable) do
        if r.usable_mean > leader.usable_mean then leader = r end
    end

    for _, r in ipairs(order) do
        local gain, win_share = PairedDiff(leader, r)
        if not (gain > SELECT_MIN_GAIN and win_share > SELECT_WIN_SHARE) then
            return r, leader, gain, win_share
        end
    end
    return leader, leader, 0, 0
end

-- Gate verdict on the SELECTED candidate, read from the pessimistic end of each
-- interval. Returns passed, an array of reason strings.
function GateVerdict(rec)
    local reasons, passed = {}, true
    if not rec or not rec.usable_mean then
        return false, { 'no result to grade' }
    end
    if rec.usable_lower < PROTOCOL.USABLE_FLOOR then
        passed = false
        reasons[#reasons + 1] = ('usable lower bound %.1f%% is below the %.0f%% floor')
            :format(rec.usable_lower * 100, PROTOCOL.USABLE_FLOOR * 100)
    end
    if rec.miss_upper > PROTOCOL.MISS_CEILING then
        passed = false
        reasons[#reasons + 1] = ('miss upper bound %.1f%% exceeds the %.0f%% ceiling')
            :format(rec.miss_upper * 100, PROTOCOL.MISS_CEILING * 100)
    end
    if rec.rho_mean < PROTOCOL.RHO_FLOOR then
        passed = false
        reasons[#reasons + 1] = ('rho %.3f is below the %.2f floor')
            :format(rec.rho_mean, PROTOCOL.RHO_FLOOR)
    end
    return passed, reasons
end

----------------------------------------------------------------------
-- Per-song residuals for the SELECTED model
----------------------------------------------------------------------

-- Re-runs one candidate over the protocol's own repeats and returns per-song averaged
-- cross-validated predictions: an array of { name, rank, pred, tier_pred, tier_act,
-- dist }, sorted worst tier distance first.
--
-- WHY THIS LIVES HERE, in the decision script, rather than being read off the analysis
-- report. The analysis fits EVERY factor with no ridge on the raw rank scale; the
-- protocol selects a small ridged model on log(rank). Those two models disagree
-- sharply about individual songs, so a worst-10 list taken from the analysis says
-- nothing about the model that would actually ship. Round 6 hit exactly that: the
-- entropy factor moved `surrender` 106 rank points in the selected keys model and only
-- 35 in the analysis fit, which read as "the factor did nothing" from the wrong report.
--
-- Averaging over repeats rather than reporting one split is deliberate: a single fold
-- assignment moves an individual song's prediction by tens of rank points, which is
-- enough to reorder a worst-10 list on noise alone.
function CandidateResiduals(d, target, extra, inst, factor_pos, rec)
    if not rec or not rec.keys then return nil end

    local strata = {}
    for n, ti in ipairs(target) do
        strata[n] = tostring(TierForRank(inst, d.ranks[ti]))
    end

    local sum, cnt = {}, {}
    for rep = 1, PROTOCOL.N_REPEATS do
        local folds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
        local pred = RunOneRepeat(d, target, extra, folds, rec.keys, factor_pos, rec.scale_obj)
        if pred then
            -- RunOneRepeat emits predictions fold by fold in fold order, so walking the
            -- folds the same way maps each one back to its row.
            local k = 0
            for f = 1, #folds do
                for _, ti in ipairs(folds[f]) do
                    k = k + 1
                    local i = target[ti]
                    sum[i] = (sum[i] or 0) + pred[k]
                    cnt[i] = (cnt[i] or 0) + 1
                end
            end
        end
    end

    local rank_lo, rank_hi = RankRange(d, target)   -- target only; see RunProtocol
    local out = {}
    for _, i in ipairs(target) do
        if cnt[i] then
            local p  = ClampRank(sum[i] / cnt[i], rank_lo, rank_hi)
            local tp = TierForRank(inst, p)
            local ta = TierForRank(inst, d.ranks[i])
            out[#out + 1] = { name = d.names[i], rank = d.ranks[i], pred = p,
                              tier_pred = tp, tier_act = ta,
                              dist = math.abs(tp - ta) }
        end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist > b.dist end
        return math.abs(a.pred - a.rank) > math.abs(b.pred - b.rank)
    end)
    return out
end
