-- Tests for the pure half of lib/reaper_helper_ui.lua: what the footer's Copy
-- result button puts on the clipboard. Drawing (DrawHelperFooter,
-- DrawResultPanel, HelperFooterHeight) needs an ImGui context and is checked in
-- REAPER by hand.
--
-- Requires globals: Test, HelperCopyText, MakeProjectPoll, r (run_helper_ui.lua).

------------------------------------------------------------------
Test.section('Helper footer: Copy result text')

Test.it('status and result are joined with a blank line', function()
    local t = HelperCopyText('Done.', 'line 1\nline 2')
    Test.expect(t == 'Done.\n\nline 1\nline 2', 'got ' .. tostring(t))
end)

Test.it('no result means nothing to copy (button disabled)', function()
    Test.expect(HelperCopyText('Done.', nil) == nil, 'nil result should give nil')
    Test.expect(HelperCopyText('Done.', '') == nil, 'empty result should give nil')
end)

Test.it('an empty status copies the result alone', function()
    Test.expect(HelperCopyText('', 'only result') == 'only result', 'empty status')
    Test.expect(HelperCopyText(nil, 'only result') == 'only result', 'nil status')
end)

Test.it('tab-column result lines are copied as they are', function()
    local t = HelperCopyText('OK', 'Notes\t12')
    Test.expect(t == 'OK\n\nNotes\t12', 'got ' .. tostring(t))
end)

------------------------------------------------------------------
Test.section('MakeProjectPoll timing (stubbed clock and change count)')

-- The track lists in every window rebuild through MakeProjectPoll(1.0, 5.0).
-- These cases drive it with a fake clock and change counter, so the timing
-- rules are checked without waiting on REAPER (venue_events.lua covers the
-- real REAPER calls).
local function WithFakeReaper(fn)
    local real_time, real_count = r.time_precise, r.GetProjectStateChangeCount
    local clock, count = 100.0, 1
    r.time_precise = function() return clock end
    r.GetProjectStateChangeCount = function() return count end
    local ok, err = pcall(fn, function(dt) clock = clock + dt end,
                              function() count = count + 1 end)
    r.time_precise, r.GetProjectStateChangeCount = real_time, real_count
    if not ok then error(err, 0) end
end

Test.it('first call fires, a quiet project does not', function()
    WithFakeReaper(function(advance)
        local poll = MakeProjectPoll(1.0, 5.0)
        Test.expect(poll() == true, 'first call')
        advance(2.0)
        Test.expect(poll() == false, 'no edit, inside fallback')
    end)
end)

Test.it('an edit fires only once min_secs has passed', function()
    WithFakeReaper(function(advance, edit)
        local poll = MakeProjectPoll(1.0, 5.0)
        poll()
        edit(); advance(0.5)
        Test.expect(poll() == false, 'edit held back inside min_secs')
        advance(0.6)
        Test.expect(poll() == true, 'edit fires after min_secs')
        advance(0.1)
        Test.expect(poll() == false, 'nothing new since')
    end)
end)

Test.it('fallback re-reads with no edit, force always fires', function()
    WithFakeReaper(function(advance)
        local poll = MakeProjectPoll(1.0, 5.0)
        poll()
        advance(5.0)
        Test.expect(poll() == true, 'fallback_secs elapsed')
        Test.expect(poll(true) == true, 'forced')
        Test.expect(poll() == false, 'quiet right after force')
    end)
end)
