import AppKit
import PetCore
import QuartzCore

/// Renders the brain on the desktop layer and feeds it the environment (clock, idle time, cursor, clicks).
/// World coordinates are top-left-origin points on the dog's screen (the one with the menu bar); layers are bottom-left.
@MainActor final class World {
    let panel: DesktopPanel
    let dogLayer = CALayer(), emoteLayer = CATextLayer(), debugLayer = CATextLayer(), ledgeLayer = CALayer()
    var objectLayers: [String: CALayer] = [:]
    var objectArt: [String: String] = [:]   // which picture each object shows (the bowls change)
    var kennelFront: CALayer?
    var swingLayer: CALayer?, bellLayer: CALayer?, holeLayer: CALayer?   // a bird's: its swing, its bell, its shadow in the birdhouse window and door
    var glowLayer: CALayer?, houseEnteredAt: CFTimeInterval?             // the birdhouse window's evening lamp
    var glintLayer: CALayer?, lanternLayer: CALayer?, preyLayer: CALayer?   // an owl's: its eyes glinting in the knothole, its lantern, its prey
    var windows: [Win] = [], windowsAt: CFTimeInterval = 0              // other apps' windows, polled for a bird
    let zzzLayer = CALayer()   // z's that puff up now and then while asleep, animated by Core Animation
    var bedRims: [String: CALayer] = [:]
    var screenFrame: NSRect, floorY: CGFloat, minX: CGFloat, maxX: CGFloat
    var screenW: CGFloat { screenFrame.width }
    var screenH: CGFloat { screenFrame.height }
    var brain: Brain
    var last = CACurrentMediaTime()
    var spriteKey = "", dogOrigin = CGPoint(x: -1, y: -1), emoteText = "", dogTilt: CGFloat = 0
    var lastPose: Pose?, lastRect = CGRect.zero, frameIndex = 0
    var tickTimer: Timer?
    var paused = false, pausedAt: Date?           // the Mac or its screens are asleep, or the session is locked
    var hiddenUntil: Date?                         // "Hide for an hour"
    var occluded = false, occlusionCheckAt: CFTimeInterval = 0
    var nextPuff: CFTimeInterval = 0, blinkUntil: CFTimeInterval = 0, nextBlink: CFTimeInterval = CACurrentMediaTime() + 4
    /// Past this many points into the kennel (from its centre) the dog is fully behind the walls: only its shadow shows in the window.
    static let shadowEdge: CGFloat = 13
    let debug = ProcessInfo.processInfo.environment["LC_DEBUG"] != nil
    /// LC_TOP=1 draws above every window (for recordings): then nothing can cover the dog.
    let onTop = ProcessInfo.processInfo.environment["LC_TOP"] != nil
    /// LC_LOG=1 prints every activity change, jump and cursor reaction (for watching behaviour in tests).
    let log = ProcessInfo.processInfo.environment["LC_LOG"] != nil
    var logged = (started: -1.0, jump: false, attention: "", pose: "")
    var posLoggedAt: CFTimeInterval = 0
    let started = CACurrentMediaTime()
    /// LC_SPEED=10 runs the dog's life 10× faster, for testing behaviour (walking looks fast too).
    let speed = max(0.1, Double(ProcessInfo.processInfo.environment["LC_SPEED"] ?? "") ?? 1)
    /// LC_HOUR=23 pins the clock to that hour (testing: an owl's night, the lantern, a dog's bedtime).
    let pinnedHour = Double(ProcessInfo.processInfo.environment["LC_HOUR"] ?? "")
    /// Local time of day, 0..<24 (or the pinned testing hour).
    var clockHour: Double {
        if let pinnedHour { return pinnedHour }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(now.hour ?? 12) + Double(now.minute ?? 0) / 60
    }
    var onStateChange: (() -> Void)?               // lets the menu refresh (hidden / shown)

