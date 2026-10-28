-- Metadata > Song key: reads the charted parts from the project and ranks the keys
-- (lib/reaper_key_detect.lua). Read-only - never writes, never touches S, never creates an
-- undo point.
--
-- Reads exactly what dev/tools/key_detect_fit_offline.lua reads from the reference MIDIs,
-- so the profiles mean the same thing here: pitched PART VOCALS and HARM1-3 notes
-- (36-84) minus the ones whose lyric marks them unpitched ('#', '#$'), and PART
-- REAL_KEYS_X notes (48-72). The whole song is read; a time selection is not consulted,
-- because the profiles were fitted on whole songs.
--
-- Requires globals: r, FindTrackExact (lib/reaper_difficulty_read.lua), KeyFeatures,
--                   KeyRankSet, KeyConfidence, KEY_RESULT_SETS, KEY_VOCAL_LO/HI,
--                   KEY_KEYS_LO/HI, KeyLyricIsUnpitched, KeySetLabel
--                   (lib/reaper_key_detect.lua),
--                   RB_KEY_PROFILES (lib/reaper_key_profiles.lua)

-- The bar number of project time t as REAPER shows it (format_timestr_pos honours the
-- project's measure offset; TimeMap2_timeToBeats does not). It only labels the key
-- check's "outside the key" lists; it plays no part in scoring.
local function BarAt(t)
    return tonumber(r.format_timestr_pos(t, '', 1):match('^(%-?%d+)'))
end

-- Notes on one track within [lo, hi]. With vocal = true, notes whose lyric marks them
-- unpitched are dropped and counted. Returns notes, unpitched_count.
-- Lyrics are matched by tick per take, from text (1) and lyric (5) events alike - official
-- charts use both - skipping bracketed events, which are animation states, not lyrics.
local function ReadPart(track, lo, hi, vocal)
    local notes, unpitched = {}, 0
    if not track then return notes, 0 end
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local take = r.GetActiveTake(r.GetTrackMediaItem(track, i))
        if take and r.TakeIsMIDI(take) then
            local lyric = {}
            if vocal then
                local _, _, _, textcnt = r.MIDI_CountEvts(take)
                for j = 0, textcnt - 1 do
                    local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(take, j)
                    if ok and msg and (typ == 1 or typ == 5) and not msg:match('^%[') then
                        lyric[ppq] = msg
                    end
                end
            end
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, j)
                if ok and not muted and pitch >= lo and pitch <= hi then
                    if vocal and KeyLyricIsUnpitched(lyric[sppq]) then
                        unpitched = unpitched + 1
                    else
                        local qn  = r.MIDI_GetProjQNFromPPQPos(take, sppq)
                        local qne = r.MIDI_GetProjQNFromPPQPos(take, eppq)
                        notes[#notes + 1] = {
                            pitch = pitch, qn = qn, len = qne - qn,
                            bar = BarAt(r.MIDI_GetProjTimeFromPPQPos(take, sppq)),
                        }
                    end
                end
            end
        end
    end
    return notes, unpitched
end

-- The tracks the key check lists, in display order. Each is read once; HARM1-3 are kept
-- apart here (the harmonies set merges them) so a harmony charted off key shows by name.
local CHECK_TRACKS = {
    { name = 'PART VOCALS',      lo = KEY_VOCAL_LO, hi = KEY_VOCAL_HI, vocal = true,  part = 'vocals' },
    { name = 'HARM1',            lo = KEY_VOCAL_LO, hi = KEY_VOCAL_HI, vocal = true,  part = 'harm' },
    { name = 'HARM2',            lo = KEY_VOCAL_LO, hi = KEY_VOCAL_HI, vocal = true,  part = 'harm' },
    { name = 'HARM3',            lo = KEY_VOCAL_LO, hi = KEY_VOCAL_HI, vocal = true,  part = 'harm' },
    { name = 'PART REAL_KEYS_X', lo = KEY_KEYS_LO,  hi = KEY_KEYS_HI,  vocal = false, part = 'keys',
      label = 'Pro Keys (PART REAL_KEYS_X)' },
}

-- Ranks the keys for every result set, and keeps each track's notes for the key check.
-- Returns {
--   parts  = { vocals = { found, notes, unpitched } },  -- PART VOCALS, for the notes above
--   tracks = { { name, label, found, notes = list, unpitched }, ... } in CHECK_TRACKS order,
--   sets   = { { set, label, ranked, used, confidence } or { set, label, why }, ... } in
--            KEY_RESULT_SETS order; label names only the parts the set actually read,
-- }
function SuggestProjectSongKey()
    local by_part = { vocals = {}, harm = {}, keys = {} }
    local tracks = {}
    for _, t in ipairs(CHECK_TRACKS) do
        local tr = FindTrackExact(t.name)
        local notes, unp = ReadPart(tr, t.lo, t.hi, t.vocal)
        tracks[#tracks + 1] = { name = t.name, label = t.label or t.name, found = tr ~= nil,
                                notes = notes, unpitched = unp }
        for _, n in ipairs(notes) do
            local list = by_part[t.part]
            list[#list + 1] = n
        end
    end

    local features = KeyFeatures(by_part)
    local out = {
        parts  = { vocals = { found = tracks[1].found, notes = #tracks[1].notes,
                              unpitched = tracks[1].unpitched } },
        tracks = tracks,
        sets   = {},
    }
    for _, set in ipairs(KEY_RESULT_SETS) do
        -- Second value: the sources used, or why the set is unavailable.
        local ranked, extra = KeyRankSet(features, set, RB_KEY_PROFILES.sources)
        local label = KeySetLabel(set, features)
        if ranked then
            out.sets[#out.sets + 1] = { set = set, label = label, ranked = ranked, used = extra,
                                        confidence = KeyConfidence(ranked) }
        else
            out.sets[#out.sets + 1] = { set = set, label = set.label, why = extra }
        end
    end
    return out
end
