import Foundation

/// The default home contents. shortcut: laid out on the desktop floor until the house popup exists (roadmap step 3).
public func defaultObjects(width: Double) -> [PetObject] {
    [PetObject(id: "kennel", kind: .kennel, x: 60),
     PetObject(id: "bed", kind: .bed, x: 150),
     PetObject(id: "food", kind: .foodBowl, x: 240),
     PetObject(id: "water", kind: .waterBowl, x: 290),
     PetObject(id: "ball", kind: .ball, x: width * 0.45),
     PetObject(id: "plush", kind: .plush, x: width * 0.65),
     PetObject(id: "rope", kind: .rope, x: width * 0.85)]
}

public struct SimReport: Sendable {
    public var seed: UInt64
    public var hours: Double
    public var personality: Personality
    public var actTime: [Act: Double] = [:]
    public var interactions: [String: Int] = [:]   // "play:ball"
    public var prefs: [String: Double] = [:]
    public var timeline: [String] = []              // hourly "HH:mm act"
    public var decisions = 0
    public var jumps = 0, runs = 0, glances = 0, turns = 0, follows = 0
    public var busyRetreats = 0, frontSits = 0
    public var failures: [String] = []

    public func share(_ a: Act) -> Double { (actTime[a] ?? 0) / (hours * 3600) }
}