    /// The floor (top of the Dock) and the walkable range on a screen, in this screen's top-left coordinates.
    static func geometry(_ screen: NSScreen) -> (frame: NSRect, floor: CGFloat, minX: CGFloat, maxX: CGFloat) {
        let f = screen.frame, v = screen.visibleFrame
        return (f, f.height - (v.minY - f.minY), v.minX - f.minX + 40, v.maxX - f.minX - 40)   // a Dock on either side shrinks the range
    }

    init(screen: NSScreen) {
        let g = Self.geometry(screen)
        screenFrame = g.frame; floorY = g.floor; minX = g.minX; maxX = g.maxX

        // LC_PET=mango picks the pet for this run only (testing); a pet this build doesn't know falls back to Ollie
        let pet = ProcessInfo.processInfo.environment["LC_PET"] ?? UserDefaults.standard.string(forKey: "dog") ?? "ollie"
        DogSprite.dog = (DogSprite.dogs + DogSprite.birds + DogSprite.owls).contains { $0.0 == pet } ? pet : "ollie"
        brain = Self.loadBrain(DogSprite.dog, home: nil, minX: Double(g.minX), maxX: Double(g.maxX))

        panel = DesktopPanel(frame: g.frame, onTop: onTop)
        let view = ClickView(frame: NSRect(origin: .zero, size: g.frame.size))
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
        Self.halo(emoteLayer)
        emoteLayer.bounds = CGRect(x: 0, y: 0, width: 40, height: 20)   // room for an owl's "hoo"
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
            debugLayer.frame = CGRect(x: 12, y: g.frame.height - 300, width: 360, height: 260)
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
        // The Mac sleeping, its screens sleeping or the session locking: stop, and catch up with real time on return.
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.pause() } }
        }
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.wake() } }
        }
        // Resolution changes, the Dock moving, displays coming and going.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        render()
        tick()
        if ProcessInfo.processInfo.environment["LC_DEMO"] == "zoomies" && DogSprite.isBird {   // LC_DEMO=zoomies: just a long joy flight
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(.zoomies) } }
        } else if ProcessInfo.processInfo.environment["LC_DEMO"] == "window" && DogSprite.isBird {   // LC_DEMO=window: off to a window top, to sit there
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.testFlyToWindow() } }
        } else if ProcessInfo.processInfo.environment["LC_DEMO"] != nil && DogSprite.isOwl {   // an owl's tour: a window, a hunt, a hoot, the pinecone, its knothole
            Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.testFlyToWindow() } }
            Timer.scheduledTimer(withTimeInterval: 24, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.testHunt() } }
            for (at, act, target) in [(38.0, Act.carry, "mouse"), (90, .hoot, nil), (100, .play, "pinecone"), (118, .idle, "lantern"), (132, .sleep, "house")] as [(TimeInterval, Act, String?)] {
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(act, target) } }
            }
        } else if ProcessInfo.processInfo.environment["LC_DEMO"] != nil && DogSprite.isBird {   // a bird's tour: onto a window (drag or close it), then its tree
            Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.testFlyToWindow() } }
            for (at, act, target) in [(24.0, Act.swing, nil), (40, .bell, nil), (50, .splash, "birdbath"), (60, .eat, "seeds"), (72, .carry, "rattan"), (100, .sleep, "house")] as [(TimeInterval, Act, String?)] {
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(act, target) } }
            }
        } else if ProcessInfo.processInfo.environment["LC_DEMO"] != nil {   // scripted tour for testing
            if let food = brain.s.objects.first(where: { $0.kind == .foodBowl }) { brain.s.x = food.x + 70 }   // start the tour by the bowls
            let steps: [(TimeInterval, Act, String?)] = [(1, .eat, "food"), (16, .drink, "water"), (26, .sniff, "rope"), (33, .stretch, nil),
                                                         (38, .zoomies, nil), (49, .groom, nil), (63, .greet, nil), (69, .sit, nil), (77, .wander, nil), (85, .play, "ball"), (96, .carry, "rope")]
            for (at, tumble) in [(43.0, true), (46.5, false)] {   // mid-zoomies: one tumble, one trip
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.brain.debugFall(tumble: tumble) } }
            }
            for (at, act, target) in steps {
                Timer.scheduledTimer(withTimeInterval: at, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.test(act, target) } }
            }
        }
    }

    func save() { Store.save(brain.s, dog: DogSprite.dog) }

    /// A dog's saved life, or a newly adopted one (new hidden personality) living in the same home. The home is tidied either way.
    static func loadBrain(_ dog: String, home: [PetObject]?, minX: Double, maxX: Double) -> Brain {
        var b: Brain
        if let saved = Store.load(dog) {
            b = Brain(state: saved.state)
            b.resume(afterOffline: Date().timeIntervalSince(saved.savedAt))
        } else if DogSprite.isBird {   // a new bird arrives at its own tree (an owl at its oak)
            b = Brain(seed: UInt64.random(in: 1...UInt64.max), species: DogSprite.isOwl ? .owl : .bird)
            b.s.objects = DogSprite.isOwl ? owlHome(maxX: maxX) : birdHome(maxX: maxX)
            b.s.x = maxX - 160
        } else {
            b = Brain(seed: UInt64.random(in: 1...UInt64.max))
            b.s.objects = home ?? defaultObjects(width: maxX + 40)
            b.s.x = minX + 120
        }
        tidy(&b.s.objects, minX: minX, maxX: maxX)
        return b
    }

    /// Keeps the home inside the floor: a dog's tidied round its kennel, a bird's tree pinned at the right end.
    static func tidy(_ objects: inout [PetObject], minX: Double, maxX: Double) {
        if DogSprite.isOwl { repairOwlHome(&objects, maxX: maxX); return }
        if DogSprite.isBird { repairBirdHome(&objects, maxX: maxX); return }
        repairHome(&objects, minX: minX, maxX: maxX) { Double(ObjectSprite.image(id: $0.id, kind: $0.kind.rawValue).1.width) / 2 }
    }

    /// Swap in another dog: this one's life is saved, the other picks up where it left off (or arrives new, in the same home).
    func switchDog(to dog: String) {
        guard dog != DogSprite.dog else { return }
        save()
        let wasBird = DogSprite.isBird, wasOwl = DogSprite.isOwl
        let home = brain.s.objects
        DogSprite.dog = dog
        UserDefaults.standard.set(dog, forKey: "dog")
        brain = Self.loadBrain(dog, home: wasBird == DogSprite.isBird && wasOwl == DogSprite.isOwl ? home : nil, minX: Double(minX), maxX: Double(maxX))   // a new dog moves into the old dog's home
        spriteKey = ""; dogOrigin = CGPoint(x: -1, y: -1); dogTilt = 0
        dogLayer.setAffineTransform(.identity)
        dogLayer.bounds = CGRect(origin: .zero, size: DogSprite.size)
        if wasBird != DogSprite.isBird || wasOwl != DogSprite.isOwl {   // another species: rebuild the home's layers
            for l in Array(objectLayers.values) + Array(bedRims.values) + [kennelFront, swingLayer, bellLayer, holeLayer, glowLayer, glintLayer, lanternLayer, preyLayer].compactMap({ $0 }) { l.removeFromSuperlayer() }
            objectLayers = [:]; objectArt = [:]; bedRims = [:]; kennelFront = nil; swingLayer = nil; bellLayer = nil; holeLayer = nil; glowLayer = nil; glintLayer = nil; lanternLayer = nil; preyLayer = nil
        }
        render()
    }

    // MARK: - The real Mac: sleep, screens, hiding

    func pause() {
        guard !paused else { return }
        paused = true; pausedAt = Date()
        tickTimer?.invalidate(); tickTimer = nil
        save()
    }

    func wake() {
        guard paused else { return }
        paused = false
        let gap = Date().timeIntervalSince(pausedAt ?? Date())   // wall clock: the media clock stops while the Mac sleeps
        last = CACurrentMediaTime()
        let env = environment()
        brain.advance(by: gap * speed, env: env)
        if gap > 30 * 60 { brain.welcomeBack(env: environment()) }   // you're back after a while: a hello where it is
        render()
        tick()
    }

    /// Re-reads the screen (resolution, Dock position, displays) and keeps the home and the dog inside it.
    func screenChanged() {
        guard let screen = NSScreen.screens.first else { return }
        let g = Self.geometry(screen)
        if g.frame.width != screenW, screenW > 0 {   // keep everything in proportion across a resolution change
            let k = Double(g.frame.width / screenW)
            for i in brain.s.objects.indices { brain.s.objects[i].x *= k }
            brain.s.x *= k
        }
        screenFrame = g.frame; floorY = g.floor; minX = g.minX; maxX = g.maxX
        panel.setFrame(g.frame, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: g.frame.size)
        Self.tidy(&brain.s.objects, minX: Double(minX), maxX: Double(maxX))
        brain.s.x = min(max(brain.s.x, Double(minX)), Double(maxX))
        dogOrigin = CGPoint(x: -1, y: -1)
        render()
    }

    var isHidden: Bool { hiddenUntil != nil }

    /// Out of sight for a while (screen sharing, a demo): the dog keeps living, just not on screen.
    func hide(for secs: TimeInterval) {
        hiddenUntil = Date().addingTimeInterval(secs)
        panel.orderOut(nil)
        onStateChange?()
    }

    func showNow() {
        hiddenUntil = nil
        panel.orderFrontRegardless()
        spriteKey = ""; dogOrigin = CGPoint(x: -1, y: -1)
        render()
        onStateChange?()
    }

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
        let extra = [p.sleepPos.map { "sleep:\($0.rawValue)" }, p.inBed.map { _ in "in bed" }, p.play?.rawValue, a.phase.map { "phase:\($0)" }].compactMap { $0 }.joined(separator: " ")
        if extra != logged.pose { logged.pose = extra; if !extra.isEmpty { line.append("[\(extra)]") } }
        if (s.jumpAt != nil) != logged.jump { logged.jump = s.jumpAt != nil; if logged.jump { line.append("JUMP") } }
        let att = s.attention?.rawValue ?? ""
        if att != logged.attention { logged.attention = att; if !att.isEmpty { line.append("cursor:\(att)") } }
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

    /// Debug menu: get it running, then trip it up.
    func testFall(tumble: Bool) {
        test(.zoomies)
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.brain.debugFall(tumble: tumble) } }
    }

    /// The cursor in this screen's top-left coordinates (NSEvent gives global, bottom-left coordinates).
    var cursor: CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x - screenFrame.minX, y: screenFrame.maxY - m.y)
    }

    lazy var kennelWidth = Double(ObjectSprite.image(id: "kennel", kind: "kennel").1.width)

    func environment() -> Environment {
        let c = cursor
        // kCGAnyInputEventType: seconds since any keyboard/mouse input. Needs no permission.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let onScreen = c.x >= 0 && c.x <= screenW
        if DogSprite.isBird { return birdEnvironment(cursor: c, idle: idle, hour: clockHour) }
        return Environment(minX: Double(minX), maxX: Double(maxX),
                           hour: clockHour,
                           userIdle: idle,
                           cursorX: onScreen && abs(c.y - floorY) < 160 ? Double(c.x) : nil, // only notices a cursor near its floor
                           systemBusy: systemBusy(),
                           reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                           kennelDoorOutside: kennelWidth / 2 + 38.5,   // just clear of the cabin's open end (dog 72 pt wide)
                           kennelInside: -kennelWidth * 0.16 ... 0)
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
        tickTimer = nil
        guard !paused else { return }
        let now = CACurrentMediaTime()
        // macOS delays timers (App Nap, coalescing): catch up on the whole gap so no time is lost.
        let gap = now - last
        last = now
        if debug && gap > 1.5 { NSLog("LittleCompanion: tick gap %.1fs", gap) }
        let env = environment()
        brain.advance(by: gap * speed, env: env)
        if log { logChanges() }
        if log && DogSprite.isBird && now >= posLoggedAt + 0.5 {   // LC_LOG: where a bird is, twice a second (for checking recordings)
            posLoggedAt = now
            let p = brain.pose
            print(String(format: "pos %.2f %.0f %.0f", now - started, p.x, p.y ?? Double(floorY))); fflush(stdout)
        }
        if let until = hiddenUntil, Date() >= until { showNow() }
        let p = brain.pose
        let moving = p.anim == .walk || p.anim == .run || p.anim == .zoom
        if moving, !onTop, now >= occlusionCheckAt {   // under a window nobody can see it: keep living, skip the drawing
            occlusionCheckAt = now + 1
            let r = lastRect.insetBy(dx: 2, dy: 2)
            occluded = otherWindowRects().contains { $0.contains(r) }
        } else if !moving { occluded = false }
        if now >= nextBlink, !p.wag, p.anim == .stand || p.anim == .sit { blinkUntil = now + 0.13; nextBlink = now + .random(in: 3.5...8) }
        if p.anim == .sleep && !p.hidden { puffZzzIfDue(now: now, env: env) }
        if !isHidden && !occluded { render(p) }
        var interval: TimeInterval = switch p.anim {
        case .walk, .run, .zoom, .play, .hop: 1.0 / 20
        case .eat, .drink, .sniff: 1.0 / 12
        case .sleep: 1.0
        default: 0.2 // brain at 5 Hz; nothing redraws unless something changed
        }
        if p.wag || p.groom != nil { interval = 1.0 / 14 }   // two-frame loops at their own pace, without dropped frames
        if brain.s.jumpAt != nil { interval = 1.0 / 30 }    // smooth arc
        if now < blinkUntil { interval = min(interval, blinkUntil - now + 0.01) }
        if p.hidden { interval = 1.0 }                      // inside the kennel: nothing to draw
        if DogSprite.isBird { interval = birdInterval(p, else: interval) }
        if p.twitch { interval = 1.0 / 8 }                  // dreaming: paddling paws
        if isHidden || occluded { interval = 1.0 }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { interval = max(interval, 1.0 / 10) }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    // MARK: - Rendering

    func dogRect(_ p: Pose) -> CGRect {
        let t = CACurrentMediaTime()
        var lift: CGFloat = 0
        if p.anim == .hop { lift = abs(sin(t * 7)) * 18 }
        if p.twitch && p.anim != .sleep { lift = 2 }
        if p.inBed != nil { lift += 3 * DogSprite.pointsPerPixel }   // up on the cushion, the rim covering its lower body
        if let j = p.jump { lift += 4 * j * (1 - j) * p.jumpHeight }   // a true parabola, peak at the middle
        if p.anim == .run || p.anim == .zoom { lift += Int(p.x / 16) % 2 == 0 ? 0 : 2 }   // gallop bounce
        let s = DogSprite.size
        let footGap = DogSprite.footRows * DogSprite.pointsPerPixel
        return CGRect(x: p.x - s.width / 2, y: floorY - s.height + footGap - lift, width: s.width, height: s.height)
    }

    /// Which frame of the sheet shows each animation.
    func spriteFrame(_ p: Pose, time t: CFTimeInterval) -> DogSprite.Frame {
        switch p.fall {
        case .trip: return .trip
        case .roll: return .tumbleRoll
        case .sprawl: return .tumbleSprawl
        case .up: return .jumpCrouch
        case .sheepish: return .look   // glances back at where it fell, as if nothing happened
        case nil: break
        }
        if p.crouch { return .jumpCrouch }
        if let j = p.jump { return j < 0.5 ? .jumpUp : .jumpDown }   // thrusting off, then reaching for the floor
        switch p.anim {
        case .walk: return Int(p.x / 10) % 2 == 0 ? .walkA : .walkB
        case .run: return Int(p.x / 16) % 2 == 0 ? .runA : .runB
        case .zoom: return Int(p.x / 20) % 2 == 0 ? .zoomA : .zoomB
        case .sit:
            switch p.groom {
            case .lick: return Int(t * 3) % 2 == 0 ? .lickA : .lickB   // steady licks
            case .scratch: return t.truncatingRemainder(dividingBy: 1.6) < 1 && Int(t * 12) % 2 == 0 ? .scratchB : .scratchA   // fast kicks in bursts
            case nil: return p.front ? .sitFront : p.back ? .sitBack : .sit
            }
        case .sleep:
            let dreaming = p.twitch && Int(t * 6) % 2 == 0   // each position has its own dream twitch
            switch p.sleepPos {
            case .curl: return dreaming ? .sleepCurlTwitch : .sleepCurl      // ear flicks
            case .side: return dreaming ? .sleepSideTwitch : .sleepSide      // legs paddle
            case .belly: return dreaming ? .sleepBellyTwitch : .sleepBelly   // paws kick the air
            default: return dreaming ? .sleepTwitch : .sleep                  // front paw kicks
            }
        case .play:
            if p.play == .shake { return Int(t * 6) % 2 == 0 ? .shakeA : .shakeB }   // shaking the toy in its mouth
            return p.swipe ? .pawUp : .stand                                            // paw up to bat the ball
        case .eat: return Int(t * 2.4 * p.pace) % 2 == 0 ? .eatA : .eatB                 // chewing, faster for gulpers
        case .drink: return Int(t * 6 * p.pace) % 2 == 0 ? .drinkA : .drinkB              // lapping
        case .sniff: return t.truncatingRemainder(dividingBy: 1.8) < 0.9 && Int(t * 8) % 2 == 0 ? .sniffB : .sniffA   // sniff-sniff, pause
        case .stretch: return p.stretchBack ? .stretchB : .bow                            // front legs, then the hind legs
        case .stand, .hop:
            if p.attention == .head, let lx = p.lookX, (lx - p.x) * p.facing < 0 { return .look }   // glancing back at the cursor
            return .stand
        }
    }

    func render() { render(brain.pose) }

    func render(_ p: Pose) {
        if DogSprite.isBird { renderBird(p); return }
        let r = dogRect(p)
        lastPose = p; lastRect = r
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
            index = DogSprite.toyFrame(DogSprite.toyArt(toy), pose) ?? index
        } else if p.wag, let w = frame.wagging(t) {
            index = w.rawValue
        } else if t < blinkUntil, let b = frame.blinking {
            index = b.rawValue
        }
        frameIndex = index
        let origin = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())
        let rawEmote = p.emote ?? ""

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dogLayer.isHidden != p.hidden { dogLayer.isHidden = p.hidden; emoteLayer.isHidden = p.hidden }
        if origin != dogOrigin { dogOrigin = origin; dogLayer.position = origin }
        let tilt = p.fall == .trip ? CGFloat(-0.3 * p.facing) : p.jump.map { CGFloat((0.5 - $0) * 0.55 * p.facing) } ?? 0   // nose up rising, nose down falling or tripping
        if tilt != dogTilt {
            dogTilt = tilt
            let c = CGPoint(x: dogLayer.bounds.midX, y: dogLayer.bounds.midY)   // about the middle, not the anchor corner
            dogLayer.setAffineTransform(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: tilt).translatedBy(x: -c.x, y: -c.y))
        }
        let kennelX = brain.s.objects.first { $0.kind == .kennel }.map { CGFloat($0.x) }
        let shadow = p.inKennel && kennelX.map { CGFloat(p.x) < $0 + Self.shadowEdge } == true
        let key = "\(index)\(p.facing)" + (shadow ? "s" : "")
        if key != spriteKey {
            spriteKey = key
            dogLayer.contents = shadow ? DogSprite.silhouette(index, facing: CGFloat(p.facing)) : DogSprite.image(index, facing: CGFloat(p.facing))
        }
        let snoozing = rawEmote == "z"   // asleep: puffs of z's instead of the static emote
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
        renderObjects(p, dog: r)
        CATransaction.commit()
        updateHitTest()
    }

    func renderObjects(_ p: Pose, dog: CGRect) {
        let root = panel.contentView!.layer!
        let ids = Set(brain.s.objects.map(\.id))
        for (id, l) in objectLayers where !ids.contains(id) { l.removeFromSuperlayer(); objectLayers[id] = nil }
        let mouthRow: CGFloat = frameIndex == DogSprite.Frame.shakeA.rawValue ? 13 : frameIndex == DogSprite.Frame.shakeB.rawValue ? 21 : 17
        let food = brain.foodLeft
        let lapping = p.anim == .drink && Int(CACurrentMediaTime() * 3 * p.pace) % 2 == 0
        for o in brain.s.objects {
            // the bowls show what's going on: food going down as it eats (refilled a little later), ripples as it drinks
            let art = o.kind == .foodBowl ? (food > 0.66 ? "foodBowl" : food > 0.2 ? "foodBowlHalf" : "foodBowlEmpty")
                    : o.kind == .waterBowl && lapping ? "waterBowlRipple"
                    : o.kind == .ball ? Self.ballArt(o.x) : o.kind.rawValue
            let (img, size) = ObjectSprite.image(id: o.id, kind: art)
            let l = objectLayers[o.id] ?? {
                let l = CALayer()
                l.contents = img; l.anchorPoint = .zero
                l.bounds = CGRect(origin: .zero, size: size)
                l.magnificationFilter = .nearest
                l.zPosition = o.kind == .rug || o.kind == .bed || o.kind == .kennel ? -1 : 0
                root.addSublayer(l); objectLayers[o.id] = l
                return l
            }()
            if objectArt[o.id] != art { objectArt[o.id] = art; l.contents = img }
            let held = o.id == p.carrying
            let baked = held && p.holding != nil   // drawn into the dog's frame instead
            if l.isHidden != baked { l.isHidden = baked }
            let beak = dog.minY + (DogSprite.isOwl ? 17 : 15) * DogSprite.pointsPerPixel + size.height * 0.5   // a bird carries its toy in its beak
            var bottom = held ? (DogSprite.isBird ? beak : dog.minY + mouthRow * DogSprite.pointsPerPixel) : floorY // carried toys ride in its mouth
            if let t = brain.s.toss, t.id == o.id { bottom = CGFloat(t.y(brain.s.time - t.at, floorY: Double(floorY))) + size.height * 0.5 }   // flung: falling
            let sink: CGFloat = o.kind == .kennel ? DogSprite.footRows * DogSprite.pointsPerPixel : 0   // kennel walls reach the dog's lowest outline row
            let ahead: CGFloat = held && DogSprite.isBird ? CGFloat(p.facing) * (DogSprite.isOwl ? 5 : 9) * DogSprite.pointsPerPixel : 0   // at the tip of its beak
            let pos = CGPoint(x: (CGFloat(o.x) + ahead - size.width / 2).rounded(), y: (screenH - bottom - sink).rounded())
            if l.position != pos { l.position = pos }
            let z: CGFloat = held ? 2 : (o.kind == .rug || o.kind == .bed || o.kind == .kennel ? -1 : 0)
            if l.zPosition != z { l.zPosition = z }
            if o.kind == .kennel { renderKennelFront(over: l, inKennel: p.inKennel) }
            if o.kind == .bed { renderBedRim(o, over: l, size: size, img: img, inBed: p.inBed == o.id) }
        }
    }

    /// A ball turns a quarter for every quarter of its circumference it rolls, so it rolls rather than slides.
    static func ballArt(_ x: Double) -> String {
        let quarter = Double.pi * 8 * Double(DogSprite.pointsPerPixel) / 4   // the ball is 8 art pixels across
        let n = Int((x / quarter).rounded(.down)) & 3
        return n == 0 ? "ball" : "ball\(n)"
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

    /// A light halo so purple text reads on any wallpaper, dark ones included.
    static func halo(_ l: CALayer) {
        l.shadowColor = CGColor(gray: 1, alpha: 1); l.shadowOpacity = 0.9; l.shadowRadius = 1.6; l.shadowOffset = .zero
    }

    /// Three z's that float up from the head, drift, grow and fade: added as one puff at a time (see `puffZzz`).
    func setUpZzz(in root: CALayer) {
        zzzLayer.zPosition = 3
        zzzLayer.isHidden = true
        root.addSublayer(zzzLayer)
        for (letter, size) in [("z", 11.0), ("z", 13.0), ("Z", 15.0)] {
            let z = CATextLayer()
            z.string = letter
            z.contentsScale = DogSprite.scale
            z.font = NSFont.systemFont(ofSize: size, weight: .heavy)
            z.fontSize = size
            z.alignmentMode = .center
            z.foregroundColor = DogSprite.rgb(0.42, 0.33, 0.55)
            Self.halo(z)
            z.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
            z.position = .zero
            z.opacity = 0
            zzzLayer.addSublayer(z)
        }
    }

    /// Every 15–30 s while it sleeps, one puff of z's (an endless animation would keep the window server busy all night).
    /// None while you're away; with Reduce Motion, a single still z.
    func puffZzzIfDue(now: CFTimeInterval, env: Environment) {
        let layers = zzzLayer.sublayers ?? []
        if env.reduceMotion {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (i, z) in layers.enumerated() { z.removeAllAnimations(); z.opacity = i == 1 ? 1 : 0; z.position = CGPoint(x: 6, y: 12) }
            CATransaction.commit()
            return
        }
        guard now >= nextPuff, env.userIdle < Brain.awayAfter else { return }
        nextPuff = now + .random(in: 15...30)
        for (i, z) in layers.enumerated() {
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
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.9
            group.fillMode = .backwards
            z.add(group, forKey: "float")   // plays once and is removed
        }
    }

    /// The bed's front rim, drawn over the dog while it lies in that bed so it sits *in* the bed.
    func renderBedRim(_ bed: PetObject, over back: CALayer, size: CGSize, img: CGImage, inBed: Bool) {
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
        let z: CGFloat = inBed ? 1.5 : -0.9
        if rim.zPosition != z { rim.zPosition = z }
    }

    func updateHitTest() {
        let p = lastPose
        let hit = !isHidden && p.map { !$0.hidden && !$0.inKennel } == true && lastRect.insetBy(dx: -4, dy: -12).contains(cursor)
        if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
    }

    func drawDebug() {
        let s = brain.s, a = s.activity, n = s.needs, p = s.personality
        let prefs = s.objects.map { String(format: "%@ %+.2f", $0.id, brain.pref($0)) }.joined(separator: "  ")
        debugLayer.string = """
         \(a.act.rawValue)\(a.target.map { " → " + $0 } ?? "")\(a.destX != nil ? " (walking)" : String(format: " %.0fs left", a.remaining))
         needs  hunger \(f(n.hunger)) thirst \(f(n.thirst)) tired \(f(n.tiredness)) bored \(f(n.boredom))
         traits play \(f(p.playfulness)) lazy \(f(p.laziness)) affect \(f(p.affection)) clumsy \(f(p.clumsy))
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
