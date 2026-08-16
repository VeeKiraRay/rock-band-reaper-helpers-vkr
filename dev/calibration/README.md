# Difficulty Calibration

A dev-only harness that fits Rock Band's official **rank** from measured properties of an
authored Expert chart, one model per instrument. It exists to answer a question the
Difficulty Suggester feature could not answer by guessing: *what weights?* The weighting
could not be settled by intuition, so it was calibrated against a corpus of real,
officially-ranked songs.

Nothing here ships. The pure scoring code and the fitted coefficients graduate into the
helper; the corpus walking, CSV writing, regression fitting and evaluation protocol stay
in `dev/`.

**Run from the repository checkout, never from a `deploy_to_reaper.bat` copy.** These
scripts locate the corpus relative to their own path, and `_external_docs/` is neither
versioned nor deployed, so a deployed copy finds no songs. Register the repo copy via
*Actions > Load ReaScript*.

---

## Where things stand

Selected model per instrument, as of round 17 (2026-08-16). Reproduced from
`calibration_protocol_report.txt`, which is regenerated on every protocol run and is the
authority if these disagree.

| instrument | selected candidate | scale | k | usable | usable lower bound | miss upper bound | rho | |
|---|---|---|---:|---:|---:|---:|---:|---|
| guitar | `full@attacks` | log(rank) | 21 | 95.70% | **92.18%** | 1.81% | +0.884 | **passes** |
| bass | `baseline+ent_rel@attacks` | log(rank) | 3 | 95.28% | **91.68%** | 1.91% | +0.830 | **passes** |
| drum | `full_drum` | rank | 26 | 95.28% | **91.68%** | 3.07% | +0.859 | **passes** |
| keys | `primary+ent_rel+complex@attacks-chord` | log(rank) | 7 | 94.02% | 89.44% | 0.82% | +0.880 | fails narrowly |
| real_keys | `primary+ent_rel@attacks` | rank | 7 | 86.89% | 81.05% | 4.47% | +0.833 | fails |
| vocals | `primary+range+parts` | log(rank) | 10 | 90.83% | 86.32% | 5.04% | +0.626 | fails |

"usable" is within-one-tier accuracy, averaged across repeats; the two bounds beside it are
the pessimistic end of each interval, which is what the gate reads (floors: usable ≥ 90%,
miss ≤ 5%, rho ≥ 0.70). Keys and Pro Keys fail on the usable lower bound alone; vocals
fails all three criteria.

Development rows per instrument: guitar 158, bass 159, drum 159, vocals 157, keys 122,
real_keys 122 — all `rb3_dlc`, with 0 disputed rows held out.

**Two things this table is not.**

1. These are **development-set repeated-CV** figures. The reserved test partition is
   defined and has deliberately **never been drawn** — it can be spent only once, and it
   is worth more at a real release decision than as a progress check. Call these
   "development-gate passes", not "validated".
2. A failing instrument is not a broken one. Keys misses by 0.86 points at n=122, which
   is a sample-size statement about certifying a 90% floor, not a claim that the model
   got worse.

The reserved partition should be drawn **by whole pack**, not by random rows: the corpus's
multi-song packs are thematic, so related songs would otherwise leak across the split, and
a pack-level split doubles as the domain-shift check.

---

## How to run

Order matters: everything downstream reads the CSV the first script writes.

1. **`run_calibration_vkr.lua`** — walks `_external_docs/reference_songs/`, imports each
   song's MIDI, scores every instrument, appends a row per (song, instrument) to
   `corpus_scores.csv`, and writes `corpus_scores.manifest.txt`.

   **Run it in a scratch project.** It imports tracks, deletes them again, and snapshots
   and restores the tempo map around each song. It is resumable — re-running skips
   (song, instrument) pairs already in the CSV — and it refuses to resume when the column
   set has changed, because appending new-order rows under an old header misaligns every
   factor silently. Delete the CSV for a full rescore.

2. **`run_calibration_protocol_vkr.lua`** — **the decision view.** Predeclared candidates,
   paired repeated cross-validation, nested ridge, and the release gate read from interval
   lower bounds. Writes `calibration_protocol_report.txt` as well as the console, because
   REAPER's console truncates at about 16 KB and this report is longer.

