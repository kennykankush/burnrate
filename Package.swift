// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "burnrate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "burnrate", targets: ["Burnrate"]),
    ],
    targets: [
        .target(
            name: "BurnrateCore",
            path: "Sources/BurnrateCore"
        ),
        .executableTarget(
            name: "Burnrate",
            dependencies: ["BurnrateCore"],
            path: "Sources/Burnrate",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
