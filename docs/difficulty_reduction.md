# Difficulty reduction - how Generate makes Hard, Medium and Easy

The instrument helper's **Difficulty > Generate** sub-tab writes a song's lower difficulties from
the one above: Expert to Hard, Hard to Medium, Medium to Easy. This document lists every rule it
applies, per instrument and difficulty, and where each rule comes from.

The code says *what* a rule does; this document says *why* - which source it follows and how
it compares with the official charts. When you change a rule, change its entry here too.

## Sources

Every rule carries one or more of these tags:

- **RBN doc** - the Rock Band Network / C3 authoring documentation (the Drum, Guitar and Bass,
  5 Lane Keyboard and Pro Keyboard Authoring pages). Quoted where it is quoted.
- **Official charts** - measured on the official Rock Band 3 DLC charts: about 480 songs, each
  difficulty compared with the one above. Numbers are shares of the cases the rule is about, by
  tempo band where tempo matters. Community (RBN) releases are not included.
- **User rule** - the project author's decision, usually from playing and reviewing generated
  charts. Where official charts do something else, the entry says so and gives the measured
  difference.

"Agreement" figures (F1) compare Generate's output with the official tier, onset by onset, over
the same songs: 100 would be the official chart exactly. A rule that lowers agreement can still
be the right call - official charts are not the only good answer.

Gem notation in examples: `K` kick, `R` snare, `Y` `B` `G` cymbals (yellow hi-hat, blue ride,
green crash), lower-case `y` `b` `g` toms (under a Pro Drums tom marker). Positions like `12:R`
are in 1/24 quarter notes from the bar line (12 = an 8th, 24 = a beat); `K RB . RB` shows one
hit per 8th, `.` for none. "The "and"" is the off-beat 8th between two beats.

## Settings

The Generate sub-tab's options, and the rules they switch:

| Setting | Options (default first) | Affects |
|---|---|---|
| Hard fast runs | Rewrite / Auto / Thin | Hard: fast tom/snare fills and 5-lane runs - played one grid slower (Rewrite), or thinned to the Hard grid as official charts do (Thin). Auto rewrites only above 160 BPM. |
| Hard 8th runs | Auto / Drop 1 / Drop 2 | 5-lane Hard's busy bars; Drums Hard's hi-hat fallback (below). |
| Drums Medium | Beats / None / Keep | Drums Medium: a kick or snare between two hi-hat/ride notes. |
| Drums fast 8ths | Hands / Beats | Drums Medium/Easy at fast tempos: which of three hand hits an 8th apart goes. |
| Only 2x bass pedal authored on PART DRUMS | off / on | Drums: treat PART DRUMS as the double-bass chart (see Drums 2X). |

---

## Drums

`difficulty_generate_drums.lua` (`GenDrumsPlanTier`). The tempo thresholds Validate also checks
live in `DRUMS_RULES` (`actions_difficulty_drums_checks.lua`), so the two cannot drift apart; the
planner's own numbers are `GEN_DRUMS_PARAMS`.

### How drums are reduced

- **Limb by limb.** Drums are not reduced like the band's one-line instruments: a drum hit is
  several limbs at once, and each limb thins on its own terms - the kick goes fastest, the snare
  backbeat stays, the right hand drops from 8ths to quarters with tempo. *User rule.*
- **Independent of the band.** Drums neither follow nor lead Guitar, Bass or Keys. *User rule,
  not measured:* the RBN docs say nothing about one instrument's lower difficulties following
  another's, and whether official drums line up with the band's reduced rhythm has not been
  checked. (Bass and Keys do follow Guitar - see Guitar and Bass.)
- **Safety net:** a hit has at most two hand gems and a kick - two hands, one foot. Official
  charts never have more, on any tier. A hit in the tier above that does (a charting mistake) is
  listed in the result to fix, and Hard keeps the kick and two hand gems, a hi-hat/ride cymbal
  going first.
- **Notes never move** - every rule removes a note or changes its lane. *Official charts:*
  0.03% of official Hard hits are not on an Expert hit. The one exception is the fast-run
  rewrite under "Hard fast runs" (Hard, below).
- **Context read from the take:** fill lanes (pitch 120), roll lanes (126/127), Pro Drums tom
  markers (110-112: a Yellow/Blue/Green gem under one is a tom, else a cymbal), Expert's
  disco-flip sections (`[mix 3 drumsNd]` to the next `[mix 3 drumsN]`), and the EVENTS track's
  section names.
- **Fill lanes change nothing.** A fill lane marks where overdrive can be activated, not what is
  played: official charts place one every few bars (about 28 a song), over grooves as often as
  over fills. Wherever a rule below says "fill", it means content - a run of snare/tom hits with
  no hi-hat or ride - never the lane. *Official charts:* Easy keeps a lane's kicks at its usual
  rate (16-18% of Medium's kicks outside verses without a lane, 19% under one; verses 60-72% /
  63-81%).
