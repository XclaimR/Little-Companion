// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LittleCompanion", path: "Sources/LittleCompanion"),
    ]
)
