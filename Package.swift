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
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        // Shared server library
        .target(
            name: "ServerLib",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "GRDB", package: "GRDB.swift"),
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
        // Tests
        .testTarget(
            name: "ServerLibTests",
            dependencies: ["ServerLib"],
            path: "Tests/ServerLibTests"
        ),
    ]
)