- **Tempo.** Almost every rule reads the tempo at each note. A few decisions are made once for
  the whole drum part (today: whether Easy's fills go to quarter notes); those use the faster of
  two tempos - the tempo at the song's first bar, where the song's authored tempo is set, and the
  tempo at the drum part's own first note. A song whose drums start in bar 10 compares bar 1 with
  bar 10; other instruments do not matter. *User rule:* a live tempo map with a marker on every
  bar can put the drums' first bar a fraction under a threshold (119.64 against 120) while the
  song is meant to be at 120. The faster one only, so Generate never applies a looser rule than
  Validate, which checks each note's tempo. (`SongTempo`)

### Hard

**Disco beats are un-flipped** - `Unflip`
Expert's disco-flip sections (hi-hat on the snare lane) go back to a normal beat: hi-hat on
Yellow, only on 8ths, snare on Red with a hi-hat above it.
*RBN doc:* "Un-flip any "Disco" beats, or "16 beats." That is, put the hihat gems back on yellow,
snares back on red, delete the in-between 16th notes, and add a yellow hihat gem above the snare
gem." *Official charts:* lower difficulties never carry a disco-flip event.

**Fast fills are rewritten one grid slower** - `RetimeFills` (`Gen5RetimeDenseRuns`), "Hard fast runs"
A tom/snare fill of 16ths (16th triplets below 140 BPM; from 140, 8th triplets too) is played on
the next slower grid - 16ths as 8th triplets, 8th triplets as 8ths - keeping the order of its
notes, inside its first and last Expert note. Grooves with a cymbal are never rewritten.
*User rule* (Rewrite, the default): it keeps more of a fill's motion than official charts, which
always thin to the 8th grid - Thin gives the official behaviour. Rewritten bars are listed in the
result.
- **Mixed runs** (`group_grid = 'own'`, `min_grid`): a run whose spacing changes (16th snares,
  then 32nd toms, then 16th toms) is split into groups, each one grid slower than itself, never
  faster than 16ths below 140 BPM or 8th triplets above. *User rule.*
- **Tom markers follow the rewrite** (`RunTomMarkers`, `ApplyTomMarkers`): a tom the rewrite
  moved gets one tom marker over the whole run, so the game still reads it as a tom; if that
  marker would turn a cymbal somewhere else into a tom, the run is thinned instead. The result
  names the bars. *Official charts:* tom markers are shared by every difficulty and often sit
  exactly on Expert's notes (median length 0.75 quarter notes, 38% a 16th or shorter). *User
  rule* for the one-marker layout.

**No 16ths at 140 BPM and faster; 16th runs only if short** - `HardSixteenths`, `hard_run_beats`, `hard_16th_min_run`
From 140 BPM nothing stays off the 8th or 8th-triplet grid. Below it, a tom/snare 16th run stays
if it lasts two beats or less; hi-hat/ride 16ths in a stream go (a crash beside them stays); a
lone 16th snare stays on the "a" and goes on the "e".
*RBN doc:* "Avoid authoring 16th note rolls when the song is at 140bpm or above"; "Such passages
should be authored only if they last a beat or two"; snare accents: "remove about half of them in
a way that is consistent throughout the entire song". *Official charts:* 3-5% of hits off the
8th grid at 140+; a lone 16th snare kept 43% on the "a", 32% on the "e".
*User rule:* two 16th snares in a row already count as a run and stay whole (`hard_16th_min_run`
2); official-like would be 3 (one of the pair goes). Agreement 92.6 with 2, 92.8 with 3.

**Kick spacing** - `ThinKicks`, `hard_kick_gap`, `hard_kick_gap_8th`, `hard_kick_gap_fast`, `hard_kick_gap_fast_bpm`
No two kicks closer than an 8th; a kick off the beat (on an 8th or a 16th) needs 3/4 of a
quarter note after the previous one, so the kick on the "and" after a beat kick goes; from 140
BPM every kick needs 3/4.
*RBN doc:* "Thin out the kicks until they number halfway between Medium and Expert. A good first
step is to remove kicks on adjacent 8th or 16th notes." *Official charts:* Hard keeps 60-71% of
Expert's kicks on beats and 8ths; 46% of 8th kicks at 140+ BPM, 65% below.

**Busy hands: kicks half a bar apart** - `BusyHands`, `hard_kick_gap_busy`
A kick with a hand hit an 8th before and after it (steady 8th hi-hats) keeps half a bar from the
previous kick - reaching back only within its own bar. Under steady hats, Expert's kick on every
beat becomes kicks on 1 and 3.
*Official charts:* kicks on 1 and 3 is official Hard's commonest answer (49% of 1,400 such bars at
100-139 BPM; all four kept 23%). *User rule* for the own-bar limit.

**The bar's last beat keeps its kick** - `EndOfBarKick`, `hard_end_of_bar_kick`
When the spacing removed the kick on beat 4 and the "and" after it has none, the beat-4 kick
comes back; a kick less than 3/4 of a quarter after it goes. Not when Expert's kicks are on
exactly the four beats: that bar keeps 1 and 3.
*Official charts:* Expert kicks on 1, 3, 4 and the "and" of 4 under steady hats (316 bars): Hard
keeps beat 4 33%, the "and" 27%, both 1%, neither 39%. *User rule* to keep it. Expert's kicks on
the four beats with the hands on every 8th: Hard plays 1 and 3 in 858 of 1,270 bars under 140 BPM,
424 of 524 at 140-169, 98 of 105 from 170; 1 and 3 plus beat 4 is not among the answers.

**Kicks on every 8th become kicks on every beat** - `HardEighthKicks`, `hard_eighth_kicks`
A bar whose Expert kicks and hands both play every 8th keeps a kick on each beat, and none
between. The busy-hands spacing would leave 1 and 3, the same as a bar of quarter kicks, so an
outro or build that goes from quarter kicks to 8th kicks would sound the same on Hard; this keeps
it one step slower than Expert.
*Official charts:* fewer bars, spread over few songs: quarters are the commonest answer under 140
BPM (102 of 322 bars, 12 songs) and from 170 (58 of 63, 2 songs); at 140-169 the 57 bars are mixed
(from 2-7 songs each). *User rule* with that support.

**One 8th kick paired with beat 3** - `PairedKick`, `hard_paired_kick`
The busy-hands spacing's dropped kick on the "and" of 2 (leading into beat 3) comes back, else the
"and" of 3 - not when Expert has both (read from Expert itself: Hard's fill rewrite can move
either "and" off the 8th grid).
*Official charts:* `K . . K K . . .` kept as it is 93% at 140+ BPM, 55% below; `K . . . K K . K`
-> `K . . . K K . .` 46% / 62%.

**A kick figure keeps the beat's kick** - `HardKickFigures` (below 140 BPM)
A kick on a beat with a kick-only hit a 16th after it keeps the beat's kick, loses the 16th one,
and is exempt from the busy-hands half bar.
*Official charts:* in such figures with the beat kick busy (900 cases, 29 songs) Hard keeps the
beat kick only 99%, the 16th one 0%.

**The kick under the snare stays** - `KickUnderSnare`, `kick_under_snare` (off)
*User rule:* on Hard and Medium no RBN rule forbids kick + snare (or kick + snare + cymbal), and
the beat's kick carries the groove. (Easy never pairs a gem with a kick.) *Official charts* mostly drop it, but per song: of 222 songs with 20+ such hits, 156
drop it almost always, 15 keep it almost always; overall Hard keeps 21.5%.

