-- Stem import action (General tab)
-- Requires: S, r, FormatTime (globals)
-- Requires: FindTrackByName, GetAudioItems (from helpers.lua)
--
-- Scans one folder (not its subfolders) for audio files, matches each file to a
-- template track by filename keyword, and places it on that track at the SONG
-- AUDIO item's position. StemImportPlan is pure so dev/tests can drive it with
-- plain filename lists; ImportStems is the thin REAPER wrapper.

local AUDIO_EXTS = {
    wav = true, mp3 = true, ogg = true, flac = true, aif = true,
    aiff = true, m4a = true, wma = true, opus = true,
}

-- A "drum" file that also names one of these is a single-piece stem, not the
-- full kit. Their names are often as short as drums_full / drums_kit, so the
-- shortest-name tie-break alone would pick them. "bass" covers bassdrum.
local KIT_EXCLUDE = { 'crash', 'cymbal', 'hh', 'kick', 'ride', 'snare', 'toms', 'bass' }

-- Rules run in this order, and a file claimed by one rule is no longer a
-- candidate for the rules after it (drums_kick goes to KICK only).
--   all      - every keyword must appear
--   none     - no keyword may appear
--   priority - keywords tried in order; the first with any hit wins
--   prefer   - among candidates, those containing this keyword win
local STEM_RULES = {
    { track = 'DRYVOX2',      all = { 'vocal', 'back' } },
    { track = 'KICK AUDIO',   all = { 'kick' } },
    { track = 'SNARE AUDIO',  all = { 'snare' } },
    { track = 'KEYS AUDIO',   priority = { 'piano', 'keys', 'accordion' } },
    { track = 'BASS AUDIO',   all = { 'bass' }, none = { 'drum' } },
    { track = 'GUITAR AUDIO', all = { 'guitar' } },
    { track = 'VOCALS AUDIO', all = { 'vocal' }, none = { 'back' }, prefer = 'lead' },
    { track = 'KIT AUDIO',    all = { 'drum' }, none = KIT_EXCLUDE },
}

local function HasAll(name, words)
    for _, w in ipairs(words or {}) do
        if not name:find(w, 1, true) then return false end
    end
    return true
end

local function HasAny(name, words)
    for _, w in ipairs(words or {}) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- Shortest base name wins; equal lengths fall back to alphabetical order so the
-- result never depends on the order the filesystem listed the files in.
local function Shortest(cands)
    table.sort(cands, function(a, b)
        if #a.base ~= #b.base then return #a.base < #b.base end
        return a.base < b.base
    end)
    return cands[1]
end

