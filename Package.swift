// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PetCore"), // behaviour engine: no AppKit, deterministic given a seed
        .executableTarget(name: "LittleCompanion", dependencies: ["PetCore"], resources: [.copy("Resources/ollie.png"), .copy("Resources/biscuit.png"), .copy("Resources/mochi.png"), .copy("Resources/bean.png"), .copy("Resources/pepper.png"), .copy("Resources/mango.png"), .copy("Resources/pearl.png"), .copy("Resources/kiwi.png"), .copy("Resources/sunny.png"), .copy("Resources/objects.png"), .copy("Resources/objects.json")]),
        .executableTarget(name: "simrun", dependencies: ["PetCore"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
    ]
)
