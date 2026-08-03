-- Harmonies tab actions (HarmoniesAction)

local function ApplyLyricSuffix(lyric, unpitched, hidden)
    if not lyric then return nil end
    local suffix     = lyric:match('[#$]+$') or ''
    local base       = lyric:sub(1, #lyric - #suffix)
    local add_hash   = unpitched or suffix:find('#', 1, true) ~= nil
    local add_dollar = hidden    or suffix:find('$', 1, true) ~= nil
    if add_hash   then base = base .. '#' end
    if add_dollar then base = base .. '$' end
    return base
end

function DiatonicThirdOffset(pitch, root, quality, direction)
    local scale = quality == 1 and HARM_SCALE.minor or HARM_SCALE.major
    local pc = pitch % 12
    local spcs = {}
    for i, s in ipairs(scale) do spcs[i] = (root + s) % 12 end

    -- Find nearest scale degree by clockwise pitch-class distance
    local best_deg, best_dist = 1, 13
    for i, spc in ipairs(spcs) do
        local dist = (pc - spc + 12) % 12
        if dist < best_dist then best_dist = dist; best_deg = i end
    end

    -- 3rd = 2 scale positions in given direction (7-degree wrap)
    local third_deg = ((best_deg - 1 + direction * 2 + 70) % 7) + 1
    local target_pc = spcs[third_deg]

    if direction > 0 then
        return (target_pc - pc + 12) % 12
    else
        local d = (pc - target_pc + 12) % 12
        return d == 0 and -12 or -d
    end
end

-- Duration in seconds of the measure containing project time t. Used as the
-- donor search radius in "Preserve target pitches" mode, so the radius follows
-- the tempo instead of being a fixed number of seconds.
local function MeasureLengthAt(t)
    local _, meas = r.TimeMap2_timeToBeats(0, t)
    local _, qn_s, qn_e = r.TimeMap_GetMeasureInfo(0, meas)
    local len = r.TimeMap2_QNToTime(0, qn_e) - r.TimeMap2_QNToTime(0, qn_s)
    if not len or len <= 0 then return 2.0 end   -- defensive: ~one 4/4 bar at 120 BPM
    return len
end

-- Existing destination notes in the vocal range that the copy is about to
-- clear. Same overlap test ClearNotesInRange uses, so every note that will be
-- removed is available as a pitch donor.
local function ReadTargetNotesInRange(take, range_start, range_end)
    local notes = {}
    local _, nc = r.MIDI_CountEvts(take)
    for i = 0, nc - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(take, i)
        if ok and p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(take, eppq)
            if s_t < range_end and e_t > range_start then
                notes[#notes + 1] = { s = s_t, e = e_t, pitch = p }
            end
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

-- Pitch assignment for "Preserve target pitches": each copied source note takes
-- its pitch from whatever was already on the destination track, so hand-authored
-- harmony pitches survive a timing-only re-sync from the lead.
--
--   new_notes  { s, e, src_pitch }  sorted by s - the notes being written
--   old_notes  { s, e, pitch }      sorted by s - the notes being replaced
--   windows    parallel to new_notes, donor search radius in seconds
--
-- Returns assigned, counts where assigned[i] = { pitch, category } and category
-- is one of the four mutually exclusive outcomes counted in counts. Kept free of
-- REAPER calls (hence the precomputed windows) so it can be unit tested.
function ResolvePreservedPitches(new_notes, old_notes, windows)
    local assigned = {}
    local counts   = { existing = 0, closest = 0, carried = 0, source = 0 }

    -- State of the current "run": consecutive new notes sharing one donor, which
    -- is what a note split for a slide looks like from the destination's side.
    local run_donor, run_first_src, run_donor_pitch = nil, nil, nil

    for i, n in ipairs(new_notes) do
        -- 1. Overlapping donor, largest overlap wins (earliest breaks ties).
        local donor, best_ov = nil, 0
        for j, o in ipairs(old_notes) do
            if o.s < n.e and o.e > n.s then
                local ov = math.min(o.e, n.e) - math.max(o.s, n.s)
                if ov > best_ov then best_ov = ov; donor = j end
            end
        end
        local via_overlap = donor ~= nil

        -- 2. Otherwise the nearest start within this note's window.
        if not donor then
            local win, best_d = windows[i] or 0, nil
            for j, o in ipairs(old_notes) do
                local d = math.abs(o.s - n.s)
                if d <= win and (best_d == nil or d < best_d) then
                    best_d = d; donor = j
                end
            end
        end

        if not donor then
            -- 3. Nothing near enough: keep the source pitch untouched.
            assigned[i] = { pitch = n.src_pitch, category = 'source' }
            counts.source = counts.source + 1
            run_donor = nil
        elseif donor == run_donor then
            -- Later half of a split: carry the source's own interval so the
            -- slide's direction and size survive.
            local pitch = run_donor_pitch + (n.src_pitch - run_first_src)
            if pitch < RB3_MIN_PITCH or pitch > RB3_MAX_PITCH then
                return nil, (
                    'A split source note carries an interval of %+d semitones onto\n' ..
                    'destination pitch %s, giving %d - outside the valid vocal range\n' ..
                    '%s\226\128\147%s.\n\n' ..
                    'Retune that note on the destination track, or reduce the interval\n' ..
                    'between the split notes in the source.')
                    :format(
                        n.src_pitch - run_first_src, PitchName(run_donor_pitch), pitch,
                        PitchName(RB3_MIN_PITCH), PitchName(RB3_MAX_PITCH))
            end
            assigned[i] = { pitch = pitch, category = 'carried' }
            counts.carried = counts.carried + 1
        else
            local cat = via_overlap and 'existing' or 'closest'
            assigned[i] = { pitch = old_notes[donor].pitch, category = cat }
            counts[cat] = counts[cat] + 1
            run_donor, run_first_src, run_donor_pitch =
                donor, n.src_pitch, old_notes[donor].pitch
        end
    end

    return assigned, counts
end

local function ResolveHarmTracks()
    local tracks = GetTrackList()
    if #tracks == 0 then return nil, 'No tracks in project.' end
    if S.harm_src_idx >= #tracks then return nil, 'Source track index out of range.' end

    local dsts, any = {}, false
    local cfg = {
        { en='harm_dst1_enabled', idx='harm_dst1_idx', mode='harm_dst1_mode',
          lu='harm_dst1_lyric_unpitched', lh='harm_dst1_lyric_hidden', n=1 },
        { en='harm_dst2_enabled', idx='harm_dst2_idx', mode='harm_dst2_mode',
          lu='harm_dst2_lyric_unpitched', lh='harm_dst2_lyric_hidden', n=2 },
        { en='harm_dst3_enabled', idx='harm_dst3_idx', mode='harm_dst3_mode',
          lu='harm_dst3_lyric_unpitched', lh='harm_dst3_lyric_hidden', n=3 },
    }
    for _, c in ipairs(cfg) do
        if S[c.en] then
            any = true
            if S[c.idx] >= #tracks then
                return nil, ('Destination %d track index out of range.'):format(c.n)
            end
            if S[c.idx] == S.harm_src_idx then
                return nil, ('Destination %d is the same as the source track.'):format(c.n)
            end
            local tr   = r.GetTrack(0, tracks[S[c.idx] + 1].idx)
            local item, take = FindFirstMIDIItem(tr)
            if not take then
                return nil, ('No MIDI item on destination %d track.'):format(c.n)
            end
            dsts[#dsts + 1] = {
                track = tr, item = item, take = take,
                mode  = HARM_MODES[S[c.mode] + 1], n = c.n,
                lyric_unpitched = S[c.lu],
                lyric_hidden    = S[c.lh],
            }
        end
    end
    if not any then return nil, 'No destination tracks enabled.' end

    return { src = r.GetTrack(0, tracks[S.harm_src_idx + 1].idx), dsts = dsts }
end

function HarmoniesAction()
    local trks, terr = ResolveHarmTracks()
    if not trks then S.status = terr; S.last_result = nil; return end

    local range_start, range_end, has_sel = GetTimeSelection()
    if not range_start then
        local src_item, _ = FindFirstMIDIItem(trks.src)
        if not src_item then
            S.status = 'Error'; S.last_result = 'No MIDI item on source track.'; return
        end
        range_start = r.GetMediaItemInfo_Value(src_item, 'D_POSITION')
        range_end   = range_start + r.GetMediaItemInfo_Value(src_item, 'D_LENGTH')
        has_sel = false
    else
        has_sel = true
    end

    local _, src_take = FindFirstMIDIItem(trks.src)
    if not src_take then
        S.status = 'Error'; S.last_result = 'No MIDI item on source track.'; return
    end

    local lyric_at = {}
    local _, n_notes, _, n_lyr = r.MIDI_CountEvts(src_take)
    for i = 0, n_lyr - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(src_take, i)
        if ok and typ == 5 and not LYRIC_IGNORE[msg] then lyric_at[ppq] = msg end
    end

    local vocal_notes, phrase_notes = {}, {}
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(src_take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(src_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(src_take, eppq)
            if s_t >= range_start - 0.001 and s_t < range_end + 0.001 then
                if p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                    vocal_notes[#vocal_notes + 1] = { s = s_t, e = e_t, pitch = p, lyric = lyric_at[sppq] }
                elseif p == RB3_PHRASE_PITCH and S.harm_copy_phrase_markers then
                    phrase_notes[#phrase_notes + 1] = { s = s_t, e = e_t, pitch = p, lyric = lyric_at[sppq] }
                elseif p == RB3_OVERDRIVE_PITCH and S.harm_copy_overdrive then
                    phrase_notes[#phrase_notes + 1] = { s = s_t, e = e_t, pitch = p, lyric = lyric_at[sppq] }
                end
            end
        end
    end

    -- "Preserve target pitches" walks the notes in time order to spot a note
    -- that has been split for a slide, so don't rely on the take's event order.
    table.sort(vocal_notes, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.pitch < b.pitch
    end)

    -- Resolve every destination's final note list before touching the project,
    -- so an out-of-range pitch on destination 3 leaves 1 and 2 untouched.
    local preserve_in, preserve_windows
    for _, dst in ipairs(trks.dsts) do
        local out = {}

        if dst.mode.preserve then
            -- The copied notes and their search windows are the same for every
            -- preserve destination - build them once.
            if not preserve_in then
                preserve_in, preserve_windows = {}, {}
                for i, n in ipairs(vocal_notes) do
                    preserve_in[i]      = { s = n.s, e = n.e, src_pitch = n.pitch }
                    preserve_windows[i] =
                        MeasureLengthAt(n.s) * HARM_PRESERVE_SEARCH_MEASURES
                end
            end
            local old_notes = ReadTargetNotesInRange(dst.take, range_start, range_end)
            local assigned, counts =
                ResolvePreservedPitches(preserve_in, old_notes, preserve_windows)
            if not assigned then
                S.status      = ('Range error on Destination %d.'):format(dst.n)
                S.last_result = counts   -- error string
                return
            end
            dst.counts = counts
            for i, n in ipairs(vocal_notes) do
                local lyric = ApplyLyricSuffix(n.lyric, dst.lyric_unpitched, dst.lyric_hidden)
                out[i] = { s = n.s, e = n.e, pitch = assigned[i].pitch, lyric = lyric }
            end
        else
            for _, n in ipairs(vocal_notes) do
                local offset
                if dst.mode.diatonic then
                    offset = DiatonicThirdOffset(
                        n.pitch, S.harm_key_root, S.harm_key_quality, dst.mode.dir)
                else
                    offset = dst.mode.offset
                end
                local new_pitch = n.pitch + offset
                if new_pitch < RB3_MIN_PITCH or new_pitch > RB3_MAX_PITCH then
                    local dir_label = dst.mode.diatonic
                        and (dst.mode.dir > 0 and '3rd above' or '3rd below')
                        or  dst.mode.label
                    S.status = ('Range error on Destination %d.'):format(dst.n)
                    S.last_result = (
                        'Note %s (pitch %d) + %s = pitch %d, which is outside\n' ..
                        'the valid vocal range %s\226\128\147%s.\n\n' ..
                        'Choose a different interval for Destination %d, or adjust the source\n' ..
                        'notes so they fall within a singable range for this harmony.')
                        :format(
                            PitchName(n.pitch), n.pitch, dir_label, new_pitch,
                            PitchName(RB3_MIN_PITCH), PitchName(RB3_MAX_PITCH),
                            dst.n)
                    return
                end
                local lyric = ApplyLyricSuffix(n.lyric, dst.lyric_unpitched, dst.lyric_hidden)
                out[#out + 1] = { s = n.s, e = n.e, pitch = new_pitch, lyric = lyric }
            end
        end

        for _, n in ipairs(phrase_notes) do
            out[#out + 1] = { s = n.s, e = n.e, pitch = n.pitch, lyric = n.lyric }
        end
        dst.out = out
    end

    local result_lines = {}
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for _, dst in ipairs(trks.dsts) do
        local out = dst.out

        r.MarkTrackItemsDirty(dst.track, dst.item)

        local cleared = ClearNotesInRange(dst.take, range_start, range_end, RB3_MIN_PITCH, RB3_MAX_PITCH)
        local lyrics_cleared = ClearLyricsInRange(dst.take, range_start, range_end)
        if S.harm_copy_phrase_markers or S.harm_copy_overdrive then
            local _, nc = r.MIDI_CountEvts(dst.take)
            for i = nc - 1, 0, -1 do
                local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(dst.take, i)
                local copy_this = (p == RB3_PHRASE_PITCH and S.harm_copy_phrase_markers)
                    or (p == RB3_OVERDRIVE_PITCH and S.harm_copy_overdrive)
                if ok and copy_this then
                    local s_t = r.MIDI_GetProjTimeFromPPQPos(dst.take, sppq)
                    local e_t = r.MIDI_GetProjTimeFromPPQPos(dst.take, eppq)
                    if s_t < range_end and e_t > range_start then
                        r.MIDI_DeleteNote(dst.take, i)
                        cleared = cleared + 1
                    end
                end
            end
        end

        InsertNotes(dst.take, out, S.velocity)
        local lyrics_inserted = 0
        for _, n in ipairs(out) do
            if n.lyric then
                local ppq = r.MIDI_GetPPQPosFromProjTime(dst.take, n.s)
                r.MIDI_InsertTextSysexEvt(dst.take, false, false, ppq, 5, n.lyric)
                lyrics_inserted = lyrics_inserted + 1
            end
        end

        local mode_label = dst.mode.preserve and 'preserve target pitches'
            or (dst.mode.diatonic
                and (dst.mode.dir > 0 and 'diatonic 3rd above' or 'diatonic 3rd below')
                or  dst.mode.label)
        result_lines[#result_lines + 1] =
            ('Destination %d [%s]: cleared %d notes / %d lyrics, inserted %d vocal + %d phrase (%d lyrics)')
            :format(dst.n, mode_label, cleared, lyrics_cleared, #vocal_notes, #phrase_notes, lyrics_inserted)
        if dst.counts then
            local c = dst.counts
            result_lines[#result_lines + 1] =
                ('  Existing pitches applied: %d'):format(c.existing)
            result_lines[#result_lines + 1] =
                ('  Matching closest pitch applied: %d'):format(c.closest)
            result_lines[#result_lines + 1] =
                ('  Slide interval carried: %d'):format(c.carried)
            result_lines[#result_lines + 1] =
                ('  No matching close pitch source applied: %d'):format(c.source)
        end
    end
    r.Undo_EndBlock2(0, 'Vocal Helper VKR: Apply Harmonies', -1)
    r.PreventUIRefresh(-1)

    local scope = has_sel
        and (' [%s \226\128\147 %s]'):format(FormatTime(range_start), FormatTime(range_end))
        or  ' [full item]'
    S.status = ('Harmonies applied to %d track%s.'):format(
        #trks.dsts, #trks.dsts == 1 and '' or 's')
    S.last_result = table.concat({
        ('Source: %d vocal, %d phrase notes%s'):format(
            #vocal_notes, #phrase_notes, scope),
        table.concat(result_lines, '\n'),
    }, '\n')
end
