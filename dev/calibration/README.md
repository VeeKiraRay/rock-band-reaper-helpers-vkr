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

Selected model per instrument, as of round 22 (2026-08-18), on the 394-song corpus at 114
factor columns. Reproduced from `calibration_protocol_report.txt`, which is regenerated on
every protocol run and is the authority if these disagree.

| instrument | selected candidate | scale | k | usable | usable lower bound | miss upper bound | rho | |
|---|---|---|---:|---:|---:|---:|---:|---|
| guitar | `full@attacks` | log(rank) | 21 | 94.16% | **91.64%** | 1.36% | +0.862 | **passes** |
| bass | `baseline+entropy` | log(rank) | 3 | 94.18% | **91.68%** | 1.35% | +0.802 | **passes** |
| drum | `full_drum@noroll` | log(rank) | 26 | 96.46% | **94.37%** | 1.35% | +0.894 | **passes** |
| keys | `primary+ent_rel+complex@attacks-chord` | rank | 7 | 92.97% | 89.94% | 1.08% | +0.878 | fails by 0.06 |
| real_keys | `primary+ent_rel@attacks` | rank | 7 | 89.40% | 85.89% | 2.02% | +0.861 | fails |
| vocals | `parts+tess+move@parts_step3` | log(rank) | 12 | 88.63% | 85.42% | 4.32% | +0.674 | fails |

Rounds 19-22 changed two of the six. Drums took the roll-lane peak twins (+0.99 on the
lower bound) and vocals took the harmony count as a step instead of a number (+0.30).
Guitar, bass, keys and Pro Keys are unchanged **to the decimal**, which is what confirms
the eighteen new columns did not leak into the four instruments they were not for.

"usable" is within-one-tier accuracy, averaged across repeats; the two bounds beside it are
the pessimistic end of each interval, which is what the gate reads (floors: usable >= 90%,
miss <= 5%, rho >= 0.70). Keys and Pro Keys fail on the usable lower bound alone; vocals
fails that and rho.

Development rows per instrument: guitar 327, bass 330, drum 328, vocals 328, keys 266,
real_keys 266 - all `rb3_dlc`, with 0 disputed rows held out. Lego (45 rows) and the RB2
disc export (15) always train at weight 0.30 and are never predicted.

**The numbers fell when the corpus grew, and that is the corpus working.** Round 17's table
read guitar 92.18% and vocals 86.32% on 205 songs whose coverage was thin at both ends.
Filling the low end and then the top end moved every figure toward what a random song would
actually get; a middle-heavy corpus flatters a model that hedges toward the middle.

**Keys is the standing lesson about sample size.** It missed by 0.05 points at n=251, so 15
charts were added specifically to close it - and it now misses by **0.06** at n=266. The
larger n was exactly cancelled by a lower mean, because the added charts were deliberately
drawn from tier 4, the model's weakest bracket. Adding songs the model already handles
would have passed the gate and taught nothing. Read this as evidence that keys has a real
accuracy ceiling rather than a sample-size shortfall.

**Two things this table is not.**

1. These are **development-set repeated-CV** figures. The reserved test partition is
   defined and has deliberately **never been drawn** — it can be spent only once, and it
   is worth more at a real release decision than as a progress check. Call these
   "development-gate passes", not "validated".
2. A failing instrument is not a broken one. Keys misses by **0.06 points** at n=266 with
   the best rho of any instrument (+0.878) - a statement about certifying a 90% floor,
   not a claim that the model got worse. It does **not** follow that a few more charts
   would clear it: two collection rounds have now tried exactly that and both cancelled
   out. See Open threads.

The reserved partition should be drawn **by whole pack**, not by random rows: the corpus's
multi-song packs are thematic, so related songs would otherwise leak across the split, and
a pack-level split doubles as the domain-shift check.

---

## How to run

Order matters: everything downstream reads the CSV the first script writes.

1. **`run_calibration_vkr.lua`** — walks every root in its own `_corpora` list, imports each
   song's MIDI, scores every instrument, appends a row per (song, instrument) to
   `corpus_scores.csv`, and writes `corpus_scores.manifest.txt`.

   Three roots as of 2026-08: `_external_docs/reference_songs/`,
   `_external_docs/new_reference_songs/` (a low-end set assembled by searching per
   instrument, so a pack easy on two instruments appears in two folders), and
   `_external_docs/hard_reference_songs/` (the top-end set, searched the same way for
   tier 5+ charts). **Per-root and total song counts are deliberately not quoted here** —
   `corpus_scores.manifest.txt` carries them and is regenerated by every run, whereas a
   number written into this paragraph has now gone stale twice. Most of the third root is
   RBN, whose dta dialect is deliberately not parsed. The song list is
   pooled and de-duplicated by shortname before
   anything is imported, and the roots are recorded in the manifest — origin counts alone
   cannot distinguish a corpus that includes the low-end set from one that does not, since
   both are `rb3_dlc`.

   The two layouts differ and both are handled: the original nests a pack under
   `Root/songs/<name>/<name>.mid`, the low-end set is flat, with `songs.dta` and every MIDI
   in one folder. A flat pack's dta describes the whole pack, so most of its entries have
   no MIDI present and are reported rather than silently skipped.

   **De-duplication prefers an entry that carries a MIDI, and this is load-bearing.** Because
   a pack's dta names every song in the pack while only some MIDIs were extracted, the same
   shortname is reported *with* its `midi_path` from the folder holding the file and
   *without* it from a folder that merely lists it. The first version of the pooled walk
   kept whichever entry came first and dropped 25 songs as MISSING MIDI whose files were
   present under another folder — among them the songs holding the lowest drum (93), keys
   (90) and Pro Keys (80) ranks in the corpus, so the low-end set failed at exactly the job
   it was assembled for, and the manifest's `missing MIDI` count absorbed the loss without
   looking wrong. Reorganising the folders on disk is not a substitute: it collapses only
   the repeated-pack-folder case, leaving the 2 songs listed by two different packs and the
   44 shared with the original root still needing the same rule.

   **Run it in a scratch project.** It imports tracks, deletes them again, and snapshots
   and restores the tempo map around each song. It is resumable — re-running skips
   (song, instrument) pairs already in the CSV — and it refuses to resume when the column
   set has changed, because appending new-order rows under an old header misaligns every
   factor silently. Delete the CSV for a full rescore.