3. **`run_calibration_analysis_vkr.lua`** — **the diagnostic view.** Per-factor Spearman
   correlations, a cross-validated all-factor fit, standardized coefficients, worst
   residuals, and the RB3-vs-Lego origin check. Writes
   `calibration_analysis_report.txt`.

   Its coefficient table is **unstable by design** — an unridged fit over ~31 collinear
   columns. It names the next factor to try; it does not decide anything. When the two
   views disagree, the decision view is the answer. Measured worst case: the analysis put
   `shadowsofthenight` four tiers out where every declared candidate got it within one.

4. **`run_calibration_diff_vkr.lua`** — diffs `corpus_scores_baseline.csv` against
   `corpus_scores.csv` per factor and per song. Run it after a scorer change to see *what
   moved*, which is a separate question from *did the fit improve*. Usage: rename
   `corpus_scores.csv` to `corpus_scores_baseline.csv`, rescore, then run this.

5. **`run_round14_offline.lua`** — scores without REAPER, reading `.mid` files directly
   through `dev/tools/smf_reader.lua` under a plain Lua interpreter.

   **Note if you rescore offline:** `smf_reader.lua` carried a running-status bug until
   2026-08-15 — a meta event overwrote the channel running status, so the next
   running-status note was read as a meta event and the rest of that track was silently
   discarded. It truncated rather than failed, which is worse: `lovehermadly` read 28
   notes on PART DRUMS instead of 5996. The current `corpus_scores.csv` is **not**
   affected (its values match a corrected parse), but any offline rescore predating the
   fix should be redone.

   ```
   lua dev/calibration/run_round14_offline.lua
   ```

   Far faster than the REAPER import loop, and the path to use when only a subset of
   instruments needs rescoring.


6. **`export_production_models.lua`** — freezes the six selected models into
   `lib/reaper_difficulty_models.lua`, the coefficients the helper actually ships. Offline,
   from the repo root:

   ```
   lua dev/calibration/export_production_models.lua
   ```

   Run it after any rescore or re-selection; nothing else regenerates that file, and a
   stale one is not detectable by eye. It refits each candidate once on every row it is
   allowed to train on, prints the pooled inner-fold error for every ridge value, and
   refuses to write if a declared factor is missing, duplicated, or reordered.

   Two deliberate differences from the protocol's ridge handling, both because a shipped
   model must commit to one number where cross-validation never has to: it uses its own
   arithmetic LCG rather than `math.random` (whose implementation changed between Lua 5.3
   and 5.4, so REAPER and the offline runner disagree on what a seed means), and it picks
   the ridge by **pooled** inner-fold error rather than a modal vote across folds. The
   modal vote is knife-edge on guitar — 0.01 at 36% against 0.1 at 31% — whereas pooled
   error separates them cleanly. Full reasoning in the file's header.

7. **`dev/tools/verify_suggester_vs_csv.lua`** — checks that the shipped suggester
   measures what the corpus was scored on. Loads real corpus MIDIs through a mock REAPER
   API and compares every factor, and every predicted rank, against the CSV row:

   ```
   lua dev/tools/verify_suggester_vs_csv.lua 200
   ```

   Current result over all 877 rb3_dlc rows: worst rank difference **2.0**, one suggestion
   changing tier (a chart predicting 332.6 against guitar's tier-5 threshold of exactly
   333). The residual factor drift is confined to `short_frac`, `short_moving_frac` and
   `sustain_frac`, whose thresholds sit exactly on common note lengths — see the file
   header. It cannot prove REAPER's own MIDI APIs behave like the mock, so it complements
   the in-REAPER fixture test rather than replacing it.

Unit tests: **`dev/tests/run_difficulty_score.lua`** for the pure scorers, and
**`dev/tests/run_difficulty_suggester.lua`** for the tiers, the predictor, and the frozen
artifact — the latter refits every model from the CSV at its recorded ridge and compares
coefficient by coefficient, which is what proves the shipped numbers are the model the
protocol selected. Both run from the Actions list or the
`dev/test_rock_band_helpers_vkr.lua` launcher.

---

## The files

### Shared with the shipped helper

The scoring code is **not** in this folder. It lives in `lib/` and in the general helper's
module folder, because the Metadata > Difficulty suggestion and this harness must run the
same measurement: a fitted coefficient only means anything paired with the exact factor
implementation it was measured against, so a second copy would drift and silently
invalidate every model here.

