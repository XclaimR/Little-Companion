import Foundation
import Testing
@testable import PetCore

private func env(_ wins: [Win], closed: Bool = false, busy: Bool = false) -> Environment {
    var e = Environment(minX: 40, maxX: 1400, hour: 11, userIdle: 0, cursorX: nil, systemBusy: busy)
    e.floorY = 830; e.topY = 25; e.windows = wins; e.windowClosed = closed
    return e
}
private let editor = Win(id: 1, box: Box(x: 200, y: 300, w: 600, h: 400))

/// A bird sitting on the editor's top edge, 300 pt along.
private func perchedBird(seed: UInt64 = 7) -> Brain {
    var b = Brain(seed: seed, species: .bird)
    b.s.objects = birdHome(maxX: 1400)
    b.s.perch = "w:1"; b.s.perchDX = 300; b.s.x = 500; b.s.y = 300
    b.s.activity = Activity(act: .idle, target: nil, destX: nil, remaining: 600, started: 0)
    b.s.nextInterruptCheck = 1e9
    return b
}

@Test func perchesOnlyOnRoomyUncoveredWindowTops() {
    let narrow = Win(id: 2, box: Box(x: 900, y: 300, w: 150, h: 300))
    let maximised = Win(id: 3, box: Box(x: 0, y: 25, w: 1440, h: 800))
    let e = env([editor, narrow])
    let spots = perchableWindows(e)
    #expect(spots.map(\.win.id) == [1])
    #expect(spots[0].xs.allSatisfy { $0 >= editor.box.x + 90 && $0 <= editor.box.maxX - 24 })   // clear of the traffic lights
    #expect(perchableWindows(env([maximised])).isEmpty)                                        // no room above it
    // A window in front over the right half of the editor's top edge: only the left half is free.
    let front = Win(id: 4, box: Box(x: 500, y: 250, w: 500, h: 300))
    let partly = perchableWindows(env([front, editor])).first { $0.win.id == 1 }!
    #expect(!partly.xs.isEmpty && partly.xs.allSatisfy { $0 < 500 - 24 })
    #expect(perchableWindows(env([Win(id: 5, box: Box(x: 150, y: 250, w: 700, h: 500)), editor])).allSatisfy { $0.win.id != 1 })   // fully covered
}

/// Your screen on 25 Nov: Phone in front of Docker Desktop, Phone's top edge inside Docker's window.
@Test func noPerchWhereAWindowBehindWouldHideIt() {
    var e = env([Win(id: 1, box: Box(x: 202, y: 170, w: 948, h: 640)),     // Phone, in front
                 Win(id: 2, box: Box(x: 54, y: 130, w: 1272, h: 720))])    // Docker Desktop, behind it
    e.topY = 34
    let spots = perchableWindows(e)
    #expect(spots.map(\.win.id) == [2])   // Docker's top edge yes; on Phone's the bird would be behind Docker
    #expect(spots[0].xs.count > 30)
}

@Test func ridesAWindowBeingDragged() {
    var b = perchedBird()
    var w = editor
    for _ in 0..<15 {   // dragged 60 pt right and 15 pt up over 1.5 s
        w.box.x += 4; w.box.y -= 1
        b.update(dt: 0.1, env: env([w]))
        #expect(b.s.perch == "w:1" && b.s.flight == nil)
        #expect(b.s.x == w.box.x + 300 && b.s.y == w.box.y)
    }
    #expect(b.pose.wobble)   // balancing
}

@Test func flapsOffAWindowDraggedHard() {
    var b = perchedBird()
    var w = editor
    w.box.x += 300   // flung 300 pt in a tenth of a second
    b.update(dt: 0.1, env: env([w]))
    #expect(b.s.perch != "w:1" && b.s.flight?.kind == .fly)
}

@Test func fallsAndRecoversWhenItsWindowCloses() {
    var b = perchedBird()
    b.update(dt: 0.1, env: env([], closed: true))
    #expect(b.s.flight?.kind == .fall && b.pose.flight == .fall && b.pose.crest)
    var kinds: [Flight.Kind] = []
    for _ in 0..<200 {
        b.update(dt: 0.05, env: env([]))
        if let k = b.s.flight?.kind, kinds.last != k { kinds.append(k) }
        #expect((25...830).contains(b.s.y ?? 830))
    }
    #expect(kinds.starts(with: [.fall, .recover, .fly]))   // tumbles, catches itself, flies on
    #expect(b.s.flight == nil && b.s.perch != nil && b.s.perch != "w:1")
}