2. **`run_calibration_protocol_vkr.lua`** — **the decision view.** Predeclared candidates,
   paired repeated cross-validation, nested ridge, and the release gate read from interval
   lower bounds. Writes `calibration_protocol_report.txt` as well as the console, because
   REAPER's console truncates at about 16 KB and this report is longer.

   **Run it offline — `lua dev/calibration/run_protocol_offline.lua`.** At 318 songs the
   in-REAPER action stopped completing: a ReaScript holds REAPER's main thread for the
   whole computation, so the UI goes "Not responding" and the run was killed partway
   through writing the report. The offline driver finishes the same work in about two
   minutes, and the numbers are not merely comparable but **identical** — fold assignment
   is explicitly seeded and both interpreters are Lua 5.4, verified by diffing against a
   crashed run's partial report (all 59 completed lines byte-identical). Sleeps or
   coroutines would not help; see the header of `run_protocol_offline.lua` for why. The
   REAPER action is kept because it still works on smaller corpora and is the reference
   the driver shims.

3. **`run_calibration_analysis_vkr.lua`** — **the diagnostic view.** Per-factor Spearman
   correlations, a cross-validated all-factor fit, standardized coefficients, worst
   residuals, and the RB3-vs-Lego origin check. Writes
   `calibration_analysis_report.txt`.

   Its coefficient table is **unstable by design** — an unridged fit over every column,
   96 of them and heavily collinear. It names the next factor to try; it does not decide
   anything. When the two views disagree, the decision view is the answer.

   **Its residual list is the trap**, because it reads exactly like a model failure.
   Measured worst case: the analysis put `deathontwolegs` **five tiers out** on keys —
   *said tier 0, actual 5, −346 rank* — on a chart the shipped model rates correctly at
   −30. The mechanism is worth knowing, because it will recur: that chart is **15.3 sd**
   out on `solo_change_ratio` and on nothing else, the unridged fit hands that column a
   *negative* coefficient, and with no ridge to restrain it the prediction floors. A
   single extreme row cannot establish a coefficient's sign, and this view has nothing
   stopping it from trying. (The previous record was `shadowsofthenight`, four tiers out
   where every declared candidate got it within one.)

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

8. **`dev/tools/score_corpus_offline.lua`** — scores an arbitrary corpus root into
   `corpus_scores.csv`'s exact schema, without REAPER:

   ```
   lua dev/tools/score_corpus_offline.lua _external_docs/new_reference_songs out.csv
   ```

   For **looking at a candidate corpus before committing to the REAPER pass** — row counts,
   rank coverage, what the clamp floors would become. It resolves MIDIs by indexing every
   `.mid` under the root by basename rather than by any path convention, so it handles both
   layouts, packs holding several songs, and dta entries whose MIDI was never extracted.
   Duplicate basenames are resolved silently when the bytes match and reported loudly when
   they do not.

   **Its output must never be merged into a REAPER-scored corpus.** The drift is small but
   systematic — this converts ticks through the SMF's tempo map and the CSV through
   REAPER's — so mixing them would put a measurement difference exactly along the new/old
   split, which is indistinguishable from a real effect. Measured on the 44 songs present
   in both corpora: **0 rank disagreements over 260 rows**, drift confined to `sustain_frac`
   (13 rows) plus one guitar chart whose final playing span closes 4 s earlier.

9. **`run_label_probes_offline.lua`** — asks whether a failing instrument is limited by its
   FACTORS or by its LABELS, without fitting anything shippable:

   ```
   lua dev/calibration/run_label_probes_offline.lua
   ```

   *Probe 1* scores each rank three ways under the locked protocol — the shipped candidate's
   chart factors, the other instruments' ranks for the same song, and both — so the share of
   a rank that is a property of the SONG rather than of the chart becomes visible. Anything
   the other instruments already predict is unreachable from one chart, whatever factors are
   added. A `chart, all` row repeats the first column over every target row and **must
   reproduce `calibration_protocol_report.txt`**; if it does not, the harness is not running
   the protocol and its other columns mean nothing.

   *Probe 2* tests whether a part new to RB3 was ranked less consistently early on, using
   `(song_id N)` from `songs.dta` as a release-order proxy inside a catalogue block. It
   reports the raw id-vs-residual trend, the trend with **rank held fixed**, and
   `rho(id, rank)` itself. The partial is the one to read: `song_id` correlates with rank on
   exactly the instruments under test (vocals +0.22, Pro Keys −0.15), because the top-end
   songs were added by a deliberate hard-song search and those skew late — so the raw trend
   measures "later songs are harder" and would report it as "the ranks were still settling".
   Vocals' raw +0.195 drops to +0.142 and stops being a finding; Pro Keys' −0.181 survives.

