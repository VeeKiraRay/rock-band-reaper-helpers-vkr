-- Metadata > Genre coverage.
--
-- The failure modes here are all silent in the UI, which is why they are pinned:
--   * A candidate naming a genre/subgenre pair that does not exist renders as a blank
--     row rather than an error (ResolveExtendedGenre skips what it cannot resolve).
--   * A transcription that gains or loses an entry against the source page changes what
--     the tool claims Rock Band supports, and nothing on screen would say so.
--   * A supported genre no extended entry points at is unreachable in the forward
--     direction, so an author can never be sent there.
--   * Non-ASCII in a label or reason renders as mojibake in ImGui and in the console.
--
-- All pure - no project fixture, no tracks, no UI. Requires globals: Test, plus the
-- three modules' own tables and functions, all set up by run_metadata_genres.lua.

-- The counts the source page actually enumerates. Its own intro prose says 21 and 120,
-- which is stale; 29 was confirmed against the tool that does the final selection.
local WANT_GENRES    = 29
local WANT_SUBGENRES = 126

local function CountSubgenres()
    local n = 0
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        n = n + #RB3_GENRES[gk].subgenres
    end
    return n
end

local function FirstNonAscii(s)
    for i = 1, #s do
        if s:byte(i) > 127 then return i end
    end
    return nil
end

----------------------------------------------------------------------
Test.section('Supported vocabulary (metadata_genres.lua)')