local function PickForRule(rule, files)
    local cands = {}
    if rule.priority then
        for _, word in ipairs(rule.priority) do
            for _, f in ipairs(files) do
                if not f.claimed and f.base:find(word, 1, true) then
                    cands[#cands + 1] = f
                end
            end
            if #cands > 0 then break end
        end
    else
        for _, f in ipairs(files) do
            if not f.claimed and HasAll(f.base, rule.all) and not HasAny(f.base, rule.none) then
                cands[#cands + 1] = f
            end
        end
    end
    if #cands == 0 then return nil end
    if rule.prefer then
        local preferred = {}
        for _, f in ipairs(cands) do
            if f.base:find(rule.prefer, 1, true) then preferred[#preferred + 1] = f end
        end
        if #preferred > 0 then cands = preferred end
    end
    return Shortest(cands)
end

-- Match filenames (no directory part) to template tracks.
-- Returns plan, unmatched:
--   plan      - array in rule order: { track = name, file = filename or nil }
--   unmatched - audio filenames no rule claimed, sorted
-- Files that are not audio (by extension) are ignored entirely.
function StemImportPlan(filenames)
    local files = {}
    for _, fn in ipairs(filenames) do
        local base, ext = fn:match('^(.+)%.([^.]+)$')
        if base and AUDIO_EXTS[ext:lower()] then
            files[#files + 1] = { name = fn, base = base:lower(), claimed = false }
        end
    end

    local plan = {}
    for _, rule in ipairs(STEM_RULES) do
        local f = PickForRule(rule, files)
        if f then f.claimed = true end
        plan[#plan + 1] = { track = rule.track, file = f and f.name or nil }
    end

    local unmatched = {}
    for _, f in ipairs(files) do
        if not f.claimed then unmatched[#unmatched + 1] = f.name end
    end
    table.sort(unmatched)
    return plan, unmatched
end

-- Folder dialog from js_ReaScriptAPI when installed; otherwise the native file
-- dialog, where the folder of whichever file is picked gets scanned.
-- Returns the folder path without a trailing separator, or nil on cancel.
local function PickStemFolder()
    local start = r.GetProjectPath('')
    if r.JS_Dialog_BrowseForFolder then
        local rv, folder = r.JS_Dialog_BrowseForFolder('Select the stem folder', start)
        if rv ~= 1 or not folder or folder == '' then return nil end
        return (folder:gsub('[/\\]+$', ''))
    end
    local ok, path = r.GetUserFileNameForRead(start, 'Select any audio file in the stem folder', '')
    if not ok or not path or path == '' then return nil end
    return path:match('^(.*)[/\\][^/\\]*$')
end

local function ListFolderFiles(folder)
    local names = {}
    local i = 0
    while true do
        local fn = r.EnumerateFiles(folder, i)
        if not fn then break end
        names[#names + 1] = fn
        i = i + 1
    end
    return names
end

-- Create an audio item for path on track at pos. Returns the item, or nil when
-- REAPER cannot read the file.
local function InsertStemItem(track, path, filename, pos)
    local src = r.PCM_Source_CreateFromFile(path)
    if not src then return nil end
    local len = r.GetMediaSourceLength(src)
    if not len or len <= 0 then
        r.PCM_Source_Destroy(src)
        return nil
    end
    local item = r.AddMediaItemToTrack(track)
    local take = r.AddTakeToMediaItem(item)
    r.SetMediaItemTake_Source(take, src)
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len)
    r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', filename, true)
    r.UpdateItemInProject(item)
    return item
end

-- Pick a folder and place its stems on the matching template tracks, aligned to
-- the SONG AUDIO item. Tracks that already hold audio are never touched.
function ImportStems()
    local ref_track = FindTrackByName('SONG AUDIO')
    if not ref_track then
        S.status = 'Error: SONG AUDIO track not found.'
        S.last_result = 'Could not find a track named "SONG AUDIO".\n' ..
                        'Stems are placed at the SONG AUDIO item position, so it is required.'
        return
    end
    local ref_audio = GetAudioItems(ref_track)
    if #ref_audio == 0 then
        S.status = 'Error: SONG AUDIO has no audio items.'
        S.last_result = 'SONG AUDIO track has no audio items.\n' ..
                        'Stems are placed at the SONG AUDIO item position, so it is required.'
        return
    end
    local ref_pos = r.GetMediaItemInfo_Value(ref_audio[1], 'D_POSITION')

    local folder = PickStemFolder()
    if not folder then
        S.status = 'Import stems cancelled.'
        return
    end
    local sep = folder:find('\\', 1, true) and '\\' or '/'

    local plan, unmatched = StemImportPlan(ListFolderFiles(folder))

    -- Sort every rule into one bucket before writing anything, so a run with
    -- nothing to import returns without creating an undo point.
    local to_import, has_audio, no_track, no_file = {}, {}, {}, {}
    for _, p in ipairs(plan) do
        local tr = FindTrackByName(p.track)
        if not p.file then
            no_file[#no_file + 1] = p
        elseif not tr then
            no_track[#no_track + 1] = p
        elseif #GetAudioItems(tr) > 0 then
            has_audio[#has_audio + 1] = p
        else
            p.tr = tr
            to_import[#to_import + 1] = p
        end
    end

    local imported, failed = {}, {}
    if #to_import > 0 then
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock2(0)
        for _, p in ipairs(to_import) do
            if InsertStemItem(p.tr, folder .. sep .. p.file, p.file, ref_pos) then
                imported[#imported + 1] = p
            else
                failed[#failed + 1] = p
            end
        end
        r.UpdateArrange()
        r.Undo_EndBlock2(0, ('Import stems (%d imported)'):format(#imported), -1)
        r.PreventUIRefresh(-1)
        if #imported > 0 then
            r.Main_OnCommand(40047, 0)  -- Peaks: Build any missing peaks
        end
    end

    local lines = {}
    lines[#lines + 1] = 'Folder: ' .. folder
    lines[#lines + 1] = ('SONG AUDIO position: %s'):format(FormatTime(ref_pos))
    local function Group(title, list, fmt)
        if #list == 0 then return end
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('%s (%d):'):format(title, #list)
        for _, p in ipairs(list) do lines[#lines + 1] = fmt(p) end
    end
    local function TrackFile(p) return ('  %-13s <- %s'):format(p.track, p.file) end
    Group('Imported', imported, TrackFile)
    Group('Skipped - track already has audio', has_audio, TrackFile)
    Group('Skipped - file could not be read', failed, TrackFile)
    Group('Skipped - track not found in project', no_track, TrackFile)
    Group('No matching file', no_file, function(p) return '  ' .. p.track end)
    if #unmatched > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Audio files not matched to any track (%d):'):format(#unmatched)
        for _, fn in ipairs(unmatched) do lines[#lines + 1] = '  ' .. fn end
    end

    S.status = #imported > 0
        and ('Imported %d stem%s.'):format(#imported, #imported == 1 and '' or 's')
        or  'No stems imported.'
    S.last_result = table.concat(lines, '\n')
end
