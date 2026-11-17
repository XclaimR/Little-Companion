import Foundation

/// Utility-AI brain: every decision scores all possible (act, target) pairs from needs, personality,
/// preferences, environment, history and noise, then picks one at random weighted by score.
/// Rules are deterministic; all randomness comes from the dog's seeded RNG.
public struct Brain: Sendable {
    public var s: DogState
    /// Top candidates of the last decision, for the debug overlay.
    public private(set) var lastScores: [String] = []

    public init(seed: UInt64) {
        var rng = SplitMix(seed: seed)
        let p = Personality.random(&rng)
        var innate: [Kind: Double] = [:]
        for k in Kind.allCases { innate[k] = Double.random(in: -0.5...0.8, using: &rng) }
        s = DogState(personality: p, innate: innate,
                     activity: Activity(act: .idle, target: nil, destX: nil, remaining: 3, started: 0), rng: rng)
    }

    public init(state: DogState) { s = state }

    // MARK: - Public API

    public mutating func update(dt: Double, env: Environment) {
        s.time += dt
        let circ = Self.sleepiness(hour: env.hour)
        if s.lastIdle > 600 && env.userIdle < 5 { s.greetBoostUntil = s.time + 180 } // you came back
        s.lastIdle = env.userIdle
        evolveNeeds(dt, circ: circ)
        decayPreferences(dt)
        s.x = min(max(s.x, env.minX), env.maxX)
        if s.emote != nil && s.time > s.emoteUntil { s.emote = nil }
        if let at = s.jumpAt, s.time - at >= (s.jumpLen ?? 0) + Brain.jumpLand { s.jumpAt = nil }
        if let at = s.jumpAt, let len = s.jumpLen, len > 0, s.time >= at, s.time < at + len, s.activity.destX == nil {
            // a standing jump still carries it forward, about as far as it rises, so it flies an arc rather than bobbing up and down
            s.x = min(max(s.x + s.facing * 0.9 * (s.jumpHeight ?? 0) / len * dt, env.minX), env.maxX)
        }
        updateAttention(dt, env: env)
        maybeJump(dt, circ: circ)
        if s.carrying != nil, s.jumpAt == nil, s.activity.act == .carry || s.activity.act == .play,
           rand(0...1) < dt * 0.12 * (0.3 + s.personality.playfulness) * mood {
            s.tossUntil = s.time + 0.7; jump(height: 10, length: 0.5)   // flings it up and catches it
        }
        if s.activity.act != .sleep, s.time >= (s.wagUntil ?? 0) {   // tail wags: random bouts when happy, far likelier while it's looking at you
            let watching = s.attention != nil || s.activity.front == true
            if rand(0...1) < dt * (watching ? 0.3 : 0.03) * (0.3 + s.personality.affection) * mood * mood { s.wagUntil = s.time + rand(1.2...3.5) }
        }
        if let at = s.fallAt {   // mid-stumble
            let t = s.time - at
            if t >= (s.fallKind == "tumble" ? Brain.tumbleLen : Brain.tripLen) { s.fallAt = nil; s.fallKind = nil; s.fallSpeed = nil }
            else if s.fallKind == "tumble" {   // everything waits until it's back on its feet; it skids a little first
                if t < 0.45 { s.x = min(max(s.x + s.facing * (s.fallSpeed ?? 60) * (1 - t / 0.45) * dt, env.minX), env.maxX) }
                return
            }
        } else if let fast = movingGait, s.jumpAt == nil, s.carrying == nil, s.activity.act != .kennel,
                  rand(0...1) < dt * s.personality.clumsy * (fast ? 0.012 : 0.002) * (0.6 + s.needs.tiredness) {
            fall(tumble: rand(0...1) < (fast ? 0.5 : 0.15))   // clumsy paws: likelier running and tired, and a tumble mostly at speed
        }

        if s.time >= s.nextInterruptCheck {
            s.nextInterruptCheck = s.time + 3
            if shouldInterrupt() { finish(); decide(env); return }
            if env.systemBusy, let k = s.objects.first(where: { $0.kind == .kennel }) {
                let a = s.activity.act, lying = a == .sleep && s.activity.destX == nil
                if a != .kennel && !lying && a != .eat && a != .drink {   // a dog asleep costs nothing to draw; leave it be
                    finish(); start(.kennel, target: k.id, env); s.activity.running = true; s.busyRetreat = true; return
                }
            }
        }

        var a = s.activity
        if a.act == .kennel && a.phase == "inside" && a.destX == nil {   // inside: stay while the Mac is busy, come out soon after it calms down
            if env.systemBusy { a.remaining = max(a.remaining, 30) }
            else if s.busyRetreat == true { a.remaining = min(a.remaining, rand(20...90)); s.busyRetreat = nil }
        }
        if a.act == .follow {   // keep steering toward the cursor; stop a little short of it
            if let cx = env.cursorX {
                if abs(cx - s.x) > 46 { a.destX = cx + (s.x < cx ? -34 : 34) }
                else if a.destX == nil { s.facing = cx >= s.x ? 1 : -1 }
            } else { a.destX = nil; a.remaining = min(a.remaining, 0.5) }
        }
        if let dest = a.destX {
            let dest = min(max(dest, env.minX), env.maxX)
            let step = (a.running == true && a.act != .zoomies ? 130 : a.act.speed) * dt * (s.fallKind == "trip" ? 0.4 : 1)   // tripping: staggers on, slower
            let d = dest - s.x
            if abs(d) <= step {
                s.x = dest
                a.destX = nil
                arrive(&a, env)
            } else {
                s.x += d > 0 ? step : -step
                s.facing = d > 0 ? 1 : -1
            }
            if a.act == .zoomies || a.act == .follow || a.act == .play { a.remaining -= dt }
        } else {
            a.remaining -= dt
            perform(&a, dt, env)
        }
        s.activity = a
        if let c = s.carrying, let i = s.objects.firstIndex(where: { $0.id == c }) { s.objects[i].x = s.x + 36 * s.facing }
        if a.remaining <= 0 && (a.destX == nil || a.act == .zoomies || a.act == .follow || a.act == .play) && !(a.act == .kennel && a.phase != "exit") { finish(); decide(env) }
        if s.activity.act == .sleep && s.activity.destX == nil { s.jumpAt = nil }   // never mid-air while lying asleep
        if s.activity.act == .kennel, s.activity.remaining <= 0, s.activity.phase == "inside" || s.activity.phase == "enter",
           let k = s.objects.first(where: { $0.kind == .kennel }) {   // time's up: walk back out through the door first
            s.activity.phase = "exit"; s.activity.destX = k.x + Self.kennelDoorOutside; s.activity.remaining = 1
        }
    }

