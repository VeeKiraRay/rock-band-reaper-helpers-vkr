-- Extended genre vocabulary, and how each one maps onto the supported list.
--
-- The authored half of the genre converter. metadata_genres.lua holds what Rock Band
-- supports; this file holds the genres authors actually think in, and says which
-- supported pair each one is closest to.
--
-- Entries carry 1 to 3 candidates, best first. A second candidate means the style has
-- more than one defensible home, and the 'why' on each says what tips the choice.
--
-- The catalogue is mostly CONSISTENT, so do not read multiple candidates as the norm:
-- only 56 of 795 artists carrying subgenre data are filed under more than one pair, and
-- a multi-filed artist has at least three possible explanations that must not be
-- conflated:
--   1. The band genuinely changed style between releases. Both filings are correct and
--      there is nothing ambiguous to report.
--   2. The cataloguing convention changed between game eras. A Day to Remember is filed
--      punk/alternative on both its RB2 songs and rock/hardrock on both its RB3 ones,
--      while the songs come from adjacent easycore-era albums - that is the era moving,
--      not the band.
--   3. The boundary really is ambiguous for one song. Five Finger Death Punch has
--      metal/metal and rock/hardrock in the SAME era off the same album cycle.
-- Only case 3 justifies a second candidate here. dev/tools/genre_corpus_report.lua
-- regenerates the multi-filed list so the calls can be re-checked against the web.
--
-- Calibrated against 3126 catalogue songs (1375 carrying a subgenre, 1319 artists) in
-- _external_docs/genre_reference_songs/. Findings that shaped entries below:
--   * The -core family is one bucket. metalcore, deathcore, mathcore and the heavier
--     end of post-hardcore all sit under Metal / Metalcore in practice.
--   * Heavy but radio-facing goes to Rock / Hard Rock, not Metal. Creed, Seether,
--     Five Finger Death Punch and A Day to Remember are all filed there.
--   * Djent splits for real: Periphery is Metal / Progressive, TesseracT is
--     Prog / Prog Rock. Both candidates are listed rather than picking a winner.
--   * Post-hardcore is the widest spread in the catalogue, reaching Metal / Metalcore,
--     Rock / Hard Rock and Alternative / Alternative depending on how melodic it is.
--
-- Guidance, not rules - the source documentation says so of its own list. Where this
-- table gives one candidate, that is the preferred convention after reviewing the
-- available catalogue, NOT a proven one: the evidence above is artist-level filing, and
-- an artist is not a style. A second candidate is a real fork, not hedging.
--
-- WHICH DIMENSION WINS. The extended list deliberately mixes sound, era, origin, subject
-- matter and instrumentation, because those are all things authors call their songs. The
-- precedence is fixed, and entries that look inconsistent are following it:
--   1. An explicit supported category for that exact thing. J-Rock maps by origin only
--      because Rock Band HAS a J-Rock genre; K-Pop has no equivalent so it maps by sound.
--      Same for Novelty, Inspirational and Classical, which are defined by intent,
--      content and tradition rather than by arrangement.
--   2. Otherwise musical style, which is what most entries use.
--   3. Otherwise scene or origin.
--   4. Otherwise instrumentation or source, which is the weakest basis and why Acoustic,
--      Instrumental Rock, Holiday and Video Game Music all say to file by the music where
--      one can.
--
-- SEE_ALSO IS NOT A CANDIDATE. An optional see_also entry points at another entry in THIS
-- table, for when the pick itself looks wrong - Post-Grunge offering Grunge, say. It is
-- deliberately not a candidate, because a candidate means "another supported home for
-- what you picked" and this means "you may have picked the wrong thing". The UI draws
-- them differently for that reason.
--
-- Every { genre, subgenre } pair here must exist in RB3_GENRES; dev/tests asserts it.
-- Pure data. No r / ctx / S / TIPS dependencies.

GENRE_FAMILY_ORDER = {
    'rock', 'metal', 'punk', 'pop', 'electronic',
    'hiphop', 'rnb', 'country_folk', 'jazz_blues', 'world_other',
}

GENRE_FAMILIES = {
    rock         = 'Rock',
    metal        = 'Metal',
    punk         = 'Punk and Hardcore',
    pop          = 'Pop and New Wave',
    electronic   = 'Electronic',
    hiphop       = 'Hip-Hop and Rap',
    rnb          = 'R&B, Soul and Funk',
    country_folk = 'Country and Folk',
    jazz_blues   = 'Jazz and Blues',
    world_other  = 'World, Classical and Other',
}

