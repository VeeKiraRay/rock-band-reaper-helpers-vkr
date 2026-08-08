# Rock Band Authoring Tools for REAPER

Three REAPER ReaScript tools for custom Rock Band song authoring, sharing a common library.

| Script                                                                 | What it does                                                                                              |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **[Rock Band Vocal Helper](rock_band_vocal_helper_vkr/README.md)**     | Generate timing-aligned MIDI notes from a vocal stem, with pitch assignment and lyric assignment built in |
| **[Rock Band General Helper](rock_band_general_helper_vkr/README.md)** | Audio alignment utilities, audio-driven tempo map generation from a drum stem, and VENUE track validation |
| **Rock Band Music Theory Helper**                                       | Interactive instrument reference — drum notation legend, common drum patterns, and a guitar chord-shape explorer, with hover highlighting and audio playback (playback needs [SWS](#sws-extension-audio-playback-only)) |

---

## Requirements

- [REAPER](https://www.reaper.fm/) **6.x or later**
- [ReaImGui](https://forum.cockos.com/showthread.php?t=250419) **0.7 or later** (August 2022) — install via **Extensions → ReaPack → Browse packages**, search for `ReaImGui`

Each script checks both on startup: if ReaImGui is missing it shows an install prompt; if it is too old (pre-0.7) it shows an update prompt.

### SWS extension (audio playback only)

The Music Theory Helper's audio playback — **both** the drum samples and the Guitar tab's synthesized chord preview — runs on the [SWS/S&M extension](https://www.sws-extension.org/)'s `CF_Preview` API. Without SWS the two tabs work fine as a visual reference, but nothing will play. No other script in this repo needs it.

> **SWS is not a ReaPack package.** ReaPack installs ReaImGui; SWS is a native extension with its own installer. Having ReaPack working does *not* mean you have SWS.

1. Close REAPER.
2. Download the installer from [sws-extension.org](https://www.sws-extension.org/) and run it (defaults are fine).
3. When it asks for the REAPER resource path, check that it matches your install — if you run a **portable** REAPER, the auto-detected path will be wrong and the extension will land somewhere REAPER never reads.
4. Start REAPER. An **Extensions** menu appears in the main menu bar. There is nothing to enable — if that menu is there, it loaded.

If the Extensions menu is missing, open **Options → Show REAPER resource path in explorer → `UserPlugins/`** and check for `reaper_sws-x64.dll`. Absent means it installed to the wrong path; present but still no menu usually means an architecture mismatch (32-bit DLL under 64-bit REAPER) or antivirus quarantine.

To confirm the exact API these scripts use is available, run this as a ReaScript — `nil` means playback will be silently disabled:

```lua
reaper.ShowConsoleMsg('CF_CreatePreview: ' .. tostring(reaper.CF_CreatePreview) .. '\n')
```

---

## Additional tools

Three smaller scripts round out the toolset, loaded the same way as the main scripts:

- **[Standalone Venue Preview](rock_band_general_helper_vkr/README.md#standalone-venue-preview)** (`rock_band_preview_vkr.lua`) — the General Helper's Venue → Preview sub-tab in its own window, so it can sit next to the generation tabs.
- **[Standalone Pitch Tuner](rock_band_vocal_helper_vkr/README.md#standalone-pitch-tuner)** (`rock_band_pitch_tuner_vkr.lua`) — the Vocal Helper's Tuner tab in its own window, so the live readout stays visible while you work in another tab.
- **[Quick actions](rock_band_vocal_helper_vkr/README.md#quick-actions)** (`quick_actions/`) — four no-UI hotkey scripts for fast vocal-note editing in the MIDI editor.

You don't have to go back to the Actions list to switch between the windowed tools: the General Helper and the Vocal Helper each have a **General → Other tools** sub-tab with buttons that open any of the others. The tool you're already in isn't listed. Opening one from there also adds it to REAPER's Action list, so you can give it a shortcut afterwards.

---

## Installation

1. Download and extract `rb_helper_scripts_vkr.zip` into your REAPER Scripts folder (or any folder you use for ReaScripts). Keep all the `.lua` entry points together in that one folder — **General → Other tools** looks for its sibling tools beside the script that's running, and greys out any it can't find.
2. In REAPER: **Actions → Show action list → Load ReaScript** and select the script(s) you want: `rock_band_vocal_helper_vkr.lua`, `rock_band_general_helper_vkr.lua`, or `rock_band_music_theory_helper_vkr.lua`. Loading just one is enough to reach the rest — open it, then use **General → Other tools**.
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
