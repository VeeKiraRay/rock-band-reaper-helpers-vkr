-- Harmonies tab actions (HarmoniesAction)

local function ApplyLyricSuffix(lyric, unpitched, hidden)
    if not lyric then return nil end
    lyric = lyric:gsub('[#$]+$', '')
    if unpitched then lyric = lyric .. '#' end
    if hidden    then lyric = lyric .. '$' end
    return lyric
end

local function DiatonicThirdOffset(pitch, root, quality, direction)
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
                elseif S.harm_copy_phrases then
                    phrase_notes[#phrase_notes + 1] = { s = s_t, e = e_t, pitch = p, lyric = lyric_at[sppq] }
                end
            end
        end
    end

    -- Pre-flight: verify all shifted notes land in the vocal range
    for _, dst in ipairs(trks.dsts) do
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
        end
    end

    local result_lines = {}
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock2(0)
    for _, dst in ipairs(trks.dsts) do
        local out = {}
        for _, n in ipairs(vocal_notes) do
            local offset
            if dst.mode.diatonic then
                offset = DiatonicThirdOffset(
                    n.pitch, S.harm_key_root, S.harm_key_quality, dst.mode.dir)
            else
                offset = dst.mode.offset
            end
            local lyric = ApplyLyricSuffix(n.lyric, dst.lyric_unpitched, dst.lyric_hidden)
            out[#out + 1] = { s = n.s, e = n.e, pitch = n.pitch + offset, lyric = lyric }
        end
        for _, n in ipairs(phrase_notes) do
            out[#out + 1] = { s = n.s, e = n.e, pitch = n.pitch, lyric = n.lyric }
        end

        r.MarkTrackItemsDirty(dst.track, dst.item)

        local cleared = ClearAllNotesInRange(dst.take, range_start, range_end)
        local lyrics_cleared = ClearLyricsInRange(dst.take, range_start, range_end)
        if S.harm_copy_phrases then
            local _, nc = r.MIDI_CountEvts(dst.take)
            for i = nc - 1, 0, -1 do
                local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(dst.take, i)
                if ok and (p < RB3_MIN_PITCH or p > RB3_MAX_PITCH) then
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

        local mode_label = dst.mode.diatonic
            and (dst.mode.dir > 0 and 'diatonic 3rd above' or 'diatonic 3rd below')
            or  dst.mode.label
        result_lines[#result_lines + 1] =
            ('Destination %d [%s]: cleared %d notes / %d lyrics, inserted %d vocal + %d phrase (%d lyrics)')
            :format(dst.n, mode_label, cleared, lyrics_cleared, #vocal_notes, #phrase_notes, lyrics_inserted)
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
