import Foundation

/// Deterministic, persistable RNG (SplitMix64). Same seed → same dog, same day.
public struct SplitMix: RandomNumberGenerator, Codable, Sendable, Equatable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Hidden traits, 0...1, rolled at adoption.
public struct Personality: Codable, Sendable, Equatable {
    public var playfulness, laziness, affection, independence, curiosity, energy: Double
    public var clumsiness: Double?          // older saves have none: a beagle is a little clumsy by default
    public var clumsy: Double { clumsiness ?? 0.35 }

    public static func random(_ rng: inout SplitMix) -> Personality {
        var t = [Double]()
        for _ in 0..<6 { t.append(Double.random(in: 0.1...0.95, using: &rng)) }
        return Personality(playfulness: t[0], laziness: t[1], affection: t[2], independence: t[3], curiosity: t[4], energy: t[5],
                           clumsiness: Double.random(in: 0.05...0.95, using: &rng))
    }
}

public enum Kind: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case bed, rug, foodBowl, waterBowl, ball, plush, rope, kennel
    case floor // not placeable: "sleeping on the bare floor" as a sleep spot with its own preference
    case tree, seedDish, waterDish   // a bird's home: its tree (branches, birdhouse, swing, bell) and its dishes
    case oak, mouse, pinecone, feather, log   // an owl's: its hollow oak, its toy mouse, a pinecone to bat, a log perch (feather: retired, kept so older saves load)
    case rattan                               // a parrot's woven ball: carried in its beak and dropped to watch it bounce
    /// A dog's kinds, in the order its innate tastes are rolled (bird kinds come after, so a dog's seed rolls the same dog).
    public static let dogKinds: [Kind] = [.bed, .rug, .foodBowl, .waterBowl, .ball, .plush, .rope, .kennel, .floor]
    /// A bird's kinds in the order they're rolled (later kinds come after, so a bird's seed rolls the same bird).
    public static let birdKinds: [Kind] = dogKinds + [.tree, .seedDish, .waterDish]
    public var isToy: Bool { self == .ball || self == .plush || self == .rope }
    public var isSleepSpot: Bool { self == .bed || self == .rug }
}

public struct PetObject: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kind: Kind
    public var x: Double // centre, points along the floor
    public var addedAt: Double
    public var vx: Double? = nil   // rolling (a kicked ball): points/s; nil at rest. Optional so older saves load.
    public init(id: String, kind: Kind, x: Double, addedAt: Double = -1e9) {
        self.id = id; self.kind = kind; self.x = x; self.addedAt = addedAt
    }
}

public enum Act: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case idle, sit, lookAround, wander, sniff, sleep, stretch, groom, eat, drink, play, carry, zoomies, greet, react, follow, kennel
    case fly, hop, peck, splash, swing, bell   // a bird's: off to another perch, hopping along it, pecking the floor, bathing, its swing and bell
    case hunt, hoot                            // an owl's: stalking and pouncing on its mouse; hooting at dusk and dawn

    /// Running pace (Activity.running), points/s.
    static let runSpeed = 130.0
    /// Walking pace, points/s. Running is `runSpeed`; zoomies are always a sprint.
    var speed: Double { switch self { case .zoomies: 170; case .greet, .follow: 50; default: 42 } }

    /// Minimum seconds before the same act scores normally again.
    var cooldown: Double {
        switch self {
        case .zoomies: 1800; case .greet: 600; case .follow: 90; case .kennel: 1800; case .eat: 1200; case .drink: 600; case .stretch: 120
        case .splash: 1800; case .swing: 1200; case .bell: 1200; case .hunt: 1200; case .hoot: 900; default: 0
        }
    }

    /// Seconds spent performing once at the destination.
    var duration: ClosedRange<Double> {
        switch self {
        case .idle: 4...15; case .sit: 8...40; case .lookAround: 3...8; case .wander: 1...3
        case .sniff: 3...8; case .sleep: 900...5400; case .stretch: 2.5...3.5; case .groom: 6...15
        case .eat: 15...30; case .drink: 5...10; case .play: 15...60; case .carry: 1...2
        case .zoomies: 6...12; case .greet: 5...12; case .react: 1...1.5; case .follow: 6...14; case .kennel: 180...900
        case .fly: 4...20; case .hop: 3...8; case .peck: 8...25; case .splash: 5...10; case .swing: 15...45; case .bell: 3...7
        case .hunt: 10...10; case .hoot: 5...9
        }
    }
}

