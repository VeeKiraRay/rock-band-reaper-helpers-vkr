-- Read-only difficulty suggestion for the current project.
--
-- Scores the finished Expert charts in the open project and returns one record per
-- instrument: a suggested rank, its tier, where it sits inside that tier band, and the
-- factor table behind it. Presentation is ui_metadata.lua's job and the explanation
-- wording is difficulty_explain.lua's; this file decides only what was measured.
--
-- READ-ONLY, AND THAT IS A HARD PROPERTY, NOT AN INTENTION. Nothing here calls Undo_*,
-- MarkTrackItemsDirty, MIDI_Insert*, SetProjExtState, or writes a track/item value.
-- Running a suggestion must leave the project bit-identical and must not create an undo
-- point, so an author can ask for it mid-edit without it appearing in their undo history.
--
-- Requires (globals): r, RB_CHART_SPECS, ScoreChartForSpec, FindTrackExact,
--                     ReadVocalNotes (difficulty_read.lua),
--                     RB_DIFFICULTY_MODELS, RB_DIFFICULTY_MODEL_ORDER
--                     (lib/reaper_difficulty_models.lua),
--                     DifficultyPredictRank (lib/reaper_difficulty_predict.lua),
--                     TierForRank, TierName, TierPosition (lib/reaper_difficulty_tiers.lua),
--                     DifficultyAnnotate (difficulty_explain.lua - load before this file)
--
-- Deliberately NOT required: S. The suggestion is a pure function of the project, so it
-- can be driven by a test with no UI state, and the UI owns where the result is stored.

----------------------------------------------------------------------
-- Harmony parts
----------------------------------------------------------------------

-- HARM tracks that actually carry sung notes, as a 1..3 part count.
--
-- WHY THIS EXISTS AT ALL. `vocal_parts` is one of the ten factors in the vocal model, and
-- the corpus read it from the song's songs.dta. A REAPER project being authored has no
-- songs.dta, so the count has to come from the MIDI. Presence-with-notes was measured
-- against the dta field across the whole calibration corpus: 203 of 203 vocal songs agree,
-- 0 disagree. So this is the same number by a different route, not an approximation.
--
-- Notes rather than track presence, because an authored-but-empty HARM2 is a common
-- intermediate state and would otherwise claim a harmony the song does not have.
--
-- HARM1 is not consulted: it is the lead part, duplicated from PART VOCALS, so a song
-- with any vocals at all has one part by definition.
function CountVocalParts()
    local n = 1
    for _, name in ipairs({ 'HARM2', 'HARM3' }) do
        local track = FindTrackExact(name)
        if track and #ReadVocalNotes(track) > 0 then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------
-- Availability
----------------------------------------------------------------------

-- Why an instrument cannot be scored, or nil when it can.
--
-- ABSENT AND MUTED ARE REPORTED SEPARATELY, which is why this does not call
-- GetMutedInstruments(). That function answers one question - "is this instrument
-- unavailable" - by returning true for a track that is missing OR muted, which is right
-- for venue generation and useless here: an author who muted PART KEYS while working on
-- something else needs a different sentence from one whose project has no keys chart. It
-- also matches names case-sensitively through FindTrackByName, while every chart reader
-- here matches case-insensitively through FindTrackExact, so a lowercased track name would
-- be found by one and not the other and would report as "muted" while being read fine.
--
-- The mute test itself is identical to that function's (B_MUTE == 1), so the policy is the
-- same; only the reporting is finer.
local function Unavailable(spec)
    local track = FindTrackExact(spec.track)
    if not track then return spec.track .. ' not found' end
    if r.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then
        return spec.track .. ' is muted'
    end
    return nil
end

-- A chart with no playable content is "no chart", never tier 0: an empty track and the
-- easiest possible chart are different answers, and rank 0 in songs.dta means the song has
-- no such part at all.
--
-- Reads the factor table rather than counting notes again, so "empty" means exactly what
-- the scorer saw - including a track holding only markers and animation states.
local function NoContent(factors, spec)
    if spec.vocal then
        if (factors.syllables_total or 0) <= 0 then return 'no vocal notes' end
    elseif (factors.events or 0) <= 0 then
        return 'no Expert gems'
    end
    if factors.no_playing_time then return 'no playing time' end
    return nil
