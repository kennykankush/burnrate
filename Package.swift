// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "bwernrate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bwernrate", targets: ["Bwernrate"]),
    ],
    targets: [
        .target(
            name: "BwernrateCore",
            path: "Sources/BwernrateCore"
        ),
        .executableTarget(
            name: "Bwernrate",
            dependencies: ["BwernrateCore"],
            path: "Sources/Bwernrate"
        ),
    ]
)
