import Foundation

/// What kind of pet. One engine: a species is its acts, its home and how it moves (dogs walk the floor;
/// birds hop and fly between perches at different heights).
public enum Species: String, Codable, Sendable { case dog, bird }

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
    public static let branches = [Ledge(from: -26 * k, to: -12 * k, h: 44 * k),   // b0: the swing hangs from it
                                  Ledge(from: 10 * k, to: 20 * k, h: 40 * k),     // b1: the bell hangs from its tip
                                  Ledge(from: -26 * k, to: -14 * k, h: 64 * k),   // b2
                                  Ledge(from: 8 * k, to: 22 * k, h: 66 * k)]      // b3, under the crown
    public static let swing = (dx: -19 * k, h: 10 * k)   // the seat
    public static let bell = (dx: 12 * k, h: 40 * k)     // sitting on b1, beak level with the bell hanging from b3
    public static let house = (dx: 0.0, h: 48 * k)        // the peg under the round entrance
    public static let entrance = (dx: 0.0, h: 54 * k)     // centre of the entrance, where its shadow shows
    public static let halfWidth = 32 * k
}

/// A bird's home: its tree at the right end of the floor, seed and water dishes at its foot on the left.
public func birdHome(maxX: Double) -> [PetObject] {
    var o = [PetObject(id: "tree", kind: .tree, x: 0), PetObject(id: "seeds", kind: .seedDish, x: 0), PetObject(id: "birdbath", kind: .waterDish, x: 0)]
    repairBirdHome(&o, maxX: maxX)
    return o
}

