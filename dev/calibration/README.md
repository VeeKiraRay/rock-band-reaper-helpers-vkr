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

Figures refreshed 2026-08-22 after the ridge-validation fix below. Guitar and drum moved a
tenth of a point in opposite directions; no selection and no verdict changed.

| instrument | selected candidate | scale | k | usable | usable lower bound | miss upper bound | rho | rho lower bound | |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| guitar | `full@attacks` | log(rank) | 21 | 94.22% | **91.71%** | 1.36% | +0.862 | **+0.830** | **passes** |
| bass | `baseline+entropy` | log(rank) | 3 | 94.18% | **91.68%** | 1.35% | +0.802 | **+0.746** | **passes** |
| drum | `full_drum@noroll` | log(rank) | 26 | 96.34% | **94.22%** | 1.35% | +0.894 | **+0.869** | **passes** |
| keys | `primary+ent_rel+complex@attacks-chord` | rank | 7 | 92.97% | 89.94% | 1.08% | +0.878 | +0.837 | fails by 0.06 |
| real_keys | `primary+ent_rel@attacks` | rank | 7 | 89.40% | 85.89% | 2.02% | +0.861 | +0.824 | fails |
| vocals | `parts+tess+move@parts_step3` | log(rank) | 12 | 88.63% | 85.42% | 4.28% | +0.674 | +0.606 | fails |

Rounds 19-22 changed two of the six. Drums took the roll-lane peak twins (+0.99 on the
lower bound) and vocals took the harmony count as a step instead of a number (+0.30).
Guitar, bass, keys and Pro Keys are unchanged **to the decimal**, which is what confirms
the eighteen new columns did not leak into the four instruments they were not for.

"usable" is within-one-tier accuracy, averaged across repeats. **Every bound in that table
is the pessimistic end of an interval, and all of them are what the gate reads** (floors:
usable >= 90%, miss <= 5%, rho >= 0.70, **endpoint band >= 80%** as of 2026-08-22 — see
"The gate gained an extremes bar" below; vocals and Pro Keys now fail on it too). The usable and miss bounds are Wilson; **rho's is
the pack bootstrap's 5th percentile, adopted 2026-08-22** — until then rho was gated on its
mean, which was the last asymmetry in the gate. It changed no verdict: all three passing
instruments clear 0.70 on the bound as they did on the mean. Keys and Pro Keys fail on the
usable lower bound alone; vocals fails that and rho.

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
would have passed the gate and taught nothing.

> *Corrected 2026-08-21.* This paragraph used to end "read this as evidence that keys has
> a real accuracy ceiling rather than a sample-size shortfall", and the peer review was
> right that the claim outruns the evidence. What two collection rounds established is
> that a **pooled, adversarially curated** bound did not move. That is not an intrinsic
> ceiling, and it cannot separate model limitation from label noise or from a changed tier
> mixture. Measured since: **keys' corpus is about 48% endpoint tiers**, and under equal
> weight per tier keys reads **91.52%** against guitar's **90.78%** - i.e. better than the
> instrument that passes. Its pooled shortfall is substantially a consequence of having
> been enriched precisely where every model is weakest. See "What the number estimates".

### What the number estimates

Declared 2026-08-21, because the peer review showed the question had never been answered
and the answer changes which instruments pass.

**The pooled figure is what a deliberately adversarial sample gets. It is not what a
random song gets, and nothing here may describe it that way.** The corpus was enriched
three times on purpose - low end, top end, then keys' weak tier 4 - so it is excellent
stress testing and is not a probability sample of the catalogue.

The report now prints three numbers per instrument, from the same cross-validated
predictions:

| instrument | pooled | macro (equal tier) | endpoints (0-1, 5-6) |
|---|---:|---:|---:|
| guitar | 94.50% | 90.78% | 86.73% |
| bass | 94.24% | **89.38%** | 92.86% |
| drum | 96.34% | 90.59% | 90.00% |
| keys | 93.23% | **91.52%** | 87.60% |
| real_keys | 89.47% | 88.74% | 82.58% |
| vocals | 89.02% | 81.13% | **64.00%** |

Macro is lower on **all six**, by 0.73 to 7.89 points, and it inverts two verdicts: bass
falls below a 90% floor while keys rises above it. The mechanism is uniform - signed tier
bias is positive at the bottom and negative at the top on every instrument - and pooled
hides it because the middle tiers run at 96-100% and hold most of the rows. Vocals is the
extreme case: 20 charts are officially tier 6 and the model puts **one** there.

**The gate still reads pooled, and that is an interim decision rather than a claim that
pooled is the right quantity.** Macro is the **pre-registered** successor, declared before
the corpus changes so that adopting it later cannot be a reaction to where the numbers
land. Two things have to happen first: measurement across at least one corpus change, and
a floor derived for the macro scale instead of inheriting 90%, which was calibrated
against a different quantity.

**A macro floor cannot be computed with the machinery the gate uses, and that reorders the
plan.** The gate reads a **Wilson lower bound**, which is a binomial interval on a
proportion over *n* rows. Macro is not that — it is the mean of seven proportions with
denominators from 2 to 102, and it has no closed-form interval. So `macro_lower >= X` does
not exist until the pack bootstrap does. **The macro floor is downstream of phase 4, not
an independent decision.**

**Which makes the endpoint band the better gate input, and macro the better reporting
one.** The endpoint rate is a genuine proportion over 75–140 rows, so Wilson applies with
the code already here; it targets the same blindness (endpoint failure hiding behind a
middle-heavy pool); and it avoids macro's weighting pathology, where **bass's 4-song tier 6
carries the same weight as its 89-song tier 1** and one song flipping moves the headline
3.6 points. Macro keeps its own job — the fixed 3/7 baseline is what makes scores
comparable between instruments, and pooled never can be.

> **This paragraph was briefly retracted on 2026-08-22 and the retraction was wrong.** A
> first version of the pack bootstrap reported an endpoint design effect of 1.55–2.42 and
> I concluded Wilson was badly optimistic there. That figure was a **bug in
> `PackBootstrap`** — the endpoint design effect was computed against the whole corpus row
> count instead of the band's own 75–140 rows, inflating the ratio by about 1.6×. The true
> value is **1.00–1.16**, so the "Wilson applies here" reasoning above **stands**.
>
> The gate reads the bootstrap p05 for this band anyway, because it assumes nothing and
> the two bounds agree — preference, not necessity. Effective n (56–138) was correct
> throughout; it does not depend on the denominator.

