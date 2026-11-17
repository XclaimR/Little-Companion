# Little Companion — Design

A cosy, non-intrusive dog that lives on your desktop. It should feel like living with a real animal, not maintaining a game object. No needs management, no punishment, no sound. Stats and preferences are never shown to the user.

## Platform & stack
- macOS first; Windows later (= rewrite of the app; keep the behaviour engine free of AppKit so its logic ports cleanly).
- **Swift + AppKit + Core Animation**, Swift Package (no Xcode project). Not SpriteKit: it runs its own render loop.
- Efficiency: brain ticks ~5 Hz; redraw only on visual change; stop drawing while asleep-still or fully hidden. Movement ~20 fps, sprite frames swap only on pose change.
- Gate: < ~2% CPU walking, < ~0.3% asleep (our processes).

### Spike results (2026-11-17, MacBook, release builds)
| Stack | Walking | Asleep | Memory |
|---|---|---|---|
| Tauri (WKWebView + canvas) | ~7.4% (app + 3 WebKit procs) | 0.13–0.47% | ~165 MB |
| **Swift + Core Animation** | **0.6%** | **0.03%** | **46 MB** |

- Any animation over the desktop also costs WindowServer ~+4–5% while it moves, whatever the stack (even at 8 fps). Lever: the dog spends most of its time still/asleep.
- WKWebView throttles hidden pages to ~1 Hz timers; native timers also coalesce when hidden. The engine must use real elapsed time and tolerate multi-second tick gaps.
- Desktop-icon level + 1 window works: real windows occlude the dog; full-screen apps hide it.
- Non-activating `NSPanel` + toggling `ignoresMouseEvents` on cursor hit-test: clicking the dog does **not** change the frontmost app (verified).

## Windows
1. **Desktop layer** — transparent full-screen window above desktop icons, below normal windows. Main display only, all Spaces, not over full-screen apps. Windows occlude the dog like icons. Only dog/kennel/toy clicks are caught; everything else passes through.
2. **House popup** — ~480×320, opens above the kennel on click; closes on Esc / click-outside / kennel click.
3. **Menu bar icon only**, no Dock icon. Open house · Call dog home (a suggestion) · Hide for 1 hour · Quit.

## Desktop world
- Side-on with gravity. Platforms: floor (above Dock), window title-bar tops, desktop icons (via read-only Finder AppleScript, asked once; skipped if denied). Brief screen-edge climbs.
- Peeking behind windows comes free from occlusion.
- Window moved slowly → dog rides it. Fast/closed/minimised → hops or falls, lands softly, may sniff that window suspiciously later.
- Mild bias toward visible spots; long hidden → tends to go home.
- Kennel: draggable along the floor, default bottom-left. Dog always exits/enters via its door.

## Interaction
- Dog may notice/follow/pounce near the cursor. The cursor never moves or drags the dog.
- Clicking the dog is a stimulus it may ignore; sleeping dog may wake or resettle. Repeated clicks don't stack.
- Toys: flick-throw from house or desktop; physics on the same platforms; max 3 on the desktop, oldest returns home.
- Only toys leave the house. Bed, bowls, furniture stay inside.
- House: one room, bed, food bowl, water bowl, 3 toys, free catalog drawer with drag-and-drop. Bowls self-refill.

## Behaviour engine (pure Swift module, no AppKit imports, seeded RNG)
- Utility scoring from needs, personality, preferences, environment, recent history, randomness → weighted random pick.
- Durations, cooldowns, interruption.
- Personality: random hidden traits + small innate likes at adoption; user picks only the name.
- Learning: each object starts at a faint hint (0.3×) of the dog's hidden innate taste; experiences pull the learned preference toward the true taste (+ noise, + mood); disuse fades it back toward the faint hint over ~2 weeks. Novelty boost for new objects (decays over ~3 h); capped 200-entry interaction log as memory.

