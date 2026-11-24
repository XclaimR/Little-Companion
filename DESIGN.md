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
3. **Menu bar icon only**, no Dock icon. As built: the dog's name · Change pet ▸ Dogs ▸ (Ollie, Biscuit, Mochi, Bean, Pepper) / Birds ▸ (Mango, Pearl, Kiwi, Sunny) · Hide for an hour · Open at login (installed app) · Quit. Planned: Open house · Call dog home (a suggestion).

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
- Typical simulated day (8 dogs, `simrun 8 24 1`): sleep 58–62%, kennel 6–13%, sit ~13%, idle ~8%, play 5–8%, wander 4–6%, carry 2–5%; asleep through the night (about 22:00–06:00: a rested dog dozes on instead of getting up), lively mornings and evenings. New tennis ball at 11:00 ends the day anywhere from going off it to carrying it everywhere.
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
- **Kennel:** a side-on plank cabin on the desktop floor (bottom-left), drawn as two layers: a lamp-lit interior behind the dog, and walls/roof with a window and an open, full-height doorway at the right end in front of it. The dog walks to the doorway, in, and back out the same way; while inside it potters, sits or naps and you see only its soft shadow through the window. Independent/lazy/tired dogs pop in for 3–15 min now and then (≈6–13% of the day). When the Mac is busy (1-min load average > 75% of cores) any awake dog runs inside within seconds and stays until it calms down.
- **Sleeping:** in its bed it lies on the cushion with the rim in front. Four positions — chin on paws, curled nose-to-tail, sprawled on its side, belly-up — chosen by a hidden taste leaned by personality (independent → curl, energetic → side, laid-back + affectionate → belly-up), refined by experience into a favourite, and shifting every few minutes. Every minute or few it dreams: each position has its own twitch (paw kick, ear flick, legs paddling, paws kicking the air); playful, energetic dogs dream more.
- Ollie's art: 23 frames in `Resources/ollie.png`, objects in `Resources/objects.png` + `objects.json` — both mirrored in the Pixelwright project "Little Companion".

### Living on a real Mac
- **Sleep and wake:** the dog stops when the Mac sleeps, its screens sleep or the session locks, and catches up with real (wall-clock) time on return. After 30+ minutes away it says hello where it is (up from a light doze, sits facing you, wags), whether or not the cursor is near.
- **Screens:** the floor and walkable range are re-read when the resolution, the Dock or the displays change; the home is kept in proportion and inside the range (a Dock on the left or right shrinks it). The dog lives on the menu-bar screen.
- **Hide for an hour** (menu): out of sight for screen sharing or a demo; the dog keeps living meanwhile.
- **Reduce Motion** (accessibility setting): no zoomies, jumps or tumbles, walks instead of runs, a still z instead of floating ones.
- **Energy:** the z's puff once every 15–30 s (none while you're away) instead of animating all night; drawing is skipped while the dog is under a window, and capped at 10 fps in Low Power Mode. Wags, grooming and blinks tick at their own pace.
- **Saves:** a save from a newer build is never overwritten (the menu says so); an unreadable one is moved aside first (named after the dog), and if that fails it's left alone.

## Birds (branch `feature/birds`)
One pet at a time; each keeps its own save (`state-mango.json`). Same engine as the dogs (`Brain`, needs, personality, learning, utility scoring); a species is data: its acts, its home and its movement. A dog walks the floor; a bird hops along a perch and flies between perches at different heights (`Sources/PetCore/Bird.swift`). Saves stay compatible: every bird field is optional and a dog's seed rolls the same dog as before.

