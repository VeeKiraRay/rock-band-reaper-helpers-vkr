-- Overdrive tab: reading the song into one plain model.
--
-- Everything the Overdrive generators and the validator need, read once and held
-- in QUARTER NOTES. A note's QN position is what MIDI stores; seconds depend on
-- the tempo map, and a tempo change would make "the same position on two tracks"
-- drift apart in seconds (see the header of actions_drums_2x.lua). Seconds only
-- appear when a finding is formatted for display.
--
-- The planners in actions_overdrive*.lua take this model and return plans without
-- touching the project, so dev/tests can drive them with a hand-built model.
--
-- Requires (globals): r, FindTrackExact, ReadGemEvents (lib/reaper_difficulty_read.lua)

OD_PITCH        = 116
OD_FILL_LO      = 120   -- drum fill lanes; the same pitches are BRE lanes after [coda]
OD_FILL_HI      = 124
OD_PHRASE_PITCH = 105
OD_SOLO_PITCH   = 103
OD_QN_EPS       = 0.0005   -- under one tick at 960 PPQ: "the same position"
OD_TIER_NAMES   = { 'Expert', 'Hard', 'Medium', 'Easy' }

-- Pro Drums tom markers: gem pitch -> the marker that turns it from a cymbal into a
-- tom. Blue 99 / 111 and green 100 / 112 matter here (crash detection); yellow is the
-- hi-hat and is not read.
OD_TOM_MARKERS  = { [99] = 111, [100] = 112 }

-- Instrument groups. Tracks in a group are written together so they cannot drift
-- apart: the game needs PART KEYS and PART REAL_KEYS_X overdrive to match, and
-- PART DRUMS_2X is the same chart as PART DRUMS with every kick kept.
--
-- ORDER MATTERS: it is the order singles are placed in, so the instrument listed
-- first gets first pick of a contested bar. Guitar leads because the authoring doc
-- starts there ("it tends to have the most interesting things going on").
OD_INST_GROUPS = {
    { key = 'guitar', label = 'Guitar', track = 'PART GUITAR', lo = 96, hi = 100 },
    { key = 'bass',   label = 'Bass',   track = 'PART BASS',   lo = 96, hi = 100 },
    { key = 'drums',  label = 'Drums',  track = 'PART DRUMS',  lo = 96, hi = 100,
      mirror = 'PART DRUMS_2X', mirror_lo = 96, mirror_hi = 100 },
    { key = 'keys',   label = 'Keys',   track = 'PART KEYS',   lo = 96, hi = 100,
      mirror = 'PART REAL_KEYS_X', mirror_lo = 48, mirror_hi = 72 },
}
OD_VOCAL_TRACK = 'PART VOCALS'
OD_HARM_TRACK  = 'HARM1'

-- The Instrument dropdown. `inst` names the instrument group a choice generates;
-- `vocals` says whether it generates vocal overdrive.
OD_GROUP_CHOICES = {
    { key = 'all',    label = 'All',    all = true, vocals = true },
    { key = 'drums',  label = 'Drums',  inst = 'drums',
      desc = 'PART DRUMS + PART DRUMS_2X' },
    { key = 'bass',   label = 'Bass',   inst = 'bass',   desc = 'PART BASS' },
    { key = 'guitar', label = 'Guitar', inst = 'guitar', desc = 'PART GUITAR' },
    { key = 'keys',   label = 'Keys',   inst = 'keys',
      desc = 'PART KEYS + PART REAL_KEYS_X' },
    { key = 'vocals', label = 'Vocals', vocals = true,
      desc = 'PART VOCALS + HARM1' },
}

function OdInstGroup(key)
    for _, g in ipairs(OD_INST_GROUPS) do
        if g.key == key then return g end
    end
    return nil
end

----------------------------------------------------------------------
-- Spans (pure)
----------------------------------------------------------------------

function OdSpansOverlap(a_s, a_e, b_s, b_e)
    return a_s < b_e - OD_QN_EPS and b_s < a_e - OD_QN_EPS
end

function OdSameQN(a, b)
    return math.abs(a - b) <= OD_QN_EPS
end

function OdSameSpan(a, b)
    return OdSameQN(a.s, b.s) and OdSameQN(a.e, b.e)
end

-- True when any span in `spans` overlaps [s, e).
function OdAnyOverlap(spans, s, e)
    for _, sp in ipairs(spans or {}) do
        if OdSpansOverlap(sp.s, sp.e, s, e) then return true end
    end
    return false
