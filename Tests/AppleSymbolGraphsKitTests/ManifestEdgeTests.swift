@testable import AppleSymbolGraphsKit
import Foundation
import Testing

@Suite("Manifest; edge cases + invariants")
struct ManifestEdgeTests {
    @Test("Empty results produce a zeroed Summary, not a crash")
    func emptyResults() {
        let m = Manifest(
            generatedAt: "x",
            swiftVersion: "x",
            targets: [.init(targetTriple: "arm64-apple-macos15", sdkPath: "/x", sdkVersion: "1.0")],
            results: []
        )
        #expect(m.summary.totalSlugs == 0)
        #expect(m.summary.okCount == 0)
        #expect(m.summary.failedCount == 0)
        #expect(m.summary.skippedCount == 0)
        #expect(m.summary.totalBytes == 0)
        #expect(m.summary.bytesPerTarget.isEmpty)
        #expect(m.summary.slugsPerTarget.isEmpty)
    }

    @Test("All-skipped results: bytesPerTarget + slugsPerTarget stay empty (skipped ≠ ok)")
    func allSkipped() {
        let results = (1 ... 3).map { i in
            ExtractionResult(
                slug: "slug\(i)", moduleName: "M\(i)",
                targetTriple: "arm64-apple-macos15", status: .skipped,
                sizeBytes: 0, fileCount: 0, errorMessage: "test reason \(i)"
            )
        }
        let m = Manifest(
            generatedAt: "x", swiftVersion: "x",
            targets: [.init(targetTriple: "arm64-apple-macos15", sdkPath: "/x", sdkVersion: "1.0")],
            results: results
        )
        #expect(m.summary.skippedCount == 3)
        #expect(m.summary.okCount == 0)
        #expect(m.summary.failedCount == 0)
        #expect(m.summary.totalBytes == 0)
        #expect(m.summary.bytesPerTarget.isEmpty, "skipped results must not contribute to bytesPerTarget")
        #expect(m.summary.slugsPerTarget.isEmpty, "skipped results must not contribute to slugsPerTarget")
    }

    @Test("All-failed results: bytesPerTarget + slugsPerTarget stay empty")
    func allFailed() {
        let results = (1 ... 3).map { i in
            ExtractionResult(
                slug: "slug\(i)", moduleName: "M\(i)",
                targetTriple: "arm64-apple-macos15", status: .failed,
                sizeBytes: 0, fileCount: 0, errorMessage: "fail \(i)"
            )
        }
        let m = Manifest(
            generatedAt: "x", swiftVersion: "x",
            targets: [.init(targetTriple: "arm64-apple-macos15", sdkPath: "/x", sdkVersion: "1.0")],
            results: results
        )
        #expect(m.summary.failedCount == 3)
        #expect(m.summary.bytesPerTarget.isEmpty)
        #expect(m.summary.slugsPerTarget.isEmpty)
    }

    @Test("Single-target manifest: bytesPerTarget has exactly one key")
    func singleTarget() {
        let results = [
            ExtractionResult(slug: "a", moduleName: "A", targetTriple: "arm64-apple-macos15", status: .ok, sizeBytes: 100, fileCount: 1, errorMessage: nil),
            ExtractionResult(slug: "b", moduleName: "B", targetTriple: "arm64-apple-macos15", status: .ok, sizeBytes: 200, fileCount: 2, errorMessage: nil),
        ]
        let m = Manifest(
            generatedAt: "x", swiftVersion: "x",
            targets: [.init(targetTriple: "arm64-apple-macos15", sdkPath: "/x", sdkVersion: "1.0")],
            results: results
        )
        #expect(m.summary.bytesPerTarget.count == 1)
        #expect(m.summary.bytesPerTarget["arm64-apple-macos15"] == 300)
        #expect(m.summary.slugsPerTarget["arm64-apple-macos15"] == 2)
    }

    @Test("currentVersion is monotonically positive")
    func currentVersionSane() {
        #expect(Manifest.currentVersion > 0)
        #expect(Manifest.currentVersion == 3, "if you bump this, also bump consumers + write a migration note")
    }

