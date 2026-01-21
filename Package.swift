// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-ops",
    platforms: [
        .macOS(.v14)  // Need macOS 14 for modern SwiftUI features
    ],
    products: [
        .library(name: "ServerLib", targets: ["ServerLib"]),
        .executable(name: "claude-ops-server", targets: ["Server"]),
        .executable(name: "ClaudeOps", targets: ["ClaudeOps"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.19.0"),
    ],
    targets: [
        // Shared server library
        .target(
            name: "ServerLib",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            ],
            path: "Sources/ServerLib"
        ),
        // CLI server executable
        .executableTarget(
            name: "Server",
            dependencies: ["ServerLib"],
            path: "Sources/Server"
        ),
        // macOS menu bar app
        .executableTarget(
            name: "ClaudeOps",
            dependencies: ["ServerLib"],
            path: "Sources/ClaudeOps"
        ),
    ]
)
