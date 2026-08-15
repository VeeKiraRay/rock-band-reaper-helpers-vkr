-- @description Rock Band Difficulty Calibration - corpus scoring run
-- @author VeeKiraRay
-- @about
--   Calibration pilot for the difficulty suggester. Walks the reference corpus in
--   _external_docs/reference_songs/, imports each song's MIDI, scores Expert
--   guitar and bass with the four planned difficulty factors, and appends a row
--   per (song, instrument) to dev/calibration/corpus_scores.csv.
--
--   Read-only with respect to the corpus. It DOES import tracks into the current
--   project and restore the tempo map around each song, so run it in a scratch
--   project, not one you care about.
--
--   Resumable: re-running skips songs already present in the CSV, so an
--   interrupted run costs nothing. Delete the CSV to start over.
--
--   Analysis (Spearman rho, the score->rank fit, tier accuracy) is a separate
--   action: run_calibration_analysis_vkr.lua, which reads the CSV this writes.
--
--   RUN THIS FROM THE REPO, not from a deploy_to_reaper.bat copy. It locates the
--   corpus relative to its own path, and _external_docs/ is neither versioned nor
--   deployed - a deployed copy would find no songs. Register it via
--   Actions > Load ReaScript pointed at the repo checkout.
--
--   Results appear in the REAPER console (View > Show REAPER console).

r = reaper

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')            -- dev/calibration/
local function _strip(d)
    return (d:match('^(.+)[/\\]+$') or d):match('^(.+[/\\])') or d
end
local _root   = _strip(_strip(_dir))                    -- repo root
local _corpus   = _root .. '_external_docs/reference_songs/'
local _csv      = _dir .. 'corpus_scores.csv'
local _manifest = _dir .. 'corpus_scores.manifest.txt'

ctx = nil

dofile(_dir .. 'difficulty_score.lua')
-- Appends the vocal columns to SCORE_FACTOR_KEYS, so it must load before anything
-- that reads that list. Same requirement in every other calibration entry point.
dofile(_dir .. 'difficulty_score_vocals.lua')
dofile(_dir .. 'songs_dta.lua')
dofile(_dir .. 'rank_tiers.lua')   -- for the coverage histogram at the end
dofile(_dir .. 'corpus.lua')

----------------------------------------------------------------------
-- What we score
----------------------------------------------------------------------

-- Guitar and bass share one factor set and one code path, so the second costs
-- almost nothing - and the pair is what turns a correlation number into a
-- diagnosis. Bass difficulty is far more purely density/speed driven, so if bass
-- correlates and guitar does not, the factors are fine and guitar needs
-- guitar-specific ones (chord shapes, HOPO chains). If neither correlates, the
-- factor set itself is wrong. One instrument cannot tell those apart.
-- `strum` and `tremolo` say whether the instrument HAS those systems at all, so the
-- difference between a structural zero and a measured zero stays visible. 5-lane keys
-- has no hammer-on/pull-off system (the guitar doc devotes a section to it, the keys
-- doc never mentions it) and the keys doc lists only trill markers, not tremolo.
local INSTRUMENTS = {
    { rank_key = 'guitar', track = 'PART GUITAR', strum = true,  tremolo = true  },
    { rank_key = 'bass',   track = 'PART BASS',   strum = true,  tremolo = true  },
    { rank_key = 'keys',   track = 'PART KEYS',   strum = false, tremolo = false },
    -- Drums shares the 96-100 gem window but 96 is the kick PEDAL, and 126/127 are
    -- ROLL lanes rather than tremolo and trill - same pitches, different meaning, so
    -- `tremolo` stays false and they are read into roll_frac instead. `drums` switches
    -- on the limb split and the tom markers.
    { rank_key = 'drum',   track = 'PART DRUMS',  strum = false, tremolo = false,
      drums = true },
    -- PRO KEYS. The first instrument that does not read everything off one track with
    -- the shared marker set, hence the three extra fields:
    --
    --   lo/hi        the gem window is 48-72 (C2-C4), not the 96-100 five-lane window.
    --   span_track   PART REAL_KEYS_X carries NO animation states - measured, 0 of 123
    --                charts have a play/idle/mellow/intense event - so playing spans
    --                come off PART KEYS, the same performer's five-lane chart. (It does
    --                carry [begin_key song_trainer_key_N] trainer sections, which look
    --                like animation states to a loose census and are not.)
    --   solo_pitch   115, not 103. Pro Keys is the ONLY instrument that differs, and
    --                103 is entirely absent here - 0 notes across all 123 charts. Left
    --                at the shared 103 this reads as an instrument with no solos.
    --   gliss        126 is a GLISSANDO lane (leniency: scoring off under the marker),
    --                not tremolo. Routed to gliss_frac so the sign stays honest.
    --
    -- No strum system and no tremolo lanes, same as five-lane keys.
    { rank_key = 'real_keys', track = 'PART REAL_KEYS_X', strum = false, tremolo = false,
      lo = 48, hi = 72, span_track = 'PART KEYS', solo_pitch = 115, gliss = true,
      lane_shifts = true },
    -- VOCALS. The only instrument that does not go through ScoreChart at all: its
    -- difficulty lives in the lyric text attached to each note rather than in pitches,
    -- and it scores pitch CLASS, so no gem factor transfers. `vocal` switches the whole
    -- read-and-score path over to ReadVocalNotes / ScoreVocalChart.
    --
    -- Harmonies are deliberately out of scope: PART VOCALS only, no HARM1/2/3, and no
    -- vocal_parts factor. The analysis reports residuals split by vocal_parts so the
    -- cost of that choice stays visible.
    { rank_key = 'vocals', track = 'PART VOCALS', strum = false, tremolo = false,
      vocal = true },
}

