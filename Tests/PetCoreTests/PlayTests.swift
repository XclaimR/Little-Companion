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

/// A content dog wags in bouts, far more while it is watching you than when it isn't, and never asleep.
@Test func wagsWhenHappyMostlyWhileWatching() {
    func wagTime(watching: Bool) -> Double {
        var total = 0.0
        for seed in 1...6 {
            var b = Brain(seed: UInt64(seed))
            b.s.objects = defaultObjects(width: 1400); b.s.x = 500
            b.s.needs = Needs(hunger: 0, thirst: 0, tiredness: 0, boredom: 0)
            let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: watching ? 520 : nil)
            for _ in 0..<(10 * 120) {
                if watching { b.s.attention = "head"; b.s.attentionUntil = b.s.time + 10 }
                b.s.needs = Needs(hunger: 0, thirst: 0, tiredness: 0, boredom: 0)
                b.update(dt: 0.1, env: env)
                let p = b.pose
                #expect(!(p.wag && p.anim == .sleep))
                if p.wag { total += 0.1 }
            }
        }
        return total
    }
    let watching = wagTime(watching: true), alone = wagTime(watching: false)
    #expect(watching > 30)
    #expect(watching > alone * 3)
}