10. **`run_cross_instrument_probe_offline.lua`** — does another part of the same song carry
    anything the target chart does not? Offline, like the label probes:

    ```
    lua dev/calibration/run_cross_instrument_probe_offline.lua
    ```

    Adds a fixed set of columns measured on a *different* part to the shipped model, and
    scores `chart` / `chart+cross` / `cross only` under the locked protocol. Carries the
    same `chart, all` fidelity row, plus a **row-loss gate** — a pair whose source part is
    missing on some songs is not measuring what the published figures measured, so the
    dropped count is printed per source and flagged. It also applies the protocol's own
    selection bar and gate thresholds directly, so a rising mean cannot be mistaken for a
    round that would land.

    Two vocabularies, and the reason is worth knowing before adding a third: the first
    (`CROSS_COLUMNS`, rhythm) turned out to be *the same numbers* on the keyboard pair,
    because the 5-lane reduction preserves timing exactly. The second
    (`CROSS_COLUMNS_GEOMETRY`) was chosen from measured Pro-Keys-to-keys ratios, not from
    scores. Shared join and both vocabularies live in `cross_factors.lua`. **Cross columns
    are carried as `{ name, src, key }` records and the name is never parsed back apart** —
    `x_real_keys_tight_p10` splits ambiguously, and getting it wrong reads the wrong
    instrument's factor while still converging.

    Result: nothing selected on any pair. See the findings section.

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
| `corpus_scores.csv` | The current run. **Versioned.** Its manifest carries the counts; this table deliberately does not, having twice gone stale here. |
| `corpus_scores.manifest.txt` | Generated beside it: date, corpus counts by origin, row counts, instruments, factor-column count, and a one-line description of the scorer's measurement behaviour. |
| `corpus_scores_baseline.csv` | The immediately preceding run, same factor set. **Versioned**, and kept for one reason only: so `run_calibration_diff_vkr.lua` has something to compare a rescore against. |
| `corpus_scores_baseline.manifest.txt` | Its manifest, plus a hand-written verdict block recording what that round selected and why. |
| `calibration_protocol_report.txt` | Generated by the decision view. Overwritten each run. |
| `calibration_analysis_report.txt` | Generated by the diagnostic view. Overwritten each run. |
| `calibration_label_probes_report.txt` | Generated by `run_label_probes_offline.lua`. Overwritten each run. |
| `calibration_cross_instrument_report.txt` | Generated by `run_cross_instrument_probe_offline.lua`. Overwritten each run. |

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

**Targets and weights.** RB3 DLC is the target throughout — 330 of the 394 songs actually
scored, the rest being 45 Lego-era, 15 RB2-era and 4 `greenday`.

> **Two different song counts, and they are easy to confuse.** `corpus_scores.manifest.txt`
> reports `corpus songs : 526` — that is songs **walked**, and 132 of them had no readable
> MIDI (mostly RBN `ugc_plus`, whose dta dialect is not parsed; see Open threads). **394**
> songs reached the CSV, which is the number every figure in this document is about.
> Confirm either from the CSV itself rather than from the manifest's headline.

The Lego-era songs sit on a rank scale about 45 points below RB3, so they are
always-training at weight 0.3 and carry an `is_lego` column: they add information without
steering the model. `PART KEYS` has no Lego rows at all — Lego Rock Band predates the
keyboard part — and none from RB2 either, so both keyboard parts are 266/266 rb3_dlc and
neither auxiliary origin contributes a single keys row. The one `greenday` song is scored
into the CSV but excluded from every fit, so it never appears in a development row count.

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
- **But the harmony term is a *step at three*, not a ramp — and it is a production-scale
  label, not a difficulty measurement.** Fitting the other eleven vocal factors and reading
  the residual by level: one part **−0.0772**, two parts **−0.0787**, three parts
  **+0.0595**. One and two singers are the *same level* (0.4 rank apart); the entire effect
  is the step to three (+34 rank). The linear term cannot say that, so it splits the
  difference and over-credits all 87 two-part songs by ~12 rank. The reason is authoring
  practice, not vocal load: three parts is the **house default** (187 of 328, 57%), an
  author adds HARM2 for any backing vocal worth capturing, and HARM3 needs three distinct
  simultaneous lines. So the term reads "this arrangement did not earn full harmonies",
  which is why it works at all — the rank it predicts grades `PART VOCALS` alone and the
  harmony tracks are never read. Declared as round 20; `parts_3` posts 88.63% / rho +0.674
  against the incumbent's 88.35% / +0.668. **The assumption-free control is the real
  result**: given one free coefficient per step, the fit ties the single step exactly
  (88.63%), so it does not use the permission.
