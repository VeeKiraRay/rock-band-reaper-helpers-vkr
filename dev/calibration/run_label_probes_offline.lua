-- Two probes into the LABELS rather than the model. Run from the repository root:
--   lua dev/calibration/run_label_probes_offline.lua
--
-- Three of the six shipped models fail the release gate, and both remaining problems have
-- an explanation that is about what the official rank MEASURES, not about which factors
-- were chosen:
--
--   * VOCALS. Rock Band scores vocals by pitch CLASS, so an octave-down performance still
--     scores. `flightoficarus` is rank 442 yet casually singable in-game. If Harmonix
--     ranked the song rather than the chart, no chart-derived factor can close that gap -
--     and every one of the hardest charts is under-predicted, by about 97 rank.
--   * KEYS. Keys and Pro Keys were new in RB3, so Harmonix had no prior calibration for
--     them the way guitar, bass and drums had three games of it. Early keys ranks may
--     simply be less settled.
--
-- Both are testable on the CSV as it stands. Neither probe fits a shipped model, changes a
-- factor, or needs REAPER. The point is to decide whether to keep hunting vocal factors or
-- stop - spending a rescore or a derived-feature refactor before knowing the ceiling would
-- be guessing.
--
-- Writes calibration_label_probes_report.txt beside the other reports.

local _script = (arg and arg[0]) or 'dev/calibration/run_label_probes_offline.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/calibration/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))
local _csv    = _dir .. 'corpus_scores.csv'
local _report = _dir .. 'calibration_label_probes_report.txt'

r = { ShowConsoleMsg = function(s) io.write(s) end }

dofile(_dir .. 'difficulty_score.lua')          -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')   -- appends the vocal columns
dofile(_dir .. 'rank_tiers.lua')
dofile(_dir .. 'stats.lua')
dofile(_dir .. 'weirdly_scored.lua')
dofile(_dir .. 'protocol.lua')
dofile(_dir .. 'songs_dta.lua')                 -- ParseSongsDta, which corpus.lua needs
dofile(_root .. 'lib/reaper_difficulty_models.lua')   -- the shipped candidate per instrument

local _rf = io.open(_report, 'w')
local function Msg(s)
    io.write(s)
    if _rf then _rf:write(s) end
end

local INSTRUMENTS = { 'guitar', 'bass', 'drum', 'keys', 'real_keys', 'vocals' }

----------------------------------------------------------------------
-- CSV
----------------------------------------------------------------------

