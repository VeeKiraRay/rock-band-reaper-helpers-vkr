-- Validation tab actions (ValidatePhrases, PhraseSimilarityAction)

----------------------------------------------------------------------
-- Validate phrases: read-only check of all phrase-marker regions
----------------------------------------------------------------------
function ValidatePhrases()
    local tracks = GetTrackList()
    if #tracks == 0 or S.midi_idx >= #tracks then
        S.status = 'Error'; S.last_result = 'Invalid MIDI destination track.'; return
    end
    local midi_track = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local _, midi_take = FindFirstMIDIItem(midi_track)
    if not midi_take then
        S.status = 'Error'
        S.last_result = 'No MIDI item found on the destination track.'
        return
    end

    -- Build PPQ -> lyric lookup from type-5 text events.
    local lyric_at = {}
    local _, _, _, n_text = r.MIDI_CountEvts(midi_take)
    for i = 0, n_text - 1 do
        local ok, _, _, ppq, typ, msg = r.MIDI_GetTextSysexEvt(midi_take, i)
        if ok and typ == 5 then lyric_at[ppq] = msg end
    end

    -- Collect vocal notes (pitch 36-84) and phrase markers (pitch 105).
    local vocal_notes    = {}
    local phrase_markers = {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                vocal_notes[#vocal_notes + 1] = { s = s_t, e = e_t, lyric = lyric_at[sppq] }
            elseif p == RB3_PHRASE_PITCH then
                phrase_markers[#phrase_markers + 1] = { s = s_t, e = e_t }
            end
        end
    end
    table.sort(vocal_notes,    function(a, b) return a.s < b.s end)
    table.sort(phrase_markers, function(a, b) return a.s < b.s end)

    if #phrase_markers == 0 then
        S.status = 'No phrase markers found.'
        S.last_result = 'No phrase markers (pitch 105) found on the destination track — cannot validate.'
        return
    end

    local lines     = {}
    local bad_count = 0

    for pm_i, pm in ipairs(phrase_markers) do
        -- Compute 64th-note duration from adjacent beat times at the phrase start.
        local _, _, _, fullbeats, _ = r.TimeMap2_timeToBeats(0, pm.s)
        local beat_floor = math.floor(fullbeats)
        local t_beat0    = r.TimeMap2_beatsToTime(0, beat_floor)
        local t_beat1    = r.TimeMap2_beatsToTime(0, beat_floor + 1)
        local dur_64th   = (t_beat1 - t_beat0) / 16

        -- Vocal notes whose start falls within [pm.s, pm.e).
        local notes_in = {}
        for _, n in ipairs(vocal_notes) do
            if n.s >= pm.s - 0.001 and n.s < pm.e - 0.001 then
                notes_in[#notes_in + 1] = n
            end
        end

        local viol = {}

        -- Check 1: first vocal note has a capitalized lyric.
        if notes_in[1] then
            local lyric = notes_in[1].lyric
            if lyric and lyric ~= '' then
                local first = lyric:sub(1, 1)
                if first ~= first:upper() then
                    viol[#viol + 1] = ('Lyric not capitalized: "%s"'):format(lyric)
                end
            end
        end

        -- Check 2 & 3: phrase marker start and end on 64th-note grid.
        if not IsOnGrid(pm.s) then viol[#viol + 1] = 'Start not on grid' end
        if not IsOnGrid(pm.e) then viol[#viol + 1] = 'End not on grid'   end

        -- Check 4: gap to next phrase >= 4 x 64th note.
        if pm_i < #phrase_markers then
            local gap_s   = phrase_markers[pm_i + 1].s - pm.e
            local min_gap = 4 * dur_64th
            if gap_s < min_gap - 0.001 then
                viol[#viol + 1] = ('Too close to next phrase: %dms (need >= %dms / 4x64th)')
                    :format(math.floor(gap_s * 1000 + 0.5), math.floor(min_gap * 1000 + 0.5))
            end
        end

        -- Check 5: first note starts at least 2 x 64th notes after phrase start.
        if notes_in[1] then
            local lead     = notes_in[1].s - pm.s
            local min_lead = 2 * dur_64th
            if lead < min_lead - 0.001 then
                viol[#viol + 1] = ('First note too close to phrase start: %dms (need >= %dms / 2x64th)')
                    :format(math.floor(lead * 1000 + 0.5), math.floor(min_lead * 1000 + 0.5))
            end
        end

        -- Check 6: last note ends at least 1 x 64th note before phrase end.
        local last_note = notes_in[#notes_in]
        if last_note then
            local tail     = pm.e - last_note.e
            local min_tail = dur_64th
            if tail < min_tail - 0.001 then
                viol[#viol + 1] = ('Last note too close to phrase end: %dms (need >= %dms / 1x64th)')
                    :format(math.floor(tail * 1000 + 0.5), math.floor(min_tail * 1000 + 0.5))
            end
        end

        if #viol > 0 then
            bad_count = bad_count + 1
            lines[#lines + 1] = ''
            lines[#lines + 1] = FormatTime(pm.s)
            for _, v in ipairs(viol) do
                lines[#lines + 1] = '  - ' .. v
            end
        end
    end

    local n = #phrase_markers
    local summary
    if bad_count == 0 then
        summary = ('Validated %d phrase%s — all OK.'):format(n, n == 1 and '' or 's')
    else
        summary = ('Validated %d phrase%s — %d with violations.'):format(
            n, n == 1 and '' or 's', bad_count)
        local ok_count = n - bad_count
        if ok_count > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('All other %d phrase%s OK.'):format(
                ok_count, ok_count == 1 and '' or 's')
        end
    end
    table.insert(lines, 1, summary)

    S.status      = summary
    S.last_result = table.concat(lines, '\n')
end

----------------------------------------------------------------------
-- Phrase Similarity Check
----------------------------------------------------------------------

local function EditDistance(a, b)
    local na, nb = #a, #b
    if na == 0 then return nb end
    if nb == 0 then return na end
    local dp = {}
    for i = 0, na do
        dp[i] = {}
        dp[i][0] = i
    end
    for j = 0, nb do dp[0][j] = j end
    for i = 1, na do
        for j = 1, nb do
            if a[i] == b[j] then
                dp[i][j] = dp[i-1][j-1]
            else
                dp[i][j] = 1 + math.min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            end
        end
    end
    return dp[na][nb]
end

function PhraseSimilarityAction()
    local tracks = GetTrackList()
    if #tracks == 0 or S.midi_idx >= #tracks then
        S.status = 'Error'; S.last_result = 'Invalid MIDI destination track.'; return
    end
    local midi_track = r.GetTrack(0, tracks[S.midi_idx + 1].idx)
    local _, midi_take = FindFirstMIDIItem(midi_track)
    if not midi_take then
        S.status = 'Error'
        S.last_result = 'No MIDI item found on the destination track.'
        return
    end

    local vocal_notes, phrase_markers = {}, {}
    local _, n_notes = r.MIDI_CountEvts(midi_take)
    for i = 0, n_notes - 1 do
        local ok, _, _, sppq, eppq, _, p = r.MIDI_GetNote(midi_take, i)
        if ok then
            local s_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, sppq)
            local e_t = r.MIDI_GetProjTimeFromPPQPos(midi_take, eppq)
            if p >= RB3_MIN_PITCH and p <= RB3_MAX_PITCH then
                vocal_notes[#vocal_notes + 1] = { s = s_t, e = e_t, pitch = p }
            elseif p == RB3_PHRASE_PITCH then
                phrase_markers[#phrase_markers + 1] = { s = s_t, e = e_t }
            end
        end
    end
    table.sort(vocal_notes,    function(a, b) return a.s < b.s end)
    table.sort(phrase_markers, function(a, b) return a.s < b.s end)

    if #phrase_markers == 0 then
        S.status = 'No phrase markers found.'
        S.last_result =
            'No phrase markers (pitch 105) on the destination track \xe2\x80\x94 cannot compare phrases.\n' ..
            'Add phrase markers first using Rock Band authoring tools.'
        return
    end

    -- Segment vocal notes into phrases by marker boundaries.
    -- A phrase is the run of notes whose start falls within [pm.s, pm.e).
    local phrases = {}
    for _, pm in ipairs(phrase_markers) do
        local ph_notes = {}
        for _, n in ipairs(vocal_notes) do
            if n.s >= pm.s - 0.001 and n.s < pm.e - 0.001 then
                ph_notes[#ph_notes + 1] = n
            end
        end
        if #ph_notes >= 2 then
            local fp = {}
            if S.phrase_same_key then
                for j = 1, #ph_notes do fp[j] = ph_notes[j].pitch end
            else
                for j = 2, #ph_notes do fp[j-1] = ph_notes[j].pitch - ph_notes[j-1].pitch end
            end
            phrases[#phrases + 1] = {
                start    = pm.s,
                notes    = ph_notes,
                fp       = fp,
                pm_label = FormatTime(pm.s),
            }
        end
    end

    if #phrases < 2 then
        S.status = 'Not enough comparable phrases.'
        S.last_result = ('Found %d phrase marker%s, but fewer than 2 have \xe2\x89\xa5 2 notes each.\n' ..
            'Phrases need at least 2 notes to produce a melodic fingerprint.')
            :format(#phrase_markers, #phrase_markers == 1 and '' or 's')
        return
    end

    local threshold = S.phrase_sim_threshold

    -- Pairwise similarity: edit distance on interval fingerprints
    local sim = {}
    for i = 1, #phrases do sim[i] = {} end
    for i = 1, #phrases do
        for j = i + 1, #phrases do
            local a, b = phrases[i].fp, phrases[j].fp
            local maxlen = math.max(#a, #b)
            local pct = math.floor((1 - EditDistance(a, b) / maxlen) * 100 + 0.5)
            sim[i][j] = pct
            sim[j][i] = pct
        end
    end

    -- Complete-linkage clustering: merge two clusters only when ALL inter-cluster
    -- pairs meet the threshold, guaranteeing every pair in a group >= threshold.
    local cid = {}
    for i = 1, #phrases do cid[i] = i end

    local function get_members(target)
        local m = {}
        for i = 1, #phrases do if cid[i] == target then m[#m + 1] = i end end
        return m
    end

    local merged = true
    while merged do
        merged = false
        local seen, clist = {}, {}
        for i = 1, #phrases do
            if not seen[cid[i]] then seen[cid[i]] = true; clist[#clist + 1] = cid[i] end
        end
        for ci = 1, #clist do
            for cj = ci + 1, #clist do
                local ma, mb = get_members(clist[ci]), get_members(clist[cj])
                local ok = true
                for _, a in ipairs(ma) do
                    for _, b in ipairs(mb) do
                        if (sim[a][b] or 0) < threshold then ok = false; break end
                    end
                    if not ok then break end
                end
                if ok then
                    local old = clist[cj]
                    for i = 1, #phrases do if cid[i] == old then cid[i] = clist[ci] end end
                    merged = true; break
                end
            end
            if merged then break end
        end
    end

    -- Collect groups with >= 2 members, sorted by earliest phrase
    local groups_by_cid = {}
    for i = 1, #phrases do
        if not groups_by_cid[cid[i]] then groups_by_cid[cid[i]] = {} end
        groups_by_cid[cid[i]][#groups_by_cid[cid[i]] + 1] = i
    end

    local groups = {}
    for _, members in pairs(groups_by_cid) do
        if #members >= 2 then
            table.sort(members, function(a, b) return phrases[a].start < phrases[b].start end)
            local min_sim = 100
            for mi = 1, #members do
                for mj = mi + 1, #members do
                    local s = sim[members[mi]][members[mj]] or 0
                    if s < min_sim then min_sim = s end
                end
            end
            groups[#groups + 1] = { members = members, min_sim = min_sim }
        end
    end
    table.sort(groups, function(a, b)
        return phrases[a.members[1]].start < phrases[b.members[1]].start
    end)

    if #groups == 0 then
        local msg = ('Compared %d phrase%s \xe2\x80\x94 no groups at %d%% similarity threshold.')
            :format(#phrases, #phrases == 1 and '' or 's', threshold)
        S.status = msg
        S.last_result = msg .. '\n\nTry lowering the threshold to find more distant matches.'
        return
    end

    local lines = {}
    local total_outliers = 0

    for g_i, g in ipairs(groups) do
        local max_len = 0
        for _, mi in ipairs(g.members) do
            if #phrases[mi].notes > max_len then max_len = #phrases[mi].notes end
        end

        -- Consensus pitch at each position: majority vote across phrase members
        local consensus = {}
        for pos = 1, max_len do
            local votes = {}
            for _, mi in ipairs(g.members) do
                local p = phrases[mi].notes[pos] and phrases[mi].notes[pos].pitch
                if p then votes[p] = (votes[p] or 0) + 1 end
            end
            local best_p, best_v = nil, 0
            for p, v in pairs(votes) do
                if v > best_v then best_p = p; best_v = v end
            end
            consensus[pos] = best_p
        end

        lines[#lines + 1] = ''
        lines[#lines + 1] = ('Group %d: %d phrases (%d%% min similarity)'):format(
            g_i, #g.members, g.min_sim)

        for _, mi in ipairs(g.members) do
            local ph = phrases[mi]
            local pitch_parts, outlier_lines = {}, {}
            for pos = 1, #ph.notes do
                local p    = ph.notes[pos].pitch
                local cons = consensus[pos]
                local name = PitchName(p)
                if cons and p ~= cons then
                    pitch_parts[#pitch_parts + 1] = name .. '*'
                    outlier_lines[#outlier_lines + 1] =
                        ('    note %d: %s vs consensus %s (%+d st)')
                        :format(pos, name, PitchName(cons), p - cons)
                    total_outliers = total_outliers + 1
                else
                    pitch_parts[#pitch_parts + 1] = name
                end
            end
            local pitch_str = table.concat(pitch_parts, ' ')
            if #outlier_lines == 0 then
                lines[#lines + 1] = ('  %s  %s'):format(ph.pm_label, pitch_str)
            else
                lines[#lines + 1] = ('  %s  %s  <- outlier%s:'):format(
                    ph.pm_label, pitch_str, #outlier_lines == 1 and '' or 's')
                for _, ol in ipairs(outlier_lines) do lines[#lines + 1] = ol end
            end
        end
    end

    local summary = ('%d similar group%s found, %d outlier note%s flagged.'):format(
        #groups, #groups == 1 and '' or 's',
        total_outliers, total_outliers == 1 and '' or 's')
    local mode_label = S.phrase_same_key and 'same key (pitch)' or 'any key (contour)'
    table.insert(lines, 1, ('Compared %d phrase%s at %d%% threshold — %s.'):format(#phrases, #phrases == 1 and '' or 's', threshold, mode_label))
    table.insert(lines, 1, summary)
    S.status = summary
    S.last_result = table.concat(lines, '\n')
end
