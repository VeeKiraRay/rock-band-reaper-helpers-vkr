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
--   keys        factor order. The TRAILING entries are the training-time origin flags,
--               one per PROTOCOL.AUX_ORIGINS entry and named is_<origin>; product
--               predictions always pass 0 for every one of them.
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
--   corr        pairwise correlation between this model's own factors, over the same
--               rb3_dlc rows as bounds, emitted only for pairs at |r| >= 0.70. Lets the
--               explanation panel drop a "notable property" that merely restates one it
--               has already shown - which factors duplicate is per-instrument, so it is
--               measured rather than hand-grouped. Key is the two factor names joined by
--               '|'; readers must try both orderings.
--   status      model maturity for the UI badge. Describes validation against noisy
--               official ranks, NOT the probability that a prediction is correct.

RB_DIFFICULTY_MODELS_SCHEMA = 3
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
    rank_lo   = 75,
    rank_hi   = 605,
    intercept = 5.480763299219961,
    n_target  = 312,
    n_lego    = 60,
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
        "is_rb2",
    },
    mean = {
        244.30716375272686, 3.4473596609090826, 5.727672348484835, 2.219609070303026, 
        0.3112740103030303, 0.5002525109090896, 1.4115942233333303, 1.7661019769696944, 
        0.3006738660606054, 0.8799204730303004, 1.9811212209090876, 0.5446965439393932, 
        0.0859112584848483, 1.4120069663636334, 0.13231252181818168, 0.10716381696969669, 
        0.008742531212121195, 0.002391518181818177, 0.0016683878787878755, 
        1172.793939393937, 564.673030303029, 0.04090909090909086, 0.013636363636363606
    },
    sd = {
        105.33513758592547, 1.2170837136392143, 2.355741720584582, 0.9472968052891751, 
        0.18565745330073766, 0.4505657149096591, 0.3083247469785301, 0.48072354665094535, 
        0.20990253679299226, 0.3411564284244924, 0.6624262732749631, 0.2292550806864255, 
        0.12127740444942917, 0.7843653332007351, 0.13574908793035562, 0.1337657698438957, 
        0.039754508398563315, 0.014569667445757665, 0.007061262216627678, 
        665.2475410494648, 389.7845357411427, 0.198079623359099, 0.11597591656520966
    },
    coefs = {
        0.027579034145181362, 0.023267753217386927, 0.06771409876605883, 
        0.12341559093445968, -0.035158510282609044, -0.01750841091938836, 
        -0.0030042377739227144, 0.004440108321380677, 0.0277340727603285, 
        -0.024594038400484255, 0.004290025112837677, -0.01981848584782346, 
        0.008960440249434883, 0.051171425274376285, 0.042548007058363785, 
        0.017355296988240218, -0.00299899899788942, -0.0036522091771374644, 
        0.0020870398198682355, 0.03898624633447806, 0.04220065424928411, 
        -0.02193217357790948, 0.025365869631600813
    },
    bounds = {
        ["playing_s"] = { min = 13.348582, max = 1167.218083, p90 = 341.1616836 },
        ["attack_density_avg"] = { min = 0.315218, max = 8.219629, p90 = 4.928140900000001 },
        ["attack_density_peak"] = { min = 0.5, max = 19.375, p90 = 8.625 },
        ["change_rate"] = { min = 0.149829, max = 5.746648, p90 = 3.4676861 },
        ["tight_p10"] = { min = 0.083333, max = 2, p90 = 0.5 },
        ["tight_med"] = { min = 0.166667, max = 4.5, p90 = 0.5 },
        ["chord_size_mean"] = { min = 1, max = 3, p90 = 1.8178272000000002 },
        ["chord_span_mean"] = { min = 0, max = 3, p90 = 2.3256438999999998 },
        ["chord_change_frac"] = { min = 0, max = 1, p90 = 0.5892226 },
        ["move_mean"] = { min = 0.026667, max = 2.066929, p90 = 1.3067441000000006 },
        ["move_p90"] = { min = 0, max = 4, p90 = 3 },
        ["anchor_frac"] = { min = 0.003597, max = 1, p90 = 0.8586181000000002 },
        ["solo_frac_marked"] = { min = 0, max = 0.803191, p90 = 0.2396664 },
        ["solo_change_ratio"] = { min = 0.274494, max = 6.736343, p90 = 2.5298764000000014 },
        ["sustain_frac"] = { min = 0, max = 1, p90 = 0.27495770000000014 },
        ["force_hopo_rate"] = { min = 0, max = 0.701172, p90 = 0.2638583000000001 },
        ["force_strum_rate"] = { min = 0, max = 0.46558, p90 = 0.014301000000000036 },
        ["tremolo_frac"] = { min = 0, max = 0.155672, p90 = 0 },
        ["trill_frac"] = { min = 0, max = 0.085774, p90 = 0.0044960000000000095 },
        ["notes_total"] = { min = 95, max = 5274, p90 = 1888.7000000000012 },
        ["total_changes"] = { min = 2, max = 2632, p90 = 971.2000000000003 },
    },
    conc = {
        solo_change_ratio = 2.5298764000000014,
        density_ratio = 2.3593820540550077,
    },
    corr = {
        ["change_rate|total_changes"] = 0.7330351387176589,
        ["chord_change_frac|anchor_frac"] = 0.7786805157106393,
        ["chord_size_mean|anchor_frac"] = 0.713679885962077,
        ["chord_size_mean|chord_change_frac"] = 0.8435158089780306,
        ["move_mean|anchor_frac"] = -0.8650063669512431,
        ["move_mean|move_p90"] = 0.8379598728045387,
        ["move_p90|anchor_frac"] = -0.701188150033027,
        ["notes_total|total_changes"] = 0.7663679839605024,
        ["playing_s|notes_total"] = 0.7347713102406279,
        ["playing_s|total_changes"] = 0.7906995373705483,
    },
},

