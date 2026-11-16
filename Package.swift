// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WritingHelper",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "WritingCore"),
        .executableTarget(name: "WritingHelper", dependencies: ["WritingCore"]),
        .testTarget(name: "WritingCoreTests", dependencies: ["WritingCore"], resources: [.copy("Fixtures")]),
    ]
)
