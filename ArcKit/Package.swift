// swift-tools-version: 5.10
import PackageDescription

// ArcKit: the parts of the Apple app that don't draw anything (Arc's /api/v1 client, its models,
// Home's rows, the playback clock). Foundation only, so `swift test` runs it on any Mac.
let package = Package(
    name: "ArcKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ArcKit", targets: ["ArcKit"])],
    targets: [
        .target(name: "ArcKit"),
        .testTarget(name: "ArcKitTests", dependencies: ["ArcKit"]),
    ]
)
