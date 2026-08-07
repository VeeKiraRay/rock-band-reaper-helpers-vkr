-- MIDI converter: raw guitar pitches -> Rock Band Expert Guitar gems
-- Requires: S, r, GetTimeSelection, FindFirstMIDIItem, InsertNotes, PitchName (globals)

-- Expert Guitar gem pitches: 96=Green, 97=Red, 98=Yellow, 99=Blue, 100=Orange
GEM_MIN     = 96
GEM_MAX     = 100
GEM_LETTERS = { [0]='G', [1]='R', [2]='Y', [3]='B', [4]='O' }

-- Notes within this window (seconds) are grouped as a single chord event
CHORD_WINDOW_S = 0.010  -- 10 ms

----------------------------------------------------------------------
-- Source MIDI reading
----------------------------------------------------------------------

local function ReadGuitarMIDI(track, t_s, t_e)
    local notes = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            local _, notecnt = r.MIDI_CountEvts(take)
            for j = 0, notecnt - 1 do
                local ok, _, muted, sppq, eppq, _, pitch, vel = r.MIDI_GetNote(take, j)
                if ok and not muted then
                    local s = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
                    local e = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
                    if (not t_s or s >= t_s - 0.001) and (not t_e or s < t_e + 0.001) then
                        notes[#notes + 1] = { s = s, e = e, pitch = pitch, vel = vel }
                    end
                end
            end
        end
    end
    table.sort(notes, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.pitch < b.pitch
    end)
    return notes
end

-- Group simultaneous notes (within CHORD_WINDOW_S) into chord events.
-- Returns events[]: {s, e, pitches[] sorted ascending}
local function GroupIntoEvents(notes)
    local events = {}
    local i = 1
    while i <= #notes do
        local ev = { s = notes[i].s, e = notes[i].e, pitches = { notes[i].pitch } }
        i = i + 1
        while i <= #notes and (notes[i].s - ev.s) <= CHORD_WINDOW_S do
            ev.pitches[#ev.pitches + 1] = notes[i].pitch
            if notes[i].e > ev.e then ev.e = notes[i].e end
            i = i + 1
        end
        table.sort(ev.pitches)
        events[#events + 1] = ev
    end
    return events
end

----------------------------------------------------------------------
-- Tempo helper
----------------------------------------------------------------------

function GetBPMAt(time)
    local tidx = r.FindTempoTimeSigMarker(0, time)
    if tidx >= 0 then
        local ok, _, _, _, bpm = r.GetTempoTimeSigMarker(0, tidx)
        if ok and bpm and bpm > 0 then return bpm end
    end
    return 120
end

----------------------------------------------------------------------
-- Gem assignment helpers
----------------------------------------------------------------------

-- Keep at most max_chord pitches: lowest + best middle + highest.
-- Pitches must be sorted ascending.
function CompressChord(pitches, max_chord)
    if #pitches <= max_chord then return pitches end
    if max_chord == 1 then return { pitches[1] } end
    if max_chord == 2 then return { pitches[1], pitches[#pitches] } end
    local mid = math.floor(#pitches / 2) + 1
    return { pitches[1], pitches[mid], pitches[#pitches] }
end

-- True when a 3-note chord has both Green (pos 0) and Orange (pos 4) - illegal per authoring rules.
local function IsIllegalGO(gems)
    return #gems == 3 and gems[1] == 0 and gems[3] == 4
end

function GemLabel(gems)
    local parts = {}
    for _, g in ipairs(gems) do parts[#parts + 1] = GEM_LETTERS[g] end
    return '[' .. table.concat(parts, '+') .. ']'
end

function PitchLabel(pitches)
    local parts = {}
    for _, p in ipairs(pitches) do parts[#parts + 1] = PitchName(p) end
    return table.concat(parts, '+')
end

function ChordTypeName(gems)
    if #gems == 1 then return 'single' end
    if #gems == 2 then
        local names = { [1]='1-2 chord', [2]='1-3 chord', [3]='1-4 chord', [4]='1-5 chord' }
        return names[gems[2] - gems[1]] or 'chord'
    end
    return '3-note chord'
end

----------------------------------------------------------------------
-- Gem assignment pools (shared by AssignGems and AssignGemsForGuide)
----------------------------------------------------------------------

-- Each sub-table is a gem combo ranked from smallest spread to largest.
-- For 2-note chords, pool starts with 1-2 entries so lower-pitch shapes
-- get adjacent gems first, maximising chord differentiation.
POOLS = {
    [1] = {{0},{1},{2},{3},{4}},
    [2] = {{0,1},{0,2},{1,2},{0,3},{1,3},{2,3},{1,4},{2,4},{3,4}},
    [3] = {{0,1,2},{0,1,3},{0,2,3},{1,2,3},{1,2,4},{1,3,4},{2,3,4}},
}

-- Pool for 2-note chords when allow_14 is off: spread ≤ 2 only (7 entries).
POOLS2_NO14 = {{0,1},{0,2},{1,2},{1,3},{2,3},{2,4},{3,4}}

----------------------------------------------------------------------
-- Shared shape -> gem-combo map (used by AssignGems and AssignGemsForGuide)
----------------------------------------------------------------------

-- combo[2]-combo[1] (lane-index spread) -> the sub-list of pool2 entries
-- with that spread, in their original relative order.
local function PoolByWidth(pool2)
    local by_width = {}
    for _, combo in ipairs(pool2) do
        local spread = combo[2] - combo[1]
        by_width[spread] = by_width[spread] or {}
        table.insert(by_width[spread], combo)
    end
    return by_width
end

-- GuitarSuggestRBMapping's width strings (lib/reaper_guitar_theory.lua) ->
-- lane-index spread.
local WIDTH_TO_SPREAD = { ['1-2'] = 1, ['1-3'] = 2, ['1-4'] = 3, ['1-5'] = 4 }

local function shape_key(sorted_pitches)
    local t = {}
    for _, p in ipairs(sorted_pitches) do t[#t + 1] = p end
    return table.concat(t, ',')
end

-- Ascending copy of an event's pitches, optionally compressed first.
-- The copy matters: CompressChord returns its ARGUMENT unchanged when the
-- chord already fits (and is skipped entirely when max_chord is nil), so
-- sorting the result in place would reorder the caller's own ev.pitches -
-- which the guide/converter reports then print via PitchLabel. Tab input
-- arrives in string order (low E first), and that's how it should read
-- back in the report, next to the tab line it came from.
function SortedChordPitches(pitches, max_chord)
    local src = max_chord and CompressChord(pitches, max_chord) or pitches
    local out = {}
    for i, p in ipairs(src) do out[i] = p end
    table.sort(out)
    return out
end

-- '  [Perfect fifth (power chord)]' for a recognized shape, else '' -
-- appended to a Phase-2 reason string so the report shows *why* a
-- particular combo was chosen, not just the combo itself. Works on any
-- pitch count: GuitarClassifyChordType is pitch-class based, so it
-- correctly names e.g. a 3-physical-note power chord (root+5th+octave) the
-- same as a literal 2-note one, and also names real 3+-pitch-class chords
-- (Major triad, Sus4, ...) when GUITAR_CHORD_TEMPLATES matches.
function ChordQualityLabel(pitches)
    local type_name = GuitarClassifyChordType(pitches)
    if type_name and type_name ~= 'Single note' and type_name ~= 'No notes'
       and not type_name:match('^Unrecognized') then
        return '  [' .. type_name .. ']'
    end
    return ''
end

local function sort_by_pitch(order, all_shapes)
    table.sort(order, function(a, b)
        local sa, sb = all_shapes[a], all_shapes[b]
        if sa.max ~= sb.max then return sa.max < sb.max end
        return sa.avg < sb.avg
    end)
end

-- Safety cap for the conflict-minimizing search in AssignByConflict below.
-- That search is roughly O(pool_size x distinct shapes) for typical songs
-- (a given shape usually only neighbors a handful of others), but can
-- approach O(pool_size x N^2) in the worst case (N = distinct shapes in
-- one group) if the adjacency pattern is densely interconnected. A real
-- guitar song's distinct-shape count per group stays in the
-- tens-to-low-hundreds even for long, harmonically dense material - this
-- cap sits comfortably above that. The realistic way to exceed it is
-- pointing the Guitar tab converter at the wrong source track (e.g. a
-- drum track, or anything not shaped like a guitar part), producing a
-- large near-random shape vocabulary - REAPER scripts run single-threaded
-- and blocking, so an uncapped O(N^2) search there would visibly freeze
-- the UI. Past this cap, AssignByConflict falls back to plain
-- clamp-to-last (O(N), no adjacency scoring) so worst-case runtime stays
-- bounded no matter how large or tangled the input gets. Hardcoded for
-- now; if real songs ever legitimately need more, this can become a
-- user-facing setting later.
local MAX_CONFLICT_SHAPES = 200

-- Assigns combos to `order` (already pitch-sorted, low to high) from
-- `list`. If there's a combo for every distinct shape (#order <= #list),
-- each gets a unique one - zero conflicts, no search needed. Otherwise
-- (overflow), the first #list shapes (lowest pitch) each claim a unique
-- combo, exactly as above; every remaining (higher-pitched) shape reuses
-- whichever already-claimed combo minimizes conflicts against shapes it's
-- actually adjacent to ANYWHERE in the passage (`adjacency`, built from
-- the real event sequence - see BuildShapeGemMap), so two chords that are
-- genuinely back-to-back never end up looking identical unless truly
-- unavoidable. Ties broken toward the top of the pool (a shape reaching
-- this branch is, by construction, higher-pitched than every claimer, so
-- prefers staying near the "Orange end"); further ties broken by the
-- earliest slot index, for determinism. A bounded refinement pass (up to
-- 3 sweeps, stopping early once a sweep changes nothing) then lets the
-- overflow shapes re-settle using full information, now that every shape
-- has an initial combo - the forward pass alone only sees earlier
-- shapes' choices. Claimed (non-overflow) shapes are never reassigned.
-- Marks every shape that didn't claim one of the first #list unique slots
-- in `shared` (key -> true) - the original claimant is never flagged.
-- Above MAX_CONFLICT_SHAPES distinct shapes, skips the search entirely
-- (see its own comment above).
local function AssignByConflict(order, list, adjacency, shape_gems, shared)
    local N, M = #order, #list
    local cur_idx = {}   -- key -> currently assigned index into `list`

    for rank = 1, math.min(N, M) do
        cur_idx[order[rank]] = rank
    end

    if N > M and N > MAX_CONFLICT_SHAPES then
        for rank = M + 1, N do
            local key = order[rank]
            cur_idx[key] = M
            shared[key] = true
        end
    elseif N > M then
        local function score(key, c)
            local total, neighbors = 0, adjacency[key]
            if neighbors then
                for other, w in pairs(neighbors) do
                    if cur_idx[other] == c then total = total + w end
                end
            end
            return total
        end

        local function best_index(key)
            local best_c, best_score, best_dist
            for c = 1, M do
                local s, dist = score(key, c), M - c
                if not best_score or s < best_score
                   or (s == best_score and dist < best_dist) then
                    best_c, best_score, best_dist = c, s, dist
                end
            end
            return best_c
        end

        for rank = M + 1, N do
            local key = order[rank]
            cur_idx[key] = best_index(key)
            shared[key] = true
        end

        for _ = 1, 3 do
            local changed = false
            for rank = M + 1, N do
                local key    = order[rank]
                local better = best_index(key)
                if better ~= cur_idx[key] and score(key, better) < score(key, cur_idx[key]) then
                    cur_idx[key] = better
                    changed = true
                end
            end
            if not changed then break end
        end
    end

    for _, key in ipairs(order) do
        shape_gems[key] = list[cur_idx[key]]
    end
end

-- Build a single global shape -> gem-combo map across the whole event list.
-- All distinct compressed chord shapes are collected and assigned gem
-- combos:
--
-- - 1-note shapes: unchanged, evenly spread across gems 0-4.
-- - 2+-note shapes: each is classified by GuitarSuggestRBMapping
--   (lib/reaper_guitar_theory.lua), which is PITCH-CLASS based, not
--   physical-note-count based - a shape with 3 physical notes but only 2
--   distinct pitch classes (e.g. a power chord voiced as root+5th+octave,
--   like "5 7 7 x x x") is recognized as a dyad and assigned the SAME
--   2-gem combo a literal 2-note power chord would get, dropping the
--   redundant note from the gem output entirely - this is what real RB
--   charts do, and is the exact case the reference table in
--   rock_band_music_theory_helper_vkr's GUITAR_CHORDS documents (that
--   shape's rb_mapping is '1-3', not a 3-note chord). A genuine compound
--   interval (>1 octave) gets GuitarSuggestRBMapping's deterministic 'GO'
--   combo directly. Shapes that resolve to a recognized width are
--   rank-cycled within that width's matching combos (for differentiation
--   across multiple same-quality shapes); shapes GuitarSuggestRBMapping
--   can't narrow (unrecognized 2-pitch-class intervals, the ambiguous
--   perfect-fourth case, or genuine 3+-pitch-class chords like a real
--   triad) fall back to the original per-physical-size pool cycling,
--   unchanged from before this classification existed.
--
-- When the number of distinct shapes in a group exceeds the group's combo
-- list size, combos are assigned by conflict-minimizing search (see
-- AssignByConflict above), using the shapes' real adjacency in the played
-- sequence - two shapes that are genuinely back-to-back anywhere in the
-- passage only end up with the same combo when it's truly unavoidable
-- (more distinct shapes in the group than that group has combos for).
-- Returns all_shapes (key -> {avg,max,sz,pitches}), shape_gems (key -> gem
-- combo, global, never reset by gaps between notes), shared (key -> true
-- for any shape that had to reuse another shape's combo in its group).
--
-- max_chord/allow_14 are passed in rather than read from S, because the two
-- callers are not governed by the same settings. AssignGems (Guitar tab
-- converter) passes S.mc_gtr_max_chord/S.mc_gtr_allow_14, its own UI
-- controls. AssignGemsForGuide (Tab Input guide) passes max_chord=nil (no
-- compression at all) and allow_14=true: the Tab Input tab exposes neither
-- control, writes nothing to the project, and exists to report the same
-- answer the Music Theory helper's Shape Search gives - which classifies
-- the full chord by pitch class and never truncates it. Reading S here
-- instead let the WIP Guitar tab's settings silently steer the shipped
-- guide's output.
function BuildShapeGemMap(events, max_chord, allow_14)
    local all_shapes  = {}   -- key -> {avg, max, sz, pitches}
    local size_orders = {}   -- sz -> [keys in first-seen order, sorted later]

    for _, ev in ipairs(events) do
        local pitches = SortedChordPitches(ev.pitches, max_chord)
        local sz  = #pitches
        local key = shape_key(pitches)
        if not all_shapes[key] then
            local sum = 0
            for _, p in ipairs(pitches) do sum = sum + p end
            all_shapes[key] = { avg = sum / sz, max = pitches[sz], sz = sz, pitches = pitches }
            if not size_orders[sz] then size_orders[sz] = {} end
            size_orders[sz][#size_orders[sz] + 1] = key
        end
    end

    local pool2      = allow_14 and POOLS[2] or POOLS2_NO14
    local pool2_by_w = PoolByWidth(pool2)
    local shape_gems = {}   -- key -> gem combo (global, never reset)
    local shared     = {}   -- key -> true when its combo is shared with another shape

    local sizes = {}
    for sz in pairs(size_orders) do sizes[#sizes + 1] = sz end
    table.sort(sizes)

    -- 1-note shapes: unchanged.
    if size_orders[1] then
        local order = size_orders[1]
        sort_by_pitch(order, all_shapes)
        local N = #order
        for rank, key in ipairs(order) do
            local gem = N == 1 and 0 or math.min(4, math.floor((rank - 1) * 4 / (N - 1) + 0.5))
            shape_gems[key] = { gem }
        end
    end

    -- 2+-note shapes: classify by real (pitch-class) width first, across
    -- ALL physical sizes, so a 3-physical-note power chord and a literal
    -- 2-note one share the same width-bucketed combo pool. Anything that
    -- doesn't resolve to a recognized width falls through to a per-size
    -- fallback bucket (sz==2 -> unconstrained pool2 cycling; sz>=3 -> that
    -- size's own POOLS entry), exactly as before this classification.
    local by_width      = {}   -- spread -> [keys], shared across all sizes
    local fallback_2    = {}   -- sz==2, no principled width
    -- Bucketed by min(sz,3), not raw sz: every shape with 3+ notes draws
    -- from POOLS[3] regardless of how many notes it actually has, so they
    -- must all compete in ONE AssignByConflict group. Keyed by raw sz, a
    -- 4-note and a 6-note shape would be assigned independently from the
    -- same 7 combos and could collide without being flagged (*Wrap).
    -- Only reachable since the Tab Input guide stopped compressing - the
    -- converter path caps sz at max_chord, so sz never exceeded 3 before.
    local fallback_3    = {}   -- min(sz,3) -> [keys], sz>=3, no principled width
    local key_to_group  = {}   -- key -> group id string, for adjacency below

    for _, sz in ipairs(sizes) do
        if sz >= 2 then
            local order = size_orders[sz]
            sort_by_pitch(order, all_shapes)
            for _, key in ipairs(order) do
                local pitches = all_shapes[key].pitches
                local width, combo = GuitarSuggestRBMapping(pitches)
                if combo == 'GO' then
                    shape_gems[key] = { 0, 4 }
                else
                    local spread = width and WIDTH_TO_SPREAD[width]
                    if spread and pool2_by_w[spread] and #pool2_by_w[spread] > 0 then
                        by_width[spread] = by_width[spread] or {}
                        by_width[spread][#by_width[spread] + 1] = key
                        key_to_group[key] = 'w' .. spread
                    elseif sz == 2 then
                        fallback_2[#fallback_2 + 1] = key
                        key_to_group[key] = 'f2'
                    else
                        local bucket = math.min(sz, 3)
                        fallback_3[bucket] = fallback_3[bucket] or {}
                        fallback_3[bucket][#fallback_3[bucket] + 1] = key
                        key_to_group[key] = 'f3:' .. bucket
                    end
                end
            end
        end
    end

    -- Adjacency: for each pair of consecutive events with DIFFERENT
    -- shapes in the SAME group, count how many times that pair is
    -- actually back-to-back in the passage - feeds AssignByConflict's
    -- conflict-minimizing search below. Cross-group adjacency (e.g. a
    -- dyad immediately followed by a real triad) isn't tracked - those
    -- shapes never compete for the same combo list anyway.
    local adjacency = {}   -- key -> { other_key -> count }
    local prev_key
    for _, ev in ipairs(events) do
        local key = shape_key(SortedChordPitches(ev.pitches, max_chord))
        if prev_key and prev_key ~= key then
            local g1, g2 = key_to_group[prev_key], key_to_group[key]
            if g1 and g1 == g2 then
                adjacency[prev_key] = adjacency[prev_key] or {}
                adjacency[prev_key][key] = (adjacency[prev_key][key] or 0) + 1
                adjacency[key] = adjacency[key] or {}
                adjacency[key][prev_key] = (adjacency[key][prev_key] or 0) + 1
            end
        end
        prev_key = key
    end

    for spread = 1, 4 do
        local keys = by_width[spread]
        if keys then
            sort_by_pitch(keys, all_shapes)
            AssignByConflict(keys, pool2_by_w[spread], adjacency, shape_gems, shared)
        end
    end
    AssignByConflict(fallback_2, pool2, adjacency, shape_gems, shared)
    for bucket, keys in pairs(fallback_3) do
        sort_by_pitch(keys, all_shapes)
        AssignByConflict(keys, POOLS[bucket] or POOLS[1], adjacency, shape_gems, shared)
    end

    return all_shapes, shape_gems, shared
end

----------------------------------------------------------------------
-- Gem assignment: main algorithm
----------------------------------------------------------------------

-- Shape-based algorithm:
--
-- Phase 1 (global map building):
--   BuildShapeGemMap collects all distinct compressed chord shapes across
--   the entire event list and assigns each a gem combo (see its own doc
--   comment above). Gaps between notes do NOT reset assignments.
--
-- Phase 2 (output):
--   Walk events in order, emitting gem assignments using the global shape map.
--   Gaps > wrap_gap_s are annotated as phrase boundaries in the report only.
--
-- Returns assignments[]: each entry is either:
--   { s, e, gems[], reason, is_meta=false }  - a real gem event
--   { s, reason, is_meta=true }              - phrase/wrap annotation
local function AssignGems(events, wrap_gap_s, max_chord)
    if #events == 0 then return {} end

    local all_shapes, shape_gems, shared = BuildShapeGemMap(events, max_chord, S.mc_gtr_allow_14)

    -- Phrase ranges: for report annotations only - do NOT reset gem assignments
    local phrase_ranges = {}
    local cur_start     = 1
    local prev_e        = -1

    for i = 1, #events do
        local ev = events[i]
        if i > 1 and prev_e >= 0 and (ev.s - prev_e) > wrap_gap_s then
            phrase_ranges[#phrase_ranges + 1] = { i_s = cur_start, i_e = i - 1 }
            cur_start = i
        end
        prev_e = ev.e
    end
    phrase_ranges[#phrase_ranges + 1] = { i_s = cur_start, i_e = #events }

    -- Build per-phrase header strings using globally-assigned gems
    local phrase_headers = {}
    for _, pr in ipairs(phrase_ranges) do
        local seen       = {}
        local seen_order = {}
        for i = pr.i_s, pr.i_e do
            local key = shape_key(SortedChordPitches(events[i].pitches, max_chord))
            if not seen[key] then
                seen[key] = true
                seen_order[#seen_order + 1] = key
            end
        end
        table.sort(seen_order, function(a, b)
            local sa, sb = all_shapes[a], all_shapes[b]
            if sa.max ~= sb.max then return sa.max < sb.max end
            return sa.avg < sb.avg
        end)
        local parts = {}
        for _, key in ipairs(seen_order) do
            local pitch_parts = {}
            for _, p in ipairs(all_shapes[key].pitches) do
                pitch_parts[#pitch_parts + 1] = PitchName(p)
            end
            parts[#parts + 1] = table.concat(pitch_parts, '+') .. '\xe2\x86\x92' .. GemLabel(shape_gems[key])
        end
        phrase_headers[#phrase_headers + 1] = table.concat(parts, '  ')
    end

    -- Phase 2: emit assignments ------------------------------------------
    local assignments = {}
    local pi          = 1
    local prev_ev_end = -1
    local prev_gems   = nil

    for i, ev in ipairs(events) do
        local pr = phrase_ranges[pi]

        if i == pr.i_s then
            prev_gems = nil
            local gap_s = (prev_ev_end >= 0) and (ev.s - prev_ev_end) or 0
            local meta_reason
            if prev_ev_end >= 0 and gap_s > wrap_gap_s then
                meta_reason = string.format(
                    'Phrase  gap=%.0f ms  %s',
                    gap_s * 1000, phrase_headers[pi])
            else
                meta_reason = 'Phrase start  ' .. phrase_headers[pi]
            end
            assignments[#assignments + 1] = { s = ev.s, reason = meta_reason, is_meta = true }
        end

        local pitches = SortedChordPitches(ev.pitches, max_chord)
        local n_orig = #ev.pitches
        local key    = shape_key(pitches)
        local src    = shape_gems[key]
        local gems   = {}
        for _, g in ipairs(src) do gems[#gems + 1] = g end

        local go_fixed = false
        if IsIllegalGO(gems) then
            gems     = { gems[1], gems[3] }
            go_fixed = true
        end

        -- Prefer R+O over G+O for playability.
        -- G+O is a full-fretboard stretch; R+O lets the player hold the lower finger from
        -- the previous note. Only keep G+O when prev note was at Green (hand already there).
        local go_subst = false
        if #gems == 2 and gems[1] == 0 and gems[2] == 4 then
            local prev_at_green = prev_gems and #prev_gems == 1 and prev_gems[1] == 0
            if not prev_at_green then
                gems     = { 1, 4 }  -- R+O
                go_subst = true
            end
        end

        -- Safety net: narrow any residual spread >= 3 when allow_14 is off
        -- (can occur after G+O -> R+O substitution above).
        local narrowed_14 = false
        if not S.mc_gtr_allow_14 and #gems == 2 and gems[2] - gems[1] >= 3 then
            gems        = { gems[1], gems[1] + 2 }
            narrowed_14 = true
        end

        local reason = string.format('%s  %s \xe2\x86\x92 %s',
            ChordTypeName(gems), PitchLabel(ev.pitches), GemLabel(gems))
        if n_orig > #pitches then
            reason = reason .. string.format('  (compressed %d\xe2\x86\x92%d)', n_orig, #pitches)
        end
        reason = reason .. ChordQualityLabel(pitches)
        if go_fixed  then reason = reason .. '  (G+O 3-note illegal \xe2\x86\x92 kept as 1-5)' end
        if go_subst  then reason = reason .. '  (G\xe2\x86\x92R: G+O \xe2\x86\x92 R+O for playability)' end
        if narrowed_14 then reason = reason .. '  (1-4 \xe2\x86\x92 1-3: narrowed per setting)' end
        if shared[key] then reason = reason .. '  (*Wrap)' end

        assignments[#assignments + 1] = {
            s = ev.s, e = ev.e, gems = gems, reason = reason, is_meta = false,
            tab_str = ev.tab_str,
        }

        prev_gems   = gems
        prev_ev_end = ev.e
        if i == pr.i_e then pi = pi + 1 end
    end

    return assignments
end

----------------------------------------------------------------------
-- Preview report
----------------------------------------------------------------------

local function BuildPreviewReport(assignments, n_src, n_gems)
    local lines = {}
    lines[#lines + 1] = string.format('Source notes: %d  ->  Gems to write: %d', n_src, n_gems)
    lines[#lines + 1] = ''
    for _, a in ipairs(assignments) do
        if a.is_meta then
            lines[#lines + 1] = ''
            lines[#lines + 1] = '  *** ' .. a.reason
        else
            local ts = r.format_timestr_pos(a.s, '', 1)
            lines[#lines + 1] = string.format('  %-10s  %-7s  %s',
                ts, GemLabel(a.gems), a.reason)
        end
    end
    return table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Target track write helpers
----------------------------------------------------------------------

local function BuildOutNotes(assignments)
    local out = {}
    for _, a in ipairs(assignments) do
        if not a.is_meta and a.gems then
            for _, g in ipairs(a.gems) do
                out[#out + 1] = { s = a.s, e = a.e, pitch = GEM_MIN + g }
            end
        end
    end
    return out
end


----------------------------------------------------------------------
-- Public action functions
----------------------------------------------------------------------

function ConvertGuitar()
    if S.mc_gtr_src_idx < 0 then
        S.status = 'Error: no guitar source track selected.'
        S.last_result = 'Select the source MIDI guitar track in the Guitar tab.'
        return
    end
    if S.mc_gtr_tgt_idx < 0 then
        S.status = 'Error: no guitar target track selected.'
        S.last_result = 'Select the PART GUITAR target track in the Guitar tab.'
        return
    end

    local src_tr = r.GetTrack(0, S.mc_gtr_src_idx)
    local tgt_tr = r.GetTrack(0, S.mc_gtr_tgt_idx)
    if not src_tr or not tgt_tr then
        S.status = 'Error: a selected track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local src_notes    = ReadGuitarMIDI(src_tr, sel_s, sel_e)
    if #src_notes == 0 then
        S.status = 'No MIDI notes found on source track.'
        S.last_result = sel_s and 'No notes in the current time selection.'
                               or 'Source track has no MIDI notes.'
        return
    end

    local events      = GroupIntoEvents(src_notes)
    local wrap_gap_s  = S.mc_gtr_wrap_gap_ms / 1000
    local assignments = AssignGems(events, wrap_gap_s, S.mc_gtr_max_chord)

    local n_gems = 0
    for _, a in ipairs(assignments) do
        if not a.is_meta and a.gems then n_gems = n_gems + #a.gems end
    end

    local preview_mode = (S.mc_gtr_workflow == 0)
    local report       = BuildPreviewReport(assignments, #src_notes, n_gems)

    if preview_mode then
        S.status = string.format('Guitar preview: %d source notes -> %d gems (not written)',
            #src_notes, n_gems)
        S.last_result = report
        return
    end

    local tgt_item, tgt_take = FindFirstMIDIItem(tgt_tr)
    if not tgt_item then
        S.status = 'Error: target track has no MIDI item.'
        S.last_result = 'Create a MIDI item on the PART GUITAR target track first.'
        return
    end

    local out_notes = BuildOutNotes(assignments)
    local ip        = r.GetMediaItemInfo_Value(tgt_item, 'D_POSITION')
    local ie        = ip + r.GetMediaItemInfo_Value(tgt_item, 'D_LENGTH')
    local clear_s   = sel_s and math.max(sel_s, ip) or ip
    local clear_e   = sel_e and math.min(sel_e, ie) or ie

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    r.MarkTrackItemsDirty(tgt_tr, tgt_item)
    ClearGuitarGems(tgt_take, clear_s, clear_e)
    InsertNotes(tgt_take, out_notes, 100)
    r.Undo_EndBlock2(0, 'Convert Guitar to Rock Band', -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()

    S.status = string.format('Guitar converted: %d gems inserted from %d source notes.',
        n_gems, #src_notes)
    S.last_result = report
end

function ValidateGuitar()
    if S.mc_gtr_tgt_idx < 0 then
        S.status = 'Error: no guitar target track selected.'
        S.last_result = 'Select the PART GUITAR target track in the Guitar tab.'
        return
    end

    local tgt_tr = r.GetTrack(0, S.mc_gtr_tgt_idx)
    if not tgt_tr then
        S.status = 'Error: target track no longer exists - refresh tracks.'
        S.last_result = nil
        return
    end

    local sel_s, sel_e = GetTimeSelection()
    local rb_notes      = ReadRBGuitarNotes(tgt_tr, sel_s, sel_e)
    if #rb_notes == 0 then
        S.status = 'No Rock Band guitar notes found on target track.'
        S.last_result = sel_s and 'No notes in the current time selection.'
                               or 'Target track has no RB guitar notes (pitch 96-100).'
        return
    end

    local violations, n_events = RunValidation(rb_notes)

    if #violations == 0 then
        S.status = string.format('Validation passed - %d chord events checked, no violations.',
            n_events)
        S.last_result = 'No violations found.'
    else
        S.status = string.format('Validation: %d violation%s in %d events.',
            #violations, #violations == 1 and '' or 's', n_events)
        S.last_result = table.concat(violations, '\n')
    end
end
