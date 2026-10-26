-- Smart default track selection for the Instrument Helper.
-- Requires: S, r (globals)
-- The shared track and action helpers (FindTrackByName, GetTakePPQPerQN,
-- GetTempoContextBefore, RefreshTrackLists, RunAction) are in
-- lib/reaper_helper_common.lua.

-- Pre-select the fields in name_to_field (track name -> S field) from the
-- project's tracks. Only sets a field when it is still -1 (not yet assigned).
local function SetDefaultsByName(name_to_field)
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, name = r.GetTrackName(tr)
        local field = name_to_field[name]
        if field and S[field] == -1 then
            S[field] = i
        end
    end
end

-- MIDI converter target tracks (WIP Drums and Guitar tabs).
function SetDefaultMIDITracks()
    SetDefaultsByName({
        ['PART DRUMS']  = 'mc_drum_tgt_idx',
        ['PART GUITAR'] = 'mc_gtr_tgt_idx',
    })
end

-- Pro Keys, Keys, Guitar/Bass and Drums difficulty tracks.
function SetDefaultDifficultyTracks()
    SetDefaultsByName({
        ['PART REAL_KEYS_X'] = 'diff_pk_x_idx',
        ['PART REAL_KEYS_H'] = 'diff_pk_h_idx',
        ['PART REAL_KEYS_M'] = 'diff_pk_m_idx',
        ['PART REAL_KEYS_E'] = 'diff_pk_e_idx',
        ['PART KEYS']        = 'diff_5k_idx',
        ['PART GUITAR']      = 'diff_gtr_idx',
        ['PART BASS']        = 'diff_bass_idx',
        ['PART DRUMS']       = 'diff_drums_idx',
        ['PART DRUMS_2X']    = 'diff_drums2x_idx',
    })
end