["bass"] = {
    candidate = "baseline+entropy",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 1e-006,
    rank_lo   = 89,
    rank_hi   = 480,
    intercept = 5.361801231036816,
    n_target  = 315,
    n_lego    = 60,
    keys = {
        "total_changes",
        "density_peak",
        "entropy_h2",
        "is_lego",
        "is_rb2",
    },
    mean = {
        375.346546546546, 4.450153903903894, 1.1292720060060035, 0.04054054054054049, 
        0.013513513513513483
    },
    sd = {
        288.23665310605315, 2.0377834807491633, 0.38087363827966636, 0.19722323674765418, 
        0.11545951007185842
    },
    coefs = {
        0.11128910333019736, 0.1724286135444511, 0.08741541962131895, 
        -0.028941279609766734, 0.0461348225403734
    },
    bounds = {
        ["total_changes"] = { min = 13, max = 1957, p90 = 687.2 },
        ["density_peak"] = { min = 0.25, max = 19, p90 = 6.825000000000003 },
        ["entropy_h2"] = { min = 0.027409, max = 1.872931, p90 = 1.6252546 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 2.095489569064651,
    },
    corr = {
    },
},

["drum"] = {
    candidate = "primary+limbs+ent+offbeat",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 0.01,
    rank_lo   = 93,
    rank_hi   = 550,
    intercept = 5.43204616786513,
    n_target  = 313,
    n_lego    = 60,
    keys = {
        "total_changes",
        "hand_density_peak",
        "tight_p10",
        "tight_med",
        "stick_size_mean",
        "playing_s",
        "kick_density_peak",
        "entropy_h2",
        "offbeat_frac",
        "is_lego",
        "is_rb2",
    },
    mean = {
        867.1419939577021, 6.499193731117812, 0.3303801492447129, 0.45285749879154, 
        1.2502541942598158, 248.82060466797557, 2.6129758308157025, 1.0007159096676714, 
        0.5556048132930503, 0.04078549848942593, 0.013595166163141964
    },
    sd = {
        412.4964704647457, 1.9823234911752865, 0.13507198225287462, 0.15984881852734004, 
        0.1315624298072191, 92.50548021868036, 1.023578872696359, 0.353720823681143, 
        0.12857228578045043, 0.19779292606762996, 0.11580301213758876
    },
    coefs = {
        0.15286584100219827, 0.08793707617748645, -0.046127745853974673, 
        0.010557390166021198, -0.034283518513044245, -0.0831335108806027, 
        0.12199838617378392, 0.07824996650003666, 0.018942248575865794, 
        -0.002139562890969427, 0.029294245572833888
    },
    bounds = {
        ["total_changes"] = { min = 163, max = 2806, p90 = 1293.8 },
        ["hand_density_peak"] = { min = 3.125, max = 25.625, p90 = 8.75 },
        ["tight_p10"] = { min = 0.083333, max = 1, p90 = 0.5 },
        ["tight_med"] = { min = 0.125, max = 1, p90 = 0.5 },
        ["stick_size_mean"] = { min = 1, max = 2, p90 = 1.3711524000000002 },
        ["playing_s"] = { min = 87.755744, max = 826.617249, p90 = 346.9773478 },
        ["kick_density_peak"] = { min = 0.875, max = 5.93125, p90 = 4 },
        ["entropy_h2"] = { min = 0.005913, max = 2.115015, p90 = 1.4869756 },
        ["offbeat_frac"] = { min = 0.024348, max = 0.856861, p90 = 0.7204966 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 1.6157637744348816,
    },
    corr = {
        ["tight_med|offbeat_frac"] = -0.8237151084641576,
        ["tight_p10|offbeat_frac"] = -0.7280624354953913,
        ["total_changes|playing_s"] = 0.8144057010164139,
    },
},

["keys"] = {
    candidate = "primary+ent_rel+complex@attacks-chord",
    scale     = "log(rank)",
    status    = "beta",
    ridge     = 0.1,
    rank_lo   = 90,
    rank_hi   = 495,
    intercept = 5.554599411098208,
    n_target  = 251,
    n_lego    = 0,
    keys = {
        "total_changes",
        "attack_density_peak",
        "tight_p10",
        "tight_med",
        "playing_s",
        "entropy_h2_rel",
        "complex_peak",
        "is_lego",
        "is_rb2",
    },
    mean = {
        379.3585657370518, 3.948630478087649, 0.5188786494023906, 0.960715470119522, 
        221.86100841832672, 1.0190221832669326, 7.534759063745025, 0, 0
    },
    sd = {
        309.1741198270825, 2.0401926176195753, 0.7195928081285822, 1.2506535102889917, 
        100.90759774844068, 0.39207719740088876, 4.40432155861704, 1, 1
    },
    coefs = {
        0.05220271494889162, 0.0950675177410407, -0.02626426364246473, 
        -0.009730990971589849, 0.030697296396786585, 0.045081239659005984, 
        0.12533585273613831, 0, 0
    },
    bounds = {
        ["total_changes"] = { min = 3, max = 1886, p90 = 784 },
        ["attack_density_peak"] = { min = 0.25, max = 12.5, p90 = 6.58125 },
        ["tight_p10"] = { min = 0.083333, max = 8, p90 = 0.75 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 2 },
        ["playing_s"] = { min = 29.179926, max = 800.699134, p90 = 331.656064 },
        ["entropy_h2_rel"] = { min = 0, max = 2.062117, p90 = 1.575536 },
        ["complex_peak"] = { min = 0, max = 22.013519, p90 = 13.235205 },
    },
    conc = {
        solo_change_ratio = 1.396315,
        density_ratio = 2.7489914255903,
    },
    corr = {
        ["attack_density_peak|complex_peak"] = 0.7868343438285724,
        ["tight_p10|tight_med"] = 0.7442411612832743,
        ["total_changes|playing_s"] = 0.7067133739383307,
    },
},

["real_keys"] = {
    candidate = "primary+ent_rel@attacks",
    scale     = "rank",
    status    = "experimental",
    ridge     = 0.01,
    rank_lo   = 80,
    rank_hi   = 505,
    intercept = 288.42629482071703,
    n_target  = 251,
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
        "is_rb2",
    },
    mean = {
        375.9282868525896, 4.00699701195219, 0.48670649800796806, 0.946792, 
        1.6958242231075684, 221.86100841832672, 0.8145377649402392, 0, 0
    },
    sd = {
        300.6706495132812, 2.1072106043574688, 0.6949240937784414, 1.1773183416835311, 
        0.5449768447359911, 100.90759774844068, 0.3121940437167813, 1, 1
    },
    coefs = {
        36.353086405623, 44.03656142134766, -2.629869045243475, -6.838555116997856, 
        14.93569749445212, -4.44906172953333, 22.985654096631936, 0, 0
    },
    bounds = {
        ["total_changes"] = { min = 3, max = 1916, p90 = 753 },
        ["attack_density_peak"] = { min = 0.25, max = 12.5, p90 = 6.75 },
        ["tight_p10"] = { min = 0.0625, max = 8, p90 = 0.666667 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 2 },
        ["chord_size_mean"] = { min = 1, max = 3.293436, p90 = 2.478261 },
        ["playing_s"] = { min = 29.179926, max = 800.699134, p90 = 331.656064 },
        ["entropy_h2_rel"] = { min = 0, max = 1.599962, p90 = 1.247528 },
    },
    conc = {
        solo_change_ratio = 1.291296,
        density_ratio = 2.742064468167082,
    },
    corr = {
        ["tight_p10|tight_med"] = 0.7175752241723634,
        ["total_changes|playing_s"] = 0.7137730291214831,
    },
},

["vocals"] = {
    candidate = "primary+range+parts",
    scale     = "log(rank)",
    status    = "experimental",
    ridge     = 0.1,
    rank_lo   = 112,
    rank_hi   = 495,
    intercept = 5.497297791815318,
    n_target  = 313,
    n_lego    = 60,
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
        "is_rb2",
    },
    mean = {
        2.131528110574013, 1.295447129909362, 0.30982811661631365, 0.5155516827794554, 
        1.5309684311178213, 168.06532441268854, 18.34561933534741, 65.28277945619321, 
        0.01050250755287007, 2.31419939577038, 0.04078549848942593, 0.013595166163141964
    },
    sd = {
        0.6192408807621828, 0.6034729394053064, 0.1004345412960728, 0.15437051895085652, 
        0.45185277212368125, 47.24186021218737, 6.031403505138854, 8.542009542129152, 
        0.022928856452284242, 0.8102874482311601, 0.19779292606762996, 0.11580301213758876
    },
    coefs = {
        0.02938868803012981, 0.019265231566623804, -0.018667430152334033, 
        -0.004386610352417699, 0.06455418274102664, 0.043867321653187054, 
        0.05330242560483454, 0.05144104668727351, 0.03216747425325856, 0.07455485237969553, 
        -0.021359537866881027, 0.046572608197882635
    },
    bounds = {
        ["syl_density_avg"] = { min = 0.762242, max = 5.255975, p90 = 2.9008442000000003 },
        ["syl_density_peak"] = { min = 0.5, max = 4.96, p90 = 1.880000000000001 },
        ["tight_p10"] = { min = 0.140417, max = 0.5625, p90 = 0.4375 },
        ["tight_med"] = { min = 0.25, max = 1, p90 = 0.6875 },
        ["pc_interval_mean"] = { min = 0, max = 2.440541, p90 = 2.0145918 },
        ["playing_s"] = { min = 60.716846, max = 418.263446, p90 = 221.09339359999998 },
        ["notated_range"] = { min = 0, max = 37, p90 = 26 },
        ["pitch_p90"] = { min = 0, max = 78, p90 = 71 },
        ["octave_jump_rate"] = { min = 0, max = 0.18957, p90 = 0.032655200000000016 },
        ["vocal_parts"] = { min = 0, max = 3, p90 = 3 },
    },
    conc = {
        solo_change_ratio = 0,
    },
    corr = {
        ["tight_p10|tight_med"] = 0.7076824481293159,
    },
},
}
