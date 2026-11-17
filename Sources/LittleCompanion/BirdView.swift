import AppKit
import PetCore
import QuartzCore

/// A bird on the desktop: its environment (other apps' windows to perch on), its frames, its tree's swing and bell,
/// and its shadow in the birdhouse doorway. The bird stays on the desktop layer, behind every window, like the dogs.
extension World {
    var pp: CGFloat { DogSprite.pointsPerPixel }
    var treeX: CGFloat { CGFloat(brain.s.objects.first { $0.kind == .tree }?.x ?? Double(maxX)) }

    /// Windows are polled ~15 times a second while it's on (or flying to) a window, once a second otherwise. No permission needed.
    func birdEnvironment(cursor c: CGPoint, idle: Double, hour: Double) -> Environment {
        let now = CACurrentMediaTime()
        let s = brain.s
        let onWindow = s.perch?.hasPrefix("w:") == true || s.flight?.to.hasPrefix("w:") == true
        if now - windowsAt >= (onWindow ? 1.0 / 15 : 1) {
            windowsAt = now
            let screen = CGRect(origin: .zero, size: screenFrame.size)   // CG window bounds are relative to the menu-bar screen, where it lives
            windows = otherWindows().filter { screen.intersects($0.rect) }
                .map { Win(id: $0.id, box: Box(x: $0.rect.minX, y: $0.rect.minY, w: $0.rect.width, h: $0.rect.height)) }
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
        if p.flight != nil || p.jump != nil { return 1.0 / 30 }   // smooth flight
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
        case .groom?: return t.truncatingRemainder(dividingBy: 3) < 2 ? (Int(t * 2.5) % 2 == 0 ? .preenA : .preenB) : .idle
        case .stretch?: return .stretch
        case .swing?: return .swing
        case .bell?: return Int(t * 3) % 2 == 0 ? .bellA : .bellB
        case .react?: return .startled
        case .greet?: return .front
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
        var frame = birdFrame(p, t)
        if t < blinkUntil { frame = frame == .idle ? .blink : frame == .front ? .frontBlink : frame }
        frameIndex = frame.rawValue
        let origin = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if dogLayer.isHidden != p.inKennel { dogLayer.isHidden = p.inKennel }
        if origin != dogOrigin { dogOrigin = origin; dogLayer.position = origin }
        let key = "\(frameIndex)\(p.facing)"
        if key != spriteKey { spriteKey = key; dogLayer.contents = DogSprite.image(frameIndex, facing: CGFloat(p.facing)) }
        renderBirdhouseShadow(p)
        renderSwingAndBell(swing: swingA, bell: ringing && !calm ? CGFloat(sin(t * 16) * 0.35) : 0)

        let rawEmote = p.emote ?? ""
        let snoozing = rawEmote == "z"
        if zzzLayer.isHidden == snoozing { zzzLayer.isHidden = !snoozing }
        if snoozing {   // from the birdhouse doorway, or just above its head on a branch
            zzzLayer.position = p.inKennel ? CGPoint(x: treeX + 6, y: screenH - (floorY - 58 * pp)) : CGPoint(x: r.midX + CGFloat(p.facing) * 6, y: screenH - (r.minY + 8 * pp))
        }
        let emote = snoozing || p.inKennel ? "" : rawEmote
        if emote != emoteText { emoteText = emote; emoteLayer.string = emote }
        if !emote.isEmpty { emoteLayer.position = CGPoint(x: r.midX + CGFloat(p.facing) * 8, y: screenH - r.minY + 10) }
        renderObjects(p, dog: r)
        CATransaction.commit()
        updateHitTest()
    }

    /// In the birdhouse: its soft shadow shows through the round doorway (the rest of it is behind the walls).
    func renderBirdhouseShadow(_ p: Pose) {
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
        let doorY = floorY - CGFloat(Tree.entrance.h)       // the doorway's centre, top-left coordinates
        let r = CGRect(x: treeX - size.width / 2, y: doorY + 12 * pp - size.height + DogSprite.footRows * pp, width: size.width, height: size.height)   // its middle behind the doorway
        hole.position = CGPoint(x: r.minX.rounded(), y: (screenH - r.maxY).rounded())
        hole.contents = DogSprite.silhouette(frameIndex, facing: CGFloat(p.facing))
        let c = CGPoint(x: treeX - r.minX, y: r.maxY - doorY), rad = 3.3 * pp
        (hole.mask as? CAShapeLayer)?.path = CGPath(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2), transform: nil)
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

    func testFlyToWindow() { brain.debugFlyToWindow(env: environment()); render() }
    func testWindowClosed() { brain.debugWindowClosed(env: environment()); render() }
}
