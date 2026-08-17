-- @description Rock Band Difficulty Calibration - corpus scoring run
-- @author VeeKiraRay
-- @about
--   Calibration pilot for the difficulty suggester. Walks the reference corpus in
--   _external_docs/ (see _corpora below - reference_songs/ plus the low-end set
--   new_reference_songs/), imports each song's MIDI, scores Expert
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
-- Every corpus root, walked in order and pooled into one song list.
--
-- More than one because the low-end set added in 2026-08 sits beside the original corpus
-- rather than inside it, and is laid out differently (flat packs; see SongMidiRelPathFlat).
-- WalkCorpus handles both layouts, so a root only has to be named here.
--
-- ADDING A ROOT IS SAFE TO RE-RUN. The resume check is by (shortname, instrument) against
-- the CSV, so songs already scored are skipped wherever they are found - including the 44
-- that appear in both roots. A song is never scored twice and never duplicated.
local _corpora = {
    _root .. '_external_docs/reference_songs/',
    _root .. '_external_docs/new_reference_songs/',
    -- The top-end set, searched per instrument for tier 5+ charts. It fills the band the
    -- low-end set could not reach: vocals was under-rating all 23 of its hardest charts
    -- by ~97 rank, and no amount of easy songs addresses that.
    --
    -- Its packs are mostly RBN (game_origin ugc_plus), whose dta files the parser does
    -- not read - deliberately, for now: every RBN rank is exactly a tier floor, so those
    -- rows are tier labels rather than ranks and cannot be regression targets.
    _root .. '_external_docs/hard_reference_songs/',
}
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

-- WHAT IS SCORED, AND WHERE THAT LIVES NOW.
--
-- The instrument table and every pitch constant this run used to declare here moved to
-- rock_band_general_helper_vkr/difficulty_read.lua (RB_CHART_SPECS, EXPERT_LO, SOLO_PITCH,
-- TOM_MARKERS, LANE_SHIFT_BASES, ...), which corpus.lua loads. They had to: the shipped
-- Metadata > Difficulty suggestion reads charts too, and a second copy of "which pitches
-- are gems" would eventually disagree with this one - at which point the suggestion would
-- be a confident number measured against a different chart than the model was fitted on.
--
-- Guitar and bass share one factor set and one code path, so the second costs almost
-- nothing - and the pair is what turns a correlation number into a diagnosis. Bass
-- difficulty is far more purely density/speed driven, so if bass correlates and guitar
-- does not, the factors are fine and guitar needs guitar-specific ones. If neither
-- correlates, the factor set itself is wrong. One instrument cannot tell those apart.
--
-- Harmonies remain out of scope for the vocal ROWS: PART VOCALS only, no HARM1/2/3 chart
-- reading. `vocal_parts` is a label-context column and still comes from songs.dta here.
local INSTRUMENTS = RB_CHART_SPECS

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

