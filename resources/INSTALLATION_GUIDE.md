# Resources — Installation Guide

The `resources/` folder holds optional asset packs that are distributed separately from the Lua scripts. Place downloaded packages here using **Extract Here** so that the subfolders land in the right place.

---

## Expected folder structure

```
resources/
  img/
    drum.png               ← bundled with the scripts (no download needed)
    spritesheets/
      camera/          *.jpg          ← full-size camera cut sprites       (426×240 px tiles)
      camera small/    *.jpg          ← half-size camera cut sprites       (213×120 px tiles)
      lighting/        *.jpg          ← full-size lighting sprites          (426×240 px tiles)
      lighting small/  *.jpg          ← half-size lighting sprites          (213×120 px tiles)
      postproc/        *.jpg          ← full-size post-process sprites     (426×240 px tiles)
      postproc small/  *.jpg          ← half-size post-process sprites     (213×120 px tiles)
  audio/
    drums/             *.ogg          ← drum sample pack (for music theory helper)
  themes/              *.rbtheme      ← venue theme presets (for general helper)
```

---

## Packages

Files can be found in my Google Drive: https://drive.google.com/drive/folders/17JGZVDkMj2JeOipHHXfdxSV8zazmHP0D

Download the packages you need, then **Extract Here** inside the `resources/` folder.

| Package zip | Provides | Used by |
|---|---|---|
| `img_large.zip` | `img/spritesheets/camera/`, `lighting/`, `postproc/` — 426×240 px tiles | General helper — venue sprite previews at 2× scale |
| `img_small.zip` | `img/spritesheets/camera small/`, `lighting small/`, `postproc small/` — 213×120 px tiles | General helper — venue sprite previews at 1× scale |
| `audio.zip` | `audio/drums/*.ogg` | Music Theory helper — drum audio preview |

You can install both `img_large.zip` and `img_small.zip` side by side — they populate different subfolders and do not conflict. Install only the size(s) you intend to use.

### Example

To install the large sprite pack:

1. Download `img_large.zip` from the Google Drive link above.
2. Open the `resources/` folder (it lives next to the `.lua` entry point scripts).
3. Right-click → **Extract Here** (or equivalent in your archive tool).
4. Confirm the result is `resources/img/spritesheets/camera/`, `resources/img/spritesheets/lighting/`, and `resources/img/spritesheets/postproc/`.

---

## Themes — adding your own

Drop any `.rbtheme` file into `resources/themes/` and it will appear in the **Venue → Themes gen** dropdown the next time the general helper opens that tab. No restart required — themes are loaded lazily on first tab open.

Venue theme files (`.rbtheme`) are not distributed with this project. If you have authored songs with Magma or another Rock Band authoring tool, check the project folder for any existing `.rbtheme` presets you can copy across.

---

## What works without the packs

| Feature | Requires | Without it |
|---|---|---|
| Venue theme generation | `themes/` | Themes gen sub-tab disabled; Analysis, Manual gen, and Section gen (Custom mode) still work |
| Venue sprite previews | `img/spritesheets/` | No animation previews; some events fall back to descriptive text tooltips, others show nothing |
| Music theory drum notation | bundled (`img/drum.png`) | Notation image missing; all other music theory features work normally |
| Music theory drum audio preview | `audio/drums/` | Audio playback disabled; all other music theory features work normally |