    /// A click on the dog: a nudge it may ignore, never a command.
    public mutating func poke(env: Environment) {
        let a = s.activity
        if a.act == .kennel && a.phase != "door" { return }   // can't be clicked while it's in its kennel
        if a.act == .sleep && a.destX == nil {
            if rand(0...1) < 0.25 + 0.5 * (1 - s.needs.tiredness) {
                startle(env: env)   // jolted awake
            } else {
                s.twitchUntil = s.time + 0.6 // stirs, resettles
            }
        } else if a.act != .react && a.act != .eat && a.act != .drink {
            guard rand(0...1) < 0.5 + 0.4 * s.personality.affection else { return } // ignored you
            if s.personality.affection > 0.5 { setEmote("♥", 2) }
            finish()
            start(.react, target: nil, env)
        }
    }

    public mutating func add(_ o: PetObject, env: Environment) {
        var o = o
        o.addedAt = s.time
        s.objects.append(o)
        let a = s.activity.act
        if a != .sleep && abs(o.x - s.x) < 90 { startle(env: env, strength: 0.5) }   // something just landed next to it
        guard a != .sleep && a != .eat && a != .drink, rand(0...1) < 0.3 + 0.6 * s.personality.curiosity else { return }
        setEmote("!", 1.5)
        finish()
        start(.sniff, target: o.id, env)
    }

    /// Testing hook: start an act right now (e.g. "play" with "ball"). Not used by the dog itself.
    public mutating func debugStart(_ act: Act, target: String?, env: Environment) {
        s.attention = nil
        finish(); start(act, target: target, env)
        if act == .kennel, s.objects.contains(where: { $0.id == target }) { s.activity.running = true }
        if act == .sleep { s.needs.tiredness = max(s.needs.tiredness, 0.6); s.nextDream = s.time + 4 }   // dream soon, for testing
        else { s.wagUntil = s.time + 6 }   // wag straight away, for testing
    }

    /// App relaunch: needs drift toward neutral (capped) and the dog wakes in its favourite sleeping spot.
    public mutating func resume(afterOffline secs: Double) {
        let k = min(1, max(0, secs) / (8 * 3600))
        s.needs.hunger += (0.3 - s.needs.hunger) * k
        s.needs.thirst += (0.3 - s.needs.thirst) * k
        s.needs.tiredness += (0.2 - s.needs.tiredness) * k
        s.needs.boredom += (0.3 - s.needs.boredom) * k
        var spot = s.objects.filter { $0.kind.isSleepSpot }.max { pref($0) < pref($1) }
        if let o = spot, pref(o) < floorPref { spot = nil } // prefers the floor
        if let spot { s.x = spot.x }
        s.carrying = nil
        s.activity = Activity(act: .sleep, target: spot?.id, destX: nil, remaining: rand(20...90), started: s.time)
        chooseSleepPos()
    }

