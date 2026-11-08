# Rock Band Instrument Helper — Work-in-progress tabs

← [Back to main README](README.md)

These views are enabled via **General → Settings → Show WIPs? = Yes**: the Drums and Guitar tabs appear after Keys in the tab bar, and the keys tools appear as the **WIP** sub-tab of the Keys tab. They work at a basic level but have known issues and aren't ready for general use — expect rough edges.

---

## Drums tab

<!-- TODO: screenshot of the Drums tab -->
![Drums tab](../assets/g_wip_drums.jpg)

Converts General MIDI drum notes to Rock Band 5-lane format and writes them to the target track.

### Track selection

| Dropdown           | What it expects                                          |
| ------------------ | -------------------------------------------------------- |
| **Source track**   | A MIDI track with GM drum notes (e.g. Guitar Pro export) |
| **Target track**   | The `PART DRUMS` MIDI track to write into                |

### Options

- **Ghost note threshold** — MIDI velocity at or below which a note is skipped. Raise to filter out ghost notes or light pedal hits.
- **Crash lane** — assigns crash cymbal notes to Yellow (default) or Green lane.
- **Pro Drums** — when enabled, inserts cymbal marker notes (110/111/112) alongside the gem notes, enabling Pro Drums mode in-game.

### Actions

- **Preview** — runs the conversion and displays the result mapping without writing any notes.
- **Convert drums** — writes Rock Band drum notes into the target track. Any existing drum notes in the time selection (or whole item if no selection) are cleared first. Fully undoable.

---

## Keys → WIP sub-tab

<!-- TODO: screenshot of the Keys > WIP sub-tab -->
![Keys - WIP sub-tab](../assets/g_wip_keys.jpg)

Contains four conversion tools for piano MIDI → Rock Band keys formats. Each tool has its own source and target track selectors.

### Hand Split

<!-- TODO: screenshot of Hand Split -->
![Hand Split](../assets/g_wip_keys_handsplit.jpg)

Splits a piano track into separate right-hand and left-hand MIDI tracks.

- Split by **MIDI channel** (Guitar Pro: ch1 = RH, ch2 = LH) or by **pitch threshold**.
- Set the right-hand target and left-hand target tracks independently — they can be different PART REAL_KEYS tracks.

### Convert to Pro Keys

<!-- TODO: screenshot of Convert to Pro Keys -->
![Convert to Pro Keys](../assets/g_wip_keys_prokeys.jpg)

Octave-shifts all notes into the C2–C4 range (MIDI 48–72) required for Pro Keys Expert authoring. Optionally inserts lane range shift markers where the pitch window moves.

### Pro Keys Animation

<!-- TODO: screenshot of Pro Keys Animation -->
![Pro Keys Animation](../assets/g_wip_keys_animation.jpg)

Copies notes in the C2–C4 range from a Pro Keys Expert source track to the animation target tracks. The animation tracks drive the on-screen keyboard highlight during gameplay.

### 5-Lane Keys

<!-- TODO: screenshot of 5-Lane Keys -->
![5-Lane Keys](../assets/g_wip_keys_5lane.jpg)

Maps a piano melody to Expert 5-Lane Keys gem pitches (96–100) using a sliding 5-semitone window. The window adapts measure-by-measure, so chords wider than 5 semitones are still mapped without collision. Phrase reset markers are inserted where the window resets to the lowest position.

All actions respect time selection.

---

## Guitar tab

<!-- TODO: screenshot of the Guitar tab -->
![Guitar tab](../assets/g_wip_guitar.jpg)

Converts raw guitar MIDI pitches to Rock Band Expert Guitar gem notes (pitches 96–100) and optionally validates existing notes against RBN authoring rules.

### Track selection

| Dropdown           | What it expects                                                         |
| ------------------ | ------------------------------------------------------------------------ |
| **Source track**   | A MIDI track with raw guitar pitches (e.g. Guitar Pro MIDI export)      |
| **Target track**   | The `PART GUITAR` MIDI track to write into                              |

### Conversion options

- **Wrap gap (ms)** — rest gap that resets the gem-assignment window back to Green (position 0). Shorter = more frequent resets for songs with many breaks.
- **Context window (measures)** — how many measures ahead the gem-scale planner looks. Wider = smoother transitions; narrower = adapts more quickly to large pitch jumps.
- **Max chord** — maximum simultaneous gems per chord event (2 or 3).

All three apply to this converter only. The Tab Input tab's Guitar / Bass guide used to read them too even though it doesn't offer them; it no longer does.

### Actions

- **Preview** — shows a detailed per-note reasoning report without writing anything.
- **Convert guitar** — writes Rock Band gem notes into the target track. Existing gems in the range are cleared first. Fully undoable.
- **Validate guitar** — checks existing gems on the target track against RBN authoring rules (chord density, sustain gaps, illegal combinations). Reports violations with measure positions.