**Backbeat on the "and"s, from 170 BPM** - `HardAndBackbeat`
A bar with the snare on at least 3 of its 4 "and"s, none on the beats, everything on the 8th grid
(or a half bar with both its "and"s) plays the hands on the "and"s only: the beats lose their
hi-hat/ride (kick and crash stay). A snare under a crash on the first beat is an accent and does
not disqualify the bar. The kicks take the busy-hands spacing - beats 1 and 3 - and beat 4's kick
does not come back.
*Official charts:* in such bars with an Expert kick on every beat (261 bars at 170+, 3 songs) Hard
keeps kicks on 1 and 3 87%, all four 12%; Medium `K RB . RB . RB . RB`, Easy the four "and"s.
*User rule* for the half-bar case.

**No constant stream where Expert has none** - `BreakEighthRuns`
A run of 4 hand hits at one spacing - 8ths from 170 BPM, 8th triplets from 140 - loses its least
valuable hit, unless Expert plays faster over the same stretch (then Hard's run is a reduction,
not a copy). Kick-only hits do not count.
*RBN doc:* "The upper threshold for playing a constant stream of 8th notes at this difficulty is
about 170bpm." *Official charts:* at 170+ BPM, where official Hard has an 8th run, Expert is
faster there 49% of the time and a copy 51%. *User rule:* relative to Expert, hands only.

**Hi-hat fallback for a Hard that would equal Expert** - `HardHatDrops`, `hard_hat_drop` ('fallback'), `hard_fallback_keep` 0.95, "Hard 8th runs"
A Hard that would keep more than 95% of Expert's notes is planned again with each steady 8th
hi-hat bar losing 1 or 2 hat-only "and"s ("Hard 8th runs": Auto = 2 above 160 BPM): the "and" of
1 first after a crash on 1, then the "and" of 4, then of 2. A hat with a kick or snare stays.
*Official charts:* Hard never keeps 97%+ of a simple Expert at 130-169 BPM (0 of 45 songs, median
86%); after a crash on 1 it drops the "and" of 1. *User rule* to apply it only as a fallback:
doing it in every steady bar lowered agreement 93.1 -> 90.9 (official keeps all 8 hats in 92-94%
of bars under 120 BPM).

### Medium

**Fills on the 8th grid** - `GridFillRuns`
*RBN doc:* "We don't require the player to know how to hit a run of 16th notes by alternating
hands, so reduce fills and rolls to 8th notes, or less for faster songs."

**A fill Hard rewrote is reduced from Expert** - `ExpertForRewrittenRuns`, `opts.expert`
Where Hard's rewrite moved a fill off the 8th grid (8th triplets), Medium takes Expert's notes for
that stretch instead, and reduces them like any fill - otherwise its 8th grid finds nothing of
the rewritten fill but the beats. Expert is passed from the same run, or read from the track, so
a Medium-only run does the same. *User rule* (follows from the rewrite). Agreement in Rewrite
mode: Medium 93.3 -> 93.5, Easy 89.1 -> 89.3.

**Hi-hat/ride to quarter notes from 130 BPM** - `LowerHands`, `lower_hat_quarter_bpm` 130
*RBN doc:* "The player's right hand shouldn't be expected to keep time with 8th notes if the song
is 140bpm or faster." *Official charts* switch earlier: steady 8th-hat bars stay all 8 in 54% of
bars at 125-129 BPM, 18% at 130-134, 3% at 135-139. With 130, Medium keeps 76% of Hard's notes at
125-134 BPM, as official does.

**Medium fallback: quarter hats when Medium would barely differ** - `medium_fallback_keep` 0.93, `medium_fallback_bpm` 120, `medium_fallback_on` 'hands'
A song from 120 BPM whose Medium would keep more than 93% of Hard's hand gems (kicks not counted)
is planned again with the hi-hat/ride on quarters at any tempo; the result says so.
*User rule:* near 128 BPM official Medium often keeps 8th hats, so this costs agreement: it fires
in 50 of 482 songs, and overall Medium agreement drops 94.0 -> 92.8.

**Two-hand "and"s keep their hat** - `LowerHands` (`TwoHand`)
When Medium's hats go to quarters, a hit of hat + snare/tom on an "and" keeps its hat.
*Official charts:* under 130 BPM Medium keeps both 44%, the drum only 27%, drops it 25%.

**Kick/snare between two hi-hat notes** - `Between`, "Drums Medium"
A kick-only or snare-only hit between two hi-hat/ride notes at most a quarter apart (a crash is
not timekeeping): Beats keeps the ones on a beat, None removes them all, Keep keeps them all.
*RBN doc:* "No kicks or snares in between hihat/ride (ie, right hand time keeping) gems." (None)
*Official charts:* Medium keeps them 83-94% on a beat, 22% on an 8th (Beats, the default).

**A tom pair plays one tom** - `MediumTomPairs`, `medium_tom_pair_bpm` 140, `medium_tom_pair_sparse_keep`
From 140 BPM a two-hand hit with a tom plays one gem - of two toms the higher lane, of a cymbal +
tom the tom; two toms also off the beat at any tempo. A snare + tom stays.
*Official charts:* Medium keeps both gems of a tom pair 26% (on the beat 44% under 140, 10% at
140+), of a cymbal + tom 28%; the higher tom kept 62% vs 26%; snare + tom kept 78%.
*User rule* (`medium_tom_pair_sparse_keep`): a bar with no more hand notes than beats - a double
counts two, kicks none - keeps its tom pairs; when a bar is over only because a tom pair repeats
an 8th later, the repeats go and the doubles on the beats stay (`yb yb . yb yb` -> `yb . . yb`).

**The hand that just crashed resets** - `AfterCrash`, `after_crash_bpm` 120, `after_crash_snare_bpm` 140
From 120 BPM the cymbal/tom gems of a hit an 8th after a crash accent go; from 140 BPM its snare
too (the kick stays).
*RBN doc:* "At faster tempos, remove gems immediately after a crash to give the player time to
reset his/her hand position." *Official charts:* the gem after a crash kept 32% at 120-139 BPM,
5% at 140+; a snare an 8th after a crash on the beat kept 80% under 140 BPM, 8% at 140-169, 12%
at 170+ (nearly all of those from one song).

**Hats between snare accents** - `SandwichedHats` (with a tom in the accent)
A hi-hat/ride hit with a snare + tom accent an 8th before and after loses its cymbal - otherwise
the right hand leaps between hat and tom on every 8th (`Y Rb Y Rb Y`).
*Official charts:* Medium with tom accents drops the hat 43 of 55 times. *User rule* to apply it.

