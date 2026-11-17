// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blacktop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Blacktop",
            path: "Sources/Blacktop"
        )
    ]
)
