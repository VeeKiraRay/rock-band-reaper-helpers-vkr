-- Directed-cut timing: what the camera shows after a directed cut.
-- Pure: no r, ctx or S. Requires (at call time): PickPriorityCameraEvent,
-- CameraShotFitsBand (venue_camera_priority.lua), RB_VENUE_SHOTS
-- (lib/reaper_venue_shots.lua).
--
-- How the game reads a custom song's VENUE camera events (checked in game):
--
--   1. Events on one tick are one spot, and the spot plays one shot: the highest-
--      priority one that fits the lineup. Every directed cut outranks every normal
--      shot, so a normal shot stacked with a directed cut is only a fallback for a
--      lineup that cannot play the cut.
--   2. A directed cut cannot follow a directed cut: when the spot after one picks a
--      directed cut, the game plays the spot's best normal shot instead, or a
--      generic band shot when it has none.
--   3. The spot after a directed cut (its "follow-up") is moved to just after the
--      directed cut's event, inside the time the directed shot is locked on screen.
--      So it never cuts the directed shot; it only names the shot that plays when
--      the directed move ends. Its own position does not matter.
--   4. The spot after that, at its own position, cuts the directed shot if the move
--      is still running - and then the follow-up is never shown.
--
-- So a directed shot runs until its move ends or until the second camera spot after
-- it, whichever comes first. How long it runs after its event depends on the version
-- the game picks (each venue has its own, rotated between), which a chart cannot
-- choose; RB_VENUE_SHOTS holds the range the game allows each directed cut (its own
-- asset check on the venue files), so every version lies inside it. The checks
-- below report only what holds anywhere in that range:
--
--   follow_skipped   the second spot comes before the shortest length allowed ends:
--                    the follow-up is never shown (an issue). Only when the follow-up
--                    was placed later than FOLLOW_AT_CUT_S after the cut: one right
--                    after it has no time of its own (it only names what comes next),
--                    and official venues often let the next spot end a long move that
--                    way - a placed time is what gets lost.
--   follow_early     the follow-up sits after the longest length allowed ends: it
--                    shows when the move ends, before its own position (advisory).
--   directed_replaced a directed cut right after a directed cut: it does not play
--                    (an issue).

-- A follow-up at most this far after the directed cut sits inside the time the cut
-- is locked on screen (at least 0.25 s after its event), the official way to write
-- "this comes next" (~0.1 s after the cut).
local FOLLOW_AT_CUT_S = 0.25

-- Seconds a directed cut's move may run after its event, as { min, max }: the range
-- the game allows its clips, or nil when the shot data has no length for it.
function DirectedCutLength(msg)
    local name = msg and msg:match('^%[(directed_[%w_]+)%]$')
    local ev   = name and RB_VENUE_SHOTS and RB_VENUE_SHOTS.events[name]
    return ev and ev.length or nil
end

local function IsDirected(msg) return msg:find('^%[directed_') ~= nil end

