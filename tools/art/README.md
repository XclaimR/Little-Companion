# Art tools

Pixel art for Little Companion is composed here and then mirrored into the Pixelwright project "Little Companion".

- `compose.py` — parametric 48×36 side-view dog composer (breeds × poses: stand, walk, sit, sleep, bow, run, zoomies, paw-up, shake).
- `front.py` — front-facing and back-facing sits.
- `ollie_sheet.py` — builds Ollie's 16-frame sheet: `python3 ollie_sheet.py tools/art` writes `ollie11.png` (copy to `Sources/LittleCompanion/Resources/ollie.png`).
- `palette.json` — token → hex for every colour in the Pixelwright palette.
- `objects_grids.json` — the home objects as pixel grids (source of `Resources/objects.png`).
- `sleepers.py` — the curled, side and belly-up sleeping positions and their dream twitches.
- `kennel.py` — the side-on cabin (front walls + lit interior) and the object atlas: `python3 kennel.py ../../Sources/LittleCompanion/Resources`.
- `kennel_options.py` / `kennel-options.png` — the four kennel styles considered (A cabin was chosen).