    public var pose: Pose {
        let a = s.activity
        let anim: Anim
        if a.destX != nil {
            anim = a.act == .zoomies ? .zoom : a.running == true ? .run : .walk
        } else {
            switch a.act {
            case .sleep: anim = .sleep
            case .sit, .greet, .groom: anim = .sit
            case .eat, .drink, .sniff: anim = .headDown
            case .play: anim = .play
            case .stretch: anim = .stretch
            case .react: anim = .hop
            case .zoomies: anim = .zoom
            default: anim = .stand
            }
        }
        let emote = anim == .sleep ? "z" : s.emote
        var pose = Pose(x: s.x, facing: s.facing, anim: anim, carrying: s.carrying, emote: emote, twitch: s.time < s.twitchUntil)
        if let at = s.jumpAt, let len = s.jumpLen, len > 0 {
            if s.time < at || s.time > at + len { pose.crouch = true }   // winding up, or soaking up the landing
            else { pose.jump = (s.time - at) / len; pose.jumpHeight = s.jumpHeight ?? 0 }
        }
        pose.attention = s.attention
        if let c = s.carrying, let o = s.objects.first(where: { $0.id == c }), o.kind.isToy {
            pose.holding = o.id == "tennis" ? "tennis" : o.kind.rawValue
            pose.toss = s.time < (s.tossUntil ?? 0)
        }
        if a.act == .play, let o = a.target.flatMap({ id in s.objects.first { $0.id == id } }) { pose.play = o.kind == .ball ? "chase" : "shake" }
        if a.act == .kennel && a.phase != "door" {
            pose.inKennel = true; pose.emote = nil
            if a.destX == nil { pose.anim = s.needs.tiredness > 0.3 ? .sleep : .sit }   // napping or sitting in its den
        }
        let asleep = (a.act == .sleep && a.destX == nil) || (pose.inKennel && pose.anim == .sleep)
        if asleep { pose.twitch = s.time < s.twitchUntil; pose.sleepPos = s.sleepPos ?? "flat" }
        if a.act == .sleep && a.destX == nil, let t = a.target, s.objects.first(where: { $0.id == t })?.kind == .bed { pose.inBed = t }
        if anim == .sit {
            pose.front = a.front == true || a.act == .greet || s.attention == "head" || s.attention == "body"
            pose.back = !pose.front && a.back == true
        }
        if s.attention == "head" { pose.lookX = s.lastCursorX }
        if let at = s.fallAt {
            let t = s.time - at
            pose.fall = s.fallKind == "trip" ? "trip" : t < 0.15 ? "trip" : t < 0.45 ? "roll" : t < 1.3 ? "sprawl" : t < 1.5 ? "up" : "sheepish"
        }
        if a.act == .groom && a.destX == nil { pose.groom = a.phase }
        pose.wag = pose.fall == nil && anim != .sleep && (s.time < (s.wagUntil ?? 0) || a.act == .greet)   // always wags hello
        return pose
    }

    /// Effective preference for an object, -1...1. Before any experience it's a faint hint of innate taste.
    public func pref(_ o: PetObject) -> Double { s.learned[o.id] ?? 0.3 * (s.innate[o.kind] ?? 0) }
    var floorPref: Double { s.learned["floor"] ?? 0.3 * (s.innate[.floor] ?? 0) }

    /// 0...1 sleep pressure from the local clock: nights, an after-lunch dip, winding down in the evening.
    public static func sleepiness(hour: Double) -> Double {
        let night = (hour >= 22 || hour < 6.5) ? 1.0 : 0
        let siesta = exp(-pow((hour - 14.5) / 1.5, 2)) * 0.6
        let evening = (hour >= 19 && hour < 22) ? (hour - 19) / 3 * 0.8 : 0
        return min(1, max(night, siesta, evening) + 0.1)
    }

    // MARK: - Needs & preferences over time

    mutating func evolveNeeds(_ dt: Double, circ: Double) {
        let a = s.activity
        let p = s.personality
        s.needs.hunger += dt / (5 * 3600)
        s.needs.thirst += dt / (3 * 3600)
        if a.act == .kennel && a.phase == "inside" && a.destX == nil {
            s.needs.tiredness -= dt / (5 * 3600)   // resting in its den: a light nap
        } else if a.act == .sleep && a.destX == nil {
            s.needs.tiredness -= dt / (3 * 3600) * (1.2 - 0.6 * circ) // sleeps deeper/longer at night
        } else {
            let effort = a.act == .zoomies ? 4.0 : a.act == .play ? 2.5 : a.destX != nil ? 1.5 : 1.0
            s.needs.tiredness += dt / (5 * 3600) * effort * (0.6 + 0.8 * circ) * (1.2 - 0.6 * p.energy + 0.3 * p.laziness)
            if a.act != .play && a.act != .zoomies { s.needs.boredom += dt / (1.5 * 3600) * (0.5 + p.playfulness) }
        }
        s.needs.clamp()
    }