@Test func fliesOffCalmlyWhenItsWindowIsMinimised() {
    var b = perchedBird()
    b.update(dt: 0.1, env: env([], closed: false))
    #expect(b.s.flight?.kind == .fly)
}

@Test func leavesAWindowCoveredByAnother() {
    var b = perchedBird()
    let cover = Win(id: 2, box: Box(x: 400, y: 200, w: 300, h: 300))
    for _ in 0..<30 { b.update(dt: 0.1, env: env([cover, editor])) }
    #expect(b.s.perch == "w:1")   // not straight away
    for _ in 0..<30 { b.update(dt: 0.1, env: env([cover, editor])) }
    #expect(b.s.perch != "w:1")
}

@Test func goesIntoItsBirdhouseWhenTheMacIsBusy() {
    var b = Brain(seed: 3, species: .bird)
    b.s.objects = birdHome(maxX: 1400)
    b.s.x = 300; b.s.perch = "floor"
    for _ in 0..<300 { b.update(dt: 0.1, env: env([], busy: true)) }
    #expect(b.s.activity.target == "house" && b.s.activity.kennel == .inside && b.pose.inKennel)
}

@Test(arguments: [1, 2, 3, 4] as [UInt64])
func aBirdsDayHoldsInvariants(seed: UInt64) {
    let r = simulateBird(seed: seed, hours: 24)
    #expect(r.failures.isEmpty, "\(r.failures.prefix(5))")
}

@Test func aBirdRoundTripsThroughJSON() throws {
    var b = perchedBird()
    b.s.flight = Flight(kind: .fly, x0: 1, y0: 2, x1: 3, y1: 4, vx: 5, vy: 6, start: 7, len: 8, to: "b1", dx: nil)
    let back = try JSONDecoder().decode(DogState.self, from: JSONEncoder().encode(b.s))
    #expect(back == b.s && back.species == .bird)
}

// MARK: - Owls

private func owl(seed: UInt64 = 5) -> Brain {
    var b = Brain(seed: seed, species: .owl)
    b.s.objects = owlHome(maxX: 1400)
    b.s.x = 600
    return b
}
private func at(_ hour: Double) -> Environment { var e = env([]); e.hour = hour; return e }

@Test func anOwlSleepsByDayAndWakesAtNight() {
    var day = owl(), night = owl()
    for _ in 0..<3600 { day.update(dt: 1, env: at(13)) }        // an hour around 1 pm
    #expect(day.s.activity.act == .sleep || day.s.activity.act == .kennel)
    #expect(day.s.activity.target == "house" && day.pose.inKennel)   // in its knothole
    var awake = 0
    for t in 0..<(7 * 3600) {   // through the night, 21:00 to 04:00
        night.update(dt: 1, env: at((21 + Double(t) / 3600).truncatingRemainder(dividingBy: 24)))
        if night.s.activity.act != .sleep && night.s.activity.act != .kennel { awake += 1 }
    }
    #expect(Double(awake) > 0.4 * 7 * 3600, "awake \(awake / 60) min of 7 h of night")   // as simrun: owls rest a while around 2–3 am
}

@Test func anOwlEatsByHuntingPreyAndPlaysWithItsToyMouse() {
    let e = at(23)
    var b = owl()   // a beetle or a moth on the floor: it watches, stalks after it, pounces, mantles over it and gulps it down
    b.s.needs.hunger = 0.9
    b.debugStart(.hunt, target: nil, env: e)
    #expect(b.s.prey != nil)
    var phases: [String] = [], preyMoved = false, firstX = b.s.prey!.x
    for _ in 0..<600 {
        b.update(dt: 0.1, env: e)
        if let p = b.s.prey, !p.caught, abs(p.x - firstX) > 5 { preyMoved = true }
        if let s = b.pose.since, !b.pose.toy {
            let ph = !b.pose.caught ? (b.pose.anim == .walk ? "stalk" : "watch") : s < 5 ? "mantle" : "gulp"
            if phases.last != ph { phases.append(ph) }
        }
        if b.s.activity.act != .hunt { break }
    }
    #expect(preyMoved && b.s.prey == nil && b.s.needs.hunger < 0.2)
    #expect(phases.first == "watch" && phases.contains("stalk") && Array(phases.suffix(2)) == ["mantle", "gulp"], "\(phases)")
    var t = owl()   // the plush mouse is a toy: fun, not food
    t.s.needs.hunger = 0.5; t.s.needs.boredom = 0.8
    t.debugStart(.hunt, target: "mouse", env: e)
    var toy = false
    for _ in 0..<300 { t.update(dt: 0.1, env: e); if t.pose.toy { toy = true } }
    #expect(toy && t.s.needs.hunger >= 0.5 && t.s.needs.boredom < 0.8)
}

