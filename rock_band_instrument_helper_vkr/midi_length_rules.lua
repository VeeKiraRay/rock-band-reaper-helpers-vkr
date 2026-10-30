-- MIDI > Length > Only sustains: the gap and plain-note rules of Difficulty > Generate and
-- Validate, applied to one track's tier. Pure: nothing here reads the project. Every number
-- comes from the Generate / Validate code (Gen5ReleaseGapQN, Gen5MinSustainQN,
-- Gen5HardSustainTooShort, DiffSustainTooShort, GenPKReleaseGapQN, GEN_PK_*), so the tab
-- cannot drift from them. Called at call time only.
--
-- Tempo: the song's first tempo (bar 1), as Generate reads a song's tempo - one value for
-- every note, so a tempo change mid-song does not switch the rules note by note.
-- Expert follows Hard's gap rules (Generate never writes Expert).

local EPS = 0.02   -- quarter-note tolerance, as GEN5_EPS

-- Track name -> kind ('gb', 'k5', 'pk') and, for Pro Keys, the tier its track carries.
-- Nil for tracks without sustain rules (drums, vocals, other).
local PK_TIER = { X = 'X', H = 'H', M = 'M', E = 'E' }
function MidiLengthKind(track_name)
    if track_name == 'PART GUITAR' or track_name == 'PART BASS' then return 'gb' end
    if track_name == 'PART KEYS' then return 'k5' end
    local t = track_name and track_name:match('^PART REAL_KEYS_([XHME])$')
    if t then return 'pk', PK_TIER[t] end
    return nil
end

-- Gap (quarter notes) a sustain leaves before the next note.
--   chord / next_chord - ascending pitches of the sustain and of the next onset
function MidiLengthGapQN(kind, dl, bpm, chord, next_chord)
    if kind == 'pk' then
        if dl == 'X' then dl = 'H' end
        return GenPKReleaseGapQN(dl, chord or { 0 }, next_chord or { 0 })
    end
    return Gen5ReleaseGapQN(kind, dl, { bpm = bpm, offs = chord or { 0 } })
end

-- True when a sustain len_qn long becomes a plain note. room_qn: from its end to the next
-- note (nil = none follows) - the Guitar/Bass Hard 300 ms floor needs a note close behind.
function MidiLengthTooShort(kind, dl, len_qn, bpm, room_qn)
    if len_qn < GEN5_SUSTAIN_QN - EPS then return false end   -- already plain
    if dl == 'X' then return DiffSustainTooShort(len_qn, bpm) end
    if kind == 'pk' then return len_qn < GEN_PK_STUB_QN - EPS end
    if dl == 'H' then return Gen5HardSustainTooShort(kind, len_qn, bpm, room_qn) end
    return len_qn < Gen5MinSustainQN(dl, bpm) - EPS
end

-- Length (quarter notes) of the plain note a too-short sustain becomes: a 1/16 on Pro Keys
-- and on Expert (what Generate's Expert question writes), a 1/32 otherwise.
function MidiLengthPlainQN(kind, dl)
    if kind == 'pk' or dl == 'X' then return GEN_PK_PLAIN_QN end
    return GEN5_MIN_LEN_QN
end

-- The single-note gap in 32nd notes, for the Custom slider's prefill.
function MidiLengthDefaultGap32(kind, dl, bpm)
    return math.floor(MidiLengthGapQN(kind, dl, bpm, { 0 }, { 0 }) * 8 + 0.5)
end

local NOTE_NAMES = {
    [0.125] = '1/32', [0.25] = '1/16', [0.5] = '1/8', [0.75] = 'dotted 1/8',
    [1.0] = 'quarter', [2.0] = 'half',
}
local function NoteName(qn)
    return NOTE_NAMES[qn] or ('%g/32'):format(qn * 8)
end

local KIND_NAMES = { gb = 'Guitar/Bass', k5 = 'Keys', pk = 'Pro Keys' }
local TIER_NAMES = { X = 'Expert', H = 'Hard', M = 'Medium', E = 'Easy' }

-- The rules as one line of text, for the UI and the result.
function MidiLengthRuleText(kind, dl, bpm)
    local fast = bpm > GEN5_PARAMS.fast_bpm
    local head = ('%s %s, song tempo %.0f BPM%s:'):format(KIND_NAMES[kind], TIER_NAMES[dl], bpm,
        fast and ' (fast, over ' .. GEN5_PARAMS.fast_bpm .. ')' or '')
    local gap
    if kind == 'pk' and (dl == 'X' or dl == 'H') then
        gap = 'gap a 1/16 before a simple change (single to single, into or out of a chord holding the note, the same chord again), a 1/8 otherwise'
    elseif kind == 'k5' and (dl == 'X' or dl == 'H') then
        gap = 'gap a 1/16 (a 1/8 after a chord)'
    else
        gap = 'gap a ' .. NoteName(MidiLengthGapQN(kind, dl, bpm)) .. ' before the next note'
    end
    local short
    if dl == 'X' then
        short = bpm >= DIFF_SUSTAIN_MIN_BPM and 'shorter than a dotted 1/8' or nil
    elseif kind == 'pk' then
        short = 'shorter than a dotted 1/8'
    elseif dl == 'H' then
        local m = GEN5_PARAMS.hard_min_sustain[kind]
        if m then
            short = ('shorter than a dotted 1/8, or under %d ms with a note within a quarter after it'):format(m.ms)
        elseif bpm >= DIFF_SUSTAIN_MIN_BPM then
            short = 'shorter than a dotted 1/8'
        end
    else
        short = 'shorter than a ' .. NoteName(Gen5MinSustainQN(dl, bpm))
    end
    local plain = short
        and ('A sustain %s becomes a plain %s note.'):format(short, NoteName(MidiLengthPlainQN(kind, dl)))
        or 'Sustains of any length stay.'
    return ('%s %s. %s'):format(head, gap, plain)
end
