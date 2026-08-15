-- GENERATED FILE - DO NOT EDIT BY HAND.
--
-- Written by dev/calibration/export_production_models.lua from
-- dev/calibration/corpus_scores.csv. Re-run the exporter to change anything here; a hand
-- edit would be silently overwritten and, worse, would not be reproducible from the
-- corpus it claims to describe.
--
-- One frozen model per instrument: the candidate the locked protocol selected, refit once
-- on every row it was allowed to train on. Apply with DifficultyPredictRank in
-- lib/reaper_difficulty_predict.lua - the coefficients are in STANDARDIZED units and mean
-- nothing applied to raw factors by hand.
--
-- Field notes:
--   keys        factor order. The LAST entry is always is_lego, a training-time origin
--               flag; product predictions always pass 0 for it.
--   mean / sd   standardization statistics from the fit, over ALL training rows including
--               the down-weighted lego ones. Only valid paired with these coefs.
--   rank_lo/hi  observed rank range of the rb3_dlc training rows. The final rank is
--               clamped to it; individual factors never are.
--   bounds      per-factor min/max/p90 over the rb3_dlc training rows - the support the
--               suggestion is honest about. A DIFFERENT row set from mean/sd, on purpose:
--               every prediction is made on the RB3 scale.
--   conc        concentration thresholds (p90) for the "difficulty is concentrated in a
--               short passage" note. Measured per instrument because a single cutoff is
--               wrong - bass and drums never mark a solo at all.
--   status      model maturity for the UI badge. Describes validation against noisy
--               official ranks, NOT the probability that a prediction is correct.

RB_DIFFICULTY_MODELS_SCHEMA = 1
RB_DIFFICULTY_MODELS_CSV_FINGERPRINT = 4207280094

RB_DIFFICULTY_MODEL_ORDER = {
    "guitar",
    "bass",
    "drum",
    "keys",
    "real_keys",
    "vocals",
}

