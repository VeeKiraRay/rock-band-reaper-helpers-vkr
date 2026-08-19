-- Reading a Rock Band chart off REAPER tracks, for difficulty scoring.
--
-- The REAPER-facing half of the difficulty suggester: it turns tracks into the plain
-- tables lib/reaper_difficulty_score.lua and lib/reaper_difficulty_score_vocals.lua
-- consume, so those stay pure and unit-testable. In particular it attaches a `qn` field
-- to every event - the scorer needs grid-relative spacing but must not call
-- TimeMap2_timeToQN itself.
--
-- ONE IMPLEMENTATION, TWO CONSUMERS, and here that matters more than it does for the
-- pure scorers. Every number in dev/calibration/corpus_scores.csv - and therefore every
-- fitted coefficient - was produced by these exact readers. A second copy in the product
-- would not merely risk drifting: any difference at all, in the chord-grouping window, in
-- which pitches are read, in how a marker span is closed, silently makes the shipped
-- suggestion a different measurement from the one the model was fitted against. These
-- functions started life in dev/calibration/corpus.lua, which now loads this file.
--
-- Uses only r.* plus NormalizeSpans / NormalizeVocalPhrases from the two pure scorers.
-- No S, no ctx, no TIPS - so the calibration harness can load it without dragging in the
-- helper's state, and dev/tests can drive it against a generated MIDI item.
--
-- Requires (globals): r, NormalizeSpans, NormalizeVocalPhrases

----------------------------------------------------------------------
-- Animation state vocabulary
----------------------------------------------------------------------