@Test func anOwlRollsItsPineconeAlongInsteadOfTeleportingIt() {
    let e = at(23)
    var b = owl()
    b.debugStart(.play, target: "pinecone", env: e)
    var last = b.s.objects.first { $0.id == "pinecone" }!.x, biggest = 0.0, moved = 0.0, jumpsWhileWalking = 0
    for _ in 0..<600 {
        b.update(dt: 0.05, env: e)
        let x = b.s.objects.first { $0.id == "pinecone" }!.x
        biggest = max(biggest, abs(x - last)); moved += abs(x - last); last = x
        if b.s.activity.destX != nil && b.s.jumpAt != nil { jumpsWhileWalking += 1 }
    }
    #expect(moved > 20 && biggest < 6)   // it rolls a few points a tick, never jumps across the floor
    #expect(jumpsWhileWalking == 0)      // owls waddle after it; they don't hop
}

@Test func atNightAnOwlSitsByItsLantern() {
    var b = owl()
    let e = at(22)
    b.debugStart(.idle, target: "lantern", env: e)
    for _ in 0..<100 { b.update(dt: 0.1, env: e) }
    #expect(b.s.perch == "b2" && b.s.facing == 1 && abs(b.s.x - (b.treeX + Oak.branches[2].to)) < 1)
}

@Test func anOwlWokenByDayJustLooksAtYou() {
    var b = owl()
    let e = at(13)
    b.debugStart(.sleep, target: nil, env: e)
    for _ in 0..<5 { b.update(dt: 1, env: e) }
    b.poke(env: e)
    #expect(b.s.activity.act == .idle && b.s.activity.front == true && b.s.emote == nil)   // no startle: a slow look, then back to sleep
}

@Test(arguments: [1, 2, 3, 4] as [UInt64])
func anOwlsDayHoldsInvariants(seed: UInt64) {
    let r = simulateBird(seed: seed, hours: 24, species: .owl)
    #expect(r.failures.isEmpty, "\(r.failures.prefix(5))")
}

/// Carries `toy` about in its beak and drops it in mid-flight: returns (landings with it, dropped in the air, where it lies, followed by).
private func carryAbout(_ b: inout Brain, _ toy: String, _ e: Environment) -> (landings: Int, midAir: Bool, bounced: Bool, lies: Double?, next: Act?) {
    b.debugStart(.carry, target: toy, env: e)
    var landings = 0, midAir = false, bounced = false, wasFlying = false, lastY: Double? = nil, fell = false, tossed = false
    for _ in 0..<4000 {
        b.update(dt: 0.05, env: e)
        let flying = b.s.flight != nil
        if wasFlying && !flying && b.s.carrying == toy { landings += 1 }
        wasFlying = flying
        if let t = b.s.toss {
            tossed = true
            if flying && b.s.carrying == nil { midAir = true }
            let y = t.y(b.s.time - t.at, floorY: e.floorY)
            if let ly = lastY { if y > ly + 0.5 { fell = true } else if fell && y < ly - 0.5 { bounced = true } }
            lastY = y
        }
        if tossed && b.s.toss == nil && b.s.activity.act != .carry { return (landings, midAir, bounced, b.s.objects.first { $0.id == toy }?.x, b.s.activity.act) }
    }
    return (landings, midAir, bounced, nil, nil)
}

@Test func birdsFlyAboutWithAToyInTheirBeakAndDropItInMidFlight() {
    var o = owl()
    let r = carryAbout(&o, "mouse", at(23))
    #expect(r.landings >= 1 && r.midAir && !r.bounced && r.lies != nil && r.next == .hunt)   // the owl swoops after its mouse
    var p = Brain(seed: 4, species: .bird)
    p.s.objects = birdHome(maxX: 1400); p.s.x = 600; p.s.perch = "floor"
    let q = carryAbout(&p, "rattan", env([]))
    #expect(q.landings >= 1 && q.midAir && q.bounced && q.lies != nil)                       // the ball bounces
}

@Test func theFeatherIsGoneFromOwlHomes() {
    var old = owlHome(maxX: 1400) + [PetObject(id: "feather", kind: .feather, x: 1100)]   // an owl saved before it was retired
    repairOwlHome(&old, maxX: 1400)
    #expect(!old.contains { $0.kind == .feather } && !owlHome(maxX: 1400).contains { $0.kind == .feather })
}