    /// Unused preferences fade over ~2 weeks toward a faint version of innate taste, so the dog can change its mind.
    mutating func decayPreferences(_ dt: Double) {
        let k = dt / (14 * 86400)
        for (id, v) in s.learned {
            let kind = id == "floor" ? Kind.floor : s.objects.first { $0.id == id }?.kind
            guard let kind else { continue }
            let rest = 0.3 * (s.innate[kind] ?? 0)
            s.learned[id] = v + (rest - v) * k
        }
    }

    // MARK: - Decision

    struct Candidate { var act: Act; var target: String?; var score: Double }

    mutating func candidates(_ env: Environment) -> [Candidate] {
        let n = s.needs, p = s.personality, circ = Self.sleepiness(hour: env.hour)
        var c: [Candidate] = []
        func f(_ pref: Double) -> Double { exp(1.3 * pref) } // favourite ≈ 3.7×, disliked ≈ 0.3×; never certain

        // Sleep: tiredness × clock × laziness, boosted while you're away; per spot by preference.
        let away = env.userIdle > 600 ? 1.8 : 1
        let night = 1 - 0.9 * circ // energetic acts fade at night
        let lastTarget = s.memory.last?.target
        let sleepBase = pow(n.tiredness, 1.5) * (0.4 + circ) * (0.6 + 0.8 * p.laziness) * away * (n.tiredness < 0.2 * (1 - circ) ? 0.05 : 1) * 4 // at night it dozes off again easily
        for o in s.objects where o.kind.isSleepSpot { c.append(.init(act: .sleep, target: o.id, score: sleepBase * f(pref(o)))) }
        c.append(.init(act: .sleep, target: nil, score: sleepBase * f(floorPref)))

        if let k = s.objects.first(where: { $0.kind == .kennel }) {
            let den = (0.15 + 0.35 * p.independence + 0.3 * p.laziness) * (0.3 + n.tiredness) * (env.userIdle > 600 ? 1.5 : 1) * (1 + 0.5 * circ)
            c.append(.init(act: .kennel, target: k.id, score: env.systemBusy ? 8 : den * 0.18 * f(pref(k))))
        }
        if let bowl = s.objects.first(where: { $0.kind == .foodBowl }) {
            c.append(.init(act: .eat, target: bowl.id, score: pow(n.hunger, 2) * 5 * (n.hunger < 0.25 ? 0.05 : 1) * f(pref(bowl) * 0.5)))
        }
        if let bowl = s.objects.first(where: { $0.kind == .waterBowl }) {
            c.append(.init(act: .drink, target: bowl.id, score: pow(n.thirst, 2) * 5 * (n.thirst < 0.25 ? 0.05 : 1)))
        }
        for toy in s.objects where toy.kind.isToy {
            let pr = pref(toy)
            c.append(.init(act: .play, target: toy.id, score: (0.3 + n.boredom) * (0.3 + p.playfulness) * (1 - 0.8 * n.tiredness) * f(pr) * 0.35 * night))
            // Carrying toys around only really happens with ones it has come to like.
            c.append(.init(act: .carry, target: toy.id, score: 0.3 * p.playfulness * f(pr * 1.5) * (pr > 0.25 ? 1 : 0.15) * night))
        }
        let perObject = 1.5 / Double(max(1, s.objects.count))
        for o in s.objects {
            c.append(.init(act: .sniff, target: o.id, score: (0.15 + 0.5 * p.curiosity) * (0.3 + 4 * novelty(o)) * perObject))
        }
        c.append(.init(act: .wander, target: nil, score: 0.6 * (0.4 + p.energy) * (1 - 0.6 * n.tiredness) * (1 - 0.6 * circ)))
        c.append(.init(act: .idle, target: nil, score: 0.5 * (0.5 + p.laziness)))
        c.append(.init(act: .sit, target: nil, score: 0.45))
        c.append(.init(act: .lookAround, target: nil, score: 0.3 * (0.5 + p.curiosity)))
        c.append(.init(act: .groom, target: nil, score: 0.2))
        let justWoke = s.time - (s.lastDone[.sleep] ?? -1e9) < 20
        c.append(.init(act: .stretch, target: nil, score: justWoke ? 4 : 0.12))
        c.append(.init(act: .zoomies, target: nil, score: 1.2 * p.energy * pow(1 - n.tiredness, 2) * n.boredom * night))
        if env.cursorX != nil {
            let boost = s.time < s.greetBoostUntil ? 2.5 : 0.12
            c.append(.init(act: .greet, target: nil, score: boost * (0.3 + p.affection) * (1.2 - p.independence)))
        }

        // History: no immediate repeats (except sleep), cooldowns, then noise.
        for i in c.indices {
            let a = c[i].act
            if a == s.activity.act && a != .sleep { c[i].score *= 0.35 }
            if let t = c[i].target, t == lastTarget, a != .sleep, a != .eat, a != .drink { c[i].score *= 0.4 } // just did something with it
            if a == .sniff, let t = c[i].target, let m = s.memory.last(where: { $0.act == .sniff && $0.target == t }), s.time - m.t < 900 { c[i].score *= 0.15 }
            if let last = s.lastDone[a], s.time - last < a.cooldown { c[i].score *= 0.05 }
            c[i].score *= exp(gauss() * 0.3)
        }
        return c
    }

