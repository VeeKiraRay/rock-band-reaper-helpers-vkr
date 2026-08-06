-- Lighting and keyframe event generation: section processing, themed and random modes.
-- Requires: BuildLightingPool, BuildPostprocPool, GetSectionPreset, FindTrackByName,
--           PickRandom, JitteredInterval, RB3_PHRASE_PITCH, r, S
--           (globals from venue_camera.lua and venue_themes.lua)
-- Globals exported: MANUAL_LIGHTING_SET, LIGHTING_DISPLAY_GROUPS,
--   LIGHTING_OFFSET_16THS, INST_KF_MODES,
--   KF_ALIGN_LABELS, FindNextMeasureStartPpq, CollectInstNotePositions,
--   CollectVocalPhraseStarts, GenerateKeyframesForSpan, GenerateLightingEvents,
--   GenerateThemedSectionEvents, KeyframeSubdivQN, SnapPpqToHalfBeat
--
-- Keyframe placement rule: [first] always lands on the SAME tick as the manual
-- lighting event it drives - it is that event's own initial keyframe. The
-- S.venue_keyframe_align modes below decide only where the FIRST [next] lands.

local MANUAL_LIGHTING_POOL = {
    '[lighting (verse)]', '[lighting (chorus)]',
    '[lighting (manual_cool)]', '[lighting (manual_warm)]',
    '[lighting (dischord)]', '[lighting (stomp)]',
}

local AUTO_LIGHTING_POOL = {
    '[lighting (loop_cool)]', '[lighting (loop_warm)]',
    '[lighting (harmony)]', '[lighting (frenzy)]',
    '[lighting (silhouettes)]', '[lighting (silhouettes_spot)]',
    '[lighting (searchlights)]', '[lighting (sweep)]',
    '[lighting (strobe_slow)]', '[lighting (strobe_fast)]',
    '[lighting (blackout_slow)]', '[lighting (blackout_fast)]', '[lighting (blackout_spot)]',
    '[lighting (flare_slow)]', '[lighting (flare_fast)]',
    '[lighting (bre)]',
}

MANUAL_LIGHTING_SET = {}
for _, v in ipairs(MANUAL_LIGHTING_POOL) do MANUAL_LIGHTING_SET[v] = true end

