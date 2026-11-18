// Headless behaviour runner: fast-forwards dogs through simulated days and prints what they did.
// Usage: swift run -c release simrun [dogs=4] [hours=24] [firstSeed=1] [birds=1] [owls=1]
import Foundation
import PetCore

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
let dogs = Int(args.first ?? 4), hours = args.dropFirst().first ?? 24, firstSeed = UInt64(args.dropFirst(2).first ?? 1)
var failed = false

for seed in firstSeed..<(firstSeed + UInt64(dogs)) {
    let clock = Date()
    let r = simulate(seed: seed, hours: hours)
    let p = r.personality
    print(String(format: "=== dog seed %llu — %.0fh simulated in %.2fs, %d decisions", seed, hours, Date().timeIntervalSince(clock), r.decisions))
    print(String(format: "personality: play %.2f  lazy %.2f  affection %.2f  independent %.2f  curious %.2f  energy %.2f",
                 p.playfulness, p.laziness, p.affection, p.independence, p.curiosity, p.energy))
    print("jumps \(r.jumps) · runs \(r.runs) · cursor: glances \(r.glances), turns \(r.turns), follows \(r.follows) · front sits \(r.frontSits) · busy retreats \(r.busyRetreats)")
    print("time spent:")
    for (a, secs) in r.actTime.sorted(by: { $0.value > $1.value }) {
        let pct = secs / (hours * 36)
        print(String(format: "  %-11@ %5.1f%%  %@", a.rawValue, pct, String(repeating: "█", count: Int(pct / 2))))
    }
    let objects = r.prefs.keys.sorted()
    print("object interactions & developed preference (-1 dislikes … +1 loves):")
    for id in objects {
        let counts = r.interactions.filter { $0.key.hasSuffix(":" + id) }.sorted { $0.key < $1.key }
            .map { "\($0.key.split(separator: ":")[0])×\($0.value)" }.joined(separator: " ")
        print(String(format: "  %-7@ %+.2f  %@", id, r.prefs[id]!, counts))
    }
    print("hourly: " + r.timeline.joined(separator: " | "))
    if r.failures.isEmpty { print("invariants: OK\n") } else {
        failed = true
        print("INVARIANT FAILURES (\(r.failures.count)):"); for f in r.failures.prefix(10) { print("  ✗ " + f) }; print("")
    }
}
let birds = Int(args.dropFirst(3).first ?? 1), owls = Int(args.dropFirst(4).first ?? 1)
for (seed, species) in (firstSeed..<(firstSeed + UInt64(birds))).map({ ($0, Species.bird) }) + (firstSeed..<(firstSeed + UInt64(owls))).map({ ($0, Species.owl) }) {
    let clock = Date()
    let r = simulateBird(seed: seed, hours: hours, species: species)
    let p = r.personality
    print(String(format: "=== \(species.rawValue) seed %llu — %.0fh simulated in %.2fs, %d decisions", seed, hours, Date().timeIntervalSince(clock), r.decisions))
    print(String(format: "personality: play %.2f  lazy %.2f  affection %.2f  curious %.2f  energy %.2f  clumsy %.2f",
                 p.playfulness, p.laziness, p.affection, p.curiosity, p.energy, p.clumsy))
    print("flights \(r.flights) · falls \(r.falls) · window visits \(r.windowVisits) · ride ticks \(r.rides) · busy retreats \(r.busyRetreats)")
    for (a, secs) in r.actTime.sorted(by: { $0.value > $1.value }) {
        let pct = secs / (hours * 36)
        print(String(format: "  %-11@ %5.1f%%  %@", a.rawValue, pct, String(repeating: "█", count: Int(pct / 2))))
    }
    print("hourly: " + r.timeline.joined(separator: " | "))
    if r.failures.isEmpty { print("invariants: OK\n") } else {
        failed = true
        print("INVARIANT FAILURES (\(r.failures.count)):"); for f in r.failures.prefix(10) { print("  ✗ " + f) }; print("")
    }
}
exit(failed ? 1 : 0)
