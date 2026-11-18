import Foundation

/// What kind of pet. One engine: a species is its acts, its home and how it moves (dogs walk the floor;
/// birds hop and fly between perches at different heights; owls are birds that live by night).
public enum Species: String, Codable, Sendable { case dog, bird, owl }

/// A rectangle in screen points, top-left origin (PetCore stays free of CoreGraphics).
public struct Box: Codable, Sendable, Equatable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px <= maxX && py >= y && py <= maxY }
}

/// Another app's ordinary window, as the bird sees it.
public struct Win: Sendable, Equatable {
    public var id: Int
    public var box: Box
    public init(id: Int, box: Box) { self.id = id; self.box = box }
}

/// A toy flung or dropped from a perch: it flies on at `vx`, falls under gravity and (with `bounce`, the share of its speed
/// it keeps) bounces a few times before it settles on the floor.
public struct Toss: Codable, Sendable, Equatable {
    public var id: String
    public var x0, y0, vx, at: Double
    public var bounce: Double? = nil
    public static let g = 900.0   // points/s²
    public func fallTime(floorY: Double) -> Double { sqrt(2 * max(0, floorY - y0) / Toss.g) }
    /// Its bottom, in screen points from the top, `t` seconds after it left the perch.
    public func y(_ t: Double, floorY: Double) -> Double {
        let t0 = fallTime(floorY: floorY)
        if t < t0 { return y0 + 0.5 * Toss.g * t * t }
        var v = Toss.g * t0 * (bounce ?? 0), tt = t - t0
        while v > 40 {
            let up = 2 * v / Toss.g
            if tt < up { return floorY - (v * tt - 0.5 * Toss.g * tt * tt) }
            tt -= up; v *= bounce ?? 0
        }
        return floorY
    }
    /// How long until it lies still.
    public func duration(floorY: Double) -> Double {
        var total = fallTime(floorY: floorY), v = Toss.g * total * (bounce ?? 0)
        while v > 40 { total += 2 * v / Toss.g; v *= bounce ?? 0 }
        return total
    }
}

/// Something small that's alive on the floor: a beetle scuttling about or a moth fluttering low. A hungry owl hunts it.
public struct Prey: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case beetle, moth }
    public var kind: Kind
    public var x: Double, vx: Double
    public var h = 0.0               // a moth's height above the floor
    public var nextTurn = 0.0
    public var caught = false
}

/// A flight is a quadratic Bézier from (x0, y0) through the pull of (vx, vy) to (x1, y1); a fall drops under gravity;
/// a recovery is a few hard flaps that catch it in the air.
public struct Flight: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case fly, fall, recover }
    public var kind: Kind
    public var x0, y0, x1, y1, vx, vy: Double
    public var start, len: Double
    public var to: String           // the perch it lands on ("" for none: decides in the air)
    public var dx: Double?          // landing spot along a window's top edge
}

/// How it's moving through the air, for the renderer.
public enum FlightStage: String, Sendable { case takeoff, flap, glide, flare, fall, recover }

/// The tree's perches: x from the tree's centre, h above the floor, in points.
/// shortcut: copied from tools/art/bird_home.py (pixels × 1.5); change both together.
public enum Tree {
    public struct Ledge: Sendable { public var from, to, h: Double }
    static let k = 1.5
    // Perches stay clear of the cottage birdhouse (dx −15…15 between heights 46 and 75) so it never stands in front of its walls.
    public static let branches = [Ledge(from: -26 * k, to: -17 * k, h: 44 * k),   // b0: the swing hangs from it
                                  Ledge(from: 16 * k, to: 23 * k, h: 40 * k),     // b1: the bell hangs above its tip
                                  Ledge(from: -27 * k, to: -20 * k, h: 64 * k),   // b2, beside the roof
                                  Ledge(from: 19 * k, to: 24 * k, h: 66 * k)]     // b3, beside the roof, under the crown
    public static let swing = (dx: -19 * k, h: 10 * k)   // the seat
    public static let bell = (dx: 19 * k, h: 40 * k)     // sitting on b1, beak level with the bell hanging from b3
    public static let house = (dx: -7 * k, h: 47 * k)     // the peg under the round door
    public static let entrance = (dx: -7 * k, h: 54 * k)  // centre of the door
    /// The curtained window (dx0, dx1, h0, h1 in points): its shadow shows here while it's inside, and the lamp glows in the evening.
    public static let window = (dx0: 3 * k, dx1: 12 * k, h0: 49 * k, h1: 60 * k)
    public static let halfWidth = 32 * k
}

/// An owl's hollow oak: perches on the level stretches of its crooked branches, and the knothole it sleeps in by day.
/// shortcut: measured from tools/art/owl_home.py (pixels × 1.5); change both together.
public enum Oak {
    static let k = 1.5
    public static let branches = [Tree.Ledge(from: -22 * k, to: -17 * k, h: 30 * k),   // low left
                                  Tree.Ledge(from: -28 * k, to: -18 * k, h: 60 * k),   // high left
                                  Tree.Ledge(from: 18 * k, to: 24 * k, h: 45 * k),     // right; the lantern hangs past its tip
                                  Tree.Ledge(from: 18 * k, to: 23 * k, h: 71 * k)]     // top right
    public static let house = (dx: 0.0, h: 31 * k)        // the lip of the knothole
    public static let entrance = (dx: 0.0, h: 37 * k)     // where its eyes glint while it's inside
    public static let lantern = (dx: 26 * k, top: 42 * k)
    public static let logTop = 7 * k
    /// The lantern is lit from dusk to dawn.
    public static func lit(_ hour: Double) -> Bool { hour >= 18 || hour < 7 }
}

/// An owl's home: the oak at the right end of the floor, its bath, and its toys along the floor to the left.
public func owlHome(maxX: Double) -> [PetObject] {
    var o: [PetObject] = []
    repairOwlHome(&o, maxX: maxX)
    return o
}

/// The oak stays pinned at the right end; the bath and toys sit to its left (the pinecone may be batted about).
public func repairOwlHome(_ objects: inout [PetObject], maxX: Double) {
    let tx = maxX - 16   // the oak is wider than the bird tree: keep its right branch tip on screen
    let home: [(String, Kind, Double)] = [("oak", .oak, 0), ("birdbath", .waterDish, -100), ("mouse", .mouse, -150), ("pinecone", .pinecone, -185),
                                          ("log", .log, -240)]
    objects.removeAll { $0.kind == .feather }   // the feather toy was retired
    for (id, kind, _) in home where !objects.contains(where: { $0.kind == kind }) { objects.append(PetObject(id: id, kind: kind, x: 0)) }
    for i in objects.indices {
        guard let (_, _, dx) = home.first(where: { $0.1 == objects[i].kind }) else { continue }
        let movable = objects[i].kind == .pinecone || objects[i].kind == .mouse   // toys it bats or throws stay where they ended up
        if !movable || objects[i].x == 0 || objects[i].x > tx - 60 { objects[i].x = tx + dx }
    }
}

