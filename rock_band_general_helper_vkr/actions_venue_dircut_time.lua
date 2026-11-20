-- Venue > Actions > Sub VENUE tracks: "Directed cut time", a view-only subtrack.
-- For every directed cut on VENUE it draws how long the cut may play. Which version
-- plays depends on the venue and the game's rotation, which a chart cannot choose,
-- so the notes show no one version, only the bounds over all of them:
--   longest note  - longest lead-in before the event to the longest run after it:
--                   the camera may be on this cut (every version lies inside it);
--   shortest note - shortest lead-in to the shortest run: the camera is on this cut
--                   whichever version plays (every version covers it), unless a
--                   camera event cuts it.
-- A note's two ends usually come from different versions (a long lead-in tends to
-- go with a short run after the hit). Each cut and the next two camera spots after
-- it are copied beside the notes as text events: the cut marks its hit, the first
-- spot names what plays when the directed shot ends, the second, at its own
-- position, is the latest the shot can be cut. Open the track in
-- the MIDI editor beside VENUE or a subtrack to see roughly where each directed cut
-- ends by itself while placing the next camera cut.
--
-- One way only: it is rebuilt from the directed cuts each time and never written
-- back to VENUE (Copy from / Copy all to main track leave it out).
-- Requires (at call time): RB_VENUE_SHOTS (lib/reaper_venue_shots.lua),
--   DirectedCutLength (venue_camera_timing.lua), VENUE_SUBTRACKS,
--   CategorizeVenueEvent, FindOrCreateSubtrack, EnsureMatchingItem
--   (actions_venue_subtracks.lua), FindTrackByName, FindNamedTrackMIDI,
--   VenueTargetName (actions_venue_manual.lua), r, S.
-- Globals exported: VENUE_DIRCUT_TIME, DIRCUT_TIME_NOTE_NAMES, VenueSubtrackOptions,
--   DirectedCutTimeNotes, DirectedCutFollowEvents (pure planners),
--   WriteDirectedCutTime (take-level writer),
--   FillDirectedCutTimeTrack, DirectedCutTimeLines (shared with Copy all to
--   subtracks), CopyDirectedCutTime (action).

VENUE_DIRCUT_TIME = {
    key = 'dircut_time', label = 'Directed cut time',
    track_name = 'VENUE directed cut time', view_only = true,
}

-- Two lanes, so a cut that starts before the previous one ends gets its own pitches
-- (two notes on one pitch cannot overlap in MIDI). A cut uses the first lane unless
-- it would overlap the note there, then the second.
local LANES = { { long = 0, short = 1 }, { long = 2, short = 3 } }

DIRCUT_TIME_NOTE_NAMES = {
    [0] = 'Directed cut: longest',
    [1] = 'Directed cut: shortest',
    [2] = 'Directed cut: longest (overlap)',
    [3] = 'Directed cut: shortest (overlap)',
}