- **Measuring inside the harmony tracks does not beat the free label. Do not build the
  reader.** The obvious upgrade — detect whether HARM2/HARM3 are real parts or the lead
  doubled — was swept over every corpus MIDI and fitted every way it can be fitted.
  - **Harmonies are almost never unison doubles.** Same pitch as the lead: mean **0.124**,
    median **0.030**. The typical HARM2 is a *different* pitch on the *same* words at the
    *same* time covering ~40% of the chart — musically a second part, structurally
    dependent on the lead. Duplication has to be measured on note starts *and* ends, not on
    pitch, or it reads every parallel-third harmony as independent.
  - **Duplication is bimodal, and 1.000 is a real mode.** Of 461 harmony tracks, **29
    (6.3%) duplicate at exactly 1.000**, **zero** sit between 0.999 and 1.000, and only 5
    between 0.990 and 0.999. Authors either paste the lead's rhythm or write something
    else; there is no continuum to grade along.
  - **A graded discount is actively harmful**: −0.98 points at **0%** of paired repeats,
    rho +0.668 → +0.632. Discounting each harmony by how mirrored it is drags 68.6% of
    songs below their declared count and erases the production-scale reading that was doing
    the work. Replacing the count with independence outright is worse still (−1.55, 0%).
  - **Only the strictest cut-offs help, and not enough.** `parts_eff` at 0.90 / 0.95 / 0.99
    / 1.00 gains +0.40 / +0.37 / **+0.49** / **+0.52** points — best at the strictest, which
    agrees with the bimodality. Against a 1.00-point bar, while moving 23 of 328 rows, for
    a new parsing path through HARM1/2/3. Adding a harmony measurement *beside* the count
    buys +0.21 / +0.09. **Not pursued.**
  - One asymmetry, recorded rather than acted on: 6% is *Harmonix's* practice. A custom
    author copy-pasting harmonies is the fast way to write them, and the one non-corpus
    chart checked (`oliver_t_cowboys_d_cry_vkr`) mirrors at **1.000 on both parts**. This
    may matter more to the tool's users than to the corpus that calibrates it — which is a
    reason to have measured it, not a reason to ship an unearned column.
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
  89.44% against the 90% floor, read at the time as a sample-size problem at n=122.

  > *Corrected since.* Keys is now at n=266 and the gate still fails, by 0.06. The
  > sample-size reading was wrong; see Open threads. The figures above are left as they
  > stood at round 16 rather than rewritten — this section is a record of what each round
  > found, not a running status.

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

  > *That SE is the round-17 corpus.* At today's n=266 it is ≈0.06, making +0.10 about
  > **1.6 SE** — still not significant, and the conclusion below is unchanged. Recorded
  > because anyone recomputing it will get 0.06 and needs to land where round 17 landed.

  So the factor is excluded because it would do a lot on evidence that cannot support it —
  not because it would do little. Anyone revisiting this should not read the round 17 table
  as "chords do not matter". The right sentence is "the corpus cannot tell whether they do".

  A methodological note worth the embarrassment: round 17 predicted `chord_change_frac`
  would be the strongest of the three, because its partial correlation was +0.22 against
  `chord_span_mean`'s +0.05. It was the weaker of the two. That is this README's own rule
  about standalone correlation not predicting fitted gain, walked into by the person who
  wrote it down.

  Regardless of any of this, **no shipped wording may state a difficulty direction for this
  factor** — see the header of `rock_band_general_helper_vkr/difficulty_explain.lua`.
- **The vocal rank rewards singing HIGH AND MOVING, not high and sustained** (round 18).
  Vocals under-predicts its hardest charts by ~117 rank, three times worse than any other
  instrument's top-end shrinkage (guitar -37, bass -45, keys -40), so the shortfall is
  vocal-specific rather than generic regression to the mean. Two readings were eliminated
  before a factor was added. It is **not a song-level label**: predicting a vocals rank
  from the *other* instruments' ranks of the same song reaches only rho **+0.219**, the
  lowest of the six against guitar's +0.623 — the rhythm section locks to a shared groove
  and predicts itself, a singer does not have to. And it is **not the "high AND held"
  interaction**: super-linear forms of sustained high time (weighted by the square, and by
  `2^(excess/6)`, of the register above G4) moved the top-end bias by under 1 rank, two of
  them the wrong way, and were beaten by their own controls.

  What was missing was simpler and had never been declared: `high_time_70`, the fraction of
  sung time above G4, is the **largest single discriminator of the charts ranked 400+**, at
  **+1.28 sd** above the rest of the corpus. The model knew how *high* a singer goes
  (`pitch_p90`, `notated_range`) and not how *long* they stay up there. It went untested
  because the tessitura family and `vocal_parts` only ever appeared in separate candidates —
  `primary+range+tess` drops parts, the selected `primary+range+parts` drops tessitura — so
  "both together" had no answer. With `pc_change_rate` beside it (`parts+tess+move`), vocals
  moved **86.81% -> 88.47% usable, rho +0.624 -> +0.684**, and the top-end bias from -117 to
  -104. All four pre-registered predictions held, including the one that mattered: **it still
  does not pass**, at a lower bound of 85.16% against the 90% floor and rho short of +0.70.

  The residual list is the sanity check — the worst misses are four Queen charts and two
  Iron Maiden, melismatic and wide-ranging rather than held-note ballads.
- **A mean-usable gate is structurally blind to rare patterns** — `deathontwolegs` is the
  case. Its keys chart is tame except for one solo changing notes **24.26×** faster than
  the rest of the chart; the next-highest `solo_change_ratio` in the corpus is 4.91, so it
  sits **15.3 sd out and is extreme on no other column**. Guitar's `full@attacks` carries
  `solo_frac_marked` *and* `solo_change_ratio`; the selected keys model carries neither,
  and the keys candidates that do were tested and lost (`primary+solo+entropy_rel` 90.75%
  against the selected 92.97%).

  That is not an oversight. **1 of 266 keys charts has the pattern.** A factor with one
  example to fit adds a column and no aggregate accuracy, so the protocol rejects it —
  correctly, on the evidence available. Solos are ordinary on guitar and the same factors
  earn their place there. The remedy is more concentrated-solo keys charts in the corpus,
  not a cleverer candidate; and note the shipped model still lands this chart's tier, by
  getting the average right rather than by seeing the solo.