local function Split(line)
    local out = {}
    for field in (line .. ','):gmatch('([^,]*),') do out[#out + 1] = field end
    return out
end

local function LoadCsv(path)
    local f = io.open(path, 'r')
    if not f then return nil, 'not found: ' .. path end
    local header, rows = nil, {}
    for line in f:lines() do
        if line ~= '' then
            local fields = Split(line)
            if not header then
                header = {}
                for i, name in ipairs(fields) do header[name] = i end
            else
                rows[#rows + 1] = fields
            end
        end
    end
    f:close()
    if not header then return nil, 'empty file' end
    return { header = header, rows = rows }
end

local csv, err = LoadCsv(_csv)
if not csv then
    Msg(('Cannot read %s (%s)\n'):format(_csv, err))
    if _rf then _rf:close() end
    return
end

local function Field(row, name)
    local i = csv.header[name]
    return i and row[i] or nil
end

-- rank_by_song[shortname][inst] = rank. Probe 1's song-level predictor is built from this.
local rank_by_song = {}
for _, row in ipairs(csv.rows) do
    local sn   = Field(row, 'shortname')
    local inst = Field(row, 'instrument')
    local rk   = tonumber(Field(row, 'rank'))
    if sn and inst and rk and rk > 0 then
        rank_by_song[sn] = rank_by_song[sn] or {}
        rank_by_song[sn][inst] = rk
    end
end

----------------------------------------------------------------------
-- The protocol's own evaluation, reused verbatim
--
-- Probe 1 has to be comparable to numbers already published in
-- calibration_protocol_report.txt, so it uses the protocol's machinery rather than a
-- simpler fit: the same repeats, the same shared stratified folds, the same nested ridge,
-- the same clamp and the same tier grading. The only thing that varies between the three
-- columns is WHICH FEATURE KEYS are named.
--
-- Extra predictors ride along as additional columns on d.feats with their own entries in
-- `pos`, so RunOneRepeat needs no modification - Slice simply reads feats[i][pos[k]].
----------------------------------------------------------------------

local function Collect(inst, extra_cols)
    local d = { feats = {}, ranks = {}, origins = {}, names = {} }
    local pos = {}
    for j, k in ipairs(SCORE_FACTOR_KEYS) do pos[k] = j end
    local n_base = #SCORE_FACTOR_KEYS
    for j, k in ipairs(extra_cols) do pos[k] = n_base + j end

    for _, row in ipairs(csv.rows) do
        if Field(row, 'instrument') == inst then
            local rank = tonumber(Field(row, 'rank'))
            local name = Field(row, 'shortname')
            local fv, ok = {}, rank ~= nil
            for j, k in ipairs(SCORE_FACTOR_KEYS) do
                local v = tonumber(Field(row, k))
                if v == nil then ok = false else fv[j] = v end
            end
            -- The song-level columns. A song missing one of them cannot be used by the
            -- comparison at all, so it is dropped from EVERY column rather than only from
            -- the one that needs it - otherwise the three numbers would describe three
            -- different row sets and could not be read against each other.
            for j, k in ipairs(extra_cols) do
                local src = k:match('^rank_(.+)$')
                local v = src and rank_by_song[name] and rank_by_song[name][src]
                if v == nil then ok = false else fv[n_base + j] = v end
            end
            if ok then
                local n = #d.feats + 1
                d.feats[n]   = fv
                d.ranks[n]   = rank
                d.origins[n] = Field(row, 'origin')
                d.names[n]   = name
            end
        end
    end
    return d, pos
end

local function Partition(d, inst)
    local target = {}
    for i, o in ipairs(d.origins) do
        if o == 'rb3_dlc' and not IsWeirdlyScored(d.names[i], inst) then
            target[#target + 1] = i
        end
    end
    return target, AuxIndices(d.origins)
end

-- One candidate's worth of the protocol: N_REPEATS of shared-fold CV, aggregated the same
-- way RunProtocol aggregates. Returns usable_mean, rho_mean, miss_mean, n_rows and the
-- per-row mean absolute residual (probe 2 needs the latter).
local function Evaluate(d, target, aux, inst, keys, pos, scale)
    local strata = {}
    for n, ti in ipairs(target) do strata[n] = tostring(TierForRank(inst, d.ranks[ti])) end
    local rank_lo, rank_hi = RankRange(d, target)

    local usable, miss, rho = {}, {}, {}
    local resid_sum, resid_n = {}, {}
    local n_rows = 0

    for rep = 1, PROTOCOL.N_REPEATS do
        local folds = ShuffledStratifiedFolds(strata, PROTOCOL.NFOLD, PROTOCOL.SEED + rep)
        local pred, act = RunOneRepeat(d, target, aux, folds, keys, pos, scale)
        if pred then
            local pt, at = {}, {}
            for i = 1, #pred do
                pred[i] = ClampRank(pred[i], rank_lo, rank_hi)
                pt[i] = TierForRank(inst, pred[i])
                at[i] = TierForRank(inst, act[i])
            end
            local dist = TierDistance(pt, at)
            usable[#usable + 1] = dist.usable / dist.n
            miss[#miss + 1]     = dist.miss / dist.n
            rho[#rho + 1]       = Spearman(pred, act) or 0
            n_rows = dist.n
            -- RunOneRepeat returns rows in fold order, which is a permutation of target -
            -- rebuild the same order to attribute a residual to a song.
            local k = 0
            for f = 1, #folds do
                for _, ti in ipairs(folds[f]) do
                    k = k + 1
                    local i = target[ti]
                    resid_sum[i] = (resid_sum[i] or 0) + math.abs(pred[k] - act[k])
                    resid_n[i]   = (resid_n[i] or 0) + 1
                end
            end
        end
    end
    if #usable == 0 then return nil end

    local resid = {}
    for i, s in pairs(resid_sum) do resid[i] = s / resid_n[i] end
    return {
        usable = MeanOf(usable), miss = MeanOf(miss), rho = MeanOf(rho),
        n_rows = n_rows, resid = resid,
    }
end

local function ScaleNamed(name)
    for _, s in ipairs(SCALES) do
        if s.name == name then return s end
    end
    return SCALES[1]
end

----------------------------------------------------------------------
-- Probe 1
----------------------------------------------------------------------

Msg('======  Label probes  ======\n\n')
Msg(('CSV : %s   (%d rows)\n\n'):format(_csv, #csv.rows))

Msg([[
PROBE 1 - how much of a rank is chart-level at all?

  Three predictors of the same rank, scored by the LOCKED protocol (10 repeats, shared
  stratified folds, nested ridge, same clamp and tier grading):

    chart        the shipped candidate's factors - today's model
    song-level   ONLY the other instruments' ranks for the same song; no chart evidence
    both         the two together

  A rank that other instruments already predict is a property of the SONG, and no
  instrument-specific chart feature can recover it. Read `song-level` as a floor on how
  much of the label is out of the model's reach - not as proof the label is wrong. Hard
  songs are often hard on everything, and that shared difficulty is real; the point is
  only that it is unreachable from one chart.

]])

-- Predictors for each instrument: the other parts that nearly every song carries. Keys and
-- Pro Keys are excluded as PREDICTORS (only 251 of 379 songs have them, and requiring them
-- would drop a third of the corpus) but are still predicted.
local SONG_LEVEL_SOURCES = { 'guitar', 'bass', 'drum', 'vocals' }

local probe1 = {}

Msg(('  %-10s %-12s %-9s %-9s %-8s %s\n')
    :format('inst', 'predictor', 'usable', 'rho', 'n', 'note'))
Msg('  ' .. string.rep('-', 74) .. '\n')

for _, inst in ipairs(INSTRUMENTS) do
    local m = RB_DIFFICULTY_MODELS[inst]
    if m then
        local scale = ScaleNamed(m.scale)
        -- The shipped model's own factor list, minus the appended origin flags.
        local chart_keys = {}
        for _, k in ipairs(m.keys) do
            if not k:match('^is_') then chart_keys[#chart_keys + 1] = k end
        end

        local sources = {}
        for _, s in ipairs(SONG_LEVEL_SOURCES) do
            if s ~= inst then sources[#sources + 1] = 'rank_' .. s end
        end

        -- FIDELITY GATE. The chart column on EVERY target row must reproduce the number
        -- already published in calibration_protocol_report.txt. If it does not, this
        -- harness is not running the protocol and its novel columns mean nothing.
        local d0, pos0 = Collect(inst, {})
        local t0, aux0 = Partition(d0, inst)
        local fid = Evaluate(d0, t0, aux0, inst, chart_keys, pos0, scale)

        -- The comparison itself, on the subset where every song-level source exists, so
        -- all three columns describe the same rows.
        local d1, pos1 = Collect(inst, sources)
        local t1, aux1 = Partition(d1, inst)

        local both_keys = {}
        for _, k in ipairs(chart_keys) do both_keys[#both_keys + 1] = k end
        for _, k in ipairs(sources)     do both_keys[#both_keys + 1] = k end

        local res = {
            chart = Evaluate(d1, t1, aux1, inst, chart_keys, pos1, scale),
            song  = Evaluate(d1, t1, aux1, inst, sources,    pos1, scale),
            both  = Evaluate(d1, t1, aux1, inst, both_keys,  pos1, scale),
        }
        probe1[inst] = { res = res, fid = fid, dropped = #t0 - #t1 }

        for _, which in ipairs({ 'chart', 'song', 'both' }) do
            local e = res[which]
            if e then
                Msg(('  %-10s %-12s %7.2f%%  %+7.3f  %-8d %s\n')
                    :format(which == 'chart' and inst or '', which,
                            e.usable * 100, e.rho, e.n_rows,
                            which == 'chart' and ('(%d songs dropped for a missing part)')
                                :format(#t0 - #t1) or ''))
            end
        end
        if fid then
            Msg(('  %-10s %-12s %7.2f%%  %+7.3f  %-8d %s\n')
                :format('', 'chart, all', fid.usable * 100, fid.rho, fid.n_rows,
                        '<- must match the protocol report'))
        end
        Msg('\n')
    end
end

----------------------------------------------------------------------
-- Probe 2
----------------------------------------------------------------------

Msg([[
PROBE 2 - were the early keys ranks less settled?

  songs.dta carries (song_id N), which runs roughly in release order inside a catalogue
  block. If Harmonix were still calibrating a part new to RB3, its early charts should be
  ranked less consistently than its later ones - visible as residuals that SHRINK as the
  id grows. Guitar, bass and drums are the controls: three games of prior calibration, so
  they should show no trend.

]])

-- shortname -> song_id, read straight from the corpus dtas.
local song_id = {}
do
    local function ListDirs(path)
        local out = {}
        local p = io.popen(('dir /b /ad "%s" 2>nul'):format(path:gsub('/', '\\')))
        if not p then return out end
        for line in p:lines() do out[#out + 1] = line end
        p:close()
        return out
    end
    local cache = {}
    r.EnumerateSubdirectories = function(path, i)
        if not cache[path] then cache[path] = ListDirs(path) end
        return cache[path][i + 1]
    end
    dofile(_dir .. 'corpus.lua')

    local n = 0
    for _, root in ipairs({
        _root .. '_external_docs/reference_songs/',
        _root .. '_external_docs/new_reference_songs/',
        _root .. '_external_docs/hard_reference_songs/',
    }) do
        for _, s in ipairs(WalkCorpus(root)) do
            if s.song_id and not song_id[s.shortname] then
                song_id[s.shortname] = s.song_id
                n = n + 1
            end
        end
    end
    Msg(('  song_id recovered for %d songs\n\n'):format(n))
end

-- The RB3 DLC block. Ids outside it are older-catalogue re-releases whose numbering is not
-- comparable, so they are excluded rather than mixed into one timeline.
local BLOCK_LO, BLOCK_HI = 1000000, 1099999

-- CONTROLLING FOR RANK IS NOT OPTIONAL HERE. song_id correlates with rank on exactly the
-- instruments under test (vocals +0.22, Pro Keys -0.15, keys -0.13) because the top-end
-- songs were added by a deliberate hard-song search and those skew late. Since the model
-- under-predicts the top end on every instrument, a raw id-vs-residual trend measures
-- "later songs are harder" and reports it as "the ranks were still settling". Both raw and
-- partial are printed so the confound is visible rather than quietly corrected away.
local function PartialSpearman(a, b, c)
    local rab, rac, rbc = Spearman(a, b), Spearman(a, c), Spearman(b, c)
    if not (rab and rac and rbc) then return nil end
    local den = math.sqrt((1 - rac * rac) * (1 - rbc * rbc))
    if den < 1e-12 then return nil end
    return (rab - rac * rbc) / den
end

local probe2 = {}

Msg(('  %-10s %-6s %-9s %-9s %-9s %-22s %s\n')
    :format('inst', 'n', 'rho raw', 'rho|rank', 'id~rank', 'mean |residual|', 'reading'))
Msg('  ' .. string.rep('-', 94) .. '\n')

for _, inst in ipairs(INSTRUMENTS) do
    local p = probe1[inst]
    if p and p.fid then
        local d0, _ = Collect(inst, {})
        local t0 = Partition(d0, inst)
        local ids, res, rks = {}, {}, {}
        for _, i in ipairs(t0) do
            local sid = song_id[d0.names[i]]
            local rv  = p.fid.resid[i]
            if sid and rv and sid >= BLOCK_LO and sid <= BLOCK_HI then
                ids[#ids + 1] = sid
                res[#res + 1] = rv
                rks[#rks + 1] = d0.ranks[i]
            end
        end
        if #ids >= 30 then
            local rho     = Spearman(ids, res) or 0
            local partial = PartialSpearman(ids, res, rks) or 0
            local id_rank = Spearman(ids, rks) or 0
            -- Earliest and latest third by id, which says whether any trend is worth
            -- anything in rank points rather than only in correlation.
            local order = {}
            for k = 1, #ids do order[k] = k end
            table.sort(order, function(a, b) return ids[a] < ids[b] end)
            local third = math.floor(#order / 3)
            local function MeanOver(from, to)
                local s = 0
                for k = from, to do s = s + res[order[k]] end
                return s / (to - from + 1)
            end
            local early, late = MeanOver(1, third), MeanOver(#order - third + 1, #order)
            -- The reading comes from the PARTIAL, never the raw one.
            local reading = (partial <= -0.15) and 'settles over time'
                or (partial >= 0.15) and 'drifts WORSE over time'
                or 'no trend once rank is held fixed'
            probe2[inst] = { partial = partial, raw = rho, id_rank = id_rank }
            Msg(('  %-10s %-6d %+8.3f %+8.3f %+8.3f  early %5.1f -> late %5.1f  %s\n')
                :format(inst, #ids, rho, partial, id_rank, early, late, reading))
        else
            Msg(('  %-10s %-8d (too few in the RB3 DLC id block to test)\n')
                :format(inst, #ids))
        end
    end
end

----------------------------------------------------------------------
-- Predictions, marked
----------------------------------------------------------------------

Msg('\n\nPREDICTIONS RECORDED BEFORE RUNNING\n')
Msg(string.rep('-', 76) .. '\n')

local v = probe1.vocals
if v and v.res.song then
    local hit = v.res.song.rho >= 0.55
    Msg(('  1. Vocals is largely song-level: other ranks alone reach rho >= 0.55.\n'
        .. '     -> song-level rho %+.3f, chart rho %+.3f.  %s\n')
        :format(v.res.song.rho, v.res.chart.rho, hit and 'HIT' or 'MISSED'))
end
do
    local k, rk = probe2.keys, probe2.real_keys
    local g, dr = probe2.guitar, probe2.drum
    if k and rk and g and dr then
        -- Judged on the PARTIAL, which is the number the prediction should have named:
        -- the raw trend was always going to be contaminated by song_id tracking rank.
        local drifts   = (k.partial <= -0.15) and (rk.partial <= -0.15)
        local controls = (math.abs(g.partial) < 0.10) and (math.abs(dr.partial) < 0.10)
        Msg(('  2. Keys drifts (rho <= -0.15) where guitar and drums do not (|rho| < 0.10).\n'
            .. '     -> keys %+.3f, Pro Keys %+.3f (rank held fixed); guitar %+.3f, drums %+.3f.\n'
            .. '        controls behaved as predicted: %s\n'
            .. '        both keyboard parts drifted: %s  %s\n')
            :format(k.partial, rk.partial, g.partial, dr.partial,
                    controls and 'YES' or 'no',
                    drifts and 'YES' or 'no - Pro Keys only',
                    (drifts and controls) and 'HIT' or 'PARTIAL'))
    end
end

Msg('\nNeither probe fits a shipped model. lib/ and corpus_scores.csv are untouched.\n')

if _rf then
    _rf:close()
    io.write(('\n[report written to %s]\n'):format(_report))
end
