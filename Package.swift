// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UsageTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "UsageTracker", path: "Sources/UsageTracker")
    ]
)
