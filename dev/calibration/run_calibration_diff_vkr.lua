-- @description Rock Band Difficulty Calibration - compare two scoring runs
-- @author VeeKiraRay
-- @about
--   Diffs dev/calibration/corpus_scores_baseline.csv against corpus_scores.csv,
--   per factor and per song, so a change to the scorer can be judged by what it
--   actually moved rather than by whether the headline number went up.
--
--   This is why the baseline CSV is kept: after a scorer change, "did that help"
--   has two separate answers - did the measurements change in the direction and by
--   the magnitude predicted, and did the fit improve. The second is what
--   run_calibration_analysis_vkr.lua reports. The first can only be answered
--   against the previous measurements, and a remembered aggregate cannot say WHICH
--   songs moved.
--
--   Usage: rename corpus_scores.csv to corpus_scores_baseline.csv before a
--   rescore, run the rescore, then run this.
--
--   Reads two CSVs and nothing else. Touches no project state.
--   Results appear in the REAPER console (View > Show REAPER console).

r = reaper

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _new    = _dir .. 'corpus_scores.csv'
local _old    = _dir .. 'corpus_scores_baseline.csv'

ctx = nil

dofile(_dir .. 'difficulty_score.lua')  -- SCORE_FACTOR_KEYS
dofile(_dir .. 'difficulty_score_vocals.lua')  -- appends the vocal columns to it

-- How many of the biggest movers to name per factor. Enough to see whether the
-- movement clusters on a kind of song, few enough to read.
local N_MOVERS = 3

-- A factor that moved by less than this fraction is treated as unchanged, so
-- floating-point noise in the CSV's 6-decimal rounding does not fill the report.
local NOISE = 1e-6

local function Msg(s) r.ShowConsoleMsg(s) end

----------------------------------------------------------------------
-- CSV load
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
    if not header then return nil, 'empty file: ' .. path end
    return { header = header, rows = rows }
end

local function Field(csv, row, name)
    local i = csv.header[name]
    return i and row[i] or nil
end

-- Rows keyed by (shortname, instrument), which is what makes two runs comparable
-- even if the corpus grew or the walk order changed between them.
local function Index(csv)
    local by_key = {}
    for _, row in ipairs(csv.rows) do
        local sn   = Field(csv, row, 'shortname')
        local inst = Field(csv, row, 'instrument')
        if sn and inst then by_key[sn .. '\0' .. inst] = row end
    end
    return by_key
end

----------------------------------------------------------------------
-- Stats over the paired rows
----------------------------------------------------------------------

local function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then return 0 end
    if n == 1 then return sorted[1] end
    local idx = p * (n - 1) + 1
    local lo, hi = math.floor(idx), math.ceil(idx)
    if lo == hi then return sorted[lo] end
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo)
end

-- Relative change, with a guard for the many factors that are legitimately 0
-- (a chart with no chords has chord_span_mean 0 in both runs).
local function RelChange(old, new)
    if old == new then return 0 end
    local denom = math.abs(old)
    if denom < 1e-9 then
        -- 0 -> something is a real change but has no meaningful ratio. Report it as
        -- a full change rather than dividing by ~0 and printing astronomic numbers.
        return 1.0
    end
    return (new - old) / denom
end

