-- EVENTS-track event vocabulary for the Venue > Events sub-tab.
-- Derived from the community "Text Events List - Events" reference (ground
-- truth); dev/tests/venue_events.lua re-verifies every generatable string
-- against it when a local copy is present, and skips when it is not.
-- No S/TIPS/REAPER dependencies - loadable standalone by the test runner.
--
-- Caps string per prc base: the character at position num+1 is the rule for
-- number num (0 = the bare, unnumbered form):
--   'a'..'z'  number valid, lettered variants valid up to this letter
--   '.'       number valid, but no lettered variants exist
--   absent    number invalid (caps string shorter than num+1)
-- e.g. verse = 'ffffdddddd': bare and _1.._3 letter up to f, _4.._9 up to d.
-- dj_intro is '.' because the list skips [prc_dj_intro_a] (has only _b.._d),
-- so the contiguous a->cap ladder cannot be used.
--
-- kind = 'prc'     -> [prc_<base>] with _N numbering and letter suffixes
-- kind = 'generic' -> [prc_<base>] with N appended directly (no underscore,
--                     e.g. [prc_a3]), digits 1-9, no letter variants
-- kind = 'plain'   -> literal full event strings, no variants

SECTION_EVENT_GROUPS = {
    { key = 'intro', label = 'Intro', kind = 'prc',
      tip = 'Marks stylistic intros at the very beginning of the song\n' ..
            '(instrument-specific, quiet, noise, fade-in), plus entry cues\n' ..
            'for instruments joining in.',
      bases = {
          { base = 'intro',           caps = 'e'  },
          { base = 'intro_slow',      caps = 'd.' },
          { base = 'intro_fast',      caps = 'd'  },
          { base = 'intro_heavy',     caps = 'd'  },
          { base = 'quiet_intro',     caps = 'd'  },
          { base = 'noise_intro',     caps = 'd'  },
          { base = 'intro_hook',      caps = 'd'  },
          { base = 'intro_riff',      caps = 'd'  },
          { base = 'fade_in',         caps = 'd'  },
          { base = 'drum_intro',      caps = 'd'  },
          { base = 'bass_intro',      caps = 'd'  },
          { base = 'vocal_intro',     caps = 'd'  },
          { base = 'gtr_intro',       caps = 'e'  },
          { base = 'violin_intro',    caps = 'd'  },
          { base = 'strings_intro',   caps = 'd'  },
          { base = 'orch_intro',      caps = 'd'  },
          { base = 'horn_intro',      caps = 'd'  },
          { base = 'harmonica_intro', caps = 'd'  },
          { base = 'organ_intro',     caps = 'd'  },
          { base = 'piano_intro',     caps = 'd'  },
          { base = 'keyboard_intro',  caps = 'd'  },
          { base = 'dj_intro',        caps = '.'  },
          { base = 'drums_enter',     caps = '.'  },
          { base = 'bass_enters',     caps = '.'  },
          { base = 'gtr_enters',      caps = '.'  },
          { base = 'rhy_enters',      caps = '.'  },
          { base = 'band_enters',     caps = '.'  },
      } },
    { key = 'structure', label = 'Structure', kind = 'prc',
      tip = 'Standard song structure markers: verses, choruses, bridges\n' ..
            'and their pre/post/alt variants.',
      bases = {
          { base = 'verse',            caps = 'ffffdddddd' },
          { base = 'alt_verse',        caps = 'd'          },
          { base = 'quiet_verse',      caps = 'd'          },
          { base = 'preverse',         caps = 'dddddd'     },
          { base = 'postverse',        caps = 'dddddd'     },
          { base = 'chorus',           caps = 'dddddddddd' },
          { base = 'alt_chorus',       caps = 'd'          },
          { base = 'chorus_break',     caps = 'd'          },
          { base = 'prechorus',        caps = 'dddddd'     },
          { base = 'postchorus',       caps = 'dddddd'     },
          { base = 'bridge',           caps = 'dddddddddd' },
          { base = 'breakdown_chorus', caps = 'd'          },
      } },
    { key = 'solo', label = 'Solo', kind = 'prc',
      tip = 'Marks instrumental solos.',
      bases = {
          { base = 'gtr_solo',       caps = 'snnnnnnnnn' },
          { base = 'slide_solo',     caps = 'ddddd'      },
          { base = 'drum_solo',      caps = 'ddddd'      },
          { base = 'perc_solo',      caps = 'ddddd'      },
          { base = 'bass_solo',      caps = 'ddddd'      },
          { base = 'organ_solo',     caps = 'ddddd'      },
          { base = 'piano_solo',     caps = 'ddddd'      },
          { base = 'keyboard_solo',  caps = 'ddddd'      },
          { base = 'synth_solo',     caps = 'ddddd'      },
          { base = 'harmonica_solo', caps = 'ddddd'      },
          { base = 'sax_solo',       caps = 'ddddd'      },
          { base = 'horn_solo',      caps = 'ddddd'      },
          { base = 'flute_solo',     caps = 'ddddd'      },
          { base = 'noise_solo',     caps = 'ddddd'      },
          { base = 'dj_solo',        caps = 'ddddd'      },
      } },
    { key = 'break', label = 'Break', kind = 'prc',
      tip = 'Short interruptions or simplified grooves (drum-only hits,\n' ..
            'riff breaks, pauses), plus heavier groove-focused breakdowns.',
      bases = {
          { base = 'break',          caps = 'ddddd' },
          { base = 'gtr_break',      caps = 'ddddd' },
          { base = 'bass_break',     caps = 'ddddd' },
          { base = 'drum_break',     caps = 'ddddd' },
          { base = 'organ_break',    caps = 'ddddd' },
          { base = 'synth_break',    caps = 'ddddd' },
          { base = 'piano_break',    caps = 'ddddd' },
          { base = 'keyboard_break', caps = 'ddddd' },
          { base = 'horn_break',     caps = '.'     },
          { base = 'perc_break',     caps = '.'     },
          { base = 'dj_break',       caps = '.'     },
          { base = 'breakdown',      caps = 'ddddd' },
      } },
    { key = 'energy', label = 'Tempo / Energy', kind = 'prc',
      tip = 'Marks changes in intensity, speed, or tension\n' ..
            '(slow/fast/quiet/loud/heavy parts, build-ups, speed-ups).',
      bases = {
          { base = 'slow_part',   caps = 'ddddd' },
          { base = 'fast_part',   caps = 'ddddd' },
          { base = 'quiet_part',  caps = 'ddddd' },
          { base = 'loud_part',   caps = 'ddddd' },
          { base = 'heavy_part',  caps = 'ddddd' },
          { base = 'spacey',      caps = '.'     },
          { base = 'trippy_part', caps = 'ddddd' },
          { base = 'speedup',     caps = '.'     },
          { base = 'tension',     caps = 'ddddd' },
          { base = 'build_up',    caps = 'ddddd' },
      } },
    { key = 'interlude', label = 'Interlude / Jam', kind = 'prc',
      tip = 'Non-structural musical sections, often instrumental or\n' ..
            'atmospheric (interludes, soundscapes, jams, vamps).',
      bases = {
          { base = 'interlude',  caps = 'ddddd' },
          { base = 'soundscape', caps = 'ddddd' },
          { base = 'jam',        caps = 'ddddd' },
          { base = 'space_jam',  caps = 'ddddd' },
          { base = 'vamp',       caps = 'ddddd' },
      } },
    { key = 'outro', label = 'Outro / Ending', kind = 'prc',
      tip = 'Marks the final part of the song\n' ..
            '(outros, endings, fade-outs).',
      bases = {
          { base = 'outro',        caps = 'ddddd' },
          { base = 'outro_solo',   caps = 'd'     },
          { base = 'outro_chorus', caps = 'd'     },
          { base = 'ending',       caps = 'd'     },
          { base = 'fade_out',     caps = 'd'     },
      } },
    { key = 'misc', label = 'Misc', kind = 'prc',
      tip = 'Other section types: main riff, big rock ending, melodies,\n' ..
            'intro-verse/chorus hybrids.',
      bases = {
          { base = 'main_riff',    caps = 'ffffdddddd' },
          { base = 'bre',          caps = '.'          },
          { base = 'melody',       caps = 'ddddd'      },
          { base = 'lo_melody',    caps = 'ddddd'      },
          { base = 'hi_melody',    caps = 'ddddd'      },
          { base = 'intro_verse',  caps = 'd'          },
          { base = 'intro_chorus', caps = 'd'          },
      } },
    { key = 'generic', label = 'Generic', kind = 'generic',
      tip = 'Generic lettered sections [prc_a]..[prc_k] for parts that fit\n' ..
            'no named section. Numbers 1-9 append with no underscore\n' ..
            '([prc_a3]); no letter variants exist.',
      bases = {
          { base = 'a' }, { base = 'b' }, { base = 'c' }, { base = 'd' },
          { base = 'e' }, { base = 'f' }, { base = 'g' }, { base = 'h' },
          { base = 'i' }, { base = 'j' }, { base = 'k' },
      } },
    { key = 'crowd', label = 'Crowd', kind = 'plain',
      tip = 'Controls crowd behavior and animation.',
      events = {
          '[crowd_realtime]', '[crowd_mellow]', '[crowd_normal]',
          '[crowd_intense]', '[crowd_noclap]', '[crowd_clap]',
          '[crowd_fists_on]', '[crowd_fists_off]',
          '[crowd_horns_on]', '[crowd_horns_off]',
          '[crowd_lighters_on]', '[crowd_lighters_off]',
      } },
    { key = 'global', label = 'Global', kind = 'plain',
      tip = 'High-level markers for song start/end.',
      events = { '[music_start]', '[music_end]', '[end]', '[coda]' } },
}

-- Lookup: base name -> base entry (caps access without walking the groups)
SECTION_EVENT_BASE = {}
for _, _g in ipairs(SECTION_EVENT_GROUPS) do
    if _g.bases then
        for _, _b in ipairs(_g.bases) do SECTION_EVENT_BASE[_b.base] = _b end
    end
end
