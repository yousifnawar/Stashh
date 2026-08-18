// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stash",
            path: "Sources/Stash",
            swiftSettings: [.unsafeFlags(["-suppress-warnings"])]
        )
    ]
)