end

----------------------------------------------------------------------
-- One instrument
----------------------------------------------------------------------

-- Returns a record. `ok` is false with a `reason` whenever there is nothing to suggest -
-- the caller still shows the row, because silently omitting an instrument looks the same
-- as the tool not having noticed it.
local function SuggestOne(spec, vocal_parts)
    local rec = {
        instrument = spec.key,
        label      = spec.label,
        ok         = false,
    }

    local model = RB_DIFFICULTY_MODELS[spec.key]
    if not model then
        rec.reason = 'no fitted model for ' .. spec.key
        return rec
    end
    rec.status = model.status

    local reason = Unavailable(spec)
    if reason then
        rec.reason = reason
        return rec
    end

    local factors, info, err = ScoreChartForSpec(spec, nil, { vocal_parts = vocal_parts })
    if not factors then
        rec.reason = err or 'could not read the chart'
        return rec
    end

    reason = NoContent(factors, spec)
    if reason then
        rec.reason = reason
        return rec
    end

    local rank, clamped, raw = DifficultyPredictRank(model, factors)
    if not rank then
        -- `clamped` carries the missing factor name on this path. A model naming a column
        -- the scorer does not produce is a build error rather than a chart problem, so it
        -- says so instead of blaming the project.
        rec.reason = ('model expects a factor the scorer did not produce (%s)')
            :format(tostring(clamped))
        return rec
    end

    rec.ok            = true
    rec.model         = model
    rec.factors       = factors
    rec.span_source   = info.span_source
    rec.rank          = rank
    rec.raw_rank      = raw
    rec.clamped       = clamped
    rec.tier          = TierForRank(spec.key, rank)
    rec.tier_name     = TierName(rec.tier)
    rec.tier_position = TierPosition(spec.key, rank, model.rank_hi)
    rec.vocal_parts   = spec.vocal and vocal_parts or nil

    -- Wording is difficulty_explain.lua's job, but it is attached here so every consumer
    -- gets the same annotations rather than each remembering to ask for them.
    DifficultyAnnotate(rec)
    return rec
end

----------------------------------------------------------------------
-- The whole project
----------------------------------------------------------------------

-- One record per instrument the suggester covers, in a fixed order, whether or not each
-- has a chart. Never raises: a malformed track produces a failed record for that
-- instrument only, so one bad chart cannot cost the author the other five suggestions.
--
-- Scores the WHOLE chart. A time selection does not change the result and is not consulted
-- - the models were calibrated on whole songs, so a section-relative rating would be a
-- different measurement wearing the same numbers. The UI says so; see the product plan's
-- "Settled v1 behavior".
function SuggestProjectDifficulties()
    local out = {}

    -- Counted once rather than per instrument: it reads two tracks in full, and only the
    -- vocal model uses it.
    local ok_parts, vocal_parts = pcall(CountVocalParts)
    if not ok_parts then vocal_parts = 1 end

    for _, spec in ipairs(RB_CHART_SPECS) do
        local ok, rec = pcall(SuggestOne, spec, vocal_parts)
        if ok then
            out[#out + 1] = rec
        else
            out[#out + 1] = {
                instrument = spec.key,
                label      = spec.label,
                status     = RB_DIFFICULTY_MODELS[spec.key]
                             and RB_DIFFICULTY_MODELS[spec.key].status or nil,
                ok         = false,
                reason     = 'could not be scored: ' .. tostring(rec),
            }
        end
    end
    return out
end

-- True when the project holds at least one track this suggester would try to read. Lets
-- the UI tell "no Rock Band tracks here" apart from six individual not-found rows, which
-- is the difference between the wrong project being open and a chart being missing.
function HasAnyChartTrack()
    for _, spec in ipairs(RB_CHART_SPECS) do
        if FindTrackExact(spec.track) then return true end
    end
    return false
end