-- Reading and scoring now happens in ScoreChartForSpec (difficulty_read.lua), shared with
-- the product. What stays here is everything the product has no equivalent of: the
-- official rank, the corpus origin, and the CSV row layout.
local function ScoreInstrument(song, spec, from_idx)
    local rank = DtaRank(song, spec.key)
    if not rank then return nil end  -- no such part; verified equivalent to no track

    local sc, info, err = ScoreChartForSpec(spec, from_idx, {
        vocal_parts = song.vocal_parts or 1,
    })
    if not sc then
        return nil, ('%s has rank %d but %s'):format(song.shortname, rank, err)
    end

    -- Recorded so a systematic tempo-import failure is visible in the output rather than
    -- silently wrong: if REAPER is not importing the MIDI tempo map, every row reads 120
    -- and every grid-relative factor is meaningless.
    local bpm_at_first = 0
    if info.first_onset then
        bpm_at_first = select(1, r.TimeMap_GetDividedBpmAtTime(info.first_onset)) or 0
    end

    local row
    if spec.vocal then
        row = {
            song.shortname, song.origin or '?', PackId(song.pack), spec.key, rank,
            sc.syllables_total, sc.tubes_total, info.span_source, info.n_anim,
            'n/a', 'n/a',
            'n/a', tostring(sc.tight_med > 0), 'n/a', sc.entropy_contexts,
            'n/a',
            bpm_at_first, r.CountTempoTimeSigMarkers(0),
        }
    else
        row = {
            song.shortname, song.origin or '?', PackId(song.pack), spec.key, rank,
            sc.notes, sc.events, info.span_source, info.n_anim,
            -- 'n/a' rather than 0 where the instrument has no such system at all. These
            -- are META columns, not factor columns, so a non-numeric cell is safe here -
            -- the analysis parses only SCORE_FACTOR_KEYS as numbers and would reject the
            -- whole row if a factor cell were 'n/a'. The matching factor cells
            -- (force_hopo_rate, force_strum_rate, tremolo_frac) stay 0 to keep the CSV
            -- rectangular, and the protocol's keys candidates exclude them so a constant
            -- column is never fitted. This pair of columns is where the distinction lives.
            info.n_fhopo or 'n/a', info.n_fstrum or 'n/a',
            tostring(sc.sustain_measured), tostring(sc.tight_measured),
            tostring(sc.solo_measured), sc.entropy_contexts,
            info.n_tom or 'n/a',
            bpm_at_first, r.CountTempoTimeSigMarkers(0),
        }
    end

    -- `or 0` because SCORE_FACTOR_KEYS spans both factor sets: the vocal columns are
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

-- Pooled across roots, de-duplicated by shortname. The low-end set shares 44 songs with
-- the original corpus, and a song listed twice would be imported and scored twice - the
-- CSV resume check works on (shortname, instrument), so the second copy would be skipped,
-- but only after paying for the import. First root named wins.
--
-- EXCEPT that an entry carrying a MIDI beats one without. A pack's songs.dta lists every
-- song in the pack while only some of the MIDIs were ever extracted, so the same song is
-- reported with its midi_path from the folder that holds the file and without it from a
-- folder that only names it. Taking whichever came first drops the song entirely and
-- reports it as MISSING MIDI, even though the file is right there under another folder.
-- That cost 25 songs on the first two-root run, among them the ones holding the lowest
-- drum, keys and Pro Keys ranks in the whole corpus.
local by_name = {}
for _, root in ipairs(_corpora) do
    for _, song in ipairs(WalkCorpus(root)) do
        local cur = by_name[song.shortname]
        if not cur or (not cur.midi_path and song.midi_path) then
            by_name[song.shortname] = song
        end
    end
end

local songs = {}
for _, song in pairs(by_name) do songs[#songs + 1] = song end
table.sort(songs, function(a, b) return a.shortname < b.shortname end)

if #songs == 0 then
    -- A clean skip, not an error: the reference corpus is deliberately not
    -- versioned (the songs are not ours to redistribute), so on any checkout but
    -- the one that gathered it there is simply nothing to score. Anything built on
    -- top of this must tolerate that rather than fail.
    r.ShowConsoleMsg('No reference songs found under any corpus root:\n')
    for _, root in ipairs(_corpora) do r.ShowConsoleMsg(('  %s\n'):format(root)) end
    r.ShowConsoleMsg('\n')
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
        if DtaRank(song, inst.key) and not done[song.shortname .. '\0' .. inst.key] then
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
    -- Which roots were pooled. Origin counts alone cannot show this: the low-end set is
    -- rb3_dlc too, so a manifest without the roots gives no way to tell a corpus that
    -- includes it from one that does not.
    for i, root in ipairs(_corpora) do
        f:write(('corpus root %d   : %s\n'):format(i, root))
    end
    f:write(('rows this run   : %d\n'):format(n_scored))
    f:write(('rows skipped    : %d  (already present)\n'):format(n_skipped))
    f:write(('missing MIDI    : %d\n'):format(n_missing))
    f:write(('warnings        : %d\n'):format(n_warn))
    f:write(('instruments     : '))
    local insts = {}
    for _, inst in ipairs(INSTRUMENTS) do insts[#insts + 1] = inst.key end
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
