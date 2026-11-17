# Art tools

Pixel art for Little Companion is composed here and then mirrored into the Pixelwright project "Little Companion".

- `compose.py` — parametric 48×36 side-view dog composer (breeds × poses: stand, walk, sit, sleep, bow, run, zoomies, paw-up, shake).
- `front.py` — front-facing and back-facing sits.
- `ollie_sheet.py` — builds a dog's 81-frame sheet (poses, sleep positions, 4 toys × 8, tail wags, jump, trip and tumble, grooming): `python3 ollie_sheet.py tools/art <breed>` (pudding = Ollie, biscuit, mochi, bean, pepper) writes `tools/art/build/<name>.png`; copy it to `Sources/LittleCompanion/Resources/`.
- `palette.json` — token → hex for every colour in the Pixelwright palette.
- `objects_grids.json` — the home objects as pixel grids (source of `Resources/objects.png`).
- `sleepers.py` — the curled, side and belly-up sleeping positions and their dream twitches.
- `kennel.py` — the side-on cabin (front walls + lit interior) and the object atlas: `python3 kennel.py ../../Sources/LittleCompanion/Resources`.
- `kennel_options.py` / `kennel-options.png` — the four kennel styles considered (A cabin was chosen).
- `bird_sheet.py` — Mango the cockatiel, 38 frames of 32×32: `python3 bird_sheet.py tools/art` writes `build/mango.png` (+ `mango_preview.png`); copy it to `Sources/LittleCompanion/Resources/`.
- `bird_home.py` — a bird's tree (branches, birdhouse), swing, bell and dishes; packed into the objects atlas by `kennel.py`. `python3 bird_home.py` writes `build/bird_home_preview.png` with Mango on each perch. Perch heights are mirrored in `enum Tree` in `Sources/PetCore/Bird.swift`.