EXTENDED_GENRES = {

    ----------------------------------------------------------------
    -- Rock
    ----------------------------------------------------------------
    { key = 'rock_general', label = 'Rock (general)', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'rock', why = 'The catch-all for guitar-led rock with no stronger pull in another direction.' },
    } },
    { key = 'classic_rock', label = 'Classic Rock', family = 'rock', candidates = {
        { genre = 'classic_rock', subgenre = 'classic_rock', why = 'Its own major genre. Use it for the 60s to 80s rock canon.' },
        { genre = 'rock', subgenre = 'rock', why = 'A modern band writing in the period style is usually filed as plain rock instead.' },
    } },
    { key = 'hard_rock', label = 'Hard Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'hard_rock', why = 'Heavy and riff-driven while still radio-facing. The catalogue leans on this one heavily.' },
    } },
    { key = 'arena_rock', label = 'Arena Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'arena', why = 'Big, anthemic and built for singalongs.' },
        { genre = 'rock', subgenre = 'hard_rock', why = 'Use this instead when the riffing matters more than the chorus.' },
    } },
    { key = 'psychedelic_rock', label = 'Psychedelic Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'psychedelic', why = 'Effects-soaked, exploratory rock.' },
    } },
    { key = 'garage_rock', label = 'Garage Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'garage', why = 'Raw, simple and deliberately unpolished.' },
        { genre = 'punk', subgenre = 'garage', why = 'Use the punk side when it is faster and shorter than it is bluesy.' },
    } },
    { key = 'surf_rock', label = 'Surf Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'surf', why = 'Reverb-drenched instrumental guitar leads.' },
    } },
    { key = 'rockabilly', label = 'Rockabilly', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'rockabilly', why = 'Exact match. The documentation names Stray Cats and Reverend Horton Heat.' },
    } },
    { key = 'rock_and_roll', label = 'Rock and Roll', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'rock_and_roll', why = 'The 50s original. The documentation names Chuck Berry.' },
    } },
    { key = 'blues_rock', label = 'Blues Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'blues_rock', why = 'Blues form played with rock weight and volume.' },
        { genre = 'blues', subgenre = 'electric', why = 'Use Blues instead when the blues idiom leads and the rock is the accent.' },
    } },
    { key = 'folk_rock', label = 'Folk Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'folk', why = 'Acoustic-rooted songwriting played by a rock band.' },
    } },
    { key = 'southern_rock', label = 'Southern Rock', family = 'rock', candidates = {
        { genre = 'southern_rock', subgenre = 'southern_rock', why = 'Its own major genre.' },
    } },
    { key = 'glam_rock', label = 'Glam Rock', family = 'rock', candidates = {
        { genre = 'glam', subgenre = 'glam', why = 'Its own major genre. The 70s glitter era rather than the 80s metal one.' },
        { genre = 'metal', subgenre = 'hair', why = 'Use Metal / Hair for the 80s Sunset Strip sound instead.' },
    } },
    { key = 'gothic_rock', label = 'Gothic Rock', family = 'rock', candidates = {
        { genre = 'glam', subgenre = 'goth', why = 'The supported home for goth, sitting under Glam.' },
        { genre = 'new_wave', subgenre = 'dark_wave', why = 'Prefer Dark Wave when synths carry the song rather than guitars.' },
    } },
    { key = 'grunge', label = 'Grunge', family = 'rock', candidates = {
        { genre = 'grunge', subgenre = 'grunge', why = 'Its own major genre. The documentation names Nirvana and Pearl Jam.' },
    } },
    { key = 'post_grunge', label = 'Post-Grunge', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'hard_rock', why = 'Where the catalogue actually files it. Creed and Seether both land here, not under Grunge.' },
    }, see_also = {
        { key = 'grunge', when = 'the song belongs to the early 90s wave rather than following it' },
    } },
    { key = 'alternative_rock', label = 'Alternative Rock', family = 'rock', candidates = {
        { genre = 'alternative', subgenre = 'alternative', why = 'Its own major genre, and one of the largest buckets in the catalogue.' },
    } },
    { key = 'college_rock', label = 'College Rock', family = 'rock', candidates = {
        { genre = 'alternative', subgenre = 'college', why = 'Exact match. The documentation names early R.E.M.' },
    } },
    { key = 'indie_rock', label = 'Indie Rock', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'indie_rock', why = 'Its own major genre.' },
    } },
    { key = 'britpop', label = 'Britpop', family = 'rock', candidates = {
        { genre = 'alternative', subgenre = 'alternative', why = 'The 90s British guitar-pop wave sits with alternative.' },
        { genre = 'pop_rock', subgenre = 'pop', why = 'Use Pop-Rock when the song is more hook than edge.' },
    } },
    { key = 'post_rock', label = 'Post-Rock', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'post_rock', why = 'Exact match. Often instrumental, built on texture and dynamics.' },
    } },
    { key = 'math_rock', label = 'Math Rock', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'math_rock', why = 'Exact match. Odd meters and angular writing with an indie tone.' },
    } },
    { key = 'shoegaze', label = 'Shoegaze', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'shoegazing', why = 'Exact match. Layered guitar wash with vocals buried as texture.' },
    } },
    { key = 'dream_pop', label = 'Dream Pop', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'shoegazing', why = 'The closest supported sound: hazy, texture-led and vocal-soft.' },
        { genre = 'indie_rock', subgenre = 'indie_rock', why = 'Use the plain indie entry when the songs are more direct than atmospheric.' },
    } },
    { key = 'lo_fi', label = 'Lo-fi', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'lo_fi', why = 'Exact match. Audible home production is the defining trait.' },
    } },
    { key = 'noise_rock', label = 'Noise Rock', family = 'rock', candidates = {
        { genre = 'indie_rock', subgenre = 'noise', why = 'Exact match. Dissonance and effects over conventional structure.' },
    } },
    { key = 'jam_band', label = 'Jam Band', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'rock', why = 'No jam category exists, and extended improvisation alone does not move the genre.' },
        { genre = 'rock', subgenre = 'psychedelic', why = 'Use this when the jamming is exploratory rather than groove-based.' },
    } },
    { key = 'stoner_rock', label = 'Stoner Rock', family = 'rock', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'Down-tuned and riff-led enough that the catalogue treats it as metal.' },
        { genre = 'rock', subgenre = 'hard_rock', why = 'Prefer this when the songs stay groovy rather than heavy.' },
    } },
    { key = 'space_rock', label = 'Space Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'psychedelic', why = 'Long, drifting and effects-led.' },
        { genre = 'prog', subgenre = 'prog_rock', why = 'Use Prog when the arrangements are composed rather than drifting.' },
    } },
    { key = 'krautrock', label = 'Krautrock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'psychedelic', why = 'Repetition-driven experimental rock, closest to the psychedelic entry.' },
        { genre = 'indie_rock', subgenre = 'post_rock', why = 'Prefer this for the motorik, largely instrumental end.' },
    } },
    { key = 'prog_rock', label = 'Progressive Rock', family = 'rock', candidates = {
        { genre = 'prog', subgenre = 'prog_rock', why = 'Its own major genre with a single subgenre. The documentation names Rush and Yes.' },
    } },
    { key = 'art_rock', label = 'Art Rock', family = 'rock', candidates = {
        { genre = 'prog', subgenre = 'prog_rock', why = 'The supported home for composed, unconventional rock.' },
        { genre = 'alternative', subgenre = 'alternative', why = 'Use this when it is more left-field than technical.' },
    } },
    { key = 'symphonic_rock', label = 'Symphonic Rock', family = 'rock', candidates = {
        { genre = 'prog', subgenre = 'prog_rock', why = 'Orchestral scale and long forms put it with prog.' },
    } },
    { key = 'j_rock', label = 'J-Rock', family = 'rock', candidates = {
        { genre = 'j_rock', subgenre = 'j_rock', why = 'Its own major genre, defined by origin rather than by sound.' },
    } },
    { key = 'christian_rock', label = 'Christian Rock', family = 'rock', candidates = {
        { genre = 'inspirational', subgenre = 'inspirational', why = 'The supported genre is defined by lyrical content, not by the arrangement.' },
        { genre = 'rock', subgenre = 'rock', why = 'Use the musical genre instead if the lyrics are not the point of the song.' },
    } },
    { key = 'instrumental_rock', label = 'Instrumental Rock', family = 'rock', candidates = {
        { genre = 'rock', subgenre = 'rock', why = 'No instrumental category exists; file by the music rather than by the absence of vocals.' },
    } },

    ----------------------------------------------------------------
    -- Metal
    ----------------------------------------------------------------
    { key = 'heavy_metal', label = 'Heavy Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'The general metal bucket, and a large one in the catalogue.' },
    } },
    { key = 'nwobhm', label = 'NWOBHM', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'No era-specific category exists; the plain metal entry is the home for it.' },
        { genre = 'classic_rock', subgenre = 'classic_rock', why = 'Only for the earliest, most rock-leaning end of it.' },
    } },
    { key = 'thrash_metal', label = 'Thrash Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'thrash', why = 'Exact match. The documentation names the Big 4.' },
    } },
    { key = 'speed_metal', label = 'Speed Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'speed', why = 'Exact match, under the Metal genre.' },
        { genre = 'metal', subgenre = 'thrash', why = 'Prefer Thrash when the riffing is palm-muted and aggressive rather than melodic.' },
    } },
    { key = 'groove_metal', label = 'Groove Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'thrash', why = 'Grew directly out of thrash and keeps its riff vocabulary at lower tempo.' },
        { genre = 'metal', subgenre = 'metal', why = 'Use the general entry when the groove is closer to mainstream metal.' },
    } },
    { key = 'death_metal', label = 'Death Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'death', why = 'Exact match. Growled vocals and double-bass drumming.' },
    } },
    { key = 'melodic_death_metal', label = 'Melodic Death Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'death', why = 'Still death metal by vocal and rhythm; the melody does not move it out.' },
        { genre = 'metal', subgenre = 'power', why = 'Only when clean vocals carry the song and the melodies turn major-key. Gothenburg-style melodeath stays minor and growled.' },
    } },
    { key = 'technical_death_metal', label = 'Technical Death Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'death', why = 'The parent style. Technicality does not move it out of death metal.' },
        { genre = 'metal', subgenre = 'progressive', why = 'Use this when the foundation is prog metal rather than death metal: clean passages, dynamics, odd meters as structure rather than as difficulty.' },
    } },
    { key = 'grindcore', label = 'Grindcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'death', why = 'The closest supported extreme-metal bucket; no grind category exists.' },
        { genre = 'punk', subgenre = 'hardcore', why = 'Prefer this for the punk-rooted end with short, fast songs.' },
    } },
    { key = 'black_metal', label = 'Black Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'black', why = 'Exact match. The documentation names Emperor and Mayhem.' },
    } },
    { key = 'blackgaze', label = 'Blackgaze', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'black', why = 'Keeps black metal tremolo and blast beats underneath the wash.' },
        { genre = 'indie_rock', subgenre = 'shoegazing', why = 'Use this when the atmosphere leads and the metal is texture.' },
    } },
    { key = 'viking_metal', label = 'Viking Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'black', why = 'The style grew out of black metal and most of its founders played it. Listen for tremolo riffing and blast beats.' },
        { genre = 'metal', subgenre = 'power', why = 'Prefer Power when the vocals are clean and the melodies are anthemic.' },
        { genre = 'metal', subgenre = 'death', why = 'Norse themes over melodic death metal riffing and growls. Amon Amarth is the band most often called Viking metal by mistake.' },
    } },
    { key = 'folk_metal', label = 'Folk Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'power', why = 'The melodic, anthemic branch, where clean vocals sit over folk instrumentation.' },
        { genre = 'metal', subgenre = 'black', why = 'Use this for the harsh-vocal, pagan branch built on black metal.' },
        { genre = 'metal', subgenre = 'death', why = 'Use this for the melodic death metal branch, where the growls and riffing carry the song.' },
    } },
    { key = 'power_metal', label = 'Power Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'power', why = 'Exact match, and the single largest metal subgenre in the catalogue.' },
    } },
    { key = 'symphonic_metal', label = 'Symphonic Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'power', why = 'The documentation lists Nightwish under Power, which is this style exactly.' },
        { genre = 'metal', subgenre = 'progressive', why = 'Use this when the arrangements are complex rather than anthemic.' },
    } },
    { key = 'progressive_metal', label = 'Progressive Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'progressive', why = 'Exact match. The documentation names Dream Theater.' },
        { genre = 'prog', subgenre = 'prog_rock', why = 'Use Prog when the song is more progressive than it is heavy.' },
    } },
    { key = 'djent', label = 'Djent', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'progressive', why = 'Where Periphery is filed. Extended-range riffing with prog structure.' },
        { genre = 'prog', subgenre = 'prog_rock', why = 'Where TesseracT is filed. Use this for the atmospheric, clean-sung end.' },
        { genre = 'metal', subgenre = 'metal', why = 'The catalogue also uses the plain metal entry for After the Burial.' },
    } },
    { key = 'avant_garde_metal', label = 'Avant-Garde Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'progressive', why = 'The documentation describes Progressive as genre-mixing and boundary-pushing.' },
    } },
    { key = 'doom_metal', label = 'Doom Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'No doom category exists; slow and heavy still files as metal.' },
        { genre = 'metal', subgenre = 'black', why = 'Only for genuinely blackened doom: tremolo riffing, blast beats and black metal atmosphere. Harsh vocals alone are not enough.' },
    } },
    { key = 'sludge_metal', label = 'Sludge Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'The general metal entry is the closest supported home.' },
        { genre = 'metal', subgenre = 'metalcore', why = 'Prefer this when hardcore vocals and breakdowns are present.' },
    } },
    { key = 'stoner_metal', label = 'Stoner Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'Down-tuned riff metal with no dedicated category.' },
    } },
    { key = 'drone_metal', label = 'Drone Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'No drone category exists; the general metal entry is the fallback.' },
        { genre = 'other', subgenre = 'experimental', why = 'Use this when the piece is closer to sound art than to a song.' },
    } },
    { key = 'gothic_metal', label = 'Gothic Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'Metal underneath, with the goth element in the atmosphere.' },
        { genre = 'glam', subgenre = 'goth', why = 'Use this when the goth identity outweighs the metal.' },
    } },
    { key = 'industrial_metal', label = 'Industrial Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'industrial', why = 'Exact match. The documentation names Ministry and Rammstein.' },
    } },
    { key = 'nu_metal', label = 'Nu-Metal', family = 'metal', candidates = {
        { genre = 'nu_metal', subgenre = 'nu_metal', why = 'Its own major genre. The documentation names KoRn and Limp Bizkit.' },
    } },
    { key = 'rap_metal', label = 'Rap Metal', family = 'metal', candidates = {
        { genre = 'nu_metal', subgenre = 'nu_metal', why = 'The documentation defines Nu-Metal as hip-hop rhythm over down-tuned riffs.' },
        { genre = 'metal', subgenre = 'alternative', why = 'Use this when the rapping is occasional rather than the main vocal.' },
    } },
    { key = 'alternative_metal', label = 'Alternative Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'alternative', why = 'Exact match, under the Metal genre.' },
        { genre = 'rock', subgenre = 'hard_rock', why = 'The catalogue often uses Hard Rock for the radio-facing end of this.' },
    } },
    { key = 'funk_metal', label = 'Funk Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'alternative', why = 'The closest supported bucket for groove-led crossover metal.' },
    } },
    { key = 'post_metal', label = 'Post-Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metal', why = 'No post-metal category exists; slow, heavy and atmospheric still files as metal.' },
        { genre = 'indie_rock', subgenre = 'post_rock', why = 'Use this when it is post-rock dynamics with metal weight rather than metal with long builds.' },
    } },
    { key = 'industrial_rock', label = 'Industrial Rock', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'industrial', why = 'The supported Industrial entry sits under Metal and fits guitar-led industrial.' },
        { genre = 'pop_dance_electronic', subgenre = 'industrial', why = 'Use the electronic Industrial entry when programming leads and the guitars are texture.' },
    } },
    { key = 'metalcore', label = 'Metalcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Exact match, and the largest metal subgenre bucket after Power.' },
    } },
    { key = 'melodic_metalcore', label = 'Melodic Metalcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Sits in the same -core bucket; the clean choruses do not move it out.' },
    } },
    { key = 'deathcore', label = 'Deathcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'The catalogue treats the whole -core family as one bucket.' },
        { genre = 'metal', subgenre = 'death', why = 'Prefer this when growls and blast beats outweigh the breakdowns.' },
    } },
    { key = 'mathcore', label = 'Mathcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Where Converge and The Dillinger Escape Plan are filed.' },
        { genre = 'metal', subgenre = 'progressive', why = 'Use this when the complexity is the point rather than the aggression.' },
    } },
    { key = 'metallic_hardcore', label = 'Metallic Hardcore', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Sits inside the same -core bucket.' },
        { genre = 'punk', subgenre = 'hardcore', why = 'Prefer the punk side when the songs keep hardcore length and tempo.' },
    } },
    { key = 'hair_metal', label = 'Hair Metal', family = 'metal', candidates = {
        { genre = 'metal', subgenre = 'hair', why = 'Exact match. The documentation names Poison and Motley Crue.' },
    } },

    ----------------------------------------------------------------
    -- Punk and Hardcore
    ----------------------------------------------------------------
    { key = 'punk_rock', label = 'Punk Rock', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'classic', why = 'The original three-chord form.' },
        { genre = 'punk', subgenre = 'alternative', why = 'The catalogue uses this broadly for modern punk of no fixed sub-style.' },
    } },
    { key = 'pop_punk', label = 'Pop-Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'pop_punk', why = 'Exact match. The documentation names Green Day and Blink 182.' },
    } },
    { key = 'easycore', label = 'Easycore', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'pop_punk', why = 'The pop-punk half: catchy melodies and pop-punk song structure carry the track.' },
        { genre = 'metal', subgenre = 'metalcore', why = 'The other half: heavy breakdowns and screamed vocals. Pick by which one dominates.' },
        { genre = 'rock', subgenre = 'hard_rock', why = 'What the RB3-era catalogue used for A Day to Remember, the defining band of the style.' },
    } },
    { key = 'skate_punk', label = 'Skate Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'pop_punk', why = 'Shares the tempo and production values of pop-punk.' },
        { genre = 'punk', subgenre = 'alternative', why = 'Where the catalogue files MxPx and Teenage Bottlerocket.' },
    } },
    { key = 'hardcore_punk', label = 'Hardcore Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'hardcore', why = 'Exact match. Fast, short and shouted.' },
    } },
    { key = 'post_hardcore', label = 'Post-Hardcore', family = 'punk', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Where the heavier end sits: screamed vocals and breakdowns.' },
        { genre = 'rock', subgenre = 'hard_rock', why = 'Use it for the melodic, radio-facing end, which the catalogue files as hard rock.' },
        { genre = 'alternative', subgenre = 'alternative', why = 'The catalogue also files Emarosa and A Skylit Drive here.' },
    } },
    { key = 'screamo', label = 'Screamo', family = 'punk', candidates = {
        { genre = 'emo', subgenre = 'emo', why = 'Screamo is an offshoot of emo, and Emo is its own supported genre. Right for the original 90s style.' },
        { genre = 'punk', subgenre = 'hardcore', why = 'The other half of its ancestry. Use this for the chaotic, hardcore-paced end.' },
        { genre = 'metal', subgenre = 'metalcore', why = 'Right only for the loose 2000s use of the word, meaning post-hardcore and melodic metalcore bands.' },
    } },
    { key = 'emo', label = 'Emo', family = 'punk', candidates = {
        { genre = 'emo', subgenre = 'emo', why = 'Its own major genre.' },
    } },
    { key = 'emo_pop', label = 'Emo Pop', family = 'punk', candidates = {
        { genre = 'emo', subgenre = 'emo', why = 'Its own major genre covers this directly.' },
        { genre = 'punk', subgenre = 'pop_punk', why = 'Use this when the hooks and tempo are pop-punk first.' },
    } },
    { key = 'street_punk', label = 'Street Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'classic', why = 'Keeps the classic punk form and attitude.' },
    } },
    { key = 'oi', label = 'Oi!', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'classic', why = 'A classic-era punk offshoot with no category of its own.' },
    } },
    { key = 'crust_punk', label = 'Crust Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'hardcore', why = 'Hardcore punk with metal weight.' },
        { genre = 'metal', subgenre = 'death', why = 'Use this for the most extreme, growled end.' },
    } },
    { key = 'd_beat', label = 'D-Beat', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'hardcore', why = 'Defined by a hardcore punk drum pattern.' },
    } },
    { key = 'powerviolence', label = 'Powerviolence', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'hardcore', why = 'Hardcore taken to its fastest and shortest extreme.' },
    } },
    { key = 'anarcho_punk', label = 'Anarcho-Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'hardcore', why = 'Musically hardcore; the politics do not change the filing.' },
        { genre = 'punk', subgenre = 'classic', why = 'Use this for the earlier, less aggressive end.' },
    } },
    { key = 'garage_punk', label = 'Garage Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'garage', why = 'Exact match, under the Punk genre.' },
    } },
    { key = 'dance_punk', label = 'Dance-Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'dance_punk', why = 'Exact match, under the Punk genre.' },
    } },
    { key = 'post_punk', label = 'Post-Punk', family = 'punk', candidates = {
        { genre = 'new_wave', subgenre = 'new_wave', why = 'The supported genre closest to the late 70s and early 80s post-punk wave.' },
        { genre = 'indie_rock', subgenre = 'noise', why = 'The documentation calls Noise an off-shoot of post-punk.' },
        { genre = 'alternative', subgenre = 'alternative', why = 'Use this for modern post-punk revival bands.' },
    } },
    { key = 'horror_punk', label = 'Horror Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'classic', why = 'Classic punk form with horror imagery.' },
        { genre = 'glam', subgenre = 'goth', why = 'Use this when the goth presentation leads.' },
    } },
    { key = 'celtic_punk', label = 'Celtic Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'alternative', why = 'Where Flogging Molly and Flatfoot 56 are filed.' },
    } },
    { key = 'folk_punk', label = 'Folk Punk', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'alternative', why = 'The catalogue uses the alternative punk entry for folk-inflected punk.' },
    } },
    { key = 'ska_punk', label = 'Ska Punk', family = 'punk', candidates = {
        { genre = 'reggae_ska', subgenre = 'ska', why = 'The documentation names Reel Big Fish and Less Than Jake under Ska.' },
        { genre = 'punk', subgenre = 'alternative', why = 'Use this when the punk outweighs the horns.' },
    } },
    { key = 'riot_grrrl', label = 'Riot Grrrl', family = 'punk', candidates = {
        { genre = 'punk', subgenre = 'alternative', why = 'The closest supported bucket for the 90s punk underground.' },
        { genre = 'alternative', subgenre = 'alternative', why = 'Use this for the more indie-leaning end.' },
    } },

    ----------------------------------------------------------------
    -- Pop and New Wave
    ----------------------------------------------------------------
    { key = 'pop', label = 'Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'The documentation names Lady Gaga and Madonna here.' },
    } },
    { key = 'power_pop', label = 'Power Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'Hook-led rock with pop structure.' },
        { genre = 'punk', subgenre = 'pop_punk', why = 'Use this when the tempo and edge lean punk.' },
    } },
    { key = 'teen_pop', label = 'Teen Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'teen_rock', why = 'The closest supported category. It is named Teen Rock, so expect a band sound rather than produced pop.' },
        { genre = 'pop_rock', subgenre = 'pop', why = 'Use plain Pop when it is not aimed at a teen market specifically.' },
    } },
    { key = 'soft_rock', label = 'Soft Rock', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'soft_rock', why = 'Exact match, under the Pop-Rock genre.' },
    } },
    { key = 'adult_contemporary', label = 'Adult Contemporary', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'contemporary', why = 'The supported category intended to cover this area: polished, adult-facing pop rock.' },
    } },
    { key = 'singer_songwriter', label = 'Singer-Songwriter', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'contemporary_folk', why = 'The supported home for acoustic, lyric-led solo writing.' },
        { genre = 'pop_rock', subgenre = 'contemporary', why = 'Use this when the production is full-band and radio-facing.' },
    } },
    { key = 'bubblegum_pop', label = 'Bubblegum Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'Straightforward pop with no dedicated category.' },
    } },
    { key = 'baroque_pop', label = 'Baroque Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'Pop songwriting with orchestral arrangement.' },
        { genre = 'indie_rock', subgenre = 'indie_rock', why = 'Use this for the modern indie end of it.' },
    } },
    { key = 'indie_pop', label = 'Indie Pop', family = 'pop', candidates = {
        { genre = 'indie_rock', subgenre = 'indie_rock', why = 'The supported indie bucket covers pop-leaning indie too.' },
        { genre = 'pop_rock', subgenre = 'pop', why = 'Use this when the production is polished rather than homemade.' },
    } },
    { key = 'electropop', label = 'Electropop', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'synthpop', why = 'Pop songs built on synths, which is what the supported Synthpop entry describes.' },
        { genre = 'pop_rock', subgenre = 'pop', why = 'Use this when it reads as mainstream pop that happens to be produced electronically.' },
    } },
    { key = 'dance_pop', label = 'Dance-Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'Pop first. The documentation files Lady Gaga and Madonna here, which is this exactly.' },
        { genre = 'pop_dance_electronic', subgenre = 'dance', why = 'Use this when the track is built for the floor rather than for the radio.' },
    } },
    { key = 'art_pop', label = 'Art Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'Pop songwriting is still the frame, however unusual the arrangement.' },
        { genre = 'indie_rock', subgenre = 'indie_rock', why = 'Use this for the independent, left-field end.' },
        { genre = 'other', subgenre = 'experimental', why = 'Only when the song abandons pop structure altogether.' },
    } },
    { key = 'k_pop', label = 'K-Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'File by sound. There is no supported category for national origin except J-Rock.' },
    } },
    { key = 'j_pop', label = 'J-Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'pop', why = 'File by sound rather than origin.' },
        { genre = 'j_rock', subgenre = 'j_rock', why = 'Use J-Rock if the song is guitar-led enough to read as rock.' },
    } },
    { key = 'city_pop', label = 'City Pop', family = 'pop', candidates = {
        { genre = 'pop_rock', subgenre = 'soft_rock', why = 'Smooth, session-played pop rock is the closest supported sound.' },
        { genre = 'rnb_soul_funk', subgenre = 'funk', why = 'Use this when the groove and horns lead.' },
    } },
    { key = 'new_wave', label = 'New Wave', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'new_wave', why = 'Its own major genre with a detailed description in the documentation.' },
    } },
    { key = 'synthpop', label = 'Synthpop', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'synthpop', why = 'Exact match. Where the catalogue files Freezepop and Plushgun.' },
    } },
    { key = 'electroclash', label = 'Electroclash', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'electroclash', why = 'Exact match, under the New Wave genre.' },
    } },
    { key = 'darkwave', label = 'Dark Wave', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'dark_wave', why = 'Exact match. The documentation calls it the modern expansion of gothic rock.' },
    } },
    { key = 'new_romantic', label = 'New Romantic', family = 'pop', candidates = {
        { genre = 'new_wave', subgenre = 'new_wave', why = 'A new wave movement with no separate category.' },
        { genre = 'new_wave', subgenre = 'synthpop', why = 'Use this when synths and sequencing carry the song.' },
    } },
    { key = 'oldies', label = 'Oldies', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'oldies', why = 'Exact match on the supported category.' },
        { genre = 'rock', subgenre = 'rock_and_roll', why = 'Prefer this when the song is specifically 50s rock and roll.' },
    } },
    { key = 'doo_wop', label = 'Doo-Wop', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'oldies', why = 'The supported home for pre-rock vocal pop.' },
        { genre = 'rnb_soul_funk', subgenre = 'rhythm_and_blues', why = 'Use this when the group is filed as an R&B act.' },
    } },
    { key = 'a_cappella', label = 'A Cappella', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'a_capella', why = 'Exact match. Note the supported list spells it "A Capella".' },
    } },
    { key = 'novelty', label = 'Novelty', family = 'pop', candidates = {
        { genre = 'novelty', subgenre = 'novelty', why = 'Its own major genre. The documentation names Weird Al.' },
    } },
    { key = 'parody', label = 'Parody', family = 'pop', candidates = {
        { genre = 'novelty', subgenre = 'novelty', why = 'The documentation names parody covers specifically.' },
    } },
    { key = 'comedy', label = 'Comedy', family = 'pop', candidates = {
        { genre = 'novelty', subgenre = 'novelty', why = 'The documentation defines Novelty as songs made primarily to be funny.' },
    } },
    { key = 'holiday', label = 'Holiday / Christmas', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'other', why = 'Holiday music is an occasion, not a sound. File by the arrangement if you can.' },
        { genre = 'novelty', subgenre = 'novelty', why = 'Use this only when the song is comedic.' },
    } },
    { key = 'musical_theatre', label = 'Musical Theatre', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'other', why = 'No show-tune category exists.' },
    } },
    { key = 'video_game_music', label = 'Video Game Music', family = 'pop', candidates = {
        { genre = 'other', subgenre = 'other', why = 'A source, not a style. File by the arrangement where you can.' },
        { genre = 'pop_dance_electronic', subgenre = 'chiptune', why = 'Use this when the sound is genuinely chip-based.' },
    } },

    ----------------------------------------------------------------
    -- Electronic
    ----------------------------------------------------------------
    { key = 'electronica', label = 'Electronica', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'electronica', why = 'The general supported bucket for electronic music.' },
    } },
    { key = 'house', label = 'House', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'house', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'techno', label = 'Techno', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'techno', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'trance', label = 'Trance', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'trance', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'dance', label = 'Dance', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'dance', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'eurodance', label = 'Eurodance', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'dance', why = 'The supported dance entry is the closest fit.' },
    } },
    { key = 'drum_and_bass', label = 'Drum and Bass', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'drum_and_bass', why = 'Exact match. The documentation names Goldie and Squarepusher.' },
    } },
    { key = 'jungle', label = 'Jungle', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'drum_and_bass', why = 'The style drum and bass grew out of, and the supported entry that covers it.' },
        { genre = 'pop_dance_electronic', subgenre = 'breakbeat', why = 'Use this for the earlier, breakbeat-led form.' },
    } },
    { key = 'breakbeat', label = 'Breakbeat', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'breakbeat', why = 'Exact match. The documentation names The Prodigy.' },
    } },
    { key = 'big_beat', label = 'Big Beat', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'breakbeat', why = 'The documentation files The Prodigy under Breakbeat, which is this sound.' },
    } },
    { key = 'dubstep', label = 'Dubstep', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'electronica', why = 'No dubstep category exists; the general electronic entry is the fallback.' },
        { genre = 'pop_dance_electronic', subgenre = 'hardcore_dance', why = 'Use this for the aggressive, high-energy end.' },
    } },
    { key = 'uk_garage', label = 'UK Garage / 2-Step', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'garage', why = 'The electronic Garage entry, not the rock one. Both names exist in the supported list.' },
    } },
    { key = 'glitch', label = 'Glitch', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'electronica', why = 'The general electronic entry; no glitch category exists.' },
        { genre = 'other', subgenre = 'experimental', why = 'Use this when the artefacts are the piece rather than an effect applied to it.' },
    } },
    { key = 'ambient', label = 'Ambient', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'ambient', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'downtempo', label = 'Downtempo', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'downtempo', why = 'Exact match, under the Pop/Dance/Electronic genre.' },
    } },
    { key = 'idm', label = 'IDM', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'electronica', why = 'The general electronic entry; no IDM category exists.' },
        { genre = 'other', subgenre = 'experimental', why = 'Use this for the most abstract end.' },
    } },
    { key = 'chiptune', label = 'Chiptune', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'chiptune', why = 'Exact match, and well attested in the catalogue.' },
    } },
    { key = 'synthwave', label = 'Synthwave', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'electronica', why = 'The general electronic bucket; the style postdates the supported list.' },
        { genre = 'new_wave', subgenre = 'synthpop', why = 'Use this when it is written as songs with vocals rather than as instrumentals.' },
    } },
    { key = 'vaporwave', label = 'Vaporwave', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'downtempo', why = 'Slow, sample-led and atmospheric.' },
        { genre = 'other', subgenre = 'experimental', why = 'Use this when the piece is a collage rather than a track.' },
    } },
    { key = 'hardcore_techno', label = 'Hardcore Techno', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'hardcore_dance', why = 'The closest supported category, covering the hard, high-BPM end of dance music.' },
    } },
    { key = 'gabber', label = 'Gabber', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'hardcore_dance', why = 'The supported hardcore dance entry covers it.' },
    } },
    { key = 'industrial', label = 'Industrial', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'industrial', why = 'The electronic-side industrial entry, for the non-metal form.' },
        { genre = 'metal', subgenre = 'industrial', why = 'Use the metal side when guitars carry the riffs.' },
    } },
    { key = 'ebm', label = 'EBM', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'industrial', why = 'The supported home for body music and its industrial relatives.' },
    } },
    { key = 'futurepop', label = 'Futurepop', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'industrial', why = 'Where the catalogue files Aesthetic Perfection.' },
        { genre = 'new_wave', subgenre = 'synthpop', why = 'Use this when the melodies are pop-forward.' },
    } },
    { key = 'electronicore', label = 'Electronicore', family = 'electronic', candidates = {
        { genre = 'metal', subgenre = 'metalcore', why = 'Where Attack Attack! is filed. The -core side wins over the synths.' },
    } },
    { key = 'trip_hop', label = 'Trip-Hop', family = 'electronic', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'trip_hop', why = 'Exact match, filed under Hip-Hop/Rap rather than under electronic.' },
        { genre = 'pop_dance_electronic', subgenre = 'downtempo', why = 'Use this when there are no hip-hop elements at all.' },
    } },
    { key = 'garage_electronic', label = 'Garage (electronic)', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'garage', why = 'The electronic Garage entry, not the rock one. Both names exist in the list.' },
    } },
    { key = 'dub', label = 'Dub', family = 'electronic', candidates = {
        { genre = 'pop_dance_electronic', subgenre = 'dub', why = 'The supported Dub entry sits under the electronic genre.' },
        { genre = 'reggae_ska', subgenre = 'reggae', why = 'Use Reggae for a conventional song with vocals, where the dub effects are incidental. Dub proper is a production-led instrumental remix.' },
    } },

    ----------------------------------------------------------------
    -- Hip-Hop and Rap
    ----------------------------------------------------------------
    { key = 'hip_hop', label = 'Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'hip_hop', why = 'Exact match, under the Hip-Hop/Rap genre.' },
    } },
    { key = 'rap', label = 'Rap', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'rap', why = 'Exact match, under the Hip-Hop/Rap genre.' },
    } },
    { key = 'old_school_hip_hop', label = 'Old School Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'old_school_hip_hop', why = 'Exact match, under the Hip-Hop/Rap genre.' },
    } },
    { key = 'boom_bap', label = 'Boom Bap', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'old_school_hip_hop', why = 'Sampled breaks and hard drums, which is the era the supported Old School entry describes.' },
        { genre = 'hip_hop_rap', subgenre = 'hip_hop', why = 'Use the general entry for a modern boom bap revival record.' },
    } },
    { key = 'trap', label = 'Trap', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'hip_hop', why = 'The general supported entry. Trap postdates this list, so it has no category of its own.' },
        { genre = 'hip_hop_rap', subgenre = 'gangsta', why = 'Use this when the subject matter and delivery follow the gangsta tradition.' },
    } },
    { key = 'drill', label = 'Drill', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'hardcore_rap', why = 'The closest supported category for its aggression and subject matter.' },
        { genre = 'hip_hop_rap', subgenre = 'gangsta', why = 'Use this when it sits squarely in the gangsta lineage.' },
    } },
    { key = 'jazz_rap', label = 'Jazz Rap', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'alternative_rap', why = 'Jazz-sampling hip-hop is the archetype of what Alternative Rap covers.' },
    } },
    { key = 'lofi_hiphop', label = 'Lo-fi Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'trip_hop', why = 'Downtempo, sample-led and usually instrumental, which is what Trip Hop describes.' },
        { genre = 'pop_dance_electronic', subgenre = 'downtempo', why = 'Use this when there is no hip-hop vocal or sampling element at all.' },
    } },
    { key = 'gangsta_rap', label = 'Gangsta Rap', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'gangsta', why = 'Exact match, under the Hip-Hop/Rap genre.' },
    } },
    { key = 'hardcore_hip_hop', label = 'Hardcore Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'hardcore_rap', why = 'The closest supported category. It is named Hardcore Rap, but covers the same ground.' },
    } },
    { key = 'alternative_hip_hop', label = 'Alternative Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'alternative_rap', why = 'The closest supported category. It is named Alternative Rap, but covers the same ground.' },
    } },
    { key = 'underground_hip_hop', label = 'Underground Hip-Hop', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'underground_rap', why = 'The closest supported category. It is named Underground Rap, but covers the same ground.' },
    } },
    { key = 'rap_rock', label = 'Rap Rock', family = 'hiphop', candidates = {
        { genre = 'nu_metal', subgenre = 'nu_metal', why = 'The documentation describes exactly this crossover under Nu-Metal.' },
        { genre = 'metal', subgenre = 'alternative', why = 'Use this when it is closer to alt-metal than to nu-metal.' },
    } },
    { key = 'nerdcore', label = 'Nerdcore', family = 'hiphop', candidates = {
        { genre = 'hip_hop_rap', subgenre = 'alternative_rap', why = 'Hip-hop first; the subject matter does not change the form.' },
        { genre = 'novelty', subgenre = 'novelty', why = 'Use this when the song is written to be funny above all.' },
    } },

    ----------------------------------------------------------------
    -- R&B, Soul and Funk
    ----------------------------------------------------------------
    { key = 'rnb', label = 'R&B', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'rhythm_and_blues', why = 'Exact match, under the R&B/Soul/Funk genre.' },
    } },
    { key = 'contemporary_rnb', label = 'Contemporary R&B', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'rhythm_and_blues', why = 'The supported R&B entry covers the modern form too.' },
    } },
    { key = 'soul', label = 'Soul', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'soul', why = 'Exact match, under the R&B/Soul/Funk genre.' },
    } },
    { key = 'neo_soul', label = 'Neo-Soul', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'soul', why = 'The supported Soul entry is the closest fit.' },
    } },
    { key = 'alternative_rnb', label = 'Alternative R&B', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'rhythm_and_blues', why = 'R&B first; the atmospheric production does not move it to another genre.' },
        { genre = 'rnb_soul_funk', subgenre = 'soul', why = 'Use this when the vocal performance is the centre of the song.' },
    } },
    { key = 'motown', label = 'Motown', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'motown', why = 'Exact match, under the R&B/Soul/Funk genre.' },
    } },
    { key = 'funk', label = 'Funk', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'funk', why = 'Exact match, under the R&B/Soul/Funk genre.' },
    } },
    { key = 'disco', label = 'Disco', family = 'rnb', candidates = {
        { genre = 'rnb_soul_funk', subgenre = 'disco', why = 'Exact match, under the R&B/Soul/Funk genre.' },
    } },
    { key = 'gospel', label = 'Gospel', family = 'rnb', candidates = {
        { genre = 'inspirational', subgenre = 'inspirational', why = 'The supported genre defined by devotional content.' },
        { genre = 'rnb_soul_funk', subgenre = 'soul', why = 'Use this when the arrangement is soul first.' },
    } },

    ----------------------------------------------------------------
    -- Country and Folk
    ----------------------------------------------------------------
    { key = 'country', label = 'Country', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'contemporary', why = 'The default for modern country.' },
        { genre = 'country', subgenre = 'traditional_folk', why = 'Use this for older, string-band styled country.' },
    } },
    { key = 'classic_country', label = 'Classic Country', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'traditional_folk', why = 'The supported home for pre-Nashville-pop country.' },
        { genre = 'country', subgenre = 'honky_tonk', why = 'Prefer this for barroom country specifically.' },
    } },
    { key = 'honky_tonk', label = 'Honky Tonk', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'honky_tonk', why = 'Exact match, under the Country genre.' },
    } },
    { key = 'outlaw_country', label = 'Outlaw Country', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'outlaw', why = 'Exact match, under the Country genre.' },
    } },
    { key = 'alt_country', label = 'Alt-Country', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'alternative', why = 'Exact match, and well attested in the catalogue.' },
    } },
    { key = 'americana', label = 'Americana', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'alternative', why = 'The supported bucket closest to roots-leaning modern country.' },
        { genre = 'other', subgenre = 'contemporary_folk', why = 'Use this when it is folk rather than country.' },
    } },
    { key = 'country_rock', label = 'Country Rock', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'alternative', why = 'Use this when country leads.' },
        { genre = 'rock', subgenre = 'folk', why = 'Use this when the band reads as a rock band.' },
        { genre = 'southern_rock', subgenre = 'southern_rock', why = 'Prefer Southern Rock for the twin-guitar southern sound.' },
    } },
    { key = 'bluegrass', label = 'Bluegrass', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'bluegrass', why = 'Exact match, under the Country genre.' },
    } },
    { key = 'folk', label = 'Folk', family = 'country_folk', candidates = {
        { genre = 'other', subgenre = 'contemporary_folk', why = 'The supported folk entry sits under Other, not under Country.' },
        { genre = 'country', subgenre = 'traditional_folk', why = 'Use the Country one for traditional string-band folk.' },
    } },
    { key = 'contemporary_folk', label = 'Contemporary Folk', family = 'country_folk', candidates = {
        { genre = 'other', subgenre = 'contemporary_folk', why = 'Exact match, under the Other genre.' },
    } },
    { key = 'traditional_folk', label = 'Traditional Folk', family = 'country_folk', candidates = {
        { genre = 'country', subgenre = 'traditional_folk', why = 'Exact match, filed under Country.' },
    } },
    { key = 'celtic', label = 'Celtic / Irish', family = 'country_folk', candidates = {
        { genre = 'world', subgenre = 'world', why = 'The supported home for regional traditional music.' },
        { genre = 'other', subgenre = 'contemporary_folk', why = 'Use this for modern singer-led Celtic folk.' },
    } },
    { key = 'acoustic', label = 'Acoustic', family = 'country_folk', candidates = {
        { genre = 'other', subgenre = 'acoustic', why = 'Exact match. An instrumentation, so prefer a real genre if one fits.' },
        { genre = 'blues', subgenre = 'acoustic', why = 'Use the Blues one when the material is blues.' },
    } },

    ----------------------------------------------------------------
    -- Jazz and Blues
    ----------------------------------------------------------------
    -- The supported Jazz subgenres are Acid Jazz, Contemporary, Experimental, Ragtime,
    -- Smooth Jazz and Other. Contemporary means modern jazz, so it is NOT a general
    -- bucket; anything historic belongs under Other rather than being back-dated into it.
    { key = 'jazz', label = 'Jazz', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'contemporary', why = 'Right for modern jazz, which is what Contemporary means here.' },
        { genre = 'jazz', subgenre = 'other', why = 'Use this for jazz from an earlier era, which Contemporary would misdate.' },
    } },
    { key = 'big_band', label = 'Big Band / Swing', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'other', why = 'There is no swing-era category, and Contemporary means modern jazz, so Other is the honest fit.' },
        { genre = 'jazz', subgenre = 'contemporary', why = 'Only for a present-day big band, or if you would rather not use an Other category.' },
    } },
    { key = 'bebop', label = 'Bebop', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'other', why = 'No bebop category exists, and it predates what Contemporary describes.' },
        { genre = 'jazz', subgenre = 'experimental', why = 'Use this for the outward-bound post-bop end.' },
    } },
    { key = 'smooth_jazz', label = 'Smooth Jazz', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'smooth_jazz', why = 'Exact match, under the Jazz genre.' },
    } },
    { key = 'acid_jazz', label = 'Acid Jazz', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'acid_jazz', why = 'Exact match, under the Jazz genre.' },
    } },
    { key = 'ragtime', label = 'Ragtime', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'ragtime', why = 'Exact match, under the Jazz genre.' },
    } },
    { key = 'free_jazz', label = 'Free / Experimental Jazz', family = 'jazz_blues', candidates = {
        { genre = 'jazz', subgenre = 'experimental', why = 'Exact for experimental jazz, and the closest supported category for free jazz, which has none of its own.' },
    } },
    { key = 'jazz_fusion', label = 'Jazz Fusion', family = 'jazz_blues', candidates = {
        { genre = 'fusion', subgenre = 'fusion', why = 'Its own major genre, kept separate from Jazz on purpose.' },
    } },
    { key = 'blues', label = 'Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'classic', why = 'The general supported blues entry.' },
    } },
    { key = 'delta_blues', label = 'Delta Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'delta', why = 'Exact match, under the Blues genre.' },
    } },
    { key = 'chicago_blues', label = 'Chicago Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'chicago', why = 'Exact match, under the Blues genre.' },
    } },
    { key = 'electric_blues', label = 'Electric Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'electric', why = 'Exact match, and the best attested blues subgenre in the catalogue.' },
    } },
    { key = 'acoustic_blues', label = 'Acoustic Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'acoustic', why = 'Exact match, under the Blues genre.' },
    } },
    { key = 'country_blues', label = 'Country Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'country', why = 'Exact match. This is Blues / Country, not the Country genre.' },
    } },
    { key = 'contemporary_blues', label = 'Contemporary Blues', family = 'jazz_blues', candidates = {
        { genre = 'blues', subgenre = 'contemporary', why = 'Exact match, under the Blues genre.' },
    } },

    ----------------------------------------------------------------
    -- World, Classical and Other
    ----------------------------------------------------------------
    { key = 'world', label = 'World', family = 'world_other', candidates = {
        { genre = 'world', subgenre = 'world', why = 'Its own major genre, for music outside the western pop tradition.' },
    } },
    { key = 'latin', label = 'Latin', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'Its own major genre.' },
    } },
    { key = 'salsa', label = 'Salsa', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
    } },
    { key = 'samba', label = 'Samba', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
    } },
    { key = 'bossa_nova', label = 'Bossa Nova', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'Brazilian in origin, so the Latin genre fits.' },
        { genre = 'jazz', subgenre = 'contemporary', why = 'Use Jazz when the performance is a jazz reading of the form.' },
    } },
    -- Cumbia, Bachata, Merengue and Mariachi all resolve to Latin / Latin, exactly like
    -- the Salsa and Samba entries above. That is deliberate: this list exists so an
    -- author can FIND their genre, and an entry whose answer matches its neighbour's is
    -- still far better than no entry and a blank result.
    { key = 'cumbia', label = 'Cumbia', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
    } },
    { key = 'bachata', label = 'Bachata', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
    } },
    { key = 'merengue', label = 'Merengue', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
    } },
    { key = 'mariachi', label = 'Mariachi', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'The Latin genre has a single subgenre covering all of it.' },
        { genre = 'world', subgenre = 'world', why = 'Use World when the recording is presented as a traditional performance.' },
    } },
    { key = 'reggaeton', label = 'Reggaeton', family = 'world_other', candidates = {
        { genre = 'latin', subgenre = 'latin', why = 'Latin is the supported catch-all for Caribbean and Latin American popular styles.' },
        { genre = 'hip_hop_rap', subgenre = 'hip_hop', why = 'Use this when the track is built around rapping and reads as hip-hop first.' },
    } },
    { key = 'flamenco', label = 'Flamenco', family = 'world_other', candidates = {
        { genre = 'world', subgenre = 'world', why = 'Traditional flamenco is a regional folk tradition, which is what World covers.' },
        { genre = 'latin', subgenre = 'latin', why = 'A compatibility choice for modern flamenco fusion sitting closer to Latin pop.' },
    } },
    { key = 'afrobeat', label = 'Afrobeat', family = 'world_other', candidates = {
        { genre = 'world', subgenre = 'world', why = 'The supported home for African popular music.' },
        { genre = 'rnb_soul_funk', subgenre = 'funk', why = 'Use this when the groove is the point and the horns lead.' },
    } },
    { key = 'klezmer', label = 'Klezmer', family = 'world_other', candidates = {
        { genre = 'world', subgenre = 'world', why = 'Regional traditional music with no category of its own.' },
    } },
    { key = 'reggae', label = 'Reggae', family = 'world_other', candidates = {
        { genre = 'reggae_ska', subgenre = 'reggae', why = 'Exact match. The documentation names Bob Marley.' },
    } },
    { key = 'dancehall', label = 'Dancehall', family = 'world_other', candidates = {
        { genre = 'reggae_ska', subgenre = 'reggae', why = 'The supported Reggae entry is the closest fit.' },
    } },
    { key = 'ska', label = 'Ska', family = 'world_other', candidates = {
        { genre = 'reggae_ska', subgenre = 'ska', why = 'Exact match, under the Reggae/Ska genre.' },
    } },
    { key = 'classical', label = 'Classical', family = 'world_other', candidates = {
        { genre = 'classical', subgenre = 'classical', why = 'Its own major genre. The documentation names Bach and Mozart.' },
    } },
    { key = 'opera', label = 'Opera', family = 'world_other', candidates = {
        { genre = 'classical', subgenre = 'classical', why = 'The Classical genre has a single subgenre covering all of it.' },
    } },
    { key = 'baroque', label = 'Baroque', family = 'world_other', candidates = {
        { genre = 'classical', subgenre = 'classical', why = 'The Classical genre has a single subgenre covering all of it.' },
    } },
    { key = 'film_score', label = 'Film / Orchestral Score', family = 'world_other', candidates = {
        { genre = 'classical', subgenre = 'classical', why = 'The documentation describes Classical as orchestral writing in the old style.' },
        { genre = 'other', subgenre = 'other', why = 'Use this when the score is electronic or otherwise not orchestral.' },
    } },
    { key = 'inspirational', label = 'Inspirational / Worship', family = 'world_other', candidates = {
        { genre = 'inspirational', subgenre = 'inspirational', why = 'Its own major genre, defined by lyrical content.' },
    } },
    { key = 'experimental', label = 'Experimental', family = 'world_other', candidates = {
        { genre = 'other', subgenre = 'experimental', why = 'Exact match. Use it when no conventional genre applies.' },
    } },
    { key = 'spoken_word', label = 'Spoken Word', family = 'world_other', candidates = {
        { genre = 'other', subgenre = 'other', why = 'No spoken-word category exists.' },
        { genre = 'other', subgenre = 'experimental', why = 'Use this when it is presented as an art piece.' },
    } },
    { key = 'soundtrack_other', label = 'Other / Unclassifiable', family = 'world_other', candidates = {
        { genre = 'other', subgenre = 'other', why = 'The final fallback when nothing else in the list is closer.' },
    } },
}