/// A bird's home: its tree at the right end of the floor, seed and water dishes at its foot on the left.
public func birdHome(maxX: Double) -> [PetObject] {
    var o = [PetObject(id: "tree", kind: .tree, x: 0), PetObject(id: "seeds", kind: .seedDish, x: 0), PetObject(id: "birdbath", kind: .waterDish, x: 0),
             PetObject(id: "rattan", kind: .rattan, x: 0)]
    repairBirdHome(&o, maxX: maxX)
    return o
}

/// The tree stays pinned at the right end and the dishes at its foot (nothing in a bird's home moves yet).
public func repairBirdHome(_ objects: inout [PetObject], maxX: Double) {
    for (id, kind) in [("tree", Kind.tree), ("seeds", .seedDish), ("birdbath", .waterDish), ("rattan", .rattan)] where !objects.contains(where: { $0.kind == kind }) {
        objects.append(PetObject(id: id, kind: kind, x: 0))
    }
    let tx = maxX - 10
    for i in objects.indices {
        switch objects[i].kind {
        case .tree: objects[i].x = tx
        case .seedDish: objects[i].x = tx - 112
        case .waterDish: objects[i].x = tx - 76
        case .rattan: if objects[i].x == 0 || objects[i].x > tx - 130 { objects[i].x = tx - 160 }   // its ball stays wherever it dropped it
        default: break
        }
    }
}

/// Window tops it may land on, with the spots along each top edge: an ordinary window at least 200 pt wide on its
/// screen, with ≥ 48 pt of clear space above (so not maximised under the menu bar), at a spot no window in front
/// covers, and clear of the traffic-light buttons at the left.
public func perchableWindows(_ env: Environment) -> [(win: Win, xs: [Double])] {
    var out: [(Win, [Double])] = []
    for (i, w) in env.windows.enumerated() where w.box.w >= 200 && w.box.y - env.topY >= 48 && w.box.y < env.floorY - 60 {
        let front = env.windows[..<i]
        var xs: [Double] = []
        var x = w.box.x + 96
        while x <= w.box.maxX - 24 {
            let covered = front.contains { $0.box.x - 24 <= x && x <= $0.box.maxX + 24 && $0.box.y <= w.box.y + 4 && $0.box.maxY >= w.box.y - 48 }
            if !covered && x >= env.minX && x <= env.maxX { xs.append(x) }
            x += 24
        }
        if !xs.isEmpty { out.append((w, xs)) }
    }
    return out
}

struct Spot { var perch: String; var x: Double; var y: Double; var dx: Double? = nil }

extension Brain {
    var isBird: Bool { s.species == .bird || s.species == .owl }   // owls run on the bird engine
    var isOwl: Bool { s.species == .owl }
    var ledges: [Tree.Ledge] { isOwl ? Oak.branches : Tree.branches }
    var peg: (dx: Double, h: Double) { isOwl ? Oak.house : Tree.house }
    /// Sleep pressure from the clock: an owl's day is a bird's night (awake from dusk to dawn).
    func clock(_ env: Environment) -> Double { Self.sleepiness(hour: isOwl ? (env.hour + 12).truncatingRemainder(dividingBy: 24) : env.hour) }
    static let flySpeed = 230.0, hopSpeed = 50.0, takeoff = 0.3

    func object(_ kind: Kind) -> PetObject? { s.objects.first { $0.kind == kind } }
    var treeX: Double { (object(.tree) ?? object(.oak))?.x ?? 1000 }
    func windowID(_ perch: String?) -> Int? { perch.flatMap { $0.hasPrefix("w:") ? Int($0.dropFirst(2)) : nil } }
    func branch(_ perch: String?) -> Int? {
        guard let p = perch, p.hasPrefix("b"), let i = Int(p.dropFirst()), ledges.indices.contains(i) else { return nil }
        return i
    }
    /// In its birdhouse (or on the way in or out).
    var inHouse: Bool { let a = s.activity; return a.target == "house" && (a.act == .kennel || a.act == .sleep) && a.kennel == .inside }

    /// Where a perch's surface is now (nil: a window that has gone).
    func perchY(_ perch: String, _ env: Environment) -> Double? {
        switch perch {
        case "floor": return env.floorY
        case "swing": return env.floorY - Tree.swing.h
        case "bell": return env.floorY - Tree.bell.h
        case "house": return env.floorY - peg.h
        case "log": return env.floorY - Oak.logTop
        default:
            if let id = windowID(perch) { return env.windows.first { $0.id == id }?.box.y }
            return branch(perch).map { env.floorY - ledges[$0].h }
        }
    }

    /// How far it can hop along a perch (nil: a single spot, like the swing).
    func perchRange(_ perch: String, _ env: Environment) -> ClosedRange<Double>? {
        if perch == "floor" { return env.minX...max(env.minX, treeX - 40) }
        if let id = windowID(perch), let w = env.windows.first(where: { $0.id == id }) {
            let lo = max(w.box.x + 96, env.minX), hi = min(w.box.maxX - 24, env.maxX)
            return lo <= hi ? lo...hi : nil
        }
        if perch == "log", let l = object(.log) { return l.x - 12...l.x + 12 }
        return branch(perch).map { treeX + ledges[$0].from ... treeX + ledges[$0].to }
    }

    // MARK: - Choosing where to go

    /// A new perch: a branch, the floor or a window top. Curious birds visit windows more; `nearYou` picks the window
    /// top closest to where you've been working.
    mutating func choosePerch(_ env: Environment, nearYou: Bool = false) -> Spot? {
        var options: [(Spot, Double)] = []
        if !nearYou {
            for (i, b) in ledges.enumerated() where "b\(i)" != s.perch {
                options.append((Spot(perch: "b\(i)", x: treeX + rand(b.from...b.to), y: env.floorY - b.h), 1))
            }
            if s.perch != "floor" { options.append((Spot(perch: "floor", x: rand(env.minX...max(env.minX, treeX - 60)), y: env.floorY), 0.9)) }
            if isOwl, let l = object(.log), s.perch != "log" { options.append((Spot(perch: "log", x: l.x + rand(-8...8), y: env.floorY - Oak.logTop), 0.8)) }   // a low watch post
        }
        let wins = perchableWindows(env)
        for (w, xs) in wins where "w:\(w.id)" != s.perch {
            let x = xs[Int.random(in: xs.indices, using: &s.rng)]
            var weight = (0.3 + 2 * s.personality.curiosity) / sqrt(Double(wins.count))
            if nearYou, let cx = env.cursorX, let cy = env.cursorY { weight = 1 / (1 + pow(hypot(x - cx, w.box.y - cy) / 150, 2)) }
            options.append((Spot(perch: "w:\(w.id)", x: x, y: w.box.y, dx: x - w.box.x), weight))
        }
        guard !options.isEmpty else { return nil }
        var r = rand(0...options.map(\.1).reduce(0, +))
        for (spot, w) in options { r -= w; if r <= 0 { return spot } }
        return options.last!.0
    }

