import AppKit
import PetCore
import QuartzCore

/// Renders the brain on the desktop layer and feeds it the environment (clock, idle time, cursor, clicks).
/// World coordinates are top-left-origin points on the main display (same as CGWindowList); layers are bottom-left.
@MainActor final class World {
    let panel: DesktopPanel
    let dogLayer = CALayer(), emoteLayer = CATextLayer(), debugLayer = CATextLayer(), ledgeLayer = CALayer()
    var objectLayers: [String: CALayer] = [:]
    let screenW: CGFloat, screenH: CGFloat, floorY: CGFloat
    var brain: Brain
    var last = CACurrentMediaTime()
    var spriteKey = "", dogOrigin = CGPoint(x: -1, y: -1), emoteText = ""
    let debug = ProcessInfo.processInfo.environment["LC_DEBUG"] != nil
    /// LC_SPEED=10 runs the dog's life 10× faster, for testing behaviour (walking looks fast too).
    let speed = max(0.1, Double(ProcessInfo.processInfo.environment["LC_SPEED"] ?? "") ?? 1)

    init(screen: NSScreen) {
        let f = screen.frame
        screenW = f.width; screenH = f.height
        floorY = f.height - (screen.visibleFrame.minY - f.minY) // top of the Dock

        if let saved = Store.load() {
            brain = Brain(state: saved.state)
            brain.resume(afterOffline: Date().timeIntervalSince(saved.savedAt))
        } else {
            brain = Brain(seed: UInt64.random(in: 1...UInt64.max)) // adoption: new hidden personality
            brain.s.objects = defaultObjects(width: Double(f.width))
            brain.s.x = 160
        }
        if !brain.s.objects.contains(where: { $0.kind == .kennel }) {
            brain.s.objects.insert(PetObject(id: "kennel", kind: .kennel, x: 60), at: 0)
        }
        for i in brain.s.objects.indices { brain.s.objects[i].x = min(max(brain.s.objects[i].x, 40), Double(f.width) - 40) }

        panel = DesktopPanel(frame: f, onTop: ProcessInfo.processInfo.environment["LC_TOP"] != nil)
        let view = ClickView(frame: NSRect(origin: .zero, size: f.size))
        view.wantsLayer = true
        panel.contentView = view
        let root = view.layer!
        dogLayer.anchorPoint = .zero
        dogLayer.bounds = CGRect(origin: .zero, size: DogSprite.size)
        dogLayer.magnificationFilter = .nearest   // whole-pixel scaling, no blur
        dogLayer.zPosition = 1
        emoteLayer.contentsScale = DogSprite.scale
        emoteLayer.fontSize = 15
        emoteLayer.alignmentMode = .center
        emoteLayer.foregroundColor = DogSprite.rgb(0.42, 0.33, 0.55)
        emoteLayer.bounds = CGRect(x: 0, y: 0, width: 24, height: 20)
        emoteLayer.zPosition = 3
        root.addSublayer(ledgeLayer)
        root.addSublayer(dogLayer)
        root.addSublayer(emoteLayer)
        if debug {
            debugLayer.contentsScale = DogSprite.scale
            debugLayer.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            debugLayer.fontSize = 11
            debugLayer.foregroundColor = .white
            debugLayer.backgroundColor = CGColor(gray: 0, alpha: 0.6)
            debugLayer.frame = CGRect(x: 12, y: f.height - 300, width: 360, height: 260)
            debugLayer.zPosition = 4
            root.addSublayer(debugLayer)
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.drawDebug() }
            }
        }
        view.onClick = { [weak self] _ in
            guard let self else { return }
            self.brain.poke(env: self.environment())
            self.render()
        }
        panel.orderFrontRegardless()

        // Clicks pass through except over the dog. Re-checked on mouse moves (no permission needed) and on each tick.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitTest() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            MainActor.assumeIsolated { self?.updateHitTest() }
            return e
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        render()
        tick()
        if ProcessInfo.processInfo.environment["LC_DEMO"] != nil {   // scripted tour for testing
            let steps: [(TimeInterval, Act, String?)] = [(1, .play, "ball"), (15, .play, "plush"), (40, .sit, nil), (48, .kennel, "kennel"), (63, .zoomies, nil)]
            for (at, act, target) in steps {
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(act, target) } }
            }
        }
    }

    func save() { Store.save(brain.s) }

    /// Debug menu: make the dog do something now.
    func test(_ act: Act, _ target: String? = nil) {
        brain.debugStart(act, target: target, env: environment())
        render()
    }

    func environment() -> Environment {
        let m = NSEvent.mouseLocation
        let cursorY = screenH - m.y
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        // kCGAnyInputEventType: seconds since any keyboard/mouse input. Needs no permission.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return Environment(minX: 40, maxX: Double(screenW) - 40,
                           hour: Double(now.hour ?? 12) + Double(now.minute ?? 0) / 60,
                           userIdle: idle,
                           cursorX: abs(cursorY - floorY) < 160 ? Double(m.x) : nil, // only notices a cursor near its floor
                           systemBusy: systemBusy())
    }

    /// Heavy CPU load: 1-minute load average above 75% of the cores. LC_BUSY=1 forces it, for testing.
    var forceBusy = ProcessInfo.processInfo.environment["LC_BUSY"] != nil   // debug menu can toggle it

    func systemBusy() -> Bool {
        if forceBusy { return true }
        var load = [0.0, 0.0, 0.0]
        guard getloadavg(&load, 3) > 0 else { return false }
        return load[0] > Double(ProcessInfo.processInfo.activeProcessorCount) * 0.75
    }

    func tick() {
        let now = CACurrentMediaTime()
        // macOS delays timers (App Nap, coalescing) — simulate the whole gap in ≤1 s steps so no time is lost.
        var gap = now - last
        last = now
        if debug && gap > 1.5 { NSLog("LittleCompanion: tick gap %.1fs", gap) }
        if gap > 8 * 3600 { brain.resume(afterOffline: gap); gap = 0 } // e.g. machine slept
        gap *= speed
        let env = environment()
        while gap > 0 { let step = min(gap, 1); brain.update(dt: step, env: env); gap -= step }
        render()
        var interval: TimeInterval = switch brain.pose.anim {
        case .walk, .run, .zoom, .play, .hop: 1.0 / 20
        case .sleep: 1.0
        default: 0.2 // brain at 5 Hz; nothing redraws unless something changed
        }
        if brain.pose.jump != nil { interval = 1.0 / 30 }   // smooth arc
        if brain.pose.hidden { interval = 1.0 }             // inside the kennel: nothing to draw
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - Rendering

    var dogRect: CGRect {
        let p = brain.pose
        let t = CACurrentMediaTime()
        var lift: CGFloat = 0
        if p.anim == .hop { lift = abs(sin(t * 7)) * 18 }
        if p.twitch { lift = 2 }
        if let j = p.jump { lift += sin(j * .pi) * p.jumpHeight }
        if p.anim == .run || p.anim == .zoom { lift += Int(p.x / 16) % 2 == 0 ? 0 : 2 }   // gallop bounce
        let s = DogSprite.size
        let footGap = DogSprite.footRows * DogSprite.pointsPerPixel
        return CGRect(x: p.x - s.width / 2, y: floorY - s.height + footGap - lift, width: s.width, height: s.height)
    }

    /// Which of Ollie's six frames shows each animation.
    func spriteFrame(_ p: Pose, time t: CFTimeInterval) -> DogSprite.Frame {
        switch p.anim {
        case .walk: return Int(p.x / 10) % 2 == 0 ? .walkA : .walkB
        case .run: return Int(p.x / 16) % 2 == 0 ? .runA : .runB
        case .zoom: return Int(p.x / 20) % 2 == 0 ? .zoomA : .zoomB
        case .sit: return p.front ? .sitFront : p.back ? .sitBack : .sit
        case .sleep: return .sleep
        case .play:
            if p.play == "shake" { return Int(t * 6) % 2 == 0 ? .shakeA : .shakeB }   // shaking the toy in its mouth
            return Int(t * 3) % 2 == 0 ? .pawUp : .stand                               // batting at the ball
        case .stretch, .headDown: return .bow   // shortcut: no head-down frame yet; the bow lowers the head
        case .stand, .hop:
            if p.jump != nil { return .runB }   // legs tucked under while airborne
            if p.attention == "head", let lx = p.lookX, (lx - p.x) * p.facing < 0 { return .look }   // glancing back at the cursor
            return .stand
        }
    }

    func render() {
        let p = brain.pose
        let r = dogRect
        let t = CACurrentMediaTime()
        let frame = spriteFrame(p, time: t)
        let origin = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())
        let key = "\(frame.rawValue)\(p.facing)"
        let emote = p.emote ?? ""

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dogLayer.isHidden != p.hidden { dogLayer.isHidden = p.hidden; emoteLayer.isHidden = p.hidden }
        if origin != dogOrigin { dogOrigin = origin; dogLayer.position = origin }
        if key != spriteKey { spriteKey = key; dogLayer.contents = DogSprite.image(frame, facing: CGFloat(p.facing)) }
        if emote != emoteText { emoteText = emote; emoteLayer.string = emote }
        if !emote.isEmpty {   // above the head, which sits toward the facing side
            let headTop: CGFloat = p.anim == .sleep ? 21 : 5   // art rows
            let ex = r.midX + CGFloat(p.facing) * 14
            emoteLayer.position = CGPoint(x: ex, y: screenH - (r.minY + headTop * DogSprite.pointsPerPixel) + 12)
        }
        renderObjects(carrying: p.carrying, dog: r, facing: CGFloat(p.facing))
        CATransaction.commit()
        updateHitTest()
    }

    func renderObjects(carrying: String?, dog: CGRect, facing: CGFloat) {
        let root = panel.contentView!.layer!
        let ids = Set(brain.s.objects.map(\.id))
        for (id, l) in objectLayers where !ids.contains(id) { l.removeFromSuperlayer(); objectLayers[id] = nil }
        for o in brain.s.objects {
            let (img, size) = ObjectSprite.image(id: o.id, kind: o.kind.rawValue)
            let l = objectLayers[o.id] ?? {
                let l = CALayer()
                l.contents = img; l.anchorPoint = .zero
                l.bounds = CGRect(origin: .zero, size: size)
                l.magnificationFilter = .nearest
                l.zPosition = o.kind == .rug || o.kind == .bed || o.kind == .kennel ? -1 : 0
                root.addSublayer(l); objectLayers[o.id] = l
                return l
            }()
            let held = o.id == carrying
            let mouthRow: CGFloat = spriteKey.hasPrefix("\(DogSprite.Frame.shakeA.rawValue)") ? 13 : spriteKey.hasPrefix("\(DogSprite.Frame.shakeB.rawValue)") ? 21 : 17
            let bottom = held ? dog.minY + mouthRow * DogSprite.pointsPerPixel : floorY // carried toys ride in its mouth
            let pos = CGPoint(x: (CGFloat(o.x) - size.width / 2).rounded(), y: (screenH - bottom).rounded())
            if l.position != pos { l.position = pos }
            let z: CGFloat = held ? 2 : (o.kind == .rug || o.kind == .bed || o.kind == .kennel ? -1 : 0)
            if l.zPosition != z { l.zPosition = z }
        }
    }

    func updateHitTest() {
        let m = NSEvent.mouseLocation
        let cursor = CGPoint(x: m.x, y: screenH - m.y)
        let hit = !brain.pose.hidden && dogRect.insetBy(dx: -4, dy: -12).contains(cursor)
        if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
    }

    func drawDebug() {
        let s = brain.s, a = s.activity, n = s.needs, p = s.personality
        let prefs = s.objects.map { String(format: "%@ %+.2f", $0.id, brain.pref($0)) }.joined(separator: "  ")
        debugLayer.string = """
         \(a.act.rawValue)\(a.target.map { " → " + $0 } ?? "")\(a.destX != nil ? " (walking)" : String(format: " %.0fs left", a.remaining))
         needs  hunger \(f(n.hunger)) thirst \(f(n.thirst)) tired \(f(n.tiredness)) bored \(f(n.boredom))
         traits play \(f(p.playfulness)) lazy \(f(p.laziness)) affect \(f(p.affection))
                indep \(f(p.independence)) curious \(f(p.curiosity)) energy \(f(p.energy))
         prefs  \(prefs)
         last decision:
           \(brain.lastScores.joined(separator: "\n   "))
        """
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ledgeLayer.sublayers = otherWindowRects().map { r in
            let l = CALayer()
            l.backgroundColor = CGColor(srgbRed: 1, green: 0.47, blue: 0.24, alpha: 0.8)
            l.frame = CGRect(x: r.minX, y: screenH - r.minY, width: r.width, height: 3)
            return l
        }
        CATransaction.commit()
    }

    private func f(_ v: Double) -> String { String(format: "%.2f", v) }
}
