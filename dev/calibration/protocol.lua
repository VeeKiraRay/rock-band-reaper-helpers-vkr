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
    -- Auxiliary origins: rows that always train, are never predicted, and carry their
    -- own indicator column so the fit can absorb a scale offset instead of smearing it
    -- across the real factors. rb3_dlc is the target and is not listed here.
    --
    -- ORDER IS PART OF THE ARTIFACT. The indicators are appended in this order, so the
    -- exported keys list ends with is_lego, is_rb2 - and reordering this table would
    -- silently reassign every exported coefficient. Append only.
    --
    -- rb2 is the RB2 disc export. Its ranks are continuous like DLC's (58 of 60 sampled
    -- values sit off a tier floor), unlike RBN's, which are all tier floors and so
    -- cannot be regression targets at all. It starts at the Lego weight because that
    -- number was measured to be insensitive and 13 songs cannot justify tuning a second
    -- one; the analysis report's origin check reports its offset per run.
    -- WHAT THEY ARE ACTUALLY WORTH, measured 2026-08-21 by ablation: run each
    -- instrument's selected model on identical folds with and without the 60 auxiliary
    -- rows, and difference the result.
    --
    --   instrument   pooled   macro    rho     (with aux, minus without)
    --   guitar        +0.15   +0.03   +0.001
    --   bass          +0.03   +0.69   +0.000
    --   drum          +0.46   +1.46   +0.002
    --   vocals        +0.00   +0.22   +0.002
    --   keys           0.00    0.00    0.000   no auxiliary rows exist
    --   real_keys      0.00    0.00    0.000   no auxiliary rows exist
    --
    -- Against paired sds of 0.43-0.79 (pooled) and 0.73-1.83 (macro), only DRUMS shows
    -- anything close to a real effect, at roughly 1 sd on both metrics. Guitar, bass and
    -- vocals gain nothing measurable, and the two keyboard parts cannot gain anything
    -- because neither Lego Rock Band nor the RB2 export has a keyboard chart.
    --
    -- The README used to say these rows "add information without steering the model".
    -- The second half is supported; the first is now known to be near-empty except
    -- possibly on drums. Kept anyway - 60 rows that cost nothing and might be worth half
    -- a point on one instrument are not worth a declared corpus change to remove, and
    -- removing them would alter every published figure for no gain. Recorded so nobody
    -- re-derives it, and so the case for dropping them is not overstated in either
    -- direction.
    --
    -- The 4 `greenday` rows are a separate matter: they are scored into the CSV and
    -- excluded from every fit, so they contribute exactly nothing by construction and
    -- need no measurement.
    AUX_ORIGINS = {
        { origin = 'lego', flag = 'is_lego', weight = 0.3 },
        { origin = 'rb2',  flag = 'is_rb2',  weight = 0.3 },
    },
    -- HOW THE NESTED RIDGE SEARCH SCORES ITS INNER HOLDOUTS. See the RIDGE VALIDATION
    -- block above ChooseRidge for the pre-registration, the arms, and the result.
    --   'unweighted'   every inner row counts 1, whatever origin it came from. What the
    --                  code did until 2026-08-22, and what peer review finding 6 is about.
    --   'weighted'     each inner row counts its training weight, so an aux row counts
    --                  0.30 - the literal reading of the declared origin policy.
    --   'target_only'  aux rows train and are never scored, matching the outer grade.
    RIDGE_VALIDATION = 'target_only',
    -- Peer review finding 8e, two halves. See the block above ClampRank.
    --   CLAMP_BOUNDS  'per_fold'   bounds from each fold's training rows only
    --                 'all_target' the pre-2026-08-22 behaviour, which leaked the
    --                              validation fold's own labels into its clamp range
    --   RHO_ON        'raw'        grade rho on unclamped out-of-fold predictions
    --                 'clamped'    the pre-2026-08-22 behaviour; clamping makes ties, and
    --                              Spearman with ties is a different statistic
    CLAMP_BOUNDS = 'per_fold',
    RHO_ON       = 'raw',
    -- PACK-GROUPED FOLDS. false means the gate keeps dealing individual rows, which is
    -- what every published figure was measured under. See the GROUPED FOLDS block below
    -- RunProtocol for what this is, what it measured, and why moving the gate onto it is
    -- a separate decision rather than a flag flip.
    GROUP_FOLDS = false,
    -- Gate thresholds. USABLE_FLOOR is read against the interval LOWER bound and
    -- MISS_CEILING against the miss rate's UPPER bound - both the pessimistic end, so
    -- a pass cannot come from a lucky split.
    USABLE_FLOOR  = 0.90,
    MISS_CEILING  = 0.05,
    RHO_FLOOR     = 0.70,
    -- The extremes bar, added 2026-08-22. Read against the ENDPOINT BAND's pack-bootstrap
    -- p05 - tiers 0-1 and 5-6 pooled. The bootstrap is preferred because it assumes
    -- nothing, not because Wilson fails here: the band's design effect measures 1.00-1.16,
    -- so the two bounds nearly agree. See the ENDPOINT FLOOR block above GateVerdict for
    -- where 0.80 comes from and what is uncomfortable about it.
    ENDPOINT_FLOOR = 0.80,
    -- One-sided 95%.
    Z = 1.645,
}

----------------------------------------------------------------------
-- FNV-1a 64
----------------------------------------------------------------------

-- Eight lines of pure Lua because this code has to produce the same number under
-- REAPER's interpreter and a bare one, and neither ships a hash function. Not
-- cryptographic and does not need to be: it fingerprints inputs so a report cannot
-- silently describe a CSV that has moved, and it assigns packs to partitions in a way
-- nobody can steer after the fact. Lua 5.4 integers are 64-bit and wrap on overflow,
-- which is the arithmetic FNV specifies. Verified against the published test vectors
-- ("" -> cbf29ce484222325, "a" -> af63dc4c8601ec8c).
local FNV_OFFSET, FNV_PRIME = 0xcbf29ce484222325, 0x100000001b3

function Fnv1a64(s)
    local h, n = FNV_OFFSET, #s
    local i = 1
    while i <= n do
        -- Blocked rather than byte-at-a-time: string.byte returning 4096 values at once
        -- holds a 1 MB file to about 0.02 s, against several seconds for the naive loop.
        local j = (i + 4095 < n) and (i + 4095) or n
        local b = { string.byte(s, i, j) }
        for k = 1, #b do h = (h ~ b[k]) * FNV_PRIME end
        i = j + 1
    end
    return h
end

function Fnv1a64Hex(s) return string.format('%016x', Fnv1a64(s)) end

----------------------------------------------------------------------
-- The reserved test partition
----------------------------------------------------------------------

-- COMMITTED 2026-08-21, BEFORE A SINGLE ELIGIBLE PACK EXISTS. That timing is the entire
-- value of this block, and it is worth being blunt about why.
--
-- The 2026-08-21 peer review's one Blocker: every figure this project reports is
-- development-set repeated CV, and no reserved partition has ever been drawn. Worse
-- than not having drawn one - across 23 rounds every rb3_dlc row has informed worst-
-- residual inspection, factor design, scale choice and candidate selection, so no
-- CURRENT row can ever supply confirmatory evidence, whatever it is later renamed to.
-- Choosing some of them as a "test set" now would produce a number that looks
-- confirmatory and is not. The README has always said the partition was undrawn; what
-- it did not say is that the rows to draw it from were already spent.
--
-- So the test set can only come from packs that have never been walked. This rule
-- decides which ones, and it is written now so that it cannot be written later - after
-- new packs arrive, any rule at all is chosen in the presence of the data it partitions,
-- and an author who has seen a promising pack cannot un-see it. A rule fixed in advance
-- is the only kind whose output is not a decision.
--
-- THE RULE.
--
--   1. A pack that already appears in corpus_scores.csv is DEVELOPMENT, permanently and
--      regardless of its hash. It has been seen. This is not adjustable.
--   2. Any other pack is RESERVED if Fnv1a64(SALT .. pack) % 100 < RESERVED_PCT.
--   3. Whole packs, never rows. The corpus's multi-song packs are thematic, so splitting
--      one leaks related songs across the boundary; a pack-level split also doubles as
--      the domain-shift check. See the README on why the reserved partition was always
--      specified this way.
--   4. Reserved packs are not scored, not plotted, not residual-inspected and not
--      mentioned in a round declaration until the partition is spent. Scoring one "just
--      to see" ends its usefulness silently and permanently - there is no way to tell
--      afterwards that it happened.
--   5. Spending it is a one-time event: freeze candidates and gate, refit on development
--      only, predict the reserved packs once, report whatever comes out. A second look
--      is a development set with extra steps.
--
-- SALT and RESERVED_PCT are part of the commitment. Changing either re-partitions
-- everything and is indistinguishable from choosing a partition; if it ever has to
-- change, the old value stays in this comment and the reason goes in the README.
--
-- RESERVED_PCT WAS 20 WHEN THIS WAS COMMITTED EARLIER ON 2026-08-21. IT IS NOW 100.
-- Recording the change here because the paragraph above says to.
--
-- The original 20% assumed packs arriving a few at a time, where holding back a fifth
-- leaves most of the new material usable for training. What actually turned up the same
-- day was a single batch: roughly 600-700 rb3_dlc songs available against the 330 already
-- walked. At that shape the sizing calculation decides it, and the answer is not close.
--
--   To certify the 90% floor the Wilson lower bound must clear 90%. At an observed 94%
--   that needs n ~ 200; at 96%, n ~ 100. Twenty per cent of ~300 new songs is n ~ 60,
--   whose lower bound at 94% is 86.8%. A partition that size can FALSIFY a collapse and
--   can never CONFIRM the gate - which is the one job it exists for.
--
-- So every unwalked pack is reserved, and the development corpus stays at 330. That is
-- also the peer review's own step 4: refit on the existing development corpus and
-- evaluate once on the new packs.
--
-- WHY CHANGING THIS AFTER SEEING THE BATCH IS NOT THE THING THE RULE FORBIDS. The hazard
-- a pre-committed partition guards against is choosing a split that flatters the model.
-- Reserving MORE data is self-penalising in every direction: it shrinks training, and it
-- enlarges the sample that could contradict the published figures. There is no version of
-- this change that makes the results look better. Lowering the percentage after seeing
-- the data would be the forbidden move; raising it is not.
--
-- The hash is kept rather than replaced by a plain "is it walked" test. At 100 every pack
-- passes the threshold, so the mechanism is inert but intact, and a future epoch that
-- needs a real split gets the same salt and the same arithmetic instead of a rule rebuilt
-- from memory. ALLOCATING A LATER BATCH IS A NEW DECLARATION - once this partition has
-- been spent, "everything unwalked is reserved" stops being the right policy, and the
-- replacement belongs in this comment with its own reasoning.
PARTITION = {
    SALT         = 'rb3-difficulty-reserved-v1',
    RESERVED_PCT = 100,   -- was 20 until 2026-08-21; see above
}

-- Returns true if this pack belongs to the reserved test partition.
--
-- `seen_packs` is the set of pack ids already present in corpus_scores.csv, as
-- { [pack] = true }. Pass it. Omitting it silently turns rule 1 off, which would let an
-- already-spent development pack be reported as held-out - the one mistake this whole
-- block exists to prevent.
function PackIsReserved(pack, seen_packs)
    if not pack or pack == '' then return false end     -- no pack id: cannot be held out
    if seen_packs and seen_packs[pack] then return false end
    return (Fnv1a64(PARTITION.SALT .. pack) % 100) < PARTITION.RESERVED_PCT
end

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