    mutating func birdCandidates(_ env: Environment) -> [Candidate] {
        let n = s.needs, p = s.personality, circ = clock(env)
        var c: [Candidate] = []
        let away = env.userIdle > Brain.awayAfter ? 1.8 : 1
        let night = 1 - 0.9 * circ, calmNight = 1 - 0.5 * circ
        let sleepBase = (pow(n.tiredness, 1.5) * (0.4 + circ) * (0.6 + 0.8 * p.laziness) * away * (n.tiredness < 0.2 * (1 - circ) ? 0.05 : 1) * 4
                         + 1.2 * max(0, circ - 0.7) / 0.3 * (0.5 + p.laziness))
        c.append(.init(act: .sleep, target: circ > 0.6 ? "house" : nil, score: sleepBase))   // nights in the birdhouse, naps on a branch
        let den = (0.15 + 0.35 * p.independence + 0.3 * p.laziness) * (0.3 + n.tiredness) * (env.userIdle > Brain.awayAfter ? 1.5 : 1) * (1 - 0.3 * circ)
        c.append(.init(act: .kennel, target: "house", score: env.systemBusy ? 8 : den * 0.18))
        if object(.seedDish) != nil { c.append(.init(act: .eat, target: "seeds", score: pow(n.hunger, 2) * 5 * (n.hunger < 0.25 ? 0.05 : 1))) }
        if object(.waterDish) != nil {
            c.append(.init(act: .drink, target: "birdbath", score: pow(n.thirst, 2) * 5 * (n.thirst < 0.25 ? 0.05 : 1)))
            c.append(.init(act: .splash, target: "birdbath", score: 0.12 * (0.4 + p.playfulness) * (0.5 + n.boredom) * night))
        }
        let fun = (0.3 + n.boredom) * (0.3 + p.playfulness) * (1 - 0.8 * n.tiredness) * night
        if isOwl {   // no swing or bell: it hunts its mouse (that's how it eats), bats its pinecone and hoots at dusk and dawn
            // It eats by hunting a rustle in the floor (nothing is ever drawn); the plush mouse is a toy it stalks for fun.
            c.append(.init(act: .hunt, target: nil, score: pow(n.hunger, 2) * 5 * (n.hunger < 0.25 ? 0.05 : 1)))
            if object(.mouse) != nil { c.append(.init(act: .hunt, target: "mouse", score: 0.3 * fun * (0.4 + p.curiosity))) }
            if Oak.lit(env.hour) {   // the lantern: it likes to sit by it at night, and goes there first when it comes out after dark
                let justUp = s.time - (s.lastDone[.sleep] ?? -1e9) < 60 && s.perch == "house"   // out of the knothole after a proper sleep
                c.append(.init(act: .idle, target: "lantern", score: justUp ? 4 : s.perch == "b2" ? 0.15 * night : 0.05 * night))
            }
            if object(.pinecone) != nil { c.append(.init(act: .play, target: "pinecone", score: 0.25 * fun)) }
            if object(.mouse) != nil { c.append(.init(act: .carry, target: "mouse", score: 0.035 * fun)) }   // up a branch with it, then flings it down
            let h = env.hour, twilight = (h >= 18.5 && h < 21.5) || (h >= 4.5 && h < 7)
            c.append(.init(act: .hoot, target: nil, score: (twilight ? 0.6 : 0.03) * (0.4 + p.independence) * (1 - circ)))
        } else {
            if object(.rattan) != nil { c.append(.init(act: .carry, target: "rattan", score: 0.025 * fun)) }   // up somewhere high, to drop it and watch it bounce
            c.append(.init(act: .swing, target: nil, score: 0.2 * fun))
            c.append(.init(act: .bell, target: nil, score: 0.2 * fun))
        }
        let onGround = s.perch == "floor" || s.perch == "log" || windowID(s.perch) != nil
        c.append(.init(act: .fly, target: nil, score: (isOwl ? 0.11 : 0.18) * (0.2 + p.energy) * (1 - 0.6 * n.tiredness) * (1 - 0.85 * circ)))   // energetic birds fly more; owls less
        // A joy flight: swooping about the desktop without landing, when it's lively, rested and happy. At most every half hour.
        let screenArea = (env.maxX - env.minX + 80) * max(1, env.floorY - env.topY)
        let covered = env.windows.reduce(0) { $0 + $1.box.w * $1.box.h } / screenArea   // overlaps count twice: a rough measure is enough
        let clearDesktop = env.windows.count <= 2 || covered < 0.35   // only when it'll be seen, not mostly behind your work
        if !calm, clearDesktop, s.time - (s.lastDone[.zoomies] ?? -1e9) > 1800 {
            c.append(.init(act: .zoomies, target: nil, score: 0.25 * p.energy * pow(1 - n.tiredness, 2) * (0.3 + n.boredom) * mood * night))
        }
        c.append(.init(act: .hop, target: nil, score: 0.3 * (0.4 + p.energy) * (onGround ? 1 : 0.4) * (1 - 0.85 * circ)))
        c.append(.init(act: .peck, target: nil, score: 0.25 * (0.3 + p.curiosity) * (0.5 + n.hunger) * (onGround ? 1 : 0.3) * (1 - 0.8 * circ)))
        c.append(.init(act: .idle, target: nil, score: 0.6 * (0.5 + p.laziness) * calmNight))
        c.append(.init(act: .lookAround, target: nil, score: 0.3 * (0.5 + p.curiosity) * (1 - 0.6 * circ)))
        c.append(.init(act: .groom, target: nil, score: 0.35 * calmNight))   // preening
        let justWoke = s.time - (s.lastDone[.sleep] ?? -1e9) < 20
        c.append(.init(act: .stretch, target: nil, score: justWoke ? 4 : 0.12))
        // Affectionate birds now and then come to sit near where you're working (at most every 10 min).
        if env.cursorY != nil, env.userIdle < 30, s.time - (s.lastNearYou ?? -1e9) > 600 {
            c.append(.init(act: .fly, target: "you", score: 0.15 * pow(p.affection, 2) * night))
        }
        applyHistory(&c)
        return c
    }

    // MARK: - Doing things

