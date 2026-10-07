-- Difficulty > Generate: the parameters and small rules every planner shares - the
-- tuned numbers (GEN5_PARAMS), beat classes, gaps, sustain minimums and release gaps.
--
-- PURE: no r, no S. Loaded first of the Generate modules; difficulty_generate_rhythm.lua
-- and difficulty_generate_5lane.lua bind Gen5MinGapQN, Gen5MinSustainQN,
-- Gen5ReleaseGapQN and the GEN5_* constants at load time.
--
-- Requires (globals, read at call time): DiffReleaseGapQN (actions_difficulty_shared.lua).

-- ONE RHYTHM MODEL FOR EVERY INSTRUMENT. Which onsets a tier keeps depends only on where
-- the onsets are (and the tempo), never on their colors, chords or instrument, and every
-- instrument uses the same numbers. So Guitar, Bass, Keys (and Pro Keys, when it gets a
-- planner) that play the same rhythm on Expert play the same rhythm on Hard, Medium and
-- Easy. Chords and colors are reduced afterwards and never change which onsets survive.
-- This is a product choice: official Keys Hard keeps more of Expert than Guitar/Bass does,
-- and following that would give the band different rhythms for the same part.
-- One exception, and how it is kept in line: a busy bar on Hard saves its sustains and
-- accent chords for last (ThinBusyBars), so two instruments with the same rhythm could
-- lose different notes. Guitar leads there - Bass and Keys take Guitar's choice in a bar
-- of the same rhythm (opts.busy_ref) unless that would remove their own protected note.
GEN5_PARAMS = {
    -- Minimum onset-to-onset gap a tier keeps: the larger of a grid floor (quarter notes)
    -- and a time floor (seconds), so the same chart thins more at fast tempos.
    --
    -- TUNED, not chosen: the best onset F1 against the official Guitar/Bass tiers over the
    -- development songs (run_generate_eval_offline.lua tune; hold-out excluded). Change a
    -- value only by re-running that sweep.
    --
    -- cap: the gap never exceeds the tier's note value (Hard 1/8, Medium 1/4, Easy 1/2).
    -- Without it the time term crossed the next note value on fast songs and a whole
    -- rhythm level vanished at once - at 210 BPM Hard lost every off-beat 8th, Medium
    -- every other beat, Easy went to whole notes. Official charts do none of that: for a
    -- bar of straight 8ths, Hard drops one or two off-beats at every tempo (dropping all
    -- of them is 2-4%), and Easy keeps beats 1 and 3 at every tempo (93-97%). Past the
    -- cap, fast passages are thinned by bar position (busy_bar_onsets / busy_drop).
    gap = {
        H = { grid = 0.5, sec = 0.15, cap = 0.5 },
        M = { grid = 1.0, sec = 0.30, cap = 1.0 },
        E = { grid = 1.0, sec = 0.70, cap = 2.0 },
    },
    -- How much an onset is worth keeping, by beat position. The thinning keeps the
    -- highest total weight that respects the gap, so these decide WHICH notes go.
    weight = { down = 8, beat = 5, ['8th'] = 3, ['16th'] = 1.5, trip = 2, other = 1 },
    -- An onset holding a sustain (SUSTAIN_QN or longer) is worth this much more. Note
    -- length is part of the rhythm, so this does not break the one-rhythm rule. 3.5 makes
    -- a sustain on a beat (5 + 3.5) win over a short note on a bar line (8) when only one
    -- fits - Easy kept the short downbeat and dropped a long held note at exactly 3.0.
    -- Offline F1 is unchanged or better on every tier against 3.0 (tune sweep).
    sustain_bonus = 3.5,
    -- On Medium and Easy the bonus counts only when the note can still be a sustain there:
    -- held to the next upper onset less the tier's release gap, at least min_sustain.
    -- A note whose tail the tier would cut anyway is just a note (chronosp bar 7: a held
    -- note on 3& won over beat 3 on Medium, and was then cut to a 1/8 tail).
    -- Shortest sustain each tier keeps; shorter ones become plain notes. Measured on the
    -- official RB3 DLC Guitar/Bass (dev songs): Medium sustains above 160 BPM are never
    -- under 0.875 QN (1st percentile 1.0), at <= 160 BPM 1st percentile 0.75; Easy 1.0
    -- both. Hard stays at the 1/8 every tier used before.
    min_sustain      = { H = 0.5, M = 0.75, E = 1.0 },
    min_sustain_fast = { M = 1.0, E = 1.0 },
    -- A chord is worth this much more on Medium: an "and" chord (3 + 2.5) outweighs a beat
    -- single (5) but not a downbeat (8). Official Medium keeps the chord of a beat single
    -- and an 8th-later chord 83% of the time (8748 vs 894), but a downbeat single over the
    -- chord before it 59% (387 vs 221). Chord size is not rhythm, so Bass and Keys follow
    -- Guitar's Medium in bars of the same rhythm (opts.rhythm_ref).
    chord_bonus = { M = 2.5 },
    -- Medium keeps a note per beat in busy bars (FillBeats). A switch so the evaluator can
    -- measure what it costs against official charts.
    fill_beats = { M = true },
    -- A keys lick that starts on an "and" (Gen5AndPhrases): Medium reduces the phrase on
    -- the "and" grid - the "and"s weigh as beats - and Easy goes back to Hard's downbeats
    -- there. A phrase is a run of upper-tier onsets with no gap of `rest` or more, at least
    -- `min_onsets` long; it qualifies when its first onset is on an "and" AND its "and"
    -- line changes note more often than its beat line by more than `variety_margin`
    -- (changes per step). korpiklaani_juo_viinaa: the lick enters on the and of 4, its
    -- beats repeat (B B C C) and its "and"s move (B G C A); the user's hand Medium kept
    -- the "and"s. A PRODUCT RULE, not official practice: official Medium goes "and"-led in
    -- 30% of Keys / Pro Keys phrases that enter on an "and" (7% of beat entries), and note
    -- variety barely predicts which (20-25% even in this shape). Keys and Pro Keys only
    -- (`kinds`), the user's choice; Guitar/Bass official 20% / 16%.
    and_phrase = { kinds = { k5 = true, pk = true }, rest = 2.0, min_onsets = 8, variety_margin = 0.2 },
    -- Most of the upper tier's onsets a tier may keep (nil = no cap). Above it, whole bar
    -- positions are removed across the song (CapKeep), so a sparse chart still gets a
    -- visibly easier tier: without a cap, an Expert with no 16ths passes the Hard gap
    -- untouched and Validate flags an unchanged copy. A product choice, not tuned.
    max_keep = { H = 0.95 },
    -- A bar the gap left completely untouched, with at least this many onsets, still
    -- loses a note (ThinBusyBars). The song-wide cap above misses such bars when the rest
    -- of the song already thinned enough - a passage of steady 8ths between 16th runs
    -- came through Hard identical to Expert. Hard only; the Medium and Easy gaps always
    -- thin 8ths.
    busy_bar_onsets = { H = 6 },
    -- How many notes a bar of straight 8ths loses: 1 (the and of 4) or 2 (also the and of
    -- 2 - "two groups of three"). A bar that already leaves 8th slots empty loses that
    -- many fewer, never fewer than one. Chosen by the caller (opts.busy_drop); left unset it is decided
    -- once per song from the tempo at the first note: 2 above fast_8ths_bpm. The RBN
    -- Guitar/Bass and Keys docs: "If the song is fast (over 160 bpm), the player shouldn't
    -- be expected to play continuous 8th notes. Thin the chart out by removing every
    -- fourth note per half measure." Official Hard keeps 7 or 6 of 8 straight 8ths about
    -- equally often at every tempo, so the user can override it per song.
    fast_8ths_bpm = 160,
    -- Above fast_8ths_bpm, Hard rewrites runs closer than its gap one grid slower (16ths to
    -- 8th triplets, 8th triplets to 8ths) instead of thinning them in place - see
    -- difficulty_generate_retime.lua. The penalty (in 1/24 QN of movement) is what a skip
    -- that invents a color move costs; 20 matched the chronosp_brutal_decay hand reduction
    -- best of the variants tried (165 of 170 colors).
    retime_color_penalty = 20,
    -- An onset is ISOLATED when its gaps to both neighbouring upper-tier onsets are more
    -- than this (quarter notes). Spacing only, so it keeps the one-rhythm rule.
    -- Hard never removes an isolated onset through the cap or the busy-bar rule: on a
    -- sparse chart (a beginner Keys part of long sustains and a few dotted-quarter notes)
    -- those removals made Hard thinner than official Hard, which keeps a median 92% of
    -- Expert on the easiest Keys songs. Medium keeps them too: it used to drop isolated
    -- OFF-BEAT onsets (the RBN tip "Try to only have playable notes on strong quarter note
    -- beats"), but official Medium keeps 99% of them (935 of 943 above 160 BPM, 4033 of
    -- 4106 at or below; RB3 DLC Guitar/Bass dev songs), and Medium F1 rose on every
    -- instrument without the drop (chronosp bass bar 52 lost its 4& note to it).
    isolated_qn = 1.0,
    -- When a tier keeps more than this share of the upper tier's onsets, the rhythm barely
    -- changed, so it is made easier by color instead: each bar moves down as a whole until
    -- its top note is color_fallback_top - Hard Blue (O B Y -> B Y R), Medium Yellow.
    -- Colors only; the tiers below inherit it. Medium tries offbeat_fallback_keep first.
    color_fallback_keep = { H = 0.95, M = 0.95 },
    color_fallback_top  = { H = 3, M = 2 },   -- Blue, Yellow
    -- Medium that keeps more than this share of Hard first drops its isolated off-beats
    -- (isolated_qn), and only if it still keeps too much is eased by color. A product
    -- choice, not official practice: official Medium on such simple parts keeps them all
    -- (560 of 560 in 58 parts) and changes colors and chord sizes instead. The user prefers
    -- removing a note to recoloring a line (pojat_lemmikkih Keys, where Medium came out
    -- the same as Hard but for sustain lengths).
    offbeat_fallback_keep = { M = 0.95 },
    -- Gap left between a sustain's end and the next note - what each tier aims for.
    -- Hard 1/8, Medium a dotted 8th, Easy a quarter; above fast_bpm, Medium a quarter and
    -- Easy a half note. Medium and Easy never go below DiffReleaseGapQN, the floor Validate
    -- enforces. A sustain that cannot leave this gap and stay 1/8 or longer becomes a 1/32
    -- note, so it clearly reads as a plain note.
    release      = { H = 0.5, M = 0.75, E = 1.0 },
    release_fast = { M = 1.0, E = 2.0 },
    fast_bpm     = 160,
    -- A rest longer than this (quarter notes) ends a color-shift segment, and a segment
    -- is never longer than segment_max: Guitar/Bass Medium/Easy shift a passage down as a
    -- whole, the way official charts move lines down a lane. Longer, not "at least": a
    -- Medium line is mostly quarter notes, and splitting at every quarter moved only the
    -- top note of a line (chronosp bar 10: G Y B O became G Y B B, a repeat Hard never had).
    segment_gap = 1.0,
    segment_max = 8.0,
    -- How Guitar/Bass Medium/Easy bring notes under their top lane:
    --   'clamp'    - only the notes above it move down, unless that makes a color repeat
    --                the tier above does not have; then the whole bar moves down
    --                (Gen5ClampOrShiftBars - pojat bar 3 G O Y B -> G B Y B, chronosp
    --                bar 10 G Y B O -> G R Y B rather than G Y B B);
    --   'bars'     - every such bar moves down whole (Gen5ShiftBars);
    --   'segments' - each passage moves down whole (Gen5ShiftSegments, segment_gap).
    -- Color agreement with official charts (run_generate_eval_offline.lua), Guitar/Bass:
    -- Medium 60.8/69.8% clamp, 58.1/68.6% bars, 56.9/67.7% segments (58.8/67.4% with the
    -- old split at every quarter); Easy 67.1/70.2%, 66.5/69.4%, 66.2/69.3% (66.6/69.4%).
    color_shift = 'clamp',
}

