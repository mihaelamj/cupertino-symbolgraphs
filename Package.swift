// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cupertino-symbolgraphs",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // Library that other tools (e.g. cupertino's AppleConstraintsKit) can
        // consume to know which Apple framework slugs map to which Swift
        // module names. Foundation-only.
        .library(
            name: "AppleSymbolGraphsKit",
            targets: ["AppleSymbolGraphsKit"]
        ),
        // CLI binary that runs `xcrun swift symbolgraph-extract` for every
        // Apple framework in the manifest, validates output against the
        // SDK's ground-truth Swift module list, and writes a per-version
        // corpus directory + manifest.json.
        .executable(
            name: "cupertino-symbolgraphs-gen",
            targets: ["cupertino-symbolgraphs-gen"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AppleSymbolGraphsKit",
            dependencies: []
        ),
        .executableTarget(
            name: "cupertino-symbolgraphs-gen",
            dependencies: [
                "AppleSymbolGraphsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "AppleSymbolGraphsKitTests",
            dependencies: ["AppleSymbolGraphsKit"],
            // Fixture file the BrewDBCoverageTests suite reads at runtime;
            // declared explicitly so SwiftPM doesn't warn about an
            // unhandled file under the test target dir.
            resources: [
                .copy("Fixtures/cupertino-brew-framework-slugs-v1.0.2.txt"),
                .copy("Fixtures/cupertino-dev-framework-slugs-v1.0.x.txt"),
            ]
        ),
    ]
)