    mutating func birdStart(_ act: Act, target: String?, _ env: Environment) {
        // A bird sits a good while between moves: perched spells run longer than a dog's.
        let span: ClosedRange<Double> = switch act { case .idle: 40...180; case .lookAround: 8...25; case .groom: 20...60; case .fly: 20...90; default: act.duration }
        var a = Activity(act: act, target: target, destX: nil, remaining: rand(span), started: s.time)
        if act == .sleep { a.remaining *= 1 + 2 * clock(env) }
        let here = s.perch ?? "air", fy = env.floorY   // no perch: its window just went from under it
        var spot: Spot?
        switch act {
        case .zoomies:   // swoops from one point in the air to the next across the whole desktop, then settles on a perch
            a.phase = "laps:\(Int(rand(6...12.99)))"
            s.activity = a
            flyTo(zoomPoint(env), env)
            s.flight?.len = 1e9                                          // a joy flight is steered, not a fixed curve (see flyTick)
            s.zoomVX = s.facing * 0.75 * Brain.zoomSpeed; s.zoomVY = -0.66 * Brain.zoomSpeed   // up and away
            return
        case .fly:
            spot = choosePerch(env, nearYou: target == "you")
            if target == "you" { s.lastNearYou = s.time }
        case .eat: if let o = object(.seedDish) { spot = Spot(perch: "floor", x: o.x + (s.x < o.x ? -16 : 16), y: fy) }
        case .drink: if let o = object(.waterDish) { spot = Spot(perch: "floor", x: o.x + (s.x < o.x ? -16 : 16), y: fy) }
        case .splash: if let o = object(.waterDish) { spot = Spot(perch: "floor", x: o.x, y: fy) }   // right in it
        case .hunt where target == "mouse":   // lands a little way off its toy and stares at it first
            if let m = object(.mouse) { let side = s.x < m.x ? -1.0 : 1; spot = Spot(perch: "floor", x: m.x + side * 26, y: fy) }
        case .hunt:   // a beetle scuttling or a moth fluttering on the floor: it lands a way off and watches it first
            let lo = env.minX + 40, hi = max(env.minX + 40, treeX - 90)
            let px = here == "floor" ? min(max(s.x + (rand(0...1) < 0.5 ? -1 : 1) * rand(70...140), lo), hi) : rand(lo...hi)
            let moth = rand(0...1) < 0.5
            s.prey = Prey(kind: moth ? .moth : .beetle, x: px, vx: (rand(0...1) < 0.5 ? -1 : 1) * (moth ? 16 : 11), h: moth ? 10 : 0, nextTurn: s.time + rand(1.5...4))
            let side = s.x < px ? -1.0 : 1
            spot = Spot(perch: "floor", x: min(max(px + side * 50, lo), hi), y: fy)
        case .idle where target == "lantern":   // on the lantern branch, right beside the light
            spot = Spot(perch: "b2", x: treeX + Oak.branches[2].to, y: fy - Oak.branches[2].h)
        case .carry:   // down to the toy first (an owl stands over it; a parrot beside it, to pick it up in its beak)
            if let o = s.objects.first(where: { $0.id == target }) { spot = Spot(perch: "floor", x: isOwl ? o.x : o.x + (s.x < o.x ? -10 : 10), y: fy) }
        case .play where isOwl:
            if let o = object(.pinecone) { spot = Spot(perch: "floor", x: o.x + (s.x < o.x ? -18 : 18), y: fy) }
        case .swing: spot = Spot(perch: "swing", x: treeX + Tree.swing.dx, y: fy - Tree.swing.h)
        case .bell: spot = Spot(perch: "bell", x: treeX + Tree.bell.dx, y: fy - Tree.bell.h)
        case .kennel:
            spot = Spot(perch: "house", x: treeX + peg.dx, y: fy - peg.h); a.kennel = .door
        case .sleep where target == "house":
            spot = Spot(perch: "house", x: treeX + peg.dx, y: fy - peg.h); a.kennel = .door
        case .sleep where branch(here) == nil:   // a daytime nap, fluffed up on a branch
            let i = Int.random(in: ledges.indices, using: &s.rng), b = ledges[i]
            spot = Spot(perch: "b\(i)", x: treeX + rand(b.from...b.to), y: fy - b.h)
        case .peck where here != "floor":
            spot = Spot(perch: "floor", x: rand(env.minX...max(env.minX, treeX - 60)), y: fy)
        case .hop:
            if let r = perchRange(here, env) { a.destX = min(max(s.x + (rand(0...1) < 0.5 ? -1 : 1) * rand(20...70), r.lowerBound), r.upperBound) }
        default: break
        }
        if let spot {
            if spot.perch == here, let r = perchRange(here, env), !(isOwl && abs(spot.x - s.x) > 100) {   // an owl flies anything further than a short waddle
                a.destX = min(max(spot.x, r.lowerBound), r.upperBound)   // it's on this perch already: hop over
            } else if spot.perch != here || abs(spot.x - s.x) > 2 {
                s.activity = a
                flyTo(spot, env)
                return
            }
        }
        if let d = a.destX, abs(d - s.x) < 2 { a.destX = nil }
        if a.destX == nil { birdArrive(&a, env) }
        s.activity = a
    }

    /// At the spot (landed, or hopped there).
    mutating func birdArrive(_ a: inout Activity, _ env: Environment) {
        if let o = s.objects.first(where: { $0.id == a.target }), a.act != .splash { s.facing = o.x >= s.x ? 1 : -1 }
        if a.act == .bell { s.facing = 1 }
        if a.act == .zoomies { a.phase = "settled"; a.remaining = rand(2...4) }   // catches its breath
        if a.act == .groom { a.phase = "preen"; s.boutUntil = s.time + preenBout() }
        if a.act == .hunt { s.huntAt = s.time; a.remaining = a.target == "mouse" ? 8 : 30; a.phase = nil }
        if a.target == "lantern" { s.facing = 1; a.front = false }   // facing the light
        if a.act == .carry {   // picks its toy up in its beak and flies about with it, perch to perch, then drops it in mid-flight
            switch a.phase {
            case nil:
                if let o = s.objects.first(where: { $0.id == a.target }) { s.facing = o.x >= s.x ? 1 : -1 }
                s.carrying = a.target
                a.phase = rand(0...1) < 0.5 ? "around:2" : "around:3"   // flights to make with it, the last one ending in the drop
                a.remaining = 0.6                                       // a moment with it in its beak before it takes off
            case let ph? where ph.hasPrefix("around"): a.remaining = rand(1.5...4)   // landed with it: a short rest, then off again
            case "thrown"?: a.remaining = 1                                            // landed after the drop: watches where it went
            default: break
            }
        }
        if a.target == "house" && (a.act == .kennel || a.act == .sleep) && a.kennel == .door { a.kennel = .inside; s.perch = "house" }
        if a.act == .lookAround || a.act == .idle { a.front = rand(0...1) < 0.15 + 0.3 * s.personality.affection }
        if a.act == .greet { a.front = true }
    }

