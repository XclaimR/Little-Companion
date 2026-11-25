import AppKit
import PetCore
import QuartzCore

/// A bird on the desktop: its environment (other apps' windows to perch on), its frames, its tree's swing and bell,
/// and its shadow in the birdhouse doorway. The bird stays on the desktop layer, behind every window, like the dogs.
extension World {
    var pp: CGFloat { DogSprite.pointsPerPixel }
    var treeX: CGFloat { CGFloat(brain.s.objects.first { $0.kind == .tree || $0.kind == .oak }?.x ?? Double(maxX)) }

    /// Windows are polled ~15 times a second while it's on (or flying to) a window, once a second otherwise. No permission needed.
    func birdEnvironment(cursor c: CGPoint, idle: Double, hour: Double) -> Environment {
        let now = CACurrentMediaTime()
        let s = brain.s
        let onWindow = s.perch?.hasPrefix("w:") == true || s.flight?.to.hasPrefix("w:") == true
        if now - windowsAt >= (onWindow ? 1.0 / 15 : 1) {
            windowsAt = now
            let screen = CGRect(origin: .zero, size: screenFrame.size)   // CG window bounds are relative to the menu-bar screen, where it lives
            let fresh = otherWindows().filter { screen.intersects($0.rect) }
            // A full-screen app (a window over the whole screen, Dock area too) is on its own Space, where the bird isn't:
            // it keeps its picture of your desktop's windows as they were, so nothing it's doing there is disturbed.
            if !fresh.contains(where: { $0.rect.width >= screenW - 1 && $0.rect.maxY >= screenH - 1 }) {
                windows = fresh.map { Win(id: $0.id, box: Box(x: $0.rect.minX, y: $0.rect.minY, w: $0.rect.width, h: $0.rect.height)) }
            }
        }
        var e = Environment(minX: Double(minX), maxX: Double(maxX), hour: hour, userIdle: idle, cursorX: nil,
                            systemBusy: systemBusy(), reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if c.x >= 0 && c.x <= screenW && c.y >= 0 && c.y <= screenH { e.cursorX = Double(c.x); e.cursorY = Double(c.y) }   // anywhere on its screen
        e.floorY = Double(floorY)
        e.topY = NSScreen.screens.first.map { Double($0.frame.maxY - $0.visibleFrame.maxY) } ?? 25
        e.windows = windows
        if let p = s.perch, p.hasPrefix("w:"), let id = Int(p.dropFirst(2)), !windows.contains(where: { $0.id == id }) {
            e.windowClosed = !windowExists(id)   // gone for good, or just minimised / on another Space
        }
        return e
    }

    func birdInterval(_ p: Pose, else base: TimeInterval) -> TimeInterval {
        if p.flight != nil || p.jump != nil || brain.s.toss != nil { return 1.0 / 30 }   // smooth flight, a falling toy
        if brain.s.prey != nil { return 1.0 / 20 }                                      // a beetle or moth on the move
        if p.wobble || [.swing, .bell, .splash].contains(p.act) || brain.s.perch?.hasPrefix("w:") == true { return 1.0 / 15 }   // riding a window that may move
        if p.anim == .walk || [.eat, .drink, .peck, .groom].contains(p.act) { return 1.0 / 10 }
        if p.inKennel { return 1.0 }
        return base
    }

    func birdFrame(_ p: Pose, _ t: Double) -> DogSprite.Bird {
        if let f = p.flight {
            switch f {
            case .takeoff: return .takeoff
            case .flap: return [DogSprite.Bird.flapUp, .flapMid, .flapDown, .flapMid][Int(t * 12) % 4]
            case .glide: return .glide
            case .flare: return .flare
            case .fall: return Int(t * 7) % 2 == 0 ? .fallA : .fallB        // tumbling, wings flailing
            case .recover: return Int(t * 14) % 2 == 0 ? .recover : .recoverB   // hard flaps, same posture
            }
        }
        if p.inKennel { return p.anim == .sleep ? (p.twitch && Int(t * 6) % 2 == 0 ? .dream : .sleep) : .nap }
        if p.wobble { return .wobble }
        if p.jump != nil { return .hopB }
        if p.anim == .walk { return .hopA }
        switch p.act {
        case .sleep?: return p.twitch && Int(t * 6) % 2 == 0 ? .dream : .nap   // dozing, fluffed up on a branch
        case .eat?: return Int(t * 2.4) % 2 == 0 ? .eatA : .eatB
        case .drink?: return Int(t * 4) % 2 == 0 ? .eatA : .eatB
        case .peck?: return t.truncatingRemainder(dividingBy: 2) < 1 && Int(t * 6) % 2 == 0 ? .peckA : .peckB
        case .splash?: return Int(t * 5) % 2 == 0 ? .splashA : .splashB
        case .groom?:   // in a bout: nibbling in an uneven rhythm; between bouts it looks round
            let k = Int(t * 3)
            if p.preening { return ((k &* 2654435761) >> 13) & 1 == 0 ? .preenA : .preenB }
            return [DogSprite.Bird.idle, .lookBack, .idle, .lookUp][((k / 4) &* 40503 >> 7) & 3]
        case .stretch?: return .stretch
        case .swing?: return .swing
        case .bell?: return Int(t * 3) % 2 == 0 ? .bellA : .bellB
        case .react?: return .startled
        case .greet?: return .front
        case .carry? where p.since != nil: return .tilt   // dropped its ball: head on one side, watching it bounce
        default: break
        }
        if p.front { return .front }
        if p.attention == .head, let lx = p.lookX { return (lx - p.x) * p.facing < 0 ? .lookBack : .tilt }   // a glance and a head tilt
        if p.act == .lookAround { return [DogSprite.Bird.lookUp, .idle, .lookBack][Int(t / 1.5) % 3] }
        let k = t.truncatingRemainder(dividingBy: 9)   // perched: a head-bob now and then, a look up
        if k < 0.8 { return Int(t * 5) % 2 == 0 ? .bobA : .bobB }
        if k > 7.5 && k < 8.5 { return .lookUp }
        return p.crest ? .idleCrest : .idle
    }

    func renderBird(_ p: Pose) {
        let t = CACurrentMediaTime()
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let swinging = p.act == .swing && p.flight == nil && brain.s.perch == "swing"
        let ringing = p.act == .bell && p.flight == nil && brain.s.perch == "bell"
        let swingA: CGFloat = swinging && !calm ? CGFloat(sin(t * 2.4) * 0.3) : 0
        var feetX = CGFloat(p.x), feetY = CGFloat(p.y ?? Double(floorY))
        let rope = 31 * pp   // pivot (under branch 0) to the seat
        if swinging { feetX += rope * sin(swingA); feetY -= rope * (1 - cos(swingA)) }
        let lift = p.jump.map { CGFloat(4 * $0 * (1 - $0) * p.jumpHeight) } ?? 0
        let size = DogSprite.size
        let r = CGRect(x: feetX - size.width / 2, y: feetY - size.height + DogSprite.footRows * pp - lift, width: size.width, height: size.height)
        lastPose = p; lastRect = r
        if DogSprite.isOwl {
            var frame = owlFrame(p, t)
            if t < blinkUntil { frame = frame == .idle ? .blink : frame == .front ? .slowBlink : frame }
            frameIndex = frame.rawValue
        } else {
            var frame = birdFrame(p, t)
            if t < blinkUntil { frame = frame == .idle ? .blink : frame == .front ? .frontBlink : frame }
            frameIndex = frame.rawValue
        }
        let origin = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dogLayer.isHidden != p.inKennel { dogLayer.isHidden = p.inKennel }
        if origin != dogOrigin { dogOrigin = origin; dogLayer.position = origin }
        let key = "\(frameIndex)\(p.facing)"
        if key != spriteKey { spriteKey = key; dogLayer.contents = DogSprite.image(frameIndex, facing: CGFloat(p.facing)) }
        if DogSprite.isOwl { renderKnothole(p, t: t); renderPrey(t: t) } else {
            renderBirdhouseShadow(p)
            renderSwingAndBell(swing: swingA, bell: ringing && !calm ? CGFloat(sin(t * 16) * 0.35) : 0)
        }

        let rawEmote = p.emote ?? ""
        let snoozing = rawEmote == "z"
        if zzzLayer.isHidden == snoozing { zzzLayer.isHidden = !snoozing }
        if snoozing {   // from the birdhouse doorway, or just above its head on a branch
            let door = DogSprite.isOwl ? Oak.entrance : Tree.entrance
            zzzLayer.position = p.inKennel ? CGPoint(x: treeX + CGFloat(door.dx), y: screenH - (floorY - CGFloat(door.h) - 6 * pp)) : CGPoint(x: r.midX + CGFloat(p.facing) * 6, y: screenH - (r.minY + 8 * pp))
        }
        let emote = snoozing || p.inKennel ? "" : rawEmote
        if emote != emoteText { emoteText = emote; emoteLayer.string = emote }
        if !emote.isEmpty { emoteLayer.position = CGPoint(x: r.midX + CGFloat(p.facing) * 8, y: screenH - r.minY + 10) }
        renderObjects(p, dog: r)
        if DogSprite.isOwl, let m = objectLayers["mouse"] {   // pounced: the mouse is under its wings (drawn into its frame) until it's eaten
            let caught = p.act == .hunt && p.toy && (3.2..<6).contains(p.since ?? 0)   // under its wings, then let go
            if m.isHidden != caught { m.isHidden = caught }
        }
        CATransaction.commit()
        updateHitTest()
    }

    /// The beetle or moth a hungry owl is after: two frames (legs, wings), facing the way it's going.
    func renderPrey(t: Double) {
        let l = preyLayer ?? {
            let l = CALayer(); l.magnificationFilter = .nearest; l.zPosition = 0.6; l.anchorPoint = CGPoint(x: 0.5, y: 0)
            panel.contentView!.layer!.addSublayer(l); preyLayer = l
            return l
        }()
        guard let prey = brain.s.prey, !prey.caught else { if !l.isHidden { l.isHidden = true }; return }
        if l.isHidden { l.isHidden = false }
        let art = prey.kind == .moth ? (Int(t * 10) % 2 == 0 ? "mothA" : "mothB") : (Int(t * 8) % 2 == 0 ? "beetleA" : "beetleB")
        let (img, size) = ObjectSprite.image(id: art, kind: art)
        if l.bounds.size != size { l.bounds = CGRect(origin: .zero, size: size) }
        if l.contents as! CGImage? !== img { l.contents = img }
        l.position = CGPoint(x: CGFloat(prey.x).rounded(), y: (screenH - floorY + CGFloat(prey.h)).rounded())
        l.setAffineTransform(CGAffineTransform(scaleX: prey.vx < 0 ? -1 : 1, y: 1))   // the art faces right
    }

    /// An owl's frame. Most of the night it sits and watches, its head (not its body) following things.
    func owlFrame(_ p: Pose, _ t: Double) -> DogSprite.Owl {
        if let f = p.flight {
            switch f {
            case .takeoff: return .takeoff
            case .flap: return [DogSprite.Owl.flapUp, .flapMid, .flapDown, .flapMid][Int(t * 8) % 4]   // slow, deep wingbeats
            case .glide: return .glide
            case .flare: return .flare
            case .fall: return Int(t * 7) % 2 == 0 ? .fallA : .fallB
            case .recover: return Int(t * 10) % 2 == 0 ? .recover : .flapDown
            }
        }
        if p.inKennel { return p.anim == .sleep ? .sleep : .fluffed }
        if p.act == .hunt, let s = p.since {   // stare, pounce, cloak its wings over it; the toy is let go, a catch is gulped
            if !p.toy && !p.caught { return p.anim == .walk ? (Int(p.x / 6) % 2 == 0 ? .walkA : .walkB) : .alert }   // watching it, stalking after it
            if s < 3 { return .alert }
            if s < 3.4 { return .pounce }
            if p.toy { return s < 6 ? .mantle : .front }
            return s < 5 ? .mantleBare : s < 6.2 ? .gulp : .idle
        }
        if p.act == .carry, let s = p.since, s < 0.45 { return .pounce }   // flinging the mouse off the branch
        if p.wobble { return .flare }
        if p.jump != nil { return p.act == .play ? .pounce : .walkB }   // a quick bat at the pinecone
        if p.anim == .walk { return Int(p.x / 6) % 2 == 0 ? .walkA : .walkB }   // a waddle
        switch p.act {
        case .sleep?: return p.twitch && Int(t * 3) % 2 == 0 ? .dream : .dayDoze   // asleep on one leg
        case .drink?: return Int(t * 2) % 2 == 0 ? .eatA : .eatB
        case .splash?: return Int(t * 3) % 2 == 0 ? .fluffed : .preen
        case .groom?:   // bouts of preening, then a look round
            let k = Int(t * 2)
            if p.preening { return ((k &* 2654435761) >> 13) & 1 == 0 ? .preen : .idle }
            return [DogSprite.Owl.idle, .swivelBack, .idle, .tiltL][((k / 3) &* 40503 >> 7) & 3]
        case .stretch?: return .stretch
        case .play?: return .idle   // side-on, watching the pinecone (no front-facing frames mid-game: they read as a flip)
        case .hoot?: let k = t.truncatingRemainder(dividingBy: 2.4); return k < 0.5 ? .hootA : k < 1.2 ? .hootB : k < 1.5 ? .hootA : .idle
        case .react?: return .startled
        case .greet?: return .front
        default: break
        }
        if p.front { return t.truncatingRemainder(dividingBy: 3) < 0.7 ? .slowBlink : .front }   // a slow blink at you
        if p.attention == .head, let lx = p.lookX { return (lx - p.x) * p.facing < 0 ? .swivelBack : (lx < p.x ? .tiltL : .tiltR) }
        if p.act == .lookAround { return [DogSprite.Owl.idle, .swivelBack, .front, .idle][Int(t / 1.5) % 4] }
        // perched: never quite still — a look over its shoulder, a slow blink, a ruffle, every couple of seconds
        let k = (t + p.x / 37).truncatingRemainder(dividingBy: 8)
        return k < 2 ? .idle : k < 3.2 ? .swivelBack : k < 5 ? .idle : k < 5.6 ? .slowBlink : k < 7 ? .idle : .fluffed
    }

    /// The owl's knothole: while it's home, its eyes glint in the dark (now and then, while it sleeps by day, it peeks).
    /// The lantern on the right branch is lit from dusk to dawn.
    func renderKnothole(_ p: Pose, t: Double) {
        let root = panel.contentView!.layer!
        let glint = glintLayer ?? {
            let l = CALayer(); l.zPosition = 0.5
            let colour: CGColor = switch DogSprite.dog { case "moth": DogSprite.rgb(1, 1, 1); case "bramble": DogSprite.rgb(0.95, 0.48, 0.07); default: DogSprite.rgb(0.95, 0.76, 0.19) }
            for dx in [-2.0, 2.0] {
                let e = CALayer(); e.backgroundColor = colour
                e.frame = CGRect(x: CGFloat(dx + 1) * pp, y: 0, width: pp, height: pp)
                l.addSublayer(e)
            }
            l.bounds = CGRect(x: 0, y: 0, width: 4 * pp, height: pp); l.anchorPoint = .zero
            root.addSublayer(l); glintLayer = l
            return l
        }()
        let peek = p.anim != .sleep || Int(t) % 23 < 2
        let show = p.inKennel && peek
        if glint.isHidden == show { glint.isHidden = !show }
        let gp = CGPoint(x: (treeX + CGFloat(Oak.entrance.dx) - 2 * pp).rounded(), y: (screenH - floorY + CGFloat(Oak.entrance.h) - pp).rounded())
        if glint.position != gp { glint.position = gp }
        let lit = Oak.lit(clockHour)
        let lantern = lanternLayer ?? {
            let l = CALayer(); l.magnificationFilter = .nearest; l.zPosition = 0.5; l.anchorPoint = CGPoint(x: 0.5, y: 1)
            root.addSublayer(l); lanternLayer = l
            return l
        }()
        let (img, size) = ObjectSprite.image(id: lit ? "lanternLit" : "lantern", kind: lit ? "lanternLit" : "lantern")
        if lantern.bounds.size != size { lantern.bounds = CGRect(origin: .zero, size: size) }
        if lantern.contents as! CGImage? !== img { lantern.contents = img }
        let lp = CGPoint(x: (treeX + CGFloat(Oak.lantern.dx)).rounded(), y: (screenH - floorY + CGFloat(Oak.lantern.top)).rounded())
        if lantern.position != lp { lantern.position = lp }
    }

    /// In the birdhouse: its soft shadow shows through the curtained window and the round door (the rest of it is
    /// behind the walls). In the evening the window glows warm while it settles in, and the lamp goes out once it's asleep.
    func renderBirdhouseShadow(_ p: Pose) {
        let now = CACurrentMediaTime()
        if p.inKennel { houseEnteredAt = houseEnteredAt ?? now } else { houseEnteredAt = nil }
        let win = Tree.window
        let winRect = CGRect(x: treeX + CGFloat(win.dx0), y: floorY - CGFloat(win.h1), width: CGFloat(win.dx1 - win.dx0), height: CGFloat(win.h1 - win.h0))   // top-left coordinates
        // the lamp
        let glow = glowLayer ?? {
            let (img, _) = ObjectSprite.image(id: "houseGlow", kind: "houseGlow")
            let l = CALayer()
            l.contents = img; l.anchorPoint = .zero; l.magnificationFilter = .nearest; l.zPosition = 0.45
            panel.contentView!.layer!.addSublayer(l)
            glowLayer = l
            return l
        }()
        let hour = clockHour
        let evening = hour >= 18 || hour < 6
        let lampOn = p.inKennel && evening && (p.anim != .sleep || now - (houseEnteredAt ?? now) < 90)   // settling in, then lights out
        if glow.isHidden == lampOn { glow.isHidden = !lampOn }
        glow.bounds = CGRect(origin: .zero, size: winRect.size)
        glow.position = CGPoint(x: winRect.minX.rounded(), y: (screenH - winRect.maxY).rounded())
        // the shadow
        let hole = holeLayer ?? {
            let l = CALayer()
            l.anchorPoint = .zero; l.magnificationFilter = .nearest; l.zPosition = 0.5
            l.bounds = CGRect(origin: .zero, size: DogSprite.size)
            let mask = CAShapeLayer()
            l.mask = mask
            panel.contentView!.layer!.addSublayer(l)
            holeLayer = l
            return l
        }()
        if hole.isHidden == p.inKennel { hole.isHidden = !p.inKennel }
        guard p.inKennel else { return }
        let size = DogSprite.size
        let feet = floorY - 46 * pp                          // standing on the birdhouse floor
        let r = CGRect(x: treeX + 2 * pp - size.width / 2, y: feet - size.height + DogSprite.footRows * pp, width: size.width, height: size.height)
        hole.position = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())
        hole.contents = DogSprite.silhouette(frameIndex, facing: CGFloat(p.facing))
        // mask in the layer's own (bottom-left) coordinates: the window panes and the round door
        let path = CGMutablePath()
        path.addRect(CGRect(x: winRect.minX - r.minX, y: r.maxY - winRect.maxY, width: winRect.width, height: winRect.height))
        let doorX = treeX + CGFloat(Tree.entrance.dx) - r.minX, doorY = r.maxY - (floorY - CGFloat(Tree.entrance.h)), rad = 4.2 * pp
        path.addEllipse(in: CGRect(x: doorX - rad, y: doorY - rad, width: rad * 2, height: rad * 2))
        (hole.mask as? CAShapeLayer)?.path = path
    }

