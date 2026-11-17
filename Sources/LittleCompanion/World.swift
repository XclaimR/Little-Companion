import AppKit
import QuartzCore

/// Spike world: one dog on the floor, a 3-state brain, click hit-testing, debug ledges.
/// shortcut: hand-rolled brain, replaced by the utility engine in roadmap step 2.
/// World coordinates are top-left-origin points on the main display (same as CGWindowList).
@MainActor final class World {
    enum State { case walk, idle, sleep, hop }

    static let dogSize = CGSize(width: 64, height: 44)
    static let speed: CGFloat = 55

    let panel: DesktopPanel
    let sprite = CALayer()
    let ledgeLayer = CALayer()
    let screenH: CGFloat, screenW: CGFloat, floorY: CGFloat

    var x: CGFloat = 240, dir: CGFloat = 1, state = State.idle, targetX: CGFloat = 240
    var until: TimeInterval = 0, hopT: CGFloat = 0, lastPoke: TimeInterval = 0
    var last = CACurrentMediaTime()
    var timer: Timer?
    var pose = ""

    // Bench mode: LC_BENCH=walk (desktop level) or top (above all windows): walk 60s, then sleep; log redraws.
    // LC_BENCH=top-still: dog asleep and stationary above all windows, for click tests.
    let bench: String?
    var benchPhase: State?
    var frames = 0

    init(screen: NSScreen, bench: String?) {
        self.bench = bench
        let f = screen.frame
        screenW = f.width; screenH = f.height
        floorY = f.height - (screen.visibleFrame.minY - f.minY) // top of the Dock, in top-left coords

        panel = DesktopPanel(frame: f, onTop: bench?.contains("top") == true)
        let view = ClickView(frame: NSRect(origin: .zero, size: f.size))
        view.wantsLayer = true
        panel.contentView = view
        sprite.contentsScale = DogSprite.scale
        sprite.magnificationFilter = .nearest
        sprite.bounds = CGRect(origin: .zero, size: DogSprite.canvas)
        sprite.anchorPoint = .zero
        view.layer!.addSublayer(ledgeLayer)
        view.layer!.addSublayer(sprite)
        view.onClick = { [weak self] p in self?.poke(at: p) }
        panel.orderFrontRegardless()

        // Clicks pass through except over the dog. Re-checked on mouse moves (no permission needed) and on each tick.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitTest() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            MainActor.assumeIsolated { self?.updateHitTest() }
            return e
        }

        if let bench, bench.contains("still") {
            benchPhase = .sleep // stays put: for click tests
            decide(now: CACurrentMediaTime()); until = .infinity
        } else if let bench {
            benchPhase = .walk
            decide(now: CACurrentMediaTime())
            Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.benchPhase = .sleep; self?.decide(now: CACurrentMediaTime()); print("BENCH sleep") }
            }
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    print("BENCH \(bench) frames/10s=\(self.frames)"); fflush(stdout); self.frames = 0
                }
            }
        }
        if ProcessInfo.processInfo.environment["LC_DEBUG"] != nil {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.drawLedges() }
            }
        }
        render()
        tick()
    }

    // MARK: brain

    func decide(now: TimeInterval) {
        let r: Double = switch benchPhase { case .walk: 0; case .sleep: 0.99; default: .random(in: 0..<1) }
        if r < 0.5 {
            state = .walk
            targetX = .random(in: 20...(screenW - Self.dogSize.width - 20))
            dir = targetX > x ? 1 : -1
        } else if r < 0.8 {
            state = .idle; until = now + .random(in: 2...6)
        } else {
            state = .sleep; until = now + .random(in: 8...20)
        }
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(2, now - last) // real elapsed time: ticks may be coalesced while hidden
        last = now
        switch state {
        case .walk:
            x += dir * Self.speed * dt
            if (targetX - x) * dir <= 0 { x = targetX; decide(now: now) }
            render()
        case .hop:
            hopT += dt * 2.5
            if hopT >= 1 { hopT = 0; state = .idle; until = now + 1.5 }
            render()
        case .idle, .sleep:
            if now > until { decide(now: now); render() }
        }
        let moving = state == .walk || state == .hop
        let interval = moving ? 1.0 / 20 : 0.5 // nothing redraws while still
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// A click is a nudge the dog may ignore; repeated clicks within 1.5s don't stack.
    func poke(at _: CGPoint) {
        let now = CACurrentMediaTime()
        guard now - lastPoke > 1.5 else { return }
        lastPoke = now
        if bench != nil { print("POKE state=\(state)"); fflush(stdout) }
        if state == .sleep && Bool.random() { until = now + .random(in: 3...8); return } // resettles
        state = .hop; hopT = 0
        timer?.invalidate(); tick()
    }

    // MARK: rendering & hit-testing

    var dogRect: CGRect {
        let lift = state == .hop ? sin(hopT * .pi) * 24 : 0
        return CGRect(x: x, y: floorY - Self.dogSize.height - lift, width: Self.dogSize.width, height: Self.dogSize.height)
    }

    func render() {
        frames += 1
        let r = dogRect
        let step = Int(x / 8) % 2
        let p = switch state { case .sleep: "sleep"; case .walk: "walk\(step)"; case .hop: "hop"; case .idle: "idle\(step)" }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Layer coords are bottom-left origin.
        sprite.position = CGPoint(x: (r.minX - DogSprite.dogOrigin.x).rounded(),
                                  y: (screenH - (r.minY - DogSprite.dogOrigin.y) - DogSprite.canvas.height).rounded())
        if p + "\(dir)" != pose { pose = p + "\(dir)"; sprite.contents = DogSprite.image(pose: p, facing: dir) }
        CATransaction.commit()
        updateHitTest()
    }

    func updateHitTest() {
        let m = NSEvent.mouseLocation
        let cursor = CGPoint(x: m.x, y: screenH - m.y)
        let hit = dogRect.insetBy(dx: -4, dy: -16).contains(cursor)
        if panel.ignoresMouseEvents == hit {
            panel.ignoresMouseEvents = !hit
            if bench != nil { print("HIT \(hit) cursor=\(cursor) dog=\(dogRect)"); fflush(stdout) }
        }
    }

    func drawLedges() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ledgeLayer.sublayers = otherWindowRects().map { r in
            let l = CALayer()
            l.backgroundColor = CGColor(srgbRed: 1, green: 0.47, blue: 0.24, alpha: 0.8)
            l.frame = CGRect(x: r.minX, y: screenH - r.minY, width: r.width, height: 3)
            return l
        }
        CATransaction.commit()
    }
}
