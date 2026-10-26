-- MIDI fixture tests for the General Helper (Venue).
--
-- Each test imports a real MIDI fixture, points S indices at the loaded tracks,
-- calls one action, asserts on S.status, then deletes the fixture tracks.
-- Actions that have preview mode are run in preview so nothing is written permanently.

local _S0 = {}
for k, v in pairs(S) do _S0[k] = v end

local function reset()
    for k, v in pairs(_S0) do S[k] = v end
    S.status      = 'Ready.'
    S.last_result = nil
end

----------------------------------------------------------------------
-- Venue - rb_venue_events.mid (EVENTS + VENUE tracks, no instrument awareness data)
-- Venue actions locate tracks by name via FindTrackByName, not S index.
----------------------------------------------------------------------
Test.section('Venue - rb_venue_events.mid (always-playing fallback)')

Test.it('ListVenueEvents: reads VENUE track and reports events', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    Test.expect(n > 0, 'rb_venue_events.mid created no tracks')
    ListVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ListVenueEvents did not update S.status')
end)

Test.it('ListEventSections: reads [prc_*] markers from EVENTS track', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    ListEventSections()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'ListEventSections did not update S.status')
end)

Test.it('GenerateVenueEvents: generates events; instruments default to always-playing', function()
    reset()
    local base, n = LoadFixture('rb_venue_events.mid')
    GenerateVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'GenerateVenueEvents did not update S.status')
    Test.expect(not S.status:find('^Error'), 'GenerateVenueEvents errored: ' .. S.status)
end)

----------------------------------------------------------------------
-- Venue with awareness - rb_venue_all_references.mid
-- Contains PART DRUMS/GUITAR/BASS/etc. with [idle] and [play] text events.
-- GenerateVenueEvents uses these to weight camera shot selection per instrument.
----------------------------------------------------------------------
Test.section('Venue - rb_venue_all_references.mid (with idle/play awareness)')

Test.it('GenerateVenueEvents: weights cameras using instrument play states', function()
    reset()
    local base, n = LoadFixture('rb_venue_all_references.mid')
    Test.expect(n > 0, 'rb_venue_all_references.mid created no tracks')
    GenerateVenueEvents()
    CleanupFixture(base)
    Test.expect(S.status ~= 'Ready.', 'GenerateVenueEvents did not update S.status')
    Test.expect(not S.status:find('^Error'), 'GenerateVenueEvents errored: ' .. S.status)
end)
