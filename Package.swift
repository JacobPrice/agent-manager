// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "agent-manager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agentctl", targets: ["agentctl"]),
        .executable(name: "AgentManagerGUI", targets: ["AgentManagerGUI"]),
        .library(name: "AgentManagerCore", targets: ["AgentManagerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "agentctl",
            dependencies: [
                "AgentManagerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "AgentManagerGUI",
            dependencies: [
                "AgentManagerCore",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "AgentManagerCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "AgentManagerCoreTests",
            dependencies: ["AgentManagerCore"]
        ),
    ]
)
