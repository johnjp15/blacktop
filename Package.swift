// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blackbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Blackbar",
            path: "Sources/Blackbar"
        )
    ]
)
