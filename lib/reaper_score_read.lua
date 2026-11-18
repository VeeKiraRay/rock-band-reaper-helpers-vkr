-- Reads a project into the parts lib/reaper_score_sim.lua simulates.
--
-- Shared by the General Helper's Metadata > Score and the Instrument Helper's
-- Overdrive > Validate, so both report the same overdrive coverage. Everything is in
-- quarter notes (what MIDI stores); seconds are added where the game's rules are in
-- seconds (the drum fill gate, the vocal deploy gap, the BRE's points).
--
-- Requires (globals): r, FindTrackExact, ReadGemEvents, ReadVocalNotes, ReadCodaTime
-- (lib/reaper_difficulty_read.lua)

-- kind = the simulator's part kind. `optional`: a missing, muted or empty track is left
-- out quietly instead of reported - PART DRUMS_2X is the same chart as PART DRUMS with
-- the second pedal's kicks, which many songs do not have.
-- `instrument`: the game's instrument class for unisons (PhraseAnalyzer's equivalent
-- track types) - Keys and Pro Keys are one, as are PART DRUMS and its 2X chart.
-- lo / hi: the Expert gem range (default 96-100); solo: the solo marker (default 103);
-- lane_lo / lane_hi: the fill / BRE lanes (default 120-124; Pro Keys has only 120).
SCORE_PARTS = {
    { key = 'guitar',  kind = 'guitar',  label = 'Guitar',   track = 'PART GUITAR',
      instrument = 'guitar' },
    { key = 'bass',    kind = 'bass',    label = 'Bass',     track = 'PART BASS',
      instrument = 'bass' },
    { key = 'drums',   kind = 'drums',   label = 'Drums',    track = 'PART DRUMS',
      instrument = 'drums' },
    { key = 'drums2x', kind = 'drums',   label = 'Drums 2X', track = 'PART DRUMS_2X',
      instrument = 'drums', optional = true },
    { key = 'keys',    kind = 'keys',    label = 'Keys',     track = 'PART KEYS',
      instrument = 'keys' },
    { key = 'prokeys', kind = 'prokeys', label = 'Pro Keys', track = 'PART REAL_KEYS_X',
      instrument = 'keys', lo = 48, hi = 72, solo = 115, lane_lo = 120, lane_hi = 120 },
    { key = 'vocals',  kind = 'vocals',  label = 'Vocals',   track = 'PART VOCALS' },
    -- Harmonies are another way to sing the same song: shown only when HARM1 and HARM2
    -- are there (optional), and left out of Validate - HARM1's overdrive is PART VOCALS'.
    { key = 'harmonies', kind = 'vocals', label = 'Harmonies', track = 'HARM1',
      harmony = true, optional = true },
}

local OD_PITCH, SOLO_PITCH = 116, 103
local FILL_LO, FILL_HI = 120, 124
local PERC_PITCH = 96               -- vocal percussion, the playable hit
local TOM_FOR = { [98] = 110, [99] = 111, [100] = 112 }

