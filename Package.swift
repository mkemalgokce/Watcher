// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Watcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WatcherCore", targets: ["WatcherCore"]),
        .library(name: "WatcherUI", targets: ["WatcherUI"]),
        .executable(name: "watcher-cli", targets: ["watcher-cli"]),
        .executable(name: "Watcher", targets: ["Watcher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.75.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.34.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.25.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.6"),
    ],
    targets: [
        .target(
            name: "TreeSitterScanners",
            path: "Sources/TreeSitterScanners",
            exclude: ["README.md", "LICENSE"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "WatcherCore",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                "SwiftTreeSitter", "TreeSitterScanners",
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "watcher-cli",
            dependencies: [
                "WatcherCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "WatcherUI",
            dependencies: ["WatcherCore"],
            resources: [.copy("Resources/AppIcon.icns")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Watcher",
            dependencies: ["WatcherUI", "WatcherCore"],
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags([
                "-Xlinker",
                "-sectcreate",
                "-Xlinker",
                "__TEXT",
                "-Xlinker",
                "__info_plist",
                "-Xlinker",
                "Sources/Watcher/Info.plist",
                "-Xlinker",
                "-platform_version",
                "-Xlinker",
                "macos",
                "-Xlinker",
                "14.0",
                "-Xlinker",
                "27.0",
            ])]
        ),
        .target(
            name: "WatcherTestSupport",
            dependencies: [
                "WatcherCore",
                "WatcherUI",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            path: "Tests/WatcherTestSupport",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherUITests",
            dependencies: ["WatcherUI", "WatcherCore", "WatcherTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherInteractionTests",
            dependencies: ["WatcherUI", "WatcherCore", "WatcherTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherCoreTests",
            dependencies: ["WatcherCore", "WatcherTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherIntegrationTests",
            dependencies: ["WatcherCore", "WatcherUI", "WatcherTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherE2ETests",
            // Listed so that `swift test` builds the binary these tests launch.
            dependencies: ["WatcherCore", "WatcherTestSupport", "watcher-cli"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WatcherSnapshotTests",
            dependencies: [
                "WatcherCore",
                "WatcherUI",
                "WatcherTestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
