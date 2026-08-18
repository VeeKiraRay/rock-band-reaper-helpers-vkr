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
RB_DIFFICULTY_MODELS_CSV_FINGERPRINT = 864960590

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
    intercept = 5.4827260558871345,
    n_target  = 327,
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
        244.72370142434747, 3.4561140756521667, 5.73534601449274, 2.22614625565217, 
        0.30969687942028984, 0.49788645971014367, 1.4090701904347798, 1.7622543402898525, 
        0.2981267124637676, 0.8811629394202867, 1.9775942113043445, 0.544418071014492, 
        0.08424253999999984, 1.4035115707246348, 0.13086192521739112, 0.106632193043478, 
        0.008389348695652159, 0.002287539130434778, 0.0016059594202898523, 
        1179.3362318840557, 566.2930434782596, 0.03913043478260865, 0.013043478260869537
    },
    sd = {
        106.02540177887472, 1.2091845040628024, 2.322596396714506, 0.9478633000387203, 
        0.18360162145444336, 0.4426182281996173, 0.3065093767373177, 0.4832184667845705, 
        0.2094462186100278, 0.3405452951488856, 0.6604812591897071, 0.23019139534001368, 
        0.11969655012791197, 0.7775140130418987, 0.135100058551427, 0.1318902798666379, 
        0.03891747437787932, 0.014257759595912916, 0.00691463594133861, 679.6389130748107, 
        389.0389469467824, 0.1939052445302412, 0.11346076826695543
    },
    coefs = {
        0.027015830098986872, 0.02190972801740802, 0.06606087760443857, 
        0.11822299150773177, -0.03557236920430322, -0.017050139844561735, 
        -0.004522360476819948, 0.00469965444901955, 0.028531970923698285, 
        -0.02763748422088547, 0.007791677095725453, -0.020437414226609572, 
        0.01021430246417062, 0.05043303430049773, 0.04307809705846523, 
        0.019518064325467804, -0.003523177244914579, -0.0036092816752311173, 
        0.0018346593406980798, 0.04115562295421172, 0.044650479209909055, 
        -0.021497961527868245, 0.025379789788856903
    },
    bounds = {
        ["playing_s"] = { min = 13.348582, max = 1167.218083, p90 = 343.34829620000016 },
        ["attack_density_avg"] = { min = 0.315218, max = 8.219629, p90 = 4.9251854 },
        ["attack_density_peak"] = { min = 0.5, max = 19.375, p90 = 8.591250000000002 },
        ["change_rate"] = { min = 0.149829, max = 5.746648, p90 = 3.4954246 },
        ["tight_p10"] = { min = 0.083333, max = 2, p90 = 0.5 },
        ["tight_med"] = { min = 0.166667, max = 4.5, p90 = 0.5 },
        ["chord_size_mean"] = { min = 1, max = 3, p90 = 1.798515600000001 },
        ["chord_span_mean"] = { min = 0, max = 3, p90 = 2.3177032000000004 },
        ["chord_change_frac"] = { min = 0, max = 1, p90 = 0.5687944000000011 },
        ["move_mean"] = { min = 0.026667, max = 2.066929, p90 = 1.3103994000000003 },
        ["move_p90"] = { min = 0, max = 4, p90 = 3 },
        ["anchor_frac"] = { min = 0.003597, max = 1, p90 = 0.8561286000000002 },
        ["solo_frac_marked"] = { min = 0, max = 0.803191, p90 = 0.23869740000000003 },
        ["solo_change_ratio"] = { min = 0.274494, max = 6.736343, p90 = 2.5121734000000013 },
        ["sustain_frac"] = { min = 0, max = 1, p90 = 0.27536380000000005 },
        ["force_hopo_rate"] = { min = 0, max = 0.701172, p90 = 0.2627948000000001 },
        ["force_strum_rate"] = { min = 0, max = 0.46558, p90 = 0.012776400000000033 },
        ["tremolo_frac"] = { min = 0, max = 0.155672, p90 = 0 },
        ["trill_frac"] = { min = 0, max = 0.085774, p90 = 0.004136600000000005 },
        ["notes_total"] = { min = 95, max = 5274, p90 = 1921.000000000001 },
        ["total_changes"] = { min = 2, max = 2632, p90 = 974.0000000000002 },
    },
    conc = {
        solo_change_ratio = 2.5121734000000013,
        density_ratio = 2.3572721149682296,
    },
    corr = {
        ["change_rate|total_changes"] = 0.7240989394918541,
        ["chord_change_frac|anchor_frac"] = 0.7809449654121305,
        ["chord_size_mean|anchor_frac"] = 0.7178365713989943,
        ["chord_size_mean|chord_change_frac"] = 0.8458227718581847,
        ["move_mean|anchor_frac"] = -0.8649614707794251,
        ["move_mean|move_p90"] = 0.8386381357334384,
        ["move_p90|anchor_frac"] = -0.7094630516494783,
        ["notes_total|total_changes"] = 0.7668780151608291,
        ["playing_s|notes_total"] = 0.74825501045175,
        ["playing_s|total_changes"] = 0.7925718166531053,
    },
},

