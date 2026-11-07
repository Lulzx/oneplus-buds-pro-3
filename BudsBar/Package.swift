// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BudsBar",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
