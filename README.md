# Rock Band Authoring Tools for REAPER

Two REAPER ReaScript tools for custom Rock Band song authoring, sharing a common library.

| Script                                                                 | What it does                                                                                              |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **[Rock Band Vocal Helper](rock_band_vocal_helper_vkr/README.md)**     | Generate timing-aligned MIDI notes from a vocal stem, with pitch assignment and lyric assignment built in |
| **[Rock Band General Helper](rock_band_general_helper_vkr/README.md)** | Audio alignment utilities, audio-driven tempo map generation from a drum stem, and VENUE track validation |

---

## Requirements

- [REAPER](https://www.reaper.fm/) **6.x or later**
- [ReaImGui](https://forum.cockos.com/showthread.php?t=250419) **0.7 or later** (August 2022) — install via **Extensions → ReaPack → Browse packages**, search for `ReaImGui`

Each script checks both on startup: if ReaImGui is missing it shows an install prompt; if it is too old (pre-0.7) it shows an update prompt.

---

## Installation

1. Download and extract `rb_helper_scripts_vkr.zip` into your REAPER Scripts folder (or any folder you use for ReaScripts).
2. In REAPER: **Actions → Show action list → Load ReaScript** and select either `rock_band_vocal_helper_vkr.lua` or `rock_band_general_helper_vkr.lua`.
3. Optionally assign either action to a toolbar button or keyboard shortcut.

---

## A note on validation rules

Validation checks in these tools are not an official or definitive source of truth. They draw from a mix of sources:

- Established community guidelines (e.g. C3 docs, Harmonix authoring specs)
- My own interpretation of those guidelines
- Personal rules I apply to my own charts

Some checks may reflect outdated documentation, misread guidelines, or judgment calls that other authors might disagree with. If a validation flags something you believe is clearly wrong — incorrect threshold, misapplied rule, or a community guideline that has changed — please open an issue and describe what the rule currently does and what it should do instead. That kind of specific feedback is the easiest to act on.

---

## License

MIT — see [LICENSE](LICENSE).
