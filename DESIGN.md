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
- Learning: preferences grow through experience and decay back toward innate likes; novelty boost for new objects; capped interaction log as memory.
- Circadian rhythm from local clock; user idle ≥10 min → longer naps; sometimes wanders to cursor on return.
- App closed: needs drift toward neutral; dog wakes in its favourite spot on launch.
- Visuals: body language first; trial emotes (zzz, !, ?, heart).
- 32px pixel-art dog at 2× (~64pt). Coloured-shape placeholders until behaviour works.

## Tooling & persistence
- Headless runner: fast-forward 24 simulated hours, assert invariants (never stuck, needs in range, no action dominating), print behaviour histogram.
- Dev-only debug overlay: scores and the reason for the chosen action.
- Single versioned JSON in app data; debounced ~30 s + save on quit.
- Personal use: unsigned builds, no updater.

## Running
```
swift build -c release && .build/release/LittleCompanion
```
Env: `LC_DEBUG=1` draws window-top ledges · `LC_BENCH=walk|top|top-still` benchmark modes (walk 60 s then sleep; `top` = above all windows; `still` = stationary asleep for click tests).

## Roadmap
1. ~~Spike~~ — done; Swift chosen (see results above).
2. Behaviour engine + headless runner.
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