One caution for whoever sets the number: the macro figures are now published above, so any
floor chosen from here is chosen in their presence. Pick it from a principle stated
independently of them — "the 90% promise should hold in every band rather than on average"
is such a principle — and record that the numbers were visible when it was set.

**Moving the gate to macro would reopen the selection, on the three instruments that
currently pass.** `SelectCandidate` ranks by *pooled* usable%, so a macro gate would be
grading on a quantity the selection never read - the fit/grade mismatch this project
already has a finding about, reintroduced through the back door. Macro is therefore
measured for **every** declared candidate, and the report names both leaders:

| instrument | pooled leader | macro leader | macro gain |
|---|---|---|---:|
| guitar | `full@attacks` / log(rank) | `full@attacks` / **rank** | +0.97 |
| bass | `primary+entropy@attacks` / log(rank) | `baseline+ent_rel@attacks` / rank | +0.11 |
| drum | `full_drum@noroll` / log(rank) | `full_drum@noroll` / **rank** | +1.56 |
| keys | `r16+chord_change` / rank | same | — |
| real_keys | `primary+ent_rel+fingers` / rank | same | — |
| vocals | `parts+tess+move+breath@mean50` / log(rank) | same | — |

On guitar and drums it is the **same feature set on a different scale**, and the direction
is mechanistically expected rather than noise: `log(rank)` buys proportional accuracy by
compressing the top end, which pooled barely notices and macro weights heavily. Note that
this enters through the equal-complexity tie-break, which a finding below already warns can
flip a release gate on noise - drums' +1.56 clears a 1-point bar, guitar's +0.97 does not.

Two things this table is **not**. These are *leaders*, not what `SelectCandidate` would
choose: the simplicity rule and the 1-point/70% bar sit between the two, and on bass the
pooled leader is not even the selected model. And nothing here is a reason to adopt macro -
see `MacroUsable` in `protocol.lua` on why adopting it because of which candidate it
favours would be precisely the forbidden move.

**Run the actual rule against paired macro differences and only DRUMS reselects.** Measured
2026-08-21, which corrects the impression the table above gives:

| instrument | best macro alternative | macro gain | win share | clears the bar? |
|---|---|---:|---:|---|
| guitar | `full@attacks` / rank | +0.98 | 60% | no, fails both |
| bass | `baseline+ent_rel@attacks` / rank | +0.74 | 60% | no, fails both |
| drum | `full_drum@noroll` / **rank** | **+1.56** | **90%** | **yes** |

And the bar itself degrades unevenly. Median sd of the **paired** difference, with what one
percentage point is worth in it:

| instrument | pooled sd | macro sd | 1 pt on pooled | 1 pt on macro |
|---|---:|---:|---:|---:|
| guitar | 0.790 | 1.608 | 1.3 sd | **0.6 sd** |
| bass | 0.433 | 1.679 | 2.3 sd | **0.6 sd** |
| drum | 0.646 | 1.829 | 1.5 sd | **0.5 sd** |
| vocals | 0.558 | 0.846 | 1.8 sd | 1.2 sd |
| keys | 0.663 | 0.808 | 1.5 sd | 1.2 sd |
| real_keys | 0.600 | 0.728 | 1.7 sd | 1.4 sd |

On exactly the three instruments where the leaders disagree, a 1-point macro difference is
half a standard deviation. **The point half of the selection rule stops discriminating on
macro; the win-share half is scale-free and still does** — which is why drums' result
survives at 90% of repeats despite +1.56 being only 1.1 sd. Any move to macro has to
re-derive the point bar or drop it, never carry 1.00 across unchanged.

**Pairing helps less than it looks like it should**, and that was a wrong prediction worth
recording. Paired differences are *larger* than marginal spread, not smaller: guitar's
marginal macro sd is 1.413 against a paired 1.608, and pooled goes 0.683 → 0.790 the same
way. Two candidates on identical folds correlate at only about r = 0.5 here, and paired sd
is `s·sqrt(2−2r)`, so anything below r = 0.5 makes the difference noisier than either
candidate alone. Pairing removes the fold's shared component and nothing else.

**The compositional trap these exist to catch.** Adding middle-tier songs raises pooled
without improving the model at all, because the middle is where it already succeeds. Macro
and the endpoint rate are tier-weighted and nearly invariant to that. So if a rescore moves
pooled and leaves macro flat, the movement is **compositional, not an improvement**. Read
them together or not at all.

The report also prints two **naive baselines** on the same folds - modal tier and median
rank, both fitted out of fold. "94% within one tier" is not interpretable without knowing
what constant guessing scores on a middle-heavy corpus.

**The baselines produced the strongest argument for macro, and it was not anticipated.**
Under macro a constant predictor scores exactly **3/7 = 42.86%** for every instrument and
every corpus - one guessed tier is within one of exactly three of the seven bands, which
is arithmetic rather than a measurement. Under pooled the same baseline ranges from
**45.86%** (real_keys) to **77.13%** (vocals), depending only on how middle-heavy that
instrument's corpus is.

So pooled scores are **not comparable between instruments**. Vocals' 89.02% sits against a
77.13% baseline; real_keys' 89.47% sits against 45.86%. The same headline hides a fourfold
difference in what was actually achieved:

| instrument | vs better baseline, pooled | vs better baseline, macro |
|---|---:|---:|
| guitar | +29.05 | +47.92 |
| bass | +19.70 | +46.53 |
| drum | +23.78 | +47.73 |
| keys | +41.73 | +48.66 |
| real_keys | +39.10 | +45.88 |
| vocals | **+11.89** | +38.27 |

Vocals is the one to sit with: on the metric the gate actually reads, it beats guessing
the modal tier by under twelve points. Keys and Pro Keys, which fail the gate, add the
*most* over baseline of any instrument - because their corpora are the least middle-heavy,
which is the same enrichment that depresses their pooled figures.

**Two things this table is not.**

