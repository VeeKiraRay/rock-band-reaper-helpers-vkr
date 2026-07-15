-- Active players row: one-line guide shown under every Venue sub-tab (and in
-- the standalone preview window) with a colored dot per instrument showing its
-- state at the playhead - active, idle, muted/missing, or no play-state data.
-- Uses the same inputs as the venue generation weights (venue_awareness.lua).
-- Requires globals: r, ctx, TIPS, ReadInstrumentPlayStates, GetMutedInstruments,
--                   ComputePlayerStatesAt, GetInstrumentTrackName, INST_LETTER_NAMES,
--                   FindTrackByName, Tooltip, FormatTime, MakeProjectPoll

local _PLAY_LOOKUP_SECS = 0.5  -- playhead-lookup cadence while playback runs

-- Cached scan results; re-read via MakeProjectPoll - at most every 1 s and
-- only when the project actually changed (GetProjectStateChangeCount covers
-- MIDI edits and track mute toggles), with an unconditional 5 s fallback.
-- The per-playhead lookup is recomputed only when the playhead moved or the
-- scan refreshed - immediately while stopped, at _PLAY_LOOKUP_SECS cadence
-- while the transport is playing.
local _poll = MakeProjectPoll(1.0, 5.0)
local _states, _no_data, _muted, _missing
local _row              = nil
local _last_playhead    = nil
local _last_lookup_time = 0

local _ROW_ORDER = { 'b', 'g', 'd', 'k', 'v' }

local _COLORS = {
    active = 0x44DD44FF,
    idle   = 0x4499FFFF,  -- blue: pops against active-green (yellow read too close)
    muted  = 0xFF4444FF,
    nodata = 0xFFAA00FF,  -- warning amber, matches ui_midi.lua
}

local function _rescan()
    _states, _no_data = ReadInstrumentPlayStates()
    _muted            = GetMutedInstruments()
    _missing          = {}
    for _, letter in ipairs(_ROW_ORDER) do
        if _muted[letter] and not FindTrackByName(GetInstrumentTrackName(letter)) then
            _missing[letter] = true
        end
    end
end

local function _tooltip_for(letter, info)
    local name = GetInstrumentTrackName(letter)
    if info.state == 'muted' then
        local tip = _missing[letter] and TIPS.venue_player_missing
                                      or TIPS.venue_player_muted
        return tip:format(name)
    elseif info.state == 'nodata' then
        return TIPS.venue_player_nodata:format(name)
    elseif info.msg then
        return TIPS.venue_player_state:format(name, info.msg, FormatTime(info.t))
    end
    return TIPS.venue_player_default_active:format(name)
end

-- The default ImGui font has no filled-circle glyph, so draw the dot directly.
local function _draw_dot(color)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local h    = r.ImGui_GetTextLineHeight(ctx)
    local rad  = h * 0.3
    local dl   = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddCircleFilled(dl, x + rad, y + h * 0.55, rad, color)
    r.ImGui_Dummy(ctx, rad * 2, h)
end

function DrawActivePlayersRow()
    local playing  = (r.GetPlayState() & 1) == 1
    local playhead = playing and r.GetPlayPosition() or r.GetCursorPosition()

    local now = r.time_precise()
    local rescanned = _poll()
    if rescanned then _rescan() end
    if rescanned
        or (playhead ~= _last_playhead
            and (not playing or now - _last_lookup_time >= _PLAY_LOOKUP_SECS)) then
        _row = ComputePlayerStatesAt(playhead, _states, _no_data, _muted)
        _last_playhead, _last_lookup_time = playhead, now
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Active players:')
    Tooltip(TIPS.venue_players_row)
    for _, letter in ipairs(_ROW_ORDER) do
        local info = _row[letter]
        r.ImGui_SameLine(ctx, 0, 14)
        r.ImGui_BeginGroup(ctx)
        _draw_dot(_COLORS[info.state])
        r.ImGui_SameLine(ctx, 0, 4)
        r.ImGui_Text(ctx, INST_LETTER_NAMES[letter])
        r.ImGui_EndGroup(ctx)
        Tooltip(_tooltip_for(letter, info))
    end
end