/// 0 = satisfied, 1 = urgent. Needs only shift behaviour weights; nothing bad happens at 1.
public struct Needs: Codable, Sendable, Equatable {
    public var hunger = 0.2, thirst = 0.2, tiredness = 0.3, boredom = 0.3
    mutating func clamp() {
        hunger = min(1, max(0, hunger)); thirst = min(1, max(0, thirst))
        tiredness = min(1, max(0, tiredness)); boredom = min(1, max(0, boredom))
    }
}

/// Where a kennel visit is: walking to the door, going in, inside, coming back out.
public enum KennelPhase: String, Codable, Sendable { case door, enter, inside, exit }
/// How it reacts to the cursor: a glance, turning to face it, or going after it.
public enum Attention: String, Codable, Sendable { case head, body, follow }
public enum SleepPos: String, Codable, Sendable, CaseIterable { case flat, curl, side, belly }
/// A trip staggers on; a tumble rolls over, lies there a moment and gets up sheepish.
public enum FallKind: String, Codable, Sendable { case trip, tumble }
/// Where it is in a stumble, for the renderer.
public enum FallStage: String, Sendable { case trip, roll, sprawl, up, sheepish }
/// Licking a front paw, or scratching an ear with a hind foot.
public enum Groom: String, Codable, Sendable { case lick, scratch }
public enum PlayStyle: String, Sendable { case chase, shake }

public struct Activity: Codable, Sendable, Equatable {
    public var act: Act
    public var target: String?
    public var destX: Double?   // walking there first while non-nil
    public var remaining: Double
    public var started: Double
    public var running: Bool? = nil   // run instead of walk to the destination (optional: older saves load)
    public var front: Bool? = nil     // sitting facing the viewer
    public var back: Bool? = nil      // sitting with its back to the viewer
    public var phase: String? = nil   // stored as text (older saves): the kennel phase, or the grooming style
    public var total: Double? = nil   // how long it was going to take once there (for progress: the food left in the bowl)
    /// The kennel visit's phase (door → enter → inside → exit).
    public var kennel: KennelPhase? { get { phase.flatMap(KennelPhase.init) } set { phase = newValue?.rawValue } }
    /// What it's grooming.
    public var groom: Groom? { get { phase.flatMap(Groom.init) } set { phase = newValue?.rawValue } }
}

public struct Memory: Codable, Sendable, Equatable {
    public var t: Double
    public var act: Act
    public var target: String?
    public var enjoyment: Double?
}

