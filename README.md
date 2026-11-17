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

## Security check before commits

Every commit runs `.githooks/pre-commit`. Turn it on once per clone:

```sh
git config core.hooksPath .githooks
```

1. An instant local scan blocks anything that looks like a key, token or password, and files that should never be public (`.env`, keys, save files, build output).
2. The `security-reviewer` agent (`.claude/agents/security-reviewer.md`) then reads the staged diff for secrets, personal data, network calls, shell execution and anything that weakens the app's no-intrusion rules. It blocks on serious findings and lists warnings.

Notes: step 2 sends the staged diff to Claude, so it needs the `claude` CLI and usage. If it can't run, the commit goes through with only step 1, and you get a warning. To skip it once: `SKIP_SECURITY_REVIEW=1 git commit …`.
