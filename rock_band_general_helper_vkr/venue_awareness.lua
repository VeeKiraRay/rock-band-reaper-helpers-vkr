-- Venue track awareness: instrument mute detection, pool filtering,
-- and [prc_*] section detection from the EVENTS track.
-- Requires: FindTrackByName, FindNamedTrackMIDI, r, S, FormatTime (globals)
-- Globals exported here also include: FindMusicStartTime, INST_LETTER_NAMES

local INST_TRACK_NAMES = {
    d = 'PART DRUMS',
    v = 'PART VOCALS',
    b = 'PART BASS',
    g = 'PART GUITAR',
    k = 'PART KEYS',
}

-- Display names for the instrument letters (shared by generator/section/UI
-- result messages and the players row)
INST_LETTER_NAMES = {
    d = 'Drums', v = 'Vocals', b = 'Bass', g = 'Guitar', k = 'Keys',
}

-- A track is unavailable (muted[letter] = true) if it is muted OR absent.
function GetMutedInstruments()
    local muted = {}
    for letter, name in pairs(INST_TRACK_NAMES) do
        local tr = FindTrackByName(name)
        if not tr or r.GetMediaTrackInfo_Value(tr, 'B_MUTE') == 1 then
            muted[letter] = true
        end
    end
    return muted
end