-- Combo display order for lighting: two groups, each alphabetical by label. The
-- manual/automatic split is functional - only the manual presets react to
-- [first]/[next] keyframes, and Manual gen gates its whole keyframe row on one
-- being selected - so alphabetising the 22 presets into a single list would bury
-- the one distinction that matters. Derived from the two pools above (bare names,
-- '[lighting (x)]' -> 'x') so this file stays the only place deciding which
-- presets are manual. LIGHTING_NAMES (venue_themes.lua) keeps its own order.
LIGHTING_DISPLAY_GROUPS = {}
do
    local function BareNames(pool)
        local out = {}
        for _, ev in ipairs(pool) do
            out[#out + 1] = ev:match('^%[lighting %((.-)%)%]$') or ev
        end
        return out
    end
    LIGHTING_DISPLAY_GROUPS = {
        { name = 'Manual (needs keyframes)',
          names = SortedByLabel(BareNames(MANUAL_LIGHTING_POOL), LIGHTING_LABELS) },
        { name = 'Automatic',
          names = SortedByLabel(BareNames(AUTO_LIGHTING_POOL),   LIGHTING_LABELS) },
    }
end

-- Keyframe alignment mode labels (S.venue_keyframe_align, 0-based - mode N is
-- KF_ALIGN_LABELS[N + 1]). Shared by every tab that draws the selector, so the
-- wording can't drift between them. Each label names where the first [next]
-- lands; [first] is always on the lighting event itself.
KF_ALIGN_LABELS = {
    'Keyframe rate only', 'Closest beat', 'Downbeat',
    'Guitar notes', 'Bass notes', 'Keys notes',
    'Drum kicks', 'Drum snare',
}

-- Instrument track info for keyframe alignment modes 3-7 (S.venue_keyframe_align).
INST_KF_MODES = {
    [3] = { track_name = 'PART GUITAR', pitch_min = 96, pitch_max = 100 },
    [4] = { track_name = 'PART BASS',   pitch_min = 96, pitch_max = 100 },
    [5] = { track_name = 'PART KEYS',   pitch_min = 96, pitch_max = 100 },
    [6] = { track_name = 'PART DRUMS',  pitch_min = 96, pitch_max = 96  },
    [7] = { track_name = 'PART DRUMS',  pitch_min = 97, pitch_max = 97  },
}

local LIGHTING_INTERVAL_16THS = 128   -- ~8 measures between lighting changes
local LIGHTING_JITTER         = 0.25  -- ±25% randomisation
LIGHTING_OFFSET_16THS         = 32    -- lighting starts 2 measures into range
local KEYFRAME_MIN_BEATS      = 1     -- manual lighting [next] min interval (beats)
local KEYFRAME_MAX_BEATS      = 4     -- manual lighting [next] max interval (beats)

-- ---------------------------------------------------------------------------

-- Converts S.venue_kf_inst_subdiv (0=every beat, 1=every half beat, 2=every quarter
-- beat) to a quarter-note fraction, for instrument-aware keyframe alignment (modes 3-7).
function KeyframeSubdivQN(mode)
    if mode == 2 then return 0.25 end
    if mode == 1 then return 0.5 end
    return 1.0
end

local function SnapPpqToNearestBeat(ppq_pos, ppq)
    return math.floor(ppq_pos / ppq + 0.5) * ppq
end

-- Half-beat snap - the grid venue_generator.lua's insert_text and
-- actions_venue_section.lua's insert_snapped apply to every non-keyframe event.
-- Keyframes are inserted unsnapped, so a [first] meant to share a lighting
-- event's tick has to be snapped here to match where that event will land.
-- Idempotent: re-snapping an already-snapped value returns it unchanged.
function SnapPpqToHalfBeat(ppq_pos, ppq)
    local half_beat = math.floor(ppq / 2 + 0.5)
    return math.floor(ppq_pos / half_beat + 0.5) * half_beat
end

-- Returns the PPQ position of the start of the NEXT measure after ppq_pos.
-- Scans forward from an estimate to find the first measure whose end exceeds ppq_pos.
function FindNextMeasureStartPpq(take, ppq_pos, ppq)
    local proj_time = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos)
    local qn        = r.TimeMap_timeToQN(proj_time)
    local est       = math.max(0, math.floor(qn / 4) - 1)
    for m = est, est + 30 do
        local _, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, m)
        if not qn_s then break end
        local t_e = r.TimeMap_QNToTime(qn_e)
        if t_e > proj_time + 1e-5 then
            return r.MIDI_GetPPQPosFromProjTime(take, t_e)
        end
    end
    return ppq_pos + 4 * ppq  -- fallback: one bar forward
end

