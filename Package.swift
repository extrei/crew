// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crew",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Crew", targets: ["CrewApp"])],
    targets: [
        .target(name: "CrewCore"),
        .target(name: "CrewUI", dependencies: ["CrewCore"]),
        .executableTarget(name: "CrewApp", dependencies: ["CrewUI"]),
        .testTarget(name: "CrewCoreTests", dependencies: ["CrewCore"]),
        .testTarget(name: "CrewUITests", dependencies: ["CrewUI", "CrewCore"])
    ]
)