- **Playing time barely matters, and "sparse charts are penalised" is measured and false.**
  A recurring hypothesis, worth recording so it is not re-proposed: `playing_s` carries
  **-0.81** rank per sd on keys and **-0.34** on drums, against +32 for the largest lever
  in the same model. Across its entire observed range it moves a suggestion by ~1 rank
  point, and the *sign is negative*, so a short chart already gets a tiny bonus. The corpus
  covers the sparse end well — keys `playing_s` spans **29-474 s**, and Harmonix rated
  `californication` (29 s of keys) Warmup 130 while `turningjapanese` (98 s) got
  Apprentice 178. A chart that scores low while playing little is being scored low for
  density, repetition and complexity, which happen to co-occur with playing little.
- **Other parts of the same song carry nothing usable (cross-instrument probe, 2026-08-17).**
  The last "nearly free" lead, and it is now closed. `run_cross_instrument_probe_offline.lua`
  adds a fixed set of columns measured on *another* part of the same song to the shipped
  model. Two vocabularies, each used identically across every pair so there is no per-pair
  search: **rhythm** (`attack_density_peak`, `total_changes`, `entropy_h2_rel`) and, after
  the first turned out to be near-duplicate on the keyboards, **geometry**
  (`chord_span_mean`, `move_mean`, `entropy_h2_rel`) — see finding 1. The fidelity gate
  reproduced all three published figures exactly, and the keyboard pair lost **zero** rows
  in both directions (266/266), so these are the same rows the protocol report describes.

  | target | source | columns | usable | gain | wins | selected? |
  |---|---|---|---:|---:|---:|---|
  | keys | Pro Keys | rhythm | 93.42% | **+0.45** | 70% | no |
  | Pro Keys | keys | rhythm | 88.83% | −0.56 | 10% | no |
  | vocals | guitar + drum | rhythm | 87.31% | −0.68 | 40% | no |
  | keys | Pro Keys | geometry | 93.20% | +0.23 | 50% | no |
  | Pro Keys | keys | geometry | 89.59% | +0.19 | 50% | no |

  **Nothing clears the bar** (1 point *and* more than 70% of paired repeats). Four findings:

  1. **The first vocabulary tested almost nothing on the keyboard pair, and only running it
     showed that.** Median ratio of the Pro Keys value to the 5-lane value over all 266
     songs carrying both: `total_changes` **1.00**, `attack_density_peak` **1.00**,
     `playing_s` 1.00, `density_peak` 1.01 — against `move_mean` **2.53** and
     `chord_span_mean` **3.19**. The 5-lane reduction preserves *when* the player plays,
     exactly, and compresses *where*. So two of the three original columns are the same
     number on both charts, and that pass could only ever measure duplicate-column noise.
     A second vocabulary (`CROSS_COLUMNS_GEOMETRY`) was declared from those measured
     ratios — the columns the reduction demonstrably discards — and run as an addendum.
  2. **The honest test is a firmer null than the accidental one.** Pitch geometry, the
     information the reduction actually loses, gains **+0.23** on keys and wins 50% of
     paired repeats — a coin flip — against the duplicate columns' +0.45. The columns that
     carry genuinely new information help *less* than the ones that carry none. This closes
     the keyboard lead properly rather than by accident.
  3. **The one number that looks like a win cannot ship, and the protocol declines it
     anyway.** `keys + Pro Keys rhythm columns` lifts keys' usable lower bound to
     **90.46%** — over the 90% floor keys has been failing, miss 1.29%, rho +0.881, so the
     *gate* passes. It was pre-committed as unshippable before its number was known,
     because RB3 requires PART KEYS for a Pro Keys chart but not the reverse: a keys model
     reading Pro Keys columns breaks for every project that has not authored Pro Keys yet.
     That pre-commitment was never actually tested, because the **selection rule refuses it
     independently** — +0.45 against a 1-point bar, winning exactly 70% against a rule
     needing more than 70%. Product judgment and statistical rule agree, which is worth
     more than either alone. Note also what it is *not* evidence of: Pro Keys columns alone
     reach 90.71% / rho +0.850 on the keys rank, but only because those three columns *are*
     the keys chart's own numbers. On geometry columns alone the same figure collapses to
     **64.74% / +0.483**. Nothing here says the reduction is redundant to the label.
  4. **Vocals cannot be reached from the band.** Guitar and drum columns alone predict a
     vocals rank at rho **+0.037** — indistinguishable from nothing, and below even the
     +0.219 their finished *ranks* manage. This sharpens the vocals thread from "missing a
     factor" to "missing a factor that is on the vocal chart": the band's density and
     entropy know nothing about how hard a song is to sing.

  If a Pro-Keys-aware **note** is ever wanted in the product, range and movement are the
  quantities to phrase it from — note count and strike rate are identical on the two charts
  and would state nothing.
