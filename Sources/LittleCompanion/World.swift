import AppKit
import PetCore
import QuartzCore

/// Renders the brain on the desktop layer and feeds it the environment (clock, idle time, cursor, clicks).
/// World coordinates are top-left-origin points on the main display (same as CGWindowList); layers are bottom-left.
@MainActor final class World {
    let panel: DesktopPanel
    let dogLayer = CALayer(), emoteLayer = CATextLayer(), debugLayer = CATextLayer(), ledgeLayer = CALayer()
    var objectLayers: [String: CALayer] = [:]
    var kennelFront: CALayer?
    let zzzLayer = CALayer()   // floating z's while asleep, animated by Core Animation (no per-frame work)
    var bedRims: [String: CALayer] = [:]
    let screenW: CGFloat, screenH: CGFloat, floorY: CGFloat
    var brain: Brain
    var last = CACurrentMediaTime()
    var spriteKey = "", dogOrigin = CGPoint(x: -1, y: -1), emoteText = "", dogTilt: CGFloat = 0
    let debug = ProcessInfo.processInfo.environment["LC_DEBUG"] != nil
    /// LC_LOG=1 prints every activity change, jump and cursor reaction (for watching behaviour in tests).
    let log = ProcessInfo.processInfo.environment["LC_LOG"] != nil
    var logged = (started: -1.0, jump: false, attention: "", pose: "")
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
        // Keep the bed, bowls and toys clear of the kennel (older saves put them where the kennel now stands).
        if let k = brain.s.objects.first(where: { $0.kind == .kennel }) {
            var cursor = k.x + Double(ObjectSprite.image(id: k.id, kind: "kennel").1.width) / 2 + 8
            for o in brain.s.objects.filter({ $0.kind != .kennel }).sorted(by: { $0.x < $1.x }) where o.x < cursor + 200 {
                let half = Double(ObjectSprite.image(id: o.id, kind: o.kind.rawValue).1.width) / 2
                if o.x - half < cursor, let i = brain.s.objects.firstIndex(where: { $0.id == o.id }) { brain.s.objects[i].x = cursor + half }
                cursor = max(cursor, (brain.s.objects.first { $0.id == o.id }?.x ?? o.x) + half + 8)
            }
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
        setUpZzz(in: root)
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
            let steps: [(TimeInterval, Act, String?)] = [(1, .zoomies, nil), (12, .greet, nil), (20, .sit, nil), (28, .sit, nil), (36, .wander, nil), (44, .play, "ball"), (55, .carry, "rope")]
            for (at, act, target) in steps {
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(act, target) } }
            }
        }
    }

    func save() { Store.save(brain.s) }

    func logChanges() {
        let s = brain.s, a = s.activity, p = brain.pose
        var line = [String]()
        if a.started != logged.started {
            logged.started = a.started
            var d = "\(a.act.rawValue)" + (a.target.map { " → \($0)" } ?? "")
            if a.running == true { d += " (running)" }
            if a.act == .sit { d += a.front == true ? " facing you" : a.back == true ? " facing away" : " side-on" }
            line.append(d)
        }
        let extra = [p.sleepPos.map { "sleep:\($0)" }, p.inBed.map { _ in "in bed" }, p.play, a.phase.map { "kennel:\($0)" }].compactMap { $0 }.joined(separator: " ")
        if extra != logged.pose { logged.pose = extra; if !extra.isEmpty { line.append("[\(extra)]") } }
        if (s.jumpAt != nil) != logged.jump { logged.jump = s.jumpAt != nil; if logged.jump { line.append("JUMP") } }
        if (s.attention ?? "") != logged.attention { logged.attention = s.attention ?? ""; if let at = s.attention { line.append("cursor:\(at)") } }
        if s.twitchUntil > s.time && p.anim == .sleep && !line.contains("twitch") { }
        guard !line.isEmpty else { return }
        let n = s.needs
        print(String(format: "%7.0fs  %@   (hungry %.2f tired %.2f bored %.2f)", s.time, line.joined(separator: "  "), n.hunger, n.tiredness, n.boredom))
        fflush(stdout)
    }

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
        if log { logChanges() }
        render()
        var interval: TimeInterval = switch brain.pose.anim {
        case .walk, .run, .zoom, .play, .hop: 1.0 / 20
        case .sleep: 1.0
        default: 0.2 // brain at 5 Hz; nothing redraws unless something changed
        }
        if brain.s.jumpAt != nil { interval = 1.0 / 30 }   // smooth arc
        if brain.pose.hidden { interval = 1.0 }             // inside the kennel: nothing to draw
        if brain.pose.twitch { interval = 1.0 / 8 }         // dreaming: paddling paws
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
        if p.twitch && p.anim != .sleep { lift = 2 }
        if p.inBed != nil { lift += 3 * DogSprite.pointsPerPixel }   // sunk into the cushion, the rim covering its lower body
        if let j = p.jump { lift += 4 * j * (1 - j) * p.jumpHeight }   // a true parabola, peak at the middle
        if p.anim == .run || p.anim == .zoom { lift += Int(p.x / 16) % 2 == 0 ? 0 : 2 }   // gallop bounce
        let s = DogSprite.size
        let footGap = DogSprite.footRows * DogSprite.pointsPerPixel
        return CGRect(x: p.x - s.width / 2, y: floorY - s.height + footGap - lift, width: s.width, height: s.height)
    }

    /// Which of Ollie's six frames shows each animation.
    func spriteFrame(_ p: Pose, time t: CFTimeInterval) -> DogSprite.Frame {
        if p.crouch { return .jumpCrouch }
        if let j = p.jump { return j < 0.5 ? .jumpUp : .jumpDown }   // thrusting off, then reaching for the floor
        switch p.anim {
        case .walk: return Int(p.x / 10) % 2 == 0 ? .walkA : .walkB
        case .run: return Int(p.x / 16) % 2 == 0 ? .runA : .runB
        case .zoom: return Int(p.x / 20) % 2 == 0 ? .zoomA : .zoomB
        case .sit: return p.front ? .sitFront : p.back ? .sitBack : .sit
        case .sleep:
            let dreaming = p.twitch && Int(t * 6) % 2 == 0   // each position has its own dream twitch
            switch p.sleepPos {
            case "curl": return dreaming ? .sleepCurlTwitch : .sleepCurl      // ear flicks
            case "side": return dreaming ? .sleepSideTwitch : .sleepSide      // legs paddle
            case "belly": return dreaming ? .sleepBellyTwitch : .sleepBelly   // paws kick the air
            default: return dreaming ? .sleepTwitch : .sleep                   // front paw kicks
            }
        case .play:
            if p.play == "shake" { return Int(t * 6) % 2 == 0 ? .shakeA : .shakeB }   // shaking the toy in its mouth
            return Int(t * 3) % 2 == 0 ? .pawUp : .stand                               // batting at the ball
        case .stretch, .headDown: return .bow   // shortcut: no head-down frame yet; the bow lowers the head
        case .stand, .hop:
            if p.attention == "head", let lx = p.lookX, (lx - p.x) * p.facing < 0 { return .look }   // glancing back at the cursor
            return .stand
        }
    }

    func render() {
        let p = brain.pose
        let r = dogRect
        let t = CACurrentMediaTime()
        let frame = spriteFrame(p, time: t)
        var index = frame.rawValue
        if let toy = p.holding {   // the toy's own frame for whatever it's doing with it
            var pose: Int = switch frame {
            case .walkA: 0
            case .walkB: 1
            case .runA, .zoomA, .jumpUp: 2
            case .runB, .zoomB, .jumpDown: 3
            case .shakeA: 5
            case .shakeB: 6
            default: 4
            }
            if p.toss { pose = 7 }
            index = DogSprite.toyFrame(toy, pose) ?? index
        } else if p.wag, let w = frame.wagging(t) {
            index = w.rawValue
        }
        let origin = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())
        let rawEmote = p.emote ?? ""

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dogLayer.isHidden != p.hidden { dogLayer.isHidden = p.hidden; emoteLayer.isHidden = p.hidden }
        if origin != dogOrigin { dogOrigin = origin; dogLayer.position = origin }
        let tilt = p.jump.map { CGFloat((0.5 - $0) * 0.55 * p.facing) } ?? 0   // nose up rising, nose down falling
        if tilt != dogTilt {
            dogTilt = tilt
            let c = CGPoint(x: dogLayer.bounds.midX, y: dogLayer.bounds.midY)   // about the middle, not the anchor corner
            dogLayer.setAffineTransform(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: tilt).translatedBy(x: -c.x, y: -c.y))
        }
        let kennelX = brain.s.objects.first { $0.kind == .kennel }.map { CGFloat($0.x) }
        let shadow = p.inKennel && kennelX.map { CGFloat(p.x) < $0 + 13 } == true   // fully past the open end: only its shadow shows
        let key = "\(index)\(p.facing)" + (shadow ? "s" : "")
        if key != spriteKey {
            spriteKey = key
            dogLayer.contents = shadow ? DogSprite.silhouette(index, facing: CGFloat(p.facing)) : DogSprite.image(index, facing: CGFloat(p.facing))
        }
        let snoozing = rawEmote == "z"   // asleep: floating z's instead of the static emote
        if zzzLayer.isHidden == snoozing { zzzLayer.isHidden = !snoozing }
        if snoozing {
            let headX = r.midX + CGFloat(p.facing) * 18
            let headTop = r.minY + 25 * DogSprite.pointsPerPixel   // lying down: rise from just above the head
            zzzLayer.position = CGPoint(x: headX, y: screenH - headTop)
        }
        let emote = snoozing ? "" : rawEmote
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
            let baked = held && brain.pose.holding != nil   // drawn into the dog's frame instead
            if l.isHidden != baked { l.isHidden = baked }
            let mouthRow: CGFloat = spriteKey.hasPrefix("\(DogSprite.Frame.shakeA.rawValue)") ? 13 : spriteKey.hasPrefix("\(DogSprite.Frame.shakeB.rawValue)") ? 21 : 17
            let bottom = held ? dog.minY + mouthRow * DogSprite.pointsPerPixel : floorY // carried toys ride in its mouth
            let sink: CGFloat = o.kind == .kennel ? DogSprite.footRows * DogSprite.pointsPerPixel : 0   // kennel walls reach the dog's lowest outline row
            let pos = CGPoint(x: (CGFloat(o.x) - size.width / 2).rounded(), y: (screenH - bottom - sink).rounded())
            if l.position != pos { l.position = pos }
            let z: CGFloat = held ? 2 : (o.kind == .rug || o.kind == .bed || o.kind == .kennel ? -1 : 0)
            if l.zPosition != z { l.zPosition = z }
            if o.kind == .kennel { renderKennelFront(over: l, inKennel: brain.pose.inKennel) }
            if o.kind == .bed { renderBedRim(o, over: l, size: size, img: img) }
        }
    }

    /// The kennel is two pictures: the lit interior (behind the dog) and the walls and roof with the doorway and
    /// window cut out — in front of the dog while it goes in, potters about inside and comes back out.
    func renderKennelFront(over back: CALayer, inKennel: Bool) {
        let front = kennelFront ?? {
            let (img, size) = ObjectSprite.image(id: "kennelFront", kind: "kennelFront")
            let l = CALayer()
            l.contents = img; l.anchorPoint = .zero; l.bounds = CGRect(origin: .zero, size: size); l.magnificationFilter = .nearest
            panel.contentView!.layer!.addSublayer(l)
            kennelFront = l
            return l
        }()
        if front.position != back.position { front.position = back.position }
        let z: CGFloat = inKennel ? 1.5 : -0.5
        if front.zPosition != z { front.zPosition = z }
    }

    /// Three z's that float up from the head, drift, grow and fade, staggered so there's always one rising.
    func setUpZzz(in root: CALayer) {
        zzzLayer.zPosition = 3
        zzzLayer.isHidden = true
        root.addSublayer(zzzLayer)
        let start = CACurrentMediaTime()
        for (i, (letter, size)) in [("z", 11.0), ("z", 13.0), ("Z", 15.0)].enumerated() {
            let z = CATextLayer()
            z.string = letter
            z.contentsScale = DogSprite.scale
            z.font = NSFont.systemFont(ofSize: size, weight: .heavy)
            z.fontSize = size
            z.alignmentMode = .center
            z.foregroundColor = DogSprite.rgb(0.42, 0.33, 0.55)
            z.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
            z.position = .zero
            z.opacity = 0
            let rise = CAKeyframeAnimation(keyPath: "position")
            rise.values = [CGPoint(x: 0, y: 0), CGPoint(x: 7, y: 10), CGPoint(x: 2, y: 20), CGPoint(x: 10, y: 30)].map { NSValue(point: $0) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.15, 0.7, 1]
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.6; grow.toValue = 1.15
            let group = CAAnimationGroup()
            group.animations = [rise, fade, grow]
            group.duration = 2.7
            group.repeatCount = .infinity
            group.beginTime = start + Double(i) * 0.9
            group.fillMode = .backwards
            z.add(group, forKey: "float")
            zzzLayer.addSublayer(z)
        }
    }

    /// The bed's front rim, drawn over the dog while it lies in that bed so it sits *in* the bed.
    func renderBedRim(_ bed: PetObject, over back: CALayer, size: CGSize, img: CGImage) {
        let rows = 7   // bottom rows of the bed art: the front lip
        let rim = bedRims[bed.id] ?? {
            let l = CALayer()
            l.contents = img.cropping(to: CGRect(x: 0, y: img.height - rows, width: img.width, height: rows))
            l.anchorPoint = .zero; l.magnificationFilter = .nearest
            l.bounds = CGRect(x: 0, y: 0, width: size.width, height: CGFloat(rows) * DogSprite.pointsPerPixel)
            panel.contentView!.layer!.addSublayer(l)
            bedRims[bed.id] = l
            return l
        }()
        if rim.position != back.position { rim.position = back.position }
        let z: CGFloat = brain.pose.inBed == bed.id ? 1.5 : -0.9
        if rim.zPosition != z { rim.zPosition = z }
    }

    func updateHitTest() {
        let m = NSEvent.mouseLocation
        let cursor = CGPoint(x: m.x, y: screenH - m.y)
        let hit = !brain.pose.hidden && !brain.pose.inKennel && dogRect.insetBy(dx: -4, dy: -12).contains(cursor)
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