-- PRO KEYS lane-shift marker -> base pitch of the display window it selects. The six
-- white notes of the bottom octave, and the mapping is simply `pitch + 48`: 0 -> C2,
-- 2 -> D2, 4 -> E2, 5 -> F2, 7 -> G2, 9 -> A2. Black notes are never used for shifts.
--
-- Written out rather than computed so an undocumented marker cannot be silently
-- accepted - see the whitelist note on ReadLaneShifts.
local LANE_SHIFT_BASES = { [0] = 48, [2] = 50, [4] = 52, [5] = 53, [7] = 55, [9] = 57 }

-- Expert gem range for the tiered PART tracks - the same window
-- GetPatternPitchRange(track, 1) returns in actions_midi_replace.lua. Hardcoded
-- rather than loading that module, which would drag in S and the rest of the
-- helper's chain for two integers. It already excludes the force-HOPO markers at
-- 101/102 and overdrive at 116.
local EXPERT_LO, EXPERT_HI = 96, 100

-- The two strum-override markers sit just above the gem window. Read as separate
-- counts (they push difficulty in opposite directions), never as gems.
local FORCE_HOPO_PITCH  = EXPERT_LO + 5   -- 101: removes a strum, easier
local FORCE_STRUM_PITCH = EXPERT_LO + 6   -- 102: adds a strum, harder

-- Section markers, read as spans by ReadMarkerSpans.
--
-- ABSOLUTE, not difficulty-relative - do NOT write these as EXPERT_LO + n even
-- though 103 happens to equal EXPERT_LO + 7. A solo covers the same bars on every
-- difficulty and so is marked once for the whole track; the lo+7 slots for
-- Hard/Medium/Easy (91/79/67) are empty across the corpus. The two constants above
-- ARE relative, which is exactly what makes this easy to get wrong.
local SOLO_PITCH    = 103   -- the authored solo section
local TREMOLO_PITCH = 126   -- tremolo lane
local TRILL_PITCH   = 127   -- trill lane

-- DRUMS. Also absolute, for the same reason, and 96 is NOT a gem colour here: it is
-- the kick pedal, the only lane played with a foot.
--
-- The tom markers are lane-specific and the mapping is not guessable - 110 governs
-- yellow, 111 blue, 112 green - so it is written out as gem pitch -> marker pitch and a
-- gem is only ever counted under its OWN lane's marker.
--
-- Roll lanes reuse 126/127. On drums 126 is a standard roll and 127 the two-lane cymbal
-- swell; both are leniency devices, and 127 is 9 events in the whole corpus, so they are
-- read together into one roll_frac rather than split into columns that cannot be fitted.
local KICK_PITCH   = 96
local TOM_MARKERS  = { [98] = 110, [99] = 111, [100] = 112 }
local ROLL_PITCHES = { 126, 127 }

