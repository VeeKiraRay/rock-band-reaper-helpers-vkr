-- Tests for StemImportPlan (actions_stem_import.lua).
--
-- Pure: the planner maps filenames to template tracks and never calls r, so
-- these tests need no project state and create nothing.

-- Plan as { [track] = filename }, plus the unmatched list.
local function Plan(files)
    local plan, unmatched = StemImportPlan(files)
    local map = {}
    for _, p in ipairs(plan) do map[p.track] = p.file end
    return map, unmatched
end

local function Eq(got, want, what)
    Test.expect(got == want, ('%s: expected %s, got %s'):format(
        what, tostring(want), tostring(got)))
end

Test.section('Stem import - basic mapping')

Test.it('maps a typical stem folder to every track', function()
    local m, un = Plan({
        'Song_Kick.wav', 'Song_Snare.wav', 'Song_Drums.wav', 'Song_Bass.wav',
        'Song_Guitar.wav', 'Song_Vocals.wav', 'Song_Vocals_Back.wav', 'Song_Keys.wav',
    })
    Eq(m['KICK AUDIO'],   'Song_Kick.wav',        'kick')
    Eq(m['SNARE AUDIO'],  'Song_Snare.wav',       'snare')
    Eq(m['KIT AUDIO'],    'Song_Drums.wav',       'kit')
    Eq(m['BASS AUDIO'],   'Song_Bass.wav',        'bass')
    Eq(m['GUITAR AUDIO'], 'Song_Guitar.wav',      'guitar')
    Eq(m['VOCALS AUDIO'], 'Song_Vocals.wav',      'vocal')
    Eq(m['DRYVOX2'],      'Song_Vocals_Back.wav', 'dryvox2')
    Eq(m['KEYS AUDIO'],   'Song_Keys.wav',        'keys')
    Eq(#un, 0, 'unmatched count')
end)

Test.it('keywords need no word boundary', function()
    local m = Plan({ 'leadvocalstem.wav', 'basstrack.ogg' })
    Eq(m['VOCALS AUDIO'], 'leadvocalstem.wav', 'vocal')
    Eq(m['BASS AUDIO'],  'basstrack.ogg',     'bass')
end)

Test.it('a track with no matching file gets nil', function()
    local m = Plan({ 'guitar.wav' })
    Eq(m['KICK AUDIO'], nil, 'kick')
    Eq(m['GUITAR AUDIO'], 'guitar.wav', 'guitar')
end)

Test.section('Stem import - drums')

Test.it('kick and snare files are not used for KIT', function()
    local m = Plan({ 'drums_kick.wav', 'drums_snare.wav' })
    Eq(m['KICK AUDIO'],  'drums_kick.wav',  'kick')
    Eq(m['SNARE AUDIO'], 'drums_snare.wav', 'snare')
    Eq(m['KIT AUDIO'],   nil,               'kit')
end)

Test.it('KIT picks the shortest drum file', function()
    local m = Plan({ 'drums_full_mix.wav', 'drums_kit.wav', 'drums_overheads.wav' })
    Eq(m['KIT AUDIO'], 'drums_kit.wav', 'kit')
end)

Test.it('KIT skips single-piece stems shorter than the kit file', function()
    local m = Plan({ 'drums_hh.wav', 'drums_ride.wav', 'drums_toms.wav',
                     'drums_crash.wav', 'drums_cymbals.wav', 'bassdrum.wav',
                     'drums_full.wav' })
    Eq(m['KIT AUDIO'], 'drums_full.wav', 'kit')
end)

Test.it('only piece stems present - KIT gets nothing', function()
    local m, un = Plan({ 'drums_hh.wav', 'drums_toms.wav', 'drums_ride.wav' })
    Eq(m['KIT AUDIO'], nil, 'kit')
    Eq(#un, 3, 'unmatched count')
end)

Test.it('bassdrum is not used for BASS', function()
    local m, un = Plan({ 'bass_drum.wav', 'bassdrum.wav' })
    Eq(m['BASS AUDIO'], nil, 'bass')
    Eq(m['KIT AUDIO'],  nil, 'kit')
    Eq(#un, 2, 'unmatched count')
end)

Test.it('bassdrum next to a real bass stem', function()
    local m = Plan({ 'bassdrum.wav', 'bass_guitar_di.wav' })
    Eq(m['BASS AUDIO'], 'bass_guitar_di.wav', 'bass')
end)

Test.section('Stem import - vocals')

Test.it('a lead file beats a shorter vocal file', function()
    local m = Plan({ 'vocals_2.wav', 'vocals_lead.wav' })
    Eq(m['VOCALS AUDIO'], 'vocals_lead.wav', 'vocal')
end)

Test.it('without a lead file the shortest vocal wins', function()
    local m = Plan({ 'vocals_main_take.wav', 'vocals.wav' })
    Eq(m['VOCALS AUDIO'], 'vocals.wav', 'vocal')
end)

Test.it('backing vocals go to DRYVOX2, never VOCAL', function()
    local m = Plan({ 'vocals_back.wav' })
    Eq(m['DRYVOX2'],     'vocals_back.wav', 'dryvox2')
    Eq(m['VOCALS AUDIO'], nil,               'vocal')
end)

Test.it('a second backing file does not fall through to VOCAL', function()
    local m, un = Plan({ 'vocals_back.wav', 'vocals_backing_2.wav' })
    Eq(m['DRYVOX2'],     'vocals_back.wav', 'dryvox2')
    Eq(m['VOCALS AUDIO'], nil,               'vocal')
    Eq(#un, 1, 'unmatched count')
end)

Test.section('Stem import - keys priority')

Test.it('piano beats keys beats accordion', function()
    local m = Plan({ 'accordion.wav', 'keys.wav', 'grand_piano.wav' })
    Eq(m['KEYS AUDIO'], 'grand_piano.wav', 'piano first')
    m = Plan({ 'accordion.wav', 'keyboard_keys.wav' })
    Eq(m['KEYS AUDIO'], 'keyboard_keys.wav', 'keys second')
    m = Plan({ 'accordion.wav' })
    Eq(m['KEYS AUDIO'], 'accordion.wav', 'accordion last')
end)

Test.section('Stem import - files')

Test.it('non-audio files are ignored, extensions are case-insensitive', function()
    local m, un = Plan({ 'guitar.txt', 'Guitar.WAV', 'notes.pdf', 'kick.Flac', 'mystery.mp3' })
    Eq(m['GUITAR AUDIO'], 'Guitar.WAV', 'guitar')
    Eq(m['KICK AUDIO'],   'kick.Flac',  'kick')
    Eq(#un, 1, 'unmatched count')
    Eq(un[1], 'mystery.mp3', 'unmatched file')
end)

Test.it('equal-length names break ties alphabetically', function()
    local m = Plan({ 'guitar_b.wav', 'guitar_a.wav' })
    Eq(m['GUITAR AUDIO'], 'guitar_a.wav', 'guitar')
end)

Test.it('unmatched list is sorted', function()
    local _, un = Plan({ 'zz.wav', 'aa.wav', 'mm.ogg' })
    Eq(table.concat(un, ','), 'aa.wav,mm.ogg,zz.wav', 'unmatched order')
end)
