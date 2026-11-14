-- Directed Moves window: the generated data (lib/reaper_venue_shots.lua) and its queries
-- (lib/reaper_venue_shots_query.lua). The expected facts are the ones the data was read
-- for (camera research of all 44 venues): the game's style / gender filter, the lineup
-- remaps, and the one cut that never plays.

local E = RB_VENUE_SHOTS.events

Test.section('Data shape')

Test.it('has the five venue kinds, the directed cuts and only the coop remaps', function()
    Test.expect(#RB_VENUE_SHOTS.kinds == 5, 'kinds')
    Test.expect(RB_VENUE_SHOTS.venues_per_kind.arena == 9, 'arenas')
    Test.expect(#VenueShotEvents('directed') >= 40, 'directed events: ' .. #VenueShotEvents('directed'))
    Test.expect(#VenueShotEvents('coop') == 0, 'coop shots are not listed')
    Test.expect(#VenueShotEvents() == #VenueShotEvents('directed'), 'every listed event is directed')
    Test.expect(RB_VENUE_SHOTS.coop_remap.coop_k_near ~= nil, 'coop remaps kept')
    Test.expect(RB_VENUE_SHOTS_SCHEMA == 1, 'schema')
end)

Test.it('every move row is complete', function()
    local bad
    for cat, ev in pairs(E) do
        for _, row in ipairs(ev.moves or {}) do
            local ok = row.label ~= '' and #row.kinds > 0 and row.variants >= 1
                and row.gender:match('^[MFB]$') and row.styles:match('^[RDBS]+$')
                and row.lead[1] <= row.lead[2]
            if not ok then bad = cat .. ' / ' .. tostring(row.label) end
        end
    end
    Test.expect(not bad, 'incomplete row: ' .. tostring(bad))
end)

Test.it('directed events carry a length range', function()
    Test.expect(E.directed_drums.length[1] < E.directed_drums.length[2], 'drums length')
end)

Test.it('coop remaps: singles go to band shots, duos to the partner, band shots never change', function()
    local s = VenueShotRemap('coop_g_near', 'no_guitar')
    Test.expect(type(s) == 'table' and #s == 3 and s[1]:find('^coop_all_') ~= nil, 'single -> band shots')
    local d = VenueShotRemap('coop_bk_near', 'no_keys')
    Test.expect(type(d) == 'table' and #d == 1 and d[1] == 'coop_b_near', 'duo -> partner')
    for _, lu in ipairs({ 'no_keys', 'no_guitar', 'no_bass' }) do
        Test.expect(VenueShotRemap('coop_all_far', lu) == nil, 'band shot ' .. lu)
    end
end)

Test.it('no lead-in is longer than its event allows', function()
    for cat, ev in pairs(E) do
        for _, row in ipairs(ev.moves or {}) do
            Test.expect(row.lead[2] <= ev.lead[2] + 1e-6, cat .. ' ' .. row.label)
        end
    end
end)

Test.it('shots with no focus move are described by what they show (crowd, group moves)', function()
    local by_label = {}
    for _, row in ipairs(E.directed_crowd.moves) do by_label[row.label] = row end
    local front_row = by_label['Crowd: front row']
    Test.expect(front_row and VenueShotKindsText(front_row.kinds) == 'Big club, Small club',
        'front row crowd shot in big and small clubs (the PS3 copy of the object is the same shot)')
    Test.expect(by_label['Crowd: whole crowd'] and by_label['Crowd: whole crowd'].kinds[1] == 'small_club',
        'whole-crowd shot in small clubs')
    Test.expect(by_label['Crowd: front center'] and by_label['Crowd: front center'].kinds[1] == 'arena',
        'front center crowd shot in arenas')
    Test.expect(by_label['Band extreme close-ups'] ~= nil, 'video crowd cut = band close-ups')
    local group = false
    for _, row in ipairs(E.directed_duo_gb.moves) do
        if row.who == 'guitar+bass' then group = true end
    end
    Test.expect(group, 'duo_gb has rows where guitar and bass both move')
end)

Test.section('Filter (the game\'s rules)')

local function Count(cat, filter)
    local n = 0
    for _, row in ipairs(E[cat].moves or {}) do
        if VenueShotRowMatches(row, filter, E[cat]) then n = n + 1 end
    end
    return n
end

Test.it('free cuts play for every style and gender', function()
    Test.expect(E.directed_crowd.free, 'directed_crowd is free')
    for _, g in ipairs({ 'M', 'F' }) do
        for _, s in ipairs({ 'R', 'D', 'B', 'S' }) do
            Test.expect(Count('directed_crowd', { gender = g, style = s }) == #E.directed_crowd.moves,
                g .. s)
        end
    end
end)

Test.it('a gender / style filter keeps only rows tagged for it', function()
    local all = Count('directed_guitar', {})
    local some = Count('directed_guitar', { gender = 'F', style = 'D' })
    Test.expect(some > 0 and some < all, ('female dramatic %d of %d'):format(some, all))
end)

Test.it('every directed event has a move for every gender and style (all five on stage)', function()
    local gaps = {}
    for _, cat in ipairs(VenueShotEvents('directed')) do
        for _, g in ipairs({ 'M', 'F' }) do
            for _, s in ipairs({ 'R', 'D', 'B', 'S' }) do
                if Count(cat, { gender = g, style = s }) == 0 then gaps[#gaps + 1] = cat .. ' ' .. g .. s end
            end
        end
    end
    Test.expect(#gaps == 0, 'gaps: ' .. table.concat(gaps, ', '))
end)

Test.it('directed_keys_np has no playable move in any arena', function()
    Test.expect(Count('directed_keys_np', { kind = 'arena' }) == 0, 'arena keys_np')
    Test.expect(Count('directed_keys_np', { kind = 'big_club' }) > 0, 'big club keys_np')
end)

Test.it('directed_all in arenas: a band with keys and a female keyboardist gets none', function()
    -- arena_11's extra variant fits every band, so the kind still has one row that plays;
    -- the rows tagged for the keys lineups are the keyboardist's, male only, plus that one.
    local female = 0
    for _, row in ipairs(E.directed_all.moves) do
        if VenueShotRowMatches(row, { kind = 'arena', lineup = 'no_guitar', gender = 'F' }, E.directed_all)
                and row.who == 'keys' then
            female = female + 1
        end
    end
    Test.expect(female == 0, 'female keyboardist rows: ' .. female)
end)

Test.section('Lineup remaps')

Test.it('without keys: keys directed cuts are dropped, keys duo shots fall to the partner', function()
    Test.expect(VenueShotRemap('directed_keys', 'no_keys') == 'dropped', 'directed_keys')
    local r = VenueShotRemap('coop_bk_near', 'no_keys')
    Test.expect(type(r) == 'table' and r[1] == 'coop_b_near', 'coop_bk_near -> ' .. tostring(r and r[1]))
    Test.expect(VenueShotRemap('directed_guitar', 'no_keys') == nil, 'guitar unchanged without keys')
end)

Test.it('without guitar: guitar directed cuts are dropped', function()
    Test.expect(VenueShotRemap('directed_guitar', 'no_guitar') == 'dropped', 'directed_guitar')
end)

Test.section('Keyword search')

Test.it('"kiss" finds the kiss move under its camera event', function()
    local res, total = VenueShotSearch('kiss', 10)
    Test.expect(total >= 1 and #res >= 1, 'no result')
    local found = false
    for _, sec in ipairs(res) do
        for _, row in ipairs(sec.rows) do
            if row.label:lower():find('kiss', 1, true) then found = true end
        end
    end
    Test.expect(found, 'kiss row')
end)

Test.it('an event name lists all its moves; the limit caps the sections', function()
    local res = VenueShotSearch('directed_drums', 10)
    local sec
    for _, s in ipairs(res) do if s.cat == 'directed_drums' then sec = s end end
    Test.expect(sec and #sec.rows == #E.directed_drums.moves, 'all drums moves')
    local capped, total = VenueShotSearch('jump', 3)
    Test.expect(#capped == 3 and total > 3, ('jump: %d shown of %d'):format(#capped, total))
end)

Test.it('every word must match; no words, no result', function()
    Test.expect(#VenueShotSearch('kiss zebra', 10) == 0, 'two words')
    Test.expect(#VenueShotSearch('   ', 10) == 0, 'blank')
end)

Test.it('kinds text marks partial kinds', function()
    Test.expect(VenueShotKindsText({ 'arena', 'big_club*' }) == 'Arena, Big club*', 'text')
end)

Test.section('Row click (competing moves)')

Test.it('a row pins only the filters it allows one value for', function()
    local f = VenueShotRowFilter({ styles = 'D', gender = 'F', kinds = { 'arena*' } }, {})
    Test.expect(f.style == 'D' and f.gender == 'F' and f.kind == 'arena',
        ('one of each: %s %s %s'):format(tostring(f.style), tostring(f.gender), tostring(f.kind)))
    f = VenueShotRowFilter({ styles = 'RDBS', gender = 'B', kinds = { 'arena', 'video' } }, {})
    Test.expect(not f.style and not f.gender and not f.kind, 'open row pins nothing')
    f = VenueShotRowFilter({ styles = 'D', gender = 'F', kinds = { 'arena' } }, { free = true })
    Test.expect(not f.style and not f.gender and f.kind == 'arena', 'free cut: style and gender stay Any')
end)

Test.it('the kiss move plays under the filter its click sets', function()
    local res = VenueShotSearch('kiss', 10)
    local n = 0
    for _, sec in ipairs(res) do
        local ev = VenueShotEvent(sec.cat)
        for _, row in ipairs(sec.rows) do
            n = n + 1
            Test.expect(VenueShotRowMatches(row, VenueShotRowFilter(row, ev), ev), sec.cat .. ' ' .. row.label)
        end
    end
    Test.expect(n > 0, 'kiss rows')
end)

Test.it('group focus is shortened to letters, one member stays spelled out', function()
    Test.expect(VenueShotWhoShort('vocals+guitar+bass') == 'V+G+B', VenueShotWhoShort('vocals+guitar+bass'))
    Test.expect(VenueShotWhoShort('guitar') == 'guitar', 'single')
    Test.expect(VenueShotWhoShort('crowd') == 'crowd', 'crowd')
end)

Test.section('Kinds text')

Test.it('kinds text says All only when every kind has it in all its venues', function()
    local all = {}
    for _, k in ipairs(RB_VENUE_SHOTS.kinds) do all[#all + 1] = k end
    Test.expect(VenueShotKindsText(all) == 'All', 'all five: ' .. VenueShotKindsText(all))
    all[1] = all[1] .. '*'
    Test.expect(VenueShotKindsText(all) ~= 'All', 'one partial kind is listed')
end)