@Test func birdsGoOnJoyFlightsAcrossTheDesktopWithoutLandingAtTheTurns() {
    var b = Brain(seed: 2, species: .bird)
    b.s.objects = birdHome(maxX: 1400); b.s.x = 600; b.s.perch = "floor"
    let e = env([])
    b.debugStart(.zoomies, target: nil, env: e)   // a long one, as in the demo
    var xs: [Double] = [], ys: [Double] = [], flares = 0, wasFlare = false, perchedMidway = false, sharpTurns = 0, lastDir: (Double, Double)? = nil, last: (Double, Double)? = nil
    for _ in 0..<6000 {
        b.update(dt: 0.05, env: e)
        if b.s.activity.act != .zoomies || b.s.flight?.to != "zoom" && b.s.activity.phase == "laps:0" { break }
        let flare = b.pose.flight == .flare
        if flare && !wasFlare { flares += 1 }
        wasFlare = flare
        if b.s.flight != nil {
            let y = b.s.y ?? e.floorY
            xs.append(b.s.x); ys.append(y)
            if let l = last, let d0 = lastDir {
                let d = (b.s.x - l.0, y - l.1), n = hypot(d.0, d.1)
                if n > 1, (d.0 * d0.0 + d.1 * d0.1) / (n * hypot(d0.0, d0.1)) < -0.5 { sharpTurns += 1 }   // doubling back within a tick
            }
            if let l = last { let d = (b.s.x - l.0, y - l.1); if hypot(d.0, d.1) > 1 { lastDir = d } }
            last = (b.s.x, y)
        } else if b.s.activity.phase?.hasPrefix("laps") == true { perchedMidway = true }
    }
    #expect(!perchedMidway && flares == 0)                        // never lands, and no landing flare at the turns
    #expect(sharpTurns == 0)                                      // swoops round, never snaps back
    #expect((xs.max()! - xs.min()!) > 800 && (ys.max()! - ys.min()!) > 300)   // all over the desktop
}

@Test func joyFlightsOnlyWhenTheDesktopIsFairlyClear() {
    var b = Brain(seed: 2, species: .bird)
    b.s.objects = birdHome(maxX: 1400); b.s.x = 600; b.s.perch = "floor"
    b.s.needs = Needs(hunger: 0, thirst: 0, tiredness: 0, boredom: 1); b.s.personality.energy = 1
    let clear = env([editor]), busy = env([Win(id: 1, box: Box(x: 40, y: 60, w: 900, h: 700)), Win(id: 2, box: Box(x: 500, y: 100, w: 800, h: 650)), Win(id: 3, box: Box(x: 100, y: 300, w: 600, h: 400))])
    #expect(b.birdCandidates(clear).contains { $0.act == .zoomies })
    #expect(!b.birdCandidates(busy).contains { $0.act == .zoomies })   // three big windows over most of the screen: not now
}

@Test func preeningComesInBoutsAndOnlyCuriousBirdsStopToLookRound() {
    func looks(curiosity: Double) -> Int {
        var b = Brain(seed: 6, species: .bird)
        b.s.objects = birdHome(maxX: 1400); b.s.x = 600; b.s.perch = "floor"
        b.s.personality.curiosity = curiosity
        b.debugStart(.groom, target: nil, env: env([]))
        var n = 0, last: String? = nil
        for _ in 0..<1200 {
            b.s.activity.remaining = 100   // keep it preening for the test
            b.update(dt: 0.1, env: env([]))
            if b.s.activity.phase == "look" && last != "look" { n += 1 }
            last = b.s.activity.phase
        }
        return n
    }
    #expect(looks(curiosity: 0.05) < looks(curiosity: 0.95))
}

@Test func comingToAClearDesktopSometimesGetsAShow() {
    let busy = env([Win(id: 1, box: Box(x: 40, y: 60, w: 900, h: 700)), Win(id: 2, box: Box(x: 500, y: 100, w: 800, h: 650)), Win(id: 3, box: Box(x: 100, y: 300, w: 600, h: 400))])
    var shows = 0
    for seed in 1...60 as ClosedRange<UInt64> {
        var b = Brain(seed: seed, species: .bird)
        b.s.objects = birdHome(maxX: 1400); b.s.x = 600; b.s.perch = "floor"
        b.s.activity = Activity(act: .idle, target: nil, destX: nil, remaining: 600, started: 0); b.s.nextInterruptCheck = 1e9
        for _ in 0..<5 { b.update(dt: 0.1, env: busy) }
        b.update(dt: 0.1, env: env([]))   // you switch to an empty desktop
        if b.s.activity.act == .zoomies || b.s.activity.act == .fly { shows += 1 }
    }
    #expect(shows > 10 && shows < 35, "\(shows) of 60")   // about one time in three, not every time
}
