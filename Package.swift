// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glassmorphism",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Glassmorphism",
            path: "Sources/Glassmorphism"
        )
    ]
)
