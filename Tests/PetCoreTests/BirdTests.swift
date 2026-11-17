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
