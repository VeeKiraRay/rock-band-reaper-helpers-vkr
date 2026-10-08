-- @description Rock Band Difficulty Probe - official tiers vs the Difficulty validators
-- @author VeeKiraRay
-- @about
--   Read-only research run for the planned Difficulty > Generate feature. Walks the
--   official RB3 DLC charts, imports each selected song, and for Guitar, Bass and
--   5-lane Keys asks two questions of the OFFICIAL Hard, Medium and Easy tiers:
--
--     1. Validator agreement - how often does each rule the Difficulty tab's Validate
--        reports fire on a chart Harmonix shipped? A rule that official charts break
--        routinely is too strict, and a generator that enforced it would strip notes
--        a real charter keeps.
--     2. Tier differences - what each step down (X>H, H>M, M>E) keeps, by beat
--        position; how chords and colours are remapped; what happens to sustains;
--        how tight the tightest gaps are.
--
--   It runs the real validators (CollectGBChecks / CollectK5Checks) on real imported
--   tracks with REAPER's own tempo map, so what it measures is exactly what the
--   Validate button would say.
--
--   It also measures, per tier and tempo band, the gaps official charts actually use
--   (start to start, and from a sustain's end to the next note) and how much of each
--   chart sits on Blue and Orange - the numbers a loosened rule's threshold comes from.
--
--   Selection: PROBE_MODE 'easiest' takes the PROBE_N lowest-ranked songs per
--   instrument; 'random' takes PROBE_N seeded-random ones; 'all' takes every song.
--   In every mode, songs in the
--   HOLD-OUT (a fixed hash of the shortname, see difficulty_holdout.lua) are never probed, so the
--   generator can later be scored on charts that did not shape its rules.
--
--   Writes, beside this script (all gitignored):
--     difficulty_probe_report.txt  - the readable summary
--     difficulty_probe_tiers.csv   - one row per (song, instrument, tier)
--     difficulty_probe_rules.csv   - one row per (song, instrument, tier, rule) that fired
--   Song shortnames and derived numbers only; no chart content.
--
--   Imports tracks and restores the tempo map around each song, so RUN IT IN A
--   SCRATCH PROJECT. Run the repo copy (Actions > Load ReaScript), not a deployed one:
--   the corpus is found relative to this script and _external_docs/ is never deployed.

r = reaper

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

-- Each keeps a value a driver set before dofile'ing this script (an offline runner),
-- and otherwise takes the default after `or`. Edit the defaults to change a REAPER run.
PROBE_MODE  = PROBE_MODE or 'easiest'  -- 'easiest', 'random', or 'all' (every song outside the hold-out)
PROBE_N     = PROBE_N    or 30         -- songs per instrument (ignored by 'all')
PROBE_SEED  = PROBE_SEED or 20261003   -- for 'random'; change it to draw a different sample

-- The hold-out (one song in five, never probed in any mode) is defined in
-- difficulty_holdout.lua, shared with run_generate_eval_offline.lua.

local PROBE_INSTRUMENTS = {
    { key = 'guitar', track = 'PART GUITAR', kind = 'gb', label = 'Guitar' },
    { key = 'bass',   track = 'PART BASS',   kind = 'gb', label = 'Bass'   },
    { key = 'keys',   track = 'PART KEYS',   kind = 'k5', label = 'Keys'   },
}

local TIERS = { 'X', 'H', 'M', 'E' }
local UPPER = { H = 'X', M = 'H', E = 'M' }

-- Onsets closer than this (quarter notes) count as the same note across two tiers.
local MATCH_QN = 0.05
-- Beat-position classification tolerance (quarter notes).
local CLASS_QN = 0.02
-- A note at least this long (quarter notes) counts as a sustain for the tier diff.
-- A dotted 8th: the guitar sustain threshold above 100 BPM, and roughly where a
-- tail starts to show on every 5-lane instrument.
local SUSTAIN_QN = 0.75
-- A note at least this long counts as sustained for the release-gap measurement: the
-- same "1/8 note or longer" test the Medium/Easy sustain-gap rules apply.
local RELEASE_SUS_QN = 0.49

-- Gap histogram buckets (quarter notes), named by the subdivision a gap is at least
-- (with 5% grace, as the validators allow). Tempo bands for splitting them.
local GAP_BUCKETS = {
    { name = '<1/16', min = 0 },
    { name = '1/16',  min = 0.25 * 0.95 },
    { name = '1/8T',  min = 1/3 * 0.95 },
    { name = '1/8',   min = 0.5 * 0.95 },
    { name = 'd8th',  min = 0.75 * 0.95 },
    { name = '1/4',   min = 1.0 * 0.95 },
    { name = '1/2+',  min = 2.0 * 0.95 },
}
local BPM_BANDS = {
    { name = '<=100',   max = 100 },
    { name = '101-140', max = 140 },
    { name = '141+',    max = math.huge },
}

----------------------------------------------------------------------
-- Paths and loading
----------------------------------------------------------------------

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')            -- dev/calibration/
local function _strip(d)
    return (d:match('^(.+)[/\\]+$') or d):match('^(.+[/\\])') or d
end
local _root   = _strip(_strip(_dir))                    -- repo root
local _mdir   = _root .. 'rock_band_general_helper_vkr/'
SCRIPT_MDIR   = _mdir
SCRIPT_DIR    = _root

-- Only the official RB3 DLC root: its charts are Harmonix-authored at all four tiers.
local CORPUS_ROOT = _root .. '_external_docs/all_rb3_dlc_reference_songs/'

local OUT_REPORT = _dir .. 'difficulty_probe_report.txt'
local OUT_TIERS  = _dir .. 'difficulty_probe_tiers.csv'
local OUT_RULES  = _dir .. 'difficulty_probe_rules.csv'

ctx = nil

dofile(_root .. 'lib/reaper_imgui_helpers.lua')     -- FormatTime, PitchName
dofile(_root .. 'lib/reaper_midi_helpers.lua')
dofile(_root .. 'lib/reaper_guitar_theory.lua')
dofile(_root .. 'lib/reaper_difficulty_score.lua')  -- NormalizeSpans, for difficulty_read.lua
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_mdir .. 'defaults.lua')
dofile(_mdir .. 'helpers.lua')                      -- GetTempoContextBefore
dofile(_mdir .. 'actions_guitar.lua')               -- GetBPMAt
dofile(_mdir .. 'actions_guitar_validate.lua')      -- SustainThresholds
dofile(_mdir .. 'actions_difficulty_shared.lua')
dofile(_mdir .. 'actions_difficulty_5k.lua')
dofile(_mdir .. 'actions_difficulty_gtrbass.lua')
dofile(_dir  .. 'difficulty_holdout.lua')           -- DiffIsHeldOut, DIFF_HOLDOUT_MOD
dofile(_dir  .. 'songs_dta.lua')                    -- ParseSongsDta, DtaRank
dofile(_dir  .. 'corpus.lua')                       -- WalkCorpus, ImportSongMidi, CleanupImport,
                                                    -- FindTrackExact (via difficulty_read.lua)

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