    /// The swing (under branch 0) and the bell (under branch 3) hang from their tops and sway when used.
    func renderSwingAndBell(swing: CGFloat, bell: CGFloat) {
        func hanging(_ existing: CALayer?, art: String) -> CALayer {
            if let existing { return existing }
            let (img, size) = ObjectSprite.image(id: art, kind: art)
            let l = CALayer()
            l.contents = img; l.magnificationFilter = .nearest; l.zPosition = 0.5
            l.bounds = CGRect(origin: .zero, size: size); l.anchorPoint = CGPoint(x: 0.5, y: 1)   // hangs from its top
            panel.contentView!.layer!.addSublayer(l)
            return l
        }
        swingLayer = hanging(swingLayer, art: "swing")
        bellLayer = hanging(bellLayer, art: "bell")
        for (l, dx, top, angle) in [(swingLayer!, -19.0, 41.0, swing), (bellLayer!, 20.0, 63.0, bell)] {   // from tools/art/bird_home.py
            let pos = CGPoint(x: (treeX + CGFloat(dx) * pp).rounded(), y: (screenH - floorY + CGFloat(top) * pp).rounded())
            if l.position != pos { l.position = pos }
            l.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        }
    }

    // MARK: - Debug menu

    func testFlyToWindow() {
        let env = environment()
        if log { print("fly to a window: \(env.windows.count) windows, \(perchableWindows(env).count) to perch on"); fflush(stdout) }
        brain.debugFlyToWindow(env: env); render()
    }
    func testWindowClosed() { brain.debugWindowClosed(env: environment()); render() }
    func testHunt() { brain.s.needs.hunger = max(brain.s.needs.hunger, 0.6); test(.hunt, nil) }   // a rustle in the floor: it eats
}