### As built (`Sources/PetCore`)
- `Model.swift` — state types (`DogState` is the whole persisted life), `SplitMix` seeded RNG.
- `Brain.swift` — scoring (`candidates`), weighted pick (`decide`, 3% "got distracted" random pick), `start`/`arrive`/`perform`/`finish`, needs over time, preference decay, interruptions, `poke`, `add` (new object), `resume(afterOffline:)`, `pose` for the renderer.
- Acts: idle, sit, lookAround, wander, sniff, sleep, stretch, groom, eat, drink, play, carry, zoomies, greet, react. Preference factor `exp(1.3·pref)`: a favourite is ~3.7× likelier, never certain.
- Typical simulated day (8 dogs): sleep 47–54%, sit ~15%, idle ~9%, play 5–9%, wander 4–8%, carry 1–7%; nights mostly asleep with brief wakes. New tennis ball at 11:00 ends the day anywhere from −0.38 (went off it) to +0.50 (carries it everywhere).
- App ticks: 20 Hz while moving, 5 Hz while still, 1 Hz asleep; timer gaps are simulated in ≤1 s steps (never dropped); gaps > 8 h use `resume`.
- Circadian rhythm from local clock; user idle ≥10 min → longer naps; sometimes wanders to cursor on return.
- App closed: needs drift toward neutral; dog wakes in its favourite spot on launch.
- Visuals: body language first; trial emotes (zzz, !, ?, heart).
- 32px pixel-art dog at 2× (~64pt). Coloured-shape placeholders until behaviour works.
- **Pixel designs:** [Little Companion — Dog Pixel Designs](https://claude.ai/artifact/MVW6fASYvK54PvE31tyUqf) (design canvas, private). Five candidates on the app's 32×24 grid — Biscuit (shiba-ish), Pudding (beagle-ish), Mochi (fluffy white), Bean (dachshund), Pepper (collie-ish tuxedo) — each in stand, walk ×2, sit, sleep and play bow, plus a real-size check on light and dark wallpaper. Sprites come from one parametric generator (body/leg/head size, ear, tail, markings, palette) that can be ported to Swift to produce the app's sprites.

### Behaviours added in testing with Ollie (beagle)
- **Gaits:** walk 42 pt/s; run 130 pt/s (greeting you, chasing a far cursor or a distant toy, sometimes when wandering happy); zoomies 170 pt/s. Each has its own frames.
- **Jumps** layer on top of any activity: hops while playing/zoomies; rare spontaneous jumps (playful × energetic × good mood × rested, rare at night, more just after you return); a startled jump with "!" when woken by a click or when something lands next to it; a pounce at the end of a cursor chase or on a rolling ball.
- **Cursor attention:** noticing a moving cursor near its floor, the dog chooses: *head* (glance; look-back frame when the cursor is behind), *body* (turns to face it) or *follow* (walks/runs after it). Lazy → glance, curious → turn, playful/affectionate → follow; tired or unhappy dogs mostly ignore it.
- **Play by toy:** balls roll away every few seconds and get chased, pounced on and batted (paw-up frame); plush and rope are grabbed and shaken (shake-up/down frames, toy held in the mouth), then dropped where play ended.
- **Sitting facing you** (front frame): sometimes when sitting (more if affectionate), when greeting you, and when it notices the cursor while sitting.
- **Kennel:** a side-on plank cabin on the desktop floor (bottom-left), drawn as two layers: a lamp-lit interior behind the dog, and walls/roof with a window and an open, full-height doorway at the right end in front of it. The dog walks to the doorway, in, and back out the same way; while inside it potters, sits or naps and you see only its soft shadow through the window. Independent/lazy/tired dogs pop in for 3–15 min now and then (≈10–15% of the day). When the Mac is busy (1-min load average > 75% of cores) any awake dog runs inside within seconds and stays until it calms down.
- **Sleeping:** in its bed it lies on the cushion with the rim in front. Four positions — chin on paws, curled nose-to-tail, sprawled on its side, belly-up — chosen by a hidden taste leaned by personality (independent → curl, energetic → side, laid-back + affectionate → belly-up), refined by experience into a favourite, and shifting every few minutes. Every minute or few it dreams: each position has its own twitch (paw kick, ear flick, legs paddling, paws kicking the air); playful, energetic dogs dream more.
- Ollie's art: 23 frames in `Resources/ollie.png`, objects in `Resources/objects.png` + `objects.json` — both mirrored in the Pixelwright project "Little Companion".

## Tooling & persistence
- Headless runner (`simrun`): fast-forwards dogs through simulated workdays (~0.3 s per day), checks invariants (needs in range, on the floor, never stuck awake 20 min, no maxed need for an hour, sleep 30–80%, no awake act > 30%, ≥ 8 different acts), prints histogram, per-object preferences and an hourly timeline.
- Tests (`swift test`): six seeded days hold invariants; same seed → same day; dogs differ (favourite toy, routine); enjoyable toy becomes a favourite; state round-trips through JSON.
- Dev-only debug overlay (`LC_DEBUG=1`): current act, needs, traits, preferences, last decision's top scores, window-top ledges.
- Single versioned JSON at `~/Library/Application Support/LittleCompanion/state.json`; atomic write every 30 s + on quit. An unreadable file is moved aside (`state.unreadable-*.json`), never overwritten.
- Personal use: unsigned builds, no updater.

## Running
```
swift build -c release && .build/release/LittleCompanion   # the app
swift run -c release simrun 4 24 1                          # 4 dogs × 24 h, seeds 1–4
swift test                                                  # engine tests
```
Env: `LC_DEBUG=1` debug overlay, ledges and a **Test** section in the 🐾 menu · `LC_TOP=1` draw above all windows · `LC_SPEED=4` run life 4× faster · `LC_BUSY=1` pretend the Mac is busy · `LC_DEMO=1` scripted tour (ball, plush, sit, kennel, zoomies). Delete `state.json` to adopt a new dog.

## Roadmap
1. ~~Spike~~ — done; Swift chosen (see results above).
2. ~~Behaviour engine + headless runner~~ — done. Objects sit on the desktop floor until step 3.
3. House popup + drag-and-drop.
4. Window/icon platforms, toy physics.
5. Pixel art, emotes, tuning.

## Out of MVP
Unlock/purchase economy, multi-monitor, sound, dragging the dog, settings beyond the menu bar.

## TODO (post-MVP)
- [ ] **Species choice: dog, cat, bird.** Picked at adoption; one pet at a time until multi-pet lands.
  - Keep species out of the engine core: a species is data (actions, animations, trait ranges, movement profile) plugged into the same utility engine.
  - **Cat:** higher jumps, likes high ledges (window tops, icons), more independent/aloof defaults, naps in sunbeams/boxes, knocks small toys off ledges.
  - **Bird:** breaks the gravity-only movement model — needs a flight movement profile (perch → fly → perch). Perches on window tops, icons and the kennel (birdhouse/cage variant). Needs its own home interior.
  - Each species needs its own sprite sheet and home variant.