**A change of drum between two-hand hits** - `DrumChanges` (Medium and Easy)
Two hits of one cymbal + one drum an 8th apart whose drum changes (tom -> snare, snare -> tom):
the first loses its drum (`Yb RY` -> `Y RY`). *Official charts:* under 130 BPM Medium drops the
tom 45 of 48 times (tom -> snare), the snare 10 of 15 (snare -> tom).

**Three-limb hits lose the kick** - `MaxGems` (2)
*RBN doc:* "No 3-limb hits (ie. Simultaneous kick, snare, and crash all at the same time)."
*Official charts:* KRY -> RY.

**Long 8th snare runs: Medium keeps them** - see Easy. *Official charts* thin them on Medium too
(5+ snare hits an 8th apart kept whole 15% at 120-129 BPM); *user rule* to keep Medium as is.

### Easy

**One beat per section** - `EasyBeats`, `easy_ks_min_density` 0.5
A verse led by the hi-hat or ride plays kick + snare when its Medium has at least 0.5 kick/snare
hits per quarter note, else the two-hand beat; every other section plays the two-hand beat (no
kick); a bar with no cymbal plays kick + snare. A gem never pairs with a kick.
*RBN doc:* "the beat can usually be reduced so that the player either is playing a 2-hand beat
with no kick, or a beat with just kick and snare ... less intense sections should be authored a
kick/snare beat, and more rocking sections should be authored as a 2-hand beat"; "No gems should
be paired with a kick." *Official charts:* kick + snare in 69-84% of hi-hat verse bars, 58-73% of
ride ones; two-hand beat in 89% of chorus bars, 90% of outro bars; KG -> G 92%. *User rule* for
the density test: a sparse verse keeps its cymbal (official: hi-hat 61%, ride 90% in such verses).

**A quiet half bar keeps its kicks** - `easy_quiet_half_kicks`
In a two-hand bar, a half bar with no hand hit keeps its kicks (`KG KB K K` -> `G B K K`).
*User rule.* *Official charts* keep a kick-only beat there 20% of the time.

**Fills to quarter notes from 120 BPM** - `GridFillRuns`, `DRUMS_RULES.roll_easy_quarter_bpm`
A once-per-song decision by the song's tempo (bar 1 or the first note, the faster). A fill
continues across a quarter-note gap, so a fill Medium broke up still goes to quarters from its
start. The quarter grid picks the beats or the "and"s, whichever keeps more of the fill (the
beats on a tie).
*RBN doc:* "Depending on tempo, you may want to reduce Medium's 8th note fills to quarter notes."
*User rule* for the phase pick (official puts such quarters on the beats more often; -0.3
agreement).

**Long 8th snare runs to the beats from 120 BPM** - `EasySnareRuns`, `easy_snare_run_bpm` 120, `easy_snare_run_min` 5
A run of 5+ hand hits an 8th apart, each with a snare, keeps only the hits on the beats.
*Official charts:* Easy keeps such a Medium run whole 51% at 120-129 BPM, 6% at 130-139, as
quarter notes 20% / 65%, on the beats 100%.

**Backbeat on the "and"s, from 110 BPM** - `HardAndBackbeat`, `easy_and_backbeat_bpm` 110
The Hard rule at a lower tempo, half bars included, tested on the bar as Medium has it: the
beats lose their hi-hat/ride (crashes stay), the "and"s keep snare + cymbal.
*User rule:* official Easy is split by song - of six songs with real stretches of this groove at
110-129 BPM two play the "and"s only, two keep all eight. (Official Easy does not thin a steady
8th groove bar by bar: it keeps all eight in 72-78% of non-verse bars below 130 BPM, and its usual
reduction is a whole section going kick + snare.)

**Hats between snare accents** - `SandwichedHats` (any snare)
As on Medium, but any snare accent counts. *Official charts:* Easy at 120+ BPM drops the hat 18 of
24 times.

**Two-hand "and"s where Easy itself went to quarters** - `EasyTwoHandAnds`
Where Easy (not Medium) moved 8th hats to quarters, a two-hand "and" keeps its drum and the beat
before loses its cymbal. *Official charts:* the "and" keeps its drum 87%; the beat's cymbal kept
11%. Where Medium was already on quarters, Easy keeps the "and" as Medium has it (official 72%).

**No hi-hat right before a crash** - `EasyBeforeCrash`
A hat + snare/tom hit an 8th before a crash loses its hat (`RY | G` -> `R | G`). Hat-only hits stay.
*User rule:* official Easy drops that hat only 34% under 130 BPM.

**A lone drum "and" goes from 140 BPM** - `EasyLoneAnds`, `easy_lone_and_bpm` 140
A snare/tom/kick on an "and" (no cymbal) with a beat hit an 8th before and after goes.
*Official charts:* dropped 94% at 140+ BPM, 36-41% at 120-139, 22% below.

**No pair of hand hits an 8th apart from 170 BPM** - `LowerEighthHands`, `easy_no_pairs_bpm` 170
(The three-in-a-row rule below, for two.) A kick next to a hand hit stays; a pair of equal hits
keeps the first.
*Official charts:* official Easy at 170+ BPM has a hand hit an 8th from another on 0.4% of its
hits; after a crash on 1 the "and" snare goes, and an "and" right before a crash goes.

**Kicks** - see "Medium and Easy kicks".

### Medium and Easy

**No three hand hits an 8th apart at fast tempos** - `LowerEighthHands`, `lower_eighth_hands_bpm` (Medium 150, Easy 140), "Drums fast 8ths" (`lower_eighth_hands_default`)
Each window of three hand hits an 8th apart loses one hit's hands (its kick stays); a pair stays.
Which one is the setting: Hands (default) - the hit with the least important hand gems (a beat
wins a tie), so a hi-hat on the beat can go and two snares stay together; Beats - the "and"
first. In both, removing a hit that would leave more than a quarter note with no hit at all
counts against it.
*Official charts:* from 150 BPM 94% of Medium's hand hits, and from 140 BPM 98% of Easy's, have no
hand hit an 8th away; where the tier above has a lone pair Medium keeps both 56% (from a beat) /
17% (from an "and"), Easy 34-39%; a beat-"and"-beat run keeps the two beats 89-100% (Beats).
*User rule:* Hands - more of the groove's movement; agreement Medium 94.2 (Beats) vs 94.0 (Hands).

