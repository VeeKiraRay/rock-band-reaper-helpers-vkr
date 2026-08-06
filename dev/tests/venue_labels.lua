-- Venue camera label-table coverage.
-- Guards COOP_LABELS / DIRECTED_LABELS (venue_camera.lua) against the two ways a
-- label table silently rots: an event added to a pool with no label added beside it
-- (the combo falls back to the raw name and one row reads differently from the rest),
-- and a mistyped key that leaves an orphan label nothing ever looks up.
-- Also checks the dev demo's mirrored copies still cover the same events - the demo
-- and dev/venue_sprite_tester_vkr.lua load dev/rock_band_venue_demo_vkr/defaults.lua,
-- not venue_camera.lua, so the mirror is a real drift risk.
--
-- Also covers RawVenueEventText (venue_sprites.lua), the other half of the same
-- promise: a label may hide the raw name in the combo, but the tooltip's last line
-- and the Add button both come from that one function, so they cannot disagree.
--
-- And the combo display order (COOP_DISPLAY_GROUPS / DIRECTED_DISPLAY /
-- LIGHTING_DISPLAY_GROUPS / POSTPROC_DISPLAY): these are sorted views over the pools,
-- so the thing worth guarding is that a view never drops, duplicates or mis-files an
-- entry - a combo missing one shot is invisible until someone goes looking for it.
--
-- Requires globals: Test, LBL_MAIN, LBL_DEMO, RawVenueEventText
-- (all set up by run_venue_labels.lua).

local function Bare(ev) return ev:match('^%[(.-)%]$') or ev end

-- Manual gen appends these two to its own list (ui_venue_manual.lua) - they are
-- excluded from DIRECTED_POOL because auto-gen must never pick a BRE cut, but they
-- are still offered by hand and so still need labels.
local DIRECTED_EXTRA = { 'directed_bre', 'directed_brej' }

