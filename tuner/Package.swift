// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlackHoleTuner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BlackHoleTuner", path: "Sources/BlackHoleTuner")
    ]
)