----------------------------------------------------------------------
-- ROUND 16: KEYS - IS THE CHORD COEFFICIENT MEASURING CHORDS, OR THE UNITS NEXT TO IT?
--
-- Declared before anything was run. Prior candidates remain byte-for-byte intact above.
--
-- THE OBSERVATION. chord_size_mean is -12.86 on keys and +12.22 on Pro Keys. Those two
-- models describe the SAME MUSIC, scored from the same notes, and nothing about chords
-- differs between them. What differs is the density factor beside it: keys uses
-- density_peak, which counts GEMS, so a three-note chord triples it; Pro Keys uses
-- attack_density_peak, which counts ATTACKS. The suspicion is therefore that keys'
-- chord_size_mean is not measuring chord difficulty at all - it is dividing chords back
-- out of a gem count, and the negative sign is that division.
--
-- Supporting evidence, not fitted: holding attack rate fixed, the partial correlation of
-- chord_size_mean with the official rank is +0.24 on keys and +0.22 on Pro Keys. It is
-- only +0.08 unconditionally, because chordal parts are struck more slowly - speed is the
-- confound. Guitar, which measures attacks, gives the factor ~0.00; bass omits it.
--
-- THE DESIGN. A 2x2 over the SELECTED keys candidate, whose other six factors are held
-- fixed. The incumbent is one cell, so three are added:
--
--                     with chord_size_mean          without
--   gems              primary+entropy_rel+          +complex_peak-chord
--                     complex_peak (INCUMBENT)
--   attacks           +complex_peak@attacks         +complex_peak@attacks-chord
--
-- Keys only. Pro Keys, guitar and bass already measure attacks and are the CONTROL for
-- this question; re-opening them would widen the experiment without adding evidence. The
-- selection bar is unchanged (1 point AND 70% of paired repeats, ties to the simpler
-- model) and the challengers are appended last, so the incumbent holds unless beaten.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. In BOTH attacks variants, chord_size_mean's fitted coefficient is positive. This
--      is the direct test: if the sign follows the units, the artifact is confirmed.
--   2. The incumbent probably HOLDS on accuracy. primary+ent_rel@attacks scored 91.23%
--      against its 93.77% - a comparison confounded by complex_peak's absence, but the
--      gem reading is also what this project's own finger-load rule predicts for a
--      five-lane keyboard, where each gem needs its own finger. A model can predict
--      better while describing the mechanism worse; that is the expected outcome.
--   3. @attacks-chord loses to @attacks if chord size carries signal beyond the
--      gems-to-attacks conversion. If they tie, conversion is all it was ever doing.
--   4. No cell changes the usable lower bound enough to matter either way - keys' gate
--      failure is a sample-size problem (122 rows), not a specification problem.
--
-- WHATEVER THIS RETURNS, no shipped wording states a difficulty direction for this
-- factor. The UI fix is independent and already made; see difficulty_explain.lua.
for _, c in ipairs({
    { name = 'primary+ent_rel+complex@attacks',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'chord_size_mean', 'playing_s', 'entropy_h2_rel', 'complex_peak' } },

    { name = 'primary+ent_rel+complex-chord',
      keys = { 'total_changes', 'density_peak', 'tight_p10', 'tight_med',
               'playing_s', 'entropy_h2_rel', 'complex_peak' } },

    { name = 'primary+ent_rel+complex@attacks-chord',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'playing_s', 'entropy_h2_rel', 'complex_peak' } },
}) do
    CANDIDATES_KEYS[#CANDIDATES_KEYS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 17: KEYS - DO CHORDS ADD DIFFICULTY ONCE THE UNITS ARE HONEST?
--
-- Declared before anything was run. Prior candidates remain byte-for-byte intact above.
--
-- THE QUESTION ROUND 16 COULD NOT ANSWER. Round 16 established that keys' chord factor
-- was an artifact of counting density in gems, and the selected model now counts attacks
-- and carries no chord term at all. That makes voicing invisible to the score - the same
-- music written as triads and as single notes now scores identically, which is a defensible
-- default and fixes a real complaint (the gems model charged ~28 rank per added note).
--
-- But "invisible" is not the same as "measured to be irrelevant". Holding attack rate
-- fixed, chord_size_mean still correlates +0.24 with the official rank on keys, and
-- chord_change_frac +0.22. Something may be there that the previous parameterisation could
-- never show, because its coefficient was busy doing arithmetic.
--
-- WHAT IS ALREADY KNOWN AND IS NOT REDECLARED. primary+ent_rel+complex@attacks is exactly
-- "the new base plus chord_size_mean" and was fitted in round 16: coefficient +0.020, and
-- usable identical to the base to two decimal places. Chord COUNT, on an attacks base,
-- adds nothing. Round 17 therefore tests different chord measurements, not that one again.
--
-- THE CANDIDATES, all on the round 16 selected base:
--   chord_change_frac  - how often a change re-forms a whole shape rather than moving one
--                        finger. This is the one an author means by "chords are harder":
--                        the cost is re-placing the hand, not the number of keys under it.
--   chord_span_mean    - how far apart the outer notes sit. A stretched shape is harder
--                        than a compact one of the same size.
--   both               - they measure different things and may not substitute.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. chord_change_frac is the strongest of the three (partial +0.22 against
--      chord_span_mean's +0.05) and is the only one with a chance of selection.
--   2. NONE clears the 1-point / 70%-of-repeats bar. The base already carries
--      complex_peak and entropy_h2_rel, which absorb "the shapes keep changing"; the
--      partial correlation is probably measuring that rather than something new.
--   3. If a chord factor is selected, its coefficient is POSITIVE. On an attacks base
--      there is no gem count left to divide out, so a negative sign would mean the
--      artifact has reappeared through some other route and the result must be refused.
--   4. The usable lower bound stays under the 90% floor either way: keys' gate failure is
--      a sample-size problem at n=122, and no single factor closes it.
--
-- IF PREDICTION 2 HOLDS, THAT IS THE ANSWER, NOT A DISAPPOINTMENT: the honest reading
-- becomes "the official keys rank does not measurably reward chord voicing once speed is
-- accounted for", and the voicing-neutral round 16 model is the right thing to ship.
for _, c in ipairs({
    { name = 'r16+chord_change',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'playing_s', 'entropy_h2_rel', 'complex_peak', 'chord_change_frac' } },

    { name = 'r16+chord_span',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'playing_s', 'entropy_h2_rel', 'complex_peak', 'chord_span_mean' } },

    { name = 'r16+chord_change+span',
      keys = { 'total_changes', 'attack_density_peak', 'tight_p10', 'tight_med',
               'playing_s', 'entropy_h2_rel', 'complex_peak',
               'chord_change_frac', 'chord_span_mean' } },
}) do
    CANDIDATES_KEYS[#CANDIDATES_KEYS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 18: VOCALS - TESSITURA ALONGSIDE HARMONY COUNT, NOT INSTEAD OF IT
--
-- Declared before running. Prior candidates remain byte-for-byte intact above.
--
-- WHY THIS ROUND EXISTS. Vocals fails both gate floors (usable lower bound 83.34% against
-- 90%, rho +0.624 against +0.70) and its failure has a shape: it under-predicts the
-- hardest charts by about 117 rank, three times worse than any other instrument's top-end
-- shrinkage (guitar -37, bass -45, keys -40). Two things were ruled out first:
--
--   * NOT a song-level label. Predicting a vocals rank from the OTHER instruments' ranks
--     of the same song reaches only rho +0.219 - the lowest of the six, against guitar's
--     +0.623. Whatever the vocal rank encodes is specific to the vocal chart, so it is
--     reachable in principle. (Guitar, bass and drums lock to a shared groove and predict
--     each other; a singer does not have to.)
--   * NOT the "high AND held" interaction, which round 14 already declared as
--     primary+range+highhold. Re-tested here as super-linear derived terms - sustained
--     high time weighted by the square, and by 2^(excess/6), of the register above G4 -
--     every variant moved the top-end bias by under 1 rank, and two of them made it worse.
--     The two CONTROLS (convexity in time alone, ceiling height alone) beat all of them,
--     which is the reverse of that hypothesis.
--
-- WHAT WAS NEVER TESTED. The tessitura family and vocal_parts have only ever appeared in
-- SEPARATE candidates: primary+range+tess carries top_note and high_time_67 but drops
-- vocal_parts, while the selected primary+range+parts keeps vocal_parts and carries no
-- tessitura at all. Both together was never declared, so "does time spent high help once
-- harmony count is already in" has no answer. It should: high_time_70 is the single
-- largest discriminator of the charts ranked 400+, sitting +1.28 sd above the rest of the
-- corpus, and it is absent from the shipped model. The model currently knows how HIGH a
-- singer goes (pitch_p90, notated_range) and not how LONG they stay up there.
--
-- pc_change_rate joins because the exploratory pass suggested the demand is high AND
-- MOVING rather than high and sustained - which fits the residual list, where the worst
-- misses are melismatic wide-ranging singing (four Queen charts and two Iron Maiden) and
-- not held-note ballads.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. parts+tess beats the incumbent on rho by at least +0.03. The exploratory pass put
--      it at +0.684 against +0.624, and rho is the floor vocals misses by the wider
--      margin.
--   2. parts+tess+move is the strongest of the four and the only one with a chance of
--      selection.
--   3. NONE passes the gate. The exploratory usable mean was 88.47%, whose Wilson lower
--      bound at n=313 is near 85% - still short of 90%, and rho +0.684 is still short of
--      +0.70. This round narrows the gap; it does not close it.
--   4. The top-end bias improves by at least 10 rank but stays worse than -80, i.e. the
--      hardest charts remain materially under-rated even when the round succeeds.
--
-- The exploratory numbers above are NOT evidence. They came from searching ~10 variants
-- against the same rows, which is exactly what inflates a selection estimate; they are
-- recorded only to make these predictions falsifiable. The protocol's numbers are the
-- ones that count, and prediction 1 is the one that is genuinely at risk.
for _, c in ipairs({
    -- The incumbent plus time-spent-high. The minimal test of the round's question.
    { name = 'parts+tess',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70' } },

    -- With the ceiling as well as the time, since one onset at the top and a sustained
    -- tessitura are different demands and top_note alone was round 11's weaker answer.
    { name = 'parts+tess+ceiling',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'top_note' } },

    -- High AND MOVING. pc_change_rate is how often the melody changes pitch class.
    { name = 'parts+tess+move',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate' } },

    -- The discrimination check: does re-entering the high register cost something beyond
    -- total time spent there? If this ties parts+tess, the answer is no.
    { name = 'parts+tess+reentry',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'high_reentry_rate_70' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 19: VOCALS - THE PHRASE AS A PITCH JOURNEY
--
-- Declared before running. Prior candidates remain byte-for-byte intact above.
--
-- WHY THIS ROUND EXISTS. parts+tess+move still fails both floors (85.12% against 90%,
-- rho +0.668 against +0.70) and still under-predicts its hardest charts by ~104 rank.
-- Two things were established before any factor was proposed:
--
--   * THE MISSES ARE INVISIBLE, NOT MIS-WEIGHTED. Across the ten worst-predicted charts,
--     the mean |z| on all twelve of the model's own factors is <= 0.42. Nothing about
--     them is unusual to the model. It is not weighting a signal badly; it has none.
--   * THEY ARE VOCAL-SPECIFIC. The same ten songs miss by -3.08 sd on vocals against
--     -0.19 guitar, -0.94 bass, -0.67 drums, -0.43 keys, -0.89 Pro Keys. Whatever this
--     is, it is in the singing and not in the song.
--
-- Reading those charts by hand then found a shape the vocabulary has no word for: a
-- single phrase walking from MIDI 50 to 66, and constant up-and-down motion inside long
-- phrases sung without a rest.
--
-- WHAT WAS MISSING, PRECISELY. notated_range is the whole song. pc_interval_* is one step
-- at a time and is mod-12, so an octave-scale leap reads as small. phrase_complex_p90 is
-- density x mean pitch-CLASS step. Nothing measured how far a phrase TRAVELS, and nothing
-- measured how wide one phrase REACHES. The two are declared together because either
-- alone conflates real cases: a climb from 50 to 66 and a jigsaw crossing four semitones
-- four times have the SAME travel and very different spans, while one big leap and a slow
-- wide climb have the same span and very different travel.
--
-- Raw semitones, on pitched notes, aggregated per phrase with no time denominator - the
-- same reversal round 12 made for notated_range, applied to the phrase instead of the
-- song.
--
-- MEASURED AND REJECTED BEFORE DECLARATION, so none of these is retried:
--
--   * PER-PHRASE COUNTS - "divide the density family by the phrase marker instead of by
--     seconds, so a slow song is not read as sparse". Syllables-per-phrase already exists
--     as phrase_syl_mean and is -0.001 against rank; it was fitted as primary+phrase and
--     scored -8.72% at 0% of paired repeats. Pitch-changes-per-phrase measures +0.237
--     against pc_change_rate's +0.440 - the per-phrase currency HALVES the signal - and is
--     +0.78 collinear with phrase length, so it mostly injects phrase-length noise. The
--     denominator instinct is right and is why travel carries no denominator at all; the
--     payload has to be semitones, not counts.
--   * TEMPO. bpm derived from qn against seconds is +0.026 against rank and +0.74 / +0.73
--     collinear with tight_p10 / tight_med, which the incumbent already carries. That is
--     arithmetic, not coincidence: syl_density_avg [syl/s] x tight_med [QN/syl] is QN/s,
--     so the model already holds both the per-second and the per-beat view of speed. The
--     independent proxy agrees - bpm_at_first_note, a meta column in the CSV since round
--     8, is +0.011 against the vocal rank over 328 rows. Note also that the hypothesis
--     ("per-second density under-reads slow charts") is an INTERACTION, and an additive
--     standardized term cannot express one.
--   * PHRASE-FINAL HOLD - "long phrases ending on a held note". Every form measures
--     NEGATIVE against rank: last-note seconds mean -0.114, p90 -0.047, as a fraction of
--     the phrase -0.151. Phrases ending on a held note go with EASIER charts. This is the
--     phrase-local refinement of round 13's breath family, and it is worse than the
--     whole-song version, which never earned selection either.
--   * PHRASE LENGTH p90. +0.060, against the existing phrase_len_mean's +0.058 and ~0.9
--     collinear with it. Round 12 already answered this.
--   * TRAVEL PER SECOND (+0.393, +0.82 collinear with pc_change_rate - a restatement of
--     an in-model column) and TRAVEL PER NOTE, which is semi_interval_mean_p, already a
--     column and +0.87 collinear with in-model pc_interval_mean. Per phrase with no
--     denominator is the only form carrying information the CSV lacks.
--   * TIME SIGNATURE, and it needs no column: only 17 of 543 corpus songs are primarily
--     non-4/4, and all 17 are 3/4, 6/8, 6/4 or 2/4 - familiar meters. The genuinely
--     awkward signatures (5/x, 7/x, 11/x) exist only as seconds-long fragments. There is
--     nothing to fit, the same finding as the concentrated keys solo in round 16. 34.6%
--     of songs DO change meter at least once, which is well populated - but that is a
--     song-level property, and the cross-instrument result above says these misses are
--     not song-level.
--
-- The exploratory figures above are NOT evidence. They came from screening ~13 variants
-- against the same rows, which is exactly what inflates a selection estimate, and this
-- document's most repeated error is that standalone rho does not predict fitted gain in
-- either direction. They are recorded to make these predictions falsifiable and to
-- justify the FORM chosen, nothing more.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. parts+tess+move+travel is the strongest of the five and the only one with a real
--      chance of selection. phrase_travel_p90 screened at +0.452 standalone, above
--      notated_range (+0.413) and pc_change_rate (+0.424).
--   2. TRAVEL BEATS SPAN. How much ground a phrase covers matters more than how far it
--      reaches, because the residual list is melismatic wide-ranging singing rather than
--      one big leap. If span wins instead, the mechanism is reach and not motion, and the
--      wording of any shipped explanation has to change with it.
--   3. THE p90 TWIN BEATS THE MEAN TWIN on both quantities. Whole-song means erase the
--      small number of decisive phrases - the round-14 argument, restated.
--   4. @phrasespan LOSES to the addition. phrase_span_p90 is only +0.49 collinear with
--      notated_range, so they are different questions and dropping the song-level one
--      costs information rather than tidying it away.
--   5. NONE PASSES THE GATE. Expect rho +0.69 to +0.72 and the usable lower bound still
--      under 88%. On the ten worst charts these two columns sit at the largest z of
--      anything measured on them, and still not large enough to explain a -104 bias.
--   6. The top-end bias improves from -104 to between -80 and -95, and no further.
--
-- IF PREDICTION 1 FAILS AND NOTHING IS SELECTED, that is the round's answer and it is
-- worth as much as a win: it would mean the phrase-level pitch journey is measurable and
-- does not move the official vocal rank, which together with the five rejections above
-- closes the last mechanism this corpus can reach for on vocals.
for _, c in ipairs({
    -- Travel alone: the round's primary hypothesis, kept separable from everything else.
    { name = 'parts+tess+move+travel',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'phrase_travel_p90' } },

    -- Span alone, so reach and motion are never entangled inside one number.
    { name = 'parts+tess+move+span',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'phrase_span_p90' } },

    -- Both - the round's best guess at where vocals lands.
    { name = 'parts+tess+move+phrase_pitch',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate',
               'phrase_travel_p90', 'phrase_span_p90' } },

    -- AGGREGATION SUBSTITUTION: identical but for mean instead of p90. Declared rather
    -- than quietly dropped, for the same reason high_time_67 and high_time_70 both exist
    -- - the exploratory pass already knows which measures better, so picking it in
    -- silence would be exactly the fishing this file exists to prevent.
    { name = 'parts+tess+move+phrase_pitch@mean',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate',
               'phrase_travel_mean', 'phrase_span_mean' } },

    -- RANGE SUBSTITUTION, same feature count as the incumbent: is the demand the span of
    -- the SONG or the span of a PHRASE? Declared later than parts+tess+move, so the
    -- incumbent wins the simplicity tie and this must CLEARLY beat it to be selected.
    { name = 'parts+tess+move@phrasespan',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'phrase_span_p90', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 20: VOCALS - HOW THE HARMONY COUNT ENTERS THE MODEL
--
-- Prior candidates remain byte-for-byte intact above.
--
-- THIS ROUND IS DECLARED AFTER MEASUREMENT, AND SAYS SO. Every candidate below was
-- already fitted on these rows under these fold seeds before this block was written, so
-- the "predictions" further down are not blind and must not be read as though they were.
-- The declaration still does two things worth doing: it FIXES the candidate set, so no
-- further shape gets tried until a new round says so, and it puts the reasoning in the
-- artifact, so a later reader can see why the shipped model stopped being linear. Every
-- other round in this file was declared first; this one was not, and the difference is
-- recorded rather than smoothed over.
--
-- WHY IT EXISTS. vocal_parts is fitted as a NUMBER, which forces the model to assert
-- that going from one singer to two costs exactly what going from two to three costs.
-- Nothing ever checked that. Fitting the other eleven factors and reading the residual
-- by level says it is false:
--
--     parts   n     mean residual   worth at the anchor   step
--       1     53         -0.0772            -18 rank
--       2     87         -0.0787            -19 rank      -0.4 rank
--       3    187         +0.0595            +15 rank       +34 rank
--
-- One part and two parts are the SAME LEVEL. The whole effect is the step to three. A
-- linear term cannot express that, so it splits the difference and over-credits every
-- two-part song by about +12 rank - 87 of 328 rows.
--
-- WHAT THE COUNT IS ACTUALLY A PROXY FOR. It is a label, not a measurement: the
-- (vocal_parts N) integer out of songs.dta, sitting beside twelve measured columns, and
-- the rank it predicts grades PART VOCALS alone - HARM1/2/3 are never read. Three parts
-- is the HOUSE DEFAULT (187 of 328, 57%), so the fitted term is not "harmony adds work"
-- but "an arrangement that did not earn full harmonies is a smaller production". That
-- also explains the step's shape: an author adds HARM2 for any backing vocal worth
-- capturing, which is a low bar a lot of ordinary songs clear, while HARM3 needs three
-- distinct simultaneous lines and selects for elaborate arrangements.
--
-- MEASURED AND REJECTED BEFORE DECLARATION:
--
--   * READING THE HARMONY TRACKS. The obvious upgrade is to stop trusting the count and
--     measure whether HARM2/HARM3 are real parts or the lead doubled. Swept over every
--     corpus MIDI: a harmony is almost never a unison double (same pitch as the lead:
--     mean 0.124, median 0.030). The typical HARM2 is a DIFFERENT pitch on the SAME words
--     at the SAME time covering about 40% of the chart - musically a second part,
--     structurally dependent. Duplication of the lead's note starts AND ends is bimodal:
--     29 of 461 harmony tracks (6.3%) duplicate at exactly 1.000, ZERO sit between 0.999
--     and 1.000, and only 5 between 0.990 and 0.999. Authors either paste the lead's
--     rhythm or write something else. Fitted every way it can be fitted:
--         @parts_eff at 0.90 / 0.95 / 0.99 / 1.00   +0.40 / +0.37 / +0.49 / +0.52 points
--         @parts_graded  (each harmony discounted by how mirrored it is)  -0.98, 0% wins
--         @harm_indep    (independence replacing the count)               -1.55, 0% wins
--         +harm_indep / +harm_cover  (measurement BESIDE the count)       +0.21 / +0.09
--     Three findings. A graded discount is actively HARMFUL, because it drags 68.6% of
--     songs below their declared count and erases the production-scale reading that was
--     doing the work. Only the STRICTEST cut-offs help, which agrees with the bimodality.
--     And the best of them is +0.52 against a 1.00-point bar while moving 23 of 328 rows,
--     so it is half a bar short for a new reader path through HARM1/2/3. NOT PURSUED, and
--     no candidate below names a harmony column. One asymmetry is recorded without being
--     acted on: 6% is HARMONIX's authoring practice, and a custom author copy-pasting
--     harmonies is the fast way to write them, so this may matter more to the tool's
--     users than to the corpus that calibrates it. That is a reason to have measured it,
--     not a reason to ship an unearned column.
--   * DROPPING THE COUNT ALTOGETHER. -1.25 points at 10% of paired repeats. The term is
--     small but it is real, so the question is its shape and not its presence.
--
-- WHAT WAS ALREADY MEASURED, since these are not predictions:
--   1. @parts_step3 posts 88.63% / rho +0.674 against the incumbent's 88.35% / +0.668,
--      a paired +0.27 points at 40% of repeats. It does NOT clear the selection bar.
--   2. @parts_free ties @parts_step3 exactly (88.63%). The extra degree of freedom buys
--      NOTHING, which is the round's real result: given a fit that is not told the two
--      steps are equal, it does not use the permission. That is what makes the step a
--      finding rather than a curve-fit.
--   3. @parts_log is WORSE than the incumbent (-0.21 points, 10% of repeats). The shape
--      is a step, not diminishing returns.
--   4. The gate still fails, and by roughly the same margin: 85.4% against the 90% floor
--      and rho +0.674 against +0.70. This round changes what the model CLAIMS, not
--      whether vocals can ship.
--
-- SO WHY SELECT IT AT ALL. Not on the gain - +0.27 at 40% of repeats is noise, and the
-- bar exists precisely to refuse that. @parts_step3 carries the SAME feature count as the
-- incumbent, and the declared tie-break among equal-complexity candidates is the better
-- mean (see SelectCandidate). It wins on mean, on rho and on the gate lower bound
-- simultaneously, having been declared as one of three competing shapes rather than
-- picked from a sweep. If the protocol run disagrees, the incumbent stays.
for _, c in ipairs({
    -- The step the residual pass pointed at. Same k as the incumbent, so it can only
    -- arrive through the equal-complexity tie-break, never by clearing the gain bar.
    { name = 'parts+tess+move@parts_step3',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'parts_3',
               'high_time_70', 'pc_change_rate' } },

    -- SHAPE SUBSTITUTION: diminishing returns instead of a step, so the round tests
    -- "which shape" rather than "linear or the one shape that was measured to win".
    { name = 'parts+tess+move@parts_log',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'parts_log',
               'high_time_70', 'pc_change_rate' } },

    -- THE ASSUMPTION-FREE CONTROL, and the one that makes the round interpretable: one
    -- coefficient per step, so the fit is told nothing about how the levels relate. If
    -- this beats @parts_step3 the step is too crude; if it ties, the levels really do
    -- collapse. k+1, so it must clearly beat both to be selected.
    { name = 'parts+tess+move@parts_free',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'parts_2', 'parts_3',
               'high_time_70', 'pc_change_rate' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

----------------------------------------------------------------------
-- ROUND 22: DRUMS - THE PEAK COLUMNS COUNT GEMS NOBODY HAS TO HIT
--
-- Declared before running. Prior candidates remain byte-for-byte intact above.
--
-- FOUND BY READING A CHART, NOT THE CORPUS, which is worth saying because it is the
-- second time that has produced something (the finger-load rule was the first).
-- `makemesmile2` is predicted 550 against an official 292 - the most over-predicted drum
-- chart on record, tier 6 against an official tier 4. The author's reading was that it is
-- an endurance chart with a constant half-beat kick, hard but not that hard.
--
-- The cause is its ending: an 11.7 s roll lane carrying 48 hand notes per measure, which
-- is the densest passage in the song and therefore sets density_peak for the whole chart.
-- A roll lane is a LENIENCY DEVICE - the notes under it are a free-play region and the
-- player is not required to hit them - so counting them literally reads the easiest bar in
-- the song as the hardest. Excluding roll-covered gems from the peaks moves it 550 -> 368,
-- tier 6 -> 5 against an official 4. This is the same class of error the Pro Keys
-- glissando lane already avoids via gliss_frac, applied to the instrument where the
-- device is common: 2.7% of drum playing time corpus-wide sits under a 126/127 lane.
--
-- WHAT WAS RULED OUT FIRST, so the substitution is not a guess:
--   * NOT THE KICK. kick_density_peak is z +0.86 on this chart, unremarkable, and the
--     model's kick coefficient is doing what it should.
--   * NOT FIXABLE BY SWAPPING FACTORS. complex_peak in place of density_peak moves the
--     prediction by +0.24 rank. The measurement is right; its INPUT is wrong.
--   * NOT A LABEL DISPUTE. The chart is not in WEIRDLY_SCORED and the author agrees it is
--     genuinely hard, only not tier 6.
--
-- NEW TWINS RATHER THAN A REDEFINITION. density_peak, attack_density_peak and
-- hand_density_peak are fitted in five shipped models. Changing them in place would
-- re-open every instrument at once and the rescore's own diff check (every pre-existing
-- column must read 0% moved) would fire on all of them, hiding any real regression in the
-- noise. The twins carry the originals' values verbatim on any instrument with no roll
-- lanes, so this is a pure drums test and the guitar/bass/keys rows are untouched.
--
-- NOT FOLDED IN, and deliberately: the guitar and bass TREMOLO (126) and TRILL (127)
-- lanes are also free-play regions and the same argument would seem to apply. It has not
-- been measured, those lanes are far rarer, and one chart's worth of reasoning about
-- drums is not evidence about guitar. A separate round, if ever.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. full_drum@noroll beats full_drum. Drums is already the strongest instrument
--      (93.38% lower bound) so the headroom is small, and the gain will be under a point.
--   2. THE GAIN IS CONCENTRATED, NOT BROAD. Only 2.7% of drum playing time is under a
--      lane, so most charts will not move at all. If usable% rises by more than a point
--      something other than roll lanes has changed and the result should be distrusted.
--   3. makemesmile2's own prediction improves by at least 100 rank. This is the one
--      number the round was built from and it is the one that would falsify it.
--   4. The partial swap (density only, leaving attacks and hands literal) is WORSE than
--      swapping all three, because the lane inflates every count that passes through it.
for _, c in ipairs({
    -- All three peaks read with roll-covered gems discounted.
    { name = 'full_drum@noroll',
      keys = { 'playing_s', 'density_avg', 'density_peak_noroll', 'change_rate',
               'attack_density_avg', 'attack_density_peak_noroll',
               'tight_p10', 'tight_med', 'chord_size_mean', 'chord_span_mean',
               'chord_change_frac', 'move_mean', 'move_p90', 'anchor_frac',
               'kick_density', 'kick_density_peak', 'hand_density_peak_noroll',
               'stick_size_mean', 'tom_frac', 'roll_frac', 'offbeat_frac',
               'pro_stations_peak', 'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },

    -- The discrimination check behind prediction 4: only the gem peak swapped, so the
    -- attack and hand peaks still count the lane. If this ties the full swap, the lane
    -- only ever inflated one column.
    { name = 'full_drum@noroll_density',
      keys = { 'playing_s', 'density_avg', 'density_peak_noroll', 'change_rate',
               'attack_density_avg', 'attack_density_peak',
               'tight_p10', 'tight_med', 'chord_size_mean', 'chord_span_mean',
               'chord_change_frac', 'move_mean', 'move_p90', 'anchor_frac',
               'kick_density', 'kick_density_peak', 'hand_density_peak',
               'stick_size_mean', 'tom_frac', 'roll_frac', 'offbeat_frac',
               'pro_stations_peak', 'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },
}) do
    CANDIDATES_DRUM[#CANDIDATES_DRUM + 1] = c
end

----------------------------------------------------------------------
-- ROUND 23a: DRUMS - COMPLEXITY-WEIGHTED PEAK DENSITY, RE-ASKED
--
-- Declared before running. Prior candidates remain byte-for-byte intact above.
--
-- WHY IT IS BEING ASKED AGAIN. `complex_peak` is peak (gems per window x conditional
-- entropy of relative motion), i.e. the measurement that says the same note count is
-- harder spread across lanes than repeated on one. It has been in the CSV since round 6
-- and is carried by NO declared drum candidate. It was tested once against the round-18
-- `full_drum` and gained +0.24 points - a quarter of the bar, and easy to read as "the
-- idea is right and the corpus does not care".
--
-- That test was confounded, and round 22 removed the confound. The old `density_peak`
-- counted every gem under a roll lane, so a single-lane roll drove it to an extreme while
-- `complex_peak` correctly read the same passage as low-complexity. The two columns were
-- therefore competing to describe the SAME artifact, and the fit could take either.
-- `makemesmile2` is the case in one line: z +7.24 on density_peak against +1.18 on
-- complex_peak. With the incumbent's peaks now roll-aware, that disagreement is gone and
-- the question "does lane spread matter beyond raw rate" is being asked cleanly for the
-- first time.
--
-- The author's framing, which is the same mechanism from the other side: a fast single-lane
-- snare roll and the same note count moving around the kit are not equally hard, and the
-- roll fix only removed the cases where the game says so with a marker. Where an author
-- charts a dense single-lane passage WITHOUT a lane marker, nothing currently reads it as
-- easier.
--
-- COSTS NO RESCORE. complex_peak is column 70 of the existing CSV.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. +complex gains MORE than the +0.24 it managed against the pre-roll-fix incumbent,
--      because the confound it was fighting is gone.
--   2. It still does NOT clear the bar. Drums is already the strongest instrument at a
--      94.37% lower bound, it already carries 26 factors, and there is little headroom
--      left above it.
--   3. @complex LOSES to +complex. Raw peak rate and complexity-weighted peak rate are
--      different questions; dropping the raw one should cost information rather than tidy
--      it away.
--   4. THE DIAGNOSTIC THAT DECIDES HOW TO READ ALL OF THE ABOVE: the measured pairwise
--      correlation of complex_peak against density_peak_noroll on drum rows. It is +0.88
--      with density_peak on KEYS, and if drums is similar then this round is restating one
--      observation and prediction 1 fails. Report it either way, before interpreting any
--      gain.
for _, c in ipairs({
    -- Beside the raw peak, not instead of it. k=27 against the incumbent's 26, so it must
    -- clearly beat it and cannot arrive on a tie-break.
    { name = 'full_drum@noroll+complex',
      keys = { 'playing_s', 'density_avg', 'density_peak_noroll', 'change_rate',
               'attack_density_avg', 'attack_density_peak_noroll',
               'tight_p10', 'tight_med', 'chord_size_mean', 'chord_span_mean',
               'chord_change_frac', 'move_mean', 'move_p90', 'anchor_frac',
               'kick_density', 'kick_density_peak', 'hand_density_peak_noroll',
               'stick_size_mean', 'tom_frac', 'roll_frac', 'offbeat_frac',
               'pro_stations_peak', 'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes', 'complex_peak' } },

    -- The sharper test: if complexity-weighted peak density is the better MEASUREMENT, it
    -- should be able to replace the raw one rather than sit beside it. Same k as the
    -- incumbent, so this one can arrive on the equal-complexity tie-break.
    { name = 'full_drum@noroll@complex',
      keys = { 'playing_s', 'density_avg', 'complex_peak', 'change_rate',
               'attack_density_avg', 'attack_density_peak_noroll',
               'tight_p10', 'tight_med', 'chord_size_mean', 'chord_span_mean',
               'chord_change_frac', 'move_mean', 'move_p90', 'anchor_frac',
               'kick_density', 'kick_density_peak', 'hand_density_peak_noroll',
               'stick_size_mean', 'tom_frac', 'roll_frac', 'offbeat_frac',
               'pro_stations_peak', 'entropy_h2', 'entropy_h2_rel',
               'notes_total', 'total_changes' } },
}) do
    CANDIDATES_DRUM[#CANDIDATES_DRUM + 1] = c
end

----------------------------------------------------------------------
-- ROUND 21: VOCALS - THE PASSAGE WITH NO ROOM TO BREATHE
--
-- Declared before running. Prior candidates remain byte-for-byte intact above.
--
-- WHY THIS ROUND EXISTS. Rounds 13 and 19 both went at sustain and both measured ONE NOTE
-- at a time - longest_note_s, breath_load, longtime_frac, and round 19's phrase-final
-- hold, which came back negative in every form. That vocabulary cannot see the shape the
-- worst-predicted charts actually have: twenty short syllables sung back to back with no
-- gap, which reads as twenty easy notes and is one long demand on the air.
--
-- The author's framing, and it is the right one: look for the notes with practically no
-- room to breathe. A breath group is a maximal run whose gaps are all shorter than a
-- threshold. It is the sustain counterpart to round 19's phrase geometry - that measured
-- where a phrase GOES, this measures how long the singer is committed before the next
-- chance to inhale.
--
-- ON ALL NOTES, NOT THE @pitched TWINS. Round 19 built on psegs; this deliberately does
-- not. A fast rapped or shouted passage needs air like any other, and
-- `killinginthename` is 0 of 628 pitched - a pitched-only reading would report no breath
-- demand for the chart most obviously made of them. Movement inside a group is the one
-- exception and steps between consecutive PITCHED notes, since a talkie's written pitch
-- is not scored and must not invent motion.
--
-- THRESHOLD CHOICE IS THE ROUND'S REAL RISK, and it was made on mechanism rather than on
-- the best number. 50 ms is "no gap at all", continuous phonation; 100 ms is a quick
-- catch-breath. A prototype swept 20 / 50 / 100 / 150 / 200 ms and the standalone
-- correlation keeps RISING through 150 ms (movemax +0.213 at 50, +0.367 at 100, +0.417 at
-- 150). Those wider thresholds are NOT declared, because at 150 ms and beyond
-- `weirdscience` - a chart that already scores near-correctly on agility and does not
-- need a sustain bump - gains as much as the underperformers do. That is the signature of
-- a column measuring legato phrasing rather than absence of breathing room, and taking
-- the better standalone number would have been exactly the fishing this file exists to
-- prevent. 20 ms is also excluded, and for a concrete reason: at that width MOVEMENT
-- inside a group is 0.000 for every song sampled - the groups are too short to contain
-- any, so the measure stops existing.
--
-- MEASURED AND REJECTED BEFORE DECLARATION:
--   * PHRASE-FINAL HOLD, PHRASE LENGTH p90, PER-PHRASE COUNTS, TEMPO, TIME SIGNATURE -
--     all five recorded under round 19 above and none retried here.
--   * DE-SHRINKING THE PREDICTION, which is the other way to attack a top-end bias.
--     Measured across all six instruments and it is worse on four, and MONOTONICALLY
--     worse on vocals (88.4 -> 87.2 -> 86.3 -> 86.0 at 1.15 / 1.30 / 1.50x). See the
--     README finding "The fit/grade mismatch is already spent".
--
-- THE PROTOTYPE NUMBERS BELOW ARE NOT EVIDENCE AND ARE NOT EVEN REPRODUCIBLE HERE. They
-- came from a scratch implementation that grouped notes slightly differently and screened
-- roughly twenty variants against these same rows. They justify the FORM and the
-- thresholds; they do not predict the fitted gain, and this document's most repeated
-- error is assuming standalone rho does.
--
-- PRE-REGISTERED PREDICTIONS:
--   1. breath_mean_50 is the strongest single addition. The prototype put it at +0.73,
--      the best of anything measured on vocals in that session, and notably it did that
--      on a standalone rho of -0.109 - the clearest case yet of the two disagreeing.
--   2. THE HONEST GAIN IS NEARER +0.4 THAN +0.73. Twenty variants on one set of rows
--      inflates a selection estimate, and this is the round where that correction is
--      being stated in advance rather than discovered afterwards.
--   3. NONE PASSES THE GATE. Vocals needs +4.9 points of usable lower bound and +0.03 of
--      rho; nothing in this family is that size.
--   4. THE MIXED-THRESHOLD PAIR BEATS EITHER ALONE. Duration wants the tight threshold
--      (at 100 ms `weirdscience` merges into long passages it does not sing) and movement
--      wants the wide one (at 50 ms there is barely room to move inside a group). If the
--      pair does NOT win, the two quantities are one thing and the substitution structure
--      is wrong.
--   5. The max forms beat the mean forms on movement and LOSE on duration. Movement is
--      concentrated in a few passages; time without air is not.
--
-- IF NOTHING IS SELECTED, that is the answer and it closes the sustain thread: rounds 13,
-- 19 and 21 will then have measured single-note hold, phrase-final hold, and continuous
-- passage length, and none of the three moves the official vocal rank.
for _, c in ipairs({
    -- Duration at the tight threshold - the round's primary claim, alone.
    { name = 'parts+tess+move+breath',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'breath_max_50' } },

    -- THRESHOLD SUBSTITUTION, never fitted beside the 50 ms twin.
    { name = 'parts+tess+move+breath@100',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'breath_max_100' } },

    -- AGGREGATION SUBSTITUTION on duration, and the prototype's strongest single column.
    { name = 'parts+tess+move+breath@mean50',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'breath_mean_50' } },

    -- Movement inside a passage rather than its length: not merely committed, but
    -- committed AND having to move while committed.
    { name = 'parts+tess+move+breathmove',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'breath_movemax_100' } },

    -- AGGREGATION SUBSTITUTION on movement.
    { name = 'parts+tess+move+breathmove@mean',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate', 'breath_move_100' } },

    -- BOTH, each at the threshold its own mechanism argues for. Prediction 4 is the test
    -- of whether the two are separate demands at all, and this is the candidate the round
    -- was designed around.
    { name = 'parts+tess+move+breath_both',
      keys = { 'syl_density_avg', 'syl_density_peak', 'tight_p10', 'tight_med',
               'pc_interval_mean', 'playing_s',
               'notated_range', 'pitch_p90', 'octave_jump_rate', 'vocal_parts',
               'high_time_70', 'pc_change_rate',
               'breath_max_50', 'breath_movemax_100' } },
}) do
    CANDIDATES_VOCALS[#CANDIDATES_VOCALS + 1] = c
end

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
-- A THIRD SCALE WAS BUILT, MEASURED, AND IS NOT HERE. log(rank) fixes the SCALE half of
-- the fit/grade mismatch; the LOSS half - squared error not knowing where the boundaries
-- are - was closed by constructing the tier coordinate that maps threshold k to exactly k
-- and interpolates log-linearly inside each band, so squared error in it IS squared tier
-- distance. It verified (thresholds land on their own tier number, inv round-trips to
-- 1e-9) and there was real room to gain: interior band widths in log space vary 1.25x on
-- guitar but 2.29x on keys and 2.16x on drums, so log(rank) is demonstrably not already
-- tier-uniform. Measured against each instrument's OWN shipped scale - keys and real_keys
-- ship on `rank`, so grading it against log(rank) would use a baseline neither of them
-- has - it is worth nothing:
--
--     guitar -0.06 (30% of repeats)   bass +0.06 (50%)   drum +0.27 (60%)
--     keys   +0.15 (40%)              real_keys +0.04 (10%)   vocals -0.18 (30%)
--
-- and rho moves by at most 0.003 anywhere. Not added, because a scale that changes
-- nothing still has to be carried by the exporter, the shipped model artifact (which
-- holds no instrument field, so DIFFICULTY_SCALE_INV could not resolve the thresholds
-- without a schema bump) and every future reader. See README, "The fit/grade mismatch is
-- already spent", for the miss anatomy that explains why: misses need a median 7-28 rank
-- of movement while correct rows carry 48-63 of slack, so they are model error and not
-- boundary-adjacent accidents a loss function could reclaim.
SCALES = {
    { name = 'rank',      fwd = function(v) return v end,
                          inv = function(v) return v end },
    { name = 'log(rank)', fwd = function(v) return math.log(math.max(1, v)) end,
                          inv = function(v) return math.exp(v) end },
}

----------------------------------------------------------------------
-- Equal-tier-weighted usable rate
----------------------------------------------------------------------

-- Within-one-tier accuracy with every OCCUPIED tier weighted equally, rather than every
-- row. Takes parallel arrays of predicted and actual tiers, the same ones TierDistance
-- reads, so it costs a second pass over data already in hand and no extra fitting.
--
-- WHY EVERY CANDIDATE GETS THIS AND NOT JUST THE SELECTED ONE. The gate is pre-registered
-- to move from pooled to macro (see TierDiagnostics). SelectCandidate ranks by pooled
-- usable%, so moving the gate without knowing what macro would have chosen means
-- selecting on one quantity and grading on another - the fit/grade mismatch this project
-- already has a finding about, reintroduced through the back door. Measuring it for every
-- declared candidate turns "would a different model win?" into a question with an answer
-- in the report.
--
-- IT IS REPORTED AND NEVER SELECTED ON. SelectCandidate still reads usable_mean, and must
-- keep doing so until the gate actually moves, because switching the selection rule is a
-- new experiment in its own right. The honest hazard to name: once macro is visible for
-- every candidate, adopting it BECAUSE it makes something pass is exactly the move the
-- pre-registration exists to prevent. The reason to adopt it has to be the one already
-- written down - that a constant predictor scores a fixed 3/7 under macro and anywhere
-- between 45.86% and 77.13% under pooled - and not which candidate it favours.
--
-- ----------------------------------------------------------------------------
-- MEASURED 2026-08-21: WOULD SELECTING ON MACRO ACTUALLY CHANGE ANYTHING?
--
-- The report names a pooled leader and a macro leader per instrument, and they differ on
-- guitar, bass and drum. A leader is not a selection though - the simplicity order and
-- the ">1 point AND >70% of paired repeats" bar sit in between. Running the rule against
-- paired MACRO differences instead of paired pooled ones:
--
--   guitar   full@attacks / rank            +0.98 macro, wins 60%   -> fails both
--   bass     baseline+ent_rel@attacks/rank  +0.74 macro, wins 60%   -> fails both
--            primary+entropy@attacks/log    +0.63 macro, wins 80%   -> fails the point bar
--   drum     full_drum@noroll / rank        +1.56 macro, wins 90%   -> CLEARS BOTH
--
-- So only DRUMS actually reselects, and it does so by changing scale rather than
-- features: the same 26 columns on `rank` instead of `log(rank)`. That is the expected
-- direction - log buys proportional accuracy by compressing the top end, which pooled
-- barely notices and macro weights heavily - and it enters through the equal-complexity
-- tie-break, which a README finding already warns can carry a gate decision on noise.
--
-- THE BAR DEGRADES UNEVENLY, AND THIS IS THE PART TO KEEP. Median sd of the PAIRED
-- difference, and what 1 percentage point is worth in it:
--
--   instrument   pooled sd   macro sd   1pt on pooled   1pt on macro
--   guitar         0.790       1.608        1.3 sd          0.6 sd
--   bass           0.433       1.679        2.3 sd          0.6 sd
--   drum           0.646       1.829        1.5 sd          0.5 sd
--   vocals         0.558       0.846        1.8 sd          1.2 sd
--   keys           0.663       0.808        1.5 sd          1.2 sd
--   real_keys      0.600       0.728        1.7 sd          1.4 sd
--
-- On the three instruments where the leaders disagree, a 1-point macro difference is
-- half a standard deviation - close to a coin flip. The POINT half of the rule stops
-- discriminating on macro; the WIN-SHARE half is scale-free and still does. Drums clears
-- on 90% of repeats, which is why its result survives despite +1.56 being only 1.1 sd.
-- Any move to macro must therefore re-derive the point bar, or drop it and lean on win
-- share - not carry 1.00 across unchanged.
--
-- AND PAIRING HELPS LESS THAN ASSUMED, in both metrics. An earlier note here predicted
-- paired differences would be substantially tighter than marginal spread, because shared
-- folds cancel. Measured, they are LARGER: guitar's marginal macro sd is 1.413 against a
-- paired 1.608, and pooled goes 0.683 -> 0.790 the same way. Two candidates on identical
-- folds correlate at only about r = 0.5 here, and paired sd is s*sqrt(2-2r), so anything
-- below r = 0.5 makes the paired difference noisier than either candidate alone. Do not
-- assume pairing rescues a noisy metric; it removes the fold's shared component and
-- nothing else.
-- ----------------------------------------------------------------------------
function MacroUsable(pred_tiers, act_tiers)
    local n_by, ok_by = {}, {}
    for i = 1, #act_tiers do
        local t = act_tiers[i]
        n_by[t]  = (n_by[t] or 0) + 1
        ok_by[t] = (ok_by[t] or 0) + ((math.abs(pred_tiers[i] - t) <= 1) and 1 or 0)
    end
    local sum, k = 0, 0
    for t, n in pairs(n_by) do
        if n > 0 then sum, k = sum + ok_by[t] / n, k + 1 end
    end
    return (k > 0) and (sum / k) or 0
end

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
-- 488, so usable% and miss% are untouched. MAE moves, and rho moves in the fifth
-- decimal. This is about not printing nonsense.
--
-- MEASURED 2026-08-22 rather than assumed, and the first half is more active than this
-- comment used to suggest: the clamp binds on 0.4%-2.3% of predictions depending on
-- instrument. Every one of those is WITHIN-TIER - the bounds are the extreme observed
-- ranks, so a prediction just outside them was already in that extreme tier - which is
-- why usable% and miss% really are untouched. See the 8e block below for the counts.
--
-- (An earlier version of this comment said rho was untouched "because Spearman is
-- order-preserving". That reasoning is wrong and the 2026-08-21 peer review caught it:
-- clamping is only NON-DECREASING, not strictly increasing. Every prediction above hi
-- collapses to hi, which creates TIES, and Spearman with ties is not the same
-- statistic. The review measured the effect on the six selected models at between
-- -0.000006 and +0.000025 - far too small to move a gate verdict, which is why the
-- conclusion survives even though the argument for it did not. That magnitude is the
-- review's measurement and has not been independently re-derived here; the protocol
-- computes rho on clamped predictions only.)
--
-- The bounds come from the observed ranks rather than a constant, because the honest
-- claim is only ever "within the range of labels the model has seen".
--
-- ---------------------------------------------------------------------------
-- FIXED 2026-08-22 - peer review finding 8e. Two separate defects, two switches.
--
-- 1. CLAMP BOUNDS LEAKED VALIDATION LABELS. They were taken over the whole target set -
--    RankRange(d, target) once at the top of RunProtocol - which includes the rows in the
--    fold about to be predicted. A validation song's own rank helped decide the range its
--    prediction was clamped into. Small, but it is label leakage into evaluation.
--    PROTOCOL.CLAMP_BOUNDS = 'per_fold' derives them from each fold's TRAINING rows only.
--
-- 2. RHO WAS GRADED ON CLAMPED PREDICTIONS. Clamping creates ties at the bounds, and
--    Spearman with ties is a different statistic. The product should clamp - printing rank
--    943 for a 1-501 scale is nonsense - but the evaluation should not.
--    PROTOCOL.RHO_ON = 'raw' grades rho on unclamped out-of-fold predictions, and this now
--    matters more than it did: rho's bootstrap lower bound became a GATE INPUT on
--    2026-08-22, so the statistic being graded had better be the one intended.
--
-- Kept as switches rather than edits so the old behaviour stays runnable and the cost of
-- each half is separately attributable - the same pattern as RIDGE_VALIDATION.
--
-- PRE-REGISTERED before either was implemented:
--
--   * Movement under 0.3 points pooled on every instrument, and no reselection.
--   * rho moves in the third decimal or smaller. The clamp-vs-raw half was measured by
--     the reviewer at -0.000006 to +0.000025 on the selected models; the per-fold half is
--     the one that could exceed that.
--   * THE MECHANISM THAT COULD SURPRISE, stated so the prediction is falsifiable rather
--     than vague: per-fold bounds come from 4/5 of the rows, so they are TIGHTER than the
--     full-target bounds, never wider. A tighter floor clamps low predictions UP, and the
--     bottom tiers are narrow, so a bottom-end prediction can cross a tier boundary it
--     previously did not. If anything moves more than predicted, expect it at the bottom
--     end and on the instruments whose corpora reach lowest.
--
-- As with finding 6, these are CORRECTNESS fixes and are adopted on that basis. The
-- measurement documents the cost; it does not decide the question.
--
-- WHAT IT MEASURED, 2026-08-22. Four arms (both switches, both settings, all six
-- instruments) came out IDENTICAL on pooled, macro, every selection and every ridge
-- histogram. So a direct count was run instead, because "no change in the headline" is
-- not the same claim as "the code does nothing" and only one of them was worth believing:
--
--   instrument  preds  bounds     binds, whole-corpus  binds, per-fold   rho clamped->raw
--   guitar       3270   75-605           28 (0.86%)         32 (+4)        +0.000007
--   bass         3300   89-480           33 (1.00%)         36 (+3)        -0.000015
--   drum         3280   93-550           21 (0.64%)         33 (+12)       -0.000000
--   vocals       3280  112-495           13 (0.40%)         14 (+1)        -0.000000
--   keys         2660   90-495           56 (2.11%)         56 (0)         -0.000012
--   real_keys    2660   80-505           62 (2.33%)         62 (0)         -0.000025
--
-- THE CLAMP DOES BIND - 0.4% to 2.3% of predictions, not the "never" this file used to
-- imply. And the pre-registered mechanism is CONFIRMED: per-fold bounds are tighter, so
-- they bind MORE OFTEN, on four of the six instruments (+1 to +12). Keys and Pro Keys are
-- unchanged, meaning their extreme labels sit in folds where removing them did not move
-- the range.
--
-- IN THE PER-REPEAT VIEW EVERY ONE OF THOSE CLAMPS IS WITHIN-TIER, which is why the gate's
-- numbers did not move at all. The bounds are the extreme observed ranks, so a prediction
-- just outside them was already in that extreme tier.
--
-- IN THE AVERAGED-PREDICTION VIEW ONE TIER DID MOVE, and the distinction is worth keeping
-- straight because the two views are graded differently. CandidateResiduals averages
-- across repeats, and it now clamps PER FOLD BEFORE averaging rather than once at the end
-- - so a prediction repeatedly clamped to a tighter ceiling averages lower. Three guitar
-- residuals shifted (dreampolice 480 -> 471, pulseofthemaggots 460 -> 450 and 480 -> 463)
-- and one of them crossed out of predicted tier 6 into tier 5. Per-tier usable is
-- unchanged, so pooled, macro and the endpoint band are unchanged too; what moved is
-- tier 5's signed bias (-0.67 -> -0.71) and the predicted-count column.
--
-- So the pre-registered tier-crossing mechanism DID materialise, in the one view where
-- averaging can carry a clamp across a boundary, and did not in the view the gate reads.
-- Predicted as a bottom-end effect; it appeared at the TOP end instead, where the ceiling
-- rather than the floor is the binding bound. Half right.
--
-- A few non-selected candidates' rho also moved in the third decimal (e.g.
-- full_drum@noroll@complex +0.892 -> +0.891) from the raw-vs-clamped half. No selected
-- model's rho moved at three decimals.
--
-- rho moves by -0.000045 to +0.000007, which independently reproduces the peer review's
-- -0.000006 to +0.000025 and widens it slightly (real_keys is the largest). Six orders of
-- magnitude below the gate's 0.70 floor.
--
-- SO: both defects were real, the fix changes 1-12 predictions per instrument, and it
-- costs nothing measurable. "No headline change" here is a measured result, not an
-- assumption - which is the whole reason the count was run.
-- ---------------------------------------------------------------------------
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

-- Feature vector plus one indicator per auxiliary origin, appended in AUX_ORIGINS
-- order. Takes the row's ORIGIN rather than a prepared flag: with more than one
-- indicator, a caller passing flags positionally is one append away from writing a
-- Lego 1 into the rb2 column, and nothing downstream would notice.
local function WithOrigin(fv, origin)
    local out = {}
    for j = 1, #fv do out[j] = fv[j] end
    for _, aux in ipairs(PROTOCOL.AUX_ORIGINS) do
        out[#out + 1] = (origin == aux.origin) and 1 or 0
    end
    return out
end

-- The indicator column names, in the order WithOrigin appends them. The exporter
-- appends these to a candidate's key list so the artifact records what each trailing
-- coefficient belongs to.
function AuxFlagKeys()
    local out = {}
    for _, aux in ipairs(PROTOCOL.AUX_ORIGINS) do out[#out + 1] = aux.flag end
    return out
end

-- Training weight for an always-training row, or nil when the origin is not auxiliary
-- (i.e. it is the target, or an origin excluded from every fit).
function AuxWeight(origin)
    for _, aux in ipairs(PROTOCOL.AUX_ORIGINS) do
        if aux.origin == origin then return aux.weight end
    end
    return nil
end

-- Row indices for every auxiliary origin, pooled. These always train and are never
-- predicted.
function AuxIndices(origins)
    local out = {}
    for i, o in ipairs(origins) do
        if AuxWeight(o) then out[#out + 1] = i end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- RIDGE VALIDATION - peer review finding 6, and its pre-registration
--
-- THE DEFECT. Auxiliary rows train at weight 0.30 (AUX_ORIGINS), because 60 Lego-era and
-- RB2 rows should inform the fit without steering it. But the nested ridge search below
-- used to accumulate `err + |e|` and `cnt + 1` over its inner holdouts, ignoring the `ws`
-- array sitting right beside it. So in the one decision that picks the regularisation
-- strength, an auxiliary row counted as much as an RB3 target row.
--
-- HOW BIG THE MISWEIGHTING IS. Inner training rows are roughly 264 target + 60 aux, so aux
-- carried about 18.5% of the vote on ridge instead of the ~6.4% the declared 0.30 policy
-- implies, or the 0% that matches how the model is actually graded. Keys and Pro Keys have
-- NO auxiliary rows at all - neither Lego Rock Band nor the RB2 export has a keyboard part
-- - so they are unaffected by construction, which makes them a free control.
--
-- THREE ARMS, and the switch is PROTOCOL.RIDGE_VALIDATION:
--   'unweighted'   the defect, kept runnable so the cost of the fix is measurable
--   'weighted'     inner rows count their training weight; the literal reading of "aux
--                  rows are worth 0.30"
--   'target_only'  aux rows train and are never scored; matches the OUTER grade, which
--                  is computed on target rows only with every origin indicator at zero
--
-- PRE-REGISTERED 2026-08-22, before any arm was run. Unlike the grouped-fold prediction,
-- nothing here had been measured when this was written.
--
--   * Keys and real_keys must be BYTE-IDENTICAL across all three arms. They have no aux
--     rows, so any movement there is a bug in the implementation, not a finding. This is
--     the hard falsifiable check.
--   * No instrument's selected CANDIDATE changes.
--   * Metric movement stays under one paired sd (so under about 0.8 points pooled).
--   * Weak directional guess: target_only >= weighted >= unweighted on the target
--     metrics, because tuning against the objective you are graded on should help. Held
--     weakly - the ridge grid is six coarse log-spaced values, so many folds will pick the
--     same value regardless.
--
-- THE DECISION RULE, AND IT IS NOT "WHICHEVER SCORES BEST". This is a CORRECTNESS fix, so
-- the arm is chosen on what it implements, not on what it measures. Choosing by score is
-- exactly the selection inflation this whole file exists to prevent, and with 6 grid
-- values on 4 instruments something would "win" by noise every time.
--
-- `target_only` is adopted because it matches the estimand: the outer CV grades target
-- rows only, so the inner search should minimise error on target rows only. `weighted` is
-- measured alongside because it is the reviewer's suggestion and the literal reading of
-- the 0.30 policy; if the two disagree by less than a paired sd, target_only still wins on
-- the argument above rather than on the number.
--
-- The A/B exists to DOCUMENT THE COST and to CATCH A RESELECTION, not to pick a winner.
--
-- WHAT IT MEASURED, 2026-08-22. Paired by repeat, against the unweighted defect:
--
--   instrument   weighted            target_only         candidate change
--                pooled   macro      pooled   macro
--   guitar       +0.00    +0.17      +0.06    +0.41      none
--   bass         +0.00    +0.00      +0.00    +0.00      none
--   drum         +0.00    +0.00      -0.12    -0.31      none
--   vocals       +0.09    +0.02      +0.00    -0.20      none
--   keys          identical           identical          none  (no aux rows)
--   real_keys     identical           identical          none  (no aux rows)
--
-- SCORING THE PRE-REGISTRATION, point by point:
--
--   * CONTROL HELD. keys and real_keys are identical across all three arms - not merely
--     to the reported decimals but in their whole ridge histograms. That is the check
--     that says this is measuring the aux rows and not an implementation slip.
--   * NO RESELECTION on any instrument, as predicted.
--   * MOVEMENT UNDER ONE PAIRED SD, as predicted, and with room to spare: the largest
--     move is 0.12 points pooled against paired sds of 0.43-0.79, and 0.41 macro against
--     0.73-1.83.
--   * THE DIRECTIONAL GUESS IS NOT SUPPORTED. Guitar moved the way it predicted, drum
--     moved against it, vocals split by metric, bass did not move at all. Two of the four
--     instruments with aux rows went each way and every magnitude sits inside noise, so
--     the direction is unresolvable at this corpus size rather than refuted. Recorded as
--     unsupported; the guess was held weakly and should have been.
--
-- THE SUBSTANTIVE RESULT IS IN THE RIDGE HISTOGRAM, NOT THE ACCURACY. The chosen ridge
-- moves a lot. Guitar under the defect picked 0.1 on 35 of 50 fold-repeats; under
-- target_only that falls to 24, with weight shifting to weaker values. Vocals goes the
-- other way, 32 -> 44 at 0.1. Drum starts picking 1.0. So the auxiliary rows genuinely
-- WERE steering regularisation strength, exactly as the review said - and the model turns
-- out to be insensitive to ridge across that range, which is why the accuracy barely
-- moves. "No measurable cost" is the finding; "no effect" would be the wrong reading.
--
-- IT DID CHANGE THE SHIPPED ARTIFACT. VOCALS' production ridge moved 0.01 -> 0.1 and its
-- 14 coefficients with it. No gate verdict changed on any instrument (vocals fails either
-- way), and guitar's usable lower bound moved 91.64 -> 91.71 while drum's moved
-- 94.37 -> 94.22 - both still passing.
-- ---------------------------------------------------------------------------

-- Weight each inner-holdout row carries when scoring a ridge value, under the mode in
-- force. Returns 0 for a row that must not be scored at all.
--
-- GLOBAL ON PURPOSE. export_production_models.lua runs the same nested search to pick the
-- production ridge, and finding 6 is precisely that the two searches implemented different
-- policies. One function, called from both, is what makes them unable to drift again.
--
--   is_aux   true when the row comes from an auxiliary origin.
--   w        the row's training weight.
function InnerScoreWeight(is_aux, w)
    local mode = PROTOCOL.RIDGE_VALIDATION
    if mode == 'target_only' then
        return is_aux and 0 or 1
    elseif mode == 'weighted' then
        return w or 1
    end
    return 1                                  -- 'unweighted', the pre-2026-08-22 behaviour
end

-- Nested ridge search. Splits the TRAINING rows again, scores each ridge value on the
-- inner holdouts, and returns the best. The training rows here never include the outer
-- fold being predicted, so nothing the model is graded on informs its ridge.
--
--   aux    parallel array of booleans, true where X[i] came from an auxiliary origin.
--         Passed explicitly rather than inferred from ws, because inferring "weight 0.30
--         means auxiliary" would silently break the day an aux origin is given weight 1.
local function ChooseRidge(X, ys, ws, aux)
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
                    -- Training weight and SCORING weight are separate: an aux row can
                    -- still train the inner fit (tw above) while contributing nothing to
                    -- the error that picks the ridge.
                    local sw = InnerScoreWeight(aux and aux[i], ws[i])
                    if sw > 0 then
                        err = err + sw * math.abs(ApplyFit(X[i], fit) - ys[i])
                        cnt = cnt + sw
                    end
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
    -- Per-prediction clamp bounds, filled in fold by fold below. See finding 8e.
    local clo, chi = {}, {}

    for f = 1, #folds do
        -- `aux` marks which rows came from an auxiliary origin, so the nested ridge
        -- search can score them differently from how it trains on them. See the RIDGE
        -- VALIDATION block above ChooseRidge.
        local X, ys, ws, aux = {}, {}, {}, {}
        for g = 1, #folds do
            if g ~= f then
                for _, ti in ipairs(folds[g]) do
                    local i = target[ti]
                    X[#X + 1]   = WithOrigin(feats[i], d.origins[i])
                    ys[#ys + 1] = scale.fwd(d.ranks[i])
                    ws[#ws + 1] = 1.0
                    aux[#aux + 1] = false
                end
            end
        end
        for _, i in ipairs(extra) do
            X[#X + 1]   = WithOrigin(feats[i], d.origins[i])
            ys[#ys + 1] = scale.fwd(d.ranks[i])
            ws[#ws + 1] = AuxWeight(d.origins[i]) or PROTOCOL.LEGO_WEIGHT
            aux[#aux + 1] = true
        end

        local ridge = ChooseRidge(X, ys, ws, aux)
        ridges[#ridges + 1] = ridge
        local fit = MultiFit(X, ys, ridge, ws)
        if not fit then return nil end

        -- Clamp bounds for THIS fold, from its training target rows only. Computed here
        -- because this is the only place the training/validation split is known - finding
        -- 8e is precisely that they used to be computed once, outside the loop, over rows
        -- that included the fold about to be predicted.
        local flo, fhi
        if PROTOCOL.CLAMP_BOUNDS == 'per_fold' then
            local train = {}
            for g = 1, #folds do
                if g ~= f then
                    for _, ti in ipairs(folds[g]) do train[#train + 1] = target[ti] end
                end
            end
            flo, fhi = RankRange(d, train)
        else
            flo, fhi = RankRange(d, target)     -- 'all_target', the leaky behaviour
        end

        for _, ti in ipairs(folds[f]) do
            local i = target[ti]
            local n = #pred + 1
            -- Mapped back through inv, so both scales are graded on the rank scale.
            -- Predicted with every origin indicator at 0, i.e. on the RB3 scale, which
            -- is the scale a custom chart should be rated on. nil is not an auxiliary
            -- origin, so WithOrigin writes zeros for all of them.
            pred[n] = scale.inv(ApplyFit(WithOrigin(feats[i], nil), fit))
            act[n]  = d.ranks[i]
            clo[n], chi[n] = flo, fhi
        end
    end
    -- pred is RAW. clo/chi are parallel and say what each prediction would clamp to, so a
    -- caller can grade on raw and display clamped without recomputing anything.
    return pred, act, ridges, clo, chi
end

-- Clamped copy of a raw prediction array, using the per-prediction bounds RunOneRepeat
-- returned. Kept as one function so every caller clamps identically.
function ClampPredictions(pred, clo, chi)
    local out = {}
    for i = 1, #pred do
        out[i] = ClampRank(pred[i], clo and clo[i] or -math.huge,
                                    chi and chi[i] or math.huge)
    end
    return out
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

    -- Clamp bounds are derived per fold inside RunOneRepeat as of 2026-08-22 (finding
    -- 8e), from that fold's training rows only. They come from the TARGET rows and not
    -- the down-weighted other-origin rows: every prediction is made with is_lego = 0,
    -- i.e. on the RB3 scale, so a Lego rank is not a label a prediction could take.

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
                          macro = {},
                          ridges = {}, ok = ok, per_row = nil,
                          keys = cand.keys, scale_obj = scale }
            if ok then
                for rep = 1, PROTOCOL.N_REPEATS do
                    local pred, act, ridges, clo, chi = RunOneRepeat(
                        d, target, extra, folds_by_repeat[rep],
                        cand.keys, factor_pos, scale)
                    if pred then
                        -- TIERS come from the clamped predictions, because a tier is what
                        -- the product shows and the product clamps. RHO comes from the
                        -- raw ones under RHO_ON = 'raw', because clamping ties the
                        -- extremes and Spearman with ties is a different statistic.
                        local shown = ClampPredictions(pred, clo, chi)
                        local pt, at = {}, {}
                        for i = 1, #shown do
                            pt[i] = TierForRank(inst, shown[i])
                            at[i] = TierForRank(inst, act[i])
                        end
                        local dist = TierDistance(pt, at)
                        rec.usable[#rec.usable + 1] = dist.usable / dist.n
                        rec.miss[#rec.miss + 1]     = dist.miss / dist.n
                        rec.rho[#rec.rho + 1]       =
                            Spearman((PROTOCOL.RHO_ON == 'raw') and pred or shown, act) or 0
                        rec.macro[#rec.macro + 1]   = MacroUsable(pt, at)
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
                -- The same for rho, and it is reported for a specific reason: the gate
                -- reads rho's MEAN while reading the pessimistic end of everything else,
                -- and the report used to describe itself as reading lower bounds
                -- throughout. The 2026-08-21 peer review caught that. Showing the spread
                -- makes the asymmetry visible instead of hidden behind one number.
                --
                -- This is a SPLIT range, not a confidence interval, and the difference
                -- matters more here than for usable%. usable% has an honest binomial
                -- interval on the row count (Wilson, below); rho has no such closed form,
                -- and these ten repeats are correlated reruns over the same songs, so
                -- their spread understates real uncertainty. A defensible lower bound for
                -- rho needs the pack bootstrap - phase 4 - and until that exists rho is
                -- gated on the mean and the report says so plainly.
                rec.rho_lo_split    = Quantile(rec.rho, 0.10)
                rec.rho_hi_split    = Quantile(rec.rho, 0.90)
                -- Measured for EVERY candidate, not just the selected one, so the
                -- question "would a different model win under macro?" has an answer
                -- before the gate is moved rather than after. Reported, never selected
                -- on - SelectCandidate still reads usable_mean. See MacroUsable.
                rec.macro_mean      = MeanOf(rec.macro)
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
-- GROUPED FOLDS - how much of the score is pack leakage?
----------------------------------------------------------------------

-- THE PROBLEM. Every figure this protocol publishes was measured with folds that deal
-- individual SONGS. DLC ships in packs, and songs in a pack share an authoring team, an
-- era, and often a deliberate difficulty spread. Dealing rows therefore lets the model
-- train on a near-sibling of the row it is graded on, and the corpus grows one pack at a
-- time, so a pack - not a song - is the honest unit of "data we did not have".
--
-- HOW EXPOSED THE CURRENT SCHEME IS, measured rather than assumed. Under row-level
-- folds, about 60% of validation rows share a pack with at least one training row
-- (guitar 59.3%, bass 59.4%, drum 61.0%, keys 59.8%, vocals 60.7%). That is much higher
-- than the pack SIZES suggest - the largest rb3 pack is 15 rows out of ~330, under 5% -
-- because the corpus is 170 packs over 330 rows: half the packs are singletons and
-- contribute no exposure at all, while the rows concentrate in the multi-song packs.
--
-- WHAT IS PRE-REGISTERED. Written before the probe below was first run, so it cannot be
-- rewritten into a prediction that came true:
--
--   Grouped folds are expected to score LOWER, by roughly 0.5 to 2 points pooled, on
--   every instrument. Direction is asserted with more confidence than size. The reason
--   for expecting the effect to be small despite 60% exposure is that the factors are
--   chart geometry, not authorship fingerprints, and packs routinely mix an easy song
--   with a hard one - so a pack sibling is a weak label hint. A drop beyond about 3
--   points would mean the opposite, and would make the grouped number the honest one to
--   publish rather than a diagnostic.
--
-- The last previous prediction recorded in this file (that pairing would tighten the
-- macro spread) was WRONG, which is exactly why this one is written down first.
--
-- WHAT IT MEASURED, 2026-08-22, selected model per instrument, matched seeds, 10 repeats
-- (grouped minus row-level; sd is of the paired per-repeat difference):
--
-- (Refreshed 2026-08-22 after the ridge-validation fix; conclusion unchanged, and the rho
-- sign pattern still holds six of six despite the underlying models having moved.)
--
--   instrument   pooled          macro           rho       leak% under row folds
--   guitar       -0.21 (sd 0.85) -0.14 (sd 1.67) -0.003        61.0
--   bass         +0.00 (sd 0.29) -1.21 (sd 2.19) -0.004        60.5
--   drum         -0.09 (sd 0.52) +0.19 (sd 1.31) -0.004        59.8
--   vocals       +0.03 (sd 0.70) +0.27 (sd 1.21) -0.009        61.1
--   keys         -0.53 (sd 0.73) -0.40 (sd 0.70) -0.004        59.7
--   real_keys    +0.19 (sd 0.44) +0.06 (sd 0.75) -0.004        59.6
--
-- SCORING THE PREDICTION (against the figures as first measured, before the ridge fix
-- refreshed them: guitar -0.31, bass +0.00, drum -0.24, vocals -0.03, keys -0.53,
-- real_keys +0.19 on pooled). Direction: right on rho, where all six instruments moved
-- down, and only 4 of 6 on pooled. Size: WRONG, and wrong in the pessimistic direction -
-- the predicted 0.5-2 point pooled drop did not appear on any instrument. Every pooled and
-- macro delta is smaller than the spread of the difference that produced it, so on those
-- two metrics grouping is not distinguishable from noise on this corpus.
--
-- Rho is the one place the leakage is visible. All six instruments moved down, by
-- 0.004-0.008, and six of six in the same direction is not something a coin flip
-- produces often (about 1 chance in 32 under a sign test). So pack leakage is REAL and
-- its effect is about five thousandths of rho - detectable in the sign, negligible in
-- the size.
--
-- WHY SO SMALL, given 60% exposure. Because a pack sibling is a weak hint, as predicted:
-- the corpus is 170 packs over 330 rows, the largest holds 15, and packs routinely mix
-- an easy song with a hard one, so knowing a neighbour's rank barely narrows the target.
-- The 60% figure counts rows with ANY sibling in training, which is the exposure, not
-- the advantage taken from it.
--
-- CONSEQUENCE FOR THE GATE: none. No instrument's verdict changes under grouping -
-- guitar, bass and drums still pass, vocals and both keyboard parts still fail, at
-- effectively the same margins. That is the finding, and it is the reason the flag stays
-- false rather than a reason grouping was rejected: if the deltas had been 3 points the
-- grouped number would be the honest one to publish.
--
-- WHAT THIS DOES NOT DO. It does not move the gate. PROTOCOL.GROUP_FOLDS stays false and
-- SelectCandidate is untouched, for the same reason macro is measured but not selected
-- on: switching the scheme changes every published number at once, and README rule 1
-- says a changed evaluation scheme is a DECLARED NEW EXPERIMENT, not a flag flip. The
-- probe puts the size of the effect on the table so that decision can be made on
-- evidence. If the gate does move, the artifact's figures must be regenerated together.

-- Rows in a validation fold that share a group with some training row, as a fraction of
-- all rows. Zero by construction under grouped folds; the point is to report the number
-- for the ROW-LEVEL scheme, where it is the size of the problem.
function PackLeakageRate(folds, groups)
    local n, leaked = 0, 0
    for f = 1, #folds do
        local in_train = {}
        for g = 1, #folds do
            if g ~= f then
                for _, ti in ipairs(folds[g]) do in_train[groups[ti]] = true end
            end
        end
        for _, ti in ipairs(folds[f]) do
            n = n + 1
            if in_train[groups[ti]] then leaked = leaked + 1 end
        end
    end
    if n == 0 then return 0 end
    return leaked / n
end

-- Run ONE candidate under both fold schemes on matched seeds and difference the result.
--
-- Paired by repeat index, so repeat 3's grouped run and repeat 3's row-level run share
-- a seed. That does NOT make them the same split - grouping changes the assignment by
-- construction - so this pairing removes less noise than the candidate-vs-candidate
-- pairing above. It is still worth doing: the two schemes see the same rows in the same
-- order, and the alternative is comparing two independent 10-repeat means.
--
--   groups   parallel array over target, holding each target row's pack key.
--
-- Returns a record with both schemes' means and the grouped-minus-row differences, or
-- nil when the candidate cannot be fitted.
function GroupedFoldProbe(d, target, extra, inst, factor_pos, keys, scale, groups)
    local strata = {}
    for n, ti in ipairs(target) do
        strata[n] = tostring(TierForRank(inst, d.ranks[ti]))
    end
    local out = {
        row     = { usable = {}, macro = {}, rho = {} },
        grouped = { usable = {}, macro = {}, rho = {} },
        leak_row = 0, diag = nil,
    }

    -- Same clamp and rho policy as RunProtocol, so the two schemes are compared on the
    -- quantities the gate actually reads rather than on a variant of them.
    local function Score(folds)
        local pred, act, _, clo, chi =
            RunOneRepeat(d, target, extra, folds, keys, factor_pos, scale)
        if not pred then return nil end
        local shown = ClampPredictions(pred, clo, chi)
        local pt, at = {}, {}
        for i = 1, #shown do
            pt[i] = TierForRank(inst, shown[i])
            at[i] = TierForRank(inst, act[i])
        end
        local dist = TierDistance(pt, at)
        local rho = Spearman((PROTOCOL.RHO_ON == 'raw') and pred or shown, act) or 0
        return dist.usable / dist.n, MacroUsable(pt, at), rho, dist.n
    end

    local leak_sum, leak_n = 0, 0
    for rep = 1, PROTOCOL.N_REPEATS do
        local seed = PROTOCOL.SEED + rep
        local rfolds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, seed)
        local gfolds, diag = StratifiedGroupFolds(strata, groups, PROTOCOL.NFOLD, seed)
        out.diag = out.diag or diag
        leak_sum = leak_sum + PackLeakageRate(rfolds, groups)
        leak_n   = leak_n + 1

        local u, m, rh, nrows = Score(rfolds)
        if u then
            out.row.usable[#out.row.usable + 1] = u
            out.row.macro[#out.row.macro + 1]   = m
            out.row.rho[#out.row.rho + 1]       = rh
            out.n_rows = nrows
        end
        u, m, rh = Score(gfolds)
        if u then
            out.grouped.usable[#out.grouped.usable + 1] = u
            out.grouped.macro[#out.grouped.macro + 1]   = m
            out.grouped.rho[#out.grouped.rho + 1]       = rh
        end
    end
    if #out.row.usable == 0 or #out.grouped.usable == 0 then return nil end
    out.leak_row = leak_sum / math.max(1, leak_n)

    for _, key in ipairs({ 'usable', 'macro', 'rho' }) do
        out[key .. '_row']     = MeanOf(out.row[key])
        out[key .. '_grouped'] = MeanOf(out.grouped[key])
        -- Paired difference and the spread of that difference, so a delta can be read
        -- against how much it moves rather than against zero.
        local n, sum, diffs = math.min(#out.row[key], #out.grouped[key]), 0, {}
        for i = 1, n do
            local dd = out.grouped[key][i] - out.row[key][i]
            diffs[#diffs + 1] = dd
            sum = sum + dd
        end
        out[key .. '_delta']    = (n > 0) and (sum / n) or 0
        out[key .. '_delta_sd'] = SampleSd(diffs)
    end
    return out
end

----------------------------------------------------------------------
-- THE PACK BOOTSTRAP - an interval for the quantities Wilson cannot reach
----------------------------------------------------------------------

-- WHY THIS EXISTS. The gate reads a Wilson lower bound, which is a binomial interval on
-- a proportion over n rows. Two things are wrong with that here, and the bootstrap fixes
-- both:
--
--   1. MACRO HAS NO CLOSED-FORM INTERVAL. It is the mean of up to seven proportions with
--      denominators from 2 to 102. `macro_lower >= X` simply does not exist analytically,
--      so the pre-registered move of the gate to macro has been blocked on this function
--      rather than on a decision. Same for rho, which the gate currently reads as a MEAN
--      while reading the pessimistic end of everything else - an asymmetry the report has
--      had to admit to in words.
--   2. WILSON ASSUMES INDEPENDENT ROWS, and these rows are clustered in packs. Songs from
--      one pack share an author and an era, so the corpus carries less information than
--      its row count suggests and Wilson is optimistic by an unknown amount. Resampling
--      PACKS instead of rows measures that amount instead of assuming it away.
--
-- WHAT IS RESAMPLED, AND WHAT THAT BUYS. Packs are drawn WITH REPLACEMENT from the
-- observed packs, and each drawn pack contributes all of its rows. So a bootstrap sample
-- has a variable row count, which is correct: it is the honest reflection of having
-- sampled a different set of packs.
--
-- WHAT IT DOES NOT CAPTURE, stated plainly because the interval will be quoted. The
-- predictions are held FIXED at the out-of-fold values the real run produced. This is an
-- interval for "what would this measured accuracy be on a different sample of packs",
-- which is exactly the question a release floor asks. It is NOT an interval for "what if
-- the model had been refitted and reselected on different data" - that needs the fitting
-- inside the bootstrap loop, at roughly 2000x the current four-minute runtime, and is not
-- affordable. The CV repeats already absorb part of the refit variability, so the two
-- together are not as far apart as the omission sounds, but the gap is real and this
-- interval must never be described as covering it.
--
-- WHICH FIGURES IT BOUNDS. The residual rows, i.e. predictions averaged over repeats and
-- then tiered - the same rows TierDiagnostics reads. Those pooled figures differ from the
-- per-repeat mean the gate quotes by a few tenths of a point (tier-then-average is not
-- average-then-tier). The report prints both and names which is which; do not mix them.
--
-- MACRO'S EMPTY-TIER PROBLEM, which is a real limitation and not a rounding detail. A
-- resample can miss a sparse tier entirely - bass tier 6 is 4 songs in 3 packs, so about
-- 3% of resamples contain none of it. MacroUsable averages over OCCUPIED tiers, so those
-- resamples compute a mean over six tiers rather than seven. That is a slightly different
-- estimand, and mixing the two inflates the spread. The rate is measured and reported
-- (`macro_short_frac`) rather than hidden; when it is more than a few per cent the macro
-- interval is wider than the sampling of packs alone justifies.
--
-- ---------------------------------------------------------------------------
-- WHAT IT MEASURED, 2026-08-22. B = 2000, selected model per instrument.
--
--   instrument   pooled  design   endpoint  design  eff n    rho    rho p05
--   guitar       95.11    1.05      88.50    1.00   112/113  0.865   0.830
--   bass         94.24    0.95      92.86    1.01   138/140  0.802   0.746
--   drum         96.34    1.00      90.00    1.01    88/90   0.895   0.869
--   vocals       89.02    1.22      64.00    1.16    56/75   0.676   0.606
--   keys         93.23    1.18      87.60    1.13   101/129  0.877   0.837
--   real_keys    89.47    1.11      82.58    1.12   106/132  0.862   0.824
--
-- CORRECTED 2026-08-22, and the correction matters more than the original claim did. An
-- earlier version of this table gave endpoint design effects of 1.55-2.42 and concluded
-- Wilson was badly optimistic on that band. THAT WAS A BUG IN THIS FILE, not a
-- measurement: the endpoint design effect was computed against the WHOLE corpus row count
-- instead of the endpoint band's own 75-140 rows, which shrinks the binomial reference by
-- sqrt(n/ep_n) - about 1.6x - and inflates the ratio by the same factor. The effective-n
-- column was always right (it reduces to p(1-p)/sd^2 and does not depend on the
-- denominator); the design ratio and everything concluded from it were not.
--
-- TWO RESULTS, once the arithmetic is right.
--
-- 1. WILSON IS FINE ON POOLED. Design effect 0.95-1.22, so clustering costs the pooled
--    proportion almost nothing and the gate's existing lower bound is defensible as it
--    stands. (A design effect slightly below 1, as on bass, is resampling noise; it
--    cannot really be below 1.) This was worth checking rather than assuming - the
--    reason the pooled figure survives clustering is that packs mix easy and hard songs,
--    so a pack is not much more correlated internally than the corpus is overall.
--
-- 2. WILSON IS FINE ON THE ENDPOINT BAND TOO, design 1.00-1.16. So the phase-3
--    recommendation - that the endpoint band makes a good gate input partly BECAUSE it is
--    a real proportion over 75-140 rows where Wilson works - STANDS. It was briefly
--    recorded here as overturned; that retraction was the bug's doing and is itself
--    retracted.
--
--    The gate still reads the BOOTSTRAP p05 for this band, and that choice is unaffected:
--    with a design effect at 1.0 the two bounds nearly agree, and the bootstrap is the
--    assumption-free one. It is no longer NECESSARY, only preferable.
--
--    Worth keeping from the wrong version, because it is still true and still the reason
--    to keep checking: the corpus was enriched three times by deliberately adding low-end
--    and top-end songs, and those songs arrived IN PACKS. The endpoint band is where
--    clustering would do the most damage if it were doing any. It measurably is not.
--
-- 3. RHO NOW HAS A LOWER BOUND, AND IT COSTS NOTHING TO ADOPT. The gate reads rho as a
--    MEAN while reading the pessimistic end of everything else - an asymmetry the peer
--    review caught and the report has had to admit to in words. The bootstrap p05 is a
--    real one-sided 95% bound, and against the 0.70 floor: guitar 0.830, bass 0.746,
--    drum 0.870 all still clear it. So the asymmetry can be repaired without changing a
--    single verdict. That is a decision to declare, not to slip in - see rule 1 - but it
--    is the cheapest honest improvement now available to the gate.
--
-- AND ONE CAUTION ABOUT MACRO, which this was built to unblock. A macro floor is now
-- computable, but bass's interval is not clean: sd 4.37 and a p05 of 79.19, driven by the
-- 4.7% of resamples that lose a tier (vocals 13.7%). That is macro's weighting pathology
-- showing up quantitatively - bass's 4-song tier 6 carries the same weight as its 89-song
-- tier 1, so whether those 4 songs are drawn moves the headline by several points. The
-- bootstrap does not fix that; it measures it. Any macro floor has to be set knowing the
-- interval on one instrument is dominated by whether three packs got drawn.
-- ---------------------------------------------------------------------------
PROTOCOL.BOOTSTRAP = {
    -- 2000 resamples: the 5th percentile is stable to well under a tenth of a point at
    -- this size, and the whole loop costs a couple of seconds because nothing is refitted.
    B    = 2000,
    -- Offset from PROTOCOL.SEED so the bootstrap draw cannot accidentally reuse a fold
    -- shuffle's stream, and so it is reproducible on its own terms.
    SEED = 909,
}

-- One metric set over a list of residual rows. Kept separate so the bootstrap loop and
-- the point estimate go through identical code - an interval whose centre is computed a
-- different way from its endpoints is a bug waiting to be argued about.
local function MetricsOf(rows)
    if #rows == 0 then return nil end
    local pt, at, pred, act = {}, {}, {}, {}
    local ok, n = 0, 0
    local ep_ok, ep_n = 0, 0
    for _, x in ipairs(rows) do
        n = n + 1
        pt[n], at[n] = x.tier_pred, x.tier_act
        -- rho on the RAW prediction under RHO_ON = 'raw' (finding 8e): clamping ties the
        -- extremes, and this bootstrap's rho p05 is a gate input.
        pred[n] = ((PROTOCOL.RHO_ON == 'raw') and x.pred_raw) or x.pred
        act[n]  = x.rank
        local hit = (math.abs(x.tier_pred - x.tier_act) <= 1) and 1 or 0
        ok = ok + hit
        if x.tier_act <= 1 or x.tier_act >= 5 then
            ep_n, ep_ok = ep_n + 1, ep_ok + hit
        end
    end
    -- Occupied tiers, so the caller can tell a six-tier macro from a seven-tier one.
    local occ = {}
    for i = 1, n do occ[at[i]] = true end
    local k = 0
    for _ in pairs(occ) do k = k + 1 end
    return {
        pooled   = ok / n,
        macro    = MacroUsable(pt, at),
        endpoint = (ep_n > 0) and (ep_ok / ep_n) or nil,
        rho      = Spearman(pred, act) or 0,
        n        = n,
        ep_n     = ep_n,          -- rows in the endpoint band; the gate's report names it
        n_tiers  = k,
    }
end

-- Percentile bootstrap over packs.
--
-- Percentile rather than BCa: BCa needs a jackknife over packs plus a bias-correction
-- term, and with 140-172 packs the acceleration estimate is itself noisy. The percentile
-- interval is what the literature calls adequate for a smooth statistic at this B, and
-- being able to say exactly what the number is beats a sharper number nobody can check.
--
--   resid   residual rows from CandidateResiduals (need pack, tier_pred, tier_act,
--           pred, rank).
--
-- Returns nil when there is nothing to resample, else a record carrying, per metric, the
-- point estimate, the bootstrap mean, sd, and the one-sided lower bound at PROTOCOL.Z's
-- confidence (5th percentile for the 95% the gate uses), plus a two-sided 90% band.
function PackBootstrap(resid)
    if not resid or #resid == 0 then return nil end

    -- Group rows by pack. A row with no pack becomes its own group, never a shared
    -- unlabelled bucket - same rule as StratifiedGroupFolds, for the same reason.
    local by, keys = {}, {}
    for idx, x in ipairs(resid) do
        local p = x.pack
        if p == nil or p == '' then p = '\0row' .. idx end
        p = tostring(p)
        if not by[p] then by[p] = {}; keys[#keys + 1] = p end
        table.insert(by[p], x)
    end
    table.sort(keys)                      -- seed alone decides the draw, not table order

    local point = MetricsOf(resid)
    if not point then return nil end

    local np = #keys
    math.randomseed(PROTOCOL.SEED + PROTOCOL.BOOTSTRAP.SEED)

    local draws = { pooled = {}, macro = {}, endpoint = {}, rho = {} }
    local short = 0                       -- resamples missing at least one occupied tier
    local sum_n = 0
    for _ = 1, PROTOCOL.BOOTSTRAP.B do
        local rows = {}
        for _ = 1, np do
            local g = by[keys[math.random(np)]]
            for _, x in ipairs(g) do rows[#rows + 1] = x end
        end
        local m = MetricsOf(rows)
        if m then
            sum_n = sum_n + m.n
            if m.n_tiers < point.n_tiers then short = short + 1 end
            draws.pooled[#draws.pooled + 1] = m.pooled
            draws.macro[#draws.macro + 1]   = m.macro
            draws.rho[#draws.rho + 1]       = m.rho
            if m.endpoint then draws.endpoint[#draws.endpoint + 1] = m.endpoint end
        end
    end

    -- Per-metric records live under `stat` rather than beside the scalars, so a caller
    -- reading out.pooled.lo cannot collide with out.n and so the two kinds of field stay
    -- visibly different.
    local out = {
        n = point.n, n_packs = np, n_tiers = point.n_tiers, ep_n = point.ep_n,
        B = PROTOCOL.BOOTSTRAP.B,
        macro_short_frac = short / PROTOCOL.BOOTSTRAP.B,
        mean_rows = sum_n / PROTOCOL.BOOTSTRAP.B,
        stat = {},
    }
    for _, key in ipairs({ 'pooled', 'macro', 'endpoint', 'rho' }) do
        local t = draws[key]
        if #t > 0 then
            out.stat[key] = {
                point = point[key],
                mean  = MeanOf(t),
                sd    = SampleSd(t),
                lo    = Quantile(t, 0.05),    -- one-sided 95%, what a floor reads
                p05   = Quantile(t, 0.05),
                p95   = Quantile(t, 0.95),
            }
        end
    end

    -- THE DESIGN EFFECT. Binomial sd is sqrt(p(1-p)/n) - what Wilson assumes. Ratio above
    -- 1 means clustering costs effective sample size and Wilson is OPTIMISTIC by that
    -- factor; at or below 1 means the pack structure is not costing anything and a
    -- binomial bound stands. Reported for pooled and the endpoint band, the two genuine
    -- proportions.
    --
    -- EACH METRIC USES ITS OWN DENOMINATOR, and getting this wrong is not a rounding
    -- detail. The endpoint rate is a proportion over the ENDPOINT ROWS (ep_n, 75-140 of
    -- them), not over the whole corpus. Dividing by the full row count instead shrinks the
    -- binomial reference by sqrt(n/ep_n) - roughly 1.6x here - and inflates the design
    -- effect by the same factor. A first version of this code did exactly that and
    -- reported endpoint design effects of 1.55-2.42, which were an artefact of the wrong
    -- denominator rather than a measurement of clustering.
    local denom = { pooled = out.n, endpoint = out.ep_n or out.n }
    for _, key in ipairs({ 'pooled', 'endpoint' }) do
        local rec = out.stat[key]
        local nk  = denom[key]
        if rec and rec.point and nk and nk > 0 then
            local p = rec.point
            local binom = math.sqrt(math.max(0, p * (1 - p)) / nk)
            rec.binom_sd = binom
            rec.ref_n    = nk
            rec.design   = (binom > 1e-12) and (rec.sd / binom) or nil
            -- Effective n: the row count an INDEPENDENT sample would need to carry the
            -- same information. n / design^2 is the standard reading.
            rec.n_eff    = rec.design and (nk / (rec.design * rec.design)) or nil
        end
    end
    return out
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

-- Gate verdict on the SELECTED candidate. Returns passed, an array of reason strings.
--
-- WHAT THIS CHECKS, AND WHAT IT DELIBERATELY DOES NOT.
--
-- Three things: the pooled usable rate against its Wilson LOWER bound, the pooled miss
-- rate against its UPPER bound, and rho against its BOOTSTRAP LOWER BOUND. All three are
-- now read from the pessimistic end.
--
-- RHO USED TO BE READ AS A MEAN, and that was the honest option at the time: ten
-- correlated reruns over the same songs have no interval, and inventing one would have
-- been worse than admitting the asymmetry. The 2026-08-21 peer review flagged it, the
-- report printed rho's split range labelled as spread rather than uncertainty, and it
-- stayed a mean until an actual interval existed.
--
-- CHANGED 2026-08-22, once PackBootstrap produced one. The pack bootstrap's 5th percentile
-- is a genuine one-sided 95% lower bound on rho, from resampling the unit the corpus
-- actually grows in. So the gate now reads it, and the last asymmetry in this function is
-- gone.
--
-- THE NUMBERS WERE VISIBLE WHEN THIS WAS DECIDED, and that has to be recorded rather than
-- presented as a blind pre-registration. The bootstrap was built and reported first, so
-- guitar 0.830, bass 0.746 and drum 0.870 against the 0.70 floor were all on the table
-- before the switch was made. What makes it defensible anyway is the DIRECTION: this
-- replaces a point estimate with a strictly lower number, so it can only ever make the
-- gate harder to pass. There is no version of this change that flatters the model, which
-- is the same test the README applies to raising RESERVED_PCT after seeing the batch.
-- Moving rho the other way - from a bound to a mean - would be the forbidden direction.
--
-- IT CHANGES NO VERDICT TODAY. All three passing instruments clear the floor on the bound
-- as they did on the mean, and vocals fails on rho either way (mean 0.676, bound 0.606).
-- The value is that the next corpus cannot quietly pass on a lucky point estimate.
--
-- FALLBACK. When no bootstrap is available the mean is used and the reason string says so,
-- rather than failing the instrument for a missing diagnostic.
--
-- THE IMPLEMENTATION PLAN'S RELEASE GATE IS WIDER THAN THIS, and the 2026-08-21 peer
-- review was right to flag the gap. That gate also requires per-tier accuracy, a
-- macro-average, signed tier bias, no severe per-tier failure, and no systematic
-- over/under-rating. None of those can currently fail a verdict here.
--
-- That gap is now a DECLARED DIVERGENCE rather than an unmet requirement, decided
-- 2026-08-21. All five quantities are measured and printed for every instrument - see
-- TierDiagnostics - and none of them gates. The reasoning:
--
--   * The per-tier figures were never measured before. Promoting an unmeasured quantity
--     straight to a gate input sets a threshold with no idea what passes, which is how
--     you get a floor that either fails everything or nothing.
--   * On the current corpus, macro would flip bass from passing to failing and keys from
--     failing to passing. A gate change that reorders verdicts on its first run needs to
--     be a declared experiment with a pre-registered threshold, not a repair bundled into
--     a reporting change - see README rule 1.
--   * The 90% floor was calibrated against the pooled quantity. Carrying it over to macro
--     unchanged would be applying a threshold to a number it was never derived for.
--
-- ---------------------------------------------------------------------------
-- THE ENDPOINT FLOOR, added 2026-08-22 - where 0.80 came from, and what is
-- uncomfortable about it
--
-- The gate now has a FOURTH input: the endpoint band (tiers 0-1 and 5-6 pooled) against
-- its pack-bootstrap p05. This is the first gate input that can fail an instrument for
-- being uneven rather than inaccurate, and it closes most of the divergence below.
--
-- ON WILSON VS THE BOOTSTRAP HERE. An earlier draft of this block said the endpoint band
-- had to use the bootstrap because Wilson was optimistic on it by 1.55-2.42x. That figure
-- was a bug in PackBootstrap's design-effect arithmetic (wrong denominator) and the true
-- value is 1.00-1.16. The bootstrap is still what the gate reads, because it assumes
-- nothing about independence and the two bounds agree anyway - but the justification is
-- preference, not necessity, and the block above records the retraction.
--
-- WHY THE ENDPOINT BAND AND NOT MACRO. Macro was the pre-registered successor, and the
-- measurement that settled it is this: read at its LOWER BOUND, which is how every other
-- gate input is read, a 90% macro floor fails ALL SIX instruments - the best is keys at
-- 88.38. That is not the model being bad. Macro is a mean of seven proportions, some over
-- 2-4 songs, so its interval is wide (sd 2.0-4.4 against pooled's 1.0-2.1), and certifying
-- evenness at 90% needs a large sample IN EVERY TIER, which this corpus does not have.
--
-- The earlier expectation, recorded in the triage doc, was "bass stops passing and keys
-- starts". That is what happens if macro is compared as a POINT ESTIMATE against 90%. It
-- is not how this gate works, and adopting a point comparison here would have abandoned
-- read-the-pessimistic-end one commit after applying it to rho.
--
-- Bass is a second reason to keep macro out of the gate: its macro p05 of 79.19 is driven
-- by the 4.7% of bootstrap resamples that lose a tier entirely and so average over six
-- bands instead of seven. That number is an artefact of sparse tiers, not a measurement of
-- bass, and gating on it would be gating on noise.
--
-- WHERE 0.80 COMES FROM. From a promise, stated so it does not depend on the figures: the
-- product promises roughly 90% within one tier, and the extremes are accepted as harder -
-- but not MORE THAN TEN POINTS harder. That gives 80%.
--
-- WHAT IS UNCOMFORTABLE ABOUT IT, recorded rather than glossed: 0.80 lands exactly where
-- the three currently-passing instruments sit (guitar 83.17, bass 89.03, drum 84.34) and
-- exactly above the three that fail (keys 82.09 passes this bar but fails on pooled;
-- real_keys 76.38 and vocals 53.53 fail it). The floor was chosen with those numbers
-- visible - they were published before the decision - and no argument here proves the
-- principle was not fitted to them after the fact. What can be said is the direction: this
-- ADDS a requirement and removes none, so it can only make the gate harder to pass. The
-- verdict set is unchanged because the passing instruments already cleared it, not because
-- the bar was placed to spare them.
--
-- A KNOWN WART. The gate now mixes two views. usable% and miss% come from the per-repeat
-- means (tier-then-average); the endpoint bound comes from the bootstrap over averaged
-- residuals (average-then-tier). Those differ by a few tenths. Keeping usable% on its
-- historical Wilson bound was deliberate - it is the number every published figure and
-- every past verdict rests on - but a future tidy-up should put all four on one view and
-- re-derive the floors, as a declared experiment.
--
-- STILL NOT GATED: macro, per-tier accuracy, signed bias, "no severe per-tier failure".
-- The divergence below is narrowed, not closed.
-- ---------------------------------------------------------------------------
--
-- The intent to move to macro is pre-registered in the TierDiagnostics header, written
-- before the corpus grows. Macro remains REPORTED and not gated, for the reasons above.
--   boot   PackBootstrap result for the same selected model, or nil.
function GateVerdict(rec, boot)
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
    -- The bootstrap bound when there is one, the mean when there is not. Both branches
    -- name which they used, so a verdict never leaves it ambiguous.
    local rho_boot = boot and boot.stat and boot.stat.rho
    local rho_val  = rho_boot and rho_boot.lo or rec.rho_mean
    if rho_val < PROTOCOL.RHO_FLOOR then
        passed = false
        reasons[#reasons + 1] = ('rho %s %.3f is below the %.2f floor')
            :format(rho_boot and 'lower bound' or 'MEAN (no bootstrap)',
                    rho_val, PROTOCOL.RHO_FLOOR)
    end

    -- The extremes bar. Bootstrap only: a Wilson bound would land close (the band's design
    -- effect is 1.00-1.16) but the gate reads one stated quantity, not whichever happens to
    -- be available. A missing bootstrap therefore cannot fail an instrument for a
    -- diagnostic that did not run - said out loud rather than passing silently.
    local ep = boot and boot.stat and boot.stat.endpoint
    if not ep then
        reasons[#reasons + 1] =
            'NOTE: endpoint band not checked - no pack bootstrap was available'
    elseif ep.lo < PROTOCOL.ENDPOINT_FLOOR then
        passed = false
        reasons[#reasons + 1] =
            ('endpoint band lower bound %.1f%% is below the %.0f%% floor (tiers 0-1, 5-6)')
                :format(ep.lo * 100, PROTOCOL.ENDPOINT_FLOOR * 100)
    end
    return passed, reasons
end

----------------------------------------------------------------------
-- Per-tier diagnostics, and what the headline number estimates
----------------------------------------------------------------------

-- WHAT THE POOLED USABLE% IS AN ESTIMATE OF. Declared here because the 2026-08-21 peer
-- review showed the question had never been answered, and the answer changes which
-- instruments pass.
--
-- The corpus was deliberately enriched: first at the low end, then at the top end, then
-- specifically in keys' weak tier 4. That is good stress testing and bad sampling. It is
-- NOT a probability sample of the RB3 catalogue, so the pooled percentage estimates an
-- unspecified mixture whose weights change every time songs are added. Keys and Pro Keys
-- currently carry about HALF their rows in the endpoint tiers (0-1, 5-6).
--
-- THE DECLARED ESTIMAND, as of 2026-08-21: the pooled figure is "what a deliberately
-- adversarial sample gets". It is NOT "what a random song gets" and no document may
-- describe it that way. The gate continues to read it, and that is an interim decision
-- rather than a claim that pooled is the right quantity.
--
-- PRE-REGISTERED INTENT: macro (equal weight per occupied tier) is the intended
-- successor as the gate's input. It is declared now, BEFORE the corpus changes and
-- before the numbers move, precisely so that adopting it later cannot be a reaction to
-- which side of the floor something landed on. What has to happen first is measurement -
-- these diagnostics - across at least one corpus change, plus a floor derived for the
-- macro scale rather than inherited from pooled, since 90% was calibrated against a
-- different quantity.
--
-- WHY THIS MATTERS MORE THAN IT SOUNDS. On the current corpus, moving pooled -> macro
-- moves every instrument DOWN, by 0.73 (real_keys) to 7.89 (vocals) points, and inverts
-- two verdicts: bass falls from 94.24% to 89.38% and keys rises from a failing pooled
-- lower bound to 91.52%. The mechanism is uniform - signed tier bias is positive at the
-- bottom and negative at the top on all six instruments - and the pooled number hides it
-- because the middle tiers run at 96-100% and hold most of the rows.
--
-- THE COMPOSITIONAL TRAP THESE EXIST TO CATCH. Adding middle-tier songs raises pooled
-- without improving the model at all, because the middle is where it already succeeds.
-- Macro and the endpoint rate are weighted by tier and are therefore near-invariant to
-- that mix change. So when a rescore moves pooled and leaves macro flat, the movement is
-- COMPOSITIONAL and not an improvement. Read them together or not at all.
--
-- AN ARGUMENT FOR MACRO THAT ONLY APPEARED ONCE THE BASELINES WERE BUILT, and it is the
-- strongest one available: under macro, a constant predictor scores exactly 3/7 =
-- 42.86%, for EVERY instrument and every corpus. A single guessed tier is within one of
-- exactly three of the seven bands, and equal tier weighting makes that arithmetic and
-- not empirical. Under pooled the same baseline ranges from 45.86% (real_keys) to 77.13%
-- (vocals), because it depends entirely on how middle-heavy that instrument's corpus is.
--
-- Two consequences. Pooled scores are NOT comparable between instruments - vocals' 89.02%
-- sits against a 77.13% baseline while real_keys' 89.47% sits against 45.86%, so the same
-- headline hides a fourfold difference in what was achieved. And a macro floor, unlike
-- the pooled 90%, can be reasoned about from a fixed reference point rather than
-- calibrated by eye.
--
-- The gap over the better baseline, measured 2026-08-21:
--   guitar +29.05 pooled / +47.92 macro      keys      +41.73 / +48.66
--   bass   +19.70 pooled / +46.53 macro      real_keys +39.10 / +45.88
--   drum   +23.78 pooled / +47.73 macro      vocals    +11.89 / +38.27
-- Vocals is the finding to sit with: on the metric the gate actually reads, it beats
-- guessing the modal tier by under twelve points.

-- Naive baselines, graded exactly like a candidate.
--
-- WHY. "94% within one tier" reads as a strong result and is not interpretable without
-- knowing what constant guessing scores. Tier distance is a forgiving metric on a
-- middle-heavy corpus: predicting the modal tier for every chart already lands within
-- one tier of everything in the three central bands. The implementation plan required
-- these from the start and they were never built; the peer review asked for them again.
--
-- Both are fitted OUT OF FOLD, on the same stratified splits and the same seeds as every
-- candidate, so the comparison is like for like. A baseline computed over all rows would
-- be optimistic in exactly the way the protocol exists to prevent.
--
--   median-rank  predict the training folds' median rank for every validation row.
--                The intercept-only model, in effect.
--   modal-tier   predict the training folds' most common tier, mapped back to that
--                tier's midpoint rank. Strictly stronger than median-rank whenever the
--                rank distribution is skewed inside the modal band.
--
-- Returns { median_rank = diag, modal_tier = diag }, each a TierDiagnostics table.
function NaiveBaselines(d, target, inst)
    if #target < PROTOCOL.NFOLD then return nil end

    local strata = {}
    for n, ti in ipairs(target) do
        strata[n] = tostring(TierForRank(inst, d.ranks[ti]))
    end

    local med_resid, mod_resid = {}, {}
    for rep = 1, PROTOCOL.N_REPEATS do
        local folds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
        for f = 1, #folds do
            -- Training half of this split.
            local train_ranks, tier_count = {}, {}
            for g = 1, #folds do
                if g ~= f then
                    for _, ti in ipairs(folds[g]) do
                        local rank = d.ranks[target[ti]]
                        train_ranks[#train_ranks + 1] = rank
                        local t = TierForRank(inst, rank)
                        tier_count[t] = (tier_count[t] or 0) + 1
                    end
                end
            end
            if #train_ranks > 0 then
                table.sort(train_ranks)
                local median = train_ranks[math.ceil(#train_ranks / 2)]

                local modal, modal_n = nil, -1
                for t, c in pairs(tier_count) do
                    -- Ties to the LOWER tier, deterministically: pairs() order is not
                    -- stable across Lua builds, so an arbitrary tie-break would make this
                    -- baseline differ between REAPER and the offline runner and break the
                    -- byte-identical report.
                    if c > modal_n or (c == modal_n and t < modal) then
                        modal, modal_n = t, c
                    end
                end
                -- Represent the modal tier by the median rank of its own training rows,
                -- so it is a rank this baseline could actually have observed.
                local in_modal = {}
                for _, rank in ipairs(train_ranks) do
                    if TierForRank(inst, rank) == modal then in_modal[#in_modal + 1] = rank end
                end
                local modal_rank = median
                if #in_modal > 0 then
                    modal_rank = in_modal[math.ceil(#in_modal / 2)]
                end

                for _, ti in ipairs(folds[f]) do
                    local act = d.ranks[target[ti]]
                    local ta  = TierForRank(inst, act)
                    local tm  = TierForRank(inst, median)
                    local tmo = TierForRank(inst, modal_rank)
                    med_resid[#med_resid + 1] = { tier_act = ta, tier_pred = tm,
                                                  dist = math.abs(tm - ta) }
                    mod_resid[#mod_resid + 1] = { tier_act = ta, tier_pred = tmo,
                                                  dist = math.abs(tmo - ta) }
                end
            end
        end
    end

    return {
        median_rank = TierDiagnostics(med_resid),
        modal_tier  = TierDiagnostics(mod_resid),
    }
end

-- Per-tier breakdown of one model's cross-validated predictions.
--
-- Takes the output of CandidateResiduals - the same predictions the headline figures are
-- computed from, so this is a different slicing of one measurement and never a second
-- fit. Returns:
--   tiers    array of { tier, n, share, usable, bias, n_pred } for occupied tiers
--   pooled   share of all rows within one tier
--   macro    unweighted mean of the per-tier usable rates
--   endpoint share of rows in tiers 0-1 and 5-6 that are within one tier
--   ep_n     how many rows that endpoint figure rests on
--   matrix   [actual][predicted] = count, for the confusion matrix
function TierDiagnostics(resid)
    if not resid or #resid == 0 then return nil end

    local n_by, ok_by, bias_by, pred_n = {}, {}, {}, {}
    local matrix = {}
    local pooled_ok, total = 0, 0
    for _, x in ipairs(resid) do
        local t = x.tier_act
        n_by[t]    = (n_by[t] or 0) + 1
        ok_by[t]   = (ok_by[t] or 0) + ((x.dist <= 1) and 1 or 0)
        bias_by[t] = (bias_by[t] or 0) + (x.tier_pred - x.tier_act)
        pred_n[x.tier_pred] = (pred_n[x.tier_pred] or 0) + 1
        matrix[t] = matrix[t] or {}
        matrix[t][x.tier_pred] = (matrix[t][x.tier_pred] or 0) + 1
        total = total + 1
        if x.dist <= 1 then pooled_ok = pooled_ok + 1 end
    end

    local tiers, macro_sum, macro_n = {}, 0, 0
    for t = 0, 6 do
        local n = n_by[t]
        if n and n > 0 then
            local u = ok_by[t] / n
            macro_sum, macro_n = macro_sum + u, macro_n + 1
            tiers[#tiers + 1] = {
                tier = t, n = n, share = n / total, usable = u,
                bias = bias_by[t] / n, n_pred = pred_n[t] or 0,
            }
        end
    end

    -- Endpoints pooled as one band. Whole tiers here hold 2-4 songs (bass Impossible has
    -- 4, vocals Warmup has 2), so a per-tier rate at the extremes is one or two songs
    -- wide and moves on noise. Combining 0-1 and 5-6 gives a band worth reading, which is
    -- the review's own suggestion for handling sparse tiers.
    local ep_ok, ep_n = 0, 0
    for _, t in ipairs({ 0, 1, 5, 6 }) do
        if n_by[t] then ep_ok, ep_n = ep_ok + ok_by[t], ep_n + n_by[t] end
    end

    return {
        tiers    = tiers,
        pooled   = pooled_ok / total,
        macro    = (macro_n > 0) and (macro_sum / macro_n) or nil,
        endpoint = (ep_n > 0) and (ep_ok / ep_n) or nil,
        ep_n     = ep_n,
        n        = total,
        matrix   = matrix,
    }
end

-- Per-tier reliability, in the conditional a USER can actually act on.
--
-- THE REPORT'S PER-TIER TABLE IS THE WRONG WAY ROUND FOR THE PRODUCT, and that is the
-- whole reason this function exists. TierDiagnostics conditions on the OFFICIAL tier -
-- "of charts that really are tier 6, how many did the model place within one?" - which is
-- what tells a calibrator the model compresses. An author holds the opposite thing: a
-- PREDICTED tier, and the question "how much should I trust this number?".
--
-- The two answers differ enormously. On vocals the official-tier view says tier 6 scores
-- 20%, which reads like a broken model. The predicted-tier view says every tier with a
-- usable sample runs 80-94%. Both are true: the model hedges toward the middle, so its
-- predictions are usually near-right - it just almost never COMMITS to an extreme.
--
-- A reliability note built on the official-tier figure would therefore frighten authors
-- about predictions that are in fact sound, and would miss the thing they cannot see: that
-- a genuinely top-end chart gets pulled down. Both facts are emitted:
--
--   n_act    charts whose OFFICIAL tier is this one
--   n_pred   times the model PREDICTED this tier
--   ok_pred  of those predictions, how many were within one tier of the truth
--   actual   the full distribution of OFFICIAL tiers among those predictions,
--            { [official tier] = count }, non-zero entries only
--
-- `actual` is what makes a genuinely useful note possible rather than a reassuring one.
-- On vocals, of the 78 charts placed at tier 4, twenty-nine were actually tier 5 or 6 -
-- so an author reading "tier 4" has better than a one-in-three chance of being
-- under-rated, and no summary statistic short of the distribution can tell them that.
-- n_act against n_pred additionally gives the reach signal (20 official tier 6 against 1
-- predicted), and ok_pred/n_pred the trust-this-number signal. The product uses all three
-- and none substitutes for another.
function TierReliability(diag)
    if not diag or not diag.matrix then return nil end
    local out = {}
    for t = 0, 6 do
        local n_act, n_pred, ok_pred = 0, 0, 0
        local actual = {}
        for a = 0, 6 do
            local row = diag.matrix[a]
            if row then
                local c = row[t] or 0
                if c > 0 then
                    n_pred = n_pred + c
                    actual[a] = c
                    if math.abs(a - t) <= 1 then ok_pred = ok_pred + c end
                end
                if a == t then
                    for p = 0, 6 do n_act = n_act + (row[p] or 0) end
                end
            end
        end
        if n_act > 0 or n_pred > 0 then
            out[t] = { n_act = n_act, n_pred = n_pred, ok_pred = ok_pred,
                       actual = actual }
        end
    end
    return out
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

    -- Two running sums per row: the CLAMPED prediction, which is what a tier and a
    -- displayed rank come from, and the RAW one, which is what rho is graded on. Clamping
    -- happens per fold with that fold's own bounds and BEFORE averaging - averaging first
    -- and clamping once at the end would put the leaky whole-corpus bounds back in by the
    -- side door. See finding 8e.
    local sum, sum_raw, cnt = {}, {}, {}
    for rep = 1, PROTOCOL.N_REPEATS do
        local folds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
        local pred, _, _, clo, chi =
            RunOneRepeat(d, target, extra, folds, rec.keys, factor_pos, rec.scale_obj)
        if pred then
            -- RunOneRepeat emits predictions fold by fold in fold order, so walking the
            -- folds the same way maps each one back to its row.
            local k = 0
            for f = 1, #folds do
                for _, ti in ipairs(folds[f]) do
                    k = k + 1
                    local i = target[ti]
                    sum[i]     = (sum[i] or 0) + ClampRank(pred[k], clo[k], chi[k])
                    sum_raw[i] = (sum_raw[i] or 0) + pred[k]
                    cnt[i]     = (cnt[i] or 0) + 1
                end
            end
        end
    end

    local out = {}
    for _, i in ipairs(target) do
        if cnt[i] then
            local p  = sum[i] / cnt[i]
            local tp = TierForRank(inst, p)
            local ta = TierForRank(inst, d.ranks[i])
            -- pack rides along for PackBootstrap, which resamples these rows by pack.
            -- nil when the caller did not collect it; the bootstrap then treats the row
            -- as its own pack rather than silently pooling every unlabelled row.
            -- pred is the clamped, product-facing value; pred_raw is what rho reads.
            out[#out + 1] = { name = d.names[i], rank = d.ranks[i], pred = p,
                              pred_raw = sum_raw[i] / cnt[i],
                              tier_pred = tp, tier_act = ta,
                              pack = d.packs and d.packs[i],
                              dist = math.abs(tp - ta) }
        end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist > b.dist end
        return math.abs(a.pred - a.rank) > math.abs(b.pred - b.rank)
    end)
    return out
end
