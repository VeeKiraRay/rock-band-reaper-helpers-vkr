-- State, constants, and tooltip text for the Venue Demo generator.
-- All venue event pools are self-contained here so this tool has no dependency
-- on the main general helper modules.

----------------------------------------------------------------------
-- Mode constants
----------------------------------------------------------------------
DEMO_MODE_CAMERA   = 0
DEMO_MODE_LIGHTING = 1
DEMO_MODE_POSTPROC = 2
DEMO_MODE_COOP     = 3

-- Which two non-drummer instruments are in the band.
-- The absent instrument's directed/coop cuts are filtered out of Camera and Coop modes.
DEMO_CAM_COMBO_BG = 0   -- Bass + Guitar  (no Keys)
DEMO_CAM_COMBO_BK = 1   -- Bass + Keys    (no Guitar)
DEMO_CAM_COMBO_GK = 2   -- Guitar + Keys  (no Bass)

----------------------------------------------------------------------
-- Event pools (mirrors rock_band_general_helper_vkr / venue_camera.lua
--              and venue_themes.lua - keep in sync if those change)
----------------------------------------------------------------------

COOP_POOL = {
    '[coop_all_behind]', '[coop_all_far]', '[coop_all_near]',
    '[coop_front_behind]', '[coop_front_near]',
    '[coop_d_behind]', '[coop_d_near]', '[coop_d_closeup_hand]', '[coop_d_closeup_head]',
    '[coop_v_behind]', '[coop_v_near]', '[coop_v_closeup]',
    '[coop_b_behind]', '[coop_b_near]', '[coop_b_closeup_hand]', '[coop_b_closeup_head]',
    '[coop_g_behind]', '[coop_g_near]', '[coop_g_closeup_hand]', '[coop_g_closeup_head]',
    '[coop_k_behind]', '[coop_k_near]', '[coop_k_closeup_hand]', '[coop_k_closeup_head]',
    '[coop_dv_near]', '[coop_bd_near]', '[coop_dg_near]',
    '[coop_bv_behind]', '[coop_bv_near]',
    '[coop_gv_behind]', '[coop_gv_near]',
    '[coop_kv_behind]', '[coop_kv_near]',
    '[coop_bg_behind]', '[coop_bg_near]',
    '[coop_bk_behind]', '[coop_bk_near]',
    '[coop_gk_behind]', '[coop_gk_near]',
}

COOP_LABELS = {
    coop_all_behind='All (Behind)', coop_all_far='All (Far)', coop_all_near='All (Near)',
    coop_front_behind='Front (Behind)', coop_front_near='Front (Near)',
    coop_d_behind='Drums (Behind)', coop_d_near='Drums (Near)',
    coop_d_closeup_hand='Drums (Hands)', coop_d_closeup_head='Drums (Head)',
    coop_v_behind='Vocals (Behind)', coop_v_near='Vocals (Near)',
    coop_v_closeup='Vocals (Close-up)',
    coop_b_behind='Bass (Behind)', coop_b_near='Bass (Near)',
    coop_b_closeup_hand='Bass (Hands)', coop_b_closeup_head='Bass (Head)',
    coop_g_behind='Guitar (Behind)', coop_g_near='Guitar (Near)',
    coop_g_closeup_hand='Guitar (Hands)', coop_g_closeup_head='Guitar (Head)',
    coop_k_behind='Keys (Behind)', coop_k_near='Keys (Near)',
    coop_k_closeup_hand='Keys (Hands)', coop_k_closeup_head='Keys (Head)',
    coop_dv_near='Duo Drums/Vocals (Near)',
    coop_bd_near='Duo Bass/Drums (Near)',
    coop_dg_near='Duo Drums/Guitar (Near)',
    coop_bv_behind='Duo Bass/Vocals (Behind)', coop_bv_near='Duo Bass/Vocals (Near)',
    coop_gv_behind='Duo Guitar/Vocals (Behind)', coop_gv_near='Duo Guitar/Vocals (Near)',
    coop_kv_behind='Duo Keys/Vocals (Behind)', coop_kv_near='Duo Keys/Vocals (Near)',
    coop_bg_behind='Duo Bass/Guitar (Behind)', coop_bg_near='Duo Bass/Guitar (Near)',
    coop_bk_behind='Duo Bass/Keys (Behind)', coop_bk_near='Duo Bass/Keys (Near)',
    coop_gk_behind='Duo Guitar/Keys (Behind)', coop_gk_near='Duo Guitar/Keys (Near)',
}