    mutating func decide(_ env: Environment) {
        if let t = s.pendingCarry {
            s.pendingCarry = nil
            if s.objects.contains(where: { $0.id == t }) { start(.carry, target: t, env); return }
        }
        let c = candidates(env)
        lastScores = c.sorted { $0.score > $1.score }.prefix(6).map { "\($0.act.rawValue)\($0.target.map { ":" + $0 } ?? "") \(String(format: "%.2f", $0.score))" }
        let pick: Candidate
        if rand(0...1) < 0.03 {
            pick = c[Int.random(in: c.indices, using: &s.rng)] // got distracted
        } else {
            let w = c.map { pow(max($0.score, 1e-6), 1.5) }
            var r = rand(0...w.reduce(0, +))
            var chosen = c[c.count - 1]
            for (i, wi) in w.enumerated() { r -= wi; if r <= 0 { chosen = c[i]; break } }
            pick = chosen
        }
        start(pick.act, target: pick.target, env)
    }

    mutating func start(_ act: Act, target: String?, _ env: Environment) {
        var a = Activity(act: act, target: target, destX: nil, remaining: rand(act.duration), started: s.time)
        if act == .sleep { a.remaining *= 1 + 2 * Self.sleepiness(hour: env.hour) } // night sleeps run long
        let o = target.flatMap { id in s.objects.first { $0.id == id } }
        switch act {
        case .eat, .drink, .sniff, .play:
            if let o { a.destX = o.x + (s.x < o.x ? -24 : 24) } // stand beside it, facing it
            if act == .play, let o { a.running = abs(o.x - s.x) > 150 }   // runs over to a toy across the room
        case .carry:
            if let o { a.destX = o.x + (s.x < o.x ? -26 : 26) }
        case .sleep:
            a.destX = o?.x ?? rand(env.minX...env.maxX)
            chooseSleepPos()
        case .kennel:
            if let o { a.destX = o.x + Self.kennelDoorOutside; a.phase = "door" }
            chooseSleepPos()
        case .sit:
            orientSit(&a)
        case .groom:
            a.phase = rand(0...1) < 0.6 ? "lick" : "scratch"   // licks a paw or scratches an ear with a hind foot
        case .wander, .zoomies:
            a.destX = rand(env.minX...env.maxX)
            // An energetic, happy dog sometimes runs instead of strolling.
            if act == .wander { a.running = rand(0...1) < 0.12 * s.personality.energy * mood * (1 - s.needs.tiredness) }
        case .greet:
            a.destX = env.cursorX
            a.running = s.time < s.greetBoostUntil && rand(0...1) < 0.5 + 0.4 * s.personality.affection   // you're back!
        case .follow:
            a.destX = env.cursorX.map { $0 + (s.x < $0 ? -34 : 34) }
            a.running = env.cursorX.map { abs($0 - s.x) > 180 } ?? false   // far away: run to catch up
        default: break
        }
        a.destX = a.destX.map { min(max($0, env.minX), env.maxX) }
        if let d = a.destX, abs(d - s.x) < 2 { a.destX = nil; s.x = d }
        if act == .sniff, let o, novelty(o) > 0.3, s.emote == nil { setEmote("?", 3) }
        if a.destX == nil { arrive(&a, env) }
        s.activity = a
    }

    /// Reached the destination.
    mutating func arrive(_ a: inout Activity, _ env: Environment) {
        if let o = a.target.flatMap({ id in s.objects.first { $0.id == id } }), a.act != .sleep, a.act != .carry || s.carrying == nil {
            s.facing = o.x >= s.x ? 1 : -1
        }
        if a.act == .play, a.target.flatMap({ id in s.objects.first { $0.id == id } })?.kind == .ball, s.time > a.started + 1 {
            jump(height: 14 + 6 * s.personality.playfulness, length: 0.4)   // pounce on the ball
        }
        if a.act == .kennel, let k = s.objects.first(where: { $0.kind == .kennel }) {
            switch a.phase {
            case "door": a.phase = "enter"; a.running = false; a.destX = k.x + rand(Self.kennelInside)   // in through the doorway
            case "enter": a.phase = "inside"
            case "exit": a.remaining = 0
            default: break
            }
        }
        switch a.act {
        case .carry where s.carrying == nil:
            s.carrying = a.target
            a.destX = rand(env.minX...env.maxX) // trot off somewhere with it
            a.running = rand(0...1) < 0.2 + 0.4 * s.personality.playfulness * s.personality.energy
        case .zoomies where a.remaining > 0:
            a.destX = rand(env.minX...env.maxX)
        default: break
        }
    }