1. These are **development-set repeated-CV** figures — but as of 2026-08-23 they are no
   longer the only evidence. The reserved partition was spent and graded once; guitar,
   bass and drum passed **out of sample**, which is what restored the word "validated" to
   those three. See "The reserved partition, spent" below. Keys, Pro Keys and vocals
   remain development-gate figures with a failing verdict on both sets.
2. A failing instrument is not a broken one. Keys misses by **0.06 points** at n=266 with
   the best rho of any instrument (+0.878) - a statement about certifying a 90% floor,
   not a claim that the model got worse. It does **not** follow that a few more charts
   would clear it: two collection rounds have now tried exactly that and both cancelled
   out. See "Why three instruments still fail".

The reserved partition should be drawn **by whole pack**, not by random rows: the corpus's
multi-song packs are thematic, so related songs would otherwise leak across the split, and
a pack-level split doubles as the domain-shift check.

**And it cannot be drawn from these rows at all.** The 2026-08-21 peer review sharpened
this point past what the paragraph above says: the problem is not merely that a partition
has not been drawn, it is that every rb3_dlc row is **already spent**. Across 23 rounds
they informed worst-residual inspection, factor design, scale choices and candidate
selection, so no current row can supply confirmatory evidence however it is later
relabelled. Choosing some of them as a "test set" now would produce a number that looks
confirmatory and is not.

The partition therefore has to come from packs that have never been walked, and the rule
deciding which ones is committed in `protocol.lua` (`PARTITION`, `PackIsReserved`) as of
2026-08-21 — **before a single eligible pack exists**, which is the only time such a rule
can be fixed without being a decision about data already seen. Read its header before
touching it: a pack already in `corpus_scores.csv` is development permanently, whatever
its hash says.

**Every unwalked pack is reserved.** `RESERVED_PCT` was 20 when the rule was first
committed and is now 100, changed the same day and recorded in the rule's own header as it
requires. The reason is arithmetic rather than preference. About 600–700 rb3_dlc songs are
available against the 330 walked; to certify the 90% floor the Wilson lower bound must
clear 90%, which at an observed 94% needs n ≈ 200. Twenty per cent of ~300 new songs is
n ≈ 60, whose lower bound at 94% is **86.8%** — a partition that can falsify a collapse and
can never confirm the gate, which is its only job.

Raising the share after seeing the batch is not the move the pre-commitment forbids:
reserving more data shrinks training *and* enlarges the sample that could contradict the
published figures, so there is no version of it that flatters the model. Lowering it would
be the forbidden direction.

Two things to hold onto when the partition is spent. The new material is **mostly middle**
— the extremes are exhausted — so grading it on pooled would flatter, for the same reason
the middle tiers already run at 96–100%; grade it on macro or report all three. And once
it is spent, "everything unwalked is reserved" stops being the right policy, and the
replacement is a new declaration with its own reasoning.

### The reserved partition, spent

**2026-08-23. The one number this whole apparatus was built to produce.**

258 rb3_dlc songs from packs that had never been walked — held out by construction since
the assignment rule was committed *before a single eligible pack existed* — were scored
under origin `rb3_dlc_test` and graded **once**, with the shipped models applied unchanged
through the shipped predictor. Nothing was refitted.

| instrument | n | pooled | **Wilson lower** | miss upper | endpoints | rho | |
|---|---:|---:|---:|---:|---:|---:|---|
| guitar | 257 | 96.50% | **94.08%** | 1.73% | 87.88% | +0.765 | **passes** |
| bass | 257 | 93.77% | **90.81%** | 1.04% | 92.31% | +0.726 | **passes** |
| drum | 257 | 97.67% | **95.55%** | 1.04% | 87.50% | +0.867 | **passes** |
| keys | 159 | 85.53% | 80.35% | 2.77% | 78.72% | +0.756 | fails |
| real_keys | 159 | 88.68% | 83.88% | 4.63% | 78.43% | +0.802 | fails |
| vocals | 258 | 88.76% | 85.11% | 3.41% | **48.39%** | +0.529 | fails |

**Guitar, bass and drums clear the 90% floor on charts nothing in this project had ever
seen.** That is the first non-circular evidence here, and it is why those three carry
`validated` again — the word was stripped on 2026-08-21 precisely because it rested on
development-set CV, and the note left behind said restoring it needed "genuinely new
pack-held-out data evaluated once". This is that.

**The verdict set is identical to the development gate's**, which is nearly as valuable as
the pass itself: the gate was predicting honestly rather than flattering the rows it was
built on. Guitar and drum scored *higher* out of sample than in CV.

#### Four things this does not say

**Two of the gate's four inputs could not be applied.** rho's bootstrap p05 and the
endpoint p05 both resample out-of-fold residuals, which rows that were never in a fold do
not have. Pooled and miss are genuine confirmatory bounds; rho and endpoints are point
estimates. Bass's rho of +0.726 sits close enough to the 0.70 floor that a bound could dip
under it.

**Keys degraded materially**: 92.97% → 85.53% pooled, a 7.4-point drop well outside
anything CV showed. It was the "fails by 0.06" instrument; out of sample it is not close.
That deserves understanding rather than filing away.

**rho fell on every instrument** (−0.03 to −0.15), and this is largely expected rather than
alarming. The development corpus was deliberately enriched at the extremes; this partition
is mostly middle, as predicted. Narrower range attenuates correlation — the same
range-restriction effect that limited the human rating study. Not a like-for-like number.

**Vocals' endpoint band collapsed to 48.39%** from 64.00%, confirming out of sample what
the per-tier reliability note already tells authors: the model cannot reach the top of the
vocal scale.

#### It cannot be done again, and that is stronger than it sounds

The partition is spent — and **the rb3_dlc population is exhausted**. All 588 songs are in
the corpus, 330 development and 258 test, with nothing behind them. `RESERVED_PCT` at 100
has nothing left to reserve because there is nothing left at all.

**So `validated` is a terminal state, not a refreshable one.** Any future change to guitar,
bass or drums makes the figures above describe the *old* models, and those three drop back
to `beta` **with no route back on this population**. Not "until more data is collected" —
there is no more comparable data. Price that in before touching a coefficient: a refit that
buys half a point of development accuracy costs the only confirmatory evidence the project
has.