-- [directed_bre] and [directed_brej] excluded (BRE-only, must be placed manually).
DIRECTED_POOL = {
    '[directed_all]', '[directed_all_cam]', '[directed_all_lt]', '[directed_all_yeah]',
    '[directed_crowd]',
    '[directed_drums]', '[directed_drums_pnt]', '[directed_drums_np]',
    '[directed_drums_lt]', '[directed_drums_kd]',
    '[directed_vocals]', '[directed_vocals_np]', '[directed_vocals_cls]',
    '[directed_vocals_cam_pr]', '[directed_vocals_cam_pt]',
    '[directed_stagedive]', '[directed_crowdsurf]',
    '[directed_bass]', '[directed_crowd_b]', '[directed_bass_np]',
    '[directed_bass_cam]', '[directed_bass_cls]',
    '[directed_guitar]', '[directed_crowd_g]', '[directed_guitar_np]',
    '[directed_guitar_cls]', '[directed_guitar_cam_pr]', '[directed_guitar_cam_pt]',
    '[directed_keys]', '[directed_keys_cam]', '[directed_keys_np]',
    '[directed_duo_drums]', '[directed_duo_bass]', '[directed_duo_guitar]',
    '[directed_duo_kv]', '[directed_duo_gb]', '[directed_duo_kb]', '[directed_duo_kg]',
}

DIRECTED_LABELS = {
    directed_all='All', directed_all_cam='All (Camera)', directed_all_lt='All (Long time)',
    directed_all_yeah='All (Yeah)', directed_crowd='Crowd',
    directed_drums='Drums', directed_drums_pnt='Drums (Point)',
    directed_drums_np='Drums (Not playing)', directed_drums_lt='Drums (Long time)',
    directed_drums_kd='Drums (Kick+Down)', directed_vocals='Vocals',
    directed_vocals_np='Vocals (Not playing)', directed_vocals_cls='Vocals (Close-up)',
    directed_vocals_cam_pr='Vocals (Long pre-roll)', directed_vocals_cam_pt='Vocals (Long post-roll)',
    directed_stagedive='Stage Dive', directed_crowdsurf='Crowd Surf',
    directed_bass='Bass', directed_crowd_b='Crowd (Bass)',
    directed_bass_np='Bass (Not playing)', directed_bass_cam='Bass (Camera)',
    directed_bass_cls='Bass (Close-up)', directed_guitar='Guitar',
    directed_crowd_g='Crowd (Guitar)', directed_guitar_np='Guitar (Not playing)',
    directed_guitar_cls='Guitar (Close-up)', directed_guitar_cam_pr='Guitar (Long pre-roll)',
    directed_guitar_cam_pt='Guitar (Long post-roll)', directed_keys='Keys',
    directed_keys_cam='Keys (Camera)', directed_keys_np='Keys (Not playing)',
    directed_duo_drums='Duo: Drums+Vocals', directed_duo_bass='Duo: Bass+Vocals',
    directed_duo_guitar='Duo: Guitar+Vocals', directed_duo_kv='Duo: Keys+Vocals',
    directed_duo_gb='Duo: Guitar+Bass', directed_duo_kb='Duo: Keys+Bass',
    directed_duo_kg='Duo: Keys+Guitar',
}

-- Maps bare directed-cut names to FCP spritesheet filename key (mirrors venue_sprites.lua)
DIRECTED_SPRITE_NAMES = {
    directed_all='dall',           directed_all_cam='dallcam',     directed_all_lt='dalllt',
    directed_all_yeah='dallyeah',  directed_crowd='dcrowd',
    directed_drums='ddrums',       directed_drums_pnt='ddrumspoint',
    directed_drums_np='ddrumsnp',  directed_drums_lt='ddrumslt',   directed_drums_kd='ddrumskd',
    directed_vocals='dvocals',     directed_vocals_np='dvoxnp',    directed_vocals_cls='dvoxcls',
    directed_vocals_cam_pr='dvoxcampr', directed_vocals_cam_pt='dvoxcampt',
    directed_stagedive='dstagedive', directed_crowdsurf='dcrowdsurf',
    directed_bass='dbass',         directed_crowd_b='dcrowdbass',
    directed_bass_np='dbassnp',    directed_bass_cam='dbasscam',   directed_bass_cls='dbasscls',
    directed_guitar='dgtr',        directed_crowd_g='dcrowdgtr',
    directed_guitar_np='dgtrnp',   directed_guitar_cls='dgtrcls',
    directed_guitar_cam_pr='dgtrcampr', directed_guitar_cam_pt='dgtrcampt',
    directed_keys='dkeys',         directed_keys_cam='dkeyscam',   directed_keys_np='dkeysnp',
    directed_duo_drums='dduodrums', directed_duo_bass='dduobass',
    directed_duo_guitar='dduogtr', directed_duo_kv='dduokv',
    directed_duo_gb='dduogb',      directed_duo_kb='dduokb',       directed_duo_kg='dduokg',
}

