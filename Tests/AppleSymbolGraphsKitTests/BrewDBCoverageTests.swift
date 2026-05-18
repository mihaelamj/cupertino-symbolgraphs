@testable import AppleSymbolGraphsKit
import Foundation
import Testing

/// **The completeness regression test.** Cross-references the
/// `FrameworkModuleMap` (curated ∪ knownNonExtractable) against the
/// authoritative list of framework slugs cupertino's apple-docs corpus
/// indexes (snapshotted from the brew-installed DB as a fixture).
///
/// If this test fails, it means one of:
/// 1. Cupertino's apple-docs corpus shipped a new framework we don't
///    yet route (real coverage gap — add to curated or knownNonExtractable).
/// 2. Someone deleted an entry from FrameworkModuleMap that we need
///    (regression — restore the entry).
///
/// Fixture update protocol: re-snapshot the brew DB framework list,
/// bump the fixture file's `-vX.Y.Z` suffix to match the cupertino
/// release the snapshot was taken from, update `fixtureFilename` below.
@Suite("Brew DB coverage — completeness regression")
struct BrewDBCoverageTests {
    /// Filename of the most-recent brew DB framework fixture this
    /// repo asserts coverage against.
    private static let fixtureFilename = "cupertino-brew-framework-slugs-v1.0.2.txt"

    /// Read the fixture from the Tests/Fixtures/ dir.
    /// Returns the sorted set of slug strings (one per non-comment line).
    private static func loadFixture() throws -> Set<String> {
        // SwiftPM doesn't bundle test resources unless declared in
        // Package.swift's testTarget(resources:). The fixture lives in
        // a known relative path from the package root; tests run from
        // that root, so a file path lookup works.
        let fixturePath = "Tests/AppleSymbolGraphsKitTests/Fixtures/\(fixtureFilename)"
        let url = URL(fileURLWithPath: fixturePath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        var slugs: Set<String> = []
        for line in raw.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            slugs.insert(t)
        }
        return slugs
    }

    @Test("Fixture loads and contains the expected slug count")
    func fixtureLoads() throws {
        let slugs = try Self.loadFixture()
        // v1.0.2 brew DB snapshot has 398 distinct framework slugs.
        #expect(slugs.count == 398, "fixture should have exactly 398 slugs; got \(slugs.count)")
        // Spot-check a few canonical entries are present (sanity, not exhaustive).
        for s in ["swiftui", "uikit", "foundation", "carekit", "addressbook"] {
            #expect(slugs.contains(s), "fixture missing canonical slug '\(s)'")
        }
    }

    @Test("EVERY brew DB slug is routed via curated or knownNonExtractable (100% coverage)")
    func everySlugRouted() throws {
        let brew = try Self.loadFixture()
        let curated = Set(FrameworkModuleMap.curated.keys)
        let nonExtractable = Set(FrameworkModuleMap.knownNonExtractable.keys)
        let covered = curated.union(nonExtractable)
        let uncovered = brew.subtracting(covered)
        #expect(uncovered.isEmpty,
                "\(uncovered.count) brew slug(s) NOT routed via either curated or knownNonExtractable: \(uncovered.sorted().prefix(20))")
    }

    @Test("curated covers Apple's main first-party Swift modules (the 'must have' subset)")
    func curatedHasMustHaves() throws {
        let brew = try Self.loadFixture()
        let curated = Set(FrameworkModuleMap.curated.keys)
        // These are slugs every Apple developer expects to be queryable.
        // They MUST be in curated (not just knownNonExtractable).
        let mustBeExtractable = [
            "swiftui", "uikit", "appkit", "foundation", "combine",
            "swiftdata", "storekit", "mapkit", "coredata", "coregraphics",
            "avfoundation", "metal", "realitykit", "arkit", "healthkit",
            "homekit", "watchkit", "cloudkit", "cryptokit", "security",
            "network", "networkextension", "weatherkit", "musickit",
            "charts", "observation",
        ]
        for slug in mustBeExtractable {
            #expect(brew.contains(slug), "fixture missing canonical slug '\(slug)' — fixture out of date?")
            #expect(curated.contains(slug), "canonical Apple slug '\(slug)' not in curated map (it's in brew DB → must be extractable)")
        }
    }

    @Test("knownNonExtractable doesn't shadow canonical Apple slugs")
    func nonExtractableDoesntShadowCanonical() throws {
        // Defensive: a contributor who accidentally moves SwiftUI into
        // knownNonExtractable would still pass the disjoint test (because
        // we'd remove it from curated). This catches the move regardless.
        let nonExtractable = Set(FrameworkModuleMap.knownNonExtractable.keys)
        let mustNotBeNonExtractable = ["swiftui", "uikit", "foundation", "combine", "appkit"]
        for slug in mustNotBeNonExtractable {
            #expect(!nonExtractable.contains(slug),
                    "canonical slug '\(slug)' was moved to knownNonExtractable — that's wrong, it's a real Swift module")
        }
    }

    @Test("Coverage stats are within expected v1.0.2-era bounds")
    func coverageStats() throws {
        let brew = try Self.loadFixture()
        let curated = Set(FrameworkModuleMap.curated.keys)
        let nonExtractable = Set(FrameworkModuleMap.knownNonExtractable.keys)
        let inCurated = brew.intersection(curated).count
        let inNonExtractable = brew.intersection(nonExtractable).count
        let total = brew.count
        let pct = Double(inCurated) * 100 / Double(total)
        // After the v1.0.2 brew completeness audit:
        //   ~265 curated (real Swift modules) of 398 brew = ~66%
        //   ~133 knownNonExtractable (REST APIs, JS, deprecated, docs, etc.) = ~33%
        // Both numbers should be ≥ floors; pct ≥ 50%.
        #expect(inCurated >= 250, "curated coverage of brew dropped: \(inCurated) (floor 250)")
        #expect(inNonExtractable >= 100, "knownNonExtractable coverage of brew dropped: \(inNonExtractable) (floor 100)")
        #expect(pct >= 50.0, "curated covers only \(pct)% of brew — should be ≥ 50%")
    }
}