/// Runs one dog for `hours` of simulated time at the app's tick rate, with a workday pattern
/// (you're away at lunch and overnight), a few pokes, and a new tennis ball introduced at 11:00.
/// Checks the invariants that "leave it alone for hours and nothing goes wrong" depends on.
public func simulate(seed: UInt64, hours: Double = 24, dt: Double = 0.2) -> SimReport {
    let width = 1400.0
    var brain = Brain(seed: seed)
    for o in defaultObjects(width: width) { brain.s.objects.append(o) }
    var world = SplitMix(seed: seed ^ 0x5EED)
    var r = SimReport(seed: seed, hours: hours, personality: brain.s.personality)

    let startHour = 8.0
    var idle = 0.0, cursorX: Double? = nil, nextCursorChange = 0.0
    var lastX = brain.s.x, stillSince = 0.0
    var hungryFor = 0.0, thirstyFor = 0.0
    var lastStarted = -1.0, lastActivity = brain.s.activity
    var nextTimeline = 0.0
    var addedBall = false
    var wasJumping = false, lastAttention: Attention? = nil
    var busySince: Double? = nil, wasBusyRetreat = false

    var t = 0.0
    while t < hours * 3600 {
        let hour = (startHour + t / 3600).truncatingRemainder(dividingBy: 24)
        let atDesk = (hour >= 9 && hour < 12.5) || (hour >= 13.5 && hour < 18.5)
        idle = atDesk ? (Double.random(in: 0...1, using: &world) < 0.02 ? 0 : idle + dt).truncatingRemainder(dividingBy: 90) : idle + dt
        if t >= nextCursorChange {
            nextCursorChange = t + 30
            cursorX = atDesk && Double.random(in: 0...1, using: &world) < 0.3 ? Double.random(in: 40...(width - 40), using: &world) : nil
        }
        if let c = cursorX { cursorX = min(width - 40, max(40, c + Double.random(in: -6...6, using: &world))) }   // you're moving the mouse
        let busy = (hour >= 10 && hour < 10 + 20.0 / 60) || (hour >= 15 && hour < 15 + 10.0 / 60)   // e.g. a build or an export
        let env = Environment(minX: 40, maxX: width - 40, hour: hour, userIdle: idle, cursorX: cursorX, systemBusy: busy)

        if !addedBall && hour >= 11 { addedBall = true; brain.add(PetObject(id: "tennis", kind: .ball, x: width * 0.3), env: env) }
        if atDesk && Double.random(in: 0...1, using: &world) < dt / 2700 { brain.poke(env: env) } // ~every 45 min

        brain.update(dt: dt, env: env)
        let s = brain.s

        // Bookkeeping
        r.actTime[s.activity.act, default: 0] += dt
        if s.activity.started != lastStarted {
            lastStarted = s.activity.started
            r.decisions += 1
            if s.activity.running == true { r.runs += 1 }
            if s.activity.act == .follow { r.follows += 1 }
            if s.activity.front == true { r.frontSits += 1 }
            r.interactions["\(lastActivity.act.rawValue)\(lastActivity.target.map { ":" + $0 } ?? "")", default: 0] += 1
            lastActivity = s.activity
        }
        if t >= nextTimeline {
            nextTimeline += 3600
            let h = Int(hour), m = Int((hour - Double(h)) * 60)
            r.timeline.append(String(format: "%02d:%02d %@%@", h, m, s.activity.act.rawValue, s.activity.target.map { " " + $0 } ?? ""))
        }

        let jumping = s.jumpAt != nil
        if jumping && !wasJumping {
            r.jumps += 1
            if s.activity.act == .sleep && s.activity.destX == nil { r.failures.append("jumped while asleep at t=\(Int(t))s") }
        }
        wasJumping = jumping
        if s.attention != lastAttention {
            if s.attention == .head { r.glances += 1 } else if s.attention == .body { r.turns += 1 }
            lastAttention = s.attention
        }

        if (s.busyRetreat == true) && !wasBusyRetreat { r.busyRetreats += 1 }
        wasBusyRetreat = s.busyRetreat == true
        let outOfTheWay = s.activity.act == .kennel && s.activity.kennel == .inside || s.activity.act == .sleep && s.activity.destX == nil
        busySince = busy && !outOfTheWay ? (busySince ?? t) : nil   // time out and about during a busy spell
        if let since = busySince, t - since > 120, s.activity.act != .eat, s.activity.act != .drink {
            r.failures.append("still out and about 2 min into a busy spell at t=\(Int(t))s (\(s.activity.act))"); busySince = t
        }

        // Invariants
        let n = s.needs
        for (name, v) in [("hunger", n.hunger), ("thirst", n.thirst), ("tiredness", n.tiredness), ("boredom", n.boredom)] where !(0...1).contains(v) || v.isNaN {
            r.failures.append("\(name) out of range: \(v) at t=\(Int(t))s")
        }
        if !(env.minX...env.maxX).contains(s.x) { r.failures.append("dog off-floor x=\(s.x) at t=\(Int(t))s") }
        if s.x != lastX || s.activity.act == .sleep || s.activity.act == .kennel { lastX = s.x; stillSince = t }
        if t - stillSince > 20 * 60 { r.failures.append("stuck awake in one spot for 20 min at t=\(Int(t))s (\(s.activity.act))"); stillSince = t }
        hungryFor = n.hunger > 0.95 ? hungryFor + dt : 0
        thirstyFor = n.thirst > 0.95 ? thirstyFor + dt : 0
        if hungryFor > 3600 { r.failures.append("hunger maxed for an hour at t=\(Int(t))s"); hungryFor = 0 }
        if thirstyFor > 3600 { r.failures.append("thirst maxed for an hour at t=\(Int(t))s"); thirstyFor = 0 }
        if let c = s.carrying, !s.objects.contains(where: { $0.id == c }) { r.failures.append("carrying missing object \(c)") }
        t += dt
    }

    for o in brain.s.objects { r.prefs[o.id] = brain.pref(o) }
    r.prefs["floor"] = brain.floorPref
    if hours >= 24 {
        let sleep = r.share(.sleep)
        if sleep < 0.3 || sleep > 0.8 { r.failures.append(String(format: "slept %.0f%% of the day (expected 30–80%%)", sleep * 100)) }
        for a in Act.allCases where a != .sleep && r.share(a) > 0.3 {
            r.failures.append(String(format: "%@ took %.0f%% of the day", a.rawValue, r.share(a) * 100))
        }
        let awakeActs = Set(r.actTime.filter { $0.key != .sleep && $0.value > 60 }.keys)
        if awakeActs.count < 8 { r.failures.append("only \(awakeActs.count) different activities in a day") }
    }
    return r
}