["bass"] = {
    candidate = "baseline+entropy",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 1e-006,
    rank_lo   = 89,
    rank_hi   = 480,
    intercept = 5.365619867489438,
    n_target  = 330,
    n_lego    = 60,
    keys = {
        "total_changes",
        "density_peak",
        "entropy_h2",
        "is_lego",
        "is_rb2",
    },
    mean = {
        379.42356321839037, 4.453739224137921, 1.13517677011494, 0.038793103448275815, 
        0.012931034482758593
    },
    sd = {
        287.9688229791429, 2.0122054839270835, 0.37841284258782143, 0.19310152400519048, 
        0.11297708984552705
    },
    coefs = {
        0.11162389721526997, 0.16837394188962787, 0.0868810050280315, 
        -0.028393480473581766, 0.04532398115563178
    },
    bounds = {
        ["total_changes"] = { min = 13, max = 1957, p90 = 691 },
        ["density_peak"] = { min = 0.25, max = 19, p90 = 6.75 },
        ["entropy_h2"] = { min = 0.027409, max = 1.872931, p90 = 1.6269718 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 2.0891660435704815,
    },
    corr = {
    },
},

["drum"] = {
    candidate = "full_drum@noroll",
    scale     = "log(rank)",
    status    = "validated",
    ridge     = 0.1,
    rank_lo   = 93,
    rank_hi   = 550,
    intercept = 5.437034571602421,
    n_target  = 328,
    n_lego    = 60,
    keys = {
        "playing_s",
        "density_avg",
        "density_peak_noroll",
        "change_rate",
        "attack_density_avg",
        "attack_density_peak_noroll",
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
        "hand_density_peak_noroll",
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
        "is_rb2",
    },
    mean = {
        249.7687607459534, 6.649232170809233, 8.536753973988422, 3.4776997872832305, 
        4.340900405780334, 5.675010838150278, 0.3271363075144508, 0.4520110754335253, 
        1.5459578994219612, 2.1936035245664716, 0.5302662395953742, 0.839112785260114, 
        1.7139691699421953, 0.6886810684971086, 1.8186019416184926, 2.617489161849704, 
        6.348361632947964, 1.247776989306355, 0.21982588323699362, 0.003101381502890166, 
        0.5570548705202302, 6.218641618497098, 1.0047999280346798, 0.8791555419075122, 
        1669.0953757225407, 873.2774566473971, 0.03901734104046238, 0.01300578034682078
    },
    sd = {
        92.39113301626246, 1.6622129813815536, 2.1385636902012206, 0.941231032806894, 
        1.137925431238347, 1.6233926089903317, 0.13399742023039146, 0.1585880031828273, 
        0.18698655328150407, 0.42751598527495766, 0.12439213625440625, 0.2787409258864441, 
        0.579564578961174, 0.1731232528639342, 0.6513612745053061, 1.016160142415686, 
        1.590888040245183, 0.13052970242120954, 0.2633457091735243, 0.008526199599229484, 
        0.128230335933938, 1.1928523419572852, 0.3558668146112079, 0.32730679811351704, 
        787.7286012866192, 411.64347741410546, 0.1936362263074619, 0.11329885270553733
    },
    coefs = {
        0.02460168021533878, 0.03274757077681184, 0.05583199910292732, 
        0.028295533620390948, 0.03563964880671196, 0.05338067857998349, 
        -0.036131851723377274, 0.024165647098450118, -0.011931481700884457, 
        0.009982118521742493, 0.0129680477992524, -0.0023626233419875927, 
        -0.005243735083040148, -0.02447362801941443, -0.008421970301813648, 
        0.06509794972358024, 0.027271781291123676, -0.01392198769874271, 
        -0.00043030648216871016, -0.0004604935793290803, 0.017219197848940774, 
        0.00397840425480445, 0.039406732900608636, 0.024359528424077646, 
        0.007806620558587195, 0.012650423360099012, -0.006739148069913349, 
        0.02103068532137083
    },
    bounds = {
        ["playing_s"] = { min = 87.755744, max = 826.617249, p90 = 348.72141130000006 },
        ["density_avg"] = { min = 2.185571, max = 12.090831, p90 = 8.6530875 },
        ["density_peak_noroll"] = { min = 4.25, max = 16.5, p90 = 11.25 },
        ["change_rate"] = { min = 0.854403, max = 6.928745, p90 = 4.5570330000000006 },
        ["attack_density_avg"] = { min = 1.604955, max = 9.584378, p90 = 5.7855663 },
        ["attack_density_peak_noroll"] = { min = 2.125, max = 11.25, p90 = 7.662500000000001 },
        ["tight_p10"] = { min = 0.083333, max = 1, p90 = 0.5 },
        ["tight_med"] = { min = 0.125, max = 1, p90 = 0.5 },
        ["chord_size_mean"] = { min = 1.149083, max = 2.666667, p90 = 1.7247726 },
        ["chord_span_mean"] = { min = 1, max = 3.49537, p90 = 2.7114508 },
        ["chord_change_frac"] = { min = 0.180672, max = 1, p90 = 0.6570862000000001 },
        ["move_mean"] = { min = 0.188135, max = 1.918593, p90 = 1.2235223000000002 },
        ["move_p90"] = { min = 0.333333, max = 4, p90 = 2.5 },
        ["anchor_frac"] = { min = 0.151475, max = 1, p90 = 0.908188 },
        ["kick_density"] = { min = 0.653757, max = 3.974139, p90 = 2.7315563000000003 },
        ["kick_density_peak"] = { min = 0.875, max = 5.93125, p90 = 4 },
        ["hand_density_peak_noroll"] = { min = 3.125, max = 11.5, p90 = 8.375 },
        ["stick_size_mean"] = { min = 1, max = 2, p90 = 1.3680522 },
        ["tom_frac"] = { min = 0, max = 1, p90 = 0.5973921000000001 },
        ["roll_frac"] = { min = 0, max = 0.060074, p90 = 0.011702100000000005 },
        ["offbeat_frac"] = { min = 0.024348, max = 0.856861, p90 = 0.7202681 },
        ["pro_stations_peak"] = { min = 2, max = 8, p90 = 8 },
        ["entropy_h2"] = { min = 0.005913, max = 2.115015, p90 = 1.4923974000000002 },
        ["entropy_h2_rel"] = { min = 0.008869, max = 1.843546, p90 = 1.3046913999999998 },
        ["notes_total"] = { min = 463, max = 5528, p90 = 2518.2000000000003 },
        ["total_changes"] = { min = 163, max = 2806, p90 = 1324.6000000000004 },
    },
    conc = {
        solo_change_ratio = 1,
        density_ratio = 1.610052492181758,
    },
    corr = {
        ["attack_density_avg|attack_density_peak_noroll"] = 0.800082929368699,
        ["attack_density_avg|hand_density_peak_noroll"] = 0.7677019929444552,
        ["attack_density_peak_noroll|hand_density_peak_noroll"] = 0.8838038489744423,
        ["change_rate|attack_density_avg"] = 0.8503977115699733,
        ["chord_size_mean|chord_change_frac"] = 0.8685393594654672,
        ["chord_size_mean|stick_size_mean"] = 0.7242003873718057,
        ["density_avg|attack_density_avg"] = 0.8986413191277889,
        ["density_avg|change_rate"] = 0.8342484718888655,
        ["density_avg|density_peak_noroll"] = 0.827669734445709,
        ["density_avg|hand_density_peak_noroll"] = 0.7786403393308612,
        ["density_avg|kick_density"] = 0.7345348984480632,
        ["density_peak_noroll|attack_density_avg"] = 0.7594415453553577,
        ["density_peak_noroll|attack_density_peak_noroll"] = 0.842101985893896,
        ["density_peak_noroll|hand_density_peak_noroll"] = 0.9203134857797459,
        ["density_peak_noroll|kick_density_peak"] = 0.7470779072628362,
        ["entropy_h2|entropy_h2_rel"] = 0.9550272364230029,
        ["kick_density|kick_density_peak"] = 0.8133576166851265,
        ["move_mean|move_p90"] = 0.7946217089261696,
        ["notes_total|total_changes"] = 0.9480081456518259,
        ["playing_s|notes_total"] = 0.8398956222065079,
        ["playing_s|total_changes"] = 0.8182099192995517,
        ["tight_med|offbeat_frac"] = -0.8218189511291523,
        ["tight_p10|offbeat_frac"] = -0.7245175959264326,
    },
},

["keys"] = {
    candidate = "primary+ent_rel+complex@attacks-chord",
    scale     = "rank",
    status    = "beta",
    ridge     = 0.1,
    rank_lo   = 90,
    rank_hi   = 495,
    intercept = 281.015037593985,
    n_target  = 266,
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
        388.2293233082707, 4.000610902255639, 0.5044995263157895, 0.9341087067669174, 
        224.58087007142854, 1.0272181616541354, 7.658189124060154, 0, 0
    },
    sd = {
        309.90440565423245, 2.011142212987085, 0.7017369152880115, 1.220554861814807, 
        100.65797172052514, 0.3915444190030697, 4.334911379746863, 1, 1
    },
    coefs = {
        19.984973871195788, 27.765512009927598, -2.7980734557022866, 0.8232502580108563, 
        8.270625586331313, 11.147736084781606, 33.297511151496835, 0, 0
    },
    bounds = {
        ["total_changes"] = { min = 3, max = 1886, p90 = 784.5 },
        ["attack_density_peak"] = { min = 0.25, max = 12.5, p90 = 6.540625 },
        ["tight_p10"] = { min = 0.083333, max = 8, p90 = 0.7083335 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 1.6875 },
        ["playing_s"] = { min = 29.179926, max = 800.699134, p90 = 341.4668915 },
        ["entropy_h2_rel"] = { min = 0, max = 2.195125, p90 = 1.570729 },
        ["complex_peak"] = { min = 0, max = 22.013519, p90 = 13.2535165 },
    },
    conc = {
        solo_change_ratio = 1.4042985,
        density_ratio = 2.7513252438760505,
    },
    corr = {
        ["attack_density_peak|complex_peak"] = 0.7787512730258799,
        ["tight_p10|tight_med"] = 0.7454157909766136,
        ["total_changes|playing_s"] = 0.7078425709323852,
    },
},