    mutating func perform(_ a: inout Activity, _ dt: Double, _ env: Environment) {
        switch a.act {
        case .eat:
            s.needs.hunger -= dt / 20
            if s.needs.hunger <= 0 { a.remaining = 0 }
        case .drink:
            s.needs.thirst -= dt / 8
            if s.needs.thirst <= 0 { a.remaining = 0 }
        case .play:
            s.needs.boredom -= dt / 40
            if let id = a.target, let i = s.objects.firstIndex(where: { $0.id == id }) {
                if s.objects[i].kind == .ball {
                    // Chase: every few seconds the ball rolls off; it runs after it and pounces.
                    if s.time >= (s.nextRoll ?? 0) {
                        s.nextRoll = s.time + rand(2.5...5)
                        let roll = (rand(0...1) < 0.5 ? -1.0 : 1.0) * rand(30...90)
                        let bx = min(max(s.objects[i].x + roll, env.minX), env.maxX)
                        s.objects[i].x = bx
                        a.destX = bx + (s.x < bx ? -24 : 24)
                        a.running = abs(bx - s.x) > 40
                    }
                } else {
                    s.carrying = id   // grab and shake (plush, rope)
                    if rand(0...1) < dt * 0.15 {   // ...and wander a few steps with it in its mouth
                        a.destX = min(max(s.x + (rand(0...1) < 0.5 ? -1 : 1) * rand(20...60), env.minX), env.maxX)
                    }
                }
            }
        case .sniff: s.needs.boredom -= dt / 200
        case .sleep:
            if s.needs.tiredness <= 0.02 { a.remaining = 0 }
            dreamTick()
            if rand(0...1) < dt * 0.0025 { chooseSleepPos(); s.twitchUntil = s.time + 0.6 }   // resettles every few minutes
        case .lookAround: if rand(0...1) < dt * 0.6 { s.facing = -s.facing }
        case .sit: if rand(0...1) < dt * 0.04 { orientSit(&a) }   // shifts round now and then
        case .groom: if rand(0...1) < dt * 0.12 { a.phase = a.phase == "lick" ? "scratch" : "lick" }   // moves on to another itch
        case .kennel:
            if a.phase == "inside", rand(0...1) < dt * 0.03, let k = s.objects.first(where: { $0.kind == .kennel }) {
                a.destX = k.x + rand(Self.kennelInside)   // potters about inside
            }
            if s.needs.tiredness > 0.3 { dreamTick() }
        default: break
        }
        s.needs.clamp()
    }

    /// Ends the current activity: remembers it and learns from it.
    mutating func finish() {
        let a = s.activity
        s.lastDone[a.act] = s.time
        if a.act == .carry || a.act == .play { s.carrying = nil }
        if a.act == .play, let t = a.target, s.objects.first(where: { $0.id == t })?.kind == .ball,
           rand(0...1) < 0.25 + 0.5 * s.personality.playfulness { s.pendingCarry = t }   // grabs the ball and trots off with it
        if a.act == .follow {
            if s.attention == "follow" { s.attention = nil; s.attentionUntil = nil }
            if rand(0...1) < 0.2 + 0.6 * s.personality.playfulness * mood { jump(height: 22 + 8 * s.personality.energy, length: 0.5) }   // pounce
        }
        var enjoyment: Double?
        let learnable: Set<Act> = [.play, .carry, .sniff, .sleep, .eat, .kennel]
        if learnable.contains(a.act), a.destX == nil || a.act == .carry {
            let o = a.target.flatMap { id in s.objects.first { $0.id == id } }
            let key = o?.id ?? (a.act == .sleep ? "floor" : nil)
            let kind = o?.kind ?? .floor
            if let key {
                let taste = s.innate[kind] ?? 0
                let mood = (a.act == .play || a.act == .carry) ? (s.personality.playfulness - 0.5) * 0.4 : 0
                let e = taste + mood + gauss() * 0.35
                enjoyment = e
                let current = s.learned[key] ?? 0.3 * taste
                let rate = a.act == .sniff ? 0.04 : 0.12
                s.learned[key] = min(1, max(-1, current + rate * (e - current)))
            }
        }
        if a.act == .sleep, let pos = s.sleepPos {   // comfiest positions become favourites
            let key = "pos:" + pos
            let e = (s.posTaste?[pos] ?? 0) + gauss() * 0.3
            let current = s.learned[key] ?? 0.3 * (s.posTaste?[pos] ?? 0)
            s.learned[key] = min(1, max(-1, current + 0.12 * (e - current)))
        }
        s.memory.append(Memory(t: s.time, act: a.act, target: a.target, enjoyment: enjoyment))
        if s.memory.count > 200 { s.memory.removeFirst(s.memory.count - 200) }
    }

