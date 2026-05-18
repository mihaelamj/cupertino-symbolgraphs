@testable import AppleSymbolGraphsKit
import Foundation
import Testing

@Suite("Manifest; schema + aggregation")
struct ManifestTests {
    private func sampleResults() -> [ExtractionResult] {
        [
            ExtractionResult(slug: "swiftui",  moduleName: "SwiftUI",  targetTriple: "arm64-apple-macos15", status: .ok,      sizeBytes: 100_000, fileCount: 7, errorMessage: nil),
            ExtractionResult(slug: "uikit",    moduleName: "UIKit",    targetTriple: "arm64-apple-ios18",   status: .ok,      sizeBytes:  50_000, fileCount: 5, errorMessage: nil),
            ExtractionResult(slug: "messages", moduleName: "Messages", targetTriple: "arm64-apple-ios18",   status: .ok,      sizeBytes:  20_000, fileCount: 2, errorMessage: nil),
            ExtractionResult(slug: "broken",   moduleName: "Broken",   targetTriple: "arm64-apple-macos15", status: .failed,  sizeBytes:  0,      fileCount: 0, errorMessage: "bad input"),
            ExtractionResult(slug: "sirikit",  moduleName: "SiriKit",  targetTriple: "arm64-apple-macos15", status: .skipped, sizeBytes:  0,      fileCount: 0, errorMessage: "deprecated"),
        ]
    }

    @Test("Summary aggregates across all results")
    func aggregateTotals() {
        let m = Manifest(
            generatedAt: "2026-05-18T00:00:00Z",
            swiftVersion: "Apple Swift version 6.3.2",
            targets: [
                .init(targetTriple: "arm64-apple-macos15", sdkPath: "/M", sdkVersion: "26.4"),
                .init(targetTriple: "arm64-apple-ios18", sdkPath: "/I", sdkVersion: "26.5"),
            ],
            results: sampleResults()
        )
        #expect(m.summary.totalSlugs == 5)
        #expect(m.summary.okCount == 3)
        #expect(m.summary.failedCount == 1)
        #expect(m.summary.skippedCount == 1)
        #expect(m.summary.totalBytes == 170_000)
    }

    @Test("bytesPerTarget + slugsPerTarget split by extracting target")
    func perTargetSplit() {
        let m = Manifest(
            generatedAt: "2026-05-18T00:00:00Z",
            swiftVersion: "x",
            targets: [
                .init(targetTriple: "arm64-apple-macos15", sdkPath: "/M", sdkVersion: "26.4"),
                .init(targetTriple: "arm64-apple-ios18", sdkPath: "/I", sdkVersion: "26.5"),
            ],
            results: sampleResults()
        )
        #expect(m.summary.bytesPerTarget["arm64-apple-macos15"] == 100_000)
        #expect(m.summary.bytesPerTarget["arm64-apple-ios18"] == 70_000)
        #expect(m.summary.slugsPerTarget["arm64-apple-macos15"] == 1)
        #expect(m.summary.slugsPerTarget["arm64-apple-ios18"] == 2)
    }

    @Test("Results are sorted by slug for stable diffs")
    func resultsSorted() {
        let m = Manifest(
            generatedAt: "x",
            swiftVersion: "x",
            targets: [.init(targetTriple: "x", sdkPath: "x", sdkVersion: "x")],
            results: sampleResults()
        )
        let slugs = m.results.map(\.slug)
        #expect(slugs == ["broken", "messages", "sirikit", "swiftui", "uikit"])
    }

    @Test("encodedJSON produces sorted-keys pretty JSON that round-trips")
    func jsonRoundtrip() throws {
        let original = Manifest(
            generatedAt: "2026-05-18T00:00:00Z",
            swiftVersion: "x",
            targets: [.init(targetTriple: "x", sdkPath: "/x", sdkVersion: "1.0")],
            results: sampleResults()
        )
        let data = try original.encodedJSON()
        let asString = String(decoding: data, as: UTF8.self)
        // sorted keys → "failedCount" appears before "okCount"
        let failedIdx = asString.range(of: "\"failedCount\"")?.lowerBound
        let okIdx = asString.range(of: "\"okCount\"")?.lowerBound
        #expect(failedIdx != nil && okIdx != nil)
        if let failedIdx, let okIdx { #expect(failedIdx < okIdx) }
        // round-trip
        let decoded = try JSONDecoder().decode(Manifest.self, from: data)
        #expect(decoded.summary.totalSlugs == original.summary.totalSlugs)
        #expect(decoded.results.count == original.results.count)
        #expect(decoded.manifestVersion == Manifest.currentVersion)
    }

    @Test("ManifestVersion is current schema (3)")
    func manifestVersionIsCurrent() {
        #expect(Manifest.currentVersion == 3)
    }
}

@Suite("SymbolGraphExtractor; directory hygiene")
struct ExtractorHygieneTests {
    @Test("emptyDirectoryContents removes children but keeps the dir")
    func emptyDirRemovesChildrenOnly() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-hygiene-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "A".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "B".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).count == 2)

        try SymbolGraphExtractor.emptyDirectoryContents(tmp)

        #expect(FileManager.default.fileExists(atPath: tmp.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).isEmpty)
    }

    @Test("Multi-target init preserves order")
    func multiTargetOrder() {
        let tmp = FileManager.default.temporaryDirectory
        let ext = SymbolGraphExtractor(
            targets: [
                ExtractionTarget(sdkPath: "/MacOSX.sdk", targetTriple: "arm64-apple-macos15"),
                ExtractionTarget(sdkPath: "/iPhoneOS.sdk", targetTriple: "arm64-apple-ios18"),
            ],
            outputRoot: tmp
        )
        #expect(ext.targets.count == 2)
        #expect(ext.targets[0].targetTriple == "arm64-apple-macos15")
        #expect(ext.targets[1].targetTriple == "arm64-apple-ios18")
    }
}