LIGHTING_NAMES = {
    'verse', 'chorus', 'manual_cool', 'manual_warm', 'dischord', 'stomp',
    'loop_cool', 'loop_warm', 'harmony', 'frenzy', 'silhouettes', 'silhouettes_spot',
    'searchlights', 'sweep', 'strobe_slow', 'strobe_fast',
    'blackout_slow', 'blackout_fast', 'blackout_spot', 'flare_slow', 'flare_fast', 'bre',
}

LIGHTING_LABELS = {
    verse='Verse (manual)', chorus='Chorus (manual)', manual_cool='Manual Cool',
    manual_warm='Manual Warm', dischord='Dischord (manual)', stomp='Stomp (manual)',
    loop_cool='Loop Cool', loop_warm='Loop Warm', harmony='Harmony', frenzy='Frenzy',
    silhouettes='Silhouettes', silhouettes_spot='Silhouettes Spot',
    searchlights='Searchlights', sweep='Sweep', strobe_slow='Strobe Slow',
    strobe_fast='Strobe Fast', blackout_slow='Blackout Slow', blackout_fast='Blackout Fast',
    blackout_spot='Blackout Spot', flare_slow='Flare Slow', flare_fast='Flare Fast', bre='BRE',
}

-- The 6 manual lighting presets that require [first]/[next] keyframe events.
MANUAL_LIGHTING_NAMES = {'verse', 'chorus', 'manual_cool', 'manual_warm', 'dischord', 'stomp'}
MANUAL_LIGHTING_SET = {}
for _, v in ipairs(MANUAL_LIGHTING_NAMES) do MANUAL_LIGHTING_SET[v] = true end

POSTPROC_NAMES = {
    'bloom.pp', 'bright.pp', 'clean_trails.pp', 'contrast_a.pp',
    'desat_blue.pp', 'desat_posterize_trails.pp', 'film_16mm.pp',
    'film_b+w.pp', 'film_blue_filter.pp', 'film_contrast.pp',
    'film_contrast_blue.pp', 'film_contrast_green.pp',
    'film_contrast_red.pp', 'film_sepia_ink.pp', 'film_silvertone.pp',
    'flicker_trails.pp', 'horror_movie_special.pp', 'photo_negative.pp',
    'photocopy.pp', 'posterize.pp', 'ProFilm_a.pp', 'ProFilm_b.pp',
    'ProFilm_mirror_a.pp', 'ProFilm_psychedelic_blue_red.pp',
    'shitty_tv.pp', 'space_woosh.pp', 'video_a.pp', 'video_bw.pp',
    'video_security.pp', 'video_trails.pp',
}

POSTPROC_LABELS = {
    ['bloom.pp']='Bloom', ['bright.pp']='Bright', ['clean_trails.pp']='Clean Trails',
    ['contrast_a.pp']='Contrast A', ['desat_blue.pp']='Desaturate Blue',
    ['desat_posterize_trails.pp']='Desaturate Posterize Trails',
    ['film_16mm.pp']='Film 16mm', ['film_b+w.pp']='Film B+W',
    ['film_blue_filter.pp']='Film Blue Filter', ['film_contrast.pp']='Film Contrast',
    ['film_contrast_blue.pp']='Film Contrast Blue',
    ['film_contrast_green.pp']='Film Contrast Green',
    ['film_contrast_red.pp']='Film Contrast Red',
    ['film_sepia_ink.pp']='Film Sepia Ink', ['film_silvertone.pp']='Film Silvertone',
    ['flicker_trails.pp']='Flicker Trails',
    ['horror_movie_special.pp']='Horror Movie Special',
    ['photo_negative.pp']='Photo Negative', ['photocopy.pp']='Photocopy',
    ['posterize.pp']='Posterize',
    ['ProFilm_a.pp']='ProFilm A', ['ProFilm_b.pp']='ProFilm B',
    ['ProFilm_mirror_a.pp']='ProFilm Mirror A',
    ['ProFilm_psychedelic_blue_red.pp']='ProFilm Psychedelic Blue Red',
    ['shitty_tv.pp']='Sucky TV', ['space_woosh.pp']='Space Woosh',
    ['video_a.pp']='Video A', ['video_bw.pp']='Video B+W',
    ['video_security.pp']='Video Security', ['video_trails.pp']='Video Trails',
}