Two routes remain and **both change the estimand**, so neither is topping up this test:

- **On-disc RB3** (~83 songs). Same game, same rank scale, the closest thing available. But
  they were ranked at launch, before the DLC calibration settled, and the label probe
  already notes keys and Pro Keys had no prior calibration in RB3. A pass there answers
  *"does this generalise to on-disc RB3"* — a different, arguably harder question than
  *"does it generalise to unseen DLC"*. Legitimate if declared as its own experiment.
- **Pre-RB3 songs cannot validate at all** in the current framing. Lego and RB2 carry origin
  indicator columns and train at 0.30 precisely because their ranks sit on another scale.
  Predicting them with the indicators at zero and grading against native ranks measures that
  offset, not the model.

Either route needs its rule declared **before the songs are in hand**, for the same reason
`PackIsReserved` was committed before a single eligible pack existed: once you have seen the
data, any rule you write is a choice about it, and git's history of the file is the only
evidence of when it was fixed.

Integrity checks that had to hold, and did: the artifact regenerated **byte-identical**
apart from the three `status` fields; every pre-existing CSV row is byte-identical with
1,347 added, 0 changed, 0 lost; `FROZEN_DEVELOPMENT_SET.txt` still reads 394 development /
258 reserved, so the test rows were not swept into training.

Grade with `dev/calibration/evaluate_reserved_partition.lua`. **Do not tune against it.**

### The per-tier reliability note — the first user-visible result

Shipped 2026-08-22. Every earlier phase improved how the project *measures itself*; this is
the first that changes what an author sees. Artifact schema 5 adds `reliability`, carried
from the manifest (it comes from out-of-fold predictions, and the exporter refits on every
row, so it cannot honestly recompute it).

**It reads the opposite conditional from the calibration report, and that is the whole
point.** `TierDiagnostics` conditions on the *official* tier — "of charts really at tier 6,
how many did the model place within one?" — which is what shows a calibrator the model
compresses. An author holds a *predicted* tier and needs "how much should I trust this?"

The two answers differ enormously. On vocals the official-tier view says tier 6 scores
**20%**; the predicted-tier view runs **80–94%** at every tier with a usable sample. Both
are true: the model hedges to the middle, so what it says is usually near-right — it just
almost never commits to an extreme. A note built on the official-tier figure would frighten
authors about predictions that are sound, and miss the thing they cannot see.

Two rules, both statable rather than fitted:

- **Miss direction** — when more than **one in ten** charts at the same predicted tier were
  officially *two or more* tiers away, name the dominant direction. Two-or-more because one
  tier out is what the suggestion is calibrated to allow. Requires ≥ 15 reference charts at
  that tier; below that, one in ten is one chart.
- **Reach** — when the model places charts in the top band less than **half** as often as
  charts actually occupy it, and the chart landed at tier 4+.

**Firing rate: 7 of 42 instrument-tier cells** — drums at Apprentice, keys at Challenging,
Pro Keys at Moderate and Challenging, vocals at Challenging, Nightmare and Impossible.
Guitar and bass never fire. That selectivity is deliberate: a note on every card trains the
eye to skip the area where chart-specific warnings live, which is why model *maturity*
stays on the badge tooltip instead. The thresholds were checked against the firing pattern
to confirm they are selective; they were not chosen from it.

Vocals is the motivating case and now says so out loud:

> This model rarely rates vocals at the top of the scale: 48 reference charts are officially
> in the highest two tiers and it placed 11 there. A genuinely top-end chart is likely to be
> rated below its real difficulty.

