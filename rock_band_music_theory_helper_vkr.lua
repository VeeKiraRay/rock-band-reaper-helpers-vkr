-- @description Rock Band Music Theory Helper
-- @author VeeKiraRay
-- @version 0.6
-- @about
--   In-DAW reference guide for Rock Band custom charters.
--   Covers drum notation, RB lane mappings, common patterns, a Guitar
--   tab with a chord-type explorer, RB lane-combo terminology, a live
--   fret-shape classifier (Standard + Drop D tuning), and a Piano tab that
--   turns written staff notation into the keys to press.
--   ALL audio playback -- drum samples and the synthesized preview tone
--   (Karplus-Strong plucked-string synthesis) on the Guitar and Piano tabs
--   alike -- goes through the SWS extension's CF_Preview API, so SWS is
--   required to hear anything. SWS is NOT a ReaPack package: install it from
--   sws-extension.org, then restart REAPER. The drum sample pack is a
--   separate optional download (see resources/INSTALLATION_GUIDE.md) and
--   is only used by the Drums tab; the Guitar and Piano tabs need no extra
--   assets.
--
--   This @about block keeps only the 5 most recent versions.
--   Full history: CHANGELOG.md in the repo.
--
--   v0.6: The window title now carries the script version -- "RB Music Theory
--         Helper v0.6". A bug report that quotes the title says which version
--         it came from, with nothing to look up. The version is read from this
--         file's own header when the script starts, so it can never disagree
--         with the version entries below. Your window size, position and dock
--         state carry over unchanged, and will survive every future version
--         bump too.
--   v0.5: New Piano tab -- an interactive grand staff for reading sheet
--         music. Pick the clef for each staff and the key signature, then
--         click the staff wherever a note head is printed. Six clefs: treble
--         and bass, each also in 8va (a small 8 above the clef, sounding an
--         octave higher) and 8vb (8 below, an octave lower -- the one piano
--         and vocal scores use). Either staff takes any of them, so a
--         two-treble score works as well as a grand staff.
--         It reports the keys to press: note names, MIDI numbers, a piano
--         keyboard diagram with those keys lit, and block-chord playback.
--         Names default to REAPER's own piano-roll spelling (C C# D Eb E F
--         F# G G# A Bb B) in Rock Band octaves (C1 = 36), so they read
--         straight across into the MIDI editor. Untick "REAPER piano roll"
--         to see the sheet-music spelling instead -- what is printed on the
--         page, spelled to match the key signature (Db rather than C#) in
--         scientific octaves (middle C = C4).
--         Ledger lines are handled automatically three positions above and
--         below each staff, and clusters of adjacent notes offset the way an
--         engraver would write them.
--         The staff maths lives in the new lib/reaper_music_notation.lua and
--         is covered by dev/tests/run_music_notation.lua.
--         Chord preview gained tone presets. The Piano tab has a Tone combo
--         (Soft / Natural / Bright) using a softer synthesized hammer strike
--         and lightly detuned unison strings, so it reads as struck rather
--         than plucked, and rings for 2.5s instead of 1s. Both tabs also
--         stop clicking at the end of every preview: the audio used to be
--         cut off mid-ring, which was the biggest single reason previews
--         sounded artificial. The Guitar tab's tone itself is unchanged.
--   v0.4: Guitar fret shapes now read LOW to HIGH -- the leftmost number is
--         the low E string, as in standard chord notation ("x 3 2 0 1 0" is
--         C major). They used to read high-to-low, which is backwards from
--         how every chord chart, chord dictionary, and Guitar Pro diagram
--         writes them. Affects the Shape Search box and all 26 shapes in the
--         Chord Type Explorer table, which were reversed to match. The
--         General Helper's horizontal Tab Input changed the same way in its
--         v0.9.47, so shapes can still be pasted between the two. Vertical
--         ASCII tab there is unchanged (high e on the top row) -- the two
--         notations genuinely run in opposite directions.
--         Also fixed the Sus2 and Sus4 rows advertising a "1-4" RB mapping
--         (a two-gem spread) for shapes that are real three-pitch-class sus
--         voicings and can only be charted as 3-note chords. Their shapes
--         had been regenerated from interval math but kept a mapping label
--         written for a different, two-note shape. Both now read "3-note".
--         Found by new tests that round-trip every row of the chord
--         reference table through the live classifier -- shape, chord type,
--         and RB mapping alike -- instead of trusting the hand-authored
--         table. The table previously had no automated check at all.
--   v0.3.1: Drums tab now says why playback is unavailable, distinguishing
--         a missing SWS extension from a missing drum sample pack (it
--         previously showed the same silent fallback text for both).
--   v0.3: Guitar tab can now play chords back (synthesized preview tone,
--         no extra assets required) from both the reference table and
--         Shape Search.

r = reaper

if not r.ImGui_CreateContext then
    r.ShowMessageBox(
        'This script requires the ReaImGui extension.\n\n' ..
        'Install it via Extensions > ReaPack > Browse packages,\n' ..
        'then search for "ReaImGui" and install it.',
        'Missing dependency', 0
    )
    return
end

if not r.ImGui_BeginDisabled then
    r.ShowMessageBox(
        'This script requires ReaImGui 0.7 or later.\n\n' ..
        'Update via Extensions > ReaPack > Browse packages.',
        'ReaImGui version too old', 0
    )
    return
end

ctx = r.ImGui_CreateContext('RB Music Theory Helper')

local _script = ({reaper.get_action_context()})[2]
local _dir    = _script:match('^(.+[\\/])')
local _mdir   = _dir .. _script:match('[/\\]([^/\\]+)%.lua$') .. '/'

local _img_path = _dir .. 'resources/img/drum.png'
local _img_ok, _img_result = pcall(r.ImGui_CreateImage, _img_path)
IMG_DRUM_NOTATION = _img_ok and _img_result or nil
-- Un-attached ReaImGui images are only guaranteed valid while drawn every
-- frame. Attach so the image survives frames where the Drums tab (and its
-- ImGui_Image call) isn't the active tab. Matches the pattern used by every
-- other image in this codebase (see venue_sprites.lua, venue_sprite_tester_vkr.lua).
if IMG_DRUM_NOTATION then r.ImGui_Attach(ctx, IMG_DRUM_NOTATION) end

-- Read PNG image dimensions from file header (bytes 17-24 of a valid PNG).
-- Used by ui.lua to maintain aspect ratio when displaying the image.
local function _png_dims(path)
    local f = io.open(path, 'rb')
    if not f then return 1, 1 end
    local b = f:read(24)
    f:close()
    if not b or #b < 24 then return 1, 1 end
    local function u32be(i) return b:byte(i)*16777216 + b:byte(i+1)*65536 + b:byte(i+2)*256 + b:byte(i+3) end
    return u32be(17), u32be(21)
end
IMG_DRUM_W, IMG_DRUM_H = _png_dims(_img_path)

dofile(_dir  .. 'lib/reaper_imgui_helpers.lua')
dofile(_dir  .. 'lib/reaper_guitar_theory.lua')
dofile(_dir  .. 'lib/reaper_music_notation.lua')
dofile(_dir  .. 'lib/reaper_karplus_strong.lua')
dofile(_dir  .. 'lib/reaper_wav_writer.lua')

-- Window title with this script's own @version, read from the header above.
-- ui.lua passes it to ImGui_Begin; the "###" id inside keeps saved window
-- geometry across version bumps. See ScriptWindowTitle.
WINDOW_TITLE = ScriptWindowTitle('RB Music Theory Helper', _script)

dofile(_mdir .. 'defaults.lua')

-- Seed the RNG once with real entropy so KarplusStrongVoice's noise burst
-- (when called without an explicit opts.seed) varies from play to play,
-- like a real strum, instead of deterministically replaying Lua's default
-- unseeded state every session.
math.randomseed(os.time())

-- Detect optional audio sample pack (separate download, MIT-licensed MuseScore Basic).
-- Probe uses the first row's audio_file so the path is driven by defaults.lua content.
-- SWS extension required for audio preview playback (CF_CreatePreview / CF_Preview_* API).
AUDIO_CF_AVAILABLE = (r.CF_CreatePreview ~= nil)

AUDIO_DRUMS_DIR = nil
local _adir = _dir .. 'resources/audio/drums/'
if AUDIO_CF_AVAILABLE and DRUM_NOTATION[1] and DRUM_NOTATION[1].audio_file then
    local _probe = io.open(_adir .. DRUM_NOTATION[1].audio_file, 'rb')
    if _probe then _probe:close(); AUDIO_DRUMS_DIR = _adir end
end

-- Scratch file the synthesized chord preview writes to and immediately plays
-- back -- shared by the Guitar and Piano tabs (single fixed name, overwritten
-- on every play; see PlaySynthChord in audio_preview.lua).
-- resources/audio/ is tracked via resources/audio/.gitkeep so it exists in any
-- checkout; RecursiveCreateDirectory is cheap insurance for non-standard
-- deployments where it might not.
SYNTH_PREVIEW_WAV_PATH = _dir .. 'resources/audio/synth_preview_scratch.wav'
if AUDIO_CF_AVAILABLE then
    r.RecursiveCreateDirectory(_dir .. 'resources/audio/', 0)
end

dofile(_mdir .. 'audio_preview.lua')
dofile(_mdir .. 'ui_piano.lua')
dofile(_mdir .. 'ui.lua')
