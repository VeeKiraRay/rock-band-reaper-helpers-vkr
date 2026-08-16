-- What the released-song catalogue says about genre, and where it disagrees with itself.
--
--     lua dev/tools/genre_corpus_report.lua [repo_root]
--
-- Reads the tab-separated exports in _external_docs/genre_reference_songs/ (name, artist,
-- genre, sub_genre; one song per line, a header line first) and reports what is actually
-- in them. Plain Lua, no REAPER: run it from a terminal.
--
-- WHY THIS EXISTS. metadata_genres_ext.lua is hand-authored judgment about which supported
-- pair a real-world style belongs to. This is the evidence behind that judgment, and the
-- way to re-check it after the mapping or the catalogue changes.
--
-- DEV ONLY, AND NOTHING HERE SHIPS. The catalogue is licensed content the repo does not
-- own; it is gitignored under _external_docs/*, and no song title, artist or count derived
-- from it may reach a shipped module or the UI. What ships is the mapping those numbers
-- informed, not the numbers.
--
-- THE MULTI-FILED LIST IS THE POINT. An artist filed under two different pairs has at
-- least three possible explanations and they must not be conflated:
--   1. the band changed style between releases - both filings correct, nothing to fix;
--   2. the cataloguing convention changed between game eras - look at the era column
--      before concluding anything about the band;
--   3. the boundary really is ambiguous - only this one justifies a second candidate in
--      metadata_genres_ext.lua.
-- The report cannot tell these apart. It flags the artists so a human can check.

local root = ... or './'
if not root:match('[/\\]$') then root = root .. '/' end

local SONG_DIR = root .. '_external_docs/genre_reference_songs/'
local MOD_DIR  = root .. 'rock_band_general_helper_vkr/'

----------------------------------------------------------------------
-- The catalogue's own genre tokens, mapped onto the transcribed vocabulary.
--
-- LOCAL TO THIS FILE ON PURPOSE. These are .dta spellings, and the shipped tables carry
-- display names only - see the header of metadata_genres.lua. Tokens also drift between
-- game eras, which is exactly what this map makes visible: 'urban' was RB1/RB2 and became
-- 'hiphoprap' in RB3, so it has no entry and gets reported as unmatched.
local TOKEN_TO_GENRE = {
    alternative        = 'alternative',
    blues              = 'blues',
    classicrock        = 'classic_rock',
    country            = 'country',
    emo                = 'emo',
    glam               = 'glam',
    grunge             = 'grunge',
    hiphoprap          = 'hip_hop_rap',
    indierock          = 'indie_rock',
    jazz               = 'jazz',
    metal              = 'metal',
    new_wave           = 'new_wave',
    novelty            = 'novelty',
    numetal            = 'nu_metal',
    other              = 'other',
    popdanceelectronic = 'pop_dance_electronic',
    poprock            = 'pop_rock',
    prog               = 'prog',
    punk               = 'punk',
    rbsoulfunk         = 'rnb_soul_funk',
    reggaeska          = 'reggae_ska',
    rock               = 'rock',
    southernrock       = 'southern_rock',
}

----------------------------------------------------------------------

dofile(MOD_DIR .. 'metadata_genres.lua')
dofile(MOD_DIR .. 'metadata_genres_ext.lua')
dofile(MOD_DIR .. 'metadata_genres_lookup.lua')

local function ListFiles(dir)
    local out = {}
    -- No LFS in the REAPER Lua distribution, and none needed: the export set is small
    -- and fixed. Anything not listed here is simply not read, which the summary shows.
    for _, name in ipairs({
        'rb1-bonus_songs.txt', 'rb1-dlc-songs.txt',
        'rb2-dlc-songs.txt',   'rb2-rbn-songs.txt',
        'rb3-dlc-songs.txt',   'rb3-rbn-songs.txt',
    }) do
        local f = io.open(dir .. name, 'r')
        if f then f:close(); out[#out + 1] = name end
    end
    return out
end

-- Dedupe on (name, artist). The rbn exports are strict subsets of the dlc ones, so the
-- same song appears more than once; a row carrying a subgenre always wins over one that
-- does not, since a blank field is an absent value rather than a different one.
local function ReadAll(dir, files)
    local rows, order = {}, {}
    for _, fname in ipairs(files) do
        local era = fname:match('^(rb%d)') or '?'
        local first = true
        for line in io.lines(dir .. fname) do
            line = line:gsub('\r', '')
            if first then
                first = false                     -- header
            elseif line ~= '' then
                local f = {}
                for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field end
                local name, artist = f[1] or '', f[2] or ''
                local genre, sub = f[3] or '', f[4] or ''
                if name ~= '' and artist ~= '' then
                    local key = name:lower() .. '\1' .. artist:lower()
                    local prev = rows[key]
                    if not prev then
                        rows[key] = { name = name, artist = artist, genre = genre,
                                      sub = sub, era = era }
                        order[#order + 1] = key
                    elseif prev.sub == '' and sub ~= '' then
                        prev.genre, prev.sub, prev.era = genre, sub, era
                    end
                end
            end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = rows[k] end
    return out
end

local function SortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

----------------------------------------------------------------------

local files = ListFiles(SONG_DIR)
if #files == 0 then
    print('No exports found in ' .. SONG_DIR)
    print('This tool needs the catalogue exports, which are gitignored and local-only.')
    os.exit(1)
end

local songs = ReadAll(SONG_DIR, files)

local genre_n, sub_n, pair_n, artists = {}, {}, {}, {}
local with_sub = 0
for _, s in ipairs(songs) do
    if s.genre ~= '' then genre_n[s.genre] = (genre_n[s.genre] or 0) + 1 end
    if s.sub ~= '' then
        with_sub = with_sub + 1
        sub_n[s.sub] = (sub_n[s.sub] or 0) + 1
        local pk = s.genre .. ' / ' .. s.sub
        pair_n[pk] = (pair_n[pk] or 0) + 1
        artists[s.artist] = artists[s.artist] or {}
        artists[s.artist][pk] = artists[s.artist][pk] or {}
        local list = artists[s.artist][pk]
        list[#list + 1] = s.name .. ' (' .. s.era .. ')'
    end
end

print('==== Genre catalogue report ====')
print(('files read        : %d  (%s)'):format(#files, table.concat(files, ', ')))
print(('unique songs      : %d'):format(#songs))
print(('carrying subgenre : %d  (%d%%)'):format(with_sub,
      #songs > 0 and math.floor(with_sub / #songs * 100 + 0.5) or 0))
print(('distinct pairs    : %d'):format(#SortedKeys(pair_n)))

----------------------------------------------------------------------
print('\n-- Genre tokens with no entry in the transcribed vocabulary')
print('   (retired or mis-typed tokens; expected, not necessarily a fault)')
local unmatched = 0
for _, tok in ipairs(SortedKeys(genre_n)) do
    local gk = TOKEN_TO_GENRE[tok]
    if not gk then
        unmatched = unmatched + 1
        print(('   %-22s n=%d'):format(tok, genre_n[tok]))
    elseif not RB3_GENRES[gk] then
        unmatched = unmatched + 1
        print(('   %-22s n=%d  -> maps to %s, which is NOT in RB3_GENRES'):format(tok, genre_n[tok], gk))
    end
end
if unmatched == 0 then print('   (none)') end

----------------------------------------------------------------------
print('\n-- Supported genres the catalogue never uses')
local seen_genre = {}
for tok in pairs(genre_n) do
    local gk = TOKEN_TO_GENRE[tok]
    if gk then seen_genre[gk] = true end
end
local missing = {}
for _, gk in ipairs(RB3_GENRE_ORDER) do
    if not seen_genre[gk] then missing[#missing + 1] = RB3_GENRES[gk].label end
end
print('   ' .. (#missing > 0 and table.concat(missing, ', ') or '(none)'))

----------------------------------------------------------------------
print('\n-- Pairs, by frequency')
local pk_sorted = SortedKeys(pair_n)
table.sort(pk_sorted, function(a, b)
    if pair_n[a] ~= pair_n[b] then return pair_n[a] > pair_n[b] end
    return a < b
end)
for _, pk in ipairs(pk_sorted) do
    print(('   %-42s %d'):format(pk, pair_n[pk]))
end

----------------------------------------------------------------------
-- The flag list. Sorted so the ones crossing a major genre come first: those are the
-- calls most likely to disagree with a mapping decision.
print('\n-- Artists filed under more than one pair')
print('   Check each against the release dates and the era column before concluding')
print('   anything: a band that changed style and a convention that changed between')
print('   games look identical here.')

local multi = {}
for artist, pairs_ in pairs(artists) do
    local n, majors = 0, {}
    for pk in pairs(pairs_) do
        n = n + 1
        majors[pk:match('^(.-) / ')] = true
    end
    if n > 1 then
        local nm = 0
        for _ in pairs(majors) do nm = nm + 1 end
        multi[#multi + 1] = { artist = artist, pairs = pairs_, n = n, majors = nm }
    end
end
table.sort(multi, function(a, b)
    if a.majors ~= b.majors then return a.majors > b.majors end
    if a.n ~= b.n then return a.n > b.n end
    return a.artist < b.artist
end)

local total_artists = 0
for _ in pairs(artists) do total_artists = total_artists + 1 end
print(('   %d of %d artists with subgenre data are multi-filed.\n'):format(#multi, total_artists))

for _, m in ipairs(multi) do
    print(('   %s   [%s]'):format(m.artist,
        m.majors > 1 and 'DIFFERENT MAJOR GENRE' or 'same major, different subgenre'))
    for _, pk in ipairs(SortedKeys(m.pairs)) do
        local songs_ = m.pairs[pk]
        table.sort(songs_)
        local shown = {}
        for i = 1, math.min(#songs_, 4) do shown[i] = songs_[i] end
        if #songs_ > 4 then shown[#shown + 1] = ('... +%d more'):format(#songs_ - 4) end
        print(('      %-34s %s'):format(pk, table.concat(shown, ', ')))
    end
    print('')
end