    /// Urgent needs can break into an activity; sleep only for the most urgent.
    func shouldInterrupt() -> Bool {
        let a = s.activity.act, n = s.needs
        switch a {
        case .sleep: return n.hunger > 0.97 || n.thirst > 0.97
        case .eat, .drink, .react, .stretch: return false
        default: return (n.hunger > 0.85 && a != .eat) || (n.thirst > 0.85 && a != .drink) || n.tiredness > 0.92
        }
    }

    func novelty(_ o: PetObject) -> Double { exp(-(s.time - o.addedAt) / (3 * 3600)) }

    /// Kennel geometry in points from its centre (side-on kennel, doorway near its right end).
    static let kennelDoorOutside = 88.0      // just clear of the cabin's open end (cabin is 99 pt wide, dog 72 pt)
    static let kennelInside = -16.0 ... 0.0

    /// Every minute or few of sleep, a short dream: paws paddle, the tail tip and an ear twitch.
    mutating func dreamTick() {
        guard s.time >= (s.nextDream ?? s.activity.started + rand(20...90)) else { return }
        if s.nextDream == nil { s.nextDream = s.activity.started + rand(20...90); return }
        // Playful, energetic dogs dream more often and twitch longer; lazy ones barely stir.
        let lively = 0.4 + s.personality.playfulness + 0.6 * s.personality.energy - 0.4 * s.personality.laziness
        s.nextDream = s.time + rand(60...300) / max(0.3, lively)
        s.twitchUntil = s.time + rand(1.0...2.5) * max(0.5, lively)
    }

    static let sleepPositions = ["flat", "curl", "side", "belly"]

    /// Picks how to lie: weighted by its developing favourite (hidden taste + experience); belly-up only when relaxed.
    mutating func chooseSleepPos() {
        if s.posTaste == nil {
            // Personality leans the hidden taste: independent dogs curl up, laid-back affectionate ones
            // go belly-up, energetic ones sprawl on their side; the rest is chance and, later, experience.
            let p = s.personality
            let bias = ["flat": 0.0, "curl": 0.6 * p.independence - 0.2, "side": 0.5 * p.energy - 0.2,
                        "belly": 0.4 * p.laziness + 0.4 * p.affection - 0.4]
            var t: [String: Double] = [:]
            for pos in Self.sleepPositions { t[pos] = min(1, max(-1, rand(-0.4...0.6) + (bias[pos] ?? 0))) }
            s.posTaste = t
        }
        let w = Self.sleepPositions.map { p -> Double in
            let pref = s.learned["pos:" + p] ?? 0.3 * (s.posTaste?[p] ?? 0)
            return exp(1.3 * pref) * (p == "belly" ? 0.3 + mood : 1)
        }
        var r = rand(0...w.reduce(0, +))
        for (i, wi) in w.enumerated() { r -= wi; if r <= 0 { s.sleepPos = Self.sleepPositions[i]; return } }
        s.sleepPos = "flat"
    }

    /// Sits any way round: side-on (either direction), facing you, or facing away.
    mutating func orientSit(_ a: inout Activity) {
        let p = s.personality
        let r = rand(0...1), front = 0.2 + 0.3 * p.affection, back = 0.12 + 0.2 * p.independence
        a.front = r < front
        a.back = !a.front! && r < front + back
        if a.front != true && a.back != true && rand(0...1) < 0.5 { s.facing = -s.facing }
    }

    // MARK: - Jumps and the cursor

    /// 0 (needs unmet) ... 1 (fed, watered, rested, entertained).
    public var mood: Double {
        let n = s.needs
        return max(0, min(1, 1 - (0.3 * n.hunger + 0.3 * n.thirst + 0.25 * n.boredom + 0.15 * n.tiredness)))
    }

    static let tripLen = 0.45, tumbleLen = 2.3

    /// nil when standing still; otherwise whether it is going fast (running or zoomies) rather than walking.
    var movingGait: Bool? {
        let a = s.activity
        return a.destX == nil ? nil : a.act == .zoomies || a.running == true
    }

    mutating func fall(tumble: Bool) {
        s.fallAt = s.time; s.fallKind = tumble ? "tumble" : "trip"
        s.fallSpeed = s.activity.act == .zoomies ? 120 : s.activity.running == true ? 90 : 35
        s.wagUntil = nil
    }

