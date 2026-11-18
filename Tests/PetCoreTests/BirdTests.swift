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
    #expect(Double(awake) > 0.5 * 7 * 3600, "awake \(awake / 60) min of 7 h of night")
}

@Test func anOwlEatsByHuntingItsMouse() {
    var b = owl()
    b.s.needs.hunger = 0.9
    let e = at(23)
    b.debugStart(.hunt, target: "mouse", env: e)
    var pounced = false, kinds: Set<String> = []
    for _ in 0..<400 {
        b.update(dt: 0.1, env: e)
        if let s = b.pose.since { kinds.insert(s < 3 ? "stare" : s < 6 ? "mantle" : "eat") }
        if b.s.jumpAt != nil && b.s.activity.act == .hunt { pounced = true }
    }
    #expect(kinds == ["stare", "mantle", "eat"] && pounced)
    #expect(b.s.needs.hunger < 0.2)
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
