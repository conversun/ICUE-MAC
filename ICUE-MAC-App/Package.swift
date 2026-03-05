// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICUE-MAC-App",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ICUE-MAC-App",
            path: "Sources/ICUE-MAC-App",
            resources: [.copy("Resources")]
        )
    ]
)