Test.it('enumerates the documented 29 major genres', function()
    Test.expect(#RB3_GENRE_ORDER == WANT_GENRES,
        ('RB3_GENRE_ORDER has %d, want %d'):format(#RB3_GENRE_ORDER, WANT_GENRES))
end)

Test.it('enumerates the documented 126 subgenres', function()
    local n = CountSubgenres()
    Test.expect(n == WANT_SUBGENRES, ('found %d subgenres, want %d'):format(n, WANT_SUBGENRES))
end)

Test.it('order list and keyed table agree exactly', function()
    local seen = {}
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        Test.expect(RB3_GENRES[gk] ~= nil, 'ordered genre missing from table: ' .. gk)
        Test.expect(not seen[gk], 'listed twice in RB3_GENRE_ORDER: ' .. gk)
        seen[gk] = true
    end
    for gk in pairs(RB3_GENRES) do
        Test.expect(seen[gk], 'in RB3_GENRES but not in RB3_GENRE_ORDER: ' .. gk)
    end
end)

Test.it('every genre has a label and at least one subgenre', function()
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        local g = RB3_GENRES[gk]
        Test.expect(g.label and g.label ~= '', 'no label: ' .. gk)
        Test.expect(#g.subgenres > 0, 'no subgenres: ' .. gk)
    end
end)

Test.it('subgenre keys are unique within their own genre', function()
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        local seen = {}
        for _, s in ipairs(RB3_GENRES[gk].subgenres) do
            Test.expect(not seen[s.key], ('%s lists subgenre %s twice'):format(gk, tostring(s.key)))
            seen[s.key] = true
            Test.expect(s.label and s.label ~= '', ('%s/%s has no label'):format(gk, tostring(s.key)))
        end
    end
end)

-- Subgenre keys are scoped to their parent, so the same key under two different genres
-- is correct and expected: Garage exists under Rock, Punk and Pop/Dance/Electronic.
Test.it('a repeated subgenre key across genres resolves to its own parent', function()
    local rock   = RB3Subgenre('rock', 'garage')
    local punk   = RB3Subgenre('punk', 'garage')
    Test.expect(rock and punk, 'expected Garage under both Rock and Punk')
    Test.expect(rock ~= punk, 'the two Garage entries must be distinct records')
end)

----------------------------------------------------------------------
Test.section('Extended vocabulary (metadata_genres_ext.lua)')

Test.it('every family in the order list has a label and at least one entry', function()
    local used = {}
    for _, e in ipairs(EXTENDED_GENRES) do used[e.family] = true end
    for _, f in ipairs(GENRE_FAMILY_ORDER) do
        Test.expect(GENRE_FAMILIES[f] ~= nil, 'family has no display label: ' .. f)
        Test.expect(used[f], 'family has no entries, so its combo would be empty: ' .. f)
    end
    for f in pairs(GENRE_FAMILIES) do
        local listed = false
        for _, k in ipairs(GENRE_FAMILY_ORDER) do if k == f then listed = true end end
        Test.expect(listed, 'in GENRE_FAMILIES but not in GENRE_FAMILY_ORDER: ' .. f)
    end
end)

Test.it('entry keys and labels are unique', function()
    local k, l = {}, {}
    for _, e in ipairs(EXTENDED_GENRES) do
        Test.expect(not k[e.key], 'duplicate key: ' .. tostring(e.key))
        Test.expect(not l[e.label], 'duplicate label: ' .. tostring(e.label))
        k[e.key], l[e.label] = true, true
    end
end)

Test.it('every entry carries 1 to 3 candidates', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        local n = #(e.candidates or {})
        Test.expect(n >= 1 and n <= 3, ('%s has %d candidates'):format(e.key, n))
    end
end)

-- The assertion that stops a typo becoming wrong advice.
Test.it('every candidate names a genre/subgenre pair that exists', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, c in ipairs(e.candidates) do
            Test.expect(RB3_GENRES[c.genre] ~= nil,
                ('%s points at unknown genre %s'):format(e.key, tostring(c.genre)))
            Test.expect(RB3Subgenre(c.genre, c.subgenre) ~= nil,
                ('%s points at %s/%s, which does not exist')
                    :format(e.key, tostring(c.genre), tostring(c.subgenre)))
        end
    end
end)

-- Quality, not mere presence: "Exact match." on its own told the reader nothing the
-- label above it had not already said.
Test.it('every candidate reason is a usable sentence', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, c in ipairs(e.candidates) do
            Test.expect(type(c.why) == 'string' and #c.why >= 20,
                ('%s -> %s/%s has a reason of %d chars')
                    :format(e.key, tostring(c.genre), tostring(c.subgenre),
                            type(c.why) == 'string' and #c.why or -1))
        end
    end
end)

Test.it('no candidate pair is listed twice within one entry', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        local seen = {}
        for _, c in ipairs(e.candidates) do
            local pk = tostring(c.genre) .. '/' .. tostring(c.subgenre)
            Test.expect(not seen[pk], ('%s lists %s twice'):format(e.key, pk))
            seen[pk] = true
        end
    end
end)

-- A supported genre nobody can arrive at is a hole in the mapping, not a valid state.
Test.it('every supported major genre is reachable from some entry', function()
    local hit = {}
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, c in ipairs(e.candidates) do hit[c.genre] = true end
    end
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        Test.expect(hit[gk], 'no extended genre maps to ' .. gk)
    end
end)

----------------------------------------------------------------------
Test.section('see_also (redirects to another extended entry)')

-- A see_also is NOT a candidate: it says "you may have picked the wrong genre", where a
-- candidate says "here is another supported home for the genre you picked". Keeping them
-- apart in the data is what lets the UI stop presenting them as the same kind of choice.
Test.it('every see_also names an entry that exists and is not itself', function()
    local keys = {}
    for _, e in ipairs(EXTENDED_GENRES) do keys[e.key] = true end
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, sa in ipairs(e.see_also or {}) do
            Test.expect(type(sa.key) == 'string', e.key .. ' has a see_also with no key')
            Test.expect(keys[sa.key], ('%s points at %s, which does not exist')
                :format(e.key, tostring(sa.key)))
            Test.expect(sa.key ~= e.key, e.key .. ' points see_also at itself')
        end
    end
end)

Test.it('every see_also carries a usable condition', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, sa in ipairs(e.see_also or {}) do
            Test.expect(type(sa.when) == 'string' and #sa.when >= 20,
                ('%s -> see_also %s has no usable condition'):format(e.key, tostring(sa.key)))
        end
    end
end)

-- The point of the split: a redirect must not also be offered as a filing, or the two
-- have simply merged again under different names.
Test.it('a see_also target is not also a candidate genre of the same entry', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        for _, sa in ipairs(e.see_also or {}) do
            local target = ExtendedGenreByKey(sa.key)
            if target and target.candidates[1] then
                local t = target.candidates[1]
                for _, c in ipairs(e.candidates) do
                    Test.expect(not (c.genre == t.genre and c.subgenre == t.subgenre),
                        ('%s both redirects to %s and offers its pair as a candidate')
                            :format(e.key, sa.key))
                end
            end
        end
    end
end)

Test.it('ResolveExtendedGenre resolves see_also to a label', function()
    local res = ResolveExtendedGenre('post_grunge')
    Test.expect(res ~= nil, 'post_grunge did not resolve')
    if res then
        Test.expect(#res.see_also == 1, 'post_grunge should carry exactly one see_also')
        local sa = res.see_also[1]
        Test.expect(sa ~= nil and sa.label == 'Grunge',
            'expected the Grunge label, got ' .. tostring(sa and sa.label))
        Test.expect(#res.candidates == 1,
            'post_grunge should have one candidate now that Grunge moved to see_also')
    end
end)

Test.it('an entry with no see_also resolves to an empty list, never nil', function()
    local res = ResolveExtendedGenre('djent')
    Test.expect(res ~= nil, 'djent did not resolve')
    if res then
        Test.expect(type(res.see_also) == 'table' and #res.see_also == 0,
            'expected an empty see_also table')
    end
end)

----------------------------------------------------------------------
Test.section('Text is plain ASCII')

-- ImGui's default font and the REAPER console both render non-ASCII badly, and the
-- source page contains at least one stray Latin-1 byte (Queensryche).
Test.it('no non-ASCII byte in any supported label or description', function()
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        local g = RB3_GENRES[gk]
        Test.expect(not FirstNonAscii(g.label), 'non-ASCII in genre label: ' .. gk)
        for _, s in ipairs(g.subgenres) do
            for _, f in ipairs({ 'label', 'blurb', 'elements', 'artists', 'albums' }) do
                if s[f] then
                    Test.expect(not FirstNonAscii(s[f]),
                        ('non-ASCII in %s/%s %s'):format(gk, s.key, f))
                end
            end
        end
    end
end)

Test.it('no non-ASCII byte in any extended label or reason', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        Test.expect(not FirstNonAscii(e.label), 'non-ASCII in label: ' .. e.key)
        for _, c in ipairs(e.candidates) do
            Test.expect(not FirstNonAscii(c.why), 'non-ASCII in reason under ' .. e.key)
        end
    end
end)

-- The repo writes plain hyphens on purpose; an em-dash is the usual way one sneaks in.
Test.it('no em-dash anywhere in either table', function()
    local function HasEmDash(s) return s:find('\226\128\148', 1, true) ~= nil end
    for _, e in ipairs(EXTENDED_GENRES) do
        Test.expect(not HasEmDash(e.label), 'em-dash in label: ' .. e.key)
        for _, c in ipairs(e.candidates) do
            Test.expect(not HasEmDash(c.why), 'em-dash in reason under ' .. e.key)
        end
    end
    for _, gk in ipairs(RB3_GENRE_ORDER) do
        for _, s in ipairs(RB3_GENRES[gk].subgenres) do
            for _, f in ipairs({ 'label', 'blurb', 'elements', 'artists', 'albums' }) do
                if s[f] then
                    Test.expect(not HasEmDash(s[f]), ('em-dash in %s/%s %s'):format(gk, s.key, f))
                end
            end
        end
    end
end)

----------------------------------------------------------------------
Test.section('Lookup (metadata_genres_lookup.lua)')

Test.it('ValidateGenreTables reports nothing', function()
    local problems = ValidateGenreTables()
    for _, p in ipairs(problems) do Test.expect(false, p) end
    Test.expect(#problems == 0, ('%d problem(s) reported'):format(#problems))
end)

Test.it('GenresInFamily covers every entry exactly once', function()
    local total = 0
    for _, f in ipairs(GENRE_FAMILY_ORDER) do total = total + #GenresInFamily(f) end
    Test.expect(total == #EXTENDED_GENRES,
        ('families hold %d entries, table has %d'):format(total, #EXTENDED_GENRES))
end)

-- The UI indexes the result without a nil guard, so this must never be nil.
Test.it('GenresInFamily returns an empty table for an unknown family', function()
    local out = GenresInFamily('no_such_family')
    Test.expect(type(out) == 'table' and #out == 0, 'expected an empty table')
end)

Test.it('ResolveExtendedGenre resolves every entry with all candidates intact', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        local res = ResolveExtendedGenre(e.key)
        Test.expect(res ~= nil, 'did not resolve: ' .. e.key)
        if res then
            -- A candidate is dropped only when its pair does not resolve, which the
            -- pair test above already forbids; this catches the two drifting apart.
            Test.expect(#res.candidates == #e.candidates,
                ('%s resolved %d of %d candidates'):format(e.key, #res.candidates, #e.candidates))
            Test.expect(res.family_label == GENRE_FAMILIES[e.family],
                'wrong family label on ' .. e.key)
            for _, c in ipairs(res.candidates) do
                Test.expect(c.genre_label and c.sub_label and c.sub,
                    'candidate not fully resolved on ' .. e.key)
            end
        end
    end
end)

Test.it('ResolveExtendedGenre returns nil for an unknown key', function()
    Test.expect(ResolveExtendedGenre('no_such_genre') == nil, 'expected nil')
end)

Test.it('the reverse index round-trips every candidate into the right bucket', function()
    for _, e in ipairs(EXTENDED_GENRES) do
        for i, c in ipairs(e.candidates) do
            local first, lower = ExtendedGenresForPair(c.genre, c.subgenre)
            local want, other = first, lower
            if i > 1 then want, other = lower, first end
            local found = false
            for _, x in ipairs(want) do if x.key == e.key then found = true end end
            Test.expect(found, ('%s (candidate %d) missing from the %s bucket of %s/%s')
                :format(e.key, i, i == 1 and 'first' or 'lower', c.genre, c.subgenre))
            -- Nothing should land in both buckets for the same pair.
            for _, x in ipairs(other) do
                Test.expect(x.key ~= e.key,
                    ('%s appears in both buckets of %s/%s'):format(e.key, c.genre, c.subgenre))
            end
        end
    end
end)

Test.it('ExtendedGenresForPair returns two empty tables for an unmapped pair', function()
    local first, lower = ExtendedGenresForPair('no_genre', 'no_sub')
    Test.expect(type(first) == 'table' and #first == 0, 'expected an empty first bucket')
    Test.expect(type(lower) == 'table' and #lower == 0, 'expected an empty lower bucket')
end)

-- Guards the specific calls the module header justifies from catalogue evidence, so a
-- later edit cannot quietly undo them.
Test.it('the calibrated calls are still in place', function()
    local function FirstPair(key)
        local res = ResolveExtendedGenre(key)
        if not res or #res.candidates == 0 then return '<none>' end
        return res.candidates[1].genre_key .. '/' .. res.candidates[1].sub_key
    end
    Test.expect(FirstPair('post_grunge') == 'rock/hard_rock',
        'post-grunge should lead with Rock / Hard Rock, got ' .. FirstPair('post_grunge'))
    Test.expect(FirstPair('deathcore') == 'metal/metalcore',
        'deathcore should lead with Metal / Metalcore, got ' .. FirstPair('deathcore'))
    Test.expect(FirstPair('djent') == 'metal/progressive',
        'djent should lead with Metal / Progressive, got ' .. FirstPair('djent'))
    local djent = ResolveExtendedGenre('djent')
    Test.expect(djent ~= nil and #djent.candidates >= 2, 'djent must keep its Prog alternative')

    -- Settled by checking sources, not by taste, so they get pinned like the rest.
    -- Screamo is an offshoot of emo; leading with Metalcore was wrong.
    Test.expect(FirstPair('screamo') == 'emo/emo',
        'screamo should lead with Emo / Emo, got ' .. FirstPair('screamo'))
    -- Viking metal grew out of black metal, so Black leads despite the style being broad.
    Test.expect(FirstPair('viking_metal') == 'metal/black',
        'viking metal should lead with Metal / Black, got ' .. FirstPair('viking_metal'))
    -- Jazz / Contemporary means MODERN jazz, so historic jazz must not be back-dated
    -- into it. Jazz / Other is the honest home.
    Test.expect(FirstPair('big_band') == 'jazz/other',
        'big band should lead with Jazz / Other, got ' .. FirstPair('big_band'))

    -- Viking and Folk Metal each need the melodeath branch reachable.
    for _, k in ipairs({ 'viking_metal', 'folk_metal' }) do
        local res = ResolveExtendedGenre(k)
        local has_death = false
        for _, c in ipairs(res and res.candidates or {}) do
            if c.genre_key == 'metal' and c.sub_key == 'death' then has_death = true end
        end
        Test.expect(has_death, k .. ' must offer Metal / Death for its melodeath branch')
    end
end)