    mutating func birdPerform(_ a: inout Activity, _ dt: Double, _ env: Environment) {
        if a.act != .hunt { s.huntAt = nil; s.prey = nil }
        if a.act != .play { s.rollTo = nil }
        switch a.act {
        case .eat:
            s.needs.hunger -= dt / 20
            if s.needs.hunger <= 0 { a.remaining = 0 }
        case .drink:
            s.needs.thirst -= dt / 8
            if s.needs.thirst <= 0 { a.remaining = 0 }
        case .splash: s.needs.boredom -= dt / 60; s.needs.thirst -= dt / 40
        case .swing, .bell: s.needs.boredom -= dt / 40
        case .hunt where a.target == "mouse":   // its toy: stare 3 s, pounce, mantle over it, let it go
            let t = s.time - (s.huntAt ?? s.time)
            if t >= 3, a.phase == nil, let m = object(.mouse) { a.phase = "pounced"; s.x = m.x - s.facing * 4; jump(height: 12, length: 0.35) }
            s.needs.boredom -= dt / 30
        case .hunt:   // real prey: watch it 2 s, stalk after it, pounce when it's close, mantle over it and gulp it down
            guard var p = s.prey else { a.remaining = 0; break }
            let t = s.time - (s.huntAt ?? s.time)
            if a.phase == "pounced" {
                if t >= 5 { s.needs.hunger -= dt / 1.5 }
            } else {
                s.facing = p.x >= s.x ? 1 : -1
                let d = abs(p.x - s.x)
                if t >= 2 && d < 26 && s.jumpAt == nil {   // pounce!
                    a.phase = "pounced"; a.destX = nil; a.remaining = 4.4
                    s.x = p.x - s.facing * 4; jump(height: 12, length: 0.35)
                    p.caught = true; s.prey = p
                    s.huntAt = s.time - 3   // so the pose runs on into pounce, mantle and gulp
                } else if t >= 2 { a.destX = p.x - s.facing * 16 }   // stalking after it
                if t > 25 { s.prey = nil; a.remaining = 0 }   // it got away
            }
        case .play:   // a paw-strike sends the pinecone rolling; it waddles after it and watches it
            s.needs.boredom -= dt / 40
            if let i = s.objects.firstIndex(where: { $0.id == "pinecone" }) {
                if let to = s.rollTo {   // rolling, slowing to a stop
                    let d = to - s.objects[i].x, step = max(12, min(90, abs(d) * 3)) * dt
                    if abs(d) <= step { s.objects[i].x = to; s.rollTo = nil } else { s.objects[i].x += d > 0 ? step : -step }
                } else if a.destX == nil, s.jumpAt == nil, case let px = s.objects[i].x, abs(s.x - (px + (s.x < px ? -18 : 18))) > 3 {
                    a.destX = px + (s.x < px ? -18 : 18)   // the bat's done and it has stopped rolling: waddle after it
                } else if s.time >= (s.nextRoll ?? 0), a.destX == nil {
                    s.nextRoll = s.time + rand(3...6)
                    s.rollTo = min(max(s.objects[i].x + s.facing * rand(20...45), env.minX), treeX - 60)
                    jump(height: 5, length: 0.3)   // the bat
                }
            }
        case .hoot: if rand(0...1) < dt * 0.6 { setEmote("hoo", 1.4) }   // a puffed throat and a soft (silent) hoo
        case .sleep:
            if a.target != "house" || a.kennel == .inside {
                if s.needs.tiredness <= 0.02 && clock(env) < 0.6 { a.remaining = 0 }
                dreamTick()
            }
        case .kennel: if a.kennel == .inside && s.needs.tiredness > 0.3 { dreamTick() }
        case .lookAround: if rand(0...1) < dt * 0.6 { s.facing = -s.facing }
        case .groom:   // preens in bouts; after one, a curious bird often stops to look round, others mostly preen on
            if s.time >= (s.boutUntil ?? 0) {
                if a.phase == "look" || rand(0...1) > 0.15 + 0.7 * s.personality.curiosity {
                    a.phase = "preen"; s.boutUntil = s.time + preenBout()
                } else {
                    a.phase = "look"; s.boutUntil = s.time + rand(2...5)
                }
            }
            if a.phase == "look" && rand(0...1) < dt * 0.5 { s.facing = -s.facing }
        case .idle: if rand(0...1) < dt * 0.05 { a.front = rand(0...1) < 0.2 + 0.3 * s.personality.affection; if a.front != true, rand(0...1) < 0.5 { s.facing = -s.facing } }
        case .hop, .peck:
            if rand(0...1) < dt * (a.act == .hop ? 0.6 : 0.15), let r = perchRange(s.perch ?? "floor", env) {   // a few more hops along
                a.destX = min(max(s.x + (rand(0...1) < 0.5 ? -1 : 1) * rand(a.act == .hop ? 20...60 : 8...20), r.lowerBound), r.upperBound)
            }
        default: break
        }
        s.needs.clamp()
    }

    // MARK: - Moving

    func bezier(_ f: Flight, _ t: Double) -> (Double, Double) {
        let u = 1 - t
        return (u * u * f.x0 + 2 * u * t * f.vx + t * t * f.x1, u * u * f.y0 + 2 * u * t * f.vy + t * t * f.y1)
    }

    /// Off to a spot. Of a few arcs it takes the one most out in the open (through the gaps between windows);
    /// if there's none, it is glimpsed passing behind them.
    static let zoomSpeed = 320.0
    /// A point in the open air somewhere across the desktop, well away from where it is now: a waypoint for a joy flight.
    /// `heading`: the way it's flying now; points roughly ahead are preferred, so it swoops on rather than doubling back.
    mutating func zoomPoint(_ env: Environment, heading: (Double, Double)? = nil) -> Spot {
        let y0 = s.y ?? env.floorY
        var best = Spot(perch: "zoom", x: s.x, y: y0), bestScore = -1.0
        for _ in 0..<10 {
            // waypoints keep well in from the edges, so it always has room to swoop round on to the next
            let p = Spot(perch: "zoom", x: rand((env.minX + 160)...max(env.minX + 160, env.maxX - 160)), y: rand((env.topY + 120)...max(env.topY + 120, env.floorY - 120)))
            let d = hypot(p.x - s.x, p.y - y0)
            var ahead = 1.0
            if let (hx, hy) = heading, d > 0 { ahead = (1 + ((p.x - s.x) * hx + (p.y - y0) * hy) / (d * max(1e-6, hypot(hx, hy)))) / 2 }
            let score = ahead < 0.4 ? d * 0.01 : d * (0.2 + 0.8 * ahead)   // nothing behind it, unless that's all there is
            if score > bestScore { bestScore = score; best = p }
        }
        return best
    }
    /// How long a preening bout lasts: laid-back birds settle into it for longer.
    mutating func preenBout() -> Double { rand(3...8) * (0.7 + 0.8 * s.personality.laziness) }
    /// `heading`: carry on in this direction from where it is (a joy flight swooping on to its next waypoint), instead of picking an arc.
    mutating func flyTo(_ spot: Spot, _ env: Environment, takeoff: Bool = true, speed: Double = Brain.flySpeed, heading: (Double, Double)? = nil) {
        let x0 = s.x, y0 = s.y ?? env.floorY
        let dist = hypot(spot.x - x0, spot.y - y0)
        var best: (vx: Double, vy: Double, cost: Double) = ((x0 + spot.x) / 2, min(y0, spot.y), .infinity)
        for lift in [24.0, 90, 180, 300] {
            let vx = (x0 + spot.x) / 2, vy = max(env.topY + 24, min(y0, spot.y) - lift - dist * 0.08)
            let f = Flight(kind: .fly, x0: x0, y0: y0, x1: spot.x, y1: spot.y, vx: vx, vy: vy, start: 0, len: 1, to: "")
            let hidden = (1..<12).filter { k in let (x, y) = bezier(f, Double(k) / 12); return env.windows.contains { $0.box.contains(x, y - 16) } }.count
            let cost = Double(hidden) + lift / 500
            if cost < best.cost { best = (vx, vy, cost) }
        }
        s.flight = Flight(kind: .fly, x0: x0, y0: y0, x1: spot.x, y1: spot.y, vx: best.vx, vy: best.vy,
                          start: s.time + (takeoff ? Brain.takeoff : 0), len: max(0.8, dist / speed + 0.3), to: spot.perch, dx: spot.dx)
        if let (hx, hy) = heading {   // a smooth turn: the new curve leaves along the old one's direction
            let n = max(1e-6, hypot(hx, hy)), ux = hx / n, uy = hy / n
            // near an edge the guide point may overshoot by up to 80 pt (the path itself only gets half as far), never bent sideways
            var k = dist * 0.45, m = 80.0
            if ux > 0 { k = min(k, (env.maxX + m - x0) / ux) } else if ux < 0 { k = min(k, (env.minX - m - x0) / ux) }
            if uy > 0 { k = min(k, (env.floorY - y0) / uy) } else if uy < 0 { k = min(k, (env.topY - y0) / uy) }   // never below the floor, nor into the menu bar
            k = max(min(dist * 0.25, 60), k)
            s.flight!.vx = x0 + ux * k; s.flight!.vy = y0 + uy * k
        }
        s.perch = nil; s.perchDX = nil; s.rideSince = nil; s.coveredSince = nil; s.jumpAt = nil
        if abs(spot.x - x0) > 2 { s.facing = spot.x > x0 ? 1 : -1 }
    }

