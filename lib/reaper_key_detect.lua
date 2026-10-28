-- Song key suggestion from charted MIDI notes - pure, no r / ctx / S.
--
-- Suggests the vocal tonic note and major/minor (the `vocal_tonic_note` and
-- `song_tonality` fields of songs.dta) from the notes an author has charted. Used by the
-- General Helper's Metadata > Song key sub-tab and by dev/tools/key_detect_fit_offline.lua,
-- which fits the profiles in reaper_key_profiles.lua against the official RB3 DLC charts.
--
-- HOW IT DECIDES. Each source below is a 12-bin pitch-class histogram. Every candidate key
-- (12 tonics x major/minor) is scored by correlating each histogram with that source's
-- profile rotated to the candidate tonic, and summing the correlations with the source's
-- weight. The profiles are not the textbook Krumhansl-Kessler ones: they are the average
-- histograms of the official charts, rotated to the tonic Harmonix wrote in songs.dta, so
-- they describe how pop and rock melodies actually sit in a key.
--
-- WHY SEVERAL SOURCES. A vocal melody often uses only 3-4 notes of the scale, and a
-- relative major/minor pair (C major / A minor) shares all seven, so a melody alone often
-- cannot tell them apart. The harmonies add notes, Pro Keys adds whole chords, and the
-- song's last notes and the lowest Pro Keys note of each chord carry most of what says
-- which note is home. Nothing reads beats or bars, so no tempo map is needed.
--
-- RESULT SETS. The tab shows four results side by side rather than one blend, because an
-- author can judge each input: Pro Keys is often not charted, and a harmony part may be a
-- simple third above the melody. A set that is missing its own input is reported as
-- unavailable rather than quietly falling back to a smaller set.

KEY_TONIC_NAMES = {
    [0] = 'C', 'C#/Db', 'D', 'D#/Eb', 'E', 'F', 'F#/Gb', 'G', 'G#/Ab', 'A', 'A#/Bb', 'B',
}

-- Pitched notes a vocal or Pro Keys source needs before its histogram means anything.
-- Below this a result set is unavailable. Low on purpose: a short song is still a song,
-- and the result panel says how many notes each answer used.
KEY_MIN_NOTES = 16

-- Pitch ranges read from each part, inclusive.
KEY_VOCAL_LO, KEY_VOCAL_HI = 36, 84   -- PART VOCALS / HARM1-3 pitched notes
KEY_KEYS_LO,  KEY_KEYS_HI  = 48, 72   -- PART REAL_KEYS_X

-- Shortest length counted, in quarter notes, so a zero-length note still counts a little.
local MIN_LEN_QN = 1 / 16

-- How many of the last notes form the "ending" sources.
local VOCAL_LAST_N = 4
local KEYS_LAST_N  = 3

-- The sources, in a fixed order (the generated profile file uses the same keys).
KEY_SOURCES = { 'V', 'Vlast', 'H', 'K', 'Kbass', 'Klast' }

KEY_SOURCE_DESC = {
    V     = 'PART VOCALS notes, weighted by length',
    Vlast = 'the last few PART VOCALS notes',
    H     = 'HARM1-3 notes, weighted by length',
    K     = 'Pro Keys notes, weighted by length',
    Kbass = 'the lowest Pro Keys note of each chord',
    Klast = 'the lowest notes of the last few Pro Keys chords',
}

-- The result sets and each source's weight in them (dev/tools/key_detect_fit_offline.lua
-- prints how each set scores against the reference charts). A set uses its sources only
-- where the project has them. `parts` lists the inputs a set reads, for its label
-- (KeySetLabel).
--
-- The fourth set, Pro Keys alone, is a second opinion rather than a better answer: it
-- often disagrees with the vocals, and is worth a look exactly when it does. It sits
-- beside the combined result, never instead of it.
KEY_RESULT_SETS = {
    { key = 'vocals', label = 'PART VOCALS',
      needs = 'vocals', parts = { 'vocals' },
      weights = { V = 2, Vlast = 0.5 } },
    { key = 'harm',   label = 'PART VOCALS + harmonies',
      needs = 'harm', parts = { 'vocals', 'harm' },
      weights = { V = 2, Vlast = 0.5, H = 2 } },
    { key = 'keys',   label = 'PART VOCALS + harmonies + Pro Keys',
      needs = 'keys', parts = { 'vocals', 'harm', 'keys' },
      weights = { V = 2, Vlast = 0.5, H = 2, K = 2, Kbass = 0.5, Klast = 0.25 } },
    { key = 'keysonly', label = 'Pro Keys only (check)', fixed_label = true,
      needs = 'keys', parts = { 'keys' },
      weights = { K = 2 } },
}

