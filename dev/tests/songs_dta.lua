-- Unit tests for dev/calibration/songs_dta.lua: ParseSongsDta, DtaRank,
-- SongMidiRelPath.
--
-- Pure - literal dta text in, records out. The parser is also validated against
-- all 63 real corpus files (155 entries, counts cross-checked against an
-- independent scan), so what these tests are for is the REGRESSION risks: the
-- specific shapes in those files that a reasonable-looking parser gets wrong.
-- Each case below corresponds to something actually present in the corpus.

local function Lines(t) return table.concat(t, '\n') end

----------------------------------------------------------------------
Test.section('ParseSongsDta - entry splitting')

Test.it('a single-song pack yields one entry with its shortname', function()
    local e = ParseSongsDta(Lines({
        '(iwantitall2',
        '   (name "I Want It All")',
        '   (rank',
        '      (guitar 351)',
        '   )',
        '   (game_origin rb3_dlc)',
        ')',
    }))
    Test.expect(#e == 1, 'one entry; got ' .. #e)
    Test.expect(e[1].shortname == 'iwantitall2', 'shortname; got ' .. tostring(e[1].shortname))
end)

Test.it('a multi-song pack yields every entry, not just the first', function()
    -- 103 of the corpus's 155 songs live in multi-song packs, so this is the
    -- difference between reading the corpus and reading a third of it.
    local e = ParseSongsDta(Lines({
        '(songone',
        '   (rank (guitar 100))',
        '   (game_origin rb3_dlc)',
        ')',
        '(songtwo',
        '   (rank',
        '      (guitar 200)',
        '   )',
        '   (game_origin rb3_dlc)',
        ')',
        '(songthree',
        '   (rank',
        '      (guitar 300)',
        '   )',
        ')',
    }))
    Test.expect(#e == 3, 'three entries; got ' .. #e)
    Test.expect(e[2].shortname == 'songtwo', 'second entry')
    Test.expect(e[3].ranks.guitar == 300, 'third entry ranks parsed')
end)

Test.it('shortnames containing digits are read whole', function()
    local e = ParseSongsDta('(wewillrockyou1\n   (rank\n      (bass 096)\n   )\n)')
    Test.expect(e[1].shortname == 'wewillrockyou1', 'got ' .. tostring(e[1].shortname))
end)

----------------------------------------------------------------------
Test.section('ParseSongsDta - rank scoping (the (bass 5) trap)')

Test.it('a bare channel index inside (tracks) is not read as a rank', function()
    -- Verbatim shape from the American Idiot dta: a single-channel track
    -- written "(bass 5)" instead of "(bass (5))". A whole-file match reads
    -- that as a rank of 5, which is how a first pass produced 53 bass values
    -- for 52 songs.
    local e = ParseSongsDta(Lines({
        '(americanidiot',
        '   (song',
        '     (tracks',
        '        ((drum (0 1 2 3 4))',
        '         (bass 5)',
        '         (guitar (6 7))',
        '        )',
        '     )',
        '   )',
        '   (rank',
        '      (drum 301)',
        '      (bass 202)',
        '   )',
        '   (game_origin greenday)',
        ')',
    }))
    Test.expect(#e == 1, 'one entry')
    Test.expect(e[1].ranks.bass == 202,
        'bass rank is the rank-block value, not the channel; got ' .. tostring(e[1].ranks.bass))
end)

Test.it('the rank block closes on its own bare paren', function()
    local e = ParseSongsDta(Lines({
        '(song',
        '   (rank',
        '      (guitar 250)',
        '   )',
        '   (solo (guitar))',
        '   (vocal_parts 3)',
        ')',
    }))
    Test.expect(e[1].ranks.guitar == 250, 'rank read')
    Test.expect(e[1].vocal_parts == 3, 'fields after the block still parsed')
end)

----------------------------------------------------------------------
Test.section('ParseSongsDta - field variance across real files')

Test.it('game_origin is picked up even though it follows the rank block', function()
    local e = ParseSongsDta(Lines({
        '(song',
        '   (rank',
        '      (guitar 100)',
        '   )',
        '   (game_origin lego)',
        ')',
    }))
    Test.expect(e[1].origin == 'lego', 'got ' .. tostring(e[1].origin))
end)

Test.it('indentation and optional fields vary without breaking parsing', function()
    -- The Green Day dta indents with 5 spaces and pads (name ...); others use 6
    -- and do not. Nothing may key off spacing.
    local e = ParseSongsDta(Lines({
        '(song',
        '     (context 1116)',
        '     (name        "Padded")',
        '        (rank',
        '              (guitar 175)',
        '        )',
        ')',
    }))
    Test.expect(e[1].ranks.guitar == 175, 'got ' .. tostring(e[1].ranks.guitar))
end)

Test.it('absent rank keys are simply absent, not zero-valued', function()
    -- The Green Day export carries no keys/real_* lines at all.
    local e = ParseSongsDta(Lines({
        '(song',
        '   (rank',
        '      (drum 301)',
        '      (guitar 235)',
        '   )',
        ')',
    }))
    Test.expect(e[1].ranks.keys == nil, 'keys key absent')
    Test.expect(DtaRank(e[1], 'keys') == nil, 'DtaRank reports no part')
end)

Test.it('vocal_parts may be missing (2 corpus songs with a vocals rank lack it)', function()
    local e = ParseSongsDta('(song\n   (rank\n      (vocals 288)\n   )\n)')
    Test.expect(e[1].vocal_parts == nil, 'nil, not an error')
    Test.expect(DtaRank(e[1], 'vocals') == 288, 'vocals rank still read')
end)

Test.it('no sub_genre field is present anywhere in the corpus, and nil is fine', function()
    local e = ParseSongsDta('(song\n   (genre metal)\n)')
    Test.expect(e[1].genre == 'metal', 'genre read')
    Test.expect(e[1].sub_genre == nil, 'sub_genre nil')
end)

-- Every Magma template pack ships 26 copies of ";;(sub_genre ^^^garage^^^)", so a
-- comment-blind parser would report `garage` as the corpus's commonest subgenre.
Test.it('a commented-out genre or sub_genre is not read as a value', function()
    local e = ParseSongsDta(
        '(song\n   (genre metal)\n   ;;(sub_genre ^^^garage^^^)  ; OPTIONAL\n)')
    Test.expect(e[1].genre == 'metal', 'real genre still read')
    Test.expect(e[1].sub_genre == nil, 'commented sub_genre must stay nil')

    local e2 = ParseSongsDta('(song\n   ;;(genre rock)\n   (sub_genre psychedelicrock)\n)')
    Test.expect(e2[1].genre == nil, 'commented genre must stay nil')
    Test.expect(e2[1].sub_genre == 'psychedelicrock', 'an uncommented sub_genre is read')
end)

----------------------------------------------------------------------
Test.section('DtaRank - zero means no part')

Test.it('a zero rank reads as no part', function()
    local e = ParseSongsDta('(song\n   (rank\n      (keys 0)\n      (guitar 223)\n   )\n)')
    Test.expect(DtaRank(e[1], 'keys') == nil, 'zero -> nil')
    Test.expect(DtaRank(e[1], 'guitar') == 223, 'non-zero passes through')
end)

Test.it('every documented rank key is recognised, drum singular included', function()
    local body = { '(song', '   (rank' }
    for i, k in ipairs(DTA_RANK_KEYS) do body[#body + 1] = ('      (%s %d)'):format(k, 100 + i) end
    body[#body + 1] = '   )'
    body[#body + 1] = ')'
    local e = ParseSongsDta(Lines(body))
    for i, k in ipairs(DTA_RANK_KEYS) do
        Test.expect(DtaRank(e[1], k) == 100 + i, 'rank key ' .. k)
    end
    Test.expect(e[1].ranks.drums == nil, 'the key is "drum", not "drums"')
end)

----------------------------------------------------------------------
Test.section('SongMidiRelPath')

Test.it('builds the path from the shortname rather than globbing', function()
    Test.expect(SongMidiRelPath('freakonaleash') == 'Root/songs/freakonaleash/freakonaleash.mid',
        'got ' .. SongMidiRelPath('freakonaleash'))
end)