    mutating func flyTick(_ env: Environment, _ dt: Double = 0.05) {
        guard var f = s.flight else { return }
        if f.kind == .fly && f.to == "zoom" {   // a joy flight: steer towards the waypoint, turning at most 2.6 rad/s (a turning circle ~150 pt)
            s.flight = f
            guard s.time >= f.start else { return }   // crouched, about to spring
            let y = s.y ?? env.floorY
            var tx = f.x1 - s.x, ty = f.y1 - y
            // shy of the edges: near one, it's pulled back towards the middle (so it never scrapes along the menu bar or the Dock)
            var nearEdge = false
            if y - env.topY < 190 { ty += 420; nearEdge = true } else if env.floorY - y < 150 && s.time - s.activity.started > 1.5 { ty -= 420; nearEdge = true }   // (not while it's climbing off the floor)
            if s.x - env.minX < 160 { tx += 420; nearEdge = true } else if env.maxX - s.x < 160 { tx -= 420; nearEdge = true }
            let cur = atan2(s.zoomVY ?? -1, s.zoomVX ?? 0)
            var d = atan2(ty, tx) - cur
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            let rate = nearEdge ? 4.5 : 2.6   // banks hard near an edge
            let a = cur + max(-rate * dt, min(rate * dt, d)), sp = Brain.zoomSpeed
            s.zoomVX = cos(a) * sp; s.zoomVY = sin(a) * sp
            s.x = min(max(s.x + s.zoomVX! * dt, env.minX - 20), env.maxX + 20)
            s.y = min(max(y + s.zoomVY! * dt, env.topY + 20), env.floorY - 20)
            if abs(s.zoomVX!) > 5 { s.facing = s.zoomVX! > 0 ? 1 : -1 }
            if hypot(f.x1 - s.x, f.y1 - y) < 60 || s.time - f.start > 6 { land(f, env) }   // reached it (or circled long enough): on to the next
            return
        }
        if f.kind == .fly, let id = windowID(f.to) {   // landing on a window that may move, or go
            if let w = env.windows.first(where: { $0.id == id }) { f.x1 = w.box.x + (f.dx ?? 0); f.y1 = w.box.y }
            else {
                s.flight = nil
                if let spot = choosePerch(env) { flyTo(spot, env, takeoff: false) }
                else { flyTo(Spot(perch: "floor", x: min(max(s.x, env.minX), treeX - 60), y: env.floorY), env, takeoff: false) }
                return
            }
        }
        let t = (s.time - f.start) / f.len
        s.flight = f
        if t < 0 { return }   // crouched, about to spring
        if t >= 1 { land(f, env); return }
        switch f.kind {
        case .fly:
            (s.x, s.y) = bezier(f, t)
            if t >= 0.55, s.activity.act == .carry, s.activity.phase == "final", let c = s.carrying {   // lets go of it in mid-air
                let vx = (f.x1 - f.x0) / f.len * 0.7
                s.toss = Toss(id: c, x0: s.x + s.facing * 6, y0: s.y! - (isOwl ? 25 : 20), vx: vx, at: s.time, bounce: isOwl ? nil : 0.45)
                s.carrying = nil; s.activity.phase = "thrown"; s.activity.remaining = 60
            }
        case .fall: s.x = f.x0 + (f.x1 - f.x0) * t; s.y = f.y0 + (f.y1 - f.y0) * t * t
        case .recover: s.x = f.x0 + (f.x1 - f.x0) * t; s.y = f.y0 + (f.y1 - f.y0) * sin(t * .pi / 2)
        }
        if f.kind == .fly, abs(f.x1 - f.x0) > 2 { s.facing = f.x1 > f.x0 ? 1 : -1 }
    }

    mutating func land(_ f: Flight, _ env: Environment) {
        s.flight = nil
        if f.to != "zoom" { s.x = f.x1; s.y = f.y1 }   // a joy flight's waypoints are passed through, not landed on
        if f.kind == .fall && f.to.isEmpty {   // caught itself in mid-air: a few hard flaps
            s.flight = Flight(kind: .recover, x0: s.x, y0: f.y1, x1: s.x + s.facing * 18, y1: f.y1 - 16, vx: s.x, vy: f.y1, start: s.time, len: 0.7, to: "")
            return
        }
        if f.kind == .recover {   // and off to somewhere steadier
            if let spot = choosePerch(env) { flyTo(spot, env, takeoff: false) }
            else { flyTo(Spot(perch: "floor", x: min(max(s.x, env.minX), treeX - 60), y: env.floorY), env, takeoff: false) }
            return
        }
        if f.to == "zoom" {   // a waypoint in mid-air: swoop on to the next, or down to a perch when the laps are done
            let laps = (s.activity.phase.flatMap { Int($0.dropFirst("laps:".count)) } ?? 1) - 1
            s.activity.phase = "laps:\(laps)"
            let heading = (s.zoomVX ?? 0, s.zoomVY ?? -1)   // the way it's flying
            if laps > 0 {
                flyTo(zoomPoint(env, heading: heading), env, takeoff: false)
                s.flight?.len = 1e9
            } else {   // down to the perch most ahead of it
                var best: Spot? = nil, score = -2.0
                for _ in 0..<5 {
                    guard let c = choosePerch(env) else { continue }
                    let dx = c.x - s.x, dy = c.y - (s.y ?? env.floorY), n = max(1, hypot(dx, dy))
                    let ahead = (dx * heading.0 + dy * heading.1) / (n * max(1e-6, hypot(heading.0, heading.1)))
                    if ahead > score { score = ahead; best = c }
                }
                s.zoomVX = nil; s.zoomVY = nil
                flyTo(best ?? Spot(perch: "floor", x: min(max(s.x, env.minX), treeX - 60), y: env.floorY), env, takeoff: false, heading: heading)
            }
            return
        }
        s.perch = f.to; s.perchDX = f.dx
        if f.kind == .fall || (!calm && rand(0...1) < 0.05 + 0.45 * s.personality.clumsy) { s.wobbleUntil = s.time + 0.9 }   // clumsy: wobbly landings
        var a = s.activity
        birdArrive(&a, env)
        s.activity = a
    }