**A cymbal change an 8th apart** - `CymbalChanges`, `lower_cymbal_change`
Two hits an 8th apart on different cymbals that need 3+ hand pads between them lose the
hi-hat/ride that is not on both (Yellow before Blue): `RY | RG` -> `R | RG`. Crashes, snares and
toms stay. *User rule.*

**A tom before a crash** - `TomBeforeCrash`
A snare + tom hit within a quarter note before a crash loses its tom.
*RBN doc:* "if crash happens right after a snare flam, turn the snare flam into a one-hand hit so
that the right hand doesn't need to move so fast to the crash." *Official charts:* Medium drops
it 79% a quarter before / 69% an 8th before under 130 BPM, 70% at 130+.

**Kicks** - `LowerKicks`, `lower_kick_gap`, `lower_kick_gap_fast`, `lower_kick_gap_fast_bpm`, `lower_kick_gap_busy`, `OneKickPerBar`
Quarter notes only above 100 BPM; at most one a quarter apart - half a bar from 140 BPM, and half
a bar when the hands are busy around the kick (an 8th before and after); one a bar from 170 BPM.
A three-limb hit loses its kick before the kicks are spaced.
*RBN doc:* "For songs above the 100-110bpm range, consider only authoring kick gems on quarter
notes"; "If the song is at 170bpm or above, one kick gem per measure is enough." *Official
charts:* Medium keeps 66% of Hard's beat kicks below 140 BPM, 42% above; the oom-pah groove
`KY RY KY RY` becomes `KY RY Y RY KY RY Y RY` in 154 of 370 such bars (*user idea*, busy hands).

### Every difficulty

**Double crashes become one crash** - `DoubleCrashes`
A Yellow/Blue + Green crash on one hit plays the Green alone (a kick under it stays), with room
around it or not. A tom pair or a cymbal + tom is not a double crash.
*Official charts:* Expert has 3,457 double crashes, Hard 26, Medium 8, Easy 0; Hard keeps the Green
alone 93-97%, even with a quarter note of room on both sides (90-95%).
*RBN doc* allows one on Hard "unless there is plenty of empty space around them" - official charts
reduce them anyway, and so does Generate.

**Rolls on the tier's grid, with an even hit count** - `Rolls`, `EvenRolls`, `medium_roll_8th_bpm`
Roll lanes are played on the tier's grid (Hard 16ths, 8ths from 140 BPM; Medium 8ths, quarters
from 120; Easy quarters), trimmed from the start to an even number of hits.
*RBN doc:* "For fast drum rolls, you can trim off a hit or two to make it start on an 8th or
quarter note grid line. 16th note rolls with an uneven number of hits require an extra bit of
advanced reading to nail, so even them out." *Official charts:* roll lanes are Expert-only; Hard
plays rolls as 16ths 38% / 8ths 46%.

**Medium and Easy: no constant 8ths from 140 BPM** - `BreakEighthRuns`
A run of four hits an 8th apart loses its least valuable hit. *RBN doc* (Medium 140 BPM, as above).

### Drums 2X (double bass pedal)

Part of the Drums selection: the "2X track" row picks PART DRUMS_2X, generated after PART DRUMS.
Below, 1X is PART DRUMS (one pedal) and 2X is PART DRUMS_2X (double pedal).
- **Each 2X difficulty plays the kicks of the 1X difficulty one step up** - 2X Hard gets 1X
  Expert's kicks, 2X Medium 1X Hard's, 2X Easy 1X Medium's (`GenDrums2xInput`,
  `opts.keep_kicks`). The hands are reduced from 2X's own difficulty above by the usual rules;
  the extra kicks can change which hand hits a difficulty keeps. The 1X kicks are already a
  reduced tier's, so the rules that *choose* kicks are skipped: Hard's kick spacing, busy hands,
  end-of-bar and paired kicks, and Medium/Easy's quarter-note and half-bar spacing. The rules
  that say what a tier may *contain* still apply, because the tier one step up is allowed more:
  on Medium and Easy, kicks only on quarter notes above 100 BPM, one kick a bar from 170 BPM, no
  kick under an off-beat crash, a three-limb hit loses its kick; on Easy no gem with a kick (all
  RBN doc rules, which Validate also checks).

  *User rule, unlike community practice.* Harmonix's own charts have no double-bass versions and
  the RBN docs give no rules for reducing them. Community RBN releases did ship "(2x Bass
  Pedal)" versions. Compared with their 1x releases (30 songs with both versions), their Hard,
  Medium and Easy are the 1x song's, unchanged - the same kicks and the same hands; only Expert
  differs. These have no documented shared guideline and a few authors account for many of
  them, so they show what was done, not a clear rule that should be followed for 2x kick
  reductions. Generate keeps the ladder on purpose: going from 2x Expert straight to
  the 1x Hard kicks is a big drop, and the ladder gives a player not yet ready for Expert a
  step toward its fast kick patterns.
- **Without a PART DRUMS** ((none) picked, or none in the song), the kicks come from a single-pedal
  version made in memory exactly as "Remove 2x kicks" makes one (`SinglePedalTiers`,
  `DoubleBassPlan`).
- **"Only 2x bass pedal authored on PART DRUMS"**: a song charted only in its double-pedal
  version - PART DRUMS is generated the way a 2X track is. The run stops if the song also has a
  PART DRUMS_2X, or if PART DRUMS Expert has no second-foot kicks to remove.
- **Muted tracks:** Generate never writes to a muted track - a muted track picked for the run
  stops it; All instruments skips muted tracks.

---

## Guitar, Bass and Keys (5-lane)

The rhythm is chosen by `difficulty_generate_rhythm.lua` (`Gen5SelectOnsets`), shared by every
instrument; chords, colors and sustains by `difficulty_generate_5lane.lua` (`Gen5PlanTier`) and
`difficulty_generate_colors.lua`; Hard's fast runs by `difficulty_generate_retime.lua`, Hard's
hammer-ons by `difficulty_generate_hopo.lua`, Keys' held notes by
`difficulty_generate_overlaps.lua`. The numbers are `GEN5_PARAMS` (`difficulty_generate_params.lua`).

### How 5-lane parts are reduced