-- Returns a sorted array of VENUE-take PPQ positions for notes in [pitch_min, pitch_max]
-- on the named instrument track that fall within [range_start_ppq, range_end_ppq).
-- Returns {} when the track or its MIDI item cannot be found.
function CollectInstNotePositions(track_name, pitch_min, pitch_max, venue_take,
                                        range_start_ppq, range_end_ppq)
    local inst_track = FindTrackByName(track_name)
    if not inst_track then return {} end
    local inst_take
    for i = 0, r.CountTrackMediaItems(inst_track) - 1 do
        local it = r.GetTrackMediaItem(inst_track, i)
        local tk = r.GetActiveTake(it)
        if tk and r.TakeIsMIDI(tk) then inst_take = tk; break end
    end
    if not inst_take then return {} end

    local start_t    = r.MIDI_GetProjTimeFromPPQPos(venue_take, range_start_ppq)
    local end_t      = r.MIDI_GetProjTimeFromPPQPos(venue_take, range_end_ppq)
    local inst_s_ppq = r.MIDI_GetPPQPosFromProjTime(inst_take, start_t)
    local inst_e_ppq = r.MIDI_GetPPQPosFromProjTime(inst_take, end_t)

    local positions   = {}
    local _, note_cnt = r.MIDI_CountEvts(inst_take)
    for i = 0, note_cnt - 1 do
        local ok, _, muted, sppq, _, _, pitch = r.MIDI_GetNote(inst_take, i)
        if ok and not muted and pitch >= pitch_min and pitch <= pitch_max
                and sppq >= inst_s_ppq and sppq < inst_e_ppq then
            local proj_t    = r.MIDI_GetProjTimeFromPPQPos(inst_take, sppq)
            local venue_ppq = r.MIDI_GetPPQPosFromProjTime(venue_take, proj_t)
            positions[#positions + 1] = venue_ppq
        end
    end
    table.sort(positions)
    return positions
end

-- Returns a sorted array of VENUE-take PPQ positions for PART VOCALS phrase-marker
-- (pitch 105, RB3_PHRASE_PITCH) note starts in [range_start_ppq, range_end_ppq). Thin
-- wrapper over CollectInstNotePositions with the phrase pitch pinned at both ends -
-- backs the "Vocal phrase start" camera pacing mode (venue_camera.lua).
function CollectVocalPhraseStarts(venue_take, range_start_ppq, range_end_ppq)
    return CollectInstNotePositions('PART VOCALS', RB3_PHRASE_PITCH, RB3_PHRASE_PITCH,
                                    venue_take, range_start_ppq, range_end_ppq)
end

-- Returns an array of {ppq, text} keyframe events ('[first]'/'[next]') for one manual-lighting
-- span [start_ppq, end_ppq), using the shared S.venue_keyframe_align / S.venue_kf_inst_subdiv
-- settings and the given rate in beats.
--
-- start_ppq IS the manual lighting event's own tick (both callers - the Keyframes tab's
-- per-span walk and Manual gen's playhead - guarantee that), so [first] always goes there.
-- In "Closest beat" mode the beat the sequence used to start on becomes the first [next]
-- instead; the other modes' [next] trains are unchanged.
function GenerateKeyframesForSpan(take, start_ppq, end_ppq, ppq, kf_rate_beats)
    local ctrl_events = {}
    local align    = S.venue_keyframe_align
    local kf_ticks = kf_rate_beats * ppq

    if align >= 3 and INST_KF_MODES[align] then
        local inst_info    = INST_KF_MODES[align]
        local inst_pos     = CollectInstNotePositions(
            inst_info.track_name, inst_info.pitch_min, inst_info.pitch_max,
            take, start_ppq, end_ppq)
        local subdiv_qn    = KeyframeSubdivQN(S.venue_kf_inst_subdiv)
        local subdiv_ticks = math.floor(subdiv_qn * ppq)

        ctrl_events[#ctrl_events + 1] = { ppq = start_ppq, text = '[first]' }

        local sec_qn    = r.TimeMap_timeToQN(r.MIDI_GetProjTimeFromPPQPos(take, start_ppq))
        local grid_qn   = math.ceil(sec_qn / subdiv_qn + 1e-6) * subdiv_qn
        local pos_ppq   = r.MIDI_GetPPQPosFromProjTime(take, r.TimeMap_QNToTime(grid_qn))
        local tolerance = math.floor(ppq / 32)
        local ni        = 1
        while pos_ppq < end_ppq do
            while ni <= #inst_pos and inst_pos[ni] < pos_ppq - tolerance do
                ni = ni + 1
            end
            if ni <= #inst_pos and inst_pos[ni] <= pos_ppq + tolerance then
                ctrl_events[#ctrl_events + 1] = { ppq = pos_ppq, text = '[next]' }
            end
            pos_ppq = pos_ppq + subdiv_ticks
        end
    else
        -- Standard modes 0-2
        -- Mode 1 ("Closest beat") snaps to the nearest beat; that position is now the
        -- first [next] rather than [first], which stays on the lighting event.
        local snap_ppq
        if align == 1 then
            snap_ppq = math.max(start_ppq, math.floor(start_ppq / ppq + 0.5) * ppq)
        else
            snap_ppq = start_ppq
        end

        local next_ppq
        if align == 2 then
            local nms = FindNextMeasureStartPpq(take, start_ppq, ppq)
            next_ppq  = nms < end_ppq and nms or nil
        else
            -- Anchor [next] to the nearest beat to the span start so the [next] grid lands on
            -- whole beats even when the lighting event is not beat-aligned (modes 0 & 1).
            local beat_anchor = math.floor(start_ppq / ppq + 0.5) * ppq
            next_ppq = beat_anchor + kf_ticks
        end

        if start_ppq < end_ppq then
            ctrl_events[#ctrl_events + 1] = { ppq = start_ppq, text = '[first]' }
        end
        if snap_ppq > start_ppq and snap_ppq < end_ppq then
            ctrl_events[#ctrl_events + 1] = { ppq = snap_ppq, text = '[next]' }
        end
        if next_ppq then
            local pos_ppq = next_ppq
            while pos_ppq < end_ppq do
                ctrl_events[#ctrl_events + 1] = { ppq = pos_ppq, text = '[next]' }
                pos_ppq = pos_ppq + kf_ticks
            end
        end
    end

    return ctrl_events
end

-- pool_override: use a specific pool instead of the combined MANUAL+AUTO default
function GenerateLightingEvents(range_16ths, ppq, pool_override)
    local sixteenth_ticks = ppq / 4
    local combined_pool
    if pool_override then
        combined_pool = pool_override
    else
        combined_pool = {}
        for _, v in ipairs(MANUAL_LIGHTING_POOL) do combined_pool[#combined_pool + 1] = v end
        for _, v in ipairs(AUTO_LIGHTING_POOL)   do combined_pool[#combined_pool + 1] = v end
    end

    local lt_events = {}
    local pos_16ths = 0
    local last_pick = nil

    while pos_16ths < range_16ths do
        local text = PickRandom(combined_pool, last_pick)
        last_pick = text
        lt_events[#lt_events + 1] = {
            tick      = math.floor(pos_16ths * sixteenth_ticks + 0.5),
            text      = text,
            pos_16ths = pos_16ths,
        }
        pos_16ths = pos_16ths + JitteredInterval(LIGHTING_INTERVAL_16THS, LIGHTING_JITTER)
    end

    local ctrl_events = {}
    for i, ev in ipairs(lt_events) do
        if MANUAL_LIGHTING_SET[ev.text] then
            local keyframe_16ths = math.random(KEYFRAME_MIN_BEATS, KEYFRAME_MAX_BEATS) * 4
            local end_16ths      = range_16ths
            if i < #lt_events then end_16ths = lt_events[i + 1].pos_16ths end

            local ctrl_pos = ev.pos_16ths
            local first    = true
            while ctrl_pos < end_16ths do
                ctrl_events[#ctrl_events + 1] = {
                    tick = math.floor(ctrl_pos * sixteenth_ticks + 0.5),
                    text = first and '[first]' or '[next]',
                }
                first    = false
                ctrl_pos = ctrl_pos + keyframe_16ths
            end
        end
    end

    return lt_events, ctrl_events
end

-- Resolves one section's theme picks without emitting anything, so the emit pass
-- can see each section's neighbours (see GenerateThemedSectionEvents). Returns nil
-- when the section falls outside the range or the theme has no preset for it.
--
-- blend_lt_ppq / blend_pp_ppq are where the PREVIOUS section's preset gets
-- re-stated to blend into this one - see BlendPpq.
local function ResolveThemeSection(sec, theme, take, range_start_ppq, range_end_ppq, ppq)
    local sec_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, sec.t_start)
    local sec_end_ppq   = r.MIDI_GetPPQPosFromProjTime(take, sec.t_end)
    if sec_start_ppq >= range_end_ppq or sec_end_ppq <= range_start_ppq then return nil end

    local preset = GetSectionPreset(theme, sec.name, sec.num)
    if not preset then return nil end

    local lt_pool = BuildLightingPool(preset)
    local pp_pool = BuildPostprocPool(preset)
    local sec_ppq = math.max(range_start_ppq, sec_start_ppq)

    return {
        sec_ppq      = sec_ppq,
        sec_end_ppq  = sec_end_ppq,
        lt_text      = (lt_pool and #lt_pool > 0) and lt_pool[math.random(#lt_pool)] or nil,
        pp_text      = (pp_pool and #pp_pool > 0) and pp_pool[math.random(#pp_pool)] or nil,
        kf_beats     = preset.keyframe_rate
                       or math.random(KEYFRAME_MIN_BEATS, KEYFRAME_MAX_BEATS),
        blend_lt_ppq = sec_ppq - (preset.lightpreset_blendin or 0) * ppq,
        blend_pp_ppq = sec_ppq - (preset.postproc_blendin    or 0) * ppq,
    }
end

-- Where the OUTGOING preset gets re-stated ahead of section `res`, or nil for none.
-- kind is 'lt' (lighting) or 'pp' (postproc).
--
-- This is what lightpreset_blendin / postproc_blendin actually mean: the incoming
-- section's own events never move off the section start (RB3 changes preset "when
-- this section begins" either way) - the blendin value only says how far ahead of
-- that the previously active preset is duplicated, giving the game something to
-- blend FROM instead of hard-cutting.
--
--   m3     [lighting (stomp)]  [ProFilm_a.pp]     <- previous section
--   m9 b3  [ProFilm_a.pp]                         <- duplicate, postproc_blendin 2
--   m9 b4  [lighting (stomp)]                     <- duplicate, lightpreset_blendin 1
--   m10    [lighting (verse)]  [ProFilm_b.pp]     <- this section, on its start
--
-- Returns nil when the preset isn't actually changing (nothing to blend), or when
-- the blend point would fall at or before the event it copies - a section shorter
-- than the next one's blendin, or a first section sitting on the song-start bookend,
-- would otherwise place the copy ahead of its own source.
--
-- prev.lt_ppq / prev.pp_ppq: where the source events actually sit, when the caller
-- knows them separately (Section gen reads them off the track). A resolved section
-- carries both at its own start, so prev.sec_ppq is the fallback for each.
local function BlendPpq(res, prev, range_start_ppq, kind)
    if not prev then return nil end
    local text      = prev[kind .. '_text']
    local blend_ppq = res['blend_' .. kind .. '_ppq']
    local src_ppq   = prev[kind .. '_ppq'] or prev.sec_ppq
    if not text or text == res[kind .. '_text'] then return nil end
    if blend_ppq >= res.sec_ppq or blend_ppq < range_start_ppq then return nil end
    if src_ppq and blend_ppq <= src_ppq then return nil end
    return blend_ppq
end

-- Emits the blend-anchor duplicates for section `res` (see BlendPpq above).
--
-- Deliberately keyframe-free, even for a manual preset: the duplicate restates a
-- preset that is already running, so it gets no [first] and the train from the
-- original event just carries on through it. See "only a preset CHANGE gets
-- [first]" in EmitThemeSection.
local function EmitBlendDuplicates(res, prev, range_start_ppq, lt_events, pp_events)
    if not prev then return end
    local blend_lt = BlendPpq(res, prev, range_start_ppq, 'lt')
    local blend_pp = BlendPpq(res, prev, range_start_ppq, 'pp')

    if blend_lt then
        lt_events[#lt_events + 1] = {
            tick = math.floor(blend_lt - range_start_ppq + 0.5),
            text = prev.lt_text,
        }
    end

    if blend_pp then
        pp_events[#pp_events + 1] = {
            tick = math.floor(blend_pp - range_start_ppq + 0.5),
            text = prev.pp_text,
        }
    end
end

-- Emits the lighting, keyframe control, and postproc events for one resolved
-- section. Tick offsets are from range_start_ppq.
--
-- `prev` is the preset state coming into this section - the previous resolved
-- section, or the caller-supplied `incoming` for the first one.
local function EmitThemeSection(res, prev, take, range_start_ppq, range_end_ppq,
                                ppq, lt_events, ctrl_events, pp_events, inst_note_positions)
    local sec_ppq = res.sec_ppq

    EmitBlendDuplicates(res, prev, range_start_ppq, lt_events, pp_events)

    if res.lt_text then
        -- The section's own preset lands exactly ON the section start - a blendin
        -- never moves it, it only adds the duplicate above (RB3 cuts to the preset
        -- "when this section begins" either way).
        lt_events[#lt_events + 1] = {
            tick = math.floor(sec_ppq - range_start_ppq + 0.5), text = res.lt_text }

        if MANUAL_LIGHTING_SET[res.lt_text] then
            local kf_end = math.min(range_end_ppq, res.sec_end_ppq)
            local align  = S.venue_keyframe_align

            -- Only a preset CHANGE starts a keyframe sequence. A section that keeps
            -- the preset already running gets no [first] - the train from the event
            -- that did start it carries straight on through this boundary. Same rule
            -- the blend duplicates follow (EmitBlendDuplicates) and the one the
            -- Keyframes tab re-derives from the track (RegenerateVenueKeyframes), so
            -- generating and regenerating agree.
            --
            -- Where it is emitted, [first] shares the lighting event's tick - it is
            -- that event's own initial keyframe. Snapped to the half-beat grid the
            -- callers will snap the lighting event onto (keyframes themselves go in
            -- unsnapped), so the two land on exactly the same tick.
            local first_kf_ppq = SnapPpqToHalfBeat(sec_ppq, ppq)
            local changes      = not (prev and prev.lt_text == res.lt_text)
            if changes and first_kf_ppq < kf_end then
                ctrl_events[#ctrl_events + 1] = {
                    tick = math.floor(first_kf_ppq - range_start_ppq + 0.5),
                    text = '[first]',
                }
            end

            if align >= 3 and inst_note_positions then
                -- Instrument-aware mode: [next] only at beat or half-beat grid positions
                -- that have at least one qualifying note. The section start gets no
                -- keyframe of its own - every [next] here is backed by a real note.
                local subdiv_qn    = KeyframeSubdivQN(S.venue_kf_inst_subdiv)
                local subdiv_ticks = math.floor(subdiv_qn * ppq)
                -- Find the first beat/half-beat grid line strictly after sec_ppq.
                -- Uses the tempo map so sparse marker projects and off-beat section
                -- starts are all handled correctly (same pattern as FindNextMeasureStartPpq).
                local sec_proj_t = r.MIDI_GetProjTimeFromPPQPos(take, sec_ppq)
                local sec_qn     = r.TimeMap_timeToQN(sec_proj_t)
                local grid_qn    = math.ceil(sec_qn / subdiv_qn + 1e-6) * subdiv_qn
                local grid_t     = r.TimeMap_QNToTime(grid_qn)
                local pos_ppq    = r.MIDI_GetPPQPosFromProjTime(take, grid_t)
                local tolerance  = math.floor(ppq / 32)  -- ~30 ticks at ppq 960
                local ni         = 1
                while pos_ppq < kf_end do
                    -- Exact match: note must be within tolerance of the grid line,
                    -- not just anywhere in the subdivision interval.
                    while ni <= #inst_note_positions
                          and inst_note_positions[ni] < pos_ppq - tolerance do
                        ni = ni + 1
                    end
                    if ni <= #inst_note_positions
                          and inst_note_positions[ni] <= pos_ppq + tolerance then
                        ctrl_events[#ctrl_events + 1] = {
                            tick = math.floor(pos_ppq - range_start_ppq + 0.5),
                            text = '[next]',
                        }
                    end
                    pos_ppq = pos_ppq + subdiv_ticks
                end
            else
                -- Standard modes 0-2: use theme keyframe_rate (or random) for [next] spacing
                local kf_ticks = res.kf_beats * ppq

                -- Anchor for the [next] train: section start, or snapped to the nearest
                -- beat (mode 1). Mode 1's snapped beat is the one case where the anchor
                -- differs from the lighting event's own tick, and it becomes the first
                -- [next] rather than the [first].
                local anchor_ppq
                if align == 1 then
                    anchor_ppq = math.max(sec_ppq, SnapPpqToNearestBeat(sec_ppq, ppq))
                else
                    anchor_ppq = sec_ppq
                end

                -- [next] start: downbeat mode begins from next measure boundary (mode 2)
                local next_ppq
                if align == 2 then
                    local nms = FindNextMeasureStartPpq(take, sec_ppq, ppq)
                    next_ppq  = nms < kf_end and nms or nil
                else
                    next_ppq = anchor_ppq + kf_ticks
                end

                -- Skipped in every mode but 1, where the anchor IS the lighting
                -- event's tick and [first] is already there.
                if anchor_ppq < kf_end and anchor_ppq > first_kf_ppq then
                    ctrl_events[#ctrl_events + 1] = {
                        tick = math.floor(anchor_ppq - range_start_ppq + 0.5),
                        text = '[next]',
                    }
                end
                if next_ppq then
                    local pos_ppq = next_ppq
                    while pos_ppq < kf_end do
                        ctrl_events[#ctrl_events + 1] = {
                            tick = math.floor(pos_ppq - range_start_ppq + 0.5),
                            text = '[next]',
                        }
                        pos_ppq = pos_ppq + kf_ticks
                    end
                end
            end
        end
    end

    if res.pp_text then
        -- Same rule as lighting: the section's own postproc lands on the section start.
        pp_events[#pp_events + 1] = {
            tick = math.floor(sec_ppq - range_start_ppq + 0.5), text = res.pp_text }
    end
end

-- `incoming` (optional): the preset state already active going into the first
-- section, as { lt_text, pp_text, sec_ppq, kf_beats } - Themes gen passes the
-- forced song-start bookend, Section gen passes what it read off the VENUE track
-- (FindActiveVenuePresetsBefore). Without it the first section gets no blend
-- duplicates, since there is nothing known to blend out of.
function GenerateThemedSectionEvents(sections, theme, take,
                                     range_start_ppq, range_end_ppq, ppq, incoming)
    local lt_events   = {}
    local ctrl_events = {}
    local pp_events   = {}

    -- Pre-compute instrument note positions once for instrument-aware modes (3-7)
    local inst_note_positions = nil
    local inst_info = INST_KF_MODES[S.venue_keyframe_align]
    if inst_info then
        inst_note_positions = CollectInstNotePositions(
            inst_info.track_name, inst_info.pitch_min, inst_info.pitch_max,
            take, range_start_ppq, range_end_ppq)
    end

    -- Pass 1: resolve every section's picks up front - emitting a section needs the
    -- PREVIOUS one's preset, both to duplicate into the blend zone and to tell whether
    -- this section actually changes the preset (only a change starts a keyframe run).
    local resolved = {}
    for _, sec in ipairs(sections) do
        local res = ResolveThemeSection(sec, theme, take, range_start_ppq, range_end_ppq, ppq)
        if res then resolved[#resolved + 1] = res end
    end

    -- Pass 2: emit.
    for i, res in ipairs(resolved) do
        EmitThemeSection(res, resolved[i - 1] or (i == 1 and incoming or nil),
                         take, range_start_ppq, range_end_ppq, ppq,
                         lt_events, ctrl_events, pp_events, inst_note_positions)
    end
    return lt_events, ctrl_events, pp_events
end