    /// Testing hook: trip (or tumble) right now.
    public mutating func debugFall(tumble: Bool) { fall(tumble: tumble) }

    /// A jump layers on top of whatever it is doing; it never replaces the activity.
    mutating func jump(height: Double, length: Double) {
        guard s.jumpAt == nil else { return }
        // Standing jumps gather into a crouch first; on the move it springs straight off its stride.
        s.jumpAt = s.time + (s.activity.destX == nil ? Brain.jumpCrouch : 0); s.jumpLen = length; s.jumpHeight = height
    }
    static let jumpCrouch = 0.14, jumpLand = 0.12

    /// Shock: a quick startled jump with a "!", waking it if asleep.
    public mutating func startle(env: Environment, strength: Double = 1) {
        if s.activity.act == .sleep { finish(); start(.react, target: nil, env) }
        setEmote("!", 1.2)
        jump(height: 14 + 10 * strength, length: 0.4)
    }

    /// Hops while playing or doing zoomies; otherwise a rare spontaneous jump for joy:
    /// likelier when playful, energetic, in a good mood and rested, much rarer at night, more right after you come back.
    mutating func maybeJump(_ dt: Double, circ: Double) {
        guard s.jumpAt == nil else { return }
        let a = s.activity, p = s.personality
        switch a.act {
        case .sleep, .eat, .drink, .react, .stretch, .kennel:
            return
        case .play where a.destX == nil:
            if rand(0...1) < dt * 0.05 * (0.4 + p.playfulness) { jump(height: rand(10...18) + 8 * p.energy, length: 0.45) }
        case .zoomies:
            if rand(0...1) < dt * 0.3 { jump(height: rand(12...20), length: 0.4) }
        default:
            let excited = s.time < s.greetBoostUntil ? 4.0 : 1.0
            let rate = 0.0015 * excited * (0.2 + p.playfulness) * (0.2 + p.energy) * mood * (1 - s.needs.tiredness) * (1 - 0.9 * circ)
            if rand(0...1) < dt * rate { jump(height: rand(14...24) + 6 * p.playfulness, length: 0.5) }
        }
    }

    /// Noticing a moving cursor near its floor, then choosing how much to care:
    /// "head" (a glance), "body" (turns to face it) or "follow" (goes after it). Lazy dogs glance,
    /// curious ones turn, playful and affectionate ones follow; tired or grumpy dogs mostly don't bother.
    mutating func updateAttention(_ dt: Double, env: Environment) {
        let moved = env.cursorX.map { abs($0 - (s.lastCursorX ?? $0)) > 1 } ?? false
        s.lastCursorX = env.cursorX
        if let until = s.attentionUntil, s.time > until || env.cursorX == nil, s.attention != "follow" { s.attention = nil; s.attentionUntil = nil }
        if s.attention == "body", let cx = env.cursorX, s.activity.destX == nil { s.facing = cx >= s.x ? 1 : -1 }
        guard moved, s.attention == nil, s.time >= (s.attentionCooldown ?? 0) else { return }
        let calm: Set<Act> = [.idle, .sit, .lookAround, .wander, .groom]
        guard calm.contains(s.activity.act) else { return }
        let p = s.personality
        let notice = 0.5 * (0.3 + 0.5 * p.curiosity + 0.5 * p.affection) * (1.1 - 0.6 * p.independence) * (0.4 + 0.6 * mood) * (1 - 0.7 * s.needs.tiredness)
        guard rand(0...1) < dt * notice else { return }
        s.attentionCooldown = s.time + rand(15...45)
        let wHead = 0.8 + p.laziness
        let wBody = 0.5 + p.curiosity
        let recentlyFollowed = s.lastDone[.follow].map { s.time - $0 < Act.follow.cooldown } ?? false
        let wFollow = (p.playfulness + p.affection + p.energy) * 0.7 * (1 - s.needs.tiredness) * mood * (recentlyFollowed ? 0.1 : 1)
        let r = rand(0...(wHead + wBody + wFollow))
        if r < wHead {
            s.attention = "head"; s.attentionUntil = s.time + rand(1.5...4)
        } else if r < wHead + wBody {
            s.attention = "body"; s.attentionUntil = s.time + rand(3...8); setEmote("?", 1)
        } else {
            s.attention = "follow"; s.attentionUntil = s.time + 20; setEmote("!", 1)
            finish(); start(.follow, target: nil, env)
        }
    }

    // MARK: - Randomness

    mutating func rand(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &s.rng) }
    mutating func gauss() -> Double {
        let u1 = max(1e-12, rand(0...1)), u2 = rand(0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
    mutating func setEmote(_ e: String, _ secs: Double) { s.emote = e; s.emoteUntil = s.time + secs }
}
