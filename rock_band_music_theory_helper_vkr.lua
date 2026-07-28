-- @description Rock Band Music Theory Helper
-- @author VeeKiraRay
-- @version 0.3
-- @about
--   In-DAW reference guide for Rock Band custom charters.
--   Covers drum notation, RB lane mappings, common patterns, and a Guitar
--   tab with a chord-type explorer, RB lane-combo terminology, a live
--   fret-shape classifier (Standard + Drop D tuning), and audio playback
--   via a synthesized preview tone (Karplus-Strong plucked-string
--   synthesis, requires SWS -- same as Drums tab audio).
--   v0.3: Guitar tab can now play chords back (synthesized preview tone,
--         no extra assets required) from both the reference table and
--         Shape Search.
--   v0.2: Added Guitar tab (chord-shape reference table, RB lane-combo
--         terminology, live fret-shape search/classifier).

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
dofile(_dir  .. 'lib/reaper_karplus_strong.lua')
dofile(_dir  .. 'lib/reaper_wav_writer.lua')
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

-- Scratch file the Guitar tab's synthesized chord preview writes to and
-- immediately plays back (single fixed name, overwritten on every play --
-- see PlayGuitarChord in ui.lua). resources/audio/ is tracked via
-- resources/audio/.gitkeep so it exists in any checkout; RecursiveCreateDirectory
-- is cheap insurance for non-standard deployments where it might not.
GUITAR_PREVIEW_WAV_PATH = _dir .. 'resources/audio/guitar_preview_scratch.wav'
if AUDIO_CF_AVAILABLE then
    r.RecursiveCreateDirectory(_dir .. 'resources/audio/', 0)
end

dofile(_mdir .. 'ui.lua')