- **The fit/grade mismatch is already spent. Stop looking for a better loss function.**
  The models are *fitted* by squared error on `rank` or `log(rank)` and *graded* on tier
  distance. `log(rank)` closed the scale half of that gap; three attempts at the loss half
  all failed, and the third explains the first two.
  - **A tier coordinate is worth nothing.** Built and verified: threshold *k* maps to
    exactly *k*, log-linear inside each band, so squared error in it *is* squared tier
    distance. There was real room — interior band widths in log space vary **1.25x** on
    guitar but **2.29x** on keys and 2.16x on drums, so `log(rank)` is measurably not
    already tier-uniform. Against each instrument's **own shipped scale** (keys and
    real_keys ship on `rank`, so `log(rank)` is the wrong baseline for them): guitar
    −0.06, bass +0.06, drum +0.27, keys +0.15, real_keys +0.04, vocals −0.18, with win
    shares 10–60% and rho moving ≤0.003 anywhere.
  - **De-shrinkage is worse, not better.** Squared-error regression compresses toward the
    mean by construction — `sd(pred)/sd(actual)` is guitar 0.88, bass 0.83, drum 0.91,
    keys 0.85, real_keys 0.83, **vocals 0.63** — and that compression *is* the mechanism
    behind every top-end bias here (vocals −125, everything else −34 to −50). Expanding
    predictions back out is worse on four of six and **monotonically worse on vocals**
    (88.4 → 87.2 → 86.3 → 86.0 at 1.15/1.30/1.50x). Amplifying a weakly-correlated
    prediction adds noise faster than it removes bias, so the instrument that looks most
    compressed is the one this helps least. It also cannot touch rho, being monotone.
  - **Why, and this is the part to keep: misses are model error, not near-misses.** For
    every cross-validated miss, the rank movement needed to become usable against the
    slack the *correct* rows have — guitar 7 vs 48, keys 17 vs 63, drum 18 vs 58, bass 24
    vs 49, vocals 26 vs 55, real_keys 28 vs 57 (medians). Wrong predictions need real
    movement and right ones sit two to seven times further from an edge. There is no
    reallocation available; a loss function can only trade near boundaries.
- **The equal-complexity tie-break can flip a release gate on noise. Read the gate on a
  configuration fixed in advance.** `SelectCandidate` prefers the better mean among
  candidates of equal complexity, with **no gain bar applied** — the bar only governs
  *bigger* models beating smaller ones. A scale change keeps the feature count, so it
  enters through that door: adopting the tier coordinate on keys moves its usable lower
  bound **89.94% → 90.11%**, i.e. from failing the 90% floor to passing it, on a
  difference worth **+0.15 points that wins 40% of paired repeats**. Nothing about that
  is a real improvement. The tie-break is correct as a way to avoid arbitrary choices
  (it was added because `log` sorted before `rank` alphabetically), but it was never
  meant to carry a ship/no-ship decision. Note the contrast with round 20, where the same
  door admits `@parts_step3` on vocals — harmless there, because vocals fails its gate
  either way and only the model's *claim* changes. Keys is 0.06 points from the floor and
  is the case where this matters.
- **The selected factors are collinear enough to matter downstream.** Not a modelling
  result — the ridge handles it — but the explanation UI shows the three *most unusual*
  measurements, and on 20% of corpus rows two of those were a correlated pair restating one
  observation. Worst offenders are per-instrument: `entropy_h2`/`entropy_h2_rel` **+0.96 on
  drums**, `notes_total`/`total_changes` **+0.94 drums but +0.80 guitar**,
  `complex_peak`/`density_peak` **+0.88 keys only**, `tight_p10`/`tight_med` **+0.45 drums
  to +0.75 vocals**. The exporter therefore ships a `corr` table per model. Any future
  consumer that ranks or groups factors needs the same treatment.

---

## Open threads

Where the three failing instruments actually stand, so this is not re-derived.

- **Keys' 0.06-point gap is an accuracy ceiling, not a sample-size shortfall.** Two
  collection attempts have now been made specifically to close it, and both failed the
  same way: the added charts raised `n` and lowered the mean by almost exactly the
  cancelling amount (89.95% at n=251 → **89.94%** at n=266). The second batch was drawn
  from tier 4 on purpose, the model's weakest bracket — adding tier-2 charts would have
  passed the gate and taught nothing. A third collection round is not the answer.
- **Vocals is missing a factor, not a corpus.** Its rank is the *most* chart-specific of
  the six — other instruments' ranks predict it at only **rho +0.219**, against guitar's
  +0.623 — so the signal is reachable in principle. Round 18 found part of it
  (`high_time_70`, tessitura) and the top-end bias only moved −117 → −104. What is ruled
  out: the "high AND held" interaction, in both quadratic and exponential form.
- **A "real singing difficulty" second score stays declined.** There is one label, so a
  second output could never be calibrated or falsified. Round 13 declined it on that
  ground and round 18 adds evidence: the realism-shaped proxies moved the official label
  almost not at all, while "high and *moving*" did.