- **One rhythm model for every instrument.** Which onsets a tier keeps depends only on their
  positions, lengths and the tempo - never on colors, chords or the instrument - and every
  instrument uses the same numbers. Guitar, Bass and Keys playing the same Expert rhythm get the
  same Hard, Medium and Easy rhythm. Chords and colors are reduced afterwards and never change
  which onsets survive. *User rule:* official Keys reduces less than Guitar/Bass; following that
  would give the band different rhythms for one part. It costs Keys agreement (Easy most, about
  2.7 points). A test checks that the same rhythm as guitar, bass and keys gives identical onsets.
- **Guitar leads.** Where a rule could pick different notes in two instruments with the same
  rhythm (Hard's busy bars, Medium's chord choices), Bass, Keys and Pro Keys take Guitar's choice
  in bars of the same rhythm, unless that would remove one of their own protected notes. Guitar's
  tiers are planned in memory for this whether or not Guitar is in the run. *User rule.*
- **Keys follows Pro Keys** of the same song: see Keys, below.
- **Notes are kept or removed, not moved** - except Hard's fast-run rewrite (below).
- **Tuned to the official charts.** The gap and weight numbers were chosen as the best agreement
  with the official Guitar/Bass lower tiers, not just to pass Validate (whose Guitar/Bass
  spacing checks are advisories). Change one only by re-running that measurement.
- **Time signatures.** Compound meters (6/8, 9/8, 12/8) count in dotted quarters; every other
  meter in quarter notes from the bar line. Medium and Easy's beat grid is one beat of the meter,
  so neither plays three quarter notes across a 6/8 bar's two beats; Easy keeps the beats
  (*official:* 6/8 Easy keeps beat 1 97%, beat 2 94%). The 4/4 tables (bar positions, the busy-bar
  rule) apply only in 4/4; elsewhere an off-beat 8th goes sooner the stronger the beat it leads
  into, which is the 4/4 table's own order. Tempo is always quarter notes per minute.

### Every difficulty: which onsets survive

**A minimum gap between kept onsets** - `gap` (Hard 1/8, Medium 1/4, Easy 1/2 at most)
Each tier keeps the most valuable onsets at least a gap apart: the larger of a grid floor and a
time floor, so the same chart thins more at fast tempos, never more than the tier's note value.
*Official charts:* tuned for agreement with official Guitar/Bass. The cap: without it a whole
rhythm level vanished on fast songs (at 210 BPM Hard lost every off-beat 8th, Easy went to whole
notes); official Hard drops one or two off-beats of a bar of straight 8ths at every tempo, and
Easy keeps beats 1 and 3 at every tempo (93-97%).
*RBN doc:* Hard - "Removing motion or strumming that is a 16th note or faster, is a good place to
start"; Medium - "Removing the remaining 8th notes from Medium is a good way to thin out from Hard.
Try to only have playable notes on strong quarter note beats"; Easy - "remove all remaining
quarter notes when possible. It's good practice to leave half note spaces between strums".

**Which onsets are worth more** - `weight`, `sustain_bonus` 3.5
Downbeat > beat > 8th > triplet > 16th, plus a bonus for a held note - on Medium/Easy only when it
can still be held there. *Official charts:* tuned; 3.5 lets a held note on a beat win over a short
note on the bar line.
*RBN doc:* "If the strong beats of a song are the upbeats, or a syncopated rhythm, make sure not
to remove them in haste."

**Isolated notes stay** - `isolated_qn` 1.0
A note more than a quarter note from both neighbours is never removed by Hard's cap or busy-bar
rule, and stays on Medium. *Official charts:* Hard keeps a median 92% of Expert on the easiest
Keys songs; Medium keeps 99% of isolated off-beats.

### Hard

**Fast runs are rewritten one grid slower** - `Gen5RetimeDenseRuns`, "Hard fast runs" (`fast_runs_default`), `fast_8ths_bpm` 160, `retime_min_run`, `retime_color_penalty`
Notes closer than Hard's gap are not thinned in place but played again on the next slower grid -
16ths as 8th triplets, 8th triplets as 8ths - keeping the order of the colors. Above 160 BPM any
such run; at or below it, a run of half a bar or more. A long run sits on one grid aligned to the
beats, inside its first and last Expert note, unbroken where it crosses beat 3; a 16th rest ends
a run. A short group running straight into the next beat is laid out backward from it, so a group
cut to one note keeps the one that hammers into the beat. A short flourish from a beat into 8ths
(3 notes or fewer) is thinned instead. A run whose spacing changes is split into groups, each on
its own grid. Colors are mapped onto the new slots with as little movement as possible, a skip
that invents a color move costing extra.
*User rule:* official Hard never rewrites - it thins (Thin, the setting's official option; Auto
rewrites above 160 BPM only). The rule was fitted to the author's hand reduction of a 210 BPM
guitar solo and reproduces it (every note position, 165 of 170 colors). Rewritten bars are listed
in the result to review. In Rewrite mode Guitar Hard's agreement with official drops (85.4 ->
76.7): a rewritten note never lines up with an official one.
*RBN doc:* "When reducing a 16th note triplet for Hard, try removing the second or third note in
the triplet".

**Busy bars lose one or two notes** - `ThinBusyBars`, `busy_bar_onsets` 6, "Hard 8th runs"
A bar of 6+ onsets the gap left whole loses 1 or 2 notes (Auto: 2 when the song starts above 160
BPM), minus the 8th slots it already leaves empty - none when two or more are. The "and" of 2 and
the "and" of 4 go first; a chord in a bar mixing chords and single notes goes later, and last of
all a sustain or the bar's last note when the next downbeat is empty - so a run of chords ending
on the "and" of 4 before a rest keeps that note, held or short, and an earlier note goes.
*Official charts:* in busy Hard bars that lost an off-beat, the "and" of 4 before an empty downbeat
is kept 69-98% when short and 87-100% when held (Guitar, Bass and Keys, every tempo band), against
1-16% when a note follows on the downbeat; the "and" of 2 is then kept 3-46%. (Fewer cases: 6-33
songs per instrument and tempo band.)
*RBN doc:* "If the song is fast (over 160 bpm), the player shouldn't be expected to play
continuous 8th notes. Thin the chart out by removing every fourth note per half measure."
*Official charts:* Hard keeps 7 or 6 of 8 straight 8ths about equally often at every tempo -
hence the setting. *User rule* for the empty-slot discount (a bar with rests is already easier).