-- The Sub VENUE tracks dropdown: the six subtracks, then this one.
function VenueSubtrackOptions()
    local opts = {}
    for i, cat in ipairs(VENUE_SUBTRACKS) do opts[i] = cat end
    opts[#opts + 1] = VENUE_DIRCUT_TIME
    return opts
end

local EPS = 1e-6

-- A copy of list sorted by time; events on one tick keep their order.
local function SortedBySec(list)
    local out = {}
    for i, c in ipairs(list) do out[i] = { c = c, i = i } end
    table.sort(out, function(a, b)
        if a.c.sec ~= b.c.sec then return a.c.sec < b.c.sec end
        return a.i < b.i
    end)
    for i, w in ipairs(out) do out[i] = w.c end
    return out
end

-- One cut's two notes in seconds, or nil when the cut is not in the shot table.
local function CutSpans(msg, sec)
    local name = msg:match('^%[(directed_[%w_]+)%]$')
    local ev   = name and RB_VENUE_SHOTS and RB_VENUE_SHOTS.events[name]
    local len  = ev and DirectedCutLength(msg)
    if not len then return nil end
    local lead = ev.lead or { 0, 0 }
    return { s = sec - lead[2], e = sec + len[2] },   -- longest
           { s = sec - lead[1], e = sec + len[1] }    -- shortest
end

-- cuts = { { sec =, msg = } } (any order). Directed cuts on one tick are one spot
-- that plays one of them, so a stack draws the widest longest note and the shortest
-- shortest note of its cuts.
-- Returns notes { { s =, e =, pitch =, msg = } } (seconds), unknown { msg = count },
-- trimmed (notes cut short because both lanes were still busy).
function DirectedCutTimeNotes(cuts)
    local sorted = SortedBySec(cuts)

    -- Group by tick, then one envelope per group.
    local spots, unknown = {}, {}
    for _, c in ipairs(sorted) do
        local long, short = CutSpans(c.msg, c.sec)
        if not long or not short then
            unknown[c.msg] = (unknown[c.msg] or 0) + 1
        else
            local last = spots[#spots]
            if last and math.abs(last.sec - c.sec) < EPS then
                last.long.s = math.min(last.long.s, long.s)
                last.long.e = math.max(last.long.e, long.e)
                if short.e - short.s < last.short.e - last.short.s then last.short = short end
                last.msg = last.msg .. ' ' .. c.msg
            else
                spots[#spots + 1] = { sec = c.sec, msg = c.msg, long = long, short = short }
            end
        end
    end

    local notes, trimmed = {}, 0
    local lane_notes = { {}, {} }   -- the notes last drawn on each lane
    local lane_end   = { -math.huge, -math.huge }
    for _, sp in ipairs(spots) do
        local cur = 1
        if sp.long.s < lane_end[1] - EPS then
            cur = 2
            if sp.long.s < lane_end[2] - EPS then
                -- Both lanes busy: the lane that frees first is cut at this start.
                cur = lane_end[1] <= lane_end[2] and 1 or 2
                for _, n in ipairs(lane_notes[cur]) do
                    if n.e > sp.long.s then
                        n.e = sp.long.s
                        trimmed = trimmed + 1
                    end
                end
            end
        end
        local lane = LANES[cur]
        local nl = { s = sp.long.s,  e = sp.long.e,  pitch = lane.long,  msg = sp.msg }
        local ns = { s = sp.short.s, e = sp.short.e, pitch = lane.short, msg = sp.msg }
        notes[#notes + 1] = nl
        notes[#notes + 1] = ns
        lane_notes[cur] = { nl, ns }
        lane_end[cur]   = sp.long.e
    end

    -- A note trimmed to nothing is dropped.
    local kept = {}
    for _, n in ipairs(notes) do
        if n.e - n.s > EPS then kept[#kept + 1] = n end
    end
    return kept, unknown, trimmed
end

-- The text events copied beside the notes (pure). camera = { { sec =, msg = } }
-- (directed and normal cuts, any order). For each known directed cut: the cut itself
-- (its event is the hit, where note 1 usually starts) and the two camera spots after
-- it. The first is the follow-up: it names the shot that plays when the directed shot
-- ends. The second, at its own position, is the latest the directed shot can be cut.
-- A directed cut's own spot gives only its directed events; a following spot gives
-- its whole stack. Returns each event once, in time order: { { sec =, msg = } }.
function DirectedCutFollowEvents(camera)
    local sorted = SortedBySec(camera)
    local spots = {}
    for _, c in ipairs(sorted) do
        local last = spots[#spots]
        if last and math.abs(last.sec - c.sec) < EPS then
            last.evs[#last.evs + 1] = c
        else
            spots[#spots + 1] = { sec = c.sec, evs = { c } }
        end
    end
    local take = {}   -- spot index -> 'all' or 'directed'
    for i, sp in ipairs(spots) do
        local directed = false
        for _, c in ipairs(sp.evs) do
            if CutSpans(c.msg, c.sec) then directed = true end   -- a known directed cut
        end
        if directed then
            take[i] = take[i] or 'directed'
            for j = i + 1, math.min(i + 2, #spots) do take[j] = 'all' end
        end
    end
    local out = {}
    for i, sp in ipairs(spots) do
        for _, c in ipairs(sp.evs) do
            if take[i] == 'all' or (take[i] == 'directed' and CutSpans(c.msg, c.sec)) then
                out[#out + 1] = c
            end
        end
    end
    return out
end

-- Clears dst_take's notes and draws the directed cuts of the src_takes (one take, or
-- the directed and normal camera subtracks) on it, plus each cut and the two camera
-- spots after it as text events. Notes are clipped to dst_item. Returns { cuts =, notes =,
-- unknown = { msg = n }, trimmed =, clipped =, follow = }.
function WriteDirectedCutTime(src_takes, dst_take, dst_item)
    local cuts, camera = {}, {}
    for _, src_take in ipairs(src_takes) do
        local _, _, _, text_count = r.MIDI_CountEvts(src_take)
        for i = 0, text_count - 1 do
            local ok, _, _, ppq, evtype, msg = r.MIDI_GetTextSysexEvt(src_take, i)
            local kind = ok and evtype == 1 and CategorizeVenueEvent(msg)
            if kind == 'directed' or kind == 'coop' then
                local ev = { sec = r.MIDI_GetProjTimeFromPPQPos(src_take, ppq), msg = msg }
                camera[#camera + 1] = ev
                if kind == 'directed' then cuts[#cuts + 1] = ev end
            end
        end
    end

    local _, note_count = r.MIDI_CountEvts(dst_take)
    for i = note_count - 1, 0, -1 do r.MIDI_DeleteNote(dst_take, i) end

    local notes, unknown, trimmed = DirectedCutTimeNotes(cuts)
    local item_s = r.GetMediaItemInfo_Value(dst_item, 'D_POSITION')
    local item_e = item_s + r.GetMediaItemInfo_Value(dst_item, 'D_LENGTH')
    local written, clipped = 0, 0
    for _, n in ipairs(notes) do
        local s, e = math.max(n.s, item_s), math.min(n.e, item_e)
        if s ~= n.s or e ~= n.e then clipped = clipped + 1 end
        if e - s > EPS then
            local sp = r.MIDI_GetPPQPosFromProjTime(dst_take, s)
            local ep = r.MIDI_GetPPQPosFromProjTime(dst_take, e)
            if ep > sp then
                r.MIDI_InsertNote(dst_take, false, false, sp, ep, 0, n.pitch, 100, false)
                written = written + 1
            end
        end
    end
    -- EnsureMatchingItem already cleared the take's text events.
    local follow = 0
    for _, ev in ipairs(DirectedCutFollowEvents(camera)) do
        if ev.sec >= item_s and ev.sec < item_e then
            r.MIDI_InsertTextSysexEvt(dst_take, false, false,
                r.MIDI_GetPPQPosFromProjTime(dst_take, ev.sec), 1, ev.msg, false)
            follow = follow + 1
        end
    end
    local unknown_n = 0
    for _, n in pairs(unknown) do unknown_n = unknown_n + n end
    return { cuts = #cuts - unknown_n, notes = written, unknown = unknown,
             trimmed = trimmed, clipped = clipped, follow = follow }
end

local function SetNoteNames(track)
    for pitch, name in pairs(DIRCUT_TIME_NOTE_NAMES) do
        r.SetTrackMIDINoteNameEx(0, track, pitch, -1, name)
    end
end

-- The view track, created after `anchor` when missing, filled from src_takes.
-- Call inside an undo block. Returns the WriteDirectedCutTime counts.
function FillDirectedCutTimeTrack(src_takes, venue_track, venue_item, anchor)
    local tr = FindOrCreateSubtrack(VENUE_DIRCUT_TIME, anchor, venue_track)
    SetNoteNames(tr)
    local item, take = EnsureMatchingItem(tr, venue_item)
    r.MarkTrackItemsDirty(tr, item)
    return WriteDirectedCutTime(src_takes, take, item)
end

-- Result lines for a fill, shared by Copy to and Copy all to subtracks.
function DirectedCutTimeLines(res)
    local lines = {}
    if res.follow > 0 then
        lines[#lines + 1] = ('%d camera event(s) copied as text: each directed cut and the ' ..
                             'next two spots after it.'):format(res.follow)
    end
    local names = {}
    for msg in pairs(res.unknown) do names[#names + 1] = msg end
    table.sort(names)
    if #names > 0 then
        lines[#lines + 1] = 'Not drawn (not a known directed cut): ' .. table.concat(names, ', ')
    end
    if res.trimmed > 0 then
        lines[#lines + 1] = ('%d note(s) cut short: three directed cuts overlap there.')
                            :format(res.trimmed)
    end
    if res.clipped > 0 then
        lines[#lines + 1] = ('%d note(s) clipped to the VENUE item.'):format(res.clipped)
    end
    return lines
end

-- "Copy to" with Directed cut time picked: reads the camera cuts from the tracks
-- Manual gen's Target names (VENUE, or "VENUE directed camera" + "VENUE normal
-- camera" with Subtracks), so it follows the tracks being edited.
function CopyDirectedCutTime()
    local venue_track, venue_item = FindNamedTrackMIDI('VENUE')
    if not venue_track then S.status = 'No VENUE track found.'; return end
    if not venue_item then S.status = 'No MIDI item on VENUE track.'; return end

    local src_takes, src_names = {}, {}
    for _, kind in ipairs({ 'directed', 'coop' }) do
        local name = VenueTargetName(kind)
        if not src_names[name] then
            local _, _, take = FindNamedTrackMIDI(name)
            if not take then
                S.status = ('No "%s" track with a MIDI item - use Copy all to subtracks first.')
                           :format(name)
                return
            end
            src_names[name] = true
            src_takes[#src_takes + 1] = take
        end
    end
    local src_name = VenueTargetName('directed')

    -- New track goes after the last existing subtrack (or VENUE).
    local anchor = venue_track
    for _, cat in ipairs(VENUE_SUBTRACKS) do
        local tr = FindTrackByName(cat.track_name)
        if tr then anchor = tr end
    end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    local res = FillDirectedCutTimeTrack(src_takes, venue_track, venue_item, anchor)
    r.Undo_EndBlock2(0, 'RB Draw directed cut time', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = ('Drew %d directed cut(s) from "%s" on "%s".')
               :format(res.cuts, src_name, VENUE_DIRCUT_TIME.track_name)
    local lines = DirectedCutTimeLines(res)
    S.last_result = #lines > 0 and table.concat(lines, '\n') or nil
end