| file | purpose |
|---|---|
| `lib/reaper_difficulty_score.lua` | The gem scorer: `ScoreChart(events, spans, opts)` for guitar, bass, drums, 5-lane keys and Pro Keys. Owns `SCORE_FACTOR_KEYS`, the authoritative factor list and column order. Pure. |
| `lib/reaper_difficulty_score_vocals.lua` | The vocal scorer: `ScoreVocalChart(notes, phrase_spans, opts)`. Pure. **Appends** its columns to `SCORE_FACTOR_KEYS`, so it must load immediately after the gem scorer and before anything that reads that list. |
| `lib/reaper_difficulty_tiers.lua` | Rank to displayed tier (0 Warmup … 6 Impossible) plus `TierBand` / `TierPosition`, from `_external_docs/InstrumentDifficulty.ts`. Pure. |
| `lib/reaper_difficulty_predict.lua` | `DifficultyPredictRank`, `DifficultyFactorZ`, `DifficultyOutOfRange` — how to apply a frozen model. Pure. Coefficients are in **standardized** units; nothing should ever apply them by hand. |
| `lib/reaper_difficulty_models.lua` | **Generated.** The six frozen models: factor order, standardization statistics, coefficients, ridge, rank clamp, per-factor support bounds, concentration thresholds, maturity badge. Rewritten only by `export_production_models.lua`. |
| `rock_band_general_helper_vkr/difficulty_read.lua` | The chart readers: track lookup, gems grouped into chord events, marker spans, animation states, vocal notes with tick-matched lyrics, phrase and percussion ranges, Pro Keys lane shifts. Touches `r.*`; no `S`, no `ctx`. Attaches the `qn` field, which is the one thing the pure scorer cannot compute for itself. |

`difficulty_score.lua`, `difficulty_score_vocals.lua` and `rank_tiers.lua` remain in this
folder as **one-line loaders** pointing at the above, so every entry point and test runner
here keeps its existing load list. Those scripts encode a locked experiment; a file move is
not a reason to edit them.

### Dev-only, and staying that way

| file | purpose |
|---|---|
| `songs_dta.lua` | `songs.dta` parsing: ranks, origin, genre, `vocal_parts`. Pure. |
| `stats.lua` | Spearman/Pearson, the weighted ridge fit (`MultiFit`/`ApplyFit`, standardizing internally), k-fold and seeded stratified shuffled folds, tier distance, Wilson bounds. Pure. |
| `weirdly_scored.lua` | The disputed-label list. Deliberately empty — see the rules below. Pure. |
| `protocol.lua` | **The locked protocol and every candidate declaration.** Read its comments before changing anything; they carry the reasoning and the pre-checks. Pure. |
| `corpus.lua` | Corpus discovery, MIDI import, tempo snapshot and restore, track cleanup, `songs.dta` walking — everything the product must never do. Loads `difficulty_read.lua` itself. |

**Entry points** — the five `run_*.lua` scripts plus `export_production_models.lua`,
described under "How to run".

### The scoring input contract

`difficulty_read.lua` produces plain tables so the scorer stays pure:

- **events** — `{ s, e, qn, qn_e, pitches, held }`, chords grouped by shared onset within
  2 ms, sorted, muted notes skipped.
- **spans** — the stretches where the instrument is actually playing, from its animation
  state text events. Each span is a separate **segment**, and no metric may pair the last
  event of one segment with the first of the next: a chord change across a bar of rest is
  not a change the player executes. That property is structural (`EventsInSegments`
  returns an array of arrays) rather than a rule each metric has to remember.
- Three-level fallback when authored playing states are absent: animation states, then
  `DeriveSpansFromEvents`. A track can legitimately carry a real rank and a real chart
  with no playing state at all.

---

## Data files, and what is versioned

