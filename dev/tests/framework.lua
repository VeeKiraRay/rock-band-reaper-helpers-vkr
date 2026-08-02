-- Minimal in-REAPER test framework.
-- Defines Test global with: Test.section, Test.it, Test.expect, Test.report.
-- Results are written to the REAPER console (View > Show REAPER console).

-- Test.after (optional): a function run after every Test.it, pass or fail.
-- Set by suites whose tests mutate project state, so that a test which errors
-- part-way -- and therefore never reaches its own cleanup -- cannot leave that
-- state behind for the tests after it. Failures inside the hook are swallowed:
-- a broken teardown must not be reported as a test failure.
Test = { _pass = 0, _fail = 0, after = nil }

function Test.section(name)
    r.ShowConsoleMsg('\n-- ' .. name .. '\n')
end

function Test.it(name, fn)
    local ok, err = pcall(fn)
    if Test.after then pcall(Test.after) end
    if ok then
        Test._pass = Test._pass + 1
        r.ShowConsoleMsg('  PASS  ' .. name .. '\n')
    else
        Test._fail = Test._fail + 1
        r.ShowConsoleMsg('  FAIL  ' .. name .. '\n         ' .. tostring(err) .. '\n')
    end
end

function Test.expect(cond, msg)
    if not cond then error(msg or 'assertion failed', 2) end
end

function Test.report()
    local total = Test._pass + Test._fail
    if Test._fail > 0 then
        r.ShowConsoleMsg(string.format('\n%d/%d passed  (%d FAILED)\n', Test._pass, total, Test._fail))
    else
        r.ShowConsoleMsg(string.format('\n%d/%d passed\n', Test._pass, total))
    end
end
