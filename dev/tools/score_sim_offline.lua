-- Score a song MIDI offline with the Metadata > Score model.
--
--   lua dev/tools/score_sim_offline.lua [--autoplay] <song.mid> [more.mid ...]
--
-- --autoplay adds a Pro drums run that deploys anywhere the moment it is ready, with no
-- fill (what the game's autoplay does), for comparing with autoplay recordings.
--
-- Runs the shipped reader and simulator (lib/reaper_score_read.lua,
-- lib/reaper_score_sim.lua) against a REAPER stand-in built from the file through the
-- pure SMF reader, and prints per part: the no-overdrive full combo, the star cut-offs,
-- the score with overdrive deployed as soon as possible, coverage and the waste
-- findings. For checking the model against a known full-combo score of an official song
-- (a leaderboard entry or playthrough), and for the reader without REAPER.
--
-- The stand-in is the same shape as dev/tools/score_corpus_offline.lua's (one track per
-- SMF track, one item, one take, PPQ = the SMF tick), plus measures from the file's time
-- signatures. Only the calls the reader makes are implemented, so a missing one fails
-- loudly instead of returning a plausible default.

local _script = (arg and arg[0]) or 'dev/tools/score_sim_offline.lua'
local _dir    = _script:match('^(.+[/\\])') or 'dev/tools/'
local function _up(d) return d:match('^(.*[/\\])[^/\\]+[/\\]$') or '' end
local _root   = _up(_up(_dir))

local AUTOPLAY, FILES = false, {}
for i = 1, #(arg or {}) do
    if arg[i] == '--autoplay' then AUTOPLAY = true else FILES[#FILES + 1] = arg[i] end
end
if #FILES == 0 then
    print('usage: lua dev/tools/score_sim_offline.lua [--autoplay] <song.mid> [more.mid ...]')
    os.exit(1)
end

local _song, _map, _tracks, _measures

local function TickToSec(tick) return SmfTickToSec(_map, _song.tpqn, tick) end

local function SecToQN(t)
    local seg = _map[1]
    for i = 2, #_map do
        if _map[i].sec > t then break end
        seg = _map[i]
    end
    local tick = seg.tick + (t - seg.sec) * _song.tpqn * 1e6 / seg.uspqn
    return tick / _song.tpqn
end

-- Measure start ticks from every time signature in the file, up to a generous end.
local function BuildMeasures()
    local sigs = {}
    for _, trk in ipairs(_song.tracks) do
        for _, ts in ipairs(trk.timesigs) do sigs[#sigs + 1] = ts end
    end
    table.sort(sigs, function(a, b) return a.tick < b.tick end)
    local last = 0
    for _, trk in ipairs(_song.tracks) do
        for _, n in ipairs(trk.notes) do last = math.max(last, n.tick + n.len) end
    end
    local out, tick, num, den, si = {}, 0, 4, 4, 1
    while tick <= last + _song.tpqn * 8 do
        while sigs[si] and sigs[si].tick <= tick do num, den = sigs[si].num, sigs[si].den; si = si + 1 end
        local len = num * 4 / den * _song.tpqn
        out[#out + 1] = { s = tick, e = tick + len }
        tick = tick + len
    end
    return out
end

r = {
    CountTracks = function() return #_tracks end,
    GetTrack    = function(_, i) return _tracks[i + 1] end,
    GetSetMediaTrackInfo_String = function(tr, key)
        if key == 'P_NAME' then return true, tr.name or '' end
        return false, ''
    end,
    GetMediaTrackInfo_Value = function() return 0 end,
    CountTrackMediaItems    = function() return 1 end,
    GetTrackMediaItem       = function(tr) return tr end,
    GetActiveTake           = function(item) return item end,
    TakeIsMIDI              = function() return true end,
    MIDI_CountEvts = function(take) return true, #take.notes, 0, #take.texts end,
    MIDI_GetNote = function(take, j)
        local n = take.notes[j + 1]
        if not n then return false end
        return true, false, false, n.tick, n.tick + n.len, 0, n.pitch, 100
    end,
    MIDI_GetTextSysexEvt = function(take, j)
        local t = take.texts[j + 1]
        if not t then return false end
        return true, false, false, t.tick, t.type, t.text
    end,
    MIDI_GetProjTimeFromPPQPos = function(_, ppq) return TickToSec(ppq) end,
    MIDI_GetProjQNFromPPQPos   = function(_, ppq) return ppq / _song.tpqn end,
    TimeMap2_timeToQN          = function(_, t) return SecToQN(t) end,
    TimeMap_GetMeasureInfo     = function(_, m)
        local ms = _measures[m + 1] or _measures[#_measures]
        return TickToSec(ms.s), ms.s / _song.tpqn, ms.e / _song.tpqn
    end,
}

dofile(_root .. 'dev/tools/smf_reader.lua')
dofile(_root .. 'lib/reaper_difficulty_score.lua')         -- NormalizeSpans
dofile(_root .. 'lib/reaper_difficulty_score_vocals.lua')
dofile(_root .. 'lib/reaper_difficulty_read.lua')
dofile(_root .. 'lib/reaper_score_sim.lua')
dofile(_root .. 'lib/reaper_score_read.lua')

local function Num(n)
    local s = tostring(math.floor(n + 0.5))
    return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

local function Report(label, res, bars)
    local gold = res.gold_qn and ('gold from bar ' .. ScoreBarOf(bars, res.gold_qn))
                 or ('short of gold by ' .. Num(res.gold_short))
    print(('  %-10s full combo %s (bonus %s) | 5 stars %s, gold %s | with OD %s, %s')
        :format(label, Num(res.base_streak + res.base_bonus), Num(res.base_bonus),
                Num(res.stars[5]), Num(res.stars[6]), Num(res.total), gold))
end

for _, path in ipairs(FILES) do
    _song = SmfReadFile(path)
    if not _song then
        print('cannot read ' .. path)
    else
        _map = SmfTempoMap(_song)
        _tracks = {}
        for _, trk in ipairs(_song.tracks) do _tracks[#_tracks + 1] = trk end
        _measures = BuildMeasures()
        print(('\n%s'):format(path))
        local song = ScoreReadSong()
        if song.no_beat then print('  (no BEAT track: drain per quarter note)') end
        for _, spec in ipairs(SCORE_PARTS) do
            local part = song.parts[spec.key]
            if not part and spec.optional then
                -- PART DRUMS_2X missing or muted: left out, as in the Score tab.
            elseif not part then
                print(('  %-10s %s'):format(spec.label, song.reasons[spec.key] or '-'))
            else
                local runs = spec.kind == 'drums'
                    and { { 'Pro drums', { pro = true } }, { 'Drums', { pro = false } } }
                    or { { spec.label, {} } }
                if spec.kind == 'drums' and AUTOPLAY then
                    runs[#runs + 1] = { 'Pro auto', { pro = true, deploy_anywhere = true } }
                end
                local first
                for _, run in ipairs(runs) do
                    local res = ScoreSimulatePart(part, run[2])
                    first = first or res
                    Report(run[1], res, song.bars)
                end
                print('             ' .. (ScoreCoverageText(first) or 'never in overdrive'))
                for _, f in ipairs(ScoreFindings(first, song.bars, spec.kind)) do
                    local mark = f.level == 'warn' and '!' or f.level == 'advice' and '?' or '-'
                    print('             ' .. mark .. ' ' .. f.text)
                end
            end
        end
    end
end