RB_DIFFICULTY_MODELS = {

["guitar"] = {
    candidate = "full@attacks",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 0.1,
    rank_lo   = 125,
    rank_hi   = 605,
    intercept = 5.535562833197784,
    n_target  = 158,
    n_lego    = 45,
    keys = {
        "playing_s",
        "attack_density_avg",
        "attack_density_peak",
        "change_rate",
        "tight_p10",
        "tight_med",
        "chord_size_mean",
        "chord_span_mean",
        "chord_change_frac",
        "move_mean",
        "move_p90",
        "anchor_frac",
        "solo_frac_marked",
        "solo_change_ratio",
        "sustain_frac",
        "force_hopo_rate",
        "force_strum_rate",
        "tremolo_frac",
        "trill_frac",
        "notes_total",
        "total_changes",
        "is_lego",
    },
    mean = {
        244.0912055096201, 3.5728372466472194, 5.927889941690944, 2.375923332944599, 
        0.2954640746355678, 0.44880950320699675, 1.3556805259475182, 1.7748457562682156, 
        0.2634272600583083, 0.9172531900874611, 2.03958212769679, 0.5072996472303188, 
        0.09884669329446033, 1.4817706927113674, 0.12550403965014545, 0.10830401107871693, 
        0.0094312437317784, 0.002926693877551012, 0.0025849795918367275, 1176.694460641396, 
        600.0285714285693, 0.07871720116618058
    },
    sd = {
        91.90379641573132, 1.2297599312528287, 2.3051311872749243, 0.9359471764460603, 
        0.15426462981769978, 0.25915650975106685, 0.2554411725009285, 0.4260373523693878, 
        0.17400872755301094, 0.32288727821262964, 0.6084333194454239, 0.21371565832858805, 
        0.12992224674746122, 0.7503809081092796, 0.12616817493055846, 0.13682569280127793, 
        0.038292711156550675, 0.018190139645831785, 0.009318755613139868, 
        604.9998915246389, 386.125035716407, 0.26929686854240176
    },
    coefs = {
        0.04372372343334303, 0.030132941716551075, 0.06999536281391695, 
        0.10988844246669105, -0.047381946272983436, -0.017150719288051407, 
        3.991096269897493e-005, -0.0036559098072479635, 0.04494697813315396, 
        -0.012927223789699658, 0.008239409284113264, -0.018926707977447752, 
        0.012452459769986532, 0.05769330087154066, 0.0420949224329217, 
        0.006965596790398937, -0.005964533177218514, -0.004900081537011219, 
        -0.0013780859004998605, 0.027287358668216098, 0.025574859432361926, 
        -0.036176542490182796
    },
    bounds = {
        ["playing_s"] = { min = 26.545466, max = 809.331069, p90 = 357.41756270000013 },
        ["attack_density_avg"] = { min = 0.561671, max = 8.219629, p90 = 5.171382400000001 },
        ["attack_density_peak"] = { min = 0.75, max = 14.875, p90 = 9.125 },
        ["change_rate"] = { min = 0.33472, max = 5.746648, p90 = 3.7123116000000005 },
        ["tight_p10"] = { min = 0.125, max = 1, p90 = 0.5 },
        ["tight_med"] = { min = 0.25, max = 3, p90 = 0.5 },
        ["chord_size_mean"] = { min = 1, max = 2.40274, p90 = 1.6240456 },
        ["chord_span_mean"] = { min = 0, max = 3, p90 = 2.3229853 },
        ["chord_change_frac"] = { min = 0, max = 1, p90 = 0.4887114 },
        ["move_mean"] = { min = 0.096133, max = 1.905276, p90 = 1.3115766000000002 },
        ["move_p90"] = { min = 0, max = 4, p90 = 3 },
        ["anchor_frac"] = { min = 0.003597, max = 0.98174, p90 = 0.8223605 },
        ["solo_frac_marked"] = { min = 0, max = 0.803191, p90 = 0.2554039000000001 },
        ["solo_change_ratio"] = { min = 0.417645, max = 4.493007, p90 = 2.6720064000000003 },
        ["sustain_frac"] = { min = 0, max = 1, p90 = 0.2287870000000001 },
        ["force_hopo_rate"] = { min = 0, max = 0.701172, p90 = 0.2656778000000001 },
        ["force_strum_rate"] = { min = 0, max = 0.310072, p90 = 0.014551200000000005 },
        ["tremolo_frac"] = { min = 0, max = 0.155672, p90 = 0 },
        ["trill_frac"] = { min = 0, max = 0.085774, p90 = 0.007808100000000005 },
        ["notes_total"] = { min = 95, max = 3717, p90 = 1868.9000000000003 },
        ["total_changes"] = { min = 44, max = 2512, p90 = 1096.9 },
    },
    conc = {
        solo_change_ratio = 2.6720064000000003,
        density_ratio = 2.251158391639551,
    },
},

["bass"] = {
    candidate = "baseline+ent_rel@attacks",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 1e-006,
    rank_lo   = 117,
    rank_hi   = 480,
    intercept = 5.39249056336381,
    n_target  = 159,
    n_lego    = 45,
    keys = {
        "total_changes",
        "attack_density_peak",
        "entropy_h2_rel",
        "is_lego",
    },
    mean = {
        388.85913043478143, 4.501123188405785, 1.1629336597101412, 0.07826086956521722
    },
    sd = {
        283.3321610567686, 1.9364467935112406, 0.37141340425227454, 0.2685816558518345
    },
    coefs = {
        0.08783889188825621, 0.192001247187596, 0.07435363436727678, -0.050423926791858135
    },
    bounds = {
        ["total_changes"] = { min = 19, max = 1957, p90 = 626.8000000000013 },
        ["attack_density_peak"] = { min = 0.75, max = 12.225, p90 = 6.775000000000002 },
        ["entropy_h2_rel"] = { min = 0.163978, max = 1.964793, p90 = 1.6304458 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 2.090430748669315,
    },
},

["drum"] = {
    candidate = "full_drum",
    scale     = "rank",
    status    = "validated",
    ridge     = 0.1,
    rank_lo   = 120,
    rank_hi   = 484,
    intercept = 250.60521739130303,
    n_target  = 159,
    n_lego    = 45,
    keys = {
        "playing_s",
        "density_avg",
        "density_peak",
        "change_rate",
        "attack_density_avg",
        "attack_density_peak",
        "tight_p10",
        "tight_med",
        "chord_size_mean",
        "chord_span_mean",
        "chord_change_frac",
        "move_mean",
        "move_p90",
        "anchor_frac",
        "kick_density",
        "kick_density_peak",
        "hand_density_peak",
        "stick_size_mean",
        "tom_frac",
        "roll_frac",
        "offbeat_frac",
        "pro_stations_peak",
        "entropy_h2",
        "entropy_h2_rel",
        "notes_total",
        "total_changes",
        "is_lego",
    },
    mean = {
        247.86516187420227, 6.804524084637663, 8.917018115942003, 3.5313322771014435, 
        4.413396936811585, 6.081413043478243, 0.32280192289855003, 0.447294673043478, 
        1.548223856811589, 2.1961146202898476, 0.5394101785507234, 0.8137938794202876, 
        1.6571014539130398, 0.6980776788405779, 1.8264393542028932, 2.6839239130434707, 
        6.785047101449254, 1.2494092092753593, 0.2038144973913039, 0.004213785507246366, 
        0.5584090759420275, 6.326376811594175, 1.0335481171014462, 0.9110335188405773, 
        1693.481159420285, 876.1895652173885, 0.07826086956521722
    },
    sd = {
        84.63305678936422, 1.6616155969770976, 2.611559264547573, 0.9288064574041973, 
        1.043774757309762, 2.301558987563789, 0.1273340757613169, 0.15491100086293694, 
        0.16571254428367863, 0.4074541367486919, 0.11415442213069288, 0.2604620852177987, 
        0.5600382169841246, 0.17152910768436908, 0.6786228541995436, 1.089032718250887, 
        2.2170661517309327, 0.11801792430298769, 0.24465527436665013, 0.009653593353071005, 
        0.12070949566120794, 1.2937418722164233, 0.34484497645190954, 0.3169860462269529, 
        790.8290401878596, 397.7091975352823, 0.2685816558518345
    },
    coefs = {
        -0.3446011616038358, 13.63454541985317, 17.31671166790854, 6.785021671537289, 
        21.444151620233313, 2.683971150949147, -7.640011849646013, 4.081328735766314, 
        -7.448222220621162, 5.239788059445172, 2.8786253467082004, -2.2733335300072026, 
        1.3814722816924596, -7.354626771391241, -12.05805260656702, 22.388861468702057, 
        -6.28210147953102, 4.719221807967266, 1.9345623987485363, 0.21646845616956167, 
        6.621128898878657, -0.39256681107427005, 5.517092462917188, 7.341583169700659, 
        9.847781041715127, 4.51790010811897, -2.2523881298979345
    },
    bounds = {
        ["playing_s"] = { min = 87.755744, max = 711.930081, p90 = 363.60228000000006 },
        ["density_avg"] = { min = 3.195176, max = 12.090831, p90 = 8.778455800000001 },
        ["density_peak"] = { min = 4.875, max = 25.625, p90 = 12.025000000000002 },
        ["change_rate"] = { min = 1.681238, max = 6.454151, p90 = 4.605320400000002 },
        ["attack_density_avg"] = { min = 2.073274, max = 7.125892, p90 = 5.961016000000001 },
        ["attack_density_peak"] = { min = 3.375, max = 25.625, p90 = 8.400000000000002 },
        ["tight_p10"] = { min = 0.083333, max = 0.5, p90 = 0.5 },
        ["tight_med"] = { min = 0.25, max = 1, p90 = 0.5 },
        ["chord_size_mean"] = { min = 1.243021, max = 2.318332, p90 = 1.6972198 },
        ["chord_span_mean"] = { min = 1, max = 3.078493, p90 = 2.6625422 },
        ["chord_change_frac"] = { min = 0.198529, max = 0.989983, p90 = 0.6723150000000002 },
        ["move_mean"] = { min = 0.227477, max = 1.918593, p90 = 1.1208318000000002 },
        ["move_p90"] = { min = 0.5, max = 3, p90 = 2.460000000000001 },
        ["anchor_frac"] = { min = 0.151475, max = 1, p90 = 0.910061 },
        ["kick_density"] = { min = 0.662415, max = 3.974139, p90 = 2.714203200000001 },
        ["kick_density_peak"] = { min = 1.125, max = 5.93125, p90 = 4.150000000000002 },
        ["hand_density_peak"] = { min = 3.375, max = 25.625, p90 = 9.5 },
        ["stick_size_mean"] = { min = 1, max = 1.987899, p90 = 1.3592218 },
        ["tom_frac"] = { min = 0, max = 1, p90 = 0.5269192000000001 },
        ["roll_frac"] = { min = 0, max = 0.060074, p90 = 0.014778000000000008 },
        ["offbeat_frac"] = { min = 0.170996, max = 0.856861, p90 = 0.7136938 },
        ["pro_stations_peak"] = { min = 2, max = 8, p90 = 8 },
        ["entropy_h2"] = { min = 0.127049, max = 1.841827, p90 = 1.4998700000000003 },
        ["entropy_h2_rel"] = { min = 0.122225, max = 1.680699, p90 = 1.320110600000001 },
        ["notes_total"] = { min = 502, max = 5528, p90 = 2439.2000000000016 },
        ["total_changes"] = { min = 263, max = 2675, p90 = 1284.8000000000002 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 1.5750853454436098,
    },
},

["keys"] = {
    candidate = "primary+entropy_rel+complex_peak",
    scale     = "rank",
    status    = "beta",
    ridge     = 0.1,
    rank_lo   = 130,
    rank_hi   = 488,
    intercept = 281.03278688524586,
    n_target  = 122,
    n_lego    = 0,
    keys = {
        "total_changes",
        "density_peak",
        "tight_p10",
        "tight_med",
        "chord_size_mean",
        "playing_s",
        "entropy_h2_rel",
        "complex_peak",
        "is_lego",
    },
    mean = {
        384.94262295081967, 5.954866803278688, 0.47209698360655744, 0.8867486229508196, 
        1.512424254098362, 221.02123569672116, 1.040071401639344, 7.952419844262292, 0
    },
    sd = {
        280.9968000278775, 2.9659787013650742, 0.7430030188807889, 1.13029443574164, 
        0.37886280287615093, 91.60026022740786, 0.36665155686065015, 4.600545585838883, 1
    },
    coefs = {
        19.719507806472762, 30.03854611070344, -1.0329860685425027, 0.7160912123114952, 
        -12.858664002343508, -0.8115701244579301, 18.64759668436102, 32.17234845893156, 0
    },
    bounds = {
        ["total_changes"] = { min = 14, max = 1670, p90 = 740.7000000000002 },
        ["density_peak"] = { min = 1.09375, max = 13.375, p90 = 10.125 },
        ["tight_p10"] = { min = 0.083333, max = 8, p90 = 0.5 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 1.5 },
        ["chord_size_mean"] = { min = 1, max = 2.797203, p90 = 2.0108243 },
        ["playing_s"] = { min = 29.179926, max = 473.514269, p90 = 349.94541730000003 },
        ["entropy_h2_rel"] = { min = 0.047445, max = 1.762838, p90 = 1.5630469000000002 },
        ["complex_peak"] = { min = 0, max = 22.013519, p90 = 13.896128800000001 },
    },
    conc = {
        solo_change_ratio = 1.2364010000000005,
        density_ratio = 2.743397310334657,
    },
},

["real_keys"] = {
    candidate = "primary+ent_rel@attacks",
    scale     = "rank",
    status    = "experimental",
    ridge     = 0.1,
    rank_lo   = 135,
    rank_hi   = 489,
    intercept = 291.76229508196724,
    n_target  = 122,
    n_lego    = 0,
    keys = {
        "total_changes",
        "attack_density_peak",
        "tight_p10",
        "tight_med",
        "chord_size_mean",
        "playing_s",
        "entropy_h2_rel",
        "is_lego",
    },
    mean = {
        383.5, 4.2326844262295085, 0.4577663688524591, 0.9298411803278689, 
        1.7041760491803275, 221.02123569672116, 0.8399412049180327, 0
    },
    sd = {
        275.42087763287947, 2.177821355708592, 0.7443869227475568, 1.1763653674886707, 
        0.543103385550659, 91.60026022740786, 0.29593521335932943, 1
    },
    coefs = {
        27.07465204867565, 45.52671535359145, -4.339541825974601, -5.2109858267993685, 
        12.224714740402854, -3.860446995457405, 26.467627629394986, 0
    },
    bounds = {
        ["total_changes"] = { min = 14, max = 1328, p90 = 737.4000000000001 },
        ["attack_density_peak"] = { min = 0.375, max = 12.5, p90 = 6.528125 },
        ["tight_p10"] = { min = 0.11875, max = 8, p90 = 0.5 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 2 },
        ["chord_size_mean"] = { min = 1, max = 3.072258, p90 = 2.5448374000000005 },
        ["playing_s"] = { min = 29.179926, max = 473.514269, p90 = 349.94541730000003 },
        ["entropy_h2_rel"] = { min = 0.03174, max = 1.599962, p90 = 1.2204030000000001 },
    },
    conc = {
        solo_change_ratio = 1.2691227000000014,
        density_ratio = 2.737163048653761,
    },
},

["vocals"] = {
    candidate = "primary+range+parts",
    scale     = "log(rank)",
    status    = "experimental",
    ridge     = 0.1,
    rank_lo   = 112,
    rank_hi   = 495,
    intercept = 5.449855413300132,
    n_target  = 157,
    n_lego    = 45,
    keys = {
        "syl_density_avg",
        "syl_density_peak",
        "tight_p10",
        "tight_med",
        "pc_interval_mean",
        "playing_s",
        "notated_range",
        "pitch_p90",
        "octave_jump_rate",
        "vocal_parts",
        "is_lego",
    },
    mean = {
        2.1539745325513118, 1.2719706744868018, 0.3206544568914946, 0.5215622035190597, 
        1.4504901941348929, 165.15589408387046, 17.885043988269732, 64.32668621700863, 
        0.010633755425219908, 2.214076246334307, 0.07917888563049835
    },
    sd = {
        0.5692753552596136, 0.624292222599853, 0.09606138147770264, 0.15102166390731067, 
        0.4641716387720225, 44.57286562389087, 6.20932364041195, 10.795650144357666, 
        0.02630624488964818, 0.8308078851257261, 0.27001775812122203
    },
    coefs = {
        -0.003414239882890953, 0.03372086293283427, -0.0006525460429315157, 
        -0.020656618524876706, 0.046600169654991384, 0.025320251249973735, 
        0.07122811833590363, 0.05248824554943997, 0.024400583487659788, 0.0776832074177053, 
        -0.0243688727164592
    },
    bounds = {
        ["syl_density_avg"] = { min = 0.762242, max = 4.390931, p90 = 2.8855994000000003 },
        ["syl_density_peak"] = { min = 0.5, max = 4.96, p90 = 1.7 },
        ["tight_p10"] = { min = 0.158333, max = 0.5, p90 = 0.43775 },
        ["tight_med"] = { min = 0.25, max = 1, p90 = 0.6875 },
        ["pc_interval_mean"] = { min = 0, max = 2.388998, p90 = 1.9598622 },
        ["playing_s"] = { min = 76.535196, max = 326.828299, p90 = 218.60418320000002 },
        ["notated_range"] = { min = 0, max = 33, p90 = 26 },
        ["pitch_p90"] = { min = 0, max = 78, p90 = 70.4 },
        ["octave_jump_rate"] = { min = 0, max = 0.18957, p90 = 0.029943600000000018 },
        ["vocal_parts"] = { min = 1, max = 3, p90 = 3 },
    },
    conc = {
        solo_change_ratio = 0,
    },
},
}