- **The RBN packs buy validation, not training.** ~145 MIDIs in the hard-song set are
  `ugc_plus`, whose dta dialect `ParseSongsDta` does not read — so they are invisible
  rather than filtered, which is the worse failure mode. Worth fixing, but **every RBN
  rank is exactly a tier floor** (7 distinct values against the DLC's 139–166), so they
  are tier labels. That makes them a genuinely independent **held-out validation set** at
  the resolution the gate already measures, and useless as regression rows.
- ~~**Cross-instrument chart factors are untested and nearly free.**~~ **Tested and
  closed** — see "Other parts of the same song carry nothing usable" in the findings
  section above. Five pairs across two column vocabularies, none clearing the selection
  bar; the only one that helped enough to reach the gate is the one that cannot ship, and
  the protocol declines it independently. Do not re-propose without a new mechanism — and
  note that the mechanism most likely to be reached for first, "Pro Keys knows something
  the reduction lost", has now been measured directly and is the *weaker* of the two.
- **Vocals reaches the top tier by exactly one route, and it is fragile.** Harmonix puts
  48 vocal charts in tiers 5-6; the model puts **9**, and tier 6 exactly **once** in 328.
  The other three instruments manage ~70% of Harmonix's top-tier count (guitar 43 of 61,
  drums 38 of 54, keys 32 of 45), so this is not a property of linear models — guitar's
  top prediction is 605 against an official 600. The one vocal chart that gets there,
  `weirdscience`, does it on `octave_jump_rate` at **z +7.88** (worth +45 rank) plus
  `pc_change_rate` at +2.09 (+41). Its opposite, `somebodytolove2` (the corpus's hardest
  vocal chart at 495, predicted 321), is *below average* on travel and extreme on the
  sustain family instead — `high_hold_time_70` **+2.34**, `breath_load` +1.74,
  `longtime_frac` +1.32 — none of which is in the model, all of which lost selection in
  rounds 13 and 18. **The vocal vocabulary is rich for agility and nearly empty for
  sustained high singing**, and that is the sharpest statement of the vocal gap so far.

---

## Rounds 19-23a, and what they settled

All five were declared and decided on 2026-08-18. Two changed a shipped model.

| round | what | outcome |
|---|---|---|
| 19 | phrase pitch geometry (span, travel, per phrase) | best `+phrase_pitch` 88.48%, below the round-20 step. **Not selected.** |
| 20 | the harmony count as a step (`parts_3`) rather than a number | **SELECTED**, 88.35% → 88.63%, rho +0.668 → +0.674 |
| 21 | breath groups — passages with no gap long enough to inhale | best `+breath@mean50` **89.02%**, the highest vocal figure recorded. **Refused** at +0.40 / 80% against a >1.00 / >70% bar. |
| 22 | the three drum peak columns with roll-lane gems excluded | **SELECTED**, 93.38% → 94.37% lower bound, rho +0.888 → +0.894 |
| 23a | `complex_peak` re-tested against the now roll-aware drum model | **+0.00 points at 20% of repeats.** Not selected, and see below. |

The eighteen columns all stay in the CSV — measured, tested and cheap to carry — whether or
not they were selected.

### Round 23a: a factor that corrects for a confound is worth nothing once the confound is fixed at source

`complex_peak` is peak *(gems per window × conditional entropy of relative motion)* — the
measurement that says the same note count is harder spread across lanes than repeated on
one. It has been in the CSV since round 6 and no declared drum candidate carried it. Tested
once against the round-18 `full_drum` it gained **+0.24 points**, which read as "the idea is
right and the corpus does not care much".

That test was confounded. The old `density_peak` counted every gem under a roll lane, so a
single-lane roll drove it to an extreme while `complex_peak` correctly read the same passage
as low-complexity — `makemesmile2` sat at z **+7.24** on one and **+1.18** on the other. The
two columns were competing to describe the same artifact, so some of that +0.24 was
`complex_peak` partially undoing roll inflation.

Round 22 removed the inflation at source. Re-asked cleanly:

```
full_drum@noroll          (k=26)   96.46%   rho +0.894      <- incumbent, retained
full_drum@noroll+complex  (k=27)   96.46%   rho +0.896      paired +0.00%, 20% of repeats
full_drum@noroll@complex  (k=26)   96.34%   rho +0.894      paired -0.12%, 20% of repeats
```

**Exactly nothing.** The pre-registered prediction was that it would gain *more* than +0.24
now that the confound was gone; the opposite happened, and that is the finding: the roll fix
absorbed what `complex_peak` had been contributing. A factor whose value came from
compensating for a bad measurement has no value once the measurement is fixed.

The diagnostic recorded before the fit, per the round's own prediction 4: `complex_peak`
against `density_peak_noroll` on drum rows is **+0.747** Pearson (+0.722 Spearman), against
**+0.853** for the keys pair. Less redundant than keys, but still above the **0.70** line
this document uses elsewhere to call two factors one observation — consistent with the null.
Its standalone correlation with the drum rank is strong (**+0.801**), which is exactly why
standalone rho must not be read as evidence of fitted gain.

Costs nothing to re-open if the drum vocabulary changes again: it is column 70 and needs no
rescore. **Do not re-test it without a reason of that kind** — this was the clean ask.

### Round 21's refusal was substantively right, not merely conservative

This is the one worth keeping, because a +0.40 refusal normally reads as the bar being
pedantic. It was not. The breath columns were designed specifically to reach the
under-predicted hard charts, and **on those charts they do nothing**:

| chart | rank | `parts+tess+move` | `@step3` | `breath@mean50` |
|---|---:|---:|---:|---:|
| antsmarching | 441 | 192 | 200 | **192** |
| phantomoftheopera | 468 | 240 | 242 | **240** |
| flightoficarus | 442 | 262 | 264 | **259** |
| somebodytolove2 | 495 | 320 | 321 | **315** |
| dontstopmenow | 457 | 292 | 295 | **280** |

Same list, same order, and it pushes three of the hardest charts *down*. Its entire gain
comes from middling charts (`saturdaynightspecial`, `shadowoftheday`,
`whatdoesntkillyou2`). **Three mechanisms — phrase geometry, harmony shape, breath
grouping — now measure null on the same ten charts.** That closes the sustain thread with
evidence rather than exhaustion, and it re-confirms the pre-round-19 finding on real
REAPER-scored data: the misses are invisible to the model, not mis-weighted.

### Round 22's cost, and the general lesson in it

