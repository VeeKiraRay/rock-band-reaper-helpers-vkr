-- Where the local, unversioned data the dev scripts read lives on this machine.
--
-- The reference corpora (official chart MIDIs with their songs.dta files) and a few
-- reference files are not ours to redistribute, so they are never in the repo. Scripts
-- that read them ask DevPath('<key>') instead of building a path, and a committed file
-- never says where the data sits.
--
-- SET YOUR PATHS in dev/dev_defaults.local.lua (gitignored, so it is never committed),
-- a file that returns a table with the keys you need:
--
--     return {
--         corpus_rb3_dlc = 'C:/path/to/official/rb3/dlc/songs',
--         text_events_list = 'relative/to/the/repo/root/events.txt',
--     }
--
-- A relative path is taken from the repo root. A key left out keeps its placeholder, and
-- DevPath then returns nil with a message saying what to set, so every script still
-- loads and runs on a fresh clone - it only stops (or a test skips) where it needs the
-- missing data.
--
-- Command-line tools in dev/tools/ do not use this: they take the corpus folder as an
-- argument on every run (SmfCorpusArg in dev/tools/smf_reader.lua).
--
-- NO ABSOLUTE PATH IN A COMMITTED FILE. Not in this file, and not in anything a script
-- writes into the repo (reports, manifests): write the key name instead. A machine's
-- path names the person and their folders, and it is wrong on every other checkout.

DEV_PATH_PLACEHOLDER = '<not set>'

-- Every key a committed script asks for, and what it is.
DEV_PATH_KEYS = {
    -- The difficulty calibration corpus, three origin-separated roots (dev/calibration/).
    corpus_rb3_dlc     = 'official RB3 DLC charts and songs.dta - rb3_dlc only, including the reserved test partition',
    corpus_aux         = 'official LEGO, RB2 and Green Day charts - always-training, never predicted',
    corpus_rbn         = 'Rock Band Network charts - unscored, every rank a tier floor',
    -- The calibration's older folders, before the 2026-08-21 consolidation; still read by
    -- the round-14 rescore, the label probes and the consolidation check.
    corpus_legacy      = 'the original reference songs folder',
    corpus_legacy_new  = 'the low-end set added in 2026-08 (flat packs)',
    corpus_legacy_hard = 'the hard-songs set',
    -- Reference files the REAPER test suites check against.
    instrument_difficulty_ts = 'the community InstrumentDifficulty.ts tier table (dev/tests/difficulty_suggester.lua)',
    text_events_list         = 'the community RB3 "Text Events List" (dev/tests/venue_events.lua)',
}

DEV_PATHS = {}
for k in pairs(DEV_PATH_KEYS) do DEV_PATHS[k] = DEV_PATH_PLACEHOLDER end

-- The repo root: this file sits in dev/.
local _src = (debug and debug.getinfo and debug.getinfo(1, 'S').source) or ''
local _dev_dir = _src:match('^@(.+[\\/])') or './dev/'
DEV_REPO_ROOT = (_dev_dir:match('^(.*[\\/])[^\\/]+[\\/]$')) or './'

-- The local values, when the file exists. Missing is the normal state of a fresh clone.
do
    local chunk = loadfile(_dev_dir .. 'dev_defaults.local.lua')
    if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == 'table' then
            for k, v in pairs(t) do
                if type(v) == 'string' and v ~= '' then DEV_PATHS[k] = v end
            end
        else
            DEV_PATHS_LOCAL_ERROR = 'dev/dev_defaults.local.lua did not return a table: ' .. tostring(t)
        end
    end
end

local function IsAbsolute(p) return p:match('^%a:[/\\]') or p:match('^[/\\]') end

-- The path for `key`, or nil and a message saying what to set. `dir` = true gives a
-- folder path with one trailing '/'.
function DevPath(key, dir)
    local v = DEV_PATHS[key]
    if not DEV_PATH_KEYS[key] then
        return nil, ('unknown dev path key %q (see dev/dev_defaults.lua)'):format(tostring(key))
    end
    if v == nil or v == DEV_PATH_PLACEHOLDER then
        local msg = ('dev path %q is not set: %s.\nSet it in dev/dev_defaults.local.lua ' ..
                     '(gitignored; the format is in dev/dev_defaults.lua).'):format(key, DEV_PATH_KEYS[key])
        if DEV_PATHS_LOCAL_ERROR then msg = msg .. '\n' .. DEV_PATHS_LOCAL_ERROR end
        return nil, msg
    end
    if not IsAbsolute(v) then v = DEV_REPO_ROOT .. v end
    if dir then v = v:gsub('[/\\]+$', '') .. '/' end
    return v
end
