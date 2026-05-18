@testable import AppleSymbolGraphsKit
import Foundation
import Testing

/// Edge-case suite for SymbolGraphExtractor's pure surface (no real
/// xcrun spawns). End-to-end behaviour lives in
/// `SymbolGraphExtractorIntegrationTests`; this file pins logic in the
/// variant generator + the multi-target ordering + the FX-search-path
/// argument plumbing.
@Suite("SymbolGraphExtractor — pure-logic edge cases")
struct SymbolGraphExtractorEdgeTests {
    @Test("variantsToTry: curated entry leads the list when present")
    func curatedLeadsVariants() {
        // SwiftUI's curated name "SwiftUI" differs from the PascalCase
        // fallback "Swiftui" — the curated form must be tried first
        // because it's the only one the extractor will actually accept.
        let variants = SymbolGraphExtractor.variantsToTry(for: "swiftui")
        #expect(variants.first == "SwiftUI", "expected 'SwiftUI' to lead, got \(variants)")
    }

    @Test("variantsToTry: PascalCase leads when no curated entry exists")
    func pascalCaseLeadsForUncurated() {
        // A slug not in the curated map: PascalCase fallback should
        // appear first (since curated injects nothing).
        let variants = SymbolGraphExtractor.variantsToTry(for: "imaginary-framework-slug-xyz")
        // Note the hyphen — the slug is preserved verbatim in non-PascalCase variants.
        #expect(variants.first == "Imaginary-framework-slug-xyz",
                "expected PascalCase fallback first, got \(variants)")
    }

    @Test("variantsToTry: never produces duplicates")
    func neverDuplicates() {
        // For a slug where curated, PascalCase fallback, and uppercase
        // happen to overlap, we should see each unique name once.
        for slug in FrameworkModuleMap.allCuratedSlugs {
            let variants = SymbolGraphExtractor.variantsToTry(for: slug)
            #expect(variants.count == Set(variants).count,
                    "duplicates in variants for slug '\(slug)': \(variants)")
        }
    }

    @Test("variantsToTry: includes slug verbatim + uppercase as final fallbacks")
    func includesSlugAndUppercase() {
        // For a generic slug, the full list should contain: PascalCase,
        // slug-as-is, and ALL-UPPERCASE. (Curated leads only when the
        // slug is curated.)
        let variants = SymbolGraphExtractor.variantsToTry(for: "imaginaryslug")
        #expect(variants.contains("imaginaryslug"))
        #expect(variants.contains("IMAGINARYSLUG"))
    }

    @Test("variantsToTry: empty slug returns empty (or single empty entry)")
    func emptySlugVariants() {
        // Defensive: empty slug. PascalCase("") = "", upper("") = "",
        // de-dup collapses to one empty entry — extractor will short-
        // circuit at xcrun anyway. The pure helper just shouldn't crash.
        let variants = SymbolGraphExtractor.variantsToTry(for: "")
        // No crash → pass. Document: produces at most one entry (after dedup).
        #expect(variants.count <= 1, "empty slug produced \(variants.count) variants: \(variants)")
    }

    @Test("ExtractionTarget legacy convenience init defaults to empty FX search paths")
    func legacyInitEmptyFX() {
        let t = ExtractionTarget(sdkPath: "/x", targetTriple: "arm64-apple-macos15")
        #expect(t.extraFrameworkSearchPaths.isEmpty)
    }

    @Test("SymbolGraphExtractor single-target convenience init preserves SDK + target")
    func singleTargetConvenience() {
        let url = URL(fileURLWithPath: "/tmp/out")
        let ext = SymbolGraphExtractor(
            sdkPath: "/sdk",
            targetTriple: "arm64-apple-macos15",
            outputRoot: url
        )
        #expect(ext.targets.count == 1)
        #expect(ext.targets[0].sdkPath == "/sdk")
        #expect(ext.targets[0].targetTriple == "arm64-apple-macos15")
        #expect(ext.targets[0].extraFrameworkSearchPaths.isEmpty)
        #expect(ext.outputRoot == url)
    }

    @Test("SymbolGraphExtractor multi-target init keeps target order stable across re-reads")
    func multiTargetOrderStable() {
        let ts = [
            ExtractionTarget(sdkPath: "/m", targetTriple: "arm64-apple-macos15"),
            ExtractionTarget(sdkPath: "/i", targetTriple: "arm64-apple-ios18"),
            ExtractionTarget(sdkPath: "/w", targetTriple: "arm64_32-apple-watchos11"),
            ExtractionTarget(sdkPath: "/x", targetTriple: "arm64-apple-xros2"),
        ]
        let ext = SymbolGraphExtractor(targets: ts, outputRoot: URL(fileURLWithPath: "/tmp"))
        let first = ext.targets.map(\.targetTriple)
        let second = ext.targets.map(\.targetTriple)
        #expect(first == second, "targets must be stable across reads")
        #expect(first == ["arm64-apple-macos15", "arm64-apple-ios18", "arm64_32-apple-watchos11", "arm64-apple-xros2"])
    }

    @Test("emptyDirectoryContents on already-empty dir is a no-op")
    func emptyDirOnEmpty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sg-empty-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try SymbolGraphExtractor.emptyDirectoryContents(tmp) // should not throw
        #expect(FileManager.default.fileExists(atPath: tmp.path))
    }

    @Test("emptyDirectoryContents handles nested + multiple files")
    func emptyDirNested() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sg-nest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // 3 flat files + 1 subdir containing 1 file (`removeItem` is recursive
        // for directories on Apple FileManager, so this should work).
        try "1".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "2".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "3".write(to: tmp.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        let sub = tmp.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "4".write(to: sub.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).count == 4)

        try SymbolGraphExtractor.emptyDirectoryContents(tmp)

        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: tmp.path), "dir itself must remain")
    }
}
