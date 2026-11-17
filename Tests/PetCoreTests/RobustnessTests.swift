import Foundation
import Testing
@testable import PetCore

private let env = Environment(minX: 40, maxX: 1360, hour: 11, userIdle: 0, cursorX: nil)

/// A save written before the optional fields existed (jumps, attention, sleep positions, falls, wags, clumsiness…) still loads.
@Test func oldSaveStillLoads() throws {
    var b = Brain(seed: 5)
    b.s.objects = defaultObjects(width: 1400)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b.s)) as! [String: Any]
    for k in ["jumpAt", "jumpLen", "jumpHeight", "attention", "attentionUntil", "attentionCooldown", "lastCursorX", "busyRetreat", "nextRoll",
              "nextDream", "sleepPos", "posTaste", "tossUntil", "wagUntil", "fallAt", "fallKind", "fallSpeed", "pendingCarry"] { json[k] = nil }
    var p = json["personality"] as! [String: Any]; p["clumsiness"] = nil; json["personality"] = p
    var a = json["activity"] as! [String: Any]; for k in ["running", "front", "back", "phase"] { a[k] = nil }; json["activity"] = a
    let old = try JSONDecoder().decode(DogState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.personality.clumsy == 0.35)
    var brain = Brain(state: old)
    for _ in 0..<600 { brain.update(dt: 1, env: env) }   // and it carries on living
}

/// Back after a night away: needs drift toward neutral and it wakes in its favourite sleeping spot.
@Test func resumeAfterANightAway() {
    var b = Brain(seed: 8)
    b.s.objects = defaultObjects(width: 1400)
    b.s.needs = Needs(hunger: 0.9, thirst: 0.9, tiredness: 0.9, boredom: 0.9)
    b.s.learned["bed"] = 0.9
    b.resume(afterOffline: 10 * 3600)
    #expect(abs(b.s.needs.hunger - 0.3) < 0.01 && abs(b.s.needs.tiredness - 0.2) < 0.01)
    #expect(b.s.activity.act == .sleep && b.s.activity.target == "bed")
    #expect(b.s.x == b.s.objects.first { $0.id == "bed" }!.x)
}

/// Catching up a delayed timer in one go lives the same seconds as ticking through them.
@Test func catchUpMatchesTicking() {
    var a = Brain(seed: 13), b = Brain(seed: 13)
    a.s.objects = defaultObjects(width: 1400); b.s.objects = a.s.objects
    a.advance(by: 40, env: env)
    for _ in 0..<40 { b.update(dt: 1, env: env) }
    #expect(a.s == b.s)
}

/// Coming back with the cursor far from the floor: a light dozer sits up facing you and wags; a deep sleeper lets you be.
@Test func welcomeBackInPlace() {
    var b = Brain(seed: 21)
    b.s.objects = defaultObjects(width: 1400)
    b.debugStart(.sleep, target: "bed", env: env)
    for _ in 0..<60 { b.update(dt: 1, env: env) }
    b.s.needs.tiredness = 0.3
    b.welcomeBack(env: env)
    #expect(b.s.activity.act == .sit && b.pose.front && b.pose.wag)

    var deep = Brain(seed: 21)
    deep.s.objects = defaultObjects(width: 1400)
    deep.debugStart(.sleep, target: "bed", env: env)
    for _ in 0..<60 { deep.update(dt: 1, env: env) }
    deep.s.needs.tiredness = 0.9
    deep.welcomeBack(env: env)
    #expect(deep.s.activity.act == .sleep)

    // and the same happens on its own when you return after being away (idle → active)
    var c = Brain(seed: 4)
    c.s.objects = defaultObjects(width: 1400)
    c.debugStart(.sit, target: nil, env: env)
    var away = env; away.userIdle = 900
    c.update(dt: 1, env: away)
    c.update(dt: 1, env: env)
    #expect(c.s.time < c.s.greetBoostUntil)
}

/// Reduce Motion: no jumps, zoomies or tumbles, and it never runs.
@Test func reduceMotionIsCalm() {
    var calm = env; calm.reduceMotion = true
    for seed in 1...3 {
        var b = Brain(seed: UInt64(seed))
        b.s.objects = defaultObjects(width: 1400)
        b.s.personality.clumsiness = 0.95; b.s.personality.energy = 0.95; b.s.personality.playfulness = 0.95
        b.s.needs.boredom = 1; b.s.needs.tiredness = 0   // would be zoomies weather
        for i in 0..<(4 * 3600) {
            if i % 300 == 0 { b.debugStart([.play, .wander, .follow, .carry][i / 300 % 4], target: [0, 3].contains(i / 300 % 4) ? "ball" : nil, env: calm) }
            b.update(dt: 1, env: calm)
            #expect(b.s.jumpAt == nil && b.s.fallAt == nil && b.s.activity.running != true)
            #expect(b.s.activity.act != .zoomies)
        }
    }
}

/// A home is tidied: a kennel exists, nothing overlaps it, and everything is inside the floor.
@Test func homeRepair() {
    var objs = [PetObject(id: "bed", kind: .bed, x: 70), PetObject(id: "ball", kind: .ball, x: 5000)]
    repairHome(&objs, minX: 40, maxX: 1360) { $0.kind == .kennel ? 50 : 30 }
    let k = objs.first { $0.kind == .kennel }!, bed = objs.first { $0.id == "bed" }!
    #expect(bed.x - 30 >= k.x + 50)
    #expect(objs.allSatisfy { $0.x >= 40 && $0.x <= 1360 })
}