    @Test("Encoded JSON is pretty-printed (multi-line, with indentation)")
    func encodedIsPretty() throws {
        let m = Manifest(
            generatedAt: "x", swiftVersion: "x",
            targets: [.init(targetTriple: "x", sdkPath: "x", sdkVersion: "x")],
            results: []
        )
        let data = try m.encodedJSON()
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("\n"), "expected pretty-printed (multi-line) JSON")
        #expect(str.contains("  "), "expected indentation")
    }

    @Test("Results stay sorted even when caller passes them out-of-order")
    func sortsUnsortedInput() {
        let results = [
            ExtractionResult(slug: "zoo", moduleName: "Zoo", targetTriple: "x", status: .ok, sizeBytes: 1, fileCount: 1, errorMessage: nil),
            ExtractionResult(slug: "alpha", moduleName: "Alpha", targetTriple: "x", status: .ok, sizeBytes: 1, fileCount: 1, errorMessage: nil),
            ExtractionResult(slug: "mid", moduleName: "Mid", targetTriple: "x", status: .ok, sizeBytes: 1, fileCount: 1, errorMessage: nil),
        ]
        let m = Manifest(
            generatedAt: "x", swiftVersion: "x",
            targets: [.init(targetTriple: "x", sdkPath: "x", sdkVersion: "x")],
            results: results
        )
        #expect(m.results.map(\.slug) == ["alpha", "mid", "zoo"])
    }

    @Test("TargetEntry round-trips through JSON")
    func targetEntryRoundTrip() throws {
        let original = Manifest.TargetEntry(
            targetTriple: "arm64-apple-macos15",
            sdkPath: "/Applications/Xcode.app/.../MacOSX.sdk",
            sdkVersion: "26.4"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Manifest.TargetEntry.self, from: data)
        #expect(decoded.targetTriple == original.targetTriple)
        #expect(decoded.sdkPath == original.sdkPath)
        #expect(decoded.sdkVersion == original.sdkVersion)
    }

    @Test("Encoded JSON contains all top-level keys consumers depend on")
    func encodedHasAllKeys() throws {
        let m = Manifest(
            generatedAt: "2026-05-18T00:00:00Z", swiftVersion: "Apple Swift version 6.3.2",
            targets: [.init(targetTriple: "arm64-apple-macos15", sdkPath: "/x", sdkVersion: "26.4")],
            results: []
        )
        let str = String(decoding: try m.encodedJSON(), as: UTF8.self)
        // Top-level keys consumers parse:
        for key in ["manifestVersion", "generatedAt", "swiftVersion", "targets", "results", "summary"] {
            #expect(str.contains("\"\(key)\""), "encoded JSON missing key '\(key)'")
        }
        // Summary keys:
        for key in ["totalSlugs", "okCount", "failedCount", "skippedCount", "totalBytes", "bytesPerTarget", "slugsPerTarget"] {
            #expect(str.contains("\"\(key)\""), "encoded JSON summary missing key '\(key)'")
        }
    }
}

@Suite("Manifest; golden-file regression against shipped v0.1.0")
struct ManifestGoldenFileTests {
    /// Path to the manifest committed in the git tree at the v0.1.0 tag.
    /// If this test fails, either (a) the shipped manifest changed shape
    /// and Manifest schema needs updating, or (b) Manifest schema changed
    /// and consumers reading the shipped corpus need re-pinning.
    private static let goldenPath: String = {
        // Resolve via the package dir; same machine as the source tree.
        let candidates = [
            "/Volumes/Code/DeveloperExt/public/cupertino-symbolgraphs/manifest.json",
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? ""
    }()

    private static let goldenAvailable: Bool = !goldenPath.isEmpty

    @Test("Shipped manifest.json decodes into Manifest with no errors", .enabled(if: goldenAvailable))
    func goldenDecodes() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.goldenPath))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        // Sanity facts about the v0.1.0 corpus we shipped.
        #expect(m.manifestVersion == 3)
        #expect(m.summary.totalSlugs == 274)
        #expect(m.summary.okCount == 265)
        #expect(m.summary.skippedCount == 9)
        #expect(m.summary.failedCount == 0)
        #expect(m.targets.count == 4)
        #expect(m.swiftVersion.contains("Swift"))
    }

    @Test("Shipped manifest's per-target split matches v0.1.0 release-notes numbers",
          .enabled(if: goldenAvailable))
    func goldenPerTargetShape() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.goldenPath))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        // From the v0.1.0 release notes:
        //   221 macOS / 40 iOS / 3 visionOS / 1 watchOS
        #expect(m.summary.slugsPerTarget["arm64-apple-macos15"] == 221)
        #expect(m.summary.slugsPerTarget["arm64-apple-ios18"] == 40)
        #expect(m.summary.slugsPerTarget["arm64-apple-xros2"] == 3)
        #expect(m.summary.slugsPerTarget["arm64_32-apple-watchos11"] == 1)
        #expect(m.summary.slugsPerTarget.values.reduce(0, +) == 265)
    }

    @Test("Every result in the shipped manifest carries a non-empty slug + valid status",
          .enabled(if: goldenAvailable))
    func goldenResultsWellFormed() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.goldenPath))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        for r in m.results {
            #expect(!r.slug.isEmpty, "empty slug in shipped manifest")
            #expect(!r.moduleName.isEmpty, "empty moduleName in shipped manifest for '\(r.slug)'")
            #expect(!r.targetTriple.isEmpty, "empty targetTriple in shipped manifest for '\(r.slug)'")
            if r.status == .ok {
                #expect(r.sizeBytes > 0, "ok result '\(r.slug)' has zero sizeBytes")
                #expect(r.fileCount >= 1, "ok result '\(r.slug)' has zero fileCount")
                #expect(r.errorMessage == nil, "ok result '\(r.slug)' has errorMessage: \(r.errorMessage ?? "")")
            } else {
                #expect(r.sizeBytes == 0, "non-ok result '\(r.slug)' has non-zero sizeBytes")
                #expect(r.fileCount == 0, "non-ok result '\(r.slug)' has non-zero fileCount")
                #expect(r.errorMessage != nil, "non-ok result '\(r.slug)' has no errorMessage")
            }
        }
    }
}
