-- REAPER-facing side of the calibration pilot: walking the corpus, importing a
-- song's MIDI, and reading the notes and playing spans the pure scorer needs.
--
-- This is the ONLY calibration module that touches r.*. Everything it produces
-- is plain tables, so difficulty_score.lua stays pure and unit-testable. In
-- particular it attaches a `qn` field to every event: the scorer needs
-- grid-relative spacing for factor 4 but must not call TimeMap2_timeToQN
-- itself.
--
-- Requires (globals): ParseSongsDta, SongMidiRelPath (songs_dta.lua),
--                     NormalizeSpans (difficulty_score.lua)
--
-- Status: calibration pilot, dev-only.

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
-- file-locals. If this pilot graduates, promote one shared copy into
-- actions_difficulty_shared.lua instead of leaving five near-duplicates.
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
-- Import / cleanup
----------------------------------------------------------------------

-- Same job as fixture_helpers.LoadFixture, but takes an absolute path (that
-- helper hardcodes _FIXTURE_DIR) and snapshots the tempo map per call.
--
-- The tempo snapshot is load-bearing, not hygiene: song MIDIs carry full tempo
-- maps, every density factor is measured in real time, and factor 4 converts
-- through the map. Restoring afterwards keeps song N+1 from inheriting song N's
-- tempo.
local _tempo_snapshot = nil

-- Snapshot/restore logic follows dev/tests/fixture_helpers.lua:22-53, whose
-- tempo functions are file-locals and so cannot be reused directly. Two details
-- there are non-obvious and both are load-bearing:
--
--   * A fresh project has ZERO explicit tempo markers (REAPER applies an
--     implicit 120/4-4 instead), so a snapshot taken then has nothing to restore
--     and index 0 keeps whatever the first import set. Materialize the default
--     into a real marker before the first snapshot.
--   * REAPER refuses to delete the LAST tempo marker, so index 0 must be
--     overwritten in place rather than deleted.
local function EnsureDefaultTempoMarker()
    if r.CountTempoTimeSigMarkers(0) == 0 then
        r.AddTempoTimeSigMarker(0, 0, 120, 4, 4, false)
    end
end

local function SnapshotTempo()
    local snap = {}
    for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
        local ok, timepos, _, _, bpm, num, denom, linear = r.GetTempoTimeSigMarker(0, i)
        if ok then
            snap[#snap + 1] = { timepos = timepos, bpm = bpm,
                                num = num, denom = denom, linear = linear }
        end
    end
    return snap
end

local function RestoreTempo(snap)
    for i = r.CountTempoTimeSigMarkers(0) - 1, 1, -1 do
        r.DeleteTempoTimeSigMarker(0, i)
    end
    if snap[1] then
        r.SetTempoTimeSigMarker(0, 0, snap[1].timepos, -1, -1,
            snap[1].bpm, snap[1].num, snap[1].denom, snap[1].linear)
    end
    for i = 2, #snap do
        local m = snap[i]
        r.AddTempoTimeSigMarker(0, m.timepos, m.bpm, m.num, m.denom, m.linear)
    end
    r.UpdateTimeline()
end

-- Returns first_track_idx, n_tracks_added.
function ImportSongMidi(abs_path)
    local n_before = r.CountTracks(0)
    -- Deselect everything: InsertMedia(path, 0) means "add to current track" and
    -- only creates tracks when there is nothing selected to add to.
    for i = 0, n_before - 1 do
        r.SetTrackSelected(r.GetTrack(0, i), false)
    end
    r.SetEditCurPos(0, false, false)
    EnsureDefaultTempoMarker()
    _tempo_snapshot = _tempo_snapshot or SnapshotTempo()
    r.InsertMedia(abs_path, 0)
    return n_before, r.CountTracks(0) - n_before
end

-- Delete every track from from_idx up, and restore the pre-import tempo map.
--
-- Must be robust: leftover tracks poison every later import (see the comment on
-- EnableFixtureAutoCleanup in dev/tests/fixture_helpers.lua - one failure
-- cascades into a run of misleading "created no tracks" results).
function CleanupImport(from_idx)
    for i = r.CountTracks(0) - 1, from_idx, -1 do
        local tr = r.GetTrack(0, i)
        if tr then r.DeleteTrack(tr) end
    end
    if _tempo_snapshot then
        RestoreTempo(_tempo_snapshot)
        _tempo_snapshot = nil
    end
end

----------------------------------------------------------------------
-- Corpus walk
----------------------------------------------------------------------

local function ReadFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local text = f:read('a')
    f:close()
    return text
end

local function FileExists(path)
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

-- Recursively collect every 'songs.dta' under root, at any depth (the corpus has
-- single-song packs at the top level and multi-song packs one folder deeper).
--
-- Matches the filename EXACTLY: folder 3A6A6D27... also contains a duplicate
-- 'songs(0).dta', and reading both would process that song twice.
local function CollectDtaPaths(root, out, depth)
    out   = out or {}
    depth = depth or 0
    if depth > 4 then return out end

    local candidate = root .. 'Root/songs/songs.dta'
    if FileExists(candidate) then out[#out + 1] = candidate end

    local i = 0
    while true do
        local sub = r.EnumerateSubdirectories(root, i)
        if not sub then break end
        CollectDtaPaths(root .. sub .. '/', out, depth + 1)
        i = i + 1
    end
    return out
end

-- Every song in the corpus, as a flat list of
--   { shortname, origin, ranks, genre, vocal_parts, midi_path }
-- Songs whose MIDI is missing are returned with midi_path = nil so the caller
-- can report them rather than silently skipping.
function WalkCorpus(root)
    local songs = {}
    for _, dta in ipairs(CollectDtaPaths(root)) do
        local pack = dta:gsub('Root/songs/songs%.dta$', '')
        local text = ReadFile(dta)
        if text then
            for _, e in ipairs(ParseSongsDta(text)) do
                local mid = pack .. SongMidiRelPath(e.shortname)
                songs[#songs + 1] = {
                    shortname   = e.shortname,
                    origin      = e.origin,
                    genre       = e.genre,
                    vocal_parts = e.vocal_parts,
                    ranks       = e.ranks,
                    midi_path   = FileExists(mid) and mid or nil,
                    pack        = pack,
                }
            end
        end
    end
    table.sort(songs, function(a, b) return a.shortname < b.shortname end)
    return songs
end