local function CompareInstrument(old_csv, new_csv, old_idx, new_idx, inst)
    -- Paired keys only, in a stable order.
    local keys = {}
    for _, row in ipairs(new_csv.rows) do
        local sn = Field(new_csv, row, 'shortname')
        local it = Field(new_csv, row, 'instrument')
        if it == inst then
            local key = sn .. '\0' .. it
            if old_idx[key] then keys[#keys + 1] = { key = key, name = sn } end
        end
    end
    if #keys == 0 then return end

    Msg(('\n==============  %s  (%d paired rows)  ==============\n')
        :format(inst:upper(), #keys))
    Msg(('  %-16s %8s %8s %8s   %s\n')
        :format('factor', 'moved', 'mean', 'p90', 'biggest movers'))

    for _, k in ipairs(SCORE_FACTOR_KEYS) do
        if old_csv.header[k] and new_csv.header[k] then
            local mags, n_moved = {}, 0
            local movers = {}
            for _, e in ipairs(keys) do
                local o = tonumber(Field(old_csv, old_idx[e.key], k))
                local n = tonumber(Field(new_csv, new_idx[e.key], k))
                if o and n then
                    local rel = RelChange(o, n)
                    if math.abs(rel) > NOISE then n_moved = n_moved + 1 end
                    mags[#mags + 1] = math.abs(rel)
                    movers[#movers + 1] = { name = e.name, rel = rel, o = o, n = n }
                end
            end
            table.sort(mags)
            table.sort(movers, function(a, b) return math.abs(a.rel) > math.abs(b.rel) end)

            local sum = 0
            for _, m in ipairs(mags) do sum = sum + m end
            local mean = (#mags > 0) and (sum / #mags) or 0

            local names = {}
            for i = 1, math.min(N_MOVERS, #movers) do
                local m = movers[i]
                if math.abs(m.rel) > NOISE then
                    names[#names + 1] = ('%s %+.1f%%'):format(m.name, m.rel * 100)
                end
            end

            Msg(('  %-16s %7d%% %7.2f%% %7.2f%%   %s\n'):format(
                k,
                (#mags > 0) and math.floor(n_moved / #mags * 100 + 0.5) or 0,
                mean * 100,
                Percentile(mags, 0.90) * 100,
                table.concat(names, ', ')))
        else
            Msg(('  %-16s   (absent from one of the two runs)\n'):format(k))
        end
    end
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

r.ClearConsole()
Msg('======  Difficulty calibration - run comparison  ======\n')

local old_csv, err1 = LoadCsv(_old)
local new_csv, err2 = LoadCsv(_new)
if not old_csv or not new_csv then
    Msg(('\nCould not read both runs.\n  %s\n')
        :format(tostring(err1 or err2)))
    Msg('\nExpected two files side by side:\n')
    Msg('  corpus_scores_baseline.csv   the previous run\n')
    Msg('  corpus_scores.csv            the current run\n\n')
    Msg('Rename the old CSV to corpus_scores_baseline.csv BEFORE rescoring.\n')
    return
end

local old_idx, new_idx = Index(old_csv), Index(new_csv)

-- Row coverage first: an unpaired row is either a song added since the baseline or
-- one that failed to score this time, and the second matters.
local n_old_only, n_new_only = 0, 0
for key in pairs(old_idx) do if not new_idx[key] then n_old_only = n_old_only + 1 end end
for key in pairs(new_idx) do if not old_idx[key] then n_new_only = n_new_only + 1 end end

Msg(('\nbaseline : %s  (%d rows)\n'):format(_old:match('[^/\\]+$'), #old_csv.rows))
Msg(('current  : %s  (%d rows)\n'):format(_new:match('[^/\\]+$'), #new_csv.rows))
Msg(('only in baseline : %d%s\n'):format(
    n_old_only, n_old_only > 0 and '   <-- rows that stopped scoring' or ''))
Msg(('only in current  : %d%s\n'):format(
    n_new_only, n_new_only > 0 and '   (songs added since the baseline)' or ''))

Msg('\n"moved" is the share of paired rows whose value changed at all; mean and p90\n')
Msg('are the size of the relative change. A factor expected to be untouched by a\n')
Msg('change should read 0% moved - if it does not, the change reached further than\n')
Msg('intended, which is more informative than the headline accuracy either way.\n')

local seen, order = {}, {}
for _, row in ipairs(new_csv.rows) do
    local inst = Field(new_csv, row, 'instrument')
    if inst and not seen[inst] then
        seen[inst] = true
        order[#order + 1] = inst
    end
end

for _, inst in ipairs(order) do
    CompareInstrument(old_csv, new_csv, old_idx, new_idx, inst)
end

Msg('\nNext: run_calibration_analysis_vkr.lua for whether the fit improved.\n')
Msg('The two questions are separate - measurements can move correctly while the\n')
Msg('fit barely responds, which is itself a finding about the factor.\n')
