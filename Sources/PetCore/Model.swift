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

    public static func random(_ rng: inout SplitMix) -> Personality {
        var t = [Double]()
        for _ in 0..<6 { t.append(Double.random(in: 0.1...0.95, using: &rng)) }
        return Personality(playfulness: t[0], laziness: t[1], affection: t[2], independence: t[3], curiosity: t[4], energy: t[5])
    }
}

public enum Kind: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case bed, rug, foodBowl, waterBowl, ball, plush, rope, kennel
    case floor // not placeable: "sleeping on the bare floor" as a sleep spot with its own preference
    public var isToy: Bool { self == .ball || self == .plush || self == .rope }
    public var isSleepSpot: Bool { self == .bed || self == .rug }
}

public struct PetObject: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kind: Kind
    public var x: Double // centre, points along the floor
    public var addedAt: Double
    public init(id: String, kind: Kind, x: Double, addedAt: Double = -1e9) {
        self.id = id; self.kind = kind; self.x = x; self.addedAt = addedAt
    }
}

public enum Act: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case idle, sit, lookAround, wander, sniff, sleep, stretch, groom, eat, drink, play, carry, zoomies, greet, react, follow, kennel

    /// Walking pace, points/s. Running (Activity.running) is 130; zoomies are always a sprint.
    var speed: Double { switch self { case .zoomies: 170; case .greet, .follow: 50; default: 42 } }

    /// Minimum seconds before the same act scores normally again.
    var cooldown: Double {
        switch self {
        case .zoomies: 1800; case .greet: 600; case .follow: 90; case .kennel: 1800; case .eat: 1200; case .drink: 600; case .stretch: 120; default: 0
        }
    }

    /// Seconds spent performing once at the destination.
    var duration: ClosedRange<Double> {
        switch self {
        case .idle: 4...15; case .sit: 8...40; case .lookAround: 3...8; case .wander: 1...3
        case .sniff: 3...8; case .sleep: 900...5400; case .stretch: 2.5...3.5; case .groom: 6...15
        case .eat: 15...30; case .drink: 5...10; case .play: 15...60; case .carry: 1...2
        case .zoomies: 6...12; case .greet: 5...12; case .react: 1...1.5; case .follow: 6...14; case .kennel: 180...900
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

public struct Activity: Codable, Sendable, Equatable {
    public var act: Act
    public var target: String?
    public var destX: Double?   // walking there first while non-nil
    public var remaining: Double
    public var started: Double
    public var running: Bool? = nil   // run instead of walk to the destination (optional: older saves load)
    public var front: Bool? = nil     // sitting facing the viewer
    public var back: Bool? = nil      // sitting with its back to the viewer
    public var phase: String? = nil   // kennel visit: "door" → "enter" → "inside" → "exit"
}

public struct Memory: Codable, Sendable, Equatable {
    public var t: Double
    public var act: Act
    public var target: String?
    public var enjoyment: Double?
}

/// Everything about the dog that persists between launches.
public struct DogState: Codable, Sendable, Equatable {
    public var version = 1
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
    public var attention: String?         // "head", "body" or "follow": how it is reacting to the cursor
    public var attentionUntil: Double?
    public var attentionCooldown: Double?
    public var lastCursorX: Double?
    public var busyRetreat: Bool?       // went into the kennel because the Mac was busy
    public var nextRoll: Double?        // when the ball it's playing with next rolls away
    public var nextDream: Double?       // when the next dream (twitching) starts while asleep
    public var sleepPos: String?        // "flat", "curl", "side" or "belly"
    public var posTaste: [String: Double]?   // hidden liking for each sleeping position, rolled once
    public var tossUntil: Double?       // tossing the toy it's holding up in the air
    public var pendingCarry: String?    // pick this toy up and trot off with it next
}

/// What the outside world tells the brain each tick.
public struct Environment: Sendable {
    public var minX: Double, maxX: Double
    public var hour: Double       // local time of day, 0..<24
    public var userIdle: Double   // seconds since the user last touched mouse/keyboard
    public var cursorX: Double?   // set when the cursor is near the dog's floor
    public var systemBusy: Bool   // the Mac is under heavy load: the dog keeps out of the way in its kennel
    public init(minX: Double, maxX: Double, hour: Double, userIdle: Double, cursorX: Double?, systemBusy: Bool = false) {
        self.minX = minX; self.maxX = maxX; self.hour = hour; self.userIdle = userIdle; self.cursorX = cursorX; self.systemBusy = systemBusy
    }
}

public enum Anim: String, Sendable { case stand, walk, run, zoom, sit, sleep, headDown, play, stretch, hop }

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
    public var attention: String? = nil     // "head", "body", "follow"
    public var lookX: Double? = nil         // where it is looking (cursor x) while attention is "head"
    public var hidden: Bool = false         // inside the kennel: draw nothing
    public var front: Bool = false          // sitting facing the viewer
    public var back: Bool = false           // sitting facing away
    public var play: String? = nil          // "chase" (balls) or "shake" (plush, rope) while playing
    public var inKennel = false             // through the doorway or inside: the kennel's walls are in front of it
    public var sleepPos: String? = nil      // sleeping position while asleep
    public var inBed: String? = nil         // id of the bed it's lying in
    public var holding: String? = nil       // toy art in its mouth: "ball", "tennis", "plush" or "rope"
    public var toss = false                 // flinging the held toy up
}