    /// Keeps it on its perch and reacts to its window moving, vanishing or being covered. false: it's leaving.
    mutating func perchTick(_ dt: Double, _ env: Environment) -> Bool {
        let perch = s.perch ?? "floor"
        guard let id = windowID(perch) else {
            s.y = perchY(perch, env) ?? env.floorY
            if perch == "floor", s.activity.destX == nil { s.x = min(max(s.x, env.minX), env.maxX) }
            return true
        }
        guard let w = env.windows.first(where: { $0.id == id }) else { windowGone(closed: env.windowClosed, env); return false }
        let nx = w.box.x + (s.perchDX ?? s.x - w.box.x), ny = w.box.y
        let moved = hypot(nx - s.x, ny - (s.y ?? ny))
        s.x = nx; s.y = ny
        if moved > 0.5 {   // its window is being dragged: it rides along, balancing
            if s.rideSince == nil { s.rideSince = s.time; setEmote("!", 1) }
            s.rideLast = s.time
            s.wobbleUntil = s.time + 0.4
            let hard = moved / max(dt, 0.02) > 1800, long = s.time - (s.rideSince ?? s.time) > 3 + 3 * (1 - s.personality.energy)
            if hard || long || nx < env.minX - 20 || nx > env.maxX + 20 || ny < env.topY + 30 || ny > env.floorY - 60 { flapOff(env); return false }
        } else if let last = s.rideLast, s.time - last > 0.6 { s.rideSince = nil; s.rideLast = nil }
        let covered = env.windows.prefix { $0.id != id }.contains { $0.box.contains(s.x, ny - 14) }
        if covered {   // another window is over it: it leaves after a few seconds
            s.coveredSince = s.coveredSince ?? s.time
            if s.time - s.coveredSince! > 4 { flapOff(env, startled: false); return false }
        } else { s.coveredSince = nil }
        if w.box.y - env.topY < 30 { flapOff(env, startled: false); return false }   // maximised: no room above it
        return true
    }

    /// Its window went. Closed: the ground vanished — a startled fall, a few panicked flaps, then off somewhere else.
    /// Minimised or another Space: it just flies off.
    mutating func windowGone(closed: Bool, _ env: Environment) {
        s.perch = nil; s.perchDX = nil; s.rideSince = nil; s.rideLast = nil; s.coveredSince = nil
        finish()
        guard closed && !calm else { birdStart(.fly, target: nil, env); return }
        s.activity = Activity(act: .react, target: nil, destX: nil, remaining: 1.5, started: s.time)
        setEmote("!", 1.5); s.crestUntil = s.time + 4
        let y0 = s.y ?? env.floorY, drop = min(110, max(0, env.floorY - y0))
        let floor = env.floorY - y0 <= 110
        s.flight = Flight(kind: .fall, x0: s.x, y0: y0, x1: s.x + s.facing * 24, y1: y0 + drop, vx: s.x, vy: y0,
                          start: s.time, len: 0.3 + 0.5 * sqrt(drop / 110), to: floor ? "floor" : "")
    }

    mutating func flapOff(_ env: Environment, startled: Bool = true) {
        s.rideSince = nil; s.rideLast = nil; s.coveredSince = nil
        if startled { s.crestUntil = s.time + 2 }
        finish(); birdStart(.fly, target: nil, env)
    }

    // MARK: - The tick

    mutating func updateBird(_ dt: Double, _ env: Environment) {
        defer { if let c = s.carrying, let i = s.objects.firstIndex(where: { $0.id == c }) { s.objects[i].x = s.x } }   // a toy in its talons goes where it goes
        s.time += dt
        if let t = s.toss, let i = s.objects.firstIndex(where: { $0.id == t.id }) {   // a flung or dropped toy falls (and bounces)
            let e = s.time - t.at, T = t.duration(floorY: env.floorY)
            s.objects[i].x = min(max(t.x0 + t.vx * min(e, T), env.minX), treeX - 60)
            if e >= T { s.toss = nil }
        }
        if var p = s.prey, !p.caught {   // the beetle scuttles, the moth flutters, turning now and then
            p.x += p.vx * dt
            let lo = env.minX + 20, hi = treeX - 70
            if p.x < lo || p.x > hi || s.time >= p.nextTurn { p.vx = -p.vx * (p.x < lo || p.x > hi ? 1 : rand(0.7...1.3)); p.nextTurn = s.time + rand(1.5...4); p.x = min(max(p.x, lo), hi) }
            if p.kind == .moth { p.h = 9 + 6 * sin(s.time * 3.1) }
            s.prey = p
        }
        let circ = clock(env)
        calm = env.reduceMotion
        if s.lastIdle > Brain.awayAfter && env.userIdle < 5 { welcomeBack(env: env) }
        s.lastIdle = env.userIdle
        evolveNeeds(dt, circ: circ)
        decayPreferences(dt)
        if s.emote != nil && s.time > s.emoteUntil { s.emote = nil }
        if let at = s.jumpAt, s.time - at >= (s.jumpLen ?? 0) + Brain.jumpLand { s.jumpAt = nil }
        birdAttention(env)

        if s.flight != nil { flyTick(env, dt); return }   // in the air: nothing else until it lands
        guard perchTick(dt, env) else { return }

        if s.time >= s.nextInterruptCheck {
            s.nextInterruptCheck = s.time + 3
            if shouldInterrupt() { finish(); decide(env); return }
            let a = s.activity.act
            if env.systemBusy && s.activity.target != "house" && a != .eat && a != .drink {   // the Mac's busy: into the birdhouse
                finish(); birdStart(.kennel, target: "house", env); s.busyRetreat = true; return
            }
        }
        var a = s.activity
        if inHouse {   // stays while the Mac is busy, comes out soon after it calms down
            if env.systemBusy { a.remaining = max(a.remaining, 30) }
            else if s.busyRetreat == true { a.remaining = min(a.remaining, rand(20...90)); s.busyRetreat = nil }
        }
        if let dest = a.destX {   // hopping along its perch
            let step = (isOwl ? (a.act == .hunt ? 34 : 18) : Brain.hopSpeed) * dt, d = dest - s.x   // an owl waddles, slowly (quicker, stalking prey)
            if s.jumpAt == nil && !isOwl { jump(height: 7, length: 0.22) }   // birds hop; owls waddle
            if abs(d) <= step { s.x = dest; a.destX = nil; birdArrive(&a, env) }
            else { s.x += d > 0 ? step : -step; s.facing = d > 0 ? 1 : -1 }
            if let id = windowID(s.perch), let w = env.windows.first(where: { $0.id == id }) { s.perchDX = s.x - w.box.x }
        } else {
            a.remaining -= dt
            birdPerform(&a, dt, env)
        }
        s.activity = a
        guard a.remaining <= 0, a.destX == nil else { return }
        if inHouse { s.activity.kennel = .exit; s.activity.remaining = 1.5; return }   // pops out of the entrance first
        if a.act == .hunt { s.prey = nil }   // eaten (or got away)
        if a.act == .carry, let ph = a.phase, ph.hasPrefix("around"), s.carrying != nil {   // off to another perch with it
            let left = Int(ph.dropFirst("around:".count)) ?? 1
            s.activity.phase = left > 1 ? "around:\(left - 1)" : "final"   // on the final flight it lets go partway across
            // roams the whole desktop with it: of a few perches (window tops count double) the furthest away
            var best: Spot? = nil, far = -1.0
            for _ in 0..<4 {
                guard let c = choosePerch(env), !(c.perch == "floor" && left > 1) else { continue }
                let d = abs(c.x - s.x) * (windowID(c.perch) != nil ? 2 : 1)
                if d > far { far = d; best = c }
            }
            if let spot = best ?? choosePerch(env) { flyTo(spot, env) }
            return
        }
        if a.act == .carry, a.phase == "thrown" {   // dropped: once it has landed, an owl swoops after its mouse; a parrot may fetch its ball
            if s.toss != nil { s.activity.remaining = 0.3; return }
            let toy = a.target
            finish()
            if isOwl, let toy { birdStart(.hunt, target: toy, env) }
            else if let toy, rand(0...1) < 0.2 { birdStart(.carry, target: toy, env) }
            else { decide(env) }
            return
        }
        finish(); decide(env)
    }

