-- Rock Band supported genre vocabulary.
--
-- Transcribed from _external_docs/Subgenre Descriptions - RBN_C3 Documentation.htm
-- (ground truth). dev/tests/metadata_genres.lua re-verifies the counts and shape.
--
-- 29 major genres, 126 subgenres. NOTE: that page's own intro prose says
-- "120 subgenre groupings, under 21 major genres" while the page itself enumerates
-- 29 and 126. The enumeration is correct - it was checked against the tool that does
-- the final selection - so do not "correct" these counts back to the prose.
--
-- The page carries two caveats worth repeating: the list is author-maintained and is
-- guidance rather than strict rules, and subgenres are not shown in-game (they feed
-- LeFluffie visualiser cards), so the major genre is the choice that matters.
--
-- blurb / elements / artists / albums are all OPTIONAL and mostly absent: of the 126
-- subgenres the page describes only about 25. Anything reading this table must render
-- correctly when a subgenre carries nothing but a label.
--
-- No .dta tokens here on purpose. Token spellings drift between game eras (RB1/RB2
-- 'urban' became RB3 'hiphoprap'; subgenre tokens are scoped to their parent, so
-- subgenre_pop means Pop-Punk under punk and Pop under poprock), and the packaging
-- tool that writes songs.dta has its own picker. This table is display names only.
--
-- Pure data. No r / ctx / S / TIPS dependencies - the test runner dofiles it directly.

RB3_GENRE_ORDER = {
    'alternative',
    'blues',
    'classical',
    'classic_rock',
    'country',
    'emo',
    'fusion',
    'glam',
    'grunge',
    'hip_hop_rap',
    'indie_rock',
    'inspirational',
    'jazz',
    'j_rock',
    'latin',
    'metal',
    'new_wave',
    'novelty',
    'nu_metal',
    'pop_dance_electronic',
    'pop_rock',
    'prog',
    'punk',
    'rnb_soul_funk',
    'reggae_ska',
    'rock',
    'southern_rock',
    'world',
    'other',
}

