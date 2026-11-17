import Testing
@testable import PetCore

/// Grab-and-shake toys stay in its mouth for the whole game (including the steps it wanders with them).
@Test func plushStaysInMouthWhilePlaying() {
    var b = Brain(seed: 21)
    b.s.objects = defaultObjects(width: 1400)
    b.s.x = 500
    let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)
    b.debugStart(.play, target: "plush", env: env)
    var log: [String] = []
    for i in 0..<(60 * 10) {
        b.update(dt: 0.1, env: env)
        let a = b.s.activity
        if a.act == .play && a.destX == nil && b.s.carrying == nil && b.s.time > a.started + 15 { log.append("t\(i) dropped while playing") }
        if a.act != .play { log.append("t\(i) ended: \(a.act)"); break }
    }
    #expect(!log.contains { $0.contains("dropped") })
}