3 charts fixed, 2 broken. `makemesmile2` moved **550 → 362** (188 rank, two tiers out to
one) and `tearsdontfall` also cleared; `dreamonlive` and `wearethechampions2` broke.

**The two it broke have identical values on the twins and their originals** — neither has a
lane under its peak window, so nothing about their charts changed. What moved is the
column's *scale*: dropping the leniency passages cut `attack_density_peak`'s corpus sd by
**17.7%** and `hand_density_peak`'s by **16.5%**, because the excluded values were the
extreme outliers. Standardization is global, so every chart's z rose on those columns —
`dreamonlive`'s attack z went **+0.44 → +0.62** with its own chart untouched.

Excluding outliers from a standardized column never stays local to the outliers. The
measurement change was concentrated (6.1% of drum rows); the model effect was corpus-wide.

---

## Queued for the next full rescore

Adding or changing a scored column forces a full REAPER re-run of all 2101 rows
(`run_calibration_vkr.lua` refuses to resume on a column-set change). Nothing below is
worth triggering a rescore on its own; it is here so that whenever one happens for another
reason, it goes in too.

### Big Rock Endings are over-charted bonus material and are being counted

**The same class of error as the drum roll lane, and it lands on five instruments.** A BRE
is a free-play region: the notes exist so the characters animate, and the player may play
as much or as little as they like. Every gem inside one inflates density, attack rate, note
totals and playing time without asking anything of the player. Vocals is exempt by spec —
nothing may be authored during a BRE.

**Use `[coda]` in the EVENTS track, never the lanes.** The lanes are pitch 120-124, but on
drums that range is also the activation/fill lane. Measured over 394 corpus songs:

```
[coda] in EVENTS        :  18
120-124 lane present    : 392
both (a real BRE)       :  18
lane but NO coda        : 374   <- drum fills, not BREs
coda but no lane        :   0
```

Reading the lanes alone would strip material from **374 songs that have no BRE at all**.
The authoring doc's requirement holds perfectly in this corpus, so `[coda]` is exact.

**One coda per song, always — 0 of 18 have more than one.** So the implementation needs no
per-instrument lane parsing at all: find the single `[coda]`, cut everything after it. That
also sidesteps the drums 120-124 ambiguity entirely, because the lanes are never read.

**The cut also discards the required final hit, and that is fine.** The doc requires a hit
*after* the lanes end, so a coda cutoff eats it — measured at a median of 1-3 gems per
instrument and a maximum of 9, against chart totals of 1000-2600. In practice a short roll,
a crash, or a few chords. A deliberate approximation, recorded here so it is not later
mistaken for an oversight.

Where a BRE exists it is worth 3-4% of gems on average, up to **16.2%** (`2112pt3` bass,
149 of 918 over 17.4s). `dreamonlive` — the chart whose regression in round 22 prompted
this — carries 84 drum gems across 10.7s, 8.3% of the chart.

**The LOCAL direction is a coin flip:**

```
over-predicted   38 rows, mean error +38   -> exclusion helps
under-predicted  40 rows, mean error -47   -> exclusion hurts
```

and the losing half loses harder. The charts most at risk are already badly under-read:
`rizeofthefenix` drum **-157**, `2112pt3` drum **-129**, `starshiptrooper` keys **-125**,
`flightoficarus` drum **-123**. Stripping 3-16% of their gems pushes them further down.

**But that check cannot answer the question, and an earlier version of this section wrongly
concluded from it that the round was not worth running.** It measures where the 18 BRE
charts currently sit and infers the sign of a *local* effect. Round 22 proved that is the
smaller half: its two regressions, `dreamonlive` and `wearethechampions2`, had
**byte-identical measurements** before and after, and broke only because removing the
outliers cut the column's corpus sd by 17.7% and re-scaled every chart's z. **Excluding an
outlier from a standardized column moves the 376 songs that do not have one.**

So the honest position is that the corpus-wide effect is *unmeasured*, the mechanism that
dominated round 22 is present here too, and 18 songs' worth of extreme values is enough to
move an sd. The round is worth running; a prediction from the local signs is not a
substitute for running it. The one thing the local check does establish is that this is not
the same easy win as the roll lanes - there is no concentrated set of obviously-wrong
predictions waiting to be fixed, so expect the gain to come from re-scaling rather than
from the BRE charts themselves, and declare it that way.

A Stage A offline preview is possible and cheap: the cutoff is a **tick** (the `[coda]`
position), so the exclusion itself is exact offline. The resulting density values depend on
the tempo map, so the preview may differ from REAPER in the last decimals and **must never
be merged into the REAPER-scored CSV** - name it `_2N_*` per the usual rule.

**The product argument is separate and the corpus cannot see it.** An author who writes a
BRE and gets a rank inflated by their own bonus section is being handed a wrong answer,
whether or not fixing it moves a corpus statistic. Unlike the harmony-mirroring case this
is not a judgement call — a BRE is a documented, unambiguous free-play region. So the
recommendation is: fold it in when a rescore happens anyway, not before.

**`playing_s` is the subtler half and the round must declare it.** BRE time currently
counts as playing time. Removing the gems but not the time lowers every density twice over;
removing both is the honest treatment, but `playing_s` carries a positive coefficient in
five of six models, so the two effects partly cancel. Declare it as one substitution, not
two.

Implementation cost, once a rescore is happening anyway: one EVENTS text scan and one time
cutoff in `difficulty_read.lua`, which does not parse the EVENTS track today.

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