    /// Notices the cursor only near its perch: a glance and a tilt of the head.
    mutating func birdAttention(_ env: Environment) {
        let near = env.cursorX.map { cx in env.cursorY.map { hypot(cx - s.x, $0 - ((s.y ?? env.floorY) - 24)) < 140 } ?? false } ?? false
        let moved = near && env.cursorX.map { abs($0 - (s.lastCursorX ?? $0)) > 1 } == true
        s.lastCursorX = near ? env.cursorX : nil
        if let until = s.attentionUntil, s.time > until || !near { s.attention = nil; s.attentionUntil = nil }
        guard moved, s.attention == nil, s.time >= (s.attentionCooldown ?? 0), s.flight == nil,
              [.idle, .lookAround, .groom, .hop, .peck].contains(s.activity.act) else { return }
        s.attentionCooldown = s.time + rand(10...30)
        s.attention = .head; s.attentionUntil = s.time + rand(1.5...4)
    }

    // MARK: - You

    /// A click near it: startled, crest up; maybe a hop or a short flight.
    mutating func birdPoke(_ env: Environment) {
        guard s.flight == nil, !inHouse else { return }
        if isOwl && s.activity.act == .sleep {   // woken by day: one slow, unimpressed look at you, then back to sleep
            finish(); s.activity = Activity(act: .idle, target: nil, destX: nil, remaining: rand(3...5), started: s.time); s.activity.front = true
            return
        }
        setEmote("!", 1.2); s.crestUntil = s.time + 3
        finish()
        let r = rand(0...1)
        if r < 0.3 && !calm { birdStart(.fly, target: nil, env); return }
        birdStart(.react, target: nil, env)
        if r < 0.7 { jump(height: 10, length: 0.3) }
    }

    /// You're back after a while: crest up, a little hop, and it faces you wherever it's perched.
    mutating func birdWelcome(_ env: Environment) {
        s.greetBoostUntil = s.time + 180
        guard s.flight == nil, !inHouse, ![.eat, .drink, .react, .greet].contains(s.activity.act) else { return }
        if s.activity.act == .sleep && s.needs.tiredness > 0.55 { return }
        finish()
        s.activity = Activity(act: .greet, target: nil, destX: nil, remaining: rand(4...7), started: s.time)
        s.activity.front = true
        s.crestUntil = s.time + 3
        jump(height: 8, length: 0.3)
        if s.personality.affection > 0.5 { setEmote("♥", 2) }
    }

    /// App relaunch: it's in its birdhouse and comes out soon.
    mutating func birdResume() {
        s.flight = nil; s.perch = "house"; s.perchDX = nil; s.y = nil
        s.x = treeX + peg.dx
        s.activity = Activity(act: .kennel, target: "house", destX: nil, remaining: rand(20...90), started: s.time)
        s.activity.kennel = .inside
    }

    var birdPose: Pose {
        let a = s.activity
        var p = Pose(x: s.x, facing: s.facing, anim: .stand, carrying: s.carrying, emote: s.emote, twitch: s.time < s.twitchUntil)
        p.y = s.y; p.act = a.act
        p.crest = s.time < (s.crestUntil ?? 0) || a.act == .react || a.act == .greet || a.act == .bell
        p.wobble = s.time < (s.wobbleUntil ?? 0)
        if let f = s.flight {
            let t = (s.time - f.start) / f.len
            switch f.kind {
            case .fall: p.flight = .fall
            case .recover: p.flight = .recover
            case .fly:
                if t < 0 { p.flight = .takeoff }
                else if f.to == "zoom" {   // steering about: flaps climbing, glides swooping down (an owl glides most of the way)
                    let vy = s.zoomVY ?? 0
                    p.flight = isOwl ? (vy < -60 ? .flap : .glide) : (vy > 150 ? .glide : .flap)
                }
                else if t > 1 - 0.3 / f.len { p.flight = .flare }   // the last moment before landing: wings back, feet forward (not at a waypoint in mid-air)
                else {
                    let (_, ya) = bezier(f, max(0, t - 0.03)), (_, yb) = bezier(f, min(1, t + 0.03))
                    let sink = (yb - ya) / 0.06 / f.len
                    p.flight = isOwl ? (sink < -60 || t < 0.25 ? .flap : .glide) : sink > 120 ? .glide : .flap   // flaps rising or level, glides down; owls glide most of the way
                }
            }
            p.emote = s.emote
            return p
        }
        if a.destX != nil { p.anim = .walk }
        if let at = s.jumpAt, let len = s.jumpLen, len > 0, s.time >= at, s.time <= at + len { p.jump = (s.time - at) / len; p.jumpHeight = s.jumpHeight ?? 0 }
        if a.act == .sleep && a.destX == nil && (a.target != "house" || a.kennel == .inside) { p.anim = .sleep; p.emote = "z" }
        if inHouse { p.inKennel = true; if p.anim != .sleep { p.anim = .sit } }
        p.attention = s.attention
        if s.attention == .head { p.lookX = s.lastCursorX }
        p.front = a.destX == nil && (a.front == true || a.act == .greet)
        if a.act == .hunt, let at = s.huntAt { p.since = s.time - at; p.toy = a.target == "mouse" }
        if a.act == .carry, let t = s.toss { p.since = s.time - t.at }   // the fling, or watching it bounce
        if a.act == .hunt, let prey = s.prey { p.caught = prey.caught }
        p.preening = a.act == .groom && a.phase != "look"
        if p.anim == .sleep || p.inKennel { p.twitch = s.time < s.twitchUntil }
        return p
    }

    // MARK: - Testing hooks

    /// Debug menu: fly to a window top now (if there's one it may land on).
    public mutating func debugFlyToWindow(env: Environment) {
        guard isBird, let (w, xs) = perchableWindows(env).first else { return }
        let x = xs[xs.count / 2]
        finish()
        s.activity = Activity(act: .fly, target: nil, destX: nil, remaining: 20, started: s.time)
        flyTo(Spot(perch: "w:\(w.id)", x: x, y: w.box.y, dx: x - w.box.x), env)
    }

    /// Debug menu: behave as if the window it's on was just closed.
    public mutating func debugWindowClosed(env: Environment) {
        guard isBird, s.flight == nil, !inHouse else { return }
        windowGone(closed: true, env)
    }
}