| file | what it is |
|---|---|
| `corpus_scores.csv` | The current run. 205 songs, 1061 rows, 96 factor columns. **Versioned.** |
| `corpus_scores.manifest.txt` | Generated beside it: date, corpus counts by origin, row counts, instruments, factor-column count, and a one-line description of the scorer's measurement behaviour. |
| `corpus_scores_baseline.csv` | The round-13 run, 84 factor columns. **Versioned**, and kept for one reason only: so `run_calibration_diff_vkr.lua` has something to compare a rescore against. |
| `corpus_scores_baseline.manifest.txt` | Its manifest, plus a hand-written verdict block recording what that round selected and why. |
| `corpus_scores_round14.csv` | The round-14 offline rescore output. |
| `calibration_protocol_report.txt` | Generated by the decision view. Overwritten each run. |
| `calibration_analysis_report.txt` | Generated by the diagnostic view. Overwritten each run. |

The corpus itself lives in the untracked `_external_docs/reference_songs/` and exists on
one machine. The CSVs are tracked deliberately: they hold only derived measurements —
shortname, official rank, factor values — with no MIDI and no audio, the same class of
metadata any `songs.dta` reader produces. Without them the repo would contain no data at
all, and the coefficients that ship in the helper would have no derivation anywhere in it.
They keep earning that place after the feature ships, because every remaining modelling
question is answered from the CSV alone, with no REAPER and no corpus.

What a CSV cannot survive is a change to the factor **set** — a new column means a full
rescore — which is why exactly **two** are tracked (current, plus the baseline a change is
being measured against) rather than an accumulating archive. Older factor sets can be
neither refit nor row-compared against the current one; they are kept locally and ignored
by `.gitignore`.

The scoring run's console output also prints the corpus's current tier histogram from the
`songs.dta` ranks, so the coverage picture stays current instead of going stale in a
document. A thin tier means residuals there say little: two songs cannot establish whether
the model handles that band.

---

## The locked protocol

Across the first four rounds the factor set went 6 → 9 → 19 → 23 factors, with roughly
forty model comparisons run against the same rows under the same fold assignment, keeping
whatever looked best each time. That is selection inflation. `protocol.lua` exists to stop
it, and its rules are fixed before a run rather than after seeing output.

- **Candidates are predeclared.** Adding one to an instrument is a **declared
  re-opening**, noted in the code beside the existing declarations, not an edit to a
  sealed table.
- **Comparisons are paired.** Every candidate is scored on the *same* fold assignments
  within each repeat, and judged by the distribution of paired differences across repeats
  — never by two marginal percentages. A round-3 result turned on a difference of about
  one song.
- **Ridge is tuned inside the training folds** (nested, `INNER_FOLD = 3`), never on rows
  it will be evaluated on.
- **The gate reads interval lower bounds**, not point estimates.

Parameters (`PROTOCOL`):

```
N_REPEATS  10        NFOLD  5        SEED  20260812        INNER_FOLD  3
RIDGE_GRID  1e-6, 1e-3, 1e-2, 1e-1, 1.0, 10.0
LEGO_WEIGHT  0.3     Z  1.645  (one-sided 95%)
USABLE_FLOOR  0.90   MISS_CEILING  0.05   RHO_FLOOR  0.70
```

Folds are stratified by **actual tier**, because whole tiers hold 2-3 songs and an
unstratified shuffle can leave a fold with none of them.

**Targets and weights.** RB3 DLC is the target throughout — 159 of the corpus's 205 songs.
The 45 Lego-era songs sit on a rank scale about 45 points below it, so they are
always-training at weight 0.3 and carry an `is_lego` column: they add information without
steering the model. `PART KEYS` has no Lego rows at all — Lego Rock Band predates the
keyboard part. The one `greenday` song is scored into the CSV but excluded from every fit,
so it never appears in a development row count.

**The selection rule.** Order candidates by simplicity (fewest features, then declaration
order); take the best mean usable% as the leader; walk upward from the simplest and select
the first candidate the leader does not *clearly* beat. "Clearly" means winning more than
**70%** of paired repeats **and** by more than **1 percentage point** on average. A bigger
model has to earn its place consistently, not post a higher average once.

**Two reporting rules.**

- **MAE is not comparable across target scales.** Fitting `log(rank)` buys proportional
  accuracy at the cost of absolute accuracy, so its MAE can rise while its tier accuracy
  improves. Grade on tier distance; the decision report omits MAE entirely.