- **Mango the cockatiel:** 32×32 art px at 1.5 pt/px, grey with a yellow face and crest and orange cheeks, 39 frames from `tools/art/bird_sheet.py` (perched, head-bob, look up/back, head tilt, blink, front; hop, peck; take-off, 4-step flap cycle, glide, landing flare, wobbly landing; preen, stretch, eat, splash; swing, bell; fluffed nap, head-tucked sleep, dream; startled, tumbling fall, recovery flap up and down). Crest is mood: up when excited or startled, flat when relaxed.
- **Its ball:** a woven rattan ball at the foot of the tree. A parrot picks it up in its beak, roams the desktop with it (two or three flights, preferring far perches and window tops), drops it in mid-flight and watches it bounce (it keeps 45% of its speed each bounce) with its head on one side; now and then it goes to fetch it and starts again. The ball stays wherever it ends up.
- **Preening** comes in bouts of a few seconds (longer for laid-back birds) with an uneven nibbling rhythm; between bouts a curious bird often stops to look round, others mostly preen straight on.
- **Joy flights (bird zoomies):** a lively, rested, happy bird sometimes swoops about the whole desktop for 6–12 waypoints without landing, then settles on a perch (at most every 15 min, and only when the desktop is fairly clear: two or fewer windows, or windows over less than about a third of the screen, so it's seen rather than behind your work). When you come to a clear desktop (an empty Space, Show Desktop) an awake bird reacts about one time in three: a joy flight, or off to a window top. Window tops are its favourite perch (about 3× likelier than before) and it settles there 1–4 min, so you'll often find it up there. It steers rather than flying fixed curves: it turns at most 2.6 rad/s (banking harder near an edge, and shying away from the edges), so there are no hairpins and no landing flare until it really lands. Owls glide most of it. `LC_DEMO=zoomies` shows one long one.
- **More birds on the same rig:** Pearl (lutino cockatiel: cream-white, red eyes), Kiwi (budgie: green, scalloped wings, small violet cheek spots, no crest) and Sunny (sun conure: golden, orange face, green and blue wings, no crest). Same 39 frames and behaviour; a species in `BIRDS` in `bird_sheet.py` sets its palette, crest, nape and wing pattern. Crestless birds show mood with eyes and pose. Each has its own save and personality.
- **Home:** a tall tree at the right end of the floor (84 px, ~1.6× the kennel) with four branches, a birdhouse on the trunk two-thirds up, a swing under the lowest branch, a bell under the top one, and seed and water dishes at its foot. The birdhouse is the kennel: it sleeps there at night and flies in while the Mac is busy (same rule), and you see its shadow through the round doorway. Perch geometry lives in `enum Tree` (mirrors `tools/art/bird_home.py`).
- **Perches:** branches, the floor (top of the Dock) and the top edges of other apps' windows. A window counts only if it's an ordinary window (layer 0, not ours, visible), ≥ 200 pt wide, with ≥ 48 pt clear above it (so not maximised under the menu bar), on the bird's screen, at a spot no window in front covers, and ≥ 96 pt in from its left (clear of the traffic lights).
- **Traits:** curious → visits windows more; energetic → flies more; affectionate → now and then (≤ every 10 min) moves to the window top nearest where you're working; clumsy → wobbly landings.
- **Flights:** a few an hour of its own choosing, plus trips to the dishes, swing, bell and birdhouse (`simrun`: ~10–15 per awake hour in all). Each flight is a Bézier arc; of four arcs it takes the one most out in the open (through gaps between windows); otherwise it is glimpsed passing behind them. Always on the desktop layer, never over your work.
- **Windows:** polled with `CGWindowListCopyWindowInfo` (no permission) ~15 Hz while it's on or flying to a window, ~1 Hz otherwise. Dragged → it rides along, balancing; flaps off if it's flung (> 1800 pt/s) or dragged for more than ~3–6 s. Closed (the window id no longer exists) → startled tumble, recovery flaps, flies on. Minimised or another Space (it still exists) → calm fly-off. Covered by another window → leaves after ~4 s. Maximised → leaves.
- **You:** it notices the cursor only near its perch (a glance and a head tilt); the cursor never steers it. A click on it: startled, crest up, sometimes a hop or a short flight. Back after 30+ min: crest up, a little hop, it faces you wherever it's perched.
- **Day / night:** eats, drinks, splashes, swings, rings its bell, preens, stretches, naps fluffed on a branch; nights in the birdhouse with dream twitches.
- **Testing:** `LC_PET=mango` picks the bird for one run without changing the saved choice (`LC_DEMO=1` then tours a window and the tree); with `LC_DEBUG=1` the 🐾 menu has "fly to a window", "pretend its window closed", swing, bell, splash and birdhouse. Tests cover window perch choice, riding a drag, flinging, falling when its window closes, minimise, covering, the busy retreat and four simulated days; `simrun [dogs] [hours] [seed] [birds]` checks a bird stays on screen and on its window's edge, never sits on a vanished window, sleeps 30–80%, retreats when busy and flies a few times an hour.
- **Verified on screen** (LC_TOP recording): flight onto a real window's top edge, riding a 300 pt drag, the fall/recovery when the window closed, swing, bell, splash, birdhouse sleep with its doorway shadow. Not yet seen on screen: the cursor head tilt, a click startle, covered/minimised fly-offs (unit-tested only).

## Owls
Change pet ▸ Owls. Four owls on the bird engine (species `owl`), drawn on an owl rig (`tools/art/owl_sheet.py`, built on the bird art helpers) and reviewed on screen at real size with the art-critic agent: **Moth** (barn owl: white heart face, black eyes, tall and slim), **Pip** (little owl: squat, white-spotted, yellow eyes under white brows), **Hedwig** (snowy owl: big, round and white with short black bars) and **Bramble** (long-eared owl: tawny, orange eyes, ear tufts that show mood like the cockatiel's crest). 32 frames each: perched (idle, front, blink, slow blink, head swivel over the shoulder, head tilts, tall-and-thin alert, fluffed), hoot A/B, waddle, pounce and mantling over a mouse, eat, take-off, flap cycle, long glide, landing flare, preen, wing-and-leg stretch, day doze on one leg, sleep, dream, the startled threat display (wings fanned like a shield), tumbling fall and recovery.

- **Home (chosen):** a hollow oak for every owl (`tools/art/owl_home.py`): bare crooked branches to perch on, and a knothole it sleeps in by day, where you see its eyes glint in the dark. **Toys:** a plush mouse (stalked and pounced on for fun, and carried up a branch and flung down), a pinecone to bat, a lantern that glows dusk to dawn, a log perch on the floor; it bathes in the birds' water dish. (A feather toy was tried and retired: lying upright it read as a grenade.)
- **Behaviour (as built):**
  - **Night clock:** an owl's sleep pressure is the bird clock shifted 12 hours, so it sleeps in the knothole by day (about 10:00–18:00) and is up at night. Eyes glint in the knothole while it's home; asleep, it peeks out now and then. The lantern on the right branch is lit 18:00–07:00.
  - **Hunting is how it eats:** when it's hungry a beetle scuttles or a moth flutters about on the floor (two-frame art, turning now and then). The owl lands a way off and watches it for 2 s, stalks after it (faster than its waddle), pounces when it's close, cloaks its wings over it and gulps it down with its head back. Prey that isn't caught in 25 s gets away. A hunt is never cut short by hunger.
  - **The toy mouse is play, not food:** it stalks it, pounces and mantles over it, then lets it go; or it picks it up in its beak, flies about with it (two or three flights, resting on each perch), lets go of it in mid-flight (it falls under gravity) and swoops after it.
  - **The lantern:** at night it likes to sit right by the lantern on the right branch, facing the light, and goes there first when it comes out after dark.
  - **Never quite still:** perched, it looks over its shoulder, slow-blinks or ruffles every couple of seconds. On the floor it waddles slowly (anything further, it flies), and the pinecone rolls along the floor rather than jumping.
  - **Night life:** fewer flights (about 5 per waking hour in `simrun`), gliding most of the way; it bats the pinecone along the floor, perches on the log, and hoots at dusk (18:30–21:30) and dawn (4:30–7:00) with a drawn "hoo" (no sound).
  - **You:** near its perch, its head (not its body) follows the cursor: a swivel over its shoulder or a tilt. Woken by a click by day it gives you a slow look and goes back to sleep, without a startle. The busy-Mac retreat is the knothole. Window perches, riding and falling are the birds'.
  - **Verified on screen** (Bramble, LC_TOP recordings, the night ones with `LC_HOUR=23`): perching on and riding a dragged window, the fall when it closed, eating (stare, pounce, mantle, gulp), carrying the mouse up a branch and flinging it, the hoot on a branch, batting the pinecone, sitting by the lit lantern, going into the knothole.
  - **Tests:** asleep by day and up through the night, eating by hunting, the daytime click, and four simulated owl days in `simrun [dogs] [hours] [seed] [birds] [owls]` (asleep ≥ 60% of 10:00–17:00, awake ≥ 40% of 22:00–04:00, hunts).

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
Env: `LC_HOUR=23` pin the clock to an hour (night for an owl, the lantern) · `LC_DEBUG=1` debug overlay, ledges and a **Test** section in the 🐾 menu · `LC_TOP=1` draw above all windows · `LC_SPEED=4` run life 4× faster · `LC_BUSY=1` pretend the Mac is busy · `LC_DEMO=1` scripted tour (ball, plush, sit, kennel, zoomies). Delete `state.json` to adopt a new dog.

## Roadmap
1. ~~Spike~~ — done; Swift chosen (see results above).
2. ~~Behaviour engine + headless runner~~ — done. Objects sit on the desktop floor until step 3.
3. House popup + drag-and-drop.
4. Window/icon platforms, toy physics.
5. Pixel art, emotes, tuning.

## Out of MVP
Unlock/purchase economy, multi-monitor, sound, dragging the dog, settings beyond the menu bar.

## TODO (post-MVP)
- [ ] **Random, stochastic elements in the world.** Now and then (every few days, only when the user is around) something new appears: a tennis ball, a stick, a leaf in autumn, at most one new thing at a time. The engine already handles novelty (`Brain.add`: the "!" / "?" reactions, sniffing, learning to like or ignore it); only the app never adds anything yet, so after a week preferences settle and days look alike.
- [ ] **Species choice: dog, cat, bird.** (Birds: see above, on `feature/birds`.) Picked at adoption; one pet at a time until multi-pet lands.
  - Keep species out of the engine core: a species is data (actions, animations, trait ranges, movement profile) plugged into the same utility engine.
  - **Cat:** higher jumps, likes high ledges (window tops, icons), more independent/aloof defaults, naps in sunbeams/boxes, knocks small toys off ledges.
  - **Bird:** breaks the gravity-only movement model — needs a flight movement profile (perch → fly → perch). Perches on window tops, icons and the kennel (birdhouse/cage variant). Needs its own home interior.
  - Each species needs its own sprite sheet and home variant.