["real_keys"] = {
    candidate = "primary+ent_rel@attacks",
    scale     = "rank",
    status    = "experimental",
    ridge     = 1e-006,
    rank_lo   = 80,
    rank_hi   = 505,
    intercept = 293.70300751879694,
    n_target  = 266,
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
        385.65413533834584, 4.061325187969924, 0.4722618984962406, 0.9193256578947369, 
        1.6932598609022538, 224.58087007142854, 0.8198802706766917, 0, 0
    },
    sd = {
        301.97624875762324, 2.0762115640349577, 0.6779917661213916, 1.1497982120770387, 
        0.5395154073302181, 100.65797172052514, 0.30874544505175283, 1, 1
    },
    coefs = {
        36.443548012881855, 43.49851596431582, -3.19509196236511, -6.815887477888555, 
        14.669904476987883, -3.615123003713574, 23.538028395913393, 0, 0
    },
    bounds = {
        ["total_changes"] = { min = 3, max = 1916, p90 = 788.5 },
        ["attack_density_peak"] = { min = 0.25, max = 12.5, p90 = 6.6875 },
        ["tight_p10"] = { min = 0.0625, max = 8, p90 = 0.5 },
        ["tight_med"] = { min = 0.125, max = 8, p90 = 2 },
        ["chord_size_mean"] = { min = 1, max = 3.293436, p90 = 2.43842 },
        ["playing_s"] = { min = 29.179926, max = 800.699134, p90 = 341.4668915 },
        ["entropy_h2_rel"] = { min = 0, max = 1.599962, p90 = 1.253007 },
    },
    conc = {
        solo_change_ratio = 1.306536,
        density_ratio = 2.7493362585475185,
    },
    corr = {
        ["tight_p10|tight_med"] = 0.7188109958566061,
        ["total_changes|playing_s"] = 0.7151576019048789,
    },
},