-- The shot a spot plays for one lineup when a directed cut may not play there
-- (rule 2): its best normal shot, or nil = the game's generic band shot.
local function BestNormal(group, muted)
    local normals = {}
    for _, ev in ipairs(group) do
        if not IsDirected(ev.msg) then normals[#normals + 1] = ev end
    end
    return PickPriorityCameraEvent(normals, muted)
end

-- One spot per tick, events deduped by text: { ppq=, sec=, group= }.
local function CameraSpots(camera, sec_of)
    local spots = {}
    local i = 1
    while i <= #camera do
        local ppq, group, seen = camera[i].ppq, {}, {}
        while i <= #camera and camera[i].ppq == ppq do
            if not seen[camera[i].msg] then
                seen[camera[i].msg] = true
                group[#group + 1] = camera[i]
            end
            i = i + 1
        end
        spots[#spots + 1] = { ppq = ppq, sec = sec_of(ppq, group[1]), group = group }
    end
    return spots
end

-- What each spot plays for one lineup (rules 1 and 2): plays[k] = { directed=,
-- msg=, ev=, replaced = { by = event or nil } when a directed cut gave way }. ev /
-- msg are nil where nothing fits (the game's generic shot - still a cut, so it
-- still counts as a spot).
local function SpotPlays(spots, muted)
    local plays, prev_directed = {}, false
    for k, spot in ipairs(spots) do
        local chosen = PickPriorityCameraEvent(spot.group, muted)
        local directed = chosen ~= nil and IsDirected(chosen.msg)
        local p = { directed = directed, ev = chosen, msg = chosen and chosen.msg }
        if directed and prev_directed then
            p.directed = false
            p.replaced = { by = BestNormal(spot.group, muted) }
        end
        plays[k] = p
        prev_directed = p.directed
    end
    return plays
end

-- camera  ppq-sorted array of { ppq=, msg= } camera events
-- lineups BuildBandLineups() result
-- sec_of  function(ppq) -> project seconds (the tempo map)
-- length_of optional override of DirectedCutLength (tests)
--
-- Returns { follow_skipped = {}, follow_early = {}, directed_replaced = {} }. One
-- entry per spot, carrying the lineups it applies to:
--   follow_skipped:    { ppq=, msg=, dir_ppq=, dir_msg=, next_ppq=, next_msg=, len=, lineups= }
--   follow_early:      { ppq=, msg=, dir_ppq=, dir_msg=, len=, lineups= }
--   directed_replaced: { ppq=, msg=, prev_ppq=, prev_msg=, plays= (msg or nil), lineups= }
function ValidateDirectedCutTiming(camera, lineups, sec_of, length_of)
    length_of = length_of or DirectedCutLength
    local out = { follow_skipped = {}, follow_early = {}, directed_replaced = {} }

    local spots = CameraSpots(camera, sec_of)

    -- Merge per-lineup findings into one entry per spot and kind.
    local index = {}
    local function Add(kind, key, fields, label)
        local id = kind .. ':' .. key
        local e = index[id]
        if not e then
            e = fields
            e.lineups = {}
            index[id] = e
            local list = out[kind]
            list[#list + 1] = e
        end
        e.lineups[#e.lineups + 1] = label
    end

    for _, lineup in ipairs(lineups) do
        local plays = SpotPlays(spots, lineup.muted)
        for k, spot in ipairs(spots) do
            if plays[k].replaced then
                local by = plays[k].replaced.by
                Add('directed_replaced', k, {
                    ppq = spot.ppq, msg = plays[k].msg,
                    prev_ppq = spots[k - 1].ppq, prev_msg = plays[k - 1].msg,
                    plays = by and by.msg or nil,
                }, lineup.label)
            end
        end

        for k, spot in ipairs(spots) do
            local len = plays[k].directed and length_of(plays[k].msg)
            local follow, second = spots[k + 1], spots[k + 2]
            if len and follow then
                local f_msg = (plays[k + 1].msg) or follow.group[1].msg
                if second and second.sec - spot.sec < len[1] then
                    if follow.sec - spot.sec > FOLLOW_AT_CUT_S then
                        Add('follow_skipped', k + 1, {
                            ppq = follow.ppq, msg = f_msg,
                            dir_ppq = spot.ppq, dir_msg = plays[k].msg,
                            next_ppq = second.ppq,
                            next_msg = (plays[k + 2] and plays[k + 2].msg) or second.group[1].msg,
                            len = len,
                        }, lineup.label)
                    end
                elseif follow.sec - spot.sec > len[2] then
                    Add('follow_early', k + 1, {
                        ppq = follow.ppq, msg = f_msg,
                        dir_ppq = spot.ppq, dir_msg = plays[k].msg, len = len,
                    }, lineup.label)
                end
            end
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
-- The camera spots for one lineup, with what the game does around directed cuts:
-- the Venue Preview's camera row, built on the same rules as the checks above.
-- Every spot keeps its own position - the Preview shows what was written and says
-- where the game differs, rather than guessing when a move ends.
--
-- camera  ppq-sorted array of { ppq=, msg=, t= } (t = project seconds)
-- muted   the lineup's muted table (CameraShotFitsBand)
--
-- Returns every spot, in order, each:
--   { t = its own position, group = its events,
--     ev = the shot that plays (nil when nothing fits: CameraFallback's case),
--     replaced = { by = event or nil, prev = event }   a directed cut right after a
--                directed cut: `by` plays instead (nil = a generic band shot),
--     follow   = { dir = event, dir_t =, len = { min, max } or nil, maybe_skipped =,
--                  skipped = }  the spot right after a directed cut: it plays as soon
--                as the move ends, not at its own position. skipped: the next spot
--                cuts the move before the shortest length allowed ends, so it is
--                never shown; maybe_skipped: the next spot falls inside the move's
--                range, so it shows only if the venue's move is short enough. len is
--                nil when the shot data has no length for the cut,
--     skips    = item   on a directed cut: its follow-up, never shown }
--
-- as_written = true: the priority pick only (rule 1) - none of the directed-cut
-- rules. The Preview's view with "Mark directed-cut timing" off.
function CameraGameTimeline(camera, muted, length_of, as_written)
    length_of = length_of or DirectedCutLength
    local spots = CameraSpots(camera, function(_, ev) return ev.t end)
    if as_written then
        local items = {}
        for k, spot in ipairs(spots) do
            items[k] = { t = spot.sec, group = spot.group,
                         ev = PickPriorityCameraEvent(spot.group, muted) }
        end
        return items
    end
    local plays = SpotPlays(spots, muted)

    local items = {}
    for k, spot in ipairs(spots) do
        local p = plays[k]
        items[k] = {
            t = spot.sec, group = spot.group, ev = p.ev,
            replaced = p.replaced and { by = p.replaced.by, prev = plays[k - 1].ev } or nil,
        }
    end

    for k, spot in ipairs(spots) do
        local follow, second = items[k + 1], items[k + 2]
        if plays[k].directed and follow then
            local len = length_of(plays[k].msg)
            local gap = second and (second.t - spot.sec)
            follow.follow = {
                dir = items[k].ev, dir_t = spot.sec, len = len,
                skipped       = len ~= nil and gap ~= nil and gap < len[1],
                maybe_skipped = len ~= nil and gap ~= nil and gap >= len[1] and gap < len[2],
            }
            if follow.follow.skipped then items[k].skips = follow end
        end
    end
    return items
end

-- ---------------------------------------------------------------------------
-- Report lines for ValidateVenueCamera. at(ppq) formats a position; nlineups is
-- how many lineups were replayed (lineup names are only shown when there are
-- several); list_max caps the advisory list.

-- A move length { min, max } as text: "6.2-16.7 s", or "1.0 s" when both agree.
function DirectedLengthText(len)
    if math.abs(len[1] - len[2]) < 0.005 then return ('%.1f s'):format(len[1]) end
    return ('%.1f-%.1f s'):format(len[1], len[2])
end
local Range = DirectedLengthText

local function ForLineups(e, nlineups)
    if nlineups <= 1 or #e.lineups >= nlineups then return '' end   -- every lineup
    return (' (%s lineup%s)'):format(table.concat(e.lineups, ' and '), #e.lineups == 1 and '' or 's')
end

function DirectedTimingReportLines(f, at, nlineups, list_max)
    local lines = {}

    if #f.follow_skipped == 0 then
        lines[#lines + 1] = 'Shots after a directed cut that are never shown: none.'
    else
        lines[#lines + 1] = ('Shots after a directed cut that are never shown (%d):')
                            :format(#f.follow_skipped)
        for _, e in ipairs(f.follow_skipped) do
            lines[#lines + 1] = ('  %s   %s%s'):format(at(e.ppq), e.msg, ForLineups(e, nlineups))
            lines[#lines + 1] = ('           - it would show when the directed cut %s at %s ends,')
                                :format(e.dir_msg, at(e.dir_ppq))
            lines[#lines + 1] = ('             but %s at %s cuts that directed cut short first: the')
                                :format(e.next_msg, at(e.next_ppq))
            lines[#lines + 1] = ('             game lets it run %s when nothing cuts it'):format(Range(e.len))
            lines[#lines + 1] = '           - place the next camera event later, or delete this one'
        end
    end
    lines[#lines + 1] = ''

    if #f.directed_replaced == 0 then
        lines[#lines + 1] = 'Directed cuts right after a directed cut: none.'
    else
        lines[#lines + 1] = ('Directed cuts right after a directed cut (%d):'):format(#f.directed_replaced)
        for _, e in ipairs(f.directed_replaced) do
            lines[#lines + 1] = ('  %s   %s%s'):format(at(e.ppq), e.msg, ForLineups(e, nlineups))
            lines[#lines + 1] = ('           - does not play: the camera event before it is %s at %s,')
                                :format(e.prev_msg, at(e.prev_ppq))
            lines[#lines + 1] = e.plays
                and ('             so the game plays the stacked %s instead'):format(e.plays)
                or  '             so the game plays a generic band shot instead'
            lines[#lines + 1] = '           - put a normal camera event between the two directed cuts'
        end
    end
    lines[#lines + 1] = ''

    local n = #f.follow_early
    if n == 0 then
        lines[#lines + 1] = 'Shots after a directed cut that show early: none.'
    else
        lines[#lines + 1] = ('Shots after a directed cut that show early (%d, not counted as issues):')
                            :format(n)
        for k, e in ipairs(f.follow_early) do
            if list_max and k > list_max then
                lines[#lines + 1] = ('  ... and %d more. Narrow the time selection to see them.')
                                    :format(n - list_max)
                break
            end
            lines[#lines + 1] = ('  %s   %s%s'):format(at(e.ppq), e.msg, ForLineups(e, nlineups))
            lines[#lines + 1] = ('             - shows when the directed cut %s at %s ends (the game allows it %s)')
                                :format(e.dir_msg, at(e.dir_ppq), Range(e.len))
        end
        lines[#lines + 1] = '  The camera event right after a directed cut plays when that directed cut ends;'
        lines[#lines + 1] = '  its own position does not matter. Fine if that is the shot you want next.'
    end
    lines[#lines + 1] = ''

    return lines
end