local function Takes(track)
    local out = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local take = r.GetActiveTake(r.GetTrackMediaItem(track, i))
        if take and r.TakeIsMIDI(take) then out[#out + 1] = take end
    end
    return out
end

-- Unmuted notes in [lo, hi] as { s, e (QN), s_sec, e_sec, pitch }, sorted by start.
local function Notes(track, lo, hi)
    local out = {}
    for _, take in ipairs(Takes(track)) do
        local _, n = r.MIDI_CountEvts(take)
        for i = 0, n - 1 do
            local ok, _, muted, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
            if ok and not muted and p >= lo and p <= hi then
                out[#out + 1] = {
                    s = r.MIDI_GetProjQNFromPPQPos(take, sppq),
                    e = r.MIDI_GetProjQNFromPPQPos(take, eppq),
                    s_sec = r.MIDI_GetProjTimeFromPPQPos(take, sppq),
                    e_sec = r.MIDI_GetProjTimeFromPPQPos(take, eppq),
                    pitch = p,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

-- Lanes (120-124, or the part's own) grouped by start: one span per fill (or BRE), all
-- lanes together.
local function LaneSpans(track, lo, hi)
    local out = {}
    for _, n in ipairs(Notes(track, lo or FILL_LO, hi or FILL_HI)) do
        local prev = out[#out]
        if prev and math.abs(prev.s - n.s) < 0.01 then
            if n.e > prev.e then prev.e, prev.e_sec = n.e, n.e_sec end
        else
            out[#out + 1] = { s = n.s, e = n.e, s_sec = n.s_sec, e_sec = n.e_sec }
        end
    end
    return out
end

local function InAny(spans, qn)
    for _, sp in ipairs(spans) do
        if qn >= sp.s - 1e-4 and qn < sp.e - 1e-4 then return true end
    end
    return false
end

-- BEAT track notes (12 downbeat, 13 upbeat) as QN positions.
function ScoreReadBeats()
    local tr = FindTrackExact('BEAT')
    local out = {}
    if not tr then return out end
    for _, n in ipairs(Notes(tr, 12, 13)) do
        if #out == 0 or n.s - out[#out] > 1e-4 then out[#out + 1] = n.s end
    end
    return out
end

-- Measures up to end_qn: { qn_s, qn_e }.
function ScoreReadBars(end_qn)
    local bars = {}
    for m = 0, 99999 do
        local _, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, m)
        if qn_s >= end_qn - 1e-4 then break end
        bars[#bars + 1] = { qn_s = qn_s, qn_e = qn_e }
    end
    return bars
end

-- 1-based measure number of a QN position.
function ScoreBarOf(bars, qn)
    local lo, hi = 1, #bars
    if hi == 0 then return 1 end
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if bars[mid].qn_s <= qn + 1e-4 then lo = mid else hi = mid - 1 end
    end
    return lo
end

local function Unavailable(tr, name)
    if not tr then return name .. ' not found' end
    if r.GetMediaTrackInfo_Value(tr, 'B_MUTE') == 1 then return name .. ' is muted' end
    if #Takes(tr) == 0 then return name .. ' has no MIDI' end
    return nil
end

-- One gem part: guitar, bass, drums (PART DRUMS or PART DRUMS_2X), keys or Pro Keys.
local function ReadGemPart(spec, coda_qn)
    local key, track_name = spec.kind, spec.track
    local tr = FindTrackExact(track_name)
    local why = Unavailable(tr, track_name)
    if why then return nil, why end

    local toms = {}
    if key == 'drums' then
        for gem, marker in pairs(TOM_FOR) do toms[gem] = Notes(tr, marker, marker) end
    end
    local gems = {}
    for _, ev in ipairs(ReadGemEvents(tr, spec.lo or 96, spec.hi or 100)) do
        local g = { qn = ev.qn, qn_e = ev.qn_e, sec = ev.s, n = #ev.pitches, toms = 0 }
        if key == 'drums' then
            for _, p in ipairs(ev.pitches) do
                if toms[p] and InAny(toms[p], ev.qn) then g.toms = g.toms + 1 end
            end
        end
        gems[#gems + 1] = g
    end
    if #gems == 0 then return nil, track_name .. ' has no Expert notes' end

    local function Spans(pitch)
        local out = {}
        for _, n in ipairs(Notes(tr, pitch, pitch)) do
            if n.e > n.s then out[#out + 1] = { s = n.s, e = n.e } end
        end
        return out
    end

    local part = { kind = key, track_name = track_name, gems = gems,
                   od = Spans(OD_PITCH), solos = Spans(spec.solo or SOLO_PITCH), fills = {} }
    for _, sp in ipairs(LaneSpans(tr, spec.lane_lo, spec.lane_hi)) do
        if coda_qn and sp.s >= coda_qn - 1e-4 then
            -- The game takes the last lane span after [coda] as the BRE.
            part.bre = { s = sp.s, e = sp.e, sec = sp.e_sec - sp.s_sec }
        elseif key == 'drums' then
            part.fills[#part.fills + 1] = sp
        end
    end
    return part
end

-- One vocal part from a track (PART VOCALS for solo vocals, HARM1 for harmonies): its
-- phrases (105/106), sung notes, percussion and overdrive.
local function ReadVocalPart(name)
    local tr = FindTrackExact(name)
    local why = Unavailable(tr, name)
    if why then return nil, why end

    local sung = ReadVocalNotes(tr)
    local perc = Notes(tr, PERC_PITCH, PERC_PITCH)
    local od = {}
    for _, n in ipairs(Notes(tr, OD_PITCH, OD_PITCH)) do od[#od + 1] = { s = n.s, e = n.e } end

    local phrases = {}
    for _, m in ipairs(Notes(tr, 105, 106)) do
        if m.e > m.s then
            local ph = { s = m.s, e = m.e, e_sec = m.e_sec, sung = false, perc = 0, od = false }
            for _, n in ipairs(sung) do
                if n.qn >= m.s - 1e-4 and n.qn < m.e - 1e-4 then ph.sung = true; break end
            end
            for _, n in ipairs(perc) do
                if n.s >= m.s - 1e-4 and n.s < m.e - 1e-4 then ph.perc = ph.perc + 1 end
            end
            for _, o in ipairs(od) do
                if o.s < m.e - 1e-4 and o.e > m.s + 1e-4 then ph.od = true; break end
            end
            -- 105 and 106 on the same span (RB2-era charts) are one phrase.
            local prev = phrases[#phrases]
            if not (prev and math.abs(prev.s - ph.s) < 1e-3 and math.abs(prev.e - ph.e) < 1e-3) then
                phrases[#phrases + 1] = ph
            end
        end
    end
    if #phrases == 0 then return nil, name .. ' has no phrase markers' end

    local notes = {}
    for _, n in ipairs(sung) do
        notes[#notes + 1] = { qn = n.qn, qn_e = n.qn_e, s = n.s, e = n.e, lyric = n.lyric }
    end
    return { kind = 'vocals', track_name = name, phrases = phrases, notes = notes }
end

-- Harmonies: HARM1 drives everything - its phrase ends are the scoring moments, its
-- overdrive the meter, its percussion the bonus (the user's play knowledge + the decomp:
-- mVocalParts[0]->AtPhraseEnd() triggers scoring for every part). HARM2 and HARM3 add a
-- voice to each HARM1 phrase they sing in. Their own markers only move the static lyrics
-- (checked in play: a HARM2 marker joining two HARM1 phrases still scored in both), so a
-- part counts in a HARM1 phrase when it sings between the previous HARM1 phrase's end and
-- this one's.
-- Deploy: any part's own freestyle section (each part's line separately - decomp,
-- VocalPlayer::InFreestyleSection). Needs HARM1 and HARM2; HARM3 is
-- optional.
local function ReadHarmonyPart()
    local part, why = ReadVocalPart('HARM1')
    if not part then return nil, why end
    local others = {}
    for _, name in ipairs({ 'HARM2', 'HARM3' }) do
        local tr = FindTrackExact(name)
        if not Unavailable(tr, name) then
            local list = {}
            for _, n in ipairs(ReadVocalNotes(tr)) do
                list[#list + 1] = { qn = n.qn, qn_e = n.qn_e, s = n.s, e = n.e,
                                    lyric = n.lyric }
            end
            if #list > 0 then others[#others + 1] = list end
        elseif name == 'HARM2' then
            return nil, 'no HARM2'
        end
    end
    if #others == 0 then return nil, 'no HARM2' end

    -- A note counts in every HARM1 phrase window it is sung through, clipped to that
    -- window: a long HARM2 note held across a HARM1 phrase end scores in both phrases
    -- (user, in play: a HARM2 phrase marker joining two HARM1 phrases, its long note
    -- over the boundary, earned the harmony bonus in both). Each piece carries only its
    -- own length, so the overdrive share is per phrase too.
    local function Between(list, a, b)
        local out = {}
        for _, n in ipairs(list) do
            if n.qn_e > a + 1e-4 and n.qn < b - 1e-4 then
                out[#out + 1] = { qn = math.max(n.qn, a), qn_e = math.min(n.qn_e, b),
                                  oq = n.qn, oq_e = n.qn_e, s = n.s, e = n.e }
            end
        end
        return out
    end
    local prev_e = -math.huge
    for _, ph in ipairs(part.phrases) do
        local voices = {}
        local own = Between(part.notes, ph.s, ph.e)
        if #own > 0 then voices[1] = own end
        for _, list in ipairs(others) do
            local v = Between(list, prev_e, ph.e)
            if #v > 0 then voices[#voices + 1] = v end
        end
        ph.voices = voices
        ph.sung = #voices > 0
        prev_e = ph.e
    end
    -- Freestyle sections come from every part's own line; any of them can deploy.
    part.lines = { part.notes }
    for _, list in ipairs(others) do part.lines[#part.lines + 1] = list end
    part.track_name = 'HARM1-' .. (#others + 1)
    part.harmony_parts = #others + 1
    return part
end

-- Mark unison phrases the way the game groups them (PhraseAnalyzer::Analyze): phrases
-- on two or more DIFFERENT instruments whose STARTS are under a quarter note apart (480
-- ticks); where they end does not matter. Keys and Pro Keys are one instrument, so are
-- PART DRUMS and PART DRUMS_2X. Vocals never join a unison: their phrases are added as
-- independent (`mAudioType == kAudioVocals`). Pure over { [key] = part } - a test can
-- call it with hand-built parts.
SCORE_UNISON_WINDOW_QN = 1.0

function ScoreMarkUnisons(parts)
    local inst = {}
    for _, spec in ipairs(SCORE_PARTS) do
        if spec.instrument then inst[spec.key] = spec.instrument end
    end
    for a, ia in pairs(inst) do
        local pa = parts[a]
        for _, sp in ipairs(pa and pa.od or {}) do
            sp.unison = false
            for b, ib in pairs(inst) do
                local pb = parts[b]
                if ib ~= ia and pb then
                    for _, o in ipairs(pb.od or {}) do
                        if math.abs(o.s - sp.s) < SCORE_UNISON_WINDOW_QN - 1e-6 then
                            sp.unison = true
                        end
                    end
                end
            end
        end
    end
end

-- The whole song. Returns { parts = { [key] = part }, reasons = { [key] = why missing },
-- beats, bars, no_beat }. An optional part (PART DRUMS_2X) that is missing, muted or
-- empty has neither a part nor a reason.
function ScoreReadSong()
    local coda_t = ReadCodaTime()
    local coda_qn = coda_t and r.TimeMap2_timeToQN(0, coda_t) or nil
    local song = { parts = {}, reasons = {} }
    local last = 0
    for _, spec in ipairs(SCORE_PARTS) do
        local part, why
        if spec.harmony then
            part, why = ReadHarmonyPart()
        elseif spec.kind == 'vocals' then
            part, why = ReadVocalPart(spec.track)
        else
            part, why = ReadGemPart(spec, coda_qn)
        end
        song.parts[spec.key] = part
        song.reasons[spec.key] = (not spec.optional) and why or nil
        if part then
            local list = part.gems or part.phrases
            local tail = list[#list]
            last = math.max(last, tail.qn_e or tail.e or 0)
        end
    end
    ScoreMarkUnisons(song.parts)
    song.beats = ScoreReadBeats()
    song.no_beat = #song.beats < 2
    song.bars = ScoreReadBars(last + 1)
    for _, part in pairs(song.parts) do
        part.beats, part.bars = song.beats, song.bars
    end
    return song
end

----------------------------------------------------------------------
-- Wording shared by Metadata > Score and Overdrive > Validate
----------------------------------------------------------------------

local function Pct(x) return ('%d%%'):format(math.floor(x * 100 + 0.5)) end

-- "24.5 bars in OD (31% of the part), 6 deploys", or nil when never deployed. A label:
-- the views spell out "overdrive (OD)" in their descriptions.
function ScoreCoverageText(res)
    if #res.deploys == 0 then return nil end
    local bars = res.od_bars and ('%.1f bars'):format(res.od_bars)
                 or ('%.1f quarter notes'):format(res.od_qn)
    return ('%s in OD (%s of the part), %d deploy%s'):format(
        bars, Pct(res.od_share), #res.deploys, #res.deploys == 1 and '' or 's')
end

-- What the simulated overdrive path says about the authored overdrive. Returns
-- { text, level } lines, bars named by measure number:
--   'warn'    overdrive the chart loses whatever the player does - into a full meter (the
--             Validate warnings);
--   'advice'  the last overdrive phrase sits too close to the end for its overdrive to be
--             spent before the last note - worth a look, not an error (amber);
--   'note'    about the chart, harmless: a drum fill that cannot appear because it starts
--             too soon after drum overdrive FIRST becomes ready (a later fill deploys
--             instead; official RB3 DLC charts have one in 15% of songs). Grey, not counted;
--   'info'    about the simulated path, not the chart: where it holds overdrive so the
--             last one is usable, overdrive it leaves unused at the end, a last deploy
--             running past the last note. A better path may do better.
SCORE_END_LEFT_NOTE = 0.25   -- report a last deploy running on by more than this meter

function ScoreFindings(res, bars, kind)
    local out = {}
    local function Bar(qn) return ScoreBarOf(bars or {}, qn) end
    local function Add(level, text) out[#out + 1] = { level = level, text = text } end

    local full, full_bars = 0, {}
    for _, w in ipairs(res.waste) do
        if w.kind == 'full' and w.amount > 0.01 then
            full = full + w.amount
            local b = Bar(w.qn)
            if full_bars[#full_bars] ~= b then full_bars[#full_bars + 1] = b end
        end
    end
    if full > 0.01 then
        Add('warn', ('Overdrive lost to a full meter: %s of a meter, at bar %s.')
            :format(Pct(full), table.concat(full_bars, ', ')))
    end
    for _, f in ipairs(res.lost_fills) do
        -- Only after the FIRST activation, which every player reaches at the same moment.
        -- Later ready moments depend on how the drummer uses overdrive (deploy at once,
        -- wait for a full meter, wait for the band), so a fill the simulated path skips
        -- there may well be used. The gate is Expert's highway length (SCORE_FILL_GATE_SEC).
        if res.first_ready_qn and math.abs(f.ready_qn - res.first_ready_qn) < 1e-6 then
            Add('note', ('Fill at bar %d does not appear on Expert: it starts %.1f s after '
                .. 'drum overdrive first becomes ready (bar %d), and fills show only from '
                .. '%.1f s (one highway length) after that.')
                :format(Bar(f.qn), f.gap_sec, Bar(f.ready_qn), SCORE_RULES.fill_gate_sec))
        end
    end

    local lo = res.last_od
    if lo and lo.too_late then
        Add('advice', ('The last overdrive phrase (bar %d) is close to the end: its %.0f beats '
            .. 'of overdrive cannot all be spent before the last note (%.0f beats left). '
            .. 'Consider placing it earlier.')
            :format(Bar(lo.qn), lo.beats_needed, math.max(0, lo.beats_left)))
    end

    for _, h in ipairs(res.held or {}) do
        Add('info', h.deploy
            and ('Holds the overdrive ready at bar %d until bar %d, so the last overdrive '
                 .. 'is usable.'):format(Bar(h.qn), Bar(h.deploy))
            or ('Holds the overdrive ready at bar %d, so the last overdrive is usable.')
                 :format(Bar(h.qn)))
    end
    for _, w in ipairs(res.waste) do
        if w.kind == 'unspent' then
            if w.ready then
                local why = kind == 'drums' and 'no fill comes after it'
                         or kind == 'vocals' and 'no freestyle section comes after it'
                         or 'the part ends'
                Add('info', ('With this plan the overdrive ready from bar %d is never used: %s.')
                    :format(Bar(w.ready_qn or w.qn), why))
            else
                Add('info', ('With this plan the overdrive earned from bar %d (%s of a meter) '
                    .. 'is never deployed: the part ends before the meter is half full.')
                    :format(Bar(w.qn), Pct(w.amount)))
            end
        end
    end
    if (res.end_left or 0) > SCORE_END_LEFT_NOTE then
        Add('info', ('The last deploy still has %s of a meter (%.0f beats) when the part ends.')
            :format(Pct(res.end_left), res.end_left * SCORE_RULES.deploy_beats))
    end
    return out
end

-- 123456 -> "123,456". The score number format both helpers show.
function ScoreNum(n)
    local t = tostring(math.floor(n + 0.5))
    return (t:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

-- Metadata > Score's cards as plain text, for Copy result: per part the card in reading
-- order (stars, full combo without and with overdrive, coverage), then its findings with
-- their level as a prefix - '!' warning, '?' advice, '-' about the simulated path.
-- result = S.score_result ({ cards, bars, no_beat }). Pure.
local SCORE_FINDING_MARK = { warn = '!', advice = '?', note = '-', info = '-' }

function ScoreReportText(result)
    local lines = { 'Score and stars - a full combo (FC), overdrive (OD) deployed as soon as possible' }
    local I = '    '
    if result.no_beat then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '! No BEAT track: overdrive drain is estimated at one beat per quarter note.'
    end
    for _, card in ipairs(result.cards) do
        lines[#lines + 1] = ''
        lines[#lines + 1] = card.label
        if not card.runs then
            lines[#lines + 1] = I .. (card.reason or 'No chart')
        else
            for _, res in ipairs(card.runs) do
                local ind = I
                if res.label then
                    lines[#lines + 1] = I .. res.label
                    ind = I .. I
                end
                local stars = {}
                for i = 1, 5 do stars[i] = ('%d* %s'):format(i, ScoreNum(res.stars[i])) end
                lines[#lines + 1] = ('%sStars: %s  Gold %s'):format(ind, table.concat(stars, '  '),
                                                                   ScoreNum(res.stars[6]))
                local fc = ('%sFC without OD: %s'):format(ind, ScoreNum(res.base_streak + res.base_bonus))
                if res.base_bonus > 0 then fc = fc .. (' (%s of it bonus)'):format(ScoreNum(res.base_bonus)) end
                lines[#lines + 1] = fc
                local got = ('%sFC with OD: %s (%s)'):format(ind, ScoreNum(res.total),
                    res.stars_reached == 6 and 'gold' or (res.stars_reached .. '*'))
                if res.gold_qn then
                    got = got .. (' - gold from bar %d'):format(ScoreBarOf(result.bars, res.gold_qn))
                else
                    got = got .. (' - short of gold by %s'):format(ScoreNum(res.gold_short))
                end
                if res.bre_points and res.bre_points > 0 then
                    got = got .. (' (up to %s of it from the Big Rock Ending)'):format(ScoreNum(res.bre_points))
                end
                lines[#lines + 1] = got
            end
            lines[#lines + 1] = I .. (ScoreCoverageText(card.runs[1]) or 'Never in OD.')
            for _, f in ipairs(card.findings or {}) do
                lines[#lines + 1] = ('%s%s %s'):format(I, SCORE_FINDING_MARK[f.level] or '-', f.text)
            end
        end
    end
    return table.concat(lines, '\n')
end
