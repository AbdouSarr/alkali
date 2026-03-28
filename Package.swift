// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Alkali",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AlkaliCore", targets: ["AlkaliCore"]),
        .library(name: "AlkaliCodeGraph", targets: ["AlkaliCodeGraph"]),
        .library(name: "AlkaliRenderer", targets: ["AlkaliRenderer"]),
        .library(name: "AlkaliPatcher", targets: ["AlkaliPatcher"]),
        .library(name: "AlkaliPreview", targets: ["AlkaliPreview"]),
        .library(name: "AlkaliDevTools", targets: ["AlkaliDevTools"]),
        .library(name: "AlkaliClient", targets: ["AlkaliClient"]),
        .executable(name: "alkali", targets: ["alkali"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.75.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.0.0"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "AlkaliCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),

        // MARK: - Code Graph
        .target(
            name: "AlkaliCodeGraph",
            dependencies: [
                "AlkaliCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),

        // MARK: - Renderer
        .target(
            name: "AlkaliRenderer",
            dependencies: [
                "AlkaliCore",
                "AlkaliCodeGraph",
            ]
        ),

        // MARK: - Patcher
        .target(
            name: "AlkaliPatcher",
            dependencies: [
                "AlkaliCore",
            ]
        ),

        // MARK: - Preview Engine (Ability A)
        .target(
            name: "AlkaliPreview",
            dependencies: [
                "AlkaliCore",
                "AlkaliCodeGraph",
                "AlkaliRenderer",
            ]
        ),

        // MARK: - DevTools (Ability B)
        .target(
            name: "AlkaliDevTools",
            dependencies: [
                "AlkaliCore",
                "AlkaliPatcher",
            ]
        ),

        // MARK: - Server (Daemon + MCP + WebSocket)
        .target(
            name: "AlkaliServer",
            dependencies: [
                "AlkaliCore",
                "AlkaliCodeGraph",
                "AlkaliRenderer",
                "AlkaliPatcher",
                "AlkaliPreview",
                "AlkaliDevTools",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),

        // MARK: - Client
        .target(
            name: "AlkaliClient",
            dependencies: [
                "AlkaliCore",
            ]
        ),

        // MARK: - CLI
        .executableTarget(
            name: "alkali",
            dependencies: [
                "AlkaliCore",
                "AlkaliCodeGraph",
                "AlkaliPreview",
                "AlkaliRenderer",
                "AlkaliDevTools",
                "AlkaliServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "AlkaliCoreTests",
            dependencies: ["AlkaliCore"]
        ),
        .testTarget(
            name: "AlkaliCodeGraphTests",
            dependencies: ["AlkaliCodeGraph", "AlkaliCore"]
        ),
        .testTarget(
            name: "AlkaliRendererTests",
            dependencies: ["AlkaliRenderer", "AlkaliCore"]
        ),
        .testTarget(
            name: "AlkaliPatcherTests",
            dependencies: ["AlkaliPatcher", "AlkaliDevTools", "AlkaliCore"]
        ),
        .testTarget(
            name: "AlkaliPreviewTests",
            dependencies: ["AlkaliPreview", "AlkaliRenderer", "AlkaliCore"]
        ),
    ]
)
