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

/// A standing jump crouches, flies forward along an arc that peaks mid-way, then lands in a crouch.
@Test func standingJumpArcsForward() {
    var b = Brain(seed: 3)
    b.s.objects = defaultObjects(width: 1400); b.s.x = 500; b.s.facing = 1
    let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)
    b.debugStart(.sit, target: nil, env: env)
    b.jump(height: 20, length: 0.5)
    var stages: [String] = [], peak = 0.0
    let x0 = b.s.x
    for _ in 0..<12 {
        b.update(dt: 0.07, env: env)
        let p = b.pose
        let st = p.crouch ? "crouch" : p.jump != nil ? "air" : "ground"
        if stages.last != st { stages.append(st) }
        if let j = p.jump { peak = max(peak, 4 * j * (1 - j)) }
    }
    #expect(stages == ["crouch", "air", "crouch", "ground"])
    #expect(b.s.x - x0 > 12)   // travelled forward, not just up and down
    #expect(peak > 0.9)
}

/// Clumsy dogs trip and tumble on the move, graceful ones hardly ever; a tumble runs trip → roll → sprawl → up → sheepish and then carries on.
@Test func clumsyDogsFallOver() {
    func falls(_ clumsiness: Double) -> Int {
        var n = 0
        for seed in 1...4 {
            var b = Brain(seed: UInt64(seed))
            b.s.personality.clumsiness = clumsiness
            b.s.objects = defaultObjects(width: 1400); b.s.x = 500
            let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)
            for i in 0..<(10 * 1800) {
                if i % 100 == 0 { b.debugStart(.zoomies, target: nil, env: env) }   // keep it sprinting
                let was = b.s.fallAt
                b.update(dt: 0.1, env: env)
                if was == nil && b.s.fallAt != nil { n += 1 }
            }
        }
        return n
    }
    let clumsy = falls(0.95), graceful = falls(0.05)
    #expect(clumsy >= 10)
    #expect(clumsy > graceful * 4)

    var b = Brain(seed: 9)
    b.s.objects = defaultObjects(width: 1400); b.s.x = 500
    let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)
    b.debugStart(.zoomies, target: nil, env: env)
    b.update(dt: 0.1, env: env)
    b.debugFall(tumble: true)
    var stages: [String] = []
    for _ in 0..<30 {
        b.update(dt: 0.1, env: env)
        let f = b.pose.fall ?? "-"
        if stages.last != f { stages.append(f) }
    }
    #expect(stages == ["trip", "roll", "sprawl", "up", "sheepish", "-"])
}