["vocals"] = {
    candidate = "parts+tess+move@parts_step3",
    scale     = "log(rank)",
    status    = "experimental",
    ridge     = 0.01,
    rank_lo   = 112,
    rank_hi   = 495,
    intercept = 5.502131002931569,
    n_target  = 328,
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
        "parts_3",
        "high_time_70",
        "pc_change_rate",
        "is_lego",
        "is_rb2",
    },
    mean = {
        2.134372021965312, 1.2970895953757187, 0.3085723196531787, 0.514711893063583, 
        1.5206084471098225, 170.13220724161823, 18.368208092485528, 65.32543352601142, 
        0.01045707803468206, 0.5404624277456637, 0.05806099190751433, 1.4539746554913264, 
        0.03901734104046238, 0.01300578034682078
    },
    sd = {
        0.6178510841370136, 0.5968544090599358, 0.09982591600288551, 0.15210539704981788, 
        0.44983200356841185, 51.061012802300944, 5.977967806973046, 8.416290662250027, 
        0.022739439218959476, 0.4983601026776993, 0.10960763379420019, 0.4811810971660276, 
        0.1936362263074619, 0.11329885270553733
    },
    coefs = {
        -0.0035697618794355707, 0.013000110502459746, -0.005192316799861242, 
        -0.009680940086768825, 0.008452320285814009, 0.047574134934001776, 
        0.0404850348744928, 0.027025252762518357, 0.020088282236183263, 
        0.07168240316289574, 0.05556894259181317, 0.08852388951520042, 
        -0.03025689600371801, 0.04212608680676181
    },
    bounds = {
        ["syl_density_avg"] = { min = 0.762242, max = 5.255975, p90 = 2.9076128000000003 },
        ["syl_density_peak"] = { min = 0.5, max = 4.96, p90 = 1.8300000000000012 },
        ["tight_p10"] = { min = 0.140417, max = 0.5625, p90 = 0.4375 },
        ["tight_med"] = { min = 0.25, max = 1, p90 = 0.6875 },
        ["pc_interval_mean"] = { min = 0, max = 2.440541, p90 = 2.0121246999999998 },
        ["playing_s"] = { min = 60.716846, max = 462.986219, p90 = 223.32283 },
        ["notated_range"] = { min = 0, max = 37, p90 = 26 },
        ["pitch_p90"] = { min = 0, max = 78, p90 = 71 },
        ["octave_jump_rate"] = { min = 0, max = 0.18957, p90 = 0.032050700000000015 },
        ["parts_3"] = { min = 0, max = 1, p90 = 1 },
        ["high_time_70"] = { min = 0, max = 0.776139, p90 = 0.1961618 },
        ["pc_change_rate"] = { min = 0, max = 3.7565, p90 = 2.0059747000000003 },
    },
    conc = {
        solo_change_ratio = 0,
    },
    corr = {
        ["tight_p10|tight_med"] = 0.7047813061126207,
    },
},
}