- Predictions are **clamped to the observed rank range** before display. A log-scale fit
  exponentiates, so an extreme input produces a number that is not a rank at all — one
  bass chart came back at 943 against a corpus spanning 135-488. This changes no headline
  figure (tier 6 is tier 6 either way, and Spearman is order-preserving); it is about not
  printing nonsense.

---

## Rules a new session must not break

1. **The protocol is locked.** Candidates and thresholds are declared before a run.
   Changing either is a new experiment, not a re-run — say so if you do.
2. **Never loosen a selection threshold to make something pass.** Bass missed by 0.17
   points in round 7 and the rule was left alone. In round 13 the best vocal candidate
   ever measured missed the bar on both criteria by the smallest possible margin and the
   simpler model was taken. That is the protocol working.
3. **`weirdly_scored.lua` is the most dangerous file here**, and its list is deliberately
   empty. Every entry raises reported accuracy. Read its four criteria before adding
   anything: a label is disputed when the chart contradicts it mechanically, not when it
   is inconvenient.
4. **Reference songs and corpus MIDI are never shipped or committed.** They are commercial
   content the author does not own. `_external_docs/` is gitignored and stays that way.
5. **Standalone Spearman does not predict fitted gain**, in either direction. It is a
   screen for whether a factor is worth declaring, never a size estimate. Getting this
   wrong is the single most repeated error in this project's history — weak rho with a big
   gain, unchanged rho with a big gain, and improved rho with a loss have all happened.
6. **Judge a factor by the decision view, not the diagnostic view.** See
   `run_calibration_analysis_vkr.lua` above.

---

## Findings worth keeping

- **The finger-load rule.** Count **attacks** where one motion strikes many gems (guitar,
  bass, Pro Keys); count **gems** where each one needs its own finger or limb (5-lane keys,
  drums). This was derived on guitar and bass, then made a correct out-of-sample prediction
  about drums before drums were in the corpus — the project's strongest methodological
  result. Its one clean failure was Pro Keys, where the gem version lost, so the mechanism
  is an open question rather than a settled rule.
- **The kick is the third limb and outweighs the hands.** `kick_density_peak` carries the
  largest coefficient in the drum model. (An earlier version of this finding added that
  `stick_size_mean` is *negative*, i.e. that simultaneous limbs read easier. **That is not
  true of the shipped model** — its coefficient is **+4.72**, and holding attack rate fixed
  the correlation with rank is **+0.01**, no effect in either direction. It reads negative
  only when GEM density is held fixed, which is the units artifact described below.)
- **The vocal rank includes harmony burden.** Scoring `PART VOCALS` alone under-rates
  3-part songs by ~34 rank points and over-rates 1- and 2-part songs by ~17. Adding
  `vocal_parts` as a context term is worth +1.53 points and rho +0.579 → +0.626.
- **The vocal rank means "sing it as written".** Register was initially refused as a factor
  on the rule that difficulty follows what the game *requires* — pitch-class scoring
  ignores the octave. Reversing that made the two register columns the strongest factors in
  the whole vocal set (`notated_range` +0.485, `pitch_p90` +0.474). Low register is *not*
  hard, measured rather than assumed: `low_time_50` is **-0.167**.
- **The rank is not Pro-drums-aware.** Scoring drums under an eight-gem vocabulary, where a
  tom and a cymbal on one colour are different gems, earns no fitted gain. Advising on the
  Pro reading is a product choice with +0.273 as its measured cost.
- **Single-note statistics are fragile.** `top_note` is the strongest vocal factor on
  record (+0.594) and one exceptional note can set it: the corpus's highest top note
  belongs to an ordinarily-ranked song, which the model using it puts three tiers out.
  Prefer duration-weighted or time-above-threshold forms.
