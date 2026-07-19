// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenSwitch",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "OpenSwitch",
            path: "Sources/OpenSwitch"
        )
    ]
)