end

-- Two span lists describe the same phrases, in order.
function OdSpanListsEqual(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if not OdSameSpan(a[i], b[i]) then return false end
    end
    return true
end

-- True when a gem (an event with `qn`, from a list sorted by qn) starts in [s, e).
-- Binary search: the planner asks this for every candidate bar.
function OdHasGem(events, s, e)
    local lo, hi = 1, #events + 1
    local from = s - OD_QN_EPS
    while lo < hi do                       -- first event at or after s
        local mid = (lo + hi) // 2
        if events[mid].qn < from then lo = mid + 1 else hi = mid end
    end
    local ev = events[lo]
    return ev ~= nil and ev.qn < e - OD_QN_EPS
end

-- What is wrong with one vocal overdrive phrase on its own track (PART VOCALS or HARM1),
-- or nil. Magma refuses each of these as a compile error, per track, with the game's own
-- texts (SongData::ValidateVocalSPPhrases).
--
-- JUDGED BY NOTES, NOT MARKERS. The game starts from the next note of the track at or
-- after the overdrive's start and takes the phrase (105) holding that note: the
-- overdrive must start at or before that phrase's first note, reach at least the start
-- of its last note (a last note ringing past the overdrive's end is fine), and stop
-- before the next phrase's first note. Worked out from a test song built in Magma (every
-- verdict matched, wording included) and from the official RBN songs, which Magma built:
-- this gives 0 errors over their 1,777 vocal overdrive phrases, where an exact
-- marker-match rule flagged 145. Magma's "ends prematurely" may be a catch-all text: a
-- phrase with no note of the track is reported that way too.
--
--   od         { s, e }
--   phrases    the track's 105 spans, sorted
--   notes      the track's own sung notes { qn, qn_e }, sorted
--   any_notes  HARM1 only: HARM1-3's notes together. A HARM1 phrase that only another
--              voice sings in is fine (Magma-built RBN songs have them, and any singer
--              clearing a HARM1 phrase earns its overdrive); the timing checks stay on
--              HARM1's own notes, since HARM2 / HARM3 may cross HARM1's phrases.
-- Returns key, magma_text:
--   after_all   no note at or after its start
--   during_note it starts inside one of the track's notes
--   off         the next note is outside every phrase marker
--   no_notes    it starts on a phrase with no note of this track (or of any voice, HARM1)
--   mid_phrase  it starts after its phrase's first note
--   short       it ends before its phrase's last note starts
--   long        it reaches the next phrase's first note
OD_VOCAL_MAGMA = {
    after_all   = 'is after all notes',
    during_note = 'begins during a note',
    mid_phrase  = 'starts mid-phrase',
    no_notes    = 'ends prematurely',
    short       = 'ends prematurely',
    long        = 'cuts into next phrase',
}

local function PhraseAt(phrases, qn)
    for _, p in ipairs(phrases) do
        if p.s <= qn + OD_QN_EPS and qn < p.e - OD_QN_EPS then return p end
    end
    return nil
end

function OdVocalOdProblem(od, phrases, notes, any_notes)
    local start_ph = PhraseAt(phrases, od.s)
    if any_notes then
        if start_ph and not OdHasGem(notes, start_ph.s, start_ph.e)
           and OdHasGem(any_notes, start_ph.s, start_ph.e) then
            return nil
        end
        if not OdHasGem(any_notes, od.s, math.huge) then return 'after_all', OD_VOCAL_MAGMA.after_all end
    end
    local key
    if not OdHasGem(notes, od.s, math.huge) then
        key = 'after_all'
    else
        for _, n in ipairs(notes) do
            if n.qn >= od.s then break end
            if n.qn < od.s - OD_QN_EPS and (n.qn_e or n.qn) > od.s + OD_QN_EPS then key = 'during_note'; break end
        end
    end
    if not key then
        local nxt
        for _, n in ipairs(notes) do
            if n.qn >= od.s - OD_QN_EPS then nxt = n; break end
        end
        local ph = PhraseAt(phrases, nxt.qn)
        if not ph then
            key = 'off'
        elseif start_ph and start_ph ~= ph and not OdHasGem(notes, start_ph.s, start_ph.e) then
            key = 'no_notes'
        else
            local first, last, after
            for _, n in ipairs(notes) do
                if n.qn >= ph.s - OD_QN_EPS and n.qn < ph.e - OD_QN_EPS then
                    first = first or n
                    last = n
                elseif n.qn >= ph.e - OD_QN_EPS and not after then
                    after = n
                end
            end
            if first.qn < od.s - OD_QN_EPS then key = 'mid_phrase'
            elseif od.e <= last.qn + OD_QN_EPS then key = 'short'
            elseif after and od.e > after.qn + OD_QN_EPS then key = 'long'
            end
        end
    end
    return key, key and OD_VOCAL_MAGMA[key]
end

-- Phrase problems on one difficulty of one part, against its gems. Pure.
--   empty    phrases with no gem in them: never earned
--   adjacent { a, b } consecutive phrases with no gem between them (a gem on a's end
--            counts as between: a phrase's span ends before its note-off). Magma refuses
--            the song: "No gems between overdrive phrases", checked on every difficulty.
-- od: the phrase spans sorted by start; events: the gems sorted by qn.
function OdPhraseGemIssues(od, events)
    local out = { empty = {}, adjacent = {} }
    for i, sp in ipairs(od) do
        if not OdHasGem(events, sp.s, sp.e) then out.empty[#out.empty + 1] = sp end
        local nx = od[i + 1]
        if nx and nx.s >= sp.e - OD_QN_EPS and not OdHasGem(events, sp.e, nx.s) then
            out.adjacent[#out.adjacent + 1] = { a = sp, b = nx }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Bars (pure apart from OdReadBars)
----------------------------------------------------------------------

-- Beats the overdrive frequency rule counts in one measure.
--
-- The rule is "one phrase per 40 beats", and the doc means COUNTED beats, not
-- quarter notes: 7/8 is counted 1-2, 1-2, 1-2-3 and so has three beats, the same
-- phrase rate as 3/4. Compound meters count their dotted pulse (6/8 = 2, 12/8 = 4);
-- other /8 meters count pairs of eighths with the odd one absorbed (5/8 = 2).
function OdCountedBeats(num, den)
    if not num or num <= 0 or not den or den <= 0 then return 4 end
    if den <= 4 then return num * 4 / den end
    local eighths = num * 8 / den
    if eighths >= 6 and eighths % 3 == 0 then return eighths / 3 end
    return math.max(1, math.floor(eighths / 2))
end

-- Every measure that STARTS before end_qn, as
-- { qn_s, qn_e, t_s, num, den, beats }, 1-based in song order.
-- Walks REAPER's own measure map, so time-signature changes are exact.
function OdReadBars(end_qn)
    local bars = {}
    for m = 0, 99999 do
        local t_s, qn_s, qn_e, num, den = r.TimeMap_GetMeasureInfo(0, m)
        if qn_s >= end_qn - OD_QN_EPS then break end
        bars[#bars + 1] = {
            qn_s = qn_s, qn_e = qn_e, t_s = t_s, num = num, den = den,
            beats = OdCountedBeats(num, den),
        }
    end
    return bars
end

-- Index of the bar containing qn (qn_s <= qn < qn_e), or nil outside the song.
function OdBarAt(bars, qn)
    local lo, hi = 1, #bars
    if hi == 0 or qn < bars[1].qn_s - OD_QN_EPS then return nil end
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if bars[mid].qn_s <= qn + OD_QN_EPS then lo = mid else hi = mid - 1 end
    end
    if qn >= bars[lo].qn_e - OD_QN_EPS and lo == #bars then return nil end
    return lo
end

-- Index of the bar that STARTS at qn, or nil when qn is not on a barline.
function OdBarStartingAt(bars, qn)
    local b = OdBarAt(bars, qn)
    if b and OdSameQN(bars[b].qn_s, qn) then return b end
    if b and b < #bars and OdSameQN(bars[b + 1].qn_s, qn) then return b + 1 end
    return nil
end

-- Bars overlapped by [s, e): first, last (inclusive), or nil.
function OdBarsOfSpan(bars, s, e)
    local a = OdBarAt(bars, s)
    local z = OdBarAt(bars, math.max(s, e - OD_QN_EPS * 2))
    if not a then return nil end
    return a, z or #bars
end

-- Per-bar onset and playing sets for a sorted gem event list.
--   onset[b]    a gem starts in bar b
--   playing[b]  a gem starts in b, or a sustain from earlier is still ringing -
--               the bars the frequency rule counts as "the instrument is playing"
--   first[b]    the earliest onset QN in bar b
function OdBarActivity(bars, events)
    local onset, playing, first = {}, {}, {}
    for _, ev in ipairs(events) do
        local b = OdBarAt(bars, ev.qn)
        if b then
            onset[b] = true
            playing[b] = true
            if not first[b] or ev.qn < first[b] then first[b] = ev.qn end
            local z = OdBarAt(bars, (ev.qn_e or ev.qn) - OD_QN_EPS * 2)
            if z then
                for k = b + 1, z do playing[k] = true end
            end
        end
    end
    return onset, playing, first
end

----------------------------------------------------------------------
-- REAPER reading
----------------------------------------------------------------------

-- Every MIDI take on a track: { item, take }.
function OdTrackTakes(track)
    local out = {}
    if not track then return out end
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            out[#out + 1] = { item = item, take = take }
        end
    end
    return out
end

-- Unmuted notes with pitch in [lo, hi], as { s, e (QN), pitch, take, sppq, eppq },
-- sorted by start. NOT merged: a phrase boundary is exactly what matters here.
function OdReadPitchNotes(track, lo, hi)
    local out = {}
    for _, tk in ipairs(OdTrackTakes(track)) do
        local _, n = r.MIDI_CountEvts(tk.take)
        for i = 0, n - 1 do
            local ok, _, muted, sppq, eppq, _, p = r.MIDI_GetNote(tk.take, i)
            if ok and not muted and p >= lo and p <= hi and eppq > sppq then
                out[#out + 1] = {
                    s = r.MIDI_GetProjQNFromPPQPos(tk.take, sppq),
                    e = r.MIDI_GetProjQNFromPPQPos(tk.take, eppq),
                    pitch = p, take = tk.take, sppq = sppq, eppq = eppq,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.pitch < b.pitch
    end)
    return out
end

-- Notes at one pitch as spans { s, e }, sorted.
local function PitchSpans(track, pitch)
    local out = {}
    for _, n in ipairs(OdReadPitchNotes(track, pitch, pitch)) do
        out[#out + 1] = { s = n.s, e = n.e, take = n.take, sppq = n.sppq, eppq = n.eppq }
    end
    return out
end

-- Drum fills: notes on 120-124 grouped by shared start, so a fill authored on all
-- five lanes reads as one span. Split at `coda_qn`: from there on the same pitches
-- are the Big Rock Ending, which this tab reads but never writes.
local function FillSpans(track, coda_qn)
    local fills, bre = {}, {}
    for _, n in ipairs(OdReadPitchNotes(track, OD_FILL_LO, OD_FILL_HI)) do
        local list = (coda_qn and n.s >= coda_qn - OD_QN_EPS) and bre or fills
        local prev = list[#list]
        if prev and OdSameQN(prev.s, n.s) then
            if n.e > prev.e then prev.e = n.e end
            prev.lanes = prev.lanes + 1
        else
            list[#list + 1] = { s = n.s, e = n.e, lanes = 1 }
        end
    end
    return fills, bre
end

-- The EVENTS track's type-1 text events that matter here.
-- Returns end_qn ([end]), coda_qn ([coda]) and sections { name, s } in order.
local function ReadEventsTrack()
    local track = FindTrackExact('EVENTS')
    local end_qn, coda_qn, sections = nil, nil, {}
    for _, tk in ipairs(OdTrackTakes(track)) do
        local _, _, _, textcnt = r.MIDI_CountEvts(tk.take)
        for i = 0, (textcnt or 0) - 1 do
            local ok, _, muted, ppq, typ, msg = r.MIDI_GetTextSysexEvt(tk.take, i)
            if ok and not muted and (typ == 1 or typ == 5) then
                local qn = r.MIDI_GetProjQNFromPPQPos(tk.take, ppq)
                local m = (msg or ''):match('^%s*(.-)%s*$')
                if m == '[end]' then
                    if not end_qn or qn < end_qn then end_qn = qn end
                elseif m == '[coda]' then
                    if not coda_qn or qn < coda_qn then coda_qn = qn end
                else
                    local name = m:match('^%[prc_(.+)%]$') or m:match('^%[section (.+)%]$')
                    if name then sections[#sections + 1] = { name = name, s = qn } end
                end
            end
        end
    end
    table.sort(sections, function(a, b) return a.s < b.s end)
    return end_qn, coda_qn, sections
end

-- Read everything the Overdrive tab works from. Returns model, or nil, error.
--
--   bars          measures up to the effective end (see below)
--   end_qn        [end], or the last note of any read track when there is none
--   coda_qn       [coda] or nil. When present it is the EFFECTIVE end: no overdrive,
--                 fill or vocal phrase may be placed in a Big Rock Ending, and the
--                 end-of-song keep-outs count back from it
--   sections      { name, s, e, bar } section starts, e = next start
--   drum_solos    { s, e } from [prc_drum_solo...] sections and PART DRUMS 103 spans
--   inst[key]     per OD_INST_GROUPS entry: present, track, mirror_track, events,
--                 onset, playing, first, od, mirror_od (nil without a mirror track)
--   fills         drum fills before the coda; fills_2x the same on PART DRUMS_2X;
--                 bre the lanes after the coda (read only)
--   rolls         { s, e } PART DRUMS 126/127
--   vocal         present, track, phrases { s, e, take, sppq, eppq, has_notes,
--                 harm = matching HARM1 phrase or nil }, od, harm_present,
--                 harm_track, harm_od, harm_phrases
function OdBuildModel()
    local end_qn, coda_qn, sections = ReadEventsTrack()

    local model = { inst = {}, sections = {}, drum_solos = {} }
    local last_note_qn = 0

    for _, g in ipairs(OD_INST_GROUPS) do
        local tr = FindTrackExact(g.track)
        local mtr = g.mirror and FindTrackExact(g.mirror) or nil
        -- A group whose primary track is missing still reads its mirror, so a
        -- project with only PART REAL_KEYS_X is not treated as having no keys.
        local read_tr, lo, hi = tr, g.lo, g.hi
        if not (tr and #OdTrackTakes(tr) > 0) and mtr then
            read_tr, lo, hi = mtr, g.mirror_lo, g.mirror_hi
        end
        local inst = { key = g.key, label = g.label, group = g, track = tr, mirror_track = mtr }
        inst.present = read_tr ~= nil and #OdTrackTakes(read_tr) > 0
        inst.events = inst.present and ReadGemEvents(read_tr, lo, hi) or {}
        inst.od = tr and PitchSpans(tr, OD_PITCH) or {}
        inst.mirror_od = mtr and PitchSpans(mtr, OD_PITCH) or nil
        -- Every authored difficulty's gems, for the phrase checks Magma makes per
        -- difficulty (OdPhraseGemIssues). Hard / Medium / Easy are 12 pitches down each;
        -- a difficulty with no gems at all is not authored yet and is left out. Pro Keys
        -- is its own chart under the same overdrive, so PART REAL_KEYS_X's gems come along
        -- with its own 116 notes.
        -- `od` is set only where a tier has overdrive of its own (Pro Keys); the others
        -- use inst.od, read when checked, so a list replaced later is still the one checked.
        inst.tiers = { { name = 'Expert', events = inst.events } }
        if inst.present and read_tr == tr then
            for t = 1, 3 do
                local ev = ReadGemEvents(tr, lo - 12 * t, hi - 12 * t)
                if #ev > 0 then
                    inst.tiers[#inst.tiers + 1] = { name = OD_TIER_NAMES[t + 1], events = ev }
                end
            end
            if g.key == 'keys' and mtr and #OdTrackTakes(mtr) > 0 then
                local ev = ReadGemEvents(mtr, g.mirror_lo, g.mirror_hi)
                if #ev > 0 then
                    inst.tiers[#inst.tiers + 1] = { name = 'Pro Keys', events = ev, od = inst.mirror_od or {},
                                                    own_label = true }
                end
            end
        end
        for _, ev in ipairs(inst.events) do
            if (ev.qn_e or ev.qn) > last_note_qn then last_note_qn = ev.qn_e or ev.qn end
        end
        model.inst[g.key] = inst
    end

    local vtr = FindTrackExact(OD_VOCAL_TRACK)
    local htr = FindTrackExact(OD_HARM_TRACK)
    local vocal = {
        present = vtr ~= nil and #OdTrackTakes(vtr) > 0, track = vtr,
        harm_present = htr ~= nil and #OdTrackTakes(htr) > 0, harm_track = htr,
    }
    vocal.phrases = vtr and PitchSpans(vtr, OD_PHRASE_PITCH) or {}
    vocal.od = vtr and PitchSpans(vtr, OD_PITCH) or {}
    vocal.harm_phrases = htr and PitchSpans(htr, OD_PHRASE_PITCH) or {}
    vocal.harm_od = htr and PitchSpans(htr, OD_PITCH) or {}
    -- Sung notes per track, { qn, qn_e } sorted (OdHasGem reads qn): PART VOCALS' and
    -- HARM1's own. Magma checks each track's overdrive against that track's own notes
    -- (OdVocalOdProblem): a HARM1 phrase with no HARM1 note in it is refused even when
    -- its overdrive fits the marker exactly.
    local function Sung(t)
        local out = {}
        for _, n in ipairs(OdReadPitchNotes(t, 36, 84)) do out[#out + 1] = { qn = n.s, qn_e = n.e } end
        return out
    end
    vocal.sung = vtr and Sung(vtr) or {}
    vocal.harm_sung = htr and Sung(htr) or nil
    if htr then
        local any = Sung(htr)
        for _, name in ipairs({ 'HARM2', 'HARM3' }) do
            local t = FindTrackExact(name)
            if t then for _, n in ipairs(Sung(t)) do any[#any + 1] = n end end
        end
        table.sort(any, function(x, y) return x.qn < y.qn end)
        vocal.harm_any = any
    end
    if vtr then
        local sung = OdReadPitchNotes(vtr, 36, 84)
        local k = 1
        for _, ph in ipairs(vocal.phrases) do
            while k <= #sung and sung[k].s < ph.s - OD_QN_EPS do k = k + 1 end
            ph.has_notes = k <= #sung and sung[k].s < ph.e - OD_QN_EPS
            if ph.e > last_note_qn then last_note_qn = ph.e end
        end
    end
    for _, ph in ipairs(vocal.phrases) do
        for _, hp in ipairs(vocal.harm_phrases) do
            if OdSameSpan(ph, hp) then ph.harm = hp; break end
        end
    end
    model.vocal = vocal

    model.has_end_event = end_qn ~= nil
    if not end_qn then
        if last_note_qn <= 0 then
            return nil, 'Nothing to work from: no [end] event on EVENTS and no notes on any PART track.'
        end
        end_qn = last_note_qn
    end
    model.end_qn  = end_qn
    model.coda_qn = (coda_qn and coda_qn < end_qn) and coda_qn or nil
    local eff_end = model.coda_qn or end_qn
    model.bars = OdReadBars(eff_end)
    if #model.bars == 0 then return nil, 'The song has no measures before its end.' end

    for i, sec in ipairs(sections) do
        local nxt = sections[i + 1]
        model.sections[#model.sections + 1] = {
            name = sec.name, s = sec.s, e = nxt and nxt.s or end_qn,
            bar = OdBarStartingAt(model.bars, sec.s),
        }
        if sec.name:find('drum_solo', 1, true) then
            model.drum_solos[#model.drum_solos + 1] = { s = sec.s, e = nxt and nxt.s or end_qn }
        end
    end

    local drums = model.inst.drums
    if drums.track then
        for _, sp in ipairs(PitchSpans(drums.track, OD_SOLO_PITCH)) do
            model.drum_solos[#model.drum_solos + 1] = { s = sp.s, e = sp.e }
        end
        model.fills, model.bre = FillSpans(drums.track, model.coda_qn)
        model.rolls = {}
        for _, n in ipairs(OdReadPitchNotes(drums.track, 126, 127)) do
            model.rolls[#model.rolls + 1] = { s = n.s, e = n.e }
        end
        -- Pro Drums tom markers: a blue or green gem inside one is a tom, not a cymbal.
        model.tom_markers = {}
        for gem, marker in pairs(OD_TOM_MARKERS) do
            model.tom_markers[gem] = PitchSpans(drums.track, marker)
        end
    else
        model.fills, model.bre, model.rolls = {}, {}, {}
    end
    model.fills_2x = drums.mirror_track and (FillSpans(drums.mirror_track, model.coda_qn)) or nil
    table.sort(model.drum_solos, function(a, b) return a.s < b.s end)

    OdFinishModel(model)
    return model
end

-- Bars whose downbeat carries a crash: a blue or green CYMBAL gem on the first beat.
--
-- This is how a drum part marks the start of a phrase - the crash that lands after
-- the drummer's own fill. The fill planner uses it where no [prc_*] section start is
-- in reach, and to flag a section start the drums do not mark (see OdPlanFills for
-- why sections, not crashes, come first). Yellow is left out on purpose: a yellow
-- cymbal is the hi-hat, which many parts play on every downbeat.
--
-- tom_markers: { [99] = spans of 111, [100] = spans of 112 }. A gem inside a marker
-- span is a tom. A chart without Pro Drums markers reads every blue/green gem as a
-- cymbal, the game's own default.
function OdCrashBars(bars, drum_events, tom_markers)
    local out = {}
    local function IsTom(p, qn)
        for _, sp in ipairs(tom_markers[p] or {}) do
            if qn >= sp.s - OD_QN_EPS and qn < sp.e - OD_QN_EPS then return true end
        end
        return false
    end
    for _, ev in ipairs(drum_events) do
        local b = OdBarAt(bars, ev.qn)
        if b and OdSameQN(ev.qn, bars[b].qn_s) then
            for _, p in ipairs(ev.pitches) do
                if (p == 99 or p == 100) and not IsTom(p, ev.qn) then out[b] = true end
            end
        end
    end
    return out
end

-- The section a [prc_*] name belongs to, without its number or subsection letter:
-- chorus_1, chorus_1a, chorus_2b -> chorus; intro_a, intro_b -> intro; gtr_solo_2a ->
-- gtr_solo. Charters split a section into practice subsections (chorus_1a, chorus_1b)
-- that are not a change in the music, and official charts write them often (verse_1 ->
-- verse_1a 143 times, intro_a -> intro_b 58 times in the RB3 DLC). The last word is
-- dropped when it is a number, a number and one letter, or a single letter.
-- A name with no other word (a bare "1a") is kept whole.
function OdSectionFamily(name)
    local words = {}
    for w in name:lower():gmatch('[^_%s]+') do words[#words + 1] = w end
    if #words > 1 and words[#words]:match('^%d*%a?$') then words[#words] = nil end
    return table.concat(words, '_')
end

-- Seconds at a QN position, from the bars' start times (linear inside a bar, which is
-- exact unless the tempo changes mid-bar). Pure, so the planners need no REAPER call.
function OdQNToSec(bars, qn)
    local b = OdBarAt(bars, qn) or (qn < bars[1].qn_s and 1 or #bars)
    local bar = bars[b]
    local nxt = bars[b + 1]
    local dur = nxt and (nxt.t_s - bar.t_s)
             or (b > 1 and (bar.t_s - bars[b - 1].t_s) * (bar.qn_e - bar.qn_s)
                           / (bars[b - 1].qn_e - bars[b - 1].qn_s))
             or 0
    return bar.t_s + (qn - bar.qn_s) / (bar.qn_e - bar.qn_s) * dur
end

-- Derived per-instrument fields. Split out so a test can build a model by hand
-- (bars, inst[key].events, ...) and get the same derivation.
function OdFinishModel(model)
    for _, inst in pairs(model.inst) do
        inst.onset, inst.playing, inst.first = OdBarActivity(model.bars, inst.events or {})
        inst.od = inst.od or {}
        -- A hand-built model (dev/tests) gives Expert only.
        inst.tiers = inst.tiers or { { name = 'Expert', events = inst.events or {} } }
    end
    model.fills = model.fills or {}
    model.rolls = model.rolls or {}
    model.drum_solos = model.drum_solos or {}
    model.sections = model.sections or {}
    -- section_bars: every section start (the interest score's context term).
    -- section_change_bars: only starts where the section really changes - what fills
    -- and the unison before a section line up with. See OdSectionFamily.
    model.section_bars, model.section_change_bars = {}, {}
    local prev_family
    for _, sec in ipairs(model.sections) do
        local family = OdSectionFamily(sec.name or '')
        if sec.bar then
            model.section_bars[sec.bar] = true
            if family ~= prev_family then model.section_change_bars[sec.bar] = true end
        end
        prev_family = family
    end
    local drums = model.inst.drums
    model.crash_bars = OdCrashBars(model.bars, drums and drums.events or {}, model.tom_markers or {})
    model.vocal = model.vocal or { present = false, phrases = {}, od = {},
                                   harm_present = false, harm_phrases = {}, harm_od = {} }
end

-- "m40  1m 20.000s" for a QN position, the form every finding uses.
function OdWhere(qn)
    return FormatTime(r.TimeMap2_QNToTime(0, qn))
end
