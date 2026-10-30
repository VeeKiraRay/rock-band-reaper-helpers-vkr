-- Tests for midi_length_rules.lua (MIDI > Length's sustain rules). Pure: no project.
-- Values are the Difficulty > Generate / Validate rules, quarter notes.

local function near(a, b) return a and math.abs(a - b) < 1e-9 end

Test.section('MidiLengthKind')

Test.it('maps the instrument tracks and leaves the rest without rules', function()
    Test.expect(MidiLengthKind('PART GUITAR') == 'gb', 'PART GUITAR')
    Test.expect(MidiLengthKind('PART BASS') == 'gb', 'PART BASS')
    Test.expect(MidiLengthKind('PART KEYS') == 'k5', 'PART KEYS')
    local k, d = MidiLengthKind('PART REAL_KEYS_M')
    Test.expect(k == 'pk' and d == 'M', ('PART REAL_KEYS_M: %s %s'):format(tostring(k), tostring(d)))
    Test.expect(MidiLengthKind('PART DRUMS') == nil, 'PART DRUMS has no rules')
    Test.expect(MidiLengthKind('PART VOCALS') == nil, 'PART VOCALS has no rules')
    Test.expect(MidiLengthKind('PART KEYS_ANIM_RH') == nil, 'animation track has no rules')
end)

Test.section('MidiLengthGapQN')

Test.it('Guitar/Bass: 1/16 on Expert and Hard, dotted 1/8 / quarter, a step longer when fast', function()
    Test.expect(near(MidiLengthGapQN('gb', 'X', 120), 0.25), 'X 120')
    Test.expect(near(MidiLengthGapQN('gb', 'H', 200), 0.25), 'H 200')
    Test.expect(near(MidiLengthGapQN('gb', 'M', 120), 0.75), 'M 120')
    Test.expect(near(MidiLengthGapQN('gb', 'E', 120), 1.0), 'E 120')
    Test.expect(near(MidiLengthGapQN('gb', 'M', 160), 0.75), 'M at 160 is not fast')
    Test.expect(near(MidiLengthGapQN('gb', 'M', 161), 1.0), 'M 161')
    Test.expect(near(MidiLengthGapQN('gb', 'E', 161), 2.0), 'E 161')
end)

Test.it('Keys: a 1/8 after a chord on Expert and Hard only', function()
    Test.expect(near(MidiLengthGapQN('k5', 'H', 120, { 84 }, { 85 }), 0.25), 'H single')
    Test.expect(near(MidiLengthGapQN('k5', 'H', 120, { 84, 86 }, { 85 }), 0.5), 'H chord')
    Test.expect(near(MidiLengthGapQN('k5', 'X', 120, { 96, 98 }, { 97 }), 0.5), 'X chord')
    Test.expect(near(MidiLengthGapQN('k5', 'M', 120, { 72, 74 }, { 73 }), 0.75), 'M chord')
end)

Test.it('Pro Keys: Hard 1/16 for a simple change, 1/8 otherwise; Medium and Easy a quarter', function()
    Test.expect(near(MidiLengthGapQN('pk', 'H', 120, { 60 }, { 62 }), 0.25), 'single to single')
    Test.expect(near(MidiLengthGapQN('pk', 'H', 120, { 60 }, { 60, 64 }), 0.25), 'into a chord holding it')
    Test.expect(near(MidiLengthGapQN('pk', 'H', 120, { 60, 64 }, { 60, 64 }), 0.25), 'same chord')
    Test.expect(near(MidiLengthGapQN('pk', 'H', 120, { 60 }, { 62, 65 }), 0.5), 'into another chord')
    Test.expect(near(MidiLengthGapQN('pk', 'X', 120, { 60, 64 }, { 62, 65 }), 0.5), 'Expert as Hard')
    Test.expect(near(MidiLengthGapQN('pk', 'M', 200, { 60 }, { 62 }), 1.0), 'M any tempo')
    Test.expect(near(MidiLengthGapQN('pk', 'E', 90, { 60 }, { 62 }), 1.0), 'E any tempo')
end)

Test.section('MidiLengthTooShort')

Test.it('Expert: only the RBN 3/16 rule at 100+ BPM', function()
    Test.expect(MidiLengthTooShort('gb', 'X', 0.625, 120) == true, '5/32 at 120')
    Test.expect(MidiLengthTooShort('gb', 'X', 0.625, 90) == false, '5/32 at 90')
    Test.expect(MidiLengthTooShort('gb', 'X', 0.75, 120) == false, '3/16 at 120')
    Test.expect(MidiLengthTooShort('gb', 'X', 0.25, 120) == false, 'a plain note is not a sustain')
end)

Test.it('Guitar/Bass Hard: 3/16 at any tempo, 300 ms only with a note close behind', function()
    Test.expect(MidiLengthTooShort('gb', 'H', 0.625, 90) == true, '5/32 at 90')
    -- 1 QN at 250 BPM = 240 ms.
    Test.expect(MidiLengthTooShort('gb', 'H', 1.0, 250, 0.5) == true, '240 ms, next note close')
    Test.expect(MidiLengthTooShort('gb', 'H', 1.0, 250, 2.0) == false, '240 ms, room behind')
    Test.expect(MidiLengthTooShort('gb', 'H', 1.0, 250, nil) == false, '240 ms, nothing after')
end)

Test.it('Keys Hard: only the 3/16 rule at 100+ BPM', function()
    Test.expect(MidiLengthTooShort('k5', 'H', 0.625, 120) == true, '5/32 at 120')
    Test.expect(MidiLengthTooShort('k5', 'H', 0.625, 90) == false, '5/32 at 90')
    Test.expect(MidiLengthTooShort('k5', 'H', 1.0, 250, 0.5) == false, 'no ms floor on Keys')
end)

Test.it('Medium / Easy: dotted 1/8 (a quarter when fast) / a quarter', function()
    Test.expect(MidiLengthTooShort('gb', 'M', 0.625, 120) == true, 'M 5/32')
    Test.expect(MidiLengthTooShort('gb', 'M', 0.75, 120) == false, 'M 3/16')
    Test.expect(MidiLengthTooShort('gb', 'M', 0.75, 170) == true, 'M 3/16 when fast')
    Test.expect(MidiLengthTooShort('k5', 'E', 0.875, 120) == true, 'E 7/32')
    Test.expect(MidiLengthTooShort('k5', 'E', 1.0, 120) == false, 'E quarter')
end)

Test.it('Pro Keys: 3/16 on Hard, Medium and Easy', function()
    Test.expect(MidiLengthTooShort('pk', 'M', 0.625, 90) == true, 'M 5/32 at 90')
    Test.expect(MidiLengthTooShort('pk', 'E', 0.75, 200) == false, 'E 3/16')
end)

Test.section('MidiLengthPlainQN / MidiLengthRuleText')

Test.it('plain length: 1/16 on Pro Keys and Expert, 1/32 otherwise', function()
    Test.expect(near(MidiLengthPlainQN('pk', 'M'), 0.25), 'pk')
    Test.expect(near(MidiLengthPlainQN('gb', 'X'), 0.25), 'Expert')
    Test.expect(near(MidiLengthPlainQN('gb', 'M'), 0.125), 'gb M')
end)

Test.it('the rule text names the instrument, tier, tempo and both rules', function()
    local t = MidiLengthRuleText('gb', 'M', 172)
    Test.expect(t:find('Guitar/Bass Medium', 1, true) and t:find('172 BPM (fast', 1, true)
        and t:find('gap a quarter', 1, true) and t:find('shorter than a quarter', 1, true), t)
    t = MidiLengthRuleText('k5', 'H', 120)
    Test.expect(t:find('a 1/8 after a chord', 1, true), t)
    t = MidiLengthRuleText('k5', 'H', 90)
    Test.expect(t:find('any length stay', 1, true), t)
end)