- **The sparse end of drums is noisy in the LABELS. Do not "fix" it in the model.** An
  author reported a slow rock-beat chart scoring 113 (pinned to the 120 floor) against their
  own judgement of Apprentice. Investigated and closed with no change:

  - The penalties are all one fact — the chart is slow. Average attack rate **-34.8**, peak
    kick rate **-29.5**, peak and average gem density **-26.0** each, total gems **-16.0**.
    It is **11 rank short** of Apprentice, much closer than the pinned display suggests.
  - Its 407 total gems is below the corpus minimum of **502**, so it is an extrapolation.
  - **There is no systematic bias at the sparse end**: mean signed error over the 12
    sparsest corpus drum charts is **+1.4 rank**, and **-0.1** over all 159.
  - What there is, is scatter of **±50 rank** — where the whole Warmup→Solid span is
    124→178 — because the official labels disagree with each other down there. Harmonix
    rated `wanteddeadoralive2` **120** and `livelyupyourself2` **229** at nearly identical
    densities, and `dreamonlive` (density 3.66) got **129**.

  So an author's Apprentice call on such a chart is well inside the model's error band and
  is not evidence of a defect. The model is unreliable at the sparse end because its
  training labels are, and no reparameterisation fixes that — only labels would.

- **A coefficient's sign is only interpretable relative to the units of the factors beside
  it.** The cleanest case in the project: `chord_size_mean` is **-12.86 on keys** and
  **+12.22 on Pro Keys** — the same music, scored from the same notes, sign reversed. The
  models differ in one relevant way. Keys measures density in **gems** (`density_peak`), so
  a three-note chord triples it and `chord_size_mean` is free to divide that back out,
  landing negative. Pro Keys measures **attacks** (`attack_density_peak`), where nothing
  needs dividing out, and it lands positive. Guitar also measures attacks and its chord
  coefficient is ~0.00; bass omits the factor entirely.

  The negative sign is a **decomposition artifact, not a statement that chords are easy**.
  Holding attack rate fixed, chord size against official rank is **+0.24 on keys and +0.22
  on Pro Keys** — larger chords go with *higher* ranks. Unconditionally it is only +0.08,
  because chordal parts are struck more slowly; speed was the confound and chord size was
  standing in for it.

  This reaches authors: a slow 80bpm keys chart of sustained three-note chords scored **84**
  uncapped, of which **-50 was chord size alone**, and the identical chart written as single
  notes scores **152**. Authors dispute that on sight and they are right to. Note separately
  that `chord_size_mean`'s corpus maximum is **2.80**, so an all-triads chart is an
  extrapolation as well as a low scorer.

  **ROUND 16 settled it.** A 2x2 over the selected keys candidate, holding the other six
  factors fixed — gems/attacks × with/without `chord_size_mean`:

  | cell | k | best usable | lower bound | rho |
  |---|---:|---:|---:|---:|
  | gems + chord (round 15 incumbent) | 8 | 93.77% | 89.14% | +0.874 |
  | gems − chord | 7 | 92.21% | 87.24% | +0.860 |
  | attacks + chord | 8 | **94.02%** | 89.44% | +0.875 |
  | attacks − chord | 7 | **94.02%** | 89.44% | **+0.880** |

  The two attacks cells are **identical to two decimal places**, and the fitted chord
  coefficient collapses from **−12.86** (with gems) to **+0.02** (with attacks). Dropping
  chord size costs 1.56 points under gems and *nothing* under attacks. The factor was doing
  the gems-to-attacks conversion and nothing else — as predicted before the run. Selection
  went to the simpler 7-feature `@attacks-chord` on the ties-to-simpler rule.

  Two things the round did **not** establish. It did not show that chords are hard: the
  factor is simply redundant once density counts attacks. And it did not fix the gate —
  89.44% against the 90% floor, still a sample-size problem at n=122.

  **This was adopted.** `lib/reaper_difficulty_models.lua` ships the round 16 model, so
  voicing is no longer an input to a keys suggestion at all. What it fixed, measured on a
  real chart: a slow keys part at a fixed strike rate scored 140 / 112 / 84 voiced one,
  two and three notes wide under round 15 — roughly **-28 rank per added note**, two tiers
  between the extremes, with the triad version pinned to the clamp floor. Under round 16
  it scores **147 at every voicing**. The author who reported it converted their chart to
  single notes and measured 144 against 84, independently confirming the slope.