The closing sentence flips for a chart already rated tier 5–6 ("a rating this high is
unusual from it"), because telling an author rated Impossible that top charts get under-rated
does not follow.

### The gate gained an extremes bar

Decided 2026-08-22, closing most of finding 2's divergence. `GateVerdict` now has a fourth
input: the **endpoint band** (tiers 0–1 and 5–6 pooled) against its pack-bootstrap p05,
floor **80%**. It is the first gate input that can fail an instrument for being *uneven*
rather than *inaccurate*.

**Why the endpoint band and not macro**, which was the pre-registered successor. Read at
its lower bound — how every other gate input is read — **a 90% macro floor fails all six
instruments**, the best being keys at 88.38. That is not the model being bad: macro is a
mean of seven proportions, some over 2–4 songs, so its interval is wide (sd 2.0–4.4 against
pooled's 1.0–2.1), and certifying evenness at 90% needs a large sample *in every tier*,
which this corpus does not have.

The older expectation — "bass stops passing, keys starts" — is what happens if macro is
compared as a **point estimate** against 90%. That isn't how this gate works, and adopting
a point comparison would have abandoned read-the-pessimistic-end one commit after applying
it to rho.

Bass is a second reason to keep macro out: its macro p05 of 79.19 is driven by the 4.7% of
resamples that lose a tier and average over six bands. That's an artefact of sparse tiers,
not a measurement of bass.

**Where 80% comes from:** a promise stated independently of the figures — the product
promises roughly 90% within one tier, and the extremes are accepted as harder, *but not
more than ten points harder*.

**What's uncomfortable about it**, recorded rather than glossed: 80% lands exactly where
the three passing instruments sit (guitar 83.17, bass 89.03, drum 84.34). The floor was
chosen with those numbers visible, and nothing here proves the principle wasn't fitted to
them afterwards. What *can* be said is the direction — this **adds** a requirement and
removes none, so it can only make the gate harder to pass. The verdict set is unchanged
because the passers already cleared it, not because the bar was placed to spare them.

**A known wart.** The gate now mixes two views: usable% and miss% come from per-repeat
means (tier-then-average), the endpoint bound from the bootstrap over averaged residuals
(average-then-tier). They differ by a few tenths. Keeping usable% on its historical Wilson
bound was deliberate — every published figure and past verdict rests on it — but a future
tidy-up should put all four on one view and re-derive the floors, as a declared experiment.

Still **not** gated: macro, per-tier accuracy, signed bias, "no severe per-tier failure".
The divergence is narrowed, not closed.

### Clamp bounds and rho's input

Peer review finding 8e, fixed 2026-08-22 — two defects, two switches, so each half's cost
is separately attributable.

**`CLAMP_BOUNDS = 'per_fold'`.** Bounds were computed once over *all* target rows, so a
validation song's own rank helped set the range its own prediction was clamped into. They
now come from each fold's training rows only.

**`RHO_ON = 'raw'`.** rho was graded on clamped predictions; clamping ties the extremes and
Spearman with ties is a different statistic. The product should clamp — rank 943 on a 1–501
scale is nonsense — the evaluation should not. This matters more since rho's bootstrap p05
became a gate input.

All four arms came out identical on pooled, macro, every selection and every ridge
histogram. So a **direct count** was run instead, because "no change in the headline" and
"the code does nothing" are different claims:

| instrument | preds | bounds | binds, whole-corpus | binds, per-fold | rho clamped → raw |
|---|---:|---:|---:|---:|---:|
| guitar | 3270 | 75–605 | 28 (0.86%) | 32 (+4) | +0.000007 |
| bass | 3300 | 89–480 | 33 (1.00%) | 36 (+3) | −0.000015 |
| drum | 3280 | 93–550 | 21 (0.64%) | 33 (+12) | −0.000000 |
| vocals | 3280 | 112–495 | 13 (0.40%) | 14 (+1) | −0.000000 |
| keys | 2660 | 90–495 | 56 (2.11%) | 56 (0) | −0.000012 |
| real_keys | 2660 | 80–505 | 62 (2.33%) | 62 (0) | −0.000025 |

**The clamp does bind** — 0.4% to 2.3% of predictions, not the "never" this project used to
assume. And the pre-registered mechanism is confirmed: per-fold bounds are tighter, so they
bind **more often**, on four of six instruments.

**The gate's numbers did not move at all**, because in the per-repeat view every clamp is
within-tier: the bounds are the extreme observed ranks, so a prediction just outside them
was already in that extreme tier.

**One tier did move, in the averaged view.** `CandidateResiduals` now clamps per fold
*before* averaging, so a prediction repeatedly clamped to a tighter ceiling averages lower.
Three guitar residuals shifted and one crossed out of predicted tier 6 into tier 5. Per-tier
usable is unchanged, so pooled, macro and the endpoint band are unchanged; tier 5's signed
bias moved −0.67 → −0.71. The pre-registered tier-crossing risk therefore **did** appear —
at the top end, where the ceiling binds, having been predicted at the bottom. Half right.

rho moved by −0.000045 to +0.000007, independently reproducing the review's −0.000006 to
+0.000025 and widening it slightly. Six orders of magnitude below the 0.70 floor.

### The ridge search now honours the origin policy

Peer review finding 6, fixed 2026-08-22. Auxiliary rows train at weight 0.30, but the
nested ridge search accumulated `err + |e|` and `cnt + 1` over its inner holdouts,
ignoring the weight array beside it. So in the one decision that sets regularisation
strength, an auxiliary row counted as much as an RB3 target row — about **18.5% of the
vote** instead of the ~6.4% the 0.30 policy implies, or the 0% that matches how the model
is graded.

`PROTOCOL.RIDGE_VALIDATION` selects the policy, and `InnerScoreWeight` is **global and
called from both** `protocol.lua` and `export_production_models.lua` — the finding is
fundamentally that two copies of the same search disagreed, so one shared function is what
stops them drifting again.

**`target_only` is shipped**: aux rows train and are never scored. Chosen because it
matches the estimand — the outer CV grades target rows only, so the inner search should
minimise error on target rows only. **Not chosen because it scored best.** With six grid
values across four instruments something wins on noise every time, and picking by score is
the selection inflation the protocol exists to prevent.

Measured against the defect, paired by repeat:

| instrument | weighted (pooled / macro) | target_only (pooled / macro) | reselect? |
|---|---:|---:|---|
| guitar | +0.00 / +0.17 | +0.06 / +0.41 | no |
| bass | +0.00 / +0.00 | +0.00 / +0.00 | no |
| drum | +0.00 / +0.00 | −0.12 / −0.31 | no |
| vocals | +0.09 / +0.02 | +0.00 / −0.20 | no |
| keys, real_keys | identical | identical | no aux rows exist |

Keys and Pro Keys are a **free control** — neither Lego Rock Band nor the RB2 export has a
keyboard part, so they have no auxiliary rows and must not move. They don't, right down to
their ridge histograms.

**The result is in the ridge histogram, not the accuracy.** Guitar under the defect picked
ridge 0.1 on 35 of 50 fold-repeats; under `target_only` that falls to 24, with weight
shifting to weaker values. Vocals goes the other way (32 → 44). Drum starts picking 1.0.
So the auxiliary rows genuinely **were** steering regularisation — and the model is simply
insensitive to ridge across that range. "No measurable cost" is the finding; "no effect"
would be the wrong reading.

**It did change the shipped artifact**: vocals' production ridge moved 0.01 → 0.1 and its
14 coefficients with it. No verdict changed anywhere — guitar's usable lower bound went
91.64 → 91.71 and drum's 94.37 → 94.22, both still passing; vocals fails either way.

A directional guess was pre-registered (`target_only ≥ weighted ≥ unweighted`) and is **not
supported** — two of the four instruments with aux rows moved each way, all inside noise.

### The pack bootstrap

Built 2026-08-22. It answers two questions the Wilson bound cannot: what interval belongs
to **macro** and **rho**, and whether Wilson itself is honest on rows that come in packs.

It resamples **packs** with replacement (B = 2000) from the out-of-fold residual rows and
recomputes every metric. What it does **not** do is refit the model inside the loop — that
is 2000× a four-minute run. So this is an interval for *"what would this measured accuracy
be on a different sample of packs"*, which is the question a release floor asks, and it is
**not** an interval for *"what if the model had been refitted and reselected"*. Never quote
it as the second.

It bounds the **averaged-prediction** figures from the per-tier block, which sit a few
tenths from the per-repeat means the gate quotes (tier-then-average is not
average-then-tier). The report prints both and names which is which.

| instrument | pooled | design | endpoints | design | effective n | rho | rho p05 |
|---|---:|---:|---:|---:|---:|---:|---:|
| guitar | 95.11 | 1.05 | 88.50 | 1.00 | 112 / 113 | 0.865 | 0.830 |
| bass | 94.24 | 0.95 | 92.86 | 1.01 | 138 / 140 | 0.802 | 0.746 |
| drum | 96.34 | 1.00 | 90.00 | 1.01 | 88 / 90 | 0.895 | 0.869 |
| vocals | 89.02 | 1.22 | 64.00 | 1.16 | 56 / 75 | 0.676 | 0.606 |
| keys | 93.23 | 1.18 | 87.60 | 1.13 | 101 / 129 | 0.877 | 0.837 |
| real_keys | 89.47 | 1.11 | 82.58 | 1.12 | 106 / 132 | 0.862 | 0.824 |

> **Design-effect figures corrected 2026-08-22.** The endpoint column first read 1.55–2.42
> because `PackBootstrap` divided by the whole corpus row count instead of the endpoint
> band's own — inflating the ratio by roughly 1.6×. Effective n was right all along (it
> reduces to `p(1-p)/sd²`, independent of the denominator); the ratio and the conclusion
> drawn from it were not.

**Wilson is fine on pooled** (design 0.95–1.22) **and on the endpoint band** (1.00–1.16).
Clustering costs these proportions almost nothing, because packs mix easy and hard songs —
a pack is not much more correlated internally than the corpus is overall. Worth checking
rather than assuming, and it came out in the gate's favour on both counts.

The gate reads the **bootstrap** p05 for the endpoint band regardless, because it assumes
nothing about independence and the two bounds agree anyway.

**Rho now has a lower bound, and the gate reads it as of 2026-08-22.** It used to read
rho's *mean* while reading the pessimistic end of everything else — the asymmetry the peer
review caught, and the last one in the gate. Against the 0.70 floor the bootstrap p05 gives
guitar 0.830, bass 0.746, drum 0.870, so **no verdict moved**; vocals now fails rho on the
bound (0.606) as it already did on the mean (0.674).

The numbers were visible when this was decided, which is recorded rather than dressed up as
a blind pre-registration — the bootstrap was built and reported first. What makes it
defensible anyway is the **direction**: it replaces a point estimate with a strictly lower
number, so it can only make the gate harder to pass. There is no version of it that
flatters the model, which is the same test applied to raising `RESERVED_PCT` after seeing
the batch. Moving rho the other way would be the forbidden direction.

**A caution about macro, which this was built to unblock.** A macro floor is now
computable, but bass's interval is not clean — sd 4.37 and p05 79.19, driven by the **4.7%
of resamples that lose a tier entirely** (vocals 13.7%). `MacroUsable` averages over
*occupied* tiers, so those resamples measure a slightly different quantity over six bands
instead of seven. That is macro's weighting pathology made quantitative: whether three
packs get drawn moves bass's headline several points. The bootstrap measures this rather
than fixing it, and the report prints the rate. Any macro floor must be set knowing one
instrument's interval is dominated by a coin flip over three packs.

### Pack leakage in the CV folds, measured

Peer review finding 7: `pack` is CSV column 3 and the fold assignment never read it, so a
song could be graded while a sibling from the same DLC pack sat in training. Songs in a
pack share an authoring team, an era and often a deliberate difficulty spread, and the
corpus grows one pack at a time — so the pack, not the song, is the honest unit of "data
we did not have".

**The exposure is much larger than pack sizes suggest.** Under row-level folds about
**60% of validation rows** have a pack sibling in training (59.6–61.1% across the six
instruments). That is not visible from the largest pack being 15 rows of ~330: the corpus
is ~170 packs over ~330 rows, so half the packs are singletons contributing no exposure
at all, while the rows concentrate in the multi-song packs.

`StratifiedGroupFolds` (`stats.lua`) deals whole packs while still balancing tiers, and
the report now prints the selected model under both schemes on matched seeds. Measured
2026-08-22, grouped minus row-level, sd is of the paired per-repeat difference:

| instrument | pooled | macro | rho |
|---|---:|---:|---:|
| guitar | −0.21 (sd 0.85) | −0.14 (sd 1.67) | −0.003 |
| bass | +0.00 (sd 0.29) | −1.21 (sd 2.19) | −0.004 |
| drum | −0.09 (sd 0.52) | +0.19 (sd 1.31) | −0.004 |
| vocals | +0.03 (sd 0.70) | +0.27 (sd 1.21) | −0.009 |
| keys | −0.53 (sd 0.73) | −0.40 (sd 0.70) | −0.004 |
| real_keys | +0.19 (sd 0.44) | +0.06 (sd 0.75) | −0.004 |

**Leakage is real and negligible.** Every pooled and macro delta is smaller than the
spread of the difference that produced it, so on those metrics grouping is indistinguishable
from noise here. Rho is where it shows: **all six instruments moved down**, by 0.003–0.009,
and six of six in one direction is about a 1-in-32 coincidence. So the effect exists, and
it is worth roughly five thousandths of rho.

(Figures refreshed 2026-08-22 after the ridge-validation fix. The conclusion is unchanged
and the rho sign pattern still holds six of six — which is itself a small robustness check
on it, since the underlying models moved slightly.)

The reason it is this small despite 60% exposure is that a pack sibling is a weak hint —
packs routinely mix an easy song with a hard one, so a neighbour's rank barely narrows the
target. The 60% counts rows with *any* sibling in training, which is exposure, not
advantage taken.

**No gate verdict changes**, at effectively unchanged margins. `PROTOCOL.GROUP_FOLDS`
therefore stays `false` and the published figures remain row-level — not because grouping
was rejected, but because it costs nothing to keep the historical basis when the two agree.
Had the deltas been ~3 points, the grouped number would be the honest one to publish.

**Grouping makes the sparsest tiers worse, not better**, and any per-tier reading of a
grouped run has to say so: bass tier 6 sits in 3 packs and vocals tier 0 in 2, against 5
folds, so those tiers cannot reach every fold. The report prints this note itself.

This is separate from — and does not substitute for — drawing the **reserved partition** by
whole pack, which remains the plan above.

### The 2026-08-21 consolidation

The corpus arrived as `all_rb3_dlc_reference_songs/` — **244 packages, 566 MIDIs, 563
distinct shortnames**, flat layout. It covered most of what the four older folders held but
**not all of it**, so nothing was deleted until a hash comparison said what was unique
where. Absent from it were all **45 lego**, **15 rb2** and **4 greenday** (expected — none
are RB3 DLC), plus **25 scored `rb3_dlc` songs** including `deathontwolegs`, and ~148
unscored RBN basenames. **89 of the 394 frozen songs lived only in the older folders.**

237 songs were then copied into three origin-separated roots, preserving each song's
`<hash>_extracted` pack folder name — that name *is* the CSV's `pack` column, and phase 4's
pack-grouped CV depends on it surviving. One pack (`644B33E6`) is genuinely mixed-origin,
holding `ohlove` (`rb3_dlc`) beside three Green Day songs, so it appears under two roots
with the same name; pack identity is unaffected and only the dta is duplicated.

Verified after the move: **0 of 394 frozen songs missing, 0 in the wrong root, 258 reserved
(unchanged), and the only thing left behind was `stillofthenight(0)`** — a Windows
duplicate-rename artifact sitting beside the real `stillofthenight.mid` in the same pack.

`FROZEN_DEVELOPMENT_SET.txt` lives in the rb3 root and records every scored shortname with
**two** hashes: `scored`, the bytes the corpus was measured from, and `current`, the bytes
of the surviving copy. They differ on exactly three songs (below). Carrying `scored`
forward rather than recomputing it is deliberate — overwriting it would erase the only
evidence the two ever differed.

**Three shortnames name different bytes in the old and new collections. None of the
differences reaches a scored quantity:**

| song | what differs | scored impact |
|---|---|---|
| `wanteddeadoralive2` | EVENTS track, +8 notes (pitch 26, ticks 176640-177480) | none — the scorer reads only the `[coda]` **text** event from EVENTS, never its notes, and neither copy has a coda |
| `badmedicine` | one Pro Keys lane-shift marker moved tick 0 → 3840 | none — Expert gems byte-identical (1832 both), and `[coda]` sits at tick 314640 in **both**, so the BRE info fields agree |
| `waitandbleed` | tempo map, 119 vs 148 markers | **a real ritardando in the last four beats** — see below |

`waitandbleed` needed a denser look than four sampled ticks, which is what a first pass used
and which produced a wrong reading. Scanned beat by beat over all 462 beats:

- **286 beats are exactly equal** and **171 differ by under 0.001%** — sub-millisecond,
  floating point rather than music. Nothing at all falls between 0.001% and 1%.
- **Four beats differ by 23-42%**, at ticks 219360-220800 (149.9-150.9 s). The new copy has
  an ending ritardando the old one does not map. That is inside the playable region: the
  last Expert gem is at tick 221040.
- Cumulative offset **at the last Expert gem: +0.4245 s, +0.28%**.

So it is a genuine chart-timing difference, not redundant markers, and the earlier
"encoding only" reading was wrong. It is still not worth a rescore: 0.28% on `playing_s`
for **one row of 394**, on standardized factors, sits far below the noise floor the
protocol reads. Every one of the nine tracks is note-for-note identical in both copies —
the difference is purely how the final two seconds are timed.

---

## How to run

Order matters: everything downstream reads the CSV the first script writes.

1. **`run_calibration_vkr.lua`** — walks every root in its own `_corpora` list, imports each
   song's MIDI, scores every instrument, appends a row per (song, instrument) to
   `corpus_scores.csv`, and writes `corpus_scores.manifest.txt`.

   **Three roots, separated by origin since the 2026-08-21 consolidation:**

   | root | holds |
   |---|---|
   | `_external_docs/all_rb3_dlc_reference_songs/` | `rb3_dlc` only — **including the reserved test partition** |
   | `_external_docs/aux_reference_songs/` | lego, rb2, greenday — always-training at weight 0.30, never predicted |
   | `_external_docs/rbn_reference_songs/` | RBN `ugc_plus` — unscored; every rank is a tier floor |

   They replace `reference_songs/`, `new_reference_songs/` and `hard_reference_songs/`,
   which held overlapping copies in two different layouts. Every song those carried now
   lives under exactly one of the three, verified by hash. **Per-root and total song counts
   are deliberately not quoted here** — `corpus_scores.manifest.txt` carries them and is
   regenerated by every run, whereas a number written into this paragraph has now gone
   stale twice. The song list is pooled and de-duplicated by shortname before anything is
   imported, and the roots are recorded in the manifest.

   **The origin separation is load-bearing, not tidiness.** `FROZEN_DEVELOPMENT_SET.txt`
   defines the reserved partition *by complement*: any song in the rb3 root not listed
   there has never been walked. Putting the 148 RBN charts in that root would classify
   them as reserved `rb3_dlc` test data, and their ranks are tier floors that can never be
   regression targets.

   **`SPEND_RESERVED_PARTITION` guards the rest.** With a CSV in hand, any song it does
   not mention is reserved, and the walk drops it before a single MIDI is imported. This
   matters because the resume check runs the other way round — it skips the songs that
   *are* in the CSV, i.e. the development set — so without the guard the most natural
   possible run, "re-scan the corpus", would score the entire test partition and nothing
   about the result would look wrong afterwards. Setting the flag is a one-time,
   irreversible act.

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

   **It now requires `calibration_decision_manifest.lua`, so run the protocol first.**
   The exporter reads its selections from that manifest and recomputes the CSV,
   `protocol.lua` and factor-list fingerprints it records; any mismatch and it exits
   without writing. Its own `SELECTIONS` table survives as a documented **assertion** —
   the rounds and reasoning against each entry are worth keeping in the file that acts on
   them — and a disagreement between the two is a hard failure rather than a silent
   preference for either. Before this existed the table simply *was* the decision, and
   nothing could tell that it had gone stale: the unit tests refit whichever model the
   exporter names, so they pass whenever the exporter agrees with itself, including when
   the protocol has since selected something else.

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
| `calibration_protocol_report.txt` | Generated by the decision view. Rewritten atomically each run, and **versioned** — the README quotes it and CI checks it. |
| `calibration_decision_manifest.lua` | Generated beside it: the same run's selections as data, plus fingerprints of the CSV, `protocol.lua` and the factor list. **Versioned.** `export_production_models.lua` reads it and refuses to export if any fingerprint no longer matches, which is what stops a superseded selection from being frozen into `lib/`. Never hand-edit. |
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
USABLE_FLOOR  0.90   MISS_CEILING  0.05   RHO_FLOOR  0.70   ENDPOINT_FLOOR  0.80
```

Folds are stratified by **actual tier**, because whole tiers hold 2-3 songs and an
unstratified shuffle can leave a fold with none of them.

**Targets and weights.** RB3 DLC is the target throughout — 330 of the 394 songs actually
scored, the rest being 45 Lego-era, 15 RB2-era and 4 `greenday`.

> **Two different song counts, and they are easy to confuse.** `corpus_scores.manifest.txt`
> reports `corpus songs : 526` — that is songs **walked**, and 132 of them had no readable
> MIDI (mostly RBN `ugc_plus`, whose dta dialect is not parsed; see "Why three instruments still fail"). **394**
> songs reached the CSV, which is the number every figure in this document is about.
> Confirm either from the CSV itself rather than from the manifest's headline.

The Lego-era songs sit on a rank scale about 45 points below RB3, so they are
always-training at weight 0.3 and carry an `is_lego` column: they are prevented from
steering the model.

> *Measured 2026-08-21, and the older wording ("they add information without steering the
> model") was half right.* Ablating all 60 auxiliary rows moves the selected model by
> **+0.15 / +0.03 / +0.001** on guitar (pooled / macro / rho), **+0.03 / +0.69 / +0.000**
> on bass, **+0.00 / +0.22 / +0.002** on vocals, and exactly zero on both keyboard parts,
> which have no auxiliary rows at all. Only **drums** shows anything real — **+0.46 pooled
> and +1.46 macro**, roughly 1 sd on each. They are kept because removing them would change
> every published figure for no gain, not because they were shown to help. `PART KEYS` has no Lego rows at all — Lego Rock Band predates the
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
7. **The protocol report is written atomically, and CI checks it.** The run writes to a
   sibling `.part` and renames onto `calibration_protocol_report.txt` only after a
   `[report complete]` footer is on disk, so a killed run leaves the previous report
   intact. This is not defensive habit: the round-23a report was committed in a state
   where an interrupted run had dropped four declared drum candidate rows and duplicated
   a block of the keys residuals, and it was read as authoritative afterwards because
   nothing about it looked wrong. `.github/workflows/calibration.yml` regenerates the
   report and fails on any byte difference. **Do not add a timestamp to the report** —
   its byte-determinism is what makes that check possible, and the header explains why
   the runtime marker goes to the console instead.

   Both generated files are opened `'wb'`, and that is load-bearing rather than tidy:
   Lua's text mode writes CRLF on Windows and LF on Linux, so a report written under
   REAPER could never match one regenerated on the CI runner. The check would have failed
   on its first run for a reason with nothing to do with the calibration. Any future
   generated file that joins the check needs the same treatment.
8. **`SPEND_RESERVED_PARTITION` stays false.** The rb3 root is in `_corpora` and holds the
   258-song test partition alongside the development set; the guard in
   `run_calibration_vkr.lua` is the only thing keeping a routine rescan from scoring it.
   The resume check skips songs that are *in* the CSV, so the reserved ones are precisely
   what a re-scan would otherwise pick up. Spending the partition is a deliberate,
   one-time, irreversible act with its own declaration - never a config edit made in
   passing, and never a way to "just get more rows".
9. **The protocol decides; the exporter obeys.** `calibration_decision_manifest.lua` is
   the machine-readable record of what a run selected and what it selected it from.
   `export_production_models.lua` reads it and refuses to write if the CSV, `protocol.lua`
   or the factor list has moved since. Do not "fix" a refusal by editing the manifest —
   it is generated, and the refusal means the selection predates the inputs. Rerun the
   protocol. If the selection genuinely changed, update `SELECTIONS` **and the reasoning
   beside it** in the exporter, which is the one edit that makes a reselection visible in
   review rather than arriving as a coefficient diff.
10. **`validated` means the reserved partition was spent and the model passed on it —
   nothing else.** Guitar, bass and drum shipped as `validated` on development-set CV
   until 2026-08-21, were demoted to `beta` when the peer review named that as
   unsupportable, and regained the word on 2026-08-23 by clearing the 90% floor on 258
   held-out songs. That is the *only* route to it.

   **The partition is now spent, so the route is closed.** A better number on existing
   rows never earned the word and still cannot. If the models change, the 2026-08-23
   figures describe the *old* ones and the word comes off until genuinely new
   pack-held-out data exists — which requires a new partition rule, since `RESERVED_PCT`
   at 100 has nothing left to reserve.

11. **`PROTOCOL.GROUP_FOLDS` is not a flag to flip.** Every published figure is measured
   under row-level folds. Setting it true changes all of them at once, which README rule 1
   makes a declared new experiment with its own pre-registration — not a repair. The
   grouped scheme is *measured and reported* beside the row-level one for exactly this
   reason. As of 2026-08-22 the two agree, so there is nothing to decide; if a future
   corpus makes them disagree by more than about a point, the grouped number is the honest
   one and the switch is the whole experiment, artifact regeneration included.

12. **This file records what was measured, not what to do next.** It is committed, so it
   holds results, the protocol, how to run the harness, and the rules above — the things a
   fresh clone needs. Work queues, candidate ideas and round plans go in the gitignored
   `_future_ideas/` instead. A finding that closes an approach stays here, because "this
   was tried and it failed for this reason" is a result; "try this next" is not.

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
  > sample-size reading was wrong; see "Why three instruments still fail". The figures above are left as they
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

## Why three instruments still fail

Where keys, Pro Keys and vocals actually stand, and what has already been ruled out for
each. Every claim here is measured; the point of the section is that none of it should be
re-derived, and that the approaches marked closed should not be re-proposed without a new
mechanism. What to do about any of it is a plan, and plans are not kept in this file.

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
(`run_calibration_vkr.lua` refuses to resume on a column-set change), so changes not
worth that cost on their own are collected until a rescore happens for another reason.
The queue itself is work not yet done rather than a record of what was measured, so it
lives in the gitignored `_future_ideas/` beside the round narrative rather than here.

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