/// Everything about the dog that persists between launches.
public struct DogState: Codable, Sendable, Equatable {
    /// Save format version. A save from a newer build is never overwritten (see Store).
    public static let currentVersion = 1
    public var version = DogState.currentVersion
    public var personality: Personality
    public var innate: [Kind: Double]          // true hidden taste, -1...1
    public var learned: [String: Double] = [:] // object id (or "floor") → developed preference, -1...1
    public var needs = Needs()
    public var objects: [PetObject] = []
    public var x: Double = 200
    public var facing: Double = 1
    public var activity: Activity
    public var carrying: String?
    public var lastDone: [Act: Double] = [:]
    public var memory: [Memory] = []
    public var time: Double = 0                 // simulated seconds since adoption
    public var rng: SplitMix
    public var emote: String?
    public var emoteUntil: Double = 0
    public var twitchUntil: Double = 0
    public var greetBoostUntil: Double = 0
    public var lastIdle: Double = 0
    public var nextInterruptCheck: Double = 0
    // Optional so saves from before these existed still load.
    public var jumpAt: Double?            // a jump in progress started at this time
    public var jumpLen: Double?
    public var jumpHeight: Double?
    public var attention: Attention?      // how it is reacting to the cursor
    public var attentionUntil: Double?
    public var attentionCooldown: Double?
    public var lastCursorX: Double?
    public var busyRetreat: Bool?       // went into the kennel because the Mac was busy
    public var nextRoll: Double?        // when the ball it's playing with next rolls away
    public var kickAt: Double?          // paw raised: it bats the ball at this time
    public var nextDream: Double?       // when the next dream (twitching) starts while asleep
    public var sleepPos: SleepPos?
    public var posTaste: [String: Double]?   // hidden liking for each sleeping position, rolled once
    public var tossUntil: Double?       // tossing the toy it's holding up in the air
    public var wagUntil: Double?        // tail wagging until then
    public var fallAt: Double?          // tripped (or went head over heels) at this time
    public var fallKind: FallKind?
    public var fallSpeed: Double?       // how fast it was going, for the slide
    public var pendingCarry: String?    // pick this toy up and trot off with it next
    // A bird's (see Bird.swift); nil for a dog.
    public var species: Species?        // nil: a dog (every save before birds)
    public var y: Double?               // feet, in screen points from the top (perched: follows its perch)
    public var perch: String?           // "floor", "b0"…"b3" (branches), "swing", "bell", "house", "w:<window id>"
    public var perchDX: Double?         // on a window: how far along its top edge from the left
    public var flight: Flight?          // in the air
    public var rideSince: Double?, rideLast: Double?   // riding a window being dragged: since, and last moved
    public var coveredSince: Double?    // its window's top edge has been covered by another window since
    public var wobbleUntil: Double?     // balancing (a wobbly landing, or riding a moving window)
    public var crestUntil: Double?      // crest up (excited or startled) until then
    public var lastNearYou: Double?     // last moved to a window near your recent activity
    public var huntAt: Double?          // an owl: when it settled to stare (the hunt runs on from there)
    public var rollTo: Double?          // an owl's pinecone is rolling to here
    public var toss: Toss?              // a toy flung (an owl's mouse) or dropped (a parrot's ball) from a perch: it's falling
    public var prey: Prey?              // the beetle or moth a hungry owl is after
    public var boutUntil: Double?       // preening comes in bouts, with pauses to look round between them
    public var zoomVX: Double?, zoomVY: Double?   // on a joy flight: its velocity (it steers, turning at a limited rate)
}

/// What the outside world tells the brain each tick.
public struct Environment: Sendable {
    public var minX: Double, maxX: Double
    public var hour: Double       // local time of day, 0..<24
    public var userIdle: Double   // seconds since the user last touched mouse/keyboard
    public var cursorX: Double?   // set when the cursor is near the dog's floor
    public var systemBusy: Bool   // the Mac is under heavy load: the dog keeps out of the way in its kennel
    public var reduceMotion: Bool // the user asked for less motion: no zoomies, jumps or tumbles, and walks instead of runs
    /// Kennel geometry in points from its centre, from the art: just clear of the open end, and where it can stand inside.
    public var kennelDoorOutside: Double
    public var kennelInside: ClosedRange<Double>
    /// How far its mouth reaches ahead of its centre with the head down (from the art): where it stands to eat,
    /// drink or sniff, so its mouth is over the middle of the bowl or toy and its paws stay clear of the rim.
    public var mouthReach: Double
    // A bird's world (screen points, top-left origin). A dog ignores these.
    public var floorY: Double = 0       // top of the Dock: the floor
    public var topY: Double = 0         // just under the menu bar
    public var cursorY: Double?         // a bird's cursor is anywhere on its screen (cursorX too)
    public var windows: [Win] = []      // other apps' ordinary windows on its screen, front to back
    public var windowClosed = false     // the window it's perched on has gone because it was closed (not minimised or another Space)
    public init(minX: Double, maxX: Double, hour: Double, userIdle: Double, cursorX: Double?, systemBusy: Bool = false,
                reduceMotion: Bool = false, kennelDoorOutside: Double = 88, kennelInside: ClosedRange<Double> = -16...0, mouthReach: Double = 28) {
        self.minX = minX; self.maxX = maxX; self.hour = hour; self.userIdle = userIdle; self.cursorX = cursorX; self.systemBusy = systemBusy
        self.reduceMotion = reduceMotion; self.kennelDoorOutside = kennelDoorOutside; self.kennelInside = kennelInside; self.mouthReach = mouthReach
    }
}