-- Shared limits, in quarter notes. Global so every Generate module uses the same values.
GEN5_SUSTAIN_QN = 0.5     -- a note this long or longer counts as sustained (1/8 note)
-- Shortest note written (1/32 note), and so the closest two kept onsets may be. Validate
-- rejects anything under 1/64; upper tiers sometimes carry near-zero lengths and flams
-- a few milliseconds apart, which would otherwise be copied straight through.
GEN5_MIN_LEN_QN = 0.125
GEN5_EPS        = 0.02    -- quarter-note tolerance for "on the grid" and gap tests

local SUSTAIN_QN = GEN5_SUSTAIN_QN
local EPS        = GEN5_EPS

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

-- Beat position of an onset: down (bar line), beat, 8th, 16th, trip, other.
function Gen5BeatClass(ev)
    if ev.down then return 'down' end
    local qn = ev.qn
    if NearInt(qn, EPS)         then return 'beat' end
    if NearInt(qn * 2, EPS * 2) then return '8th'  end
    if NearInt(qn * 4, EPS * 4) then return '16th' end
    if NearInt(qn * 3, EPS * 3) or NearInt(qn * 6, EPS * 6) then return 'trip' end
    return 'other'
end

-- Minimum onset-to-onset gap tier dl keeps at this tempo (GEN5_PARAMS.gap).
function Gen5MinGapQN(dl, bpm)
    local g = GEN5_PARAMS.gap[dl]
    return math.min(math.max(g.grid, g.sec * (bpm or 120) / 60), g.cap or math.huge)
end

-- Shortest sustain tier dl keeps at this tempo (GEN5_PARAMS.min_sustain).
function Gen5MinSustainQN(dl, bpm)
    local p = GEN5_PARAMS
    if (bpm or 120) > p.fast_bpm and p.min_sustain_fast[dl] then return p.min_sustain_fast[dl] end
    return p.min_sustain[dl] or SUSTAIN_QN
end

-- Gap a sustain must leave before the next note on this tier.
function Gen5ReleaseGapQN(kind, dl, ev)
    local p = GEN5_PARAMS
    local need = p.release[dl] or 0.25
    if (ev.bpm or 120) > p.fast_bpm and p.release_fast[dl] then need = p.release_fast[dl] end
    local floor = DiffReleaseGapQN(dl, ev.bpm)
    if floor and floor > need then need = floor end
    if kind == 'k5' and (dl == 'H' or dl == 'X') and #ev.offs > 1 then
        need = math.max(need, 0.5)   -- Keys X/H: 1/8 after a sustained chord
    end
    return need
end