function GetCoopRequiredInstruments(event_name)
    local inner = event_name:match('^%[coop_(.+)%]$')
    if not inner then return {} end
    if inner:match('^all') or inner:match('^front') then return {} end
    local code = inner:match('^(%a+)_')
    if not code then return {} end
    local required = {}
    for i = 1, #code do
        local ch = code:sub(i, i)
        if INST_TRACK_NAMES[ch] then required[#required + 1] = ch end
    end
    return required
end

function GetDirectedRequiredInstruments(event_name)
    local inner = event_name:match('^%[directed_(.+)%]$')
    if not inner then return {} end
    if inner:match('^all') or inner == 'stagedive' or inner == 'crowdsurf'
        or inner == 'crowd' then return {} end
    if inner == 'crowd_b' then return {'b'} end
    if inner == 'crowd_g' then return {'g'} end
    if inner:match('^duo_') then
        local part = inner:match('^duo_(.+)$')
        if part == 'drums'  then return {'d', 'v'} end
        if part == 'bass'   then return {'b', 'v'} end
        if part == 'guitar' then return {'g', 'v'} end
        if #part == 2 then
            local req = {}
            local a, b_ch = part:sub(1, 1), part:sub(2, 2)
            if INST_TRACK_NAMES[a]    then req[#req + 1] = a    end
            if INST_TRACK_NAMES[b_ch] then req[#req + 1] = b_ch end
            return req
        end
        return {}
    end
    if inner:match('^drums')  then return {'d'} end
    if inner:match('^vocals') then return {'v'} end
    if inner:match('^bass')   then return {'b'} end
    if inner:match('^guitar') then return {'g'} end
    if inner:match('^keys')   then return {'k'} end
    return {}
end

local PLAY_STATE_ACTIVE = { ['[play]']=true, ['[mellow]']=true, ['[intense]']=true }
local PLAY_STATE_IDLE   = { ['[idle]']=true, ['[idle_realtime]']=true }

function FilterPool(pool, muted, get_required_fn)
    local filtered = {}
    for _, name in ipairs(pool) do
        local required = get_required_fn(name)
        local blocked  = false
        for _, letter in ipairs(required) do
            if muted[letter] then blocked = true; break end
        end
        if not blocked then filtered[#filtered + 1] = name end
    end
    return filtered
end

-- Reads [play]/[mellow]/[intense]/[idle]/[idle_realtime] text events from each PART track.
-- Returns:
--   states   table[letter] = sorted { {t, is_active}, … }  or nil (always active)
--   no_data  array of letters whose present tracks have no play-state events
-- Reads MIDI notes at pitches 85/86/87 from the VENUE take.
-- These signal which non-vocalist players are also singing (bass/drums/guitar).
-- Notes survive ClearVenueTextEventsInRange (that function only removes text/sysex events).
-- Returns { letter = [{sppq, eppq}, ...] } for letters that have notes; empty table otherwise.
function ReadSingNoteTimelines(take)
    local SING_PITCH_MAP = { [85] = 'b', [86] = 'd', [87] = 'g' }
    local _, note_cnt = r.MIDI_CountEvts(take)
    local result = {}
    for i = 0, note_cnt - 1 do
        local ok, _, muted, sppq, eppq, _, pitch = r.MIDI_GetNote(take, i)
        if ok and not muted then
            local letter = SING_PITCH_MAP[pitch]
            if letter then
                if not result[letter] then result[letter] = {} end
                result[letter][#result[letter] + 1] = { sppq = sppq, eppq = eppq }
            end
        end
    end
    return result
end

function ReadInstrumentPlayStates()
    local states  = {}
    local no_data = {}
    for letter, track_name in pairs(INST_TRACK_NAMES) do
        local track = FindTrackByName(track_name)
        if track then
            local events = {}
            for i = 0, r.CountTrackMediaItems(track) - 1 do
                local it = r.GetTrackMediaItem(track, i)
                local tk = r.GetActiveTake(it)
                if tk and r.TakeIsMIDI(tk) then
                    local _, _, _, tc = r.MIDI_CountEvts(tk)
                    for j = 0, tc - 1 do
                        local ok, _, _, ppq, et, msg = r.MIDI_GetTextSysexEvt(tk, j)
                        if ok and et == 1 then
                            if PLAY_STATE_ACTIVE[msg] then
                                events[#events + 1] = {
                                    t = r.MIDI_GetProjTimeFromPPQPos(tk, ppq),
                                    is_active = true,
                                    msg = msg,
                                }
                            elseif PLAY_STATE_IDLE[msg] then
                                events[#events + 1] = {
                                    t = r.MIDI_GetProjTimeFromPPQPos(tk, ppq),
                                    is_active = false,
                                    msg = msg,
                                }
                            end
                        end
                    end
                end
            end
            table.sort(events, function(a, b) return a.t < b.t end)
            if #events == 0 then
                states[letter] = nil   -- always active (fallback)
                no_data[#no_data + 1] = letter
            else
                states[letter] = events
            end
        end
        -- absent track: muted check handles exclusion, no play-state entry needed
    end
    return states, no_data
end

function GetInstrumentTrackName(letter)
    return INST_TRACK_NAMES[letter]
end

-- Pure point-in-time query over ReadInstrumentPlayStates() data (UI row + tests).
-- playhead in project seconds; states/no_data from ReadInstrumentPlayStates();
-- muted from GetMutedInstruments().
-- Returns result[letter] = { state = 'muted'|'nodata'|'active'|'idle',
--                            msg = play-state event string or nil,
--                            t   = that event's project time or nil }
-- Before the first event an instrument counts as active, matching how the
-- generator treats missing/preceding play-state data.
function ComputePlayerStatesAt(playhead, states, no_data, muted)
    local nodata_set = {}
    for _, letter in ipairs(no_data or {}) do nodata_set[letter] = true end
    local result = {}
    for letter in pairs(INST_TRACK_NAMES) do
        if muted and muted[letter] then
            result[letter] = { state = 'muted' }
        elseif nodata_set[letter] then
            result[letter] = { state = 'nodata' }
        else
            local last = nil
            for _, ev in ipairs(states and states[letter] or {}) do
                if ev.t <= playhead then last = ev else break end
            end
            if last then
                result[letter] = { state = last.is_active and 'active' or 'idle',
                                   msg = last.msg, t = last.t }
            else
                result[letter] = { state = 'active' }
            end
        end
    end
    return result
end

-- =============================================================================
-- EVENT SECTION DETECTION
-- Reads [prc_*] text events from the EVENTS track and groups them into song
-- sections for use by the venue generator. Not yet wired into generation.
-- =============================================================================

-- Parses a [prc_*] event name into {name, num, letter}.
-- Returns nil for anything that is not a [prc_*] event.
-- letter is nil (not empty string) when no letter suffix is present.
local function ParsePrcEvent(event_name)
    local inner = event_name:match('^%[prc_(.+)%]$')
    if not inner then return nil end

    local num_str, letter = inner:match('_(%d+)([a-z]?)$')
    local name, num
    if num_str then
        num  = tonumber(num_str)
        name = inner:sub(1, #inner - #num_str - #letter - 1)
        if #letter == 0 then letter = nil end
    else
        name   = inner
        num    = nil
        letter = nil
    end

    return { name = name, num = num, letter = letter }
end

-- Reads [prc_*] events from the EVENTS MIDI track and returns a sorted array
-- of section records:
--   { name, num, is_lettered, sub_count, t_start, t_end }
-- t_end of the last section is set to song_end_t.
-- Consecutive events sharing (name, num) and both having letter suffixes are
-- merged into one section. Events without a letter are always standalone.
-- Returns nil, error_string on failure; returns {} when no prc events found.
function ReadEventSections(song_end_t)
    local track, item, take = FindNamedTrackMIDI('EVENTS')
    if not track then
        return nil, 'No track named "EVENTS" found in this project.'
    end
    if not item then
        return nil, 'Found the EVENTS track but it has no MIDI items.'
    end

    local prc_events = {}
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 then
            local parsed = ParsePrcEvent(msg)
            if parsed then
                prc_events[#prc_events + 1] = {
                    t      = r.MIDI_GetProjTimeFromPPQPos(take, ppq),
                    parsed = parsed,
                }
            end
        end
    end

    if #prc_events == 0 then return {} end

    table.sort(prc_events, function(a, b) return a.t < b.t end)

    -- Build section list, merging consecutive letter-variant events
    local sections = {}
    for _, ev in ipairs(prc_events) do
        local p    = ev.parsed
        local last = sections[#sections]
        local merge = p.letter ~= nil
                   and last ~= nil
                   and last.is_lettered
                   and last.name == p.name
                   and last.num  == p.num
        if merge then
            last.sub_count = last.sub_count + 1
        else
            sections[#sections + 1] = {
                name        = p.name,
                num         = p.num,
                is_lettered = p.letter ~= nil,
                sub_count   = 1,
                t_start     = ev.t,
                t_end       = song_end_t,
            }
        end
    end

    -- t_end of each section = t_start of the next
    for i = 1, #sections - 1 do
        sections[i].t_end = sections[i + 1].t_start
    end

    return sections
end

-- Returns the project time of the earliest "[music_start]" text event on the
-- EVENTS track, or nil if the track/item/event doesn't exist. Used by the
-- venue generator to anchor the first generated camera cut and any [prc_*]
-- section placed right at the song's literal start.
function FindMusicStartTime()
    local _, _, take = FindNamedTrackMIDI('EVENTS')
    if not take then return nil end
    local best_ppq
    local _, _, _, text_count = r.MIDI_CountEvts(take)
    for i = 0, text_count - 1 do
        local ok, _, _, ppq, evt_type, msg = r.MIDI_GetTextSysexEvt(take, i)
        if ok and evt_type == 1 and msg == '[music_start]' then
            if not best_ppq or ppq < best_ppq then best_ppq = ppq end
        end
    end
    if not best_ppq then return nil end
    return r.MIDI_GetProjTimeFromPPQPos(take, best_ppq)
end

function ListEventSections()
    -- Use VENUE item end as song_end_t; fall back to project length
    local song_end_t = r.GetProjectLength(0)
    local _, venue_item = FindNamedTrackMIDI('VENUE')
    if venue_item then
        song_end_t = r.GetMediaItemInfo_Value(venue_item, 'D_POSITION')
                   + r.GetMediaItemInfo_Value(venue_item, 'D_LENGTH')
    end

    local sections, err = ReadEventSections(song_end_t)
    if sections == nil then
        S.status      = 'Error reading EVENTS track.'
        S.last_result = err
        return
    end

    if #sections == 0 then
        S.status      = 'No [prc_*] section markers found.'
        S.last_result = 'The EVENTS track has no [prc_*] text events.\n\n' ..
                        'Add section markers such as [prc_verse_1], [prc_chorus_1]\n' ..
                        'to the EVENTS track to enable section-aware generation.'
        return
    end

    local lines = {}
    lines[#lines + 1] = ('Event sections: %d total'):format(#sections)
    lines[#lines + 1] = ''

    for i, sec in ipairs(sections) do
        local cap_name   = sec.name:sub(1,1):upper() .. sec.name:sub(2)
        local name_part  = sec.num and (cap_name .. ' ' .. sec.num) or cap_name
        local parts_note = (sec.is_lettered and sec.sub_count > 1)
                           and ('  (%d parts)'):format(sec.sub_count) or ''
        lines[#lines + 1] = ('%3d.  %s\t%s  ->  %s%s'):format(
            i, name_part,
            FormatTime(sec.t_start),
            FormatTime(sec.t_end),
            parts_note)
    end

    S.status      = ('%d event sections detected.'):format(#sections)
    S.last_result = table.concat(lines, '\n')
end
