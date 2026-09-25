// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CheetWithBothHands",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CheetWithBothHands", targets: ["CheetWithBothHands"]),
        .library(name: "CheetCore", targets: ["CheetCore"]),
    ],
    targets: [
        .target(name: "CheetCore"),
        .executableTarget(
            name: "CheetWithBothHands",
            dependencies: ["CheetCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "CheetCoreTests", dependencies: ["CheetCore"]),
    ]
)