-- Maps postproc bare names (without .pp) to the FCP spritesheet key (exceptions only).
-- Mirrors the local table in venue_sprites.lua - keep in sync if that changes.
POSTPROC_SPRITE_NAMES = {
    contrast_a='contrastbw',                  desat_posterize_trails='desatposterize',
    film_16mm='16mmfilm',                     ['film_b+w']='filmbw',
    film_blue_filter='bluefilter',            film_sepia_ink='sepiaink',
    film_silvertone='silvertone',             horror_movie_special='horrormovie',
    ProFilm_b='colormuted',                   ProFilm_mirror_a='mirror',
    ProFilm_psychedelic_blue_red='psychbluered', video_a='videograiny',
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
S = {
    status      = 'Ready.',
    last_result = nil,
    -- Demo generator settings (not persisted)
    demo_mode         = 0,    -- 0=Camera, 1=Lighting, 2=PostProc
    demo_bpm          = 120,
    demo_window_s     = 4.0,  -- seconds per event window
    demo_lt_idx       = 8,    -- index into LIGHTING_NAMES; default loop_warm (index 8)
    demo_pp_idx       = 21,   -- index into POSTPROC_NAMES; default ProFilm_a.pp (index 21)
    demo_cam_far_idx  = 2,    -- index into COOP_POOL; default coop_all_far (index 2)
    demo_cam_near_idx = 3,    -- index into COOP_POOL; default coop_all_near (index 3)
    demo_cam_combo    = DEMO_CAM_COMBO_BG,  -- which two non-drummer instruments are present
}

----------------------------------------------------------------------
-- Tooltip text
----------------------------------------------------------------------
TIPS = {
    demo_mode =
        "Which layer of events to cycle through in this pass.\n\n" ..
        "Camera  - cycles all 38 directed cuts (4 measures each).\n" ..
        "          Neutral lighting and postproc are held constant throughout.\n\n" ..
        "Coop    - cycles all coop (non-directed) camera shots (2 measures each).\n" ..
        "          Neutral lighting and postproc are held constant throughout.\n\n" ..
        "Lighting - cycles all 22 lighting presets.\n" ..
        "          Each preset gets two windows: Far (whole venue) and Near (band members).\n" ..
        "          Manual presets also generate two keyframe densities (1-beat and 2-beat).\n\n" ..
        "PostProc - cycles all 30 .pp effects x 2 camera angles (far + near).\n" ..
        "          Each effect gets one far window then one near window.\n" ..
        "          Neutral lighting is held constant throughout.\n" ..
        "          Change the neutral lighting selector and re-run to capture combinations.",

    demo_bpm =
        "Project BPM applied at t=0 before generating.\n\n" ..
        "120 BPM = 0.5 s/beat, so a 4-second window = 8 beats = 2 measures.\n" ..
        "Used to compute keyframe spacing in Lighting mode.",

    demo_window_s =
        "Duration in seconds allocated to each Lighting or PostProc event window.\n\n" ..
        "Must be long enough to capture the full animation loop (≈2.4 s) plus\n" ..
        "lead-in and settle time. 4 s is a comfortable default.",

    demo_window_s_camera =
        "Camera (directed cut) windows are fixed at 4 measures each.\n\n" ..
        "Directed cuts have variable pre-roll and some shots take time to complete\n" ..
        "before yielding - 4 measures gives enough headroom at any BPM.\n\n" ..
        "Change BPM above to adjust the absolute duration.",

    demo_window_s_coop =
        "Coop camera windows are fixed at 2 measures each.\n\n" ..
        "Coop shots are instant cuts with no pre-roll - 2 measures gives enough\n" ..
        "time to see the full composition settle.\n\n" ..
        "Change BPM above to adjust the absolute duration.",

    demo_lt_idx =
        "Neutral lighting preset held constant during Camera and PostProc passes.\n\n" ..
        "Defaults to Loop Warm for a clean, representative look.\n" ..
        "Change this and re-run to capture the same events under different lighting.",

    demo_pp_idx =
        "Neutral post-process effect held constant during Camera and Lighting passes.\n\n" ..
        "Defaults to ProFilm A (the game's default, no visible effect).",

    demo_cam_far_idx =
        "FAR camera event used for the first window of each preset in Lighting and PostProc modes\n" ..
        "(shows the whole venue).\n\n" ..
        "Defaults to coop_all_far.",

    demo_cam_near_idx =
        "NEAR camera event used for the second window of each preset in Lighting and PostProc modes\n" ..
        "(shows band members up close).\n\n" ..
        "Defaults to coop_all_near.",

    demo_cam_combo =
        "Which two non-drummer instruments are in the band.\n\n" ..
        "Directed cuts that require the absent instrument are excluded from the\n" ..
        "generated sequence - for example, selecting Bass + Guitar removes all\n" ..
        "keyboard-specific cuts ([directed_keys], [directed_duo_kb], etc.).\n\n" ..
        "Drums and vocals are always present and are never filtered.",

    demo_generate =
        "Generate the demo VENUE track in the current project.\n\n" ..
        "Clears any existing VENUE MIDI events and writes a deterministic\n" ..
        "sequence based on the current mode and neutral-layer settings.\n\n" ..
        "Also writes a manifest CSV to the project folder mapping each\n" ..
        "event key to its window start/end time and expected spritesheet filename.\n\n" ..
        "Use an empty/dedicated demo project - this REPLACES the VENUE track.",
}