**Hard never equals Expert** - `max_keep` 0.95, `CapKeep`
A Hard keeping more than 95% of Expert's onsets loses whole bar positions across the song, the
position official Hard keeps least first ("the and of 4"), so a riff reduces the same way every
time it comes round. *User rule:* an Expert with no 16ths would otherwise pass untouched, and
Validate flags a copy.

**...or is eased by color** - `color_fallback_keep` 0.95, `color_fallback_top`
If Hard still keeps more than 95%, each bar moves down as a whole until its top note is Blue
(`O B Y` -> `B Y R`); Medium and Easy inherit it. *User rule.*

**Chords** - Hard keeps Expert's chords; no three-note chords, no Green + Orange.
*RBN doc:* "All chords in Expert should be retained in Hard unless special circumstances prevent
that making sense"; "Three note chords and Green/Orange chords are not permitted in Hard."

**Sustains: Expert's length, a 1/8 gap before the next note** - `release`
*RBN doc:* "Sustain durations in Hard should be the same as Expert unless the slower scroll rate
of the highway creates sustains that are too short visually."

**Hammer-on markers (Guitar/Bass)** - `difficulty_generate_hopo.lua`
Notes Expert forces to hammer on keep their marker on Hard where they survive; a hammer-on lost
by the reduction is restored only on rewritten notes (8th triplets turned 8ths), at most an 8th
apart, in runs of 2+. The hammer-on threshold is assumed to be the default (170 ticks).
*Official charts:* Hard keeps 77% of Expert's forced hammer-ons, and turns a lost automatic one
into a strum almost always (4% forced). *RBN doc:* forced hammer-ons "sparingly"; "Hopos should
not be forced on Medium or Easy". *User rule:* the restore on rewritten notes, which follows from
the rewrite.

### Medium

**A note per beat in busy bars** - `FillBeats`, `fill_beats`
A bar whose Hard has more onsets than beats keeps a note on each beat - removed onsets added back
at least an 8th from kept ones, never between two kept ones closer than a quarter.
*User rule:* official fast Medium keeps both of a beat + 8th-later pair only 5% of the time; this
costs Bass Medium about 1 point of agreement and keeps odd lick bars moving.

**A chord bonus** - `chord_bonus` 2.5
A chord next to a single note within the gap is worth more, so an 8th-later chord can win over a
beat single but not over a downbeat. *Official charts:* Medium keeps the chord of a beat single +
8th-later chord 83%, but a downbeat single over the chord before it 59%.

**The note that ends a phrase** - `phrase_end_bonus` 5, `PhraseEnds` (Medium and Easy)
The bar's last note on its last "and", before an empty next downbeat, is worth 5 more - a phrase
end (3 + 5) then outweighs a beat-4 chord next to it (5 + 2.5), so Medium plays `1 2 3 &4` where
the tier above ends a run of chords on the "and" of 4, held or short. Only when the note after it
is at least the tier's gap away, so keeping the phrase end never costs the note that starts the
next phrase. Same position in other simple meters (the "and" of 3 in 3/4).
*Official charts:* where Hard has both beat 4 and the "and" of 4 before an empty downbeat, Medium
keeps the "and" 90-100% for a held note and 49-92% for a short one (Guitar and Bass 140+ BPM:
67-92%), beat 4 0-49%, both rarely (0-18%; Keys held notes 41%).

**Isolated off-beats, and a Medium that barely differs from Hard** - `offbeat_fallback_keep` 0.95
A Medium keeping more than 95% of Hard first drops its isolated off-beats, then is eased by color
(top note Yellow). *User rule:* official Medium on such simple parts keeps every isolated off-beat
(560 of 560) and changes colors and chord sizes instead; removing a note was preferred to
recoloring a line.

**Colors under the top lane** - `color_shift` 'clamp', `Gen5ClampOrShiftBars`
Notes above the tier's top lane move down (a chord whole); if that creates a same-color repeat
the tier above does not have, the whole bar moves down instead (`G O Y B` -> `G B Y B`, but
`G Y B O` -> `G R Y B` rather than `G Y B B`). The other modes, kept for comparison: 'bars'
moves every such bar down whole; 'segments' moves each passage down whole, a passage ending at a
rest longer than `segment_gap` (a quarter) and lasting at most `segment_max` (two bars).
*Official charts:* the best color agreement of the options measured (Guitar/Bass Medium 60.8 /
69.8%). *RBN doc:* "Try starting by moving every chord in the song down one position."

**Chords** - two-note chords only; no Green + Blue, Green + Orange or Red + Orange.
*RBN doc:* "Do not use the Green/Blue, Green/Orange, or Red/Orange chords in Medium"; "Do not use
any three finger chords in Medium".

**Sustains** - `min_sustain` (0.75 QN, 1.0 above `fast_bpm` 160: `min_sustain_fast`), `release` (`release_fast` above 160)
A sustain shorter than the minimum becomes a plain note; the rest leave a dotted-8th gap (a
quarter above 160 BPM) before the next note.
*RBN doc:* "try and leave a quarter note between the end of a note and the beginning of the next
... if a note tail looks too short, pull that note back to a 16th." *Official charts:* fast Medium
never has a sustain under 0.875 QN.

**Bass and Keys follow Guitar's Medium** in bars of the same Hard rhythm - `opts.rhythm_ref`.
*User rule* (Guitar leads).

**A rewritten note goes back to its beat** - `SnapRewrittenToBeats`
Where Hard's rewrite left an Expert beat empty, the rewritten note nearest to it (within a 16th)
returns to that beat on Medium and Easy, so the beat is not left empty below Hard.

**6/8: the beat and the 8th after it** - `TierGapQN`
*Official charts:* 6/8 Medium's commonest bar of six 8ths keeps 0, 0.5, 1.5, 2 (164 of 335).
*User rule* to follow it: before, Medium and Easy were identical in steady 6/8 bars.

### Easy

**The note that ends a phrase** - `phrase_end_bonus` 5, `phrase_end_gap` 1.5
As on Medium, and it may sit 1.5 quarter notes after the previous kept note where Easy's gap
would ask for more (at 154 BPM, 1.8) - beat 3 and the "and" of 4 both stay.
*Official charts:* Easy keeps an "and" of 4 before an empty downbeat 69-100% (held notes 94-100%);
the commonest gap back to the previous Easy note is 1.5 quarter notes at every tempo.