KEY_PART_LABELS = { vocals = 'PART VOCALS', harm = 'harmonies', keys = 'Pro Keys' }

-- A set's label naming only the parts it actually read, so "+ harmonies" never appears
-- for a project without harmony notes. features from KeyFeatures.
function KeySetLabel(set, features)
    if set.fixed_label then return set.label end
    local out = {}
    for _, p in ipairs(set.parts) do
        if (features.counts[p] or 0) > 0 then out[#out + 1] = KEY_PART_LABELS[p] end
    end
    return #out > 0 and table.concat(out, ' + ') or set.label
end

-- A note "uses" a key note when that note is at least this share of the track's notes;
-- one stray note is not use. A track using KEY_FEW_NOTES or fewer of the key's notes fits
-- many keys, so the tab says so.
KEY_USED_MIN_SHARE = 0.02
KEY_FEW_NOTES = 4

-- How far the best key's score leads the runner-up's. The fitter prints how often each
-- band of lead matches the reference charts; a lead under KEY_CLOSE_MARGIN is close to a
-- coin flip. Used for wording only - the tab never shows a percentage, since the
-- reference keys are themselves one charter's judgement.
KEY_CLEAR_MARGIN = 0.15
KEY_CLOSE_MARGIN = 0.08

-- 'clear', 'fair' or 'close' for a ranked list from KeyRankSet.
function KeyConfidence(ranked)
    local margin = ranked[1].score - ranked[2].score
    if margin >= KEY_CLEAR_MARGIN then return 'clear' end
    if margin >= KEY_CLOSE_MARGIN then return 'fair' end
    return 'close'
end

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------

-- "F#/Gb major". tonic 0-11, minor boolean.
function KeyName(tonic, minor)
    return KEY_TONIC_NAMES[tonic % 12] .. (minor and ' minor' or ' major')
end

-- How key b relates to key a, for labelling a runner-up: 'relative' (C major / A minor),
-- 'parallel' (C major / C minor), 'fifth' (tonics a fifth apart, same mode), or nil.
function KeyRelation(a_tonic, a_minor, b_tonic, b_minor)
    if a_minor ~= b_minor then
        if a_tonic == b_tonic then return 'parallel' end
        local rel = a_minor and (a_tonic + 3) % 12 or (a_tonic + 9) % 12
        if b_tonic == rel then return 'relative' end
    else
        local d = (b_tonic - a_tonic) % 12
        if d == 5 or d == 7 then return 'fifth' end
    end
    return nil
end

----------------------------------------------------------------------
-- Scales
----------------------------------------------------------------------

-- Each scale is spelled with every letter once (F# major has E#, not F; Eb minor has
-- Cb), the way a chord chart writes it, so the notes read like the key they belong to.
-- The tonic spellings pick the commoner name of each key: Db major rather than C# major,
-- G# minor rather than Ab minor.
local LETTERS   = { 'C', 'D', 'E', 'F', 'G', 'A', 'B' }
local LETTER_PC = { 0, 2, 4, 5, 7, 9, 11 }
local TONIC_SPELL = {
    [false] = { [0] = 'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B' },
    [true]  = { [0] = 'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B' },
}
local STEPS = {
    [false] = { 0, 2, 4, 5, 7, 9, 11 },   -- major
    [true]  = { 0, 2, 3, 5, 7, 8, 10 },   -- natural minor
}
local SHARP_NAMES = { [0] = 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
local FLAT_NAMES  = { [0] = 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' }
local ACCIDENTAL  = { [-2] = 'bb', [-1] = 'b', [0] = '', [1] = '#', [2] = '##' }

-- The seven notes of the key, tonic first: { { pc, name }, ... }, plus whether the key is
-- written with flats (used to spell notes outside it the same way).
-- Minor is the natural minor scale; the raised 7th of harmonic minor (G# in A minor) is
-- outside it, and the tab's tooltip says that such notes are normal.

-- "A  B  C  D  E  F  G" - the key's notes on one line, for tooltips and the key check.
function KeyScaleText(tonic, minor)
    local out = {}
    for i, s in ipairs((KeyScale(tonic, minor))) do out[i] = s.name end
    return table.concat(out, '  ')
end
function KeyScale(tonic, minor)
    tonic, minor = tonic % 12, minor and true or false
    local tl = TONIC_SPELL[minor][tonic]:sub(1, 1)
    local li = 1
    while LETTERS[li] ~= tl do li = li + 1 end
    local out, flats = {}, false
    for i, step in ipairs(STEPS[minor]) do
        local l = (li + i - 2) % 7 + 1
        local pc = (tonic + step) % 12
        local d = (pc - LETTER_PC[l] + 6) % 12 - 6   -- -6..5, accidental in semitones
        if d < 0 then flats = true end
        out[i] = { pc = pc, name = LETTERS[l] .. (ACCIDENTAL[d] or '?') }
    end
    return out, flats
end

-- One track's notes against a key:
--   { total = notes, share_out = share of notes outside the key (0..1),
--     used = how many of the key's notes the track uses (each >= KEY_USED_MIN_SHARE),
--     outside = notes outside the key, most frequent first: { pc, name, n, bars } }
-- notes: { pitch, bar (optional) }. Bars are sorted and listed once each.
--
-- The share outside is the useful number: the larger it is, the less likely the key is
-- right. How many of the key's notes a track uses matters only when it is very few
-- (KEY_FEW_NOTES), which is why the tab shows no "found in key" list.
function KeyTrackReport(notes, tonic, minor)
    local scale, flats = KeyScale(tonic, minor)
    local in_scale = {}
    for _, s in ipairs(scale) do in_scale[s.pc] = true end

    local n, bars = {}, {}
    for pc = 0, 11 do n[pc] = 0; bars[pc] = {} end
    for _, note in ipairs(notes or {}) do
        local pc = note.pitch % 12
        n[pc] = n[pc] + 1
        if note.bar then bars[pc][note.bar] = true end
    end

    local total, out_n, used = #(notes or {}), 0, 0
    local outside = {}
    for pc = 0, 11 do
        if in_scale[pc] then
            if total > 0 and n[pc] >= KEY_USED_MIN_SHARE * total then used = used + 1 end
        elseif n[pc] > 0 then
            out_n = out_n + n[pc]
            local list = {}
            for b in pairs(bars[pc]) do list[#list + 1] = b end
            table.sort(list)
            outside[#outside + 1] = {
                pc = pc, name = (flats and FLAT_NAMES or SHARP_NAMES)[pc], n = n[pc], bars = list,
            }
        end
    end
    table.sort(outside, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.pc < b.pc
    end)
    return { total = total, share_out = total > 0 and out_n / total or 0,
             used = used, outside = outside }
end

----------------------------------------------------------------------
-- Features
----------------------------------------------------------------------

-- Lyrics that mark a note unpitched: '#' (also '#$', the hidden-harmony form). Such a note
-- carries no pitch the singer is asked to match - screams, growls, spoken words - so it is
-- not evidence for a key.
function KeyLyricIsUnpitched(lyric)
    return lyric ~= nil and lyric:find('#', 1, true) ~= nil
end

local function NewHist() return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end

local function Normalize(h)
    local tot = 0
    for i = 1, 12 do tot = tot + h[i] end
    if tot > 0 then for i = 1, 12 do h[i] = h[i] / tot end end
    return h, tot
end

local function AddNote(h, n, w)
    if w > 0 then
        local pc = n.pitch % 12 + 1
        h[pc] = h[pc] + w
    end
end

local function NoteLen(n) return math.max(n.len or 0, MIN_LEN_QN) end

local function SortedByTime(notes)
    local out = {}
    for i, n in ipairs(notes or {}) do out[i] = n end
    table.sort(out, function(a, b)
        if a.qn ~= b.qn then return a.qn < b.qn end
        return a.pitch < b.pitch
    end)
    return out
end

-- Lowest note of each onset, in time order. Two notes are one onset when they start
-- within 1/64 QN of each other.
local function LowestPerOnset(sorted)
    local out, i = {}, 1
    while i <= #sorted do
        local j, lo = i, sorted[i]
        while j <= #sorted and sorted[j].qn - sorted[i].qn < 1 / 64 do
            if sorted[j].pitch < lo.pitch then lo = sorted[j] end
            j = j + 1
        end
        out[#out + 1] = lo
        i = j
    end
    return out
end

-- parts: { vocals = notes, harm = notes, keys = notes }, any of them nil or empty.
-- A note is { pitch, qn, len }: qn orders the notes and len weights them, so any one time
-- unit works as long as a part uses it throughout (the audio path passes seconds). The
-- caller has already dropped unpitched vocal notes and anything outside the part's range.
-- Returns { hist = { <source> = normalized histogram or nil }, counts = { vocals, harm, keys } }.
function KeyFeatures(parts)
    local v = SortedByTime(parts.vocals)
    local h = parts.harm or {}
    local k = SortedByTime(parts.keys)

    local f = { hist = {}, counts = { vocals = #v, harm = #h, keys = #k } }
    local function Put(name, hist)
        local nh, tot = Normalize(hist)
        if tot > 0 then f.hist[name] = nh end
    end

    if #v > 0 then
        local all, last = NewHist(), NewHist()
        for i, n in ipairs(v) do
            AddNote(all, n, NoteLen(n))
            if i > #v - VOCAL_LAST_N then AddNote(last, n, NoteLen(n)) end
        end
        Put('V', all); Put('Vlast', last)
    end

    if #h > 0 then
        local all = NewHist()
        for _, n in ipairs(h) do AddNote(all, n, NoteLen(n)) end
        Put('H', all)
    end

    if #k > 0 then
        local all, bass, last = NewHist(), NewHist(), NewHist()
        for _, n in ipairs(k) do AddNote(all, n, NoteLen(n)) end
        local lows = LowestPerOnset(k)
        for i, n in ipairs(lows) do
            AddNote(bass, n, NoteLen(n))
            if i > #lows - KEYS_LAST_N then AddNote(last, n, NoteLen(n)) end
        end
        Put('K', all); Put('Kbass', bass); Put('Klast', last)
    end

    return f
end

----------------------------------------------------------------------
-- Scoring
----------------------------------------------------------------------

local function Corr(x, y)
    local mx, my = 0, 0
    for i = 1, 12 do mx = mx + x[i]; my = my + y[i] end
    mx, my = mx / 12, my / 12
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, 12 do
        local a, b = x[i] - mx, y[i] - my
        sxy = sxy + a * b; sxx = sxx + a * a; syy = syy + b * b
    end
    if sxx == 0 or syy == 0 then return 0 end
    return sxy / math.sqrt(sxx * syy)
end

-- Why a result set cannot be computed from these features, or nil when it can.
-- 'no_vocals' / 'no_harm' / 'no_keys' - the caller turns these into sentences.
function KeySetUnavailable(features, set)
    local c = features.counts
    if set.needs == 'vocals' or set.needs == 'harm' then
        if c.vocals < KEY_MIN_NOTES then return 'no_vocals' end
    end
    if set.needs == 'harm' and c.harm == 0 then return 'no_harm' end
    -- Pro Keys alone is enough: a song whose vocals are all unpitched still has a key.
    if set.needs == 'keys' and c.keys < KEY_MIN_NOTES then return 'no_keys' end
    return nil
end

-- All 24 keys scored for one result set, best first:
--   { { tonic, minor, score }, ... }, sources_used (array of source names)
-- or nil, reason (see KeySetUnavailable).
-- profiles: RB_KEY_PROFILES.sources (reaper_key_profiles.lua) - per source, [0] major and
-- [1] minor, each 12 values with the tonic at index 1.
function KeyRankSet(features, set, profiles)
    local why = KeySetUnavailable(features, set)
    if why then return nil, why end

    local used, wsum = {}, 0
    for _, name in ipairs(KEY_SOURCES) do
        local w = set.weights[name]
        if w and w > 0 and features.hist[name] and profiles[name] then
            used[#used + 1] = name
            wsum = wsum + w
        end
    end
    if wsum == 0 then return nil, 'no_vocals' end

    local ranked = {}
    for tonic = 0, 11 do
        for m = 0, 1 do
            local s = 0
            for _, name in ipairs(used) do
                local prof = profiles[name][m]
                local rot = {}
                for i = 1, 12 do rot[i] = prof[((i - 1 - tonic) % 12) + 1] end
                s = s + set.weights[name] * Corr(features.hist[name], rot)
            end
            -- Divided by the weights used, so a score reads like a correlation (-1..1)
            -- whichever sources a project has.
            ranked[#ranked + 1] = { tonic = tonic, minor = m == 1, score = s / wsum }
        end
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.tonic ~= b.tonic then return a.tonic < b.tonic end
        return not a.minor and b.minor
    end)
    return ranked, used
end

-- The profiles a set of training songs implies: for every source, the average histogram
-- rotated so each song's tonic sits at index 1, separately for major [0] and minor [1],
-- normalized to sum 1. songs: { { features = KeyFeatures(...), tonic, minor }, ... }.
-- Used by the offline fitter; the shipped profiles are this function's output.
function KeyFitProfiles(songs)
    local out = {}
    for _, name in ipairs(KEY_SOURCES) do
        local acc = { [0] = NewHist(), [1] = NewHist() }
        local n = { [0] = 0, [1] = 0 }
        for _, s in ipairs(songs) do
            local h = s.features.hist[name]
            if h then
                local m = s.minor and 1 or 0
                for d = 0, 11 do
                    acc[m][d + 1] = acc[m][d + 1] + h[((s.tonic + d) % 12) + 1]
                end
                n[m] = n[m] + 1
            end
        end
        if n[0] > 0 and n[1] > 0 then
            out[name] = { [0] = (Normalize(acc[0])), [1] = (Normalize(acc[1])) }
        end
    end
    return out
end