-- Verified against all 155 reference MIDIs. Every PART track carries its own
-- set, so no cross-track lookup is needed for the 5-lane instruments (Pro Keys
-- would read PART KEYS's, since PART REAL_KEYS_* carries none).
--
-- [play_solo] and [idle_intense] are easy to miss - 380 events between them
-- across the corpus. [mellow] and [intense] are intensity modifiers on a
-- playing state, not states of their own.
--
-- Deliberately NOT here: [tambourine_*], [cowbell_*], [clap_*]. Those share the
-- bracketed namespace but mark vocalist percussion sections, and appear only on
-- PART VOCALS and HARM1.
ANIM_PLAYING = {
    ['[play]'] = true, ['[play_solo]'] = true,
    ['[mellow]'] = true, ['[intense]'] = true,
}
ANIM_IDLE = {
    ['[idle]'] = true, ['[idle_realtime]'] = true, ['[idle_intense]'] = true,
}

----------------------------------------------------------------------
-- Track lookup
----------------------------------------------------------------------

-- Exact, case-insensitive name match.
--
-- NOT a substring search, and not FindFixtureTrack: these MIDIs carry
-- 'PART KEYS_ANIM_LH' beside 'PART KEYS' and 'PART REAL_KEYS_E' before
-- 'PART REAL_KEYS_X', so a substring match returns the wrong track. Searches
-- from from_idx so a run can ignore tracks that existed before the import.
function FindTrackExact(name, from_idx)
    local want = name:lower()
    for i = (from_idx or 0), r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, nm = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        if nm:lower() == want then return tr end
    end
    return nil
end

----------------------------------------------------------------------
-- Reading a track
----------------------------------------------------------------------

-- Latest end time across a track's MIDI items, used to close a playing span
-- that never gets an explicit idle event.
local function TrackEndTime(track)
    local last = 0
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local pos  = r.GetMediaItemInfo_Value(item, 'D_POSITION')
        local len  = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
        if pos + len > last then last = pos + len end
    end
    return last
end

-- Chord events in pitch range [lo, hi], grouped by shared onset, each carrying
-- its quarter-note position. Sorted by time; pitches ascending.
--
-- Mirrors ReadGBNotes + GroupGBChords in actions_difficulty_gtrbass.lua (2 ms
-- chord window, muted notes skipped) rather than reusing them, because those are
-- file-locals.
--
-- The pilot has since graduated, and the obvious follow-up - fold the five
-- near-duplicate gem readers in this script into one shared copy - is deliberately
-- NOT done here. This reader is now the measurement the fitted coefficients were
-- calibrated against, so unifying it with the difficulty-tier readers would put a
-- refactor of unrelated code on the critical path of every future rescore. Do that
-- from the other direction: move the tier readers onto this one, with a diff run
-- (run_calibration_diff_vkr.lua) proving no factor moved.
function ReadGemEvents(track, lo, hi)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= lo and pitch <= hi then
                    notes[#notes + 1] = {
                        s     = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                        e     = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                        pitch = pitch,
                    }
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)

    local events = {}
    local i = 1
    while i <= #notes do
        local ev = { s = notes[i].s, e = notes[i].e, pitches = { notes[i].pitch } }
        local j  = i + 1
        while j <= #notes and notes[j].s - ev.s <= 0.002 do
            ev.pitches[#ev.pitches + 1] = notes[j].pitch
            if notes[j].e > ev.e then ev.e = notes[j].e end
            j = j + 1
        end
        table.sort(ev.pitches)
        -- The scorer is pure and cannot do these itself. qn_e is what lets it
        -- measure note length in grid terms rather than seconds.
        ev.qn   = r.TimeMap2_timeToQN(0, ev.s)
        ev.qn_e = r.TimeMap2_timeToQN(0, ev.e)
        events[#events + 1] = ev
        i = j
    end

    -- HELD notes: pitches already sounding at this onset because they were struck
    -- earlier and have not ended.
    --
    -- WHY THIS EXISTS, and why it is not a guitar concern. The guitar/bass authoring
    -- rules forbid overlapping notes outright ("Notes should not overlap. Any note
    -- that begins before the end of the previous..."), and the corpus honours it - a
    -- census over PART GUITAR and PART BASS found 0 overlapped onsets in 5826. So on
    -- those instruments `held` is always empty and every factor below is unchanged.
    --
    -- 5-lane KEYS deliberately allows it: overlapping gems represent broken chords, up
    -- to three at a time. A green held for a measure under a moving melody is one
    -- sustained note plus a melody, and grouping strictly by onset describes that as a
    -- run of single notes - which misleads three separate factors at once
    -- (chord_size_mean reads 1.0 while two fingers are committed, PitchSetChanged
    -- counts a change for a note that never stopped, and hand movement measures travel
    -- the hand never made). `held` is what lets the scorer tell the two apart.
    --
    -- A forward sweep over an active set, not a backward scan per event: notes are
    -- already sorted by onset, so each note is added once and dropped once and the
    -- active set only ever holds what is currently sounding (a handful, capped at 3 by
    -- the authoring rules). Scanning backwards from the end of the track per event
    -- would be quadratic on a 1300-note chart.
    local active, ni = {}, 1
    for _, ev in ipairs(events) do
        -- Everything that has started by this onset joins the active set.
        while ni <= #notes and notes[ni].s <= ev.s + 0.002 do
            active[#active + 1] = notes[ni]
            ni = ni + 1
        end
        -- Everything that has ended leaves it.
        local still = {}
        for _, n in ipairs(active) do
            if n.e > ev.s + 0.002 then still[#still + 1] = n end
        end
        active = still

        local struck = {}
        for _, p in ipairs(ev.pitches) do struck[p] = true end
        local held = {}
        for _, n in ipairs(active) do
            -- Strictly earlier onset, and not re-struck at this instant. The 2 ms
            -- window matches the chord grouping above, so a note belonging to THIS
            -- event can never also be counted as held.
            if n.s < ev.s - 0.002 and not struck[n.pitch] then held[n.pitch] = true end
        end
        ev.held = {}
        for p in pairs(held) do ev.held[#ev.held + 1] = p end
        table.sort(ev.held)
    end
    return events
end

-- Counts of the two strum-override marker notes, returned SEPARATELY.
--
-- They sit just above a difficulty's gem range (101 and 102 for Expert's 96-100),
-- which the gem window deliberately excludes - they are not playable notes.
--
-- Counting them as one number was a mistake: the two markers push difficulty in
-- OPPOSITE directions. lo+5 forces a HOPO onto notes the engine would not have
-- auto-HOPO'd, removing a required strum, which makes the passage easier. lo+6
-- forces a strum back onto notes the engine would have auto-HOPO'd, which makes it
-- harder. Summed, they cancel.
--
-- Both are also closer to authoring intent than to difficulty - a chart only needs
-- them where the engine's automatic behaviour is not what the author wanted - so
-- expect small coefficients either way.
--
-- Returns force_hopo_count, force_strum_count.
function CountStrumOverrides(track, hopo_pitch, strum_pitch)
    local n_hopo, n_strum = 0, 0
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, _, _, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted then
                    if     pitch == hopo_pitch  then n_hopo  = n_hopo + 1
                    elseif pitch == strum_pitch then n_strum = n_strum + 1 end
                end
            end
        end
    end
    return n_hopo, n_strum
end

-- Sustained marker notes, as spans. Merged and sorted, so they can be handed
-- straight to the scorer's span arithmetic.
--
-- These pitches are the authored, GAMEPLAY-RELEVANT annotations - the ones that
-- change what the player has to do - and until now every one of them was thrown
-- away. ReadGemEvents takes 96-100 and CountStrumOverrides takes 101/102;
-- nothing read above that.
--
--   103  solo section
--   126  tremolo lane      (one note repeated fast)
--   127  trill lane        (two notes alternating fast)
--
-- Each is ONE long note covering the whole section, which is why they need a
-- span reader rather than the per-note counting CountStrumOverrides does.
--
-- ABSOLUTE PITCHES, NOT DIFFICULTY-RELATIVE. This is worth stating because the
-- neighbouring FORCE_HOPO_PITCH = EXPERT_LO + 5 establishes the opposite pattern
-- and 103 happens to equal EXPERT_LO + 7, so the relative form looks right and
-- is wrong. A solo covers the same bars on every difficulty, so it is marked
-- once; verified against the corpus, where the lo+7 slots for Hard/Medium/Easy
-- (91/79/67) are empty.
--
-- Not read: 116 (overdrive). Measured across four songs at 8-11% of the track
-- regardless of rank, i.e. placed by a near-mechanical rule, so it carries
-- phrase structure rather than difficulty. Recorded here so it is not
-- re-derived later as an oversight.
function ReadMarkerSpans(track, pitch)
    local spans = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, p = r.MIDI_GetNote(take, j)
                if ok and not muted and p == pitch then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
                    if e > s then spans[#spans + 1] = { s = s, e = e } end
                end
            end
        end
    end
    -- Sorted and disjoint, the shape every span consumer in difficulty_score.lua
    -- assumes. NormalizeSpans is a global from that module.
    return NormalizeSpans(spans)
end

----------------------------------------------------------------------
-- VOCALS
--
-- A different shape from every gem instrument: the difficulty lives in the LYRIC
-- TEXT attached to each note, not in the note pitches, and the scoring unit is the
-- authored phrase rather than the whole song.
----------------------------------------------------------------------

VOCAL_LO, VOCAL_HI = 36, 84   -- pitched syllables. C1..C5, per the authoring doc.

-- Sung notes with their lyric text, in time order.
--
-- THE LYRIC ASSOCIATION IS BY TICK, AND THAT RULE IS LOAD-BEARING. Every note in a
-- vocal part carries a lyric event placed exactly at the note's onset, so the pairing
-- is "same PPQ", not "next text event". Measured over all 204 corpus vocal tracks:
-- text events landing on a 36-84 onset number 78,890 - EXACTLY the note count - and
-- every one of the 204 tracks matches exactly.
--
-- TWO TRAPS, both of which cost real rows if handled the obvious way:
--
--   1. LYRICS ARE NOT ALWAYS TYPE 5. `CLAUDE.md` and the design doc both say "type 5 =
--      lyric", and 40 corpus songs store them as type 1 TEXT instead - 32 of them
--      rb3_dlc, i.e. a fifth of the gate corpus, so this is not an old-pack quirk.
--      Both types are read.
--   2. DO NOT FILTER BY BRACKETS. Type-1 lyrics share their stream with the animation
--      states, so the tempting fix is to drop anything matching '^%[.*%]$'. One corpus
--      event is `[intense]#`, which that pattern does NOT match because of the trailing
--      '#' - it would be kept and counted as a talkie. Tick alignment drops it, along
--      with the corrupted text events a few tracks carry, and needs no vocabulary.
--
-- Returns an array of { s, e, qn, qn_e, pitch, lyric }, plus the count of text events
-- that were discarded for not landing on an onset (diagnostic only).
function ReadVocalNotes(track)
    local notes, by_tick = {}, {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= VOCAL_LO and pitch <= VOCAL_HI then
                    local n = {
                        s     = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                        e     = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                        qn    = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                        qn_e  = r.MIDI_GetProjQNFromPPQPos(take, eppq),
                        pitch = pitch,
                        lyric = nil,
                    }
                    notes[#notes + 1] = n
                    -- Keyed per take: PPQ is take-relative, so two takes can share a
                    -- tick number without sharing a moment.
                    by_tick[take] = by_tick[take] or {}
                    by_tick[take][sppq] = n
                end
            end

            local _, _, _, textcnt = r.MIDI_CountEvts(take)
            for j = 0, textcnt - 1 do
                local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, j)
                -- Type 1 = text, type 5 = lyric. Both carry lyrics in this corpus.
                if ok and (evt_type == 1 or evt_type == 5) then
                    local n = by_tick[take] and by_tick[take][ppq]
                    if n and not n.lyric then n.lyric = msg end
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Phrase markers. PITCH 105 AND 106 BOTH COUNT: 105 is the modern marker (200 of 204
-- corpus tracks) and 106 is the RB1/RB2-era second marker, present in 38 more. Reading
-- only 105 would leave those songs with no phrase structure at all, which the scorer
-- would then read as "never sings".
--
-- READS THE NOTES DIRECTLY RATHER THAN CALLING ReadMarkerSpans, which would be the
-- obvious reuse and is wrong here: that function ends with NormalizeSpans, which MERGES
-- touching spans. For a solo or tremolo lane that is correct. For phrases it destroys the
-- only thing that matters - the boundary - because the game scores each phrase
-- separately. Measured: 8335 raw markers across 189 tracks collapsed to 5364 that way,
-- 35.6% of every phrase boundary in the corpus, with `whativedone2` going from 32
-- phrases to 2. That is why phrase_syl_mean read rho -0.008; it was measuring blobs.
--
-- NormalizeVocalPhrases (difficulty_score_vocals.lua) clips overlaps instead of merging,
-- so the covered time is identical and only the segmentation differs.
function ReadPhraseSpans(track)
    local spans = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, p = r.MIDI_GetNote(take, j)
                if ok and not muted and (p == 105 or p == 106) then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
                    if e > s then spans[#spans + 1] = { s = s, e = e } end
                end
            end
        end
    end
    return NormalizeVocalPhrases(spans)
end

-- Vocalist percussion RANGES, built from text events - NOT from the 96/97 notes.
--
-- The two are different things and conflating them is the easy mistake here: pitch 96
-- (playable) and 97 (sample only) are the individual percussion HITS, 4115 of them
-- across the corpus, while the range the player is in is delimited by
-- `[tambourine_start]` / `[tambourine_end]` and the cowbell and clap equivalents. Only
-- the range matters for playing time; the hits are bonus points and are never required.
--
-- THE MARKERS ARE NOT BALANCED, measured: 84 starts against 87 ends across 43 songs,
-- with cowbell 44/45, clap 19/16 and tambourine 21/26. A builder that assumes pairs
-- will either mis-pair across a gap or walk off the end, so:
--   * a start while a span is already open is ignored (no nesting),
--   * an end with nothing open is ignored,
--   * a span still open at the end of the track closes at the track end.
--
-- A range is only SUBTRACTED from playing time where it holds no sung note - see the
-- scorer. 43% of these begin while the vocalist is still in a playing state, so a
-- blanket rule would discard real singing.
function ReadPercussionSpans(track)
    local marks = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textcnt = r.MIDI_CountEvts(take)
            for j = 0, textcnt - 1 do
                local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and (evt_type == 1 or evt_type == 5) then
                    local kind = msg:match('^%[(%a+)_start%]$') and 'start'
                              or msg:match('^%[(%a+)_end%]$')   and 'end'
                    local what = msg:match('^%[(%a+)_')
                    if kind and (what == 'tambourine' or what == 'cowbell' or what == 'clap') then
                        marks[#marks + 1] = {
                            t = r.MIDI_GetProjTimeFromPPQPos(take, ppq), kind = kind,
                        }
                    end
                end
            end
        end
    end
    table.sort(marks, function(a, b) return a.t < b.t end)

    local spans, open = {}, nil
    for _, m in ipairs(marks) do
        if m.kind == 'start' then
            if not open then open = m.t end
        elseif open then
            if m.t > open then spans[#spans + 1] = { s = open, e = m.t } end
            open = nil
        end
    end
    if open then
        local last = TrackEndTime(track)
        if last > open then spans[#spans + 1] = { s = open, e = last } end
    end
    return NormalizeSpans(spans)
end

-- PRO KEYS lane-shift markers, in time order.
--
-- `bases` maps marker pitch -> the base pitch of the display window it selects, e.g.
-- { [0] = 48, [2] = 50, ... }. Returns an ordered array of { s = project time,
-- base = window base }, which ScoreChart turns into shift_rate / shift_span_mean.
--
-- WHITELISTED, NOT RANGE-CHECKED, and that is load-bearing. Three corpus charts carry
-- low notes on PART REAL_KEYS_X that are not documented lane shifts - pitch 11 in
-- `wewerentborn` and `saturdaynightspecial`, pitch 32 in `lovehermadly`, 8 notes in all.
-- A "below the gem window means it is a shift" test would invent a phantom range for
-- each, with no base to map it to. Anything not in `bases` is ignored.
--
-- Instants, not spans: only the onset matters, since a marker selects a range that holds
-- until the next marker replaces it.
function ReadLaneShifts(track, bases)
    local out = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, _, _, p = r.MIDI_GetNote(take, j)
                if ok and not muted and bases[p] then
                    out[#out + 1] = {
                        s    = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                        base = bases[p],
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

-- Playing spans from the track's animation state text events.
--
-- A playing state opens a span, an idle state closes it, and a span still open
-- at the end runs to the track's item end.
--
-- Returns spans, n_state_events, solo_spans.
--   n_state_events matters because zero state events is a real case
--     (wewillrockyou1's PART BASS carries only idle events) and the caller must be
--     able to tell "never plays" from "no information".
--   solo_spans covers the stretches specifically marked [play_solo]. Those are
--     playing spans too and are included in `spans`; they are tracked separately
--     as well because solo passages are where the technical difficulty of a chart
--     concentrates, which the plain playing/idle split cannot express.
--
--     BUT THESE ARE ANIMATION CUES, NOT THE SOLO. [play_solo] drives the
--     on-stage character animation and is optional polish that many songs simply
--     omit - absent on 87% of corpus songs below rank 230 and still 36% above
--     355. The real solo is a NOTE at pitch 103 (see ReadMarkerSpans), and the
--     two disagree badly: webuiltthiscity has an authored solo over 11% of its
--     guitar chart and no [play_solo] event anywhere.
--
--     So a factor built on these measures how thoroughly a chart was animated,
--     which correlates with rank only because flagship songs get more authoring
--     attention. Kept for one calibration round purely to measure that against
--     the pitch-103 version; expected to lose and be removed.
function ReadPlayingSpans(track)
    local evs = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            -- MIDI_CountEvts returns the text/sysex count as its FOURTH value.
            local _, _, _, txtcnt = r.MIDI_CountEvts(take)
            for j = 0, txtcnt - 1 do
                local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and typ == 1 and msg then
                    local m = msg:lower()
                    if ANIM_PLAYING[m] or ANIM_IDLE[m] then
                        evs[#evs + 1] = {
                            t = r.MIDI_GetProjTimeFromPPQPos(take, ppq),
                            playing = ANIM_PLAYING[m] or false,
                            solo    = (m == '[play_solo]'),
                        }
                    end
                end
            end
        end
    end
    table.sort(evs, function(a, b) return a.t < b.t end)

    local fin = nil
    local function TrackEnd()
        fin = fin or TrackEndTime(track)
        return fin
    end

    local spans, solo_spans = {}, {}
    local open_at, solo_at = nil, nil
    for _, e in ipairs(evs) do
        if e.playing then
            if not open_at then open_at = e.t end
            -- A solo span runs until the next state event of any kind: entering
            -- [play] or [intense] ends the solo just as an idle state does.
            if e.solo then
                if not solo_at then solo_at = e.t end
            elseif solo_at then
                if e.t > solo_at then solo_spans[#solo_spans + 1] = { s = solo_at, e = e.t } end
                solo_at = nil
            end
        else
            if open_at then
                if e.t > open_at then spans[#spans + 1] = { s = open_at, e = e.t } end
                open_at = nil
            end
            if solo_at then
                if e.t > solo_at then solo_spans[#solo_spans + 1] = { s = solo_at, e = e.t } end
                solo_at = nil
            end
        end
    end
    if open_at and TrackEnd() > open_at then
        spans[#spans + 1] = { s = open_at, e = TrackEnd() }
    end
    if solo_at and TrackEnd() > solo_at then
        solo_spans[#solo_spans + 1] = { s = solo_at, e = TrackEnd() }
    end
    return spans, #evs, solo_spans
end

----------------------------------------------------------------------
-- WHAT TO READ FOR EACH INSTRUMENT
--
-- The pitch windows, marker pitches and track names below decide what the factors are
-- measured over, so they belong beside the readers rather than in either consumer. They
-- used to be locals in dev/calibration/run_calibration_vkr.lua, which meant the shipped
-- suggester would have needed its own copy - and a copy disagreeing by one pitch would
-- produce a confident number measured against a different chart than the model was
-- fitted on.
--
-- ABSOLUTE PITCHES, NOT DIFFICULTY-RELATIVE, for everything except the two strum
-- overrides. Worth stating because FORCE_HOPO_PITCH = EXPERT_LO + 5 establishes the
-- opposite pattern and SOLO_PITCH happens to equal EXPERT_LO + 7, so the relative form
-- looks right and is wrong: a solo covers the same bars on every difficulty and is marked
-- once for the whole track. Verified against the corpus, where the lo+7 slots for
-- Hard/Medium/Easy (91/79/67) are empty.
----------------------------------------------------------------------

-- Expert gem range for the tiered PART tracks. Already excludes the force-HOPO markers
-- at 101/102 and overdrive at 116.
EXPERT_LO, EXPERT_HI = 96, 100

-- The two strum-override markers sit just above the gem window and push difficulty in
-- OPPOSITE directions, so they are counted separately and never summed: lo+5 forces a
-- HOPO, removing a required strum (easier); lo+6 forces a strum back on (harder).
FORCE_HOPO_PITCH  = EXPERT_LO + 5   -- 101
FORCE_STRUM_PITCH = EXPERT_LO + 6   -- 102

SOLO_PITCH    = 103   -- authored solo section (115 on Pro Keys - see the spec table)
TREMOLO_PITCH = 126   -- tremolo lane on guitar/bass; glissando on Pro Keys; roll on drums
TRILL_PITCH   = 127   -- trill lane on guitar/bass; two-lane cymbal roll on drums

-- DRUMS. 96 is NOT a gem colour here: it is the kick pedal, the only lane played with a
-- foot. The tom markers are lane-specific and the mapping is not guessable - 110 governs
-- yellow, 111 blue, 112 green - so it is written out as gem pitch -> marker pitch, and a
-- gem is only ever counted under its OWN lane's marker.
KICK_PITCH   = 96
TOM_MARKERS  = { [98] = 110, [99] = 111, [100] = 112 }
ROLL_PITCHES = { 126, 127 }

-- BIG ROCK ENDINGS. A BRE is a free-play region at the end of a song: the notes exist so
-- the characters animate, and the player may play as much or as little as they like. Every
-- gem inside one inflates density, attack rate, note totals and playing time while asking
-- nothing of the player.
--
-- READ THE [coda] EVENT, NEVER THE LANES. The BRE lanes are pitch 120-124, but on drums
-- that same range is the activation/fill lane, so pitch alone cannot tell a BRE from a
-- fill. Measured over the 394-song corpus: 392 songs carry a 120-124 lane and only 18
-- carry a [coda], with no song having a coda and no lane. Reading the lanes would strip
-- material from 374 songs that have no BRE at all.
--
-- ONE CODA PER SONG, ALWAYS - 0 of 18 have more - so this needs no per-instrument lane
-- parsing: find the single [coda] and cut everything after it. (Newer games support
-- [midcoda] and charting past it; Rock Band 3 does not, and the corpus agrees.)
--
-- THE REQUIRED FINAL HIT IS DISCARDED BY THIS CUT, deliberately. The authoring doc puts a
-- hit AFTER the lanes end, so a coda cutoff eats it: measured at a median of 1-3 gems per
-- instrument and a maximum of 9, against chart totals of 1000-2600. A short roll, a crash,
-- or a few chords. Negligible against every density and rate column, and recorded here so
-- it is not later mistaken for an oversight.
--
-- VOCALS IS EXEMPT BY SPEC and is deliberately NOT filtered - nothing may be authored
-- during a BRE, so a vocal chart that moves under this switch means either the corpus
-- violates the spec or the cutoff is wrong. That makes vocals a free control group and it
-- must stay untouched.
BRE_EVENTS_TRACK = 'EVENTS'

-- Which BRE treatment is active. nil or 'off' is the shipped behaviour and must remain the
-- default: this is a declared round under evaluation, not a decided one.
--   'gems'     drop gem events at or after the coda; leave playing spans alone
--   'gemstime' also clip the playing spans, so playing_s loses the bonus section too
DIFFICULTY_BRE_MODE = nil

-- Project time of the song's [coda], or nil when there is none - which is 376 of 394 corpus
-- songs, so the nil path is the common one.
--
-- Tolerant of both meta types: the corpus writes [coda] as a type-1 TEXT event, but type 5
-- (lyric) costs nothing to accept and some authoring tools emit it. MIDI_CountEvts returns
-- the text/sysex count as its FOURTH value - the third is the CC count, which is the
-- classic misread.
function ReadCodaTime(from_idx)
    local track = FindTrackExact(BRE_EVENTS_TRACK, from_idx)
    if not track then return nil end
    local best
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, _, _, textcnt = r.MIDI_CountEvts(take)
            for j = 0, (textcnt or 0) - 1 do
                local ok, _, muted, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(take, j)
                if ok and not muted and (evtype == 1 or evtype == 5)
                   and tostring(msg or ''):lower():find('coda', 1, true) then
                    local t = r.MIDI_GetProjTimeFromPPQPos(take, ppq)
                    if not best or t < best then best = t end
                end
            end
        end
    end
    return best
end

-- PRO KEYS lane-shift marker -> base pitch of the display window it selects. The six
-- white notes of the bottom octave; the mapping is simply `pitch + 48`. Written out
-- rather than computed so an undocumented marker cannot be silently accepted.
LANE_SHIFT_BASES = { [0] = 48, [2] = 50, [4] = 52, [5] = 53, [7] = 55, [9] = 57 }

-- One entry per scored instrument, keyed by the songs.dta rank key so a rank, a tier
-- table and a fitted model can all be looked up without a translation step.
--
--   track        the chart to read
--   lo / hi      gem window, defaulting to Expert 96-100
--   span_track   where playing states come from, when not the instrument's own track
--   solo_pitch   overrides SOLO_PITCH
--   strum        the instrument HAS a hammer-on/pull-off system at all. 5-lane keys does
--                not (the guitar doc devotes a section to it, the keys doc never mentions
--                it), so reading 101/102 there would produce zeros indistinguishable from
--                "this chart happens to use none"
--   tremolo      126/127 mean tremolo and trill lanes here
--   gliss        126 is a GLISSANDO lane instead - leniency, the opposite meaning
--   drums        switch on the limb split and the tom markers
--   lane_shifts  read the moving display window
--   vocal        an entirely different reader and scorer; no gem factor transfers
RB_CHART_SPECS = {
    { key = 'guitar', label = 'Guitar', track = 'PART GUITAR',
      strum = true, tremolo = true },

    { key = 'bass', label = 'Bass', track = 'PART BASS',
      strum = true, tremolo = true },

    -- Shares the 96-100 window, but 96 is the kick PEDAL and 126/127 are ROLL lanes
    -- rather than tremolo and trill - same pitches, different meaning.
    { key = 'drum', label = 'Drums', track = 'PART DRUMS', drums = true },

    { key = 'keys', label = 'Keys', track = 'PART KEYS' },

    -- PRO KEYS is the only instrument that does not read everything off one track.
    -- PART REAL_KEYS_X carries NO animation states - measured, 0 of 123 corpus charts -
    -- so playing spans come off PART KEYS, the same performer's five-lane chart. Its solo
    -- marker is 115, not 103; pitch 103 is entirely absent across all 123 charts, so the
    -- shared value would read as an instrument with no solos.
    { key = 'real_keys', label = 'Pro Keys', track = 'PART REAL_KEYS_X',
      lo = 48, hi = 72, span_track = 'PART KEYS', solo_pitch = 115,
      gliss = true, lane_shifts = true },

    { key = 'vocals', label = 'Vocals', track = 'PART VOCALS', vocal = true },
}

function ChartSpecFor(key)
    for _, spec in ipairs(RB_CHART_SPECS) do
        if spec.key == key then return spec end
    end
    return nil
end

----------------------------------------------------------------------
-- Reading and scoring one instrument
----------------------------------------------------------------------

-- The single path from "a track exists" to "a factor table", shared by the calibration
-- corpus run and the shipped suggestion. Anything either consumer does differently -
-- where the rank came from, what is written where - happens outside this function.
--
-- opts.vocal_parts  1..3. Deliberately a PARAMETER rather than derived here: the corpus
--   run reads it from songs.dta, and a REAPER project has no songs.dta, so the product
--   counts HARM tracks instead. The two agree on all 203 corpus vocal songs, but they are
--   different sources and this function should not pretend otherwise.
-- from_idx  first track index to search from, so a corpus import can ignore tracks that
--   existed before it. nil means the whole project.
--
-- Returns factors, info - or nil, nil, error_string when the chart track is absent.
-- info carries what the CSV writer needs and what the suggestion reports:
--   span_source  'phrase' | 'anim' | 'fallback_idle_only' | 'fallback_no_events'
--   n_anim, n_fhopo, n_fstrum, n_tom, first_onset
--   bre_gem_frac, bre_seconds  present only on a gem chart that HAS a [coda]; the share
--                              of its gems sitting inside the Big Rock Ending, and how
--                              long that section runs. Reported, never subtracted.
function ScoreChartForSpec(spec, from_idx, opts)
    opts = opts or {}
    local track = FindTrackExact(spec.track, from_idx)
    if not track then return nil, nil, spec.track .. ' not found' end

    local info = { n_anim = 0 }

    -- VOCALS takes an entirely separate path: different reader, different scorer,
    -- different factor set. It returns early rather than threading a flag through the
    -- gem-marker reading below, none of which applies.
    if spec.vocal then
        local notes = ReadVocalNotes(track)
        local perc  = ReadPercussionSpans(track)

        -- Phrase markers are the authored scoring unit and are present on 200 of 204
        -- corpus tracks; animation states cover most of the rest; DeriveSpansFromEvents is
        -- the last resort so a track with a real chart and no structure still scores
        -- instead of yielding a NaN.
        local spans = ReadPhraseSpans(track)
        info.span_source = 'phrase'
        if #spans == 0 then
            spans, info.n_anim = ReadPlayingSpans(track)
            info.span_source = 'anim'
        end
        if #spans == 0 then
            spans = DeriveSpansFromEvents(notes)
            info.span_source = (info.n_anim > 0) and 'fallback_idle_only' or 'fallback_no_events'
        end

        info.first_onset = notes[1] and notes[1].s or nil
        return ScoreVocalChart(notes, spans, {
            perc_spans = perc, vocal_parts = opts.vocal_parts or 1,
        }), info
    end

    local events = ReadGemEvents(track, spec.lo or EXPERT_LO, spec.hi or EXPERT_HI)

    -- BIG ROCK ENDING. The coda is read ALWAYS, not only when the filter is armed: the
    -- shipped product reports the share of a chart that sits inside a BRE as a note, and
    -- that has to work with DIFFICULTY_BRE_MODE off, which is the default and the only
    -- state the corpus was fitted in.
    local coda = ReadCodaTime(from_idx)
    if coda then
        local inside, last = 0, 0
        for _, e in ipairs(events) do
            if e.s >= coda then inside = inside + 1 end
            if e.e and e.e > last then last = e.e end
        end
        info.bre_gem_frac = (#events > 0) and (inside / #events) or 0
        info.bre_seconds  = math.max(0, last - coda)
    end

    -- The cut itself, gem instruments only, applied to the EVENTS before anything derives
    -- from them so the DeriveSpansFromEvents fallback below already sees the trimmed chart.
    --
    -- MEASURED AND NOT ADOPTED - see the README. Excluding these gems moves only the 18
    -- corpus songs that have a BRE plus about 1 rank of refit ripple on everything else,
    -- and on the songs it targets it is net NEGATIVE: 4 tier flips toward the official
    -- rank against 6 away. `2112pt3` bass is the case that settles it, predicted 399
    -- against an actual 390 and dropping to 288 once its BRE is removed. The official
    -- ranks appear to include the ending, so the shipped behaviour counts it.
    if coda and DIFFICULTY_BRE_MODE and DIFFICULTY_BRE_MODE ~= 'off' then
        local keep = {}
        for _, e in ipairs(events) do
            if e.s < coda then keep[#keep + 1] = e end
        end
        events = keep
    end

    -- Playing spans normally come off the instrument's own track. Falling back to the gem
    -- track keeps a missing PART KEYS out of the fatal path for Pro Keys; it then hits the
    -- no-animation fallback below, which is the correct handling anyway.
    local span_track = track
    if spec.span_track then
        span_track = FindTrackExact(spec.span_track, from_idx) or track
    end
    local spans, n_anim, solo_spans = ReadPlayingSpans(span_track)
    info.n_anim = n_anim

    -- Only read what the instrument actually has - see the `strum` note on the spec table.
    if spec.strum then
        info.n_fhopo, info.n_fstrum =
            CountStrumOverrides(track, FORCE_HOPO_PITCH, FORCE_STRUM_PITCH)
    end

    -- The fallback the design insists on keeping: wewillrockyou1's PART BASS carries only
    -- idle events despite a real rank of 96 - the lowest bass rank in the corpus and one
    -- of the few Warmup examples, so it must not drop out.
    info.span_source = 'anim'
    if #spans == 0 then
        spans = DeriveSpansFromEvents(events)
        info.span_source = (n_anim > 0) and 'fallback_idle_only' or 'fallback_no_events'
    end

    -- The second half of the BRE treatment, and a declared substitution against 'gems'
    -- rather than an obvious extra: a BRE is arguably not playing time in any meaningful
    -- sense, but playing_s carries a POSITIVE coefficient in five of the six models, so
    -- shortening it pushes a prediction down at the same time as removing gems pushes
    -- density up. The two effects partly cancel and the sign is not predictable by
    -- reasoning, which is why both variants are previewed rather than one being chosen.
    if coda and DIFFICULTY_BRE_MODE == 'gemstime' then
        local clipped = {}
        for _, sp in ipairs(spans) do
            if sp.s < coda then
                clipped[#clipped + 1] = { s = sp.s, e = math.min(sp.e, coda) }
            end
        end
        spans = clipped
    end

    -- Drum-only reads. The tom markers are spans, not note-aligned modifiers: the doc says
    -- a marker applies "for the duration of the note", and across the corpus the median
    -- marker is a whole beat long, so only a third are note-length and the rest blanket a
    -- section.
    local tom_spans, roll_spans
    if spec.drums then
        tom_spans, info.n_tom = {}, 0
        for gem, marker in pairs(TOM_MARKERS) do
            local sp = ReadMarkerSpans(track, marker)
            if #sp > 0 then
                tom_spans[gem] = sp
                info.n_tom = info.n_tom + #sp
            end
        end
        local rolls = {}
        for _, pitch in ipairs(ROLL_PITCHES) do
            for _, sp in ipairs(ReadMarkerSpans(track, pitch)) do rolls[#rolls + 1] = sp end
        end
        roll_spans = rolls
    end

    info.first_onset = events[1] and events[1].s or nil

    return ScoreChart(events, spans, {
        solo_spans        = solo_spans,   -- animation cue; excluded from every candidate
        marked_solo_spans = ReadMarkerSpans(track, spec.solo_pitch or SOLO_PITCH),
        tremolo_spans     = spec.tremolo and ReadMarkerSpans(track, TREMOLO_PITCH) or nil,
        -- 126 again, read as a glissando lane. Mutually exclusive with tremolo_spans: the
        -- pitch means "harder than it looks" on guitar and "easier than it looks" here, so
        -- passing both would fit one measurement under two opposite names.
        gliss_spans       = spec.gliss and ReadMarkerSpans(track, TREMOLO_PITCH) or nil,
        lane_shifts       = spec.lane_shifts and ReadLaneShifts(track, LANE_SHIFT_BASES) or nil,
        pro_keys          = spec.key == 'real_keys',
        -- 127 is a trill lane on guitar and a two-lane cymbal roll on drums, so it must
        -- not land in trill_frac for an instrument where that name would be false.
        trill_spans       = (not spec.drums) and ReadMarkerSpans(track, TRILL_PITCH) or nil,
        force_hopo_count  = info.n_fhopo,
        force_strum_count = info.n_fstrum,
        kick_pitch        = spec.drums and KICK_PITCH or nil,
        tom_spans         = tom_spans,
        roll_spans        = roll_spans,
        -- Measured on every instrument: it is a property of the rhythm, not of the
        -- controller. Only the drum candidates fit it.
        offbeat           = true,
    }), info
end