-- Seeded LCG for 'random', independent of math.random so a seed means the same sample
-- everywhere (math.random's generator differs between Lua versions).
local function Shuffle(list, seed)
    local state = seed & 0x7fffffff
    for i = #list, 2, -1 do
        state = (state * 1103515245 + 12345) & 0x7fffffff
        local j = state % i + 1
        list[i], list[j] = list[j], list[i]
    end
end

----------------------------------------------------------------------
-- Per-tier measurement
----------------------------------------------------------------------

local function ReadTier(kind, track, dl)
    if kind == 'gb' then return ReadGBTierEvents(track, dl) end
    return ReadK5TierEvents(track, dl)
end

local function CheckTier(kind, dl, events, track)
    if kind == 'gb' then return CollectGBChecks(dl, events, track) end
    return CollectK5Checks(dl, events)
end

local function RangeFor(kind) return kind == 'gb' and GB_RANGE or K5_RANGE end

local function NearInt(x, tol) return math.abs(x - math.floor(x + 0.5)) <= tol end

-- Beat-position class of an onset: down (bar line), beat, 8th, 16th, triplet, other.
local function BeatClass(t, qn)
    local beat_in_bar = r.TimeMap2_timeToBeats(0, t)
    if beat_in_bar <= CLASS_QN then return 'down' end
    if NearInt(qn, CLASS_QN)         then return 'beat' end
    if NearInt(qn * 2, CLASS_QN * 2) then return '8th'  end
    if NearInt(qn * 4, CLASS_QN * 4) then return '16th' end
    if NearInt(qn * 3, CLASS_QN * 3) or NearInt(qn * 6, CLASS_QN * 6) then return 'trip' end
    return 'other'
end
local CLASSES = { 'down', 'beat', '8th', '16th', 'trip', 'other' }

local function Annotate(events)
    for _, ev in ipairs(events) do
        ev.qn    = r.TimeMap2_timeToQN(0, ev.s)
        ev.qn_e  = r.TimeMap2_timeToQN(0, ev.e)
        ev.class = BeatClass(ev.s, ev.qn)
        ev.bpm   = GetBPMAt(ev.s)   -- quarter notes per minute; the "divided" BPM is 2x in /8
    end
end

local function GapBucket(gap)
    local name = GAP_BUCKETS[1].name
    for _, b in ipairs(GAP_BUCKETS) do
        if gap >= b.min then name = b.name end
    end
    return name
end

local function BpmBand(bpm)
    for _, b in ipairs(BPM_BANDS) do
        if bpm <= b.max then return b.name end
    end
end

-- hist[band][bucket] += 1, plus hist[band].n
local function HistAdd(hist, bpm, gap)
    local band = BpmBand(bpm)
    hist[band] = hist[band] or { n = 0 }
    local h = hist[band]
    local bucket = GapBucket(gap)
    h[bucket] = (h[bucket] or 0) + 1
    h.n = h.n + 1
end

local function Percentile(sorted, p)
    if #sorted == 0 then return nil end
    local idx = math.max(1, math.min(#sorted, math.floor(p * (#sorted - 1) + 0.5) + 1))
    return sorted[idx]
end

local function GapStats(events)
    local gaps = {}
    for i = 2, #events do gaps[#gaps + 1] = events[i].qn - events[i - 1].qn end
    table.sort(gaps)
    return gaps[1], Percentile(gaps, 0.10), Percentile(gaps, 0.50)
end

local COLORS = { [0] = 'G', 'R', 'Y', 'B', 'O' }
local function Shape(pitches, lo)
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = COLORS[p - lo] or '?' end
    return table.concat(parts)
end

-- Match lower-tier onsets to upper-tier onsets (both sorted). Returns the upper index
-- each lower event matched (or nil) and the matched flag per upper event.
local function MatchTiers(upper, lower)
    local low_to_up, up_matched = {}, {}
    local j = 1
    for i, lev in ipairs(lower) do
        while j <= #upper and upper[j].qn < lev.qn - MATCH_QN do j = j + 1 end
        if j <= #upper and math.abs(upper[j].qn - lev.qn) <= MATCH_QN then
            low_to_up[i] = j
            up_matched[j] = true
        end
    end
    return low_to_up, up_matched
end

----------------------------------------------------------------------
-- Aggregates
----------------------------------------------------------------------

-- AGG[inst][tier] = { songs, rules = { [rule] = { songs_hit, errors, advisories,
--                     worst_song, worst_n, name } } }
-- PAIR[inst][tier] = { songs, up_events, low_events, added, by_class = { [c] = {n, kept} },
--                      shapes = { [key] = n }, sus_up, sus_kept, keep_fracs = {} }
-- GAPS[inst][tier] = { start = hist, release = hist, sustains }  (see HistAdd)
-- COLOR[inst][tier] = { { blue, orange, song }... }  per-song share of notes
local AGG, PAIR, GAPS, COLOR = {}, {}, {}, {}
local tier_rows, rule_rows = {}, {}

local function Bucket(t, a, b, init)
    t[a] = t[a] or {}
    if t[a][b] == nil then t[a][b] = init() end
    return t[a][b]
end

local function ProbeInstrument(song, inst, rank, from_idx)
    local track = FindTrackExact(inst.track, from_idx)
    if not track then return ('%s: rank %d but no %s track'):format(song.shortname, rank, inst.track) end

    local range = RangeFor(inst.kind)
    local ev_by_tier = {}
    for _, dl in ipairs(TIERS) do
        local events = ReadTier(inst.kind, track, dl)
        Annotate(events)
        ev_by_tier[dl] = events
    end
    if #ev_by_tier.X == 0 then return ('%s: %s has no Expert notes'):format(song.shortname, inst.track) end

    local bpm_first = GetBPMAt(ev_by_tier.X[1].s)

    for _, dl in ipairs(TIERS) do
        local events = ev_by_tier[dl]
        local row = {
            song.shortname, inst.key, rank, ('%.1f'):format(bpm_first), dl, #events,
        }
        local n_notes, n_blue, n_orange = 0, 0, 0
        local lo = range[dl].lo
        for _, ev in ipairs(events) do
            n_notes = n_notes + #ev.pitches
            for _, p in ipairs(ev.pitches) do
                if p - lo == 3 then n_blue = n_blue + 1 elseif p - lo == 4 then n_orange = n_orange + 1 end
            end
        end
        row[#row + 1] = n_notes
        local share_b = n_notes > 0 and n_blue / n_notes or 0
        local share_o = n_notes > 0 and n_orange / n_notes or 0
        row[#row + 1] = ('%.3f'):format(share_b)
        row[#row + 1] = ('%.3f'):format(share_o)

        if #events > 0 then
            local cl = Bucket(COLOR, inst.key, dl, function() return {} end)
            cl[#cl + 1] = { blue = share_b, orange = share_o, song = song.shortname }

            -- Gaps official charts use: start to start, and sustain end to next onset.
            local gp = Bucket(GAPS, inst.key, dl, function() return { start = {}, release = {}, sustains = 0 } end)
            for i = 2, #events do
                HistAdd(gp.start, events[i].bpm, events[i].qn - events[i - 1].qn)
            end
            for i = 1, #events - 1 do
                local ev, nx = events[i], events[i + 1]
                if ev.qn_e - ev.qn >= RELEASE_SUS_QN and nx.qn >= ev.qn_e - 0.001 then
                    gp.sustains = gp.sustains + 1
                    HistAdd(gp.release, ev.bpm, nx.qn - ev.qn_e)
                end
            end
        end

        -- Tier diff against the tier above.
        local up_dl = UPPER[dl]
        local keep_frac, added = '', ''
        if up_dl and #events > 0 and #ev_by_tier[up_dl] > 0 then
            local upper = ev_by_tier[up_dl]
            local low_to_up, up_matched = MatchTiers(upper, events)
            local pr = Bucket(PAIR, inst.key, dl, function()
                return { songs = 0, up_events = 0, low_events = 0, added = 0, by_class = {},
                         shapes = {}, sus_up = 0, sus_kept = 0, keep_fracs = {} }
            end)
            pr.songs      = pr.songs + 1
            pr.up_events  = pr.up_events + #upper
            pr.low_events = pr.low_events + #events
            local kept = 0
            for j, uev in ipairs(upper) do
                local c = pr.by_class[uev.class] or { n = 0, kept = 0 }
                pr.by_class[uev.class] = c
                c.n = c.n + 1
                if up_matched[j] then c.kept = c.kept + 1; kept = kept + 1 end
            end
            local n_added = 0
            for i, lev in ipairs(events) do
                local j = low_to_up[i]
                if not j then
                    n_added = n_added + 1
                else
                    local uev = upper[j]
                    local key = Shape(uev.pitches, range[up_dl].lo) .. '>' .. Shape(lev.pitches, range[dl].lo)
                    pr.shapes[key] = (pr.shapes[key] or 0) + 1
                    if uev.qn_e - uev.qn >= SUSTAIN_QN then
                        pr.sus_up = pr.sus_up + 1
                        if lev.qn_e - lev.qn >= SUSTAIN_QN then pr.sus_kept = pr.sus_kept + 1 end
                    end
                end
            end
            pr.added = pr.added + n_added
            keep_frac = ('%.3f'):format(kept / #upper)
            pr.keep_fracs[#pr.keep_fracs + 1] = { frac = kept / #upper, song = song.shortname, rank = rank }
            added = n_added
        end
        row[#row + 1] = keep_frac
        row[#row + 1] = added

        local gmin, gp10, gmed = GapStats(events)
        row[#row + 1] = gmin and ('%.3f'):format(gmin) or ''
        row[#row + 1] = gp10 and ('%.3f'):format(gp10) or ''
        row[#row + 1] = gmed and ('%.3f'):format(gmed) or ''

        -- Validator agreement, official H/M/E only: Expert is the source, not a target.
        local err_total, adv_total = 0, 0
        if dl ~= 'X' and #events > 0 then
            local ag = Bucket(AGG, inst.key, dl, function() return { songs = 0, rules = {} } end)
            ag.songs = ag.songs + 1
            for _, cat in ipairs(CheckTier(inst.kind, dl, events, track)) do
                local n_err, n_adv = 0, 0
                for _, rec in ipairs(cat.issues) do
                    if cat.advisory or rec.advisory then n_adv = n_adv + 1 else n_err = n_err + 1 end
                end
                local ru = ag.rules[cat.rule] or { songs_hit = 0, errors = 0, advisories = 0,
                                                    worst_n = 0, name = cat.name }
                ag.rules[cat.rule] = ru
                if n_err + n_adv > 0 then
                    ru.songs_hit  = ru.songs_hit + 1
                    ru.errors     = ru.errors + n_err
                    ru.advisories = ru.advisories + n_adv
                    if n_err + n_adv > ru.worst_n then
                        ru.worst_n, ru.worst_song = n_err + n_adv, song.shortname
                    end
                    rule_rows[#rule_rows + 1] = { song.shortname, inst.key, dl, cat.rule, n_err, n_adv }
                end
                err_total, adv_total = err_total + n_err, adv_total + n_adv
            end
        end
        row[#row + 1] = dl ~= 'X' and err_total or ''
        row[#row + 1] = dl ~= 'X' and adv_total or ''
        tier_rows[#tier_rows + 1] = row
    end
    return nil
end

----------------------------------------------------------------------
-- Output
----------------------------------------------------------------------

local function WriteCsv(path, header, rows)
    local f = io.open(path, 'w')
    if not f then return false end
    f:write(table.concat(header, ','), '\n')
    for _, row in ipairs(rows) do
        local cells = {}
        for i, v in ipairs(row) do cells[i] = tostring(v) end
        f:write(table.concat(cells, ','), '\n')
    end
    f:close()
    return true
end

local function SortedKeys(t, cmp)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, cmp)
    return keys
end

local function BuildReport(lines, selected_counts, n_held)
    local function L(s) lines[#lines + 1] = s or '' end
    L('Difficulty probe - official tiers vs the Difficulty validators')
    L(('Mode %s, %s songs per instrument%s, hold-out 1 in %d (%d songs held out of the pool)')
        :format(PROBE_MODE, PROBE_MODE == 'all' and 'all' or tostring(PROBE_N),
                PROBE_MODE == 'random' and (', seed ' .. PROBE_SEED) or '',
                DIFF_HOLDOUT_MOD, n_held))
    for _, inst in ipairs(PROBE_INSTRUMENTS) do
        L(('  %s: %d songs selected'):format(inst.label, selected_counts[inst.key] or 0))
    end
    L()

    L('=== 1. Validator agreement on OFFICIAL charts ===')
    L('songs% = share of probed songs where the rule fired at least once. A rule that')
    L('fires on many official charts is a candidate for loosening before Generate enforces it.')
    L()
    for _, inst in ipairs(PROBE_INSTRUMENTS) do
        for _, dl in ipairs({ 'H', 'M', 'E' }) do
            local ag = AGG[inst.key] and AGG[inst.key][dl]
            if ag then
                L(('%s %s  (%d songs)'):format(inst.label, dl, ag.songs))
                L(('  %-18s %6s %7s %7s  %-24s %s'):format('rule', 'songs%', 'errors', 'advis.', 'worst song', 'category'))
                for _, rule in ipairs(SortedKeys(ag.rules)) do
                    local ru = ag.rules[rule]
                    L(('  %-18s %5.0f%% %7d %7d  %-24s %s'):format(
                        rule, 100 * ru.songs_hit / ag.songs, ru.errors, ru.advisories,
                        ru.worst_song and (ru.worst_song .. ' (' .. ru.worst_n .. ')') or '-', ru.name))
                end
                L()
            end
        end
    end

    L('=== 2. What each step down keeps ===')
    for _, inst in ipairs(PROBE_INSTRUMENTS) do
        for _, dl in ipairs({ 'H', 'M', 'E' }) do
            local pr = PAIR[inst.key] and PAIR[inst.key][dl]
            if pr then
                L(('%s %s>%s  (%d songs, %d > %d events, %d onsets new on the lower tier)'):format(
                    inst.label, UPPER[dl], dl, pr.songs, pr.up_events, pr.low_events, pr.added))
                local cells = {}
                for _, c in ipairs(CLASSES) do
                    local b = pr.by_class[c]
                    if b and b.n > 0 then
                        cells[#cells + 1] = ('%s %.0f%% of %d'):format(c, 100 * b.kept / b.n, b.n)
                    end
                end
                L('  kept by position: ' .. table.concat(cells, ', '))
                if pr.sus_up > 0 then
                    L(('  sustains kept as sustains: %.0f%% of %d'):format(100 * pr.sus_kept / pr.sus_up, pr.sus_up))
                end
                table.sort(pr.keep_fracs, function(a, b) return a.frac > b.frac end)
                local hi, lo = pr.keep_fracs[1], pr.keep_fracs[#pr.keep_fracs]
                local fr = {}
                for _, k in ipairs(pr.keep_fracs) do fr[#fr + 1] = k.frac end
                table.sort(fr)
                L(('  per-song keep: min %.0f%% (%s, rank %d), median %.0f%%, max %.0f%% (%s, rank %d)'):format(
                    100 * lo.frac, lo.song, lo.rank, 100 * Percentile(fr, 0.5), 100 * hi.frac, hi.song, hi.rank))
                local keys = SortedKeys(pr.shapes, function(a, b) return pr.shapes[a] > pr.shapes[b] end)
                local top = {}
                for i = 1, math.min(18, #keys) do
                    top[#top + 1] = ('%s %d'):format(keys[i], pr.shapes[keys[i]])
                end
                L('  top shape mappings (upper>lower): ' .. table.concat(top, ', '))
                L()
            end
        end
    end

    L('=== 3. Gaps official charts use, by tempo band ===')
    L('Each cell: share of gaps that are AT LEAST that subdivision but less than the next')
    L('(5% grace). "start" = onset to onset; "release" = end of a sustained note (1/8 or')
    L('longer) to the next onset - what the sustain-gap rules measure.')
    L()
    local function HistLines(label, hist)
        local hdr = { ('    %-8s %-8s %7s'):format(label, 'bpm', 'n') }
        for _, b in ipairs(GAP_BUCKETS) do hdr[#hdr + 1] = ('%6s'):format(b.name) end
        L(table.concat(hdr, ' '))
        for _, band in ipairs(BPM_BANDS) do
            local h = hist[band.name]
            if h and h.n > 0 then
                local cells = { ('    %-8s %-8s %7d'):format('', band.name, h.n) }
                for _, b in ipairs(GAP_BUCKETS) do
                    cells[#cells + 1] = ('%5.1f%%'):format(100 * (h[b.name] or 0) / h.n)
                end
                L(table.concat(cells, ' '))
            end
        end
    end
    for _, inst in ipairs(PROBE_INSTRUMENTS) do
        for _, dl in ipairs(TIERS) do
            local gp = GAPS[inst.key] and GAPS[inst.key][dl]
            if gp then
                L(('%s %s  (%d sustained notes followed by a note)'):format(inst.label, dl, gp.sustains))
                HistLines('start', gp.start)
                HistLines('release', gp.release)
                L()
            end
        end
    end

    L('=== 4. Blue and Orange use per song ===')
    L('Share of a tier\'s notes on each colour, across songs. "any" = songs using it at all.')
    L()
    for _, inst in ipairs(PROBE_INSTRUMENTS) do
        for _, dl in ipairs(TIERS) do
            local cl = COLOR[inst.key] and COLOR[inst.key][dl]
            if cl and #cl > 0 then
                for _, col in ipairs({ 'blue', 'orange' }) do
                    local vals, any, top = {}, 0, nil
                    for _, c in ipairs(cl) do
                        vals[#vals + 1] = c[col]
                        if c[col] > 0 then any = any + 1 end
                        if not top or c[col] > top[col] then top = c end
                    end
                    table.sort(vals)
                    L(('  %-6s %s %-6s any %3.0f%%  median %5.1f%%  p90 %5.1f%%  max %5.1f%% (%s)  [%d songs]'):format(
                        inst.label, dl, col, 100 * any / #cl, 100 * Percentile(vals, 0.5),
                        100 * Percentile(vals, 0.9), 100 * top[col], top.song, #cl))
                end
            end
        end
        L()
    end

    L('Per-song numbers are in difficulty_probe_tiers.csv and difficulty_probe_rules.csv.')
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

r.ClearConsole()
r.ShowConsoleMsg('======  Difficulty probe - official tiers vs validators  ======\n\n')

local by_name = {}
for _, song in ipairs(WalkCorpus(CORPUS_ROOT)) do
    local cur = by_name[song.shortname]
    if not cur or (not cur.midi_path and song.midi_path) then by_name[song.shortname] = song end
end

local pool, n_held = {}, 0
for _, song in pairs(by_name) do
    if song.midi_path then
        if DiffIsHeldOut(song.shortname) then n_held = n_held + 1 else pool[#pool + 1] = song end
    end
end
table.sort(pool, function(a, b) return a.shortname < b.shortname end)

if #pool == 0 then
    r.ShowConsoleMsg('No songs found under ' .. CORPUS_ROOT .. '\n')
    r.ShowConsoleMsg('Run the repo copy of this script; _external_docs/ is never deployed.\n')
    return
end

-- todo[shortname] = { song, insts = { inst... } }
local todo, selected_counts = {}, {}
for _, inst in ipairs(PROBE_INSTRUMENTS) do
    local cands = {}
    for _, song in ipairs(pool) do
        if DtaRank(song, inst.key) then cands[#cands + 1] = song end
    end
    local take_n = PROBE_MODE == 'all' and #cands or math.min(PROBE_N, #cands)
    if PROBE_MODE == 'random' then
        Shuffle(cands, PROBE_SEED)
    elseif PROBE_MODE == 'all' then
        -- pool order (by shortname); every candidate is taken
    else
        table.sort(cands, function(a, b)
            local ra, rb = DtaRank(a, inst.key), DtaRank(b, inst.key)
            if ra ~= rb then return ra < rb end
            return a.shortname < b.shortname
        end)
    end
    for i = 1, take_n do
        local song = cands[i]
        todo[song.shortname] = todo[song.shortname] or { song = song, insts = {} }
        local t = todo[song.shortname].insts
        t[#t + 1] = inst
    end
    selected_counts[inst.key] = take_n
end

local names = SortedKeys(todo)
r.ShowConsoleMsg(('Pool %d songs (%d held out). Probing %d songs.\n\n'):format(#pool, n_held, #names))

local warnings = {}
local baseline = r.CountTracks(0)
local TEMPO_CHECK_AFTER = 12
local n_tempo_seen, n_tempo_flat = 0, 0

r.PreventUIRefresh(1)
for si, name in ipairs(names) do
    local entry = todo[name]
    local from_idx, added = ImportSongMidi(entry.song.midi_path)
    if added == 0 then
        warnings[#warnings + 1] = ('IMPORT FAILED  %s (created no tracks)'):format(name)
    else
        -- Tempo-import tripwire, as in run_calibration_vkr.lua: a run where REAPER drops
        -- the MIDI tempo map measures every grid position wrongly. Stop while it is cheap.
        n_tempo_seen = n_tempo_seen + 1
        if r.CountTempoTimeSigMarkers(0) <= 1 then n_tempo_flat = n_tempo_flat + 1 end
        if n_tempo_seen == math.min(TEMPO_CHECK_AFTER, #names) and n_tempo_flat == n_tempo_seen
           and n_tempo_seen >= 3 then
            CleanupImport(from_idx)
            r.PreventUIRefresh(-1)
            r.ShowConsoleMsg(('\nSTOPPING: the first %d songs imported with NO tempo map.\n'):format(n_tempo_seen))
            r.ShowConsoleMsg('Check the MIDI import preferences (import tempo map) and re-run.\n')
            return
        end
        for _, inst in ipairs(entry.insts) do
            local ok, err = pcall(ProbeInstrument, entry.song, inst, DtaRank(entry.song, inst.key), from_idx)
            if not ok then
                warnings[#warnings + 1] = ('ERROR  %s %s: %s'):format(name, inst.key, tostring(err))
            elseif err then
                warnings[#warnings + 1] = 'SKIPPED  ' .. err
            end
        end
    end
    -- Always clean up, even after a failed import: leftover tracks make every later
    -- InsertMedia append to an existing track instead of creating one.
    CleanupImport(from_idx)
    if si % 10 == 0 then
        r.ShowConsoleMsg(('  ... %d/%d songs\n'):format(si, #names))
    end
end
r.PreventUIRefresh(-1)
r.UpdateArrange()

WriteCsv(OUT_TIERS, { 'shortname', 'instrument', 'rank', 'bpm_first', 'tier', 'events', 'notes',
                      'blue_share', 'orange_share', 'keep_frac_vs_upper', 'onsets_added', 'gap_min_qn', 'gap_p10_qn', 'gap_med_qn',
                      'errors', 'advisories' }, tier_rows)
WriteCsv(OUT_RULES, { 'shortname', 'instrument', 'tier', 'rule', 'errors', 'advisories' }, rule_rows)

local lines = {}
BuildReport(lines, selected_counts, n_held)
if #warnings > 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '-- warnings --'
    for _, w in ipairs(warnings) do lines[#lines + 1] = '  ' .. w end
end
local leftover = r.CountTracks(0) - baseline
lines[#lines + 1] = ''
lines[#lines + 1] = ('Leftover tracks: %d%s'):format(leftover, leftover == 0 and ' (clean)' or ' <-- CLEANUP FAILED')

local report = table.concat(lines, '\n') .. '\n'
local f = io.open(OUT_REPORT, 'w')
if f then f:write(report); f:close() end

-- The console truncates at about 16 KB; the file has everything.
r.ShowConsoleMsg(report:sub(1, 15000))
r.ShowConsoleMsg(('\nFull report: %s\n'):format(OUT_REPORT))