local function PoolNames(pool, extra)
    local names = {}
    for _, ev in ipairs(pool) do names[#names + 1] = Bare(ev) end
    for _, n in ipairs(extra or {}) do names[#names + 1] = n end
    return names
end

local function Join(list)
    table.sort(list)
    return table.concat(list, ', ')
end

-- Every pool event resolves to a label.
local function CheckCovered(what, names, labels)
    Test.it(what .. ': every event has a label', function()
        local missing = {}
        for _, n in ipairs(names) do
            if not labels[n] then missing[#missing + 1] = n end
        end
        Test.expect(#missing == 0, 'no label for: ' .. Join(missing))
    end)
end

-- No label key that no pool event ever looks up (catches a typo in the table).
local function CheckNoOrphans(what, names, labels)
    Test.it(what .. ': no orphan label keys', function()
        local known = {}
        for _, n in ipairs(names) do known[n] = true end
        local orphans = {}
        for k in pairs(labels) do
            if not known[k] then orphans[#orphans + 1] = k end
        end
        Test.expect(#orphans == 0, 'label with no matching event: ' .. Join(orphans))
    end)
end

-- Two events showing the same text in the combo is always a copy/paste slip.
local function CheckUnique(what, labels)
    Test.it(what .. ': labels are unique', function()
        local seen  = {}
        local dupes = {}
        for k, v in pairs(labels) do
            if seen[v] then dupes[#dupes + 1] = v .. ' (' .. seen[v] .. ' / ' .. k .. ')' end
            seen[v] = k
        end
        Test.expect(#dupes == 0, 'duplicate label: ' .. Join(dupes))
    end)
end

-- ---------------------------------------------------------------------------

Test.section('Camera label coverage (venue_camera.lua)')

local coop_names = PoolNames(LBL_MAIN.coop_pool)
local dir_names  = PoolNames(LBL_MAIN.dir_pool, DIRECTED_EXTRA)

CheckCovered  ('COOP_LABELS',     coop_names, LBL_MAIN.coop)
CheckNoOrphans('COOP_LABELS',     coop_names, LBL_MAIN.coop)
CheckUnique   ('COOP_LABELS',                 LBL_MAIN.coop)

CheckCovered  ('DIRECTED_LABELS', dir_names,  LBL_MAIN.dir)
CheckNoOrphans('DIRECTED_LABELS', dir_names,  LBL_MAIN.dir)
CheckUnique   ('DIRECTED_LABELS',             LBL_MAIN.dir)

Test.section('Camera label style')

-- A label is the whole point of the table: none of them may leak the raw event
-- name's shape (a stray coop_/directed_ prefix or an unconverted underscore).
Test.it('no label leaks raw event syntax', function()
    local bad = {}
    for _, labels in ipairs({ LBL_MAIN.coop, LBL_MAIN.dir }) do
        for k, v in pairs(labels) do
            if v:find('_') or v:find('coop', 1, true) or v:find('directed', 1, true) then
                bad[#bad + 1] = k .. '="' .. v .. '"'
            end
        end
    end
    Test.expect(#bad == 0, 'raw-looking label: ' .. Join(bad))
end)

-- Coop labels are all "Subject (Variation)" - every coop event has a view suffix.
Test.it('every coop label is "Subject (Variation)"', function()
    local bad = {}
    for k, v in pairs(LBL_MAIN.coop) do
        if not v:match('^%u[%w%s/%-]* %(%u[%w%s%-]+%)$') then
            bad[#bad + 1] = k .. '="' .. v .. '"'
        end
    end
    Test.expect(#bad == 0, 'unexpected shape: ' .. Join(bad))
end)

Test.section('Raw event text (venue_sprites.lua)')

-- RawVenueEventText is what both the tooltip's last line and Manual gen's Add button
-- use, so these cases are the contract "what you hovered is what gets written".
Test.it('camera: bare name in brackets', function()
    Test.expect(RawVenueEventText('Camera', 'coop_all_far') == '[coop_all_far]',
        'got ' .. tostring(RawVenueEventText('Camera', 'coop_all_far')))
    Test.expect(RawVenueEventText('Camera', 'directed_all_lt') == '[directed_all_lt]',
        'got ' .. tostring(RawVenueEventText('Camera', 'directed_all_lt')))
end)

Test.it('lighting: name wrapped in [lighting (...)]', function()
    Test.expect(RawVenueEventText('Lighting', 'verse') == '[lighting (verse)]',
        'got ' .. tostring(RawVenueEventText('Lighting', 'verse')))
end)

Test.it('postproc: .pp kept, not doubled', function()
    Test.expect(RawVenueEventText('PostProc', 'ProFilm_a.pp') == '[ProFilm_a.pp]',
        'got ' .. tostring(RawVenueEventText('PostProc', 'ProFilm_a.pp')))
end)

Test.it('nothing selected returns nil', function()
    Test.expect(RawVenueEventText('Camera', '') == nil, "'' should give nil")
    Test.expect(RawVenueEventText('Camera', nil) == nil, 'nil should give nil')
    Test.expect(RawVenueEventText('Lighting', '') == nil, "'' should give nil (Lighting)")
end)

-- Against real data: a camera event must round-trip to the pool string it came from,
-- and every lighting/postproc name must land on an event the validator accepts.
Test.it('every camera pool entry round-trips', function()
    local bad = {}
    for _, pool in ipairs({ LBL_MAIN.coop_pool, LBL_MAIN.dir_pool }) do
        for _, ev in ipairs(pool) do
            local got = RawVenueEventText('Camera', Bare(ev))
            if got ~= ev then bad[#bad + 1] = ev .. ' -> ' .. tostring(got) end
        end
    end
    Test.expect(#bad == 0, Join(bad))
end)

Test.it('every lighting/postproc name maps into VENUE_VALID', function()
    local bad = {}
    for _, n in ipairs(LBL_MAIN.lighting_names) do
        local got = RawVenueEventText('Lighting', n)
        if not LBL_MAIN.venue_valid[got] then bad[#bad + 1] = tostring(got) end
    end
    for _, n in ipairs(LBL_MAIN.postproc_names) do
        local got = RawVenueEventText('PostProc', n)
        if not LBL_MAIN.venue_valid[got] then bad[#bad + 1] = tostring(got) end
    end
    Test.expect(#bad == 0, 'not a valid VENUE event: ' .. Join(bad))
end)

Test.section('Combo display order')

-- Set equality both ways, plus a count check so a duplicated entry (which a set
-- comparison alone would hide) still fails.
local function CheckSameContents(what, got, want)
    Test.it(what .. ': same entries as the pool', function()
        local in_want = {}
        for _, v in ipairs(want) do in_want[v] = true end
        local in_got  = {}
        for _, v in ipairs(got)  do in_got[v]  = true end
        local diff = {}
        for v in pairs(in_want) do if not in_got[v]  then diff[#diff + 1] = v .. ' (missing)' end end
        for v in pairs(in_got)  do if not in_want[v] then diff[#diff + 1] = v .. ' (unexpected)' end end
        Test.expect(#diff == 0, Join(diff))
        Test.expect(#got == #want,
            ('%d entries displayed, %d in the pool - duplicate?'):format(#got, #want))
    end)
end

local function CheckSorted(what, names, labels, key_fn)
    Test.it(what .. ': alphabetical by label', function()
        local bad = {}
        for i = 1, #names - 1 do
            local ka = key_fn and key_fn(names[i])     or names[i]
            local kb = key_fn and key_fn(names[i + 1]) or names[i + 1]
            local la = (labels[ka] or ka):lower()
            local lb = (labels[kb] or kb):lower()
            if la > lb then bad[#bad + 1] = '"' .. la .. '" before "' .. lb .. '"' end
        end
        Test.expect(#bad == 0, 'out of order: ' .. Join(bad))
    end)
end

local function FlattenGroups(groups, field)
    local out = {}
    for _, g in ipairs(groups) do
        for _, v in ipairs(g[field]) do out[#out + 1] = v end
    end
    return out
end

-- Normal camera: three groups covering the whole pool, each sorted.
CheckSameContents('COOP_DISPLAY_GROUPS',
    FlattenGroups(LBL_MAIN.coop_groups, 'events'), LBL_MAIN.coop_pool)
for _, g in ipairs(LBL_MAIN.coop_groups) do
    CheckSorted('COOP_DISPLAY_GROUPS/' .. g.name, g.events, LBL_MAIN.coop, Bare)
end

Test.it('COOP_DISPLAY_GROUPS: groups match CategorizeCoopPool', function()
    local venue, solo, duo = CategorizeCoopPool(LBL_MAIN.coop_pool)
    local want = { Venue = {}, Solo = {}, Duo = {} }
    for _, ev in ipairs(venue) do want.Venue[ev] = true end
    for _, shots in pairs(solo) do for _, ev in ipairs(shots) do want.Solo[ev] = true end end
    for _, shots in pairs(duo)  do for _, ev in ipairs(shots) do want.Duo[ev]  = true end end
    local bad = {}
    for _, g in ipairs(LBL_MAIN.coop_groups) do
        for _, ev in ipairs(g.events) do
            if not (want[g.name] and want[g.name][ev]) then
                bad[#bad + 1] = ev .. ' filed under ' .. g.name
            end
        end
    end
    Test.expect(#bad == 0, Join(bad))
end)

-- Directed camera: alphabetical, BRE pinned outside the list by the UI.
CheckSameContents('DIRECTED_DISPLAY', LBL_MAIN.dir_display, PoolNames(LBL_MAIN.dir_pool))
CheckSorted('DIRECTED_DISPLAY', LBL_MAIN.dir_display, LBL_MAIN.dir)

Test.it('DIRECTED_DISPLAY: BRE cuts are pinned, not inline', function()
    for _, n in ipairs(LBL_MAIN.dir_display) do
        Test.expect(n ~= 'directed_bre' and n ~= 'directed_brej',
            n .. ' should be in DIRECTED_BRE_NAMES, not the sorted list')
    end
    local bre = LBL_MAIN.dir_bre
    Test.expect(#bre == 2 and bre[1] == 'directed_bre' and bre[2] == 'directed_brej',
        'DIRECTED_BRE_NAMES should be exactly the two BRE cuts')
end)

-- Lighting: two groups, and the Manual one has to be exactly the presets that need
-- keyframes - the whole reason the split survives alphabetising.
CheckSameContents('LIGHTING_DISPLAY_GROUPS',
    FlattenGroups(LBL_MAIN.lighting_groups, 'names'), LBL_MAIN.lighting_names)
for _, g in ipairs(LBL_MAIN.lighting_groups) do
    CheckSorted('LIGHTING_DISPLAY_GROUPS/' .. g.name, g.names, LBL_MAIN.lighting)
end

Test.it('LIGHTING_DISPLAY_GROUPS: Manual group is the keyframe presets', function()
    local manual
    for _, g in ipairs(LBL_MAIN.lighting_groups) do
        if g.name:find('Manual', 1, true) then manual = g.names end
    end
    Test.expect(manual, 'no Manual group found')
    local bad = {}
    for _, n in ipairs(manual) do
        if not LBL_MAIN.manual_set['[lighting (' .. n .. ')]'] then
            bad[#bad + 1] = n .. ' is not a manual preset'
        end
    end
    local n_manual = 0
    for _ in pairs(LBL_MAIN.manual_set) do n_manual = n_manual + 1 end
    Test.expect(#bad == 0, Join(bad))
    Test.expect(#manual == n_manual,
        ('Manual group has %d, MANUAL_LIGHTING_SET has %d'):format(#manual, n_manual))
end)

-- Post proc: the one place label order differs from the raw-name order.
CheckSameContents('POSTPROC_DISPLAY', LBL_MAIN.postproc_display, LBL_MAIN.postproc_names)
CheckSorted('POSTPROC_DISPLAY', LBL_MAIN.postproc_display, LBL_MAIN.postproc)

Test.it('POSTPROC_DISPLAY: "Sucky TV" sorts after "Space Woosh"', function()
    local i_sucky, i_space
    for i, n in ipairs(LBL_MAIN.postproc_display) do
        if n == 'shitty_tv.pp'   then i_sucky = i end
        if n == 'space_woosh.pp' then i_space = i end
    end
    Test.expect(i_sucky and i_space, 'both entries should be present')
    Test.expect(i_sucky > i_space,
        'label order should win over raw-name order for shitty_tv.pp')
end)

Test.section('Dev demo mirror (rock_band_venue_demo_vkr/defaults.lua)')

-- Pools first: the demo's own copies feed the sprite tester and the spritesheet
-- coverage test, so a pool that drifts from venue_camera.lua breaks those quietly.
local function CheckPoolParity(what, main_pool, demo_pool)
    Test.it(what .. ': demo pool matches venue_camera.lua', function()
        local in_main = {}
        for _, ev in ipairs(main_pool) do in_main[ev] = true end
        local in_demo = {}
        for _, ev in ipairs(demo_pool) do in_demo[ev] = true end
        local diff = {}
        for ev in pairs(in_main) do if not in_demo[ev] then diff[#diff + 1] = ev .. ' (missing from demo)' end end
        for ev in pairs(in_demo) do if not in_main[ev] then diff[#diff + 1] = ev .. ' (extra in demo)'    end end
        Test.expect(#diff == 0, Join(diff))
    end)
end

CheckPoolParity('COOP_POOL',     LBL_MAIN.coop_pool, LBL_DEMO.coop_pool)
CheckPoolParity('DIRECTED_POOL', LBL_MAIN.dir_pool,  LBL_DEMO.dir_pool)

-- Keys only, not values: the demo deliberately words some of its directed labels
-- differently (e.g. "Duo: Drums+Vocals" where the helper says "Duo Drums"), and it
-- is a throwaway generator, not the authoring UI. Coverage is what matters here.
CheckCovered('demo COOP_LABELS',     PoolNames(LBL_DEMO.coop_pool), LBL_DEMO.coop)
CheckCovered('demo DIRECTED_LABELS', PoolNames(LBL_DEMO.dir_pool),  LBL_DEMO.dir)