- **Chord voicing earns nothing on keys once speed is counted honestly (round 17).** Having
  removed the artifact, the obvious next question is whether chords add difficulty for real.
  Three candidates on the round 16 base:

  | candidate | k | best usable | lower bound | coefficient on the added factor |
  |---|---:|---:|---:|---:|
  | base (round 16) | 7 | 94.02% | 89.44% | — |
  | + `chord_change_frac` | 8 | 94.02% | 89.44% | +0.008 |
  | + `chord_span_mean` | 8 | 94.18% | 89.64% | **-0.010** |
  | + both | 9 | 93.61% | 88.93% | — |
  | (+ `chord_size_mean`, from round 16) | 8 | 94.02% | 89.44% | +0.020 |

  Nothing came near the 1-point bar — the best is +0.16 — so the base was retained. Every
  coefficient is negligible, and the one belonging to the *best-performing* candidate is
  **negative**, which under round 17's own pre-registered rule would have been grounds to
  refuse it had it been selected.

  The honest reading: **the official keys rank does not measurably reward chord voicing once
  strike speed is accounted for.** That is a result, not a failure, and it is why shipping a
  voicing-neutral model is right rather than merely convenient.

  **"Not measurable" is not "not there", and the difference decides this.** The fitted
  coefficient on `chord_size_mean` is small in standardized units but *not* small in effect:
  at +0.0203 on log(rank) with sd 0.379, including it would move a chart **+11.3%** between
  single notes and triads — +17 rank at 150, +28 at 250, about half a tier. What is small is
  the evidence. The partial correlation with rank falls from **+0.24 holding attack rate
  alone to +0.10 holding the full base**: `complex_peak`, `entropy_h2_rel` and
  `total_changes` already absorb most of what chord size was tracking. At n=122 with 8
  factors the standard error on a correlation is ≈0.09, so +0.10 is **one standard error
  from zero**.

  So the factor is excluded because it would do a lot on evidence that cannot support it —
  not because it would do little. Anyone revisiting this should not read the round 17 table
  as "chords do not matter". The right sentence is "the corpus cannot tell whether they do".
  Keys needs ~50 more songs to clear the gate regardless (n=122 → 172); at that size a +0.10
  residual becomes testable, and this question gets a real answer for free.

  A methodological note worth the embarrassment: round 17 predicted `chord_change_frac`
  would be the strongest of the three, because its partial correlation was +0.22 against
  `chord_span_mean`'s +0.05. It was the weaker of the two. That is this README's own rule
  about standalone correlation not predicting fitted gain, walked into by the person who
  wrote it down.

  Regardless of any of this, **no shipped wording may state a difficulty direction for this
  factor** — see the header of `rock_band_general_helper_vkr/difficulty_explain.lua`.
- **Playing time barely matters, and "sparse charts are penalised" is measured and false.**
  A recurring hypothesis, worth recording so it is not re-proposed: `playing_s` carries
  **-0.81** rank per sd on keys and **-0.34** on drums, against +32 for the largest lever
  in the same model. Across its entire observed range it moves a suggestion by ~1 rank
  point, and the *sign is negative*, so a short chart already gets a tiny bonus. The corpus
  covers the sparse end well — keys `playing_s` spans **29-474 s**, and Harmonix rated
  `californication` (29 s of keys) Warmup 130 while `turningjapanese` (98 s) got
  Apprentice 178. A chart that scores low while playing little is being scored low for
  density, repetition and complexity, which happen to co-occur with playing little.
- **The selected factors are collinear enough to matter downstream.** Not a modelling
  result — the ridge handles it — but the explanation UI shows the three *most unusual*
  measurements, and on 20% of corpus rows two of those were a correlated pair restating one
  observation. Worst offenders are per-instrument: `entropy_h2`/`entropy_h2_rel` **+0.96 on
  drums**, `notes_total`/`total_changes` **+0.94 drums but +0.80 guitar**,
  `complex_peak`/`density_peak` **+0.88 keys only**, `tight_p10`/`tight_med` **+0.45 drums
  to +0.75 vocals**. The exporter therefore ships a `corr` table per model. Any future
  consumer that ranks or groups factors needs the same treatment.

---

## The full history

The round-by-round record — every hypothesis, every negative result, the reasoning behind
each factor, and the residual investigations — lives in
`_future_ideas/general_difficulty_suggester.md`, with per-round detail in the
`_round14_results.md` and `_round15_results.md` files beside it.

That folder is **gitignored**, so those documents exist only on the authoring machine.
This README is the tracked summary. If you have the narrative file, read the
**CURRENT STATUS** block at the top of it before anything else: the rest is chronological,
and numbers quoted inside a round section are that round's numbers and are often
superseded.
