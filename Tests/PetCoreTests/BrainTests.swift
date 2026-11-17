import Foundation
import Testing
@testable import PetCore

@Test(arguments: [1, 2, 3, 4, 5, 6] as [UInt64])
func aDayAloneHoldsInvariants(seed: UInt64) {
    let r = simulate(seed: seed, hours: 24)
    #expect(r.failures.isEmpty, "\(r.failures.prefix(5))")
}

@Test func jumpsRunsAndCursorReactionsHappen() {
    let days = (1...4).map { simulate(seed: UInt64($0), hours: 24) }
    #expect(days.allSatisfy { $0.jumps > 0 }, "\(days.map(\.jumps))")
    #expect(days.map(\.runs).reduce(0, +) > 0)
    #expect(days.map(\.glances).reduce(0, +) > 0 && days.map(\.turns).reduce(0, +) > 0 && days.map(\.follows).reduce(0, +) > 0)
}

@Test func clickingASleepingDogCanStartleItAwake() {
    var b = Brain(seed: 3)
    let env = Environment(minX: 40, maxX: 1400, hour: 14, userIdle: 0, cursorX: nil)
    b.s.needs.tiredness = 0   // rested enough that it always wakes
    var woke = false
    for _ in 0..<20 {
        b.s.activity = Activity(act: .sleep, target: nil, destX: nil, remaining: 600, started: b.s.time)
        b.s.jumpAt = nil
        b.poke(env: env)
        if b.s.activity.act == .react { woke = true; #expect(b.s.jumpAt != nil && b.s.emote == "!") }
    }
    #expect(woke)
}

@Test func goesIntoTheKennelWhenTheMacIsBusy() {
    var b = Brain(seed: 11)
    b.s.objects = defaultObjects(width: 1400)
    b.s.x = 900
    b.s.activity = Activity(act: .idle, target: nil, destX: nil, remaining: 5, started: 0)
    let busy = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil, systemBusy: true)
    for _ in 0..<(5 * 60 * 5) { b.update(dt: 0.2, env: busy) }   // 5 busy minutes
    #expect(b.s.activity.act == .kennel && b.s.activity.phase == "inside" && b.pose.inKennel)
    let calm = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)
    for _ in 0..<(3 * 60 * 5) { b.update(dt: 0.2, env: calm) }    // comes out within a few minutes once it's quiet
    #expect(b.s.activity.act != .kennel)   // walked back out through the door
}

@Test func sameSeedSameDay() {
    let a = simulate(seed: 42, hours: 6), b = simulate(seed: 42, hours: 6)
    #expect(a.actTime == b.actTime)
    #expect(a.prefs == b.prefs)
}

@Test func differentDogsLiveDifferently() {
    let days = (1...4).map { simulate(seed: UInt64($0), hours: 24) }
    let toys: Set = ["ball", "plush", "rope", "tennis"]
    let favouriteToys = Set(days.map { d in d.prefs.filter { toys.contains($0.key) }.max { $0.value < $1.value }!.key })
    #expect(favouriteToys.count >= 2, "every dog picked the same favourite toy: \(favouriteToys)")
    // How differently two dogs split their day (sum of share differences across activities).
    var maxDistance = 0.0
    for a in days { for b in days { maxDistance = max(maxDistance, Act.allCases.map { abs(a.share($0) - b.share($0)) }.reduce(0, +)) } }
    #expect(maxDistance > 0.1, "daily routines nearly identical: \(maxDistance)")
}

@Test func enjoyableToyBecomesFavourite() {
    var b = Brain(seed: 7)
    b.s.innate[.ball] = 0.8
    b.s.objects = [PetObject(id: "ball", kind: .ball, x: 300)]
    let before = b.pref(b.s.objects[0])
    for _ in 0..<20 { b.s.activity = Activity(act: .play, target: "ball", destX: nil, remaining: 0, started: 0); b.finish() }
    #expect(b.pref(b.s.objects[0]) > before + 0.3)
}

@Test func stateRoundTripsThroughJSON() throws {
    let r = Brain(seed: 9).s
    let back = try JSONDecoder().decode(DogState.self, from: JSONEncoder().encode(r))
    #expect(back == r)
}