/// The tree stays pinned at the right end and the dishes at its foot (nothing in a bird's home moves yet).
public func repairBirdHome(_ objects: inout [PetObject], maxX: Double) {
    for (id, kind) in [("tree", Kind.tree), ("seeds", .seedDish), ("birdbath", .waterDish)] where !objects.contains(where: { $0.kind == kind }) {
        objects.append(PetObject(id: id, kind: kind, x: 0))
    }
    let tx = maxX - 10
    for i in objects.indices {
        switch objects[i].kind {
        case .tree: objects[i].x = tx
        case .seedDish: objects[i].x = tx - 112
        case .waterDish: objects[i].x = tx - 76
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
    var isBird: Bool { s.species == .bird }
    static let flySpeed = 230.0, hopSpeed = 50.0, takeoff = 0.3

    func object(_ kind: Kind) -> PetObject? { s.objects.first { $0.kind == kind } }
    var treeX: Double { object(.tree)?.x ?? 1000 }
    func windowID(_ perch: String?) -> Int? { perch.flatMap { $0.hasPrefix("w:") ? Int($0.dropFirst(2)) : nil } }
    func branch(_ perch: String?) -> Int? {
        guard let p = perch, p.hasPrefix("b"), let i = Int(p.dropFirst()), Tree.branches.indices.contains(i) else { return nil }
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
        case "house": return env.floorY - Tree.house.h
        default:
            if let id = windowID(perch) { return env.windows.first { $0.id == id }?.box.y }
            return branch(perch).map { env.floorY - Tree.branches[$0].h }
        }
    }

    /// How far it can hop along a perch (nil: a single spot, like the swing).
    func perchRange(_ perch: String, _ env: Environment) -> ClosedRange<Double>? {
        if perch == "floor" { return env.minX...max(env.minX, treeX - 40) }
        if let id = windowID(perch), let w = env.windows.first(where: { $0.id == id }) {
            let lo = max(w.box.x + 96, env.minX), hi = min(w.box.maxX - 24, env.maxX)
            return lo <= hi ? lo...hi : nil
        }
        return branch(perch).map { treeX + Tree.branches[$0].from ... treeX + Tree.branches[$0].to }
    }

    // MARK: - Choosing where to go

    /// A new perch: a branch, the floor or a window top. Curious birds visit windows more; `nearYou` picks the window
    /// top closest to where you've been working.
    mutating func choosePerch(_ env: Environment, nearYou: Bool = false) -> Spot? {
        var options: [(Spot, Double)] = []
        if !nearYou {
            for (i, b) in Tree.branches.enumerated() where "b\(i)" != s.perch {
                options.append((Spot(perch: "b\(i)", x: treeX + rand(b.from...b.to), y: env.floorY - b.h), 1))
            }
            if s.perch != "floor" { options.append((Spot(perch: "floor", x: rand(env.minX...max(env.minX, treeX - 60)), y: env.floorY), 0.9)) }
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
        let n = s.needs, p = s.personality, circ = Self.sleepiness(hour: env.hour)
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
        c.append(.init(act: .swing, target: nil, score: 0.2 * fun))
        c.append(.init(act: .bell, target: nil, score: 0.2 * fun))
        let onGround = s.perch == "floor" || windowID(s.perch) != nil
        c.append(.init(act: .fly, target: nil, score: 0.18 * (0.2 + p.energy) * (1 - 0.6 * n.tiredness) * (1 - 0.85 * circ)))   // energetic birds fly more
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
        if act == .sleep { a.remaining *= 1 + 2 * Self.sleepiness(hour: env.hour) }
        let here = s.perch ?? "air", fy = env.floorY   // no perch: its window just went from under it
        var spot: Spot?
        switch act {
        case .fly:
            spot = choosePerch(env, nearYou: target == "you")
            if target == "you" { s.lastNearYou = s.time }
        case .eat: if let o = object(.seedDish) { spot = Spot(perch: "floor", x: o.x + (s.x < o.x ? -16 : 16), y: fy) }
        case .drink: if let o = object(.waterDish) { spot = Spot(perch: "floor", x: o.x + (s.x < o.x ? -16 : 16), y: fy) }
        case .splash: if let o = object(.waterDish) { spot = Spot(perch: "floor", x: o.x, y: fy) }   // right in it
        case .swing: spot = Spot(perch: "swing", x: treeX + Tree.swing.dx, y: fy - Tree.swing.h)
        case .bell: spot = Spot(perch: "bell", x: treeX + Tree.bell.dx, y: fy - Tree.bell.h)
        case .kennel:
            spot = Spot(perch: "house", x: treeX + Tree.house.dx, y: fy - Tree.house.h); a.kennel = .door
        case .sleep where target == "house":
            spot = Spot(perch: "house", x: treeX + Tree.house.dx, y: fy - Tree.house.h); a.kennel = .door
        case .sleep where branch(here) == nil:   // a daytime nap, fluffed up on a branch
            let i = Int.random(in: Tree.branches.indices, using: &s.rng), b = Tree.branches[i]
            spot = Spot(perch: "b\(i)", x: treeX + rand(b.from...b.to), y: fy - b.h)
        case .peck where here != "floor":
            spot = Spot(perch: "floor", x: rand(env.minX...max(env.minX, treeX - 60)), y: fy)
        case .hop:
            if let r = perchRange(here, env) { a.destX = min(max(s.x + (rand(0...1) < 0.5 ? -1 : 1) * rand(20...70), r.lowerBound), r.upperBound) }
        default: break
        }
        if let spot {
            if spot.perch == here, let r = perchRange(here, env) {
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
        if a.target == "house" && (a.act == .kennel || a.act == .sleep) && a.kennel == .door { a.kennel = .inside; s.perch = "house" }
        if a.act == .lookAround || a.act == .idle { a.front = rand(0...1) < 0.15 + 0.3 * s.personality.affection }
        if a.act == .greet { a.front = true }
    }

    mutating func birdPerform(_ a: inout Activity, _ dt: Double, _ env: Environment) {
        switch a.act {
        case .eat:
            s.needs.hunger -= dt / 20
            if s.needs.hunger <= 0 { a.remaining = 0 }
        case .drink:
            s.needs.thirst -= dt / 8
            if s.needs.thirst <= 0 { a.remaining = 0 }
        case .splash: s.needs.boredom -= dt / 60; s.needs.thirst -= dt / 40
        case .swing, .bell: s.needs.boredom -= dt / 40
        case .sleep:
            if a.target != "house" || a.kennel == .inside {
                if s.needs.tiredness <= 0.02 && Self.sleepiness(hour: env.hour) < 0.6 { a.remaining = 0 }
                dreamTick()
            }
        case .kennel: if a.kennel == .inside && s.needs.tiredness > 0.3 { dreamTick() }
        case .lookAround: if rand(0...1) < dt * 0.6 { s.facing = -s.facing }
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
    mutating func flyTo(_ spot: Spot, _ env: Environment, takeoff: Bool = true) {
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
                          start: s.time + (takeoff ? Brain.takeoff : 0), len: max(0.8, dist / Brain.flySpeed + 0.3), to: spot.perch, dx: spot.dx)
        s.perch = nil; s.perchDX = nil; s.rideSince = nil; s.coveredSince = nil; s.jumpAt = nil
        if abs(spot.x - x0) > 2 { s.facing = spot.x > x0 ? 1 : -1 }
    }

    mutating func flyTick(_ env: Environment) {
        guard var f = s.flight else { return }
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
        case .fly: (s.x, s.y) = bezier(f, t)
        case .fall: s.x = f.x0 + (f.x1 - f.x0) * t; s.y = f.y0 + (f.y1 - f.y0) * t * t
        case .recover: s.x = f.x0 + (f.x1 - f.x0) * t; s.y = f.y0 + (f.y1 - f.y0) * sin(t * .pi / 2)
        }
        if f.kind == .fly, abs(f.x1 - f.x0) > 2 { s.facing = f.x1 > f.x0 ? 1 : -1 }
    }

    mutating func land(_ f: Flight, _ env: Environment) {
        s.flight = nil
        s.x = f.x1; s.y = f.y1
        if f.kind == .fall && f.to.isEmpty {   // caught itself in mid-air: a few hard flaps
            s.flight = Flight(kind: .recover, x0: s.x, y0: f.y1, x1: s.x + s.facing * 18, y1: f.y1 - 16, vx: s.x, vy: f.y1, start: s.time, len: 0.7, to: "")
            return
        }
        if f.kind == .recover {   // and off to somewhere steadier
            if let spot = choosePerch(env) { flyTo(spot, env, takeoff: false) }
            else { flyTo(Spot(perch: "floor", x: min(max(s.x, env.minX), treeX - 60), y: env.floorY), env, takeoff: false) }
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
        s.time += dt
        let circ = Self.sleepiness(hour: env.hour)
        calm = env.reduceMotion
        if s.lastIdle > Brain.awayAfter && env.userIdle < 5 { welcomeBack(env: env) }
        s.lastIdle = env.userIdle
        evolveNeeds(dt, circ: circ)
        decayPreferences(dt)
        if s.emote != nil && s.time > s.emoteUntil { s.emote = nil }
        if let at = s.jumpAt, s.time - at >= (s.jumpLen ?? 0) + Brain.jumpLand { s.jumpAt = nil }
        birdAttention(env)

        if s.flight != nil { flyTick(env); return }   // in the air: nothing else until it lands
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
            let step = Brain.hopSpeed * dt, d = dest - s.x
            if s.jumpAt == nil { jump(height: 7, length: 0.22) }
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
        s.x = treeX + Tree.house.dx
        s.activity = Activity(act: .kennel, target: "house", destX: nil, remaining: rand(20...90), started: s.time)
        s.activity.kennel = .inside
    }

    var birdPose: Pose {
        let a = s.activity
        var p = Pose(x: s.x, facing: s.facing, anim: .stand, carrying: nil, emote: s.emote, twitch: s.time < s.twitchUntil)
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
                else if t > 1 - 0.3 / f.len { p.flight = .flare }   // the last moment: wings back, feet forward
                else {
                    let (_, ya) = bezier(f, max(0, t - 0.03)), (_, yb) = bezier(f, min(1, t + 0.03))
                    p.flight = (yb - ya) / 0.06 / f.len > 120 ? .glide : .flap   // flaps rising or level, glides down
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