public enum Anim: String, Sendable { case stand, walk, run, zoom, sit, sleep, eat, drink, sniff, play, stretch, hop }

/// What the renderer draws.
public struct Pose: Sendable, Equatable {
    public var x: Double
    public var facing: Double
    public var anim: Anim
    public var carrying: String?
    public var emote: String?
    public var twitch: Bool
    public var jump: Double? = nil          // 0...1 through a jump, nil when on the ground
    public var jumpHeight: Double = 0       // points at the top of the arc
    public var crouch = false               // crouched just before a jump or just after landing
    public var attention: Attention? = nil
    public var lookX: Double? = nil         // where it is looking (cursor x) while attention is "head"
    public var hidden: Bool = false         // inside the kennel: draw nothing
    public var front: Bool = false          // sitting facing the viewer
    public var back: Bool = false           // sitting facing away
    public var play: PlayStyle? = nil       // chasing a ball, or shaking a plush or rope
    public var inKennel = false             // through the doorway or inside: the kennel's walls are in front of it
    public var sleepPos: SleepPos? = nil    // sleeping position while asleep
    public var inBed: String? = nil         // id of the bed it's lying in
    public var holding: PetObject? = nil    // the toy in its mouth (the renderer picks its art)
    public var toss = false                 // flinging the held toy up
    public var swipe = false                // paw raised, about to bat the ball
    public var wag = false                  // tail wagging
    public var groom: Groom? = nil
    public var fall: FallStage? = nil       // where it is in a stumble
    public var pace = 1.0                   // eating/drinking speed: gulpers chew and lap faster
    public var stretchBack = false          // second half of a stretch: the hind legs
    // A bird's
    public var y: Double? = nil             // feet, screen points from the top
    public var act: Act? = nil
    public var flight: FlightStage? = nil   // in the air, and how
    public var crest = false                // crest up: excited or startled
    public var wobble = false               // balancing
    public var since: Double? = nil         // an owl's hunt: seconds since it settled to stare
    public var toy = false                  // ...at its toy mouse (else at prey)
    public var caught = false               // it has its prey under its wings
    public var preening = false             // mid-bout (between bouts it stops and looks round)
}

/// Keeps a home tidy: a kennel exists, nothing overlaps the kennel, and everything sits inside the floor's range.
/// `halfWidth` gives each object's half width in points (from its art).
public func repairHome(_ objects: inout [PetObject], minX: Double, maxX: Double, halfWidth: (PetObject) -> Double) {
    if !objects.contains(where: { $0.kind == .kennel }) { objects.insert(PetObject(id: "kennel", kind: .kennel, x: minX + 20), at: 0) }
    for i in objects.indices { objects[i].x = min(max(objects[i].x, minX), maxX) }
    guard let k = objects.first(where: { $0.kind == .kennel }) else { return }
    var cursor = k.x + halfWidth(k) + 8
    for o in objects.filter({ $0.kind != .kennel }).sorted(by: { $0.x < $1.x }) where o.x < cursor + 200 {
        let half = halfWidth(o)
        guard let i = objects.firstIndex(where: { $0.id == o.id }) else { continue }
        if o.x - half < cursor { objects[i].x = cursor + half }
        cursor = max(cursor, objects[i].x + half + 8)
    }
}