**No chords.** Guitar/Bass keep the lowest note; Keys the top note (see Keys).
*RBN doc:* "There are no chords in easy."

**Sustains** - `min_sustain` 1.0 QN, `release` (a quarter; a half above 160 BPM, `release_fast`)
*RBN doc:* "leaving at least a 1/4 note gap between the end of a sustain and the beginning of the
next note".

**A tail kept through the chain** - `FixLengths`, `qn_e_full`
When Easy inherits a tail Medium shortened for a note Easy drops, and the tail is under Easy's
minimum, it is stretched back to the minimum, no further.

### Keys

**Keys follows Pro Keys** - `SelectByGuide`
Keys plays exactly Pro Keys' onsets on every tier, at Pro Keys' positions (a rewritten Pro Keys
run sits on 8th triplets); each Keys note keeps its own color. In All instruments Keys follows the
Pro Keys just generated; on its own it reads the Pro Keys track, and without Pro Keys it is
planned like Guitar. A Pro Keys note with no Keys note within a 32nd is listed in the result.
*Official charts:* official Pro Keys and Keys onsets agree 89-96% per tier. *User rule* to make it
exact.

**Chords keep their top notes** - `Gen5ReduceChordSizeKeys`
On every tier, including Easy's single note. *Official charts:* Keys keeps the top note going to
one note 52-70% (the bottom 25-32%).

**Easy keeps the line moving** - `Gen5KeysEasyMotion`
The same Medium chord keeps the previous Easy note; a different chord whose note would repeat the
previous one takes another chord note, from the top down. *Official charts:* Easy repeats a note
on 27.0% of steps (official 27.9%); repeats the reduction itself created 1.4% (official 2.4%,
10.2% without this rule).

**A lick that starts on an "and"** - `Gen5AndPhrases`, `and_phrase` (Keys and Pro Keys)
A phrase entering on an "and" whose "and"s change note more often than its beats is reduced on
Medium on the "and" grid - the "and"s weigh as beats - and Easy goes back to Hard's beat notes
there. *User rule:* from the author's hand chart of a 120 BPM test song (beats B B C C, "and"s
B G C A); official Medium goes "and"-led in 30% of such Keys/Pro Keys phrases, and note variety
barely predicts which. Agreement cost under 0.2 points.

**Held notes under moving notes** - `difficulty_generate_overlaps.lua`
A note Expert holds while later notes start keeps sounding on Hard within the limits (5-lane 3
notes sounding, Pro Keys 4 within an octave); over the limit the new chord loses notes first,
then the earliest held note ends. Medium holds only over a note a bar or more later (2 notes);
Easy never. *RBN doc:* "Up to 4 notes in Pro Keys Expert / Hard & 3 notes in 5 lane Expert /
Hard. Generally no overlapping notes are allowed in Medium. In some rare cases we will add 2 note
overlaps if they are spaced out over a ½ note or more. Not allowed in Pro Keys Easy or 5 Lane
Easy." *Official charts* decide Hard overlaps per song (about half keep none, a sixth all).

**Rolled chords become one chord** - `GenMergeRolls` (Hard)
Onsets closer than Hard's gap, all held past the last one, the last a sustain: one chord on the
roll's strongest beat position. *User rule.*

---

## Pro Keys

`difficulty_generate_prokeys.lua` (`GenPKPlanTier`), one track per difficulty. The rhythm is the
same as every instrument's (`Gen5SelectOnsets`), including Hard's fast-run rewrite and following
Guitar. Measured on the official Pro Keys charts (about 350 songs).

**Chords lose notes from the bottom**
Hard: 3 notes within a 7th; Medium: 2 within a 6th; Easy: one note.
*Official charts:* the top note stays 70-80%. *RBN doc:* "Hard PK should only contain 2- and
3-note chords, within the span of a 7th (11 semitones)"; Medium "only ... 2-note chords, and only
within the span of a 6th (9 semitones)"; Easy "Reduce all chords to the most prominent and
musically sensible single note."

**Hard keeps Expert's pitches and lane shifts**
A lane shift whose notes already fit the window showing is dropped; with no lane shift in Expert,
Hard gets a best-fitting one before its first note.
*Official charts:* Hard keeps Expert's pitches exactly 78% (a subset 18%) and its lane shifts
87%. *RBN doc:* "make sure to remove lane shifts that are no longer needed after reducing from
Expert".

**Medium and Easy show one window for the whole song** - `GenPKUpperWindow`, `GenPKBestWindow`
Medium keeps Hard's window when Hard shows one window all song, otherwise the window that fits the
most notes (then C, F, A, E, D, G); Easy keeps Medium's. Notes outside the window move by the
smallest number of octaves that fits, a chord whole when it fits; notes inside never move, so the
same note always lands on the same key.
*RBN doc:* "Lane shifts are not allowed on Medium PK"; Easy "the visible range should match that
of Medium"; "Try to primarily use the ranges of C-2 (C2-E3 range), F-2 (F2-A3 range), and A-2
(A2-C4 range)". *Official charts:* Medium keeps Hard's single window in 126 of 136 such songs;
Generate's Easy matches the official window in 96% of songs, Medium in 63%.

**Sustains leave room to move** - Hard 1/16 (simple transition) or 1/8, Medium and Easy a quarter
A sustain cut under 3/16 becomes a 1/16 note.
*RBN doc:* Expert/Hard "leave a 1/16th note space ... between two chords or between a chord and a
non-complementary note, leave an 1/8th note space"; Medium "All sustains should be pulled back to
leave a 1/4th note space ... (shorter than 3/16ths in duration ...) it may need to be pulled back
into a 1/16th note".

**Hard equal to Expert asks first** - `GenPKSameAsUpper`, `PullBackSustains`
If Hard would equal Expert exactly, Generate asks before writing: shorten the sustains (1/16 before
a simple transition or a phrase end, 1/8 otherwise) or keep Hard as Expert.
*Official charts:* charters decide per song, nearly all or nothing (41 of 275 songs pull back 75%+
of Hard's sustains, 185 under 5%).

**Interval jumps are not changed.** *RBN doc* asks to avoid jumps over a 7th (Hard), 6th (Medium),
5th (Easy), or leave extra space; Generate leaves them for the author (Validate lists them).
