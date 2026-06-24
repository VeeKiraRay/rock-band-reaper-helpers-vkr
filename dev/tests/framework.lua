-- Minimal in-REAPER test framework.
-- Defines Test global with: Test.section, Test.it, Test.expect, Test.report.
-- Results are written to the REAPER console (View > Show REAPER console).

Test = { _pass = 0, _fail = 0 }

function Test.section(name)
    r.ShowConsoleMsg('\n-- ' .. name .. '\n')
end

function Test.it(name, fn)
    local ok, err = pcall(fn)
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