-- One line naming the scorer behaviour this run used, recorded in the manifest.
-- Not a version number: the factor SET is already recorded exactly by the CSV
-- header, so what a header cannot capture is a change in how the same columns are
-- computed - which is exactly what the span-aware rewrite was. Update this whenever
-- ScoreChart's measurement semantics change, not when a column is added.
SCORER_BEHAVIOUR = 'span-aware segments + authored markers + held notes + entropy rate'
                .. ' + attack-based density + drum limb split'
                .. ' + per-instrument gem window and markers (pro keys lane shifts)'
                .. ' + vocal scorer (pitch-class intervals, tick-matched lyrics)'

----------------------------------------------------------------------
-- CSV
----------------------------------------------------------------------

local CSV_COLS = {
    'shortname', 'origin', 'pack', 'instrument', 'rank',
    -- 'events' was called 'chords' until round 8. It was always the EVENT count
    -- (#in_span), never a count of chords, and the wrong name is why attack-based
    -- density looked like it needed new measurement when the number was already here.
    'notes', 'events', 'span_source', 'anim_events',
    'force_hopo_notes', 'force_strum_notes',
    'sustain_measured', 'tight_measured', 'solo_measured', 'entropy_contexts',
    -- 'n/a' on everything but drums. Recorded because tom_frac is predicted to carry no
    -- signal, and a null result is only worth anything if the markers were actually
    -- there to be measured - 93 of 103 corpus drum charts use them.
    'tom_marker_spans',
    'bpm_at_first_note', 'tempo_markers',
}
-- Factor columns come from the scorer's own list so the writer and the analysis
-- cannot drift apart.
local function AllCols()
    local cols = {}
    for _, c in ipairs(CSV_COLS) do cols[#cols + 1] = c end
    for _, k in ipairs(SCORE_FACTOR_KEYS) do cols[#cols + 1] = k end
    return cols
end

-- Which (song, instrument) pairs the CSV already holds, plus whether its schema
-- still matches what we would write.
--
-- The schema check is the point. Without it, a resume after any change to
-- SCORE_FACTOR_KEYS or CSV_COLS appends rows in the NEW column order under the OLD
-- header - silent misalignment. The analysis catches a column that went missing,
-- but a reorder or an equal-count swap would sail through and be read as wrong
-- numbers under the right names.
local function ReadDoneSet()
    local done = {}
    local f = io.open(_csv, 'r')
    if not f then return done, false, nil end

    local want   = table.concat(AllCols(), ',')
    local header = nil
    local first  = true
    for line in f:lines() do
        if first then
            first  = false
            header = line
        else
            local sn, _, _, inst = line:match('^([^,]*),([^,]*),([^,]*),([^,]*)')
            if sn and inst then done[sn .. '\0' .. inst] = true end
        end
    end
    f:close()
    return done, true, (header == want)
end

-- Short identifier for the pack a song came from.
--
-- WalkCorpus returns the pack as an absolute path; that would bloat every row and
-- would not survive being read on another machine. The leaf folder name is what
-- identifies the pack (the extracted-hash folder), and it is what a grouped
-- leave-one-pack-out check needs: songs from one pack are related, so random row
-- folds over them are optimistically biased, and only a pack-aware split shows it.
local function PackId(path)
    if not path or path == '' then return '?' end
    local leaf = path:match('([^/\\]+)[/\\]*$') or path
    -- Commas would split the field; nothing else in these names needs escaping.
    return (leaf:gsub(',', '_'))
end

-- %.6f then trim the trailing zeros, so the CSV stays readable without losing
-- precision on the small factor values. Wrapped in a function because gsub
-- returns two values and letting that leak into a table would corrupt the row.
local function Num(v)
    local s = ('%.6f'):format(v)
    s = s:gsub('0+$', '')
    s = s:gsub('%.$', '')
    return s
end

local function AppendRow(vals)
    local f = io.open(_csv, 'a')
    if not f then return false end
    local out = {}
    for _, v in ipairs(vals) do
        out[#out + 1] = (type(v) == 'number') and Num(v) or tostring(v)
    end
    f:write(table.concat(out, ','), '\n')
    f:close()
    return true
end

----------------------------------------------------------------------
-- Scoring one instrument on one already-imported song
----------------------------------------------------------------------

local function ScoreInstrument(song, inst, from_idx)
    local rank = DtaRank(song, inst.rank_key)
    if not rank then return nil end  -- no such part; verified equivalent to no track

    local track = FindTrackExact(inst.track, from_idx)
    if not track then
        return nil, ('%s has rank %d but no %s track'):format(song.shortname, rank, inst.track)
    end

    -- VOCALS takes an entirely separate path: different reader, different scorer,
    -- different factor set. It returns early rather than threading a `vocal` flag
    -- through the twenty lines of gem-marker reading below, none of which applies.
    if inst.vocal then
        local notes  = ReadVocalNotes(track)
        local phrase = ReadPhraseSpans(track)
        local perc   = ReadPercussionSpans(track)

        -- Same three-level fallback the gem path uses. Phrase markers are the authored
        -- scoring unit and are present on 200 of 204 corpus tracks; animation states
        -- cover most of the rest; DeriveSpansFromEvents is the last resort so a track
        -- with a real rank and no structure still scores instead of yielding a NaN.
        local spans, n_anim = phrase, 0
        local span_source = 'phrase'
        if #spans == 0 then
            spans, n_anim = ReadPlayingSpans(track)
            span_source = 'anim'
        end
        if #spans == 0 then
            spans = DeriveSpansFromEvents(notes)
            span_source = (n_anim > 0) and 'fallback_idle_only' or 'fallback_no_events'
        end

        local sc = ScoreVocalChart(notes, spans, {
            perc_spans = perc, vocal_parts = song.vocal_parts or 1,
        })

        local bpm_at_first = 0
        if #notes > 0 then
            bpm_at_first = select(1, r.TimeMap_GetDividedBpmAtTime(notes[1].s)) or 0
        end

        local row = {
            song.shortname, song.origin or '?', PackId(song.pack), inst.rank_key, rank,
            sc.syllables_total, sc.tubes_total, span_source, n_anim,
            'n/a', 'n/a',
            'n/a', tostring(sc.tight_med > 0), 'n/a', sc.entropy_contexts,
            'n/a',
            bpm_at_first, r.CountTempoTimeSigMarkers(0),
        }
        for _, k in ipairs(SCORE_FACTOR_KEYS) do row[#row + 1] = sc[k] or 0 end
        return row
    end

    local events = ReadGemEvents(track, inst.lo or EXPERT_LO, inst.hi or EXPERT_HI)

    -- Playing spans normally come off the instrument's own track. Pro Keys is the
    -- exception: PART REAL_KEYS_X carries no animation states at all, so its spans are
    -- read from PART KEYS - the same keyboardist, whose five-lane chart is animated.
    -- Falling back to the gem track keeps a missing PART KEYS out of the fatal path; it
    -- then hits the no-animation fallback below, which is the correct handling anyway.
    local span_track = track
    if inst.span_track then
        span_track = FindTrackExact(inst.span_track, from_idx) or track
    end
    local spans, n_anim, solo_spans = ReadPlayingSpans(span_track)

    -- Only read what the instrument actually has. Keys has no strum system and no
    -- tremolo lanes, so reading them would produce zeros indistinguishable from "this
    -- chart happens to use none" - and the protocol's keys candidates drop those
    -- factors rather than fitting a constant.
    local n_fhopo, n_fstrum = nil, nil
    if inst.strum then
        n_fhopo, n_fstrum = CountStrumOverrides(track, FORCE_HOPO_PITCH, FORCE_STRUM_PITCH)
    end

    -- The fallback the design insists on keeping. wewillrockyou1's PART BASS
    -- carries only idle events despite a real rank of 96 - the lowest bass rank
    -- in the corpus and one of the few Warmup examples, so it must not drop out.
    local span_source = 'anim'
    if #spans == 0 then
        spans = DeriveSpansFromEvents(events)
        span_source = (n_anim > 0) and 'fallback_idle_only' or 'fallback_no_events'
    end

    -- Drum-only reads. The tom markers are spans, not note-aligned modifiers: the doc
    -- says a marker applies "for the duration of the note", and across the corpus the
    -- median marker is a whole beat long with a p90 of 3000 ticks, so only a third are
    -- note-length and the rest blanket a section. ReadMarkerSpans already returns
    -- normalized spans, which is exactly that case.
    local tom_spans, roll_spans, n_tom = nil, nil, nil
    if inst.drums then
        tom_spans, n_tom = {}, 0
        for gem, marker in pairs(TOM_MARKERS) do
            local sp = ReadMarkerSpans(track, marker)
            if #sp > 0 then
                tom_spans[gem] = sp
                n_tom = n_tom + #sp
            end
        end
        local rolls = {}
        for _, pitch in ipairs(ROLL_PITCHES) do
            for _, sp in ipairs(ReadMarkerSpans(track, pitch)) do rolls[#rolls + 1] = sp end
        end
        roll_spans = rolls
    end

    local sc = ScoreChart(events, spans, {
        solo_spans        = solo_spans,   -- animation cue; on borrowed time
        -- 115 on Pro Keys, 103 everywhere else. Not a relative offset on either.
        marked_solo_spans = ReadMarkerSpans(track, inst.solo_pitch or SOLO_PITCH),
        tremolo_spans     = inst.tremolo and ReadMarkerSpans(track, TREMOLO_PITCH) or nil,
        -- 126 again, read as a glissando lane. Mutually exclusive with tremolo_spans:
        -- the pitch means "harder than it looks" on guitar and "easier than it looks"
        -- here, so passing both would fit one measurement under two opposite names.
        gliss_spans       = inst.gliss and ReadMarkerSpans(track, TREMOLO_PITCH) or nil,
        lane_shifts       = inst.lane_shifts and ReadLaneShifts(track, LANE_SHIFT_BASES) or nil,
        pro_keys          = inst.rank_key == 'real_keys',
        -- 127 is a trill lane on guitar and a two-lane cymbal roll on drums, so it must
        -- not land in trill_frac for an instrument where that name would be false.
        trill_spans       = (not inst.drums) and ReadMarkerSpans(track, TRILL_PITCH) or nil,
        force_hopo_count  = n_fhopo,
        force_strum_count = n_fstrum,
        kick_pitch        = inst.drums and KICK_PITCH or nil,
        tom_spans         = tom_spans,
        roll_spans        = roll_spans,
        -- Measured on every instrument: it is a property of the rhythm, not of the
        -- controller. Only the drum candidates fit it this round.
        offbeat           = true,
    })

    -- Recorded so a systematic tempo-import failure is visible in the output
    -- rather than silently wrong: if REAPER is not importing the MIDI tempo map,
    -- every row reads 120 and every grid-relative factor is meaningless.
    local bpm_at_first = 0
    if #events > 0 then
        bpm_at_first = select(1, r.TimeMap_GetDividedBpmAtTime(events[1].s)) or 0
    end

    -- playing_s is not repeated here: it is now one of SCORE_FACTOR_KEYS and gets
    -- appended below with the rest of the factors.
    local row = {
        song.shortname, song.origin or '?', PackId(song.pack), inst.rank_key, rank,
        sc.notes, sc.events, span_source, n_anim,
        -- 'n/a' rather than 0 where the instrument has no such system at all. These
        -- are META columns, not factor columns, so a non-numeric cell is safe here -
        -- the analysis parses only SCORE_FACTOR_KEYS as numbers and would reject the
        -- whole row if a factor cell were 'n/a'. The matching factor cells
        -- (force_hopo_rate, force_strum_rate, tremolo_frac) stay 0 to keep the CSV
        -- rectangular, and the protocol's keys candidates exclude them so a constant
        -- column is never fitted. This pair of columns is where the distinction lives.
        n_fhopo or 'n/a', n_fstrum or 'n/a',
        tostring(sc.sustain_measured), tostring(sc.tight_measured),
        tostring(sc.solo_measured), sc.entropy_contexts,
        n_tom or 'n/a',
        bpm_at_first, r.CountTempoTimeSigMarkers(0),
    }
    -- `or 0` because SCORE_FACTOR_KEYS now spans both factor sets: the vocal columns are
    -- structurally absent from a gem score, exactly as the gem columns are absent from a
    -- vocal one. A nil here would shift every later column left by one.
    for _, k in ipairs(SCORE_FACTOR_KEYS) do row[#row + 1] = sc[k] or 0 end
    return row
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty calibration - corpus scoring  ======\n\n')

local songs = WalkCorpus(_corpus)
if #songs == 0 then
    -- A clean skip, not an error: the reference corpus is deliberately not
    -- versioned (the songs are not ours to redistribute), so on any checkout but
    -- the one that gathered it there is simply nothing to score. Anything built on
    -- top of this must tolerate that rather than fail.
    r.ShowConsoleMsg(('No reference songs found under:\n  %s\n\n'):format(_corpus))
    r.ShowConsoleMsg('Nothing to do - skipping rather than failing.\n\n')
    r.ShowConsoleMsg('If you expected songs there, the usual cause is running a deployed\n')
    r.ShowConsoleMsg('copy of this script instead of the repo one. The corpus path is derived\n')
    r.ShowConsoleMsg('from the script location, and _external_docs/ is neither versioned nor\n')
    r.ShowConsoleMsg('deployed. Register the repo copy via Actions > Load ReaScript.\n')
    return
end

local done, had_csv, schema_ok = ReadDoneSet()
if not had_csv then
    AppendRow(AllCols())
    r.ShowConsoleMsg(('Created %s\n'):format(_csv))
elseif not schema_ok then
    r.ShowConsoleMsg('\nThis CSV was written with a different column set.\n\n')
    r.ShowConsoleMsg('Resuming would append rows in the current column order under the old\n')
    r.ShowConsoleMsg('header, which misaligns every factor silently. Refusing.\n\n')
    r.ShowConsoleMsg(('Delete or rename %s and re-run for a full rescore.\n'):format(_csv))
    r.ShowConsoleMsg('(Renaming it to corpus_scores_baseline.csv keeps it for\n')
    r.ShowConsoleMsg(' run_calibration_diff_vkr.lua to compare against.)\n')
    return
else
    r.ShowConsoleMsg('Resuming: existing CSV found, completed rows will be skipped.\n')
end

r.ShowConsoleMsg(('Corpus: %d songs\n\n'):format(#songs))

----------------------------------------------------------------------
-- Tier coverage of the corpus
----------------------------------------------------------------------

-- Derived from the songs.dta ranks alone, so it needs no MIDI import and covers
-- EVERY song in the corpus regardless of what this run happens to score - on a
-- resume, the rows scored this run are not the corpus.
--
-- The design doc's coverage tables were built on a 155-song snapshot and the corpus
-- has grown by ~50 songs since. The conclusions drawn from them - which tiers are
-- thin, and therefore which residuals carry any weight - may have moved, so print
-- the current shape rather than leaving the stale table as the only record.
local function ReportCoverage()
    -- Only the origins that reach a fit; greenday is excluded at analysis time and
    -- would pad the counts with a song no model ever sees.
    local ORIGINS = { 'rb3_dlc', 'lego' }
    local INST_KEYS = { 'guitar', 'bass', 'drum', 'vocals', 'keys', 'real_keys', 'band' }

    r.ShowConsoleMsg('-- corpus tier coverage (from songs.dta ranks, all origins listed) --\n')
    r.ShowConsoleMsg(('  %-12s %-9s %5s  %s\n'):format(
        'instrument', 'origin', 'n', 'Wrm Apr Sol Mod Chl Ngt Imp'))
    for _, origin in ipairs(ORIGINS) do
        for _, inst in ipairs(INST_KEYS) do
            local by_tier, n = {}, 0
            for t = 0, 6 do by_tier[t] = 0 end
            for _, song in ipairs(songs) do
                if (song.origin or '?') == origin then
                    local tier = TierForRank(inst, DtaRank(song, inst))
                    if tier then
                        by_tier[tier] = by_tier[tier] + 1
                        n = n + 1
                    end
                end
            end
            if n > 0 then
                local cells = {}
                for t = 0, 6 do cells[#cells + 1] = ('%3d'):format(by_tier[t]) end
                r.ShowConsoleMsg(('  %-12s %-9s %5d  %s\n')
                    :format(inst, origin, n, table.concat(cells, ' ')))
            end
        end
    end
    r.ShowConsoleMsg('  (a thin tier means residuals there say little - 2 songs cannot\n')
    r.ShowConsoleMsg('   establish whether the model handles that band.)\n\n')
end

ReportCoverage()

local baseline  = r.CountTracks(0)
local n_scored, n_skipped, n_missing, n_warn = 0, 0, 0, 0
local warnings  = {}


r.PreventUIRefresh(1)

for si, song in ipairs(songs) do
    -- Which instruments still need a row for this song?
    local todo = {}
    for _, inst in ipairs(INSTRUMENTS) do
        if DtaRank(song, inst.rank_key) and not done[song.shortname .. '\0' .. inst.rank_key] then
            todo[#todo + 1] = inst
        end
    end

    if not song.midi_path then
        n_missing = n_missing + 1
        warnings[#warnings + 1] = ('MISSING MIDI  %s'):format(song.shortname)
    elseif #todo == 0 then
        n_skipped = n_skipped + 1
    else
        local from_idx, added = ImportSongMidi(song.midi_path)
        if added == 0 then
            warnings[#warnings + 1] = ('IMPORT FAILED  %s (created no tracks)'):format(song.shortname)
            n_warn = n_warn + 1
        else
            for _, inst in ipairs(todo) do
                local row, err = ScoreInstrument(song, inst, from_idx)
                if row then
                    AppendRow(row)
                    n_scored = n_scored + 1
                elseif err then
                    warnings[#warnings + 1] = err
                    n_warn = n_warn + 1
                end
            end
        end
        -- Always clean up, even after a failed import: leftover tracks make every
        -- later InsertMedia append to an existing track instead of creating one,
        -- turning a single failure into a cascade of false "created no tracks".
        CleanupImport(from_idx)
    end

    if si % 10 == 0 then
        r.ShowConsoleMsg(('  ... %d/%d songs (%d rows written)\n'):format(si, #songs, n_scored))
    end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()

local leftover = r.CountTracks(0) - baseline
r.ShowConsoleMsg('\n')
r.ShowConsoleMsg(('Rows written this run : %d\n'):format(n_scored))
r.ShowConsoleMsg(('Songs already done    : %d\n'):format(n_skipped))
r.ShowConsoleMsg(('Songs with no MIDI    : %d\n'):format(n_missing))
r.ShowConsoleMsg(('Warnings              : %d\n'):format(n_warn))
r.ShowConsoleMsg(('Leftover tracks       : %d%s\n'):format(
    leftover, leftover == 0 and '  (clean)' or '  <-- CLEANUP FAILED'))

if #warnings > 0 then
    r.ShowConsoleMsg('\n-- warnings --\n')
    for _, w in ipairs(warnings) do r.ShowConsoleMsg('  ' .. w .. '\n') end
end

----------------------------------------------------------------------
-- Run manifest
----------------------------------------------------------------------

-- Written beside the CSV, not into it: comment lines inside the CSV would have to
-- be skipped by LoadCsv and by every future consumer.
--
-- The header already records the factor set exactly, so this only carries what a
-- header cannot - when the run happened, what it covered, and which scorer
-- behaviour produced it. Generated rather than hand-maintained, because a
-- hand-written manifest goes stale the same way the design doc's corpus counts did.
local function WriteManifest()
    local f = io.open(_manifest, 'w')
    if not f then
        r.ShowConsoleMsg(('\nCould not write the manifest: %s\n'):format(_manifest))
        return
    end
    local by_origin = {}
    for _, song in ipairs(songs) do
        local o = song.origin or '?'
        by_origin[o] = (by_origin[o] or 0) + 1
    end
    local origins = {}
    for o, n in pairs(by_origin) do origins[#origins + 1] = ('%s=%d'):format(o, n) end
    table.sort(origins)

    f:write('Difficulty calibration run manifest\n')
    f:write('(generated by run_calibration_vkr.lua - do not hand-edit)\n\n')
    f:write(('date            : %s\n'):format(os.date('%Y-%m-%d %H:%M')))
    f:write(('scorer          : %s\n'):format(SCORER_BEHAVIOUR))
    f:write(('corpus songs    : %d  (%s)\n'):format(#songs, table.concat(origins, ', ')))
    f:write(('rows this run   : %d\n'):format(n_scored))
    f:write(('rows skipped    : %d  (already present)\n'):format(n_skipped))
    f:write(('missing MIDI    : %d\n'):format(n_missing))
    f:write(('warnings        : %d\n'):format(n_warn))
    f:write(('instruments     : '))
    local insts = {}
    for _, inst in ipairs(INSTRUMENTS) do insts[#insts + 1] = inst.rank_key end
    f:write(table.concat(insts, ', ') .. '\n')
    f:write(('factor columns  : %d\n'):format(#SCORE_FACTOR_KEYS))
    f:write('\nColumn order is the CSV header itself, which is the authoritative\n')
    f:write('record of the factor set - a differing header means a different scorer.\n')
    f:close()
    r.ShowConsoleMsg(('Manifest: %s\n'):format(_manifest))
end

WriteManifest()

r.ShowConsoleMsg(('\nCSV: %s\n'):format(_csv))
r.ShowConsoleMsg('Next: run run_calibration_analysis_vkr.lua for rho and tier accuracy.\n')
r.ShowConsoleMsg('Then: run_calibration_diff_vkr.lua to see what moved, if a baseline exists.\n')
