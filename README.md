# Little Companion

A small autonomous dog that lives on your macOS desktop. It sits on the desktop layer, under your windows: it never steals focus or blocks a click. It decides for itself what to do (nap, play, follow your cursor, retreat to its kennel when your Mac is busy) and slowly develops its own preferences.

Native Swift + AppKit + Core Animation. About 0.6% CPU while walking and close to zero asleep.

## Run

```
swift build -c release && .build/release/LittleCompanion
```

Quit from the 🐾 menu-bar icon. For testing: `LC_DEBUG=1` (overlay and a Test menu), `LC_SPEED=4`, `LC_BUSY=1`, `LC_DEMO=1`.

```
swift test                          # engine tests
swift run -c release simrun 4 24 1  # 4 dogs × 24 simulated hours
```

See [DESIGN.md](DESIGN.md) for the design, behaviour engine and roadmap.