RB3_GENRES = {
    ['alternative'] = {
        label = 'Alternative',
        subgenres = {
            { key = 'alternative', label = 'Alternative' },
            { key = 'college', label = 'College',
              blurb = 'melodic, punky',
              elements = 'melodic pop sound, jangling guitars, post-punk/new wave experimentation',
              artists = 'R.E.M. (early), Billy Bragg',
              albums = 'Document, Talking with the Taxman About Poetry',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['blues'] = {
        label = 'Blues',
        subgenres = {
            { key = 'acoustic', label = 'Acoustic' },
            { key = 'chicago', label = 'Chicago' },
            { key = 'classic', label = 'Classic' },
            { key = 'contemporary', label = 'Contemporary' },
            { key = 'country', label = 'Country' },
            { key = 'delta', label = 'Delta' },
            { key = 'electric', label = 'Electric' },
            { key = 'other', label = 'Other' },
        },
    },
    ['classical'] = {
        label = 'Classical',
        subgenres = {
            { key = 'classical', label = 'Classical',
              elements = 'Any Western music created in the "old style" of pre-popular music (pre blues, jazz, rock, etc), Often utilizing orchestras or choirs',
              artists = 'JS Bach, Beethoven, Mozart, etc',
            },
        },
    },
    ['classic_rock'] = {
        label = 'Classic Rock',
        subgenres = {
            { key = 'classic_rock', label = 'Classic Rock' },
        },
    },
    ['country'] = {
        label = 'Country',
        subgenres = {
            { key = 'alternative', label = 'Alternative' },
            { key = 'bluegrass', label = 'Bluegrass' },
            { key = 'contemporary', label = 'Contemporary' },
            { key = 'honky_tonk', label = 'Honky Tonk' },
            { key = 'outlaw', label = 'Outlaw' },
            { key = 'traditional_folk', label = 'Traditional Folk' },
            { key = 'other', label = 'Other' },
        },
    },
    ['emo'] = {
        label = 'Emo',
        subgenres = {
            { key = 'emo', label = 'Emo' },
        },
    },
    ['fusion'] = {
        label = 'Fusion',
        subgenres = {
            { key = 'fusion', label = 'Fusion' },
        },
    },
    ['glam'] = {
        label = 'Glam',
        subgenres = {
            { key = 'glam', label = 'Glam' },
            { key = 'goth', label = 'Goth' },
            { key = 'other', label = 'Other' },
        },
    },
    ['grunge'] = {
        label = 'Grunge',
        subgenres = {
            { key = 'grunge', label = 'Grunge',
              blurb = 'dirty, distorted, aggressive',
              elements = 'distorted guitars, contrasting dynamics',
              artists = 'Nirvana, Pearl Jam',
              albums = 'Nevermind, Ten',
            },
        },
    },
    ['hip_hop_rap'] = {
        label = 'Hip-Hop/Rap',
        subgenres = {
            { key = 'alternative_rap', label = 'Alternative Rap' },
            { key = 'gangsta', label = 'Gangsta' },
            { key = 'hardcore_rap', label = 'Hardcore Rap' },
            { key = 'hip_hop', label = 'Hip Hop' },
            { key = 'old_school_hip_hop', label = 'Old School Hip Hop' },
            { key = 'rap', label = 'Rap' },
            { key = 'trip_hop', label = 'Trip Hop' },
            { key = 'underground_rap', label = 'Underground Rap' },
            { key = 'other', label = 'Other' },
        },
    },
    ['indie_rock'] = {
        label = 'Indie Rock',
        subgenres = {
            { key = 'indie_rock', label = 'Indie Rock',
              blurb = 'unpolished, unconventional',
              elements = 'lack of professional production, non-mainstream song elements',
              artists = 'Death Cab for Cutie, Guided by Voices',
              albums = 'The Moon and Antarctica, Bee Thousand',
            },
            { key = 'lo_fi', label = 'Lo-fi',
              blurb = 'minimal, unpolished',
              elements = 'clear evidence of home production, unusual mixing characteristics',
              artists = 'Say Hi, Cat Power',
            },
            { key = 'math_rock', label = 'Math Rock',
              elements = 'typical "indie" sound qualities, written with incredibly complex time signatures, chords and melodies',
              artists = 'American Football, Don Caballero, Minus the Bear',
            },
            { key = 'noise', label = 'Noise',
              elements = 'Off-shoot of Post-Punk, High amounts of effects, strong levels of dissonance, complex song structures',
              artists = 'Sonic Youth, The Jesus Lizard',
            },
            { key = 'post_rock', label = 'Post-Rock',
              elements = '"Rock" instruments used in unconventional ways musically, often instrumental, unusual song structures (lack of clear verse/chorus), spacey/atmospheric mixing and production',
              artists = 'Godspeed You! Black Emperor, Mogwai, Sigur Ros',
            },
            { key = 'shoegazing', label = 'Shoegazing',
              blurb = 'spacy, layered',
              elements = 'distorted/sustained guitar work, vocals \'as an instrument\', focus on texture over riff',
              artists = 'My Bloody Valentine, Lush',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['inspirational'] = {
        label = 'Inspirational',
        subgenres = {
            { key = 'inspirational', label = 'Inspirational' },
        },
    },
    ['jazz'] = {
        label = 'Jazz',
        subgenres = {
            { key = 'acid_jazz', label = 'Acid Jazz' },
            { key = 'contemporary', label = 'Contemporary' },
            { key = 'experimental', label = 'Experimental' },
            { key = 'ragtime', label = 'Ragtime' },
            { key = 'smooth_jazz', label = 'Smooth Jazz' },
            { key = 'other', label = 'Other' },
        },
    },
    ['j_rock'] = {
        label = 'J-Rock',
        subgenres = {
            { key = 'j_rock', label = 'J-Rock' },
        },
    },
    ['latin'] = {
        label = 'Latin',
        subgenres = {
            { key = 'latin', label = 'Latin' },
        },
    },
    ['metal'] = {
        label = 'Metal',
        subgenres = {
            { key = 'alternative', label = 'Alternative' },
            { key = 'black', label = 'Black',
              elements = 'lo-fi production quality, unconventional song structures, raspy vocals, prevalence of fast tremelo-picking and blast beats over more "melodic" instrumentation',
              artists = 'Emperor, Bathory, Mayhem, Darkthrone',
            },
            { key = 'metalcore', label = 'Metalcore',
              elements = 'Combination of "traditional" metal elements and hardcore punk elements, thrash riffs, hardcore breakdowns, utilizes both aggressive and clean vocals',
              artists = 'All That Remains, The Devil Wears Prada, Underoath, As I Lay Dying',
            },
            { key = 'death', label = 'Death',
              elements = 'aggressive, loud and violent extreme Metal, often using downtuned heavy guitars, extremely fast and/or complex drumming with a lot of double bass pedal involved, and guttural growling as the main source of vocals.',
              artists = 'Cannibal Corpse, Dying Fetus',
            },
            { key = 'hair', label = 'Hair',
              elements = 'highly-produced "pop metal" popular in the 80\'s, simple power chord riffs and fast, melodic soloing with standard song structures, lyrics about living the "rock star life"',
              artists = 'Poison, Motley Crue, Ratt, The Scorpions, Whitesnake, Night Ranger',
            },
            { key = 'industrial', label = 'Industrial',
              elements = 'mixes elements of Heavy and Thrash Metal with noise and electronic elements, sometimes using samples, effect heavy vocals, repetitive guitar and drums and playing with inhuman loudness as an artistic choice.',
              artists = 'Ministry, KMFDM, Nine Inch Nails, Rammstein, Marilyn Manson',
              albums = 'Psalm 69, The Downward Spiral',
            },
            { key = 'metal', label = 'Metal' },
            { key = 'power', label = 'Power',
              elements = 'High tempo, highly produced, technically complex musicianship, simple, "epic feeling" major-key melodies, highly melodic vocals',
              artists = 'Dragonforce, Nightwish, Firewind, Kamelot, Helloween',
            },
            { key = 'progressive', label = 'Progressive',
              blurb = 'genre-mixing, seeks to push boundaries of what Metal can be',
              elements = 'complex rhythm, longer length, detailed instrumentation',
              artists = 'Dream Theater, Queensryche',
            },
            { key = 'speed', label = 'Speed' },
            { key = 'thrash', label = 'Thrash',
              elements = 'fast, palm-muted guitar riffs and technically complex solos, fast, straightforward drum beats, shouted or harshly-song (but still melodic) vocals',
              artists = '"The Big 4": Metallica, Megadeth, Anthrax, Slayer. Other examples: Machinehead, Testament, Evile, Municipal Waste, Anvil',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['new_wave'] = {
        label = 'New Wave',
        subgenres = {
            { key = 'dark_wave', label = 'Dark Wave',
              blurb = 'Somber or introspective tone + sequenced synths and / or ambient processed guitars = moody textural atmosphere. Historical precursor to Gothic Rock, now the contemporary expansion of that genre.',
            },
            { key = 'electroclash', label = 'Electroclash' },
            { key = 'new_wave', label = 'New Wave',
              blurb = 'Brit: Mashed Punk & Disco ca. \'76-\'83. Amer: Rock without the "Prog", "Hard" or "Soft". Danceable, synthy songs. ca. \'81-\'88 . Resurfaced in the 21st Century.',
            },
            { key = 'synthpop', label = 'Synthpop',
              blurb = 'Friendly, rock song structures, eschews instrumental virtuosity, signature use of arpeggiated electronics, or later into the \'80s, programmed sequences.',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['novelty'] = {
        label = 'Novelty',
        subgenres = {
            { key = 'novelty', label = 'Novelty',
              elements = 'songs that are primarily made to be funny or comedic as it\'s main point. Can span any and all genres of music, and sometimes it\'s a cover version of a serious song with new lyrics to create a parody of the original.',
              artists = 'Weird Al, Parry Grip',
            },
        },
    },
    ['nu_metal'] = {
        label = 'Nu-Metal',
        subgenres = {
            { key = 'nu_metal', label = 'Nu-Metal',
              elements = 'Dark and heavy, yet relatively mainstream music. Mashes hip-hop style syncopated drum beats with down-tuned, chunky metal/industrial guitar riffs, and avoids guitar solos. Aggressive (but often still melodic) vocals and introspective, dark, often depressive/angry lyrics. Gained popularity in the late 90\'s/early 2000\'s, but has mostly died off since then.',
              artists = 'KoRn, Early Disturbed/Slipknot/Linkin Park (all three have moved away from nu metal since then), Saliva, Limp Bizkit, Godsmack',
              albums = 'Life is Peachy/Follow the Leader (KoRn), The Sickness (Disturbed), Significant Other (Limp Bizkit), Vol. 3 (The Subliminal Verses) (Slipknot)',
            },
        },
    },
    ['pop_dance_electronic'] = {
        label = 'Pop/Dance/Electronic',
        subgenres = {
            { key = 'ambient', label = 'Ambient' },
            { key = 'breakbeat', label = 'Breakbeat',
              artists = 'The Prodigy, The Crystal Method',
            },
            { key = 'chiptune', label = 'Chiptune' },
            { key = 'dance', label = 'Dance' },
            { key = 'downtempo', label = 'Downtempo' },
            { key = 'dub', label = 'Dub' },
            { key = 'drum_and_bass', label = 'Drum and Bass',
              artists = 'Goldie, Squarepusher',
            },
            { key = 'electronica', label = 'Electronica' },
            { key = 'garage', label = 'Garage' },
            { key = 'hardcore_dance', label = 'Hardcore Dance' },
            { key = 'house', label = 'House' },
            { key = 'industrial', label = 'Industrial',
              artists = 'Throbbing Gristle, God Lives Underwater',
            },
            { key = 'techno', label = 'Techno' },
            { key = 'trance', label = 'Trance' },
            { key = 'other', label = 'Other' },
        },
    },
    ['pop_rock'] = {
        label = 'Pop-Rock',
        subgenres = {
            { key = 'contemporary', label = 'Contemporary' },
            { key = 'pop', label = 'Pop',
              artists = 'Lady Gaga, Madonna',
            },
            { key = 'soft_rock', label = 'Soft Rock' },
            { key = 'teen_rock', label = 'Teen Rock' },
            { key = 'other', label = 'Other' },
        },
    },
    ['prog'] = {
        label = 'Prog',
        subgenres = {
            { key = 'prog_rock', label = 'Prog Rock',
              elements = 'melodic and epic Rock music that often focuses on strange time signatures, complex instrumental parts, avant-garde and/or complex lyrics, uncommon song structures and long running times.',
              artists = 'Rush, King Crimson, Genesis, Yes, Pink Floyd, Tool',
            },
        },
    },
    ['punk'] = {
        label = 'Punk',
        subgenres = {
            { key = 'alternative', label = 'Alternative' },
            { key = 'classic', label = 'Classic' },
            { key = 'dance_punk', label = 'Dance Punk' },
            { key = 'garage', label = 'Garage' },
            { key = 'hardcore', label = 'Hardcore' },
            { key = 'pop_punk', label = 'Pop-Punk',
              elements = 'high energy, high tempo, instrumentally simple music. Differentiated from standard punk by high production values and palatable vocal harmonies',
              artists = 'Green Day, Blink 182, Simple Plan, Sum 41, Good Charlotte',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['rnb_soul_funk'] = {
        label = 'R&B/Soul/Funk',
        subgenres = {
            { key = 'disco', label = 'Disco' },
            { key = 'funk', label = 'Funk' },
            { key = 'motown', label = 'Motown' },
            { key = 'rhythm_and_blues', label = 'Rhythm and Blues' },
            { key = 'soul', label = 'Soul' },
            { key = 'other', label = 'Other' },
        },
    },
    ['reggae_ska'] = {
        label = 'Reggae/Ska',
        subgenres = {
            { key = 'reggae', label = 'Reggae',
              artists = 'Bob Marley',
            },
            { key = 'ska', label = 'Ska',
              artists = 'Reel Big Fish, Less Than Jake',
            },
            { key = 'other', label = 'Other' },
        },
    },
    ['rock'] = {
        label = 'Rock',
        subgenres = {
            { key = 'arena', label = 'Arena' },
            { key = 'blues_rock', label = 'Blues-Rock' },
            { key = 'folk', label = 'Folk' },
            { key = 'garage', label = 'Garage' },
            { key = 'hard_rock', label = 'Hard Rock' },
            { key = 'psychedelic', label = 'Psychedelic' },
            { key = 'rock', label = 'Rock' },
            { key = 'rockabilly', label = 'Rockabilly',
              artists = 'The Reverend Horton Heat, Stray Cats',
            },
            { key = 'rock_and_roll', label = 'Rock and Roll',
              artists = 'Chuck Berry, Chubby Checker',
            },
            { key = 'surf', label = 'Surf' },
            { key = 'other', label = 'Other' },
        },
    },
    ['southern_rock'] = {
        label = 'Southern Rock',
        subgenres = {
            { key = 'southern_rock', label = 'Southern Rock' },
        },
    },
    ['world'] = {
        label = 'World',
        subgenres = {
            { key = 'world', label = 'World' },
        },
    },
    ['other'] = {
        label = 'Other',
        subgenres = {
            { key = 'a_capella', label = 'A Capella',
              elements = 'Music created using only human vocalization, and occasionally percussion',
              artists = 'The Nylons, Van Canto',
            },
            { key = 'acoustic', label = 'Acoustic' },
            { key = 'contemporary_folk', label = 'Contemporary Folk' },
            { key = 'experimental', label = 'Experimental' },
            { key = 'oldies', label = 'Oldies' },
            { key = 'other', label = 'Other' },
        },
    },
}
